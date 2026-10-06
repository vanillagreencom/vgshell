import QtQuick
import qs.Commons
import qs.Ui

// The network icon in the bar: Wi-Fi while a Wi-Fi network is joined,
// Ethernet while a wired device is connected, otherwise disconnected. A
// click opens or closes the dropdown under it.
BarWidget {
    id: root
    readonly property var network: shell === null ? ({}) : shell.status.values.network || ({})
    readonly property var joined: (network.wifi || []).find(row => row.connected) || null
    readonly property string icon: joined !== null ? "wifi" : (network.ethernet || []).some(row => row.connected) ? "ethernet-port" : "wifi-off"
    visible: setting("showDisconnected", true) || root.joined !== null || (network.ethernet || []).some(row => row.connected)
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    // Open or close the dropdown under this widget; answers the panel
    // host's reply.
    function toggle() {
        const reply = shell.surfaces.toggle("panel", "{}", root);
        if (reply !== "ok") console.warn("network widget: panel " + reply);
        return reply;
    }

    BarItem {
        id: button
        anchors.centerIn: parent
        label: "Network"
        iconName: root.icon
        tooltip: root.joined === null ? root.network.text || "Network" : root.joined.name + " · " + root.joined.strength + "%"
        onClicked: root.toggle()
    }
}
