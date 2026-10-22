import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "NotificationLogic.js" as Logic

// One long-lived child that talks to the session's PipeWire: the pw-cli
// writer and the sound rule's metadata watcher. It runs while `wanted` is true
// and PipeWire is ready, launched through NotificationLogic.guardedArgv so
// it cannot outlive the shell, and is started again after an exit nobody
// asked for, as NotificationLogic.restartStep spaces the starts, since
// pw-cli, pw-metadata and pw-dump each exit when PipeWire restarts
// (measured in the nested sandbox, PipeWire 1.6.9, VGS-1424). `label`
// keys its log lines. An exit is logged at `exitLevel`, `warn` where the
// owner's work stops without the child; giving up is always a warning.
// Quickshell kills the child of a destroyed Process (vgs.capture's
// Service.qml), so the owner's destruction ends it.
Item {
    id: sup

    visible: false

    required property string label
    // The program and its arguments, without the guard.
    required property var argv
    property bool wanted: true
    property bool stdinEnabled: false
    property string exitLevel: "info"
    readonly property bool running: proc.running
    readonly property var processId: proc.running ? proc.processId : null

    signal line(string text)
    signal started()
    signal ended()

    // Exits in the current streak, when the child last started, and the
    // last line it wrote on stderr.
    property int streak: 0
    property real startedAt: 0
    property string lastError: ""
    property bool gaveUp: false
    // Set as the owner goes, so the exit the destruction causes restarts
    // and reports nothing.
    property bool ending: false
    readonly property bool canRun: wanted && Pipewire.ready && !gaveUp

    function write(data) {
        if (proc.running) proc.write(data);
    }

    function start() {
        if (!canRun || proc.running || backoff.running) return;
        proc.command = Logic.guardedArgv(Quickshell.processId, argv);
        proc.running = true;
    }

    onCanRunChanged: {
        if (canRun) start();
        else if (!wanted) proc.running = false;
    }

    Process {
        id: proc
        property var completion: null
        stdinEnabled: sup.stdinEnabled
        // Under clearEnvironment a null value passes the shell's own value
        // through (Quickshell 0.3.1, Process.clearEnvironment); these
        // programs need the program path and the session's PipeWire alone.
        clearEnvironment: true
        environment: ({ PATH: null, XDG_RUNTIME_DIR: null, PIPEWIRE_RUNTIME_DIR: null, PIPEWIRE_REMOTE: null, LANG: "C.UTF-8" })
        stdout: SplitParser {
            onRead: text => sup.line(text)
        }
        stderr: SplitParser {
            onRead: text => {
                sup.lastError = text;
                console.info("notifications: " + sup.label + ": stderr " + text);
            }
        }
        onStarted: {
            sup.startedAt = Date.now();
            sup.started();
        }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (sup.ending) return;
            sup.ended();
            if (!sup.wanted) return;
            const step = Logic.restartStep(sup.streak, Date.now() - sup.startedAt);
            sup.streak = step.streak;
            const text = "notifications: " + sup.label + ": exit=" + JSON.stringify(done) + " restart=" + (step.delay < 0 ? "gave-up" : step.delay + "ms") + " " + sup.lastError;
            if (step.delay < 0) {
                sup.gaveUp = true;
                console.warn(text);
                return;
            }
            if (sup.exitLevel === "warn") console.warn(text);
            else console.info(text);
            backoff.interval = step.delay;
            backoff.restart();
        }
    }

    Timer {
        id: backoff
        onTriggered: sup.start()
    }

    Component.onCompleted: start()
    Component.onDestruction: ending = true
}
