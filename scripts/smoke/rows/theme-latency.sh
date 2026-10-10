# Theme browser timings on the nested seat. The probe stamps the first
# presented frame with visible cards and keyboard focus, or the changed
# desktop. IPC polls back to back; its round trips do not inflate the
# in-shell frame timestamp. Warm open: 240 ms, twice the highest of six
# readings (112, 120, 97, 98, 88, 97 ms) on cachy, 2026-10-04, load 11.95,
# CPU pressure 0.3 to 1.4%, compositor logs on. The owner allowed this
# measured bound after the original 100 ms target failed. Every reading
# above harness.sh's shared CPU pressure limit is unmeasured (exit 77),
# including fast readings. Missing pressure is unread. Theme summaries
# exclude busy samples and still fail measured median or single-reading
# misses. Every raw reading remains in the output.
# Theme change:
# six readings, median <=150 ms and every reading <=292 ms. Owner ruling
# ask 1791136884-3060298-761, 2026-10-04: the median holds the desk target;
# the single-reading ceiling guards a slowdown under fleet load. On cachy,
# 2026-10-04, twelve readings at load 3.2 to 3.5 had min/median/max
# 89/108/132 ms. Six at load 8.6: 171, 93, 158, 116, 108, 121 ms,
# CPU pressure 0.3 to 0.8%, compositor logs on.
# Wallpaper keeps its 150 ms bound.
# Each theme change prints a split line, the ms of each part of the change
# (latency_split), and each reading keeps the probe's marks, its frame
# starts and presents and the probe's own ms. The browser is off the screen
# when its window hides, the split's `close`, and the summon host hides
# that window before the plugin unloads, which each theme change checks
# (latency_hide_order). A held-answer reading after
# the six, outside their median, holds the judge's exit while the browser
# must close on the publish alone.
# inputs: shell/plugins/vgs.themes/* shell/Core/ThemeRunner.qml shell/Commons/Theme* shell/Ui/layout/CardCarousel.qml shell/Hosts/SummonHost.qml shell/Hosts/SummonLayer.qml themes/* bin/vgshell bin/vgshell-theme-judge bin/lib/* scripts/smoke/rows/hyprland-consent.sh scripts/smoke/ThemeLatencyProbe.qml scripts/smoke/theme-latency-stamps.js scripts/smoke/fixtures/theme-image.jpg
set -euo pipefail
# Exercise the actual QML reader under Node with controlled presented frames.
# These controls hold dismissal, which is the hide of the browser's window,
# wallpaper readiness and selected content.
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
    const result = { children, visible: true, Window: { window: null }, toString: () => type };
    for (const child of children) child.parent = result;
    return result;
}
function reader(text) {
    let clock = 10;
    const context = vm.createContext({ root: { themeLatency: null, browserWindow: null }, Theme: { name: 'latency' }, Plugins: { built: { overlay: [] } }, Image, Date: { now: () => clock++ } });
    for (const name of ['typeName', 'descendants', 'browserParts', 'catalogWaiting', 'visibleInTree', 'desktopExposed', 'coverChanged', 'latencyMark', 'requestDesktopFrame', 'backgroundReady', 'selectedCard', 'cardPicture', 'selectedPictureReady', 'latencyFrame', 'readFrame', 'frameLog']) vm.runInContext(declaration(text, name), context);
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
    // The browser's window is still mapped and its plugin row has already
    // left the built list, as when the window is left to its destruction.
    const browserWindow = { visible: true };
    c.begin('theme', 'latency', 'file:///a.jpg');
    c.root.browserWindow = browserWindow;
    c.coverChanged();
    assert.equal(c.root.themeLatency.uncovered, undefined, 'a window mapped after its row left the built list must not stamp uncovered');
    c.latencyFrame(bar, 'bar'); c.latencyFrame(background, 'background');
    assert.equal(c.root.themeLatency.drawn, undefined, 'mapped browser must block theme completion');
    browserWindow.visible = false; c.coverChanged();
    assert.equal(typeof c.root.themeLatency.uncovered, 'number', 'the hidden window must stamp uncovered');
    browserWindow.visible = true;
    c.begin('wallpaper', 'file:///a.jpg');
    c.latencyFrame(background, 'background');
    assert.equal(c.root.themeLatency.drawn, undefined, 'mapped browser must block wallpaper completion');
    browserWindow.visible = false;
    c.latencyFrame(bar, 'bar');
    assert.equal(typeof c.root.themeLatency.drawn, 'number', 'exposed frame must complete with the retained ready wallpaper');
    c.begin('theme', 'latency', 'file:///a.jpg');
    browserWindow.visible = true;
    c.latencyFrame(bar, 'bar'); c.latencyFrame(background, 'background');
    // A deleted window reads as null.
    image.status = Image.Loading; c.root.browserWindow = null;
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
    c.Theme.name = 'before';
    c.begin('theme', 'latency', 'file:///a.jpg'); c.latencyFrame(background, 'background'); c.latencyFrame(bar, 'bar');
    assert.equal(c.root.themeLatency.drawn, undefined, 'a bar frame before the theme publishes must not complete it');
    c.Theme.name = 'latency'; c.latencyFrame(bar, 'bar');
    assert.equal(typeof c.root.themeLatency.drawn, 'number', 'a wallpaper frame drawn before the theme publishes must count');
    // A warm open waits for every catalog card, then for each visible
    // card's picture.
    const openPicture = new Image('file:///a.jpg', Image.Loading), openCard = item('ThemeCard', [openPicture]);
    openCard.current = true; openCard.picture = 'file:///a.jpg'; openCard.modelData = { name: 'a' };
    const openView = item('ThemeView', [openCard]);
    Object.assign(openView, { cards: [], packages: [], entries: [{ name: 'a' }, { name: 'b' }], shownCards: [{ name: 'a' }], activeFocus: true });
    const openBrowser = item('Browser', [openView]);
    c.begin('open', 'warm');
    c.latencyFrame(openBrowser, 'overlay');
    assert.equal(c.root.themeLatency.drawn, undefined, 'a warm open must wait for a catalog entry with no card');
    assert.equal(c.root.themeLatency.waits[c.root.themeLatency.waits.length - 1][1], 'cards');
    openView.entries = [{ name: 'a' }]; c.latencyFrame(openBrowser, 'overlay');
    assert.equal(c.root.themeLatency.drawn, undefined, 'a warm open must wait for a loading picture');
    assert.equal(c.root.themeLatency.waits[c.root.themeLatency.waits.length - 1][1], 'pictures=1');
    openPicture.status = Image.Ready; c.latencyFrame(openBrowser, 'overlay');
    assert.equal(typeof c.root.themeLatency.drawn, 'number', 'a warm open completes once every visible picture is ready');
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
    ['window mapped after its row left', 'return !window || !window.visible;', 'return !(Plugins.built.overlay || []).some(row => row.id === "vgs.themes");'],
    ['uncovered waits for the hide', ' || !desktopExposed()) return;\n        latencyMark("uncovered");', ') return;\n        latencyMark("uncovered");'],
    ['wallpaper readiness', 'if (reading.barFrame === undefined || (reading.background !== "" && reading.backgroundFrame === undefined)) return;', 'if (reading.barFrame === undefined) return;'],
    ['live requested wallpaper', 'if (background !== "" && !backgroundReady(background)) return;', ''],
    ['missing selected picture', 'if (card === undefined || !visibleInTree(card)) { reading.late = (reading.late || 0) + 1; return; }', 'if (card === undefined || !visibleInTree(card)) return;'],
    ['low selected picture', 'if (picture !== null && picture.low) reading.low = (reading.low || 0) + 1;', ''],
    ['a low picture is not full', '&& !picture.low && reading.full[key]', '&& reading.full[key]'],
    ['an unmeasured file is low', 'size === undefined || size[0]', 'size !== undefined && size[0]'],
    ['bar waits for the published theme', '            if (Theme.name !== reading.want) return;\n            if (kind === "bar")', '            if (kind === "bar")'],
    ['warm open waits for pictures', 'if (!shown.some(image => image.status === Image.Ready)) pending++;', 'if (!shown.some(image => image.status === Image.Ready)) ;'],
    ['warm open waits for every card', 'if (view.shownCards.length !== Object.keys(names).length) return "cards";', ''],
    ['wallpaper frame before the publish', '            if (kind === "background" && descendants(item).some(child => child instanceof Image && child.status === Image.Ready && String(child.source).split("?")[0] === reading.background)) reading.backgroundFrame = frameTime - reading.started;\n            if (Theme.name !== reading.want) return;\n', '            if (Theme.name !== reading.want) return;\n            if (kind === "background" && descendants(item).some(child => child instanceof Image && child.status === Image.Ready && String(child.source).split("?")[0] === reading.background)) reading.backgroundFrame = frameTime - reading.started;\n']
];
for (const [label, needle, replacement] of controls) {
    assert.equal(source.split(needle).length, 2, label + ': exact control match');
    assert.throws(() => verify(source.replace(needle, replacement)), { name: 'AssertionError' }, label + ': reader without this rule must fail');
}
console.log('theme-latency-reader: ok controls=13 browser-held=refused window-mapped=refused uncovered-mapped=refused wallpaper-loading=refused retained-live=refused selected-missing=refused selected-low=refused low-full=refused unmeasured-low=refused bar-unpublished=refused wallpaper-before-publish=refused open-pictures=refused open-cards=refused');
JS

