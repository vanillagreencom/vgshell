# NetworkManager-only network views against S08's private NM mock. The
# device guard checks the running shell before it reads Networking. The
# existing stand-ins record systemctl/nmcli argv; fixtures/devices/network.py
# extends only the NM mock. Each kind reads its own delivered status.
# No latency budget is measured. Polls use expect_poll's IPC round trip.
# The production reprompt control suppresses the password prompt in a
# sandbox plugin copy. The secret reader's control plants a synthetic log.
# The password prompt's control plants the field in the body, outside the
# dialog, and drops the prompt's reading of its scrolled view, in a sandbox
# plugin copy. Its focus controls, in another copy, drop the hand-off to the
# dialog when it shows and leave the page enabled behind it. The scrim's
# control, in another copy, parents the Scrim back to the body, so it
# leaves the dropdown's header and footer undimmed and a click on the
# Wi-Fi switch turns Wi-Fi off.
# inputs: scripts/smoke/user-config.sh shell/plugins/vgs.network/* shell/Commons/Nmcli.js shell/Commons/qmldir shell/plugins/vgs.system/* shell/Core/* shell/Hosts/* shell/Ui/* shell/Commons/* shell/shell.qml config/shell.json bin/vgshell-scan bin/vgshell-plugin-judge bin/lib/check-manifests.js bin/lib/qml-library.js scripts/smoke/fixtures/devices/* scripts/smoke/rows/device-fakes.sh scripts/smoke/rows/start-order.sh scripts/smoke/rows/overlay-capture.sh
set -euo pipefail
devices_ready network || return 0
net_fixture() { python3 "$repo/scripts/smoke/fixtures/devices/network.py" "unix:path=$rt_dir/system-bus" "$1"; }
net_expect_fixture() { # LABEL ACTION
  local reply status=0
  reply="$(net_fixture "$2" 2>&1)" || status=$?
  if [[ $status -ne 0 || $reply != ok ]]; then
    fail "network: fixture=$2 status=$status $reply"
    return 1
  fi
  ok "$1"
}
net_expect_fixture "the mock has a saved Wi-Fi profile" prepare || return 0
net_saved="$sandbox/network-shell-before.json"
cp -- "$home/.config/vgshell/shell.json" "$net_saved"
# Sharing stands over only the two CLI readers it owns. Every other nmcli
# call still reaches S08's recorded stand-in, never the host command.
net_qr_dir="$sandbox/network-qr"
mkdir -p -- "$net_qr_dir"
cp -- "$repo/scripts/smoke/fixtures/devices/network-qr-tools.py" "$net_qr_dir/nmcli"
cp -- "$repo/scripts/smoke/fixtures/devices/network-qr-tools.py" "$net_qr_dir/qrencode"
net_qr_world() { python3 - "$net_qr_dir/world.json" "$1" <<'PYWORLD'
import hashlib,json,pathlib,sys
payload=b"WIFI:T:WPA;S:VGS Smoke Wi-Fi;P:network-share-fixture-secret;;"
pathlib.Path(sys.argv[1]).write_text(json.dumps({"active":"--", "profiles":[{"uuid":"profile-smoke", "ssid":"VGS Smoke Wi-Fi", "key_management":"wpa-psk", "hidden":"no", "secret_codes":[110,101,116,119,111,114,107,45,115,104,97,114,101,45,102,105,120,116,117,114,101,45,115,101,99,114,101,116]}], "payload_digest":hashlib.sha256(payload).hexdigest(), "hold":sys.argv[2]=="hold"}))
PYWORLD
}
net_qr_world ready
net_join_dir="$sandbox/network-join"
mkdir -p -- "$net_join_dir"
net_join_world() { python3 - "$net_join_dir/world.json" "$1" "$2" <<'PYJOINWORLD'
import hashlib,json,pathlib,sys
secret="network-smoke-joined-secret"
pathlib.Path(sys.argv[1]).write_text(json.dumps({"secret_codes":list(map(ord,secret)), "stdin_digest":hashlib.sha256((sys.argv[2]+":"+secret+"\n").encode()).hexdigest(), "fail":{"up":"refused"} if sys.argv[3]=="refused" else {"up":"failed"}, "hold":"up" if sys.argv[3]=="hold" else None}))
PYJOINWORLD
}
net_join_world 802-11-wireless-security.psk refused
# A details read waits while $net_hold exists, so the row sees its loading state.
net_hold="$sandbox/network-details-hold"
net_connectivity_dir="$sandbox/network-connectivity"
mkdir -p -- "$net_connectivity_dir"
cat >"$net_connectivity_dir/PollObserver.qml" <<'QMLPOLL'
import QtQuick
QtObject {
    property var service: null
    readonly property var timer: service === null ? null : Array.from(service.resources).find(resource => resource.objectName === "network-connectivity-poll") || null
    readonly property var reading: timer === null ? null : ({ interval: timer.interval, running: timer.running })
}
QMLPOLL
cat >"$net_connectivity_dir/check.py" <<'PYNMCHECK'
import pathlib,sys,time
import dbus
address,folder=sys.argv[1:]
root=pathlib.Path(folder)
(root/"ready").touch()
while (root/"hold").exists(): time.sleep(0.05)
if (root/"skip-call").exists():
    print("portal")
else:
    manager=dbus.Interface(dbus.bus.BusConnection(address).get_object("org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager"), "org.freedesktop.NetworkManager")
    print({0:"unknown",1:"none",2:"portal",3:"limited",4:"full"}[int(manager.CheckConnectivity())])
