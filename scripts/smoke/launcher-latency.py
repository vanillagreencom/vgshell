#!/usr/bin/env python3
"""Disposable launcher observation and guarded capture controller.

prepare TREE [--slow] instruments only a harness copy. measure KEYBOARD PID
SOCKET FIELD_JSON LEFT_PADDING_JSON SURFACE_JSON OUTPUT takes twelve separate 50 ms o presses.
The first includes provider loading. Later presses retain the provider cache
but clear the display model. summary.json and per-trial PPM/JSON files retain
request-to-first-changed-glyph capture-return upper bounds, not presentation.

Reuses Phase 1 diagnosis-measure.py's keyboard/shot_grim correlation. A
frameSwapped signal is deliberately not a measurement: it can precede paint.
"""
import argparse
import json
import math
import os
from pathlib import Path
import re
import subprocess
import threading
import time


def replace_once(path, old, new):
    if path.is_symlink():
        raise ValueError(f"instrument: symlink={path}")
    text = path.read_text()
    if text.count(old) != 1 or old == new:
        raise ValueError(f"instrument: match-count={text.count(old)} path={path}")
    path.write_text(text.replace(old, new))


def prepare(tree, slow):
    launcher = tree / "shell/plugins/vgs.launcher/Launcher.qml"
    replace_once(launcher, "    id: root\n", """    id: root
    property var latencyEvents: []
    function latencyNote(kind, details) {
        latencyEvents.push(Object.assign({kind: kind, at: Date.now()}, details));
    }
    function latencyReset() {
        latencyEvents = [];
        return "reset";
    }
    function latencyClear() {
        setFilter("");
        return "cleared";
    }
    function latencyFixtureRows() {
        let count = 0;
        for (let i = 0; i < displayModel.count; i++) {
            const item = items[displayModel.get(i).itemId];
            if (item && (item.appId || "").indexOf("vgs-latency-o-") === 0) count++;
        }
        return count;
    }
    function latencyAppsLoaded() {
        const ids = itemOrder.filter(id => items[id].provider === "apps");
        return ids.length > 0 && ids.every(id => providersLoaded[id] === true);
    }
    function latencyRead() {
        // DesktopEntries is the actual Application model, not a row proxy:
        // https://quickshell.org/docs/v0.3.1/types/Quickshell/DesktopEntries/
        const apps = DesktopEntries.applications.values;
        const fixture = id => id.indexOf("vgs-latency-o-") === 0;
        return JSON.stringify({events: latencyEvents, text: filterText,
            apps: apps.length, fixtureApps: apps.filter(a => fixture(a.id)).length,
            items: itemOrder.length, rows: displayModel.count, fixtureRows: latencyFixtureRows(),
            providers: Object.keys(providersLoaded), mode: mode, fileMode: fileMode,
            appProviderWarm: latencyAppsLoaded(),
            // Character-position rectangles read the field without moving its cursor:
            // https://doc.qt.io/qt-6/qml-qtquick-textinput.html#positionToRectangle-method
            firstGlyphAdvance: filterText.length === 0 ? null :
                field.positionToRectangle(1).x - field.positionToRectangle(0).x,
            menusReady: menusReady, theme: Theme.name, themeState: Theme.fileState,
            look: {palette: look.palette, card: look.card, highlight: look.highlight},
            hintGround: hintBackgroundContext});
    }
""")
    replace_once(launcher, "    function setFilter(next) {\n", """    function setFilter(next) {
        latencyNote("filter-begin", {text: next, appProviderWarm: latencyAppsLoaded()});
""")
    replace_once(launcher, "        rebuildDisplay();\n    }\n\n    function setActiveMenu",
                 """        rebuildDisplay();
        latencyNote("filter-end", {text: filterText, rows: displayModel.count, fixtureRows: latencyFixtureRows()});
    }

    function setActiveMenu""")
    replace_once(launcher, """                    Keys.onPressed: event => {
                        event.accepted = root.handleKey(event);
                    }
""", """                    Keys.onPressed: event => {
                        // Qt's flag distinguishes auto-repeat from another down:
                        // https://doc.qt.io/qt-6/qml-qtquick-keyevent.html#isAutoRepeat-prop
                        root.latencyNote("press", {key: event.key, text: event.text, repeat: event.isAutoRepeat});
                        event.accepted = root.handleKey(event);
                    }
                    Keys.onReleased: event => {
                        root.latencyNote("release", {key: event.key, text: event.text, repeat: event.isAutoRepeat});
                        event.accepted = false;
                    }
""")
    if slow:
        theme = tree / "shell/Commons/Theme.qml"
        text = theme.read_text()
        # Restore the diagnosed repeated solve, not a delayed input handler.
        # The four-space closing brace belongs to this Theme member.
        pattern = r"^    function keyHintInk\(context, part\) \{.*?^    \}"
        old = re.findall(pattern, text, re.M | re.S)
        if len(old) != 1:
            raise ValueError("control: keyHintInk member not uniquely found")
        restored = """    function keyHintInk(context, part) {
        const colors = context === null ? null : {
            fill: Qt.color(context.fill), plate: Qt.color(context.plate), sheen: Qt.color(context.sheen)
        };
        return toColor(ThemeLogic.formatColor(ThemeLogic.keyHintInk(source.values, colors, part)));
    }"""
        replace_once(theme, old[0], restored)


