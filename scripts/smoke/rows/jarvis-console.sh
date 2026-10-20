# Jarvis console window. Scripted daemon fixtures only: no audio, account,
# provider or network runs. The row has no latency ceiling. It polls once
# per nested IPC round trip; fixture callback gates poll at 10 ms.
# inputs: shell/plugins/vgs.jarvis/* scripts/fixtures/jarvis/* scripts/smoke/keyboard/* scripts/smoke/toplevel/* shell/Ui/* shell/Commons/* scripts/smoke/rows/jarvis-keys.sh scripts/smoke/rows/jarvis-bubble.sh scripts/smoke/rows/jarvis.sh scripts/smoke/rows/windows.sh scripts/smoke/rows/capabilities.sh scripts/smoke/rows/plugins.sh scripts/smoke/rows/hyprland-consent.sh scripts/smoke/rows/hold-shortcuts.sh shell/Core/ShortcutRegistry.qml shell/Hosts/AppWindow.qml shell/Hosts/PluginSlot.qml shell/Hosts/SummonHost.qml shell/Core/HyprlandLayer.js
set -euo pipefail

jarvis_console_config="$home/.config/vgshell/shell.json"
jarvis_console_lua="$home/.config/hypr/hyprland.lua"
jarvis_console_service="$repo/shell/plugins/vgs.jarvis/Service.qml"
jarvis_console_qml="$repo/shell/plugins/vgs.jarvis/Console.qml"
jarvis_console_backend="$repo/shell/plugins/vgs.jarvis/backend/jarvisd.js"
jarvis_console_engine="$repo/shell/plugins/vgs.jarvis/backend/ChainedEngine.js"
jarvis_console_plugin="$repo/shell/plugins/vgs.jarvis"
jarvis_console_gates="$sandbox/jarvis-console-gates"
jarvis_key_gates="$jarvis_console_gates"
cp -- "$jarvis_console_config" "$sandbox/jarvis-console-config-before.json"
cp -- "$jarvis_console_lua" "$sandbox/jarvis-console-lua-before"
cp -- "$jarvis_console_service" "$sandbox/jarvis-console-service-before"
cp -- "$jarvis_console_qml" "$sandbox/jarvis-console-qml-before"
cp -- "$jarvis_console_backend" "$sandbox/jarvis-console-backend-before"
cp -- "$jarvis_console_engine" "$sandbox/jarvis-console-engine-before"
jarvis_console_resolve_binds_by_sym() { hypr -j getoption input:resolve_binds_by_sym | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps([v.get("bool"), v["set"]]))'; }
jarvis_console_option_before="$(jarvis_console_resolve_binds_by_sym)"
jarvis_console_keyboards() {
  hypr -j devices | py_reply 'import json,sys; print(json.dumps(sorted(k["name"] for k in json.load(sys.stdin)["keyboards"])))'
}
jarvis_console_keyboards_before="$(jarvis_console_keyboards)"
jarvis_console_keyboard_check() {
  expect_poll "the console row restores its starting keyboard devices" "$jarvis_console_keyboards_before" jarvis_console_keyboards
}
jarvis_console_keyboard_control() {
  (failures=0 behaviour_failures=0
   jarvis_console_keyboard_check >"$sandbox/jarvis-console-keyboard-control.log"
   echo "$failures")
}

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
jarvis_console_tabs() {
  ipc smoke itemValues window vgs.jarvis Tabs count,currentIndex | py_reply 'import json,sys; rows=json.load(sys.stdin); print(json.dumps([[r.get("count"),r.get("currentIndex")] for r in rows]))'
}
jarvis_console_selected() {
  ipc smoke itemValues window vgs.jarvis ListCursor target.modelData.id | py_reply 'import json,sys; rows=json.load(sys.stdin); print(next((r["target.modelData.id"] for r in rows if r.get("target.modelData.id")), "none"))'
}
jarvis_console_body_focused() {
  # QQuickControl is Qt's concrete template type. The scroll proxy has no
  # content children; the Tasks and Audit controls own their columns.
  ipc smoke itemValues window vgs.jarvis QQuickControl activeFocus,contentItem.children.length | py_reply 'import json,sys; rows=json.load(sys.stdin); print("true" if any(r.get("activeFocus") and (r.get("contentItem.children.length") or 0)>0 for r in rows) else "false")'
}
jarvis_console_fixture_task() { # INDEX
  ipc smoke jarvisProcess | py_reply 'import json,sys; rows=json.load(sys.stdin)["status"].get("taskList", []); i=int(sys.argv[1]); print(rows[i]["id"] if len(rows)>i else "missing")' "$1"
}
jarvis_console_intent() { # INTENT
  python3 - "$jarvis_console_gates/effects.jsonl" "$1" <<'PY_INTENT'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
rows=[json.loads(line) for line in p.read_text().splitlines()] if p.exists() else []
print(next((row['task'] for row in reversed(rows) if row.get('kind')=='console-intent' and row.get('intent')==sys.argv[2]), 'none'))
PY_INTENT
}
jarvis_console_intent_count() { # INTENT
  python3 - "$jarvis_console_gates/effects.jsonl" "$1" <<'PY_COUNT'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
print(sum(row.get('kind')=='console-intent' and row.get('intent')==sys.argv[2] for row in [json.loads(line) for line in p.read_text().splitlines()]) if p.exists() else 0)
PY_COUNT
}
jarvis_console_audit() {
  ipc smoke itemValues window vgs.jarvis Label text,visible | py_reply 'import json,sys; rows=json.load(sys.stdin); print("shown" if any(r.get("visible") and r.get("text")=="files.delete" for r in rows) else "missing")'
}
jarvis_console_tasks_tab_check() { expect_poll "the tab bar reaches Tasks" '[[3, 1]]' jarvis_console_tabs; }
jarvis_console_stop_check() { expect_poll "Stop sends the selected fixture id" "$1" jarvis_console_intent task-stop; }
jarvis_console_audit_check() { expect_poll "Audit draws the fixture failure" shown jarvis_console_audit; }
# A failed voice stream's record draws its cause after its result, as a
# withheld one draws its refusal.
jarvis_console_audit_cause() {
  ipc smoke itemValues window vgs.jarvis Label text,visible | py_reply 'import json,sys; rows=json.load(sys.stdin); print("shown" if any(r.get("visible") and str(r.get("text")).startswith("Failed \u00b7 ") for r in rows) else "missing")'
}
jarvis_console_audit_cause_check() { expect_poll "Audit draws the failed stream's cause" shown jarvis_console_audit_cause; }
# The hairline count of each shown GroupList: the fixture's three Audit
# records are three groups, so two hairlines part them.
jarvis_console_audit_groups() {
  ipc smoke itemValues window vgs.jarvis GroupList visible,hairlines | py_reply 'import json,sys; rows=json.load(sys.stdin); print(json.dumps([len(r.get("hairlines") or []) for r in rows if r.get("visible")]))'
}
jarvis_console_audit_groups_check() { expect_poll "Audit draws its records as one GroupList with a hairline between them" '[2]' jarvis_console_audit_groups; }
jarvis_console_tasks_path() {
  expect_poll "Conversation has composer focus before its tab switch" true jarvis_console_text_field_focused
  type_keys -M ctrl -k Tab -m ctrl || fail "switching to Tasks failed"
  jarvis_console_tasks_tab_check
  expect_poll "Tasks takes keyboard focus" true jarvis_console_body_focused
}
jarvis_console_stop_path() {
  local intents_before first_fixture
  first_fixture="$(jarvis_console_fixture_task 0)"
  expect_poll "the Tasks cursor starts on the newest fixture" "$first_fixture" jarvis_console_selected
  intents_before="$(jarvis_console_intent_count task-stop)"
  type_keys -k Down || fail "selecting the second task by keyboard failed"
  expect_poll "Down moves the cursor to the second task" "$second_task" jarvis_console_selected
  type_keys -k Tab -k Tab -k Return || fail "stopping the second task by keyboard failed"
  expect_poll "Stop records a new console intent" "$((intents_before + 1))" jarvis_console_intent_count task-stop
}
jarvis_console_tab_control() {
  (failures=0 behaviour_failures=0
   jarvis_console_tasks_tab_check >"$sandbox/jarvis-console-tabs-control.log"
   echo "$failures")
}
jarvis_console_stop_control() {
  (failures=0 behaviour_failures=0
   jarvis_console_stop_check "$1" >"$sandbox/jarvis-console-stop-control.log"
   echo "$failures")
}
jarvis_console_audit_control() {
  (failures=0 behaviour_failures=0
   jarvis_console_audit_check >"$sandbox/jarvis-console-audit-control.log"
   echo "$failures")
}
jarvis_console_groups_control() {
  (failures=0 behaviour_failures=0
   jarvis_console_audit_groups_check >"$sandbox/jarvis-console-groups-control.log"
   echo "$failures")
}
jarvis_console_requirement_shims() {
  python3 - "$shim" "${jarvis_requirement_standins[@]}" <<'PY'
import json, pathlib, sys
shim = pathlib.Path(sys.argv[1])
print(json.dumps([name for name in sys.argv[2:] if (shim / name).exists()]))
PY
}
printf '%s\n' \
  'hl.config({ input = { resolve_binds_by_sym = true } })' \
  'hl.bind("code:67", hl.dsp.global("smoke:hold-marker"), { description = "smoke:hold-marker", ignore_mods = true })' >>"$jarvis_console_lua"
