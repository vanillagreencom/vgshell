import QtQuick
import qs.Commons

Grid {
    id: root

    // The `#rrggbbaa` colours, in order; empty draws nothing.
    property var colours: []
    readonly property int rowCount: Math.max(Math.ceil(colours.length / columns), 1)

    Repeater {
        model: root.colours
        Rectangle {
            required property string modelData
            width: root.width / root.columns
            height: root.height / root.rowCount
            color: Theme.toColor(modelData)
        }
    }
}
