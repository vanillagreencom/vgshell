# The gallery: the first-party window that draws every component. Summoned
# over IPC it maps one Hyprland window, holds every section and component
# it claims, draws the custom-emoji ImageText image and rejects an alt-only
# control copy through the shared grim pixel reader, shows the hand over an
# enabled control and the arrow over a disabled one, sends a system
# notification through its capability, which Notifications draws as a
# card, and takes its window down when hidden. Summoned again, it
# is read as every application window is (app_window_rows,
# scripts/smoke/app-window.sh), ending closed by Escape.
# inputs: shell/plugins/vgs.gallery/* shell/Ui/* shell/Core/Notifier.qml shell/plugins/vgs.notifications/* shell/Hosts/AppWindow.qml scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail
expect "the gallery summons over IPC" ok ipc shell summon window vgs.gallery '{}'
expect_poll "the gallery maps one window" 1 window_count "VGS Components"
expect "the gallery maps no layer surface" 0 layer_count vgs:panel
# Every component the module's qmldir lists is drawn, read back by type
# name; the headings have a size, so they show.
expect_poll "the gallery draws every component of the module" '[]' ipc smoke galleryMissing window vgs.gallery
# The key/value row, the device row and the level display draw with a
# size in each state the gallery shows: a form row with and without its
# message, a device row per badge (a battery, a low battery by its
# text, a level), and a level display read as a percentage, as Muted and
# as a device's name, each read back by type and text. The control
# flattens the first box, which the check names. `[]` is the pass.
gallery_drawn_rows=("FormRow|Natural scroll" "FormRow|Pointer speed" "Label|Overridden" "DeviceRow|Headphones" "DeviceRow|Mouse" "Badge|8%" "DeviceRow|Speaker" "LevelOsd|45%" "LevelOsd|Muted" "LevelOsd|Studio Display" "LevelSlider|60%" "LevelSlider|Muted")
gallery_drawn() {
  local boxes=() entry
  for entry in "${gallery_drawn_rows[@]}"; do boxes+=("$entry=$(ipc smoke shownWindowGeometry window vgs.gallery "${entry%%|*}" "${entry#*|}")"); done
  python3 - "${1:-}" "${boxes[@]}" <<'PY'
import json, sys
plant, rows = sys.argv[1] == "flat", sys.argv[2:]
out = []
for n, row in enumerate(rows):
    name, _, raw = row.partition("=")
    if not raw.startswith("["):
        out.append("%s=%s" % (name, raw)); continue
    box = json.loads(raw)
    if plant and n == 0: box[3] = 0
    if box[2] <= 0 or box[3] <= 0: out.append("%s.height=%s" % (name, box[3]))
print(json.dumps(out))
PY
}
gallery_drawn_planted() { gallery_drawn flat | py_reply 'import json,sys; print(json.load(sys.stdin) == ["FormRow|Natural scroll.height=0"])'; }
geometry expect_poll "the gallery draws its form rows, device rows, level displays and level sliders" '[]' gallery_drawn
expect "control: a form row drawn flat is named" True gallery_drawn_planted
expect "the form row draws its message as no chip" absent ipc smoke shownWindowGeometry window vgs.gallery Badge Overridden

# The Gallery's DeviceList owns movement; only its selected row takes a
# Tab stop. A reading is the focused item's type, the list's example name,
# a shown focus ring, and the list's selected row. The controls for a list
# that swallows movement or makes every row a Tab stop are the component's
# own, in scripts/qml-tests/tst_devicelist.qml.
device_focus_is() {
  local focus key
  focus="$(ipc smoke focused window vgs.gallery)" && key="$(ipc smoke readDescendant window vgs.gallery DeviceList currentKey)" || return 1
  python3 -c 'import json,sys
row=json.loads(sys.argv[1])
print(row[0]==sys.argv[3] and row[1]=="Device list" and all(row[2:]) and json.loads(sys.argv[2])==sys.argv[4])' "$focus" "$key" "$1" "$2"
}
expect "the device list's first row takes focus" focused ipc smoke focusExample window vgs.gallery "Device list"
expect_poll "the device list starts on Headphones" True device_focus_is DeviceRow Headphones
type_keys -k Down || fail "moving down the Gallery device list failed"
expect_poll "the device list navigator moves focus and the cursor to Mouse" True device_focus_is DeviceRow Mouse
type_keys -k End || fail "moving to the last Gallery device failed"
expect_poll "the device list navigator reaches Speaker" True device_focus_is DeviceRow Speaker
type_keys -k Home -k Down || fail "returning to the middle Gallery device failed"
expect_poll "the device list navigator returns to Mouse" True device_focus_is DeviceRow Mouse
type_keys -k Tab || fail "tabbing to the device overflow failed"
expect_poll "Tab reaches the current device's overflow" True device_focus_is IconButton Mouse
type_keys -k Tab || fail "tabbing past the device row failed"
expect_poll "Tab skips an unselected device row and reaches its action" True device_focus_is Button Mouse

# Pointer scrolling (docs/architecture/design-system.md § Pointer) on a plain Flickable a
# plugin declares, the gallery's slim list, brought into the window first:
# a mouse drag leaves it where it was and a wheel notch scrolls it. The
# control gives the
# list Qt's left-button drag back through the probe, and the same drag then
# scrolls it. The Tab tour below reads the window's keyboard reveal after.
slim_revealed() { [[ $(ipc smoke revealText window vgs.gallery ListItem "Slim 1") =~ ^[0-9.]+$ ]] && echo revealed; }
slim_kind() { ipc smoke viewHolding window vgs.gallery "Slim 1" | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps([v["type"], v["contentY"], v["acceptedButtons"]]))'; }
expect "the slim list is brought into the gallery's view" revealed slim_revealed
# A plain Flickable reads as its C++ class name.
expect "the slim list is a Flickable at its top that takes no mouse button" '["QQuickFlickable", 0, 0]' slim_kind
expect "a mouse drag on the slim list leaves it where it was" still view_pointer "window:VGS Components" window vgs.gallery "Slim 1" drag
expect "a wheel notch on the slim list scrolls it" moved view_pointer "window:VGS Components" window vgs.gallery "Slim 1" wheel
expect "control: the probe gives the slim list Qt's left-button drag" 0 ipc smoke setViewButtons window vgs.gallery "Slim 1" 1
expect "control: the same drag then scrolls the slim list" moved view_pointer "window:VGS Components" window vgs.gallery "Slim 1" drag
expect "the slim list takes no mouse button again" 1 ipc smoke setViewButtons window vgs.gallery "Slim 1" 0
# Touchpad scrolling (docs/architecture/design-system.md § Pointer) of a view inside a view:
# a two-finger swipe of 10 px of axis length over the slim list moves it
# as far as GTK
# moves a list and leaves the page that holds it where it was, to the
# pixel: a swipe's begin and end reach the page too, and Qt rounds a view's
# position there. The control turns the list's touchpad scroll off through
# the probe, and the same swipe then moves it Qt's one pixel per pixel.
tabs_revealed() { [[ $(ipc smoke revealText window vgs.gallery QQuickTabButton Installed) =~ ^[0-9.]+$ ]] && echo revealed; }
gallery_page_y() { ipc smoke viewHolding window vgs.gallery "Natural scroll" | py_reply 'import json,sys; v=json.load(sys.stdin); print(v["contentY"] if v["type"] == "ScrollArea" else "type=" + v["type"])'; }
slim_swipe() {
  local page answer after
  page="$(gallery_page_y)" || return 1
  answer="$(view_swipe "window:VGS Components" window vgs.gallery "Slim 1" 10)" || return 1
  after="$(gallery_page_y)" || return 1
  python3 -c 'import sys
try: moved = abs(float(sys.argv[2]) - float(sys.argv[1])) >= 1
except ValueError: print("page=" + sys.argv[1]); sys.exit()
print("page-moved" if moved else sys.argv[3])' "$page" "$after" "$answer"
}
expect "a two-finger swipe on the slim list moves it alone, as far as a GTK list" as-gtk slim_swipe
expect "control: the probe turns the slim list's touchpad scroll off" true ipc smoke setViewTouchpad window vgs.gallery "Slim 1" false
expect "control: the same swipe then moves the slim list one pixel per pixel" as-qt slim_swipe
expect "the slim list's touchpad scroll is on again" false ipc smoke setViewTouchpad window vgs.gallery "Slim 1" true
# A swipe across a view goes to the view under it (design-system.md
# § Pointer): the same swipe with the pointer over a tab strip, a list
# view that fits and stays
# interactive, scrolls the page that holds the strip. The pointer lies at
# the strip's right end, past its tabs, so it leaves the arrow for the
# cursor rows below. The slim list's swipe above is its control: a view
# that takes the deltas leaves the page.
tabs_swipe() {
  local strip page x y after
  strip="$(view_at_rest window vgs.gallery Installed)" || return 1
  [[ $strip == \{* ]] || { echo "strip=$strip"; return 0; }
  page="$(view_at_rest window vgs.gallery "Natural scroll")" || return 1
  [[ $page == \{* ]] || { echo "page=$page"; return 0; }
  read -r x y < <(at_centre "window:VGS Components" "$(python3 -c 'import json,sys; x, y, w, h = json.loads(sys.argv[1])["box"]; print(json.dumps([x + w - 8, y, 8, h]))' "$strip")") || return 1
  hover "$x" "$((y + 1))" || return 1
  swipe "$x" "$y" 10 || return 1
  # The view starts to move in the frame that takes the input.
  sleep 0.2
  after="$(view_at_rest window vgs.gallery "Natural scroll")" || return 1
  [[ $after == \{* ]] || { echo "page=$after"; return 0; }
  python3 -c 'import json,sys
strip, page, after = (json.loads(a) for a in sys.argv[1:4])
moved = after["contentY"] - page["contentY"]
print("page-moved" if strip["type"] == "QQuickListView" and page["type"] == "ScrollArea" and moved >= 1 else "strip=%s page=%s moved=%g" % (strip["type"], page["type"], moved))' "$strip" "$page" "$after"
}
expect "a tab strip is brought into the gallery's view" revealed tabs_revealed
expect "a two-finger swipe down over a tab strip scrolls the page that holds it" page-moved tabs_swipe
# Touchpad steps on a carousel: a swipe moves the rail as
# TouchpadScroll moves a view's content and steps one card per slice step of
# travel, so the cards a swipe steps fall as the rail's scale grows. The
# same swipe of 100 px down goes over a 60-card copy at the height of the
# Gallery's carousel, then over one twice as tall, whose slice step is
# twice as long: `as-rail` when the first steps at least four cards and the
# second half as many, within one. A rail that steps a card per notch of
# the swipe's angle steps both alike, `per-notch`. The control loads a copy
# of the carousel without its touchpad step, which reads the swipe by the
# notch, and the check refuses it. The pointer then goes back to where the
# tab strip's swipe left it, over the arrow the cursor rows below start on.
carousel_rest="$pointer_at"
mkdir -p "$repo/shell/Core/CarouselSwipeControl"
carousel_box='    readonly property var windowBox: { const at = mapToItem(null, 0, 0); return [at.x, at.y, width, height]; }'
printf 'import QtQuick\nimport qs.Ui\n\nCardCarousel {\n%s\n}\n' "$carousel_box" >"$repo/shell/Core/CarouselSwipeControl/SwipeRail.qml"
python3 - "$repo/shell/Ui/layout/CardCarousel.qml" "$repo/shell/Core/CarouselSwipeControl/NotchRail.qml" "$carousel_box" <<'PY'
from pathlib import Path
import json, sys
source, destination, box = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
text = source.read_text()
logic = source.with_name("TouchpadScrollLogic.js").as_uri()
for needle, replacement in [
    ('import "TouchpadScrollLogic.js" as Logic', "import " + json.dumps(logic) + " as Logic"),
    ("    id: root\n", "    id: root\n" + box + "\n"),
    ("if (wheel.phase === Qt.ScrollUpdate) {", "if (false) {"),
    ("if (wheel.phase !== Qt.NoScrollPhase) {", "if (false) {"),
]:
    assert text.count(needle) == 1, needle
    changed = text.replace(needle, replacement)
    assert changed != text
    text = changed
destination.write_text(text)
PY
carousel_swipe() { # FILE TAG: the cards one swipe steps on each rail, kept under TAG
  local height n name box x y now steps=()
  height="$(ipc smoke readDescendant window vgs.gallery CardCarousel height)" || return 1
  [[ $height =~ ^[0-9.]+$ ]] || { echo "height=$height"; return 0; }
  for n in 1 2; do
    name="carousel-swipe-$n"
    [[ $(ipc smoke popupLoad "$name" "$1" window vgs.gallery "{\"width\":4000,\"height\":$(python3 -c 'import sys; print(float(sys.argv[1]) * int(sys.argv[2]))' "$height" "$n"),\"model\":60,\"currentIndex\":30}") == ok ]] || { echo "load=$name"; return 0; }
    box="$(ipc smoke popupRead "$name" windowBox)" || return 1
    read -r x y < <(at_centre "window:VGS Components" "$(python3 -c 'import json,sys; x, y, w, h = json.loads(sys.argv[1]); print(json.dumps([x, y, 80, h]))' "$box")") || return 1
    hover "$x" "$y" || return 1
    swipe "$x" "$y" 100 || return 1
    # The rail steps in the frames that take the deltas.
    sleep 0.3
    now="$(ipc smoke popupRead "$name" currentIndex)" || return 1
    ipc smoke popupDrop "$name" >/dev/null || return 1
    [[ $now =~ ^[0-9]+$ ]] || { echo "index=$now"; return 0; }
    steps+=("$((now - 30))")
  done
  printf '%s,%s\n' "${steps[@]}" >"$sandbox/carousel-swipe-$2"
  python3 -c 'import sys
small, large = int(sys.argv[1]), int(sys.argv[2])
print("as-rail" if small >= 4 and abs(2 * large - small) <= 1 else "per-notch" if small == large else "steps=%d,%d" % (small, large))' "${steps[@]}"
}
expect "a two-finger swipe steps a carousel by the rail's travel" as-rail carousel_swipe "$repo/shell/Core/CarouselSwipeControl/SwipeRail.qml" rail
[[ -f $sandbox/carousel-swipe-rail ]] && printf '  carousel-swipe length=100 steps=%s\n' "$(<"$sandbox/carousel-swipe-rail")"
expect "control: a carousel that steps a swipe by the notch is refused" per-notch carousel_swipe "$repo/shell/Core/CarouselSwipeControl/NotchRail.qml" notch
[[ -f $sandbox/carousel-swipe-notch ]] && printf '  carousel-swipe-control length=100 steps=%s\n' "$(<"$sandbox/carousel-swipe-notch")"
rm -r -- "${repo:?}/shell/Core/CarouselSwipeControl" || fail "removing the carousel swipe controls failed"
if [[ -n $carousel_rest ]]; then
  read -r rest_x rest_y <<<"$carousel_rest"
  hover "$rest_x" "$rest_y" || fail "moving the pointer back after the carousel swipes failed"
fi

expect_poll "the gallery draws every focus example" '[]' ipc smoke galleryFocusMissing window vgs.gallery
gallery_tab_tour() {
  local required focus label seen_json
  required='["Button primary","Button secondary","Button tertiary","Button ghost","Button danger","ToggleButton","IconButton","BarItem","Switch","Checkbox","SegmentedControl","Select","TextField","Slider","TitleButton","Tabs","Disclosure","DeviceRow","CardCarousel","KeyNav list","Dialog accept action"]'
  seen_json='[]'
  [[ $(ipc smoke focusExample window vgs.gallery "Button primary") == focused ]] || { echo "focus-start-failed"; return 1; }
  for _ in $(seq 1 220); do
    focus="$(ipc smoke focused window vgs.gallery)" || return 1
    if [[ $focus != \[* ]]; then printf 'focus=%s\n' "$focus"; return; fi
    if ! python3 - "$focus" <<'PY'
import json, sys
row = json.loads(sys.argv[1])
composite = len(row) == 5 and row[1] in ("CardCarousel", "KeyNav list")
if len(row) != 5 or not ((row[2] and row[3] and row[4]) or (composite and row[4])):
    print("bad-focus=" + json.dumps(row))
    sys.exit(1)
PY
    then return 1; fi
    label="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])[1])' "$focus")" || return 1
    seen_json="$(python3 - "$seen_json" "$label" <<'PY'
import json, sys
seen = json.loads(sys.argv[1])
label = sys.argv[2]
if label and label not in seen:
    seen.append(label)
print(json.dumps(seen))
PY
)" || return 1
    if python3 - "$required" "$seen_json" <<'PY'
import json, sys
required, seen = map(json.loads, sys.argv[1:])
sys.exit(0 if all(label in seen for label in required) else 1)
PY
    then printf 'ok\n'; return 0; fi
    type_keys -k Tab || return 1
  done
  python3 - "$required" "$seen_json" <<'PY'
import json, sys
required, seen = map(json.loads, sys.argv[1:])
print("missing=" + json.dumps([label for label in required if label not in seen]) + " seen=" + json.dumps(seen))
PY
}
expect "the Gallery Tab tour reaches every Focus control with its ring in view" ok gallery_tab_tour
expect "the Gallery Radio focus example takes focus" focused ipc smoke focusExample window vgs.gallery Radio
mkdir -p "$repo/shell/Core/DialogModalControl"
cat >"$repo/shell/Core/DialogModalControl/Item.qml" <<'QML'
import QtQuick
import qs.Ui

Item {
    id: root
    property Item examples: root
    width: 480
    height: 220
    Dialog {
        property string focusExample: "Dialog accept action"
        width: parent.width
        modal: true
        title: "Modal control"
        message: "Escape stays in this control."
        actions: [{ label: "Cancel", role: "cancel" }, { label: "Save", role: "accept" }]
    }
}
QML
expect "the modal dialog control builds" ok ipc smoke popupLoad gallery-modal-control "$repo/shell/Core/DialogModalControl/Item.qml" window vgs.gallery '{}'
expect "the modal dialog control takes focus" focused ipc smoke popupFocusExample gallery-modal-control "Dialog accept action"
type_keys -k Escape || fail "Escape in the modal Gallery control failed"
expect "control: a modal Dialog keeps Escape from closing the Gallery window" 1 window_count "VGS Components"
expect "the modal dialog control is released" ok ipc smoke popupDrop gallery-modal-control
rm -r -- "${repo:?}/shell/Core/DialogModalControl" || fail "removing the modal Dialog control failed"
ipc smoke scrollTo window vgs.gallery 0 >/dev/null || fail "the gallery did not return to the top after the Tab tour"
render expect_poll "the gallery's headings are drawn with a size" 16 ipc smoke galleryHeadings window vgs.gallery
geometry expect "every example stays inside the gallery" '[]' ipc smoke galleryOverflow window vgs.gallery
mkdir -p "$repo/shell/Core/GalleryFocusControl"
cat >"$repo/shell/Core/GalleryFocusControl/Item.qml" <<'QML'
import QtQuick
import qs.Ui

Item {
    id: root
    property Item examples: root
    width: 240
    height: 80
    Switch {
        property string focusExample: "Switch"
        focusPreview: false
        text: "Switch"
    }
}
QML
focus_control_names_switch() { ipc smoke galleryFocusMissingCopy gallery-focus-control | py_reply 'import json,sys; print("Switch:focusPreview" in json.load(sys.stdin))'; }
expect "the focus example control builds" ok ipc smoke popupLoad gallery-focus-control "$repo/shell/Core/GalleryFocusControl/Item.qml" window vgs.gallery '{}'
expect "control: a missing focusPreview is named" True focus_control_names_switch
expect "the focus example control is released" ok ipc smoke popupDrop gallery-focus-control
rm -r -- "${repo:?}/shell/Core/GalleryFocusControl" || fail "removing the Gallery focus control failed"
# No block of the gallery draws over another: the title and each section's
# heading, in the order the body lays them out, each start at or below the
# end of the one before, within one pixel. The control moves the third
# heading onto the second in a copy of the same reading, which the check
# refuses. `[]` is the pass.
gallery_sections=(Surfaces Typography Buttons Choices Inputs Groups Feedback "Voice levels" Dialogs Cards Carousel Focus "Titles and scrolling" Lists "List motion")
gallery_stack() {
  local boxes=() title name
  title="$(ipc smoke shownWindowGeometry window vgs.gallery Label "VGS Components")" || return
  for name in "${gallery_sections[@]}"; do boxes+=("$(ipc smoke shownWindowGeometry window vgs.gallery SectionHeader "$name")"); done
  python3 - "${1:-}" "$title" "${boxes[@]}" <<'PY'
import json, sys
plant, raw = sys.argv[1] == "overlap", sys.argv[2:]
bad = [r for r in raw if not r.startswith("[")]
if bad:
    print(json.dumps(["unread=%s" % bad])); sys.exit()
boxes = [json.loads(r) for r in raw]
if plant: boxes[3] = [boxes[3][0], boxes[2][1] + 4] + boxes[3][2:]
out = []
for n in range(1, len(boxes)):
    prev, cur = boxes[n - 1], boxes[n]
    if cur[1] < prev[1] + prev[3] - 1: out.append("block%d.top=%.2f prev.bottom=%.2f" % (n, cur[1], prev[1] + prev[3]))
print(json.dumps(out))
PY
}
gallery_stack_planted() { gallery_stack overlap | py_reply 'import json,sys; print(any(e.startswith("block3.top=") for e in json.load(sys.stdin)))'; }
geometry expect_poll "no block of the gallery draws over another" '[]' gallery_stack
expect "control: a heading moved onto the one before is refused" True gallery_stack_planted
image_text_revealed() {
  local reply
  reply="$(ipc smoke revealImageText window vgs.gallery 0)" || return
  [[ $reply =~ ^[0-9] ]] && echo True || printf '%s\n' "$reply"
}
image_text_ready() {
  ipc smoke imageTextItems window vgs.gallery '' | py_reply 'import json,sys
items=json.load(sys.stdin)
ok=len(items)==1 and items[0]["imageMode"] and items[0]["failed"]==[] and len(items[0]["held"])==1
if ok:
    held=items[0]["held"][0]
    ok=held["status"]=="Ready" and held["sourceSize"]==[items[0]["deviceSize"], items[0]["deviceSize"]]
print(ok)'
}
image_text_control_props() {
  ipc smoke imageTextItems window vgs.gallery '' | py_reply 'import json,sys
item=json.load(sys.stdin)[0]
x,y,w,h=item["box"]
print(json.dumps({"x":x,"y":y,"boxWidth":w}))'
}
expect_poll "the gallery scrolls the ImageText sample into view" True image_text_revealed
expect_poll "the gallery ImageText sample loads its pool image" True image_text_ready
render expect_poll "the gallery ImageText sample draws magenta emoji pixels" True image_text_magenta_drawn "window:VGS Components" window vgs.gallery '' 0
image_text_pixels="$(image_text_magenta_count "window:VGS Components" window vgs.gallery '' 0)" || image_text_pixels=""
if [[ $image_text_pixels == \{* ]]; then
  py_reply 'import json,sys
row=json.load(sys.stdin)
print("  image-text-magenta scale=1 count=%d threshold=%d deviceSize=%d geometry=%s" % (row["count"], row["threshold"], row["deviceSize"], row["geometry"]))' <<<"$image_text_pixels"
fi
# Both controls are written before the first popup load because Qt caches
# the plugin directory's file names once it loads a control from it.
python3 - "$repo/shell/Ui/feedback/VoiceOrb.qml" "$repo/shell/plugins/vgs.gallery/VoiceOrbControl.qml" "$repo/shell/Ui/feedback/shaders/voiceorb.frag.qsb" <<'PY'
from pathlib import Path
import json, sys
source, destination, pack = map(Path, sys.argv[1:])
text = source.read_text()
for needle, replacement in [
    ("    Accessible.ignored: true\n", "    Accessible.ignored: true\n    function hideShader() { shader.visible = false; }\n"),
    ('Qt.resolvedUrl("shaders/voiceorb.frag.qsb")', 'Qt.resolvedUrl(' + json.dumps(str(pack)) + ')'),
]:
    assert text.count(needle) == 1, needle
    changed = text.replace(needle, replacement)
    assert changed != text
    text = changed
destination.write_text(text)
PY
cat >"$repo/shell/plugins/vgs.gallery/ImageTextControl.qml" <<'QML'
import QtQuick
import qs.Commons
import qs.Ui

Item {
    property real boxWidth: 400
    width: boxWidth
    height: sample.implicitHeight

    Rectangle { anchors.fill: parent; color: Theme.color.surface }
    ImageText {
        id: sample
        width: parent.width
        maximumLineCount: 2
        segments: [
            { markup: "An image sits in the line at the text's height " },
            { image: "", alt: ":sample:" },
            { markup: " and a text too long for its lines ends at a whole word or image." }
        ]
    }
}
QML
expect "the ImageText alt-only control builds" ok ipc smoke popupLoad image-text-control "$repo/shell/plugins/vgs.gallery/ImageTextControl.qml" window vgs.gallery "$(image_text_control_props)"
# The sample's magenta fill covers much more than one fifth of its square,
# while the alt-only text control draws no magenta image pixels.
render expect_poll "the pixel reader rejects the alt-only ImageText control" False image_text_magenta_drawn "window:VGS Components" window vgs.gallery image-text-control 0
expect "the ImageText control is released" ok ipc smoke popupDrop image-text-control
# The cursor over the controls, with the Buttons section scrolled to the
# top: the hand over an enabled button, switch and checkbox, and the arrow
# over each disabled one, which Qt skips when it picks the cursor.
gallery_box() { ipc smoke shownWindowGeometry window vgs.gallery "$1" "$2"; }
# A section's distance below the first one, read at the top, is the
# scroll that brings it to the top: the title sits in the fixed header.
gallery_offset() { python3 -c 'import json,sys; print(int(json.loads(sys.argv[1])[1] - json.loads(sys.argv[2])[1]))' "$(gallery_box SectionHeader "$1")" "$(gallery_box SectionHeader Surfaces)"; }
expect_poll "the gallery builds the VoiceOrb tones and level states" True orb_examples_ok
gallery_draw_orbs "the Gallery VoiceOrb shader"
# The same control must draw before its shader is hidden. Its blue tone
# occupies a blank fourth slot beside the final three accent examples.


mkdir -p "$repo/shell/Core/VoiceOrbControl"
python3 - "$repo/shell/Ui/feedback/VoiceOrb.qml" "$repo/shell/Core/VoiceOrbControl/VoiceOrb.qml" "$repo/shell/Ui/feedback/shaders/voiceorb.frag.qsb" <<'PY'
from pathlib import Path
import json, sys
source, destination, pack = map(Path, sys.argv[1:])
text = source.read_text()
for needle, replacement in [
    ("    Accessible.ignored: true\n", "    Accessible.ignored: true\n    function hideShader() { shader.visible = false; }\n"),
    ('Qt.resolvedUrl("shaders/voiceorb.frag.qsb")', 'Qt.resolvedUrl(' + json.dumps(str(pack)) + ')'),
]:
    assert text.count(needle) == 1, needle
    changed = text.replace(needle, replacement)
    assert changed != text
    text = changed
destination.write_text(text)
PY
control_gap="$(ipc smoke themeValue space.sm)" || exit 1
control_position="$(ipc smoke galleryOrbs window vgs.gallery '' | py_reply 'import json,sys
orb=json.load(sys.stdin)[-1]; x,y,w,h=orb["box"]
print(json.dumps({"x":x+w+json.loads(sys.argv[1]),"y":y,"tone":"info"}))' "$control_gap")" || exit 1
expect "the orb drawing control builds" ok ipc smoke popupLoad orb-control "$repo/shell/Core/VoiceOrbControl/VoiceOrb.qml" window vgs.gallery "$control_position"
render expect_poll "the normal orb control draws before the defect" True orb_drawn orb-control 0
expect "the control hides only its shader" ok ipc smoke popupCall orb-control hideShader
render expect_poll "the pixel reader rejects the hidden shader control" False orb_drawn orb-control 0
expect "the orb control is released" ok ipc smoke popupDrop orb-control
rm -r -- "${repo:?}/shell/Core/VoiceOrbControl" || fail "removing the orb control failed"
if [[ $(ipc smoke scrollTo window vgs.gallery 0) == \[* ]] && offset="$(gallery_offset Buttons)" && [[ $(ipc smoke scrollTo window vgs.gallery "$offset") == \[* ]]; then
  expect_cursor "an enabled button shows the hand" pointer "window:VGS Components" "$(gallery_box Button Small)"
  expect_cursor "a disabled button shows the arrow" default "window:VGS Components" "$(gallery_box Button Disabled)"
  if offset="$(gallery_offset Choices)" && [[ $(ipc smoke scrollTo window vgs.gallery "$offset") == \[* ]]; then
  expect_cursor "an enabled switch shows the hand" pointer "window:VGS Components" "$(gallery_box Switch Off)"
  expect_cursor "a disabled switch shows the arrow" default "window:VGS Components" "$(gallery_box Switch Disabled)"
  expect_cursor "an enabled checkbox shows the hand" pointer "window:VGS Components" "$(gallery_box Checkbox Unchecked)"
  expect_cursor "a disabled checkbox shows the arrow" default "window:VGS Components" "$(gallery_box Checkbox Disabled)"
  else
    fail "the gallery did not scroll its Choices section to the top"
  fi
  rest_pointer || fail "moving the pointer off the gallery failed"
else
  fail "the gallery did not scroll its Buttons section to the top"
fi
notes_on "gallery"
expect "the gallery sends a notification through its capability" ok ipc smoke invokeInstance window vgs.gallery notify ''
expect_poll "the gallery's notification shows as its card" '[["Saved", "The theme was saved", 1, "success", "check", "none"]]' plugin_cards "VGS Components"
notes_off "gallery"
expect "hiding the gallery is allowed" ok ipc shell hide window vgs.gallery
expect_poll "the gallery's window is gone" 0 window_count "VGS Components"
expect "the gallery summons again for the window rows" ok ipc shell summon window vgs.gallery '{}'
expect "the non-modal Gallery dialog example takes focus" focused ipc smoke focusExample window vgs.gallery "Dialog accept action"
type_keys -k Escape || fail "Escape in the Gallery's non-modal Dialog failed"
expect_poll "Escape from a Gallery Dialog example closes the window" 0 window_count "VGS Components"
expect "the gallery summons again for the app-window rows" ok ipc shell summon window vgs.gallery '{}'
app_window_rows "VGS Components" vgs.gallery
