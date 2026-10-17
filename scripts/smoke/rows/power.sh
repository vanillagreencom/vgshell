# vgs.power over the sandbox's device fakes: python-dbusmock's upower
# template and upower_power_profiles_daemon template run on the sandbox
# system bus. The row starts the UPower mock before it restarts the shell,
# because Quickshell's UPower singleton connects once when first read. The
# smoke set disables vgs.power, so the row starts the mocks and then
# enables the plugin for the first time in this shell. The row drives the
# mocks through their D-Bus interfaces with shell_env, so no call reaches
# the host's UPower, power-profiles-daemon, battery, charger or system
# bus. The power profile service's D-Bus name satisfies the requirement
# probe.
#
# Two stand-ins record the argv the shell runs. notify-send records each
# notice the core's `notify` capability sends for the plugin. gdbus
# records each run of the service and hands it to the real gdbus with the
# sandbox system bus as its address, whatever the argv names. It is also
# the row's barrier on a profile write, a Properties.Set run: armed by
# power_hold_next_set, it holds the next write until power_release_set,
# reading the release file 0.05 s apart; armed by the refuse file, it ends
# the next write with exit 1 and the daemon never sees it. The row's own
# gdbus calls come from the host path and never pass through it.
#
# The bus variable: every sandbox shell runs with DBUS_SYSTEM_BUS_ADDRESS
# set, and the row never starts one without it, since Quickshell's UPower
# singleton would then read the host's bus. The check is therefore on the
# argv: the service's runs name `--system` and no address, so they are the
# same runs with the variable unset. The control restores the test of the
# variable against "" on a name no sandbox shell sets, which is what the
# shell read on a machine with the variable unset; its runs name
# `--address`, and the stand-in still lands them on the sandbox bus.
#
# Rows: before the mocks start, the first enable raises a requirement
# notice for org.freedesktop.UPower.PowerProfiles; after the mocks own that
# name, enabling vgs.power raises no notice and the requirement reads
# present. Those two readings are each other's control. The first real
# enable sees a discharging battery and a power-saver profile without
# applying the remembered battery profile; the widget draws the 51 % text
# and a non-charging icon; with a charging display battery,
# it draws the charging icon; one discharge sends one low and one critical
# alert through `notify`, each with its icon and tone, no repeats below the same
# thresholds; the panel draws the battery level, state and time left in
# one Field, lists the profiles the daemon offers as icon tiles with the
# active one marked, and follows the daemon to a shorter list; keyboard
# selection in the panel chooses Performance and writes the current source setting; a
# plug change applies the remembered charger profile; removing the display
# battery hides the widget's battery part again; Power's Settings tab draws
# its four battery fields with a battery, none with no battery and all
# four again once the display battery is back; with no battery a bar pick
# sets the profile and remembers no setting, and with one it remembers
# the current source's; and a profile service that starts after the
# plugin is read. Two orders of a profile write
# are held with the barrier: a profile asked for while a write runs is
# written next, and after a write the daemon refuses the mark returns to
# the daemon's profile. Controls build fixture
# copies at run time: acme.power-relatch sends low twice in one discharge
# and sends its notices without an icon or tone, acme.power-nocharge draws no
# charging icon while the service publishes charging, acme.power-order
# drops a profile asked for while a write runs and starts no read after a
# refused write, acme.power-busenv is the address control above, and
# acme.power-once reads the service only on the watch's first line, so it
# never reads one that starts later. A control that asserts something did
# not happen waits for the line its fixture logs when it decides not to,
# then reads once. Polls use expect_poll's reads 0.2 s apart.
# The row disables vgs.power, starts the mocks, then restarts the shell
# before the first enable, so Quickshell's connect-once UPower singleton
# binds to the mock no matter what earlier rows left. The row restores
# notify-send and gdbus, vgs.power's
# enablement and placement, moves fixture copies out of the plugin
# directory, stops the mock process groups it spawned, and restarts the
# shell because Quickshell keeps that singleton in the process after the
# plugin is disabled.
# inputs: shell/plugins/vgs.power/* shell/plugins/vgs.settings/* shell/Core/Registry.qml shell/Core/Capabilities.qml shell/Core/PluginStatus.qml shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/Core/Notices.qml shell/Core/Notifier.qml shell/Hosts/NoticeHost.qml shell/Hosts/SummonHost.qml bin/vgshell-scan scripts/smoke/rows/device-fakes.sh scripts/smoke/power-fakes.sh
set -euo pipefail
source "$repo/scripts/smoke/power-fakes.sh"

