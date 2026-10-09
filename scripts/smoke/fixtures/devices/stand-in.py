#!/usr/bin/env python3
"""A device command's stand-in in the smoke sandbox's shim directory.

Usage: stand-in.py NAME STATE ARG...

scripts/smoke/devices.sh writes $shim/NAME as a two-line script that
runs this with NAME, its state directory STATE and the caller's argv.
No stand-in runs the host's command: each records its argv and answers
from files a row plants under STATE.

- Every call appends its argv as one JSON list line to
  STATE/calls/NAME.calls. A bluetoothctl transcript also appends each
  stdin line it reads, as {"stdin": LINE}, and {"eof": true} when its
  stdin ends past the last step.
- rfkill keeps STATE/rfkill.json, {"devices": [{"id", "type", "device",
  "soft", "hard"}]} with "blocked" or "unblocked", as its only state: it
  lists it as util-linux's rfkill does and block, unblock and toggle
  change the soft state of the devices that one or more IDs, TYPEs,
  aliases or `all` select. A hard block is never changed, as on real
  hardware; a row moves it with set_hard. While STATE/bluez-follow.json
  holds {"adapter": PATH, "autoEnable": BOOL}, each block, unblock or
  toggle of a Bluetooth radio, and each set_hard, moves that adapter of
  the sandbox's BlueZ mock as bluetoothd follows rfkill: blocked, Powered
  false and PowerState off-blocked; unblocked, Powered true and
  PowerState on with autoEnable, else PowerState off and Powered left
  false. The mock is reached on the system bus the caller's environment
  names, the sandbox's.
- bluetoothctl with no argument, or with exactly `--agent CAPABILITY` as
  the core's Bluetooth agent starts it, replays STATE/replies/bluetoothctl
  .transcript.json, a list of {"out": TEXT}, printed at once,
  {"in": LINE}, which reads one stdin line and ends with status 1 when it
  differs, {"wait": NAME}, which waits up to 30 s for STATE/NAME to exist,
  records {"waited": NAME} and ends with status 1 when it does not, and
  {"pair": ADDRESS}, which
  marks device ADDRESS of the BlueZ mock's hci0 paired, as BlueZ does once
  the agent's answer completes bonding; past the last step it records
  stdin until EOF.
- pw-play, the core's sound player, exits 0 after its record: it plays
  nothing, and its caller reads no answer but its exit.
- Any other call answers from STATE/replies/NAME.json, a list of
  {"argv", "stdout", "stderr", "status"} rows, the row whose argv equals
  the call's. device_reply keeps one row per argv and replaces older rows.
  A call no row answers prints the line
  `stand-in: name=NAME reply=none argv=<json>` on stderr and exits 1, so
  a caller never reads an answer no row planted.
"""

import json
import os
import sys
import time

# util-linux rfkill's type names and the label `rfkill list` prints.
RFKILL_LABELS = {"wlan": "Wireless LAN", "bluetooth": "Bluetooth", "uwb": "Ultra-Wideband", "wimax": "WiMAX",
                 "wwan": "Wireless WAN", "gps": "GPS", "fm": "FM", "nfc": "NFC"}
RFKILL_ALIASES = {"wifi": "wlan", "ultrawideband": "uwb"}


