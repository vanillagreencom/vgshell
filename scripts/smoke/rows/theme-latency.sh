# Theme browser timings on the nested seat. The probe stamps the first
# presented frame with visible cards and keyboard focus, or the changed
# desktop. IPC polls back to back; its round trips do not inflate the
# in-shell frame timestamp. Warm open: 240 ms, twice the highest of six
# readings (112, 120, 97, 98, 88, 97 ms) on cachy, 2026-10-04, load 11.95,
# CPU pressure 0.3 to 1.4%, compositor logs on. The owner allowed this
# measured bound after the original 100 ms target failed. A warm open
# over its bound while CPU pressure exceeds 2.8%, twice that run's highest
# 1.4%, is not measured (exit 77), since fleet load alone slows it past
# the bound. Load only slows an open, so a warm open within its bound
# passes at any pressure, and an unreadable pressure excuses nothing.
# Theme change:
# six readings, median <=150 ms and every reading <=292 ms. Owner ruling
# ask 1791136884-3060298-761, 2026-10-04: the median holds the desk target;
# the single-reading ceiling guards a slowdown under fleet load. On cachy,
# 2026-10-04, twelve readings at load 3.2 to 3.5 had min/median/max
# 89/108/132 ms. Six at load 8.6: 171, 93, 158, 116, 108, 121 ms,
# CPU pressure 0.3 to 0.8%, compositor logs on.
# Wallpaper keeps its 150 ms bound.
# inputs: shell/plugins/vgs.themes/* shell/Core/ThemeRunner.qml shell/Commons/Theme* shell/Ui/layout/CardCarousel.qml themes/* bin/vgshell bin/vgshell-theme-judge bin/lib/* scripts/smoke/rows/hyprland-consent.sh scripts/smoke/ThemeLatencyProbe.qml
set -euo pipefail
# Exercise the actual QML reader under Node with controlled presented frames.
# These controls hold dismissal, wallpaper readiness and selected content.
node - "$repo/scripts/smoke/ThemeLatencyProbe.qml" <<'JS'
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const source = fs.readFileSync(process.argv[2], 'utf8');
function declaration(text, name) {
    const start = text.indexOf('    function ' + name + '(');
    assert.ok(start >= 0, name);
    const open = text.indexOf('{', start);
    let depth = 1, at = open + 1;
    for (; depth > 0 && at < text.length; at++) {
        if (text[at] === '{') depth++;
        else if (text[at] === '}') depth--;
    }
    assert.equal(depth, 0, name);
    return text.slice(start, at);
}
// A picture the card decodes at 200x100 device pixels.
class Image { constructor(source, status = Image.Ready) { this.source = source; this.status = status; this.visible = true; this.sourceSize = { width: 200, height: 100 }; } }
Image.Ready = 1; Image.Loading = 2;
function item(type, children = []) {
    const result = { children, visible: true, toString: () => type };
    for (const child of children) child.parent = result;
    return result;
}
function reader(text) {
    let clock = 10;
    const context = vm.createContext({ root: { themeLatency: null }, Theme: { name: 'latency' }, Plugins: { built: { overlay: [] } }, Image, Date: { now: () => clock++ } });
    for (const name of ['typeName', 'descendants', 'visibleInTree', 'desktopExposed', 'backgroundReady', 'selectedCard', 'cardPicture', 'selectedPictureReady', 'latencyFrame']) vm.runInContext(declaration(text, name), context);
    context.root.selectedPictureReady = context.selectedPictureReady;
    context.begin = (kind, want, background = '') => { context.root.themeLatency = { kind, want, background, started: 0, jobs: [] }; };
    return context;
}
function verify(text) {
    const c = reader(text), bar = item('Bar'), image = new Image('file:///a.jpg'), background = item('Background', [image]);
    c.Plugins.built.background = [{ kind: 'background', instance: background }];
    c.begin('theme', 'latency', 'file:///a.jpg');
    c.latencyFrame(bar, 'bar');
    assert.equal(c.root.themeLatency.drawn, undefined, 'ready wallpaper must still present a requested background frame');
    c.latencyFrame(background, 'background');
    assert.equal(typeof c.root.themeLatency.drawn, 'number');
    c.begin('theme', 'latency', 'file:///a.jpg');
    c.Plugins.built.overlay = [{ id: 'vgs.themes' }];
    c.latencyFrame(bar, 'bar'); c.latencyFrame(background, 'background');
    assert.equal(c.root.themeLatency.drawn, undefined, 'mapped browser must block theme completion');
    c.begin('wallpaper', 'file:///a.jpg');
    c.latencyFrame(background, 'background');
    assert.equal(c.root.themeLatency.drawn, undefined, 'mapped browser must block wallpaper completion');
    c.Plugins.built.overlay = [];
    c.latencyFrame(bar, 'bar');
    assert.equal(typeof c.root.themeLatency.drawn, 'number', 'exposed frame must complete with the retained ready wallpaper');
    c.begin('theme', 'latency', 'file:///a.jpg');
    c.Plugins.built.overlay = [{ id: 'vgs.themes' }];
    c.latencyFrame(bar, 'bar'); c.latencyFrame(background, 'background');
    image.status = Image.Loading; c.Plugins.built.overlay = [];
    c.latencyFrame(bar, 'bar');
    assert.equal(c.root.themeLatency.drawn, undefined, 'retained frames must not complete after requested wallpaper loses readiness');
    image.status = Image.Ready; c.latencyFrame(bar, 'bar');
    assert.equal(typeof c.root.themeLatency.drawn, 'number', 'exposed native frame completes with both retained ready buffers');
    c.begin('theme', 'latency', 'file:///a.jpg'); image.status = Image.Loading;
    c.latencyFrame(bar, 'bar'); c.latencyFrame(background, 'background');
    assert.equal(c.root.themeLatency.drawn, undefined, 'loading wallpaper must block theme completion after a ready bar');
    image.status = Image.Ready; image.source = 'file:///other.jpg';
    c.latencyFrame(background, 'background');
    assert.equal(c.root.themeLatency.drawn, undefined, 'old wallpaper must not complete the theme');
    image.source = 'file:///a.jpg'; c.latencyFrame(background, 'background');
    assert.equal(typeof c.root.themeLatency.drawn, 'number', 'both exposed frames must complete');
    c.begin('theme', 'latency', ''); c.latencyFrame(bar, 'bar');
    assert.equal(typeof c.root.themeLatency.drawn, 'number', 'explicit no-wallpaper theme must complete');
    c.begin('theme', 'latency', 'file:///a.jpg'); c.latencyFrame(background, 'background');
    assert.equal(c.root.themeLatency.drawn, undefined, 'theme must wait for its new bar frame too');
    c.latencyFrame(bar, 'bar'); assert.equal(typeof c.root.themeLatency.drawn, 'number');
    c.begin('step', '');
    const picture = new Image('file:///a.jpg'), card = item('ThemeCard', [picture]), browser = item('Browser', [card]);
    card.current = true; card.picture = 'file:///a.jpg';
    for (const name of ['one', 'two', 'three']) { card.modelData = { name }; c.latencyFrame(browser, 'overlay'); }
    assert.equal(c.root.themeLatency.steps, 3); assert.equal(c.root.themeLatency.late || 0, 0);
    c.latencyFrame(item('Browser'), 'overlay');
    card.modelData = { name: 'four' }; c.latencyFrame(browser, 'overlay');
    assert.equal(c.root.themeLatency.steps, 4); assert.equal(c.root.themeLatency.late, 1, 'later ready frames must retain the missing selected-picture failure');
    card.visible = false; c.latencyFrame(browser, 'overlay');
    assert.equal(c.root.themeLatency.late, 2, 'hidden selected card must also fail');
    card.visible = true; picture.status = Image.Loading; c.latencyFrame(browser, 'overlay');
    assert.equal(c.root.themeLatency.late, 3, 'loading selected picture must fail');
    picture.status = Image.Ready; c.root.themeLatency.sizes = { '/a.jpg': [120, 60], '/b.jpg': [200, 80] };
    card.modelData = { name: 'five' }; c.latencyFrame(browser, 'overlay');
    assert.equal(c.root.themeLatency.low, 1, 'a file smaller than its drawn size must count as low');
    assert.equal(c.root.themeLatency.full.five, undefined, 'a low picture is not the full one');
    picture.source = 'file:///c.jpg?2'; c.latencyFrame(browser, 'overlay');
    assert.equal(c.root.themeLatency.low, 2, 'an unmeasured file must count as low');
    picture.source = 'file:///b.jpg?2'; c.latencyFrame(browser, 'overlay');
    assert.equal(c.root.themeLatency.low, 2, 'a file as wide as its drawn size is full');
    assert.equal(typeof c.root.themeLatency.full.five, 'number', 'the first full frame stamps the selection');
}
verify(source);
const controls = [
    ['browser dismissal', 'if (["bar", "background"].indexOf(kind) === -1 || !desktopExposed()) return;', ''],
    ['wallpaper readiness', 'if (reading.barFrame === undefined || (reading.background !== "" && reading.backgroundFrame === undefined)) return;', 'if (reading.barFrame === undefined) return;'],
    ['live requested wallpaper', 'if (background !== "" && !backgroundReady(background)) return;', ''],
    ['missing selected picture', 'if (card === undefined || !visibleInTree(card)) { reading.late = (reading.late || 0) + 1; return; }', 'if (card === undefined || !visibleInTree(card)) return;'],
    ['low selected picture', 'if (picture !== null && picture.low) reading.low = (reading.low || 0) + 1;', ''],
    ['a low picture is not full', '&& !picture.low && reading.full[key]', '&& reading.full[key]'],
    ['an unmeasured file is low', 'size === undefined || size[0]', 'size !== undefined && size[0]']
];
for (const [label, needle, replacement] of controls) {
    assert.equal(source.split(needle).length, 2, label + ': exact control match');
    assert.throws(() => verify(source.replace(needle, replacement)), { name: 'AssertionError' }, label + ': reader without this rule must fail');
}
console.log('theme-latency-reader: ok controls=7 browser-held=refused wallpaper-loading=refused retained-live=refused selected-missing=refused selected-low=refused low-full=refused unmeasured-low=refused');
JS

