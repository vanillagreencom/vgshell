import QtQuick
import qs.Commons
import qs.Ui

// The readout of a level, which LevelOsd and LevelSlider share: `text`
// right-aligned in a column as wide as "100%" or the text, whichever is
// wider, up to `maxWidth`, where the text elides, so what stands beside it
// keeps its place while the level changes. It draws in `role`, its line
// placed by capital height in the height its caller gives it, and
// `lineBox` is that role's line, for a caller that sizes a row from it.
Item {
    id: root

    property string text: ""
    property string role: "label"
    property real maxWidth: Infinity
    readonly property real lineBox: label.lineBox
    readonly property bool truncated: label.truncated

    width: Math.min(maxWidth, Math.max(label.implicitWidth, widest.implicitWidth))
    implicitHeight: label.lineBox

    Label { id: widest; visible: false; role: root.role; text: "100%" }
    Label {
        id: label
        role: root.role
        text: root.text
        width: parent.width
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        y: topForCapCenter(parent.height)
    }
}
