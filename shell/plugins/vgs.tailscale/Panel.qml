import QtQuick
import qs.Commons
import qs.Ui

// The Tailscale flyout: the connection switch, sign-in and the exit nodes
// (TailscaleBody.qml), and a button that opens the Tailscale section of System.
Item {
    id: root

    property var shell: null
    property var payload: ({})
    // The header switch while it can be used, else where the body opens.
    readonly property Item initialFocus: layout.headerSwitch !== null && layout.headerSwitch.enabled && body.lockReason === "" ? layout.headerSwitch : body.initialFocus

    implicitWidth: Theme.size.panel.lg
    implicitHeight: layout.implicitHeight

    function open(payloadJson) {
        payload = payloadJson ? JSON.parse(payloadJson) : {};
        body.open();
    }
    function close() { body.close(); }

    function openSettings() {
        const reply = shell.surfaces.summon("pane", "{}");
        if (reply !== "ok") console.warn("tailscale panel: pane " + reply);
        else shell.surfaces.hide("panel");
    }

    Surface { anchors.fill: parent }

    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight
        title: "Tailscale"
        switchShown: body.switchable
        switchChecked: body.tailscale.state !== "stopped"
        switchEnabled: !body.busy
        switchDisabledReason: body.lockReason
        switchUnlock: body.unlock
        switchName: "Tailscale"
        onSwitchToggled: checked => body.request(checked ? "connect" : "disconnect", "")

        footer: [Button { text: "Tailscale settings"; variant: "tertiary"; iconName: "settings"; onClicked: root.openSettings() }]

        TailscaleBody {
            id: body
            width: layout.contentWidth
            shell: root.shell
        }
    }
}