cp -- "$repo/scripts/smoke/ThemeLatencyProbe.qml" "$repo/shell/ThemeLatencyProbe.qml"
expect "the latency observer loads" ok ipc smoke runnerLoad "$repo/shell/ThemeLatencyProbe.qml"

latency_read() { ipc theme-latency themeLatencyRead; }
latency_done() { latency_read | py_reply 'import json,sys; print("drawn" if "drawn" in json.load(sys.stdin) else "pending")'; }
latency_report() {
  local value end_ms pressure
  value="$(latency_read)" || return 1
  # The window closes at the reading, before the checks, since the warm
  # verdict reads its pressure.
  end_ms="$(now_ms)"
  pressure="$(cpu_some_pct "$latency_cpu_start" "$(cpu_some_us)" "$((end_ms - latency_window_start))")"
  if [[ $1 != open-cold ]]; then
    local bound=150 planted warm drawn
    [[ $1 == open-warm ]] && bound=240
    [[ $1 == theme ]] && bound=292
    planted="$(printf '%s' "$value" | py_reply 'import json,sys; x=json.load(sys.stdin); x["drawn"]=int(sys.argv[1])+1; print(json.dumps(x))' "$bound")" || planted=unread
    case $1 in
      theme)
        latency_theme_readings+=("$value")
        expect "$1 rejects a reading over its bound" over latency_bound "$planted" "$bound"
        ;;
      open-warm)
        warm="$(latency_warm_verdict "$value" "$bound" "$pressure")" || warm=unread
        if [[ $warm == unmeasured ]]; then
          drawn="$(printf '%s' "$value" | py_reply 'import json,sys; print(json.load(sys.stdin).get("drawn"))')" || drawn=unread
          not_measured theme-latency "open-warm=${drawn}ms-over-${bound}ms-at-cpu_some_pct=${pressure}-above-${latency_warm_pressure}"
        else
          expect "$1 meets its $bound ms bound" within latency_warm_verdict "$value" "$bound" "$pressure"
        fi
        # Planted at the threshold itself, which must not excuse it.
        expect "$1 rejects a reading over its bound" over latency_warm_verdict "$planted" "$bound" "$latency_warm_pressure"
        ;;
      *)
        expect "$1 meets its $bound ms bound" within latency_bound "$value" "$bound"
        expect "$1 rejects a reading over its bound" over latency_bound "$planted" "$bound"
        ;;
    esac
  fi
  printf 'theme-latency: reading=%s value=%s\n' "$1" "$value"
  printf 'theme-latency: load=%s cpu_some_pct=%s pressure_window_ms=%s\n' "$latency_load" "$pressure" "$((end_ms - latency_window_start))"
}
latency_pressure_start() {
  latency_load="$(cut -d ' ' -f 1 /proc/loadavg)"
  latency_window_start="$(now_ms)"
  latency_cpu_start="$(cpu_some_us)"
}
latency_bound() { printf '%s' "$1" | py_reply 'import json,sys; value=json.load(sys.stdin).get("drawn"); print("within" if isinstance(value,int) and 0 <= value <= int(sys.argv[1]) else "over")' "$2"; }
latency_warm_pressure=2.8
# latency_warm_verdict VALUE BOUND PRESSURE: within, over, or unmeasured
# for a drawn reading over BOUND while PRESSURE, a cpu_some_pct answer,
# exceeds latency_warm_pressure. Only a drawn reading counts as slow, and
# only cpu_some_pct's one-decimal number counts as a pressure, so a
# missing reading or an unreadable pressure fails.
latency_warm_verdict() {
  printf '%s' "$1" | py_reply 'import json,re,sys
value=json.load(sys.stdin).get("drawn"); bound=int(sys.argv[1]); pressure=sys.argv[2]
drawn=type(value) is int and value>=0
if drawn and value<=bound: print("within")
elif drawn and re.fullmatch(r"[0-9]+\.[0-9]",pressure) and float(pressure)>float(sys.argv[3]): print("unmeasured")
else: print("over")' "$2" "$3" "$latency_warm_pressure"
}
latency_theme_readings=()
latency_theme_summary() {
  printf '%s' "$1" | py_reply 'import json,statistics,sys
values=[x.get("drawn") for x in json.load(sys.stdin)]
valid=len(values)==6 and all(type(x) is int and x>=0 for x in values)
median=statistics.median(values) if valid else None
maximum=max(values) if valid else None
print(json.dumps({"readings_ms":values,"median_ms":median,"max_ms":maximum,"result":"within" if valid and median<=150 and maximum<=292 else "over"}))'
}
latency_theme_bound() { latency_theme_summary "$1" | py_reply 'import json,sys; print(json.load(sys.stdin)["result"])'; }
# Each control violates only one part of the six-reading rule.
expect "theme median over 150 ms fails below the single-reading ceiling" over latency_theme_bound '[{"drawn":151},{"drawn":151},{"drawn":151},{"drawn":151},{"drawn":151},{"drawn":151}]'
expect "theme reading over 292 ms fails below the median limit" over latency_theme_bound '[{"drawn":293},{"drawn":100},{"drawn":100},{"drawn":100},{"drawn":100},{"drawn":100}]'
expect "theme median at 150 ms and reading at 292 ms pass" within latency_theme_bound '[{"drawn":292},{"drawn":150},{"drawn":150},{"drawn":150},{"drawn":150},{"drawn":0}]'
# Each control violates only one part of the warm pressure rule.
expect "open-warm over 240 ms at 1.0% pressure fails" over latency_warm_verdict '{"drawn":241}' 240 1.0
expect "open-warm over 240 ms above 2.8% pressure is not measured" unmeasured latency_warm_verdict '{"drawn":241}' 240 30.0
expect "open-warm within 240 ms above 2.8% pressure passes" within latency_warm_verdict '{"drawn":240}' 240 30.0
expect "open-warm over 240 ms at unread pressure fails" over latency_warm_verdict '{"drawn":241}' 240 unmeasured
latency_theme_value() { ipc smoke readDescendant overlay vgs.themes ThemeView "$1"; }
latency_steps() { latency_read | py_reply 'import json,sys; x=json.load(sys.stdin); print("ready" if x.get("steps",0)>2 and x.get("late",0)==0 else "steps=%s late=%s" % (x.get("steps",0),x.get("late",0)))'; }
latency_low() { latency_read | py_reply 'import json,sys; print(json.load(sys.stdin).get("low",0))'; }
latency_low_seen() { latency_read | py_reply 'import json,sys; print(json.load(sys.stdin).get("low",0) > 0)'; }
# The epoch ms of the first frame drawing card NAME's full picture, or
# `pending`; latency_full_drawn NAME answers `drawn` once there is one.
latency_full_at() { latency_read | py_reply 'import json,sys; t=json.load(sys.stdin).get("full",{}).get(sys.argv[1]); print("pending" if t is None else t)' "$1"; }
latency_full_drawn() { [[ $(latency_full_at "$1") == pending ]] && echo pending || echo drawn; }
latency_moved() { [[ $(latency_theme_value selectedName) != "$1" ]] && echo moved || echo same; }
latency_catalog_ready() { latency_theme_value entries | py_reply 'import json,sys; print("ready" if isinstance(json.load(sys.stdin),list) else "pending")'; }
latency_installed() { latency_theme_value shownCards | py_reply 'import json,sys; print(any(c["name"]=="latency" and c["installed"] for c in json.load(sys.stdin)))'; }
latency_wall_value() { ipc smoke readDescendant overlay vgs.themes WallpaperView "$1"; }

