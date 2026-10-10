import QtQuick
import qs.Commons

// A package's palette as a row of small chips, one per colour, in the
// order `shell.theme.swatch` answers them; null draws nothing.
Row {
    id: root

    property var swatch: null

    visible: swatch !== null
    spacing: Theme.stack.row

    Repeater {
        model: root.swatch === null ? [] : Object.keys(root.swatch)
        Rectangle {
            required property string modelData
            width: Theme.icon.size.sm
            height: Theme.icon.size.sm
            radius: Theme.radius.sm
            color: root.swatch[modelData]
            border.width: Theme.surface.border
            border.color: Theme.surface.level.base.border
        }
    }
}
