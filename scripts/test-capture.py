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
import select
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
    return {"action": action, "output": "NESTED", "folder": str(root / "pictures"), "recordFolder": str(root / "videos"), "audio": "desktop", "smart": False,
            "outputs": [{"x": 0, "y": 0, "width": 320, "height": 240, "name": "NESTED", "scale": 1, "transform": 0}]}


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
        message = json.loads(proc.stdout.readline())
        if message["event"] == "selection-ended":
            message = json.loads(proc.stdout.readline())
        saved = message["event"] == "saved"
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
            expected_event = "copied" if payload.get("processing") == "copy" else "saved"
            assert json.loads(proc.stdout.readline())["event"] == expected_event and proc.poll() is None, "copy completes while provider lives"
            if expected_event == "copied":
                grims = [row["args"] for row in calls(root) if row["tool"] == "grim"]
                assert not Path(grims[-1][-1]).exists() and not (root / "pictures").exists(), "scratch ends before clipboard ownership"
                assert (root / "clipboard").read_bytes().startswith(b"\x89PNG\r\n\x1a\n"), "copy bytes stay available"
        proc.kill()
        try:
            proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            return False
        deadline = time.monotonic() + 2
        while True:
            waited, _ = os.waitpid(pid, os.WNOHANG)
            if waited:
                break
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.01)
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


def choice_holds(root, helper, payload, geometry=None, boxes=None, cursor=False, processing="save-copy", selection=True):
    code, messages, err = worker(root, payload, helper)
    if code != 0 or not messages:
        return False
    grims = [row["args"] for row in calls(root) if row["tool"] == "grim"]
    if not grims:
        return False
    args = grims[-1]
    if geometry is not None and args[:2] != ["-g", geometry]:
        return False
    if ("-c" in args) != cursor:
        return False
    if selection and [message["event"] for message in messages] != ["selection-ended", "copied" if processing == "copy" else "saved"]:
        return False
    if boxes is not None:
        slurps = [row for row in calls(root) if row["tool"] == "slurp"]
        if not slurps or "-r" not in slurps[-1]["args"] or (root / "slurp-input").read_text() != boxes:
            return False
    if processing == "copy":
        return (messages[-1]["event"] == "copied" and "path" not in messages[-1]
                and not (root / "pictures").exists() and not Path(args[-1]).exists()
                and (root / "clipboard").exists())
    if messages[-1]["event"] != "saved" or not Path(messages[-1]["path"]).is_file():
        return False
    if processing == "save":
        return (root / "clipboard").read_bytes() == b"previous clipboard" and not any(row["tool"] == "wl-copy" for row in calls(root))
    return (root / "clipboard").read_bytes() == Path(messages[-1]["path"]).read_bytes()


