# The screen freeze, held by the fixture service through capability
# `screencopy` over two outputs, the second turned a quarter (transform 1,
# as cachy's DP-2 is): one surface per output, on the overlay layer,
# covering the whole output, listed in the lending record, its `done` told
# once every output shows its frame. A floating window marks the turned
# output's top-left quarter. Each output's frozen frame matches the
# live frame read just before it, upright and unstretched, and hides a
# theme change made under it until the thaw, after which the change shows.
# A second hold is refused, a thaw ends it and the fixture's disable
# releases it. A disposable tree that turns the turned output's frame a
# second time, as the external picker that froze the screen before did on
# Hyprland 0.57.0, fails the frame match on that output alone.
# Each hold draws the screen as it is when the hold starts: a hold over a
# solid window on each output, a thaw, the windows closed with no capture
# running, then a second hold whose frame holds none of the windows on
# either output. The grim reads of the first hold leave each output's
# capture mirror kept, as on a desktop after its first screenshot:
# Hyprland 0.57.0 stops no wlr-screencopy session when its client leaves
# (protocols/Screencopy.cpp captureOutput, ScreenshareManager.cpp
# getManagedSession), so the second hold reads a mirror only its damage
# tracking refreshed. A disposable tree whose surfaces outlive the thaw
# keeps the first hold's frame and fails the check on both outputs.
# A hold that asks for the still gets every output's frame written once it
# shows: PPM bands of at most 2 MP, each output's device size, in a
# directory of its own under $XDG_RUNTIME_DIR/vgshell/freeze, mode 0700,
# which a thaw and a disable remove. A thaw at the hold's done, before any
# frame is written, gets no still answer, and malformed options are
# refused. The control tree's end() skips the removal, and the first hold's
# directory stays. A screen removed while its bands are written ends the
# still with `failed: still=screen-gone` and the shell lives on; a tree
# that does not cancel the chain on a screen change leaves the still
# unanswered.
# inputs: scripts/smoke/fixtures/plugins/acme.freeze/* shell/Core/ScreenFreeze.qml shell/Core/FreezeBands.js shell/Hosts/FreezeHost.qml shell/Core/Capabilities.qml shell/Core/HyprlandLayer.js shell/Core/HyprlandLayer.qml shell/shell.qml themes/catalog/flexoki-light/theme.json
set -euo pipefail
freeze_world="$sandbox/screen-freeze"
freeze_socket="$(shot_socket "$rt_dir" "$nested_socket")"
freeze_theme="$home/.config/vgshell/theme.json"
freeze_frames="$freeze_world/frames"
mkdir -p -- "$freeze_frames"
if [[ -e $freeze_theme ]]; then cp -- "$freeze_theme" "$freeze_world/theme-found.json"; fi
freeze_theme_found="$(ipc smoke themeName)"
freeze_plugin="$home/.config/vgshell/plugins/acme.freeze"
mkdir -p -- "$freeze_plugin"
cp -R -- "$repo/scripts/smoke/fixtures/plugins/acme.freeze/." "$freeze_plugin/"

freeze_first="$(first_name)"
freeze_first_w="$(first_width)"
freeze_turned=VGS-TURNED
freeze_rule="hl.monitor({ output = \"$freeze_turned\", mode = \"1920x1080@60\", position = \"${freeze_first_w}x0\", scale = 1, transform = 1 })"
# A nested Wayland output comes up at the sink's 1920x1080 and takes a
# rule only once it exists, and a reload drops a rule eval alone applied
# (sandbox-shots.sh's Displays shot), so the rule also goes in the file
# and each poll applies it again.
freeze_turned_taken() {
  local reply
  reply="$(hypr eval "$freeze_rule")" || { echo eval-failed; return; }
  [[ $reply == ok ]] || { echo eval-refused; return; }
  hypr -j monitors | py_reply 'import json,sys; m=[o for o in json.load(sys.stdin) if o["name"]==sys.argv[1]]; print("%dx%d@%d,%d transform=%d" % (m[0]["width"], m[0]["height"], m[0]["x"], m[0]["y"], m[0]["transform"]) if m else "absent")' "$freeze_turned"
}
hypr_lua_save screen-freeze
printf '%s\n' "$freeze_rule" >>"$home/.config/hypr/hyprland.lua"
expect "the nested compositor adds the turned output" ok hypr output create wayland "$freeze_turned"
expect_poll "the turned output stands at transform 1 right of the first" "1920x1080@$freeze_first_w,0 transform=1" freeze_turned_taken
freeze_outputs=("$freeze_first" "$freeze_turned")
freeze_names="$(printf '%s\n' "${freeze_outputs[@]}" | sort | py_reply 'import json,sys; print(json.dumps(sys.stdin.read().split()))')"

