import QtQuick
import qs.Commons
import qs.Ui
import "VpnLogic.js" as Logic

// One saved profile: a Disclosure whose row names it, its type and state
// (VpnLogic.rowView) and ends with its switch, and a spinner before the
// switch while a change runs. The switch stays a Tab stop with its reason
// while it cannot be used. Expanded, it shows the Type row, the Server
// row when the profile names one, the Address row while connected and,
// in System Settings, Remove profile at the content edge, `stack.group`
// under the details: a remove action with no row of its own leads its text
// with the trash mark (docs/architecture/design-system.md § Settings pages).
Disclosure {
    id: root

    required property var modelData
    property var profiles: ({})
    property bool removable: false
    readonly property var view: Logic.rowView(modelData, profiles)
    readonly property Item removeAction: remove

    signal toggleRequested(bool wanted)
    signal removeRequested()
    signal detailsOpened()

    objectName: "vpn-profile:" + modelData.uuid
    text: modelData.name
    secondary: view.secondary
    iconName: view.connected ? "shield-check" : "shield"
    onExpandedChanged: if (expanded) detailsOpened()

    trailing: [
        Spinner {
            objectName: "vpn-profile-spinner:" + root.modelData.uuid
            anchors.verticalCenter: parent.verticalCenter
            visible: root.view.busy
        },
        Switch {
            id: toggle
            objectName: "vpn-profile-toggle:" + root.modelData.uuid
            anchors.verticalCenter: parent.verticalCenter
            size: "sm"
            Accessible.name: root.modelData.name
            checked: root.view.switchOn
            disabledReason: root.view.reason
            onToggled: {
                const wanted = checked;
                checked = Qt.binding(() => root.view.switchOn);
                root.toggleRequested(wanted);
            }
        }
    ]

    // A failure's secondary line draws in the danger colour (ListItem
    // `secondaryTone`), on the Disclosure's own row.
    Binding {
        target: root.focusItem
        property: "secondaryTone"
        value: root.view.danger ? "danger" : ""
    }

    Column {
        width: parent.width
        spacing: Theme.stack.group

        Column {
            objectName: root.expanded ? "vpn-details:" + root.modelData.uuid : ""
            width: parent.width
            spacing: Theme.stack.row

            Field {
                width: parent.width
                inline: true
                label: "Type"
                Label {
                    objectName: "vpn-type:" + root.modelData.uuid
                    width: parent.width
                    role: "value"
                    textFormat: Text.PlainText
                    text: root.view.type
                }
            }
            Field {
                width: parent.width
                visible: root.modelData.server !== ""
                inline: true
                label: "Server"
                Label {
                    objectName: "vpn-server:" + root.modelData.uuid
                    width: parent.width
                    role: "value"
                    textFormat: Text.PlainText
                    text: root.modelData.server
                    elide: Text.ElideRight
                }
            }
            Field {
                width: parent.width
                visible: root.modelData.address !== ""
                inline: true
                label: "Address"
                Label {
                    objectName: "vpn-address:" + root.modelData.uuid
                    width: parent.width
                    role: "value"
                    textFormat: Text.PlainText
                    text: root.modelData.address
                    elide: Text.ElideRight
                }
            }
        }
        RowAction {
            id: remove
            objectName: "vpn-remove:" + root.modelData.uuid
            visible: root.removable
            tone: "danger"
            text: "Remove profile"
            onClicked: root.removeRequested()
        }
    }
}
