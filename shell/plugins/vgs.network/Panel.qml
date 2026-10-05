import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    property var shell: null
    property var payload: ({})
    readonly property Item initialFocus: body.initialFocus
    implicitWidth: Theme.size.panel.lg
    implicitHeight: layout.implicitHeight
    function open(payloadJson) { payload = payloadJson ? JSON.parse(payloadJson) : {}; body.open(); }
    function close() { body.close(); }
    Surface { anchors.fill: parent }
    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight
        header: [Label { role: "h3"; text: "Network" }]
        footer: [Button { text: "Network settings"; variant: "tertiary"; onClicked: root.shell.surfaces.summon("pane", "{}") }]
        NetworkBody { id: body; objectName: "network-body"; width: layout.contentWidth; shell: root.shell }
    }
}
