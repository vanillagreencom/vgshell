#!/usr/bin/env python3
"""The open-split instrument and its reader, for scripts/smoke/rows/open-split.sh.

prepare TREE stamps a disposable harness copy's shared creation path. Each
stamp is one shell log line, `open-split: {"e","id","kind","t"}`, `t` the
GUI thread's Date.now() in integer milliseconds. The stamps cover every
build of a summoned kind (PluginLogic.SUMMONABLE_KINDS) or a pane, the
kinds a host builds on open:

  request, returned   SummonHost.summon's entry and return, the open
                      handler's synchronous span on the host side
  mount, mounted      PaneHost.mount's entry and return, a pane selection
  attempt             Plugins.attemptInstance's entry
  load, loaded        around Qt.createComponent: component load
  created             after component.createObject: object creation
  attach, attached    around `instance.shell = facadeFor(...)`: the
                      shell-tool attachment and every binding it runs
  built               attemptInstance's built return, after the context,
                      the record and its refresh
  open, opened        around the plugin's own open(payload)
  start, frame        the instance window's first GUI-thread frame start
                      (afterAnimating) after the build, then the first
                      frameSwapped handled after that start: Qt queued the
                      frame, which is not compositor presentation
                      (doc.qt.io/qt-6/qml-qtquick-window.html#frameSwapped-signal)
  content             at that frame stamp, `target`, the instance's
                      initialFocus as Qt names the object, or null;
                      `focus`, whether it holds active focus; `active`,
                      whether the window has the keyboard; `views`, the
                      FirstViews in the instance; and `items`, the sorted
                      "Type:text" of every shown Text that meets the window
                      and every clipping ancestor, whatever its opacity: a
                      list row fading in (ListEntrance) is built content
  view, settled,      a FirstView (shell/Ui/layout/FirstView.qml) completes,
  unsettled, gone     turns settled, turns unsettled as new values arrive,
                      and is destroyed; `id` is view:<n>
  step                one deferred FirstView step: `t` its start, `ms` its
                      length; it is logged after the step, so after any
                      settle the step itself made. A step that starts a
                      block's load is logged again, `block` true, as the
                      load ends: `ms` runs from the step's start to the
                      load's end, so it holds the block's whole build,
                      which the engine's incubation pauses only once its
                      objects are created and between their bindings and
                      completion handlers, and bounds from above the
                      longest span the build holds the GUI thread

The instrument changes no product decision: it logs and connects to the
window's signals, disconnecting each after its first call.

framed LOG OFFSET KIND ID prints `framed` once the first open of KIND/ID
after byte OFFSET of LOG has its frame stamp, `no-open` when no such open
was logged yet, `no-build` when it returned without building KIND/ID, else
`pending`.

settled LOG OFFSET prints `settled` once every FirstView stamped after
OFFSET last turned settled or was destroyed, else `pending`; a log with
no view prints `settled`. A step stamp is no state.

content LOG OFFSET KIND ID SETTLED_JSON compares the open's frame content
stamp with SETTLED_JSON, the same record the probe reads once the
instance settles. It prints `no-view` when the settled instance holds no
FirstView: nothing is deferred, its first frame is its whole build, and
the check makes no claim on it. Else it prints `equal`, or `differs` with
the items only one side holds and both focus readings. The frame must
hold an item and the initial focus target, the same object that holds
active focus once settled. Active focus at the frame is reported, not
judged: a new surface takes the keyboard when the compositor gives it,
which can come after its first frame (the VPN panel's target, its body,
is built at creation and reads false there).

sweep TREE SOURCES FLOOR... reads `shell listPlugins` JSON on stdin and prints
the class sweep. TREE is the tree the shell runs, whose PluginLogic.js
names the summonable kinds (SUMMONABLE_KINDS), read under node through its
bin/lib/qml-library.js; an empty or unreadable kind set exits 2. SOURCES
is the probe's `pluginSources` reply, each listed plugin's `bundled` or
`installed` source as Registry.sourceOf names it,
since a listing row carries the plugin's dir and no source. The sweep
prints `excluded ID needs=WHAT` for each plugin EXCLUDED names,
`off ID needs=NAME` for a bundled plugin off that a missing requirement
keeps off, `enable ID` for each other bundled plugin off, then `entry
KIND ID` for each summonable kind (PluginLogic SUMMONABLE_KINDS) and
`pane ID` for each pane of a plugin enabled or to be enabled. FLOOR's
`KIND/ID` members, which the row measures on their own routes, are left
out. A listing that is not scanned or lists no plugin, a listed plugin
SOURCES does not name, an excluded plugin it does not list, or a FLOOR
member it does not discover exits 2: an incomplete discovery is never an
empty sweep.

reading LOG OFFSET KIND ID PLACE OPEN CPU_SOME_PCT OUT_JSON prints that
open's split figures, one line for each build inside it and one for the
open, writes them to OUT_JSON, and exits 0 when every figure was read and 1,
printing `missing=`, when one was not. A stamp line that does not parse
exits 2: an unreadable reading is never a figure. Figures are separate
spans, never a sum:

  build: load_ms create_ms lend_ms attach_ms settle_ms open_ms
    lend_ms is created to attach: the instance's row and its capability
    providers. settle_ms is attached to built. open_ms is the plugin's own
    open() of that build. `within` names the build whose open() holds it,
    as a pane's build sits in the System window's open, or `-`.
  open: sync_ms first_content_ms frame_start_ms settle_ms
        longest_step_ms
    sync_ms is request to returned (mount to mounted for a pane), the
    handler the user waits on; first_content_ms is returned to the first
    queued frame of the opened build's window; frame_start_ms is returned
    to that frame's GUI-thread start. From the frame to the last settle
    stamp, settle_ms is that span and longest_step_ms the longest step
    stamp. With no FirstView in the open both read 0. The row prints
    both and judges neither.
"""
import json
from pathlib import Path
import re
import subprocess
import sys

