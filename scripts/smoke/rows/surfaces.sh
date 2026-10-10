# Hosts: a fixture of every summonable kind plus a background and a bar
# widget. Each summonable kind opens on demand, in its own layer surface
# without an anchor or as a popup of its anchor's window with one, and is
# destroyed on hide; a window is a Hyprland window with or without an
# anchor. The background is drawn on every screen while enabled. Layer
# geometry is read from the compositor's layer list, window geometry from
# its client list, popup geometry from the built instance.
# It reads what rows/hyprland-consent.sh leaves: the Hyprland layer wired
# into hyprland.lua, whose application-window rule floats a shell window
# at the size it asks. Without it the window tiles and its size and
# keyboard checks fail.
# inputs: scripts/smoke/fixtures/plugins/acme.surfaces/* shell/Hosts/SummonHost.qml shell/Hosts/SummonLayer.qml shell/Ui/layout/SurfaceHeight.qml shell/Hosts/SummonPopup.qml shell/Commons/AnchorTracker.qml shell/Ui/BarWidget.qml shell/Ui/overlay/Menu.qml shell/Hosts/PluginSlot.qml shell/Hosts/BackgroundHost.qml shell/Hosts/AppWindow.qml scripts/smoke/toplevel/* scripts/smoke/rows/sources.sh shell/Ui/foundation/FocusRing.qml shell/Ui/overlay/ModalDialog.qml shell/Ui/feedback/Dialog.qml shell/Ui/layout/Pane.qml shell/Commons/Tokens.js shell/Ui/foundation/KeyNavLogic.js scripts/smoke/rows/hyprland-consent.sh shell/Core/HyprlandLayer.js
set -euo pipefail
surf="$home/.config/vgshell/plugins/acme.surfaces"
mkdir -p "$surf"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.surfaces/." "$surf/"
python3 - "$surf/Widget.qml" <<'PYEDIT'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
marker = '    function summonHere() { return shell.surfaces.summon("panel", "{\\"from\\":\\"widget\\"}", root); }\n'
assert text.count(marker) == 1, "summonHere must occur once"
text = text.replace(marker, marker + '    function summonPayload(payload) { return shell.surfaces.summon("panel", payload || "{}", root); }\n    function toggleHere(payload) { return shell.surfaces.toggle("panel", payload || "{}", root); }\n', 1)
path.write_text(text)
PYEDIT
python3 - "$surf/Summoned.qml" <<'PYEDIT'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
marker = "    property string lastPayload: \"\"\n"
assert text.count(marker) == 1, "lastPayload must occur once"
text = text.replace(marker, marker + "    property int smokePressMarks: 0\n", 1)
marker = "    property int smokePressMarks: 0\n"
assert text.count(marker) == 1, "smokePressMarks must occur once"
text = text.replace(marker, marker + "    property int smokeCloseMarks: 0\n    property int smokeButtonMarks: 0\n", 1)
marker = "    function geometry() { const p = mapToGlobal(0, 0); return JSON.stringify([p.x, p.y, width, height]); }\n"
assert text.count(marker) == 1, "geometry must occur once"
text = text.replace(marker, marker + "    function smokeMarkerGeometry() { const p = smokeMarker.mapToGlobal(0, 0); return JSON.stringify([p.x, p.y, smokeMarker.width, smokeMarker.height]); }\n    function smokeEdgeGeometry() { const p = smokeEdge.mapToGlobal(0, 0); return JSON.stringify([p.x, p.y, smokeEdge.width, smokeEdge.height]); }\n    function smokeButtonGeometry() { const p = smokeButton.mapToGlobal(0, 0); return JSON.stringify([p.x, p.y, smokeButton.width, smokeButton.height]); }\n", 1)
marker = '    Button {\n        text: "Next"\n'
assert text.count(marker) == 1, "the Next button must occur once"
text = text.replace(marker, '    Button {\n        id: smokeButton\n        text: "Next"\n        onPressed: root.smokeButtonMarks += 1\n', 1)
marker = "    function close() {\n"
assert text.count(marker) == 1, "close function must occur once"
text = text.replace(marker, marker + "        smokeCloseMarks += 1;\n", 1)
# The marker sits on the 200x120 card, left of the centred control and
# above the edge marker: a probe copy's popup window is the card's size.
marker = "    FocusScope {\n"
insert = '''    Rectangle {
        id: smokeMarker
        x: 4
        y: 60
        width: 24
        height: 24
        color: "#ff00ff"
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: root.smokePressMarks += 1
        }
    }
'''
assert text.count(marker) == 1, "the initial focus scope must occur once"
text = text.replace(marker, insert + marker, 1)
# The edge marker sits on the card's bottom edge, the band a slide offset
# leaves outside a mask that follows the card's Translate.
marker = "    Item {\n        id: container\n"
insert = '''    Rectangle {
        id: smokeEdge
        x: 4
        y: parent.height - 18
        width: 24
        height: 16
        color: "#00ffff"
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: root.smokePressMarks += 1
        }
    }
'''
assert text.count(marker) == 1, "the menu anchor container must occur once"
text = text.replace(marker, insert + marker, 1)
# The swatch is an opaque white fill with an opaque white child over its
# right half, as a chip sits on a card. Faded as one image, both halves
# match mid-close; faded item by item, the child's half is lighter.
insert = '''    Rectangle {
        id: smokeSwatch
        x: 164
        y: 4
        width: 32
        height: 60
        color: "#ffffff"
        Rectangle { x: 16; width: 16; height: 60; color: "#ffffff" }
    }
'''
text = text.replace(marker, insert + marker, 1)
marker = "    function smokeButtonGeometry() {"
assert text.count(marker) == 1, "smokeButtonGeometry must occur once"
text = text.replace(marker, "    function smokeSwatchGeometry() { const p = smokeSwatch.mapToGlobal(0, 0); return JSON.stringify([p.x, p.y, smokeSwatch.width, smokeSwatch.height]); }\n" + marker, 1)
path.write_text(text)
PYEDIT
respaced() { "$@" | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)))'; }
surface_focused() { respaced ipc smoke focused "$1" acme.surfaces | py_reply 'import json,sys; row=json.load(sys.stdin); row[0]="Control"; print(json.dumps(row))'; }
acme_widget_laid_out() {
  local widget
  widget="$(ipc smoke barParticipationGeometry "bar:$screen_name")" || return 1
  python3 - "$widget" <<'PY'
import json, sys
try:
    bar = json.loads(sys.argv[1])
except Exception:
    print("false")
else:
    ready = bar.get("shown") and bar.get("windowVisible")
    for section in bar.get("sections", []):
        for entry in section.get("entries", []):
            box = entry.get("box")
            if entry.get("id") == "acme.surfaces":
                ready = ready and entry.get("present") and entry.get("visible") and box is not None and box[2] > 0 and box[3] > 0
                print("true" if ready else "false")
                raise SystemExit
    print("false")
PY
}
monitor_logical_size() { hypr -j monitors | py_reply 'import json,sys; m=json.load(sys.stdin)[0]; print(round(m["width"] / m["scale"]), round(m["height"] / m["scale"]))'; }
rescan "rescan after adding the hosts fixture answers ok"
expect_poll "the hosts fixture is discovered" True plugin_known acme.surfaces
expect_poll "enabling the hosts fixture is allowed" ok ipc shell setPluginEnabled acme.surfaces true

expect_poll "the background host draws one surface per screen" "$monitors" layer_count vgs:background
expect "the background sits on the bottom layer" True py_reply 'import json,subprocess,sys; print(any(l["namespace"]=="vgs:background" and l["pid"]!=-1 for m in json.loads(sys.stdin.read()).values() for l in m["levels"]["0"]))' < <(hypr -j layers)
expect "the background receives its screen" "\"$screen_name\"" ipc smoke readInstance "background:$screen_name" acme.surfaces screenName

expect "a panel summons over IPC" ok ipc shell summon panel acme.surfaces '{"n":1}'
expect "the panel received its payload" '"{\"n\":1}"' ipc smoke readInstance panel acme.surfaces lastPayload
expect_poll "the panel host maps one surface" 1 layer_count vgs:panel
# summon_box KIND: the plugin's box on the output, [x, y, w, h]: the layer's
# origin plus the instance's box in the layer, which covers the free area.
summon_box() {
  local layer item
  layer="$(surface_box "vgs:$1")" || return 1
  item="$(ipc smoke instanceGeometry "$1" acme.surfaces)" || return 1
  python3 -c 'import json,sys; l=json.loads(sys.argv[1]); r=json.loads(sys.argv[2]); print(json.dumps([l[0] + r[0], l[1] + r[1], r[2], r[3]]))' "$layer" "$item"
}
geometry read_bar_settled "the bar set has settled before the panel rows read the bar's reserved height"
read -r mon_logical_w mon_logical_h < <(monitor_logical_size) || { fail "the monitor's logical size is readable for the panel geometry"; exit 1; }
panel_gap="$(ipc smoke themeValue space.md)" || { fail "Theme.space.md is readable for the panel placement"; exit 1; }
# The summoned fixture asks for 200x120 in acme.surfaces/Summoned.qml.
geometry expect_poll "the panel's layer covers the logical free area below the bar" "[[0, $bar_reserved, $mon_logical_w, $((mon_logical_h - bar_reserved))]]" layers_of vgs:panel
geometry expect_poll "the panel takes its top-right placement below the bar" "[$((mon_logical_w - panel_gap - 200)), $((bar_reserved + panel_gap)), 200, 120]" summon_box panel
if before="$(builds)"; then
  expect "summoning an open panel is allowed" ok ipc shell summon panel acme.surfaces '{"n":2}'
  expect "the open panel received the new payload" 2 ipc smoke readInstance panel acme.surfaces opened
  expect "summoning an open panel builds nothing" "$before" builds
else
  fail "buildCount unreadable before the summon rows"
fi
expect "summoning with a close marker is allowed" ok ipc shell summon panel acme.surfaces "{\"closeMarker\":\"$sandbox/closed-by-hide\"}"
expect "hiding the panel is allowed" ok ipc shell hide panel acme.surfaces
marker() { [[ -f $1 ]] && echo yes || echo no; }
expect_poll "hide called the panel's close()" yes marker "$sandbox/closed-by-hide"
expect "the hidden panel leaves the build records" absent ipc smoke readInstance panel acme.surfaces opened
expect_poll "the panel host destroyed its surface" 0 layer_count vgs:panel
expect "toggle opens a closed panel" ok ipc shell toggle panel acme.surfaces '{}'
expect_poll "the toggled panel is mapped" 1 layer_count vgs:panel
expect "toggle closes an open panel" ok ipc shell toggle panel acme.surfaces '{}'
expect_poll "the toggled panel is gone" 0 layer_count vgs:panel

