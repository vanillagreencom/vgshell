import QtQuick
import qs.Commons
import qs.Ui
import "SyncLogic.js" as Logic

// The Local Sync flyout under the bar item: one Card a sync job, in the
// order SyncLogic.jobs gives. A card holds the job's name and its options
// menu (Details, Remove), its state in plain words, danger ink and a mark
// for a failure, From and To path chips that open the folder, its last
// copy, and on a problem what went wrong, what to do and its links: View
// log, which opens the job's journal in a floating terminal, and Send to
// agent, which hands the failure to Agent Debug's Diagnose (SyncLogic.card
// decides which). Details replaces the cards with the job's readings and a
// way back. Remove of a job the user made outside VGS asks first, in a
// confirmation over the flyout, and then asks the service to stop and
// turn it off; its file stays. Remove of a job Automations runs, and Add
// sync job in the footer, open Automations on that job, where the user
// saves or removes it. The flyout
// reads the `jobs` value the service publishes and changes nothing itself.
// It is `size.panel.lg` wide, fits its content up to `size.panel.maxHeight`
// and scrolls its body past that. The panel host closes it on Escape and
// on a click outside it. It takes no payload.
Item {
    id: root

    property var shell: null
    readonly property var value: shell === null ? undefined : shell.status.values.jobs
    readonly property bool known: value !== undefined && value !== null
    readonly property double now: Time.now.getTime()
    readonly property var jobs: known ? value.jobs : []
    readonly property var cards: known ? Logic.cards(value, now, Timestamp.text) : []
    // The job Details shows, and the one Remove asks about, "" for none.
    property string detailsUnit: ""
    property string confirmUnit: ""
    readonly property var detailsJob: jobs.find(job => job.unit === detailsUnit) || null
    readonly property var confirmJob: jobs.find(job => job.unit === confirmUnit) || null
    readonly property var detailsView: detailsJob === null ? null : Logic.detailsOf(value, detailsJob, now, Timestamp.text)
    // The refusal the last press was answered with, "" for none.
    property string problem: ""
    readonly property string problemLine: problem !== "" ? problem : !known ? "" : value.removeProblem !== "" ? value.removeProblem : value.problem !== "" ? value.problem : value.storeProblem

    function open(payloadJson) {
        problem = "";
        detailsUnit = "";
        confirmUnit = "";
        answered(shell.ipc.call("refresh", ""), "Local Sync could not read the jobs again.");
    }
    function close() {
        confirmUnit = "";
    }

    function answered(reply, sentence) {
        problem = reply === "ok" ? "" : sentence;
        if (reply !== "ok") console.warn("local-sync panel: " + reply);
        return reply;
    }

    // Open FOLDER in the file manager through the core's one folder route.
    function showFolder(folder) {
        return answered(shell.tui.edit(folder.replace(/\/*$/, "") + "/"), "VGS could not open the folder.");
    }

    function viewLog(unit) {
        const reply = answered(shell.tui.run("log", [unit]), "VGS could not open the job's log.");
        if (reply === "ok") shell.surfaces.hide("panel");
        return reply;
    }

    function openSetup() {
        const reply = answered(shell.surfaces.openPage(shell.manifest.id, "Setup"), "VGS could not show the Local Sync setup.");
        if (reply === "ok") shell.surfaces.hide("panel");
        return reply;
    }

    // Remove: an automation's job goes to Automations, which asks there;
    // any other job asks here first.
    function remove(job) {
        problem = "";
        if (job.automation !== "" && automationsReason !== "") problem = automationsReason;
        else if (job.automation !== "") handTo(automationsTarget, Logic.removeRequest(job));
        else confirmUnit = job.unit;
    }

    function add() {
        handTo(automationsTarget, Logic.addRequest(known ? value.engines : []));
    }

    function acceptRemove() {
        const unit = confirmUnit;
        confirmUnit = "";
        detailsUnit = "";
        answered(shell.ipc.call("remove", unit), "Local Sync could not stop the job.");
    }

    // The one place the panel picks another plugin's receiver: by its
    // fixed key among the targets the core lends (D127); undefined while
    // that plugin does not offer it.
    function target(key) {
        return shell === null ? undefined : shell.handoff.targets.find(each => each.key === key);
    }
    readonly property var agentTarget: target(Logic.AGENT_TARGET)
    readonly property var automationsTarget: target(Logic.AUTOMATIONS_TARGET)
    function unavailable(found, owner) {
        return found === undefined ? "Turn on " + owner + " to use this." : found.available ? "" : found.reason;
    }
    readonly property string agentReason: unavailable(agentTarget, "Agent Debug")
    readonly property string automationsReason: unavailable(automationsTarget, "Automations")

    // Hand TEXT to FOUND, a receiver that opens its own draft; an opened
    // draft closes the flyout, and a refusal says why.
    function handTo(found, text) {
        if (found === undefined || !found.available) return;
        const result = found.open(text);
        problem = result.ok ? "" : result.reason;
        if (result.ok) shell.surfaces.hide("panel");
    }

    // Hand JOB's failure to Agent Debug, which opens it as a draft the user
    // runs in the agent chosen there.
    function sendToAgent(unit) {
        const job = jobs.find(each => each.unit === unit);
        if (job !== undefined) handTo(agentTarget, Logic.agentFacts(job, Logic.factsOf(value, job)));
    }

    function linkText(action) {
        return action === "log" ? "View log" : action === "agent" ? "Send to agent" : "Open Local Sync setup";
    }

    function act(action, card) {
        if (action === "log") viewLog(card.unit);
        else if (action === "agent") sendToAgent(card.unit);
        else if (action === "setup") openSetup();
    }

    // The tone of a card's state line as its colour.
    function toneColor(tone) {
        return tone === "danger" ? Theme.color.danger : tone === "info" ? Theme.color.info : Theme.color.textMuted;
    }

    implicitWidth: Theme.size.panel.lg
    implicitHeight: Math.max(layout.implicitHeight, confirm.visible ? confirmDialog.implicitHeight + 2 * Theme.dialog.margin : 0)

    Surface {
        anchors.fill: parent
    }

    // One folder of a job: its label, From or To, and its chip.
    component FolderRow: Item {
        id: folderRow
        property string label: ""
        property string folder: ""
        property real labelWidth: 0
        width: parent.width
        implicitHeight: Math.max(folderLabel.implicitHeight, chip.height)
        Label {
            id: folderLabel
            y: topForCapCenter(chip.lineHeight)
            role: "hint"
            text: folderRow.label
            color: Theme.color.textMuted
        }
        PathChip {
            id: chip
            x: folderRow.labelWidth + Theme.stack.inline
            maxWidth: parent.width - x
            width: implicitWidth
            height: implicitHeight
            text: folderRow.folder === "" ? "Not readable from the job" : folderRow.folder
            onClicked: root.showFolder(folderRow.folder)
        }
    }

    // A job's card: the layout of flyout v6 (VGS-2190).
    component JobCard: Card {
        id: jobCard
        required property var modelData
        readonly property var job: root.jobs.find(each => each.unit === modelData.unit) || null

        Column {
            width: parent.width
            spacing: Theme.stack.inline

            Column {
                width: parent.width
                spacing: Theme.row.lineGap
                Item {
                    width: parent.width
                    implicitHeight: Math.max(jobName.implicitHeight, options.implicitHeight)
                    Label {
                        id: jobName
                        width: parent.width - options.width - Theme.stack.inline
                        anchors.verticalCenter: parent.verticalCenter
                        role: "bodyStrong"
                        // A job's name comes from its unit or the user.
                        textFormat: Text.PlainText
                        text: jobCard.modelData.name
                        wrapMode: Text.Wrap
                    }
                    IconButton {
                        id: options
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        size: "sm"
                        iconName: "ellipsis"
                        label: "Job options"
                        onClicked: jobMenu.toggle("pointer")
                        Menu {
                            id: jobMenu
                            MenuItem {
                                text: "Details"
                                iconName: "info"
                                onTriggered: root.detailsUnit = jobCard.modelData.unit
                            }
                            MenuItem {
                                text: "Remove"
                                iconName: "trash"
                                onTriggered: if (jobCard.job !== null) root.remove(jobCard.job)
                            }
                        }
                    }
                }
                Item {
                    width: parent.width
                    implicitHeight: stateLabel.implicitHeight
                    Icon {
                        id: attention
                        visible: jobCard.modelData.tone === "danger"
                        name: "triangle-alert"
                        size: Theme.icon.size.sm
                        color: Theme.color.danger
                        y: stateLabel.topForLeadingIcon(height)
                    }
                    Label {
                        id: stateLabel
                        x: attention.visible ? attention.width + Theme.stack.inline : 0
                        width: parent.width - x
                        role: "hint"
                        text: jobCard.modelData.stateText
                        color: root.toneColor(jobCard.modelData.tone)
                        wrapMode: Text.Wrap
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.row.lineGap
                FolderRow { label: "From"; folder: jobCard.modelData.from; labelWidth: Math.max(fromWidth.implicitWidth, toWidth.implicitWidth) }
                FolderRow { label: "To"; folder: jobCard.modelData.to; labelWidth: Math.max(fromWidth.implicitWidth, toWidth.implicitWidth) }
                // The wider of the two labels sets where both chips start.
                Label { id: fromWidth; visible: false; role: "hint"; text: "From" }
                Label { id: toWidth; visible: false; role: "hint"; text: "To" }
            }

            Column {
                width: parent.width
                spacing: Theme.row.lineGap
                Label {
                    width: parent.width
                    role: "hint"
                    text: jobCard.modelData.recent
                    color: Theme.color.textMuted
                    wrapMode: Text.Wrap
                }
                Label {
                    width: parent.width
                    visible: text !== ""
                    role: "hint"
                    text: jobCard.modelData.explanation
                    color: jobCard.modelData.tone === "danger" ? Theme.color.danger : Theme.color.textMuted
                    wrapMode: Text.Wrap
                }
                Label {
                    width: parent.width
                    visible: text !== ""
                    role: "hint"
                    text: jobCard.modelData.next
                    color: Theme.color.text
                    wrapMode: Text.Wrap
                }
            }

            RowActions {
                visible: jobCard.modelData.actions.length > 0
                width: parent.width
                Repeater {
                    model: jobCard.modelData.actions
                    RowAction {
                        required property string modelData
                        text: root.linkText(modelData)
                        disabledReason: modelData === "agent" ? root.agentReason : ""
                        onClicked: root.act(modelData, jobCard.modelData)
                    }
                }
            }
        }
    }

    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight
        settingsGear: false
        title: root.detailsView === null ? "Local Sync" : ""

        // Details leads its title with the way back to the cards.
        titleContent: [
            Row {
                visible: root.detailsView !== null
                spacing: Theme.stack.inline
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    size: "sm"
                    iconName: "chevron-left"
                    label: "Back to sync jobs"
                    onClicked: root.detailsUnit = ""
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "h3"
                    textFormat: Text.PlainText
                    text: root.detailsJob === null ? "" : root.detailsJob.name
                }
            }
        ]

        Label {
            width: layout.contentWidth
            visible: !root.known || (!root.value.ready && root.value.problem === "")
            role: "body"
            text: "Reading the sync jobs"
            color: Theme.color.textMuted
        }

        EmptyState {
            width: layout.contentWidth
            visible: root.known && root.value.ready && root.jobs.length === 0 && root.detailsView === null
            iconName: "folder-sync"
            text: "No sync jobs on this computer."
        }

        Repeater {
            model: root.detailsView === null ? root.cards : []
            JobCard { width: layout.contentWidth }
        }

        GroupList {
            width: layout.contentWidth
            visible: root.detailsView !== null
            Repeater {
                model: root.detailsView === null ? [] : root.detailsView.rows
                FormRow {
                    id: reading
                    required property var modelData
                    width: parent.width
                    label: modelData.label
                    // A reading holds the unit's and the journal's own text,
                    // such as an engine's error line, which may hold markup.
                    Label {
                        width: parent.width
                        role: "value"
                        textFormat: Text.PlainText
                        text: reading.modelData.value
                        color: reading.modelData.tone === "danger" ? Theme.color.danger : Theme.color.text
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }
                }
            }
        }

        Label {
            width: layout.contentWidth
            visible: root.detailsView !== null && root.detailsView.help !== ""
            role: "hint"
            text: root.detailsView === null ? "" : root.detailsView.help
            wrapMode: Text.Wrap
        }

        // A receiver's reason may name a page (PageReference): it opens
        // that page.
        LinkText {
            width: layout.contentWidth
            visible: text !== ""
            role: "hint"
            text: root.problemLine
            color: Theme.color.danger
            wrapMode: Text.Wrap
            onPageActivated: (page, tab) => {
                if (root.answered(root.shell.surfaces.openPage(page, tab), "VGS could not show that page.") === "ok") root.shell.surfaces.hide("panel");
            }
        }

        footer: [
            RowAction {
                visible: root.detailsView === null
                text: "Add sync job"
                disabledReason: root.automationsReason
                onClicked: root.add()
            }
        ]
    }

    // Remove's question, over the flyout: a job the user made outside VGS
    // is stopped and turned off, and its file stays.
    Item {
        id: confirm
        anchors.fill: parent
        visible: root.confirmJob !== null
        Keys.onEscapePressed: event => {
            root.confirmUnit = "";
            event.accepted = true;
        }
        Scrim { anchors.fill: parent; onClicked: root.confirmUnit = "" }
        Dialog {
            id: confirmDialog
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 2 * Theme.dialog.margin)
            // The flyout's own height follows the dialog's, so the dialog
            // takes the flyout's height cap as its room.
            availableHeight: Theme.size.panel.maxHeight
            title: root.confirmJob === null ? "" : Logic.removal(root.confirmJob).title
            message: root.confirmJob === null ? "" : Logic.removal(root.confirmJob).text
            actions: [
                { label: "Cancel", role: "cancel", focused: true },
                { label: root.confirmJob === null ? "" : Logic.removal(root.confirmJob).action, role: "accept", variant: "danger" }
            ]
            onRejected: root.confirmUnit = ""
            onAccepted: root.acceptRemove()
        }
        onVisibleChanged: if (visible) Qt.callLater(() => confirmDialog.forceActiveFocus())
    }
}
