# Run the actual accounts script on a private controlling terminal.
# Gum's stand-in consumes the test's scratch menu queue, never host input.
import errno
import fcntl
import os
import pty
import select
import struct
import subprocess
import sys
import termios
import time

master, slave = pty.openpty()
# An optional fourth argument sizes the terminal, COLUMNS wide.
if len(sys.argv) > 4:
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, int(sys.argv[4]), 0, 0))
env = {name: os.environ[name] for name in (
    "PATH", "HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_DATA_HOME",
    "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS")}
for name in ("CLAUDE_CONFIG_DIR", "CODEX_HOME", "TERM", "COLORTERM"):
    if name in os.environ:
        env[name] = os.environ[name]
# The suite supplies synthetic presenter colors inside its private world.
for name, value in os.environ.items():
    if name.startswith("GUM_"):
        env[name] = value
env["VGS_TUI_LIB"] = sys.argv[2]
env["VGS_PLUGIN_DIR"] = sys.argv[3]
env["VGS_PLUGIN_ID"] = "vgs.jarvis"
for name, value in os.environ.items():
    if name.startswith("GUM_") or name in ("TERM", "COLORTERM", "FOREGROUND", "BACKGROUND", "BORDER_FOREGROUND"):
        env[name] = value
env["OPENAI_API_KEY"] = "fixture-secret-private"
env["VGSHELL_RUNNER_PID"] = "999"

def terminal():
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

child = subprocess.Popen(["bash", sys.argv[1]], stdin=slave, stdout=slave,
                         stderr=slave, env=env, preexec_fn=terminal)
os.close(slave)
output = b""
deadline = time.monotonic() + 15  # Bound a script stuck waiting for fixture input.
try:
    while time.monotonic() < deadline:
        if select.select([master], [], [], 0.05)[0]:
            try:
                part = os.read(master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not part:
                break
            output += part
        elif child.poll() is not None:
            break
    if child.poll() is None:
        child.kill()
    code = child.wait(timeout=2)
    sys.stdout.buffer.write(output)
    sys.exit(code)
finally:
    if child.poll() is None:
        child.kill()
        child.wait()
    os.close(master)
