import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// A tooltip for the item it is declared in: it draws one title line and
// optional quieter detail lines. A detail is a string line, or `{ label,
// value }` for a count row whose value column aligns with the other count
// rows. After the theme's delay with the pointer resting on the item or
// after keyboard focus reaches it, the tooltip opens in its own surface
// under the item and takes no focus. It closes when the pointer leaves and
// focus leaves, on a press on the item, when the item hides, and it does
// not open while another overlay is open. After a press it stays closed
// until the pointer leaves the item, so it never covers what the press
// opened. The declaring item is an invisible, sizeless member of its parent.
Item {
    id: root

    property string text: ""
    property var details: []
    readonly property bool opened: window.visible
    readonly property Item anchorItem: parent

    // The handlers live on the anchor, made once it is known: a handler
    // declared with a parent binding crashes the engine while the parent
    // is still null.
    property var hover: null
    property var press: null
    // A press on the item since the pointer last entered it.
    property bool pressedHere: false
    readonly property Component hoverComponent: Component { HoverHandler { onHoveredChanged: if (!hovered) root.pressedHere = false } }
    // pointer-cursor-exempt: it watches a press on the anchor to close the tooltip; the anchor's own control owns the cursor
    // keyboard-path: the anchor's focus opens the tooltip and focus leaving closes it
    readonly property Component pressComponent: Component { TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onPressedChanged: if (pressed) root.pressedHere = true } }
    readonly property bool focusResting: anchorItem !== null && ("visualFocus" in anchorItem) && anchorItem.visualFocus === true
    readonly property bool resting: ((hover !== null && hover.hovered && !(press !== null && press.pressed) && !pressedHere) || focusResting) && text !== ""

    visible: false

    Component.onCompleted: {
        if (anchorItem === null) return;
        hover = hoverComponent.createObject(anchorItem);
        press = pressComponent.createObject(anchorItem);
    }

    onRestingChanged: {
        if (resting) delay.restart();
        else { delay.stop(); window.visible = false; }
    }

    Timer {
        id: delay
        interval: Theme.tooltip.delay
        onTriggered: if (root.resting && OverlayState.open === 0) window.visible = true
    }

    // Another overlay opening closes a tooltip already shown.
    Connections {
        target: OverlayState
        function onOpenChanged() { if (OverlayState.open > 0) window.visible = false; }
    }

    PopupWindow {
        id: window

        anchor.item: root.anchorItem
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
        anchor.margins.bottom: -Theme.tooltip.gap
        grabFocus: false
        visible: false
        color: "transparent"
        // One line up to `tooltip.maxWidth`, then title and plain details
        // wrap; never wider than the output less its gutters.
        readonly property real paddedWidth: Math.min(content.implicitWidth + 2 * Theme.tooltip.paddingX, OverlayState.widthFor(root.anchorItem, Theme.tooltip.maxWidth + 2 * Theme.tooltip.paddingX))
        implicitWidth: Math.max(1, paddedWidth)
        implicitHeight: Math.max(1, content.implicitHeight + 2 * Theme.tooltip.paddingY)

        // Under a rounded theme the text sits in from the sides until it
        // clears the drawn corner.
        ClearingInset {
            id: sideInset
            pad: Theme.tooltip.paddingX
            radius: Theme.tooltip.radius
            width: window.paddedWidth
            height: content.implicitHeight + 2 * Theme.tooltip.paddingY
            top: Theme.tooltip.paddingY
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.tooltip.radius
            color: Theme.tooltip.background
            border.width: Theme.border.thin
            border.color: Theme.tooltip.border
        }

        Item {
            id: content
            objectName: "tooltipContent"
            x: sideInset.inset
            y: Theme.tooltip.paddingY
            width: Math.max(0, window.width - 2 * sideInset.inset)
            height: column.implicitHeight
            implicitWidth: Math.min(Math.max(titleWidth, detailWidth), Theme.tooltip.maxWidth)
            implicitHeight: column.implicitHeight

            readonly property real titleWidth: Math.min(Math.ceil(titleLabel.implicitWidth), Theme.tooltip.maxWidth)
            readonly property real labelColumnWidth: detailColumn.maxColumn("labelImplicitWidth")
            readonly property real valueColumnWidth: detailColumn.maxColumn("valueImplicitWidth")
            readonly property real countWidth: labelColumnWidth > 0 || valueColumnWidth > 0 ? labelColumnWidth + Theme.tooltip.gap + valueColumnWidth : 0
            readonly property real detailWidth: Math.min(Math.max(detailColumn.maxColumn("detailWidth"), countWidth), Theme.tooltip.maxWidth)
            readonly property string detailRole: "itemHint"
            readonly property int lineWrapMode: Text.Wrap

            function detailModel() {
                if (Array.isArray(root.details)) return root.details;
                throw new Error("Tooltip: details=" + JSON.stringify(root.details) + " unexpected");
            }

            function isCount(entry) {
                return entry !== null && typeof entry === "object" && !Array.isArray(entry)
                    && Object.prototype.hasOwnProperty.call(entry, "label")
                    && Object.prototype.hasOwnProperty.call(entry, "value");
            }

            function detailKind(entry, index) {
                if (typeof entry === "string") return "plain";
                if (isCount(entry)) return "count";
                throw new Error("Tooltip: details[" + index + "]=" + JSON.stringify(entry) + " unexpected");
            }

            function detailHidden(entry) {
                return isCount(entry) && (entry.value === 0 || entry.value === "0");
            }

            Column {
                id: column
                width: content.width
                spacing: Theme.tooltip.gap

                Label {
                    id: titleLabel
                    objectName: "tooltipTitle"
                    role: "tooltip"
                    text: root.text
                    color: Theme.tooltip.foreground
                    width: parent.width
                    wrapMode: content.lineWrapMode
                }

                Column {
                    id: detailColumn
                    objectName: "tooltipDetails"
                    width: parent.width
                    spacing: Theme.tooltip.gap
                    visible: root.details.length > 0

                    function maxColumn(propertyName) {
                        var max = 0;
                        for (var i = 0; i < children.length; i++) {
                            var child = children[i];
                            if (child.visible && child[propertyName] !== undefined)
                                max = Math.max(max, Math.ceil(child[propertyName]));
                        }
                        return max;
                    }

                    Repeater {
                        model: content.detailModel()
                        delegate: Item {
                            objectName: kind === "count" ? "tooltipCountRow" : "tooltipDetailRow"
                            property var entry: modelData
                            readonly property string kind: content.detailKind(entry, index)
                            readonly property bool zeroRow: content.detailHidden(entry)
                            readonly property bool isCountDetail: kind === "count"
                            readonly property real labelImplicitWidth: countLabel.implicitWidth
                            readonly property real valueImplicitWidth: valueLabel.implicitWidth
                            readonly property real detailWidth: kind === "plain" ? plainLabel.detailWidth : labelImplicitWidth + Theme.tooltip.gap + valueImplicitWidth
                            width: detailColumn.width
                            height: !visible ? 0 : kind === "plain" ? plainLabel.height : Math.max(countLabel.height, valueLabel.height)
                            visible: !zeroRow

                            Label {
                                id: plainLabel
                                objectName: "tooltipDetailLine"
                                property real detailWidth: Math.min(Math.ceil(implicitWidth), Theme.tooltip.maxWidth)
                                visible: kind === "plain"
                                role: content.detailRole
                                text: kind === "plain" ? entry : ""
                                width: parent.width
                                wrapMode: content.lineWrapMode
                            }

                            Label {
                                id: countLabel
                                objectName: "tooltipCountLabel"
                                visible: kind === "count"
                                role: content.detailRole
                                text: kind === "count" ? String(entry.label) : ""
                                width: Math.max(0, parent.width - content.valueColumnWidth - Theme.tooltip.gap)
                                elide: Text.ElideRight
                            }

                            Label {
                                id: valueLabel
                                objectName: "tooltipCountValue"
                                visible: kind === "count"
                                role: content.detailRole
                                text: kind === "count" ? String(entry.value) : ""
                                x: parent.width - width
                                width: content.valueColumnWidth
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }
            }
        }
    }

    readonly property AnchorTracker tracker: AnchorTracker { popup: window; anchor: root.anchorItem }
}