PYNMCHECK
printf '#!/usr/bin/env bash\nif [[ " $* " == *" --get-values "* ]]; then\n  export NETWORK_QR_WORLD=%q NETWORK_QR_CALLS=%q NETWORK_QR_READY=%q\n  exec python3 %q "$@"\nfi\nif [[ " $* " == *" connection add "* || " $* " == *" connection up "* || " $* " == *" connection delete "* ]]; then exec python3 %q %q %q %q "$@"; fi\nif [[ " $* " == *" networking connectivity check "* && -e %q ]]; then exec python3 %q %q %q; fi\nif [[ " $* " == *" device show "* ]]; then while [[ -e %q ]]; do sleep 0.05; done; fi\nexec %q "$@"\n' "$net_qr_dir/world.json" "$net_qr_dir/calls" "$net_qr_dir/ready" "$net_qr_dir/nmcli" "$repo/scripts/smoke/fixtures/devices/network-join-nmcli.py" "$net_join_dir/world.json" "$net_join_dir/calls" "$net_join_dir/ready" "$net_connectivity_dir/active" "$net_connectivity_dir/check.py" "unix:path=$rt_dir/system-bus" "$net_connectivity_dir" "$net_hold" "$(sentinel_saved "$shim/nmcli")" | sentinel_stand_over "$shim/nmcli"
net_qr_had_shim=false
if [[ -e $shim/qrencode ]]; then net_qr_had_shim=true; else printf '#!/usr/bin/env bash\nexit 1\n' >"$shim/qrencode"; fi
printf '#!/usr/bin/env bash\nexport NETWORK_QR_WORLD=%q NETWORK_QR_CALLS=%q NETWORK_QR_READY=%q\nexec python3 %q "$@"\n' "$net_qr_dir/world.json" "$net_qr_dir/calls" "$net_qr_dir/ready" "$net_qr_dir/qrencode" | sentinel_stand_over "$shim/qrencode"
net_qr_calls() { python3 - "$net_qr_dir/calls" <<'PYCALLS'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);calls=[json.loads(line) for line in p.read_text().splitlines()] if p.exists() else []
print("private" if any(tool=="nmcli" and "--show-secrets" in args for tool,args in calls) else "public")
PYCALLS
}
net_qr_state() { ipc smoke networkShare "$1" | py_reply 'import json,sys; s=sys.stdin.read().strip(); r=json.loads(s) if s.startswith("{") else None; print("ready" if r and r["state"]=="ready" and r["side"]==3 and r["visible"] and r["moduleSize"]>0 and int(r["moduleSize"])==r["moduleSize"] else s)'; }
# Network shares a Wi-Fi QR image. It opens no screen-capture session.
net_qr_owner_count() { ipc smoke readDescendant panel vgs.network NetworkBody shareTarget | py_reply 'import json,sys; s=sys.stdin.read().strip(); print(0 if s=="absent" else int(json.loads(s) is not None))'; }
net_qr_released() {
  expect_poll "$1: Wi-Fi sharing releases its QR owner" 0 net_qr_owner_count
  printf 'network-lifetime: case=%s qrOwners=%s\n' "$1" "$(net_qr_owner_count)"
}
net_qr_encoder_ready() { if [[ -f $net_qr_dir/ready ]]; then echo yes; else echo no; fi; }
net_menu_selection() { ipc smoke menus panel vgs.network | py_reply 'import json,sys; print(json.dumps([m["current"] for m in json.load(sys.stdin) if m["opened"]]))'; }
# Menu.opened can precede its native keyboard focus. End is idempotent:
# every poll delivers a real key and observes the last action before Enter.
net_menu_end() { type_keys -k End; net_menu_selection; }
net_qr_child_stopped() { python3 - "$net_qr_dir/ready" <<'PYSTOP'
import os,pathlib,sys
p=pathlib.Path(sys.argv[1])
if not p.exists():
    print("not-started")
else:
    try: os.kill(int(p.read_text()),0)
    except ProcessLookupError: print("stopped")
    else: print("running")
PYSTOP
}
net_unit() { device_reply systemctl 0 "$1" show --property=LoadState --property=ActiveState NetworkManager.service; }
net_permission() { device_reply nmcli 0 "org.freedesktop.NetworkManager.network-control:$1" -t -f PERMISSION,VALUE general permissions; }
net_state() { ipc smoke readInstance service vgs.network state; }
net_snapshot() { ipc smoke statusValues vgs.network; }
net_prompt() { net_snapshot | py_reply 'import json,sys; print("prompt" if json.load(sys.stdin)["network"]["prompt"] else "none")'; }
net_joined() { net_snapshot | py_reply 'import json,sys; print(any(r["connected"] for r in json.load(sys.stdin)["network"]["wifi"]))'; }
net_known() { net_snapshot | py_reply 'import json,sys; print(any(r["known"] for r in json.load(sys.stdin)["network"]["wifi"]))'; }
net_action() { net_snapshot | py_reply 'import json,sys; print(json.load(sys.stdin)["network"]["action"]["kind"])'; }
net_changing() { net_snapshot | py_reply 'import json,sys; print(any(r["changing"] for r in json.load(sys.stdin)["network"]["wifi"]))'; }
net_problem() { ipc smoke readInstance service vgs.network problem; }
net_radio() { net_snapshot | py_reply 'import json,sys; print(json.load(sys.stdin)["network"]["wifiEnabled"])'; }
net_shown() { [[ $(ipc smoke instanceGeometry "$1" vgs.network) != absent ]] && echo shown || echo hidden; }
net_rows() { ipc smoke readDescendant "$1" vgs.network NetworkBody rows | py_reply 'import json,sys; print(json.dumps([[r["name"],r["strength"],r["known"],r["connected"]] for r in json.load(sys.stdin)]))'; }
net_header() { ipc smoke paneHeader panel vgs.network | py_reply 'import json,sys
h=json.load(sys.stdin)
if h=="absent":
    print("absent"); raise SystemExit
s=h["switchBox"]; t=h["titleBox"]; g=h["gearBox"]
right = (g[0] - h["inlineGap"]) if g else h["contentRight"]
ok = h["title"] == "Network" and t is not None and s is not None and abs(t[0] - h["contentLeft"]) < 0.5 and abs(s[0] + s[2] - right) < 0.5 and abs(s[1] + s[3] / 2 - h["titleCenterY"]) <= 0.5
print(json.dumps({"placed": ok, "checked": h["switchChecked"], "enabled": h["switchEnabled"]}, sort_keys=True))'; }
net_wifi_field_absent() { ipc smoke itemValues panel vgs.network Field label,visible | py_reply 'import json,sys; print("absent" if all(not (r.get("label") == "Wi-Fi" and r.get("visible")) for r in json.load(sys.stdin)) else "visible")'; }
net_placed() { bar_widget_ids | py_reply 'import json,sys; print(any("vgs.network" in ids for ids in json.load(sys.stdin)))'; }
net_do() { ipc vgs.network invoke action "{\"kind\":\"$1\",\"key\":\"[\\\"wlan0\\\",\\\"VGS Smoke Wi-Fi\\\"]\"}"; }
net_refresh() { ipc vgs.network invoke refresh ""; }
net_widget_click() { rest_pointer && click_centre "$(bar_key)" vgs.network; }
# The password prompt of the view HOST holds: whether its dialog shows,
# whether the dialog names the prompted network, and its top in the body.
net_dialog() { ipc smoke readMatchingDescendant "$1" vgs.network Dialog objectName network-prompt visible; }
net_dialog_names() { ipc smoke readMatchingDescendant "$1" vgs.network Label objectName network-prompt-name text | py_reply 'import json,sys; print("VGS Smoke Wi-Fi" in json.load(sys.stdin))'; }
net_reason_matches() {
  local reason
  reason="$(ipc smoke readMatchingDescendant "$1" vgs.network Label objectName network-prompt-reason text)" || return 1
  net_snapshot | py_reply 'import json,sys; problem=json.load(sys.stdin)["network"]["problem"]; print("same" if problem and json.loads(sys.argv[1])==problem else "different")' "$reason"
}
net_saved_reason() { expect "$1: the dialog draws the service failure reason" same net_reason_matches panel; }
net_hint_suppressed() { expect "$1: the list hint is hidden under the dialog" false ipc smoke readMatchingDescendant panel vgs.network LinkText objectName network-problem visible; }
# net_dialog_focus HOST: [whether the dialog holds the focus, whether the
# body holds it].
net_dialog_focus() { printf '[%s, %s]\n' "$(ipc smoke activeFocusWithin "$1" vgs.network Dialog)" "$(ipc smoke activeFocusIn "$1" vgs.network)"; }
net_dialog_y() { ipc smoke itemValues "$1" vgs.network Dialog objectName,y | py_reply 'import json,sys; print(next(r["y"] for r in json.load(sys.stdin) if r["objectName"]=="network-prompt"))'; }
# net_dropdown_click READER TYPE TEXT: one real click on the centre of the
# dropdown item the probe's READER, itemGeometry or labelledGeometry, finds.
net_dropdown_click() {
  local rect x y
  rect="$(ipc smoke "$1" panel vgs.network "$2" "$3")" || return 1
  [[ $rect == \[* ]] || { echo "net_dropdown_click: no $2 $3: $rect" >&2; return 1; }
  read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x + w / 2), int(y + h / 2))' "$rect") || return 1
  hover "$((x + 1))" "$y" && click "$x" "$y"
}
net_dropdown_button() { net_dropdown_click itemGeometry Button "$1"; }
# net_scrim_covers: `covers` while the shown Scrim's box is the dropdown
# Surface's, its header and footer included, else `partial` with both boxes.
net_scrim_covers() { ipc smoke descendantGeometry panel vgs.network | py_reply 'import json,sys
items=json.load(sys.stdin); box=lambda t: next((i["box"] for i in items if i["type"]==t and i["visible"]), None)
print("covers" if box("Scrim") is not None and box("Scrim")==box("Surface") else "partial scrim=%s surface=%s" % (box("Scrim"), box("Surface")))'; }
# net_scrim_click LABEL READER TYPE TEXT: Tab moves the dialog's focus to
# Cancel, then a real click on that dropdown control lands on the scrim,
# which hands the focus back to the field: the click arrived, and the
# control under it changed nothing and took no focus.
net_scrim_click() {
  type_keys -k Tab
  expect_poll "$1: Tab moves the focus to Cancel" '{"masked":true,"length":7,"focused":false}' ipc smoke networkField panel
  net_dropdown_click "${@:2}" || fail "$1: the click failed"
  expect_poll "$1: the scrim hands the focus back to the field" '{"masked":true,"length":7,"focused":true}' ipc smoke networkField panel
  expect "$1: the dialog keeps the focus" '[true, true]' net_dialog_focus panel
  expect "$1: Wi-Fi stays on" True net_radio
  expect "$1: no radio action starts" idle net_action
  expect "$1: the dropdown stays open" shown net_shown panel
}
# net_reprompt LABEL: the saved profile's activation fails on its password,
# so the service prompts, and the failed activation is removed.
net_reprompt() {
  expect "$1: the saved profile starts" ok net_do connect
  expect_poll "$1: the activation is pending" connect net_action
  net_expect_fixture "$1: the mock refuses the saved password" fail || return 1
  expect_poll "$1: the service prompts" prompt net_prompt
  net_expect_fixture "$1: the failed activation is removed" drop-active || return 1
}
# net_share_prompt LABEL: in the dropdown, whose list holds the keyboard,
# Share QR code opens, the saved profile's password fails behind it, and
# Close QR code closes Share over the prompt that waited.
net_share_prompt() {
  type_keys -k Menu
  expect_poll "$1: the sharing menu opens" true ipc smoke readDescendant panel vgs.network Menu opened
  expect_poll "$1: the sharing menu selects Share QR code" '["Share QR code"]' net_menu_end
  type_keys -k Return
  expect_poll "$1: Share opens" ready net_qr_state panel
  net_reprompt "$1" || return 1
  expect "$1: the prompt waits behind Share" false net_dialog panel
  type_keys -k Return
  expect_poll "$1: Close QR code closes Share" closed ipc smoke networkShare panel
  expect_poll "$1: the prompt that waited opens its dialog" true net_dialog panel
}
# net_search_click: one real click on the System sidebar's search, found by
# the query it holds. The password field holds typed text first, so no
# empty field reads as an empty query.
net_search_click() {
  local query
  query="$(ipc smoke readDescendant window vgs.system Sidebar query | py_reply 'import json,sys; print(json.load(sys.stdin))')" || return 1
  click_in 'window:System Settings' window vgs.system TextField "$query"
}
# net_tab_to_body: Tab from the focused System search, one stop at a time,
# until a stop inside the network body holds the focus. Each Tab waits up
# to 2 s, polled every 0.2 s, for the body to take the focus before the
# next one, over at most six stops; 1 when none reaches the body. The
# System window's scroll areas take Tab stops before the pane.
net_tab_to_body() {
  local stop poll
  for ((stop = 0; stop < 6; stop++)); do
    type_keys -k Tab || return 1
    for ((poll = 0; poll < 10; poll++)); do
      [[ $(ipc smoke activeFocusIn window vgs.network) == true ]] && return 0
      sleep 0.2
    done
  done
  return 1
}
# A short nested System window gives the prompt a page that really scrolls,
# even when hiding the list's reason line lets the normal window fit it.
net_follow_size() { window_of 'System Settings' size | py_reply 'import json,sys; s=sys.stdin.read().strip(); r=json.loads(s) if s.startswith("[") else []; print(json.dumps(r[0]) if r else "unreadable")'; }
net_follow_overflow() { ipc smoke viewHolding window vgs.system Cancel | py_reply 'import json,sys; s=sys.stdin.read().strip(); r=json.loads(s) if s.startswith("{") else {}; print("yes" if r.get("contentHeight",0)>r.get("height",0)>0 else "no")'; }
net_follow_shorten() {
  local layout
  layout="$(window_of 'System Settings' address size | py_reply 'import json,sys; s=sys.stdin.read().strip(); r=json.loads(s) if s.startswith("[") else []; print("%s %s %s" % (r[0],r[1][0],r[1][1]) if len(r)==2 else "unreadable")')" || return 1
  read -r net_follow_address net_follow_width net_follow_height <<<"$layout"
  [[ $net_follow_address =~ ^0x[[:xdigit:]]+$ && $net_follow_width =~ ^[0-9]+$ && $net_follow_height =~ ^[0-9]+$ ]] || return 1
  net_follow_short_height=$((net_follow_height / 2))
  expect "the scroll check shortens the nested System window" ok hypr dispatch "hl.dsp.window.resize({ x = $net_follow_width, y = $net_follow_short_height, relative = false, window = \"address:$net_follow_address\" })"
  expect_poll "the shorter System window reads back its size" "[$net_follow_width, $net_follow_short_height]" net_follow_size
  expect_poll "the prompt's page has real overflow" yes net_follow_overflow
}
net_follow_restore() {
  expect "the scroll check restores the nested System window" ok hypr dispatch "hl.dsp.window.resize({ x = $net_follow_width, y = $net_follow_height, relative = false, window = \"address:$net_follow_address\" })"
  expect_poll "System reads back its original size" "[$net_follow_width, $net_follow_height]" net_follow_size
}
# net_dialog_follows HOST: the dialog follows a measured increase in the
# page's scroll. Its enabled title first moves to the view's top third,
# then Cancel moves there. The disabled page behind it takes no focus.
net_dialog_follows() {
  local before after prior scrolled
  ipc smoke revealText "$1" vgs.system Label 'Wi-Fi password' >/dev/null || return 1
  before="$(net_dialog_y "$1")" || return 1
  prior="$(ipc smoke viewHolding "$1" vgs.system Cancel | py_reply 'import json,sys; s=sys.stdin.read().strip(); r=json.loads(s) if s.startswith("{") else {}; print(r.get("contentY","unreadable"))')" || return 1
  scrolled="$(ipc smoke revealText "$1" vgs.system Button Cancel)" || return 1
  after="$(net_dialog_y "$1")" || return 1
  python3 -c 'import sys; b,a,p,s=sys.argv[1:]; moved=all(v.replace(".","",1).isdigit() for v in (b,a,p,s)) and float(s)>float(p); result="follows" if moved and float(a)>float(b) else "fixed" if moved else "unscrolled"; print(result if result=="follows" else "%s before=%s after=%s prior=%s scrolled=%s" % (result,b,a,p,s))' "$before" "$after" "$prior" "$scrolled"
}
net_unit $'LoadState=loaded\nActiveState=active'
net_permission yes
rescan "the private sharing commands are discovered"
expect "Network enables over the private mock" ok ipc shell setPluginEnabled vgs.network true
expect_poll "Network's service is built" True record_exists vgs.network
# start-order already enabled the service before these command replies existed.
# Refresh its real probes and observe their results rather than rebuilding it.
expect "Network refreshes the planted backend replies" ok net_refresh
expect_poll "Network observes the running private service" '"running"' ipc smoke readInstance service vgs.network serviceState
expect_poll "Network observes the allowed private permission" '"allowed"' ipc smoke readInstance service vgs.network access
expect_poll "Network publishes disconnected state" '"offline"' net_state
expect_poll "Network's widget reads the shared state" '"Not connected"' ipc smoke readDescendant "$(bar_key)" vgs.network BarItem tooltip
expect_poll "Network's widget is placed" True net_placed
expect "System enables for the network pane" ok ipc shell setPluginEnabled vgs.system true
expect "the network pane opens in System" ok ipc shell summon window vgs.system '{"pane":"vgs.network","source":"smoke"}'
expect_poll "Network's pane is mounted" shown net_shown window
expect "the pane receives its payload" '{"source":"smoke"}' ipc smoke readInstance window vgs.network payload
expect_poll "the pane owns one scan lease" '{"leases":1,"device":"wlan0","scanning":true}' ipc smoke networkScan
net_join_result() {
  local reply
  reply="$(ipc smoke readDescendant window vgs.network NetworkJoin result)" || return
  if [[ $reply == absent ]]; then echo closed
  else py_reply 'import json,sys; r=json.load(sys.stdin); print("closed" if r=="absent" else r["kind"])' <<<"$reply"
  fi
}
net_other_reveal() { ipc smoke revealText window vgs.system Button 'Other Network…' | py_reply 'import json,sys; json.load(sys.stdin); print("scrolled")'; }
net_join_cancel_reveal() { ipc smoke revealText window vgs.system Button Cancel | py_reply 'import json,sys; json.load(sys.stdin); print("scrolled")'; }
net_join_record() { python3 - "$net_join_dir/calls" "$net_join_dir/world.json" "${1:-Hidden smoke Wi-Fi}" "${2:-yes}" "${3:-psk}" "${4:-}" "${5:-}" <<'PYJOINCALLS'
import json,pathlib,sys,uuid
p=pathlib.Path(sys.argv[1]); rows=[json.loads(line) for line in p.read_text().splitlines()] if p.exists() else []
up=next((r for r in rows if r["operation"]=="up"),None)
if up is None:
    print("pending")
else:
    add=rows[0]["argv"]; profile=add[add.index("connection.uuid")+1]
    valid=all(not r["argv_secret"] and not r["helper_argv_secret"] for r in rows)
    valid=valid and up["stdin_ok"] and up["argv"]==["--wait","120","connection","up","uuid",profile,"passwd-file","/dev/stdin"]
    valid=valid and str(uuid.UUID(profile))==profile
    valid=valid and up["helper_argv"][2:]==["wlan0"]+sys.argv[3:]
    valid=valid and add[add.index("ssid")+1]==sys.argv[3] and add[add.index("ifname")+1]=="wlan0"
    valid=valid and add[add.index("802-11-wireless.hidden")+1]==sys.argv[4]
    valid=valid and add[add.index("802-11-wireless-security.key-mgmt")+1]==("wpa-psk" if sys.argv[5]=="psk" else "wpa-eap")
    if sys.argv[5]!="psk":
        valid=valid and add[add.index("802-1x.eap")+1]==sys.argv[5]
        valid=valid and add[add.index("802-1x.phase2-auth")+1]==("mschapv2" if sys.argv[5]=="peap" else "pap")
        valid=valid and add[add.index("802-1x.identity")+1]==sys.argv[6] and add[add.index("802-1x.domain-suffix-match")+1]==sys.argv[7]
    valid=valid and rows[-1]["argv"]==["--wait","5","connection","delete","uuid",profile]
    valid=valid and profile not in json.loads(pathlib.Path(sys.argv[2]).read_text()).get("profiles", [])
    print("private-cleaned" if valid else "invalid")
PYJOINCALLS
}
expect "Other Network scrolls into view" scrolled net_other_reveal
click_in 'window:System Settings' window vgs.network Button 'Other Network…' || fail "Other Network could not be opened"
expect_poll "Other Network opens its hidden form" idle net_join_result
expect "the hidden password field is masked" true ipc smoke readMatchingDescendant window vgs.network TextField objectName network-join-password password
expect "the hidden form selects personal security" false ipc smoke readDescendant window vgs.network NetworkJoin enterprise
type_keys 'Hidden smoke Wi-Fi'
type_keys -k Tab
type_keys -k Tab
type_keys network-smoke-joined-secret
type_keys -k Return
expect_poll "a refused hidden connection reports its typed result" refused net_join_result
expect "the helper receives no secret argument and cleans its UUID" private-cleaned net_join_record
expect "the submitted hidden form needs a new password" false ipc smoke readDescendant window vgs.network NetworkJoin canSubmit
click_in 'window:System Settings' window vgs.network Button Cancel || fail "Other Network could not be canceled"
expect_poll "Cancel releases the hidden form" closed net_join_result
expect "the hidden operation releases its shared owner" idle net_action
net_join_child_stopped() { python3 - "$net_join_dir/ready" <<'PYJOINSTOP'
import os,pathlib,sys
p=pathlib.Path(sys.argv[1])
if not p.exists(): print("not-started")
else:
    try: os.kill(int(p.read_text()),0)
    except ProcessLookupError: print("stopped")
    else: print("running")
PYJOINSTOP
}
# The held command acknowledges activation before each real removal path.
net_join_close_test() { # RECORD OPERATION [form|device|disable|rebuild]
rm -f -- "${net_join_dir:?}/calls" "${net_join_dir:?}/ready"
net_join_world 802-11-wireless-security.psk hold
expect "Other Network is revealed for its close test" scrolled net_other_reveal
click_in 'window:System Settings' window vgs.network Button 'Other Network…' || fail "the close test form could not open"
expect_poll "the close test takes focus" true ipc smoke activeFocusWithin window vgs.network NetworkJoin
type_keys 'Hidden smoke Wi-Fi'
type_keys -k Tab
type_keys -k Tab
type_keys network-smoke-joined-secret
type_keys -k Return
net_join_held() { python3 - "$net_join_dir/ready" "$net_join_dir/world.json" "$net_join_dir/calls" <<'PYJOINHELD'
import json,pathlib,sys
ready,world,calls=map(pathlib.Path,sys.argv[1:])
rows=[json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
add=next((r for r in rows if r["operation"]=="add"),None)
profile=add["argv"][add["argv"].index("connection.uuid")+1] if add else None
print("held" if ready.exists() and profile in json.loads(world.read_text()).get("profiles", []) else "pending")
PYJOINHELD
}
expect_poll "the real helper reaches held activation" held net_join_held
expect "the pending helper holds the service operation" join net_action
expect "the pending form retains its original adapter" '"wlan0"' ipc smoke readDescendant window vgs.network NetworkJoin interfaceName
case ${3:-form} in
form)
expect "Cancel is visible during activation" scrolled net_join_cancel_reveal
click_in 'window:System Settings' window vgs.network Button Cancel || fail "the pending form could not close"
;;
device) net_expect_fixture "the join adapter is replaced" replace || return 1 ;;
disable)
expect "Network disables during held activation" ok ipc shell setPluginEnabled vgs.network false
expect_poll "disabling destroys the service" False record_exists vgs.network
;;
rebuild)
printf '\n' >>"$net_copy/Service.qml"
rescan "source replacement destroys the pending service"
;;
esac
expect_poll "closing during activation releases the form" closed net_join_result
expect_poll "closing during activation reads cleanup ownership" "$1" net_join_record
if [[ ${3:-form} != disable ]]; then expect_poll "closing during activation reads the shared operation" "$2" net_action; fi
if [[ $1 == private-cleaned ]]; then expect_poll "cancellation reaps the network command" stopped net_join_child_stopped; fi
case ${3:-form} in
device)
net_expect_fixture "the join adapter returns" restore || return 1
expect_poll "the restored adapter is selected" '{"leases":1,"device":"wlan0","scanning":true}' ipc smoke networkScan
;;
disable)
expect "Network enables after held activation cleanup" ok ipc shell setPluginEnabled vgs.network true
expect_poll "the service returns after cleanup" True record_exists vgs.network
expect "System remounts Network" ok ipc shell summon window vgs.system '{"pane":"vgs.network"}'
expect_poll "the pane returns after service removal" shown net_shown window
;;
esac
if [[ ${3:-form} != form ]]; then expect_poll "the replacement service is ready" '"offline"' net_state; fi
}
net_join_close_test private-cleaned idle || return 0
net_join_close_test private-cleaned idle device || return 0
net_join_close_test private-cleaned idle disable || return 0
net_expect_fixture "the mock adds a scanned enterprise network" enterprise || return 0
net_enterprise_seen() { net_snapshot | py_reply 'import json,sys; print(any(r["name"]=="VGS Enterprise Wi-Fi" and r["security"]=="Wpa2Eap" for r in json.load(sys.stdin)["network"]["wifi"]))'; }
net_enterprise_reveal() { ipc smoke revealText window vgs.system DeviceRow 'VGS Enterprise Wi-Fi' | py_reply 'import json,sys; json.load(sys.stdin); print("scrolled")'; }
expect_poll "the scanned enterprise row uses its security kind" True net_enterprise_seen
net_join_submitted() { python3 - "$net_join_dir/calls" <<'PYSUBMITTED'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);rows=[json.loads(line) for line in p.read_text().splitlines()] if p.exists() else []
print("submitted" if any(r["operation"]=="up" for r in rows) else "pending")
PYSUBMITTED
}
# net_join_choose TEXT FIELD [KEY...]: a click on the join form's Select
# reading TEXT, objectName network-join-FIELD, then KEY... and Return in
# its list once the list is open, so no key reaches the form before the
# list, and 0 once Return closed it, so the next key reaches the form, not
# the list. 1, with a failure and no key typed, when the list does not
# open.
net_join_choose() {
  local text=$1 field=$2 before=$failures
  shift 2
  click_in 'window:System Settings' window vgs.network Select "$text" || { fail "the enterprise $field choice could not open"; return 1; }
  expect_poll "the enterprise $field list opens" true ipc smoke readMatchingDescendant window vgs.network Select objectName "network-join-$field" listOpen
  (( failures == before )) || return 1
  type_keys "$@" -k Return
  expect_poll "Return closes the enterprise $field list" false ipc smoke readMatchingDescendant window vgs.network Select objectName "network-join-$field" listOpen
}
# A step that fails ends the case through net_enterprise_abandon: keys
# typed on would act on whatever holds them, the network list's Return
# connecting its selected network into the checks after this one. It
# closes an open list, whose catcher would take the press on Cancel
# (DismissScope), then the form.
net_enterprise_abandon() {
  local field
  [[ $(net_join_result) != closed ]] || return 0
  for field in security method; do
    [[ $(ipc smoke readMatchingDescendant window vgs.network Select objectName "network-join-$field" listOpen) != true ]] || type_keys -k Escape
  done
  expect "the abandoned enterprise form's Cancel scrolls into view" scrolled net_join_cancel_reveal
  click_in 'window:System Settings' window vgs.network Button Cancel || fail "the abandoned enterprise form could not be canceled"
  expect_poll "Cancel releases the abandoned enterprise form" closed net_join_result
}
net_enterprise_submit_test() { # HIDDEN METHOD RECORD
local net_enterprise_hidden=$1 net_enterprise_method=$2 net_enterprise_name net_enterprise_before=$failures
rm -f -- "${net_join_dir:?}/calls" "${net_join_dir:?}/ready"
net_join_world 802-1x.password failed
if [[ $net_enterprise_hidden == no ]]; then
net_enterprise_name='VGS Enterprise Wi-Fi'
expect "the enterprise row is revealed" scrolled net_enterprise_reveal
expect_poll "the scanned enterprise row is mounted and enabled" true ipc smoke readMatchingDescendant window vgs.network DeviceRow text "$net_enterprise_name" enabled
click_item 'window:System Settings' window vgs.network DeviceRow "$net_enterprise_name" || fail "the enterprise row could not be opened"
else
net_enterprise_name='Hidden enterprise Wi-Fi'
expect "Other Network is revealed for enterprise input" scrolled net_other_reveal
click_in 'window:System Settings' window vgs.network Button 'Other Network…' || fail "the hidden enterprise form could not open"
expect_poll "the hidden enterprise form takes focus" true ipc smoke activeFocusWithin window vgs.network NetworkJoin
type_keys "$net_enterprise_name"
net_join_choose 'WPA/WPA2 Personal' security -k Down || { net_enterprise_abandon; return 0; }
fi
expect_poll "enterprise input uses the shared form" idle net_join_result
expect "the form selects enterprise security" true ipc smoke readDescendant window vgs.network NetworkJoin enterprise
(( failures == net_enterprise_before )) || { net_enterprise_abandon; return 0; }
expect "the enterprise password field is masked" true ipc smoke readMatchingDescendant window vgs.network TextField objectName network-join-password password
local -a net_enterprise_step=()
[[ $net_enterprise_method != ttls ]] || net_enterprise_step=(-k Down)
net_join_choose 'PEAP / MSCHAPv2' method "${net_enterprise_step[@]}" || { net_enterprise_abandon; return 0; }
type_keys -k Tab
type_keys 'enterprise.user'
type_keys -k Tab
type_keys 'auth.example.test'
type_keys -k Tab
type_keys network-smoke-joined-secret
type_keys -k Return
expect_poll "enterprise submission reports its typed result" failed net_join_result
expect_poll "enterprise input reaches helper activation" submitted net_join_submitted
expect "enterprise submission maps public fields and privately cleans its UUID" "$3" net_join_record "$net_enterprise_name" "$net_enterprise_hidden" "$net_enterprise_method" enterprise.user auth.example.test
expect "the enterprise Cancel button scrolls into view" scrolled net_join_cancel_reveal
click_in 'window:System Settings' window vgs.network Button Cancel || fail "the enterprise form could not be canceled"
expect_poll "Cancel releases the enterprise form" closed net_join_result
}
for net_enterprise_hidden in no yes; do
for net_enterprise_method in peap ttls; do
net_enterprise_submit_test "$net_enterprise_hidden" "$net_enterprise_method" private-cleaned
done
done
net_expect_fixture "the mock removes its scanned enterprise network" unenterprise || return 0
expect "the flyout opens over the pane" ok ipc shell summon panel vgs.network '{"source":"smoke"}'
expect_poll "Network's flyout is shown" shown net_shown panel
expect "the flyout receives its payload" '{"source":"smoke"}' ipc smoke readInstance panel vgs.network payload
expect_poll "both open views hold the scanner" '{"leases":2,"device":"wlan0","scanning":true}' ipc smoke networkScan
expect_poll "the shared Wi-Fi header switch reads on and sits beside the gear" '{"checked": true, "enabled": true, "placed": true}' net_header
expect "the old Wi-Fi Field row is absent from the dropdown" absent net_wifi_field_absent
expect "the pane reads the network and strength" '[["VGS Smoke Wi-Fi", 82, true, false]]' net_rows window
expect "the flyout reads the same network and strength" '[["VGS Smoke Wi-Fi", 82, true, false]]' net_rows panel
expect "opening Network reads no saved secret" public net_qr_calls
type_keys -k Menu
expect_poll "the saved-network sharing menu opens" true ipc smoke readDescendant panel vgs.network Menu opened
expect_poll "the sharing menu selects Share QR code" '["Share QR code"]' net_menu_end
type_keys -k Return
expect_poll "Share draws whole QR modules for a saved disconnected network" ready net_qr_state panel
expect "Share reads only after the explicit menu action" private net_qr_calls
expect "the QR lifetime observer retains the view" ok ipc smoke networkRememberShare panel
type_keys -k Return
expect_poll "Close QR code removes the matrix owner" closed ipc smoke networkShare panel
expect_poll "closing Share destroys its collector and view" false ipc smoke networkRememberedShareAlive
net_qr_released finished
# Stop a real shipped helper while the private encoder holds its output.
net_qr_world hold
rm -f -- "$net_qr_dir/ready"
type_keys -k Menu
expect_poll "the pending sharing menu opens" true ipc smoke readDescendant panel vgs.network Menu opened
expect_poll "the pending sharing menu selects Share QR code" '["Share QR code"]' net_menu_end
type_keys -k Return
expect_poll "the encoder reaches its private pipe" yes net_qr_encoder_ready
expect "the pending QR lifetime observer retains the view" ok ipc smoke networkRememberShare panel
type_keys -k Return
expect_poll "closing during encoding destroys the pending owner" false ipc smoke networkRememberedShareAlive
expect_poll "closing Share stops its owned encoder" stopped net_qr_child_stopped
net_qr_released cancelled
expect "buffered output cannot reopen Share" closed ipc smoke networkShare panel
net_qr_world ready
device_reply nmcli 0 $'GENERAL.DEVICE:wlan0\nIP4.ADDRESS[1]:192.0.2.2/24' -t device show wlan0
type_keys -k Menu
expect_poll "the flyout's Wi-Fi menu opens" true ipc smoke readDescendant panel vgs.network Menu opened
expect_poll "the Details menu starts at Share QR code" '["Share QR code"]' net_menu_end
type_keys -k Up
expect_poll "the Wi-Fi menu selects Details" '["Details"]' net_menu_selection
type_keys -k Return
expect_poll "the flyout Details menu action draws its result" '{"visible":true,"rows":[["GENERAL.DEVICE","wlan0"],["IP4.ADDRESS[1]","192.0.2.2/24"]]}' ipc smoke networkDetails panel
expect "the flyout closes" ok ipc shell hide panel vgs.network
expect_poll "closing the flyout keeps the pane's scan" '{"leases":1,"device":"wlan0","scanning":true}' ipc smoke networkScan
expect "the scanner observer retains the first fake device" ok ipc smoke networkRememberDevice
net_expect_fixture "the mock replaces the Wi-Fi device" replace || return 0
expect_poll "the lease moves to the replacement" '{"leases":1,"device":"wlan1","scanning":true}' ipc smoke networkScan
expect "the replaced device stops scanning" false ipc smoke networkRememberedScanning
net_expect_fixture "the mock restores the first device" restore || return 0
expect_poll "the lease returns to the restored device" '{"leases":1,"device":"wlan0","scanning":true}' ipc smoke networkScan
expect "System closes the pane" ok ipc shell hide window vgs.system
expect_poll "both closed views release the scanner" '{"leases":0,"device":null,"scanning":false}' ipc smoke networkScan

