import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "VpnLogic.js" as Logic

// The profile list the flyout and System Settings share, from the
// `profiles` value the service publishes. The flyout (`expanded` false)
// draws the problem line, the profiles and Import a VPN file; it draws no
// empty or NetworkManager-absent state, since the bar icon that opens it
// hides in both. System Settings adds the Profiles heading with what VGS
// can connect, Remove profile in each expanded profile, the import hint,
// the empty and NetworkManager-absent states, and the Updates section
// while NetworkManager answers.
//
// The remove confirmation is a Dialog over a Scrim in the body's own
// window, as vgs.network's password prompt is (NetworkBody.qml header): a
// ModalDialog layer surface would take the keyboard from the window. The
// page is disabled while it shows, so Tab cannot reach the list behind
// the scrim. After Cancel the focus goes back to Remove profile; after the
// profile leaves the list, to the profile now at its place, else the one
// before it, else Import a VPN file.
//
// The password prompt (ConnectPrompt) is a Dialog over a Scrim too, drawn
// over `promptPane` when the host names one: the flyout names its own
// Pane, so the Scrim also covers its footer, which lies outside the body,
// and the dialog centres in it. System Settings names none, and the prompt
// stands beside its profile in the body, as the remove confirmation does.
// A press on the switch of a profile that reads Needs password opens it,
// and so does the end of a connect this body started, the prompt's own
// included, that leaves its profile at Needs password; after a connect
// with a password, it shows its retry line. After Cancel, or a submit,
// the focus goes back to the profile's switch.
FocusScope {
    id: root
    property var shell: null
    property bool expanded: false
    property string leaseId: ""
    property bool leased: false
    property string localProblem: ""
    readonly property var profiles: shell === null || !shell.status.values.profiles
        ? Logic.compose(Logic.emptyProfiles("reading"), {}, {}, {}, null, "") : shell.status.values.profiles
    readonly property var profileRows: profiles.rows
    readonly property bool answering: profiles.state === "available"
    readonly property bool listed: answering && profileRows.length > 0
    readonly property var pollChoices: [10, 30, 60]
    readonly property Item list: expanded ? paneList.item : flyoutList.item
    readonly property Item initialFocus: list !== null && list.rowAt(0) !== null ? list.rowAt(0).focusItem : root
    // The profile the confirmation asks about, and the one whose removal
    // runs with the place it stood at.
    property var confirmTarget: null
    property string removingUuid: ""
    property int removingIndex: -1
    readonly property bool confirming: confirmTarget !== null && content.visible
    // The profile the password prompt asks about, { uuid, name }, and the
    // connect this body started, followed until it ends: `watchSeen` holds
    // once the published state shows it connecting.
    property var promptTarget: null
    readonly property bool prompting: promptTarget !== null && content.visible
    readonly property var promptRow: promptTarget === null ? null : profileRows.find(row => row.uuid === promptTarget.uuid) || null
    property string watchUuid: ""
    property bool watchSeen: false
    property Pane promptPane: null
    readonly property Item promptHost: promptPane === null ? root : promptPane
    // The corner the scrim rounds to: the hosting Pane's container corner,
    // or none over the body, a square part of its page.
    readonly property real promptCorner: promptPane === null ? 0 : promptPane.cornerRadius

    implicitHeight: Math.max(content.implicitHeight, confirming ? confirm.implicitHeight + 2 * Theme.dialog.margin : 0,
        prompting ? prompt.implicitHeight + 2 * Theme.dialog.margin : 0)

    // Qt starts Tab traversal at the window's first stop from a body
    // that is not itself a Tab stop; move from this section explicitly.
    Keys.onTabPressed: event => {
        nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason);
        event.accepted = true;
    }
    function open() {
        if (leaseId === "") leaseId = String(root);
        if (shell !== null && !leased) leased = shell.ipc.call("lease", JSON.stringify({ id: leaseId, open: true })) === "ok";
    }
    function close() {
        confirmTarget = null;
        prompt.clear();
        promptTarget = null;
        watchUuid = "";
        if (!leased || shell === null) return;
        shell.ipc.call("lease", JSON.stringify({ id: leaseId, open: false }));
        leased = false;
    }
    Component.onDestruction: close()

    function answered(reply, refusal) {
        localProblem = reply === "ok" || reply === "satisfied" ? "" : reply === "busy" ? "A VPN change is still in progress." : refusal;
        if (reply !== "ok" && reply !== "satisfied" && reply !== "busy") console.warn("vpn: " + reply);
        return reply;
    }
    function act(kind, uuid, refusal) {
        return answered(shell.ipc.call("action", JSON.stringify({ kind: kind, id: uuid })), refusal);
    }
    // A switch press: a profile that reads Needs password asks for it,
    // and a connect is followed so its end can ask.
    function toggle(row, wanted) {
        if (wanted && Logic.rowView(row, profiles).key === "needs-password") {
            askPassword(row);
            return;
        }
        // Set before the call: the service publishes the change in flight
        // and PluginStatus.set records it at once, so the body reads it
        // connecting before the reply returns.
        if (wanted) follow(row.uuid);
        if (act(wanted ? "profile-up" : "profile-down", row.uuid, "This VPN profile cannot change now.") !== "ok") watchUuid = "";
    }
    function follow(uuid) {
        watchUuid = uuid;
        watchSeen = false;
    }

    // An open prompt keeps its profile: retargeting it would hand the typed
    // password to another server. The other profile still reads Needs
    // password, and its switch asks once this prompt closes.
    function askPassword(row) {
        if (confirming || promptTarget !== null && promptTarget.uuid !== row.uuid) return;
        localProblem = "";
        promptTarget = { uuid: row.uuid, name: row.name };
        Qt.callLater(() => { if (root.prompting) prompt.takeFocus(); });
    }
    function closePrompt(uuid) {
        prompt.clear();
        promptTarget = null;
        Qt.callLater(() => root.focusSwitch(uuid));
    }
    function passwordAnswered(uuid, reply) {
        if (answered(reply, "VGS could not connect this profile.") !== "ok") watchUuid = "";
        closePrompt(uuid);
    }
    function focusSwitch(uuid) {
        const row = list === null ? null : list.rowFor(uuid);
        if (row !== null) row.switchAction.forceActiveFocus(Qt.TabFocusReason);
    }
    // An opened profile asks for its address; the row shows no reply.
    function readAddress(uuid) {
        const reply = shell.ipc.call("action", JSON.stringify({ kind: "profile-details", id: uuid }));
        if (reply !== "ok") console.warn("vpn: " + reply);
    }
    function importFile() {
        answered(shell.ipc.call("import", ""), "VGS could not open the import window.");
    }

    function askRemove(row) {
        localProblem = "";
        confirmTarget = { uuid: row.uuid, name: row.name };
        Qt.callLater(() => { if (root.confirming) confirm.takeFocus(); });
    }
    function cancelRemove() {
        const uuid = confirmTarget === null ? "" : confirmTarget.uuid;
        confirmTarget = null;
        Qt.callLater(() => root.focusRemove(uuid));
    }
    function acceptRemove() {
        const target = confirmTarget;
        confirmTarget = null;
        if (act("profile-remove", target.uuid, "VGS could not remove this profile.") === "ok") {
            removingUuid = target.uuid;
            removingIndex = profileRows.findIndex(row => row.uuid === target.uuid);
        }
        Qt.callLater(() => root.focusRemove(target.uuid));
    }
    function focusRemove(uuid) {
        const row = list === null ? null : list.rowFor(uuid);
        if (row !== null) row.removeAction.forceActiveFocus(Qt.TabFocusReason);
    }
    // The removed profile left the list: focus its neighbour.
    function removed() {
        const index = removingIndex;
        removingUuid = "";
        removingIndex = -1;
        Qt.callLater(() => {
            const next = root.list === null ? null : root.list.rowAt(Math.min(index, root.profileRows.length - 1));
            if (next !== null) next.focusItem.forceActiveFocus(Qt.TabFocusReason);
            // The empty state's own action is the first Tab stop after it
            // (tst_vpn_views.qml test_last_removal_focuses_import, 2026-10-20).
            else if (empty.visible) empty.nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason);
            else importAction.forceActiveFocus(Qt.TabFocusReason);
        });
    }
    onProfilesChanged: {
        followed();
        // A prompt whose profile left the list, or no longer reads Needs
        // password, has nothing left to ask.
        if (promptTarget !== null) {
            const row = profiles.rows.find(candidate => candidate.uuid === promptTarget.uuid);
            if (row === undefined || Logic.rowView(row, profiles).key !== "needs-password") closePrompt(promptTarget.uuid);
        }
        if (removingUuid === "") return;
        // `profileRows` still held the old rows in this handler
        // (tst_vpn_views.qml test_removal_moves_the_focus, 2026-10-20).
        if (!profiles.rows.some(row => row.uuid === removingUuid)) removed();
        // A removal that failed leaves its problem line and the profile.
        else if (profiles.action === null && profiles.problem !== "") { removingUuid = ""; removingIndex = -1; }
    }

    // The followed connect: seen connecting, then ended. An end at Needs
    // password opens the prompt.
    function followed() {
        if (watchUuid === "") return;
        const row = profiles.rows.find(candidate => candidate.uuid === watchUuid);
        if (row === undefined) {
            watchUuid = "";
            return;
        }
        if (Logic.motion(row, profiles.action) === "connecting") {
            watchSeen = true;
            return;
        }
        if (!watchSeen) return;
        watchUuid = "";
        if (Logic.rowView(row, profiles).key === "needs-password") askPassword(row);
    }

    Component {
        id: profileList
        ProfileList {}
    }
    component ProfileList: Item {
        id: listRoot
        width: parent.width
        implicitHeight: rows.implicitHeight
        function rowAt(index) { return index < 0 ? null : repeater.itemAt(index); }
        function rowFor(uuid) {
            for (let i = 0; i < repeater.count; i++) if (repeater.itemAt(i).modelData.uuid === uuid) return repeater.itemAt(i);
            return null;
        }
        Connections {
            target: root
            function onProfileRowsChanged() { profileCursor.rebuilt(); }
        }
        // Beside the rows' column: a positioner would lay the plate out
        // as a row.
        ListCursor { id: profileCursor }
        Column {
            id: rows
            width: listRoot.width
            Repeater {
                id: repeater
                model: ScriptModel { values: root.profileRows; objectProp: "uuid" }
                ProfileRow {
                    id: profileRow
                    width: rows.width
                    cursor: profileCursor
                    profiles: root.profiles
                    removable: root.expanded
                    onDetailsOpened: root.readAddress(modelData.uuid)
                    onToggleRequested: wanted => root.toggle(modelData, wanted)
                    onRemoveRequested: root.askRemove(modelData)
                }
            }
        }
    }

    Column {
        id: content
        width: root.width
        enabled: !root.confirming && !root.prompting
        spacing: Theme.stack.group
        Label {
            objectName: "vpn-problem"
            width: parent.width
            visible: text !== ""
            role: "hint"
            color: Theme.color.danger
            textFormat: Text.PlainText
            text: root.localProblem !== "" ? root.localProblem : root.profiles.problem
            wrapMode: Text.Wrap
        }
        EmptyState {
            id: empty
            objectName: "vpn-empty"
            width: parent.width
            visible: root.expanded && root.profiles.state !== "reading" && !root.listed
            iconName: root.answering ? "shield" : "shield-off"
            text: root.profiles.state === "missing" ? "NetworkManager is not installed, so VGS cannot show VPN profiles."
                : root.profiles.state === "not-running" ? "NetworkManager is not running, so VGS cannot show VPN profiles."
                : root.profiles.state === "no-answer" ? "NetworkManager did not answer, so VGS cannot show VPN profiles."
                : "No VPN profiles yet. Import a WireGuard or OpenVPN file to add one. The VPN icon shows in the bar when you have a profile."
            actionText: root.answering ? "Import a VPN file" : ""
            onActivated: root.importFile()
        }
        Section {
            objectName: "vpn-profiles"
            width: parent.width
            visible: root.expanded && root.listed
            title: "Profiles"
            infoTitle: "What VGS can connect"
            info: "Import: WireGuard (.conf) files, and OpenVPN (.ovpn) files, which need NetworkManager's OpenVPN plugin.\n\n"
                + "Connect and disconnect:\n• every WireGuard profile whose private key NetworkManager holds\n"
                + "• every VPN profile other than OpenConnect whose NetworkManager plugin is installed and whose passwords NetworkManager holds\n"
                + "• an OpenVPN, L2TP, PPTP, SSTP or Fortinet SSL profile that asks for its password: VGS asks you for it and does not keep it\n\n"
                + "Details: the type, the server and, while connected, the address.\n\n"
                + "Remove: any profile, after you confirm. NetworkManager deletes the profile with the passwords and keys saved in it. "
                + "Key and certificate files that the profile uses stay on this computer.\n\n"
                + "Not supported: OpenConnect profiles (Cisco AnyConnect, GlobalProtect, Pulse or Ivanti), a VPN that signs in through a web page, "
                + "a profile that asks for a secret other than its password or a one-time code when it connects, a smart card or certificate passphrase, "
                + "a profile of any other type that asks for a secret when it connects, and making or editing a profile by hand. "
                + "These profiles still show with their details and Remove profile. The switch of an OpenConnect profile says why it cannot connect; "
                + "the switch of another such profile says why after a connect fails."
            description: root.profiles.count > root.profileRows.length
                ? "Showing " + root.profileRows.length + " of " + root.profiles.count + " profiles." : ""
            Loader {
                id: paneList
                width: parent.width
                active: root.expanded
                sourceComponent: profileList
            }
        }
        Loader {
            id: flyoutList
            width: parent.width
            visible: root.listed
            active: !root.expanded
            sourceComponent: profileList
        }
        Column {
            width: parent.width
            visible: root.listed
            spacing: Theme.field.gap
            RowAction {
                id: importAction
                objectName: "vpn-import"
                text: "Import a VPN file"
                onClicked: root.importFile()
            }
            Label {
                objectName: "vpn-import-hint"
                width: parent.width
                visible: root.expanded
                role: "hint"
                text: "Imports WireGuard (.conf) and OpenVPN (.ovpn) files"
                wrapMode: Text.Wrap
            }
        }
        Section {
            objectName: "vpn-updates"
            width: parent.width
            visible: root.expanded && root.answering
            title: "Updates"
            Field {
                width: parent.width
                label: "Check every"
                hint: "How often VGS reads your VPN profiles while its flyout and this section are closed"
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

    // The scrim takes each press, hover and wheel over the body; a press on
    // it keeps the question open. The dialog stands beside the profile it
    // asks about, inside the body.
    Scrim {
        visible: root.confirming
        onClicked: confirm.takeFocus()
    }
    Dialog {
        id: confirm
        objectName: "vpn-remove-confirm"
        z: 1
        visible: root.confirming
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(implicitWidth, root.width)
        readonly property real anchorY: {
            const row = root.confirming && root.list !== null ? root.list.rowFor(root.confirmTarget.uuid) : null;
            return row === null ? root.height / 2 : row.mapToItem(root, 0, row.height / 2).y;
        }
        y: Math.max(0, Math.min(root.height - height, anchorY - height / 2))
        title: root.confirmTarget === null ? "" : "Remove " + root.confirmTarget.name + "?"
        message: "NetworkManager deletes this profile with the passwords and keys saved in it. Key and certificate files that the profile uses stay on this computer. You cannot undo this."
        actions: [{ label: "Cancel", role: "cancel", focused: true }, { label: "Remove", role: "accept", variant: "danger" }]
        onAccepted: root.acceptRemove()
        onRejected: root.cancelRemove()
    }

    // As the remove confirmation's, over the prompt's host. Over a Pane
    // the scrim rounds to the Pane's container corner, so it darkens
    // nothing outside the card in the transparent popup. Both items join
    // the host in no set order, so the dialog's `z` keeps it above.
    Scrim {
        visible: root.prompting
        parent: root.promptHost
        radius: root.promptCorner
        onClicked: prompt.takeFocus()
    }
    ConnectPrompt {
        id: prompt
        parent: root.promptHost
        z: 1
        visible: root.prompting
        target: root.promptTarget
        retry: root.promptRow !== null && root.promptRow.failure === "password-tried"
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(implicitWidth, parent.width)
        readonly property real anchorY: {
            const row = root.prompting && root.promptPane === null && root.list !== null ? root.list.rowFor(root.promptTarget.uuid) : null;
            return row === null ? parent.height / 2 : row.mapToItem(root, 0, row.height / 2).y;
        }
        y: Math.max(0, Math.min(parent.height - height, anchorY - height / 2))
        onSubmitting: uuid => root.follow(uuid)
        onSubmitted: (uuid, reply) => root.passwordAnswered(uuid, reply)
        onCanceled: uuid => root.closePrompt(uuid)
    }
}
