# Helpers for sandbox UPower and PowerProfiles fakes. Call only after the
# harness has set shell_env and spawn. Every D-Bus call uses the sandbox
# system bus through shell_env.
power_upower_pid="${power_upower_pid:-}"
power_profiles_pid="${power_profiles_pid:-}"
power_supply_added="${power_supply_added:-false}"

power_call() { "${shell_env[@]}" gdbus call --system "$@"; }
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
power_start_mocks() { # LOG_PREFIX [ACTIVE_PROFILE]
  local prefix="$1" active="${2:-balanced}"
  power_supply_added=false
  spawn "$sandbox/$prefix-upower.log" "${shell_env[@]}" python3 -m dbusmock --system --template upower
  power_upower_pid="$spawn_pid"
  spawn "$sandbox/$prefix-profiles.log" "${shell_env[@]}" python3 -m dbusmock --system --template upower_power_profiles_daemon
  power_profiles_pid="$spawn_pid"
  expect_poll "the sandbox UPower mock owns its bus name" true power_bus_has org.freedesktop.UPower
  expect_poll "the sandbox PowerProfiles mock owns its bus name" true power_bus_has org.freedesktop.UPower.PowerProfiles
  power_profile_set_mock "$active"
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
