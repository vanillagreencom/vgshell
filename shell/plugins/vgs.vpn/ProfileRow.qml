import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root

    required property var modelData
    property bool busy: false
    readonly property real inset: Theme.controlPadding(Theme.listItem.paddingX, Theme.listItem.radius, height, lines.implicitHeight)

    signal toggleRequested(bool active)

    objectName: "vpn-profile:" + modelData.id
    implicitHeight: Theme.listItem.twoLineHeight

    Icon {
        id: icon
        x: root.inset
        anchors.verticalCenter: parent.verticalCenter
        name: root.modelData.type === "wireguard" ? "waypoints" : "shield"
        size: Theme.icon.size.md
        color: Theme.color.textMuted
    }
    Column {
        id: lines
        x: icon.x + icon.width + Theme.listItem.iconGap
        width: Math.max(0, toggle.x - x - Theme.listItem.gap)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.row.lineGap

        Label {
            width: parent.width
            role: "item"
            textFormat: Text.PlainText
            text: root.modelData.name
            elide: Text.ElideRight
        }
        Label {
            width: parent.width
            role: "itemHint"
            textFormat: Text.PlainText
            text: root.modelData.type === "wireguard" ? "WireGuard" : "VPN"
            elide: Text.ElideRight
        }
    }
    Switch {
        id: toggle
        objectName: "vpn-profile-toggle:" + root.modelData.id
        x: parent.width - root.inset - width
        anchors.verticalCenter: parent.verticalCenter
        size: "sm"
        Accessible.name: root.modelData.name
        checked: root.modelData.active
        enabled: !root.busy
        onToggled: {
            const wanted = checked;
            checked = Qt.binding(() => root.modelData.active);
            root.toggleRequested(wanted);
        }
    }
}