STAMP = re.compile(r"open-split: (.*?)\s*$")
OPENERS = {"request": "returned", "mount": "mounted"}
BUILD_SPANS = (("load_ms", "load", "loaded"), ("create_ms", "loaded", "created"),
               ("lend_ms", "created", "attach"), ("attach_ms", "attach", "attached"),
               ("settle_ms", "attached", "built"))


def replace_once(path, old, new):
    if path.is_symlink():
        raise ValueError(f"open-split: refused: symlink={path}")
    text = path.read_text()
    if text.count(old) != 1 or old == new:
        raise ValueError(f"open-split: match-count={text.count(old)} path={path} needle={old.splitlines()[0]!r}")
    path.write_text(text.replace(old, new))


PANE = '"pane"'


def mark(event, id_expr, kind_expr):
    return f'Plugins.openSplitMark("{event}", {id_expr}, {kind_expr});'


PLUGINS_HELPERS = '''    // open-split instrument (scripts/smoke/open-split.py), harness copy only.
    function openSplitKind(kind) { return Logic.SUMMONABLE_KINDS.indexOf(kind) !== -1 || kind === "pane"; }
    function openSplitMark(event, id, kind) {
        if (openSplitKind(kind)) console.info("open-split: " + JSON.stringify({ e: event, id: id, kind: kind, t: Date.now() }));
    }
    // The shown text of INSTANCE that meets its window: each visible Text
    // inside the window and inside every clipping ancestor, as "Type:text",
    // whatever its opacity; its initial focus target and the FirstViews in it.
    function openSplitContent(instance) {
        const win = instance === null ? null : instance.Window.window;
        if (win === null || win === undefined) return { target: null, focus: false, active: false, views: 0, items: [] };
        const meets = item => {
            const at = item.mapToItem(null, 0, 0);
            let box = { x: at.x, y: at.y, r: at.x + item.width, b: at.y + item.height };
            const cut = clip => { box = { x: Math.max(box.x, clip.x), y: Math.max(box.y, clip.y), r: Math.min(box.r, clip.r), b: Math.min(box.b, clip.b) }; };
            cut({ x: 0, y: 0, r: win.width, b: win.height });
            for (let up = item.parent; up !== null; up = up.parent)
                if (up.clip) {
                    const p = up.mapToItem(null, 0, 0);
                    cut({ x: p.x, y: p.y, r: p.x + up.width, b: p.y + up.height });
                }
            return box.r > box.x && box.b > box.y;
        };
        const items = [];
        const visit = item => {
            if (!item.visible) return;
            if (item instanceof Text && String(item.text) !== "" && item.width > 0 && item.height > 0 && meets(item))
                items.push(String(item).replace(/(_QMLTYPE_\\d+)?\\(.*$/, "") + ":" + String(item.text));
            for (const child of item.children) visit(child);
        };
        visit(instance);
        items.sort();
        let views = 0;
        const count = item => {
            if (item.firstViewRoot === true) views++;
            for (const child of item.children) count(child);
        };
        count(instance);
        const focus = instance.initialFocus === undefined ? null : instance.initialFocus;
        return { target: focus === null ? null : String(focus), focus: focus !== null && focus.activeFocus === true,
            active: win.active === true, views: views, items: items };
    }
    // The slot's window can arrive after the build (Quickshell creates a
    // window's backing QQuickWindow on its own schedule), so the hook
    // follows PluginSlot.inputWindow until it has one.
    function openSplitFrame(id, kind, slot) {
        if (!openSplitKind(kind)) return;
        let hooked = false;
        const hook = () => {
            const win = slot.inputWindow;
            if (hooked || win === null || win === undefined) return;
            hooked = true;
            slot.inputWindowChanged.disconnect(hook);
            let started = false;
            const onStart = () => {
                win.afterAnimating.disconnect(onStart);
                started = true;
                openSplitMark("start", id, kind);
            };
            const instance = slot.instance;
            const onSwap = () => {
                if (!started) return;
                win.frameSwapped.disconnect(onSwap);
                openSplitMark("frame", id, kind);
                const content = openSplitContent(instance);
                console.info("open-split: " + JSON.stringify(Object.assign({ e: "content", id: id, kind: kind, t: Date.now() }, content)));
            };
            win.afterAnimating.connect(onStart);
            win.frameSwapped.connect(onSwap);
        };
        slot.inputWindowChanged.connect(hook);
        hook();
    }

'''


