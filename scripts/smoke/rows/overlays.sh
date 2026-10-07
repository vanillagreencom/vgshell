# The overlay components, from a fixture bar widget holding a popover, a
# tooltip, a menu and a select, and a fixture panel with a select nested in
# a summoned surface, summoned too as an application window. Each overlay
# is a Qt window popup: it leaves the bar, takes keys through the nested
# seat, follows its anchor and closes on a press outside, on Escape and
# when its anchor hides; a select's list shows the hand over its entries.
# Popup rectangles are read through the popup's content item in the bar
# window's coordinates, the same coordinates a click takes, since the bar
# sits at the origin.
# The press outside closes each one through its focus grab: a copy of each
# without the grab, written beside the shipped file and built under the
# same widget, stays open through it. A press in the window the select sits
# in, which the grab hands to the shell, and Escape close its list, in an
# application window and in a bar flyout, through the DismissScope the
# three share: in the application window, a select copy whose scope takes
# the press without closing, and one whose scope drops Escape, stay open
# through the same press and key.
# A popover and a dialog in the summoned panel's popup cap their height at
# their share of the output; copies that find the output as the Qt window's
# own `screen` cap at the fallback.
# inputs: scripts/smoke/fixtures/plugins/acme.overlays/* shell/Ui/overlay/* shell/Ui/controls/Select.qml shell/Ui/controls/InputWidth.qml shell/Ui/feedback/Dialog.qml
set -euo pipefail
ov="$home/.config/vgshell/plugins/acme.overlays"
mkdir -p "$ov"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.overlays/." "$ov/"
python3 - "$ov/Widget.qml" <<'PYEDIT'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = '    function tipTargetGeometry() { return rect(target); }\n'
insert = '''    function menuGeometry() {
        if (!menu.opened) return "closed";
        const boxes = menu.items().filter(item => item.visible).map(item => JSON.parse(rect(item)));
        if (boxes.length === 0) return "items=0";
        const left = Math.min(...boxes.map(box => box[0]));
        const top = Math.min(...boxes.map(box => box[1]));
        const right = Math.max(...boxes.map(box => box[0] + box[2]));
        const bottom = Math.max(...boxes.map(box => box[1] + box[3]));
        return JSON.stringify([left, top, right - left, bottom - top]);
    }
    property int tipDelayRuns: 0
    readonly property bool tipResting: tip.resting
    onTipRestingChanged: {
        tipDelayProbe.stop();
        if (tipResting) tipDelayProbe.restart();
    }
    Timer { id: tipDelayProbe; interval: Theme.tooltip.delay; repeat: false; onTriggered: root.tipDelayRuns += 1 }
    function startTipDelayProbe() { tipDelayProbe.restart(); return "ok"; }
'''
assert text.count(needle) == 1, "tipTargetGeometry must occur once"
path.write_text(text.replace(needle, needle + insert, 1))
PYEDIT
rescan "rescan after adding the overlay fixture answers ok"
expect_poll "the overlay fixture is discovered" True plugin_known acme.overlays
expect_poll "enabling the overlay fixture is allowed" ok ipc shell setPluginEnabled acme.overlays true
ov_key="$(bar_key)"
expect_poll "the overlay widget is built in the bar" True record_exists acme.overlays
ovw() { ipc smoke invokeInstance "$ov_key" acme.overlays "$1" ''; }
ovr() { ipc smoke readInstance "$ov_key" acme.overlays "$1"; }
tooltip_resting() { ipc smoke readDescendant "$ov_key" acme.overlays Tooltip resting; }
rect() { python3 -c 'import json,sys; print(*json.loads(sys.argv[1]))' "$1"; }
centre_of() { python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2), int(y+h/2))' "$1"; }
monitor_logical_size() { hypr -j monitors | py_reply 'import json,sys; m=json.load(sys.stdin)[0]; print(round(m["width"] / m["scale"]), round(m["height"] / m["scale"]))'; }
outside_box_point() {
  local size
  size="$(monitor_logical_size)" || return
  python3 - "$1" $size <<'PY'
import json, sys
x, y, w, h = (float(v) for v in json.loads(sys.argv[1]))
mw, mh = (float(v) for v in sys.argv[2:4])
candidates = []
if x + w < mw:
    candidates.append(((x + w + mw - 1) / 2, y + h / 2))
if x > 0:
    candidates.append((x / 2, y + h / 2))
if y + h < mh:
    candidates.append((x + w / 2, (y + h + mh - 1) / 2))
if y > 0:
    candidates.append((x + w / 2, y / 2))
for cx, cy in candidates:
    ix, iy = round(cx), round(cy)
    if 0 <= ix < mw and 0 <= iy < mh and not (x <= ix < x + w and y <= iy < y + h):
        print(ix, iy)
        sys.exit()
print("no-outside")
PY
}
press_outside_box() { local x y; read -r x y < <(outside_box_point "$1") && [[ $x =~ ^[0-9]+$ ]] && click "$x" "$y"; }
hover_outside_box() { local x y; read -r x y < <(outside_box_point "$1") && [[ $x =~ ^[0-9]+$ ]] && hover "$x" "$y"; }
bar_h="$(ovr barSize)"
popover_gap="$(ipc smoke themeValue popover.gap)" || { fail "Theme.popover.gap is readable for the popover placement"; exit 1; }
popover_fixture_width=160 # acme.overlays/Widget.qml sets Popover.width.
click_centre "$ov_key" acme.overlays || fail "the click on the overlay widget failed"

