import QtQuick
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
    readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("helper/capture.py")).replace(/^file:\/\//, ""))
    readonly property var outputs: shell === null ? null : shell.monitors.outputs
    readonly property var missing: shell === null ? [] : shell.requirements.missing
    readonly property var tools: ({
        "screenshot": ["grim", "wl-copy"],
        "screenshot-area": ["grim", "slurp", "hyprpicker", "wl-copy"],
        "record": ["grim", "slurp", "hyprpicker", "gpu-screen-recorder"],
        "text": ["slurp", "hyprpicker", "grim", "tesseract", "wl-copy"]
    })

    onShellChanged: start()
    onMissingChanged: publish()

    function start() {
        if (shell === null || registered) return;
        registered = true;
        for (const name of ["screenshot", "screenshot-area", "record", "text", "toggle"]) {
            shell.ipc.handle(name, () => root.invoke(name));
            shell.shortcut.register(name, name === "toggle" ? "Open or close Capture" : name === "record" ? "Start or stop recording" : name === "text" ? "Copy text from an area" : name === "screenshot-area" ? "Capture an area" : "Capture the focused output", () => root.invoke(name));
        }
        shell.ipc.handle("setting", arg => root.setFromRequest(arg));
        publish();
    }

    // Widgets and panels use this state rather than probing tools or processes.
    function publish() {
        if (shell === null) return;
        const available = {};
        for (const name of Object.keys(tools)) available[name] = tools[name].every(tool => missing.indexOf(tool) < 0);
        shell.status.set("capture", { phase: phase, action: action, path: lastPath, available: available });
        const recording = phase === "recording" || phase === "stopping";
        shell.status.set("recording", { tone: recording ? "warning" : "info", text: phase === "stopping" ? "Saving recording" : recording ? "Recording" : available.record ? "Ready" : "Unavailable: recording needs gpu-screen-recorder on Arch" });
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
        // The same key again ends its selection. Once the area is chosen the
        // worker no longer reads the line, and the capture completes.
        if (phase === "capturing" && action === name) {
            activeJob.write("cancel\n");
            return "ok";
        }
        if (phase !== "idle") return "refused: capture=busy";
        const needed = tools[name].filter(tool => missing.indexOf(tool) >= 0);
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
        const job = workerComponent.createObject(root, { actionName: name, command: ["python3", helperPath, JSON.stringify({ action: name, output: output, folder: shell.settings.folder, recordFolder: shell.settings.recordFolder, audio: shell.settings.audio })] });
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
        phase = "idle";
        action = "";
    }

    function accept(job, line) {
        let event;
        try { event = JSON.parse(line); } catch (error) { notice("Capture failed", "The capture tool returned an invalid answer", "danger"); return; }
        switch (event.event) {
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
            notice("Text copied", "Text from the selected area is on the clipboard", "success");
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
            property bool armed: false
            property bool answered: false
            stdinEnabled: true
            stdout: SplitParser { onRead: line => root.accept(worker, line) }
            stderr: StdioCollector { id: errors }
            onRunningChanged: if (!running && armed) root.finished(worker, errors.text)
        }
    }
}
