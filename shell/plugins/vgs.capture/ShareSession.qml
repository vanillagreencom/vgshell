import QtQuick
import Quickshell
import Quickshell.Io

// The service owns one pending portal request. A closed surface cancels it.
// The caller consumes a completed answer once and cancels on its own timeout.
Item {
    id: root
    property var shell: null
    property bool registered: false
    property var session: null
    readonly property var missing: shell === null ? [] : shell.requirements.missing
    readonly property var setupEnded: shell === null || shell.tui.state["setup-sharing"] === undefined ? null : shell.tui.state["setup-sharing"].endedAt
    // shellDir is the root configuration, independent of plugin snapshots.
    // https://quickshell.org/docs/v0.3.1/types/Quickshell/Quickshell
    readonly property string pickerPath: Quickshell.shellDir + "/../bin/vgshell-share-picker"
    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("share-begin", arg => root.begin(arg));
        shell.ipc.handle("share-result", arg => root.result(JSON.parse(arg).id));
        shell.ipc.handle("share-cancel", arg => root.cancel(JSON.parse(arg).id));
        shell.ipc.handle("share-close", arg => root.session !== null && root.session.phase === "pending" ? root.cancel(JSON.parse(arg).id, false) : "ok");
        shell.ipc.handle("share-choice", arg => root.choose(arg));
        setup.running = true;
    }
    onMissingChanged: if (registered && !setup.running) setup.running = true
    onSetupEndedChanged: if (registered && !setup.running) setup.running = true

    function begin(arg) {
        if (session !== null) return "refused: share=busy";
        const request = JSON.parse(arg);
        if (typeof request.id !== "string" || request.id === "" || !Array.isArray(request.windows) || typeof request.remember !== "boolean") return "refused: share=request";
        // A later portal start can activate a previously needed setup.
        if (!setup.running) setup.running = true;
        session = { phase: "pending", request: request };
        deadline.restart();
        const reply = shell.surfaces.summon("window", JSON.stringify(request));
        if (reply !== "ok") { deadline.stop(); session = null; return reply; }
        return "ok";
    }

    function result(id) {
        if (session === null || session.request.id !== id) return "cancelled";
        if (session.phase === "pending") return "pending";
        const answer = session.phase === "selected" ? JSON.stringify({ choice: session.choice }) : "cancelled";
        session = null;
        deadline.stop();
        return answer;
    }

    function cancel(id, hideSurface) {
        if (session === null || session.request.id !== id) return "ok";
        session = { phase: "cancelled", request: session.request };
        // A close or replacement already owns the window's visibility.
        if (hideSurface !== false) shell.surfaces.hide("window");
        session = null;
        deadline.stop();
        return "ok";
    }

    Timer { id: deadline; interval: 300000; onTriggered: if (root.session !== null) root.cancel(root.session.request.id) }

    function choose(arg) {
        const answer = JSON.parse(arg);
        if (session === null || session.phase !== "pending" || session.request.id !== answer.id) return "refused: share=request-ended";
        // The executable owns the xdph grammar and validates this typed choice.
        session = { phase: "selected", request: session.request, choice: answer.choice };
        shell.surfaces.hide("window");
        return "ok";
    }

    // Quickshell 0.3.1 clearEnvironment passes only the named values.
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process
    Process {
        id: setup
        command: [root.pickerPath, "--probe"]
        clearEnvironment: true
        environment: ({ HOME: null, XDG_CONFIG_HOME: null, XDG_RUNTIME_DIR: null, DBUS_SESSION_BUS_ADDRESS: null, PATH: null, VGS_TEST_RUN: null })
        stderr: StdioCollector { id: setupError }
        stdout: StdioCollector { id: setupResult }
        onExited: (code, status) => {
            let ready = false;
            if (code === 0 && status === 0) {
                try { ready = JSON.parse(setupResult.text).state === "ready"; }
                catch (error) { console.error("capture: share-probe invalid-result"); }
            }
            root.shell.status.set("sharing", { tone: ready ? "info" : "warning", text: ready ? "Ready" : "Setup needed. Select Set up screen sharing in Capture settings.", action: !ready });
            if (code !== 0 || status !== 0) console.error("capture: share-probe " + setupError.text.trim());
        }
    }
}
