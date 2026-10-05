import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import "TrayLogic.js" as TrayLogic

// One tray icon, `size` square, from the image source Quickshell resolves
// for the item, its `?path=` search folder included. A symbolic icon ships
// a fixed fill the host is meant to recolour, so it draws in `tint`: the
// icon is kept as a hidden layer the effect samples.
Item {
    id: root

    property string source: ""
    property real size: 0
    property color tint: "transparent"
    readonly property bool symbolic: TrayLogic.isSymbolic(source)

    implicitWidth: size
    implicitHeight: size

    IconImage {
        id: image
        anchors.fill: parent
        source: root.source
        visible: !root.symbolic
        layer.enabled: root.symbolic
    }

    MultiEffect {
        anchors.fill: image
        source: image
        visible: root.symbolic
        colorization: 1
        colorizationColor: root.tint
    }
}
