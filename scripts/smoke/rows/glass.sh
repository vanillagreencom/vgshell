# The Glass section of System Settings: the real pane writes a surface's
# choice to shell.json `appearance.glassSurfaces` through capability
# `appearance`, its Switch reads the saved choice back, and the one deciding
# place hands the choice to the surface's glass. The real Style Select
# saves Clear and removes the override on Auto. The disposable copy omits
# each write. No pixel, timing or compositor glass is measured; reads use
# expect_poll's 200 ms interval.
# inputs: shell/plugins/vgs.glass/* shell/plugins/vgs.system/manifest.json shell/plugins/vgs.system/Window.qml shell/Hosts/PaneHost.qml shell/Hosts/AppWindow.qml shell/Core/Capabilities.qml shell/Core/Config.qml shell/Core/ConfigLogic.js shell/Core/PluginLogic.js shell/Commons/ThemeLogic.js shell/Commons/Theme.qml shell/Commons/Glass.js shell/Ui/controls/Switch.qml shell/Ui/controls/Select.qml shell/Ui/controls/FormRow.qml
set -euo pipefail

glass_file="$home/.config/vgshell/shell.json"
glass_saved_copy="$sandbox/shell-before-glass.json"
glass_control="$home/.config/vgshell/plugins/vgs.glass"
cp -- "$glass_file" "$glass_saved_copy"

glass_saved() { python3 -c 'import json,sys; print(json.dumps((json.load(open(sys.argv[1])).get("appearance") or {}).get("glassSurfaces")))' "$glass_file"; }
glass_switch() { ipc smoke readMatchingDescendant window vgs.system Switch objectName "glass-$1" checked; }
glass_style() { ipc smoke readMatchingDescendant window vgs.system Select objectName glassStyle "${1:-currentText}"; }
glass_style_saved() {
  python3 -c 'import json,sys; a=json.load(open(sys.argv[1])).get("appearance") or {}; print(json.dumps(a["glassStyle"]) if "glassStyle" in a else "absent")' "$glass_file"
}
glass_style_readback() {
  local saved resolved
  saved="$(glass_style_saved)" && resolved="$(ipc smoke themeValue glassStyle)" || return 1
  printf '%s|%s\n' "$saved" "$resolved"
}
glass_assert_clear() {
  expect_poll "choosing Clear saves the override and sets the resolved Theme style" '"clear"|"clear"' glass_style_readback
}
glass_pick_style() { # Home for Auto, End for Clear
  ipc smoke revealScopedText window vgs.system FormRow 'Style' Select '' >/dev/null || return 1
  click_item 'scoped:System Settings' window vgs.glass FormRow 'Style' Select '' || return 1
  expect_poll "the Style Select opens" true glass_style listOpen
  [[ $(glass_style listOpen) == true ]] || return 1
  type_keys -k "$1" && type_keys -k Return || return 1
  expect_poll "the Style Select closes after the choice" false glass_style listOpen
}
glass_open() {
  expect "System Settings opens Glass" ok ipc shell summon window vgs.system '{"pane":"vgs.glass"}'
  expect_poll "Glass mounts in System Settings" '["vgs.glass"]' window_panes
}
glass_click_launcher() {
  ipc smoke revealScopedText window vgs.system FormRow 'Launcher' Switch '' >/dev/null || fail "the Launcher row is not reachable"
  click_item 'scoped:System Settings' window vgs.glass FormRow 'Launcher' Switch '' || fail "the Launcher switch does not take the click"
}

expect "Glass enables" ok ipc shell setPluginEnabled vgs.glass true
glass_open
expect_poll "the Style select shows Auto while no style is saved" '"Auto"' glass_style
glass_auto="$(ipc smoke themeValue scheme.mode)"
[[ $glass_auto == '"light"' || $glass_auto == '"dark"' ]] || fail "the Auto theme mode is unreadable: $glass_auto"
expect "Auto starts with no style override" "absent|$glass_auto" glass_style_readback
glass_pick_style End || fail "the Style Select could not choose Clear"
glass_assert_clear
expect_poll "the Style Select shows the saved Clear choice" '"Clear"' glass_style
glass_pick_style Home || fail "the Style Select could not choose Auto"
expect_poll "choosing Auto removes the override and restores the theme mode" "absent|$glass_auto" glass_style_readback
expect_poll "the Style Select shows Auto again" '"Auto"' glass_style
expect_poll "the Launcher row reads glass on by default" true glass_switch launcher
expect "nothing is saved before a choice" null glass_saved
glass_click_launcher
expect_poll "the Launcher row writes its choice" '{"launcher": "off"}' glass_saved
expect_poll "the Launcher row reads the saved choice back" false glass_switch launcher
glass_click_launcher
expect_poll "turning the Launcher row on again removes the default from the file" null glass_saved
expect "System Settings closes after the Glass rows" ok ipc shell hide window vgs.system

# Keep both controls intact but omit the settings writes from their handlers.
cp -R -- "$repo/shell/plugins/vgs.glass" "$glass_control"
python3 - "$glass_control/Pane.qml" <<'GLASSCONTROL'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
assert not path.is_symlink(), path
text = path.read_text()
for needle in ("root.choose(modelData, wanted);",
               'root.answer(root.write("glassStyle", wanted === "auto" ? undefined : wanted));'):
    assert text.count(needle) == 1, needle
    text = text.replace(needle, "void wanted;")
path.write_text(text)
GLASSCONTROL
expected_errors+=('plugins: hidden by a higher-precedence plugin with the same id: vgs\.glass')
rescan "the write-less Glass control is scanned"
glass_open
glass_click_launcher
expect "control: the write-less row leaves the file without the choice" null glass_saved
glass_pick_style End || fail "the control Style Select could not choose Clear"
glass_style_control() {
  (failures=0; behaviour_failures=0; glass_assert_clear >"$smoke_log_dir/glass-style-control.log"; echo "$failures")
}
expect "control: the write-less Style handler fails the same Clear assertion" 1 glass_style_control
expect "control: the file and resolved Theme still show Auto" "absent|$glass_auto" glass_style_readback
expect "System Settings closes after the Glass control" ok ipc shell hide window vgs.system
rm -rf -- "${glass_control:?}"
cp -- "$glass_saved_copy" "$glass_file.next" && mv -T -- "$glass_file.next" "$glass_file"
rescan "the production Glass page returns"
