#!/usr/bin/env python3
"""Mutate only a disposable installed rule, with exact matching controls."""
from pathlib import Path
import sys

action, source_path, destination = sys.argv[1:]
source = Path(source_path).read_text()
edits = {
    "restart": ('  read_hold(store ~= nil and store:find(0, "hold") or nil)',
                '  if false then read_hold(store ~= nil and store:find(0, "hold") or nil) end'),
    "lease": ('local function holder_present(pid)\n',
              'local function holder_present(pid)\n  if true then return true end\n'),
    "deadline": ('          if entry.origin == "rule" then',
                 '          if false and entry.origin == "rule" then'),
}
old, new = edits[action]
assert source.count(old) == 1, (action, source.count(old))
changed = source.replace(old, new)
assert changed != source
target = Path(destination)
assert not target.is_symlink()
target.write_text(changed)
