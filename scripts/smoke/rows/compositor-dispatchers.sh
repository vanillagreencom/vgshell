# The compositor provider's window, monitor and pointer operations, sent
# through the existing acme.probe dispatch handle. Read each effect from
# Hyprland, not from the queue's `ok`. Before each effect, a hyprctl copy
# answers `ok` without dispatching: the same state assertion must fail
# once. The control logs stay in the sandbox. State polls use the shared
# expect_poll interval of 200 ms; no latency budget is measured here.
# Fullscreen is focused-window-only in both dialects. Move and resize are
# absolute layout coordinates and size, respectively.
# Repeated sets wait for a distinct pointer move queued behind them before
# reading the already-matching state. A toggle control uses that same read.
# inputs: scripts/smoke/fixtures/plugins/acme.probe/* shell/Core/Compositor.qml shell/Core/Dispatch.js scripts/smoke/toplevel/* scripts/smoke/rows/capabilities.sh
set -euo pipefail

dispatch_client() { # ADDRESS FIELD
  hypr -j clients | py_reply 'import json,sys
c = next((c for c in json.load(sys.stdin) if c["address"] == sys.argv[1]), None)
print("absent" if c is None else json.dumps(c[sys.argv[2]]))' "$1" "$2"
}
dispatch_monitor() {
  hypr -j monitors | py_reply 'import json,sys
print(next((m["name"] for m in json.load(sys.stdin) if m["focused"]), "absent"))'
}
dispatch_cursor() {
  hypr -j cursorpos | py_reply 'import json,sys
p = json.load(sys.stdin); print(json.dumps([p["x"], p["y"]]))'
}
dispatch_plan() { # ADDRESS: sentinel1 sentinel2 move1 move2 size1 size2 cursor1 cursor2, or refused:...
  hypr --batch 'j/monitors; j/clients; j/getoption general:float_gaps' | py_reply '
import json, math, sys
text = sys.stdin.read()
decoder, at, parts = json.JSONDecoder(), 0, []
while len(parts) < 3:
    while at < len(text) and text[at].isspace(): at += 1
    part, at = decoder.raw_decode(text, at)
    parts.append(part)
monitors, clients, gaps = parts
cs = [c for c in clients if c["address"] == sys.argv[1]]
if len(cs) != 1:
    print("refused: dispatch target windows=%d" % len(cs)); sys.exit()
c = cs[0]
ms = [m for m in monitors if m["id"] == c["monitor"]]
if len(ms) != 1:
    print("refused: dispatch monitor id=%s absent" % c["monitor"]); sys.exit()
m = ms[0]
mx, my = math.ceil(m["x"]), math.ceil(m["y"])
mw, mh = math.floor(m["width"] / m["scale"]), math.floor(m["height"] / m["scale"])
if mw < 4 or mh < 2:
    print("refused: dispatch logical-monitor=%dx%d" % (mw, mh)); sys.exit()
sx = mx + max(0, min(mw - 2, mw // 5))
sy = my + max(0, min(mh - 1, mh // 5))
sentinel2_x = sx + 1
cx0 = mx + max(0, min(mw - 1, mw // 4))
cy0 = my + max(0, min(mh - 1, mh // 4))
cx1 = mx + max(0, min(mw - 1, (mw * 3) // 5))
cy1 = my + max(0, min(mh - 1, (mh * 3) // 5))
if (cx0, cy0) == (cx1, cy1):
    cx1 = min(mx + mw - 1, cx0 + 1)
top, right, bottom, left = (int(v) for v in gaps["css"].split())
rl, rt, rr, rb = m["reserved"]
area_x = math.ceil(m["x"] + rl + left)
area_y = math.ceil(m["y"] + rt + top)
area_w = math.floor(m["width"] / m["scale"] - rl - rr - left - right)
area_h = math.floor(m["height"] / m["scale"] - rt - rb - top - bottom)
cw, ch = c["size"]
if area_w < cw + 2 or area_h < ch + 2:
    print("refused: dispatch work-area=%dx%d current=%dx%d" % (area_w, area_h, cw, ch)); sys.exit()
move1_x = area_x + max(0, (area_w - cw) // 5)
move1_y = area_y + max(0, (area_h - ch) // 5)
move2_x = area_x + max(0, ((area_w - cw) * 2) // 5)
move2_y = area_y + max(0, ((area_h - ch) * 2) // 5)
if (move1_x, move1_y) == (move2_x, move2_y):
    print("refused: dispatch work-area=%dx%d current=%dx%d no-second-position" % (area_w, area_h, cw, ch)); sys.exit()
if area_w < 2 or area_h < 2:
    print("refused: dispatch work-area=%dx%d no-second-size" % (area_w, area_h)); sys.exit()
w1, h1 = max(1, area_w // 2), max(1, area_h // 2)
w2, h2 = max(1, (area_w * 3) // 5), max(1, (area_h * 3) // 5)
if w1 == w2:
    w2 = w2 + 1 if w2 < area_w else w1 - 1
if h1 == h2:
    h2 = h2 + 1 if h2 < area_h else h1 - 1
if w2 <= 0 or h2 <= 0:
    print("refused: dispatch work-area=%dx%d no-positive-second-size" % (area_w, area_h)); sys.exit()
print(sx, sy, sentinel2_x, sy, move1_x, move1_y, move2_x, move2_y, w1, h1, w2, h2, cx0, cy0, cx1, cy1)' "$1"
}

cat >"$shim/hyprctl.dispatch-noop" <<EOF
#!/usr/bin/env bash
if [[ \${1:-} == dispatch ]]; then
  printf '%s\n' "\$2" >>"$sandbox/dispatch-dropped.log"
  echo ok
else
  exec "$hyprctl_bin" "\$@"
fi
EOF
chmod 755 "$shim/hyprctl.dispatch-noop"
: >"$sandbox/dispatch-dropped.log"
dispatch_drops() { wc -l <"$sandbox/dispatch-dropped.log"; }
# A fake successful transport must fail the effect's real assertion. The
# assertion runs in a subshell so only its controlled failure is counted.
dispatch_noop_control() { # REQUEST WANT READER [ARGS...]
  local request="$1" want="$2" log="$sandbox/dispatch-control-${1%% *}.log" count before
  shift 2
  before="$(dispatch_drops)"
  shim_hyprctl dispatch-noop
  expect "control: the queue accepts $request with a dropped transport" ok probe dispatch "$request"
  expect_poll "control: the transport drops $request" "$((before + 1))" dispatch_drops
  (
    failures=0
    row_class=behaviour
    expect "the dropped dispatch has no requested effect" "$want" "$@"
    printf 'control-failures=%s\n' "$failures"
  ) >"$log"
  count="$(sed -n 's/^control-failures=//p' "$log")"
  expect "control: dropping ${request%% *} fails its readback once" 1 printf '%s' "$count"
  shim_hyprctl real
}

# The queue serializes requests. A new pointer position proves the request
# ahead of it completed, even when that request should leave state alone.
dispatch_completed_state() { # LABEL REQUEST WANT READER [ARGS...]
  local label="$1" request="$2" want="$3"
  shift 3
  expect "$label: the completion sentinel resets" ok probe dispatch "moveCursor $dispatch_sentinel_x $dispatch_sentinel_y"
  expect_poll "$label: the completion sentinel starts elsewhere" "[$dispatch_sentinel_x, $dispatch_sentinel_y]" dispatch_cursor
  expect "$label: the request and completion sentinel are queued" 'ok,ok' probe batch "$request;moveCursor $dispatch_sentinel2_x $dispatch_sentinel2_y"
  expect_poll "$label: the queued request completes before readback" "[$dispatch_sentinel2_x, $dispatch_sentinel2_y]" dispatch_cursor
  expect "$label" "$want" "$@"
}

dispatch_toggle_control() { # NAME SET_REQUEST WANT FIELD
  local name="$1" request="$2" want="$3" field="$4" log="$sandbox/dispatch-repeat-$1-control.log" count
  (
    failures=0
    row_class=behaviour
    dispatch_completed_state "a repeated $name set keeps its state" "${request% set} toggle" "$want" dispatch_client "$dispatch_target" "$field"
    printf 'control-failures=%s\n' "$failures"
  ) >"$log"
  count="$(sed -n 's/^control-failures=//p' "$log")"
  expect "control: toggling a repeated $name set fails its completed readback once" 1 printf '%s' "$count"
  expect "the $name state is restored after the toggle control" ok probe dispatch "$request"
  expect_poll "the restored $name state is read back" "$want" dispatch_client "$dispatch_target" "$field"
}

if open_toplevel "$sandbox/dispatch-target.log" smoke.dispatch target; then
  dispatch_target_pid="$toplevel_pid"
  dispatch_target="$(toplevel_address "$dispatch_target_pid")"
  if open_toplevel "$sandbox/dispatch-other.log" smoke.dispatch other; then
    dispatch_other_pid="$toplevel_pid"
    dispatch_other="$(toplevel_address "$dispatch_other_pid")"
    dispatch_plan_line="$(dispatch_plan "$dispatch_target")" || dispatch_plan_line="refused: dispatch plan unreadable"
    if [[ $dispatch_plan_line == refused:* ]]; then
      geometry fail "$dispatch_plan_line"
      dispatch_plan_line="0 0 1 0 0 0 1 1 1 1 2 2 0 0 1 1"
    fi
    read -r dispatch_sentinel_x dispatch_sentinel_y dispatch_sentinel2_x dispatch_sentinel2_y \
      dispatch_move_start_x dispatch_move_start_y dispatch_move_x dispatch_move_y \
      dispatch_resize_start_w dispatch_resize_start_h dispatch_resize_w dispatch_resize_h \
      dispatch_cursor_start_x dispatch_cursor_start_y dispatch_cursor_x dispatch_cursor_y <<<"$dispatch_plan_line"
    expect_poll "the other window is focused before addressed operations" '["smoke.dispatch", "other"]' active_window
    expect_poll "the target starts tiled" false dispatch_client "$dispatch_target" floating
    dispatch_noop_control "floatWindow $dispatch_target set" true dispatch_client "$dispatch_target" floating
    expect "float addresses the target, not the active window" ok probe dispatch "floatWindow $dispatch_target set"
    expect_poll "float makes the addressed window floating" true dispatch_client "$dispatch_target" floating
    expect "float leaves the active window tiled" false dispatch_client "$dispatch_other" floating
    dispatch_completed_state "a repeated float set keeps its state" "floatWindow $dispatch_target set" true dispatch_client "$dispatch_target" floating
    dispatch_toggle_control float "floatWindow $dispatch_target set" true floating
    expect "float unset is accepted" ok probe dispatch "floatWindow $dispatch_target unset"
    expect_poll "float unset tiles the target" false dispatch_client "$dispatch_target" floating
    expect "float toggle is accepted" ok probe dispatch "floatWindow $dispatch_target toggle"
    expect_poll "float toggle floats the target again" true dispatch_client "$dispatch_target" floating

    expect "the target gets a known starting position" ok probe dispatch "moveWindow $dispatch_target $dispatch_move_start_x $dispatch_move_start_y"
    geometry expect_poll "the starting position is read back" "[$dispatch_move_start_x, $dispatch_move_start_y]" dispatch_client "$dispatch_target" at
    dispatch_noop_control "moveWindow $dispatch_target $dispatch_move_x $dispatch_move_y" "[$dispatch_move_x, $dispatch_move_y]" dispatch_client "$dispatch_target" at
    expect "an absolute move is accepted" ok probe dispatch "moveWindow $dispatch_target $dispatch_move_x $dispatch_move_y"
    geometry expect_poll "move puts the addressed window at the requested position" "[$dispatch_move_x, $dispatch_move_y]" dispatch_client "$dispatch_target" at
    expect "the target gets a known starting size" ok probe dispatch "resizeWindow $dispatch_target $dispatch_resize_start_w $dispatch_resize_start_h"
    geometry expect_poll "the starting size is read back" "[$dispatch_resize_start_w, $dispatch_resize_start_h]" dispatch_client "$dispatch_target" size
    dispatch_noop_control "resizeWindow $dispatch_target $dispatch_resize_w $dispatch_resize_h" "[$dispatch_resize_w, $dispatch_resize_h]" dispatch_client "$dispatch_target" size
    expect "an absolute resize is accepted" ok probe dispatch "resizeWindow $dispatch_target $dispatch_resize_w $dispatch_resize_h"
    geometry expect_poll "resize gives the addressed window the requested size" "[$dispatch_resize_w, $dispatch_resize_h]" dispatch_client "$dispatch_target" size
    expect "move and resize leave the other window focused" '["smoke.dispatch", "other"]' active_window

    expect "the target is focused for fullscreen" ok probe dispatch "focusWindow $dispatch_target"
    expect_poll "the target has the focus for fullscreen" '["smoke.dispatch", "target"]' active_window
    expect "the target starts without fullscreen" 0 dispatch_client "$dispatch_target" fullscreen
    dispatch_noop_control "fullscreenWindow fullscreen set" 2 dispatch_client "$dispatch_target" fullscreen
    expect "fullscreen set is accepted" ok probe dispatch "fullscreenWindow fullscreen set"
    expect_poll "fullscreen sets the focused window's state" 2 dispatch_client "$dispatch_target" fullscreen
    dispatch_completed_state "a repeated fullscreen set keeps its state" "fullscreenWindow fullscreen set" 2 dispatch_client "$dispatch_target" fullscreen
    dispatch_toggle_control fullscreen "fullscreenWindow fullscreen set" 2 fullscreen
    expect "fullscreen unset is accepted" ok probe dispatch "fullscreenWindow fullscreen unset"
    expect_poll "fullscreen unset restores the window" 0 dispatch_client "$dispatch_target" fullscreen
    expect "maximized toggle is accepted" ok probe dispatch "fullscreenWindow maximized toggle"
    expect_poll "maximized mode is distinct from fullscreen" 1 dispatch_client "$dispatch_target" fullscreen
    expect "maximized unset is accepted" ok probe dispatch "fullscreenWindow maximized unset"
    expect_poll "maximized unset restores the window" 0 dispatch_client "$dispatch_target" fullscreen
    expect "fullscreen leaves the other window unchanged" 0 dispatch_client "$dispatch_other" fullscreen

    expect "the pointer gets a known starting position" ok probe dispatch "moveCursor $dispatch_cursor_start_x $dispatch_cursor_start_y"
    geometry expect_poll "the starting pointer position is read back" "[$dispatch_cursor_start_x, $dispatch_cursor_start_y]" dispatch_cursor
    dispatch_noop_control "moveCursor $dispatch_cursor_x $dispatch_cursor_y" "[$dispatch_cursor_x, $dispatch_cursor_y]" dispatch_cursor
    expect "cursor move is accepted" ok probe dispatch "moveCursor $dispatch_cursor_x $dispatch_cursor_y"
    geometry expect_poll "cursor move changes the compositor's pointer position" "[$dispatch_cursor_x, $dispatch_cursor_y]" dispatch_cursor

    # The headless output has no usable size on NVIDIA. Suppress mouse
    # focus and warps in this nested configuration alone so the pointer's
    # monitor cannot immediately take focus back from that output.
    dispatch_config="$home/.config/hypr/hyprland.lua"
    cp -- "$dispatch_config" "$sandbox/hyprland-before-dispatch.lua"
    printf '%s\n' 'hl.config({ input = { follow_mouse = 0 }, cursor = { no_warps = true }, misc = { mouse_move_focuses_monitor = false } })' >>"$dispatch_config"
    expect "the nested configuration holds explicit monitor focus" ok hypr reload config-only
    dispatch_first_monitor="$(dispatch_monitor)"
    dispatch_output=SMOKE-DISPATCH
    expect "the nested compositor adds the focus target monitor" ok hypr output create headless "$dispatch_output"
    dispatch_noop_control "focusMonitor $dispatch_output" "$dispatch_output" dispatch_monitor
    expect "monitor focus is accepted" ok probe dispatch "focusMonitor $dispatch_output"
    expect_poll "monitor focus changes Hyprland's focused monitor" "$dispatch_output" dispatch_monitor
    expect "monitor focus returns to the original monitor" ok probe dispatch "focusMonitor $dispatch_first_monitor"
    expect_poll "the original monitor has the focus again" "$dispatch_first_monitor" dispatch_monitor
    expect "the nested compositor removes the focus target monitor" ok hypr output remove "$dispatch_output"
    cp -- "$sandbox/hyprland-before-dispatch.lua" "$dispatch_config.next"
    mv -T -- "$dispatch_config.next" "$dispatch_config"
    expect "the nested configuration restores its mouse focus settings" ok hypr reload config-only

    close_toplevel "$dispatch_other_pid" "the other dispatch window exits"
  else
    fail "the other dispatch window maps"
  fi
  close_toplevel "$dispatch_target_pid" "the target dispatch window exits"
else
  fail "the target dispatch window maps"
fi
expect "the dispatch row returns to workspace 1" ok probe dispatch "focusWorkspace 1"
rm -f -- "${shim:?}/hyprctl.dispatch-noop"