def prepare(tree):
    plugins = tree / "shell/Core/Plugins.qml"
    facade_end = "            facade[name] = providers[name];\n        return facade;\n    }\n"
    replace_once(plugins, facade_end, facade_end + "\n" + PLUGINS_HELPERS)
    replace_once(plugins, '        const refused = { state: "refused" };\n',
                 '        openSplitMark("attempt", id, kind);\n        const refused = { state: "refused" };\n')
    replace_once(plugins, "        const component = Qt.createComponent(url);\n",
                 '        openSplitMark("load", id, kind);\n        const component = Qt.createComponent(url);\n'
                 '        openSplitMark("loaded", id, kind);\n')
    replace_once(plugins, "        const instance = component.createObject(parent);\n",
                 '        const instance = component.createObject(parent);\n        openSplitMark("created", id, kind);\n')
    replace_once(plugins, "            instance.shell = facadeFor(manifest, settings, row.providers);\n",
                 '            openSplitMark("attach", id, kind);\n'
                 "            instance.shell = facadeFor(manifest, settings, row.providers);\n"
                 '            openSplitMark("attached", id, kind);\n')
    replace_once(plugins, '        return { state: "built", instance: instance };\n',
                 '        openSplitMark("built", id, kind);\n        return { state: "built", instance: instance };\n')

    slot = tree / "shell/Hosts/PluginSlot.qml"
    replace_once(slot, "        loadedHostKey = hostKey;\n        built(instance);\n",
                 "        loadedHostKey = hostKey;\n        Plugins.openSplitFrame(pluginId, kind, slot);\n        built(instance);\n")

    summon = tree / "shell/Hosts/SummonHost.qml"
    replace_once(summon, "    function summon(id, payloadJson, origin) {\n",
                 "    function summon(id, payloadJson, origin) {\n"
                 f"        {mark('request', 'id', 'host.kind')}\n"
                 "        const reply = openSplitSummon(id, payloadJson, origin);\n"
                 f"        {mark('returned', 'id', 'host.kind')}\n"
                 "        return reply;\n"
                 "    }\n"
                 "    function openSplitSummon(id, payloadJson, origin) {\n")
    replace_once(summon, "            instance.open(payloadJson);\n",
                 f"            {mark('open', 'id', 'host.kind')}\n"
                 "            instance.open(payloadJson);\n"
                 f"            {mark('opened', 'id', 'host.kind')}\n")

    view = tree / "shell/Ui/layout/FirstView.qml"
    replace_once(view, "    readonly property bool firstViewRoot: true\n",
                 "    readonly property bool firstViewRoot: true\n"
                 "    // open-split instrument (scripts/smoke/open-split.py), harness copy only.\n"
                 "    readonly property string openSplitView: \"view:\" + String(Math.random()).slice(2)\n"
                 "    function openSplitMark(event, extra) {\n"
                 "        console.info(\"open-split: \" + JSON.stringify(Object.assign({ e: event, id: openSplitView, kind: \"view\", t: Date.now() }, extra || {})));\n"
                 "    }\n"
                 "    onSettledChanged: openSplitMark(settled ? \"settled\" : \"unsettled\")\n"
                 "    Component.onDestruction: openSplitMark(\"gone\")\n")
    replace_once(view, "    Component.onCompleted: {\n        completed = true;\n",
                 "    Component.onCompleted: {\n        openSplitMark(\"view\");\n        completed = true;\n")
    replace_once(view, "    function step() {\n",
                 "    function step() {\n"
                 "        const begin = Date.now();\n"
                 "        openSplitStep();\n"
                 "        openSplitMark(\"step\", { t: begin, ms: Date.now() - begin });\n"
                 "    }\n"
                 "    function openSplitStep() {\n")
    # A block's step only starts its load; the load runs on in the engine's
    # incubation after step() returns, so its stamp is the load's end.
    replace_once(view, "        property bool wanted: false\n",
                 "        property bool wanted: false\n        property real openSplitBegin: 0\n")
    replace_once(view, "            asynchronous = true;\n",
                 "            openSplitBegin = begin;\n            asynchronous = true;\n")
    replace_once(view, "            view.resume();\n",
                 "            view.openSplitMark(\"step\", { t: openSplitBegin, ms: Date.now() - openSplitBegin, block: true });\n"
                 "            view.resume();\n")

    panes = tree / "shell/Hosts/PaneHost.qml"
    replace_once(panes, "    function mount(ctx, id, container, payloadJson) {\n",
                 "    function mount(ctx, id, container, payloadJson) {\n"
                 f"        {mark('mount', 'id', PANE)}\n"
                 "        const reply = openSplitMount(ctx, id, container, payloadJson);\n"
                 f"        {mark('mounted', 'id', PANE)}\n"
                 "        return reply;\n"
                 "    }\n"
                 "    function openSplitMount(ctx, id, container, payloadJson) {\n")
    replace_once(panes, "                        instance.open(mounted.payloadJson);\n",
                 f"                        {mark('open', 'mounted.pluginId', PANE)}\n"
                 "                        instance.open(mounted.payloadJson);\n"
                 f"                        {mark('opened', 'mounted.pluginId', PANE)}\n")


