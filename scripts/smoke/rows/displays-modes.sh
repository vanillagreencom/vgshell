# System -> Displays monitor-mode writes: the plugin's monitor trial applies
# a nested output rule, the detached guard reverts it when it is not kept,
# Keep saves it into the generated layer, a position trial reverts, and the
# guard still reverts while the shell is stopped. A kept rule that turns
# the main output off holds while the headless output stays on, the layer
# turns the main output back on when that output goes, and a reload with
# the main output alone leaves it on. An sRGB colour rule goes through
# trial, Keep and reload, and the judge refuses an HDR trial, since the
# nested panel has no EDID. The row uses WAYLAND-1, whose nested
# backend takes any mode and integer scale. The nested headless output
# takes no mirror rule, so the unit rows alone hold Mirror. Each poll reads
# every 0.2 s for up to 5 s.
# Control run on 2026-10-06, host cachy, through this row after the setup
# rows: a guard copy that exits before restore leaves the trial scale in
# place and the control reports the defect.
# Control run on 2026-10-06, host cachy, through this row after the setup
# rows: a rule that turns the main output off with no check, sent while it
# is the only output, leaves it off, and the control reports the defect;
# a reload of the layer turns it back on.
# Control run on 2026-10-06, host cachy, through this row after the setup
# rows: an HDR rule sent with no judge is answered ok, and Hyprland shows
# sRGB in its place, the fallback the judge's refusal spares the user.
# inputs: shell/plugins/vgs.displays/* shell/Core/MonitorState.qml shell/Core/MonitorLogic.js shell/Core/HyprlandLayer.js shell/Core/Dispatch.js shell/Core/Compositor.qml bin/vgshell-display-guard
set -euo pipefail

user_config="$home/.config/vgshell/shell.json"
hypr_layer="$home/.local/state/vgshell/hypr/vgs.lua"
cp -- "$user_config" "$sandbox/shell-before-displays-modes.json"

read_displays() { ipc smoke readInstance service vgs.displays "$1"; }
invoke_displays() { ipc smoke invokeInstance service vgs.displays "$1" "$2"; }
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
not_base_scale() { [[ "$(scale_of "$1")" == 1 ]] && echo no || echo yes; }
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
layer_sets_colour() { grep -q -F -- "cm = \"$1\"" "$hypr_layer" && echo yes || echo no; }
colour_rule_json() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
name, mode, cm = sys.argv[1], sys.argv[2], sys.argv[3]
w, h = map(int, mode.split("x"))
print(json.dumps({name: {"mode": {"width": w, "height": h, "refresh": 60}, "position": {"x": 0, "y": 0}, "scale": 1, "transform": 0, "cm": cm}}))
PY
}

expect "enabling vgs.displays for display modes is allowed" ok ipc shell setPluginEnabled vgs.displays true
expect_poll "vgs.displays is built for display modes" True record_exists vgs.displays
expect_poll "vgs.displays has outputs" present outputs_state

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
expect "control: a guard that never restores leaves a non-restored scale" yes not_base_scale "$output"
mv -f -- "$repo/bin/vgshell-display-guard.good" "$repo/bin/vgshell-display-guard"
release_mode "display modes control restores $output" "$output" "$base" 1

# Use this display: the headless output stays on, so the main one may go
# off; the layer turns it off only while another output is on. While the
# main output is off and no other is left, Hyprland lists FALLBACK, and
# Quickshell 0.3.1 warns when it goes, since it never tracked it.
expected_errors+=('WARN quickshell\.hyprland\.ipc: Got removal for monitor "FALLBACK" which was not previously tracked\.')
off_rules="$(off_rule_json "$output" "$base")"
expect "the off trial starts" ok invoke_displays trialRules "$off_rules"
expect_poll "the off trial turns $output off" true disabled_of "$output"
token="$(token_of)"
expect "Keep saves the off rule" ok invoke_displays keepTrial "{\"token\":\"$token\",\"rules\":$off_rules}"
expect_poll "the layer turns $output off inside its check" yes layer_turns_off "$output"
expect "reload with the headless output on" ok hypr reload config-only
expect_poll "the kept off rule holds while the headless output is on" true disabled_of "$output"
expect "the nested compositor removes the headless output" ok hypr output remove "$extra_output"
expect_poll "the layer turns $output back on when no other output is left" false disabled_of "$output"
expect "reload with $output alone" ok hypr reload config-only
expect_poll "$output stays on after a reload with no other output" false disabled_of "$output"

# Control: the same rule with no check, sent while $output is the only
# output, leaves the session dark; a reload of the layer turns it back on.
expect "control: the unchecked off rule is sent" ok hypr eval "hl.monitor({ output = \"$output\", disabled = true })"
expect_poll "control: an unchecked off rule leaves the only output off" true disabled_of "$output"
expect "reload after the control" ok hypr reload config-only
expect_poll "the layer turns $output back on after the control" false disabled_of "$output"
expect "clearing the off rule is allowed" ok invoke_displays clearRules ""
expect_poll "the layer drops the off rule" no layer_has_rule
expect "reload drops the off rule" ok hypr reload config-only
release_mode "display modes restores $output after the off rule" "$output" "$base" 1

# Colour: the nested panel has no EDID, so sRGB is the one colour mode it
# offers. An sRGB rule goes through trial, Keep and reload; an HDR trial is
# refused before it reaches Hyprland.
expect "the sRGB trial starts" ok invoke_displays trialRules "$(colour_rule_json "$output" "$base" srgb)"
expect_poll "the sRGB trial holds" holding trial_phase
token="$(token_of)"
expect "Keep saves the sRGB rule" ok invoke_displays keepTrial "{\"token\":\"$token\",\"rules\":$(colour_rule_json "$output" "$base" srgb)}"
expect_poll "the layer sets $output to sRGB" yes layer_sets_colour srgb
expect "reload with the sRGB rule" ok hypr reload config-only
expect_poll "$output shows sRGB after the reload" srgb preset_of "$output"
expect "the judge refuses an HDR trial on a panel without HDR" "refused: monitors.$output.cm=unsupported cm=hdr" invoke_displays trialRules "{\"$output\":{\"cm\":\"hdr\"}}"
expect "the refused HDR trial leaves the trial idle" idle trial_phase
# Control: the same HDR rule with no judge is taken, and Hyprland shows
# sRGB in its place with no error.
expect "control: the unjudged HDR rule is sent" ok hypr eval "hl.monitor({ output = \"$output\", cm = \"hdr\" })"
expect_poll "control: Hyprland answers ok to the unjudged HDR rule and still shows sRGB" srgb preset_of "$output"
expect "clearing the sRGB rule is allowed" ok invoke_displays clearRules ""
expect_poll "the layer drops the sRGB rule" no layer_has_rule
expect "reload drops the sRGB rule" ok hypr reload config-only
release_mode "display modes restores $output after the colour rule" "$output" "$base" 1

cp -- "$sandbox/shell-before-displays-modes.json" "$user_config.next" && mv -T -- "$user_config.next" "$user_config"
expect "disabling vgs.displays after display modes is allowed" ok ipc shell setPluginEnabled vgs.displays false
