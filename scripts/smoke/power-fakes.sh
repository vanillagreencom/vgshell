# Helpers for sandbox UPower and PowerProfiles fakes, the judge of a reveal
# in Power's section and the readers of its Wake on LAN field. Call only
# after the harness has set shell_env and spawn. Every D-Bus call uses the sandbox system bus through
# shell_env.
power_upower_pid="${power_upower_pid:-}"
power_profiles_pid="${power_profiles_pid:-}"
power_supply_added="${power_supply_added:-false}"

power_call() { "${shell_env[@]}" gdbus call --system "$@"; }
# power_revealed REPLY: whether a probe reveal (revealText,
# revealScopedText) scrolled its area, which it answers with the new
# offset. It answers `absent` for no such item and `unscrolled` for one no
# shown area holds, both with exit 0, and Power's section scrolls in the
# System window, so neither is a reveal there.
power_revealed() { [[ $1 =~ ^[0-9]+(\.[0-9]+)?$ ]]; }
# power_wol_field [ID]: whether the section of ID (vgs.power) draws the Wake
# on LAN field, and its switch's state when it does.
power_wol_field() { ipc smoke itemValues window "${1:-vgs.power}" Switch checked,visible,Accessible.name | py_reply 'import json,sys
rows = [r for r in json.load(sys.stdin) if r["visible"] and r["Accessible.name"] == "Wake on LAN"]
print("hidden" if not rows else "on" if rows[0]["checked"] else "off")'; }
# power_wol_error [ID]: whether that field draws an error line.
power_wol_error() { ipc smoke itemValues window "${1:-vgs.power}" Field label,error | py_reply 'import json,sys
rows = [r for r in json.load(sys.stdin) if r["label"] == "Wake on LAN"]
print("absent" if not rows else "error" if rows[0]["error"] != "" else "clear")'; }
power_unlink() { python3 - "$1" <<'PY_UNLINK'
import pathlib, sys
pathlib.Path(sys.argv[1]).unlink(missing_ok=True)
PY_UNLINK
}
power_bus_has() { power_call --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.NameHasOwner "$1" | py_reply 'import sys; print("true" if "true" in sys.stdin.read().lower() else "false")'; }
power_upower() { power_call --dest org.freedesktop.UPower --object-path /org/freedesktop/UPower --method "$@" >/dev/null; }
power_add_battery() { power_call --dest org.freedesktop.UPower --object-path /org/freedesktop/UPower --method org.freedesktop.DBus.Mock.AddDischargingBattery mock_BAT0 "Smoke Battery" "${1:-51.0}" "${2:-5400}" | py_reply "import re,sys; m=re.search(r\"'([^']+)'\", sys.stdin.read()); print(m.group(1) if m else '')"; }
power_profile_get() { power_call --dest org.freedesktop.UPower.PowerProfiles --object-path /org/freedesktop/UPower/PowerProfiles --method org.freedesktop.DBus.Properties.Get org.freedesktop.UPower.PowerProfiles ActiveProfile | py_reply "import re,sys; m=re.search(r\"'([^']+)'\", sys.stdin.read()); print(m.group(1) if m else '')"; }
power_profile_set_mock() { power_call --dest org.freedesktop.UPower.PowerProfiles --object-path /org/freedesktop/UPower/PowerProfiles --method org.freedesktop.DBus.Properties.Set org.freedesktop.UPower.PowerProfiles ActiveProfile "<'$1'>" >/dev/null; }
power_on_battery() { power_upower org.freedesktop.DBus.Properties.Set org.freedesktop.UPower OnBattery "<$1>"; }
power_supply() {
  if [[ $power_supply_added == false ]]; then
    power_call --dest org.freedesktop.UPower --object-path /org/freedesktop/UPower/devices/DisplayDevice --method org.freedesktop.DBus.Mock.AddProperty org.freedesktop.UPower.Device PowerSupply "<$1>" >/dev/null
    power_supply_added=true
  else
    power_upower org.freedesktop.DBus.Mock.SetDeviceProperties /org/freedesktop/UPower/devices/DisplayDevice "{'PowerSupply': <$1>}"
  fi
}
power_display() {
  power_upower org.freedesktop.DBus.Mock.SetupDisplayDevice "$1" "$2" "$3" "$3" 100.0 10.0 "$4" "$5" "$6" battery-good 1
  power_supply "$6"
}
power_no_battery() { power_display 0 0 0.0 0 0 false; }
power_discharging() { power_on_battery true; power_display 2 2 "$1" "$2" 0 true; }
power_charging() { power_on_battery false; power_display 2 1 "$1" 0 "$2" true; }
power_start_profiles() { # LOG_PREFIX ACTIVE_PROFILE
  spawn "$sandbox/$1-profiles.log" "${shell_env[@]}" python3 -m dbusmock --system --template upower_power_profiles_daemon
  power_profiles_pid="$spawn_pid"
  expect_poll "the sandbox PowerProfiles mock owns its bus name" true power_bus_has org.freedesktop.UPower.PowerProfiles
  power_profile_set_mock "$2"
}
power_start_mocks() { # LOG_PREFIX [ACTIVE_PROFILE]
  local prefix="$1" active="${2:-balanced}"
  power_supply_added=false
  spawn "$sandbox/$prefix-upower.log" "${shell_env[@]}" python3 -m dbusmock --system --template upower
  power_upower_pid="$spawn_pid"
  expect_poll "the sandbox UPower mock owns its bus name" true power_bus_has org.freedesktop.UPower
  power_start_profiles "$prefix" "$active"
}
power_stop_mock() { python3 - "$1" <<'PY_STOP'
import os, signal, sys
pid = sys.argv[1]
if pid.isdigit() and int(pid) > 1:
    try:
        os.killpg(int(pid), signal.SIGTERM)
    except ProcessLookupError:
        pass
PY_STOP
}
power_stop_mocks() {
  power_stop_mock "$power_upower_pid"
  power_stop_mock "$power_profiles_pid"
  power_upower_pid=""
  power_profiles_pid=""
}

# power_stage_owners: two plugins that declare idle stages at the times the
# shipped owners default to, dim at 120 s (vgs.displays), screensaver at
# 150 s (vgs.screensaver) and lock at 300 s (vgs.lock), and run nothing,
# each service an empty item, so the core's stage record holds the stages
# and no watch starts. acme.power-dim owns the dim, acme.power-away the
# screensaver and the lock. Both go under PLUGINS; the caller rescans,
# enables them and removes them.
power_stage_owners() { # PLUGINS
  power_stage_owner "$1/acme.power-dim" '{ "schemaVersion": 1, "id": "acme.power-dim", "name": "Dim Owner", "version": "0.1.0", "author": "acme", "description": "smoke fixture that declares the dim stage",
  "kinds": ["service"], "entryPoints": { "service": "Service.qml" }, "capabilities": ["idle"],
  "idleStages": { "dim": { "seconds": "dimAfter" } },
  "settings": { "dimAfter": 120 },
  "schema": { "dimAfter": { "type": "number", "label": "Dim after", "min": 0, "max": 3600, "step": 30, "unit": "seconds" } } }'
  power_stage_owner "$1/acme.power-away" '{ "schemaVersion": 1, "id": "acme.power-away", "name": "Away Owner", "version": "0.1.0", "author": "acme", "description": "smoke fixture that declares the screensaver and lock stages",
  "kinds": ["service"], "entryPoints": { "service": "Service.qml" }, "capabilities": ["idle"],
  "idleStages": { "screensaver": { "seconds": "saverAfter", "enabled": "saverOn" }, "lock": { "seconds": "lockAfter" } },
  "settings": { "saverOn": true, "saverAfter": 150, "lockAfter": 300 },
  "schema": {
    "saverOn": { "type": "boolean", "label": "Start the screensaver" },
    "saverAfter": { "type": "number", "label": "Screensaver after", "min": 0, "max": 3600, "step": 30, "unit": "seconds" },
    "lockAfter": { "type": "number", "label": "Lock after", "min": 0, "max": 3600, "step": 30, "unit": "seconds" } } }'
}
power_stage_owner() { # DIR MANIFEST
  mkdir -p -- "$1"
  printf '%s\n' "$2" >"$1/manifest.json"
  printf 'import QtQuick\nItem { property var shell: null }\n' >"$1/Service.qml"
}
# power_stage_setting CONFIG KEY VALUE: one value of acme.power-away's
# plugins row in the shell configuration CONFIG; null removes it.
power_stage_setting() { python3 - "$@" <<'PY_STAGE'
import json, os, sys
path, key, value = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
config = json.load(open(path))
rows = config.setdefault("plugins", [])
row = next((r for r in rows if r.get("id") == "acme.power-away"), None)
if row is None:
    row = {"id": "acme.power-away"}
    rows.append(row)
if value is None:
    row.pop(key, None)
else:
    row[key] = value
json.dump(config, open(path + ".tmp", "w"), indent=2)
os.replace(path + ".tmp", path)
PY_STAGE
}
