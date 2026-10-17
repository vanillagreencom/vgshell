# System -> Displays monitor-mode writes: the plugin's monitor trial applies
# a nested output rule, the detached guard reverts it when it is not kept,
# Keep saves it into the generated layer, a position trial reverts, and the
# guard still reverts while the shell is stopped. A kept rule that turns
# the main output off holds while the headless output stays on, the layer
# turns the main output back on when that output goes, and a reload with
# the main output alone leaves it on. An sRGB colour rule goes through
# trial, Keep and reload with no configuration error, and the judge refuses
# an HDR trial, since the nested panel has no EDID. The row uses WAYLAND-1, whose nested
# backend takes any mode and integer scale. The nested headless output
# takes no mirror rule, so the unit rows alone hold Mirror. Around each
# rule that turns the main output off the row waits for the shell's bar on
# it to go and to come back, so no rule turns off an output the shell has
# not bound. Each poll reads every 0.2 s for up to 5 s. The row takes the
# run's held rule out of the configuration while it tests monitor rules
# and puts it back at its end (suspend_run_base in mode-hold.sh): that rule
# loads after the generated layer, so each reload would give the output
# the held mode again and replace the rule Keep saved.
# Control run on 2026-10-10, host cachy, through this row after the setup
# rows: a guard copy that exits before restore leaves the trial's token
# held and writes no log, and the control reports the defect; with the
# shipped guard left in place the same check reads `token=claimed
# log=written` and fails.
# Control run on 2026-10-06, host cachy, through this row after the setup
# rows: a rule that turns the main output off with no check, sent while it
# is the only output, leaves it off, and the control reports the defect;
# a reload of the layer turns it back on.
# inputs: shell/plugins/vgs.displays/* shell/Core/MonitorState.qml shell/Core/MonitorLogic.js shell/Core/HyprlandLayer.js shell/Core/Dispatch.js shell/Core/Compositor.qml bin/vgshell-display-guard
set -euo pipefail

user_config="$home/.config/vgshell/shell.json"
hypr_layer="$home/.local/state/vgshell/hypr/vgs.lua"
cp -- "$user_config" "$sandbox/shell-before-displays-modes.json"

