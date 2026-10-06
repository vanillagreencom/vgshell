# Scratchpads. Pads are made from the Settings window: the Scratchpads
# page's Add button appends one under the lowest whole number no pad names,
# each field is set through its drawn editor, Remove deletes one, and the
# page draws what shell.json holds, field for field. A second pad left on
# the first one's window class is reported among the plugin's problems,
# keeps its Keys row, and its key starts no app and shows one toast. The
# pad the row works with runs the harness's toplevel helper with its own
# app-id a second after a press, logging each start, its screen the first
# monitor, its key recorded through the Keys row; the generated layer holds
# its window rule and bind with an empty `configerrors`. Its key, typed on
# the nested seat with the app not running, starts the app once and shows
# the pad: a reader of Hyprland's monitors and clients every 20 ms through
# the start never sees the pad's special workspace shown without its
# window, and its control, the workspace toggled while it holds no window,
# reads an empty pad. Shown, the window is tiled at the configured shares
# of its monitor's work area, anchored as configured, at the sandbox's
# mode, at 1440x900 and at 3008x1692 at scale 2, and again after a mode
# change while it is shown; it has the keyboard, and the key hides it and
# gives the keyboard back to the window that had it, not the one under the
# pointer. Two presses during a start leave the pad hidden once its window
# maps; bursts of two and three presses end hidden and shown, as many
# toggles as presses, read from Hyprland's `activespecial` events. A pad
# window moved out of its workspace comes back on the next press. A change
# of size, position, entry or motion takes effect on the next press. On a
# second, headless monitor named as the pad's screen, with the pointer on
# the nested output, the pad opens there, and `focused` opens it on the
# nested output; a focus move to a window on the nested output hides it. A
# press beside the shown pad hides it. A pad whose app maps no window ends
# in exactly one toast. A start with the pad set to start at login starts
# its app once, hidden, and a shell started again takes that window and
# starts nothing. Turning Scratchpads off and Remove each bring the pad's
# window to the focused workspace, and Remove takes its bind out of
# Hyprland and its rule out of the layer. Three controls start copies of the
# tree. In the first the background takes no click: a press beside the
# pad leaves it shown across the real reading's 5 s. In the second the
# layer writes no focus hook and no refit on a layout change: a focus move
# leaves the pad on the second monitor shown, and the box keeps the old
# mode's size after a mode change. In the third the layer writes no gaps
# for a pad: the window fills the work area. The keyboard's way back after
# a hide has no control: Hyprland gives it back to the window focused
# last on its own.
# Every key goes to the nested instance alone, through wtype on its seat,
# with `input:resolve_binds_by_sym` on so a typed key reaches its bind
# (runtime-hyprland-capture.md), and the row puts the harness hyprland.lua
# back at its end.
# No latency is measured; each reading polls every 200 ms for up to 5 s,
# the toast reading every 200 ms for up to 25 s.
# inputs: shell/plugins/vgs.scratchpads/* shell/plugins/vgs.settings/* shell/Core/Pads.js shell/Core/HyprlandLayer.js shell/Core/HyprlandLayer.qml shell/Core/PluginLogic.js shell/Core/Dispatch.js shell/Core/Compositor.qml shell/Core/Capabilities.qml shell/Hosts/BackgroundHost.qml bin/lib/qml-library.js
set -euo pipefail

sp_id=vgs.scratchpads
sp_class=org.vgs.pad.smoke
sp_ws=special:vgs-pad-1
sp_user="$home/.config/vgshell/shell.json"
sp_layer="$home/.local/state/vgshell/hypr/vgs.lua"
sp_events="$sandbox/scratchpads-events.log"

