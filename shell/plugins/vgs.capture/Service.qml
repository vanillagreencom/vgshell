import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// One service owns the worker, every IPC and shortcut, and all status writes.
// The worker's stdin carries recording stop; its lifetime owns every tool.
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
    readonly property var tools: ({
        "screenshot": ["grim"],
        "screenshot-area": ["grim", "slurp", "hyprpicker"],
        "screenshot-window": ["grim", "slurp", "hyprpicker"],
        "screenshot-display": ["grim", "slurp", "hyprpicker"],
        "screenshot-all": ["grim"],
        "record": ["grim", "slurp", "hyprpicker", "gpu-screen-recorder"],
        "text": ["slurp", "hyprpicker", "grim", "tesseract", "wl-copy"]
    })

    onShellChanged: { start(); publish(); }
    onMissingChanged: publish()

    function start() {
        if (shell === null || registered) return;
        registered = true;
        for (const name of ["screenshot", "screenshot-area", "screenshot-window", "screenshot-display", "screenshot-all", "record", "text", "toggle"]) {
            shell.ipc.handle(name, () => root.invoke(name));
            shell.shortcut.register(name, name === "toggle" ? "Open or close Capture" : name === "record" ? "Start or stop recording" : name === "text" ? "Copy text from an area" : name === "screenshot-area" ? "Capture an area" : name === "screenshot-window" ? "Capture a window" : name === "screenshot-display" ? "Choose a display to capture" : name === "screenshot-all" ? "Capture all displays" : "Capture the focused output", () => root.invoke(name));
        }
        shell.ipc.handle("setting", arg => root.setFromRequest(arg));
        publish();
    }

    // Widgets and panels use this state rather than probing tools or processes.
    function publish() {
        if (shell === null) return;
        const available = {};
        for (const name of Object.keys(tools)) available[name] = requiredTools(name).every(tool => missing.indexOf(tool) < 0);
        shell.status.set("capture", { phase: phase, action: action, path: lastPath, remaining: remaining, available: available });
        const recording = phase === "recording" || phase === "stopping";
        shell.status.set("recording", { tone: recording ? "warning" : "info", text: phase === "stopping" ? "Saving recording" : recording ? "Recording" : available.record ? "Ready" : "Unavailable: recording needs gpu-screen-recorder on Arch" });
    }

    function requiredTools(name) {
        const required = tools[name];
        return name.indexOf("screenshot") === 0 && shell.settings.processing !== "save" ? required.concat(["wl-copy"]) : required;
    }

    function setFromRequest(arg) {
        let request;
        try { request = JSON.parse(arg); } catch (error) { return "refused: setting=unparsed"; }
        if (request === null || typeof request !== "object" || !Object.prototype.hasOwnProperty.call(request, "key") || !Object.prototype.hasOwnProperty.call(request, "value")) return "refused: setting=malformed";
        return shell.configure.set(request.key, request.value);
    }

    function invoke(name) {
        if (name === "toggle") return shell.surfaces.toggle("panel", "{}");
        if (name === "record" && phase === "recording") {
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
        if (name === "screenshot") {
            const focused = Hyprland.focusedMonitor;
            const found = focused === null || outputs === null ? null : outputs.find(item => item.name === focused.name && !item.disabled);
            if (found === null || found === undefined) return "refused: capture=output-unavailable";
            output = found.name;
        }
        phase = "capturing";
        action = name;
        if (name === "screenshot-window" || (name === "screenshot-area" && shell.settings.smart)) {
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
        const selection = name === "screenshot-area" || name === "screenshot-window" || name === "screenshot-display";
        const focused = selection ? Hyprland.activeToplevel : null;
        const request = { action: name, output: output, folder: shell.settings.folder, recordFolder: shell.settings.recordFolder, audio: shell.settings.audio, smart: shell.settings.smart, delay: shell.settings.delay, cursor: shell.settings.cursor, processing: shell.settings.processing, timeout: shell.settings.timeout, windows: selection ? windowRectangles() : [], outputs: outputRectangles() };
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
        case "saved":
            job.answered = true;
            lastPath = event.path;
            notice(job.actionName === "record" ? "Recording saved" : "Screenshot saved", event.path, "success");
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
            notice(event.reason === "english-data-unavailable" ? "Text capture unavailable" : "Capture failed", event.message, "danger");
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
