import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// One choice among a few, drawn as adjoining segments: `model` lists the
// segment texts and `currentIndex` the chosen one. Set wider than its
// content, the control gives each segment an equal share of its width,
// with the label centred, while the share holds the widest segment;
// unsized, each segment is as wide as its own label. A click or the left
// and right keys move it; `activated` fires on a change the user made. The
// control is one tab stop: the segments take no focus of their own, so the
// ring draws around the whole control and the keys act on it. A segment
// that is not chosen fills on hover and more on a press, and the chosen
// one draws an accent stroke along its foot; a segment's corner is the
// control's less its inset, so it nests in a rounded control, and a
// disabled control fades.
T.Control {
    id: root

    property var model: []
    property int currentIndex: 0
    property bool focusPreview: false
    // The segments' own widths and gaps, which the control's implicit width
    // reads rather than the row's, whose children may take a share.
    readonly property real naturalContentWidth: {
        let total = Math.max(0, model.length - 1) * Theme.segmented.gap;
        for (const child of row.children) {
            if (child.implicitWidth !== undefined) total += child.implicitWidth;
        }
        return total;
    }
    readonly property real widestSegment: {
        let widest = 0;
        for (const child of row.children) {
            if (child.implicitWidth !== undefined) widest = Math.max(widest, child.implicitWidth);
        }
        return widest;
    }
    // Each segment's equal share of the width, or 0 while that share is
    // narrower than the widest segment, which then keeps its own width.
    readonly property real segmentShare: {
        if (model.length === 0) return 0;
        const share = (availableWidth - (model.length - 1) * Theme.segmented.gap) / model.length;
        return share >= widestSegment ? share : 0;
    }
    signal activated(int index)

    function choose(index) {
        if (index < 0 || index >= model.length || index === currentIndex) return;
        currentIndex = index;
        activated(index);
    }

    implicitWidth: naturalContentWidth + leftPadding + rightPadding
    implicitHeight: Theme.segmented.height
    padding: Theme.segmented.padding
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : Theme.opacity.disabled
    Keys.onPressed: event => { event.accepted = nav.handle(event); }

    property KeyNav nav: KeyNav {
        count: root.model.length
        currentIndex: root.currentIndex
        orientation: "horizontal"
        wrap: false
        onMoved: index => root.choose(index)
    }

    contentItem: Row {
        id: row
        height: root.availableHeight
        spacing: Theme.segmented.gap

        Repeater {
            model: root.model
            // keyboard-path: the segmented control is one tab stop and its arrow keys choose segments
            T.Button {
                id: segment
                required property int index
                required property var modelData
                readonly property bool current: index === root.currentIndex

                width: root.segmentShare > 0 ? root.segmentShare : implicitWidth
                height: row.height
                focusPolicy: Qt.NoFocus
                implicitWidth: implicitContentWidth + leftPadding + rightPadding
                leftPadding: Theme.controlPadding(Theme.segmented.paddingX, Math.max(0, Theme.segmented.radius - Theme.segmented.padding), row.height, implicitContentHeight)
                rightPadding: leftPadding
                hoverEnabled: true
                PointerCursor {}
                text: String(modelData)
                Accessible.name: text
                onClicked: { root.forceActiveFocus(Qt.MouseFocusReason); root.choose(index); }

                contentItem: Label {
                    role: "button"
                    text: segment.text
                    color: segment.current ? Theme.segmented.selectedForeground : Theme.segmented.foreground
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Math.max(0, Theme.segmented.radius - Theme.segmented.padding)
                    color: segment.current ? Theme.segmented.selected : segment.down ? Theme.segmented.pressed : segment.hovered ? Theme.segmented.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.motion.duration.fast; easing.type: Theme.motion.easing.standard } }
                    // Inset by the corner so the stroke stays inside the rounded fill.
                    Rectangle {
                        objectName: "segmentIndicator"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: parent.radius
                        anchors.rightMargin: parent.radius
                        height: Theme.segmented.indicator
                        color: Theme.segmented.indicatorColor
                        visible: segment.current
                    }
                }
            }
        }
    }

    background: Rectangle {
        radius: Theme.segmented.radius
        color: Theme.segmented.background
        border.width: Theme.border.thin
        border.color: Theme.segmented.border
        FocusRing { target: root; targetRadius: Theme.segmented.radius }
    }
}
