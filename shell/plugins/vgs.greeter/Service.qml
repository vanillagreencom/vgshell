import QtQuick
import Quickshell.Io
import qs.Commons
import "GreeterLogic.js" as Logic

// The login screen's service. It publishes the `greeter` system step's
// state, with Set up offered while the step reads needed or nixos; the core
// runs the step in its floating TUI (D081, D101). While the step reads
// ready, it keeps the login screen's copy of the applied theme current:
// bin/copy-theme copies theme.json and the background image into the
// directory the step made, once when the step turns ready and again after
// each change to theme.json or to backgrounds.json, which the theme runner
// replaces on every background change. One copy runs at a time; a change
// during one runs one more when it ends.
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    // The values last written, by key.
    property var reported: ({})
    // The last copy's result: null before one, else { ok }.
    property var copied: null
    property bool copyAgain: false
    // Whether the running copy has yet to report its exit; a command that
    // fails to start reports none.
    property bool awaitingExit: false

    readonly property var steps: shell === null ? null : shell.system.state
    readonly property var step: steps === null ? null : steps.greeter
    readonly property bool ready: step !== null && step !== undefined && step.state === "ready"
    readonly property var values: ({ greeter: Logic.stepState(step), theme: Logic.themeState(ready, copied) })
    readonly property string helperPath: String(Qt.resolvedUrl("bin/copy-theme")).replace(/^file:\/\//, "")

    onShellChanged: publish()
    onValuesChanged: publish()
    onReadyChanged: {
        copied = null;
        copy();
    }

    function publish() {
        if (shell === null) return;
        const next = Object.assign({}, reported);
        for (const key of Object.keys(values)) {
            if (JSON.stringify(reported[key]) === JSON.stringify(values[key])) continue;
            const reply = shell.status.set(key, values[key]);
            // A disabled plugin's instance lives on for a moment; its
            // writes are refused and it is on its way out.
            if (reply.endsWith(" reason=retired")) return;
            if (reply !== "ok") console.error("greeter: " + reply);
            else next[key] = values[key];
        }
        reported = next;
    }

    function copy() {
        const args = Logic.copyArguments(ready, Paths.configDir, Paths.stateDir);
        if (args === null) return;
        if (copier.running) {
            copyAgain = true;
            return;
        }
        copier.command = ["bash", helperPath].concat(args);
        awaitingExit = true;
        copier.running = true;
    }

    FileView {
        path: Paths.configDir + "/theme.json"
        preload: false
        watchChanges: true
        printErrors: false
        onFileChanged: root.copy()
    }

    FileView {
        path: Paths.stateDir + "/backgrounds.json"
        preload: false
        watchChanges: true
        printErrors: false
        onFileChanged: root.copy()
    }

    Process {
        id: copier
        stdout: StdioCollector { id: copyOut; waitForEnd: true }
        stderr: StdioCollector { id: copyErr; waitForEnd: true }
        onExited: code => {
            root.awaitingExit = false;
            const line = code === 0 ? Logic.copyLine(copyOut.text) : null;
            if (line === null) console.error("greeter: copy-theme exit=" + code + " " + (copyErr.text.trim() || copyOut.text.trim()));
            else if (line.theme !== "unchanged" || line.background !== "unchanged") console.info("greeter: " + copyOut.text.trim());
            root.copied = { ok: line !== null };
        }
        onRunningChanged: {
            if (running) return;
            if (root.awaitingExit) {
                root.awaitingExit = false;
                console.error("greeter: copy-theme did not start");
                root.copied = { ok: false };
            }
            if (!root.copyAgain) return;
            root.copyAgain = false;
            root.copy();
        }
    }
}
