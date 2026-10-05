import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons

// One service owns the worker, every IPC and shortcut, and all status writes.
// The worker's stdin carries recording stop; its lifetime owns every tool.
// A probe worker reads the offered devices and missing languages for status.
Item {
    id: root
    property var shell: null
    property bool registered: false
    property string phase: "idle"
    property string action: ""
    property string lastPath: ""
    property var jobs: []
    property var activeJob: null
    property int remaining: 0
    property var countdownToast: null
    property var waitingWindows: []
    property var waitingMonitors: []
    readonly property var settings: shell === null ? ({}) : shell.settings
    readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("helper/capture.py")).replace(/^file:\/\//, ""))
    readonly property var outputs: shell === null ? null : shell.monitors.outputs
    readonly property var missing: shell === null ? [] : shell.requirements.missing
    readonly property string ocrLanguages: shell === null ? "" : shell.settings.ocrLanguages
    readonly property var languagesInstalled: shell === null || shell.tui.state["install-languages"] === undefined ? null : shell.tui.state["install-languages"].endedAt
    readonly property var tools: ({
        "screenshot": ["grim"],
        "screenshot-area": ["grim", "slurp", "hyprpicker"],
        "screenshot-window": ["grim", "slurp", "hyprpicker"],
        "screenshot-display": ["grim", "slurp", "hyprpicker"],
        "screenshot-all": ["grim"],
        "record": ["grim", "slurp", "hyprpicker", "gpu-screen-recorder", "ffmpeg", "wl-copy"],
        "record-window": ["grim", "slurp", "hyprpicker", "gpu-screen-recorder", "ffmpeg", "wl-copy"],
        "record-display": ["grim", "slurp", "hyprpicker", "gpu-screen-recorder", "ffmpeg", "wl-copy"],
        "record-output": ["gpu-screen-recorder", "ffmpeg", "wl-copy"],
        "record-portal": ["gpu-screen-recorder", "ffmpeg", "wl-copy"],
        "text": ["slurp", "hyprpicker", "grim", "tesseract", "wl-copy"]
    })
    readonly property var descriptions: ({
        "screenshot": "Capture the focused output",
        "screenshot-area": "Capture an area",
        "screenshot-window": "Capture a window",
        "screenshot-display": "Choose a display to capture",
        "screenshot-all": "Capture all displays",
        "record": "Start or stop recording an area",
        "record-window": "Start or stop recording a window",
        "record-display": "Start or stop recording a chosen display",
        "record-output": "Start or stop recording the focused display",
        "record-portal": "Start or stop recording what the screen picker shares",
        "text": "Copy text from an area",
        "toggle": "Open or close Capture"
    })

    onShellChanged: { start(); publish(); }
    onMissingChanged: { publish(); probe(); }
    onOcrLanguagesChanged: probe()
    onLanguagesInstalledChanged: probe()

    function start() {
        if (shell === null || registered) return;
        registered = true;
        for (const name of Object.keys(descriptions)) {
            shell.ipc.handle(name, () => root.invoke(name));
            shell.shortcut.register(name, descriptions[name], () => root.invoke(name));
        }
        shell.ipc.handle("setting", arg => root.setFromRequest(arg));
        publish();
        probe();
    }

    function isRecord(name) { return name.indexOf("record") === 0; }

    // The worker answers one probe line; a request during a run reruns it.
    function probe() {
        if (shell === null) return;
        if (prober.running) {
            prober.again = true;
            return;
        }
        prober.command = ["python3", helperPath, JSON.stringify({ action: "probe", ocrLanguages: shell.settings.ocrLanguages })];
        prober.running = true;
    }

    function probed(line) {
        let event;
        try { event = JSON.parse(line); } catch (error) { return; }
        if (event.event !== "probe") return;
        if (event.devices.error === undefined) {
            shell.status.set("audioSources", event.devices.audioSources);
            shell.status.set("cameras", event.devices.cameras);
        }
        const report = event.languages;
        shell.status.set("languages", report.missing === undefined
            ? { tone: "danger", text: report.invalid ? "The language list is not valid" : "Installed languages could not be read" }
            : report.missing.length > 0
            ? { tone: "warning", text: ("Missing: " + report.missing.join(", ")).slice(0, 200), action: true }
            : { tone: "info", text: "Ready" });
    }

    // Widgets and panels use this state rather than probing tools or processes.
    function publish() {
        if (shell === null) return;
        const available = {};
        for (const name of Object.keys(tools)) available[name] = requiredTools(name).every(tool => missing.indexOf(tool) < 0);
        shell.status.set("capture", { phase: phase, action: action, path: lastPath, remaining: remaining, available: available });
        const recording = phase === "recording" || phase === "stopping";
        const needed = requiredTools("record").filter(tool => missing.indexOf(tool) >= 0);
        shell.status.set("recording", { tone: recording ? "warning" : "info", text: phase === "stopping" ? "Saving recording" : recording ? "Recording" : available.record ? "Ready" : "Unavailable: recording needs " + needed.join(", ") });
    }

    function requiredTools(name) {
        const required = tools[name];
        if (name.indexOf("screenshot") === 0 && shell.settings.processing !== "save") return required.concat(["wl-copy"]);
        // The worker asks PipeWire for the camera, and for the first offered
        // source of an empty audio source.
        if (isRecord(name) && (shell.settings.webcam || shell.settings.audioSources.some(item => item.source === ""))) return required.concat(["pw-dump"]);
        return required;
    }

    function setFromRequest(arg) {
        let request;
        try { request = JSON.parse(arg); } catch (error) { return "refused: setting=unparsed"; }
        if (request === null || typeof request !== "object" || !Object.prototype.hasOwnProperty.call(request, "key") || !Object.prototype.hasOwnProperty.call(request, "value")) return "refused: setting=malformed";
        return shell.configure.set(request.key, request.value);
    }

    function invoke(name) {
        if (name === "toggle") return shell.surfaces.toggle("panel", "{}");
        if (isRecord(name) && tools[name] !== undefined && phase === "recording") {
            phase = "stopping";
            activeJob.write("stop\n");
            publish();
            return "ok";
        }
        if ((phase === "capturing" || phase === "delaying") && action === name) {
            if (activeJob === null) {
                windowDeadline.stop();
                waitingWindows = [];
                waitingMonitors = [];
                phase = "idle";
                action = "";
                publish();
                return "ok";
            }
            activeJob.write("cancel\n");
            return "ok";
        }
        if (phase !== "idle") return "refused: capture=busy";
        if (tools[name] === undefined) return "refused: capture=action";
        const needed = requiredTools(name).filter(tool => missing.indexOf(tool) >= 0);
        if (needed.length > 0) {
            shell.requirements.offer(needed);
            return "refused: capture=missing " + needed.join(",");
        }
        let output = "";
        if (name === "screenshot" || name === "record-output") {
            const focused = Hyprland.focusedMonitor;
            const found = focused === null || outputs === null ? null : outputs.find(item => item.name === focused.name && !item.disabled);
            if (found === null || found === undefined) return "refused: capture=output-unavailable";
            output = found.name;
        }
        phase = "capturing";
        action = name;
        if (name === "screenshot-window" || name === "record-window" || ((name === "screenshot-area" || name === "record") && shell.settings.smart)) {
            waitingWindows = Hyprland.toplevels.values.filter(t => t.address !== "").map(t => t.address);
            waitingMonitors = Hyprland.monitors.values.map(m => m.name);
            if (waitingWindows.length > 0 || waitingMonitors.length > 0) {
                windowDeadline.restart();
                Hyprland.refreshMonitors();
                Hyprland.refreshToplevels();
                publish();
                return "ok";
            }
        }
        return launch(name, output);
    }

    function windowRead(address) {
        if (!windowDeadline.running) return;
        waitingWindows = waitingWindows.filter(value => value !== address && Hyprland.toplevels.values.some(t => t.address === value));
        selectionReady();
    }

    function monitorRead(name) {
        if (!windowDeadline.running) return;
        waitingMonitors = waitingMonitors.filter(value => value !== name && Hyprland.monitors.values.some(m => m.name === value));
        selectionReady();
    }

    function selectionReady() {
        if (waitingWindows.length > 0 || waitingMonitors.length > 0) return;
        windowDeadline.stop();
        launch(action, "");
    }

    function windowRectangles() {
        const monitors = Hyprland.monitors.values.map(m => m.lastIpcObject).filter(m => m !== null);
        return Hyprland.toplevels.values.map(t => t.lastIpcObject).filter(window => window !== null && window.mapped && !window.hidden && shell.compositor.onScreen(window, monitors) && window.size[0] > 0 && window.size[1] > 0).map(window => ({ x: window.at[0], y: window.at[1], width: window.size[0], height: window.size[1], address: window.address, focus: window.focusHistoryID }));
    }

    function outputRectangles() {
        return outputs === null ? [] : outputs.filter(output => !output.disabled).map(output => ({ name: output.name, x: output.x, y: output.y, width: output.width, height: output.height, scale: output.scale, transform: output.transform }));
    }

    function launch(name, output) {
        const selection = ["screenshot-area", "screenshot-window", "screenshot-display", "record", "record-window", "record-display"].indexOf(name) >= 0;
        const focused = selection ? Hyprland.activeToplevel : null;
        const s = shell.settings;
        const request = { action: name, output: output, folder: s.folder, recordFolder: s.recordFolder, audio: s.audio, smart: s.smart, delay: s.delay, cursor: s.cursor, processing: s.processing, timeout: s.timeout,
            quality: s.quality, frameRate: s.frameRate, codec: s.codec, constantFrameRate: s.constantFrameRate, recordCursor: s.recordCursor, audioSources: s.audioSources, webcam: s.webcam, webcamDevice: s.webcamDevice,
            postProcess: s.postProcess, ocrLanguages: s.ocrLanguages, stateDir: Paths.stateDir, windows: selection ? windowRectangles() : [], outputs: outputRectangles() };
        const job = workerComponent.createObject(root, { actionName: name, focusAddress: focused === null ? "" : focused.address, command: ["python3", helperPath, JSON.stringify(request)] });
        if (job === null) {
            phase = "idle";
            action = "";
            notice("Capture failed", "The capture worker could not start", "danger");
            publish();
            return "refused: capture=worker-unavailable";
        }
        jobs = jobs.concat([job]);
        activeJob = job;
        job.armed = true;
        job.running = true;
        publish();
        return "ok";
    }

    function finishAction(job) {
        if (activeJob !== job) return;
        activeJob = null;
        clearCountdown();
        phase = "idle";
        action = "";
    }

    function restoreFocus(job) {
        const address = job.focusAddress;
        job.focusAddress = "";
        if (address !== "" && Hyprland.toplevels.values.some(t => t.address === address) && (Hyprland.activeToplevel === null || Hyprland.activeToplevel.address !== address)) shell.compositor.focusWindow("0x" + address);
    }

    function clearCountdown() {
        if (countdownToast !== null) countdownToast();
        countdownToast = null;
        remaining = 0;
    }

    function accept(job, line) {
        let event;
        try { event = JSON.parse(line); } catch (error) { notice("Capture failed", "The capture tool returned an invalid answer", "danger"); return; }
        switch (event.event) {
        case "selection-ended":
            restoreFocus(job);
            break;
        case "countdown":
            clearCountdown();
            remaining = event.remaining;
            if (remaining > 0) {
                phase = "delaying";
                countdownToast = shell.toasts.show({ title: "Screenshot in " + remaining + " seconds", message: "Press the capture key again or click Capture to cancel.", duration: 0, icon: "camera" });
            } else {
                phase = "capturing";
                Qt.callLater(() => Qt.callLater(() => { if (root.activeJob === job) job.write("countdown-hidden\n"); }));
            }
            break;
        case "recording":
            phase = "recording";
            lastPath = event.path;
            break;
        case "stopped":
            // Post-processing continues in this worker; the next capture can start.
            lastPath = event.path;
            finishAction(job);
            break;
        case "saved":
            job.answered = true;
            lastPath = event.path;
            savedNotice(job, event);
            finishAction(job);
            break;
        case "copied":
            job.answered = true;
            notice(job.actionName === "text" ? "Text copied" : "Screenshot copied", job.actionName === "text" ? "Text from the selected area is on the clipboard" : "The screenshot is on the clipboard", "success");
            finishAction(job);
            break;
        case "cancelled":
            job.answered = true;
            finishAction(job);
            break;
        case "error":
            job.answered = true;
            notice(event.reason === "language-data-unavailable" ? "Text capture unavailable" : "Capture failed", event.message, "danger");
            finishAction(job);
            break;
        default:
            notice("Capture failed", "The capture tool returned an unknown answer", "danger");
        }
        publish();
    }

    function notice(title, message, tone) {
        shell.toasts.show({ title: title, message: String(message).slice(0, 200), tone: tone, icon: "camera" });
    }

    // Every saved screenshot and recording; a failed post-process keeps the
    // recording as recorded and shows the end of the recorder log.
    function savedNotice(job, event) {
        const recording = isRecord(job.actionName);
        let message = event.path;
        if (recording && event.processing === "failed") {
            message += "\nProcessing failed, so the recording is kept as recorded.";
            if (event.detail !== "") message += "\n" + event.detail.slice(-Math.max(0, 199 - message.length));
        }
        notice(recording ? "Recording saved" : "Screenshot saved", message, "success");
    }

    function finished(job, error) {
        restoreFocus(job);
        if (!job.answered) notice("Capture failed", error || "The capture tool stopped without an answer", "danger");
        finishAction(job);
        jobs = jobs.filter(item => item !== job);
        publish();
        job.destroy();
    }

    // A clipboard provider stays owned after its action finishes. Replacing
    // the clipboard ends that worker. New captures use independent children.
    Component {
        id: workerComponent
        Process {
            id: worker
            property string actionName: ""
            property string focusAddress: ""
            property bool armed: false
            property bool answered: false
            stdinEnabled: true
            stdout: SplitParser { onRead: line => root.accept(worker, line) }
            stderr: StdioCollector { id: errors }
            onRunningChanged: if (!running && armed) root.finished(worker, errors.text)
        }
    }

    Process {
        id: prober
        property bool again: false
        stdout: SplitParser { onRead: line => root.probed(line) }
        onRunningChanged: if (!running && again) { again = false; root.probe(); }
    }

    Instantiator {
        model: Hyprland.toplevels
        onCountChanged: root.windowRead("")
        delegate: Connections {
            required property var modelData
            target: modelData
            // refreshToplevels emits addressChanged even for an unchanged
            // reply. Read on the next turn after its whole update lands.
            function onAddressChanged() {
                const address = modelData.address;
                Qt.callLater(() => root.windowRead(address));
            }
        }
    }
    Instantiator {
        model: Hyprland.monitors
        onCountChanged: root.monitorRead("")
        delegate: Connections {
            required property var modelData
            target: modelData
            function onLastIpcObjectChanged() { root.monitorRead(modelData.name); }
        }
    }
    Timer {
        id: windowDeadline
        interval: root.shell === null ? 0 : root.shell.settings.timeout * 1000
        onTriggered: {
            root.waitingWindows = [];
            root.waitingMonitors = [];
            root.phase = "idle";
            root.action = "";
            root.notice("Capture failed", "Window information could not be read", "danger");
            root.publish();
        }
    }
}
