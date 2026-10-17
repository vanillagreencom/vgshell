import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import qs.Commons
import qs.Ui
import "../foundation/KeyNavLogic.js" as KeyNavLogic

// An on and off switch with an optional text after it. `size` is `md`, the
// default, or `sm` for inline rows. The template holds `checked` and
// toggles it on a click, Space or Enter, and moves `position` under a drag;
// the knob follows `visualPosition`, so it drags and mirrors, and slides
// on `motion.duration.fast` when not dragged. The knob colour follows the
// track it sits on. Hover lightens the track and a press widens the knob.
// The text draws in `item`; the track centres on its capital centre on a
// whole pixel, and the control is never shorter than `size.control.sm`,
// so a compact track keeps a larger input area. `inkBelow()` is how far
// above its bottom edge the track or the text ends, for the space a
// `Section` measures from what it draws, and `inkAbove()` how far below its
// top edge they start, for the space a key/value row under another
// measures (Field). `inkEnd()` is where the track,
// or the text after it, ends, or the unlock mark after them.
// A set `disabledReason` disables the switch: it stays a Tab stop, takes
// no click or key, draws faded with no hover or press, and shows the
// reason on hover and keyboard focus (DisabledReason). With `unlock` set,
// `{ label, run }`, a lock-open mark after the track, or after the text,
// runs that step (UnlockMark); the switch is that much wider.
// Its tokens are `Theme.toggle`, since `switch` is a JavaScript keyword.
T.Switch {
    id: root

    readonly property real minimumWidth: Theme.control.minWidth
    readonly property real maximumWidth: Theme.control.maxWidth
    Layout.minimumWidth: minimumWidth
    Layout.maximumWidth: maximumWidth
    width: Math.max(minimumWidth, Math.min(maximumWidth, implicitWidth))
    InputWidth { target: root }

    property string size: "md"
    property bool focusPreview: false
    property string disabledReason: ""
    property var unlock: null
    readonly property DisabledReason lock: lockState
    readonly property var sizeTokens: sizeOf(size)

    function sizeOf(name) {
        const found = Theme.toggle.size[name];
        if (found !== undefined) return found;
        console.error("Switch: no size named " + JSON.stringify(name));
        return Theme.toggle.size.md;
    }

    // The content's left padding already holds the indicator and the gap;
    // the right padding holds the unlock mark.
    implicitWidth: (text !== "" ? implicitContentWidth : implicitIndicatorWidth) + rightPadding
    rightPadding: mark.room
    implicitHeight: Math.max(Theme.size.control.sm, implicitIndicatorHeight, implicitContentHeight)

    function inkBelow() {
        const text = root.text === "" ? 0 : contentItem.y + contentItem.height - Theme.inkBelow(contentItem);
        return height - Math.max(indicator.y + indicator.height, text);
    }
    function inkAbove() {
        const text = root.text === "" ? height : contentItem.y + Theme.inkAbove(contentItem);
        return Math.min(indicator.y, text);
    }
    function inkEnd() {
        return root.text === "" ? indicator.x + indicator.width + root.rightPadding : Math.min(root.width, root.implicitWidth);
    }
    spacing: Theme.toggle.gap
    hoverEnabled: !lockState.locked
    PointerCursor { enabled: !lockState.locked }
    opacity: enabled ? 1 : Theme.opacity.disabled
    Accessible.name: text
    Keys.onReturnPressed: KeyNavLogic.activate(root)
    Keys.onEnterPressed: KeyNavLogic.activate(root)
    Keys.onPressed: event => { event.accepted = lockState.takeKey(event); }

    indicator: Rectangle {
        implicitWidth: root.sizeTokens.width
        implicitHeight: root.sizeTokens.height
        y: root.contentItem.indicatorY(height)
        radius: Theme.toggle.radius
        color: lockState.faded(root.checked ? (root.down ? Theme.toggle.onPressed : root.hovered ? Theme.toggle.onHover : Theme.toggle.on) : root.down ? Theme.toggle.offPressed : root.hovered ? Theme.toggle.offHover : Theme.toggle.off)
        Behavior on color { ColorAnimation { duration: Theme.motion.duration.fast; easing.type: Theme.motion.easing.standard } }

        Rectangle {
            readonly property int inset: Theme.toggle.inset
            width: parent.height - 2 * inset + (root.down ? 2 * inset : 0)
            height: parent.height - 2 * inset
            y: inset
            x: inset + root.visualPosition * (parent.width - width - 2 * inset)
            radius: Theme.toggle.radius
            opacity: lockState.fade
            color: root.checked ? Theme.toggle.knobOn : Theme.toggle.knobOff
            Behavior on x { enabled: !root.down; NumberAnimation { duration: Theme.motion.duration.fast; easing.type: Theme.motion.easing.standard } }
        }

        FocusRing { target: root; outside: true }
    }

    contentItem: IndicatorLabel { control: root; opacity: lockState.fade }

    DisabledReason { id: lockState; control: root }
    UnlockMark { id: mark; control: root; bodyEnd: root.inkEnd() - mark.room; centreY: root.indicator.y + root.indicator.height / 2 }
}
