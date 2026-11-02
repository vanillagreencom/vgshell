import QtQuick
import QtQuick.Templates as T
import Quickshell
import qs.Commons
import qs.Ui
import "Session.js" as Session
import "WidgetView.js" as WidgetView
import "SetupGate.js" as Gate
import "AccountProviders.js" as Providers
import "History.js" as History

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
    readonly property var asksState: values.ownerAsks === undefined ? ({ kind: "reading" }) : values.ownerAsks === null
        ? ({ kind: "unavailable", cause: "The ask page is unavailable because the console is full. Refresh to read it again." }) : values.ownerAsks
    readonly property bool asksReady: asksState.kind === "ready"
    readonly property var activeAsks: asksReady ? asksState.active : []
    readonly property var snoozedAsks: asksReady ? asksState.snoozed : []
    readonly property var askAnswer: values.ownerAskAnswer === undefined ? null : values.ownerAskAnswer
    property bool snoozedExpanded: false
    property string askProblem: ""
    property string pendingAsk: ""
    property var pendingRequest: null
    property var unconfirmedRequest: null
    property int askSerial: 0
    property var editingAsk: null
    property string editingHome: ""
    property string editingAction: ""
    property Item returnAskFocus: null
    property string historyQuery: ""
    property int historyType: 0
    readonly property var historyGroups: History.conversations(conversation, historyQuery)
    readonly property var historyProblems: History.problems(auditRows, historyQuery)
    readonly property bool showConversations: tab === 2 && (historyType === 0 || historyType === 1)
    readonly property bool showTasks: tab === 2 && (historyType === 0 || historyType === 2)
    readonly property bool showProblems: tab === 2 && (historyType === 0 || historyType === 3)
    readonly property string currentHome: shell === null ? "" : shell.settings.home
    onCurrentHomeChanged: { editingAsk = null; pendingAsk = ""; pendingRequest = null; unconfirmedRequest = null; askProblem = ""; }
    onAskAnswerChanged: {
        if (askAnswer === null || (askAnswer.requestId !== pendingAsk
            && (unconfirmedRequest === null || askAnswer.requestId !== unconfirmedRequest.requestId))) return;
        unconfirmedRequest = askAnswer.kind === "unknown" ? (pendingRequest === null ? unconfirmedRequest : pendingRequest) : null;
        pendingRequest = null;
        pendingAsk = "";
        askProblem = askAnswer.kind === "accepted" ? "" : askAnswer.cause;
        if (unconfirmedRequest !== null) askProblem += " Request: " + unconfirmedRequest.requestId;
        if (askAnswer.kind === "accepted") closeAskEditor();
    }

    onAsksStateChanged: {
        if (asksState.kind !== "unavailable" || pendingRequest === null) return;
        unconfirmedRequest = pendingRequest;
        pendingRequest = null;
        pendingAsk = "";
        askProblem = "The action was not confirmed. Refresh and review the original ask before trying again. Request: " + unconfirmedRequest.requestId;
    }

    function refreshAsks() {
        if (shell === null) return;
        const reply = shell.ipc.call("owner-asks-refresh", "");
        askProblem = reply !== "ok" ? "Jarvis is not ready to refresh your asks."
            : unconfirmedRequest === null ? ""
            : "The action was not confirmed. Review the original ask before trying again. Request: " + unconfirmedRequest.requestId;
    }
    function askPage(view, first) {
        if (!asksReady || shell === null) return;
        const cursor = first ? null : asksState[view + "NextCursor"];
        const reply = shell.ipc.call("owner-asks-page", JSON.stringify({ view: view, cursor: cursor, expectedRevision: asksState.revision }));
        askProblem = reply === "ok" ? "" : "This page changed. Press Refresh to start again.";
    }
    function askActions(row) {
        return ["reply", "done", "later"].map(action => ({ id: action,
            label: action === "reply" ? "Reply" : action === "done" ? "Done" : "Later",
            disabledReason: pendingAsk !== "" ? "Wait for the current ask action to finish."
                : row.actions[action].allowed ? "" : row.actions[action].reason }));
    }
    function chooseAsk(action, row, source) {
        if (pendingAsk !== "" || !row.actions[action].allowed) return;
        askProblem = "";
        returnAskFocus = source;
        if (action === "done") { sendAsk(action, row, "", null); return; }
        editingAsk = row;
        editingHome = asksState.homeId;
        editingAction = action;
        replyField.text = unconfirmedRequest !== null && unconfirmedRequest.id === row.id && unconfirmedRequest.action === action
            ? unconfirmedRequest.text : "";
        const tomorrow = new Date();
        tomorrow.setDate(tomorrow.getDate() + 1);
        laterDate.date = laterDate.stamp(tomorrow.getFullYear(), tomorrow.getMonth() + 1, tomorrow.getDate());
        laterTime.currentIndex = 0;
        Qt.callLater(() => askDialog.forceActiveFocus(Qt.OtherFocusReason));
    }
    function closeAskEditor() {
        if (editingAsk === null) return;
        editingAsk = null;
        Qt.callLater(() => {
            if (returnAskFocus !== null && returnAskFocus.visible) returnAskFocus.forceActiveFocus(Qt.OtherFocusReason);
            else if (root.tab === 1) asksBody.forceActiveFocus(Qt.OtherFocusReason);
        });
    }
    function laterInstant() {
        const date = laterDate.parse(laterDate.displayText);
        if (date === null) return null;
        return new Date(date.y, date.m - 1, date.d, [9, 12, 17][laterTime.currentIndex]).toISOString();
    }
    function editorReason() {
        if (editingAsk === null || !asksReady || asksState.homeId !== editingHome) return "This ask changed. Close this dialog and refresh.";
        if (pendingAsk !== "") return "Wait for the current ask action to finish.";
        if (editingAction === "reply") return replyField.text.trim() === "" ? "Write your reply first."
            : /[\x00-\x09\x0b-\x1f\x7f]/.test(replyField.text) ? "Remove control characters from your reply."
            : replyField.text.length > 4096 ? "Use up to 4,096 characters in your reply." : "";
        const until = laterInstant();
        return until === null ? "Choose a date from the calendar." : Date.parse(until) <= Date.now() ? "Choose a future date and time." : "";
    }
    function submitAskEditor() {
        if (editorReason() !== "") return;
        sendAsk(editingAction, editingAsk, editingAction === "reply" ? replyField.text : "", editingAction === "later" ? laterInstant() : null);
    }
    function sendAsk(action, row, text, until) {
        if (shell === null || !asksReady || pendingAsk !== "") return;
        const sameUnconfirmed = unconfirmedRequest !== null && unconfirmedRequest.action === action
            && unconfirmedRequest.id === row.id && unconfirmedRequest.text === text && unconfirmedRequest.until === until;
        const requestId = sameUnconfirmed ? unconfirmedRequest.requestId : "console:" + Date.now() + ":" + (++askSerial);
        const request = { action: action, id: row.id,
            requestId: requestId, expectedRevision: sameUnconfirmed ? unconfirmedRequest.expectedRevision : row.revision, text: text, until: until };
        const reply = shell.ipc.call("owner-ask-action", JSON.stringify(request));
        if (reply === "ok") { pendingRequest = request; pendingAsk = requestId; }
        else askProblem = "This ask could not be sent. Refresh before trying again.";
    }
    function openAskLink(row) {
        if (shell === null) return;
        const reply = shell.run.detached(DesktopLaunch.open(row.link.url));
        askProblem = reply === "ok" ? "" : "The original thread could not be opened.";
    }
    function timeText(at) { return new Date(at).toLocaleTimeString(); }
    function dateText(at) { return new Date(at).toLocaleDateString(); }
    function askTime(row) { return "since " + dateText(Date.parse(row.askedAt)) + ", " + timeText(Date.parse(row.askedAt)); }
    function askState(row) { return row.state === "checking" ? "Checking…" : row.state === "snoozed" ? "Snoozed" : row.kind === "fleet-approval" ? "Fleet approval" : row.kind === "tracker-item" ? "Your approval" : "Needs reply"; }
    function problemAction(row) {
        if (row.settings) root.shell.surfaces.openPage("vgs.jarvis", "Settings");
        else { root.tab = 0; Qt.callLater(() => root.composerFocus.forceActiveFocus()); }
    }

    property int selectedTask: 0
    readonly property var taskRows: History.tasks(Array.isArray(values.taskList) ? values.taskList : [], historyQuery)
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
        editingAsk = null;
        askProblem = "";
        refreshAsks();
        Qt.callLater(() => root.composerFocus.forceActiveFocus());
        Qt.callLater(followEnd);
    }

    function close() {}

    function focusTab() {
        layout.scrollArea.contentY = 0;
        const control = tab === 0 ? composerFocus : tab === 1 ? asksBody : historySearch;
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
    implicitHeight: Math.floor(OverlayState.windowRoom(screen).height)
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
                    text: (root.speechOnly ? "Talk to Jarvis" : "Type to Jarvis") + " in Now. Needs you holds your asks. History shows conversations, tasks and problems."
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

        header: Column {
            width: layout.contentWidth
            spacing: Theme.stack.group
            Tabs {
                id: consoleTabs
                width: parent.width
                model: ["Now", "Needs you", "History"]
                unreadCounts: root.asksReady && root.asksState.activeCount > 0 ? ({ "Needs you": root.asksState.activeCount }) : ({})
                currentIndex: root.tab
                KeyNavigation.tab: root.tab === 0 ? root.composerFocus : root.tab === 1 ? asksBody : historySearch
                onCurrentIndexChanged: root.tab = currentIndex
            }
            Row {
                visible: root.tab === 2
                width: parent.width
                spacing: Theme.stack.group
                Item {
                    width: parent.width - historyFilter.width - parent.spacing
                    height: historySearch.implicitHeight
                    TextField {
                        id: historySearch
                        x: -sidePadding
                        width: parent.width
                        placeholderText: "Search conversations, tasks and problems"
                        leadingIcon: "search"
                        rightPadding: 0
                        topPadding: 0
                        bottomPadding: 0
                        onTextChanged: root.historyQuery = text
                        Keys.onPressed: event => root.handleBacktab(event)
                        Component.onCompleted: { background.color = "transparent"; background.border.width = 0; }
                    }
                    Rectangle {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                        height: Theme.border.thin
                        color: Theme.textField.borderColor
                    }
                }
                ResultsFilter {
                    id: historyFilter
                    accessibleLabel: "Filter history results"
                    model: ["All types", "Conversations", "Tasks", "Problems"]
                    currentIndex: root.historyType
                    onActivated: index => root.historyType = index
                }
            }
        }

        Column {
            visible: root.tab === 0
            width: layout.contentWidth
            spacing: Theme.stack.row

            Repeater {
                model: root.transcriptRows
                MessageRow {
                    required property var modelData
                    width: layout.contentWidth
                    sender: root.speaker(modelData.role)
                    timeText: modelData.at === undefined ? "Listening" : root.timeText(modelData.at)
                    initials: modelData.role === "user" ? "Y" : ""
                    avatarIcon: modelData.role === "assistant" ? "vgs-letter-j" : ""
                    bodyText: String(modelData.text)
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
            id: asksBody
            visible: root.tab === 1
            width: layout.contentWidth
            implicitHeight: asksColumn.implicitHeight
            focusPolicy: Qt.StrongFocus
            Keys.onPressed: event => {
                if (root.handleBacktab(event)) return;
                if (layout.scrollArea.handleScrollKey(event)) event.accepted = true;
            }
            FocusRing { target: asksBody; outside: true }
            contentItem: Column {
                id: asksColumn
                width: asksBody.width
                spacing: Theme.stack.group
                Column {
                    width: parent.width; spacing: Theme.row.lineGap
                    Label { role: "bodyStrong"; text: root.asksReady ? root.asksState.activeCount + " waiting for you" : root.asksState.kind === "reading" ? "Reading your asks…" : "Your asks are unavailable" }
                    Label { role: "hint"; width: parent.width; wrapMode: Text.Wrap; color: Theme.color.textMuted; text: root.asksState.kind === "unavailable" ? root.asksState.cause : "From your main Jarvis session" }
                }
                Label { visible: root.askProblem !== ""; width: parent.width; role: "hint"; text: root.askProblem; color: Theme.color.danger; wrapMode: Text.Wrap }
                GroupList {
                    width: parent.width
                    Repeater {
                        id: activeAskRows
                        // ScriptModel string keys retain delegates on Quickshell0.3.1; current payloads stay in the canonical page (DeviceList.qml).
                        model: ScriptModel { values: root.activeAsks.map(row => row.id) }
                        MessageRow {
                            id: activeAskRow
                            required property var modelData
                            readonly property var ask: root.activeAsks.find(row => row.id === modelData)
                            readonly property bool live: ask !== undefined
                            visible: live
                            width: asksColumn.width
                            sender: live ? ask.askedBy.name : ""
                            timeText: live ? root.askTime(ask) : ""
                            initials: live ? ask.askedBy.name.slice(0, 1).toUpperCase() : ""
                            avatarIcon: live && ask.kind === "jarvis-ask" ? "vgs-letter-j" : ""
                            title: live ? ask.what : ""
                            bodyText: !live || ask.statusText === undefined ? "" : ask.statusText
                            linkText: live ? ask.link.label : ""
                            stateText: live ? root.askState(ask) : ""
                            stateTone: live && ask.state === "checking" ? "info" : "warning"
                            actions: live ? root.askActions(ask) : []
                            onLinkActivated: if (live) root.openAskLink(ask)
                            onActionTriggered: action => { if (live) root.chooseAsk(action, ask, actionAt(["reply", "done", "later"].indexOf(action))); }
                        }
                    }
                }
                EmptyState { visible: root.asksReady && root.activeAsks.length === 0; width: parent.width; iconName: "circle-check"; text: "No asks need you now" }
                RowActions {
                    visible: root.asksReady
                    RowAction { text: "Next asks"; visible: root.asksReady && root.asksState.activeNextCursor !== null; disabledReason: root.pendingAsk === "" ? "" : "Wait for the current ask action to finish."; onClicked: root.askPage("active", false) }
                    RowAction { text: "Back to first"; visible: root.asksReady && root.asksState.activeCursor !== null; disabledReason: root.pendingAsk === "" ? "" : "Wait for the current ask action to finish."; onClicked: root.askPage("active", true) }
                }
                Section {
                    visible: root.snoozedExpanded && root.asksReady
                    title: "Snoozed"
                    rowSpacing: Theme.stack.group
                    GroupList {
                        width: parent.width
                        Repeater {
                            // ScriptModel string keys retain delegates on Quickshell0.3.1; current payloads stay in the canonical page (DeviceList.qml).
                            model: ScriptModel { values: root.snoozedAsks.map(row => row.id) }
                            MessageRow {
                                required property var modelData
                                readonly property var ask: root.snoozedAsks.find(row => row.id === modelData)
                                readonly property bool live: ask !== undefined
                                visible: live
                                width: asksColumn.width
                                sender: live ? ask.askedBy.name : ""
                                timeText: live ? root.askTime(ask) : ""
                                initials: live ? ask.askedBy.name.slice(0, 1).toUpperCase() : ""
                                avatarIcon: live && ask.kind === "jarvis-ask" ? "vgs-letter-j" : ""
                                title: live ? ask.what : ""
                                bodyText: live ? "Returns " + root.dateText(Date.parse(ask.snoozedUntil)) + " at " + root.timeText(Date.parse(ask.snoozedUntil)) + "." : ""
                                linkText: live ? ask.link.label : ""
                                stateText: "Snoozed"
                                actions: live ? root.askActions(ask) : []
                                onLinkActivated: if (live) root.openAskLink(ask)
                                onActionTriggered: action => { if (live) root.chooseAsk(action, ask, actionAt(["reply", "done", "later"].indexOf(action))); }
                            }
                        }
                    }
                    EmptyState { visible: root.snoozedAsks.length === 0; width: parent.width; iconName: "clock"; text: "No snoozed asks" }
                    RowActions {
                        RowAction { text: "Next snoozed asks"; visible: root.asksReady && root.asksState.snoozedNextCursor !== null; onClicked: root.askPage("snoozed", false) }
                        RowAction { text: "Back to first snoozed"; visible: root.asksReady && root.asksState.snoozedCursor !== null; onClicked: root.askPage("snoozed", true) }
                    }
                }
            }
        }

        Column {
            visible: root.showConversations
            width: layout.contentWidth
            spacing: Theme.stack.group
            Repeater {
                model: root.historyGroups
                Section {
                    required property var modelData
                    width: layout.contentWidth
                    title: root.dateText(modelData.at) + " · Session " + root.timeText(modelData.startedAt)
                    GroupList {
                        width: parent.width
                        Repeater {
                            model: modelData.rows
                            MessageRow {
                                required property var modelData
                                width: layout.contentWidth
                                sender: root.speaker(modelData.role)
                                timeText: root.timeText(modelData.at)
                                initials: modelData.role === "user" ? "Y" : ""
                                avatarIcon: modelData.role === "assistant" ? "vgs-letter-j" : ""
                                bodyText: modelData.text
                            }
                        }
                    }
                }
            }
            EmptyState { visible: root.historyGroups.length === 0; width: parent.width; iconName: "message-circle"; text: root.historyQuery === "" ? "No conversations yet" : "No matching conversations" }
        }

        T.Control {
            id: tasksBody
            visible: root.showTasks
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
                SectionHeader { text: "Coding tasks"; width: parent.width }
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
            visible: root.showProblems
            width: layout.contentWidth
            implicitHeight: auditColumn.implicitHeight
            focusPolicy: Qt.StrongFocus
            Keys.onPressed: event => {
                if (root.handleBacktab(event)) return;
                if (layout.scrollArea.handleScrollKey(event)) event.accepted = true;
            }
            FocusRing { target: auditBody; outside: true }
            contentItem: Section {
                id: auditColumn
                title: "Problems"
                info: "This list holds the newest 20 failures. Search and the type filter apply to the records still in this list."
                GroupList {
                    id: auditList
                    width: parent.width
                    Repeater {
                        model: root.historyProblems
                        MessageRow {
                            required property var modelData
                            width: auditList.width
                            sender: "Jarvis"
                            avatarIcon: "vgs-letter-j"
                            timeText: root.dateText(modelData.at) + ", " + root.timeText(modelData.at)
                            title: modelData.title
                            bodyText: modelData.body
                            linkText: modelData.action
                            onLinkActivated: root.problemAction(modelData)
                        }
                    }
                    EmptyState { width: parent.width; visible: root.historyProblems.length === 0; iconName: "shield-check"; text: root.historyQuery === "" ? "No recent failures" : "No matching problems" }
                }
            }
        }

        footer: [
            RowActions {
                visible: root.tab === 1
                RowAction { text: "Refresh"; disabledReason: root.pendingAsk === "" ? "" : "Wait for the current ask action to finish."; onClicked: root.refreshAsks() }
                RowAction { text: root.snoozedExpanded ? "Hide snoozed" : "Snoozed (" + (root.asksReady ? root.asksState.snoozedCount : "?") + ")"; onClicked: root.snoozedExpanded = !root.snoozedExpanded }
            },
            Column {
                visible: root.showTasks
                width: layout.contentWidth
                spacing: Theme.stack.inline
                Label { width: parent.width; role: "hint"; visible: root.problem !== ""; text: root.problem; color: Theme.color.danger; wrapMode: Text.Wrap }
                Row {
                    spacing: Theme.control.gap
                    Button { text: "Open"; iconName: "external-link"; disabledReason: root.canOpenTask ? "" : "Select a task with a running terminal to open it."; onClicked: root.taskAction("open") }
                    Button { id: taskStopButton; text: "Stop"; iconName: "square"; disabledReason: root.canStopTask ? "" : "Select a running task to stop it."; onClicked: root.taskAction("stop") }
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

                Row {
                    width: parent.width
                    spacing: Theme.control.gap
                    visible: !root.speechOnly

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
            }
        ]
    }
    Item {
        anchors.fill: parent
        visible: root.editingAsk !== null
        Scrim { onClicked: if (root.pendingAsk === "") root.closeAskEditor() }
        Dialog {
            id: askDialog
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 2 * Theme.dialog.margin)
            availableHeight: parent.height - 2 * Theme.dialog.margin
            title: root.editingAction === "reply" ? "Reply to " + (root.editingAsk === null ? "" : root.editingAsk.askedBy.name) : "Show this ask later"
            message: root.editingAsk === null ? "" : root.editingAsk.what
            initialFocus: root.editingAction === "reply" ? replyField : laterDate.input
            tabItems: root.editingAction === "reply" ? [replyField, askSubmit, askCancel] : [laterDate.input, laterTime, askSubmit, askCancel]
            busy: root.pendingAsk !== ""
            actions: []
            onRejected: if (root.pendingAsk === "") root.closeAskEditor()
            Column {
                width: parent.width
                spacing: Theme.stack.page
                TextArea {
                    id: replyField
                    visible: root.editingAction === "reply"
                    width: parent.width
                    placeholderText: "Write your reply"
                    Accessible.name: "Reply to the original ask"
                }
                Column {
                    visible: root.editingAction === "later"
                    width: parent.width
                    spacing: Theme.stack.page
                    Label { role: "body"; text: "Choose when this ask returns." }
                    DateField { id: laterDate; width: parent.width }
                    ResultsFilter { id: laterTime; accessibleLabel: "Return time"; model: ["9:00 am", "Noon", "5:00 pm"] }
                }
                Label { visible: root.askProblem !== ""; width: parent.width; role: "hint"; text: root.askProblem; color: Theme.color.danger; wrapMode: Text.Wrap }
                RowActions {
                    Button {
                        id: askSubmit
                        text: root.editingAction === "reply" ? "Send reply" : "Snooze"
                        disabledReason: root.editorReason()
                        onClicked: root.submitAskEditor()
                    }
                    Button {
                        id: askCancel
                        text: "Cancel"
                        variant: "secondary"
                        disabledReason: root.pendingAsk === "" ? "" : "Wait for the current ask action to finish."
                        onClicked: root.closeAskEditor()
                    }
                }
            }
        }
    }
}
