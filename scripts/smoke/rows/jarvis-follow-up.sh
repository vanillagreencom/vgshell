# Jarvis's follow-up listening window in Always mode, against private
# scripted Session ports and the scripted chained engine: after a spoken
# reply the follow-up capture opens, the bar widget and the bubble say so,
# and silence returns Jarvis to waiting for the wake word. The row resets
# Jarvis at its start and at its end (disable, rescan, enable), so no row
# after it reads its Jarvis state. It runs the window in the dark and the
# light theme and keeps one output capture of each window open and closed
# in the sandbox. No audio, account, provider or network runs. No latency
# ceiling is measured: state, widget and bubble reads poll once per nested
# IPC round trip; fixture callback gates poll at 10 ms; the window's close
# waits on Session.js's WAKE_SILENCE_MS.
# inputs: scripts/smoke/user-config.sh shell/plugins/vgs.jarvis/* scripts/fixtures/jarvis/* scripts/smoke/keyboard/* shell/plugins/vgs.bar/* shell/Ui/feedback/VoiceOrb.qml shell/Core/Layers.qml themes/catalog/flexoki-light/theme.json scripts/smoke/rows/jarvis.sh scripts/smoke/rows/jarvis-keys.sh scripts/smoke/rows/hold-shortcuts.sh
set -euo pipefail
# The Jarvis fixtures log the set jarvis.sh declares.
expected_errors+=("${jarvis_provoked_errors[@]}")

jarvis_follow_up_config="$home/.config/vgshell/shell.json"
jarvis_follow_up_lua="$home/.config/hypr/hyprland.lua"
jarvis_follow_up_theme="$home/.config/vgshell/theme.json"
jarvis_follow_up_dir="$repo/shell/plugins/vgs.jarvis"
jarvis_follow_up_gates="$sandbox/jarvis-follow-up-gates"
jarvis_follow_up_files=(Session.js backend/jarvisd.js backend/ChainedEngine.js)
# The chained engine speaks its acknowledgement of the scripted utterance
# before the scripted driver's reply; the caption carries both.
jarvis_follow_up_reply="$(python3 -c 'print("On it. " + " ".join(["scripted reply"] * 24))')"
cp -- "$jarvis_follow_up_config" "$sandbox/jarvis-follow-up-config-before.json"
cp -- "$jarvis_follow_up_lua" "$sandbox/jarvis-follow-up-lua-before"
for jarvis_follow_up_file in "${jarvis_follow_up_files[@]}"; do
  cp -- "$jarvis_follow_up_dir/$jarvis_follow_up_file" "$sandbox/jarvis-follow-up-before-${jarvis_follow_up_file##*/}"
done
jarvis_follow_up_theme_before="$(ipc smoke themeName)" || fail "the theme before the follow-up row is unreadable"
[[ ! -e $jarvis_follow_up_theme ]] || cp -- "$jarvis_follow_up_theme" "$sandbox/jarvis-follow-up-theme-before.json"
jarvis_follow_up_key="$(bar_key)"

jarvis_follow_up_gate() { : >"$jarvis_follow_up_gates/$1"; }
jarvis_follow_up_capture() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
capture=json.load(sys.stdin)["status"]["detail"]["state"]["capture"]
print(capture.get("mode", capture["kind"]))
'
}
jarvis_follow_up_widget() { # state|tooltip
  ipc smoke readInstance "$jarvis_follow_up_key" vgs.jarvis view | py_reply 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"
}
jarvis_follow_up_tooltip_named() {
  local tooltip
  tooltip="$(jarvis_follow_up_widget tooltip)" || return 1
  [[ $tooltip == *follow-up* ]] && echo follow-up || echo other
}
jarvis_follow_up_bubble() {
  ipc smoke layerWindows vgs.jarvis | py_reply '
import json,sys
rows=json.load(sys.stdin)
shown=[r for r in rows if r["visible"] and r["presented"] and r["width"]>0 and r["height"]>0]
print("presented" if len(shown)==1 else "not-presented")
'
}
jarvis_follow_up_text() { # TEXT
  ipc smoke layerItems vgs.jarvis Label text,visible | py_reply '
import json,sys
rows=json.load(sys.stdin)
print("drawn" if any(v["visible"] and v["text"]==sys.argv[1] and box[2]>0 and box[3]>0 for _,box,v in rows) else "absent")
' "$1"
}
jarvis_follow_up_shot() { # NAME
  local path="$sandbox/jarvis-follow-up-$1.png" socket output
  socket="$(shot_socket "$rt_dir" "$nested_socket")" &&
    output="$(first_name)" &&
    shot_grim "$socket" "$rt_dir" -o "$output" -t png "$path" || { fail "the $1 follow-up capture is written"; return 0; }
  printf 'jarvis-follow-up: shot=%s\n' "$path"
}
# One Always-mode request from Talk to the end of its spoken reply: the
# follow-up window, when Session opens it, opens as that reply ends.
jarvis_follow_up_request() {
  jarvis_key_mode always
  jarvis_key_talk_down
  jarvis_key_talk_up
  expect_poll "Talk in Always mode listens" listening jarvis_key_state phase
  expect_poll "the listening bubble presents" presented jarvis_follow_up_bubble
  jarvis_follow_up_gate final
  jarvis_key_commit
  jarvis_follow_up_gate played
  jarvis_follow_up_gate reply
  expect_poll "the scripted reply reaches the bubble before the follow-up window" drawn jarvis_follow_up_text "$jarvis_follow_up_reply"
  jarvis_follow_up_gate played
}
jarvis_follow_up_opens() { expect_poll "the follow-up capture opens" follow-up jarvis_follow_up_capture; }
jarvis_follow_up_end() {
  jarvis_key_mode hold
  jarvis_key_stop
  jarvis_key_stop_assertion
}
jarvis_follow_up_window() { # THEME
  jarvis_follow_up_request
  jarvis_follow_up_opens
  expect_poll "the bar icon reads listening during the follow-up window" listening jarvis_follow_up_widget state
  expect_poll "the bar tooltip names the follow-up window" "Jarvis is listening for a follow-up" jarvis_follow_up_widget tooltip
  expect_poll "the bubble reads Listening during the follow-up window" drawn jarvis_follow_up_text Listening
  jarvis_follow_up_shot "$1-open"
  expect "the follow-up window is still open after its capture" follow-up jarvis_follow_up_capture
  expect_poll "silence closes the follow-up window and returns to wake-word listening" armed jarvis_key_state phase
  expect_poll "the bar tooltip no longer names follow-up after the window" other jarvis_follow_up_tooltip_named
  expect_poll "the bubble no longer reads Listening after the follow-up window" absent jarvis_follow_up_text Listening
  jarvis_follow_up_shot "$1-closed"
  jarvis_follow_up_end
}
# The control's whole run with Session.js planted; called in an || list so
# no failing step skips the restore after it.
jarvis_follow_up_control() {
  jarvis_rescan
  jarvis_enable
  jarvis_follow_up_request
  jarvis_follow_up_failures="$(
    failures=0 behaviour_failures=0
    jarvis_follow_up_opens >"$sandbox/jarvis-follow-up-control.log"
    echo "$failures"
  )"
  expect "control: removing the follow-up window fails the same capture check" 1 printf '%s\n' "$jarvis_follow_up_failures"
  # The verdict line the harness prints: the capture went back to the wake
  # word, not a reader that failed.
  expect "control: the capture check reads the wake-word capture instead" 1 grep -c -x -F '  FAIL  the follow-up capture opens: got armed want follow-up' "$sandbox/jarvis-follow-up-control.log"
  jarvis_follow_up_end
  jarvis_disable
}