expect "the theme service retires before the cold reading" ok ipc shell setPluginEnabled vgs.themes false
expect "the existing theme reads settle" idle theme_idle
mkdir -p -- "$home/.config/vgshell/themes/latency/backgrounds"
printf '%s\n' '{"schemaVersion":1,"name":"latency","tokens":{"palette":{"accent":"#12ab34"}}}' >"$home/.config/vgshell/themes/latency/theme.json"
cp -- "$repo/themes/catalog/thumbnails/nord.jpg" "$home/.config/vgshell/themes/latency/backgrounds/a.jpg"
cp -- "$repo/themes/catalog/thumbnails/akane.jpg" "$home/.config/vgshell/themes/latency/backgrounds/b.jpg"
mkdir -p -- "$home/.config/vgshell/themes/sample-peer/backgrounds"
printf '%s\n' '{"schemaVersion":1,"name":"sample-peer","tokens":{"palette":{"accent":"#ab1234"}}}' >"$home/.config/vgshell/themes/sample-peer/theme.json"
cp -- "$home/.config/vgshell/themes/latency/backgrounds/"*.jpg "$home/.config/vgshell/themes/sample-peer/backgrounds/"
cp -p -- "$hypr_lua" "$sandbox/hyprland-before-latency.lua"
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$hypr_lua"
expect "latency input bindings reload" ok hypr reload config-only
# Hold the first catalog answer. Installed rows must draw before it ends.
cp -p -- "$repo/bin/vgshell" "$sandbox/vgshell-before-latency"
cp -p -- "$repo/bin/vgshell" "$repo/bin/vgshell.latency-real"
latency_gate="$sandbox/latency-catalog-gate"
latency_started="$sandbox/latency-catalog-started"
cat >"$repo/bin/vgshell" <<EOF
#!/usr/bin/env bash
if [[ \${1-} == theme && \${2-} == catalog ]]; then
  touch '$latency_started'
  while [[ ! -e '$latency_gate' ]]; do sleep 0.01; done
