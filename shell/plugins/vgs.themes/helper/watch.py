#!/usr/bin/env python3
"""Watch the folders the Themes service reads and print what changed.

  watch.py CONFIG CATALOG

CONFIG is the shell's config folder (Paths.configDir), CATALOG the shipped
catalog folder (shellDir/../themes/catalog). Every watch is a directory
watch on one inotify instance, so the instance count stays one however many
packages and images exist. One Quickshell FileView per path costs one
instance each (Quickshell 0.3.1 src/io/fileview.cpp updateWatchedFiles makes
one QFileSystemWatcher per FileView), and a Qt directory watch misses an
in-place write (qtbase 6.12 qfilesystemwatcher_inotify.cpp watches a
directory without IN_MODIFY). IN_CLOSE_WRITE here reports each finished
write of a child once, where IN_MODIFY would fire per written block of a
copied wallpaper.

Watched, when present:
  CONFIG                       a child created, deleted or moved is a list
                               change: a shell.json save, themes/ or
                               backgrounds/ created
  CONFIG/themes                a child created, deleted or moved is a list
                               change; every child folder, a symlink to one
                               included, is a package
  CONFIG/themes/P              an event names P: theme.json, terminal.json,
  CONFIG/themes/P/backgrounds  preview.jpg, its images
  CONFIG/backgrounds           an event names "", the user images' key
  CATALOG                      only index.json, as a list change
In CONFIG and CONFIG/themes a write in place is no change: every theme
command opens CONFIG/theme.lock for append (bin/vgshell theme_lock), and its
close would read the whole browser. A shell.json save still is one, since
shell/Core/Config.qml writes through a FileView with atomicWrites at its
default, true, which writes another file and renames it over the target
(Quickshell 0.3.1 FileView, https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/FileView).
The watch set is reconciled at start, when a watched folder's themes/ or
backgrounds/ entry, or any CONFIG/themes entry, is created, moved or
deleted, when a watched folder itself goes, and once on a queue overflow,
which also names every package and "". A missing folder under CONFIG is
armed once it appears; CONFIG and CATALOG, whose parents are not watched,
are armed only by a reconcile. A package renamed in reports under its new
name; a folder moved off its path reports nothing more. A backgrounds/ that
is a symlink is not followed: it holds no images. A reconcile that arms,
drops or renames a folder other than an images folder is a list change.

Output, one JSON line per kernel read, flushed: `{"ready": true}` once the
first watches are armed, then `{"list": BOOL, "names": [...]}`, names sorted,
only for a read that changed something. The process blocks in read(2) with
no timeout and forks nothing. It ends at once on SIGTERM, which its parent's
death sends (PR_SET_PDEATHSIG), and exits 0 when the parent died before
that signal was set. A setup failure, or a present folder that cannot be
watched, prints `watch.py: watch=failed reason=<init|pdeathsig|setup>
[path=PATH]: <strerror>` on stderr and exits 1; wrong arguments exit 2.
"""
import ctypes
import errno
import json
import os
import struct
import sys

IN_CLOSE_WRITE, IN_MOVED_FROM, IN_MOVED_TO = 0x8, 0x40, 0x80
IN_CREATE, IN_DELETE, IN_DELETE_SELF, IN_MOVE_SELF = 0x100, 0x200, 0x400, 0x800
IN_Q_OVERFLOW, IN_IGNORED, IN_ONLYDIR, IN_DONT_FOLLOW = 0x4000, 0x8000, 0x1000000, 0x2000000
MASK = IN_CLOSE_WRITE | IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO | IN_DELETE_SELF | IN_MOVE_SELF
ENTRY = IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO
GONE = IN_DELETE_SELF | IN_MOVE_SELF | IN_IGNORED
EVENT = struct.Struct("iIII")  # struct inotify_event: wd, mask, cookie, len

libc = ctypes.CDLL(None, use_errno=True)


class WatchFailed(Exception):
    def __init__(self, reason, err, path=None):
        super().__init__(reason)
        self.reason, self.err, self.path = reason, err, path