# A popover leaves the bar, takes focus and keys, and closes on Escape and
# on a press outside. Its top-left sits at the anchor's bottom-left, the
# theme's gap below.
expect "the widget opens its popover" ok ovw openPopover
expect_poll "the popover is open" true ovr popoverOpen
placed_under() { python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); ax,ay,aw,ah=json.loads(sys.argv[2]); gap,width,bar_h=(int(v) for v in sys.argv[3:6]); print("placed" if (x, y) == (ax, ay + ah + gap) and h > bar_h and w == width else "popover=%s anchor=%s gap=%s width=%s" % (sys.argv[1], sys.argv[2], gap, width))' "$(ovw popoverGeometry)" "$(ovw anchorGeometry)" "$popover_gap" "$popover_fixture_width" "$bar_h"; }
render expect_poll "the popover sits under its anchor and is taller than the bar" placed placed_under
expect "the popover's input takes focus" ok ovw focusInput
expect_poll "the input holds active focus" true ovr inputFocus
type_keys ab || fail "typing into the popover failed"
expect_poll "typed keys reach the popover's input" '"ab"' ovr typed
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape closes the popover" false ovr popoverOpen
expect "the widget opens its popover again" ok ovw openPopover
expect_poll "the popover is open before the outside press" true ovr popoverOpen
press_outside_box "$(ovw popoverGeometry)" || fail "the click outside the popover failed"
expect_poll "a press outside closes the popover" false ovr popoverOpen

# The popover follows its anchor and closes when the anchor hides.
expect "the widget opens its popover for the anchor rows" ok ovw openPopover
expect_poll "the popover is open before the anchor moves" true ovr popoverOpen
expect "moving the anchor is allowed" ok ovw moveAnchor
render expect_poll "the popover follows its moved anchor" placed placed_under
expect "hiding the anchor is allowed" ok ovw hideAnchor
expect_poll "hiding the anchor closes its popover" false ovr popoverOpen
expect "showing the anchor again is allowed" ok ovw showAnchor

