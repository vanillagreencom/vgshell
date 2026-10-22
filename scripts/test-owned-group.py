#!/usr/bin/env python3
"""Private query groups preserve results and end after their owner is killed.

Every PID comes from a fixture this suite started, and held pidfds protect
both liveness readings and cleanup from PID reuse. No shell or session API
is started. The control removes the owner's signal handler in a disposable
copy and must leave the same stubborn descendants running.
"""

import fcntl
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parent.parent
OWNER = REPO / "bin/lib/owned-group.py"
BASH_OWNER = REPO / "bin/lib/owned-group.sh"
ENV = {"PATH": os.defpath, "LC_ALL": "C", "VGS_TEST_RUN": "1"}
FIXTURE = '''import json,os,pathlib,signal,sys,time
root=pathlib.Path(sys.argv[1])
stubborn=sys.argv[2] == "stubborn"
child=os.fork()
if child == 0:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    (root/"grandchild").write_text(str(os.getpid()))
    while True: signal.pause()
def stop(signum,frame):
    (root/"term-ack").write_text("ack")
    sys.exit(0)
signal.signal(signal.SIGTERM, signal.SIG_IGN if stubborn else stop)
while not (root/"grandchild").exists(): time.sleep(0.01)
(root/"ready").write_text(json.dumps([os.getpid(),child]))
while True: signal.pause()
'''
PARENT = '''import os,pathlib,signal,subprocess,sys
owner,root,fixture,mode=sys.argv[1:]
child=subprocess.Popen(["env","--default-signal=TERM,INT,HUP","setpriv","--pdeathsig","TERM","--",owner,str(os.getpid()),"0.2",sys.executable,fixture,root,mode],start_new_session=True,env={"PATH":os.defpath,"LC_ALL":"C","VGS_TEST_RUN":"1"})
pathlib.Path(root,"owner").write_text(str(child.pid))
while True: signal.pause()
'''
RETURNING = '''import json,os,pathlib,signal,sys,time
root=pathlib.Path(sys.argv[1])
lock_fd=int(sys.argv[2])
os.fstat(lock_fd)
pids=[]
for mode in ("responsive", "stubborn"):
    child=os.fork()
    if child == 0:
        os.close(lock_fd)
        def stop(signum,frame):
            (root/"term-ack").write_text("ack")
            sys.exit(0)
        signal.signal(signal.SIGTERM, stop if mode == "responsive" else signal.SIG_IGN)
        (root/mode).write_text(str(os.getpid()))
        while True: signal.pause()
    pids.append(child)
while not all((root/name).exists() for name in ("responsive", "stubborn")): time.sleep(0.01)
(root/"ready").write_text(json.dumps(pids))
while not (root/"return").exists(): time.sleep(0.01)
print("query-output", flush=True)
print("query-error", file=sys.stderr, flush=True)
sys.exit(7)
'''


def exited(fd):
    poll = select.poll()
    poll.register(fd, select.POLLIN)
    return bool(poll.poll(0))


