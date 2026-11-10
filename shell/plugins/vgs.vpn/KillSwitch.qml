import QtQuick
import qs.Commons
import qs.Ui
import "VpnLogic.js" as Logic

// The kill switch (D129), in the flyout and in System Settings: Block
// traffic if the VPN drops and, while it is on, Allow local network under
// it, which the service writes into the state file as kill-switch=block,
// block-lan or off over IPC. Until the `vpn-kill-switch` system step is
// set up, Set up stands in the switch's place and runs the step through
// the `killSwitch` status action. The line under the switch says what the
// root half reads (VpnLogic.killSwitchView), in the danger colour when it
// blocks traffic for a profile it cannot use; beside the blocked-traffic
// notice, it is the refused count, which the switch's info explains.
// Nothing shows before the service publishes `killSwitchState`.
Section {
    id: root

    property var shell: null
    property var profiles: ({})
    readonly property var view: Logic.killSwitchView(shell === null ? null : shell.status.values.killSwitchState, profiles)
    signal replied(string reply, string refusal)

    objectName: "vpn-kill-switch"
    width: parent.width
    visible: view.shown
    title: "Kill switch"
    infoTitle: "How the kill switch works"
    info: "When a VPN you turned on in VGS drops, the kill switch blocks traffic outside it until it connects again or you turn it off in VGS.\n"
        + "Turning the VPN off in another app or in a terminal counts as a drop, so the block stays.\n"
        + "The block works while VGS is not running and after a restart. It works with WireGuard profiles.\n"
        + "Containers and virtual machines on this computer work only with Allow local network on."

    function setMode(mode) {
        replied(shell.ipc.call("kill-switch", mode), "VGS could not save the kill switch setting.");
    }

    Field {
        objectName: "vpn-kill-switch-field"
        width: parent.width
        inline: true
        label: "Block traffic if the VPN drops"
        // Only while its line is the refused count: what the count counts.
        info: root.view.countInfo
        hint: root.view.tone === "" ? root.view.hint : ""
        error: root.view.tone === "danger" ? root.view.hint : ""

        RowAction {
            objectName: "vpn-kill-switch-setup"
            visible: root.view.setup
            text: "Set up"
            onClicked: root.replied(root.shell.status.act("killSwitch"), "VGS could not open the kill switch setup.")
        }
        Switch {
            objectName: "vpn-kill-switch-toggle"
            visible: !root.view.setup
            size: "sm"
            Accessible.name: "Block traffic if the VPN drops"
            checked: root.view.switchOn
            disabledReason: root.view.reason
            onToggled: {
                const wanted = checked;
                checked = Qt.binding(() => root.view.switchOn);
                root.setMode(wanted ? "block" : "off");
            }
        }
    }
    Field {
        objectName: "vpn-kill-switch-lan-field"
        width: parent.width
        visible: root.view.lanShown
        inline: true
        label: "Allow local network"
        hint: Logic.KILL_LAN_HINT

        Switch {
            objectName: "vpn-kill-switch-lan"
            size: "sm"
            Accessible.name: "Allow local network"
            checked: root.view.lanOn
            disabledReason: root.view.reason
            onToggled: {
                const wanted = checked;
                checked = Qt.binding(() => root.view.lanOn);
                root.setMode(wanted ? "block-lan" : "block");
            }
        }
    }
}
