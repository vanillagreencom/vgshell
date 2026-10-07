# Jarvis console window. Scripted daemon fixtures only: no audio, account,
# provider or network runs. The row has no latency ceiling. It polls once
# per nested IPC round trip; fixture callback gates poll at 10 ms.
# inputs: shell/plugins/vgs.jarvis/* scripts/fixtures/jarvis/* scripts/smoke/keyboard/* scripts/smoke/toplevel/* shell/Ui/* shell/Commons/* scripts/smoke/rows/jarvis-keys.sh scripts/smoke/rows/jarvis-bubble.sh scripts/smoke/rows/jarvis.sh scripts/smoke/rows/windows.sh scripts/smoke/rows/capabilities.sh scripts/smoke/rows/plugins.sh scripts/smoke/rows/hyprland-consent.sh scripts/smoke/rows/hold-shortcuts.sh shell/Core/ShortcutRegistry.qml shell/Hosts/AppWindow.qml shell/Hosts/PluginSlot.qml shell/Hosts/SummonHost.qml shell/Core/HyprlandLayer.js
set -euo pipefail

jarvis_console_config="$home/.config/vgshell/shell.json"
jarvis_console_lua="$home/.config/hypr/hyprland.lua"
jarvis_console_service="$repo/shell/plugins/vgs.jarvis/Service.qml"
jarvis_console_backend="$repo/shell/plugins/vgs.jarvis/backend/jarvisd.js"
jarvis_console_plugin="$repo/shell/plugins/vgs.jarvis"
jarvis_console_gates="$sandbox/jarvis-console-gates"
jarvis_key_gates="$jarvis_console_gates"
cp -- "$jarvis_console_config" "$sandbox/jarvis-console-config-before.json"
cp -- "$jarvis_console_lua" "$sandbox/jarvis-console-lua-before"
cp -- "$jarvis_console_service" "$sandbox/jarvis-console-service-before"
cp -- "$jarvis_console_backend" "$sandbox/jarvis-console-backend-before"

jarvis_console_state() { # FIELD
  ipc smoke jarvisProcess | py_reply '
import json,sys
s=json.load(sys.stdin)["status"].get("conversation", [])
if sys.argv[1] == "count": print(len(s))
elif sys.argv[1] == "last": print("none" if not s else s[-1]["role"]+":"+s[-1]["text"]+":"+s[-1]["stage"])
elif sys.argv[1] == "text": print("\n".join(row["role"]+":"+row["text"] for row in s))
' "$1"
}
jarvis_console_open() { hold_send "down 133" "down 64" "down 54" "up 54" "up 64" "up 133"; }
jarvis_console_client_count() { window_count Jarvis; }
jarvis_console_say_count() {
  python3 - "$jarvis_console_gates/effects.jsonl" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
print(sum(json.loads(line).get("kind")=="brain-send" and json.loads(line).get("text")=="typed from console" for line in p.read_text().splitlines()) if p.exists() else 0)
PY
}
jarvis_console_text_field_focused() {
  ipc smoke itemValues window vgs.jarvis TextField activeFocus | py_reply '
import json,sys
rows=json.load(sys.stdin)
print("true" if any(row.get("activeFocus") is True for row in rows) else "false")
'
}
jarvis_console_field_text() { ipc smoke readShownDescendant window vgs.jarvis TextField text; }
jarvis_console_hint_has() { # TEXT
  ipc smoke itemValues window vgs.jarvis Label text,visible | py_reply '
import json,sys
print("shown" if any(row.get("visible") and row.get("text")==sys.argv[1] for row in json.load(sys.stdin)) else "missing")
' "$1"
}
jarvis_console_shortcuts() {
  hypr globalshortcuts | python3 -c 'import json,re,sys; print(json.dumps(sorted(set(re.findall(r"vgs\.jarvis:[A-Za-z0-9_.-]+", sys.stdin.read())))))'
}
jarvis_console_send_drop_control() {
  (failures=0 behaviour_failures=0
   expect_poll "the console sends typed text to the daemon" "$1" jarvis_console_say_count >"$sandbox/jarvis-console-send-control.log"
   echo "$failures")
}
jarvis_console_open_control() {
  (failures=0 behaviour_failures=0
   expect_poll "the console key opens one Jarvis window" 1 jarvis_console_client_count >"$sandbox/jarvis-console-open-control.log"
   echo "$failures")
}
jarvis_console_focus_control() {
  (failures=0 behaviour_failures=0
   expect_poll "the console text field has focus" true jarvis_console_text_field_focused >"$sandbox/jarvis-console-focus-control.log"
   echo "$failures")
}
jarvis_console_cleanup() {
  hold_stop_keyboard || true
  ipc smoke holdMarkerStop >/dev/null || true
  cp -- "$sandbox/jarvis-console-service-before" "$jarvis_console_service"
  cp -- "$sandbox/jarvis-console-backend-before" "$jarvis_console_backend"
  cp -- "$sandbox/jarvis-console-config-before.json" "$jarvis_console_config"
  cp -- "$sandbox/jarvis-console-lua-before" "$jarvis_console_lua"
  rm -f -- "${jarvis_console_plugin:?}/backend/scripted-fixture.js" "${home:?}/.local/state/vgshell/jarvis/mute.json"
}
trap jarvis_console_cleanup EXIT

printf '%s\n' \
  'hl.config({ input = { resolve_binds_by_sym = false } })' \
  'hl.bind("code:67", hl.dsp.global("smoke:hold-marker"), { description = "smoke:hold-marker", ignore_mods = true })' >>"$jarvis_console_lua"
