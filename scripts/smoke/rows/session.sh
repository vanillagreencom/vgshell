# Shared session observation beside the exclusive lock holder. All reads use
# IPC round-trip polling; this row sets no latency budget.
# scripts/test-session-lock.sh holds the owner's must-fail controls.
# inputs: scripts/smoke/fixtures/plugins/acme.session/* scripts/smoke/fixtures/plugins/acme.probe/* shell/Core/SessionLock.qml shell/Core/Compositor.qml shell/Core/Dispatch.js shell/Core/HyprlandLayer.js scripts/smoke/toplevel/* shell/Commons/SessionLockState.js scripts/smoke/rows/capabilities.sh scripts/smoke/rows/plugins.sh
set -euo pipefail
session_dir="$home/.config/vgshell/plugins/acme.session"
mkdir -p "$session_dir"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.session/." "$session_dir/"
rescan "rescan discovers the session reader"
expect_poll "the session reader is known" True plugin_known acme.session
expect "enable the session reader beside a lock holder" ok ipc shell setPluginEnabled acme.session true
expect_poll "the session reader builds without lock authority" True record_exists acme.session
session_read() { ipc smoke readInstance service acme.session "$1"; }
expect "the reader receives only its declared capabilities" '"ipc,manifest,session,settings"' session_read shellKeys
expect "the lock remains exclusive to its holder" '["acme.probe"]' lent holders.lock
expect "the reader holds session independently" '["acme.session"]' lent holders.session
expect "the reader initially sees an unlocked session" false session_read locked
expect "the unlocked session provider resists writes and authority injection" true ipc acme.session invoke read-only ""
expect "the holder locks for the reader" ok probe lock
expect_poll "the reader binding changes to locked" true session_read locked
expect_poll "the compositor confirms the observed lock" true read_service lockSecure
expect "the locked session provider resists writes" true ipc acme.session invoke read-only ""
expect "unload the holder while its session is locked" ok ipc shell setPluginEnabled acme.probe false
expect_poll "the unloaded holder releases lock authority" null lent holders.lock
expect "the reader stays locked after the holder leaves" true session_read locked
expect "holder unload preserves the lock request" true lent lock.requested
expect "holder unload drops only the lock content" false lent lock.content
expect "restore the holder without replacing the reader" ok ipc shell setPluginEnabled acme.probe true
expect_poll "the restored holder supplies content again" true lent lock.content
expect "the holder unlocks for the reader" ok probe unlock
expect_poll "the reader binding changes back to unlocked" false session_read locked
expect "the same reader observed both transitions" 2 session_read changes
# The fact is confirmed from outputs, then released with its input monitor.
session_power() { # true|false: every nested output has this status
  hypr -j monitors | py_reply 'import json,sys
ms = json.load(sys.stdin)
print(bool(ms) and all(m["dpmsStatus"] is (sys.argv[1] == "true") for m in ms))' "$1"
}
session_blank() {
  expect "$1: the core accepts off" ok probe dispatch "displayPower off"
  expect_poll "$1: every output confirms off" True session_power false
  expect_poll "$1: the session fact confirms off" true session_read displaysOff
}
session_key() {
  type_keys -k Shift_L || fail "$1: the nested wake key could not be sent"
  expect_poll "$1: every output wakes on input" True session_power true
  expect_poll "$1: input clears the session fact" false session_read displaysOff
}
expect "the reader initially sees displays on" false session_read displaysOff
session_blank "display fact"
expect "the off fact is read only" true ipc acme.session invoke read-only ""
session_key "display fact"
session_blank "explicit on"
expect "an explicit on is accepted" ok probe dispatch "displayPower on"
expect_poll "explicit on powers every output" True session_power true
expect_poll "explicit on clears the session fact" false session_read displaysOff

# A valid-looking monitor reply from an unsuccessful transport establishes
# no off fact. The following on must also refuse that failed prerequisite.
cat >"$shim/hyprctl.power-read-failed" <<EOF
#!/usr/bin/env bash
if [[ \${1:-} == -j && \${2:-} == monitors ]]; then
  "$hyprctl_bin" "\$@"
  printf 'read-failed\n' >>"$sandbox/power-read-failed.log"
  exit 1
fi
if [[ \${1:-} == dispatch && \${2:-} == *dpms* ]]; then
  printf '%s\n' "\$2" >>"$sandbox/power-failed-dispatched.log"
