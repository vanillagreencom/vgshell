import QtQuick
import qs.Commons
import qs.Ui

// The locked state of a control, internal to the module: an enabled
// control whose `disabledReason` is set. Qt gives a disabled item no
// active focus and Tab skips it, so a control a reason disables stays
// Qt-enabled and this takes its actions away instead: a shield over the
// control takes every press while locked, so a click toggles, opens or
// clicks nothing, and `takeKey` takes Space, Return and Enter, the keys
// the control hands it first. `KeyNavLogic.activate` refuses a locked
// control too, since a `Keys.onReturnPressed` handler runs before
// `Keys.onPressed` and stops it (a qml-unit run, 2026-10-13). The control
// draws no hover or press while locked. Its drawn parts fade while the
// control itself stays opaque, so an unlock mark it holds (UnlockMark)
// draws at full strength: a part that holds the control's FocusRing draws
// its fill and border through `faded`, the colour at the disabled
// opacity, so the ring on it keeps its full strength, and a part with no
// ring binds `fade`, the disabled opacity. The reason shows in the shared
// Tooltip on hover and on keyboard focus of the control, built only while
// locked, on its "clear" side, so it covers no sibling text or control,
// and is the control's accessible description. A control the
// plain Qt `enabled` disables is not locked: it keeps its own fade and
// shows no reason. A control that keeps some of its parts working while
// locked, as a DeviceList with a row that opens does, sets `shields`
// false: no shield covers it, and it refuses its locked parts' presses
// itself.
Item {
    id: root

    required property Item control
    property bool shields: true
    readonly property bool locked: control.enabled && control.disabledReason !== ""
    readonly property bool shielded: locked && shields
    readonly property real fade: locked ? Theme.opacity.disabled : 1
    // The box the reason's places keep clear of, in the control's
    // coordinates, and the width its text wraps past. A holder that draws
    // the control's name outside it, as Pane draws a header switch's,
    // widens the box over that name and narrows the text to the room the
    // name leaves.
    property rect reasonBox: Qt.rect(0, 0, control.width, control.height)
    property real reasonWidth: Theme.tooltip.maxWidth

    // `color` as a locked part draws it (Theme.faded).
    function faded(color) {
        return locked ? Theme.faded(color) : color;
    }

    // Whether a locked control takes `event`, so the control never acts.
    function takeKey(event) {
        return locked && [Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter].indexOf(event.key) !== -1;
    }

    anchors.fill: parent
    // Over the control's own parts, which would take a press first; under
    // its unlock mark.
    z: 1

    // pointer-cursor-exempt: it takes the presses of a locked control, which a press cannot change; the control's PointerCursor stands down while locked, so the arrow shows
    // keyboard-path: the control keeps its focus and its keys, which takeKey refuses while locked
    // Hidden while unlocked too: Qt takes a cursor from the topmost item
    // under the pointer, and the shield's arrow would hide the control's
    // hand (a gallery smoke run, 2026-10-13).
    MouseArea {
        anchors.fill: parent
        visible: root.shielded
        enabled: root.shielded
        acceptedButtons: Qt.AllButtons
    }

    Binding {
        target: root.control
        property: "Accessible.description"
        value: root.control.disabledReason
        when: root.locked
    }

    Loader {
        active: root.locked
        sourceComponent: Tooltip {
            objectName: "disabledReasonTip"
            anchorItem: root.control
            text: root.control.disabledReason
            side: "clear"
            box: root.reasonBox
            maxWidth: root.reasonWidth
        }
    }
}
