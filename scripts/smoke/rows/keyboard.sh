# vgs.keyboard's real editor, layer options and bar click in the nested
# sandbox. The direct-hyprctl widget control changes the keymap but fails
# the widget's source contract: only the core owns the transport.
# inputs: shell/plugins/vgs.keyboard/* shell/plugins/vgs.system/* shell/Core/HyprlandLayer.* shell/Core/HyprlandState.* shell/Core/PluginLogic.js shell/Core/PluginStatus.qml shell/Core/Capabilities.qml shell/Core/Dispatch.js shell/Core/Compositor.qml shell/Ui/layout/DeviceList.qml shell/Ui/layout/DeviceRow.qml shell/Ui/controls/Select.qml shell/Ui/controls/Button.qml shell/Ui/controls/Slider.qml shell/Ui/controls/TextField.qml shell/Ui/controls/Switch.qml shell/Ui/controls/BarItem.qml shell/Ui/BarWidget.qml shell/Ui/overlay/Menu.qml shell/Ui/overlay/MenuItem.qml shell/Hosts/SummonPopup.qml shell/Ui/foundation/KeyNav.qml shell/Ui/foundation/KeyNavLogic.js scripts/smoke/Probe.qml scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail
keyboard_file="$home/.config/vgshell/shell.json"
keyboard_saved="$sandbox/shell-before-keyboard.json"
keyboard_copy="$home/.config/vgshell/plugins/vgs.keyboard"
cp -- "$keyboard_file" "$keyboard_saved"
keyboard_option() { hypr -j getoption "$1" | py_reply 'import json,sys; value=json.load(sys.stdin).get(sys.argv[1]); print(json.dumps("" if value == "[[EMPTY]]" else value))' "$2"; }
keyboard_keymaps() { hypr -j devices | py_reply 'import json,sys; print(json.dumps(sorted({k["active_keymap"] for k in json.load(sys.stdin).get("keyboards", [])})))'; }
keyboard_sources() { ipc smoke readDescendant window vgs.keyboard KeyboardControls sources | py_reply 'import json,sys; print(json.dumps([[r["code"], r["variant"]] for r in json.load(sys.stdin)]))'; }
keyboard_active_code() { ipc smoke readInstance "$(bar_key)" vgs.keyboard active | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get("code", "")))'; }
keyboard_panels() { ipc shell built | py_reply 'import json,sys; print(sum(r["id"] == "vgs.keyboard" for r in json.load(sys.stdin).get("panel", [])))'; }
keyboard_right_click() {
  local box x y
  box="$(ipc smoke instanceGeometry "$(bar_key)" vgs.keyboard)" || return 1
  [[ $box == \[* ]] || return 1
  read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2), int(y+h/2))' "$box") || return 1
  hover "$((x - 1))" "$y" && right_click "$x" "$y"
}
keyboard_controls_activate() {
  local index keyboard_index
  index="$(ipc smoke readInstance "$(bar_key)" vgs.keyboard frameMenuEntries | py_reply 'import json,sys; rows=json.load(sys.stdin); print(rows.index("Keyboard Controls") if "Keyboard Controls" in rows else -1)')" || return 1
  [[ $index =~ ^[0-9]+$ ]] || return 1
  type_keys -k Home || return 1
  for ((keyboard_index=0; keyboard_index<index; keyboard_index++)); do type_keys -k Down || return 1; done
  type_keys -k Return
}
keyboard_panel_sources() { ipc smoke readDescendant panel vgs.keyboard KeyboardControls sources | py_reply 'import json,sys; print(json.dumps([[r["code"], r["variant"]] for r in json.load(sys.stdin)]))'; }
keyboard_catalog() { ipc smoke statusValues vgs.keyboard | py_reply 'import json,sys; print(json.load(sys.stdin).get("catalog", {}).get("state", "absent"))'; }
keyboard_saved_value() {
  cat -- "$keyboard_file" | py_reply 'import json,sys
doc=json.load(sys.stdin)
entries=[e for section in doc.get("bar", {}).get("layout", {}).values() for e in section if e.get("id") == "vgs.keyboard"]
entries += [r for r in doc.get("plugins", []) if r.get("id") == "vgs.keyboard"]
print(json.dumps([r.get(sys.argv[1], "absent") for r in entries]))' "$1"
}
keyboard_focus() {
  for _ in $(seq 1 40); do
    [[ $(ipc smoke readMatchingDescendant window vgs.keyboard "$1" objectName "$2" activeFocus) == true ]] && return 0
    type_keys -k Tab || return 1
  done
  return 1
}
# Select through its real closed-list key path. The model identifies the
# requested entry; Home and Down activate its normal user handlers.
keyboard_pick() {
  local index keyboard_index
  index="$(ipc smoke readMatchingDescendant window vgs.keyboard Select objectName "$1" model | py_reply 'import json,sys
rows=json.load(sys.stdin)
want=None if sys.argv[2] == "__custom" else sys.argv[2]
print(next((i for i,row in enumerate(rows) if row.get(sys.argv[1]) == want), "absent"))' "$2" "$3")" || return 1
  [[ $index =~ ^[0-9]+$ ]] || return 1
  keyboard_focus Select "$1" || return 1
  type_keys -k Home || return 1
  for ((keyboard_index=0; keyboard_index<index; keyboard_index++)); do type_keys -k Down || return 1; done
}
keyboard_system_layout="$(keyboard_option input:kb_layout str)"
keyboard_system_variant="$(keyboard_option input:kb_variant str)"
keyboard_transport_contract() {
  python3 -c 'import pathlib,sys; source=pathlib.Path(sys.argv[1]).read_text(); print("ok" if "hyprctl" not in source and "shell.hyprland.switchKeyboardLayout(\"next\")" in source else "direct")' "$1/Widget.qml"
}
keyboard_set_sources() {
  python3 - "$keyboard_file" "$1" "$2" <<'PY'
import json, os, sys
path, layouts, variants = sys.argv[1:]
doc = json.load(open(path))
rows = doc.setdefault("plugins", [])
row = next((r for r in rows if r.get("id") == "vgs.keyboard"), None)
if row is None:
    row = {"id":"vgs.keyboard"}
    rows.append(row)
row.update(layouts=layouts, variants=variants)
for section in doc.get("bar", {}).get("layout", {}).values():
    for entry in section:
        if entry.get("id") == "vgs.keyboard": entry.update(layouts=layouts, variants=variants)
with open(path + ".tmp", "w") as out: json.dump(doc, out)
os.replace(path + ".tmp", path)
PY
}
expect "enabling Keyboard is allowed" ok ipc shell setPluginEnabled vgs.keyboard true
expect "placing Keyboard is allowed" ok ipc shell setPluginPlaced vgs.keyboard true
expect "enabling System for Keyboard is allowed" ok ipc shell setPluginEnabled vgs.system true
expect_poll "the Keyboard catalog is complete" ready keyboard_catalog
keyboard_set_sources us ''
expect "the keyboard configuration reloads" ok ipc shell reloadConfig
expect_poll "one source reaches Hyprland" '"us"' keyboard_option input:kb_layout str
expect_poll "one source hides the widget" false ipc smoke readInstance "$(bar_key)" vgs.keyboard visible
keyboard_set_sources us,de ',nodeadkeys'
expect "the second source configuration reloads" ok ipc shell reloadConfig
expect_poll "the second source reaches Hyprland" '"us,de"' keyboard_option input:kb_layout str
expect_poll "the aligned variants reach Hyprland" '",nodeadkeys"' keyboard_option input:kb_variant str
expect_poll "two sources show the widget" true ipc smoke readInstance "$(bar_key)" vgs.keyboard visible
expect_poll "the initial keymap is English" '["English (US)"]' keyboard_keymaps
expect_poll "the initial widget code is US" '"US"' keyboard_active_code
expect "the shipped widget uses the core transport" ok keyboard_transport_contract "$repo/shell/plugins/vgs.keyboard"
click_item "$(bar_key)" vgs.keyboard BarItem US || fail "clicking the Keyboard widget failed"
expect_poll "the widget click switches the real keymap" '["German (no dead keys)"]' keyboard_keymaps
expect_poll "the widget follows the active code" '"DE"' keyboard_active_code
keyboard_right_click || fail "right clicking Keyboard failed"
expect_poll "the Keyboard widget menu opens" true ipc smoke readInstance "$(bar_key)" vgs.keyboard frameMenuOpen
expect "the widget keeps both Keyboard Controls and System settings" '["Hide","Keyboard Controls","Keyboard Settings"]' ipc smoke readInstance "$(bar_key)" vgs.keyboard frameMenuEntries
keyboard_controls_activate || fail "activating Keyboard Controls failed"
expect_poll "the menu action builds the typed Keyboard panel" '[["us", ""], ["de", "nodeadkeys"]]' keyboard_panel_sources
expect "the opened panel has the Keyboard title" '"Keyboard"' ipc smoke readDescendant panel vgs.keyboard Pane title
expect "the menu-opened Keyboard panel closes" ok ipc shell hide panel vgs.keyboard
expect_poll "the menu-opened panel is gone" 0 keyboard_panels
expect "the Keyboard pane opens" ok ipc shell summon window vgs.system '{"pane":"vgs.keyboard"}'
expect_poll "the Keyboard pane mounts" '["vgs.keyboard"]' window_panes
expect_poll "the editor holds both sources and variants" '[["us", ""], ["de", "nodeadkeys"]]' keyboard_sources
type_keys -k End || fail "selecting the last source failed"
type_keys -M ctrl -k Up -m ctrl || fail "moving the source up failed"
expect_poll "keyboard move keeps the source and variant together" '[["de", "nodeadkeys"], ["us", ""]]' keyboard_sources
expect_poll "keyboard move reaches Hyprland" '"de,us"' keyboard_option input:kb_layout str
type_keys -k Delete || fail "removing the selected source failed"
expect_poll "keyboard removal keeps the remaining source" '[["us", ""]]' keyboard_sources
type_keys -k Delete || fail "trying to remove the last source failed"
expect "the editor keeps the last source" '[["us", ""]]' keyboard_sources
# DeviceRow includes a focusable overflow button. Traverse the actual
# controls until the first repeat slider, rather than assume a Tab count.
for _ in $(seq 1 12); do
  [[ $(ipc smoke activeFocusItem window vgs.keyboard) == '["Slider",null]' ]] && break
  type_keys -k Tab || fail "tabbing to repeat rate failed"
