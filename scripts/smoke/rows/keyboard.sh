# vgs.keyboard's real editor, layer options and bar click in the nested
# sandbox. The direct-hyprctl widget control changes the keymap but fails
# the widget's source contract: only the core owns the transport.
# inputs: shell/plugins/vgs.keyboard/* shell/plugins/vgs.system/* shell/Core/HyprlandLayer.* shell/Core/HyprlandState.* shell/Core/PluginLogic.js shell/Core/PluginStatus.qml shell/Core/Capabilities.qml shell/Core/Dispatch.js shell/Core/Compositor.qml shell/Ui/layout/DeviceList.qml shell/Ui/layout/DeviceRow.qml shell/Ui/controls/Select.qml shell/Ui/controls/Button.qml shell/Ui/controls/RowAction.qml shell/Ui/controls/Slider.qml shell/Ui/controls/TextField.qml shell/Ui/controls/Switch.qml shell/Ui/controls/BarItem.qml shell/Ui/BarWidget.qml shell/Ui/overlay/Menu.qml shell/Ui/overlay/MenuItem.qml shell/Hosts/SummonPopup.qml shell/Ui/layout/SurfaceHeight.qml shell/Hosts/SummonLayer.qml shell/Ui/foundation/KeyNav.qml shell/Ui/foundation/KeyNavLogic.js scripts/smoke/Probe.qml scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail
keyboard_file="$home/.config/vgshell/shell.json"
keyboard_saved="$sandbox/shell-before-keyboard.json"
keyboard_copy="$home/.config/vgshell/plugins/vgs.keyboard"
cp -- "$keyboard_file" "$keyboard_saved"
keyboard_option() { hypr -j getoption "$1" | py_reply 'import json,sys; value=json.load(sys.stdin).get(sys.argv[1]); print(json.dumps("" if value == "[[EMPTY]]" else value))' "$2"; }
keyboard_keymaps() { hypr -j devices | py_reply 'import json,sys; print(json.dumps(sorted({k["active_keymap"] for k in json.load(sys.stdin).get("keyboards", [])})))'; }
keyboard_sources() { ipc smoke readDescendant window vgs.keyboard KeyboardControls sources | py_reply 'import json,sys; print(json.dumps([[r["code"], r["variant"]] for r in json.load(sys.stdin)]))'; }
keyboard_active_code() { ipc smoke readInstance "$(bar_key)" vgs.keyboard active | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get("code", "")))'; }
keyboard_active_fields() { ipc smoke statusValues vgs.keyboard | py_reply 'import json,sys; row=json.load(sys.stdin).get("active", {}); print(json.dumps([row.get("code"),row.get("name"),row.get("count")]))'; }
keyboard_service_index() { ipc smoke readInstance service vgs.keyboard devices | py_reply 'import json,sys; value=json.load(sys.stdin); rows=[] if value is None else value.get("keyboards", []); print(next((r["activeLayoutIndex"] for r in rows if r["main"]), "absent"))'; }
keyboard_event_fields() { ipc smoke readInstance service vgs.keyboard layoutEvent | py_reply 'import json,sys; row=json.load(sys.stdin); print(json.dumps(None if row is None else [row["code"],row["name"],row["layouts"],row["variants"]]))'; }
keyboard_panels() { ipc shell built | py_reply 'import json,sys; print(sum(r["id"] == "vgs.keyboard" for r in json.load(sys.stdin).get("panel", [])))'; }
# A built pane can have item focus before its window receives the seat.
# Wait on the activated window, not on the editor's remembered focus.
keyboard_wait() {
  local held="unreadable" panel="unreadable" active="unreadable" holder="unknown"
  smoke_poll_tries 200
  for _ in $(seq 1 "$smoke_poll_n"); do
    if held="$(window_keyboard vgs.system)" && [[ $held == true ]]; then return 0; fi
    sleep 0.2
  done
  panel="$(ipc smoke windowFocused panel vgs.keyboard)" || panel=unreadable
  active="$(active_window)" || active=unreadable
  if [[ $panel == true ]]; then holder=panel:vgs.keyboard; else holder="active-window:$active"; fi
  fail "keyboard-input: status=timeout target=window:vgs.system holder=$holder window_keyboard=$held panel_keyboard=$panel"
  return 1
}
keyboard_editor_keys() {
  keyboard_wait || return 1
  type_keys "$@" || { fail "keyboard-input: status=type-failed target=window:vgs.system"; return 1; }
}
# main-run.sh treats a leading FAIL as a real failure. These logs hold
# expected failures from subshell controls, whose assertions passed.
keyboard_control_log() {
  sed 's/^/  CONTROL  /'
}
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
    keyboard_editor_keys -k Tab || return 1
  done
  fail "keyboard-input: status=control-unreachable type=$1 object=$2"
  return 1
}
# Select through its real closed-list key path. The model identifies the
# requested entry; Home and Down activate its normal user handlers.
keyboard_pick() {
  local index keyboard_index
  index="$(ipc smoke readMatchingDescendant window vgs.keyboard Select objectName "$1" model | py_reply 'import json,sys
rows=json.load(sys.stdin)
want=None if sys.argv[2] == "__custom" else sys.argv[2]
print(next((i for i,row in enumerate(rows) if row.get(sys.argv[1]) == want), "absent"))' "$2" "$3")" || { fail "keyboard-input: status=choices-unreadable control=$1"; return 1; }
  [[ $index =~ ^[0-9]+$ ]] || { fail "keyboard-input: status=choice-absent control=$1 value=$3"; return 1; }
  keyboard_focus Select "$1" || return 1
  keyboard_editor_keys -k Home || return 1
  for ((keyboard_index=0; keyboard_index<index; keyboard_index++)); do keyboard_editor_keys -k Down || return 1; done
}
keyboard_system_layout="$(keyboard_option input:kb_layout str)"
keyboard_system_variant="$(keyboard_option input:kb_variant str)"
keyboard_input_options() {
  local option
  for option in kb_layout kb_variant kb_options repeat_rate repeat_delay; do
    case "$option" in repeat_*) keyboard_option "input:$option" int || return 1;;
      *) keyboard_option "input:$option" str || return 1;; esac
  done
}
keyboard_saved_options="$(keyboard_input_options)"
# The row shares its sandbox with later rows, including after a timeout.
# Its saved file and input options belong to the same cleanup path.
keyboard_restore() {
  expect "Keyboard closes its System window during restore" ok ipc shell hide window vgs.system
  expect "Keyboard closes its panel during restore" ok ipc shell hide panel vgs.keyboard
  expect_poll "Keyboard leaves no System window during restore" 0 window_count 'System Settings'
  expect_poll "Keyboard leaves no panel during restore" 0 keyboard_panels
  expect_poll "Keyboard unmaps its panel during restore" 0 layer_count vgs:panel
  if ! cp -- "$keyboard_saved" "$keyboard_file.tmp" || ! mv -T -- "$keyboard_file.tmp" "$keyboard_file"; then
    fail "keyboard-restore: status=file-failed"
    return 1
  fi
  expect "Keyboard restores the row's configuration" ok ipc shell reloadConfig
  expect "Keyboard reloads its starting system options" ok hypr reload config-only
  expect_poll "Keyboard restores its starting input options" "$keyboard_saved_options" keyboard_input_options
}
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
# A previous row can leave Hyprland's remembered group at 1 across reload.
# Prime group 0 so this frozen-read fixture tests a received German event.
expect "the event fixture primes the initial source" ok hypr switchxkblayout all 0
expect_poll "the event fixture has no pending source" null keyboard_event_fields
printf 'keyboard-event-state before=%s\n' "$(ipc smoke readInstance service vgs.keyboard layoutEvent)"
hypr -j devices >"$sandbox/keyboard-event-devices.json"
python3 - "$shim" "$sandbox/keyboard-event-devices.json" <<'PYSTALE'
import pathlib, shlex, sys
shim = pathlib.Path(sys.argv[1])
snapshot = shlex.quote(sys.argv[2])
real = shlex.quote(str(shim / "hyprctl.real"))
(shim / "hyprctl.keyboard-stale").write_text('#!/usr/bin/env bash\nif [[ ${1-} == -j && ${2-} == devices ]]; then\n  cat -- ' + snapshot + '\nelse\n  exec ' + real + ' "$@"\nfi\n')
(shim / "hyprctl.keyboard-stale").chmod(0o755)
PYSTALE
shim_hyprctl keyboard-stale
click_item "$(bar_key)" vgs.keyboard BarItem US || fail "clicking the Keyboard widget failed"
expect_poll "the widget click switches the real keymap" '["German (no dead keys)"]' keyboard_keymaps
expect_poll "the widget follows the active code" '"DE"' keyboard_active_code
expect "the event arrives before the devices read changes" 0 keyboard_service_index
expect_poll "the event keeps the code and name together" '["DE", "German (no dead keys)", 2]' keyboard_active_fields
expect "the event identifies the configured source" '["DE", "German (no dead keys)", "us,de", ",nodeadkeys"]' keyboard_event_fields
printf 'keyboard-event-state after=%s devices=%s\n' "$(ipc smoke readInstance service vgs.keyboard layoutEvent)" "$(ipc smoke readInstance service vgs.keyboard devices)"
shim_hyprctl real
rm -- "${shim:?}/hyprctl.keyboard-stale"
keyboard_right_click || fail "right clicking Keyboard failed"
expect_poll "the Keyboard widget menu opens" true ipc smoke readInstance "$(bar_key)" vgs.keyboard frameMenuOpen
expect "the widget keeps both Keyboard Controls and System settings" '["Hide","Keyboard Controls","Keyboard Settings","Settings"]' ipc smoke readInstance "$(bar_key)" vgs.keyboard frameMenuEntries
keyboard_controls_activate || fail "activating Keyboard Controls failed"
expect_poll "the menu action builds the typed Keyboard panel" '[["us", ""], ["de", "nodeadkeys"]]' keyboard_panel_sources
expect "the opened panel has the Keyboard title" '"Keyboard"' ipc smoke readDescendant panel vgs.keyboard Pane title
expect "the menu-opened Keyboard panel closes" ok ipc shell hide panel vgs.keyboard
expect_poll "the menu-opened panel is gone" 0 keyboard_panels
expect "the Keyboard pane opens" ok ipc shell summon window vgs.system '{"pane":"vgs.keyboard"}'
expect_poll "the Keyboard pane mounts" '["vgs.keyboard"]' window_panes
expect_poll "the editor holds both sources and variants" '[["us", ""], ["de", "nodeadkeys"]]' keyboard_sources
keyboard_wait || { keyboard_restore; return 0; }
ok "the System window holds the keyboard before editor input"

