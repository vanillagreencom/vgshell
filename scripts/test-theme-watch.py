#!/usr/bin/env python3
"""The Themes watch helper's lines for each change the service must see.

Each case starts the helper on a scratch config and catalog folder, never
the user's, makes one change and reads the lines it prints. A change is
judged by the union of its lines up to a sync point: a folder made in the
`zz-sync` package after the change, whose event the one inotify queue
delivers after every event of the change, so a missing or a surplus name is
seen without a quiet-period wait. A step taken before that package exists
reads until its expected lines arrive. Every line must be well formed and
report something.

The count case installs 40 packages of 5 images and reads the helper's own
/proc fd table: one inotify instance holding one watch per watched folder.
The lifetime cases end the helper's parent, and send SIGTERM, and require
the helper gone within the runner's five-second cleanup grace
(docs/architecture/runtime.md § Process).

Controls: each rule is removed from a copy of the helper, and the case that
holds the rule must then fail.
"""
import json
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parent.parent
HELPER = REPO / "shell/plugins/vgs.themes/helper/watch.py"
ENV = {"PATH": os.defpath, "LC_ALL": "C", "VGS_TEST_RUN": "1"}
SYNC = "zz-sync"
# A bound on a line or an exit the kernel already owes, not a latency
# budget; the runner's cleanup grace for the lifetime cases.
WAIT = 5


class Helper:
    """One helper run on ROOT/config and ROOT/catalog, read line by line."""

    def __init__(self, helper, root):
        self.proc = subprocess.Popen([sys.executable, str(helper), str(root / "config"), str(root / "catalog")],
                                     stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=ENV)
        self.buffer = b""
        self.ready = self.line() == {"ready": True}

    def line(self):
        """The next line as JSON, or None when none came within WAIT."""
        deadline = time.monotonic() + WAIT
        while b"\n" not in self.buffer:
            left = deadline - time.monotonic()
            if left <= 0 or not select.select([self.proc.stdout], [], [], left)[0]:
                return None
            chunk = os.read(self.proc.stdout.fileno(), 65536)
            if not chunk:
                return None
            self.buffer += chunk
        text, self.buffer = self.buffer.split(b"\n", 1)
        return json.loads(text)

    def stop(self):
        self.proc.kill()
        self.proc.wait()
        self.proc.stdout.close()
        self.proc.stderr.close()


def change(helper, root, action, listed=False, names=(), allowed=()):
    """Whether ACTION's lines add up to the list flag LISTED and NAMES, with
    any of ALLOWED besides: a package's own files written while it was
    being armed."""
    sync = root / "config/themes" / SYNC
    synced = sync.is_dir()
    action()
    if synced:
        (sync / f"n{time.monotonic_ns()}").mkdir()  # one event: IN_CREATE
    seen_list, seen = False, set()
    while (SYNC not in seen) if synced else (seen_list != listed or not set(names) <= seen):
        line = helper.line()
        if line is None or set(line) != {"list", "names"} or line["names"] != sorted(set(line["names"])):
            return False
        if not (line["list"] or line["names"]):
            return False
        seen_list |= line["list"]
        seen |= set(line["names"])
    seen.discard(SYNC)
    return seen_list == listed and set(names) <= seen <= set(names) | set(allowed)


def package(folder, images=1):
    (folder / "backgrounds").mkdir(parents=True)
    (folder / "theme.json").write_text("{}")
    (folder / "terminal.json").write_text("{}")
    for index in range(images):
        (folder / f"backgrounds/{index}.jpg").write_bytes(b"jpg")


def world(root, themes=True, user=True):
    (root / "config").mkdir(parents=True)
    (root / "catalog").mkdir()
    (root / "catalog/index.json").write_text("{}")
    (root / "config/shell.json").write_text("{}")
    (root / "config/theme.lock").write_text("")
    (root / "config/screensaver.txt").write_text("text")
    if themes:
        package(root / "config/themes/a")
        package(root / "config/themes" / SYNC, images=0)
    if user:
        (root / "config/backgrounds").mkdir()
        (root / "config/backgrounds/u.jpg").write_bytes(b"jpg")


def write(path, data="{}"):
    """PATH rewritten in place, through its own inode."""
    with open(path, "r+") as file:
        file.write(data)


def replace(path, data="{}"):
    """A write beside PATH renamed over it, as a save or a package swap does."""
    staged = path.with_name("." + path.name + ".new")
    staged.write_text(data)
    staged.rename(path)


def started(helper_path, root, prepare=world):
    prepare(root)
    return Helper(helper_path, root)