fi
exec '$repo/bin/vgshell.latency-real' "\$@"
EOF
chmod +x "$repo/bin/vgshell"
latency_catalog_held() { [[ -e $latency_started ]] && echo held || echo pending; }
# The switch reading's catalog themes, the filter `ar` shows, with their
# first wallpapers in the preview cache as a fetch leaves them: a 6016x3384
# image, the size of the catalog's wallpapers (everforest, tycho,
# flexoki-light, akane and untitled measured 6016 wide, 2026-10-06), for
# the six it steps through, and the 480-pixel catalog thumbnail for lunar,
# its control.
latency_previews="$home/.cache/vgshell/theme-assets/previews"
mkdir -p -- "$latency_previews"
"$imagemagick" "$repo/themes/catalog/thumbnails/akane.jpg" -resize 6016x3384\! "$sandbox/latency-wallpaper.jpg" || fail "the switch wallpaper could not be made"
latency_pins="$(python3 -c 'import json,sys; print(" ".join(e["name"] + "=" + e["imagery"]["sha256"] for e in json.load(open(sys.argv[1]))["entries"] if "ar" in e["name"]))' "$repo/themes/catalog/index.json")" || fail "the switch themes' pins are unreadable"
for latency_pin in $latency_pins; do
  if [[ ${latency_pin%%=*} == lunar ]]; then
    cp -- "$repo/themes/catalog/thumbnails/akane.jpg" "$latency_previews/${latency_pin#*=}-a.jpg"
  else
    ln -- "$sandbox/latency-wallpaper.jpg" "$latency_previews/${latency_pin#*=}-a.jpg"
  fi
