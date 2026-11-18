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
import "AccountProviders.js" as Providers

// Jarvis console: a keyboard-first chat window. It asks the service through
// IPC, reads the service's bounded conversation status, and never owns the
// daemon or a transcript store. Its header holds the title, one status
// chip, New conversation, More and Settings on every tab; Chat holds the
// conversation over one message box with the model and effort at its left
// and Send, or Stop while Jarvis works, at its right.
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
    // An action Jarvis has not confirmed, waiting for the person's Retry.
    readonly property bool askUnconfirmed: askOperation !== null && askOperation.kind === "unknown"
    readonly property string askOutcome: askOperation === null ? "" : askOperation.kind === "not-sent" ? "The action was not sent. Try again."
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
    // The recovery notice's Retry: the same held request again, or why it
    // cannot go now.
    function retryAsk() {
        if (unconfirmedRequest === null) return;
        if (askRetryReason !== "") { askProblem = askRetryReason; return; }
        sendAskRequest(unconfirmedRequest);
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
    // A time in the shell's one wording, against the shared minute clock,
    // so a recent one reads as its age. No row shows one; a snooze names
    // its return in a sentence and a snoozed ask in its description.
    function when(at) { return Timestamp.text(at, Time.now.getTime()); }
    // The one sentence for the ask and the action a pending or unconfirmed
    // REQUEST holds: what is being sent, or what Jarvis has not confirmed,
    // which the notice's Retry sends again. An ask off the current page
    // keeps its action without its words.
    function recoveryText(request, sending) {
        const ask = activeAsks.concat(snoozedAsks).find(row => row.id === request.id);
        const what = ask === undefined ? "an ask not on this page" : "“" + ask.what + "”";
        if (request.action === "reply")
            return sending ? "Sending your reply “" + request.text + "” to " + what + "."
                : "Jarvis has not confirmed your reply “" + request.text + "” to " + what + ".";
        if (request.action === "done")
            return sending ? "Jarvis is checking that " + what + " is done." : "Jarvis has not confirmed that " + what + " is done.";
        const until = when(Date.parse(request.until));
        return sending ? "Snoozing " + what + " until " + until + "." : "Jarvis has not confirmed your snooze of " + what + " until " + until + ".";
    }
    function askState(row) { return row.state === "checking" ? "Checking…" : row.state === "snoozed" ? "Snoozed" : row.kind === "fleet-approval" ? "Fleet approval" : row.kind === "tracker-item" ? "Your approval" : "Needs reply"; }
    function problemAction(row) {
        if (row.settings) root.shell.surfaces.openPage("vgs.jarvis", "Settings");
        else { root.tab = 0; Qt.callLater(() => root.composerFocus.forceActiveFocus()); }
    }

    readonly property var taskRows: History.tasks(Array.isArray(values.taskList) ? values.taskList : [], historyQuery)
    readonly property var auditRows: Array.isArray(values.auditFailures) ? values.auditFailures.slice().reverse() : []
    property bool composerRegistered: false
    onShellChanged: {
        if (shell === null || composerRegistered) return;
        composerRegistered = true;
        shell.ipc.handle("compose-draft", text => JSON.stringify(acceptDraft(text)));
    }
    readonly property var refusal: Session.sayRefusal(state)
    readonly property var conversation: Array.isArray(values.conversation) ? values.conversation : []
    readonly property var memoryInbox: Array.isArray(values.memoryInbox) ? values.memoryInbox : []
    readonly property string livePartial: state !== null && state.turn.kind === "collecting" ? state.turn.partial : ""
    readonly property var transcriptRows: rows()
    // History's Messages: every turn the log holds, oldest first.
    readonly property var historyRows: History.messages(conversation, historyQuery)
    readonly property var messageLimit: Gate.messageLimit(Session.TRANSCRIPT_CHARS)
    readonly property string historyLimit: "The list keeps the newest 20 failures.\nSearch and the type filter use only these records."
    // A duplex voice takes no typed message (Session.sayRefusal): the
    // message box stays, locked, under one notice that says how to talk.
    readonly property bool speechOnly: state !== null && state.engine.kind === "duplex"
    // Jarvis works while it thinks, waits for a confirmation, runs a task or
    // speaks: Stop then takes Send's place in the message box.
    readonly property bool working: detail !== null && ["thinking", "confirming", "acting", "speaking"].indexOf(detail.phase) !== -1
    // More's Stop has nothing to stop while Jarvis is ready and idle; while
    // it starts, fails or works, Stop ends that.
    readonly property bool nothingToStop: detail !== null && (detail.phase === "idle" || detail.phase === "listening")
    // The header's status chip: the bar widget's own state reading.
    readonly property var statusLook: WidgetView.stateView(values, Providers.cloudVoice(shell === null ? "" : shell.settings.voiceProvider))
    // The shortcut keys as people read them, the bar's own spelling.
    readonly property var spelledKeys: WidgetView.spelledKeys(shell === null ? null : shell.shortcut.keys, ShortcutLabels.shortcutText)
    // How to talk now: the sentence the Voice step and the bar say it with.
    readonly property string talkLine: Gate.talkHint(shell !== null && shell.settings.holdToTalk, spelledKeys.talk) + "."
    // Chat's first control: the message box, locked under a voice that
    // takes speech only, so the reason it gives stays in reach.
    readonly property Item composerFocus: entryField
    readonly property string speechOnlyText: speechOnlyLine(values.voiceRoute, talkLine)
    // The model and effort choices the plugin offers for the chosen sign-in
    // (Accounts.qml), each { label, value }.
    readonly property var modelChoices: Array.isArray(values.models) ? values.models : []
    // The model of modelChoices the saved setting runs, "" while it runs none.
    readonly property string modelShown: typeof values.modelShown === "string" ? values.modelShown : ""
    readonly property var effortChoices: Array.isArray(values.efforts) ? values.efforts : []

    // Qt retains active focus on an item whose branch becomes invisible:
    // Send and Stop trade places as Jarvis starts and ends work, Send goes
    // and the speech-only notice comes as typing turns off, and the notice
    // goes as it turns on. Focus on Send or Stop that went moves to the one
    // that shows, and any other, the notice's links, to the message box,
    // keeping its reason. tst_jarvis_console drives the speech-only
    // transitions.
    function keepComposerFocus() {
        const focused = root.Window.activeFocusItem;
        if (!root.activeFocus || root.tab !== 0 || focused === null || focused.visible) return;
        if (!KeyNavLogic.contains(composer, focused)) return;
        const swapped = focused === sendButton || focused === stopButton;
        (swapped && stopButton.visible ? stopButton : swapped && sendButton.visible ? sendButton : entryField).forceActiveFocus(focused.focusReason);
    }
    onWorkingChanged: Qt.callLater(keepComposerFocus)
    onSpeechOnlyChanged: Qt.callLater(keepComposerFocus)

    // Tab and Backtab through the header and the message box in this
    // order: the tabs, New conversation, More and Settings, then the tab's
    // first control (tabStart); in the box the text, the model, the effort,
    // then Send or Stop, and on to the tabs. Backtab from the text returns
    // to New conversation (handleBacktab), and Backtab from the tabs goes to
    // the content's last control, the one before tabWrap, which marks the
    // content's end in Qt's item order for both directions. Each control
    // hands its keys here first (traverseKey), since Qt moves the focus
    // along the item order at the focused item when its key handlers leave
    // Tab unaccepted, and the header stands before the tabs in that order.
    // No KeyNavigation edge joins them: an edge to the text makes Qt set the
    // text's own Tab edge back, which takes Ctrl+Tab, the tab switch, too
    // (tst_jarvis_console).
    // Tab or Backtab with Control held is that switch, which the root's
    // handler takes.
    function traverse(event) {
        if (event.modifiers & Qt.ControlModifier) return false;
        const forward = event.key === Qt.Key_Tab && event.modifiers === Qt.NoModifier;
        const backward = event.key === Qt.Key_Backtab || event.key === Qt.Key_Tab && event.modifiers === Qt.ShiftModifier;
        if (!forward && !backward) return false;
        const header = [consoleTabs, newConversationButton, moreButton, settingsButton];
        const box = [entryField, modelSelect, effortSelect, sendButton, stopButton].filter(control => control.visible);
        const chain = tab === 0 ? header.concat(box) : header;
        const at = chain.findIndex(control => control.activeFocus);
        if (at === -1) return false;
        const next = backward ? (at === 0 ? tabWrap.nextItemInFocusChain(false) : chain[at - 1])
            : at === header.length - 1 ? tabStart() : at + 1 < chain.length ? chain[at + 1] : consoleTabs;
        if (next === null) return false;
        next.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
        return true;
    }
    function traverseKey(event) { if (traverse(event)) event.accepted = true; }
    // The first control of the tab that shows: on Chat, the first link of
    // the forwarding notice or else the speech-only notice while one shows,
    // else the message box. Qt's item order walks on from a notice's links
    // to the message box.
    function tabStart() {
        const notice = [reachNotice, speechNotice].find(item => item.visible && item.firstStop !== null);
        return tab === 0 ? (notice === undefined ? root.composerFocus : notice.firstStop)
            : tab === 1 ? asksBody : historySearch;
    }

    // A change of model or effort ends the conversation, so the console asks
    // first (choiceDialog); CONTROL, the select, takes the focus back. The
    // entry it shows already (choiceIndex: the saved choice, or what an
    // unset model or effort runs) changes nothing.
    property var pendingChoice: null
    function askChoice(key, choices, index, control) {
        const choice = choices[index];
        if (choice === undefined || shell === null || index === choiceIndex(key, choices)) return;
        pendingChoice = { key: key, value: choice.value, label: choice.label, control: control,
            reason: control.visualFocus ? Qt.TabFocusReason : Qt.MouseFocusReason };
        Qt.callLater(() => choiceDialog.forceActiveFocus(Qt.OtherFocusReason));
    }
    function closeChoice(confirmed) {
        const choice = pendingChoice;
        if (choice === null) return;
        pendingChoice = null;
        if (confirmed) {
            const reply = shell.configure.set(choice.key, choice.value);
            if (reply !== "ok") {
                problem = choice.key === "model" ? "Jarvis did not change the AI model." : "Jarvis did not change the effort.";
                console.warn("jarvis console: " + choice.key + " " + reply);
            }
        }
        Qt.callLater(() => { if (choice.control.visible) choice.control.forceActiveFocus(choice.reason); });
    }
    // The entry of CHOICES that KEY shows: for the model, the one
    // `modelShown` names (AccountProviders.modelChoice `shown`), none where
    // it names no entry; for the effort, the saved level, the first one
    // offered while it is unset (AccountProviders.effortOffers).
    function choiceIndex(key, choices) {
        const value = key === "model" ? modelShown : shell === null ? "" : shell.settings.effort;
        const at = choices.findIndex(choice => choice.value === value);
        return at === -1 && value === "" && key === "effort" ? 0 : at;
    }

    // A summons or a handoff puts the person back in the console's body,
    // so it closes the console's dialogs: a message box under one still
    // takes Return.
    function closeDialogs() {
        editingAsk = null;
        pendingChoice = null;
    }



    // The History tab filtered to its Problems list, every record in it
    // shown, its search field focused (focusTab).
    function openProblems() {
        problem = "";
        closeDialogs();
        askProblem = "";
        historySearch.text = "";
        historyType = 3;
        if (tab === 2) Qt.callLater(focusTab);
        else tab = 2;
    }

    function open(payloadJson) {
        payload = payloadJson ? JSON.parse(payloadJson) : {};
        choicesShown(true);
        // The restart notice's action opens the Problems list (Service.qml).
        if (payload.problems === true) {
            openProblems();
            return;
        }
        if (payload.text !== undefined) {
            const result = acceptDraft(payload.text);
            if (!result.ok) throw new Error("draft=refused");
        }
        problem = "";
        tab = 0;
        closeDialogs();
        askProblem = "";
        refreshAsks();
        Qt.callLater(() => root.composerFocus.forceActiveFocus());
        // An open from Jarvis's reply card names its answer.
        placeAt(payload.answer === undefined ? null : payload.answer);
        Qt.callLater(() => root.keepPlace("open"));
    }
    // Where the transcript view stands: "end", at its newest row; "pending",
    // at the answer an open from Jarvis's reply card named, which waits for
    // its row's and the view's first height, since a new console opens before
    // its window maps; "held", that answer's top under the top fade band, as
    // far as the end allows, marked for `messageRow.markHold`, and placed
    // again as the window settles its height. keepPlace() puts the view
    // there on each change that can move it.
    property string placement: "end"
    property var markedAnswer: null
    Timer { id: markTimer; interval: Theme.messageRow.markHold; onTriggered: root.placeAt(null) }
    function placeAt(answer) {
        markedAnswer = answer;
        placement = answer === null ? "end" : "pending";
        if (answer === null) markTimer.stop();
    }
    function answerItem() {
        const index = markedAnswer === null ? -1 : transcriptRows.findIndex(row => WidgetView.isAnswer(row, markedAnswer));
        return index < 0 ? null : transcriptList.itemAt(index);
    }
    // TRIGGER is what moved: "open", "tab", "rows", "content" or "view".
    // At the end, a content change follows only a view already at its end,
    // and a view change moves nothing.
    function keepPlace(trigger) {
        if (tab !== 0) return;
        if (placement === "end") {
            if (trigger === "view" || trigger === "content" && !atEnd) return;
            followEnd();
            return;
        }
        const item = answerItem();
        const view = layout.scrollArea;
        if (item === null) {
            placeAt(null);
            followEnd();
            return;
        }
        if (placement === "pending") {
            if (!(view.height > 0) || !(item.height > 0)) return;
            placement = "held";
            markTimer.restart();
        }
        const at = item.mapToItem(view.contentItem, 0, 0);
        const top = at.y - view.clipPadding - view.fadeExtent;
        view.contentY = Math.max(0, Math.min(view.contentHeight - view.height, top));
    }

    function close() { choicesShown(false); }

    // While the console shows, the service reads the sign-in's model list
    // for the model and effort choices (Accounts.qml). Its reply is not
    // read: a console that outlives its service, as one closing while the
    // plugin turns off, has no list to stop, and one that opens before the
    // service shows the saved choice alone.
    function choicesShown(shown) {
        if (shell !== null) shell.ipc.call("console-choices", shown ? "shown" : "hidden");
    }

    function acceptDraft(text) {
        // Diagnose asks before Service summons this console again. Reopening
        // clears the ask editor even when the message composer is empty.
        if (editingAsk !== null)
            return { ok: false, reason: "Finish or cancel your open ask before retrying Diagnose." };
        const result = Composer.draft(entryField.text, text, state);
        if (!result.ok) return result;
        closeDialogs();
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
        Qt.callLater(() => root.keepPlace("tab"));
    }

    // Handle Backtab and Tab with Shift before the control's native traversal.
    // These controls have no Keys.forwardTo receivers:
    // https://doc.qt.io/qt-6/qml-qtquick-keys.html#key-handling-priorities
    function handleBacktab(event) {
        const backward = event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier));
        if (!backward || (event.modifiers & Qt.ControlModifier)) return false;
        (tab === 0 ? newConversationButton : consoleTabs).forceActiveFocus(Qt.BacktabFocusReason);
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

    // The notice over the locked message box under a voice that takes
    // speech only (ROUTE, the Voice provider reading), saying how to talk
    // (TALK).
    function speechOnlyLine(route, talk) {
        return (route === undefined || route === null ? "This voice" : route.text) + " takes speech only. " + talk;
    }

    // Chat's line for REACH, the daemon's reading of the main Jarvis
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
            return "Jarvis cannot forward requests without a Home folder.\n[Choose home folder](page:vgs.jarvis/Settings/home)";
        const blocked = reach.host === "" ? "Jarvis cannot forward requests: " : "Jarvis cannot forward to " + reach.host + ": ";
        if (reach.cause === "package-old")
            return blocked + "the Jarvis package in your home folder is older than the version that forwards requests. A newer Jarvis package is necessary.";
        if (reach.cause === "package-unread")
            return blocked + "the Jarvis package in your home folder did not answer as expected.";
        if (reach.cause === "setting-unhanded")
            return blocked + (shell.settings.mainHost === ""
                ? "set Main Jarvis host to " + reach.host + "."
                : "choose This computer, then " + reach.host + ".")
                + "\n[Change main host](page:vgs.jarvis/Settings/mainHost)";
        if (reach.cause === "package")
            return blocked + "the Jarvis package in your home folder has no session program. [Repair it in Setup](page:vgs.jarvis/Setup/sessionStart).";
        if (reach.cause === "not-set-up")
            return blocked + "this home folder is not a Jarvis home yet. [Set it up in Home folder](page:vgs.jarvis/Setup/setupHome).";
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
        if (key === "say-text") return "Use up to " + Gate.numberText(messageLimit.maximum) + " characters of plain text";
        return Composer.refusalText(key);
    }

    // Why Send cannot send now, or "".
    function sendReason() {
        if (shell === null || state === null) return "Wait for Jarvis to be ready.";
        if (refusal !== null) return refusalText(refusal);
        return entryField.text.trim() === "" ? "Type a message to Jarvis first." : "";
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
        if (shell === null || speechOnly || entryField.text.trim() === "") return;
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
            entryField.text = "";
            // A new conversation is Chat's: it shows, and its message box
            // takes the keys by the way New conversation was pressed.
            const reason = newConversationButton.visualFocus ? Qt.TabFocusReason : Qt.MouseFocusReason;
            tab = 0;
            Qt.callLater(() => root.composerFocus.forceActiveFocus(reason));
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

    onTranscriptRowsChanged: Qt.callLater(() => root.keepPlace("rows"))
    // A view at its end stays there while rows and memory cards lay out, so
    // the newest card shows whole; a view the user scrolled up stays put.
    property bool atEnd: true
    Connections {
        target: layout.scrollArea
        function onContentYChanged() {
            const view = layout.scrollArea;
            root.atEnd = view.contentY >= view.contentHeight - view.height - 1;
        }
        function onContentHeightChanged() { Qt.callLater(() => root.keepPlace("content")); }
        function onHeightChanged() { Qt.callLater(() => root.keepPlace("view")); }
    }
    implicitWidth: Math.floor(Math.min(Theme.size.window.width, OverlayState.room(screen).width))
    implicitHeight: Math.floor(OverlayState.windowRoom(screen).height)
    focus: true

    // The console's canvas is the sunken level, as the window host draws a
    // level while window glass is off (AppWindow.qml), so the cards, the
    // notices and the person's turns read on their low-emphasis fill; under
    // window glass the glass is the canvas.
    Rectangle {
        anchors.fill: parent
        visible: !Theme.appearanceState.hyprland.glass
        color: Theme.surface.level.sunken.background
    }

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

        title: "Jarvis"
        // The status chip and the header's three actions, on every tab. Tab
        // reaches them after the tabs and before the tab's own first
        // control (traverse); a window names no Settings page, so the
        // console draws its own gear to the Jarvis page. The row stands at
        // the title row's top: the slot's height is the row's own, so a
        // place read from it would feed that height back.
        titleContent: Row {
            id: headerActions
            objectName: "consoleHeader"
            anchors.right: parent.right
            spacing: Theme.stack.inline
            Badge {
                anchors.verticalCenter: parent.verticalCenter
                text: WidgetView.LOOKS[root.statusLook.state].title
                tone: WidgetView.LOOKS[root.statusLook.state].chip
            }
            IconButton {
                id: newConversationButton
                Keys.onPressed: event => root.traverseKey(event)
                objectName: "newConversationAction"
                size: "sm"
                iconName: "square-pen"
                label: "New conversation"
                disabledReason: root.state === null ? "Wait for Jarvis to be ready." : ""
                onClicked: root.newConversation()
            }
            IconButton {
                id: moreButton
                Keys.onPressed: event => root.traverseKey(event)
                objectName: "moreButton"
                size: "sm"
                iconName: "ellipsis"
                label: "More"
                onClicked: {
                    moreMenu.toggle(KeyNavLogic.opener(moreButton));
                }
                Menu {
                    id: moreMenu
                    MenuItem { text: "Jarvis home"; onTriggered: root.shell.surfaces.openPage("vgs.jarvis", "Settings/home") }
                    MenuItem { text: "Message limits"; info: root.messageLimit.info; helpReturnFocus: moreButton }
                    MenuItem { text: "History limits"; info: root.historyLimit; helpReturnFocus: moreButton }
                    MenuItem {
                        text: "Stop Jarvis startup or current work"
                        disabledReason: root.nothingToStop ? "Jarvis has no current work to stop." : ""
                        onTriggered: root.stop()
                    }
                }
            }
            IconButton {
                id: settingsButton
                Keys.onPressed: event => root.traverseKey(event)
                objectName: "settingsButton"
                size: "sm"
                iconName: "settings"
                label: "Settings"
                onClicked: root.shell.surfaces.openPage("vgs.jarvis", "Settings")
            }
        }
        header: Column {
            width: layout.contentWidth
            spacing: Theme.stack.group
            Tabs {
                id: consoleTabs
                Keys.onPressed: event => root.traverseKey(event)
                width: parent.width
                model: ["Chat", "Needs you", "History"]
                unreadCounts: root.asksReady && root.asksState.activeCount > 0 ? ({ "Needs you": root.asksState.activeCount }) : ({})
                currentIndex: root.tab
                onCurrentIndexChanged: root.tab = currentIndex
            }
            // The main Jarvis's reachability, in the fixed header so a long
            // conversation never scrolls it away: a reading as a hint line,
            // and a route that cannot forward, or a main that did not
            // answer, which stops a forward, as a warning notice with the
            // reading's page link (design-system.md).
            LinkText {
                objectName: "mainReachLine"
                visible: root.tab === 0 && text !== "" && !reachNotice.warns
                width: parent.width
                role: "hint"
                text: root.reachText(root.values.mainReach)
                color: Theme.color.textMuted
                wrapMode: Text.Wrap
            }
            Callout {
                id: reachNotice
                objectName: "mainReachNotice"
                readonly property var reach: root.values.mainReach
                readonly property bool warns: reach !== undefined && reach !== null
                    && (reach.kind === "unavailable" || reach.kind === "satellite" && reach.cause !== "")
                visible: root.tab === 0 && warns
                tone: "warning"
                text: warns ? root.reachText(reach) : ""
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
                        placeholderText: "Search messages, tasks and problems"
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

        // Chat: the person's turns on their fill, Jarvis's across the view,
        // and blank while no conversation has begun.
        Column {
            visible: root.tab === 0
            width: layout.contentWidth
            spacing: Theme.stack.row

            Repeater {
                id: transcriptList
                model: root.transcriptRows
                MessageRow {
                    required property var modelData
                    width: layout.contentWidth
                    turn: modelData.role === "user" ? "own" : "reply"
                    marked: root.placement === "held" && WidgetView.isAnswer(modelData, root.markedAnswer)
                    sender: root.speaker(modelData.role)
                    bodyText: String(modelData.text)
                }
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

        // Needs you: the waiting count with Show snoozed and Refresh at its
        // right, the notices an ask action leaves, then one list of cards,
        // the active asks and, when shown, the snoozed ones after them.
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
                Item {
                    width: parent.width
                    height: Math.max(askCount.implicitHeight, askControls.height)
                    Label {
                        id: askCount
                        width: parent.width - askControls.width - Theme.stack.group
                        anchors.verticalCenter: parent.verticalCenter
                        role: "bodyStrong"
                        wrapMode: Text.Wrap
                        text: root.asksReady ? root.asksState.activeCount + " waiting for you" : root.asksState.kind === "reading" ? "Reading your asks…" : "Your asks are unavailable"
                    }
                    Row {
                        id: askControls
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.stack.inline
                        Checkbox {
                            objectName: "showSnoozed"
                            visible: root.asksReady
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Show snoozed"
                            checked: root.snoozedExpanded
                            onToggled: root.snoozedExpanded = checked
                        }
                        // The unavailable notice holds the one Refresh then.
                        IconButton {
                            visible: root.asksState.kind !== "unavailable"
                            anchors.verticalCenter: parent.verticalCenter
                            size: "sm"
                            iconName: "refresh-cw"
                            label: "Refresh"
                            disabledReason: root.pendingAsk === "" ? "" : "Wait for the current ask action to finish."
                            onClicked: root.refreshAsks()
                        }
                    }
                }
                Callout {
                    visible: root.asksState.kind === "unavailable"
                    tone: "warning"
                    iconName: "triangle-alert"
                    plain: true
                    text: visible ? root.asksState.cause : ""
                    linkText: "Refresh"
                    onActivated: root.refreshAsks()
                }
                Callout {
                    visible: text !== ""
                    tone: "danger"
                    iconName: "circle-alert"
                    plain: true
                    text: root.askProblem || root.askOutcome
                }
                // One notice for the ask action Jarvis has not confirmed, or
                // is sending, with Retry while it waits for the person.
                Callout {
                    visible: root.editingAsk === null && root.askRecoveryText !== ""
                    tone: root.askUnconfirmed ? "warning" : "info"
                    iconName: root.askUnconfirmed ? "triangle-alert" : "info"
                    plain: true
                    text: root.askRecoveryText
                    linkText: root.askUnconfirmed ? "Retry" : ""
                    onActivated: root.retryAsk()
                }
                Column {
                    width: parent.width
                    spacing: Theme.stack.group
                    Repeater {
                        id: activeAskRows
                        // ScriptModel string keys retain delegates on Quickshell0.3.1; current payloads stay in the canonical page (DeviceList.qml).
                        model: ScriptModel { values: root.activeAsks.map(row => row.id) }
                        Card {
                            id: activeCard
                            required property var modelData
                            readonly property var ask: root.activeAsks.find(row => row.id === modelData)
                            readonly property bool live: ask !== undefined
                            visible: live
                            width: asksColumn.width
                            MessageRow {
                                width: parent.width
                                padded: false
                                sender: activeCard.live ? activeCard.ask.askedBy.name : ""
                                title: activeCard.live ? activeCard.ask.what : ""
                                bodyText: !activeCard.live || activeCard.ask.statusText === undefined ? "" : activeCard.ask.statusText
                                linkText: activeCard.live ? activeCard.ask.link.label : ""
                                stateText: activeCard.live ? root.askState(activeCard.ask) : ""
                                stateTone: activeCard.live && activeCard.ask.state === "checking" ? "info" : "warning"
                                actions: activeCard.live ? root.askActions(activeCard.ask) : []
                                onSourceActivated: if (activeCard.live) root.openAskLink(activeCard.ask)
                                onActionTriggered: action => { if (activeCard.live) root.chooseAsk(action, activeCard.ask, actionAt(["reply", "done", "later"].indexOf(action))); }
                            }
                        }
                    }
                    Repeater {
                        // ScriptModel string keys retain delegates on Quickshell0.3.1; current payloads stay in the canonical page (DeviceList.qml).
                        model: ScriptModel { values: root.snoozedExpanded && root.asksReady ? root.snoozedAsks.map(row => row.id) : [] }
                        Card {
                            id: snoozedCard
                            required property var modelData
                            readonly property var ask: root.snoozedAsks.find(row => row.id === modelData)
                            readonly property bool live: ask !== undefined
                            visible: live
                            width: asksColumn.width
                            MessageRow {
                                width: parent.width
                                padded: false
                                // No row shows a time: the return time stays
                                // in the snoozed ask's description.
                                Accessible.description: snoozedCard.live ? "Returns " + root.when(Date.parse(snoozedCard.ask.snoozedUntil)) : ""
                                sender: snoozedCard.live ? snoozedCard.ask.askedBy.name : ""
                                title: snoozedCard.live ? snoozedCard.ask.what : ""
                                linkText: snoozedCard.live ? snoozedCard.ask.link.label : ""
                                stateText: "Snoozed"
                                actions: snoozedCard.live ? root.askActions(snoozedCard.ask) : []
                                onSourceActivated: if (snoozedCard.live) root.openAskLink(snoozedCard.ask)
                                onActionTriggered: action => { if (snoozedCard.live) root.chooseAsk(action, snoozedCard.ask, actionAt(["reply", "done", "later"].indexOf(action))); }
                            }
                        }
                    }
                }
                RowActions {
                    visible: root.asksReady
                    RowAction { text: "Next asks"; visible: root.asksReady && root.asksState.activeNextCursor !== null; disabledReason: root.pendingAsk === "" ? "" : "Wait for the current ask action to finish."; onClicked: root.askPage("active", false) }
                    RowAction { text: "Back to first"; visible: root.asksReady && root.asksState.activeCursor !== null; disabledReason: root.pendingAsk === "" ? "" : "Wait for the current ask action to finish."; onClicked: root.askPage("active", true) }
                    RowAction { text: "Next snoozed asks"; visible: root.snoozedExpanded && root.asksReady && root.asksState.snoozedNextCursor !== null; disabledReason: root.pendingAsk === "" ? "" : "Wait for the current ask action to finish."; onClicked: root.askPage("snoozed", false) }
                    RowAction { text: "Back to first snoozed"; visible: root.snoozedExpanded && root.asksReady && root.asksState.snoozedCursor !== null; disabledReason: root.pendingAsk === "" ? "" : "Wait for the current ask action to finish."; onClicked: root.askPage("snoozed", true) }
                }
            }
        }

        Section {
            visible: root.showConversations
            width: layout.contentWidth
            title: "Messages"
            Repeater {
                model: root.historyRows
                MessageRow {
                    required property var modelData
                    width: layout.contentWidth
                    turn: modelData.role === "user" ? "own" : "reply"
                    sender: root.speaker(modelData.role)
                    bodyText: modelData.text
                }
            }
            EmptyState { visible: root.historyRows.length === 0; width: parent.width; placement: "top"; text: root.historyQuery === "" ? "No messages yet" : "No matching messages" }
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
                Callout { visible: root.problem !== ""; tone: "danger"; iconName: "circle-alert"; plain: true; text: root.problem }
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
                            padded: false
                            sender: live ? task.agent : ""
                            title: live ? task.goal : ""
                            bodyText: live ? root.taskFailure(task) : ""
                            stateText: live ? root.taskState(task) : ""
                            stateTone: live ? root.taskTone(task) : "neutral"
                            actions: live ? root.taskActions(task) : []
                            onActionTriggered: action => { if (live) root.taskAction(action, task, actionAt(actions.findIndex(item => item.id === action))); }
                        }
                    }
                    EmptyState { width: parent.width; visible: root.taskRows.length === 0; placement: "top"; text: "No coding tasks" }
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
                GroupList {
                    id: auditList
                    width: parent.width
                    Repeater {
                        model: root.historyProblems
                        MessageRow {
                            required property var modelData
                            width: auditList.width
                            padded: false
                            sender: "Jarvis"
                            title: modelData.title
                            bodyText: modelData.body
                            linkText: modelData.action
                            onSourceActivated: root.problemAction(modelData)
                        }
                    }
                    EmptyState { width: parent.width; visible: root.historyProblems.length === 0; placement: "top"; text: root.historyQuery === "" ? "No recent failures" : "No matching problems" }
                }
            }
        }

        footer: [
            Column {
                id: composer
                visible: root.tab === 0
                width: layout.contentWidth
                spacing: Theme.stack.group

                // Under a voice that takes speech only, the one sentence on
                // how to talk, over the locked message box.
                Callout {
                    id: speechNotice
                    visible: root.speechOnly
                    tone: "info"
                    iconName: "info"
                    text: root.speechOnlyText
                    linkText: "Voice settings"
                    onActivated: root.shell.surfaces.openPage("vgs.jarvis", "Settings/voiceProvider")
                    onPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
                }
                // What the last message, Stop or memory answer could not do.
                Callout {
                    visible: root.problem !== ""
                    tone: "danger"
                    iconName: "circle-alert"
                    plain: true
                    text: root.problem
                }

                // The message box: the text over one row of the model and
                // effort at its left and Send, or Stop while Jarvis works, at
                // its right, all in the text's own frame (TextArea `framed`).
                Item {
                    id: composerBox
                    width: parent.width
                    implicitHeight: draftScroll.height + composerRow.height + Theme.textField.paddingX

                    FieldFrame { anchors.fill: parent; target: entryField }

                    ScrollArea {
                        id: draftScroll
                        width: parent.width
                        implicitHeight: Math.min(entryField.implicitHeight, Theme.size.control.lg * 8)
                        keyboardScroll: false
                        // TextEdit does not scroll itself. The shared ScrollArea
                        // owns wheel/overflow; cursor changes reveal its line.
                        // https://doc.qt.io/qt-6/qml-qtquick-textedit.html
                        TextArea {
                            id: entryField
                            width: draftScroll.contentWidth
                            framed: false
                            minimumHeight: 0
                            placeholderText: "Message Jarvis"
                            textFormat: TextEdit.PlainText
                            disabledReason: root.speechOnly ? "Typing is off for this voice." : ""
                            onCursorRectangleChanged: {
                                draftScroll.contentY = Math.max(0, Math.min(draftScroll.contentHeight - draftScroll.height,
                                    Math.max(cursorRectangle.y + cursorRectangle.height - draftScroll.height,
                                        Math.min(draftScroll.contentY, cursorRectangle.y))));
                            }
                            Keys.onPressed: event => {
                                if (root.handleBacktab(event)) return;
                                // Tab leaves the box for its own controls; a
                                // message holds no tab character.
                                if (root.traverse(event)) { event.accepted = true; return; }
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

                    Item {
                        id: composerRow
                        x: Theme.textField.paddingX
                        y: draftScroll.height
                        width: parent.width - 2 * Theme.textField.paddingX
                        height: Math.max(choices.height, sendButton.height)
                        Row {
                            id: choices
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.stack.inline
                            Select {
                                id: modelSelect
                                Keys.onPressed: event => root.traverseKey(event)
                                objectName: "modelSelect"
                                visible: root.modelChoices.length > 0
                                quiet: true
                                textRole: "label"
                                placeholderText: "Choose a model"
                                model: root.modelChoices
                                currentIndex: root.choiceIndex("model", root.modelChoices)
                                Accessible.name: "AI model: " + currentText
                                onActivated: index => {
                                    currentIndex = Qt.binding(() => root.choiceIndex("model", root.modelChoices));
                                    root.askChoice("model", root.modelChoices, index, modelSelect);
                                }
                            }
                            Select {
                                id: effortSelect
                                Keys.onPressed: event => root.traverseKey(event)
                                objectName: "effortSelect"
                                visible: root.effortChoices.length > 0
                                quiet: true
                                textRole: "label"
                                placeholderText: "Choose effort"
                                model: root.effortChoices
                                currentIndex: root.choiceIndex("effort", root.effortChoices)
                                Accessible.name: "Effort: " + currentText
                                onActivated: index => {
                                    currentIndex = Qt.binding(() => root.choiceIndex("effort", root.effortChoices));
                                    root.askChoice("effort", root.effortChoices, index, effortSelect);
                                }
                            }
                        }
                        IconButton {
                            id: sendButton
                            Keys.onPressed: event => root.traverseKey(event)
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !root.working && !root.speechOnly
                            variant: "primary"
                            radius: Theme.button.roundRadius
                            iconName: "arrow-up"
                            label: "Send message"
                            disabledReason: root.sendReason()
                            onClicked: root.sendMessage()
                        }
                        IconButton {
                            id: stopButton
                            Keys.onPressed: event => root.traverseKey(event)
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.working
                            variant: "danger"
                            radius: Theme.button.roundRadius
                            iconName: "square"
                            label: "Stop Jarvis"
                            tooltip: root.spelledKeys.stop === null ? "Stop Jarvis" : "Stop Jarvis " + root.spelledKeys.stop
                            onClicked: root.stop()
                        }
                    }
                }
            }
        ]
    }
    // The end of the console's content in Qt's item order, whose title row,
    // New conversation, More and Settings, comes before the tabs. Forward,
    // Qt wraps from the last control of Needs you or History to New
    // conversation: this stop takes that wrap and hands it to the tabs,
    // where the header order starts. Backward, traverse sends Backtab from
    // the tabs to the item before this stop, the content's last control.
    // focus-indicator: the tabs' ring, since this stop gives them its focus at once
    Item {
        id: tabWrap
        objectName: "tabWrap"
        activeFocusOnTab: true
        onActiveFocusChanged: if (activeFocus) consoleTabs.forceActiveFocus(Qt.TabFocusReason)
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
                // The editor hides the list's recovery notice, so it names
                // the action Jarvis has not confirmed itself.
                Label { visible: text !== ""; width: parent.width; role: "hint"; text: root.askProblem || root.askOutcome || (root.askUnconfirmed ? root.askRecoveryText : ""); color: Theme.color.danger; wrapMode: Text.Wrap; textFormat: Text.PlainText }
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
    // A model or effort change, asked before it ends the conversation.
    Item {
        anchors.fill: parent
        visible: root.pendingChoice !== null
        Scrim { onClicked: root.closeChoice(false) }
        Dialog {
            id: choiceDialog
            readonly property bool model: root.pendingChoice !== null && root.pendingChoice.key === "model"
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 2 * Theme.dialog.margin)
            availableHeight: parent.height - 2 * Theme.dialog.margin
            title: model ? "Change the AI model?" : "Change the effort?"
            message: "This ends the conversation and starts a new one."
            actions: [{ label: model ? "Change model" : "Change effort", role: "accept" }, { label: "Cancel", role: "cancel" }]
            onAccepted: root.closeChoice(true)
            onRejected: root.closeChoice(false)
        }
    }
}