def stamps(log, offset):
    """The stamp events after byte OFFSET of LOG, in log order."""
    with open(log, "rb") as source:
        source.seek(offset)
        text = source.read().decode(errors="replace")
    events = []
    for line in text.splitlines():
        found = STAMP.search(line)
        if found is None:
            continue
        try:
            event = json.loads(found.group(1))
        except json.JSONDecodeError as error:
            raise ValueError(f"open-split: unreadable stamp: {line.strip()!r}: {error}") from error
        if not (isinstance(event, dict) and isinstance(event.get("e"), str) and isinstance(event.get("id"), str)
                and isinstance(event.get("kind"), str) and isinstance(event.get("t"), int)
                and not isinstance(event.get("t"), bool)):
            raise ValueError(f"open-split: unreadable stamp: {line.strip()!r}")
        events.append(event)
    return events


def find_open(events, kind, id_):
    """The span [first, last] of the first top-level open of KIND/ID: a
    summon's request, or for a pane its mount, at depth 0. `last` is None
    while it has not returned."""
    opener = "mount" if kind == "pane" else "request"
    depth = 0
    for at, event in enumerate(events):
        if event["e"] in OPENERS:
            if depth == 0 and event["e"] == opener and event["kind"] == kind and event["id"] == id_:
                return at, close_of(events, at)
            depth += 1
        elif event["e"] in OPENERS.values():
            depth = max(depth - 1, 0)
    return None


def close_of(events, first):
    depth = 0
    for at in range(first, len(events)):
        name = events[at]["e"]
        if name in OPENERS:
            depth += 1
        elif name in OPENERS.values():
            depth -= 1
            if depth == 0:
                return at
    return None


