# The restart notice, for a shell whose own files changed under it. Runs
# after rows/hyprland-consent.sh, a core row, has answered the first-start
# welcome, so the consent slot holds no notice of its own here. The
# fixture acme.drift's panel draws a sibling file, Mark.qml, which the row
# rewrites. Control first, with the sandbox copy's core as the shell
# started over it: Mark.qml names a type no core has, the summon is refused
# build-failed and no restart notice is owed. Then the sandbox copy's
# qs.Ui gains a type, DriftMark, the running engine never read, and
# Mark.qml names it: the rescan publishes the plugin, its build fails, and
# the summon is refused with the one restart notice drawn, Restart and Not
# now, its command only behind Show command. Escape closes it. Second
# control, over the changed core: a panel whose root the host cannot take
# is refused build-failed and owes no notice, since the engine loaded its
# files. With the panel as it was the load fails and owes the notice
# again, and after Escape so does one more summon, which the recorded
# failure refuses with no new build. Return on Restart runs `vgsh restart` from inside the shell: the
# row presses it only once it has read that the shell which draws the
# notice runs in the sandbox's runtime directory and is the pid the
# sandbox's instance lock names, so the restart reaches no other shell.
# The relaunched shell, which read DriftMark at its start, summons the same
# panel and owes no notice. The row then removes the fixture and the type
# and starts the sandbox's tree again, so the rows after it run over the
# core their shell started with.
# inputs: scripts/smoke/fixtures/plugins/acme.drift/* bin/vgsh-scan bin/vgsh shell/Core/Registry.qml shell/Core/Plugins.qml shell/Core/Notices.qml shell/Hosts/NoticeHost.qml shell/Ui/qmldir scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail
drift="$home/.config/vgs/plugins/acme.drift"
drift_qmldir="$repo/shell/Ui/qmldir"
drift_type="$repo/shell/Ui/DriftMark.qml"
drift_owed() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["notices"]["restart"]))'; }
drift_drawn() { ipc smoke noticeDrawn | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d[sys.argv[1]]))' "$1"; }
# `sandboxed` when the shell the row addresses has the sandbox's runtime
# directory in its environment and is the pid the sandbox's lock names.
drift_sandboxed() {
  local held
  grep -q -z -x -F -e "XDG_RUNTIME_DIR=$rt_dir" -- "/proc/$shell_qs_pid/environ" || { echo "runtime-dir=other"; return; }
  IFS= read -r held <"$rt_dir/vgsh.lock" || held=""
  if [[ $held == "$shell_qs_pid" ]]; then echo sandboxed; else echo "lock=[$held] shell=$shell_qs_pid"; fi
}
# The live pid the sandbox's lock names once it is no longer OLD_PID, the
# relaunched shell's, else `none`.
drift_relaunched() { # OLD_PID
  local pid
  if IFS= read -r pid 2>/dev/null <"$rt_dir/vgsh.lock" && [[ $pid =~ ^[0-9]+$ && $pid != "$1" && -d /proc/$pid ]]; then echo "$pid"; else echo none; fi
}

[[ $shell_tree == "$repo" ]] || fail "the row needs the sandbox's own tree as the running shell, found $shell_tree"
install_plugin_copy acme.drift acme.drift Drift
expected_errors+=('plugins: acme\.drift failed to load: ' 'plugins: acme\.drift panel not built: ')
rescan "rescan after adding the drift fixture answers ok"
expect_poll "the drift fixture is discovered" True plugin_known acme.drift
expect "enabling the drift fixture is allowed" ok ipc shell setPluginEnabled acme.drift true
expect "the panel summons before anything changes" ok ipc shell summon panel acme.drift '{}'
expect "the panel hides" ok ipc shell hide panel acme.drift

# Control: the plugin's own defect, over an unchanged core. The summon
# raises the notice before it replies, so the reading after it is final.
printf 'import QtQuick\nimport qs.Ui\nDriftAbsent {}\n' >"$drift/Mark.qml"
rescan "rescan after the plugin took a type no core has answers ok"
expect "control: the summon of the plugin's own defect is refused" "refused: build-failed=acme.drift" ipc shell summon panel acme.drift '{}'
expect_log "control: the core logged the failed build" 1 'plugins: acme\.drift failed to load: .*Type Mark unavailable'
expect "control: a build failure over an unchanged core owes no restart notice" false drift_owed
expect "control: no notice is drawn" absent ipc smoke noticeDrawn