cp -- "$repo/scripts/smoke/ThemeLatencyProbe.qml" "$repo/shell/ThemeLatencyProbe.qml"
expect "the latency observer loads" ok ipc smoke runnerLoad "$repo/shell/ThemeLatencyProbe.qml"

# Host memory and I/O pressure are advisory measurements, not budget exceptions.
# Unavailable PSI stays unmeasured; an observed zero is a different result.
latency_memory_io_us() {
  local resource kind rest total
  for resource in memory io; do
    total=""
    { while read -r kind rest; do
        if [[ $kind == some && $rest =~ total=([0-9]+) ]]; then total="${BASH_REMATCH[1]}"; break; fi
      done <"/proc/pressure/$resource"; } 2>/dev/null || true
    printf '%s\n' "$total"
  done
}
# The overseer's timing comparison reads this object beside the drawn result.
# The window includes the IPC wait through the read, not only the frame latency.
latency_contention() {
  printf '{}\n' | py_reply 'import json,re,sys
values=[float(x) if re.fullmatch(r"[0-9]+\.[0-9]",x) else None for x in sys.argv[1:4]]
load=float(sys.argv[5]) if re.fullmatch(r"[0-9]+(?:\.[0-9]+)?",sys.argv[5]) else None
print(json.dumps(dict(zip(["cpu_some_pct","memory_some_pct","io_some_pct"],values)) | {"window_ms":int(sys.argv[4]),"load_average":load,"scope":"host"}))' "$@"
}
expect "contention keeps measured zero and nonzero pressure" '{"cpu_some_pct": 0.0, "memory_some_pct": 1.2, "io_some_pct": 2.3, "window_ms": 100, "load_average": 6.25, "scope": "host"}' latency_contention 0.0 1.2 2.3 100 6.25
expect "contention keeps unavailable pressure distinct from zero" '{"cpu_some_pct": null, "memory_some_pct": null, "io_some_pct": 0.0, "window_ms": 100, "load_average": null, "scope": "host"}' latency_contention unmeasured unmeasured 0.0 100 unmeasured