# sp_list ARG: one of the probe's list verbs on the Settings page's Pads
# field; ARG is JSON naming the item, the field and the value.
sp_list() { ipc smoke invokeInstance window vgs.settings "$1" "$2"; }
# sp_drawn: the names of the items the Pads field draws, as JSON.
sp_drawn() { sp_list listItems "{\"id\":\"$sp_id\",\"key\":\"pads\"}" | py_reply 'import json,sys; print(json.dumps([i["name"] for i in json.load(sys.stdin)]))'; }
# sp_field FIELD VALUE [NAME]: pad NAME's (1 by default) drawn FIELD
# editor sends VALUE, JSON.
sp_field() { sp_list listApply "{\"id\":\"$sp_id\",\"key\":\"pads\",\"name\":\"${3:-1}\",\"field\":\"$1\",\"value\":$2}"; }
sp_add() { sp_list listAdd "{\"id\":\"$sp_id\",\"key\":\"pads\"}"; }
sp_remove() { sp_list listRemove "{\"id\":\"$sp_id\",\"key\":\"pads\",\"name\":\"$1\"}"; }
# sp_drawn_same: `same` while the Pads field draws each pad of shell.json
# with the same value in each field, in order, else both.
sp_drawn_same() {
  local drawn
  drawn="$(sp_list listItems "{\"id\":\"$sp_id\",\"key\":\"pads\"}")" || return 1
  sp_pads | py_reply 'import json,sys; f=json.load(sys.stdin); d=json.loads(sys.argv[1]); print("same" if json.dumps(d, sort_keys=True) == json.dumps(f, sort_keys=True) else "drawn=%s file=%s" % (sys.argv[1], json.dumps(f)))' "$drawn"
}
# sp_pads: the pads the user file holds, as JSON, or `absent`.
sp_pads() { python3 -c 'import json,sys; rows=[r for r in json.load(open(sys.argv[1])).get("plugins", []) if r["id"] == "vgs.scratchpads"]; print(json.dumps(rows[0]["pads"], sort_keys=True) if rows and "pads" in rows[0] else "absent")' "$sp_user"; }
sp_pad_field() { sp_pads | py_reply 'import json,sys; p=json.load(sys.stdin); print(json.dumps(p[0][sys.argv[1]]) if p else "none")' "$1"; }
sp_key() { python3 -c 'import json,sys; rows=[r for r in json.load(open(sys.argv[1])).get("plugins", []) if r["id"] == "vgs.scratchpads"]; k=rows[0].get("keys", {}) if rows else {}; print(json.dumps(k.get(sys.argv[2], "absent")))' "$sp_user" "pad-${1:-1}"; }
# sp_key_row NAME: `drawn` while the page draws a Keys row for pad NAME.
sp_key_row() { local got; got="$(ipc smoke invokeInstance window vgs.settings keyField "{\"id\":\"$sp_id\",\"shortcut\":\"pad-$1\"}")" || return 1; [[ $got == \{* ]] && echo drawn || echo "$got"; }
# sp_problems: the plugin's `hyprland: ` problems listPlugins reports.
sp_problems() { ipc shell listPlugins | py_reply 'import json,sys; print(json.dumps(sorted(e["error"] for e in json.load(sys.stdin)["errors"] if e["error"].startswith("hyprland: pad"))))'; }
# sp_starts: how many times the pad's app started, from the line its
# command logs before it runs the helper.
sp_starts() { if [[ -f $sandbox/pad-starts ]]; then wc -l <"$sandbox/pad-starts"; else echo 0; fi; }
# sp_started_2: `started` once pad 2's app logged its start, else `absent`.
sp_started_2() { if [[ -e $sandbox/pad-starts-2 ]]; then echo started; else echo absent; fi; }
sp_press() { type_keys -M logo -M alt -k p -m alt -m logo; }
# sp_presses N: N presses of the pad's key in one wtype run.
sp_presses() {
  local words=() i
  for ((i = 0; i < $1; i++)); do words+=(-M logo -M alt -k p -m alt -m logo); done
  type_keys "${words[@]}"
}
sp_config_errors() { hypr -j configerrors | py_reply 'import json,sys; print(json.dumps([e for e in json.load(sys.stdin) if e]))'; }
sp_layer_has() { if grep -qF -- "$1" "$sp_layer"; then echo yes; else echo no; fi; }
sp_bound() { hypr -j binds | py_reply 'import json,sys; print(any(b["description"] == "vgs.scratchpads:pad-1" and b["submap"] in ("", "default") for b in json.load(sys.stdin)))'; }
# sp_active_class: the class of the window that has the keyboard, or none.
sp_active_class() { hypr -j activewindow | py_reply 'import json,sys; d=json.load(sys.stdin); print(d.get("class") or "none")'; }
# sp_windows: how many mapped windows of the pad's class Hyprland lists.
sp_windows() { hypr -j clients | py_reply 'import json,sys; print(sum(1 for c in json.load(sys.stdin) if c["class"] == sys.argv[1] and c["mapped"]))' "$sp_class"; }
# sp_state: `shown` while a monitor shows the pad's workspace with the
# pad's window active in it, `hidden` while no monitor shows it, else what
# differs.
sp_state() {
  local batch
  batch="$(hypr --batch 'j/monitors;j/clients;j/activewindow')" || return 1
  py_reply '
import json, sys
monitors, clients, active = (json.loads(p) for p in sys.stdin.read().split("\n\n\n") if p.strip())
ws = sys.argv[1]
on = [m["name"] for m in monitors if m["specialWorkspace"]["name"] == ws]
mine = [c for c in clients if c["workspace"]["name"] == ws and c["mapped"]]
if not on: print("hidden"); sys.exit()
if not mine: print("empty"); sys.exit()
print("shown" if active.get("address") == mine[0]["address"] else "shown-unfocused")' "$sp_ws" <<<"$batch"
}
# sp_watch SECONDS: the pad's state every 20 ms for SECONDS, as the
# distinct states it read in order; `empty` among them is a pad shown with
# no window.
sp_watch() {
  python3 - "$1" "$sp_ws" "$signature" "${shell_env[@]}" <<'PY'
import json, subprocess, sys, time
seconds, ws, sig, env = float(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4:]
seen = []
end = time.monotonic() + seconds
while time.monotonic() < end:
    out = subprocess.run(env + ["hyprctl", "-i", sig, "--batch", "j/monitors;j/clients"], capture_output=True, text=True).stdout
    parts = [p for p in out.split("\n\n\n") if p.strip()]
    if len(parts) == 2:
        monitors, clients = json.loads(parts[0]), json.loads(parts[1])
        on = any(m["specialWorkspace"]["name"] == ws for m in monitors)
        held = any(c["workspace"]["name"] == ws and c["mapped"] for c in clients)
        state = "hidden" if not on else "shown" if held else "empty"
        if not seen or seen[-1] != state: seen.append(state)
    time.sleep(0.02)
print(" ".join(seen))
PY
}
# sp_box: how far the pad's window sits from where its shares put it on
# its monitor, [dx, dy, dw, dh] in logical pixels, each 0 when within 1.5
# of where it sits, which a share's rounding to whole pixels stays inside; the window box less the border Hyprland draws around it.
# WIDTH HEIGHT MARGIN are the pad's shares and ACROSS DOWN its anchors,
# start, center or end.
sp_box() { # WIDTH HEIGHT MARGIN ACROSS DOWN
  local border batch
  border="$(hypr -j getoption general:border_size | py_reply 'import json,sys; print(json.load(sys.stdin)["int"])')" || return 1
  batch="$(hypr --batch 'j/monitors;j/clients')" || return 1
  py_reply '
import json, math, sys
monitors, clients = (json.loads(p) for p in sys.stdin.read().split("\n\n\n") if p.strip())
ws, border, wide, tall, margin, across, down = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5]), sys.argv[6], sys.argv[7]
mons = [m for m in monitors if m["specialWorkspace"]["name"] == ws]
mine = [c for c in clients if c["workspace"]["name"] == ws and c["mapped"]]
if len(mons) != 1 or len(mine) != 1: print("monitors=%d windows=%d" % (len(mons), len(mine))); sys.exit()
m, c = mons[0], mine[0]
if c["floating"]: print("floating"); sys.exit()
w, h = m["width"] / m["scale"], m["height"] / m["scale"]
if m["transform"] % 2 == 1: w, h = h, w
left, top, right, bottom = m["reserved"]
area_w, area_h = w - left - right, h - top - bottom
box_w, box_h = area_w * wide / 100, area_h * tall / 100
gap = min(area_w, area_h) * margin / 100
place = lambda anchor, free: min(gap, free) if anchor == "start" else max(free - gap, 0) if anchor == "end" else free / 2
x, y = m["x"] + left + place(across, area_w - box_w), m["y"] + top + place(down, area_h - box_h)
got = [c["at"][0] - border, c["at"][1] - border, c["size"][0] + 2 * border, c["size"][1] + 2 * border]
want = [x, y, box_w, box_h]
print(json.dumps([0 if abs(g - v) <= 1.5 else round(g - v) for g, v in zip(got, want)]))' "$sp_ws" "$border" "$@" <<<"$batch"
}
# sp_monitor: the name of the monitor that shows the pad, or `none`.
sp_monitor() { hypr -j monitors | py_reply 'import json,sys; m=[m["name"] for m in json.load(sys.stdin) if m["specialWorkspace"]["name"] == sys.argv[1]]; print(m[0] if m else "none")' "$sp_ws"; }
sp_leaf() { hypr -j animations | py_reply '
import json, sys
data = json.load(sys.stdin)
rows = data[0] if data and isinstance(data[0], list) else data
row = next((r for r in rows if r.get("name") == sys.argv[1]), None)
print("absent" if row is None else json.dumps([row.get("enabled"), row.get("style", "")]))' "$1"; }
# sp_pad_loaded LUA: `loaded` once the layer Hyprland has loaded holds pad
# 1 with the Lua condition LUA over `pad` true, else `not-loaded` and
# hyprctl's reply. The shell reloads Hyprland in a Process after it writes
# the layer file, so the file can hold a change Hyprland has not loaded;
# a press before that load toggles the old pad, and the load after it sets
# the special workspace leaves back to the configuration's
# (docs/architecture/runtime-hyprland.md). A function run
# through `hyprctl dispatch` that raises answers its error text, not `ok`.
sp_pad_loaded() {
  local reply
  if reply="$(hypr dispatch "function() local pad = hl.__vgs_pads ~= nil and hl.__vgs_pads.list[\"1\"] or nil if pad == nil or not ($1) then error(\"vgs-pad=not-loaded\") end end" 2>&1)" && [[ $reply == ok ]]; then
    echo loaded
  else
    printf 'not-loaded reply=[%s]\n' "$reply"
  fi
}
# The `activespecial` lines of Hyprland's event socket since line N of
# its log, as `<workspace>@<monitor>` words.
sp_specials_since() { tail -n "+$(($1 + 1))" -- "$sp_events" | sed -n 's/^activespecial>>\(.*\),\(.*\)$/\1@\2/p' | tr '\n' ' ' | sed 's/ $//'; }
sp_event_lines() { wc -l <"$sp_events"; }
# sp_specials_then LINE WANT: the `activespecial` words since line LINE
# once they read WANT, polled every 200 ms for up to 10 s, and then once
# more after a quiet 600 ms, so an extra toggle after them shows.
sp_specials_then() {
  local got=""
  for _ in $(seq 1 50); do
    got="$(sp_specials_since "$1")"
    [[ $got == "$2" ]] && break
    sleep 0.2
  done
  sleep 0.6 # an extra toggle the burst queued lands within this
  sp_specials_since "$1"
}
# sp_holds STATE: `held` when sp_state reads STATE at each of 25 readings
# 200 ms apart, the window a real reading polls for a change, else the
# first other reading.
sp_holds() {
  local got
  for _ in $(seq 1 25); do
    got="$(sp_state)" || return 1
    [[ $got == "$1" ]] || { echo "$got"; return; }
    sleep 0.2
  done
  echo held
}
sp_shown() { ipc smoke statusValues "$sp_id" | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get("shown")))'; }
# sp_away: `sits` when sp_box reads the pad at its shares, else `differs`.
sp_away() { local got; got="$(sp_box "$@")" || return 1; [[ $got == "[0, 0, 0, 0]" ]] && echo sits || echo differs; }
# sp_toast_count TITLE: how many shown toasts carry TITLE.
sp_toast_count() { ipc shell lent | py_reply 'import json,sys; t=json.load(sys.stdin)["toasts"]; print(sum(1 for e in t["visible"] + t["waiting"] if e["title"] == sys.argv[1]))' "$1"; }
# sp_toast_within TITLE: `shown` once a toast with TITLE shows, polled
# every 200 ms for up to 25 s, else `absent`.
sp_toast_within() {
  for _ in $(seq 1 125); do
    [[ $(sp_toast_count "$1") -ge 1 ]] && { echo shown; return; }
    sleep 0.2
  done
  echo absent
}
# sp_window_workspace: `special` while a window of the pad's class is in a
# special workspace, `regular` while every one is in a regular one, `none`
# with none.
sp_window_workspace() { hypr -j clients | py_reply 'import json,sys; w=[c["workspace"]["name"] for c in json.load(sys.stdin) if c["class"] == sys.argv[1] and c["mapped"]]; print("special" if any(n.startswith("special:") for n in w) else "regular" if w else "none")' "$sp_class"; }
# sp_close_windows: every window of the pad's class closed through Hyprland,
# which the toplevel helper answers by exiting 0.
sp_close_windows() {
  local address
  for address in $(hypr -j clients | py_reply 'import json,sys; print(" ".join(c["address"] for c in json.load(sys.stdin) if c["class"] == sys.argv[1]))' "$sp_class"); do
    hypr dispatch "hl.dsp.window.close({ window = \"address:$address\" })" >/dev/null || true
  done
}

