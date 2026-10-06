# The restart notice, for a shell whose own files changed under it. Runs
# after rows/hyprland-consent.sh, a core row, has answered the first-start
# welcome, so the consent slot holds no notice of its own here. The row
# compiles acme.drift before the core changes and leaves acme.drift-b
# unbuilt. The core watcher sees the sandbox copy's qs.Ui/qmldir
# modification, while the new DriftMark.qml file alone would not count,
# and raises Restart to update without a plugin rescan. A rescan after that
# change holds the manifest map, so the open panel keeps its old snapshot
# and the unbuilt copy is refused with `refused: restart=owed`, not built
# against the changed core; the notice that refusal owes waits while a
# floating TUI run is live and shows once it ends. Restart is pressed only after the row proves
# the notice belongs to the sandbox shell. The relaunched shell then builds
# both panels from the changed core. Cleanup removes the fixtures and type
# and starts the sandbox tree again.
# inputs: scripts/smoke/fixtures/plugins/acme.drift/* bin/vgshell-scan bin/vgshell shell/Core/Registry.qml shell/Core/Plugins.qml shell/Core/Notices.qml shell/Hosts/NoticeHost.qml shell/Core/TuiRunner.qml shell/Hosts/PluginSlot.qml shell/Hosts/SummonHost.qml shell/Ui/qmldir scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail
drift="$home/.config/vgshell/plugins/acme.drift"
drift_b="$home/.config/vgshell/plugins/acme.drift-b"
drift_qmldir="$repo/shell/Ui/qmldir"
drift_type="$repo/shell/Ui/DriftMark.qml"
drift_owed() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["notices"]["restart"]))'; }
drift_drawn() { ipc smoke noticeDrawn | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d[sys.argv[1]]))' "$1"; }
drift_revision() { ipc shell listPlugins | py_reply 'import json,sys; rows=[p["revision"] for p in json.load(sys.stdin)["plugins"] if p["id"] == sys.argv[1]]; print(rows[0] if rows else "absent")' "$1"; }
# `sandboxed` when the shell the row addresses has the sandbox's runtime
# directory in its environment and is the pid the sandbox's lock names.
drift_sandboxed() {
  local held
  grep -q -z -x -F -e "XDG_RUNTIME_DIR=$rt_dir" -- "/proc/$shell_qs_pid/environ" || { echo "runtime-dir=other"; return; }
  IFS= read -r held <"$rt_dir/vgshell.lock" || held=""
  if [[ $held == "$shell_qs_pid" ]]; then echo sandboxed; else echo "lock=[$held] shell=$shell_qs_pid"; fi
}
# The live pid the sandbox's lock names once it is no longer OLD_PID, the
# relaunched shell's, else `none`.
drift_relaunched() { # OLD_PID
  local pid
  if IFS= read -r pid 2>/dev/null <"$rt_dir/vgshell.lock" && [[ $pid =~ ^[0-9]+$ && $pid != "$1" && -d /proc/$pid ]]; then echo "$pid"; else echo none; fi
}
drift_relaunch_deadline_ms=120000

[[ $shell_tree == "$repo" ]] || fail "the row needs the sandbox's own tree as the running shell, found $shell_tree"
install_plugin_copy acme.drift acme.drift Drift
install_plugin_copy acme.drift acme.drift-b DriftB
expected_errors+=('plugins: acme\.drift failed to load: ')
rescan "rescan after adding the drift fixtures answers ok"
expect_poll "the drift fixture is discovered" True plugin_known acme.drift
expect_poll "the second drift fixture is discovered" True plugin_known acme.drift-b
expect "enabling the drift fixture is allowed" ok ipc shell setPluginEnabled acme.drift true
expect "enabling the second drift fixture is allowed" ok ipc shell setPluginEnabled acme.drift-b true
expect "the panel summons before anything changes" ok ipc shell summon panel acme.drift '{}'
expect "the panel hides" ok ipc shell hide panel acme.drift

# Acceptance: a plugin-only change over an unchanged core still hot-loads.
# Must-fail control: the same kind of plugin change after coreChanged is
# held below, where the listed revision must not move and `scan held` must
# be logged.
drift_before="$(drift_revision acme.drift)"
printf 'import QtQuick\nItem { width: 24; height: 24 }\n' >"$drift/Mark.qml"
rescan "rescan after a plugin-only drift change answers ok"
drift_after="$(drift_revision acme.drift)"
if [[ $drift_after != "$drift_before" && $drift_after != absent ]]; then ok "the plugin-only change publishes a new revision"; else fail "the plugin-only change did not publish a new revision: before=$drift_before after=$drift_after"; fi
expect "the changed plugin revision summons without restart debt" ok ipc shell summon panel acme.drift '{}'
expect "the changed plugin revision hides" ok ipc shell hide panel acme.drift
expect "the plugin-only change owes no restart notice" false drift_owed