# The core changes under the running shell, and the plugin takes the new type.
cp -- "$drift_qmldir" "$sandbox/core-drift-qmldir.orig"
printf 'import QtQuick\nItem {\n    width: 20\n    height: 20\n}\n' >"$drift_type"
printf 'DriftMark 1.0 DriftMark.qml\n' >>"$drift_qmldir"
printf 'import QtQuick\nimport qs.Ui\nDriftMark {}\n' >"$drift/Mark.qml"
rescan "rescan after the core and the plugin took the new type answers ok"
expect "the summon of a plugin that needs the newer core is refused" "refused: build-failed=acme.drift" ipc shell summon panel acme.drift '{}'
expect_log "the core logged both failed builds" 2 'plugins: acme\.drift failed to load: .*Type Mark unavailable'
expect "a build failure over a changed core owes the restart notice" true drift_owed
expect_poll "the restart notice is the one notice surface" 1 layer_count vgs:notice
expect_poll "the restart notice names the fix" '"Restart VGS to finish the update"' drift_drawn title
expect "the restart notice offers Restart and Not now" '["Restart", "Not now"]' drift_drawn actions
expect "the command Restart runs is behind Show command, closed" '{"toggle": "Show command", "expanded": false, "text": "vgsh restart"}' drift_drawn command
expect "no row of the notice's body draws a command" '[]' drift_drawn rows
type_keys -k Escape || fail "sending Escape to the restart notice failed"
expect_poll "Escape closes the restart notice" false drift_owed
expect_poll "the closed restart notice leaves no surface" 0 layer_count vgs:notice

# Control over the changed core: the engine loads the panel, and the host
# cannot take its root.
printf 'import QtQuick\nQtObject { property var shell: null }\n' >"$drift/Panel.qml"
rescan "rescan after the panel took a root the host cannot take answers ok"
expect "control: the summon of a root the host cannot take is refused" "refused: build-failed=acme.drift" ipc shell summon panel acme.drift '{}'
expect_log "control: the core logged the root it could not take" 1 'plugins: acme\.drift panel not built: entry point must be an Item'
expect "control: a build the engine loaded owes no restart notice over a changed core" false drift_owed
expect "control: no notice surface is left" 0 layer_count vgs:notice
cp -- "$repo/scripts/smoke/fixtures/plugins/acme.drift/Panel.qml" "$drift/Panel.qml"
rescan "rescan after the panel came back answers ok"
expect "the summon of the panel that needs the newer core is refused again" "refused: build-failed=acme.drift" ipc shell summon panel acme.drift '{}'
expect "the failed load owes the restart notice again" true drift_owed
type_keys -k Escape || fail "sending Escape to the second restart notice failed"
expect_poll "Escape closes the second restart notice" false drift_owed
expect "one more summon is refused on the recorded failure" "refused: build-failed=acme.drift" ipc shell summon panel acme.drift '{}'
expect "that summon built nothing again" 3 log_lines 'plugins: acme\.drift failed to load: '
expect "that summon owes the restart notice again" true drift_owed
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
  ok "the shell that draws the notice is the sandbox's"
  type_keys -k Return || fail "sending Return to Restart failed"
  for _ in $(seq 1 $((timeout_s * 5))); do
    drift_new="$(drift_relaunched "$drift_old")"
    [[ $drift_new == none ]] || break
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
    expect "the relaunched shell owes no restart notice" false drift_owed
    expect "the panel hides after the restart" ok ipc shell hide panel acme.drift
  fi
elif [[ $drift_where == sandboxed ]]; then
  fail "Restart brought no new shell within ${timeout_s}s: the lock names [$(cat -- "$rt_dir/vgsh.lock" 2>/dev/null)]"
fi

# The fixture and the type go, and the sandbox's tree starts again over
# the core as it was.
expect "disabling the drift fixture is allowed" ok ipc shell setPluginEnabled acme.drift false
rm -rf -- "${drift:?}"
cp -- "$sandbox/core-drift-qmldir.orig" "$drift_qmldir"
rm -f -- "${drift_type:?}"
if stop_shell && start_shell "$repo" "$sandbox/core-drift-qs.log"; then
  expect "the shell started again owes no restart notice" false drift_owed
fi