expect "Jarvis console keys use the physical evdev map" ok hypr reload config-only
expect "the console row creates its ordering marker" ok ipc smoke holdMarkerStart
expect_poll "the console row ordering marker is registered" 1 hold_native smoke:hold-marker
hold_markers="$(ipc smoke holdMarkerCount)"
hold_delayed_keyboard=""
hold_start_keyboard jarvis-console "$sandbox/keyboard" us ""
jarvis_setup_requirements
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" "$jarvis_console_backend" "$jarvis_console_gates" --mapped-indicator
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" --console-data "$jarvis_console_backend"
jarvis_rescan
jarvis_enable
jarvis_shortcut_assertion
# The first event from the row's virtual keyboard can be dropped by the
# nested compositor; warm it with an unbound key before testing the shortcut.
hold_send "down 30" "up 30"
hold_barrier
jarvis_console_open
hold_barrier
expect_poll "the console key opens one Jarvis window" 1 jarvis_console_client_count
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
jarvis_console_tasks_path
second_task="$(jarvis_console_fixture_task 1)"
first_task="$(jarvis_console_fixture_task 0)"
jarvis_console_stop_path
jarvis_console_stop_check "$second_task"
# Stop returns to the list before its footer actions disable.
type_keys -k Up -k Return || fail "opening the first task by keyboard failed"
expect_poll "Enter opens the selected alive fixture" "$first_task" jarvis_console_intent task-open
type_keys -k Escape || fail "Escape from Tasks failed"
expect_poll "Escape closes Tasks" 0 jarvis_console_client_count
jarvis_console_open
hold_barrier
jarvis_console_tasks_path
# The first control receives focus on switch; Backtab returns to the
# reachable tab bar, whose Right key switches to Audit.
type_keys -M shift -k Tab -m shift || fail "reaching the tab bar failed"
expect_poll "the tab bar takes keyboard focus" true ipc smoke activeFocusWithin window vgs.jarvis Tabs
type_keys -k Right || fail "switching the tab bar to Audit failed"
expect_poll "Right selects Audit" '[[3, 2]]' jarvis_console_tabs
expect_poll "Audit takes keyboard focus" true jarvis_console_body_focused
jarvis_console_audit_check
jarvis_console_audit_cause_check
jarvis_console_audit_groups_check
type_keys -k Page_Down -k Page_Up -M shift -k Tab -m shift || fail "Audit scrolling or Backtab failed"
expect_poll "Audit Backtab reaches the tab bar" true ipc smoke activeFocusWithin window vgs.jarvis Tabs
type_keys -k Left || fail "switching the tab bar left failed"
expect_poll "Left selects Tasks" '[[3, 1]]' jarvis_console_tabs
expect_poll "Left focuses Tasks" true jarvis_console_body_focused
type_keys -M ctrl -k Tab -m ctrl || fail "returning to Audit failed"
expect_poll "the console returns to Audit" '[[3, 2]]' jarvis_console_tabs
type_keys -k Escape || fail "Escape from Audit failed"
expect_poll "Escape closes Audit" 0 jarvis_console_client_count
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
needle='send(fields); return "ok";'
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
expect "control: dropping say delivery breaks the daemon assertion" 1 jarvis_console_send_drop_control "$((say_before + 1))"
jarvis_disable
cp -- "$sandbox/jarvis-console-service-before" "$jarvis_console_service"
python3 - "$jarvis_console_qml" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
replacements=[
    ('property Item initialFocus: entryField', 'property Item initialFocus: stopButton'),
    ('Qt.callLater(() => entryField.forceActiveFocus());', 'Qt.callLater(() => stopButton.forceActiveFocus());'),
]
for needle, replacement in replacements:
    assert s.count(needle)==1, needle
    s=s.replace(needle, replacement)