# Hold the real panel mapped and focused. The same input driver must stop
# before sending a key; omitting its wait must turn that assertion red.
expect "the keyboard-holder control opens the panel" ok ipc shell summon panel vgs.keyboard '{}'
expect_poll "the keyboard-holder control maps the panel" 1 layer_count vgs:panel
click_in vgs:panel panel vgs.keyboard DeviceRow 'English (US)' || { fail "the keyboard-holder control focuses the panel"; keyboard_restore; return 0; }
expect_poll "the keyboard-holder control gives the panel the keyboard" true ipc smoke windowFocused panel vgs.keyboard
expect_poll "the System window reads the keyboard leave before the control" false window_keyboard vgs.system
keyboard_reject_panel() {
  local status=0 count
  (failures=0 behaviour_failures=0; "$1" -k End) >"$sandbox/keyboard-input-$1.log" || status=$?
  if [[ $status != 1 ]]; then echo "accepted status=$status"; return; fi
  count="$(grep -cE 'keyboard-input: status=timeout target=window:vgs.system holder=panel:vgs.keyboard window_keyboard=false panel_keyboard=true$' "$sandbox/keyboard-input-$1.log")" || return 1
  if [[ $count == 1 ]]; then echo rejected; else echo "timeouts=$count"; fi
}
expect "a mapped panel stops editor input at the keyboard-holder wait" rejected keyboard_reject_panel keyboard_editor_keys
keyboard_control_log <"$sandbox/keyboard-input-keyboard_editor_keys.log"
declare -f keyboard_editor_keys >"$sandbox/keyboard-input-driver.sh"
python3 - "$sandbox/keyboard-input-driver.sh" "$sandbox/keyboard-input-no-wait.sh" <<'PYNOWAIT'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
name = 'keyboard_editor_keys ()'
wait = '    keyboard_wait || return 1;'
assert text.count(name) == 1 and text.count(wait) == 1
changed = text.replace(name, 'keyboard_editor_keys_unchecked ()').replace(wait, '    if false; then keyboard_wait || return 1; fi;')
assert changed != text
pathlib.Path(sys.argv[2]).write_text(changed)
PYNOWAIT
source "$sandbox/keyboard-input-no-wait.sh"
keyboard_rejection_control() {
  (failures=0 behaviour_failures=0
   expect "a mapped panel stops editor input at the keyboard-holder wait" rejected keyboard_reject_panel keyboard_editor_keys_unchecked >"$sandbox/keyboard-input-control.log"
   echo "$failures")
}
expect "control: removing the wait fails the same keyboard-holder assertion" 1 keyboard_rejection_control
keyboard_control_log <"$sandbox/keyboard-input-control.log"
expect "the keyboard-holder control hides its panel" ok ipc shell hide panel vgs.keyboard
expect_poll "the keyboard-holder control unmaps its panel" 0 layer_count vgs:panel
expect "the keyboard-holder control closes its System window" ok ipc shell hide window vgs.system
expect_poll "the keyboard-holder control unmaps its System window" 0 window_count 'System Settings'
expect "the Keyboard pane reopens after the keyboard-holder control" ok ipc shell summon window vgs.system '{"pane":"vgs.keyboard"}'
expect_poll "the reopened Keyboard pane mounts" '["vgs.keyboard"]' window_panes
keyboard_editor_keys -k End || { keyboard_restore; return 0; }
keyboard_editor_keys -M ctrl -k Up -m ctrl || { keyboard_restore; return 0; }
expect_poll "keyboard move keeps the source and variant together" '[["de", "nodeadkeys"], ["us", ""]]' keyboard_sources
expect_poll "keyboard move reaches Hyprland" '"de,us"' keyboard_option input:kb_layout str
keyboard_editor_keys -k Delete || { keyboard_restore; return 0; }
expect_poll "keyboard removal keeps the remaining source" '[["us", ""]]' keyboard_sources
keyboard_editor_keys -k Delete || { keyboard_restore; return 0; }
expect "the editor keeps the last source" '[["us", ""]]' keyboard_sources
# DeviceRow includes a focusable overflow button. Traverse the actual
# controls until the first repeat slider, rather than assume a Tab count.
for _ in $(seq 1 12); do
  [[ $(ipc smoke activeFocusItem window vgs.keyboard) == '["Slider",null]' ]] && break
  keyboard_editor_keys -k Tab || { keyboard_restore; return 0; }
