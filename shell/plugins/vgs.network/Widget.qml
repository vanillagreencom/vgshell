import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    readonly property var network: shell === null ? ({}) : shell.status.values.network || ({})
    readonly property var joined: (network.wifi || []).find(row => row.connected) || null
    readonly property string icon: joined !== null ? "wifi" : (network.ethernet || []).some(row => row.connected) ? "ethernet-port" : "wifi-off"
    visible: setting("showDisconnected", true) || root.joined !== null || (network.ethernet || []).some(row => row.connected)
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    BarItem {
        id: button
        anchors.centerIn: parent
        label: "Network"
        iconName: root.icon
        tooltip: root.joined === null ? root.network.text || "Network" : root.joined.name + " · " + root.joined.strength + "%"
        onClicked: root.shell.surfaces.toggle("panel", "{}")
    }
}
