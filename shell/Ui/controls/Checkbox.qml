import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import qs.Commons
import qs.Ui
import "../foundation/KeyNavLogic.js" as KeyNavLogic

// A checkbox with an optional text after it. The template holds `checked`
// and toggles it on a click, Space or Enter; the box fills with the
// checked colour and draws the check icon on it. Hover strengthens the
// outline, or the checked fill, and a press fills the box. The text draws
// in `item`; the box centres on its capital centre on a whole pixel, and
// the control is never shorter than `size.control.sm`, so a click just
// beside the box still reaches it. `inkEnd` is where the box, or the
// text after it, ends, or the unlock mark after them.
// A set `disabledReason` disables the checkbox: it stays a Tab stop, takes
// no click or key, draws faded with no hover or press, and shows the
// reason on hover and keyboard focus (DisabledReason). With `unlock` set,
// `{ label, run }`, a lock-open mark after the box, or after the text,
// runs that step (UnlockMark); the checkbox is that much wider.
T.CheckBox {
    id: root

    readonly property real minimumWidth: Theme.control.minWidth
    readonly property real maximumWidth: Theme.control.maxWidth
    Layout.minimumWidth: minimumWidth
    Layout.maximumWidth: maximumWidth
    width: Math.max(minimumWidth, Math.min(maximumWidth, implicitWidth))
    InputWidth { target: root }

    property bool focusPreview: false
    property string disabledReason: ""
    property var unlock: null
    readonly property DisabledReason lock: lockState

    // The content's left padding already holds the indicator and the gap;
    // the right padding holds the unlock mark.
    implicitWidth: (text !== "" ? implicitContentWidth : implicitIndicatorWidth) + rightPadding
    rightPadding: mark.room
    implicitHeight: Math.max(Theme.size.control.sm, implicitIndicatorHeight, implicitContentHeight)

    readonly property real inkEnd: {
        return root.text === "" ? indicator.x + indicator.width + root.rightPadding : Math.min(root.width, root.implicitWidth);
    }
    spacing: Theme.checkbox.gap
    hoverEnabled: !lockState.locked
    PointerCursor { enabled: !lockState.locked }
    opacity: enabled ? 1 : Theme.opacity.disabled
    Accessible.name: text
    Keys.onReturnPressed: KeyNavLogic.activate(root)
    Keys.onEnterPressed: KeyNavLogic.activate(root)
    Keys.onPressed: event => { event.accepted = lockState.takeKey(event); }

    indicator: Rectangle {
        implicitWidth: Theme.checkbox.size
        implicitHeight: Theme.checkbox.size
        y: root.contentItem.indicatorY(height)
        radius: Theme.checkbox.radius
        color: lockState.faded(root.checked ? (root.down ? Theme.checkbox.checkedPressed : root.hovered ? Theme.checkbox.checkedHover : Theme.checkbox.checked) : root.down ? Theme.checkbox.pressed : Theme.checkbox.background)
        border.width: Theme.checkbox.border
        border.color: root.checked ? color : lockState.faded(root.hovered || root.down ? Theme.checkbox.hoverBorder : Theme.checkbox.borderColor)
        Behavior on color { ColorAnimation { duration: Theme.motion.duration.fast; easing.type: Theme.motion.easing.standard } }

        Icon {
            anchors.centerIn: parent
            name: "check"
            size: Theme.icon.size.xs
            color: Theme.checkbox.mark
            opacity: lockState.fade
            visible: root.checked
        }

        FocusRing { target: root; outside: true }
    }

    contentItem: IndicatorLabel { control: root; opacity: lockState.fade }

    DisabledReason { id: lockState; control: root }
    UnlockMark { id: mark; control: root; bodyEnd: root.inkEnd - mark.room; centreY: root.indicator.y + root.indicator.height / 2 }
}
