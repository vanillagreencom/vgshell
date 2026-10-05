#!/usr/bin/env python3
# Adapted from Omarchy's test/shell.d/fixtures/tray-menu-activation/mock-sni.py
# (https://github.com/basecamp/omarchy, main 821ae589):
#
# Copyright (c) David Heinemeier Hansson
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# mock-sni.py RECORD: two stand-in tray apps on the session bus that
# DBUS_SESSION_BUS_ADDRESS names, which scripts/smoke/rows/tray.sh sets to
# the nested sandbox's private bus and nothing else. Each is a
# StatusNotifierItem, Id vgs-smoke-tray-a and vgs-smoke-tray-b, titled
# Smoke Tray A and Smoke Tray B, with a drawn icon and a dbusmenu tree:
# Open, a separator, Accounts with one entry Sign in, and Quit, ids 1 to 5,
# Sign in 4. GetLayout answers the subtree under its parent id down to its
# recursion depth, -1 for all of it. Each call a row reads appends one line
# to RECORD: `Activate <Id>`, `SecondaryActivate <Id>`, `Scroll <Id> <delta>
# <orientation>` and `Event <menu id> clicked`. Both items register with
# org.kde.StatusNotifierWatcher at start, when it has an owner, and again
# each time that name gets a new owner, as when the shell restarts. Each
# item holds a bus connection of its own.
import os
import sys

import dbus
import dbus.bus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

WATCHER = "org.kde.StatusNotifierWatcher"
ITEMS = (("a", "vgs-smoke-tray-a", "Smoke Tray A", (0xff, 0x4c, 0x9a, 0xe0)), ("b", "vgs-smoke-tray-b", "Smoke Tray B", (0xff, 0xe0, 0x8a, 0x3c)))
# The menu: id -> (properties, child ids).
MENU = {
    0: ({"children-display": "submenu"}, [1, 2, 3, 5]),
    1: ({"label": "Open"}, []),
    2: ({"type": "separator"}, []),
    3: ({"label": "Accounts", "children-display": "submenu"}, [4]),
    4: ({"label": "Sign in"}, []),
    5: ({"label": "Quit"}, []),
}
ICON_SIZE = 22


def record(path, line):
    with open(path, "a", encoding="utf-8") as out:
        out.write(line + "\n")


def icon(argb):
    # One ICON_SIZE square in the item's colour, ARGB32 in network order.
    return dbus.Array([dbus.Struct((dbus.Int32(ICON_SIZE), dbus.Int32(ICON_SIZE), dbus.ByteArray(bytes(argb) * ICON_SIZE * ICON_SIZE)), signature="iiay")], signature="(iiay)")


class Item(dbus.service.Object):
    def __init__(self, bus, path, item_id, title, argb, record_path):
        super().__init__(bus, path)
        self.item_id, self.title, self.argb, self.record_path = item_id, title, argb, record_path
        self.menu_path = path + "/Menu"

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
    def Get(self, interface, prop):
        return self.GetAll(interface)[prop]

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface != "org.kde.StatusNotifierItem":
            return dbus.Dictionary({}, signature="sv")
        return dbus.Dictionary({
            "Category": "ApplicationStatus",
            "Id": self.item_id,
            "Title": self.title,
            "Status": "Active",
            "WindowId": dbus.Int32(0),
            "IconName": "",
            "IconPixmap": icon(self.argb),
            "IconThemePath": "",
            "Menu": dbus.ObjectPath(self.menu_path),
            "ItemIsMenu": dbus.Boolean(False),
            "ToolTip": dbus.Struct(("", dbus.Array([], signature="(iiay)"), self.title, ""), signature="sa(iiay)ss"),
        }, signature="sv")

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ssv")
    def Set(self, interface, prop, value):
        return

    @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii")
    def ContextMenu(self, x, y):
        return

    @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii")
    def Activate(self, x, y):
        record(self.record_path, "Activate " + self.item_id)

    @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii")
    def SecondaryActivate(self, x, y):
        record(self.record_path, "SecondaryActivate " + self.item_id)

    @dbus.service.method("org.kde.StatusNotifierItem", in_signature="is")
    def Scroll(self, delta, orientation):
        record(self.record_path, "Scroll %s %d %s" % (self.item_id, int(delta), orientation))