def append(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a") as out:
        out.write(json.dumps(value) + "\n")


def refuse(name, key, detail=""):
    print(f"stand-in: name={name} {key}", file=sys.stderr)
    if detail:
        print(detail, file=sys.stderr)
    sys.exit(1)


def load_rfkill(state):
    with open(os.path.join(state, "rfkill.json")) as source:
        return json.load(source)


def save_rfkill(state, doc):
    path = os.path.join(state, "rfkill.json")
    with open(path + ".next", "w") as out:
        json.dump(doc, out)
    os.replace(path + ".next", path)


def follow_bluez(state, doc):
    """Move the followed adapter as bluetoothd would after a radio change."""
    path = os.path.join(state, "bluez-follow.json")
    if not os.path.exists(path):
        return
    with open(path) as source:
        follow = json.load(source)
    radios = [d for d in doc["devices"] if d["type"] == "bluetooth"]
    blocked = any(d["soft"] == "blocked" or d["hard"] == "blocked" for d in radios)
    import dbus
    if blocked:
        props = {"Powered": dbus.Boolean(False), "PowerState": dbus.String("off-blocked")}
    elif follow["autoEnable"]:
        props = {"Powered": dbus.Boolean(True), "PowerState": dbus.String("on")}
    else:
        props = {"PowerState": dbus.String("off")}
    bus = dbus.bus.BusConnection(os.environ["DBUS_SYSTEM_BUS_ADDRESS"])
    dbus.Interface(bus.get_object("org.bluez", follow["adapter"]), "org.freedesktop.DBus.Mock").UpdateProperties("org.bluez.Adapter1", props)


def set_hard(state, kind, value):
    """A hardware switch: the hard state of every radio of KIND."""
    doc = load_rfkill(state)
    for d in doc["devices"]:
        if d["type"] == kind:
            d["hard"] = value
    save_rfkill(state, doc)
    follow_bluez(state, doc)


def rfkill_selected(devices, selector):
    if selector.isdigit():
        return [d for d in devices if d["id"] == int(selector)]
    selector = RFKILL_ALIASES.get(selector, selector)
    if selector != "all" and selector not in RFKILL_LABELS:
        return None
    return [d for d in devices if selector == "all" or d["type"] == selector]


def rfkill(state, argv):
    doc = load_rfkill(state)
    devices = doc["devices"]
    if not argv:
        print("ID TYPE      DEVICE    SOFT      HARD")
        for d in devices:
            print(f"{d['id']:>2} {d['type']:<9} {d['device']:<9} {d['soft']:<9} {d['hard']}")
        return
    if argv in (["-J"], ["--json"]):
        print(json.dumps({"rfkilldevices": devices}, indent=3))
        return
    verb, rest = argv[0], argv[1:]
    if verb == "list" and len(rest) <= 1:
        shown = devices if not rest else rfkill_selected(devices, rest[0])
        if shown is None:
            refuse("rfkill", f"selector={rest[0]} reason=unknown")
        for d in shown:
            print(f"{d['id']}: {d['device']}: {RFKILL_LABELS[d['type']]}")
            print(f"\tSoft blocked: {'yes' if d['soft'] == 'blocked' else 'no'}")
            print(f"\tHard blocked: {'yes' if d['hard'] == 'blocked' else 'no'}")
        return
    if verb in ("block", "unblock", "toggle") and rest:
        chosen = []
        seen = set()
        for selector in rest:
            selected = rfkill_selected(devices, selector)
            if selected is None:
                refuse("rfkill", f"selector={selector} reason=unknown")
            for device in selected:
                if device["id"] in seen:
                    continue
                seen.add(device["id"])
                chosen.append(device)
        for d in chosen:
            blocked = {"block": True, "unblock": False, "toggle": d["soft"] != "blocked"}[verb]
            d["soft"] = "blocked" if blocked else "unblocked"
        save_rfkill(state, doc)
        if any(d["type"] == "bluetooth" for d in chosen):
            follow_bluez(state, doc)
        return
    refuse("rfkill", "usage=unsupported argv=" + json.dumps(argv))


def transcript(state, path):
    with open(path) as source:
        steps = json.load(source)
    calls = os.path.join(state, "calls", "bluetoothctl.calls")
    for step in steps:
        if "out" in step:
            sys.stdout.write(step["out"])
            sys.stdout.flush()
            continue
        if "wait" in step:
            marker = os.path.join(state, step["wait"])
            deadline = time.monotonic() + 30
            while not os.path.exists(marker):
                if time.monotonic() > deadline:
                    refuse("bluetoothctl", "transcript=wait-timeout name=" + json.dumps(step["wait"]))
                time.sleep(0.05)
            append(calls, {"waited": step["wait"]})
            continue
        if "pair" in step:
            import dbus
            bus = dbus.bus.BusConnection(os.environ["DBUS_SYSTEM_BUS_ADDRESS"])
            dbus.Interface(bus.get_object("org.bluez", "/"), "org.bluez.Mock").PairDevice("hci0", step["pair"])
            continue
        line = sys.stdin.readline()
        if line == "":
            refuse("bluetoothctl", "transcript=ended-early want=" + json.dumps(step["in"]))
        line = line.rstrip("\n")
        append(calls, {"stdin": line})
        if line != step["in"]:
            refuse("bluetoothctl", "transcript=diverged want=" + json.dumps(step["in"]) + " got=" + json.dumps(line))
    for line in sys.stdin:
        append(calls, {"stdin": line.rstrip("\n")})
    append(calls, {"eof": True})


def replies(name, state, argv):
    path = os.path.join(state, "replies", name + ".json")
    rows = []
    if os.path.exists(path):
        with open(path) as source:
            rows = json.load(source)
    for row in rows:
        if row["argv"] == argv:
            sys.stdout.write(row.get("stdout", ""))
            sys.stderr.write(row.get("stderr", ""))
            sys.exit(row.get("status", 0))
    refuse(name, "reply=none argv=" + json.dumps(argv))


def main():
    if len(sys.argv) < 3:
        print("stand-in: usage=NAME STATE ARG...", file=sys.stderr)
        sys.exit(2)
    name, state, argv = sys.argv[1], sys.argv[2], sys.argv[3:]
    append(os.path.join(state, "calls", name + ".calls"), argv)
    if name == "rfkill":
        rfkill(state, argv)
        return
    if name == "pw-play":
        return
    script = os.path.join(state, "replies", "bluetoothctl.transcript.json")
    agent = len(argv) == 2 and argv[0] == "--agent"
    if name == "bluetoothctl" and (not argv or agent) and os.path.exists(script):
        transcript(state, script)
        return
    replies(name, state, argv)


if __name__ == "__main__":
    main()