p.write_text(s)
PY
jarvis_rescan
jarvis_enable
jarvis_console_open
hold_barrier
expect "control: moving focus off the field breaks the keyboard-path assertion" 1 jarvis_console_focus_control
jarvis_disable
cp -- "$sandbox/jarvis-console-qml-before" "$jarvis_console_qml"
for jarvis_console_mutant in tabs stop audit groups; do
  python3 - "$jarvis_console_qml" "$jarvis_console_mutant" <<'PY_CONTROL'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
changes={
    "tabs": ('model: ["Conversation", "Tasks", "Audit"]', 'model: ["Conversation", "Audit"]'),
    "stop": ('"open-task", task.id);', '"open-task", taskRows[0].id);'),
    "audit": ('model: root.auditRows', 'model: []'),
    "groups": ('contentItem: GroupList {', 'contentItem: Column {'),
}
needle,replacement=changes[sys.argv[2]]
assert s.count(needle)==1, needle
p.write_text(s.replace(needle,replacement))
PY_CONTROL
  jarvis_rescan
  jarvis_enable
  jarvis_console_open
  hold_barrier
  expect_poll "the mutant Conversation has composer focus before switching" true jarvis_console_text_field_focused
  type_keys -M ctrl -k Tab -m ctrl || fail "switching the mutant Tasks tab failed"
  case "$jarvis_console_mutant" in
    tabs) expect "control: dropping Tasks breaks the tab assertion" 1 jarvis_console_tab_control ;;
    stop)
      jarvis_console_tasks_tab_check
      expect_poll "the Stop control focuses Tasks" true jarvis_console_body_focused
      second_task="$(jarvis_console_fixture_task 1)"
      jarvis_console_stop_path
      expect "control: sending the first id breaks the selected-task assertion" 1 jarvis_console_stop_control "$second_task"
      ;;
    audit|groups)
      jarvis_console_tasks_tab_check
      expect_poll "the Audit control starts with Tasks focus" true jarvis_console_body_focused
      type_keys -M ctrl -k Tab -m ctrl || fail "switching the mutant Audit tab failed"
      if [[ "$jarvis_console_mutant" == audit ]]; then
        expect "control: empty audit data breaks the failure assertion" 1 jarvis_console_audit_control
      else
        jarvis_console_audit_check
        expect "control: a plain Column breaks the GroupList assertion" 1 jarvis_console_groups_control
      fi
      ;;
  esac
  jarvis_disable
  cp -- "$sandbox/jarvis-console-qml-before" "$jarvis_console_qml"
