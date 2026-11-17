import QtQuick
import qs.Commons
import qs.Ui

// The frame of a multi-line text input, `target`, a TextArea: its fill, its
// outline and its focus ring, faded while the target is locked. The outline
// shows the error first, then keyboard focus, then hover. The ring keeps
// the error colour while the target holds keyboard focus. A TextArea
// draws it as its background; a box that holds more than the text, such as
// a message box with its own choices and Send, draws it around them all
// and sets the area `framed: false`.
Rectangle {
    id: root

    required property Item target
    readonly property color outline: target.lock.faded(target.error ? Theme.textField.error
        : focusRing.visible ? Theme.textField.focus : target.hovered ? Theme.textField.hover : Theme.textField.borderColor)

    radius: Theme.textField.radius
    color: target.lock.faded(Theme.textField.background)
    border.width: Theme.textField.border
    // Do not animate the outline: a focus reset must clear the keyboard
    // colour immediately.
    border.color: outline
    FocusRing { id: focusRing; target: root.target; ringColor: root.target.error ? Theme.textField.error : Theme.focusRing.color }
}
