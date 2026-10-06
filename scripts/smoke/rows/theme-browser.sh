# The theme browser, vgs.themes' overlay and service: SUPER+CTRL+T on the
# nested seat opens it, and every row reads what it holds back through the
# probe: the view's cards and state through readDescendant, the images the
# cards draw through images, the texts it draws beside its rail and tabs
# through descendantGeometry, and its Dialog's through itemTexts. The rows page, filter, install and apply a catalog
# entry, and answer the wallpaper offer both ways. akane's first wallpaper waits in the
# preview cache as a fetch leaves it, so its card draws that file and never
# the catalog thumbnail. The old keys, SUPER+T
# and SUPER+W, open nothing, and each view's key moves an open browser to
# that view; a manifest copy still bound to SUPER+T is their control. The sandbox copy's
# catalog pins nord's wallpapers to an archive this row builds, served from
# a file:// base, which the runner takes under the sandbox's test-run
# marker. A stand-in holds the download behind a gate after two progress
# lines, polled every 50 ms for at most 30 s, so the Dialog's progress and
# the held close read back before the real download runs. The wallpaper
# view's rows, SUPER+CTRL+W, follow the theme view's: they flip its source,
# from its source line and from Alt+S, and its scope, set an image for one screen and for every screen on a second
# headless output and read each screen's drawn image back, and run the
# update card against a second archive the catalog pins anew. A copy of
# WallpaperView.qml that sets every image as the current one is their
# control. rows/themes.sh defines the helpers used here and leaves the
# plugin disabled, and rows/theme-browse.sh leaves vgs applied, no current
# wallpaper and nord not installed; this file enables the plugin and
# leaves all four so.
# inputs: shell/plugins/vgs.themes/* themes/catalog/* shell/Core/ThemeRunner.qml bin/vgshell bin/lib/theme-* shell/Ui/layout/CardCarousel.qml shell/Ui/feedback/Dialog.qml bin/vgshell-theme-judge shell/Core/ShortcutRegistry.qml shell/Core/Plugins.qml scripts/smoke/rows/themes.sh scripts/smoke/rows/theme-browse.sh scripts/smoke/rows/hyprland-consent.sh
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
offer_name() { view_value offer | py_reply 'import json,sys; o=json.load(sys.stdin); print("none" if o is None else o["name"])'; }
# rest_texts: every text the browser draws outside its rail and its tabs,
# sorted and once each; rest_has TEXT: whether TEXT is one of them. At rest
# the theme view draws none, and the wallpaper view its source line and,
# with two screens, its scope control.
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
rest_has() { rest_texts | py_reply 'import json,sys; print(sys.argv[1] in json.load(sys.stdin))' "$1"; }
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
# SUPER+CTRL+T and SUPER+CTRL+W typed on the nested seat, and the keys
# the two browsers had before them.
press_themes() { type_keys -M logo -M ctrl -k t -m ctrl -m logo; }
press_wallpapers() { type_keys -M logo -M ctrl -k w -m ctrl -m logo; }
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
# A card's eight colours from its own palette and tokens, written out here
# apart from BrowserLogic: the palette's background, the raised surface,
# then the palette's foreground, accent, info, success, warning and danger.
theme_eight_py='
def eight(card):
    p, c = card.get("palette") or {}, (card.get("tokens") or {}).get("color") or {}
    v = [p.get("background"), c.get("surfaceRaised"), p.get("foreground"), p.get("accent"), p.get("info"), p.get("success"), p.get("warning"), p.get("danger")]
    return v if all(isinstance(x, str) for x in v) else None