spawn "$sp_events" python3 -u -c '
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
buf = b""
while True:
    data = s.recv(4096)
    if not data: break
    buf += data
    while b"\n" in buf:
        line, buf = buf.split(b"\n", 1)
        print(line.decode(errors="replace"), flush=True)
' "$rt_dir/hypr/$signature/.socket2.sock"
sp_events_pid="$spawn_pid"

hypr_lua_save scratchpads
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$home/.config/hypr/hyprland.lua"
expect "the nested instance reloads with typed keys reaching their binds" ok hypr reload config-only
expect_poll "the nested instance holds no configuration error" '[]' sp_config_errors

sp_before="$(plugin_enabled "$sp_id")" || sp_before=unread
sp_settings_before="$(record_exists vgs.settings)" || sp_settings_before=unread
expect "enabling Scratchpads is allowed" ok ipc shell setPluginEnabled "$sp_id" true
expect_poll "the Scratchpads service is built" True record_exists "$sp_id"
sp_monitor_name="$(first_name)" || fail "the first monitor's name is unreadable"
rm -f -- "${sandbox:?}/pad-starts" "${sandbox:?}/pad-starts-2"
# The pad's app: the helper a second after the press, so an early show
# would read empty for that second, its start logged first.
sp_app="sleep 1; echo start >>$sandbox/pad-starts; exec $sandbox/toplevel $sp_class Pad"

