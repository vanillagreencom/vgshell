import QtQuick
import QtQuick.Templates as T
import Quickshell
import qs.Commons
import qs.Ui
import "Session.js" as Session
import "WidgetView.js" as WidgetView
import "SetupGate.js" as Gate
import "History.js" as History
import "Composer.js" as Composer

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
    readonly property var askOperation: values.ownerAskAnswer === undefined || values.ownerAskAnswer === null
        || values.ownerAskAnswer.home !== currentHome ? null : values.ownerAskAnswer
    readonly property var askAnswer: askOperation !== null && askOperation.kind === "answered" ? askOperation.result : null
    property bool snoozedExpanded: false
    property string askProblem: ""
    readonly property string pendingAsk: askOperation !== null && (askOperation.kind === "first-pending" || askOperation.kind === "retry-pending")
        ? askOperation.request.requestId : ""
    readonly property var unconfirmedRequest: askOperation !== null && (askOperation.kind === "unknown" || askOperation.kind === "retry-pending")
        ? askOperation.request : null
    readonly property string askOutcome: askOperation === null ? "" : askOperation.kind === "unknown"
        ? "The action was not confirmed. Retry your previous action."
        : askOperation.kind === "not-sent" ? "The action was not sent. Try again."
        : askAnswer !== null && askAnswer.kind !== "accepted" ? askAnswer.cause : ""
    readonly property string askRecoveryText: askOperation === null || (pendingAsk === "" && unconfirmedRequest === null) ? ""
        : recoveryText(askOperation.request, pendingAsk !== "")
    readonly property string askRetryReason: pendingAsk !== "" ? "Wait for the current ask action to finish."
        : shell === null || state === null ? "Wait for Jarvis to be ready."
        : shell.session === undefined || shell.session.locked !== false ? "Unlock your session before answering an ask." : ""
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
    onCurrentHomeChanged: { editingAsk = null; askProblem = ""; }
    onAskOperationChanged: {
        askProblem = "";
        if (askOperation !== null && askOperation.kind === "answered" && askOperation.result.kind === "accepted"
                && editingAsk !== null && editingAsk.id === askOperation.request.id && editingAsk.revision === askOperation.request.expectedRevision
                && editingAction === askOperation.request.action && (editingAction === "reply" ? replyField.text === askOperation.request.text
                    : laterInstant() === askOperation.request.until))
            closeAskEditor();
    }

    function refreshAsks() {
        if (shell === null) return;
        const reply = shell.ipc.call("owner-asks-refresh", "");
        askProblem = reply !== "ok" ? "Jarvis is not ready to refresh your asks." : "";
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
                : unconfirmedRequest !== null ? "Retry your previous ask action first."
                : row.actions[action].allowed ? "" : row.actions[action].reason }));
    }
    function chooseAsk(action, row, source) {
        if (pendingAsk !== "" || unconfirmedRequest !== null || !row.actions[action].allowed) return;
        askProblem = "";
        returnAskFocus = source;
        if (action === "done") { sendAsk(action, row, "", null); return; }
        editingAsk = row;
        editingHome = asksState.homeId;
        editingAction = action;
        replyField.text = "";
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
        if (unconfirmedRequest !== null) return "Close this dialog and retry your previous action.";
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
        if (shell === null || !asksReady || pendingAsk !== "" || unconfirmedRequest !== null) return;
        const requestId = "console:" + Date.now() + ":" + (++askSerial);
        const request = { action: action, id: row.id,
            requestId: requestId, expectedRevision: row.revision, text: text, until: until };
        sendAskRequest(request);
    }
    function retryAsk() {
        if (unconfirmedRequest !== null && askRetryReason === "") sendAskRequest(unconfirmedRequest);
    }
    function sendAskRequest(request) {
        if (shell === null || pendingAsk !== "") return;
        const reply = shell.ipc.call("owner-ask-action", JSON.stringify(request));
        if (reply !== "ok") askProblem = unconfirmedRequest === null ? "This ask could not be sent. Refresh before trying again."
            : "The retry could not be sent. Your previous action is still unconfirmed.";
    }
    function openAskLink(row) {
        if (shell === null) return;
        const reply = shell.run.detached(DesktopLaunch.open(row.link.url));
        askProblem = reply === "ok" ? "" : "The original thread could not be opened.";
    }
    // Every time the console shows reads in the shell's one wording, against
    // the shared minute clock, so a recent one reads as its age.
    function when(at) { return Timestamp.text(at, Time.now.getTime()); }
    function askTime(row) { return "Asked " + when(Date.parse(row.askedAt)); }
    // The ask and the action a pending or unconfirmed REQUEST holds, the one
    // Retry previous action sends again. An ask off the current page keeps
    // its action without its words.
    function recoveryText(request, sending) {
        const ask = activeAsks.concat(snoozedAsks).find(row => row.id === request.id);
        const what = ask === undefined ? "an ask not on this page" : "“" + ask.what + "”";
        if (request.action === "reply")
            return (sending ? "Sending your reply to " + what + ": " : "Your reply to " + what + " is not confirmed: ") + "“" + request.text + "”";
        if (request.action === "done")
            return sending ? "Jarvis is checking that " + what + " is done." : "Your Done for " + what + " is not confirmed.";
        const until = when(Date.parse(request.until));
        return sending ? "Snoozing " + what + " until " + until + "." : "Your snooze of " + what + " until " + until + " is not confirmed.";
    }
    // A conversation group's heading: when its session started, and the
    // first time on a later day it holds.
    function sessionTitle(group) {
        const started = new Date(group.startedAt), first = new Date(group.rows[0].at);
        const sameDay = started.toDateString() === first.toDateString();
        return "Session started " + when(group.startedAt) + (sameDay ? "" : " · continued " + when(group.rows[0].at));
    }
    function askState(row) { return row.state === "checking" ? "Checking…" : row.state === "snoozed" ? "Snoozed" : row.kind === "fleet-approval" ? "Fleet approval" : row.kind === "tracker-item" ? "Your approval" : "Needs reply"; }
    function problemAction(row) {
        if (row.settings) root.shell.surfaces.openPage("vgs.jarvis", "Settings");
        else { root.tab = 0; Qt.callLater(() => root.composerFocus.forceActiveFocus()); }
    }

    readonly property var taskRows: History.tasks(Array.isArray(values.taskList) ? values.taskList : [], historyQuery)
    readonly property var auditRows: Array.isArray(values.auditFailures) ? values.auditFailures.slice().reverse() : []
    property string draft: ""
    property bool composerRegistered: false
    onShellChanged: {
        if (shell === null || composerRegistered) return;
        composerRegistered = true;
        shell.ipc.handle("compose-draft", text => JSON.stringify(acceptDraft(text)));
    }
    readonly property var refusal: Session.sayRefusal(state)
    readonly property bool ready: shell !== null && state !== null && refusal === null
    readonly property string stopKey: shell === null || shell.shortcut.keys.stop === undefined || shell.shortcut.keys.stop === null ? "" : shell.shortcut.keys.stop
    readonly property var conversation: Array.isArray(values.conversation) ? values.conversation : []
    readonly property var memoryInbox: Array.isArray(values.memoryInbox) ? values.memoryInbox : []
    // SessionStart publishes the canonical resume reading independently of
    // conversation readiness. Complete outcomes wrap in the scroll body;
    // the state-only bar and bounded Setup badges cannot carry these lines.
    readonly property var sessionReading: values.jarvisSession === undefined ? null : values.jarvisSession
    readonly property var sessionLines: sessionReading === null ? [] : sessionReading.steps.map(Gate.sessionStepLine)
    readonly property string sessionCheckedText: sessionReading === null || sessionReading.checkedAt === null ? ""
        : Gate.sessionCheckedLine(sessionReading.checkedAt)
    readonly property string livePartial: state !== null && state.turn.kind === "collecting" ? state.turn.partial : ""
    readonly property var transcriptRows: rows()
    readonly property string hint: problem !== "" ? problem : refusalText(refusal)
    readonly property var messageLimit: Gate.messageLimit(Session.TRANSCRIPT_CHARS)
    // A duplex voice takes no typed message (Session.sayRefusal), so the
    // composer offers none: one line says how to talk instead.
    readonly property bool speechOnly: state !== null && state.engine.kind === "duplex"
    // The shortcut keys as people read them, the bar's own spelling.
    readonly property var spelledKeys: WidgetView.spelledKeys(shell === null ? null : shell.shortcut.keys, ShortcutLabels.keyCaps)
    // How to talk now: the sentence the Voice step and the bar say it with.
    readonly property string talkLine: Gate.talkHint(shell !== null && shell.settings.holdToTalk, spelledKeys.talk) + "."
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
        if (payload.text !== undefined) {
            const result = acceptDraft(payload.text);
            if (!result.ok) throw new Error("draft=refused");
        }
        problem = "";
        tab = 0;
        editingAsk = null;
        askProblem = "";
        refreshAsks();
        Qt.callLater(() => root.composerFocus.forceActiveFocus());
        Qt.callLater(followEnd);
    }

    function close() {}

    function acceptDraft(text) {
        // Diagnose asks before Service summons this console again. Reopening
        // clears the ask editor even when the message composer is empty.
        if (editingAsk !== null)
            return { ok: false, reason: "Finish or cancel your open ask before retrying Diagnose." };
        const result = Composer.draft(entryField.text, text, state);
        if (!result.ok) return result;
        entryField.text = text;
        entryField.cursorPosition = 0;
        tab = 0;
        problem = "";
        Qt.callLater(() => entryField.forceActiveFocus(Qt.OtherFocusReason));
        return result;
    }

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
        (tab === 0 ? newConversationAction : consoleTabs).forceActiveFocus(Qt.BacktabFocusReason);
        event.accepted = true;
        return true;
    }

    function taskState(row) {
        const words = { starting: "Starting", working: "Working", waiting: "Waiting for you",
            "reported-ok": "Done as reported", failed: "Failed", "reported-failed": "Failed",
            stopped: "Stopped", lost: "Lost", exited: "Stopped", noisy: "Task record unreadable" };
        return words[row.state];
    }

    function taskTone(row) {
        return ["failed", "reported-failed", "lost"].includes(row.state) ? "danger" : row.state === "waiting" || row.state === "noisy" ? "warning"
            : row.state === "reported-ok" ? "success" : ["starting", "working"].includes(row.state) ? "info" : "neutral";
    }

    function taskFailure(row) {
        return row.failure === null ? "" : typeof row.failure === "number" ? "Exited with code " + row.failure : String(row.failure);
    }

    // The actions ROW's own task takes, in its row: Open while its process
    // is alive, since Tasks.derive clears endedAt then and a failed turn can
    // still be alive, and Stop while it runs. A starting process has no
    // terminal to open yet.
    function taskActions(row) {
        const ready = state === null ? "Wait for Jarvis to be ready." : "";
        const actions = [];
        if (row.endedAt === null)
            actions.push({ id: "open", label: "Open", disabledReason: ready || (row.state === "starting" ? "Wait for the task's terminal to start." : "") });
        if (["starting", "working", "waiting"].includes(row.state)) actions.push({ id: "stop", label: "Stop", disabledReason: ready });
        return actions;
    }

    // ACTION on ROW's task, from SOURCE, the row's button.
    function taskAction(action, row, source) {
        const offered = taskActions(row).find(item => item.id === action);
        if (shell === null || offered === undefined || offered.disabledReason !== "") return;
        const reply = shell.ipc.call(action === "stop" ? "stop-task" : "open-task", row.id);
        problem = reply === "ok" ? "" : reply === "refused: jarvis=not-ready" ? "Jarvis is not ready"
            : action === "stop" ? "The coding task could not be stopped" : "The coding task could not be opened";
        // A stopped task's row drops its Open and Stop. Return to the list
        // before that republish removes the focused button, keeping the
        // keyboard or pointer focus reason.
        if (reply === "ok" && action === "stop") tasksBody.forceActiveFocus(source === null ? Qt.OtherFocusReason : source.focusReason);
    }

    Keys.onPressed: event => {
        if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && (event.modifiers & Qt.ControlModifier)) {
            event.accepted = consoleTabs.nav.handle(event);
        }
    }
    onTabChanged: { problem = ""; Qt.callLater(focusTab); }

    // The line in place of the message box under a voice that takes speech
    // only (ROUTE, the Voice provider reading), saying how to talk (TALK).
    function speechOnlyLine(route, talk) {
        return (route === undefined || route === null ? "This voice" : route.text) + " takes speech only. " + talk;
    }

    // The empty conversation's line: how to start one, by typing or, under a
    // voice that takes speech only (SPEECH), by talking (TALK).
    function emptyText(speech, talk) {
        return "No conversation yet. " + (speech ? talk : "Type a message to start.");
    }

    // The Now line for REACH, the daemon's reading of the main Jarvis
    // (Satellite.js), or "" before the first. A host comes from Main
    // Jarvis host, or from the package while that field is empty. An
    // unavailable route links where it is fixed, as the session row's blocks do
    // (SetupGate.SESSION_BLOCKS): a missing session program to its Repair,
    // a block of the home to the Home folder. A package that is older or
    // did not answer has no fix in VGS, so its line links nothing.
    function reachText(reach) {
        if (reach === undefined || reach === null) return "";
        if (reach.kind === "main") return "This computer runs your main Jarvis.";
        if (reach.kind === "unavailable" && reach.cause === "no-home")
            return "Jarvis cannot forward requests until you choose a [Home folder](page:vgs.jarvis/Settings/home).";
        const blocked = reach.host === "" ? "Jarvis cannot forward requests: " : "Jarvis cannot forward to " + reach.host + ": ";
        if (reach.cause === "package-old")
            return blocked + "the Jarvis package in your home folder is older than the version that forwards requests. A newer Jarvis package is necessary.";
        if (reach.cause === "package-unread")
            return blocked + "the Jarvis package in your home folder did not answer as expected.";
        if (reach.cause === "setting-unhanded")
            return blocked + (shell.settings.mainHost === ""
                ? "set [Main Jarvis host](page:vgs.jarvis/Settings/mainHost) to " + reach.host + "."
                : "choose This computer in [Main Jarvis host](page:vgs.jarvis/Settings/mainHost), then choose " + reach.host + ".");
        if (reach.cause === "package")
            return blocked + "the Jarvis package in your home folder has no session program. [Repair it in Setup](page:vgs.jarvis/Setup/sessionStart).";
        if (reach.cause === "vgs-package")
            return blocked + "VGS made this Home folder without the Jarvis package. [Choose a Kendex Jarvis home](page:vgs.jarvis/Settings/home).";
        if (reach.kind === "unavailable")
            return blocked + "the Jarvis package in your [Home folder](page:vgs.jarvis/Settings/home) cannot be opened.";
        if (reach.cause === "setting-invalid")
            return "Jarvis cannot reach your main Jarvis: [Main Jarvis host](page:vgs.jarvis/Settings/mainHost) is not a computer name.";
        const destination = "Requests that need your main Jarvis go to " + reach.host + ". ";
        if (reach.reachable === true) return destination + "It is reachable.";
        if (reach.reachable === false) return destination + "It did not answer. Requests wait here.";
        return destination + "None sent yet.";
    }

    function rows() {
        const result = detail === null ? [] : conversation.filter(row => row.session === detail.conversationId);
        if (livePartial.trim() !== "") result.push({ gen: state.gen, role: "user", text: livePartial, stage: "partial" });
        return result;
    }

    function speaker(role) { return role === "user" ? "You" : "Jarvis"; }

    function refusalText(key) {
        if (key === null) return draft.trim() === "" ? "Type a message to Jarvis" : "Enter sends the message";
        if (key === "say-text") return "Use up to " + Gate.numberText(messageLimit.maximum) + " characters of plain text";
        return Composer.refusalText(key);
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

    function newConversation() {
        if (shell === null) return;
        const reply = shell.ipc.call("new-conversation", "");
        problem = reply === "ok" ? "" : "Jarvis is not ready to start a new conversation";
        if (reply === "ok") {
            draft = "";
            entryField.text = "";
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
        header: Column {
            width: layout.contentWidth
            spacing: Theme.stack.group
            Tabs {
                id: consoleTabs
                width: parent.width
                model: ["Now", "Needs you", "History"]
                unreadCounts: root.asksReady && root.asksState.activeCount > 0 ? ({ "Needs you": root.asksState.activeCount }) : ({})
                currentIndex: root.tab
                KeyNavigation.tab: root.tab === 0 ? newConversationAction : root.tab === 1 ? asksBody : historySearch
                onCurrentIndexChanged: root.tab = currentIndex
            }
            RowAction {
                id: newConversationAction
                objectName: "newConversationAction"
                visible: root.tab === 0
                text: "New conversation"
                disabledReason: root.state === null ? "Wait for Jarvis to be ready." : ""
                // Explicit reverse navigation keeps the header action between
                // tabs and composer: https://doc.qt.io/qt-6/qml-qtquick-keynavigation.html
                KeyNavigation.backtab: consoleTabs
                KeyNavigation.tab: root.composerFocus
                onClicked: root.newConversation()
            }
            // The main Jarvis's reachability, in the fixed header so a long
            // conversation never scrolls it away.
            LinkText {
                objectName: "mainReachLine"
                visible: root.tab === 0 && text !== ""
                width: parent.width
                role: "hint"
                text: root.reachText(root.values.mainReach)
                // A route that cannot forward, or a main that did not answer,
                // stops a forward: the warning tone (design-system.md).
                color: root.values.mainReach && (root.values.mainReach.kind === "unavailable"
                    || root.values.mainReach.kind === "satellite" && root.values.mainReach.cause !== "") ? Theme.color.warning : Theme.color.textMuted
                wrapMode: Text.Wrap
                onPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
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
                        variant: "search"
                        width: parent.width
                        placeholderText: "Search conversations, tasks and problems"
                        leadingIcon: "search"
                        onTextChanged: root.historyQuery = text
                        Keys.onPressed: event => root.handleBacktab(event)
                    }
                }
                ResultsFilter {
                    id: historyFilter
                    accessibleLabel: "Filter history results"
                    model: ["All types", "Conversations", "Tasks", "Problems"]
                    currentIndex: root.historyType
                    // The body's scroll stop follows the header in item
                    // order, so Tab names the shown result list that owns
                    // its keys; conversations own none and take that stop
                    // (https://doc.qt.io/qt-6/qml-qtquick-keynavigation.html#tab-prop).
                    KeyNavigation.tab: root.showTasks ? tasksBody : root.showProblems ? auditBody : layout.scrollArea.focusProxy
                    onActivated: index => root.historyType = index
                }
            }
        }

        Column {
            visible: root.tab === 0
            width: layout.contentWidth
            spacing: Theme.stack.row

            Section {
                objectName: "sessionResume"
                visible: root.sessionLines.length > 0 || root.sessionCheckedText !== ""
                width: layout.contentWidth
                title: "Session resume"
                Repeater {
                    model: root.sessionLines
                    Label {
                        required property var modelData
                        objectName: "sessionResumeLine"
                        // Repeater teardown can detach a delegate before
                        // deleting it. Keep geometry on the owning layout.
                        // qml-smoke run 20261107T024427Z, Console.qml:596;
                        // https://doc.qt.io/qt-6/qml-qtquick-repeater.html#count-prop
                        width: layout.contentWidth
                        role: "body"
                        text: modelData
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                    }
                }
                LinkText {
                    objectName: "sessionResumeChecked"
                    visible: text !== ""
                    width: parent.width
                    role: "hint"
                    text: root.sessionCheckedText
                    wrapMode: Text.Wrap
                    onPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
                }
            }

            Repeater {
                model: root.transcriptRows
                MessageRow {
                    required property var modelData
                    width: layout.contentWidth
                    sender: root.speaker(modelData.role)
                    timeText: modelData.at === undefined ? "Listening" : root.when(modelData.at)
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
                onPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
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
                Label { visible: text !== ""; width: parent.width; role: "hint"; text: root.askProblem || root.askOutcome; color: Theme.color.danger; wrapMode: Text.Wrap }
                Label { visible: root.editingAsk === null && text !== ""; width: parent.width; role: "body"; text: root.askRecoveryText; wrapMode: Text.Wrap }
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
                            onSourceActivated: if (live) root.openAskLink(ask)
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
                                bodyText: live ? "Returns " + root.when(Date.parse(ask.snoozedUntil)) + "." : ""
                                linkText: live ? ask.link.label : ""
                                stateText: "Snoozed"
                                actions: live ? root.askActions(ask) : []
                                onSourceActivated: if (live) root.openAskLink(ask)
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
                    title: root.sessionTitle(modelData)
                    GroupList {
                        width: parent.width
                        Repeater {
                            model: modelData.rows
                            MessageRow {
                                required property var modelData
                                width: layout.contentWidth
                                sender: root.speaker(modelData.role)
                                timeText: root.when(modelData.at)
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
            // The list scrolls by key as Needs you and Problems do; Tab
            // walks each task row's own Open and Stop, which the scroll
            // area reveals as they take focus.
            Keys.onPressed: event => {
                if (root.handleBacktab(event)) return;
                if (layout.scrollArea.handleScrollKey(event)) event.accepted = true;
            }
            FocusRing { target: tasksBody; outside: true }
            contentItem: Section {
                id: taskColumn
                title: "Coding tasks"
                Label { visible: root.problem !== ""; width: parent.width; role: "hint"; text: root.problem; color: Theme.color.danger; wrapMode: Text.Wrap }
                GroupList {
                    id: taskGroups
                    width: parent.width
                    Repeater {
                        // ScriptModel string keys retain delegates on Quickshell0.3.1; current payloads stay in the canonical list (DeviceList.qml).
                        model: ScriptModel { values: root.taskRows.map(row => row.id) }
                        MessageRow {
                            required property var modelData
                            readonly property var task: root.taskRows.find(row => row.id === modelData)
                            readonly property bool live: task !== undefined
                            visible: live
                            width: taskGroups.width
                            sender: live ? task.agent : ""
                            avatarIcon: "terminal"
                            title: live ? task.goal : ""
                            bodyText: live ? root.taskFailure(task) : ""
                            stateText: live ? root.taskState(task) : ""
                            stateTone: live ? root.taskTone(task) : "neutral"
                            actions: live ? root.taskActions(task) : []
                            onActionTriggered: action => { if (live) root.taskAction(action, task, actionAt(actions.findIndex(item => item.id === action))); }
                        }
                    }
                    EmptyState { width: parent.width; visible: root.taskRows.length === 0; iconName: "terminal"; text: "No coding tasks" }
                }
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
                            timeText: root.when(modelData.at)
                            title: modelData.title
                            bodyText: modelData.body
                            linkText: modelData.action
                            onSourceActivated: root.problemAction(modelData)
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
                RowAction { text: "Retry previous action"; visible: root.unconfirmedRequest !== null; disabledReason: root.askRetryReason; onClicked: root.retryAsk() }
                RowAction { text: root.snoozedExpanded ? "Hide snoozed" : "Snoozed (" + (root.asksReady ? root.asksState.snoozedCount : "?") + ")"; onClicked: root.snoozedExpanded = !root.snoozedExpanded }
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

                        ScrollArea {
                            id: draftScroll
                            width: parent.width - sendButton.width - stopButton.width - parent.spacing - parent.spacing
                            implicitHeight: Math.min(entryField.implicitHeight, Theme.size.control.lg * 8)
                            keyboardScroll: false
                            // TextEdit does not scroll itself. The shared ScrollArea
                            // owns wheel/overflow; cursor changes reveal its line.
                            // https://doc.qt.io/qt-6/qml-qtquick-textedit.html
                            TextArea {
                                id: entryField
                                width: draftScroll.contentWidth
                                placeholderText: "Message Jarvis"
                                textFormat: TextEdit.PlainText
                                onTextChanged: root.draft = text
                                onCursorRectangleChanged: {
                                    draftScroll.contentY = Math.max(0, Math.min(draftScroll.contentHeight - draftScroll.height,
                                        Math.max(cursorRectangle.y + cursorRectangle.height - draftScroll.height,
                                            Math.min(draftScroll.contentY, cursorRectangle.y))));
                                }
                                Keys.onPressed: event => {
                                    if (root.handleBacktab(event)) return;
                                    // Keys runs before TextEdit; Shift+Enter alone
                                    // reaches its native newline insertion.
                                    // https://doc.qt.io/qt-6/qml-qtquick-keys.html
                                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                        root.sendMessage(); event.accepted = true; return;
                                    }
                                    if ((event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) && layout.scrollArea.handleScrollKey(event)) event.accepted = true;
                                }
                            }
                        }
                        IconButton {
                            id: stopButton
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "square"
                            label: "Stop Jarvis"
                            tooltip: root.stopKey === "" ? "Stop Jarvis" : "Stop Jarvis " + root.stopKey
                            onClicked: root.stop()
                        }
                        Button {
                            id: sendButton
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Send"
                            iconName: "send"
                            disabledReason: !root.ready ? root.refusalText(root.refusal) : entryField.text.trim() === "" ? "Type a message to Jarvis first" : ""
                            onClicked: root.sendMessage()
                        }
                    }
                    KeyHints {
                        onPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
                        afterActions: true
                        hints: root.speechOnly ? [] : [
                            { key: "Enter", text: "Send" },
                            { key: "SHIFT+Enter", text: "New line" },
                            { key: root.shell === null ? "" : root.shell.shortcut.keys.talk || "", text: "Talk" },
                            { key: root.stopKey, text: "Stop" }
                        ]
                        visible: !root.speechOnly
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
                    readOnly: root.pendingAsk !== "" || root.unconfirmedRequest !== null
                }
                Column {
                    visible: root.editingAction === "later"
                    width: parent.width
                    spacing: Theme.stack.page
                    Label { role: "body"; text: "Choose when this ask returns." }
                    DateField { id: laterDate; width: parent.width }
                    ResultsFilter { id: laterTime; accessibleLabel: "Return time"; model: ["9:00 am", "Noon", "5:00 pm"] }
                }
                Label { visible: text !== ""; width: parent.width; role: "hint"; text: root.askProblem || root.askOutcome; color: Theme.color.danger; wrapMode: Text.Wrap }
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