'
# collapsed_stacks: one finding per broken rule, `[]` the pass. Every
# shown slice, a visible paletteStack, is 8 bands across its whole width,
# stacked top to bottom with no gap, each an eighth of its height
# (`vertical`), in the eight colours of a shown theme, top first
# (`colours`); and at least 3 slices show (`stacks`). The strips and their
# drawn colours are read in the probe's one tree order.
collapsed_stacks() {
  local shown colours
  shown="$(view_value shownCards)" || return
  colours="$(ipc smoke itemColours overlay vgs.themes ThemePaletteStrip QQuickRectangle)" || return
  ipc smoke descendantGeometry overlay vgs.themes | py_reply "$theme_eight_py"'
import json, sys
rows, shown, colours = json.load(sys.stdin), json.loads(sys.argv[1]), json.loads(sys.argv[2])
want = [w for w in (eight(c) for c in shown if c.get("state") == "ok") if w is not None]
strips = [i for i, r in enumerate(rows) if r["type"] == "ThemePaletteStrip"]
if len(strips) != len(colours):
    print(json.dumps(["readers strips=%d colours=%d" % (len(strips), len(colours))])); sys.exit()
out, stacks = [], 0
for k, i in enumerate(strips):
    x, y, w, h = rows[i]["box"]
    if rows[i]["name"] != "paletteStack" or not rows[i]["visible"] or w <= 0 or h <= 0: continue
    stacks += 1
    bands = sorted((r["box"] for r in rows if r["parent"] == i and r["type"] == "QQuickRectangle" and r["visible"]), key=lambda b: (b[1], b[0]))
    at = y
    for b in bands:
        if len(bands) != 8 or abs(b[0] - x) > 1 or abs(b[2] - w) > 1 or abs(b[1] - at) > 1 or abs(b[3] - h / 8) > 1:
            out.append("vertical stack=%d bands=%d band=%s stack=%s" % (k, len(bands), [round(v, 2) for v in b], [round(v, 2) for v in rows[i]["box"]])); break
        at = b[1] + b[3]
    if colours[k] not in want: out.append("colours stack=%d got=%s" % (k, colours[k]))
if stacks < 3: out.append("stacks shown=%d" % stacks)
print(json.dumps(out))' "$shown" "$colours"
}
# expanded_preview: the same for the selected card, read once its desktop
# shows. One visible paletteStrip lies along the card's foot as 8 bands
# side by side, left to right with no gap, each an eighth of its width
# (`strip`), in the selected theme's eight colours, left first
# (`strip-colours`); the terminal, the Settings window and the
# launcher's search lie inside the card above that strip, stand apart and
# cover less than half the card, so the wallpaper shows (`windows`); and
# the desktop draws the theme's raised surface, accent and background
# (`windows-colours`).
expanded_preview() {
  local selected strips drawn scale
  selected="$(view_value selected)" || return
  scale="$(ipc smoke readDescendant overlay vgs.themes DesktopPreview scale)" || return
  strips="$(ipc smoke itemColours overlay vgs.themes ThemePaletteStrip QQuickRectangle)" || return
  drawn="$(ipc smoke itemColours overlay vgs.themes DesktopPreview QQuickRectangle)" || return
  ipc smoke descendantGeometry overlay vgs.themes | py_reply "$theme_eight_py"'
import json, sys
rows, card, strips, drawn, scale = json.load(sys.stdin), json.loads(sys.argv[1]), json.loads(sys.argv[2]), json.loads(sys.argv[3]), json.loads(sys.argv[4])
want, out = eight(card), []
def shown(r): return r["visible"] and r["box"][2] > 0 and r["box"][3] > 0
cards = [r["box"] for r in rows if r["type"] == "AngledCard" and shown(r)]
feet = [(k, i) for k, i in enumerate(i for i, r in enumerate(rows) if r["type"] == "ThemePaletteStrip") if rows[i]["name"] == "paletteStrip" and shown(rows[i])]
if want is None or not cards or len(feet) != 1 or len(drawn) != 1 or not isinstance(scale, (int, float)):
    print(json.dumps(["readers eight=%s cards=%d strips=%d previews=%d scale=%s" % (want is not None, len(cards), len(feet), len(drawn), scale)])); sys.exit()
cx, cy, cw, ch = max(cards, key=lambda b: b[2] * b[3])
k, i = feet[0]
sx, sy, sw, sh = rows[i]["box"]
bands = sorted((r["box"] for r in rows if r["parent"] == i and r["type"] == "QQuickRectangle" and r["visible"]), key=lambda b: (b[0], b[1]))
at = sx
if abs(sy + sh - (cy + ch)) > 1 or abs(sw - cw) > 1: out.append("strip strip=%s card=%s" % (rows[i]["box"], [cx, cy, cw, ch]))
for b in bands:
    if len(bands) != 8 or abs(b[1] - sy) > 1 or abs(b[3] - sh) > 1 or abs(b[0] - at) > 1 or abs(b[2] - sw / 8) > 1:
        out.append("strip bands=%d band=%s strip=%s" % (len(bands), [round(v, 2) for v in b], [round(v, 2) for v in rows[i]["box"]])); break
    at = b[0] + b[2]
if strips[k] != want: out.append("strip-colours got=%s want=%s" % (strips[k], want))
boxes = {}
for name in ("previewTerminal", "previewWindow", "previewLauncher"):
    found = [r["box"] for r in rows if r["name"] == name and shown(r)]
    if len(found) != 1: out.append("windows %s=%d" % (name, len(found))); continue
    # The desktop draws at its reference size scaled to the card, and the
    # reader gives a box its own size at its scaled origin.
    boxes[name] = [found[0][0], found[0][1], found[0][2] * scale, found[0][3] * scale]
for name, (x, y, w, h) in boxes.items():
    if x < cx - 1 or y < cy - 1 or x + w > cx + cw + 1 or y + h > sy + 1: out.append("windows outside %s=%s card=%s" % (name, [round(v, 2) for v in (x, y, w, h)], [cx, cy, cw, ch]))
names = sorted(boxes)
for a in range(len(names)):
    for b in range(a + 1, len(names)):
        (ax, ay, aw, ah), (bx, by, bw, bh) = boxes[names[a]], boxes[names[b]]
        if not (ax + aw <= bx + 1 or bx + bw <= ax + 1 or ay + ah <= by + 1 or by + bh <= ay + 1): out.append("windows overlap %s %s" % (names[a], names[b]))
if sum(w * h for x, y, w, h in boxes.values()) >= cw * ch / 2: out.append("windows cover=%.0f card=%.0f" % (sum(w * h for x, y, w, h in boxes.values()), cw * ch))
for colour in (want[1], want[3], want[0]):
    if colour not in drawn[0]: out.append("windows-colours missing=%s" % colour)
print(json.dumps(out))' "$selected" "$strips" "$drawn" "$scale"
}
# judged_rule JUDGE RULE: whether JUDGE reports a finding of RULE.
judged_rule() { "$1" | py_reply 'import json,sys; print(any(e.startswith(sys.argv[1] + " ") for e in json.load(sys.stdin)))' "$2"; }