# The list field: two Adds, a second pad on the first one's class, Remove
# and an Add that takes the lowest free name again.
settings_page_open "$sp_id"
expect "the page draws no pad at first" '[]' sp_drawn
expect "the page's Add button is clicked" clicked sp_add
expect_poll "Add writes one pad named 1" '["1"]' sp_drawn
expect "the page's Add button is clicked again" clicked sp_add
expect_poll "a second Add writes pad 2 beside pad 1" '["1", "2"]' sp_drawn
expect_poll "the page draws each pad as shell.json holds it" same sp_drawn_same
expect_poll "a second pad on the first one's class is reported" '["hyprland: pad 2 of vgs.scratchpads skipped: class=org.vgs.pad held by pad 1"]' sp_problems
expect_poll "the refused pad keeps its Keys row" drawn sp_key_row 2
expect "pad 2's app logs its start" applied sp_field command "\"echo start >>$sandbox/pad-starts-2\"" 2
expect_poll "pad 2's app reaches shell.json" same sp_drawn_same
expect "pad 2's shortcut is pressed" ok hypr dispatch 'hl.dsp.global("vgs.scratchpads:pad-2")'
expect "the refused pad's press says why" shown sp_toast_within "Pad 2 cannot open"
expect "the refused pad's press shows one toast" 1 sp_toast_count "Pad 2 cannot open"
expect "the refused pad's press starts no app" absent sp_started_2
expect "pad 1's Remove button is clicked" clicked sp_remove 1
expect_poll "Remove leaves pad 2 alone" '["2"]' sp_drawn
expect "the page's Add button is clicked after Remove" clicked sp_add
expect_poll "Add takes the lowest free name again, after pad 2" '["2", "1"]' sp_drawn
expect "pad 2's Remove button is clicked" clicked sp_remove 2
expect_poll "Remove leaves pad 1 alone" '["1"]' sp_drawn
expect_poll "no pad is reported once one pad is left" '[]' sp_problems
for pair in "command \"$sp_app\"" "class \"$sp_class\"" "width 50" "height 40" "position \"top\"" "margin 2" "motion \"none\"" "screen \"$sp_monitor_name\""; do
  field="${pair%% *}"
  value="${pair#* }"
  expect "the pad's $field editor takes $value" applied sp_field "$field" "$value"
  expect_poll "the pad's $field reaches shell.json" "$value" sp_pad_field "$field"
done
expect_poll "the page draws the pad as shell.json holds it" same sp_drawn_same
expect "the Keys row records the pad's key" applied ipc smoke invokeInstance window vgs.settings applyKey "{\"id\":\"$sp_id\",\"shortcut\":\"pad-1\",\"key\":\"SUPER+ALT+P\"}"
expect_poll "the pad's key reaches shell.json" '"SUPER+ALT+P"' sp_key 1
expect "the Settings window is hidden" ok ipc shell hide window vgs.settings
expect_poll "the layer holds the pad's window rule" yes sp_layer_has 'hl.window_rule({ name = "vgs.scratchpads:pad-1", match = { class = "^org\\.vgs\\.pad\\.smoke$" }, workspace = "special:vgs-pad-1 silent", tile = true'
expect_poll "Hyprland holds the pad's bind" True sp_bound
expect_poll "the layer holds no configuration error" '[]' sp_config_errors
expect "no window of the pad's class runs before its first press" 0 sp_windows

