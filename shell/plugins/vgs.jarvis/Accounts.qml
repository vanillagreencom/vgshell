import QtQuick
import Quickshell
import Quickshell.Io
import "AccountProviders.js" as Providers
import "AccountStatus.js" as Words

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
    readonly property var tuiState: shell === null ? null : shell.tui.state["accounts"]
    readonly property var keyState: shell === null ? null : shell.tui.state["add-key"]
    readonly property var endedAt: tuiState === null || tuiState === undefined ? null : tuiState.endedAt
    readonly property var keyEndedAt: keyState === null || keyState === undefined ? null : keyState.endedAt
    readonly property string program: String(Qt.resolvedUrl("backend/accounts.js")).replace(/^file:\/\//, "")
    onShellChanged: refresh()
    onEndedAtChanged: if (endedAt !== null) refresh()
    onKeyEndedAtChanged: if (keyEndedAt !== null) refresh()

    function refresh() {
        if (shell === null) return;
        if (probe.running) { pending = true; return; }
        pending = false;
        completion = { kind: "starting" };
        diagnostic = { kind: "collected", text: "" };
        output = "";
        probe.command = ["node", program, "presence", JSON.stringify(Providers.keyPresence(name => Quickshell.env(name)))];
        probe.running = true;
    }
    function publish() {
        const code = completion.kind === "exited" ? completion.code : -1;
        try {
            if (code !== 0) throw new Error("probe");
            const value = JSON.parse(output);
            const accounts = value.accounts.map(item => ({ label: item.label, value: item.value, hint: Words.accountHint(item) }));
            const search = Words.searchValue({ kind: "found", found: value.search.found, partial: value.search.partial });
            if (shell.status.set("accounts", accounts) !== "ok" || shell.status.set("brains", value.brains) !== "ok"
                || shell.status.set("accountSearch", search) !== "ok") throw new Error("status");
        } catch (error) {
            const reason = Providers.probeFailure(completion, diagnostic);
            console.warn(reason);
            const replies = [shell.status.set("accounts", []), shell.status.set("brains", []),
                shell.status.set("accountSearch", Words.searchValue({ kind: "failed", reason: reason }))];
            if (replies.some(reply => reply !== "ok")) throw new Error("jarvis-accounts: status=refused");
        }
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
