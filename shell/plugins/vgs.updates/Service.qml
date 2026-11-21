import QtQuick
import Quickshell
import Quickshell.Io
import "UpdatesLogic.js" as Logic

// Owns vgs.updates runtime state: cached snapshot readback, the last update
// run's outcome, one check process, cadence timers, IPC and every status
// write. The widget and the window
// read status only; this service is the single writer.
Item {
    id: root

    property var shell: null
    property bool registered: false
    // `cached` on the snapshot is true when it was read from the cache at
    // start, the one origin that can predate this boot
    // (UpdatesLogic.snapshotBeforeBoot); nothing publishes or writes it.
    property var snapshot: null
    // Whether the startup reads have answered, loaded or failed: until then
    // no timer is set, so a service rebuilt with a fresh cache does not
    // check before it reads it and the current boot time.
    property bool cacheRead: false
    property bool bootRead: false
    property var bootedAt: null
    // Startup, admission, execution and publication are one refresh lifetime.
    property string phase: "idle"
    readonly property bool checking: phase !== "idle"
    property string admission: "unknown"
    // Whether a run's end, its own check or its TUI's, arrived during a
    // refresh that may have read the packages before the run's last step:
    // that refresh is replaced once.
    property bool queued: false
    // Whether the update run now ending asked its own check (`check run`,
    // tui/pipeline.sh), so its TUI's end starts none.
    property bool runChecked: false
    // The last update run's outcome, UpdatesLogic.runOutcome of
    // outcome.json, null before one is read.
    property var lastRun: null
    // The TUI state this instance last read, null before the first read.
    property var lastTuiState: null
    property string checkFailure: ""
    property double failedAt: -1
    property var reported: ({})
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/vgshell/updates"
    readonly property string statusPath: stateDir + "/status.json"
    readonly property string outcomePath: stateDir + "/outcome.json"
    readonly property string bootPath: "/proc/stat"
    readonly property string packageLogPath: "/var/log/pacman.log"
    // The last completed transaction this instance read in the package log
    // (UpdatesLogic.packageLogMark), null before the first read.
    property var packageLogMark: null
    // Whether the next read takes the log as it stands and judges nothing:
    // the check asked with it covers the transactions already there. Any
    // answer ends it; after a failed read the next read judges them, which
    // costs at most one more check and loses none.
    property bool packageLogRebase: false
    // Whether a read was asked while one was in flight, which may predate
    // what the ask is for: that result is dropped and the log read again.
    property bool packageLogAgain: false
    readonly property string checkScript: String(Qt.resolvedUrl("bin/check")).replace(/^file:\/\//, "")
    readonly property string vgshellPath: Quickshell.shellDir + "/../bin/vgshell"
    readonly property string connectivityPath: Quickshell.shellDir + "/../bin/lib/connectivity.js"
    readonly property int currentIntervalMs: Logic.intervalMs(shell === null ? null : shell.settings)
    readonly property var currentTuiState: shell === null || shell.tui === undefined ? ({}) : shell.tui.state
    // Whether an install run of this plugin's TUIs (shell.tui.state is keyed
    // by script name) has not yet asked its own check: until then its
    // transactions are its own, and that check, which tui/pipeline.sh asks
    // after its last package step, covers them. The log viewer installs
    // nothing.
    readonly property bool installing: !runChecked && ["update", "update-source"].some(name => (currentTuiState[name] || {}).running === true)
    // The reboot-notice system step, which the core probes again after its
    // run in core/system and after each plugin scan.
    readonly property var rebootStep: shell === null ? null : shell.system.state["reboot-notice"]
    readonly property string rebootRequest: shell === null || typeof shell.settings.rebootNotice !== "string" ? "" : shell.settings.rebootNotice
    readonly property bool pageViewed: shell !== null && shell.status.viewed
    property bool rebootOfferVisited: false
    property bool updateAfterRebootNotice: false
    // Another Update press must wait for the setup terminal to end.
    property bool rebootSetupRunning: false
    // The AUR command setting, which decides what the VGS row says installs
    // a new release package (UpdatesLogic.publishedNote).
    readonly property string aurCommand: shell === null || typeof shell.settings.aurCommand !== "string" ? "" : shell.settings.aurCommand

    onShellChanged: {
        start();
        offerRebootNotice();
    }
    onCurrentIntervalMsChanged: schedule()
    onRebootStepChanged: {
        publishNow();
        offerRebootNotice();
    }
    onPageViewedChanged: {
        if (!pageViewed) rebootOfferVisited = false;
        offerRebootNotice();
    }
    onRebootRequestChanged: {
        // Qt.callLater runs its callback when the engine returns to the event loop
        // (doc.qt.io/qt-6/qml-qtqml-qt.html#callLater-method). managerChoose
        // must read the new setting and report the user's press first. A
        // stored request or config edit is cleared without starting a step.
        if (rebootRequest !== "") Qt.callLater(clearRebootRequest);
    }
    onAurCommandChanged: publishNow()
    // Only a run that ends after this instance first read the state starts
    // a check: `shell` arrives with every run an earlier instance saw end,
    // and this handler can run before onShellChanged does, so the first read
    // is recorded and judged by nothing (UpdatesLogic.tuiRunEnded). It reads
    // the state from its source, since the binding may not have followed a
    // new `shell` yet. A run that asked its own check starts no second one;
    // one stopped before it asked, or a TUI that asks none, gets this one.
    onCurrentTuiStateChanged: {
        if (shell === null) return;
        const state = shell.tui.state;
        if (Logic.tuiRunEnded(lastTuiState, state)) {
            outcomeReader.reload();
            if (runChecked) runChecked = false;
            else {
                rebasePackageLog();
                requestCheck("tui");
            }
        }
        lastTuiState = state;
    }

    function start() {
        if (shell === null || registered) return;
        registered = true;
        shell.shortcut.register("toggle", "Open or close Updates", () => root.toggleWindow());
        shell.shortcut.register("update-all", "Update all", () => {
            const reply = root.updateAll();
            if (reply !== "ok") root.showUpdateRefusal(reply);
        });
        shell.ipc.handle("check", arg => root.requestCheck(arg === "run" ? "run" : "ipc"));
        shell.ipc.handle("update-all", () => root.updateAll());
        shell.ipc.handle("reboot-notice-answer", choice => root.answerRebootNotice(choice));
        shell.ipc.handle("reboot-notice-dismissed", () => {
            const reply = root.answerRebootNotice("");
            if (reply !== "ok") root.showUpdateRefusal(reply);
            return reply;
        });
        shell.ipc.handle("status", () => JSON.stringify(shell.status.values));
        // handleChoice reports only the user's Settings press, never a
        // config edit or reload (plugin API, status.handleChoice).
        shell.status.handleChoice("rebootNotice", value => root.takeRebootRequest(value));
        cacheReader.path = statusPath;
        outcomeReader.path = outcomePath;
        bootReader.path = bootPath;
        packageLogWatch.path = packageLogPath;
        readPackageLog(false);
        if (lastTuiState === null) lastTuiState = shell.tui.state;
        publishNow();
    }

    function toggleWindow() {
        const reply = shell.surfaces.toggle("window", "{}");
        if (reply !== "ok") console.warn("updates: window " + reply);
        return reply;
    }

    function offerRebootNotice() {
        if (shell === null || updateAfterRebootNotice) return;
        if (!pageViewed || !rebootStep || rebootStep.state !== "needed") {
            shell.surfaces.hide("panel");
            return;
        }
        if (rebootOfferVisited || !Logic.offerRebootNotice(rebootStep, shell.settings.rebootNoticeAnswered)) return;
        const reply = shell.surfaces.summon("panel", "{}");
        if (reply === "ok") rebootOfferVisited = true;
        else console.warn("updates: reboot offer " + reply);
    }

    function runAll() {
        const request = Logic.tuiRequest("all");
        return shell.tui.run(request.name, request.args);
    }

    function updateAll() {
        if (rebootSetupRunning) return "busy";
        updateAfterRebootNotice = true;
        if (!Logic.offerRebootNotice(rebootStep, shell.settings.rebootNoticeAnswered)) return finishUpdateOffer();
        return shell.surfaces.summon("panel", "{}");
    }

    function finishUpdateOffer() {
        const reply = runAll();
        if (reply === "ok") updateAfterRebootNotice = false;
        return reply;
    }

    function showUpdateRefusal(reply) {
        const problem = Logic.replyLine(reply);
        if (problem === "") return;
        const shown = shell.surfaces.summon("window", JSON.stringify({ problem }));
        if (shown !== "ok") console.warn("updates: window " + shown);
    }

    function answerRebootNotice(choice) {
        if (choice !== "" && choice !== "both" && choice !== "vgsOnly") return "refused: reboot-notice=choice";
        const setup = choice === "vgsOnly" && Logic.rebootNoticeRequested(choice, shell.status.values.rebootNotice);
        if (choice !== "") {
            const stored = shell.configure.set("rebootNoticeAnswered", true);
            if (stored !== "ok") return stored;
        }
        if (setup) {
            // status.act's done is released with its asking instance (plugin
            // API). The service outlives the hidden panel and Updates window,
            // so the update starts only after the setup terminal ends.
            const update = updateAfterRebootNotice;
            rebootSetupRunning = true;
            const reply = shell.status.act("rebootNotice", undefined, undefined, () => {
                root.rebootSetupRunning = false;
                if (!update) return;
                const launched = root.finishUpdateOffer();
                if (launched !== "ok") root.showUpdateRefusal(launched);
            });
            if (reply !== "ok") rebootSetupRunning = false;
            return reply;
        }
        if (updateAfterRebootNotice) return finishUpdateOffer();
        return "ok";
    }

    // The core's `core/system` run shows its root commands and asks before
    // it changes anything, and the probe after it moves the field.
    function takeRebootRequest(request) {
        if (shell === null || request === "") return;
        if (Logic.rebootNoticeRequested(request, reported.rebootNotice)) {
            const reply = shell.status.act("rebootNotice");
            if (reply !== "ok") console.warn("updates: reboot notice " + reply);
        }
        clearRebootRequest();
    }

    function clearRebootRequest() {
        if (shell === null || rebootRequest === "") return;
        const cleared = shell.configure.unset("rebootNotice");
        if (cleared !== "ok") console.error("updates: " + cleared);
    }

    function requestCheck(reason) {
        if (reason === "run") {
            runChecked = true;
            rebasePackageLog();
        }
        if (checking && phase !== "publishing") {
            if (reason === "run" || reason === "tui" || reason === "log") queued = true;
            return "queued";
        }
        phase = "startup";
        if (!publishNow()) {
            phase = "publishing";
            return "refused: check=status-unavailable";
        }
        beginAdmission();
        return "started";
    }

    function beginAdmission() {
        if (phase !== "startup" || !cacheRead || !bootRead) return;
        phase = "admission";
        connectivityProc.command = ["node", connectivityPath];
        connectivityProc.running = true;
    }

    function finishRefresh() {
        // Keep the mask through the one replacement, including offline
        // admission.
        if (queued) {
            queued = false;
            phase = "startup";
            beginAdmission();
            return;
        }
        phase = "publishing";
        // Publish the complete result under the mask; clearing checking is
        // the final write. A refused write leaves the mask in place.
        if (!publishNow(true)) return;
        phase = "idle";
        schedule();
    }

    function maybeCheck() {
        if (!cacheRead || !bootRead) return;
        if (phase === "startup") { beginAdmission(); return; }
        if (Logic.shouldRunCheck(snapshot, checking, Date.now(), currentIntervalMs, failedAt < 0 ? null : failedAt, bootedAt)) requestCheck("due");
        else schedule();
    }

    function schedule() {
        const delay = Logic.nextTimerDelay(snapshot, checking, Date.now(), currentIntervalMs, failedAt < 0 ? null : failedAt, cacheRead, bootRead, bootedAt);
        if (delay === null) {
            cadence.stop();
            return;
        }
        cadence.interval = Math.max(1000, Math.min(delay, 2147483647));
        cadence.restart();
    }

    function acceptText(text, cached) {
        const judged = Logic.parseSnapshotText(text);
        if (!judged.ok) {
            console.warn("updates: cache refused: " + judged.error);
            return false;
        }
        snapshot = Object.assign(judged.snapshot, { cached: cached });
        checkFailure = "";
        failedAt = -1;
        if (cached) { publishNow(); schedule(); }
        return true;
    }

    function takeOutcome(outcome) {
        if (outcome === null) {
            console.warn("updates: outcome refused: " + outcomePath);
            return;
        }
        lastRun = outcome;
        publishNow();
    }

    function rebasePackageLog() {
        packageLogSettle.stop();
        readPackageLog(true);
    }

    function readPackageLog(rebase) {
        if (rebase === true) packageLogRebase = true;
        if (packageLogReader.path !== "") {
            packageLogAgain = true;
            return;
        }
        packageLogReader.path = packageLogPath;
    }

    // MARK is undefined for an unreadable log, which keeps the last mark.
    function takePackageLog(mark) {
        // An empty path unloads the view (FileView.path,
        // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/FileView),
        // so the service holds the mark and none of the log between reads.
        packageLogReader.path = "";
        if (packageLogAgain) {
            packageLogAgain = false;
            Qt.callLater(readPackageLog);
            return;
        }
        const rebase = packageLogRebase;
        packageLogRebase = false;
        if (mark === undefined) return;
        const completed = !rebase && Logic.packageLogCompleted(packageLogMark, mark);
        packageLogMark = mark;
        if (completed && !installing) requestCheck("log");
    }

    function publishNow(completed) {
        if (shell === null) return false;
        const notice = Logic.rebootNoticeValue(rebootStep);
        const values = Object.assign(Logic.publishValues(snapshot, completed === true ? false : checking, Date.now(), currentIntervalMs, checkFailure, aurCommand, admission),
            { admission: admission, lastRun: lastRun },
            { rebootNotice: notice, rebootNotices: Logic.rebootNoticeChoices(notice), rebootNoticeOwner: Logic.rebootNoticeOwnerValue(rebootStep) });
        const writes = Logic.statusWrites(reported, values);
        const next = Object.assign({}, reported);
        for (const write of writes) {
            const reply = shell.status.set(write.key, write.value);
            if (!shell.status.isOk(reply)) {
                console.error("updates: " + reply);
                reported = next;
                return false;
            }
            next[write.key] = write.value;
        }
        reported = next;
        return true;
    }

    // Reads the cache once, when start() sets its path; without `preload` it
    // would never read.
    FileView {
        id: cacheReader
        printErrors: false
        onLoaded: {
            root.cacheRead = true;
            root.acceptText(text(), true);
            root.maybeCheck();
        }
        onLoadFailed: error => {
            root.cacheRead = true;
            if (error !== FileViewError.FileNotFound) console.warn("updates: cache unreadable: " + error);
            root.publishNow();
            root.maybeCheck();
        }
    }

    // Reads the last run's outcome when start() sets its path and again at
    // each TUI end; it watches nothing, since only a run writes the file.
    FileView {
        id: outcomeReader
        printErrors: false
        onLoaded: root.takeOutcome(Logic.runOutcome(text()))
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) console.warn("updates: outcome unreadable: " + error);
        }
    }

    FileView {
        id: bootReader
        onLoaded: {
            root.bootedAt = Logic.parseBootTime(text());
            root.bootRead = true;
            if (root.bootedAt === null) console.warn("updates: boot time unreadable");
            root.maybeCheck();
        }
        onLoadFailed: error => {
            root.bootedAt = null;
            root.bootRead = true;
            console.warn("updates: boot time unreadable: " + error);
            root.maybeCheck();
        }
    }

    // Watches the package log for a transaction an install outside the
    // Updates window completed. The engine's view watches the file and its
    // folder, and reports the file again once it is created or replaced, so
    // a log missing at start or rotated keeps its watch (FileView::
    // onWatchedDirectoryChanged in the shipped engine's src/io/fileview.cpp).
    FileView {
        id: packageLogWatch
        preload: false
        watchChanges: true
        printErrors: false
        onFileChanged: if (!root.installing) packageLogSettle.restart()
    }

    // A transaction's hooks write after its completed line, and a script's
    // next transaction follows within seconds: one read once the log has
    // been quiet this long takes the burst as one change, well inside the
    // minute an outside install may take to reach the count.
    Timer {
        id: packageLogSettle
        objectName: "packageLogSettle"
        interval: 5000
        repeat: false
        onTriggered: root.readPackageLog(false)
    }

    FileView {
        id: packageLogReader
        printErrors: false
        onLoaded: root.takePackageLog(Logic.packageLogMark(text()))
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) console.warn("updates: package log unreadable: " + error);
            root.takePackageLog(error === FileViewError.FileNotFound ? Logic.packageLogMark("") : undefined);
        }
    }

    Process {
        id: connectivityProc
        stdout: StdioCollector { id: connectivityOut }
        property var completion: null
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            root.admission = Logic.connectivityAdmission(done, connectivityOut.text);
            if (root.admission === "online") {
                root.phase = "check";
                checkProc.command = [root.checkScript, "--vgshell", root.vgshellPath];
                checkProc.running = true;
            } else {
                root.failedAt = Date.now();
                root.finishRefresh();
            }
        }
    }

    // Process reports exited before running becomes false, after its
    // collectors finish (quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process).
    Process {
        id: checkProc
        stdout: StdioCollector { id: checkOut }
        stderr: StdioCollector { id: checkErr }
        property var completion: null
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (done !== null && done.code === 0 && root.acceptText(checkOut.text, false)) {
                root.checkFailure = "";
                root.failedAt = -1;
            } else {
                const line = String(checkErr.text || "").split("\n").filter(l => l !== "")[0] || "no-output";
                root.checkFailure = (done === null ? "start=failed" : "exit=" + done.code) + " " + line;
                root.failedAt = Date.now();
            }
            root.finishRefresh();
        }
    }

    Timer {
        id: cadence
        repeat: false
        interval: root.currentIntervalMs
        onTriggered: {
            if (Logic.shouldRunCheck(root.snapshot, root.checking, Date.now(), root.currentIntervalMs, root.failedAt < 0 ? null : root.failedAt, root.bootedAt)) root.requestCheck("timer");
            else {
                root.publishNow();
                root.schedule();
            }
        }
    }
}
