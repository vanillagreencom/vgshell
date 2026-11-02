import QtQuick
import qs.Commons
import qs.Ui
import "../foundation/KeyNavLogic.js" as Logic

Row {
    id: root

    property string shortcut: ""
    // The caps show a field's value, not a key hint (Kbd.value).
    property bool value: false
    property var backgroundContext: null
    // Resolved once for every cap of the chord.
    readonly property color ink: Theme.keyHintInk(backgroundContext, value ? "value" : "key")
    readonly property var caps: Logic.keyCaps(shortcut)

    spacing: Theme.space.sm
    visible: caps.length > 0

    Repeater {
        model: root.caps
        Kbd { text: String(modelData); value: root.value; ink: root.ink }
    }
}
