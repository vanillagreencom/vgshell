import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "AccountProviders.js" as Providers
import "AccountStatus.js" as Words
import "SetupGate.js" as Gate

// One metadata reader. An accounts TUI end invalidates its old discovery.
// It publishes the accounts, the brain choices and the search's outcome in
// the page's words; a failure's safe cause goes to the log alone. A second
// reader, the chosen sign-in's model list, runs only as the Settings window
// shows the Jarvis page or while the console is open (consoleShown).
Item {
    id: root
    property var shell: null
    property bool pending: false
    property var completion: ({ kind: "starting" })
    property var diagnostic: ({ kind: "collected", text: "" })
    property string output: ""
    property var modelAccess: ({ kind: "checking" })
    // The stored cloud voice keys of the last read, each with its provider,
    // undefined while no read has an answer: before the first one and after
    // a failed one.
    property var voiceKeys: undefined
    // The provider of each offered AI model choice by its id, from the last
    // read; none before its answer and after a failed one.
    property var providers: ({})
    readonly property string brain: shell === null ? "" : shell.settings.brain
    // The sign-in and the model save() last saw, null before its first
    // sight of them.
    property var seenBrain: null
    property var seenModel: null
    onBrainChanged: Qt.callLater(save)
    // Whether the console is open, which offers the list's model and
    // effort choices as the page does (Service.qml `console-choices`).
    property bool consoleShown: false
    // The sign-in whose model list the page or the console wants: the
    // chosen one while either shows, else none. Nothing else starts a list
    // read: not the shell's start and not another setting's change.
    readonly property string wanted: shell !== null && (shell.status.viewed || consoleShown) ? brain : ""
    onWantedChanged: readList(shell !== null && shell.status.viewed || listed.kind === "failed")
    // The last read, of sign-in `brain`, kept while nothing shows: `kind` is
    // "reading" until it ends, then readOffers' answer; "none" before the
    // first read and after an accounts change (forgetList).
    property var listed: ({ brain: "", kind: "none" })
    // The chosen sign-in's own read: one for another sign-in counts as none.
    readonly property var list: listed.brain === brain ? listed : ({ kind: "none" })
    // The page's model and effort choices, the model a model field shows,
    // and the model and effort a read list saves.
    readonly property var choice: Providers.modelChoice(shell === null ? ({ model: "", effort: "" }) : shell.settings, list, providers[brain])
    onChoiceChanged: publishChoice()
    readonly property var tuiState: shell === null ? null : shell.tui.state["accounts"]
    readonly property var keyState: shell === null ? null : shell.tui.state["add-key"]
    readonly property var voiceKeyState: shell === null ? null : shell.tui.state["add-voice-key"]
    readonly property var voiceKeyEndedAt: voiceKeyState === null || voiceKeyState === undefined ? null : voiceKeyState.endedAt
    // The Voice keys the last read offered when Add a key ended, until the
    // read that end starts has published; undefined otherwise. The key that
    // read adds is the one the user just stored, which Jarvis selects.
    property var addedFrom: undefined
    onVoiceKeyEndedAtChanged: {
        if (voiceKeyEndedAt === null) return;
        addedFrom = voiceKeys;
        refresh();
    }
    readonly property var removeState: shell === null ? null : shell.tui.state["remove-key"]
    readonly property var signInState: shell === null ? null : shell.tui.state["sign-in"]
    readonly property var endedAt: tuiState === null || tuiState === undefined ? null : tuiState.endedAt
    readonly property var keyEndedAt: keyState === null || keyState === undefined ? null : keyState.endedAt
    readonly property var removeEndedAt: removeState === null || removeState === undefined ? null : removeState.endedAt
    // The Voice keys the last read offered when Remove key ended, until the
    // read that end starts has published; undefined otherwise.
    property var removedFrom: undefined
    readonly property var signInEndedAt: signInState === null || signInState === undefined ? null : signInState.endedAt
    // The Voice key choices are the keys of the selected cloud voice's
    // provider, so a change of Voice provider publishes them again from the
    // last read. configure.set replaces `shell`, which this binding reads,
    // so the publication waits for the event loop (see save()).
    readonly property string voiceKeyProvider: voice === null ? "" : voice.provider
    // The cloud voice the settings name (AccountProviders.cloudVoice), null
    // for Local or without a shell.
    readonly property var voice: shell === null ? null : Providers.cloudVoice(shell.settings.voiceProvider)
    onVoiceKeyProviderChanged: Qt.callLater(republishVoice)
    readonly property string program: String(Qt.resolvedUrl("backend/accounts.js")).replace(/^file:\/\//, "")
    onShellChanged: refresh()
    onEndedAtChanged: if (endedAt !== null) { refresh(); forgetList(); }
    onKeyEndedAtChanged: if (keyEndedAt !== null) { refresh(); forgetList(); }
    onRemoveEndedAtChanged: {
        if (removeEndedAt === null) return;
        removedFrom = voiceKeys;
        refresh();
        forgetList();
    }
    onSignInEndedAtChanged: if (signInEndedAt !== null) { refresh(); forgetList(); }
    // Emitted once each check has published, whatever it read.
    signal refreshed()

    // Write the model and effort the page's state asks for. A model belongs
    // to its sign-in's list: a sign-in changed on the page drops the saved
    // model and effort, the first sight of the saved sign-in is no change,
    // and a read list saves its choice while the page shows. Without the
    // page a write ends the conversation, which the console does only after
    // asking, so a read saves nothing then and leaves an unset model unset,
    // except the effort of a model changed to another one: that change has
    // ended the conversation already. configure.set replaces `shell`
    // before it returns, so a call from the change handler of `brain` or
    // `choice` updates that binding inside its own update: Qt logs a
    // binding loop and keeps the old value, as a run of
    // scripts/qml-tests/tst_jarvis_accounts.qml under qmltestrunner 6.11.2
    // shows. Qt.callLater runs this once the engine is back in the event
    // loop, one call for the changes of a turn
    // (https://doc.qt.io/qt-6/qml-qtqml-qt.html#callLater-method), so it
    // judges the sign-in, the list and the settings it finds then.
    function save() {
        if (shell === null) return;
        const changed = seenBrain !== null && seenBrain !== brain && shell.status.viewed;
        const modelChanged = seenModel !== null && seenModel !== shell.settings.model && shell.settings.model !== "";
        seenBrain = brain;
        seenModel = shell.settings.model;
        const fills = shell.status.viewed || modelChanged;
        const wanted = changed ? { model: "", effort: "" } : list.kind === "read" && fills ? choice : shell.settings;
        for (const key of ["model", "effort"])
            if (wanted[key] !== shell.settings[key] && shell.configure.set(key, wanted[key]) !== "ok")
                console.warn("jarvis-accounts: model-selection=refused");
    }

    function publishChoice() {
        if (shell === null) return;
        const replies = [shell.status.set("models", choice.models), shell.status.set("modelShown", choice.shown),
            shell.status.set("efforts", choice.efforts)];
        if (replies.some(reply => !shell.status.isOk(reply)))
            throw new Error("jarvis-accounts: status=refused");
        if (replies.some(reply => reply !== "ok")) return;
        Qt.callLater(save);
    }

    // Start the read `wanted` names, unless the kept read is that sign-in's
    // and AGAIN does not ask for a fresh one: the console reads a sign-in's
    // list once, not on each open, since a CLI sign-in's read starts its
    // vendor's program, and Copilot's leaves a session in the account's
    // history (CopilotHarness.models). The page's show asks again, and so
    // does the next show after a failed read (onWantedChanged), whose cause,
    // such as a local server that was not running yet, can pass by then; the
    // failed read's own end does not, so it starts no loop. One program runs at a
    // time: a running read runs to its end, where its helper removes its
    // program's private folder, keeps its answer for its own sign-in, and
    // starts the read wanted then.
    function readList(again) {
        if (wanted === "" || listed.brain === wanted && listed.kind !== "none" && !again) return;
        if (lister.running) {
            lister.again = true;
            return;
        }
        listed = { brain: wanted, kind: "reading" };
        lister.output = "";
        lister.command = ["node", program, "--tree", Quickshell.shellDir + "/..", "models", wanted];
        lister.running = true;
    }

    // An accounts change can change any sign-in's list: the kept read goes,
    // and a shown page or console reads again.
    function forgetList() {
        listed = { brain: "", kind: "none" };
        readList(false);
    }

    function listRead(text) {
        if (listed.kind !== "reading") return;
        let answer;
        try { answer = JSON.parse(text); } catch (error) { answer = { kind: "failed", reason: "helper" }; }
        if (answer.kind === "failed") console.warn("jarvis-accounts: models=" + answer.reason);
        listed = Object.assign({ brain: listed.brain }, answer);
    }

    function refresh() {
        if (shell === null) return;
        if (probe.running) { pending = true; return; }
        pending = false;
        completion = { kind: "starting" };
        diagnostic = { kind: "collected", text: "" };
        output = "";
        probe.command = ["node", program, "--tree", Quickshell.shellDir + "/..", "presence", JSON.stringify(Providers.keyPresence(name => Quickshell.env(name)))];
        probe.running = true;
    }
    // The Voice key choices and the key row for KEYS, the last read's cloud
    // voice keys, under the Voice provider the settings name now, and the
    // key Jarvis selects for the user. KEYS holds only present references.
    // configure.set writes the plugin's row through the core writer. A
    // queued refresh can publish status, but cannot select a stale key.
    // After Remove key, a Voice key offered before it (removedFrom) that
    // KEYS no longer holds is the removed key: the choice is cleared in the
    // same step, never left naming a key that is gone, and the sole key
    // left, if any, is then selected.
    function publishVoice(keys) {
        const voice = Providers.cloudVoice(shell.settings.voiceProvider);
        const voiceChoices = Gate.voiceKeys(keys, voice);
        const choices = shell.status.set("voiceAccounts", voiceChoices);
        if (!shell.status.isOk(choices)) throw new Error("jarvis-accounts: status=refused");
        if (choices !== "ok") return false;
        if (removedFrom !== undefined && !pending) {
            const named = key => key.value === shell.settings.voiceAccount;
            const gone = removedFrom.some(named) && !keys.some(named);
            removedFrom = undefined;
            if (gone && shell.configure.set("voiceAccount", "") !== "ok")
                console.warn("jarvis-accounts: voice-selection=refused");
        }
        let chosen = pending ? null : Gate.voiceChoice(keys, voice, shell.settings.voiceAccount);
        if (addedFrom !== undefined && !pending) {
            const added = Gate.voiceAdded(addedFrom, keys, voice);
            addedFrom = undefined;
            if (added !== null) chosen = added;
        }
        if (chosen !== null && chosen !== shell.settings.voiceAccount && shell.configure.set("voiceAccount", chosen) !== "ok")
            console.warn("jarvis-accounts: voice-selection=refused");
        return true;
    }
    function republishVoice() {
        if (shell !== null && voiceKeys !== undefined) publishVoice(voiceKeys);
    }
    function publish() {
        const code = completion.kind === "exited" ? completion.code : -1;
        try {
            if (code !== 0) throw new Error("probe");
            const value = JSON.parse(output);
            modelAccess = Gate.accountAccess(value.accounts);
            voiceKeys = value.voiceAccounts;
            providers = value.providers;
            const accounts = value.accounts.map(item => Words.accountHint(item) === "" ? { label: item.label, value: item.value }
                : { label: item.label, value: item.value, hint: Words.accountHint(item) });
            const search = Words.searchValue({ kind: "found", found: value.search.found, partial: value.search.partial }, PageReference);
            const replies = [shell.status.set("accounts", accounts), shell.status.set("brains", value.brains),
                shell.status.set("accountSearch", search), shell.status.set("copilotMemory", Gate.copilotMemory(value.accounts))];
            if (replies.some(reply => !shell.status.isOk(reply))) throw new Error("status");
            if (replies.some(reply => reply !== "ok")) return false;
            if (!publishVoice(value.voiceAccounts)) return false;
        } catch (error) {
            modelAccess = { kind: "checking" };
            voiceKeys = undefined;
            providers = {};
            const reason = Providers.probeFailure(completion, diagnostic);
            console.warn(reason);
            const replies = [shell.status.set("accounts", []), shell.status.set("brains", []), shell.status.set("voiceAccounts", []),
                shell.status.set("accountSearch", Words.searchValue({ kind: "failed", reason: reason })),
                shell.status.set("copilotMemory", Gate.copilotMemory([]))];
            if (replies.some(reply => !shell.status.isOk(reply))) throw new Error("jarvis-accounts: status=refused");
            if (replies.some(reply => reply !== "ok")) return false;
        }
        refreshed();
        return true;
    }
    Process {
        id: probe
        clearEnvironment: true
        environment: ({
            PATH: Quickshell.env("PATH"), HOME: Quickshell.env("HOME"),
            XDG_CONFIG_HOME: Quickshell.env("XDG_CONFIG_HOME"), XDG_STATE_HOME: Quickshell.env("XDG_STATE_HOME"),
            XDG_DATA_HOME: Quickshell.env("XDG_DATA_HOME"), XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR"),
            DBUS_SESSION_BUS_ADDRESS: Quickshell.env("DBUS_SESSION_BUS_ADDRESS"),
            CLAUDE_CONFIG_DIR: Quickshell.env("CLAUDE_CONFIG_DIR"), CODEX_HOME: Quickshell.env("CODEX_HOME"),
            COPILOT_HOME: Quickshell.env("COPILOT_HOME"), PI_CODING_AGENT_DIR: Quickshell.env("PI_CODING_AGENT_DIR"),
            LANG: "C.UTF-8"
        })
        stdout: StdioCollector { onStreamFinished: root.output = text }
        stderr: SplitParser {
            splitMarker: ""
            onRead: data => root.diagnostic = Providers.feedDiagnostic(root.diagnostic, data)
        }
        onExited: (code, status) => root.completion = status === 0 ? { kind: "exited", code: code } : { kind: "crashed" }
        onRunningChanged: {
            if (running) return;
            if (root.publish() && root.pending) Qt.callLater(root.refresh);
        }
    }
    Process {
        id: lister
        // True while a fresh read waits for this one's end.
        property bool again: false
        property string output: ""
        clearEnvironment: true
        environment: probe.environment
        stdout: StdioCollector { onStreamFinished: lister.output = text }
        onRunningChanged: {
            if (running) return;
            root.listRead(output);
            const fresh = again;
            again = false;
            root.readList(fresh);
        }
    }
}
