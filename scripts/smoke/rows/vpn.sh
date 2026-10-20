# Saved VPN and WireGuard profiles by uuid over the nmcli stand-in, with
# the readings of scripts/fixtures/vpn/: each row state, the details of an
# expanded profile, Remove profile behind its confirmation, the bar icon,
# the Updates section, Import and the privacy of nmcli's output. Switches,
# Remove and Import are pressed with the pointer and reach recorded nmcli
# and the fixture terminal only; a held stand-in reply shows a change in
# flight. Controls on a disposable installed copy reverse the toggle
# route, remove on Cancel, remove without the confirmation, break the
# Import callback and drop Import's availability guard.
# inputs: scripts/smoke/user-config.sh shell/plugins/vgs.vpn/* shell/plugins/vgs.system/* scripts/smoke/fixtures/tui/vgs.vpn/* scripts/smoke/fixtures/devices/* scripts/fixtures/vpn/* shell/Commons/Nmcli.js shell/Commons/SettingValues.js shell/Core/PluginStatus.qml shell/Core/Capabilities.qml shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/Core/Notices.qml shell/Core/TuiRunner.qml shell/Hosts/PaneHost.qml shell/Hosts/SummonHost.qml shell/Hosts/NoticeHost.qml bin/vgshell-tui bin/vgshell-scan scripts/smoke/rows/device-fakes.sh scripts/smoke/rows/start-order.sh shell/Ui/controls/RowAction.qml shell/Ui/controls/Switch.qml shell/Ui/controls/BarItem.qml shell/Ui/controls/Button.qml shell/Ui/layout/Disclosure.qml shell/Ui/layout/ListItem.qml shell/Ui/layout/Section.qml shell/Ui/feedback/Dialog.qml shell/Ui/feedback/EmptyState.qml shell/Ui/feedback/Spinner.qml
set -euo pipefail
devices_ready vpn || return 0
vpn_saved="$sandbox/vpn-shell-before.json"
cp -- "$home/.config/vgshell/shell.json" "$vpn_saved"
vpn_fixtures="$repo/scripts/fixtures/vpn"
vpn_home=9d76b882-ead1-4c49-8675-7be6431d5f71
vpn_office=95ea5c2d-312f-4a84-8fd1-9ebc0a4a7581
vpn_travel=5b1c0a9e-2f43-4d7a-9a51-0c3e6e1d2b84
vpn_campus=2e8f4d1a-7c6b-4f3e-8a29-6d5b4c3a2f10
vpn_branch=76ceb7f0-0f5b-4315-9f38-2af0937bb726
vpn_lab=c41d7e02-58b3-4a6f-9e1d-3f2a0b8c7d65
vpn_list_argv=(-t -f NAME,UUID,TYPE,STATE connection show)
# Private text the stand-in's answers carry: nmcli's own lines, the
# certificate path and user vpn.data holds, the WireGuard peer keys and
# the name of the secret a failed connect asked for. None may reach the
# log, the published status or a drawn text.
vpn_private='office-ca\.pem|/home/fixture|fixture-user|xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg|HIgo9xNzJMWLKASShiTqIybxZ0U3wGLiUeJ1PKf8ykw|allowed-ips|passwd-file|journalctl|private-key|nm-l2tp-auth-dialog|Unknown reason|PRIVATE-FIXTURE-PROFILE-ERROR'