done
expect "the theme service enables for latency readings" ok ipc shell setPluginEnabled vgs.themes true
expect_poll "the theme service builds" false ipc smoke readInstance service vgs.themes setupPending
expect_poll "the catalog answer is held behind installed rows" held latency_catalog_held

# Instrument only the sandbox plugin copies to separate view work and image
# readiness from the window's presented frame. The row instruments no core
# file because editing a live core file owes a restart
# (docs/architecture/overview.md § Plugins and kinds).
python3 - "$repo" "$sandbox" <<'PY'
from pathlib import Path
import shutil, sys
repo, saved = map(Path, sys.argv[1:])
changes = {
    'shell/plugins/vgs.themes/Browser.qml': [('onLoaded: {', 'onLoaded: { console.log("theme-latency-stage page-loaded " + Date.now());')],
    'shell/plugins/vgs.themes/ThemeView.qml': [('started = true;', 'console.log("theme-latency-stage view-start " + Date.now()); started = true;'), ('        focusRail();\n    }\n\n    Component.onCompleted: start()', '        focusRail();\n        console.log("theme-latency-stage view-ready " + Date.now());\n    }\n\n    Component.onCompleted: start()')],
    'shell/plugins/vgs.themes/ThemeCard.qml': [('onStatusChanged: if (status === Image.Error)', 'onStatusChanged: { if (status === Image.Ready) console.log("theme-latency-stage image-ready " + Date.now() + " " + root.modelData.name); if (status === Image.Error)'), ('console.warn("themes: card image unreadable path=" + root.image)', 'console.warn("themes: card image unreadable path=" + root.image); }')],
}
for name, replacements in changes.items():
    target = repo / name
    shutil.copy2(target, saved / (target.name + '.latency-original'))
    source = target.read_text()
    for before, after in replacements:
        assert source.count(before) == 1, (name, before)
        source = source.replace(before, after)
    target.write_text(source)
PY

