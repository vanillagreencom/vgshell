import QtQuick
import qs.Commons
import qs.Ui

// A key cap: one key name inside a muted chip `kbd.height` tall, never
// narrower than it is tall. A hint's key name draws in the keyName role
// and hint ink; a `value` cap, a field's bound key, draws in the kbd role
// and value ink. Under a rounded theme the side padding grows until the
// label clears the drawn corner.
Rectangle {
    id: root

    property string text: ""
    // The cap shows a field's value, not a key hint.
    property bool value: false
    // The key name's ink: its part's default, unless the caps around it
    // hand the ink they resolved once for their surface.
    property color ink: Theme.keyHintInk(null, root.value ? "value" : "key")
    readonly property real sidePadding: Theme.controlPadding(Theme.kbd.paddingX, Theme.kbd.radius, Theme.kbd.height, label.lineBox)

    implicitWidth: Math.max(Theme.kbd.height, Math.round(label.opticalWidth + 2 * sidePadding))
    implicitHeight: Math.max(Theme.kbd.height, label.lineBox)
    radius: Theme.kbd.radius
    color: Theme.kbd.background
    border.width: Theme.kbd.border
    border.color: Theme.kbd.borderColor

    Label {
        id: label
        role: root.value ? "kbd" : "keyName"
        text: root.text
        color: root.ink
        x: Math.round((root.width - opticalWidth) / 2)
        y: topForCapCenter(root.height)
    }
}
