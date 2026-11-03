#!/usr/bin/env python3
"""client.py LIB VERB [ARG]: a stand-in caller of org.freedesktop.ScreenSaver
on the session bus DBUS_SESSION_BUS_ADDRESS names, which
scripts/smoke/rows/idle-inhibit.sh sets to the nested sandbox's private
bus and nothing else. It speaks through LIB/dbus_wire.py, the wire module
bin/vgshell-idle-inhibit uses.

  hold       Inhibit("vgs-smoke", "idle-inhibit row"), print `cookie=<n>`,
             then wait: SIGUSR1 sends UnInhibit of that cookie on the same
             connection and prints `released`, SIGTERM exits 0.
  own        RequestName(org.freedesktop.ScreenSaver, ALLOW_REPLACEMENT |
             DO_NOT_QUEUE), print `owner=primary` or `owner=<reply code>`,
             then wait for SIGTERM. A helper that asks REPLACE_EXISTING
             displaces it; one that does not, leaves it.
  owner      print the pid of the name's owner, or `none`.
  uninhibit COOKIE
             UnInhibit(COOKIE) on a connection of its own, print `ok`.
  active     GetActive(), print `true` or `false`.

A failed call prints `error=<cause>` and exits 1.
"""
import signal
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import dbus_wire as wire  # noqa: E402

NAME = "org.freedesktop.ScreenSaver"
PATH = "/org/freedesktop/ScreenSaver"


def screensaver(sock, serial, member, signature="", values=()):
    return wire.call(sock, serial, member, time.monotonic() + 5, signature, wire.pack_body(signature, values), NAME, PATH, NAME)


def main(verb, arg):
    # Blocked before the first call, so a signal the row sends early waits.
    signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGUSR1, signal.SIGTERM})
    sock = wire.connect("session", time.monotonic() + 5)
    if verb == "hold":
        cookie = wire.parse_uint(screensaver(sock, 2, "Inhibit", "ss", ["vgs-smoke", "idle-inhibit row"]))
        print(f"cookie={cookie}", flush=True)
        serial = 2
        while signal.sigwait({signal.SIGUSR1, signal.SIGTERM}) == signal.SIGUSR1:
            serial += 1
            screensaver(sock, serial, "UnInhibit", "u", [cookie])
            print("released", flush=True)
    elif verb == "own":
        code = wire.parse_uint(wire.call(sock, 2, "RequestName", time.monotonic() + 5, "su", wire.pack_body("su", [NAME, 1 | 4])))
        print("owner=primary" if code == 1 else f"owner={code}", flush=True)
        signal.sigwait({signal.SIGTERM})
    elif verb == "owner":
        try:
            pid = wire.parse_uint(wire.call(sock, 2, "GetConnectionUnixProcessID", time.monotonic() + 5, "s", wire.pack_body("s", [NAME])))
        except OSError as exc:
            if "NameHasNoOwner" not in str(exc):
                raise
            print("none")
        else:
            print(pid)
    elif verb == "uninhibit":
        screensaver(sock, 2, "UnInhibit", "u", [int(arg)])
        print("ok")
    elif verb == "active":
        print("true" if wire.parse_uint(screensaver(sock, 2, "GetActive")) else "false")
    else:
        raise ValueError("verb=" + verb)


if __name__ == "__main__":
    try:
        main(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
    except (OSError, ValueError) as exc:
        print(f"error={exc}", flush=True)
        sys.exit(1)
