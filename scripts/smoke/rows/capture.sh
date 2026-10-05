# The capture service uses real nested tools for image and selection readings.
# Stand-ins hold tool failures, countdown frames, OCR and the recorder.
# inputs: shell/plugins/vgs.capture/* shell/Core/Capabilities.qml shell/Core/Compositor.qml shell/Core/Config.qml shell/Core/IpcRegistry.qml shell/Core/Lifetime.js shell/Core/MonitorLogic.js shell/Core/MonitorState.qml shell/Core/Notices.qml shell/Core/PackageManagers.js shell/Core/PluginLogic.js shell/Core/Plugins.qml shell/Core/PluginStatus.qml shell/Core/Registry.qml shell/Core/ServiceGate.qml shell/Core/ShortcutRegistry.qml shell/Core/Toasts.qml shell/Hosts/BarHost.qml shell/Hosts/NoticeHost.qml shell/Hosts/OverlaySurface.qml shell/Hosts/PluginSlot.qml shell/Hosts/ServiceHost.qml shell/Hosts/Summon* shell/Hosts/ToastHost.qml shell/Ui/* shell/Commons/* bin/vgshell-scan bin/lib/check-manifests.js bin/lib/qml-library.js scripts/test-capture.py scripts/smoke/fixtures/capture/*
# Expected rectangles come from Hyprland. Disposable copies remove each
# screenshot choice, countdown cleanup and the owned tool deadline.
# Readbacks use the harness's state poll, with no capture latency budget.
set -euo pipefail
capture_state="$sandbox/capture-world"
capture_saved="$sandbox/shell-before-capture.json"
capture_real_grim="$(command -v grim)" || { fail "capture: grim is unavailable"; return 0; }
capture_real_slurp="$(command -v slurp)" || { fail "capture: slurp is unavailable"; return 0; }
capture_real_picker="$(command -v hyprpicker)" || { fail "capture: hyprpicker is unavailable"; return 0; }
cp -- "$home/.config/vgshell/shell.json" "$capture_saved"
mkdir -p "$capture_state/saved-shims"
for capture_tool in grim slurp hyprpicker tesseract wl-copy gpu-screen-recorder; do
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
capture_clipboard() { python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); print(p.read_text() if p.exists() else "absent")' "$capture_state/clipboard"; }
capture_counts() { python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); print(len(list(p.glob("*.png"))))' "$home/Pictures/Screenshots"; }
capture_toasts() { ipc shell lent | py_reply 'import json,sys; rows=json.load(sys.stdin)["toasts"]; print(sum(r["plugin"] == "vgs.capture" for k in ("visible", "waiting") for r in rows[k]))'; }
capture_wait_toasts() {
  local count duration deadline now
  count="$(capture_toasts)" || return 1
  duration="$(ipc smoke themeValue toast.duration)" || return 1
  deadline="$(python3 -c 'import json,sys,time; print(time.monotonic() + (int(sys.argv[1]) + 1) * json.loads(sys.argv[2]) / 1000)' "$count" "$duration")" || return 1
  while ((count > 0)); do
    now="$(python3 -c 'import sys,time; print(time.monotonic() >= float(sys.argv[1]))' "$deadline")" || return 1
    [[ $now == False ]] || break
    sleep 0.2
    count="$(capture_toasts)" || return 1
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
capture_before="$(capture_counts)"
expect "earlier capture notices expire before cancellation" 0 capture_wait_toasts
capture_config cancel true
expect "capture accepts an area selection that is cancelled" ok ipc vgs.capture invoke screenshot-area ''
expect_poll "cancelled selection leaves capture idle" idle capture_phase
expect "cancelled selection writes no file" "$capture_before" capture_counts
expect "cancelled selection posts no notice" 0 capture_toasts
capture_config cancel false
capture_config escape true
expect "capture accepts an area selection that Escape ends" ok ipc vgs.capture invoke screenshot-area ''
expect_poll "Escape leaves capture idle" idle capture_phase
expect "Escape writes no file" "$capture_before" capture_counts
expect "Escape posts no notice" 0 capture_toasts
capture_config escape false
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
expect "capture notices leave the cursor baseline" 0 capture_wait_toasts
hover "$capture_target_cx" "$capture_target_cy" || fail "capture: the cursor could not be placed"
expect "capture takes a pointer-free baseline" ok ipc vgs.capture invoke screenshot ''
expect_poll "the cursor baseline finishes" idle capture_phase
capture_cursor_baseline="$(capture_clipboard_digest)"
capture_setting cursor true
expect "capture notices leave before the cursor image" 0 capture_wait_toasts
expect "capture takes the cursor image" ok ipc vgs.capture invoke screenshot ''
expect_poll "the cursor image finishes" idle capture_phase
expect "the cursor option reaches grim" True capture_cursor_flag
capture_cursor_changed() { [[ $(capture_clipboard_digest) != "$capture_cursor_baseline" ]] && echo True || echo False; }
expect "including the cursor changes the image bytes" True capture_cursor_changed
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
# Compare a small area inside the countdown card with the same desktop area
# before it maps. The image must contain the desktop after the card closes.
capture_crop_hash() { python3 - "$imagemagick" "$1" "$capture_countdown_crop" <<'PY'
import hashlib, subprocess, sys
program, image, crop = sys.argv[1:]
result = subprocess.run([program, image, "-crop", crop, "+repage", "-depth", "8", "rgb:-"], check=True, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE)
assert len(result.stdout) == 50 * 20 * 3, "countdown crop must contain all RGB pixels"
print(hashlib.sha256(result.stdout).hexdigest())
PY
}
capture_countdown_pixels() {
  local signature
  signature="$(capture_crop_hash "$(capture_path)")" || return 1
  [[ $signature == "$capture_countdown_baseline" ]] && echo True || echo False
}
capture_countdown_image() {
  capture_config real "{\"grim\": \"$capture_real_grim\"}"
  capture_setting delay 0
  expect "earlier capture notices expire before countdown pixels" 0 capture_wait_toasts
  expect "capture takes the desktop before the countdown" ok ipc vgs.capture invoke screenshot ''
  expect_poll "the countdown baseline finishes" idle capture_phase
  cp -- "$(capture_path)" "$capture_state/countdown-baseline.png"
  expect "the baseline's notice expires before the countdown" 0 capture_wait_toasts
  capture_setting delay 2
  expect "capture starts the countdown for image readback" ok ipc vgs.capture invoke screenshot ''
  expect_poll "the countdown image reaches its delay" delaying capture_phase
  expect_poll "the countdown maps its toast" 1 layer_count vgs:toast
  capture_countdown_layer="$(surface_box vgs:toast)"
  capture_countdown_card="$(ipc smoke toastWindowGeometry 0)"
  capture_countdown_crop="$(python3 -c 'import json,sys; layer,card=map(json.loads,sys.argv[1:]); print("50x20+%d+%d"%(layer[0]+card[0]+10,layer[1]+card[1]+10))' "$capture_countdown_layer" "$capture_countdown_card")" || return 1
  capture_countdown_baseline="$(capture_crop_hash "$capture_state/countdown-baseline.png")" || return 1
  expect_poll "the countdown image finishes" idle capture_phase
}
capture_countdown_image
expect "the delayed PNG contains no countdown card" True capture_countdown_pixels
capture_setting delay 0
capture_source_service="$repo/shell/plugins/vgs.capture/Service.qml"
python3 - "$capture_source_service" "$sandbox" "$rt_dir" "$capture_state/service-original.qml" <<'PY'
from pathlib import Path
import sys
service, sandbox, runtime, original = map(Path, sys.argv[1:])
assert any(service.resolve().is_relative_to(root.resolve()) for root in (sandbox, runtime)), "countdown control must stay inside the sandbox"
source = service.read_text()
original.write_text(source)
before = "if (countdownToast !== null) countdownToast();"
assert source.count(before) == 1, "countdown disposer control"
changed = source.replace(before, "if (false) countdownToast();")
assert changed != source
service.write_text(changed)
PY
expect "capture stops before the retained-countdown control" ok ipc shell setPluginEnabled vgs.capture false
expect_poll "the original capture service is released" False record_exists vgs.capture
rescan "the retained-countdown service copy is rescanned"
expect "capture enables the retained-countdown service" ok ipc shell setPluginEnabled vgs.capture true
expect_poll "the retained-countdown service is built" True record_exists vgs.capture
capture_countdown_image
expect "control: keeping the countdown fails the image readback" False capture_countdown_pixels
expect "capture stops after the retained-countdown control" ok ipc shell setPluginEnabled vgs.capture false
expect_poll "the retained-countdown service is released" False record_exists vgs.capture
cp -- "$capture_state/service-original.qml" "$capture_source_service"
rescan "the original capture service is rescanned"
expect "capture enables the restored service" ok ipc shell setPluginEnabled vgs.capture true
expect_poll "the restored capture service is built" True record_exists vgs.capture
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
expect "text reaches the clipboard" "Nested capture text" capture_clipboard
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
expect "capture starts another owned recording" ok ipc vgs.capture invoke record ''
expect_poll "the second recording is active" recording capture_phase
click_centre "$(bar_key)" vgs.capture || fail "the recording widget could not be clicked"
expect_poll "clicking the recording widget stops capture" idle capture_phase
expect "the widget clears its recording indicator after finalization" false ipc smoke readInstance "$(bar_key)" vgs.capture recording
expect "capture opens its panel" ok ipc vgs.capture invoke toggle ''
expect_poll "capture panel maps" false capture_panel
expect_poll "capture panel has a drawn layer with geometry" True capture_panel_geometry
expect "capture closes its panel" ok ipc vgs.capture invoke toggle ''
expect_poll "capture panel unmaps" absent capture_panel
expect_poll "capture panel leaves no layer" 0 layer_count vgs:panel
rm -f -- "${shim:?}/tesseract"
rescan "the missing OCR command is rescanned"
expect_poll "only OCR is unavailable" True capture_missing
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
    "display": ('boxes = outputs\n', 'boxes = windows\n', 1),
    "all": ('args = ["grim", "-g", f"{left},{top} {right - left}x{bottom - top}"]', 'args = ["grim", "-o", ""]', 1),
    "delay": ('if not self.countdown(delay, timeout):', 'if False:', 1),
    "cancel-delay": ('ready, _, _ = select.select([sys.stdin], [], [], max(0, deadline - time.monotonic()))\n                if ready and sys.stdin.readline().strip() in ("", "cancel"):\n                    return False', 'ready, _, _ = select.select([sys.stdin], [], [], max(0, deadline - time.monotonic()))\n                if ready and sys.stdin.readline().strip() == "":\n                    return False', 1),
    "cursor": ('args = args + (["-c"] if request.get("cursor", False) else [])', 'args = args', 1),
    "copy-only": ('if processing == "copy":', 'if False:', 1),
    "save-only": ('if processing != "save":', 'if True:', 1),
    "focus": ('emit("selection-ended")', 'pass', 2),
    "timeout": ('child.communicate(timeout=timeout)', 'child.communicate()', 1),
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
      expect "control: dropping the cursor flag fails the cursor readback" False capture_cursor_flag
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
      capture_setting delay 3
      capture_before="$(capture_counts)"
      capture_delay_started="$(python3 -c 'import time; print(time.time())')"
      expect "control: a delayed action starts without a countdown" ok ipc vgs.capture invoke screenshot ''
      expect_poll "control: the early capture completes" idle capture_phase
      expect "control: removing the delay fails the elapsed-time readback" False capture_delay_elapsed 3
      capture_setting delay 0
      ;;
    cancel-delay)
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
capture_config real "{\"grim\": \"$capture_real_grim\"}"
for capture_control in no-output no-clipboard hard-stop inherited-stdin; do
  python3 - "$capture_state/helper-original.py" "$capture_helper" "$capture_control" <<'PY'
