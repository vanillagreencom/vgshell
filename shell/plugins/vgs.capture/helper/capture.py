#!/usr/bin/env python3
"""Service.qml consumes JSON lines for action progress and completion.

An error's optional reason english-data-unavailable selects its notice title.

While an area is selected, one `cancel` line or stdin EOF ends the selection.
Screenshot selection emits selection-ended for focus restoration. Countdown
ticks report remaining seconds; countdown-hidden confirms its UI was removed.
For recording, one `stop` line or stdin EOF sends SIGINT to the owned recorder.
SIGTERM releases all owned children, including during service replacement.
"""
import json
import math
import ctypes
from contextlib import contextmanager
import io
import os
from pathlib import Path
import re
import select
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime


class CaptureFailure(RuntimeError):
    """Carry a classified tool failure to the service's existing error notice."""

    def __init__(self, reason, message):
        super().__init__(message)
        self.reason = reason


# hyprpicker freezes every output under the selector: -r freezes the outputs
# without the pointer, -z and -d draw no lens or colour preview into the frame
# the capture reads.
FREEZE = ["hyprpicker", "-r", "-z", "-d", "-q"]
# slurp's default wash, white at 25%, shows on a dark desktop where a dark dim
# does not: on host cachy on 2026-10-04 grim read DP-1's mean level 16 -> 76
# under the default and 14 -> 8 under -b #00000066.
SELECT = ["slurp"]
# slurp's own Escape answer, which is a cancel and not a failure.
SELECTION_CANCELLED = b"selection cancelled"
# Captures of the selection, scaled down, compared until two agree.
SETTLE_SCALE = "0.125"
SETTLE_TRIES = 40

# The CLI has no structured initialization error. --list-langs lists files,
# but cannot prove that a model loads. This fallback maps Tesseract's own
# init_tesseract diagnostic; the stand-in pins that upstream example.
OCR_FAILURES = (
    ("Failed loading language 'eng'", "english-data-unavailable",
     "English text recognition data is missing or cannot be read. Text capture is unavailable."),
)