# A tooltip opens on hover after the delay, closes when the pointer leaves,
# and stays closed while a popover is open.
read -r tx ty < <(centre_of "$(ovw tipTargetGeometry)")
hover "$tx" "$ty" || fail "hovering the tooltip target failed"
expect_poll "hovering the target opens its tooltip" true ovr tooltipOpen
hover_outside_box "$(ovw tipTargetGeometry)" || fail "moving the pointer away failed"
expect_poll "leaving the target closes its tooltip" false ovr tooltipOpen
hover "$tx" "$ty" || fail "hovering the target under the popover failed"
expect_poll "the tooltip target processed the hover before the popover" true tooltip_resting
expect "the widget opens its popover beside the tooltip target" ok ovw openPopover
expect_poll "the popover is open under the hover" true ovr popoverOpen
tip_delay_before="$(ovr tipDelayRuns)" || fail "the tooltip delay count is readable before the blocked hover"
expect "the tooltip delay probe starts under the popover" ok ovw startTipDelayProbe
expect_poll "the tooltip delay ran out under the popover" "$((tip_delay_before + 1))" ovr tipDelayRuns
expect "a tooltip does not open while a popover is open" false ovr tooltipOpen
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape closes the popover under the hover" false ovr popoverOpen
hover_outside_box "$(ovw tipTargetGeometry)" || fail "moving the pointer away failed"

# A menu takes the arrow keys and Enter, and Escape closes it.
expect "the widget opens its menu" ok ovw openMenu
expect_poll "the menu is open" true ovr menuOpen
type_keys -k Down -k Return || fail "sending keys to the menu failed"
# A menu opens with its first reachable entry highlighted, so one Down key
# reaches the second entry.
expect_poll "the keys trigger the second entry" 1 ovr triggered
expect_poll "a triggered entry closes the menu" false ovr menuOpen
expect "the widget opens its menu again" ok ovw openMenu
expect_poll "the menu is open before Escape" true ovr menuOpen
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape closes the menu" false ovr menuOpen

# A select chooses by pointer and by keyboard. The list's rectangle is read
# through the list's own item, in the bar window's coordinates.
expect "the select starts on the first entry" 0 ovr selected
expect "the widget opens its select" ok ovw openSelect
expect_poll "the select list is open" true ovr selectOpen
read -r lx ly lw lh < <(rect "$(ovw selectListGeometry)")
# The list is its own popup surface; its entries show the hand too.
expect_cursor_at "an entry of the select's popup list shows the hand" pointer "$((lx + lw / 2))" "$((ly + lh / 2))"
click "$((lx + lw / 2))" "$((ly + lh / 2))" || fail "the click on the middle entry failed"
expect_poll "a click on the middle entry chooses it" 1 ovr selected
expect_poll "a choice closes the list" false ovr selectOpen
expect "the widget opens its select for the keys" ok ovw openSelect
expect_poll "the select list is open for the keys" true ovr selectOpen
type_keys -k Down -k Return || fail "sending keys to the select failed"
expect_poll "the keys choose the next entry" 2 ovr selected
expect_poll "the keyboard choice closes the list" false ovr selectOpen

# Every flyout closes on a press outside it, as the popover does above.
expect "the widget opens its menu for the outside press" ok ovw openMenu
expect_poll "the menu is open before the outside press" true ovr menuOpen
press_outside_box "$(ovw menuGeometry)" || fail "the click outside the menu failed"
expect_poll "a press outside closes the menu" false ovr menuOpen
expect "the widget opens its select for the outside press" ok ovw openSelect
expect_poll "the select list is open before the outside press" true ovr selectOpen
press_outside_box "$(ovw selectListGeometry)" || fail "the click outside the select failed"
expect_poll "a press outside closes the select list" false ovr selectOpen

