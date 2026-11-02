# The power menu, vgs.power's overlay, over the shared inert logind
# transport in scripts/smoke/power-fakes.sh. The row enables Power with
# Log out, Suspend, Reboot and Shut down offered, reads the Settings Keys
# row of the unbound `power-menu` shortcut, opens the menu through that
# shortcut, and drives it on the nested seat: the keyboard selection, a
# hold with nothing selected, a release before 2 s, a release with Shift
# down, a full key hold, Escape and focus loss during a hold, a pointer hold and
# its early release, a press beside the card held across the deadline,
# opening from the launcher's System > Power menu row, and a full hold with
# Motion off. Each action runs `vgshell power <verb>`; the row's
# `vgshell` is a stand-in that records its argv and exits with the status
# its file holds, so no action reaches the host. A failed run and a
# refused request each send Power's notice through a recording
# notify-send. The row ends with Power disabled and its menu gone.
#
# The hold is 2000 ms. A full hold here lasts 2.4 s and an early release
# 1.5 s, and the row then waits 2.5 s with no run, past the deadline the
# early press would have had. Those margins are not latencies; the exact
# threshold is proved over injected time in scripts/test-power-logic.js.
# Run lists poll every 0.2 s (expect_poll).
# inputs: shell/plugins/vgs.power/* shell/plugins/vgs.launcher/* scripts/smoke/power-fakes.sh scripts/smoke/pointer/* shell/Hosts/SummonLayer.qml shell/Hosts/PluginSlot.qml shell/Core/ShortcutRegistry.qml shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/Core/HyprlandLayer.js shell/Ui/layout/ListCursor.qml shell/Ui/layout/ListCursorRow.qml shell/Ui/layout/ListItem.qml shell/Ui/layout/Pane.qml shell/Ui/foundation/KeyNav.qml shell/Ui/foundation/KeyNavLogic.js shell/Ui/foundation/Scrim.qml shell/Ui/controls/InfoButton.qml shell/Ui/controls/BindField.qml shell/Ui/feedback/KeyHints.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/KeyField.qml shell/Commons/Theme.qml
set -euo pipefail
source "$repo/scripts/smoke/power-fakes.sh"

pm_config="$home/.config/vgshell/shell.json"
pm_runs_file="$sandbox/power-menu.runs"
pm_exit_file="$sandbox/power-menu.exit"
pm_notify_file="$sandbox/power-menu-notify.calls"
pm_pointer_out="$sandbox/power-menu-pointer.out"
pm_pointer_gate="$sandbox/power-menu-pointer.gate"
pm_vgshell_saved=""

pm_read() { ipc smoke readInstance overlay vgs.power "$1"; }
pm_phase() { pm_read hold | py_reply 'import json,sys; t=sys.stdin.read().strip(); print(json.loads(t)["phase"] if t.startswith("{") else t)'; }
pm_offered() { ipc smoke statusValues vgs.power | py_reply 'import json,sys; v=json.load(sys.stdin).get("actions"); print(json.dumps(v["offered"]) if isinstance(v, dict) and v.get("state") == "ready" else json.dumps(v))'; }
# The verbs the stand-in ran, one `vgshell power <verb>` each.
pm_runs() { [[ -s $pm_runs_file ]] || { echo '[]'; return; }; py_reply 'import json,sys; print(json.dumps([r[1] for r in map(json.loads, sys.stdin) if len(r) == 2 and r[0] == "power"]))' <"$pm_runs_file"; }
pm_notices() { [[ -s $pm_notify_file ]] || { echo 0; return; }; py_reply 'import sys; print(sum(1 for line in sys.stdin if line.strip()))' <"$pm_notify_file"; }
pm_keys_row() { ipc smoke itemValues window vgs.settings KeyField pluginId,bind | py_reply 'import json,sys; t=sys.stdin.read(); rows=json.loads(t) if t.startswith("[") else t; print(json.dumps([r["bind"]["key"] for r in rows if r["pluginId"] == "vgs.power" and r["bind"]["shortcut"] == "power-menu"]) if isinstance(rows, list) else rows.strip())'; }
pm_resolves() { [[ $(shell_resolves vgshell) == "$shim/vgshell" ]] && echo stand-in || shell_resolves vgshell; }
# pm_quiet MS: the run list is unchanged for MS ms, sampled every 0.2 s.
pm_quiet() {
  local before deadline
  before="$(pm_runs)" || return 1
  deadline=$(( $(now_ms) + $1 ))
  while (( $(now_ms) < deadline )); do
    [[ $(pm_runs) == "$before" ]] || { pm_runs; return; }
    sleep 0.2
  done
  echo "$before"
}

