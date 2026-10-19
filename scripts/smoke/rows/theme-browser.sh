# The theme browser, vgs.themes' overlay and service: SUPER+SHIFT+T on the
# nested seat opens it, and every row reads what it holds back through the
# probe: the view's cards and state through readDescendant, the images the
# cards draw through images, the texts it draws beside its rail and tabs
# through descendantGeometry, the typed filter and each tab's search hint
# among them, and its Dialog's through itemTexts. Neither view draws a
# search field; a copy of each view with one is its control. The rows page,
# filter, install and apply a catalog
# entry, and answer the wallpaper offer both ways. Holding SUPER+D, the
# user's focus bind, steps the rail as holding Right does; a layer whose
# captured focus bind does not repeat is its control. akane's card draws its
# package preview. A typed filter, in either view, takes its hint's place
# on one line of one height, and a failed apply shows its line under the
# pane; neither moves the rail. A copy of the theme view whose line takes
# the height of the text it shows is the filter's control, and one whose
# caption grows with the failures the failure's. A typed wallpaper filter
# leaves the divider and Show all on their rest rows; a copy of the
# wallpaper view whose source line centres on its Row is that control.
# Show all draws the same pixels at rest and with three typed filters of
# different widths; a copy whose typed filter takes a fractional width,
# which puts Show all at a fractional x, is that control. The old keys, SUPER+T
# and SUPER+W, open nothing, and each view's key moves an open browser to
# that view; a manifest copy still bound to SUPER+T is their control. The sandbox copy's
# catalog pins nord's wallpapers to an archive this row builds, served from
# a file:// base, which the runner takes under the sandbox's test-run
# marker. A stand-in holds the download behind a gate after two progress
# lines, polled every 50 ms for at most 30 s, so the Dialog's progress and
# the held close read back before the real download runs. The wallpaper
# view's rows, SUPER+SHIFT+W, follow the theme view's: they flip its source,
# from its source line and from Alt+S, and its scope, from its words and
# from Alt+M, set an image for one screen and for every screen on a second
# headless output and read each screen's drawn image back, and run the
# update card against a second archive the catalog pins anew. A copy of
# WallpaperView.qml that sets every image as the current one is their
# control. rows/themes.sh defines the helpers used here and leaves the
# plugin disabled, and rows/theme-browse.sh leaves vgs applied with Black
# current and nord not installed; this file enables the plugin and leaves
# all four so.
# A source without images keeps its no-wallpapers state under a filter;
# a logic copy that always treats a filter as the cause is its control.
# Every search line and empty state starts on whole screen rows and
# columns, in vgs and flexoki-light; a slot copy shifted by a fractional
# row is that check's control.
# inputs: shell/plugins/vgs.themes/* themes/catalog/* themes/vgs/* shell/Core/HyprlandLayer.js shell/Core/ThemeRunner.qml bin/vgshell bin/lib/theme-* bin/lib/qml-library.js shell/Commons/ThemeLogic.js shell/Ui/layout/CardCarousel.qml shell/Ui/layout/AngledCard.qml shell/Ui/layout/Tabs.qml shell/Ui/layout/Pane.qml shell/Ui/layout/ScrollArea.qml shell/Commons/ClearingInset.qml shell/Commons/Inset.js shell/Ui/feedback/Dialog.qml shell/Ui/controls/Button.qml shell/Ui/foundation/FocusRing.qml bin/vgshell-theme-judge shell/Core/ShortcutRegistry.qml shell/Core/Plugins.qml scripts/smoke/rows/themes.sh scripts/smoke/rows/theme-browse.sh scripts/smoke/rows/hyprland-consent.sh scripts/smoke/fixtures/theme-image.jpg
set -euo pipefail
view_value() { ipc smoke readDescendant overlay vgs.themes ThemeView "$1"; }
view_names() { view_value shownCards | py_reply 'import json,sys; print(json.dumps([c["name"] for c in json.load(sys.stdin)]))'; }
view_selected_name() { view_value selectedName | tr -d '"'; }
view_count() { view_value shownCards | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
has_card() { view_value shownCards | py_reply 'import json,sys; print(sys.argv[1] in [c["name"] for c in json.load(sys.stdin)])' "$1"; }
# The shown card at INDEX, or the last for -1.
card_at() { view_value shownCards | py_reply 'import json,sys; print(json.load(sys.stdin)[int(sys.argv[1])]["name"])' "$1"; }
job_step() { view_value job | py_reply 'import json,sys; j=json.load(sys.stdin); print("none" if j is None else j["step"] + " " + j["name"])'; }
selected_installed() { view_value selected | py_reply 'import json,sys; print(json.load(sys.stdin)["installed"])'; }
selected_preview() { view_value selected | py_reply 'import json,sys; print(json.load(sys.stdin).get("previewImage"))'; }
selected_slot() { view_value selected | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["terminal"][sys.argv[1]]))' "$1"; }
offer_name() { view_value offer | py_reply 'import json,sys; o=json.load(sys.stdin); print("none" if o is None else o["name"])'; }
# rest_texts: every text the browser draws outside its rail and its tabs,
# sorted and once each; rest_has TEXT: whether TEXT is one of them. At rest
# the theme view draws the selected name and its search hint, and
# the wallpaper view that hint beside its divider and source line and, with two
# screens, its scope line. A typed filter shows in place of the hint.
rest_texts() {
  ipc smoke descendantGeometry overlay vgs.themes | py_reply '
import json, sys
rows = json.load(sys.stdin)
def under(j):
    while j != -1:
        if rows[j]["type"] in ("CardCarousel", "Tabs"): return True
        j = rows[j]["parent"]
    return False
print(json.dumps(sorted({r["text"] for i, r in enumerate(rows) if isinstance(r.get("text"), str) and r["text"] != "" and r["visible"] and r["box"][2] > 0 and r["box"][3] > 0 and not under(i)})))'
}
# rail_top: the top of the rail on the output, to a hundredth of a pixel.
# rail_held TOP: `held` while the rail's top is TOP, else `moved` with both.
rail_top() {
  ipc smoke descendantGeometry overlay vgs.themes | py_reply '
import json, sys
rails = [r["box"] for r in json.load(sys.stdin) if r["type"] == "CardCarousel" and r["box"][2] > 0 and r["box"][3] > 0]
print("%.2f" % rails[0][1] if len(rails) == 1 else "rails=%d" % len(rails))'
}
rail_held() { # TOP
  local now
  now="$(rail_top)" || return
  if [[ $now == "$1" ]]; then echo held; else echo "moved from=$1 to=$now"; fi
}
# text_line TEXT: the top and the height of the search line the drawn text
# TEXT sits in, its nearest BrowserSlot ancestor, to a hundredth of a pixel.
text_line() {
  ipc smoke descendantGeometry overlay vgs.themes | py_reply '
import json, sys
rows = json.load(sys.stdin)
def line(j):
    j = rows[j]["parent"]
    while j != -1 and rows[j]["type"] != "BrowserSlot":
        j = rows[j]["parent"]
    return j
found = [line(i) for i, r in enumerate(rows) if r.get("text") == sys.argv[1] and r["visible"] and r["box"][2] > 0 and r["box"][3] > 0]
found = [j for j in found if j != -1]
print("%.2f %.2f" % (rows[found[0]]["box"][1], rows[found[0]]["box"][3]) if len(found) == 1 else "lines=%d" % len(found))' "$1"
}
# text_top TEXT: the top of the one drawn text TEXT on the output, to a
# hundredth of a pixel; no line and a failure while not exactly one shows.
text_top() {
  ipc smoke descendantGeometry overlay vgs.themes | py_reply '
import json, sys
tops = [r["box"][1] for r in json.load(sys.stdin) if r.get("text") == sys.argv[1] and r["visible"] and r["box"][2] > 0 and r["box"][3] > 0]
print("%.2f" % tops[0]) if len(tops) == 1 else sys.exit("texts=%d" % len(tops))' "$1"
}
# show_all_pixels: the pixels Show all draws on the nested output, its box
# one pixel wider on every side, read through grim, as `WxH HEX`; no line
# and a failure while the box is unreadable or the crop holds one colour.
show_all_pixels() {
  local rows surface socket geometry
  rows="$(ipc smoke descendantGeometry overlay vgs.themes)" &&
    surface="$(surface_box vgs:overlay)" &&
    socket="$(shot_socket "$rt_dir" "$nested_socket")" || return 1
  # The probe answers boxes in the overlay window's coordinates; the
  # layer's position on the layout places them for grim.
  geometry="$(python3 -c '
import json, math, sys
boxes = [r["box"] for r in json.loads(sys.argv[1]) if r.get("text") == "Show all" and r["visible"] and r["box"][2] > 0 and r["box"][3] > 0]
if len(boxes) != 1: sys.exit("show-all-boxes=%d" % len(boxes))
l = json.loads(sys.argv[2])
x, y, w, h = boxes[0]
print("%d,%d %dx%d" % (round(l[0] + x) - 1, math.floor(l[1] + y) - 1, math.ceil(w) + 3, math.ceil(h) + 3))' "$rows" "$surface")" || return 1
  shot_grim "$socket" "$rt_dir" -g "$geometry" -t ppm - | python3 -c '
import sys
d = sys.stdin.buffer.read().split(b"\n", 3)
if len(d) != 4 or d[0] != b"P6" or d[2] != b"255": sys.exit("show-all-pixels=unreadable")
w, h = map(int, d[1].split())
px = d[3]
if len(px) != w * h * 3: sys.exit("show-all-pixels=incomplete")
if len({px[i:i + 3] for i in range(0, len(px), 3)}) < 2: sys.exit("show-all-pixels=blank")
print("%dx%d %s" % (w, h, px.hex()))'
}
# pixels_near A B: `same` when two show_all_pixels readings are one size
# and no channel of a pixel differs by more than 2, else `differs` with the
# largest difference and how many pixels exceed it. The nested renderer
# draws one unmoved text a level apart between frames (sandbox-shots on
# f8dca8ce4: 3 of 1045 pixels, 1 level, two rest captures of Show all).
pixels_near() {
  python3 -c '
import sys
(sa, ha), (sb, hb) = (v.split() for v in sys.argv[1:3])
if sa != sb: sys.exit(print("differs size=%s,%s" % (sa, sb)))
a, b = bytes.fromhex(ha), bytes.fromhex(hb)
gaps = [abs(p - q) for p, q in zip(a, b)]
over = sum(1 for g in gaps if g > 2)
print("same" if over == 0 else "differs max=%d channels=%d" % (max(gaps), over))' "$1" "$2"
}
# settled_show_all_pixels: show_all_pixels once two readings 0.2 s apart
# are pixels_near; no line and a failure when none are within
# smoke_poll_bound_ms.
settled_show_all_pixels() {
  local now last=""
  for _ in $(seq 1 $((smoke_poll_bound_ms / 200))); do
    now="$(show_all_pixels)" || return 1
    [[ -n $last && $(pixels_near "$now" "$last") == same ]] && { echo "$now"; return 0; }
    last="$now"
    sleep 0.2
  done
  echo "show-all-pixels=unsettled" >&2
  return 1
}
# show_all_against REST: pixels_near of Show all's pixels now and REST.
show_all_against() {
  local now
  now="$(show_all_pixels)" || return 1
  pixels_near "$now" "$1"
}
# pointer_off_line: the pointer moved to the overlay's left edge, half way
# down, off the search line, so Show all draws no hover in its reading.
pointer_off_line() {
  local surface x y
  surface="$(surface_box vgs:overlay)" || return 1
  read -r x y < <(python3 -c 'import json,sys; l=json.loads(sys.argv[1]); print(int(l[0]) + 8, int(l[1] + l[3] / 2))' "$surface") || return 1
  hover "$x" "$y"
}
rest_has() { rest_texts | py_reply 'import json,sys; print(sys.argv[1] in json.load(sys.stdin))' "$1"; }
# search_field: whether the shown view draws a search field, `absent`
# for none.
search_field() { ipc smoke readDescendant overlay vgs.themes TextField visible; }
# slice_names: the side cards the rail shows and how many of them draw no
# name, as [shown, unnamed]: a side card is a shown AngledCard other than
# the selected one, the largest, and it names its theme with a visible
# Label inside it.
slice_names() {
  ipc smoke descendantGeometry overlay vgs.themes | py_reply '
import json, sys
rows = json.load(sys.stdin)
def card_of(j):
    while j != -1:
        if rows[j]["type"] == "AngledCard": return j
        j = rows[j]["parent"]
    return -1
cards = [i for i, r in enumerate(rows) if r["type"] == "AngledCard" and r["visible"] and r["box"][2] > 0 and r["box"][3] > 0]
selected = max(cards, key=lambda i: rows[i]["box"][2] * rows[i]["box"][3]) if cards else -1
named = {card_of(i) for i, r in enumerate(rows) if r["type"] == "Label" and r["visible"] and isinstance(r.get("text"), str) and r["text"] != "" and r["box"][2] > 0 and r["box"][3] > 0}
sides = [i for i in cards if i != selected]
print(json.dumps([len(sides), len([i for i in sides if i not in named])]))'
}
slices_named() { slice_names | py_reply 'import json,sys; shown, unnamed = json.load(sys.stdin); print("named" if shown > 0 and unnamed == 0 else "shown=%d unnamed=%d" % (shown, unnamed))'; }
slices_unnamed() { slice_names | py_reply 'import json,sys; shown, unnamed = json.load(sys.stdin); print("unnamed" if shown > 0 and unnamed == shown else "shown=%d unnamed=%d" % (shown, unnamed))'; }
# slice_look: the side cards' names as drawn, one finding per broken
# rule, `[]` the pass. Each shown name starts carousel.sliceName.inset up
# its slice's slanted axis from the slice's bottom edge, on that axis
# within a pixel (`inset`), and reads up it (`upward`); it draws in h2
# (`role`), white (`colour`), over a shadow, one per shown name, of black
# at full opacity blurred 4 pixels, its offsets turned through the name's
# rotation landing carousel.sliceName.shadowOffset down and right on
# screen (`shadow`); on a card whose dim wash shows, it
# is drawn after the wash, so the wash does not reach it (`wash`). The
# wash is the Rectangle AngledCard keeps beside its content inside the
# masked item, a grandchild of the card; the name is over it when one of
# its ancestors is a later sibling of the wash, as items of one z draw in
# their parent's order, which a breadth-first list keeps. The axis runs
# from the bottom edge's centre to the top edge's, the drawn lean apart,
# the card's height times
# angledCard.skew over carousel.sliceHeight; a name's start is the middle
# of its leading edge, half its line box from its rotated origin. A
# layer's effect is a sibling of the item it draws and reads as its C++
# type, QQuickMultiEffect. `none` while no side card draws a name.
slice_look() {
  local rows rotation colour enabled shadow opacity blur radius sideways downward offset inset skew height
  rows="$(ipc smoke descendantGeometry overlay vgs.themes)" || return
  rotation="$(ipc smoke readMatchingDescendant overlay vgs.themes Label objectName sliceName rotation)" || return
  colour="$(ipc smoke readMatchingDescendant overlay vgs.themes Label objectName sliceName color)" || return
  enabled="$(ipc smoke readMatchingDescendant overlay vgs.themes QQuickMultiEffect objectName sliceNameShadow shadowEnabled)" || return
  shadow="$(ipc smoke readMatchingDescendant overlay vgs.themes QQuickMultiEffect objectName sliceNameShadow shadowColor)" || return
  opacity="$(ipc smoke readMatchingDescendant overlay vgs.themes QQuickMultiEffect objectName sliceNameShadow shadowOpacity)" || return
  blur="$(ipc smoke readMatchingDescendant overlay vgs.themes QQuickMultiEffect objectName sliceNameShadow blurMax)" || return
  radius="$(ipc smoke readMatchingDescendant overlay vgs.themes QQuickMultiEffect objectName sliceNameShadow shadowBlur)" || return
  sideways="$(ipc smoke readMatchingDescendant overlay vgs.themes QQuickMultiEffect objectName sliceNameShadow shadowHorizontalOffset)" || return
  downward="$(ipc smoke readMatchingDescendant overlay vgs.themes QQuickMultiEffect objectName sliceNameShadow shadowVerticalOffset)" || return
  offset="$(ipc smoke themeValue carousel.sliceName.shadowOffset)" || return
  inset="$(ipc smoke themeValue carousel.sliceName.inset)" || return
  skew="$(ipc smoke themeValue angledCard.skew)" || return
  height="$(ipc smoke themeValue carousel.sliceHeight)" || return
  printf '%s\n' "$rows" | py_reply '
import json, math, sys
rows = json.load(sys.stdin)
rotation, colour, enabled, shadow, opacity, blur, radius, sideways, downward, offset, inset, skew, height = sys.argv[1:]
def card_of(j):
    while j != -1:
        if rows[j]["type"] == "AngledCard": return j
        j = rows[j]["parent"]
    return -1
def shown(r): return r["visible"] and r["box"][2] > 0 and r["box"][3] > 0
def rgba(text):
    try: c = json.loads(text)
    except ValueError: return None
    return [round(c[k], 2) for k in "rgba"] if isinstance(c, dict) and all(k in c for k in "rgba") else None
names = [r for r in rows if r["type"] == "Label" and r["name"] == "sliceName" and shown(r) and r["text"]]
if not names or rotation == "absent":
    print("none"); sys.exit()
turn = math.radians(float(rotation))
inset, lean = float(inset), float(skew) / float(height)
found = set()
def lineage(j):
    out = []
    while j != -1:
        out.append(j)
        j = rows[j]["parent"]
    return out
for r in names:
    card = card_of(r["parent"])
    washes = [k for k, w in enumerate(rows) if w["type"] == "QQuickRectangle" and w["parent"] != -1 and rows[w["parent"]]["type"] == "QQuickItem" and rows[w["parent"]]["parent"] == card]
    own = next(k for k, row in enumerate(rows) if row is r)
    if card == -1 or len(washes) != 1: found.add("wash")
    elif rows[washes[0]]["visible"] and not any(rows[a]["parent"] == rows[washes[0]]["parent"] and a > washes[0] for a in lineage(own)): found.add("wash")
    x, y, cw, ch = rows[card]["box"] if card != -1 else (0, 0, 0, 0)
    s = ch * lean
    bottom = (x + (cw - s) / 2, y + ch)
    length = math.hypot(s, ch) or 1
    axis = (s / length, -ch / length)
    half = r["box"][3] / 2
    start = (r["box"][0] - half * math.sin(turn), r["box"][1] + half * math.cos(turn))
    rel = (start[0] - bottom[0], start[1] - bottom[1])
    along = rel[0] * axis[0] + rel[1] * axis[1]
    across = rel[0] * axis[1] - rel[1] * axis[0]
    if ch == 0 or abs(along - inset) > 1 or abs(across) > 1: found.add("inset")
    if math.cos(turn) * axis[0] + math.sin(turn) * axis[1] < 0.9999: found.add("upward")
    if r["role"] != "h2": found.add("role")
if rgba(colour) != [1, 1, 1, 1]: found.add("colour")
effects = [r for r in rows if r["type"] == "QQuickMultiEffect" and r["name"] == "sliceNameShadow" and r["visible"]]
def dropped():
    if "absent" in (sideways, downward): return False
    h, v, o = float(sideways), float(downward), float(offset)
    return abs(h * math.cos(turn) - v * math.sin(turn) - o) <= 0.01 and abs(h * math.sin(turn) + v * math.cos(turn) - o) <= 0.01
if len(effects) < len(names) or enabled != "true" or rgba(shadow) != [0, 0, 0, 1] or opacity == "absent" or abs(float(opacity) - 1) > 0.005 or blur != "4" or radius != "1" or not dropped(): found.add("shadow")
print(json.dumps(sorted(found)))' "$rotation" "$colour" "$enabled" "$shadow" "$opacity" "$blur" "$radius" "$sideways" "$downward" "$offset" "$inset" "$skew" "$height"
}
dialog_has() { ipc smoke itemTexts overlay vgs.themes Dialog | py_reply 'import json,sys; print(any(sys.argv[1] in t for t in json.load(sys.stdin)))' "$1"; }
# The status of the card image drawing PATH, `none` when no card draws it.
card_image() { ipc smoke images overlay vgs.themes | py_reply 'import json,sys; r=[i[1] for i in json.load(sys.stdin) if i[0]==sys.argv[1]]; print(r[0] if r else "none")' "$1"; }
# Whether a palette card names LABEL: a card with no image draws its
# label, and one whose image shows draws none.
palette_card() { ipc smoke itemTexts overlay vgs.themes ThemeCard | py_reply 'import json,sys; print(any(sys.argv[1] in t for t in json.load(sys.stdin)))' "$1"; }
theme_card_has_colour() { ipc smoke itemColours overlay vgs.themes ThemeCard Rectangle | py_reply 'import json,sys; print(any(sys.argv[1] in row for row in json.load(sys.stdin)))' "$1"; }
lent_themes() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(sorted(s for s in json.load(sys.stdin)["shortcuts"] if s.startswith("vgs.themes"))))'; }
# The binds of shortcut NAME, `themes` by default, as [modmask, key].
themes_bind() { hypr -j binds | py_reply 'import json,sys; print(json.dumps([[b["modmask"], b["key"]] for b in json.load(sys.stdin) if b["description"] == "vgs.themes:" + sys.argv[1] and b.get("submap", "") in ("", "default")]))' "${1:-themes}"; }
catalog_imagery() { "${shell_env[@]}" "$repo/bin/vgshell" theme catalog --json | py_reply 'import json,sys; print([e["imageryInstalled"] for e in json.load(sys.stdin)["entries"] if e["name"]==sys.argv[1]][0])' "$1"; }
# Whether the first ready image drawing PATH asks to decode at its drawn size
# times the CardCarousel's screen scale.
card_source_size_matches() { # PATH
  local dpr
  dpr="$(ipc smoke readDescendant overlay vgs.themes CardCarousel devicePixelRatio)" || return 1
  ipc smoke images overlay vgs.themes | py_reply 'import json,sys; path, dpr = sys.argv[1], float(sys.argv[2]); rows=[i for i in json.load(sys.stdin) if i[0] == path and i[1] == "ready"]; print(bool(rows and rows[0][4] == [round(rows[0][2][0] * dpr), round(rows[0][2][1] * dpr)]))' "$1" "$dpr"
}
# SUPER+SHIFT+T and SUPER+SHIFT+W typed on the nested seat, and the keys
# the two browsers had before them.
press_themes() { type_keys -M logo -M shift -k t -m shift -m logo; }
press_wallpapers() { type_keys -M logo -M shift -k w -m shift -m logo; }
press_old_themes() { type_keys -M logo -k t -m logo; }
press_old_wallpapers() { type_keys -M logo -k w -m logo; }
rail_focused() { ipc smoke readDescendant overlay vgs.themes CardCarousel activeFocus; }
# The selected card as `card=<name>`, read from the view's card object
# through py_reply; `no-selection` for none, and a state word the probe
# answers in its place, such as `absent` for a closed browser, passes
# through without the prefix, so no failed read ever names a card.
selected_card() { view_value selected | py_reply 'import json,sys; c=json.load(sys.stdin); print("card=" + c["name"] if isinstance(c, dict) and isinstance(c.get("name"), str) and c["name"] else "no-selection")'; }
# selection_moved CARD: `moved` once the view selects a card other than
# CARD, a `card=<name>` selected_card read, `same` while it selects CARD,
# and anything selected_card answers that names no card as it came.
selection_moved() {
  local now
  now="$(selected_card)" || return 1
  [[ $now == card=* ]] || { printf '%s\n' "$now"; return 0; }
  [[ $now != "$1" ]] && echo moved || echo same
}
# rail_band: the midpoint of the empty band between the rail's left edge
# and the first shown card, as `X Y`: inside the browser's pane, over no card.
rail_band() {
  ipc smoke descendantGeometry overlay vgs.themes | py_reply '
import json,sys
rows=json.load(sys.stdin)
rails=[x["box"] for x in rows if x["type"] == "CardCarousel" and x["box"][2] > 0 and x["box"][3] > 0]
if len(rails) != 1:
    print("rails=%d" % len(rails)); sys.exit()
rail=rails[0]
cards=[r["box"] for r in rows if r["type"] == "AngledCard" and r["visible"] and r["box"][2] > 0 and r["box"][3] > 0]
if not cards:
    print("cards=0"); sys.exit()
first=min(c[0] for c in cards)
gap=first - rail[0]
if gap <= 1:
    print("gap=%.2f" % gap); sys.exit()
print("%d %d" % (round(rail[0] + gap / 2), round(rail[1] + rail[3] / 2)))'
}
# band_click LABEL: summon the theme view and click the rail's band.
band_click() {
  local at x y
  expect "$1: a summon over IPC opens the theme view" ok ipc shell summon overlay vgs.themes '{}'
  expect_poll "$1: the summon maps the browser" 1 layer_count vgs:overlay
  expect_poll "$1: the summoned browser read its cards" true view_value loaded
  at="$(rail_band)" && [[ $at =~ ^[0-9]+\ [0-9]+$ ]] || { fail "$1: the rail's band is unreadable: ${at:-failed}"; return 1; }
  read -r x y <<<"$at"
  click "$x" "$y"
}
browser_focused() { expect_poll "${1:-the browser holds the keyboard}" true ipc smoke activeFocusIn overlay vgs.themes; }
# sixteen(card): a card's sixteen colours, written out here apart from
# BrowserLogic: its terminal slots color0 to color15, each made opaque, as
# the theme's terminal.json gives them; None without them.
theme_sixteen_py='
def sixteen(card):
    t = card.get("terminal") or {}
    v = [t.get("color%d" % i) for i in range(16)]
    return [x[:7] + "ff" for x in v] if all(isinstance(x, str) for x in v) else None
