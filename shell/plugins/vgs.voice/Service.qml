import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "VoiceLogic.js" as VoiceLogic

Item {
    id: root

    property var shell: null
    property var registeredWith: null
    property var setupValue: ({ tone: "info", text: "Not checked", action: "", engine: VoiceLogic.DEFAULT_ENGINE, model: VoiceLogic.DEFAULT_MODEL })
    // The core's one recording and its voxtype daemon, as the `dictation`
    // capability lends them (D106): a new copy after each change.
    readonly property var dictationState: shell === null ? null : shell.dictation.state
    // What Voice shows of it, VoiceLogic.ownDictation: its own recording's
    // phase, `idle` during another holder's.
    property string dictation: "idle"
    property bool ownDictation: false
    // A refused busy start waits for the core's fresh engine read. If
    // that read fails, the existing Setup page gives the correction.
    property bool recoveryRequested: false
    // The capability's word for the daemon, "" before the first read. Set
    // up's state reads it.
    readonly property string daemon: dictationState === null ? "" : dictationState.daemon
    property string modelShown: ""
    // The dictation sounds run in flight (VoiceLogic.feedbackRun), null
    // while none runs; the Sounds page's choice that waits for it to end,
    // undefined for none; and what the last run read and ended with, a
    // value of the sound event and a key of VoiceLogic.FEEDBACK_PROBLEMS.
    property var feedbackRun: null
    property var feedbackWaiting: undefined
    property string feedbackDetail: ""
    property var feedbackValue: null
    property string feedbackProblem: ""
    readonly property string configFile: Paths.configHome + "/voxtype/config.toml"
    // Whether the service itself stopped the bridge, or is being
    // destroyed: an exit it did not ask for is logged and acted on.
    property bool bridgeStopping: false
    property bool closing: false
    // The end time of the last run of each of VoiceLogic.RESTART_TUIS this
    // instance read, undefined until its first read, so a run that ended
    // before it started restarts nothing.
    property var restartSeenEnds: undefined
    // The level the on-screen display draws from the latest
    // voxtype-audio-bridge frame; zero while no bridge runs.
    property real level: 0
    readonly property var missing: shell === null ? [] : shell.requirements.missing
    readonly property int requirementsRevision: shell === null ? 0 : shell.requirements.revision
    readonly property bool voxtypePresent: shell !== null && missing.indexOf("voxtype") === -1
    readonly property var tuiState: shell === null ? null : shell.tui.state
    readonly property string dictationStatus: shell === null || shell.status.values.dictation === undefined ? "" : String(shell.status.values.dictation.text)
    readonly property var shortcutKeys: shell === null ? ({}) : shell.shortcut.keys
    readonly property string osdMode: shell === null ? "off" : String(shell.settings.osd)
    // The on-screen display shows, and its levels flow, while voxtype
    // records or transcribes Voice's own dictation.
    readonly property bool osdActive: osdMode !== "off" && (dictation === "recording" || dictation === "transcribing")
    readonly property string focusedOutput: Hyprland.focusedMonitor === null ? "" : Hyprland.focusedMonitor.name
    readonly property bool bridgePresent: shell !== null && missing.indexOf("voxtype-audio-bridge") === -1
    readonly property bool bridgeWanted: osdActive && bridgePresent

    // Each bridge frame's level, which the plasma orb eases towards, and
    // the bridge's disconnected line, which resets the orb.
    signal frame(real level)
    signal bridgeDisconnected()

    Component.onDestruction: closing = true

    onShellChanged: {
        if (shell === null) return;
        if (registeredWith === null) {
            registeredWith = shell;
            shell.shortcut.register("toggle", "Start or stop dictation", root.toggle);
            shell.shortcut.register("tap", "Tap a key to dictate", root.toggle);
            shell.ipc.handle("toggle", root.toggle);
            shell.shortcut.register("talk", "Dictate while held", root.start, root.stop);
            shell.layers.show(osdLayer);
            const held = shell.sounds.hold("feedback", { read: () => root.readFeedback(), choose: value => root.chooseFeedback(value) });
            if (held !== "ok") console.error("voice: sounds " + held);
            Qt.callLater(root.readFeedback);
        }
    }
    // The core's daemon failed to start while voxtype was missing; once it
    // is found, the core starts one.
    onVoxtypePresentChanged: {
        readFeedback();
        if (voxtypePresent && daemon === "failed") restartDaemon();
        refreshSetup();
    }
    onDictationStateChanged: applyDictation()
    // Also the first read of Set up's state, when the shell arrives. A
    // daemon that starts again, as after the core's dictation setup, may
    // find a model that setup downloaded.
    onDaemonChanged: refreshSetup()
    onMissingChanged: refreshSetup()
    onRequirementsRevisionChanged: refreshSetup()
    // Configure and Choose model can each change voxtype's config, and
    // Stop the other voxtype frees the place the core's daemon takes.
    onTuiStateChanged: {
        noteRestartEnds();
        refreshSetup();
        readFeedback();
    }
    onBridgeWantedChanged: bridgeWanted ? startBridge() : stopBridge()

    // A run of one of VoiceLogic.RESTART_TUIS that ended with code 0 since
    // the last read has the core start its daemon again, which probes for
    // another daemon and reads the config the run left.
    function noteRestartEnds() {
        if (tuiState === null) return;
        const ends = {};
        let finished = false;
        for (const name of VoiceLogic.RESTART_TUIS) {
            if (VoiceLogic.runFinished(restartSeenEnds === undefined ? undefined : restartSeenEnds[name], tuiState[name])) finished = true;
            ends[name] = tuiState[name].endedAt;
        }
        restartSeenEnds = ends;
        if (finished) restartDaemon();
    }

    // A restart the capability refuses, as during a recording, is logged:
    // the daemon then reads the config when it next starts.
    function restartDaemon() {
        const answer = shell.dictation.restart();
        if (answer !== "ok") console.warn("voice: restart " + answer);
        return answer;
    }

    // The capability's state changed: the dictation Voice shows and the
    // Model row.
    function applyDictation() {
        if (dictationState === null) return;
        const shown = VoiceLogic.ownDictation(dictationState, ownDictation);
        ownDictation = shown.own;
        if (shown.phase !== dictation) publishDictation(shown.phase);
        publishModel();
        refreshSetup();
        if (recoveryRequested && (dictationState.daemon === "failed" || dictationState.phase === "idle")) {
            recoveryRequested = false;
            if (dictationState.daemon === "failed") shell.surfaces.openPage(VoiceLogic.HOLDER, "Setup");
        }
    }

    // The core retires a disabled plugin's status record, then lets go of
    // its daemon: the capability's state moves once more under the
    // instance, whose write is then refused as retired.
    function publish(key, value) {
        const reply = shell.status.set(key, value);
        if (reply !== "ok" && !reply.endsWith(" reason=retired")) console.error("voice: status=" + key + " " + reply);
    }

    function publishDictation(state) {
        dictation = state;
        const tone = state === "recording" ? "warning" : state === "transcribing" ? "info" : "ok";
        publish("dictation", { tone: tone, text: state });
    }

    function publishModel() {
        const value = VoiceLogic.modelData(dictationState, setupValue);
        const text = JSON.stringify(value);
        if (text === modelShown) return;
        modelShown = text;
        publish("model", value);
    }

    // The required step stays visible. The other service's Stop action
    // belongs beside its fact on Details.
    function publishSetup() {
        publish("setup", VoiceLogic.setupPublished(setupValue));
        publish("otherService", setupValue.action === "stop"
            ? { tone: "warning", text: "Another voxtype runs", action: true }
            : { tone: "ok", text: "No other service to stop", action: false });
        publishModel();
    }

    // Read the dictation sounds value again and state it to the Sounds
    // page, once this instance holds the event. A run in flight ends with
    // what it read.
    function readFeedback() {
        if (registeredWith === null || closing) return;
        if (!voxtypePresent) stateFeedback(null, "missing");
        else if (feedbackRun === null) startFeedback(VoiceLogic.feedbackRun(null));
    }

    // The Sounds page's choice. Only its Off and its Dictation tones start
    // a run, and only while voxtype is found; a choice made while a run is
    // in flight waits for it, the latest one alone. The row shows the
    // choice while the run applies it, then what the run read back.
    function chooseFeedback(value) {
        if (value !== VoiceLogic.FEEDBACK_ON && value !== VoiceLogic.FEEDBACK_OFF) return "refused: feedback=" + JSON.stringify(value) + " reason=value";
        if (!voxtypePresent) return "refused: feedback=" + JSON.stringify(value) + " reason=voxtype-missing";
        if (feedbackRun === null) startFeedback(VoiceLogic.feedbackRun(value));
        else feedbackWaiting = value;
        stateFeedback(value, "");
        return "ok";
    }

    // The restart stage runs no command: the core starts its daemon again,
    // and its answer is the stage's end.
    function startFeedback(run) {
        feedbackRun = run;
        const command = VoiceLogic.feedbackCommand(run.stage, run.wanted, configFile);
        if (command === null) {
            const answer = shell.dictation.restart();
            stepFeedback(answer === "ok" ? 0 : 1, "", answer);
            return;
        }
        feedbackProcess.command = command;
        feedbackProcess.running = true;
    }

    // The stage ended: CODE is its command's exit code, -1 when it did not
    // start or was killed.
    function stepFeedback(code, out, complaint) {
        const next = VoiceLogic.feedbackNext(feedbackRun, code, out);
        if (next.problem !== feedbackRun.problem)
            feedbackDetail = "stage=" + feedbackRun.stage + " exit=" + code + " " + complaint.split("\n")[0].slice(0, 200);
        if (next.stage !== "done") {
            startFeedback(next);
            return;
        }
        if (next.problem !== "") console.warn("voice: feedback wanted=" + JSON.stringify(next.wanted) + " problem=" + next.problem + " " + feedbackDetail);
        feedbackRun = null;
        feedbackDetail = "";
        stateFeedback(next.value, next.problem);
        const waiting = feedbackWaiting;
        feedbackWaiting = undefined;
        if (waiting !== undefined && voxtypePresent) {
            startFeedback(VoiceLogic.feedbackRun(waiting));
            stateFeedback(waiting, "");
        }
    }

    function stateFeedback(value, problem) {
        feedbackValue = value;
        feedbackProblem = problem;
        const reply = shell.sounds.report("feedback", value, VoiceLogic.FEEDBACK_PROBLEMS[problem]);
        if (reply !== "ok") console.error("voice: sounds " + reply);
    }

    // A bridge still exiting from a stop starts again from its exit, at once.
    // The bridge logs through tracing: warnings only, without colour codes.
    function startBridge() {
        if (!bridgeWanted || bridgeProcess.running) return;
        bridgeProcess.command = ["setpriv", "--pdeathsig", "TERM", "--", "env", "RUST_LOG=warn", "NO_COLOR=1", "voxtype-audio-bridge"];
        bridgeProcess.running = true;
    }

    function stopBridge() {
        bridgeRestart.stop();
        bridgeStopping = bridgeProcess.running;
        bridgeProcess.running = false;
        level = 0;
    }

    function applyFrame(line) {
        const parsed = VoiceLogic.parseFrame(line);
        if (!parsed.ok) {
            console.warn("voice: bridge=line reason=" + parsed.reason);
            return;
        }
        if (parsed.kind === "disconnected") {
            level = 0;
            bridgeDisconnected();
        }
        if (parsed.kind !== "frame") return;
        level = VoiceLogic.frameLevel(parsed.peak, parsed.rms);
        frame(level);
    }

    // The one start or stop of dictation: the toggle key, the tap key and
    // the bar widget's click, which asks through the ipc handler, each run
    // this function, so a change to it reaches all three. It starts while
    // no recording of Voice's own runs, and stops that one otherwise.
    function toggle() {
        if (!voxtypePresent) return "refused: voxtype=missing";
        return dictationState.holder === VoiceLogic.HOLDER ? stop() : start();
    }

    // The recording is the core's, in mode `type`, which sends the words
    // to voxtype's configured output. A refusal, as during another
    // plugin's recording or while the daemon is not ready, is logged.
    // A daemon refusal opens the existing correction without starting it.
    function start() {
        const answer = shell.dictation.start("type");
        recoveryRequested = answer.indexOf("refused: dictation=engine-busy state=") === 0;
        if (answer !== "ok") console.warn("voice: start " + answer);
        if (answer === "refused: dictation=daemon-failed" || answer === "refused: dictation=daemon-absent" || answer === "refused: dictation=daemon-elsewhere" || answer === "refused: dictation=daemon-starting") {
            refreshSetup();
            shell.surfaces.openPage(VoiceLogic.HOLDER, setupValue.action === "stop" ? "Details" : "Setup");
        }
        return answer;
    }

    function stop() {
        const answer = shell.dictation.stop();
        if (answer !== "ok") console.warn("voice: stop " + answer);
        return answer;
    }

    function refreshSetup() {
        if (dictationState === null) return;
        if (!voxtypePresent) {
            setupValue = VoiceLogic.setupState({ present: false }, daemon);
            publishSetup();
            return;
        }
        setupValue = VoiceLogic.setupState(dictationState.setup, daemon);
        publishSetup();
    }

    Process {
        id: bridgeProcess
        property var completion: null
        stdout: SplitParser { onRead: line => root.applyFrame(line) }
        stderr: SplitParser { onRead: line => console.warn("voice: bridge " + line) }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const requested = root.bridgeStopping || root.closing;
            const exit = completion === null ? "unstarted" : "code=" + completion.code + " status=" + completion.status;
            root.bridgeStopping = false;
            completion = null;
            root.level = 0;
            if (!requested) console.warn("voice: bridge exited " + exit);
            if (!root.bridgeWanted) return;
            if (requested) root.startBridge();
            else bridgeRestart.start();
        }
    }

    // A bridge that exits on its own while it is still wanted starts again
    // a second or more later, so one that cannot reach voxtype's audio
    // socket does not spin. A Timer is not exact: with a 1000 ms interval
    // the voice smoke row read a restart 994 ms after it killed the bridge,
    // on host cachy on 2026-10-05, so the interval keeps a tenth of a
    // second spare.
    Timer {
        id: bridgeRestart
        interval: 1100
        onTriggered: root.startBridge()
    }

    Component {
        id: osdLayer
        Osd { service: root }
    }

    // One stage of a dictation sounds run. voxtype reads its config from
    // the session's own environment.
    Process {
        id: feedbackProcess
        property var completion: null
        stdout: StdioCollector { id: feedbackOut }
        stderr: StdioCollector { id: feedbackErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running || root.closing) return;
            const code = completion === null || completion.status !== 0 ? -1 : completion.code;
            completion = null;
            root.stepFeedback(code, feedbackOut.text, feedbackErr.text.trim());
        }
    }

}
