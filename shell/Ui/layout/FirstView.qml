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
// `targetItem`, `lastBuilt`, `grow`, `complete`, `buildThrough`, `drop`,
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
// until it is known. A target, the row or block a page reveals with a
// reveal that moves the least (ScrollArea `reveal`), builds with every
// part before it. A target that ends inside the first window, `cap` from
// the top, adds no room: that window holds it, so the reveal shows it
// with the rows the first window builds. A target past the first window
// builds one `cap` of room after it: where the reveal leaves it depends on
// the viewport the reveal measures, and a window that maps after the
// page's open draws a viewport up to `cap` tall below a reveal measured
// against a shorter one. A target inside another, as a group holds its
// linked row, counts no room of its own; the inner one names the row the
// reveal shows. A shown part before one already built is always built, so
// nothing above the viewport changes height later and the scroll position
// holds; content that fits under `cap` builds whole and defers nothing.
// The first view builds when the view completes, again for values or a
// room that arrive before its first frame, as a surface's data does when
// the core assigns `shell`, and when a hidden view or part shows. A hidden
// part, such as a hidden tab's page or a menu's undrawn entries, is left
// to the steps; a hidden block that shows builds at once. A part that
// shows with the view is the view's show, and its first view builds the
// part: Qt sets an item's visibility through its tree and emits
// visibleChanged for its children before the item itself (qtdeclarative
// v6.12.1 QQuickItemPrivate::setEffectiveVisibleRecur), so such a show
// arrives before the view's own handler has run.
//
// `drop()` and `refill()` replace a view's content, as a page that draws
// one record at a time takes another: drop unbuilds every part in the
// view's tree and holds every build, a show's included, so no build reads
// a part whose values still hold the old content; refill, once every value
// follows the new content, ends the hold and builds the first view as a
// show does, or leaves it to the next show while the view is hidden. A
// part outside the view's tree, such as a menu's entries, keeps what it
// built: it does not draw the record, and a menu entry that switches the
// record must outlive its own trigger.
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
//
// A Rows part's build writes its Repeater's model, and a part nested in
// its rows changes or registers inside that write. A first view built
// there would write the outer model again within its own write, which Qt
// reports as a binding loop on the ScriptModel's `values` and leaves at its
// stale value, so a change that arrives during a build waits for the
// outermost build to end and runs once then (`hold`).
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
    // The view's visibility as its own handler last read it.
    property bool viewShown: false
    // True from drop() until refill() or a show.
    property bool replacing: false
    property bool filling: false
    // Rows builds in progress, and whether a change arrived during one.
    property int holding: 0
    property bool heldChange: false
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
        viewShown = visible;
        fill();
        latch.arm();
    }

    onCapChanged: changed()

    onVisibleChanged: {
        if (!completed) return;
        viewShown = visible;
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
        // Unload; a load in flight finishes first, as at a hide.
        function drop() {
            if (loading()) complete();
            asynchronous = false;
            wanted = false;
        }
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
            const next = limit >= values.length ? values : values.slice(0, limit);
            view.hold(() => { shown = next; });
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
        function drop() { if (limit > 0) build(0); }
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
    // Whether OUTER holds INNER in its tree.
    function encloses(outer, inner) {
        for (let at = inner.parent; at !== null; at = at.parent)
            if (at === outer) return true;
        return false;
    }
    // The bottom of the built target in this view, or 0 while none is
    // built; a target that holds another built target counts the inner one.
    function targetBottom() {
        const items = [];
        for (const part of parts) {
            if (!part.visible) continue;
            const item = part.targetItem();
            if (item !== null) items.push(item);
        }
        let bottom = 0;
        for (const item of items)
            if (!items.some(other => other !== item && encloses(item, other)))
                bottom = Math.max(bottom, item.mapToItem(root, 0, item.height).y);
        return bottom;
    }
    // The height the first view fills: `cap`, or one `cap` past a target
    // that ends past it.
    function room() {
        const bottom = targetBottom();
        return bottom > cap ? bottom + cap : cap;
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
    // than its room.
    function fill() {
        if (filling || replacing || !completed || !visible) return;
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
                if (!(above || next <= target || (isFinite(cap) && height < room()))) break;
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
        if (!settled && visible && !first && !replacing && !latch.armed && !loading()) latch.arm();
    }

    // Run WORK, a Rows build, and a change that arrives during it once the
    // outermost build has ended.
    function hold(work) {
        holding++;
        try {
            work();
        } finally {
            holding--;
        }
        if (holding > 0 || !heldChange) return;
        heldChange = false;
        changed();
    }

    // A part's values, target or registration changed.
    function changed() {
        if (!completed || filling || replacing) return;
        if (holding > 0) {
            heldChange = true;
            return;
        }
        if (first && visible) fill();
        else resume();
    }

    // A hidden part shows: a block builds at once; rows join the first
    // view before the first frame and take the next steps after it. A
    // part that shows with the view waits for the view's own show.
    function shown(part) {
        if (!completed || !viewShown || replacing) return;
        if (part.showsWhole && pending(part)) ensure(part);
        else if (first) fill();
        else resume();
    }

    function step() {
        first = false;
        if (!visible || replacing) return;
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

    function drop() {
        replacing = true;
        latch.disarm();
        // Last first, so a part a row of another holds drops before that
        // row goes, while it can still run.
        for (const part of order().slice().reverse())
            if (parts.indexOf(part) !== -1 && pathOf(part) !== null) part.drop();
        // A Column lays out a removed child only at its next polish
        // (qtdeclarative v6.12.1 QQuickBasePositioner::itemChange), so the
        // first view after the hold would read the old content's height.
        root.forceLayout();
        positionAbove();
        settled = false;
    }

    function refill() {
        if (!replacing) return;
        replacing = false;
        if (!visible) return;
        first = true;
        fill();
        latch.arm();
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