# The fixture archive and nord's pin to it, in the sandbox copy's catalog.
index="$repo/themes/catalog/index.json"
cp -p -- "$index" "$sandbox/catalog-index.json"
assets="$sandbox/theme-assets"
mkdir -p -- "$assets/themes"
python3 - "$repo/themes/catalog/nord/preview.png" <<'PY'
import base64, sys
open(sys.argv[1], "wb").write(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="))
PY
python3 - "$assets/themes/vgs-theme-nord-smoke.tar.gz" "$repo/themes/catalog/thumbnails/nord.jpg" "$index" <<'PY'
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

# akane's first wallpaper as a preview fetch caches it, before the service
# reads the catalog.
akane_preview="$home/.cache/vgshell/theme-assets/previews/$(python3 -c 'import json,sys; print([e["imagery"]["sha256"] for e in json.load(open(sys.argv[1]))["entries"] if e["name"] == "akane"][0])' "$index")-a.jpg"
mkdir -p -- "${akane_preview%/*}"
cp -- "$repo/themes/catalog/thumbnails/akane.jpg" "$akane_preview"
# The service registers the shortcut and the layer binds SUPER+CTRL+T.
expect "enabling vgs.themes for the browser rows is allowed" ok ipc shell setPluginEnabled vgs.themes true
expect_poll "the themes service registered its shortcuts" '["vgs.themes:gaps", "vgs.themes:panel", "vgs.themes:themes", "vgs.themes:wallpapers"]' lent_themes
expect_poll "the nested instance binds SUPER+CTRL+T to the theme browser" '[[68, "T"]]' themes_bind
expect_poll "the nested instance binds SUPER+CTRL+W to the wallpaper browser" '[[68, "W"]]' themes_bind wallpapers
themes_global() { hypr globalshortcuts | python3 -c 'import sys; print(sum(1 for line in sys.stdin if "vgs.themes:themes" in line))'; }
expect_poll "the compositor lists the themes shortcut" 1 themes_global
# wtype types on a virtual keyboard with keycodes of its own, which a bind
# resolves only by keysym, so the sandbox user's settings turn that on
# for these rows, as rows/hyprland.sh does for its own (docs/architecture/
# runtime-hyprland.md), and the file is put back after them.
hypr_lua="$home/.config/hypr/hyprland.lua"
cp -p -- "$hypr_lua" "$sandbox/hyprland-before-browser.lua"
{
  printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })'
  printf '%s\n' 'hl.bind("SUPER + A", hl.dsp.focus({ direction = "left" }), { description = "Smoke focus left" })'
  printf '%s\n' 'hl.bind("SUPER + D", hl.dsp.focus({ direction = "right" }), { description = "Smoke focus right" })'
} >>"$hypr_lua"
expect "the nested instance reloads with binds resolved by keysym and smoke focus keys" ok hypr reload config-only
expect "no browser shows before SUPER+CTRL+T" 0 layer_count vgs:overlay
# The old keys open nothing: each goes just before the new key of the same
# browser, which would close a browser the old key opened. Inside one
# browser the other browser's key switches the view, and its own key
# closes it.
press_old_wallpapers || fail "typing SUPER+W failed"
press_wallpapers || fail "typing SUPER+CTRL+W after SUPER+W failed"
expect_poll "SUPER+W opens nothing, so SUPER+CTRL+W opens the browser" 1 layer_count vgs:overlay
expect_poll "SUPER+CTRL+W opens the wallpaper view" '"wallpapers"' ipc smoke readInstance overlay vgs.themes view
press_themes || fail "typing SUPER+CTRL+T in the wallpaper view failed"
expect_poll "SUPER+CTRL+T in the wallpaper view switches to the theme view" '"themes"' ipc smoke readInstance overlay vgs.themes view
expect "the switch to the theme view keeps the browser open" 1 layer_count vgs:overlay
press_wallpapers || fail "typing SUPER+CTRL+W in the theme view failed"
expect_poll "SUPER+CTRL+W in the theme view switches to the wallpaper view" '"wallpapers"' ipc smoke readInstance overlay vgs.themes view
expect "the switch to the wallpaper view keeps the browser open" 1 layer_count vgs:overlay
press_wallpapers || fail "typing SUPER+CTRL+W to close the switched browser failed"
expect_poll "SUPER+CTRL+W on the switched wallpaper view closes it" 0 layer_count vgs:overlay
# SUPER+CTRL+T opens the theme view on the applied theme.
press_old_themes || fail "typing SUPER+T failed"
press_themes || fail "typing SUPER+CTRL+T failed"
expect_poll "SUPER+T opens nothing, so SUPER+CTRL+T opens the browser" 1 layer_count vgs:overlay
expect "the browser shows the theme view" '"themes"' ipc smoke readInstance overlay vgs.themes view
browser_focused "the open browser holds the keyboard"
expect_poll "the browser read the list, the catalog and the images" true view_value loaded
expect "the browser includes the shipped vgs card" True has_card vgs
expect_poll "the retained catalog reaches the installed list with nord" True has_card nord
expect "the applied theme is selected" '"vgs"' view_value selectedName
expect_poll "the resting theme view draws the selected theme's name alone beside its cards and tabs" '["Vgs"]' rest_texts
expect_poll "every side card names its theme" named slices_named
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
expect_poll "every shown slice stacks its theme's eight colours top to bottom" '[]' collapsed_stacks
type_keys -k Home || fail "sending Home before focus bind failed"
focus_first="$(card_at 0)"
focus_second="$(card_at 1)"
type_keys -M logo -k d -m logo || fail "sending the user's focus-right bind failed"
expect_poll "the user's focus-right bind moves the carousel inside the browser" "$focus_second" view_selected_name
type_keys -M logo -k a -m logo || fail "sending the user's focus-left bind failed"
expect_poll "the user's focus-left bind moves the carousel inside the browser" "$focus_first" view_selected_name
press_themes || fail "closing the browser after the focus bind check failed"
expect_poll "the browser closes after the focus bind check" 0 layer_count vgs:overlay
press_themes || fail "reopening the browser after the focus bind check failed"
expect_poll "the browser reopens after the focus bind check" 1 layer_count vgs:overlay
browser_focused "the reopened browser holds the keyboard after the focus bind check"
expect_poll "the reopened browser read its cards after the focus bind check" true view_value loaded
first_card=akane