read_displays() { ipc smoke readInstance service vgs.displays "$1"; }
invoke_displays() {
  local reply status=0
  display_record_call mark display-request "$1" "$2" >/dev/null || true
  ipc smoke displayEventBoundary "before:$1" >/dev/null || true
  reply="$(ipc smoke invokeInstance service vgs.displays "$1" "$2")" || status=$?
  display_record_call mark display-reply "$1" "$status" "$reply" >/dev/null || true
  ipc smoke displayEventBoundary "after:$1" >/dev/null || true
  printf '%s\n' "$reply"
  return "$status"
}
outputs_state() { read_displays outputs | py_reply 'import json,sys; value=json.load(sys.stdin); print("present" if isinstance(value, list) and value else "absent")'; }
output_present() { read_displays outputs | py_reply 'import json,sys; value=json.load(sys.stdin); print("present" if any(row.get("name") == sys.argv[1] for row in value) else "absent")' "$1"; }
scale_of() { hypr -j monitors all | py_reply 'import json,sys; rows=[m for m in json.load(sys.stdin) if m["name"]==sys.argv[1]]; print(rows[0]["scale"] if rows else "absent")' "$1"; }
position_of() { hypr -j monitors all | py_reply 'import json,sys; rows=[m for m in json.load(sys.stdin) if m["name"]==sys.argv[1]]; print("%sx%s" % (rows[0]["x"], rows[0]["y"]) if rows else "absent")' "$1"; }
position_wait() {
  local output="$1" want="$2" got
  for _ in $(seq 1 25); do
    got="$(position_of "$output")" || got=absent
    [[ $got == "$want" ]] && { echo yes; return; }
    sleep 0.2
  done
  echo no
}
not_trial_scale() { [[ "$(scale_of "$1")" == "$trial_scale" ]] && echo no || echo yes; }
mode_of() { hypr -j monitors all | py_reply 'import json,sys; rows=[m for m in json.load(sys.stdin) if m["name"]==sys.argv[1]]; print("%dx%d" % (rows[0]["width"], rows[0]["height"]) if rows else "absent")' "$1"; }
token_of() { read_displays trialState | py_reply 'import json,sys; print(json.load(sys.stdin).get("token",""))'; }
trial_phase() { read_displays trialState | py_reply 'import json,sys; print(json.load(sys.stdin).get("phase",""))'; }
guard_pid_for() { python3 - "$1" <<'PY'
import pathlib, sys
token = sys.argv[1]
for path in pathlib.Path("/proc").glob("[0-9]*/cmdline"):
    try:
        parts = path.read_bytes().decode(errors="ignore").split("\0")
    except OSError:
        continue
    if token in parts:
        print(path.parent.name)
        raise SystemExit
print("absent")
PY
}
guard_running() { [[ "$(guard_pid_for "$1")" == absent ]] && echo no || echo yes; }
# guard_left TOKEN: what a guard left of a trial. A guard that restores
# first renames the token file, and every guard that reaches its deadline
# writes TOKEN.log. A configuration reload also puts the scale back, so the
# scale does not say whether a guard restored.
guard_left() { echo "token=$([[ -e $1 ]] && echo held || echo claimed) log=$([[ -e $1.log ]] && echo written || echo none)"; }
rule_json() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
name, mode, scale = sys.argv[1], sys.argv[2], float(sys.argv[3])
w, h = map(int, mode.split("x"))
print(json.dumps({name: {"mode": {"width": w, "height": h, "refresh": 60}, "position": {"x": 0, "y": 0}, "scale": scale, "transform": 0}}))
PY
}
position_rule_json() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
name, x, y = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
print(json.dumps({name: {"position": {"x": x, "y": y}}}))
PY
}
layer_has_rule() { grep -q -E 'hl\.monitor[[:space:]]*\(' "$hypr_layer" && echo yes || echo no; }
hold_file_state() { [[ -e $mode_hold_file ]] && echo present || echo absent; }
disabled_of() { hypr -j monitors all | py_reply 'import json,sys; rows=[m for m in json.load(sys.stdin) if m["name"]==sys.argv[1]]; print(str(rows[0]["disabled"]).lower() if rows else "absent")' "$1"; }
layer_turns_off() { grep -q -F -x -- "    local vgs_monitors_off = { \"$1\" }" "$hypr_layer" && echo yes || echo no; }
off_rule_json() {
  python3 - "$1" "$2" <<'PY'
import json, sys
name, mode = sys.argv[1], sys.argv[2]
w, h = map(int, mode.split("x"))
print(json.dumps({name: {"mode": {"width": w, "height": h, "refresh": 60}, "position": {"x": 0, "y": 0}, "scale": 1, "transform": 0, "disabled": True}}))
PY
}
preset_of() { hypr -j monitors all | py_reply 'import json,sys; rows=[m for m in json.load(sys.stdin) if m["name"]==sys.argv[1]]; print(rows[0]["colorManagementPreset"] if rows else "absent")' "$1"; }
service_scale_of() { read_displays outputs | py_reply 'import json,sys; rows=[m for m in json.load(sys.stdin) if m["name"]==sys.argv[1]]; print(rows[0]["scale"] if rows else "absent")' "$1"; }
trial_failure() { read_displays trialState | py_reply 'import json,sys; print(json.load(sys.stdin).get("failure") or "none")'; }
reload_names_cm() { hypr_reload_errors | py_reply 'import json,sys; print("yes" if any("cm" in e for e in json.load(sys.stdin)) else "no")'; }
layer_sets_colour() { grep -q -F -- "cm = \"$1\"" "$hypr_layer" && echo yes || echo no; }
colour_rule_json() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, sys
name, mode, scale, cm = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
w, h = map(int, mode.split("x"))
print(json.dumps({name: {"mode": {"width": w, "height": h, "refresh": 60}, "position": {"x": 0, "y": 0}, "scale": scale, "transform": 0, "cm": cm}}))
PY
}

expect "enabling vgs.displays for display modes is allowed" ok ipc shell setPluginEnabled vgs.displays true
expect_poll "vgs.displays is built for display modes" True record_exists vgs.displays
expect_poll "vgs.displays has outputs" present outputs_state
display_record_call mark displays-row-start >/dev/null || true
display_record_call require-display "$shell_pid" "$shell_qs_pid" >/dev/null || true
display_observer_arm="$(ipc smoke displayEventArm displays-modes)" || display_observer_arm=unavailable
display_record_call mark display-observer-arm "$display_observer_arm" >/dev/null || true

