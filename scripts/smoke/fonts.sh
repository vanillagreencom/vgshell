# Shared /proc observation for processes that load the bundled fonts.
# `copies` means both exported private paths are mapped at their current
# inodes and no installed bundled font is mapped, deleted files included.
# A name after the directories is a face the process may leave undrawn: its
# private path is still required, and its file unmapped is no difference.
set -euo pipefail

font_copies_read() { # PID BUNDLED_DIR PRIVATE_DIR [UNDRAWN_NAME...]
  python3 - "$@" <<'PY'
import os, sys
qs, bundled, private, *undrawn = sys.argv[1:]
private = os.path.realpath(private)
try:
    with open(f"/proc/{qs}/environ", "rb") as fh:
        env = dict(item.split(b"=", 1) for item in fh.read().split(b"\0") if b"=" in item)
    with open(f"/proc/{qs}/maps") as fh:
        rows = [line.split(None, 5) for line in fh.read().splitlines()]
except OSError as exc:
    print(f"unreadable={type(exc).__name__}")
    sys.exit(0)
files = [(parts[5].removesuffix(" (deleted)"), int(parts[4])) for parts in rows if len(parts) == 6]
differences = []
for name in ("VGSHELL_FONT_SANS", "VGSHELL_FONT_MONO"):
    value = env.get(name.encode())
    if value is None:
        differences.append(f"{name}=unset")
        continue
    path = os.path.realpath(os.fsdecode(value))
    if os.path.dirname(path) != private:
        differences.append(f"{name}=outside:{path}")
        continue
    try:
        inode = os.stat(path).st_ino
    except OSError as exc:
        differences.append(f"{name}=unreadable:{type(exc).__name__}")
        continue
    if (path, inode) not in files and name not in undrawn:
        differences.append(f"{name}=unmapped")
held = sorted({os.path.basename(path) for path, _ in files if os.path.dirname(path) == bundled})
if held:
    differences.append("bundled=" + ",".join(held))
print(" ".join(differences) or "copies")
PY
}
