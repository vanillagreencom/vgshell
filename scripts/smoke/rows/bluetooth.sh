# vgs.bluetooth over the sandbox's device fakes
# (docs/architecture/validation.md § Host safety): python-dbusmock's bluez5
# template with the planted adapter hci0 and its paired, connected
# headphones, the rfkill stand-in, which here moves hci0 as bluetoothd
# follows rfkill (bluez_follow), and the bluetoothctl stand-in, which the
# core's pairing agent runs and which replays the transcript the row
# plants: a transcript pairs a held device as BlueZ does once the agent's
# answer completes bonding, and waits for a marker the row touches. No step
# reaches the host's BlueZ, rfkill or system bus. The service holds
# `system`, so the core probes the system steps; they run in the fakes'
# system tree (devices_system_tree), so no probe reaches the host's devices
# or units, and the systemctl stand-in answers that bluetooth.service
# runs.
#
# Rows: the service reads on; Off writes the soft block, the adapter goes
# down, the widget shows off, and a rebuilt service reads off again and
# unblocks nothing; On unblocks and waits for confirmed power, and with no
# auto power-on the service sets Powered itself after its wait, which the
# mock's own log and its unmoved PowerState show; a hard block shows the
# hardware-switch state, offers no switch, refuses On and runs no rfkill
# write; the flyout's discovery lease starts discovery, and a start BlueZ
# confirms only after the flyout closed is still stopped; three pairings
# through the System window's Bluetooth section each call Device1.Pair once
# with the agent's lease taken and released: a confirm prompt answered yes
# from the keyboard, a code to type dismissed once paired, and a PIN typed
# into the dialog that survives a later line of bluetoothctl's output;
# Disconnect and Connect clicks move the headphones; a failed Connect shows
# Connecting… with the busy spinner and then one failure sentence, and
# Retry connects it again; and a keyboard path from SUPER+COMMA turns
# Bluetooth off and on, turns Discoverable on, whose lease BlueZ's own end
# of Discoverable releases, writes Hide when off, disconnects a device with
# Return and forgets it with Delete, which removes it from the mock, and
# closes.
#
# The controls: one copy of the plugin whose discovery tick writes no stop,
# a plain lease counter, and whose pairing never calls Pair. The counter
# leaves the late-confirmed start running for 5 s, past the 1 s tick's
# three attempts and as long as a positive poll waits; the copy's pairing
# reaches done with the mock's Pair count at 0. A second copy, whose
# service lists no adapter, is the fixture of the stopped service: with the
# systemctl stand-in answering that bluetooth.service is loaded and not
# running, its section reads the service off, a click on Turn on the
# service hands the stand-in terminal `vgshell system apply service-bluetooth`
# through `status.act`, and before the click the terminal holds no record.
# Over that copy a LoadState systemctl cannot read, then one it does not
# know, leave the step unknown with only its reason changed, and the
# published service value follows the reason alone; a third copy without
# that republish keeps the old value. The stand-in terminal runs no
# system step. The shell's log over the row holds no unexpected error. Every poll is
# expect_poll's: 25 reads 0.2 s apart. The row leaves vgs.bluetooth and
# vgs.system enabled or disabled as it found them, discovery confirming,
# the follow off and no planted systemctl answer, whichever step it
# returns from.
# Nearby: 32 fake radios publish Alias, Name and RSSI changes every 50 ms.
# The actual Nearby rowsChanged observer checks stable keys and presentation,
# publications at the configured 500 ms cadence, and the held middle
# scroll offset through 10 s of churn, including loss of the focused tail.
# Radio 12 then keeps a changed name while the other radios still churn.
# Its displayed name must change without moving the selected row or scroll.
# Each rule has its own disposable production mutation. Cadence is a view
# contract, not a machine latency budget. State polling uses expect_poll.
# inputs: shell/plugins/vgs.bluetooth/* shell/plugins/vgs.system/* shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/Hosts/AppWindow.qml shell/Hosts/SummonHost.qml shell/Hosts/SummonPopup.qml shell/Ui/layout/Pane.qml shell/Ui/layout/ScrollArea.qml shell/Ui/layout/DeviceList.qml shell/Ui/controls/RowAction.qml shell/Ui/feedback/Spinner.qml scripts/smoke/Probe.qml scripts/smoke/fixtures/devices/* shell/Core/BluetoothAgent.qml shell/Core/BluetoothAgentModel.js shell/Core/SystemSteps.qml shell/Core/PluginStatus.qml shell/Core/Capabilities.qml shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/Hosts/PaneHost.qml bin/vgshell-system bin/vgshell-tui scripts/smoke/rows/device-fakes.sh shell/Core/Compositor.qml shell/Core/Dispatch.js shell/Ui/overlay/Menu.qml shell/Ui/overlay/DismissScope.qml shell/Ui/layout/DeviceRow.qml
set -euo pipefail

bt_keyboard=00:1B:66:AA:BB:02
bt_mouse=00:1B:66:AA:BB:03
bt_headphones=00:1B:66:AA:BB:01
bt_speaker=00:1B:66:AA:BB:05
bt_pad=00:1B:66:AA:BB:06
bt_default='"                 default-agent"'
bt_off='"                 agent off"'

# Intentional menu closes must restore native keys without moving the
# outside pointer. The second real device's connection proves Return acts.
bt_menu_keyboard() {
  local close connected pointer pointer_after
  for close in trigger escape; do
    type_keys -k Menu || { fail "Bluetooth $close: opening the device menu failed"; return 1; }
    expect_poll "Bluetooth $close: the device menu opens" True bt_menu_open
    rest_pointer || { fail "Bluetooth $close: parking the pointer outside failed"; return 1; }
    pointer="$(bt_menu_pointer)" || { fail "Bluetooth $close: reading the outside pointer failed"; return 1; }
    if [[ $close == trigger ]]; then
      type_keys -k End -k Up || { fail "Bluetooth trigger: selecting the trust action failed"; return 1; }
      expect_poll "Bluetooth trigger: the trust action is selected" trust bt_menu_choice
      type_keys -k Return || { fail "Bluetooth trigger: activating the trust action failed"; return 1; }
      connected=False
    else
      type_keys -k Escape || { fail "Bluetooth escape: sending Escape to the menu failed"; return 1; }
      connected=True
    fi
    expect_poll "Bluetooth $close: the menu closes" False bt_menu_open
    expect_poll "Bluetooth $close: native keys return to the headphones row" "Smoke Headphones" bt_focus
    pointer_after="$(bt_menu_pointer)" || { fail "Bluetooth $close: reading the restored pointer failed"; return 1; }
    expect "Bluetooth $close: the outside pointer stays at its original position" "$pointer" printf '%s' "$pointer_after"
    printf '  menu_activation close=%s pointer_before=%s pointer_after=%s\n' "$close" "$pointer" "$pointer_after"
    type_keys -k Down || { fail "Bluetooth $close: sending Down to the device list failed"; return 1; }
    expect_poll "Bluetooth $close: Down selects the keyboard with the pointer outside" "Smoke Keyboard" bt_focus
    type_keys -k Return || { fail "Bluetooth $close: sending Return to the selected device failed"; return 1; }
    expect_poll "Bluetooth $close: Return acts on the selected keyboard" "$connected" bt_device "$bt_keyboard" Connected
    type_keys -k Up || { fail "Bluetooth $close: returning to the headphones with Up failed"; return 1; }
    expect_poll "Bluetooth $close: Up returns to the headphones for another menu" "Smoke Headphones" bt_focus
  done
}
bt_menu_open() { ipc smoke menus window vgs.bluetooth | py_reply 'import json,sys; print(any(m["opened"] for m in json.load(sys.stdin)))'; }
bt_menu_choice() { ipc smoke menus window vgs.bluetooth | py_reply 'import json,sys; m=next((m for m in json.load(sys.stdin) if m["opened"]), {}); print("trust" if m.get("current") in ("Trust", "Don\u0027t trust") else "other")'; }
bt_menu_pointer() { hypr -j cursorpos | py_reply 'import json,sys; p=json.load(sys.stdin); print(json.dumps([p["x"],p["y"]]))'; }

