# The capture service runs stand-ins. grim always, and slurp and hyprpicker for
# the dragged area, run as the real tools on the nested socket.
# inputs: shell/plugins/vgs.capture/* shell/Core/Capabilities.qml shell/Core/Config.qml shell/Core/IpcRegistry.qml shell/Core/Lifetime.js shell/Core/MonitorLogic.js shell/Core/MonitorState.qml shell/Core/Notices.qml shell/Core/PackageManagers.js shell/Core/PluginLogic.js shell/Core/Plugins.qml shell/Core/PluginStatus.qml shell/Core/Registry.qml shell/Core/ServiceGate.qml shell/Core/ShortcutRegistry.qml shell/Core/Toasts.qml shell/Hosts/BarHost.qml shell/Hosts/NoticeHost.qml shell/Hosts/OverlaySurface.qml shell/Hosts/PluginSlot.qml shell/Hosts/ServiceHost.qml shell/Hosts/Summon* shell/Hosts/ToastHost.qml shell/Ui/* shell/Commons/* bin/vgsh-scan bin/lib/check-manifests.js bin/lib/qml-library.js scripts/test-capture.py scripts/smoke/fixtures/capture/*
# Mode dimensions come from Hyprland. The row plants dropped-output,
# dropped-clipboard, SIGKILL and inherited-stdin controls and requires each
# assertion to fail.
# Readbacks use the harness's state poll, with no capture latency budget.
set -euo pipefail
capture_state="$sandbox/capture-world"
capture_saved="$sandbox/shell-before-capture.json"
capture_real_grim="$(command -v grim)" || { fail "capture: grim is unavailable"; return 0; }
capture_real_slurp="$(command -v slurp)" || { fail "capture: slurp is unavailable"; return 0; }
capture_real_picker="$(command -v hyprpicker)" || { fail "capture: hyprpicker is unavailable"; return 0; }
cp -- "$home/.config/vgs/shell.json" "$capture_saved"
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
capture_geometry() { python3 -c 'import json,sys; rows=[json.loads(l) for l in open(sys.argv[1])]; print([r["args"] for r in rows if r["tool"]=="grim"][-1][:2])' "$capture_state/calls.jsonl"; }
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
expect_poll "earlier capture notices expire before cancellation" 0 capture_toasts
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
for capture_control in no-output no-clipboard hard-stop inherited-stdin; do
  python3 - "$capture_state/helper-original.py" "$capture_helper" "$capture_control" <<'PY'
from pathlib import Path
import sys
original, helper, control = sys.argv[1:]
changes = {
    "no-output": ('path = self.grab(request, ["grim", "-o", request["output"]])', 'path = self.grab(request, ["grim"])'),
    "no-clipboard": ('child = self.copy(image, "image/png")', 'child = self.spawn([sys.executable, "-c", "import sys; sys.stdin.buffer.read()"], stdin=image, stderr=subprocess.PIPE)'),
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
cp -- "$capture_saved" "$home/.config/vgs/shell.json.next" && mv -T -- "$home/.config/vgs/shell.json.next" "$home/.config/vgs/shell.json"
rescan "the capture fixture cleanup is rescanned"