def ppm(data):
    header = data.split(b"\n", 3)
    if len(header) != 4 or header[0] != b"P6" or header[2] != b"255":
        raise ValueError("capture: invalid-ppm")
    width, height = map(int, header[1].split())
    if width != 12 or height <= 0 or len(header[3]) != width * height * 3:
        raise ValueError("capture: invalid-geometry")
    return header[3]


def first_glyph(baseline, final, captures, glyph_columns):
    """Judge only the actual first character, not an adjacent animated caret."""
    if type(glyph_columns) is not int or not 1 <= glyph_columns <= 12:
        raise ValueError("capture: unread-first-glyph-width")
    channels = [i for i, (a, b) in enumerate(zip(baseline, final))
                if abs(a - b) >= 40 and (i // 3) % 12 < glyph_columns]
    if len(baseline) != len(final) or len(channels) < 12:
        raise ValueError("capture: missing-glyph-discriminator")
    separation = sum(abs(final[i] - baseline[i]) for i in channels)
    for capture in captures:
        pixels = capture["pixels"]
        if len(pixels) != len(final):
            raise ValueError("capture: changed-geometry")
        capture["finalErrorRatio"] = sum(abs(pixels[i] - final[i]) for i in channels) / separation
    matching = next((i for i, c in enumerate(captures) if c["finalErrorRatio"] <= 0.10), None)
    if matching is None:
        raise ValueError("capture: no-changed-glyph")
    return matching, len(channels)


def context():
    return {name: Path("/proc", name).read_text().strip() for name in
            ("loadavg", "pressure/cpu", "pressure/memory", "pressure/io")}


def cpu_total(reading):
    return int(re.search(r"^some .* total=(\d+)$", reading["pressure/cpu"], re.M)[1])


def glyph_geometry(field_json, padding_json, surface_json):
    """Map the actual TextField text start, not its leading icon, to the output."""
    try:
        field = json.loads(field_json)
        padding = json.loads(padding_json)
        surface = json.loads(surface_json)
    except (TypeError, json.JSONDecodeError) as error:
        raise ValueError("capture: unread-text-field-geometry") from error
    if (not isinstance(field, list) or len(field) != 4
            or not isinstance(surface, list) or len(surface) != 4):
        raise ValueError("capture: invalid-text-field-box")
    if any(type(v) not in (int, float) or not math.isfinite(v)
           for v in [*field, *surface, padding]):
        raise ValueError("capture: invalid-text-field-reading")
    if (padding < 0 or field[2] < padding + 12 or round(field[3]) < 1
            or surface[2] <= 0 or surface[3] <= 0):
        raise ValueError("capture: text-start-outside-field")
    # TextField inherits TextInput: leftPadding is reserved before its content,
    # not an icon-size estimate. Qt reference and Ui.TextField's placeholder.x:
    # https://doc.qt.io/qt-6/qml-qtquick-textinput.html#leftPadding-prop
    x = round(surface[0] + field[0] + padding)
    y = round(surface[1] + field[1])
    return f"{x},{y} 12x{round(field[3])}"


def measure(args):
    out = args.output
    geometry = glyph_geometry(args.field, args.padding, args.surface)
    out.mkdir(exist_ok=False)
    socket = Path(os.environ["XDG_RUNTIME_DIR"]) / os.environ["WAYLAND_DISPLAY"]
    if str(socket) != args.socket or not socket.is_socket():
        raise ValueError("input: socket-not-nested")
    # shell_env is the harness's explicit, scrubbed child environment.
    env = dict(os.environ)
    fifo = out / "keyboard.fifo"
    os.mkfifo(fifo)
    commands = os.open(fifo, os.O_RDWR | os.O_NONBLOCK)
    keylog = (out / "keyboard.log").open("wb")
    keyproc = subprocess.Popen([args.keyboard, str(fifo), "us", ""],
                               stdout=keylog, stderr=subprocess.STDOUT, env=env)

    def wait_key(text, offset=0):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if text in (out / "keyboard.log").read_text()[offset:]:
                return
            if keyproc.poll() is not None:
                raise RuntimeError("keyboard: exited")
            time.sleep(0.005)
        raise TimeoutError(f"keyboard: no-ack={text}")

    def invoke(name, argument=""):
        run = subprocess.run(["qs", "ipc", "--pid", args.pid, "call", "smoke",
                              "invokeInstance", "overlay", "vgs.launcher", name, argument],
                             capture_output=True, text=True, timeout=10, check=True, env=env)
        # These private replies are bounded JSON or the literal reset; errors,
        # paging or an absent reply cannot become a reading.
        lines = run.stdout.strip().splitlines()
        if not lines:
            raise ValueError(f"ipc: empty-reply function={name}")
        return lines[-1]

    def read():
        return json.loads(invoke("latencyRead"))

    def snap(path):
        start = time.monotonic_ns() / 1e6
        run = subprocess.run(["/usr/bin/bash", "-c",
            'source "$1"; shot_grim "$2" "$3" -s 1 -g "$4" -t ppm -',
            "_", str(Path(__file__).with_name("shot.sh")), args.socket,
            os.environ["XDG_RUNTIME_DIR"], geometry],
            capture_output=True, timeout=11, check=True, env=env)
        end = time.monotonic_ns() / 1e6
        pixels = ppm(run.stdout)
        path.write_bytes(run.stdout)
        return {"start": start, "end": end, "file": str(path), "pixels": pixels}

    def settled(path, expected=None):
        previous = snap(path.with_name("settle-first.ppm"))
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            current = snap(path)
            if current["pixels"] == previous["pixels"] and (
                    expected is None or current["pixels"] == expected):
                return current
            previous = current
        raise TimeoutError("capture: baseline-not-restored")

    trials = []
    try:
        wait_key("ready")
        initial = read()
        if (initial["text"] != "" or initial["rows"] != 0 or not initial["menusReady"]
                or initial["fixtureApps"] != 60 or initial["appProviderWarm"]):
            raise ValueError(f"workload: not-bare-launcher facts={initial}")
        baseline = settled(out / "blank.ppm")
        blank = baseline["pixels"]
        for index in range(12):
            trialdir = out / f"trial-{index:03d}"
            trialdir.mkdir()
            if index:
                if invoke("latencyClear") != "cleared":
                    raise ValueError("ipc: clear-refused")
                baseline = settled(trialdir / "blank.ppm", blank)
            if invoke("latencyReset") != "reset":
                raise ValueError("ipc: reset-refused")
            ready = read()
            if (ready["appProviderWarm"] != (index > 0) or ready["text"] != ""
                    or ready["fixtureApps"] != 60 or ready["themeState"] != "absent"):
                raise ValueError(f"workload: cache-theme-fixture-not-ready facts={ready}")
            before = context()
            key_offset = (out / "keyboard.log").stat().st_size
            send = {}
            send_errors = []

            def press():
                try:
                    send["down"] = time.monotonic_ns() / 1e6
                    os.write(commands, b"down 32\n")
                    time.sleep(0.050)  # The measured physical-style hold, not a setup barrier.
                    send["up"] = time.monotonic_ns() / 1e6
                    os.write(commands, b"up 32\nsync\n")
                except Exception as error:
                    send_errors.append(repr(error))

            thread = threading.Thread(target=press)
            thread.start()
            captures = []
            deadline = time.monotonic() + 1
            while time.monotonic() < deadline:
                captures.append(snap(trialdir / f"frame-{len(captures):03d}.ppm"))
            after = context()
            thread.join(timeout=2)
            if thread.is_alive() or send_errors:
                raise RuntimeError(f"input: sender-failed errors={send_errors}")
            hold_ms = send["up"] - send["down"]
            if not 45 <= hold_ms <= 100:
                raise ValueError(f"workload: 50ms-request-outside-short-press-window actualMs={hold_ms}")
            wait_key("sync", key_offset)
            keyboard = (out / "keyboard.log").read_text()[key_offset:]
            if keyboard.splitlines() != ["down 32", "up 32", "sync"]:
                raise ValueError(f"workload: unexpected-input={keyboard!r}")
            facts = read()
            final = settled(trialdir / "final.ppm")
            advance = facts["firstGlyphAdvance"]
            if (type(advance) not in (int, float) or not math.isfinite(advance)
                    or not 1 <= advance <= 12):
                raise ValueError("capture: unread-first-glyph-advance")
            glyph_columns = math.floor(advance)
            first, channels = first_glyph(blank, final["pixels"], captures, glyph_columns)
            visible = captures[first]
            prior_start = captures[first - 1]["start"] if first else send["down"]
            upper = visible["end"] - send["down"]
            bracket = visible["end"] - max(send["down"], prior_start)
            elapsed = captures[-1]["end"] - captures[0]["start"]
            pressure = (cpu_total(after) - cpu_total(before)) / (elapsed * 10)
            reached = [e for e in facts["events"] if e["kind"] == "filter-end" and e["text"] == "o"]
            if (facts["fixtureApps"] != 60 or not reached
                    or reached[0]["fixtureRows"] != 60 or reached[0]["rows"] < 60):
                raise ValueError(f"workload: first-letter-fixture-not-reached facts={facts}")
            began = next(e for e in facts["events"] if e["kind"] == "filter-begin")
            if began["appProviderWarm"] != (index > 0) or not facts["appProviderWarm"]:
                raise ValueError("workload: provider-cache-changed")
            if facts["mode"] != "menu" or facts["fileMode"]:
                raise ValueError("workload: not-ordinary-app-menu")
            trial = {"index": index, "providerCache": "cold" if index == 0 else "warm",
                     "geometry": geometry, "send": send, "holdMs": hold_ms,
                     "fieldBox": json.loads(args.field), "leftPadding": json.loads(args.padding),
                     "surfaceBox": json.loads(args.surface),
                     "firstGlyphAdvance": advance, "glyphColumns": glyph_columns,
                     "keyboard": keyboard, "facts": facts,
                     "before": before, "after": after, "upperMs": upper, "bracketMs": bracket,
                     "cpuSomePct": pressure, "discriminantChannels": channels,
                     "firstMatchingCapture": first, "captures": []}
            for capture in captures:
                trial["captures"].append({k: v for k, v in capture.items() if k != "pixels"})
            (trialdir / "trial.json").write_text(json.dumps(trial, indent=2) + "\n")
            trials.append(trial)
        summary = {
            "trials": len(trials), "minUpperMs": min(t["upperMs"] for t in trials),
            "geometry": geometry, "fieldBox": json.loads(args.field),
            "leftPadding": json.loads(args.padding), "surfaceBox": json.loads(args.surface),
            "maxUpperMs": max(t["upperMs"] for t in trials),
            "maxBracketMs": max(t["bracketMs"] for t in trials),
            "maxCaptureMs": max(c["end"] - c["start"] for t in trials for c in t["captures"]),
            "maxCpuSomePct": max(t["cpuSomePct"] for t in trials),
            "maxLoad": max(float(t[edge]["loadavg"].split()[0])
                           for t in trials for edge in ("before", "after")),
            "singleCharacter": all(t["facts"]["text"] == "o" for t in trials),
            "onePressRelease": all(
                sum(e["kind"] == "press" and not e["repeat"] for e in t["facts"]["events"]) == 1
                and sum(e["kind"] == "release" and not e["repeat"] for e in t["facts"]["events"]) == 1
                for t in trials),
            "initial": initial,
        }
        (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(json.dumps(summary), flush=True)
    finally:
        os.write(commands, b"quit\n")
        try:
            keyproc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            keyproc.terminate()
            keyproc.wait(timeout=10)
        os.close(commands)
        keylog.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    instrument = commands.add_parser("prepare")
    instrument.add_argument("tree", type=Path)
    instrument.add_argument("--slow", action="store_true")
    capture = commands.add_parser("measure")
    for name in ("keyboard", "pid", "socket", "field", "padding", "surface"):
        capture.add_argument(name)
    capture.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.tree, args.slow)
    else:
        measure(args)


if __name__ == "__main__":
    main()
