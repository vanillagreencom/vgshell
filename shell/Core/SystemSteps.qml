import QtQuick
import Quickshell
import Quickshell.Io
import "PluginLogic.js" as Logic

// Owns the `system` capability (D081): the states of the core's system
// steps and the one `bin/vgshell-system status --json` that reads them. It
// probes while a plugin holds the capability, once when the first holder
// arrives, again after every `core/system` run the manager opened ends and
// after every plugin scan, which ends each requirement install;
// a request while a probe runs starts one more after it, never two at a
// time. PluginLogic.systemReport judges each report, and a run that gives
// none reads every step unknown. Until the first run ends no step has a
// reading, so a plugin's `state` holds none of its steps. `revision` rises
// when a report changes a step's state or reason, so a plugin binds to it.
Scope {
    id: root

    // Whether any plugin holds `system`; Capabilities binds it.
    property bool active: false
    // Every step of PluginLogic.SYSTEM_STEPS as { state, reason }, replaced
    // whole when a report changes it; null until the first run ends.
    property var steps: null
    property int revision: 0
    property int probes: 0
    property bool again: false
    property var pending: []

    // The core's bin/ beside the shell directory: the shell's PATH need not
    // hold the core's commands.
    readonly property string coreBin: Quickshell.shellDir + "/../bin"

    onActiveChanged: if (active) probe()

    // A requirement install ends with a scan, and a unit or command it
    // installed changes a step from absent.
    Connections {
        target: Registry
        function onScanFinished() { if (root.active) root.probe(); }
    }

    // `state`: the calling plugin's declared steps, each { state, reason },
    // one frozen copy per read, and none before the first report;
    // `revision`: the count of changed reports. Both are bindable.
    function provider(ctx) {
        return {
            get state() {
                const out = root.steps === null ? {} : Logic.systemStateOf(root.steps, ctx.manifest.systemSteps);
                for (const step of Object.keys(out)) Object.freeze(out[step]);
                return Object.freeze(out);
            },
            get revision() { return root.revision; },
            refresh: done => root.refresh(ctx, done)
        };
    }

    // A request during a probe belongs to the following probe. Revision
    // describes changed values; completion describes a fresh reading.
    function refresh(ctx, done) {
        if (done !== undefined && typeof done !== "function") throw new Error("refused: system=refresh done=not-a-function");
        if (!ctx.active) return "refused: system=refresh released";
        if (done !== undefined) {
            const entry = { after: probes + (prober.running ? 2 : 1), id: ctx.id, done: done, release: null };
            entry.release = ctx.onDispose(() => {
                entry.done = null;
                root.pending = root.pending.filter(item => item !== entry);
            });
            pending = pending.concat([entry]);
        }
        probe();
        return "ok";
    }

    function probe() {
        if (prober.running) {
            again = true;
            return;
        }
        prober.completion = null;
        prober.expired = false;
        deadline.restart();
        prober.running = true;
    }

    Timer {
        id: deadline
        interval: 10000
        repeat: false
        onTriggered: {
            prober.expired = true;
            prober.signal(9);
        }
    }

    // The probe state and the steps, null before the first report, for
    // the lending record.
    function record() {
        return { probing: prober.running, probes: probes, revision: revision, steps: steps };
    }

    // Quickshell 0.3.1 Process supports restarting in runningChanged and
    // signal(9) kills the current child; StdioCollector waitForEnd exposes
    // final output. https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process/
    // A missing completion is an unstarted probe, never an access reading.
    Process {
        id: prober
        property var completion: null
        property bool expired: false
        command: [root.coreBin + "/vgshell-system", "status", "--json"]
        stdout: StdioCollector { id: probeOutput; waitForEnd: true }
        stderr: StdioCollector { id: probeErrors; waitForEnd: true }
        onExited: (code, status) => { prober.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            deadline.stop();
            const report = prober.expired
                ? { steps: Logic.systemUnknown("probe-timeout"), line: "system: probe=timeout" }
                : Logic.systemReport(prober.completion, probeOutput.text, probeErrors.text);
            if (report.line !== "") console.error(report.line);
            root.probes += 1;
            if (root.steps === null || !Logic.systemStepsEqual(root.steps, report.steps)) {
                root.steps = report.steps;
                root.revision += 1;
            }
            const ended = root.pending.filter(entry => entry.after <= root.probes);
            root.pending = root.pending.filter(entry => entry.after > root.probes);
            for (const entry of ended) {
                const done = entry.done;
                entry.release();
                if (done !== null) {
                    try { done(); }
                    catch (error) { console.error("capabilities: system refresh of " + entry.id + " threw: " + error.message); }
                }
            }
            if (root.again) {
                root.again = false;
                root.probe();
            }
        }
    }
}