def builds_in(events, first, last):
    """Each build between FIRST and LAST: its stamps by name, the build
    whose open() holds it, and the first frame stamps after its built."""
    end = len(events) if last is None else last + 1
    builds, opening = [], []
    for at in range(first, end):
        event = events[at]
        key = (event["kind"], event["id"])
        if event["e"] == "attempt":
            within = opening[-1]["key"] if opening else None
            builds.append({"key": key, "stamps": {"attempt": event["t"]}, "within": within})
        elif event["e"] in ("load", "loaded", "created", "attach", "attached", "built"):
            build = next((b for b in reversed(builds) if b["key"] == key and "built" not in b["stamps"]), None)
            if build is not None:
                build["stamps"].setdefault(event["e"], event["t"])
        elif event["e"] == "open":
            build = next((b for b in reversed(builds) if b["key"] == key and "built" in b["stamps"]
                          and "open" not in b["stamps"]), None)
            if build is not None:
                build["stamps"]["open"] = event["t"]
                opening.append(build)
        elif event["e"] == "opened":
            build = next((b for b in reversed(opening) if b["key"] == key), None)
            if build is not None:
                build["stamps"]["opened"] = event["t"]
                opening.remove(build)
    for build in builds:
        for event in events[end:] if last is not None else []:
            if (event["kind"], event["id"]) != build["key"]:
                continue
            if event["e"] == "start" and "start" not in build["stamps"]:
                build["stamps"]["start"] = event["t"]
            elif event["e"] == "frame" and "start" in build["stamps"] and "frame" not in build["stamps"]:
                build["stamps"]["frame"] = event["t"]
    return builds


def span(stamps, first, last):
    return stamps[last] - stamps[first] if first in stamps and last in stamps else None


def reading(events, kind, id_):
    """The split figures of the first open of KIND/ID, and what is missing."""
    found = find_open(events, kind, id_)
    if found is None:
        return None, ["open"]
    first, last = found
    missing = []
    opened = {"kind": kind, "id": id_, "request": events[first]["t"]}
    if last is None:
        missing.append("returned")
    else:
        opened["returned"] = events[last]["t"]
    builds = builds_in(events, first, last)
    rows = []
    for build in builds:
        row = {"kind": build["key"][0], "id": build["key"][1],
               "within": "-" if build["within"] is None else ":".join(build["within"])}
        for name, a, b in BUILD_SPANS:
            row[name] = span(build["stamps"], a, b)
        row["open_ms"] = span(build["stamps"], "open", "opened")
        rows.append(row)
    target = next((b for b in builds if b["key"] == (kind, id_)), None)
    if target is None:
        missing.append("build")
    else:
        top = rows[builds.index(target)]
        missing += [name for name in [s[0] for s in BUILD_SPANS] + ["open_ms"] if top[name] is None]
        for stamp in ("start", "frame"):
            if stamp not in target["stamps"]:
                missing.append(stamp)
    returned = opened.get("returned")
    stamps_of = {} if target is None else target["stamps"]
    opened["sync_ms"] = None if returned is None else returned - opened["request"]
    opened["first_content_ms"] = None if returned is None or "frame" not in stamps_of else stamps_of["frame"] - returned
    opened["frame_start_ms"] = None if returned is None or "start" not in stamps_of else stamps_of["start"] - returned
    opened.update(deferral(events, target))
    return {"open": opened, "builds": rows}, missing


def deferral(events, target):
    """settle_ms and longest_step_ms from the target build's frame to the
    last settle stamp after it."""
    figures = {"settle_ms": None, "longest_step_ms": None}
    if target is None or "frame" not in target["stamps"]:
        return figures
    frame = target["stamps"]["frame"]
    settles = [e["t"] for e in events if e["kind"] == "view" and e["e"] == "settled"]
    end = max([frame] + [t for t in settles if t >= frame])
    steps = [e.get("ms", 0) for e in events if e["kind"] == "view" and e["e"] == "step" and frame <= e["t"] <= end]
    figures["settle_ms"] = end - frame
    figures["longest_step_ms"] = max(steps, default=0)
    return figures


VIEW_STATES = ("view", "settled", "unsettled", "gone")


def settled(events):
    """Whether every FirstView logged last turned settled or was destroyed."""
    last = {}
    for event in events:
        if event["kind"] == "view" and event["e"] in VIEW_STATES:
            last[event["id"]] = event["e"]
    return all(state in ("settled", "gone") for state in last.values())


