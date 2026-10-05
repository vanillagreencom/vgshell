import QtQuick
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
    readonly property var missing: shell === null ? [] : shell.requirements.missing
    readonly property int requirementsRevision: shell === null ? 0 : shell.requirements.revision
    readonly property bool voxtypePresent: shell !== null && missing.indexOf("voxtype") === -1
    readonly property bool systemctlPresent: shell !== null && missing.indexOf("systemctl") === -1
    readonly property var tuiState: shell === null ? null : shell.tui.state
    readonly property bool statusRunning: statusProcess.running
    readonly property string dictationStatus: shell === null || shell.status.values.dictation === undefined ? "" : String(shell.status.values.dictation.text)
    readonly property var shortcutKeys: shell === null ? ({}) : shell.shortcut.keys

    onShellChanged: {
        if (shell === null) return;
        if (registeredWith === null) {
            registeredWith = shell;
            shell.shortcut.register("toggle", "Start or stop dictation", () => root.record("toggle"));
            shell.shortcut.register("talk", "Dictate while held", () => root.record("start"), () => root.record("stop"));
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

    function publishPresence() {
        if (shell === null) return;
        publish("voxtype", voxtypePresent ? "present" : "absent");
    }

    function publish(key, value) {
        const reply = shell.status.set(key, value);
        if (reply !== "ok") console.error("voice: status=" + key + " " + reply);
    }

    function publishDictation(state) {
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

    Process {
        id: statusProcess
        stdout: SplitParser { onRead: line => root.applyStatus(line) }
        stderr: SplitParser { onRead: line => console.warn("voice: status " + line) }
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
