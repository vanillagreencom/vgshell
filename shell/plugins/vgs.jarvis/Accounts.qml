import QtQuick
import Quickshell
import Quickshell.Io
import "AccountProviders.js" as Providers
import "AccountStatus.js" as Words
import "SetupGate.js" as Gate

// One metadata reader. An accounts TUI end invalidates its old discovery.
// It publishes the accounts, the brain choices and the search's outcome in
// the page's words; a failure's safe cause goes to the log alone. A second
// reader, the chosen sign-in's model list, runs only while the Settings
// window shows the Jarvis page.
Item {
    id: root
    property var shell: null
    property bool pending: false
    property var completion: ({ kind: "starting" })
    property var diagnostic: ({ kind: "collected", text: "" })
    property string output: ""
    property var modelAccess: ({ kind: "checking" })
    // The stored OpenAI keys of the last read, undefined while no read has
    // an answer: before the first one and after a failed one.
    property var voiceKeys: undefined
    readonly property string brain: shell === null ? "" : shell.settings.brain
    // The sign-in this reader last saw, null before its first sight of one.
    property var seenBrain: null
    // A model belongs to its sign-in's list: a sign-in changed on the page
    // drops the saved model and effort, and the new list's read saves its
    // own. The first sight of the saved sign-in is no change.
    onBrainChanged: {
        if (shell !== null && seenBrain !== null && shell.status.viewed) save("", "");
        seenBrain = shell === null ? null : brain;
    }
    // The sign-in whose model list the page wants: the chosen one while the
    // Jarvis page is shown, else none. Nothing else starts a list read: not
    // the shell's start and not another setting's change.
    readonly property string wanted: shell !== null && shell.status.viewed ? brain : ""
    onWantedChanged: readList()
    // The read for sign-in `brain`: `kind` is "reading" until it ends, then
    // readOffers' answer; "none" with no read.
    property var listed: ({ brain: "", kind: "none" })
    // The chosen sign-in's own read: one for another sign-in counts as none.
    readonly property var list: listed.brain === brain ? listed : ({ kind: "none" })
    // The page's model and effort choices, and the model and effort a read
    // list saves: Jarvis runs what is saved, with no list read.
    readonly property var choice: Providers.modelChoice(shell === null ? ({ model: "", effort: "" }) : shell.settings, list)
    onChoiceChanged: publishChoice()
    readonly property var tuiState: shell === null ? null : shell.tui.state["accounts"]
    readonly property var keyState: shell === null ? null : shell.tui.state["add-key"]
    readonly property var signInState: shell === null ? null : shell.tui.state["sign-in"]
    readonly property var endedAt: tuiState === null || tuiState === undefined ? null : tuiState.endedAt
    readonly property var keyEndedAt: keyState === null || keyState === undefined ? null : keyState.endedAt
    readonly property var signInEndedAt: signInState === null || signInState === undefined ? null : signInState.endedAt
    readonly property var missing: shell === null ? [] : shell.requirements.missing
    onMissingChanged: publishRequirements()
    readonly property string program: String(Qt.resolvedUrl("backend/accounts.js")).replace(/^file:\/\//, "")
    onShellChanged: refresh()
    onEndedAtChanged: if (endedAt !== null) refresh()
    onKeyEndedAtChanged: if (keyEndedAt !== null) refresh()
    onSignInEndedAtChanged: if (signInEndedAt !== null) refresh()
    // Emitted once each check has published, whatever it read.
    signal refreshed()

    function publishRequirements() {
        if (shell === null) return;
        for (const command of ["claude", "codex"])
            if (shell.status.set(command, Gate.requirementValue(command, missing)) !== "ok")
                throw new Error("jarvis-accounts: status=refused");
    }

    function save(model, effort) {
        if ((model !== shell.settings.model && shell.configure.set("model", model) !== "ok")
                || (effort !== shell.settings.effort && shell.configure.set("effort", effort) !== "ok"))
            console.warn("jarvis-accounts: model-selection=refused");
    }

    function publishChoice() {
        if (shell === null) return;
        if (shell.status.set("models", choice.models) !== "ok" || shell.status.set("efforts", choice.efforts) !== "ok")
            throw new Error("jarvis-accounts: status=refused");
        if (list.kind === "read") save(choice.model, choice.effort);
    }

    // Start the read `wanted` names. A running read is ended first and its
    // end starts this one, so one program runs at a time and the answer of
    // a read for an earlier sign-in, or for a page since closed, is dropped.
    function readList() {
        if (lister.running) {
            lister.dropped = true;
            lister.running = false;
            return;
        }
        listed = { brain: wanted, kind: wanted === "" ? "none" : "reading" };
        if (wanted === "") return;
        lister.output = "";
        lister.command = ["node", program, "--tree", Quickshell.shellDir + "/..", "models", wanted];
        lister.running = true;
    }

    function listRead(text) {
        let answer;
        try { answer = JSON.parse(text); } catch (error) { answer = { kind: "failed", reason: "helper" }; }
        if (answer.kind === "failed") console.warn("jarvis-accounts: models=" + answer.reason);
        listed = Object.assign({ brain: listed.brain }, answer);
    }

    function refresh() {
        if (shell === null) return;
        publishRequirements();
        if (probe.running) { pending = true; return; }
        pending = false;
        completion = { kind: "starting" };
        diagnostic = { kind: "collected", text: "" };
        output = "";
        probe.command = ["node", program, "--tree", Quickshell.shellDir + "/..", "presence", JSON.stringify(Providers.keyPresence(name => Quickshell.env(name)))];
        probe.running = true;
    }
    function publish() {
        const code = completion.kind === "exited" ? completion.code : -1;
        try {
            if (code !== 0) throw new Error("probe");
            const value = JSON.parse(output);
            modelAccess = Gate.accountAccess(value.accounts);
            voiceKeys = value.voiceAccounts;
            const accounts = value.accounts.map(item => Words.accountHint(item) === "" ? { label: item.label, value: item.value }
                : { label: item.label, value: item.value, hint: Words.accountHint(item) });
            const search = Words.searchValue({ kind: "found", found: value.search.found, partial: value.search.partial });
            if (shell.status.set("accounts", accounts) !== "ok" || shell.status.set("brains", value.brains) !== "ok"
                || shell.status.set("voiceAccounts", value.voiceAccounts) !== "ok"
                || shell.status.set("voiceKey", Gate.voiceKey(value.voiceAccounts)) !== "ok"
                || shell.status.set("accountSearch", search) !== "ok"
                || shell.status.set("copilotMemory", Gate.copilotMemory(value.accounts)) !== "ok"
                || shell.status.set("setupSignIn", { tone: "info", text: "Optional", action: true }) !== "ok") throw new Error("status");
            // voiceAccounts already contains only present OpenAI key references.
            // configure.set uses the core writer for every entry the service reads.
            // A queued refresh can publish status, but cannot select a stale key.
            if (!pending && shell.settings.voiceAccount === "" && value.voiceAccounts.length === 1) {
                if (shell.configure.set("voiceAccount", value.voiceAccounts[0].value) !== "ok")
                    console.warn("jarvis-accounts: voice-selection=refused");
            }
        } catch (error) {
            modelAccess = { kind: "checking" };
            voiceKeys = undefined;
            const reason = Providers.probeFailure(completion, diagnostic);
            console.warn(reason);
            const replies = [shell.status.set("accounts", []), shell.status.set("brains", []), shell.status.set("voiceAccounts", []),
                shell.status.set("accountSearch", Words.searchValue({ kind: "failed", reason: reason })),
                shell.status.set("copilotMemory", Gate.copilotMemory([])), shell.status.set("voiceKey", Gate.voiceKey(null)),
                shell.status.set("setupSignIn", { tone: "info", text: "Optional", action: true })];
            if (replies.some(reply => reply !== "ok")) throw new Error("jarvis-accounts: status=refused");
        }
        refreshed();
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
            root.publish();
            if (root.pending) Qt.callLater(root.refresh);
        }
    }
    Process {
        id: lister
        // True while its end is one readList asked for.
        property bool dropped: false
        property string output: ""
        clearEnvironment: true
        environment: probe.environment
        stdout: StdioCollector { onStreamFinished: lister.output = text }
        onRunningChanged: {
            if (running) return;
            if (dropped) {
                dropped = false;
                root.readList();
            } else root.listRead(output);
        }
    }
}
