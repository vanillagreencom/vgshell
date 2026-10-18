import QtQuick
import Quickshell
import Quickshell.Io
import "SetupGate.js" as Gate

// The Local voice setting's one reader and writer. `setup-local choices`
// runs when the shell is first set, after every requirement scan and after
// every local setup run ends; its offers become the `localTiers` choices.
// A change of `localTier` starts the wanted tier's download in the floating
// TUI (SetupGate.tierRun); after a run ends, the setting follows the tier
// it left ready (SetupGate.tierAfterRun), and so it does when the TUI
// refuses the run. A start and the service's own write start no run.
Item {
    id: root
    property var shell: null
    // { pick, ready, choices } from the last read, null before one and
    // after a failed one: no run starts and no setting is written then.
    property var reading: null
    // The setting value last acted on, null before the shell is set.
    property var decided: null
    property bool pending: false
    // A run ended and the read that follows it has not answered yet.
    property bool afterRun: false
    // The setting when the last run ended: a pick made since is kept.
    property var endedWanted: null
    property int code: -1
    property string output: ""
    readonly property string wanted: shell === null ? "" : shell.settings.localTier
    readonly property var tuiState: shell === null ? null : shell.tui.state["setup-local"]
    readonly property var endedAt: tuiState === null || tuiState === undefined ? null : tuiState.endedAt
    readonly property var requirementsRevision: shell === null ? -1 : shell.requirements.revision
    property string program: String(Qt.resolvedUrl("setup-local")).replace(/^file:\/\//, "")
    property var command: ["python3", "-I", program, "choices"]
    onShellChanged: {
        if (shell === null || decided !== null) return;
        // Qt runs this handler before the `wanted` binding re-evaluates
        // (a run on Qt 6.11.2 read "" there), so the facade gives the value.
        decided = shell.settings.localTier;
        refresh();
    }
    onWantedChanged: decide()
    onEndedAtChanged: {
        if (endedAt === null) return;
        afterRun = true;
        endedWanted = wanted;
        refresh();
    }
    onRequirementsRevisionChanged: refresh()

    function refresh() {
        if (shell === null) return;
        if (reader.running) { pending = true; return; }
        pending = false;
        code = -1;
        output = "";
        reader.running = true;
    }

    // Start the run a change of the setting asks for, judged on a read that
    // answered after the last run's end.
    function decide() {
        if (shell === null || decided === null || reading === null || afterRun || wanted === decided) return;
        decided = wanted;
        const args = Gate.tierRun(wanted, reading.pick, reading.ready);
        if (args === null) return;
        const answer = shell.tui.run("setup-local", args);
        if (answer === "ok") return;
        console.warn("jarvis-tier: run=" + answer);
        // configure.set replaces `shell` before it returns; from this change
        // handler of `wanted` Qt would keep the old value (Accounts.qml save).
        Qt.callLater(follow);
    }

    // Write the setting to the tier setup left ready, "auto" for the pick,
    // so the page shows what is installed; nothing while it already does.
    // Answers whether it wrote.
    function follow() {
        if (shell === null || reading === null) return false;
        const next = Gate.tierAfterRun(wanted, reading.pick, reading.ready);
        if (next === null) return false;
        // The written tier is ready, so the setting it delivers starts no run.
        if (shell.configure.set("localTier", next) !== "ok") console.warn("jarvis-tier: setting=refused");
        return true;
    }

    function answered() {
        let value = null;
        try { if (code === 0) value = JSON.parse(output); } catch (error) {}
        const shaped = value !== null && typeof value === "object" && typeof value.pick === "string"
            && (value.ready === null || typeof value.ready === "string") && Array.isArray(value.choices);
        if (!shaped) console.warn("jarvis-tier: choices=" + (code === 0 ? "invalid" : "exit code=" + code));
        reading = shaped ? value : null;
        const reply = shell.status.set("localTiers", shaped ? value.choices : []);
        if (!shell.status.isOk(reply)) throw new Error("jarvis-tier: status=refused");
        if (reply !== "ok") return false;
        // A read that started before the run ended answers for the state
        // before it; the read after it judges the end.
        if (pending) return true;
        const ended = afterRun;
        afterRun = false;
        // A pick made since the run ended is judged as a change instead.
        if (ended && wanted === endedWanted && follow()) return true;
        decide();
        return true;
    }

    Process {
        id: reader
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
            if (root.answered() && root.pending) Qt.callLater(root.refresh);
        }
    }
}
