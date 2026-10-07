#!/usr/bin/env python3
"""Private nmcli double. Record public argv and a typed stdin check only."""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import time

world_path, calls_path, ready_path = map(Path, sys.argv[1:4])
world = json.loads(world_path.read_text())
args = sys.argv[4:]
secret = "".join(map(chr, world["secret_codes"]))
leaked = any(secret in arg for arg in args)
public = [arg.replace(secret, "<secret>") for arg in args]
operation = args[args.index("connection") + 1]
record = {"argv": public, "argv_secret": leaked, "operation": operation}
parent_argv = Path("/proc/" + str(os.getppid()) + "/cmdline").read_bytes().decode().split("\0")[:-1]
record["helper_argv_secret"] = any(secret in arg for arg in parent_argv)
record["helper_argv"] = [arg.replace(secret, "<secret>") for arg in parent_argv]
if operation == "up":
    feed = sys.stdin.buffer.read()
    record["stdin_ok"] = hashlib.sha256(feed).hexdigest() == world["stdin_digest"]
    feed = b""
with calls_path.open("a") as log:
    log.write(json.dumps(record) + "\n")
if world.get("hold") == operation:
    ready_path.write_text(str(__import__("os").getpid()))
    while json.loads(world_path.read_text()).get("hold") == operation:
        time.sleep(.05)
failure = world.get("fail", {}).get(operation)
if failure:
    # Deliberate upstream secret echo: the real helper must consume it privately.
    print(("Not authorized" if failure == "refused" else "failed") + " " + secret, file=sys.stderr)
    sys.exit(4 if operation == "up" else 10)
if leaked or (operation == "up" and not record["stdin_ok"]):
    sys.exit(2)
world = json.loads(world_path.read_text())
profiles = world.get("profiles", [])
if operation == "add":
    profiles.append(args[args.index("connection.uuid") + 1])
elif operation == "delete":
    profile = args[args.index("uuid") + 1]
    profiles.remove(profile)
world["profiles"] = profiles
with tempfile.NamedTemporaryFile("w", dir=world_path.parent, delete=False) as updated:
    json.dump(world, updated)
Path(updated.name).replace(world_path)
