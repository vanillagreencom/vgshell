#!/usr/bin/env python3
"""The sandbox's radios on its private system bus.

Usage: world.py ADDRESS
       world.py ADDRESS VERB ARG...

ADDRESS is the sandbox system bus, where scripts/smoke/devices.sh has
started python-dbusmock's bluez5 and networkmanager templates. With no
verb this waits up to 10 s for both names, then plants one Bluetooth
adapter with one paired, connected device, and one Wi-Fi device that sees
one access point. It prints `world=planted`, or `world=failed
reason=<key>` with status 1.

The verbs a Bluetooth row drives the planted adapter with, each printing
one line and exiting 1 with `world=failed reason=<key>` on a D-Bus error:
  add-device MAC NAME [held]  a nearby, unpaired device; with `held` its
                              Pair answers at once and pairs nothing, so the
                              bluetoothctl stand-in's transcript pairs it
                              once the agent's prompt is answered
                              (stand-in.py). Prints its path.
  discovery confirm|hold      StartDiscovery confirms Discovering at once,
                              or records the call and confirms nothing
                              until a row sets it. Prints the mode.
  update PATH IFACE JSON      set the properties of JSON, an object of
                              booleans and strings, on PATH and emit their
                              change, as BlueZ does. Prints `updated`.
  props PATH IFACE            the properties as one JSON object.
  calls PATH METHOD           how many times METHOD was called on PATH.

The templates lack members Quickshell 0.3.1 reads, which the line
QS_DBUS_PROPERTY_BINDING names in src/bluetooth/adapter.hpp,
src/bluetooth/device.hpp and src/network/nm/*.hpp. A required property
missing from a GetAll answer logs `missing from property set` and leaves
the value unset, and NetworkManager's GetAllDevices is the call that
lists devices. Each gap is filled through dbusmock's own
org.freedesktop.DBus.Mock interface, AddProperty and AddMethod, so no
second fake owns any object.

The template's own Adapter1.StartDiscovery and StopDiscovery read a
DiscoveryFilter property no adapter has until SetDiscoveryFilter, and
fail; its Device1.Connect and Disconnect read a Python flag that its own
ConnectDevice never sets, so the planted device could not disconnect.
Each is replaced the same way, reading and writing the D-Bus properties.
"""

import json

import sys
import time

import dbus

BLUEZ = "org.bluez"
NM = "org.freedesktop.NetworkManager"
MOCK = "org.freedesktop.DBus.Mock"
ADAPTER = "org.bluez.Adapter1"
DEVICE = "org.bluez.Device1"
SMOKE = "org.vgs.Smoke"
NM_DEVICE = "org.freedesktop.NetworkManager.Device"
NM_WIRELESS = "org.freedesktop.NetworkManager.Device.Wireless"
NM_ACCESS_POINT = "org.freedesktop.NetworkManager.AccessPoint"
NM_DISCONNECTED = 30
NM_INFRA = 2
AP_SEC_KEY_MGMT_PSK = 0x100
# A WPA2-Personal access point's RSN flags, as NetworkManager's
# NM80211ApSecurityFlags spell them: PSK key management with a CCMP
# cipher. Quickshell reads a network's security from its access point
# before its saved profile, and a key management with no cipher it
# supports reads as Unknown security.
AP_SEC_WPA2_PSK = 0x8 | 0x80 | AP_SEC_KEY_MGMT_PSK

# What the row reads back: scripts/smoke/rows/device-fakes.sh.
ADAPTER_ID = "hci0"
ADAPTER_NAME = "VGS Smoke"
DEVICE_ADDRESS = "00:1B:66:AA:BB:01"
DEVICE_NAME = "Smoke Headphones"
WIFI_INTERFACE = "wlan0"
WIFI_SSID = "VGS Smoke Wi-Fi"


def refuse(reason):
    print(f"world=failed reason={reason}")
    sys.exit(1)


