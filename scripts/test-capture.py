#!/usr/bin/env python3
"""Capture worker behaviour against stand-ins, plus behaviour-removing controls.

--nested REAL_GRIM OUTPUT WIDTH HEIGHT DISPLAY RUNTIME runs grim on that
confined output. The mode expectations come from Hyprland, never from a PNG.
No inherited desktop, bus or device environment reaches an offline child.
"""
import json
import ctypes
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parent.parent
HELPER = REPO / "shell/plugins/vgs.capture/helper/capture.py"
FIXTURE = REPO / "scripts/smoke/fixtures/capture/tools.py"
TOOLS = ("grim", "slurp", "hyprpicker", "tesseract", "wl-copy", "gpu-screen-recorder")


def plant(root, config):
    """Put stand-ins first on PATH; each reads the same fixture world."""
    root.mkdir(parents=True, exist_ok=True)
    (root / "bin").mkdir(exist_ok=True)
    (root / "config.json").write_text(json.dumps(config))
    for tool in TOOLS:
        path = root / "bin" / tool
        path.write_text(f"#!{sys.executable}\nimport os, runpy\nos.environ['VGS_CAPTURE_FIXTURE'] = {str(root)!r}\nos.environ['VGS_CAPTURE_TOOL'] = {tool!r}\nrunpy.run_path({str(FIXTURE)!r}, run_name='__main__')\n")
        path.chmod(0o755)


def events(output):
    return [json.loads(line) for line in output.splitlines()]


def calls(root):
    path = root / "calls.jsonl"
    return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []


def request(root, action):
    return {"action": action, "output": "NESTED", "folder": str(root / "pictures"), "recordFolder": str(root / "videos"), "audio": "desktop"}


def environment(root, config):
    env = {"PATH": str(root / "bin"), "HOME": str(root / "home"), "XDG_CONFIG_HOME": str(root / "home/.config"), "LC_ALL": "C", "VGS_TEST_RUN": "1"}
    if "real" in config:
        env.update(WAYLAND_DISPLAY=config["display"], XDG_RUNTIME_DIR=config["runtime"])
    return env


def wait_for(path, proc):
    # A stand-in writes its marker once it is ready; the helper may exit first.
    deadline = time.monotonic() + 5
    while not path.exists() and proc.poll() is None and time.monotonic() < deadline:
        time.sleep(0.01)


