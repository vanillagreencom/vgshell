# NetworkManager-only network views against S08's private NM mock. The
# device guard checks the running shell before it reads Networking. The
# existing stand-ins record systemctl/nmcli argv; fixtures/devices/network.py
# extends only the NM mock. Each kind reads its own delivered status.
# No latency budget is measured. Polls use expect_poll's IPC round trip.
# The production reprompt control suppresses the password prompt in a
# sandbox plugin copy. The secret reader's control plants a synthetic log.
# inputs: shell/plugins/vgs.network/* shell/Commons/Nmcli.js shell/Commons/qmldir shell/plugins/vgs.system/* shell/Core/* shell/Hosts/* shell/Ui/* shell/Commons/* shell/shell.qml config/shell.json bin/vgshell-scan bin/vgshell-plugin-judge bin/lib/check-manifests.js bin/lib/qml-library.js scripts/smoke/fixtures/devices/* scripts/smoke/rows/device-fakes.sh scripts/smoke/rows/start-order.sh scripts/smoke/rows/overlay-capture.sh
set -euo pipefail
devices_ready network || return 0
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
# A details read waits while $net_hold exists, so the row sees its loading state.
net_hold="$sandbox/network-details-hold"
printf '#!/usr/bin/env bash\nif [[ " $* " == *" --get-values "* ]]; then\n  export NETWORK_QR_WORLD=%q NETWORK_QR_CALLS=%q NETWORK_QR_READY=%q\n  exec python3 %q "$@"\nfi\nif [[ " $* " == *" device show "* ]]; then while [[ -e %q ]]; do sleep 0.05; done; fi\nexec %q "$@"\n' "$net_qr_dir/world.json" "$net_qr_dir/calls" "$net_qr_dir/ready" "$net_qr_dir/nmcli" "$net_hold" "$(sentinel_saved "$shim/nmcli")" | sentinel_stand_over "$shim/nmcli"
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
net_fixture() { python3 "$repo/scripts/smoke/fixtures/devices/network.py" "unix:path=$rt_dir/system-bus" "$1"; }
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
net_unit $'LoadState=loaded\nActiveState=active'
net_permission yes
expect "the mock has a saved Wi-Fi profile" ok net_fixture prepare
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
expect "the mock replaces the Wi-Fi device" ok net_fixture replace
expect_poll "the lease moves to the replacement" '{"leases":1,"device":"wlan1","scanning":true}' ipc smoke networkScan
expect "the replaced device stops scanning" false ipc smoke networkRememberedScanning
expect "the mock restores the first device" ok net_fixture restore
expect_poll "the lease returns to the restored device" '{"leases":1,"device":"wlan0","scanning":true}' ipc smoke networkScan
expect "System closes the pane" ok ipc shell hide window vgs.system
expect_poll "both closed views release the scanner" '{"leases":0,"device":null,"scanning":false}' ipc smoke networkScan