bt_service() { ipc smoke readInstance service "${bt_id:-vgs.bluetooth}" "$1"; }
bt_view() { bt_service view | py_reply 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "${1:-key}"; }
bt_leases() { bt_service discovery | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["leases"]))'; }
bt_radio() { rfkill_state | py_reply 'import json,sys; print(json.dumps([r[1:] for r in json.load(sys.stdin) if r[0] == "bluetooth"]))'; }
bt_adapter() { bluez props "$bluez_adapter_path" org.bluez.Adapter1 | py_reply 'import json,sys; d=json.load(sys.stdin); print(" ".join(str(d[k]) for k in sys.argv[1:]))' "$@"; }
bt_path() { printf '%s/dev_%s' "$bluez_adapter_path" "${1//:/_}"; }
bt_device() { local mac="$1"; shift; bluez props "$(bt_path "$mac")" org.bluez.Device1 | py_reply 'import json,sys; d=json.load(sys.stdin); print(" ".join(str(d[k]) for k in sys.argv[1:]))' "$@"; }
bt_connect_answer() { # MAC fail|accept
  "${shell_env[@]}" python3 - "unix:path=$rt_dir/system-bus" "$(bt_path "$1")" "$2" "$devices_fixtures" <<'PY'
import sys

import dbus

bus_address, path, mode, fixtures = sys.argv[1:]
sys.path.insert(0, fixtures)
import world

if mode == "accept":
    code = world.CONNECT
elif mode == "fail":
    code = 'time.sleep(3)\nraise dbus.exceptions.DBusException("br-connection-page-timeout", name="org.bluez.Error.Failed")'
else:
    sys.exit("mode=" + mode)
bus = dbus.bus.BusConnection(bus_address)
dbus.Interface(bus.get_object(world.BLUEZ, path), world.MOCK).AddMethod(world.DEVICE, "Connect", "", "", code)
print("installed")
PY
}
bt_secondary() {
  ipc smoke readDescendant window vgs.bluetooth DeviceSections lists | py_reply 'import json,sys
target=sys.argv[1]
try:
    doc=json.load(sys.stdin)
except Exception:
    print("absent"); raise SystemExit
for row in doc.get("mine", []):
    if row.get("key") == target:
        print(json.dumps(row.get("secondary", ""), ensure_ascii=False))
        break
else:
    print("absent")
' "$1"
}
bt_failures() {
  ipc smoke readDescendant window vgs.bluetooth DeviceSections failures | py_reply 'import json,sys
text=sys.stdin.read().strip()
if text == "absent":
    print("absent")
else:
    print(json.dumps(json.loads(text), ensure_ascii=False))
'
}
bt_busy_spinner() {
  ipc smoke descendantGeometry window vgs.bluetooth | py_reply 'import json,sys
rows=json.load(sys.stdin)
target=sys.argv[1]
row_index=None
for i,row in enumerate(rows):
    if row.get("type") == "DeviceRow" and row.get("text") == target and row.get("visible"):
        row_index=i
        break
if row_index is None:
    print("absent"); raise SystemExit
def inside(index, owner):
    at=index
    while at is not None and at >= 0:
        if at == owner:
            return True
        at=rows[at].get("parent")
    return False
print(any(row.get("type") == "Spinner" and row.get("visible") and inside(i, row_index) for i,row in enumerate(rows)))
' "$1"
}
# `gone` once the mock holds no object for device MAC: its answer names
# the unknown object; any other answer is printed.
bt_device_gone() {
  local out
  if out="$(bluez props "$(bt_path "$1")" org.bluez.Device1 2>&1)"; then echo present; return; fi
  [[ $out == *UnknownObject* || $out == *UnknownMethod* ]] && echo gone || echo "$out"
}
bt_calls() { bluez calls "${2:-$bluez_adapter_path}" "$1"; }
# How many times anything set hci0's Powered over D-Bus, from the mock's
# own log: the service's fallback is the only writer in this row.
bt_powered_sets() {
  [[ -r $devices_dir/bluez.log ]] || { echo "bluez-log=unreadable"; return 1; }
  python3 -c 'import sys; print(sum(1 for line in open(sys.argv[1], errors="replace") if sys.argv[2] in line))' "$devices_dir/bluez.log" "Set $bluez_adapter_path org.bluez.Adapter1.Powered"
}
bt_count() { device_calls "$1" | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
# Each distinct argv the rfkill stand-in received since call COUNT.
bt_rfkill_argvs_since() { device_calls rfkill | py_reply 'import json,sys; print(json.dumps([list(c) for c in sorted({tuple(c) for c in json.load(sys.stdin)[int(sys.argv[1]):]})]))' "$1"; }
bt_widget() { ipc smoke readInstance "$(bar_key)" vgs.bluetooth "$1"; }
bt_widget_view() { bt_widget view | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]]))' "$1"; }
bt_widget_setting() { bt_widget settings | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get(sys.argv[1])))' "$1"; }
bt_pane() { ipc smoke readInstance window vgs.bluetooth "$1"; }
bt_panel_header() { ipc smoke paneHeader panel "${bt_id:-vgs.bluetooth}" | py_reply 'import json,sys
h=json.load(sys.stdin)
if h=="absent":
    print("absent"); raise SystemExit
s=h["switchBox"]; t=h["titleBox"]; g=h["gearBox"]
right = (g[0] - h["inlineGap"]) if g else h["contentRight"]
ok = h["title"] == "Bluetooth" and t is not None and s is not None and abs(t[0] - h["contentLeft"]) < 0.5 and abs(s[0] + s[2] - right) < 0.5 and abs(s[1] + s[3] / 2 - h["titleCenterY"]) <= 0.5
print(json.dumps({"placed": ok, "checked": h["switchChecked"], "enabled": h["switchEnabled"]}, sort_keys=True))'; }
bt_power_field_absent() { ipc smoke readDescendant panel "${bt_id:-vgs.bluetooth}" PowerField powerOn; }
bt_lists() { # HOST_KEY ID
  ipc smoke readDescendant "$1" "$2" DeviceSections lists | py_reply 'import json,sys; print(json.dumps([[r["text"], r["connected"]] for r in json.load(sys.stdin)["mine"]]))'
}
bt_mine() { bt_lists window vgs.bluetooth; }
bt_nearby_count() {
  ipc smoke readDescendant "$1" "$2" DeviceSections lists | py_reply 'import json,sys; print(len(json.load(sys.stdin)["nearby"]))'
}
bt_observation_rule() {
  ipc smoke bluetoothObservation | py_reply 'import json,sys
d=json.load(sys.stdin); samples=d["samples"]; times=d["publications"]; rule=sys.argv[1]
if not samples or len(samples[0]["keys"]) < 32 or len(times) < 2:
    print("not-observed"); raise SystemExit
base=samples[0]; expected=base["keys"]; names=dict(zip(expected, base["names"]))
if rule == "order":
    good=all(s["keys"] == [k for k in expected if k in s["keys"]] and all(names.get(k)==n for k,n in zip(s["keys"],s["names"])) for s in samples)
elif rule == "cadence":
    good=all(b-a >= 500 for a,b in zip(times,times[1:]))
elif rule == "scroll":
    good=base["contentY"] > 0 and samples[-1]["at"]-base["at"] >= 10000 and all(s["contentY"]==base["contentY"] for s in samples)
else:
    print("unknown-rule"); raise SystemExit
print("kept" if good else "rejected")
' "$1"
}
bt_cadence_facts() {
  ipc smoke bluetoothObservation | py_reply 'import json,sys
d=json.load(sys.stdin); times=d["publications"]; gaps=[b-a for a,b in zip(times,times[1:])]
print(json.dumps({"publications":len(times),"minGapMs":min(gaps) if gaps else None,"gapsMs":gaps}))
'
}
bt_settled_name_rule() {
  ipc smoke bluetoothObservation | py_reply 'import json,sys
d=json.load(sys.stdin); samples=d["samples"]; target="02:56:00:00:00:0C"; settled="Settled Nearby Radio 12"
if not samples or target not in samples[0]["keys"]:
    print("not-observed"); raise SystemExit
base=samples[0]; names=dict(zip(base["keys"],base["names"])); final=dict(zip(samples[-1]["keys"],samples[-1]["names"]))
good=names[target]!=settled and final.get(target)==settled and base["focusedKey"]==target and base["focusedRowKey"]==target and base["contentY"]>0
good=good and all(s["keys"]==base["keys"] and s["focusedKey"]==target and s["focusedRowKey"]==target and s["contentY"]==base["contentY"] and all(k==target or names[k]==n for k,n in zip(s["keys"],s["names"])) for s in samples)
print("kept" if good else "rejected")
'
}
bt_trace_ready() {
  ipc smoke bluetoothObservation | py_reply 'import json,sys; d=json.load(sys.stdin); print("ready" if len(d["publications"])>=3 else "waiting")'
}
bt_churn_run() { # HOST ID MODE DURATION
  local host="$1" id="$2" mode="$3" duration="$4" pid
  expect "the Nearby observer attaches to $id" observing ipc smoke bluetoothObserve "$host" "$id"
  if [[ $mode == remove-tail ]]; then
    expect "the last Nearby row receives keyboard focus" 02:56:00:00:00:1F ipc smoke bluetoothFocus 31
    expect "the expanded Bluetooth body rests at its midpoint" middle bt_middle
    expect "the scroll observer starts after focus and scrolling" observing ipc smoke bluetoothObserve "$host" "$id"
  fi
  spawn "$sandbox/bt-churn-$id-$mode.log" "${shell_env[@]}" python3 "$devices_fixtures/world.py" "unix:path=$rt_dir/system-bus" churn-nearby 32 "$duration" "$mode"
  pid="$spawn_pid"
  expect_poll "the production list publishes while the fake changes" ready bt_trace_ready
  wait "$pid" || fail "Bluetooth churn producer failed: $id"
  # A publication after the producer finished establishes the full window.
  expect_poll "the producer interval reaches the observer" ready bt_trace_after "$duration"
  local facts
  facts="$(bt_cadence_facts)" || { fail "Bluetooth cadence facts are unreadable: $id"; return; }
  printf 'bluetooth-cadence host=%s plugin=%s facts=%s\n' "$host" "$id" "$facts"
}
bt_trace_after() {
  ipc smoke bluetoothObservation | py_reply 'import json,sys; d=json.load(sys.stdin); s=d["samples"]; print("ready" if len(s)>1 and s[-1]["at"]-s[0]["at"] >= float(sys.argv[1])*1000 else "waiting")' "$1"
}
bt_middle() { ipc smoke bluetoothMiddle | py_reply 'import json,sys; y,total,height=json.load(sys.stdin); print("middle" if total>height and abs(y-(total-height)/2)<0.5 else "not-middle")'; }
bt_opening_rule() {
  ipc smoke bluetoothOpeningHeight "$1" | py_reply 'import json,sys
d=json.load(sys.stdin)
if d.get("state") != "shown" or d.get("height",0)<=0 or d.get("requestedHeight",0)<=0:
    print("not-observed")
else:
    print("fits" if d["height"]>=d["requestedHeight"] else "smaller")
'
}
bt_stability() {
  local id host rule copy source root_copy
  expect "32 nearby radios join the mock" nearby=32 bluez add-nearby 32
  expect "the Bluetooth expanded section opens for churn" ok ipc shell summon window vgs.system '{"pane":"vgs.bluetooth"}'
  expect_poll "the expanded section lists 32 radios" 32 bt_nearby_count window vgs.bluetooth
  expect_poll "the expanded opening height includes its Nearby content" fits bt_opening_rule vgs.bluetooth
  ipc smoke bluetoothOpeningHeight vgs.bluetooth
  expect "the settled-name observer attaches" observing ipc smoke bluetoothObserve window vgs.bluetooth
  expect "radio 12 receives focus before its rename" 02:56:00:00:00:0C ipc smoke bluetoothFocus 12
  expect "the settled-name view rests at its midpoint" middle bt_middle
  bt_churn_run window vgs.bluetooth settled-name 8
  expect "a continuously present radio adopts its settled name without moving order, focus or scroll" kept bt_settled_name_rule
  expect "the settled-name observer ends" ended ipc smoke bluetoothObserveEnd
  bt_churn_run window vgs.bluetooth remove-tail 10
  expect "Nearby order and names stay stable under churn" kept bt_observation_rule order
  expect "list publication stays within its cadence" kept bt_observation_rule cadence
  expect "expanded scroll stays unchanged through focused tail expiry" kept bt_observation_rule scroll
  expect "the expired focused tail selects its predecessor" '["02:56:00:00:00:1E", "02:56:00:00:00:1E"]' bt_focused_keys
  expect "a row above the focused device disappears" removed bluez remove-device 02:56:00:00:00:00
  expect_poll "the row above expires" 30 bt_nearby_count window vgs.bluetooth
  expect "the moving selection keeps the same focused device" '["02:56:00:00:00:1E", "02:56:00:00:00:1E"]' bt_focused_keys
  expect "a middle Nearby row receives keyboard focus" 02:56:00:00:00:10 ipc smoke bluetoothFocus 15
  expect "the focused middle device disappears" removed bluez remove-device 02:56:00:00:00:10
  expect_poll "the focused middle row expires" 29 bt_nearby_count window vgs.bluetooth
  expect "the departing middle selection gives focus to its next device" '["02:56:00:00:00:11", "02:56:00:00:00:11"]' bt_focused_keys
  expect "the production observer ends" ended ipc smoke bluetoothObserveEnd
  expect "29 remaining radios leave the mock" removed=29 bluez remove-nearby 32
  expect "the expanded section closes after churn" ok ipc shell hide window vgs.system
  expect "32 radios join for the flyout" nearby=32 bluez add-nearby 32
  expect "the flyout opens for churn" ok ipc shell summon panel vgs.bluetooth '{}'
  expect_poll "the flyout lists 32 radios" 32 bt_nearby_count panel vgs.bluetooth
  bt_churn_run panel vgs.bluetooth steady 2
  expect "the flyout Nearby order and names stay stable" kept bt_observation_rule order
  expect "the flyout publication stays within its cadence" kept bt_observation_rule cadence
  # Call the real close hook while the disposable host still holds the item.
  # This proves the timer stops, without destruction hiding a live timer.
  expect "the flyout close hook runs" closed ipc smoke bluetoothViewOpened panel vgs.bluetooth false
  expect "the closed-view observer starts" observing ipc smoke bluetoothObserve panel vgs.bluetooth
  bluez churn-nearby 32 1.5 >/dev/null
  expect "the closed view publishes nothing" 0 bt_publication_count
  expect "the closed view's actual timer is stopped" '[false]' ipc smoke bluetoothTimerState
  expect "the closed observer ends" ended ipc smoke bluetoothObserveEnd
  expect "the flyout closes after churn" ok ipc shell hide panel vgs.bluetooth
  expect "the flyout radios leave the mock" removed=32 bluez remove-nearby 32

  expect "the original plugin releases pairing for the controls" ok ipc shell setPluginEnabled vgs.bluetooth false
  expect_poll "the exclusive pairing capability is free" null bt_agent_holders
  # A fresh plugin directory for each rule avoids QML directory-cache reuse.
  for rule in order cadence scroll closed opening; do
    id="acme.bluetooth-$rule-control"
    copy="$home/.config/vgshell/plugins/$id"
    cp -R -- "$repo/shell/plugins/vgs.bluetooth" "$copy"
    python3 - "$copy" "$id" "$rule" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1]); ident,rule=sys.argv[2:]
