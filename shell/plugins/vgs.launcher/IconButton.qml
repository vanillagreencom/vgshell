import QtQuick
import qs.Ui

// A ghost icon button: a press squish and a pointer cursor. It draws no
// fill or border in any state; the caller dims its glyph at rest,
// brightens it on hover and draws it in the accent while `checked`.
Item {
    id: button

    required property var look
    property string label: ""
    property bool checked: false
    readonly property bool hovered: mouse.containsMouse
    default property alias content: inner.data
    signal clicked()

    width: look.button.size
    height: look.button.size

    Item {
        id: inner
        anchors.fill: parent
        scale: mouse.pressed ? button.look.button.pressScale : 1
        Behavior on scale {
            Anim { duration: button.look.motion.duration.short4; curve: button.look.motion.curve.emphasizedDecel }
        }
    }

    // keyboard-path: the launcher binds Ctrl+B to the categories action this button shows
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        PointerCursor {}
        onClicked: button.clicked()
    }

    Tooltip {
        text: button.label
    }
}
