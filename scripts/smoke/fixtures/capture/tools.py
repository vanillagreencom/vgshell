#!/usr/bin/env python3
"""Capture tools that read fixtures only. grim, slurp and hyprpicker can
forward to the real tool on a nested socket.

The fixture config names allowed display/runtime, geometry, text and failures.
Each tool writes `<tool>-pid-<pid>` before it runs, so a check can read
whether that process is still alive.
slurp reads stdin to EOF when it is not a terminal, as the real slurp does.
The recorder logs its start, then writes `finalized`, or copies the fixture's
`video`, only after SIGINT, never on a hard stop. ffmpeg copies its input, or
writes a JPEG marker for a one-frame thumbnail. pw-dump prints the fixture's
nodes. tesseract lists the fixture's languages and fails as Tesseract does
for a requested one it does not hold.
"""
import json
import os
import shutil
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
            (root / "slurp-input").write_text(sys.stdin.read())
        if config.get("slurpRelease"):
            (root / "slurp-ready").touch()
            while not (root / "slurp-release").exists():
                time.sleep(0.01)
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
        if config.get("grimHold"):
            (root / "grim-ready").write_text(str(os.getpid()))
            signal.pause()
        data = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 320, 240)
        data += str(config.get("frame", "")).encode()
        if sys.argv[-1] == "-":
            sys.stdout.buffer.write(data)
        else:
            Path(sys.argv[-1]).write_bytes(data)
    case "tesseract":
        languages = config.get("languages", ["eng", "osd"])
        if sys.argv[1:] == ["--list-langs"]:
            print(f'List of available languages in "{root}/tessdata/" ({len(languages)}):')
            print("\n".join(languages))
            sys.exit(0)
        data = sys.stdin.buffer.read()
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            sys.exit("capture-fixture: OCR received no PNG")
        for code in sys.argv[sys.argv.index("-l") + 1].split("+"):
            if code not in languages:
                # Tesseract init_tesseract emits this when a language cannot load.
                print(f"Failed loading language '{code}'\nTesseract couldn't load any languages!", file=sys.stderr)
                sys.exit(1)
        print(config.get("text", "Nested capture text"))
    case "pw-dump":
        print(json.dumps(config.get("nodes", [
            {"id": 40, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Audio/Source", "node.name": "fixture-mic", "node.description": "Fixture microphone"}}},
            {"id": 41, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Audio/Sink", "node.name": "fixture-speaker", "node.description": "Fixture speaker"}}},
            {"id": 42, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Video/Source", "node.name": "fixture-camera", "node.description": "Fixture camera", "api.v4l2.path": "/dev/video7"}}},
            {"id": 43, "type": "PipeWire:Interface:Link", "info": {}},
        ])))
    case "ffmpeg":
        source, target = Path(sys.argv[sys.argv.index("-i") + 1]), Path(sys.argv[-1])
        if "-frames:v" in sys.argv:
            target.write_bytes(b"\xff\xd8\xff fixture thumbnail")
            sys.exit(0)
        if config.get("ffmpegFail"):
            print("fixture ffmpeg failure", file=sys.stderr)
            sys.exit(1)
        if config.get("ffmpegHold"):
            target.write_bytes(b"partial")
            (root / "ffmpeg-ready").write_text(str(os.getpid()))
            while True:
                signal.pause()
        shutil.copyfile(source, target)
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
        print("fixture recorder started", file=sys.stderr, flush=True)
        if config.get("crash"):
            print("fixture recorder crash: no encoder", file=sys.stderr)
            sys.exit(1)
        def finish(signum, frame):
            (root / "signal").write_text(str(signum))
            while config.get("holdFinalize") and not (root / "finalize-release").exists():
                time.sleep(0.01)
            if config.get("video"):
                shutil.copyfile(config["video"], target)
            else:
                target.write_bytes(b"finalized")
            sys.exit(0)
        signal.signal(signal.SIGINT, finish)
        if config.get("picker"):
            # A portal picker stays open until the user answers it.
            (root / "picker-ready").write_text(str(os.getpid()))
        else:
            target.write_bytes(b"recording")
            (root / "recorder-ready").write_text(str(os.getpid()))
        while True:
            signal.pause()
    case _:
        sys.exit("capture-fixture: unknown tool")