expect "Jarvis console keys use the physical evdev map" ok hypr reload config-only
expect "the console row creates its ordering marker" ok ipc smoke holdMarkerStart
expect_poll "the console row ordering marker is registered" 1 hold_native smoke:hold-marker
hold_markers="$(ipc smoke holdMarkerCount)"
hold_delayed_keyboard=""
hold_start_keyboard jarvis-console "$sandbox/keyboard" us ""
jarvis_setup_requirements
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" "$jarvis_console_backend" "$jarvis_console_gates" --mapped-indicator
jarvis_rescan
jarvis_enable
expect_poll "Jarvis registers its manifest shortcuts and talk release companion" '["vgs.jarvis:confirm", "vgs.jarvis:console", "vgs.jarvis:mute", "vgs.jarvis:stop", "vgs.jarvis:talk", "vgs.jarvis:talk.release"]' jarvis_console_shortcuts
jarvis_console_open
hold_barrier
expect "the console key opens one Jarvis window" 1 jarvis_console_client_count
jarvis_console_open
hold_barrier
# The core window host's single-instance rule is owned by rows/windows.sh:
# its bundled-window loop opens one client for each window plugin, and its
# Themes panel control proves non-window surfaces do not count as clients.
expect "a second console key press keeps one Jarvis window" 1 jarvis_console_client_count
expect_poll "the console text field has focus" true jarvis_console_text_field_focused
say_before="$(jarvis_console_say_count)"
type_keys "typed from console" || fail "typing into the console failed"
type_keys -k Return || fail "pressing Enter in the console failed"
expect_poll "the console sends typed text to the daemon" "$((say_before + 1))" jarvis_console_say_count
expect_poll "the console shows the typed user line" "user:typed from console:final" jarvis_console_state last
jarvis_key_gate brain
expect_poll "the console shows the scripted Jarvis reply" "assistant:scripted utterance:partial" jarvis_console_state last
jarvis_key_mute
expect_poll "muted state reaches the console" on jarvis_key_state mute
type_keys " stays in field" || fail "typing while muted failed"
type_keys -k Return || fail "pressing Enter while muted failed"
expect_poll "muted Send is refused in the composer" shown jarvis_console_hint_has "Unmute Jarvis to type"
expect 'muted refusal keeps the typed text' '" stays in field"' jarvis_console_field_text
expect "muted refusal leaves daemon send count unchanged" "$((say_before + 1))" jarvis_console_say_count
jarvis_key_mute
expect_poll "the console controls start unmuted" off jarvis_key_state mute
type_keys -k Escape || fail "typing Escape into the console failed"
expect_poll "Escape closes the console" 0 jarvis_console_client_count
jarvis_console_open
hold_barrier
expect_poll "the console window is open before disable" 1 jarvis_console_client_count
jarvis_disable
expect_poll "disabling Jarvis closes the console window" 0 jarvis_console_client_count

cp -- "$sandbox/jarvis-console-service-before" "$jarvis_console_service"
python3 - "$jarvis_console_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
needle='shell.surfaces.summon("window", "{}")'
assert s.count(needle)==1
p.write_text(s.replace(needle, '"ok"'))
PY
jarvis_rescan
jarvis_enable
jarvis_console_open
hold_barrier
expect "control: dropping the summon path breaks the open assertion" 1 jarvis_console_open_control
jarvis_disable
cp -- "$sandbox/jarvis-console-service-before" "$jarvis_console_service"
python3 - "$jarvis_console_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
needle='send(fields);\n        return "ok";'
assert s.count(needle)==1
p.write_text(s.replace(needle, 'return "ok";'))
PY
jarvis_rescan
jarvis_enable
jarvis_console_open
hold_barrier
say_before="$(jarvis_console_say_count)"
type_keys "typed from console" || fail "typing into the send control failed"
type_keys -k Return || fail "pressing Enter in the send control failed"
expect_poll "control: the mutation leaves text in the field" '"typed from console"' jarvis_console_field_text
expect "control: dropping say delivery breaks the daemon assertion" 1 jarvis_console_send_drop_control "$((say_before + 1))"
jarvis_disable
cp -- "$sandbox/jarvis-console-service-before" "$jarvis_console_service"
python3 - "$repo/shell/plugins/vgs.jarvis/Console.qml" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
needle='Qt.callLater(() => entryField.forceActiveFocus());'
assert s.count(needle)==1
p.write_text(s.replace(needle, 'Qt.callLater(() => stopButton.forceActiveFocus());'))
PY
jarvis_rescan
jarvis_enable
jarvis_console_open
hold_barrier
expect "control: moving focus off the field breaks the keyboard-path assertion" 1 jarvis_console_focus_control
jarvis_disable
cp -- "$sandbox/jarvis-console-backend-before" "$jarvis_console_backend"
cp -- "$sandbox/jarvis-console-service-before" "$jarvis_console_service"
rm -f -- "${jarvis_console_plugin:?}/backend/scripted-fixture.js" "${home:?}/.local/state/vgshell/jarvis/mute.json"
jarvis_rescan
jarvis_enable
expect_poll "the restored stock daemon remains unconfigured" session jarvis_session unconfigured
expect "the console row leaves no scripted fixture" False python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).exists())' "$jarvis_console_plugin/backend/scripted-fixture.js"
expect "the console row leaves no Jarvis mute state" False python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).exists())' "$home/.local/state/vgshell/jarvis/mute.json"
jarvis_disable
jarvis_notice_close