pm_open() { # LABEL
  expect_poll "$1: no menu is open before the shortcut" 0 layer_count vgs:overlay
  expect "$1: the shortcut opens the menu" ok hypr dispatch 'hl.dsp.global("vgs.power:power-menu")'
  expect_poll "$1: the menu maps" 1 layer_count vgs:overlay
  expect_poll "$1: the menu holds the keyboard" true ipc smoke activeFocusIn overlay vgs.power
  expect_poll "$1: the menu opens with nothing selected" '""' pm_read selected
}
pm_closed() { # LABEL
  expect_poll "$1" 0 layer_count vgs:overlay
  expect_poll "$1: the menu instance is gone" absent pm_read hold
}

# pm_hold_at X Y SECONDS: the primary button held at (X, Y) for SECONDS,
# then released, through the virtual pointer's held drag, which presses,
# prints `holding`, and releases on a line on its stdin.
pm_hold_at() {
  local x="$1" y="$2" pid fd
  coordinate_mode_check || return 1
  nested_input_check "$sandbox/click" || return 1
  power_unlink "$pm_pointer_gate"
  mkfifo -- "$pm_pointer_gate"
  : >"$pm_pointer_out"
  "${shell_env[@]}" "$sandbox/click" "$x" "$y" "$mon_w" "$mon_h" drag "$x" "$y" hold <"$pm_pointer_gate" >"$pm_pointer_out" &
  pid=$!
  exec {fd}>"$pm_pointer_gate"
  local deadline=$(( $(now_ms) + 5000 ))
  until grep -q '^holding' "$pm_pointer_out"; do
    (( $(now_ms) < deadline )) || { exec {fd}>&-; wait "$pid" || true; return 1; }
    sleep 0.05
  done
  sleep "$3"
  printf '\n' >&"$fd"
  exec {fd}>&-
  wait "$pid"
}
# pm_pointer_hold ROW SECONDS: pm_hold_at on ROW's title.
pm_pointer_hold() {
  local at x y
  at="$(point_item overlay vgs.power ListItem "$1")" || return 1
  read -r x y <<<"$at" || return 1
  pm_hold_at "$x" "$y" "$2"
}
pm_launcher_first() { ipc smoke launcherRows overlay vgs.launcher | py_reply 'import json,sys; t=sys.stdin.read(); r=json.loads(t) if t.startswith("[") else []; print(r[0][1] if r else t.strip())'; }

pm_restore() {
  ipc shell hide overlay vgs.power >/dev/null || true
  ipc shell setPluginEnabled vgs.launcher false >/dev/null || true
  ipc shell setPluginEnabled vgs.power false >/dev/null || true
  power_logind_stop || true
  power_restore_stand notify-send "$power_notify_stood" || true
  power_unlink "$shim/vgshell"
  if [[ -n $pm_vgshell_saved ]]; then mv -- "$pm_vgshell_saved" "$shim/vgshell"; fi
  cp -- "$sandbox/power-menu-config.json" "$pm_config.power-menu"
  mv -T -- "$pm_config.power-menu" "$pm_config"
  ipc shell reloadConfig >/dev/null || true
}

