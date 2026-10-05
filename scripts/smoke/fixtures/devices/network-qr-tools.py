#!/usr/bin/env python3
"""Readonly Share doubles. Decode no host state and persist no secret or stdin.

NETWORK_QR_WORLD names a private JSON fixture with public profile fields and
synthetic secret character codes. The argv log contains public arguments only.
The qrencode double checks its stdin by digest and emits a public test matrix.
"""
import hashlib
import json
import os
from pathlib import Path
import sys
import time

world = json.loads(Path(os.environ["NETWORK_QR_WORLD"]).read_text())
tool = Path(sys.argv[0]).name
argv = sys.argv[1:]
with Path(os.environ["NETWORK_QR_CALLS"]).open("a") as log:
    log.write(json.dumps([tool, argv]) + "\n")
if tool == "nmcli":
    fields = argv[argv.index("--get-values") + 1]
    if world.get("refused"):
        sys.exit(1)
    if fields == "GENERAL.CON-UUID":
        print(world.get("active", "--"))
    elif fields == "UUID,TYPE":
        for profile in world["profiles"]:
            print(profile["uuid"] + ":802-11-wireless")
    else:
        profile = next(p for p in world["profiles"] if p["uuid"] == argv[-1])
        if "--show-secrets" in argv:
            print("".join(chr(c) for c in profile["secret_codes"]))
        else:
            print(profile["ssid"] + "\n" + profile["key_management"] + "\n" + profile["hidden"])
elif tool == "qrencode":
    feed = sys.stdin.buffer.read()
    if hashlib.sha256(feed).hexdigest() != world["payload_digest"]:
        sys.exit(1)
    feed = b""
    if world.get("hold"):
        Path(os.environ["NETWORK_QR_READY"]).write_text(str(os.getpid()))
        while True:
            time.sleep(1)
    if world.get("invalid"):
        print("bad")
    else:
        # The synthetic QR result is intentionally public. The helper test
        # holds payload correctness, not this stand-in's encoding algorithm.
        print("######\n##  ##\n######")
else:
    sys.exit(2)
