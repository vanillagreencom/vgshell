# Passive layers, drawn by the fixture service through its `layers`
# capability and read back from the compositor's layer list, the core's
# lending record, the fixture and the probe. One surface per screen, on the
# overlay layer, clear of reserved space, taking no keyboard focus; pointer
# input reaches the content only where it says; a screen added or removed
# gains or loses its surface; the disposer and a disable release every one.
# Content that stops showing while a popup holds the keyboard grab, the
# Gallery's Select list or the bar's calendar, keeps its surface mapped,
# undrawn, until the popup closes, so the popup's keys stay in it.
# inputs: scripts/smoke/fixtures/plugins/acme.layers/* shell/Core/Layers.qml shell/Hosts/OverlaySurface.qml shell/Hosts/LayerHost.qml scripts/smoke/toplevel/* scripts/smoke/rows/capabilities.sh shell/Ui/overlay/OverlayState.qml shell/Ui/overlay/DismissScope.qml shell/Ui/controls/Select.qml shell/plugins/vgs.gallery/* shell/Hosts/AppWindow.qml shell/Hosts/SummonPopup.qml shell/Hosts/SummonHost.qml shell/plugins/vgs.bar/*
set -euo pipefail
layers_dir="$home/.config/vgshell/plugins/acme.layers"
mkdir -p "$layers_dir"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.layers/." "$layers_dir/"
# JSON the shell answers, respaced as python prints it, so a row compares values.
respaced() { "$@" | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)))'; }
built_screens() { respaced read_layers built; }
lent_layers() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["layers"]))'; }
on_overlay() { hypr -j layers | py_reply 'import json,sys; print(sum(1 for m in json.load(sys.stdin).values() for l in m["levels"].get("3", []) if l["namespace"]=="vgs:layer" and l["pid"]!=-1))'; }
screen_names() { hypr -j monitors | py_reply 'import json,sys; print(json.dumps(sorted(m["name"] for m in json.load(sys.stdin))))'; }
monitor_logical_size() { hypr -j monitors | py_reply 'import json,sys; m=json.load(sys.stdin)[0]; print(round(m["width"] / m["scale"]), round(m["height"] / m["scale"]))'; }

rescan "rescan after adding the layers fixture answers ok"
expect_poll "the layers fixture is discovered" True plugin_known acme.layers
expect "enabling the layers fixture is allowed" ok ipc shell setPluginEnabled acme.layers true
expect_poll "the layers fixture's service is built" True record_exists acme.layers
expect "no layer surface exists before a show" 0 layer_count vgs:layer
expect "the lending record lists no layer" '[]' lent_layers

expect "the fixture shows a layer" ok layered draw
expect_poll "the layer host maps one surface per screen" "$monitors" layer_count vgs:layer
expect "every layer surface is on the overlay layer" "$monitors" on_overlay
expect_poll "every copy of the content received its screen" "$(screen_names)" built_screens
screen_json="$(screen_names)"
expect "the lending record lists the layer under its plugin and screens" "[{\"plugin\": \"acme.layers\", \"screens\": $screen_json}]" lent_layers
surfaces_want="$(python3 -c 'import json,sys; print(json.dumps([[n, True, True, True] for n in json.loads(sys.argv[1])]))' "$screen_json")"
expect "every surface takes no keyboard, sits on the overlay layer and clears reserved space" "$surfaces_want" respaced ipc smoke layerSurfaces acme.layers
geometry read_bar_settled "the bar set has settled before the row reads the bar's reserved height"
read -r mon_logical_w mon_logical_h < <(monitor_logical_size) || { fail "the monitor's logical size is readable for the layer geometry"; exit 1; }
geometry expect_poll "the surface covers the logical screen below the bar's reserved space" "[[0, $bar_reserved, $mon_logical_w, $((mon_logical_h - bar_reserved))]]" layers_of vgs:layer