# A catalog card draws its cached wallpaper, never its thumbnail, and its
# live preview from its own tokens.
type_keys "$first_card" || fail "typing $first_card failed"
expect_poll "the filter selects the catalog card" "\"$first_card\"" view_value selectedName
expect_poll "the catalog card draws its cached wallpaper" ready card_image "$akane_preview"
expect "the catalog card draws no thumbnail" none card_image "$repo/themes/catalog/thumbnails/$first_card.jpg"
expect "the catalog card decodes at card size times screen scale" True card_source_size_matches "$akane_preview"
expect_poll "the selected card draws its desktop with windows and its eight colours across the foot" '[]' expanded_preview
before_accent="$(ipc smoke readDescendant overlay vgs.themes DesktopPreview accentHex)" || before_accent=""
python3 - "$repo/themes/catalog/$first_card/theme.json" "$index" "$first_card" <<'PY'
import json, os, sys
theme_file, index_file, name = sys.argv[1:]
theme = json.load(open(theme_file))
theme.setdefault("tokens", {}).setdefault("palette", {})["accent"] = "#00ff00"
with open(theme_file + ".next", "w") as f:
    json.dump(theme, f)
os.replace(theme_file + ".next", theme_file)
doc = json.load(open(index_file))
for entry in doc["entries"]:
    if entry["name"] == name:
        entry["palette"]["accent"] = "#00ff00ff"
with open(index_file + ".next", "w") as f:
    json.dump(doc, f)
os.replace(index_file + ".next", index_file)
PY
press_themes || fail "closing the browser for the live preview token change failed"
expect_poll "the browser closes before the live preview token check" 0 layer_count vgs:overlay
press_themes || fail "reopening the browser for the live preview token change failed"
expect_poll "the browser reopens after the live preview token change" 1 layer_count vgs:overlay
expect_poll "the browser rereads the changed package tokens" true view_value loaded
type_keys "$first_card" || fail "typing $first_card after the token change failed"
expect_poll "the live preview changes when the package accent changes" '"#00ff00"' ipc smoke readDescendant overlay vgs.themes DesktopPreview accentHex
expect_poll "the live preview's desktop and foot follow the changed accent" '[]' expanded_preview
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

# The filter and the scope.
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
expect "the selection moves to the one match" '"nord"' view_value selectedName
# Control: scripts/test-qml-unit.sh deletes CardCarousel's modelData rebind and tst_carousel.qml fails.
expect "the drawn centre theme card matches the selected name after filtering" '"nord"' ipc smoke currentThemeCardName overlay vgs.themes
expect_poll "nord's package preview wins over its thumbnail and live preview" "$repo/themes/catalog/nord/preview.png" selected_preview
expect_poll "nord's selected card draws preview.png" ready card_image "$repo/themes/catalog/nord/preview.png"
expect "nord's selected card does not build the live preview" absent ipc smoke readDescendant overlay vgs.themes DesktopPreview visible
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
press_themes || fail "typing SUPER+CTRL+T during the download failed"
expect "Escape and SUPER+CTRL+T leave the browser open during the download" 1 layer_count vgs:overlay
touch -- "$wallpaper_gate"
expect_poll "the download and the apply after it close the browser" 0 layer_count vgs:overlay
expect "the wallpapers are unpacked into nord" True bash -c '[[ -f $1/nord/backgrounds/a.jpg && -f $1/nord/backgrounds/b.jpg ]] && echo True' _ "$installed"
expect "the catalog records the wallpapers" True catalog_imagery nord
expect_poll "the apply after the download shows nord's first wallpaper" "\"$installed/nord/backgrounds/a.jpg\"" bg_current

