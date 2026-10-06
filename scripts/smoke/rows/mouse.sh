# vgs.mouse maps pointer and touchpad settings through the Hyprland options
# layer. The row runs in the nested sandbox only. It enables the plugin,
# drives the pane's real pointer-speed slider through the probe geometry and
# a click, reads the nested Hyprland option, checks an untouched option, adds
# a user table of two keys after the VGS loading line, reads that the pane's
# value holds over it, that the row names the user's value in the message
# under it and that the slider keeps its width, clicks the row's one action
# and reads the setting gone and the user's value back, waits
# for Hyprland devices before checking the no-touchpad view and published
# status, clicks the bar widget to open the flyout through surfaces, changes
# the same slider from the keyboard, and installs a disposable vgs.mouse copy
# whose pane writes sensitivity with hyprctl instead of configure.set.
#
# Control run on 2026-10-05, host cachy, through this row with
# hyprland-consent: the disposable vgs.mouse copy removed hyprland.options for
# sensitivity and made MouseControls.setValue run hyprctl eval for the slider.
# The same slider drove getoption to the requested value, but the generated
# layer held no vgs.mouse option section, so the row's real option contract
# check went red on that copy. The control expects that red result.
#
# Control run on 2026-10-05, host cachy, through this row after the consent
# row: a source_tree copy of the shell whose PluginLogic.withoutSetting
# removes no key failed "the action removes the setting from the bar entry
# and the plugins row", reading [0.55, 0.55], and getoption kept 0.55.
# inputs: shell/plugins/vgs.mouse/* shell/plugins/vgs.system/* shell/Core/PluginLogic.js shell/Core/HyprlandLayer.* shell/Core/HyprlandState.* shell/Core/Capabilities.qml shell/Core/PluginStatus.qml shell/Hosts/PaneHost.qml shell/Ui/controls/Slider.qml shell/Ui/controls/Switch.qml shell/Ui/controls/SegmentedControl.qml shell/Ui/controls/FormRow.qml shell/Ui/layout/DeviceRow.qml bin/vgshell scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail

mouse_file="$home/.config/vgshell/shell.json"
mouse_saved="$sandbox/shell-before-mouse.json"
mouse_hypr="$home/.config/hypr/hyprland.lua"
mouse_layer="$home/.local/state/vgshell/hypr/vgs.lua"
mouse_copy="$home/.config/vgshell/plugins/vgs.mouse"
cp -- "$mouse_file" "$mouse_saved"
hypr_lua_save mouse
mouse_system_was="$(plugin_enabled vgs.system)" || fail "vgs.system's enabled state is unreadable"
mouse_was="$(plugin_enabled vgs.mouse)" || fail "vgs.mouse's enabled state is unreadable"