# Native methods can refuse with no frontend failure signal. The sandbox
# probe only shortens the real service watchdog; its triggered handler runs.
net_expect_fixture "the connect refusal is installed" refuse-connect || return 0
expect "a refused connect starts one operation" ok net_do connect
expect "the operation has a bounded running watchdog" '{"running":true,"bounded":true}' ipc smoke networkWatchdog false
expect "the sandbox advances the connect watchdog" ok ipc smoke networkWatchdog true
expect_poll "a silent connect refusal releases the operation" idle net_action
expect "a silent refusal has a retry message" '"The network change did not complete. Try again."' net_problem
net_expect_fixture "normal network requests are restored" normal || return 0
expect "connect can retry after refusal" ok net_do connect
expect_poll "the retry reaches a native transition" True net_changing
net_expect_fixture "a noncredentials terminal failure removes activation" drop-active || return 0
expect_poll "terminal connect failure releases the operation" idle net_action
expect "terminal failure can retry" ok net_do connect
expect_poll "the retry is connecting before radio cancellation" True net_changing
expect "radio off cancels the pending operation" ok ipc vgs.network invoke action '{"kind":"radio"}'
expect_poll "radio cancellation releases the operation" idle net_action
net_expect_fixture "the canceled mock activation is removed" drop-active || return 0
expect "radio on restores the connection path" ok ipc vgs.network invoke action '{"kind":"radio"}'
expect "connect retries after radio cancellation" ok net_do connect
expect_poll "the source-loss request is connecting" True net_changing
net_expect_fixture "the pending source is replaced" replace || return 0
expect_poll "device loss releases the operation" idle net_action
net_expect_fixture "the pending source is restored" restore || return 0
net_expect_fixture "the source-loss activation is removed" drop-active || return 0