# The first press starts the app once; the pad shows once its window maps.
rest_pointer
sp_watch 6 >"$sandbox/scratchpads-watch.log" &
sp_watch_pid=$!
sleep 0.3 # the reader is running before the key is typed
sp_press || fail "typing the pad's key failed"
wait "$sp_watch_pid" || fail "the start reader failed"
expect "through the start the pad is never shown empty" "hidden shown" tail -n 1 "$sandbox/scratchpads-watch.log"
expect_poll "the first press shows the pad with its window focused" shown sp_state
expect "the first press starts the app once" 1 sp_starts
expect "one window of the pad's class runs" 1 sp_windows
geometry expect_poll "the pad sits at its shares at the sandbox's mode" '[0, 0, 0, 0]' sp_box 50 40 2 center start
sp_press || fail "typing the pad's key to hide failed"
expect_poll "the key hides the pad" hidden sp_state

# Control: the reader reads an empty pad when the pad's workspace is shown
# with no window in it.
sp_close_windows
expect_poll "the pad's window is closed" 0 sp_windows
sp_watch 2 >"$sandbox/scratchpads-control-watch.log" &
sp_watch_pid=$!
sleep 0.3 # the reader is running before the workspace is shown
hypr dispatch 'hl.dsp.workspace.toggle_special("vgs-pad-1")' >/dev/null || fail "control: toggling the empty workspace failed"
wait "$sp_watch_pid" || fail "control: the reader failed"
expect "control: the reader reads a workspace shown with no window as empty" "hidden empty" tail -n 1 "$sandbox/scratchpads-control-watch.log"
hypr dispatch 'hl.dsp.workspace.toggle_special("vgs-pad-1")' >/dev/null || fail "control: hiding the empty workspace failed"
expect_poll "control: the empty workspace is hidden again" hidden sp_state

# Two presses during a start: the window maps and the pad stays hidden.
sp_lines="$(sp_event_lines)"
sp_presses 2 || fail "typing two presses failed"
expect_poll "two presses during a start map the pad's window" 1 sp_windows
expect "two presses during a start show nothing" "" sp_specials_then "$sp_lines" ""
expect "two presses during a start leave the pad hidden" hidden sp_state
expect "two presses during a start start the app once" 2 sp_starts

# Bursts on a running app: as many toggles as presses.
sp_lines="$(sp_event_lines)"
sp_presses 2 || fail "typing a burst of two failed"
expect "a burst of two shows and hides once" "$sp_ws@$sp_monitor_name @$sp_monitor_name" sp_specials_then "$sp_lines" "$sp_ws@$sp_monitor_name @$sp_monitor_name"
expect "a burst of two ends hidden" hidden sp_state
sp_lines="$(sp_event_lines)"
sp_presses 3 || fail "typing a burst of three failed"
expect "a burst of three toggles three times" "$sp_ws@$sp_monitor_name @$sp_monitor_name $sp_ws@$sp_monitor_name" sp_specials_then "$sp_lines" "$sp_ws@$sp_monitor_name @$sp_monitor_name $sp_ws@$sp_monitor_name"
expect "a burst of three ends shown" shown sp_state

# A press on the screen beside the shown pad hides it.
expect_poll "the service publishes the pad its screen shows" "{\"$sp_monitor_name\": \"1\"}" sp_shown
click 5 "$((mon_h - 5))" || fail "pressing beside the pad failed"
expect_poll "a press beside the pad hides it" hidden sp_state
rest_pointer

# A pad window moved out of its workspace comes back on the next press.
sp_address="$(hypr -j clients | py_reply 'import json,sys; print(next((c["address"] for c in json.load(sys.stdin) if c["class"] == sys.argv[1]), "none"))' "$sp_class")" || fail "the pad's window address is unreadable"
expect "the pad's window moves to workspace 1" ok hypr dispatch "hl.dsp.window.move({ workspace = \"1\", window = \"address:$sp_address\", follow = false })"
expect_poll "the moved window is on a regular workspace" regular sp_window_workspace
sp_press || fail "typing the pad's key after the move failed"
expect_poll "the next press brings the moved window back and shows it" shown sp_state
expect "the press after the move starts no app" 2 sp_starts
sp_press || fail "typing the pad's key to hide after the move failed"
expect_poll "the key hides the pad after the move" hidden sp_state

# The keyboard goes back to the window that had it, not the one under the
# pointer: two helpers of another class tile beside each other, the
# pointer rests on the second, the first has the keyboard. No control
# reads this: a layer copy that gives the keyboard to no window on a hide
# read the first helper too, since Hyprland gives the keyboard back to the
# window focused last (read on host cachy on 2026-10-04).
# sp_focus_rows LABEL_PREFIX WANT: those readings; WANT is the class that
# has the keyboard after the hide.
sp_focus_rows() {
  local first second first_address second_box x y
  open_toplevel "$sandbox/scratchpads-focus-a.log" smoke.focus-a "Focus A" || { fail "$1the first focus helper maps"; return; }
  first="$toplevel_pid"
  open_toplevel "$sandbox/scratchpads-focus-b.log" smoke.focus-b "Focus B" || { fail "$1the second focus helper maps"; close_toplevel "$first" "$1the first focus helper exits 0"; return; }
  second="$toplevel_pid"
  first_address="$(toplevel_address "$first")"
  second_box="$(hypr -j clients | py_reply 'import json,sys; c=[c for c in json.load(sys.stdin) if c["pid"] == int(sys.argv[1])][0]; print(int(c["at"][0] + c["size"][0] / 2), int(c["at"][1] + c["size"][1] / 2))' "$second")"
  read -r x y <<<"$second_box"
  hover "$x" "$y" || fail "$1the pointer rests on the second helper"
  expect "$1the first helper takes the keyboard" ok hypr dispatch "hl.dsp.focus({ window = \"address:$first_address\" })"
  expect_poll "$1the first helper has the keyboard" smoke.focus-a sp_active_class
  sp_press || fail "$1typing the pad's key over the helpers failed"
  expect_poll "$1the pad shows over the helpers" shown sp_state
  sp_press || fail "$1typing the pad's key to hide over the helpers failed"
  expect_poll "$1the key hides the pad over the helpers" hidden sp_state
  expect_poll "$1the hide gives the keyboard to $2" "$2" sp_active_class
  close_toplevel "$second" "$1the second focus helper exits 0 on SIGTERM"
  close_toplevel "$first" "$1the first focus helper exits 0 on SIGTERM"
  rest_pointer
}
sp_focus_rows "" smoke.focus-a

