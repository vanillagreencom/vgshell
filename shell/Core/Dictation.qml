import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "DictationModel.js" as Model

// Owns the `dictation` capability (D106): voxtype's one recording, lent to
// one holder at a time, and the `voxtype daemon` child that runs while a
// plugin holds the capability. DictationModel.js makes every decision; this
// scope runs its effects on the daemon child, the status follower, one
// serial command runner, the one timer and the start check, and hands it
// their output and ends as events. The shipped helper bounds their raw
// streams outside the shell and resolves voxtype on the shell's PATH.
Scope {
    id: root

    // The plugin ids that hold the capability, as Capabilities accounts for
    // them: each id that enters is a lease and each that leaves a release.
    property var holders: []
    // Pipewire.ready follows the initial server sync; either default can
    // still be null (Quickshell 0.3.1, Pipewire singleton).
    readonly property bool outputReady: Pipewire.ready && Pipewire.defaultAudioSink !== null
    readonly property bool inputReady: Pipewire.ready && Pipewire.defaultAudioSource !== null
    onOutputReadyChanged: if (model !== undefined) apply(Model.audio(model, outputReady, inputReady))
    onInputReadyChanged: if (model !== undefined) apply(Model.audio(model, outputReady, inputReady))
    // Replaced whole on every event, so the provider's `state` is bindable.
    property var model: Model.initial(Quickshell.env("XDG_RUNTIME_DIR") + "/vgshell/dictation", Quickshell.env("XDG_RUNTIME_DIR") + "/voxtype/state", outputReady, inputReady)
    // The commands the model asked for that have not started, oldest first.
    property var queue: []
    // The callback of the stop that waits, or null.
    property var waiting: null
    readonly property string transport: Quickshell.shellDir + "/../bin/vgshell-dictation"

    // What voxtype needs of the session: its config and runtime
    // directories, the display and session bus its output and its
    // notifications go to, and the audio server. VGSHELL_RUNNER_PID, which
    // marks the shell's own processes, is not among them.
    // Under clearEnvironment a null value passes the shell's own value
    // through (Quickshell 0.3.1, Process.clearEnvironment).
    readonly property var environment: ({
        PATH: null, HOME: null, USER: null, LANG: null, NO_COLOR: "1",
        XDG_RUNTIME_DIR: null, XDG_CONFIG_HOME: null, XDG_DATA_HOME: null, XDG_CACHE_HOME: null, XDG_STATE_HOME: null,
        XDG_CURRENT_DESKTOP: null, XDG_SESSION_TYPE: null, WAYLAND_DISPLAY: null, DISPLAY: null,
        HYPRLAND_INSTANCE_SIGNATURE: null, DBUS_SESSION_BUS_ADDRESS: null, YDOTOOL_SOCKET: null,
        PIPEWIRE_RUNTIME_DIR: null, PIPEWIRE_REMOTE: null, PULSE_SERVER: null
    })

    // ARGV as a child that cannot outlive the shell. setpriv sets SIGKILL
    // as the parent-death signal and execs bash in the same process; bash
    // reads PPID when it starts, so a shell that died before the signal
    // was set is seen and nothing runs; bash then execs ARGV in the same
    // process, so the Process's pid is the program's and a signal reaches
    // it. /usr/bin/voxtype is a script that execs the engine's binary, and
    // the signal setting survives an exec (prctl(2), PR_SET_PDEATHSIG).
    function guarded(argv) {
        return ["setpriv", "--pdeathsig", "KILL", "--", "bash", "-c", '[[ $PPID == "$1" ]] || exit 1; shift; exec "$@"', "bash", String(Quickshell.processId)].concat(argv);
    }

    onHoldersChanged: {
        for (const id of holders)
            if (model.holders.indexOf(id) === -1) apply(Model.lease(model, id));
        for (const id of model.holders)
            if (holders.indexOf(id) === -1) apply(Model.release(model, id));
    }

    function apply(step) {
        model = step.model;
        for (const effect of step.effects) run(effect);
        return step;
    }

    function run(effect) {
        switch (effect.kind) {
        case "run":
            queue = queue.concat([{ tag: effect.tag, argv: effect.argv }]);
            pump();
            return;
        // signal sends only while the process runs (Quickshell 0.3.1,
        // Process.signal), and `running` turns false at the exit, where
        // the handlers below read each end.
        case "abort":
            queue = [];
            if (runner.running) {
                runner.aborted = true;
                runner.signal(15);
            }
            return;
        case "daemon":
            daemon.completion = null;
            daemon.running = true;
            return;
        case "term":
            daemon.signal(15);
            return;
        case "kill":
            daemon.signal(9);
            return;
        case "follow":
            follower.wanted = true;
            if (!follower.running) follower.running = true;
            return;
        case "unfollow":
            follower.wanted = false;
            if (follower.running) {
                follower.stopping = true;
                follower.signal(15);
            }
            return;
        case "timer":
            if (effect.ms === 0) {
                wait.stop();
            } else {
                wait.interval = effect.ms;
                wait.restart();
            }
            return;
        case "check":
            check.restart();
            return;
        // The callback runs after the event that ended the recording, so
        // a start it makes meets the model that event left.
        case "done": {
            const done = waiting;
            // Qt.callLater runs after returning to the event loop
            // (doc.qt.io/qt-6/qml-qtqml-qt.html#callLater-method). A
            // cancellation or recovery can retire this result first.
            const delivery = model.delivery;
            waiting = null;
            if (done !== null) Qt.callLater(() => { if (root.model.delivery === delivery) done(effect.result); });
            return;
        }
        case "forget":
            waiting = null;
            return;
        case "log":
            console.warn(effect.line);
            return;
        }
        throw new Error("dictation: effect kind " + JSON.stringify(effect.kind) + " is unknown");
    }

    // Starts the oldest queued command once none runs: voxtype's record
    // verbs write shared files under its runtime directory before they
    // signal the daemon, so they run one at a time, in order.
    function pump() {
        if (runner.running || queue.length === 0) return;
        const next = queue[0];
        queue = queue.slice(1);
        runner.tag = next.tag;
        runner.aborted = false;
        runner.completion = null;
        runner.command = guarded([transport, "run", "--"].concat(next.argv));
        runner.running = true;
    }

    // start: `ok` or the refusal; MODE `type` sends the text to voxtype's
    // configured output and `text` to DONE of the stop. stop: `ok` or the
    // refusal; DONE, if given, receives { kind: "text", text },
    // { kind: "empty" }, { kind: "typed" } or { kind: "failed", reason }
    // while the calling instance lives. `state` is bindable.
    function provider(ctx) {
        const refused = "refused: dictation=released";
        return {
            start: mode => ctx.active ? root.apply(Model.start(root.model, ctx.id, mode)).answer : refused,
            stop: done => ctx.active ? root.stop(ctx, done) : refused,
            cancel: () => ctx.active ? root.apply(Model.cancel(root.model, ctx.id)).answer : refused,
            restart: () => ctx.active ? root.restart() : refused,
            get state() { return Object.freeze(Model.state(root.model)); }
        };
    }

    function restart() {
        return apply(Model.restart(model)).answer;
    }

    function stop(ctx, done) {
        if (done !== undefined && typeof done !== "function")
            throw new Error("refused: dictation done=not-a-function");
        const answer = apply(Model.stop(model, ctx.id)).answer;
        if (answer === "ok") waiting = typeof done === "function" ? result => { if (ctx.active) done(result); } : null;
        return answer;
    }

    function record() {
        return Model.record(model);
    }

    Timer {
        id: wait
        onTriggered: root.apply(Model.deadline(root.model))
    }

    Timer {
        id: check
        interval: Model.CHECK_MS
        onTriggered: root.apply(Model.checked(root.model))
    }

    // A child that fails to start emits only runningChanged, so each end
    // is read there: no exit recorded is a failed start, and an exit on a
    // signal is no exit code.
    Process {
        id: daemon
        property var completion: null
        // The helper bounds raw bytes before QProcess. A null parser
        // alone still drains the pipe in Qt (Qt 6.12 qprocess.cpp).
        command: root.guarded([root.transport, "daemon"])
        clearEnvironment: true
        environment: root.environment
        stderr: StdioCollector { id: daemonErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const code = completion === null || completion.status !== 0 ? null : completion.code;
            completion = null;
            root.apply(Model.exited(root.model, code, daemonErr.text.trim()));
        }
    }

    // The one reader of the daemon's state, while the child runs. One that
    // was told to end and is wanted again starts from its exit.
    Process {
        id: follower
        property bool wanted: false
        property bool stopping: false
        property var completion: null
        command: root.guarded([root.transport, "follow"])
        clearEnvironment: true
        environment: root.environment
        stdout: SplitParser { onRead: line => root.apply(Model.status(root.model, line)) }
        stderr: StdioCollector { id: followerErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) { completion = null; return; }
            const code = completion === null || completion.status !== 0 ? null : completion.code;
            completion = null;
            const asked = stopping;
            stopping = false;
            if (!asked) {
                wanted = false;
                root.apply(Model.unfollowed(root.model, code, followerErr.text.trim()));
            } else if (wanted) {
                running = true;
            }
        }
    }

    Process {
        id: runner
        property string tag: ""
        property bool aborted: false
        property var completion: null
        clearEnvironment: true
        environment: root.environment
        stdout: StdioCollector { id: runnerOut }
        stderr: StdioCollector { id: runnerErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const code = completion === null || completion.status !== 0 ? null : completion.code;
            completion = null;
            if (!aborted) {
                const complaint = runnerErr.text.trim();
                if (code !== 0 && code !== 74 && complaint !== "") console.warn("dictation: " + tag + " code=" + (code === null ? "none" : code) + " stderr=" + JSON.stringify(complaint.slice(0, 200)));
                root.apply(Model.ran(root.model, tag, code, runnerOut.text));
            }
            root.pump();
        }
    }
}