# A passive layer that unmaps while a popup holds the keyboard grab moves
# the keyboard to the popup's parent window (Hyprland 0.56.2
# CLayerSurface::onUnmap; LayerHost). The fixture's own `shown` drops while
# the Gallery's Select list is open, and again while the bar's calendar, a
# summoned popup, is open; the surface must stay mapped, drawing nothing,
# until the popup closes, and the popup's keys must reach it. The first
# grab begins with the layer mapped, the second maps it during the grab.
# A hidden copy reads no pad: the probe's layer lookup skips an item that
# does not draw. With no pads the layer takes no pointer focus, which would
# send Hyprland down its other unmap path. The list opens from the keyboard
# with the pointer resting off the Gallery, as the Sound row's list does:
# with the pointer over the list's parent window, the motion Hyprland
# simulates after the unmap hands the keyboard back to the popup
# (InputManager.cpp mouseMoveUnified, rawSurfaceFocus), and the defect does
# not show. Once a grab ends, Hyprland gives the keyboard to what lies under
# the pointer (follow_mouse 1; SeatManager.cpp setGrab), so the pointer goes
# back over the Gallery before the key that must reach it.
gallery_select() { ipc smoke readMatchingDescendant window vgs.gallery Select model 'Default,Ocean,Forest' "$1"; }
layer_presented() { ipc smoke layerWindows acme.layers | py_reply 'import json,sys; print(json.dumps(sorted({r["presented"] for r in json.load(sys.stdin)})))'; }
layer_pad() { local box; box="$(ipc smoke layerItemGeometry acme.layers QQuickRectangle width 80)" || return 1; [[ $box == \[* ]] && echo drawn || echo "$box"; }
gallery_off_pointer() { windows_of "VGS Components" | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin)[0]; px,py=map(int, sys.argv[1].split()); print(not (x<=px<x+w and y<=py<y+h))' "$pointer_at"; }
calendar_title() { ipc smoke readMatchingDescendant panel vgs.bar Label objectName calendarTitle text; }
calendar_open() { local title; title="$(calendar_title)" || return 1; [[ $title == \"* ]] && echo open || echo "$title"; }
calendar_moved() { local title; title="$(calendar_title)" || return 1; [[ $title != "$calendar_month" && $title != absent ]] && echo moved || echo "still $title"; }
clock_point() { ipc smoke descendantGeometry "$(bar_key)" vgs.bar/center-clock | py_reply 'import json,sys; x,y,w,h=next(r["box"] for r in json.load(sys.stdin) if r["type"] == "BarItem"); print(int(x + w / 2), int(y + h / 2))'; }
gallery_focused="[\"$shell_class\", \"VGS Components\"]"
expect "the content removes its input items for the grab rows" ok layered pads 0
expect_poll "the shown layer draws its pads" drawn layer_pad
expect "the gallery summons for the grab rows" ok ipc shell summon window vgs.gallery '{}'
expect_poll "the gallery maps one window" 1 window_count "VGS Components"
expect_poll "the gallery has the keyboard" "$gallery_focused" active_window
ipc smoke revealText window vgs.gallery Select Default >/dev/null || fail "revealing the Gallery's Select failed"
if read -r select_x select_y < <(at_centre "window:VGS Components" "$(ipc smoke shownWindowGeometry window vgs.gallery Select Default)"); then
  hover "$select_x" "$select_y" || fail "hovering the Gallery's Select failed"
  click "$select_x" "$select_y" || fail "clicking the Gallery's Select failed"
else
  fail "the Gallery's Select has no box"
fi
expect_poll "the click opens the Select's list" true gallery_select listOpen
type_keys -k Escape || fail "Escape in the clicked list failed"
expect_poll "Escape closes the clicked list" false gallery_select listOpen
rest_pointer || fail "moving the pointer off the Gallery failed"
expect "the resting pointer is off the Gallery window" True gallery_off_pointer
expect_poll "the Gallery keeps the keyboard with the pointer off it" "$gallery_focused" active_window
type_keys -k space || fail "Space on the Gallery's Select failed"
expect_poll "Space opens the Select's list" true gallery_select listOpen
expect "the content stops showing while the list grabs" ok layered shown 0
expect_poll "the hidden content draws no pad" absent layer_pad
expect "the hidden content reads unpresented" '[false]' layer_presented
expect "the hidden layer stays mapped while the list holds the grab" "$monitors" layer_count vgs:layer
type_keys -k Down || fail "Down in the Select's list failed"
type_keys -k Return || fail "Enter in the Select's list failed"
expect_poll "Down and Enter in the list choose the next entry" '"Ocean"' gallery_select currentText
expect_poll "Enter closes the list" false gallery_select listOpen
expect_poll "the held layer unmaps once the list closes" 0 layer_count vgs:layer
hover "$select_x" "$select_y" || fail "moving the pointer back over the Gallery failed"
expect_poll "the Gallery has the keyboard after the list closed" "$gallery_focused" active_window
rest_pointer || fail "moving the pointer off the Gallery again failed"
type_keys -k space || fail "Space on the Gallery's Select after Enter failed"
expect_poll "the key after the list closed reaches the Select and opens its list" true gallery_select listOpen
expect "the content shows during the second grab" ok layered shown 1
expect_poll "the layer maps during the grab" "$monitors" layer_count vgs:layer
expect_poll "the layer shown during the grab draws its pads" drawn layer_pad
expect "the content stops showing during the second grab" ok layered shown 0
expect_poll "the content hidden again draws no pad" absent layer_pad
expect "the content hidden again reads unpresented" '[false]' layer_presented
expect "the layer mapped during the grab stays mapped while hidden" "$monitors" layer_count vgs:layer
type_keys -k Escape || fail "Escape in the Select's list failed"
expect_poll "Escape closes the list after the layer's time ended" false gallery_select listOpen
expect_poll "the held layer unmaps once Escape closed the list" 0 layer_count vgs:layer
expect "Escape left the Gallery window open" 1 window_count "VGS Components"
hover "$select_x" "$select_y" || fail "moving the pointer back over the Gallery after Escape failed"
expect_poll "the Gallery has the keyboard back" "$gallery_focused" active_window
type_keys -k space || fail "Space on the Gallery's Select after Escape failed"
expect_poll "the key after Escape reaches the Select" true gallery_select listOpen
type_keys -k Escape || fail "Escape in the reopened list failed"
expect_poll "Escape closes the reopened list" false gallery_select listOpen
expect "hiding the gallery after the grab rows is allowed" ok ipc shell hide window vgs.gallery
expect_poll "the gallery's window is gone" 0 window_count "VGS Components"
expect "the content shows before the calendar's grab" ok layered shown 1
expect_poll "the layer maps before the calendar's grab" "$monitors" layer_count vgs:layer
if read -r clock_x clock_y < <(clock_point); then
  click "$clock_x" "$clock_y" || fail "clicking the bar's clock failed"
else
  fail "the bar's clock has no box"
fi
expect_poll "the clock opens the calendar" open calendar_open
calendar_month="$(calendar_title)"
expect "the content stops showing while the calendar grabs" ok layered shown 0
expect_poll "the content hidden under the calendar draws no pad" absent layer_pad
expect "the hidden layer stays mapped while the calendar holds the grab" "$monitors" layer_count vgs:layer
type_keys -k Right || fail "Right in the calendar failed"
expect_poll "Right reaches the calendar after the layer's time ended" moved calendar_moved
type_keys -k Escape || fail "Escape in the calendar failed"
expect_poll "Escape closes the calendar" absent calendar_title
expect_poll "the held layer unmaps once the calendar closes" 0 layer_count vgs:layer
expect "the content shows again after the grab rows" ok layered shown 1
expect "the content restores both pads after the grab rows" ok layered pads 2
expect_poll "the layer maps again after the grab rows" "$monitors" layer_count vgs:layer

layer_hidden_assertion() {
  (failures=0 behaviour_failures=0
   expect_poll "hidden content maps no passive surface" 0 layer_count vgs:layer >"$sandbox/layer-hidden-assertion.log"
   echo "$failures")
}
expect "the observer retains the host for the ignored-map control" ok ipc smoke layerWindowRemember acme.layers
expect "the content requests no map without destroying its copies" ok layered shown 0
expect "hidden content maps no passive surface" 0 layer_hidden_assertion
expect "hidden copies still belong to the registration" "$(screen_names)" built_screens
expect "control: the host ignores the content's map request" ok ipc smoke layerWindowSet acme.layers visible true
expect_poll "control: the changed host wrongly maps hidden content" "$monitors" layer_count vgs:layer
expect "control: ignoring shown breaks the same map assertion" 1 layer_hidden_assertion
expect "the observer releases its control references" ok ipc smoke layerWindowForget
expect "a redraw restores the host's map binding" ok layered redraw
expect "the restored hidden registration maps no surface" 0 layer_hidden_assertion
expect "the content requests its map again" ok layered shown 1
expect_poll "shown content maps its retained copies" "$monitors" layer_count vgs:layer

# Every reading counts press AND release on both the layer and a real xdg
# client below it. An unchanged layer counter cannot prove pass-through:
# an oversized mask with no handler below the point could swallow input.
# layer_input_begin RECEIVER X Y stores the expected change before clicking;
# layer_input_result is the same assertion for positive rows and controls.
# RECEIVER is left, right, layer (outside either pad under inputAll), client.
layer_input_sample() {
  local events down up
  events="$(read_layers events)" && down="$(other_events '^button 272 pressed$')" && up="$(other_events '^button 272 released$')" || return 1
  python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1]) + [int(sys.argv[2]), int(sys.argv[3])]))' "$events" "$down" "$up"
}
layer_input_begin() {
  input_before="$(layer_input_sample)" || return 1
  input_want="$(python3 -c '
import json,sys
values = json.loads(sys.argv[1])
increments = {"left": [1,1,1,0,0,0], "right": [1,1,0,1,0,0], "layer": [1,1,0,0,0,0], "client": [0,0,0,0,1,1]}
print(json.dumps([v+d for v,d in zip(values, increments[sys.argv[2]])]))' "$input_before" "$1")" || return 1
  hover "$(($2 - 1))" "$3" && click "$2" "$3"
}
layer_input_result() {
  local got
  got="$(layer_input_sample)" || return 1
  [[ $got == "$input_want" ]] && echo ok || echo violation
}

