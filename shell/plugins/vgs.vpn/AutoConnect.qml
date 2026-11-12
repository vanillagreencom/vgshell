import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "VpnLogic.js" as Logic

// Connect automatically, in System Settings: the profile to connect on a
// network not on the trusted list, from the service's `vpnChoices`, and
// Trusted networks, one row with a switch per saved Wi-Fi profile of the
// service's last list read (`networks`), the active ones first; only a
// Wi-Fi profile can be trusted (VpnLogic.networkList). Both write the plugin's
// own settings, `autoConnect` and `trustedNetworks`, which the Settings
// page draws from the manifest too; the labels, hints and info are the
// manifest's, so both pages read alike. The line under the profile is the
// service's `autoConnectProblem`, the field's error on both pages.
Column {
    id: root

    property var shell: null
    signal replied(string reply, string refusal)

    readonly property var schema: shell === null ? ({}) : shell.manifest.schema
    readonly property var values: shell === null ? ({}) : shell.status.values
    readonly property var choices: Array.isArray(values.vpnChoices) ? values.vpnChoices : []
    readonly property string chosen: shell === null || typeof shell.settings.autoConnect !== "string" ? "" : shell.settings.autoConnect.toLowerCase()
    // Off is the first choice and stands for the empty setting.
    readonly property int chosenIndex: chosen === "" ? 0 : choices.findIndex((choice, index) => index > 0 && choice.value === chosen)
    readonly property var networks: values.networks !== undefined && values.networks !== null ? values.networks : Logic.emptyNetworks("reading")
    readonly property var trusted: Logic.trustedUuids(shell === null ? [] : shell.settings.trustedNetworks)

    width: parent === null ? implicitWidth : parent.width
    spacing: Theme.stack.group

    function save(key, value) {
        replied(shell.configure.set(key, value), "VGS could not save this setting.");
    }

    Section {
        objectName: "vpn-auto-connect-section"
        width: root.width
        title: root.schema.autoConnect === undefined ? "" : root.schema.autoConnect.group

        Field {
            width: root.width
            inline: true
            label: root.schema.autoConnect === undefined ? "" : root.schema.autoConnect.label
            info: root.schema.autoConnect === undefined ? "" : root.schema.autoConnect.info
            hint: root.schema.autoConnect === undefined ? "" : root.schema.autoConnect.description
            error: typeof root.values.autoConnectProblem === "string" ? root.values.autoConnectProblem : ""

            Select {
                objectName: "vpn-auto-connect"
                width: parent.width
                Accessible.name: "Connect automatically: " + currentText
                model: root.choices
                textRole: "label"
                currentIndex: root.chosenIndex
                // A saved profile no longer listed; the error line says so.
                placeholderText: "Choose a profile"
                onActivated: index => {
                    currentIndex = Qt.binding(() => root.chosenIndex);
                    root.save("autoConnect", index === 0 ? "" : root.choices[index].value);
                }
            }
        }
    }

    Section {
        objectName: "vpn-trusted-networks"
        width: root.width
        title: root.schema.trustedNetworks === undefined ? "" : root.schema.trustedNetworks.label
        description: root.schema.trustedNetworks === undefined ? "" : root.schema.trustedNetworks.description
        info: root.schema.trustedNetworks === undefined ? "" : root.schema.trustedNetworks.info

        Label {
            objectName: "vpn-trusted-empty"
            width: root.width
            visible: text !== ""
            role: "hint"
            text: root.networks.state === "unreadable" ? "VGS could not read your saved networks"
                : root.networks.state === "available" && root.networks.rows.length === 0 ? "No saved Wi-Fi networks yet" : ""
            wrapMode: Text.Wrap
        }
        Repeater {
            // Keyed rows keep a switch's focus while the list is read again:
            // https://quickshell.org/docs/v0.3.1/types/Quickshell/ScriptModel
            model: ScriptModel { values: root.networks.rows; objectProp: "uuid" }
            // A row leaving the model loses its parent before it is
            // destroyed, so it reads the section's width, not its parent's.
            ContentRow {
                id: networkRow
                required property var modelData
                objectName: "vpn-trusted-row:" + modelData.uuid
                width: root.width
                iconName: "wifi"
                text: modelData.name
                secondary: modelData.active ? modelData.type + " · Connected" : modelData.type
                trailing: [
                    Switch {
                        objectName: "vpn-trusted:" + networkRow.modelData.uuid
                        anchors.verticalCenter: parent.verticalCenter
                        size: "sm"
                        Accessible.name: "Trust " + networkRow.modelData.name
                        checked: root.trusted.indexOf(networkRow.modelData.uuid) !== -1
                        onToggled: {
                            const wanted = checked;
                            const uuid = networkRow.modelData.uuid;
                            checked = Qt.binding(() => root.trusted.indexOf(networkRow.modelData.uuid) !== -1);
                            root.save("trustedNetworks", Logic.trustedChange(root.shell.settings.trustedNetworks, uuid, wanted));
                        }
                    }
                ]
            }
        }
    }
}