done
expect_poll "the repeat slider holds keyboard focus" '["Slider",null]' ipc smoke activeFocusItem window vgs.keyboard
keyboard_editor_keys -k End || { keyboard_restore; return 0; }
expect_poll "repeat rate reaches Hyprland" 200 keyboard_option input:repeat_rate int
keyboard_pick layoutPicker code de || { keyboard_restore; return 0; }
keyboard_pick variantPicker code nodeadkeys || { keyboard_restore; return 0; }
keyboard_focus Button addSource || { keyboard_restore; return 0; }
keyboard_editor_keys -k space || { keyboard_restore; return 0; }
expect_poll "Add saves the selected layout in every settings entry" '["us,de", "us,de"]' keyboard_saved_value layouts
expect_poll "Add saves the selected variant in every settings entry" '[",nodeadkeys", ",nodeadkeys"]' keyboard_saved_value variants
expect_poll "Add applies the selected layout" '"us,de"' keyboard_option input:kb_layout str
expect_poll "Add applies the selected variant" '",nodeadkeys"' keyboard_option input:kb_variant str
keyboard_focus RowAction systemLayout || { keyboard_restore; return 0; }
keyboard_editor_keys -k space || { keyboard_restore; return 0; }
expect_poll "reset removes both saved layout values" '["absent", "absent"]' keyboard_saved_value layouts
expect_poll "reset removes both saved variant values" '["absent", "absent"]' keyboard_saved_value variants
expect_poll "reset restores the compositor's system layout" "$keyboard_system_layout" keyboard_option input:kb_layout str
expect_poll "reset restores the compositor's system variant" "$keyboard_system_variant" keyboard_option input:kb_variant str
keyboard_pick modifierPicker value caps:escape || { keyboard_restore; return 0; }
expect_poll "the modifier preset is saved" '["caps:escape", "caps:escape"]' keyboard_saved_value options
expect_poll "the modifier preset reaches Hyprland" '"caps:escape"' keyboard_option input:kb_options str
keyboard_pick modifierPicker value __custom || { keyboard_restore; return 0; }
keyboard_focus TextField customOptions || { keyboard_restore; return 0; }
keyboard_editor_keys -M ctrl -k a -m ctrl || { keyboard_restore; return 0; }
keyboard_editor_keys 'compose:ralt,grp:alt_shift_toggle' || { keyboard_restore; return 0; }
keyboard_editor_keys -k Return || { keyboard_restore; return 0; }
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
expect "the absent-action menu keeps System settings" '["Hide","Keyboard Settings","Settings"]' ipc smoke readInstance "$(bar_key)" vgs.keyboard frameMenuEntries
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
keyboard_restore