def content(events, kind, id_, after):
    """The open's frame content stamp against AFTER: ("equal" | "no-view" |
    "differs", report)."""
    if after.get("views") == 0:
        return "no-view", {}
    found = find_open(events, kind, id_)
    stamp_ = None
    if found is not None:
        stamp_ = next((e for e in events[found[0]:] if e["e"] == "content" and (e["kind"], e["id"]) == (kind, id_)), None)
    if stamp_ is None:
        return "differs", {"missing": "content"}
    first, later = stamp_.get("items", []), after.get("items", [])
    report = {"frame_target": stamp_.get("target"), "settled_target": after.get("target"),
              "frame_focus": stamp_.get("focus"), "frame_active": stamp_.get("active"), "settled_focus": after.get("focus"),
              "frame_only": sorted(set(first) - set(later)), "settled_only": sorted(set(later) - set(first)),
              "frame_items": len(first)}
    equal = (sorted(first) == sorted(later) and len(first) > 0
             and stamp_.get("target") is not None and stamp_.get("target") == after.get("target")
             and after.get("focus") is True)
    return "equal" if equal else "differs", report


# Plugins the sweep never enables, each with what keeps it off: the
# sandbox cannot meet it without the host's authentication, or the
# plugin runs only in its own fixture world.
EXCLUDED = {
    "vgs.polkit": "the host's polkit authentication agent",
    "vgs.sudo": "the host's sudo authentication",
    "vgs.lock": "the host's PAM authentication",
    "vgs.jarvis": "the Jarvis fixture world (scripts/smoke/jarvis-console.sh), where the row measures it",
}
# The one judge of kinds, PluginLogic.js, loaded as every offline reader
# loads a shell library (bin/lib/qml-library.js).
KINDS = ("const { load } = require(process.argv[1]);"
         "process.stdout.write(JSON.stringify(load(process.argv[2]).SUMMONABLE_KINDS));")


def summonable(tree):
    """TREE's PluginLogic.SUMMONABLE_KINDS, read under node."""
    tree = Path(tree)
    try:
        run = subprocess.run(["node", "-e", KINDS, str(tree / "bin/lib/qml-library.js"), str(tree / "shell/Core/PluginLogic.js")],
                             capture_output=True, text=True, check=False)
    except OSError as error:
        raise ValueError(f"open-split: sweep: refused: kinds-unread error={error.strerror}") from error
    if run.returncode != 0:
        raise ValueError(f"open-split: sweep: refused: kinds-unread node-exit={run.returncode} {run.stderr.strip()}")
    try:
        kinds = json.loads(run.stdout)
    except json.JSONDecodeError as error:
        raise ValueError(f"open-split: sweep: refused: kinds-unread {error}") from error
    if not isinstance(kinds, list) or not all(isinstance(kind, str) and kind for kind in kinds):
        raise ValueError(f"open-split: sweep: refused: kinds-unread kinds={run.stdout!r}")
    return tuple(kinds)


def sweep(listing, sources, floor, kinds):
    """The sweep's lines from a `shell listPlugins` reply, each plugin's
    source, the FLOOR members the row measures itself and the summonable
    KINDS."""
    if not kinds:
        raise ValueError("open-split: sweep: refused: kinds=empty")
    if listing.get("scanned") is not True or not listing.get("plugins"):
        raise ValueError("open-split: sweep: refused: listing=unscanned-or-empty")
    plugins = listing["plugins"]
    ids = {p["id"] for p in plugins}
    unsourced = sorted(i for i in ids if sources.get(i) not in ("bundled", "installed"))
    if unsourced:
        raise ValueError("open-split: sweep: refused: source-unread=" + ",".join(unsourced))
    lost = sorted(set(EXCLUDED) - ids)
    if lost:
        raise ValueError("open-split: sweep: refused: excluded-unlisted=" + ",".join(lost))
    lines, opened, found = [], [], set()
    for plugin in sorted(plugins, key=lambda p: p["id"]):
        id_ = plugin["id"]
        if sources[id_] != "bundled" and id_ not in EXCLUDED:
            continue
        places = [(kind, id_) for kind in plugin.get("kinds", []) if kind in kinds or kind == "pane"]
        found |= {f"{kind}/{id_}" for kind, _ in places}
        if id_ in EXCLUDED:
            lines.append(f"excluded {id_} needs={EXCLUDED[id_]}")
            continue
        if not plugin.get("enabled"):
            missing = [r["name"] for r in plugin.get("requirements", []) if r.get("state") != "present" and not r.get("optional")]
            if missing:
                lines.append(f"off {id_} needs={','.join(missing)}")
                continue
            lines.append(f"enable {id_}")
        opened += places
    unfound = sorted(set(floor) - found)
    if unfound:
        raise ValueError("open-split: sweep: refused: floor-undiscovered=" + ",".join(unfound))
    lines += [f"entry {kind} {id_}" for kind, id_ in opened if kind != "pane" and f"{kind}/{id_}" not in floor]
    lines += [f"pane {id_}" for kind, id_ in opened if kind == "pane" and f"pane/{id_}" not in floor]
    return lines


