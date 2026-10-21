import QtQuick
import Quickshell
import Quickshell.Io
import "SetupGate.js" as Gate

// The Local voice setting's one reader and writer. `setup-local choices`
// runs when the shell is first set, after every requirement scan and after
// every local setup run ends; its offers become the `localTiers` choices.
// A choice of `localTier` the user makes on the Jarvis page (chosen) starts
// the chosen tier's download in the floating TUI (SetupGate.tierRun); after
// a run ends, the setting follows the tier it left ready unless the run
// failed (SetupGate.tierAfterRun), and so it does when the TUI refuses the
// run. A choice of a Voice provider on that page that hears on this
// computer, in place of one that does not, while no tier is ready starts
// the setting's download the same way, which asks first. No change of the
// setting opens a run: not a start, a reload, an edit of the configuration
// file nor the service's own write.
Item {
    id: root
    property var shell: null
    // { pick, ready, choices } from the last read, null before one and
    // after a failed one: no run starts and no setting is written then.
    property var reading: null
    // Whether the first read has been asked for: configure.set replaces
    // `shell` at every write, which must not read again.
    property bool started: false
    // A Local voice model chosen on the page whose run waits for a read
    // that answers after the last run's end, else null.
    property var chosenTier: null
    property bool pending: false
    // A run ended and the read that follows it has not answered yet.
    property bool afterRun: false
    // The setting when the last run ended: a pick made since is kept.
    property var endedWanted: null
    property int code: -1
    property string output: ""
    readonly property string wanted: shell === null ? "" : shell.settings.localTier
    // The download size of the model setup-local picks for this computer,
    // as its choices answer words it, "" before a read.
    readonly property string pickSize: reading === null || typeof reading.pickSize !== "string" ? "" : reading.pickSize
    // The tier the setting asks for and the tier ready, from the last read:
    // "" and null before one. The Voice step words a failed setup only for
    // the wanted tier while it is not ready (SetupGate.localFailure).
    readonly property string wantedTier: reading === null ? "" : Gate.wantedTier(wanted, reading.pick)
    readonly property var readyTier: reading === null ? null : reading.ready
    readonly property var tuiState: shell === null ? null : shell.tui.state["setup-local"]
    readonly property var endedAt: tuiState === null || tuiState === undefined ? null : tuiState.endedAt
    readonly property var requirementsRevision: shell === null ? -1 : shell.requirements.revision
    property string program: String(Qt.resolvedUrl("setup-local")).replace(/^file:\/\//, "")
    property var command: ["python3", "-I", program, "choices"]
    onShellChanged: {
        if (shell === null || started) return;
        started = true;
        refresh();
    }
    // The user chose VALUE as the Local voice model on the Jarvis page: with
    // setUp, the only ways a download opens.
    function chosen(value) {
        if (shell === null) return;
        chosenTier = value;
        decide();
    }
    // The download of the tier the setting names, which the Voice provider
    // the user chose on the page asks for (SetupGate.providerWindow).
    function setUp() {
        if (shell === null) return;
        const answer = shell.tui.run("setup-local", []);
        if (answer !== "ok") console.warn("jarvis-tier: run=" + answer);
    }
    // The exit code of the last run, which a failed run keeps the chosen
    // model by (SetupGate.tierAfterRun); null for a run the TUI refused.
    readonly property var endedCode: tuiState === null || tuiState === undefined ? null : tuiState.code
    property var runCode: null
    onEndedAtChanged: {
        if (endedAt === null) return;
        runCode = endedCode;
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

    // Start the run the page's choice asks for, judged on a read that
    // answered after the last run's end.
    function decide() {
        if (shell === null || reading === null || afterRun || chosenTier === null) return;
        const args = Gate.tierRun(chosenTier, reading.pick, reading.ready);
        chosenTier = null;
        if (args === null) return;
        const answer = shell.tui.run("setup-local", args);
        if (answer === "ok") return;
        console.warn("jarvis-tier: run=" + answer);
        runCode = null;
        // configure.set replaces `shell` before it returns; from the choice's
        // handler Qt would keep the old value (Accounts.qml save).
        Qt.callLater(follow);
    }

    // Write the setting to the tier setup left ready, "auto" for the pick,
    // so the page shows what is installed; nothing while it already does.
    // Answers whether it wrote.
    function follow() {
        if (shell === null || reading === null) return false;
        const next = Gate.tierAfterRun(wanted, reading.pick, reading.ready, runCode);
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
        // A choice made since the run ended is judged instead, and a setting
        // changed since is kept.
        if (ended && chosenTier === null && wanted === endedWanted && follow()) return true;
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
