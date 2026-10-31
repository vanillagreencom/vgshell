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
// takes no change, its controls say why (`lockReason`, and `accountReason`
// for Add account and Sign in), and the connection switch's unlock mark
// runs the same step.
//
// Accounts share one card in both views. Network devices use a flyout
// disclosure and an open section in the pane. Its device fields copy
// through the same CopyText as the lists. This device and each network
// device copy their address through a copy icon, and a network device that
// runs an ssh server (TailscaleLogic.sshCapable) has Connect in terminal
// before it, which opens the user's terminal on ssh to its DNS name through
// `shell.tui.ssh`; the core builds the command, and this view hands it the
// device's name and DNS name alone. While ssh is missing, Connect raises
// its requirement notice instead. The pane expands exit countries in place
// and ends with Updates. Each list is one Tab stop; arrows move inside it
// and Shift+F10 opens a device's menu, which holds its icon actions. Sign
// out asks first and opens with Cancel focused, in the flyout's Pane or
// beside the pane's account actions inside its scrolling body.
FocusScope {
    id: root

    property var shell: null
    // The System pane uses open sections and an inline exit node chooser.
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
    readonly property bool accountShown: reached
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
    // The same for Add account and for a saved account's Sign in.
    readonly property string addReason: Logic.accountReason(tailscale, setupAction === null ? "" : setupAction.label, "add-account")
    readonly property string signInReason: Logic.accountReason(tailscale, setupAction === null ? "" : setupAction.label, "sign-in")
    readonly property var unlock: setupAction === null ? null : ({ label: setupAction.label, run: () => root.runSetup() })
    readonly property var stateHint: Logic.stateHint(tailscale, setupAction === null ? "" : setupAction.label)
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
        // The pane opens its network device list.
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
    // Whether row KEY's copy reads Copied now.
    function copied(key) { return copier.confirming && copiedKey === key; }
    // A network device ROW's icon actions, as DeviceList.iconActionsOf
    // takes them: Connect in terminal first, then copy, so copy keeps the
    // row's last place on every row.
    function deviceIcons(row) {
        const icons = row.connects ? [{ key: "connect", iconName: "terminal", label: "Connect in terminal" }] : [];
        return row.address === "" ? icons : icons.concat([{ key: "copy", iconName: copied(row.key) ? "check" : "copy", label: copied(row.key) ? "Copied" : "Copy" }]);
    }
    // Opens the user's terminal on ssh to network device KEY. A refusal,
    // and a launcher that found no terminal, leave the problem line.
    function connect(key) {
        const row = root.devices.rows.find(peer => peer.id === key);
        if (row === undefined || !row.connects) return;
        if (shell.requirements.missing.indexOf("ssh") !== -1) {
            const offered = shell.requirements.offer(["ssh"]);
            if (offered !== "ok") console.warn("tailscale: offer ssh " + offered);
            return;
        }
        const reply = shell.tui.ssh(row.name, row.dnsName, end => root.connectEnded(end));
        localProblem = reply === "ok" ? "" : Reply.line(reply);
        if (reply !== "ok") console.warn("tailscale: connect " + reply);
    }
    function connectEnded(end) {
        if (end.reason === null) return;
        console.warn("tailscale: connect reason=" + end.reason);
        localProblem = end.reason === "launcher-missing" ? Reply.line("refused: tui=core/ssh reason=launcher-missing") : "VGS could not open your terminal.";
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
        const parts = [inlineChooser, inlineSearch];
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

    Component {
        id: networkContents
        Column {
            width: parent.width
            spacing: Theme.stack.group
            DeviceList {
                id: deviceList
                objectName: "tailscale-devices"
                width: parent.width
                rows: Logic.deviceRows(root.devices)
                iconActionsOf: row => root.deviceIcons(row)
                menuOf: row => root.expanded && row.dnsName !== "" ? [{ key: "copy-dns", text: "Copy DNS name", iconName: "copy" }] : []
                onChose: (key, entry) => {
                    const row = deviceList.rows.find(item => item.key === key);
                    if (row === undefined) return;
                    if (entry === "connect") root.connect(key);
                    else if (entry === "copy" && row.address !== "") root.copy(key, row.address);
                    else if (entry === "copy-dns" && row.dnsName !== "") root.copy(key, row.dnsName);
                }
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
    }

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        Card {
            objectName: "tailscale-accounts-card"
            visible: root.accountShown
            Row {
                width: parent.width
                spacing: Theme.stack.inline
                SectionHeader {
                    objectName: "tailscale-accounts-header"
                    width: parent.width - accountButtons.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Accounts"
                    bottomPadding: 0
                }
                Row {
                    id: accountButtons
                    spacing: Theme.stack.inline
                    IconButton {
                        objectName: "tailscale-add-account"
                        iconName: "plus"
                        label: "Add account"
                        size: "sm"
                        disabledReason: root.addReason
                        onClicked: root.request("add-account", "")
                    }
                    IconButton {
                        id: signOutAction
                        objectName: "tailscale-sign-out"
                        visible: !root.signedOut
                        iconName: "log-out"
                        label: "Sign out"
                        tone: "danger"
                        size: "sm"
                        disabledReason: root.lockReason
                        onClicked: root.askSignOut()
                    }
                }
            }
            // The state's why stands before the rows it explains.
            Label {
                objectName: "tailscale-signed-out-hint"
                width: parent.width
                visible: root.signedOut && root.tailscale.login === "idle"
                role: "hint"
                textFormat: Text.PlainText
                text: root.stateHint.text
                wrapMode: Text.Wrap
            }
            DeviceList {
                objectName: "tailscale-accounts"
                width: parent.width
                visible: rows.length > 0
                disabledReason: root.signedOut ? root.signInReason : root.lockReason
                rows: Logic.accountRows(root.tailscale)
                // The row of an unread list is the status account, which
                // no request names.
                actionOf: row => root.signedOut && root.tailscale.accountsRead ? ({ text: "Sign in" }) : null
                onActed: key => {
                    if (!root.tailscale.accountsRead) return;
                    if (root.signedOut) root.request("sign-in", key);
                    else if (!root.tailscale.accounts.some(row => row.id === key && row.current)) root.request("switch", key);
                }
            }
            Button {
                objectName: "tailscale-sign-in"
                visible: root.signedOut && root.tailscale.accountsRead && root.tailscale.accounts.length === 0 && root.tailscale.login === "idle"
                disabledReason: root.addReason
                variant: "primary"
                text: "Sign in"
                iconName: "log-in"
                onClicked: root.request("add-account", "")
            }
        }

        Field {
            id: connectField
            objectName: "tailscale-connection-section"
            width: parent.width
            visible: root.expanded && (root.switchable || root.tailscale.state === "service-off")
            label: "Tailscale"
            inline: true

            Switch {
                id: toggle
                objectName: "tailscale-toggle"
                size: "sm"
                Accessible.name: "Tailscale"
                checked: root.tailscale.state === "running" || root.tailscale.state === "starting"
                enabled: !root.busy
                disabledReason: root.lockReason
                unlock: root.unlock
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.tailscale.state === "running" || root.tailscale.state === "starting");
                    root.request(wanted ? "connect" : "disconnect", "");
                }
            }
        }
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

        Label {
            objectName: "tailscale-state-hint"
            width: parent.width
            visible: text !== "" && !root.signedOut
            role: "hint"
            textFormat: Text.PlainText
            text: root.stateHint.text
            wrapMode: Text.Wrap
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

        EmptyState {
            objectName: "tailscale-install"
            width: parent.width
            visible: root.expanded && root.tailscale.state === "missing"
            iconName: "route-off"
            text: "Tailscale is not installed."
            actionText: "Install Tailscale"
            onActivated: root.shell.requirements.offer(["tailscale"])
        }
        Item {
            width: parent.width
            height: rowColumn.implicitHeight
            visible: !root.expanded && (root.deviceShown || root.connected)
            ListCursor { id: rowCursor }
            Column {
                id: rowColumn
                width: parent.width
                DeviceRow {
                    objectName: "tailscale-this-device"
                    width: parent.width
                    visible: root.deviceShown
                    cursor: rowCursor
                    text: root.tailscale.device.name
                    secondary: "This device · " + root.tailscale.device.address
                    iconName: "laptop"
                    onClicked: root.copy("self", root.tailscale.device.address)
                    // keyboard-path: Enter, Return and Space on the row copy, as its click does
                    actions: IconButton {
                        objectName: "tailscale-self-copy"
                        anchors.verticalCenter: parent.verticalCenter
                        size: "sm"
                        focusPolicy: Qt.NoFocus
                        iconName: root.copied("self") ? "check" : "copy"
                        label: root.copied("self") ? "Copied" : "Copy"
                        onClicked: root.copy("self", root.tailscale.device.address)
                    }
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
                    Loader {
                        width: parent.width
                        active: !root.expanded
                        sourceComponent: networkContents
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
                    trailing: [Icon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-right"; size: Theme.icon.size.md; color: Theme.color.textMuted }]
                }
            }
        }
        Section {
            objectName: "tailscale-device-section"
            visible: root.expanded && root.deviceShown
            title: "This device"
            Field {
                width: parent.width
                label: "Name"
                inline: true
                Label { text: root.tailscale.device.name; role: "body" }
            }
            Field {
                width: parent.width
                label: "Tailscale address"
                inline: true
                Row {
                    spacing: Theme.stack.inline
                    Label { anchors.verticalCenter: parent.verticalCenter; text: root.tailscale.device.address; role: "body" }
                    RowAction {
                        objectName: "tailscale-self-address"
                        text: copier.confirming && root.copiedKey === "self" ? "Copied" : "Copy"
                        onClicked: root.copy("self", root.tailscale.device.address)
                    }
                }
            }
            Field {
                width: parent.width
                label: "DNS name"
                inline: true
                visible: root.tailscale.device.dnsName !== ""
                Row {
                    spacing: Theme.stack.inline
                    Label { anchors.verticalCenter: parent.verticalCenter; text: root.tailscale.device.dnsName; role: "body" }
                    RowAction {
                        objectName: "tailscale-self-dns"
                        text: copier.confirming && root.copiedKey === "self-dns" ? "Copied" : "Copy"
                        onClicked: root.copy("self-dns", root.tailscale.device.dnsName)
                    }
                }
            }
            Field {
                width: parent.width
                label: "Network"
                inline: true
                Label { text: root.tailscale.tailnet; role: "body" }
            }
        }
        Section {
            objectName: "tailscale-exit-section"
            visible: root.expanded && root.connected
            title: "Exit node"
            rowSpacing: Theme.stack.group
            TextField {
                id: inlineSearch
                objectName: "tailscale-inline-search"
                width: parent.width
                leadingIcon: "search"
                placeholderText: "Search countries, cities and devices"
                Keys.onDownPressed: inlineChooser.focusFirst()
            }
            ExitNodes {
                id: inlineChooser
                objectName: "tailscale-exit-nodes"
                width: parent.width
                inlineCountries: true
                tailscale: root.tailscale
                exitNodes: root.exitNodes
                searchField: inlineSearch
                pending: root.busy ? root.pendingExit : null
                disabledReason: root.lockReason
                onChose: id => root.chooseExit(id)
            }
        }
        Section {
            objectName: "tailscale-network-section"
            visible: root.expanded && root.connected
            title: "Network devices"
            Loader {
                width: parent.width
                active: root.expanded
                sourceComponent: networkContents
            }
        }
        Section {
            objectName: "tailscale-admin-section"
            visible: root.expanded && root.tailscale.state !== "missing"
            title: "Admin console"
            rowSpacing: Theme.stack.group
            Label {
                width: parent.width
                role: "body"
                text: "Manage users, devices and access" + (root.tailscale.tailnet === "" ? "" : " for " + root.tailscale.tailnet) + " on the Tailscale website."
                wrapMode: Text.Wrap
            }
            RowAction {
                objectName: "tailscale-admin-console"
                text: "Open admin console"
                onClicked: root.request("admin-console", "")
            }
        }
        Section {
            objectName: "tailscale-updates-section"
            visible: root.expanded && root.tailscale.state !== "missing"
            title: "Updates"
            Field {
                width: parent.width
                visible: root.expanded && root.tailscale.state !== "missing"
                label: "Check every"
                hint: "How often VGS reads Tailscale while its flyout and this section are closed"
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
        anchors.horizontalCenter: parent.horizontalCenter
        // The pane body scrolls and can be much taller than its window.
        // Keep the question beside Sign out, whose keyboard focus already
        // placed it in view, rather than at the body's offscreen centre.
        readonly property real questionY: {
            return root.expanded ? signOutAction.mapToItem(root, 0, signOutAction.height / 2).y : parent.height / 2;
        }
        y: Math.max(0, Math.min(parent.height - height, questionY - height / 2))
        width: Math.min(implicitWidth, parent.width - 2 * Theme.dialog.margin)
        title: root.signOut.title
        message: root.signOut.message
        actions: [{ label: "Cancel", role: "cancel", focused: true }, { label: "Sign out", role: "accept", variant: "danger" }]
        onAccepted: root.endSignOut(true)
        onRejected: root.endSignOut(false)
    }
}
