#!/usr/bin/env python3
"""Capture tools that read fixtures only. grim, slurp and hyprpicker can
forward to the real tool on a nested socket.

The fixture config names allowed display/runtime, geometry, text and failures.
Each tool writes `<tool>-pid-<pid>` before it runs, so a check can read
whether that process is still alive.
slurp reads stdin to EOF when it is not a terminal, as the real slurp does.
The recorder writes `finalized` only after SIGINT, never on a hard stop.
"""
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import time

root = Path(os.environ["VGS_CAPTURE_FIXTURE"])
tool = os.environ["VGS_CAPTURE_TOOL"]
config = json.loads((root / "config.json").read_text())
with (root / "calls.jsonl").open("a") as log:
    log.write(json.dumps({"tool": tool, "args": sys.argv[1:]}) + "\n")
(root / f"{tool}-pid-{os.getpid()}").touch()
if config.get("fail") == tool:
    print("fixture failure", file=sys.stderr)
    sys.exit(1)
real = config.get("real", {}).get(tool)
if real:
    if os.environ.get("WAYLAND_DISPLAY") != config["display"] or os.environ.get("XDG_RUNTIME_DIR") != config["runtime"]:
        sys.exit("capture-fixture: refused non-nested socket")
    os.execv(real, [real, *sys.argv[1:]])
match tool:
    case "slurp":
        if not sys.stdin.isatty():
            sys.stdin.read()
        if config.get("hold"):
            (root / "slurp-ready").touch()
            signal.pause()
        if config.get("escape"):
            sys.exit("selection cancelled")
        if config.get("cancel"):
            sys.exit(1)
        print(config.get("geometry", "10,20 80x60"))
    case "hyprpicker":
        signal.pause()
    case "grim":
        data = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 320, 240)
        if sys.argv[-1] == "-":
            sys.stdout.buffer.write(data)
        else:
            Path(sys.argv[-1]).write_bytes(data)
    case "tesseract":
        data = sys.stdin.buffer.read()
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            sys.exit("capture-fixture: OCR received no PNG")
        if config.get("englishDataMissing"):
            # Tesseract init_tesseract emits this when eng cannot load.
            print("Failed loading language 'eng'\nTesseract couldn't load any languages!", file=sys.stderr)
            sys.exit(1)
        print(config.get("text", "Nested capture text"))
    case "wl-copy":
        (root / "clipboard").write_bytes(sys.stdin.buffer.read())
        if config.get("clipboardHold"):
            pid = str(os.getpid())
            def copied_done(signum, frame):
                (root / ("clipboard-signal-" + pid)).write_text(str(signum))
                sys.exit(0)
            signal.signal(signal.SIGTERM, copied_done)
            (root / ("clipboard-ready-" + pid)).touch()
            while True:
                signal.pause()
    case "gpu-screen-recorder":
        target = Path(sys.argv[sys.argv.index("-o") + 1])
        if config.get("crash"):
            sys.exit(1)
        def finish(signum, frame):
            (root / "signal").write_text(str(signum))
            while config.get("holdFinalize") and not (root / "finalize-release").exists():
                time.sleep(0.01)
            target.write_bytes(b"finalized")
            sys.exit(0)
        signal.signal(signal.SIGINT, finish)
        target.write_bytes(b"recording")
        (root / "recorder-ready").write_text(str(os.getpid()))
        while True:
            signal.pause()
    case _:
        sys.exit("capture-fixture: unknown tool")
