import QtQuick
import qs.Commons
import qs.Ui
import "ListCursorLogic.js" as Logic

// The one cursor of a list: a plate under the row the pointer is over,
// else the row that holds the list's selection. It travels to the next row
// and takes its height rather than lighting each row, fades in while
// `shown` and out while not, and lands at once after `snap()` and while
// hidden, so it appears where it lands. `shown` holds while a row holds
// the cursor; a list that knows whether it has a selection, and rebuilds
// its rows under it, binds it instead, so a row it destroys leaves the
// plate in place for the next.
//
// The list owns its selection, which the keyboard moves. A row hands the
// cursor itself through `follow(row, holds)` while it holds the
// selection. A hover takes the plate, `hovered`, only once `hoverTakes`
// answers true: after `disarm()`, which a keyboard step and a rebuilt list
// call, the pointer must move before it takes the plate again, so a
// pointer resting over a list that moves under it never takes it from the
// keyboard. A pick list, whose Enter acts on the row under the pointer,
// also moves its selection on the row's `pointed`; a navigation list
// leaves its selection on the page it shows. When the pointer leaves the
// cursor's parent the plate goes back to the selection: the cursor emits
// `pointerLeft()`, and unless the list then changed its selection, hands
// it back to the row that held it before the hover took it, through that
// row's `pointed`. A disarm ends the hover with the selection where the
// keyboard put it.
//
// Declare the cursor in the item that holds the rows, or in any item above
// them that is not a positioner, such as a view's contentItem. It follows
// the row through every item between, by their positions, so it ignores a
// row's transform, such as its entrance. It draws at z -1, under every
// sibling, the rows among them, and so under anything its parent draws
// itself: its parent must draw nothing, and a parent that paints a fill is
// refused with an error. `enterSlot()` places a row that arrives among the
// others of its turn, for ListEntrance.
//
// Every timing and distance is `motion`, `Theme.motion.list` by default. A
// plugin that owns its look hands its own, in the same shape, and its own
// `background`.
Item {
    id: root

    property var motion: Theme.motion.list
    // The default plate's fill and corner; a replaced `background` draws
    // its own.
    property color color: Theme.listItem.selected
    // The plate's fill while the row it holds is pressed.
    property color pressedColor: Theme.listItem.selectedPressed
    property real radius: Theme.listItem.radius
    // Whether the row that holds the cursor is pressed: its template's
    // `down`, which a release outside the row clears.
    readonly property bool pressed: placed !== null && placed.down === true
    // What the plate draws. The cursor parents it and fills itself with it.
    property Item background: Rectangle { color: root.pressed ? root.pressedColor : root.color; radius: root.radius }
    // The row that holds the selection; null for none.
    readonly property alias target: state.target
    // The row under the pointer that took the plate; null for none.
    readonly property alias hovered: state.hovered
    // The row the plate sits on.
    readonly property Item placed: state.hovered !== null ? state.hovered : state.target
    // Whether a hover moves the selection: the pointer has moved since the
    // last `disarm()`.
    readonly property alias armed: state.armed
    property bool shown: state.hovered !== null || state.target !== null
    // A press on the row under the pointer chooses it: leaving the list
    // afterwards hands nothing back.
    onPressedChanged: if (pressed) state.restore = null

    // The pointer left the cursor's parent after a hover took the plate. A
    // list that clears its selection then, as a menu with no keyboard
    // choice does, sets it here, before the cursor hands it back.
    signal pointerLeft()

    z: -1
    opacity: shown ? 1 : 0
    // A plate faded out takes no room, so a scroll area that measures its
    // children skips it.
    visible: opacity > 0
    Behavior on opacity {
        enabled: root.motion.fade.duration > 0
        ListAnimation { step: root.motion.fade }
    }

    // `holds` true hands the cursor `row`; false lets it go, unless another
    // row took it first. A row that lets go before the next row takes it
    // leaves the cursor travelling between them, since the plate is still
    // shown when the next row takes it. A row outside the cursor's parent is
    // refused with an error, and the cursor stays where it was.
    function follow(row, holds) {
        if (holds) {
            if (chainOf(row) === null) {
                console.error("ListCursor: row " + row + " is not inside the cursor's parent " + root.parent);
                return;
            }
            state.target = row;
        } else if (state.target === row) state.target = null;
    }

    // The next placement, this turn, lands at once.
    function snap() {
        state.snapping = true;
        Qt.callLater(state.settle);
    }

    // Whether a hover at `point`, in scene coordinates, moves the selection.
    function hoverTakes(point) {
        if (state.armed) return true;
        const moved = Logic.pointerMoved(state.last, point);
        state.last = Qt.point(point.x, point.y);
        if (moved) state.armed = true;
        return moved;
    }

    function disarm() {
        state.armed = false;
        state.last = null;
        if (state.hovering) state.endHover();
    }

    // The next hover moves the selection without the pointer moving first,
    // as after a click that rebuilt the list under the pointer.
    function arm() { state.armed = true; }

    // The place, 0 first, of a row that arrives among the others that
    // arrive in the same turn.
    function enterSlot() {
        if (state.arrivals === 0) Qt.callLater(state.endArrivals);
        return state.arrivals++;
    }

    QtObject {
        id: state

        property Item target: null
        // The ListCursorRow of `target`, when a row of qs.Ui holds it.
        property QtObject holder: null
        property Item hovered: null
        // Whether a hover holds the plate since the pointer entered, and
        // the ListCursorRow that held the selection when it took it.
        property bool hovering: false
        property QtObject restore: null
        property bool snapping: false
        property bool armed: false
        // The last scene point a hover read since the cursor was disarmed.
        property var last: null
        property int arrivals: 0

        function settle() { snapping = false; }
        function endHover() {
            hovering = false;
            hovered = null;
            restore = null;
        }
        function endArrivals() { arrivals = 0; }
    }

    // `row` and every item between it and the cursor's parent, whose
    // positions sum to the row's place; empty while the row or the cursor
    // has no parent yet, as while a view creates it, and null for a row
    // outside the cursor's parent.
    function chainOf(row) {
        if (row.parent === null || root.parent === null) return [];
        const out = [];
        for (let at = row; at !== root.parent; at = at.parent) {
            if (at === null) return null;
            out.push(at);
        }
        return out;
    }
    // The ListCursorRow side of `follow`: `row` is the handler, whose
    // parent is the row, so the cursor can hand the row the selection back
    // through the handler's `pointed`.
    function followRow(row, holds) {
        follow(row.parent, holds);
        if (holds && state.target === row.parent) state.holder = row;
        else if (!holds && state.holder === row) state.holder = null;
    }

    // A hover that `hoverTakes` let through puts the plate on `row`; the
    // first of a hover keeps the ListCursorRow of the row that held the
    // selection. A list whose rows are not rows of qs.Ui, such as the
    // launcher's, calls it from its own pointer path and keeps what it
    // hands back itself, on `pointerLeft()`.
    function hover(row) {
        if (!state.hovering) {
            state.hovering = true;
            state.restore = state.target !== null && state.holder !== null && state.holder.parent === state.target ? state.holder : null;
        }
        if (chainOf(row) !== null) state.hovered = row;
    }

    function pointerLeave() {
        if (!state.hovering) return;
        const over = state.hovered;
        const back = state.restore;
        state.endHover();
        root.pointerLeft();
        if (back !== null && over !== null && state.target === over && back.parent !== over) back.pointed();
    }

    // Whether the pointer is over the cursor's parent, read by a
    // HoverHandler made on it: one declared here would sit on the plate.
    Component {
        id: parentHover
        HoverHandler {}
    }
    property HoverHandler parentHovered: null
    Connections {
        target: root.parentHovered
        function onHoveredChanged() { if (!root.parentHovered.hovered) root.pointerLeave(); }
    }
    function watchParent() {
        if (parentHovered !== null) parentHovered.destroy();
        parentHovered = parent === null ? null : parentHover.createObject(parent);
    }

    readonly property var chain: placed === null ? [] : chainOf(placed) ?? []
    onChainChanged: place()

    Instantiator {
        model: root.chain
        delegate: Connections {
            required property Item modelData
            target: modelData
            // A surface destroys the cursor, and this delegate, before
            // the rows it follows, and a row can still move after they went.
            function onXChanged() { if (root !== null) root.place(); }
            function onYChanged() { if (root !== null) root.place(); }
            function onWidthChanged() { if (root !== null) root.place(); }
            function onHeightChanged() { if (root !== null) root.place(); }
        }
    }

    function place() {
        const chain = root.chain;
        if (chain.length === 0) return;
        let x = 0, y = 0;
        for (const at of chain) {
            x += at.x;
            y += at.y;
        }
        root.x = x;
        root.width = chain[0].width;
        move(travel, "y", y, root.motion.travel.duration);
        move(resize, "height", chain[0].height, root.motion.resize.duration);
    }

    // Glide `property` to `value` over `animation`, or land at once while
    // snapping, hidden or stilled. Hidden reads the opacity, not `shown`:
    // a row that lets go before the next takes the cursor leaves `shown`
    // false for that turn, and whether its binding has caught up when the
    // next row takes the cursor depends on the order Qt notifies them in.
    function move(animation, property, value, duration) {
        const glide = !state.snapping && root.opacity > 0 && duration > 0;
        if (glide && animation.running && animation.to === value) return;
        animation.stop();
        if (glide && root[property] !== value) {
            animation.to = value;
            animation.start();
        } else root[property] = value;
    }

    ListAnimation { id: travel; target: root; property: "y"; step: root.motion.travel }
    ListAnimation { id: resize; target: root; property: "height"; step: root.motion.resize }

    function adopt() {
        if (background === null) return;
        background.parent = root;
        background.anchors.fill = root;
    }
    onBackgroundChanged: adopt()

    // Qt draws a child at a negative z under its parent's own paint, so a
    // parent's fill, such as a surface's, would hide the plate.
    function checkParent() {
        if (parent !== null && parent.color !== undefined && parent.color.a > 0)
            console.error("ListCursor: parent " + parent + " paints a fill over the plate; declare the cursor in an item that draws nothing, around the rows");
    }
    onParentChanged: {
        checkParent();
        watchParent();
    }
    Component.onCompleted: {
        adopt();
        if (parentHovered === null) watchParent();
    }
    Component.onDestruction: if (parentHovered !== null) parentHovered.destroy()
}
