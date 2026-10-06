import QtQuick
import qs.Commons

// The ring a control draws while it has keyboard focus. Its inner edge sits
// `offset` outside the target, and square targets keep square rings.
// `ringColor` lets a control keep a state cue, such as an error, while it
// holds focus.
Rectangle {
    id: root

    required property Item target
    property int offset: Theme.focusRing.offset
    property real targetRadius: parent !== null && parent.radius !== undefined ? parent.radius : Theme.focusRing.radius
    property color ringColor: Theme.focusRing.color
    readonly property real ringWidth: Theme.focusRing.width
    readonly property real ringRadius: targetRadius === 0 ? 0 : targetRadius + offset + ringWidth

    anchors.fill: parent
    anchors.margins: -(offset + ringWidth)
    visible: target.focusPreview === true || (("visualFocus" in target) ? target.visualFocus : target.activeFocus)
    color: "transparent"
    border.color: ringColor
    border.width: ringWidth
    radius: ringRadius
}