expect "a panel summons over IPC for keyboard focus" ok ipc shell summon panel acme.surfaces '{}'
expect_poll "the IPC panel focuses its primary control without a ring" '["Control", "Initial focus", false, false, true]' surface_focused panel
type_keys -k Tab || fail "sending Tab to the IPC panel failed"
expect_poll "Tab shows the IPC panel focus ring" '["Control", "Next", true, true, true]' surface_focused panel
type_keys -M shift -k Tab -m shift || fail "returning to the panel's scope leaf failed"
expect_poll "Backtab focuses the initial scope leaf with its ring" '["Control", "Initial focus", true, true, true]' surface_focused panel
expect "the IPC panel repeats its open" ok ipc shell summon panel acme.surfaces '{}'
expect_poll "a repeated panel open clears its ring" '["Control", "Initial focus", false, false, true]' surface_focused panel
type_keys -k Escape || fail "sending Escape to the IPC panel failed"
expect_poll "Escape closes an IPC panel the plugin leaves unaccepted" 0 layer_count vgs:panel

summon_noescape="$repo/shell/Hosts/SummonPopupNoEscape.qml"
summon_copy="$repo/shell/Hosts/SummonPopupNoGrab.qml"
summon_no_commit="$repo/shell/Hosts/SummonPopupNoCommit.qml"
summon_input_copy="$repo/shell/Hosts/SummonPopupInputEnabled.qml"
summon_mask_copy="$repo/shell/Hosts/SummonPopupItemMask.qml"
summon_fade_copy="$repo/shell/Hosts/SummonPopupFadeHeld.qml"
summon_fade_control="$repo/shell/Hosts/SummonPopupItemFade.qml"
layer_copy="$repo/shell/Hosts/SummonLayerNoCatch.qml"
python3 - "$repo/shell/Hosts/SummonPopup.qml" "$summon_noescape" <<'PYEDIT'
import pathlib, sys
source, target = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
text = source.read_text()
old = "        Keys.onEscapePressed: popup.requestDismiss()\n"
assert text.count(old) == 1, "the SummonPopup Escape handler must occur once"
target.write_text(text.replace(old, ""))
PYEDIT
python3 - "$repo/shell/Hosts/SummonPopup.qml" "$summon_copy" <<'PYEDIT'
import pathlib, sys
source, target = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
text = source.read_text()
assert text.count("    grabFocus: true\n") == 1, "the SummonPopup grab must occur once"
target.write_text(text.replace("    grabFocus: true\n", "    grabFocus: false\n"))
PYEDIT
# The commit request lives in the popup's AnchorTracker, so the no-commit
# copy declares an edited tracker as its own inline component: a sibling
# file written into shell/Hosts after the shell read that directory would
# not resolve.
python3 - "$repo/shell/Commons/AnchorTracker.qml" "$repo/shell/Hosts/SummonPopup.qml" "$summon_no_commit" <<'PYEDIT'
import pathlib, sys
tracker, source, target = (pathlib.Path(arg) for arg in sys.argv[1:4])
body = tracker.read_text()
old = "        if (window !== null) window.update();\n"
assert body.count(old) == 1, "the AnchorTracker commit request must occur once"
marker = "    property bool closeOnHide: true\n"
assert body.count(marker) == 1, "the AnchorTracker hide switch must occur once"
body = body.replace(marker, marker + "    property bool skipCommit: false\n", 1).replace(old, "        if (!skipCommit && window !== null) window.update();\n")
start = body.index("QtObject {\n")
inline = "    component AnchorTrackerNoCommit: " + "\n".join(("    " + line if line else line) for line in body[start:].rstrip("\n").split("\n")).lstrip() + "\n"
text = source.read_text()
marker = "import QtQuick\n"
assert text.count(marker) == 1, "the SummonPopup QtQuick import must occur once"
text = text.replace(marker, marker + "import QtQuick.Window\nimport QtQml.Models\n", 1)
old = "    readonly property AnchorTracker tracker: AnchorTracker {\n"
assert text.count(old) == 1, "the SummonPopup tracker must occur once"
text = text.replace(old, inline + "    readonly property var tracker: AnchorTrackerNoCommit {\n")
marker = "    function finishDismiss() {\n"
assert text.count(marker) == 1, "the SummonPopup finishDismiss function must occur once"
target.write_text(text.replace(marker, "    function disableCommit() { tracker.skipCommit = true; }\n\n" + marker, 1))
PYEDIT
python3 - "$repo/shell/Hosts/SummonPopup.qml" "$summon_input_copy" <<'PYEDIT'
import pathlib, sys
source, target = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
text = source.read_text()
for old, new in (("            visible: popup.closing\n", "            visible: false\n"), ("            focus: popup.closing\n", "            focus: false\n")):
    assert text.count(old) == 1, "the SummonPopup closing input guard must occur once: " + old
    text = text.replace(old, new)
target.write_text(text)
PYEDIT
python3 - "$repo/shell/Hosts/SummonPopup.qml" "$summon_mask_copy" <<'PYEDIT'
import pathlib, sys
source, target = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
text = source.read_text()
old = "    mask: Region { x: sized.x; y: sized.y; width: Math.ceil(sized.width); height: Math.ceil(sized.height) }\n"
assert text.count(old) == 1, "the SummonPopup card mask must occur once"
target.write_text(text.replace(old, "    mask: Region { item: sized }\n"))
PYEDIT
# The fade copies stop a real close half way, so a frame reads the card at
# one known progress. The control fades the card item by item, as before
# the layer.
python3 - "$repo/shell/Hosts/SummonPopup.qml" "$summon_fade_copy" "$summon_fade_control" <<'PYEDIT'
import pathlib, sys
source, held, control = (pathlib.Path(arg) for arg in sys.argv[1:4])
text = source.read_text()
marker = "    function finishDismiss() {\n"
assert text.count(marker) == 1, "the SummonPopup finishDismiss function must occur once"
text = text.replace(marker, "    function holdHalfway() { requestDismiss(); flyoutMotion.stop(); motionProgress = 0.5; }\n\n" + marker, 1)
held.write_text(text)
old = "        layer.enabled: popup.motionProgress < 1\n"
assert text.count(old) == 1, "the SummonPopup card layer must occur once"
control.write_text(text.replace(old, ""))
PYEDIT
python3 - "$repo/shell/Hosts/SummonLayer.qml" "$layer_copy" <<'PYEDIT'
import pathlib, sys
source, target = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
text = source.read_text()
old = "        enabled: win.catches\n"
assert text.count(old) == 1, "the SummonLayer catcher must occur once"
target.write_text(text.replace(old, "        enabled: false\n"))
PYEDIT
cp -- "$home/.config/vgshell/plugins/acme.surfaces/Summoned.qml" "$sandbox/Summoned.initial-focus"
python3 - "$home/.config/vgshell/plugins/acme.surfaces/Summoned.qml" <<'PYEDIT'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
old = "    property alias initialFocus: initialScope\n"
assert s.count(old) == 1
p.write_text(s.replace(old, ""))
PYEDIT
rescan "the fixture without initialFocus is rescanned"
expect "the panel without initialFocus opens" ok ipc shell summon panel acme.surfaces '{}'
expect_poll "without initialFocus the plugin has no visual focus" no-focus ipc smoke focused panel acme.surfaces
type_keys -k Escape || fail "sending Escape to the no-initialFocus panel failed"
expect_poll "the slot still closes a panel without initialFocus on Escape" 0 layer_count vgs:panel
mv -T -- "$sandbox/Summoned.initial-focus" "$home/.config/vgshell/plugins/acme.surfaces/Summoned.qml"
rescan "the fixture with initialFocus is restored"

expect "an overlay summons over IPC" ok ipc shell summon overlay acme.surfaces '{}'
read -r mon_logical_w mon_logical_h < <(monitor_logical_size) || { fail "the monitor's logical size is readable for the overlay geometry"; exit 1; }
geometry expect_poll "the overlay covers its logical screen" "[[0, 0, $mon_logical_w, $mon_logical_h]]" layers_of vgs:overlay
expect "hiding the overlay is allowed" ok ipc shell hide overlay acme.surfaces
expect_poll "the overlay host destroyed its surface" 0 layer_count vgs:overlay
expected_errors+=('summon host: acme\.surfaces open\(\) failed: probe open refused')
expect "an open() that throws refuses the summon" "refused: open-failed=acme.surfaces" ipc shell summon menu acme.surfaces '{"fail":true}'
expect_poll "the refused summon leaves no surface" 0 layer_count vgs:menu
expect "a menu summons over IPC" ok ipc shell summon menu acme.surfaces '{}'
expect_poll "the menu host maps one surface" 1 layer_count vgs:menu
expect "hiding the menu is allowed" ok ipc shell hide menu acme.surfaces
expect_poll "the menu host destroyed its surface" 0 layer_count vgs:menu

