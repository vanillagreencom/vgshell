import QtQuick
import QtQuick.Window

// The root of a grabbing popup's content, shared by Popover, Menu and the
// list of Select: an Escape no item inside accepts closes the popup, and so
// does a press anywhere in the window its anchor draws in. The compositor's
// grab dismisses the popup on a press outside that window but hands a press
// inside it to the shell like any other (runtime-pointer.md), so while the
// popup is open one item over that window's content takes the press. It
// closes the popup and keeps the press from what lies under it, as the
// compositor's dismissal does; hover and the wheel still reach the window.
FocusScope {
    id: scope

    required property var popup
    required property Item anchor

    // The content of the window the anchor draws in while the popup is
    // open, and the catcher over it.
    readonly property Item covered: popup.visible && anchor !== null && anchor.Window.window !== null ? anchor.Window.window.contentItem : null
    property Item catcher: null

    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: popup.visible = false

    function drop() {
        if (catcher === null) return;
        catcher.visible = false;
        catcher.destroy();
        catcher = null;
    }
    onCoveredChanged: {
        drop();
        if (covered !== null) catcher = catcherComponent.createObject(covered);
    }
    Component.onDestruction: drop()

    Component {
        id: catcherComponent

        // pointer-cursor-exempt: a press here is a press beside the open popup, not a control
        MouseArea {
            anchors.fill: parent
            // Above every item the window draws.
            z: Number.MAX_VALUE
            acceptedButtons: Qt.AllButtons
            onPressed: scope.popup.visible = false
            onWheel: wheel => { wheel.accepted = false; }
        }
    }
}