# Controls: a popover, a menu and a select copied without their grab and
# built under the widget stay open through the press outside that closes
# the grabbing popover. The shell reads every popup's events on one
# connection in order, so once the popover has closed each copy has had
# any dismissal the same press brought. Every copy is written before the
# first is built: the type loader keeps the listing of a directory it has
# read and refuses a file written after it as a case mismatch. A copy is no member of qs.Ui and sees
# the module's internal types only through their directories, so the
# select's copy sits beside AnchorTracker in overlay/ and imports the
# directories of ScrollBar and InputWidth, which its list and control use.
declare -A nograb_copy=(
  [popover]="$repo/shell/Ui/overlay/Popover.qml|$repo/shell/Ui/overlay/PopoverNoGrab.qml"
  [menu]="$repo/shell/Ui/overlay/Menu.qml|$repo/shell/Ui/overlay/MenuNoGrab.qml"
  [select]="$repo/shell/Ui/controls/Select.qml|$repo/shell/Ui/overlay/SelectNoGrab.qml"
)
# name -> the line of DismissScope the copy plants a defect in, and what
# replaces it.
declare -A scope_defect=(
  [NoCatch]='onPressed: scope.popup.visible = false|onPressed: {}'
  [NoEscape]='Keys.onEscapePressed: popup.visible = false|Keys.onEscapePressed: {}'
)
for defect in NoCatch NoEscape; do
  python3 - "$repo/shell/Ui/overlay/DismissScope.qml" "$repo/shell/Ui/overlay/DismissScope$defect.qml" "${scope_defect[$defect]}" "$repo/shell/Ui/controls/Select.qml" "$repo/shell/Ui/overlay/Select$defect.qml" "$defect" <<'PYEDIT'
import pathlib, sys
scope, scope_copy, defect, select, select_copy, name = sys.argv[1:]
old, new = defect.split("|")
text = pathlib.Path(scope).read_text()
assert text.count(old) == 1, "the defect's line must occur once in DismissScope.qml"
if name == "NoCatch":
    new = "onPressed: { scope.smokePressed(); }"
    signal = "    signal smokePressed()\n"
elif name == "NoEscape":
    new = "Keys.onEscapePressed: { scope.smokeEscaped(); }"
    signal = "    signal smokeEscaped()\n"
else:
    signal = ""
text = text.replace(old, new)
if signal:
    marker = "    required property Item anchor\n"
    assert text.count(marker) == 1, "the DismissScope anchor must occur once"
    text = text.replace(marker, marker + signal, 1)
pathlib.Path(scope_copy).write_text(text)
text = pathlib.Path(select).read_text()
handler = "                onSmokePressed: root.smokeMarks += 1\n" if name == "NoCatch" else "                onSmokeEscaped: root.smokeMarks += 1\n"
for line, replacement in (("import qs.Ui\n", "import qs.Ui\nimport \"../layout\"\nimport \"../controls\" as Controls\n"), ("    InputWidth { target: root }", "    Controls.InputWidth { target: root }"), ("    property string emptyText: \"\"\n", "    property string emptyText: \"\"\n    property int smokeMarks: 0\n"), ("        DismissScope {\n", "        DismissScope" + name + " {\n" + handler)):
    assert text.count(line) == 1, line + " must occur once in Select.qml"
    text = text.replace(line, replacement)
pathlib.Path(select_copy).write_text(text)
PYEDIT
done
for name in popover menu select; do
  python3 - "${nograb_copy[$name]%%|*}" "${nograb_copy[$name]##*|}" "$name" <<'PYEDIT'
import pathlib, sys
source, target, name = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
text = source.read_text()
assert text.count("        grabFocus: true\n") == 1, "the grab must occur once in " + source.name
text = text.replace("        grabFocus: true\n", "        grabFocus: false\n")
if name == "select":
    assert text.count("import qs.Ui\n") == 1, "the qs.Ui import must occur once in " + source.name
    text = text.replace("import qs.Ui\n", "import qs.Ui\nimport \"../layout\"\nimport \"../controls\" as Controls\n")
    assert text.count("    InputWidth { target: root }") == 1, "the width helper must occur once in " + source.name
    text = text.replace("    InputWidth { target: root }", "    Controls.InputWidth { target: root }")
