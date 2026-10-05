# vgs.mouse maps pointer and touchpad settings through the Hyprland options
# layer. The row runs in the nested sandbox only. It enables the plugin,
# drives the pane's real pointer-speed slider through the probe geometry and
# a click, reads the nested Hyprland option, checks an untouched option, adds
# a user line after the VGS loading line to prove the overridden badge, reads
# that the touchpad section is hidden on the sandbox's no-touchpad instance,
# clicks the bar widget to open the flyout through surfaces, changes the
# same slider from the keyboard, and installs a disposable bad copy that
# calls hyprctl itself so the control reaches Hyprland without a VGS layer
# option record.
#
# Control run on 2026-10-05, host cachy, through this row alone after the
# System rows: a disposable copy named acme.mouse-control was enabled, and
# the control planted the same direct hyprctl keyword write that the bad copy
# stands for. The option reached Hyprland, but the generated layer held no
# acme.mouse-control option section. The row's layer-record check failed on
# that copy, proving a direct hyprctl writer does not satisfy the contract.
# inputs: shell/plugins/vgs.mouse/* shell/plugins/vgs.system/* shell/Core/PluginLogic.js shell/Core/HyprlandLayer.* shell/Core/HyprlandState.* shell/Core/Capabilities.qml shell/Core/PluginStatus.qml shell/Hosts/PaneHost.qml shell/Ui/controls/Slider.qml shell/Ui/controls/Switch.qml shell/Ui/controls/SegmentedControl.qml shell/Ui/controls/FormRow.qml shell/Ui/layout/DeviceRow.qml bin/vgshell scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail

mouse_file="$home/.config/vgshell/shell.json"
mouse_saved="$sandbox/shell-before-mouse.json"
mouse_hypr="$home/.config/hypr/hyprland.lua"
mouse_layer="$home/.local/state/vgshell/hypr/vgs.lua"
mouse_copy="$home/.config/vgshell/plugins/acme.mouse-control"
cp -- "$mouse_file" "$mouse_saved"
hypr_lua_save mouse
mouse_system_was="$(plugin_enabled vgs.system)" || fail "vgs.system's enabled state is unreadable"
mouse_was="$(plugin_enabled vgs.mouse)" || fail "vgs.mouse's enabled state is unreadable"

