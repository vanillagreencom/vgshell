#!/usr/bin/env python3
"""Network row operations on S08's existing NetworkManager mock.

Usage: network.py SANDBOX_BUS prepare|fail|drop-active|replace|restore|calls

prepare makes the existing Wi-Fi saved and makes saved-profile activation
stay Connecting until fail emits NetworkManager's NoSecrets failure. An
updated PSK activates normally. No secret is printed or supplied in argv.
The mock's own D-Bus argument log is disabled before it receives a PSK;
method counts remain available through GetMethodCalls. replace adds wlan1
and removes wlan0 from the manager's list while keeping the old fake object
alive so the row can read that its scanner was released. restore returns
wlan0 and removes wlan1. No operation contacts the host's bus or devices.
"""
import json
import pathlib
import sys

import dbus

NM = "org.freedesktop.NetworkManager"
MOCK = "org.freedesktop.DBus.Mock"
DEV = NM + ".Device"
WIFI = DEV + ".Wireless"
ACTIVE = NM + ".Connection.Active"
ROOT = "/org/freedesktop"
MANAGER = ROOT + "/NetworkManager"
DEVICE = MANAGER + "/Devices/wlan0"
PROFILE = MANAGER + "/Settings/network_saved"
AP = MANAGER + "/AccessPoint/ap0"


def configure(root, manager, device, bus, mode):
    profile = dbus.Interface(bus.get_object(NM, PROFILE), MOCK)
    manager.AddMethod(NM, "ActivateConnection", "ooo", "o", f'''
root = objects["{ROOT}"]
connection = objects[args[0]]
updated = __import__("hashlib").sha256(str(connection.settings.get("802-11-wireless-security", {{}}).get("psk", "")).encode()).hexdigest() == "d568e2f90f1f59614030a38f74cc51eb287c5b471a5f36bbfcc3614d72607bba"
ret = dbus.ObjectPath(root.AddActiveConnection([args[1]], args[0], "{AP}", "network_active", 2 if updated else 1))
objects[ret].log = lambda msg: None
''')
    refused = 'raise dbus.exceptions.DBusException("fixture refused", name="org.freedesktop.NetworkManager.PermissionDenied")'
    if mode == "refuse-connect": manager.AddMethod(NM, "ActivateConnection", "ooo", "o", refused)
    device.AddMethod(DEV, "Disconnect", "", "", refused if mode == "refuse-disconnect" else f'objects["{ROOT}"].RemoveActiveConnection("{DEVICE}", "{MANAGER}/ActiveConnection/network_active")')
    profile.AddMethod(NM + ".Settings.Connection", "Update", "a{sa{sv}}", "", refused if mode == "refuse-psk" else "self.ConnectionUpdate(self, args[0])")
    profile.AddMethod(NM + ".Settings.Connection", "Delete", "", "", refused if mode == "refuse-forget" else "self.ConnectionDelete(self)")


def main():
    address, action = sys.argv[1:]
    if not address.startswith("unix:path=") or pathlib.Path(address[len("unix:path="):]).name != "system-bus" or not pathlib.Path(address[len("unix:path="):]).parent.name.startswith("vs."):
        raise ValueError("network fixture requires the sandbox bus")
    bus = dbus.bus.BusConnection(address)
    root = dbus.Interface(bus.get_object(NM, ROOT), MOCK)
    manager = dbus.Interface(bus.get_object(NM, MANAGER), MOCK)
    device = dbus.Interface(bus.get_object(NM, DEVICE), MOCK)
    if action == "prepare":
        # dbusmock logs method arguments by default. NetworkManager owns
        # PSKs, so the fake must also keep those arguments off disk.
        root.AddMethod(MOCK, "NetworkQuiet", "", "", "\nfor obj in objects.values():\n    obj.log = lambda msg: None")
        root.NetworkQuiet()
        root.AddMethod(MOCK, "NetworkSaved", "", "", f'''
self.AddWiFiConnection("{DEVICE}", "network_saved", "VGS Smoke Wi-Fi", "wpa-psk")
profile = objects["{PROFILE}"]
profile.settings["802-11-wireless-security"] = dict(profile.settings["802-11-wireless-security"])
profile.settings["802-11-wireless-security"].pop("psk", None)
profile.log = lambda msg: None
''')
        root.NetworkSaved()
        configure(root, manager, device, bus, "normal")
        # The template's Delete drops the connection object and device list.
        # Its log would contain the PSK after Update, so quiet this new object.
        root.NetworkQuiet()
    elif action in ("normal", "refuse-connect", "refuse-psk", "refuse-disconnect", "refuse-forget"):
        configure(root, manager, device, bus, action)
    elif action == "fail":
        device.UpdateProperties(DEV, dbus.Dictionary({"StateReason": dbus.Struct((dbus.UInt32(120), dbus.UInt32(7)), signature="uu")}, signature="sv"))
        device.EmitSignal(DEV, "StateChanged", "uuu", [dbus.UInt32(120), dbus.UInt32(100), dbus.UInt32(7)])
        active = dbus.Interface(bus.get_object(NM, MANAGER + "/ActiveConnection/network_active"), MOCK)
        active.UpdateProperties(ACTIVE, dbus.Dictionary({"State": dbus.UInt32(4)}, signature="sv"))
        active.EmitSignal(ACTIVE, "StateChanged", "uu", [dbus.UInt32(4), dbus.UInt32(3)])
    elif action == "drop-active":
        root.RemoveActiveConnection(DEVICE, MANAGER + "/ActiveConnection/network_active")
    elif action == "replace":
        root.AddMethod(MOCK, "NetworkReplace", "", "s", f'''
ret = self.AddWiFiDevice("wlan1", "wlan1", 30)
next_device = objects[ret]
next_device.log = lambda msg: None
next_device.AddProperty("{DEV}", "HwAddress", dbus.String("11:22:33:44:55:77"))
next_device.AddProperty("{DEV}", "Autoconnect", dbus.Boolean(True))
next_device.AddProperty("{DEV}", "InterfaceFlags", dbus.UInt32(0))
next_device.AddProperty("{WIFI}", "LastScan", dbus.Int64(-1))
next_device.AddProperty("{WIFI}", "ActiveAccessPoint", dbus.ObjectPath("/"))
''')
        replacement = root.NetworkReplace()
        manager.UpdateProperties(NM, dbus.Dictionary({"Devices": dbus.Array([dbus.ObjectPath(replacement)], signature="o")}, signature="sv"))
        manager.EmitSignal(NM, "DeviceRemoved", "o", [dbus.ObjectPath(DEVICE)])
    elif action == "restore":
        manager.UpdateProperties(NM, dbus.Dictionary({"Devices": dbus.Array([dbus.ObjectPath(DEVICE)], signature="o")}, signature="sv"))
        manager.EmitSignal(NM, "DeviceRemoved", "o", [dbus.ObjectPath(MANAGER + "/Devices/wlan1")])
        manager.EmitSignal(NM, "DeviceAdded", "o", [dbus.ObjectPath(DEVICE)])
        root.RemoveObject(MANAGER + "/Devices/wlan1")
    elif action == "calls":
        print(json.dumps({"connect": len(manager.GetMethodCalls("ActivateConnection")), "new": len(manager.GetMethodCalls("AddAndActivateConnection"))}))
        return
    else:
        raise ValueError("unknown network fixture action")
    print("ok")


if __name__ == "__main__":
    main()
