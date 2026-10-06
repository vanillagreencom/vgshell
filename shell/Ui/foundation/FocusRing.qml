import QtQuick
import qs.Commons

// The ring a control draws while it has keyboard focus. It shows for
// `visualFocus`, which Qt raises for keyboard focus and not for a click,
// so a pointer user never sees it. A target without `visualFocus`, such as
// a text input or a plain item, shows it for `activeFocus`, since an input
// with the caret is focused however it got there.
//
// It has two placements. A box control, whose shape holds its label or
// content, such as a button, a field or a bar item, draws the ring on its
// own edge, inside its bounds: a ring around such a control read as a
// second border. A ring on a fill it cannot be told from, below WCAG 2.2
// SC 1.4.11's 3:1, such as a primary button's accent, draws in white or
// black, whichever contrasts more with the fill (`Theme.contrastOf`); one
// of the two meets any opaque fill at 4.58:1 or more. That ring sits
// `focusRing.offset` inside the edge, so the fill shows on both sides of
// it: on the edge, white or black matches the page behind the control in
// one of the two modes, and the control only looks smaller. A glyph control, a
// small shape beside or under its label such as a radio, a checkbox, a
// switch or a slider handle, a control that draws no box around its text,
// and a container set `outside`: a ring on a radio's or a handle's edge
// cannot be told from its own border or fill, and one on a bare label runs
// through its glyphs. That ring sits `focusRing.offset` outside the control,
// so the surface shows in the gap, and keeps `ringColor`.
// `targetRadius` is the corner of the shape the ring follows: the radius
// of the item it fills, `focusRing.radius` when that item has none, so the
// ring follows a rounded control, a pill or a circle. `ringColor` lets a
// control keep a state cue, such as an error, while it holds focus.
Rectangle {
    id: root

    required property Item target
    property bool outside: false
    property real targetRadius: parent !== null && parent.radius !== undefined ? parent.radius : Theme.focusRing.radius
    property color ringColor: Theme.focusRing.color
    // The colour the item it fills paints, or null for none.
    readonly property var fill: parent !== null && parent.color !== undefined && parent.color.a > 0 ? parent.color : null
    // An edge ring that `ringColor` cannot show on the fill.
    readonly property bool contrastRing: !outside && fill !== null && Theme.contrastRatio(ringColor, fill) < Theme.boundaryFloor
    readonly property color drawnColor: contrastRing ? Theme.contrastOf(fill) : ringColor
    // How far the ring's outer edge lies outside the control; below 0, how
    // far inside it.
    readonly property real extent: outside ? Theme.focusRing.offset + Theme.focusRing.width : contrastRing ? -Theme.focusRing.offset : 0
    // The ring's corner: the target's own, moved by the extent, and square
    // on a square target.
    readonly property real ringRadius: targetRadius === 0 ? 0 : Math.max(0, targetRadius + extent)

    anchors.fill: parent
    anchors.margins: -extent
    visible: target.focusPreview === true || (("visualFocus" in target) ? target.visualFocus : target.activeFocus)
    color: "transparent"
    border.color: drawnColor
    border.width: Theme.focusRing.width
    radius: ringRadius
}
