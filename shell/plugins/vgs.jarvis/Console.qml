import QtQuick
import QtQuick.Templates as T
import Quickshell
import qs.Commons
import qs.Ui
import "Session.js" as Session
import "WidgetView.js" as WidgetView
import "SetupGate.js" as Gate
import "AccountProviders.js" as Providers

// Jarvis console: a keyboard-first window for typed turns. It asks the
// service through IPC, reads the service's bounded conversation status, and
// never owns the daemon or a transcript store.
FocusScope {
    id: root

    property var shell: null
    property var payload: ({})
    property string problem: ""
    property Item initialFocus: composerFocus
    readonly property var screen: shell === null ? null : shell.screens.current
    readonly property var values: shell === null ? ({}) : shell.status.values
    readonly property var detail: values.detail === undefined ? null : values.detail
    readonly property var state: detail === null || detail.state === undefined ? null : detail.state
    property int tab: 0
    property int selectedTask: 0
    readonly property var taskRows: Array.isArray(values.taskList) ? values.taskList : []
    readonly property var auditRows: Array.isArray(values.auditFailures) ? values.auditFailures.slice().reverse() : []
    readonly property var task: taskRows[selectedTask] === undefined ? null : taskRows[selectedTask]
    readonly property bool canStopTask: task !== null && ["starting", "working", "waiting"].includes(task.state)
    // Tasks.derive clears endedAt while the process is alive. A starting
    // process has no terminal to open yet; a failed turn can still be alive.
    readonly property bool canOpenTask: task !== null && task.endedAt === null && task.state !== "starting"
    property string draft: ""
    readonly property var refusal: Session.sayRefusal(state)
    readonly property bool ready: shell !== null && state !== null && refusal === null
    readonly property string stopKey: shell === null || shell.shortcut.keys.stop === undefined || shell.shortcut.keys.stop === null ? "" : shell.shortcut.keys.stop
    readonly property var conversation: Array.isArray(values.conversation) ? values.conversation : []
    readonly property var memoryInbox: Array.isArray(values.memoryInbox) ? values.memoryInbox : []
    readonly property string livePartial: state !== null && state.turn.kind === "collecting" ? state.turn.partial : ""
    readonly property var transcriptRows: rows()
    readonly property string hint: problem !== "" ? problem : refusalText(refusal)
    readonly property var messageLimit: Gate.messageLimit(Session.TRANSCRIPT_CHARS)
    // A duplex voice takes no typed message (Session.sayRefusal), so the
    // composer offers none: one line says how to talk instead.
    readonly property bool speechOnly: state !== null && state.engine.kind === "duplex"
    // The shortcut keys as people read them, the bar's own spelling.
    readonly property var spelledKeys: WidgetView.spelledKeys(shell === null ? null : shell.shortcut.keys, KeyNavLogic.keyCaps)
    // How to talk now: the sentence the Voice step and the bar say it with.
    readonly property string talkLine: Gate.talkHint(shell === null ? "hold" : shell.settings.mode, spelledKeys.talk) + "."
    // What the bar shows (WidgetView), whose title and first action the
    // status line under the console's purpose repeats.
    readonly property var barView: WidgetView.view(values, spelledKeys, shell === null ? "hold" : shell.settings.mode,
        shell === null ? null : Providers.cloudVoice(shell.settings.voiceProvider))
    // The Conversation tab's first control: the message box, or Stop where
    // one line stands in its place.
    readonly property Item composerFocus: speechOnly ? speechStop : entryField
    readonly property string speechOnlyText: speechOnlyLine(values.voiceRoute, talkLine)

    onComposerFocusChanged: {
        if (!root.activeFocus || root.tab !== 0) return;
        // Qt retains active focus when an item's branch becomes invisible.
        // tst_jarvis_console drives both replacements and outside focus.
        const replaced = speechOnly ? [messageInfo, entryField, sendButton, stopButton] : [speechHint, speechStop];
        const previous = replaced.find(item => item.activeFocus);
        if (previous !== undefined) composerFocus.forceActiveFocus(previous.focusReason);
    }

    function open(payloadJson) {
        payload = payloadJson ? JSON.parse(payloadJson) : {};
        problem = "";
        tab = 0;
        Qt.callLater(() => root.composerFocus.forceActiveFocus());
        Qt.callLater(followEnd);
    }

    function close() {}

    function focusTab() {
        layout.scrollArea.contentY = 0;
        const control = tab === 0 ? composerFocus : tab === 1 ? tasksBody : auditBody;
        control.forceActiveFocus(consoleTabs.activeFocus ? consoleTabs.focusReason : Qt.TabFocusReason);
        if (tab === 0) Qt.callLater(followEnd);
    }

    // Handle Backtab and Tab with Shift before the control's native traversal.
    // These controls have no Keys.forwardTo receivers:
    // https://doc.qt.io/qt-6/qml-qtquick-keys.html#key-handling-priorities
    function handleBacktab(event) {
        const backward = event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier));
        if (!backward || (event.modifiers & Qt.ControlModifier)) return false;
        consoleTabs.forceActiveFocus(Qt.BacktabFocusReason);
        event.accepted = true;
        return true;
    }

    function taskState(row) {
        const words = { starting: "Starting", working: "Working", waiting: "Waiting for you",
            "reported-ok": "Done as reported", failed: "Failed", "reported-failed": "Failed",
            stopped: "Stopped", lost: "Lost", exited: "Stopped", noisy: "Task record unreadable" };
        return words[row.state];
    }

    function taskDetail(row) {
        const failure = row.failure === null ? "" : typeof row.failure === "number" ? "Exited with code " + row.failure : String(row.failure);
        return taskState(row) + (failure === "" ? "" : " · " + failure);
    }

    function taskAction(action) {
        if (shell === null || task === null || (action === "stop" ? !canStopTask : !canOpenTask)) return;
        const reply = shell.ipc.call(action === "stop" ? "stop-task" : "open-task", task.id);
        problem = reply === "ok" ? "" : reply === "refused: jarvis=not-ready" ? "Jarvis is not ready"
            : action === "stop" ? "The coding task could not be stopped" : "The coding task could not be opened";
        // Stop disables its button when the task ends. Return to the list
        // before that transition, keeping the keyboard or pointer focus reason.
        if (reply === "ok" && action === "stop") tasksBody.forceActiveFocus(taskStopButton.focusReason);
    }

    // What a failed voice stream's cause says (Audit.js STREAM_CAUSES).
    readonly property var streamCauses: ({
        "input-silent": "the microphone sent only silence",
        "unheard": "the voice service heard no words",
        // A row keeps no provider, and the voice may have changed since.
        "key-refused": "the voice service refused the key",
        "voice-stopped": "the voice stopped after a problem"
    })

    function auditDetail(row) {
        const result = row.decision === "refuse" ? "Refused" : row.decision === "withhold" ? "Withheld"
            : row.outcome === "failed" ? "Failed" : "Result unknown";
        // Qt's QML String API supplies regex replacement:
        // https://doc.qt.io/qt-6/qtqml-javascript-functionlist.html#string-objects
        return result + (row.refusal === null ? "" : " · " + String(row.refusal).replace(/-/g, " "))
            + (row.cause === null ? "" : " · " + streamCauses[row.cause]);
    }

    onTaskRowsChanged: {
        taskCursor.rebuilt();
        selectedTask = Math.max(0, Math.min(selectedTask, taskRows.length - 1));
    }
    Keys.onPressed: event => {
        if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && (event.modifiers & Qt.ControlModifier)) {
            event.accepted = consoleTabs.nav.handle(event);
        }
    }
    onTabChanged: { problem = ""; Qt.callLater(focusTab); }

    // The bar's state line, the action of a state that needs one, then the
    // AI model, one fact a line in the bar tooltip's order. The action's
    // page reference stays whole for the LinkText that draws it.
    function stateLines() {
        const view = barView;
        const isModel = line => String(line).indexOf("AI model: ") === 0;
        const model = view.tooltipDetails.find(isModel);
        const action = view.state === "problem" || view.state === "off" ? view.tooltipDetails.find(line => !isModel(line)) : undefined;
        return [view.tooltip].concat(action === undefined ? [] : [action], model === undefined ? [] : [model]);
    }

    // The line in place of the message box under a voice that takes speech
    // only (ROUTE, the Voice provider reading), saying how to talk (TALK).
    function speechOnlyLine(route, talk) {
        return (route === undefined || route === null ? "This voice" : route.text) + " takes speech only. " + talk;
    }

    // The empty conversation's line: how to start one, by typing or, under a
    // voice that takes speech only (SPEECH), by talking (TALK).
    function emptyText(speech, talk) {
        return "No conversation yet. " + (speech ? PageReference.plain(talk) : "Type a message to start.");
    }

    // The status line's color for STATE, the bar's state: a warning only
    // while it says Jarvis cannot take a request, a problem or off.
    function stateColor(state) {
        return state === "problem" || state === "off" ? Theme.color.warning : Theme.color.textMuted;
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
        if (key === "duplex") return "Typing is unavailable with this voice provider: speak to Jarvis instead";
        if (key === "say-text") return "Use up to " + Gate.numberText(messageLimit.maximum) + " characters of plain text";
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
            if (root.tab !== 0) return;
            const item = memoryList.itemAt(index) || memoryList.itemAt(index - 1);
            if (item !== null && item.confirmButton !== undefined) item.confirmButton.forceActiveFocus();
            else root.composerFocus.forceActiveFocus();
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
        if (problem === "bootstrap") return "Not saved. Jarvis cannot rewrite " + Gate.homeReference("memory/MEMORY.md",
            { kind: values.homePath ? "ready" : "empty", path: values.homePath }, "/memory/MEMORY.md") + ".";
        if (problem === "write") return "Not saved. Jarvis could not write the note.";
        return "";
    }

    function followEnd() {
        if (tab !== 0) return;
        const view = layout.scrollArea;
        view.contentY = Math.max(0, view.contentHeight - view.height);
    }

    onTranscriptRowsChanged: if (tab === 0) Qt.callLater(followEnd)
    // A view at its end stays there while rows and memory cards lay out, so
    // the newest card shows whole; a view the user scrolled up stays put.
    property bool atEnd: true
    Connections {
        target: layout.scrollArea
        function onContentYChanged() {
            const view = layout.scrollArea;
            root.atEnd = view.contentY >= view.contentHeight - view.height - 1;
        }
        function onContentHeightChanged() { if (root.tab === 0 && root.atEnd) Qt.callLater(root.followEnd); }
    }
    implicitWidth: Math.floor(Math.min(Theme.size.window.width, OverlayState.room(screen).width))
    implicitHeight: Math.floor(Math.min(Theme.size.panel.maxHeight, OverlayState.windowRoom(screen).height))
    focus: true

    Pane {
        id: layout
        anchors.fill: parent
        container: "window"
        // Memory cards and a long transcript scroll inside the console, so
        // the window keeps its own height. The bubble places itself.
        maximumHeight: root.implicitHeight
        // The transcript is the pane's body, so the pane's one divider
        // marks it scrolled under the title and over the composer.
        Component.onCompleted: scrollArea.keyboardScroll = true

        title: "Jarvis console"
        subtitle: [
            Column {
                width: layout.contentWidth
                spacing: Theme.row.lineGap
                // The console's three jobs, so a first look says what it is for.
                Label {
                    width: parent.width
                    role: "hint"
                    text: (root.speechOnly ? "Talk to Jarvis" : "Type to Jarvis") + " and read its replies. Tasks shows the coding tasks it started. Audit shows actions it refused or that failed."
                    color: Theme.color.textMuted
                    wrapMode: Text.Wrap
                }
                Repeater {
                    model: root.stateLines()
                    // A Repeater builds its delegate before it parents it, so
                    // the width reads the pane, not `parent`.
                    LinkText {
                        required property string modelData
                        width: layout.contentWidth
                        role: "hint"
                        text: modelData
                        color: root.stateColor(root.barView.state)
                        wrapMode: Text.Wrap
                        onPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
                    }
                }
            }
        ]

        header: [
            Tabs {
                id: consoleTabs
                width: layout.contentWidth
                model: ["Conversation", "Tasks", "Audit"]
                currentIndex: root.tab
                // KeyNavigation assigns the explicit Tab/Backtab target.
                // https://doc.qt.io/qt-6/qml-qtquick-keynavigation.html
                KeyNavigation.tab: root.tab === 0 ? root.composerFocus : root.tab === 1 ? tasksBody : auditBody
                onCurrentIndexChanged: root.tab = currentIndex
            }
        ]

        Column {
            visible: root.tab === 0
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
                text: root.emptyText(root.speechOnly, root.talkLine)
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
                        LinkText {
                            width: parent.width
                            role: "body"
                            visible: modelData.problem !== ""
                            text: root.memoryProblemText(modelData.problem)
                            color: Theme.color.danger
                            wrapMode: Text.Wrap
                            onPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
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

        T.Control {
            id: tasksBody
            visible: root.tab === 1
            width: layout.contentWidth
            implicitHeight: taskColumn.implicitHeight
            focusPolicy: Qt.StrongFocus
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: event => {
                if (root.handleBacktab(event)) return;
                event.accepted = taskNav.handle(event);
            }
            FocusRing { target: tasksBody; outside: true }
            ListCursor { id: taskCursor }
            KeyNav {
                id: taskNav
                focusTarget: tasksBody
                count: root.taskRows.length
                currentIndex: root.selectedTask
                cursor: taskCursor
                wrap: false
                flickable: layout.scrollArea
                itemAt: index => taskList.itemAt(index)
                onMoved: index => root.selectedTask = index
                onActivated: root.taskAction("open")
            }
            contentItem: Column {
                id: taskColumn
                width: tasksBody.width
                Repeater {
                    id: taskList
                    // Keyed by the task's id, so a republished list keeps
                    // each task's row and the hovered row keeps the plate
                    // (ListCursor.rebuilt).
                    model: ScriptModel { values: root.taskRows; objectProp: "id" }
                    // keyboard-path: Tasks owns the cursor through KeyNav; its footer acts on the selection
                    ListItem {
                        required property var modelData
                        required property int index
                        width: tasksBody.width
                        text: modelData.goal
                        secondary: root.taskDetail(modelData)
                        trailing: [Badge { text: modelData.agent; verbatim: true }]
                        secondaryTone: ["failed", "reported-failed", "lost"].includes(modelData.state) ? "danger" : ""
                        cursor: taskCursor
                        highlighted: root.selectedTask === index
                        focusPolicy: Qt.NoFocus
                        onClicked: { root.selectedTask = index; tasksBody.forceActiveFocus(Qt.MouseFocusReason); }
                    }
                }
                EmptyState { width: tasksBody.width; visible: root.taskRows.length === 0; iconName: "terminal"; text: "No coding tasks" }
            }
        }

        T.Control {
            id: auditBody
            visible: root.tab === 2
            width: layout.contentWidth
            padding: Theme.listItem.paddingX
            implicitHeight: implicitContentHeight + topPadding + bottomPadding
            focusPolicy: Qt.StrongFocus
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: event => {
                if (root.handleBacktab(event)) return;
                if (layout.scrollArea.handleScrollKey(event)) event.accepted = true;
            }
            FocusRing { target: auditBody; outside: true }
            // Audit rows are read-only, like the transcript, and take no cursor.
            // Each record is one group of a GroupList, so a hairline parts it from the next.
            // Control sizes its content inside padding; rows use that content width.
            // https://doc.qt.io/qt-6/qml-qtquick-controls-control.html#contentItem-prop
            contentItem: GroupList {
                id: auditList
                Repeater {
                    model: root.auditRows
                    Column {
                        required property var modelData
                        width: auditList.width
                        spacing: Theme.row.lineGap
                        Label { width: parent.width; role: "hint"; text: new Date(modelData.time).toLocaleTimeString(); textFormat: Text.PlainText; color: Theme.color.textMuted }
                        Label { width: parent.width; role: "bodyStrong"; text: modelData.tool; textFormat: Text.PlainText; wrapMode: Text.Wrap }
                        Label { width: parent.width; role: "body"; text: root.auditDetail(modelData); textFormat: Text.PlainText; color: Theme.color.danger; wrapMode: Text.Wrap }
                    }
                }
                EmptyState { width: auditList.width; visible: root.auditRows.length === 0; iconName: "shield-alert"; text: "No recent failures" }
            }
        }

        footer: [
            Column {
                visible: root.tab === 1
                width: layout.contentWidth
                spacing: Theme.stack.inline
                Label { width: parent.width; role: "hint"; visible: root.problem !== ""; text: root.problem; color: Theme.color.danger; wrapMode: Text.Wrap }
                Row {
                    spacing: Theme.control.gap
                    Button { text: "Open"; iconName: "external-link"; enabled: root.canOpenTask; onClicked: root.taskAction("open") }
                    Button { id: taskStopButton; text: "Stop"; iconName: "square"; enabled: root.canStopTask; onClicked: root.taskAction("stop") }
                }
            },
            Column {
                id: composer
                visible: root.tab === 0
                width: layout.contentWidth
                spacing: Theme.stack.inline

                // Under a voice that takes speech only, one line in place of
                // the message box and Send; Stop stays beside it.
                Row {
                    width: parent.width
                    spacing: Theme.control.gap
                    visible: root.speechOnly
                    // The talk sentence links the Talk key setting while none is set.
                    LinkText {
                        id: speechHint
                        width: parent.width - speechStop.width - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        role: "hint"
                        text: root.speechOnlyText
                        color: Theme.color.textMuted
                        wrapMode: Text.Wrap
                        onPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
                    }
                    IconButton {
                        id: speechStop
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "square"
                        label: "Stop Jarvis"
                        tooltip: root.stopKey === "" ? "Stop Jarvis" : "Stop Jarvis " + root.stopKey
                        onClicked: root.stop()
                        Keys.onPressed: event => root.handleBacktab(event)
                    }
                }

                Row {
                    width: parent.width
                    spacing: Theme.control.gap
                    visible: !root.speechOnly
                    Label {
                        width: parent.width - messageInfo.width - parent.spacing
                        role: "hint"
                        text: root.hint
                        color: root.problem !== "" ? Theme.color.danger : root.refusal === null ? Theme.color.textMuted : Theme.color.warning
                        wrapMode: Text.Wrap
                    }
                    InfoButton {
                        id: messageInfo
                        title: "Message length"
                        info: root.messageLimit.info
                    }
                }

                Column {
                    width: parent.width
                    visible: !root.speechOnly
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
                                if (root.handleBacktab(event)) return;
                                if ((event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) && layout.scrollArea.handleScrollKey(event)) event.accepted = true;
                            }
                        }
                        Button {
                            id: sendButton
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Send"
                            iconName: "send"
                            disabledReason: !root.ready ? root.refusalText(root.refusal) : entryField.text.trim() === "" ? "Type a message to Jarvis first" : ""
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
                    KeyHints {
                        afterActions: true
                        hints: root.speechOnly ? [] : [
                            { key: "Enter", text: "Send" },
                            { key: root.shell === null ? "" : root.shell.shortcut.keys.talk || "", text: "Talk" },
                            { key: root.stopKey, text: "Stop" }
                        ]
                        visible: !root.speechOnly
                    }
                }
            }
        ]
    }
}