# A theme reading with its apply process's stamps from STAMPS, the last
# line the stand-in started after the reading did, as ms from its start,
# and `split`: the ms each part of the change took, in order. queue: the
# key press to the queued job; launch: to the stand-in's start; runner:
# bin/vgshell to node; boot: node's start; judge: the judge up to the
# theme file; seen: to the shell's watcher; read: the read and the judge
# in the shell to the new name; bound: the tokens bound to the revision;
# close: the revision to the hide of the browser's window, when the browser
# is off the screen; frame: to the drawn frame, which waits behind the
# teardown of that window: the bar's frame swaps on the render thread, and
# its stamp is handled on the GUI thread after the teardown.
# Off the drawn path: hooks: applied.json and the reload hooks, which run
# after the theme file, to the process's exit; reply: the exit to the
# answer; answer: the hide to the answer, positive when the answer came
# after the browser was off the screen. A part whose ends are missing is
# null.
latency_split() { # VALUE [STAMPS]
  printf '%s' "$1" | py_reply 'import json,sys
x=json.load(sys.stdin)
start=x["started"]
rows=[]
try:
    with open(sys.argv[1]) as f: rows=[json.loads(line) for line in f if line.strip()]
except FileNotFoundError: pass
mine=[r for r in rows if r.get("spawned",0)>=start]
p={k:v-start for k,v in mine[-1].items()} if mine else {}
x["process"]=p
q=next((j["queued"] for j in x.get("jobs",[]) if j["verb"]=="apply"),None)
def gap(a,b): return None if a is None or b is None else b-a
x["split"]={"queue":q,"launch":gap(q,p.get("spawned")),"runner":gap(p.get("spawned"),p.get("node")),"boot":gap(p.get("node"),p.get("ready")),"judge":gap(p.get("ready"),p.get("theme")),"seen":gap(p.get("theme"),x.get("seen")),"read":gap(x.get("seen"),x.get("named")),"bound":gap(x.get("named"),x.get("published")),"close":gap(x.get("published"),x.get("uncovered")),"frame":gap(x.get("uncovered"),x.get("drawn")),"hooks":gap(p.get("applied"),p.get("exit")),"reply":gap(p.get("exit"),x.get("answered")),"answer":gap(x.get("uncovered"),x.get("answered"))}
print(json.dumps(x))' "${2-$latency_stamps}"
}
latency_split_field() { latency_split "$@" | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["split"], sort_keys=True))'; }
latency_split_control="$sandbox/latency-split-control"
printf '%s\n' '{"spawned":900,"node":1015,"ready":1030,"theme":1080,"applied":1082,"exit":1090}' '{"spawned":1012,"node":1020,"ready":1035,"theme":1070,"applied":1072,"exit":1110}' >"$latency_split_control"
expect "the split reads the reading's own apply process" '{"answer": 14, "boot": 15, "bound": 8, "close": 4, "frame": 30, "hooks": 38, "judge": 35, "launch": 4, "queue": 8, "read": 12, "reply": 3, "runner": 8, "seen": 5}' latency_split_field '{"started":1000,"jobs":[{"verb":"list","queued":2},{"verb":"apply","queued":8}],"seen":75,"named":87,"published":95,"uncovered":99,"answered":113,"drawn":129}' "$latency_split_control"
expect "the split takes no earlier reading's process and leaves its parts null" '{"answer": null, "boot": null, "bound": null, "close": null, "frame": null, "hooks": null, "judge": null, "launch": null, "queue": null, "read": null, "reply": null, "runner": null, "seen": null}' latency_split_field '{"started":5000,"jobs":[]}' "$latency_split_control"
rm -- "$latency_split_control"
# What closed the browser in theme reading VALUE: `publish` when the probe
# saw its window hidden before the apply's answer, or with no answer yet,
# else `answer`.
latency_close_on_publish() { # VALUE
  printf '%s' "$1" | py_reply 'import json,sys
x=json.load(sys.stdin)
u=x.get("uncovered"); a=x.get("answered")
print("publish" if type(u) is int and (a is None or a>u) else "answer")'
}
# Which went first in theme reading VALUE: `window-first` when the
# browser's window hid no later than its plugin row left the built list, as
# the summon host orders a hide; `teardown-first` when the window outlived
# the row, as a window left to its destruction does; `unread` without both
# marks.
latency_hide_order() { # VALUE
  printf '%s' "$1" | py_reply 'import json,sys
x=json.load(sys.stdin)
u=x.get("uncovered"); b=x.get("unbuilt")
print("unread" if type(u) is not int or type(b) is not int else "window-first" if u<=b else "teardown-first")'
}
expect "the hide order takes a window hidden in the turn its row leaves" window-first latency_hide_order '{"uncovered":99,"unbuilt":99}'
expect "the hide order rejects a window that outlived its row" teardown-first latency_hide_order '{"uncovered":127,"unbuilt":107}'
expect "the hide order refuses a reading without the hide" unread latency_hide_order '{"unbuilt":107}'
# The split line a theme reading prints: its parts beside the probe's marks.
latency_split_line() { # VALUE
  printf '%s' "$1" | py_reply 'import json,sys; x=json.load(sys.stdin); print(json.dumps(dict(x["split"], drawn=x.get("drawn"), wallReady=x.get("wallReady"), hyprReloaded=x.get("hyprReloaded"), probeMs=x.get("probeMs"), frames=x.get("frames",{}))))'
}
latency_read() { ipc theme-latency themeLatencyRead; }
latency_done() { latency_read | py_reply 'import json,sys; print("drawn" if "drawn" in json.load(sys.stdin) else "pending")'; }
latency_report() {
  local value end_ms pressure resources memory_pressure io_pressure contention cpu_end
  value="$(latency_read)" || return 1
  mapfile -t resources < <(latency_memory_io_us)
  cpu_end="$(cpu_some_us)"
  # The window closes at the reading, before the verdict reads its pressure.
  end_ms="$(now_ms)"
  pressure="$(cpu_some_pct "$latency_cpu_start" "$cpu_end" "$((end_ms - latency_window_start))")"
  memory_pressure="$(cpu_some_pct "$latency_memory_start" "${resources[0]}" "$((end_ms - latency_window_start))")"
  io_pressure="$(cpu_some_pct "$latency_io_start" "${resources[1]}" "$((end_ms - latency_window_start))")"
  contention="$(latency_contention "$pressure" "$memory_pressure" "$io_pressure" "$((end_ms - latency_window_start))" "$latency_load")" || return 1
  value="$(printf '%s' "$value" | py_reply 'import json,sys; value=json.load(sys.stdin); value["contention"]=json.loads(sys.argv[1]); print(json.dumps(value))' "$contention")" || return 1
  [[ $1 != theme ]] || value="$(latency_split "$value")" || return 1
  [[ $1 != theme ]] || expect "the browser's window hides before its plugin unloads" window-first latency_hide_order "$value"
  if [[ $1 != open-cold ]]; then
    local bound=150 planted verdict drawn reading=$1
    [[ $1 == open-warm ]] && bound=240
    if [[ $1 == theme ]]; then
      reading="theme-$(( ${#latency_theme_readings[@]} + 1 ))"
    fi
    verdict="$(latency_verdict "$value" "$bound")" || verdict=unread
    value="$(printf '%s' "$value" | py_reply 'import json,sys; x=json.load(sys.stdin); x["result"]=sys.argv[1]; print(json.dumps(x))' "$verdict")" || return 1
    [[ $1 != theme ]] || latency_theme_readings+=("$value")
    if [[ $verdict == unmeasured ]]; then
      drawn="$(printf '%s' "$value" | py_reply 'import json,sys; print(json.load(sys.stdin).get("drawn"))')" || drawn=unread
      not_measured theme-latency "${reading}=${drawn}ms-at-cpu_some_pct=${pressure}-above-${latency_pressure_limit}"
    elif [[ $1 != theme ]]; then
      expect "$1 meets its $bound ms bound" within latency_verdict "$value" "$bound"
    fi
    [[ $1 == theme ]] && bound=292
    planted="$(printf '%s' "$value" | py_reply 'import json,sys; x=json.load(sys.stdin); x["drawn"]=int(sys.argv[1])+1; x["contention"]["cpu_some_pct"]=float(sys.argv[2]); print(json.dumps(x))' "$bound" "$latency_pressure_limit")" || planted=unread
    expect "$1 rejects a reading over its bound" over latency_verdict "$planted" "$bound"
  fi
  printf 'theme-latency: reading=%s value=%s\n' "$1" "$value"
  [[ $1 != theme ]] || printf 'theme-latency: split=%s\n' "$(latency_split_line "$value")"
  printf 'theme-latency: load=%s cpu_some_pct=%s pressure_window_ms=%s\n' "$latency_load" "$pressure" "$((end_ms - latency_window_start))"
}
latency_pressure_start() {
  local resources
  latency_load="$(cut -d ' ' -f 1 /proc/loadavg)"
  latency_window_start="$(now_ms)"
  latency_cpu_start="$(cpu_some_us)"
  mapfile -t resources < <(latency_memory_io_us)
  latency_memory_start="${resources[0]}"
  latency_io_start="${resources[1]}"
}
# Parse the frame reader's data here; the harness alone judges pressure.
latency_verdict() { # JSON BUDGET_MS
  local fields
  fields="$(printf '%s' "$1" | py_reply 'import json,sys
x=json.load(sys.stdin)
value=x.get("drawn") if isinstance(x,dict) else None
contention=x.get("contention") if isinstance(x,dict) else None
pressure=contention.get("cpu_some_pct") if isinstance(contention,dict) else None
print(value if type(value) is int and value>=0 else "unmeasured")
print(pressure if type(pressure) in (int,float) else "unmeasured")')" || { echo unread; return; }
  local -a values
  mapfile -t values <<<"$fields"
  latency_pressure_verdict "${values[0]:-}" "${values[1]:-}" "$2"
}
latency_theme_readings=()
latency_theme_summary() {
  local rows reading result
  local -a verdicts=()
  rows="$(printf '%s' "$1" | py_reply 'import json,sys
x=json.load(sys.stdin)
if isinstance(x,list):
    for row in x: print(json.dumps(row))')" || return 1
  while IFS= read -r reading; do
    result="$(latency_verdict "$reading" 292)" || return 1
    verdicts+=("$result")
  done <<<"$rows"
  printf '%s' "$1" | py_reply 'import json,statistics,sys
rows=json.load(sys.stdin)
verdicts=sys.argv[1:]
values=[x.get("drawn") if isinstance(x,dict) else None for x in rows] if isinstance(rows,list) else []
valid=len(values)==6 and len(verdicts)==len(values) and all(type(x) is int and x>=0 for x in values)
median=statistics.median(values) if valid else None
maximum=max(values) if valid else None
measured=[x for x,v in zip(values,verdicts) if v in ("within","over")]
measured_median=statistics.median(measured) if valid and measured else None
failed=any(v=="over" for v in verdicts) or (measured_median is not None and measured_median>150)
result="unread" if not valid or "unread" in verdicts else "over" if failed else "unmeasured" if "unmeasured" in verdicts else "within"
print(json.dumps({"readings_ms":values,"median_ms":median,"max_ms":maximum,"measured_median_ms":measured_median,"not_measured_indices":[i+1 for i,v in enumerate(verdicts) if v=="unmeasured"],"result":result}))' "${verdicts[@]}"
}
latency_theme_bound() { latency_theme_summary "$1" | py_reply 'import json,sys; print(json.load(sys.stdin)["result"])'; }
# Each control violates only one part of the six-reading rule.
expect "theme median over 150 ms fails below the single-reading ceiling" over latency_theme_bound '[{"drawn":151,"contention":{"cpu_some_pct":0.0}},{"drawn":151,"contention":{"cpu_some_pct":0.0}},{"drawn":151,"contention":{"cpu_some_pct":0.0}},{"drawn":151,"contention":{"cpu_some_pct":0.0}},{"drawn":151,"contention":{"cpu_some_pct":0.0}},{"drawn":151,"contention":{"cpu_some_pct":0.0}}]'
expect "theme reading over 292 ms fails below the median limit" over latency_theme_bound '[{"drawn":293,"contention":{"cpu_some_pct":0.0}},{"drawn":100,"contention":{"cpu_some_pct":0.0}},{"drawn":100,"contention":{"cpu_some_pct":0.0}},{"drawn":100,"contention":{"cpu_some_pct":0.0}},{"drawn":100,"contention":{"cpu_some_pct":0.0}},{"drawn":100,"contention":{"cpu_some_pct":0.0}}]'
expect "theme median at 150 ms and reading at 292 ms pass" within latency_theme_bound '[{"drawn":292,"contention":{"cpu_some_pct":0.0}},{"drawn":150,"contention":{"cpu_some_pct":0.0}},{"drawn":150,"contention":{"cpu_some_pct":0.0}},{"drawn":150,"contention":{"cpu_some_pct":0.0}},{"drawn":150,"contention":{"cpu_some_pct":0.0}},{"drawn":0,"contention":{"cpu_some_pct":0.0}}]'
for latency_control_bound in 150 240 292; do
  latency_control_slow="$((latency_control_bound + 1))"
  expect "slow reading at low pressure fails: $latency_control_bound" over latency_verdict "{\"drawn\":$latency_control_slow,\"contention\":{\"cpu_some_pct\":1.0}}" "$latency_control_bound"
  expect "slow reading at threshold fails: $latency_control_bound" over latency_verdict "{\"drawn\":$latency_control_slow,\"contention\":{\"cpu_some_pct\":2.8}}" "$latency_control_bound"
  expect "slow reading above threshold is not measured: $latency_control_bound" unmeasured latency_verdict "{\"drawn\":$latency_control_slow,\"contention\":{\"cpu_some_pct\":2.9}}" "$latency_control_bound"
  expect "fast reading above threshold is not measured: $latency_control_bound" unmeasured latency_verdict "{\"drawn\":$latency_control_bound,\"contention\":{\"cpu_some_pct\":30.0}}" "$latency_control_bound"
  expect "slow reading with missing pressure is unread: $latency_control_bound" unread latency_verdict "{\"drawn\":$latency_control_slow}" "$latency_control_bound"
  expect "slow reading with unreadable pressure is unread: $latency_control_bound" unread latency_verdict "{\"drawn\":$latency_control_slow,\"contention\":{\"cpu_some_pct\":null}}" "$latency_control_bound"
  expect "slow reading with text pressure is unread: $latency_control_bound" unread latency_verdict "{\"drawn\":$latency_control_slow,\"contention\":{\"cpu_some_pct\":\"30.0\"}}" "$latency_control_bound"
  expect "missing reading above threshold is unread: $latency_control_bound" unread latency_verdict '{"contention":{"cpu_some_pct":30.0}}' "$latency_control_bound"
