#!/usr/bin/env python3
"""This user's gliff-server processes, read from /proc, and the end of one.

list       one JSON line {"pid", "start", "peer"} per gliff-server whose
           real uid is the caller's: `start` is field 22 of
           /proc/<pid>/stat, `peer` the client address of SSH_CONNECTION
           in its environment, "" without one. Exit 0. A /proc read that
           fails for any cause but the process ending prints
           `sessions: unreadable=<path> errno=<n>` and exits 2.
end PID START [PID START...]
           SIGTERM through a pidfd to each gliff-server that /proc still
           shows with that start time, name and uid. One line each:
           `<pid> ended`, `<pid> gone` when it left first, or `<pid>
           refused` when the pid names another process now. Exit 0, or 2
           as list does.

Omarchy's remote-session probe.sh lists the same processes with pgrep and
reads the same variable. A process of the same user can take the name, so
the match is a disclosure aid, not a security boundary. gliff spawns the
server through `ssh -- <host> gliff-server`, so it inherits the session
environment sshd sets.
"""
import json
import os
import signal
import sys

NAME = b"gliff-server"
# A process that ends during the scan: its /proc files read as missing or
# as ESRCH.
GONE = (FileNotFoundError, ProcessLookupError)


class Unreadable(Exception):
    pass


def read(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except GONE:
        raise
    except OSError as e:
        raise Unreadable("%s errno=%d" % (path, e.errno))


def identity(pid):
    """(start, peer) of PID while it is this user's gliff-server, else None.
    Raises a GONE error when it ended and Unreadable for another failure.
    comm is bytes: the kernel cuts it at 15 bytes, mid-character too."""
    base = "/proc/%d/" % pid
    if read(base + "comm").rstrip(b"\n") != NAME:
        return None
    uid = [line.split()[1] for line in read(base + "status").splitlines() if line.startswith(b"Uid:")]
    if uid != [str(os.getuid()).encode()]:
        return None
    # The fields after the name's last ")" start at field 3, so the start
    # time, field 22, is index 19.
    start = read(base + "stat").rsplit(b")", 1)[1].split()[19].decode()
    peer = ""
    for entry in read(base + "environ").split(b"\0"):
        if entry.startswith(b"SSH_CONNECTION="):
            peer = entry[len(b"SSH_CONNECTION="):].decode("utf-8", "replace").split(" ")[0]
    return start, peer


def listing():
    for pid in sorted(int(name) for name in os.listdir("/proc") if name.isdigit()):
        try:
            found = identity(pid)
        except GONE:
            continue
        if found is not None:
            print(json.dumps({"pid": pid, "start": found[0], "peer": found[1]}))


def end(pid, start):
    try:
        fd = os.pidfd_open(pid)
    except ProcessLookupError:
        return "gone"
    try:
        found = identity(pid)
        if found is None or found[0] != start:
            return "refused"
        signal.pidfd_send_signal(fd, signal.SIGTERM)
        return "ended"
    except GONE:
        return "gone"
    finally:
        os.close(fd)


def main(argv):
    pairs = argv[1:]
    try:
        if argv == ["list"]:
            listing()
            return 0
        if argv[:1] == ["end"] and pairs and len(pairs) % 2 == 0 and all(word.isdigit() for word in pairs):
            for i in range(0, len(pairs), 2):
                print("%s %s" % (pairs[i], end(int(pairs[i]), pairs[i + 1])))
            return 0
    except Unreadable as e:
        print("sessions: unreadable=%s" % e, file=sys.stderr)
        return 2
    except OSError as e:
        print("sessions: unreadable=/proc errno=%d" % e.errno, file=sys.stderr)
        return 2
    print("sessions: refused: argv=" + json.dumps(argv), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