p=root/"manifest.json"; d=json.loads(p.read_text()); d["id"]=ident; d["name"]=ident; p.write_text(json.dumps(d))
edits={
    "order": [("BluetoothLogic.js", "    return { mine: mine, nearby: held };", "    if (oldRows.length > 0) held.reverse();\n    return { mine: mine, nearby: held };")],
    "cadence": [("BluetoothLogic.js", "var DEVICE_REFRESH_MS = 500;", "var DEVICE_REFRESH_MS = 1;")],
    "scroll": [("DeviceSections.qml", "                view.contentY = Math.max(0, Math.min(offset, view.contentHeight - view.height));", "                void offset;")],
    "closed": [("DeviceSections.qml", "running: root.opened && root.visible && root.powerOn", "running: root.visible && root.powerOn")],
    "opening": [("DeviceSections.qml", "        root.refresh(false);\n    }\n\n    function refresh(mineOnly)", "        root.refresh(true);\n    }\n\n    function refresh(mineOnly)")]
}
for name,old,new in edits[rule]:
    p=root/name; text=p.read_text(); assert text.count(old)==1, old; p.write_text(text.replace(old,new))
    print("bluetooth-control rule="+rule+" source="+name+" edits=1")
PY
    rescan "the $rule control plugin is scanned"
    expect_poll "the $rule control is enabled" True plugin_enabled "$id"
    expect_poll "the $rule control owns pairing" "[\"$id\"]" bt_agent_holders
    local bt_id="$id"
    expect_poll "the $rule control reads On before opening" on bt_view
    # The opening control's mutant opens the section before Nearby fills,
    # so it tells only while that section stands under the window cap: at
    # four paired devices it opened at 537 of 559 at a row space of 16 and
    # at the cap at 20 (scripts/validate qml on main and on VGS-2226,
    # 2026-11-02). Two forgotten devices take two rows out of it.
    if [[ $rule == opening ]]; then
      expect "the speaker leaves My Devices for the opening control" removed bluez remove-device "$bt_speaker"
      expect "the pad leaves My Devices for the opening control" removed bluez remove-device "$bt_pad"
    fi
    expect "32 radios join for $rule control" nearby=32 bluez add-nearby 32
    if [[ $rule == scroll || $rule == opening ]]; then
      host=window
      expect "the $rule control section opens" ok ipc shell summon window vgs.system "{\"pane\":\"$id\"}"
    else
      host=panel
      expect "the $rule control flyout opens" ok ipc shell summon panel "$id" '{}'
    fi
    expect_poll "the $rule control lists 32 radios" 32 bt_nearby_count "$host" "$id"
    if [[ $rule == opening ]]; then
      expect_poll "control: empty first Nearby publication leaves a smaller window" smaller bt_opening_rule "$id"
      ipc smoke bluetoothOpeningHeight "$id"
    else
      if [[ $rule == scroll ]]; then bt_churn_run "$host" "$id" remove-tail 10; else bt_churn_run "$host" "$id" steady 2; fi
      if [[ $rule == closed ]]; then
        expect "the timer control close hook runs" closed ipc smoke bluetoothViewOpened "$host" "$id" false
        expect "the timer control observer starts after close" observing ipc smoke bluetoothObserve "$host" "$id"
        bluez churn-nearby 32 1.5 >/dev/null
        expect "control: a timer left running after close is detected" rejected bt_closed_rule
      else
        expect "control: the production $rule defect is rejected" rejected bt_observation_rule "$rule"
      fi
      expect "the $rule control observer ends" ended ipc smoke bluetoothObserveEnd
    fi
    if [[ $rule == scroll || $rule == opening ]]; then
      expect "the $rule control closes" ok ipc shell hide window vgs.system
      if [[ $rule == scroll ]]; then expect "the remaining control radios leave" removed=31 bluez remove-nearby 31; else expect "the opening control radios leave" removed=32 bluez remove-nearby 32; fi
    else
      expect "the $rule control closes" ok ipc shell hide panel "$id"
      expect "the control radios leave" removed=32 bluez remove-nearby 32
    fi
    expect "the $rule control is disabled" ok ipc shell setPluginEnabled "$id" false
    expect_poll "the $rule control releases pairing" null bt_agent_holders
    rm -rf -- "${copy:?}"
    rescan "the $rule control copy is removed"
  done
  expect "the original Bluetooth plugin is restored after the controls" ok ipc shell setPluginEnabled vgs.bluetooth true
  expect_poll "the original plugin owns pairing again" '["vgs.bluetooth"]' bt_agent_holders
}
bt_publication_count() { ipc smoke bluetoothObservation | py_reply 'import json,sys; print(len(json.load(sys.stdin)["publications"]))'; }
bt_focused_keys() { ipc smoke bluetoothObservation | py_reply 'import json,sys; d=json.load(sys.stdin)["current"]; print(json.dumps([d["focusedKey"],d["focusedRowKey"]]))'; }
bt_closed_rule() { ipc smoke bluetoothTimerState | py_reply 'import json,sys; print("kept" if json.load(sys.stdin)==[False] else "rejected")'; }
bt_phase() { ipc smoke readDescendant window "${1:-vgs.bluetooth}" Pairing current | py_reply 'import json,sys; print(json.load(sys.stdin)["phase"])'; }
bt_prompt() { ipc smoke readDescendant window "${2:-vgs.bluetooth}" Prompt "$1"; }
bt_field() { ipc smoke readDescendant window vgs.bluetooth TextField text; }
bt_focus() { ipc smoke focused window "${1:-vgs.bluetooth}" | py_reply 'import json,sys; r=json.load(sys.stdin); print(r[1] if isinstance(r, list) else r)'; }
# The agent child's stdin lines and end since call COUNT, and whether it
# passed the transcript's wait NAME.
bt_agent_stdin() { device_calls bluetoothctl | py_reply 'import json,sys; print(json.dumps([c["stdin"] if "stdin" in c else "EOF" for c in json.load(sys.stdin)[int(sys.argv[1]):] if isinstance(c, dict) and ("stdin" in c or "eof" in c)]))' "$1"; }
bt_waited() { device_calls bluetoothctl | py_reply 'import json,sys; print(any(isinstance(c, dict) and c.get("waited") == sys.argv[1] for c in json.load(sys.stdin)))' "$1"; }
bt_agent_holders() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["holders"].get("bluetoothAgent")))'; }
# Whether the count CMD prints has risen above BEFORE.
bt_rose() { local before="$1" now; shift; now="$("$@")" || return; [[ $now -gt $before ]] && echo rose || echo "still $now"; }
# `leaked` when hci0 reads discovering for 25 reads 0.2 s apart, as long
# as a positive poll waits, else `stopped`.
bt_stays_discovering() {
  local now
  for _ in $(seq 1 25); do
    now="$(bt_adapter Discovering)" || return
    [[ $now == True ]] || { echo stopped; return 0; }
    sleep 0.2
  done
  echo leaked
}
# `kept` when the pairing dialog's field reads TEXT for 5 reads 0.2 s
# apart, else the first other reading.
bt_field_kept() {
  local now
  for _ in $(seq 1 5); do
    now="$(bt_field)" || return
    [[ $now == "\"$1\"" ]] || { echo "$now"; return 0; }
    sleep 0.2
  done
  echo kept
}
bt_service_action() { ipc smoke readInstance window "${bt_id:-vgs.bluetooth}" serviceAction | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)))'; }
# bt_status KEY: the status value the service published under KEY.
bt_status() { ipc smoke statusValues "${bt_id:-vgs.bluetooth}" | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get(sys.argv[1])))' "$1"; }
bt_window_closed() { [[ $(window_count "System Settings") == 0 ]] && echo closed || echo open; }
# bt_status_field KEY FIELD: FIELD of the status value under KEY, as JSON.
bt_status_field() { bt_status "$1" | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps(None if v is None else v.get(sys.argv[1])))' "$2"; }
# The core's reading of service-bluetooth, and the service's, "STATE REASON".
bt_core_step() { ipc shell lent | py_reply 'import json,sys; s=json.load(sys.stdin)["system"]["steps"]["service-bluetooth"]; print(s["state"] + " " + s["reason"])'; }
bt_service_step() { bt_service stepEntry | py_reply 'import json,sys; s=json.load(sys.stdin); print(s["state"] + " " + s["reason"])'; }
# bt_load_state STATUS STDOUT REASON: plant systemctl's LoadState answer,
# probe again, and wait until the core and then the service read the step
# unknown with REASON.
bt_load_state() {
  device_reply systemctl "$1" "$2" show --property=LoadState --value bluetooth.service
  rescan "rescan to probe the LoadState for $3 answers ok"
  expect_poll "the core reads the step unknown, reason $3" "unknown $3" bt_core_step
  expect_poll "the service reads the step unknown, reason $3" "unknown $3" bt_service_step
}
# bt_followed BEFORE: whether the service value moved off BEFORE.
bt_followed() { [[ $(bt_status service) != "$1" ]] && echo followed || echo stale; }
# bt_bare_copy ID [OLD NEW]: a copy of the plugin as ID whose service lists
# no adapter, with OLD replaced by NEW in its Service.qml once.
bt_bare_copy() {
  local dir="$home/.config/vgshell/plugins/$1"
  rm -rf -- "${dir:?}"
  cp -R -- "$repo/shell/plugins/vgs.bluetooth" "$dir"
  python3 - "$dir" "$1" "${2:-}" "${3:-}" <<'PY'
import json, os, sys
root, plugin, old, new = sys.argv[1:]
path = os.path.join(root, "manifest.json")
doc = json.load(open(path))
doc["id"], doc["name"] = plugin, "Bluetooth " + plugin.rsplit("-", 1)[-1].capitalize()
json.dump(doc, open(path, "w"))
file = os.path.join(root, "Service.qml")
text = open(file).read()
edits = [("readonly property var adapters: Bluetooth.adapters.values", "readonly property var adapters: []")]
if old:
    edits.append((old, new))
for a, b in edits:
    assert text.count(a) == 1, a
    text = text.replace(a, b)
open(file, "w").write(text)
PY
}
# The transcript of an agent that registers, takes the default role, then
# prints PROMPT and runs the steps of REST, a JSON list's inside, before
# its release.
bt_transcript() { # PROMPT_OUT REST_STEPS
  device_transcript "[
  {\"out\": \"Agent registered\\n\"},
  {\"in\": $bt_default},
  {\"out\": \"Default agent request successful\\n$1\"}${2:+, $2},
  {\"in\": $bt_off},
  {\"out\": \"Agent unregistered\\n\"}
]"
}
bt_confirm_prompt='[bluetoothctl]> \r\u001b[KRequest confirmation\n[bluetoothctl]> \r\u001b[1;39m\u001b[1;39m[agent] Confirm passkey 004821 (yes/no): \u001b[0m\u001b[0m'
bt_pin_prompt='[bluetoothctl]> \r\u001b[KRequest PIN code\n[bluetoothctl]> \r\u001b[1;39m\u001b[1;39m[agent] Enter PIN code: \u001b[0m\u001b[0m'
bt_display_prompt='[bluetoothctl]> \r\u001b[K\u001b[0;91m[agent]\u001b[0m Passkey: \u001b[1;30m\u001b[1;37m246810\n\u001b[0m\u001b[0;94m[bluetoothctl]> \u001b[0m'

# The real widget's shared gear must release its animated native popup
# before the shared activation dispatch, then deliver Escape to Settings.
# WAYLAND_DEBUG records the native role destruction and keyboard enter.
# Wayland 1.26's wl_closure_print uses CLOCK_REALTIME in UTC time-of-day:
# https://github.com/wayland-mirror/wayland/blob/1.26.0/src/connection.c
# The transparent hyprctl observer uses that clock and execs unchanged argv.
# State polls use the harness interval, not a latency budget.
bt_popup_state() { ipc smoke summonWindowState panel vgs.bluetooth; }
bt_popup_field() { bt_popup_state | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get(sys.argv[1], "absent")))' "$1"; }
bt_popup_page() { ipc smoke readInstance window vgs.settings page; }
bt_popup_cursor() { hypr -j cursorpos; }
bt_popup_no_warps() { hypr -j getoption cursor:no_warps | py_reply 'import json,sys; print(json.dumps({k:v for k,v in json.load(sys.stdin).items() if k not in ("option","set")},sort_keys=True))'; }
bt_popup_released() { ipc smoke windowActivationState | py_reply 'import json,sys; d=json.load(sys.stdin); print(d["grabs"] == 0 and not d["activationWaiting"])'; }
bt_popup_pending() {
  ipc smoke windowActivationState | py_reply 'import json,sys
d=json.load(sys.stdin); print("popup-pending "+json.dumps(d,sort_keys=True),file=sys.stderr)
print(d["activationWindow"]==sys.argv[1] and d["activationWindowPresent"] and d["activationWaiting"] and d["grabs"]>0)' "$1"
}
bt_popup_trace() { # CASE START_BYTE TARGET_TITLE EXPECT_ACTIVATION
  python3 - "$shell_log" "$1" "$2" "$3" "$4" "$smoke_log_dir" "$sandbox/bt-popup-dispatch.jsonl" "$bt_popup_dispatch_start" <<'PY'
import json, pathlib, re, sys
path, case, start, title, mode, output, dispatch_file, dispatch_start = sys.argv[1:]
raw = pathlib.Path(path).read_bytes()
lines = raw.decode(errors="replace").splitlines()
start_line = len(raw[:int(start)].decode(errors="replace").splitlines())
surfaces, toplevels, titles, popups, grabbed = {}, {}, {}, {}, set()
destroyed, unmap_times, enters, keys, target_destroys = [], [], [], [], []
dispatches = [json.loads(s) for s in pathlib.Path(dispatch_file).read_text().splitlines()[int(dispatch_start):]]
kept = []
for n, line in enumerate(lines):
    match = re.search(r'get_xdg_surface\(new id xdg_surface[@#](\d+), wl_surface[@#](\d+)\)', line)
    if match:
        surfaces[match[1]] = match[2]
    match = re.search(r'xdg_surface[@#](\d+)\.get_toplevel\(new id xdg_toplevel[@#](\d+)\)', line)
    if match:
        toplevels[match[2]] = surfaces.get(match[1])
    match = re.search(r'xdg_toplevel[@#](\d+)\.set_title\("(.*)"\)', line)
    if match:
        titles[toplevels.get(match[1])] = match[2]
    match = re.search(r'xdg_surface[@#](\d+)\.get_popup\(new id xdg_popup[@#](\d+)', line)
    if match:
        popups[match[2]] = surfaces.get(match[1])
    match = re.search(r'xdg_popup[@#](\d+)\.grab\(', line)
    if match:
        grabbed.add(match[1])
    if n < start_line:
        continue
    match = re.search(r'xdg_toplevel[@#](\d+)\.destroy\(\)', line)
    if match and titles.get(toplevels.get(match[1])) == title:
        target_destroys.append(n)
    if any(word in line for word in ("xdg_popup", "wl_keyboard")):
        kept.append(f"{n + 1}: {line}")
    match = re.search(r'xdg_popup[@#](\d+)\.destroy\(\)', line)
    if match and match[1] in popups and match[1] in grabbed:
        destroyed.append(n)
        stamp = re.search(r'\[(\d\d):(\d\d):(\d\d)\.(\d{6})\]', line)
        if stamp:
            h, m, s, us = map(int, stamp.groups())
            unmap_times.append(((h * 60 + m) * 60 + s) * 1000000 + us)
    match = re.search(r'wl_keyboard[@#]\d+\.enter\(\d+, wl_surface[@#](\d+),', line)
    if match:
        enters.append((n, titles.get(match[1], "non-target"), match[1]))
    if re.search(r'wl_keyboard[@#]\d+\.key\(\d+, \d+, \d+, 1\)', line):
        keys.append(n)
target_enters = [n for n, actual, _ in enters if actual == title]
problems = []
if len(destroyed) != 1:
    problems.append("popup-destroy-count=" + str(len(destroyed)))
if case == "far" and target_destroys:
    problems.append("existing-target-remapped")
if mode == "activate":
    if len(dispatches) != 1:
        problems.append("activation-dispatch-count=" + str(len(dispatches)))
    if len(unmap_times) != 1:
        problems.append("native-unmap-clock-unreadable")
    elif dispatches and not 0 < (dispatches[0]["wallUs"] % 86400000000 - unmap_times[0]) % 86400000000 < 43200000000:
        problems.append("activation-before-native-unmap")
    if not target_enters or not destroyed or not any(n > destroyed[0] for n in target_enters):
        problems.append("no-post-unmap-native-target-enter")
    if not keys or not target_enters or not any(n > target_enters[-1] for n in keys):
        problems.append("no-native-key-after-target-enter")
else:
    if dispatches:
        problems.append("cancelled-target-dispatched")
receipt = dict(case=case, title=title, startByte=int(start), nativeUnmap=destroyed,
               nativeUnmapUtcDayUs=unmap_times, activationDispatch=dispatches, keyboardEnters=enters, nativeKeyPresses=keys,
               targetNativeDestructions=target_destroys,
               problems=problems, verdict="fail" if problems else "pass")
out = pathlib.Path(output)
(out / ("popup-" + case + ".native.log")).write_text("\n".join(kept) + "\n")
(out / ("popup-" + case + ".json")).write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps(receipt, sort_keys=True))
sys.exit(bool(problems))
PY
}
bt_popup_gear() {
  local x y box clients
  box="$(ipc smoke labelledGeometry panel vgs.bluetooth IconButton Settings)" || return 1
  read -r x y < <(py_reply 'import json,sys; b=json.load(sys.stdin); print(round(b[0]+b[2]/2),round(b[1]+b[3]/2))' <<<"$box") || return 1
  [[ $x =~ ^[0-9]+$ && $y =~ ^[0-9]+$ ]] || return 1
  clients="$(hypr -j clients)" || return 1
  expect "popup: the independent client lies beneath the gear pointer" True py_reply 'import json,sys
cs=[c for c in json.load(sys.stdin) if c["pid"]==int(sys.argv[1]) and c["mapped"]]
x,y=map(int,sys.argv[2:])
print(len(cs)==1 and cs[0]["at"][0]<=x<cs[0]["at"][0]+cs[0]["size"][0] and cs[0]["at"][1]<=y<cs[0]["at"][1]+cs[0]["size"][1])' "$other_pid" "$x" "$y" <<<"$clients" || return 1
  click "$x" "$y"
}
bt_popup_open() {
  click_centre "bar:$screen_name" vgs.bluetooth || return 1
  expect_poll "popup: the actual Bluetooth widget maps its popup" true bt_popup_field backingWindowVisible || return 1
  expect_poll "popup: the flyout finishes opening with motion enabled" 1 bt_popup_field motionProgress
}
bt_popup_case() { # CASE new|existing|far|latest|hide|destroy
  local name="$1" kind="$2" start pointer pointer_after no_warps no_warps_after address effect=0 trace=0 before="$failures"
  expect "popup $name: close any old target" ok ipc shell hide window vgs.settings || return 1
  expect_poll "popup $name: old Settings is destroyed" 0 window_count Plugins || return 1
  if [[ $kind != new ]]; then
    expect "popup $name: map Settings before the opener" ok ipc shell summon window vgs.settings '{"plugin":"vgs.bluetooth"}' || return 1
    expect_poll "popup $name: existing Settings maps" 1 window_count Plugins || return 1
    expect_poll "popup $name: existing activation finishes" True bt_popup_released || return 1
    if [[ $kind == far ]]; then
      address="$(window_address Plugins)" || return 1
      expect "popup $name: move existing Settings to B" ok hypr dispatch "hl.dsp.window.move({ monitor = \"SMOKE-BT-POPUP\", window = \"address:$address\", follow = false })" || return 1
      expect_poll "popup $name: Settings is on output B" '"SMOKE-BT-POPUP"' bt_popup_monitor || return 1
    fi
  fi
  expect "popup $name: focus output A before opening" ok hypr dispatch "hl.dsp.focus({ monitor = \"$screen_name\" })" || return 1
  bt_popup_open || return 1
  start="$(stat -c %s -- "$shell_log")" || return 1
  bt_popup_dispatch_start="$(wc -l <"$sandbox/bt-popup-dispatch.jsonl")" || return 1
  no_warps="$(bt_popup_no_warps)" || return 1
  bt_popup_gear || return 1
  pointer="$(bt_popup_cursor)" || return 1
  expect_poll "popup $name: the gear selects the real Bluetooth Settings page" '"vgs.bluetooth"' bt_popup_page || return 1
  expect "popup $name: close motion still owns the native grab" true bt_popup_field closing || return 1
  if [[ $kind == latest || $kind == hide || $kind == destroy ]]; then
    # Read the actual shared completion before replacing or destroying its
    # target; no copied activation model keeps a fixture target alive.
    expect "popup $name: the actual target waits for native release" True bt_popup_pending Plugins || return 1
    case "$kind" in
      latest)
        expect "popup latest: replace the pending Settings target" ok ipc shell summon window vgs.system '{}' || return 1
        expect_poll "popup latest: only the replacement owns the actual wait" True bt_popup_pending "System Settings" || return 1 ;;
      hide|destroy)
        # Host hide destroys this summoned AppWindow. The observer separately
        # proves Qt cleared the actual typed reference, not just its client.
        expect "popup $name: destroy the pending target through its real host" ok ipc shell hide window vgs.settings || return 1
        expect_poll "popup $name: the actual typed reference clears" false bt_popup_activation_target || return 1 ;;
    esac
  fi
  expect_poll "popup $name: the animated source instance closes" absent ipc smoke readInstance panel vgs.bluetooth title || return 1
  expect_poll "popup $name: shared release wait finishes" True bt_popup_released || return 1
  pointer_after="$(bt_popup_cursor)" || return 1
  no_warps_after="$(bt_popup_no_warps)" || return 1
  expect "popup $name: the opener pointer has not moved" "$pointer" printf '%s' "$pointer_after" || return 1
  expect "popup $name: the effective no_warps option is restored" "$no_warps" printf '%s' "$no_warps_after" || return 1
  printf 'popup-preservation case=%s pointer-before=%s pointer-after=%s no-warps-before=%s no-warps-after=%s\n' "$name" "$pointer" "$pointer_after" "$no_warps" "$no_warps_after"
  if [[ $kind == far ]]; then
    expect "popup far: Settings keeps its original native address" "$address" window_address Plugins || return 1
    expect "popup far: Settings remains on output B after the gear" '"SMOKE-BT-POPUP"' bt_popup_monitor || return 1
  fi
  case "$kind" in
    latest)
      expect_poll "popup latest: wait for target activation before typing" true window_keyboard vgs.system
      type_keys popup-latest || return 1
      expect_poll "popup latest: native typing changes the System search" '"popup-latest"' ipc smoke readDescendant window vgs.system Sidebar query || effect=$?
      bt_popup_trace "$name" "$start" "System Settings" activate || trace=$?
      expect "popup latest: close System" ok ipc shell hide window vgs.system || return 1
      [[ $effect == 0 && $trace == 0 ]] || return 1 ;;
    hide|destroy)
      bt_popup_trace "$name" "$start" Plugins cancel || return 1 ;;
    *)
      # Escape pops this actual Settings page to the plugin list. Neither
      # activewindow identity nor a Qt focus property can cause that effect.
      expect_poll "popup $name: wait for target activation before typing" true window_keyboard vgs.settings
      type_keys -k Escape || return 1
      expect_poll "popup $name: native Escape returns Settings to its list" '""' bt_popup_page || effect=$?
      bt_popup_trace "$name" "$start" Plugins activate || trace=$?
      [[ $effect == 0 && $trace == 0 ]] || return 1 ;;
  esac
  [[ $failures == "$before" ]]
}
bt_popup_monitor() {
  hypr --batch 'j/clients;j/monitors' | py_reply 'import json,sys
s=sys.stdin.read(); d=json.JSONDecoder(); cs,n=d.raw_decode(s); ms=json.loads(s[n:])
c=next(c for c in cs if c["title"]=="Plugins" and c["mapped"])
print(json.dumps(next(m["name"] for m in ms if m["id"]==c["monitor"])))'
}
bt_popup_activation_target() { ipc smoke windowActivationState | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["activationWindowPresent"]))'; }
bt_popup_motion() {
  local theme="$home/.config/vgshell/theme.json"
  printf '%s\n' '{"schemaVersion":1,"name":"popup-native","tokens":{"motion":{"flyout":{"travel":{"duration":2000}}}}}' >"$theme.next"
  mv -T -- "$theme.next" "$theme"
  expect_poll "popup: normal motion remains enabled" 2000 ipc smoke themeValue motion.flyout.travel.duration
}
bt_popup_native() {
  local before="$failures" theme="$home/.config/vgshell/theme.json" had_theme=false
  cp -- "$home/.config/vgshell/shell.json" "$sandbox/bt-popup-config.json"
  if [[ -f $theme ]]; then cp -- "$theme" "$sandbox/bt-popup-theme.json"; had_theme=true; fi
  # Slow only the normal flyout animation so IPC can acknowledge a pending
  # target before release. This is not a sleep or a copied activation model.
  stop_shell
  cp -- "$shim/hyprctl" "$sandbox/bt-popup-hyprctl"
  : >"$sandbox/bt-popup-dispatch.jsonl"
  python3 - "$shim/hyprctl" "$shim/hyprctl.real" "$sandbox/bt-popup-dispatch.jsonl" <<'PY'
import pathlib, sys
path, real, log = sys.argv[1:]
pathlib.Path(path).write_text("""#!/usr/bin/python3
import json, os, sys, time
real = %r
log = %r
if any("alter_zorder" in a or "alterzorder top,address:" in a for a in sys.argv[1:]):
    with open(log, "a") as out:
        out.write(json.dumps(dict(wallUs=time.time_ns()//1000, argv=sys.argv[1:]))+"\\n")
os.execv(real, [real]+sys.argv[1:])
""" % (real, log))
PY
  chmod 755 "$shim/hyprctl"
  start_shell "$repo" "$sandbox/bt-popup-native.log" bar WAYLAND_DEBUG=client || return 1
  bt_popup_motion
  expect "popup: System is enabled for latest-target replacement" ok ipc shell setPluginEnabled vgs.system true
  open_other "$sandbox/bt-popup-other.log" || return 1
  local underneath
  underneath="$(other_address)" || return 1
  expect "popup: float the independent client under the opener" ok hypr dispatch "hl.dsp.window.float({ action = \"enable\", window = \"address:$underneath\" })"
  expect "popup: size the independent client across output A" ok hypr dispatch "hl.dsp.window.resize({ x = $mon_w, y = $((mon_h - bar_reserved)), relative = false, window = \"address:$underneath\" })"
  expect "popup: place the independent client below the bar" ok hypr dispatch "hl.dsp.window.move({ x = 0, y = $bar_reserved, relative = false, window = \"address:$underneath\" })"
  # Placement is read before each action, not assumed from activewindow.
  expect "popup: add output B" ok create_output SMOKE-BT-POPUP
  expect_poll "popup: output B receives a bar" "$((monitors + 1))" bar_count
  local scenario
  for scenario in far new existing latest destroy; do
    coordinate_observation "popup $scenario" bt_popup_case "$scenario" "$scenario"
  done
  # Keep the actual operation and native assertions. Only remove the new
  # release condition; live-target, visibility and epoch guards remain.
  copy_tree bt-popup-release
  edit_tree bt-popup-release shell/Core/Compositor.qml \
    ' && OverlayState.grabs === 0;' ';'
  cp -- "$shell_log" "$smoke_log_dir/popup-positive.raw.log"
  stop_shell
  start_shell "$sandbox/tree-bt-popup-release" "$sandbox/bt-popup-release.log" bar WAYLAND_DEBUG=client || return 1
  bt_popup_motion
  local control_status=0
  if (
    failures=0 behaviour_failures=0
    status=0
    bt_popup_case release-control existing || status=$?
    printf 'popup-control raw-exit=%s failures=%s\n' "$status" "$failures"
    exit "$status"
  ) >"$smoke_log_dir/popup-release-control.log" 2>&1; then
    control_status=0
  else
    control_status=$?
  fi
  printf '%s\n' "$control_status" >"$smoke_log_dir/popup-release-control.exit"
  cat -- "$smoke_log_dir/popup-release-control.log"
  cp -- "$shell_log" "$smoke_log_dir/popup-control.raw.log"
  cp -- "$sandbox/bt-popup-dispatch.jsonl" "$smoke_log_dir/popup-dispatch.raw.jsonl"
  cp -- "$other_log" "$smoke_log_dir/popup-other.raw.log"
  expect "popup control: the unguarded workload exits nonzero" 1 printf '%s' "$control_status"
  expect "popup control: the exact native ordering assertion detects early activation" True \
    py_reply 'import json,sys; print("activation-before-native-unmap" in json.load(sys.stdin)["problems"])' \
    <"$smoke_log_dir/popup-release-control.json"
  expect "popup: close Settings after native checks" ok ipc shell hide window vgs.settings
  if create_output_remove SMOKE-BT-POPUP; then
    ok "popup: remove output B"
  else
    fail "popup: remove output B"
  fi
  close_other "popup: the owned client below the opener exits"
  stop_shell
  cp -- "$sandbox/bt-popup-hyprctl" "$shim/hyprctl"
  if [[ $had_theme == true ]]; then cp -- "$sandbox/bt-popup-theme.json" "$theme.next"; mv -T -- "$theme.next" "$theme"; else rm -f -- "$theme"; fi
  user_config_restore "$sandbox/bt-popup-config.json" || return 1
  start_shell "$repo" "$sandbox/bt-popup-restored.log" || return 1
  [[ $failures == "$before" ]]
}

