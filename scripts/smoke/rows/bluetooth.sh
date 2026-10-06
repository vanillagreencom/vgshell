# vgs.bluetooth over the sandbox's device fakes
# (docs/architecture/validation-smoke-host.md): python-dbusmock's bluez5
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
# Disconnect and Connect clicks move the headphones; and a keyboard path
# from SUPER+PERIOD turns Bluetooth off and on, turns Discoverable on, whose
# lease BlueZ's own end of Discoverable releases, writes Hide when off,
# disconnects a device with Return and forgets it with Delete, which
# removes it from the mock, and closes.
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
# The stand-in terminal runs no system step. Every poll is
# expect_poll's: 25 reads 0.2 s apart. The row leaves vgs.bluetooth and
# vgs.system enabled or disabled as it found them, discovery confirming,
# the follow off and no planted systemctl answer, whichever step it
# returns from.
# inputs: shell/plugins/vgs.bluetooth/* shell/plugins/vgs.system/* shell/Ui/layout/DeviceList.qml scripts/smoke/fixtures/devices/* shell/Core/BluetoothAgent.qml shell/Core/BluetoothAgentModel.js shell/Core/SystemSteps.qml shell/Core/PluginStatus.qml shell/Core/Capabilities.qml shell/Core/PluginLogic.js shell/Hosts/PaneHost.qml bin/vgshell-system bin/vgshell-tui scripts/smoke/rows/device-fakes.sh
set -euo pipefail

bt_keyboard=00:1B:66:AA:BB:02
bt_mouse=00:1B:66:AA:BB:03
bt_headphones=00:1B:66:AA:BB:01
bt_speaker=00:1B:66:AA:BB:05
bt_pad=00:1B:66:AA:BB:06
bt_default='"                 default-agent"'
bt_off='"                 agent off"'

bt_service() { ipc smoke readInstance service "${bt_id:-vgs.bluetooth}" "$1"; }
bt_view() { bt_service view | py_reply 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "${1:-key}"; }
bt_leases() { bt_service discovery | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["leases"]))'; }
bt_radio() { rfkill_state | py_reply 'import json,sys; print(json.dumps([r[1:] for r in json.load(sys.stdin) if r[0] == "bluetooth"]))'; }
bt_adapter() { bluez props "$bluez_adapter_path" org.bluez.Adapter1 | py_reply 'import json,sys; d=json.load(sys.stdin); print(" ".join(str(d[k]) for k in sys.argv[1:]))' "$@"; }
bt_path() { printf '%s/dev_%s' "$bluez_adapter_path" "${1//:/_}"; }
bt_device() { local mac="$1"; shift; bluez props "$(bt_path "$mac")" org.bluez.Device1 | py_reply 'import json,sys; d=json.load(sys.stdin); print(" ".join(str(d[k]) for k in sys.argv[1:]))' "$@"; }
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
bt_lists() { # HOST_KEY ID
  ipc smoke readDescendant "$1" "$2" DeviceSections lists | py_reply 'import json,sys; print(json.dumps([[r["text"], r["connected"]] for r in json.load(sys.stdin)["mine"]]))'
}
bt_mine() { bt_lists window vgs.bluetooth; }
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
bt_window_closed() { [[ $(window_count System) == 0 ]] && echo closed || echo open; }
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
  expect "the widget counts one connected device" '"1"' bt_widget_view count

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
  click_in window:System window vgs.bluetooth Button Disconnect || fail "the click on Disconnect failed"
  expect_poll "Disconnect disconnects the first device" "False" bt_device "$bt_headphones" Connected
  click_in window:System window vgs.bluetooth Button Connect || fail "the click on Connect failed"
  expect_poll "Connect connects it again" "True" bt_device "$bt_headphones" Connected
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
  rm -rf -- "${bare_dir:?}"
  cp -R -- "$repo/shell/plugins/vgs.bluetooth" "$bare_dir"
  python3 - "$bare_dir" <<'PY'
import json, os, sys
root = sys.argv[1]
path = os.path.join(root, "manifest.json")
doc = json.load(open(path))
doc["id"], doc["name"] = "acme.bluetooth-bare", "Bluetooth Bare"
json.dump(doc, open(path, "w"))
file = os.path.join(root, "Service.qml")
text = open(file).read()
old = "readonly property var adapters: Bluetooth.adapters.values"
assert text.count(old) == 1, old
open(file, "w").write(text.replace(old, "readonly property var adapters: []"))
PY
  device_reply systemctl 3 "" is-active --quiet bluetooth.service
  device_reply systemctl 0 loaded show --property=LoadState --value bluetooth.service
  terminal_stand_in
  terminal_ready "bluetooth"
  rescan "rescan after adding the bare copy answers ok"
  expect_poll "the bare copy lands enabled, as a new bar widget does" True plugin_enabled acme.bluetooth-bare
  bt_id=acme.bluetooth-bare
  expect_poll "with no adapter and the service stopped, the service reads service-needed" service-needed bt_view
  expect "the stopped service's line" "The Bluetooth service is off." bt_view text
  expect "the bare copy's section summons" ok ipc shell summon window vgs.system '{"pane":"acme.bluetooth-bare"}'
  expect_poll "the bare copy's section mounts" '["acme.bluetooth-bare"]' window_panes
  expect_poll "the section offers the status row's action" '{"label": "Turn on the service"}' bt_service_action
  forget_record
  expect "no terminal is asked for before the click" absent recorded
  click_in window:System window acme.bluetooth-bare Button "Turn on the service" || fail "the click on Turn on the service failed"
  expect_poll "Turn on the service hands the terminal vgshell system apply service-bluetooth" \
    "$(core_words core/system "System setup" org.vgs.tui system apply service-bluetooth)" recorded
  expect_run_end "the Turn on the service core/system run ends" core/system
  forget_record
  expect "hiding the System window after the stopped service is allowed" ok ipc shell hide window vgs.system
  expect_poll "the System window is closed after the stopped service" closed bt_window_closed
  unset bt_id
  expect "disabling the bare copy is allowed" ok ipc shell setPluginEnabled acme.bluetooth-bare false
  rm -rf -- "${bare_dir:?}"
  device_reply_clear systemctl
  device_reply systemctl 0 "" is-active --quiet bluetooth.service
  rescan "rescan after removing the bare copy answers ok"
  expect_poll "the bare copy is gone" absent plugin_enabled acme.bluetooth-bare

  expect "enabling vgs.bluetooth after the controls is allowed" ok ipc shell setPluginEnabled vgs.bluetooth true
  expect_poll "vgs.bluetooth reads on again" on bt_view

  # Keyboard alone: SUPER+PERIOD, the search, the section, its switches and
  # its devices, then out.
  hypr_lua_save bluetooth
  printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$home/.config/hypr/hyprland.lua"
  expect "the nested instance reloads with binds resolved by keysym" ok hypr reload config-only
  rest_pointer || fail "moving the pointer off the System window failed"
  type_keys -M logo -k period -m logo || fail "typing SUPER+PERIOD failed"
  expect_poll "SUPER+PERIOD opens the System window" 1 window_count System
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

  if [[ $bt_was_system == False ]]; then expect "vgs.system is disabled again as the row found it" ok ipc shell setPluginEnabled vgs.system false; fi
}

bt_was_system=""
bt_was_bluetooth=""
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
