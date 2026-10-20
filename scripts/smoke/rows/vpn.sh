# Saved VPN and WireGuard profiles over the device fakes. The profile
# switches and Import reach recorded nmcli and the fixture terminal only.
# Controls reverse the toggle route, remove the Import callback and discard
# a failed action's visible error and availability guard.
# inputs: scripts/smoke/user-config.sh shell/plugins/vgs.vpn/* shell/plugins/vgs.system/* scripts/smoke/fixtures/tui/vgs.vpn/* scripts/smoke/fixtures/devices/* shell/Commons/Nmcli.js shell/Core/PluginStatus.qml shell/Core/Capabilities.qml shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/Hosts/PaneHost.qml bin/vgshell-tui scripts/smoke/rows/device-fakes.sh scripts/smoke/rows/start-order.sh shell/Ui/controls/RowAction.qml shell/Ui/controls/Switch.qml
set -euo pipefail
devices_ready vpn || return 0
vpn_saved="$sandbox/vpn-shell-before.json"
cp -- "$home/.config/vgshell/shell.json" "$vpn_saved"
vpn_body() { ipc smoke readDescendant "$1" vgs.vpn VpnBody "$2"; }
vpn_call_count() { device_calls "$1" | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
vpn_refresh() { ipc vgs.vpn invoke refresh ""; }
vpn_widget() { ipc smoke readInstance "$(bar_key)" vgs.vpn visible; }
vpn_icon() { ipc smoke readDescendant "$(bar_key)" vgs.vpn BarItem iconName; }
vpn_act() { ipc vgs.vpn invoke action "{\"kind\":\"$1\",\"id\":\"${2:-}\"}"; }
vpn_profile_count() { vpn_body window profileRows | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
vpn_profiles() { ipc smoke statusValues vgs.vpn | py_reply 'import json,sys; v=json.load(sys.stdin).get("profiles"); print("unpublished" if v is None else json.dumps(v[sys.argv[1]]))' "$1"; }
vpn_nm_changes() { device_calls nmcli | py_reply 'import json,sys; print(json.dumps([c for c in json.load(sys.stdin)[int(sys.argv[1]):] if c[:2] == ["connection", "up"] or c[:2] == ["connection", "down"]]))' "$1"; }
vpn_profile_press() {
  local profile name checked view rect x y
  profile="$(ipc smoke readMatchingDescendant window vgs.vpn ProfileRow objectName "vpn-profile:$1" modelData)" || return 1
  name="$(py_reply 'import json,sys; r=json.load(sys.stdin); sys.exit(1) if [r["id"],r["type"],r["active"]] != [sys.argv[1],sys.argv[2],sys.argv[3]=="true"] else print(r["name"])' "$1" "$2" "$3" <<<"$profile")" || return 1
  checked="$(ipc smoke readMatchingDescendant window vgs.vpn Switch objectName "vpn-profile-toggle:$1" checked)" || return 1
  [[ $checked == "$3" ]] || return 1
  # Only the reveal reader needs drawn text. Identity, type, state and
  # the pressed switch's box come from the selected profile's typed data.
  ipc smoke revealScopedText window vgs.system ProfileRow "$name" Switch "" | py_reply 'import json,sys; value=json.load(sys.stdin); sys.exit(0 if type(value) in (int,float) else 1)' || return 1
  view="$(view_at_rest window vgs.system "$name")" || return 1
  [[ $view == \{* ]] || return 1
  rect="$(ipc smoke descendantGeometry window vgs.system | py_reply 'import json,sys; rows=json.load(sys.stdin); matches=[r for r in rows if r["type"]=="Switch" and r["name"]=="vpn-profile-toggle:"+sys.argv[1] and r["visible"]]; sys.exit(1) if len(matches)!=1 else None; b=matches[0]["box"]; origin=rows[0]["box"]; print(json.dumps([b[0]-origin[0],b[1]-origin[1],b[2],b[3]]))' "$1")" || return 1
  read -r x y < <(at_centre 'window:System Settings' "$rect") || return 1
  hover "$((x + 1))" "$y" || return 1
  click "$x" "$y"
}
vpn_import_press() {
  local view rect x y hovered=false
  vpn_import_state before-reveal
  ipc smoke revealText window vgs.system RowAction "Import WireGuard" | py_reply 'import json,sys; value=json.load(sys.stdin); sys.exit(0 if type(value) in (int,float) else 1)' || return 1
  view="$(view_at_rest window vgs.system 'Import WireGuard')" || return 1
  [[ $view == \{* ]] || { vpn_import_state scroll-unsettled; return 1; }
  rect="$(ipc smoke windowGeometry window vgs.vpn RowAction 'Import WireGuard')" || return 1
  [[ $rect == \[* ]] || { vpn_import_state button-absent; return 1; }
  read -r x y < <(at_centre 'window:System Settings' "$rect") || return 1
  # A reveal changes the scene before the pointer has reached the button.
  # Wait for its real hover acknowledgement before the one acceptance click.
  hover "$x" "$y" || return 1
  smoke_poll_tries 200
  for _ in $(seq 1 "$smoke_poll_n"); do
    hovered="$(ipc smoke readMatchingDescendant window vgs.vpn RowAction objectName vpn-import hovered)" || return 1
    [[ $hovered == true ]] && break
    sleep 0.2
  done
  [[ $hovered == true ]] || { vpn_import_state pointer-unreceived; return 1; }
  vpn_import_state before-click
  click "$x" "$y" || return 1
  vpn_import_state after-click
}
# State and geometry alone explain a missed press without profile identities
# or private import data. The pane lives inside System's scrolling view.
vpn_import_state() {
  local key
  printf '        vpn-import phase=%s profiles=%s action=%s window=%s button=%s view=%s\n' "$1" \
    "$(vpn_profiles state)" "$(vpn_profiles action)" "$(surface_box 'window:System Settings')" \
    "$(ipc smoke windowGeometry window vgs.vpn RowAction 'Import WireGuard')" \
    "$(ipc smoke viewHolding window vgs.system 'Import WireGuard')" >&2
  for key in visible enabled hovered pressed activeFocus; do
    printf '        vpn-import button.%s=%s\n' "$key" \
      "$(ipc smoke readMatchingDescendant window vgs.vpn RowAction objectName vpn-import "$key")" >&2
  done
  printf '        vpn-import local-problem=%s\n' \
    "$(vpn_body window localProblem | py_reply 'import json,sys; print("present" if json.load(sys.stdin) else "absent")')" >&2
}
vpn_profile_error() {
  local problem visible drawn
  problem="$(vpn_profiles problem)" || return 1
  visible="$(ipc smoke readMatchingDescendant window vgs.vpn Label objectName vpn-problem visible)" || return 1
  drawn="$(ipc smoke readMatchingDescendant window vgs.vpn Label objectName vpn-problem text)" || return 1
  if [[ $problem != '""' && $drawn == "$problem" && $visible == true ]]; then echo shown; else echo absent; fi
}
# Actor and refresh both fail. Read completion state rather than error wording.
vpn_profile_fail() {
  device_reply nmcli 10 'PRIVATE-FIXTURE-PROFILE-ERROR' connection down id 'Home tunnel'
  device_reply nmcli 10 '/private/fixture.conf' -t -f NAME,TYPE,STATE connection show
  [[ $(vpn_act profile-down 'Home tunnel') == ok ]] || { echo refused; return; }
  for _ in $(seq 1 50); do
    if [[ $(vpn_profiles state) == '"unavailable"' && $(vpn_profiles action) == '""' ]]; then vpn_profile_error; return; fi
    sleep 0.2
  done
  echo unended
}
expected_errors+=('vpn: refused: profile=state' 'vpn: operation=profile-(read|down) completion=failed code=10')
expect "VPN enables over its stand-in" ok ipc shell setPluginEnabled vgs.vpn true
expect_poll "the VPN service is built" True record_exists vgs.vpn
expect "System enables for VPN profiles" ok ipc shell setPluginEnabled vgs.system true
terminal_stand_in
terminal_ready vpn
# No saved profile leaves System Settings as the setup path and hides the bar.
device_reply nmcli 0 "" -t -f NAME,TYPE,STATE connection show
expect "a refresh reads NetworkManager without saved profiles" ok vpn_refresh
expect_poll "NetworkManager reports no saved profile" 0 vpn_profiles count
expect_poll "the VPN icon hides without saved profiles" false vpn_widget
expect "the VPN setup pane opens without saved profiles" ok ipc shell summon window vgs.system '{"pane":"vgs.vpn"}'
expect_poll "the VPN setup pane has no profile rows" 0 vpn_profile_count
expect "the empty setup pane closes" ok ipc shell hide window vgs.system
device_reply nmcli 0 'Office VPN:vpn:deactivated' -t -f NAME,TYPE,STATE connection show
expect "a refresh reads a newly saved profile" ok vpn_refresh
expect_poll "the VPN icon returns with a saved profile" true vpn_widget
expect_poll "a disconnected saved profile draws shield-off" '"shield-off"' vpn_icon
# NetworkManager profiles use the unescaped name as one id argument.
device_reply nmcli 0 $'Office\\:west\\\\desk:vpn:deactivated\nHome tunnel:wireguard:activated' -t -f NAME,TYPE,STATE connection show
device_reply nmcli 0 "" connection up id 'Office:west\desk'
device_reply nmcli 0 "" connection down id 'Home tunnel'
vpn_nm_before="$(vpn_call_count nmcli)" || { fail "vpn: nmcli calls are unreadable"; return 0; }
expect "a refresh reads NetworkManager profiles" ok vpn_refresh
expect_poll "both VPN types publish with their full identities" \
  '[{"id": "Office:west\\desk", "name": "Office:west\\desk", "type": "vpn", "active": false, "ambiguous": false}, {"id": "Home tunnel", "name": "Home tunnel", "type": "wireguard", "active": true, "ambiguous": false}]' vpn_profiles rows
expect_poll "a connected profile draws shield-check" '"shield-check"' vpn_icon
expect "the profile section opens" ok ipc shell summon window vgs.system '{"pane":"vgs.vpn"}'
expect_poll "the pane reads both profiles" 2 vpn_profile_count
vpn_profile_press 'Office:west\desk' vpn false || fail "the VPN profile switch could not be pressed"
expect_poll "the VPN switch runs up with id and one unescaped name" '[["connection", "up", "id", "Office:west\\desk"]]' vpn_nm_changes "$vpn_nm_before"
expect_poll "the profile change ends" '""' vpn_profiles action
vpn_profile_press 'Home tunnel' wireguard true || fail "the WireGuard profile switch could not be pressed"
expect_poll "the WireGuard switch runs down with id and its name" '[["connection", "up", "id", "Office:west\\desk"], ["connection", "down", "id", "Home tunnel"]]' vpn_nm_changes "$vpn_nm_before"
expect_poll "the second profile change ends" '""' vpn_profiles action
expect "a failed profile action stays visible after its failed refresh" shown vpn_profile_fail
expect "profile failure releases the busy state" '""' vpn_profiles action
expect_log "profile action logs only operation and completion" 1 '^.*vpn: operation=profile-down completion=failed code=10$'
expect_log "profile output and private paths stay out of the log" 0 'PRIVATE-FIXTURE-PROFILE-ERROR|/private/fixture.conf'
device_reply nmcli 0 $'Office\\:west\\\\desk:vpn:deactivated\nHome tunnel:wireguard:activated' -t -f NAME,TYPE,STATE connection show
device_reply nmcli 0 "" connection down id 'Home tunnel'
expect "a refresh recovers the profile list" ok vpn_refresh
expect_poll "profiles return after recovery" '"available"' vpn_profiles state
vpn_profile_press 'Home tunnel' wireguard true || fail "the recovered profile switch could not be pressed"
expect_poll "a later successful action clears the profile error" '""' vpn_profiles problem
expect_poll "the recovered action releases the busy state" '""' vpn_profiles action
expect "System closes after profile switches" ok ipc shell hide window vgs.system
# Import runs a fixture copy. The terminal cannot execute the shipped TUI.
expect "VPN disables before the import fixture" ok ipc shell setPluginEnabled vgs.vpn false
expect_poll "the service is gone before the import fixture" False record_exists vgs.vpn
vpn_copy="$home/.config/vgshell/plugins/vgs.vpn"
mkdir -p -- "$vpn_copy"
cp -R -- "$repo/shell/plugins/vgs.vpn/." "$vpn_copy/"
cp -- "$repo/scripts/smoke/fixtures/tui/vgs.vpn/tui/import-wireguard.sh" "$vpn_copy/tui/import-wireguard.sh"
rescan "the import fixture is discovered"
expect "the import fixture enables" ok ipc shell setPluginEnabled vgs.vpn true
expect_poll "the import fixture reads profiles" '"available"' vpn_profiles state
expect "the import fixture pane opens" ok ipc shell summon window vgs.system '{"pane":"vgs.vpn"}'
forget_record
vpn_import_press || fail "the Import button could not be pressed"
expect_poll "Import hands the terminal the declared TUI" "$(words vgs.vpn/import-wireguard tui/import-wireguard.sh)" recorded_tail
vpn_import_state after-launch-check
expect_run_end "the import fixture ends" vgs.vpn/import-wireguard
expect "System closes after Import" ok ipc shell hide window vgs.system
expect_poll "the VPN icon is visible before nmcli disappears" true vpn_widget
mv -- "$shim/nmcli" "$sandbox/vpn-nmcli-hidden"
rescan "the scan reads nmcli absent without a host fallback"
expect_poll "the VPN icon hides while nmcli is missing" false vpn_widget
mv -- "$sandbox/vpn-nmcli-hidden" "$shim/nmcli"
rescan "the nmcli stand-in returns"
expect "a refresh reads the restored nmcli" ok vpn_refresh
expect_poll "the VPN icon returns with its available backend" true vpn_widget
device_reply nmcli 10 "" -t -f NAME,TYPE,STATE connection show
expect "a refresh reads a missing NetworkManager" ok vpn_refresh
expect_poll "profiles hide when NetworkManager cannot answer" '"unavailable"' vpn_profiles state
expect_poll "the VPN icon hides when NetworkManager does not answer" false vpn_widget
expect "Import refuses without NetworkManager" 'refused: import=unavailable' ipc vgs.vpn invoke import-wireguard ""

# Controls mutate a disposable installed copy, never the shipped plugin.
expect "VPN disables before its control copy" ok ipc shell setPluginEnabled vgs.vpn false
expect_poll "the disabled service's build record is gone" False record_exists vgs.vpn
vpn_copy="$home/.config/vgshell/plugins/vgs.vpn"
mkdir -p -- "$vpn_copy"
cp -R -- "$repo/shell/plugins/vgs.vpn/." "$vpn_copy/"
cp -- "$repo/scripts/smoke/fixtures/tui/vgs.vpn/tui/import-wireguard.sh" "$vpn_copy/tui/import-wireguard.sh"
python3 - "$vpn_copy/Service.qml" "$vpn_copy/VpnBody.qml" <<'PYCONTROL'
import pathlib, sys
service, body = map(pathlib.Path, sys.argv[1:])
for path, edits in ((service, [
    ('if (profiles.state !== "available")', 'if (false)'),
    ('root.profileProblem = code === -1 ? "NetworkManager did not answer." : "NetworkManager could not change this connection.";', 'root.profileProblem = "";'),
]), (body, [
    ('kind: wanted ? "profile-up" : "profile-down",', 'kind: wanted ? "profile-down" : "profile-up",'),
    ('root.shell.ipc.call("import-wireguard", "")', 'root.shell.ipc.call("refresh", "")'),
])):
    text = path.read_text()
    for old, new in edits:
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    path.write_text(text)
PYCONTROL
rescan "the VPN control copy is discovered"
expect "the VPN control copy enables" ok ipc shell setPluginEnabled vgs.vpn true
expect_poll "the control's service builds" True record_exists vgs.vpn
device_reply nmcli 0 $'Office\\:west\\\\desk:vpn:deactivated\nHome tunnel:wireguard:activated' -t -f NAME,TYPE,STATE connection show
expect "control: refresh reads available profiles" ok vpn_refresh
expect_poll "control: profiles publish" '"available"' vpn_profiles state
expect "control: the pane opens" ok ipc shell summon window vgs.system '{"pane":"vgs.vpn"}'
vpn_nm_before="$(vpn_call_count nmcli)" || { fail "control: nmcli calls are unreadable"; return 0; }
vpn_profile_press 'Office:west\desk' vpn false || fail "control: the profile switch could not be pressed"
expect "control: the broken toggle route records no connection up" '[]' vpn_nm_changes "$vpn_nm_before"
forget_record
vpn_import_press || fail "control: Import could not be pressed"
expect "control: the broken Import callback launches no TUI" absent recorded
expect "control: the missing failure assignment leaves no visible error" absent vpn_profile_fail
forget_record
expect "control: missing availability guard starts Import on an unavailable backend" ok ipc vgs.vpn invoke import-wireguard ""
expect_poll "control: the unavailable import reaches the fixture terminal" "$(words vgs.vpn/import-wireguard tui/import-wireguard.sh)" recorded_tail
expect_run_end "control: unavailable import fixture ends" vgs.vpn/import-wireguard
expect "control: System closes" ok ipc shell hide window vgs.system
expect "the VPN control copy disables" ok ipc shell setPluginEnabled vgs.vpn false
expect_poll "the VPN control service is gone" False record_exists vgs.vpn
rm -rf -- "${vpn_copy:?}"
rescan "the shipped VPN plugin is restored"
user_config_restore "$vpn_saved"
expect "the VPN row restores the configuration" ok ipc shell reloadConfig
device_reply_clear nmcli
