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
# second time, as hyprpicker 0.4.7 does on Hyprland 0.57.0, fails the
# frame match on that output alone.
# inputs: scripts/smoke/fixtures/plugins/acme.freeze/* shell/Core/ScreenFreeze.qml shell/Hosts/FreezeHost.qml shell/Core/Capabilities.qml shell/Core/HyprlandLayer.js shell/Core/HyprlandLayer.qml shell/shell.qml
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

rescan "the freeze fixture enters the registry"
expect "the freeze fixture enables" ok ipc shell setPluginEnabled acme.freeze true
expect_poll "the freeze fixture's service is built" True record_exists acme.freeze
freeze_theme_to vgs
expect "no freeze surface exists before a hold" 0 layer_count vgs:freeze
expect "the lending record lists no freeze" '{"holder": null, "screens": [], "shown": false}' freeze_lent
rest_pointer || fail "screen-freeze: parking the pointer failed"
freeze_grab dark-live
expect "the fixture holds the freeze" ok ipc acme.freeze invoke freeze ''
expect_poll "the hold's done hears ok once every output shows its frame" '["ok"]' freeze_answers
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
expect_poll "the light hold's done hears ok" '["ok", "ok"]' freeze_answers
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
start_shell "$repo" "$freeze_world/restored-shell.log"

if [[ -e $freeze_world/theme-found.json ]]; then cp -- "$freeze_world/theme-found.json" "$freeze_theme"; else rm -f -- "${freeze_theme:?}"; fi
expect_poll "the theme goes back as the row found it" "$freeze_theme_found" ipc smoke themeName
rm -rf -- "${freeze_plugin:?}"
rescan "the freeze fixture leaves the registry"
close_toplevel "$freeze_mark_pid" "the mark window closes"
expect "the nested compositor removes the turned output" ok hypr output remove "$freeze_turned"
hypr_lua_restore screen-freeze
