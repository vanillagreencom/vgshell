# General > Packages and the Updates plugin page edit the same saved
# update option. The real fields emit each edit and the other page reads
# it back. Agent review remains editable with Updates off. System Settings
# refuses a disable while its real Packages page stays mounted. No install,
# update, agent or timing measurement runs; waits use bounded expect_poll.
# A disposable page whose field keeps a private value is the readback's
# control: the same reader sees the stale value after the other page writes.
# inputs: shell/plugins/vgs.packages/* shell/plugins/vgs.system/manifest.json shell/plugins/vgs.system/Window.qml shell/plugins/vgs.updates/manifest.json shell/plugins/vgs.updates/Service.qml shell/plugins/vgs.updates/UpdatesLogic.js shell/plugins/vgs.updates/bin/check shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/PageHeader.qml shell/plugins/vgs.settings/EditSet.qml shell/plugins/vgs.settings/Steps.js shell/plugins/vgs.settings/StatusRow.qml shell/plugins/vgs.settings/StatusLine.qml shell/plugins/vgs.settings/RequirementRow.qml shell/Ui/controls/SettingField.qml shell/Ui/controls/Select.qml shell/Ui/controls/Switch.qml shell/Ui/controls/Field.qml shell/Ui/layout/Section.qml shell/Ui/feedback/SaveBar.qml shell/Hosts/PaneHost.qml shell/Hosts/AppWindow.qml shell/Core/Capabilities.qml shell/Core/Config.qml shell/Core/ConfigLogic.js shell/Core/PluginLogic.js shell/Commons/Reply.js shell/Commons/PageReference.js bin/vgshell bin/vgshell-pkg bin/lib/pkg-review.sh bin/lib/ipc-reply.sh
set -euo pipefail

packages_file="$home/.config/vgshell/shell.json"
packages_saved="$sandbox/shell-before-packages.json"
packages_control="$home/.config/vgshell/plugins/vgs.packages"
cp -- "$packages_file" "$packages_saved"

packages_field() { # HOST ID
  ipc smoke readMatchingDescendant "$1" "$2" SettingField key hideWhenCurrent value
}
packages_choice() {
  ipc smoke readMatchingDescendant window vgs.system Select objectName packageReviewChoice currentIndex
}
packages_owner_enabled() {
  "${shell_env[@]}" PATH="$shell_start_path" "$repo/bin/vgshell" pkg review-settings-read | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["settings"].get("enabled")))'
}
packages_open() {
  expect "System Settings opens Packages" ok ipc shell summon window vgs.system '{"pane":"vgs.packages"}'
  expect_poll "Packages mounts in System Settings" '["vgs.packages"]' window_panes
}

expect "System Settings is always enabled" True plugin_enabled vgs.system
packages_open
expect "System Settings refuses to turn off" 'refused: enabled=vgs.system reason=always-on' ipc shell setPluginEnabled vgs.system false
expect "System Settings stays enabled after the refusal" True plugin_enabled vgs.system
expect "Packages stays shown after the disable refusal" '["vgs.packages"]' window_panes
updates_cache_fresh
expect "Updates enables for the two-page edit" ok ipc shell setPluginEnabled vgs.updates true
expect "the Packages field changes the update option" applied ipc smoke invokeInstance window vgs.system applyField '{"id":"vgs.updates","key":"hideWhenCurrent","value":true}'
expect_poll "Packages reads the saved update option" true packages_field window vgs.system
expect "the Updates settings page opens" ok ipc shell summon window vgs.settings '{"plugin":"vgs.updates"}'
expect_poll "Updates reads the value saved on Packages" true packages_field window vgs.settings
expect "the Updates field changes the same option back" applied ipc smoke invokeInstance window vgs.settings applyField '{"id":"vgs.updates","key":"hideWhenCurrent","value":false}'
expect_poll "the Updates field reads its saved value" false packages_field window vgs.settings
expect "the Plugins window closes after its shared field edit" ok ipc shell hide window vgs.settings
expect_poll "Packages reads the value saved on Updates" false packages_field window vgs.system

expect "Updates turns off while review remains available" ok ipc shell setPluginEnabled vgs.updates false
ipc smoke revealText window vgs.system Field 'Before installing' >/dev/null || fail "the review choice is not reachable"
click_scoped_in 'window:System Settings' window vgs.system Field 'Before installing' Select '' || fail "the review choice does not open"
type_keys -k Home -k Return || fail "the review choice cannot select agent review"
expect_poll "Agent review saves with Updates off" 0 packages_choice
expect_poll "the package owner reads that same saved review choice" true packages_owner_enabled

# A field bound to a private value fails the cross-page reading even though
# both pages still exist and all writes go through the real manager.
expect "System Settings hides before the readback control" ok ipc shell hide window vgs.system
cp -R -- "$repo/shell/plugins/vgs.packages" "$packages_control"
python3 - "$packages_control/Pane.qml" <<'PACKAGESCONTROL'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = 'value: root.updateRow.settings[key]'
assert text.count(needle) == 1, needle
path.write_text(text.replace(needle, 'value: key === "hideWhenCurrent" ? true : root.updateRow.settings[key]'))
PACKAGESCONTROL
expected_errors+=('plugins: hidden by a higher-precedence plugin with the same id: vgs\.packages')
rescan "the private-value Packages control is scanned"
packages_open
expect_poll "control: the shared reader detects the page's stale private value" true packages_field window vgs.system
expect "System Settings closes after the readback control" ok ipc shell hide window vgs.system
rm -rf -- "${packages_control:?}"
cp -- "$packages_saved" "$packages_file.next" && mv -T -- "$packages_file.next" "$packages_file"
rescan "the production Packages page returns"
expect_poll "System Settings remains enabled after restore" True plugin_enabled vgs.system