target.write_text(text)
PYEDIT
done
# The height caps' copies, written with the others: a popover that reads
# its cap back, and a popover and a dialog that find their output as the
# Qt window's own `screen`, which a Quickshell window does not have.
# feedback/ was read at startup, so Qt's cached listing cannot see a new
# Dialog file there. Its control uses a fresh directory instead.
dialog_controls="$repo/shell/Ui/feedback/overlays-controls"
mkdir "$dialog_controls"
python3 - "$repo/shell/Ui/overlay/Popover.qml" "$repo/shell/Ui/overlay" "$repo/shell/Ui/feedback/Dialog.qml" "$dialog_controls" <<'PYEDIT'
import pathlib, sys
popover, overlay, dialog, dialog_controls = map(pathlib.Path, sys.argv[1:])
old_read = """    function windowScreen(item) {
        const window = item === null || item === undefined ? null : item.Window.window;
        return window === null || window === undefined || window.screen === null || window.screen === undefined ? null : window.screen;
    }
"""
def planted(text, call, anchor):
    assert text.count(call) == 1, call + " must occur once"
    assert text.count(anchor) == 1, anchor + " must occur once"
    return text.replace(call, call.replace("OverlayState.outputOf", "root.windowScreen")).replace(anchor, anchor + old_read)
text = popover.read_text()
marker = "    readonly property real availableHeight: screenHeight()\n"
assert text.count(marker) == 1, "the available height must occur once in Popover.qml"
text = text.replace(marker, marker + "    readonly property real smokeCap: pane.maximumHeight\n")
(overlay / "PopoverCap.qml").write_text(text)
(overlay / "PopoverOldRead.qml").write_text(planted(text, "OverlayState.outputOf(anchorItem)", marker))
text = dialog.read_text()
keynav = 'import "../foundation/KeyNavLogic.js" as KeyNavLogic\n'
assert text.count(keynav) == 1, "the KeyNavLogic import must occur once in Dialog.qml"
text = text.replace(keynav, 'import "../../foundation/KeyNavLogic.js" as KeyNavLogic\n')
(dialog_controls / "DialogOldRead.qml").write_text(planted(text, "OverlayState.outputOf(root)", "    property real availableHeight: 0\n"))
PYEDIT
# name -> [the member that opens it, the property that reads it open, its properties]
declare -A nograb_use=(
  [popover]='open opened {"width":160}'
  [menu]='open opened {}'
  [select]='openList listOpen {"width":40,"height":20,"model":["one","two"]}'
)
for name in popover menu select; do
  read -r opener reader props <<<"${nograb_use[$name]}"
  expect "the probe builds the $name copy without the grab" ok ipc smoke popupLoad "$name-nograb" "${nograb_copy[$name]##*|}" "$ov_key" acme.overlays "$props"
  expect "the $name copy opens" ok ipc smoke popupCall "$name-nograb" "$opener"
  expect_poll "the $name copy is open" true ipc smoke popupRead "$name-nograb" "$reader"
done
expect "the widget opens its popover beside the copies" ok ovw openPopover
expect_poll "the popover is open beside the copies" true ovr popoverOpen
press_outside_box "$(ovw popoverGeometry)" || fail "the click outside the copies failed"
expect_poll "the press outside closes the grabbing popover" false ovr popoverOpen
for name in popover menu select; do
  read -r opener reader props <<<"${nograb_use[$name]}"
  expect "the press outside leaves the $name copy without the grab open" true ipc smoke popupRead "$name-nograb" "$reader"
  expect "the probe drops the $name copy" ok ipc smoke popupDrop "$name-nograb"
done

