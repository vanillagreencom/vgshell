#!/usr/bin/env python3
"""Recorded ss stand-in. Counters advance without network traffic. A row
names the pid an app's socket holds in WORLD/pids, a JSON object by app
name; an app it does not name holds pid 42."""
import json
import os
from pathlib import Path
import sys
import time
world = Path(sys.argv[1])
with (world / "calls").open("a") as out:
    out.write(json.dumps(sys.argv[2:]) + "\n")
(world / "pid").write_text(str(os.getpid()))
end = time.monotonic() + 20
while (world / "hold").exists() and time.monotonic() < end:
    time.sleep(0.05)
p = world / "sample"
value = int(p.read_text()) + 1 if p.exists() else 1
p.write_text(str(value))
pids = json.loads((world / "pids").read_text()) if (world / "pids").exists() else {}
for inode, name, down, up in ((10, "Browser", 6000, 3000), (11, "Player", 3000, 1500)):
    print(f'ESTAB 0 0 192.0.2.2:{4000 + inode} 198.51.100.1:443 users:(("{name}",pid={pids.get(name, 42)},fd=8)) ino:{inode}')
    print(f'\tbytes_sent:{up * value + 500} bytes_acked:{up * value} bytes_received:{down * value}')