# Must-fail control for the log reader and unchanged-core notice rule: a
# real plugin load failure increments the failed-load count, refuses the
# summon, and still owes no restart.
loads_before="$(log_lines 'plugins: acme\.drift failed to load: ')" || fail "the instance log is unreadable before the defect control"
printf 'import QtQuick\nimport qs.Ui\nDriftAbsent {}\n' >"$drift/Mark.qml"
rescan "rescan after the plugin took a type no core has answers ok"
expect "control: the summon of the plugin's own defect is refused" "refused: build-failed=acme.drift" ipc shell summon panel acme.drift '{}'
expect_log "control: the core logged the failed build" "$((loads_before + 1))" 'plugins: acme\.drift failed to load: '
expect "control: a build failure over an unchanged core owes no restart notice" false drift_owed
expect "control: no notice is drawn" absent ipc smoke noticeDrawn
printf 'import QtQuick\nItem { width: 28; height: 28 }\n' >"$drift/Mark.qml"
rescan "rescan after the plugin defect is restored answers ok"
drift_open_revision="$(drift_revision acme.drift)"
expect "the restored panel summons and stays open" ok ipc shell summon panel acme.drift '{}'
expect "the restored panel has a live build record" True record_exists acme.drift

# Acceptance: the core watcher raises restart debt with no rescan. If the
# watcher is broken, this poll never sees the notice.
owed_logs="$(log_lines 'notices: restart=owed')" || fail "the instance log is unreadable before the core change"
loads_after_control="$(log_lines 'plugins: acme\.drift failed to load: ')" || fail "the instance log is unreadable after the defect control"
cp -- "$drift_qmldir" "$sandbox/core-drift-qmldir.orig"
printf 'import QtQuick\nItem {\n    width: 20\n    height: 20\n}\n' >"$drift_type"
printf 'DriftMark 1.0 DriftMark.qml\n' >>"$drift_qmldir"
expect_poll "the core watcher raises restart debt without a rescan" true drift_owed
expect "the restart notice was raised once" "$((owed_logs + 1))" log_lines 'notices: restart=owed'
expect_poll "the restart notice is the one notice surface" 1 layer_count vgs:notice
expect_poll "the restart notice names the action" '"Restart to update"' drift_drawn title
expect "the restart notice offers Restart and Not now" '["Restart", "Not now"]' drift_drawn actions
expect "the restart notice draws no Show command row" '[]' drift_drawn rows
expect "no row of the notice's body draws a command" '[]' drift_drawn rows

# Must-fail control for the hot-load acceptance: after coreChanged, a plugin
# source edit is held. The listed revision stays at the open panel's old
# revision, the old instance stays alive, and no load failure is added.
held_before="$(log_lines 'plugins: scan held reason=core-changed')" || fail "the instance log is unreadable before the held scan"
printf 'import QtQuick\nimport qs.Ui\nDriftMark {}\n' >"$drift/Mark.qml"
rescan "rescan after the core changed and the plugin took the new type answers ok"
expect_log "the differing scan is held while restart is owed" "$((held_before + 1))" 'plugins: scan held reason=core-changed'
expect "the held scan leaves the listed plugin revision unchanged" "$drift_open_revision" drift_revision acme.drift
expect "the open panel keeps its live build record" True record_exists acme.drift
expect "the held scan adds no failed load" "$loads_after_control" log_lines 'plugins: acme\.drift failed to load: '
expect "the held scan does not raise the notice again" "$((owed_logs + 1))" log_lines 'notices: restart=owed'

type_keys -k Escape || fail "sending Escape to the restart notice failed"
expect_poll "Escape closes the restart notice" false drift_owed
expect_poll "the closed restart notice leaves no surface" 0 layer_count vgs:notice
expect "the compiled panel hides after restart debt" ok ipc shell hide panel acme.drift
expect "the compiled panel summons again under restart debt" ok ipc shell summon panel acme.drift '{}'
expect "the compiled panel hides again" ok ipc shell hide panel acme.drift