# The acme.layers fixture pads are 80x40 at x=0 and x=160 in Service.qml.
left_x=40 right_x=200 gap_x=120 pad_y=$((bar_reserved + 20))
away_x=$((mon_w / 2)) away_y=$((mon_h / 2))
if ! open_other "$sandbox/toplevel-layers.log"; then fail "the client below the passive layer maps"; exit 1; fi
client_focused='["smoke.other", "Other window"]'
expect_poll "the client below the passive layer has keyboard focus" "$client_focused" active_window
for point in "left $left_x $pad_y" "right $right_x $pad_y" "client $gap_x $pad_y" "client $away_x $away_y"; do
  read -r receiver x y <<<"$point"
  layer_input_begin "$receiver" "$x" "$y" || { fail "the $receiver input check could not click"; exit 1; }
  expect_poll "the $receiver receives press and release at $x,$y, and the other receiver gets neither" ok layer_input_result
done
expect "pressing a passive layer leaves the keyboard on the client" "$client_focused" active_window

client_keys_before="$(other_events '^key [0-9]+ released$')" || fail "the client key count is unreadable"
type_keys z || fail "typing while the passive layer is mapped failed"
expect_poll "a passive layer leaves typed keys on the client" "$((client_keys_before + 1))" other_events '^key [0-9]+ released$'

