import QtQuick
import qs.Commons
import qs.Ui

// The VPN flyout: the connection switch, sign-in and the exit nodes
// (VpnBody.qml), and a button that opens the VPN section of System.
Item {
    id: root

    property var shell: null
    property var payload: ({})
    readonly property Item initialFocus: body.initialFocus

    implicitWidth: Theme.size.panel.lg
    implicitHeight: layout.implicitHeight

    function open(payloadJson) {
        payload = payloadJson ? JSON.parse(payloadJson) : {};
        body.open();
    }
    function close() { body.close(); }

    function openSettings() {
        const reply = shell.surfaces.summon("pane", "{}");
        if (reply !== "ok") console.warn("vpn panel: pane " + reply);
        else shell.surfaces.hide("panel");
    }

    Surface { anchors.fill: parent }

    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight
        header: [Label { role: "h3"; text: "VPN" }]
        footer: [Button { text: "VPN settings"; variant: "tertiary"; iconName: "settings"; onClicked: root.openSettings() }]

        VpnBody {
            id: body
            width: layout.contentWidth
            shell: root.shell
        }
    }
}