# A press in the application window the select sits in closes its list, as
# Escape does, and the window stays open. The press lands in the window's
# corner, clear of the select and its list.
expect "the overlay fixture summons as a window" ok ipc shell summon window acme.overlays '{}'
expect_poll "the overlay window maps" 1 window_count Overlays
read -r wx wy ww _ < <(rect "$(one_window Overlays)")
expect "the window opens its select" ok ipc smoke invokeInstance window acme.overlays openSelect ''
expect_poll "the window's select list is open" true ipc smoke readInstance window acme.overlays selectOpen
click "$((wx + ww - 10))" "$((wy + 10))" || fail "the press in the window failed"
expect_poll "a press in the window closes the select list" false ipc smoke readInstance window acme.overlays selectOpen
expect "the window opens its select for Escape" ok ipc smoke invokeInstance window acme.overlays openSelect ''
expect_poll "the window's select list is open before Escape" true ipc smoke readInstance window acme.overlays selectOpen
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape closes the window's select list" false ipc smoke readInstance window acme.overlays selectOpen
expect "the window stays open through the press and Escape" 1 window_count Overlays
# The controls open one at a time: a second grabbing popup would end the
# first one's grab. Each reading waits a second, past the time the shipped
# list took to close.
copy_props='{"x":20,"y":70,"width":40,"height":20,"model":["one","two"]}'
expect "the probe builds the select copy without the catch" ok ipc smoke popupLoad select-NoCatch "$repo/shell/Ui/overlay/SelectNoCatch.qml" window acme.overlays "$copy_props"
expect "the select copy without the catch opens" ok ipc smoke popupCall select-NoCatch openList
expect_poll "the select copy without the catch is open" true ipc smoke popupRead select-NoCatch listOpen
click "$((wx + ww - 10))" "$((wy + 10))" || fail "the press in the window beside the copy failed"
expect_poll "the select copy without the catch processed the window press" 1 ipc smoke popupRead select-NoCatch smokeMarks
expect "the press in the window leaves the select copy without the catch open" true ipc smoke popupRead select-NoCatch listOpen
expect "the probe drops the select copy without the catch" ok ipc smoke popupDrop select-NoCatch
expect "the probe builds the select copy without Escape" ok ipc smoke popupLoad select-NoEscape "$repo/shell/Ui/overlay/SelectNoEscape.qml" window acme.overlays "$copy_props"
expect "the select copy without Escape opens" ok ipc smoke popupCall select-NoEscape openList
expect_poll "the select copy without Escape is open" true ipc smoke popupRead select-NoEscape listOpen
type_keys -k Escape || fail "sending Escape to the copy failed"
expect_poll "the select copy without Escape processed Escape" 1 ipc smoke popupRead select-NoEscape smokeMarks
expect "Escape leaves the select copy without Escape open" true ipc smoke popupRead select-NoEscape listOpen
expect "the probe drops the select copy without Escape" ok ipc smoke popupDrop select-NoEscape
expect "hiding the overlay window is allowed" ok ipc shell hide window acme.overlays

