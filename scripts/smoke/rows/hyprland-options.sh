# Input options a plugin's settings set, rendered into the Hyprland layer
# only when set, and the `hyprland` capability, read back from the nested
# Hyprland through hyprctl and from the acme.hyprland fixture's instance.
# The consent row wired hyprland.lua and the hyprland row left it so; this
# row puts the hypr directory behind a symlink, as a dotfiles checkout
# holds it, and loads the user's own input.lua, one table of several keys,
# after the loading line, then puts the directory, hyprland.lua and
# shell.json back and disables the fixture again. No
# latency is budgeted: each reading polls through expect_poll every 0.2 s
# for up to 5 s.
#
# Control run on 2026-09-30, host cachy, through this row alone after the
# bar and consent rows: a source_tree copy of the shell whose
# PluginLogic.hyprlandSection lists every declared option at its effective
# setting, so the layer writes the manifest's defaults for unset options,
# failed "an unset option keeps Hyprland's default", reading [false, true]:
# Hyprland reported natural_scroll as set by the configuration. The layer
# text rows failed with it.
#
# Control runs on 2026-10-05, host cachy, through this row after the consent
# row, each on a source_tree copy of the shell. A layer that writes its
# values where the file loads, not in the callback, failed "the set
# sensitivity holds over the user's later table", reading [-0.5, true], and
# read the same after the second reload. A callback that keeps no user value
# failed "userValues names the path and the value the user's file gave",
# reading []. A callback that keeps every value it reads failed "no option
# has a user value while the user sets none after the line" and named
# tap_to_click, kb_layout and repeat_rate beside the sensitivity.
#
# The user's own bind on the fixture's key: the capture and the Settings
# Keys row name the file and line, the removal waits for the prompt and
# Undo puts the line back byte for byte. Control runs on 2026-10-06, host
# cachy, through this row after the consent row, each on a source_tree
# copy of the shell: a layer whose recorder records no call site failed
# "the capture names the user's file and line for the key", reading [],
# and the Keys row named "your other shortcuts"; a copy whose restore puts
# the line first and whose Keys row removes without asking failed "Remove
# my line asks before it removes", "the line stays while the confirmation
# asks" and "the user's files, their modes and the symlink are as they
# were".
# inputs: scripts/smoke/fixtures/plugins/acme.hyprland/* scripts/smoke/fixtures/plugins/acme.hyprland-other/* shell/Core/PluginLogic.js shell/Core/HyprlandLayer.js shell/Core/HyprlandState.* shell/Core/KeyCapture.qml shell/Core/Dispatch.js shell/Core/Compositor.qml shell/plugins/vgs.settings/* shell/Ui/controls/BindField.qml shell/Ui/controls/ShortcutField.qml shell/Ui/feedback/LinkText.qml bin/vgshell bin/vgshell-hypr-judge scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail
hypr_lua="$home/.config/hypr/hyprland.lua"
hypr_layer="$home/.local/state/vgshell/hypr/vgs.lua"
user_config="$home/.config/vgshell/shell.json"
fixture_dir="$home/.config/vgshell/plugins/acme.hyprland"
other_fixture_dir="$home/.config/vgshell/plugins/acme.hyprland-other"
mkdir -p "$fixture_dir"
mkdir -p "$other_fixture_dir"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.hyprland/." "$fixture_dir/"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.hyprland-other/." "$other_fixture_dir/"
cp -- "$user_config" "$sandbox/shell-before-options.json"
cp -- "$hypr_lua" "$sandbox/hyprland-before-options.lua"

