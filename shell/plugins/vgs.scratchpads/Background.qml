import QtQuick

// The click away from a shown pad. While a pad is shown, Hyprland hands a
// click on that screen outside the pad's window to no window, and to the
// layer under the windows instead, so this instance is shown on a screen while a pad is shown there, draws
// nothing, and hides the pad on a click. The service publishes which pad
// each screen shows.
Item {
    id: root

    property var shell: null
    property var screen: null

    readonly property var shownOn: shell === null || shell.status.values.shown === undefined ? ({}) : shell.status.values.shown
    readonly property string pad: screen !== null && Object.prototype.hasOwnProperty.call(shownOn, screen.name) ? shownOn[screen.name] : ""
    readonly property bool shown: pad !== ""

    // pointer-cursor-exempt: a press here is a click away from the shown pad, not a control
    // keyboard-path: the pad's own key hides it, and so does a focus move to another window
    MouseArea {
        anchors.fill: parent
        enabled: root.shown
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: {
            const reply = root.shell.compositor.togglePad(root.pad, root.screen.name);
            if (reply !== "ok") console.warn("scratchpads: pad=" + root.pad + " hide " + reply);
        }
    }
}
