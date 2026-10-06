import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import "VoiceLogic.js" as VoiceLogic

Item {
    id: root

    property var shell: null
    property var registeredWith: null
    property var lastStatus: ({ state: "idle", engine: "", model: "" })
    property var setupRead: ({ engine: "", model: "", models: "", engines: "", unit: "" })
    property var setupValue: ({ tone: "info", text: "Not checked", action: false, engine: VoiceLogic.DEFAULT_ENGINE, model: VoiceLogic.DEFAULT_MODEL })
    property string probeStage: "idle"
    property string pendingVerb: ""
    property string activeVerb: ""
    property var recordCompletion: null
    property string dictation: "idle"
    // Whether the service itself stopped the status follower or the bridge,
    // or is being destroyed: an exit it did not ask for is logged and acted on.
    property bool statusStopping: false
    property bool bridgeStopping: false
    property bool closing: false
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
            shell.shortcut.register("tap", "Tap to start or stop dictation", () => root.record("toggle"));
            shell.shortcut.register("talk", "Dictate while held", () => root.record("start"), () => root.record("stop"));
            shell.layers.show(osdLayer);
        }
        if (voxtypePresent) Qt.callLater(root.startStatus);
        publishPresence();
        refreshSetup();
    }
    onVoxtypePresentChanged: {
        publishPresence();
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
    onTuiStateChanged: refreshSetup()
    onBridgeWantedChanged: bridgeWanted ? startBridge() : stopBridge()

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
            setupValue = { tone: "info", text: "Install voxtype first", action: false, engine: VoiceLogic.DEFAULT_ENGINE, model: VoiceLogic.DEFAULT_MODEL, reasons: [] };
            publish("setup", root.setupStatusValue());
            publish("model", VoiceLogic.modelData(lastStatus, setupValue));
            return;
        }
        if (probeProcess.running) return;
        probeStage = "engine";
        probeProcess.command = ["voxtype", "config", "get", "engine", "--json"];
        probeProcess.running = true;
    }

    function runNextProbe(out) {
        if (probeStage === "engine") {
            setupRead = { engine: out, model: setupRead.model, models: setupRead.models, engines: setupRead.engines, unit: setupRead.unit };
            const engine = VoiceLogic.configValue(out, VoiceLogic.DEFAULT_ENGINE);
            probeStage = "model";
            probeProcess.command = ["voxtype", "config", "get", engine + ".model", "--json"];
            probeProcess.running = true;
            return;
        }
        if (probeStage === "model") {
            setupRead = { engine: setupRead.engine, model: out, models: setupRead.models, engines: setupRead.engines, unit: setupRead.unit };
            probeStage = "models";
            probeProcess.command = ["voxtype", "info", "models", "--json"];
            probeProcess.running = true;
            return;
        }
        if (probeStage === "models") {
            setupRead = { engine: setupRead.engine, model: setupRead.model, models: out, engines: setupRead.engines, unit: setupRead.unit };
            probeStage = "engines";
            probeProcess.command = ["voxtype", "info", "engines", "--json"];
            probeProcess.running = true;
            return;
        }
        if (probeStage === "engines") {
            setupRead = { engine: setupRead.engine, model: setupRead.model, models: setupRead.models, engines: out, unit: setupRead.unit };
            if (systemctlPresent) {
                probeStage = "unit";
                probeProcess.command = ["systemctl", "--user", "is-enabled", "voxtype"];
                probeProcess.running = true;
                return;
            }
            finishSetup("");
            return;
        }
        if (probeStage === "unit") finishSetup(out);
    }

    function finishSetup(unitOut) {
        probeStage = "idle";
        setupRead = { engine: setupRead.engine, model: setupRead.model, models: setupRead.models, engines: setupRead.engines, unit: unitOut };
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
            if (stage === "unit") {
                root.runNextProbe(out);
                return;
            }
            if (err !== "") console.warn("voice: probe=" + stage + " " + err);
            root.runNextProbe(out);
        }
    }
}
