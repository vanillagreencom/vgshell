#!/usr/bin/env python3
"""A stand-in polkitd for scripts/smoke/rows/polkit.sh.

authority.py BUS_ADDRESS LOG

Owns org.freedesktop.PolicyKit1 on the bus at BUS_ADDRESS, the sandbox's
system bus, and answers the calls an agent makes to register, as
polkit's org.freedesktop.PolicyKit1.Authority does: it takes one agent,
refuses a second with org.freedesktop.PolicyKit1.Error.Failed while the
first holds, and lets go when the holder unregisters or leaves the bus.
It never calls an agent's BeginAuthentication, so no request goes live,
and it checks no authorization and runs no PAM.

It appends one line per change to LOG, which the row reads:
`ready`, `registered <path>`, `refused <path>` and `released <path>`,
<path> the object path the agent registered.
"""

import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

NAME = "org.freedesktop.PolicyKit1"
PATH = "/org/freedesktop/PolicyKit1/Authority"
IFACE = "org.freedesktop.PolicyKit1.Authority"


class Failed(dbus.DBusException):
    _dbus_error_name = "org.freedesktop.PolicyKit1.Error.Failed"


class Authority(dbus.service.Object):
    def __init__(self, bus, log):
        super().__init__(bus, PATH)
        self.log = log
        # The one agent: (its bus name, its object path), or None.
        self.holder = None
        bus.add_signal_receiver(self.owner_changed, "NameOwnerChanged", "org.freedesktop.DBus", "org.freedesktop.DBus")

    def note(self, line):
        with open(self.log, "a", encoding="utf-8") as out:
            out.write(line + "\n")

    def owner_changed(self, name, old, new):
        if self.holder is not None and name == self.holder[0] and new == "":
            self.release()

    def release(self):
        self.note(f"released {self.holder[1]}")
        self.holder = None

    def register(self, sender, path):
        if self.holder is not None:
            self.note(f"refused {path}")
            raise Failed("An authentication agent already exists for the given subject")
        self.holder = (sender, str(path))
        self.note(f"registered {path}")

    @dbus.service.method(IFACE, in_signature="(sa{sv})ss", sender_keyword="sender")
    def RegisterAuthenticationAgent(self, subject, locale, path, sender=None):
        self.register(sender, path)

    @dbus.service.method(IFACE, in_signature="(sa{sv})ssa{sv}", sender_keyword="sender")
    def RegisterAuthenticationAgentWithOptions(self, subject, locale, path, options, sender=None):
        self.register(sender, path)

    @dbus.service.method(IFACE, in_signature="(sa{sv})s", sender_keyword="sender")
    def UnregisterAuthenticationAgent(self, subject, path, sender=None):
        if self.holder != (sender, str(path)):
            raise Failed("No such agent registered")
        self.release()

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return {"BackendName": "smoke", "BackendVersion": "0", "BackendFeatures": dbus.UInt32(0)}

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return self.GetAll(interface)[name]


def main():
    if len(sys.argv) != 3:
        print("authority=failed reason=usage", file=sys.stderr)
        return 2
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.bus.BusConnection(sys.argv[1])
    held = dbus.service.BusName(NAME, bus, do_not_queue=True)
    authority = Authority(bus, sys.argv[2])
    authority.note("ready")
    GLib.MainLoop().run()
    del held
    return 0


if __name__ == "__main__":
    sys.exit(main())
