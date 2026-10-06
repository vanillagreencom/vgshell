# vgs.power over the sandbox's device fakes: python-dbusmock's upower
# template and upower_power_profiles_daemon template run on the sandbox
# system bus. The row starts them before it restarts the shell, because
# Quickshell's UPower and PowerProfiles singletons connect once when first
# read. The smoke set disables vgs.power, so the row starts the mocks and
# then enables the plugin for the first time in this shell. The row drives
# the mocks through their D-Bus interfaces with
# shell_env, so no call reaches the host's UPower, power-profiles-daemon,
# battery, charger or system bus. A notify-send stand-in records battery
# notices and a powerprofilesctl stand-in satisfies the requirement probe;
# the plugin never runs powerprofilesctl.
#
# Rows: the first enable sees a discharging battery and a power-saver
# profile without applying the remembered battery profile; the widget draws
# the 51 % text and a non-charging icon; with a charging display battery,
# it draws the charging icon; one discharge sends one low and one critical
# alert, no repeats below the same thresholds; keyboard selection in the
# panel chooses Performance and writes the current source setting; a plug
# change applies the remembered charger profile; and removing the display
# battery hides the widget's battery part again. Controls build fixture
# copies at run time: acme.power-relatch sends low twice in one discharge,
# and acme.power-nocharge draws no charging icon while the service
# publishes charging. Polls use expect_poll's 25 reads 0.2 s apart.
# The row disables vgs.power, starts the mocks, then restarts the shell
# before the first enable, so Quickshell's connect-once UPower and
# PowerProfiles singletons bind to the mocks no matter what earlier rows
# left. The row restores notify-send, powerprofilesctl, vgs.power's
# enablement and placement, moves fixture copies out of the plugin
# directory, stops the mock process groups it spawned, and restarts the
# shell because Quickshell keeps those singletons in the process after the
# plugin is disabled.
# inputs: shell/plugins/vgs.power/* shell/Core/Capabilities.qml shell/Core/PluginStatus.qml shell/Core/PluginLogic.js shell/Hosts/SummonHost.qml scripts/smoke/rows/device-fakes.sh scripts/smoke/power-fakes.sh
set -euo pipefail
source "$repo/scripts/smoke/power-fakes.sh"

power_upower_pid=""
power_profiles_pid=""
power_notify_stood=""
power_profilesctl_stood=""
power_gdbus_stood=""
power_was_enabled=""
power_was_placed=""
power_relatch_dir="$home/.config/vgshell/plugins/acme.power-relatch"
power_nocharge_dir="$home/.config/vgshell/plugins/acme.power-nocharge"
power_notify_calls="$sandbox/power-notify-send.calls"
power_moved_count=0
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
      powerprofilesctl) power_profilesctl_stood=yes ;;
      gdbus) power_gdbus_stood=yes ;;
    esac
    sentinel_stand_over "$shim/$name"
  else
    case "$name" in
      notify-send) power_notify_stood=no ;;
      powerprofilesctl) power_profilesctl_stood=no ;;
      gdbus) power_gdbus_stood=no ;;
    esac
    cat >"$shim/$name" && chmod 755 "$shim/$name"
  fi
}

power_restore_stand() {
  if [[ $2 == yes ]]; then sentinel_restore "$shim/$1"; else power_unlink "$shim/$1"; fi
}