expect "the follow-up row starts with Jarvis disabled" absent ipc smoke jarvisProcess
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" "$jarvis_follow_up_dir/backend/jarvisd.js" "$jarvis_follow_up_gates" --mapped-indicator
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" --chained-engine "$jarvis_follow_up_dir/backend/ChainedEngine.js"
# The stand-ins keep the requirement notice off the captures.
jarvis_setup_requirements
jarvis_rescan
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = false } })' >>"$jarvis_follow_up_lua"
expect "Jarvis keys use the physical evdev map" ok hypr reload config-only
hold_start_keyboard jarvis-follow-up "$sandbox/keyboard" us ""
jarvis_enable
expect_poll "no requirement notice stands over the follow-up captures" null notice_shown
expect_poll "the Jarvis bar widget is mounted" ready jarvis_follow_up_widget state

jarvis_follow_up_window dark
jarvis_follow_up_light="$(cat "$repo/themes/catalog/flexoki-light/theme.json")" || fail "the light theme is unreadable"
printf '%s\n' "$jarvis_follow_up_light" >"$jarvis_follow_up_theme.tmp" && mv -T -- "$jarvis_follow_up_theme.tmp" "$jarvis_follow_up_theme"
expect_poll "the light theme applies" flexoki-light ipc smoke themeName
jarvis_follow_up_window light
if [[ -e $sandbox/jarvis-follow-up-theme-before.json ]]; then
  cp -- "$sandbox/jarvis-follow-up-theme-before.json" "$jarvis_follow_up_theme.tmp" && mv -T -- "$jarvis_follow_up_theme.tmp" "$jarvis_follow_up_theme"
else
  rm -f -- "$jarvis_follow_up_theme"
fi
expect_poll "the theme before the row returns" "$jarvis_follow_up_theme_before" ipc smoke themeName

# Keep the reply and its played callback. Open no follow-up window at the
# reply's end; the same capture check must fail once.
jarvis_disable
python3 - "$jarvis_follow_up_dir/Session.js" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); assert not p.is_symlink()
s=p.read_text(); needle='s.input = { kind: "follow-up" };'
assert s.count(needle)==1
changed=s.replace(needle, 's.input = { kind: "released" };')
assert changed!=s
p.write_text(changed)
PY
jarvis_follow_up_control || fail "control: the follow-up control runs to its end"
cp -- "$sandbox/jarvis-follow-up-before-Session.js" "$jarvis_follow_up_dir/Session.js"
[[ $(ipc smoke jarvisProcess) == absent ]] || jarvis_disable

hold_stop_keyboard
jarvis_restore_requirements
for jarvis_follow_up_file in "${jarvis_follow_up_files[@]}"; do
  cp -- "$sandbox/jarvis-follow-up-before-${jarvis_follow_up_file##*/}" "$jarvis_follow_up_dir/$jarvis_follow_up_file"
done
rm -- "$jarvis_follow_up_dir/backend/scripted-fixture.js"
rm -f -- "$home/.local/state/vgshell/jarvis/mute.json"
jarvis_rescan
user_config_restore "$sandbox/jarvis-follow-up-config-before.json"
cp -- "$sandbox/jarvis-follow-up-lua-before" "$jarvis_follow_up_lua"
expect "restore the Jarvis follow-up configuration" ok ipc shell reloadConfig
expect "restore the nested keyboard configuration" ok hypr reload config-only
jarvis_enable
expect_poll "the restored stock daemon remains unconfigured" session jarvis_session unconfigured
expect "the restored nested keys have no configuration errors" '[]' hypr_reload_errors
jarvis_disable
jarvis_notice_close
