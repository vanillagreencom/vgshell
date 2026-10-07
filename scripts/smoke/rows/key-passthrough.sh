# Key capture pass-through, D067, after rows/key-capture.sh, whose shell
# and Settings plugin it keeps. Every way a capture ends leaves the nested
# Hyprland's vgs:passthrough submap, read through `hyprctl submap` of the
# nested instance alone: a commit, Escape (the submap's own bind), a focus
# loss to a toplevel helper that maps over the window, the window's close,
# a `hyprctl reload` of the nested instance, the 10 s timeout (the field
# names it when it fires, polled every 200 ms) and a
# SIGKILL of the shell, whose window then closes. Each path has a control:
# a tree copy with that exit removed holds the submap after the same exit
# is ordered, and the row resets it by hand. The commit control drops the
# owner's leave on commit, the Escape control binds Escape to a no-op, the
# focus control drops the field's focus-loss cancel, the close control
# drops every leave but commit and cancel and the layer's window close
# hook, the reload control drops the layer's leave as it loads, the timeout
# control drops the timer's leave, and the SIGKILL control drops the close
# hook. The row appends `input:resolve_binds_by_sym` to the nested
# hyprland.lua, so wtype's Escape reaches the submap's bind, and puts the
# file back at its end. Keys go to the nested seat alone.
# inputs: shell/Core/KeyCapture.qml shell/Core/HyprlandLayer.js shell/Ui/controls/ShortcutField.qml shell/Ui/controls/BindField.qml shell/plugins/vgs.settings/* shell/Commons/Reply.js scripts/smoke/toplevel/* shell/Core/Compositor.qml shell/Core/Dispatch.js scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail

kp_settings_open() { [[ $(ipc smoke instanceGeometry window vgs.settings) != absent ]] && echo open || echo closed; }
kp_markers=0
kp_marker_count() { ipc smoke holdMarkerCount; }
kp_type_exit() { # LABEL TYPE_KEYS...
  local label="$1"
  shift
  kp_markers=$((kp_markers + 1))
  type_keys "$@" -k F9 || fail "$label: typing the exit and marker failed"
  expect_poll "$label: the marker key after the exit is processed" "$kp_markers" kp_marker_count
}
kp_key_marker() { # LABEL
  kp_markers=$((kp_markers + 1))
  type_keys -k F9 || fail "$1: typing the marker key failed"
  expect_poll "$1: the marker key after the exit is processed" "$kp_markers" kp_marker_count
}
kp_timeout_notice() {
  local got=""
  for _ in $(seq 1 150); do # a failure bound well past the 10 s timer
    got="$(settings_key_field notice)" || return
    [[ $got == '"Listening stopped after 10 s. Press Return or click the field to listen again."' ]] && { echo noticed; return; }
    sleep 0.2
  done
  printf '%s\n' "$got"
}

