#!/usr/bin/env python3
"""Keep picker stdout, stderr and status separate for the nested row."""
import os
from pathlib import Path
import subprocess
import sys
root = Path(sys.argv[1])
env = {k: os.environ[k] for k in ("PATH", "HOME", "XDG_CONFIG_HOME", "XDG_RUNTIME_DIR", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "HYPRLAND_INSTANCE_SIGNATURE", "LANG", "VGS_TEST_RUN", "XDPH_WINDOW_SHARING_LIST", "LD_PRELOAD") if k in os.environ}
with root.with_suffix(".out").open("wb") as stdout, root.with_suffix(".err").open("wb") as stderr:
    child = subprocess.Popen(sys.argv[2:], env=env, stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr)
    try:
        code = child.wait(timeout=150)
    except subprocess.TimeoutExpired:
        child.kill()
        child.wait()
        code = 124
root.with_suffix(".exit").write_text(str(code))
