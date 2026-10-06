#!/usr/bin/env python3
# edit.py FILE OLD NEW: FILE, a file of a sandbox copy of a plugin or a
# host copy the ai-usage row makes, with OLD, which must match exactly
# once, replaced by NEW. The ai-usage row points its copy's usage endpoint
# at its stand-in and plants each control through it, and the tray row
# plants each of its controls; a missing or repeated match, or a link,
# ends with exit 1 and the file unchanged.
import sys
from pathlib import Path

path, old, new = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
if path.is_symlink() or not path.is_file():
    sys.exit("edit: refused: file=%s reason=not-a-file" % path)
text = path.read_text()
if text.count(old) != 1:
    sys.exit("edit: refused: file=%s matches=%d" % (path, text.count(old)))
changed = text.replace(old, new)
if changed == text:
    sys.exit("edit: refused: file=%s reason=unchanged" % path)
path.write_text(changed)