# The password prompt in the real dropdown, a popup that holds the seat
# grab: the dropdown stays open under its prompt, the prompt keeps the keys
# and the presses, and each way out clears the typed text.
net_widget_click || fail "the click on the Network widget for the prompt failed"
expect_poll "the prompt's dropdown opens" shown net_shown panel
summon_drawn panel vgs.network || fail "the prompt's dropdown never drew a frame"
net_reprompt "Prompt" || return 0
expect_poll "a network that needs a password opens the dialog" true net_dialog panel
expect "the dropdown stays open under its dialog" shown net_shown panel
expect "the dialog is drawn in the dropdown, on no layer of its own" 0 layer_count vgs:dialog
expect "the dialog names the network" True net_dialog_names panel
net_saved_reason "Saved password"
net_hint_suppressed "Saved password"
expect_poll "the dialog focuses its masked field" '{"masked":true,"length":0,"focused":true}' ipc smoke networkField panel
expect "the focused field is the dialog's own" true ipc smoke activeFocusWithin panel vgs.network Dialog
type_keys partial
expect_poll "the dialog's field takes the typed text" '{"masked":true,"length":7,"focused":true}' ipc smoke networkField panel
expect "the dim layer covers the whole dropdown, header and footer included" covers net_scrim_covers
net_scrim_click "Wi-Fi switch" itemGeometry Switch ""
net_scrim_click "Settings gear" labelledGeometry IconButton Settings
net_scrim_click "Network settings" itemGeometry Button "Network settings"
expect "the header switch stays checked under the dialog" '{"checked": true, "enabled": true, "placed": true}' net_header
expect "no click under the dialog opens System" hidden net_shown window
net_expect_fixture "the list gains a network under the dialog" enterprise || return 0
expect_poll "the list refreshes under the dialog" True net_enterprise_seen
expect "a list refresh keeps the dialog" true net_dialog panel
expect "a list refresh keeps the typed text and the focus" '{"masked":true,"length":7,"focused":true}' ipc smoke networkField panel
net_expect_fixture "the added network leaves the list" unenterprise || return 0
# One Tab leaves the field for Cancel, and two more pass Join and come back
# to the field. With the field empty Join is disabled, so one Tab rests on
# Cancel, where Delete would forget the profile if the list behind took the
# key. The text typed after Delete shows the shell has handled Delete.
type_keys -k Tab
expect_poll "Tab moves the focus off the field" '{"masked":true,"length":7,"focused":false}' ipc smoke networkField panel
type_keys -k Tab -k Tab
expect_poll "Tab wraps inside the dialog, back to its field" '{"masked":true,"length":7,"focused":true}' ipc smoke networkField panel
type_keys -M ctrl -k a -m ctrl -k BackSpace
expect_poll "the field empties before the list check" '{"masked":true,"length":0,"focused":true}' ipc smoke networkField panel
type_keys -k Tab
expect_poll "Tab rests on the dialog's Cancel" '{"masked":true,"length":0,"focused":false}' ipc smoke networkField panel
expect "the focus on Cancel is inside the dialog" '[true, true]' net_dialog_focus panel
type_keys -k Delete -M shift -k Tab -m shift
type_keys partial
expect_poll "Shift+Tab returns to the field" '{"masked":true,"length":7,"focused":true}' ipc smoke networkField panel
expect "the list behind the dialog takes no key" idle net_action
expect "the profile stays saved under the dialog" True net_known
type_keys -k Escape
expect_poll "Escape cancels the prompt" none net_prompt
expect_poll "Escape closes the dialog" false net_dialog panel
expect "Escape clears the typed text" '{"masked":true,"length":0,"focused":false}' ipc smoke networkField panel
expect "Escape keeps the dropdown open" shown net_shown panel
expect_poll "the focus returns to the dropdown, outside the dialog" '[false, true]' net_dialog_focus panel
net_reprompt "Cancel" || return 0
expect_poll "the prompt opens the dialog again" true net_dialog panel
expect_poll "the reopened dialog focuses its field" '{"masked":true,"length":0,"focused":true}' ipc smoke networkField panel
type_keys partial
expect_poll "the reopened field takes the typed text" '{"masked":true,"length":7,"focused":true}' ipc smoke networkField panel
net_dropdown_button Cancel || fail "the click on the dialog's Cancel failed"
expect_poll "Cancel cancels the prompt" none net_prompt
expect_poll "Cancel closes the dialog" false net_dialog panel
expect "Cancel clears the typed text" '{"masked":true,"length":0,"focused":false}' ipc smoke networkField panel
net_reprompt "Vanish" || return 0
expect_poll "the dialog opens before its network vanishes" '{"masked":true,"length":0,"focused":true}' ipc smoke networkField panel
type_keys partial
expect_poll "the field holds text before its network vanishes" '{"masked":true,"length":7,"focused":true}' ipc smoke networkField panel
net_expect_fixture "the prompted network's device is replaced" replace || return 0
expect_poll "a vanished network ends the prompt" none net_prompt
expect_poll "a vanished network closes the dialog" false net_dialog panel
expect "a vanished network clears the typed text" '{"masked":true,"length":0,"focused":false}' ipc smoke networkField panel
net_expect_fixture "the prompted network's device returns" restore || return 0
expect_poll "the returned device is scanned for the dropdown" '{"leases":1,"device":"wlan0","scanning":true}' ipc smoke networkScan
expect_poll "the returned network is listed" '[["VGS Smoke Wi-Fi", 82, true, false]]' net_rows panel
# A prompt that arrives while Share shows opens once Share closes, and
# takes the keys there.
net_share_prompt "Share" || return 0
expect_poll "the dialog that waited behind Share holds the keyboard" '[true, true]' net_dialog_focus panel
expect_poll "the dialog that waited behind Share focuses its field" '{"masked":true,"length":0,"focused":true}' ipc smoke networkField panel
type_keys partial
expect_poll "the field takes the text typed after Share" '{"masked":true,"length":7,"focused":true}' ipc smoke networkField panel
expect "the profile stays saved under the dialog after Share" True net_known
type_keys -k Escape
expect_poll "Escape cancels the prompt that waited behind Share" none net_prompt
expect_poll "Escape closes the dialog that waited behind Share" false net_dialog panel
expect "Escape clears the text typed after Share" '{"masked":true,"length":0,"focused":false}' ipc smoke networkField panel
net_reprompt "Close" || return 0
expect_poll "the dialog opens before the dropdown closes" '{"masked":true,"length":0,"focused":true}' ipc smoke networkField panel
type_keys partial
expect_poll "the field holds text before the dropdown closes" '{"masked":true,"length":7,"focused":true}' ipc smoke networkField panel
expect "the dropdown closes over its prompt" ok ipc shell hide panel vgs.network
expect_poll "closing the dropdown leaves no password field" absent ipc smoke networkField panel
net_closed_prompt() { expect "$1: the service holds no prompt after close" none net_prompt; }
net_closed_prompt "Dropdown"
expect "the dropdown reopens after canceling its prompt" ok ipc shell summon panel vgs.network '{}'
expect_poll "the reopened dropdown is mounted" shown net_shown panel
expect_poll "the prompt does not return on reopen" false net_dialog panel
expect "the dropdown closes after its reopen check" ok ipc shell hide panel vgs.network

# First-time NoSecrets uses the mock's existing new-profile verb, held in
# Connecting like its saved-profile verb, then the same native failure signal.
net_new_profile_mode() { python3 - "unix:path=$rt_dir/system-bus" "$1" <<'PYNEWPROFILE'
import dbus,sys
bus=dbus.bus.BusConnection(sys.argv[1]);nm="org.freedesktop.NetworkManager"
manager=dbus.Interface(bus.get_object(nm,"/org/freedesktop/NetworkManager"),"org.freedesktop.DBus.Mock")
code='ret = self.add_and_activate_connection(self, args[0], args[1], args[2])'
if sys.argv[2]=="hold":
    code='''
root=objects["/org/freedesktop"]
profile=dbus.ObjectPath(root.AddWiFiConnection(args[1], "network_saved", "VGS Smoke Wi-Fi", "wpa-psk"))
objects[profile].log=lambda msg: None
active=dbus.ObjectPath(root.AddActiveConnection([args[1]], profile, args[2], "network_active", 1))
objects[active].log=lambda msg: None
ret=(profile, active)
'''
manager.AddMethod(nm,"AddAndActivateConnection","a{sa{sv}}oo","oo",code)
print("ok")
PYNEWPROFILE
}
expect "the first-time case forgets its saved profile" ok net_do forget
expect_poll "the first-time network has no saved profile" False net_known
expect "the new-profile mock holds activation" ok net_new_profile_mode hold
expect "the first-time password case opens" ok ipc shell summon panel vgs.network '{}'
expect_poll "the first-time password case is mounted" shown net_shown panel
expect_poll "the first-time network is listed without a saved profile" '[["VGS Smoke Wi-Fi", 82, false, false]]' net_rows panel
net_reprompt "First-time password" || return 0
expect_poll "the first-time password dialog shows" true net_dialog panel
expect "the first-time dialog has no failure reason line" false ipc smoke readMatchingDescendant panel vgs.network Label objectName network-prompt-reason visible
expect "the first-time dialog still names its network" True net_dialog_names panel
expect "the first-time password view closes" ok ipc shell hide panel vgs.network
expect_poll "closing the first-time view cancels its prompt" none net_prompt
expect "the first-time case removes its new profile" ok net_do forget
expect_poll "the first-time profile is removed" False net_known
expect "the new-profile mock restores its normal activation" ok net_new_profile_mode normal
net_expect_fixture "the saved profile returns for the keyboard case" prepare || return 0