def wait_for(bus, names):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if all(bus.name_has_owner(name) for name in names):
            return
        time.sleep(0.05)
    refuse("names-absent names=" + ",".join(n for n in names if not bus.name_has_owner(n)))


# The methods the template gets wrong, as dbusmock code strings run with
# `self` the object (mockobject.DBusMockObject.mock_method).
START_DISCOVERY = (
    'if not getattr(self, "vgs_hold", False):\n'
    '    self.UpdateProperties("org.bluez.Adapter1", {"Discovering": dbus.Boolean(True)})'
)
STOP_DISCOVERY = 'self.UpdateProperties("org.bluez.Adapter1", {"Discovering": dbus.Boolean(False)})'
CONNECT = (
    'if self.props["org.bluez.Device1"]["Connected"]:\n'
    '    raise dbus.exceptions.DBusException("Already Connected", name="org.bluez.Error.AlreadyConnected")\n'
    'self.UpdateProperties("org.bluez.Device1", {"Connected": dbus.Boolean(True)})'
)
DISCONNECT = (
    'if not self.props["org.bluez.Device1"]["Connected"]:\n'
    '    raise dbus.exceptions.DBusException("Not Connected", name="org.bluez.Error.NotConnected")\n'
    'self.UpdateProperties("org.bluez.Device1", {"Connected": dbus.Boolean(False)})'
)
HELD_PAIR = (
    'if self.props["org.bluez.Device1"]["Paired"]:\n'
    '    raise dbus.exceptions.DBusException("Device already paired", name="org.bluez.Error.AlreadyExists")'
)


def fill_device(bus, path, held):
    device = dbus.Interface(bus.get_object(BLUEZ, path), MOCK)
    device.AddMethod(DEVICE, "Connect", "", "", CONNECT)
    device.AddMethod(DEVICE, "Disconnect", "", "", DISCONNECT)
    if held:
        device.AddMethod(DEVICE, "Pair", "", "", HELD_PAIR)
    return device


def plant_bluez(bus):
    root = dbus.Interface(bus.get_object(BLUEZ, "/"), "org.bluez.Mock")
    adapter_path = root.AddAdapter(ADAPTER_ID, ADAPTER_NAME)
    adapter = dbus.Interface(bus.get_object(BLUEZ, adapter_path), MOCK)
    adapter.AddProperty(ADAPTER, "PowerState", dbus.String("on"))
    adapter.AddMethod(ADAPTER, "StartDiscovery", "", "", START_DISCOVERY)
    adapter.AddMethod(ADAPTER, "StopDiscovery", "", "", STOP_DISCOVERY)
    adapter.AddMethod(SMOKE, "HoldDiscovery", "b", "", "self.vgs_hold = bool(args[0])")
    device_path = root.AddDevice(ADAPTER_ID, DEVICE_ADDRESS, DEVICE_NAME)
    root.PairDevice(ADAPTER_ID, DEVICE_ADDRESS)
    root.ConnectDevice(ADAPTER_ID, DEVICE_ADDRESS)
    device = fill_device(bus, device_path, False)
    device.AddProperty(DEVICE, "Bonded", dbus.Boolean(True))
    device.UpdateProperties(DEVICE, {"Icon": dbus.String("audio-headphones")})