bt_main() {
  devices_ready bluetooth || return 0
  # The core probes the system steps once vgs.bluetooth holds `system`,
  # and the fakes' tree keeps that probe off the host's /sys, /dev and
  # systemd.
  local bt_tree
  bt_tree="$(devices_system_tree)" || { fail "bluetooth: the fakes' system tree: $bt_tree"; return 0; }
  device_reply systemctl 0 "" is-active --quiet bluetooth.service
  bluez_follow auto
  bluez discovery confirm >/dev/null
  bt_was_system="$(plugin_enabled vgs.system)" || { fail "bluetooth: vgs.system's enabled state is unreadable"; return 0; }
  bt_was_bluetooth="$(plugin_enabled vgs.bluetooth)" || { fail "bluetooth: vgs.bluetooth's enabled state is unreadable"; bt_was_bluetooth=""; return 0; }
  bt_powered_sets >/dev/null || { fail "bluetooth: the BlueZ mock's log is unreadable"; return 0; }

  expect "enabling vgs.bluetooth is allowed" ok ipc shell setPluginEnabled vgs.bluetooth true
  expect_poll "the Bluetooth service is built" True record_exists vgs.bluetooth
  expect_poll "the service reads rfkill unblocked and hci0 powered: on" on bt_view
  expect_poll "the widget shows on with the connected headphones" '"bluetooth-connected"' bt_widget_view icon
  bt_popup_native || {
    row_class=operation fail "bluetooth: native popup proof failed status=$?"
    return 0
  }

  # Off: the soft block is the state, and BlueZ follows it.
  local rfkill_before
  rfkill_before="$(bt_count rfkill)" || { fail "bluetooth: the rfkill stand-in's calls are unreadable"; return 0; }
  expect "Off answers ok" ok ipc vgs.bluetooth invoke power off
  expect_poll "Off writes the soft block" '[["blocked", "unblocked"]]' bt_radio
  expect_poll "the adapter follows the block down" "False off-blocked" bt_adapter Powered PowerState
  expect_poll "the service reads off" off bt_view
  expect_poll "the widget shows off" '"bluetooth-off"' bt_widget_view icon
  expect "Off ran rfkill block bluetooth and reads" '[["-J"], ["block", "bluetooth"]]' bt_rfkill_argvs_since "$rfkill_before"
  expect "disabling vgs.bluetooth to restart its service is allowed" ok ipc shell setPluginEnabled vgs.bluetooth false
  expect_poll "the service is gone" False record_exists vgs.bluetooth
  rfkill_before="$(bt_count rfkill)" || { fail "bluetooth: the rfkill stand-in's calls are unreadable"; return 0; }
  expect "enabling vgs.bluetooth again is allowed" ok ipc shell setPluginEnabled vgs.bluetooth true
  expect_poll "the restarted service reads off" off bt_view
  expect "the block survives the restart" '[["blocked", "unblocked"]]' bt_radio
  expect "the restarted service only read rfkill" '[["-J"]]' bt_rfkill_argvs_since "$rfkill_before"
  expect "the off flyout opens with the shared header switch" ok ipc shell summon panel vgs.bluetooth '{}'
  expect_poll "the shared Bluetooth header switch reads off and sits in the title row" '{"checked": false, "enabled": true, "placed": true}' bt_panel_header
  expect "the old Bluetooth PowerField row is absent from the flyout" absent bt_power_field_absent
  expect "the off flyout closes" ok ipc shell hide panel vgs.bluetooth

  # On: unblock, then wait for an adapter to report powered; the auto
  # power-on comes, so the service sets nothing.
  local sets_before
  sets_before="$(bt_powered_sets)" || { fail "bluetooth: the BlueZ mock's log is unreadable"; return 0; }
  expect "On answers ok" ok ipc vgs.bluetooth invoke power on
  expect_poll "On unblocks" '[["unblocked", "unblocked"]]' bt_radio
  expect_poll "the service reads on once the adapter reports powered" on bt_view
  expect "the auto power-on left Powered to BlueZ" "$sets_before" bt_powered_sets

  # On with no auto power-on: after its wait the service sets Powered,
  # which BlueZ's PowerState, left off by the unblock, does not follow.
  bluez_follow manual
  expect "Off for the fallback answers ok" ok ipc vgs.bluetooth invoke power off
  expect_poll "the service reads off before the fallback" off bt_view
  expect "On for the fallback answers ok" ok ipc vgs.bluetooth invoke power on
  expect_poll "the service turns on through the fallback" on bt_view
  expect "the fallback set Powered once" "$((sets_before + 1))" bt_powered_sets
  expect "the unblock moved PowerState no further than off, so Powered came from the fallback" "True off" bt_adapter Powered PowerState
  bluez update "$bluez_adapter_path" org.bluez.Adapter1 '{"PowerState": "on"}' >/dev/null
  bluez_follow auto

  # A hard block: the hardware switch state, no switch, On refused and
  # no rfkill write.
  rfkill_before="$(bt_count rfkill)" || { fail "bluetooth: the rfkill stand-in's calls are unreadable"; return 0; }
  rfkill_hard bluetooth blocked
  expect_poll "a hard block shows the hardware-switch state" hard-blocked bt_view
  expect "the hard block's line" "Turned off by a hardware switch" bt_view text
  expect "the hard block offers no switch" False bt_view canToggle
  expected_errors+=('bluetooth: refused: power=on reason=hard-blocked')
  expect "On is refused under a hard block" "refused: power=on reason=hard-blocked" ipc vgs.bluetooth invoke power on
  expect "the refusal ran no rfkill write" '[["-J"]]' bt_rfkill_argvs_since "$rfkill_before"
  rfkill_hard bluetooth unblocked
  expect_poll "lifting the hardware switch reads on" on bt_view

  # Discovery: the flyout's lease starts it; BlueZ confirms only after the
  # flyout closed, and the debt still stops it.
  local starts_before stops_before
  bluez discovery hold >/dev/null
  starts_before="$(bt_calls StartDiscovery)"
  stops_before="$(bt_calls StopDiscovery)"
  expect "the flyout opens" ok ipc shell summon panel vgs.bluetooth '{}'
  expect_poll "the flyout's lease starts discovery" rose bt_rose "$starts_before" bt_calls StartDiscovery
  expect_poll "the shared Bluetooth header switch reads on and sits beside the gear" '{"checked": true, "enabled": true, "placed": true}' bt_panel_header
  expect "the old Bluetooth PowerField row stays absent from the flyout" absent bt_power_field_absent
  expect_poll "the flyout lists the headphones as connected" '[["Smoke Headphones", true]]' bt_lists panel vgs.bluetooth
  expect "BlueZ has not confirmed the start" False bt_adapter Discovering
  expect "the flyout closes" ok ipc shell hide panel vgs.bluetooth
  expect_poll "the flyout's teardown ended its lease" '[]' bt_leases
  expect "BlueZ confirms the start after the last release" updated bluez update "$bluez_adapter_path" org.bluez.Adapter1 '{"Discovering": true}'
  expect_poll "a start confirmed after the last release is still stopped" False bt_adapter Discovering
  expect "the service wrote the stop" rose bt_rose "$stops_before" bt_calls StopDiscovery
  bluez discovery confirm >/dev/null

  # Pairing through the System window's section. Each device is held: its
  # Pair answers at once and pairs nothing, and the transcript pairs it
  # once the agent's answer is in.
  local dev agent_before
  for dev in "$bt_keyboard Smoke Keyboard" "$bt_mouse Smoke Mouse" "$bt_speaker Smoke Speaker" "$bt_pad Smoke Pad"; do
    expect "a nearby ${dev#* } joins the mock" "$(bt_path "${dev%% *}")" bluez add-device "${dev%% *}" "${dev#* }" held
  done
  expect "enabling the System window is allowed" ok ipc shell setPluginEnabled vgs.system true

  # A confirm prompt, answered yes with Return.
  bt_transcript "$bt_confirm_prompt" "{\"in\": \"yes\"}, {\"pair\": \"$bt_keyboard\"}, {\"out\": \"yes\\n\"}"
  agent_before="$(bt_count bluetoothctl)" || { fail "bluetooth: the bluetoothctl stand-in's calls are unreadable"; return 0; }
  rest_pointer || fail "moving the pointer off the System window failed"
  expect "a deep link pairs the keyboard in the Bluetooth section" ok ipc shell summon window vgs.system "{\"pane\":\"vgs.bluetooth\",\"pair\":\"$bt_keyboard\"}"
  expect_poll "the section mounts" '["vgs.bluetooth"]' window_panes
  expect_poll "the agent's confirm prompt shows in the Dialog" '"confirm"' bt_prompt kind
  expect "the prompt names the device it pairs" '"Smoke Keyboard"' bt_prompt deviceName
  expect_poll "the section called Pair on the keyboard once" 1 bt_calls Pair "$(bt_path "$bt_keyboard")"
  expect_poll "the Dialog's Pair action holds the keyboard" Pair bt_focus
  type_keys -k Return || fail "typing Return on the confirm prompt failed"
  expect_poll "the pairing ends done" done bt_phase
  expect_poll "Return answered yes, and the pairing released the agent's lease" "[$bt_default, \"yes\", $bt_off, \"EOF\"]" bt_agent_stdin "$agent_before"
  expect_poll "the paired keyboard is trusted and connected" "True True True" bt_device "$bt_keyboard" Paired Trusted Connected
  expect "the prompt is gone" '""' bt_prompt kind

  # A code to type on the device, dismissed once it pairs.
  bt_transcript "$bt_display_prompt" "{\"wait\": \"bt-display-seen\"}, {\"pair\": \"$bt_mouse\"}"
  agent_before="$(bt_count bluetoothctl)" || { fail "bluetooth: the bluetoothctl stand-in's calls are unreadable"; return 0; }
  expect "a deep link pairs the mouse" ok ipc shell summon window vgs.system "{\"pane\":\"vgs.bluetooth\",\"pair\":\"$bt_mouse\"}"
  expect_poll "the Dialog shows the code to type" '"passkey-display"' bt_prompt kind
  expect "the Dialog carries the code" '"246810"' python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["code"]))' "$(bt_prompt request)"
  expect_poll "the section called Pair on the mouse once" 1 bt_calls Pair "$(bt_path "$bt_mouse")"
  : >"$devices_dir/bt-display-seen"
  expect_poll "the second pairing ends done" done bt_phase
  expect_poll "the code is dismissed once paired" '""' bt_prompt kind
  expect_poll "the second pairing releases the agent's lease" "[$bt_default, $bt_off, \"EOF\"]" bt_agent_stdin "$agent_before"
  expect_poll "the paired mouse is trusted and connected" "True True True" bt_device "$bt_mouse" Paired Trusted Connected

  # A PIN typed into the dialog survives a line bluetoothctl prints while
  # the prompt is open, and Return sends it.
  bt_transcript "$bt_pin_prompt" "{\"wait\": \"bt-pin-typed\"}, {\"out\": \"\\r\\u001b[K[CHG] Device $bt_speaker RSSI: -60\\n\\r\\u001b[1;39m\\u001b[1;39m[agent] Enter PIN code: \\u001b[0m\\u001b[0m\"}, {\"in\": \"0000\"}, {\"pair\": \"$bt_speaker\"}, {\"out\": \"0000\\n\"}"
  agent_before="$(bt_count bluetoothctl)" || { fail "bluetooth: the bluetoothctl stand-in's calls are unreadable"; return 0; }
  expect "a deep link pairs the speaker" ok ipc shell summon window vgs.system "{\"pane\":\"vgs.bluetooth\",\"pair\":\"$bt_speaker\"}"
  expect_poll "the Dialog asks for the PIN" '"pin"' bt_prompt kind
  expect_poll "the PIN field holds the keyboard" PIN bt_focus
  type_keys 0000 || fail "typing the PIN failed"
  expect_poll "the PIN field reads what was typed" '"0000"' bt_field
  : >"$devices_dir/bt-pin-typed"
  expect_poll "bluetoothctl printed a line while the PIN prompt is open" True bt_waited bt-pin-typed
  expect "the typed PIN survives the line" kept bt_field_kept 0000
  expect_poll "the section called Pair on the speaker once" 1 bt_calls Pair "$(bt_path "$bt_speaker")"
  type_keys -k Return || fail "typing Return on the PIN prompt failed"
  expect_poll "Return sends the PIN, and the pairing releases the agent's lease" "[$bt_default, \"0000\", $bt_off, \"EOF\"]" bt_agent_stdin "$agent_before"
  expect_poll "the third pairing ends done" done bt_phase
  device_transcript -

  # Connect and disconnect by pointer.
  expect_poll "My Devices lists the four devices" '[["Smoke Headphones", true], ["Smoke Keyboard", true], ["Smoke Mouse", true], ["Smoke Speaker", true]]' bt_mine
  click_in "window:System Settings" window vgs.bluetooth RowAction Disconnect || fail "the click on Disconnect failed"
  expect_poll "Disconnect disconnects the first device" "False" bt_device "$bt_headphones" Connected
  click_in "window:System Settings" window vgs.bluetooth RowAction Connect || fail "the click on Connect failed"
  expect_poll "Connect connects it again" "True" bt_device "$bt_headphones" Connected
  click_in "window:System Settings" window vgs.bluetooth RowAction Disconnect || fail "the click on Disconnect before a failed connect failed"
  expect_poll "Disconnect leaves the headphones not connected before the failed connect" "False" bt_device "$bt_headphones" Connected
  expect "the headphones' Connect fails as an unanswering speaker's does" installed bt_connect_answer "$bt_headphones" fail
  expected_errors+=('Failed to connect to device .*br-connection-page-timeout')
  click_in "window:System Settings" window vgs.bluetooth RowAction Connect || fail "the click on the failing Connect failed"
  expect_poll "Connect shows the working state at once" '"Connecting…"' bt_secondary "$bt_headphones"
  expect_poll "Connect shows the busy spinner at once" True bt_busy_spinner "Smoke Headphones"
  expect_poll "a connect BlueZ fails reads Not connected" '"Not connected"' bt_secondary "$bt_headphones"
  expect_poll "and one plain sentence names the device" '["Smoke Headphones did not answer. Check that it is on, nearby and not connected to another device."]' bt_failures
  expect "the headphones' Connect accepts again" installed bt_connect_answer "$bt_headphones" accept
  click_in "window:System Settings" window vgs.bluetooth RowAction Retry || fail "the click on Retry failed"
  expect_poll "Retry connects the headphones again" "True" bt_device "$bt_headphones" Connected
  expect_poll "Retry reads Connected in the row" '"Connected"' bt_secondary "$bt_headphones"
  expect_poll "Retry clears the failure sentence" '[]' bt_failures
  expect "hiding the System window after pairing is allowed" ok ipc shell hide window vgs.system
  expect_poll "the System window is closed after pairing" closed bt_window_closed

  # Controls: one copy whose discovery tick writes no stop, a plain lease
  # counter, and whose pairing never calls Pair.
  local mutant_dir="$home/.config/vgshell/plugins/acme.bluetooth-mutant"
  rm -rf -- "${mutant_dir:?}"
  cp -R -- "$repo/shell/plugins/vgs.bluetooth" "$mutant_dir"
  python3 - "$mutant_dir" <<'PY'