# Keyboard-only join and forget, through the actual NM failure signal.
hypr_lua_save network
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$home/.config/hypr/hyprland.lua"
expect "the nested keyboard uses symbol bindings" ok hypr reload config-only
rest_pointer || fail "moving the pointer off System failed"
type_keys -M logo -k period -m logo
expect_poll "the System shortcut opens the keyboard path" shown net_shown window
expect_poll "System starts the keyboard path in search" '["TextField",""]' ipc smoke activeFocusItem window vgs.system
type_keys Network
expect_poll "the keyboard search names Network" '"Network"' ipc smoke readDescendant window vgs.system Sidebar query
type_keys -k Return
expect_poll "Enter focuses Network in System" true ipc smoke activeFocusWithin window vgs.network NetworkBody
type_keys -k Return
expect_poll "Enter starts the saved profile" connect net_action
expect "an unrelated network failure is ignored" ok ipc smoke networkBackgroundFailure true
expect "the unrelated failure keeps the matching operation" connect net_action
net_expect_fixture "the mock emits a wrong saved password failure" fail || return 0
expect_poll "a wrong saved password reprompts" prompt net_prompt
expect_poll "the reprompt is a masked focused field" '{"masked":true,"length":0,"focused":true}' ipc smoke networkField window
expect "a failed saved password uses the same dialog" true net_dialog window
expect "the System dialog names the network" True net_dialog_names window
expect "the System dialog holds the focused field" true ipc smoke activeFocusWithin window vgs.network Dialog
net_follow_shorten || return 0
expect "the dialog follows the scrolled System page" follows net_dialog_follows window
net_follow_restore
net_expect_fixture "the failed activation is removed before retry" drop-active || return 0
type_keys partial
expect "an idle background failure is ignored" ok ipc smoke networkBackgroundFailure false
expect "the password prompt keeps its typed value" '{"masked":true,"length":7,"focused":true}' ipc smoke networkField window
# A click on the System search takes the keyboard off the dialog, and Tab
# from there enters the dialog, never the page behind its scrim.
net_search_click || fail "the click on the System search failed"
expect_poll "a click takes the keyboard to the System search" '[false, false]' net_dialog_focus window
net_tab_to_body || fail "Tab from the System search never reached the network body"
expect_poll "Tab from the search enters the dialog, not the page behind it" '[true, true]' net_dialog_focus window
type_keys -k Delete
expect "the page behind the dialog takes no Delete" True net_known
type_keys -M shift -k Tab -m shift
expect_poll "Shift+Tab returns to the dialog's field" '{"masked":true,"length":7,"focused":true}' ipc smoke networkField window
type_keys -M ctrl -k a -m ctrl -k BackSpace
net_expect_fixture "the PSK update refusal is installed" refuse-psk || return 0
type_keys network-smoke-joined-secret
click_in 'window:System Settings' window vgs.network Button Join || fail "the click on the dialog's Join failed"
expect_poll "Join closes the dialog" false net_dialog window
expect "the sandbox advances the PSK watchdog" ok ipc smoke networkWatchdog true
expect_poll "a refused PSK update releases the operation" idle net_action
expect "the field clears after the refused PSK update" '{"masked":true,"length":0,"focused":false}' ipc smoke networkField window
net_expect_fixture "normal PSK requests are restored" normal || return 0
type_keys -k Return
expect_poll "connect retries after a refused PSK" connect net_action
net_expect_fixture "the retry requests a password again" fail || return 0
expect_poll "the retry reprompts for the password" prompt net_prompt
net_expect_fixture "the retry activation is removed" drop-active || return 0
expect_poll "the retry's dialog focuses its field" '{"masked":true,"length":0,"focused":true}' ipc smoke networkField window
type_keys network-smoke-joined-secret
type_keys -k Return
expect_poll "Enter in the dialog joins the network" True net_joined
expect "Enter closes the dialog" false net_dialog window
expect "the field clears its PSK" '{"masked":true,"length":0,"focused":false}' ipc smoke networkField window
net_no_secret() {
  local status
  status="$(net_snapshot)" || return 1
  python3 - "$status" "$home/.config/vgshell/shell.json" "$instance_log" "$devices_dir/network.log" <<'PY'
import pathlib,sys
texts=[sys.argv[1]]+[pathlib.Path(p).read_text(errors="replace") for p in sys.argv[2:]]
print("clean" if all("network-smoke-joined-secret" not in t for t in texts) else "leaked")
PY
}
net_qr_no_secret() {
  local status
  status="$(net_snapshot)" || return 1
  python3 - "$status" "$home" "$instance_log" "$devices_dir/network.log" "$net_qr_dir" <<'PYPRIVATE'
import pathlib,sys
texts=[sys.argv[1]]+[pathlib.Path(p).read_text(errors="replace") for p in sys.argv[3:5]]
for directory in (sys.argv[2],sys.argv[5]):
    texts.extend(p.read_text(errors="replace") for p in pathlib.Path(directory).rglob("*") if p.is_file())
print("clean" if all("network-share-fixture-secret" not in t for t in texts) else "leaked")
PYPRIVATE
}
expect "the PSK is absent from status, configuration and logs" clean net_no_secret
expect "the shared password is absent from status, configuration, logs and scratch files" clean net_qr_no_secret
net_secret_control="$sandbox/network-secret-control.log"
printf '%s\n' network-smoke-joined-secret >"$net_secret_control"
net_real_log="$instance_log"
instance_log="$net_secret_control"
expect "control: the leak reader catches a PSK in a log" leaked net_no_secret
instance_log="$net_real_log"
rm -f -- "${net_secret_control:?}"
net_expect_fixture "the disconnect refusal is installed" refuse-disconnect || return 0
expect "a refused disconnect starts one operation" ok net_do disconnect
expect "the sandbox advances the disconnect watchdog" ok ipc smoke networkWatchdog true
expect_poll "a refused disconnect releases the operation" idle net_action
expect "the joined network remains after refused disconnect" True net_joined
net_expect_fixture "normal disconnect requests are restored" normal || return 0
expect "disconnect retries after refusal" ok net_do disconnect
expect_poll "the disconnect retry completes" False net_joined
expect_poll "the successful disconnect releases the operation" idle net_action
expect "the saved exact PSK can reconnect" ok net_do connect
expect_poll "the exact saved PSK reconnects" True net_joined
net_expect_fixture "the forget refusal is installed" refuse-forget || return 0
expect "a refused forget starts one operation" ok net_do forget
expect "the sandbox advances the forget watchdog" ok ipc smoke networkWatchdog true
expect_poll "a refused forget releases the operation" idle net_action
expect "the saved profile remains after refused forget" True net_known
net_expect_fixture "normal forgetting is restored" normal || return 0
type_keys -k Delete
expect_poll "Delete forgets the Wi-Fi profile" False net_known
net_expect_fixture "the joined activation disconnects after forget" drop-active || return 0
expect "radio off uses the in-process control" ok ipc vgs.network invoke action '{"kind":"radio"}'
expect_poll "the radio is off" False net_radio
expect_poll "radio-off has its own state" '"radio-off"' net_state
expect "radio on restores the fake radio" ok ipc vgs.network invoke action '{"kind":"radio"}'
expect_poll "the radio is on" True net_radio
type_keys -k Escape
type_keys -k Escape
type_keys -k Escape
expect_poll "Escape closes System after the keyboard path" hidden net_shown window
hypr_lua_restore network || fail "hyprland.lua is put back after the Network keyboard path"
expect "the nested instance reloads hyprland.lua as the row found it" ok hypr reload config-only

net_unit $'LoadState=not-found\nActiveState=inactive'
expect "the absence probe refreshes" ok net_refresh
expect_poll "absent is distinct from stopped" '"absent"' net_state
net_unit $'LoadState=loaded\nActiveState=inactive'
expect "the stopped probe refreshes" ok net_refresh
expect_poll "stopped does not claim another manager" '"stopped"' net_state
net_unit $'LoadState=loaded\nActiveState=active'
net_permission no
expect "permission refusal refreshes" ok net_refresh
expect_poll "access denied has its own state" '"denied"' net_state
net_permission yes
expect "permissions recover" ok net_refresh
expect_poll "permissions allow changes again" '"offline"' net_state

device_reply nmcli 1 '' -t -f PERMISSION,VALUE general permissions
expect "the failed optional permissions probe refreshes" ok net_refresh
expect "Network opens to show the failed probe" ok ipc shell summon panel vgs.network '{}'
expect_poll "a failed permission check draws an explicit notice" '{"visible":true,"text":"Network permissions could not be checked. NetworkManager still handles each change."}' ipc smoke networkPermissionNotice panel
expect "the failed optional probe keeps native controls available" '"offline"' net_state
expect "the sandbox supplies the missing optional tool capability" ok ipc smoke networkPermissionsTool false
expect_poll "the missing optional tool is recorded" false ipc smoke readInstance service vgs.network nmcliPresent
expect "the missing optional tool draws its explicit notice" '{"visible":true,"text":"Network permissions could not be checked. NetworkManager still handles each change."}' ipc smoke networkPermissionNotice panel
expect "the missing optional tool keeps native controls available" '"offline"' net_state
expect "the missing optional tool permits a native radio change" ok ipc vgs.network invoke action '{"kind":"radio"}'
expect_poll "the radio changes without the optional tool" False net_radio
expect_poll "the shared Wi-Fi header switch follows radio off" '{"checked": false, "enabled": true, "placed": true}' net_header
expect "the old Wi-Fi Field row remains absent from the dropdown" absent net_wifi_field_absent
expect "the native radio restores without the optional tool" ok ipc vgs.network invoke action '{"kind":"radio"}'
expect_poll "the radio is restored without the optional tool" True net_radio
expect_poll "the shared Wi-Fi header switch follows radio on" '{"checked": true, "enabled": true, "placed": true}' net_header
expect "the original optional tool capability is restored" ok ipc smoke networkPermissionsTool true
net_permission yes
expect "the working optional permissions probe refreshes" ok net_refresh
expect_poll "the successful permission probe clears the notice" '""' ipc smoke readDescendant panel vgs.network NetworkBody permissionNotice
expect "the permission-notice flyout closes" ok ipc shell hide panel vgs.network

