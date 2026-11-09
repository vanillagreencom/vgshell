# Capture > Record > Picker, then a screen, on a nested output at transform
# 1, through the real capture service and worker, the VGS share picker,
# xdph, the public portal and gpu-screen-recorder on the world's bus with a
# PipeWire of the row's own. Choices go through the service's share-choice
# IPC. The worker hands the screen to Display mode (VGS-2242): the portal's
# recorder is gone before xdph starts a stream, xdph keeps no session, and
# the next recorder gets record-output's argv for the picked output and the
# same file. That recorder cannot record here: gpu-screen-recorder's
# monitor capture looks the name up among DRM connectors (6.1.6
# src/recorder/capture_setup.c validate_monitor_get_valid), which a nested
# output is not, so it ends with `display "NAME" not found`, the job with
# its Recording failed to start notice, and no file is left. Controls: a
# tree whose ShareSession answers the picker as before records the
# portal's stream sideways and fails the hand-off reading; its last frame
# is kept as $smoke_log_dir/picked-screen/control.png. A share another
# app opened before the job launched is answered with its choice and hands
# nothing off; a tree that hands off any request's screen fails that.
# No latency ceiling. State readbacks poll every 200 ms through expect_poll.
# inputs: shell/plugins/vgs.capture/* shell/plugins/vgs.notifications/* shell/Core/Capabilities.qml shell/Core/IpcRegistry.qml shell/Hosts/AppWindow.qml shell/Hosts/SummonHost.qml shell/Hosts/PluginSlot.qml shell/Hosts/ServiceHost.qml shell/Commons/* shell/Ui/* bin/vgshell-share-picker bin/vgshell bin/lib/ipc-reply.sh bin/lib/owned-group.py scripts/smoke/fixtures/share-picker/* scripts/smoke/toplevel/*
set -euo pipefail
for ps_required in /usr/lib/xdg-desktop-portal /usr/lib/xdg-desktop-portal-hyprland /usr/lib/xdg-permission-store /usr/bin/gpu-screen-recorder; do
  if [[ ! -x $ps_required ]]; then not_measured picked-screen missing="$ps_required"; return 0; fi
done
if ! pkg-config --exists libpipewire-0.3 wayland-client || ! command -v ffmpeg >/dev/null || ! python3 -c 'from PIL import Image' >/dev/null 2>&1; then
  not_measured picked-screen missing=recording-tools; return 0
fi
ps_world="$sandbox/picked-screen"
ps_fixture="$source_repo/scripts/smoke/fixtures/share-picker"
ps_out="$smoke_log_dir/picked-screen"
mkdir -p -- "$ps_world" "$ps_out"
ps_output=VGS-2242-OUT
cp -- "$home/.config/vgshell/shell.json" "$ps_world/shell.saved"
# The mark paints its quadrants red, green, blue and yellow from the top
# left, so any turn or mirror of a frame moves them.
python3 - "$repo/scripts/smoke/toplevel/toplevel.c" "$ps_world/mark.c" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
old = 'for (size_t i = 0; i < size / 4; i++) pixels[i] = 0xff336699;'
assert text.count(old) == 1
new = ('for (int32_t y = 0; y < height; y++) for (int32_t x = 0; x < width; x++) pixels[(size_t)y * (size_t)width + (size_t)x] = '
       'y < height / 2 ? (x < width / 2 ? 0xffff0000u : 0xff00ff00u) : (x < width / 2 ? 0xff0000ffu : 0xffffff00u);')
pathlib.Path(sys.argv[2]).write_text(text.replace(old, new, 1))
PY
cc -Wall -Wextra -Werror "$ps_world/mark.c" "$sandbox/xdg-shell-protocol.c" -I"$sandbox" -o "$ps_world/mark" $(pkg-config --cflags --libs wayland-client) || { fail "picked-screen: mark build failed"; return 0; }
# The worker's recorder: the real one for every target, each call's argv
# written to calls.jsonl first.
ps_saved_recorder=absent
if [[ -e $shim/gpu-screen-recorder ]]; then mv -- "$shim/gpu-screen-recorder" "$ps_world/recorder.saved"; ps_saved_recorder=saved; fi
ps_calls="$ps_world/calls.jsonl"
cat >"$shim/gpu-screen-recorder" <<PY
#!/usr/bin/env python3
import json, os, sys
with open("$ps_calls", "a") as log:
    log.write(json.dumps({"pid": os.getpid(), "args": sys.argv[1:]}) + "\\n")
