import QtQuick
import qs.Commons
import qs.Ui
import "VpnLogic.js" as Logic

// The body the flyout and the System pane share. It draws the `vpn` value
// the service publishes and asks the service for every change through the
// plugin's own IPC; it starts no process. While it is open it holds a
// lease, which makes the service's poll fast. The setup step, Install,
// Enable or Allow, is the `setup` status entry's action as the core's
// status rows offer it (`status.rows`), run through `status.act`.
//
// Tab moves from the connection switch to the exit nodes and, in the
// pane, the accounts. Up and Down move inside a list, and Enter chooses.
FocusScope {
    id: root

    property var shell: null
    // The pane's extra sections: this device, accounts, devices, the poll.
    property bool expanded: false
    property string leaseId: ""
    property bool leased: false
    // The line a refused request left, "" for none.
    property string localProblem: ""

    readonly property var vpn: shell === null || !shell.status.values.vpn ? Logic.unread() : shell.status.values.vpn
    readonly property var profiles: shell === null || !shell.status.values.profiles ? Object.assign(Logic.emptyProfiles(), { action: "", problem: "" }) : shell.status.values.profiles
    readonly property var profileRows: profiles.rows
    readonly property bool busy: vpn.action !== ""
    readonly property bool switchable: ["running", "starting", "stopped"].indexOf(vpn.state) !== -1
    readonly property bool reached: switchable || vpn.state === "signed-out" || vpn.state === "needs-approval"
    // The setup step the core offers now, { label }, else null.
    readonly property var setupAction: {
        if (shell === null) return null;
        const row = shell.status.rows.find(r => r.key === "setup");
        return row === undefined || row.action === null || !row.action.offered ? null : { label: row.action.label };
    }
    readonly property var exitRows: [{ key: "", text: "None", secondary: "Use this computer's own connection", iconName: "globe-off",
        badge: vpn.exit === null ? "In use" : "", badgeTone: "success" }].concat(vpn.exitNodes.map(node => ({
            key: node.id, text: node.place !== "" ? node.place : node.name,
            secondary: node.place !== "" ? node.name : node.online ? "Online" : "Offline", iconName: "globe",
            badge: node.active ? "In use" : "", badgeTone: "success" })))
    readonly property var accountRows: vpn.accounts.map(row => ({ key: row.id, text: row.account, secondary: row.tailnet,
        iconName: "user", badge: row.current ? "In use" : "", badgeTone: "success" }))
    readonly property var pollChoices: [10, 30, 60]
    // The connection switch while it can be used, else the body, from
    // which Tab reaches the setup step: no view opens on a step that
    // changes the system (design-system.md § Keyboard).
    readonly property Item initialFocus: connectField.visible && toggle.enabled ? toggle : root

    implicitHeight: content.implicitHeight

    // Qt moves Tab only from an item that is a Tab stop. The body is none,
    // so its own Tab would start from the window's first stop and leave
    // the section.
    Keys.onTabPressed: event => {
        nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason);
        event.accepted = true;
    }

    function open() {
        if (leaseId === "") leaseId = String(root);
        if (shell !== null && !leased) leased = shell.ipc.call("lease", JSON.stringify({ id: leaseId, open: true })) === "ok";
    }
    function close() {
        if (!leased || shell === null) return;
        shell.ipc.call("lease", JSON.stringify({ id: leaseId, open: false }));
        leased = false;
    }
    Component.onDestruction: close()

    function answered(reply, refusal) {
        localProblem = reply === "ok" ? "" : reply === "busy" ? "A VPN change is still in progress." : refusal;
        if (reply !== "ok" && reply !== "busy") console.warn("vpn: " + reply);
        return reply;
    }
    function request(kind, id) {
        return answered(shell.ipc.call("action", JSON.stringify({ kind: kind, id: id })), "Tailscale cannot do this now.");
    }

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        Label {
            objectName: "vpn-state"
            width: parent.width
            role: "body"
            textFormat: Text.PlainText
            visible: root.vpn.state !== "missing"
            text: root.vpn.text
            wrapMode: Text.Wrap
        }
        Label {
            objectName: "vpn-problem"
            width: parent.width
            visible: text !== ""
            role: "hint"
            color: Theme.color.danger
            text: root.localProblem !== "" ? root.localProblem : root.profiles.problem !== "" ? root.profiles.problem : root.vpn.problem
            wrapMode: Text.Wrap
        }
        RowAction {
            objectName: "vpn-setup"
            visible: root.vpn.state !== "missing" && root.setupAction !== null
            text: root.setupAction === null ? "" : root.setupAction.label
            onClicked: root.answered(root.shell.status.act("setup"), "VGS could not open the setup step.")
        }
        Field {
            id: connectField
            width: parent.width
            visible: root.expanded && root.switchable
            label: "Tailscale"
            inline: true

            Switch {
                id: toggle
                objectName: "vpn-toggle"
                size: "sm"
                Accessible.name: "Tailscale"
                checked: root.vpn.state !== "stopped"
                enabled: root.vpn.writable && !root.busy
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.vpn.state !== "stopped");
                    root.request(wanted ? "connect" : "disconnect", "");
                }
            }
        }
        Button {
            objectName: "vpn-sign-in"
            visible: root.vpn.state === "signed-out" && root.vpn.login === "idle"
            enabled: root.vpn.writable
            text: "Sign in"
            iconName: "log-in"
            onClicked: root.request("login", "")
        }
        Row {
            visible: root.vpn.login !== "idle"
            spacing: Theme.control.gap

            Label {
                anchors.verticalCenter: parent.verticalCenter
                role: "hint"
                text: root.vpn.login === "opened" ? "Finish the sign-in in your browser." : "Opening the sign-in page"
            }
            RowAction {
                anchors.verticalCenter: parent.verticalCenter
                text: "Cancel"
                onClicked: root.request("cancel-login", "")
            }
        }
        Section {
            width: parent.width
            visible: root.vpn.state === "running"
            title: "Exit node"
            description: root.vpn.exitCount > root.vpn.exitNodes.length
                ? "Showing " + root.vpn.exitNodes.length + " of " + root.vpn.exitCount + " exit nodes." : ""

            DeviceList {
                id: exitList
                objectName: "vpn-exit-nodes"
                width: parent.width
                enabled: root.vpn.writable && !root.busy
                rows: root.exitRows
                onActed: key => { if (key !== (root.vpn.exit === null ? "" : root.vpn.exit.id)) root.request("exit-node", key); }
            }
        }
        Section {
            width: parent.width
            visible: root.expanded && root.reached
            title: "This device"

            Repeater {
                model: [["Name", root.vpn.device.name], ["Address", root.vpn.device.address], ["Network", root.vpn.tailnet], ["Account", root.vpn.account]]

                Field {
                    id: deviceRow
                    required property var modelData
                    width: parent.width
                    visible: modelData[1] !== ""
                    label: modelData[0]
                    inline: true

                    Label { role: "value"; textFormat: Text.PlainText; text: deviceRow.modelData[1]; elide: Text.ElideRight }
                }
            }
        }
        Section {
            width: parent.width
            visible: root.expanded && root.reached
            title: "Accounts"
            rowSpacing: Theme.stack.group

            DeviceList {
                objectName: "vpn-accounts"
                width: parent.width
                visible: root.accountRows.length > 0
                enabled: root.vpn.writable && !root.busy
                rows: root.accountRows
                onActed: key => { if (!root.vpn.accounts.some(row => row.id === key && row.current)) root.request("switch", key); }
            }
            RowAction {
                visible: root.vpn.login === "idle" && root.vpn.state !== "signed-out"
                enabled: root.vpn.writable
                text: "Add account"
                onClicked: root.request("login", "")
            }
        }
        Section {
            width: parent.width
            visible: root.expanded && root.vpn.peers.length > 0
            title: "Devices"
            description: root.vpn.peerCount > root.vpn.peers.length
                ? "Showing " + root.vpn.peers.length + " of " + root.vpn.peerCount + " devices." : ""

            Repeater {
                model: root.vpn.peers

                Field {
                    id: peerRow
                    required property var modelData
                    width: parent.width
                    label: modelData.name
                    inline: true

                    Label {
                        role: "value"
                        textFormat: Text.PlainText
                        text: peerRow.modelData.online ? peerRow.modelData.address : "Offline"
                    }
                }
            }
        }
        Section {
            width: parent.width
            visible: root.profiles.state === "available"
            title: "VPN profiles"
            description: root.profiles.count > root.profileRows.length
                ? "Showing " + root.profileRows.length + " of " + root.profiles.count + " profiles." : ""

            Repeater {
                model: root.profileRows

                ProfileRow {
                    id: profileRow
                    width: parent.width
                    busy: root.profiles.action !== ""
                    onToggleRequested: wanted => {
                        root.answered(root.shell.ipc.call("action", JSON.stringify({
                            kind: wanted ? "profile-up" : "profile-down", id: profileRow.modelData.id
                        })), "This VPN profile cannot change now.");
                    }
                }
            }
            RowAction {
                objectName: "vpn-import"
                text: "Import WireGuard"
                onClicked: root.answered(root.shell.ipc.call("import-wireguard", ""), "VGS could not open the import window.")
            }
        }
        Field {
            width: parent.width
            visible: root.expanded && root.vpn.state !== "missing"
            label: "Check every"
            hint: "How often VGS reads Tailscale while this section is closed."
            inline: true

            SegmentedControl {
                objectName: "vpn-poll"
                model: root.pollChoices.map(seconds => seconds + " s")
                currentIndex: root.shell === null ? 1 : root.pollChoices.indexOf(root.shell.settings.pollSeconds)
                onActivated: index => root.answered(root.shell.configure.set("pollSeconds", root.pollChoices[index]), "VGS could not save this setting.")
            }
        }
    }
}