# Native methods can refuse with no frontend failure signal. The sandbox
# probe only shortens the real service watchdog; its triggered handler runs.
expect "the connect refusal is installed" ok net_fixture refuse-connect
expect "a refused connect starts one operation" ok net_do connect
expect "the operation has a bounded running watchdog" '{"running":true,"bounded":true}' ipc smoke networkWatchdog false
expect "the sandbox advances the connect watchdog" ok ipc smoke networkWatchdog true
expect_poll "a silent connect refusal releases the operation" idle net_action
expect "a silent refusal has a retry message" '"The network change did not complete. Try again."' net_problem
expect "normal network requests are restored" ok net_fixture normal
expect "connect can retry after refusal" ok net_do connect
expect_poll "the retry reaches a native transition" True net_changing
expect "a noncredentials terminal failure removes activation" ok net_fixture drop-active
expect_poll "terminal connect failure releases the operation" idle net_action
expect "terminal failure can retry" ok net_do connect
expect_poll "the retry is connecting before radio cancellation" True net_changing
expect "radio off cancels the pending operation" ok ipc vgs.network invoke action '{"kind":"radio"}'
expect_poll "radio cancellation releases the operation" idle net_action
expect "the canceled mock activation is removed" ok net_fixture drop-active
expect "radio on restores the connection path" ok ipc vgs.network invoke action '{"kind":"radio"}'
expect "connect retries after radio cancellation" ok net_do connect
expect_poll "the source-loss request is connecting" True net_changing
expect "the pending source is replaced" ok net_fixture replace
expect_poll "device loss releases the operation" idle net_action
expect "the pending source is restored" ok net_fixture restore
expect "the source-loss activation is removed" ok net_fixture drop-active

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
expect "the mock emits a wrong saved password failure" ok net_fixture fail
expect_poll "a wrong saved password reprompts" prompt net_prompt
expect_poll "the reprompt is a masked focused field" '{"masked":true,"length":0,"focused":true}' ipc smoke networkField window
expect "the failed activation is removed before retry" ok net_fixture drop-active
type_keys partial
expect "an idle background failure is ignored" ok ipc smoke networkBackgroundFailure false
expect "the password prompt keeps its typed value" '{"masked":true,"length":7,"focused":true}' ipc smoke networkField window
type_keys -M ctrl -k a -m ctrl -k BackSpace
expect "the PSK update refusal is installed" ok net_fixture refuse-psk
type_keys network-smoke-joined-secret
type_keys -k Return
expect "the sandbox advances the PSK watchdog" ok ipc smoke networkWatchdog true
expect_poll "a refused PSK update releases the operation" idle net_action
expect "the field clears after the refused PSK update" '{"masked":true,"length":0,"focused":false}' ipc smoke networkField window
expect "normal PSK requests are restored" ok net_fixture normal
type_keys -k Return
expect_poll "connect retries after a refused PSK" connect net_action
expect "the retry requests a password again" ok net_fixture fail
expect_poll "the retry reprompts for the password" prompt net_prompt
expect "the retry activation is removed" ok net_fixture drop-active
type_keys network-smoke-joined-secret
type_keys -k Return
expect_poll "the supplied PSK joins the network" True net_joined
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
expect "the disconnect refusal is installed" ok net_fixture refuse-disconnect
expect "a refused disconnect starts one operation" ok net_do disconnect
expect "the sandbox advances the disconnect watchdog" ok ipc smoke networkWatchdog true
expect_poll "a refused disconnect releases the operation" idle net_action
expect "the joined network remains after refused disconnect" True net_joined
expect "normal disconnect requests are restored" ok net_fixture normal
expect "disconnect retries after refusal" ok net_do disconnect
expect_poll "the disconnect retry completes" False net_joined
expect_poll "the successful disconnect releases the operation" idle net_action
expect "the saved exact PSK can reconnect" ok net_do connect
expect_poll "the exact saved PSK reconnects" True net_joined
expect "the forget refusal is installed" ok net_fixture refuse-forget
expect "a refused forget starts one operation" ok net_do forget
expect "the sandbox advances the forget watchdog" ok ipc smoke networkWatchdog true
expect_poll "a refused forget releases the operation" idle net_action
expect "the saved profile remains after refused forget" True net_known
expect "normal forgetting is restored" ok net_fixture normal
type_keys -k Delete
expect_poll "Delete forgets the Wi-Fi profile" False net_known
expect "the joined activation disconnects after forget" ok net_fixture drop-active
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
net_widget_click() { rest_pointer && click_centre "$(bar_key)" vgs.network; }
net_below() { ipc smoke itemGeometry window vgs.network ListItem enp11s0 | py_reply 'import json,sys; print(json.load(sys.stdin)[1])'; }
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
  before="$(net_below)" || before=unread
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
  if [[ $before == unread || $during == unread || $after == unread ]]; then net_layout="unread before=$before during=$during after=$after"
  elif [[ $during != "$before" ]]; then net_layout="moved-while-loading before=$before during=$during after=$after"
  elif [[ $after == "$before" ]]; then net_layout="never-moved before=$before after=$after"
  else net_layout=steady; fi
}
expect "the mock adds two Ethernet devices" ok net_fixture wired
expect_poll "Network publishes each wired device's state" '[["enp10s0", "connected"], ["enp11s0", "no-cable"]]' net_wired
expect_poll "the connected wired device connects the computer" '"connected"' net_state
net_widget_click || fail "the click on the Network widget failed"
expect_poll "a click on the widget opens the dropdown" shown net_shown panel
summon_drawn panel vgs.network || fail "the dropdown never drew a frame"
expect "the dropdown is a popup under the widget, not a centred layer" 0 layer_count vgs:panel
expect_poll "the dropdown lists both wired devices with their states" "[[\"enp10s0\", \"$(net_wired_text connected)\"], [\"enp11s0\", \"$(net_wired_text no-cable)\"]]" net_wired_rows panel
click 40 "$((mon_h - 40))" || fail "the press outside the dropdown failed"
expect_poll "a press outside closes the dropdown" hidden net_shown panel
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
expect "the mock removes the Ethernet devices" ok net_fixture unwired
expect_poll "Network lists no wired device" '[]' net_wired
expect_poll "Network is disconnected again" '"offline"' net_state

