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

    function stateText() {
        return WidgetView.view(values).tooltip;
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

    function followEnd() {
        transcript.contentY = Math.max(0, transcript.contentHeight - transcript.height);
    }

    onTranscriptRowsChanged: Qt.callLater(followEnd)
    implicitWidth: screen === null ? Theme.size.window.width : Math.floor(Math.min(Theme.size.window.width, screen.width - Theme.size.window.gutter - Theme.size.window.gutter))
    implicitHeight: screen === null ? Theme.size.panel.maxHeight : Math.floor(Math.min(Theme.size.panel.maxHeight, screen.height - Theme.size.window.gutter - Theme.size.window.gutter))
    focus: true

    Pane {
        id: layout
        anchors.fill: parent
        container: "window"

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

        ScrollArea {
            id: transcript
            width: layout.contentWidth
            height: Math.max(Theme.size.control.lg, layout.height - layout.headerHeight - composer.height - Theme.stack.group - Theme.stack.group)
            keyboardScroll: true
            contentPadding: Theme.focusRing.width + Theme.focusRing.offset

            Column {
                width: transcript.contentWidth
                spacing: Theme.stack.row

                // Conversation rows are read-only transcript entries. They
                // take no selection, so this list has no ListCursor.
                Repeater {
                    model: root.transcriptRows
                    Column {
                        required property var modelData
                        width: transcript.contentWidth
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
                    width: transcript.contentWidth
                    visible: root.transcriptRows.length === 0
                    iconName: "message-circle"
                    text: "No conversation yet. Type a message to start."
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
                            if ((event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) && transcript.handleScrollKey(event)) event.accepted = true;
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