printf 'theme-latency: host=%s date=%s warm_samples=6 ipc_poll=back-to-back compositor_logs=on\n' "$(hostname)" "$(date -u +%Y-%m-%d)"
for temperature in cold warm warm warm warm warm warm; do
  latency_pressure_start
  expect "the $temperature open reader arms" ok ipc theme-latency themeLatencyBegin open "$temperature" ''
  type_keys -M logo -M ctrl -k t -m ctrl -m logo || fail "the theme open key failed"
  expect_poll "the $temperature browser draws and takes keys" drawn latency_done
  latency_report "open-$temperature"
  if [[ $temperature == cold ]]; then
    expect "cold open draws the shell-known installed theme" True latency_installed
    expect "cold open does not need the catalog answer" null latency_theme_value entries
    type_keys latency || fail "cold installed filter failed"
    expect_poll "the cold installed card is selected" '"latency"' latency_theme_value selectedName
    touch -- "$latency_gate"
    expect "the catalog refresh settles behind the open list" idle theme_idle
    expect_poll "the catalog arrives behind the list" ready latency_catalog_ready
    expect "the arriving catalog keeps the selected installed card" '"latency"' latency_theme_value selectedName
    type_keys -k Escape || fail "cold filter clear failed"
    expect_poll "the retained catalog completes the visible list before warm reopen" ready ipc theme-latency themeCatalogReady
  fi
  type_keys -k Escape || fail "the theme browser close key failed"
  expect_poll "the browser closes between readings" 0 layer_count vgs:overlay
done

type_keys -M logo -M ctrl -k t -m ctrl -m logo || fail "the held theme browser open failed"
expect_poll "the held theme browser takes keys" true latency_theme_value activeFocus
expect_poll "the held theme selected picture has drawn before arming" ready ipc theme-latency selectedPictureReady
expect "the held theme frame observer arms" ok ipc theme-latency themeLatencyBegin step '' ''
type_keys -P Right -s 900 -p Right || fail "the held theme key failed"
expect "held theme steps keep the selected picture ready" ready latency_steps
type_keys -k Escape || fail "the held theme browser close failed"
expect_poll "the held theme browser closes" 0 layer_count vgs:overlay

