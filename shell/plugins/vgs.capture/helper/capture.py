#!/usr/bin/env python3
"""Service.qml consumes JSON lines for action progress and completion.

An error's optional reason language-data-unavailable selects its notice title.

While an area is selected, and until a screenshot's file is written, one
`cancel` line or stdin EOF ends the capture with no file and emits cancelled.
A selection with a request emits selection-ended for focus restoration.
Countdown ticks report remaining seconds; countdown-hidden confirms its UI was
removed. Until the recorder writes its file, `cancel` or stdin EOF ends it with
no file; then one `stop` line or stdin EOF sends SIGINT to the owned recorder.
A recording emits stopped once the recorder ends, so the service can start the
next capture while this worker post-processes, then saved.
saved carries `actions`, its notification's buttons: one `{id, label, argv}`
for each program that opens the file and is installed; `default` opens it.
probe emits the offered audio sources and cameras and the missing languages.
SIGTERM releases all owned children, including during service replacement.
"""
import fcntl
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
import stat
import subprocess
import sys
import tempfile
import time
from datetime import datetime


class CaptureCancelled(Exception):
    """End a capture the service cancelled after its selection ended."""


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
# Each selecting action's mode: the boxes slurp offers. An area offers
# windows and outputs while smart selection is on.
SELECTION_MODES = {
    "screenshot-area": "area", "record": "area",
    "screenshot-window": "window", "record-window": "window",
    "screenshot-display": "display", "record-display": "display",
}
# slurp's own Escape answer, which is a cancel and not a failure.
SELECTION_CANCELLED = b"selection cancelled"
# Captures of the selection, scaled down, compared until two agree.
SETTLE_SCALE = "0.125"
SETTLE_TRIES = 40

