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
# inputs: scripts/smoke/fixtures/plugins/acme.freeze/* shell/Core/ScreenFreeze.qml shell/Hosts/FreezeHost.qml shell/Core/Capabilities.qml shell/Core/HyprlandLayer.js shell/Core/HyprlandLayer.qml shell/shell.qml themes/catalog/flexoki-light/theme.json
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
expect "the lending record lists no freeze" '{"holder": null, "screens": [], "shown": false}' freeze_lent
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
expect "the lending record lists the hold, shown on both outputs" "{\"holder\": \"acme.freeze\", \"screens\": $freeze_names, \"shown\": true}" freeze_lent
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
expect "the lending record lists no freeze after the thaw" '{"holder": null, "screens": [], "shown": false}' freeze_lent
expect "a thaw with no hold is refused" 'refused: freeze=unheld' ipc acme.freeze invoke thaw ''
freeze_grab light-live
for output in "${freeze_outputs[@]}"; do
  expect "$output shows the theme change once thawed" False freeze_match dark-live light-live "$output"
done
expect "the fixture holds the freeze in the light theme" ok ipc acme.freeze invoke freeze ''
expect_poll "the light hold's done hears ok" '["ok", "ok", "ok", "ok"]' freeze_answers
freeze_grab light-frozen
for output in "${freeze_outputs[@]}"; do
  expect "$output's light frozen frame matches its live frame" True freeze_match light-live light-frozen "$output"
done
expect "the freeze fixture disables" ok ipc shell setPluginEnabled acme.freeze false
expect_poll "the disable unmaps every freeze surface" 0 layer_count vgs:freeze
expect "the lending record lists no freeze after the disable" '{"holder": null, "screens": [], "shown": false}' freeze_lent

# The control: the turned output's frame turned a second time. The same
# match fails on that output and holds on the other.
copy_tree screen-freeze-control
edit_tree screen-freeze-control shell/Hosts/FreezeHost.qml \
  $'                anchors.fill: parent\n                captureSource: surface.modelData' \
  $'                readonly property bool turned: surface.modelData.name === "'"$freeze_turned"$'"\n                anchors.centerIn: parent\n                width: turned ? parent.height : parent.width\n                height: turned ? parent.width : parent.height\n                rotation: turned ? 90 : 0\n                captureSource: surface.modelData'
stop_shell || :
start_shell "$sandbox/tree-screen-freeze-control" "$freeze_world/control-shell.log"
expect "the freeze fixture enables in the control tree" ok ipc shell setPluginEnabled acme.freeze true
expect_poll "the control tree's freeze fixture is built" True record_exists acme.freeze
rest_pointer || fail "screen-freeze: parking the pointer failed"
freeze_grab control-live
expect "the control tree's fixture holds the freeze" ok ipc acme.freeze invoke freeze ''
expect_poll "the control tree's hold shows" '["ok"]' freeze_answers
freeze_grab control-frozen
expect "control: a frame turned twice fails the turned output's match" False freeze_match control-live control-frozen "$freeze_turned"
expect "control: the unturned output still matches" True freeze_match control-live control-frozen "$freeze_first"
expect "the control tree's fixture disables" ok ipc shell setPluginEnabled acme.freeze false
stop_shell || :
close_toplevel "$freeze_mark_pid" "the mark window closes"

# The freshness control: surfaces built at the first hold and kept after
# the thaw, so the second hold shows the first hold's frame. The fresh
# check fails on both outputs.
copy_tree screen-freeze-stale
edit_tree screen-freeze-stale shell/Hosts/FreezeHost.qml \
  'model: ScreenFreeze.holding ? Quickshell.screens : []' \
  'model: ScreenFreeze.serial > 0 ? Quickshell.screens : []'
edit_tree screen-freeze-stale shell/Hosts/FreezeHost.qml \
  'function onHoldingChanged() { host.framed = false; }' \
  'function onHoldingChanged() { host.framed = ScreenFreeze.holding && host.allFramed; }'
start_shell "$sandbox/tree-screen-freeze-stale" "$freeze_world/stale-shell.log"
expect "the freeze fixture enables in the stale tree" ok ipc shell setPluginEnabled acme.freeze true
expect_poll "the stale tree's freeze fixture is built" True record_exists acme.freeze
freeze_fresh_holds stale '["ok"]' '["ok", "ok"]'
for output in "${freeze_outputs[@]}"; do
  expect "control: a kept surface's second frame shows the first on $output" most freeze_window_share stale-second "$output"
done
expect "the stale tree's fixture disables" ok ipc shell setPluginEnabled acme.freeze false
stop_shell || :
start_shell "$repo" "$freeze_world/restored-shell.log"

if [[ -e $freeze_world/theme-found.json ]]; then cp -- "$freeze_world/theme-found.json" "$freeze_theme"; else rm -f -- "${freeze_theme:?}"; fi
expect_poll "the theme goes back as the row found it" "$freeze_theme_found" ipc smoke themeName
rm -rf -- "${freeze_plugin:?}"
rescan "the freeze fixture leaves the registry"
expect "the nested compositor removes the turned output" ok hypr output remove "$freeze_turned"
hypr_lua_restore screen-freeze
