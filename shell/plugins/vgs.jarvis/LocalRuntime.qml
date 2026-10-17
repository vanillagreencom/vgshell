import QtQuick
import Quickshell
import Quickshell.Io
import "SetupGate.js" as Gate

// One readiness reader. Every completed setup run and every requirement scan
// triggers a fresh check. While the last scan misses a command of `requires`,
// the published value withholds the setup step (SetupGate.setupValue). A
// reader's `shape` turns that value into the one it publishes. Each
// published check of a live reader emits `refreshed`; `republish` shapes
// the last check again and emits nothing.
Item {
    id: root
    property var shell: null
    property string statusKey: "localRuntime"
    property string tuiName: "setup-local"
    property var command: ["python3", "-I", program, "status"]
    // The declared requirement commands the setup TUI needs.
    property var requires: []
    property var shape: value => value
    property bool pending: false
    property bool timedOut: false
    property int code: -1
    property string output: ""
    // The value the last check gave, before `shape`, null before the first
    // check: a shape that reads more than the check publishes it again.
    property var reading: null
    readonly property string setupCause: timedOut ? "setup=probe-timeout" : ""
    readonly property var tuiState: shell === null ? null : shell.tui.state[tuiName]
    readonly property var endedAt: tuiState === null || tuiState === undefined ? null : tuiState.endedAt
    // Rises after every scan, so an installed or removed command is read again.
    readonly property var requirementsRevision: shell === null ? -1 : shell.requirements.revision
    property string program: String(Qt.resolvedUrl("setup-local")).replace(/^file:\/\//, "")
    onShellChanged: refresh()
    onEndedAtChanged: if (endedAt !== null) refresh()
    onRequirementsRevisionChanged: refresh()
    signal refreshed()

    function refresh() {
        if (shell === null) return;
        if (probe.running) { pending = true; return; }
        pending = false;
        timedOut = false;
        code = -1;
        output = "";
        probe.running = true;
        probeDeadline.restart();
    }
    // The check's value: its answer, else the failure SetupGate words from
    // the manifest entry this reader publishes.
    function checked() {
        const entry = shell.manifest.status[statusKey];
        if (timedOut) return Gate.checkFailure("timeout", entry);
        if (code !== 0) return Gate.checkFailure("failed", entry);
        try {
            return JSON.parse(output);
        } catch (error) {
            return Gate.checkFailure("unreadable", entry);
        }
    }
    // A retired reader emits no `refreshed`: its handlers would write
    // status for an instance the core already refuses.
    function publish() {
        reading = Gate.setupValue(checked(), requires, shell.requirements.missing);
        if (republish()) refreshed();
    }
    // Publishes the last check through `shape`, also for a shape whose
    // other input changed; it emits no `refreshed`. A value the status
    // judge refuses is published as an unreadable check. A probe can end
    // after a disable or a rescan retired this instance; the core is about
    // to destroy it and refuses its write (PluginStatus.set), so the write
    // ends there and the call returns false. Otherwise it returns true. The
    // fallback runs in the same call, so it is never retired.
    function republish() {
        if (reading === null) return true;
        const written = shell.status.set(statusKey, shape(reading));
        if (written.endsWith(" reason=retired")) return false;
        if (written === "ok") return true;
        reading = Gate.setupValue(Gate.checkFailure("unreadable", shell.manifest.status[statusKey]), requires, shell.requirements.missing);
        const reply = shell.status.set(statusKey, shape(reading));
        if (reply !== "ok") throw new Error("jarvis-setup: " + reply);
        return true;
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
            probeDeadline.stop();
            root.publish();
            if (root.pending) Qt.callLater(root.refresh);
        }
    }
    Timer {
        id: probeDeadline
        // setup-local status was measured on this machine on 2026-10-10:
        // python3 -I shell/plugins/vgs.jarvis/setup-local status, five
        // runs, median 58.8 ms and max 72.1 ms. The 10000 ms bound leaves
        // room for a slow disk without letting Setup wait forever.
        interval: 10000
        repeat: false
        onTriggered: {
            root.timedOut = true;
            // The keyed cause stays in the log: the row draws its words.
            console.warn("jarvis: " + root.setupCause + " check=" + root.statusKey);
            // Quickshell.Io Process owns this probe child. Setting running
            // false ends the child before the Setup page can wait forever.
            probe.running = false;
            root.publish();
        }
    }
}