power_upower_pid=""
power_profiles_pid=""
power_notify_stood=""
power_gdbus_stood=""
power_was_enabled=""
power_was_placed=""
power_relatch_dir="$home/.config/vgshell/plugins/acme.power-relatch"
power_nocharge_dir="$home/.config/vgshell/plugins/acme.power-nocharge"
power_busenv_dir="$home/.config/vgshell/plugins/acme.power-busenv"
power_once_dir="$home/.config/vgshell/plugins/acme.power-once"
power_order_dir="$home/.config/vgshell/plugins/acme.power-order"
power_notify_calls="$sandbox/power-notify-send.calls"
power_gdbus_calls="$sandbox/power-gdbus.calls"
power_set_hold="$sandbox/power-set.hold"
power_set_held="$sandbox/power-set.held"
power_set_release="$sandbox/power-set.release"
power_set_refuse="$sandbox/power-set.refuse"
power_set_refused="$sandbox/power-set.refused"
power_moved_count=0
power_watch_ends=0
power_notify_base=0

power_move_away() { # PATH
  local path="$1" dest
  [[ -e $path ]] || return 0
  power_moved_count=$((power_moved_count + 1))
  dest="$sandbox/power-moved-$power_moved_count"
  mv -T -- "$path" "$dest"
}

power_unlink() { python3 - "$1" <<'PY_UNLINK'
import pathlib, sys
pathlib.Path(sys.argv[1]).unlink(missing_ok=True)
PY_UNLINK
}

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

