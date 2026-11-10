import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons

// A popup under the item it is declared in that tells the user something
// and takes no keyboard: its own surface, anchored to that item's bottom
// edge with its right edge at the item's right edge, sliding along the
// output to stay on it. It shows while `shown` is true and opens and
// closes with the bar flyouts' fade and short anchor-edge slide
// (`motion.flyout`), at once at motion scale 0; while it closes it keeps
// its content mapped, so the content draws what it last drew. It draws no
// ground of its own: its content brings one, as a floating Card does.
// Content goes in the body, `width` is the author's and the height follows
// the content. The pointer reaches the content, which owns its own hover
// and click. `placedBox` is the box the popup takes in its anchor's window,
// which the bar host reads as a bar widget's cover: the compositor slides
// it along the output, and the bar's window spans its output.
//
// Tooltip, Popover and Menu do not serve: a tooltip opens on hover or focus
// and closes on a press, a popover and a menu take the keyboard and close
// on a press outside. This one opens and closes on its owner's state alone.
// The declaring item is an invisible, sizeless member of its parent.
Item {
    id: root

    property bool shown: false
    default property alias content: body.data
    readonly property Item anchorItem: parent
    // Whether the popup is on screen, while it closes too.
    readonly property bool drawing: window.visible
    // How far the popup has come in: 0 closed, 1 open.
    property real motionProgress: 0
    // The popup's box in its anchor's window, or an empty rect while it is
    // not drawn.
    property rect placedBox: Qt.rect(0, 0, 0, 0)

    visible: false
    onShownChanged: {
        if (shown) {
            window.visible = true;
            place();
        }
        setMotion(shown ? 1 : 0);
    }
    onWidthChanged: place()
    Component.onDestruction: motion.stop()

    function setMotion(target) {
        motion.stop();
        if (Theme.motion.flyout.travel.duration <= 0) {
            motionProgress = target;
            if (target === 0) close();
            return;
        }
        motion.to = target;
        motion.duration = Theme.motion.flyout.travel.duration;
        motion.easing.type = Theme.motion.flyout.travel.easing;
        motion.start();
    }

    function close() {
        window.visible = false;
        placedBox = Qt.rect(0, 0, 0, 0);
    }

    // Under the anchor, its right edge at the anchor's right edge, slid
    // along the anchor's window to stay inside it.
    function place() {
        const host = anchorItem === null ? null : anchorItem.Window.window;
        if (!window.visible || host === null) return;
        const at = anchorItem.mapToItem(null, 0, 0);
        const x = Math.max(0, Math.min(host.width - width, at.x + anchorItem.width - width));
        placedBox = Qt.rect(x, at.y + anchorItem.height + Theme.popover.gap, width, window.implicitHeight);
    }

    NumberAnimation {
        id: motion
        target: root
        property: "motionProgress"
        onStopped: if (!root.shown && root.motionProgress === 0) root.close()
    }

    PopupWindow {
        id: window
        anchor.item: root.anchorItem
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        anchor.adjustment: PopupAdjustment.Slide
        anchor.margins.bottom: -Theme.popover.gap
        // No grab: a popup with one takes the keyboard (Tooltip.qml).
        grabFocus: false
        visible: false
        color: "transparent"
        implicitWidth: Math.max(1, root.width)
        implicitHeight: Math.max(1, body.childrenRect.height)
        onImplicitHeightChanged: root.place()
        readonly property AnchorTracker tracker: AnchorTracker {
            popup: window
            anchor: root.anchorItem
            closeOnHide: false
            onFollowed: root.place()
            onAnchorHidden: {
                root.motionProgress = 0;
                root.close();
            }
        }

        // The content fades as one image while it moves (SummonPopup.qml).
        Item {
            id: body
            objectName: "passivePopupBody"
            anchors.fill: parent
            opacity: root.motionProgress
            layer.enabled: root.motionProgress < 1
            transform: Translate { y: -Theme.motion.flyout.slide * (1 - root.motionProgress) }
        }
    }
}