fi
exec "$hyprctl_bin" "\$@"
EOF
chmod 755 "$shim/hyprctl.power-read-failed"
: >"$sandbox/power-read-failed.log"
: >"$sandbox/power-failed-dispatched.log"
session_failed_reads() { wc -l <"$sandbox/power-read-failed.log"; }
session_failed_dispatches() { wc -l <"$sandbox/power-failed-dispatched.log"; }
expected_errors+=('ERROR qml: compositor: hyprctl exited 1 for \["hyprctl","-j","monitors"\]' 'ERROR qml: compositor: display-power=transport exit=1 status=0')
shim_hyprctl power-read-failed
expect "off with a failed confirmation read is queued" ok probe dispatch "displayPower off"
expect_poll "failed confirmation read reaches the transport" 1 session_failed_reads
expect "failed confirmation never publishes off" false session_read displaysOff
expect "on with a failed prerequisite read is queued" ok probe dispatch "displayPower on"
expect_poll "failed on prerequisite reaches the transport" 2 session_failed_reads
expect "only the original off reached the dispatcher" 1 session_failed_dispatches
expect "failed on prerequisite leaves the outputs off" True session_power false
shim_hyprctl real
session_key "failed confirmation cleanup"
rm -f -- "${shim:?}/hyprctl.power-read-failed"

# Hyprland's documented idle_inhibit=always rule holds a real inhibitor
# for this nested window (wiki.hypr.land/Configuring/Basics/Window-Rules/).
# Input must clear the fact even while that inhibitor remains held.
hypr_lua_save session-inhibitor
printf '%s\n' 'hl.window_rule({ name = "smoke-session-inhibit", match = { class = "^smoke.session$" }, idle_inhibit = "always" })' >>"$home/.config/hypr/hyprland.lua"
expect "the nested inhibitor rule is installed" ok hypr reload config-only
if open_toplevel "$sandbox/session-inhibitor.log" smoke.session inhibitor; then
  session_inhibitor_pid="$toplevel_pid"
  session_inhibited() {
    hypr -j clients | py_reply 'import json,sys
print(any(c["class"] == "smoke.session" and c["inhibitingIdle"] for c in json.load(sys.stdin)))'
  }
  expect_poll "the nested window holds its idle inhibitor" True session_inhibited
  session_blank "held inhibitor"
  session_key "held inhibitor"
  expect "the inhibitor is still held after input" True session_inhibited

  stop_shell || fail "the shell stops for the input observer control"
  copy_tree session-inhibitor || fail "the input observer control tree is copied"
  edit_tree session-inhibitor shell/Core/Compositor.qml 'respectInhibitors: false' 'respectInhibitors: true' || fail "the input observer control is planted"
  start_shell "$sandbox/tree-session-inhibitor" "$sandbox/qs-session-inhibitor.log" || fail "the input observer control starts"
  expect_poll "the session reader returns in the control shell" True record_exists acme.session
  session_blank "control observer"
  type_keys -k Shift_L || fail "the control wake key could not be sent"
  expect_poll "control input still wakes all nested outputs" True session_power true
  (
    failures=0
    expect "input clears the fact while inhibited" false session_read displaysOff
    printf 'control-failures=%s\n' "$failures"
  ) >"$sandbox/session-inhibitor-control.log"
  session_control_failures="$(sed -n 's/^control-failures=//p' "$sandbox/session-inhibitor-control.log")"
  expect "respecting inhibitors fails the input fact assertion once" 1 printf '%s' "$session_control_failures"
  stop_shell || fail "the input observer control stops"
  rm -rf -- "${sandbox:?}/tree-session-inhibitor"
  start_shell "$repo" "$sandbox/qs-session-restored.log" || fail "the production shell returns"
  expect_poll "the restored session reader is built" True record_exists acme.session
  expect "the restored shell holds no off fact" false session_read displaysOff
  close_toplevel "$session_inhibitor_pid" "the nested inhibitor window exits"
else
  fail "the nested inhibitor window maps"
fi
hypr_lua_restore session-inhibitor
expect "the nested inhibitor rule is removed" ok hypr reload config-only
expect "disable releases the session reader" ok ipc shell setPluginEnabled acme.session false
expect_poll "the session hold is gone" null lent holders.session
expect "the lock holder remains built after the reader leaves" True record_exists acme.probe
