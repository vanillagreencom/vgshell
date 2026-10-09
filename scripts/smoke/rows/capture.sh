# The capture service uses real nested tools for image and selection readings.
# Stand-ins hold tool failures, countdown frames, OCR, the recorder, ffmpeg
# and the PipeWire device list. vgs.notifications runs as the row finds it,
# disabled in the smoke set and enabled in the default set a restarted
# shell runs; capture_wait_cards dismisses its cards before an image
# reading. Late in the row it is enabled for the notification readings, and
# shell.json's restore at the end puts it back as found.
# SUPER+SHIFT+S is typed on the bind hyprland-consent's wired layer holds.
# inputs: shell/plugins/vgs.capture/* shell/plugins/vgs.notifications/* shell/plugins/vgs.sysmon/* shell/plugins/vgs.launcher/* shell/Core/HyprlandLayer.js scripts/smoke/rows/hyprland-consent.sh shell/Core/NotificationHub.qml shell/Core/Layers.qml shell/Core/Capabilities.qml shell/Core/Compositor.qml shell/Core/Config.qml shell/Core/IpcRegistry.qml shell/Core/Lifetime.js shell/Core/MonitorLogic.js shell/Core/MonitorState.qml shell/Core/Notices.qml shell/Core/PackageManagers.js shell/Core/PluginLogic.js shell/Core/Plugins.qml shell/Core/PluginStatus.qml shell/Core/Registry.qml shell/Core/ServiceGate.qml shell/Core/ShortcutRegistry.qml shell/Core/Notifier.qml shell/Core/TuiRecords.qml shell/Core/TuiRunner.qml bin/vgshell-tui shell/Hosts/BarHost.qml shell/Hosts/NoticeHost.qml shell/Hosts/OverlaySurface.qml shell/Hosts/PluginSlot.qml shell/Hosts/ServiceHost.qml shell/Hosts/Summon* shell/Ui/* shell/Commons/* bin/vgshell-scan bin/lib/check-manifests.js bin/lib/qml-library.js scripts/test-capture.py scripts/smoke/fixtures/capture/*
# Expected rectangles come from Hyprland. Disposable copies remove each
# screenshot choice and the owned tool deadline, and
# the panel's mode and target choices, its press and its opening focus.
# Readbacks use the harness's state poll, with no capture latency budget.
set -euo pipefail
capture_state="$sandbox/capture-world"
capture_saved="$sandbox/shell-before-capture.json"
capture_real_grim="$(command -v grim)" || { fail "capture: grim is unavailable"; return 0; }
capture_real_slurp="$(command -v slurp)" || { fail "capture: slurp is unavailable"; return 0; }
capture_real_picker="$(command -v hyprpicker)" || { fail "capture: hyprpicker is unavailable"; return 0; }
cp -- "$home/.config/vgshell/shell.json" "$capture_saved"
mkdir -p "$capture_state/saved-shims"
for capture_tool in grim slurp hyprpicker tesseract wl-copy gpu-screen-recorder ffmpeg pw-dump; do
  if [[ -e $shim/$capture_tool ]]; then mv -- "$shim/$capture_tool" "$capture_state/saved-shims/$capture_tool"; fi