net_copy="$home/.config/vgshell/plugins/vgs.network"
mkdir -p -- "$net_copy"
cp -R -- "$repo/shell/plugins/vgs.network/." "$net_copy/"
python3 - "$net_copy/Service.qml" <<'PY'
import sys
p=sys.argv[1];s=open(p).read();old='if (Logic.shouldReprompt(Logic.enumName(reason, failureVariants), security, pending.known)) {'
assert s.count(old)==1
open(p,"w").write(s.replace(old,'if (false && Logic.shouldReprompt(Logic.enumName(reason, failureVariants), security, pending.known)) {'))
PY
rescan "the reprompt control is discovered"
expect_poll "the control's service is built" True record_exists vgs.network
expect "the control re-adds a saved profile" ok net_fixture prepare
expect "the control's flyout opens" ok ipc shell summon panel vgs.network '{}'
expect_poll "the control's flyout is shown" shown net_shown panel
expect_poll "the reprompt control finishes its backend probes" '"offline"' net_state
expect "the control connects the saved profile" ok net_do connect
expect_poll "the control has an activation to fail" connect net_action
expect "the control emits the wrong password failure" ok net_fixture fail
expect_poll "control: a bare retry provides no password prompt" none net_prompt
expect "the control closes" ok ipc shell hide panel vgs.network
expect "the failed control activation is removed" ok net_fixture drop-active
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
expect "the empty-PSK control needs a password" ok net_fixture fail
expect_poll "the empty-PSK control has a password field" prompt net_prompt
expect "the empty-PSK control removes its failed activation" ok net_fixture drop-active
type_keys network-smoke-joined-secret
type_keys -k Return
expect_poll "control: an empty submitted PSK stays Connecting" True net_changing
expect "control: an empty PSK does not join" False net_joined
expect "the empty-PSK control ends its failed request" ok net_fixture fail
expect "the empty-PSK control removes the activation" ok net_fixture drop-active
expect "the empty-PSK control cancels its prompt" ok ipc vgs.network invoke action '{"kind":"cancel"}'
expect "the empty-PSK control closes" ok ipc shell hide panel vgs.network
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
expect "the retained QR control closes its flyout" ok ipc shell hide panel vgs.network
rm -rf -- "${net_copy:?}"
rescan "the shipped plugin is restored"
expect "Network disables after its row" ok ipc shell setPluginEnabled vgs.network false
expect_poll "Network releases its service build record" False record_exists vgs.network
cp -- "$net_saved" "$home/.config/vgshell/shell.json"
expect "the row restores the configuration" ok ipc shell reloadConfig
device_reply_clear nmcli
device_reply_clear systemctl
sentinel_restore "$shim/nmcli"
sentinel_restore "$shim/qrencode"
if [[ $net_qr_had_shim == false ]]; then rm -f -- "$shim/qrencode"; fi