def worker(root, payload, helper=HELPER, recording=False, line=None, timeout=10):
    """Run the helper with its control pipe held open, as the service holds it.

    LINE is written once the slurp stand-in waits; recording writes `stop`.
    A helper still running after TIMEOUT is killed and answers None.
    """
    config = json.loads((root / "config.json").read_text())
    control, writer = os.pipe()
    proc = subprocess.Popen([sys.executable, str(helper), json.dumps(payload)], env=environment(root, config), stdin=control, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    os.close(control)
    try:
        if line is not None:
            wait_for(root / "slurp-ready", proc)
            os.write(writer, line.encode())
        if recording:
            wait_for(root / "recorder-ready", proc)
            os.write(writer, b"stop\n")
        try:
            out, err = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            return None, [], "timeout"
        return proc.returncode, events(out), err
    finally:
        os.close(writer)


def alive(root, tool):
    """Pids of TOOL's stand-ins that still run."""
    pids = []
    for marker in root.glob(tool + "-pid-*"):
        pid = int(marker.name.removeprefix(tool + "-pid-"))
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            continue
        pids.append(pid)
    return pids


def area_holds(root, payload, helper):
    """An area capture finishes with the selected geometry while the service's pipe stays open."""
    code, output, err = worker(root, payload, helper, timeout=5)
    grims = [c["args"] for c in calls(root) if c["tool"] == "grim"]
    return (code == 0 and output[-1]["event"] == "saved" and grims[-1][:2] == ["-g", "10,20 80x60"]
            and Path(output[-1]["path"]).is_file() and not alive(root, "slurp") and not alive(root, "hyprpicker"))


def freeze_released_holds(root, payload, config, helper):
    """The freeze ends with the capture, while the helper still holds the clipboard."""
    proc = subprocess.Popen([sys.executable, str(helper), json.dumps(payload)], env=environment(root, config), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        saved = json.loads(proc.stdout.readline())["event"] == "saved"
        return saved and proc.poll() is None and bool(list(root.glob("hyprpicker-pid-*"))) and not alive(root, "hyprpicker")
    finally:
        proc.kill()
        proc.communicate(timeout=5)


def screenshot_holds(root, payload, helper, dimensions):
    code, output, err = worker(root, payload, helper)
    if code or not output or output[-1]["event"] != "saved":
        return False
    image = Path(output[-1]["path"]).read_bytes()
    copied = root / "clipboard"
    argv = next(c["args"] for c in calls(root) if c["tool"] == "grim")
    return (image[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", image[16:24]) == dimensions
            and argv[:2] == ["-o", payload["output"]] and copied.exists() and copied.read_bytes() == image)


def record_holds(root, payload, helper):
    code, output, err = worker(root, payload, helper, recording=True)
    recorder = [c for c in calls(root) if c["tool"] == "gpu-screen-recorder"]
    return (code == 0 and output[-1]["event"] == "saved" and len(recorder) == 1
            and recorder[0]["args"][:4] == ["-w", "region", "-region", "80x60+10+20"]
            and Path(output[-1]["path"]).read_bytes() == b"finalized"
            and (root / "signal").read_text() == str(signal.SIGINT))


def english_data_error_holds(root, helper):
    """An installed OCR tool without English data reports its cause and keeps the clipboard."""
    (root / "clipboard").write_bytes(b"previous clipboard")
    code, output, err = worker(root, request(root, "text"), helper)
    return (code == 1 and len(output) == 1 and output[0]["event"] == "error"
            and output[0].get("reason") == "english-data-unavailable"
            and (root / "clipboard").read_bytes() == b"previous clipboard"
            and not any(call["tool"] == "wl-copy" for call in calls(root)))


def killed_owner_holds(root, payload, config, helper=HELPER):
    """Kill only the owned helper; reap or clean up its known fixture child."""
    clipboard = payload["action"] == "screenshot"
    ready = "clipboard-ready-" if clipboard else "recorder-ready"
    proc = subprocess.Popen([sys.executable, str(helper), json.dumps(payload)], env=environment(root, config), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    pid = None
    try:
        deadline = time.monotonic() + 5
        while not list(root.glob(ready + "*")) and proc.poll() is None and time.monotonic() < deadline:
            time.sleep(0.01)
        markers = list(root.glob(ready + "*"))
        assert len(markers) == 1, "owned tool readiness"
        pid = int(markers[0].name.removeprefix(ready)) if clipboard else int(markers[0].read_text())
        if clipboard:
            assert json.loads(proc.stdout.readline())["event"] == "saved" and proc.poll() is None, "copy completes while provider lives"
        proc.kill()
        try:
            proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            return False
        os.waitpid(pid, 0)
        stopped = root / ("clipboard-signal-" + str(pid)) if clipboard else root / "signal"
        pid = None
        expected = signal.SIGTERM if clipboard else signal.SIGINT
        return (stopped.exists() and stopped.read_text() == str(expected)
                and (clipboard or next((root / "videos").glob("*.mp4")).read_bytes() == b"finalized"))
    finally:
        if proc.poll() is None:
            proc.kill()
        if pid is not None:
            waited, _ = os.waitpid(pid, os.WNOHANG)
            if waited == 0:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
        proc.communicate(timeout=5)


def main():
    config = {}
    output = "NESTED"
    dimensions = (320, 240)
    if len(sys.argv) > 1:
        assert sys.argv[1] == "--nested" and len(sys.argv) == 8
        real, output, width, height, display, runtime = sys.argv[2:]
        config = {"real": {"grim": real}, "display": display, "runtime": runtime}
        dimensions = (int(width), int(height))
    with tempfile.TemporaryDirectory(prefix="capture-test-", dir=REPO / "tmp") as temp:
        base = Path(temp).resolve()
        def world(name, **extra):
            root = base / name
            plant(root, {**config, **extra})
            return root
        root = world("screenshot")
        payload = request(root, "screenshot")
        payload["output"] = output
        assert screenshot_holds(root, payload, HELPER, dimensions), "screenshot mode and clipboard"
        root = world("area")
        assert area_holds(root, request(root, "screenshot-area"), HELPER), "area capture with the control pipe open"
        cancels = ("cancel", "escape", "second-press", "record-second-press", "eof")
        for name, action, extra, line, event in [
            ("cancel", "screenshot-area", {"cancel": True}, None, "cancelled"),
            ("escape", "screenshot-area", {"escape": True}, None, "cancelled"),
            ("second-press", "screenshot-area", {"hold": True}, "cancel\n", "cancelled"),
            ("record-second-press", "record", {"hold": True}, "cancel\n", "cancelled"),
            ("text", "text", {}, None, "copied"),
            ("empty-text", "text", {"text": ""}, None, "error"),
            ("freeze-failure", "screenshot-area", {"fail": "hyprpicker"}, None, "error"),
            ("selection-failure", "text", {"fail": "slurp"}, None, "error"),
            ("grim-failure", "screenshot", {"fail": "grim"}, None, "error"),
            ("clipboard-failure", "screenshot", {"fail": "wl-copy"}, None, "error"),
            ("ocr-failure", "text", {"fail": "tesseract"}, None, "error"),
            ("recorder-failure", "record", {"fail": "gpu-screen-recorder"}, None, "error"),
            ("recorder-crash", "record", {"crash": True}, None, "error"),
        ]:
            root = world(name, **extra)
            if name in (*cancels, "empty-text", "ocr-failure"):
                (root / "clipboard").write_bytes(b"previous clipboard")
            payload = request(root, action)
            payload["output"] = output
            code, messages, err = worker(root, payload, line=line)
            assert messages and messages[-1]["event"] == event and code == (1 if event == "error" else 0), (name, messages, err)
            assert not alive(root, "slurp") and not alive(root, "hyprpicker"), (name, "selector or freeze left running")
            if name in cancels:
                assert not (root / "pictures").exists() and not (root / "videos").exists() and (root / "clipboard").read_bytes() == b"previous clipboard", name
            if name == "freeze-failure":
                assert "hyprpicker exited 1: fixture failure" in messages[-1]["message"] and not any(c["tool"] == "slurp" for c in calls(root))
            if name == "text":
                assert (root / "clipboard").read_bytes() == b"Nested capture text"
            if name == "empty-text":
                assert (root / "clipboard").read_bytes() == b"previous clipboard"
            if name == "ocr-failure":
                assert "tesseract: fixture failure" in messages[-1]["message"]
                assert (root / "clipboard").read_bytes() == b"previous clipboard"
        root = world("record")
        assert record_holds(root, request(root, "record"), HELPER), "record SIGINT finalization"
        root = world("freeze-released", clipboardHold=True)
        assert freeze_released_holds(root, request(root, "screenshot-area"), config, HELPER), "freeze ends with the capture"
        for audio, wanted in [("none", None), ("microphone", "default_input"), ("both", "default_output|default_input")]:
            root = world("record-" + audio)
            payload = request(root, "record")
            payload["audio"] = audio
            assert record_holds(root, payload, HELPER), audio
            args = next(row["args"] for row in calls(root) if row["tool"] == "gpu-screen-recorder")
            assert ("-a" not in args) if wanted is None else args[args.index("-a") + 1] == wanted
        root = world("relative-folder")
        payload = request(root, "screenshot")
        payload.update(folder="relative", output=output)
        code, messages, err = worker(root, payload)
        assert code == 1 and messages[-1]["event"] == "error" and not (root / "clipboard").exists()
        source = HELPER.read_text()
        root = world("english-data-missing", englishDataMissing=True)
        assert english_data_error_holds(root, HELPER), "OCR English data failure"
        before = "for pattern, reason, message in OCR_FAILURES:"
        assert source.count(before) == 1, "OCR error classification control match"
        changed = source.replace(before, "for pattern, reason, message in ():")
        assert changed != source
        helper = base / "raw-ocr-error.py"
        helper.write_text(changed)
        root = world("raw-ocr-error", englishDataMissing=True)
        assert not english_data_error_holds(root, helper), "control did not fail: raw OCR error"
        mutations = [
            ("no-output", 'path = self.grab(request, ["grim", "-o", request["output"]])', 'path = self.grab(request, ["grim"])', "screenshot"),
            ("no-clipboard", 'child = self.copy(image, "image/png")', 'child = self.spawn([sys.executable, "-c", "import sys; sys.stdin.buffer.read()"], stdin=image, stderr=subprocess.PIPE)', "screenshot"),
            ("hard-stop", 'self.recorder.send_signal(signal.SIGINT)', 'self.recorder.send_signal(signal.SIGKILL)', "record"),
        ]
        for name, before, after, action in mutations:
            assert source.count(before) == 1, name
            changed = source.replace(before, after)
            assert changed != source
            helper = base / f"{name}.py"
            helper.write_text(changed)
            root = world(name)
            payload = request(root, action)
            payload["output"] = output
            holds = record_holds(root, payload, helper) if action == "record" else screenshot_holds(root, payload, helper, dimensions)
            assert not holds, f"control did not fail: {name}"
        for name, before, after, check in [
            ("inherited-stdin", 'kwargs.setdefault("stdin", subprocess.DEVNULL)', 'pass', lambda root, helper: area_holds(root, request(root, "screenshot-area"), helper)),
            ("kept-freeze", "            self.stop(freeze)\n", "            pass\n", lambda root, helper: freeze_released_holds(root, request(root, "screenshot-area"), config, helper)),
        ]:
            assert source.count(before) == 1, name
            changed = source.replace(before, after)
            assert changed != source
            helper = base / f"{name}.py"
            helper.write_text(changed)
            root = world(name, clipboardHold=name == "kept-freeze")
            assert not check(root, helper), f"control did not fail: {name}"
        root = world("xdg")
        dirs = root / "home/.config"
        dirs.mkdir(parents=True)
        (dirs / "user-dirs.dirs").write_text('XDG_PICTURES_DIR="$HOME/My Pictures"\nXDG_VIDEOS_DIR="$HOME/My Videos"\n')
        payload = request(root, "screenshot")
        payload.update(folder="", output=output)
        code, messages, err = worker(root, payload)
        assert code == 0 and Path(messages[-1]["path"]).parent == root / "home/My Pictures/Screenshots"
        # A service teardown kills its helper: no recorder survives that owner.
        root = world("teardown")
        proc = subprocess.Popen([sys.executable, str(HELPER), json.dumps(request(root, "record"))], env=environment(root, {}), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        deadline = time.monotonic() + 5
        while not (root / "recorder-ready").exists() and proc.poll() is None and time.monotonic() < deadline:
            time.sleep(0.01)
        assert (root / "recorder-ready").exists()
        proc.terminate()
        proc.communicate(timeout=10)
        assert (root / "signal").read_text() == str(signal.SIGINT)
        try:
            os.kill(int((root / "recorder-ready").read_text()), 0)
        except ProcessLookupError:
            pass
        else:
            raise AssertionError("recorder survived worker teardown")
        # Quickshell destroys a Process with SIGKILL. Adopt the test child
        # here so the fixture can reap it after the worker is killed.
        assert ctypes.CDLL(None).prctl(36, 1, 0, 0, 0) == 0, "test subreaper setup"
        for name, action, extra in [
            ("killed-recorder-owner", "record", {}),
            ("killed-clipboard-owner", "screenshot", {"clipboardHold": True}),
        ]:
            root = world(name, **extra)
            payload = request(root, action)
            payload["output"] = output
            assert killed_owner_holds(root, payload, config), name
        before = "if libc.prctl(1, stop, 0, 0, 0) != 0:"
        assert source.count(before) == 1
        helper = base / "unowned-child.py"
        helper.write_text(source.replace(before, "if False:"))
        root = world("unowned-child")
        assert not killed_owner_holds(root, request(root, "record"), config, helper), "control did not fail: unowned child"
    print("test-capture: pass; controls=raw-ocr-error,no-output,no-clipboard,hard-stop,inherited-stdin,kept-freeze,unowned-child")


if __name__ == "__main__":
    main()
