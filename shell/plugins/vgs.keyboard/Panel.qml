import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    property var shell: null
    readonly property Item initialFocus: controls.firstFocus
    function open(payloadJson) {}
    function close() {}
    implicitWidth: Theme.size.panel.lg
    implicitHeight: layout.implicitHeight
    Surface { anchors.fill: parent }
    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight
        title: "Keyboard"
        KeyboardControls { id: controls; width: layout.contentWidth; shell: root.shell }
    }
}