read_options() { ipc smoke readInstance service acme.hyprland "$1"; }
read_other_options() { ipc smoke readInstance service acme.hyprland-other "$1"; }
# An option as the nested instance holds it: [value, whether a configuration
# line set it]. FIELD is the reply's value field: bool, int, float or str.
option_value() { hypr -j getoption "$1" | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps([v.get(sys.argv[1]), v["set"]]))' "$2"; }
# Each keymap a keyboard of the nested instance is on, once, sorted.
keymaps() { hypr -j devices | py_reply 'import json,sys; print(json.dumps(sorted({k["active_keymap"] for k in json.load(sys.stdin)["keyboards"]})))'; }
user_value_named() { read_options userValues | py_reply 'import json,sys; print(any(v["path"] == sys.argv[1] for v in json.load(sys.stdin)))' "$1"; }
foreign_has() { read_options foreignBinds | py_reply 'import json,sys; print(sys.argv[1] in json.load(sys.stdin))' "$1"; }
# Where the user binds the fixture's key, as the capture answers it:
# [place, line, removable] per user line.
user_bind_rows() { read_options conflict | py_reply 'import json,sys; print(json.dumps([[b["place"], b["line"], b["removable"]] for b in json.load(sys.stdin)["userBinds"]]))'; }
user_bind_line() { if grep -qxF -- 'hl.bind("SUPER + F7", hl.dsp.exec_cmd("true"))' "$user_hypr/hyprland.lua"; then echo yes; else echo no; fi; }
# Whether the Settings window's prompt shows.
removal_asked() { ipc smoke dialogCard window vgs.settings | py_reply 'import json,sys; print(json.load(sys.stdin)["shown"])'; }
reads_active() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["hyprland"]["active"]))'; }
layer_has() { if grep -qxF -- "$1" "$hypr_layer"; then echo yes; else echo no; fi; }
# The user's own files as they stand: the bytes and mode of input.lua and of
# hyprland.lua, and where the hypr directory's symlink points.
user_files() { printf '%s %s %s %s %s\n' "$(sha256sum <"$user_hypr/input.lua")" "$(stat -c %a -- "$user_hypr/input.lua")" "$(sha256sum <"$user_hypr/hyprland.lua")" "$(stat -c %a -- "$user_hypr/hyprland.lua")" "$(readlink -- "$home/.config/hypr")"; }
# The record the layer's callback keeps in the nested Hyprland's Lua state,
# which starts empty at each reload: the answer the shell's own request
# raises, so hyprctl exits 7 with it.
layer_record() { hypr eval 'error(hl.__vgs_options.report(), 0)' || true; }
layer_mentions() { if grep -qF -- "$1" "$hypr_layer"; then echo yes; else echo no; fi; }
hypr_problems() { ipc shell listPlugins | py_reply 'import json,sys; print(json.dumps(sorted(e["error"] for e in json.load(sys.stdin)["errors"] if e["error"].startswith("hyprland: "))))'; }
has_problem() { hypr_problems | py_reply 'import json,sys; print(sys.argv[1] in json.load(sys.stdin))' "$1"; }
config_errors() { hypr -j configerrors | py_reply 'import json,sys; print(json.dumps([e for e in json.load(sys.stdin) if e]))'; }
switch_layout() { ipc acme.hyprland invoke switch "$1"; }
# Merge JSON object WANT into the fixture's plugins row in shell.json.
set_options() {
  python3 - "$user_config" "$1" "$2" <<'PY'
import json, os, sys
path, plugin_id, want = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
config = json.load(open(path))
rows = config.setdefault("plugins", [])
row = next((r for r in rows if r.get("id") == plugin_id), None)
if row is None:
    row = {"id": plugin_id}
    rows.append(row)
row.update(want)
with open(path + ".next", "w") as f:
    json.dump(config, f, indent=2)
os.replace(path + ".next", path)
PY
}
touchpad_status() {
  local names
  names="$(hypr -j devices | py_reply 'import json,sys; print(json.dumps([m["name"] for m in json.load(sys.stdin)["mice"] if "touchpad" in m["name"].lower() or "trackpad" in m["name"].lower()]))')" || return 1
  if [[ $names == "[]" ]]; then
    hypr_problems | py_reply 'import json,sys; want="hyprland: device.touchpad.enabled for acme.hyprland:touchpad skipped: Hyprland lists no touchpad"; print("ok" if want in json.load(sys.stdin) else "missing-problem")'
    return
  fi
  python3 - "$hypr_layer" "$names" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read().splitlines()
names = json.loads(sys.argv[2])
missing = [name for name in names if f'hl.device({{ name = "{name}", enabled = false }})' not in text]
print("ok" if not missing else "missing:" + ",".join(missing))
PY
}

rescan "rescan discovers the options fixture"
expect_poll "the options fixture is known" True plugin_known acme.hyprland
expect_poll "the second options fixture is known" True plugin_known acme.hyprland-other
expect "enabling the options fixture is allowed" ok ipc shell setPluginEnabled acme.hyprland true
expect "enabling the second options fixture is allowed" ok ipc shell setPluginEnabled acme.hyprland-other true
expect_poll "the options fixture builds" True record_exists acme.hyprland
expect_poll "the second options fixture builds" True record_exists acme.hyprland-other
expect_poll "the fixture reads back the exact hyprland members it was given" '"devices,foreignBinds,overridden,resolveKeys,switchKeyboardLayout,userValues"' read_options members
expect_poll "the core reads Hyprland while a plugin holds hyprland" true reads_active
expect_poll "with no option set the layer writes no options section" no layer_mentions "acme.hyprland 0.1.0: input options its settings set"
expect_poll "the fixture's bind is written" yes layer_has 'hl.bind("SUPER + F7", hl.dsp.global("acme.hyprland:ping"), { description = "acme.hyprland:ping" })'