vpn_refresh() { ipc vgs.vpn invoke refresh ""; }
vpn_act() { ipc vgs.vpn invoke action "{\"kind\":\"$1\",\"id\":\"$2\"}"; }
vpn_profiles() { ipc smoke statusValues vgs.vpn | py_reply 'import json,sys; v=json.load(sys.stdin).get("profiles"); print("unpublished" if v is None else json.dumps(v[sys.argv[1]]))' "$1"; }
# The published rows as [uuid, name, type, state, service, server, address, failure].
vpn_rows() { ipc smoke statusValues vgs.vpn | py_reply 'import json,sys; v=json.load(sys.stdin).get("profiles"); print("unpublished" if v is None else json.dumps([[r[k] for k in ("uuid","name","type","state","service","server","address","failure")] for r in v["rows"]]))'; }
vpn_call_count() { device_calls nmcli | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
# The `connection VERB` calls nmcli recorded from index FROM on, VERB one
# of up, down or delete.
vpn_changes() { # FROM
  device_calls nmcli | py_reply 'import json,sys; print(json.dumps([c for c in json.load(sys.stdin)[int(sys.argv[1]):] if c[:1] == ["connection"] and c[1:2] in (["up"], ["down"], ["delete"])]))' "$1"
}
vpn_marker() { [[ -f $1 ]] && echo 1 || echo 0; }
# vpn_plant [UUID=STATE|UUID=-]...: list.txt answered for the list read,
# each named profile's STATE set and `-` dropped, and details.txt's blocks
# of the listed VPN profiles answered for the detail read of that uuid
# set, whose argv names the uuids sorted.
vpn_plant() {
  local uuids argv=(-t -f connection.uuid,vpn.service-type,vpn.data,wireguard.peers connection show) uuid
  uuids="$(python3 - "$vpn_fixtures" "$sandbox/vpn-list.txt" "$sandbox/vpn-details.txt" "$@" <<'PY'
import os, sys
fixtures, list_out, details_out, *overrides = sys.argv[1:]
states = dict(o.split("=", 1) for o in overrides)
lines, vpns = [], []
for line in open(os.path.join(fixtures, "list.txt")).read().splitlines():
    if not line:
        continue
    name, uuid, kind, state = line.rsplit(":", 3)
    state = states.get(uuid, state)
    if state == "-":
        continue
    lines.append(":".join([name, uuid, kind, state]))
    if kind in ("vpn", "wireguard"):
        vpns.append(uuid)
blocks = {}
for block in open(os.path.join(fixtures, "details.txt")).read().split("\n\n"):
    head = block.strip().split("\n")[0]
    blocks[head.split(":", 1)[1]] = block.strip()
with open(list_out, "w") as out:
    out.write("\n".join(lines))
with open(details_out, "w") as out:
    out.write("\n\n".join(blocks[u] for u in sorted(vpns)))
print(" ".join(sorted(vpns)))
PY
)" || return 1
  for uuid in $uuids; do argv+=(uuid "$uuid"); done
  device_reply nmcli 0 "$(cat -- "$sandbox/vpn-list.txt")" "${vpn_list_argv[@]}"
  device_reply nmcli 0 "$(cat -- "$sandbox/vpn-details.txt")" "${argv[@]}"
}
# vpn_hold MARKER ARGV...: the planted nmcli reply for ARGV waits for
# $devices_dir/MARKER, recording MARKER.waiting once the call arrives.
vpn_hold() { # MARKER ARGV...
  rm -f -- "${devices_dir:?}/$1" "${devices_dir:?}/$1.waiting"
  python3 - "$devices_dir/replies/nmcli.json" "$@" <<'PY'
import json, os, sys
path, marker, argv = sys.argv[1], sys.argv[2], sys.argv[3:]
rows = json.load(open(path))
next(row for row in rows if row["argv"] == argv)["wait"] = marker
json.dump(rows, open(path + ".next", "w"))
os.replace(path + ".next", path)
PY
}
vpn_release() { : >"$devices_dir/$1"; }
vpn_unhold() { rm -f -- "${devices_dir:?}/$1" "${devices_dir:?}/$1.waiting"; }

