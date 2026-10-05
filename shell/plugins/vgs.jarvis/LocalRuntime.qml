import QtQuick
import Quickshell
import Quickshell.Io
import "SetupGate.js" as Gate

// One readiness reader. Every completed setup run and every requirement scan
// triggers a fresh check. While the last scan misses a command of `requires`,
// the published value withholds the setup step (SetupGate.setupValue).
Item {
    id: root
    property var shell: null
    property string statusKey: "localRuntime"
    property string tuiName: "setup-local"
    property var command: ["python3", "-I", program, "status"]
    // The declared requirement commands the setup TUI needs.
    property var requires: []
    property bool pending: false
    property int code: -1
    property string output: ""
    readonly property var tuiState: shell === null ? null : shell.tui.state[tuiName]
    readonly property var endedAt: tuiState === null || tuiState === undefined ? null : tuiState.endedAt
    // Rises after every scan, so an installed or removed command is read again.
    readonly property var requirementsRevision: shell === null ? -1 : shell.requirements.revision
    property string program: String(Qt.resolvedUrl("setup-local")).replace(/^file:\/\//, "")
    onShellChanged: refresh()
    onEndedAtChanged: if (endedAt !== null) refresh()
    onRequirementsRevisionChanged: refresh()

    function refresh() {
        if (shell === null) return;
        if (probe.running) { pending = true; return; }
        pending = false;
        code = -1;
        output = "";
        probe.running = true;
    }
    function publish() {
        let value = { tone: "warning", text: "Setup check failed", action: true };
        try {
            if (code === 0) value = JSON.parse(output);
        } catch (error) {
            value = { tone: "warning", text: "Setup check returned invalid status", action: true };
        }
        const missing = shell.requirements.missing;
        const reply = shell.status.set(statusKey, Gate.setupValue(value, requires, missing));
        if (reply !== "ok") {
            const fallback = shell.status.set(statusKey, Gate.setupValue(
                { tone: "warning", text: "Setup check returned invalid status", action: true }, requires, missing));
            if (fallback !== "ok") throw new Error("jarvis-setup: status=refused");
        }
    }
    Process {
        id: probe
        command: root.command
        clearEnvironment: true
        environment: ({
            PATH: Quickshell.env("PATH"), HOME: Quickshell.env("HOME"),
            XDG_STATE_HOME: Quickshell.env("XDG_STATE_HOME"),
            XDG_DATA_HOME: Quickshell.env("XDG_DATA_HOME"),
            XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR"), LC_ALL: "C.UTF-8"
        })
        stdout: StdioCollector { onStreamFinished: root.output = text }
        stderr: StdioCollector {}
        onExited: (code, status) => root.code = status === 0 ? code : -1
        onRunningChanged: {
            if (running) return;
            root.publish();
            if (root.pending) Qt.callLater(root.refresh);
        }
    }
}
