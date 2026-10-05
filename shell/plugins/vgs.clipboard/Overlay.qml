import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The clipboard history: a card over a scrim on the screen it was summoned
// on, the search field over the entries on the left and the selected entry
// on the right. Typing filters the entries. Enter pastes the selected entry
// into the window that had the keyboard, Shift+Enter puts it on the
// clipboard alone, Ctrl+P pins it or lets it go, Delete removes it and
// Shift+Delete clears the history behind a confirmation. Escape clears the
// filter, then closes. A click on an entry pastes it.
//
// The overlay holds no history. It asks the plugin's service for the rows
// of the filter and for every change, through `shell.ipc.call`, and reads
// the rows again after each change it asked for. The service hides the
// overlay once a paste or a copy is on the clipboard.
//
// The payload is `{}` or empty; any other payload throws out of open(),
// which refuses the summon.
FocusScope {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    // What the service answered `rows` last: the rows drawn, the entries
    // the history holds and the directory of its image files.
    property var rows: []
    property int total: 0
    property string imagesDir: ""
    // The index in `rows` that holds the selection.
    property int current: 0
    // Whether the Clear all question shows.
    property bool confirming: false
    readonly property string filter: search.text
    readonly property var selected: current >= 0 && current < rows.length ? rows[current] : null
    readonly property Item initialFocus: search

    function open(payloadJson) {
        const payload = JSON.parse(payloadJson === "" ? "{}" : payloadJson);
        if (payload === null || typeof payload !== "object" || Array.isArray(payload) || Object.keys(payload).length > 0)
            throw new Error("payload must be {}, got " + payloadJson);
        refresh();
    }

    function close() {}

    // A Hyprland focus key moves the selection (D067).
    function navigate(direction) {
        if (direction === "up") nav.moveBy(-1);
        else if (direction === "down") nav.moveBy(1);
    }

    onShellChanged: refresh()
    onFilterChanged: {
        current = 0;
        refresh();
    }

    // Read the filter's rows from the service. The rows change under a
    // resting pointer: it takes no row until it moves, and the cursor lands
    // on the row the keyboard keeps.
    function refresh() {
        if (shell === null) return;
        const reply = shell.ipc.call("rows", filter);
        let answer = null;
        try { answer = JSON.parse(reply); } catch (e) { console.error("clipboard: rows answered " + reply.slice(0, 80)); }
        cursorPlate.disarm();
        cursorPlate.snap();
        rows = answer === null ? [] : answer.rows;
        total = answer === null ? 0 : answer.total;
        imagesDir = answer === null ? "" : answer.images;
        current = Math.max(0, Math.min(current, rows.length - 1));
    }

    // Ask the service for VERB on the row at INDEX; answers whether it did.
    function ask(verb, index) {
        if (index < 0 || index >= rows.length) return false;
        const reply = shell.ipc.call(verb, rows[index].id);
        if (reply !== "ok") console.warn("clipboard: " + verb + " " + reply);
        return reply === "ok";
    }

    function change(verb, index) {
        if (ask(verb, index)) refresh();
    }

    function clearAll() {
        confirming = false;
        const reply = shell.ipc.call("clear", "");
        if (reply !== "ok") console.warn("clipboard: clear " + reply);
        refresh();
        search.forceActiveFocus(Qt.ShortcutFocusReason);
    }

    // The file of image entry ID, which its id names.
    function fileUrl(id) {
        return "file://" + (imagesDir + "/" + id).split("/").map(encodeURIComponent).join("/");
    }

    function stamp(seconds) {
        return Qt.formatDateTime(new Date(seconds * 1000), "d MMM, HH:mm");
    }

    // The search field has the keyboard, so it keeps the caret keys; a
    // Delete with nothing after the caret has no text to delete and removes
    // the selected entry.
    function handleKey(event) {
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        const plain = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) === 0;
        if (event.key === Qt.Key_Escape && plain) {
            if (search.text === "") return false;
            search.clear();
            return true;
        }
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && plain && shift) {
            ask("copy", current);
            return true;
        }
        if (event.key === Qt.Key_Delete && plain && search.cursorPosition === search.length && search.selectedText === "") {
            if (!shift) change("delete", current);
            else if (total > 0) {
                confirming = true;
                confirm.forceActiveFocus(Qt.ShortcutFocusReason);
            }
            return true;
        }
        if (event.key === Qt.Key_P && event.modifiers === Qt.ControlModifier) {
            change("pin", current);
            return true;
        }
        return nav.handle(event);
    }

    Scrim {
        onClicked: {
            const reply = root.shell.surfaces.hide("overlay");
            if (reply !== "ok") console.warn("clipboard: hide " + reply);
        }
    }

    KeyNav {
        id: nav
        count: root.rows.length
        currentIndex: root.current
        textEntry: true
        viewHeight: list.height
        rowHeight: Theme.listItem.height
        cursor: cursorPlate
        flickable: list
        itemAt: index => entries.itemAt(index)
        onMoved: index => root.current = index
        onActivated: index => root.ask("paste", index)
    }

    Surface {
        id: card
        level: "raised"
        anchors.centerIn: parent
        width: Math.min(2 * Theme.size.panel.lg, root.width - 2 * Theme.inset.overlay)
        height: Math.min(Theme.size.panel.maxHeight, root.height - 2 * Theme.inset.overlay)

        readonly property real pad: Theme.inset.dialog
        readonly property real gap: Theme.stack.group

        // pointer-cursor-exempt: a press on the card's own ground does nothing, so the scrim under it does not close the history
        // keyboard-path: no action; Escape closes the history
        MouseArea {
            anchors.fill: parent
            onWheel: wheel => { wheel.accepted = true; }
        }

        TextField {
            id: search
            x: card.pad
            y: card.pad
            width: card.width - 2 * card.pad
            placeholderText: "Search the clipboard history"
            leadingIcon: "search"
            focus: true
            Keys.onPressed: event => { event.accepted = root.handleKey(event); }
        }

        KeyHints {
            id: hints
            x: card.pad
            y: card.height - card.pad - height
            hints: [
                { key: "Enter", text: "Paste" },
                { key: "Shift+Enter", text: "Copy" },
                { key: "Ctrl+P", text: "Pin" },
                { key: "Delete", text: "Remove" },
                { key: "Shift+Delete", text: "Clear all" }
            ]
        }

        Item {
            id: body
            x: card.pad
            y: search.y + search.height + card.gap
            width: card.width - 2 * card.pad
            height: hints.y - card.gap - y

            EmptyState {
                visible: root.rows.length === 0
                anchors.centerIn: parent
                width: parent.width
                iconName: root.total === 0 ? "clipboard-list" : "search-x"
                text: root.total === 0 ? "The clipboard history is empty" : "No entry matches the search"
                actionText: root.total === 0 ? "" : "Clear search"
                onActivated: {
                    search.clear();
                    search.forceActiveFocus();
                }
            }

            ScrollArea {
                id: list
                visible: root.rows.length > 0
                width: (parent.width - card.gap) / 2
                height: parent.height

                ListCursor {
                    id: cursorPlate
                    parent: list.contentItem
                }

                Column {
                    width: list.contentWidth

                    Repeater {
                        id: entries
                        // Rows are compared by structure, the model's
                        // default, so a row whose pin changed is built
                        // again and every other row stays.
                        model: ScriptModel { values: root.rows }

                        // An entry on one line, which ListItem draws as
                        // plain text, with an image entry's thumbnail and
                        // the pin of a pinned entry at its end.
                        ListItem {
                            id: entryRow
                            required property var modelData
                            required property int index
                            // A thumbnail is decoded once its row has been
                            // inside the list's view.
                            readonly property bool inView: y + height > list.contentY && y < list.contentY + list.height
                            property bool seen: false
                            width: list.contentWidth
                            text: modelData.label
                            iconName: modelData.type === "image" ? "image" : "type"
                            cursor: cursorPlate
                            highlighted: index === root.current
                            Component.onCompleted: if (inView) seen = true
                            onInViewChanged: if (inView) seen = true
                            onPointed: root.current = index
                            onClicked: {
                                root.current = index;
                                root.ask("paste", index);
                            }
                            trailing: [
                                Image {
                                    visible: entryRow.modelData.type === "image"
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.icon.size.lg
                                    height: Theme.icon.size.lg
                                    source: entryRow.modelData.type === "image" && entryRow.seen ? root.fileUrl(entryRow.modelData.id) : ""
                                    sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                },
                                Icon {
                                    visible: entryRow.modelData.pinned
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "pin"
                                    size: Theme.icon.size.sm
                                    color: Theme.color.textMuted
                                }
                            ]
                        }
                    }
                }
            }

            Divider {
                visible: list.visible
                vertical: true
                x: list.width + (card.gap - width) / 2
                height: parent.height
            }

            Item {
                id: preview
                visible: root.selected !== null
                x: list.width + card.gap
                width: parent.width - x
                height: parent.height
                clip: true

                Label {
                    id: caption
                    role: "hint"
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.selected === null ? "" : (root.selected.pinned ? "Pinned. " : "") + "Copied " + root.stamp(root.selected.time)
                }

                // Copied data: plain text, so a tag in it is text.
                Label {
                    visible: root.selected !== null && root.selected.type === "text"
                    role: "body"
                    textFormat: Text.PlainText
                    y: caption.height + Theme.stack.row
                    width: parent.width
                    height: parent.height - y
                    wrapMode: Text.WrapAnywhere
                    elide: Text.ElideRight
                    text: root.selected !== null && root.selected.type === "text" ? root.selected.text : ""
                }

                Image {
                    visible: root.selected !== null && root.selected.type === "image"
                    y: caption.height + Theme.stack.row
                    width: parent.width
                    height: parent.height - y
                    source: root.selected !== null && root.selected.type === "image" ? root.fileUrl(root.selected.id) : ""
                    sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
                    fillMode: Image.PreserveAspectFit
                    horizontalAlignment: Image.AlignLeft
                    verticalAlignment: Image.AlignTop
                    asynchronous: true
                }
            }
        }
    }

    Scrim {
        visible: root.confirming
        onClicked: confirm.rejected()
    }

    Dialog {
        id: confirm
        visible: root.confirming
        anchors.centerIn: parent
        title: "Clear the clipboard history?"
        message: "Pinned entries stay."
        actions: [
            { label: "Cancel", role: "cancel" },
            { label: "Clear", role: "accept", variant: "danger" }
        ]
        onAccepted: root.clearAll()
        onRejected: {
            root.confirming = false;
            search.forceActiveFocus(Qt.ShortcutFocusReason);
        }
    }
}
