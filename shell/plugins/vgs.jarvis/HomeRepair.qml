import QtQuick
import Quickshell
import Quickshell.Io

// Reads the failed Home's writer without changing it. The plain folder
// reader remains independent: a failed install plan must not hide its files.
Item {
    id: root
    property var shell: null
    property bool wanted: false
    property var result: ({ kind: "unavailable" })
    property bool pending: false
    readonly property string selected: shell === null ? "" : shell.settings.home
    readonly property var tuiState: shell === null ? null : shell.tui.state["repair-home"]
    readonly property var endedAt: tuiState === null ? null : tuiState.endedAt
    readonly property string program: String(Qt.resolvedUrl("backend/fleet-setup.js")).replace(/^file:\/\//, "")
    onSelectedChanged: {
        result = { kind: "unavailable" };
        if (wanted) refresh();
    }
    onWantedChanged: if (wanted) refresh()
    onEndedAtChanged: if (endedAt !== null) { refresh(); recheck(); }
    signal recheck()

    function refresh() {
        if (shell === null || selected === "") return;
        result = { kind: "reading" };
        if (probe.running) { pending = true; return; }
        pending = false;
        probe.selected = selected;
        probe.code = -1;
        probe.output = "";
        probe.timedOut = false;
        probe.running = true;
        deadline.restart();
    }

    function finished() {
        deadline.stop();
        if (pending || probe.selected !== selected) { refresh(); return; }
        result = { kind: "failed" };
        if (probe.code !== 0 || probe.timedOut) return;
        try {
            const repair = JSON.parse(probe.output);
            if ((repair.kind !== "home" && repair.kind !== "install") || typeof repair.folder !== "string"
                || (repair.lastRepair !== null && (!repair.lastRepair || ["running", "failed", "complete"].indexOf(repair.lastRepair.kind) === -1)))
                throw new Error("shape");
            if (repair.lastRepair !== null && repair.lastRepair.kind === "running" && tuiState !== null && !tuiState.running && tuiState.endedAt !== null)
                repair.lastRepair = { kind: "failed", cause: "interrupted" };
            result = { kind: "ready", repair: repair };
        } catch (error) { console.warn("jarvis: home-repair=status-unreadable"); }
    }

    Process {
        id: probe
        property string selected: ""
        property string output: ""
        property int code: -1
        property bool timedOut: false
        command: ["node", root.program, "--tree", Quickshell.shellDir + "/..", "repair-status", selected]
        clearEnvironment: true
        environment: ({ PATH: Quickshell.env("PATH"), HOME: Quickshell.env("HOME"),
            XDG_STATE_HOME: Quickshell.env("XDG_STATE_HOME"), LANG: "C.UTF-8" })
        // Quickshell 0.3.1 Process and StdioCollector: argv is not a shell
        // command; streamFinished supplies the collected output. The same
        // exit-before-runningChanged order is exercised by the Home smoke.
        // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process/
        stdout: StdioCollector { onStreamFinished: probe.output = text }
        stderr: StdioCollector {}
        onExited: (code, status) => probe.code = status === 0 ? code : -1
        onRunningChanged: if (!running) root.finished()
    }
    Timer {
        id: deadline
        // Reuse the existing Home path reader's bound for this read-only
        // helper. Process.running=false sends SIGTERM in Quickshell 0.3.1.
        interval: 10000
        repeat: false
        onTriggered: { probe.timedOut = true; probe.running = false; }
    }
}