done
python3 - "$source_repo/scripts/test-capture.py" "$capture_state" "$shim" "$capture_real_grim" "$nested_socket" "$rt_dir" <<'PY'
import importlib.util, json, os, sys
source, state, shim, grim, display, runtime = sys.argv[1:]
spec = importlib.util.spec_from_file_location("capture_test", source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.plant(module.Path(state), {"real": {"grim": grim}, "display": display, "runtime": runtime, "clipboardHold": True})
for tool in module.TOOLS:
    os.symlink(os.path.join(state, "bin", tool), os.path.join(shim, tool))
PY
capture_read() { ipc smoke readInstance service vgs.capture "$1"; }
capture_phase() { capture_read phase | py_reply 'import json,sys; print(json.load(sys.stdin))'; }
capture_outputs() { capture_read outputs | py_reply 'import json,sys; rows=json.load(sys.stdin); print(rows is not None and any(r["name"] == sys.argv[1] and not r["disabled"] for r in rows))' "$capture_output"; }
capture_path() { capture_read lastPath | py_reply 'import json,sys; print(json.load(sys.stdin))'; }
capture_panel() { ipc smoke readInstance panel vgs.capture recording; }
capture_panel_geometry() { layers_of vgs:panel | py_reply 'import json,sys; rows=json.load(sys.stdin); print(len(rows) == 1 and rows[0][2] > 0 and rows[0][3] > 0)'; }
capture_status() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["status"].get("vgs.capture")))'; }
# The service's exclusive recording action, not a compositor session.
capture_recording_actions() { ipc smoke statusValues vgs.capture | py_reply 'import json,sys; s=json.load(sys.stdin)["capture"]; print(int(s["action"].startswith("record") and s["phase"]!="idle"))'; }
capture_recording_counts() { python3 - "$capture_state" "$(capture_recording_actions)" <<'PY'
import json,os,pathlib,sys
root=pathlib.Path(sys.argv[1]); pid=int((root/"owned-recorder").read_text())
try:
    arguments=(pathlib.Path("/proc")/str(pid)/"cmdline").read_bytes().split(b"\0")
except FileNotFoundError:
    arguments=[]
target=(root/"bin/gpu-screen-recorder").resolve()
print(json.dumps({"recorders":int(any(pathlib.Path(os.fsdecode(argument)).resolve()==target for argument in arguments if argument)),"recordingActions":int(sys.argv[2])},sort_keys=True))
PY
}
capture_recording_released() {
  expect_poll "$1: Capture releases its recorder and recording action" '{"recorders": 0, "recordingActions": 0}' capture_recording_counts
  printf 'capture-lifetime: case=%s counts=%s\n' "$1" "$(capture_recording_counts)"
}
# capture_clipboard: the clipboard stand-in's bytes as text. The helper
# reports copied once wl-copy's stdin closes, before the stand-in writes, so
# an earlier image's bytes read as a mismatch to poll past.
capture_clipboard() { python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); print(p.read_bytes().decode(errors="replace") if p.exists() else "absent")' "$capture_state/clipboard"; }
capture_counts() { python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); print(len(list(p.glob("*.png"))))' "$home/Pictures/Screenshots"; }
# capture_cards: Capture's notifications vgs.notifications shows and is not
# taking off, as [summary, ...]; [] while it is not built.
capture_cards() {
  local raw
  raw="$(ipc smoke modelRows vgs.notifications rows app,summary,leaving)" || return 1
  if [[ $raw == absent ]]; then echo '[]'; return; fi
  py_reply 'import json,sys; print(json.dumps([r[1] for r in json.load(sys.stdin) if r[0] == "Capture" and r[2] == ""]))' <<<"$raw"
}
# capture_card_count: how many Capture cards vgs.notifications shows and is
# not taking off.
capture_card_count() { capture_cards | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
# A failure notice sent while no plugin holds the notification server is
# dropped and logged by the core.
expected_errors+=('notify: unsent plugin=vgs\.capture ')
# capture_no_card_for: `quiet` when no Capture card shows for 2 s, else the
# count. It reads only while vgs.notifications draws, Silence off: with it
# disabled another server can take a wrongly sent notice unseen.
capture_no_card_for() { local got; for _ in $(seq 1 10); do got="$(capture_card_count)" || return 1; ((got == 0)) || { echo "$got"; return 0; }; sleep 0.2; done; echo quiet; }
# capture_wait_cards: every card dismissed, how many Capture rows are left
# once those taking off have gone, polled as expect_poll polls; 0 while
# vgs.notifications is not built, which draws none.
capture_wait_cards() {
  local raw count=0
  if [[ $(record_exists vgs.notifications) == True ]]; then ipc vgs.notifications invoke dismiss-all '' >/dev/null || return 1; fi
  smoke_poll_tries 200 1
  for _ in $(seq 1 "$smoke_poll_n"); do
    raw="$(ipc smoke modelRows vgs.notifications rows app)" || return 1
    [[ $raw == absent ]] && { count=0; break; }
    count="$(py_reply 'import json,sys; print(sum(1 for r in json.load(sys.stdin) if r[0] == "Capture"))' <<<"$raw")" || return 1
    ((count > 0)) || break
    sleep 0.2
  done
  echo "$count"
}
capture_notice() { ipc smoke noticeDrawn | py_reply 'import json,sys; v=json.load(sys.stdin); print("tesseract" if any("tesseract" in r for r in v["rows"]) else "other")'; }
capture_missing() { capture_read missing | py_reply 'import json,sys; print("tesseract" in json.load(sys.stdin))'; }
capture_workers() { python3 - "$capture_state" <<'PY'
import os
from pathlib import Path
import sys
providers = list(Path(sys.argv[1]).glob("clipboard-ready-*"))
live = False
for provider in providers:
    try:
        os.kill(int(provider.name.removeprefix("clipboard-ready-")), 0)
        live = True
    except ProcessLookupError:
        pass
print(live)
PY
}
capture_released() { python3 - "$capture_state" <<'PY'
from pathlib import Path
import signal, sys
root = Path(sys.argv[1])
providers = list(root.glob("clipboard-ready-*"))
print(bool(providers) and all((root / p.name.replace("clipboard-ready-", "clipboard-signal-")).exists() and (root / p.name.replace("clipboard-ready-", "clipboard-signal-")).read_text() == str(signal.SIGTERM) for p in providers))
PY
}
capture_config() { python3 - "$capture_state/config.json" "$1" "$2" <<'PY'
import json, sys
path, key, value = sys.argv[1:]
doc = json.load(open(path))
doc[key] = json.loads(value)
with open(path, "w") as output:
    json.dump(doc, output)
PY
}
capture_png() { python3 - "$capture_state" "$capture_output" "$capture_width" "$capture_height" "$(capture_path)" <<'PY'
import json, pathlib, struct, sys
state, output, width, height, path = sys.argv[1:]
root = pathlib.Path(state)
file = pathlib.Path(path)
if not file.is_file():
    print("absent")
else:
    data = file.read_bytes()
    calls = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]
    grim = [c["args"] for c in calls if c["tool"] == "grim"][-1]
    clipboard = root / "clipboard"
    print(data[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", data[16:24]) == (int(width), int(height)) and grim[:2] == ["-o", output] and clipboard.read_bytes() == data)
PY
}
# capture_left: how many slurp and hyprpicker processes the row's captures
# started still run. Each stand-in records its pid before it runs or execs.
capture_left() { python3 - "$capture_state" <<'PY'
import os, sys
from pathlib import Path
left = 0
for marker in [*Path(sys.argv[1]).glob("slurp-pid-*"), *Path(sys.argv[1]).glob("hyprpicker-pid-*")]:
    try:
        os.kill(int(marker.name.rsplit("-", 1)[1]), 0)
    except ProcessLookupError:
        continue
    left += 1
print(left)
PY
}
# capture_selecting: True once the real slurp's selection layer maps above the
# hyprpicker freeze, False when it has not after 3 s.
capture_selecting() {
  local i
  for i in $(seq 1 30); do
    if [[ $(layer_count selection) == 1 && $(layer_count hyprpicker) == 1 ]]; then echo True; return; fi
    sleep 0.1 # each tool maps its layer on its own schedule, with no event to wait on
  done
  echo False
}
# capture_area_png: grim's geometry for the dragged box, the saved PNG's size
# and whether the clipboard holds the same bytes.
capture_area_png() { python3 - "$capture_state" "$(capture_path)" <<'PY'
import json, pathlib, struct, sys
root, path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
rows = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]
grim = [row["args"] for row in rows if row["tool"] == "grim"][-1]
data = path.read_bytes() if path.is_file() else b""
size = "%dx%d" % struct.unpack(">II", data[16:24]) if data[:8] == b"\x89PNG\r\n\x1a\n" else "none"
print(grim[:2], size, "clipboard=%s" % ((root / "clipboard").read_bytes() == data))
PY
}
# capture_recorder_left: whether the last recorder stand-in still runs.
capture_recorder_left() { python3 -c 'import os,pathlib,sys
pid = int((pathlib.Path(sys.argv[1]) / "recorder-ready").read_text())
try:
    os.kill(pid, 0)
except ProcessLookupError:
    print(False)
else:
    print(True)' "$capture_state"; }
capture_geometry() { python3 -c 'import json,sys; rows=[json.loads(l) for l in open(sys.argv[1])]; a=[r["args"] for r in rows if r["tool"]=="grim"][-1]; print(a[a.index("-g"):a.index("-g")+2] if "-g" in a else a[:2])' "$capture_state/calls.jsonl"; }
capture_setting_value() { capture_read settings | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]]))' "$1"; }
capture_setting() {
  local payload
  payload="$(python3 -c 'import json,sys; print(json.dumps({"key":sys.argv[1],"value":json.loads(sys.argv[2])}))' "$1" "$2")" || return 1
  expect "capture setting $1 is accepted" ok ipc vgs.capture invoke setting "$payload"
  expect_poll "capture setting $1 reaches its service" "$2" capture_setting_value "$1"
}
capture_image_box() { python3 - "$capture_state" "$(capture_path)" "$1" <<'PY'
import json, pathlib, struct, sys
root, path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
expected = sys.argv[3]
rows = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]
grims = [r["args"] for r in rows if r["tool"] == "grim"]
args = grims[-1] if grims else []
data = path.read_bytes() if path.is_file() else b""
size = tuple(map(int, expected.split()[1].split("x")))
print("-g" in args and args[args.index("-g") + 1] == expected and data[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", data[16:24]) == size and (root / "clipboard").read_bytes() == data)
PY
}
capture_copy_only() { python3 - "$capture_state" "$home/Pictures/Screenshots" "$capture_before" <<'PY'
from pathlib import Path
import sys
root, folder, before = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3])
data = (root / "clipboard").read_bytes()
print(data.startswith(b"\x89PNG\r\n\x1a\n") and len(list(folder.glob("*.png"))) == before)
PY
}
capture_save_only() { python3 - "$capture_state" "$(capture_path)" "$home/Pictures/Screenshots" "$capture_before" <<'PY'
from pathlib import Path
import sys
root, image, folder, before = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), int(sys.argv[4])
print(image.is_file() and image.read_bytes().startswith(b"\x89PNG\r\n\x1a\n") and (root / "clipboard").read_bytes() == b"previous clipboard" and len(list(folder.glob("*.png"))) == before + 1)
PY
}
capture_cursor_flag() { python3 - "$capture_state/calls.jsonl" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1])]
args = [r["args"] for r in rows if r["tool"] == "grim"][-1]
print("-c" in args)
PY
}
capture_clipboard_digest() { python3 -c 'import hashlib,pathlib,sys; print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())' "$capture_state/clipboard"; }
capture_delay_elapsed() { python3 - "$(capture_path)" "$capture_delay_started" "$1" <<'CONTROL'
from pathlib import Path
import sys
path = Path(sys.argv[1])
print(path.is_file() and path.stat().st_mtime - float(sys.argv[2]) >= float(sys.argv[3]))
CONTROL
}
capture_grim_past_limit() { python3 - "$capture_state/grim-ready" <<'CONTROL'
from pathlib import Path
import sys, time
path = Path(sys.argv[1])
print(path.is_file() and time.time() - path.stat().st_mtime >= 2)
CONTROL
}
capture_delay_held() { [[ $(capture_phase) == delaying && $(capture_counts) == "$capture_before" ]] && echo True || echo False; }
capture_countdown() { capture_read remaining | py_reply 'import json,sys; v=json.load(sys.stdin); print(isinstance(v,int) and v > 0)'; }
capture_fresh_frame() { python3 - "$(capture_path)" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
print(path.is_file() and path.read_bytes().endswith(b"after countdown"))
PY
}
capture_grim_left() { python3 - "$capture_state" <<'PY'
import os, sys
from pathlib import Path
left = 0
for marker in Path(sys.argv[1]).glob("grim-pid-*"):
    try:
        os.kill(int(marker.name.rsplit("-", 1)[1]), 0)
    except ProcessLookupError:
        continue
    left += 1
print(left)
PY
}
capture_timeout_clean() { [[ $(capture_phase) == idle && $(capture_counts) == "$capture_before" && $(capture_grim_left) == 0 ]] && echo True || echo False; }
capture_marker() { [[ -f $capture_state/$1 ]] && echo True || echo False; }
capture_active_address() { hypr -j activewindow | py_reply 'import json,sys; print(json.load(sys.stdin).get("address", ""))'; }
capture_crop_hash() { python3 - "$imagemagick" "$1" "$2" "$3" "$4" <<'PY'
import hashlib, subprocess, sys
program, image, crop, width, height = sys.argv[1:]
result = subprocess.run([program, image, "-crop", crop, "+repage", "-depth", "8", "rgb:-"], check=True, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE)
assert len(result.stdout) == int(width) * int(height) * 3, "capture crop must contain all RGB pixels"
print(hashlib.sha256(result.stdout).hexdigest())
PY
}
capture_cursor_width() { ipc smoke instanceGeometry "$(bar_key)" vgs.capture | py_reply 'import json,sys; print(json.load(sys.stdin)[2])'; }
capture_cursor_position() {
  hover "$capture_cursor_inside" "$capture_cursor_y" || return 1
  expect_poll "the flat cursor fixture holds the priming pointer" true ipc smoke popupRead capture-cursor hovering
  hover "$capture_cursor_gap_x" "$capture_cursor_gap_y" || return 1
  expect_poll "the adjacent bar gap requests a fresh arrow" default cursor_shape
  expect_cursor_at "the flat fixture requests a fresh hand bitmap" pointer "$1" "$capture_cursor_y"
  hover "$1" "$capture_cursor_y" || return 1
  expect_poll "the flat cursor fixture holds the capture pointer" true ipc smoke popupRead capture-cursor hovering
}
capture_cursor_geometry() {
  local previous="" current="" i
  for i in $(seq 1 50); do
    current="$(ipc smoke instanceGeometry "$(bar_key)" vgs.capture)" || return 1
    if [[ $current == \[* && $current == "$previous" ]]; then echo "$current"; return; fi
    previous="$current"
    sleep 0.1
  done
  printf 'capture: cursor-geometry=unsettled value=%s\n' "$current" >&2
  return 1
}
capture_cursor_setup() {
  local rect x y width height
  capture_setting cursor true
  expect "capture notices leave the cursor baseline" 0 capture_wait_cards
  python3 - "$sandbox/capture-cursor.qml" "$sandbox" <<'PY'
from pathlib import Path
import sys
fixture, sandbox = map(Path, sys.argv[1:])
assert fixture.parent.resolve().is_relative_to(sandbox.resolve()), "cursor fixture must stay in the sandbox"
fixture.write_text('''import QtQuick
import QtQuick.Templates as T
Rectangle {
    x: 0
    y: 0
    width: 160
    height: parent.height
    z: 1000
    color: "#334455"
    property Item owner: null
    property Item button: null
    readonly property bool hovering: pointer.hovered
    Component.onCompleted: {
        owner = parent;
        // BarWidget owns a Loader before the plugin's button.
        button = owner.children.find(child => child instanceof T.AbstractButton);
        owner.implicitWidth = 160;
    }
    Component.onDestruction: {
        const original = button;
        if (owner !== null && original !== null)
            owner.implicitWidth = Qt.binding(() => original.implicitWidth);
    }
    HoverHandler { id: pointer; cursorShape: Qt.PointingHandCursor }
}
''')
PY
  expect "the flat hand-cursor fixture builds on the bar" ok ipc smoke popupLoad capture-cursor "$sandbox/capture-cursor.qml" "$(bar_key)" vgs.capture '{}'
  expect_poll "the bar gives the cursor fixture its input width" 160 capture_cursor_width
  rect="$(capture_cursor_geometry)" || return 1
  read -r x y width height < <(python3 -c 'import json,sys; print(*json.loads(sys.argv[1]))' "$rect")
  capture_cursor_inside=$((x + 24))
  capture_cursor_outside=$((x + 124))
  capture_cursor_y=$((y + height / 2))
  capture_cursor_gap_x=$((x - 1))
  capture_cursor_gap_y=$((y + 1))
  capture_cursor_crop="$(python3 -c 'import sys; x,y,h,w,oh=map(int,sys.argv[1:]); left=x+4; top=y+(h-20)//2; assert h>=20 and left>=0 and left+50<=w and top>=0 and top+20<=oh; print("50x20+%d+%d"%(left,top))' "$x" "$y" "$height" "$capture_width" "$capture_height")" || return 1
}
capture_cursor_pair() {
  local moved="${1:-move}"
  expect "capture notices leave the cursor baseline" 0 capture_wait_cards
  capture_cursor_position "$capture_cursor_outside"
  expect "capture takes a scene with the pointer outside its crop" ok ipc vgs.capture invoke screenshot ''
  expect_poll "the cursor baseline finishes" idle capture_phase
  capture_cursor_baseline="$(capture_crop_hash "$(capture_path)" "$capture_cursor_crop" 50 20)" || return 1
  expect "capture notices leave before the cursor image" 0 capture_wait_cards
  if [[ $moved == move ]]; then capture_cursor_position "$capture_cursor_inside"; else capture_cursor_position "$capture_cursor_outside"; fi
  expect "capture takes the second scene with the hand cursor" ok ipc vgs.capture invoke screenshot ''
  expect_poll "the cursor image finishes" idle capture_phase
}
capture_widget_width_restored() {
  local widget button
  widget="$(ipc smoke readInstance "$(bar_key)" vgs.capture implicitWidth)" || return 1
  button="$(ipc smoke readDescendant "$(bar_key)" vgs.capture BarItem implicitWidth)" || return 1
  [[ $widget == "$button" && $widget != 0 ]] && echo True || echo False
}
capture_cursor_release() {
  expect "the flat cursor fixture is released" ok ipc smoke popupDrop capture-cursor
  expect_poll "the cursor fixture restores the capture button's width" True capture_widget_width_restored
}
capture_cursor_changed() {
  local current
  current="$(capture_crop_hash "$(capture_path)" "$capture_cursor_crop" 50 20)" || return 1
  [[ $current != "$capture_cursor_baseline" ]] && echo True || echo False
}
capture_recorded() { python3 - "$capture_state" "$(capture_path)" <<'PY'
import json, pathlib, signal, sys
root, path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
rows = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]
stopped = root / "signal"
print(sum(row["tool"] == "gpu-screen-recorder" for row in rows) == 1 and stopped.exists() and stopped.read_text() == str(signal.SIGINT) and path.is_file() and path.read_bytes() == b"finalized")
PY
}
read -r capture_output capture_width capture_height < <(hypr -j monitors | py_reply 'import json,sys; rows=json.load(sys.stdin); m=next(m for m in rows if m["focused"]); print(m["name"],m["width"],m["height"])')
rescan "capture stand-ins are found after rescan"
expect "capture service is enabled" ok ipc shell setPluginEnabled vgs.capture true
expect "capture widget is placed" ok ipc shell setPluginPlaced vgs.capture true
capture_notes_found="$(record_exists vgs.notifications)"
expect_poll "capture service is built" True record_exists vgs.capture
expect_poll "capture is idle" idle capture_phase
expect_poll "capture has the focused nested output" True capture_outputs
expect "capture takes the focused output" ok ipc vgs.capture invoke screenshot ''
expect_poll "capture finishes the screenshot" idle capture_phase
expect_poll "screenshot equals the output mode and clipboard bytes" True capture_png
expect_poll "the completed screenshot keeps its clipboard provider alive" True capture_workers
expect "capture takes the selected area" ok ipc vgs.capture invoke screenshot-area ''
expect_poll "capture finishes the selected area" idle capture_phase
expect "area geometry reaches grim unchanged" "['-g', '10,20 80x60']" capture_geometry
# A background group tab remains mapped and unhidden. Only the drawn tab
# may reach the selector, even though both tabs have the same rectangle.
open_toplevel "$sandbox/capture-group-one.log" smoke.capture-group "Capture group one" || fail "capture: the first group tab did not map"
capture_group_one_pid="$toplevel_pid"
capture_group_one="$(toplevel_address "$capture_group_one_pid")"
expect "the first capture tab receives focus" ok hypr dispatch "hl.dsp.focus({ window = \"address:$capture_group_one\" })"
expect "the first capture tab becomes a group" ok hypr dispatch "hl.dsp.group.toggle({ window = \"address:$capture_group_one\" })"
open_toplevel "$sandbox/capture-group-two.log" smoke.capture-group "Capture group two" || fail "capture: the second group tab did not map"
capture_group_two_pid="$toplevel_pid"
capture_group_two="$(toplevel_address "$capture_group_two_pid")"
expect "the second capture tab stays current" ok hypr dispatch "hl.dsp.focus({ window = \"address:$capture_group_two\" })"
capture_group_state() { hypr -j clients | py_reply 'import json,sys
rows=json.load(sys.stdin)
a=next(r for r in rows if r["address"]==sys.argv[1]); b=next(r for r in rows if r["address"]==sys.argv[2])
print(set(a["grouped"])=={a["address"],b["address"]} and set(b["grouped"])=={a["address"],b["address"]} and a["mapped"] and b["mapped"] and not a["hidden"] and not b["hidden"] and not a["visible"] and b["visible"] and a["at"]==b["at"] and a["size"]==b["size"])' "$capture_group_one" "$capture_group_two"; }
capture_group_advertised() {
  local clients
  clients="$(hypr -j clients)" || return 1
  python3 - "$capture_state/slurp-input" "$clients" "$capture_group_one" "$capture_group_two" <<'PY'
from pathlib import Path
import json, sys
path = Path(sys.argv[1])
rows = json.loads(sys.argv[2])
a = next(row for row in rows if row["address"] == sys.argv[3])
b = next(row for row in rows if row["address"] == sys.argv[4])
rectangle = "%d,%d %dx%d" % (*b["at"], *b["size"])
print(a["at"] == b["at"] and a["size"] == b["size"] and not a["visible"] and b["visible"] and path.is_file() and path.read_text().splitlines().count(rectangle) == 1)
PY
}
expect_poll "capture's group has one drawn and one mapped background tab" True capture_group_state
for capture_group_action in screenshot-area screenshot-window; do
  rm -f -- "${capture_state:?}/slurp-input"
  expect "capture selects the current group tab through $capture_group_action" ok ipc vgs.capture invoke "$capture_group_action" ''
  expect_poll "the $capture_group_action group selection finishes" idle capture_phase
  expect "the $capture_group_action offers the drawn group rectangle once" True capture_group_advertised
  expect "the $capture_group_action leaves the group tab unchanged" True capture_group_state
done
capture_group_service="$repo/shell/plugins/vgs.capture/Service.qml"
expect "capture stops before the group-tab visibility control" ok ipc shell setPluginEnabled vgs.capture false
expect_poll "the group-tab control releases the original service" False record_exists vgs.capture
python3 - "$capture_group_service" "$sandbox" "$capture_state/group-service-original.qml" <<'PY'
from pathlib import Path
import sys
service, sandbox, original = map(Path, sys.argv[1:])
assert service.resolve().is_relative_to(sandbox.resolve()), "group-tab control must stay inside the sandbox"
source = service.read_text()
original.write_text(source)
before = " && shell.compositor.onScreen(window, monitors)"
assert source.count(before) == 1, "group-tab visibility control match"
changed = source.replace(before, "")
assert changed != source
service.write_text(changed)
PY
rescan "the dropped group-tab visibility check is rescanned"
expect "capture enables the group-tab visibility control" ok ipc shell setPluginEnabled vgs.capture true
expect_poll "the group-tab visibility control is built" True record_exists vgs.capture
for capture_group_action in screenshot-area screenshot-window; do
  expect "control: the background tab remains a mapped hidden-false tab" True capture_group_state
  rm -f -- "${capture_state:?}/slurp-input"
  expect "control: $capture_group_action runs without the on-screen check" ok ipc vgs.capture invoke "$capture_group_action" ''
  expect_poll "control: the $capture_group_action group selection finishes" idle capture_phase
  expect "control: advertising the background tab fails the $capture_group_action rectangle readback" False capture_group_advertised
  expect "control: the $capture_group_action keeps the same group tab current" True capture_group_state
done
expect "capture stops after the group-tab visibility control" ok ipc shell setPluginEnabled vgs.capture false
expect_poll "the group-tab visibility control releases its service" False record_exists vgs.capture
cp -- "$capture_state/group-service-original.qml" "$capture_group_service"
rescan "the original group-tab visibility check is rescanned"
expect "capture enables the restored group-tab service" ok ipc shell setPluginEnabled vgs.capture true
expect_poll "the restored group-tab service is built" True record_exists vgs.capture
close_toplevel "$capture_group_two_pid" "capture's current group tab closes"
close_toplevel "$capture_group_one_pid" "capture's background group tab closes"
capture_before="$(capture_counts)"
# The cancel readings need vgs.notifications drawing with Silence off; it
# goes back to the state the row found after them.
expect "notifications are enabled for the cancel readings" ok ipc shell setPluginEnabled vgs.notifications true
expect_poll "the notifications service is built for the cancel readings" True record_exists vgs.notifications
expect_poll "the notifications loaded their state with Silence off for the cancel readings" True notes_quiet
expect "earlier capture notices expire before cancellation" 0 capture_wait_cards
capture_config cancel true
expect "capture accepts an area selection that is cancelled" ok ipc vgs.capture invoke screenshot-area ''
expect_poll "cancelled selection leaves capture idle" idle capture_phase
expect "cancelled selection writes no file" "$capture_before" capture_counts
expect "cancelled selection posts no notice" quiet capture_no_card_for
capture_config cancel false
capture_config escape true
expect "capture accepts an area selection that Escape ends" ok ipc vgs.capture invoke screenshot-area ''
expect_poll "Escape leaves capture idle" idle capture_phase
expect "Escape writes no file" "$capture_before" capture_counts
expect "Escape posts no notice" quiet capture_no_card_for
capture_config escape false
if [[ $capture_notes_found != True ]]; then
  expect "notifications go back to disabled after the cancel readings" ok ipc shell setPluginEnabled vgs.notifications false
  expect_poll "the notifications service is gone after the cancel readings" False record_exists vgs.notifications
fi
capture_config real "{\"grim\": \"$capture_real_grim\", \"slurp\": \"$capture_real_slurp\", \"hyprpicker\": \"$capture_real_picker\"}"
: >"$capture_state/calls.jsonl"
expect "capture starts a real area selection" ok ipc vgs.capture invoke screenshot-area ''
expect "the selection maps above the freeze" True capture_selecting
drag 100 100 300 250 || fail "capture: the area drag failed"
expect_poll "the dragged area finishes" idle capture_phase
expect_poll "the dragged box is saved and copied" "['-g', '100,100 201x151'] 201x151 clipboard=True" capture_area_png
expect_poll "the dragged area leaves no selector or freeze" 0 capture_left
expect_poll "the dragged area unmaps the selection" 0 layer_count selection
capture_before="$(capture_counts)"
expect "capture starts a real selection for Escape" ok ipc vgs.capture invoke screenshot-area ''
expect "the Escape selection maps" True capture_selecting
type_keys -k Escape || fail "capture: Escape could not be typed"
expect_poll "Escape on the real selector leaves capture idle" idle capture_phase
expect_poll "Escape leaves no selector or freeze" 0 capture_left
expect "capture starts a real selection for a second press" ok ipc vgs.capture invoke screenshot-area ''
expect "the second-press selection maps" True capture_selecting
expect "a second press of the same key cancels" ok ipc vgs.capture invoke screenshot-area ''
expect_poll "the second press leaves capture idle" idle capture_phase
expect_poll "the second press leaves no selector or freeze" 0 capture_left
expect "cancelled real selections write no file" "$capture_before" capture_counts
# SUPER+SHIFT+S from any state: the real key on the real selector. slurp
# 1.5.0 takes every pointer button as a selection, so without the layer's
# vgs:selection submap a right click on a bare desktop selected the output
# box and saved it. A typed key reaches its bind only by keysym, so the
# option is on until the readings put the harness hyprland.lua back.
capture_press() { type_keys -M logo -M shift -k s -m shift -m logo; }
hypr_lua_save capture
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$home/.config/hypr/hyprland.lua"
expect "the nested instance reloads with typed keys reaching binds" ok hypr reload config-only
expect "notifications are enabled for the key readings" ok ipc shell setPluginEnabled vgs.notifications true
expect_poll "the notifications service is built for the key readings" True record_exists vgs.notifications
expect_poll "the notifications loaded their state with Silence off for the key readings" True notes_quiet
expect "earlier capture notices expire before the key readings" 0 capture_wait_cards
capture_before="$(capture_counts)"
for capture_round in first second; do
  capture_press || fail "capture: SUPER+SHIFT+S could not be typed"
  expect "SUPER+SHIFT+S opens the $capture_round selector" True capture_selecting
  right_click "$((mon_w / 2))" "$((mon_h / 2))" || fail "capture: the right click failed"
  expect_poll "the $capture_round right click leaves capture idle" idle capture_phase
  expect_poll "the $capture_round right click leaves no selector or freeze" 0 capture_left
done
expect "right-click cancels write no file" "$capture_before" capture_counts
expect "right-click cancels post no notice" quiet capture_no_card_for
for capture_round in first second; do
  capture_press || fail "capture: SUPER+SHIFT+S could not be typed"
  expect "SUPER+SHIFT+S opens the selector for the $capture_round key cancel" True capture_selecting
  capture_press || fail "capture: SUPER+SHIFT+S could not be typed over the selector"
  expect_poll "the $capture_round key cancel leaves capture idle" idle capture_phase
  expect_poll "the $capture_round key cancel leaves no selector or freeze" 0 capture_left
done
expect "key cancels write no file" "$capture_before" capture_counts
expect "key cancels post no notice" quiet capture_no_card_for
: >"$capture_state/calls.jsonl"
capture_press || fail "capture: SUPER+SHIFT+S could not be typed"
expect "SUPER+SHIFT+S opens a selector after the cancels" True capture_selecting
drag 100 100 300 250 || fail "capture: the area drag after the cancels failed"
expect_poll "the capture after the cancels finishes" idle capture_phase
expect_poll "the capture after the cancels saves its box" "['-g', '100,100 201x151'] 201x151 clipboard=True" capture_area_png
capture_before="$(capture_counts)"
expect "earlier capture notices expire before the right-click control" 0 capture_wait_cards
capture_press || fail "capture: SUPER+SHIFT+S could not be typed for the right-click control"
expect "control: the right-click selector maps" True capture_selecting
expect "control: the selection submap is left by hand" ok hypr dispatch 'hl.dsp.submap("reset")'
right_click "$((mon_w / 2))" "$((mon_h / 2))" || fail "capture: the control right click failed"
expect_poll "control: the right click without the selection submap finishes" idle capture_phase
expect_poll "control: a right click slurp reads saves a file" "$((capture_before + 1))" capture_counts
expect "earlier capture notices expire before the busy-worker control" 0 capture_wait_cards
# The worker the service starts reads the sandbox copy at each run.
capture_helper="$repo/shell/plugins/vgs.capture/helper/capture.py"
cp -- "$capture_helper" "$capture_state/helper-original.py"
python3 - "$capture_helper" "$sandbox" <<'PY'
from pathlib import Path
import sys
helper, sandbox = map(Path, sys.argv[1:])
assert helper.resolve().is_relative_to(sandbox.resolve()), "busy-worker control must stay inside the sandbox"
source = helper.read_text()
before = "            if self.cancelled(0.05):\n"
assert source.count(before) == 1, "busy-worker control match"
helper.write_text(source.replace(before, "            if False:\n"))
PY
capture_press || fail "capture: SUPER+SHIFT+S could not be typed for the busy-worker control"
expect "control: the busy-worker selector maps" True capture_selecting
capture_press || fail "capture: SUPER+SHIFT+S could not be typed over the busy-worker selector"
expect "control: a worker that ignores the key cancel stays busy" capturing capture_phase
cp -- "$capture_state/helper-original.py" "$capture_helper"
type_keys -k Escape || fail "capture: Escape could not end the busy-worker control"
expect_poll "control: Escape ends the busy worker" idle capture_phase
expect_poll "control: the busy worker leaves no selector or freeze" 0 capture_left
expect "earlier capture notices expire before the surface readings" 0 capture_wait_cards
# The surface readings drag over the display below the bar, where each
# surface draws, and compare the saved image with grim's image of the same
# box with the surface open and with it closed, pixel by pixel.
read -r capture_box_top < <(hypr -j monitors | py_reply 'import json,sys; print(json.load(sys.stdin)[0]["reserved"][1] + 1)')
# slurp counts both drag corners, so the box ends on the bottom row.
capture_surface_box="1,$capture_box_top $((mon_w - 2))x$((mon_h - capture_box_top))"
capture_reference() { "${shell_env[@]}" "$capture_real_grim" -g "$capture_surface_box" "$capture_state/reference-$1.png"; }
# capture_shows OPEN BARE: `shown=<bool> open=<n> bare=<n>`, the pixels of
# the last saved image that differ from reference OPEN and from reference
# BARE by more than 32 in a channel; shown when the image is far nearer the
# open surface than the bare desktop.
capture_shows() { python3 - "$(capture_path)" "$capture_state/reference-$1.png" "$capture_state/reference-$2.png" <<'PY'
import pathlib, struct, sys, zlib
def pixels(path):
    data, pos, idat, head = pathlib.Path(path).read_bytes(), 8, b"", None
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        if kind == b"IHDR": head = struct.unpack(">IIBBBBB", data[pos + 8:pos + 8 + n])
        elif kind == b"IDAT": idat += data[pos + 8:pos + 8 + n]
        pos += 12 + n
    width, height, depth, ctype, _, _, interlace = head
    assert depth == 8 and ctype in (2, 6) and interlace == 0, "png=%d/%d/%d" % (depth, ctype, interlace)
    step = 3 if ctype == 2 else 4
    raw, stride, prev, out = zlib.decompress(idat), width * step, bytearray(width * step), []
    for y in range(height):
        f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a, b, c = (line[i - step] if i >= step else 0), prev[i], (prev[i - step] if i >= step else 0)
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                line[i] = (line[i] + (a if abs(p - a) <= abs(p - b) and abs(p - a) <= abs(p - c) else b if abs(p - b) <= abs(p - c) else c)) & 255
        out.append([tuple(line[x * step:x * step + 3]) for x in range(width)])
        prev = line
    return out
def differ(one, two):
    assert len(one) == len(two) and len(one[0]) == len(two[0]), "sizes differ"
    return sum(1 for r1, r2 in zip(one, two) for p, q in zip(r1, r2) if max(abs(u - v) for u, v in zip(p, q)) > 32)
saved, shown, bare = (pixels(p) for p in sys.argv[1:])
near, far = differ(saved, shown), differ(saved, bare)
print("shown=%s open=%d bare=%d" % (far >= 1000 and near * 10 <= far, near, far))
PY
}
capture_shown_verdict() { capture_shows "$@" | cut -d' ' -f1; }
# A flyout is an xdg_popup holding a grab, and Hyprland ends every seat
# grab when a layer that takes the keyboard maps (v0.56.2 LayerSurface.cpp
# onMap, setGrab(nullptr)): hyprpicker and slurp both do, so the flyout
# closes when the selector maps, and STAYS is False for it.
capture_surface() { # LABEL OPEN_CMD SHOWN_CMD CLOSE_CMD STAYS
  local label="$1" open="$2" shown="$3" close="$4" stays="$5"
  capture_reference "bare-$label" || fail "capture: the bare $label reference failed"
  eval "$open" || fail "capture: the $label could not be opened"
  expect_poll "the $label shows" True eval "$shown"
  sleep 1 # the surface's open animation has no end event the row can read
  capture_reference "open-$label" || fail "capture: the open $label reference failed"
  capture_press || fail "capture: SUPER+SHIFT+S could not be typed over the $label"
  expect "SUPER+SHIFT+S opens a selector over the $label" True capture_selecting
  expect "the selector leaves the $label open: $stays" "$stays" eval "$shown"
  drag 1 "$capture_box_top" "$((mon_w - 2))" "$((mon_h - 1))" || fail "capture: the drag over the $label failed"
  expect_poll "the capture over the $label finishes" idle capture_phase
  expect "the capture leaves the $label open: $stays" "$stays" eval "$shown"
  expect_poll "the capture over the $label shows it" shown=True capture_shown_verdict "open-$label" "bare-$label"
  printf 'capture-surface: surface=%s %s\n' "$label" "$(capture_shows "open-$label" "bare-$label")"
  if [[ $stays == True ]]; then eval "$close" || fail "capture: the $label could not be closed"; fi
  expect_poll "the $label closes" False eval "$shown"
  expect "earlier capture notices expire after the $label" 0 capture_wait_cards
}
capture_notes_shown() { [[ $(ipc smoke instanceGeometry panel vgs.notifications) != absent ]] && echo True || echo False; }
capture_surface "notifications panel" "type_keys -M logo -k n -m logo" capture_notes_shown "type_keys -k Escape" True
expect "System Monitor enables for the flyout reading" ok ipc shell setPluginEnabled vgs.sysmon true
expect "System Monitor places its widget for the flyout reading" ok ipc shell setPluginPlaced vgs.sysmon true
capture_flyout_shown() { [[ $(ipc smoke instanceGeometry panel vgs.sysmon) != absent ]] && echo True || echo False; }
capture_surface "System Monitor flyout" 'click_centre "$(bar_key)" vgs.sysmon' capture_flyout_shown "type_keys -k Escape" False
expect "System Monitor leaves the bar after the flyout reading" ok ipc shell setPluginPlaced vgs.sysmon false
expect "System Monitor disables after the flyout reading" ok ipc shell setPluginEnabled vgs.sysmon false
expect "the launcher enables for its reading" ok ipc shell setPluginEnabled vgs.launcher true
expect_poll "the launcher service is built" True record_exists vgs.launcher
capture_launcher_shown() { [[ $(layer_count vgs:overlay) == 1 ]] && echo True || echo False; }
capture_surface "launcher" "type_keys -M logo -k space -m logo" capture_launcher_shown "type_keys -k Escape" True
expect "the launcher disables after its reading" ok ipc shell setPluginEnabled vgs.launcher false
hypr_lua_restore capture || fail "capture: the harness hyprland.lua could not be put back"
expect "the nested instance reloads the harness hyprland.lua" ok hypr reload config-only
if [[ $capture_notes_found != True ]]; then
  expect "notifications go back to disabled after the key readings" ok ipc shell setPluginEnabled vgs.notifications false
  expect_poll "the notifications service is gone after the key readings" False record_exists vgs.notifications
fi
capture_config real "{\"grim\": \"$capture_real_grim\"}"
# Expected rectangles come from the nested compositor, independently of the
# helper's rectangle list. Both owned windows close before this row exits.
open_toplevel "$sandbox/capture-target.log" smoke.capture-target "Capture target" || fail "capture: the screenshot target did not map"
capture_target_pid="$toplevel_pid"
capture_target_address="$(toplevel_address "$capture_target_pid")"
read -r capture_target_x capture_target_y capture_target_w capture_target_h < <(hypr -j clients | py_reply 'import json,sys; w=next(w for w in json.load(sys.stdin) if w["address"]==sys.argv[1]); print(*w["at"],*w["size"])' "$capture_target_address")
capture_target_box="$capture_target_x,$capture_target_y ${capture_target_w}x${capture_target_h}"
capture_target_cx=$((capture_target_x + capture_target_w / 2))
capture_target_cy=$((capture_target_y + capture_target_h / 2))
read -r capture_display_x capture_display_y capture_display_w capture_display_h < <(hypr -j monitors | py_reply 'import json,sys; m=next(m for m in json.load(sys.stdin) if m["name"]==sys.argv[1]); w,h=m["width"],m["height"]; w,h=(h,w) if m["transform"]%2 else (w,h); print(m["x"],m["y"],int(w/m["scale"]),int(h/m["scale"]))' "$capture_output")
capture_display_box="$capture_display_x,$capture_display_y ${capture_display_w}x${capture_display_h}"
capture_all_box="$(hypr -j monitors | py_reply 'import json,sys; rects=[]
for m in json.load(sys.stdin):
 if m.get("disabled",False): continue
 w,h=m["width"],m["height"]
 if m["transform"]%2: w,h=h,w
 rects.append((m["x"],m["y"],int(w/m["scale"]),int(h/m["scale"])))
l=min(r[0] for r in rects); t=min(r[1] for r in rects); r=max(r[0]+r[2] for r in rects); b=max(r[1]+r[3] for r in rects); print("%d,%d %dx%d"%(l,t,r-l,b-t))')"
capture_config real "{\"grim\": \"$capture_real_grim\", \"slurp\": \"$capture_real_slurp\", \"hyprpicker\": \"$capture_real_picker\"}"
for capture_selection in screenshot-area screenshot-window screenshot-display; do
  : >"$capture_state/calls.jsonl"
  expect "capture starts $capture_selection by click" ok ipc vgs.capture invoke "$capture_selection" ''
  expect "the $capture_selection selector maps" True capture_selecting
  click "$capture_target_cx" "$capture_target_cy" || fail "capture: the selection click failed"
  expect_poll "the $capture_selection click finishes" idle capture_phase
  if [[ $capture_selection == screenshot-display ]]; then capture_expected_box="$capture_display_box"; else capture_expected_box="$capture_target_box"; fi
  expect_poll "the $capture_selection image equals its selected rectangle" True capture_image_box "$capture_expected_box"
  expect_poll "the $capture_selection leaves no selector or freeze" 0 capture_left
done
: >"$capture_state/calls.jsonl"
expect "capture accepts all enabled displays" ok ipc vgs.capture invoke screenshot-all ''
expect_poll "capture finishes all displays" idle capture_phase
expect_poll "all-display image equals the compositor bounding box" True capture_image_box "$capture_all_box"
capture_config real "{\"grim\": \"$capture_real_grim\"}"
capture_cursor_setup
capture_cursor_pair move
expect "the cursor option reaches grim" True capture_cursor_flag
expect "moving the hand cursor into the crop changes delivered pixels" True capture_cursor_changed
capture_cursor_pair stay
expect "control: omitting the cursor move fails the pixel-change readback" False capture_cursor_changed
capture_cursor_release
capture_setting cursor false
capture_setting processing '"copy"'
capture_before="$(capture_counts)"
printf 'previous clipboard' >"$capture_state/clipboard"
expect "capture accepts copy-only processing" ok ipc vgs.capture invoke screenshot ''
expect_poll "copy-only capture finishes" idle capture_phase
expect_poll "copy-only delivers PNG bytes without a Pictures file" True capture_copy_only
capture_setting processing '"save"'
capture_before="$(capture_counts)"
printf 'previous clipboard' >"$capture_state/clipboard"
expect "capture accepts save-only processing" ok ipc vgs.capture invoke screenshot ''
expect_poll "save-only capture finishes" idle capture_phase
expect "save-only keeps the clipboard and writes the PNG" True capture_save_only
python3 - "$shell_host_path" "$sandbox" <<'PY'
from pathlib import Path
import sys
host, sandbox = map(Path, sys.argv[1:])
assert host.resolve().is_relative_to(sandbox.resolve()), "clipboard control must use the sandbox command directory"
assert (host / "wl-copy").is_symlink(), "clipboard control requires the private host-command link"
PY
mv -- "$shell_host_path/wl-copy" "$capture_state/host-wl-copy"
rm -f -- "${shim:?}/wl-copy"
rescan "the missing clipboard command is rescanned for save-only"
capture_missing_clipboard() { capture_read missing | py_reply 'import json,sys; print("wl-copy" in json.load(sys.stdin))'; }
expect_poll "the service reads the missing clipboard command" True capture_missing_clipboard
capture_before="$(capture_counts)"
expect "save-only remains available without the clipboard tool" ok ipc vgs.capture invoke screenshot ''
expect_poll "save-only without the clipboard tool finishes" idle capture_phase
expect "save-only without wl-copy keeps both deliverables correct" True capture_save_only
mv -- "$capture_state/host-wl-copy" "$shell_host_path/wl-copy"
ln -s -- "$capture_state/bin/wl-copy" "$shim/wl-copy"
rescan "the restored clipboard command is rescanned"
expect_poll "the service finds the restored clipboard command" False capture_missing_clipboard
capture_setting processing '"save-copy"'
capture_config geometry "\"$capture_target_cx,$capture_target_cy 1x1\""
expect "smart capture accepts a tiny selected point" ok ipc vgs.capture invoke screenshot-area ''
expect_poll "smart capture finishes the selected point" idle capture_phase
expect "smart capture expands a tiny point to its window" True capture_image_box "$capture_target_box"
capture_setting smart false
expect "plain area capture accepts the same tiny point" ok ipc vgs.capture invoke screenshot-area ''
expect_poll "plain area capture finishes the selected point" idle capture_phase
expect "plain area capture keeps the tiny geometry" True capture_image_box "$capture_target_cx,$capture_target_cy 1x1"
capture_setting smart true
capture_config geometry "\"$capture_display_x,$capture_display_y 1x1\""
expect "smart capture accepts a point outside all windows" ok ipc vgs.capture invoke screenshot-area ''
expect_poll "smart capture finishes the output point" idle capture_phase
expect "smart capture expands an empty desktop point to its output" True capture_image_box "$capture_display_box"
capture_config geometry '"10,20 80x60"'
# A changing token in the fake frame separates the selected frame from the
# image read after the countdown. The real compositor checks stay above.
capture_config real '{}'
capture_config frame '"before countdown"'
capture_setting delay 3
capture_before="$(capture_counts)"
capture_delay_started="$(python3 -c 'import time; print(time.time())')"
expect "capture accepts a delayed area" ok ipc vgs.capture invoke screenshot-area ''
expect_poll "delay begins after the selection" True capture_delay_held
expect "the countdown exposes remaining time" True capture_countdown
expect "the widget shows countdown state" true ipc smoke readInstance "$(bar_key)" vgs.capture delaying
expect_poll "the countdown releases the selector and freeze" 0 capture_left
capture_config frame '"after countdown"'
expect_poll "the delayed screenshot completes" idle capture_phase
expect "the delayed screenshot reads the new frame" True capture_fresh_frame
expect "the delayed screenshot waits for the configured duration" True capture_delay_elapsed 3
for capture_cancel in key widget; do
  capture_before="$(capture_counts)"
  capture_cancel_clipboard="$(capture_clipboard_digest)"
  expect "capture starts a countdown for $capture_cancel cancellation" ok ipc vgs.capture invoke screenshot ''
  expect_poll "the $capture_cancel cancellation reaches the countdown" True capture_delay_held
  if [[ $capture_cancel == key ]]; then
    expect "the same capture action cancels its countdown" ok ipc vgs.capture invoke screenshot ''
  else
    click_centre "$(bar_key)" vgs.capture || fail "capture: the countdown widget could not be clicked"
  fi
  expect_poll "the $capture_cancel cancellation leaves capture idle" idle capture_phase
  expect "the $capture_cancel cancellation writes no file" "$capture_before" capture_counts
  expect "the $capture_cancel cancellation keeps the clipboard" "$capture_cancel_clipboard" capture_clipboard_digest
  expect "the $capture_cancel cancellation removes its countdown" 0 capture_read remaining
done
capture_setting delay 0
capture_config frame '""'
capture_setting timeout 1
capture_config grimHold true
capture_before="$(capture_counts)"
rm -f -- "${capture_state:?}/grim-ready"
expect "capture starts a tool held beyond its time limit" ok ipc vgs.capture invoke screenshot ''
expect_poll "the held screenshot reaches grim" True capture_marker grim-ready
expect_poll "the time limit ends the held capture and owned tool" True capture_timeout_clean
capture_config grimHold false
capture_setting timeout 10
capture_setting delay 0
capture_config slurpRelease true
capture_config real "{\"grim\": \"$capture_real_grim\"}"
rm -f -- "${capture_state:?}/slurp-ready" "${capture_state:?}/slurp-release"
expect "the target receives focus before selection" ok hypr dispatch "hl.dsp.focus({ window = \"address:$capture_target_address\" })"
expect_poll "capture reads its focus target" "$capture_target_address" capture_active_address
expect "capture starts a held selector for focus restoration" ok ipc vgs.capture invoke screenshot-area ''
expect_poll "the held selector is ready" True capture_marker slurp-ready
open_toplevel "$sandbox/capture-disturbance.log" smoke.capture-disturbance "Capture disturbance" || fail "capture: the focus disturbance did not map"
capture_disturbance_pid="$toplevel_pid"
capture_disturbance_address="$(toplevel_address "$capture_disturbance_pid")"
expect_poll "the second window changes focus during selection" "$capture_disturbance_address" capture_active_address
touch -- "$capture_state/slurp-release"
expect_poll "the held selection finishes" idle capture_phase
expect_poll "selection restores the still-open window's focus" "$capture_target_address" capture_active_address
capture_config slurpRelease false
expect "capture recognizes selected text" ok ipc vgs.capture invoke text ''
expect_poll "capture finishes text recognition" idle capture_phase
expect_poll "text reaches the clipboard" "Nested capture text" capture_clipboard
capture_config holdFinalize true
expect "capture starts one recorder" ok ipc vgs.capture invoke record ''
expect_poll "capture publishes recording" recording capture_phase
expect_poll "widget shows the recording indicator" true ipc smoke readInstance "$(bar_key)" vgs.capture recording
expect "a second record call stops the owned recorder" ok ipc vgs.capture invoke record ''
expect "capture holds stopping until finalization" stopping capture_phase
expect "widget keeps its recording indicator during finalization" true ipc smoke readInstance "$(bar_key)" vgs.capture recording
touch -- "$capture_state/finalize-release"
expect_poll "capture waits for recorder finalization" idle capture_phase
expect "SIGINT finalized the single recorder's file" True capture_recorded
expect "the stopped recording leaves no recorder" False capture_recorder_left
capture_config holdFinalize false
: >"$capture_state/calls.jsonl"
rm -f -- "$capture_state/signal"
expect "capture starts another owned recording" ok ipc vgs.capture invoke record ''
expect_poll "the second recording is active" recording capture_phase
# The old cursor teardown collapsed the widget to its inherited Loader's
# width. Keep that defect in a disposable copy to prove the width readback
# rejects it.
capture_cursor_control="$(mktemp -d "$sandbox/capture-cursor-control.XXXXXX")"
python3 - "$sandbox/capture-cursor.qml" "$capture_cursor_control/Item.qml" <<'PY'
from pathlib import Path
import sys
source, control = map(Path, sys.argv[1:])
original = source.read_text()
before = "button = owner.children.find(child => child instanceof T.AbstractButton);"
after = "button = false ? owner.children.find(child => child instanceof T.AbstractButton) : owner.children[0];"
assert original.count(before) == 1, "cursor teardown control match"
changed = original.replace(before, after)
assert changed != original
control.write_text(changed)
PY
expect "control: the cursor teardown copy builds" ok ipc smoke popupLoad capture-cursor-control "$capture_cursor_control/Item.qml" "$(bar_key)" vgs.capture '{}'
expect_poll "control: the cursor copy takes its input width" 160 capture_cursor_width
expect "control: the cursor teardown copy is released" ok ipc smoke popupDrop capture-cursor-control
expect_poll "control: the inherited child fails the restored-width readback" False capture_widget_width_restored
expect "the correct cursor teardown builds after its control" ok ipc smoke popupLoad capture-cursor "$sandbox/capture-cursor.qml" "$(bar_key)" vgs.capture '{}'
expect_poll "the restored cursor fixture takes its input width" 160 capture_cursor_width
capture_cursor_release
# A disposable copy lays a mouse area over the whole widget, so the click
# lands on the shield and never reaches the button. The stop readings must
# fail on that click.
capture_cursor_shield="$(mktemp -d "$sandbox/capture-cursor-shield.XXXXXX")"
python3 - "$sandbox/capture-cursor.qml" "$capture_cursor_shield/Item.qml" <<'PY'
from pathlib import Path
import sys
source, control = map(Path, sys.argv[1:])
original = source.read_text()
before = "    HoverHandler { id: pointer; cursorShape: Qt.PointingHandCursor }\n"
after = before + "    MouseArea { anchors.fill: parent }\n"
assert original.count(before) == 1, "click shield control match"
changed = original.replace(before, after)
assert changed != original
control.write_text(changed)
PY
expect "control: the click shield copy builds" ok ipc smoke popupLoad capture-cursor-shield "$capture_cursor_shield/Item.qml" "$(bar_key)" vgs.capture '{}'
expect_poll "control: the shield copy takes its input width" 160 capture_cursor_width
click_centre "$(bar_key)" vgs.capture || fail "control: the shielded recording widget could not be clicked"
expect "control: the shielded click fails the idle stop readback" recording capture_phase
expect "control: the shielded click leaves the owned recorder running" True capture_recorder_left
expect "control: the shielded click fails the finalized-file readback" False capture_recorded
expect "control: the click shield copy is released" ok ipc smoke popupDrop capture-cursor-shield
expect_poll "the shield copy's teardown restores the capture button's width" True capture_widget_width_restored
click_centre "$(bar_key)" vgs.capture || fail "the recording widget could not be clicked"
expect_poll "clicking the recording widget stops capture" idle capture_phase
expect_poll "the widget stop finalizes the owned recorder's file" True capture_recorded
expect "the widget stop leaves no recorder" False capture_recorder_left
expect "the widget clears its recording indicator after finalization" false ipc smoke readInstance "$(bar_key)" vgs.capture recording
# The panel opens on its primary action. Shift+Tab reaches the target tiles
# and then the mode switch; an arrow choice on either changes the action the
# primary button hands the service, and the mode its text. A press starts
# the panel's action, which a delay holds in its countdown until the same
# action cancels it. Each panel copy below plants the defects its readings
# must fail on and is rebuilt as the service copies above are.
# capture_is READER EXPECTED: True when READER prints EXPECTED.
capture_is() { [[ "$($1)" == "$2" ]] && echo True || echo False; }
capture_focus() { ipc smoke focused panel vgs.capture | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)))'; }
capture_focus_type() { ipc smoke focused panel vgs.capture | py_reply 'import json,sys; print(json.load(sys.stdin)[0])'; }
capture_primary() { ipc smoke readInstance panel vgs.capture primaryActionName | py_reply 'import json,sys; print(json.load(sys.stdin))'; }
capture_choice() { ipc smoke readDescendant panel vgs.capture "$1" currentIndex; }
capture_action() { capture_read action | py_reply 'import json,sys; print(json.load(sys.stdin))'; }
capture_back() { type_keys -M shift -k Tab -m shift || fail "capture: sending Shift+Tab to the panel failed"; }
capture_key() { type_keys -k "$1" || fail "capture: sending $1 to the panel failed"; }
capture_shot_initial='["Button", "Take screenshot", false, false, true]'
capture_shot_focus='["Button", "Take screenshot", true, true, true]'
capture_record_focus='["Button", "Start recording", true, true, true]'
capture_panel_file="$repo/shell/plugins/vgs.capture/Panel.qml"
capture_panel_plant() { # walk | focus | original
  expect "capture stops before the $1 panel copy" ok ipc shell setPluginEnabled vgs.capture false
  expect_poll "the $1 panel copy releases the service" False record_exists vgs.capture
  python3 - "$capture_panel_file" "$sandbox" "$rt_dir" "$capture_state/panel-original.qml" "$1" <<'PY'
from pathlib import Path
import sys
panel, sandbox, runtime, original, control = sys.argv[1:]
panel, original = Path(panel), Path(original)
assert any(panel.resolve().is_relative_to(Path(root).resolve()) for root in (sandbox, runtime)), "panel control must stay inside the sandbox or its private runtime"
if not original.exists():
    original.write_text(panel.read_text())
source = original.read_text()
changes = {
    "walk": [
        ("onActivated: index => root.chooseMode(index)", "onActivated: index => {}"),
        ("onActivated: index => root.chooseTarget(index)", "onActivated: index => {}"),
        ("onClicked: root.invoke(root.primaryActionName)", 'onClicked: root.invoke("screenshot")'),
    ],
    "focus": [("property Item initialFocus: primaryAction", "property Item initialFocus: modeSwitch")],
    "original": [],
}
changed = source
for before, after in changes[control]:
    assert changed.count(before) == 1, control + ": " + before
    changed = changed.replace(before, after)
assert control == "original" or changed != source, control
panel.write_text(changed)
PY
  rescan "the $1 panel copy is rescanned"
  expect "capture enables the $1 panel copy" ok ipc shell setPluginEnabled vgs.capture true
  expect_poll "the $1 panel copy's service is built" True record_exists vgs.capture
}
capture_setting delay 3
expect "capture opens its panel" ok ipc vgs.capture invoke toggle ''
expect_poll "capture panel maps" false capture_panel
expect_poll "capture panel has a drawn layer with geometry" True capture_panel_geometry
expect_poll "the panel opens on Take screenshot without its ring" "$capture_shot_initial" capture_focus
expect "the primary action screenshots an area" screenshot-area capture_primary
capture_back
expect_poll "Shift+Tab reaches the target tiles" TileGroup capture_focus_type
capture_key Right
expect_poll "Right chooses the Window tile" 1 capture_choice TileGroup
expect "the Window tile makes the primary action a window screenshot" screenshot-window capture_primary
capture_back
expect_poll "Shift+Tab reaches the mode switch" SegmentedControl capture_focus_type
capture_key Right
expect_poll "Right chooses Record" 1 capture_choice SegmentedControl
expect "Record makes the primary action an area recording" record capture_primary
capture_key Tab
capture_key Tab
expect_poll "Tab returns to the primary action" Button capture_focus_type
expect "Record names the primary action Start recording" "$capture_record_focus" capture_focus
capture_back
capture_back
expect_poll "Shift+Tab reaches the mode switch again" SegmentedControl capture_focus_type
capture_key Left
expect_poll "Left chooses Screenshot" 0 capture_choice SegmentedControl
capture_key Tab
capture_key End
expect_poll "End chooses the All tile" 3 capture_choice TileGroup
expect "the All tile makes the primary action an all-displays screenshot" screenshot-all capture_primary
capture_key Tab
expect_poll "Tab reaches the primary action" Button capture_focus_type
capture_pressed="$(capture_primary)"
capture_key Return
expect_poll "the pressed primary action reaches its countdown" delaying capture_phase
expect "the press starts the panel's own action" "$capture_pressed" capture_action
expect_poll "the started action closes the panel" absent capture_panel
expect "the same action cancels the panel's countdown" ok ipc vgs.capture invoke "$(capture_action)" ''
expect_poll "the cancelled countdown leaves capture idle" idle capture_phase
capture_panel_plant walk
expect "capture opens the walk copy's panel" ok ipc vgs.capture invoke toggle ''
expect_poll "control: the walk copy opens on Take screenshot" "$capture_shot_initial" capture_focus
capture_back
expect_poll "control: Shift+Tab reaches the walk copy's tiles" TileGroup capture_focus_type
capture_key Right
expect_poll "control: Right moves the walk copy's tiles" 1 capture_choice TileGroup
expect "control: a tile choice the panel drops fails the window-screenshot readback" False capture_is capture_primary screenshot-window
capture_back
expect_poll "control: Shift+Tab reaches the walk copy's mode switch" SegmentedControl capture_focus_type
capture_key Right
expect_poll "control: Right moves the walk copy's mode switch" 1 capture_choice SegmentedControl
expect "control: a mode choice the panel drops fails the area-recording readback" False capture_is capture_primary record
capture_key Tab
capture_key Tab
expect_poll "control: Tab returns to the walk copy's primary action" Button capture_focus_type
expect "control: a mode choice the panel drops fails the Start recording readback" False capture_is capture_focus "$capture_record_focus"
capture_pressed="$(capture_primary)"
capture_key Return
expect_poll "control: the walk copy's press reaches a countdown" delaying capture_phase
expect "control: a press of another action fails the pressed-action readback" False capture_is capture_action "$capture_pressed"
expect "control: the walk copy's action cancels its countdown" ok ipc vgs.capture invoke "$(capture_action)" ''
expect_poll "control: the walk copy's countdown leaves capture idle" idle capture_phase
expect_poll "control: the walk copy's panel closes" absent capture_panel
capture_panel_plant focus
expect "capture opens the focus copy's panel" ok ipc vgs.capture invoke toggle ''
expect_poll "control: the focus copy opens on the mode switch" SegmentedControl capture_focus_type
expect "control: opening on the mode switch fails the Take screenshot readback" False capture_is capture_focus "$capture_shot_initial"
expect "capture closes the focus copy's panel" ok ipc vgs.capture invoke toggle ''
expect_poll "the focus copy's panel unmaps" absent capture_panel
capture_panel_plant original
capture_setting delay 0
expect_poll "capture panel leaves no layer" 0 layer_count vgs:panel
rm -f -- "${shim:?}/tesseract"
rescan "the missing OCR command is rescanned"
expect_poll "only OCR is unavailable" True capture_missing
# A press on an action whose tool is missing still reaches the service,
# which raises the install notice, and the panel names the cause. The panel
# closes before the notice's Escape below, so the key reaches the notice.
expect "capture opens its panel without OCR" ok ipc vgs.capture invoke toggle ''
expect_poll "the panel without OCR opens on its primary action" Button capture_focus_type
capture_back
capture_back
expect_poll "Shift+Tab reaches the mode switch without OCR" SegmentedControl capture_focus_type
capture_key End
expect_poll "End chooses Text" 2 capture_choice SegmentedControl
capture_key Tab
expect_poll "Tab from the mode switch reaches Copy text, past the hidden tiles" '["Button", "Copy text", true, true, true]' capture_focus
capture_key Return
expect_poll "a press without OCR names the missing tools in the panel" '"Install the missing tools to use this action."' ipc smoke readInstance panel vgs.capture problem
expect_poll "the panel's press raises the core install notice" tesseract capture_notice
expect "the refused press runs no capture" idle capture_phase
expect "capture closes its panel over the install notice" ok ipc vgs.capture invoke toggle ''
expect_poll "the panel over the install notice unmaps" absent capture_panel
expect "missing OCR refuses capture before running tools" 'refused: capture=missing tesseract' ipc vgs.capture invoke text ''
expect_poll "missing OCR raises the core install notice" tesseract capture_notice
type_keys -k Escape || fail "capture: closing the install notice failed"
ln -s -- "$capture_state/bin/tesseract" "$shim/tesseract"
rescan "the restored OCR command is rescanned"
expect_poll "the restored OCR command is found" False capture_missing
# Mutate only the helper in this disposable runtime tree. Each control uses
# the same service IPC and readback as the positive assertion above.
capture_helper="$(capture_read helperPath | py_reply 'import json,sys; print(json.load(sys.stdin))')"
python3 - "$capture_helper" "$sandbox" "$rt_dir" "$capture_state/helper-original.py" <<'PY'
from pathlib import Path
import sys
helper, sandbox, runtime, original = map(Path, sys.argv[1:])
assert any(helper.resolve().is_relative_to(root.resolve()) for root in (sandbox, runtime)), "capture control must stay inside the sandbox or its private runtime"
original.write_bytes(helper.read_bytes())
PY
capture_mutate() { python3 - "$capture_state/helper-original.py" "$capture_helper" "$1" <<'PY'
from pathlib import Path
import sys
original, helper, control = sys.argv[1:]
changes = {
    "smart": ('picked = rectangle_geometry(target), tuple(str(target[k]) for k in ("x", "y", "width", "height"))', 'picked = picked', 1),
    "window": ('boxes = windows\n', 'boxes = outputs\n', 1),
    # A display selection is handed no window boxes, so its wrong boxes are
    # the displays' own, each one pixel in.
    "display": ('boxes = outputs\n', 'boxes = [dict(r, x=r["x"] + 1, y=r["y"] + 1, width=r["width"] - 2, height=r["height"] - 2) for r in outputs]\n', 1),
    "all": ('args = ["grim", "-g", f"{left},{top} {right - left}x{bottom - top}"]', 'args = ["grim", "-o", ""]', 1),
    "delay": ('if not self.countdown(delay, timeout):', 'if False:', 1),
    "cancel-delay": ('ready, _, _ = select.select([sys.stdin], [], [], max(0, deadline - time.monotonic()))\n                if ready and sys.stdin.readline().strip() in ("", "cancel"):\n                    return False', 'ready, _, _ = select.select([sys.stdin], [], [], max(0, deadline - time.monotonic()))\n                if ready and sys.stdin.readline().strip() == "":\n                    return False', 1),
    "cursor": ('args = args + (["-c"] if request.get("cursor", False) else [])', 'args = args', 1),
    "copy-only": ('if processing == "copy":', 'if False:', 1),
    "save-only": ('if processing != "save":', 'if True:', 1),
    "focus": ('emit("selection-ended")', 'pass', 2),
    "timeout": ('child.communicate(timeout=timeout)', 'child.communicate()', 1),
    "output-match": ('target = next((r["name"] for r in request["outputs"] if (r["x"], r["y"], r["width"], r["height"]) == (x, y, width, height)), None)', 'target = None', 1),
    "options": ('*options, ', '', 1),
    "choices": ('audio.append((label, "device:" + name))', 'pass', 1),
    "ocr-failures": ('for pattern, reason, message in OCR_FAILURES:', 'for pattern, reason, message in ():', 1),
    "missing-check": ('report = {"missing": [code for code in dict.fromkeys(languages.split("+")) if code not in installed]}', 'report = {"missing": []}', 1),
}
source = Path(original).read_text()
before, after, count = changes[control]
assert source.count(before) == count, control
changed = source.replace(before, after)
assert changed != source, control
Path(helper).write_text(changed)
PY
}
capture_count_unchanged() { [[ $(capture_counts) == "$capture_before" ]] && echo True || echo False; }
for capture_control in smart window display all cursor copy-only save-only delay cancel-delay focus timeout; do
  capture_mutate "$capture_control"
  : >"$capture_state/calls.jsonl"
  capture_config real "{\"grim\": \"$capture_real_grim\"}"
  case "$capture_control" in
    smart)
      read -r capture_target_x capture_target_y capture_target_w capture_target_h < <(hypr -j clients | py_reply 'import json,sys; w=next(w for w in json.load(sys.stdin) if w["address"]==sys.argv[1]); print(*w["at"],*w["size"])' "$capture_target_address")
      capture_target_box="$capture_target_x,$capture_target_y ${capture_target_w}x${capture_target_h}"
      capture_target_cx=$((capture_target_x + capture_target_w / 2))
      capture_target_cy=$((capture_target_y + capture_target_h / 2))
      capture_config geometry "\"$capture_target_cx,$capture_target_cy 1x1\""
      expect "control: smart capture starts with a tiny click" ok ipc vgs.capture invoke screenshot-area ''
      expect_poll "control: the unsnapped click completes" idle capture_phase
      expect "control: dropping click snapping fails the window image readback" False capture_image_box "$capture_target_box"
      capture_config geometry '"10,20 80x60"'
      ;;
    window|display)
      capture_config real "{\"grim\": \"$capture_real_grim\", \"slurp\": \"$capture_real_slurp\", \"hyprpicker\": \"$capture_real_picker\"}"
      expect "control: the $capture_control selection starts" ok ipc vgs.capture invoke "screenshot-$capture_control" ''
      expect "control: the wrong rectangle selector maps" True capture_selecting
      click "$capture_target_cx" "$capture_target_cy" || fail "capture: the control click failed"
      expect_poll "control: the wrong rectangle capture finishes" idle capture_phase
      if [[ $capture_control == display ]]; then capture_expected_box="$capture_display_box"; else capture_expected_box="$capture_target_box"; fi
      expect "control: wrong $capture_control rectangles fail the selected image" False capture_image_box "$capture_expected_box"
      ;;
    all)
      expect "control: all-display capture starts without its bounding box" ok ipc vgs.capture invoke screenshot-all ''
      expect_poll "control: the bounding-box copy finishes" idle capture_phase
      expect "control: dropping the bounding rectangle fails the all-display readback" False capture_image_box "$capture_all_box"
      ;;
    cursor)
      capture_setting cursor true
      expect "control: capture starts with the cursor flag dropped" ok ipc vgs.capture invoke screenshot ''
      expect_poll "control: the cursor copy completes" idle capture_phase
      expect "control: dropping the cursor flag fails the cursor argument readback" False capture_cursor_flag
      capture_setting cursor false
      ;;
    copy-only|save-only)
      if [[ $capture_control == copy-only ]]; then capture_setting processing '"copy"'; else capture_setting processing '"save"'; fi
      capture_before="$(capture_counts)"
      printf 'previous clipboard' >"$capture_state/clipboard"
      expect "control: the $capture_control screenshot starts" ok ipc vgs.capture invoke screenshot ''
      expect_poll "control: the $capture_control screenshot completes" idle capture_phase
      if [[ $capture_control == copy-only ]]; then
        expect "control: saving copy-only fails its deliverable readback" False capture_copy_only
      else
        expect "control: copying save-only fails its deliverable readback" False capture_save_only
      fi
      capture_setting processing '"save-copy"'
      ;;
    delay)
      expect "control: notices leave before the screen settles" 0 capture_wait_cards
      capture_setting delay 3
      capture_before="$(capture_counts)"
      capture_delay_started="$(python3 -c 'import time; print(time.time())')"
      expect "control: a delayed action starts without a countdown" ok ipc vgs.capture invoke screenshot ''
      expect_poll "control: the early capture completes" idle capture_phase
      expect "control: removing the delay fails the elapsed-time readback" False capture_delay_elapsed 3
      capture_setting delay 0
      ;;
    cancel-delay)
      expect "control: notices leave before the countdown" 0 capture_wait_cards
      capture_setting delay 2
      capture_before="$(capture_counts)"
      expect "control: the countdown starts with cancellation dropped" ok ipc vgs.capture invoke screenshot ''
      expect_poll "control: the countdown awaits cancellation" True capture_delay_held
      expect "control: the same action sends cancellation" ok ipc vgs.capture invoke screenshot ''
      expect_poll "control: the ignored cancellation finishes" idle capture_phase
      expect "control: ignoring countdown cancellation fails the no-file readback" False capture_count_unchanged
      capture_setting delay 0
      ;;
    focus)
      capture_config slurpRelease true
      rm -f -- "${capture_state:?}/slurp-ready" "${capture_state:?}/slurp-release"
      expect "control: target focus is set before selection" ok hypr dispatch "hl.dsp.focus({ window = \"address:$capture_target_address\" })"
      expect_poll "control: the target has focus" "$capture_target_address" capture_active_address
      expect "control: selection starts with its end event dropped" ok ipc vgs.capture invoke screenshot-area ''
      expect_poll "control: the selector awaits focus disturbance" True capture_marker slurp-ready
      expect "control: the other window receives focus during selection" ok hypr dispatch "hl.dsp.focus({ window = \"address:$capture_disturbance_address\" })"
      expect_poll "control: the other window has focus" "$capture_disturbance_address" capture_active_address
      touch -- "$capture_state/slurp-release"
      expect_poll "control: selection without focus restoration completes" idle capture_phase
      expect "control: dropping selection-end fails the original-window readback" "$capture_disturbance_address" capture_active_address
      capture_config slurpRelease false
      ;;
    timeout)
      capture_config real '{}'
      capture_setting timeout 1
      capture_config grimHold true
      capture_before="$(capture_counts)"
      rm -f -- "${capture_state:?}/grim-ready"
      expect "control: the screenshot starts without its tool deadline" ok ipc vgs.capture invoke screenshot ''
      expect_poll "control: the unbounded tool has started" True capture_marker grim-ready
      expect_poll "control: the held tool crosses the configured deadline" True capture_grim_past_limit
      expect "control: dropping the deadline fails the bounded cleanup readback" False capture_timeout_clean
      cp -- "$capture_state/helper-original.py" "$capture_helper"
      expect "control: disabling capture ends the unbounded tool" ok ipc shell setPluginEnabled vgs.capture false
      expect_poll "control: the unbounded tool is gone" 0 capture_grim_left
      capture_config grimHold false
      expect "capture is enabled after the timeout control" ok ipc shell setPluginEnabled vgs.capture true
      expect_poll "capture is idle after the timeout control" idle capture_phase
      capture_setting timeout 10
      ;;
  esac
  cp -- "$capture_state/helper-original.py" "$capture_helper"
