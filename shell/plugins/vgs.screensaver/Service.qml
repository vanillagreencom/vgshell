import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "ScreensaverLogic.js" as Logic

// The screensaver's service. The core's cover presentation (capability
// `cover`) runs the cover on every screen; this service starts it on
// demand and from its screensaver stage watch, ends it on input, and
// publishes its state. While the lock holds it, only the lock's first
// input ends it.
Item {
    id: root

    property var shell: null
    property var registeredWith: null
    property var idleDisposer: null
    property var activityDisposer: null
    readonly property bool running: shell !== null && shell.cover.running
    property bool effectFailed: false
    property var published: ({})
    property string artInUse: ""
    property string artProblem: ""
    property bool convertAgain: false
    property bool convertTimedOut: false
    property bool convertCancelled: false

    readonly property bool locked: shell !== null && shell.session.locked
    readonly property bool displaysOff: shell !== null && shell.session.displaysOff
    readonly property bool idleEnabled: shell !== null && shell.settings.idleEnabled === true
    readonly property int idleSeconds: shell === null ? 150 : shell.settings.idleSeconds
    readonly property int requirementsRevision: shell === null ? 0 : shell.requirements.revision
    readonly property string art: shell === null || shell.settings.art === undefined ? "" : shell.settings.art
    readonly property string convertedArt: Paths.stateDir + "/screensaver-art.txt"
    readonly property string legacyArt: Paths.configDir + "/screensaver.txt"
    readonly property string movedArt: Paths.configDir + "/screensaver-art.txt"
    readonly property var stages: shell === null ? [] : shell.idle.stages
    // The screensaver stage's owner in the core's record: the watch is
    // taken again when this plugin becomes the owner or stops being it.
    readonly property string stageOwner: {
        const row = stages.find(stage => stage.stage === "screensaver");
        return row === undefined ? "" : row.plugin;
    }

    onShellChanged: {
        if (shell === null) return;
        if (registeredWith === null) {
            registeredWith = shell;
            if (art === "") artMigration.running = true;
            shell.shortcut.register("start", "Start the screensaver", () => root.start());
            shell.ipc.handle("start", () => root.start());
            shell.ipc.handle("stop", () => root.stop());
            shell.ipc.handle("effect-failed", () => root.failEffect());
            shell.ipc.handle("status", () => root.statusJson());
        }
        publish("effects", [{ label: "Random", value: "random" }]);
        refreshEffects();
        watchIdle();
        publishAll();
    }
    onIdleEnabledChanged: { watchIdle(); publishLockOrder(); }
    onIdleSecondsChanged: { watchIdle(); publishLockOrder(); }
    onRequirementsRevisionChanged: {
        refreshEffects();
        if (Logic.retryArtAfterScan(art, artProblem) && !artConvert.running) Qt.callLater(root.updateArt);
    }
    onRunningChanged: { publishState(); watchActivity(); }
    onArtChanged: updateArt()
    onArtProblemChanged: publishArt()
    onArtInUseChanged: publishArtFile()
    onStagesChanged: publishLockOrder()
    onStageOwnerChanged: watchIdle()
    Component.onDestruction: stopArtConversion(false)

    // `ok`, or the core's refusal: `refused: cover=locked` and
    // `refused: cover=displays-off` among them. TICKET, from the stage
    // watch, makes it an idle start.
    function start(ticket) {
        if (shell === null) return "refused: screensaver=not-ready";
        const reply = ticket === undefined ? shell.cover.present() : shell.cover.present(ticket);
        if (reply === "ok" && effectFailed) {
            effectFailed = false;
            publishState();
        }
        return reply;
    }

    function stop() {
        return shell === null ? "ok" : shell.cover.stop();
    }

    function turnedOff() {
        stop();
        stopArtConversion(false);
    }

    function failEffect() {
        effectFailed = true;
        if (shell !== null) shell.cover.failed();
        publishState();
        return "ok";
    }

    function updateArt() {
        if (shell === null) return;
        if (artConvert.running) {
            stopArtConversion(true);
            return;
        }
        convertAgain = false;
        convertTimedOut = false;
        if (art === "") {
            textArt.path = "";
            settleArt("", "");
            return;
        }
        if (!Logic.isArtImage(art)) {
            textArt.path = art;
            return;
        }
        textArt.path = "";
        // Handlers can run before a dependent binding updates, so read the current requirements in place.
        const requirementProblem = Logic.imageRequirementProblem(shell.requirements.missing);
        if (requirementProblem !== "") {
            settleArt(convertedArt, requirementProblem);
            return;
        }
        artProblem = "";
        convertCancelled = false;
        publishArt();
        artConvert.command = [Logic.fileUrlPath(Qt.resolvedUrl("bin/transcode-ascii")), art, convertedArt];
        artConvert.running = true;
    }

    function stopArtConversion(restart) {
        if (artConvert.running) {
            convertAgain = restart;
            convertCancelled = !restart && !convertTimedOut;
            // Setting `running` to false sends SIGTERM (Quickshell 0.3.1,
            // Process.running; shell/Core/Sounds.qml). The helper's own
            // per-fork parent-death signals end its children if this
            // service is removed.
            artConvert.running = false;
        } else if (restart) {
            Qt.callLater(root.updateArt);
        }
    }

    function settleArt(next, problem) {
        const result = Logic.artResult(artInUse, next, problem);
        artInUse = result.inUse;
        artProblem = result.problem;
    }

    function textArtLoaded(path, content) {
        if (path !== art || Logic.isArtImage(art) || art === "") return;
        settleArt(path, Logic.textArtProblem(content));
    }

    function textArtFailed(path, error) {
        if (path !== art || Logic.isArtImage(art) || art === "") return;
        settleArt(path, "file");
    }

    function migratedArt() {
        if (shell === null) return;
        const reply = shell.configure.set("art", movedArt);
        if (reply !== "ok") console.warn("screensaver: art migration " + reply);
    }

    // The screensaver stage watch, taken again when its settings change;
    // the core holds no watch while the stage is off, and refuses one while
    // another plugin owns the stage.
    function watchIdle() {
        if (idleDisposer !== null) idleDisposer();
        idleDisposer = null;
        if (shell === null) return;
        try {
            idleDisposer = shell.idle.watchStage("screensaver", (idle, ticket) => {
                if (idle) root.start(ticket);
                else root.stop();
            });
        } catch (e) {
            console.info("screensaver: idle watch " + e.message);
        }
    }

    function watchActivity() {
        if (activityDisposer !== null) activityDisposer();
        activityDisposer = null;
        if (shell === null || !running) return;
        activityDisposer = shell.idle.watch(1, idle => {
            if (!idle && root.running) root.stop();
        });
    }

    function statusJson() {
        return JSON.stringify({ running: running, placement: shell === null ? "none" : shell.cover.placement, idleEnabled: idleEnabled, idleSeconds: idleSeconds, locked: locked, displaysOff: displaysOff });
    }

    function publish(key, value) {
        if (shell === null) return;
        const text = JSON.stringify(value);
        if (published[key] === text) return;
        const reply = shell.status.set(key, value);
        if (reply !== "ok") {
            console.warn("screensaver: status " + reply);
            return;
        }
        const next = Object.assign({}, published);
        next[key] = text;
        published = next;
    }

    function publishAll() {
        publishState();
        publishArt();
        publishArtFile();
        publishLockOrder();
    }

    function publishState() {
        publish("state", effectFailed ? { tone: "warning", text: "Effect failed" } : running ? { tone: "info", text: "Running" } : { tone: "ok", text: "Off" });
    }

    function publishArt() {
        publish("art", Logic.artStatus(artProblem));
    }

    function publishArtFile() {
        publish("artFile", artInUse);
    }

    function publishLockOrder() {
        if (shell === null) return;
        const stages = shell.idle.stages;
        const lock = stages.find(row => row.stage === "lock");
        const screensaver = stages.find(row => row.stage === "screensaver");
        if (lock === undefined) {
            publish("lockOrder", null);
            return;
        }
        const seconds = lock.seconds;
        if (seconds <= 0) {
            publish("lockOrder", { tone: "warning", text: "Lock is off" });
            return;
        }
        if (screensaver === undefined || screensaver.seconds === 0) {
            publish("lockOrder", { tone: "info", text: "Idle start is off" });
            return;
        }
        // The core owns stage order; equal times are not a before verdict.
        publish("lockOrder", { tone: lock.before.includes("screensaver") ? "warning" : "ok", text: "Lock follows at " + seconds + " s" });
    }

    function refreshEffects() {
        // Handlers can run before a dependent binding updates, so read the current requirements in place.
        if (shell === null || effectsHelp.running || !Logic.ttfxReady(shell.requirements.missing)) return;
        effectsHelp.running = true;
    }

    FileView {
        id: textArt
        path: ""
        watchChanges: true
        printErrors: false
        onLoaded: root.textArtLoaded(path, text())
        onLoadFailed: error => root.textArtFailed(path, error)
        onFileChanged: reload()
    }

    Process {
        id: artConvert
        stderr: SplitParser { onRead: line => console.warn("screensaver: " + line) }
        onExited: code => {
            if (root.convertAgain) {
                root.convertAgain = false;
                root.convertTimedOut = false;
                root.convertCancelled = false;
                Qt.callLater(root.updateArt);
                return;
            }
            if (root.convertCancelled) {
                root.convertCancelled = false;
                return;
            }
            const problem = Logic.conversionProblem(code, root.convertTimedOut);
            root.convertTimedOut = false;
            root.settleArt(root.convertedArt, problem);
        }
    }

    Timer {
        // `transcode-ascii` converted a 6000x4000 plasma:fractal PNG
        // (122 MB) in 2.5 s wall on host cachy (32 CPUs, load ~6) on
        // 2026-10-12 with `time`; 20 s is 8x that reading.
        interval: Logic.CONVERT_LIMIT_MS
        running: artConvert.running
        onTriggered: {
            root.convertTimedOut = true;
            root.stopArtConversion(false);
        }
    }

    // D107: art made before the Art setting sat in screensaver.txt. Move it
    // once into a text file the setting names.
    Process {
        id: artMigration
        command: ["mv", "-n", "--", root.legacyArt, root.movedArt]
        onExited: code => {
            if (code === 0) migrationCheck.path = root.legacyArt;
        }
    }

    FileView {
        id: migrationCheck
        path: ""
        printErrors: false
        onLoaded: migrationCheck.path = ""
        onLoadFailed: error => {
            // coreutils 9.5+ `mv -n` exits 0 when the target exists and it
            // skips the move, while 9.2-9.4 exit 1, so the old path decides.
            if (error === FileViewError.FileNotFound) root.migratedArt();
            migrationCheck.path = "";
        }
    }

    Process {
        id: effectsHelp
        command: ["ttfx", "--help"]
        stdout: StdioCollector { id: effectsOut; waitForEnd: true }
        onExited: code => {
            if (code === 0) root.publish("effects", Logic.effectChoices(effectsOut.text));
        }
    }
}
