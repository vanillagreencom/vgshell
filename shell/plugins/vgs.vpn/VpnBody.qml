import QtQuick
import qs.Commons
import qs.Ui
import "VpnLogic.js" as Logic

// The existing profile list, shared by the flyout and System Settings.
FocusScope {
    id: root
    property var shell: null
    property bool expanded: false
    property string leaseId: ""
    property bool leased: false
    property string localProblem: ""
    readonly property var profiles: shell === null || !shell.status.values.profiles ? Object.assign(Logic.emptyProfiles(), { action: "", problem: "" }) : shell.status.values.profiles
    readonly property var profileRows: profiles.rows
    readonly property var pollChoices: [10, 30, 60]
    readonly property Item initialFocus: root
    implicitHeight: content.implicitHeight

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

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group
        Label {
            objectName: "vpn-state"
            width: parent.width
            visible: root.profiles.state !== "available"
            role: "body"
            textFormat: Text.PlainText
            text: root.shell === null || !root.shell.status.values.connection ? "" : root.shell.status.values.connection.text
            wrapMode: Text.Wrap
        }
        Label {
            objectName: "vpn-problem"
            width: parent.width
            visible: text !== ""
            role: "hint"
            color: Theme.color.danger
            text: root.localProblem !== "" ? root.localProblem : root.profiles.problem
            wrapMode: Text.Wrap
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
                    width: root.width
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
            visible: root.expanded && root.profiles.state === "available"
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
