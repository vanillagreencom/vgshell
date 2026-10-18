import QtQuick
import qs.Commons
import qs.Ui
import "GoogleDriveLogic.js" as Logic

// The Google Drive popover under the bar icon: whether Google Drive is in
// sync, and the files that need the user. Everything the user sets up is
// on the plugin's Settings page, which the gear the panel host draws
// opens. The header is the status mark in the headline's tone, "Google
// Drive", the headline (GoogleDriveLogic.headline, which the bar and the
// Details tab also read) and the last sync with the count of folder pairs
// (panelHeader); it names no file. A problem, such as a sign-in Google
// refused, is a callout with what happened and its one fix
// (problemCallout), which opens the plugin's own TUI or a tab of its page
// and closes the popover. With nothing to review it says what the state
// means (panelBody). Needs you lists each file that needs the user, its
// name, its folder pair and folders, its one line and, for a change on
// both sides whose copy VGS kept, Show older copy, which opens that
// copy's folder in the file manager. The notes, the files that need
// nothing, fold into one line that unfolds in place; a note has no
// action, since its fix is in Google Drive (reviewView). The footer holds
// Pause or Resume and Sync now, and shows only while a sync can run
// (footerView). It runs nothing itself: Sync now, Pause and Resume ask the
// service through the plugin's own IPC. The popover is `size.panel.md`
// wide, fits its content up to `size.panel.maxHeight`, and scrolls its
// body past that. The panel host closes it on Escape and on a click
// outside it. It takes no payload.
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation, and
    // again when the plugin's settings change.
    property var shell: null
    readonly property var cloud: shell === null ? undefined : shell.status.values.cloud
    readonly property bool known: cloud !== undefined && cloud !== null
    readonly property double now: Time.now.getTime()
    readonly property var header: known ? Logic.panelHeader(cloud, now, Timestamp.text) : null
    readonly property var callout: known ? Logic.problemCallout(cloud, now) : null
    readonly property string body: known ? Logic.panelBody(cloud, now) : ""
    readonly property var review: known ? Logic.reviewView(cloud) : ({ needs: [], notes: [], notesLine: "", moreNeeds: "", moreNotes: "" })
    readonly property var footer: Logic.footerView(cloud)
    readonly property bool notesOpen: notesFold.expanded
    // The refusal the last press was answered with, "" for none; else the
    // service's last failed request.
    property string problem: ""
    readonly property string problemLine: problem !== "" ? problem : known ? cloud.problem : ""

    function open(payloadJson) {
        problem = "";
    }
    function close() {}

    // Sync now, Pause or Resume through the service; answers its reply.
    function ask(name) {
        return answered(shell.ipc.call(name, ""), "VGS could not reach the Google Drive sync.");
    }

    // A callout's fix: the plugin's own TUI or a tab of its page. A fix
    // that opened closes the popover, since the user works there now.
    function fix(action) {
        const reply = action.tui !== undefined
            ? answered(shell.tui.run(action.tui), "VGS could not open the window for this step.")
            : answered(shell.surfaces.openPage("vgs.google-drive", action.tab), "VGS could not show the Google Drive settings.");
        if (reply === "ok") shell.surfaces.hide("panel");
        return reply;
    }

    // Open FOLDER in the file manager through the core's one route.
    function showFolder(folder) {
        return answered(shell.tui.edit(folder + "/"), "VGS could not open the folder.");
    }

    function answered(reply, sentence) {
        problem = reply === "ok" ? "" : sentence;
        if (reply !== "ok") console.warn("google-drive panel: " + reply);
        return reply;
    }

    // A Badge tone as the colour the header draws its mark and headline in.
    function toneColor(tone) {
        const found = Theme.badge.tone[tone];
        if (found === undefined) throw new Error("google-drive panel: tone " + JSON.stringify(tone) + " is not a Badge tone");
        return found.foreground;
    }

    // One file to review: its mark, its name, its place, its one line with
    // the info that says why a limit there holds, and its action. The
    // mark leads the name on its x-height centre (design-system.md
    // § Tokens). The lines wrap, so none is cut. Its text sits on the
    // content edge, as unboxed text does: the row takes no click.
    component ReviewRow: Row {
        id: reviewRow
        required property var modelData
        signal showFolder(string folder)
        spacing: Theme.listItem.iconGap

        Icon {
            id: mark
            y: nameLabel.topForLeadingIcon(height)
            name: reviewRow.modelData.icon
            size: Theme.icon.size.md
            color: reviewRow.modelData.needs === "you" ? Theme.color.warning : Theme.color.textMuted
        }
        Column {
            width: Math.max(0, reviewRow.width - mark.width - reviewRow.spacing)
            spacing: Theme.row.lineGap

            // Text.Wrap breaks a long name with no space inside a word
            // (Qt Text.wrapMode).
            Label {
                id: nameLabel
                width: parent.width
                role: "item"
                textFormat: Text.PlainText
                text: reviewRow.modelData.name
                wrapMode: Text.Wrap
            }
            Label {
                width: parent.width
                role: "itemHint"
                textFormat: Text.PlainText
                text: reviewRow.modelData.place
                wrapMode: Text.Wrap
            }
            Row {
                width: parent.width
                spacing: Theme.space.xs
                Label {
                    id: detailLabel
                    width: parent.width - (limitInfo.visible ? limitInfo.width + parent.spacing : 0)
                    role: "body"
                    color: Theme.color.textMuted
                    textFormat: Text.PlainText
                    text: reviewRow.modelData.detail
                    wrapMode: Text.Wrap
                }
                InfoButton {
                    id: limitInfo
                    visible: reviewRow.modelData.info !== ""
                    y: detailLabel.topForLeadingIcon(height)
                    title: "Kept copies"
                    info: reviewRow.modelData.info
                }
            }
            RowAction {
                visible: reviewRow.modelData.action !== null
                text: reviewRow.modelData.action === null ? "" : reviewRow.modelData.action.label
                onClicked: reviewRow.showFolder(reviewRow.modelData.action.folder)
            }
        }
    }

    implicitWidth: Theme.size.panel.md
    implicitHeight: layout.implicitHeight

    Surface {
        anchors.fill: parent
    }

    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight

        // The status mark leads the title, and the headline and the sync
        // line under it start where the title's text does.
        titleContent: [
            Item {
                width: parent.width
                implicitHeight: titleLabel.implicitHeight

                Icon {
                    id: statusMark
                    y: titleLabel.topForLeadingIcon(height)
                    name: root.known ? root.header.icon : "cloud"
                    size: Theme.icon.size.lg
                    color: root.known ? root.toneColor(root.header.tone) : Theme.color.textMuted
                }
                Label {
                    id: titleLabel
                    x: statusMark.width + Theme.listItem.iconGap
                    width: Math.max(0, parent.width - x)
                    role: "h3"
                    text: "Google Drive"
                    elide: Text.ElideRight
                }
            }
        ]
        subtitle: [
            Column {
                x: statusMark.width + Theme.listItem.iconGap
                width: Math.max(0, layout.headerWidth - x)
                spacing: Theme.row.lineGap

                Label {
                    width: parent.width
                    role: "bodyStrong"
                    text: root.known ? root.header.headline : "Reading the sync status"
                    color: root.known ? root.toneColor(root.header.tone) : Theme.color.textMuted
                    wrapMode: Text.Wrap
                }
                Label {
                    width: parent.width
                    visible: root.known
                    role: "hint"
                    text: root.known ? root.header.meta : ""
                    wrapMode: Text.Wrap
                }
            }
        ]

        Callout {
            width: layout.contentWidth
            visible: root.callout !== null
            tone: root.callout === null ? "danger" : root.callout.tone
            title: root.callout === null ? "" : root.callout.title
            text: root.callout === null ? "" : root.callout.text
            linkText: root.callout === null || root.callout.action === null ? "" : root.callout.action.label
            onActivated: root.fix(root.callout.action)
        }

        Label {
            width: layout.contentWidth
            visible: text !== ""
            role: "body"
            text: root.body
            wrapMode: Text.Wrap
        }

        Section {
            width: layout.contentWidth
            visible: root.review.needs.length > 0
            title: "Needs you"

            GroupList {
                id: needsList
                width: parent.width
                Repeater {
                    model: root.review.needs
                    ReviewRow {
                        width: needsList.width
                        onShowFolder: folder => root.showFolder(folder)
                    }
                }
            }
            Label {
                width: parent.width
                visible: text !== ""
                role: "hint"
                text: root.review.moreNeeds
            }
        }

        // The notes, folded until the user opens them. The fold line's
        // chevron stands in the rows' icon column and its words in their
        // text column, so it and every row share one grid: the row takes no
        // side padding, and its hover box reaches out into the focus ring's
        // room instead (Pane leaves that room past the content edge), never
        // pushing the content in. Disclosure would put the chevron at the
        // end and inset the line by its padding. The line is a Tab stop;
        // a click, Return, Enter or Space opens and closes it, Right opens
        // and Left closes, as Disclosure's row does.
        Column {
            id: notesFold
            property bool expanded: false
            readonly property real ringRoom: Theme.focusRing.width + Theme.focusRing.offset
            width: layout.contentWidth
            visible: root.review.notesLine !== ""
            spacing: Theme.stack.row

            // focus-indicator: ListItem draws its FocusRing for the fold line
            ListItem {
                width: parent.width
                leftPadding: 0
                rightPadding: 0
                leftInset: -notesFold.ringRoom
                rightInset: -notesFold.ringRoom
                focusPolicy: Qt.StrongFocus
                iconName: notesFold.expanded ? "chevron-down" : "chevron-right"
                text: root.review.notesLine
                onClicked: notesFold.expanded = !notesFold.expanded
                Keys.onReturnPressed: notesFold.expanded = !notesFold.expanded
                Keys.onEnterPressed: notesFold.expanded = !notesFold.expanded
                Keys.onSpacePressed: notesFold.expanded = !notesFold.expanded
                Keys.onRightPressed: notesFold.expanded = true
                Keys.onLeftPressed: notesFold.expanded = false
            }

            GroupList {
                id: notesList
                width: parent.width
                visible: notesFold.expanded
                Repeater {
                    model: root.review.notes
                    ReviewRow {
                        width: notesList.width
                    }
                }
            }
            Label {
                width: parent.width
                visible: notesFold.expanded && text !== ""
                role: "hint"
                text: root.review.moreNotes
            }
        }

        Label {
            width: layout.contentWidth
            visible: text !== ""
            role: "hint"
            text: root.problemLine
            color: Theme.color.danger
            wrapMode: Text.Wrap
        }

        // Pause or Resume, and Sync now. Hidden while no sync can run, when
        // it takes no height, so the pane keeps no footer room.
        footer: [
            Item {
                width: layout.contentWidth
                visible: root.footer.shown
                implicitHeight: visible ? Math.max(pauseButton.implicitHeight, syncButton.implicitHeight) : 0
                height: implicitHeight

                Button {
                    id: pauseButton
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    variant: "secondary"
                    text: root.footer.shown ? root.footer.pause.text : ""
                    iconName: root.footer.shown ? root.footer.pause.icon : ""
                    onClicked: root.ask(root.footer.pause.action)
                }
                Button {
                    id: syncButton
                    anchors.left: pauseButton.right
                    anchors.leftMargin: Theme.stack.inline
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    variant: "primary"
                    text: root.footer.shown ? root.footer.sync.text : ""
                    iconName: root.footer.shown ? root.footer.sync.icon : ""
                    disabledReason: root.footer.shown ? root.footer.sync.reason : ""
                    onClicked: root.ask(root.footer.sync.action)
                }
            }
        ]
    }
}
