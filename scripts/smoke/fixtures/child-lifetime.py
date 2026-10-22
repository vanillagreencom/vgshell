#!/usr/bin/env python3
"""Inert sleep tools and a pidfd observer for the child-lifetime smoke row.

The inhibitor transparently passes its fixture environment to sleep-watch.
The monitor forks a child that ignores TERM, so shell cleanup must reach
owned descendants rather than only each QProcess's immediate child.
"""

import errno
import json
import os
from pathlib import Path
import select
import signal
import sys
import time


def publish(path, value):
    temporary = Path(str(path) + ".next")
    temporary.write_text(json.dumps(value) + "\n")
    temporary.replace(path)


def process(pid):
    folder = Path(f"/proc/{pid}")
    stat = (folder / "stat").read_text().rsplit(") ", 1)[1].split()
    return {"pid": pid, "parent": int(stat[1]), "start": stat[19],
            "argv": (folder / "cmdline").read_bytes().decode().strip("\0").split("\0")}


def children(pid):
    found = set()
    for task in Path(f"/proc/{pid}/task").glob("*/children"):
        try:
            found.update(map(int, task.read_text().split()))
        except FileNotFoundError:
            pass
    return found


def hold(pid, parent=None):
    try:
        fd = os.pidfd_open(pid)
        try:
            record = process(pid)
            if parent is not None and record["parent"] != parent:
                os.close(fd)
                return None
            return fd, record
        except BaseException:
            os.close(fd)
            raise
    except OSError as error:
        if error.errno in (errno.ENOENT, errno.ESRCH):
            return None
        raise


def ended(fd):
    poll = select.poll()
    poll.register(fd, select.POLLIN)
    return bool(poll.poll(0))


def observe(root, prefix, gate, state):
    held, detached = [], []
    root_handle = hold(root)
    if root_handle is None:
        raise RuntimeError("shell=absent")

    def acquire(parent):
        for pid in sorted(children(parent)):
            item = hold(pid, parent)
            if item is None:
                continue
            held.append(item)
            acquire(pid)

    try:
        acquire(root)
        # holdUntil uses Quickshell.execDetached: its double-forked process
        # is no longer a shell descendant. Its unique gate is the row's.
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit() or int(entry.name) == os.getpid():
                continue
            try:
                argv = (entry / "cmdline").read_bytes().decode().strip("\0").split("\0")
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                continue
            if gate not in argv:
                continue
            item = hold(int(entry.name))
            if item is None:
                continue
            fd, record = item
            if gate in record["argv"]:
                detached.append(item)
            else:
                os.close(fd)
        roles = set()
        for _, record in held:
            argv = record["argv"]
            if argv[-2:] == ["--format=json", "subscribe"]:
                roles.add("pactl")
            for name in ("systemd-inhibit", "sleep-watch", "dbus-monitor"):
                if any(Path(word).name == name for word in argv[:3]):
                    roles.add(name)
        stubborn = int((Path(state) / "child-lifetime.stubborn").read_text())
        if stubborn in {record["pid"] for _, record in held}:
            roles.add("grandchild")
        responsive = int((Path(state) / "child-lifetime.responsive").read_text())
        if responsive in {record["pid"] for _, record in held}:
            roles.add("responsive")
        required = {"pactl", "systemd-inhibit", "sleep-watch", "dbus-monitor", "grandchild", "responsive"}
        if not required <= roles or not detached:
            raise RuntimeError(f"coverage=missing roles={sorted(required - roles)} detached={len(detached)}")
        detached_pids = {record["pid"] for _, record in detached}
        if detached_pids & {record["pid"] for _, record in held}:
            raise RuntimeError("detached=managed-descendant")
        publish(prefix + ".ready", {"roles": sorted(roles), "managed": [r for _, r in held],
                                    "detached": [r for _, r in detached]})
        deadline = time.monotonic() + 120
        while not Path(prefix + ".check").exists():
            if time.monotonic() >= deadline:
                raise RuntimeError("request=timeout")
            time.sleep(0.02)
        deadline = time.monotonic() + 10
        while any(not ended(fd) for fd, _ in held) and time.monotonic() < deadline:
            time.sleep(0.02)
        survivors = [r for fd, r in held if not ended(fd)]
        detached_alive = all(not ended(fd) for fd, _ in detached)
        acknowledged = (Path(state) / f"child-lifetime.term-ack.{responsive}").exists()
        publish(prefix + ".result", {"survivors": survivors, "detachedAlive": detached_alive,
                                     "cleanupAcknowledged": acknowledged})
        # Readings precede cleanup. A pre-fix control must leave no orphan
        # in the shared sandbox; held pidfds cannot signal a reused PID.
        for fd, _ in held:
            if not ended(fd):
                signal.pidfd_send_signal(fd, signal.SIGKILL)
        return 0 if not survivors and detached_alive and acknowledged else 1
    finally:
        os.close(root_handle[0])
        for fd, _ in held + detached:
            os.close(fd)


def tool(name, state, argv):
    if name == "busctl":
        print("b false" if argv[-1] == "PreparingForSleep" else "t 5000000")
    elif name == "systemd-inhibit":
        while argv and argv[0].startswith("--"):
            argv.pop(0)
        child = os.fork()
        if child == 0:
            os.execvpe(argv[0], argv, os.environ)
        _, status = os.waitpid(child, 0)
        return os.waitstatus_to_exitcode(status)
    elif name == "dbus-monitor":
        Path(state, "child-lifetime.stubborn").unlink(missing_ok=True)
        Path(state, "child-lifetime.responsive").unlink(missing_ok=True)
        child = os.fork()
        if child == 0:
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            Path(state, "child-lifetime.stubborn").write_text(str(os.getpid()))
            while True:
                signal.pause()
        responsive = os.fork()
        if responsive == 0:
            def acknowledge(signum, frame):
                Path(state, f"child-lifetime.term-ack.{os.getpid()}").write_text(str(time.monotonic_ns()))
                sys.exit(0)
            signal.signal(signal.SIGTERM, acknowledge)
            Path(state, "child-lifetime.responsive").write_text(str(os.getpid()))
            while True:
                signal.pause()
        while not all(Path(state, "child-lifetime." + name).exists() for name in ("stubborn", "responsive")):
            time.sleep(0.01)
        print("signal member=NameAcquired", flush=True)
        while True:
            signal.pause()
    else:
        raise ValueError(f"tool={name}")
    return 0


if __name__ == "__main__":
    if sys.argv[1] == "observe":
        try:
            sys.exit(observe(int(sys.argv[2]), *sys.argv[3:]))
        except Exception as error:
            publish(sys.argv[3] + ".error", {"error": str(error)})
            raise
    sys.exit(tool(sys.argv[1], sys.argv[2], sys.argv[3:]))
