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
# power_wol_error [ID]: whether the Wake on LAN Field of the pane or
# Settings page draws the published problem, or has cleared it. Read the
# Field's visible text as well as its error so an undrawn binding fails.
power_wol_error() {
  local id="${1:-vgs.power}" status texts
  status="$(ipc smoke statusValues vgs.power)" || return 1
  texts="$(ipc smoke itemTexts window "$id" Field)" || return 1
  ipc smoke itemValues window "$id" Field label,error | py_reply 'import json,sys
label = json.load(open(sys.argv[1]))["schema"]["wakeOnLan"]["label"].casefold()
rows = json.load(sys.stdin)
texts = json.loads(sys.argv[3])
problem = json.loads(sys.argv[2]).get("wakeOnLanProblem", "")
fields = [(r, t) for r, t in zip(rows, texts) if r.get("label", "").casefold() == label] if isinstance(rows, list) and isinstance(texts, list) else []
if len(fields) != 1:
    print("absent")
else:
    field, drawn = fields[0]
    print("error" if isinstance(problem, str) and problem != "" and field.get("error") == problem and problem in drawn else "clear" if problem == "" and field.get("error") == "" else "mismatch")' "$repo/shell/plugins/vgs.power/manifest.json" "$status" "$texts"
}
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

# The Power and power menu rows and their screenshot scenes share one
# inert logind transport. Each Can method answers its file under
# power_sleep_replies, and User.Display answers the session id in
# Display, empty for no graphical session.
power_gdbus_stood=""
power_notify_stood=""
power_gdbus_calls="$sandbox/power-gdbus.calls"
power_set_hold="$sandbox/power-set.hold"
power_set_held="$sandbox/power-set.held"
power_set_release="$sandbox/power-set.release"
power_set_refuse="$sandbox/power-set.refuse"
power_set_refused="$sandbox/power-set.refused"
power_prepare_sleep_1="$sandbox/power-prepare-sleep-1"
power_prepare_sleep_2="$sandbox/power-prepare-sleep-2"
power_prepare_sleep_signals="$sandbox/power-prepare-sleep.signals"
power_sleep_replies="$sandbox/power-logind-replies"
power_sleep_refuse="$sandbox/power-sleep.refuse"
power_gdbus_saved=""

power_stand() {
  local name="$1"
  if [[ -e $shim/$name ]]; then
    case "$name" in
      notify-send) power_notify_stood=yes ;;
      gdbus) power_gdbus_stood=yes ;;
    esac
    sentinel_stand_over "$shim/$name"
  else
    case "$name" in
      notify-send) power_notify_stood=no ;;
      gdbus) power_gdbus_stood=no ;;
    esac
    cat >"$shim/$name" && chmod 755 "$shim/$name"
  fi
}

power_restore_stand() {
  if [[ $2 == yes ]]; then sentinel_restore "$shim/$1"; else power_unlink "$shim/$1"; fi
}

# Own only the private PATH link the harness created. Keep its exact link
# value beside it; neither the acquisition nor restoration follows it.
power_hide_gdbus() {
  local real_gdbus
  "$source_repo/scripts/smoke/gpu-fence.sh" --check || {
    echo 'power: gdbus-path=world-unproved' >&2
    return 1
  }
  real_gdbus="$(command -v gdbus)" || return
  power_gdbus_saved="$(mktemp -d "$sandbox/power-gdbus.XXXXXX")" || return
  python3 - "$sandbox" "$shell_host_path" "$power_gdbus_saved" "$real_gdbus" <<'PY_GDBUS_HIDE'
import os, pathlib, sys
root, host, saved, expected = map(pathlib.Path, sys.argv[1:])
if root.resolve(strict=True) != root or host != root / "host-path" or host.resolve(strict=True) != host or saved.parent != root or saved.resolve(strict=True) != saved:
    raise SystemExit("power: gdbus-path=outside-private-world")
link = host / "gdbus"
if not link.is_symlink() or os.readlink(link) != str(expected):
    raise SystemExit("power: gdbus-path=unexpected-link")
(saved / "target").write_text(os.readlink(link))
os.rename(link, saved / "gdbus")
PY_GDBUS_HIDE
}

power_restore_gdbus_path() {
  [[ -n $power_gdbus_saved ]] || return 0
  python3 - "$sandbox" "$shell_host_path" "$power_gdbus_saved" <<'PY_GDBUS_RESTORE' || return
import os, pathlib, sys
root, host, saved = map(pathlib.Path, sys.argv[1:])
if root.resolve(strict=True) != root or host != root / "host-path" or host.resolve(strict=True) != host or saved.parent != root or saved.resolve(strict=True) != saved:
    raise SystemExit("power: gdbus-restore=outside-private-world")
link, held = host / "gdbus", saved / "gdbus"
if not held.is_symlink() or os.readlink(held) != (saved / "target").read_text():
    raise SystemExit("power: gdbus-restore=ownership-lost")
if os.path.lexists(link):
    raise SystemExit("power: gdbus-restore=destination-changed")
# Hard-linking the symlink itself refuses an occupied destination.
os.link(held, link, follow_symlinks=False)
held.unlink()
(saved / "target").unlink()
saved.rmdir()
PY_GDBUS_RESTORE
  power_gdbus_saved=""
}