power_widget() { ipc smoke readInstance "$(bar_key)" "${power_id:-vgs.power}" "$1"; }
power_requirement_state() { ipc shell listPlugins | py_reply 'import json,sys; p=[p for p in json.load(sys.stdin)["plugins"] if p["id"]=="vgs.power"][0]; print([r["state"] for r in p["requirements"] if r["name"]=="org.freedesktop.UPower.PowerProfiles"][0])'; }
power_status() { ipc smoke statusValues "${power_id:-vgs.power}" | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get("power"), sort_keys=True, separators=(",", ":")))'; }
power_status_charging() { power_status | py_reply 'import json,sys; print(json.load(sys.stdin)["battery"]["charging"])'; }
power_status_dump() { power_status; }
power_notify_count() { [[ -f $power_notify_calls ]] && wc -l <"$power_notify_calls" || echo 0; }
power_notify_delta() { local n; n="$(power_notify_count)" || return; echo $((n - power_notify_base)); }
power_notify_delta_over_one() { local n; n="$(power_notify_delta)" || return; [[ $n -gt 1 ]] && echo yes || echo "no $n"; }
power_notify_urgencies() { [[ -f $power_notify_calls ]] && py_reply 'import json,sys; print(json.dumps([a for line in sys.stdin for a in json.loads(line) if a.startswith("--urgency=")]))' <"$power_notify_calls" || echo '[]'; }
power_notify_icons() { [[ -s $power_notify_calls ]] && py_reply 'import json,sys; print(json.dumps([a.rsplit(":", 1)[1] for line in sys.stdin for a in json.loads(line) if a.startswith("--hint=string:x-vgs-icon:")]))' <"$power_notify_calls" || echo '[]'; }
power_notify_tones() { [[ -s $power_notify_calls ]] && py_reply 'import json,sys; print(json.dumps([a.rsplit(":", 1)[1] for line in sys.stdin for a in json.loads(line) if a.startswith("--hint=string:x-vgs-tone:")]))' <"$power_notify_calls" || echo '[]'; }
# A record file with no line holds no run; py_reply answers an empty input
# as a failed read, so each reader of one answers that state itself.
# power_service_buses: the bus words of the service's own gdbus runs, its
# watch and its reads, sorted and once each.
power_service_buses() { [[ -s $power_gdbus_calls ]] && py_reply 'import json,sys
runs = [json.loads(line) for line in sys.stdin]
print(json.dumps(sorted({a for run in runs if run[:1] == ["monitor"] or "org.freedesktop.DBus.Properties.GetAll" in run for a in run if a in ("--system", "--session", "--address")})))' <"$power_gdbus_calls" || echo '[]'; }
power_reads() { [[ -s $power_gdbus_calls ]] && py_reply 'import json,sys; print(sum("org.freedesktop.DBus.Properties.GetAll" in json.loads(line) for line in sys.stdin))' <"$power_gdbus_calls" || echo 0; }
power_has_read() { local n; n="$(power_reads)" || return; [[ $n -gt 0 ]] && echo yes || echo no; }
power_status_active() { power_status | py_reply 'import json,sys; print(json.load(sys.stdin)["profile"]["active"])'; }
power_profile_list() { ipc smoke itemValues panel vgs.power TileGroup model,currentIndex | py_reply 'import json,sys; print(json.dumps([[[m["text"] for m in r["model"]], r["currentIndex"]] for r in json.load(sys.stdin)]))'; }
power_profile_icons() { ipc smoke itemValues panel vgs.power TileGroup model | py_reply 'import json,sys; print(json.dumps([[m["icon"] for m in r["model"]] for r in json.load(sys.stdin)]))'; }
power_profiles_set_mock() { power_call --dest org.freedesktop.UPower.PowerProfiles --object-path /org/freedesktop/UPower/PowerProfiles --method org.freedesktop.DBus.Properties.Set org.freedesktop.UPower.PowerProfiles Profiles "<[$1]>" >/dev/null; }
# power_battery_field: the texts of the panel Field that draws the battery, sorted.
power_battery_field() { ipc smoke itemTexts panel vgs.power Field | py_reply 'import json,sys; print(json.dumps(sorted(next((row for row in json.load(sys.stdin) if "Battery" in row), []))))'; }
# power_set_writes: the profiles of the service's write runs, in the order
# the stand-in recorded them.
power_set_writes() { [[ -s $power_gdbus_calls ]] && py_reply 'import json,sys
runs = [json.loads(line) for line in sys.stdin]
print(json.dumps([run[-1][2:-2] for run in runs if "org.freedesktop.DBus.Properties.Set" in run]))' <"$power_gdbus_calls" || echo '[]'; }
power_exists() { [[ -e $1 ]] && echo yes || echo no; }
# power_battery_fields: which of the four battery settings Power's Settings
# tab draws, as the sorted schema keys whose label a SettingField of the
# Settings window shows. The keys are listed here, not read from the
# manifest's shownWhen, so a field that loses its condition still counts.
power_battery_keys='["batteryProfile", "chargerProfile", "criticalThreshold", "lowThreshold"]'
power_battery_fields() { ipc smoke itemTexts window vgs.settings SettingField | py_reply 'import json,sys
schema = json.load(open(sys.argv[1]))["schema"]
drawn = {t.lower() for row in json.load(sys.stdin) for t in row}
print(json.dumps(sorted(k for k in json.loads(sys.argv[2]) if schema[k]["label"].lower() in drawn)))' "$repo/shell/plugins/vgs.power/manifest.json" "$power_battery_keys"; }
power_battery_presence() { ipc smoke statusValues vgs.power | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get("battery")))'; }
power_hold_next_set() {
  power_unlink "$power_set_held"
  power_unlink "$power_set_release"
  : >"$power_set_hold"
}
power_release_set() { : >"$power_set_release"; }
power_label_has() { ipc smoke itemTexts panel vgs.power Label | py_reply 'import json,sys; print(any(sys.argv[1] in row for row in json.load(sys.stdin)))' "$1"; }
power_level() { power_status | py_reply 'import json,sys; print(json.load(sys.stdin)["battery"]["level"])'; }
power_profile_available() { power_status | py_reply 'import json,sys; print(json.load(sys.stdin)["profile"]["available"])'; }
power_icons() { ipc smoke itemValues "$(bar_key)" "${power_id:-vgs.power}" BarItem iconName,text,visible | py_reply 'import json,sys; print(json.dumps([r["iconName"] for r in json.load(sys.stdin) if r["visible"]]))'; }
power_texts() { ipc smoke itemTexts "$(bar_key)" "${power_id:-vgs.power}" BarItem | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)))'; }
power_setting() { python3 - "$home/.config/vgshell/shell.json" "$1" <<'PY_SET'
import json, sys
rows = [r for r in json.load(open(sys.argv[1])).get("plugins", []) if r.get("id") == "vgs.power"]
print(json.dumps(rows[0].get(sys.argv[2])) if rows and sys.argv[2] in rows[0] else "null")
PY_SET
}
power_install_fixture() { # ID DIR FILE OLD NEW [FILE OLD NEW]...
  local id="$1" dir="$2"
  shift 2
  power_move_away "$dir"
  cp -R -- "$repo/shell/plugins/vgs.power" "$dir"
  python3 - "$id" "$dir" "$@" <<'PY_MUTANT'
import json, os, sys
plugin, root, edits = sys.argv[1], sys.argv[2], sys.argv[3:]
if not edits or len(edits) % 3:
    raise SystemExit(f"edit-words={len(edits)} want=FILE OLD NEW triples")
manifest = os.path.join(root, "manifest.json")
doc = json.load(open(manifest))
doc["id"] = plugin
doc["name"] = plugin
json.dump(doc, open(manifest, "w"), indent=2)
for file_name, old, new in zip(edits[0::3], edits[1::3], edits[2::3]):
    path = os.path.join(root, file_name)
    text = open(path).read()
    if text.count(old) != 1:
        raise SystemExit(f"replace-count={text.count(old)} file={file_name}")
    changed = text.replace(old, new)
    if changed == text:
        raise SystemExit(f"unchanged file={file_name}")
    open(path, "w").write(changed)
PY_MUTANT
}