os.execv("/usr/bin/gpu-screen-recorder", ["/usr/bin/gpu-screen-recorder", *sys.argv[1:]])
PY
chmod 755 -- "$shim/gpu-screen-recorder"
# The picker's probe reads the portal active and started after its file.
device_reply systemctl 0 $'LoadState=loaded\nActiveState=active' --user show --property=LoadState --property=ActiveState xdg-desktop-portal-hyprland.service
ps_busctl_planted=absent
if [[ ! -e $shim/busctl ]]; then
  printf '#!/usr/bin/env bash\nexec %q -c %q\n' "$(command -v python3)" 'import time; print("t %d" % (time.time_ns() // 1000))' >"$shim/busctl"
  chmod 755 -- "$shim/busctl"
  ps_busctl_planted=planted
fi
mkdir -p -- "$home/.config/xdg-desktop-portal"
printf '[preferred]\ndefault=hyprland\n' >"$home/.config/xdg-desktop-portal/portals.conf"
ps_pw_dir="$rt_dir/picked-screen-pipewire"
mkdir -m 700 -- "$ps_pw_dir"
ps_env=("${shell_env[@]}" PATH="$shell_start_path" XDG_CURRENT_DESKTOP=Hyprland PIPEWIRE_RUNTIME_DIR="$ps_pw_dir" PIPEWIRE_REMOTE=pipewire-0 PIPEWIRE_CONFIG_DIR="$ps_fixture")
spawn "$ps_out/pipewire.log" "${ps_env[@]}" pipewire -c "$ps_fixture/pipewire.conf"
ps_pw_pid="$spawn_pid"
ps_pw_ready() { [[ -S $ps_pw_dir/pipewire-0 && -S $ps_pw_dir/pipewire-0-manager ]] && echo ready || echo pending; }
expect_poll "picked-screen: the row's PipeWire owns its socket" ready ps_pw_ready
spawn "$ps_out/permission-store.log" "${ps_env[@]}" /usr/lib/xdg-permission-store
ps_perm_pid="$spawn_pid"
ps_name() { "${ps_env[@]}" gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.NameHasOwner "$1"; }
# A fresh xdph per round reads the round's tree's picker, as xdph reads its
# file once at start.
ps_xdph_pid="" ps_portal_pid="" ps_xdph_log=""
ps_portal_start() { # LABEL TREE
  printf 'screencopy {\n    custom_picker_binary = %s\n}\n' "$(realpath -- "$2/bin/vgshell-share-picker")" >"$home/.config/hypr/xdph.conf"
  ps_xdph_log="$ps_out/xdph-$1.log"
  spawn_display "$ps_xdph_log" "${ps_env[@]}" -- /usr/lib/xdg-desktop-portal-hyprland --verbose
  ps_xdph_pid="$spawn_pid"
  expect_poll "$1: xdph owns its bus name" '(true,)' ps_name org.freedesktop.impl.portal.desktop.hyprland
  spawn "$ps_out/portal-$1.log" "${ps_env[@]}" /usr/lib/xdg-desktop-portal
  ps_portal_pid="$spawn_pid"
  expect_poll "$1: the portal owns its bus name" '(true,)' ps_name org.freedesktop.portal.Desktop
}
ps_portal_stop() { # LABEL
  local p
  for p in "$ps_portal_pid" "$ps_xdph_pid"; do [[ -z $p ]] || { kill -TERM -- -"$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; }; done
  ps_portal_pid="" ps_xdph_pid=""
  expect_poll "$1: xdph left its bus name" '(false,)' ps_name org.freedesktop.impl.portal.desktop.hyprland
  expect_poll "$1: the portal left its bus name" '(false,)' ps_name org.freedesktop.portal.Desktop
}
# The row's PipeWire has no session manager, which links a stream that
# asks for it on a desktop, so this links the recorder's stream to the
# portal's source when one shows: only the control's portal makes one.
cat >"$ps_world/linker.py" <<'PY'
import json, subprocess, sys, time
deadline = time.monotonic() + float(sys.argv[1])
while time.monotonic() < deadline:
    try:
        rows = json.loads(subprocess.run(["pw-dump"], capture_output=True, timeout=3).stdout)
    except (subprocess.TimeoutExpired, ValueError) as error:
        print("pw-dump", error, flush=True); time.sleep(0.2); continue
    nodes = {r["id"]: (r.get("info") or {}).get("props", {}) for r in rows if r.get("type") == "PipeWire:Interface:Node"}
    ports = [r for r in rows if r.get("type") == "PipeWire:Interface:Port"]
    links = [(r.get("info") or {}) for r in rows if r.get("type") == "PipeWire:Interface:Link"]
    source = sorted(i for i, p in nodes.items() if p.get("media.class") == "Video/Source")[-1:]
    sink = sorted(i for i, p in nodes.items() if p.get("node.name") == "gpu-screen-recorder" and p.get("media.class") == "Stream/Input/Video")[-1:]
    if source and sink and any(l.get("output-node-id") == source[0] and l.get("input-node-id") == sink[0] for l in links):
        print("linked", source[0], sink[0], flush=True)
        sys.exit(0)
    def port(node, direction):
        return [p["id"] for p in ports if str((p.get("info") or {}).get("props", {}).get("node.id")) == str(node) and p["info"].get("direction") == direction]
    if source and sink and port(source[0], "output") and port(sink[0], "input"):
        subprocess.run(["pw-link", str(port(source[0], "output")[0]), str(port(sink[0], "input")[0])], capture_output=True, timeout=5)
    time.sleep(0.2)
print("linker: nothing to link", flush=True)
PY
# The turned output, made as capture.sh makes one, with the mark on it.
ps_rule="$(printf 'hl.monitor({ output = "%s", mode = "1920x1080@60", position = "%sx0", scale = 1, transform = 1 })' "$ps_output" "$(first_width)")"
hypr_lua_save picked-screen
printf '%s\n' "$ps_rule" >>"$home/.config/hypr/hyprland.lua"
# A rule the file holds reaches an output made after the last reload only
# through an eval, as capture.sh's turned output takes it.
ps_transform() {
  local reply
  reply="$(hypr eval "$ps_rule")" || { echo eval-failed; return; }
  [[ $reply == ok ]] || { echo eval-refused; return; }
  hypr -j monitors | py_reply 'import json,sys; m=[o for o in json.load(sys.stdin) if o["name"]==sys.argv[1]]; print("transform=%d" % m[0]["transform"] if m else "absent")' "$ps_output"
}
expect "picked-screen: the nested compositor adds the output" ok hypr output create wayland "$ps_output"
expect_poll "picked-screen: the output stands at transform 1" transform=1 ps_transform
expect "picked-screen: the mark rule applies" ok hypr eval 'hl.window_rule({ name = "picked-screen-mark", match = { class = "^smoke\\.picked-screen-mark$" }, float = true, size = { 640, 360 }, move = { 100, 120 } })'
read -r ps_cx ps_cy < <(hypr -j monitors | py_reply 'import json,sys
m = next(m for m in json.load(sys.stdin) if m["name"] == sys.argv[1])
w, h = (m["height"], m["width"]) if m["transform"] % 2 else (m["width"], m["height"])
print(round(m["x"] + w / m["scale"] / 2), round(m["y"] + h / m["scale"] / 2))' "$ps_output")
expect "picked-screen: the cursor moves onto the output" ok hypr eval "hl.dispatch(hl.dsp.cursor.move({ x = $ps_cx, y = $ps_cy }))"
spawn_display "$ps_out/mark.log" "${shell_env[@]}" -- "$ps_world/mark" smoke.picked-screen-mark "Picked screen mark"
ps_mark_pid="$spawn_pid"
acquire_toplevel "$ps_mark_pid" "$ps_out/mark.log"
ps_mark_on() { hypr -j clients | py_reply 'import json,sys; print(any(c["class"]=="smoke.picked-screen-mark" and c["mapped"] for c in json.load(sys.stdin)))'; }
expect_poll "picked-screen: the mark maps on the turned output" True ps_mark_on
ps_read() { ipc smoke readInstance service vgs.capture "$1" | py_reply 'import json,sys; print(json.load(sys.stdin))'; }
ps_share() { ipc smoke readDescendant service vgs.capture ShareSession session | py_reply 'import json,sys; d=json.load(sys.stdin); print(d["phase"] if isinstance(d,dict) else "none")'; }
ps_share_id() { ipc smoke readDescendant service vgs.capture ShareSession session | py_reply 'import json,sys; d=json.load(sys.stdin); print(d["request"]["id"] if isinstance(d,dict) else "none")'; }
ps_setting() { # LABEL KEY JSON
  local payload
  payload="$(python3 -c 'import json,sys; print(json.dumps({"key":sys.argv[1],"value":json.loads(sys.argv[2])}))' "$2" "$3")" || return 1
  expect "$1: setting $2 is accepted" ok ipc vgs.capture invoke setting "$payload"
}
# The app the early round shares for: the share-picker fixture's portal
# client, with its PipeWire consumer.
cc -Wall -Wextra -Werror "$ps_fixture/consume.c" -o "$ps_world/consume" $(pkg-config --cflags --libs libpipewire-0.3) || { fail "picked-screen: consumer build failed"; return 0; }
ps_app_phase() { python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); print(p.read_text() if p.exists() else "pending")' "$ps_world/app-$1.phase"; }
# The failure notice is read from vgs.notifications' cards.
expect "picked-screen: notifications are enabled for the failure notice" ok ipc shell setPluginEnabled vgs.notifications true
# ps_failures: the first line of each Capture failure card shown, up to
# its exit status.
ps_failures() {
  local raw
  raw="$(ipc smoke modelRows vgs.notifications rows app,summary,body,leaving)" || return 1
  if [[ $raw == absent ]]; then echo '[]'; return; fi
  py_reply 'import json,sys; print(json.dumps([r[2].split("\n")[0].split(" (exit")[0] for r in json.load(sys.stdin) if r[0]=="Capture" and r[1]=="Capture failed" and r[3]==""]))' <<<"$raw"
}
ps_recorder_log() { python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); print(p.is_file() and sys.argv[2] in p.read_text(errors="replace"))' "$home/.local/state/vgshell/plugins/vgs.capture/recorder.log" "display \"$ps_output\" not found"; }
ps_empty() { python3 -c 'import os,sys; d=sys.argv[1]; print(os.path.isdir(d) and os.listdir(d)==[])' "$1"; }
# ps_handoff: what the hand-off decided. recorders: each call's -w; argv:
# whether the second call is record-output's argv for the picked output
# with the manifest's default options and audio none, into the first
# call's file; videoSources: the portal's source nodes; starts and
# sessions: the shares xdph started and holds open; portalLeft: whether a
# portal recorder of that file still runs.
ps_handoff() {
  local dump
  dump="$("${ps_env[@]}" timeout -k 1 5 pw-dump)" || { echo pw-dump-failed; return 0; }
  py_dumps "$dump" "\"$ps_calls\"" "\"$ps_xdph_log\"" "\"$ps_output\"" <<'PY'
import json, os, sys
nodes, calls, xdph, output = (json.loads(a) for a in sys.argv[1:])
rows = [json.loads(line)["args"] for line in open(calls)] if os.path.exists(calls) else []
targets = [r[r.index("-w") + 1] for r in rows]
path = rows[0][rows[0].index("-o") + 1] if rows else None
display = ["-w", output, "-f", "60", "-k", "auto", "-q", "very_high", "-fm", "cfr", "-cursor", "no", "-o", path]
log = open(xdph, errors="replace").read() if os.path.exists(xdph) else ""
left = False
for pid in filter(str.isdigit, os.listdir("/proc")):
    try:
        argv = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")
    except OSError:
        continue
    left = left or (path is not None and b"-w" in argv and argv[argv.index(b"-w") + 1:argv.index(b"-w") + 2] == [b"portal"] and path.encode() in argv)
print(json.dumps({"recorders": targets, "argv": len(rows) == 2 and rows[1] == display,
                  "videoSources": sum(n.get("type") == "PipeWire:Interface:Node" and (n.get("info") or {}).get("props", {}).get("media.class") == "Video/Source" for n in nodes),
                  "starts": log.count("[screencopy] Start:"), "sessions": log.count("[screencopy] New session:") - log.count("[screencopy] Session destroyed"),
                  "portalLeft": left}, sort_keys=True))
PY
}
ps_handed='{"argv": true, "portalLeft": false, "recorders": ["portal", "'"$ps_output"'"], "sessions": 0, "starts": 0, "videoSources": 0}'
# ps_early LABEL: whether the app's own request got its choice and nothing
# was handed off: the app's phase, the job's phase, each recorder call's
# -w, and how many screen selections the picker gave xdph.
ps_early() {
  local phase
  phase="$(ps_read phase)" || return
  python3 -c 'import json,os,sys
calls, xdph, app, phase, output = sys.argv[1:]
rows = [json.loads(line)["args"] for line in open(calls)] if os.path.exists(calls) else []
log = open(xdph, errors="replace").read() if os.path.exists(xdph) else ""
print(json.dumps({"app": app, "phase": phase, "recorders": [r[r.index("-w") + 1] for r in rows],
                  "selections": log.count("[SELECTION]/screen:" + output)}, sort_keys=True))' "$ps_calls" "$ps_xdph_log" "$(ps_app_phase "$1")" "$phase" "$ps_output"
}
ps_answered='{"app": "complete", "phase": "capturing", "recorders": ["portal"], "selections": 1}'
# ps_classify PNG LABEL: the frame's orientation, read from where the
# mark's quadrants stand.
ps_classify() { python3 - "$@" <<'PY'
import json, sys
from PIL import Image
path, label = sys.argv[1:]
img = Image.open(path).convert("RGB")
w, h = img.size
px = img.load()
# A quadrant is told by which channels stand high against its brightest,
# so a notice's dim over the screen keeps its colour.
targets = {(True, False, False): "red", (False, True, False): "green", (False, False, True): "blue", (True, True, False): "yellow"}
sums = {k: [0, 0, 0] for k in targets.values()}
for y in range(0, h, 2):
    for x in range(0, w, 2):
        p = px[x, y]
        top = max(p)
        k = targets.get(tuple(v > top * 0.6 for v in p)) if top >= 48 else None
        if k is not None:
            s = sums[k]; s[0] += x; s[1] += y; s[2] += 1
cent = {k: (s[0] / s[2], s[1] / s[2]) if s[2] > 50 else None for k, s in sums.items()}
def axis(a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    return ("+x" if dx > 0 else "-x") if abs(dx) > abs(dy) else ("+y" if dy > 0 else "-y")
names = {("+x", "+y"): "upright", ("+y", "-x"): "turned 90 clockwise", ("-x", "-y"): "turned 180",
         ("-y", "+x"): "turned 90 counter-clockwise", ("-x", "+y"): "mirrored left-right", ("+x", "-y"): "mirrored top-bottom",
         ("+y", "+x"): "transposed", ("-y", "-x"): "anti-transposed"}
verdict = "mark-not-found" if None in (cent["red"], cent["green"], cent["blue"]) else names[(axis(cent["red"], cent["green"]), axis(cent["red"], cent["blue"]))]
print(json.dumps({"label": label, "size": [w, h], "orientation": verdict}))
PY
}
ps_capture_on() { # LABEL
  : >"$ps_calls"
  expect "$1: capture enables" ok ipc shell setPluginEnabled vgs.capture true
  expect_poll "$1: capture's service is built" True record_exists vgs.capture
  expect_poll "$1: capture is idle" idle ps_read phase
  ps_setting "$1" audio '"none"'
  ps_setting "$1" recordFolder "\"$ps_world/videos-$1\""
}
ps_choose() { # LABEL ID
  expect "$1: the screen is chosen" ok ipc vgs.capture invoke share-choice "{\"id\":\"$2\",\"choice\":{\"type\":\"screen\",\"output\":\"$ps_output\",\"remember\":false}}"
}
# ps_handoff_round: the hand-off of the job's own request.
ps_handoff_round() {
  local id
  ps_portal_start handoff "$repo"
  ps_capture_on handoff
  expect "handoff: Picker starts a recording" ok ipc vgs.capture invoke record-portal ''
  expect_poll "handoff: the portal's picker asks VGS" pending ps_share
  id="$(ps_share_id)"
  ps_choose handoff "$id"
  expect_poll "handoff: the job ends" idle ps_read phase
  expect_poll "handoff: the picked screen goes to Display mode's recorder, not the portal" "$ps_handed" ps_handoff
  printf 'picked-screen: handoff handoff=%s\n' "$(ps_handoff)"
  expect_poll "handoff: the share request is released" none ps_share
  expect_poll "handoff: the job ends in its start failure" '["Recording failed to start"]' ps_failures
  expect "handoff: the recorder could not find the nested output" True ps_recorder_log
  expect "handoff: no file is left" True ps_empty "$ps_world/videos-handoff"
  expect "handoff: capture disables" ok ipc shell setPluginEnabled vgs.capture false
  ps_portal_stop handoff
}
# ps_early_round LABEL TREE: an app's share opens before the job; the
# job's request queues behind it in xdph.
ps_early_round() {
  local label="$1" id own
  ps_portal_start "$label" "$2"
  ps_capture_on "$label"
  spawn "$ps_out/app-$label.log" "${ps_env[@]}" timeout 90 python3 "$ps_fixture/portal-client.py" "$ps_world/app-$label" "$ps_world/consume"
  ps_app_pid="$spawn_pid"
  expect_poll "$label: the app's picker asks VGS" pending ps_share
  id="$(ps_share_id)"
  expect "$label: Picker starts a recording behind the app's share" ok ipc vgs.capture invoke record-portal ''
  ps_choose "$label" "$id"
  expect_poll "$label: the app's request gets its screen and nothing is handed off" "$ps_answered" ps_early "$label"
  printf 'picked-screen: %s early=%s\n' "$label" "$(ps_early "$label")"
  # Every request still open is cancelled, so its caller ends: the job's
  # own, which opens once the app's is answered while the job waits, and
  # the app's when a hand-off held it.
  ps_own() { ps_share_id | py_reply 'import sys; s=sys.stdin.read().strip(); print(s not in ("none", sys.argv[1]))' "$id"; }
  [[ $(ps_read phase) != capturing ]] || expect_poll "$label: the job's own request opens" True ps_own
  own="$(ps_share_id)"
  [[ $own == none ]] || expect "$label: the open request is cancelled" ok ipc vgs.capture invoke share-cancel "{\"id\":\"$own\"}"
  [[ $(ps_read phase) == idle ]] || expect "$label: the waiting recording is cancelled" ok ipc vgs.capture invoke record-portal ''
  expect_poll "$label: capture is idle again" idle ps_read phase
  own="$(ps_share_id)"
  [[ $own == none ]] || expect "$label: the job's request is cancelled" ok ipc vgs.capture invoke share-cancel "{\"id\":\"$own\"}"
  kill -TERM -- -"$ps_app_pid" 2>/dev/null || true
  wait "$ps_app_pid" 2>/dev/null || true
  expect "$label: capture disables" ok ipc shell setPluginEnabled vgs.capture false
  ps_portal_stop "$label"
}
ps_handoff_round
ps_early_round early "$repo"
# Control: the portal answers the screen. Its recording runs, stops and
# saves; the hand-off reading alone fails, and the frame reads sideways.
copy_tree picked-screen-portal
if edit_tree picked-screen-portal shell/plugins/vgs.capture/ShareSession.qml \
    'const handed = answer.choice !== null && typeof answer.choice === "object" && answer.choice.type === "screen" && handOff(answer.id, answer.choice.output);' \
    'const handed = false;'; then
  stop_shell || :
  start_shell "$sandbox/tree-picked-screen-portal" "$sandbox/picked-screen-portal.log"
  ps_portal_start control "$sandbox/tree-picked-screen-portal"
  ps_capture_on control
  spawn "$ps_out/linker-control.log" "${ps_env[@]}" timeout 40 python3 "$ps_world/linker.py" 30
  ps_linker_pid="$spawn_pid"
  expect "control: Picker starts a recording" ok ipc vgs.capture invoke record-portal ''
  expect_poll "control: the portal's picker asks VGS" pending ps_share
  ps_choose control "$(ps_share_id)"
  expect_poll "control: the portal's recording runs" recording ps_read phase
  ps_control() {
    (failures=0 behaviour_failures=0
    expect_poll "control: the picked screen goes to Display mode's recorder, not the portal" "$ps_handed" ps_handoff >"$ps_world/control.log"
    echo "failures=$failures")
  }
  expect "control: the portal's own recording fails the hand-off reading" failures=1 ps_control
  control_output "$ps_world/control.log"
  expect "control: the recording stops" ok ipc vgs.capture invoke record-portal ''
  expect_poll "control: capture is idle again" idle ps_read phase
  ps_path="$(ps_read lastPath)"
  ps_orientation() { ffmpeg -hide_banner -loglevel error -y -sseof -1 -i "$ps_path" -frames:v 1 "$ps_out/control.png" && ps_classify "$ps_out/control.png" control | py_reply 'import json,sys; print(json.load(sys.stdin)["orientation"])'; }
  expect "control: the portal records the output at transform 1 sideways" "turned 90 clockwise" ps_orientation
  kill -TERM -- -"$ps_linker_pid" 2>/dev/null || true
  wait "$ps_linker_pid" 2>/dev/null || true
  expect "control: capture disables" ok ipc shell setPluginEnabled vgs.capture false
  ps_portal_stop control
fi
# Control: a service that hands off any request's screen takes the app's.
copy_tree picked-screen-claim
if edit_tree picked-screen-claim shell/plugins/vgs.capture/Service.qml 'job.shareId !== id || ' ''; then
  stop_shell || :
  start_shell "$sandbox/tree-picked-screen-claim" "$sandbox/picked-screen-claim.log"
  ps_claim_control() {
    (failures=0 behaviour_failures=0
    ps_early_round claim "$sandbox/tree-picked-screen-claim" >"$ps_world/claim-control.log"
    grep -q -F -- "FAIL  claim: the app's request gets its screen and nothing is handed off" "$ps_world/claim-control.log" && echo "failures=$failures named=True" || echo "failures=$failures named=False")
  }
  expect "control: handing off the app's request fails the early reading alone" "failures=1 named=True" ps_claim_control
  control_output "$ps_world/claim-control.log"
fi
stop_shell || :
start_shell "$repo" "$sandbox/picked-screen-restored.log"
cp -- "$ps_calls" "$ps_world/control.log" "$ps_world/claim-control.log" "$ps_out/" 2>/dev/null || true
close_toplevel "$ps_mark_pid" "picked-screen: the mark closes"
expect "picked-screen: the nested compositor removes the output" ok hypr output remove "$ps_output"
for ps_process in "$ps_perm_pid" "$ps_pw_pid"; do kill -TERM -- -"$ps_process" 2>/dev/null || true; wait "$ps_process" 2>/dev/null || true; done
hypr_lua_restore picked-screen
rm -rf -- "${home:?}/.config/xdg-desktop-portal"
rm -f -- "${home:?}/.config/hypr/xdph.conf" "${shim:?}/gpu-screen-recorder"
if [[ $ps_saved_recorder == saved ]]; then mv -- "$ps_world/recorder.saved" "$shim/gpu-screen-recorder"; fi
if [[ $ps_busctl_planted == planted ]]; then rm -f -- "${shim:?}/busctl"; fi
device_reply_clear systemctl
cp -- "$ps_world/shell.saved" "$home/.config/vgshell/shell.json.next"
mv -T -- "$home/.config/vgshell/shell.json.next" "$home/.config/vgshell/shell.json"