import json, os, sys
root = sys.argv[1]
path = os.path.join(root, "manifest.json")
doc = json.load(open(path))
doc["id"], doc["name"] = "acme.bluetooth-mutant", "Bluetooth Mutant"
json.dump(doc, open(path, "w"))
for name, old, new in (
    ("BluetoothLogic.js", 'return { state: withState(state, { attempts: state.attempts + 1 }), effects: ["stop"] };', "return { state: state, effects: [] };"),
    ("Pairing.qml", "if (target !== null) target.pair();", "if (target !== null) {}"),
):
    file = os.path.join(root, name)
    text = open(file).read()
    assert text.count(old) == 1, old
    open(file, "w").write(text.replace(old, new))
PY
  expect "disabling vgs.bluetooth for the controls is allowed" ok ipc shell setPluginEnabled vgs.bluetooth false
  rescan "rescan after adding the mutant copy answers ok"
  expect_poll "the mutant copy lands enabled, as a new bar widget does" True plugin_enabled acme.bluetooth-mutant
  bt_id=acme.bluetooth-mutant
  expect_poll "the mutant copy's service reads on" on bt_view
  bluez discovery hold >/dev/null
  starts_before="$(bt_calls StartDiscovery)"
  expect "the mutant copy's flyout opens" ok ipc shell summon panel acme.bluetooth-mutant '{}'
  expect_poll "control: the counter's lease starts discovery" rose bt_rose "$starts_before" bt_calls StartDiscovery
  expect "the mutant copy's flyout closes" ok ipc shell hide panel acme.bluetooth-mutant
  expect_poll "control: the counter's lease ended" '[]' bt_leases
  expect "control: BlueZ confirms the start after the last release" updated bluez update "$bluez_adapter_path" org.bluez.Adapter1 '{"Discovering": true}'
  expect "control: a plain lease counter leaks the late start" leaked bt_stays_discovering
  bluez update "$bluez_adapter_path" org.bluez.Adapter1 '{"Discovering": false}' >/dev/null
  bluez discovery confirm >/dev/null
  bt_transcript "$bt_confirm_prompt" "{\"in\": \"yes\"}, {\"pair\": \"$bt_pad\"}, {\"out\": \"yes\\n\"}"
  expect "the mutant copy's section pairs the pad" ok ipc shell summon window vgs.system "{\"pane\":\"acme.bluetooth-mutant\",\"pair\":\"$bt_pad\"}"
  expect_poll "control: the copy's confirm prompt shows" '"confirm"' bt_prompt kind acme.bluetooth-mutant
  expect_poll "control: the copy's Dialog holds the keyboard" Pair bt_focus acme.bluetooth-mutant
  type_keys -k Return || fail "typing Return on the copy's confirm prompt failed"
  expect_poll "control: the copy's pairing ends done" done bt_phase acme.bluetooth-mutant
  expect "control: a section that never calls Pair leaves the mock's Pair count at 0" 0 bt_calls Pair "$(bt_path "$bt_pad")"
  device_transcript -
  expect "hiding the System window after the controls is allowed" ok ipc shell hide window vgs.system
  expect_poll "the System window is closed after the controls" closed bt_window_closed
  unset bt_id
  expect "disabling the mutant copy is allowed" ok ipc shell setPluginEnabled acme.bluetooth-mutant false
  rm -rf -- "${mutant_dir:?}"
  rescan "rescan after removing the mutant copy answers ok"
  expect_poll "the mutant copy is gone" absent plugin_enabled acme.bluetooth-mutant

  # The stopped service: a copy whose service lists no adapter, over a
  # bluetooth.service that is loaded and not running. Its section offers
  # the step, and the click runs it through status.act.
  local bare_dir="$home/.config/vgshell/plugins/acme.bluetooth-bare"
  bt_bare_copy acme.bluetooth-bare
  device_reply systemctl 3 "" is-active --quiet bluetooth.service
  device_reply systemctl 0 loaded show --property=LoadState --value bluetooth.service
  terminal_stand_in
  terminal_ready "bluetooth"
  rescan "rescan after adding the bare copy answers ok"
  expect_poll "the bare copy lands enabled, as a new bar widget does" True plugin_enabled acme.bluetooth-bare
  bt_id=acme.bluetooth-bare
  expect_poll "with no adapter and the service stopped, the service reads service-needed" service-needed bt_view
  expect "the stopped service's line" "The Bluetooth service is off." bt_view text
  expect_poll "the power reading publishes no action" '{"tone": "warning", "text": "The Bluetooth service is off."}' bt_status power
  expect_poll "the service setup step is open and offers its action" '{"tone": "warning", "text": "Off", "action": true}' bt_status service
  expect "the bare copy's section summons" ok ipc shell summon window vgs.system '{"pane":"acme.bluetooth-bare"}'
  expect_poll "the bare copy's section mounts" '["acme.bluetooth-bare"]' window_panes
  expect_poll "the section offers the service status row's action" '{"label": "Turn on the service"}' bt_service_action
  forget_record
  expect "no terminal is asked for before the click" absent recorded
  click_in "window:System Settings" window acme.bluetooth-bare RowAction "Turn on the service" || fail "the click on Turn on the service failed"
  expect_poll "Turn on the service hands the terminal vgshell system apply service-bluetooth" \
    "$(core_words core/system "System setup" org.vgs.tui system apply service-bluetooth)" recorded
  expect_run_end "the Turn on the service core/system run ends" core/system
  forget_record
  expect "hiding the System window after the stopped service is allowed" ok ipc shell hide window vgs.system
  expect_poll "the System window is closed after the stopped service" closed bt_window_closed

  # The reason alone: the step reads unknown twice, and only its reason
  # changes, so only the service's republish on its step's report moves
  # the published value.
  local bt_before
  bt_load_state 1 "" systemctl-failed
  expect_poll "a LoadState systemctl cannot read reads the step not available" false bt_status_field service available
  bt_before="$(bt_status service)"
  bt_load_state 0 bad-setting load-state
  expect "the published service value follows the reason alone" followed bt_followed "$bt_before"
  expect "a LoadState systemd cannot load reads the step not available" false bt_status_field service available
  unset bt_id
  expect "disabling the bare copy is allowed" ok ipc shell setPluginEnabled acme.bluetooth-bare false
  rm -rf -- "${bare_dir:?}"
  # The control: a copy with no republish on its step's report keeps the
  # value it published when only the reason changes.
  local stale_dir="$home/.config/vgshell/plugins/acme.bluetooth-stale"
  bt_bare_copy acme.bluetooth-stale "    onStepEntryChanged: publish()
