import QtQuick
import qs.Commons
import qs.Ui
import "TailscaleLogic.js" as Logic

// The Tailscale flyout's main view, which the System pane also mounts
// (`expanded`). It draws the `tailscale`, `devices` and `exitNodes` values
// the service publishes and asks the service for every change through the
// plugin's own IPC; it starts no process. While it is open it holds a
// lease, which makes the service's poll fast. The setup step, Enable or
// Allow, is the `setup` status entry's action as the core's status rows
// offer it (`status.rows`), run through `status.act`. While Tailscale
// takes no change, its controls say why (`lockReason`), and the connection
// switch's unlock mark runs the same step.
//
// Rows, top to bottom: the account, a disclosure whose list switches
// accounts and ends with Add account and Sign out; this device, whose
// Copy puts its address on the clipboard through CopyText; the network
// devices, a disclosure of their addresses; and the Exit node row, which
// asks the host for the exit node chooser (`exitNodesRequested`). The
// flyout opens with the disclosures closed, the account's open while
// signed out, and the pane with both open (design VGS-1923 § 4, "Flyout
// versus section"). While the device waits for approval the flyout shows
// only the approval step, and the pane keeps the account and this device,
// since the CLI still switches, signs in and signs out there. Sign out
// asks first, in a Dialog over a Scrim drawn over `promptPane`, the
// flyout's own Pane, so the title row and the footer take no input while
// it waits; the shared ModalDialog is a layer surface, and Hyprland ends
// the flyout's popup grab when one maps (NetworkBody.qml header). With no
// `promptPane`, as in the System pane, it draws over the body.
//
// Tab moves from the connection switch through the account row, its list,
// Add account and Sign out while it is expanded, this device and its
// Copy, the network devices row and, while it is expanded, its list and
// each device's Copy, and the Exit node row. In the pane the Exit node
// section follows the network devices: the search field, or Back in a
// country's view, then each list the chooser shows; then Check every. Up
// and Down move inside a list, and Enter chooses. Nothing opens with the
// keyboard on Sign out.
FocusScope {
    id: root

    property var shell: null
    // The System pane's rows: the state line, the connection switch, the
    // exit node chooser inline and the poll setting.
    property bool expanded: false
    // The Pane the sign-out confirmation covers, null for the body, and
    // the corner its scrim follows: the body draws none.
    property Pane promptPane: null
    readonly property real promptCorner: promptPane === null ? 0 : promptPane.cornerRadius
    property string leaseId: ""
    property bool leased: false
    // The line a refused request left, "" for none.
    property string localProblem: ""
    // Whether the sign-out confirmation shows.
    property bool signingOut: false
    // The row whose address the last copy took, which reads Copied while
    // the copy confirms.
    property string copiedKey: ""
    // The exit node a change runs for, null while none does.
    property var pendingExit: null

    // The host shows the exit node chooser.
    signal exitNodesRequested()
    // A chosen exit node is in use, or was already.
    signal exitChosen()

    readonly property var values: shell === null ? ({}) : shell.status.values
    readonly property var tailscale: values.tailscale ? values.tailscale : Logic.unread()
    readonly property var devices: values.devices ? values.devices : Logic.emptySnapshot("checking").devices
    readonly property var exitNodes: values.exitNodes ? values.exitNodes : Logic.emptySnapshot("checking").exitNodes
    readonly property bool busy: tailscale.action !== ""
    readonly property bool switchable: ["running", "starting", "stopped"].indexOf(tailscale.state) !== -1
    readonly property bool reached: switchable || tailscale.state === "signed-out" || tailscale.state === "needs-approval"
    readonly property bool signedOut: tailscale.state === "signed-out"
    readonly property bool connected: tailscale.state === "running"
    readonly property bool approvalPane: expanded && tailscale.state === "needs-approval"
    readonly property var currentAccount: tailscale.accounts.find(row => row.current) || null
    readonly property bool accountShown: switchable || approvalPane || (signedOut && tailscale.accounts.length > 0)
    readonly property bool deviceShown: (switchable || approvalPane) && tailscale.device.address !== ""
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
    readonly property string stateHint: Logic.stateHint(tailscale)
    readonly property string problemText: localProblem !== "" ? localProblem : tailscale.problem
    readonly property var signOut: Logic.signOutPrompt(tailscale.tailnet)
    readonly property var pollChoices: [10, 30, 60]
    // The connection switch while it can be used, else the body, from
    // which Tab reaches the setup step: no view opens on a step that
    // changes the system (design-system.md § Keyboard), nor on a locked
    // switch, nor on Sign out.
    readonly property Item initialFocus: connectField.visible && toggle.enabled && root.lockReason === "" ? toggle : root
    readonly property bool prompting: signingOut && !signedOut && reached

    implicitHeight: Math.max(content.implicitHeight, prompting && promptPane === null ? prompt.implicitHeight + 2 * Theme.dialog.margin : 0)

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
        // The flyout opens with both disclosures closed, the account's open
        // while signed out, where it lists the accounts to switch to; the
        // pane opens both.
        accountRow.expanded = signedOut || expanded;
        devicesRow.expanded = expanded;
        signingOut = false;
        localProblem = "";
        if (expanded) suggest();
    }
    function close() {
        signingOut = false;
        if (!leased || shell === null) return;
        shell.ipc.call("lease", JSON.stringify({ id: leaseId, open: false }));
        leased = false;
    }
    Component.onDestruction: close()

    function answered(reply) {
        localProblem = Logic.replyText(reply);
        if (reply !== "ok" && reply !== "busy") console.warn("tailscale: " + reply);
        return reply;
    }
    function request(kind, id) {
        return answered(shell.ipc.call("action", JSON.stringify({ kind: kind, id: id })));
    }
    function runSetup() {
        const reply = shell.status.act("setup");
        localProblem = reply === "ok" ? "" : "VGS could not open the setup step.";
        if (reply !== "ok") console.warn("tailscale: setup " + reply);
        return reply;
    }
    // Asks the service to read the suggested exit node; the chooser shows
    // Recommended once it is read.
    function suggest() {
        if (shell === null) return;
        const reply = shell.ipc.call("suggest", "");
        if (reply !== "ok" && reply !== "busy") console.info("tailscale: " + reply);
    }
    function copy(key, address) {
        copiedKey = key;
        copier.copy(address);
    }
    function chooseExit(id) {
        if (id === (tailscale.exit === null ? "" : tailscale.exit.id)) {
            exitChosen();
            return;
        }
        if (request("exit-node", id) === "ok") pendingExit = id;
    }
    onBusyChanged: {
        if (busy || pendingExit === null) return;
        pendingExit = null;
        if (tailscale.problem === "") exitChosen();
    }
    // Gives the keyboard to the Exit node row; answers false while the row
    // is hidden. A hidden item keeps the keyboard, and a focus scope hands
    // its keyboard to the child that held its focus last, hidden or not
    // (a qmltestrunner run, Qt 6.11, 2026-10-20), so a hidden row first
    // gives up its place, and the body then takes the keyboard itself.
    function focusExitRow() {
        if (exitRow.visible) {
            exitRow.forceActiveFocus(Qt.TabFocusReason);
            return true;
        }
        exitRow.focus = false;
        return false;
    }
    // Tailscale leaving the running state ends every choice: the pane's
    // inline chooser hides, starts over, and hands the keyboard it held to
    // where the pane opens.
    onConnectedChanged: {
        if (connected || !expanded) return;
        const parts = [inlineChooser, inlineSearch, inlineBack];
        const held = parts.some(part => part.activeFocus);
        inlineChooser.country = "";
        inlineSearch.text = "";
        if (!held) return;
        for (const part of parts) part.focus = false;
        initialFocus.forceActiveFocus(Qt.TabFocusReason);
    }

    function askSignOut() {
        signingOut = true;
        Qt.callLater(() => { if (root.prompting) prompt.takeFocus(); });
    }
    function endSignOut(confirmed) {
        signingOut = false;
        if (confirmed) {
            request("logout", "");
            root.forceActiveFocus();
        } else {
            signOutAction.forceActiveFocus(Qt.TabFocusReason);
        }
    }

    CopyText { id: copier }

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        Label {
            objectName: "tailscale-state"
            width: parent.width
            role: "body"
            textFormat: Text.PlainText
            visible: root.expanded && root.tailscale.state !== "missing"
            text: root.tailscale.text
            wrapMode: Text.Wrap
        }
        Label {
            objectName: "tailscale-problem"
            width: parent.width
            visible: text !== ""
            role: "hint"
            color: Theme.color.danger
            text: root.problemText
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
        Label {
            objectName: "tailscale-state-hint"
            width: parent.width
            visible: text !== "" && !(root.signedOut && root.tailscale.login !== "idle")
            role: "hint"
            textFormat: Text.PlainText
            text: root.stateHint
            wrapMode: Text.Wrap
        }
        Button {
            objectName: "tailscale-sign-in"
            visible: root.signedOut && root.tailscale.login === "idle"
            disabledReason: root.lockReason
            variant: "primary"
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
        RowAction {
            objectName: "tailscale-approval-console"
            visible: root.tailscale.state === "needs-approval"
            text: "Open admin console"
            onClicked: root.request("admin-console", "")
        }
        RowAction {
            objectName: "tailscale-try-again"
            visible: root.tailscale.state === "unavailable"
            text: "Try again"
            onClicked: root.shell.ipc.call("refresh", "")
        }

        // The rows and their one cursor, beside the column that holds
        // them: a positioner would lay the plate out as a row.
        Item {
            width: parent.width
            height: rowColumn.implicitHeight
            visible: root.accountShown || root.deviceShown

            ListCursor { id: rowCursor }

            Column {
                id: rowColumn
                width: parent.width

                Disclosure {
                    id: accountRow
                    objectName: "tailscale-account"
                    width: parent.width
                    visible: root.accountShown
                    cursor: rowCursor
                    iconName: "user"
                    text: root.signedOut ? "Accounts" : root.tailscale.account !== "" ? root.tailscale.account
                        : root.currentAccount !== null ? root.currentAccount.account : "Account"
                    secondary: root.signedOut ? "Not signed in" : root.tailscale.tailnet

                    DeviceList {
                        objectName: "tailscale-accounts"
                        width: parent.width
                        visible: rows.length > 0
                        disabledReason: root.lockReason
                        rows: Logic.accountRows(root.tailscale.accounts)
                        onActed: key => { if (!root.tailscale.accounts.some(row => row.id === key && row.current)) root.request("switch", key); }
                    }
                    RowActions {
                        RowAction {
                            objectName: "tailscale-add-account"
                            visible: root.tailscale.login === "idle"
                            disabledReason: root.lockReason
                            text: "Add account"
                            onClicked: root.request("login", "")
                        }
                        RowAction {
                            id: signOutAction
                            objectName: "tailscale-sign-out"
                            visible: !root.signedOut
                            disabledReason: root.lockReason
                            text: "Sign out"
                            tone: "danger"
                            markName: "log-out"
                            onClicked: root.askSignOut()
                        }
                    }
                }
                DeviceList {
                    objectName: "tailscale-this-device"
                    width: parent.width
                    visible: root.deviceShown
                    rows: [{ key: "self", text: root.tailscale.device.name, secondary: "This device · " + root.tailscale.device.address, iconName: "laptop" }]
                    actionOf: row => ({ text: copier.confirming && root.copiedKey === "self" ? "Copied" : "Copy" })
                    onActed: key => root.copy("self", root.tailscale.device.address)
                }
                Disclosure {
                    id: devicesRow
                    objectName: "tailscale-network-devices"
                    width: parent.width
                    visible: root.connected
                    expandable: root.devices.rows.length > 0
                    cursor: rowCursor
                    iconName: "network"
                    text: "Network devices"
                    secondary: Logic.devicesLine(root.devices)

                    DeviceList {
                        id: deviceList
                        objectName: "tailscale-devices"
                        width: parent.width
                        rows: Logic.deviceRows(root.devices)
                        actionOf: row => row.address === "" ? null : ({ text: copier.confirming && root.copiedKey === row.key ? "Copied" : "Copy" })
                        onActed: key => {
                            const row = deviceList.rows.find(entry => entry.key === key);
                            if (row !== undefined && row.address !== "") root.copy(key, row.address);
                        }
                    }
                    Row {
                        visible: root.devices.count > root.devices.rows.length
                        spacing: Theme.stack.inline

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            role: "hint"
                            text: "Showing " + root.devices.rows.length + " of " + root.devices.count + " devices."
                        }
                        InfoButton {
                            anchors.verticalCenter: parent.verticalCenter
                            title: "Network devices"
                            info: "The list shows the first " + root.devices.rows.length + " devices, so it opens quickly. The admin console on the Tailscale website lists every device."
                        }
                    }
                }
                // focus-indicator: ListItem draws its FocusRing for the row
                ListItem {
                    id: exitRow
                    objectName: "tailscale-exit-row"
                    width: parent.width
                    visible: root.connected && !root.expanded
                    focusPolicy: Qt.StrongFocus
                    cursor: rowCursor
                    iconName: root.tailscale.exit === null ? "globe" : "earth-lock"
                    text: "Exit node"
                    secondary: Logic.exitLine(root.tailscale)
                    onClicked: root.exitNodesRequested()
                    Keys.onReturnPressed: root.exitNodesRequested()
                    Keys.onEnterPressed: root.exitNodesRequested()
                    Keys.onSpacePressed: root.exitNodesRequested()
                    trailing: [
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "chevron-right"
                            size: Theme.icon.size.md
                            color: Theme.color.textMuted
                        }
                    ]
                }
            }
        }

        // The System pane holds the chooser inline, its country view under
        // a Back row in place of the search field.
        Section {
            width: parent.width
            visible: root.expanded && root.connected
            title: "Exit node"
            rowSpacing: Theme.stack.group

            Row {
                visible: inlineChooser.country !== ""
                spacing: Theme.control.gap

                IconButton {
                    id: inlineBack
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "chevron-left"
                    label: "Back"
                    onClicked: inlineChooser.closeCountry()
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "h3"
                    text: inlineChooser.countryName
                }
            }
            TextField {
                id: inlineSearch
                width: parent.width
                visible: inlineChooser.country === ""
                leadingIcon: "search"
                placeholderText: "Search countries, cities and devices"
                Keys.onDownPressed: inlineChooser.focusFirst()
            }
            ExitNodes {
                id: inlineChooser
                width: parent.width
                tailscale: root.tailscale
                exitNodes: root.exitNodes
                searchField: inlineSearch
                pending: root.busy ? root.pendingExit : null
                disabledReason: root.lockReason
                onChose: id => root.chooseExit(id)
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
                onActivated: index => {
                    const reply = root.shell.configure.set("pollSeconds", root.pollChoices[index]);
                    root.localProblem = reply === "ok" ? "" : "VGS could not save this setting.";
                }
            }
        }
    }

    Scrim {
        visible: root.prompting
        parent: root.promptPane === null ? root : root.promptPane
        radius: root.promptCorner
        onClicked: prompt.takeFocus()
    }
    Dialog {
        id: prompt
        objectName: "tailscale-sign-out-prompt"
        parent: root.promptPane === null ? root : root.promptPane
        z: 1
        visible: root.prompting
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width - 2 * Theme.dialog.margin)
        title: root.signOut.title
        message: root.signOut.message
        actions: [{ label: "Cancel", role: "cancel", focused: true }, { label: "Sign out", role: "accept", variant: "danger" }]
        onAccepted: root.endSignOut(true)
        onRejected: root.endSignOut(false)
    }
}
