import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import qs.Commons
import qs.Ui
import "../foundation/KeyNavLogic.js" as KeyNavLogic

// One item of the bar: a workspace pill or a widget's button. It is
// `bar.item.height` tall and its content, `bar.item.paddingX` in from each
// side, is an optional icon `bar.item.icon` wide at full opacity or a
// spinner in its place, or a short `caption` word there instead, an
// optional `text`, and an optional `count`, drawn in the `bar` role in
// `tone`, the same way in every widget. A value at `textLevel` or
// `countLevel` "warning" or "danger" draws in that state colour, and the
// icon or caption draws in the most severe level of the values shown, so
// it turns red exactly when a value beside it does. A `separator` draws
// flush between text and count in `bar.item.separator`, never a state
// colour; without one the two keep the item gap. The item is as wide as
// what it draws and reserves no room after it; the `bar` role is mono, so
// a reading's width moves only with its character count. The item is
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
    property string caption: ""
    property string separator: ""
    // "normal", "warning" or "danger".
    property string textLevel: "normal"
    property string countLevel: "normal"
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
    // The most severe level among the values shown; an unknown level
    // ranks as normal.
    readonly property var levels: ["normal", "warning", "danger"]
    readonly property string level: levels[Math.max(0, text === "" ? 0 : levels.indexOf(textLevel), count === "" ? 0 : levels.indexOf(countLevel))]
    function levelColor(value) {
        return value === "danger" ? Theme.color.danger : value === "warning" ? Theme.color.warning : foreground;
    }

    implicitWidth: Math.max(implicitHeight, Math.ceil(implicitContentWidth) + leftPadding + rightPadding)
    implicitHeight: Theme.bar.item.height
    readonly property bool iconOnly: text === "" && count === "" && caption === ""
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

            Label {
                role: "bar"
                visible: root.caption !== "" && !root.spinning
                text: root.caption
                color: glyph.color
                y: topForCapCenter(row.height)
            }
            Item {
                visible: (root.iconName !== "" && root.caption === "") || root.spinning
                width: Theme.bar.item.icon
                height: Theme.bar.item.icon
                anchors.verticalCenter: parent.verticalCenter

                Icon {
                    id: glyph
                    anchors.centerIn: parent
                    visible: !root.spinning
                    name: root.iconName
                    size: Theme.bar.item.icon
                    color: root.levelColor(root.level)
                }
                Spinner {
                    anchors.centerIn: parent
                    visible: root.spinning
                    size: Theme.bar.item.icon
                }
            }
            Row {
                id: values
                visible: root.text !== "" || root.count !== ""
                spacing: root.separator !== "" ? 0 : root.spacing
                Label {
                    id: textLabel
                    role: "bar"
                    visible: root.text !== ""
                    text: root.text
                    color: root.levelColor(root.textLevel)
                    y: topForCapCenter(row.height)
                }
                Label {
                    role: "bar"
                    visible: root.separator !== "" && root.text !== "" && root.count !== ""
                    text: root.separator
                    color: Theme.bar.item.separator
                    y: topForCapCenter(row.height)
                }
                Label {
                    id: countLabel
                    role: "bar"
                    visible: root.count !== ""
                    text: root.count
                    color: root.levelColor(root.countLevel)
                    y: topForCapCenter(row.height)
                }
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
