import QtQuick
import qs.Commons
import qs.Ui
import "Session.js" as Session
import "WidgetView.js" as WidgetView

// Jarvis console: a keyboard-first window for typed turns. It asks the
// service through IPC, reads the service's bounded conversation status, and
// never owns the daemon or a transcript store.
FocusScope {
    id: root

    property var shell: null
    property var payload: ({})
    property string problem: ""
    property Item initialFocus: entryField
    readonly property var screen: shell === null ? null : shell.screens.current
    readonly property var values: shell === null ? ({}) : shell.status.values
    readonly property var detail: values.detail === undefined ? null : values.detail
    readonly property var state: detail === null || detail.state === undefined ? null : detail.state
    property string draft: ""
    readonly property var refusal: Session.sayRefusal(state)
    readonly property bool ready: shell !== null && state !== null && refusal === null
    readonly property string stopKey: shell === null || shell.shortcut.keys.stop === undefined || shell.shortcut.keys.stop === null ? "" : shell.shortcut.keys.stop
    readonly property var conversation: Array.isArray(values.conversation) ? values.conversation : []
    readonly property var memoryInbox: Array.isArray(values.memoryInbox) ? values.memoryInbox : []
    readonly property string livePartial: state !== null && state.turn.kind === "collecting" ? state.turn.partial : ""
    readonly property var transcriptRows: rows()
    readonly property string hint: problem !== "" ? problem : refusalText(refusal)

    function open(payloadJson) {
        payload = payloadJson ? JSON.parse(payloadJson) : {};
        problem = "";
        Qt.callLater(() => entryField.forceActiveFocus());
        Qt.callLater(followEnd);
    }

    function close() {}

    // The bar's state line, with the action of a state that needs one.
    function stateText() {
        const view = WidgetView.view(values, WidgetView.spelledKeys(shell === null ? null : shell.shortcut.keys, KeyNavLogic.keyCaps),
            shell === null ? "hold" : shell.settings.mode);
        return view.state === "problem" || view.state === "off" ? view.tooltip + ". " + view.tooltipDetails[0] : view.tooltip;
    }

    function rows() {
        const result = conversation.slice();
        if (livePartial.trim() !== "") result.push({ gen: state.gen, role: "user", text: livePartial, stage: "partial" });
        return result;
    }

    function speaker(role) { return role === "user" ? "You" : "Jarvis"; }

    function refusalText(key) {
        if (key === null) return draft.trim() === "" ? "Type a message to Jarvis" : "Enter sends the message";
        if (key === "muted") return "Unmute Jarvis to type";
        if (key === "speaking") return "Wait for Jarvis to finish speaking, or press Stop";
        if (key === "busy") return "Wait, or press Stop";
        if (key === "held") return "Confirm or cancel the request first";
        if (key === "duplex") return "This voice mode owns the turn";
        if (key === "say-text") return "Message too long or has unsupported characters";
        return "Jarvis is not ready";
    }

    function refusalReply(reply) {
        if (reply === "refused: jarvis=not-ready") return "Jarvis is not ready";
        if (reply.indexOf("refused: say=") === 0) return refusalText(reply.slice("refused: say=".length));
        return "Jarvis did not send the message";
    }

    function expectedRefusal(reply) {
        return reply === "refused: jarvis=not-ready" || reply.indexOf("refused: say=") === 0;
    }

    function sendMessage() {
        if (shell === null || entryField.text.trim() === "") return;
        const reply = shell.ipc.call("say", entryField.text);
        if (reply === "ok") {
            entryField.text = "";
            problem = "";
        } else {
            problem = refusalReply(reply);
            if (!expectedRefusal(reply)) console.warn("jarvis console: " + reply);
        }
    }

    function stop() {
        if (shell === null) return;
        const reply = shell.ipc.call("stop", "");
        if (reply !== "ok") {
            problem = "Jarvis did not stop";
            console.warn("jarvis console: " + reply);
        }
    }

    function answerMemory(kind, entry, index) {
        if (shell === null) return;
        const reply = shell.ipc.call(kind === "confirm" ? "memory-confirm" : "memory-discard",
            JSON.stringify({ id: entry.id, hash: entry.hash }));
        if (reply === "ok") {
            problem = "";
            focusAfterMemory(index);
            return;
        }
        problem = kind === "confirm" ? "Memory note not confirmed" : "Memory note not discarded";
        console.warn("jarvis console: " + reply);
    }

    function focusAfterMemory(index) {
        Qt.callLater(() => Qt.callLater(() => {
            const item = memoryList.itemAt(index) || memoryList.itemAt(index - 1);
            if (item !== null && item.confirmButton !== undefined) item.confirmButton.forceActiveFocus();
            else entryField.forceActiveFocus();
        }));
    }

    function originText(labels) {
        const shown = labels.filter(label => label !== "home");
        return "Sources: " + (shown.length === 0 ? "home" : shown.join(", "));
    }

    function memoryProblemText(problem) {
        if (problem === "exists") return "Not saved. The note already exists.";
        if (problem === "conflict") return "Not saved. The note changed after Jarvis read it.";
        if (problem === "link") return "Not saved. The note path contains a link.";
        if (problem === "secret") return "Not saved. The note contains a secret.";
        if (problem === "hash") return "Not saved. The pending note changed.";
        if (problem === "bootstrap") return "Not saved. Jarvis cannot rewrite MEMORY.md.";
        if (problem === "write") return "Not saved. Jarvis could not write the note.";
        return "";
    }

    function followEnd() {
        const view = layout.scrollArea;
        view.contentY = Math.max(0, view.contentHeight - view.height);
    }

    onTranscriptRowsChanged: Qt.callLater(followEnd)
    implicitWidth: Math.floor(Math.min(Theme.size.window.width, OverlayState.room(screen).width))
    implicitHeight: Math.floor(Math.min(Theme.size.panel.maxHeight, OverlayState.room(screen).height))
    focus: true

    Pane {
        id: layout
        anchors.fill: parent
        container: "window"
        // The transcript is the pane's body, so the pane's one divider
        // marks it scrolled under the title and over the composer.
        Component.onCompleted: scrollArea.keyboardScroll = true

        title: "Jarvis console"
        subtitle: [
            Column {
                width: layout.contentWidth
                spacing: Theme.row.lineGap
                Label {
                    width: parent.width
                    role: "hint"
                    text: root.stateText()
                    color: root.refusal === null ? Theme.color.textMuted : Theme.color.warning
                    wrapMode: Text.Wrap
                }
            }
        ]

        Column {
            width: layout.contentWidth
            spacing: Theme.stack.row

            // Conversation rows are read-only transcript entries. They
            // take no selection, so this list has no ListCursor.
            Repeater {
                model: root.transcriptRows
                Column {
                    required property var modelData
                    width: layout.contentWidth
                    spacing: Theme.row.lineGap

                    Label {
                        width: parent.width
                        role: "label"
                        text: root.speaker(modelData.role)
                        color: Theme.color.textMuted
                        elide: Text.ElideRight
                    }
                    Label {
                        width: parent.width
                        role: modelData.role === "user" ? "bodyStrong" : "body"
                        text: String(modelData.text)
                        wrapMode: Text.Wrap
                        color: modelData.stage === "partial" ? Theme.color.textMuted : Theme.color.text
                    }
                }
            }
            EmptyState {
                width: layout.contentWidth
                visible: root.transcriptRows.length === 0 && root.memoryInbox.length === 0
                iconName: "message-circle"
                text: "No conversation yet. Type a message to start."
            }

            Repeater {
                id: memoryList
                model: root.memoryInbox
                Surface {
                    required property var modelData
                    required property int index
                    property alias confirmButton: confirmButton
                    width: layout.contentWidth
                    height: card.implicitHeight + 2 * Theme.stack.group
                    level: "raised"

                    Column {
                        id: card
                        anchors.centerIn: parent
                        width: parent.width - 2 * Theme.stack.group
                        spacing: Theme.stack.inline
                        Label {
                            width: parent.width
                            role: "label"
                            text: modelData.kind === "replace" ? "Memory note edit waiting" : "Memory note waiting"
                            color: Theme.color.textMuted
                            textFormat: Text.PlainText
                        }
                        Label {
                            width: parent.width
                            role: "bodyStrong"
                            text: String(modelData.title)
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                        }
                        Label {
                            width: parent.width
                            role: "hint"
                            text: (modelData.kind === "replace" ? "Replaces " : "Adds ") + String(modelData.target) + ". " + root.originText(modelData.labels)
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                        }
                        Label {
                            width: parent.width
                            role: "body"
                            visible: modelData.problem !== ""
                            text: root.memoryProblemText(modelData.problem)
                            color: Theme.color.danger
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                        }
                        Label {
                            width: parent.width
                            role: "body"
                            text: String(modelData.text)
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                        }
                        Row {
                            spacing: Theme.control.gap
                            Button {
                                id: confirmButton
                                text: "Confirm"
                                iconName: "check"
                                onClicked: root.answerMemory("confirm", modelData, index)
                            }
                            Button {
                                text: "Discard"
                                iconName: "trash-2"
                                variant: "danger"
                                onClicked: root.answerMemory("discard", modelData, index)
                            }
                        }
                    }
                }
            }
        }

        footer: [
            Column {
                id: composer
                width: layout.contentWidth
                spacing: Theme.stack.inline

                Label {
                    width: parent.width
                    role: "hint"
                    text: root.hint
                    color: root.problem !== "" ? Theme.color.danger : root.refusal === null ? Theme.color.textMuted : Theme.color.warning
                    wrapMode: Text.Wrap
                }

                Row {
                    width: parent.width
                    spacing: Theme.control.gap

                    TextField {
                        id: entryField
                        width: parent.width - sendButton.width - stopButton.width - parent.spacing - parent.spacing
                        placeholderText: "Message Jarvis"
                        maximumLength: Session.TRANSCRIPT_CHARS
                        onTextChanged: root.draft = text
                        Keys.onReturnPressed: event => { root.sendMessage(); event.accepted = true; }
                        Keys.onEnterPressed: event => { root.sendMessage(); event.accepted = true; }
                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) && layout.scrollArea.handleScrollKey(event)) event.accepted = true;
                        }
                    }
                    Button {
                        id: sendButton
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Send"
                        iconName: "send"
                        enabled: root.ready && entryField.text.trim() !== ""
                        onClicked: root.sendMessage()
                    }
                    IconButton {
                        id: stopButton
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "square"
                        label: "Stop Jarvis"
                        tooltip: root.stopKey === "" ? "Stop Jarvis" : "Stop Jarvis " + root.stopKey
                        onClicked: root.stop()
                    }
                }
            }
        ]
    }
}