# A select inside a summoned panel opens its list over the panel's popup
# and the panel stays open through the choice.
expect "the widget summons the fixture panel" ok ovw summonHere
expect_poll "the panel is open" 1 ipc smoke readInstance panel acme.overlays opened
expect "the panel opens its select" ok ipc smoke invokeInstance panel acme.overlays openSelect ''
expect_poll "the nested list is open" true ipc smoke readInstance panel acme.overlays selectOpen
read -r nx ny nw nh < <(rect "$(ipc smoke invokeInstance panel acme.overlays selectListGeometry '')")
click "$((nx + nw / 2))" "$((ny + nh / 2))" || fail "the click on the nested entry failed"
expect_poll "the nested list chooses on click" 1 ipc smoke readInstance panel acme.overlays selected
expect "the panel stays open through the choice" 1 ipc smoke readInstance panel acme.overlays opened
# A press in the flyout beside the select closes its list, as Escape does,
# and the flyout stays open through both.
read -r px py pw ph < <(rect "$(ipc smoke invokeInstance panel acme.overlays geometry '')")
expect "the panel opens its select for the press" ok ipc smoke invokeInstance panel acme.overlays openSelect ''
expect_poll "the nested list is open before the press" true ipc smoke readInstance panel acme.overlays selectOpen
click "$((px + pw - 10))" "$((py + ph - 10))" || fail "the press in the flyout failed"
expect_poll "a press in the flyout closes the nested list" false ipc smoke readInstance panel acme.overlays selectOpen
expect "the panel opens its select for Escape" ok ipc smoke invokeInstance panel acme.overlays openSelect ''
expect_poll "the nested list is open before Escape" true ipc smoke readInstance panel acme.overlays selectOpen
type_keys -k Escape || fail "sending Escape to the nested list failed"
expect_poll "Escape closes the nested list" false ipc smoke readInstance panel acme.overlays selectOpen
expect "the flyout stays open through the press and Escape" 1 ipc smoke readInstance panel acme.overlays opened
# A popover and a dialog in the flyout's popup cap their height at their
# share of the output's height, read from Hyprland. Their copies with the
# Qt window's `screen` find no output and cap at the fallback; an output
# whose share equals the fallback would read `share` there and fail.
read -r _ out_h < <(monitor_logical_size)
cap_reads() { # COPY PROPERTY SHARE: `share` when the copy's cap is that share of the output's height, `fallback` when it is the fallback
  local cap share fallback
  cap="$(ipc smoke popupRead "$1" "$2")" || return
  share="$(ipc smoke readInstance panel acme.overlays "$3")" || return
  fallback="$(ipc smoke readInstance panel acme.overlays fallbackCap)" || return
  python3 - "$cap" "$share" "$out_h" "$fallback" <<'PY'
import math, sys
values = []
for name, raw in zip(("cap", "share", "height", "fallback"), sys.argv[1:]):
    try:
        value = float(raw)
    except ValueError:
        print("cap-read-unavailable=" + name + ":" + (raw or "empty"))
        sys.exit()
    if not math.isfinite(value):
        print("cap-read-unavailable=" + name + ":non-finite")
        sys.exit()
    values.append(value)
cap, share, height, fallback = values
print("share" if abs(cap - share * height) < 1 else "fallback" if cap == fallback else "cap=%g want=%g" % (cap, share * height))
PY
}
expect "the probe builds the popover copy that reads its cap" ok ipc smoke popupLoad popover-cap "$repo/shell/Ui/overlay/PopoverCap.qml" panel acme.overlays '{"width":160}'
expect "the probe builds the popover copy with the window's screen" ok ipc smoke popupLoad popover-old "$repo/shell/Ui/overlay/PopoverOldRead.qml" panel acme.overlays '{"width":160}'
expect "the probe builds a dialog in the flyout" ok ipc smoke popupLoad dialog-cap "$repo/shell/Ui/feedback/Dialog.qml" panel acme.overlays '{"width":240}'
expect "the probe builds the dialog copy with the window's screen" ok ipc smoke popupLoad dialog-old "$dialog_controls/DialogOldRead.qml" panel acme.overlays '{"width":240}'
expect_poll "a popover in a popup caps at its share of the output" share cap_reads popover-cap smokeCap popoverShare
expect "the popover copy with the window's screen caps at the fallback" fallback cap_reads popover-old smokeCap popoverShare
expect_poll "a dialog in a popup caps at its share of the output" share cap_reads dialog-cap maximumHeight dialogShare
expect "the dialog copy with the window's screen caps at the fallback" fallback cap_reads dialog-old maximumHeight dialogShare
dialog_share_control() {
  (failures=0 behaviour_failures=0
   expect "a dialog in a popup caps at its share of the output" share cap_reads dialog-old maximumHeight dialogShare >"$sandbox/overlays-dialog-share-control.log"
   echo "$failures")
}
expect "control: reading the window's screen fails the dialog output share check" 1 dialog_share_control
expect "a missing dialog cap has a named reason" cap-read-unavailable=cap:absent cap_reads dialog-absent maximumHeight dialogShare
for name in popover-cap popover-old dialog-cap dialog-old; do
  expect "the probe drops the $name copy" ok ipc smoke popupDrop "$name"
done
expect "hiding the panel is allowed" ok ipc shell hide panel acme.overlays

# Disabling the plugin with a popover open leaves no record and no error;
# the log row at the end holds the second half.
expect "the widget opens its popover before teardown" ok ovw openPopover
expect_poll "the popover is open before teardown" true ovr popoverOpen
expect "disabling the overlay fixture is allowed" ok ipc shell setPluginEnabled acme.overlays false
expect_poll "the disabled fixture leaves the build records" False record_exists acme.overlays