def plant_network(bus):
    root = dbus.Interface(bus.get_object(NM, "/org/freedesktop"), MOCK)
    manager = dbus.Interface(bus.get_object(NM, "/org/freedesktop/NetworkManager"), MOCK)
    manager.AddMethod(NM, "GetAllDevices", "", "ao", 'ret = [k for k in objects.keys() if "/Devices/" in k]')
    manager.AddProperty(NM, "ConnectivityCheckAvailable", dbus.Boolean(False))
    manager.AddProperty(NM, "ConnectivityCheckEnabled", dbus.Boolean(False))
    device_path = root.AddWiFiDevice(WIFI_INTERFACE, WIFI_INTERFACE, dbus.Int32(NM_DISCONNECTED))
    device = dbus.Interface(bus.get_object(NM, device_path), MOCK)
    device.AddProperty(NM_DEVICE, "HwAddress", dbus.String("11:22:33:44:55:66"))
    device.AddProperty(NM_DEVICE, "Autoconnect", dbus.Boolean(True))
    device.AddProperty(NM_DEVICE, "InterfaceFlags", dbus.UInt32(0))
    device.AddProperty(NM_WIRELESS, "LastScan", dbus.Int64(-1))
    device.AddProperty(NM_WIRELESS, "ActiveAccessPoint", dbus.ObjectPath("/"))
    # dbusmock writes one value to WpaFlags and RsnFlags, and its saved
    # connection template reads WpaFlags as the bare PSK key management.
    ap_path = root.AddAccessPoint(device_path, "ap0", WIFI_SSID, "00:11:22:33:44:01", dbus.UInt32(NM_INFRA),
                                  dbus.UInt32(2437), dbus.UInt32(54000), dbus.Byte(82), dbus.UInt32(AP_SEC_KEY_MGMT_PSK))
    ap = dbus.Interface(bus.get_object(NM, ap_path), MOCK)
    ap.UpdateProperties(NM_ACCESS_POINT, {"RsnFlags": dbus.UInt32(AP_SEC_WPA2_PSK)})


def wire(value):
    if isinstance(value, bool):
        return dbus.Boolean(value)
    if isinstance(value, str):
        return dbus.String(value)
    refuse("update-value type=" + type(value).__name__)


def drive(bus, verb, args):
    adapter_path = "/org/bluez/" + ADAPTER_ID
    if verb == "add-device" and len(args) in (2, 3) and args[2:] in ([], ["held"]):
        root = dbus.Interface(bus.get_object(BLUEZ, "/"), "org.bluez.Mock")
        path = root.AddDevice(ADAPTER_ID, args[0], args[1])
        fill_device(bus, path, args[2:] == ["held"])
        return str(path)
    if verb == "discovery" and args in (["confirm"], ["hold"]):
        held = args[0] == "hold"
        dbus.Interface(bus.get_object(BLUEZ, adapter_path), SMOKE).HoldDiscovery(dbus.Boolean(held))
        return args[0]
    if verb == "update" and len(args) == 3:
        values = json.loads(args[2])
        dbus.Interface(bus.get_object(BLUEZ, args[0]), MOCK).UpdateProperties(args[1], {k: wire(v) for k, v in values.items()})
        return "updated"
    if verb == "props" and len(args) == 2:
        props = dbus.Interface(bus.get_object(BLUEZ, args[0]), dbus.PROPERTIES_IFACE).GetAll(args[1])
        return json.dumps({str(k): (bool(v) if isinstance(v, dbus.Boolean) else str(v) if isinstance(v, (dbus.String, dbus.ObjectPath)) else None)
                           for k, v in props.items() if isinstance(v, (dbus.Boolean, dbus.String, dbus.ObjectPath))}, sort_keys=True)
    if verb == "calls" and len(args) == 2:
        return str(len(dbus.Interface(bus.get_object(BLUEZ, args[0]), MOCK).GetMethodCalls(args[1])))
    refuse("usage verb=" + verb)


def main():
    if len(sys.argv) < 2:
        refuse("usage")
    try:
        bus = dbus.bus.BusConnection(sys.argv[1])
    except dbus.DBusException as error:
        refuse(f"bus-unreachable error={error.get_dbus_name()}")
    if len(sys.argv) > 2:
        try:
            print(drive(bus, sys.argv[2], sys.argv[3:]))
        except dbus.DBusException as error:
            refuse(f"mock-call error={error.get_dbus_name()} message={error.get_dbus_message()!r}")
        return
    wait_for(bus, (BLUEZ, NM))
    try:
        plant_bluez(bus)
        plant_network(bus)
    except dbus.DBusException as error:
        refuse(f"mock-call error={error.get_dbus_name()} message={error.get_dbus_message()!r}")
    print("world=planted")


if __name__ == "__main__":
    main()