# nord's card now draws its first wallpaper; Escape clears the filter,
# then closes.
press_themes || fail "typing SUPER+CTRL+T to reopen failed"
expect_poll "SUPER+CTRL+T opens the browser again" 1 layer_count vgs:overlay
browser_focused
expect_poll "the reopened browser selects the applied nord" '"nord"' view_value selectedName
expect_poll "nord's card draws its first wallpaper" ready card_image "$installed/nord/backgrounds/a.jpg"
type_keys "x" || fail "typing x failed"
expect_poll "x filters" '"x"' view_value filterText
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape clears the filter" '""' view_value filterText
expect "Escape with a filter keeps the browser open" 1 layer_count vgs:overlay
type_keys -k Escape || fail "sending Escape again failed"
expect_poll "Escape with no filter closes the browser" 0 layer_count vgs:overlay
# A filter no card matches shows the empty state; its Clear filter clears
# the filter and hands the keyboard back to the rail, so Right steps and
# Escape closes.
clear_filter() { # LABEL
  press_themes || { fail "$1: typing SUPER+CTRL+T failed"; return 1; }
  expect_poll "$1: SUPER+CTRL+T opens the browser" 1 layer_count vgs:overlay
  expect_poll "$1: the browser read its cards" true view_value loaded
  type_keys zzqx || { fail "$1: typing the filter failed"; return 1; }
  expect_poll "$1: a filter no card matches empties the rail" 0 view_count
  click_in vgs:overlay overlay vgs.themes Button "Clear filter" || { fail "$1: the click on Clear filter failed"; return 1; }
}
clear_filter "Clear filter"
expect_poll "Clear filter clears the filter" '""' view_value filterText
expect_poll "Clear filter hands the keyboard back to the rail" true rail_focused
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
# SUPER+CTRL+T closes the view it opened, and a click on the scrim closes it.
press_themes || fail "typing SUPER+CTRL+T failed"
expect_poll "SUPER+CTRL+T opens the browser" 1 layer_count vgs:overlay
press_themes || fail "typing SUPER+CTRL+T again failed"
expect_poll "SUPER+CTRL+T on the open theme view closes it" 0 layer_count vgs:overlay
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
# read again, so Enter retries the apply and not the install.
press_themes || fail "typing SUPER+CTRL+T for akane failed"
expect_poll "SUPER+CTRL+T opens the browser for akane" 1 layer_count vgs:overlay
browser_focused
type_keys "akane" || fail "typing akane failed"
expect_poll "the filter selects akane" '"akane"' view_value selectedName
type_keys -k Return || fail "sending Return for akane failed"
expect_poll "the apply after the install fails with the runner's reason" '"Could not apply Akane. Another theme action is running. Wait for it to finish."' view_value problem
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
press_themes || fail "typing SUPER+CTRL+T for vgs failed"
expect_poll "SUPER+CTRL+T opens the browser for vgs" 1 layer_count vgs:overlay
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
wall_keys() { wall_value cards | py_reply 'import json,sys; print(json.dumps([c["key"] for c in json.load(sys.stdin)]))'; }
wall_selected() { wall_value selected | py_reply 'import json,sys; s=json.load(sys.stdin); print("none" if s is None else s["key"])'; }
# Whether the cards hold every KEY.
wall_has() { wall_value cards | py_reply 'import json,sys; keys=[c["key"] for c in json.load(sys.stdin)]; print(all(k in keys for k in sys.argv[1:]))' "$@"; }
wall_job() { wall_value job | py_reply 'import json,sys; j=json.load(sys.stdin); print("none" if j is None else j["step"])'; }
nord_a="$installed/nord/backgrounds/a.jpg"; nord_b="$installed/nord/backgrounds/b.jpg"; nord_c="$installed/nord/backgrounds/c.jpg"
wall_output=SMOKE-WALL
# Whether the wallpaper view's scope control holds the keyboard.
segment_focused() { ipc smoke readDescendant overlay vgs.themes SegmentedControl activeFocus; }
thumbs="$repo/themes/catalog/thumbnails"
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
# and c.jpg from nord's thumbnail, pinned for nord in the sandbox copy's
# catalog, which the update card then offers.
pin_nord() {
  python3 - "$assets/themes/$1" "$2" "$thumbs/nord.jpg" "$index" <<'PY'
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
# The bind reads the old key, and SUPER+CTRL+T opens nothing: the SUPER+T
# typed after it, which would close a browser it opened, opens the browser.
plugin_control manifest.json "old theme key" '{ "shortcut": "themes", "key": "SUPER+CTRL+T" }' '{ "shortcut": "themes", "key": "SUPER+T" }'
expect_poll "control: the copy binds SUPER+T to the theme browser" '[[64, "T"]]' themes_bind
press_themes || fail "typing SUPER+CTRL+T for the old theme key control failed"
press_old_themes || fail "typing SUPER+T for the old theme key control failed"
expect_poll "control: SUPER+CTRL+T on the copy opens nothing, so SUPER+T opens the browser" 1 layer_count vgs:overlay
type_keys -k Escape || fail "closing the old theme key control browser failed"
expect_poll "the old theme key control browser closes" 0 layer_count vgs:overlay
plugin_restore manifest.json "old theme key"
expect_poll "the restored manifest binds SUPER+CTRL+T to the theme browser" '[[68, "T"]]' themes_bind

# Controls for the preview guarantees above.
plugin_control ThemeCard.qml "preview sourceSize" "sourceSize: root.decodeSize" "sourceSize: Qt.size(1, 1)"
press_themes || fail "typing SUPER+CTRL+T for the preview sourceSize control failed"
expect_poll "the sourceSize control opens the theme browser" 1 layer_count vgs:overlay
expect_poll "the sourceSize control read its cards" true view_value loaded
type_keys -k Home || fail "sending Home for the sourceSize control failed"
expect_poll "control: the live preview no longer decodes at card size times scale" False card_source_size_matches "$akane_preview"
type_keys -k Escape || fail "closing the sourceSize control browser failed"
expect_poll "the sourceSize control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeCard.qml "preview sourceSize"

# Control for the slice names: a card copy whose slice name is empty.
plugin_control ThemeCard.qml "slice name" $'        text: root.modelData.label\n        color: root.colors === null ? Theme.color.text :' $'        text: ""\n        color: root.colors === null ? Theme.color.text :'
press_themes || fail "typing SUPER+CTRL+T for the slice name control failed"
expect_poll "the slice name control opens the theme browser" 1 layer_count vgs:overlay
expect_poll "the slice name control read its cards" true view_value loaded
expect_poll "control: side cards without their names read as unnamed" unnamed slices_unnamed
type_keys -k Escape || fail "closing the slice name control browser failed"
expect_poll "the slice name control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeCard.qml "slice name"

plugin_control ThemeCard.qml "live preview token" "tokens: root.modelData.tokens" "tokens: ({})"
press_themes || fail "typing SUPER+CTRL+T for the live preview control failed"
expect_poll "the live preview control opens the theme browser" 1 layer_count vgs:overlay
expect_poll "the live preview control read its cards" true view_value loaded
type_keys "$first_card" || fail "typing $first_card for the live preview control failed"
expect "control: the live preview no longer uses the package accent" '"#ff5a36"' ipc smoke readDescendant overlay vgs.themes DesktopPreview accentHex
expect_poll "control: the windows no longer draw the theme's colours" True judged_rule expanded_preview windows-colours
type_keys -k Escape || fail "clearing the live preview control filter failed"
type_keys -k Escape || fail "closing the live preview control browser failed"
expect_poll "the live preview control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeCard.qml "live preview token"

plugin_control ThemeCard.qml "preview precedence" "readonly property bool packagePreview: typeof modelData.previewImage === \"string\" && modelData.previewImage !== \"\"" "readonly property bool packagePreview: false"
press_themes || fail "typing SUPER+CTRL+T for the preview precedence control failed"
expect_poll "the preview precedence control opens the theme browser" 1 layer_count vgs:overlay
expect_poll "the preview precedence control read its cards" true view_value loaded
type_keys "nord" || fail "typing nord for the preview precedence control failed"
expect_poll "the preview precedence control selects nord" '"nord"' view_value selectedName
expect "control: nord no longer draws preview.png first" none card_image "$repo/themes/catalog/nord/preview.png"
expect "control: nord shows the live preview instead" true ipc smoke readDescendant overlay vgs.themes DesktopPreview visible
type_keys -k Escape || fail "clearing the preview precedence control filter failed"
type_keys -k Escape || fail "closing the preview precedence control browser failed"
expect_poll "the preview precedence control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeCard.qml "preview precedence"

# Controls for the recovery flows and the band: a copy of the theme view
# whose Clear filter clears nothing, one that leaves the keyboard off the
# rail, and one whose rail band takes the press.
plugin_control ThemeView.qml "clear filter" 'root.editFilter({ kind: "clear" });' ''
clear_filter "control: the clear filter copy"
expect "control: a Clear filter that clears nothing keeps the filter" '"zzqx"' view_value filterText
type_keys -k Escape || fail "clearing the clear filter control's filter failed"
type_keys -k Escape || fail "closing the clear filter control failed"
expect_poll "the clear filter control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeView.qml "clear filter"
plugin_control ThemeView.qml "clear filter focus" 'Qt.callLater(root.focusRail);' ''
clear_filter "control: the clear filter focus copy"
expect_poll "the clear filter focus control clears the filter" '""' view_value filterText
expect "control: a Clear filter that keeps the keyboard leaves the rail unfocused" false rail_focused
expect "the clear filter focus control browser hides" ok ipc shell hide overlay vgs.themes
expect_poll "the clear filter focus control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeView.qml "clear filter focus"
plugin_control ThemeView.qml "rail band" '            // No card to show: the list loading, no theme at all, or a' $'            MouseArea { anchors.fill: parent }\n            // No card to show: the list loading, no theme at all, or a'
band_click "control: a rail band that takes the press" || fail "the rail band control's click failed"
expect "control: a band that takes the press leaves the browser open" 1 layer_count vgs:overlay
expect "the rail band control browser hides" ok ipc shell hide overlay vgs.themes
expect_poll "the rail band control browser closes" 0 layer_count vgs:overlay
plugin_restore ThemeView.qml "rail band"
# Control for the resting texts: a copy of the theme view that draws a key
# hint under the rail.
plugin_control ThemeView.qml "resting text" $'                id: caption\n' $'                id: caption\n                Label { role: "hint"; text: "Enter" }\n'
press_themes || fail "typing SUPER+CTRL+T for the resting text control failed"
expect_poll "SUPER+CTRL+T opens the resting text control browser" 1 layer_count vgs:overlay
expect_poll "the resting text control read its cards" true view_value loaded
expect_poll "control: a key hint under the rail is a resting text" '["Enter", "Vgs"]' rest_texts
type_keys -k Escape || fail "sending Escape to the resting text control failed"
expect_poll "Escape closes the resting text control browser" 0 layer_count vgs:overlay
plugin_restore ThemeView.qml "resting text"

# vgs, applied, ships no wallpaper, so the wallpaper view's theme source is
# empty; a click on the source line's Show all switches to all, turns the
# line to Show theme and leaves the keys with the view, so Alt+S flips it
# back. Controls: a copy whose line flips nothing, one whose line takes the
# keyboard, and one whose line keeps its first text.
show_every() { # LABEL
  press_wallpapers || { fail "$1: typing SUPER+CTRL+W failed"; return 1; }
  expect_poll "$1: SUPER+CTRL+W opens the browser" 1 layer_count vgs:overlay
  expect_poll "$1: the wallpaper view read its lists" true ipc smoke readDescendant overlay vgs.themes WallpaperView loaded
  expect "$1: vgs's theme source lists no image" '[]' ipc smoke readDescendant overlay vgs.themes WallpaperView cards
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

press_wallpapers || fail "typing SUPER+CTRL+W failed"
expect_poll "SUPER+CTRL+W opens the browser" 1 layer_count vgs:overlay
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
expect_poll "the resting wallpaper view draws its source line and scope control alone" '["All monitors", "Show all", "This monitor"]' rest_texts

# The toggles: Alt+S flips the source, Alt+M flips the scope, and
# Tab and Shift+Tab switch the top tabs. None moves the selected card.
type_keys -M alt -k s -m alt || fail "sending Alt+S failed"
expect_poll "Alt+S shows every source" '"all"' wall_value source
expect_poll "every source lists nord's images" True wall_has "$nord_a" "$nord_b"
expect_poll "every source turns the source line to Show theme" True rest_has "Show theme"
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

# This monitor: Space sets b.jpg on the browser's screen alone and closes.
type_keys -k Right || fail "sending Right failed"
expect_poll "Right selects b.jpg" "$nord_b" wall_selected
type_keys -k space || fail "sending Space for this monitor failed"
expect_poll "Space sets this monitor and closes the browser" 0 layer_count vgs:overlay
expect_poll "the browser's screen draws b.jpg" "$nord_b ready" background_image_on "$this_screen"
expect "the other screen keeps nord's first image" "$nord_a ready" background_image_on "$other_screen"
expect "a set for this monitor keeps the current image" "\"$nord_a\"" bg_current

# Each open starts on every monitor; This monitor selects the screen's own
# image, and All monitors sets the current image on every screen, the
# screen's own cleared.
press_wallpapers || fail "typing SUPER+CTRL+W to reopen failed"
expect_poll "SUPER+CTRL+W opens the browser again" 1 layer_count vgs:overlay
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
press_wallpapers || fail "typing SUPER+CTRL+W for the scope control failed"
expect_poll "SUPER+CTRL+W opens the scope control's browser" 1 layer_count vgs:overlay
expect_poll "the scope control's view read its lists" true wall_value loaded
type_keys -M alt -k m -m alt -k Right || fail "sending Alt+M and Right to the scope control failed"
expect_poll "the scope control selects b.jpg for this monitor" "$nord_b" wall_selected
type_keys -k Return || fail "sending Return to the scope control failed"
expect_poll "the scope control's set closes the browser" 0 layer_count vgs:overlay
expect_poll "the scope control moves the other screen's image too" "$nord_b ready" background_image_on "$other_screen"
plugin_restore WallpaperView.qml scope
expect "set --every-screen puts nord's first image back on every screen" "ok background=a.jpg theme=nord path=$nord_a screen=*" vgshell_theme background set "$nord_a" --every-screen

# A click on the scope segment already chosen hands the keyboard back as a
# change does: Right then steps the rail and leaves the scope. Control: a
# copy of the view whose scope control keeps the keyboard switches the
# scope on Right.
press_wallpapers || fail "typing SUPER+CTRL+W for the segment click failed"
expect_poll "SUPER+CTRL+W opens the browser for the segment click" 1 layer_count vgs:overlay
expect_poll "the segment-click view selects a.jpg" "$nord_a" wall_selected
click_in vgs:overlay overlay vgs.themes QQuickButton "All monitors" || fail "the click on the chosen All monitors segment failed"
expect_poll "the view takes the keyboard back after a click on the chosen scope" false segment_focused
type_keys -k Right || fail "sending Right after the segment click failed"
expect_poll "Right after the click steps the rail" "$nord_b" wall_selected
expect "Right after the click leaves the scope" '"every"' wall_value scope
type_keys -k Escape || fail "sending Escape after the segment click failed"
expect_poll "Escape closes the browser after the segment click" 0 layer_count vgs:overlay
plugin_control WallpaperView.qml "wallpaper focus" $'currentIndex: root.scopeIndex\n                    onActiveFocusChanged: if (activeFocus) Qt.callLater(root.takeKeys)' 'currentIndex: root.scopeIndex'
press_wallpapers || fail "typing SUPER+CTRL+W for the wallpaper focus control failed"
expect_poll "SUPER+CTRL+W opens the wallpaper focus control's browser" 1 layer_count vgs:overlay
expect_poll "the wallpaper focus control's view read its lists" true wall_value loaded
click_in vgs:overlay overlay vgs.themes QQuickButton "All monitors" || fail "the click on the focus control's All monitors segment failed"
type_keys -k Right || fail "sending Right to the wallpaper focus control failed"
expect_poll "the wallpaper focus control's Right switches the scope" '"this"' wall_value scope
press_wallpapers || fail "typing SUPER+CTRL+W to close the wallpaper focus control failed"
expect_poll "SUPER+CTRL+W closes the wallpaper focus control's browser, whose keys the control holds" 0 layer_count vgs:overlay
plugin_restore WallpaperView.qml "wallpaper focus"
# Controls for the slices: a copy of the theme card whose stack lies
# across the slice, and one whose stack reverses its colours.
for control in vertical colours; do
  case $control in
    vertical) plugin_control ThemeCard.qml "stack $control" $'        vertical: true\n' '' ;;
    colours) plugin_control ThemeCard.qml "stack $control" $'vertical: true\n        colours: root.swatches === null ? [] : root.swatches' $'vertical: true\n        colours: root.swatches === null ? [] : root.swatches.slice().reverse()' ;;
  esac
  press_themes || fail "typing SUPER+CTRL+T for the stack $control control failed"
  expect_poll "SUPER+CTRL+T opens the stack $control control browser" 1 layer_count vgs:overlay
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
plugin_control WallpaperCard.qml identity "Files.stampedUrl(root.modelData.path, root.modelData.generation)" "Files.fileUrl(root.modelData.path)"
pin_nord vgs-theme-nord-smoke2.tar.gz "$thumbs/frankenstein.jpg"
press_wallpapers || fail "typing SUPER+CTRL+W for the identity control failed"
expect_poll "SUPER+CTRL+W opens the identity control's browser" 1 layer_count vgs:overlay
expect_poll "the theme source ends with the update card" "[\"$nord_a\", \"$nord_b\", \"update\"]" wall_keys
expect_poll "the identity control draws nord's b.jpg" "$(file_ratio "$thumbs/nord.jpg")" card_ratio "$nord_b"
type_keys -k End || fail "sending End failed"
expect_poll "End selects the update card" update wall_selected
type_keys -k Return || fail "sending Return to the identity control's update card failed"
expect_poll "the identity control's update, apply and lists end" none wall_job
expect "the identity control's update left no problem" '""' wall_value problem
expect_poll "the theme source lists the third image and no card" "[\"$nord_a\", \"$nord_b\", \"$nord_c\"]" wall_keys
expect "the update replaced b.jpg on disk" True bash -c 'cmp -s -- "$1" "$2" && echo True' _ "$thumbs/frankenstein.jpg" "$nord_b"
expect "control: an unstamped image URL keeps drawing the replaced b.jpg's old picture" "$(file_ratio "$thumbs/nord.jpg")" card_ratio "$nord_b"
type_keys -k Escape || fail "sending Escape to the identity control failed"
expect_poll "Escape closes the identity control's browser" 0 layer_count vgs:overlay
plugin_restore WallpaperCard.qml identity
pin_nord vgs-theme-nord-smoke3.tar.gz "$thumbs/biscuit-de-mar.jpg"
press_wallpapers || fail "typing SUPER+CTRL+W for the update failed"
expect_poll "SUPER+CTRL+W opens the browser for the update" 1 layer_count vgs:overlay
expect_poll "a new open draws the b.jpg the last update replaced" "$(file_ratio "$thumbs/frankenstein.jpg")" card_ratio "$nord_b"
expect_poll "the theme source ends with the next update card" "[\"$nord_a\", \"$nord_b\", \"$nord_c\", \"update\"]" wall_keys
type_keys -k End || fail "sending End for the update failed"
expect_poll "End selects the next update card" update wall_selected
type_keys -k Return || fail "sending Return to the update card failed"
expect_poll "the update, the apply after it and the lists end" none wall_job
expect "the update left no problem" '""' wall_value problem
expect "the update keeps the browser open" 1 layer_count vgs:overlay
expect_poll "the rail draws the b.jpg the update replaced" "$(file_ratio "$thumbs/biscuit-de-mar.jpg")" card_ratio "$nord_b"
expect "the update unpacks the third image" True bash -c '[[ -f $1 ]] && echo True' _ "$nord_c"
type_keys -k Escape || fail "sending Escape after the update failed"
expect_poll "Escape closes the browser after the update" 0 layer_count vgs:overlay