output="$(first_name)"
base="$(unscaled_mode_of "$output")"
base_position="$(position_of "$output")"
trial_mode="$(hidpi_mode_of "$output")"
trial_scale=2
rules="$(rule_json "$output" "$trial_mode" "$trial_scale")"
position_x=128
position_y=0
position_rules="$(position_rule_json "$output" "$position_x" "$position_y")"
extra_output=SMOKE-DISPLAYS-MODES
suspend_run_base "display modes"

expect "the display starts at scale 1" 1 scale_of "$output"
expect "the nested compositor adds a monitor for display positions" ok hypr output create headless "$extra_output"
expect_poll "vgs.displays still has outputs after the second monitor appears" present outputs_state
expect_poll "vgs.displays reads the second monitor" present output_present "$extra_output"
extra_base_position="$(position_of "$extra_output")"
extra_position_rules="$(position_rule_json "$extra_output" "$position_x" "$position_y")"
expect "the headless position trial starts" ok invoke_displays trialRules "$extra_position_rules"
token="$(token_of)"
if [[ "$(position_wait "$extra_output" "${position_x}x${position_y}")" == yes ]]; then
  ok "the headless position trial reads back ${position_x}x${position_y}"
  sleep 16
  expect_poll "the guard reverts the headless position trial" "$extra_base_position" position_of "$extra_output"
else
  ok "the headless output does not report position; the sized output proves positions"
  expect "the headless position check is reverted" ok invoke_displays revertTrial "$token"
  expect_poll "the headless position trial state is idle" idle trial_phase
  expect "the sized output position trial starts" ok invoke_displays trialRules "$position_rules"
  token="$(token_of)"
  expect_poll "the sized output position trial reads back ${position_x}x${position_y}" "${position_x}x${position_y}" position_of "$output"
  sleep 16
  expect_poll "the guard reverts the sized output position trial" "$base_position" position_of "$output"
fi
expect "the display trial starts" ok invoke_displays trialRules "$rules"
expect_poll "the trial applies scale $trial_scale" "$trial_scale" scale_of "$output"
token="$(token_of)"
sleep 16
expect_poll "the guard reverts the unkept trial" 1 scale_of "$output"

