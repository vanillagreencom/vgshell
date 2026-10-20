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
// copy's folder in the file manager. The files that need no action fold
// into one line that unfolds in place, and each of their rows offers
// Dismiss, which asks the service to hide the row until its record
// changes; the row leaves when the runner writes the record again, and
// the fold line goes with the last row (reviewView). A Dismiss pressed
// from the keyboard hands the focus to the fold line, or from the last
// row to the stop after it, so the keyboard keeps its place when the row
// leaves. A row's name, in Needs you and in the rows that need no
// action, is a link that opens the file through
// the core's one file route (a text file in the core editor, any other
// in its default application) and closes the popover; a file that is no
// longer on this computer says so on its row and keeps it. A name is plain
// text where the file was never here (conflictRow's `file`). The footer holds
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
    // The header's parts test `header` itself, not `known`: both follow
    // `cloud`, and a binding that tested `known` ran before `header` took
    // the new value when the core assigned `shell`, and read null (a
    // qml-unit run, 2026-10-18).
    readonly property var header: known ?Logic.panelHeader(cloud, now, Timestamp.text) : null
    readonly property var callout: known ? Logic.problemCallout(cloud, now) : null
    readonly property string body: known ? Logic.panelBody(cloud, now) : ""
    readonly property var review: known ? Logic.reviewView(cloud) : ({ needs: [], notes: [], notesLine: "", moreNeeds: "", moreNotes: "" })
    readonly property var footer: Logic.footerView(cloud)
    readonly property bool notesOpen: notesFold.expanded
    // The refusal the last press was answered with, "" for none; else the
    // service's last failed request.
    property string problem: ""
    // The files this popover found no longer on this computer, whose rows
    // say so.
    property var goneFiles: []
    readonly property string problemLine: problem !== "" ? problem : known ? cloud.problem : ""

    function open(payloadJson) {
        problem = "";
        goneFiles = [];
    }
    function close() {}

    // Sync now, Pause or Resume through the service; answers its reply.
    function ask(name) {
        return answered(shell.ipc.call(name, ""), "VGS could not reach the Google Drive sync.");
    }

    // Dismiss through the service: the row of KEY, which needs no action.
    function dismiss(key) {
        return answered(shell.ipc.call("dismiss", key), "VGS could not remove the file from the list.");
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

    // Open FILE, a review row's file on this computer, through the same
    // route: a text file in the core editor, any other in its default
    // application. The route answers once it has read the file
    // (GoogleDriveLogic.openFileEnd): an opened file closes the popover, as
    // a fix does, since the editor takes the keyboard the popover holds; a
    // file that is gone keeps its row, which says so.
    function openFile(file) {
        shell.tui.edit(file, undefined, reply => {
            const end = Logic.openFileEnd(reply);
            if (end === "opened") {
                problem = "";
                shell.surfaces.hide("panel");
            } else if (end === "gone") {
                problem = "";
                goneFiles = goneFiles.concat([file]);
            } else {
                problem = "VGS could not open the file.";
                console.warn("google-drive panel: " + reply);
            }
        });
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
    // content edge, as unboxed text does: the row takes no click, only
    // its name's link and its action do.
    component ReviewRow: Row {
        id: reviewRow
        required property var modelData
        readonly property bool linked: modelData.file !== null
        property bool gone: false
        signal showFolder(string folder)
        signal openFile(string file)
        // KEYBOARD is the action when Tab, Backtab or a shortcut gave it
        // its focus, else null.
        signal dismiss(string key, Item keyboard)
        spacing: Theme.listItem.iconGap

        Icon {
            id: mark
            y: nameLabel.topForLeadingIcon(height, 0, reviewRow.linked && nameLabel.lineCount === 1)
            name: reviewRow.modelData.icon
            size: Theme.icon.size.md
            color: reviewRow.modelData.needs === "you" ? Theme.color.warning : Theme.color.textMuted
        }
        Column {
            width: Math.max(0, reviewRow.width - mark.width - reviewRow.spacing)
            spacing: Theme.row.lineGap

            // Text.Wrap breaks a long name with no space inside a word
            // (Qt Text.wrapMode). The mark reads its centre from this
            // label's font, which the link draws in too, so it stays in
            // place while the label is hidden for a linked name.
            Label {
                id: nameLabel
                visible: !reviewRow.linked
                width: parent.width
                role: "item"
                textFormat: Text.PlainText
                text: reviewRow.modelData.name
                wrapMode: Text.Wrap
            }
            // The name as a link to its file, the whole name its words.
            // As wide as its words up to the column, so the pointer
            // reaches the link wherever it meets the box.
            LinkText {
                visible: reviewRow.linked
                width: Math.min(implicitWidth, parent.width)
                role: "item"
                text: reviewRow.modelData.name
                link: reviewRow.linked ? reviewRow.modelData.name : ""
                wrapMode: Text.Wrap
                onActivated: reviewRow.openFile(reviewRow.modelData.file)
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
            Label {
                visible: reviewRow.gone
                width: parent.width
                role: "body"
                color: Theme.color.danger
                text: "This file is no longer on this computer."
                wrapMode: Text.Wrap
            }
            // visualFocus holds only while Tab, Backtab or a shortcut gave
            // the action its focus (Qt Quick Templates, Control.visualFocus),
            // so only a Dismiss pressed from the keyboard moves the focus.
            RowAction {
                id: rowAction
                visible: reviewRow.modelData.action !== null
                text: reviewRow.modelData.action === null ? "" : reviewRow.modelData.action.label
                onClicked: {
                    const action = reviewRow.modelData.action;
                    if (action.kind === "folder") reviewRow.showFolder(action.folder);
                    else if (action.kind === "dismiss") reviewRow.dismiss(action.key, rowAction.visualFocus ? rowAction : null);
                    else throw new Error("google-drive panel: row action " + JSON.stringify(action.kind) + " is not one conflictRow makes");
                }
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
                    name: root.header !== null ? root.header.icon : "cloud"
                    size: Theme.icon.size.lg
                    color: root.header !== null ? root.toneColor(root.header.tone) : Theme.color.textMuted
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
                    text: root.header !== null ? root.header.headline : "Reading the sync status"
                    color: root.header !== null ? root.toneColor(root.header.tone) : Theme.color.textMuted
                    wrapMode: Text.Wrap
                }
                Label {
                    width: parent.width
                    visible: root.header !== null
                    role: "hint"
                    text: root.header !== null ? root.header.meta : ""
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
                        gone: root.goneFiles.indexOf(modelData.file) !== -1
                        onShowFolder: folder => root.showFolder(folder)
                        onOpenFile: file => root.openFile(file)
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

        // The files that need no action, folded until the user opens them.
        // The fold line's chevron stands in the rows' icon column and its
        // words in their text column, so it and every row share one grid:
        // the line and its cursor reach out into the focus ring's room on
        // both sides (Pane leaves that room past the content edge), and the
        // line's padding is that room, so the plate covers the reach and the
        // content stays on the grid. Disclosure would put the chevron at the
        // end and inset the line by its padding. The line is a Tab stop; a
        // click, Return, Enter or Space opens and closes it, Right opens and
        // Left closes, as Disclosure's row does.
        Column {
            id: notesFold
            property bool expanded: false
            readonly property real ringRoom: Theme.focusRing.width + Theme.focusRing.offset
            width: layout.contentWidth
            visible: root.review.notesLine !== ""
            spacing: Theme.stack.row

            // Column sets only a child's y (tst_googledrive_panel.qml reads
            // the reach), so the wrapper keeps the x that reaches out.
            Item {
                x: -notesFold.ringRoom
                width: parent.width + 2 * notesFold.ringRoom
                height: foldLine.height
                ListCursor { id: foldCursor }
                // focus-indicator: ListItem draws its FocusRing for the fold line
                ListItem {
                    id: foldLine
                    width: parent.width
                    leftPadding: notesFold.ringRoom
                    rightPadding: notesFold.ringRoom
                    cursor: foldCursor
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
            }

            GroupList {
                id: notesList
                width: parent.width
                visible: notesFold.expanded
                Repeater {
                    model: root.review.notes
                    ReviewRow {
                        width: notesList.width
                        gone: root.goneFiles.indexOf(modelData.file) !== -1
                        onOpenFile: file => root.openFile(file)
                        // The fold line stays while another row does; the
                        // last row takes it along, so the focus moves on to
                        // the stop after the action (Item.nextItemInFocusChain,
                        // tst_googledrive_panel.qml reads both).
                        onDismiss: (key, keyboard) => {
                            const last = root.review.notes.length === 1 && root.review.moreNotes === "";
                            if (keyboard !== null) (last ? keyboard.nextItemInFocusChain(true) : foldLine).forceActiveFocus(Qt.TabFocusReason);
                            root.dismiss(key);
                        }
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