done
cp -- "$sandbox/jarvis-console-backend-before" "$jarvis_console_backend"
cp -- "$sandbox/jarvis-console-engine-before" "$jarvis_console_engine"
cp -- "$sandbox/jarvis-console-service-before" "$jarvis_console_service"
cp -- "$sandbox/jarvis-console-qml-before" "$jarvis_console_qml"
rm -f -- "${jarvis_console_plugin:?}/backend/scripted-fixture.js" "${home:?}/.local/state/vgshell/jarvis/mute.json"
jarvis_rescan
cp -- "$sandbox/jarvis-console-config-before.json" "$jarvis_console_config.next" && mv -T -- "$jarvis_console_config.next" "$jarvis_console_config"
cp -- "$sandbox/jarvis-console-lua-before" "$jarvis_console_lua"
expect "restore the Jarvis console shell configuration" ok ipc shell reloadConfig
expect "restore the Jarvis console keyboard configuration" ok hypr reload config-only
expect "the console row restores symbolic bind resolution" "$jarvis_console_option_before" jarvis_console_resolve_binds_by_sym
jarvis_restore_requirements
expect "the console row removes its requirement shims" '[]' jarvis_console_requirement_shims
jarvis_enable
expect_poll "the restored stock daemon remains unconfigured" session jarvis_session unconfigured
expect "the console row leaves no scripted fixture" False python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).exists())' "$jarvis_console_plugin/backend/scripted-fixture.js"
expect "the console row restores Console.qml" same python3 -c 'import filecmp,sys; print("same" if filecmp.cmp(sys.argv[1], sys.argv[2], shallow=False) else "different")' "$sandbox/jarvis-console-qml-before" "$jarvis_console_qml"
expect "the console row restores ChainedEngine.js" same python3 -c 'import filecmp,sys; print("same" if filecmp.cmp(sys.argv[1], sys.argv[2], shallow=False) else "different")' "$sandbox/jarvis-console-engine-before" "$jarvis_console_engine"
expect "the console row leaves no Jarvis mute state" False python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).exists())' "$home/.local/state/vgshell/jarvis/mute.json"
jarvis_disable
jarvis_notice_close
# Rows share the harness process. Waiting for EXIT keeps this keyboard
# alive in later rows and replaces the harness's sandbox teardown.
expect "control: retaining the console keyboard fails the device cleanup check" 1 jarvis_console_keyboard_control
sed 's/^/  CONTROL  /' "$sandbox/jarvis-console-keyboard-control.log"
hold_stop_keyboard
expect "the console row releases its ordering marker" ok ipc smoke holdMarkerStop
expect_poll "the console row leaves no ordering marker" 0 hold_native smoke:hold-marker
jarvis_console_keyboard_check