# The dropdown and Details over two wired fakes on the sandbox bus:
# enp10s0 connected with its cable in, enp11s0 with no cable.
net_wired() { net_snapshot | py_reply 'import json,sys; print(json.dumps([[r["name"],r["state"]] for r in json.load(sys.stdin)["network"]["ethernet"]]))'; }
net_wired_text() { node -e 'const { load } = require(process.argv[1] + "/bin/lib/qml-library.js"); console.log(load(process.argv[1] + "/shell/plugins/vgs.network/NetworkLogic.js", { "qs.Commons 1.0": { Nmcli: load(process.argv[1] + "/shell/Commons/Nmcli.js") } }).ethernetText(process.argv[2]));' "$repo" "$1"; }
net_wired_rows() { ipc smoke itemValues "$1" vgs.network ListItem text,secondary | py_reply 'import json,sys; print(json.dumps([[r["text"],r["secondary"]] for r in json.load(sys.stdin) if r["text"].startswith("enp")]))'; }
net_wired_listed() { net_wired_rows "$1" | py_reply 'import json,sys; print(json.dumps([[t, s != ""] for t,s in json.load(sys.stdin)]))'; }
# The System window's ScrollArea holds the pane, so its instance reveals.
net_reveal() { ipc smoke revealText window vgs.system ListItem enp10s0 | py_reply 'import json,sys; json.load(sys.stdin); print("scrolled")'; }
# To a tenth of a pixel: a row still ending its entrance (ListEntrance)
# reads a fraction of a pixel off its place.
net_below() { ipc smoke itemGeometry window vgs.network ListItem enp11s0 | py_reply 'import json,sys; print(round(json.load(sys.stdin)[1], 1))'; }
# net_settled_below: net_below once two reads 0.2 s apart agree, so the
# row has ended its entrance and the reveal's scroll. A failed read is
# retried as expect_poll retries; with no two agreeing reads within
# smoke_poll_bound_ms it prints `unsettled:` and the last read and fails.
net_settled_below() {
  local last=unread now
  smoke_poll_tries 200 1
  for _ in $(seq 1 "$smoke_poll_n"); do
    now="$(net_below)" || now=unread
    [[ ! -s $ipc_timeout_log ]] || break
    if [[ $now != unread && $now == "$last" ]]; then printf '%s\n' "$now"; return 0; fi
    last="$now"
    sleep 0.2
  done
  printf 'unsettled:%s\n' "$last"
  return 1
}
net_spinners() { ipc smoke itemValues window vgs.network Spinner visible | py_reply 'import json,sys; print(sum(1 for r in json.load(sys.stdin) if r["visible"]))'; }
net_detail_state() { net_snapshot | py_reply 'import json,sys; d=json.load(sys.stdin)["network"]["detail"]; print(d["interface"] + " " + d["state"])'; }
# net_details_layout LABEL: opens enp10s0's Details in System while its
# read is held and sets net_layout to `steady` when the enp11s0 row stays
# put during the read and moves once the rows draw, else to
# `moved-while-loading`, `never-moved` or `unread` with the readings.
net_details_layout() {
  local before during after
  net_layout=unread
  expect "$1: System opens the Network pane" ok ipc shell summon window vgs.system '{"pane":"vgs.network"}'
  expect_poll "$1: the pane is mounted" shown net_shown window
  expect_poll "$1: the pane lists the wired devices" '[["enp10s0", true], ["enp11s0", true]]' net_wired_listed window
  expect "$1: enp10s0 scrolls into view" scrolled net_reveal
  before="$(net_settled_below)" || true
  touch -- "$net_hold"
  click_in "window:System Settings" window vgs.network ListItem enp10s0 || fail "$1: the click on enp10s0 failed"
  expect_poll "$1: the held read is loading" "enp10s0 loading" net_detail_state
  expect_poll "$1: the expanded row shows one spinner" 1 net_spinners
  during="$(net_below)" || during=unread
  rm -f -- "$net_hold"
  expect_poll "$1: Details draws the device's rows" '{"visible":true,"rows":[["GENERAL.DEVICE","enp10s0"],["IP4.ADDRESS[1]","192.0.2.10/24"]]}' ipc smoke networkDetails window
  expect "$1: the spinner stops once the rows draw" 0 net_spinners
  after="$(net_below)" || after=unread
  expect "$1: System closes the pane" ok ipc shell hide window vgs.system
  expect_poll "$1: the pane is gone" hidden net_shown window
  if [[ $before == unread || $before == unsettled:* || $during == unread || $after == unread ]]; then net_layout="unread before=$before during=$during after=$after"
  elif [[ $during != "$before" ]]; then net_layout="moved-while-loading before=$before during=$during after=$after"
  elif [[ $after == "$before" ]]; then net_layout="never-moved before=$before after=$after"
  else net_layout=steady; fi
}
net_expect_fixture "the mock adds two Ethernet devices" wired || return 0
expect_poll "Network publishes each wired device's state" '[["enp10s0", "connected"], ["enp11s0", "no-cable"]]' net_wired
expect_poll "the connected wired device connects the computer" '"connected"' net_state
net_portal_url='http://captive.apple.com/hotspot-detect.html'
device_reply xdg-open 0 ""
net_portal_calls_before="$(device_calls xdg-open | py_reply 'import json,sys; print(len(json.load(sys.stdin)))')"
net_portal_calls() { device_calls xdg-open | py_reply 'import json,sys; calls=json.load(sys.stdin)[int(sys.argv[1]):]; print(json.dumps([[arg.split("?",1)[0] for arg in call] for call in calls]))' "$net_portal_calls_before"; }
net_portal_available() { net_snapshot | py_reply 'import json,sys; print(json.load(sys.stdin)["network"]["portalAvailable"])'; }
net_native_checks() { python3 - "unix:path=$rt_dir/system-bus" <<'PYNMCOUNT'
import sys,dbus
manager=dbus.Interface(dbus.bus.BusConnection(sys.argv[1]).get_object("org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager"), "org.freedesktop.DBus.Mock")
print(len(manager.GetMethodCalls("CheckConnectivity")))
PYNMCOUNT
}
net_probe_held() { [[ -f $net_connectivity_dir/ready ]] && echo held || echo waiting; }
net_probe_running() { ipc smoke readInstance service vgs.network connectivityRequest | py_reply 'import json,sys; print(str(json.load(sys.stdin) is not None).lower())'; }
net_poll() {
  local reading
  ipc smoke popupLoad network-poll-observer "$net_connectivity_dir/PollObserver.qml" service vgs.network '{"service":"@instance"}' >/dev/null || return 1
  reading="$(ipc smoke popupRead network-poll-observer reading)" || return 1
  ipc smoke popupDrop network-poll-observer >/dev/null || return 1
  printf '%s\n' "$reading"
}
net_slow_poll() { expect "$1: a closed limited network backs off" '{"interval":300000,"running":true}' net_poll; }
net_known_portal() { expect "$1: the native known portal offers Sign in before the check returns" True net_portal_available; }
net_check_progress() { local after; after="$(net_native_checks)" || return 1; [[ $after -gt $net_checks_before ]] && echo yes || echo no; }
net_check_called() { expect "$1: CheckConnectivity reaches the private NetworkManager" yes net_check_progress; }
touch "$net_connectivity_dir/hold" "$net_connectivity_dir/active"
net_checks_before="$(net_native_checks)"
net_expect_fixture "the network already requires browser sign-in" portal || return 0
expect_poll "the fresh CLI probe reaches its fixture barrier" held net_probe_held
expect_poll "Network follows the native portal before the held check completes" '"portal"' net_state
net_known_portal "Native follow"
# Rebuild while NM reports Portal and the CLI result remains held.
net_connectivity_copy="$home/.config/vgshell/plugins/vgs.network"
mkdir -p -- "$net_connectivity_copy"
cp -R -- "$repo/shell/plugins/vgs.network/." "$net_connectivity_copy/"
rescan "the known-portal seed check rebuilds Network"
expect_poll "the rebuilt Network seeds the known portal" '"portal"' net_state
net_known_portal "Native seed"
expect "portal detection waits for the user to open the browser" '[]' net_portal_calls
expect "the sign-in dropdown opens" ok ipc shell summon panel vgs.network '{}'
expect_poll "the sign-in dropdown is mounted" shown net_shown panel
click_in vgs:panel panel vgs.network RowAction 'Sign in' || fail "network: sign-in action was not clickable"
expect_poll "Sign in opens the fixed HTTP page through the browser stand-in" "[[\"$net_portal_url\"]]" net_portal_calls
rm -f -- "${net_connectivity_dir:?}/hold"
expect_poll "the fresh check returns from the private mock" false net_probe_running
net_check_called "Fresh check"
net_expect_fixture "the portal grants internet access" full || return 0
expect_poll "successful sign-in clears the portal result" '"connected"' net_state
expect_poll "successful sign-in removes the sign-in actions" False net_portal_available
net_expect_fixture "an inconclusive check reports limited access" limited || return 0
expect_poll "Network follows limited access" '"limited"' net_state
expect "an open Network view keeps its fast check" '{"interval":10000,"running":true}' net_poll
expect "limited access does not claim browser sign-in is needed" False net_portal_available
expect "limited access refuses an unrelated sign-in request" 'refused: portal=unavailable' ipc vgs.network invoke action '{"kind":"sign-in"}'
expect "limited access opens no browser" "[[\"$net_portal_url\"]]" net_portal_calls
expect "the portal test closes the dropdown" ok ipc shell hide panel vgs.network
expect_poll "the closed limited view releases its scan lease" '{"leases":0,"device":null,"scanning":false}' ipc smoke networkScan
net_slow_poll "Limited state"
# Control: preserve limited state but replace its backoff with fast polling.
python3 - "$net_connectivity_copy/Service.qml" <<'PYPOLLCONTROL'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();old='? 10000 : 300000'
assert s.count(old)==1
p.write_text(s.replace(old,'? 10000 : 10000'))
PYPOLLCONTROL
rescan "the limited fast-poll control is discovered"
expect_poll "the poll control reports the same limited state" '"limited"' net_state
net_poll_control() { (failures=0 behaviour_failures=0; net_slow_poll control >"$net_connectivity_dir/poll-control.log"; echo "$failures"); }
expect "control: fast polling fails the same closed-limited assertion" 1 net_poll_control
control_output "$net_connectivity_dir/poll-control.log"
cp -- "$repo/shell/plugins/vgs.network/Service.qml" "$net_connectivity_copy/Service.qml"
# Control: discard native seed and follow while the CLI reply stays held.
touch "$net_connectivity_dir/hold"
rm -f -- "${net_connectivity_dir:?}/ready"
net_expect_fixture "the native-off control starts with a known portal" portal || return 0
python3 - "$net_connectivity_copy/Service.qml" <<'PYSEEDCONTROL'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text()
old='property string checkedConnectivity: nativeConnectivity'
assert s.count(old)==1
s=s.replace(old,'property string checkedConnectivity: "Unknown"')
old='checkedConnectivity = nativeConnectivity;'
assert s.count(old)==2
p.write_text(s.replace(old,'checkedConnectivity = "Unknown";'))
PYSEEDCONTROL
rescan "the native seed and follow control is discovered"
expect_poll "the native-off control reaches its held fresh check" held net_probe_held
expect_poll "without native seed the held check leaves Connected" '"connected"' net_state
net_seed_control() { (failures=0 behaviour_failures=0; net_known_portal control >"$net_connectivity_dir/seed-control.log"; echo "$failures"); }
expect "control: discarded native connectivity fails the same immediate Sign in assertion" 1 net_seed_control
control_output "$net_connectivity_dir/seed-control.log"
# Control: a CLI-looking result without CheckConnectivity fails the call check.
touch "$net_connectivity_dir/skip-call"
net_checks_before="$(net_native_checks)"
rm -f -- "${net_connectivity_dir:?}/hold"
expect_poll "the no-call CLI control returns" false net_probe_running
net_call_control() { (failures=0 behaviour_failures=0; net_check_called control >"$net_connectivity_dir/call-control.log"; echo "$failures"); }
expect "control: a CLI result without the mock method fails the same CheckConnectivity assertion" 1 net_call_control
control_output "$net_connectivity_dir/call-control.log"
rm -f -- "${net_connectivity_dir:?}/skip-call"
rm -rf -- "${net_connectivity_copy:?}"
rescan "the shipped connectivity service is restored"
expect_poll "the restored service reports its known portal" '"portal"' net_state
expect_poll "the restored probe finishes before the manual check" false net_probe_running
net_checks_before="$(net_native_checks)"
expect "the user can request a fresh connectivity check" ok ipc vgs.network invoke action '{"kind":"check-connectivity"}'
expect_poll "the manual check reaches CheckConnectivity" yes net_check_progress
net_expect_fixture "the portal test restores disabled checks" checks-off || return 0
expect_poll "the portal test restores the connected result" '"connected"' net_state
expect "a full connection refuses an unrelated sign-in request" 'refused: portal=unavailable' ipc vgs.network invoke action '{"kind":"sign-in"}'
device_reply_clear xdg-open
net_widget_click || fail "the click on the Network widget failed"
expect_poll "a click on the widget opens the dropdown" shown net_shown panel
summon_drawn panel vgs.network || fail "the dropdown never drew a frame"
expect "the dropdown is a popup under the widget, not a centred layer" 0 layer_count vgs:panel
expect_poll "the dropdown lists both wired devices with their states" "[[\"enp10s0\", \"$(net_wired_text connected)\"], [\"enp11s0\", \"$(net_wired_text no-cable)\"]]" net_wired_rows panel
click 40 "$((mon_h - 40))" || fail "the press outside the dropdown failed"
expect_poll "a press outside closes the dropdown" hidden net_shown panel
# The dropdown keeps its content through its close motion. A SummonPopup
# copy under the widget closes with the motion slowed, and the scan lease
# and the Wi-Fi rows are read at the close frame. Control: a copy that
# closes the plugin before the motion.
net_motion_theme="$home/.config/vgshell/theme.json"
net_motion_had_theme=false
if [[ -f $net_motion_theme ]]; then
  cp -- "$net_motion_theme" "$sandbox/network-motion-theme.json"
  net_motion_had_theme=true