# Each change takes effect on the next press.
settings_page_open "$sp_id"
for pair in "width 80" "height 30" "position \"bottom-left\"" "margin 5" "entry \"left\"" "motion \"slide\""; do
  field="${pair%% *}"
  value="${pair#* }"
  expect "the pad's $field editor takes $value" applied sp_field "$field" "$value"
  expect_poll "the pad's $field reaches shell.json" "$value" sp_pad_field "$field"
done
expect "the Settings window is hidden after the changes" ok ipc shell hide window vgs.settings
expect_poll "the layer holds the changed pad" yes sp_layer_has 'pads.list["1"] = { x = "start", y = "end", width = 80, height = 30, margin = 5, entry = "left", motion = "slide" }'
expect_poll "Hyprland loads the changed pad's layer" loaded sp_pad_loaded 'pad.x == "start" and pad.y == "end" and pad.width == 80 and pad.height == 30 and pad.margin == 5 and pad.entry == "left" and pad.motion == "slide"'
sp_unloaded="$(sp_pad_loaded 'pad.motion == "fade"')"
expect "control: the loaded-layer reader refuses a pad Hyprland does not hold" not-loaded echo "${sp_unloaded%% *}"
sp_press || fail "typing the pad's key after the changes failed"
expect_poll "the next press shows the changed pad" shown sp_state
geometry expect_poll "the changed pad sits at its new shares" '[0, 0, 0, 0]' sp_box 80 30 5 start end
expect "the pad slides in from its entry side" '[true, "slide left"]' sp_leaf specialWorkspaceIn
expect "the pad slides out to its entry side" '[true, "slide right"]' sp_leaf specialWorkspaceOut
sp_press || fail "typing the pad's key to hide the changed pad failed"
expect_poll "the key hides the changed pad" hidden sp_state
settings_page_open "$sp_id"
expect "the pad's motion editor takes none" applied sp_field motion '"none"'
expect "the pad's position editor takes center" applied sp_field position '"center"'
expect "the Settings window is hidden after the motion change" ok ipc shell hide window vgs.settings
expect_poll "the layer holds the motionless pad" yes sp_layer_has 'motion = "none" }'
expect_poll "Hyprland loads the motionless pad's layer" loaded sp_pad_loaded 'pad.x == "center" and pad.y == "center" and pad.motion == "none"'
sp_press || fail "typing the pad's key after the motion change failed"
expect_poll "the motionless pad shows" shown sp_state
expect "the pad shows with no special workspace animation" '[false, ""]' sp_leaf specialWorkspaceIn
geometry expect_poll "the centred pad sits at the centre" '[0, 0, 0, 0]' sp_box 80 30 5 center center
sp_press || fail "typing the pad's key to hide the motionless pad failed"
expect_poll "the key hides the motionless pad" hidden sp_state

# The pad's screen: a second monitor named as its screen while the pointer
# is on the nested output, and `focused`. A focus move to a window on the
# nested output hides the pad on the second monitor. The headless output
# lists no size, so the box is not read there.
sp_screen_output=SMOKE-PAD
# sp_screen_rows LABEL_PREFIX WANT: those readings, real and control; WANT
# is the monitor that shows the pad after the focus move, none once hidden.
sp_screen_rows() {
  local helper helper_address
  expect "$1the nested compositor adds a monitor for the pad" ok hypr output create headless "$sp_screen_output"
  settings_page_open "$sp_id"
  expect "$1the pad's screen editor takes the second monitor" applied sp_field screen "\"$sp_screen_output\""
  expect "$1the Settings window is hidden after the screen change" ok ipc shell hide window vgs.settings
  expect_poll "$1the second monitor reaches shell.json" "\"$sp_screen_output\"" sp_pad_field screen
  rest_pointer
  open_toplevel "$sandbox/scratchpads-screen.log" smoke.screen "Screen" || fail "$1the nested output's helper maps"
  helper="$toplevel_pid"
  helper_address="$(toplevel_address "$helper")"
  sp_press || fail "$1typing the pad's key for the second monitor failed"
  expect_poll "$1the pad opens on the monitor it names, not the pointer's" "$sp_screen_output" sp_monitor
  expect "$1a window on the nested output takes the keyboard" ok hypr dispatch "hl.dsp.focus({ window = \"address:$helper_address\" })"
  expect_poll "$1a focus move off the pad leaves it on $2" "$2" sp_monitor
  if [[ $(sp_monitor) != none ]]; then
    expect "$1the pad is hidden on the second monitor" ok hypr dispatch 'hl.__vgs_pads.toggle("1","")'
    expect_poll "$1the pad is hidden before the monitor goes" none sp_monitor
  fi
  close_toplevel "$helper" "$1the nested output's helper exits 0 on SIGTERM"
  settings_page_open "$sp_id"
  expect "$1the pad's screen editor takes focused" applied sp_field screen '"focused"'
  expect "$1the Settings window is hidden after focused" ok ipc shell hide window vgs.settings
  expect_poll "$1focused reaches shell.json" '"focused"' sp_pad_field screen
  sp_press || fail "$1typing the pad's key for the focused monitor failed"
  expect_poll "$1focused opens the pad on the pointer's monitor" "$sp_monitor_name" sp_monitor
  sp_press || fail "$1typing the pad's key to hide on the focused monitor failed"
  expect_poll "$1the key hides the pad on the focused monitor" none sp_monitor
  expect "$1the nested compositor removes the pad's monitor" ok hypr output remove "$sp_screen_output"
}
sp_screen_rows "" none