# ARM LABEL: the Settings window on its own page, its Keys row's field
# focused, Return pressed and the submap entered.
kp_arm() {
  expect "$1: Settings is summoned on its own page" ok ipc shell summon window vgs.settings '{"plugin":"vgs.settings"}'
  expect_poll "$1: the Settings window has the keyboard" "[\"$shell_class\", \"Plugins\"]" active_window
  expect_poll "$1: the field takes the focus" focused settings_key_invoke focusKeyField
  type_keys -k Return || fail "$1: Return on the field failed"
  expect_poll "$1: Return starts a capture" true settings_key_field capturing
  expect_poll "$1: the capture enters the pass-through submap" vgs:passthrough key_submap
}
# HELD LABEL: a control's reading, the submap still held after its exit,
# then reset by hand.
kp_held() {
  expect "$1: the submap stays vgs:passthrough without that exit" vgs:passthrough key_submap
  expect "$1: resetting the submap for cleanup is allowed" ok hypr dispatch 'hl.dsp.submap("reset")'
  expect_poll "$1: the cleanup reset reaches the default map" default key_submap
}
# A commit of the key in effect, SUPER+M, which writes nothing, so no
# layer write reloads Hyprland and only the owner's leave can end it.
kp_commit() {
  kp_arm "$1"
  kp_type_exit "$1: SUPER+M" -M logo -k m -m logo
  expect_poll "$1: the commit ends the capture" false settings_key_field capturing
  expect "$1: the key in effect is not written" absent settings_key
}
kp_escape() {
  kp_arm "$1"
  kp_type_exit "$1: Escape" -k Escape
}
kp_focus() {
  local log="$sandbox/key-passthrough-${1//[^A-Za-z0-9]/-}-helper.log"
  kp_arm "$1"
  if open_toplevel "$log" smoke.key-passthrough-helper "Key passthrough helper"; then
    kp_helper_pid="$toplevel_pid"
    expect_poll "$1: the helper takes the keyboard" '["smoke.key-passthrough-helper", "Key passthrough helper"]' active_window
    kp_key_marker "$1: focus loss"
  else
    fail "$1: the toplevel helper maps"
    kp_helper_pid=""
  fi
}
kp_focus_done() {
  [[ -z $kp_helper_pid ]] || close_toplevel "$kp_helper_pid" "$1: the toplevel helper exits 0 on SIGTERM"
}
kp_close() {
  kp_arm "$1"
  expect "$1: the Settings window is hidden" ok ipc shell hide window vgs.settings
  expect_poll "$1: the Settings window closes" closed kp_settings_open
  kp_key_marker "$1: close"
}
kp_timeout() {
  kp_arm "$1"
  expect "$1: the field starts the timeout while still capturing" true settings_key_field capturing
  expect "$1: the submap is held before the timeout fires" vgs:passthrough key_submap
}
kp_reload() {
  kp_arm "$1"
  expect "$1: the nested instance reloads" ok hypr reload config-only
  kp_key_marker "$1: reload"
}
kp_kill() {
  kp_arm "$1"
  kp_killed="$shell_qs_pid"
  kill -KILL -- "$kp_killed" 2>/dev/null || fail "$1: killing the recorded shell pid failed"
  expect_poll "$1: the Settings window is gone with its shell" 0 window_count Plugins
}
# CONTROL NAME LABEL: start the tree copy NAME, whose edits are made.
kp_control_start() {
  stop_shell
  start_shell "$sandbox/tree-$1" "$sandbox/key-passthrough-$1.log" || fail "$2: the control shell starts"
  expect "$2: the observer creates the pass-through ordering marker" ok ipc smoke holdMarkerStart
  kp_markers=0
}

hypr_lua_save key-passthrough
printf '%s\n' \
  'hl.config({ input = { resolve_binds_by_sym = true } })' \
  'hl.bind("F9", hl.dsp.global("smoke:hold-marker"), { description = "smoke:hold-marker", ignore_mods = true })' \
  'hl.define_submap("vgs:passthrough", function() hl.bind("F9", hl.dsp.global("smoke:hold-marker"), { description = "smoke:hold-marker", ignore_mods = true }) end)' \
  >>"$home/.config/hypr/hyprland.lua"
expect "the nested instance reloads with keysym binds" ok hypr reload config-only
expect "the observer creates the pass-through ordering marker" ok ipc smoke holdMarkerStart
kp_markers=0

# The nominal paths.
kp_commit "commit"
expect_poll "commit: the commit leaves the submap" default key_submap

kp_escape "Escape"
expect_poll "Escape: Hyprland's Escape bind leaves the submap" default key_submap
expect_poll "Escape: the field sees the capture end" false settings_key_field capturing
expect "Escape: no key is stored" absent settings_key

kp_focus "focus loss"
expect_poll "focus loss: the focus loss leaves the submap" default key_submap
kp_focus_done "focus loss"

kp_close "close"
expect_poll "close: the window's close leaves the submap" default key_submap

kp_reload "reload"
expect_poll "reload: the layer's run leaves the submap" default key_submap
expect_poll "reload: the field sees the capture end" false settings_key_field capturing

kp_timeout "timeout"
expect "timeout: the field reports its 10 s timeout" noticed kp_timeout_notice
expect "timeout: the timer leaves the submap after the field reports it" default key_submap
expect_poll "timeout: the field sees the capture end" false settings_key_field capturing
expect_poll "timeout: the field says listening stopped" '"Listening stopped after 10 s. Press Return or click the field to listen again."' settings_key_field notice

kp_kill "SIGKILL"
expect_poll "SIGKILL: the window close hook leaves the submap" default key_submap
adopt_shell "$kp_killed" || fail "SIGKILL: the runner starts the shell again"