power_widget() { ipc smoke readInstance "$(bar_key)" "${power_id:-vgs.power}" "$1"; }
power_status() { ipc smoke statusValues "${power_id:-vgs.power}" | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get("power"), sort_keys=True, separators=(",", ":")))'; }
power_status_charging() { power_status | py_reply 'import json,sys; print(json.load(sys.stdin)["battery"]["charging"])'; }
power_status_dump() { power_status; }
power_notify_count() { [[ -f $power_notify_calls ]] && wc -l <"$power_notify_calls" || echo 0; }
power_notify_delta() { local n; n="$(power_notify_count)" || return; echo $((n - power_notify_base)); }
power_notify_delta_over_one() { local n; n="$(power_notify_delta)" || return; [[ $n -gt 1 ]] && echo yes || echo "no $n"; }
power_notify_urgencies() { [[ -f $power_notify_calls ]] && py_reply 'import json,sys; print(json.dumps([a for line in sys.stdin for a in json.loads(line) if a.startswith("--urgency=")]))' <"$power_notify_calls" || echo '[]'; }
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
power_install_fixture() { # ID DIR FILE OLD NEW
  local id="$1" dir="$2"
  shift 2
  power_move_away "$dir"
  cp -R -- "$repo/shell/plugins/vgs.power" "$dir"
  python3 - "$id" "$dir" "$@" <<'PY_MUTANT'
import json, os, sys
plugin, root, file_name, old, new = sys.argv[1:]
manifest = os.path.join(root, "manifest.json")
doc = json.load(open(manifest))
doc["id"] = plugin
doc["name"] = plugin
json.dump(doc, open(manifest, "w"), indent=2)
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
  power_stand powerprofilesctl <<'EOF_STAND'
#!/usr/bin/env bash
exit 0
EOF_STAND
  power_stand gdbus <<EOF_STAND
#!/usr/bin/env bash
exec env DBUS_SYSTEM_BUS_ADDRESS="$rt_dir/system-bus" $(command -v gdbus) "\$@"
EOF_STAND

  expect "disabling vgs.power before the UPower restart is allowed" ok ipc shell setPluginEnabled vgs.power false
  power_start_mocks power power-saver
  expect "the mock starts with a discharging battery object" "/org/freedesktop/UPower/devices/mock_BAT0" power_add_battery
  power_discharging 51.0 5400
  stop_shell || fail "power: the shell stops before the UPower restart"
  start_shell "$repo" "$sandbox/qs-power.log" || return 0
  rescan "rescan after adding power stand-ins answers ok"
  expect "enabling vgs.power is allowed" ok ipc shell setPluginEnabled vgs.power true
  expect "placing vgs.power in the bar is allowed" ok ipc shell setPluginPlaced vgs.power true
  expect_poll "the Power service publishes the initial discharging battery" 51 power_level
  expect_poll "the Power service reports profiles available" True power_profile_available
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

  expect "the Power panel opens" ok ipc shell summon panel vgs.power '{}'
  expect_poll "the Power panel focuses the profile control" true ipc smoke activeFocusIn panel vgs.power
  type_keys -k Right || fail "typing Right in the Power panel failed"
  expect_poll "the panel keyboard path chooses Performance" performance power_profile_get
  expect_poll "choosing Performance remembers the battery profile" '"performance"' power_setting batteryProfile
  power_profile_set_mock balanced
  expect_poll "the mock profile was reset to balanced" balanced power_profile_get
  power_on_battery false
  expect_poll "plugging in applies the remembered charger profile" performance power_profile_get
  expect "the Power panel closes" ok ipc shell hide panel vgs.power

  power_no_battery
  expect_poll "removing the display battery hides the widget battery text" '[[], []]' power_texts
  expect_poll "removing the display battery leaves the profile icon" '["zap"]' power_icons

  expect "disabling vgs.power for controls is allowed" ok ipc shell setPluginEnabled vgs.power false
  power_install_fixture acme.power-relatch "$power_relatch_dir" PowerLogic.js \
    'if (!next.low) out.push({ threshold: "low", urgency: "normal", level: n });
        next.low = true;' \
    'if (!next.low) out.push({ threshold: "low", urgency: "normal", level: n });
        next.low = false;'
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
  expect "re-enabling vgs.power without the profile daemon starts clean" ok ipc shell setPluginEnabled vgs.power true
  expect_poll "without the profile daemon the service reports profiles unavailable" False power_profile_available
  expect "the unavailable profile panel opens" ok ipc shell summon panel vgs.power '{}'
  expect_poll "the unavailable profile panel says profiles are unavailable" True power_label_has "Power profiles are not available."
  expect "the unavailable profile panel closes" ok ipc shell hide panel vgs.power
  expect "disabling vgs.power after the unavailable check is allowed" ok ipc shell setPluginEnabled vgs.power false

  power_restore_stand notify-send "$power_notify_stood"
  power_restore_stand powerprofilesctl "$power_profilesctl_stood"
  power_restore_stand gdbus "$power_gdbus_stood"
  power_stop_mocks
  stop_shell || fail "power: the shell stops after UPower mocks"
  start_shell "$repo" "$sandbox/qs-power-restored.log" || return 0
}

power_main