done
close_toplevel "$capture_disturbance_pid" "capture's focus disturbance closes"
close_toplevel "$capture_target_pid" "capture's screenshot target closes"
# Recording modes, settings, devices, post-processing and languages, each
# through service IPC. The fixture slurp answers the configured geometry,
# the stand-in recorder logs its argv, and the stand-in ffmpeg keeps the
# recorded bytes. Each control copy of the helper fails the readback above it.
capture_argv() { python3 - "$capture_state/calls.jsonl" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1])]
argv = [row["args"] for row in rows if row["tool"] == "gpu-screen-recorder"]
print(json.dumps(argv[-1][:-2] if argv and argv[-1][-2] == "-o" else None))
PY
}
capture_words() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@"; }
capture_defaults=(-f 60 -k auto -q very_high -fm cfr -cursor no -a default_output -ac aac)
capture_record() { # ACTION LABEL
  : >"$capture_state/calls.jsonl"
  expect "$2: $1 starts" ok ipc vgs.capture invoke "$1" ''
  expect_poll "$2: $1 is recording" recording capture_phase
  expect "$2: a second $1 press stops it" ok ipc vgs.capture invoke "$1" ''
  expect_poll "$2: $1 is saved" idle capture_phase
}
capture_uri() { python3 - "$capture_state/clipboard" "$(capture_path)" <<'PY'
from pathlib import Path
import sys
clipboard, path = Path(sys.argv[1]), Path(sys.argv[2])
print(path.is_file() and path.read_bytes() == b"finalized" and clipboard.read_bytes() == (path.as_uri() + "\r\n").encode())
PY
}
capture_choices() { ipc smoke readInstance panel vgs.capture values | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps([v.get("audioSources"), v.get("cameras")]))'; }
capture_languages() { ipc smoke readInstance panel vgs.capture languagesRow | py_reply 'import json,sys; r=json.load(sys.stdin); print("absent" if r is None or r["action"] is None else json.dumps([r["tone"], r["action"]["offered"]]))'; }
capture_titles() { capture_cards | py_reply 'import json,sys; print(json.load(sys.stdin).count(sys.argv[1]))' "$1"; }
capture_log_holds() { python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); print(p.is_file() and sys.argv[2] in p.read_text() and p.stat().st_mode & 0o777 == 0o600)' "$home/.local/state/vgshell/plugins/vgs.capture/recorder.log" "$1"; }
open_toplevel "$sandbox/capture-record-target.log" smoke.capture-record "Capture record target" || fail "capture: the recording target did not map"
capture_record_pid="$toplevel_pid"
capture_record_address="$(toplevel_address "$capture_record_pid")"
read -r capture_rx capture_ry capture_rw capture_rh < <(hypr -j clients | py_reply 'import json,sys; w=next(w for w in json.load(sys.stdin) if w["address"]==sys.argv[1]); print(*w["at"],*w["size"])' "$capture_record_address")
capture_region="${capture_rw}x${capture_rh}+${capture_rx}+${capture_ry}"
capture_config geometry "\"$capture_rx,$capture_ry ${capture_rw}x${capture_rh}\""
capture_record record-window "record window"
expect "the window recording records the selected box" "$(capture_words -w region -region "$capture_region" "${capture_defaults[@]}")" capture_argv
expect_poll "the saved recording's link is on the clipboard" True capture_uri
capture_config geometry "\"$capture_display_box\""
capture_record record-display "record display"
expect "a box equal to the display records that output" "$(capture_words -w "$capture_output" "${capture_defaults[@]}")" capture_argv
capture_record record-output "record output"
expect "the focused display records that output" "$(capture_words -w "$capture_output" "${capture_defaults[@]}")" capture_argv
capture_record record-portal "record portal"
expect "portal recording hands the recorder the portal" "$(capture_words -w portal "${capture_defaults[@]}")" capture_argv
capture_recording_released finished-portal
expect "finished portal recording leaves no owned recorder" False capture_recorder_left
capture_config portalCancel true
expect "the portal Cancel response reaches Capture" ok ipc vgs.capture invoke record-portal ''
capture_recording_released cancelled-portal
capture_config portalCancel false
capture_config picker true
rm -f -- "$capture_state/picker-ready"
expect "Capture starts a recording with a pending picker" ok ipc vgs.capture invoke record-portal ''
expect_poll "the recorder holds its picker" True capture_marker picker-ready
expect "the pending picker has one owned recorder and one VGS recording action" '{"recorders": 1, "recordingActions": 1}' capture_recording_counts
capture_open_control() { (failures=0 behaviour_failures=0; capture_recording_released held-picker >"$capture_state/held-picker-control.log"; echo "$failures"); }
expect "control: the held recorder picker fails the same release check" 1 capture_open_control
cat -- "$capture_state/held-picker-control.log"
expect "a second press closes the pending recorder picker" ok ipc vgs.capture invoke record-portal ''
capture_recording_released closed-recorder-picker
capture_config picker false
capture_mutate output-match
capture_record record-display "control: output match dropped"
expect "control: dropping the output match fails the display argv" False capture_is capture_argv "$(capture_words -w "$capture_output" "${capture_defaults[@]}")"
cp -- "$capture_state/helper-original.py" "$capture_helper"
capture_setting quality '"ultra"'
capture_setting frameRate 30
capture_setting codec '"hevc"'
capture_setting constantFrameRate false
capture_setting recordCursor true
capture_setting audioSources '[{"name": "source-1", "source": "device:fixture-speaker.monitor"}]'
capture_setting webcam true
capture_chosen="$(capture_words -w "$capture_output|v4l2:/dev/video7;x=74%;y=69%;width=22%;height=22%;camera_fps=30" -f 30 -k hevc -q ultra -fm vfr -cursor yes -a default_output -a device:fixture-speaker.monitor -ac aac)"
capture_record record-output "record settings"
expect "every recording setting reaches the recorder" "$capture_chosen" capture_argv
capture_mutate options
capture_record record-output "control: options dropped"
expect "control: dropping the recorder options fails the settings argv" False capture_is capture_argv "$capture_chosen"
cp -- "$capture_state/helper-original.py" "$capture_helper"
capture_setting webcamDevice '"/dev/video9"'
: >"$capture_state/calls.jsonl"
expect "a camera that is not connected refuses before recording" ok ipc vgs.capture invoke record-output ''
expect_poll "the refused camera leaves capture idle" idle capture_phase
expect "the refused camera starts no recorder" null capture_argv
for capture_reset in 'quality "very_high"' 'frameRate 60' 'codec "auto"' 'constantFrameRate true' 'recordCursor false' 'audioSources []' 'webcam false' 'webcamDevice ""'; do
  capture_setting ${capture_reset%% *} "${capture_reset#* }"
