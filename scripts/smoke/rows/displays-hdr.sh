# Automatic HDR's production wiring: the real Displays service publishes
# candidate visibility and the existing layer applies native 0/1 at startup,
# after a saved choice, and after the observed output capabilities change.
# The Outputs fixture replaces only the core's JSON observation through
# Probe.popupLoad; native supportsHDR remains untouched. This proves mapping
# and wiring, not original HDR pixels or a physical monitor transition.
# No latency is budgeted. The row uses the shared expect_poll bound and poll interval.
# Mapping and admission mutation controls live in test-hyprland-layer.js
# and test-monitor-logic.js, not a second implementation in this row.
# inputs: shell/plugins/vgs.displays/manifest.json shell/plugins/vgs.displays/Service.qml shell/Core/Registry.qml shell/Core/MonitorLogic.js shell/Core/MonitorState.qml shell/Core/PluginLogic.js shell/Core/HyprlandLayer.js shell/Core/HyprlandLayer.qml shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/PluginPage.qml scripts/smoke/fixtures/displays-hdr/Outputs.qml scripts/smoke/rows/device-fakes.sh scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail
devices_ready displays-hdr || return 0
hdr_user="$home/.config/vgshell/shell.json"
cp -- "$hdr_user" "$sandbox/shell-before-displays-hdr.json"

hdr_option() { hypr -j getoption render:cm_auto_hdr | py_reply 'import json,sys; print(json.load(sys.stdin)["int"])'; }
hdr_presence() { ipc smoke readInstance service vgs.displays layoutValues | py_reply 'import json,sys; print(json.load(sys.stdin)["hdrDisplay"])'; }
hdr_page() { ipc smoke readInstance window vgs.settings page; }
hdr_fields() { ipc smoke itemValues window vgs.settings SettingField key,value | py_reply 'import json,sys; rows=[r for r in json.load(sys.stdin) if r.get("key")=="automaticHdr"]; print("absent" if not rows else str(rows[0]["value"]).lower() if len(rows)==1 else "duplicate")'; }
hdr_pose() {
  local json
  json="$(hypr -j monitors all | py_reply 'import json,sys; rows=json.load(sys.stdin); candidate=sys.argv[1]=="candidate"
for row in rows: row["hardwareDetails"]={"hdr": candidate, "bt2020": candidate}
print(json.dumps({"outputs": rows}))' "$1")" || return 1
  ipc smoke popupCallWith hdr-outputs pose "$json"
}
hdr_choose() { ipc smoke invokeInstance window vgs.settings applySetting "{\"id\":\"vgs.displays\",\"key\":\"automaticHdr\",\"value\":$1}"; }

expect "HDR enables Displays" ok ipc shell setPluginEnabled vgs.displays true
expect_poll "HDR service builds" True record_exists vgs.displays
expect_poll "HDR defaults off at startup" 0 hdr_option
expect "HDR enables Settings" ok ipc shell setPluginEnabled vgs.settings true
expect "HDR opens Settings" ok ipc shell summon window vgs.settings '{}'
expect_poll "HDR Settings maps" 1 window_count Plugins
expect "HDR opens Displays" ok ipc smoke invokeInstance window vgs.settings openPlugin vgs.displays
expect_poll "HDR Displays page opens" '"vgs.displays"' hdr_page
settings_tab_click Settings
expect_poll "HDR is hidden on the nested SDR output" absent hdr_fields
expect "HDR loads the observation fixture" ok ipc smoke popupLoad hdr-outputs "$repo/scripts/smoke/fixtures/displays-hdr/Outputs.qml" service vgs.displays '{}'
expect "HDR poses a candidate observation" ok hdr_pose candidate
expect_poll "HDR candidate is published" present hdr_presence
expect_poll "HDR candidate field defaults off" false hdr_fields
expect "HDR chooses on through Settings" ok hdr_choose true
expect_poll "HDR native option follows user on" 1 hdr_option
expect "HDR poses candidate removal" ok hdr_pose absent
expect_poll "HDR field is hidden after removal" absent hdr_fields
expect_poll "HDR removal overrides the saved opt-in" 0 hdr_option
expect "HDR poses candidate return" ok hdr_pose candidate
expect_poll "HDR saved opt-in returns" true hdr_fields
expect_poll "HDR native option follows output return" 1 hdr_option
expect "HDR chooses off through Settings" ok hdr_choose false
expect_poll "HDR native option follows user off" 0 hdr_option
expect "HDR releases its observation" ok ipc smoke popupCall hdr-outputs release
expect_poll "HDR native output observation returns" absent hdr_presence
expect "HDR drops its fixture" ok ipc smoke popupDrop hdr-outputs
expect "HDR closes Settings" ok ipc shell hide window vgs.settings
expect_poll "HDR Settings is gone" 0 window_count Plugins
expect "HDR disables Displays" ok ipc shell setPluginEnabled vgs.displays false
expect_poll "HDR service is gone while disabled" False record_exists vgs.displays
cp -- "$sandbox/shell-before-displays-hdr.json" "$hdr_user.next"
mv -T -- "$hdr_user.next" "$hdr_user"
