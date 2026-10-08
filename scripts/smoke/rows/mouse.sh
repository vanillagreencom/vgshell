# vgs.mouse maps pointer and touchpad settings through the Hyprland options
# layer. The row runs in the nested sandbox only. It enables the plugin,
# drives the pane's real pointer-speed slider through the probe geometry and
# a click, reads the nested Hyprland option, checks an untouched option, adds
# a user table of two keys after the VGS loading line, reads that the pane's
# value holds over it, that the pane holds the user's value, that the row
# alone shows a message under it, that the slider keeps its width and that
# the action stands beside the message in the pane and under it in the
# narrower flyout, clicks
# the row's one action and reads the setting gone, the user's value back and
# the keys on the row's slider, waits
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
# Control runs on 2026-10-05, host cachy, through this row after the consent
# row, each on a source_tree copy of the shell. A copy whose
# MouseControls.useHyprlandValue calls no configure.unset failed "the action
# removes the setting from the bar entry and the plugins row", reading
# [0.55, 0.55], and getoption kept 0.55. A copy whose MouseLogic.warningText
# gives every row a line, whose FormRow never moves its action under the
# message and whose action hands the keys to no control failed "no row
# shows a message before the user table", read the flyout's message -10.95
# px wide beside an action 186.95 px wide, and read the keys on the action.
# inputs: shell/plugins/vgs.mouse/* shell/plugins/vgs.system/* shell/Core/PluginLogic.js shell/Core/HyprlandLayer.* shell/Core/HyprlandState.* shell/Core/Capabilities.qml shell/Core/Plugins.qml shell/Core/PluginStatus.qml shell/Hosts/PaneHost.qml shell/Ui/controls/Button.qml shell/Ui/controls/RowAction.qml shell/Ui/controls/Slider.qml shell/Ui/controls/Switch.qml shell/Ui/controls/SegmentedControl.qml shell/Ui/controls/FormRow.qml shell/Ui/feedback/LinkText.qml shell/Ui/layout/DeviceRow.qml bin/vgshell scripts/smoke/rows/hyprland-consent.sh shell/Commons/Tokens.js shell/Ui/controls/TextField.qml scripts/smoke/Probe.qml
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
# The key/value rows of the pane that show a message, whatever it says: for
# each shown, non-empty hint line directly under a row, the types of that
# row's controls among Slider, Switch and SegmentedControl, as a JSON list.
# A chip's label is no message.
mouse_messages() { ipc smoke descendantGeometry window vgs.mouse | py_reply '
import json, sys
items = json.load(sys.stdin)
def under(index, row):
    while index >= 0:
        if index == row:
            return True
        index = items[index]["parent"]
    return False
rows = [i["parent"] for i in items if i["type"] in ("Label", "LinkText") and i.get("role") == "hint" and i["visible"] and i.get("text") and items[i["parent"]].get("name") == "fieldRow"]
print(json.dumps([sorted({c["type"] for n, c in enumerate(items) if c["type"] in ("Slider", "Switch", "SegmentedControl") and under(n, row)}) for row in rows]))'; }
# The user's values the pane's controls hold from the `hyprland` capability.
mouse_user_values() { ipc smoke readDescendant window vgs.mouse MouseControls userValues; }
mouse_slider_width() { ipc smoke descendantGeometry window vgs.mouse | py_reply 'import json,sys; r=[i["box"][2] for i in json.load(sys.stdin) if i["type"] == "Slider" and i["visible"]]; print(r[0] if r else "absent")'; }
# The boxes of the drawn "use my Hyprland value" actions, as a JSON list.
mouse_actions() { ipc smoke descendantGeometry window vgs.mouse | py_reply 'import json,sys; print(json.dumps([i["box"] for i in json.load(sys.stdin) if i["name"] == "useHyprlandValue" and i["visible"]]))'; }
# mouse_action_place HOST_KEY: where the first drawn action of the Mouse
# instance under that host stands against its row's message: `beside`, on
# the message's line past its end, `under`, below a message that has a
# width, else both boxes.
mouse_action_place() { ipc smoke descendantGeometry "$1" vgs.mouse | py_reply '
import json, sys
items = json.load(sys.stdin)
def row_of(index):
    while index >= 0 and items[index].get("name") != "fieldRow":
        index = items[index]["parent"]
    return index
found = [n for n, i in enumerate(items) if i["name"] == "useHyprlandValue" and i["visible"]]
if not found:
    print("absent"); sys.exit(0)
row = row_of(found[0])
action = items[found[0]]["box"]
message = next(i["box"] for i in items if i["type"] in ("Label", "LinkText") and i.get("role") == "hint" and i["visible"] and i.get("text") and i["parent"] == row)
if message[2] > 0 and action[1] >= message[1] + message[3]: print("under")
elif message[2] > 0 and action[1] < message[1] + message[3] and action[0] >= message[0] + message[2]: print("beside")
else: print("action=%s message=%s" % (action, message))'; }
mouse_action_count() { mouse_actions | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
# The centre of the first drawn action once two readings 0.1 s apart match:
# the row that holds it has just appeared, and the pane lays out again.
mouse_action_point() {
  local rect now last=""
  for _ in $(seq 1 30); do
    rect="$(mouse_actions | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[0]))')" && now="$(at_centre "window:System Settings" "$rect")" || return 1
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
  read -r x y < <(at_centre "window:System Settings" "$rect") || return 1
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

# System Settings supplies the real parent-width bindings. The same reader
# must reject a visible slider whose width the probe sets past its token.
mouse_input_widths() {
  ipc smoke descendantGeometry window vgs.system | py_reply '
import json, math, sys
rows = json.load(sys.stdin)
inputs = [r for r in rows if r["visible"] and "maximumWidth" in r and r["box"][2] > 0]
if not any(r["type"] == "Slider" for r in inputs):
    print("missing")
elif any(not math.isfinite(r["maximumWidth"]) or r["maximumWidth"] <= 0 for r in inputs):
    print("unbounded")
elif any(r["box"][2] > r["maximumWidth"] for r in inputs):
    print("oversized")
else:
    print("bounded")'
}
mouse_wide_window() {
  ipc smoke instanceGeometry window vgs.system | py_reply 'import json,sys; r=json.load(sys.stdin); print(r[2] > 2 * float(sys.argv[1]))' "$mouse_input_max"
}
mouse_theme="$home/.config/vgshell/theme.json"
mouse_theme_was="$(ipc smoke themeValue size.window.width)" || fail "the window width token is unreadable"
mouse_theme_present=false
if [[ -f $mouse_theme ]]; then
  mouse_theme_present=true
  cp -- "$mouse_theme" "$sandbox/mouse-theme.json"
fi
expect "the Mouse pane closes before the wide window" ok ipc shell hide window vgs.system
python3 - "$mouse_theme" <<'PYWIDTH'
import json, os, sys
path = sys.argv[1]
doc = json.load(open(path)) if os.path.exists(path) else {"schemaVersion": 1, "name": "wide-inputs", "tokens": {}}
doc.setdefault("tokens", {}).setdefault("size", {}).setdefault("window", {})["width"] = 2000
with open(path + ".tmp", "w") as out:
    json.dump(doc, out)
os.replace(path + ".tmp", path)
PYWIDTH
expect_poll "the wide window token is published" 2000 ipc smoke themeValue size.window.width
mouse_input_max="$(ipc smoke themeValue control.maxWidth)" || fail "the input maximum is unreadable"
mouse_input_oversize="$(python3 -c 'import sys; print(int(float(sys.argv[1])) + 4)' "$mouse_input_max")" || fail "the oversized width is unreadable"
expect "the Mouse page opens in wide Settings" ok ipc shell summon window vgs.system '{"pane":"vgs.mouse"}'
expect_poll "wide Settings mounts Mouse" '["vgs.mouse"]' window_panes
geometry expect_poll "Settings is wider than twice the input maximum" True mouse_wide_window
expect_poll "every visible input in wide Settings respects its maximum" bounded mouse_input_widths
expect "control: the probe renders an oversized slider" "$mouse_input_oversize" ipc smoke forceInputWidth window vgs.system Slider "$mouse_input_oversize"
expect "control: the wide Settings check rejects an oversized rendered slider" oversized mouse_input_widths
expect "the oversized control window closes" ok ipc shell hide window vgs.system
if "$mouse_theme_present"; then
  cp -- "$sandbox/mouse-theme.json" "$mouse_theme.tmp" && mv -T -- "$mouse_theme.tmp" "$mouse_theme"
else
  rm -f -- "${mouse_theme:?}"
fi
expect_poll "the window width token returns to its row start" "$mouse_theme_was" ipc smoke themeValue size.window.width
expect "the Mouse pane reopens after the width control" ok ipc shell summon window vgs.system '{"pane":"vgs.mouse"}'
expect_poll "the Mouse pane is mounted after the width control" '["vgs.mouse"]' window_panes

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
expect "no row shows a message before the user table" '[]' mouse_messages
expect "the pane holds no user value before the user table" '[]' mouse_user_values
printf '%s\n' 'hl.config({ input = { accel_profile = "flat", sensitivity = -0.5 } })' >>"$mouse_hypr"
expect "the nested instance reloads with the user Mouse table" ok hypr reload config-only
expect_poll "the pane's sensitivity holds over the user Mouse table" '[0.55, true]' mouse_option input:sensitivity float
expect_poll "the user's other key of that table keeps the user's value" '["flat", true]' mouse_option input:accel_profile str
expect_poll "the pane holds the user's value of the pointer speed" '[{"path":"input.sensitivity","value":-0.5}]' mouse_user_values
expect_poll "the pointer speed row alone shows a message under it" '[["Slider"]]' mouse_messages
expect "the message leaves the pointer-speed slider its width" "$mouse_width" mouse_slider_width
expect_poll "the pointer speed row alone offers the user's Hyprland value" 1 mouse_action_count
expect "the pane draws the action beside its message" beside mouse_action_place window
expect "the Mouse pane closes before the flyout's action is read" ok ipc shell hide window vgs.system
read -r fx fy < <(mouse_widget_point) || fail "the Mouse widget has no box before the action's flyout reading"
hover "$fx" "$fy" || fail "hovering the Mouse widget before the action's flyout reading failed"
click "$fx" "$fy" || fail "clicking the Mouse widget before the action's flyout reading failed"
expect_poll "the widget opens its flyout while the user's value stands" 1 mouse_panel_built
expect_poll "the flyout, too narrow for both, draws the action under its message" under mouse_action_place panel
expect "hiding the flyout after the action's reading is allowed" ok ipc shell hide panel vgs.mouse
expect_poll "the flyout is gone after the action's reading" 0 mouse_panel_built
expect_poll "the Mouse pane opens again for the action" ok ipc shell summon window vgs.system '{"pane":"vgs.mouse"}'
expect_poll "the Mouse pane is mounted again for the action" '["vgs.mouse"]' window_panes
expect_poll "the reopened pane offers the user's Hyprland value" 1 mouse_action_count
read -r ax ay < <(mouse_action_point) || fail "the Mouse action has no box"
hover "$ax" "$ay" || fail "hovering the Mouse action failed"
click "$ax" "$ay" || fail "clicking the Mouse action failed"
expect_poll "the action removes the setting from the bar entry and the plugins row" '["absent", "absent"]' mouse_saved_sensitivity
expect_poll "the action leaves the keys on the row's slider" '["Slider",null]' mouse_focus
expect_poll "with the setting gone getoption reads the user's value again" '[-0.5, true]' mouse_option input:sensitivity float
expect_poll "the layer writes no Mouse option once the setting is gone" no mouse_layer_mentions 'vgs.mouse 0.1.0: input options its settings set'
expect_poll "no row offers the user's Hyprland value once VGS sets none" 0 mouse_action_count
expect_poll "no row shows a message once VGS sets none" '[]' mouse_messages
expect_poll "the pane holds no user value once VGS sets none" '[]' mouse_user_values
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