def figure(value):
    return "-" if value is None else str(value)


def main(argv):
    if len(argv) == 3 and argv[1] == "prepare":
        prepare(Path(argv[2]))
        return 0
    if len(argv) == 6 and argv[1] == "framed":
        log, offset, kind, id_ = argv[2], int(argv[3]), argv[4], argv[5]
        result, missing = reading(stamps(log, offset), kind, id_)
        print("no-open" if result is None else "no-build" if "build" in missing and "returned" not in missing
              else "framed" if "build" not in missing and "frame" not in missing else "pending")
        return 0
    if len(argv) == 10 and argv[1] == "reading":
        log, offset, kind, id_, place, open_, pressure, out = argv[2], int(argv[3]), *argv[4:10]
        result, missing = reading(stamps(log, offset), kind, id_)
        result = {"place": place, "open": open_, "cpu_some_pct": pressure, "missing": missing,
                  **(result or {"open": None, "builds": []})}
        Path(out).write_text(json.dumps(result, indent=1) + "\n")
        for row in result["builds"]:
            print(f"open-split: place={place} open={open_} part=build kind={row['kind']} id={row['id']} "
                  + " ".join(f"{name}={figure(row[name])}" for name in [s[0] for s in BUILD_SPANS] + ["open_ms"])
                  + f" within={row['within']}")
        if result["open"] is not None:
            o = result["open"]
            print(f"open-split: place={place} open={open_} part=open kind={kind} id={id_} "
                  f"sync_ms={figure(o['sync_ms'])} first_content_ms={figure(o['first_content_ms'])} "
                  f"frame_start_ms={figure(o['frame_start_ms'])} settle_ms={figure(o['settle_ms'])} "
                  f"longest_step_ms={figure(o['longest_step_ms'])} "
                  f"cpu_some_pct={pressure}")
        if missing:
            print(f"open-split: place={place} open={open_} missing={','.join(missing)}")
            return 1
        return 0
    if len(argv) == 4 and argv[1] == "settled":
        print("settled" if settled(stamps(argv[2], int(argv[3]))) else "pending")
        return 0
    if len(argv) == 7 and argv[1] == "content":
        try:
            after = json.loads(argv[6])
        except json.JSONDecodeError as error:
            raise ValueError(f"open-split: unreadable settled content: {error}") from error
        verdict, report = content(stamps(argv[2], int(argv[3])), argv[4], argv[5], after)
        print(verdict if verdict != "differs" else "differs " + json.dumps(report, sort_keys=True))
        return 0
    if len(argv) >= 4 and argv[1] == "sweep":
        try:
            listing = json.load(sys.stdin)
            sources = json.loads(argv[3])
        except json.JSONDecodeError as error:
            raise ValueError(f"open-split: sweep: unreadable listing or sources: {error}") from error
        if not isinstance(sources, dict):
            raise ValueError("open-split: sweep: refused: sources=not-an-object")
        print("\n".join(sweep(listing, sources, argv[4:], summonable(argv[2]))))
        return 0
    print("usage: open-split.py prepare TREE | framed LOG OFFSET KIND ID | settled LOG OFFSET"
          " | content LOG OFFSET KIND ID SETTLED_JSON | sweep TREE SOURCES FLOOR..."
          " | reading LOG OFFSET KIND ID PLACE OPEN CPU_SOME_PCT OUT_JSON", file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except (ValueError, OSError) as error:
        print(error, file=sys.stderr)
        sys.exit(2)