" ""
  rescan "rescan after adding the stale control copy answers ok"
  expect_poll "the stale control copy lands enabled" True plugin_enabled acme.bluetooth-stale
  bt_id=acme.bluetooth-stale
  expect_poll "the stale control reads the step unknown, reason load-state" "unknown load-state" bt_service_step
  bt_before="$(bt_status service)"
  bt_load_state 1 "" systemctl-failed
  expect "control: a service with no republish on its step's report keeps the old value" stale bt_followed "$bt_before"
  unset bt_id
  expect "disabling the stale control copy is allowed" ok ipc shell setPluginEnabled acme.bluetooth-stale false
  rm -rf -- "${stale_dir:?}"
  device_reply_clear systemctl
  device_reply systemctl 0 "" is-active --quiet bluetooth.service
  rescan "rescan after removing the bare copy answers ok"
  expect_poll "the bare copy is gone" absent plugin_enabled acme.bluetooth-bare
  expect_poll "the stale control copy is gone" absent plugin_enabled acme.bluetooth-stale

  expect "enabling vgs.bluetooth after the controls is allowed" ok ipc shell setPluginEnabled vgs.bluetooth true
  expect_poll "vgs.bluetooth reads on again" on bt_view

  # Keyboard alone: SUPER+COMMA, the search, the section, its switches and
  # its devices, then out.
  hypr_lua_save bluetooth
  printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$home/.config/hypr/hyprland.lua"
  expect "the nested instance reloads with binds resolved by keysym" ok hypr reload config-only
  rest_pointer || fail "moving the pointer off the System window failed"
  type_keys -M logo -k comma -m logo || fail "typing SUPER+COMMA failed"
  expect_poll "SUPER+COMMA opens the System window" 1 window_count "System Settings"
  expect_poll "the keyboard starts in the search field" "Search sections" bt_focus vgs.system
  type_keys bluetooth || fail "typing the search failed"
  type_keys -k Return || fail "typing Return in the search failed"
  expect_poll "Return enters the Bluetooth section on its power switch" Bluetooth bt_focus
  type_keys -k space || fail "typing Space on the power switch failed"
  expect_poll "Space turns Bluetooth off" '[["blocked", "unblocked"]]' bt_radio
  expect_poll "the section reads off" off bt_view
  type_keys -k space || fail "typing Space on the power switch again failed"
  expect_poll "Space turns Bluetooth on" on bt_view
  bt_transcript "" ""
  agent_before="$(bt_count bluetoothctl)" || { fail "bluetooth: the bluetoothctl stand-in's calls are unreadable"; return 0; }
  type_keys -k Tab || fail "typing Tab to Discoverable failed"
  expect_poll "Tab reaches Discoverable" Discoverable bt_focus
  type_keys -k space || fail "typing Space on Discoverable failed"
  expect_poll "Discoverable makes the adapter discoverable" True bt_adapter Discoverable
  expect_poll "Discoverable holds the agent's lease" "[$bt_default]" bt_agent_stdin "$agent_before"
  expect "BlueZ ends Discoverable on its own timeout" updated bluez update "$bluez_adapter_path" org.bluez.Adapter1 '{"Discoverable": false}'
  expect_poll "BlueZ's end of Discoverable releases the agent's lease" "[$bt_default, $bt_off, \"EOF\"]" bt_agent_stdin "$agent_before"
  expect_poll "no lease is left with Discoverable off" '"off"' python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["bluetoothAgent"]["state"]))' "$(ipc shell lent)"
  device_transcript -
  type_keys -k Tab || fail "typing Tab to Hide when off failed"
  expect_poll "Tab reaches Hide when off" "Hide when off" bt_focus
  type_keys -k space || fail "typing Space on Hide when off failed"
  expect_poll "Hide when off reaches the section through configure" true bt_pane hideWhenOff
  expect_poll "and the widget's settings" true bt_widget_setting hideWhenOff
  type_keys -k space || fail "typing Space on Hide when off again failed"
  expect_poll "Hide when off turns off again" false bt_pane hideWhenOff
  type_keys -k Tab || fail "typing Tab to My Devices failed"
  expect_poll "Tab reaches the first of My Devices" "Smoke Headphones" bt_focus
  bt_menu_keyboard || return 0
  type_keys -k Down || fail "typing Down in My Devices failed"
  expect_poll "Down moves to the keyboard" "Smoke Keyboard" bt_focus
  type_keys -k Return || fail "typing Return on the keyboard's row failed"
  expect_poll "Return disconnects the keyboard" "False" bt_device "$bt_keyboard" Connected
  local removes_before
  removes_before="$(bt_calls RemoveDevice)"
  type_keys -k Delete || fail "typing Delete on the keyboard's row failed"
  expect_poll "Delete forgets the keyboard in the section" '[["Smoke Headphones", true], ["Smoke Mouse", true], ["Smoke Pad", true], ["Smoke Speaker", true]]' bt_mine
  expect "Delete removed the keyboard through BlueZ" rose bt_rose "$removes_before" bt_calls RemoveDevice
  expect "the mock holds the keyboard no more" gone bt_device_gone "$bt_keyboard"
  type_keys -k Escape || fail "typing Escape in the section failed"
  expect_poll "Escape returns the keyboard to the search field" bluetooth bt_focus vgs.system
  type_keys -k Escape -k Escape || fail "typing Escape in the search field failed"
  expect_poll "Escape closes the System window" closed bt_window_closed
  hypr_lua_restore bluetooth || fail "hyprland.lua is put back after the Bluetooth keyboard path"
  expect "the nested instance reloads hyprland.lua as the row found it" ok hypr reload config-only

  bt_stability
  if [[ $bt_was_system == False ]]; then expect "vgs.system is disabled again as the row found it" ok ipc shell setPluginEnabled vgs.system false; fi
}