mouse_option() { hypr -j getoption "$1" | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps([v.get(sys.argv[1]), v["set"]]))' "$2"; }
mouse_widget() { ipc smoke readInstance "$(bar_key)" vgs.mouse "$1"; }
mouse_placed() { bar_widget_ids | py_reply 'import json,sys; print(any("vgs.mouse" in ids for ids in json.load(sys.stdin)))'; }
mouse_text_count() { ipc smoke itemTextCount window vgs.mouse "$1" "$2"; }
mouse_layer_mentions() { if grep -qF -- "$1" "$mouse_layer"; then echo yes; else echo no; fi; }
mouse_status_published() { ipc smoke readInstance service vgs.mouse published | py_reply 'import json,sys; d=json.load(sys.stdin); print("ok" if d.get("hasTouchpad") is False and isinstance(d.get("devices"), list) else "bad")'; }
mouse_set_options() {
  python3 - "$mouse_file" "$1" "$2" <<'PY'
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
mouse_slider_point() {
  local rect
  rect="$(ipc smoke descendantGeometry window vgs.mouse | py_reply 'import json,sys; r=[i["box"] for i in json.load(sys.stdin) if i["type"] == "Slider" and i["visible"]]; print(json.dumps(r[0]) if r else "absent")')" || return 1
  [[ $rect == \[* ]] || { echo "mouse_slider_point: no slider: $rect" >&2; return 1; }
  read -r x y < <(at_centre window:System "$rect") || return 1
  python3 -c 'import json,sys; r=json.loads(sys.argv[1]); print(int(int(sys.argv[2]) - r[2] / 2 + r[2] * float(sys.argv[4])), sys.argv[3])' "$rect" "$x" "$y" "$1"
}
mouse_widget_point() { local rect; rect="$(ipc smoke instanceGeometry "$(bar_key)" vgs.mouse)" && at_centre vgs:bar "$rect"; }
mouse_focus() { ipc smoke activeFocusItem window vgs.mouse; }
mouse_control_result() {
  printf '%s %s\n' "$(mouse_option input:sensitivity float)" "$(mouse_layer_mentions 'acme.mouse-control 0.1.0: input options its settings set')"
}
mouse_panel_built() { ipc shell built | py_reply 'import json,sys; print(sum(1 for r in json.load(sys.stdin).get("panel", []) if r["id"] == "vgs.mouse"))'; }

expect "enabling the System window is allowed" ok ipc shell setPluginEnabled vgs.system true
expect "enabling Mouse is allowed" ok ipc shell setPluginEnabled vgs.mouse true
expect_poll "the Mouse widget is placed in the bar" True mouse_placed
expect_poll "the Mouse pane can be summoned" ok ipc shell summon window vgs.system '{"pane":"vgs.mouse"}'
expect_poll "the Mouse pane is mounted" '["vgs.mouse"]' window_panes
expect_poll "the sandbox has no touchpad section" 0 mouse_text_count SectionHeader Touchpad
expect_poll "the Mouse service publishes devices" ok mouse_status_published

read -r sx sy < <(mouse_slider_point 0.75) || fail "the Mouse pointer-speed slider has no box"
hover "$sx" "$sy" || fail "hovering the Mouse pointer-speed slider failed"
click "$sx" "$sy" || fail "clicking the Mouse pointer-speed slider failed"
expect_poll "a pane write reaches nested Hyprland sensitivity" '[0.5, true]' mouse_option input:sensitivity float
expect "an untouched natural-scroll option keeps Hyprland's default" '[false, false]' mouse_option input:natural_scroll bool
expect "the layer writes no untouched natural-scroll option" no mouse_layer_mentions natural_scroll
expect_poll "the Mouse layer records the sensitivity option" yes mouse_layer_mentions 'vgs.mouse 0.1.0: input options its settings set'

printf '%s\n' 'hl.config({ input = { sensitivity = -0.5 } })' >>"$mouse_hypr"
expect "the nested instance reloads with the user Mouse line" ok hypr reload config-only
expect_poll "the user Mouse line wins" '[-0.5, true]' mouse_option input:sensitivity float
expect_poll "the pane shows the overridden badge" 1 mouse_text_count Badge 'Overridden by your Hyprland config'
hypr_lua_restore mouse || fail "hyprland.lua is put back after the Mouse override read"
expect "the nested instance reloads without the Mouse override line" ok hypr reload config-only

expect "the Mouse pane closes before the widget flyout" ok ipc shell hide window vgs.system
expect "the Mouse widget toggles its flyout through surfaces" ok ipc smoke invokeInstance "$(bar_key)" vgs.mouse toggle ""
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
doc["id"] = "acme.mouse-control"
doc["name"] = "Mouse Control"
doc.pop("hyprland", None)
json.dump(doc, open(path, "w"))
service = os.path.join(root, "Service.qml")
open(service, "w").write('''import QtQuick\nimport Quickshell\nItem {\n    property var shell: null\n    Component.onCompleted: Quickshell.execDetached(["hyprctl", "keyword", "input:sensitivity", "0.45"])\n}\n''')
PY
rescan "rescan discovers the bad Mouse control copy"
expect_poll "the bad Mouse control copy is known" True plugin_known acme.mouse-control
expect "enabling the bad Mouse control copy is allowed" ok ipc shell setPluginEnabled acme.mouse-control true
expect "control: the bad copy's direct hyprctl write reaches Hyprland" ok hypr eval 'hl.config({ input = { sensitivity = 0.45 } })'
expect_poll "control: direct hyprctl changes sensitivity but no layer option record exists" '[0.45, true] no' mouse_control_result
expect "disabling the bad Mouse control copy is allowed" ok ipc shell setPluginEnabled acme.mouse-control false
rm -rf -- "${mouse_copy:?}"
rescan "rescan removes the bad Mouse control copy"

cp -- "$mouse_saved" "$mouse_file.next" && mv -T -- "$mouse_file.next" "$mouse_file"
expect "the configuration reloads as the row found it" ok ipc shell reloadConfig
expect_poll "vgs.system's enablement is as the row found it" "$mouse_system_was" plugin_enabled vgs.system
expect_poll "vgs.mouse's enablement is as the row found it" "$mouse_was" plugin_enabled vgs.mouse
expect_poll "the Mouse option leaves Hyprland" '[0.0, false]' mouse_option input:sensitivity float