def add_watch(fd, path, follow):
    """The wd of PATH, or None while no folder stands there."""
    wd = libc.inotify_add_watch(fd, os.fsencode(path), MASK | IN_ONLYDIR | (0 if follow else IN_DONT_FOLLOW))
    if wd != -1:
        return wd
    err = ctypes.get_errno()
    if err in (errno.ENOENT, errno.ENOTDIR):
        return None
    raise WatchFailed("setup", err, path)


def reconcile(fd, watches, config, catalog):
    """Arm every present folder of the set and drop every other watch."""
    themes = os.path.join(config, "themes")
    want = [(config, "config", None), (themes, "themes", None),
            (os.path.join(config, "backgrounds"), "images", ""), (catalog, "catalog", None)]
    try:
        packages = sorted(os.listdir(themes))
    except (FileNotFoundError, NotADirectoryError):
        packages = []
    except OSError as exc:
        raise WatchFailed("setup", exc.errno, themes) from exc
    for name in packages:
        folder = os.path.join(themes, name)
        want += [(folder, "package", name), (os.path.join(folder, "backgrounds"), "images", name)]
    armed = {}
    for path, kind, name in want:
        # A symlinked backgrounds/ holds no images (bin/lib/theme-backgrounds.js images).
        wd = add_watch(fd, path, follow=kind != "images")
        if wd is not None:
            armed[wd] = (path, kind, name)
    for wd in watches.keys() - armed.keys():
        libc.inotify_rm_watch(fd, wd)  # EINVAL for a wd the kernel already dropped
    def folders(table):
        return {item for item in table.items() if item[1][1] != "images"}
    changed = folders(watches) != folders(armed)
    watches.clear()
    watches.update(armed)
    return changed


def read_batch(data, watches):
    """The list change, the names, and whether to reconcile, of one read."""
    listed, names, again, overflow = False, set(), False, False
    offset = 0
    while offset < len(data):
        wd, mask, _, size = EVENT.unpack_from(data, offset)
        name = data[offset + EVENT.size:offset + EVENT.size + size].split(b"\0", 1)[0]
        offset += EVENT.size + size
        if mask & IN_Q_OVERFLOW:
            listed = again = overflow = True
            continue
        if wd not in watches:
            continue
        _, kind, owner = watches[wd]
        if mask & GONE:
            again = True
            continue
        if mask & ENTRY and (kind == "themes" or kind in ("config", "package") and name in (b"themes", b"backgrounds")):
            again = True
        if kind in ("config", "themes"):
            listed |= bool(mask & ENTRY)
        elif kind == "catalog" and name == b"index.json":
            listed = True
        elif kind in ("package", "images"):
            names.add(owner)
    return listed, names, again, overflow


def main(argv):
    if len(argv) != 2:
        print("watch.py: usage=CONFIG CATALOG", file=sys.stderr)
        return 2
    config, catalog = (os.path.abspath(arg) for arg in argv)
    parent = os.getppid()
    try:
        fd = libc.inotify_init1(os.O_CLOEXEC)  # IN_CLOEXEC is O_CLOEXEC
        if fd == -1:
            raise WatchFailed("init", ctypes.get_errno())
        PR_SET_PDEATHSIG, SIGTERM = 1, 15
        if libc.prctl(PR_SET_PDEATHSIG, SIGTERM, 0, 0, 0) == -1:
            raise WatchFailed("pdeathsig", ctypes.get_errno())
        # A parent that died before prctl sends no signal.
        current = os.getppid()
        if current == 1 or current != parent:
            return 0
        watches = {}
        reconcile(fd, watches, config, catalog)
        print(json.dumps({"ready": True}), flush=True)
        while True:
            listed, names, again, overflow = read_batch(os.read(fd, 65536), watches)
            if again:
                listed |= reconcile(fd, watches, config, catalog)
            if overflow:
                names |= {name for _, kind, name in watches.values() if kind == "package"} | {""}
            if listed or names:
                print(json.dumps({"list": listed, "names": sorted(names)}), flush=True)
    except WatchFailed as exc:
        path = f" path={exc.path}" if exc.path else ""
        print(f"watch.py: watch=failed reason={exc.reason}{path}: {os.strerror(exc.err)}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
