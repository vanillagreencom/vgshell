import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "UsageView.js" as View

// The one reader of AI plan usage. It runs backend/usage.js at start, on
// its check interval, when the panel asks and after a sign-in TUI ends, and
// publishes what it read as `usage` with the two sign-in rows. A read asked
// for while one runs starts once it ends. The widget and the panel draw
// status alone.
Item {
    id: root
    property var shell: null
    property bool registered: false
    property bool pending: false
    // The usage published last, which a failed read keeps marked stale.
    property var usage: null
    property string output: ""
    property int code: -1
    readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("backend/usage.js")).replace(/^file:\/\//, ""))
    readonly property int intervalMs: (shell === null ? 15 : shell.settings.refreshMinutes) * 60000
    readonly property bool gatewayEnabled: shell !== null && shell.settings.aiGateway === true
    readonly property var claudeEnded: ended("sign-in-claude")
    readonly property var codexEnded: ended("sign-in-codex")

    onShellChanged: start()
    onClaudeEndedChanged: if (claudeEnded !== null) refresh()
    onCodexEndedChanged: if (codexEnded !== null) refresh()

    function ended(name) {
        const state = shell === null ? undefined : shell.tui.state[name];
        return state === undefined || state === null ? null : state.endedAt;
    }

    function start() {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("refresh", () => { root.refresh(); return "ok"; });
        refresh();
    }

    function refresh() {
        if (shell === null) return;
        if (reader.running) { pending = true; return; }
        pending = false;
        output = "";
        code = -1;
        const command = ["node", helper, "--tree", Quickshell.shellDir + "/.."]
        if (gatewayEnabled) command.push("--gateway");
        reader.command = command;
        reader.running = true;
    }

    // The helper's line, or null for a run that failed or answered another
    // shape; the failure goes to the log by its exit code alone.
    function reading() {
        if (code !== 0) return null;
        try {
            const value = JSON.parse(output);
            if (value !== null && typeof value === "object" && Array.isArray(value.accounts)) return value;
        } catch (error) {}
        return null;
    }

    function finished() {
        const value = reading();
        if (value === null) console.warn("ai-usage: read=failed exit=" + code);
        usage = View.merge(usage, value, Date.now());
        for (const [key, entry] of [["usage", usage], ["accounts", View.accountChoices(usage)], ["claude", View.signIn(usage, "claude")], ["codex", View.signIn(usage, "codex")], ["gatewayKey", View.gatewayKey(gatewayEnabled && usage.gatewayKey !== null ? usage.gatewayKey : "absent")]]) {
            const reply = shell.status.set(key, entry);
            if (reply !== "ok") console.warn("ai-usage: status=" + key + " " + reply);
        }
    }

    Timer {
        interval: root.intervalMs
        running: root.shell !== null
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: reader
        clearEnvironment: true
        // The explicit account roots reach the helper beside the homes.
        environment: Object.assign({
            PATH: Quickshell.env("PATH"), HOME: Quickshell.env("HOME"),
            XDG_CONFIG_HOME: Quickshell.env("XDG_CONFIG_HOME"), XDG_DATA_HOME: Quickshell.env("XDG_DATA_HOME"),
            DBUS_SESSION_BUS_ADDRESS: Quickshell.env("DBUS_SESSION_BUS_ADDRESS"), XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR"),
            LANG: "C.UTF-8"
        }, AccountDirectories.accountVariables(name => Quickshell.env(name)))
        stdout: StdioCollector { onStreamFinished: root.output = text }
        // Only the helper's own keyed lines reach the log.
        stderr: SplitParser { onRead: line => { if (View.keyed(line)) console.warn(line); } }
        onExited: (exitCode, exitStatus) => root.code = exitStatus === 0 ? exitCode : -1
        onRunningChanged: {
            if (running) return;
            root.finished();
            if (root.pending) Qt.callLater(root.refresh);
        }
    }
}
