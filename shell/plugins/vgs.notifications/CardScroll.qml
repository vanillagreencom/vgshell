import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Shared scroll frame for notification cards. The stack and the panel use
// the same text column, overflow rule and slim bar. The cards sit in a
// one-column grid, in child order unless a card names its `Layout.row`:
// Qt 6.11's GridLayout puts a child with a row at that row as given and
// fills the rest in order (QQuickGridLayout::insertLayoutItems), and it
// lays them out at polish, once a Repeater has renumbered every card.
Item {
    id: root

    required property var look
    property real maxHeight: 0
    // Whether the view holds its place from the content's end rather than
    // its start: a bottom stack, whose newest card is the last. As the
    // content or the view changes size the view keeps its distance from
    // the end, `endGap`, as a top stack keeps its distance from the start,
    // so a newest card in view stays in view. While the user scrolls the
    // view is left to move and the hold catches up when the move ends:
    // Qt 6.11's setContentY resets the view's timeline and ends its
    // movement (QQuickFlickable::setContentY), which would stop a wheel
    // step or a flick each frame a card grows or shrinks. A change of side
    // shows the newest card again.
    property bool fromEnd: false
    property real endGap: 0
    // While holdEnd writes the view's place, which that write must not move.
    property bool holding: false
    property string scrollObjectName: "notificationScrollBar"
    default property alias content: cards.data
    readonly property real textColumn: Math.ceil(Inset.clearing(look.card.pad, look.radius.full, look.card.width, look.card.maxHeight, look.radius.clearance, look.card.pad))
    readonly property alias flickable: view
    readonly property alias cards: cards

    implicitWidth: cards.implicitWidth + look.stack.pad * 2
    implicitHeight: Math.min(cards.implicitHeight + look.stack.tail, maxHeight)

    onFromEndChanged: {
        if (!fromEnd) {
            view.contentY = 0;
            return;
        }
        endGap = 0;
        holdEnd();
    }

    function holdEnd() {
        if (!fromEnd || view.moving || view.flicking) return;
        holding = true;
        view.contentY = Math.max(0, view.contentHeight - view.height - endGap);
        holding = false;
    }

    function motionStep(duration, curve) {
        return { duration: duration, easing: Easing.BezierSpline, curve: [curve.x1, curve.y1, curve.x2, curve.y2, 1, 1] };
    }

    // Sample the look's cubic curve in space, rather than time. The mask
    // changes only content alpha, so the wallpaper receives no colour band.
    function fadePoint(t) {
        const curve = look.motion.curve.standard;
        const back = 1 - t;
        const x = 3 * back * back * t * curve.x1 + 3 * back * t * t * curve.x2 + t * t * t;
        const y = 3 * back * back * t * curve.y1 + 3 * back * t * t * curve.y2 + t * t * t;
        const span = Math.min(look.stack.fadeHeight, view.height / 2) / Math.max(1, view.height);
        return { position: 1 - span + span * x, alpha: 1 - y };
    }

    function maskColor(alpha) {
        const color = Qt.color(root.look.text.foreground);
        color.a = alpha;
        return color;
    }

    Flickable {
        id: view
        anchors.fill: parent
        contentWidth: width
        contentHeight: cards.implicitHeight + root.look.stack.tail
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        acceptedButtons: Qt.NoButton
        clip: true
        // Qt's Item layer effect consumes a texture-backed mask's alpha
        // (doc.qt.io/qt-6/qml-qtquick-effects-multieffect.html). Hidden
        // ancestors disable both layers with their scroll frame.
        layer.enabled: root.visible && height > 0 && !(atYBeginning && atYEnd)
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: fadeMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
        TouchpadScroll { view: view }
        onContentHeightChanged: root.holdEnd()
        onHeightChanged: root.holdEnd()
        onMovementEnded: root.holdEnd()
        // A scroll by the user moves the place the view holds, and so does
        // the view's own return inside its bounds, which Qt 6.11's
        // setContentHeight runs before contentHeightChanged
        // (QQuickFlickable::setContentHeight), so it reads the new height.
        onContentYChanged: if (root.fromEnd && !root.holding) root.endGap = Math.max(0, contentHeight - height - contentY)

        GridLayout {
            id: cards
            x: root.look.stack.pad
            width: root.look.card.width
            columns: 1
            rowSpacing: 0
        }
    }

    Rectangle {
        id: fadeMask
        anchors.fill: view
        visible: false
        layer.enabled: view.layer.enabled
        layer.smooth: true
        gradient: Gradient {
            GradientStop { position: 0; color: root.maskColor(view.atYBeginning ? 1 : 0) }
            GradientStop { position: 1 - root.fadePoint(0.75).position; color: root.maskColor(view.atYBeginning ? 1 : root.fadePoint(0.75).alpha) }
            GradientStop { position: 1 - root.fadePoint(0.5).position; color: root.maskColor(view.atYBeginning ? 1 : root.fadePoint(0.5).alpha) }
            GradientStop { position: 1 - root.fadePoint(0.25).position; color: root.maskColor(view.atYBeginning ? 1 : root.fadePoint(0.25).alpha) }
            GradientStop { position: 1 - root.fadePoint(0).position; color: root.maskColor(1) }
            GradientStop { position: root.fadePoint(0).position; color: root.maskColor(1) }
            GradientStop { position: root.fadePoint(0.25).position; color: root.maskColor(view.atYEnd ? 1 : root.fadePoint(0.25).alpha) }
            GradientStop { position: root.fadePoint(0.5).position; color: root.maskColor(view.atYEnd ? 1 : root.fadePoint(0.5).alpha) }
            GradientStop { position: root.fadePoint(0.75).position; color: root.maskColor(view.atYEnd ? 1 : root.fadePoint(0.75).alpha) }
            GradientStop { position: 1; color: root.maskColor(view.atYEnd ? 1 : 0) }
        }
    }

    SlimScrollBar {
        id: scrollbar
        objectName: root.scrollObjectName
        parent: root
        flickable: view
        x: cards.x + cards.width + root.look.scrollbar.gap
        width: root.look.scrollbar.width
        thin: root.look.scrollbar.thin
        wide: root.look.scrollbar.wide
        minLength: root.look.scrollbar.minHeight
        color: root.look.text.foreground
        radius: root.look.radius.full
        idleOpacity: root.look.scrollbar.idle
        movingOpacity: root.look.scrollbar.moving
        activeOpacity: root.look.scrollbar.active
        widthStep: root.motionStep(root.look.motion.duration.short4, root.look.motion.curve.standard)
        opacityStep: root.motionStep(root.look.motion.duration.medium2, root.look.motion.curve.standard)
    }
}
