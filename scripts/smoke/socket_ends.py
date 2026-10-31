"""The client ends of the connections the sandbox's servers accepted.

One reader of `ss -xpnH` decides which unix-socket end is a connection to
which server, for the recorder's shell stop (scripts/smoke/display-record.sh,
which inlines this file into its program) and for the row boundary's
socket-holder evidence (leak_socket_holders in scripts/smoke/leaks.sh, which
imports it), so the two never disagree on whose end an inode is.

ss prints one line per socket: netid, state, queues, the local address and
inode, the peer address and inode, and `users:((comm,pid=P,fd=F),...)`, the
processes holding that socket. An end a server accepted has the server's
listening path as its local address and the client end's inode as its peer,
so the client end is found by the server's path, never by its holders.
https://man7.org/linux/man-pages/man8/ss.8.html
"""
import re
import subprocess

SOCKET_ENDS_HOLDER = re.compile(r",pid=(\d+),fd=\d+\)")


class SocketEndsUnreadable(Exception):
    """ss could not be run or answered with a failure; the reason is the message."""


def socket_ends_parse(text, servers):
    """{client inode: (server name, holders)} for every connection a
    listening socket at one of SERVERS' paths (name -> path) accepted.
    Holders is the sorted holder pids of a client end ss lists; None for one
    ss lists with no users column, open but in no descriptor table ss can
    read, as a descriptor in flight in a unix message is; [] for one ss
    lists no socket for, closed after ss read the server's side. Once a
    client end has closed, the server's side reads peer 0 and is no
    connection here (ss 7.3.0 on Linux 7.3.1, 2026-10-31)."""
    sockets = {}
    for line in text.splitlines():
        words = line.split()
        if len(words) < 8 or not words[0].startswith("u_"):
            continue
        holders = sorted({int(m.group(1)) for m in SOCKET_ENDS_HOLDER.finditer(line)})
        sockets[words[5]] = (words[4], words[7], holders or None)
    names = {path: name for name, path in servers.items()}
    ends = {}
    for local, peer, _ in sockets.values():
        if local in names and peer not in ("0", "*"):
            ends[int(peer)] = (names[local], sockets.get(peer, (None, None, []))[2])
    return ends


def socket_ends_read(servers, timeout):
    """socket_ends_parse over a live `ss -xpnH`, within TIMEOUT seconds."""
    try:
        out = subprocess.run(["ss", "-xpnH"], capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SocketEndsUnreadable(str(error)) from error
    if out.returncode:
        raise SocketEndsUnreadable(f"ss-exit-{out.returncode}")
    return socket_ends_parse(out.stdout, servers)