# Acceptance: a never-compiled entry is refused before Qt.createComponent.
# Must-fail control: the unchanged-core defect above proves the failed-load
# counter can move when the engine is allowed to compile. A floating TUI
# run held live meanwhile holds the owed notice back, so it never comes up
# in the middle of a setup flow; it shows once the run ends. The reading
# while the run is live and the one after it are each other's control.
hold_runs
expect "a core TUI opens while the restart notice is closed" ok ipc shell openTui core/doctor
expect_poll "the core TUI's run is live" busy key_idle core/doctor
expect "the never-built panel is refused because restart is owed" "refused: restart=owed" ipc shell summon panel acme.drift-b '{}'
expect "the refused first build adds no failed load" "$loads_after_control" log_lines 'plugins: acme\.drift failed to load: '
expect "the refused first build raises the restart notice again" "$((owed_logs + 2))" log_lines 'notices: restart=owed'
expect "the owed restart notice is held while a TUI run is live" true drift_owed
expect "the held restart notice draws no dialog" absent ipc smoke noticeDrawn
expect "the held restart notice maps no surface" 0 layer_count vgs:notice
release_runs
expect_run_end "the core TUI's run ends" core/doctor
expect_poll "the restart notice is one surface again" 1 layer_count vgs:notice
expect_poll "the restart notice holds the keyboard" true ipc smoke noticeFocused
expect_poll "Restart holds the keyboard first" '"Restart"' drift_drawn focused

# Restart, pressed only on the sandbox's own shell. The runner Hyprland's
# dispatch starts is no child of the harness, so its process group joins
# the teardown's, as in rows/start-order.sh.
drift_old="$shell_qs_pid"
drift_new=none
drift_where="$(drift_sandboxed)" || drift_where=unreadable
if [[ $drift_where == sandboxed ]]; then
  drift_deadline=$(( $(now_ms) + drift_relaunch_deadline_ms ))
  ok "the shell that draws the notice is the sandbox's"
  type_keys -k Return || fail "sending Return to Restart failed"
  while :; do
    drift_new="$(drift_relaunched "$drift_old")"
    [[ $drift_new == none ]] || break
    (( $(now_ms) < drift_deadline )) || break
    sleep 0.2
  done
else
  fail "Restart is not pressed: $drift_where"
  type_keys -k Escape || fail "sending Escape to the unpressed notice failed"
fi
if [[ $drift_new != none ]]; then
  ok "Restart brought a new shell: pid=$drift_new replaced pid=$drift_old"
  shell_pid="$(awk '$1 == "PPid:" { print $2 }' "/proc/$drift_new/status")" || shell_pid=""
  if [[ $shell_pid =~ ^[0-9]+$ ]] && pgid="$(ps -o pgid= -p "$shell_pid")"; then pgids+=("${pgid// /}"); else fail "the relaunched shell's runner is unreadable: [$shell_pid]"; fi
  if shell_answers "$shell_tree" "$shell_log"; then
    expect "the relaunched shell answers as the guarded instance" true ipc shell guarded
    expect "the relaunched shell summons the panel that needs the new type" ok ipc shell summon panel acme.drift '{}'
    expect "the relaunched shell summons the never-built copy" ok ipc shell summon panel acme.drift-b '{}'
    expect "the relaunched shell owes no restart notice" false drift_owed
    expect "the panel hides after the restart" ok ipc shell hide panel acme.drift
    expect "the copy hides after the restart" ok ipc shell hide panel acme.drift-b
  fi
elif [[ $drift_where == sandboxed ]]; then
  fail "Restart brought no live replacement shell before the restart deadline: deadline_ms=$drift_relaunch_deadline_ms lock=[$(cat -- "$rt_dir/vgshell.lock" 2>/dev/null)]"
fi

# The fixtures and the type go, and the sandbox's tree starts again over
# the core as it was.
expect "disabling the drift fixture is allowed" ok ipc shell setPluginEnabled acme.drift false
expect "disabling the second drift fixture is allowed" ok ipc shell setPluginEnabled acme.drift-b false
rm -rf -- "${drift:?}" "${drift_b:?}"
cp -- "$sandbox/core-drift-qmldir.orig" "$drift_qmldir"
rm -f -- "${drift_type:?}"
if stop_shell && start_shell "$repo" "$sandbox/core-drift-qs.log"; then
  expect "the shell started again owes no restart notice" false drift_owed
fi