class OwnedGroupTests(unittest.TestCase):
    def owned_jobs(self, owner):
        with tempfile.TemporaryDirectory(prefix="owned-group-jobs-") as directory:
            fixture = Path(directory) / "job.py"
            fixture.write_text('''import pathlib,signal,sys
def stop(signum,frame):
    pathlib.Path(sys.argv[1]).write_text("ack")
    sys.exit(0)
signal.signal(signal.SIGTERM, stop)
print("ready", flush=True)
for line in sys.stdin:
    print("pong", flush=True)
''')
            script = '''set -euo pipefail
source "$1"
true &
finished=$!
wait "$finished"
coproc QUERY { exec "$2" "$3" "$4"; }
running=$QUERY_PID
input=${QUERY[1]}
output=${QUERY[0]}
read -r ready <&"$output"
[[ $ready == ready ]]
owned_group_stop "$finished"
printf 'ping\\n' >&"$input"
read -r pong <&"$output"
[[ $pong == pong ]]
owned_group_stop "$running"
wait "$running"
[[ -f $4 ]]
'''
            job = subprocess.Popen(["/bin/bash", "-c", script, "owned-jobs", str(owner), sys.executable,
                                    str(fixture), str(Path(directory) / "ack")],
                                   start_new_session=True, env=ENV, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                stdout, stderr = job.communicate(timeout=5)
                self.assertEqual(job.returncode, 0, stdout + stderr)
            finally:
                if job.poll() is None:
                    os.killpg(job.pid, signal.SIGKILL)
                job.communicate(timeout=5)

    def test_owned_job_stop_ignores_completed_jobs(self):
        self.owned_jobs(BASH_OWNER)
        with tempfile.TemporaryDirectory(prefix="owned-group-job-control-") as directory:
            control = Path(directory) / "owned-group.sh"
            source = BASH_OWNER.read_text()
            needle = '[[ $job_pid == "$pid" && $spec == \\[* ]] || continue'
            self.assertEqual(source.count(needle), 1)
            control.write_text(source.replace(needle, '[[ $spec == \\[* ]] || continue', 1))
            with self.assertRaises(AssertionError):
                self.owned_jobs(control)

    def returning_query(self, owner):
        with tempfile.TemporaryDirectory(prefix="owned-group-returning-") as directory:
            root = Path(directory)
            fixture = root / "fixture.py"
            fixture.write_text(RETURNING)
            lock_path = root / "query.lock"
            lock = lock_path.open("w")
            fcntl.flock(lock, fcntl.LOCK_EX)
            query = subprocess.Popen([str(owner), str(os.getpid()), "0.2", sys.executable, str(fixture), directory, str(lock.fileno())],
                                     start_new_session=True, env=ENV, stdin=subprocess.DEVNULL,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                     pass_fds=(lock.fileno(),))
            lock.close()
            held = []
            try:
                deadline = time.monotonic() + 5
                while not (root / "ready").exists():
                    self.assertIsNone(query.poll(), "query ended before descendant readiness")
                    self.assertLess(time.monotonic(), deadline, "query readiness timeout")
                    time.sleep(0.01)
                held = [os.pidfd_open(pid) for pid in json.loads((root / "ready").read_text())]
                self.assertTrue(all(not exited(fd) for fd in held))
                (root / "return").touch()
                self.assertEqual(query.wait(timeout=3), 7)
                with lock_path.open("w") as next_query:
                    try:
                        fcntl.flock(next_query, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except BlockingIOError:
                        self.fail("returned query retained the caller lock")
                deadline = time.monotonic() + 3
                while any(not exited(fd) for fd in held) and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(all(exited(fd) for fd in held), "descendants survived a returned query")
                self.assertTrue((root / "term-ack").exists(), "returned query skipped responsive cleanup")
                stdout, stderr = query.communicate(timeout=3)
                self.assertEqual(stdout, "query-output\n")
                self.assertEqual(stderr, "query-error\n")
            finally:
                if query.poll() is None:
                    query.kill()
                query.wait(timeout=3)
                for fd in held:
                    if not exited(fd):
                        signal.pidfd_send_signal(fd, signal.SIGKILL)
                    os.close(fd)
                query.communicate(timeout=3)

    def test_returning_query_cleans_descendants(self):
        self.returning_query(OWNER)
        with tempfile.TemporaryDirectory(prefix="owned-group-return-control-") as directory:
            control = Path(directory) / "owned-group.py"
            source = OWNER.read_text()
            needle = '        finish_descendants(group, grace)\n'
            self.assertEqual(source.count(needle), 1)
            control.write_text(source.replace(needle, "        pass\n", 1))
            control.chmod(0o755)
            with self.assertRaisesRegex(AssertionError, "descendants survived a returned query"):
                self.returning_query(control)
        with tempfile.TemporaryDirectory(prefix="owned-group-fd-control-") as directory:
            control = Path(directory) / "owned-group.py"
            source = OWNER.read_text()
            needle = '            if fd == acknowledgement:'
            self.assertEqual(source.count(needle), 1)
            control.write_text(source.replace(needle, '            if fd == acknowledgement or fd > 2:', 1))
            control.chmod(0o755)
            with self.assertRaisesRegex(AssertionError, "returned query retained the caller lock"):
                self.returning_query(control)

    def empty_query(self, owner):
        # Hold the real child and all its inherited streams until it exits.
        # An empty owner must leave neither a cleaner nor a timer in its
        # session; the picker runs this same entry point on each 100ms poll.
        query = subprocess.Popen([str(owner), str(os.getpid()), "0.3", "/usr/bin/true"],
                                 start_new_session=True, env=ENV, stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        held = []
        try:
            self.assertEqual(query.wait(timeout=3), 0)
            for entry in Path('/proc').iterdir():
                if not entry.name.isdigit():
                    continue
                try:
                    fields = (entry / 'stat').read_text().rsplit(') ', 1)[1].split()
                    if fields[0] != 'Z' and int(fields[2]) == query.pid:
                        held.append(os.pidfd_open(int(entry.name)))
                except (FileNotFoundError, ProcessLookupError):
                    continue
            self.assertFalse(held, "empty query retained cleanup processes")
            self.assertEqual(query.communicate(timeout=1), (b'', b''))
        finally:
            if query.poll() is None:
                query.kill()
            query.wait(timeout=3)
            for fd in held:
                if not exited(fd):
                    signal.pidfd_send_signal(fd, signal.SIGKILL)
                os.close(fd)
            query.communicate(timeout=3)

    def test_empty_query_releases_cleanup_resources(self):
        self.empty_query(OWNER)
        with tempfile.TemporaryDirectory(prefix="owned-group-empty-control-") as directory:
            control = Path(directory) / "owned-group.py"
            source = OWNER.read_text()
            needle = '    if children_remain():\n        finish_descendants(group, grace)'
            self.assertEqual(source.count(needle), 1)
            control.write_text(source.replace(needle, '    if True:\n        finish_descendants(group, grace)', 1))
            control.chmod(0o755)
            with self.assertRaisesRegex(AssertionError, "empty query retained cleanup processes"):
                self.empty_query(control)

    def exercise(self, owner, mode):
        with tempfile.TemporaryDirectory(prefix="owned-group-") as directory:
            root = Path(directory)
            fixture, parent_script = root / "fixture.py", root / "parent.py"
            fixture.write_text(FIXTURE)
            parent_script.write_text(PARENT)
            parent = subprocess.Popen([sys.executable, str(parent_script), str(owner), directory, str(fixture), mode],
                                      env=ENV, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            held = []
            try:
                deadline = time.monotonic() + 5
                while not (root / "ready").exists():
                    self.assertIsNone(parent.poll(), "fixture owner exited before readiness")
                    self.assertLess(time.monotonic(), deadline, "fixture readiness timeout")
                    time.sleep(0.01)
                pids = [int((root / "owner").read_text()), *json.loads((root / "ready").read_text())]
                held = [os.pidfd_open(pid) for pid in pids]
                self.assertTrue(all(not exited(fd) for fd in held))
                parent.kill()
                parent.wait(timeout=5)
                deadline = time.monotonic() + 3
                while any(not exited(fd) for fd in held) and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(all(exited(fd) for fd in held), "owned descendants survived their killed owner")
                if mode == "responsive":
                    self.assertTrue((root / "term-ack").exists(), "responsive query received no cleanup signal")
            finally:
                if parent.poll() is None:
                    parent.kill()
                parent.wait(timeout=5)
                for fd in held:
                    if not exited(fd):
                        signal.pidfd_send_signal(fd, signal.SIGKILL)
                    os.close(fd)

    def test_owner_death_and_control(self):
        for mode in ("responsive", "stubborn"):
            with self.subTest(mode=mode):
                self.exercise(OWNER, mode)
        with tempfile.TemporaryDirectory(prefix="owned-group-control-") as directory:
            control = Path(directory) / "owned-group.py"
            text = OWNER.read_text()
            needle = "        signal.signal(signum, requested)\n"
            self.assertEqual(text.count(needle), 1)
            control.write_text(text.replace(needle, "        signal.signal(signum, signal.SIG_DFL)\n", 1))
            control.chmod(0o755)
            with self.assertRaisesRegex(AssertionError, "owned descendants survived"):
                self.exercise(control, "stubborn")

    def test_normal_result_and_refusals(self):
        argv = [str(OWNER), str(os.getpid()), "0.2", sys.executable, "-c", "import json,sys; print(json.dumps(sys.argv[1:])); sys.exit(7)", "a b", "$(false)"]
        result = subprocess.run(argv, start_new_session=True, env=ENV, stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 7)
        self.assertEqual(json.loads(result.stdout), ["a b", "$(false)"])
        for own_session, parent in ((False, str(os.getpid())), (True, "0")):
            result = subprocess.run([str(OWNER), parent, "0.2", "false"], start_new_session=own_session,
                                    env=ENV, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 1)


if __name__ == "__main__":
    unittest.main()