expect "the content can take input on its whole surface" ok layered full 1
layer_input_begin layer "$gap_x" "$pad_y" || { fail "the full-layer gap click failed"; exit 1; }
expect_poll "inputAll catches press and release in the gap instead of the client" ok layer_input_result
expect "the content returns to its pads" ok layered full 0
expect "the content removes its input items" ok layered pads 0
layer_input_begin client "$left_x" "$pad_y" || { fail "the empty-list click failed"; exit 1; }
expect_poll "an empty input list passes press and release through a former pad" ok layer_input_result
expect "inputAll can override an empty list" ok layered full 1
layer_input_begin layer "$gap_x" "$pad_y" || { fail "the empty full-layer click failed"; exit 1; }
expect_poll "inputAll still catches input with an empty list" ok layer_input_result
expect "the empty surface returns to pass-through" ok layered full 0
expect "the content adds only the left pad" ok layered pads 1
layer_input_begin left "$left_x" "$pad_y" || { fail "the single-pad click failed"; exit 1; }
expect_poll "adding one input item gives its pad input" ok layer_input_result
layer_input_begin client "$right_x" "$pad_y" || { fail "the removed-pad click failed"; exit 1; }
expect_poll "the removed right pad passes press and release to the client" ok layer_input_result
expect "the content restores both pads" ok layered pads 2
layer_input_begin right "$right_x" "$pad_y" || { fail "the restored-pad click failed"; exit 1; }
expect_poll "adding the right item restores input to that pad" ok layer_input_result