# Remove the plugin's handler in fresh copies so only the post-switch core
# read can publish the new source. Removing that completion read must turn
# the same typed active-code assertion red.
keyboard_completion_setup() {
  expect "the completion fixture enables Keyboard" ok ipc shell setPluginEnabled vgs.keyboard true
  expect "the completion fixture places Keyboard" ok ipc shell setPluginPlaced vgs.keyboard true
  keyboard_set_sources us,de ',nodeadkeys'
  expect "the completion fixture reloads its sources" ok ipc shell reloadConfig
  expect_poll "the completion fixture starts on English" '["English (US)"]' keyboard_keymaps
  expect_poll "the completion fixture reads the initial source" 0 keyboard_service_index
  expect_poll "the completion fixture starts with US" '"US"' keyboard_active_code
  click_item "$(bar_key)" vgs.keyboard BarItem US || fail "clicking the completion fixture failed"
  expect_poll "the completion fixture switches the real keymap" '["German (no dead keys)"]' keyboard_keymaps
}
keyboard_completion_check() { expect_poll "the completion read publishes the switched source" '["DE", "German (no dead keys)", 2]' keyboard_active_fields; }
keyboard_completion_control() { (failures=0 behaviour_failures=0; keyboard_completion_check >"$sandbox/keyboard-completion-control.log"; echo "$failures"); }
for keyboard_fixture in keyboard-no-layout-event keyboard-no-completion; do
  copy_tree "$keyboard_fixture"
  edit_tree "$keyboard_fixture" shell/plugins/vgs.keyboard/Service.qml \
    'root.layoutEvent = Logic.layoutValue(root.devices, root.catalog, args[0], args[1], root.layoutEvent);' \
    $'return;\n            root.layoutEvent = Logic.layoutValue(root.devices, root.catalog, args[0], args[1], root.layoutEvent);'
  edit_tree "$keyboard_fixture" shell/Core/HyprlandState.qml \
    $'            } else if (event.name === "activelayout") {\n                root.readDevices();' \
    $'            } else if (event.name === "activelayout") {\n                return;\n                root.readDevices();'
  if [[ $keyboard_fixture == keyboard-no-completion ]]; then
    edit_tree "$keyboard_fixture" shell/Core/Compositor.qml 'root.keyboardLayoutSwitched();' 'if (false) root.keyboardLayoutSwitched();'
  fi
  stop_shell
  start_shell "$sandbox/tree-$keyboard_fixture" "$sandbox/$keyboard_fixture.log" || fail "the completion fixture starts"
  keyboard_completion_setup
  if [[ $keyboard_fixture == keyboard-no-layout-event ]]; then
    keyboard_completion_check
    expect "the completion read updates devices without a plugin event" 1 keyboard_service_index
  else
    expect "control: the omitted completion keeps the old device source" 0 keyboard_service_index
    expect "control: removing the completion read fails the same active source check" 1 keyboard_completion_control
  fi
  expect "the completion fixture holds no plugin layout event" null ipc smoke readInstance service vgs.keyboard layoutEvent
  keyboard_restore
