import QtQuick
import "TouchpadScrollLogic.js" as Logic

// The one touchpad scroll of every view: a Flickable, a ListView or a
// GridView declares it and hands itself as `view`. A two-finger swipe then
// moves the view as far as it moves a GTK list, and the view coasts once
// the fingers lift. Qt Wayland turns a finger-source wl_pointer.axis into
// a wheel event in the ScrollUpdate phase whose pixelDelta is the axis
// length, and Qt's own Flickable moves one pixel per pixel of it and never
// coasts (QQuickFlickable::wheelEvent, qtdeclarative 6.11), which crawls
// under a compositor that scales touchpad deltas down for the toolkits that
// multiply them, as Hyprland's input.touchpad.scroll_factor does; a window
// rule's scroll_touchpad reaches no layer surface. ScrollArea declares it;
// a view a control or a plugin declares itself declares it too.
//
// It makes itself an item of the view's content, which a list view's
// declaration alone does not, covers the part in view under every other
// item of the content, and takes no button and no hover: Qt hands a wheel
// event to the items under the pointer in reverse paint order, and an item
// stands among its children at z 0, so a child of the content at negative z
// reads it after the content's other items and before the view
// (QQuickDeliveryAgentPrivate::eventTargets, qtdeclarative 6.11). A
// MouseArea, unlike a blocking WheelHandler, can leave one event to the
// view by not accepting it. It takes a swipe's deltas, which come in the update phase, and leaves every other
// wheel event to the view: a mouse wheel's, whose step stays Qt's, and a
// swipe's begin and end, which press and release the view. It takes a
// delta only while the view is interactive and has content past its size
// on the axis the delta runs along, so a view that fits, and a view a
// swipe runs across, leave the swipe to the view under them.
MouseArea {
    id: root

    required property Flickable view
    // The fraction of a pixel the last delta left on each axis.
    property point carry: Qt.point(0, 0)
    // The deltas of the last moments, which a coast is read from.
    property var history: []

    parent: view.contentItem
    x: view.contentX
    y: view.contentY
    width: view.width
    height: view.height
    z: -1
    enabled: view.interactive
    acceptedButtons: Qt.NoButton

    // Whether the view scrolls on the axis a delta of (dx, dy) runs along,
    // the axis of its larger part: its content and margins are past its
    // size there. A view at its bounds still does.
    function scrolls(dx, dy) {
        return Math.abs(dx) > Math.abs(dy) ? view.contentWidth + view.leftMargin + view.rightMargin > view.width : view.contentHeight + view.topMargin + view.bottomMargin > view.height;
    }

    // The content moved by a delta of (dx, dy) read at `at`, a time in ms,
    // each axis held inside the view's bounds. Answers whether the view
    // took the delta: one along an axis it does not scroll on moves nothing
    // and is left to the view under it.
    function move(dx, dy, at) {
        if (!scrolls(dx, dy)) return false;
        const x = Logic.step(dx, carry.x), y = Logic.step(dy, carry.y);
        carry = Qt.point(x.carry, y.carry);
        history = Logic.remember(history, at, dx, dy);
        const left = view.originX - view.leftMargin, top = view.originY - view.topMargin;
        view.contentX = Logic.clamp(view.contentX + x.move, left, view.originX + view.contentWidth + view.rightMargin - view.width);
        view.contentY = Logic.clamp(view.contentY + y.move, top, view.originY + view.contentHeight + view.bottomMargin - view.height);
        return true;
    }

    // The fingers lifted at `at`: the view flicks the distance the swipe
    // coasts. A flick's positive velocity moves the content toward its
    // start, so each velocity is negated.
    function lift(at) {
        const coast = Logic.coast(history, at);
        carry = Qt.point(0, 0);
        history = [];
        if (coast.x === 0 && coast.y === 0) return;
        view.flick(-Logic.flickVelocity(coast.x, view.flickDeceleration), -Logic.flickVelocity(coast.y, view.flickDeceleration));
    }

    onWheel: wheel => {
        if (wheel.phase === Qt.ScrollUpdate) {
            wheel.accepted = root.move(-wheel.pixelDelta.x, -wheel.pixelDelta.y, Date.now());
            return;
        }
        wheel.accepted = false;
        // The view reads the end after this handler and stops there, so
        // the coast starts once it has.
        if (wheel.phase === Qt.ScrollEnd) {
            const at = Date.now();
            Qt.callLater(() => root.lift(at));
        }
    }
}