# Each output's logical rectangle, [x, y, w, h], sorted: the turned output's
# sides swap.
freeze_rects() { hypr -j monitors | py_reply 'import json,sys
rows = []
for m in json.load(sys.stdin):
    w, h = round(m["width"] / m["scale"]), round(m["height"] / m["scale"])
    if m["transform"] % 2: w, h = h, w
    rows.append([m["x"], m["y"], w, h])
print(json.dumps(sorted(rows)))'; }
freeze_on_overlay() { hypr -j layers | py_reply 'import json,sys; print(sum(1 for m in json.load(sys.stdin).values() for l in m["levels"].get("3", []) if l["namespace"]=="vgs:freeze" and l["pid"]!=-1))'; }
freeze_lent() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["freeze"], sort_keys=True))'; }
freeze_answers() { ipc smoke readInstance service acme.freeze answers | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)))'; }
# The still: the core owns $XDG_RUNTIME_DIR/vgshell/freeze and makes one
# directory a hold in it (ScreenFreeze.qml).
freeze_root="$rt_dir/vgshell/freeze"
freeze_stills() { ipc smoke readInstance service acme.freeze stills; }
freeze_still_count() { freeze_stills | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
freeze_still_dir() { freeze_stills | py_reply 'import json,os,sys; s=json.load(sys.stdin)[-1]; print(os.path.dirname(s["screens"][0]["frames"][0]["bands"][0]["path"]) if isinstance(s, dict) else "answer=" + s)'; }
freeze_dir_state() { if [[ -e $1 ]]; then echo present; else echo gone; fi; }
freeze_still_lent() { python3 - "$(ipc shell lent)" "$(freeze_still_dir)" <<'PY'
import json, sys
still = json.loads(sys.argv[1])["freeze"]["still"]
print("absent" if still is None else "%s cursor=%s newest=%s" % (still["state"], still["cursor"], still["dir"] == sys.argv[2]))
PY
}
# freeze_still_files: `ok` when the newest still answer holds, for every
# output Hyprland lists, a frame at its own scale of its device size, upright,
# cut into PPM bands of at most 2 MP whose headers match the answer, in one
# directory of the runtime root that only the shell's user can open; else
# the first fault.
freeze_still_files() { python3 - "$(freeze_stills)" "$(hypr -j monitors)" "$freeze_root" <<'PY'
import json, os, re, stat, sys
stills, monitors, root = json.loads(sys.argv[1]), json.loads(sys.argv[2]), sys.argv[3]
answer = stills[-1]
if not isinstance(answer, dict):
    sys.exit(print("answer=" + answer))
screens = {s["name"]: s for s in answer["screens"]}
paths = [b["path"] for s in answer["screens"] for f in s["frames"] for b in f["bands"]]
folders = {os.path.dirname(p) for p in paths}
if len(folders) != 1 or os.path.dirname(next(iter(folders))) != root:
    sys.exit(print("folders=" + json.dumps(sorted(folders))))
for folder in (root, next(iter(folders))):
    info = os.stat(folder)
    if stat.S_IMODE(info.st_mode) != 0o700 or info.st_uid != os.getuid():
        sys.exit(print("mode=%o uid=%d path=%s" % (stat.S_IMODE(info.st_mode), info.st_uid, folder)))
for m in monitors:
    w, h = (m["height"], m["width"]) if m["transform"] % 2 else (m["width"], m["height"])
    ratio = round(w / round(w / m["scale"]) * 120)
    frame = next((f for f in screens.get(m["name"], {"frames": []})["frames"] if f["ratio"] == ratio), None)
    if frame is None or (frame["width"], frame["height"]) != (w, h):
        sys.exit(print("frame=%s want=%dx%d" % (m["name"], w, h)))
    rows = 0
    for band in frame["bands"]:
        data = open(band["path"], "rb").read()
        head = re.match(rb"P6\s(\d+)\s(\d+)\s255\s", data)
        if head is None or (int(head.group(1)), int(head.group(2))) != (w, band["rows"]) or len(data) != head.end() + w * band["rows"] * 3 or w * band["rows"] > 2000000:
            sys.exit(print("band=" + band["path"]))
        rows += band["rows"]
    if rows != h:
        sys.exit(print("rows=%s %d/%d" % (m["name"], rows, h)))
print("ok")
PY
}
# freeze_grab NAME: every output as NAME-<output>.png.
freeze_grab() {
  local output
  for output in "${freeze_outputs[@]}"; do
    shot_grab "$freeze_socket" "$rt_dir" "$output" "$freeze_frames/$1-$output.png" || { fail "screen-freeze: grim could not read $output for $1"; return 1; }
  done
}
# freeze_match ONE TWO OUTPUT: True when OUTPUT's two images have one size
# and at most 1% of their pixels differ by more than 32 in a channel. The
# mark turned with its frame changes about a sixth of the turned output;
# the bar's clock, which shows seconds, changes a few hundred pixels.
freeze_match() { python3 - "$freeze_frames/$1-$3.png" "$freeze_frames/$2-$3.png" <<'PY'
import sys
from PIL import Image, ImageChops
one, two = (Image.open(p).convert("RGB") for p in sys.argv[1:])
if one.size != two.size:
    print("size=%dx%d/%dx%d" % (*one.size, *two.size))
    sys.exit()
mask = ImageChops.difference(one, two).convert("L").point(lambda v: 255 if v > 32 else 0)
changed = mask.histogram()[255]
print(changed <= one.size[0] * one.size[1] // 100)
PY
}
freeze_theme_to() { # vgs|flexoki-light
  if [[ $1 == vgs ]]; then printf '{"schemaVersion":1,"name":"vgs","tokens":{}}\n' >"$freeze_theme.next"
  else cp -- "$repo/themes/catalog/$1/theme.json" "$freeze_theme.next"; fi
  mv -T -- "$freeze_theme.next" "$freeze_theme"
  expect_poll "the $1 theme publishes" "$1" ipc smoke themeName
}

# The fresh windows: the toplevel helper, which fills its window with
# #336699, tiled once on each output. freeze_window_share NAME OUTPUT reads
# how much of OUTPUT's NAME frame is that colour: `most` over half, `none`
# at most 0.1%, else `some=<share>`. A tiled window covers about 90% of
# either output and the shell draws no #336699.
freeze_centre() { hypr -j monitors | py_reply 'import json,sys
m = next(m for m in json.load(sys.stdin) if m["name"] == sys.argv[1])
w, h = (m["height"], m["width"]) if m["transform"] % 2 else (m["width"], m["height"])
print(round(m["x"] + w / m["scale"] / 2), round(m["y"] + h / m["scale"] / 2))' "$1"; }
freeze_fresh_on() { python3 - "$(hypr -j clients)" "$(hypr -j monitors)" <<'PY'
import json, sys
clients, monitors = json.loads(sys.argv[1]), json.loads(sys.argv[2])
names = {m["id"]: m["name"] for m in monitors}
print(json.dumps(sorted(names[c["monitor"]] for c in clients if c["class"] == "smoke.freeze-fresh")))
PY
}
freeze_fresh_pids=()
freeze_fresh_open() {
  local output x y
  freeze_fresh_pids=()
  for output in "${freeze_outputs[@]}"; do
    read -r x y <<<"$(freeze_centre "$output")"
    expect "the cursor moves onto $output" ok hypr eval "hl.dispatch(hl.dsp.cursor.move({ x = $x, y = $y }))"
    open_toplevel "$freeze_world/fresh-$output.log" smoke.freeze-fresh "Freeze fresh" || fail "screen-freeze: the fresh window on $output did not map"
    freeze_fresh_pids+=("$toplevel_pid")
  done
  expect_poll "a fresh window tiles on each output" "$freeze_names" freeze_fresh_on
  rest_pointer || fail "screen-freeze: parking the pointer failed"
}
freeze_fresh_close() {
  local pid
  for pid in "${freeze_fresh_pids[@]}"; do close_toplevel "$pid" "a fresh window closes"; done
  expect_poll "no fresh window is left" '[]' freeze_fresh_on
}
freeze_window_share() { python3 - "$freeze_frames/$1-$2.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
n = sum(1 for r, g, b in im.get_flattened_data() if abs(r - 0x33) <= 8 and abs(g - 0x66) <= 8 and abs(b - 0x99) <= 8)
share = n / (im.size[0] * im.size[1])
print("most" if share > 0.5 else "none" if share <= 0.001 else "some=%.4f" % share)
PY
}
# freeze_fresh_holds PREFIX FIRST SECOND: a hold over the fresh windows,
# a thaw, the windows closed, a second hold; FIRST and SECOND are the
# fixture's answers once each hold shows. Leaves PREFIX-first-<output>.png
# and PREFIX-second-<output>.png and the second hold held.
freeze_fresh_holds() {
  local output
  freeze_fresh_open
  expect "$1: the fixture holds the freeze over the fresh windows" ok ipc acme.freeze invoke freeze ''
  expect_poll "$1: the first hold shows" "$2" freeze_answers
  freeze_grab "$1-first"
  for output in "${freeze_outputs[@]}"; do
    expect "$1: $output's first frame shows its fresh window" most freeze_window_share "$1-first" "$output"
  done
  expect "$1: the fixture thaws" ok ipc acme.freeze invoke thaw ''
  freeze_fresh_close
  expect "$1: the fixture holds the freeze again" ok ipc acme.freeze invoke freeze ''
  expect_poll "$1: the second hold shows" "$3" freeze_answers
  freeze_grab "$1-second"
}

rescan "the freeze fixture enters the registry"
expect "the freeze fixture enables" ok ipc shell setPluginEnabled acme.freeze true
expect_poll "the freeze fixture's service is built" True record_exists acme.freeze
freeze_theme_to vgs
expect "no freeze surface exists before a hold" 0 layer_count vgs:freeze
expect "the lending record lists no freeze" '{"holder": null, "screens": [], "shown": false, "still": null}' freeze_lent
freeze_fresh_holds fresh '["ok"]' '["ok", "ok"]'
for output in "${freeze_outputs[@]}"; do
  expect "$output's second frame holds none of the first" none freeze_window_share fresh-second "$output"
done
expect "the fixture thaws the second fresh hold" ok ipc acme.freeze invoke thaw ''
expect_poll "the thaw unmaps every freeze surface" 0 layer_count vgs:freeze

# The turned output's mark: a floating window in its top-left quarter, so
# a frame turned on that output moves a large block of colour. The rule
# floats only this class; the window opens on the output under the cursor.
freeze_mark_rule='hl.window_rule({ name = "vgs-freeze-mark", match = { class = "^smoke\\.freeze-mark$" }, float = true, size = { 360, 480 }, move = { 40, 80 } })'
expect "the mark window's rule applies" ok hypr eval "$freeze_mark_rule"
expect "the cursor moves onto the turned output" ok hypr eval "hl.dispatch(hl.dsp.cursor.move({ x = $((freeze_first_w + 540)), y = 960 }))"
open_toplevel "$freeze_world/mark.log" smoke.freeze-mark "Freeze mark" || fail "screen-freeze: the mark window did not map"
freeze_mark_pid="$toplevel_pid"
# Whether the mark lies inside the turned output's top-left quarter.
freeze_mark_placed() { python3 - "$(hypr -j clients)" "$(hypr -j monitors)" "$freeze_turned" <<'PY2'
import json, sys
clients, monitors, name = json.loads(sys.argv[1]), json.loads(sys.argv[2]), sys.argv[3]
m = next(m for m in monitors if m["name"] == name)
w, h = (m["height"], m["width"]) if m["transform"] % 2 else (m["width"], m["height"])
c = [c for c in clients if c["class"] == "smoke.freeze-mark"]
print(len(c) == 1 and c[0]["monitor"] == m["id"] and m["x"] <= c[0]["at"][0] and c[0]["at"][0] + c[0]["size"][0] <= m["x"] + w / 2
      and m["y"] <= c[0]["at"][1] and c[0]["at"][1] + c[0]["size"][1] <= m["y"] + h / 2)
PY2
}
expect_poll "the mark window floats in the turned output's top-left quarter" True freeze_mark_placed
rest_pointer || fail "screen-freeze: parking the pointer failed"
freeze_grab dark-live
expect "the fixture holds the freeze" ok ipc acme.freeze invoke freeze ''
expect_poll "the hold's done hears ok once every output shows its frame" '["ok", "ok", "ok"]' freeze_answers
expect "one freeze surface covers each whole output" "$(freeze_rects)" layers_of vgs:freeze
expect "every freeze surface is on the overlay layer" 2 freeze_on_overlay
expect "the lending record lists the hold, shown on both outputs" "{\"holder\": \"acme.freeze\", \"screens\": $freeze_names, \"shown\": true, \"still\": null}" freeze_lent
freeze_grab dark-frozen
for output in "${freeze_outputs[@]}"; do
  expect "$output's frozen frame matches its live frame, upright and unstretched" True freeze_match dark-live dark-frozen "$output"
done
freeze_theme_to flexoki-light
freeze_grab dark-frozen-under-light
for output in "${freeze_outputs[@]}"; do
  expect "$output stays frozen while the theme changes under it" True freeze_match dark-frozen dark-frozen-under-light "$output"
done
expect "a second hold is refused" 'refused: freeze=busy holder=acme.freeze' ipc acme.freeze invoke freeze ''
expect "the fixture thaws" ok ipc acme.freeze invoke thaw ''
expect_poll "the thaw unmaps every freeze surface" 0 layer_count vgs:freeze
expect "the lending record lists no freeze after the thaw" '{"holder": null, "screens": [], "shown": false, "still": null}' freeze_lent
expect "a thaw with no hold is refused" 'refused: freeze=unheld' ipc acme.freeze invoke thaw ''
for freeze_form in "options:options not-an-object" "still:still not-a-function" "cursor:cursor not-a-boolean" "lone-cursor:cursor without-still"; do
  expect "malformed options of form ${freeze_form%%:*} are refused" "refused: freeze=${freeze_form#*:}" ipc acme.freeze invoke refuse "${freeze_form%%:*}"
done
expect "a refused hold maps no freeze surface" 0 layer_count vgs:freeze
# The written frames: the still answers with every output's frame at its
# own scale, in band files under the hold's own directory.
expect "the fixture holds the freeze with the still" ok ipc acme.freeze invoke freeze-still ''
expect_poll "the still's hold shows" '["ok", "ok", "ok", "ok"]' freeze_answers
expect_poll "the still answers once" 1 freeze_still_count
freeze_still_first="$(freeze_still_dir)"
expect "the frames are each output's device size in bands of at most 2 MP, in a 0700 directory of the runtime root" ok freeze_still_files
expect "the fixture thaws the still's hold" ok ipc acme.freeze invoke thaw ''
expect_poll "the thaw removes the hold's frame directory" gone freeze_dir_state "$freeze_still_first"
# A thaw at the hold's done comes before any frame is written; the next
# hold's answer, which comes only after its own frames are written, shows
# that the first hold's still was never called.
expect "the fixture holds the freeze and thaws at its done" ok ipc acme.freeze invoke freeze-early ''
expect_poll "the early hold's done hears ok" '["ok", "ok", "ok", "ok", "ok"]' freeze_answers
expect_poll "the early thaw unmaps every freeze surface" 0 layer_count vgs:freeze
freeze_grab light-live
for output in "${freeze_outputs[@]}"; do
  expect "$output shows the theme change once thawed" False freeze_match dark-live light-live "$output"
done
# The light hold asks for the pointer in its written frames, and its
# freeze shows the same frame as one without.
expect "the fixture holds the freeze in the light theme with the cursor" ok ipc acme.freeze invoke freeze-cursor ''
expect_poll "the light hold's done hears ok" '["ok", "ok", "ok", "ok", "ok", "ok"]' freeze_answers
freeze_grab light-frozen
for output in "${freeze_outputs[@]}"; do
  expect "$output's light frozen frame matches its live frame" True freeze_match light-live light-frozen "$output"
done
expect_poll "the lending record names the cursor hold's written still, the newest answer" "written cursor=True newest=True" freeze_still_lent
expect "the cursor hold's still answers, the early hold's never" 2 freeze_still_count
expect "the cursor hold's frames stand in their own directory" ok freeze_still_files
freeze_still_last="$(freeze_still_dir)"
expect "the freeze fixture disables" ok ipc shell setPluginEnabled acme.freeze false
expect_poll "the disable unmaps every freeze surface" 0 layer_count vgs:freeze
expect "the lending record lists no freeze after the disable" '{"holder": null, "screens": [], "shown": false, "still": null}' freeze_lent
expect_poll "the disable removes the hold's frame directory" gone freeze_dir_state "$freeze_still_last"

# The control: the turned output's frame turned a second time. The same
# match fails on that output and holds on the other. The same tree's end()
# skips the frame directory's removal: removals and makes run in order, so
# once a second hold's still is answered the first hold's directory reads
# present.
copy_tree screen-freeze-control
edit_tree screen-freeze-control shell/Hosts/FreezeHost.qml \
  $'                anchors.fill: parent\n                captureSource: surface.modelData' \
  $'                readonly property bool turned: surface.modelData.name === "'"$freeze_turned"$'"\n                anchors.centerIn: parent\n                width: turned ? parent.height : parent.width\n                height: turned ? parent.width : parent.height\n                rotation: turned ? 90 : 0\n                captureSource: surface.modelData'
edit_tree screen-freeze-control shell/Core/ScreenFreeze.qml \
  '        if (entry.dir !== "") queue({ kind: "remove", entry: entry });' \
  ''
stop_shell || :
start_shell "$sandbox/tree-screen-freeze-control" "$freeze_world/control-shell.log"
expect "the freeze fixture enables in the control tree" ok ipc shell setPluginEnabled acme.freeze true
expect_poll "the control tree's freeze fixture is built" True record_exists acme.freeze
rest_pointer || fail "screen-freeze: parking the pointer failed"
freeze_grab control-live
expect "the control tree's fixture holds the freeze with the still" ok ipc acme.freeze invoke freeze-still ''
expect_poll "the control tree's hold shows" '["ok"]' freeze_answers
freeze_grab control-frozen
expect "control: a frame turned twice fails the turned output's match" False freeze_match control-live control-frozen "$freeze_turned"
expect "control: the unturned output still matches" True freeze_match control-live control-frozen "$freeze_first"
expect_poll "the control tree's still answers" 1 freeze_still_count
freeze_still_kept="$(freeze_still_dir)"
expect "the control tree's fixture thaws" ok ipc acme.freeze invoke thaw ''
expect "the control tree's fixture holds the freeze with the still again" ok ipc acme.freeze invoke freeze-still ''
expect_poll "the control tree's second still answers" 2 freeze_still_count
expect "control: an end() that skips the removal leaves the first hold's frame directory" present freeze_dir_state "$freeze_still_kept"
expect "the control tree's fixture disables" ok ipc shell setPluginEnabled acme.freeze false
rm -rf -- "${freeze_root:?}"
stop_shell || :
close_toplevel "$freeze_mark_pid" "the mark window closes"

# The freshness control: surfaces built at the first hold and kept after
# the thaw, so the second hold shows the first hold's frame. The fresh
# check fails on both outputs.
copy_tree screen-freeze-stale
edit_tree screen-freeze-stale shell/Hosts/FreezeHost.qml \
  'const next = ScreenFreeze.holding ? Quickshell.screens.slice() : [];' \
  'const next = ScreenFreeze.serial > 0 ? Quickshell.screens.slice() : [];'
edit_tree screen-freeze-stale shell/Hosts/FreezeHost.qml \
  '            host.framed = false;' \
  '            host.framed = ScreenFreeze.holding && host.allFramed;'
start_shell "$sandbox/tree-screen-freeze-stale" "$freeze_world/stale-shell.log"
expect "the freeze fixture enables in the stale tree" ok ipc shell setPluginEnabled acme.freeze true
expect_poll "the stale tree's freeze fixture is built" True record_exists acme.freeze
freeze_fresh_holds stale '["ok"]' '["ok", "ok"]'
for output in "${freeze_outputs[@]}"; do
  expect "control: a kept surface's second frame shows the first on $output" most freeze_window_share stale-second "$output"
done
expect "the stale tree's fixture disables" ok ipc shell setPluginEnabled acme.freeze false
stop_shell || :

# A screen that leaves while the still's bands are written. A disposable
# tree whose bands hold 20000 device pixels makes the turned output's
# frame about 107 bands, one per frame, so the removal lands while a band
# grab of the leaving output's surface is pending. The chain ends with
# `failed: still=screen-gone`, the leaving output's surface goes, and the
# shell lives on. Once the shell lists the first output alone, it has run
# the screen change: Quickshell updates `screens` and emits its change in
# the one call (quickshell 2b4501a src/core/qmlglobal.cpp updateScreens),
# so a tree that removes both screen-gone answers reads the still
# unanswered there and fails.
freeze_shell_screens() { ipc smoke perScreenLayers | py_reply 'import json,sys; print(json.dumps(sorted({r["screen"] for r in json.load(sys.stdin)})))'; }
# freeze_leave_chain: `on-turned` while the still is written and its last
# written band is the turned output's, else the state.
freeze_leave_chain() { ipc shell lent | py_reply 'import json,sys
s = json.load(sys.stdin)["freeze"]["still"]
print("none" if s is None else "on-turned" if s["state"] == "writing" and s["bands"] and s["bands"][-1]["screen"] == sys.argv[1] else s["state"])' "$freeze_turned"; }
freeze_lent_dir() { ipc shell lent | py_reply 'import json,sys; print(json.load(sys.stdin)["freeze"]["still"]["dir"])'; }
freeze_lent_still_state() { ipc shell lent | py_reply 'import json,sys; s=json.load(sys.stdin)["freeze"]["still"]; print(json.dumps(None if s is None else s["state"]))'; }
freeze_stills_json() { freeze_stills | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)))'; }
# freeze_leave TREE: a still hold in TREE, the turned output removed while
# its bands are written; the shell then lists the first output alone.
freeze_leave() {
  start_shell "$sandbox/tree-screen-freeze-$1" "$freeze_world/$1-shell.log"
  expect "the freeze fixture enables in the $1 tree" ok ipc shell setPluginEnabled acme.freeze true
  expect_poll "the $1 tree's freeze fixture is built" True record_exists acme.freeze
  expect "the $1 tree's fixture holds the freeze with the still" ok ipc acme.freeze invoke freeze-still ''
  expect_poll "the $1 tree's hold shows" '["ok"]' freeze_answers
  expect_poll "the $1 tree's chain writes the turned output's bands" on-turned freeze_leave_chain
  freeze_leave_dir="$(freeze_lent_dir)"
  expect "the nested compositor removes the turned output while its bands are written" ok hypr output remove "$freeze_turned"
  expect_poll "the $1 tree's shell lists the first output alone" "[\"$freeze_first\"]" freeze_shell_screens
}
copy_tree screen-freeze-leave
edit_tree screen-freeze-leave shell/Core/FreezeBands.js 'var BAND_PIXELS = 2000000;' 'var BAND_PIXELS = 20000;'
freeze_leave leave
expect "the still answers that a screen left" '["failed: still=screen-gone"]' freeze_stills_json
expect "the lending record names the failed still" '"failed: still=screen-gone"' freeze_lent_still_state
expect_poll "one freeze surface stands, on the output that stayed" 1 layer_count vgs:freeze
expect "the leave tree's fixture thaws" ok ipc acme.freeze invoke thaw ''
expect_poll "the thaw unmaps the freeze surface" 0 layer_count vgs:freeze
expect_poll "the thaw removes the hold's frame directory" gone freeze_dir_state "$freeze_leave_dir"
expect "the leave tree's fixture disables" ok ipc shell setPluginEnabled acme.freeze false
stop_shell || :
expect "the nested compositor adds the turned output again" ok hypr output create wayland "$freeze_turned"
expect_poll "the turned output stands at transform 1 right of the first again" "1920x1080@$freeze_first_w,0 transform=1" freeze_turned_taken
# The control removes both screen-gone producers: screen-list cancellation
# and a surviving callback's next grab finding no surface. Either callback
# lifetime then leaves the chain unanswered.
copy_tree screen-freeze-uncancelled
edit_tree screen-freeze-uncancelled shell/Core/FreezeBands.js 'var BAND_PIXELS = 2000000;' 'var BAND_PIXELS = 20000;'
edit_tree screen-freeze-uncancelled shell/Hosts/FreezeHost.qml \
  '                if (run.screens.some(screen => names.indexOf(screen.name) < 0)) host.stillFailed(run, "screen-gone");' \
  ''
edit_tree screen-freeze-uncancelled shell/Hosts/FreezeHost.qml \
  '            stillFailed(run, "screen-gone");' \
  ''
freeze_leave uncancelled
expect "control: a chain not cancelled on a screen change leaves the still unanswered" '[]' freeze_stills_json
expect "the uncancelled tree's fixture disables" ok ipc shell setPluginEnabled acme.freeze false
stop_shell || :
start_shell "$repo" "$freeze_world/restored-shell.log"

if [[ -e $freeze_world/theme-found.json ]]; then cp -- "$freeze_world/theme-found.json" "$freeze_theme"; else rm -f -- "${freeze_theme:?}"; fi
expect_poll "the theme goes back as the row found it" "$freeze_theme_found" ipc smoke themeName
rm -rf -- "${freeze_plugin:?}"
rescan "the freeze fixture leaves the registry"
hypr_lua_restore screen-freeze