done
stop_shell
start_shell "$repo" "$sandbox/keyboard-completion-restored.log" || fail "the completion fixtures restore the shipped shell"
expect "the restored shell reloads the system sources" ok hypr reload config-only
expect_poll "the restored shell keeps the system layout" "$keyboard_system_layout" keyboard_option input:kb_layout str
expect_poll "the restored shell keeps the system variant" "$keyboard_system_variant" keyboard_option input:kb_variant str

# Source the actual row through its failure return, not just its input
# driver. A focused panel plants the timeout before any editor key.
keyboard_cleanup_state() {
  local configuration=changed windows panels options
  cmp -s -- "$keyboard_saved" "$keyboard_file" && configuration=restored
  windows="$(window_count 'System Settings')" && panels="$(keyboard_panels)" && options="$(keyboard_input_options)" || return 1
  if [[ $configuration == restored && $windows == 0 && $panels == 0 && $options == "$keyboard_saved_options" ]]; then
    echo restored
  else
    printf 'configuration=%s windows=%s panels=%s options_match=%s\n' "$configuration" "$windows" "$panels" "$([[ $options == "$keyboard_saved_options" ]] && echo true || echo false)"
  fi
}
keyboard_timeout_row() {
  (failures=0 behaviour_failures=0
   source "$sandbox/keyboard-timeout-$1.sh" >"$sandbox/keyboard-timeout-$1.log"
   echo "$failures")
}
keyboard_cleanup_check() { expect "a stopped Keyboard row restores its starting file, windows and options" restored keyboard_cleanup_state; }
keyboard_cleanup_control() {
  (failures=0 behaviour_failures=0
   keyboard_cleanup_check >"$sandbox/keyboard-cleanup-control.log"
   echo "$failures")
}
for keyboard_cleanup_fixture in restored omitted; do
  python3 - "$repo/scripts/smoke/rows/keyboard.sh" "$sandbox/keyboard-timeout-$keyboard_cleanup_fixture.sh" "$keyboard_cleanup_fixture" <<'PYCLEANUP'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