done
# Keep pressure attached to each sample. A busy sample excludes only itself.
expect "slow busy theme makes the batch not measured" unmeasured latency_theme_bound '[{"drawn":293,"contention":{"cpu_some_pct":30.0}},{"drawn":100,"contention":{"cpu_some_pct":0.0}},{"drawn":100,"contention":{"cpu_some_pct":0.0}},{"drawn":100,"contention":{"cpu_some_pct":0.0}},{"drawn":100,"contention":{"cpu_some_pct":0.0}},{"drawn":100,"contention":{"cpu_some_pct":0.0}}]'
expect "fast busy themes cannot lower a measured failing median" over latency_theme_bound '[{"drawn":151,"contention":{"cpu_some_pct":1.0}},{"drawn":151,"contention":{"cpu_some_pct":1.0}},{"drawn":151,"contention":{"cpu_some_pct":1.0}},{"drawn":0,"contention":{"cpu_some_pct":30.0}},{"drawn":0,"contention":{"cpu_some_pct":30.0}},{"drawn":0,"contention":{"cpu_some_pct":30.0}}]'
expect "busy theme cannot hide a failing single low-pressure reading" over latency_theme_bound '[{"drawn":293,"contention":{"cpu_some_pct":1.0}},{"drawn":500,"contention":{"cpu_some_pct":30.0}},{"drawn":0,"contention":{"cpu_some_pct":0.0}},{"drawn":0,"contention":{"cpu_some_pct":0.0}},{"drawn":0,"contention":{"cpu_some_pct":0.0}},{"drawn":0,"contention":{"cpu_some_pct":0.0}}]'
expect "busy theme cannot hide a failing low-pressure median" over latency_theme_bound '[{"drawn":151,"contention":{"cpu_some_pct":0.0}},{"drawn":151,"contention":{"cpu_some_pct":0.0}},{"drawn":151,"contention":{"cpu_some_pct":0.0}},{"drawn":151,"contention":{"cpu_some_pct":0.0}},{"drawn":151,"contention":{"cpu_some_pct":0.0}},{"drawn":500,"contention":{"cpu_some_pct":30.0}}]'
expect "fast busy themes are not measured" unmeasured latency_theme_bound '[{"drawn":100,"contention":{"cpu_some_pct":30.0}},{"drawn":100,"contention":{"cpu_some_pct":30.0}},{"drawn":100,"contention":{"cpu_some_pct":30.0}},{"drawn":100,"contention":{"cpu_some_pct":30.0}},{"drawn":100,"contention":{"cpu_some_pct":30.0}},{"drawn":100,"contention":{"cpu_some_pct":30.0}}]'
expect "theme summary refuses missing pressure" unread latency_theme_bound '[{"drawn":100},{"drawn":100},{"drawn":100},{"drawn":100},{"drawn":100},{"drawn":100}]'
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
cp -- "$repo/scripts/smoke/fixtures/theme-image.jpg" "$home/.config/vgshell/themes/latency/backgrounds/a.jpg"
cp -- "$repo/scripts/smoke/fixtures/theme-image.jpg" "$home/.config/vgshell/themes/latency/backgrounds/b.jpg"
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
# Each apply's judge stamps its parts into this file, one line a process.
latency_stamps="$sandbox/latency-apply-stamps"
# While this file exists the judge holds its exit, so the answer waits,
# for at most twice the harness's poll bound: a view that waits for the
# answer fails the close poll before the hold lets the answer through.
latency_hold="$sandbox/latency-answer-hold"
latency_hold_ms=$((2 * smoke_poll_bound_ms))
cat >"$repo/bin/vgshell" <<EOF
#!/usr/bin/env bash
if [[ \${1-} == theme && \${2-} == catalog ]]; then
  touch '$latency_started'
  while [[ ! -e '$latency_gate' ]]; do sleep 0.01; done