def one_change(action, listed=False, names=(), allowed=(), prepare=world):
    """A case of ACTION on the neutral world, as its single change."""
    def case(root, helper_path):
        helper = started(helper_path, root, prepare)
        try:
            return helper.ready and change(helper, root, lambda: action(root), listed, names, allowed)
        finally:
            helper.stop()
    return case


def themes(root, *parts):
    return root.joinpath("config/themes", *parts)


def copied_in(root):
    package(root / "elsewhere/new")
    shutil.copytree(root / "elsewhere/new", themes(root, "new"))


def staged_in_is_watched(root, helper_path):
    """A package renamed in, as an install lands, reports under its name."""
    stage = root / "config/.vgshell-theme-add.x/new"
    helper = started(helper_path, root, lambda root: (world(root), package(stage)))
    try:
        return helper.ready and change(helper, root, lambda: stage.rename(themes(root, "new")), True) \
            and change(helper, root, lambda: write(themes(root, "new/theme.json")), names=["new"])
    finally:
        helper.stop()


def swapped_name_moves(root, helper_path):
    """After a rename the package reports under its new name alone."""
    helper = started(helper_path, root)
    try:
        return helper.ready and change(helper, root, lambda: themes(root, "a").rename(themes(root, "b")), True) \
            and change(helper, root, lambda: write(themes(root, "b/theme.json")), names=["b"]) \
            and change(helper, root, lambda: write(themes(root, "b/backgrounds/0.jpg")), names=["b"])
    finally:
        helper.stop()


def moved_out_is_silent(root, helper_path):
    """A package moved off its path, as an update sets the old one aside, reports nothing more."""
    helper = started(helper_path, root)
    old = root / "config/.vgshell-old"
    try:
        return helper.ready and change(helper, root, lambda: themes(root, "a").rename(old), True) \
            and change(helper, root, lambda: write(old / "theme.json")) \
            and change(helper, root, lambda: write(old / "backgrounds/0.jpg"))
    finally:
        helper.stop()


def late_backgrounds_is_watched(root, helper_path):
    """A backgrounds folder made after start is watched."""
    def prepare(root):
        world(root)
        shutil.rmtree(themes(root, "a/backgrounds"))
    helper = started(helper_path, root, prepare)
    try:
        return helper.ready and change(helper, root, lambda: themes(root, "a/backgrounds").mkdir(), names=["a"]) \
            and change(helper, root, lambda: themes(root, "a/backgrounds/1.jpg").write_bytes(b"jpg"), names=["a"])
    finally:
        helper.stop()


def late_folders_are_watched(root, helper_path):
    """themes/ and backgrounds/ absent at start are watched once made."""
    helper = started(helper_path, root, lambda root: world(root, themes=False, user=False))
    try:
        return helper.ready and change(helper, root, lambda: themes(root).mkdir(), True) \
            and change(helper, root, lambda: themes(root, SYNC).mkdir(), True) \
            and change(helper, root, lambda: (root / "config/backgrounds").mkdir(), True) \
            and change(helper, root, lambda: (root / "config/backgrounds/u.jpg").write_bytes(b"jpg"), names=[""]) \
            and change(helper, root, lambda: package(themes(root, "p")), True, allowed=["p"]) \
            and change(helper, root, lambda: write(themes(root, "p/backgrounds/0.jpg")), names=["p"])
    finally:
        helper.stop()


def take_theme_lock(root):
    """What every theme command does: open the lock for append and close it."""
    with open(root / "config/theme.lock", "a"):
        pass


def config_writes_are_nothing(root, helper_path):
    """A write in place under CONFIG is no change; a shell.json save, a rename, still is."""
    helper = started(helper_path, root)
    try:
        return helper.ready and change(helper, root, lambda: take_theme_lock(root)) \
            and change(helper, root, lambda: write(root / "config/screensaver.txt", "more")) \
            and change(helper, root, lambda: replace(root / "config/shell.json"), True)
    finally:
        helper.stop()


def inotify(pid):
    """The inotify fds of PID and the watches each holds."""
    found = {}
    for fd in os.listdir(f"/proc/{pid}/fd"):
        try:
            if os.readlink(f"/proc/{pid}/fd/{fd}") == "anon_inode:inotify":
                info = Path(f"/proc/{pid}/fdinfo/{fd}").read_text()
                found[fd] = sum(line.startswith("inotify wd:") for line in info.splitlines())
        except FileNotFoundError:
            continue
    return found


