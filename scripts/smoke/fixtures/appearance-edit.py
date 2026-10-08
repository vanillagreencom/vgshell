#!/usr/bin/env python3
"""Set shell.json `appearance` for a smoke row: FILE, then the JSON object
the key takes, `{}` to remove the key. Every other key stays as it was, and
the file is replaced by rename, so the shell never reads half a file."""
import json
import os
import sys

path, want = sys.argv[1], json.loads(sys.argv[2])
with open(path) as handle:
    config = json.load(handle)
if want:
    config["appearance"] = want
else:
    config.pop("appearance", None)
with open(path + ".next", "w") as handle:
    json.dump(config, handle, indent=2)
os.replace(path + ".next", path)