class Capture:
    """Own every child until its exit, including cancellation and teardown."""

    def __init__(self):
        self.children = []
        self.recorder = None
        signal.signal(signal.SIGTERM, self.terminate)
        signal.signal(signal.SIGHUP, self.terminate)

    def spawn(self, argv, **kwargs):
        # A fresh interpreter sets the Linux parent-death signal before exec.
        # This needs no preexec_fn, which is unsafe in a threaded parent.
        stop = signal.SIGINT if argv[0] == "gpu-screen-recorder" else signal.SIGTERM
        # The worker's stdin is the service's control pipe, which stays open.
        # slurp reads boxes from a stdin that is not a terminal until EOF, so
        # an inherited pipe holds it before it maps any surface.
        kwargs.setdefault("stdin", subprocess.DEVNULL)
        child = subprocess.Popen([sys.executable, __file__, "--owned", str(int(stop)), str(os.getpid()), *argv], **kwargs)
        self.children.append(child)
        return child

    def run(self, argv, timeout=None, **kwargs):
        child = self.spawn(argv, **kwargs)
        try:
            stdout, stderr = child.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            child.kill()
            child.communicate()
            raise CaptureFailure("timeout", f"{argv[0]} exceeded its time limit") from None
        if child.returncode:
            detail = (stderr or b"").decode(errors="replace").strip()
            raise RuntimeError(f"{argv[0]} exited {child.returncode}: {detail}")
        return stdout

    def release(self):
        for child in self.children:
            if child.poll() is None:
                child.send_signal(signal.SIGINT if child is self.recorder else signal.SIGTERM)
        for child in self.children:
            if child.poll() is None:
                # A broken tool must not outlive the service which owns it.
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()

    def terminate(self, signum, frame):
        self.release()
        raise SystemExit(128 + signum)

    def stop(self, child):
        if child.poll() is None:
            child.terminate()
        child.wait()

    @contextmanager
    def selection(self, recording=False, request=None):
        """Yield the selected (geometry, groups) over a frozen screen, or None.

        The freeze lasts until the block ends, so a capture inside it reads
        the frame the user selected on.
        """
        freeze = self.spawn(FREEZE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        ended = False
        try:
            # A layer maps above the layers mapped before it. hyprpicker maps
            # within 4 ms (hyprctl layers poll, host cachy, 2026-10-04), and
            # slurp must map after it to stay on top and receive input.
            time.sleep(0.1)
            if freeze.poll() is not None:
                raise RuntimeError(f"hyprpicker exited {freeze.returncode}: {freeze.communicate()[1].decode(errors='replace').strip()}")
            boxes = None
            args = SELECT + (["-o"] if recording else [])
            if request is not None:
                action = request["action"]
                windows = sorted(request.get("windows", []), key=lambda r: (r["width"] * r["height"], r.get("focus", 0)))
                outputs = request.get("outputs", [])
                if action == "screenshot-window":
                    boxes = windows
                    args += ["-r"]
                elif action == "screenshot-display":
                    boxes = outputs
                    args += ["-r"]
                elif request.get("smart", True):
                    boxes = windows + outputs
                if action in ("screenshot-window", "screenshot-display") and not boxes:
                    raise CaptureFailure("no-targets", "No capture targets are available")
            picked = self.pick(args, boxes, notify=request is None)
            if picked is not None and request is not None:
                x, y, width, height = map(int, picked[1])
                if request["action"] == "screenshot-area" and request.get("smart", True) and width * height < 20:
                    choices = boxes
                    target = next((r for r in choices if r["x"] <= x < r["x"] + r["width"] and r["y"] <= y < r["y"] + r["height"]), None)
                    if target is None:
                        raise RuntimeError("No capture target contains the selected point")
                    picked = rectangle_geometry(target), tuple(str(target[k]) for k in ("x", "y", "width", "height"))
            if picked is not None:
                self.settle(picked[0], request.get("timeout", 10) if request is not None else None)
            if request is not None:
                emit("selection-ended")
                ended = True
            yield picked
        finally:
            self.stop(freeze)
            if request is not None and not ended:
                emit("selection-ended")

    def pick(self, argv, boxes=None, notify=True):
        if boxes is None:
            child = self.spawn(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        else:
            # slurp reads this owned rectangle stream to EOF before mapping.
            with tempfile.TemporaryFile() as source:
                source.write("".join(rectangle_geometry(r) + "\n" for r in boxes).encode())
                source.seek(0)
                child = self.spawn(argv, stdin=source, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        while child.poll() is None:
            ready, _, _ = select.select([sys.stdin], [], [], 0.05)
            if ready and sys.stdin.readline().strip() in ("", "cancel"):
                child.terminate()
                break
        out, err = child.communicate()
        geometry = out.decode().strip()
        err = err.strip()
        if child.returncode or not geometry:
            if err and err != SELECTION_CANCELLED:
                raise RuntimeError("slurp: " + err.decode(errors="replace"))
            if notify:
                emit("cancelled")
            return None
        match = re.fullmatch(r"(-?\d+),(-?\d+) ([1-9]\d*)x([1-9]\d*)", geometry)
        if match is None:
            raise RuntimeError("slurp returned invalid geometry")
        return geometry, match.groups()

    def settle(self, geometry, timeout=None, interval=0):
        # The compositor fades slurp's layer out after it exits. Over the
        # still freeze that fade is the only change, so two equal captures
        # mean it ended. A layer drawn above the freeze can keep changing;
        # the capture then proceeds after the last try.
        previous = None
        for _ in range(SETTLE_TRIES):
            if interval:
                ready, _, _ = select.select([sys.stdin], [], [], interval)
                if ready and sys.stdin.readline().strip() in ("", "cancel"):
                    return False
            frame = self.run(["grim", "-s", SETTLE_SCALE, "-t", "ppm", "-g", geometry, "-"], timeout=timeout, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if frame == previous:
                return True
            previous = frame
        return True

    def screenshot(self, request):
        request = {**request, "outputs": output_rectangles(request["outputs"])}
        delay = request.get("delay", 0)
        if type(delay) is not int or not 0 <= delay <= 60:
            raise CaptureFailure("invalid-delay", "Invalid screenshot delay")
        timeout = request.get("timeout", 10)
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or not 1 <= timeout <= 60:
            raise CaptureFailure("invalid-timeout", "Invalid screenshot time limit")
        processing = request.get("processing", "save-copy")
        if processing not in ("save-copy", "copy", "save"):
            raise CaptureFailure("invalid-processing", "Invalid screenshot processing choice")
        if request["action"] in ("screenshot-area", "screenshot-window", "screenshot-display"):
            with self.selection(request=request) as picked:
                if picked is None:
                    emit("cancelled")
                    return
                args = ["grim", "-g", picked[0]]
                if not delay:
                    path, child = self.deliver(request, args)
        else:
            if request["action"] == "screenshot-all":
                outputs = request.get("outputs", [])
                if not outputs:
                    raise CaptureFailure("no-targets", "No enabled displays are available")
                left = min(r["x"] for r in outputs)
                top = min(r["y"] for r in outputs)
                right = max(r["x"] + r["width"] for r in outputs)
                bottom = max(r["y"] + r["height"] for r in outputs)
                args = ["grim", "-g", f"{left},{top} {right - left}x{bottom - top}"]
            else:
                args = ["grim", "-o", request["output"]]
            if not delay:
                path, child = self.deliver(request, args)
        if delay:
            if not self.countdown(delay, timeout):
                emit("cancelled")
                return
            # Spaced samples cover presentation after the service removes its
            # countdown. Immediate equal samples can precede the next frame.
            outputs = request.get("outputs", [])
            geometry = args[2] if args[1] == "-g" else next((rectangle_geometry(r) for r in outputs if r.get("name") == request["output"]), None)
            if geometry is None:
                raise RuntimeError("The focused display has no capture rectangle")
            if not self.settle(geometry, timeout, interval=0.05):
                emit("cancelled")
                return
            path, child = self.deliver(request, args)
        if path is None:
            emit("copied")
        else:
            emit("saved", path=str(path))
        if child is not None:
            self.clipboard_exit(child)

    def countdown(self, delay, timeout):
        for remaining in range(delay, 0, -1):
            emit("countdown", remaining=remaining)
            deadline = time.monotonic() + 1
            while time.monotonic() < deadline:
                ready, _, _ = select.select([sys.stdin], [], [], max(0, deadline - time.monotonic()))
                if ready and sys.stdin.readline().strip() in ("", "cancel"):
                    return False
        emit("countdown", remaining=0)
        # The service replies after it removes the countdown surfaces.
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            ready, _, _ = select.select([sys.stdin], [], [], max(0, deadline - time.monotonic()))
            if ready:
                line = sys.stdin.readline().strip()
                if line in ("", "cancel"):
                    return False
                if line == "countdown-hidden":
                    return True
        raise CaptureFailure("timeout", "The screenshot countdown did not close")

    def deliver(self, request, args):
        args = args + (["-c"] if request.get("cursor", False) else [])
        processing = request.get("processing", "save-copy")
        if processing == "copy":
            with tempfile.TemporaryDirectory(prefix="vgs-screenshot-") as scratch:
                path = self.grab(request, args, Path(scratch))
                with path.open("rb") as image:
                    child = self.copy(image, "image/png")
            return None, child
        path = self.grab(request, args)
        child = None
        if processing != "save":
            try:
                with path.open("rb") as image:
                    child = self.copy(image, "image/png")
            except (OSError, RuntimeError) as error:
                raise RuntimeError(f"Screenshot saved to {path}; clipboard failed: {error}") from error
        return path, child

    def grab(self, request, args, folder=None):
        if folder is None:
            folder = capture_folder(request["folder"], "PICTURES", "Screenshots")
        path = new_file(folder, "screenshot", ".png")
        try:
            self.run(args + [str(path)], timeout=request.get("timeout", 10), stderr=subprocess.PIPE)
            if path.stat().st_size == 0:
                raise RuntimeError("grim wrote no image")
        except BaseException:
            path.unlink(missing_ok=True)
            raise
        return path

    def text(self):
        with self.selection() as picked:
            if picked is None:
                return
            image = self.run(["grim", "-g", picked[0], "-"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        reader = self.spawn(["tesseract", "stdin", "stdout", "--oem", "1", "--psm", "6", "-l", "eng", "--dpi", "300"],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        text, err = reader.communicate(image)
        if reader.returncode:
            detail = err.decode(errors="replace").strip()
            for pattern, reason, message in OCR_FAILURES:
                if pattern in detail:
                    raise CaptureFailure(reason, message)
            raise RuntimeError("tesseract: " + detail)
        if not text.strip():
            raise RuntimeError("No text found in the selected area")
        child = self.copy(io.BytesIO(text.rstrip(b"\r\n")), "text/plain;charset=utf-8")
        emit("copied")
        self.clipboard_exit(child)

    def copy(self, source, mime):
        child = self.spawn(["wl-copy", "--foreground", "--type", mime], stdin=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            shutil.copyfileobj(source, child.stdin)
            child.stdin.close()
        except BrokenPipeError:
            child.stdin = None
            raise RuntimeError("wl-copy: " + child.communicate()[1].decode(errors="replace").strip()) from None
        child.stdin = None
        if child.poll() not in (None, 0):
            raise RuntimeError("wl-copy: " + child.communicate()[1].decode(errors="replace").strip())
        return child

    def clipboard_exit(self, child):
        # Wayland needs this foreground provider until another copy replaces
        # it. The service can start another job while this worker stays owned.
        _, error = child.communicate()
        if child.returncode:
            raise RuntimeError("wl-copy: " + error.decode(errors="replace").strip())

    def record(self, request):
        with self.selection(recording=True) as picked:
            if picked is None:
                return
        x, y, width, height = picked[1]
        folder = capture_folder(request["recordFolder"], "VIDEOS", "Screencasts")
        path = new_file(folder, "screencast", ".mp4")
        # The recorder takes slurp's logical layout coordinates unchanged.
        args = ["gpu-screen-recorder", "-w", "region", "-region", f"{width}x{height}+{x}+{y}", "-k", "auto", "-f", "60", "-o", str(path)]
        if request["audio"] != "none":
            audio = {"desktop": "default_output", "microphone": "default_input", "both": "default_output|default_input"}[request["audio"]]
            args += ["-a", audio, "-ac", "aac"]
        try:
            self.recorder = self.spawn(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=sys.stderr)
        except OSError:
            path.unlink(missing_ok=True)
            raise
        # The reserved file starts empty. Publish recording only after the
        # recorder writes it, so an encoding failure never shows a live icon.
        while self.recorder.poll() is None and path.stat().st_size == 0:
            select.select([], [], [], 0.01)
        if self.recorder.poll() is not None:
            path.unlink(missing_ok=True)
            raise RuntimeError(f"Recording failed to start (exit {self.recorder.returncode})")
        emit("recording", path=str(path))
        stopping = False
        while self.recorder.poll() is None:
            # stdin carries stop; the short wait also observes a recorder crash.
            ready, _, _ = select.select([sys.stdin], [], [], 0.1)
            if ready:
                line = sys.stdin.readline()
                if line == "" or line.strip() == "stop":
                    self.recorder.send_signal(signal.SIGINT)
                    stopping = True
                    try:
                        self.recorder.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        raise RuntimeError("The recorder did not stop; the video may be incomplete")
                    break
        if not stopping or self.recorder.returncode not in (0, -signal.SIGINT) or path.stat().st_size == 0:
            if path.stat().st_size == 0:
                path.unlink()
            raise RuntimeError(f"Recording failed (exit {self.recorder.returncode})")
        emit("saved", path=str(path))


def emit(event, **fields):
    """Publish one event to the owning service, without captured text."""
    print(json.dumps({"event": event, **fields}), flush=True)


def output_rectangles(outputs):
    rectangles = []
    for output in outputs:
        width = int(output["width"] / output["scale"])
        height = int(output["height"] / output["scale"])
        if output["transform"] in (1, 3, 5, 7):
            width, height = height, width
        rectangles.append({"name": output["name"], "x": output["x"], "y": output["y"], "width": width, "height": height})
    return rectangles


def rectangle_geometry(rectangle):
    return f'{rectangle["x"]},{rectangle["y"]} {rectangle["width"]}x{rectangle["height"]}'


def capture_folder(setting, kind, leaf):
    """Read the XDG user directory as data, never as executable shell code."""
    home = Path.home()
    if setting:
        folder = Path(os.path.expanduser(setting))
        if not folder.is_absolute():
            raise RuntimeError("Choose an absolute capture folder")
    else:
        folder = home / ("Pictures" if kind == "PICTURES" else "Videos")
        config = Path(os.environ.get("XDG_CONFIG_HOME", str(home / ".config"))) / "user-dirs.dirs"
        if config.exists():
            for line in config.read_text().splitlines():
                if not line.startswith(f"XDG_{kind}_DIR="):
                    continue
                values = shlex.split(line.split("=", 1)[1], comments=True)
                if len(values) != 1:
                    raise RuntimeError(f"Invalid XDG {kind.lower()} directory")
                folder = Path(values[0].replace("${HOME}", str(home)).replace("$HOME", str(home)))
                if not folder.is_absolute():
                    raise RuntimeError(f"Invalid XDG {kind.lower()} directory")
                break
        folder /= leaf
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def new_file(folder, prefix, suffix):
    """Reserve a distinct private name even for simultaneous captures."""
    stamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    fd, name = tempfile.mkstemp(prefix=f"{prefix}-{stamp}-", suffix=suffix, dir=folder)
    os.close(fd)
    return Path(name)


def main():
    request = json.loads(sys.argv[1])
    capture = Capture()
    try:
        match request["action"]:
            case "screenshot" | "screenshot-area" | "screenshot-window" | "screenshot-display" | "screenshot-all":
                capture.screenshot(request)
            case "text":
                capture.text()
            case "record":
                capture.record(request)
            case other:
                raise RuntimeError(f"Unknown capture action: {other}")
        return 0
    except CaptureFailure as error:
        emit("error", reason=error.reason, message=str(error))
        return 1
    except (OSError, ValueError, RuntimeError) as error:
        emit("error", message=str(error))
        return 1
    finally:
        capture.release()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--owned":
        stop, parent = int(sys.argv[2]), int(sys.argv[3])
        libc = ctypes.CDLL(None, use_errno=True)
        # PR_SET_PDEATHSIG is Linux prctl option 1. It survives an ordinary
        # exec. Check the parent again to close the fork-to-prctl race.
        if libc.prctl(1, stop, 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), "Cannot own capture tool lifetime")
        if os.getppid() != parent:
            os.kill(os.getpid(), stop)
            sys.exit(128 + stop)
        os.execvpe(sys.argv[4], sys.argv[4:], os.environ)
    sys.exit(main())