def one_instance(root, helper_path):
    """40 packages of 5 images cost one instance; moved-out folders drop their watches."""
    def prepare(root):
        world(root)
        for index in range(40):
            package(themes(root, f"p{index:02}"), images=5)
    helper = started(helper_path, root, prepare)
    try:
        if not helper.ready:
            return False
        # CONFIG, themes/, backgrounds/ and the catalog, then each package and its backgrounds/.
        folders = 4 + 2 * len(os.listdir(themes(root)))
        if list(inotify(helper.proc.pid).values()) != [folders]:
            return False
        (root / "aside").mkdir()
        for index in range(10):
            if not change(helper, root, lambda: themes(root, f"p{index:02}").rename(root / f"aside/p{index:02}"), True):
                return False
        return list(inotify(helper.proc.pid).values()) == [folders - 2 * 10]
    finally:
        helper.stop()


PARENT = '''import subprocess,sys,signal
child=subprocess.Popen([sys.executable]+sys.argv[1:],stdin=subprocess.DEVNULL,stdout=subprocess.PIPE)
child.stdout.readline()
print(child.pid,flush=True)
while True: signal.pause()
'''


def ends_with_its_parent(root, helper_path):
    """The parent's death ends the helper within the cleanup grace."""
    world(root)
    parent = subprocess.Popen([sys.executable, "-c", PARENT, str(helper_path), str(root / "config"), str(root / "catalog")],
                              stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, env=ENV)
    pidfd = None
    try:
        if not select.select([parent.stdout], [], [], WAIT)[0]:
            return False
        # The helper is the parent's unreaped child, so its pid is its own until the parent goes.
        pidfd = os.pidfd_open(int(parent.stdout.readline()))
        if select.select([pidfd], [], [], 0)[0]:
            return False
        parent.kill()
        parent.wait()
        return bool(select.select([pidfd], [], [], WAIT)[0])
    finally:
        parent.kill()
        parent.wait()
        parent.stdout.close()
        if pidfd is not None:
            try:
                signal.pidfd_send_signal(pidfd, signal.SIGKILL)
            except ProcessLookupError:
                pass
            select.select([pidfd], [], [], WAIT)
            os.close(pidfd)


def ends_on_sigterm(root, helper_path):
    """SIGTERM ends the helper at once, by the default disposition."""
    helper = started(helper_path, root)
    try:
        helper.proc.send_signal(signal.SIGTERM)
        return helper.ready and helper.proc.wait(timeout=WAIT) == -signal.SIGTERM
    except subprocess.TimeoutExpired:
        return False
    finally:
        helper.stop()


def unwatchable_folder_fails(root, helper_path):
    """A present folder the helper may not watch fails setup: no partial watch set."""
    world(root)
    os.chmod(themes(root, "a"), 0)
    try:
        helper = Helper(helper_path, root)
    finally:
        os.chmod(themes(root, "a"), 0o755)
    try:
        if helper.ready or helper.proc.wait(timeout=WAIT) != 1:
            return False
        # The service logs this line; its stable key leads it.
        return helper.proc.stderr.read().decode().startswith(f"watch.py: watch=failed reason=setup path={themes(root, 'a')}: ")
    finally:
        helper.stop()


CASES = [
    ("a package copied in is a list change", one_change(copied_in, True, allowed=["new"])),
    ("a package renamed in is watched under its name", staged_in_is_watched),
    ("a package removed is a list change", one_change(lambda root: shutil.rmtree(themes(root, "a")), True, allowed=["a"])),
    ("a package renamed reports its new name alone", swapped_name_moves),
    ("a package moved out reports nothing more", moved_out_is_silent),
    ("theme.json written in place", one_change(lambda root: write(themes(root, "a/theme.json")), names=["a"])),
    ("terminal.json written in place", one_change(lambda root: write(themes(root, "a/terminal.json")), names=["a"])),
    ("theme.json replaced by rename", one_change(lambda root: replace(themes(root, "a/theme.json")), names=["a"])),
    ("terminal.json replaced by rename", one_change(lambda root: replace(themes(root, "a/terminal.json")), names=["a"])),
    ("preview.jpg created", one_change(lambda root: themes(root, "a/preview.jpg").write_bytes(b"jpg"), names=["a"])),
    ("an image created", one_change(lambda root: themes(root, "a/backgrounds/1.jpg").write_bytes(b"jpg"), names=["a"])),
    ("an image rewritten in place", one_change(lambda root: write(themes(root, "a/backgrounds/0.jpg"), "gpj"), names=["a"])),
    ("an image deleted", one_change(lambda root: themes(root, "a/backgrounds/0.jpg").unlink(), names=["a"])),
    ("a backgrounds folder made after start is watched", late_backgrounds_is_watched),
    ("themes and backgrounds made after start are watched", late_folders_are_watched),
    ("a user image added", one_change(lambda root: (root / "config/backgrounds/v.jpg").write_bytes(b"jpg"), names=[""])),
    ("a user image rewritten in place", one_change(lambda root: write(root / "config/backgrounds/u.jpg", "gpj"), names=[""])),
    ("the catalog index replaced", one_change(lambda root: replace(root / "catalog/index.json"), True)),
    ("another catalog file is nothing", one_change(lambda root: (root / "catalog/other.json").write_text("{}"))),
    ("a shell.json save is a list change", one_change(lambda root: replace(root / "config/shell.json"), True)),
    ("a write in place in the config folder is nothing", config_writes_are_nothing),
    ("one inotify instance for 40 packages of 5 images", one_instance),
    ("the parent's death ends the helper", ends_with_its_parent),
    ("SIGTERM ends the helper", ends_on_sigterm),
    ("an unwatchable folder fails setup", unwatchable_folder_fails),
]
CASE = dict(CASES)

