# The Glass section of System Settings: the real pane writes a surface's
# choice to shell.json `appearance.glassSurfaces` through capability
# `appearance`, its Switch reads the saved choice back, and the one deciding
# place hands the choice to the surface's glass. A disposable Glass copy
# whose row writes nothing is the readback's control: the same click leaves
# the file without the choice. No pixel, timing or compositor glass is
# measured; waits use bounded expect_poll.
# inputs: shell/plugins/vgs.glass/* shell/plugins/vgs.system/manifest.json shell/plugins/vgs.system/Window.qml shell/Hosts/PaneHost.qml shell/Hosts/AppWindow.qml shell/Core/Capabilities.qml shell/Core/Config.qml shell/Core/ConfigLogic.js shell/Core/PluginLogic.js shell/Commons/ThemeLogic.js shell/Commons/Theme.qml shell/Commons/Glass.js shell/Ui/controls/Switch.qml shell/Ui/controls/Select.qml shell/Ui/controls/FormRow.qml
set -euo pipefail

glass_file="$home/.config/vgshell/shell.json"
glass_saved_copy="$sandbox/shell-before-glass.json"
glass_control="$home/.config/vgshell/plugins/vgs.glass"
cp -- "$glass_file" "$glass_saved_copy"

glass_saved() { python3 -c 'import json,sys; print(json.dumps((json.load(open(sys.argv[1])).get("appearance") or {}).get("glassSurfaces")))' "$glass_file"; }
glass_switch() { ipc smoke readMatchingDescendant window vgs.system Switch objectName "glass-$1" checked; }
glass_style() { ipc smoke readMatchingDescendant window vgs.system Select objectName glassStyle currentText; }
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
expect_poll "the Launcher row reads glass on by default" true glass_switch launcher
expect "nothing is saved before a choice" null glass_saved
glass_click_launcher
expect_poll "the Launcher row writes its choice" '{"launcher": "off"}' glass_saved
expect_poll "the Launcher row reads the saved choice back" false glass_switch launcher
glass_click_launcher
expect_poll "turning the Launcher row on again removes the default from the file" null glass_saved
expect "System Settings closes after the Glass rows" ok ipc shell hide window vgs.system

# A row bound to no write fails the readback: the click leaves the file.
cp -R -- "$repo/shell/plugins/vgs.glass" "$glass_control"
python3 - "$glass_control/Pane.qml" <<'GLASSCONTROL'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = "root.choose(modelData, wanted);"
assert text.count(needle) == 1, needle
path.write_text(text.replace(needle, "void wanted;"))
GLASSCONTROL
expected_errors+=('plugins: hidden by a higher-precedence plugin with the same id: vgs\.glass')
rescan "the write-less Glass control is scanned"
glass_open
glass_click_launcher
expect "control: the write-less row leaves the file without the choice" null glass_saved
expect "System Settings closes after the Glass control" ok ipc shell hide window vgs.system
rm -rf -- "${glass_control:?}"
cp -- "$glass_saved_copy" "$glass_file.next" && mv -T -- "$glass_file.next" "$glass_file"
rescan "the production Glass page returns"
