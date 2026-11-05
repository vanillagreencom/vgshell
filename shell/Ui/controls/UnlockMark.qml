import QtQuick
import qs.Commons
import qs.Ui

// The unlock mark of a locked toggle, internal to the module: a lock-open
// IconButton `stack.inline` after the toggle's body, built only while the
// toggle is locked (DisabledReason) and its `unlock` is set. `unlock` is
// `{ label, run }`, the words of the one step the user takes to unlock the
// toggle and the function that takes it, the shape of a setup step's
// action; another value is logged and draws no mark. The mark names the
// step, a click on it, or Space or Enter, calls `run`, and it is the Tab
// stop after the toggle. With the keyboard on it, the mark shows the
// toggle's reason on the tooltip's "clear" side, as the toggle does; under the pointer the toggle's own reason shows, since
// the mark lies inside the toggle and a second tooltip would repeat it.
// `room` is the width the toggle keeps after its body for the mark, 0
// without it. When the lock clears with the keyboard on the mark, as a
// step that unlocks at once does, the focus goes back to the toggle with
// the reason the mark held, before the mark goes: Qt would otherwise move
// it to the enclosing focus scope (QQuickItem::setParentItem clears the
// focus of an item it unparents). A step that opens another window leaves
// the mark its scope's `focus` with no `activeFocus`: the toggle then takes
// the mark's place in that scope and takes the keyboard from no one, so
// the keyboard is on the toggle when the user comes back. Qt hands a
// window that comes back the ActiveWindowFocusReason, so no control shows
// a ring then until the next key moves the focus. The mark is a toggle's
// own part, so an IconButton, which
// extends Button, holds none: Button cannot contain its own kind.
Loader {
    id: root

    required property Item control
    // Where the toggle's body ends, and the height the mark centres on.
    required property real bodyEnd
    required property real centreY
    readonly property bool valid: shaped(control.unlock)
    readonly property real room: item !== null ? Theme.stack.inline + item.width : 0
    readonly property bool wanted: control.lock.locked && valid

    function shaped(unlock) {
        if (unlock === null || unlock === undefined) return false;
        if (typeof unlock === "object" && typeof unlock.label === "string" && unlock.label !== "" && typeof unlock.run === "function") return true;
        console.error("UnlockMark: unlock=" + JSON.stringify(unlock) + " unexpected; want { label, run }");
        return false;
    }

    // Set here, never bound, so the focus moves before the mark goes.
    function follow() {
        if (!wanted && item !== null) {
            if (item.activeFocus) control.forceActiveFocus(item.focusReason);
            else if (item.focus) control.focus = true;
        }
        active = wanted;
    }
    onWantedChanged: follow()
    Component.onCompleted: follow()

    active: false
    x: bodyEnd + Theme.stack.inline
    y: Math.round(centreY - height / 2)
    // Over the toggle's shield (DisabledReason), which takes every other
    // press on the locked toggle.
    z: 2

    sourceComponent: IconButton {
        size: "sm"
        iconName: "lock-open"
        label: root.valid ? root.control.unlock.label : ""
        tooltip: visualFocus ? root.control.disabledReason : ""
        tooltipSide: "clear"
        onClicked: root.control.unlock.run()
    }
}
