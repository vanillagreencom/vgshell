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
import shutil
import struct
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parent.parent
HELPER = REPO / "shell/plugins/vgs.capture/helper/capture.py"
FIXTURE = REPO / "scripts/smoke/fixtures/capture/tools.py"
TOOLS = ("grim", "slurp", "hyprpicker", "tesseract", "wl-copy", "gpu-screen-recorder", "ffmpeg", "pw-dump")


def service_rectangles():
    """Hyprland's undrawn group tab must not reach either screenshot selector."""
    service = (HELPER.parent.parent / "Service.qml").read_text()
    capabilities = (REPO / "shell/Core/Capabilities.qml").read_text()
    start, end = "    function windowRectangles(clients, monitors) {\n", "\n    }\n\n    function outputRectangles()"
    assert service.count(start) == service.count(end) == 1, "window rectangle function boundary"
    body = service.split(start)[1].split(end)[0]
    start, end = "        compositor: ctx => {\n", "\n        },\n        configure:"
    assert capabilities.count(start) == capabilities.count(end) == 1, "compositor provider boundary"
    factory = capabilities.split(start)[1].split(end)[0]
    before = " && shell.compositor.onScreen(window, monitors)"
    assert body.count(before) == 1, "service drawn-window control"
    no_query = body.replace(before, "")
    before = "out.onScreen = (window, monitors) => Dispatch.onScreen(window, monitors);"
    assert factory.count(before) == 1, "compositor drawn-window control"
    no_delegate = factory.replace(before, "out.onScreen = (window, monitors) => true;")
    assert no_query != body and no_delegate != factory
    program = r'''
const path = require("path");
const input = JSON.parse(process.argv[1]);
const Dispatch = require(path.join(input.repo, "bin/lib/qml-library.js")).load(path.join(input.repo, "shell/Core/Dispatch.js"));
const base = { mapped: true, hidden: false, visible: true, monitor: 0, workspace: { id: 1, name: "1" }, at: [10, 20], size: [80, 60], focusHistoryID: 0 };
const clients = [
    { ...base, address: "shown" },
    { ...base, address: "group-background", visible: false },
    { ...base, address: "other-workspace", workspace: { id: 2, name: "2" } },
    { ...base, address: "covered-regular", monitor: 1, workspace: { id: 2, name: "2" } },
    { ...base, address: "shown-special", monitor: 1, workspace: { id: -3, name: "special:pad" } },
    { ...base, address: "closed-special", workspace: { id: -4, name: "special:closed" } },
    { ...base, address: "unmapped", mapped: false },
    { ...base, address: "hidden", hidden: true },
    { ...base, address: "zero-width", size: [0, 60] },
    { ...base, address: "zero-height", size: [80, 0] },
];
const monitors = [
    { id: 0, activeWorkspace: { id: 1 }, specialWorkspace: { id: 0, name: "" } },
    { id: 1, activeWorkspace: { id: 2 }, specialWorkspace: { id: -3, name: "special:pad" } },
];
function addresses(body, factory) {
    const compositor = new Function("Dispatch", "Compositor", "ctx", factory)(Dispatch, {}, { active: true });
    return new Function("clients", "monitors", "shell", body)(clients, monitors, { compositor }).map(window => window.address);
}
const expected = JSON.stringify(["shown", "shown-special"]);
console.log(JSON.stringify([
    addresses(input.body, input.factory),
    JSON.stringify(addresses(input.no_query, input.factory)) === expected,
    JSON.stringify(addresses(input.body, input.no_delegate)) === expected,
]));
'''
    payload = dict(repo=str(REPO), body=body, factory=factory, no_query=no_query, no_delegate=no_delegate)
    result = subprocess.run(["node", "-e", program, json.dumps(payload)], stdin=subprocess.DEVNULL, capture_output=True, text=True, env={"PATH": os.defpath, "LC_ALL": "C"}, timeout=10)
    assert result.returncode == 0, result.stderr
    actual, query_control, delegate_control = json.loads(result.stdout)
    assert actual == ["shown", "shown-special"], ("drawn screenshot windows", actual)
    assert not query_control, "omitting the drawn-window query must fail the same candidate readback"
    assert not delegate_control, "bypassing Dispatch.onScreen must fail the same candidate readback"


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
    """The service's request with the manifest's default settings."""
    return {"action": action, "output": "NESTED", "folder": str(root / "pictures"), "recordFolder": str(root / "videos"), "audio": "desktop", "smart": False,
            "quality": "very_high", "frameRate": 60, "codec": "auto", "constantFrameRate": True, "recordCursor": False, "audioSources": [],
            "webcam": False, "webcamDevice": "", "postProcess": True, "ocrLanguages": "eng", "stateDir": str(root / "state"),
            "viewer": "imv %f", "editor": "satty --filename %f --output-filename %f", "player": "mpv %f",
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


def worker(root, payload, helper=HELPER, recording=False, line=None, timeout=10, ready="slurp-ready"):
    """Run the helper with its control pipe held open, as the service holds it.

    LINE is written once the READY marker exists; recording writes `stop`.
    A helper still running after TIMEOUT is killed and answers None.
    """
    config = json.loads((root / "config.json").read_text())
    control, writer = os.pipe()
    proc = subprocess.Popen([sys.executable, str(helper), json.dumps(payload)], env=environment(root, config), stdin=control, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    os.close(control)
    try:
        if line is not None:
            wait_for(root / ready, proc)
            os.write(writer, line.encode())
        if recording:
            wait_for(root / "recorder-ready", proc)
            try:
                os.write(writer, b"stop\n")
            except BrokenPipeError:
                # The helper already ended, as after a recorder failure.
                pass
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


def language_data_error_holds(root, helper, languages="eng"):
    """An installed OCR tool without a language's data reports its cause and keeps the clipboard."""
    (root / "clipboard").write_bytes(b"previous clipboard")
    payload = request(root, "text")
    payload["ocrLanguages"] = languages
    code, output, err = worker(root, payload, helper)
    return (code == 1 and len(output) == 1 and output[0]["event"] == "error"
            and output[0].get("reason") == "language-data-unavailable"
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
        ("empty-selection-accepted", 'if mode in ("window", "display") and not boxes:', 'if False:', "empty-selection"),
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

TUI = HELPER.parent.parent / "tui/install-languages.sh"
WEBCAM = ";x=74%;y=69%;width=22%;height=22%;camera_fps=30"
OUTPUTS = [{"x": -160, "y": -40, "width": 160, "height": 240, "name": "LEFT", "scale": 1, "transform": 0},
           {"x": 0, "y": 20, "width": 320, "height": 180, "name": "NESTED", "scale": 1, "transform": 0}]
WINDOW = {"x": 10, "y": 20, "width": 80, "height": 60, "address": "0x1"}


def tool_calls(root, tool):
    return [row["args"] for row in calls(root) if row["tool"] == tool]


def option(args, flag):
    return args[args.index(flag) + 1] if args is not None and flag in args else None


def recorded(root, payload, helper):
    """One recording stopped once it writes: (exit, events, recorder argv, stderr)."""
    code, messages, err = worker(root, payload, helper, recording=True)
    argv = tool_calls(root, "gpu-screen-recorder")
    return code, messages, argv[-1] if argv else None, err


def target_holds(root, helper, payload, target, region, slurp, boxes):
    """The recorder's -w and -region for one mode; SLURP is None for no
    selector, "slurp" for offered boxes, or the flag that limits them."""
    code, messages, argv, err = recorded(root, payload, helper)
    slurps = tool_calls(root, "slurp")
    if slurp is None:
        selector = not slurps and not tool_calls(root, "hyprpicker")
    else:
        offered = (root / "slurp-input").read_text() if (root / "slurp-input").exists() else None
        selector = len(slurps) == 1 and [arg for arg in slurps[0] if arg in ("-r", "-o")] == ([] if slurp == "slurp" else [slurp]) and offered == boxes
    return (code == 0 and messages[-1]["event"] == "saved" and argv[:2] == ["-w", target]
            and option(argv, "-region") == region and selector)


def mode_cases():
    """Function 12: each record action's argv; a box equal to an output records it."""
    window = "region|v4l2:/dev/video7" + WEBCAM
    windows, outputs = "10,20 80x60\n", "-160,-40 160x240\n0,20 320x180\n"
    return [
        # name, action, extra, slurp geometry, -w, -region, selector, offered boxes
        ("record-smart-window", "record", {"smart": True}, "30,40 1x1", "region", "80x60+10+20", "slurp", windows + outputs),
        ("record-smart-output", "record", {"smart": True}, "250,40 1x1", "NESTED", None, "slurp", windows + outputs),
        ("record-area", "record", {}, "30,40 5x4", "region", "5x4+30+40", "-o", ""),
        ("record-area-output", "record", {}, "0,20 320x180", "NESTED", None, "-o", ""),
        ("record-window", "record-window", {}, "10,20 80x60", "region", "80x60+10+20", "-r", windows),
        ("record-display", "record-display", {}, "-160,-40 160x240", "LEFT", None, "-r", outputs),
        ("record-output", "record-output", {}, None, "NESTED", None, None, None),
        ("record-portal", "record-portal", {}, None, "portal", None, None, None),
        ("record-webcam", "record", {"webcam": True}, "30,40 5x4", window, "5x4+30+40", "-o", ""),
        ("record-output-webcam", "record-output", {"webcam": True, "webcamDevice": "/dev/video7"}, None, "NESTED|v4l2:/dev/video7" + WEBCAM, None, None, None),
    ]


def options_cases():
    """Functions 13 and 14: quality, frame rate, codec, frame rate mode and pointer."""
    return [
        ("defaults", {}, {"-q": "very_high", "-f": "60", "-k": "auto", "-fm": "cfr", "-cursor": "no"}),
        ("chosen", {"quality": "ultra", "frameRate": 144, "codec": "hevc", "constantFrameRate": False, "recordCursor": True},
         {"-q": "ultra", "-f": "144", "-k": "hevc", "-fm": "vfr", "-cursor": "yes"}),
    ]


def options_hold(root, helper, extra, wanted):
    payload = request(root, "record-output")
    payload.update(extra)
    code, messages, argv, err = recorded(root, payload, helper)
    return code == 0 and argv is not None and {flag: option(argv, flag) for flag in wanted} == wanted


def audio_holds(root, helper, audio, sources, wanted):
    """Function 15: one -a per source, the audio choice first, aac whenever any."""
    payload = request(root, "record-output")
    payload.update(audio=audio, audioSources=sources)
    code, messages, argv, err = recorded(root, payload, helper)
    if code != 0 or argv is None:
        return False
    given = [argv[i + 1] for i, arg in enumerate(argv) if arg == "-a"]
    return given == wanted and (option(argv, "-ac") == "aac") == bool(wanted)


def refused_before_recorder(root, helper, payload, reason):
    """A device refusal comes before any selection, file or recorder."""
    code, messages, err = worker(root, payload, helper, timeout=5)
    return (code == 1 and messages[-1].get("reason") == reason and not tool_calls(root, "gpu-screen-recorder")
            and not tool_calls(root, "slurp") and not tool_calls(root, "hyprpicker")
            and not list((root / "videos").glob("*.mp4")))


def probe_holds(root, helper, languages, missing):
    """Functions 15, 16 and 22: the offered sources and cameras and the missing languages."""
    code, messages, err = worker(root, {"action": "probe", "ocrLanguages": languages}, helper, timeout=5)
    if code != 0 or [m["event"] for m in messages] != ["probe"]:
        return False
    event = messages[0]
    return (event["devices"] == {"audioSources": [{"label": "Fixture microphone", "value": "device:fixture-mic"},
                                                  {"label": "Monitor of Fixture speaker", "value": "device:fixture-speaker.monitor"}],
                                 "cameras": [{"label": "Fixture camera", "value": "/dev/video7"}]}
            and event["languages"] == {"missing": missing}
            and tool_calls(root, "pw-dump") == [[]] and tool_calls(root, "tesseract") == [["--list-langs"]])


def portal_cancel_holds(root, helper):
    """Function 17: a cancel while the picker is open ends the recorder with no file."""
    code, messages, err = worker(root, request(root, "record-portal"), helper, line="cancel\n", ready="picker-ready", timeout=5)
    pid = (root / "picker-ready").read_text() if (root / "picker-ready").exists() else None
    return (code == 0 and [m["event"] for m in messages] == ["cancelled"] and option(tool_calls(root, "gpu-screen-recorder")[-1], "-w") == "portal"
            and not list((root / "videos").glob("*")) and (root / "signal").read_text() == str(signal.SIGINT) and pid is not None
            and not alive(root, "gpu-screen-recorder"))


def saved_holds(root, helper, audio="desktop", post=True):
    """Functions 18, 19 and 20: stopped before post-processing, then saved with
    the trimmed file, its thumbnail and its URI on the clipboard."""
    payload = request(root, "record-output")
    payload.update(audio=audio, postProcess=post)
    code, messages, argv, err = recorded(root, payload, helper)
    events = [m["event"] for m in messages]
    if code != 0 or events[-3:] != ["recording", "stopped", "saved"]:
        return False
    saved = messages[-1]
    path = Path(saved["path"])
    state = root / "state/plugins/vgs.capture"
    ffmpeg = tool_calls(root, "ffmpeg")
    processing = [args for args in ffmpeg if "-frames:v" not in args]
    thumbnail = [args for args in ffmpeg if "-frames:v" in args]
    trim = ["-ss", "0.1", "-i", str(path), "-map", "0:v:0"]
    if post:
        temp = Path(processing[0][-1]) if len(processing) == 1 else None
        audio_args = ["-map", "0:a?", "-c:v", "copy", "-af", "loudnorm=I=-14:TP=-1.5:LRA=11", "-ar", "48000", "-c:a", "aac", "-b:a", "192k"] if audio != "none" else ["-c:v", "copy", "-an"]
        if (temp is None or processing[0][processing[0].index("-ss"):-1] != trim + audio_args or temp.parent != path.parent
                or not temp.name.startswith(".screencast-processing-") or temp.exists() or saved["processing"] != "done"):
            return False
    elif processing or saved["processing"] != "off":
        return False
    clipboard = (root / "clipboard").read_bytes() if (root / "clipboard").exists() else b""
    return (path.read_bytes() == b"finalized" and saved["thumbnail"] == str(state / "thumbnails" / (path.stem + ".jpg"))
            and Path(saved["thumbnail"]).read_bytes().startswith(b"\xff\xd8\xff") and len(thumbnail) == 1
            and clipboard == (path.as_uri() + "\r\n").encode() and tool_calls(root, "wl-copy")[-1] == ["--foreground", "--type", "text/uri-list"]
            and stat_mode(state) == 0o700 and stat_mode(state / "recorder.log") == 0o600
            and "fixture recorder started" in (state / "recorder.log").read_text() and "fixture recorder" not in err)


def stat_mode(path):
    return path.stat().st_mode & 0o777


def processing_failure_holds(root, helper):
    """Function 18: a failed post-process keeps the recording whole and says so with the log's end."""
    code, messages, argv, err = recorded(root, request(root, "record-output"), helper)
    saved = messages[-1] if messages else {}
    return (code == 0 and saved.get("event") == "saved" and saved["processing"] == "failed" and "fixture ffmpeg failure" in saved["detail"]
            and Path(saved["path"]).read_bytes() == b"finalized" and not list((root / "videos").glob(".screencast-processing-*")))


class Lines:
    """JSON lines from a helper's stdout, read straight from its pipe so a
    zero-timeout read sees every line already written."""

    def __init__(self, stream):
        self.fd, self.buffer, self.closed = stream.fileno(), b"", False

    def read(self, timeout):
        ready, _, _ = select.select([self.fd], [], [], timeout)
        if ready:
            chunk = os.read(self.fd, 65536)
            self.closed = not chunk
            self.buffer += chunk
        *lines, self.buffer = self.buffer.split(b"\n")
        return [json.loads(line) for line in lines]


def held_processing(root, helper):
    """A recording whose post-process the stand-in ffmpeg holds half way:
    (process, its line reader, its events, the recording or None)."""
    config = json.loads((root / "config.json").read_text())
    proc = subprocess.Popen([sys.executable, str(helper), json.dumps(request(root, "record-output"))], env=environment(root, config),
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    lines, events = Lines(proc.stdout), []
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline and not (root / "ffmpeg-ready").exists() and not lines.closed:
        for event in lines.read(0.05):
            events.append(event)
            if event["event"] == "recording":
                proc.stdin.write(b"stop\n")
                proc.stdin.flush()
    if (root / "ffmpeg-ready").exists():
        # Lines written before the hold: stopped must be the last of them.
        events += lines.read(0)
    stopped = bool(events) and events[-1]["event"] == "stopped" and (root / "ffmpeg-ready").exists()
    return proc, lines, events, Path(events[-1]["path"]) if stopped else None


def next_recording(root, helper, **config):
    """Another recording in the same world, as the service starts the next capture."""
    world_config = json.loads((root / "config.json").read_text())
    (root / "config.json").write_text(json.dumps({**world_config, **config}))
    (root / "recorder-ready").unlink(missing_ok=True)
    return recorded(root, request(root, "record-output"), helper)


def killed_processing_holds(root, helper, signum):
    """Function 18: stopped reaches the service before the post-process; a
    recording started meanwhile leaves the live output alone; a kill half way
    keeps the recording whole and the next start removes the output; SIGTERM
    ends the worker promptly with no ffmpeg left."""
    proc, lines, events, first = held_processing(root, helper)
    try:
        temps = list((root / "videos").glob(".screencast-processing-*"))
        if first is None or len(temps) != 1:
            return False
        if signum == signal.SIGKILL:
            code, messages, argv, err = next_recording(root, helper, ffmpegHold=False)
            if code != 0 or not temps[0].exists():
                return False
        proc.send_signal(signum)
        try:
            proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            return False
        deadline = time.monotonic() + 5
        while alive(root, "ffmpeg") and time.monotonic() < deadline:
            time.sleep(0.01)
        if alive(root, "ffmpeg") or first.read_bytes() != b"finalized":
            return False
        if signum == signal.SIGTERM:
            return not temps[0].exists()
        if not temps[0].exists():
            return False
        code, messages, argv, err = next_recording(root, helper)
        return code == 0 and not temps[0].exists() and first.read_bytes() == b"finalized"
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.communicate(timeout=5)


def own_log_holds(root, helper):
    """Function 20: a post-process that fails after the next recording started
    shows its own recording's log lines, never the next one's."""
    proc, lines, events, first = held_processing(root, helper)
    try:
        if first is None:
            return False
        code, messages, argv, err = next_recording(root, helper, ffmpegHold=False, ffmpegFail=False)
        if code != 0:
            return False
        second = Path(messages[-1]["path"])
        (root / "ffmpeg-release").touch()
        deadline = time.monotonic() + 5
        while not lines.closed and time.monotonic() < deadline:
            events += lines.read(0.05)
        proc.wait(timeout=5)
        saved = events[-1]
        return (saved["event"] == "saved" and saved["path"] == str(first) and saved["processing"] == "failed"
                and first.name in saved["detail"] and "fixture ffmpeg failure" in saved["detail"] and second.name not in saved["detail"]
                and first.read_bytes() == b"finalized")
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.communicate(timeout=5)


def portal_exit_holds(root, helper):
    """Function 17: Cancel in the portal's picker ends the recorder with exit 60: no file and no notice."""
    code, messages, err = worker(root, request(root, "record-portal"), helper, timeout=5)
    return code == 0 and [m["event"] for m in messages] == ["cancelled"] and not list((root / "videos").glob("*"))


def service_function(source, name):
    start = "    function " + name + "("
    assert source.count(start) == 1, "service function boundary: " + name
    body = source[source.index(start):]
    return body[:body.index("\n    }\n") + 6]


def service_notices(source=None):
    """Function 20: Service.qml's notification argv for saved and copied
    captures and its error toasts, run in node with a stand-in toast
    capability. Answers whether every case holds."""
    source = source if source is not None else (HELPER.parent.parent / "Service.qml").read_text()
    functions = "\n".join(service_function(source, name) for name in ("isRecord", "notice", "errorNotice", "noticeCommand"))
    program = r'''
const input = JSON.parse(process.argv[1]);
const shown = [];
const shell = { toasts: { show: toast => shown.push(toast) } };
const api = new Function("shell", "helperPath", input.functions + "; return { noticeCommand, errorNotice };")(shell, "/helper/capture.py");
const record = { actionName: "record-output" };
const actions = [{ id: "default", label: "Open", argv: ["imv", "/pictures/a.png"] }, { id: "edit", label: "Edit", argv: ["satty", "/pictures/a.png"] }];
const commands = [
    api.noticeCommand({ actionName: "screenshot-area" }, { event: "saved", path: "/pictures/a.png", actions: actions }, 41),
    api.noticeCommand(record, { event: "saved", path: "/videos/a.mp4", thumbnail: "/state/a.jpg", processing: "failed", detail: "fixture tail line", actions: [] }, 41),
    api.noticeCommand(record, { event: "saved", path: "/videos/b.mp4", thumbnail: "", processing: "done", detail: "", actions: [actions[0]] }, 41),
    api.noticeCommand({ actionName: "text" }, { event: "copied" }, 41),
    api.noticeCommand({ actionName: "screenshot" }, { event: "copied" }, 41),
];
api.errorNotice({ reason: "language-data-unavailable", message: "no deu data" });
api.errorNotice({ message: "Recording failed (exit 1)\nfixture recorder crash" });
console.log(JSON.stringify([commands, shown]));
'''
    result = subprocess.run(["node", "-e", program, json.dumps({"functions": functions})], stdin=subprocess.DEVNULL, capture_output=True, text=True,
                            env={"PATH": os.defpath, "LC_ALL": "C"}, timeout=10)
    assert result.returncode == 0, result.stderr
    (screenshot, failed, done, text, copied), (language, crash) = json.loads(result.stdout)
    owned = ["python3", "/helper/capture.py", "--owned", str(int(signal.SIGINT)), "41", "notify-send", "--print-id", "--app-name=Capture"]
    styled = ["--hint=string:x-vgs-icon:camera", "--hint=string:x-vgs-tone:success"]
    pairs = ["--action=default=Open", "--action=edit=Edit"]
    return (notice_shape(screenshot, owned, styled + ["--hint=string:image-path:/pictures/a.png"], pairs, "/pictures/a.png")
            and notice_shape(failed, owned, styled + ["--hint=string:image-path:/state/a.jpg"], [], "/videos/a.mp4")
            and failed[-1].endswith("\nfixture tail line")
            and notice_shape(done, owned, styled, pairs[:1], "/videos/b.mp4")
            and notice_shape(text, owned, styled, [], None)
            and notice_shape(copied, owned, styled, [], None)
            and language["tone"] == crash["tone"] == "danger" and language["icon"] == crash["icon"] == "camera"
            and language["title"] != crash["title"]
            and language["message"] == "no deu data" and crash["message"] == "Recording failed (exit 1)\nfixture recorder crash")


def notice_shape(command, owned, hints, actions, path):
    """Whether COMMAND is OWNED, then exactly HINTS in any order and ACTIONS
    in button order, then `--`, a title and a body that starts with the
    saved PATH. The title and body wording is the service's to change."""
    options = command[len(owned):-3]
    body = command[-1]
    return (command[:len(owned)] == owned and command[-3] == "--" and isinstance(command[-2], str) and command[-2] != ""
            and sorted(item for item in options if item.startswith("--hint=")) == sorted(hints)
            and [item for item in options if item.startswith("--action=")] == actions
            and len(options) == len(hints) + len(actions)
            and isinstance(body, str) and body != ""
            and (path is None or body == path or body.startswith(path + "\n")))


def notice_command(source, root, parent):
    """Service.qml's notification argv for a saved screenshot with one
    button, as a child of PARENT."""
    program = r'''
const input = JSON.parse(process.argv[1]);
const api = new Function("helperPath", input.functions + "; return { noticeCommand };")(input.helper);
console.log(JSON.stringify(api.noticeCommand({ actionName: "screenshot" }, { event: "saved", path: input.path, actions: [{ id: "default", label: "Open", argv: ["imv", input.path] }] }, input.parent)));
'''
    functions = "\n".join(service_function(source, name) for name in ("isRecord", "noticeCommand"))
    payload = {"functions": functions, "helper": str(HELPER), "path": str(root / "a.png"), "parent": parent}
    result = subprocess.run(["node", "-e", program, json.dumps(payload)], stdin=subprocess.DEVNULL, capture_output=True, text=True,
                            env={"PATH": os.defpath, "LC_ALL": "C"}, timeout=10)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


# A notify-send stand-in that offers its buttons and waits, as notify-send
# waits for its notification to close: it records its pid, then the signal
# that ends the wait.
NOTIFY_STAND_IN = """#!{python}
import os, signal, sys
from pathlib import Path
root = Path({root!r})
def ended(signum, frame):
    (root / "notify-signal").write_text(str(signum))
    sys.exit(0)
signal.signal(signal.SIGINT, ended)
signal.signal(signal.SIGTERM, ended)
print(7, flush=True)
(root / "notify-pid").write_text(str(os.getpid()))
signal.pause()
"""


def notice_owner_holds(base, name, source):
    """The shell's end closes a waiting notification: the service's argv,
    started by a stand-in shell that is then killed, ends its notify-send
    with SIGINT, which closes the notification."""
    root = base / name
    (root / "bin").mkdir(parents=True)
    stand_in = root / "bin/notify-send"
    stand_in.write_text(NOTIFY_STAND_IN.format(python=sys.executable, root=str(root)))
    stand_in.chmod(0o755)
    shell = subprocess.Popen([sys.executable, "-c", "import json, subprocess, sys, signal\nsubprocess.Popen(json.loads(sys.stdin.readline()))\nsignal.pause()"],
                             env={"PATH": str(root / "bin") + os.pathsep + os.defpath, "LC_ALL": "C"}, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, text=True)
    pid = None
    try:
        command = notice_command(source, root, shell.pid)
        shell.stdin.write(json.dumps(command) + "\n")
        shell.stdin.flush()
        deadline = time.monotonic() + 5
        while not (root / "notify-pid").exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        pid = int((root / "notify-pid").read_text())
        shell.kill()
        shell.wait(timeout=5)
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline and not process_ended(pid):
            time.sleep(0.01)
        if process_ended(pid):
            pid = None
        signalled = root / "notify-signal"
        return pid is None and signalled.exists() and signalled.read_text() == str(int(signal.SIGINT))
    finally:
        if shell.poll() is None:
            shell.kill()
            shell.wait()
        if pid is not None:
            os.kill(pid, signal.SIGKILL)
            while not process_ended(pid):
                time.sleep(0.01)


def process_ended(pid):
    """Whether PID has exited; a child adopted by this subreaper is reaped."""
    try:
        return os.waitpid(pid, os.WNOHANG)[0] == pid
    except ChildProcessError:
        pass
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    return False


def open_with_holds(root, helper, action, installed, folder, wanted):
    """The worker's buttons for one saved or copied capture: WANTED lists
    (id, label, argv) with argv's "FILE" the saved path. INSTALLED names
    the stand-in programs on the worker's PATH; FOLDER holds the file."""
    for program in installed:
        stand_in = root / "bin" / program
        stand_in.write_text("#!/bin/sh\nexit 0\n")
        stand_in.chmod(0o755)
    payload = request(root, action)
    payload["folder"] = payload["recordFolder"] = str(root / folder)
    payload["editor"] = "satty --filename %f --output-filename %f"
    payload["viewer"] = "imv --title=%f %f"
    payload["player"] = "mpv"
    code, messages, err = worker(root, payload, helper, recording=action.startswith("record"))
    if code != 0 or not messages or messages[-1]["event"] not in ("saved", "copied"):
        return False
    last = messages[-1]
    if last["event"] == "copied":
        return "actions" not in last and wanted == []
    path = last["path"]
    expected = [{"id": i, "label": label, "argv": [path if word == "FILE" else word for word in argv]} for i, label, argv in wanted]
    return last["actions"] == expected


def open_with_cases():
    """Each row: name, action, installed programs, folder, and the buttons."""
    return [
        ("screenshot-tools", "screenshot", ("imv", "satty"), "pictures",
         [("default", "Open", ["imv", "--title=%f", "FILE"]), ("edit", "Edit", ["satty", "--filename", "FILE", "--output-filename", "FILE"])]),
        ("screenshot-spaced-path", "screenshot", ("imv", "satty"), "my pictures",
         [("default", "Open", ["imv", "--title=%f", "FILE"]), ("edit", "Edit", ["satty", "--filename", "FILE", "--output-filename", "FILE"])]),
        ("screenshot-no-editor", "screenshot", ("imv",), "pictures", [("default", "Open", ["imv", "--title=%f", "FILE"])]),
        ("screenshot-no-tools", "screenshot", (), "pictures", []),
        ("recording-player", "record-output", ("imv", "satty", "mpv"), "pictures", [("default", "Open", ["mpv", "FILE"])]),
        ("recording-no-player", "record-output", ("imv", "satty"), "pictures", []),
        ("text", "text", ("imv", "satty", "mpv"), "pictures", []),
    ]


def notification_functions(base, source, plant_world):
    """The buttons each finished capture offers, the shell's end closing a
    waiting notification, and the control that removes each."""
    def holds(name, helper):
        _, action, installed, folder, wanted = cases[name]
        return open_with_holds(plant_world(name + "-" + helper.stem), helper, action, installed, folder, wanted)
    cases = {case[0]: case for case in open_with_cases()}
    for name in cases:
        assert holds(name, HELPER), name
    def mutated(name, before, after):
        assert source.count(before) == 1, name
        changed = source.replace(before, after)
        assert changed != source, name
        helper = base / (name + ".py")
        helper.write_text(changed)
        return helper
    assert not holds("screenshot-no-editor", mutated("absent-tool-offered", "if not words or shutil.which(words[0]) is None:", "if not words:")), "control did not fail: absent-tool-offered"
    assert not holds("screenshot-tools", mutated("file-appended", 'if "%f" not in words:', "if True:")), "control did not fail: file-appended"
    assert not holds("screenshot-spaced-path", mutated("file-split", "return [str(path) if word == \"%f\" else word for word in words]", "return \" \".join(str(path) if word == \"%f\" else word for word in words).split()")), "control did not fail: file-split"
    service = (HELPER.parent.parent / "Service.qml").read_text()
    assert notice_owner_holds(base, "notice-owner", service), "the shell's end closes a waiting notification"
    before = '["python3", helperPath, "--owned", "2", String(parent), "notify-send"'
    assert service.count(before) == 1, "notice owner control match"
    assert not notice_owner_holds(base, "notice-unowned", service.replace(before, '["notify-send"')), "control did not fail: notice-unowned"
    return "absent-tool-offered,file-appended,file-split,notice-unowned"


def failure_log_holds(root, helper, reason):
    """Function 20: a failed start or a crash shows the end of the recorder log, which stays out of the worker's stderr."""
    code, messages, argv, err = recorded(root, request(root, "record-output"), helper)
    log = root / "state/plugins/vgs.capture/recorder.log"
    return (code == 1 and messages[-1]["event"] == "error" and reason in messages[-1]["message"] and reason in log.read_text()
            and reason not in err and stat_mode(log) == 0o600 and not list((root / "videos").glob("*.mp4")))


def text_holds(root, helper, languages):
    """Functions 21 and 22: Tesseract reads the chosen languages and keeps inter-word spaces."""
    payload = request(root, "text")
    payload["ocrLanguages"] = languages
    code, messages, err = worker(root, payload, helper)
    reads = tool_calls(root, "tesseract")
    return (code == 0 and messages[-1]["event"] == "copied" and len(reads) == 1 and option(reads[0], "-l") == languages
            and option(reads[0], "-c") == "preserve_interword_spaces=1")


def media(ffprobe, path):
    result = subprocess.run([ffprobe, "-v", "error", "-show_entries", "format=duration:stream=codec_type,codec_name", "-of", "json", str(path)],
                            stdin=subprocess.DEVNULL, capture_output=True, text=True, env={"PATH": os.defpath, "LC_ALL": "C"}, timeout=20)
    assert result.returncode == 0, result.stderr
    info = json.loads(result.stdout)
    return float(info["format"]["duration"]), sorted((s["codec_type"], s["codec_name"]) for s in info["streams"])


def real_processing(base, source):
    """Function 18 with the real ffmpeg on a 2 s fixture video this check makes:
    the saved file is 0.1 s shorter, its audio AAC, its thumbnail a JPEG.
    Answers the cause when ffmpeg or its lavfi source is absent, else None."""
    ffmpeg, ffprobe = shutil.which("ffmpeg"), shutil.which("ffprobe")
    if ffmpeg is None or ffprobe is None:
        return "ffmpeg-unavailable"
    fixture = base / "real-fixture.mp4"
    made = subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc=duration=2:size=160x120:rate=30",
                           "-f", "lavfi", "-i", "sine=frequency=440:duration=2", "-c:v", "mpeg4", "-g", "1", "-c:a", "aac", "-shortest", str(fixture)],
                          stdin=subprocess.DEVNULL, capture_output=True, env={"PATH": os.defpath, "LC_ALL": "C"}, timeout=60)
    if made.returncode != 0:
        return "lavfi-unavailable"
    def run(name, helper, audio):
        root = base / name
        plant(root, {"video": str(fixture)})
        (root / "bin/ffmpeg").unlink()
        (root / "bin/ffmpeg").symlink_to(ffmpeg)
        payload = request(root, "record-output")
        payload["audio"] = audio
        code, messages, argv, err = recorded(root, payload, helper)
        assert code == 0 and messages[-1]["event"] == "saved", (name, messages, err)
        thumbnail = Path(messages[-1]["thumbnail"]).read_bytes() if messages[-1]["thumbnail"] else b""
        return messages[-1]["processing"], *media(ffprobe, messages[-1]["path"]), thumbnail[:3] == b"\xff\xd8\xff"
    def trimmed(result, streams):
        processing, duration, codecs, thumbnail = result
        return processing == "done" and 1.8 <= duration <= 1.95 and codecs == streams and thumbnail
    assert media(ffprobe, fixture)[0] >= 1.99, "fixture video length"
    assert trimmed(run("real-audio", HELPER, "desktop"), [("audio", "aac"), ("video", "mpeg4")]), "real ffmpeg trim and loudness"
    assert trimmed(run("real-silent", HELPER, "none"), [("video", "mpeg4")]), "real ffmpeg drops audio"
    before = '"-ss", "0.1", '
    assert source.count(before) == 1, "trim control match"
    helper = base / "no-trim.py"
    helper.write_text(source.replace(before, ""))
    assert not trimmed(run("real-no-trim", helper, "desktop"), [("audio", "aac"), ("video", "mpeg4")]), "control did not fail: no-trim"
    return None


def languages_tui(base, script, name, manager, chosen, installed):
    """Run the language TUI against a stand-in core: (exit, stderr, pkg run argv)."""
    tree = base / ("tui-" + name)
    root = tree / "world"
    plant(root, {"languages": installed})
    (tree / "bin/lib").mkdir(parents=True)
    shutil.copyfile(REPO / "bin/lib/tui.sh", tree / "bin/lib/tui.sh")
    (tree / "bin/vgshell").write_text(f"""#!{sys.executable}
import json, sys
from pathlib import Path
root, args = Path({str(root)!r}), sys.argv[1:]
with (root / "vgshell.calls").open("a") as log:
    log.write(json.dumps(args) + "\\n")
if args == ["plugin", "settings", "vgs.capture"]:
    print(json.dumps({{"ocrLanguages": {chosen!r}}}))
elif args == ["plugin", "requirements", "--json", "vgs.capture"]:
    print(json.dumps([{{"command": "tesseract", "package": {{"manager": {manager!r}, "name": "tesseract"}}}}]))
elif args[:3] == ["pkg", "run", "install"]:
    config = json.loads((root / "config.json").read_text())
    config["languages"] += [package.rsplit("-", 1)[1] for package in args[5:]]
    (root / "config.json").write_text(json.dumps(config))
else:
    sys.exit("vgshell stand-in: " + " ".join(args))
""")
    (tree / "bin/vgshell").chmod(0o755)
    (root / "bin/gum").write_text("#!/bin/sh\nexit 0\n")
    (root / "bin/gum").chmod(0o755)
    (tree / "run").mkdir()
    env = {"PATH": str(root / "bin") + ":" + os.defpath, "HOME": str(tree), "XDG_RUNTIME_DIR": str(tree / "run"), "LC_ALL": "C",
           "VGS_TUI_LIB": str(tree / "bin/lib/tui.sh"), "VGS_PLUGIN_ID": "vgs.capture", "VGS_PLUGIN_DIR": str(HELPER.parent.parent), "VGS_TUI_UNATTENDED": "1"}
    result = subprocess.run(["bash", str(script)], env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
    runs = [json.loads(line) for line in (root / "vgshell.calls").read_text().splitlines()] if (root / "vgshell.calls").exists() else []
    return result.returncode, result.stderr, [run for run in runs if run[:2] == ["pkg", "run"]]


def language_tui_holds(base, script, suffix=""):
    """Function 22: the TUI installs each missing chosen language's package for this system's manager."""
    cases = [
        ("pacman", "pacman", "deu+eng", ["eng", "osd"], 0, [["pkg", "run", "install", "--manager", "pacman", "tesseract-data-deu"]]),
        ("dnf", "dnf", "deu+chi_sim+eng", ["eng", "osd"], 0, [["pkg", "run", "install", "--manager", "dnf", "tesseract-langpack-deu", "tesseract-langpack-chi_sim"]]),
        ("installed", "pacman", "eng", ["eng", "osd"], 0, []),
        ("nix", "nix", "deu+eng", ["eng", "osd"], 1, []),
    ]
    for name, manager, chosen, installed, status, runs in cases:
        code, err, ran = languages_tui(base, script, name + suffix, manager, chosen, installed)
        if code != status or ran != runs:
            return False
        if name == "nix" and "capture: languages=by-hand manager=nix codes=deu\n" not in err:
            return False
    return True


def recording_functions(base, source):
    """Functions 12 to 22, each with the control that removes it."""
    def world(name, **config):
        root = base / ("rec-" + name)
        plant(root, config)
        return root
    def mutated(name, before, after, count=1):
        assert source.count(before) == count, name
        changed = source.replace(before, after)
        assert changed != source, name
        helper = base / (name + ".py")
        helper.write_text(changed)
        return helper
    def mode_payload(root, action, extra):
        payload = request(root, action)
        payload.update(windows=[WINDOW], outputs=OUTPUTS, **extra)
        return payload
    modes = {case[0]: case for case in mode_cases()}
    def mode_holds(name, helper):
        _, action, extra, geometry, target, region, slurp, boxes = modes[name]
        root = world(name + "-" + helper.stem, **({"geometry": geometry} if geometry else {}))
        return target_holds(root, helper, mode_payload(root, action, extra), target, region, slurp, boxes)
    for name in modes:
        assert mode_holds(name, HELPER), name
    for name, case, before, after in [
        ("record-no-snap", "record-smart-window", 'picked = rectangle_geometry(target), tuple(str(target[k]) for k in ("x", "y", "width", "height"))', 'picked = picked'),
        ("record-no-output-match", "record-display", 'target = next((r["name"] for r in request["outputs"] if (r["x"], r["y"], r["width"], r["height"]) == (x, y, width, height)), None)', 'target = None'),
        ("record-window-boxes", "record-window", 'boxes = windows\n', 'boxes = outputs\n'),
        ("record-no-camera", "record-webcam", 'target += "|v4l2:" + camera + WEBCAM', 'pass'),
    ]:
        assert not mode_holds(case, mutated(name, before, after)), "control did not fail: " + name
    for name, extra, wanted in options_cases():
        assert options_hold(world("options-" + name), HELPER, extra, wanted), name
    payload = request(world("fractional-rate"), "record-output")
    payload["frameRate"] = 59.5
    assert refused_before_recorder(base / "rec-fractional-rate", HELPER, payload, "invalid-frame-rate"), "fractional frame rate"
    for name, before, after, check in [
        ("no-recorder-options", '*options, ', '', lambda helper: options_hold(world("no-options"), helper, *options_cases()[1][1:])),
        ("fixed-pointer", '"yes" if request["recordCursor"] else "no"', '"yes"', lambda helper: options_hold(world("fixed-pointer"), helper, *options_cases()[0][1:])),
        ("fractional-rate-accepted", 'raise CaptureFailure("invalid-frame-rate", "Invalid recording frame rate")', 'pass',
         lambda helper: refused_before_recorder(base / "rec-fractional-rate-control", helper, {**payload, "recordFolder": str(world("fractional-rate-control") / "videos")}, "invalid-frame-rate")),
    ]:
        assert not check(mutated(name, before, after)), "control did not fail: " + name
    sources = [{"name": "source-1", "source": "device:fixture-speaker.monitor"}, {"name": "source-2", "source": ""}]
    wanted = ["default_output", "device:fixture-speaker.monitor", "device:fixture-mic"]
    assert audio_holds(world("audio-sources"), HELPER, "desktop", sources, wanted), "audio sources"
    assert audio_holds(world("audio-none"), HELPER, "none", [], []), "no audio"
    assert refused_before_recorder(world("audio-unoffered", nodes=[]), HELPER, {**request(base / "rec-audio-unoffered", "record-output"), "audioSources": [{"name": "source-1", "source": ""}]}, "audio-unavailable"), "no offered source"
    assert not audio_holds(world("audio-dropped"), mutated("no-audio-sources", 'for item in request["audioSources"]:', 'for item in []:'), "desktop", sources, wanted), "control did not fail: no-audio-sources"
    assert probe_holds(world("probe", languages=["eng", "osd"]), HELPER, "deu+eng", ["deu"]), "probe"
    assert probe_holds(world("probe-ready", languages=["eng", "deu", "osd"]), HELPER, "deu+eng", []), "probe ready"
    assert not probe_holds(world("probe-control", languages=["eng", "osd"]), mutated("no-missing-check", 'report = {"missing": [code for code in dict.fromkeys(languages.split("+")) if code not in installed]}', 'report = {"missing": []}'), "deu+eng", ["deu"]), "control did not fail: no-missing-check"
    root = world("camera-absent")
    absent = {**request(root, "record"), "webcam": True, "webcamDevice": "/dev/video9"}
    assert refused_before_recorder(root, HELPER, absent, "camera-unavailable"), "absent camera"
    root = world("camera-absent-control")
    assert not refused_before_recorder(root, mutated("absent-camera", 'if camera not in cameras:', 'if False:'), {**absent, "recordFolder": str(root / "videos"), "stateDir": str(root / "state")}, "camera-unavailable"), "control did not fail: absent-camera"
    assert portal_cancel_holds(world("portal-cancel", picker=True), HELPER), "portal cancel"
    assert not portal_cancel_holds(world("portal-cancel-control", picker=True), mutated("picker-ignores-cancel", 'if line in ("", "cancel") or path.stat().st_size == 0:', 'if False:')), "control did not fail: picker-ignores-cancel"
    for name, audio, post in [("saved", "desktop", True), ("saved-silent", "none", True), ("saved-unprocessed", "desktop", False)]:
        assert saved_holds(world(name), HELPER, audio, post), name
    assert processing_failure_holds(world("processing-failure", ffmpegFail=True), HELPER), "processing failure keeps the recording"
    for signum in (signal.SIGKILL, signal.SIGTERM):
        assert killed_processing_holds(world("processing-" + signum.name, ffmpegHold=True), HELPER, signum), signum.name
    assert own_log_holds(world("own-log", ffmpegHold=True, ffmpegFail=True), HELPER), "each recording reads its own log"
    assert portal_exit_holds(world("portal-exit", portalCancel=True), HELPER), "portal picker cancel"
    assert service_notices(), "service notices"
    service = (HELPER.parent.parent / "Service.qml").read_text()
    for name, before, after in [
        ("notice-processing-ignored", 'event.processing === "failed"', 'false'),
        ("notice-detail-dropped", 'if (event.detail !== "") message += "\\n" + event.detail.slice(-Math.max(0, 199 - message.length));', ''),
        ("notice-reason-renamed", 'event.reason === "language-data-unavailable"', 'event.reason === "english-data-unavailable"'),
        ("notice-unstyled", '"--hint=string:x-vgs-icon:camera", "--hint=string:x-vgs-tone:success"]', ']'),
        ("notice-imageless", 'if (image !== "") command.push("--hint=string:image-path:" + image);', ''),
        ("notice-buttonless", 'for (const action of event.actions || []) command.push(', 'for (const action of []) command.push('),
        ("notice-unseparated", 'return command.concat(["--", title, message.slice(0, 200)]);', 'return command.concat([title, message.slice(0, 200)]);'),
        ("notice-pathless", 'message = event.path;', 'message = "";'),
    ]:
        assert service.count(before) == 1, name
        assert not service_notices(service.replace(before, after)), "control did not fail: " + name
    for name, before, after, check in [
        ("raw-replaced", 'if code or temp.stat().st_size == 0:', 'if temp.stat().st_size == 0:', lambda helper: processing_failure_holds(world("raw-replaced", ffmpegFail=True), helper)),
        ("kept-processing-output", 'remove_stale_processing(folder)\n', 'pass\n', lambda helper: killed_processing_holds(world("kept-output", ffmpegHold=True), helper, signal.SIGKILL)),
        ("unlocked-processing-output", 'fcntl.flock(fd, fcntl.LOCK_EX)', 'pass', lambda helper: killed_processing_holds(world("unlocked-output", ffmpegHold=True), helper, signal.SIGKILL)),
        ("stopped-after-processing", '            emit("stopped", path=str(path))\n', '', lambda helper: killed_processing_holds(world("late-stopped", ffmpegHold=True), helper, signal.SIGKILL)),
        ("untimed-processing-wait", 'code = self.wait(child)', 'code = child.wait()', lambda helper: killed_processing_holds(world("untimed-wait", ffmpegHold=True), helper, signal.SIGTERM)),
        ("shared-log", '    path.unlink(missing_ok=True)\n    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_APPEND | os.O_NOFOLLOW, 0o600)', '    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND | os.O_NOFOLLOW, 0o600)', lambda helper: own_log_holds(world("shared-log", ffmpegHold=True, ffmpegFail=True), helper)),
        ("portal-cancel-failure", 'if target.startswith("portal") and self.recorder.returncode == PORTAL_CANCELLED:', 'if False:', lambda helper: portal_exit_holds(world("portal-exit-control", portalCancel=True), helper)),
        ("no-uri-copy", 'child = self.copy(io.BytesIO((path.as_uri() + "\\r\\n").encode()), "text/uri-list")', 'child = self.spawn([sys.executable, "-c", "pass"])', lambda helper: saved_holds(world("no-uri-copy"), helper)),
        ("recorder-log-to-stderr", 'self.recorder = self.spawn(args, stdin=subprocess.DEVNULL, stdout=log, stderr=log)', 'self.recorder = self.spawn(args, stdin=subprocess.DEVNULL, stdout=log, stderr=sys.stderr)', lambda helper: saved_holds(world("log-to-stderr"), helper)),
        ("no-log-tail", 'return "\\n" + tail if tail else ""', 'return ""', lambda helper: failure_log_holds(world("no-log-tail", crash=True), helper, "fixture recorder crash: no encoder")),
    ]:
        assert not check(mutated(name, before, after)), "control did not fail: " + name
    assert failure_log_holds(world("crash", crash=True), HELPER, "fixture recorder crash: no encoder"), "crash log tail"
    assert failure_log_holds(world("start-failure", fail="gpu-screen-recorder"), HELPER, "fixture failure"), "failed start log tail"
    for name, languages in [("text-english", "eng"), ("text-german", "deu+eng")]:
        assert text_holds(world(name, languages=["eng", "deu", "osd"]), HELPER, languages), name
    root = world("text-invalid")
    payload = {**request(root, "text"), "ocrLanguages": "eng;deu"}
    code, messages, err = worker(root, payload)
    assert code == 1 and messages[-1].get("reason") == "invalid-languages" and not calls(root), "invalid languages"
    helper = mutated("invalid-languages-accepted", 'raise CaptureFailure("invalid-languages", "Invalid text recognition languages")', 'pass')
    root = world("text-invalid-control")
    code, messages, err = worker(root, {**request(root, "text"), "ocrLanguages": "eng;deu"}, helper)
    assert not (code == 1 and messages[-1].get("reason") == "invalid-languages" and not calls(root)), "control did not fail: invalid-languages-accepted"
    for name, before, after in [
        ("no-interword-spaces", ', "-c", "preserve_interword_spaces=1"', ''),
        ("english-only", '"-l", languages,', '"-l", "eng",'),
    ]:
        assert not text_holds(world(name + "-control", languages=["eng", "deu", "osd"]), mutated(name, before, after), "deu+eng"), "control did not fail: " + name
    assert language_tui_holds(base, TUI), "language TUI"
    script = TUI.read_text()
    before = 'print(*report["missing"])'
    assert script.count(before) == 1, "language TUI control match"
    control = base / "tui-no-missing-check.sh"
    control.write_text(script.replace(before, 'print("eng", *report["missing"])'))
    assert not language_tui_holds(base, control, "-control"), "control did not fail: tui-installs-installed"
    return ("record-no-snap,record-no-output-match,record-window-boxes,record-no-camera,no-recorder-options,fixed-pointer,fractional-rate-accepted,"
            "no-audio-sources,no-missing-check,absent-camera,picker-ignores-cancel,raw-replaced,kept-processing-output,stopped-after-processing,"
            "no-uri-copy,recorder-log-to-stderr,no-log-tail,invalid-languages-accepted,no-interword-spaces,english-only,tui-installs-installed,"
            "unlocked-processing-output,untimed-processing-wait,shared-log,portal-cancel-failure,notice-processing-ignored,notice-detail-dropped,notice-reason-renamed,"
            "notice-unstyled,notice-imageless,notice-buttonless,notice-unseparated,notice-pathless")


def main():
    config = {}
    output = "NESTED"
    dimensions = (320, 240)
    if len(sys.argv) > 1:
        assert sys.argv[1] == "--nested" and len(sys.argv) == 8
        real, output, width, height, display, runtime = sys.argv[2:]
        config = {"real": {"grim": real}, "display": display, "runtime": runtime}
        dimensions = (int(width), int(height))
    service_rectangles()
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
        recording_controls = recording_functions(base, source)
        notification_controls = notification_functions(base, source, world)
        unmeasured = real_processing(base, source)
        for name, installed, languages in [("english-data-missing", ["osd"], "eng"), ("german-data-missing", ["eng", "osd"], "deu+eng")]:
            root = world(name, languages=installed)
            assert language_data_error_holds(root, HELPER, languages), name
        before = "for pattern, reason, message in OCR_FAILURES:"
        assert source.count(before) == 1, "OCR error classification control match"
        changed = source.replace(before, "for pattern, reason, message in ():")
        assert changed != source
        helper = base / "raw-ocr-error.py"
        helper.write_text(changed)
        root = world("raw-ocr-error", languages=["eng"])
        assert not language_data_error_holds(root, helper, "deu+eng"), "control did not fail: raw OCR error"
        mutations = [
            ("no-output", 'args = ["grim", "-o", request["output"]]', 'args = ["grim"]', "screenshot"),
            ("no-clipboard", 'child = self.spawn(["wl-copy", "--foreground", "--type", mime], stdin=subprocess.PIPE, stderr=subprocess.PIPE)', 'child = self.spawn([sys.executable, "-c", "import sys; sys.stdin.buffer.read()"], stdin=subprocess.PIPE, stderr=subprocess.PIPE)', "screenshot"),
            ("hard-stop", 'self.recorder.send_signal(signal.SIGINT)\n                    stopping = True', 'self.recorder.send_signal(signal.SIGKILL)\n                    stopping = True', "record"),
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
    if unmeasured is None:
        recording_controls += ",no-trim"
    controls = ("undrawn-windows,drawn-window-delegate,raw-ocr-error,no-output,no-clipboard,hard-stop,inherited-stdin,kept-freeze,unowned-child,invalid-delay-accepted,invalid-timeout-accepted,invalid-processing-accepted,empty-selection-accepted,empty-displays-accepted,smart-snap,window-boxes,display-boxes,all-bounds,no-scale,no-rotation,no-cursor,copy-saves,save-copies,no-delay,delay-ignores-cancel,no-timeout,no-selection-end," + recording_controls + "," + notification_controls)
    if unmeasured is not None:
        # The rest passed, but the real post-process could not run: not a pass.
        print(f"test-capture: status=not-measured cause={unmeasured}; controls={controls}")
        sys.exit(77)
    print("test-capture: pass; controls=" + controls)


if __name__ == "__main__":
    main()