bt_was_system=""
bt_was_bluetooth=""
# The shell's log from here on is the row's.
bt_log_from="$(stat -c %s -- "$instance_log")" || { fail "bluetooth: the shell's log is unreadable: $instance_log"; bt_log_from=0; }
bt_main
unset bt_id
# vgs.bluetooth as the row found it, whichever step the row returned from:
# disabled in the smoke set, enabled after a row restarted over the default
# set, such as rows/hidpi.sh.
case "$bt_was_bluetooth" in
  True)
    expect "vgs.bluetooth is enabled again as the row found it" ok ipc shell setPluginEnabled vgs.bluetooth true
    expect_poll "vgs.bluetooth holds the agent's capability again" '["vgs.bluetooth"]' bt_agent_holders ;;
  False)
    expect "vgs.bluetooth is disabled again as the row found it" ok ipc shell setPluginEnabled vgs.bluetooth false
    expect_poll "no plugin holds the agent at the row's end" null bt_agent_holders ;;
esac
bluez_follow off
device_reply_clear systemctl
rm -f -- "${devices_dir:?}/bt-display-seen" "${devices_dir:?}/bt-pin-typed"
tail -c "+$((bt_log_from + 1))" -- "$instance_log" >"$sandbox/bluetooth-row.log"
check_unexpected_log "the shell's log over the Bluetooth row" "$sandbox/bluetooth-row.log"