pm_main() {
  local pm_log_from
  pm_log_from="$(stat -c %s -- "$instance_log")"
  cp -- "$pm_config" "$sandbox/power-menu-config.json"
  power_logind_start
  smoke_row_abandon=(pm_restore)
  printf 'yes\n' >"$power_sleep_replies/CanReboot"
  printf 'yes\n' >"$power_sleep_replies/CanPowerOff"
  printf '2\n' >"$power_sleep_replies/Display"
  : >"$pm_runs_file"
  printf '0\n' >"$pm_exit_file"
  if [[ -e $shim/vgshell ]]; then
    pm_vgshell_saved="$sandbox/power-menu-vgshell.saved"
    mv -- "$shim/vgshell" "$pm_vgshell_saved"
  fi
  cat >"$shim/vgshell" <<EOF_VGSHELL
#!/usr/bin/env bash
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "\$@" >>"$pm_runs_file"
exit "\$(cat "$pm_exit_file")"
EOF_VGSHELL
  chmod 755 "$shim/vgshell"
  : >"$pm_notify_file"
  power_stand notify-send <<EOF_STAND
#!/usr/bin/env bash
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "\$@" >>"$pm_notify_file"
EOF_STAND
  expect "the shell runs the recording vgshell" stand-in pm_resolves

  expect "Power enables over the inert transports" ok ipc shell setPluginEnabled vgs.power true
  expect_poll "Power offers what the stand-ins allow, and no Switch user without a seat" '["logout", "suspend", "reboot", "poweroff"]' pm_offered
  printf 'yes\n' >"$power_sleep_replies/CanHibernate"
  expect "Power reads the offers again" '' ipc smoke invokeInstance service vgs.power readSleepActions ''
  expect_poll "a yes from CanHibernate offers Hibernate" '["logout", "suspend", "hibernate", "reboot", "poweroff"]' pm_offered
  printf 'no\n' >"$power_sleep_replies/CanHibernate"
  : >"$power_sleep_replies/Display"
  expect "Power reads the offers without a session" '' ipc smoke invokeInstance service vgs.power readSleepActions ''
  expect_poll "no graphical session offers no Log out" '["suspend", "reboot", "poweroff"]' pm_offered
  printf '2\n' >"$power_sleep_replies/Display"
  expect "Power reads the session again" '' ipc smoke invokeInstance service vgs.power readSleepActions ''
  expect_poll "the session offers Log out again" '["logout", "suspend", "reboot", "poweroff"]' pm_offered

  expect "Settings opens Power's page" ok ipc shell summon window vgs.settings '{"plugin":"vgs.power","tab":"Settings"}'
  expect_poll "Settings draws the power menu's Keys row, unbound" '[null]' pm_keys_row
  expect "Settings closes" ok ipc shell hide window vgs.settings

  pm_open "keyboard"
  expect "the power menu carries no info control" '[]' ipc smoke itemValues overlay vgs.power InfoButton infoOpen
  type_keys -P space -s 2400 -p space || fail "the hold with nothing selected failed to type"
  expect "a hold with nothing selected runs nothing" '[]' pm_runs
  type_keys -k Down || fail "Down failed"
  expect_poll "the first Down selects the first action" '"logout"' pm_read selected
  type_keys -k End || fail "End failed"
  expect_poll "End selects the last action" '"poweroff"' pm_read selected
  type_keys -k Up || fail "Up failed"
  expect_poll "Up selects Reboot" '"reboot"' pm_read selected
  expect "moving the selection runs nothing" '[]' pm_runs
  type_keys -P space -s 1500 -p space || fail "the early release failed to type"
  expect_poll "the early release ends the hold" idle pm_phase
  expect "a release at 1.5 s runs nothing past the deadline" '[]' pm_quiet 2500
  type_keys -P space -s 500 -M shift -s 300 -p space -s 300 -m shift || fail "the release under Shift failed to type"
  expect_poll "a release with Shift down ends the hold" idle pm_phase
  expect "a release with Shift down runs nothing past the deadline" '[]' pm_quiet 3400
  type_keys -P space -s 2400 -p space || fail "the full hold failed to type"
  expect_poll "a 2 s hold of Space runs Reboot once" '["reboot"]' pm_runs
  pm_closed "the accepted run closes the menu"
  expect "the closed menu runs nothing more" '["reboot"]' pm_quiet 1000

  : >"$pm_runs_file"
  pm_open "escape"
  type_keys -k Down -P Return -s 1000 -k Escape -s 2500 -p Return || fail "Escape during a hold failed to type"
  pm_closed "Escape during a hold closes the menu"
  expect "Escape during a hold runs nothing" '[]' pm_quiet 1000

  pm_open "focus"
  type_keys -k Down -P Return -s 4200 -p Return &
  local pm_focus_pid=$!
  expect_poll "the focus-loss check starts a key hold" holding pm_phase
  expect "focus moves off the action list" focused ipc smoke invokeInstance overlay vgs.power focusInstance ''
  expect_poll "leaving the action list cancels the hold" idle pm_phase
  wait "$pm_focus_pid" || fail "the hold during a focus move failed to type"
  expect "moving focus during a hold runs nothing" '[]' pm_quiet 1000
  expect "the menu stays open after focus moves" 1 layer_count vgs:overlay
  type_keys -k Escape || fail "Escape failed"
  pm_closed "Escape closes the menu"

  pm_open "pointer"
  pm_pointer_hold Suspend 1.2 || fail "the short pointer hold failed"
  expect_poll "a pointer press selects its row" '"suspend"' pm_read selected
  expect "a 1.2 s pointer hold runs nothing past the deadline" '[]' pm_quiet 2500
  pm_pointer_hold Suspend 2.4 || fail "the full pointer hold failed"
  expect_poll "a 2 s pointer hold runs Suspend once" '["suspend"]' pm_runs
  pm_closed "the pointer's run closes the menu"

  # A press beside the card during a key hold ends the hold at the press,
  # though the button is released only after the deadline.
  pm_open "outside press"
  type_keys -k Down || fail "Down failed"
  type_keys -P space -s 4200 -p space &
  local pm_keys_pid=$!
  sleep 0.8
  pm_hold_at 200 "$((mon_h / 2))" 3 || fail "the press beside the card failed"
  wait "$pm_keys_pid" || fail "the key hold beside the press failed to type"
  pm_closed "a press beside the card closes the menu"
  expect "a press beside the card during a hold runs nothing" '["suspend"]' pm_quiet 1000
  # The same with the secondary button: its press closes the menu. The
  # virtual pointer holds only the primary button, so this press is a
  # click, made 0.8 s into a hold that is released after the deadline.
  pm_open "outside right press"
  type_keys -k Down || fail "Down failed"
  type_keys -P space -s 4200 -p space &
  pm_keys_pid=$!
  sleep 0.8
  right_click 200 "$((mon_h / 2))" || fail "the right press beside the card failed"
  pm_closed "a right press beside the card closes the menu"
  wait "$pm_keys_pid" || fail "the key hold beside the right press failed to type"
  expect "a right press beside the card during a hold runs nothing" '["suspend"]' pm_quiet 1000

  # The launcher's System > Power menu row opens the menu while the
  # launcher fades out; the menu keeps the keyboard as the pointer moves.
  expect "the launcher enables" ok ipc shell setPluginEnabled vgs.launcher true
  expect "the launcher opens on Power menu" ok ipc shell summon overlay vgs.launcher '{"menu":"system","query":"Power menu"}'
  expect_poll "the launcher lists Power menu first" "Power menu" pm_launcher_first
  expect_poll "the launcher holds the keyboard" true ipc smoke activeFocusIn overlay vgs.launcher
  type_keys -k Return || fail "picking Power menu failed"
  expect_poll "the launcher's row opens the menu with the keyboard" true ipc smoke activeFocusIn overlay vgs.power
  expect_poll "the launcher closes" absent ipc smoke readInstance overlay vgs.launcher opened
  hover 300 300 || fail "moving the pointer failed"
  hover 320 340 || fail "moving the pointer failed"
  expect "the menu stays mapped after the launcher closes" 1 layer_count vgs:overlay
  expect "the menu keeps the keyboard after the launcher closes" true ipc smoke activeFocusIn overlay vgs.power
  type_keys -k Escape || fail "Escape failed"
  pm_closed "Escape closes the menu from the launcher"
  expect "the launcher disables" ok ipc shell setPluginEnabled vgs.launcher false

  # A run the route fails leaves the menu closed and sends Power's notice.
  : >"$pm_runs_file"
  printf '1\n' >"$pm_exit_file"
  expected_errors+=('power: action argv=\["vgshell","power","logout"\] exit=1' 'power: action refused: action=switch-user reason=unavailable')
  pm_open "failure"
  type_keys -k Home -P space -s 2400 -p space || fail "the failing hold failed to type"
  expect_poll "the failing hold runs Log out once" '["logout"]' pm_runs
  pm_closed "the failing run's menu closes"
  expect_poll "a failed run sends one notice" 1 pm_notices
  printf '0\n' >"$pm_exit_file"
  expect "a request for an action not offered is refused" 'refused: action=switch-user reason=unavailable' ipc vgs.power invoke action switch-user
  expect_poll "a refused request sends a notice" 2 pm_notices
  expect "a refused request runs nothing" '["logout"]' pm_runs

  # Motion off stills the entrance; the hold stays 2000 ms.
  : >"$pm_runs_file"
  python3 - "$pm_config" <<'PY_MOTION'
import json, os, sys
path = sys.argv[1]
with open(path) as source:
    config = json.load(source)
config.setdefault("appearance", {})["motion"] = False
with open(path + ".next", "w") as out:
    json.dump(config, out)
os.replace(path + ".next", path)
PY_MOTION
  expect "Motion off reloads" ok ipc shell reloadConfig
  expect_poll "Motion off settles" true ipc smoke configSettled
  pm_open "motion off"
  type_keys -k Down -P space -s 1500 -p space || fail "the early hold with Motion off failed to type"
  expect "a release at 1.5 s with Motion off runs nothing" '[]' pm_quiet 1500
  type_keys -P space -s 2400 -p space || fail "the full hold with Motion off failed to type"
  expect_poll "a 2 s hold with Motion off runs Log out once" '["logout"]' pm_runs
  pm_closed "the Motion-off run closes the menu"

  pm_restore
  smoke_row_abandon=()
  expect_poll "Power releases its service" False record_exists vgs.power
  expect_poll "the row restores Power disabled" False plugin_enabled vgs.power
  tail -c "+$((pm_log_from + 1))" -- "$instance_log" >"$sandbox/power-menu-row.log"
  check_unexpected_log "the shell's log over the power menu row" "$sandbox/power-menu-row.log"
}
pm_main