set_options acme.hyprland '{"sensitivity": 0.35, "tapToClick": false, "layouts": "us,de", "repeatRate": 40, "touchpad": false}'
expect_poll "the set options are one hl.config in the manifest's order, inside the callback" yes layer_has '        hl.config({ input = { sensitivity = 0.35, touchpad = { tap_to_click = false }, kb_layout = "us,de", repeat_rate = 40 } })'
expect_poll "the touchpad option writes each listed touchpad or reports none" ok touchpad_status
expect_poll "the set sensitivity reads back through getoption" '[0.35, true]' option_value input:sensitivity float
expect_poll "the set tap-to-click reads back through its Lua name" '[false, true]' option_value input:touchpad:tap_to_click bool
expect_poll "the set layouts read back" '["us,de", true]' option_value input:kb_layout str
expect_poll "the set repeat rate reads back" '[40, true]' option_value input:repeat_rate int
expect "an unset option keeps Hyprland's default" '[false, false]' option_value input:natural_scroll bool
expect "the layer writes no unset option" no layer_mentions natural_scroll
expect "the options hold no configuration error" '[]' config_errors
expect_poll "no option is overridden while the user sets none after the line" '[]' read_options overridden
expect_poll "no option has a user value while the user sets none after the line" '[]' read_options userValues
expect_poll "the layer's own bind is no foreign bind" False foreign_has SUPER+F7

set_options acme.hyprland '{"repeatRate": 2.5}'
expect_poll "listPlugins reports the fractional repeat rate refusal" True has_problem 'hyprland: input.repeat_rate for acme.hyprland:repeatRate skipped: want=whole-number'
set_options acme.hyprland '{"repeatRate": 40}'

set_options acme.hyprland-other '{"sensitivity": -0.25, "repeatDelay": 900}'
expect_poll "listPlugins reports the second fixture's option conflict" True has_problem 'hyprland: input.sensitivity for acme.hyprland-other:sensitivity skipped: already set by acme.hyprland'

# The user's own configuration after the loading line: the value a setting
# set holds over it, its other keys keep the user's, no file of the user's
# changes, and the capability names the value the user's file gave.
user_hypr="$sandbox/dotfiles-hypr"
mv -T -- "$home/.config/hypr" "$user_hypr"
ln -s -- "$user_hypr" "$home/.config/hypr"
printf '%s\n' 'hl.config({' '    input = {' '        accel_profile = "flat",' '        sensitivity = -0.5,' '        repeat_delay = 700,' '    },' '})' >"$user_hypr/input.lua"
chmod 640 -- "$user_hypr/input.lua"
printf '%s\n' "dofile(\"$home/.config/hypr/input.lua\")" 'hl.bind("SUPER + F7", hl.dsp.exec_cmd("true"))' >>"$hypr_lua"
user_before="$(user_files)" || fail "the user's files are readable before the reload"
expect "the nested instance reloads with the user's lines" ok hypr reload config-only
expect_poll "the set sensitivity holds over the user's later table" '[0.35, true]' option_value input:sensitivity float
expect_poll "the user's other key of that table keeps the user's value" '["flat", true]' option_value input:accel_profile str
expect_poll "the second fixture's repeat delay holds over the user's" '[900, true]' option_value input:repeat_delay int
expect_poll "userValues names the path and the value the user's file gave" '[{"path":"input.sensitivity","value":-0.5}]' read_options userValues
expect "the layer changed an option the user's file leaves alone" '[false, true]' option_value input:touchpad:tap_to_click bool
expect "an option the user's file leaves alone has no user value" False user_value_named input.touchpad.tap_to_click
expect_poll "an option that holds is not overridden" '[]' read_options overridden
expect_poll "the second fixture lists only its own user value" '[{"path":"input.repeat_delay","value":700}]' read_other_options userValues
expect_poll "the second fixture's lost path is its one overridden path" '["input.sensitivity"]' read_other_options overridden
expect_poll "a user bind on the same key shows in foreignBinds" True foreign_has SUPER+F7

