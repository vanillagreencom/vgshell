#!/usr/bin/env python3
"""A stand-in for another polkit agent, for scripts/smoke/rows/polkit.sh.

agent.py BUS_ADDRESS

Registers as the agent of one session with the authority on the bus at
BUS_ADDRESS, the sandbox's system bus, where authority.py answers, then
holds its connection until SIGTERM ends it, as a real agent holds the
session until it stops. The row runs it from a copy of the Python
interpreter named as an agent's program is, so the process and its program
file read as another agent's. It exports no agent object and shows no
prompt: the stand-in authority never begins an authentication.

Exit 1 with `agent=refused <error>` on stderr when the authority refuses.
"""

import signal
import sys

import dbus

PATH = "/org/vgshell/Smoke/OtherAgent"


def main():
    bus = dbus.bus.BusConnection(sys.argv[1])
    authority = dbus.Interface(bus.get_object("org.freedesktop.PolicyKit1", "/org/freedesktop/PolicyKit1/Authority"), "org.freedesktop.PolicyKit1.Authority")
    try:
        authority.RegisterAuthenticationAgent(("unix-session", {"session-id": dbus.String("smoke", variant_level=1)}), "C", PATH)
    except dbus.DBusException as error:
        print(f"agent=refused {error.get_dbus_name()}", file=sys.stderr)
        return 1
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    while True:
        signal.pause()


if __name__ == "__main__":
    sys.exit(main())