# The same shares at 1440x900, at 3008x1692 at scale 2, and after a mode
# change while the pad is shown.
sp_base_mode="$(first_mode)" || fail "the first monitor's mode is unreadable"
for hold in "1440x900 1" "3008x1692 2"; do
  read -r mode scale <<<"$hold"
  hold_mode "the nested compositor holds $sp_monitor_name at $mode scale $scale for the pad" "$sp_monitor_name" "$mode" "$scale"
  sp_press || fail "typing the pad's key at $mode failed"
  expect_poll "the pad shows at $mode scale $scale" shown sp_state
  geometry expect_poll "the pad sits at its shares at $mode scale $scale" '[0, 0, 0, 0]' sp_box 80 30 5 center center
  sp_press || fail "typing the pad's key to hide at $mode failed"
  expect_poll "the key hides the pad at $mode scale $scale" hidden sp_state
  release_mode "the nested compositor gives $sp_monitor_name its own mode after $mode" "$sp_monitor_name" "$sp_base_mode"
done
# sp_refit_rows LABEL_PREFIX WANT: the pad shown at 1440x900, then the
# mode given back while it shows; WANT is sp_away's reading after it. A
# hold never taken leaves no mode change to read, so only the release
# runs.
sp_refit_rows() {
  local held=false
  hold_mode "$1the nested compositor holds $sp_monitor_name at 1440x900 before the pad shows" "$sp_monitor_name" 1440x900
  [[ ${#mode_hold[@]} -eq 0 ]] || held=true
  if [[ $held == true ]]; then
    sp_press || fail "$1typing the pad's key before the mode change failed"
    expect_poll "$1the pad shows before the mode change" shown sp_state
  fi
  release_mode "$1the nested compositor gives $sp_monitor_name its own mode while the pad shows" "$sp_monitor_name" "$sp_base_mode"
  if [[ $held == true ]]; then
    geometry expect_poll "$1after a mode change while shown the pad $2" "$2" sp_away 80 30 5 center center
    sp_press || fail "$1typing the pad's key after the mode change failed"
    expect_poll "$1the key hides the pad after the mode change" hidden sp_state
  fi
}
sp_refit_rows "" sits

# A pad whose app maps no window ends in exactly one toast.
sp_close_windows
expect_poll "the pad's window is closed before the failing start" 0 sp_windows
settings_page_open "$sp_id"
expect "the pad's command editor takes a command that maps nothing" applied sp_field command '"true"'
expect "the Settings window is hidden after the command change" ok ipc shell hide window vgs.settings
expect_poll "the failing command reaches shell.json" '"true"' sp_pad_field command
sp_press || fail "typing the pad's key for the failing start failed"
expect "a start that maps no window ends in a toast" shown sp_toast_within "Pad 1 did not open"
expect "a start that maps no window ends in one toast" 1 sp_toast_count "Pad 1 did not open"
expect "the failed start shows no pad" hidden sp_state

# The pad set to start at login; the first control tree's start reads it.
settings_page_open "$sp_id"
expect "the pad's command editor takes the helper again" applied sp_field command "\"$sp_app\""
expect "the pad's preload switch turns on" applied sp_field preload true
expect "the Settings window is hidden before the controls" ok ipc shell hide window vgs.settings
expect_poll "the helper command reaches shell.json" "\"$sp_app\"" sp_pad_field command
expect_poll "the preload reaches shell.json" true sp_pad_field preload
sp_starts_before="$(sp_starts)"

# Control: a background that takes no click. The tree keeps the gaps, so
# the press beside the pad lands beside its window.
if copy_tree scratchpads-background \
  && edit_tree scratchpads-background shell/plugins/vgs.scratchpads/Background.qml '        enabled: root.shown' '        enabled: false'; then
  stop_shell
  start_shell "$sandbox/tree-scratchpads-background" "$sandbox/scratchpads-background.log" || fail "the Scratchpads background control shell starts"
  expect_poll "control: the Scratchpads service is built" True record_exists "$sp_id"
  expect_poll "a preloaded pad's app starts with the shell" 1 sp_windows
  expect "a preloaded pad starts its app once" "$((sp_starts_before + 1))" sp_starts
  expect "a preloaded pad stays hidden" hidden sp_state
  rest_pointer
  sp_press || fail "control: typing the pad's key failed"
  expect_poll "control: the pad shows" shown sp_state
  geometry expect_poll "control: the pad sits at its shares with the gaps kept" '[0, 0, 0, 0]' sp_box 80 30 5 center center
  click 5 "$((mon_h - 5))" || fail "control: pressing beside the pad failed"
  expect "control: a background that takes no click leaves the pad shown through the real reading's window" held sp_holds shown
  rest_pointer
  sp_press || fail "control: typing the pad's key to hide failed"
  expect_poll "control: the key hides the pad" hidden sp_state
  stop_shell
  sp_starts_before="$(sp_starts)"
  start_shell "$repo" "$sandbox/scratchpads-restart.log" || fail "the shell starts again after the background control"
  expect_poll "the restarted Scratchpads service is built" True record_exists "$sp_id"
  rest_pointer
  sp_press || fail "typing the pad's key after the restart failed"
  expect_poll "the restarted service shows the pad it found" shown sp_state
  expect "the restarted service starts no second app" "$sp_starts_before" sp_starts
  expect "one window of the pad's class runs after the restart" 1 sp_windows
  sp_press || fail "typing the pad's key to hide after the restart failed"
  expect_poll "the key hides the pad after the restart" hidden sp_state
fi

# Control: a layer that keeps the gaps but writes no focus hook and no
# refit on a layout change.
sp_stopped=false
if copy_tree scratchpads-hooks \
  && edit_tree scratchpads-hooks shell/Core/HyprlandLayer.js 'if visible ~= nil and current ~= pads.prefix .. name then hide(name, visible.monitor, false) end' 'local _ = visible' \
  && edit_tree scratchpads-hooks shell/Core/HyprlandLayer.js '        "    hl.on(\"monitor.layout_changed\", refit)",' ''; then
  stop_shell
  sp_stopped=true
  start_shell "$sandbox/tree-scratchpads-hooks" "$sandbox/scratchpads-hooks.log" || fail "the Scratchpads hooks control shell starts"
  expect_poll "control: the hooks copy's Scratchpads service is built" True record_exists "$sp_id"
  sp_screen_rows "control: " "$sp_screen_output"
  sp_refit_rows "control: " differs
  stop_shell
fi

# Control: a layer that writes no gaps for a pad.
if copy_tree scratchpads-gaps \
  && edit_tree scratchpads-gaps shell/Core/HyprlandLayer.js '        "        hl.workspace_rule({ workspace = pads.prefix .. name, gaps_in = 0, gaps_out = { top = top, right = width - w - left, bottom = height - h - top, left = left } })",' ''; then
  stop_shell
  sp_stopped=true
  start_shell "$sandbox/tree-scratchpads-gaps" "$sandbox/scratchpads-gaps.log" || fail "the Scratchpads gaps control shell starts"
  expect_poll "control: the gaps copy's Scratchpads service is built" True record_exists "$sp_id"
  expect_poll "control: the layer holds the pad with no gaps" no sp_layer_has 'hl.workspace_rule({ workspace = pads.prefix .. name'
  rest_pointer
  sp_press || fail "control: typing the pad's key in the gaps copy failed"
  expect_poll "control: the pad shows in the gaps copy" shown sp_state
  geometry expect_poll "control: a pad with no gaps of its own does not sit at its shares" differs sp_away 80 30 5 center center
  sp_press || fail "control: typing the pad's key to hide in the gaps copy failed"
  expect_poll "control: the key hides the pad in the gaps copy" hidden sp_state
  stop_shell
fi
if [[ $sp_stopped == true ]]; then
  start_shell "$repo" "$sandbox/scratchpads-restart-2.log" || fail "the shell starts again after the layer controls"
  expect_poll "the Scratchpads service is built again after the layer controls" True record_exists "$sp_id"
fi

# Turning Scratchpads off brings the pad's window to the focused
# workspace; turning it on takes it back into the pad.
expect_poll "the pad's window is in the pad before Scratchpads turns off" special sp_window_workspace
expect "disabling Scratchpads is allowed" ok ipc shell setPluginEnabled "$sp_id" false
expect_poll "turning Scratchpads off brings the pad's window to the focused workspace" regular sp_window_workspace
expect "enabling Scratchpads again is allowed" ok ipc shell setPluginEnabled "$sp_id" true
expect_poll "the Scratchpads service is built after it turns on" True record_exists "$sp_id"
expect_poll "turning Scratchpads on takes the window back into the pad" special sp_window_workspace

# Remove drops the pad: its bind leaves Hyprland and the layer.
settings_page_open "$sp_id"
expect "the pad's Keys row is reset" applied ipc smoke invokeInstance window vgs.settings applyKey "{\"id\":\"$sp_id\",\"shortcut\":\"pad-1\"}"
expect_poll "the reset removes the pad's key from shell.json" '"absent"' sp_key 1
expect "the pad's Remove button is clicked" clicked sp_remove 1
expect_poll "Remove writes no pad to shell.json" '[]' sp_pads
expect_poll "the page draws no pad after Remove" '[]' sp_drawn
expect "the Settings window is hidden after Remove" ok ipc shell hide window vgs.settings
expect_poll "the removed pad's bind is gone from Hyprland" False sp_bound
expect_poll "the removed pad's window rule leaves the layer" no sp_layer_has 'name = "vgs.scratchpads:pad-1"'
expect_poll "the removed pad's window comes to the focused workspace" regular sp_window_workspace

sp_close_windows
expect_poll "no window of the pad's class is left" 0 sp_windows
kill -TERM -- "$sp_events_pid" 2>/dev/null || true
hypr_lua_restore scratchpads || fail "Scratchpads puts the harness hyprland.lua back"
expect "the nested instance reloads the harness hyprland.lua" ok hypr reload config-only
if [[ $sp_settings_before != True ]]; then
  expect "Settings is disabled again after the pads" ok ipc shell setPluginEnabled vgs.settings false
  expect_poll "the Settings service is gone after the pads" False record_exists vgs.settings
fi
case "$sp_before" in
  True) ;;
  False)
    expect "Scratchpads is disabled again" ok ipc shell setPluginEnabled "$sp_id" false
    expect_poll "the Scratchpads service is gone" False record_exists "$sp_id"
    ;;
  *) fail "Scratchpads' enabled state before the row: got $sp_before" ;;
esac
