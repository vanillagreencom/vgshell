# Jarvis console window. Scripted daemon fixtures only: no audio, account,
# provider or network runs. The row has no latency ceiling. It polls once
# per nested IPC round trip; fixture callback gates poll at 10 ms.
# inputs: shell/plugins/vgs.jarvis/* scripts/fixtures/jarvis/* scripts/smoke/keyboard/* scripts/smoke/toplevel/* shell/Ui/* shell/Commons/* scripts/smoke/rows/jarvis-keys.sh scripts/smoke/rows/jarvis-bubble.sh scripts/smoke/rows/jarvis.sh scripts/smoke/rows/windows.sh scripts/smoke/rows/capabilities.sh scripts/smoke/rows/plugins.sh scripts/smoke/rows/hyprland-consent.sh scripts/smoke/rows/hold-shortcuts.sh shell/Core/ShortcutRegistry.qml shell/Hosts/SummonHost.qml
set -euo pipefail

jarvis_console_state() { # FIELD
  ipc smoke jarvisProcess | py_reply '
import json,sys
s=json.load(sys.stdin)["status"].get("conversation", [])
if sys.argv[1] == "count": print(len(s))
elif sys.argv[1] == "last": print("none" if not s else s[-1]["role"]+":"+s[-1]["text"]+":"+s[-1]["stage"])
elif sys.argv[1] == "text": print("\n".join(row["role"]+":"+row["text"] for row in s))
' "$1"
}
jarvis_console_open() { hold_send "down 133" "down 64" "down 28" "up 28" "up 64" "up 133"; }
jarvis_console_client_count() { window_count Jarvis; }
jarvis_console_say_count() {
  python3 - "$jarvis_key_gates/effects.jsonl" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
print(sum(json.loads(line).get("kind")=="brain-send" and json.loads(line).get("text")=="typed from console" for line in p.read_text().splitlines()) if p.exists() else 0)
PY
}
jarvis_console_focus() { ipc smoke activeFocusIn window vgs.jarvis; }
jarvis_console_hint() { ipc smoke readShownDescendant window vgs.jarvis Label text; }
jarvis_console_send_drop_control() {
  (failures=0 behaviour_failures=0
   expect_poll "the console sends typed text to the daemon" "$1" jarvis_console_say_count >"$sandbox/jarvis-console-send-control.log"
   echo "$failures")
}
jarvis_console_single_control() {
  (failures=0 behaviour_failures=0
   expect_poll "the console key opens one Jarvis window" 1 jarvis_console_client_count >"$sandbox/jarvis-console-single-control.log"
   echo "$failures")
}

cp -- "$repo/shell/plugins/vgs.jarvis/backend/jarvisd.js" "$sandbox/jarvis-console-backend-before"
cp -- "$repo/shell/plugins/vgs.jarvis/Service.qml" "$sandbox/jarvis-console-service-before"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" "$repo/shell/plugins/vgs.jarvis/backend/jarvisd.js" "$sandbox/jarvis-console-gates" --mapped-indicator
jarvis_rescan
jarvis_enable
expect_poll "Jarvis console registers its default key" 5 hold_native vgs.jarvis:
jarvis_console_open
expect_poll "the console key opens one Jarvis window" 1 jarvis_console_client_count
jarvis_console_open
expect_poll "a second console key press keeps one Jarvis window" 1 jarvis_console_client_count
expect_poll "the console text field has focus" true jarvis_console_focus
say_before="$(jarvis_console_say_count)"
type_text "typed from console" || fail "typing into the console failed"
type_keys -k Return || fail "pressing Enter in the console failed"
expect_poll "the console sends typed text to the daemon" "$((say_before + 1))" jarvis_console_say_count
expect_poll "the console shows the typed user line" "user:typed from console:final" jarvis_console_state last
jarvis_key_gate brain
expect_poll "the console shows the scripted Jarvis reply" "assistant:scripted utterance:partial" jarvis_console_state last
jarvis_key_mute
expect_poll "muted state reaches the console" on jarvis_key_state mute
type_text " stays in field" || fail "typing while muted failed"
type_keys -k Return || fail "pressing Enter while muted failed"
expect_poll "muted Send is refused with text kept" true jarvis_console_focus
expect_poll "muted refusal leaves daemon send count unchanged" "$((say_before + 1))" jarvis_console_say_count
type_keys -k Escape || fail "typing Escape into the console failed"
expect_poll "Escape closes the console" 0 jarvis_console_client_count
jarvis_disable
jarvis_console_open
hold_barrier
expect "disabling Jarvis leaves no console window" 0 jarvis_console_client_count

cp -- "$sandbox/jarvis-console-service-before" "$repo/shell/plugins/vgs.jarvis/Service.qml"
python3 - "$repo/shell/plugins/vgs.jarvis/Service.qml" <<'PY'
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
expect "control: dropping the summon path breaks the one-window assertion" 1 jarvis_console_single_control
jarvis_disable
cp -- "$sandbox/jarvis-console-service-before" "$repo/shell/plugins/vgs.jarvis/Service.qml"
python3 - "$repo/shell/plugins/vgs.jarvis/Service.qml" <<'PY'
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
say_before="$(jarvis_console_say_count)"
type_text "typed from console" || fail "typing into the send control failed"
type_keys -k Return || fail "pressing Enter in the send control failed"
expect "control: dropping say delivery breaks the daemon assertion" 1 jarvis_console_send_drop_control "$((say_before + 1))"
jarvis_disable
cp -- "$sandbox/jarvis-console-service-before" "$repo/shell/plugins/vgs.jarvis/Service.qml"
cp -- "$sandbox/jarvis-console-backend-before" "$repo/shell/plugins/vgs.jarvis/backend/jarvisd.js"
jarvis_rescan
jarvis_enable
expect_poll "the restored stock daemon remains unconfigured" session jarvis_session unconfigured
jarvis_disable
