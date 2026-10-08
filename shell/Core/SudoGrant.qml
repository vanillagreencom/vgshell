import QtQuick
import Quickshell
import Quickshell.Io
import "PluginLogic.js" as Logic

// Owns the `sudo` capability (D103): the passwordless sudo grant's state
// and the one `bin/vgshell-sudo-grant status` that reads it, which lists
// the user's own sudo rules and never asks or elevates. Every grant and
// revoke runs in a core floating TUI, so the shell never elevates. It
// reads while a plugin holds the capability: once when the first holder
// arrives, again after every run of `core/sudo-grant` or
// `core/sudo-revoke` ends, whoever opened it, and at an active timed
// grant's deadline through one Timer; a request while a read runs starts
// one more after it, never two at a time, and nothing polls.
// PluginLogic.sudoReport judges each read, and `revision` rises when one
// changes the state.
Scope {
    id: root

    // Whether any plugin holds `sudo`; Capabilities binds it.
    property bool active: false
    // The runner that opens the grant's TUIs and holds their records.
    required property TuiRunner runner
    // { state, until, rootHalf } as PluginLogic.sudoReport reads them,
    // frozen and replaced whole when a read changes one.
    property var current: Object.freeze({ state: "unknown", until: "", rootHalf: "" })
    property int revision: 0
    property int reads: 0
    property bool again: false
    // The count of ended runs this owner has seen, the count when the
    // running read started, and the count when the last finished read
    // started: a read that started after a run ended reads its result.
    property int ends: 0
    property int readEnds: 0
    property int doneEnds: -1
    // Each `done` waiting for the read that follows its run's end:
    // { done, need, result, release }.
    property var waiters: []

    // The core's bin/ beside the shell directory: the shell's PATH need not
    // hold the core's commands.
    readonly property string coreBin: Quickshell.shellDir + "/../bin"
    // The latest ended run of each of the grant's TUIs. It changes when a
    // run ends, a run the launcher opened included, and when the shell
    // first lists the records a run before it left.
    readonly property string endedRuns: runner.coreEnded("sudo-grant") + " " + runner.coreEnded("sudo-revoke")

    onActiveChanged: {
        if (active) read();
        else deadline.stop();
    }
    onEndedRunsChanged: {
        ends += 1;
        if (active) read();
    }

    // `state`: { state, until, rootHalf }, one frozen copy for every
    // reader; `revision`: the count of changed reads; both bindable.
    // `grant` and `revoke` open the core TUIs and return the shown answer;
    // `done`, when given, is called once with { code, reason, state,
    // until } after the run ended and the read after it finished, and is
    // dropped with CTX's instance.
    function provider(ctx) {
        return {
            get state() { return root.current; },
            get revision() { return root.revision; },
            grant: (duration, done) => root.grant(ctx, duration, done),
            revoke: done => root.open(ctx, "sudo-revoke", [], done)
        };
    }

    function grant(ctx, duration, done) {
        if (!Logic.sudoDurationValid(duration))
            return "refused: sudo=duration value=" + JSON.stringify(duration);
        return open(ctx, "sudo-grant", [duration], done);
    }

    // Opens core TUI NAME with ARGS; a refused launch, a busy key's
    // focused window included, calls no `done`.
    function open(ctx, name, args, done) {
        if (done !== undefined && typeof done !== "function")
            throw new Error("refused: sudo done=not-a-function");
        let waiter = null;
        if (done !== undefined) {
            waiter = { done: done, need: 0, result: null, release: null };
            waiter.release = ctx.onDispose(() => {
                waiter.done = null;
                root.waiters = root.waiters.filter(w => w !== waiter);
            });
        }
        const answer = runner.openCore(name, args, waiter === null ? undefined : result => root.runEnded(waiter, result));
        if (answer !== "ok" && waiter !== null) waiter.release();
        return Logic.tuiShownAnswer("core/" + name, answer);
    }

    // TuiRecords hands a run's end after the records that show it, so
    // `ends` already counts it; a launch that failed counts none, and the
    // last read stands.
    function runEnded(waiter, result) {
        if (waiter.done === null) return;
        waiter.need = ends;
        waiter.result = result;
        waiters = waiters.concat([waiter]);
        settle();
        if (waiters.indexOf(waiter) !== -1 && !reader.running) read();
    }

    function settle() {
        const due = waiters.filter(w => doneEnds >= w.need);
        if (due.length === 0) return;
        waiters = waiters.filter(w => doneEnds < w.need);
        const shared = Object.freeze({ state: current.state, until: current.until });
        for (const waiter of due) {
            const done = waiter.done;
            waiter.release();
            try {
                done(Object.freeze({ code: waiter.result.code, reason: waiter.result.reason, state: shared.state, until: shared.until }));
            } catch (e) {
                console.error("capabilities: sudo done threw: " + e.message);
            }
        }
    }

    function read() {
        if (reader.running) {
            again = true;
            return;
        }
        reader.completion = null;
        readEnds = ends;
        reader.running = true;
    }

    // One timer for an active timed grant's deadline, restarted on each
    // new one; none while no grant, or an indefinite one, is active. The
    // status read counts the grant as ended from its deadline's second on.
    // A QML Timer is synchronized with the animation timer
    // (https://doc.qt.io/qt-6/qml-qtqml-timer.html), which counts on Qt's
    // monotonic clock, and that clock leaves out the time the system
    // sleeps (https://doc.qt.io/qt-6/qelapsedtimer.html, MonotonicClock).
    // After a suspend past the deadline this read comes late, and the
    // holder shows the grant on until it does; sudo itself refuses the
    // rule from its NOTAFTER deadline on.
    function arm() {
        const at = active && current.state === "active" && current.until !== "indefinite" ? Date.parse(current.until) : NaN;
        if (isNaN(at)) {
            deadline.stop();
            return;
        }
        deadline.interval = Math.max(at - Date.now(), 0);
        deadline.restart();
    }

    // The read state, the deadline and the waiting callbacks, for the
    // lending record.
    function record() {
        return { reading: reader.running, reads: reads, revision: revision, state: current, deadline: deadline.running, waiters: waiters.length };
    }

    Timer {
        id: deadline
        repeat: false
        onTriggered: root.read()
    }

    // A command that fails to start emits only runningChanged, so the end
    // is read there: no exit recorded is a failed start.
    Process {
        id: reader
        property var completion: null
        command: [root.coreBin + "/vgshell-sudo-grant", "status"]
        stdout: StdioCollector { id: readOutput }
        stderr: StdioCollector { id: readErrors }
        onExited: (code, status) => { reader.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const report = Logic.sudoReport(reader.completion, readOutput.text, readErrors.text);
            if (report.line !== "") console.error(report.line);
            root.reads += 1;
            root.doneEnds = root.readEnds;
            if (report.state !== root.current.state || report.until !== root.current.until || report.rootHalf !== root.current.rootHalf) {
                root.current = Object.freeze({ state: report.state, until: report.until, rootHalf: report.rootHalf });
                root.revision += 1;
            }
            root.arm();
            root.settle();
            if (root.again) {
                root.again = false;
                root.read();
            }
        }
    }
}
