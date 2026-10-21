#!/usr/bin/env python3
"""Local installer doubles, not vendor protocol or model evidence.

Source: setup-local argv contract and synthetic files, 2026-09-30; the
clone verbs' and the clone TUI's pw-record argv, 2026-10-12.
All effects stay in J09's scratch world. No installer or downloader runs.
"""
import json
import math
import os
from pathlib import Path
import shutil
import struct
import sys
import time
from urllib.parse import urlparse

name = Path(sys.argv[0]).name
args = sys.argv[1:]
data = Path(os.environ["UV_CACHE_DIR"]).parent
config = json.loads((data / "fixture.json").read_text())
with (data / "calls.jsonl").open("a") as log:
    log.write(json.dumps([name, *args]) + "\n")

# A tier's environment, or the cloned voice's.
runtimes = (data / "venv", data / "clone/venv")
if name == "uv":
    assert args[:1] == ["--no-config"]
    if args[1] == "venv":
        assert args[2:5] == ["--managed-python", "--python", "3.12"]
        target = Path(args[5])
        assert target in runtimes
        (target / "bin").mkdir(parents=True)
        shutil.copyfile(__file__, target / "bin/python")
        (target / "bin/python").chmod(0o700)
        (target / "pyvenv.cfg").write_text("fixture private environment\n")
    else:
        assert args[1:4] == ["pip", "sync", "--python"]
        assert args[4] in [str(runtime / "bin/python") for runtime in runtimes]
        assert args[5:8] == ["--require-hashes", "--only-binary", ":all:"]
        assert Path(args[8]).is_file()
        (Path(args[4]).parents[1] / "installed").write_text("fixture package bytes\n")
    sys.exit(config.get("uv_exit", 0))
elif name == "curl":
    assert args[:8] == ["--disable", "--fail", "--location", "--proto", "=https", "--proto-redir", "=https", "--output"]
    assert args[9] == "--"
    source = data / "downloads" / urlparse(args[10]).path.lstrip("/")
    shutil.copyfile(source, args[8])
    sys.stderr.write(config.get("curl_stderr", ""))
    sys.exit(config.get("curl_exit", 0))
elif name == "unshare":
    assert args[:2] == ["-rn", "--"] and args[2] in [str(runtime / "bin/python") for runtime in runtimes]
    assert args[3:5] == ["-I", str(Path(args[4]))]
    assert args[5:] in (["probe", config["tier"]], ["clone", "probe"])
    # No bootstrap unshare or external program enters the test PATH.
    os.execve(args[2], args[2:], dict(os.environ))
elif name == "python" and args[2:] == ["clone", "probe"]:
    # The cloned voice's probe: the clone environment's interpreter, and
    # the recording setup-local stored, which it records it read.
    assert Path(sys.argv[0]) == data / "clone/venv/bin/python"
    state = Path(os.environ["XDG_STATE_HOME"]) / "vgshell/jarvis"
    (data / "clone-probed").write_bytes((state / "voice-reference.wav").read_bytes())
    print(json.dumps(config.get("clone_record", {"scope": "chatterbox", "provider_requested": "cuda",
        "artifact_ids": ["chatterbox"], "peak_rss_bytes": 8192, "gpu_peak_bytes": 4096})))
    sys.exit(config.get("clone_probe_exit", 0))
elif name == "python":
    assert args[:1] == ["-I"] and args[2:] == ["probe", config["tier"]]
    assert Path(sys.argv[0]) == data / "venv/bin/python"
    if config.get("entry_probe"):
        os.execve(sys.executable, [sys.executable, "-I", config["entry_probe"],
                  args[1], args[3], str(data / "probe-expected.json")], dict(os.environ))
    if config.get("change_runtime"):
        (data / "venv/installed").write_text("changed during probe\n")
    # Records distinguish calling the chosen venv from a host interpreter.
    (data / "probed").write_text(config["tier"])
    if config.get("hold_probe"):
        (data / "probe-held").write_text("held")
        # The signal case owns the release file. This is not a startup delay.
        while not (data / "probe-release").exists():
            time.sleep(0.01)
    # A failing engine's own lines, which the owner must not see.
    sys.stderr.write(config.get("probe_stderr", ""))
    value = json.loads((Path(args[1]).parent / "artifacts.json").read_text())
    tier = value["tiers"][config["tier"]]
    print(json.dumps(config.get("probe_record", {"scope": config["tier"],
        "provider_requested": tier["provider"], "artifact_ids": tier["artifacts"],
        "peak_rss_bytes": 4096, "gpu_peak_bytes": 2048 if tier["provider"] == "cuda" else None})))
    sys.exit(config.get("probe_exit", 0))
elif name == "pw-record":
    # Stands in for the microphone: pcm_seconds of a tone at pcm_amplitude
    # of full scale, raw s16 mono at 24000 Hz, as the TUI asks. No device.
    assert args == ["--raw", "--rate", "24000", "--channels", "1", "--format", "s16", "-"]
    seconds, amplitude = config.get("pcm_seconds", 10), config.get("pcm_amplitude", 0.5)
    sys.stdout.buffer.write(b"".join(struct.pack("<h", round(amplitude * 32767 * math.sin(2 * math.pi * 220 * i / 24000)))
                                     for i in range(int(seconds * 24000))))
    sys.exit(0)
elif name == "nvidia-smi":
    # Stands in for the declared GPU requirement; no host GPU is read. It
    # lists the total memory, in MiB, of each GPU in gpu_memory.
    assert args == ["--query-gpu=memory.total", "--format=csv,noheader,nounits"]
    for total in config.get("gpu_memory", [32607]):
        print(total)
    sys.exit(config.get("gpu_exit", 0))
else:
    raise RuntimeError("unknown fixture command: " + name)
