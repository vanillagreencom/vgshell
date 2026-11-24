#!/usr/bin/env python3
# loads: scripts/nested-slot.sh -- the controls read the slot script beside them
"""Exercise fleet admission with private load/cgroup files and a sleep barrier.

No host load is generated and no real slot is taken. The copied production
wrapper retains its admission logic; only its external file reads move into
the fixture. Removing its load decision must fail the same high-load case.
"""
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile


SOURCE = Path(__file__).with_name("nested-slot.sh").read_text()


def replace_once(source, old, new):
    assert source.count(old) == 1, old
    return source.replace(old, new)


def admission(source, reading, held, rise_at_slot=False):
    with tempfile.TemporaryDirectory(prefix="nested-slot-") as scratch:
        root = Path(scratch)
        (root / "bin").mkdir()
        load = root / "load"
        load.write_text(reading)
        (root / "cgroup").write_text("0::/user@1000.service/agents.slice/test.service\n")
        os.mkfifo(root / "release")
        sleep = root / "bin/sleep"
        sleep.write_text("#!/usr/bin/python3\nimport os\n"
                         "fd = os.open('release', os.O_RDWR)\n"
                         "print('waiting', flush=True)\nos.read(fd, 1)\n")
        sleep.chmod(0o755)
        if rise_at_slot:
            (root / "raise").touch()
            flock = root / "bin/flock"
            flock.write_text('#!/bin/bash\n/usr/bin/flock "$@" || exit "$?"\n'
                             'if [[ -f raise ]]; then printf "8.00 0 0 1/1 1\\n" > load; rm raise; fi\n')
            flock.chmod(0o755)
        copied = source.replace("/proc/loadavg", str(load))
        copied = copied.replace("/proc/self/cgroup", str(root / "cgroup"))
        copied = replace_once(copied, "dir=/home/method/dev/vgshell/tmp/nested-slots",
                              "dir=" + str(root / "slots"))
        wrapper = root / "nested-slot.sh"
        wrapper.write_text(copied)
        marker = root / "ran"
        env = {"PATH": str(root / "bin") + ":/usr/bin:/bin",
               "NESTED_SLOTS": "1", "XDG_RUNTIME_DIR": str(root), "VGS_TEST_RUN": "1"}
        proc = subprocess.Popen(["bash", str(wrapper), sys.executable, "-c",
                                 "from pathlib import Path; Path('ran').touch()"],
                                cwd=root, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, start_new_session=True)
        try:
            if held:
                ready, _, _ = select.select([proc.stdout], [], [], 5)
                assert ready and proc.stdout.readline() == b"waiting\n", "no hold barrier"
                assert not marker.exists(), "command entered while load was held"
                load.write_text("7.99 0 0 1/1 1\n")
                fd = os.open(root / "release", os.O_WRONLY | os.O_NONBLOCK)
                os.write(fd, b"x")
                os.close(fd)
            _, stderr = proc.communicate(timeout=5)
            assert proc.returncode == 0, stderr.decode()
            assert marker.exists(), "command not admitted below limit"
            assert not list((root / "slots/queue").iterdir()), "ticket leaked"
        finally:
            # This group belongs to this fixture and never leaves its scratch cwd.
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.communicate(timeout=5)


for name, reading, held, rise_at_slot in [
    ("below limit", "7.99 0 0 1/1 1\n", False, False),
    ("at limit", "8.00 0 0 1/1 1\n", True, False),
    ("incident load", "11409.27 0 0 1/1 1\n", True, False),
    ("unreadable load", "", True, False),
    ("malformed load", "unknown\n", True, False),
    ("load rises while taking a slot", "7.99 0 0 1/1 1\n", True, True),
]:
    admission(SOURCE, reading, held, rise_at_slot)
    print("  ok    admission " + name)

mutant = replace_once(SOURCE, "load_ready() {", "load_ready() { return 0; ")
try:
    admission(mutant, "11409.27 0 0 1/1 1\n", True)
except AssertionError:
    print("  ok    control: a missing load gate fails admission")
else:
    raise AssertionError("missing load gate passed admission")
