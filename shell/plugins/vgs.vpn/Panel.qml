import QtQuick
import qs.Commons
import qs.Ui
import "VpnLogic.js" as Logic

// The VPN flyout: its header says what is connected, the body lists the
// profiles (VpnBody), and VPN settings opens the System Settings section.
// No header switch: one switch cannot say which profile it moves. The
// body's password prompt draws over this Pane (VpnBody promptPane).
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
        title: "VPN"
        subtitle: [
            Label {
                objectName: "vpn-subtitle"
                width: layout.headerWidth
                role: "body"
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: Logic.summary(body.profiles)
            }
        ]
        footer: [Button { objectName: "vpn-settings"; text: "VPN settings"; variant: "tertiary"; iconName: "settings"; onClicked: root.openSettings() }]

        VpnBody {
            id: body
            width: layout.contentWidth
            shell: root.shell
            promptPane: layout
        }
    }
}
