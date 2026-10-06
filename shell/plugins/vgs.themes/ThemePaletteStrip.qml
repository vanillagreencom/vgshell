import QtQuick
import qs.Commons

// A theme card's colours as equal blocks: across the strip, or stacked
// top to bottom when `vertical`. The card places and sizes it.
Grid {
    id: root

    // The `#rrggbbaa` colours, in order; empty draws nothing.
    property var colours: []
    property bool vertical: false

    columns: vertical ? 1 : Math.max(colours.length, 1)

    Repeater {
        model: root.colours
        Rectangle {
            required property string modelData
            width: root.vertical ? root.width : root.width / root.colours.length
            height: root.vertical ? root.height / root.colours.length : root.height
            color: Theme.toColor(modelData)
        }
    }
}
