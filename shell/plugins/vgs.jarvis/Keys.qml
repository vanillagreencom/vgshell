import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "AccountStatus.js" as Words

// One presence reader, refreshed after the core reports an add-key TUI end.
// It publishes the key list and the keyring's outcome in the page's words; a
// failure's cause goes to the log alone.
Item {
    id: root
    property var shell: null
    property bool pending: false
    property int code: -1
    property string output: ""
    readonly property var tuiState: shell === null ? null : shell.tui.state["add-key"]
    readonly property var endedAt: tuiState === null || tuiState === undefined ? null : tuiState.endedAt
    readonly property var accountsState: shell === null ? null : shell.tui.state["accounts"]
    readonly property var accountsEndedAt: accountsState === null || accountsState === undefined ? null : accountsState.endedAt
    readonly property string program: String(Qt.resolvedUrl("backend/keys.js")).replace(/^file:\/\//, "")
    onShellChanged: refresh()
    onEndedAtChanged: if (endedAt !== null) refresh()
    onAccountsEndedAtChanged: if (accountsEndedAt !== null) refresh()

    function refresh() {
        if (shell === null) return;
        if (probe.running) { pending = true; return; }
        pending = false;
        code = -1;
        output = "";
        probe.running = true;
    }
    function publish() {
        let shown = null;
        try {
            if (code !== 0) throw new Error("probe");
            const rows = JSON.parse(output);
            shown = rows.map(row => Words.keyHint(row) === "" ? { label: row.label, value: row.value }
                : { label: row.label, value: row.value, hint: Words.keyHint(row) });
            // A row's diagnostic key goes to the log; the page shows words.
            for (const row of rows) if (typeof row.hint === "string") console.warn(row.hint);
        } catch (error) {
            console.warn("jarvis-keys: presence=failed");
        }
        if (shown !== null && shell.status.set("keys", shown) === "ok"
            && shell.status.set("keyStore", Words.keysValue({ kind: "listed", rows: shown })) === "ok") return;
        if (shown !== null) console.warn("jarvis-keys: presence=invalid");
        if (shell.status.set("keys", []) !== "ok"
            || shell.status.set("keyStore", Words.keysValue({ kind: "failed" })) !== "ok") throw new Error("jarvis-keys: status=refused");
    }
    Process {
        id: probe
        command: ["node", root.program, "presence"]
        clearEnvironment: true
        environment: ({
            PATH: Quickshell.env("PATH"), HOME: Quickshell.env("HOME"),
            XDG_CONFIG_HOME: Quickshell.env("XDG_CONFIG_HOME"), XDG_STATE_HOME: Quickshell.env("XDG_STATE_HOME"),
            XDG_DATA_HOME: Quickshell.env("XDG_DATA_HOME"), XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR"),
            DBUS_SESSION_BUS_ADDRESS: Quickshell.env("DBUS_SESSION_BUS_ADDRESS"), LANG: "C.UTF-8"
        })
        stdout: StdioCollector { onStreamFinished: root.output = text }
        // Never forward helper stderr. The keyed status owns this diagnosis.
        stderr: StdioCollector {}
        onExited: (code, status) => root.code = status === 0 ? code : -1
        onRunningChanged: {
            if (running) return;
            root.publish();
            if (root.pending) Qt.callLater(root.refresh);
        }
    }
}