# A profile row as drawn, `KEY|CHECKED|LOCKED|SPINNER|TONE`: the state key
# VpnLogic.rowView gave it, whether its switch is on and holds a disabled
# reason, whether its spinner shows and its secondary line's tone;
# `absent` for a row not drawn.
vpn_row() { # UUID NAME
  local view checked reason spinner tone
  view="$(ipc smoke readMatchingDescendant window vgs.vpn ProfileRow objectName "vpn-profile:$1" view)" || return 1
  [[ $view == \{* ]] || { echo absent; return 0; }
  checked="$(ipc smoke readMatchingDescendant window vgs.vpn Switch objectName "vpn-profile-toggle:$1" checked)" || return 1
  reason="$(ipc smoke readMatchingDescendant window vgs.vpn Switch objectName "vpn-profile-toggle:$1" disabledReason)" || return 1
  spinner="$(ipc smoke readMatchingDescendant window vgs.vpn Spinner objectName "vpn-profile-spinner:$1" visible)" || return 1
  tone="$(ipc smoke readMatchingDescendant window vgs.vpn ListItem text "$2" secondaryTone)" || return 1
  py_reply 'import json,sys; v=json.load(sys.stdin); print("|".join([v["key"], sys.argv[1], "locked" if sys.argv[2] not in ("\"\"", "absent") else "free", sys.argv[3], json.loads(sys.argv[4]) if sys.argv[4].startswith("\"") else sys.argv[4]]))' \
    "$checked" "$reason" "$spinner" "$tone" <<<"$view"
}
# An expanded profile's details as drawn, `TYPE|SERVER|ADDRESS|INSTALL|REMOVE`:
# each value as JSON, `hidden` for a row not shown, and whether Install
# plugin and Remove profile show; `closed` while the details are hidden.
vpn_details() { # UUID
  local shown part out=() value visible
  shown="$(ipc smoke readMatchingDescendant window vgs.vpn QQuickColumn objectName "vpn-details:$1" visible)" || return 1
  [[ $shown == true ]] || { echo closed; return 0; }
  for part in type server address; do
    visible="$(ipc smoke readMatchingDescendant window vgs.vpn Label objectName "vpn-$part:$1" visible)" || return 1
    value="$(ipc smoke readMatchingDescendant window vgs.vpn Label objectName "vpn-$part:$1" text)" || return 1
    if [[ $visible == true ]]; then out+=("$value"); else out+=(hidden); fi
  done
  out+=("$(ipc smoke readMatchingDescendant window vgs.vpn RowAction objectName "vpn-install-plugin:$1" visible)") || return 1
  out+=("$(ipc smoke readMatchingDescendant window vgs.vpn RowAction objectName "vpn-remove:$1" visible)") || return 1
  (IFS='|'; echo "${out[*]}")
}
vpn_expanded() { ipc smoke readMatchingDescendant window vgs.vpn ProfileRow objectName "vpn-profile:$1" expanded; }
# The bar icon as drawn, `ICON|SPINNING|TONE`, the tone `warning` when
# its icon draws in the theme's warning colour, else `calm`; `hidden`
# while it hides. The theme writes a colour `#aarrggbb` and the probe
# reads one drawn as `#rrggbbaa`.
vpn_bar() {
  local key shown icon spinning colours warning
  key="$(bar_key)" || return 1
  shown="$(ipc smoke readInstance "$key" vgs.vpn visible)" || return 1
  [[ $shown == true ]] || { echo hidden; return 0; }
  icon="$(ipc smoke readDescendant "$key" vgs.vpn BarItem iconName)" && spinning="$(ipc smoke readDescendant "$key" vgs.vpn BarItem spinning)" \
    && colours="$(ipc smoke itemColours "$key" vgs.vpn BarItem Icon)" && warning="$(ipc smoke themeValue color.warning)" || return 1
  [[ $warning == \"#* ]] || { echo "warning=$warning"; return 0; }
  py_reply 'import json,sys; w=sys.argv[3].strip("\""); w="#" + w[3:] + w[1:3]; print("|".join([sys.argv[1].strip("\""), sys.argv[2], "warning" if any(c == w for b in json.load(sys.stdin) for c in b) else "calm"]))' \
    "$icon" "$spinning" "$warning" <<<"$colours"
}
# Whether the bar icon's tooltip names NEEDLE, such as a profile's name.
vpn_tooltip_names() { ipc smoke readDescendant "$(bar_key)" vgs.vpn BarItem tooltip | py_reply 'import json,sys; print(json.dumps(sys.argv[1] in json.load(sys.stdin)))' "$1"; }
vpn_focus() { ipc smoke activeFocusItem window vgs.vpn; }
vpn_named() { ipc smoke readMatchingDescendant "$1" vgs.vpn "$2" objectName "$3" "$4"; } # HOST TYPE NAME PROPERTY
vpn_confirm() { vpn_named window Dialog vpn-remove-confirm visible; }
vpn_answer() { printf '%s|%s\n' "$(vpn_profiles state)" "$(vpn_profiles count)"; }
vpn_empty_action() { vpn_named window EmptyState vpn-empty actionText | py_reply 'import json,sys; print("offered" if json.load(sys.stdin) else "none")'; }
# Whether any private text is drawn in System Settings or published.
vpn_drawn_private() { ipc smoke itemTexts window vgs.system QQuickText | py_reply 'import json,re,sys; print(json.dumps(any(re.search(sys.argv[1], t) for row in json.load(sys.stdin) for t in row)))' "$vpn_private"; }
vpn_status_private() { ipc smoke statusValues vgs.vpn | py_reply 'import json,re,sys; print(json.dumps(re.search(sys.argv[1], json.dumps(json.load(sys.stdin))) is not None))' "$vpn_private"; }
# The OpenVPN plugin's offer, as [plugin, whether it names the plugin's bus name].
vpn_notice() { notice_shown | py_reply 'import json,sys; s=json.load(sys.stdin); print(json.dumps(None if s is None else [s[0], "org.freedesktop.NetworkManager.openvpn" in json.dumps(s[1:])]))'; }

# vpn_press NAME TYPE TEXT: one pointer press on the control TYPE reading
# TEXT in the profile row drawing NAME, brought into System Settings'
# view first.
vpn_press() {
  local shown
  shown="$(ipc smoke revealScopedText window vgs.system ProfileRow "$1" "$2" "$3")" || return 1
  [[ $shown =~ ^[0-9.]+$ ]] || { echo "vpn_press: no $2 '$3' in $1: $shown" >&2; return 1; }
  [[ $(view_at_rest window vgs.system "$1") == \{* ]] || { echo "vpn_press: the view holding $1 is not at rest" >&2; return 1; }
  click_item "scoped:System Settings" window vgs.vpn ProfileRow "$1" "$2" "$3"
}
vpn_expand() { # LABEL UUID NAME
  [[ $(vpn_expanded "$2") == true ]] && return 0
  vpn_press "$3" ListItem "$3" || { fail "$1: the row of $3 could not be pressed"; return 0; }
  expect_poll "$1: $3 expands" true vpn_expanded "$2"
}
vpn_dialog_press() { click_item "window:System Settings" window vgs.vpn Button "$1"; }
vpn_import_press() {
  local shown
  shown="$(ipc smoke revealText window vgs.system RowAction "Import a VPN file")" || return 1
  [[ $shown =~ ^[0-9.]+$ ]] || { echo "vpn_import_press: no Import to reveal: $shown" >&2; return 1; }
  [[ $(view_at_rest window vgs.system "Import a VPN file") == \{* ]] || return 1
  click_item "window:System Settings" window vgs.vpn RowAction "Import a VPN file"
}

# The steps the controls run again on a mutated copy.
# The off switch of Lab tunnel connects it: the press hands nmcli `up` by
# uuid, and while that reply is held the row shows the change in flight
# with its switch held on and the bar spins.
vpn_connect_step() { # LABEL
  local before
  device_reply nmcli 0 "" connection up uuid "$vpn_lab"
  vpn_hold vpn-up-hold connection up uuid "$vpn_lab"
  read_count before "$1: nmcli calls are unreadable" vpn_call_count
  vpn_press "Lab tunnel" Switch "" || fail "$1: the switch of Lab tunnel could not be pressed"
  expect_poll "$1: the off switch hands NetworkManager up with the uuid" "[[\"connection\", \"up\", \"uuid\", \"$vpn_lab\"]]" vpn_changes "$before"
  expect_poll "$1: the connect is held at the stand-in" 1 vpn_marker "$devices_dir/vpn-up-hold.waiting"
  expect_poll "$1: Connecting spins with the switch held on and locked" 'connecting|true|locked|true|' vpn_row "$vpn_lab" "Lab tunnel"
  expect_poll "$1: the bar spins while the profile connects" 'shield|true|calm' vpn_bar
  expect "$1: the bar tooltip names the connecting profile" true vpn_tooltip_names "Lab tunnel"
  vpn_plant "$vpn_lab=activated"
  vpn_release vpn-up-hold
  expect_poll "$1: the change ends" null vpn_profiles action
  expect_poll "$1: Lab tunnel reads Connected" 'connected|true|free|false|' vpn_row "$vpn_lab" "Lab tunnel"
  vpn_unhold vpn-up-hold
}
# Remove profile opens the confirmation, which takes the focus on Cancel
# and has handed nmcli nothing.
vpn_remove_ask_step() { # LABEL UUID NAME
  local before
  device_reply nmcli 0 "" connection delete uuid "$2"
  read_count before "$1: nmcli calls are unreadable" vpn_call_count
  vpn_expand "$1" "$2" "$3"
  vpn_press "$3" RowAction "Remove profile" || fail "$1: Remove profile of $3 could not be pressed"
  expect_poll "$1: the confirmation shows" true vpn_confirm
  expect_poll "$1: Cancel holds the focus" '["Button","Cancel"]' vpn_focus
  expect "$1: asking removes nothing" '[]' vpn_changes "$before"
  vpn_ask_mark="$before"
}
# Cancel closes it, hands nmcli no delete and gives the focus back to
# Remove profile.
vpn_remove_cancel_step() { # LABEL UUID
  vpn_dialog_press Cancel || fail "$1: Cancel could not be pressed"
  expect_poll "$1: Cancel closes the confirmation" false vpn_confirm
  expect_poll "$1: the focus returns to Remove profile" true vpn_named window RowAction "vpn-remove:$2" activeFocus
  expect "$1: Cancel records no connection delete" '[]' vpn_changes "$vpn_ask_mark"
}
vpn_cancel_steps() { vpn_remove_ask_step "$@"; vpn_remove_cancel_step "$1" "$2"; } # LABEL UUID NAME
vpn_import_step() { # LABEL
  forget_record
  vpn_import_press || fail "$1: Import a VPN file could not be pressed"
  expect_poll "$1: Import hands the terminal the declared TUI" "$(words vgs.vpn/import tui/import.sh)" recorded_tail
  expect_run_end "$1: the import fixture ends" vgs.vpn/import
}
vpn_import_refused_step() { # LABEL
  forget_record
  expect "$1: Import refuses without NetworkManager" 'refused: import=unavailable' ipc vgs.vpn invoke import ""
  expect "$1: the refused import starts no TUI" absent recorded
}
# vpn_control LOG FN ARGS...: FN run as a must-fail control, its output
# in LOG; prints how many of its checks failed.
vpn_control() { (failures=0 behaviour_failures=0; "${@:2}" >"$1" 2>&1; echo "$failures"); }
vpn_control_failed() { [[ $1 -gt 0 ]] && echo failed || echo passed; }

expected_errors+=('vpn: refused: profile=state' 'vpn: operation=profile-up completion=failed code=4$' 'vpn: operation=profile-read completion=failed code=8$')
read_count vpn_private_logged "the instance log is unreadable before the VPN row" log_lines "$vpn_private"
expect "VPN enables over its stand-in" ok ipc shell setPluginEnabled vgs.vpn true
expect_poll "the VPN service is built" True record_exists vgs.vpn
expect "System enables for VPN profiles" ok ipc shell setPluginEnabled vgs.system true
terminal_stand_in
terminal_ready vpn
device_reply nmcli 0 "$(cat -- "$vpn_fixtures/address.txt")" -t -f GENERAL.STATE,IP4.ADDRESS connection show uuid "$vpn_home"
device_reply nmcli 0 $'GENERAL.STATE:activated\nIP4.ADDRESS[1]:10.30.0.2/24' -t -f GENERAL.STATE,IP4.ADDRESS connection show uuid "$vpn_lab"

# No saved profile: the bar hides and the pane draws the no-profile line
# with Import a VPN file, and its Updates section.
device_reply nmcli 0 "" "${vpn_list_argv[@]}"
expect "a refresh reads NetworkManager without saved profiles" ok vpn_refresh
expect_poll "NetworkManager answers with no saved profile" '"available"|0' vpn_answer
expect_poll "the VPN icon hides without saved profiles" hidden vpn_bar
expect "the VPN pane opens without saved profiles" ok ipc shell summon window vgs.system '{"pane":"vgs.vpn"}'
expect_poll "the no-profile line shows" true vpn_named window EmptyState vpn-empty visible
expect "the no-profile line offers Import a VPN file" offered vpn_empty_action
expect "no profile list draws without profiles" false vpn_named window Section vpn-profiles visible
expect "the pane's Updates section shows while NetworkManager answers" true vpn_named window Section vpn-updates visible
expect "Check every shows in the pane" true vpn_named window SegmentedControl vpn-poll visible
expect "the empty pane closes" ok ipc shell hide window vgs.system

# The stand-in profiles: Home tunnel connected; Office VPN without its
# OpenVPN plugin, which the sandbox's system bus does not hold; Travel
# L2TP, Branch IPsec and Lab tunnel off; Campus AnyConnect OpenConnect.
vpn_plant
expect "a refresh reads the saved profiles" ok vpn_refresh
expect_poll "each VPN profile publishes by uuid with its details and nothing else" \
  "[[\"$vpn_home\", \"Home tunnel\", \"wireguard\", \"activated\", \"\", \"203.0.113.10:51820\", \"10.20.0.2\", \"\"], [\"$vpn_office\", \"Office VPN\", \"vpn\", \"\", \"openvpn\", \"vpn.example.com\", \"\", \"\"], [\"$vpn_travel\", \"Travel L2TP\", \"vpn\", \"\", \"l2tp\", \"l2tp.example.net\", \"\", \"\"], [\"$vpn_campus\", \"Campus AnyConnect\", \"vpn\", \"\", \"openconnect\", \"vpn.example.edu\", \"\", \"\"], [\"$vpn_branch\", \"Branch IPsec\", \"vpn\", \"\", \"vpnc\", \"ipsec.example.net\", \"\", \"\"], [\"$vpn_lab\", \"Lab tunnel\", \"wireguard\", \"\", \"\", \"[2001:db8::1]:51820\", \"\", \"\"]]" vpn_rows
expect "the OpenVPN plugin reads missing" true vpn_profiles openvpnMissing
expect_poll "a connected profile draws shield-check" 'shield-check|false|calm' vpn_bar
expect "the bar tooltip names the connected profile" true vpn_tooltip_names "Home tunnel"
expect "System Settings opens on VPN" ok ipc shell summon window vgs.system '{"pane":"vgs.vpn"}'
expect_poll "the pane draws the profiles" true vpn_named window Section vpn-profiles visible
expect_poll "Home tunnel: Connected with its switch on" 'connected|true|free|false|' vpn_row "$vpn_home" "Home tunnel"
expect "Office VPN: Plugin needed, its switch off and locked with its reason" 'plugin-needed|false|locked|false|' vpn_row "$vpn_office" "Office VPN"
expect "Travel L2TP: Off" 'off|false|free|false|' vpn_row "$vpn_travel" "Travel L2TP"
expect "Campus AnyConnect: Not supported here, its switch locked with its reason" 'unsupported|false|locked|false|' vpn_row "$vpn_campus" "Campus AnyConnect"
expect "Branch IPsec: Off" 'off|false|free|false|' vpn_row "$vpn_branch" "Branch IPsec"
expect "Lab tunnel: Off" 'off|false|free|false|' vpn_row "$vpn_lab" "Lab tunnel"
expect "Updates shows beside the profiles" true vpn_named window Section vpn-updates visible
vpn_expand "Home tunnel details" "$vpn_home" "Home tunnel"
expect_poll "Home tunnel shows its type, server and address" '"WireGuard"|"203.0.113.10:51820"|"10.20.0.2"|false|true' vpn_details "$vpn_home"
vpn_expand "Office VPN details" "$vpn_office" "Office VPN"
expect_poll "Office VPN shows its type with Install plugin and its server, no address" '"OpenVPN"|"vpn.example.com"|hidden|true|true' vpn_details "$vpn_office"
vpn_expand "Campus AnyConnect details" "$vpn_campus" "Campus AnyConnect"
expect_poll "Campus AnyConnect keeps its details and Remove profile" '"OpenConnect"|"vpn.example.edu"|hidden|false|true' vpn_details "$vpn_campus"
expect "a locked switch is refused over IPC too" 'refused: profile=unsupported' vpn_act profile-up "$vpn_campus"

vpn_connect_step "connect"
expect_poll "two connected profiles draw shield-check" 'shield-check|false|calm' vpn_bar
expect "the bar tooltip counts the connected profiles" true vpn_tooltip_names 2
device_reply nmcli 0 "" connection down uuid "$vpn_home"
read_count vpn_before "disconnect: nmcli calls are unreadable" vpn_call_count
vpn_press "Home tunnel" Switch "" || fail "the switch of Home tunnel could not be pressed"
expect_poll "the on switch hands NetworkManager down with the uuid" "[[\"connection\", \"down\", \"uuid\", \"$vpn_home\"]]" vpn_changes "$vpn_before"
expect_poll "the disconnect ends" null vpn_profiles action
vpn_plant "$vpn_home=" "$vpn_lab=activated"
expect "a refresh reads Home tunnel off" ok vpn_refresh
expect_poll "Home tunnel: Off" 'off|false|free|false|' vpn_row "$vpn_home" "Home tunnel"
expect "the bar tooltip names the one connected profile" true vpn_tooltip_names "Lab tunnel"
device_reply nmcli 0 "" connection down uuid "$vpn_lab"
expect "Lab tunnel disconnects over IPC" ok vpn_act profile-down "$vpn_lab"
expect_poll "the IPC disconnect ends" null vpn_profiles action
vpn_plant "$vpn_home="
expect "a refresh reads every profile off" ok vpn_refresh
expect_poll "no connected profile draws shield-off" 'shield-off|false|calm' vpn_bar

# Failed connects, classified from nmcli's text alone.
device_reply nmcli 4 "$(cat -- "$vpn_fixtures/up-secrets-password.txt")" connection up uuid "$vpn_travel"
expect "Travel L2TP connects" ok vpn_act profile-up "$vpn_travel"
expect_poll "Travel L2TP: Needs password, its switch off and free" 'needs-password|false|free|false|' vpn_row "$vpn_travel" "Travel L2TP"
expect_poll "a profile that needs its password draws shield-alert in the warning tone" 'shield-alert|false|warning' vpn_bar
expect "the warning tooltip names the profile" true vpn_tooltip_names "Travel L2TP"
device_reply nmcli 4 "$(cat -- "$vpn_fixtures/up-secrets-password.txt")" connection up uuid "$vpn_branch"
expect "Branch IPsec connects" ok vpn_act profile-up "$vpn_branch"
expect_poll "Branch IPsec: a password failure of vpnc asks for sign-in details, locked and never Could not connect" 'sign-in|false|locked|false|' vpn_row "$vpn_branch" "Branch IPsec"
expect "the sign-in switch is refused over IPC" 'refused: profile=sign-in' vpn_act profile-up "$vpn_branch"
device_reply nmcli 4 "$(cat -- "$vpn_fixtures/up-secrets-wireguard.txt")" connection up uuid "$vpn_home"
expect "Home tunnel connects" ok vpn_act profile-up "$vpn_home"
expect_poll "Home tunnel: a WireGuard profile without its key asks for sign-in details, never Could not connect" 'sign-in|false|locked|false|' vpn_row "$vpn_home" "Home tunnel"
device_reply nmcli 4 "$(cat -- "$vpn_fixtures/up-failed.txt")"$'\nPRIVATE-FIXTURE-PROFILE-ERROR' connection up uuid "$vpn_travel"
read_count vpn_before "retry: nmcli calls are unreadable" vpn_call_count
vpn_press "Travel L2TP" Switch "" || fail "the switch of Travel L2TP could not be pressed"
expect_poll "the Needs password switch runs up again" "[[\"connection\", \"up\", \"uuid\", \"$vpn_travel\"]]" vpn_changes "$vpn_before"
expect_poll "Travel L2TP: Could not connect in the danger tone" 'failed|false|free|false|danger' vpn_row "$vpn_travel" "Travel L2TP"
expect_poll "the failed connect keeps shield-alert in the warning tone" 'shield-alert|false|warning' vpn_bar
rescan "a requirements rescan starts"
expect_poll "the rescan clears Branch IPsec's sign-in failure" 'off|false|free|false|' vpn_row "$vpn_branch" "Branch IPsec"
expect "the rescan clears Home tunnel's sign-in failure" 'off|false|free|false|' vpn_row "$vpn_home" "Home tunnel"
expect "the rescan keeps Could not connect" 'failed|false|free|false|danger' vpn_row "$vpn_travel" "Travel L2TP"
device_reply nmcli 4 "$(cat -- "$vpn_fixtures/up-service-missing.txt")" connection up uuid "$vpn_branch"
expect "Branch IPsec connects again" ok vpn_act profile-up "$vpn_branch"
expect_poll "Branch IPsec: Plugin needed from the missing service, locked" 'plugin-needed|false|locked|false|' vpn_row "$vpn_branch" "Branch IPsec"
vpn_expand "Branch IPsec details" "$vpn_branch" "Branch IPsec"
expect_poll "a missing plugin VGS cannot install offers no Install plugin" '"Cisco IPsec (vpnc)"|"ipsec.example.net"|hidden|false|true' vpn_details "$vpn_branch"
expect "each failed connect logs its operation and code alone" 5 log_lines 'vpn: operation=profile-up completion=failed code=4$'

# Remove profile: Cancel keeps the profile; Remove deletes it by uuid and
# the focus moves to the profile now at its place.
vpn_remove_ask_step "remove" "$vpn_campus" "Campus AnyConnect"
vpn_remove_cancel_step "remove" "$vpn_campus"
vpn_remove_ask_step "remove again" "$vpn_campus" "Campus AnyConnect"
vpn_hold vpn-delete-hold connection delete uuid "$vpn_campus"
vpn_dialog_press Remove || fail "the confirmation's Remove could not be pressed"
expect_poll "the delete is held at the stand-in" 1 vpn_marker "$devices_dir/vpn-delete-hold.waiting"
expect_poll "Campus AnyConnect shows Removing with its spinner" 'removing|false|locked|true|' vpn_row "$vpn_campus" "Campus AnyConnect"
vpn_plant "$vpn_home=" "$vpn_campus=-"
vpn_release vpn-delete-hold
expect_poll "the removed profile leaves the pane" absent vpn_row "$vpn_campus" "Campus AnyConnect"
expect "Remove hands NetworkManager one delete by uuid" "[[\"connection\", \"delete\", \"uuid\", \"$vpn_campus\"]]" vpn_changes "$vpn_ask_mark"
expect_poll "the focus moves to the next profile's row" '["ListItem","Branch IPsec"]' vpn_focus
vpn_unhold vpn-delete-hold

expect "nmcli's output and private values stay out of the log" "$vpn_private_logged" log_lines "$vpn_private"
expect "nmcli's output and private values stay out of the published status" false vpn_status_private
expect "nmcli's output and private values are not drawn" false vpn_drawn_private

vpn_press "Office VPN" RowAction "Install plugin" || fail "Install plugin could not be pressed"
expect_poll "Install plugin offers the OpenVPN plugin" '["vgs.vpn", true]' vpn_notice
expect_poll "the offer holds the keyboard" true ipc smoke noticeFocused
type_keys -k Escape || fail "sending Escape to the plugin offer failed"
expect_poll "Escape closes the offer" null vpn_notice
expect "System closes after the profile checks" ok ipc shell hide window vgs.system

# The flyout lists the profiles and has no Updates section.
expect "the flyout opens" ok ipc shell summon panel vgs.vpn '{}'
expect_poll "the flyout lists the profiles" true vpn_named panel ProfileRow "vpn-profile:$vpn_lab" visible
expect "the flyout has no Updates section" false vpn_named panel Section vpn-updates visible
expect "the flyout has no Check every" false vpn_named panel SegmentedControl vpn-poll visible
expect "the flyout closes" ok ipc shell hide panel vgs.vpn

# NetworkManager absent: not running, then nmcli missing.
device_reply nmcli 8 "" "${vpn_list_argv[@]}"
expect "a refresh reads NetworkManager not running" ok vpn_refresh
expect_poll "profiles read NetworkManager not running" '"not-running"' vpn_profiles state
expect_poll "the VPN icon hides while NetworkManager does not run" hidden vpn_bar
vpn_import_refused_step "not running"
mv -- "$shim/nmcli" "$sandbox/vpn-nmcli-hidden"
rescan "the scan reads nmcli absent without a host fallback"
expect_poll "profiles read nmcli missing" '"missing"' vpn_profiles state
expect_poll "the VPN icon hides while nmcli is missing" hidden vpn_bar
mv -- "$sandbox/vpn-nmcli-hidden" "$shim/nmcli"
rescan "the nmcli stand-in returns"

# Import runs a fixture copy, since the terminal runs no shipped TUI. The
# same copy then carries the controls.
expect "VPN disables before the import fixture" ok ipc shell setPluginEnabled vgs.vpn false
expect_poll "the service is gone before the import fixture" False record_exists vgs.vpn
vpn_copy="$home/.config/vgshell/plugins/vgs.vpn"
mkdir -p -- "$vpn_copy"
cp -R -- "$repo/shell/plugins/vgs.vpn/." "$vpn_copy/"
cp -- "$repo/scripts/smoke/fixtures/tui/vgs.vpn/tui/import.sh" "$vpn_copy/tui/import.sh"
rescan "the import fixture is discovered"
vpn_plant
expect "the import fixture enables" ok ipc shell setPluginEnabled vgs.vpn true
expect_poll "the import fixture reads profiles" '"available"' vpn_profiles state
expect "the import fixture pane opens" ok ipc shell summon window vgs.system '{"pane":"vgs.vpn"}'
vpn_import_step "import"
expect "System closes after Import" ok ipc shell hide window vgs.system

# Controls mutate the disposable installed copy, never the shipped plugin.
expect "VPN disables before its controls" ok ipc shell setPluginEnabled vgs.vpn false
expect_poll "the disabled service's build record is gone" False record_exists vgs.vpn
python3 - "$vpn_copy/Service.qml" "$vpn_copy/VpnBody.qml" <<'PYCONTROL'
import pathlib, sys
service, body = map(pathlib.Path, sys.argv[1:])
for path, edits in ((service, [
    ('if (profiles.state !== "available") return "refused: import=unavailable";', 'if (false) return "refused: import=unavailable";'),
]), (body, [
    ('root.act(wanted ? "profile-up" : "profile-down",', 'root.act(wanted ? "profile-down" : "profile-up",'),
    ('answered(shell.ipc.call("import", ""),', 'answered(shell.ipc.call("refresh", ""),'),
    ('onRejected: root.cancelRemove()', 'onRejected: root.acceptRemove()'),
])):
    text = path.read_text()
    for old, new in edits:
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    path.write_text(text)
PYCONTROL
rescan "the VPN control copy is discovered"
vpn_plant
expect "the VPN control copy enables" ok ipc shell setPluginEnabled vgs.vpn true
expect_poll "control: profiles publish" '"available"' vpn_profiles state
expect "control: the pane opens" ok ipc shell summon window vgs.system '{"pane":"vgs.vpn"}'
expect_poll "control: the pane draws Lab tunnel off" 'off|false|free|false|' vpn_row "$vpn_lab" "Lab tunnel"
expect "control: the reversed toggle route fails the connect step" failed vpn_control_failed "$(vpn_control "$sandbox/vpn-toggle-control.log" vpn_connect_step control)"
control_output "$sandbox/vpn-toggle-control.log"
vpn_unhold vpn-up-hold
expect "control: a Cancel that removes fails the Cancel step" failed vpn_control_failed \
  "$(vpn_control "$sandbox/vpn-cancel-control.log" vpn_cancel_steps control "$vpn_campus" "Campus AnyConnect")"
control_output "$sandbox/vpn-cancel-control.log"
expect "control: the broken Import callback fails the import step" failed vpn_control_failed "$(vpn_control "$sandbox/vpn-import-control.log" vpn_import_step control)"
control_output "$sandbox/vpn-import-control.log"
device_reply nmcli 8 "" "${vpn_list_argv[@]}"
expect "control: a refresh reads NetworkManager not running" ok vpn_refresh
expect_poll "control: profiles read NetworkManager not running" '"not-running"' vpn_profiles state
expect "control: the dropped availability guard fails the refusal step" failed vpn_control_failed "$(vpn_control "$sandbox/vpn-guard-control.log" vpn_import_refused_step control)"
control_output "$sandbox/vpn-guard-control.log"
expect_run_end "control: the unguarded import fixture ends" vgs.vpn/import
expect "control: System closes" ok ipc shell hide window vgs.system
expect "VPN disables before its second control" ok ipc shell setPluginEnabled vgs.vpn false
expect_poll "the first control's service is gone" False record_exists vgs.vpn
cp -- "$repo/shell/plugins/vgs.vpn/VpnBody.qml" "$vpn_copy/VpnBody.qml"
python3 - "$vpn_copy/VpnBody.qml" <<'PYASKCONTROL'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = 'onRemoveRequested: root.askRemove(modelData)'
assert text.count(old) == 1, old
path.write_text(text.replace(old, 'onRemoveRequested: root.act("profile-remove", modelData.uuid, "")'))
PYASKCONTROL
rescan "the unconfirmed-remove control is discovered"
vpn_plant
expect "the unconfirmed-remove control enables" ok ipc shell setPluginEnabled vgs.vpn true
expect_poll "control: profiles publish again" '"available"' vpn_profiles state
expect "control: the pane opens again" ok ipc shell summon window vgs.system '{"pane":"vgs.vpn"}'
expect_poll "control: the pane draws Campus AnyConnect" 'unsupported|false|locked|false|' vpn_row "$vpn_campus" "Campus AnyConnect"
expect "control: a Remove profile without the confirmation fails the ask step" failed vpn_control_failed \
  "$(vpn_control "$sandbox/vpn-ask-control.log" vpn_remove_ask_step control "$vpn_campus" "Campus AnyConnect")"
control_output "$sandbox/vpn-ask-control.log"
expect_poll "control: the unconfirmed remove ends" null vpn_profiles action
expect "control: System closes again" ok ipc shell hide window vgs.system
expect "the VPN control copy disables" ok ipc shell setPluginEnabled vgs.vpn false
expect_poll "the VPN control service is gone" False record_exists vgs.vpn
rm -rf -- "${vpn_copy:?}"
rescan "the shipped VPN plugin is restored"
user_config_restore "$vpn_saved"
expect "the VPN row restores the configuration" ok ipc shell reloadConfig
device_reply_clear nmcli
vpn_unhold vpn-up-hold
vpn_unhold vpn-delete-hold
rm -f -- "${sandbox:?}"/vpn-{list,details}.txt