done
expect_poll "the repeat slider holds keyboard focus" '["Slider",null]' ipc smoke activeFocusItem window vgs.keyboard
type_keys -k End || fail "changing repeat rate from the keyboard failed"
expect_poll "repeat rate reaches Hyprland" 200 keyboard_option input:repeat_rate int
keyboard_pick layoutPicker code de || fail "choosing German through the layout control failed"
keyboard_pick variantPicker code nodeadkeys || fail "choosing the non-default variant failed"
keyboard_focus Button addSource || fail "the Add button cannot take keys"
type_keys -k space || fail "activating Add input source failed"
expect_poll "Add saves the selected layout in every settings entry" '["us,de", "us,de"]' keyboard_saved_value layouts
expect_poll "Add saves the selected variant in every settings entry" '[",nodeadkeys", ",nodeadkeys"]' keyboard_saved_value variants
expect_poll "Add applies the selected layout" '"us,de"' keyboard_option input:kb_layout str
expect_poll "Add applies the selected variant" '",nodeadkeys"' keyboard_option input:kb_variant str
keyboard_focus Button systemLayout || fail "the system layout button cannot take keys"
type_keys -k space || fail "activating Use system layout failed"
expect_poll "reset removes both saved layout values" '["absent", "absent"]' keyboard_saved_value layouts
expect_poll "reset removes both saved variant values" '["absent", "absent"]' keyboard_saved_value variants
expect_poll "reset restores the compositor's system layout" "$keyboard_system_layout" keyboard_option input:kb_layout str
expect_poll "reset restores the compositor's system variant" "$keyboard_system_variant" keyboard_option input:kb_variant str
keyboard_pick modifierPicker value caps:escape || fail "choosing the modifier preset failed"
expect_poll "the modifier preset is saved" '["caps:escape", "caps:escape"]' keyboard_saved_value options
expect_poll "the modifier preset reaches Hyprland" '"caps:escape"' keyboard_option input:kb_options str
keyboard_pick modifierPicker value __custom || fail "choosing custom modifiers failed"
keyboard_focus TextField customOptions || fail "the custom modifier field cannot take keys"
type_keys -M ctrl -k a -m ctrl || fail "selecting the custom modifier text failed"
type_keys 'compose:ralt,grp:alt_shift_toggle' || fail "typing custom modifier options failed"
type_keys -k Return || fail "committing custom modifiers failed"
expect_poll "custom modifiers are saved" '["compose:ralt,grp:alt_shift_toggle", "compose:ralt,grp:alt_shift_toggle"]' keyboard_saved_value options
expect_poll "custom modifiers reach Hyprland" '"compose:ralt,grp:alt_shift_toggle"' keyboard_option input:kb_options str
expect "the Keyboard pane closes before the control" ok ipc shell hide window vgs.system
expect "the Keyboard panel opens" ok ipc shell summon panel vgs.keyboard '{}'
expect_poll "the Keyboard panel is built" 1 keyboard_panels
expect "the Keyboard panel closes" ok ipc shell hide panel vgs.keyboard
expect_poll "the Keyboard panel is gone" 0 keyboard_panels
expect "disabling Keyboard before its control is allowed" ok ipc shell setPluginEnabled vgs.keyboard false
cp -R -- "$repo/shell/plugins/vgs.keyboard" "$keyboard_copy"
# Control: remove only the new action. The widget still builds, switches
# layouts and offers System settings, but the same menu opener cannot run.
python3 - "$keyboard_copy/Widget.qml" <<'PYNOPANEL'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = '        { label: "Keyboard Controls", action: () => widget.toggleControls() },\n'
assert text.count(needle) == 1
changed = text.replace(needle, '')
assert changed != text
path.write_text(changed)
PYNOPANEL
rescan "rescan discovers the absent-action Keyboard control"
keyboard_set_sources us,de ',nodeadkeys'
expect "the absent-action control layout reloads" ok ipc shell reloadConfig
expect "enabling the absent-action control is allowed" ok ipc shell setPluginEnabled vgs.keyboard true
expect_poll "the absent-action widget builds and stays visible" true ipc smoke readInstance "$(bar_key)" vgs.keyboard visible
expect_poll "the absent-action widget still reads US" '"US"' keyboard_active_code
keyboard_right_click || fail "right clicking the absent-action control failed"
expect_poll "the absent-action widget menu opens" true ipc smoke readInstance "$(bar_key)" vgs.keyboard frameMenuOpen
expect "the absent-action menu keeps System settings" '["Hide","Keyboard Settings"]' ipc smoke readInstance "$(bar_key)" vgs.keyboard frameMenuEntries
if keyboard_controls_activate; then fail "control: an absent action still activates Keyboard Controls"
else ok "control: removing the action fails the same menu opener"; fi
expect "control: the absent action builds no typed Keyboard panel" absent ipc smoke readDescendant panel vgs.keyboard KeyboardControls sources
type_keys -k Escape || fail "closing the absent-action menu failed"
expect "disabling the absent-action control is allowed" ok ipc shell setPluginEnabled vgs.keyboard false
cp -- "$repo/shell/plugins/vgs.keyboard/Widget.qml" "$keyboard_copy/Widget.qml"
python3 - "$keyboard_copy/Widget.qml" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = 'shell.hyprland.switchKeyboardLayout("next")'
assert text.count(needle) == 1
text = text.replace('import QtQuick\n', 'import QtQuick\nimport Quickshell\n', 1)
path.write_text(text.replace(needle, '(Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"]), "ok")'))
PY
rescan "rescan discovers the direct-hyprctl Keyboard control"
keyboard_set_sources us,de ',nodeadkeys'
expect "the control layout reloads" ok ipc shell reloadConfig
expect "enabling the control widget is allowed" ok ipc shell setPluginEnabled vgs.keyboard true
expect_poll "the control starts on English" '["English (US)"]' keyboard_keymaps
expect_poll "the control widget is visible before its click" true ipc smoke readInstance "$(bar_key)" vgs.keyboard visible
expect_poll "the control widget code is US" '"US"' keyboard_active_code
click_item "$(bar_key)" vgs.keyboard BarItem US || fail "clicking the control widget failed"
expect_poll "control: direct hyprctl changes the keymap" '["German (no dead keys)"]' keyboard_keymaps
expect "control: the source contract rejects the direct transport" direct keyboard_transport_contract "$keyboard_copy"
expect "disabling the control is allowed" ok ipc shell setPluginEnabled vgs.keyboard false
rm -rf -- "${keyboard_copy:?}"
rescan "rescan restores the shipped Keyboard plugin"
cp -- "$keyboard_saved" "$keyboard_file.tmp" && mv -T -- "$keyboard_file.tmp" "$keyboard_file"
expect "Keyboard restores the row's configuration" ok ipc shell reloadConfig