# One screen: no scope control, Alt+M does nothing and Tab switches tabs.
expect "the nested compositor removes the wallpaper rows' monitor" ok hypr output remove "$wall_output"
expect_poll "the wallpaper rows' monitor is gone" False screen_listed "$wall_output"
press_wallpapers || fail "typing SUPER+CTRL+W on one screen failed"
expect_poll "SUPER+CTRL+W opens the browser on one screen" 1 layer_count vgs:overlay
expect_poll "the one-screen view read its lists" true wall_value loaded
expect "one screen shows no scope control" false wall_value scoped
expect_poll "one screen selects the current image" "$nord_a" wall_selected
type_keys -M alt -k m -m alt || fail "sending Alt+M on one screen failed"
expect "Alt+M on one screen leaves every monitor" '"every"' wall_value scope
type_keys -k Tab || fail "sending Tab on one screen failed"
expect_poll "Tab on one screen switches to the theme view" '"themes"' ipc smoke readInstance overlay vgs.themes view
type_keys -M shift -k Tab -m shift || fail "sending Shift+Tab on one screen failed"
expect_poll "Shift+Tab on one screen switches back to the wallpaper view" '"wallpapers"' ipc smoke readInstance overlay vgs.themes view
press_wallpapers || fail "typing SUPER+CTRL+W to close failed"
expect_poll "SUPER+CTRL+W on the open wallpaper view closes it" 0 layer_count vgs:overlay
expect "the follow after the wallpaper rows ends" idle theme_idle
expect "vgs applies after the wallpaper rows" "ok theme=vgs state=applied shell=applied" vgshell_theme apply vgs
expect_poll "the shell follows vgs after the wallpaper rows" vgs ipc smoke themeName

expect "disabling vgs.themes after the browser rows is allowed" ok ipc shell setPluginEnabled vgs.themes false
expect_poll "disabling vgs.themes released its shortcut" '[]' lent_themes
expect_poll "disabling vgs.themes unbinds SUPER+CTRL+T" '[]' themes_bind
expect_poll "disabling vgs.themes unbinds SUPER+CTRL+W" '[]' themes_bind wallpapers
cp -p -- "$sandbox/hyprland-before-browser.lua" "$hypr_lua.next" && mv -T -- "$hypr_lua.next" "$hypr_lua"
expect "the nested instance reloads the hyprland.lua the browser rows found" ok hypr reload config-only
mv -T -- "$repo/bin/vgshell.real" "$repo/bin/vgshell"
cp -p -- "$sandbox/catalog-index.json" "$index"
rm -r -- "$installed/nord" "$installed/akane" "$assets" "$wallpaper_gate" "$akane_refused" "$akane_preview"
rm -f -- "$bg_state/backgrounds.json" "$bg_state/background"