fi
if [[ \${1-} == theme && \${2-} == apply ]]; then
  export VGS_LATENCY_SPAWNED="\$EPOCHREALTIME" VGS_LATENCY_STAMPS='$latency_stamps' VGS_LATENCY_HOLD='$latency_hold' VGS_LATENCY_HOLD_MS='$latency_hold_ms'
  export NODE_OPTIONS="\${NODE_OPTIONS:+\$NODE_OPTIONS }--require=$repo/scripts/smoke/theme-latency-stamps.js"
fi
exec '$repo/bin/vgshell.latency-real' "\$@"
EOF
chmod +x "$repo/bin/vgshell"
latency_catalog_held() { [[ -e $latency_started ]] && echo held || echo pending; }
# The switch reading's catalog themes, the filter `ar` shows, draw the
# package previews they ship; in the sandbox copy lunar's is the small
# test image instead, its control.
latency_lunar="$repo/themes/catalog/lunar/preview.jpg"
cp -p -- "$latency_lunar" "$sandbox/latency-lunar-preview.jpg"
cp -- "$repo/scripts/smoke/fixtures/theme-image.jpg" "$latency_lunar"
expect "the theme service enables for latency readings" ok ipc shell setPluginEnabled vgs.themes true
expect_poll "the theme service builds" false ipc smoke readInstance service vgs.themes setupPending
expect_poll "the catalog answer is held behind installed rows" held latency_catalog_held