expect "the second display trial starts" ok invoke_displays trialRules "$rules"
expect_poll "the second trial applies scale $trial_scale" "$trial_scale" scale_of "$output"
token="$(token_of)"
expect "Keep saves the rule" ok invoke_displays keepTrial "{\"token\":\"$token\",\"rules\":$rules}"
expect_poll "the layer holds the saved monitor rule" yes layer_has_rule
if [[ ${#mode_hold_suspended[@]} -gt 0 ]]; then
  expect "the run's held rule is out of the configuration when the kept rule reloads" absent hold_file_state
fi
expect "reload keeps the saved rule" ok hypr reload config-only
expect_poll "the kept rule survives reload" "$trial_scale" scale_of "$output"
expect "clearing saved display rules is allowed" ok invoke_displays clearRules ""
expect_poll "the layer drops the saved monitor rule" no layer_has_rule
expect "reload drops the saved rule" ok hypr reload config-only
release_mode "display modes restores $output" "$output" "$base" 1

expect "the stopped-shell trial starts" ok invoke_displays trialRules "$rules"
expect_poll "the stopped-shell trial applies scale $trial_scale" "$trial_scale" scale_of "$output"
token="$(token_of)"
expect_poll "the detached guard is running before the shell stops" yes guard_running "$token"
kill -STOP "$shell_qs_pid"
expect "the guard path can restore while the shell is stopped" ok output_mode "$output" "$base" 1
expect_poll "the guard reverts while the shell is stopped" yes not_trial_scale "$output"
kill -CONT "$shell_qs_pid"
expect_poll "the shell resumes after the guard control" ok ipc shell ping
expect "the shell clears the stopped-shell trial" ok invoke_displays revertTrial "$token"
expect_poll "the stopped-shell trial state is idle" idle trial_phase

cp -- "$repo/bin/vgshell-display-guard" "$repo/bin/vgshell-display-guard.good"
printf '#!/usr/bin/env bash\nexit 0\n' >"$repo/bin/vgshell-display-guard"
chmod 755 "$repo/bin/vgshell-display-guard"
expect "the control display trial starts" ok invoke_displays trialRules "$rules"
expect_poll "the control trial applies scale $trial_scale" "$trial_scale" scale_of "$output"
token="$(token_of)"
sleep 16
expect "control: a guard that never restores leaves the trial's token held and no guard log" "token=held log=none" guard_left "$token"
mv -f -- "$repo/bin/vgshell-display-guard.good" "$repo/bin/vgshell-display-guard"
release_mode "display modes control restores $output" "$output" "$base" 1

# The row turns $output off and on within one Quickshell j/monitors round
# trip. Quickshell 0.3.1 HyprlandIpc::refreshMonitors in
# src/wayland/hyprland/ipc/connection.cpp can apply a monitors answer
# older than the events, drop $output from its list, and warn at the row's
# next removal of it. Nothing else is lost; the next refresh lists it
# again. When the main output is off and no other is left, Hyprland lists
# FALLBACK, and Quickshell warns when FALLBACK goes because it never
# tracked it.
# An output that goes off before the shell has bound it ends the shell.
# Hyprland 0.56.2 over libwayland 1.26.0 answers the late wl_registry bind
# with `global wl_output (N) is unavailable`, a protocol error, and Qt
# 6.11.2 exits the process on one: the runner logs `The Wayland connection
# experienced a fatal error: Protocol error` and `shell=exited status=255`,
# and Quickshell writes no crash report (this row's off control in a loop
# with no wait, after the hyprland, clipboard and monitor-outputs rows,
# ended the shell at its repeat 17 on 2026-10-11, host cachy; with the
# waits it ran 40). The shell builds a bar only on an output it has
# bound, so the row waits for that bar to go after each rule that turns
# $output off and for it to come back before the next one.
shell_bar_on() { local screens; screens="$(bar_screens)" || return; [[ " $screens " == *" $1 "* ]] && echo yes || echo no; }
display_modes_output_regex_safe() { [[ $output =~ ^[A-Za-z0-9_-]+$ ]] && echo yes || echo no; }
expect "the output name is regex-safe for the warning excuse" yes display_modes_output_regex_safe
expected_errors+=("WARN quickshell\\.hyprland\\.ipc: Got removal for monitor \"(FALLBACK|$output)\" which was not previously tracked\\.")
display_modes_warning_filter_control() {
  local log="$sandbox/display-modes-warning-control.log" output_line extra_line got
  output_line="2026-01-01 00:00:00.000  WARN quickshell.hyprland.ipc: Got removal for monitor \"$output\" which was not previously tracked."
  extra_line="2026-01-01 00:00:00.000  WARN quickshell.hyprland.ipc: Got removal for monitor \"$extra_output\" which was not previously tracked."
  printf '%s\n%s\n' "$output_line" "$extra_line" >"$log"
  got="$(unexpected_log_errors "$log")" || return
  if [[ $got == "$extra_line" ]]; then echo only-other; elif [[ -z $got ]]; then echo none; else printf '%s\n' "$got"; fi
}
expect "control: the same warning for another monitor still fails the log check" only-other display_modes_warning_filter_control
off_rules="$(off_rule_json "$output" "$base")"
expect "the off trial starts" ok invoke_displays trialRules "$off_rules"
expect_poll "the off trial turns $output off" true disabled_of "$output"
expect_poll "the shell drops its bar on $output once it is off" no shell_bar_on "$output"
token="$(token_of)"
expect "Keep saves the off rule" ok invoke_displays keepTrial "{\"token\":\"$token\",\"rules\":$off_rules}"
expect_poll "the layer turns $output off inside its check" yes layer_turns_off "$output"
expect "reload with the headless output on" ok hypr reload config-only
expect_poll "the kept off rule holds while the headless output is on" true disabled_of "$output"
expect "the nested compositor removes the headless output" ok hypr output remove "$extra_output"
expect_poll "the layer turns $output back on when no other output is left" false disabled_of "$output"
expect_poll "the shell holds a bar on $output again before the next off rule" yes shell_bar_on "$output"
expect "reload with $output alone" ok hypr reload config-only
expect_poll "$output stays on after a reload with no other output" false disabled_of "$output"

# Control: the same rule with no check, sent while $output is the only
# output, leaves the session dark; a reload of the layer turns it back on.
expect "control: the unchecked off rule is sent" ok hypr eval "hl.monitor({ output = \"$output\", disabled = true })"
expect_poll "control: an unchecked off rule leaves the only output off" true disabled_of "$output"
expect_poll "the shell drops its bar on $output after the control" no shell_bar_on "$output"
expect "reload after the control" ok hypr reload config-only
expect_poll "the layer turns $output back on after the control" false disabled_of "$output"
expect_poll "the shell holds a bar on $output again after the control" yes shell_bar_on "$output"
expect "clearing the off rule is allowed" ok invoke_displays clearRules ""
expect_poll "the layer drops the off rule" no layer_has_rule
expect "reload drops the off rule" ok hypr reload config-only
release_mode "display modes restores $output after the off rule" "$output" "$base" 1
expect_poll "Quickshell's focused monitor is $output again after the off steps" "\"$output\"" ipc smoke readInstance service vgs.displays focusedOutput

# Colour: the nested panel has no EDID, so sRGB is the one colour mode it
# offers. An sRGB rule goes through trial, Keep and reload with no error
# from Hyprland for its colour fields. The rule takes the window's own
# mode at the whole scale whole_scale_mode picks for it: a host configure
# of the nested window, which another sandbox's window on the host can
# cause at any time, leaves a rule at the window's size as it is, and
# moves the doubled trial mode to the window's size at scale 1.5
# (held_mode_state in mode-hold.sh) before the trial's 15 s are up. The
# service holds no panel reading, so a first HDR trial finds the panels
# unread and asks for them, and the judge then refuses HDR before it
# reaches Hyprland.
colour_mode_scale="$(whole_scale_mode "$base")"
colour_mode="${colour_mode_scale% *}"
colour_scale="${colour_mode_scale#* }"
colour_rules="$(colour_rule_json "$output" "$colour_mode" "$colour_scale" srgb)"
expect "the sRGB trial starts" ok invoke_displays trialRules "$colour_rules"
expect_poll "the shell reads the sRGB trial's scale back after Hyprland answers it" "$colour_scale" service_scale_of "$output"
expect "Hyprland answers the sRGB trial with no error" none trial_failure
token="$(token_of)"
expect "Keep saves the sRGB rule" ok invoke_displays keepTrial "{\"token\":\"$token\",\"rules\":$colour_rules}"
expect_poll "the layer sets $output to sRGB" yes layer_sets_colour srgb
expect "Hyprland reloads the sRGB rule with no configuration error" '[]' hypr_reload_errors
expect_poll "the kept sRGB rule's scale survives the reload" "$colour_scale" scale_of "$output"
expect "$output shows sRGB after the reload" srgb preset_of "$output"
# Control: a colour value Hyprland rejects, put in the layer by hand, is
# what the configuration errors read after a reload name.
cp -- "$hypr_layer" "$sandbox/layer-before-colour-control.lua"
printf 'hl.monitor({ output = "%s", cm = "rec709" })\n' "$output" >>"$hypr_layer"
expect "control: a colour value Hyprland rejects is named in the configuration errors" yes reload_names_cm
cp -- "$sandbox/layer-before-colour-control.lua" "$hypr_layer.next" && mv -T -- "$hypr_layer.next" "$hypr_layer"
expect "the layer reloads with no configuration error after the control" '[]' hypr_reload_errors
expect "a first HDR trial finds the panels unread" "refused: monitors.$output support=unread" invoke_displays trialRules "{\"$output\":{\"cm\":\"hdr\"}}"
expect_poll "the judge refuses an HDR trial on a panel without HDR" "refused: monitors.$output.cm=unsupported cm=hdr" invoke_displays trialRules "{\"$output\":{\"cm\":\"hdr\"}}"
expect "the refused HDR trial leaves the trial idle" idle trial_phase
expect "clearing the sRGB rule is allowed" ok invoke_displays clearRules ""
expect_poll "the layer drops the sRGB rule" no layer_has_rule
expect "reload drops the sRGB rule" ok hypr reload config-only
release_mode "display modes restores $output after the colour rule" "$output" "$base" 1
resume_run_base "display modes"

cp -- "$sandbox/shell-before-displays-modes.json" "$user_config.next" && mv -T -- "$user_config.next" "$user_config"
expect "disabling vgs.displays after display modes is allowed" ok ipc shell setPluginEnabled vgs.displays false
display_observer_stop="$(ipc smoke displayEventStop displays-modes-end)" || display_observer_stop=unavailable
display_observer_state="$(ipc smoke displayEventState)" || display_observer_state=unavailable
display_record_call mark displays-row-end "$display_observer_stop" "$display_observer_state" >/dev/null || true
