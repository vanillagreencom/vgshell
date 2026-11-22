import QtQuick
import QtQuick.Window
import Quickshell
import qs.Ui
import "FirstViewLogic.js" as Logic

// A surface's content that builds only its first view before the first
// frame and the rest in frame-sized steps after it. It is a Column; its
// parts stand anywhere inside it, in document order:
//
//   FirstView.Block, a Loader of one block, the block declared inside it;
//   `target` true builds it into the first view.
//   FirstView.Rows, a Repeater whose `values` it shows a growing slice of,
//   kept by `objectProp` as a ScriptModel keeps them; `target`, a row
//   index, builds the rows through it into the first view. A change of
//   `values` keeps every row built: the slice runs through the last value
//   whose key, or with no `objectProp` the value itself, was built, so a
//   value inserted before it builds with it.
//
// Both parts carry `view` and `showsWhole` and answer the same questions
// (`buildAlone`, `remaining`, `loading`, `progressed`, `targetUnbuilt`,
// `targetItem`, `lastBuilt`, `grow`, `complete`, `buildThrough`,
// `stepOnce`, `itemOf`), so the view and FirstViewLogic.js read a part
// through them and an Item's `visible` and `parent` alone.
//
// A part belongs to the nearest FirstView it stands in, or to the `view`
// its page names for a part outside the view's tree, such as a menu's
// entries, which sorts after the view's own parts.
//
// The first view: no item has a position before layout, so the view builds
// its shown parts in order, one block or one row at a time, positions what
// it built at once through each positioner's forceLayout(), deepest first
// (https://doc.qt.io/qt-6/qml-qtquick-column.html#forceLayout-method), and
// stops once its height reaches `cap`, the room the surface's host gives
// it: its window's height unless the page names it. A room not yet known,
// before the item has a sized window, builds no part past the targets
// until it is known. A target builds with every part before it and one
// `cap` of room after it. A shown part before one already built is always built, so
// nothing above the viewport changes height later and the scroll position
// holds; content that fits under `cap` builds whole and defers nothing.
// The first view builds when the view completes, again for values or a
// room that arrive before its first frame, as a surface's data does when
// the core assigns `shell`, and when a hidden view or part shows. A hidden
// part, such as a hidden tab's page or a menu's undrawn entries, is left
// to the steps; a hidden block that shows builds at once.
//
// The rest: once a frame started after the first view has swapped
// (FrameLatch), each such frame takes one step: the next block loads
// asynchronously, and the next rows build until the step reaches a third of
// a frame (`stepBudget`). Quickshell installs its incubation controller on
// the engine and, while it tracks a window, incubates a block's load for a
// third of the primary screen's frame on each timeToIncubate, which the
// threaded render loop emits as it advances a running animation on a shown
// window (Qt 6.12 QSGThreadedRenderLoop::interleaveIncubation), and
// otherwise for two thirds of a frame on each event-loop turn
// (src/core/incubator.cpp QsIncubationController::incubate and
// src/core/generation.cpp EngineGeneration::updateIncubationMode, at
// 2b4501a, the pinned engine). A slice pauses only once the block's
// objects are all created, and then between their bindings and between
// their completion handlers (Qt 6.12 qqmlobjectcreator.cpp
// QQmlObjectCreator::create and finalize), so creating the objects is
// never split.
// A step runs only while the view is shown: an ancestor's `visible` false
// reads false here (https://doc.qt.io/qt-6/qml-qtquick-item.html#visible-prop),
// so an instance the core hides before draining its lifetime starts no
// step. A hide never aborts a block whose load is in flight: a Loader
// turned inactive mid-load keeps the load's partial tree as its child
// until a later turn (Qt 6.12, offscreen), where a window torn down in
// the same turn walks it. A view still in its window finishes the load at
// the hide, since a load left running past the drain could resume from the
// engine's queued incubation call (Quickshell
// QsIncubationController::incubateLater, src/core/incubator.cpp, 2b4501a)
// and register on the drained lifetime. A view whose window has gone is
// being destroyed with it, and its Loaders take their loads with them, so
// it builds nothing then: a FloatingWindow makes its proxy window, which
// owns the content item, as its first child (Quickshell
// FloatingWindowInterface's constructor, src/window/floatingwindow.cpp,
// 2b4501a), so the content item lets the instance go before the host's
// PluginSlot, a later child, destroys and hides it.
//
// `ensure(part, index)` builds a part now, with every shown part before
// it, and answers its item: a block's, or a Rows part's row `index`, for a
// lookup, a focus move or a deep link; with no index it builds every row
// of a Rows part and answers null. `ensureAll()` builds every shown part
// and leaves a hidden one to the steps. A block before the
// part whose load is in flight finishes too, since its height lands above
// the part. What either builds is positioned as the first view is, and
// every positioner above the view is laid out again, so a reveal or a
// geometry read in the same turn sees it laid out, a scroll area's content
// height around the view included: a Column sets its implicit height as it
// lays out, which it otherwise does in the next polish
// (https://doc.qt.io/qt-6/qml-qtquick-column.html#forceLayout-method).
// Setting an incubating Loader's `asynchronous` to false completes it in
// the same turn (https://doc.qt.io/qt-6/qml-qtquick-loader.html#asynchronous-prop).
// `settled` is true while every part is built and nothing loads.
Column {
    id: root

    // The room the surface's host gives it: the height the first view
    // fills. Infinity while unknown.
    property real cap: Window.window !== null && Window.window.height > 0 ? Window.window.height : Infinity
    property bool settled: false
    readonly property bool firstViewRoot: true

    property var parts: []
    property bool ordered: true
    property bool completed: false
    // True from completion, or a show, until the first frame after it swaps.
    property bool first: true
    property bool filling: false
    // A rows step's share, in ms: a third of a 60 Hz frame, the share
    // Quickshell's incubation controller takes of each animation tick for
    // a block's load, which leaves the rest of the frame to drawing. QML
    // reads no screen refresh rate (the attached Screen carries none:
    // https://doc.qt.io/qt-6/qml-qtquick-screen.html).
    readonly property int stepBudget: Math.trunc(1000 / 60 / 3)

    readonly property FrameLatch latch: FrameLatch {
        window: root.Window.window
        onFired: Qt.callLater(root.step)
    }

    Component.onCompleted: {
        completed = true;
        fill();
        latch.arm();
    }

    onCapChanged: changed()

    onVisibleChanged: {
        if (!completed) return;
        if (!visible) {
            latch.disarm();
            if (Window.window !== null)
                for (const part of parts.slice())
                    if (part.loading()) part.complete();
            return;
        }
        first = true;
        fill();
        latch.arm();
    }

    component Block: Loader {
        id: block

        default property Component content: null
        property bool target: false
        property Item view: null
        property bool wanted: false
        // A block that shows builds at once, as a tab's page does when its
        // tab is chosen.
        readonly property bool showsWhole: true

        active: wanted
        asynchronous: false
        sourceComponent: content
        width: parent ? parent.width : 0

        Component.onCompleted: Logic.join(block, "a block")
        Component.onDestruction: if (view !== null) view.unregister(block)
        // A load a step starts ends Ready or Error
        // (https://doc.qt.io/qt-6/qml-qtquick-loader.html#status-prop);
        // either lets the steps go on to the parts after it.
        onStatusChanged: {
            if (view === null || !asynchronous || status === Loader.Loading || status === Loader.Null) return;
            if (status === Loader.Error) console.error("first-view: a block failed to load: " + content.url);
            view.resume();
        }
        onVisibleChanged: if (visible && view !== null) view.shown(block)
        onTargetChanged: if (view !== null) view.changed()

        function buildAlone() { wanted = true; }
        function remaining() { return !wanted && content !== null; }
        function loading() { return status === Loader.Loading; }
        function progressed() { return wanted; }
        function targetUnbuilt() { return target && !wanted; }
        function targetItem() { return target ? item : null; }
        function lastBuilt() { return block; }
        function grow() { complete(); }
        function complete() {
            asynchronous = false;
            wanted = true;
            view.position(item, block);
        }
        function buildThrough(count) { complete(); }
        // Start the block's load; true while it is in flight, which ends
        // the step.
        function stepOnce(begin, budget) {
            asynchronous = true;
            wanted = true;
            return status === Loader.Loading;
        }
        function itemOf(index) { return item; }
    }

    component Rows: Repeater {
        id: rows

        property var values: []
        property string objectProp: ""
        property int target: -1
        property Item view: null
        // The rows built: `values` up to this count.
        property int limit: 0
        readonly property bool showsWhole: false
        // True for rows outside a FirstView, which build every value.
        property bool alone: false
        // The values the model holds: the first `limit`, assigned after
        // `limit` changes, so no model update slices by a stale count.
        property var shown: []

        model: ScriptModel {
            values: rows.shown
            objectProp: rows.objectProp
        }

        Component.onCompleted: Logic.join(rows, "rows")
        Component.onDestruction: if (view !== null) view.unregister(rows)
        onValuesChanged: {
            if (alone) shown = values;
            else if (limit > 0) build(kept());
            if (view !== null) view.changed();
        }
        onTargetChanged: if (view !== null) view.changed()
        onVisibleChanged: if (visible && view !== null) view.shown(rows)

        function build(count) {
            limit = count;
            shown = limit >= values.length ? values : values.slice(0, limit);
        }
        // How many values the model keeps after `values` changed: through
        // the last value whose key was built, and no fewer than before, so
        // no built row leaves the model. With no `objectProp` the key is
        // the value, matched by strict equality, which for the strings and
        // numbers an unkeyed Rows holds is the ScriptModel's default
        // Structure comparison
        // (https://quickshell.org/docs/v0.3.1/types/Quickshell/ObjectComparison/).
        function kept() {
            const key = value => objectProp === "" ? value : value[objectProp];
            const built = shown.map(key);
            let count = Math.min(limit, values.length);
            for (let i = count; i < values.length; i++)
                if (built.indexOf(key(values[i])) !== -1) count = i + 1;
            return count;
        }

        function buildAlone() {
            alone = true;
            limit = Number.MAX_SAFE_INTEGER;
            shown = values;
        }
        function remaining() { return limit < values.length; }
        function loading() { return false; }
        function progressed() { return limit > 0; }
        function targetUnbuilt() { return target >= 0 && target < values.length && limit <= target; }
        function targetItem() { return target >= 0 && target < limit ? itemAt(target) : null; }
        // The row built last: Qt stacks a Repeater's rows before the
        // Repeater, so it stands where the next row goes.
        function lastBuilt() { return count === 0 ? null : itemAt(count - 1); }
        function grow() { buildThrough(limit + 1); }
        function complete() { buildThrough(values.length); }
        function buildThrough(count) {
            const from = limit;
            if (count <= from) return;
            build(count);
            for (let i = from; i < rows.count; i++) view.position(itemAt(i), rows);
        }
        function stepOnce(begin, budget) {
            while (remaining() && Date.now() - begin < budget) build(limit + 1);
            return false;
        }
        function itemOf(index) { return index === undefined ? null : itemAt(index); }
    }

    function register(part) {
        parts.push(part);
        ordered = false;
        changed();
    }

    function unregister(part) {
        const at = parts.indexOf(part);
        if (at !== -1) parts.splice(at, 1);
    }

    // The parts in document order. A path is each ancestor's index among
    // its parent's children, from this view down; a Loader holds its item.
    // Qt stacks a Repeater's rows before the Repeater in its parent's
    // children, so a Rows part stands where its next row goes, after its
    // built rows and the parts in them, and a built group's rows fill
    // before the next group (tst_first_view.qml, Qt 6 offscreen). A part
    // moved out of this view's tree, as a menu's entries move into its
    // window, sorts last.
    function pathOf(item) {
        const path = [];
        for (let at = item; at !== root; at = at.parent) {
            if (at === null || at.parent === null) return null;
            path.unshift(at.parent.children.indexOf(at));
        }
        return path;
    }
    // Where a part's last built content starts, or null.
    function builtAt(part) {
        if (!part.progressed()) return null;
        return pathOf(part.lastBuilt());
    }
    function compare(a, b) {
        if (a === null || b === null) return (a === null) - (b === null);
        for (let i = 0; i < Math.min(a.length, b.length); i++)
            if (a[i] !== b[i]) return a[i] - b[i];
        return a.length - b.length;
    }
    function order() {
        if (ordered) return parts;
        const keyed = parts.map(part => ({ part: part, path: pathOf(part) }));
        keyed.sort((a, b) => compare(a.path, b.path));
        parts = keyed.map(entry => entry.part);
        ordered = true;
        return parts;
    }

    // Unbuilt, or a block still loading: a part whose height can change.
    function pending(part) {
        return part.remaining() || part.loading();
    }
    // The bottom of the built target in this view, or 0 while none is built.
    function targetBottom() {
        let bottom = 0;
        for (const part of parts) {
            if (!part.visible) continue;
            const item = part.targetItem();
            if (item !== null) bottom = Math.max(bottom, item.mapToItem(root, 0, item.height).y);
        }
        return bottom;
    }

    function positioner(item) {
        return item instanceof Column || item instanceof Row || item instanceof Flow || item instanceof Grid;
    }
    // Position ITEM's tree now, deepest first, then every positioner from
    // PART up to this view, so the view's height counts what was built.
    function position(item, part) {
        const settle = node => {
            for (const child of node.children) settle(child);
            if (positioner(node)) node.forceLayout();
        };
        if (item !== null) settle(item);
        for (let at = part.parent; at !== null; at = at.parent) {
            if (positioner(at)) at.forceLayout();
            if (at === root) break;
        }
    }

    // Build the first view: the next shown part grows while a part after it
    // was built, while a target is unbuilt, or while the view is shorter
    // than its cap, then one cap past a built target.
    function fill() {
        if (filling || !completed || !visible) return;
        filling = true;
        try {
            for (;;) {
                const list = order();
                let target = -1;
                let next = -1;
                for (let i = 0; i < list.length; i++) {
                    if (list[i].visible && list[i].targetUnbuilt()) target = i;
                    if (next === -1 && list[i].visible && list[i].remaining()) next = i;
                }
                if (next === -1) break;
                const at = pathOf(list[next]);
                const above = list.some(part => {
                    const built = builtAt(part);
                    return part !== list[next] && built !== null && compare(built, at) > 0;
                });
                if (!(above || next <= target || (isFinite(cap) && height < Math.max(cap, targetBottom() + cap)))) break;
                list[next].grow();
            }
        } finally {
            filling = false;
        }
        settled = !working();
    }

    function working() {
        return parts.some(pending);
    }

    function loading() {
        return parts.some(part => part.loading());
    }

    // Read whether anything is left, and wait for the next frame for it
    // unless a load in flight takes the next step when it ends.
    function resume() {
        settled = !working();
        if (!settled && visible && !first && !latch.armed && !loading()) latch.arm();
    }

    // A part's values, target or registration changed.
    function changed() {
        if (!completed || filling) return;
        if (first && visible) fill();
        else resume();
    }

    // A hidden part shows: a block builds at once; rows join the first
    // view before the first frame and take the next steps after it.
    function shown(part) {
        if (!completed) return;
        if (part.showsWhole && pending(part)) ensure(part);
        else if (first) fill();
        else resume();
    }

    function step() {
        first = false;
        if (!visible) return;
        const list = order().slice();
        if (loading()) return;
        const budget = root.stepBudget;
        const begin = Date.now();
        for (const part of list) {
            if (!part.remaining()) continue;
            if (part.stepOnce(begin, budget)) break;
            if (Date.now() - begin >= budget) break;
        }
        resume();
    }

    // Complete every shown part before STOP, or every shown part when STOP
    // is null, in order. A part built here can register parts of its own;
    // each pass reads the order again. Each part is completed once.
    function completeBefore(stop) {
        const done = [];
        for (let built = true; built; ) {
            built = false;
            for (const before of order().slice()) {
                if (before === stop) break;
                if (!before.visible || !pending(before) || done.indexOf(before) !== -1) continue;
                done.push(before);
                before.complete();
                built = true;
                break;
            }
        }
    }

    function ensure(part, index) {
        completeBefore(part);
        if (index === undefined) part.complete();
        else part.buildThrough(index + 1);
        positionAbove();
        const item = part.itemOf(index);
        resume();
        return item;
    }

    function ensureAll() {
        completeBefore(null);
        positionAbove();
        resume();
    }

    // Lay out every positioner above this view, nearest first.
    function positionAbove() {
        for (let at = root.parent; at !== null; at = at.parent)
            if (positioner(at)) at.forceLayout();
    }
}