# Five switches over catalog themes, one Right each, the next pressed once
# the last drew its full picture: no frame draws the selected picture
# decoded smaller than the card, and each press reaches it. The row prints
# each press-to-full time.
type_keys -M logo -M ctrl -k t -m ctrl -m logo || fail "the switch browser open failed"
expect_poll "the switch browser holds the keyboard" true latency_theme_value activeFocus
type_keys ar || fail "the switch filter failed"
expect_poll "the switch filter selects the first catalog theme" '"arc-blueberry"' latency_theme_value selectedName
expect_poll "the first switch picture has drawn before arming" ready ipc theme-latency selectedPictureReady
expect "the switch frame observer arms" ok ipc theme-latency themeLatencyBegin step '' ''
latency_files=("$repo"/themes/catalog/thumbnails/*.jpg "$latency_previews"/*)
latency_sizes="$("$imagemagick" -ping "${latency_files[@]}" -format '%d/%f %w %h\n' info: | python3 -c 'import json,os,sys
rows = [l.rsplit(" ", 2) for l in sys.stdin.read().splitlines()]
assert len(rows) == int(sys.argv[1]), "measured %d of %s files" % (len(rows), sys.argv[1])
print(json.dumps({k: [int(w), int(h)] for p, w, h in rows for k in (p, os.path.realpath(p))}))' "${#latency_files[@]}")" || fail "the switch pictures could not be measured"
expect "the switch reading takes the pictures' sizes" ok ipc theme-latency themeLatencySizes "$latency_sizes"
for latency_switch in 1 2 3 4 5; do
  latency_from="$(latency_theme_value selectedName)" || fail "switch $latency_switch: the selection is unreadable"
  latency_pressed="$(now_ms)"
  type_keys -k Right || fail "switch $latency_switch: the key failed"
  expect_poll "switch $latency_switch moves the selection" moved latency_moved "$latency_from"
  latency_to="$(latency_theme_value selectedName | tr -d '"')"
  expect_poll "switch $latency_switch draws $latency_to's full picture" drawn latency_full_drawn "$latency_to"
  latency_full="$(latency_full_at "$latency_to")"
  [[ $latency_full == pending ]] || latency_full="$((latency_full - latency_pressed))"
  printf 'theme-latency: switch=%s card=%s press_to_full_ms=%s\n' "$latency_switch" "$latency_to" "$latency_full"
done
expect "five catalog switches draw no picture smaller than its card" 0 latency_low
printf 'theme-latency: switches=%s\n' "$(latency_read)"
# Control: lunar's cached wallpaper is the catalog thumbnail, which the
# card can only draw stretched; the reader counts its frames.
type_keys -k Right || fail "the control switch key failed"
expect_poll "the control switch selects lunar" '"lunar"' latency_theme_value selectedName
expect_poll "control: a picture smaller than its card reads as low" True latency_low_seen
type_keys -k Escape -k Escape || fail "the switch browser close failed"
expect_poll "the switch browser closes" 0 layer_count vgs:overlay

type_keys -M logo -M ctrl -k t -m ctrl -m logo || fail "the apply browser open failed"
expect_poll "the apply browser reads cards" true latency_theme_value loaded
expect_poll "the apply browser holds the keyboard" true latency_theme_value activeFocus
type_keys latency || fail "the apply card filter failed"
expect_poll "the apply card is selected" '"latency"' latency_theme_value selectedName
rm -- "${latency_gate:?}" "${latency_started:?}"
expect "a background refresh starts before activation" '' ipc smoke invokeInstance service vgs.themes refreshData ''
expect_poll "activation meets a held catalog read" held latency_catalog_held
latency_service_value() { ipc smoke readInstance service vgs.themes "$1"; }
latency_read_revision="$(latency_service_value dataRevision)"
latency_read_cards="$(latency_service_value cards)"
latency_read_last="$(latency_service_value themeLastText)"
expect "a read-only queue change starts behind the held catalog" ok ipc theme-latency readOnlyThemeJob
expect "a read-only queue change leaves apply state unchanged" "$latency_read_last" latency_service_value themeLastText
expect "a read-only queue change leaves the browser revision unchanged" "$latency_read_revision" latency_service_value dataRevision
expect "a read-only queue change leaves precomputed cards unchanged" "$latency_read_cards" latency_service_value cards
expect "the theme change reader arms" ok ipc theme-latency themeLatencyBegin theme latency "file://$home/.config/vgshell/themes/latency/backgrounds/a.jpg"
latency_pressure_start
type_keys -k Return || fail "the apply key failed"
expect_poll "the desktop presents the applied theme" drawn latency_done
latency_report theme
touch -- "$latency_gate"
expect_poll "the apply browser closes" 0 layer_count vgs:overlay
expect "the queue settles after theme apply" idle theme_idle

# Alternate installed packages so every sample writes a changed theme.
latency_previous=latency
for latency_package in sample-peer latency sample-peer latency sample-peer; do
  type_keys -M logo -M ctrl -k t -m ctrl -m logo || fail "the repeated apply browser open failed"
  expect_poll "the repeated apply browser reads cards" true latency_theme_value loaded
  expect_poll "the repeated apply browser holds the keyboard" true latency_theme_value activeFocus
  type_keys "$latency_package" || fail "the repeated apply filter failed"
  expect_poll "the repeated apply card is selected" "\"$latency_package\"" latency_theme_value selectedName
  expect "the next sample starts from a different published theme" "$latency_previous" ipc smoke themeName
  expect "the repeated theme reader arms" ok ipc theme-latency themeLatencyBegin theme "$latency_package" "file://$home/.config/vgshell/themes/$latency_package/backgrounds/a.jpg"
  latency_pressure_start
  type_keys -k Return || fail "the repeated theme apply key failed"
  expect_poll "the repeated desktop presents the changed theme" drawn latency_done
  latency_report theme
  expect_poll "the repeated apply browser closes" 0 layer_count vgs:overlay
  expect "the queue settles after the repeated theme apply" idle theme_idle
  latency_previous="$latency_package"
done

latency_theme_samples="$(printf '%s\n' "${latency_theme_readings[@]}" | py_reply 'import json,sys; print(json.dumps([json.loads(line) for line in sys.stdin]))')" || fail "theme readings could not be collected"
expect "six theme changes meet the median and single-reading limits" within latency_theme_bound "$latency_theme_samples"
latency_theme_result="$(latency_theme_summary "$latency_theme_samples")" || fail "theme readings could not be summarized"
printf 'theme-latency: summary=%s\n' "$latency_theme_result"

type_keys -M logo -M ctrl -k w -m ctrl -m logo || fail "the wallpaper browser open failed"
expect_poll "the wallpaper browser reads cards" true latency_wall_value loaded
expect_poll "the wallpaper browser holds the keyboard" true latency_wall_value activeFocus
type_keys -k Right || fail "the wallpaper selection key failed"
expect "the wallpaper change reader arms" ok ipc theme-latency themeLatencyBegin wallpaper "file://$home/.config/vgshell/themes/$latency_previous/backgrounds/b.jpg" ''
latency_pressure_start
type_keys -k Return || fail "the wallpaper apply key failed"
expect_poll "the desktop presents the selected wallpaper" drawn latency_done
latency_report wallpaper
expect_poll "the wallpaper browser closes" 0 layer_count vgs:overlay

type_keys -M logo -M ctrl -k w -m ctrl -m logo || fail "held wallpaper browser failed"
expect_poll "the held-key browser takes keys" true latency_wall_value activeFocus
expect_poll "the held wallpaper selected picture has drawn before arming" ready ipc theme-latency selectedPictureReady
expect "the held-key frame observer arms" ok ipc theme-latency themeLatencyBegin step '' ''
type_keys -P Right -s 900 -p Right || fail "the held wallpaper key failed"
expect "held wallpaper steps keep the selected picture ready" ready latency_steps
type_keys -k Escape || fail "the held-key browser close failed"
expect_poll "the held-key browser closes" 0 layer_count vgs:overlay

# An install, an update and a removal made outside the open view must
# reach its retained answer without a new open-time catalog command.
type_keys -M logo -M ctrl -k t -m ctrl -m logo || fail "the refresh browser open failed"
expect_poll "the refresh browser holds the keyboard" true latency_theme_value activeFocus
type_keys latency || fail "the refresh card filter failed"
expect_poll "the refresh card is selected" '"latency"' latency_theme_value selectedName
latency_stamp() { latency_theme_value generations | py_reply 'import json,sys; print(json.load(sys.stdin).get("latency",0))'; }
latency_unchanged_stamp="$(latency_stamp)"
latency_extra() { latency_theme_value cards | py_reply 'import json,sys; cards=json.load(sys.stdin); found=next((c for c in cards if c["name"]=="latency-extra"),None); print("absent" if found is None else found["palette"]["accent"])'; }
mkdir -p -- "$home/.config/vgshell/themes/latency-extra"
printf '%s\n' '{"schemaVersion":1,"name":"latency-extra","tokens":{"palette":{"accent":"#abcdef"}}}' >"$home/.config/vgshell/themes/latency-extra/theme.json"
expect_poll "an installed package reaches the open list" '#abcdefff' latency_extra
expect "install keeps the selected theme" '"latency"' latency_theme_value selectedName
printf '%s\n' '{"schemaVersion":1,"name":"latency-extra","tokens":{"palette":{"accent":"#fedcba"}}}' >"$home/.config/vgshell/themes/latency-extra/theme.json"
expect_poll "an updated package reaches the open list" '#fedcbaff' latency_extra
expect "update keeps the selected theme" '"latency"' latency_theme_value selectedName
rm -- "${home:?}/.config/vgshell/themes/latency-extra/theme.json"
rmdir -- "${home:?}/.config/vgshell/themes/latency-extra"
expect_poll "a removed package leaves the open list" absent latency_extra
expect "removal keeps the selected theme" '"latency"' latency_theme_value selectedName
expect "unrelated changes keep the installed thumbnail cache URL" "$latency_unchanged_stamp" latency_stamp
expect "the package change reads settle before the timer check" idle theme_idle
expect_poll "the service has no refresh pending before the timer check" false ipc smoke readInstance service vgs.themes readingData
rm -- "${latency_started:?}"
expect "the registered refresh timer fires" ok ipc theme-latency serviceTimer
expect_poll "the timer refreshes the retained catalog" held latency_catalog_held
expect "the timer refresh settles" idle theme_idle
expect "timer refresh keeps the selected theme" '"latency"' latency_theme_value selectedName
type_keys -k Escape -k Escape || fail "the refresh browser close failed"
expect_poll "the refresh browser closes" 0 layer_count vgs:overlay

cp -p -- "$sandbox/vgshell-before-latency" "$repo/bin/vgshell"
rm -- "$repo/bin/vgshell.latency-real"
expect "the theme service disables after latency readings" ok ipc shell setPluginEnabled vgs.themes false
expect "vgs restores after latency readings" 'ok theme=vgs state=applied shell=applied' "${shell_env[@]}" "$repo/bin/vgshell" theme apply vgs
expect_poll "vgs restores the shell" vgs ipc smoke themeName
cp -p -- "$sandbox/hyprland-before-latency.lua" "$hypr_lua"
expect "latency input bindings restore" ok hypr reload config-only
rm -r -- "${home:?}/.config/vgshell/themes/latency" "${home:?}/.config/vgshell/themes/sample-peer" "${latency_previews:?}"
rm -- "$sandbox/latency-wallpaper.jpg"

expect "the latency observer drops" ok ipc smoke runnerDrop
rm -- "$repo/shell/ThemeLatencyProbe.qml"
python3 - "$repo" "$sandbox" <<'PY'
from pathlib import Path
import shutil, sys
repo, saved = map(Path, sys.argv[1:])
for name in ('shell/plugins/vgs.themes/Browser.qml', 'shell/plugins/vgs.themes/ThemeView.qml', 'shell/plugins/vgs.themes/ThemeCard.qml'):
    target = repo / name
    shutil.copy2(saved / (target.name + '.latency-original'), target)
PY