'
# collapsed_stacks: one finding per broken rule, `[]` the pass. Every
# shown slice, a visible paletteStack, is 16 blocks in 2 columns and 8
# rows filling it with no gap, each half its width and an eighth of its
# height, filled row by row (`grid`), in the sixteen colours of a shown
# theme (`colours`), drawn after its card's dim wash, so the wash does not
# reach it (`wash`, the rule slice_look reads for the name); and at least 3
# slices show (`stacks`). The strips and their drawn colours are read in
# the probe's one tree order.
collapsed_stacks() {
  local shown colours
  shown="$(view_value shownCards)" || return
  colours="$(ipc smoke itemColours overlay vgs.themes ThemePaletteStrip QQuickRectangle)" || return
  ipc smoke descendantGeometry overlay vgs.themes | py_reply "$theme_sixteen_py"'
import json, sys
rows, shown, colours = json.load(sys.stdin), json.loads(sys.argv[1]), json.loads(sys.argv[2])
want = [w for w in (sixteen(c) for c in shown if c.get("state") == "ok") if w is not None]
def card_of(j):
    while j != -1:
        if rows[j]["type"] == "AngledCard": return j
        j = rows[j]["parent"]
    return -1
def lineage(j):
    out = []
    while j != -1:
        out.append(j)
        j = rows[j]["parent"]
    return out
strips = [i for i, r in enumerate(rows) if r["type"] == "ThemePaletteStrip"]
if len(strips) != len(colours):
    print(json.dumps(["readers strips=%d colours=%d" % (len(strips), len(colours))])); sys.exit()
out, stacks = [], 0
for k, i in enumerate(strips):
    x, y, w, h = rows[i]["box"]
    if rows[i]["name"] != "paletteStack" or not rows[i]["visible"] or w <= 0 or h <= 0: continue
    stacks += 1
    blocks = [r["box"] for r in rows if r["parent"] == i and r["type"] == "QQuickRectangle" and r["visible"]]
    for n, b in enumerate(blocks):
        if len(blocks) != 16 or abs(b[0] - (x + n % 2 * w / 2)) > 1 or abs(b[2] - w / 2) > 1 or abs(b[1] - (y + n // 2 * h / 8)) > 1 or abs(b[3] - h / 8) > 1:
            out.append("grid stack=%d blocks=%d block=%d box=%s stack=%s" % (k, len(blocks), n, [round(v, 2) for v in b], [round(v, 2) for v in rows[i]["box"]])); break
    if colours[k] not in want: out.append("colours stack=%d got=%s" % (k, colours[k]))
    card = card_of(i)
    washes = [j for j, r in enumerate(rows) if r["type"] == "QQuickRectangle" and r["parent"] != -1 and rows[r["parent"]]["type"] == "QQuickItem" and rows[r["parent"]]["parent"] == card]
    if card == -1 or len(washes) != 1: out.append("wash stack=%d washes=%d" % (k, len(washes)))
    elif rows[washes[0]]["visible"] and not any(rows[a]["parent"] == rows[washes[0]]["parent"] and a > washes[0] for a in lineage(i)): out.append("wash stack=%d" % k)
if stacks < 3: out.append("stacks shown=%d" % stacks)
print(json.dumps(out))' "$shown" "$colours"
}
# expanded_foot: the same for the selected card. One visible paletteStrip
# lies along the card's foot as 16 blocks in 8 columns and 2 rows with no
# gap, each an eighth of its width and half its height, filled row by row
# (`strip`), in the selected theme's sixteen colours (`strip-colours`).
expanded_foot() {
  local selected strips
  selected="$(view_value selected)" || return
  strips="$(ipc smoke itemColours overlay vgs.themes ThemePaletteStrip QQuickRectangle)" || return
  ipc smoke descendantGeometry overlay vgs.themes | py_reply "$theme_sixteen_py"'
import json, sys
rows, card, strips = json.load(sys.stdin), json.loads(sys.argv[1]), json.loads(sys.argv[2])
want, out = sixteen(card), []
def shown(r): return r["visible"] and r["box"][2] > 0 and r["box"][3] > 0
cards = [r["box"] for r in rows if r["type"] == "AngledCard" and shown(r)]
feet = [(k, i) for k, i in enumerate(i for i, r in enumerate(rows) if r["type"] == "ThemePaletteStrip") if rows[i]["name"] == "paletteStrip" and shown(rows[i])]
if want is None or not cards or len(feet) != 1:
    print(json.dumps(["readers sixteen=%s cards=%d strips=%d" % (want is not None, len(cards), len(feet))])); sys.exit()
cx, cy, cw, ch = max(cards, key=lambda b: b[2] * b[3])
k, i = feet[0]
sx, sy, sw, sh = rows[i]["box"]
blocks = [r["box"] for r in rows if r["parent"] == i and r["type"] == "QQuickRectangle" and r["visible"]]
if abs(sy + sh - (cy + ch)) > 1 or abs(sw - cw) > 1: out.append("strip strip=%s card=%s" % (rows[i]["box"], [cx, cy, cw, ch]))
for n, b in enumerate(blocks):
    if len(blocks) != 16 or abs(b[0] - (sx + n % 8 * sw / 8)) > 1 or abs(b[2] - sw / 8) > 1 or abs(b[1] - (sy + n // 8 * sh / 2)) > 1 or abs(b[3] - sh / 2) > 1:
        out.append("strip blocks=%d block=%d box=%s strip=%s" % (len(blocks), n, [round(v, 2) for v in b], [round(v, 2) for v in rows[i]["box"]])); break
if strips[k] != want: out.append("strip-colours got=%s want=%s" % (strips[k], want))
print(json.dumps(out))' "$selected" "$strips"
}
# judged_rule JUDGE RULE: whether JUDGE reports a finding of RULE.
judged_rule() { "$1" | py_reply 'import json,sys; print(any(e.startswith(sys.argv[1] + " ") for e in json.load(sys.stdin)))' "$2"; }

# The fixture archive and nord's pin to it, in the sandbox copy's catalog.
index="$repo/themes/catalog/index.json"
cp -p -- "$index" "$sandbox/catalog-index.json"
assets="$sandbox/theme-assets"
mkdir -p -- "$assets/themes"
python3 - "$assets/themes/vgs-theme-nord-smoke.tar.gz" "$repo/scripts/smoke/fixtures/theme-image.jpg" "$index" <<'PY'
import hashlib, io, json, os, sys, tarfile
out, image, index = sys.argv[1:]
with tarfile.open(out, "w:gz") as tar:
    for name in ("backgrounds/a.jpg", "backgrounds/b.jpg"):
        tar.add(image, arcname=name)
data = open(out, "rb").read()
doc = json.load(open(index))
nord = [e for e in doc["entries"] if e["name"] == "nord"][0]
nord["imagery"] = dict(nord["imagery"], archive=os.path.basename(out), size=len(data), sha256=hashlib.sha256(data).hexdigest())
with open(index + ".next", "w") as f:
    json.dump(doc, f)
os.replace(index + ".next", index)
PY
wallpaper_gate="$sandbox/theme-wallpaper-gate"
# The first apply of akane answers busy, as a runner holding the theme lock
# does; the file records that it did.
akane_refused="$sandbox/theme-akane-refused"
cp -p -- "$repo/bin/vgshell" "$repo/bin/vgshell.real"
stand_in_vgshell "export VGS_THEME_ASSET_BASE=$(printf %q "file://$assets")
if [[ \${2:-} == apply && \${4:-} == akane && ! -e $(printf %q "$akane_refused") ]]; then
  touch -- $(printf %q "$akane_refused")
  printf '%s\n' '{\"state\":\"failed\",\"shell\":\"failed\",\"targets\":[],\"theme\":\"akane\",\"reason\":\"busy\"}'
  exit 75
fi
if [[ \${2:-} == wallpapers ]]; then
  printf '%s\n' '{\"state\":\"downloading\",\"bytes\":0,\"total\":4000000}' '{\"state\":\"downloading\",\"bytes\":2000000,\"total\":4000000}'
  for _ in \$(seq 1 600); do [[ -e $(printf %q "$wallpaper_gate") ]] && break; sleep 0.05; done
fi"

# The service registers the shortcut and the layer binds SUPER+SHIFT+T.
expect "enabling vgs.themes for the browser rows is allowed" ok ipc shell setPluginEnabled vgs.themes true
expect_poll "the themes service registered its shortcuts" '["vgs.themes:gaps", "vgs.themes:panel", "vgs.themes:themes", "vgs.themes:wallpapers"]' lent_themes
expect_poll "the nested instance binds SUPER+SHIFT+T to the theme browser" '[[65, "T"]]' themes_bind
expect_poll "the nested instance binds SUPER+SHIFT+W to the wallpaper browser" '[[65, "W"]]' themes_bind wallpapers
themes_global() { hypr globalshortcuts | python3 -c 'import sys; print(sum(1 for line in sys.stdin if "vgs.themes:themes" in line))'; }
expect_poll "the compositor lists the themes shortcut" 1 themes_global
# wtype types on a virtual keyboard with keycodes of its own, which a bind
# resolves only by keysym, so the sandbox user's settings turn that on
# for these rows, as rows/hyprland.sh does for its own, and the file is
# put back after them.
hypr_lua="$home/.config/hypr/hyprland.lua"
cp -p -- "$hypr_lua" "$sandbox/hyprland-before-browser.lua"
{
  printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })'
  printf '%s\n' 'hl.bind("SUPER + A", hl.dsp.focus({ direction = "left" }), { description = "Smoke focus left" })'
  printf '%s\n' 'hl.bind("SUPER + D", hl.dsp.focus({ direction = "right" }), { description = "Smoke focus right" })'
} >>"$hypr_lua"
expect "the nested instance reloads with binds resolved by keysym and smoke focus keys" ok hypr reload config-only
expect "no browser shows before SUPER+SHIFT+T" 0 layer_count vgs:overlay
# The old keys open nothing: each goes just before the new key of the same
# browser, which would close a browser the old key opened. Inside one
# browser the other browser's key switches the view, and its own key
# closes it.
press_old_wallpapers || fail "typing SUPER+W failed"
press_wallpapers || fail "typing SUPER+SHIFT+W after SUPER+W failed"
expect_poll "SUPER+W opens nothing, so SUPER+SHIFT+W opens the browser" 1 layer_count vgs:overlay
expect_poll "SUPER+SHIFT+W opens the wallpaper view" '"wallpapers"' ipc smoke readInstance overlay vgs.themes view
press_themes || fail "typing SUPER+SHIFT+T in the wallpaper view failed"
expect_poll "SUPER+SHIFT+T in the wallpaper view switches to the theme view" '"themes"' ipc smoke readInstance overlay vgs.themes view
expect "the switch to the theme view keeps the browser open" 1 layer_count vgs:overlay
press_wallpapers || fail "typing SUPER+SHIFT+W in the theme view failed"
expect_poll "SUPER+SHIFT+W in the theme view switches to the wallpaper view" '"wallpapers"' ipc smoke readInstance overlay vgs.themes view
expect "the switch to the wallpaper view keeps the browser open" 1 layer_count vgs:overlay
press_wallpapers || fail "typing SUPER+SHIFT+W to close the switched browser failed"
expect_poll "SUPER+SHIFT+W on the switched wallpaper view closes it" 0 layer_count vgs:overlay
# SUPER+SHIFT+T opens the theme view on the applied theme.
press_old_themes || fail "typing SUPER+T failed"
press_themes || fail "typing SUPER+SHIFT+T failed"
expect_poll "SUPER+T opens nothing, so SUPER+SHIFT+T opens the browser" 1 layer_count vgs:overlay
expect "the browser shows the theme view" '"themes"' ipc smoke readInstance overlay vgs.themes view
browser_focused "the open browser holds the keyboard"
expect_poll "the browser read the list, the catalog and the images" true view_value loaded
expect "the browser includes the shipped vgs card" True has_card vgs
expect_poll "the retained catalog reaches the installed list with nord" True has_card nord
expect "the applied theme is selected" '"vgs"' view_value selectedName
expect_poll "the resting theme view draws the selected theme's name and its search hint beside its cards and tabs" '["Type a theme name to search", "VGS"]' rest_texts
expect "the theme view draws no search field" absent search_field
expect_poll "every side card names its theme" named slices_named
expect_poll "every side card's name starts the inset up its slice, in h2, white over its shadow, above its card's wash" '[]' slice_look
# The browser's layout, one finding per broken rule, `[]` the pass: its
# tabs lie inside the output less inset.overlay each side (`inset`); the
# tabs end above the rail and the rail holds the selected card (`order`);
# and the rail is centred, the same distance in from both output sides
# (`centre`). Each holds within one pixel and reads containment, so a
# theme with a larger font still passes.
# browser_geometry reads the overlay and keeps the reading;
# browser_planted RULE judges that kept reading with one box moved, so
# each rule's control requires its own finding on the reading the rule
# passed and reads the overlay, a paged reply of seconds, no second time.
browser_kept="$sandbox/theme-browser-reading"
browser_geometry() {
  local inset reading extent width height
  inset="$(ipc smoke themeValue inset.overlay)" || return
  extent="$(surface_box vgs:overlay | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print(w, h)')" || return
  read -r width height <<<"$extent"
  reading="$(ipc smoke descendantGeometry overlay vgs.themes)" || return
  printf '%s %s %s\n%s\n' "$inset" "$width" "$height" "$reading" >"$browser_kept.tmp" && mv -T -- "$browser_kept.tmp" "$browser_kept" || return
  browser_judge "$inset" "$width" "$height" "" <<<"$reading"
}
browser_judge() { # INSET WIDTH HEIGHT PLANT, the reading on stdin
  py_reply '
import json, sys
rows, inset, width, height, plant = json.load(sys.stdin), float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
out = []
def shown(r): return r["box"][2] > 0 and r["box"][3] > 0
def of(kind): return [i for i, r in enumerate(rows) if r["type"] == kind and shown(r)]
rail = of("CardCarousel")
if len(rail) != 1:
    print(json.dumps(["rails=%d" % len(rail)])); sys.exit()
rail = rows[rail[0]]["box"][:]
header = [rows[i]["box"][:] for i in of("Tabs")]
cards = [r["box"] for r in rows if r["type"] == "AngledCard" and shown(r)]
if plant == "inset": header[0][0] += width
if plant == "order" and header: rail[1] = max(b[1] + b[3] for b in header) - 0.5
if plant == "centre": rail[0] += max(2, rail[2] / 100)
for b in header:
    if b[0] < inset - 1 or b[1] < inset - 1 or b[0] + b[2] > width - inset + 1 or b[1] + b[3] > height - inset + 1:
        out.append("inset box=%s" % [round(v, 2) for v in b])
if not header or not cards: out.append("order header=%d cards=%d" % (len(header), len(cards)))
else:
    card = max(cards, key=lambda b: b[2] * b[3])
    if max(b[1] + b[3] for b in header) > rail[1] + 1: out.append("order header.bottom=%.2f rail.top=%.2f" % (max(b[1] + b[3] for b in header), rail[1]))
    if card[1] < rail[1] - 1 or card[1] + card[3] > rail[1] + rail[3] + 1: out.append("order card=%s rail=%s" % (card, rail))
if abs(rail[0] - (width - rail[0] - rail[2])) > 1: out.append("centre left=%.2f right=%.2f" % (rail[0], width - rail[0] - rail[2]))
print(json.dumps(out))' "$1" "$2" "$3" "$4"
}
browser_planted() { # RULE
  local inset width height
  { read -r inset width height && browser_judge "$inset" "$width" "$height" "$1"; } <"$browser_kept" \
    | py_reply 'import json,sys; print(any(e.startswith(sys.argv[1] + " ") for e in json.load(sys.stdin)))' "$1"
}
click_overlay_scrim() {
  surface_box vgs:overlay | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print(int(x + max(1, min(w - 1, w / 100))), int(y + max(1, min(h - 1, h / 100))))' | while read -r x y; do click "$x" "$y"; done
}
geometry expect_poll "the browser's tabs and rail keep their places" '[]' browser_geometry
for rule in inset order centre; do
  expect "control: the browser's $rule rule refuses its planted box" True browser_planted "$rule"
done
expect_poll "every shown slice draws its theme's sixteen colours, opaque, two by eight over its wash" '[]' collapsed_stacks
type_keys -k Home || fail "sending Home before focus bind failed"
focus_first="$(card_at 0)"
focus_second="$(card_at 1)"
type_keys -M logo -k d -m logo || fail "sending the user's focus-right bind failed"
expect_poll "the user's focus-right bind moves the carousel inside the browser" "$focus_second" view_selected_name
type_keys -M logo -k a -m logo || fail "sending the user's focus-left bind failed"
expect_poll "the user's focus-left bind moves the carousel inside the browser" "$focus_first" view_selected_name
# A 2 s hold of Right and of SUPER+D, each from the first card, steps the
# rail as far, within the timing of two holds: Hyprland repeats the
# captured focus bind at the keyboard's repeat rate and delay, which Qt
# repeats Right at. Control: the layer with that bind's repeat removed,
# reloaded, steps once for the hold.
rail_index() { ipc smoke readDescendant overlay vgs.themes CardCarousel currentIndex; }
# held_steps WTYPE_ARGS...: from the first card, the index one hold the
# wtype arguments type leaves selected, read once two readings 0.2 s
# apart match.
held_steps() {
  local before="" now
  type_keys -k Home || return
  for _ in $(seq 1 50); do [[ "$(rail_index)" == 0 ]] && break; sleep 0.1; done
  type_keys "$@" || return
  for _ in $(seq 1 50); do
    now="$(rail_index)" || return
    if [[ $now == "$before" ]]; then echo "$now"; return; fi
    before="$now"; sleep 0.2
  done
  return 1
}
# steps_match ARROW SUPER: `match` when both holds stepped at least 5
# cards and within 3 plus a tenth of the arrow's steps of each other.
steps_match() { python3 -c 'import sys; a, s = map(int, sys.argv[1:]); print("match" if a >= 5 and s >= 5 and abs(a - s) <= 3 + a // 10 else "differs arrow=%d super=%d" % (a, s))' "$1" "$2"; }
arrow_steps="$(held_steps -P Right -s 2000 -p Right)" || fail "the held Right failed"
super_steps="$(held_steps -M logo -P d -s 2000 -p d -m logo)" || fail "the held SUPER+D failed"
echo "theme-browser: held-steps arrow=${arrow_steps:-none} super=${super_steps:-none}"
expect "holding SUPER+D steps the rail as holding Right does" match steps_match "${arrow_steps:-0}" "${super_steps:-0}"
hypr_layer="$home/.local/state/vgshell/hypr/vgs.lua"
cp -p -- "$hypr_layer" "$sandbox/vgs-layer-before-hold.lua"
python3 - "$hypr_layer" <<'PY' || fail "control: the layer copy without repeat is made"
import os, sys
path = sys.argv[1]
text = open(path).read()
old = "{ description = capture.globals[direction], repeating = true }"
assert text.count(old) == 1, "repeat binds=%d" % text.count(old)
with open(path + ".next", "w") as f:
    f.write(text.replace(old, "{ description = capture.globals[direction] }"))
os.replace(path + ".next", path)
PY
expect "control: the nested instance reloads the layer without repeat" ok hypr reload config-only
control_steps="$(held_steps -M logo -P d -s 2000 -p d -m logo)" || fail "control: the held SUPER+D failed"
echo "theme-browser: held-steps control=${control_steps:-none}"
expect "control: a focus bind without repeat steps once for the hold" 1 printf '%s\n' "${control_steps:-none}"
expect "control: a focus bind without repeat fails the hold check" "differs arrow=${arrow_steps:-0} super=1" steps_match "${arrow_steps:-0}" "${control_steps:-0}"
cp -p -- "$sandbox/vgs-layer-before-hold.lua" "$hypr_layer.next" && mv -T -- "$hypr_layer.next" "$hypr_layer" || fail "putting the layer back after the hold control failed"
expect "the nested instance reloads the layer with repeat" ok hypr reload config-only
press_themes || fail "closing the browser after the focus bind check failed"
expect_poll "the browser closes after the focus bind check" 0 layer_count vgs:overlay
press_themes || fail "reopening the browser after the focus bind check failed"
expect_poll "the browser reopens after the focus bind check" 1 layer_count vgs:overlay
browser_focused "the reopened browser holds the keyboard after the focus bind check"
expect_poll "the reopened browser read its cards after the focus bind check" true view_value loaded
first_card=akane

# A catalog card draws its package preview, and the colours of its own
# tokens across its foot.
type_keys "$first_card" || fail "typing $first_card failed"
expect_poll "the filter selects the catalog card" "\"$first_card\"" view_value selectedName
expect_poll "the catalog card draws its package preview" ready card_image "$repo/themes/catalog/$first_card/preview.jpg"
expect "the catalog card decodes at card size times screen scale" True card_source_size_matches "$repo/themes/catalog/$first_card/preview.jpg"
expect_poll "the selected card draws its sixteen colours, opaque, eight by two across the foot" '[]' expanded_foot
# The service reads the catalog again when its index changes, so the
# index is written again beside the changed slot.
python3 - "$repo/themes/catalog/$first_card/terminal.json" "$index" <<'PY'
import json, os, sys
terminal_file, index_file = sys.argv[1:]
terminal = json.load(open(terminal_file))
terminal["slots"]["color4"] = "#00ff00"
with open(terminal_file + ".next", "w") as f:
    json.dump(terminal, f)
os.replace(terminal_file + ".next", terminal_file)
doc = json.load(open(index_file))
with open(index_file + ".next", "w") as f:
    json.dump(doc, f)
os.replace(index_file + ".next", index_file)
PY
press_themes || fail "closing the browser for the terminal colour change failed"
expect_poll "the browser closes before the terminal colour check" 0 layer_count vgs:overlay
press_themes || fail "reopening the browser for the terminal colour change failed"
expect_poll "the browser reopens after the terminal colour change" 1 layer_count vgs:overlay
expect_poll "the browser rereads the changed terminal colours" true view_value loaded
type_keys "$first_card" || fail "typing $first_card after the terminal colour change failed"
expect_poll "the selected card holds the changed color4" '"#00ff00ff"' selected_slot color4
expect_poll "the selected card's foot follows the changed color4" '[]' expanded_foot
expect "the selected catalog card is not installed" False selected_installed
expect "a catalog card draws only its name and the typed filter beside the rail" "[\"Akane\", \"$first_card\"]" rest_texts

# Paging: Home, Right, Left and End move the selection.
type_keys -k Escape || fail "clearing the catalog-card filter failed"
expect_poll "the catalog-card filter clears" '""' view_value filterText
first_card="$(card_at 0)"
type_keys -k Home || fail "sending Home failed"
expect_poll "Home selects the first card" "\"$first_card\"" view_value selectedName
type_keys -k Right || fail "sending Right failed"
expect_poll "Right selects the second card" "\"$(card_at 1)\"" view_value selectedName
type_keys -k Left || fail "sending Left failed"
expect_poll "Left selects the first card again" "\"$first_card\"" view_value selectedName
type_keys -k End || fail "sending End failed"
expect_poll "End selects the last card" "\"$(card_at -1)\"" view_value selectedName
type_keys -k Home || fail "sending Home for Up and Down failed"
expect_poll "Home selects the first card before Up and Down" "\"$first_card\"" view_value selectedName
type_keys -k Down || fail "sending Down failed"
expect_poll "Down selects the second card" "\"$(card_at 1)\"" view_value selectedName
type_keys -k Up || fail "sending Up failed"
expect_poll "Up selects the first card again" "\"$first_card\"" view_value selectedName
type_keys -M ctrl -k Page_Down -m ctrl || fail "sending Ctrl+PageDown failed"
expect_poll "Ctrl+PageDown switches to the wallpaper view" '"wallpapers"' ipc smoke readInstance overlay vgs.themes view
type_keys -M ctrl -k Page_Up -m ctrl || fail "sending Ctrl+PageUp failed"
expect_poll "Ctrl+PageUp switches back to the theme view" '"themes"' ipc smoke readInstance overlay vgs.themes view

# The filter and the scope. The typed filter takes the hint's place on its
# line, so the rail keeps its place while it shows.
filter_rail="$(rail_top)" || fail "the rail's top before the filter is unreadable"
hint_line="$(text_line "Type a theme name to search")" || fail "the theme hint's line is unreadable"
type_keys "nor" || fail "typing the filter failed"
expect_poll "typing reaches the filter" '"nor"' view_value filterText
type_keys -M ctrl -k u -m ctrl || fail "sending Ctrl+U failed"
expect_poll "Ctrl+U clears the filter" '""' view_value filterText
type_keys "gruvy " || fail "typing a two-word theme filter failed"
expect_poll "Space in the theme filter stays text" '"gruvy "' view_value filterText
expect_poll "the two-word theme filter keeps the browser on the filter match" '["gruvy-glass"]' view_names
type_keys -M ctrl -k u -m ctrl || fail "clearing the two-word theme filter failed"
expect_poll "Ctrl+U clears the two-word filter" '""' view_value filterText
type_keys "nor" || fail "typing the filter after Ctrl+U failed"
expect_poll "typing reaches the filter after Ctrl+U" '"nor"' view_value filterText
type_keys -k BackSpace || fail "sending BackSpace failed"
expect_poll "BackSpace erases a character" '"no"' view_value filterText
type_keys "rd" || fail "typing the rest of the filter failed"
expect_poll "the filter leaves nord alone" '["nord"]' view_names
expect_poll "the footer shows the typed filter in place of the hint" '["Nord", "nord"]' rest_texts
expect "the typed filter sits on the hint's line, at its top and height" "$hint_line" text_line nord
expect "a typed filter leaves the rail where it was" held rail_held "$filter_rail"
expect "the selection moves to the one match" '"nord"' view_value selectedName
# Control: scripts/test-qml-unit.sh deletes CardCarousel's modelData rebind and tst_carousel.qml fails.
expect "the drawn centre theme card matches the selected name after filtering" '"nord"' ipc smoke currentThemeCardName overlay vgs.themes
expect_poll "nord's package preview wins over its installed wallpaper" "$repo/themes/catalog/nord/preview.jpg" selected_preview
expect_poll "nord's selected card draws preview.jpg" ready card_image "$repo/themes/catalog/nord/preview.jpg"
type_keys -M alt -k i -m alt || fail "sending Alt+I in the theme view failed"
expect "Alt+I leaves the filter" '"nord"' view_value filterText
expect "Alt+I leaves the catalog's nord in the one list" '["nord"]' view_names

# Enter installs nord, applies it, and offers its wallpapers; Not now
# leaves it applied without them.
type_keys -k Return || fail "sending Return failed"
expect_poll "Enter installs and applies nord" nord ipc smoke themeName
expect_poll "the offer follows the apply" nord offer_name
expect "the browser stays open for the offer" 1 layer_count vgs:overlay
expect "nord is installed as a catalog package" True bash -c '[[ -f $1/nord/.vgs-catalog.json ]] && echo True' _ "$installed"
expect "the Dialog names the theme and the archive's size" True dialog_has "Download wallpapers for Nord (1 MB)?"
type_keys -k Escape || fail "sending Escape to the wallpaper offer failed"
expect_poll "Escape withdraws the wallpaper offer" none offer_name
expect "Escape from the wallpaper offer leaves the browser open" 1 layer_count vgs:overlay
expect "Escape from the wallpaper offer downloads nothing" False catalog_imagery nord
browser_focused "the rail takes the keyboard back after Escape from the offer"

# Enter again applies nord and offers again; Download runs on the lane,
# shows its progress, holds the browser open, and applies nord again.
type_keys -k Return || fail "sending Return again failed"
expect_poll "applying nord again offers its wallpapers again" nord offer_name
type_keys -k Return || fail "sending Return to the Dialog failed"
expect_poll "Download runs the download" "download nord" job_step
expect_poll "the Dialog shows the download's progress" True dialog_has "Downloading 2 of 4 MB"
type_keys -k Escape || fail "sending Escape during the download failed"
press_themes || fail "typing SUPER+SHIFT+T during the download failed"
expect "Escape and SUPER+SHIFT+T leave the browser open during the download" 1 layer_count vgs:overlay
touch -- "$wallpaper_gate"
expect_poll "the download and the apply after it close the browser" 0 layer_count vgs:overlay
expect "the wallpapers are unpacked into nord" True bash -c '[[ -f $1/nord/backgrounds/a.jpg && -f $1/nord/backgrounds/b.jpg ]] && echo True' _ "$installed"
expect "the catalog records the wallpapers" True catalog_imagery nord
expect_poll "the apply after the download shows nord's first wallpaper" "\"$installed/nord/backgrounds/a.jpg\"" bg_current

# The installed nord's card still draws its catalog preview; Escape clears
# the filter, then closes.
press_themes || fail "typing SUPER+SHIFT+T to reopen failed"
expect_poll "SUPER+SHIFT+T opens the browser again" 1 layer_count vgs:overlay
browser_focused
expect_poll "the reopened browser selects the applied nord" '"nord"' view_value selectedName
expect_poll "the installed nord's card draws its catalog preview" ready card_image "$repo/themes/catalog/nord/preview.jpg"
type_keys "x" || fail "typing x failed"
expect_poll "x filters" '"x"' view_value filterText
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape clears the filter" '""' view_value filterText
expect "Escape with a filter keeps the browser open" 1 layer_count vgs:overlay
type_keys -k Escape || fail "sending Escape again failed"
expect_poll "Escape with no filter closes the browser" 0 layer_count vgs:overlay
# A filter no card matches shows the empty state; its Clear filter clears
# the filter and leaves the keyboard on the rail, so Right steps and
# Escape closes.
clear_filter() { # LABEL
  press_themes || { fail "$1: typing SUPER+SHIFT+T failed"; return 1; }
  expect_poll "$1: SUPER+SHIFT+T opens the browser" 1 layer_count vgs:overlay
  expect_poll "$1: the browser read its cards" true view_value loaded
  local rail
  rail="$(rail_top)" || { fail "$1: the rail's top before the filter is unreadable"; return 1; }
  type_keys zzqx || { fail "$1: typing the filter failed"; return 1; }
  expect_poll "$1: a filter no card matches empties the rail" 0 view_count
  expect "$1: the footer shows the filter no card matches" True rest_has zzqx
  expect "$1: the footer hides the hint while the filter shows" False rest_has "Type a theme name to search"
  expect "$1: a filter no card matches leaves the rail where it was" held rail_held "$rail"
  click_in vgs:overlay overlay vgs.themes Label "Clear filter" || { fail "$1: the click on Clear filter failed"; return 1; }
}
clear_filter "Clear filter"
expect_poll "Clear filter clears the filter" '""' view_value filterText
expect_poll "Clear filter leaves the keyboard on the rail" true rail_focused
cleared_on="$(selected_card)" || cleared_on="unreadable"
[[ $cleared_on == card=* ]] || fail "the card selected after Clear filter is unreadable: $cleared_on"
type_keys -k Right || fail "sending Right after Clear filter failed"
expect_poll "Right after Clear filter steps the rail" moved selection_moved "$cleared_on"
expect "the browser stays open after Right" 1 layer_count vgs:overlay
type_keys -k Escape || fail "sending Escape after Clear filter failed"
expect_poll "Escape after Clear filter closes the browser" 0 layer_count vgs:overlay
# Control: the closed browser answers a state word, which names no card
# and so reads as no move.
expect "control: a closed browser is no step of the rail" absent selection_moved "$cleared_on"
# SUPER+SHIFT+T closes the view it opened, and a click on the scrim closes it.
press_themes || fail "typing SUPER+SHIFT+T failed"
expect_poll "SUPER+SHIFT+T opens the browser" 1 layer_count vgs:overlay
press_themes || fail "typing SUPER+SHIFT+T again failed"
expect_poll "SUPER+SHIFT+T on the open theme view closes it" 0 layer_count vgs:overlay
expect "a summon over IPC opens the first view" ok ipc shell summon overlay vgs.themes '{}'
expect_poll "the summon maps the browser" 1 layer_count vgs:overlay
expect_poll "the summoned browser read its cards" true view_value loaded
click_overlay_scrim || fail "the click on the scrim failed"
expect_poll "a click on the scrim closes the browser" 0 layer_count vgs:overlay
# The band beside the cards lies in the browser's pane, whose body fits
# and so takes no press: the click reaches the scrim.
band_click "the band beside the cards" || fail "the click on the band beside the cards failed"
expect_poll "a click on the band beside the cards closes the browser" 0 layer_count vgs:overlay
expected_errors+=('summon host: vgs\.themes open\(\) failed: payload=')
expect "a payload naming no view is refused" "refused: open-failed=vgs.themes" ipc shell summon overlay vgs.themes '{"view":"fonts"}'
expect "a payload with an unknown key is refused" "refused: open-failed=vgs.themes" ipc shell summon overlay vgs.themes '{"view":"themes","source":"all"}'
expect_poll "a refused summon leaves no browser" 0 layer_count vgs:overlay

# An install whose apply fails leaves the theme installed: the cards are
# read again, so Enter retries the apply and not the install. The failure
# line lies under the pane, so the rail keeps its place when it shows.
press_themes || fail "typing SUPER+SHIFT+T for akane failed"
expect_poll "SUPER+SHIFT+T opens the browser for akane" 1 layer_count vgs:overlay
browser_focused
type_keys "akane" || fail "typing akane failed"
expect_poll "the filter selects akane" '"akane"' view_value selectedName
akane_rail="$(rail_top)" || fail "the rail's top before akane's failure is unreadable"
type_keys -k Return || fail "sending Return for akane failed"
expect_poll "the apply after the install fails with the runner's reason" '"Could not apply Akane. Another theme action is running. Wait for it to finish."' view_value problem
expect "a failure line leaves the rail where it was" held rail_held "$akane_rail"
expect "the install before the failed apply landed" True bash -c '[[ -f $1/akane/.vgs-catalog.json ]] && echo True' _ "$installed"
expect_poll "the cards read akane installed after the failed apply" True selected_installed
type_keys -k Return || fail "sending Return to retry akane failed"
expect_poll "Enter retries the apply" akane ipc smoke themeName
expect_poll "the retried apply offers akane's wallpapers" akane offer_name
click_in vgs:overlay overlay vgs.themes Button "Not now" || fail "the click on Not now for akane failed"
expect_poll "Not now withdraws akane's offer" none offer_name
type_keys -k Escape || fail "sending Escape to clear akane's filter failed"
type_keys -k Escape || fail "sending Escape to close after akane failed"
expect_poll "Escape twice closes the browser after akane" 0 layer_count vgs:overlay

# vgs applies from the browser, which closes it, since vgs offers nothing.
press_themes || fail "typing SUPER+SHIFT+T for vgs failed"
expect_poll "SUPER+SHIFT+T opens the browser for vgs" 1 layer_count vgs:overlay
browser_focused
type_keys "vgs" || fail "typing vgs failed"
expect_poll "the filter selects vgs" '"vgs"' view_value selectedName
type_keys -k Return || fail "sending Return for vgs failed"
expect_poll "Enter applies vgs" vgs ipc smoke themeName
expect_poll "an apply that offers nothing closes the browser" 0 layer_count vgs:overlay

# ---- the wallpaper view -----------------------------------------------------
# nord, applied with its two downloaded images, and a second headless
# output. The browser opens on the focused output; the rows read which one
# from the view and name the other.
wall_value() { ipc smoke readDescendant overlay vgs.themes WallpaperView "$1"; }
wall_keys() { wall_value shownCards | py_reply 'import json,sys; print(json.dumps([c["key"] for c in json.load(sys.stdin)]))'; }
wall_count() { wall_value shownCards | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
wall_selected() { wall_value selected | py_reply 'import json,sys; s=json.load(sys.stdin); print("none" if s is None else s["key"])'; }
# Whether the cards hold every KEY.
wall_has() { wall_value shownCards | py_reply 'import json,sys; keys=[c["key"] for c in json.load(sys.stdin)]; print(all(k in keys for k in sys.argv[1:]))' "$@"; }
wall_job() { wall_value job | py_reply 'import json,sys; j=json.load(sys.stdin); print("none" if j is None else j["step"])'; }
nord_a="$installed/nord/backgrounds/a.jpg"; nord_b="$installed/nord/backgrounds/b.jpg"; nord_c="$installed/nord/backgrounds/c.jpg"
wall_output=SMOKE-WALL
# scope_tones: whether All monitors and This monitor each draw in
# carousel.hintActive, as [all, this]; the chosen word does, the other
# carousel.hint.
scope_tones() {
  local text all this
  text="$(ipc smoke themeValue carousel.hintActive)" || return
  all="$(ipc smoke readMatchingDescendant overlay vgs.themes Label text "All monitors" color)" || return
  this="$(ipc smoke readMatchingDescendant overlay vgs.themes Label text "This monitor" color)" || return
  python3 -c '
import json, sys
# A colour reads as {r, g, b, a}, #rrggbb, or #aarrggbb, the form Theme
# publishes (shell/Commons/Theme.qml).
def rgba(text):
    value = json.loads(text)
    if isinstance(value, dict): return tuple(round(value[k] * 255) for k in "rgba")
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (2, 4, 6, 0)) if len(value) == 8 else tuple(int(value[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
text = rgba(sys.argv[1])
print(json.dumps([rgba(sys.argv[2]) == text, rgba(sys.argv[3]) == text]))' "$text" "$all" "$this"
}
# scope_weights: the font weights All monitors and This monitor draw at, as
# [all, this]; the chosen word draws at bodyStrong's, the other at itemHint's.
scope_weights() {
  local all this
  all="$(ipc smoke readMatchingDescendant overlay vgs.themes Label text "All monitors" font)" || return
  this="$(ipc smoke readMatchingDescendant overlay vgs.themes Label text "This monitor" font)" || return
  python3 -c 'import json,sys; print(json.dumps([json.loads(a)["weight"] for a in sys.argv[1:]]))' "$all" "$this"
}
fixture_image="$repo/scripts/smoke/fixtures/theme-image.jpg"
fixture_tall="$sandbox/theme-image-tall.jpg"
"$imagemagick" "$fixture_image" -resize 160x120\! "$fixture_tall"
# The width over the height of the file IMAGE, a JPEG, and of the ready card
# image drawing PATH, `none` while none is ready, each to one decimal place.
# A card decodes to cover its box, so its image keeps the file's ratio.
file_ratio() {
  python3 - "$1" <<'PY'
import struct, sys
d = open(sys.argv[1], "rb").read(); i = 2
while i < len(d):
    m, l = d[i + 1], struct.unpack(">H", d[i + 2:i + 4])[0]
    if m in (0xC0, 0xC1, 0xC2):
        h, w = struct.unpack(">HH", d[i + 5:i + 9]); print("%.1f" % (w / h)); break
    i += 2 + l
PY
}
card_ratio() { ipc smoke images overlay vgs.themes | py_reply 'import json,sys; r=[i[3] for i in json.load(sys.stdin) if i[0]==sys.argv[1] and i[1]=="ready"]; print("%.1f" % (r[0][0] / r[0][1]) if r else "none")' "$1"; }
# pin_nord ARCHIVE B_IMAGE: an archive holding b.jpg from B_IMAGE and a.jpg
# and c.jpg from the test image, pinned for nord in the sandbox copy's
# catalog, which the update card then offers.
pin_nord() {
  python3 - "$assets/themes/$1" "$2" "$fixture_image" "$index" <<'PY'
import hashlib, json, os, sys, tarfile
out, second, image, index = sys.argv[1:]
with tarfile.open(out, "w:gz") as tar:
    tar.add(image, arcname="backgrounds/a.jpg")
    tar.add(second, arcname="backgrounds/b.jpg")
    tar.add(image, arcname="backgrounds/c.jpg")
data = open(out, "rb").read()
doc = json.load(open(index))
nord = [e for e in doc["entries"] if e["name"] == "nord"][0]
nord["imagery"] = dict(nord["imagery"], archive=os.path.basename(out), size=len(data), sha256=hashlib.sha256(data).hexdigest())
with open(index + ".next", "w") as f:
    json.dump(doc, f)
os.replace(index + ".next", index)
PY
}
# plugin_control FILE LABEL OLD NEW: rescan vgs.themes with the OLD text of
# its FILE, which must occur once, replaced by NEW; plugin_restore FILE
# LABEL rescans it with the file put back. Each waits for the scan to
# publish a new revision of the plugin and for the follow after it.
themes_revision() { ipc shell listPlugins | py_reply 'import json,sys; print([p["revision"] for p in json.load(sys.stdin)["plugins"] if p["id"]=="vgs.themes"][0])'; }
themes_revised() { [[ $(themes_revision) != "$1" ]] && echo revised || echo same; }
themes_rescan() { # LABEL
  local before
  before="$(themes_revision)" || { fail "the revision before $1 is unreadable"; return; }
  rescan "a rescan builds $1"
  expect "the rescan publishes $1" revised themes_revised "$before"
  expect "the follow after the rescan for $1 ends" idle theme_idle
}
plugin_control() {
  local file="$repo/shell/plugins/vgs.themes/$1"
  cp -p -- "$file" "$sandbox/$1.real"
  python3 - "$sandbox/$1.real" "$file.tmp" "$3" "$4" <<'PY' || { fail "the $2 control's text occurs once in $1"; return; }
import pathlib, sys
src, dst, old, new = sys.argv[1:]
text = pathlib.Path(src).read_text()
assert text.count(old) == 1, "control text must match once: " + old
pathlib.Path(dst).write_text(text.replace(old, new))
PY
  mv -T -- "$file.tmp" "$file"
  themes_rescan "the $2 control"
}
plugin_restore() {
  local file="$repo/shell/plugins/vgs.themes/$1"
  cp -- "$sandbox/$1.real" "$file.tmp" && mv -T -- "$file.tmp" "$file"
  themes_rescan "the view the $2 control replaced"
}

# Control: a manifest copy that still binds the theme browser to SUPER+T.
# The bind reads the old key, and SUPER+SHIFT+T opens nothing: the SUPER+T
# typed after it, which would close a browser it opened, opens the browser.
plugin_control manifest.json "old theme key" '"shortcut": "themes", "key": "SUPER+SHIFT+T",' '"shortcut": "themes", "key": "SUPER+T",'
expect_poll "control: the copy binds SUPER+T to the theme browser" '[[64, "T"]]' themes_bind
press_themes || fail "typing SUPER+SHIFT+T for the old theme key control failed"
press_old_themes || fail "typing SUPER+T for the old theme key control failed"
expect_poll "control: SUPER+SHIFT+T on the copy opens nothing, so SUPER+T opens the browser" 1 layer_count vgs:overlay
type_keys -k Escape || fail "closing the old theme key control browser failed"
expect_poll "the old theme key control browser closes" 0 layer_count vgs:overlay
plugin_restore manifest.json "old theme key"
expect_poll "the restored manifest binds SUPER+SHIFT+T to the theme browser" '[[65, "T"]]' themes_bind

# Controls for the preview guarantees above.
plugin_control ThemeCard.qml "preview sourceSize" "sourceSize: root.decodeSize" "sourceSize: Qt.size(1, 1)"
press_themes || fail "typing SUPER+SHIFT+T for the preview sourceSize control failed"
expect_poll "the sourceSize control opens the theme browser" 1 layer_count vgs:overlay
expect_poll "the sourceSize control read its cards" true view_value loaded
type_keys -k Home || fail "sending Home for the sourceSize control failed"
expect_poll "control: the card no longer decodes at card size times scale" False card_source_size_matches "$repo/themes/catalog/$first_card/preview.jpg"
type_keys -k Escape || fail "closing the sourceSize control browser failed"
expect_poll "the sourceSize control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeCard.qml "preview sourceSize"

# Control for the slice names: a card copy whose slice name is empty.
plugin_control ThemeCard.qml "slice name" $'        text: root.modelData.label\n        color: Theme.carousel.sliceName.foreground' $'        text: ""\n        color: Theme.carousel.sliceName.foreground'
press_themes || fail "typing SUPER+SHIFT+T for the slice name control failed"
expect_poll "the slice name control opens the theme browser" 1 layer_count vgs:overlay
expect_poll "the slice name control read its cards" true view_value loaded
expect_poll "control: side cards without their names read as unnamed" unnamed slices_unnamed
type_keys -k Escape || fail "closing the slice name control browser failed"
expect_poll "the slice name control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeCard.qml "slice name"
# Control for the slice names' look: a card copy whose name is centred on
# its slice, reads down it, draws in h3 and the text colour, and has no
# shadow, each a finding of its own.
plugin_control ThemeCard.qml "slice look" $'        role: Theme.carousel.sliceName.role\n        x: (parent.width - parent.height * Math.tan(root.lean)) / 2 + inset * Math.sin(root.lean)\n        y: parent.height - inset * Math.cos(root.lean) - height / 2\n        width: Math.min(implicitWidth, parent.height / Math.cos(root.lean) - 2 * inset)\n        transformOrigin: Item.Left\n        rotation: root.lean * 180 / Math.PI - 90\n        visible: !root.expanded && root.swatches !== null\n        elide: Text.ElideRight\n        text: root.modelData.label\n        color: Theme.carousel.sliceName.foreground\n        layer.enabled: visible' $'        role: "h3"\n        x: (parent.width - parent.height * Math.tan(root.lean)) / 2 + inset * Math.sin(root.lean)\n        y: (parent.height - height) / 2\n        width: Math.min(implicitWidth, parent.height / Math.cos(root.lean) - 2 * inset)\n        transformOrigin: Item.Left\n        rotation: root.lean * 180 / Math.PI + 90\n        visible: !root.expanded && root.swatches !== null\n        elide: Text.ElideRight\n        text: root.modelData.label\n        color: Theme.color.text\n        layer.enabled: false'
press_themes || fail "typing SUPER+SHIFT+T for the slice look control failed"
expect_poll "the slice look control opens the theme browser" 1 layer_count vgs:overlay
expect_poll "the slice look control read its cards" true view_value loaded
expect_poll "control: a centred, downward, h3, text-coloured name without a shadow reads as each broken rule" '["colour", "inset", "role", "shadow", "upward"]' slice_look
type_keys -k Escape || fail "closing the slice look control browser failed"
expect_poll "the slice look control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeCard.qml "slice look"
# Control for the name over the wash: a card copy that keeps its name with
# the rest of the card, under the side card's dim wash.
plugin_control ThemeCard.qml "slice name wash" $'        parent: root.foreground ?? root\n        // The carousel hands' $'        parent: root\n        // The carousel hands'
press_themes || fail "typing SUPER+SHIFT+T for the slice name wash control failed"
expect_poll "the slice name wash control opens the theme browser" 1 layer_count vgs:overlay
expect_poll "the slice name wash control read its cards" true view_value loaded
expect_poll "control: a name drawn with the card's content reads as under the wash" '["wash"]' slice_look
type_keys -k Escape || fail "closing the slice name wash control browser failed"
expect_poll "the slice name wash control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeCard.qml "slice name wash"

plugin_control ThemeCard.qml "preview precedence" "readonly property bool packagePreview: typeof modelData.previewImage === \"string\" && modelData.previewImage !== \"\"" "readonly property bool packagePreview: false"
press_themes || fail "typing SUPER+SHIFT+T for the preview precedence control failed"
expect_poll "the preview precedence control opens the theme browser" 1 layer_count vgs:overlay
expect_poll "the preview precedence control read its cards" true view_value loaded
type_keys "nord" || fail "typing nord for the preview precedence control failed"
expect_poll "the preview precedence control selects nord" '"nord"' view_value selectedName
expect "control: nord no longer draws preview.jpg first" none card_image "$repo/themes/catalog/nord/preview.jpg"
type_keys -k Escape || fail "clearing the preview precedence control filter failed"
type_keys -k Escape || fail "closing the preview precedence control browser failed"
expect_poll "the preview precedence control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeCard.qml "preview precedence"

# Controls for the recovery flow and the band: a copy of the theme view
# whose Clear filter clears nothing, and one whose rail band takes the
# press.
plugin_control ThemeView.qml "clear filter" 'onActivated: root.editFilter({ kind: "clear" })' 'onActivated: {}'
clear_filter "control: the clear filter copy"
expect "control: a Clear filter that clears nothing keeps the filter" '"zzqx"' view_value filterText
type_keys -k Escape || fail "clearing the clear filter control's filter failed"
type_keys -k Escape || fail "closing the clear filter control failed"
expect_poll "the clear filter control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeView.qml "clear filter"
plugin_control ThemeView.qml "rail band" '            // No card to show: the list loading, no theme at all, or a' $'            MouseArea { anchors.fill: parent }\n            // No card to show: the list loading, no theme at all, or a'
band_click "control: a rail band that takes the press" || fail "the rail band control's click failed"
expect "control: a band that takes the press leaves the browser open" 1 layer_count vgs:overlay
expect "the rail band control browser hides" ok ipc shell hide overlay vgs.themes
expect_poll "the rail band control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeView.qml "rail band"
# Control for the rail's place under a typed filter: a copy of the theme
# view whose search line takes the height of the text it shows, so the
# filter's taller text grows the centred pane and the line.
plugin_control ThemeView.qml "growing line" 'height: Math.max(hintLine.height, typed.height)' 'height: root.filterText === "" ? hintLine.height : typed.height'
press_themes || fail "typing SUPER+SHIFT+T for the growing line control failed"
expect_poll "SUPER+SHIFT+T opens the growing line control browser" 1 layer_count vgs:overlay
expect_poll "the growing line control read its cards" true view_value loaded
grown_rail="$(rail_top)" || fail "the rail's top before the growing line control's filter is unreadable"
grown_line="$(text_line "Type a theme name to search")" || fail "the growing line control's hint line is unreadable"
type_keys "nord" || fail "typing nord for the growing line control failed"
expect_poll "the growing line control's filter selects nord" '"nord"' view_value selectedName
expect "control: a line that grows with the typed filter moves the rail" moved bash -c 'echo "${1%% *}"' _ "$(rail_held "$grown_rail")"
expect "control: a line that grows with the typed filter is not the hint's" True bash -c '[[ $1 != "$2" && $1 != lines=* ]] && echo True' _ "$(text_line nord)" "$grown_line"
expect "the growing line control browser hides" ok ipc shell hide overlay vgs.themes
expect_poll "the growing line control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeView.qml "growing line"
# Control for the rail's place under a failure: a copy of the theme view
# whose caption grows with the failures, as a failure line in the pane's
# footer grew it. akane's apply answers busy once more, and the centred
# pane moves the rail up when the line shows.
plugin_control ThemeView.qml "growing column" $'                id: caption\n' $'                id: caption\n                bottomPadding: failures.height\n'
rm -- "$akane_refused" || fail "the growing column control's busy answer is not armed"
press_themes || fail "typing SUPER+SHIFT+T for the growing column control failed"
expect_poll "SUPER+SHIFT+T opens the growing column control browser" 1 layer_count vgs:overlay
expect_poll "the growing column control read its cards" true view_value loaded
type_keys "akane" || fail "typing akane for the growing column control failed"
expect_poll "the growing column control's filter selects akane" '"akane"' view_value selectedName
grown_rail="$(rail_top)" || fail "the rail's top before the growing column control's failure is unreadable"
type_keys -k Return || fail "sending Return for the growing column control failed"
expect_poll "the growing column control's apply fails" '"Could not apply Akane. Another theme action is running. Wait for it to finish."' view_value problem
expect "control: a caption that grows with the failures moves the rail" moved bash -c 'echo "${1%% *}"' _ "$(rail_held "$grown_rail")"
expect "the growing column control browser hides" ok ipc shell hide overlay vgs.themes
expect_poll "the growing column control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeView.qml "growing column"
# Control for the resting texts: a copy of the theme view that draws a key
# hint under the rail.
plugin_control ThemeView.qml "resting text" $'                id: caption\n' $'                id: caption\n                Label { role: "hint"; text: "Enter" }\n'
press_themes || fail "typing SUPER+SHIFT+T for the resting text control failed"
expect_poll "SUPER+SHIFT+T opens the resting text control browser" 1 layer_count vgs:overlay
expect_poll "the resting text control read its cards" true view_value loaded
expect_poll "control: a key hint under the rail is a resting text" '["Enter", "Type a theme name to search", "VGS"]' rest_texts
type_keys -k Escape || fail "sending Escape to the resting text control failed"
expect_poll "Escape closes the resting text control browser" 0 layer_count vgs:overlay
plugin_restore ThemeView.qml "resting text"
# Control for the search field: a copy of the theme view that draws one.
search_field_line=$'                id: caption\n'
search_field_copy=$'                id: caption\n                TextField { width: parent.width; text: root.filterText }\n'
plugin_control ThemeView.qml "search field" "$search_field_line" "$search_field_copy"
press_themes || fail "typing SUPER+SHIFT+T for the search field control failed"
expect_poll "SUPER+SHIFT+T opens the search field control browser" 1 layer_count vgs:overlay
expect_poll "the search field control read its cards" true view_value loaded
expect "control: a theme view with a search field draws one" true search_field
expect "the search field control browser hides" ok ipc shell hide overlay vgs.themes
expect_poll "the search field control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeView.qml "search field"

# vgs, applied, ships Black; a click on the source line's Show all
# switches to all, turns the line to Show theme and leaves the keys with
# the view, so Alt+S flips it back. Controls: a copy whose line flips
# nothing, one whose line takes the keyboard, and one whose line keeps its
# first text.
vgs_black="$repo/themes/vgs/backgrounds/black.png"
show_every() { # LABEL
  press_wallpapers || { fail "$1: typing SUPER+SHIFT+W failed"; return 1; }
  expect_poll "$1: SUPER+SHIFT+W opens the browser" 1 layer_count vgs:overlay
  expect_poll "$1: the wallpaper view read its lists" true ipc smoke readDescendant overlay vgs.themes WallpaperView loaded
  expect "$1: vgs's theme source lists Black" "[\"$vgs_black\"]" wall_keys
  click_in vgs:overlay overlay vgs.themes Label "Show all" || { fail "$1: the click on Show all failed"; return 1; }
}
show_every "the source line"
expect_poll "the source line's Show all shows every source" '"all"' ipc smoke readDescendant overlay vgs.themes WallpaperView source
expect_poll "the source line then reads Show theme" True rest_has "Show theme"
type_keys -M alt -k s -m alt || fail "sending Alt+S after the source line's click failed"
expect_poll "the source line leaves the keys with the view" '"theme"' ipc smoke readDescendant overlay vgs.themes WallpaperView source
expect_poll "Alt+S puts Show all back on the source line" True rest_has "Show all"
type_keys -k Escape || fail "sending Escape after the source line's click failed"
expect_poll "Escape after the source line's click closes the browser" 0 layer_count vgs:overlay
plugin_control WallpaperView.qml "source line" 'onClicked: root.flipSource()' 'onClicked: {}'
show_every "control: the source line copy"
expect "control: a source line that flips nothing keeps the theme source" '"theme"' ipc smoke readDescendant overlay vgs.themes WallpaperView source
expect "the source line control browser hides" ok ipc shell hide overlay vgs.themes
expect_poll "the source line control browser closes" 0 layer_count vgs:overlay
plugin_restore WallpaperView.qml "source line"
plugin_control WallpaperView.qml "source line keys" 'onClicked: root.flipSource()' 'onClicked: { root.flipSource(); forceActiveFocus(); }'
show_every "control: the source line keys copy"
expect_poll "the source line keys control shows every source" '"all"' ipc smoke readDescendant overlay vgs.themes WallpaperView source
type_keys -M alt -k s -m alt || fail "sending Alt+S to the source line keys control failed"
expect "control: a source line that takes the keys leaves Alt+S unread" '"all"' ipc smoke readDescendant overlay vgs.themes WallpaperView source
expect "the source line keys control browser hides" ok ipc shell hide overlay vgs.themes
expect_poll "the source line keys control browser closes" 0 layer_count vgs:overlay
plugin_restore WallpaperView.qml "source line keys"
plugin_control WallpaperView.qml "source line text" 'text: BrowserLogic.WALLPAPER_SOURCES[root.sourceIndex].switchLabel' 'text: BrowserLogic.WALLPAPER_SOURCES[0].switchLabel'
show_every "control: the source line text copy"
expect_poll "the source line text control shows every source" '"all"' ipc smoke readDescendant overlay vgs.themes WallpaperView source
expect "control: a source line that keeps its first text never reads Show theme" False rest_has "Show theme"
expect "the source line text control browser hides" ok ipc shell hide overlay vgs.themes
expect_poll "the source line text control browser closes" 0 layer_count vgs:overlay
plugin_restore WallpaperView.qml "source line text"

expect "the follow before the wallpaper rows ends" idle theme_idle
expect "nord applies for the wallpaper rows" "ok theme=nord state=applied shell=applied" vgshell_theme apply nord
expect_poll "the shell follows nord" nord ipc smoke themeName
expect "the nested compositor adds a monitor for the wallpaper rows" ok hypr output create headless "$wall_output"
expect_poll "the wallpaper rows' monitor is listed" True screen_listed "$wall_output"
expect_poll "the wallpaper rows' monitor draws nord's first image" "$nord_a ready" background_image_on "$wall_output"

press_wallpapers || fail "typing SUPER+SHIFT+W failed"
expect_poll "SUPER+SHIFT+W opens the browser" 1 layer_count vgs:overlay
expect "the browser shows the wallpaper view" '"wallpapers"' ipc smoke readInstance overlay vgs.themes view
browser_focused "the wallpaper view holds the keyboard"
expect_poll "the wallpaper view read the images and the catalog" true wall_value loaded
if ! this_screen="$(wall_value screenName | tr -d '"')"; then fail "reading the wallpaper view's screen failed"; this_screen=""; fi
if [[ $this_screen == "$wall_output" ]]; then other_screen="$screen_name"; else other_screen="$wall_output"; fi
expect "the wallpaper view shows on one of the two outputs" True python3 -c 'import sys; print(sys.argv[1] in sys.argv[2:])' "$this_screen" "$screen_name" "$wall_output"
expect "the view starts on the theme source" '"theme"' wall_value source
expect "the theme source lists nord's images and no card" "[\"$nord_a\", \"$nord_b\"]" wall_keys
expect "the view starts on every monitor" '"every"' wall_value scope
expect "two screens show the scope control" true wall_value scoped
expect_poll "the selection starts on the image every screen shows" "$nord_a" wall_selected
expect "the wallpaper card decodes at card size times screen scale" True card_source_size_matches "$nord_a"
expect_poll "the resting wallpaper view draws its hint line and scope line alone" '["/", "All monitors", "Apply to:", "Show all", "This monitor", "Type a wallpaper or image file name to search", "|"]' rest_texts
expect "the wallpaper view draws no search field" absent search_field

# The wallpaper filter: text reaches the filter, filters the rail, Space
# stays text, Ctrl+U clears, Clear filter works from the empty state, and
# Escape clears before it closes.
wall_rail="$(rail_top)" || fail "the wallpaper rail's top before the filter is unreadable"
wall_line="$(text_line "Type a wallpaper or image file name to search")" || fail "the wallpaper hint's line is unreadable"
wall_show_all="$(text_top "Show all")" || fail "the resting Show all's top is unreadable"
wall_divider="$(text_top "|")" || fail "the resting divider's top is unreadable"
pointer_off_line || fail "moving the pointer off the wallpaper search line failed"
wall_show_all_px="$(settled_show_all_pixels)" || fail "the resting Show all's pixels are unreadable"
for wall_typed in a gyp Nord; do
  type_keys "$wall_typed" || fail "typing $wall_typed for Show all's pixels failed"
  expect_poll "the wallpaper filter reads $wall_typed" "\"$wall_typed\"" wall_value filterText
  expect_poll "a typed $wall_typed leaves Show all's pixels as at rest" same show_all_against "$wall_show_all_px"
  type_keys -M ctrl -k u -m ctrl || fail "clearing $wall_typed failed"
  expect_poll "Ctrl+U clears $wall_typed" '""' wall_value filterText
done
type_keys "b." || fail "typing the wallpaper filter failed"
expect_poll "typing reaches the wallpaper filter" '"b."' wall_value filterText
expect_poll "the wallpaper filter keeps b.jpg alone" "[\"$nord_b\"]" wall_keys
# The divider before Show all belongs to the source line and stays.
expect_poll "the wallpaper footer shows the typed filter in place of the hint" '["/", "All monitors", "Apply to:", "Show all", "This monitor", "b.", "|"]' rest_texts
expect "the typed wallpaper filter sits on the hint's line, at its top and height" "$wall_line" text_line b.
expect "a typed wallpaper filter leaves Show all on its rest row" "$wall_show_all" text_top "Show all"
expect "a typed wallpaper filter leaves the divider on its rest row" "$wall_divider" text_top "|"
expect "a typed wallpaper filter leaves the rail where it was" held rail_held "$wall_rail"
type_keys -k space || fail "sending Space to the wallpaper filter failed"
expect_poll "Space in the wallpaper filter stays text" '"b. "' wall_value filterText
type_keys -M ctrl -k u -m ctrl || fail "clearing the wallpaper filter failed"
expect_poll "Ctrl+U clears the wallpaper filter" '""' wall_value filterText
type_keys "zzqx" || fail "typing the empty wallpaper filter failed"
expect_poll "a wallpaper filter no card matches empties the rail" 0 wall_count
expect "the wallpaper footer shows the filter no card matches" True rest_has zzqx
expect "a wallpaper filter no card matches leaves the rail where it was" held rail_held "$wall_rail"
click_in vgs:overlay overlay vgs.themes Label "Clear filter" || fail "the wallpaper Clear filter click failed"
expect_poll "Clear filter clears the wallpaper filter" '""' wall_value filterText
expect_poll "Clear filter puts the wallpaper hint back" True rest_has "Type a wallpaper or image file name to search"
type_keys "b." || fail "typing the wallpaper filter before Escape failed"
expect_poll "the wallpaper filter is set before Escape" '"b."' wall_value filterText
type_keys -k Escape || fail "sending Escape with a wallpaper filter failed"
expect_poll "Escape clears the wallpaper filter" '""' wall_value filterText
expect "Escape with a wallpaper filter keeps the browser open" 1 layer_count vgs:overlay
type_keys -k Escape || fail "sending Escape after clearing the wallpaper filter failed"
expect_poll "Escape with no wallpaper filter closes the browser" 0 layer_count vgs:overlay
# Control: a wallpaper view whose source line centres on its Row, which
# the taller typed filter grows, so typing moves Show all.
plugin_control WallpaperView.qml "row-centred source line" 'y: BrowserLogic.inkCentredTop(searchSlot.height, sourceText.y + sourceText.capTop(), sourceText.y + sourceText.lastBaseline())' 'anchors.verticalCenter: parent.verticalCenter'
press_wallpapers || fail "typing SUPER+SHIFT+W for the row-centred source line control failed"
expect_poll "SUPER+SHIFT+W opens the row-centred source line control browser" 1 layer_count vgs:overlay
expect_poll "the row-centred source line control view read its lists" true wall_value loaded
centred_show_all="$(text_top "Show all")" || fail "the row-centred source line control's resting Show all is unreadable"
type_keys "b." || fail "typing the row-centred source line control's filter failed"
expect_poll "the row-centred source line control's filter reads b." '"b."' wall_value filterText
expect "control: a source line centred on its Row leaves Show all's rest row when a filter is typed" True bash -c '[[ $1 != "$2" && -n $1 ]] && echo True' _ "$(text_top "Show all")" "$centred_show_all"
type_keys -M ctrl -k u -m ctrl || fail "clearing the row-centred source line control's filter failed"
expect "the row-centred source line control browser hides" ok ipc shell hide overlay vgs.themes
expect_poll "the row-centred source line control browser closes" 0 layer_count vgs:overlay
plugin_restore WallpaperView.qml "row-centred source line"

# Control: a wallpaper view whose typed filter takes its fractional width,
# so Show all after it starts at a fractional x for some filters.
plugin_control WallpaperView.qml "fractional filter width" 'width: Math.ceil(Math.min(implicitWidth, ' 'width: (Math.min(implicitWidth, '
press_wallpapers || fail "typing SUPER+SHIFT+W for the fractional filter width control failed"
expect_poll "SUPER+SHIFT+W opens the fractional filter width control browser" 1 layer_count vgs:overlay
expect_poll "the fractional filter width control view read its lists" true wall_value loaded
pointer_off_line || fail "moving the pointer off the fractional filter width control's line failed"
fractional_rest="$(settled_show_all_pixels)" || fail "the fractional filter width control's resting Show all is unreadable"
fractional_moved=0
for wall_typed in a gyp Nord; do
  type_keys "$wall_typed" || fail "typing $wall_typed for the fractional filter width control failed"
  expect_poll "the fractional filter width control's filter reads $wall_typed" "\"$wall_typed\"" wall_value filterText
  fractional_now="$(settled_show_all_pixels)" || fail "the fractional filter width control's Show all with $wall_typed is unreadable"
  [[ $(pixels_near "$fractional_now" "$fractional_rest") == same ]] || fractional_moved=$((fractional_moved + 1))
  type_keys -M ctrl -k u -m ctrl || fail "clearing $wall_typed in the fractional filter width control failed"
  expect_poll "Ctrl+U clears $wall_typed in the fractional filter width control" '""' wall_value filterText
done
expect "control: a fractional filter width changes Show all's pixels for some typed filter" True bash -c '[[ $1 -gt 0 ]] && echo True' _ "$fractional_moved"
expect "the fractional filter width control browser hides" ok ipc shell hide overlay vgs.themes
expect_poll "the fractional filter width control browser closes" 0 layer_count vgs:overlay
plugin_restore WallpaperView.qml "fractional filter width"

plugin_control WallpaperView.qml "search field" "$search_field_line" "$search_field_copy"
press_wallpapers || fail "typing SUPER+SHIFT+W for the wallpaper search field control failed"
expect_poll "SUPER+SHIFT+W opens the wallpaper search field control browser" 1 layer_count vgs:overlay
expect_poll "the wallpaper search field control view read its lists" true wall_value loaded
expect "control: a wallpaper view with a search field draws one" true search_field
expect "the wallpaper search field control browser hides" ok ipc shell hide overlay vgs.themes
expect_poll "the wallpaper search field control browser closes" 0 layer_count vgs:overlay
plugin_restore WallpaperView.qml "search field"

plugin_control WallpaperView.qml "wallpaper typing" $'case "":\n                if (event.key === Qt.Key_Backspace' $'case "":\n                return;\n                if (event.key === Qt.Key_Backspace'
press_wallpapers || fail "typing SUPER+SHIFT+W for the wallpaper typing control failed"
expect_poll "SUPER+SHIFT+W opens the wallpaper typing control browser" 1 layer_count vgs:overlay
expect_poll "the wallpaper typing control view read its lists" true wall_value loaded
wallpaper_typing_control_failures() {
  (failures=0; behaviour_failures=0
  type_keys "b." >/dev/null || fail "control: typing the wallpaper filter failed"
  expect_poll "control: typing reaches the wallpaper filter" '"b."' wall_value filterText >"$sandbox/wallpaper-typing-control.log"
  echo "$failures")
}
expect "control: a wallpaper view that returns before typing fails the filter assertion" 1 wallpaper_typing_control_failures
expect "the wallpaper typing control browser hides" ok ipc shell hide overlay vgs.themes
expect_poll "the wallpaper typing control browser closes" 0 layer_count vgs:overlay
plugin_restore WallpaperView.qml "wallpaper typing"
press_wallpapers || fail "typing SUPER+SHIFT+W after the wallpaper typing control failed"
expect_poll "SUPER+SHIFT+W opens the browser after the wallpaper typing control" 1 layer_count vgs:overlay
expect_poll "the wallpaper view read the images after the typing control" true wall_value loaded

# The toggles: Alt+S flips the source, Alt+M flips the scope, and
# Tab and Shift+Tab switch the top tabs. None moves the selected card.
type_keys -M alt -k s -m alt || fail "sending Alt+S failed"
expect_poll "Alt+S shows every source" '"all"' wall_value source
expect_poll "every source lists nord's images" True wall_has "$nord_a" "$nord_b"
expect_poll "every source turns the source line to Show theme" True rest_has "Show theme"
type_keys "black" || fail "typing black in every source failed"
expect_poll "Show all filters to Black alone" "[\"$vgs_black\"]" wall_keys
type_keys -M ctrl -k u -m ctrl || fail "clearing the Black wallpaper filter failed"
expect_poll "Ctrl+U clears the Black wallpaper filter" '""' wall_value filterText
type_keys -M alt -k s -m alt || fail "sending Alt+S again failed"
expect_poll "Alt+S shows the theme again" '"theme"' wall_value source
type_keys -k Tab || fail "sending Tab failed"
expect_poll "Tab switches to the theme view" '"themes"' ipc smoke readInstance overlay vgs.themes view
type_keys -M shift -k Tab -m shift || fail "sending Shift+Tab failed"
expect_poll "Shift+Tab switches back to the wallpaper view" '"wallpapers"' ipc smoke readInstance overlay vgs.themes view
type_keys -M ctrl -k Tab -m ctrl || fail "sending Ctrl+Tab in the wallpaper view failed"
expect_poll "Ctrl+Tab switches to the theme view" '"themes"' ipc smoke readInstance overlay vgs.themes view
type_keys -M ctrl -M shift -k Tab -m shift -m ctrl || fail "sending Ctrl+Shift+Tab in the theme view failed"
expect_poll "Ctrl+Shift+Tab switches back to the wallpaper view" '"wallpapers"' ipc smoke readInstance overlay vgs.themes view
type_keys -M alt -k m -m alt || fail "sending Alt+M failed"
expect_poll "Alt+M flips the scope to this monitor" '"this"' wall_value scope
expect_poll "Alt+M moves no card while the scope shows" "$nord_a" wall_selected
type_keys -M alt -k m -m alt || fail "sending Alt+M again failed"
expect_poll "Alt+M flips the scope back" '"every"' wall_value scope
type_keys -M alt -k m -m alt || fail "sending Alt+M for this monitor failed"
expect_poll "Alt+M flips the scope to this monitor again" '"this"' wall_value scope

# This monitor: Return sets b.jpg on the browser's screen alone and closes.
type_keys -k Right || fail "sending Right failed"
expect_poll "Right selects b.jpg" "$nord_b" wall_selected
type_keys -k Return || fail "sending Return for this monitor failed"
expect_poll "Return sets this monitor and closes the browser" 0 layer_count vgs:overlay
expect_poll "the browser's screen draws b.jpg" "$nord_b ready" background_image_on "$this_screen"
expect "the other screen keeps nord's first image" "$nord_a ready" background_image_on "$other_screen"
expect "a set for this monitor keeps the current image" "\"$nord_a\"" bg_current

# Each open starts on every monitor; This monitor selects the screen's own
# image, and All monitors sets the current image on every screen, the
# screen's own cleared.
press_wallpapers || fail "typing SUPER+SHIFT+W to reopen failed"
expect_poll "SUPER+SHIFT+W opens the browser again" 1 layer_count vgs:overlay
expect_poll "the reopened view read its lists" true wall_value loaded
expect "the reopened view is on every monitor again" '"every"' wall_value scope
expect_poll "every monitor selects the current image" "$nord_a" wall_selected
type_keys -M alt -k m -m alt || fail "sending Alt+M to this monitor failed"
expect_poll "this monitor selects the screen's own image" "$nord_b" wall_selected
type_keys -M alt -k m -m alt || fail "sending Alt+M to every monitor failed"
expect_poll "every monitor selects the current image again" "$nord_a" wall_selected
type_keys -k Return || fail "sending Return for every monitor failed"
expect_poll "a set for every monitor closes the browser" 0 layer_count vgs:overlay
expect_poll "the browser's screen draws a.jpg again" "$nord_a ready" background_image_on "$this_screen"
expect "the other screen draws a.jpg" "$nord_a ready" background_image_on "$other_screen"
expect "a set for every monitor clears each screen's own image" '{}' bg_screens

# Control: a copy of the view that sets every image as the current one
# moves the other screen's image under This monitor.
plugin_control WallpaperView.qml scope "shell.theme.set(card.path, BrowserLogic.setScreen(scope, screenName), result => {" "shell.theme.set(card.path, null, result => {"
press_wallpapers || fail "typing SUPER+SHIFT+W for the scope control failed"
expect_poll "SUPER+SHIFT+W opens the scope control's browser" 1 layer_count vgs:overlay
expect_poll "the scope control's view read its lists" true wall_value loaded
type_keys -M alt -k m -m alt -k Right || fail "sending Alt+M and Right to the scope control failed"
expect_poll "the scope control selects b.jpg for this monitor" "$nord_b" wall_selected
type_keys -k Return || fail "sending Return to the scope control failed"
expect_poll "the scope control's set closes the browser" 0 layer_count vgs:overlay
expect_poll "the scope control moves the other screen's image too" "$nord_b ready" background_image_on "$other_screen"
plugin_restore WallpaperView.qml scope
expect "set --every-screen puts nord's first image back on every screen" "ok background=a.jpg theme=nord path=$nord_a screen=*" vgshell_theme background set "$nord_a" --every-screen

# A click on a scope word chooses that scope, draws it brighter and bolder
# and leaves the keyboard with the view: Right then steps the rail and
# leaves the scope. Controls: copies whose words draw one colour, and one
# weight.
press_wallpapers || fail "typing SUPER+SHIFT+W for the scope word click failed"
expect_poll "SUPER+SHIFT+W opens the browser for the scope word click" 1 layer_count vgs:overlay
expect_poll "the scope word view selects a.jpg" "$nord_a" wall_selected
expect "the chosen All monitors draws brighter than This monitor" '[true, false]' scope_tones
expect "the chosen All monitors draws bolder than This monitor" '[600, 400]' scope_weights
click_in vgs:overlay overlay vgs.themes Label "This monitor" || fail "the click on This monitor failed"
expect_poll "a click on This monitor chooses it" '"this"' wall_value scope
expect_poll "the clicked This monitor draws brighter than All monitors" '[false, true]' scope_tones
expect_poll "the clicked This monitor draws bolder than All monitors" '[400, 600]' scope_weights
browser_focused "a click on a scope word leaves the keyboard with the view"
type_keys -k Right || fail "sending Right after the scope word click failed"
expect_poll "Right after the click steps the rail" "$nord_b" wall_selected
expect "Right after the click leaves the scope" '"this"' wall_value scope
type_keys -k Escape || fail "sending Escape after the scope word click failed"
expect_poll "Escape closes the browser after the scope word click" 0 layer_count vgs:overlay
plugin_control WallpaperView.qml "scope tone" 'color: chosen ? Theme.carousel.hintActive : ' 'color: '
press_wallpapers || fail "typing SUPER+SHIFT+W for the scope tone control failed"
expect_poll "SUPER+SHIFT+W opens the scope tone control's browser" 1 layer_count vgs:overlay
expect_poll "the scope tone control's view read its lists" true wall_value loaded
expect "control: words that draw one colour show no chosen word" '[false, false]' scope_tones
expect "the scope tone control browser hides" ok ipc shell hide overlay vgs.themes
expect_poll "the scope tone control browser closes" 0 layer_count vgs:overlay
plugin_restore WallpaperView.qml "scope tone"
plugin_control WallpaperView.qml "scope weight" 'readonly property int weight: chosen ? Theme.text.bodyStrong.weight : typography.weight' 'readonly property int weight: typography.weight'
press_wallpapers || fail "typing SUPER+SHIFT+W for the scope weight control failed"
expect_poll "SUPER+SHIFT+W opens the scope weight control's browser" 1 layer_count vgs:overlay
expect_poll "the scope weight control's view read its lists" true wall_value loaded
expect "control: words that draw one weight show no bolder word" '[400, 400]' scope_weights
expect "the scope weight control browser hides" ok ipc shell hide overlay vgs.themes
expect_poll "the scope weight control browser closes" 0 layer_count vgs:overlay
plugin_restore WallpaperView.qml "scope weight"
# Controls for the slices: a copy of the theme card whose stack is one
# column, one whose stack reverses its colours, and one whose stack sits
# under the wash.
for control in grid colours wash; do
  case $control in
    grid) plugin_control ThemeCard.qml "stack $control" $'        columns: 2\n' $'        columns: 1\n' ;;
    colours) plugin_control ThemeCard.qml "stack $control" $'columns: 2\n        colours: root.swatches === null ? [] : root.swatches' $'columns: 2\n        colours: root.swatches === null ? [] : root.swatches.slice().reverse()' ;;
    wash) plugin_control ThemeCard.qml "stack $control" $'        parent: root.foreground ?? root\n        anchors.fill: parent\n' $'        anchors.fill: parent\n' ;;
  esac
  press_themes || fail "typing SUPER+SHIFT+T for the stack $control control failed"
  expect_poll "SUPER+SHIFT+T opens the stack $control control browser" 1 layer_count vgs:overlay
  expect_poll "the stack $control control read its cards" true view_value loaded
  expect_poll "control: the stack $control copy breaks the $control rule" True judged_rule collapsed_stacks "$control"
  type_keys -k Escape || fail "sending Escape to the stack $control control failed"
  expect_poll "Escape closes the stack $control control browser" 0 layer_count vgs:overlay
  plugin_restore ThemeCard.qml "stack $control"
done

# The update card: the catalog pins a newer archive, which replaces b.jpg
# under its name with an image of another shape and adds c.jpg. Enter on
# it runs the update form on the download lane, applies nord again, reads
# the lists again, loads every card's image again and stays open. Each
# card image is read back by the ratio it decodes to. A changed generation
# makes the card image URL change; a copy that drops that stamp keeps Qt's
# old decode for the same path.
# Qt reloads an Image when sourceSize changes (Qt 6 Image documentation).
# Keep this control's decode at the native size so carousel movement cannot
# replace the cached decode independently of the URL generation.
plugin_control WallpaperCard.qml identity $'Files.stampedUrl(root.modelData.path, root.modelData.generation)\n        sourceSize: root.decodeSize' 'Files.fileUrl(root.modelData.path)'
pin_nord vgs-theme-nord-smoke2.tar.gz "$fixture_tall"
press_wallpapers || fail "typing SUPER+SHIFT+W for the identity control failed"
expect_poll "SUPER+SHIFT+W opens the identity control's browser" 1 layer_count vgs:overlay
expect_poll "the theme source ends with the update card" "[\"$nord_a\", \"$nord_b\", \"update\"]" wall_keys
expect_poll "the identity control draws nord's b.jpg" "$(file_ratio "$fixture_image")" card_ratio "$nord_b"
type_keys -k End || fail "sending End failed"
expect_poll "End selects the update card" update wall_selected
type_keys -k Return || fail "sending Return to the identity control's update card failed"
expect_poll "the identity control's update, apply and lists end" none wall_job
expect "the identity control's update left no problem" '""' wall_value problem
expect_poll "the theme source lists the third image and no card" "[\"$nord_a\", \"$nord_b\", \"$nord_c\"]" wall_keys
expect "the update replaced b.jpg on disk" True bash -c 'cmp -s -- "$1" "$2" && echo True' _ "$fixture_tall" "$nord_b"
expect "control: an unstamped image URL keeps drawing the replaced b.jpg's old picture" "$(file_ratio "$fixture_image")" card_ratio "$nord_b"
type_keys -k Escape || fail "sending Escape to the identity control failed"
expect_poll "Escape closes the identity control's browser" 0 layer_count vgs:overlay
plugin_restore WallpaperCard.qml identity
pin_nord vgs-theme-nord-smoke3.tar.gz "$fixture_image"
press_wallpapers || fail "typing SUPER+SHIFT+W for the update failed"
expect_poll "SUPER+SHIFT+W opens the browser for the update" 1 layer_count vgs:overlay
expect_poll "a new open draws the b.jpg the last update replaced" "$(file_ratio "$fixture_tall")" card_ratio "$nord_b"
expect_poll "the theme source ends with the next update card" "[\"$nord_a\", \"$nord_b\", \"$nord_c\", \"update\"]" wall_keys
type_keys -k End || fail "sending End for the update failed"
expect_poll "End selects the next update card" update wall_selected
type_keys -k Return || fail "sending Return to the update card failed"
expect_poll "the update, the apply after it and the lists end" none wall_job
expect "the update left no problem" '""' wall_value problem
expect "the update keeps the browser open" 1 layer_count vgs:overlay
expect_poll "the rail draws the b.jpg the update replaced" "$(file_ratio "$fixture_image")" card_ratio "$nord_b"
expect "the update unpacks the third image" True bash -c '[[ -f $1 ]] && echo True' _ "$nord_c"
type_keys -k Escape || fail "sending Escape after the update failed"
expect_poll "Escape closes the browser after the update" 0 layer_count vgs:overlay

# One screen: no scope control, Alt+M does nothing and Tab switches tabs.
expect "the nested compositor removes the wallpaper rows' monitor" ok hypr output remove "$wall_output"
expect_poll "the wallpaper rows' monitor is gone" False screen_listed "$wall_output"
press_wallpapers || fail "typing SUPER+SHIFT+W on one screen failed"
expect_poll "SUPER+SHIFT+W opens the browser on one screen" 1 layer_count vgs:overlay
expect_poll "the one-screen view read its lists" true wall_value loaded
expect "one screen shows no scope control" false wall_value scoped
expect_poll "one screen selects the current image" "$nord_a" wall_selected
type_keys -M alt -k m -m alt || fail "sending Alt+M on one screen failed"
expect "Alt+M on one screen leaves every monitor" '"every"' wall_value scope
type_keys -k Tab || fail "sending Tab on one screen failed"
expect_poll "Tab on one screen switches to the theme view" '"themes"' ipc smoke readInstance overlay vgs.themes view
type_keys -M shift -k Tab -m shift || fail "sending Shift+Tab on one screen failed"
expect_poll "Shift+Tab on one screen switches back to the wallpaper view" '"wallpapers"' ipc smoke readInstance overlay vgs.themes view
press_wallpapers || fail "typing SUPER+SHIFT+W to close failed"
expect_poll "SUPER+SHIFT+W on the open wallpaper view closes it" 0 layer_count vgs:overlay
expect "the follow after the wallpaper rows ends" idle theme_idle
expect "vgs applies after the wallpaper rows" "ok theme=vgs state=applied shell=applied" vgshell_theme apply vgs
expect_poll "the shell follows vgs after the wallpaper rows" vgs ipc smoke themeName

browser_slot_origins() {
  ipc smoke descendantGeometry overlay vgs.themes | py_reply '
import json,sys
rows = json.load(sys.stdin)
slots = [r for r in rows if r["type"] == "QQuickItem" and r["visible"] and r["box"][2] > 0 and r["box"][3] > 0 and r["parent"] != -1 and rows[r["parent"]]["type"] in ("BrowserSlot", "BrowserEmptyState")]
search = any(rows[r["parent"]]["type"] == "BrowserSlot" for r in slots)
print("whole" if search and all(abs(v-round(v)) < 0.0001 for r in slots for v in r["box"][:2]) else "fractional-or-no-search-line")'
}
plant_flexoki_light "$installed" || fail "the empty-state light package could not be installed"
for empty_theme in vgs flexoki-light; do
  if [[ $empty_theme != vgs ]]; then
    expect "the empty-state check applies $empty_theme" "ok theme=$empty_theme state=applied shell=applied" vgshell_theme apply "$empty_theme"
  fi
  expect_poll "the empty-state check follows $empty_theme" "$empty_theme" ipc smoke themeName
  for empty_view in themes wallpapers; do
    "press_$empty_view" || fail "opening the $empty_theme $empty_view empty-state check failed"
    expect_poll "the $empty_theme $empty_view empty-state check opens" 1 layer_count vgs:overlay
    empty_value=view_value; [[ $empty_view == wallpapers ]] && empty_value=wall_value
    expect_poll "the $empty_theme $empty_view empty-state check read its lists" true "$empty_value" loaded
    geometry expect "the $empty_theme $empty_view resting lines start on whole rows and columns" whole browser_slot_origins
    if [[ $empty_theme == flexoki-light && $empty_view == wallpapers ]]; then
      expect_poll "the no-wallpaper state has no cards" 0 wall_count
      empty_unfiltered="$(ipc smoke readDescendant overlay vgs.themes BrowserEmptyState text)" || fail "reading the no-wallpapers line failed"
    fi
    for empty_filter in a gyp Nord; do
      type_keys "$empty_filter" || fail "typing $empty_filter for the line-origin check failed"
      expect_poll "the $empty_theme $empty_view line-origin filter reads $empty_filter" "\"$empty_filter\"" "$empty_value" filterText
      geometry expect "the $empty_theme $empty_view $empty_filter lines start on whole rows and columns" whole browser_slot_origins
      type_keys -M ctrl -k u -m ctrl || fail "clearing the line-origin filter failed"
      expect_poll "the line-origin filter clears" '""' "$empty_value" filterText
    done
    type_keys zzqx || fail "typing the $empty_theme $empty_view empty-state filter failed"
    expect_poll "the $empty_theme $empty_view empty-state filter is set" '"zzqx"' "$empty_value" filterText
    geometry expect "the $empty_theme $empty_view filtered lines start on whole rows and columns" whole browser_slot_origins
    if [[ $empty_theme == flexoki-light && $empty_view == wallpapers ]]; then
      expect "the no-wallpapers line stays under the filter" "$empty_unfiltered" ipc smoke readDescendant overlay vgs.themes BrowserEmptyState text
      expect "the no-wallpapers state offers no filter action" '""' ipc smoke readDescendant overlay vgs.themes BrowserEmptyState actionText
    fi
    expect "the $empty_theme $empty_view empty-state check hides" ok ipc shell hide overlay vgs.themes
    expect_poll "the $empty_theme $empty_view empty-state check closes" 0 layer_count vgs:overlay
  done
done
# The current text-choice control treats any typed filter as the cause,
# even on an image-free source. It must fail the same state comparison.
plugin_control BrowserLogic.js "current empty-state text choice" 'filter !== "" && cards.some(function (card) { return card.kind === "image"; })' 'filter !== ""'
press_wallpapers || fail "opening the empty-state text-choice control failed"
expect_poll "the empty-state text-choice control opens" 1 layer_count vgs:overlay
expect_poll "the empty-state text-choice control read its lists" true wall_value loaded
empty_unfiltered="$(ipc smoke readDescendant overlay vgs.themes BrowserEmptyState text)" || fail "reading the text-choice control line failed"
type_keys zzqx || fail "typing the text-choice control filter failed"
expect_poll "the text-choice control filter is set" '"zzqx"' wall_value filterText
empty_line_held() {
  local now
  now="$(ipc smoke readDescendant overlay vgs.themes BrowserEmptyState text)" || return
  [[ $now == "$empty_unfiltered" ]] && echo held || echo changed
}
expect "control: the current text choice changes the no-wallpapers line under a filter" changed empty_line_held
expect "the empty-state text-choice control hides" ok ipc shell hide overlay vgs.themes
expect_poll "the empty-state text-choice control closes" 0 layer_count vgs:overlay
plugin_restore BrowserLogic.js "current empty-state text choice"
# The origin control keeps the slot and its text but shifts them a
# quarter row, so the whole-coordinate assertion must reject it.
plugin_control BrowserSlot.qml "fractional slot row" 'y: Math.round(origin.y) - origin.y' 'y: Math.round(origin.y) - origin.y + 0.25'
press_wallpapers || fail "opening the fractional slot row control failed"
expect_poll "the fractional slot row control opens" 1 layer_count vgs:overlay
expect_poll "the fractional slot row control read its lists" true wall_value loaded
geometry expect "control: a fractionally shifted slot fails the whole-row check" fractional-or-no-search-line browser_slot_origins
expect "the fractional slot row control hides" ok ipc shell hide overlay vgs.themes
expect_poll "the fractional slot row control closes" 0 layer_count vgs:overlay
plugin_restore BrowserSlot.qml "fractional slot row"
expect "vgs applies after the empty-state checks" "ok theme=vgs state=applied shell=applied" vgshell_theme apply vgs
expect_poll "the shell follows vgs after the empty-state checks" vgs ipc smoke themeName
rm -r -- "$installed/flexoki-light"

expect "disabling vgs.themes after the browser rows is allowed" ok ipc shell setPluginEnabled vgs.themes false
expect_poll "disabling vgs.themes released its shortcut" '[]' lent_themes
expect_poll "disabling vgs.themes unbinds SUPER+SHIFT+T" '[]' themes_bind
expect_poll "disabling vgs.themes unbinds SUPER+SHIFT+W" '[]' themes_bind wallpapers
cp -p -- "$sandbox/hyprland-before-browser.lua" "$hypr_lua.next" && mv -T -- "$hypr_lua.next" "$hypr_lua"
expect "the nested instance reloads the hyprland.lua the browser rows found" ok hypr reload config-only
mv -T -- "$repo/bin/vgshell.real" "$repo/bin/vgshell"
cp -p -- "$sandbox/catalog-index.json" "$index"
rm -r -- "$installed/nord" "$installed/akane" "$assets" "$wallpaper_gate" "$akane_refused"
rm -f -- "$bg_state/backgrounds.json" "$bg_state/background"