printf 'theme-latency: host=%s date=%s warm_samples=6 ipc_poll=back-to-back compositor_logs=on\n' "$(hostname)" "$(date -u +%Y-%m-%d)"
for temperature in cold warm warm warm warm warm warm; do
  latency_pressure_start
  expect "the $temperature open reader arms" ok ipc theme-latency themeLatencyBegin open "$temperature" ''
  type_keys -M logo -M shift -k t -m shift -m logo || fail "the theme open key failed"
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

type_keys -M logo -M shift -k t -m shift -m logo || fail "the held theme browser open failed"
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
type_keys -M logo -M shift -k t -m shift -m logo || fail "the switch browser open failed"
expect_poll "the switch browser holds the keyboard" true latency_theme_value activeFocus
type_keys ar || fail "the switch filter failed"
expect_poll "the switch filter selects the first catalog theme" '"arc-blueberry"' latency_theme_value selectedName
expect_poll "the first switch picture has drawn before arming" ready ipc theme-latency selectedPictureReady
expect "the switch frame observer arms" ok ipc theme-latency themeLatencyBegin step '' ''
latency_files=("$repo"/themes/catalog/*/preview.jpg)
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
# Control: lunar's preview is the small test image, which the card can
# only draw stretched; the reader counts its frames.
type_keys -k Right || fail "the control switch key failed"
expect_poll "the control switch selects lunar" '"lunar"' latency_theme_value selectedName
expect_poll "control: a picture smaller than its card reads as low" True latency_low_seen
type_keys -k Escape -k Escape || fail "the switch browser close failed"
expect_poll "the switch browser closes" 0 layer_count vgs:overlay

type_keys -M logo -M shift -k t -m shift -m logo || fail "the apply browser open failed"
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
latency_pressure_start
expect "the theme change reader arms" ok ipc theme-latency themeLatencyBegin theme latency "file://$home/.config/vgshell/themes/latency/backgrounds/a.jpg"
type_keys -k Return || fail "the apply key failed"
expect_poll "the desktop presents the applied theme" drawn latency_done
latency_report theme
touch -- "$latency_gate"
expect_poll "the apply browser closes" 0 layer_count vgs:overlay
expect "the queue settles after theme apply" idle theme_idle

# Alternate installed packages so every sample writes a changed theme.
latency_previous=latency
for latency_package in sample-peer latency sample-peer latency sample-peer; do
  type_keys -M logo -M shift -k t -m shift -m logo || fail "the repeated apply browser open failed"
  expect_poll "the repeated apply browser reads cards" true latency_theme_value loaded
  expect_poll "the repeated apply browser holds the keyboard" true latency_theme_value activeFocus
  type_keys "$latency_package" || fail "the repeated apply filter failed"
  expect_poll "the repeated apply card is selected" "\"$latency_package\"" latency_theme_value selectedName
  expect "the next sample starts from a different published theme" "$latency_previous" ipc smoke themeName
  latency_pressure_start
  expect "the repeated theme reader arms" ok ipc theme-latency themeLatencyBegin theme "$latency_package" "file://$home/.config/vgshell/themes/$latency_package/backgrounds/a.jpg"
  type_keys -k Return || fail "the repeated theme apply key failed"
  expect_poll "the repeated desktop presents the changed theme" drawn latency_done
  latency_report theme
  expect_poll "the repeated apply browser closes" 0 layer_count vgs:overlay
  expect "the queue settles after the repeated theme apply" idle theme_idle
  latency_previous="$latency_package"
done

latency_theme_samples="$(printf '%s\n' "${latency_theme_readings[@]}" | py_reply 'import json,sys; print(json.dumps([json.loads(line) for line in sys.stdin]))')" || fail "theme readings could not be collected"
latency_theme_result="$(latency_theme_summary "$latency_theme_samples")" || fail "theme readings could not be summarized"
printf 'theme-latency: summary=%s\n' "$latency_theme_result"
latency_theme_status="$(printf '%s' "$latency_theme_result" | py_reply 'import json,sys; print(json.load(sys.stdin)["result"])')" || latency_theme_status=unread
if [[ $latency_theme_status != unmeasured ]]; then
  expect "six theme changes meet the median and single-reading limits" within latency_theme_bound "$latency_theme_samples"
fi

# The held-answer reading: the judge holds its exit, after applied.json and
# the reload hooks, until the gate goes, so the browser must close on the
# publish before the release.
latency_answer_state() { latency_read | py_reply 'import json,sys; print("answered" if "answered" in json.load(sys.stdin) else "held")'; }
touch -- "$latency_hold"
type_keys -M logo -M shift -k t -m shift -m logo || fail "the held-answer browser open failed"
expect_poll "the held-answer browser reads cards" true latency_theme_value loaded
expect_poll "the held-answer browser holds the keyboard" true latency_theme_value activeFocus
type_keys latency || fail "the held-answer filter failed"
expect_poll "the held-answer card is selected" '"latency"' latency_theme_value selectedName
expect "the held-answer apply starts from a different published theme" "$latency_previous" ipc smoke themeName
expect "the held-answer reader arms" ok ipc theme-latency themeLatencyBegin theme latency "file://$home/.config/vgshell/themes/latency/backgrounds/a.jpg"
type_keys -k Return || fail "the held-answer apply key failed"
expect_poll "the browser closes on the publish while the answer is held" 0 layer_count vgs:overlay
expect "the apply answer is still held after the browser closed" held latency_answer_state
rm -- "${latency_hold:?}"
expect "the queue settles once the answer is released" idle theme_idle
latency_held="$(latency_split "$(latency_read)")" || fail "the held-answer reading is unreadable"
printf 'theme-latency: reading=held-answer value=%s\n' "$latency_held"
printf 'theme-latency: split=%s\n' "$(latency_split_line "$latency_held")"
expect "the held-answer browser closed before the answer" publish latency_close_on_publish "$latency_held"
latency_planted="$(printf '%s' "$latency_held" | py_reply 'import json,sys; x=json.load(sys.stdin); a=x.get("answered", x.get("uncovered", 0)); x["answered"]=a; x["uncovered"]=a+1; print(json.dumps(x))')" || latency_planted=unread
expect "the close check rejects a browser removed after the answer" answer latency_close_on_publish "$latency_planted"
latency_previous=latency

type_keys -M logo -M shift -k w -m shift -m logo || fail "the wallpaper browser open failed"
expect_poll "the wallpaper browser reads cards" true latency_wall_value loaded
expect_poll "the wallpaper browser holds the keyboard" true latency_wall_value activeFocus
type_keys -k Right || fail "the wallpaper selection key failed"
latency_pressure_start
expect "the wallpaper change reader arms" ok ipc theme-latency themeLatencyBegin wallpaper "file://$home/.config/vgshell/themes/$latency_previous/backgrounds/b.jpg" ''
type_keys -k Return || fail "the wallpaper apply key failed"
expect_poll "the desktop presents the selected wallpaper" drawn latency_done
latency_report wallpaper
expect_poll "the wallpaper browser closes" 0 layer_count vgs:overlay

type_keys -M logo -M shift -k w -m shift -m logo || fail "held wallpaper browser failed"
expect_poll "the held-key browser takes keys" true latency_wall_value activeFocus
expect_poll "the held wallpaper selected picture has drawn before arming" ready ipc theme-latency selectedPictureReady
expect "the held-key frame observer arms" ok ipc theme-latency themeLatencyBegin step '' ''
type_keys -P Right -s 900 -p Right || fail "the held wallpaper key failed"
expect "held wallpaper steps keep the selected picture ready" ready latency_steps
type_keys -k Escape || fail "the held-key browser close failed"
expect_poll "the held-key browser closes" 0 layer_count vgs:overlay

# An install, an update and a removal made outside the open view must
# reach its retained answer without a new open-time catalog command.
type_keys -M logo -M shift -k t -m shift -m logo || fail "the refresh browser open failed"
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
expect "unrelated changes keep the installed image cache URL" "$latency_unchanged_stamp" latency_stamp
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
rm -f -- "${latency_stamps:?}"
expect "the theme service disables after latency readings" ok ipc shell setPluginEnabled vgs.themes false
expect "vgs restores after latency readings" 'ok theme=vgs state=applied shell=applied' "${shell_env[@]}" "$repo/bin/vgshell" theme apply vgs
expect_poll "vgs restores the shell" vgs ipc smoke themeName
cp -p -- "$sandbox/hyprland-before-latency.lua" "$hypr_lua"
expect "latency input bindings restore" ok hypr reload config-only
rm -r -- "${home:?}/.config/vgshell/themes/latency" "${home:?}/.config/vgshell/themes/sample-peer"
mv -T -- "$sandbox/latency-lunar-preview.jpg" "$latency_lunar"

expect "the latency observer drops" ok ipc smoke runnerDrop
rm -- "$repo/shell/ThemeLatencyProbe.qml"