power_main() {
  devices_ready power || return 0
  power_was_enabled="$(plugin_enabled vgs.power)" || { fail "power: vgs.power's enabled state is unreadable"; return 0; }
  power_was_placed="$(bar_widget_ids | py_reply 'import json,sys; print("True" if any("vgs.power" in ids for ids in json.load(sys.stdin)) else "False")')" || { fail "power: vgs.power's placement is unreadable"; return 0; }

  : >"$power_notify_calls"
  power_stand notify-send <<EOF_STAND
#!/usr/bin/env bash
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "\$@" >>"$power_notify_calls"
EOF_STAND
  : >"$power_gdbus_calls"
  power_stand gdbus <<EOF_STAND
#!/usr/bin/env bash
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "\$@" >>"$power_gdbus_calls"
if [[ " \$* " == *" org.freedesktop.DBus.Properties.Set "* ]]; then
  if mv -T -- "$power_set_hold" "$power_set_held" 2>/dev/null; then
    until [[ -e "$power_set_release" ]]; do sleep 0.05; done
  elif mv -T -- "$power_set_refuse" "$power_set_refused" 2>/dev/null; then
    exit 1
  fi
fi
exec env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$rt_dir/system-bus" $(command -v gdbus) "\$@"
EOF_STAND

  expect "disabling vgs.power before the UPower restart is allowed" ok ipc shell setPluginEnabled vgs.power false
  rescan "rescan before the PowerProfiles mock starts answers ok"
  expect "the power profiles service is missing before its mock starts" missing power_requirement_state
  expect "enabling vgs.power without the PowerProfiles bus name is allowed" ok ipc shell setPluginEnabled vgs.power true
  expect_poll "enabling without the PowerProfiles bus name raises its requirement notice" '["vgs.power", ["org.freedesktop.UPower.PowerProfiles"], ["org.freedesktop.UPower.PowerProfiles"], false]' notice_shown
  expect_poll "the PowerProfiles requirement notice holds the keyboard" true ipc smoke noticeFocused
  type_keys -k Escape || fail "sending Escape to the PowerProfiles requirement notice failed"
  expect_poll "Escape closes the PowerProfiles requirement notice" null notice_shown
  expect "disabling vgs.power after the missing-service proof is allowed" ok ipc shell setPluginEnabled vgs.power false
  power_start_mocks power power-saver
  expect "the mock starts with a discharging battery object" "/org/freedesktop/UPower/devices/mock_BAT0" power_add_battery
  power_discharging 51.0 5400
  stop_shell || fail "power: the shell stops before the UPower restart"
  start_shell "$repo" "$sandbox/qs-power.log" || return 0
  rescan "rescan after adding power stand-ins answers ok"
  expect_poll "the power profiles service requirement is present after mocks start" present power_requirement_state
  expect "enabling vgs.power is allowed" ok ipc shell setPluginEnabled vgs.power true
  expect "enabling vgs.power with the PowerProfiles bus name raises no notice" null notice_shown
  expect "placing vgs.power in the bar is allowed" ok ipc shell setPluginPlaced vgs.power true
  expect_poll "the Power service publishes the initial discharging battery" 51 power_level
  expect_poll "the Power service reports profiles available" True power_profile_available
  expect "the service's watch and reads name the system bus and no address" '["--system"]' power_service_buses
  expect "the first enable does not apply the remembered battery profile" power-saver power_profile_get
  expect_poll "the widget draws the 51 percent battery text" '[["51%"], []]' power_texts
  expect_poll "the widget draws the medium battery and power saver icons" '["battery-medium", "leaf"]' power_icons
  power_charging 52.0 2400
  expect_poll "the service reads the charging level" 52 power_level
  expect_poll "the widget draws the charging icon" '["battery-charging", "zap"]' power_icons

  : >"$power_notify_calls"
  power_discharging 19.0 3000
  expect_poll "the service reads the low level before alert count" 19 power_level
  expect_poll "crossing low sends one alert" 1 power_notify_count
  power_discharging 18.0 2900
  expect_poll "the service reads the next low level before alert count" 18 power_level
  expect "staying below low sends no second low alert" 1 power_notify_count
  power_discharging 9.0 1200
  expect_poll "the service reads the critical level before alert count" 9 power_level
  expect_poll "crossing critical sends one more alert" 2 power_notify_count
  power_discharging 8.0 1000
  expect_poll "the service reads the next critical level before alert count" 8 power_level
  expect "staying below critical sends no second critical alert" 2 power_notify_count
  expect "the low and critical alerts use their urgencies" '["--urgency=normal", "--urgency=critical"]' power_notify_urgencies
  expect "the low and critical alerts carry their icons" '["battery-low", "battery-warning"]' power_notify_icons
  expect "the low alert is a warning and the critical one danger" '["warning", "danger"]' power_notify_tones

  expect "the Power panel opens" ok ipc shell summon panel vgs.power '{}'
  expect_poll "the Power panel focuses the profile control" true ipc smoke activeFocusIn panel vgs.power
  expect_poll "the panel draws the level, the state and the time left in the Battery field" '["17 min left", "8%", "Battery", "On battery"]' power_battery_field
  expect_poll "the panel lists the daemon's profiles with the active one marked" '[[["Power saver", "Balanced", "Performance"], 1]]' power_profile_list
  expect "the panel draws each profile's icon on its tile" '[["leaf", "gauge", "zap"]]' power_profile_icons
  power_profiles_set_mock "{'Profile': <'power-saver'>, 'Driver': <'dbusmock'>}, {'Profile': <'balanced'>, 'Driver': <'dbusmock'>}"
  expect_poll "the panel follows the daemon to a list without Performance" '[[["Power saver", "Balanced"], 1]]' power_profile_list
  power_profiles_set_mock "{'Profile': <'power-saver'>, 'Driver': <'dbusmock'>}, {'Profile': <'balanced'>, 'Driver': <'dbusmock'>}, {'Profile': <'performance'>, 'Driver': <'dbusmock'>}"
  expect_poll "the panel lists Performance again" '[[["Power saver", "Balanced", "Performance"], 1]]' power_profile_list
  type_keys -k Right || fail "typing Right in the Power panel failed"
  expect_poll "the panel keyboard path chooses Performance" performance power_profile_get
  expect_poll "the panel marks Performance" '[[["Power saver", "Balanced", "Performance"], 2]]' power_profile_list
  expect_poll "choosing Performance remembers the battery profile" '"performance"' power_setting batteryProfile

  : >"$power_gdbus_calls"
  power_hold_next_set
  expect "a profile request with no write running is taken" power-saver ipc vgs.power invoke profile power-saver
  expect_poll "the stand-in holds the service's write" yes power_exists "$power_set_held"
  expect "a profile request inside that write is taken" balanced ipc vgs.power invoke profile balanced
  power_release_set
  expect_poll "the daemon holds the profile asked for inside the write" balanced power_profile_get
  expect "the service wrote both profiles in the order asked" '["power-saver", "balanced"]' power_set_writes
  expect_poll "the panel marks the profile asked for inside the write" '[[["Power saver", "Balanced", "Performance"], 1]]' power_profile_list
  expected_errors+=('power: profile write exit=1$')
  : >"$power_set_refuse"
  expect "a profile request whose write the daemon refuses is taken" performance ipc vgs.power invoke profile performance
  expect_log "the service logs the refused write" 1 'power: profile write exit=1$'
  expect_poll "after the refused write the panel marks the daemon's profile" '[[["Power saver", "Balanced", "Performance"], 1]]' power_profile_list
  expect "the refused write never reached the daemon" balanced power_profile_get
  power_profile_set_mock balanced
  expect_poll "the mock profile was reset to balanced" balanced power_profile_get
  power_on_battery false
  expect_poll "plugging in applies the remembered charger profile" performance power_profile_get
  expect "the Power panel closes" ok ipc shell hide panel vgs.power

  expect "Settings opens on Power's Settings tab" ok ipc shell summon window vgs.settings '{"plugin":"vgs.power","tab":"Settings"}'
  expect_poll "with a battery Settings draws Power's four battery fields" "$power_battery_keys" power_battery_fields
  power_no_battery
  expect_poll "removing the display battery hides the widget battery text" '[[], []]' power_texts
  expect_poll "removing the display battery leaves the profile icon" '["zap"]' power_icons
  expect_poll "with no battery the service publishes the battery absent" '"absent"' power_battery_presence
  expect_poll "with no battery Settings draws none of Power's battery fields" '[]' power_battery_fields
  expect "with no battery a bar pick is taken" power-saver ipc vgs.power invoke profile power-saver
  expect_poll "with no battery the daemon holds the bar pick" power-saver power_profile_get
  power_discharging 64.0 7200
  expect_poll "with the battery back the service publishes it present" '"present"' power_battery_presence
  expect_poll "with the battery back Settings draws Power's four battery fields again" "$power_battery_keys" power_battery_fields
  # Writes to the configuration land in order, so once this pick is stored
  # a store of the no-battery pick would be too.
  expect "with a battery a bar pick is taken" balanced ipc vgs.power invoke profile balanced
  expect_poll "with a battery a bar pick remembers the battery profile" '"balanced"' power_setting batteryProfile
  expect "with no battery the bar pick remembered no charger profile" null power_setting chargerProfile
  expect "the Settings window hides after Power's fields" ok ipc shell hide window vgs.settings
  expect_poll "the Settings window is gone after Power's fields" 0 window_count Plugins

  expect "disabling vgs.power for controls is allowed" ok ipc shell setPluginEnabled vgs.power false
  power_install_fixture acme.power-relatch "$power_relatch_dir" PowerLogic.js \
    'if (!next.low) out.push({ threshold: "low", urgency: "normal", level: n });
        next.low = true;' \
    'if (!next.low) out.push({ threshold: "low", urgency: "normal", level: n });
        next.low = false;' \
    PowerLogic.js \
    '        tone: critical ? "danger" : "warning",
        icon: critical ? "battery-warning" : "battery-low",
' \
    ''
  rescan "rescan after adding the relatch fixture answers ok"
  expect "enabling the relatch fixture is allowed" ok ipc shell setPluginEnabled acme.power-relatch true
  power_id=acme.power-relatch
  : >"$power_notify_calls"
  power_charging 30.0 3600
  expect_poll "the relatch fixture starts from a charging state" True power_status_charging
  power_notify_base="$(power_notify_count)"
  power_discharging 19.0 3000
  expect_poll "control: relatch sends more than one low alert" yes power_notify_delta_over_one
  power_discharging 18.0 2900
  expect_poll "control: relatch keeps sending low in one discharge" yes power_notify_delta_over_one
  expect "control: a notice sent without the icon carries none" '[]' power_notify_icons
  expect "control: a notice sent without the tone carries none" '[]' power_notify_tones
  unset power_id
  expect "disabling the relatch fixture is allowed" ok ipc shell setPluginEnabled acme.power-relatch false
  power_move_away "$power_relatch_dir"

  power_install_fixture acme.power-nocharge "$power_nocharge_dir" PowerLogic.js \
    'batteryIcon: batteryIcon(Number(battery.level || 0), battery.charging === true),' \
    'batteryIcon: batteryIcon(Number(battery.level || 0), false),'
  rescan "rescan after adding the nocharge fixture answers ok"
  expect "enabling the nocharge fixture is allowed" ok ipc shell setPluginEnabled acme.power-nocharge true
  expect "placing the nocharge fixture is allowed" ok ipc shell setPluginPlaced acme.power-nocharge true
  power_id=acme.power-nocharge
  power_charging 52.0 2400
  expect_poll "control: the nocharge fixture service publishes charging" True power_status_charging
  expect_poll "control: the nocharge widget ignores charging" '["battery-medium", "zap"]' power_icons
  unset power_id
  expect "unplacing the nocharge fixture is allowed" ok ipc shell setPluginPlaced acme.power-nocharge false
  expect "disabling the nocharge fixture is allowed" ok ipc shell setPluginEnabled acme.power-nocharge false
  power_move_away "$power_nocharge_dir"

  power_install_fixture acme.power-order "$power_order_dir" Service.qml \
    '            if (root.profileWanted !== "") root.writeProfile(root.profileWanted);' \
    '            if (root.profileWanted !== "") console.warn("power: control dropped wanted=" + root.profileWanted);' \
    Service.qml \
    '                console.warn("power: profile write exit=" + code);
                root.readProfiles();' \
    '                console.warn("power: profile write exit=" + code);'
  expected_errors+=('power: control dropped wanted=')
  power_profile_set_mock performance
  rescan "rescan after adding the order fixture answers ok"
  expect "enabling the order fixture is allowed" ok ipc shell setPluginEnabled acme.power-order true
  power_id=acme.power-order
  expect_poll "the order fixture reads the daemon's profile" performance power_status_active
  power_hold_next_set
  expect "the order fixture takes a profile request" power-saver ipc acme.power-order invoke profile power-saver
  expect_poll "the stand-in holds the order fixture's write" yes power_exists "$power_set_held"
  expect "the order fixture takes a request inside that write" balanced ipc acme.power-order invoke profile balanced
  power_release_set
  expect_log "control: a service without the next-write step drops the profile asked for inside the write" 1 'power: control dropped wanted=balanced$'
  expect "control: the daemon then holds the first profile, not the second" power-saver power_profile_get
  expect_poll "the order fixture's mark follows the daemon to the first profile" power-saver power_status_active
  : >"$power_set_refuse"
  expect "the order fixture takes a request whose write the daemon refuses" performance ipc acme.power-order invoke profile performance
  expect_log "control: the order fixture logs the refused write" 2 'power: profile write exit=1$'
  expect "control: with no read after a refused write the mark stays on a profile the daemon does not hold" performance power_status_active
  expect "control: the daemon still holds the first profile" power-saver power_profile_get
  unset power_id
  expect "disabling the order fixture is allowed" ok ipc shell setPluginEnabled acme.power-order false
  power_move_away "$power_order_dir"


  power_install_fixture acme.power-busenv "$power_busenv_dir" Service.qml \
    'import Quickshell.Io
' \
    'import Quickshell
import Quickshell.Io
' \
    Service.qml \
    '    readonly property var profilesBus: ["--system", "--dest", profilesInterface, "--object-path", "/org/freedesktop/UPower/PowerProfiles"]' \
    '    readonly property var profilesBus: (Quickshell.env("VGS_SMOKE_UNSET_BUS_ADDRESS") === "" ? ["--system"] : ["--address", Quickshell.env("VGS_SMOKE_UNSET_BUS_ADDRESS")]).concat(["--dest", profilesInterface, "--object-path", "/org/freedesktop/UPower/PowerProfiles"])'
  expected_errors+=('power: profile watch ended exit=')
  power_watch_ends="$(log_lines 'power: profile watch ended exit=')" || { fail "power: the instance log is unreadable before the busenv fixture"; power_watch_ends=0; }
  # A scan builds a plugin it meets for the first time, so the record is
  # emptied before the scan that meets the fixture.
  : >"$power_gdbus_calls"
  rescan "rescan after adding the busenv fixture answers ok"
  expect "enabling the busenv fixture is allowed" ok ipc shell setPluginEnabled acme.power-busenv true
  power_id=acme.power-busenv
  expect_poll "control: the test of an unset variable against the empty text names an address" '["--address"]' power_service_buses
  expect_log "control: with that address the watch ends" "$((power_watch_ends + 1))" 'power: profile watch ended exit='
  expect "control: after the watch ends the profiles read unavailable" False power_profile_available
  unset power_id
  expect "disabling the busenv fixture is allowed" ok ipc shell setPluginEnabled acme.power-busenv false
  power_move_away "$power_busenv_dir"
  rescan "rescan after removing the power fixtures answers ok"

  if [[ $power_was_placed != True ]]; then
    expect "enabling vgs.power to restore placement is allowed" ok ipc shell setPluginEnabled vgs.power true
    expect "restoring vgs.power placement is allowed" ok ipc shell setPluginPlaced vgs.power false
  fi
  if [[ $power_was_enabled == True ]]; then expect "restoring vgs.power enablement is allowed" ok ipc shell setPluginEnabled vgs.power true; fi

  expect "disabling vgs.power before the unavailable check is allowed" ok ipc shell setPluginEnabled vgs.power false
  power_stop_mock "$power_profiles_pid"
  power_profiles_pid=""
  expect_poll "the profile mock releases its bus name" false power_bus_has org.freedesktop.UPower.PowerProfiles
  : >"$power_gdbus_calls"
  expect "re-enabling vgs.power without the profile daemon starts clean" ok ipc shell setPluginEnabled vgs.power true
  expect_poll "the service reads the absent profile daemon" yes power_has_read
  expect "without the profile daemon the service reports profiles unavailable" False power_profile_available
  expect "the unavailable profile panel opens" ok ipc shell summon panel vgs.power '{}'
  expect_poll "the unavailable profile panel says profiles are unavailable" True power_label_has "Power profiles are not available."
  power_start_profiles power-later performance
  expect_poll "a profile service that starts after the plugin is read" True power_profile_available
  expect_poll "the later service's active profile is read" performance power_status_active
  expect_poll "the open panel lists the later service's profiles" '[[["Power saver", "Balanced", "Performance"], 2]]' power_profile_list
  expect "the Power panel closes after the later service" ok ipc shell hide panel vgs.power
  expect "disabling vgs.power after the later service check is allowed" ok ipc shell setPluginEnabled vgs.power false

  power_stop_mock "$power_profiles_pid"
  power_profiles_pid=""
  expect_poll "the later profile mock releases its bus name" false power_bus_has org.freedesktop.UPower.PowerProfiles
  power_install_fixture acme.power-once "$power_once_dir" Service.qml \
    'stdout: SplitParser { onRead: () => root.readProfiles() }' \
    'stdout: SplitParser { onRead: line => { if (line.indexOf("Monitoring signals") === 0) root.readProfiles(); else console.warn("power: control ignored watch line=" + line); } }'
  # Before the mock starts the watch prints that the name has no owner, so
  # the wait is for a line the daemon's start or its first signal causes.
  expected_errors+=('power: control ignored watch line=')
  : >"$power_gdbus_calls"
  rescan "rescan after adding the once fixture answers ok"
  expect "enabling the once fixture is allowed" ok ipc shell setPluginEnabled acme.power-once true
  power_id=acme.power-once
  expect_poll "control: the once fixture reads the absent service" yes power_has_read
  power_start_profiles power-once balanced
  expect_log "control: the once fixture ignores a watch line the started service causes" 1 'power: control ignored watch line=.*(is owned by|PropertiesChanged)'
  expect "control: a service read once is not read after it starts" False power_profile_available
  unset power_id
  expect "disabling the once fixture is allowed" ok ipc shell setPluginEnabled acme.power-once false
  power_move_away "$power_once_dir"
  rescan "rescan after removing the once fixture answers ok"

  power_restore_stand notify-send "$power_notify_stood"
  power_restore_stand gdbus "$power_gdbus_stood"
  power_stop_mocks
  stop_shell || fail "power: the shell stops after UPower mocks"
  start_shell "$repo" "$sandbox/qs-power-restored.log" || return 0
}

power_main