mouse_option() { hypr -j getoption "$1" | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps([v.get(sys.argv[1]), v["set"]]))' "$2"; }
mouse_placed() { bar_widget_ids | py_reply 'import json,sys; print(any("vgs.mouse" in ids for ids in json.load(sys.stdin)))'; }
mouse_text_count() { ipc smoke itemTextCount window vgs.mouse "$1" "$2"; }
# How many shown hint lines directly under a key/value row of the pane
# read TEXT: a row's message, and no chip's label.
mouse_messages() { ipc smoke descendantGeometry window vgs.mouse | py_reply '
import json, sys
items = json.load(sys.stdin)
print(sum(1 for i in items if i["type"] == "Label" and i.get("role") == "hint" and i["visible"] and i.get("text") == sys.argv[1] and items[i["parent"]].get("name") == "fieldRow"))' "$1"; }
mouse_slider_width() { ipc smoke descendantGeometry window vgs.mouse | py_reply 'import json,sys; r=[i["box"][2] for i in json.load(sys.stdin) if i["type"] == "Slider" and i["visible"]]; print(r[0] if r else "absent")'; }
# The boxes of the drawn "use my Hyprland value" actions, as a JSON list.
mouse_actions() { ipc smoke descendantGeometry window vgs.mouse | py_reply 'import json,sys; print(json.dumps([i["box"] for i in json.load(sys.stdin) if i["name"] == "useHyprlandValue" and i["visible"]]))'; }
mouse_action_count() { mouse_actions | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
# The centre of the first drawn action once two readings 0.1 s apart match:
# the row that holds it has just appeared, and the pane lays out again.
mouse_action_point() {
  local rect now last=""
  for _ in $(seq 1 30); do
    rect="$(mouse_actions | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[0]))')" && now="$(at_centre window:System "$rect")" || return 1
    [[ $now == "$last" ]] && { echo "$now"; return 0; }
    last="$now"
    sleep 0.1
  done
  echo "mouse_action_point: unsettled at $now" >&2
  return 1
}
# The sensitivity the user file holds for Mouse, in its bar entry and in its
# plugins row, each `absent` when the file gives none.
mouse_saved_sensitivity() {
  python3 -c 'import json,sys
config = json.load(open(sys.argv[1]))
entries = [e for section in config.get("bar", {}).get("layout", {}).values() for e in section if e.get("id") == "vgs.mouse"]
rows = [r for r in config.get("plugins", []) if r.get("id") == "vgs.mouse"]
print(json.dumps([e.get("sensitivity", "absent") for e in entries] + [r.get("sensitivity", "absent") for r in rows]))' "$mouse_file"
}
mouse_layer_mentions() { if grep -qF -- "$1" "$mouse_layer"; then echo yes; else echo no; fi; }
mouse_status_published() { ipc smoke statusValues vgs.mouse | py_reply 'import json,sys; d=json.load(sys.stdin).get("devices"); print("ok" if isinstance(d, dict) and d.get("hasTouchpad") is False and isinstance(d.get("devices"), list) else "bad")'; }
mouse_slider_point() {
  local rect
  rect="$(ipc smoke descendantGeometry window vgs.mouse | py_reply 'import json,sys; r=[i["box"] for i in json.load(sys.stdin) if i["type"] == "Slider" and i["visible"]]; print(json.dumps(r[0]) if r else "absent")')" || return 1
  [[ $rect == \[* ]] || { echo "mouse_slider_point: no slider: $rect" >&2; return 1; }
  read -r x y < <(at_centre window:System "$rect") || return 1
  python3 -c 'import json,sys; r=json.loads(sys.argv[1]); print(int(int(sys.argv[2]) - r[2] / 2 + r[2] * float(sys.argv[4])), sys.argv[3])' "$rect" "$x" "$y" "$1"
}
mouse_widget_point() { local rect; rect="$(ipc smoke instanceGeometry "$(bar_key)" vgs.mouse)" && at_centre vgs:bar "$rect"; }
mouse_focus() { ipc smoke activeFocusItem window vgs.mouse; }
mouse_contract() {
  local want="$1" got layer
  got="$(mouse_option input:sensitivity float)" || return
  layer="$(mouse_layer_mentions 'vgs.mouse 0.1.0: input options its settings set')" || return
  [[ $got == "$want" && $layer == yes ]] && echo ok || printf 'option=%s layer=%s\n' "$got" "$layer"
}
mouse_control_option() {
  local got
  got="$(mouse_option input:sensitivity float)" || return
  [[ $got == '[0.5, true]' ]] && echo ok || printf 'option=%s\n' "$got"
}
mouse_panel_built() { ipc shell built | py_reply 'import json,sys; print(sum(1 for r in json.load(sys.stdin).get("panel", []) if r["id"] == "vgs.mouse"))'; }

expect "enabling the System window is allowed" ok ipc shell setPluginEnabled vgs.system true
expect "enabling Mouse is allowed" ok ipc shell setPluginEnabled vgs.mouse true
expect_poll "the Mouse widget is placed in the bar" True mouse_placed
expect_poll "the Mouse pane can be summoned" ok ipc shell summon window vgs.system '{"pane":"vgs.mouse"}'
expect_poll "the Mouse pane is mounted" '["vgs.mouse"]' window_panes
expect_poll "Hyprland devices are read before Mouse checks touchpads" true ipc smoke readInstance service vgs.mouse devicesRead
expect_poll "the sandbox has no touchpad section" 0 mouse_text_count SectionHeader Touchpad
expect_poll "the Mouse service publishes its status value" ok mouse_status_published

read -r sx sy < <(mouse_slider_point 0.75) || fail "the Mouse pointer-speed slider has no box"
hover "$sx" "$sy" || fail "hovering the Mouse pointer-speed slider failed"
click "$sx" "$sy" || fail "clicking the Mouse pointer-speed slider failed"
expect_poll "a pane write reaches nested Hyprland sensitivity" '[0.55, true]' mouse_option input:sensitivity float
expect "an untouched natural-scroll option keeps Hyprland's default" '[false, false]' mouse_option input:natural_scroll bool
expect "the layer writes no untouched natural-scroll option" no mouse_layer_mentions natural_scroll
expect_poll "the Mouse layer records the sensitivity option" ok mouse_contract '[0.55, true]'

expect "the user file holds the pane's sensitivity in the bar entry and the plugins row" '[0.55, 0.55]' mouse_saved_sensitivity
expect "no row offers the user's Hyprland value while the user's config sets none" 0 mouse_action_count
mouse_width="$(mouse_slider_width)" || fail "the Mouse pointer-speed slider's width is unreadable"
expect "the pane shows no message before the user table" 0 mouse_messages 'Your Hyprland config sets this to -0.50×'
printf '%s\n' 'hl.config({ input = { accel_profile = "flat", sensitivity = -0.5 } })' >>"$mouse_hypr"
expect "the nested instance reloads with the user Mouse table" ok hypr reload config-only
expect_poll "the pane's sensitivity holds over the user Mouse table" '[0.55, true]' mouse_option input:sensitivity float
expect_poll "the user's other key of that table keeps the user's value" '["flat", true]' mouse_option input:accel_profile str
expect_poll "the pointer speed row names the user's value in the message under it" 1 mouse_messages 'Your Hyprland config sets this to -0.50×'
expect "the message leaves the pointer-speed slider its width" "$mouse_width" mouse_slider_width
expect_poll "the pointer speed row alone offers the user's Hyprland value" 1 mouse_action_count
read -r ax ay < <(mouse_action_point) || fail "the Mouse action has no box"
hover "$ax" "$ay" || fail "hovering the Mouse action failed"
click "$ax" "$ay" || fail "clicking the Mouse action failed"
expect_poll "the action removes the setting from the bar entry and the plugins row" '["absent", "absent"]' mouse_saved_sensitivity
expect_poll "with the setting gone getoption reads the user's value again" '[-0.5, true]' mouse_option input:sensitivity float
expect_poll "the layer writes no Mouse option once the setting is gone" no mouse_layer_mentions 'vgs.mouse 0.1.0: input options its settings set'
expect_poll "no row offers the user's Hyprland value once VGS sets none" 0 mouse_action_count
expect_poll "the row names no user value once VGS sets none" 0 mouse_messages 'Your Hyprland config sets this to -0.50×'
hypr_lua_restore mouse || fail "hyprland.lua is put back after the Mouse override read"
expect "the nested instance reloads without the Mouse override line" ok hypr reload config-only

expect "the Mouse pane closes before the widget flyout" ok ipc shell hide window vgs.system
read -r wx wy < <(mouse_widget_point) || fail "the Mouse widget has no box"
hover "$wx" "$wy" || fail "hovering the Mouse widget failed"
click "$wx" "$wy" || fail "clicking the Mouse widget failed"
expect_poll "the widget opens its flyout through surfaces" 1 mouse_panel_built
expect "hiding the Mouse flyout is allowed" ok ipc shell hide panel vgs.mouse
expect_poll "the Mouse flyout is gone after hide" 0 mouse_panel_built

expect "the Mouse pane opens for keyboard control" ok ipc shell summon window vgs.system '{"pane":"vgs.mouse"}'
expect_poll "the Mouse pane is mounted for keyboard control" '["vgs.mouse"]' window_panes
expect_poll "the keyboard starts on the pointer speed slider" '["Slider",null]' mouse_focus
type_keys -k Home || fail "Home on the Mouse pointer-speed slider failed"
expect_poll "Home on the slider writes -1" '[-1.0, true]' mouse_option input:sensitivity float
type_keys -k End || fail "End on the Mouse pointer-speed slider failed"
expect_poll "End on the slider writes 1" '[1.0, true]' mouse_option input:sensitivity float
expect "disabling Mouse before the direct-hyprctl control is allowed" ok ipc shell setPluginEnabled vgs.mouse false
expect_poll "the Mouse layer option leaves before the direct-hyprctl control" no mouse_layer_mentions 'vgs.mouse 0.1.0: input options its settings set'

rm -rf -- "${mouse_copy:?}"
cp -R -- "$repo/shell/plugins/vgs.mouse" "$mouse_copy"
python3 - "$mouse_copy" <<'PY'
import json, os, sys
root = sys.argv[1]
path = os.path.join(root, "manifest.json")
doc = json.load(open(path))
doc["hyprland"]["options"].pop("sensitivity")
json.dump(doc, open(path, "w"))
controls = os.path.join(root, "MouseControls.qml")
text = open(controls).read()
text = text.replace("import QtQuick\n", "import QtQuick\nimport Quickshell\n")
old = '''    function setValue(key, value) {
        const reply = shell.configure.set(key, value);
        problem = reply === "ok" ? "" : "VGS could not save this setting.";
        if (reply !== "ok") console.warn("mouse: configure " + reply);
        return reply;
    }'''
new = '''    function setValue(key, value) {
        if (key === "sensitivity") {
            Quickshell.execDetached(["hyprctl", "eval", "hl.config({ input = { sensitivity = " + value + " } })"]);
            return "ok";
        }
        const reply = shell.configure.set(key, value);
        problem = reply === "ok" ? "" : "VGS could not save this setting.";
        if (reply !== "ok") console.warn("mouse: configure " + reply);
        return reply;
    }'''
assert text.count(old) == 1, old
open(controls, "w").write(text.replace(old, new))
PY
rescan "rescan discovers the bad Mouse control copy"
expect "enabling the bad Mouse control copy is allowed" ok ipc shell setPluginEnabled vgs.mouse true
expect_poll "the bad Mouse control copy is enabled" True plugin_enabled vgs.mouse
expect "the bad Mouse pane opens for the control" ok ipc shell summon window vgs.system '{"pane":"vgs.mouse"}'
expect_poll "the bad Mouse pane is mounted for the control" '["vgs.mouse"]' window_panes
read -r cx cy < <(mouse_slider_point 0.75) || fail "the bad Mouse pointer-speed slider has no box"
hover "$cx" "$cy" || fail "hovering the bad Mouse pointer-speed slider failed"
click "$cx" "$cy" || fail "clicking the bad Mouse pointer-speed slider failed"
expect_poll "control: the bad copy's direct hyprctl write reaches Hyprland" ok mouse_control_option
if [[ $(mouse_contract '[0.55, true]') == ok ]]; then
  fail "control: direct hyprctl copy satisfied the layer-backed Mouse contract"
else
  ok "control: direct hyprctl copy turns the layer-backed Mouse contract red"
fi
expect "hiding the bad Mouse pane is allowed" ok ipc shell hide window vgs.system
rm -rf -- "${mouse_copy:?}"
rescan "rescan removes the bad Mouse control copy"

cp -- "$mouse_saved" "$mouse_file.next" && mv -T -- "$mouse_file.next" "$mouse_file"
expect "the configuration reloads as the row found it" ok ipc shell reloadConfig
expect_poll "vgs.system's enablement is as the row found it" "$mouse_system_was" plugin_enabled vgs.system
expect_poll "vgs.mouse's enablement is as the row found it" "$mouse_was" plugin_enabled vgs.mouse
expect_poll "the Mouse option leaves Hyprland" '[0.0, false]' mouse_option input:sensitivity float
