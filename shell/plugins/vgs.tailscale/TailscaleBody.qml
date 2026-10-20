import QtQuick
import qs.Commons
import qs.Ui
import "TailscaleLogic.js" as Logic

// The body the flyout and the System pane share. It draws the `tailscale` value
// the service publishes and asks the service for every change through the
// plugin's own IPC; it starts no process. While it is open it holds a
// lease, which makes the service's poll fast. The setup step, Enable or
// Allow, is the `setup` status entry's action as the core's
// status rows offer it (`status.rows`), run through `status.act`. While
// Tailscale takes no change, its controls say why (`lockReason`), and the
// connection switch's unlock mark runs the same step.
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

    readonly property var tailscale: shell === null || !shell.status.values.tailscale ? Logic.unread() : shell.status.values.tailscale
    readonly property bool busy: tailscale.action !== ""
    readonly property bool switchable: ["running", "starting", "stopped"].indexOf(tailscale.state) !== -1
    readonly property bool reached: switchable || tailscale.state === "signed-out" || tailscale.state === "needs-approval"
    // The setup step the core offers now, { label, hint }, else null.
    // `hint` is the sentence that says what the step does.
    readonly property var setupAction: {
        if (shell === null) return null;
        const row = shell.status.rows.find(r => r.key === "setup");
        return row === undefined || row.action === null || !row.action.offered ? null : { label: row.action.label, hint: row.hint };
    }
    // Why the controls cannot change Tailscale now, "" while they can, and
    // the switch's unlock mark, the setup step, null while none is offered.
    readonly property string lockReason: Logic.lockReason(tailscale, setupAction === null ? "" : setupAction.label)
    readonly property var unlock: setupAction === null ? null : ({ label: setupAction.label, run: () => root.runSetup() })
    readonly property var exitRows: [{ key: "", text: "None", secondary: "Use this computer's own connection", iconName: "globe-off",
        badge: tailscale.exit === null ? "In use" : "", badgeTone: "success" }].concat(tailscale.exitNodes.map(node => ({
            key: node.id, text: node.place !== "" ? node.place : node.name,
            secondary: node.place !== "" ? node.name : node.online ? "Online" : "Offline", iconName: "globe",
            badge: node.active ? "In use" : "", badgeTone: "success" })))
    readonly property var accountRows: tailscale.accounts.map(row => ({ key: row.id, text: row.account, secondary: row.tailnet,
        iconName: "user", badge: row.current ? "In use" : "", badgeTone: "success" }))
    readonly property var pollChoices: [10, 30, 60]
    // The connection switch while it can be used, else the body, from
    // which Tab reaches the setup step: no view opens on a step that
    // changes the system (design-system.md § Keyboard), nor on a locked
    // switch.
    readonly property Item initialFocus: connectField.visible && toggle.enabled && root.lockReason === "" ? toggle : root

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
        localProblem = reply === "ok" ? "" : reply === "busy" ? "A Tailscale change is still in progress." : refusal;
        if (reply !== "ok" && reply !== "busy") console.warn("tailscale: " + reply);
        return reply;
    }
    function request(kind, id) {
        return answered(shell.ipc.call("action", JSON.stringify({ kind: kind, id: id })), "Tailscale cannot do this now.");
    }
    function runSetup() {
        return answered(shell.status.act("setup"), "VGS could not open the setup step.");
    }

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        Label {
            objectName: "tailscale-state"
            width: parent.width
            role: "body"
            textFormat: Text.PlainText
            visible: root.tailscale.state !== "missing"
            text: root.tailscale.text
            wrapMode: Text.Wrap
        }
        Label {
            objectName: "tailscale-problem"
            width: parent.width
            visible: text !== ""
            role: "hint"
            color: Theme.color.danger
            text: root.localProblem !== "" ? root.localProblem : root.tailscale.problem
            wrapMode: Text.Wrap
        }
        Label {
            id: setupHint
            objectName: "tailscale-setup-hint"
            readonly property bool repeatsReason: true
            opacity: OverlayState.coveredReason === setupHint ? Theme.opacity.disabled : 1
            width: parent.width
            visible: setupStep.visible && text !== ""
            role: "hint"
            textFormat: Text.PlainText
            text: root.setupAction === null ? "" : root.setupAction.hint
            wrapMode: Text.Wrap
        }
        RowAction {
            id: setupStep
            objectName: "tailscale-setup"
            visible: root.tailscale.state !== "missing" && root.setupAction !== null
            text: root.setupAction === null ? "" : root.setupAction.label
            onClicked: root.runSetup()
        }
        Field {
            id: connectField
            width: parent.width
            visible: root.expanded && root.switchable
            label: "Tailscale"
            inline: true

            Switch {
                id: toggle
                objectName: "tailscale-toggle"
                size: "sm"
                Accessible.name: "Tailscale"
                checked: root.tailscale.state !== "stopped"
                enabled: !root.busy
                disabledReason: root.lockReason
                unlock: root.unlock
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.tailscale.state !== "stopped");
                    root.request(wanted ? "connect" : "disconnect", "");
                }
            }
        }
        Button {
            objectName: "tailscale-sign-in"
            visible: root.tailscale.state === "signed-out" && root.tailscale.login === "idle"
            disabledReason: root.lockReason
            text: "Sign in"
            iconName: "log-in"
            onClicked: root.request("login", "")
        }
        Row {
            visible: root.tailscale.login !== "idle"
            spacing: Theme.control.gap

            Label {
                anchors.verticalCenter: parent.verticalCenter
                role: "hint"
                text: root.tailscale.login === "opened" ? "Finish the sign-in in your browser." : "Opening the sign-in page"
            }
            RowAction {
                anchors.verticalCenter: parent.verticalCenter
                text: "Cancel"
                onClicked: root.request("cancel-login", "")
            }
        }
        Section {
            width: parent.width
            visible: root.tailscale.state === "running"
            title: "Exit node"
            description: root.tailscale.exitCount > root.tailscale.exitNodes.length
                ? "Showing " + root.tailscale.exitNodes.length + " of " + root.tailscale.exitCount + " exit nodes." : ""

            DeviceList {
                id: exitList
                objectName: "tailscale-exit-nodes"
                width: parent.width
                enabled: !root.busy
                disabledReason: root.lockReason
                rows: root.exitRows
                onActed: key => { if (key !== (root.tailscale.exit === null ? "" : root.tailscale.exit.id)) root.request("exit-node", key); }
            }
        }
        Section {
            width: parent.width
            visible: root.expanded && root.reached
            title: "This device"

            Repeater {
                model: [["Name", root.tailscale.device.name], ["Address", root.tailscale.device.address], ["Network", root.tailscale.tailnet], ["Account", root.tailscale.account]]

                Field {
                    id: deviceRow
                    required property var modelData
                    width: root.width
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
                objectName: "tailscale-accounts"
                width: parent.width
                visible: root.accountRows.length > 0
                enabled: !root.busy
                disabledReason: root.lockReason
                rows: root.accountRows
                onActed: key => { if (!root.tailscale.accounts.some(row => row.id === key && row.current)) root.request("switch", key); }
            }
            RowAction {
                visible: root.tailscale.login === "idle" && root.tailscale.state !== "signed-out"
                disabledReason: root.lockReason
                text: "Add account"
                onClicked: root.request("login", "")
            }
        }
        Section {
            width: parent.width
            visible: root.expanded && root.tailscale.peers.length > 0
            title: "Devices"
            description: root.tailscale.peerCount > root.tailscale.peers.length
                ? "Showing " + root.tailscale.peers.length + " of " + root.tailscale.peerCount + " devices." : ""

            Repeater {
                model: root.tailscale.peers

                Field {
                    id: peerRow
                    required property var modelData
                    width: root.width
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
        Field {
            width: parent.width
            visible: root.expanded && root.tailscale.state !== "missing"
            label: "Check every"
            hint: "How often VGS reads Tailscale while this section is closed."
            inline: true

            SegmentedControl {
                objectName: "tailscale-poll"
                model: root.pollChoices.map(seconds => seconds + " s")
                currentIndex: root.shell === null ? 1 : root.pollChoices.indexOf(root.shell.settings.pollSeconds)
                onActivated: index => root.answered(root.shell.configure.set("pollSeconds", root.pollChoices[index]), "VGS could not save this setting.")
            }
        }
    }
}
