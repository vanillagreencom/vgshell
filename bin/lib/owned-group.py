#!/usr/bin/env python3
"""Own an isolated query group: PARENT GRACE COMMAND... in a new session.

setpriv --pdeathsig TERM arms parent death before this executor starts.
The query inherits the caller's environment, streams and descriptors.
Only a query that leaves descendants needs a detached cleanup lifetime.
"""

import ctypes
import errno
import os
import selectors
import signal
import sys
import time


STOP_SIGNALS = (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)


def children_remain():
    while True:
        try:
            pid, _ = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            return False
        if pid == 0:
            return True


def drain(fd):
    try:
        os.read(fd, 4096)
    except BlockingIOError:
        pass


def wait_for_children(grace, wakeup):
    deadline = time.monotonic() + grace
    with selectors.DefaultSelector() as selector:
        selector.register(wakeup, selectors.EVENT_READ)
        while children_remain():
            remaining = None if deadline is None else max(0, deadline - time.monotonic())
            if remaining == 0:
                break
            selector.select(remaining)
            drain(wakeup)


def ignore_stops():
    for signum in STOP_SIGNALS:
        signal.signal(signum, signal.SIG_IGN)


def stop_group(group, grace, wakeup):
    ignore_stops()
    os.killpg(group, signal.SIGTERM)
    # Keep responsive cleanup and the one deadline at the shared owner.
    wait_for_children(grace, wakeup)
    os.killpg(group, signal.SIGKILL)


def finish_descendants(group, grace):
    # The child must close caller locks as well as streams before the result
    # leader returns. Its group membership holds the PGID until final KILL.
    ignore_stops()
    ready, acknowledgement = os.pipe()
    cleaner = os.fork()
    if cleaner == 0:
        signal.set_wakeup_fd(-1)
        for entry in os.listdir('/proc/self/fd'):
            fd = int(entry)
            if fd == acknowledgement:
                continue
            try:
                os.close(fd)
            except OSError as error:
                if error.errno != errno.EBADF:
                    os._exit(1)
        os.write(acknowledgement, b'1')
        os.close(acknowledgement)
        os.killpg(group, signal.SIGTERM)
        # Adopted descendants remain children of the result leader until it
        # exits, so this member retains the group for the full bounded grace.
        time.sleep(grace)
        os.killpg(group, signal.SIGKILL)
        os._exit(1)
    os.close(acknowledgement)
    acknowledged = os.read(ready, 1)
    os.close(ready)
    if acknowledged != b'1':
        print('owned-group: refused: cleanup=descriptor-close', file=sys.stderr)
        os.killpg(group, signal.SIGKILL)


def main():
    parent, grace = int(sys.argv[1]), float(sys.argv[2])
    command = sys.argv[3:]
    group = os.getpid()
    if os.getpgrp() != group or os.getsid(0) != group:
        print('owned-group: refused: session=unowned', file=sys.stderr)
        return 1
    # Linux reparents orphaned descendants to the nearest ancestor subreaper.
    # After waitpid reaps this query, ECHILD therefore proves an empty owned
    # tree, without a racy /proc snapshot or a worker on every picker poll.
    # https://man7.org/linux/man-pages/man2/PR_SET_CHILD_SUBREAPER.2const.html
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
        print('owned-group: refused: subreaper=failed', file=sys.stderr)
        return 1
    read_fd, write_fd = os.pipe2(os.O_CLOEXEC | os.O_NONBLOCK)
    stopped = []

    def requested(signum, frame):
        if not stopped:
            stopped.append(signum)

    for signum in STOP_SIGNALS:
        signal.signal(signum, requested)
    signal.signal(signal.SIGCHLD, lambda signum, frame: None)
    signal.set_wakeup_fd(write_fd, warn_on_full_buffer=False)
    if os.getppid() != parent:
        print('owned-group: refused: parent=changed', file=sys.stderr)
        return 1
    if stopped:
        return 128 + stopped[0]
    child = os.fork()
    if child == 0:
        signal.set_wakeup_fd(-1)
        for signum in (*STOP_SIGNALS, signal.SIGCHLD, signal.SIGPIPE):
            signal.signal(signum, signal.SIG_DFL)
        os.close(read_fd)
        os.close(write_fd)
        try:
            os.execvp(command[0], command)
        except OSError as error:
            print(f'owned-group: exec=failed errno={error.errno}', file=sys.stderr)
            os._exit(127 if error.errno == errno.ENOENT else 126)
    with selectors.DefaultSelector() as selector:
        selector.register(read_fd, selectors.EVENT_READ)
        while True:
            if stopped:
                stop_group(group, grace, read_fd)
            pid, status = os.waitpid(child, os.WNOHANG)
            if pid:
                break
            selector.select()
            drain(read_fd)
    if children_remain():
        finish_descendants(group, grace)
    return os.waitstatus_to_exitcode(status) if os.WIFEXITED(status) else 128 + os.WTERMSIG(status)


if __name__ == '__main__':
    sys.exit(main())
