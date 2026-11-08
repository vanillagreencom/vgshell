import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "GoogleDriveLogic.js" as Logic

// Owns vgs.google-drive's runtime side: the one runner door (RunnerClient),
// the one watch of the runner's status record, the presence probe of the
// Google Drive keys, the notification when the sync needs the user, IPC
// and every status write. The widget and the popover read status only.
// The plugin never runs rclone: Sync now asks systemd for the same service
// the hourly timer and the command line start (bin/google-drive start), and
// that run writes the status record this service watches.
//
// The record is read again whenever the runner writes it: a run's start
// and end, a pause or resume from any caller, install and a pair change.
// The service asks the runner to render it afresh at start and after each
// of its setup TUIs ends, which also reads a run cut short as interrupted.
// The keys are probed at start, after each write the core makes from the
// Settings page's masked fields, after a Sign in or Sign out TUI ends and
// when the pair list changes. The probe's account address reaches the
// published account value alone, which the Details tab draws and the
// `status` IPC answer returns with every published value; never the bar,
// the popover or a log line.
//
//   vgshell ipc call vgs.google-drive invoke <name> ""   with <name>:
//     status    the published values, JSON
//     sync      Sync now: starts the service through systemd; `ok`
//     pause     pauses every pair; `ok`
//     resume    resumes every pair; `ok`
//     dismiss   with a review row's key as its argument, hides that row,
//               one that needs nothing, until its record changes
//               (bin/google-drive dismiss); `ok`
//     refresh   renders the record and probes the keys again; `ok`
// A request that fails is logged and shown in the popover as `problem`. An
// answer the runner holds for the rename from the plugin's previous name
// (Logic.RUNNER_HELD) is no failure: the Details sync value says why it
// waits, and status and probe are asked again on the `held` timer until
// the runner answers them.
Item {
    id: root

    property var shell: null
    property bool registered: false
    // The runner's last accepted status record and probe answer, null
    // before the first.
    property var statusRead: ({ kind: "pending" })
    readonly property var record: statusRead.kind === "loaded" ? statusRead.record : null
    property var presence: null
    // The operation of the last request that failed, and its log line.
    property string problem: ""
    property string problemLine: ""
    // Why the runner last held the rename from the plugin's previous name
    // (Logic.heldReason), "" once an answer passed it.
    property string heldReason: ""
    property var reported: ({})
    // The attention key this service last notified, so a record read again
    // before the runner writes `notified` sends no second notification.
    property string notifiedKey: ""
    property string pairKeys: ""
    // The first `status` answered: the record exists, so its directory
    // does, which the watch needs.
    property bool statusReady: false
    // Settings owns the choice. The runner's control is only its mirror.
    readonly property var twoWaySync: selectedMode()
    property var modeConfirmed: null
    property bool modeInFlight: false
    property bool syncPending: false
    readonly property string statusFile: Paths.stateDir + "/google-drive/status.json"
    readonly property int secretRevision: shell === null ? 0 : shell.secrets.revision
    // The end of each setup TUI's last run, whoever opened it: Settings,
    // the popover or the launcher.
    readonly property string tuiEnds: shell === null ? "" : JSON.stringify(["setup", "add-pair", "remove-pair", "reset-pairs", "connect", "sign-out", "initialize"]
        .map(name => shell.tui.state[name] ? shell.tui.state[name].endedAt : null))

    onShellChanged: {
        start();
        if (registered) mirrorMode();
    }
    onTwoWaySyncChanged: if (registered) mirrorMode()
    onSecretRevisionChanged: if (registered) probe()
    onTuiEndsChanged: if (registered) {
        mirrorMode();
        refresh();
        probe();
    }

    // Binding evaluation order is unspecified, so shellChanged can run
    // before twoWaySync updates. Imperative admission reads Settings
    // directly; the binding above only supplies change notifications.
    // https://doc.qt.io/qt-6/qtqml-syntax-propertybinding.html
    function selectedMode() {
        return shell === null ? undefined
            : shell.settings.twoWaySync === undefined ? shell.manifest.settings.twoWaySync : shell.settings.twoWaySync;
    }

    function start() {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("status", () => JSON.stringify(shell.status.values));
        shell.ipc.handle("sync", () => root.act(["start"]));
        shell.ipc.handle("pause", () => root.act(["pause"]));
        shell.ipc.handle("resume", () => root.act(["resume"]));
        shell.ipc.handle("dismiss", key => root.act(["dismiss", key]));
        shell.ipc.handle("refresh", () => {
            root.refresh();
            root.probe();
            return "ok";
        });
        mirrorMode();
        refresh();
        probe();
    }

    function failed(operation, line) {
        console.warn("google-drive: " + line);
        problem = operation;
        problemLine = line;
        publish();
    }

    function succeeded(operation) {
        if (problem !== operation) return;
        problem = "";
        problemLine = "";
        publish();
    }

    // The runner writes the record; the watch reads it.
    function refresh() {
        client.request(["status", "--quiet"], (ok, out, line, code) => {
            if (root.heldAnswer(code, line)) return;
            if (!ok) {
                root.unreadable(line);
                return;
            }
            root.statusReady = true;
        });
    }

    function probe() {
        client.request(["probe"], (ok, out, line, code) => {
            if (root.heldAnswer(code, line)) return;
            if (!ok) {
                root.failed("probe", line);
                return;
            }
            const judged = Logic.parseProbe(out);
            if (!judged.ok) {
                root.failed("probe", "probe answer refused: " + judged.error);
                return;
            }
            root.presence = judged.presence;
            root.succeeded("probe");
            root.publish();
        });
    }

    // Whether the runner held this answer for the rename. The rename runs
    // before every verb, so each answer sets or clears the held state.
    function heldAnswer(code, line) {
        root.retryIfHeld(code);
        const reason = code === Logic.RUNNER_HELD ? Logic.heldReason(line) : "";
        if (reason === heldReason) return reason !== "";
        if (reason !== "") console.warn("google-drive: " + line);
        heldReason = reason;
        publish();
        return reason !== "";
    }

    function retryIfHeld(code) {
        if (code === Logic.RUNNER_HELD) held.restart();
    }

    // start, pause, resume or dismiss, the runner's verb and its
    // arguments; the runner's record write shows its effect.
    function act(args) {
        const operation = args[0];
        if (operation === "start") {
            syncPending = true;
            mirrorMode();
            return "ok";
        }
        client.request(args, (ok, out, line, code) => {
            if (root.heldAnswer(code, line)) return;
            if (ok) root.succeeded(operation);
            else root.failed(operation, line);
        });
        return "ok";
    }

    function mirrorMode() {
        if (shell === null || modeInFlight) return;
        const selected = selectedMode();
        if (modeConfirmed === selected) {
            flushSync();
            return;
        }
        modeInFlight = true;
        publish();
        // RunnerClient's Process command is an argv list, never a shell
        // string (Quickshell 0.3.1):
        // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process
        // Coalesce changes while this serialized write runs. Only its
        // successful answer permits a Sync now request.
        client.request(["set-two-way", selected ? "true" : "false"], (ok, out, line, code) => {
            root.modeInFlight = false;
            if (root.heldAnswer(code, line)) {
                root.modeConfirmed = null;
                return;
            }
            if (!ok) {
                root.modeConfirmed = null;
                root.syncPending = false;
                root.failed("set-two-way", line);
                return;
            }
            root.modeConfirmed = selected;
            root.succeeded("set-two-way");
            root.publish();
            root.refresh();
            root.mirrorMode();
        });
    }

    function flushSync() {
        if (!syncPending || modeInFlight || modeConfirmed !== selectedMode()) return;
        syncPending = false;
        if (statusRead.kind === "unreadable") return;
        client.request(["start"], (ok, out, line, code) => {
            if (root.heldAnswer(code, line)) return;
            if (ok) root.succeeded("start");
            else root.failed("start", line);
        }, () => {
            if (root.modeInFlight || root.modeConfirmed !== root.selectedMode()) {
                root.syncPending = true;
                root.mirrorMode();
                return false;
            }
            return root.statusRead.kind !== "unreadable";
        });
    }

    function unreadable(line) {
        statusRead = { kind: "unreadable", line: line };
        syncPending = false;
        stale.stop();
        failed("status", line);
    }

    function accept(content) {
        const judged = Logic.parseStatus(content);
        if (!judged.ok) {
            unreadable("status record refused: " + judged.error);
            return;
        }
        statusRead = { kind: "loaded", record: judged.record };
        succeeded("status");
        if (record.twoWaySync !== selectedMode()) {
            modeConfirmed = null;
            mirrorMode();
        }
        const now = record.pairs.map(p => p.id).sort().join(",");
        if (now !== pairKeys) {
            pairKeys = now;
            probe();
        }
        publish();
        notifyOnce();
        schedule();
    }

    function publish() {
        if (shell === null) return;
        // A later control failure or success cannot erase an unreadable
        // status result. Only the watch's next accepted read replaces it.
        const failure = statusRead.kind === "unreadable" ? Logic.problemText("status", statusRead.line) : Logic.problemText(problem, problemLine);
        const values = Logic.statusValues(record, presence, failure, heldReason, Date.now(), Paths.home);
        const selected = selectedMode();
        if (values.cloud !== undefined) values.cloud.modePending = modeInFlight || modeConfirmed !== selected || record.twoWaySync !== selected;
        const next = Object.assign({}, reported);
        for (const key of Logic.changedKeys(reported, values)) {
            const value = values[key] === undefined ? null : values[key];
            const reply = shell.status.set(key, value);
            if (!shell.status.isOk(reply)) console.error("google-drive: " + reply);
            else next[key] = value;
        }
        reported = next;
    }

    // The runner keeps whether a change that needs the user was notified
    // (`attention.notified`), so a restart of the shell notifies no change
    // twice: the service notifies while it is false, then has the runner
    // record the key, whether the core delivered the notification or
    // dropped it by its own rule.
    function notifyOnce() {
        if (record.attention === null) {
            notifiedKey = "";
            return;
        }
        if (record.attention.notified || record.attention.key === notifiedKey) return;
        const key = record.attention.key;
        notifiedKey = key;
        const message = Logic.notification(record);
        if (message !== null) {
            const reply = shell.notify.send({ title: message.title, message: message.message, tone: message.tone, icon: "cloud-alert" });
            if (reply !== "ok") console.warn("google-drive: notify " + reply);
        }
        client.request(["attention-seen", key], (ok, out, line) => {
            if (!ok) console.warn("google-drive: " + line);
        });
    }

    // Idle data turns old with no write, so the values are published again
    // when it does.
    function schedule() {
        const at = Logic.nextStale(record, Date.now());
        if (at === null) {
            stale.stop();
            return;
        }
        stale.interval = Math.min(at - Date.now() + 1000, 2147483647);
        stale.restart();
    }

    RunnerClient { id: client }

    // The runner replaces the record by rename; WatchedFile reads it again
    // on every change and drops no change that lands during a read.
    LazyLoader {
        active: root.statusReady
        WatchedFile {
            path: root.statusFile
            onChanged: read()
            onLoaded: content => root.accept(content)
            onLoadFailed: error => root.unreadable("status record unreadable: " + FileViewError.toString(error))
        }
    }

    // One timer for both requests: each held answer restarts it, and its
    // end asks for both again, which RunnerClient runs one after the other.
    Timer {
        id: held
        interval: Logic.HELD_RETRY_MS
        repeat: false
        onTriggered: {
            root.mirrorMode();
            root.refresh();
            root.probe();
        }
    }

    Timer {
        id: stale
        repeat: false
        onTriggered: {
            root.publish();
            root.schedule();
        }
    }
}