# An unanchored panel or menu covers its screen and catches a press beside
# it (SummonLayer), so a press outside the plugin closes it through the hide
# path, over a client window or on the empty desktop, and a press inside it
# does not. The fixture sits at the top right; the desktop point is the
# bottom left, and the other window tiles the screen, so its point is left
# of the panel and above the desktop point's row. A layer takes a press
# only once it has drawn at its size, so each press beside a summon that
# has just mapped waits for that (summon_drawn).
layer_desktop_point="40 $((mon_h - 40))"
layer_window_point="$((mon_w / 4)) $((mon_h / 2))"
# layer_press LABEL POINT: one press at POINT, `x y`.
layer_press() {
  local x y
  read -r x y <<<"$2"
  click "$x" "$y" || fail "$1: the press failed"
}
# layer_copy_state NAME: the dismissals the probe counted for SummonLayer
# copy NAME and the panel layers mapped, as `<dismissals> <layers>`.
layer_copy_state() { printf '%s %s\n' "$(ipc smoke summonLayerDismissals "$1")" "$(layer_count vgs:panel)"; }
smoke_marks() { ipc smoke readInstance panel acme.surfaces smokePressMarks; }
smoke_close_marks() { ipc smoke readInstance panel acme.surfaces smokeCloseMarks; }
# plugin_focus: `held` while an item of the panel instance has active focus,
# else the probe's `no-focus` or `absent`.
plugin_focus() {
  local focused
  focused="$(ipc smoke focused panel acme.surfaces)" || return 1
  case $focused in no-focus | absent) echo "$focused" ;; *) echo held ;; esac
}
smoke_marker_press() {
  local box layer x y
  box="$(ipc smoke invokeInstance panel acme.surfaces smokeMarkerGeometry '')" || return 1
  [[ $box == \[* ]] || { echo "$box"; return 1; }
  layer="$(surface_box vgs:panel)" || return 1
  read -r x y < <(python3 -c 'import json,sys; b=json.loads(sys.argv[1]); l=json.loads(sys.argv[2]); print(int(l[0] + b[0] + b[2] / 2), int(l[1] + b[1] + b[3] / 2))' "$box" "$layer") || return 1
  click "$x" "$y" >/dev/null && echo ok
}
smoke_button_marks() { ipc smoke readInstance panel acme.surfaces smokeButtonMarks; }
# popup_marker_press [GEOMETRY]: presses the centre of the box the panel
# instance's GEOMETRY function names, the edge marker by default.
popup_marker_press() {
  local box x y
  box="$(ipc smoke invokeInstance panel acme.surfaces "${1:-smokeEdgeGeometry}" '')" || return 1
  [[ $box == \[* ]] || { echo "$box"; return 1; }
  read -r x y < <(python3 -c 'import json,sys; b=json.loads(sys.argv[1]); print(int(b[0] + b[2] / 2), int(b[1] + b[3] / 2))' "$box") || return 1
  click "$x" "$y" >/dev/null && echo ok
}
expect "a panel summons for the outside press on the desktop" ok ipc shell summon panel acme.surfaces "{\"closeMarker\":\"$sandbox/closed-by-desktop-press\"}"
expect_poll "the panel is mapped before the inside press" 1 layer_count vgs:panel
summon_drawn panel acme.surfaces || fail "the panel never drew before the inside press"
# The inside point is 6 px into the fixture's top-left corner, clear of its
# centred control, so no item of the plugin takes the press and the catcher
# under it must leave it.
if panel_inside="$(python3 -c 'import json,sys; b=json.loads(sys.argv[1]); print(int(b[0] + 6), int(b[1] + 6))' "$(summon_box panel)")"; then
  inside_mark="$(smoke_marks)" || fail "the press marker is readable before the inside press"
  layer_press "the press inside the panel" "$panel_inside"
  expect "the marker press after the inside press is sent" ok smoke_marker_press
  expect_poll "the panel processes input after the inside press" "$((inside_mark + 1))" smoke_marks
  expect "a press inside the panel leaves it open" 1 layer_count vgs:panel
else
  fail "the panel's box is unreadable"
fi
layer_press "the press on the desktop" "$layer_desktop_point"
expect_poll "a press on the desktop called the panel's close()" yes marker "$sandbox/closed-by-desktop-press"
expect_poll "a press on the desktop closes an unanchored panel" 0 layer_count vgs:panel
expect "a menu summons for the outside press" ok ipc shell summon menu acme.surfaces '{}'
expect_poll "the menu is mapped before the outside press" 1 layer_count vgs:menu
summon_drawn menu acme.surfaces || fail "the menu never drew before the outside press"
layer_press "the press beside the menu" "$layer_desktop_point"
expect_poll "a press on the desktop closes an unanchored menu" 0 layer_count vgs:menu
expect_poll "the closed menu leaves the build records" absent ipc smoke readInstance menu acme.surfaces opened
if open_other "$sandbox/toplevel-surfaces-outside-press.log"; then
  expect "a panel summons over the other window" ok ipc shell summon panel acme.surfaces '{}'
  expect_poll "the panel is mapped over the other window" 1 layer_count vgs:panel
  summon_drawn panel acme.surfaces || fail "the panel over the other window never drew"
  layer_press "the press on the other window" "$layer_window_point"
  expect_poll "a press on a client window closes an unanchored panel" 0 layer_count vgs:panel
  expect "the press beside the panel never reached the other window" 0 other_events "^button 272 pressed$"
  expect_poll "the panel closed by the window press leaves the build records" absent ipc smoke readInstance panel acme.surfaces opened

  # Control: the SummonLayer copy whose catcher takes no press, written at
  # the top of the row, stays open under the same presses, over the window
  # and on the desktop. The probe counts the copy's dismissals.
  expect "the probe builds the SummonLayer copy without the catcher" ok ipc smoke summonLayerLoad layer-nocatch "$layer_copy" acme.surfaces panel
  ipc smoke invokeInstance panel acme.surfaces open '{}' >/dev/null || fail "the catchless layer copy's open() could not be called"
  expect_poll "the catchless layer copy has opened its panel" 1 ipc smoke readInstance panel acme.surfaces opened
  expect_poll "the catchless layer copy is mapped" "0 1" layer_copy_state layer-nocatch
  summon_drawn panel acme.surfaces || fail "the catchless layer copy never drew"
  client_mark="$(smoke_marks)" || fail "the press marker is readable before the catchless client-window press"
  layer_press "the press on the other window beside the catchless copy" "$layer_window_point"
  expect "the marker press after the client-window press is sent" ok smoke_marker_press
  expect_poll "the catchless copy processes input after the client-window press" "$((client_mark + 1))" smoke_marks
  expect "control: a press on a client window leaves the catchless copy open" "0 1" layer_copy_state layer-nocatch
  desktop_mark="$(smoke_marks)" || fail "the press marker is readable before the catchless desktop press"
  layer_press "the press on the desktop beside the catchless copy" "$layer_desktop_point"
  expect "the marker press after the desktop press is sent" ok smoke_marker_press
  expect_poll "the catchless copy processes input after the desktop press" "$((desktop_mark + 1))" smoke_marks
  expect "control: a press on the desktop leaves the catchless copy open" "0 1" layer_copy_state layer-nocatch
  expect "the probe drops the catchless layer copy" ok ipc smoke popupDrop layer-nocatch
  expect_poll "the catchless layer copy leaves the build records" absent ipc smoke readInstance panel acme.surfaces opened
  expect_poll "the catchless layer copy's surface is gone" 0 layer_count vgs:panel
  close_other "the outside-press window's helper exits 0 on SIGTERM"
else
  fail "the other window for the outside press did not map"
fi

# An application window: a client of the shell's class titled with the
# plugin's name, at the size the instance asks, whatever the plugin's
# placement setting. Summoning an open one hands it the new payload and
# builds nothing; hide and a close through Hyprland each call close() and
# destroy it; an anchored summon builds a window all the same.
window_size() { window_of Surfaces size; }
expect "a window summons over IPC" ok ipc shell summon window acme.surfaces '{"n":1}'
expect "the window received its payload" '"{\"n\":1}"' ipc smoke readInstance window acme.surfaces lastPayload
expect_poll "the window host maps one window titled with the plugin's name" 1 window_count Surfaces
expect_poll "the window focuses its primary control without a ring" '["Control", "Initial focus", false, false, true]' surface_focused window
type_keys -k Tab || fail "sending Tab to the window failed"
expect_poll "Tab shows the window focus ring" '["Control", "Next", true, true, true]' surface_focused window
geometry expect_poll "the window asks for the instance's size, whatever its placement setting" '[[200, 120]]' window_size
expect "the window host maps no layer surface" 0 layer_count vgs:window
if before="$(builds)"; then
  expect "summoning an open window is allowed" ok ipc shell summon window acme.surfaces '{"n":2}'
  expect "the open window received the new payload" 2 ipc smoke readInstance window acme.surfaces opened
  expect "summoning an open window builds nothing" "$before" builds
else
  fail "buildCount unreadable before the window rows"
fi
expect "summoning the window with a close marker is allowed" ok ipc shell summon window acme.surfaces "{\"closeMarker\":\"$sandbox/window-closed-by-hide\"}"
expect "hiding the window is allowed" ok ipc shell hide window acme.surfaces
expect_poll "hide called the window's close()" yes marker "$sandbox/window-closed-by-hide"
expect_poll "the window host destroyed the window" 0 window_count Surfaces
expect "toggle opens a closed window" ok ipc shell toggle window acme.surfaces '{}'
expect_poll "the toggled window is mapped" 1 window_count Surfaces
expect "toggle closes an open window" ok ipc shell toggle window acme.surfaces '{}'
expect_poll "the toggled window is gone" 0 window_count Surfaces
expect "the widget summons its window with itself as the anchor" ok ipc smoke invokeInstance "bar:$screen_name" acme.surfaces windowHere "{\"closeMarker\":\"$sandbox/window-closed-by-hyprland\"}"
expect_poll "an anchored window summon maps a window" 1 window_count Surfaces
expect "an anchored window summon maps no popup panel" absent ipc smoke readInstance panel acme.surfaces opened
if surfaces_address="$(window_of Surfaces address)" && [[ $surfaces_address == \[\"0x* ]]; then
  surfaces_address="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])[0])' "$surfaces_address")"
  expect "a close dispatch aimed at the window answers ok" ok hypr dispatch "hl.dsp.window.close({ window = \"address:$surfaces_address\" })"
  expect_poll "a close through Hyprland called the window's close()" yes marker "$sandbox/window-closed-by-hyprland"
  expect_poll "a close through Hyprland removed the window from the build records" absent ipc smoke readInstance window acme.surfaces opened
  expect_poll "a close through Hyprland left no window" 0 window_count Surfaces
else
  fail "the fixture window's address is unreadable: ${surfaces_address:-}"
fi

# A small plugin request must include the Pane's actual title and sources.
# The last row is checked at open, then at the shared screen cap with the
# production scroll area moved to its end. The ignored-request plant below
# reaches the same clipped row that the Updates title gap exposed.
surface_content_state() { ipc smoke titledPaneContent window acme.surfaces; }
surface_content_visible() { surface_content_state | py_reply 'import json,sys; rows=json.load(sys.stdin); print(isinstance(rows,list) and len(rows)==1 and rows[0]["lastRowVisible"] and rows[0]["footerFits"])'; }
surface_last_row_check() { expect "the titled window keeps its last source row visible" True surface_content_visible; }
expect "the source-row fixture opens its titled window" ok ipc shell summon window acme.surfaces '{"sizing":true}'
geometry expect_poll "the titled window grows to keep its last source row visible" True surface_content_visible
printf 'surfaces: titled-window opened=%s\n' "$(surface_content_state)"
expect "the fitted source window closes" ok ipc shell hide window acme.surfaces
expect "the source-row fixture opens beyond the screen cap" ok ipc shell summon window acme.surfaces '{"sizing":true,"rows":100}'
geometry expect_poll "the capped source window exposes its shared scrollbar" true ipc smoke readDescendant window acme.surfaces ScrollArea overflowing
expect "the shared Pane scrolls to its last row" True py_reply 'import json,sys; rows=json.load(sys.stdin); print(isinstance(rows,list) and len(rows)==1 and rows[0]["lastRowVisible"] and rows[0]["footerFits"] and rows[0]["scrollbarVisible"] and rows[0]["contentY"]>0)' <<<"$(ipc smoke titledPaneScrollEnd window acme.surfaces)"
printf 'surfaces: titled-window capped=%s\n' "$(surface_content_state)"
expect "the capped source window closes" ok ipc shell hide window acme.surfaces

# Popup geometry is read from the instance through Item.mapToGlobal, which
# answers in the coordinates of the window the popup was anchored in, after
# the compositor's configure event; the anchor is read the same way, from
# the same window. A bar's window starts at the screen's top-left corner;
# a layer panel's origin is read from the compositor's layer list. A popup
# sits flush under its anchor, centred on it when that fits the screen;
# one that would not fit is the compositor's to slide, and the row asserts
# only that it stays on the screen and under its anchor.
popup_geometry() { ipc smoke invokeInstance "$1" acme.surfaces geometry ''; }
popup_marker_geometry() { ipc smoke invokeInstance "$1" acme.surfaces smokeMarkerGeometry ''; }
popup_marker_box() {
  local socket
  socket="$(shot_socket "$rt_dir" "$nested_socket" "$host_socket")" || return 1
  shot_grim "$socket" "$rt_dir" -o "$screen_name" -t ppm - | python3 -c '
import sys
data = sys.stdin.buffer.read().split(b"\n", 3)
if len(data) != 4 or data[0] != b"P6" or data[2] != b"255":
    print("unreadable")
    sys.exit()
w, h = map(int, data[1].split())
pixels = data[3]
if len(pixels) != w * h * 3:
    print("unreadable")
    sys.exit()
xs, ys = [], []
for i in range(0, len(pixels), 3):
    r, g, b = pixels[i], pixels[i + 1], pixels[i + 2]
    if r >= 240 and g <= 32 and b >= 240:
        p = i // 3
        xs.append(p % w)
        ys.append(p // w)
if not xs:
    print("absent")
else:
    print("[%d,%d,%d,%d]" % (min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1))
'
}
popup_marker_mapped() {
  local actual expected
  actual="$(popup_marker_box)" || return 1
  expected="$(popup_marker_geometry panel)" || return 1
  python3 - "$actual" "$expected" <<'PY'
import json, sys
try:
    actual = json.loads(sys.argv[1])
    expected = json.loads(sys.argv[2])
except Exception:
    print("marker=%s expected=%s" % (sys.argv[1], sys.argv[2]))
    sys.exit()
same = len(actual) == 4 and len(expected) == 4 and all(abs(actual[i] - expected[i]) <= 1 for i in range(4))
print("followed" if same else "marker=%s expected=%s" % (actual, expected))
PY
}
# popup_marker_follows: `followed` when the marker the compositor draws
# stands where the widget's on-screen position puts it: the popup centred
# under the widget, and the marker at its offset in the popup. The tail
# widget keeps the fixture widget clear of the screen's edge, so the
# compositor slides nothing. Qt's own mapping of the popup is read only for
# the marker's offset, which no reposition changes, so a popup the
# compositor leaves behind fails while Qt maps it at the widget.
popup_marker_follows() {
  local actual widget popup marker
  actual="$(popup_marker_box)" || return 1
  widget="$(ipc smoke invokeInstance "bar:$screen_name" acme.surfaces geometry '')" || return 1
  popup="$(popup_geometry panel)" || return 1
  marker="$(popup_marker_geometry panel)" || return 1
  python3 - "$actual" "$widget" "$popup" "$marker" <<'PY'
import json, sys
try:
    actual, widget, popup, marker = (json.loads(v) for v in sys.argv[1:5])
    ax, ay, aw, ah = widget
    x = round(ax + aw / 2 - popup[2] / 2)
    expected = [x + marker[0] - popup[0], ay + ah + marker[1] - popup[1], marker[2], marker[3]]
except Exception:
    print("marker=%s widget=%s popup=%s qt-marker=%s" % tuple(sys.argv[1:5]))
    sys.exit()
same = len(actual) == 4 and all(abs(actual[i] - expected[i]) <= 1 for i in range(4))
print("followed" if same else "marker=%s expected=%s widget=%s" % (actual, expected, widget))
PY
}
popup_motion_state() {
  local value
  value="$(ipc smoke popupRead "$1" motionProgress)" || return 1
  python3 - "$value" <<'PY'
import sys
try:
    value = float(sys.argv[1])
except ValueError:
    print(sys.argv[1])
    sys.exit()
if value <= 0:
    print("closed")
elif value < 1:
    print("moving")
else:
    print("rest")
PY
}
popup_fade_slide_state() {
  local progress opacity y
  progress="$(ipc smoke popupRead "$1" motionProgress)" || return 1
  opacity="$(ipc smoke popupRead "$1" cardOpacity)" || return 1
  y="$(ipc smoke popupRead "$1" cardTranslateY)" || return 1
  python3 - "$progress" "$opacity" "$y" <<'PY'
import sys
try:
    progress, opacity, y = map(float, sys.argv[1:4])
except ValueError:
    print("progress=%s opacity=%s y=%s" % tuple(sys.argv[1:4]))
    raise SystemExit
moving = 0 < progress < 1 and 0 <= opacity < 1 and y < 0
print("moving" if moving else "progress=%.3f opacity=%.3f y=%.3f" % (progress, opacity, y))
PY
}
# popup_swatch_fade: the fixture swatch in one frame of the screen, read
# on its middle row: `rest` while its fill still reads white, `one` when
# its two halves match, else `patch` with both colours.
popup_swatch_fade() {
  local box socket frame="$sandbox/surfaces-swatch.ppm"
  box="$(ipc smoke invokeInstance panel acme.surfaces smokeSwatchGeometry '')" || return 1
  socket="$(shot_socket "$rt_dir" "$nested_socket" "$host_socket")" || return 1
  shot_grim "$socket" "$rt_dir" -o "$screen_name" -t ppm "$frame" || return 1
  python3 - "$frame" "$box" <<'PY'
import json, sys
head = open(sys.argv[1], "rb").read().split(b"\n", 3)
if len(head) != 4 or head[0] != b"P6" or head[2] != b"255":
    print("unreadable")
    sys.exit()
w, h = map(int, head[1].split())
try:
    x, y, bw, bh = json.loads(sys.argv[2])
except Exception:
    print("swatch=%s" % sys.argv[2])
    sys.exit()
row = int(y + bh / 2)
def at(cx):
    i = (row * w + int(cx)) * 3
    return tuple(head[3][i:i + 3])
if not (0 <= row < h and 0 <= x and x + bw < w) or len(head[3]) != w * h * 3:
    print("swatch=%s frame=%dx%d" % (sys.argv[2], w, h))
    sys.exit()
left, right = at(x + bw / 4), at(x + 3 * bw / 4)
if min(left) >= 250:
    print("rest")
elif max(abs(a - b) for a, b in zip(left, right)) <= 3:
    print("one")
else:
    print("patch left=#%02x%02x%02x right=#%02x%02x%02x" % (left + right))
PY
}
popup_swatch_patch() { local state; state="$(popup_swatch_fade)" || return 1; [[ $state == patch* ]] && echo patch || echo "$state"; }
install_tail_widget() {
  local tail="$home/.config/vgshell/plugins/acme.surfaces-tail"
  mkdir -p "$tail"
  cp -R "$repo/scripts/smoke/fixtures/plugins/acme.surfaces/." "$tail/"
  python3 - "$tail/manifest.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
d["id"] = "acme.surfaces-tail"
d["name"] = "Surfaces tail"
d["kinds"] = ["bar-widget"]
d["entryPoints"] = {"bar-widget": "Widget.qml"}
d.pop("capabilities", None)
p.write_text(json.dumps(d))
PY
  python3 - "$tail/Widget.qml" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
t = p.read_text()
assert t.count("    implicitWidth: 30\n") == 1, "implicitWidth must occur once"
# A Row sizes in its window's polish pass, as Traffic's speeds do, so the
# growth moves its neighbours during the bar's polish. Its 300 px base keeps
# the fixture widget's flyout and menu clear of the screen's right edge.
t = t.replace("    implicitWidth: 30\n", "    implicitWidth: smokeRow.implicitWidth\n    function grow(width) { smokeWide.width = Number(width) || 100; smokeWide.visible = true; return \"grown\"; }\n    Row {\n        id: smokeRow\n        Item { width: 300; height: 1 }\n        Item { id: smokeWide; visible: false; width: 100; height: 1 }\n    }\n", 1)
p.write_text(t)
PY
  rescan "the tail widget fixture is scanned for the flyout follow re-layout"
  expect "enabling the tail widget fixture is allowed" ok ipc shell setPluginEnabled acme.surfaces-tail true
}
remove_tail_widget() {
  expect "hiding the tail widget fixture is allowed" ok ipc shell setPluginPlaced acme.surfaces-tail false
  rm -rf -- "$home/.config/vgshell/plugins/acme.surfaces-tail"
  rescan "the tail widget fixture is removed after the flyout follow check"
}
placed_below() { # POPUP_KIND ANCHOR_HOST ANCHOR_FUNCTION [WINDOW_X WINDOW_Y]
  local actual anchor
  actual="$(popup_geometry "$1")" || return
  anchor="$(ipc smoke invokeInstance "$2" acme.surfaces "$3" '')" || return
  # Answers `placed`, or the geometry read, so a failure names it.
  python3 - "$actual" "$anchor" "$mon_logical_w" "${4:-0}" "${5:-0}" <<'PY'
import json, sys
x, y, w, h = json.loads(sys.argv[1])
ax, ay, aw, ah = json.loads(sys.argv[2])
mw, wx, wy = (int(v) for v in sys.argv[3:6])
centred = round(ax + aw / 2 - w / 2)
fits = 0 <= centred + wx and centred + wx + 200 <= mw
placed = (w, h, y) == (200, 120, ay + ah) and ((x == centred) if fits else (0 <= x + wx and x + wx + w <= mw and x < ax + aw and x + w > ax))
print("placed" if placed else "popup=%s anchor=%s centred=%s fits=%s" % (sys.argv[1], sys.argv[2], centred, fits))
PY
}
panel_origin() { layers_of vgs:panel | py_reply 'import json,sys; l=json.load(sys.stdin)[0]; print(l[0], l[1])'; }
expect "the widget summons its panel under itself" ok ipc smoke invokeInstance "bar:$screen_name" acme.surfaces summonHere ''
geometry expect_poll "the popup panel sits under its widget" placed placed_below panel "bar:$screen_name" geometry
render expect_poll "the compositor shows the panel marker where Qt maps it" followed popup_marker_mapped
flyout_follow_check() { render expect_poll "the compositor flyout follows the widget after another right-section widget is added" followed popup_marker_follows; }
anchor_updates="$(log_lines 'summon popup: anchor updated for acme\.surfaces')" || fail "instance log unreadable: $instance_log"
install_tail_widget
expect_log "the host updates the popup's anchor for the bar re-layout" "$((anchor_updates + 1))" 'summon popup: anchor updated for acme\.surfaces'
flyout_follow_check
# A neighbour that changes width moves the widget with no widget added or
# removed, and the flyout, open and still, follows it.
flyout_widget_x() { ipc smoke invokeInstance "bar:$screen_name" acme.surfaces geometry '' | py_reply 'import json,sys; print(json.load(sys.stdin)[0])'; }
flyout_rest_x="$(flyout_widget_x)" || flyout_rest_x=unreadable
flyout_first_rest_x="$flyout_rest_x"
# One render call holds the growth, so the bar frame the growth draws
# counts and a flyout left behind fails rather than reading as a stalled
# sandbox.
flyout_grow_check() {
  expect "the tail widget fixture grows while the flyout is open" grown ipc smoke invokeInstance "bar:$screen_name" acme.surfaces-tail grow ''
  [[ $flyout_rest_x =~ ^-?[0-9]+$ ]] || fail "the widget's x before the growth is unreadable: $flyout_rest_x"
  expect_poll "the tail widget's growth moves the widget left" "$((${flyout_rest_x//[!0-9-]/} - 100))" flyout_widget_x
  expect_poll "the compositor flyout follows the widget after its neighbour grows" followed popup_marker_follows
}
render flyout_grow_check
expect "the anchored panel received the widget's payload" '"{\"from\":\"widget\"}"' ipc smoke readInstance panel acme.surfaces lastPayload
expect "the anchored panel uses no layer surface" 0 layer_count vgs:panel
expect_poll "the anchored panel focuses initialFocus without a ring" '["Control", "Initial focus", false, false, true]' surface_focused panel
type_keys -k Tab || fail "sending Tab to the anchored panel failed"
expect_poll "Tab shows the popup focus ring" '["Control", "Next", true, true, true]' surface_focused panel
type_keys -k Escape || fail "sending Escape to the anchored panel failed"
expect_poll "Escape closes an anchored panel the plugin leaves unaccepted" absent ipc smoke readInstance panel acme.surfaces opened

# The widget's bar menu, an overlay its AnchorTracker keeps with the widget,
# follows it the same way when the tail widget grows again. The menu is
# what the screen draws below the bar that a frame taken before it opened
# does not, and it stands at the widget's left edge, at the height it opened
# at. Every frame the check reads holds the pointer parked at the output's
# bottom-left pixel: on the widget, its image reaches below the bar and
# changes shape once the growth moves the widget from under it, which reads
# as menu. At (1, height - 1) only the tip's row stays on the output, not
# the ten rows the harness's rest point (rest_pointer) leaves, and the check
# holds while that row keeps one shape.
surf_menu_ref="$sandbox/surfaces-menu-ref.ppm"
surf_menu_grab() { local socket; socket="$(shot_socket "$rt_dir" "$nested_socket" "$host_socket")" && shot_grim "$socket" "$rt_dir" -o "$screen_name" -t ppm "$1"; }
# surf_menu_still: `still` once a frame equals the one before it.
surf_menu_still() {
  surf_menu_grab "$surf_menu_ref.next" || return 1
  if cmp -s "$surf_menu_ref" "$surf_menu_ref.next"; then echo still; else mv -- "$surf_menu_ref.next" "$surf_menu_ref"; echo moving; fi
}
surf_menu_box() {
  surf_menu_grab "$surf_menu_ref.now" || return 1
  python3 - "$surf_menu_ref.now" "$surf_menu_ref" "$bar_reserved" <<'PY'
import sys
def ppm(path):
    head = open(path, "rb").read().split(b"\n", 3)
    if len(head) != 4 or head[0] != b"P6" or head[2] != b"255":
        return None
    w, h = map(int, head[1].split())
    return (w, h, head[3]) if len(head[3]) == w * h * 3 else None
now, ref, top = ppm(sys.argv[1]), ppm(sys.argv[2]), int(sys.argv[3])
if now is None or ref is None or now[:2] != ref[:2]:
    print("unreadable")
    sys.exit()
w, h = now[:2]
ys, xs = [], []
for y in range(top, h):
    a, b = now[2][y * w * 3:(y + 1) * w * 3], ref[2][y * w * 3:(y + 1) * w * 3]
    if a == b:
        continue
    cols = [x for x in range(w) if a[3 * x:3 * x + 3] != b[3 * x:3 * x + 3]]
    ys.append(y)
    xs += [cols[0], cols[-1]]
print("absent" if not ys else "[%d,%d,%d,%d]" % (min(xs), ys[0], max(xs) - min(xs) + 1, ys[-1] - ys[0] + 1))
PY
}
surf_menu_follows() { # [OPEN_BOX]
  local box widget
  box="$(surf_menu_box)" || return 1
  widget="$(ipc smoke invokeInstance "bar:$screen_name" acme.surfaces geometry '')" || return 1
  python3 - "$box" "$widget" "${1:-[]}" <<'PY'
import json, sys
try:
    box, widget, opened = (json.loads(v) for v in sys.argv[1:4])
    same = abs(box[0] - widget[0]) <= 1 and box[1] >= widget[1] + widget[3] and (not opened or box[1:] == opened[1:])
except Exception:
    print("menu=%s widget=%s opened=%s" % tuple(sys.argv[1:4]))
    sys.exit()
print("followed" if same else "menu=%s widget=%s opened=%s" % (box, widget, opened))
PY
}
read -r surf_menu_x surf_menu_y < <(ipc smoke invokeInstance "bar:$screen_name" acme.surfaces geometry '' | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print(int(x+w/2), int(y+h/2))') || fail "the fixture widget has no box to right-click"
surf_menu_park() { hover 1 "$((mon_h - 1))"; }
surf_menu_park || fail "parking the pointer before the bar menu opens failed"
surf_menu_grab "$surf_menu_ref" || fail "the frame before the bar menu opens is unreadable"
render expect_poll "the screen is still before the bar menu opens" still surf_menu_still
hover "$((surf_menu_x + 1))" "$surf_menu_y" && right_click "$surf_menu_x" "$surf_menu_y" || fail "the right click on the fixture widget failed"
expect_poll "a right click on the fixture widget opens its bar menu" true ipc smoke readInstance "bar:$screen_name" acme.surfaces frameMenuOpen
surf_menu_park || fail "parking the pointer off the open bar menu failed"
render expect_poll "the compositor draws the bar menu under its widget" followed surf_menu_follows
surf_menu_open_box="$(surf_menu_box)" || surf_menu_open_box=unreadable
flyout_rest_x="$(flyout_widget_x)" || flyout_rest_x=unreadable
surf_menu_grow_check() {
  expect "the tail widget fixture grows again while the menu is open" grown ipc smoke invokeInstance "bar:$screen_name" acme.surfaces-tail grow 200
  [[ $flyout_rest_x =~ ^-?[0-9]+$ ]] || fail "the widget's x before the second growth is unreadable: $flyout_rest_x"
  expect_poll "the second growth moves the widget left" "$((${flyout_rest_x//[!0-9-]/} - 100))" flyout_widget_x
  expect_poll "the compositor bar menu follows the widget after its neighbour grows" followed surf_menu_follows "$surf_menu_open_box"
}
render surf_menu_grow_check
# The menu moved, so the check above read a move and not a menu at rest.
expect "the bar menu left where it opened" True py_reply 'import json,sys; a=json.loads(sys.argv[1]); b=json.load(sys.stdin); print(a[0] != b[0])' "$surf_menu_open_box" < <(surf_menu_box)
type_keys -k Escape || fail "sending Escape to the bar menu failed"
expect_poll "Escape closes the bar menu" false ipc smoke readInstance "bar:$screen_name" acme.surfaces frameMenuOpen
remove_tail_widget

expect "the unanchored panel opens for a nested menu" ok ipc shell summon panel acme.surfaces '{}'
expect_poll "the parent panel is mapped" 1 layer_count vgs:panel
read -r panel_x panel_y < <(panel_origin)
expect "the panel summons a menu from its own item" ok ipc smoke invokeInstance panel acme.surfaces menuHere '{}'
geometry expect_poll "the nested menu uses its parent's window coordinates" placed placed_below menu panel anchorGeometry "$panel_x" "$panel_y"
type_keys -k Escape || fail "sending Escape to the nested menu failed"
expect_poll "Escape closes the nested menu" absent ipc smoke readInstance menu acme.surfaces opened
expect_poll "closing a popup returns focus to the parent panel" '["Control", "Initial focus", false, false, true]' surface_focused panel
expect "the panel summons a menu from its own item again" ok ipc smoke invokeInstance panel acme.surfaces menuHere '{}'
geometry expect_poll "the nested menu still uses its parent's window coordinates" placed placed_below menu panel anchorGeometry "$panel_x" "$panel_y"
anchor_updates="$(log_lines 'summon popup: anchor updated for acme\.surfaces')" || fail "instance log unreadable: $instance_log"
expect "moving an anchor ancestor is allowed" ok ipc smoke invokeInstance panel acme.surfaces moveAnchor ''
expect_log "the host updates the popup's anchor for the moved ancestor" "$((anchor_updates + 1))" 'summon popup: anchor updated for acme\.surfaces'
render expect_poll "the popup follows its moving anchor ancestor" placed placed_below menu panel anchorGeometry "$panel_x" "$panel_y"
expect "hiding an anchor ancestor is allowed" ok ipc smoke invokeInstance panel acme.surfaces hideAnchor ''
expect_poll "hiding an anchor closes its popup" absent ipc smoke readInstance menu acme.surfaces opened
expect "hiding the parent panel is allowed" ok ipc shell hide panel acme.surfaces

expect "the rightmost widget opens a menu" ok ipc smoke invokeInstance "bar:$screen_name" acme.surfaces menuHere '{}'
geometry expect_poll "the menu at the screen edge stays fully on screen" placed placed_below menu "bar:$screen_name" geometry
expect "hiding the edge menu is allowed" ok ipc shell hide menu acme.surfaces

surface_motion_theme="$home/.config/vgshell/theme.json"
surface_motion_had_theme=false
if [[ -f $surface_motion_theme ]]; then
  cp -- "$surface_motion_theme" "$sandbox/surface-motion-theme.json"
  surface_motion_had_theme=true
fi
printf '%s\n' '{"schemaVersion":1,"name":"surface-motion","tokens":{"motion":{"scale":4}}}' >"$surface_motion_theme.tmp"
mv -T -- "$surface_motion_theme.tmp" "$surface_motion_theme"
expect_poll "the flyout motion duration is slowed for the motion check" 400 ipc smoke themeValue motion.flyout.travel.duration
expect "the widget toggles its panel open for host-close motion" ok ipc smoke invokeInstance "bar:$screen_name" acme.surfaces toggleHere "{\"closeMarker\":\"$sandbox/closed-by-toggle-motion\"}"
expect_poll "the host-close panel is open before toggle close" 1 ipc smoke readInstance panel acme.surfaces opened
expect "the widget toggle starts the host-close motion" ok ipc smoke invokeInstance "bar:$screen_name" acme.surfaces toggleHere '{}'
expect "toggle close keeps the panel instance during the motion" 1 ipc smoke readInstance panel acme.surfaces opened
expect "toggle close calls no close() before the motion ends" 0 smoke_close_marks
expect "a widget toggle during close reopens the same panel" ok ipc smoke invokeInstance "bar:$screen_name" acme.surfaces toggleHere "{\"closeMarker\":\"$sandbox/closed-by-ipc-motion\"}"
expect_poll "toggle during close calls open() on the same panel" 2 ipc smoke readInstance panel acme.surfaces opened
expect "a reopen during the motion leaves close() uncalled" 0 smoke_close_marks
expect "IPC hide starts the host-close motion" ok ipc shell hide panel acme.surfaces
expect "IPC hide keeps the panel instance during the motion" 2 ipc smoke readInstance panel acme.surfaces opened
expect "IPC hide calls no close() before the motion ends" 0 smoke_close_marks
expect_poll "IPC hide called the panel's close() when the motion ended" yes marker "$sandbox/closed-by-ipc-motion"
expect_poll "IPC hide destroys the panel after the close motion" absent ipc smoke readInstance panel acme.surfaces opened
expect "the widget opens a panel for Escape-close reopen" ok ipc smoke invokeInstance "bar:$screen_name" acme.surfaces summonHere ''
expect_poll "the Escape-close panel opens" 1 ipc smoke readInstance panel acme.surfaces opened
type_keys -k Escape || fail "sending Escape to the slowed panel failed"
expect "Escape close calls no close() before the motion ends" 0 smoke_close_marks
expect "summon during Escape close reopens the panel" ok ipc smoke invokeInstance "bar:$screen_name" acme.surfaces summonHere ''
expect_poll "summon during Escape close keeps the panel open" 2 ipc smoke readInstance panel acme.surfaces opened
type_keys -k Escape || fail "sending Escape to the slowed panel for toggle failed"
expect "toggle during Escape close reopens the panel" ok ipc smoke invokeInstance "bar:$screen_name" acme.surfaces toggleHere '{}'
expect_poll "toggle during Escape close keeps the panel open" 3 ipc smoke readInstance panel acme.surfaces opened
expect "the panel closes before popup copy checks" ok ipc shell hide panel acme.surfaces
expect_poll "the panel is gone before popup copy checks" absent ipc smoke readInstance panel acme.surfaces opened
expect "the probe builds the SummonPopup copy for motion" ok ipc smoke popupLoad summon-motion "$repo/shell/Hosts/SummonPopup.qml" "bar:$screen_name" acme.surfaces '{"pluginId":"acme.surfaces","kind":"panel","request":{"anchor":"@instance","anchored":true,"payloadJson":"{}"}}'
expect "the motion copy's panel takes a payload" '' ipc smoke invokeInstance panel acme.surfaces open '{}'
expect_poll "the motion copy is shown before its motion is read" true ipc smoke popupRead summon-motion visible
expect "the motion copy opens with a fade and slide in progress" moving popup_fade_slide_state summon-motion
expect_poll "the motion copy reaches rest after opening" rest popup_motion_state summon-motion
expect_poll "the open motion copy's plugin holds the keyboard focus" held plugin_focus
expect "the motion copy marker starts untouched" 0 smoke_marks
expect "the open card's bottom-edge marker press is sent" ok popup_marker_press
expect "a plugin MouseArea on the open card's bottom edge takes the press" 1 smoke_marks
expect "a press on the open card's bottom edge leaves it shown" true ipc smoke popupRead summon-motion visible
expect "the open card's Templates button press is sent" ok popup_marker_press smokeButtonGeometry
expect "a Templates control on the open card takes the press" 1 smoke_button_marks
expect "the motion copy starts closing" ok ipc smoke popupCall summon-motion requestDismiss
expect "the motion copy closes with a fade and slide in progress" moving popup_fade_slide_state summon-motion
expect "the closing card's plugin holds no keyboard focus" no-focus plugin_focus
type_keys -k Tab || fail "sending Tab to the closing card failed"
expect "a Tab during the close focuses nothing in the plugin" no-focus plugin_focus
expect "pressing the closing motion copy marker is sent" ok popup_marker_press
expect "the closing card's plugin MouseArea takes no press" 1 smoke_marks
expect "the marker press landed while the card was closing" moving popup_motion_state summon-motion
expect "a reopen during the close is allowed" ok ipc smoke popupCall summon-motion reopenFromHost
expect_poll "the reopened card's plugin takes its keyboard focus back" held plugin_focus
expect_poll "the reopened motion copy reaches rest" rest popup_motion_state summon-motion
expect "the motion copy starts closing again" ok ipc smoke popupCall summon-motion requestDismiss
expect "pressing the closing card's Templates button is sent" ok popup_marker_press smokeButtonGeometry
expect "the closing card's Templates control takes no press" 1 smoke_button_marks
expect "the button press landed while the card was closing" moving popup_motion_state summon-motion
expect_poll "the motion copy releases its popup after closing" false ipc smoke popupRead summon-motion visible
expect "the probe drops the motion copy" ok ipc smoke popupDrop summon-motion
expect_poll "the motion copy's panel leaves the build records" absent ipc smoke readInstance panel acme.surfaces opened
expect "the probe builds the input-control popup copy" ok ipc smoke popupLoad summon-input-control "$summon_input_copy" "bar:$screen_name" acme.surfaces '{"pluginId":"acme.surfaces","kind":"panel","request":{"anchor":"@instance","anchored":true,"payloadJson":"{}"}}'
expect "the input-control copy's panel takes a payload" '' ipc smoke invokeInstance panel acme.surfaces open '{}'
expect_poll "the input-control copy is shown" true ipc smoke popupRead summon-input-control visible
expect "the input-control copy starts closing" ok ipc smoke popupCall summon-input-control requestDismiss
type_keys -k Tab || fail "sending Tab to the unguarded closing card failed"
expect "control: without the key sink a Tab during the close focuses the plugin" held plugin_focus
expect "control: without the input guard the closing marker press reaches the plugin" ok popup_marker_press
expect "control: the unguarded closing marker press increments the marker" 1 smoke_marks
expect "control: the unguarded press landed while the card was closing" moving popup_motion_state summon-input-control
expect "the probe drops the input-control copy" ok ipc smoke popupDrop summon-input-control
expect_poll "the input-control copy's panel leaves the build records" absent ipc smoke readInstance panel acme.surfaces opened
expect "the probe builds the item-mask popup copy" ok ipc smoke popupLoad summon-mask-control "$summon_mask_copy" "bar:$screen_name" acme.surfaces '{"pluginId":"acme.surfaces","kind":"panel","request":{"anchor":"@instance","anchored":true,"payloadJson":"{}"}}'
expect "the item-mask copy's panel takes a payload" '' ipc smoke invokeInstance panel acme.surfaces open '{}'
expect_poll "the item-mask copy reaches rest" rest popup_motion_state summon-mask-control
expect "the item-mask copy's bottom-edge marker press is sent" ok popup_marker_press
expect_poll "control: a mask mapped through the slide dismisses the card on a bottom-edge press" false ipc smoke popupRead summon-mask-control visible
expect "the probe drops the item-mask copy" ok ipc smoke popupDrop summon-mask-control
expect_poll "the item-mask copy's panel leaves the build records" absent ipc smoke readInstance panel acme.surfaces opened
# A card stopped half way through its close fades as one image: the
# swatch's white child matches the white fill under it. The control, faded
# item by item, shows the child lighter, as the light theme's chips were.
for fade in "summon-fade:$summon_fade_copy:one:popup_swatch_fade" "summon-fade-control:$summon_fade_control:patch:popup_swatch_patch"; do
  IFS=: read -r fade_name fade_file fade_want fade_read <<<"$fade"
  expect "the probe builds the $fade_name copy" ok ipc smoke popupLoad "$fade_name" "$fade_file" "bar:$screen_name" acme.surfaces '{"pluginId":"acme.surfaces","kind":"panel","request":{"anchor":"@instance","anchored":true,"payloadJson":"{}"}}'
  expect "the $fade_name copy's panel takes a payload" '' ipc smoke invokeInstance panel acme.surfaces open '{}'
  expect_poll "the $fade_name copy reaches rest" rest popup_motion_state "$fade_name"
  render expect_poll "the $fade_name copy's swatch reads white at rest" rest popup_swatch_fade
  expect "the $fade_name copy stops its close half way" ok ipc smoke popupCall "$fade_name" holdHalfway
  expect "the $fade_name copy holds its close at progress 0.5" 0.5 ipc smoke popupRead "$fade_name" motionProgress
  [[ $fade_want == one ]] && fade_label="half way through the close, the swatch's child fades with its fill" || fade_label="control: faded item by item, the swatch's child stands lighter than its fill"
  render expect_poll "$fade_label" "$fade_want" "$fade_read"
  expect "the $fade_name copy finishes its close" ok ipc smoke popupCall "$fade_name" finishDismiss
  expect_poll "the $fade_name copy releases its popup" false ipc smoke popupRead "$fade_name" visible
  expect "the probe drops the $fade_name copy" ok ipc smoke popupDrop "$fade_name"
  expect_poll "the $fade_name copy's panel leaves the build records" absent ipc smoke readInstance panel acme.surfaces opened
done
printf '%s\n' '{"schemaVersion":1,"name":"surface-motion-off","tokens":{"motion":{"scale":0}}}' >"$surface_motion_theme.tmp"
mv -T -- "$surface_motion_theme.tmp" "$surface_motion_theme"
expect_poll "motion scale 0 stills the flyout duration" 0 ipc smoke themeValue motion.flyout.travel.duration
expect "the widget opens a panel for the motion-off host close" ok ipc smoke invokeInstance "bar:$screen_name" acme.surfaces summonPayload "{\"closeMarker\":\"$sandbox/closed-by-motion-off\"}"
expect "the motion-off host panel opens at once" 1 ipc smoke readInstance panel acme.surfaces opened
expect "IPC hide closes immediately when motion is off" ok ipc shell hide panel acme.surfaces
expect_poll "motion off called close() before the immediate destroy" yes marker "$sandbox/closed-by-motion-off"
expect "motion off destroys the host panel at once" absent ipc smoke readInstance panel acme.surfaces opened
expect "the probe builds the SummonPopup copy for motion off" ok ipc smoke popupLoad summon-motion-off "$repo/shell/Hosts/SummonPopup.qml" "bar:$screen_name" acme.surfaces '{"pluginId":"acme.surfaces","kind":"panel","request":{"anchor":"@instance","anchored":true,"payloadJson":"{}"}}'
expect "the motion-off copy's panel takes a payload" '' ipc smoke invokeInstance panel acme.surfaces open '{}'
expect_poll "the motion-off copy is shown before its motion is read" true ipc smoke popupRead summon-motion-off visible
expect "the motion-off copy opens at rest" rest popup_motion_state summon-motion-off
expect "the motion-off copy starts closing" ok ipc smoke popupCall summon-motion-off requestDismiss
expect "motion scale 0 closes the copy at once" false ipc smoke popupRead summon-motion-off visible
expect "the probe drops the motion-off copy" ok ipc smoke popupDrop summon-motion-off
expect_poll "the motion-off copy's panel leaves the build records" absent ipc smoke readInstance panel acme.surfaces opened
if [[ $surface_motion_had_theme == true ]]; then
  cp -- "$sandbox/surface-motion-theme.json" "$surface_motion_theme.tmp"
  mv -T -- "$surface_motion_theme.tmp" "$surface_motion_theme"
else
  rm -f -- "$surface_motion_theme"
fi
expect_poll "the original flyout motion duration returns after the motion check" 100 ipc smoke themeValue motion.flyout.travel.duration

# An anchored surface takes a focus grab, so a click outside it closes it
# and calls the plugin's close(). The clicks go through the nested
# compositor's virtual pointer. The first click lands on the widget itself,
# as a user's would before its menu opens.
#
# Control: a SummonPopup copy without the grab, written beside the shipped
# file and built under the same widget as the host builds an anchored
# panel, stays open through the click that closes the menu. The shell
# reads both popups' events on one connection in order, so once the menu
# has closed the copy has had any dismissal the same click brought.
expect "the probe builds the SummonPopup copy without Escape" ok ipc smoke popupLoad summon-noescape "$summon_noescape" "bar:$screen_name" acme.surfaces '{"pluginId":"acme.surfaces","kind":"panel","request":{"anchor":"@instance","anchored":true,"payloadJson":"{}"}}'
expect "the no-Escape copy's panel takes a payload" '' ipc smoke invokeInstance panel acme.surfaces open '{}'
expect_poll "the no-Escape copy is shown before Escape" true ipc smoke popupRead summon-noescape visible
type_keys -k Escape || fail "sending Escape to the no-Escape copy failed"
expect_poll "control: the no-Escape copy stays open" true ipc smoke popupRead summon-noescape visible
expect "the probe drops the no-Escape copy" ok ipc smoke popupDrop summon-noescape
expect_poll "the no-Escape copy's panel leaves the build records" absent ipc smoke readInstance panel acme.surfaces opened

click_centre "bar:$screen_name" acme.surfaces || fail "the click on the widget failed"
expect "the probe builds the SummonPopup copy without the grab" ok ipc smoke popupLoad summon-nograb "$summon_copy" "bar:$screen_name" acme.surfaces '{"pluginId":"acme.surfaces","kind":"panel","request":{"anchor":"@instance","anchored":true,"payloadJson":"{}"}}'
expect_poll "the grabless copy has built its panel" 0 ipc smoke readInstance panel acme.surfaces opened
expect "the grabless copy's panel takes a payload" '' ipc smoke invokeInstance panel acme.surfaces open '{}'
expect_poll "the grabless copy is shown" true ipc smoke popupRead summon-nograb visible
expect "the widget opens a menu with a close marker" ok ipc smoke invokeInstance "bar:$screen_name" acme.surfaces menuHere "{\"closeMarker\":\"$sandbox/closed-by-click\"}"
expect_poll "the menu is open before the outside click" 1 ipc smoke readInstance menu acme.surfaces opened
click "$((mon_w / 2))" "$((mon_h / 2))" || fail "the click outside the menu failed"
expect_poll "the outside click called the menu's close()" yes marker "$sandbox/closed-by-click"
expect "the outside click leaves the grabless copy shown" true ipc smoke popupRead summon-nograb visible
expect "the probe drops the grabless copy" ok ipc smoke popupDrop summon-nograb
expect_poll "the grabless copy's panel leaves the build records" absent ipc smoke readInstance panel acme.surfaces opened
expect_poll "the outside click removed the menu from the build records" absent ipc smoke readInstance menu acme.surfaces opened
expect "the widget opens an anchored panel" ok ipc smoke invokeInstance "bar:$screen_name" acme.surfaces summonHere ''
expect_poll "the panel is open before the outside click" 1 ipc smoke readInstance panel acme.surfaces opened
click "$((mon_w / 2))" "$((mon_h / 2))" || fail "the click outside the panel failed"
expect_poll "the outside click closes an anchored panel too" absent ipc smoke readInstance panel acme.surfaces opened

expect "the probe builds the SummonPopup copy without the forced commit" ok ipc smoke popupLoad summon-no-commit "$summon_no_commit" "bar:$screen_name" acme.surfaces '{"pluginId":"acme.surfaces","kind":"panel","request":{"anchor":"@instance","anchored":true,"payloadJson":"{}"}}'
expect "the no-commit copy's panel takes a payload" '' ipc smoke invokeInstance panel acme.surfaces open '{}'
expect_poll "the no-commit copy is shown" true ipc smoke popupRead summon-no-commit visible
expect "the no-commit copy disables its forced commit after the first frame" ok ipc smoke popupCall summon-no-commit disableCommit
install_tail_widget
expect_poll "the re-added tail widget puts the widget back at its rest x" "$flyout_first_rest_x" flyout_widget_x
flyout_rest_x="$flyout_first_rest_x"
# The control runs the neighbour-grows check, the case the commit request
# after the bar's polish exists for. A copy whose marker the screen does
# not show fails that check too, so an absent marker is not the failure
# the control wants.
flyout_follow_control() {
  local failed
  failed="$(failures=0 behaviour_failures=0; flyout_grow_check >"$sandbox/flyout-follow-control.log"; echo "$failures")"
  if grep -q 'after its neighbour grows: got marker=absent ' "$sandbox/flyout-follow-control.log"; then echo marker-absent; else echo "$failed"; fi
}
expect "control: a popup without the forced commit fails the same compositor follow assertion" 1 flyout_follow_control
sed 's/^/  CONTROL  /' "$sandbox/flyout-follow-control.log"
remove_tail_widget
expect "the probe drops the no-commit copy" ok ipc smoke popupDrop summon-no-commit
expect_poll "the no-commit copy's panel leaves the build records" absent ipc smoke readInstance panel acme.surfaces opened

# Replacing an open plugin runs open() on the replacement. A refusal must
# remove its surface just as a refusal during the first summon does.
expect "the panel opens before its source changes" ok ipc shell summon panel acme.surfaces '{}'
cp -- "$home/.config/vgshell/plugins/acme.surfaces/Summoned.qml" "$sandbox/Summoned.good"
python3 - "$home/.config/vgshell/plugins/acme.surfaces/Summoned.qml" <<'PYEDIT'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
old = 'if (payload.fail === true)'
assert s.count(old) == 1
p.write_text(s.replace(old, 'if (true)'))
PYEDIT
rescan "the changed open plugin is rescanned"
expect_poll "a replacement whose open throws is removed" absent ipc smoke readInstance panel acme.surfaces opened
expect_poll "the refused replacement leaves no panel surface" 0 layer_count vgs:panel
mv -T -- "$sandbox/Summoned.good" "$home/.config/vgshell/plugins/acme.surfaces/Summoned.qml"
rescan "the repaired surface plugin is rescanned"

modal_focus_state() { ipc smoke popupRead focus-title-modal evidence; }
modal_focus_key() { modal_focus_state | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get(sys.argv[1])))' "$1"; }
modal_title_space() { modal_focus_state | py_reply 'import json,sys; value=json.load(sys.stdin); print(value.get("loaded") is True and value.get("card") is True and value.get("gap") == value.get("titleSpace") and value.get("gap", 0) > 0)'; }
expect "the actual ModalDialog fixture opens" ok ipc smoke popupLoad focus-title-modal "$surf/ModalFocus.qml" "bar:$screen_name" acme.surfaces '{}'
expect_poll "the actual ModalDialog takes initial focus" true modal_focus_key focused
expect "the actual ModalDialog opens without a ring" false modal_focus_key ring
expect_poll "ModalDialog leaves the title-space after its title and description" True modal_title_space
type_keys -k Tab || fail "Tab in the actual ModalDialog failed"
expect_poll "Tab shows the actual ModalDialog ring" true modal_focus_key ring
expect "the actual ModalDialog removes its description" ok ipc smoke popupCall focus-title-modal noDescription
expect_poll "ModalDialog leaves the title-space after a bare title" True modal_title_space
expect "the actual ModalDialog fixture closes" ok ipc smoke popupDrop focus-title-modal
expect_poll "the actual ModalDialog surface closes" 0 layer_count vgs:dialog

expect "the panel opens again for the disable check" ok ipc smoke invokeInstance "bar:$screen_name" acme.surfaces summonHere ''

expect "a background is not summonable" "refused: not-summonable=background" ipc shell summon background acme.surfaces '{}'
expect "a plugin without the kind is refused" "refused: kind=panel id=acme.tick" ipc shell summon panel acme.tick '{}'
expect "an unknown plugin is refused" "unknown: acme.nope" ipc shell summon panel acme.nope '{}'
expect "re-summoning with a close marker is allowed" ok ipc shell summon panel acme.surfaces "{\"closeMarker\":\"$sandbox/closed-by-disable\"}"
expect "disabling the hosts fixture is allowed" ok ipc shell setPluginEnabled acme.surfaces false
expect_poll "disabling closes its open panel" 0 layer_count vgs:panel
expect_poll "disabling called the panel's close()" yes marker "$sandbox/closed-by-disable"
expect_poll "disabling removes the background surface" 0 layer_count vgs:background
expect "a disabled plugin is not summoned" "refused: disabled=acme.surfaces" ipc shell summon panel acme.surfaces '{}'
if copy_tree host-close-motion-control \
  && edit_tree host-close-motion-control shell/Hosts/SummonHost.qml 'if (PluginLogic.hasOwn(closers, id)) {' 'if (false && PluginLogic.hasOwn(closers, id)) {'; then
  printf '%s\n' '{"schemaVersion":1,"name":"surface-motion-control","tokens":{"motion":{"scale":4}}}' >"$surface_motion_theme.tmp"
  mv -T -- "$surface_motion_theme.tmp" "$surface_motion_theme"
  stop_shell
  start_shell "$sandbox/tree-host-close-motion-control" "$sandbox/host-close-motion-control.log" || fail "the host close motion control shell starts"
  expect "the host close control enables its fixture" ok ipc shell setPluginEnabled acme.surfaces true
  expect "the host close control sees slowed flyout motion" 400 ipc smoke themeValue motion.flyout.travel.duration
  geometry read_bar_settled "the host close control bar has settled before its widget panel opens"
  expect_poll "the host close control widget is laid out before its panel opens" true acme_widget_laid_out
  expect_poll "the host close control widget has drawn before its panel opens" drawn ipc smoke windowDrawn "bar:$screen_name" acme.surfaces
  click_centre "bar:$screen_name" acme.surfaces || fail "the host close control widget receives input before its panel opens"
  expect "the host close control opens the widget panel" ok ipc smoke invokeInstance "bar:$screen_name" acme.surfaces summonHere ''
  expect_poll "the host close control panel opens" 1 ipc smoke readInstance panel acme.surfaces opened
  expect "the host close control hides the widget panel" ok ipc shell hide panel acme.surfaces
  host_close_motion_control() { (failures=0 behaviour_failures=0; expect "a host close keeps the panel instance during motion" 1 ipc smoke readInstance panel acme.surfaces opened >"$sandbox/host-close-motion-control.out"; echo "$failures"); }
  expect "control: immediate host drop fails the close-motion assertion" 1 host_close_motion_control
  sed 's/^/  CONTROL  /' "$sandbox/host-close-motion-control.out"
  stop_shell
  if [[ $surface_motion_had_theme == true ]]; then
    cp -- "$sandbox/surface-motion-theme.json" "$surface_motion_theme.tmp"
    mv -T -- "$surface_motion_theme.tmp" "$surface_motion_theme"
  else
    rm -f -- "$surface_motion_theme"
  fi
  start_shell "$repo" "$sandbox/host-close-motion-restored.log" || fail "the shell starts after the host close motion control"
fi

# Must-fail control for initial focus: retain the focus call but restore a
# keyboard reason in a disposable tree. The same no-ring assertion fails.
copy_tree focus-keyboard-open
edit_tree focus-keyboard-open shell/Ui/foundation/KeyNavLogic.js \
  'owner.focusReason = Qt.OtherFocusReason;' \
  'owner.focusReason = Qt.TabFocusReason;'
edit_tree focus-keyboard-open shell/Ui/layout/Pane.qml \
  'readonly property real headerBodyGap: hasTitle && headerSlotImplicitHeight === 0 ? Theme.stack.titleSpace : gap' \
  'readonly property real headerBodyGap: gap'
stop_shell
start_shell "$sandbox/tree-focus-keyboard-open" "$sandbox/focus-keyboard-open.log" || fail "the initial keyboard reason control starts"
expect "the focus control enables its fixture" ok ipc shell setPluginEnabled acme.surfaces true
expect "the focus control opens its window" ok ipc shell summon window acme.surfaces '{}'
expect_poll "the focus control window maps" 1 window_count Surfaces
expect_poll "the focus control window holds the keyboard" true ipc smoke windowFocused window acme.surfaces
expect "the focus control repeats its open after activation" ok ipc shell summon window acme.surfaces '{}'
surface_no_ring() { expect "an opened window has no ring" '["Control", "Initial focus", false, false, true]' surface_focused window; }
surface_no_ring_control() { (failures=0 behaviour_failures=0; surface_no_ring >"$sandbox/focus-keyboard-open-control.log"; echo "$failures"); }
expect "control: restoring a keyboard reason at open fails the same no-ring assertion" 1 surface_no_ring_control
sed 's/^/  CONTROL  /' "$sandbox/focus-keyboard-open-control.log"
expect "the old-gap control opens the actual ModalDialog" ok ipc smoke popupLoad focus-title-modal "$surf/ModalFocus.qml" "bar:$screen_name" acme.surfaces '{}'
expect_poll "the old-gap control modal maps" true modal_focus_key focused
modal_gap_check() { expect "ModalDialog leaves the title-space after its title block" True modal_title_space; }
modal_gap_control() { (failures=0 behaviour_failures=0; modal_gap_check >"$sandbox/modal-old-gap-control.log"; echo "$failures"); }
expect "control: restoring the old gap fails the actual ModalDialog title-space assertion" 1 modal_gap_control
sed 's/^/  CONTROL  /' "$sandbox/modal-old-gap-control.log"
expect "the old-gap control closes the actual ModalDialog" ok ipc smoke popupDrop focus-title-modal
expect "the focus control window closes" ok ipc shell hide window acme.surfaces
expect "the focus control restores its disabled fixture" ok ipc shell setPluginEnabled acme.surfaces false
stop_shell
start_shell "$repo" "$sandbox/focus-open-restored.log" || fail "the focus control restores the shipped shell"

copy_tree focus-scope-leaf
edit_tree focus-scope-leaf shell/Ui/foundation/KeyNavLogic.js \
  'owner = focused;' \
  'owner = target;'
stop_shell
start_shell "$sandbox/tree-focus-scope-leaf" "$sandbox/focus-scope-leaf.log" || fail "the retained-scope control starts"
expect "the retained-scope control enables its fixture" ok ipc shell setPluginEnabled acme.surfaces true
expect "the retained-scope control opens its window" ok ipc shell summon window acme.surfaces '{}'
expect_poll "the retained-scope window maps" 1 window_count Surfaces
expect_poll "the retained-scope window holds the keyboard" true ipc smoke windowFocused window acme.surfaces
type_keys -k Tab -M shift -k Tab -m shift || fail "native scope-leaf navigation in the control failed"
expect_poll "the control's scope leaf holds keyboard focus" '["Control", "Initial focus", true, true, true]' surface_focused window
expect "the retained-scope control repeats its open" ok ipc shell summon window acme.surfaces '{}'
expect "control: removing only the leaf reset fails the repeated-open no-ring assertion" 1 surface_no_ring_control
sed 's/^/  CONTROL  /' "$sandbox/focus-keyboard-open-control.log"
expect "the retained-scope control closes its window" ok ipc shell hide window acme.surfaces
expect "the retained-scope control disables its fixture" ok ipc shell setPluginEnabled acme.surfaces false
stop_shell
start_shell "$repo" "$sandbox/focus-scope-restored.log" || fail "the retained-scope control restores the shipped shell"

copy_tree window-pane-request
edit_tree window-pane-request shell/Hosts/AppWindow.qml \
  'paneHeight(slot.instance)' \
  '0'
stop_shell
start_shell "$sandbox/tree-window-pane-request" "$sandbox/window-pane-request.log" || fail "the clipped source-row control starts"
expect "the clipped-row control enables its fixture" ok ipc shell setPluginEnabled acme.surfaces true
expect "the clipped-row control opens its titled window" ok ipc shell summon window acme.surfaces '{"sizing":true}'
expect_poll "the clipped-row control maps" 1 window_count Surfaces
surface_last_row_control() { (failures=0 behaviour_failures=0; surface_last_row_check >"$sandbox/window-pane-request-control.log"; echo "$failures"); }
expect "control: ignoring the Pane request fails the same last-row visibility assertion" 1 surface_last_row_control
sed 's/^/  CONTROL  /' "$sandbox/window-pane-request-control.log"
expect "the clipped-row control closes" ok ipc shell hide window acme.surfaces
expect "the clipped-row control disables its fixture" ok ipc shell setPluginEnabled acme.surfaces false
stop_shell
start_shell "$repo" "$sandbox/window-pane-request-restored.log" || fail "the clipped-row control restores the shipped shell"
