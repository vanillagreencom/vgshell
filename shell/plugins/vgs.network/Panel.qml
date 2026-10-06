import QtQuick
import qs.Commons
import qs.Ui

// The Network dropdown under the bar widget: what the computer is
// connected through, the Wi-Fi networks to join where a Wi-Fi device
// exists, every Ethernet device with its state, and a footer whose Network
// settings opens System on this plugin's pane and closes the dropdown.
Item {
    id: root
    property var shell: null
    property var payload: ({})
    readonly property Item initialFocus: layout.headerSwitch !== null ? layout.headerSwitch : body.initialFocus
    implicitWidth: Theme.size.panel.lg
    implicitHeight: layout.implicitHeight
    function open(payloadJson) { payload = payloadJson ? JSON.parse(payloadJson) : {}; body.open(); }
    function close() { body.close(); }

    // Open System on the Network pane and close the dropdown; answers the
    // panes holder's reply.
    function openSettings() {
        const reply = shell.surfaces.summon("pane", "{}");
        if (reply !== "ok") {
            console.warn("network panel: pane " + reply);
            body.localProblem = "System is not available. Turn it on in Plugins.";
            return reply;
        }
        shell.surfaces.hide("panel");
        return reply;
    }

    Surface { anchors.fill: parent }
    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight
        title: "Network"
        switchShown: !!body.network.hasWifi
        switchChecked: !!body.network.wifiEnabled
        switchEnabled: !!body.network.writable && body.network.wifiHardwareEnabled !== false
        switchName: "Wi-Fi"
        onSwitchToggled: checked => body.action("radio", null)

        footer: [Button { width: layout.contentWidth; text: "Network settings"; iconName: "settings"; variant: "tertiary"; onClicked: root.openSettings() }]
        NetworkBody { id: body; objectName: "network-body"; width: layout.contentWidth; shell: root.shell }
    }
}