fi
printf '%s\n' '{"schemaVersion":1,"name":"network-motion","tokens":{"motion":{"scale":4}}}' >"$net_motion_theme.tmp"
mv -T -- "$net_motion_theme.tmp" "$net_motion_theme"
expect_poll "the flyout motion is slowed for the close-frame check" 400 ipc smoke themeValue motion.flyout.travel.duration
net_close_first="$repo/shell/Hosts/SummonPopupCloseFirst.qml"
python3 - "$repo/shell/Hosts/SummonPopup.qml" "$net_close_first" <<'PYCLOSE'
import pathlib,sys
source,first=map(pathlib.Path,sys.argv[1:])
s=source.read_text()
old="        closing = true;\n"
assert s.count(old)==1, "the SummonPopup close start must occur once"
first.write_text(s.replace(old,old+"        slot.closeInstance();\n"))
PYCLOSE
net_leases() { ipc smoke networkScan | py_reply 'import json,sys; print(json.load(sys.stdin)["leases"])'; }
net_close_state() {
  local scan rows
  scan="$(ipc smoke networkScan)" || return 1
  rows="$(net_rows panel)" || return 1
  printf '%s rows=%s\n' "$scan" "$rows"
}
# net_close_frame LABEL NAME FILE: opens the dropdown in the SummonPopup
# copy FILE under the widget, starts its close and sets net_close to `kept`
# when the close frame reads as the open card did, `changed` with both
# readings when it does not, or `late` when the motion ended first.
net_close_frame() {
  local before during progress leases
  leases="$(net_leases)"
  expect "$1: the probe builds the popup copy" ok ipc smoke popupLoad "$2" "$3" "$(bar_key)" vgs.network '{"pluginId":"vgs.network","kind":"panel","request":{"anchor":"@instance","anchored":true,"payloadJson":"{}"}}'
  expect "$1: the copy's dropdown opens" '' ipc smoke invokeInstance panel vgs.network open '{}'
  expect_poll "$1: the copy's dropdown comes to rest" 1 ipc smoke popupRead "$2" motionProgress
  before="$(net_close_state)" || before=unread
  ipc smoke popupCall "$2" requestDismiss >/dev/null
  during="$(net_close_state)" || during=unread
  progress="$(ipc smoke popupRead "$2" motionProgress)" || progress=unread
  if ! python3 -c 'import sys; sys.exit(0 if 0 < float(sys.argv[1]) < 1 else 1)' "$progress" 2>/dev/null; then net_close="late progress=$progress"
  elif [[ $before == unread || $during != "$before" ]]; then net_close="changed before=$before during=$during"
  else net_close=kept; fi
  expect_poll "$1: the copy releases its popup after closing" false ipc smoke popupRead "$2" visible
  expect_poll "$1: the plugin heard close() when the motion ended" "$leases" net_leases
  expect "$1: the probe drops the copy" ok ipc smoke popupDrop "$2"
  expect_poll "$1: the copy's dropdown leaves the build records" absent ipc smoke readInstance panel vgs.network payload
}
net_close_frame "Close frame" network-close "$repo/shell/Hosts/SummonPopup.qml"
expect "the dropdown keeps its scan and rows at the close frame" kept printf '%s\n' "$net_close"
net_close_frame "Close-first control" network-close-first "$net_close_first"
expect "control: closing the plugin before the motion changes the close frame" changed printf '%s\n' "${net_close%% *}"
rm -f -- "${net_close_first:?}"
if [[ $net_motion_had_theme == true ]]; then
  cp -- "$sandbox/network-motion-theme.json" "$net_motion_theme.tmp"
  mv -T -- "$net_motion_theme.tmp" "$net_motion_theme"
else
  rm -f -- "${net_motion_theme:?}"
fi
expect_poll "the flyout motion returns after the close-frame check" 100 ipc smoke themeValue motion.flyout.travel.duration
device_reply nmcli 0 $'GENERAL.DEVICE:enp10s0\nIP4.ADDRESS[1]:192.0.2.10/24' -t device show enp10s0
net_details_layout "Details"
expect "Details expands with a stable layout" steady printf '%s\n' "$net_layout"
# Controls: a widget that toggles without its anchor opens the centred
# layer, and a body that draws a line while loading moves the row under it.
net_copy="$home/.config/vgshell/plugins/vgs.network"
mkdir -p -- "$net_copy"
cp -R -- "$repo/shell/plugins/vgs.network/." "$net_copy/"
python3 - "$net_copy/Widget.qml" "$net_copy/NetworkBody.qml" <<'PYWIRED'
import pathlib,sys
widget,body=map(pathlib.Path,sys.argv[1:])
s=widget.read_text(); old='shell.surfaces.toggle("panel", "{}", root)'
assert s.count(old)==1
widget.write_text(s.replace(old,'shell.surfaces.toggle("panel", "{}")'))
s=body.read_text(); old='visible: parent.detailState === "failed"'
assert s.count(old)==1
body.write_text(s.replace(old,'visible: parent.detailState !== "ready"'))
PYWIRED
rescan "the dropdown and layout controls are discovered"
expect_poll "the controls' service publishes the wired devices" '[["enp10s0", "connected"], ["enp11s0", "no-cable"]]' net_wired
net_widget_click || fail "the click on the control widget failed"
expect_poll "the control widget opens its panel" shown net_shown panel
expect_poll "control: a widget without its anchor opens the centred layer" 1 layer_count vgs:panel
expect "the control's panel closes" ok ipc shell hide panel vgs.network
expect_poll "the control's panel is gone" hidden net_shown panel
net_details_layout "Details control"
expect "control: a line drawn while loading moves the row under it" moved-while-loading printf '%s\n' "${net_layout%% *}"
rm -rf -- "${net_copy:?}"
rescan "the shipped plugin is restored after the dropdown controls"
net_expect_fixture "the mock removes the Ethernet devices" unwired || return 0
expect_poll "Network lists no wired device" '[]' net_wired
expect_poll "Network is disconnected again" '"offline"' net_state

net_copy="$home/.config/vgshell/plugins/vgs.network"
mkdir -p -- "$net_copy"
cp -R -- "$repo/shell/plugins/vgs.network/." "$net_copy/"
rescan "the disposable service source is discovered"
expect_poll "the disposable service is ready" '"offline"' net_state
net_expect_fixture "the reason controls restore a saved profile without a password" prepare || return 0
python3 - "$net_copy/NetworkBody.qml" <<'PYREASONCONTROL'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();old='text: root.network.problem || ""'
assert s.count(old)==1
p.write_text(s.replace(old,'text: ""'))
PYREASONCONTROL
rescan "the missing dialog reason control is discovered"
expect_poll "the dialog reason control is ready" '"offline"' net_state
expect "the dialog reason control opens" ok ipc shell summon panel vgs.network '{}'
expect_poll "the dialog reason control is mounted" shown net_shown panel
net_reprompt "Missing reason control" || return 0
net_reason_control() { (failures=0 behaviour_failures=0; net_saved_reason control >"$sandbox/network-reason-control.log"; echo "$failures"); }
expect "control: the missing message fails the same dialog reason assertion" 1 net_reason_control
control_output "$sandbox/network-reason-control.log"
expect "the dialog reason control closes" ok ipc shell hide panel vgs.network
cp -- "$repo/shell/plugins/vgs.network/NetworkBody.qml" "$net_copy/NetworkBody.qml"
python3 - "$net_copy/NetworkBody.qml" <<'PYHINTCONTROL'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();old='visible: text !== "" && !root.prompting'
assert s.count(old)==1
p.write_text(s.replace(old,'visible: text !== ""'))
PYHINTCONTROL
rescan "the duplicate list hint control is discovered"
expect_poll "the list hint control is ready" '"offline"' net_state
expect "the list hint control opens" ok ipc shell summon panel vgs.network '{}'
expect_poll "the list hint control is mounted" shown net_shown panel
net_reprompt "Duplicate hint control" || return 0
net_hint_control() { (failures=0 behaviour_failures=0; net_hint_suppressed control >"$sandbox/network-hint-control.log"; echo "$failures"); }
expect "control: the duplicate hint fails the same single-reason assertion" 1 net_hint_control
control_output "$sandbox/network-hint-control.log"
expect "the list hint control closes" ok ipc shell hide panel vgs.network
cp -- "$repo/shell/plugins/vgs.network/NetworkBody.qml" "$net_copy/NetworkBody.qml"
python3 - "$net_copy/NetworkBody.qml" <<'PYCLOSEPROMPT'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();old='if (promptKey !== "") cancelPassword(false);'
assert s.count(old)==1
p.write_text(s.replace(old,'if (false) cancelPassword(false);'))
PYCLOSEPROMPT
rescan "the prompt-close cancellation control is discovered"
expect_poll "the prompt-close control is ready" '"offline"' net_state
expect "the prompt-close control opens" ok ipc shell summon panel vgs.network '{}'
expect_poll "the prompt-close control is mounted" shown net_shown panel
net_reprompt "Close cancellation control" || return 0
expect "the prompt-close control closes" ok ipc shell hide panel vgs.network
expect_poll "the prompt-close control destroys its view" absent ipc smoke networkField panel
net_close_prompt_control() { (failures=0 behaviour_failures=0; net_closed_prompt control >"$sandbox/network-close-prompt-control.log"; echo "$failures"); }
expect "control: skipped cancellation fails the same null-prompt assertion" 1 net_close_prompt_control
control_output "$sandbox/network-close-prompt-control.log"
expect "the prompt-close control reopens" ok ipc shell summon panel vgs.network '{}'
expect_poll "control: the retained service prompt returns on reopen" true net_dialog panel
expect "the row cancels the control prompt" ok ipc vgs.network invoke action '{"kind":"cancel"}'
expect "the prompt-close control closes after cleanup" ok ipc shell hide panel vgs.network
cp -- "$repo/shell/plugins/vgs.network/NetworkBody.qml" "$net_copy/NetworkBody.qml"
rescan "the shipped prompt cancellation is restored"
expect_poll "the restored prompt service is ready" '"offline"' net_state
expect "System opens the rebuild cancellation test" ok ipc shell summon window vgs.system '{"pane":"vgs.network"}'
expect_poll "the rebuild cancellation pane is mounted" shown net_shown window
net_join_close_test private-cleaned idle rebuild || return 0
python3 - "$net_copy/NetworkJoin.qml" <<'PYEAPCONTROL'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);source=p.read_text();old='identity: identity.text, domain: domain.text'
assert source.count(old)==1
p.write_text(source.replace(old,'identity: "wrong-user", domain: domain.text'))
PYEAPCONTROL
rescan "the enterprise field mapping control is discovered"
expect_poll "the enterprise mapping control is ready" '"offline"' net_state
expect "System remounts the enterprise mapping control" ok ipc shell summon window vgs.system '{"pane":"vgs.network"}'
expect_poll "the enterprise mapping control pane is mounted" shown net_shown window
net_expect_fixture "the control adds scanned enterprise input" enterprise || return 0
expect_poll "the control sees the scanned enterprise network" True net_enterprise_seen
net_enterprise_submit_test no peap invalid
net_expect_fixture "the control removes its enterprise input" unenterprise || return 0
cp -- "$repo/shell/plugins/vgs.network/NetworkJoin.qml" "$net_copy/NetworkJoin.qml"
python3 - "$net_copy/Service.qml" <<'PYCANCELCONTROL'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();old='joinHelper.running = false;'
assert s.count(old)==1
p.write_text(s.replace(old,'/* control: retain activation after form close */'))
PYCANCELCONTROL
rescan "the form cancellation control is discovered"
expect_poll "the cancellation control finishes its backend probes" '"offline"' net_state
expect "System opens the cancellation control" ok ipc shell summon window vgs.system '{"pane":"vgs.network"}'
expect_poll "the cancellation control pane is mounted" shown net_shown window
net_join_close_test invalid join || return 0
# Releasing the fake's barrier lets its failed activation finish normally.
python3 - "$net_join_dir/world.json" <<'PYJOINRELEASE'
import json,pathlib,sys,tempfile
p=pathlib.Path(sys.argv[1]);world=json.loads(p.read_text());world["hold"]=None
with tempfile.NamedTemporaryFile("w",dir=p.parent,delete=False) as updated:
    json.dump(world,updated)