# The controls, each a tree copy without that exit.
if copy_tree kp-commit && edit_tree kp-commit shell/Core/KeyCapture.qml '&& reason !== "timeout") leave();' '&& reason !== "timeout" && reason !== "commit") leave();'; then
  kp_control_start kp-commit "control commit"
  kp_commit "control commit"
  kp_held "control commit"
fi
if copy_tree kp-escape && edit_tree kp-escape shell/Core/HyprlandLayer.js '", hl.dsp.submap(\"reset\"), { description = \"" + p.description' '", hl.dsp.exec_cmd(\"true\"), { description = \"" + p.description'; then
  kp_control_start kp-escape "control Escape"
  kp_escape "control Escape"
  kp_held "control Escape"
fi
if copy_tree kp-focus && edit_tree kp-focus shell/Ui/controls/ShortcutField.qml 'onActiveFocusChanged: if (!activeFocus) root.stop("focus")' 'onActiveFocusChanged: {}'; then
  kp_control_start kp-focus "control focus loss"
  kp_focus "control focus loss"
  kp_held "control focus loss"
  kp_focus_done "control focus loss"
fi
if copy_tree kp-close && edit_tree kp-close shell/Core/KeyCapture.qml '&& reason !== "compositor" && reason !== "timeout") leave();' '&& (reason === "commit" || reason === "cancel")) leave();' \
  && edit_tree kp-close shell/Core/HyprlandLayer.js 'then passthrough." + p.verbs.leave + "() end",' 'then local _ = passthrough end",'; then
  kp_control_start kp-close "control close"
  kp_close "control close"
  kp_held "control close"
fi
if copy_tree kp-reload && edit_tree kp-reload shell/Core/HyprlandLayer.js $'        "    passthrough." + p.verbs.leave + "()",\n        "end"' $'        "end"'; then
  kp_control_start kp-reload "control reload"
  kp_reload "control reload"
  kp_held "control reload"
fi
kp_timeout_marker="$sandbox/key-passthrough-timeout-fired"
kp_timeout_marker_seen() {
  for _ in $(seq 1 150); do # a failure bound well past the 10 s timer
    [[ -e $kp_timeout_marker ]] && { echo fired; return; }
    sleep 0.2
  done
  echo waiting
}
kp_timeout_replacement="$(python3 - "$kp_timeout_marker" <<'PY'
import json, sys
lines = [
    "        passthrough.timer:set_enabled(false)",
    "        local f = io.open(" + json.dumps(sys.argv[1]) + ', "w"); if f ~= nil then f:close() end',
]
print(",\n".join("        " + json.dumps(line) for line in lines) + ",")
PY
)" || fail "the timeout control marker replacement is built"
if copy_tree kp-timeout && edit_tree kp-timeout shell/Core/HyprlandLayer.js $'        "        passthrough.timer:set_enabled(false)",\n        "        passthrough." + p.verbs.leave + "()",' "$kp_timeout_replacement"; then
  rm -f -- "$kp_timeout_marker"
  kp_control_start kp-timeout "control timeout"
  kp_timeout "control timeout"
  expect "control timeout: the timer fires in the control copy" fired kp_timeout_marker_seen
  kp_held "control timeout"
fi
if copy_tree kp-kill && edit_tree kp-kill shell/Core/HyprlandLayer.js 'then passthrough." + p.verbs.leave + "() end",' 'then local _ = passthrough end",'; then
  kp_control_start kp-kill "control SIGKILL"
  kp_kill "control SIGKILL"
  kp_held "control SIGKILL"
  adopt_shell "$kp_killed" || fail "control SIGKILL: the runner starts the shell again"
  expect "control SIGKILL: the restarted observer creates the pass-through ordering marker" ok ipc smoke holdMarkerStart
fi

expect "the observer releases the pass-through ordering marker" ok ipc smoke holdMarkerStop
stop_shell
hypr_lua_restore key-passthrough || fail "key passthrough puts the harness hyprland.lua back"
start_shell "$repo" "$sandbox/key-passthrough-final.log" || fail "key passthrough leaves a live shell for the rows after it"
expect "the nested instance reloads the harness hyprland.lua" ok hypr reload config-only