def delay_holds(root, payload, helper, cancel=False, acknowledge=True):
    config = json.loads((root / "config.json").read_text())
    control, writer = os.pipe()
    proc = subprocess.Popen([sys.executable, str(helper), json.dumps(payload)], env=environment(root, config),
                            stdin=control, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    os.close(control)
    observed = []
    valid = True
    started = time.monotonic()
    try:
        # Each line is a readiness barrier. The deadline bounds mutated copies
        # that drop ticks, cancellation, or the completion acknowledgement.
        deadline = time.monotonic() + 4
        while proc.poll() is None and time.monotonic() < deadline:
            ready, _, _ = select.select([proc.stdout], [], [], min(0.05, max(0, deadline - time.monotonic())))
            if not ready:
                continue
            line = proc.stdout.readline()
            if not line:
                break
            message = json.loads(line)
            observed.append(message)
            if message["event"] == "countdown":
                valid = valid and not (root / "pictures").exists() and not alive(root, "hyprpicker")
                if message["remaining"] == 0:
                    valid = valid and time.monotonic() - started >= payload["delay"]
                    if acknowledge:
                        config["frame"] = "after-countdown"
                        (root / "config.json").write_text(json.dumps(config))
                        os.write(writer, b"countdown-hidden\n")
                elif cancel:
                    os.write(writer, b"cancel\n")
            if message["event"] in ("saved", "copied", "cancelled", "error"):
                break
        out, err = proc.communicate(timeout=1)
        observed.extend(events(out))
        ticks = [m["remaining"] for m in observed if m["event"] == "countdown"]
        if cancel:
            return (valid and proc.returncode == 0 and ticks == [payload["delay"]] and observed[-1]["event"] == "cancelled"
                    and not (root / "pictures").exists() and not (root / "clipboard").exists())
        if not acknowledge:
            return valid and proc.returncode == 1 and ticks == [1, 0] and observed[-1].get("reason") == "timeout" and not (root / "pictures").exists()
        return (valid and proc.returncode == 0 and ticks == list(range(payload["delay"], -1, -1))
                and observed[-1]["event"] == "saved" and Path(observed[-1]["path"]).read_bytes().endswith(b"after-countdown"))
    except subprocess.TimeoutExpired:
        return False
    finally:
        os.close(writer)
        if proc.poll() is None:
            proc.kill()
        proc.communicate(timeout=5)


def timeout_holds(root, helper, action):
    payload = request(root, action)
    payload["timeout"] = 1
    code, messages, err = worker(root, payload, helper, timeout=3)
    return (code == 1 and messages[-1].get("reason") == "timeout" and not alive(root, "grim")
            and not alive(root, "hyprpicker") and not list((root / "pictures").glob("*.png")))


def refusal_holds(root, helper, payload, reason):
    code, messages, err = worker(root, payload, helper, timeout=3)
    return (code == 1 and bool(messages) and messages[-1]["event"] == "error" and messages[-1].get("reason") == reason
            and not (root / "pictures").exists() and not (root / "clipboard").exists()
            and not any(row["tool"] in ("slurp", "grim", "wl-copy") for row in calls(root)))


def screenshot_choices(base, source):
    def world(name, **config):
        root = base / ("choices-" + name)
        plant(root, config)
        return root
    window = {"x": 10, "y": 20, "width": 80, "height": 60, "address": "0x1"}
    outer = {"x": 0, "y": 0, "width": 200, "height": 160, "address": "0x2"}
    outputs = [{"x": -160, "y": -40, "width": 160, "height": 240, "name": "LEFT", "scale": 1, "transform": 0},
               {"x": 0, "y": 20, "width": 320, "height": 180, "name": "NESTED", "scale": 1, "transform": 0}]
    cases = [
        ("smart-window", "screenshot-area", "30,40 1x1", "10,20 80x60", True, [outer, window], None),
        ("smart-output", "screenshot-area", "250,40 1x1", "0,20 320x180", True, [outer, window], None),
        ("region", "screenshot-area", "30,40 1x1", "30,40 1x1", False, [window], None),
        ("threshold", "screenshot-area", "30,40 5x4", "30,40 5x4", True, [window], None),
        ("window", "screenshot-window", "10,20 80x60", "10,20 80x60", True, [window], "10,20 80x60\n"),
        ("display", "screenshot-display", "-160,-40 160x240", "-160,-40 160x240", True, [window], "-160,-40 160x240\n0,20 320x180\n"),
        ("all", "screenshot-all", None, "-160,-40 480x240", True, [window], None),
    ]
    for name, action, selected, geometry, smart, windows, boxes in cases:
        root = world(name, **({"geometry": selected} if selected else {}))
        payload = request(root, action)
        payload.update(windows=windows, outputs=outputs, smart=smart)
        assert choice_holds(root, HELPER, payload, geometry, boxes, selection=action != "screenshot-all"), name
    root = world("smart-focus-tie", geometry="30,40 1x1")
    payload = request(root, "screenshot-area")
    payload.update(smart=True, windows=[{**window, "focus": 2}, {**window, "x": 20, "focus": 1}])
    assert choice_holds(root, HELPER, payload, geometry="20,20 80x60"), "focus orders equal-sized windows"
    for name, scale, transform, width, height, expected in [
        ("scaled-output", 2, 0, 640, 480, "-160,20 480x240"),
        ("rotated-output", 1, 1, 240, 160, "-160,20 480x240"),
        ("flipped-output", 1, 5, 240, 160, "-160,20 480x240"),
    ]:
        root = world(name)
        payload = request(root, "screenshot-all")
        payload["outputs"] = [
            {"x": -160, "y": 20, "width": width, "height": height, "scale": scale, "transform": transform, "name": "LEFT"},
            {"x": 0, "y": 20, "width": 320, "height": 180, "scale": 1, "transform": 0, "name": "NESTED"},
        ]
        assert choice_holds(root, HELPER, payload, geometry=expected, selection=False), name
    for name, processing, cursor in [("cursor", "save-copy", True), ("copy", "copy", False), ("save", "save", False)]:
        root = world(name)
        (root / "clipboard").write_bytes(b"previous clipboard")
        payload = request(root, "screenshot")
        payload.update(processing=processing, cursor=cursor)
        # Save needs no clipboard command, even when that command is absent.
        if processing == "save":
            (root / "bin/wl-copy").unlink()
        assert choice_holds(root, HELPER, payload, cursor=cursor, processing=processing, selection=False), name
    root = world("copy-ignores-save-folder")
    payload = request(root, "screenshot")
    payload.update(processing="copy", folder="relative")
    assert choice_holds(root, HELPER, payload, processing="copy", selection=False), "copy ignores save folder"
    for action in ("screenshot-window", "screenshot-display", "screenshot-all"):
        root = world("empty-" + action)
        payload = request(root, action)
        payload.update(windows=[], outputs=[])
        assert refusal_holds(root, HELPER, payload, "no-targets"), action
    invalid_settings = [
        ("delay", -1, "invalid-delay"), ("delay", 61, "invalid-delay"), ("delay", 1.5, "invalid-delay"), ("delay", True, "invalid-delay"),
        ("timeout", 0, "invalid-timeout"), ("timeout", 61, "invalid-timeout"), ("timeout", float("nan"), "invalid-timeout"), ("timeout", True, "invalid-timeout"),
        ("processing", "edit", "invalid-processing"),
    ]
    for index, (setting, value, reason) in enumerate(invalid_settings):
        root = world("invalid-setting-" + str(index))
        payload = request(root, "screenshot")
        payload[setting] = value
        assert refusal_holds(root, HELPER, payload, reason), (setting, value)
    for name, cancel, acknowledge in [("delay", False, True), ("delay-cancel", True, True), ("delay-ack", False, False)]:
        root = world(name)
        payload = request(root, "screenshot-area")
        payload.update(delay=1, timeout=1)
        assert delay_holds(root, payload, HELPER, cancel=cancel, acknowledge=acknowledge), name
    for action in ("screenshot", "screenshot-area"):
        root = world("timeout-" + action, grimHold=True)
        assert timeout_holds(root, HELPER, action), action
    mutations = [
        ("invalid-delay-accepted", 'if type(delay) is not int or not 0 <= delay <= 60:', 'if False:', "invalid-delay"),
        ("invalid-timeout-accepted", 'if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or not 1 <= timeout <= 60:', 'if False:', "invalid-timeout"),
        ("invalid-processing-accepted", 'if processing not in ("save-copy", "copy", "save"):', 'if False:', "invalid-processing"),
        ("empty-selection-accepted", 'if action in ("screenshot-window", "screenshot-display") and not boxes:', 'if False:', "empty-selection"),
        ("empty-displays-accepted", 'if not outputs:', 'if False:', "empty-displays"),
        ("smart-snap", 'picked = rectangle_geometry(target), tuple(str(target[k]) for k in ("x", "y", "width", "height"))', 'picked = picked', "smart"),
        ("window-boxes", 'boxes = windows\n', 'boxes = outputs\n', "window"),
        ("display-boxes", 'boxes = outputs\n', 'boxes = windows\n', "display"),
        ("all-bounds", 'args = ["grim", "-g", f"{left},{top} {right - left}x{bottom - top}"]', 'args = ["grim", "-o", request["output"]]', "all"),
        ("no-scale", 'width = int(output["width"] / output["scale"])', 'width = int(output["width"])', "scale"),
        ("no-rotation", 'if output["transform"] in (1, 3, 5, 7):', 'if False:', "rotation"),
        ("no-cursor", 'args = args + (["-c"] if request.get("cursor", False) else [])', 'args = args', "cursor"),
        ("copy-saves", 'if processing == "copy":', 'if False:', "copy"),
        ("save-copies", 'if processing != "save":', 'if True:', "save"),
        ("no-delay", 'if not self.countdown(delay, timeout):', 'if False:', "delay"),
        ("delay-ignores-cancel", 'ready, _, _ = select.select([sys.stdin], [], [], max(0, deadline - time.monotonic()))\n                if ready and sys.stdin.readline().strip() in ("", "cancel"):\n                    return False', 'ready, _, _ = select.select([sys.stdin], [], [], max(0, deadline - time.monotonic()))\n                if ready and sys.stdin.readline().strip() == "":\n                    return False', "cancel"),
        ("no-timeout", 'child.communicate(timeout=timeout)', 'child.communicate()', "timeout"),
    ]
    for name, before, after, kind in mutations:
        assert source.count(before) == 1, name
        changed = source.replace(before, after)
        assert changed != source
        helper = base / (name + ".py")
        helper.write_text(changed)
        root = world(name, **({"geometry": "30,40 1x1"} if kind == "smart" else {"grimHold": True} if kind == "timeout" else {}))
        payload = request(root, "screenshot")
        if kind.startswith("invalid-"):
            setting, value = {"invalid-delay": ("delay", 1.5), "invalid-timeout": ("timeout", 0), "invalid-processing": ("processing", "edit")}[kind]
            payload[setting] = value
            holds = refusal_holds(root, helper, payload, kind)
        elif kind.startswith("empty-"):
            payload.update(action="screenshot-window" if kind == "empty-selection" else "screenshot-all", windows=[], outputs=[])
            holds = refusal_holds(root, helper, payload, "no-targets")
        elif kind in ("delay", "cancel"):
            payload.update(action="screenshot-area", delay=1, timeout=1)
            holds = delay_holds(root, payload, helper, cancel=kind == "cancel")
        elif kind == "timeout":
            holds = timeout_holds(root, helper, "screenshot")
        else:
            payload.update(windows=[window], outputs=outputs)
            geometry, boxes, selection = None, None, False
            if kind == "smart":
                payload.update(action="screenshot-area", smart=True)
                geometry, selection = "10,20 80x60", True
            elif kind == "window":
                payload["action"] = "screenshot-window"
                geometry, boxes, selection = "10,20 80x60", "10,20 80x60\n", True
            elif kind == "display":
                payload["action"] = "screenshot-display"
                boxes, selection = "-160,-40 160x240\n0,20 320x180\n", True
            elif kind == "all":
                payload["action"] = "screenshot-all"
                geometry = "-160,-40 480x240"
            elif kind in ("scale", "rotation"):
                payload["action"] = "screenshot-all"
                payload["outputs"] = [{"x": 0, "y": 0, "width": 640, "height": 480, "name": "NESTED", "scale": 2, "transform": 1 if kind == "rotation" else 0}]
                geometry = "0,0 240x320" if kind == "rotation" else "0,0 320x240"
            elif kind == "cursor":
                payload["cursor"] = True
            elif kind in ("copy", "save"):
                payload["processing"] = kind
                (root / "clipboard").write_bytes(b"previous clipboard")
            holds = choice_holds(root, helper, payload, geometry, boxes, cursor=kind == "cursor",
                                 processing=kind if kind in ("copy", "save") else "save-copy", selection=selection)
        assert not holds, "control did not fail: " + name
    # Selection-end is the service's focus-restore protocol on all exit paths.
    for name, extra, event in [("success", {}, "saved"), ("cancel", {"cancel": True}, "cancelled"), ("error", {"fail": "slurp"}, "error")]:
        root = world("selection-end-" + name, **extra)
        code, messages, err = worker(root, request(root, "screenshot-area"))
        assert [m["event"] for m in messages] == ["selection-ended", event], name
    assert source.count('emit("selection-ended")') == 2
    helper = base / "no-selection-end.py"
    helper.write_text(source.replace('emit("selection-ended")', 'pass'))
    root = world("no-selection-end")
    code, messages, err = worker(root, request(root, "screenshot-area"), helper)
    assert [m["event"] for m in messages] != ["selection-ended", "saved"], "control did not fail: selection-end"


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
        screenshot_choices(base, source)
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
            ("no-output", 'args = ["grim", "-o", request["output"]]', 'args = ["grim"]', "screenshot"),
            ("no-clipboard", 'child = self.spawn(["wl-copy", "--foreground", "--type", mime], stdin=subprocess.PIPE, stderr=subprocess.PIPE)', 'child = self.spawn([sys.executable, "-c", "import sys; sys.stdin.buffer.read()"], stdin=subprocess.PIPE, stderr=subprocess.PIPE)', "screenshot"),
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
            ("killed-copy-owner", "screenshot", {"clipboardHold": True}),
        ]:
            root = world(name, **extra)
            payload = request(root, action)
            payload["output"] = output
            if name == "killed-copy-owner":
                payload["processing"] = "copy"
            assert killed_owner_holds(root, payload, config), name
        before = "if libc.prctl(1, stop, 0, 0, 0) != 0:"
        assert source.count(before) == 1
        helper = base / "unowned-child.py"
        helper.write_text(source.replace(before, "if False:"))
        root = world("unowned-child")
        assert not killed_owner_holds(root, request(root, "record"), config, helper), "control did not fail: unowned child"
    print("test-capture: pass; controls=raw-ocr-error,no-output,no-clipboard,hard-stop,inherited-stdin,kept-freeze,unowned-child,invalid-delay-accepted,invalid-timeout-accepted,invalid-processing-accepted,empty-selection-accepted,empty-displays-accepted,smart-snap,window-boxes,display-boxes,all-bounds,no-scale,no-rotation,no-cursor,copy-saves,save-copies,no-delay,delay-ignores-cancel,no-timeout,no-selection-end")


if __name__ == "__main__":
    main()
