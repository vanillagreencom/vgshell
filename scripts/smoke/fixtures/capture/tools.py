#!/usr/bin/env python3
"""Capture tools that read fixtures only. grim, slurp and hyprpicker can
forward to the real tool on a nested socket.

The fixture config names allowed display/runtime, geometry, text and failures.
Each tool writes `<tool>-pid-<pid>` before it runs, so a check can read
whether that process is still alive.
slurp reads stdin to EOF when it is not a terminal, as the real slurp does.
The recorder logs its start and output name, then writes `finalized`, or
copies the fixture's `video`, only after SIGINT, never on a hard stop.
ffmpeg copies its input, or writes a small JPEG for a one-frame thumbnail;
ffmpegHold holds it half way until `ffmpeg-release` exists. grimHeldCall N
holds the Nth grim run until `grim-release` exists. pw-dump prints the fixture's
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
import zlib

# A grey 4x4 JPEG from ImageMagick, which an image reader decodes.
THUMBNAIL = bytes.fromhex(
    "ffd8ffe000104a46494600010100000100010000ffdb004300100b0c0e0c0a100e0d0e1211101318281a181616183123251d283a333d3c3933383740"
    "485c4e404457453738506d51575f626768673e4d71797064785c656763ffc0000b080004000401011100ffc40014000100000000000000000000000000"
    "000000ffc40014100100000000000000000000000000000000ffda0008010100003f003fffd9")
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
        if config.get("grimHeldCall") == [json.loads(line)["tool"] for line in (root / "calls.jsonl").read_text().splitlines()].count("grim"):
            (root / "grim-ready").write_text(str(os.getpid()))
            while not (root / "grim-release").exists():
                time.sleep(0.01)
        # A whole grey 320x240 PNG, which an image reader decodes, then the
        # frame token, which a PNG reader ignores past IEND.
        def chunk(kind, body):
            return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
        rows = b"".join(b"\x00" + b"\x80" * (320 * 3) for _ in range(240))
        data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 320, 240, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
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
            target.write_bytes(THUMBNAIL)
            sys.exit(0)
        if config.get("ffmpegHold"):
            # Held half way until the check writes ffmpeg-release.
            target.write_bytes(b"partial")
            (root / "ffmpeg-ready").write_text(str(os.getpid()))
            while not (root / "ffmpeg-release").exists():
                time.sleep(0.01)
        if config.get("ffmpegFail"):
            target.write_bytes(b"partial")
            print("fixture ffmpeg failure", file=sys.stderr)
            sys.exit(1)
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
        (root / "owned-recorder").write_text(str(os.getpid()))
        print(f"fixture recorder started {target.name}", file=sys.stderr, flush=True)
        if config.get("portalCancel"):
            # The recorder's exit when the user cancels the portal picker.
            sys.exit(60)
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