# The CLI has no structured initialization error. --list-langs lists files,
# but cannot prove that a model loads. This fallback maps Tesseract's own
# init_tesseract diagnostic; the stand-in pins that upstream example.
OCR_FAILURES = (
    (re.compile(r"Failed loading language '([^']*)'"), "language-data-unavailable",
     "Text recognition data for {0} is missing or cannot be read. Text capture is unavailable."),
)
# Tesseract's -l: language codes joined by +, such as eng+deu or chi_sim.
LANGUAGES = re.compile(r"[A-Za-z_]+(\+[A-Za-z_]+)*")
AUDIO = {"desktop": "default_output", "microphone": "default_input", "both": "default_output|default_input"}
# gpu-screen-recorder's camera overlay, placed as v1 placed it.
WEBCAM = ";x=74%;y=69%;width=22%;height=22%;camera_fps=30"
# The hidden post-process output beside a recording; a later recording start
# removes one no live worker holds.
PROCESSING_PREFIX = ".screencast-processing-"
# Status choices: PluginLogic's STATUS_LIST_MAX items, labels of at most
# STATUS_LABEL_MAX characters.
CHOICES_MAX = 32
CHOICE_LABEL_MAX = 60
# The failure notice shows this much of the recorder log's end; the service
# cuts a notice message at 200 characters.
LOG_TAIL_LINES = 4
LOG_TAIL_CHARS = 140
LOG_TAIL_READ = 4096
# gpu-screen-recorder's exit status when the user cancels the portal picker.
PORTAL_CANCELLED = 60


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

    def cancelled(self, timeout=0):
        """Whether a `cancel` line or stdin EOF arrives within TIMEOUT seconds."""
        ready, _, _ = select.select([sys.stdin], [], [], timeout)
        return bool(ready) and sys.stdin.readline().strip() in ("", "cancel")

    @contextmanager
    def selection(self, request=None):
        """Yield the selected (geometry, groups) over a frozen screen, or None.

        The freeze lasts until the block ends, so a capture inside it reads
        the frame the user selected on. The request's action names the mode
        of SELECTION_MODES; without a request slurp offers no boxes.
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
            args = list(SELECT)
            mode = None
            if request is not None:
                mode = SELECTION_MODES[request["action"]]
                windows = sorted(request.get("windows", []), key=lambda r: (r["width"] * r["height"], r.get("focus", 0)))
                outputs = request.get("outputs", [])
                if mode == "window":
                    boxes = windows
                    args += ["-r"]
                elif mode == "display":
                    boxes = outputs
                    args += ["-r"]
                elif request.get("smart", True):
                    boxes = windows + outputs
                elif request["action"] == "record":
                    # slurp offers each output itself.
                    args += ["-o"]
                if mode in ("window", "display") and not boxes:
                    raise CaptureFailure("no-targets", "No capture targets are available")
            picked = self.pick(args, boxes, notify=request is None)
            if picked is not None and request is not None:
                x, y, width, height = map(int, picked[1])
                if mode == "area" and request.get("smart", True) and width * height < 20:
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
        cancelled = False
        while child.poll() is None:
            if self.cancelled(0.05):
                cancelled = True
                child.terminate()
                break
        out, err = child.communicate()
        geometry = out.decode().strip()
        err = err.strip()
        # A cancel read as slurp answers wins over the geometry it printed.
        if cancelled or child.returncode or not geometry:
            if not cancelled and err and err != SELECTION_CANCELLED:
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
            if self.cancelled(interval):
                raise CaptureCancelled()
            frame = self.run(["grim", "-s", SETTLE_SCALE, "-t", "ppm", "-g", geometry, "-"], timeout=timeout, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if frame == previous:
                return
            previous = frame

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
            self.settle(geometry, timeout, interval=0.05)
            path, child = self.deliver(request, args)
        if path is None:
            emit("copied")
        else:
            emit("saved", path=str(path), actions=actions(request, path, (("default", "Open", "viewer"), ("edit", "Edit", "editor"))))
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
            if self.cancelled():
                raise CaptureCancelled()
        except BaseException:
            path.unlink(missing_ok=True)
            raise
        return path

    def text(self, request):
        languages = request.get("ocrLanguages", "eng")
        if not isinstance(languages, str) or not LANGUAGES.fullmatch(languages):
            raise CaptureFailure("invalid-languages", "Invalid text recognition languages")
        with self.selection() as picked:
            if picked is None:
                return
            image = self.run(["grim", "-g", picked[0], "-"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        reader = self.spawn(["tesseract", "stdin", "stdout", "--oem", "1", "--psm", "6", "-l", languages, "--dpi", "300", "-c", "preserve_interword_spaces=1"],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        text, err = reader.communicate(image)
        if reader.returncode:
            detail = err.decode(errors="replace").strip()
            for pattern, reason, message in OCR_FAILURES:
                found = pattern.search(detail)
                if found is not None:
                    raise CaptureFailure(reason, message.format(*found.groups()))
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
        request = {**request, "outputs": output_rectangles(request["outputs"])}
        options = recorder_options(request)
        devices = None
        if request["webcam"] or any(not item["source"] for item in request["audioSources"]):
            devices = self.devices()
        camera = None
        if request["webcam"]:
            cameras = [choice["value"] for choice in devices["cameras"]]
            if not cameras:
                raise CaptureFailure("camera-unavailable", "No camera is connected")
            camera = request["webcamDevice"] or cameras[0]
            if camera not in cameras:
                raise CaptureFailure("camera-unavailable", "The chosen camera is not connected")
        audio = recorder_audio(request, devices)
        region = None
        if request["action"] == "record-portal":
            # The recorder opens the desktop portal's own picker.
            target = "portal"
        elif request["action"] == "record-output":
            target = request["output"]
        else:
            with self.selection(request=request) as picked:
                if picked is None:
                    emit("cancelled")
                    return
            x, y, width, height = map(int, picked[1])
            # The recorder takes slurp's logical layout coordinates unchanged.
            # A box equal to an output records that output whole.
            target = next((r["name"] for r in request["outputs"] if (r["x"], r["y"], r["width"], r["height"]) == (x, y, width, height)), None)
            if target is None:
                target, region = "region", f"{width}x{height}+{x}+{y}"
        if camera is not None:
            target += "|v4l2:" + camera + WEBCAM
        state = plugin_state(request["stateDir"])
        folder = capture_folder(request["recordFolder"], "VIDEOS", "Screencasts")
        remove_stale_processing(folder)
        path = new_file(folder, "screencast", ".mp4")
        args = ["gpu-screen-recorder", "-w", target, *(["-region", region] if region else []), *options, *audio, "-o", str(path)]
        with open_log(state / "recorder.log") as log:
            try:
                self.recorder = self.spawn(args, stdin=subprocess.DEVNULL, stdout=log, stderr=log)
            except OSError:
                path.unlink(missing_ok=True)
                raise
            # The reserved file starts empty. Publish recording only after the
            # recorder writes it, so an encoding failure never shows a live
            # icon. The portal's picker can stay open here, so a second press
            # or stdin EOF cancels it; a stop that meets a written file stops.
            line = None
            while self.recorder.poll() is None and path.stat().st_size == 0:
                ready, _, _ = select.select([sys.stdin], [], [], 0.01)
                if ready:
                    line = sys.stdin.readline().strip()
                    if line in ("", "cancel") or path.stat().st_size == 0:
                        self.end_recorder()
                        path.unlink(missing_ok=True)
                        emit("cancelled")
                        return
                    break
            if self.recorder.poll() is not None:
                path.unlink(missing_ok=True)
                if target.startswith("portal") and self.recorder.returncode == PORTAL_CANCELLED:
                    emit("cancelled")
                    return
                raise RuntimeError(f"Recording failed to start (exit {self.recorder.returncode})" + log_tail(log))
            emit("recording", path=str(path))
            stopping = False
            while self.recorder.poll() is None:
                # stdin carries stop; the short wait also observes a recorder crash.
                if line != "stop":
                    ready, _, _ = select.select([sys.stdin], [], [], 0.1)
                    if not ready:
                        continue
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
                raise RuntimeError(f"Recording failed (exit {self.recorder.returncode})" + log_tail(log))
            emit("stopped", path=str(path))
            processing = "off"
            if request["postProcess"]:
                processing = "done" if self.postprocess(path, bool(audio), log) else "failed"
            thumbnail = self.thumbnail(path, state, log)
            detail = log_tail(log).strip() if processing == "failed" else ""
        try:
            child = self.copy(io.BytesIO((path.as_uri() + "\r\n").encode()), "text/uri-list")
        except (OSError, RuntimeError) as error:
            raise RuntimeError(f"Recording saved to {path}; clipboard failed: {error}") from error
        emit("saved", path=str(path), thumbnail=thumbnail, processing=processing, detail=detail,
             actions=actions(request, path, (("default", "Open", "player"),)))
        self.clipboard_exit(child)

    def wait(self, child):
        """Wait for a child in short polls, so SIGTERM's release can reap it."""
        while child.poll() is None:
            select.select([], [], [], 0.1)
        return child.returncode

    def end_recorder(self):
        """Stop a recorder that never wrote its file; it saves nothing."""
        self.recorder.send_signal(signal.SIGINT)
        try:
            self.recorder.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.recorder.kill()
            self.recorder.wait()

    def postprocess(self, path, audio, log):
        """Trim the first 0.1 s and normalize loudness; True once PATH holds it.

        The output replaces PATH by one rename on the same filesystem only
        after ffmpeg succeeds, so any other end keeps the recording whole.
        """
        fd, name = tempfile.mkstemp(prefix=PROCESSING_PREFIX, suffix=path.suffix, dir=path.parent)
        temp = Path(name)
        try:
            # The lock marks this output live for remove_stale_processing.
            fcntl.flock(fd, fcntl.LOCK_EX)
            args = ["ffmpeg", "-hide_banner", "-loglevel", "warning", "-y", "-ss", "0.1", "-i", str(path), "-map", "0:v:0"]
            if audio:
                # loudnorm resamples to 192 kHz; AAC takes at most 96 kHz.
                args += ["-map", "0:a?", "-c:v", "copy", "-af", "loudnorm=I=-14:TP=-1.5:LRA=11", "-ar", "48000", "-c:a", "aac", "-b:a", "192k"]
            else:
                args += ["-c:v", "copy", "-an"]
            child = self.spawn(args + [str(temp)], stdout=log, stderr=log)
            code = self.wait(child)
            if code or temp.stat().st_size == 0:
                return False
            os.replace(temp, path)
            return True
        finally:
            temp.unlink(missing_ok=True)
            os.close(fd)

    def thumbnail(self, path, state, log):
        """One frame of the recording as a JPEG, or "" when none was made."""
        folder = state / "thumbnails"
        folder.mkdir(mode=0o700, exist_ok=True)
        thumbnail = folder / (path.stem + ".jpg")
        child = self.spawn(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-ss", "1", "-i", str(path), "-frames:v", "1", str(thumbnail)],
                           stdout=log, stderr=log)
        if self.wait(child) == 0 and thumbnail.is_file() and thumbnail.stat().st_size > 0:
            return str(thumbnail)
        thumbnail.unlink(missing_ok=True)
        return ""

    def devices(self):
        """The audio sources and cameras PipeWire offers, as status choices."""
        nodes = json.loads(self.run(["pw-dump"], timeout=10, stdout=subprocess.PIPE, stderr=subprocess.PIPE))
        audio, cameras = [], []
        for node in nodes:
            if not isinstance(node, dict) or node.get("type") != "PipeWire:Interface:Node":
                continue
            props = (node.get("info") or {}).get("props") or {}
            kind, name = props.get("media.class"), props.get("node.name")
            label = props.get("node.description") or props.get("node.nick") or name
            if kind == "Audio/Source" and name:
                audio.append((label, "device:" + name))
            elif kind == "Audio/Sink" and name:
                # The recorder reads a sink's sound through its monitor source.
                audio.append(("Monitor of " + str(label), "device:" + name + ".monitor"))
            elif kind == "Video/Source" and props.get("api.v4l2.path"):
                cameras.append((label or props["api.v4l2.path"], props["api.v4l2.path"]))
        return {"audioSources": choices(audio), "cameras": choices(cameras)}

    def languages(self):
        """The language codes Tesseract lists as installed."""
        listing = self.run(["tesseract", "--list-langs"], timeout=10, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        # The first line names the data folder; one code follows per line.
        return [line.strip() for line in listing.decode(errors="replace").splitlines()[1:] if line.strip()]

    def probe(self, request):
        try:
            devices = self.devices()
        except (OSError, ValueError, RuntimeError) as error:
            devices = {"error": str(error)}
        languages = request.get("ocrLanguages", "eng")
        if not isinstance(languages, str) or not LANGUAGES.fullmatch(languages):
            report = {"invalid": True}
        else:
            try:
                installed = self.languages()
            except (OSError, RuntimeError) as error:
                report = {"error": str(error)}
            else:
                report = {"missing": [code for code in dict.fromkeys(languages.split("+")) if code not in installed]}
        emit("probe", devices=devices, languages=report)


def emit(event, **fields):
    """Publish one event to the owning service, without captured text."""
    print(json.dumps({"event": event, **fields}), flush=True)


def choices(pairs):
    """Distinct printable (label, value) pairs as status choices, bounded."""
    out, seen = [], set()
    for label, value in pairs:
        label = str(label)[:CHOICE_LABEL_MAX]
        if not label.isprintable() or not label.strip() or not value.isprintable() or value in seen:
            continue
        seen.add(value)
        out.append({"label": label, "value": value})
    return out[:CHOICES_MAX]


def recorder_options(request):
    rate = request["frameRate"]
    if isinstance(rate, bool) or not isinstance(rate, (int, float)) or not math.isfinite(rate) or rate != int(rate) or not 1 <= rate <= 240:
        raise CaptureFailure("invalid-frame-rate", "Invalid recording frame rate")
    return ["-f", str(int(rate)), "-k", request["codec"], "-q", request["quality"],
            "-fm", "cfr" if request["constantFrameRate"] else "vfr",
            "-cursor", "yes" if request["recordCursor"] else "no"]


def recorder_audio(request, devices):
    """One -a per source: the audio choice, then each listed source."""
    sources = [] if request["audio"] == "none" else [AUDIO[request["audio"]]]
    for item in request["audioSources"]:
        source = item["source"]
        if not source:
            # Empty is the first offered source.
            if not devices["audioSources"]:
                raise CaptureFailure("audio-unavailable", "No audio source is available to record")
            source = devices["audioSources"][0]["value"]
        sources.append(source)
    args = [arg for source in sources for arg in ("-a", source)]
    return args + (["-ac", "aac"] if args else [])


def open_with(setting, path):
    """The argv that opens PATH with SETTING, the command a setting names, or
    None when its program is not installed.

    The command splits on white space and no shell reads it. Each word that is
    exactly %f, the Desktop Entry field code, becomes PATH as one argument;
    with none, PATH is the last argument.
    """
    words = setting.split()
    if not words or shutil.which(words[0]) is None:
        return None
    if "%f" not in words:
        return [*words, str(path)]
    return [str(path) if word == "%f" else word for word in words]


def actions(request, path, offered):
    """The notification buttons for PATH: each (id, label, setting) of OFFERED
    whose setting names an installed program."""
    out = []
    for action_id, label, setting in offered:
        argv = open_with(request[setting], path)
        if argv is not None:
            out.append({"id": action_id, "label": label, "argv": argv})
    return out


def plugin_state(state_dir):
    """The plugin's private state folder: the recorder log and thumbnails."""
    folder = Path(state_dir) / "plugins/vgs.capture"
    if not folder.is_absolute():
        raise RuntimeError("Invalid capture state folder")
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(folder, 0o700)
    return folder


@contextmanager
def open_log(path):
    """This recording's own owner-only log; every writer appends to its end.

    A recording that starts while an earlier one post-processes replaces the
    name, and the earlier worker keeps writing and reading its own file.
    """
    path.unlink(missing_ok=True)
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_APPEND | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "r+b") as log:
        yield log


def log_tail(log):
    """The end of this recording's log on a new line, or "" for an empty log."""
    fd = log.fileno()
    size = os.fstat(fd).st_size
    text = os.pread(fd, LOG_TAIL_READ, max(0, size - LOG_TAIL_READ)).decode(errors="replace")
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    tail = "\n".join(lines[-LOG_TAIL_LINES:])[-LOG_TAIL_CHARS:]
    return "\n" + tail if tail else ""


def remove_stale_processing(folder):
    """Remove post-process outputs that no live worker holds locked."""
    for temp in folder.glob(PROCESSING_PREFIX + "*"):
        try:
            fd = os.open(temp, os.O_RDONLY | os.O_NOFOLLOW)
        except OSError:
            continue
        try:
            if not stat.S_ISREG(os.fstat(fd).st_mode):
                continue
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            temp.unlink(missing_ok=True)
        except BlockingIOError:
            continue
        finally:
            os.close(fd)


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
                capture.text(request)
            case "record" | "record-window" | "record-display" | "record-output" | "record-portal":
                capture.record(request)
            case "probe":
                capture.probe(request)
            case other:
                raise RuntimeError(f"Unknown capture action: {other}")
        return 0
    except CaptureCancelled:
        emit("cancelled")
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
