import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "VoiceLogic.js" as VoiceLogic

Item {
    id: root

    property var shell: null
    property var registeredWith: null
    property var lastStatus: ({ state: "idle", engine: "", model: "" })
    // What the running probe chain has read so far, by stage, for
    // VoiceLogic.setupState.
    property var setupRead: ({})
    property var setupValue: ({ tone: "info", text: "Not checked", action: false, engine: VoiceLogic.DEFAULT_ENGINE, model: VoiceLogic.DEFAULT_MODEL })
    property string probeStage: "idle"
    property string pendingVerb: ""
    property string activeVerb: ""
    property var recordCompletion: null
    property string dictation: "idle"
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
    // Whether the service itself stopped the status follower or the bridge,
    // or is being destroyed: an exit it did not ask for is logged and acted on.
    property bool statusStopping: false
    property bool bridgeStopping: false
    property bool closing: false
    // The end time of the last Set up run this instance read, undefined
    // until its first read, so a run that ended before it started sends no
    // notification.
    property var setupSeenEnd: undefined
    // The level the on-screen display draws from the latest
    // voxtype-audio-bridge frame; zero while no bridge runs.
    property real level: 0
    readonly property var missing: shell === null ? [] : shell.requirements.missing
    readonly property int requirementsRevision: shell === null ? 0 : shell.requirements.revision
    readonly property bool voxtypePresent: shell !== null && missing.indexOf("voxtype") === -1
    readonly property bool systemctlPresent: shell !== null && missing.indexOf("systemctl") === -1
    readonly property var tuiState: shell === null ? null : shell.tui.state
    readonly property bool statusRunning: statusProcess.running
    readonly property string dictationStatus: shell === null || shell.status.values.dictation === undefined ? "" : String(shell.status.values.dictation.text)
    readonly property var shortcutKeys: shell === null ? ({}) : shell.shortcut.keys
    readonly property string osdMode: shell === null ? "off" : String(shell.settings.osd)
    // The on-screen display shows, and its levels flow, while voxtype
    // records or transcribes; a stopped daemon sends no audio.
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
            shell.shortcut.register("toggle", "Start or stop dictation", () => root.record("toggle"));
            shell.shortcut.register("tap", "Tap a key to dictate", () => root.record("toggle"));
            shell.shortcut.register("talk", "Dictate while held", () => root.record("start"), () => root.record("stop"));
            shell.layers.show(osdLayer);
            const held = shell.sounds.hold("feedback", { read: () => root.readFeedback(), choose: value => root.chooseFeedback(value) });
            if (held !== "ok") console.error("voice: sounds " + held);
            Qt.callLater(root.readFeedback);
        }
        if (voxtypePresent) Qt.callLater(root.startStatus);
        publishPresence();
        refreshSetup();
    }
    onVoxtypePresentChanged: {
        publishPresence();
        readFeedback();
        if (voxtypePresent) {
            root.startStatus();
            refreshSetup();
        } else {
            statusRestart.stop();
            statusStopping = statusProcess.running;
            statusProcess.running = false;
            publishDictation("idle");
        }
    }
    onMissingChanged: {
        publishPresence();
        refreshSetup();
    }
    onRequirementsRevisionChanged: refreshSetup()
    // Configure and Set up can each change voxtype's config.
    onTuiStateChanged: {
        noteSetupEnd();
        refreshSetup();
        readFeedback();
    }
    onBridgeWantedChanged: bridgeWanted ? startBridge() : stopBridge()

    // A Set up run that ended with code 0 since the last read sends one
    // notification naming the key the user dictates with, spelled as
    // KeyCaps spells it.
    function noteSetupEnd() {
        if (tuiState === null) return;
        const setup = tuiState.setup;
        if (VoiceLogic.setupFinished(setupSeenEnd, setup)) {
            const reply = shell.notify.send({ title: "Voice is ready", message: VoiceLogic.readyMessage(shortcutKeys, key => KeyNavLogic.keyCaps(key).join("+")), tone: "success", icon: "mic" });
            if (reply !== "ok") console.error("voice: notice " + reply);
        }
        setupSeenEnd = setup.endedAt;
    }

    function publishPresence() {
        if (shell === null) return;
        publish("voxtype", voxtypePresent ? "present" : "absent");
    }

    function publish(key, value) {
        const reply = shell.status.set(key, value);
        if (reply !== "ok") console.error("voice: status=" + key + " " + reply);
    }

    function publishDictation(state) {
        dictation = state;
        const tone = state === "recording" ? "warning" : state === "transcribing" ? "info" : state === "stopped" ? "warning" : "ok";
        publish("dictation", { tone: tone, text: state });
    }

    function setupStatusValue() {
        const value = { tone: setupValue.tone, text: setupValue.text, action: setupValue.action };
        if (setupValue.lines !== undefined && setupValue.lines.length > 0) value.lines = setupValue.lines;
        return value;
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

    function startFeedback(run) {
        feedbackRun = run;
        feedbackProcess.command = VoiceLogic.feedbackCommand(run.stage, run.wanted, configFile);
        feedbackProcess.running = true;
    }

    // The stage's command ended: CODE is its exit code, -1 when it did not
    // start or was killed.
    function stepFeedback(code, out, complaint) {
        const next = VoiceLogic.feedbackNext(feedbackRun, code, out, systemctlPresent);
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

    function startStatus() {
        if (!voxtypePresent || statusProcess.running) return;
        statusProcess.command = ["setpriv", "--pdeathsig", "TERM", "--", "voxtype", "status", "--follow", "--extended", "--format", "json"];
        statusProcess.running = true;
    }

    function applyStatus(line) {
        const parsed = VoiceLogic.parseStatus(line);
        if (!parsed.ok) {
            console.warn("voice: status=line reason=" + parsed.reason);
            return;
        }
        lastStatus = parsed;
        publishDictation(parsed.state);
        publish("model", VoiceLogic.modelData(parsed, setupValue));
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

    function record(verb) {
        if (!voxtypePresent) return "refused: voxtype=missing";
        if (recordProcess.running) {
            pendingVerb = verb;
            return "busy";
        }
        activeVerb = verb;
        recordCompletion = null;
        recordProcess.command = ["voxtype", "record", verb];
        recordProcess.running = true;
        return "ok";
    }

    function refreshSetup() {
        if (shell === null) return;
        if (!voxtypePresent) {
            setupValue = VoiceLogic.setupState({ present: false });
            publish("setup", root.setupStatusValue());
            publish("model", VoiceLogic.modelData(lastStatus, setupValue));
            return;
        }
        if (probeProcess.running) return;
        setupRead = ({ present: true });
        startProbe(VoiceLogic.PROBE_STAGES[0]);
    }

    // The command of each probe stage, VoiceLogic.PROBE_STAGES. The model's
    // key names the engine the engine stage read.
    function probeCommand(stage) {
        switch (stage) {
        case "version": return ["voxtype", "--version"];
        case "engine": return ["voxtype", "config", "get", "engine", "--json"];
        case "model": return ["voxtype", "config", "get", VoiceLogic.configValue(setupRead.engine || "", VoiceLogic.DEFAULT_ENGINE) + ".model", "--json"];
        case "models": return ["voxtype", "info", "models", "--json"];
        case "engines": return ["voxtype", "info", "engines", "--json"];
        case "unit": return ["systemctl", "--user", "is-enabled", "voxtype"];
        case "active": return ["systemctl", "--user", "is-active", "voxtype"];
        }
        throw new Error("voice: probe stage " + JSON.stringify(stage) + " is not one of " + VoiceLogic.PROBE_STAGES.join(", "));
    }

    function startProbe(stage) {
        probeStage = stage;
        probeProcess.command = probeCommand(stage);
        probeProcess.running = true;
    }

    // Each stage's stdout is kept under its name; the service's two stages
    // run only while systemctl is found, and read nothing otherwise.
    function runNextProbe(out) {
        const read = Object.assign({}, setupRead);
        read[probeStage] = out;
        setupRead = read;
        const next = VoiceLogic.PROBE_STAGES[VoiceLogic.PROBE_STAGES.indexOf(probeStage) + 1];
        if (next !== undefined && (systemctlPresent || VoiceLogic.SERVICE_STAGES.indexOf(next) === -1)) {
            startProbe(next);
            return;
        }
        probeStage = "idle";
        setupValue = VoiceLogic.setupState(setupRead);
        publish("setup", root.setupStatusValue());
        publish("model", VoiceLogic.modelData(lastStatus, setupValue));
    }

    // A follower that exits on its own, as one killed with voxtype does,
    // leaves no state to read: dictation goes idle and the follower starts
    // again.
    Process {
        id: statusProcess
        property var completion: null
        stdout: SplitParser { onRead: line => root.applyStatus(line) }
        stderr: SplitParser { onRead: line => console.warn("voice: status " + line) }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const requested = root.statusStopping || root.closing;
            const exit = completion === null ? "unstarted" : "code=" + completion.code + " status=" + completion.status;
            root.statusStopping = false;
            completion = null;
            if (requested) return;
            console.warn("voice: status exited " + exit);
            root.publishDictation("idle");
            if (root.voxtypePresent) statusRestart.start();
        }
    }

    Timer {
        id: statusRestart
        interval: 1100
        onTriggered: root.startStatus()
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
    // second spare. The status follower's restart keeps the same bound.
    Timer {
        id: bridgeRestart
        interval: 1100
        onTriggered: root.startBridge()
    }

    Component {
        id: osdLayer
        Osd { service: root }
    }

    Process {
        id: recordProcess
        stderr: StdioCollector { id: recordErr }
        onExited: (code, status) => { root.recordCompletion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            if (root.recordCompletion === null || root.recordCompletion.code !== 0 || root.recordCompletion.status !== 0)
                console.error("voice: record=" + root.activeVerb + " failed=" + JSON.stringify(root.recordCompletion) + "\n" + recordErr.text.trim());
            if (root.pendingVerb !== "") {
                const next = root.pendingVerb;
                root.pendingVerb = "";
                root.record(next);
            }
        }
    }

    // One stage of a dictation sounds run. voxtype reads its config from
    // the session's own environment, and systemctl its user bus.
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

    Process {
        id: probeProcess
        property var completion: null
        stdout: StdioCollector { id: probeOut }
        stderr: StdioCollector { id: probeErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const stage = root.probeStage;
            const out = probeOut.text;
            const err = probeErr.text.trim();
            completion = null;
            // systemctl answers a unit that is off on stderr too; that is
            // a state, not a failure.
            if (err !== "" && VoiceLogic.SERVICE_STAGES.indexOf(stage) === -1) console.warn("voice: probe=" + stage + " " + err);
            root.runNextProbe(out);
        }
    }
}