done
expect "earlier capture notices expire before the failure notices" 0 capture_wait_cards
# Notifications. vgs.notifications now shows each finished capture with the
# worker's buttons. Stand-ins for the viewer, the editor and the player, in
# the row's own folder, record their argv; nothing opens a real program.
capture_open="$capture_state/open-with"
mkdir -p -- "$capture_open"
for capture_program in viewer editor player; do
  printf '#!%s\nimport json, sys\nwith open(%s, "a") as log:\n    log.write(json.dumps(sys.argv[1:]) + "\\n")\n' "$(command -v python3)" "'$capture_open/$capture_program.calls'" >"$capture_open/$capture_program"
  chmod 755 -- "$capture_open/$capture_program"
done
capture_setting viewer "\"$capture_open/viewer %f\""
capture_setting editor "\"$capture_open/editor --filename %f --output-filename %f\""
capture_setting player "\"$capture_open/player\""
expect "notifications are enabled for capture's notifications" ok ipc shell setPluginEnabled vgs.notifications true
expect_poll "the notifications service is built" True record_exists vgs.notifications
expect_poll "the notifications loaded their state with Silence off" True notes_quiet
# capture_pills SUMMARY: the newest Capture notification's buttons as the
# History panel lists them, ["key", [label, ...]], or none.
capture_pills() {
  local rows i
  ipc vgs.notifications invoke history '' >/dev/null || return 1
  for i in $(seq 1 30); do
    rows="$(ipc smoke readInstance panel vgs.notifications rows)" || return 1
    [[ $rows == absent ]] || break
    sleep 0.1 # the summoned panel builds on its own schedule
  done
  ipc vgs.notifications invoke close '' >/dev/null || return 1
  python3 -c 'import json,sys; t=sys.argv[2]; rows=[] if t == "absent" else json.loads(t); r=next((r for r in rows if r["app"] == "Capture" and r["summary"] == sys.argv[1] and r["origin"] == "live"), None); print("none" if r is None else json.dumps([r["key"], [a["label"] for a in r["actions"]]]))' "$1" "$rows"
}
capture_labels() { capture_pills "$1" | py_reply 'import json,sys; t=sys.stdin.read().strip(); print("none" if t == "none" else json.dumps(json.loads(t)[1]))'; }
capture_choose() { # SUMMARY CHOICE
  local key
  key="$(capture_pills "$1" | py_reply 'import json,sys; print(json.load(sys.stdin)[0])')" || return 1
  ipc smoke invokeInstance service vgs.notifications chooseFromPanel "$(python3 -c 'import json,sys; print(json.dumps({"key": sys.argv[1], "choice": sys.argv[2]}))' "$key" "$2")"
}
capture_opened() { python3 -c 'import json,pathlib,sys; p=pathlib.Path(sys.argv[1]); print(json.dumps([json.loads(l) for l in p.read_text().splitlines()][-1] if p.exists() else None))' "$capture_open/$1.calls"; }
capture_held_count() { ipc vgs.notifications invoke status '' | py_reply 'import json,sys; print(json.load(sys.stdin)["held"])'; }
# capture_notify_left: the notify-send processes on the sandbox's session
# bus, read from /proc.
capture_notify_left() { python3 - "unix:path=$rt_dir/bus" <<'PY'
import os, sys
bus = ("DBUS_SESSION_BUS_ADDRESS=" + sys.argv[1]).encode()
left = 0
for pid in filter(str.isdigit, os.listdir("/proc")):
    try:
        argv = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")
        env = open(f"/proc/{pid}/environ", "rb").read().split(b"\0")
    except OSError:
        continue
    if os.path.basename(argv[0]) == b"notify-send" and bus in env:
        left += 1
print(left)
PY
}
capture_quiet() {
  expect "$1: earlier notifications leave" 0 capture_wait_cards
  expect "$1: the history lets go of its notifications" ok ipc vgs.notifications invoke clear-history ''
  expect_poll "$1: no Capture notification is held" 0 capture_held_count
  expect_poll "$1: no notify-send run waits" 0 capture_notify_left
}
capture_quiet "screenshot notification"
expect "a screenshot for its notification" ok ipc vgs.capture invoke screenshot ''
expect_poll "the screenshot for its notification finishes" idle capture_phase
expect_poll "the saved screenshot offers Open, Edit and Dismiss" '["Open", "Edit", "Dismiss"]' capture_labels "Screenshot saved"
expect "Edit is chosen on the screenshot's notification" left capture_choose "Screenshot saved" action:edit
expect_poll "Edit hands the editor the saved file" "$(python3 -c 'import json,sys; print(json.dumps(["--filename", sys.argv[1], "--output-filename", sys.argv[1]]))' "$(capture_path)")" capture_opened editor
capture_quiet "screenshot click"
expect "a screenshot for a click on its notification" ok ipc vgs.capture invoke screenshot ''
expect_poll "the clicked screenshot finishes" idle capture_phase
expect_poll "the clicked screenshot's notification shows" '["Open", "Edit", "Dismiss"]' capture_labels "Screenshot saved"
expect "a click opens the screenshot's notification" left capture_choose "Screenshot saved" open
expect_poll "a click hands the viewer the saved file" "$(capture_words "$(capture_path)")" capture_opened viewer
capture_quiet "recording notification"
capture_record record-output "notification"
expect_poll "the saved recording offers Open and Dismiss" '["Open", "Dismiss"]' capture_labels "Recording saved"
expect "Open is chosen on the recording's notification" left capture_choose "Recording saved" action:default
expect_poll "Open hands the player the saved file last" "$(capture_words "$(capture_path)")" capture_opened player
expect "the recording's link is on the clipboard" True capture_uri
capture_quiet "text notification"
expect "text capture for its notification" ok ipc vgs.capture invoke text ''
expect_poll "the text capture finishes" idle capture_phase
expect_poll "copied text offers Dismiss alone" '["Dismiss"]' capture_labels "Text copied"
# A disabled service ends its waiting run and closes its notification.
capture_waiting() { # LABEL
  capture_quiet "$1"
  expect "$1: a screenshot whose notification waits" ok ipc vgs.capture invoke screenshot ''
  expect_poll "$1: the screenshot finishes" idle capture_phase
  expect_poll "$1: one notify-send run waits" 1 capture_notify_left
  expect_poll "$1: vgs.notifications holds its notification" 1 capture_held_count
  expect "$1: capture is disabled" ok ipc shell setPluginEnabled vgs.capture false
  expect_poll "$1: the disabled service is released" False record_exists vgs.capture
  expect_poll "$1: no notify-send run is left" 0 capture_notify_left
}
capture_waiting "disabled capture"
expect_poll "disabling capture closes its notification" 0 capture_held_count
expect "capture is enabled after its notification closes" ok ipc shell setPluginEnabled vgs.capture true
expect_poll "capture is built after its notification closes" True record_exists vgs.capture
# Disposable Service copies: one without the buttons, one that closes no
# notification when it goes.
capture_notice_service="$repo/shell/plugins/vgs.capture/Service.qml"
capture_notice_control() { # NAME
  expect "capture stops before the $1 control" ok ipc shell setPluginEnabled vgs.capture false
  expect_poll "the $1 control releases the original service" False record_exists vgs.capture
  python3 - "$capture_notice_service" "$sandbox" "$capture_state/notice-service-original.qml" "$1" <<'PY'
from pathlib import Path
import sys
service, sandbox, original, control = sys.argv[1:]
service, sandbox, original = Path(service), Path(sandbox), Path(original)
assert service.resolve().is_relative_to(sandbox.resolve()), "notification control must stay inside the sandbox"
source = original.read_text() if original.exists() else service.read_text()
original.write_text(source)
before = {
    "no-buttons": '        for (const action of event.actions || []) command.push("--action=" + action.id + "=" + action.label);\n',
    "no-close": "        for (const run of notices) {\n",
}[control]
after = {"no-buttons": "", "no-close": "        for (const run of []) {\n"}[control]
assert source.count(before) == 1, control
changed = source.replace(before, after)
assert changed != source
service.write_text(changed)
PY
  rescan "the $1 control service is rescanned"
  expect "capture enables the $1 control" ok ipc shell setPluginEnabled vgs.capture true
  expect_poll "the $1 control is built" True record_exists vgs.capture
}
capture_notice_restore() { # NAME
  expect "capture stops after the $1 control" ok ipc shell setPluginEnabled vgs.capture false
  expect_poll "the $1 control releases its service" False record_exists vgs.capture
  cp -- "$capture_state/notice-service-original.qml" "$capture_notice_service"
  rescan "the original service is rescanned after the $1 control"
  expect "capture enables the restored service after the $1 control" ok ipc shell setPluginEnabled vgs.capture true
  expect_poll "the restored service is built after the $1 control" True record_exists vgs.capture
}
capture_notice_control no-buttons
capture_quiet "control: no buttons"
expect "control: a screenshot without buttons" ok ipc vgs.capture invoke screenshot ''
expect_poll "control: the screenshot without buttons finishes" idle capture_phase
expect_poll "control: the copy's notification shows" '["Dismiss"]' capture_labels "Screenshot saved"
capture_screenshot_labels() { capture_labels "Screenshot saved"; }
expect "control: dropping the buttons fails the Open, Edit and Dismiss readback" False capture_is capture_screenshot_labels '["Open", "Edit", "Dismiss"]'
capture_notice_restore no-buttons
capture_notice_control no-close
capture_waiting "control: no close"
expect "control: a notification the copy left open stays held" 1 capture_held_count
cp -- "$capture_state/notice-service-original.qml" "$capture_notice_service"
rescan "the original service is rescanned after the no-close control"
expect "capture enables the restored service after the no-close control" ok ipc shell setPluginEnabled vgs.capture true
expect_poll "the restored service is built after the no-close control" True record_exists vgs.capture
# With vgs.notifications disabled no server answers: the capture still
# saves its file and the service returns to idle.
capture_quiet "no notification server"
expect "notifications are disabled for the no-server capture" ok ipc shell setPluginEnabled vgs.notifications false
expect_poll "the notifications service is released" False record_exists vgs.notifications
capture_before="$(capture_counts)"
expect "a screenshot with no notification server" ok ipc vgs.capture invoke screenshot ''
expect_poll "the screenshot with no notification server finishes" idle capture_phase
expect "the screenshot with no notification server is saved" "$((capture_before + 1))" capture_counts
expect_poll "no notify-send run waits with no server" 0 capture_notify_left
expect "notifications are enabled again" ok ipc shell setPluginEnabled vgs.notifications true
expect_poll "the notifications service is built again" True record_exists vgs.notifications
capture_config crash true
capture_record_crash() {
  : >"$capture_state/calls.jsonl"
  expect "a crashing recorder starts" ok ipc vgs.capture invoke record-output ''
  expect_poll "the crashed recording leaves capture idle" idle capture_phase
}
capture_record_crash
expect_poll "the crash raises the failure notice" 1 capture_titles "Capture failed"
expect "the recorder log keeps the crash line, owner-only" True capture_log_holds "fixture recorder crash: no encoder"
capture_config crash false
expect "the crash notice expires" 0 capture_wait_cards
capture_config ffmpegFail true
capture_record record-output "failed processing"
expect_poll "a failed post-process still notices the saved recording" 1 capture_titles "Recording saved"
expect "a failed post-process keeps the recording as recorded" True capture_uri
capture_config ffmpegFail false
expect "capture opens its panel for its choices" ok ipc vgs.capture invoke toggle ''
expect_poll "the panel maps for its choices" false capture_panel
capture_offered='[[{"label": "Fixture microphone", "value": "device:fixture-mic"}, {"label": "Monitor of Fixture speaker", "value": "device:fixture-speaker.monitor"}], [{"label": "Fixture camera", "value": "/dev/video7"}]]'
expect_poll "the panel offers the fixture's audio sources and camera" "$capture_offered" capture_choices
capture_setting ocrLanguages '"deu+eng"'
expect_poll "a missing chosen language offers Install languages" '["warning", true]' capture_languages
capture_config languages '["eng", "deu", "osd"]'
forget_record
expect "Install languages answers ok" ok ipc smoke invokeInstance panel vgs.capture installLanguages '{}'
expect_poll "the terminal is handed the language TUI" "$(words vgs.capture/install-languages tui/install-languages.sh)" recorded_tail
expect_poll "the ended TUI run reads the languages again" '["info", false]' capture_languages
capture_setting ocrLanguages '"fra+eng"'
expect_poll "another missing language offers Install languages again" '["warning", true]' capture_languages
capture_mutate missing-check
capture_setting ocrLanguages '"fra+deu+eng"'
expect_poll "control: the missing-check copy reads the new languages" '["info", false]' capture_languages
expect "control: dropping the missing check fails the offered readback" False capture_is capture_languages '["warning", true]'
capture_mutate choices
capture_setting ocrLanguages '"eng"'
expect_poll "control: the choices copy probes again" '[[{"label": "Monitor of Fixture speaker", "value": "device:fixture-speaker.monitor"}], [{"label": "Fixture camera", "value": "/dev/video7"}]]' capture_choices
expect "control: dropping a source fails the offered choices" False capture_is capture_choices "$capture_offered"
cp -- "$capture_state/helper-original.py" "$capture_helper"
expect "capture closes its panel after its choices" ok ipc vgs.capture invoke toggle ''
expect_poll "the choices panel unmaps" absent capture_panel
# A camera plugged in while the panel is closed shows when it opens again.
capture_plugged() { python3 - "$capture_state/config.json" "$1" <<'PY'
import json, sys
path, plugged = sys.argv[1], sys.argv[2] == "in"
doc = json.load(open(path))
doc.pop("nodes", None)
if plugged:
    doc["nodes"] = [
        {"id": 40, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Audio/Source", "node.name": "fixture-mic", "node.description": "Fixture microphone"}}},
        {"id": 41, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Audio/Sink", "node.name": "fixture-speaker", "node.description": "Fixture speaker"}}},
        {"id": 42, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Video/Source", "node.name": "fixture-camera", "node.description": "Fixture camera", "api.v4l2.path": "/dev/video7"}}},
        {"id": 44, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Video/Source", "node.name": "plugged-camera", "node.description": "Plugged camera", "api.v4l2.path": "/dev/video8"}}},
    ]
with open(path, "w") as output:
    json.dump(doc, output)
PY
}
capture_cameras() { capture_choices | py_reply 'import json,sys; print(json.dumps([c["value"] for c in json.load(sys.stdin)[1]]))'; }
capture_plugged in
expect "capture opens its panel after a camera is plugged in" ok ipc vgs.capture invoke toggle ''
expect_poll "the opened panel offers the plugged-in camera" '["/dev/video7", "/dev/video8"]' capture_cameras
expect "capture closes its panel after the plugged-in camera" ok ipc vgs.capture invoke toggle ''
expect_poll "the plugged-in camera's panel unmaps" absent capture_panel
capture_plugged out
# Text in a language whose data is missing names the cause in its notice.
capture_config languages '["eng", "osd"]'
capture_setting ocrLanguages '"deu+eng"'
expect "earlier notices expire before the missing-language text" 0 capture_wait_cards
expect "text capture starts with a missing language" ok ipc vgs.capture invoke text ''
expect_poll "the missing-language text finishes" idle capture_phase
expect_poll "missing language data raises Text capture unavailable" 1 capture_titles "Text capture unavailable"
expect "the missing-language notice expires" 0 capture_wait_cards
capture_mutate ocr-failures
expect "control: text capture starts without the failure table" ok ipc vgs.capture invoke text ''
expect_poll "control: the unclassified text failure finishes" idle capture_phase
expect_poll "control: the unclassified failure raises the general notice" 1 capture_titles "Capture failed"
expect "control: dropping the failure table fails the Text capture unavailable readback" 0 capture_titles "Text capture unavailable"
cp -- "$capture_state/helper-original.py" "$capture_helper"
capture_setting ocrLanguages '"eng"'
expect "the unclassified failure notice expires" 0 capture_wait_cards
# The service is idle once the recorder stops, so a capture starts while the
# worker still post-processes; the saved notice follows the release.
capture_held() { # LABEL ANSWER
  rm -f -- "${capture_state:?}/ffmpeg-ready" "${capture_state:?}/ffmpeg-release"
  capture_config ffmpegHold true
  expect "$1: a recording starts" ok ipc vgs.capture invoke record-output ''
  expect_poll "$1: the recording is active" recording capture_phase
  expect "$1: a second press stops it" ok ipc vgs.capture invoke record-output ''
  expect_poll "$1: the post-process is held half way" True capture_marker ffmpeg-ready
  expect "$1: a screenshot during the post-process" "$2" ipc vgs.capture invoke screenshot ''
  touch -- "$capture_state/ffmpeg-release"
  capture_config ffmpegHold false
  expect_poll "$1: the released post-process saves the recording" 1 capture_titles "Recording saved"
  expect_poll "$1: capture is idle after the release" idle capture_phase
  expect "$1: notices expire" 0 capture_wait_cards
}
capture_held "held post-process" ok
capture_stopped_service="$repo/shell/plugins/vgs.capture/Service.qml"
expect "capture stops before the stopped-event control" ok ipc shell setPluginEnabled vgs.capture false
expect_poll "the stopped-event control releases the original service" False record_exists vgs.capture
python3 - "$capture_stopped_service" "$sandbox" "$capture_state/stopped-service-original.qml" <<'PY'
from pathlib import Path
import sys
service, sandbox, original = map(Path, sys.argv[1:])
assert service.resolve().is_relative_to(sandbox.resolve()), "stopped-event control must stay inside the sandbox"
source = service.read_text()
original.write_text(source)
before = "            // Post-processing continues in this worker; the next capture can start.\n            lastPath = event.path;\n            finishAction(job);\n"
assert source.count(before) == 1, "stopped-event control match"
changed = source.replace(before, "            lastPath = event.path;\n")
assert changed != source
service.write_text(changed)
PY
rescan "the stopped-event control service is rescanned"
expect "capture enables the stopped-event control" ok ipc shell setPluginEnabled vgs.capture true
expect_poll "the stopped-event control is built" True record_exists vgs.capture
capture_held "control: stopped leaves the action open" 'refused: capture=busy'
expect "capture stops after the stopped-event control" ok ipc shell setPluginEnabled vgs.capture false
expect_poll "the stopped-event control releases its service" False record_exists vgs.capture
cp -- "$capture_state/stopped-service-original.qml" "$capture_stopped_service"
rescan "the original stopped-event service is rescanned"
expect "capture enables the restored stopped-event service" ok ipc shell setPluginEnabled vgs.capture true
expect_poll "the restored stopped-event service is built" True record_exists vgs.capture
expect_poll "the restored service is idle" idle capture_phase
# A rescan publishes a new snapshot, so later helper controls edit its copy.
capture_helper="$(capture_read helperPath | py_reply 'import json,sys; print(json.load(sys.stdin))')"
python3 -c 'import pathlib,sys; h=pathlib.Path(sys.argv[1]).resolve(); assert any(h.is_relative_to(pathlib.Path(r).resolve()) for r in sys.argv[2:]), "capture control must stay inside the sandbox or its private runtime"' "$capture_helper" "$sandbox" "$rt_dir"
cmp -s -- "$capture_state/helper-original.py" "$capture_helper" || fail "capture: the rescanned helper differs from the original"
close_toplevel "$capture_record_pid" "capture's recording target closes"
capture_config real "{\"grim\": \"$capture_real_grim\"}"
for capture_control in no-output no-clipboard hard-stop inherited-stdin; do
  python3 - "$capture_state/helper-original.py" "$capture_helper" "$capture_control" <<'PY'
from pathlib import Path
import sys
original, helper, control = sys.argv[1:]
changes = {
    "no-output": ('args = ["grim", "-o", request["output"]]', 'args = ["grim"]'),
    "no-clipboard": ('child = self.spawn(["wl-copy", "--foreground", "--type", mime], stdin=subprocess.PIPE, stderr=subprocess.PIPE)', 'child = self.spawn([sys.executable, "-c", "import sys; sys.stdin.buffer.read()"], stdin=subprocess.PIPE, stderr=subprocess.PIPE)'),
    "hard-stop": ('self.recorder.send_signal(signal.SIGINT)\n                    stopping = True', 'self.recorder.send_signal(signal.SIGKILL)\n                    stopping = True'),
    "inherited-stdin": ('kwargs.setdefault("stdin", subprocess.DEVNULL)', 'pass'),
}
source = Path(original).read_text()
before, after = changes[control]
assert source.count(before) == 1, control
changed = source.replace(before, after)
assert changed != source, control
Path(helper).write_text(changed)
PY
  : >"$capture_state/calls.jsonl"
  rm -f -- "$capture_state/signal"
  if [[ $capture_control == hard-stop ]]; then
    expect "control: the recorder starts before a hard stop" ok ipc vgs.capture invoke record ''
    expect_poll "control: the recorder is active before a hard stop" recording capture_phase
    expect "control: the service asks the hard-stop copy to stop" ok ipc vgs.capture invoke record ''
    expect_poll "control: the hard-stop copy finishes" idle capture_phase
    expect "control: SIGKILL fails the recording row" False capture_recorded
  elif [[ $capture_control == inherited-stdin ]]; then
    capture_setting smart false
    capture_config real "{\"grim\": \"$capture_real_grim\", \"slurp\": \"$capture_real_slurp\", \"hyprpicker\": \"$capture_real_picker\"}"
    expect "control: the inherited-stdin copy starts a selection" ok ipc vgs.capture invoke screenshot-area ''
    # The held worker stays until the plugin is disabled below, which ends
    # it as a shell stop does.
    expect "control: an inherited stdin fails the selection row" False capture_selecting
    capture_config real "{\"grim\": \"$capture_real_grim\"}"
  else
    printf 'previous clipboard' >"$capture_state/clipboard"
    expect "control: the screenshot copy starts" ok ipc vgs.capture invoke screenshot ''
    expect_poll "control: the screenshot copy finishes" idle capture_phase
    expect "control: $capture_control fails the screenshot row" False capture_png
  fi
done
cp -- "$capture_state/helper-original.py" "$capture_helper"
expect "the capture notifications leave" 0 capture_wait_cards
expect "the capture notifications leave the history" ok ipc vgs.notifications invoke clear-history ''
expect "notifications are disabled after the row" ok ipc shell setPluginEnabled vgs.notifications false
expect_poll "the notifications service is released after the row" False record_exists vgs.notifications
expect "capture is disabled after the row" ok ipc shell setPluginEnabled vgs.capture false
expect_poll "disabled capture releases its service" False record_exists vgs.capture
expect_poll "disabling capture ends a held selection's selector and freeze" 0 capture_left
expect_poll "disabled capture releases its status" null capture_status
expect_poll "disabling capture releases all owned clipboard providers" True capture_released
for capture_tool in grim slurp hyprpicker tesseract wl-copy gpu-screen-recorder ffmpeg pw-dump; do
  rm -f -- "${shim:?}/$capture_tool"
  if [[ -e $capture_state/saved-shims/$capture_tool ]]; then mv -- "$capture_state/saved-shims/$capture_tool" "$shim/$capture_tool"; fi
done
cp -- "$capture_saved" "$home/.config/vgshell/shell.json.next" && mv -T -- "$home/.config/vgshell/shell.json.next" "$home/.config/vgshell/shell.json"
rescan "the capture fixture cleanup is rescanned"
expect_poll "the notifications service is as the row found it" "$capture_notes_found" record_exists vgs.notifications