# Remove the host's forwarding binding in its sandbox instance. The click
# must reach the client before the normal layer assertion is read as red.
expect "control: the probe removes the host's delivered input items" ok ipc smoke layerInputDrop acme.layers
layer_input_begin left "$left_x" "$pad_y" || { fail "the host forwarding control could not click"; exit 1; }
client_up="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])[5]+1)' "$input_before")"
expect_poll "control: the missing host binding sends the pad click to the client" "$client_up" other_events '^button 272 released$'
expect "control: the missing host binding breaks the shared input assertion" violation layer_input_result
expect "a redraw restores the host's input binding" ok layered redraw
expect_poll "the redrawn layer maps again" "$monitors" layer_count vgs:layer
layer_input_begin left "$left_x" "$pad_y" || { fail "the restored host click failed"; exit 1; }
expect_poll "the restored host binding passes the shared input assertion" ok layer_input_result

# The harness prepares the mask copies before shell startup, so Qt's
# directory cache sees every file. Each mutant removes a mask behavior,
# not the test or its fixture. The real layer is released after the copy
# maps; it cannot catch a click a mutant wrongly lets through.
expect "the original registration is released before mask controls" ok layered undraw
expect_poll "the original layer is gone before mask controls" 0 layer_count vgs:layer
python3 - "$repo/scripts/smoke/toplevel/toplevel.c" "$sandbox/toplevel-silent.c" <<'PY'
from pathlib import Path
import sys
helper, silent = map(Path, sys.argv[1:])
text = helper.read_text()
old = 'printf("button %u %s\\n", button, state == WL_POINTER_BUTTON_STATE_PRESSED ? "pressed" : "released");'
assert text.count(old) == 1, "button observer mutation must match once"
changed = text.replace(old, old.replace('"button ', '"unobserved-button '))
assert changed != text
silent.write_text(changed)
PY
for control in "NoLeft left $left_x client" "NoRight right $right_x client" "NoMask client $gap_x layer"; do
  read -r name wanted x actual <<<"$control"
  expect "control: the fixture registers content for $name" ok layered draw
  expect_poll "control: the original content is built before $name" "$screen_json" built_screens
  expect "control: the probe loads $name with the real layer content" ok ipc smoke layerSurfaceLoad "$name" "$repo/shell/Hosts/OverlaySurface$name.qml" acme.layers
  expect_poll "control: the $name surface maps" 1 layer_count vgs:layer-control
  expect "control: the original layer is released beside $name" ok layered undraw
  expect_poll "control: no original layer can catch input beside $name" 0 layer_count vgs:layer
  layer_input_begin "$wanted" "$x" "$pad_y" || { fail "the $name control could not click"; exit 1; }
  if [[ $actual == client ]]; then
    client_up="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])[5]+1)' "$input_before")"
    expect_poll "control: $name sends the pad's release to the client" "$client_up" other_events '^button 272 released$'
  else
    layer_up="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])[1]+1)' "$input_before")"
    expect_poll "control: $name catches the gap's release on the layer" "$layer_up" read_layers releases
  fi
  expect "control: $name breaks the shared input assertion" violation layer_input_result
  expect "control: the probe drops $name" ok ipc smoke popupDrop "$name"
  expect_poll "control: the $name surface is destroyed" 0 layer_count vgs:layer-control
done
expect "the fixture shows the original layer after mask controls" ok layered draw
expect_poll "the original layer maps after mask controls" "$monitors" layer_count vgs:layer

expect "the fixture moves only the pads' parent" ok layered offset 80
layer_input_begin left "$((left_x + 80))" "$pad_y" || { fail "the moved parent click failed"; exit 1; }
expect_poll "an ancestor move updates the pad's input rectangle" ok layer_input_result
expect "the parent returns before its control" ok layered offset 0
expect "control: the probe loads a mask without ancestor observation" ok ipc smoke layerSurfaceLoad NoAncestors "$repo/shell/Hosts/OverlaySurfaceNoAncestors.qml" acme.layers
expect_poll "control: the ancestor-blind surface maps" 1 layer_count vgs:layer-control
expect "control: release the original before the ancestor move" ok layered undraw
expect_poll "control: no original mask can catch the moved pad" 0 layer_count vgs:layer
expect "control: move only the copied pads' parent" ok layered offset 80
layer_input_begin left "$((left_x + 80))" "$pad_y" || { fail "the ancestor control click failed"; exit 1; }
expect "control: ignoring ancestors breaks the same input reader" violation layer_input_result
expect "control: the probe drops the ancestor-blind surface" ok ipc smoke popupDrop NoAncestors
expect "the pads return to their neutral positions" ok layered offset 0
expect "the fixture restores its ordinary layer" ok layered draw
expect_poll "the restored layer maps after the ancestor control" "$monitors" layer_count vgs:layer

