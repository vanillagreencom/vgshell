import QtQuick
import Quickshell
import Quickshell.Io
import "AccountProviders.js" as Providers
import "AccountStatus.js" as Words
import "SetupGate.js" as Gate

// One metadata reader. An accounts TUI end invalidates its old discovery.
// It publishes the accounts, the brain choices and the search's outcome in
// the page's words; a failure's safe cause goes to the log alone.
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
}
