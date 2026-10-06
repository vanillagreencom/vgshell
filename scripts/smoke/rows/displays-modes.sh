# System -> Displays monitor-mode writes: the plugin's monitor trial applies
# a nested output rule, the detached guard reverts it when it is not kept,
# Keep saves it into the generated layer, and the guard still reverts while
# the shell is stopped. The row uses WAYLAND-1, whose nested backend takes any
# mode and integer scale. Each poll reads every 0.2 s for up to 5 s.
# Control run on 2026-10-06, host cachy, through this row after the setup
# rows: a guard copy that exits before restore leaves the trial scale in
# place and the control reports the defect.
# inputs: shell/plugins/vgs.displays/* shell/Core/MonitorState.qml shell/Core/MonitorLogic.js shell/Core/HyprlandLayer.js shell/Core/Dispatch.js shell/Core/Compositor.qml bin/vgshell-display-guard
set -euo pipefail

user_config="$home/.config/vgshell/shell.json"
hypr_layer="$home/.local/state/vgshell/hypr/vgs.lua"
cp -- "$user_config" "$sandbox/shell-before-displays-modes.json"

read_displays() { ipc smoke readInstance service vgs.displays "$1"; }
invoke_displays() { ipc smoke invokeInstance service vgs.displays "$1" "$2"; }
outputs_state() { read_displays outputs | py_reply 'import json,sys; value=json.load(sys.stdin); print("present" if isinstance(value, list) and value else "absent")'; }
scale_of() { hypr -j monitors all | py_reply 'import json,sys; rows=[m for m in json.load(sys.stdin) if m["name"]==sys.argv[1]]; print(rows[0]["scale"] if rows else "absent")' "$1"; }
mode_of() { hypr -j monitors all | py_reply 'import json,sys; rows=[m for m in json.load(sys.stdin) if m["name"]==sys.argv[1]]; print("%dx%d" % (rows[0]["width"], rows[0]["height"]) if rows else "absent")' "$1"; }
token_of() { read_displays trialState | py_reply 'import json,sys; print(json.load(sys.stdin).get("token",""))'; }
rule_json() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
name, mode, scale = sys.argv[1], sys.argv[2], float(sys.argv[3])
w, h = map(int, mode.split("x"))
print(json.dumps({name: {"mode": {"width": w, "height": h, "refresh": 60}, "position": {"x": 0, "y": 0}, "scale": scale, "transform": 0, "disabled": False}}))
PY
}
layer_has_rule() { grep -q -E 'hl\.monitor[[:space:]]*\(' "$hypr_layer" && echo yes || echo no; }

expect "enabling vgs.displays for display modes is allowed" ok ipc shell setPluginEnabled vgs.displays true
expect_poll "vgs.displays is built for display modes" True record_exists vgs.displays
expect_poll "vgs.displays has outputs" present outputs_state

output="$(first_name)"
base="$(unscaled_mode_of "$output")"
trial_mode="$(hidpi_mode_of "$output")"
trial_scale=2
rules="$(rule_json "$output" "$trial_mode" "$trial_scale")"

expect "the display starts at scale 1" 1 scale_of "$output"
expect "the display trial starts" ok invoke_displays trialRules "$rules"
expect_poll "the trial applies scale $trial_scale" "$trial_scale" scale_of "$output"
token="$(token_of)"
sleep 16
expect_poll "the guard reverts the unkept trial" 1 scale_of "$output"
expect "the shell observes the reverted trial" ok invoke_displays revertTrial "$token"

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
sleep 1
kill -STOP "$shell_qs_pid"
sleep 20
expect_poll "the guard reverts while the shell is stopped" 1 scale_of "$output"
kill -CONT "$shell_qs_pid"
expect_poll "the shell resumes after the guard control" ok ipc shell ping
expect "the shell observes the stopped-shell revert" ok invoke_displays revertTrial "$token"

cp -- "$repo/bin/vgshell-display-guard" "$repo/bin/vgshell-display-guard.good"
printf '#!/usr/bin/env bash\nexit 0\n' >"$repo/bin/vgshell-display-guard"
chmod 755 "$repo/bin/vgshell-display-guard"
expect "the control display trial starts" ok invoke_displays trialRules "$rules"
expect_poll "the control trial applies scale $trial_scale" "$trial_scale" scale_of "$output"
token="$(token_of)"
sleep 16
expect "control: a guard that never restores leaves the trial scale" "$trial_scale" scale_of "$output"
expect "the shell clears the control trial" ok invoke_displays revertTrial "$token"
mv -f -- "$repo/bin/vgshell-display-guard.good" "$repo/bin/vgshell-display-guard"
release_mode "display modes control restores $output" "$output" "$base" 1

cp -- "$sandbox/shell-before-displays-modes.json" "$user_config.next" && mv -T -- "$user_config.next" "$user_config"
expect "disabling vgs.displays after display modes is allowed" ok ipc shell setPluginEnabled vgs.displays false