wait = 'keyboard_wait || { keyboard_restore; return 0; }\n'
assert text.count(wait) == 1
plant = '''expect "the timeout-row control opens its panel" ok ipc shell summon panel vgs.keyboard '{}'
expect_poll "the timeout-row control maps its panel" 1 layer_count vgs:panel
click_in vgs:panel panel vgs.keyboard DeviceRow 'English (US)' || { fail "the timeout-row control focuses its panel"; keyboard_restore; return 0; }
expect_poll "the timeout-row control gives the panel the keyboard" true ipc smoke windowFocused panel vgs.keyboard
expect_poll "the timeout-row control reads the System keyboard leave" false window_keyboard vgs.system
'''
replacement = wait if sys.argv[3] == 'restored' else 'keyboard_wait || { if false; then keyboard_restore; fi; return 0; }\n'
# Stop the copy at the tested return so a failed plant cannot enter the
# row's later controls or recursively source another copy.
changed = text.split(wait, 1)[0] + plant + replacement + '''fail "keyboard-timeout-control: status=not-rejected"
keyboard_restore
return 0
'''
assert changed != text
pathlib.Path(sys.argv[2]).write_text(changed)
PYCLEANUP
  expect "the $keyboard_cleanup_fixture cleanup fixture stops on one keyboard timeout" 1 keyboard_timeout_row "$keyboard_cleanup_fixture"
  grep -F 'keyboard-input: status=timeout' "$sandbox/keyboard-timeout-$keyboard_cleanup_fixture.log" | keyboard_control_log
  if [[ $keyboard_cleanup_fixture == restored ]]; then
    keyboard_cleanup_check
  else
    expect "control: omitting failure cleanup fails the same restored-state assertion" 1 keyboard_cleanup_control
    keyboard_control_log <"$sandbox/keyboard-cleanup-control.log"
    keyboard_restore
    keyboard_cleanup_check
  fi
done