from pathlib import Path
import sys
original, helper, control = sys.argv[1:]
changes = {
    "no-output": ('args = ["grim", "-o", request["output"]]', 'args = ["grim"]'),
    "no-clipboard": ('child = self.spawn(["wl-copy", "--foreground", "--type", mime], stdin=subprocess.PIPE, stderr=subprocess.PIPE)', 'child = self.spawn([sys.executable, "-c", "import sys; sys.stdin.buffer.read()"], stdin=subprocess.PIPE, stderr=subprocess.PIPE)'),
    "hard-stop": ('self.recorder.send_signal(signal.SIGINT)', 'self.recorder.send_signal(signal.SIGKILL)'),
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
expect "capture is disabled after the row" ok ipc shell setPluginEnabled vgs.capture false
expect_poll "disabled capture releases its service" False record_exists vgs.capture
expect_poll "disabling capture ends a held selection's selector and freeze" 0 capture_left
expect_poll "disabled capture releases its status" null capture_status
expect_poll "disabling capture releases all owned clipboard providers" True capture_released
for capture_tool in grim slurp hyprpicker tesseract wl-copy gpu-screen-recorder; do
  rm -f -- "${shim:?}/$capture_tool"
  if [[ -e $capture_state/saved-shims/$capture_tool ]]; then mv -- "$capture_state/saved-shims/$capture_tool" "$shim/$capture_tool"; fi
done
cp -- "$capture_saved" "$home/.config/vgshell/shell.json.next" && mv -T -- "$home/.config/vgshell/shell.json.next" "$home/.config/vgshell/shell.json"
rescan "the capture fixture cleanup is rescanned"