# The receiver is also controlled: a copy that hides button events cannot
# pass the same client assertion. A key round trip proves the client has
# processed input before testing its absent button record.
close_other "the pointer-observing client exits after the mask controls"
cp "$sandbox/toplevel" "$sandbox/toplevel-observing"
build_helper toplevel toplevel "$sandbox/toplevel-silent.c" "$repo/scripts/smoke/toplevel/xdg-shell.xml"
if ! open_other "$sandbox/toplevel-layers-silent.log"; then fail "the silent client maps"; exit 1; fi
expect_poll "the silent client has keyboard focus" "$client_focused" active_window
layer_input_begin client "$gap_x" "$pad_y" || { fail "the silent receiver control could not click"; exit 1; }
type_keys x || { fail "the silent receiver control could not type its marker"; exit 1; }
expect_poll "control: the silent client processes the key after the gap click" 1 other_events '^key [0-9]+ released$'
expect "control: a receiver with no button record breaks the shared input assertion" violation layer_input_result
close_other "the silent receiver exits after its control"
mv "$sandbox/toplevel-observing" "$sandbox/toplevel"

# A screen that comes gains the layer; one that goes takes it along.
layer_output=SMOKE-LAYER
expect "the nested compositor adds a monitor for the layer rows" ok create_output "$layer_output"
expect_poll "the new monitor gets its own layer surface" "$((monitors + 1))" layer_count vgs:layer
expect_poll "the new screen's copy received its screen" "$(screen_names)" built_screens
expect "the nested compositor removes that monitor" ok hypr output remove "$layer_output"
expect_poll "the removed monitor's layer surface is gone" "$monitors" layer_count vgs:layer
expect_poll "the removed screen's copy was destroyed" "$screen_json" built_screens
expect_poll "the lending record forgot the removed screen" "[{\"plugin\": \"acme.layers\", \"screens\": $screen_json}]" lent_layers

# Refusals: something that is no component, and a content with no screen.
expect "showing something that is no component is refused" "refused: layers=not-a-component" layered bad
expected_errors+=('layers: acme\.layers content not built on [^:]+: .*screen')
expect "a content without a screen property is shown" ok layered bare
expect_log "the host logs the content it did not build" 1 'layers: acme\.layers content not built on [^:]+: .*screen'
expect "the refused content maps no surface" "$monitors" layer_count vgs:layer
expect "releasing the refused content is allowed" ok layered unbare

# A registration that ends as another begins, in one call, leaves the new
# one built on every screen and recorded there.
expect "the fixture releases and registers again at once" ok layered redraw
expect_poll "the new registration has one surface per screen" "$monitors" layer_count vgs:layer
expect_poll "every copy of the new registration received its screen" "$screen_json" built_screens
expect_poll "the lending record lists the new registration on every screen" "[{\"plugin\": \"acme.layers\", \"screens\": $screen_json}]" lent_layers

# The disposer and a disable release every surface.
expect "the fixture's disposer hides the layer" ok layered undraw
expect_poll "the disposer destroyed every layer surface" 0 layer_count vgs:layer
expect_poll "every content copy was destroyed" '[]' built_screens
expect "the lending record lists no layer after the disposer" '[]' lent_layers
expect "the fixture shows its layer again" ok layered draw
expect_poll "the layer is back on every screen" "$monitors" layer_count vgs:layer
expect "disabling the layers fixture is allowed" ok ipc shell setPluginEnabled acme.layers false
expect_poll "a disabled plugin's layer surfaces are gone" 0 layer_count vgs:layer
expect "a disabled plugin holds no layer" '[]' lent_layers
expect "a disabled plugin holds no layers capability" null lent holders.layers