pathlib.Path(updated.name).replace(p)
PYJOINRELEASE
expect_poll "the released control cleans its UUID" private-cleaned net_join_record
expect_poll "the released control ends its operation" idle net_action
expect "System closes the cancellation control" ok ipc shell hide window vgs.system
cp -- "$repo/shell/plugins/vgs.network/Service.qml" "$net_copy/Service.qml"
python3 - "$net_copy/Service.qml" <<'PY'
import sys
p=sys.argv[1];s=open(p).read();old='if (Logic.shouldReprompt(Logic.enumName(reason, failureVariants), security, pending.known)) {'
assert s.count(old)==1
open(p,"w").write(s.replace(old,'if (false && Logic.shouldReprompt(Logic.enumName(reason, failureVariants), security, pending.known)) {'))
PY
rescan "the reprompt control is discovered"
expect_poll "the control's service is built" True record_exists vgs.network
expect_poll "the reprompt control retains the saved profile" True net_known
expect "the control's flyout opens" ok ipc shell summon panel vgs.network '{}'
expect_poll "the control's flyout is shown" shown net_shown panel
expect_poll "the reprompt control lists its saved disconnected network" '[["VGS Smoke Wi-Fi", 82, true, false]]' net_rows panel
expect_poll "the reprompt control finishes its backend probes" '"offline"' net_state
expect "the control connects the saved profile" ok net_do connect
expect_poll "the control has an activation to fail" connect net_action
net_expect_fixture "the control emits the wrong password failure" fail || return 0
expect_poll "control: a bare retry provides no password prompt" none net_prompt
expect "the control closes" ok ipc shell hide panel vgs.network
net_expect_fixture "the failed control activation is removed" drop-active || return 0
# An empty submitted PSK must not satisfy the mock's exact secret check.
cp -- "$repo/shell/plugins/vgs.network/Service.qml" "$net_copy/Service.qml"
python3 - "$net_copy/NetworkBody.qml" <<'PYEMPTY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();old='n.connectWithPsk(secret);'
assert s.count(old)==1
p.write_text(s.replace(old,'n.connectWithPsk("");'))
PYEMPTY
rescan "the empty-PSK control is discovered"
expect "the empty-PSK control opens" ok ipc shell summon panel vgs.network '{}'
expect_poll "the empty-PSK control finishes its backend probes" '"offline"' net_state
expect "the empty-PSK control first uses the saved profile" ok net_do connect
expect_poll "the empty-PSK control reaches Connecting" True net_changing
net_expect_fixture "the empty-PSK control needs a password" fail || return 0
expect_poll "the empty-PSK control has a password field" prompt net_prompt
net_expect_fixture "the empty-PSK control removes its failed activation" drop-active || return 0
type_keys network-smoke-joined-secret
type_keys -k Return
expect_poll "control: an empty submitted PSK stays Connecting" True net_changing
expect "control: an empty PSK does not join" False net_joined
net_expect_fixture "the empty-PSK control ends its failed request" fail || return 0
net_expect_fixture "the empty-PSK control removes the activation" drop-active || return 0
expect "the empty-PSK control cancels its prompt" ok ipc vgs.network invoke action '{"kind":"cancel"}'
expect "the empty-PSK control closes" ok ipc shell hide panel vgs.network
# The prompt's controls, in one copy: the password field planted in the
# body, outside the dialog, and a prompt that reads no scrolled view.
cp -- "$repo/shell/plugins/vgs.network/NetworkBody.qml" "$net_copy/NetworkBody.qml"
python3 - "$net_copy/NetworkBody.qml" <<'PYPROMPT'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text()
field=s[s.index('        TextField {\n            id: password\n'):]
field=field[:field.index('        }\n')+len('        }\n')]
slot='    Scrim {\n        visible: root.prompting\n'
view='                promptView = at;\n'
assert s.count(field)==1 and s.count(slot)==1 and s.count(view)==1
s=s.replace(field,'').replace(slot,field+slot).replace(view,'                break;\n')
p.write_text(s)
PYPROMPT
rescan "the prompt controls are discovered"
expect_poll "the prompt controls finish their backend probes" '"offline"' net_state
expect "System opens the prompt controls" ok ipc shell summon window vgs.system '{"pane":"vgs.network"}'
expect_poll "the prompt controls' pane is mounted" shown net_shown window
net_reprompt "Prompt controls" || return 0
expect_poll "the prompt controls focus the planted field" '{"masked":true,"length":0,"focused":true}' ipc smoke networkField window
expect "control: a field outside the dialog is not the dialog's own" false ipc smoke activeFocusWithin window vgs.network Dialog
net_follow_shorten || return 0
net_follows_control="$(net_dialog_follows window)" || net_follows_control=unread
expect "control: a prompt that reads no view stays put on a scrolled page" fixed printf '%s\n' "${net_follows_control%% *}"
net_follow_restore
expect "the prompt controls cancel their prompt" ok ipc vgs.network invoke action '{"kind":"cancel"}'
expect_poll "the prompt controls hold no prompt" none net_prompt
expect "System closes the prompt controls" ok ipc shell hide window vgs.system
expect_poll "the prompt controls' pane is gone" hidden net_shown window
# The focus controls, in one copy: no hand-off to the dialog when it shows,
# and the page left enabled behind it.
cp -- "$repo/shell/plugins/vgs.network/NetworkBody.qml" "$net_copy/NetworkBody.qml"
python3 - "$net_copy/NetworkBody.qml" <<'PYFOCUS'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text()
handoff='    onShownPromptChanged: if (shownPrompt !== "") Qt.callLater(() => { if (root.prompting) prompt.takeFocus(); })\n'
page='        enabled: !root.prompting\n'
assert s.count(handoff)==1 and s.count(page)==1
p.write_text(s.replace(handoff,'').replace(page,''))
PYFOCUS
rescan "the focus controls are discovered"
expect_poll "the focus controls finish their backend probes" '"offline"' net_state
expect "the focus controls' dropdown opens" ok ipc shell summon panel vgs.network '{}'
expect_poll "the focus controls' list takes the keyboard" true ipc smoke activeFocusWithin panel vgs.network NetworkBody
net_share_prompt "Focus controls" || return 0
type_keys partial
expect "control: with no hand-off the text typed after Share misses the field" '{"masked":true,"length":0,"focused":false}' ipc smoke networkField panel
expect "the focus controls cancel the dropdown's prompt" ok ipc vgs.network invoke action '{"kind":"cancel"}'
expect_poll "the focus controls' dropdown holds no prompt" none net_prompt
expect "the focus controls' dropdown closes" ok ipc shell hide panel vgs.network
expect "System opens the focus controls" ok ipc shell summon window vgs.system '{"pane":"vgs.network"}'
expect_poll "the focus controls' pane is mounted" shown net_shown window
net_reprompt "Focus controls in System" || return 0
expect_poll "the focus controls' System dialog shows" true net_dialog window
click_in 'window:System Settings' window vgs.network TextField "" || fail "the click on the focus controls' field failed"
type_keys partial
expect_poll "the focus controls' field takes the typed text" '{"masked":true,"length":7,"focused":true}' ipc smoke networkField window
net_search_click || fail "the click on the focus controls' System search failed"
expect_poll "the focus controls' search takes the keyboard" '[false, false]' net_dialog_focus window
net_tab_to_body || fail "Tab from the focus controls' System search never reached the network body"
expect_poll "control: Tab from the search reaches a page left enabled behind the dialog" '[false, true]' net_dialog_focus window
expect "the focus controls cancel the System prompt" ok ipc vgs.network invoke action '{"kind":"cancel"}'
expect_poll "the focus controls hold no prompt" none net_prompt
expect "System closes the focus controls" ok ipc shell hide window vgs.system
expect_poll "the focus controls' pane is gone" hidden net_shown window
# The scrim's control: the Scrim parented back to the body.
cp -- "$repo/shell/plugins/vgs.network/NetworkBody.qml" "$net_copy/NetworkBody.qml"
python3 - "$net_copy/NetworkBody.qml" <<'PYSCRIM'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();old='    Scrim {\n        visible: root.prompting\n        parent: root.promptHost\n'
assert s.count(old)==1
p.write_text(s.replace(old,'    Scrim {\n        visible: root.prompting\n'))
PYSCRIM
rescan "the scrim control is discovered"
expect_poll "the scrim control finishes its backend probes" '"offline"' net_state
net_widget_click || fail "the click on the Network widget for the scrim control failed"
expect_poll "the scrim control's dropdown opens" shown net_shown panel
summon_drawn panel vgs.network || fail "the scrim control's dropdown never drew a frame"
net_reprompt "Scrim control" || return 0
expect_poll "the scrim control's dialog shows" true net_dialog panel
net_scrim_control="$(net_scrim_covers)" || net_scrim_control=unread
expect "control: a scrim in the body leaves the header and footer undimmed" partial printf '%s\n' "${net_scrim_control%% *}"
net_dropdown_click itemGeometry Switch "" || fail "the click on the scrim control's Wi-Fi switch failed"
expect_poll "control: the Wi-Fi switch over a body scrim turns Wi-Fi off" False net_radio
expect "the scrim control restores Wi-Fi" ok ipc vgs.network invoke action '{"kind":"radio"}'
expect_poll "the scrim control's Wi-Fi is back on" True net_radio
expect_poll "the scrim control lists the saved network again" True net_known
expect "the scrim control closes" ok ipc shell hide panel vgs.network
cp -- "$repo/shell/plugins/vgs.network/NetworkBody.qml" "$net_copy/NetworkBody.qml"
# These mutations make the production scanner and keyboard checks red.
python3 - "$net_copy/Service.qml" "$net_copy/NetworkBody.qml" <<'PYCONTROL'
import pathlib,sys
service,body=map(pathlib.Path,sys.argv[1:])
s=service.read_text(); old='else if (wifiDevice !== null) wifiDevice.scannerEnabled = false;'
assert s.count(old)==1
service.write_text(s.replace(old,'else if (wifiDevice !== null) wifiDevice.scannerEnabled = true;'))
s=body.read_text(); old='onActivated: index => root.activate(root.rows[index])'
assert s.count(old)==1
body.write_text(s.replace(old,'onActivated: index => root.localProblem = "Keyboard control consumed Enter."'))
PYCONTROL
rescan "the scanner and keyboard controls are discovered"
expect_poll "the keyboard control finishes its backend probes" '"offline"' net_state
expect "the keyboard control opens" ok ipc shell summon panel vgs.network '{}'
expect_poll "the keyboard control takes focus" true ipc smoke activeFocusWithin panel vgs.network NetworkBody
type_keys -k Return
expect_poll "control: the disabled keyboard route consumes Enter" '"Keyboard control consumed Enter."' ipc smoke readDescendant panel vgs.network NetworkBody localProblem
expect "control: Enter without activation leaves the connection idle" idle net_action
expect "the scanner control closes" ok ipc shell hide panel vgs.network
expect_poll "control: a scanner left enabled is observable after close" '{"leases":0,"device":null,"scanning":true}' ipc smoke networkScan
# Restoring all other code makes the owner-retention control independent.
cp -- "$repo/shell/plugins/vgs.network/Service.qml" "$net_copy/Service.qml"
cp -- "$repo/shell/plugins/vgs.network/NetworkBody.qml" "$net_copy/NetworkBody.qml"
python3 - "$net_copy/NetworkBody.qml" <<'PYSHARECONTROL'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();old='shareTarget = null;'
assert s.count(old)==1
p.write_text(s.replace(old,'/* control: retain the share owner */'))
PYSHARECONTROL
rescan "the QR owner-retention control is discovered"
expect "the QR control opens" ok ipc shell summon panel vgs.network '{}'
expect_poll "the QR control takes list focus" true ipc smoke activeFocusWithin panel vgs.network NetworkBody
type_keys -k Menu
expect_poll "the QR control's menu opens" true ipc smoke readDescendant panel vgs.network Menu opened
expect_poll "the QR control's menu selects Share QR code" '["Share QR code"]' net_menu_end
type_keys -k Return
expect_poll "the QR control reaches the same ready state" ready net_qr_state panel
expect "the QR control observer retains its view" ok ipc smoke networkRememberShare panel
type_keys -k Return
expect_poll "control: a closed QR view stays retained" true ipc smoke networkRememberedShareAlive
expect "control: the retained QR owner fails the zero-owner reading" 1 net_qr_owner_count
net_qr_retained_control() { (failures=0 behaviour_failures=0; net_qr_released retained >"$net_qr_dir/retained-control.log"; echo "$failures"); }
expect "control: the retained QR owner fails the same release check" 1 net_qr_retained_control
control_output "$net_qr_dir/retained-control.log"
expect "the retained QR control closes its flyout" ok ipc shell hide panel vgs.network
rm -rf -- "${net_copy:?}"
rescan "the shipped plugin is restored"
expect "Network disables after its row" ok ipc shell setPluginEnabled vgs.network false
expect_poll "Network releases its service build record" False record_exists vgs.network
user_config_restore "$net_saved"
expect "the row restores the configuration" ok ipc shell reloadConfig
device_reply_clear nmcli
device_reply_clear systemctl
sentinel_restore "$shim/nmcli"
sentinel_restore "$shim/qrencode"
if [[ $net_qr_had_shim == false ]]; then rm -f -- "$shim/qrencode"; fi