class Menu(dbus.service.Object):
    def __init__(self, bus, path, record_path):
        super().__init__(bus, path)
        self.record_path = record_path

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
    def Get(self, interface, prop):
        return self.GetAll(interface)[prop]

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface != "com.canonical.dbusmenu":
            return dbus.Dictionary({}, signature="sv")
        return dbus.Dictionary({"Version": dbus.UInt32(3), "TextDirection": "ltr", "Status": "normal", "IconThemePath": dbus.Array([], signature="s")}, signature="sv")

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ssv")
    def Set(self, interface, prop, value):
        return

    @dbus.service.method("com.canonical.dbusmenu", in_signature="i", out_signature="b")
    def AboutToShow(self, item_id):
        return False

    @dbus.service.method("com.canonical.dbusmenu", in_signature="ai", out_signature="aiai")
    def AboutToShowGroup(self, item_ids):
        return ([], [])

    def node(self, item_id, depth):
        props, children = MENU[item_id]
        below = [] if depth == 0 else [dbus.Struct(self.node(child, depth - 1), signature="ia{sv}av", variant_level=1) for child in children]
        return (dbus.Int32(item_id), dbus.Dictionary(props, signature="sv"), dbus.Array(below, signature="v"))

    @dbus.service.method("com.canonical.dbusmenu", in_signature="iias", out_signature="u(ia{sv}av)")
    def GetLayout(self, parent_id, recursion_depth, property_names):
        if int(parent_id) not in MENU:
            raise dbus.DBusException("no menu item %d" % int(parent_id), name="com.canonical.dbusmenu.Error")
        return (dbus.UInt32(1), dbus.Struct(self.node(int(parent_id), int(recursion_depth)), signature="ia{sv}av"))

    @dbus.service.method("com.canonical.dbusmenu", in_signature="aias", out_signature="a(ia{sv})")
    def GetGroupProperties(self, item_ids, property_names):
        return dbus.Array([dbus.Struct((dbus.Int32(i), dbus.Dictionary(MENU[int(i)][0], signature="sv"))) for i in item_ids if int(i) in MENU], signature="(ia{sv})")

    @dbus.service.method("com.canonical.dbusmenu", in_signature="is", out_signature="v")
    def GetProperty(self, item_id, name):
        return MENU.get(int(item_id), ({}, []))[0].get(str(name), "")

    @dbus.service.method("com.canonical.dbusmenu", in_signature="isvu")
    def Event(self, item_id, event_id, data, timestamp):
        if str(event_id) == "clicked":
            record(self.record_path, "Event %d clicked" % int(item_id))

    @dbus.service.method("com.canonical.dbusmenu", in_signature="a(isvu)", out_signature="ai")
    def EventGroup(self, events):
        for item_id, event_id, data, timestamp in events:
            self.Event(item_id, event_id, data, timestamp)
        return dbus.Array([], signature="i")


def main():
    record_path = sys.argv[1]
    DBusGMainLoop(set_as_default=True)
    # One connection per item: the watcher drops the items of a connection
    # that leaves the bus but tells its host of only one of them.
    items = []
    for suffix, item_id, title, argb in ITEMS:
        bus = dbus.bus.BusConnection(os.environ["DBUS_SESSION_BUS_ADDRESS"])
        path = "/StatusNotifierItem/" + suffix
        Item(bus, path, item_id, title, argb, record_path)
        Menu(bus, path + "/Menu", record_path)
        items.append((bus, path))

    def register(owner):
        if not owner:
            return
        for bus, path in items:
            watcher = dbus.Interface(bus.get_object(WATCHER, "/StatusNotifierWatcher"), WATCHER)
            watcher.RegisterStatusNotifierItem(path, reply_handler=lambda: None, error_handler=lambda error: print("register:", error, flush=True))
        print("registered with", owner, flush=True)

    items[0][0].watch_name_owner(WATCHER, register)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