# The user's bind on the fixture's key: the capture and the Settings Keys
# row name its file and line, Remove my line takes the line out only once
# the confirmation is answered, and Undo puts it back; the user's files
# reading as they were below proves the bytes, the mode and the symlink.
bind_line="$(wc -l <"$user_hypr/hyprland.lua")"
expect_poll "the capture names the user's file and line for the key" "[[\"~/.config/hypr/hyprland.lua\", $bind_line, true]]" user_bind_rows
settings_page_open acme.hyprland
expect_poll "the Keys row's line names the user's file and line" "\"Also used by your Hyprland config at ~/.config/hypr/hyprland.lua line $bind_line.\"" key_field acme.hyprland ping conflict
expect_poll "the Keys row's line links the user's file and line" "\"~/.config/hypr/hyprland.lua line $bind_line\"" key_field acme.hyprland ping hintLink
settings_press "Remove my line" || fail "the click on Remove my line failed"
expect_poll "Remove my line asks before it removes" True removal_asked
expect "the line stays while the confirmation asks" yes user_bind_line
click_in window:Plugins window vgs.settings Button "Remove line" || fail "the click on Remove line failed"
expect_poll "the answer closes the prompt" False removal_asked
expect_poll "the confirmed removal takes the line out of the user's hyprland.lua" no user_bind_line
expect_poll "the user's bind leaves Hyprland" False foreign_has SUPER+F7
expect "the hypr directory stays a symlink to the user's directory" "$user_hypr" readlink -- "$home/.config/hypr"
expect "the removal holds no configuration error" '[]' config_errors
settings_press "Undo" || fail "the click on Undo failed"
expect_poll "Undo puts the user's line back" yes user_bind_line
expect_poll "the user's bind holds the key again" True foreign_has SUPER+F7
settings_page_close acme.hyprland
expect "the user's lines hold no configuration error" '[]' config_errors
expect "a second reload is accepted" ok hypr reload
expect "the set sensitivity holds after the second reload" '[0.35, true]' option_value input:sensitivity float
expect "the new Lua state holds the same record" 'error: vgs-user-values=[{"path":"input.repeat_delay","value":700},{"path":"input.sensitivity","value":-0.5}]' layer_record
expect_poll "userValues is the same after the second reload" '[{"path":"input.sensitivity","value":-0.5}]' read_options userValues
expect "the second reload holds no configuration error" '[]' config_errors
expect "the user's files, their modes and the symlink are as they were" "$user_before" user_files

# Two layouts: the switch moves every keyboard, and the devices follow.
expect_poll "the keyboards start on the first layout" '["English (US)"]' keymaps
expect_poll "the fixture reads the first layout" '["English (US)"]' read_options keymaps
expect "switchKeyboardLayout('next') is accepted" ok switch_layout next
expect_poll "the next layout is the active keymap in devices -j" '["German"]' keymaps
expect_poll "the fixture's devices follow the switch" '["German"]' read_options keymaps
expect "switchKeyboardLayout(0) is accepted" ok switch_layout 0
expect_poll "the first layout is active again" '["English (US)"]' keymaps
expected_errors+=('compositor: refused: layout=')
expect "a target that is no layout is refused" 'refused: layout="up" want=next|prev|index' switch_layout up
expect "the switches hold no configuration error" '[]' config_errors

# Leave the sandbox as the row found it.
unlink -- "$home/.config/hypr"
unlink -- "$user_hypr/input.lua"
mv -T -- "$user_hypr" "$home/.config/hypr"
cp -- "$sandbox/hyprland-before-options.lua" "$hypr_lua.next" && mv -T -- "$hypr_lua.next" "$hypr_lua"
expect "the nested instance reloads without the user's lines" ok hypr reload config-only
cp -- "$sandbox/shell-before-options.json" "$user_config.next" && mv -T -- "$user_config.next" "$user_config"
expect "disabling the options fixture is allowed" ok ipc shell setPluginEnabled acme.hyprland false
expect "disabling the second options fixture is allowed" ok ipc shell setPluginEnabled acme.hyprland-other false
expect_poll "the options fixture is disabled" False plugin_enabled acme.hyprland
expect_poll "the second options fixture is disabled" False plugin_enabled acme.hyprland-other
expect_poll "the disabled fixture's options leave the layer" no layer_mentions "acme.hyprland"
expect_poll "the layer's sensitivity leaves Hyprland" '[0.0, false]' option_value input:sensitivity float
expect_poll "the layouts are Hyprland's own again" '["us", false]' option_value input:kb_layout str
expect_poll "the core stops reading Hyprland once no plugin holds hyprland" false reads_active
expect "the configuration after the options rows holds no error" '[]' config_errors
