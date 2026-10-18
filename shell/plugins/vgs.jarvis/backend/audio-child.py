#!/usr/bin/env python3
"""Child bootstrap. fd 3 is the caller's lease; fd 4 reports readiness.

setpriv arms parent death before this bootstrap checks its expected parent.
The namespace init retains the lease and exits on EOF. Its death kills every
descendant, including a tool that forks or creates another process group.
See docs/decisions/D064-jarvis-child-lease.md.
Host installation repair retains the same lease without changing namespaces.
"""
import ctypes
import os
import signal
import time
import selectors
import subprocess
import sys


def finish_host(child):
    # Subreaping retains each adopted PID until waitpid reaps it. Only these
    # owned children are signalled; /proc names no process outside this lease.
    pending = {}
    while True:
        with open(f"/proc/self/task/{os.getpid()}/children") as stream:
            children = [int(value) for value in stream.read().split()]
        if not children:
            return
        now = time.monotonic()
        for pid in children:
            if pid in pending and pending[pid] is None:
                continue
            # An elevation owner can also hide its proc metadata. Unknown
            # credentials retain the lock; they never grant signal authority.
            try:
                owned = os.stat(f"/proc/{pid}").st_uid == os.geteuid()
            except OSError:
                owned = False
            if not owned:
                pending[pid] = None
                continue
            first = pid not in pending
            since = pending.setdefault(pid, now)
            if not first and now - since < 1:
                continue
            try:
                os.kill(pid, signal.SIGTERM if first else signal.SIGKILL)
            except ProcessLookupError:
                continue
            except PermissionError:
                # An elevation owner controls its root child. Retain the
                # repair lock and wait for that child instead of orphaning it.
                pending[pid] = None
        while True:
            try:
                pid, status = os.waitpid(-1, os.WNOHANG)
            except ChildProcessError:
                return
            if pid == 0:
                break
            pending.pop(pid, None)
            if pid == child.pid:
                child.returncode = os.waitstatus_to_exitcode(status)
        # This observes child exit and newly adopted descendants after TERM.
        time.sleep(0.05)


def main():
    mode, parent, *command = sys.argv[1:]
    if mode in ("outer", "exec", "host"):
        if os.getppid() != int(parent):
            raise RuntimeError("parent-ended")
    if mode == "outer":
        os.set_inheritable(3, True)
        os.set_inheritable(4, True)
        os.execvp("unshare", ["unshare", "--map-current-user", "--pid", "--fork",
                             "--kill-child=KILL", "--", sys.executable, "-I",
                             __file__, "init", "0", *command])
    if mode == "exec":
        os.write(4, b"R")
        os.close(4)
        os.execvp(command[0], command)
    if mode == "host":
        # PR_SET_CHILD_SUBREAPER keeps detached descendants with this owner.
        # https://man7.org/linux/man-pages/man2/PR_SET_CHILD_SUBREAPER.2const.html
        if ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), "subreaper")
        for number in (signal.SIGINT, signal.SIGHUP, signal.SIGTERM):
            signal.signal(number, lambda *_: None)
    elif mode != "init" or os.getpid() != 1:
        raise RuntimeError("namespace-init")
    # No tool starts if the outer parent's death raced unshare's fork.
    if os.read(3, 1) != b"S":
        raise RuntimeError("lease-ended")
    child = subprocess.Popen(
        ["setpriv", "--pdeathsig", "KILL", "--", sys.executable, "-I",
         __file__, "exec", str(os.getpid()), *command],
        env=dict(os.environ), pass_fds=(4,))
    try:
        os.close(4)
        selector = selectors.DefaultSelector()
        selector.register(3, selectors.EVENT_READ)
        while child.poll() is None:
            # This wait observes the lease while also reaping a naturally ended
            # tool. It is not a startup delay or a device-retry backoff.
            if selector.select(0.05):
                if os.read(3, 1) == b"":
                    break
                raise RuntimeError("lease-data")
    finally:
        if mode == "host":
            finish_host(child)
    code = child.returncode if child.returncode is not None else 0
    return code if code >= 0 else 128 - code


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError) as error:
        print("jarvis: audio-child=" + str(error), file=sys.stderr)
        sys.exit(70)
