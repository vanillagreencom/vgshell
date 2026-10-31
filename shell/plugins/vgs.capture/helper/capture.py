#!/usr/bin/env python3
"""Service.qml consumes JSON lines for action progress and completion.

An error's optional reason language-data-unavailable selects its notice title.

While an area is selected, and until a screenshot's file is written, one
`cancel` line or stdin EOF ends the capture with no file and emits cancelled.
A selection with a request emits selection-ended for focus restoration.
Countdown ticks report remaining seconds; countdown-hidden confirms its UI was
removed. Until the recorder writes its file, `cancel` or stdin EOF ends it with
no file; then one `stop` line or stdin EOF sends SIGINT to the owned recorder.
A recording emits stopped once the recorder ends, then saved after processing.
saved carries `actions`, its notification's buttons: one `{id, label, argv}`
for each program that opens the file and is installed; `default` opens it.
probe emits the offered audio sources and cameras and the missing languages.
SIGTERM releases all owned children, including during service replacement.
After a copied result, this process becomes wl-copy --foreground; only that
clipboard provider stays alive until another copy replaces it.

--notify reads one JSON request, then close or EOF on stdin. Its resident
notification emits ready, action, closed and error JSON lines until closed.
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
# How long hyprpicker may take to map its layer on every output before the
# freeze counts as failed.
FREEZE_TIMEOUT = 10
# How long one grim run, and the service's answer that its countdown left the
# screen, may take before the screenshot counts as failed. It is the default
# of the setting this replaced, and FREEZE_TIMEOUT's bound for the same kind
# of wait: a tool or a reply that hangs. No measured grim time sets it.
CAPTURE_TIMEOUT = 10
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

# Nix substitutes these constants in its existing install phase.
NOTICE_GIO_LIBRARY = "libgio-2.0.so.0"
NOTICE_GOBJECT_LIBRARY = "libgobject-2.0.so.0"
NOTICE_GLIB_LIBRARY = "libglib-2.0.so.0"

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
        deadline = time.monotonic() + 4
        for child in self.children:
            if child.poll() is None:
                child.send_signal(signal.SIGINT if child is self.recorder else signal.SIGTERM)
        for child in self.children:
            if child.poll() is None:
                # A broken tool must not outlive the service which owns it.
                try:
                    child.wait(timeout=max(0, deadline - time.monotonic()))
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
            self.frozen(freeze)
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
                self.settle(picked[0], CAPTURE_TIMEOUT if request is not None else None)
            if request is not None:
                emit("selection-ended")
                ended = True
            yield picked
        finally:
            self.stop(freeze)
            if request is not None and not ended:
                emit("selection-ended")

    def frozen(self, freeze):
        """Return once FREEZE's layer is mapped on every output.

        A layer maps above the layers mapped before it, so slurp must map
        after the freeze to stay on top and receive input. hyprpicker maps
        within 4 ms (hyprctl layers poll, host cachy, 2026-10-04), but a
        loaded machine can delay both its map and its failure, so only
        Hyprland's layer list or hyprpicker's exit decides. Hyprland 0.56.2
        lists a layer from its creation, before hyprpicker's screencopy can
        still fail; its `alpha`, the fade's goal, is 0 until the layer maps
        (HyprCtl.cpp layersRequest, LayerSurface.cpp onMap).
        """
        deadline = time.monotonic() + FREEZE_TIMEOUT
        while (left := deadline - time.monotonic()) > 0:
            outputs = json.loads(self.run(["hyprctl", "-j", "layers"], timeout=left, stdout=subprocess.PIPE, stderr=subprocess.PIPE))
            # Read after the layers, so a freeze that mapped and then exited
            # is a failure.
            if freeze.poll() is not None:
                raise RuntimeError(f"hyprpicker exited {freeze.returncode}: {freeze.communicate()[1].decode(errors='replace').strip()}")
            if outputs and all(any(layer["pid"] == freeze.pid and layer["alpha"] > 0 for layers in output["levels"].values() for layer in layers)
                               for output in outputs.values()):
                return
            time.sleep(0.05)
        raise CaptureFailure("timeout", "hyprpicker did not freeze the screen")

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

    def settle(self, geometry, timeout=None):
        # The compositor fades slurp's layer out after it exits. Over the
        # still freeze that fade is the only change, so two equal captures
        # mean it ended. A layer drawn above the freeze can keep changing;
        # the capture then proceeds after the last try.
        previous = None
        for _ in range(SETTLE_TRIES):
            if self.cancelled():
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
            if not self.countdown(delay):
                emit("cancelled")
                return
            path, child = self.deliver(request, args)
        if path is None:
            emit("copied")
        else:
            emit("saved", path=str(path), actions=actions(request, path, (("default", "Open", "viewer"), ("edit", "Edit", "editor"))))
        if child is not None:
            self.clipboard_exit(child)

    def countdown(self, delay):
        for remaining in range(delay, 0, -1):
            emit("countdown", remaining=remaining)
            deadline = time.monotonic() + 1
            while time.monotonic() < deadline:
                ready, _, _ = select.select([sys.stdin], [], [], max(0, deadline - time.monotonic()))
                if ready and sys.stdin.readline().strip() in ("", "cancel"):
                    return False
        emit("countdown", remaining=0)
        # The service replies after it removes the countdown surfaces.
        deadline = time.monotonic() + CAPTURE_TIMEOUT
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
            self.run(args + [str(path)], timeout=CAPTURE_TIMEOUT, stderr=subprocess.PIPE)
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
        if shutil.which("wl-copy") is None:
            raise RuntimeError("wl-copy is unavailable")
        clipboard = tempfile.TemporaryFile()
        try:
            shutil.copyfileobj(source, clipboard)
            clipboard.seek(0)
        except BaseException:
            clipboard.close()
            raise
        return clipboard, mime

    def clipboard_exit(self, child):
        # exec preserves the service's managed PID/group while removing the
        # Python helper. dup2 makes only the staged clipboard stdin inheritable
        # (Python os.execvpe/os.dup2 documentation); no control pipe survives.
        clipboard, mime = child
        with clipboard:
            self.release()
            os.dup2(clipboard.fileno(), sys.stdin.fileno())
        os.execvpe("wl-copy", ["wl-copy", "--foreground", "--type", mime], os.environ)

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
             actions=actions(request, path, (("default", "Open", "player"), ("show", "Show", "browser"))))
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


class NoticeError(ctypes.Structure):
    _fields_ = [("domain", ctypes.c_uint), ("code", ctypes.c_int), ("message", ctypes.c_char_p)]


class CaptureNotice:
    """One managed notification run owns its bus reference and native callbacks."""

    destination = b"org.freedesktop.Notifications"
    object_path = b"/org/freedesktop/Notifications"
    cleanup_ms = 4000  # Capture.release's existing shared cleanup allowance.

    def __init__(self, request, control):
        self.request, self.control = request, control
        self.gio = ctypes.CDLL(NOTICE_GIO_LIBRARY)
        self.object = ctypes.CDLL(NOTICE_GOBJECT_LIBRARY)
        self.glib = ctypes.CDLL(NOTICE_GLIB_LIBRARY)
        pointer, string, integer, unsigned = ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_uint
        self.async_type = ctypes.CFUNCTYPE(None, pointer, pointer, pointer)
        self.signal_type = ctypes.CFUNCTYPE(None, pointer, string, string, string, string, pointer, pointer)
        self.destroy_type = ctypes.CFUNCTYPE(None, pointer)
        self.source_type = ctypes.CFUNCTYPE(integer, pointer)
        self.fd_type = ctypes.CFUNCTYPE(integer, integer, integer, pointer)
        self.appeared_type = ctypes.CFUNCTYPE(None, pointer, string, string, pointer)
        self.vanished_type = ctypes.CFUNCTYPE(None, pointer, string, pointer)
        self.closed_type = ctypes.CFUNCTYPE(None, pointer, integer, pointer, pointer)
        self.bind(self.glib, {
            "g_main_loop_new": (pointer, [pointer, integer]), "g_main_loop_run": (None, [pointer]),
            "g_main_loop_quit": (None, [pointer]), "g_main_loop_unref": (None, [pointer]),
            "g_timeout_add": (unsigned, [unsigned, self.source_type, pointer]),
            "g_unix_signal_add": (unsigned, [integer, self.source_type, pointer]),
            "g_unix_fd_add": (unsigned, [integer, integer, self.fd_type, pointer]),
            "g_source_remove": (integer, [unsigned]), "g_error_free": (None, [pointer]),
            "g_variant_type_new": (pointer, [string]), "g_variant_type_free": (None, [pointer]),
            "g_variant_new_string": (pointer, [string]), "g_variant_new_uint32": (pointer, [ctypes.c_uint32]),
            "g_variant_new_int32": (pointer, [ctypes.c_int32]), "g_variant_new_boolean": (pointer, [integer]),
            "g_variant_new_variant": (pointer, [pointer]),
            "g_variant_new_array": (pointer, [pointer, ctypes.POINTER(pointer), ctypes.c_size_t]),
            "g_variant_new_tuple": (pointer, [ctypes.POINTER(pointer), ctypes.c_size_t]),
            "g_variant_new_dict_entry": (pointer, [pointer, pointer]), "g_variant_unref": (None, [pointer]),
            "g_variant_is_of_type": (integer, [pointer, pointer]),
            "g_variant_get_child_value": (pointer, [pointer, ctypes.c_size_t]),
            "g_variant_get_uint32": (ctypes.c_uint32, [pointer]),
            "g_variant_get_string": (string, [pointer, ctypes.POINTER(ctypes.c_size_t)]),
        })
        self.bind(self.object, {
            "g_object_unref": (None, [pointer]),
            "g_signal_connect_data": (ctypes.c_ulong, [pointer, string, pointer, pointer, pointer, integer]),
            "g_signal_handler_disconnect": (None, [pointer, ctypes.c_ulong]),
        })
        self.bind(self.gio, {
            "g_bus_get": (None, [integer, pointer, self.async_type, pointer]),
            "g_bus_get_finish": (pointer, [pointer, ctypes.POINTER(pointer)]),
            "g_cancellable_new": (pointer, []), "g_cancellable_cancel": (None, [pointer]),
            "g_bus_watch_name_on_connection": (unsigned, [pointer, string, integer, self.appeared_type, self.vanished_type, pointer, self.destroy_type]),
            "g_bus_unwatch_name": (None, [unsigned]), "g_dbus_is_unique_name": (integer, [string]),
            "g_dbus_connection_set_exit_on_close": (None, [pointer, integer]),
            "g_dbus_connection_signal_subscribe": (unsigned, [pointer, string, string, string, string, string, integer, self.signal_type, pointer, self.destroy_type]),
            "g_dbus_connection_signal_unsubscribe": (None, [pointer, unsigned]),
            "g_dbus_connection_call": (None, [pointer, string, string, string, string, pointer, pointer, integer, integer, pointer, self.async_type, pointer]),
            "g_dbus_connection_call_finish": (pointer, [pointer, pointer, ctypes.POINTER(pointer)]),
        })
        self.callbacks, self.sources, self.types = [], {}, {}
        self.connection, self.owner, self.id, self.watch, self.closed_handler = None, None, 0, 0, 0
        self.pending, self.subscriptions, self.releasing = {}, {}, set()
        self.closing = self.close_started = self.released = self.closed_sent = False
        self.exit_code = 0
        self.loop = self.glib.g_main_loop_new(None, False)
        self.bus_callback = self.callback(self.async_type, self.bus_ready)
        self.call_callback = self.callback(self.async_type, self.call_ready)
        self.signal_callback = self.callback(self.signal_type, self.notification_signal)
        self.destroy_callback = self.callback(self.destroy_type, self.native_released)
        self.appeared_callback = self.callback(self.appeared_type, self.owner_appeared)
        self.vanished_callback = self.callback(self.vanished_type, self.owner_vanished)
        self.closed_callback = self.callback(self.closed_type, self.connection_closed)

    @staticmethod
    def bind(library, functions):
        for name, (result, arguments) in functions.items():
            function = getattr(library, name)
            function.restype, function.argtypes = result, arguments

    def callback(self, signature, function):
        def invoke(*args):
            try:
                return function(*args)
            except Exception as error:
                self.fail("callback", str(error))
                return False
        result = signature(invoke)
        self.callbacks.append(result)
        return result

    def event(self, event, **fields):
        try:
            print(json.dumps({"event": event, **fields}), flush=True)
        except BrokenPipeError:
            self.exit_code = 1
            self.close()

    def error_message(self, error):
        return ctypes.cast(error, ctypes.POINTER(NoticeError)).contents.message.decode(errors="replace")

    def fail(self, operation, message):
        self.exit_code = 1
        self.event("error", operation=operation, message=message)
        self.close()

    def type(self, signature):
        if signature not in self.types:
            self.types[signature] = self.glib.g_variant_type_new(signature.encode())
        return self.types[signature]

    def text(self, value):
        if not isinstance(value, str) or "\0" in value:
            raise ValueError("Notification text must be a NUL-free string")
        return self.glib.g_variant_new_string(value.encode())

    def tuple(self, children):
        values = (ctypes.c_void_p * len(children))(*children)
        return self.glib.g_variant_new_tuple(values, len(children))

    def array(self, signature, children):
        values = (ctypes.c_void_p * len(children))(*children)
        return self.glib.g_variant_new_array(self.type(signature), values, len(children))

    def parameters(self):
        actions = self.request["actions"]
        self.actions = {action["id"] for action in actions}
        offered = self.array("s", [self.text(action[key]) for action in actions for key in ("id", "label")])
        hints = [self.glib.g_variant_new_dict_entry(self.text(key), self.glib.g_variant_new_variant(self.text(value)))
                 for key, value in self.request["hints"].items() if key != "resident"]
        hints.append(self.glib.g_variant_new_dict_entry(self.text("resident"), self.glib.g_variant_new_variant(self.glib.g_variant_new_boolean(True))))
        return self.tuple([self.text("Capture"), self.glib.g_variant_new_uint32(0), self.text(""),
                           self.text(self.request["title"]), self.text(self.request["message"]), offered,
                           self.array("{sv}", hints), self.glib.g_variant_new_int32(-1)])

    def source(self, name, interval, function):
        callback = self.callback(self.source_type, function)
        self.sources[name] = self.glib.g_timeout_add(interval, callback, None)

    def remove_source(self, name):
        identifier = self.sources.pop(name, 0)
        if identifier:
            self.glib.g_source_remove(identifier)

    def run(self):
        os.set_blocking(sys.stdin.fileno(), False)
        # GLibUnix sources dispatch on this same main context; GLib is not
        # reentrant from a Unix/Python signal handler (GLib 2.36 API).
        for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            self.sources[str(signum)] = self.glib.g_unix_signal_add(signum, self.callback(self.source_type, self.stop_signal), None)
        self.sources["stdin"] = self.glib.g_unix_fd_add(sys.stdin.fileno(), 1 | 8 | 16, self.callback(self.fd_type, self.control_ready), None)
        self.source("startup", CAPTURE_TIMEOUT * 1000, self.startup_timeout)
        self.pending["bus"] = self.gio.g_cancellable_new()
        self.gio.g_bus_get(2, self.pending["bus"], self.bus_callback, None)  # G_BUS_TYPE_SESSION
        if self.control:
            self.control_ready(sys.stdin.fileno(), 0, None)
        self.glib.g_main_loop_run(self.loop)
        self.glib.g_main_loop_unref(self.loop)
        return self.exit_code

    def stop_signal(self, _):
        self.close()
        return True

    def control_ready(self, descriptor, condition, _):
        try:
            data = os.read(descriptor, 4096)
        except BlockingIOError:
            data = None
        if data:
            self.control += data
        while b"\n" in self.control:
            line, self.control = self.control.split(b"\n", 1)
            if line == b"close":
                self.close()
            else:
                self.fail("control", "Unknown notification control")
        if data == b"" or condition & (8 | 16):
            self.close()
        return not self.closing

    def startup_timeout(self, _):
        self.sources.pop("startup", None)
        self.fail("startup", "Notification startup exceeded its time limit")
        return False

    def cleanup_timeout(self, _):
        self.exit_code = 1
        self.event("error", operation="cleanup", message="Notification cleanup exceeded its time limit")
        # A native operation that cannot finish must not outlive this run.
        # Exit without freeing callback pointers that C still owns.
        os._exit(1)

    def bus_ready(self, _, result, __):
        error = ctypes.c_void_p()
        self.connection = self.gio.g_bus_get_finish(result, ctypes.byref(error))
        self.object.g_object_unref(self.pending.pop("bus"))
        if error:
            message = self.error_message(error)
            self.glib.g_error_free(error)
            if not self.closing:
                self.fail("bus", message)
        elif not self.closing:
            # g_bus_get returns a shared connection in this helper process.
            # Own/unref our reference, never explicitly close the shared bus.
            self.gio.g_dbus_connection_set_exit_on_close(self.connection, False)
            self.closed_handler = self.object.g_signal_connect_data(self.connection, b"closed", ctypes.cast(self.closed_callback, ctypes.c_void_p), None, None, 0)
            self.watch = self.gio.g_bus_watch_name_on_connection(self.connection, self.destination, 0, self.appeared_callback, self.vanished_callback, 3, self.destroy_callback)
        self.settle()

    def owner_appeared(self, _, __, owner, ___):
        if self.closing:
            return
        if self.owner is not None:
            raise RuntimeError("Notification server identity changed without retirement")
        if not self.gio.g_dbus_is_unique_name(owner):
            raise RuntimeError("Notification server has no unique owner")
        self.owner = owner
        for token, member in ((1, b"ActionInvoked"), (2, b"NotificationClosed")):
            identifier = self.gio.g_dbus_connection_signal_subscribe(self.connection, owner, self.destination, member, self.object_path, None, 0, self.signal_callback, token, self.destroy_callback)
            self.subscriptions[identifier] = token
        self.call("notify", b"Notify", self.parameters(), "(u)", CAPTURE_TIMEOUT * 1000, 1)

    def owner_vanished(self, _, __, ___):
        if self.closing:
            return
        self.id = 0
        self.fail("server", "Notification server has no owner" if self.owner is None else "Notification server lost its owner")

    def connection_closed(self, _, __, error, ___):
        self.id = 0
        self.fail("bus", self.error_message(error) if error else "Notification connection closed")

    def call(self, name, method, parameters, reply, timeout, token):
        self.pending[name] = self.gio.g_cancellable_new()
        self.gio.g_dbus_connection_call(self.connection, self.owner, self.object_path, self.destination, method, parameters,
                                       self.type(reply), 0, timeout, self.pending[name], self.call_callback, token)

    def call_ready(self, connection, result, token):
        name = "notify" if token == 1 else "close"
        error = ctypes.c_void_p()
        reply = self.gio.g_dbus_connection_call_finish(connection, result, ctypes.byref(error))
        self.object.g_object_unref(self.pending.pop(name))
        if error:
            message = self.error_message(error)
            self.glib.g_error_free(error)
            self.fail(name, message)
        else:
            try:
                if name == "notify":
                    child = self.glib.g_variant_get_child_value(reply, 0)
                    try:
                        self.id = self.glib.g_variant_get_uint32(child)
                    finally:
                        self.glib.g_variant_unref(child)
                    if not self.id:
                        raise RuntimeError("Notification server returned an invalid id")
                    if not self.closing:
                        self.remove_source("startup")
                        self.event("ready", owner=self.owner.decode(), id=self.id)
                else:
                    self.id = 0
                    self.closed(3)
            finally:
                self.glib.g_variant_unref(reply)
        self.settle()

    def notification_signal(self, _, sender, __, ___, member, parameters, ____):
        if sender != self.owner or not self.id:
            return
        signature = "(us)" if member == b"ActionInvoked" else "(uu)"
        if not self.glib.g_variant_is_of_type(parameters, self.type(signature)):
            self.fail("signal", "Notification signal has an invalid type")
            return
        first = self.glib.g_variant_get_child_value(parameters, 0)
        try:
            identifier = self.glib.g_variant_get_uint32(first)
        finally:
            self.glib.g_variant_unref(first)
        if identifier != self.id:
            return
        second = self.glib.g_variant_get_child_value(parameters, 1)
        try:
            if member == b"ActionInvoked":
                action = self.glib.g_variant_get_string(second, None).decode()
                if not self.closing and action in self.actions:
                    self.event("action", id=action)
            else:
                reason = self.glib.g_variant_get_uint32(second)
                self.id = 0
                self.closed(reason)
                self.close()
        finally:
            self.glib.g_variant_unref(second)

    def closed(self, reason):
        if not self.closed_sent:
            self.closed_sent = True
            self.event("closed", reason=reason)

    def close(self):
        if not self.closing:
            self.closing = True
            self.remove_source("startup")
            self.remove_source("stdin")
            self.source("cleanup", self.cleanup_ms, self.cleanup_timeout)
            if "bus" in self.pending:
                self.gio.g_cancellable_cancel(self.pending["bus"])
            # Keep one in-flight Notify reply within this shared deadline:
            # cancelling it could discard the id of an accepted notification.
            # Once learned, settle closes that id at its retained unique owner.
        self.settle()

    def settle(self):
        if not self.closing or self.released or self.pending:
            return
        if self.id and not self.close_started:
            self.close_started = True
            self.call("close", b"CloseNotification", self.tuple([self.glib.g_variant_new_uint32(self.id)]), "()", self.cleanup_ms, 2)
            return
        watch, self.watch = self.watch, 0
        subscriptions, self.subscriptions = self.subscriptions, {}
        self.releasing.update(subscriptions.values())
        if watch:
            self.releasing.add(3)
        if watch:
            self.gio.g_bus_unwatch_name(watch)
        for identifier in subscriptions:
            self.gio.g_dbus_connection_signal_unsubscribe(self.connection, identifier)
        # GLib 2.88.3 signal_unsubscribe requires draining the same context
        # until its destroy notifications run, even after unsubscribe returns.
        if self.releasing or self.released:
            return
        self.released = True
        if self.closed_handler:
            self.object.g_signal_handler_disconnect(self.connection, self.closed_handler)
        for name in list(self.sources):
            self.remove_source(name)
        if self.connection:
            self.object.g_object_unref(self.connection)
        for value in self.types.values():
            self.glib.g_variant_type_free(value)
        self.glib.g_main_loop_quit(self.loop)

    def native_released(self, token):
        self.releasing.discard(token)
        if not self.releasing and not self.released:
            # DestroyNotify can run inside an unsubscribe/unwatch call.
            # Let that native stack return before releasing the connection.
            self.source("release", 0, self.release_ready)

    def release_ready(self, _):
        self.sources.pop("release", None)
        self.settle()
        return False


def notification():
    """Read the producer request without buffering later control lines away."""
    initial = b""
    try:
        while b"\n" not in initial:
            data = os.read(sys.stdin.fileno(), 4096)
            if not data:
                raise ValueError("Notification request is missing")
            initial += data
        line, control = initial.split(b"\n", 1)
        request = json.loads(line)
        return CaptureNotice(request, control).run()
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(json.dumps({"event": "error", "operation": "startup", "message": str(error)}), flush=True)
        return 1


def main():
    if sys.argv[1:] == ["--notify"]:
        return notification()
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
