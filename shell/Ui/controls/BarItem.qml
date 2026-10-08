import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import qs.Commons
import qs.Ui
import "../foundation/KeyNavLogic.js" as KeyNavLogic

// One item of the bar: a workspace pill or a widget's button. It is
// `bar.item.height` tall and its content, `bar.item.paddingX` in from each
// side, is an optional icon `bar.item.icon` wide at full opacity or a
// spinner in its place, an optional `text`, and an optional `count`, drawn
// in the `bar` role in `tone`, the same way in every widget. The item is
// never narrower than it is tall, and an item that draws an icon alone is
// square, its icon centred. The tooltip reads `tooltip` as its title and
// `tooltipDetails` as its quieter detail lines. `active` fills it with
// `bar.active`, as the focused workspace; otherwise hover and press fill
// it with `bar.item.hover` and `bar.item.pressed`. The template owns the
// click, hover and focus, and the ring shows for keyboard focus.
T.AbstractButton {
    id: root

    readonly property real minimumWidth: Theme.control.minWidth
    readonly property real maximumWidth: Theme.control.maxWidth
    Layout.minimumWidth: minimumWidth
    Layout.maximumWidth: maximumWidth
    width: Math.max(minimumWidth, Math.min(maximumWidth, implicitWidth))
    InputWidth { target: root }

    property string iconName: ""
    property string count: ""
    // TextMetrics.advanceWidth keeps these slots independent of the current
    // reading. Empty reservations retain the label's natural width.
    property string reservedText: ""
    property string reservedCount: ""
    property color textTone: foreground
    property color countTone: foreground
    property bool spinning: false
    property bool active: false
    property color tone: Theme.bar.foreground
    property string tooltip: ""
    property var tooltipDetails: []
    property bool focusPreview: false
    // What a screen reader and a probe name the item: its text, or the
    // widget's name for an item that draws an icon alone.
    property string label: text
    readonly property color foreground: active ? Theme.bar.onActive : tone

    implicitWidth: Math.max(implicitHeight, Math.ceil(implicitContentWidth) + leftPadding + rightPadding)
    implicitHeight: Theme.bar.item.height
    readonly property bool iconOnly: text === "" && count === ""
    leftPadding: iconOnly ? Math.floor((Theme.bar.item.height - Theme.bar.item.icon) / 2) : Theme.bar.item.paddingX
    rightPadding: leftPadding
    spacing: Theme.bar.item.iconGap
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    PointerCursor {}
    opacity: enabled ? 1 : Theme.opacity.disabled
    Accessible.name: label
    Keys.onReturnPressed: KeyNavLogic.activate(root)
    Keys.onEnterPressed: KeyNavLogic.activate(root)

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight

        Row {
            id: row
            anchors.centerIn: parent
            spacing: root.spacing

            Item {
                visible: root.iconName !== "" || root.spinning
                width: Theme.bar.item.icon
                height: Theme.bar.item.icon
                anchors.verticalCenter: parent.verticalCenter

                Icon {
                    anchors.centerIn: parent
                    visible: !root.spinning
                    name: root.iconName
                    size: Theme.bar.item.icon
                    color: root.foreground
                }
                Spinner {
                    anchors.centerIn: parent
                    visible: root.spinning
                    size: Theme.bar.item.icon
                }
            }
            TextMetrics { id: textWidth; font: textLabel.font; text: root.reservedText }
            TextMetrics { id: countWidth; font: countLabel.font; text: root.reservedCount }
            Label {
                id: textLabel
                role: "bar"
                visible: root.text !== ""
                width: root.reservedText === "" ? implicitWidth : Math.ceil(textWidth.advanceWidth)
                horizontalAlignment: Text.AlignRight
                text: root.text
                color: root.textTone
                y: topForCapCenter(row.height)
            }
            Label {
                id: countLabel
                role: "bar"
                visible: root.count !== ""
                width: root.reservedCount === "" ? implicitWidth : Math.ceil(countWidth.advanceWidth)
                horizontalAlignment: Text.AlignRight
                text: root.count
                color: root.countTone
                y: topForCapCenter(row.height)
            }
        }
    }

    background: Rectangle {
        radius: Theme.bar.item.radius
        color: root.active ? Theme.bar.active : root.down ? Theme.bar.item.pressed : root.hovered ? Theme.bar.item.hover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.motion.duration.fast; easing.type: Theme.motion.easing.standard } }
        FocusRing { target: root }
    }

    Tooltip {
        text: root.tooltip !== "" ? root.tooltip
            : root.iconOnly || root.tooltipDetails.length > 0 || (root.label !== root.text && root.label !== root.count) ? root.label : ""
        details: root.tooltipDetails
    }
}
