# vgs.windows' group lock key, SUPER+CTRL+G, typed on the nested seat. On
# a grouped window two presses lock and then unlock the group: the nested
# Hyprland's own Lua read of the focused window's group gives true, then
# false, and the Windows cards on screen, cleared before each press, are
# exactly one Group locked with `lock`, then exactly one Group unlocked
# with `lock-open`, each with a one-line message. A press on a window in no
# group shows no card. After each press the row waits for the service's
# count of finished presses, so no press is still reading or toggling when
# the harness groups, ungroups or closes the window. The service sends a
# notification before it counts the press, and notify-send exits once the
# server answered, after vgs.notifications took the card in the server's
# notification handler; so once the count moves and the core's notify runs
# reach none, every card the press sent is on screen, and the row reads
# the cards once then. A poll would pass once an extra card expired, after
# 8 s. The service is in the smoke set from the start, and the row leaves
# it so; it turns the notifications on for its cards and off again, and
# puts hyprland.lua back. State polls use the shared expect_poll interval
# of 200 ms; no latency budget is measured here.
# inputs: shell/plugins/vgs.windows/* scripts/smoke/Probe.qml shell/Core/Compositor.qml shell/Core/Dispatch.js shell/Core/Capabilities.qml shell/Core/Notifier.qml shell/Core/HyprlandLayer.* shell/Core/ConfigLogic.js shell/Core/PluginLogic.js shell/plugins/vgs.notifications/* scripts/smoke/toplevel/* scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail
gl_layer="$home/.local/state/vgshell/hypr/vgs.lua"
gl_bind='hl.bind("SUPER + CTRL + G", hl.dsp.global("vgs.windows:group-lock"), { description = "vgs.windows:group-lock" })'
gl_layer_binds() { if grep -qxF -- "$gl_bind" "$gl_layer"; then echo yes; else echo no; fi; }
# The focused window's group lock as the nested Hyprland's Lua gives it:
# true, false, ungrouped, or none with no focused window.
gl_state() { hypr repl 'local w = hl.get_active_window() if w == nil then return "none" end if w.group == nil then return "ungrouped" end return tostring(w.group.locked)'; }
# The Windows cards on screen, newest first, each as [summary, icon,
# whether its message is one line that is not empty].
gl_cards() {
  local raw
  raw="$(plugin_cards Windows)" || return 1
  py_reply 'import json,sys; print(json.dumps([[r[0], r[4], r[1] != "" and "\n" not in r[1]] for r in json.load(sys.stdin)]))' <<<"$raw"
}
gl_finished() { ipc smoke readInstance service vgs.windows finished; }
# gl_press LABEL: SUPER+CTRL+G typed once, and the service's count of
# finished presses read one higher.
gl_press() {
  local before
  before="$(gl_finished)" || { fail "$1: the finished presses are unreadable"; return 0; }
  [[ $before =~ ^[0-9]+$ ]] || { fail "$1: the finished presses read $before"; return 0; }
  type_keys -M logo -M ctrl -k g -m ctrl -m logo || { fail "$1: typing SUPER+CTRL+G failed"; return 0; }
  expect_poll "$1: the service finished the press" "$((before + 1))" gl_finished
}
# gl_cards_now LABEL WANT: the cards read once, after every notify run the
# shell started has ended.
gl_cards_now() {
  expect_poll "$1: every notification the shell started has reached the server" 0 ipc smoke themeNoticeRuns
  expect "$1" "$2" gl_cards
}

expect "the Windows plugin is enabled in the smoke set" True plugin_enabled vgs.windows
expect_poll "the Windows service is built" True record_exists vgs.windows
expect_poll "the layer binds SUPER+CTRL+G to the group lock" yes gl_layer_binds
notes_on "group lock"
# wtype's keys resolve a bind by keysym only, as the lock row reads.
hypr_lua_save group-lock
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$home/.config/hypr/hyprland.lua"
expect "the nested instance reloads with binds resolved by keysym" ok hypr reload config-only

if open_toplevel "$sandbox/group-lock-target.log" smoke.group-lock target; then
  gl_pid="$toplevel_pid"
  expect_poll "the target window is focused" '["smoke.group-lock", "target"]' active_window
  expect "the target starts in no group" ungrouped gl_state
  expect "the harness groups the target" ok hypr dispatch 'hl.dsp.group.toggle()'
  expect_poll "the target's group starts unlocked" false gl_state

  gl_press "the first press"
  expect_poll "the first press locks the group in Hyprland" true gl_state
  gl_cards_now "the first press shows one Group locked card with the lock icon" '[["Group locked", "lock", true]]'
  notes_first_card "the group lock card"
  notes_clear "group lock second press"
  gl_press "the second press"
  expect_poll "the second press unlocks the group in Hyprland" false gl_state
  gl_cards_now "the second press shows one Group unlocked card with the open lock icon" '[["Group unlocked", "lock-open", true]]'

  notes_clear "group lock ungrouped"
  expect "the harness ungroups the target" ok hypr dispatch 'hl.dsp.group.toggle()'
  expect_poll "the target is in no group again" ungrouped gl_state
  gl_press "the press on the window in no group"
  gl_cards_now "the press on the window in no group showed no card" '[]'
  expect "the harness groups the target again" ok hypr dispatch 'hl.dsp.group.toggle()'
  expect_poll "the target's new group starts unlocked" false gl_state
  gl_press "the press after it"
  expect_poll "the press after it locks the new group" true gl_state
  gl_cards_now "the press after it shows one Group locked card" '[["Group locked", "lock", true]]'

  notes_clear "group lock last press"
  gl_press "a last press"
  expect_poll "a last press unlocks the group" false gl_state
  gl_cards_now "a last press shows one Group unlocked card" '[["Group unlocked", "lock-open", true]]'
  expect "the harness ungroups the target at the end" ok hypr dispatch 'hl.dsp.group.toggle()'
  expect_poll "the target ends in no group" ungrouped gl_state
  close_toplevel "$gl_pid" "the group lock target window exits"
else
  fail "the group lock target window maps"
fi

hypr_lua_restore group-lock || fail "hyprland.lua is put back after the group lock rows"
expect "the nested instance reloads the consent-wired hyprland.lua" ok hypr reload config-only
notes_off "group lock"