# Each control: the case it must fail and the edits, each a text removed and
# what replaces it.
NO_CLOSE_WRITE = [("MASK = IN_CLOSE_WRITE | ", "MASK = ")]
STALE = [("    watches.clear()\n    watches.update(armed)\n",
          "    watches.update({wd: item for wd, item in armed.items() if wd not in watches})\n")]
KEPT = [("        libc.inotify_rm_watch(fd, wd)", "        pass")]
CONTROLS = [
    ("no-close-write", "theme.json written in place", NO_CLOSE_WRITE),
    ("no-close-write-image", "an image rewritten in place", NO_CLOSE_WRITE),
    ("no-entry-reconcile", "a backgrounds folder made after start is watched",
     [('name in (b"themes", b"backgrounds")):\n            again = True\n', 'name in (b"themes", b"backgrounds")):\n            pass\n')]),
    ("stale-names", "a package renamed reports its new name alone", STALE),
    # A folder moved out is silenced twice: its watch is removed and its wd unmapped.
    ("stale-moved-out", "a package moved out reports nothing more", KEPT + STALE),
    ("kept-watches", "one inotify instance for 40 packages of 5 images", KEPT),
    ("two-instances", "one inotify instance for 40 packages of 5 images",
     [("        fd = libc.inotify_init1(os.O_CLOEXEC)", "        libc.inotify_init1(0)\n        fd = libc.inotify_init1(os.O_CLOEXEC)")]),
    ("whole-catalog", "another catalog file is nothing", [(' and name == b"index.json"', "")]),
    ("unlisted-save", "a shell.json save is a list change", [('        if kind in ("config", "themes"):\n', '        if kind == "themes":\n')]),
    ("listed-config-write", "a write in place in the config folder is nothing",
     [("            listed |= bool(mask & ENTRY)\n", "            listed = True\n")]),
    ("no-pdeathsig", "the parent's death ends the helper", [("libc.prctl(PR_SET_PDEATHSIG, SIGTERM, 0, 0, 0) == -1", "False")]),
    ("sigterm-ignored", "SIGTERM ends the helper",
     [("    parent = os.getppid()\n", "    import signal\n    signal.signal(signal.SIGTERM, signal.SIG_IGN)\n    parent = os.getppid()\n")]),
    ("unwatchable-skipped", "an unwatchable folder fails setup", [("    if err in (errno.ENOENT, errno.ENOTDIR):", "    if True:")]),
]


def main():
    failed = []
    with tempfile.TemporaryDirectory(prefix="theme-watch-test-") as temp:
        base = Path(temp).resolve()
        for index, (label, case) in enumerate(CASES):
            if not case(base / "cases" / str(index), HELPER):
                failed.append(label)
        source = HELPER.read_text()
        for name, label, edits in CONTROLS:
            mutated = source
            for before, after in edits:
                assert mutated.count(before) == 1, f"control {name}: the text to replace must occur once"
                mutated = mutated.replace(before, after)
            mutant = base / "controls" / name / "watch.py"
            mutant.parent.mkdir(parents=True)
            mutant.write_text(mutated)
            if CASE[label](base / "controls" / name / "world", mutant):
                failed.append(f"control did not fail: {name}")
    if failed:
        sys.exit("test-theme-watch: failed: " + "; ".join(failed))
    print("test-theme-watch: pass; controls=" + ",".join(name for name, _, _ in CONTROLS))


if __name__ == "__main__":
    main()