power_sleep_transport_ready() {
  [[ ${shell_start_path%%:*} == "$shim" && -x $shim/gdbus && $(shell_resolves gdbus) == "$shim/gdbus" ]] || {
    echo 'power: sleep-transport=not-owned' >&2
    return 1
  }
  echo ready
}


power_logind_start() {
  local real_gdbus
  power_hide_gdbus || return
  real_gdbus="$(readlink -- "$power_gdbus_saved/gdbus")" || return
  : >"$power_gdbus_calls" || return
  mkdir -p -- "$power_sleep_replies" || return
  printf 'yes\n' >"$power_sleep_replies/CanSuspend" || return
  printf 'no\n' >"$power_sleep_replies/CanHibernate" || return
  printf 'no\n' >"$power_sleep_replies/CanSuspendThenHibernate" || return
  printf 'no\n' >"$power_sleep_replies/CanReboot" || return
  printf 'no\n' >"$power_sleep_replies/CanPowerOff" || return
  : >"$power_sleep_replies/Display" || return
  power_stand gdbus <<EOF_STAND || return
#!/usr/bin/env bash
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "\$@" >>"$power_gdbus_calls"
logind=false
for word in "\$@"; do
  case "\$word" in org.freedesktop.login1|org.freedesktop.login1.*|--dest=org.freedesktop.login1) logind=true ;; esac
done
if [[ \$logind == true ]]; then
  if [[ \${1:-} == call ]]; then
    method=""
    for ((i=1; i<=\$#; i++)); do
      if [[ \${!i} == --method ]]; then j=\$((i+1)); method="\${!j}"; break; fi
    done
    case "\$method" in
      org.freedesktop.login1.Manager.CanSuspend|org.freedesktop.login1.Manager.CanHibernate|org.freedesktop.login1.Manager.CanSuspendThenHibernate|org.freedesktop.login1.Manager.CanReboot|org.freedesktop.login1.Manager.CanPowerOff)
        read -r answer <"$power_sleep_replies/\${method##*.}" || exit 65
        printf "('%s',)\\n" "\$answer"
        exit 0 ;;
      org.freedesktop.DBus.Properties.Get)
        [[ " \$* " == *" --object-path /org/freedesktop/login1/user/self "*" org.freedesktop.login1.User Display "* ]] || exit 64
        read -r session <"$power_sleep_replies/Display" || session=""
        if [[ -n \$session ]]; then printf "(<('%s', objectpath '/org/freedesktop/login1/session/smoke')>,)\\n" "\$session"
        else echo "(<('', objectpath '/')>,)"; fi
        exit 0 ;;
      org.freedesktop.login1.Manager.Suspend|org.freedesktop.login1.Manager.Hibernate|org.freedesktop.login1.Manager.SuspendThenHibernate)
        [[ \${!#} == false ]] || exit 64
        [[ ! -e "$power_sleep_refuse" ]] || exit 1
        echo '()'
        exit 0 ;;
      *) exit 64 ;;
    esac
  fi
  [[ \${1:-} == monitor ]] || exit 64
  echo 'Monitoring signals from all objects owned by org.freedesktop.login1'
  while :; do
    until [[ -e "$power_prepare_sleep_1" || -e "$power_prepare_sleep_2" ]]; do sleep 0.05; done
    if [[ -e "$power_prepare_sleep_1" ]]; then trigger="$power_prepare_sleep_1"; else trigger="$power_prepare_sleep_2"; fi
    rm -f -- "\$trigger"
    echo '/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,)'
    printf 'power-resume-emission pid=%s ppid=%s trigger=%s\n' "\$\$" "\$PPID" "\${trigger##*/}" >>"$power_prepare_sleep_signals"
  done
fi
if [[ " \$* " == *" org.freedesktop.DBus.Properties.Set "* && " \$* " == *" org.freedesktop.UPower.PowerProfiles "* ]]; then
  if mv -T -- "$power_set_hold" "$power_set_held" 2>/dev/null; then
    until [[ -e "$power_set_release" ]]; do sleep 0.05; done
  elif mv -T -- "$power_set_refuse" "$power_set_refused" 2>/dev/null; then
    exit 1
  fi
fi
exec env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$rt_dir/system-bus" "$real_gdbus" "\$@"
EOF_STAND

  power_sleep_transport_ready
}

power_logind_stop() {
  [[ -n $power_gdbus_saved ]] || return 0
  power_restore_stand gdbus "$power_gdbus_stood" || return
  power_restore_gdbus_path
}
