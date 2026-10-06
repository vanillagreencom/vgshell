# System -> Displays monitor-mode writes: the plugin's monitor trial applies
# a nested output rule, the detached guard reverts it when it is not kept,
# Keep saves it into the generated layer, a position trial reverts, and the
# guard still reverts while the shell is stopped. The row uses WAYLAND-1,
# whose nested backend takes any mode and integer scale. Each poll reads every
# 0.2 s for up to 5 s.
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

cp -- "$sandbox/shell-before-displays-modes.json" "$user_config.next" && mv -T -- "$user_config.next" "$user_config"
expect "disabling vgs.displays after display modes is allowed" ok ipc shell setPluginEnabled vgs.displays false
expect "the nested compositor removes the display position monitor" ok hypr output remove "$extra_output"
