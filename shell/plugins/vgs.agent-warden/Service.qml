import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "WardenLogic.js" as WardenLogic
import "ViewLogic.js" as ViewLogic
import "Notices.js" as Notices

// The Agent Warden service: the one reader of the warden's status file,
// $XDG_RUNTIME_DIR/agent-warden/status.json, which vsys's warden replaces
// every tick. It derives the consumer state through WardenLogic.js and
// publishes it as plugin status (manifest `status`, D037), which the
// plugin's other instances and its Settings page read. It never runs,
// starts or changes the warden.
//   vgshell ipc call vgs.agent-warden invoke status
//     the published values as one JSON line
//   vgshell ipc call vgs.agent-warden invoke panel open|closed
//     the flyout's own report of its open and close (Panel.qml), the one
//     reader of the summary while no fresh status comes
//
// The derivation runs again when a file changes and when one timer fires
// at the moment WardenLogic.nextChange names, so a status the warden
// stopped rewriting reads as stale 90 s after its time, with no file
// change.
//
// It runs `vsys --once --summary` once for each status it reads, when
// vsys comes or goes, and, while the flyout is open and no fresh status
// comes (not set up, or not checking), once as it opens and every
// WardenLogic.TICK_MS after, and adds the summary's warn and
// danger causes to the derived state, so the shield, the flyout's heading
// and its rows count the same things (WardenLogic.withCauses). A run is
// stopped after summaryLimitMs.
//
// It also owns the desktop notices about agents (Notices.js). While it
// reads a status, it touches the warden's heartbeat,
// $XDG_RUNTIME_DIR/agent-warden/notifier, every 60 s, and the warden then
// sends none of its own. Each derivation steps the episodes it remembers
// and sends each new one once through the core's shell.notify.send. A
// press on one of a notice's actions opens the plugin's `vsys` TUI with
// that action's arguments. The episodes live as long as the service: a
// service built again, by a shell restart or a new plugin revision, sends
// each episode still open once more.
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    // The shell this service registered with, so a new object handed over
    // registers nothing twice.
    property var registeredWith: null

    readonly property string dir: Quickshell.env("XDG_RUNTIME_DIR") + "/agent-warden"
    // The last read of status.json: WardenLogic.readStatus's answer, or
    // { kind: "absent" }, or { kind: "pending" } before the first read.
    property var status: ({ kind: "pending" })
    // The derived state, WardenLogic.derive's answer with the summary's
    // causes; null while a read is pending. derive() alone sets it.
    property var detail: null
    // The warn and danger causes of the last `vsys --once --summary`,
    // ViewLogic.readSummary's, or null while none was read, vsys is
    // missing or the last run failed.
    property var causes: null
    // Whether a status landed while a summary ran, so one more run follows
    // it and the causes are never older than the last status.
    property bool summaryOwed: false
    // How long a summary run may take before it is stopped. vsys samples
    // for about 200 ms, so this ends only a run that hangs.
    readonly property int summaryLimitMs: 10000
    // Whether the running summary was stopped at its limit.
    property bool summaryTimedOut: false
    // The cause of the last failed summary, logged once until a run reads
    // or fails for another cause; "" after a run that reads.
    property string summaryFailure: ""
    // Whether the derived state is one no fresh status paces: not set up,
    // or not checking for any reason.
    readonly property bool summaryUnpaced: detail !== null && (detail.state === "not-set-up" || detail.state === "not-checking")
    // Whether the flyout is open, as Panel.qml reports it. In an unpaced
    // state the shield counts no cause, so the flyout is the summary's only
    // reader there.
    property bool panelOpen: false
    // The plugin's requirement commands the last scan did not find; its
    // change publishes again. publish() reads the source itself, since a
    // dependent binding may still hold its old value in a change handler.
    readonly property var missing: shell === null ? null : shell.requirements.missing
    // The `notify` setting: which notices go out, one of Notices.MODES.
    readonly property string mode: shell === null ? "" : shell.settings.notify
    // Whether this service owns the notices and touches the heartbeat.
    readonly property bool owns: shell !== null && Notices.owns(status)
    // The keys of the open episodes this service remembers, Notices.step's.
    property var episodes: []
    // The new episodes the last step dropped past Notices.MAX_EPISODES,
    // logged when it changes.
    property int dropped: 0
    // Whether the last heartbeat write failed, logged when it starts.
    property bool heartbeatFailed: false

    onShellChanged: {
        if (shell === null) return;
        if (registeredWith === null) {
            registeredWith = shell;
            shell.shortcut.register("toggle", "Open or close Agent Warden", () => root.togglePanel());
            shell.ipc.handle("status", () => JSON.stringify(root.shell.status.values));
            shell.ipc.handle("panel", state => root.panelReport(state));
        }
        derive();
    }

    // The flyout reports STATE, `open` or `closed`. An open while no fresh
    // status comes runs the summary once, so the flyout shows a fresh
    // reading.
    function panelReport(state) {
        if (state !== "open" && state !== "closed") return "refused: panel=" + JSON.stringify(state);
        panelOpen = state === "open";
        if (panelOpen && summaryUnpaced) summarize();
        return "ok";
    }

    function togglePanel() {
        const reply = shell.surfaces.toggle("panel", "{}");
        if (reply !== "ok") console.warn("agent-warden: panel " + reply);
        return reply;
    }
    onStatusChanged: {
        derive();
        summarize();
    }
    onCausesChanged: derive()

    // One `vsys --once --summary` per status read, the warden's check, per
    // change of the missing commands, and per tick of summaryTick. vsys
    // judges the computer apart from the warden, so a status that is
    // absent, stale or cannot be read runs it too. A call while a run goes
    // owes one more run after it, never a second run beside it.
    function summarize() {
        if (shell === null || status.kind === "pending") return;
        if (shell.requirements.missing.indexOf("vsys") !== -1) {
            causes = null;
            return;
        }
        if (summaryRun.running) {
            summaryOwed = true;
            return;
        }
        summaryRun.completion = null;
        summaryTimedOut = false;
        summaryRun.running = true;
        summaryLimit.restart();
    }
    onMissingChanged: {
        publish();
        summarize();
    }
    // A value the manifest's schema does not offer reaches the service
    // only from a hand-edited file; the service then sends nothing.
    onModeChanged: {
        if (mode !== "" && Notices.MODES.indexOf(mode) === -1)
            console.error("agent-warden: notify=" + JSON.stringify(mode) + " unknown\nThe notify setting takes " + Notices.MODES.join(", ") + "; no notice goes out until it does.");
    }

    // Derive the state from the status at this moment, publish it, and set
    // the timer to the next moment the answer can change with the files
    // unchanged.
    function derive() {
        const file = status;
        const now = Date.now();
        detail = WardenLogic.withCauses(WardenLogic.derive(file, now), causes);
        const next = WardenLogic.nextChange(file, now);
        if (next === null) {
            deadline.stop();
        } else {
            // Timer.interval is a 32-bit int: a moment further ahead fires
            // at the ceiling, derives again and sets the timer again.
            deadline.interval = Math.min(next - now, 2147483647);
            deadline.restart();
        }
        publish();
        if (detail !== null) notify(now);
    }

    // Step the remembered episodes through the derived state at NOW and
    // send each new one the `notify` setting asks for. Memory moves under
    // every setting, so an episode open while notices were off is not sent
    // when they come back on.
    function notify(now) {
        if (shell === null) return;
        const result = Notices.step(episodes, Notices.conditionsOf(detail));
        episodes = result.memory;
        if (result.dropped !== dropped && result.dropped > 0)
            console.error("agent-warden: notices=full dropped=" + result.dropped + " limit=" + Notices.MAX_EPISODES);
        dropped = result.dropped;
        if (Notices.MODES.indexOf(mode) === -1) return;
        const vsys = shell.requirements.missing.indexOf("vsys") === -1;
        for (const notice of Notices.notices(result.opened, mode, vsys, now)) send(notice);
    }

    // One notice through the core. A refusal or failed delivery forgets
    // its episodes, so the next status retries even a notice with no action.
    // A pressed action answers its index in notice.actions (shellOptions).
    function send(notice) {
        const reply = shell.notify.send(Notices.shellOptions(notice), (action, delivery) => {
            if (delivery === "failed") {
                episodes = Notices.forget(episodes, notice.keys);
                return;
            }
            if (action === "") return;
            const chosen = notice.actions[Number(action)];
            if (chosen === undefined) return;
            const opened = shell.tui.run("vsys", chosen.args);
            if (!ViewLogic.handedOff(opened)) console.error("agent-warden: action=" + action + " " + opened);
        });
        if (reply !== "ok") {
            console.error("agent-warden: notice=" + notice.keys.join(",") + " " + reply);
            episodes = Notices.forget(episodes, notice.keys);
        }
    }

    // Publish each value that differs from the one the core holds. A
    // refusal means a value this plugin declares did not fit its own
    // declaration, which WardenLogic.published rules out.
    function publish() {
        if (shell === null || detail === null) return;
        const values = WardenLogic.published(detail, shell.requirements.missing);
        const held = shell.status.values;
        for (const key of Object.keys(values)) {
            if (JSON.stringify(held[key]) === JSON.stringify(values[key])) continue;
            const reply = shell.status.set(key, values[key]);
            if (!shell.status.isOk(reply)) console.error("agent-warden: publish=" + key + " " + reply);
        }
    }

    // A status that cannot be read is logged once per cause; the published
    // state already says so. An absent status is a warden not set up, a
    // normal state, and logs nothing.
    function readStatus(next) {
        if ((next.kind === "unreadable" || next.kind === "schema" || next.kind === "old-vsys") && JSON.stringify(next) !== JSON.stringify(status))
            console.warn("agent-warden: status=" + next.kind + " " + (next.kind === "unreadable" ? "cause=" + next.cause : "schema=" + next.schema) + " path=" + dir + "/status.json");
        status = next;
    }

    // The heartbeat: a write of the time, in milliseconds, so the text
    // changes and FileView.setText, which skips unchanged text, writes each
    // time.
    // The warden reads only the file's age. The timer touches it at once
    // when the service starts to own the notices, and a file it stops
    // touching goes stale 120 s after its last write.
    FileView {
        id: heartbeat
        path: root.dir + "/notifier"
        preload: false
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onSaved: root.heartbeatFailed = false
        onSaveFailed: error => {
            if (!root.heartbeatFailed)
                console.error("agent-warden: heartbeat=failed path=" + path + " error=" + FileViewError.toString(error));
            root.heartbeatFailed = true;
        }
    }
    Timer {
        interval: Notices.HEARTBEAT_MS
        repeat: true
        triggeredOnStart: true
        running: root.owns && dirProc.settled
        onTriggered: heartbeat.setText(String(Date.now()) + "\n")
    }

    Timer {
        id: deadline
        repeat: false
        onTriggered: root.derive()
    }

    // The summary's pace while no fresh status sets it and the flyout,
    // its one reader then, is open.
    Timer {
        id: summaryTick
        interval: WardenLogic.TICK_MS
        repeat: true
        running: root.summaryUnpaced && root.panelOpen
        onTriggered: root.summarize()
    }

    // Setting Process.running to false sends the run SIGTERM, and its end
    // then takes the failure branch below
    // (https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process/).
    Timer {
        id: summaryLimit
        interval: root.summaryLimitMs
        repeat: false
        onTriggered: {
            root.summaryTimedOut = true;
            summaryRun.running = false;
        }
    }

    // A watcher adds only a directory that exists when it is built, so the
    // warden's directory is made
    // before the watches start: a warden set up while the shell runs is
    // then seen. A directory that could not be made is logged and the
    // watches start anyway, reading the status as absent.
    Process {
        id: dirProc
        property var completion: null
        property bool settled: false
        command: ["mkdir", "-p", "--", root.dir]
        running: true
        stderr: StdioCollector { id: dirErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            if (completion === null || completion.code !== 0 || completion.status !== 0)
                console.error("agent-warden: directory failed: dir=" + root.dir + " " + JSON.stringify(completion) + "\n" + dirErr.text.trim());
            settled = true;
        }
    }

    LazyLoader {
        active: dirProc.settled
        WatchedFile {
            path: root.dir + "/status.json"
            onChanged: read()
            onLoaded: content => root.readStatus(WardenLogic.readStatus(content))
            onLoadFailed: error => root.readStatus(error === FileViewError.FileNotFound ? { kind: "absent" } : { kind: "unreadable", cause: "read=" + FileViewError.toString(error) })
        }
    }

    // vsys exits 2 after it prints the summary when it could not read a
    // source, so the causes follow the summary alone, whatever the exit
    // code; a run that did not start, was stopped at its limit or printed
    // what this plugin cannot read drops the causes, logged when its cause
    // differs from the last failure's. A run that ends after vsys left the
    // scan keeps no causes and owes no rerun.
    Process {
        id: summaryRun
        // The run's exit, { code, status }, null until `exited` arrives: a
        // command that fails to start emits `runningChanged` alone.
        property var completion: null
        command: ["vsys", "--once", "--summary"]
        stdout: StdioCollector { id: summaryOut }
        stderr: StdioCollector { id: summaryErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            summaryLimit.stop();
            if (root.shell === null || root.shell.requirements.missing.indexOf("vsys") !== -1) {
                root.causes = null;
                root.summaryOwed = false;
                return;
            }
            const read = completion === null || root.summaryTimedOut ? null : ViewLogic.readSummary(summaryOut.text);
            if (read !== null && read.kind === "read") {
                root.summaryFailure = "";
                if (JSON.stringify(read.causes) !== JSON.stringify(root.causes)) root.causes = read.causes;
            } else {
                root.causes = null;
                const failure = root.summaryTimedOut ? "timeout" : JSON.stringify(completion) + (read === null ? "" : " cause=" + read.cause);
                if (failure !== root.summaryFailure) {
                    if (root.summaryTimedOut) console.warn("agent-warden: summary=timeout limit=" + root.summaryLimitMs);
                    else console.warn("agent-warden: summary=failed " + failure + " " + summaryErr.text.trim().split("\n")[0]);
                }
                root.summaryFailure = failure;
            }
            if (root.summaryOwed) {
                root.summaryOwed = false;
                root.summarize();
            }
        }
    }
}
