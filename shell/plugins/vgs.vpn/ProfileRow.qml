import QtQuick
import qs.Commons
import qs.Ui
import "VpnLogic.js" as Logic

// One saved profile: a Disclosure whose row names it, its type and state
// (VpnLogic.rowView) and ends with its switch, and a spinner before the
// switch while a change runs. The switch stays a Tab stop with its reason
// while it cannot be used. Expanded, it shows the Type row, the Server
// row when the profile names one, the Tunnel address row while connected,
// a WireGuard profile's leak check while connected or dropped under the
// kill switch's block (VpnLogic.checkView): the public address with its
// place, a line per family, the kill switch line while it is not off, and
// Check, which runs it again;
// Reconnect for a dropped profile the kill switch holds the block for and,
// in System Settings, Edit in connection editor then Remove profile at
// the content edge, `stack.group`
// under the details: a remove action with no row of its own leads its text
// with the trash mark (docs/architecture/design-system.md § Settings pages).
Disclosure {
    id: root

    required property var modelData
    property var profiles: ({})
    property var missingRequirements: []
    // Whether the kill switch is on (VpnLogic.killSwitchOn): a profile
    // that is not WireGuard then cannot connect.
    property bool killOn: false
    // The profile the blocked-traffic notice names, or "": it reads
    // Dropped with its switch on, which turns it off.
    property string held: ""
    property bool removable: false
    // The published `leakCheck`, or null.
    property var check: null
    readonly property var view: Logic.rowView(modelData, profiles, missingRequirements, killOn, held)
    readonly property var checkView: Logic.checkView(check, modelData, held)
    readonly property Item removeAction: remove
    readonly property Item switchAction: toggle

    signal toggleRequested(bool wanted)
    // KEYED: the press came from the keyboard, with Reconnect focused.
    signal reconnectRequested(bool keyed)
    signal removeRequested()
    signal editRequested()
    signal installRequested(string requirement)
    signal detailsOpened()
    signal checkRequested()

    objectName: "vpn-profile:" + modelData.uuid
    text: modelData.name
    secondary: view.secondary
    iconName: view.connected ? "shield-check" : "shield"
    onExpandedChanged: if (expanded) detailsOpened()

    trailing: [
        RowAction {
            objectName: "vpn-install-plugin:" + root.modelData.uuid
            anchors.verticalCenter: parent.verticalCenter
            visible: root.view.install !== ""
            text: "Install plugin"
            onClicked: root.installRequested(root.view.install)
        },
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
                label: "Tunnel address"
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
        Column {
            objectName: root.expanded && root.checkView.shown ? "vpn-check:" + root.modelData.uuid : ""
            width: parent.width
            visible: root.checkView.shown
            spacing: Theme.stack.row

            Field {
                width: parent.width
                visible: root.checkView.publicShown
                inline: true
                label: "Public address"
                info: Logic.PUBLIC_INFO
                error: root.checkView.public.error
                hint: root.checkView.public.hint
                hintLink: root.checkView.public.link
                onHintLinkActivated: root.installRequested(root.checkView.public.install)
                Label {
                    objectName: "vpn-public:" + root.modelData.uuid
                    width: parent.width
                    role: "value"
                    textFormat: Text.PlainText
                    text: root.checkView.public.text
                    wrapMode: Text.Wrap
                }
            }
            Field {
                width: parent.width
                visible: root.checkView.place !== ""
                inline: true
                label: "Location"
                Label {
                    objectName: "vpn-place:" + root.modelData.uuid
                    width: parent.width
                    role: "value"
                    textFormat: Text.PlainText
                    text: root.checkView.place
                    wrapMode: Text.Wrap
                }
            }
            Repeater {
                model: root.checkView.families
                // One family's line; a leak or a failed reading says why
                // in the error line.
                Field {
                    id: family
                    required property var modelData
                    width: parent.width
                    inline: true
                    label: family.modelData.label
                    error: family.modelData.error
                    hint: family.modelData.hint
                    hintLink: family.modelData.link
                    onHintLinkActivated: root.installRequested(family.modelData.install)
                    Label {
                        objectName: "vpn-" + family.modelData.key + ":" + root.modelData.uuid
                        width: parent.width
                        role: "value"
                        textFormat: Text.PlainText
                        text: family.modelData.text
                        wrapMode: Text.Wrap
                    }
                }
            }
            Field {
                width: parent.width
                visible: root.checkView.killShown
                inline: true
                label: "Kill switch"
                info: Logic.KILL_COUNT_INFO
                error: root.checkView.kill.error
                Label {
                    objectName: "vpn-check-kill:" + root.modelData.uuid
                    width: parent.width
                    role: "value"
                    textFormat: Text.PlainText
                    text: root.checkView.kill.text
                    wrapMode: Text.Wrap
                }
            }
        }
        // A dropped profile the kill switch holds the block for offers
        // Reconnect, in the flyout too: a connect that keeps the block.
        RowActions {
            width: parent.width
            visible: root.removable || root.view.reconnect || root.checkView.shown
            RowAction {
                objectName: "vpn-check-run:" + root.modelData.uuid
                visible: root.checkView.shown
                text: "Check"
                disabledReason: root.checkView.reason
                onClicked: root.checkRequested()
            }
            RowAction {
                id: reconnect
                objectName: "vpn-reconnect:" + root.modelData.uuid
                visible: root.view.reconnect
                text: "Reconnect"
                onClicked: root.reconnectRequested(reconnect.activeFocus)
            }
            RowAction {
                objectName: "vpn-edit:" + root.modelData.uuid
                visible: root.removable
                text: "Edit in connection editor"
                onClicked: root.editRequested()
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
}
