import QtQuick
import qs.Commons

// The ring a control draws while it has keyboard focus. It fills the
// control's background and draws on its own edge, inside its bounds, so a
// focused control never looks larger or wears a second border. It shows
// for `visualFocus`, which Qt raises for keyboard focus and not for a
// click, so a pointer user never sees it. A target without `visualFocus`,
// such as a text input or a plain item, shows it for `activeFocus`, since
// an input with the caret is focused however it got there.
// `targetRadius` is the corner of the shape the ring draws on: the radius
// of the item it fills, `focusRing.radius` when that item has none, so the
// ring follows a rounded control, a pill or a circle. `ringColor` lets a
// control keep a state cue, such as an error, while it holds focus.
// A ring on a fill it cannot be told from, below WCAG 2.2 SC 1.4.11's 3:1,
// such as the accent fill of a primary button, draws in
// `focusRing.contrast` instead, which the theme judge holds against every
// resting surface around the control.
Rectangle {
    id: root

    required property Item target
    property real targetRadius: parent !== null && parent.radius !== undefined ? parent.radius : Theme.focusRing.radius
    property color ringColor: Theme.focusRing.color
    // The colour the item it fills paints, or null for none.
    readonly property var fill: parent !== null && parent.color !== undefined && parent.color.a > 0 ? parent.color : null
    readonly property color drawnColor: fill !== null && Theme.contrastRatio(ringColor, fill) < Theme.boundaryFloor ? Theme.focusRing.contrast : ringColor

    anchors.fill: parent
    visible: target.focusPreview === true || (("visualFocus" in target) ? target.visualFocus : target.activeFocus)
    color: "transparent"
    border.color: drawnColor
    border.width: Theme.focusRing.width
    radius: targetRadius
}
