import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons

// One service owns the worker, every IPC and shortcut, and all status writes.
// The worker's stdin carries recording stop; its lifetime owns every tool.
// A probe worker reads the offered devices and missing languages for status.
// A finished capture keeps one sender alive for its notification's actions.
Item {
    id: root
    property var shell: null
    ShareSession { shell: root.shell }
    property bool registered: false
    property string phase: "idle"
    property string action: ""
    property string lastPath: ""
    property var jobs: []
    property var activeJob: null
    property int remaining: 0
    // The windows read a selection waits for, counted so a reply to a
    // cancelled or replaced read is dropped.
    property int windowsAsked: 0
    // The notification senders, oldest first. A run waits for
    // its notification to close, and vgs.notifications keeps an expired
    // toast's notification open for its History row
    // (NotificationLogic.heldAfterLeave), so a run can wait for good: past
    // noticesMax the oldest run's notification closes.
    property var notices: []
    readonly property int noticesMax: 8
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
        "screenshot": "Screenshot this screen",
        "screenshot-area": "Capture an area",
        "screenshot-window": "Capture a window",
        "screenshot-display": "Choose a display to capture",
        "screenshot-all": "Capture all displays",
        "record": "Record an area",
        "record-window": "Start or stop recording a window",
        "record-display": "Start or stop recording a chosen display",
        "record-output": "Record this screen",
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
        // The panel asks again each time it opens, which also refreshes the
        // audio sources and cameras the Settings page offers.
        shell.ipc.handle("probe", () => { root.probe(); return "ok"; });
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
        // A list the user cannot mend here reads Not available on Setup, its
        // hint naming what changes it (PluginLogic.statusDeclarationFits): a
        // change of the languages probes again.
        shell.status.set("languages", report.missing === undefined
            ? { tone: "danger", text: report.invalid ? "The language list is not valid" : "Installed languages could not be read", available: false,
                hint: report.invalid ? "Choose the [languages](page:vgs.capture/Settings/ocrLanguages) again" : "VGS checks again when you change the [languages](page:vgs.capture/Settings/ocrLanguages)" }
            : report.missing.length > 0
            ? { tone: "warning", text: ("Missing: " + report.missing.join(", ")).slice(0, 200), action: true }
            : { tone: "ok", text: "Ready" });
    }

    // Widgets and panels use this state rather than probing tools or processes.
    function publish() {
        if (shell === null) return;
        const available = {};
        for (const name of Object.keys(tools)) available[name] = requiredTools(name).every(tool => missing.indexOf(tool) < 0);
        shell.status.set("capture", { phase: phase, action: action, path: lastPath, remaining: remaining, available: available });
        const recording = phase === "recording" || phase === "stopping";
        const needed = requiredTools("record").filter(tool => missing.indexOf(tool) >= 0);
        shell.status.set("recording", { tone: recording || !available.record ? "warning" : "ok", text: phase === "stopping" ? "Saving recording" : recording ? "Recording" : available.record ? "Ready" : "Unavailable: recording needs " + needed.join(", ") });
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
        // `delay` has no schema entry, so the core judges its JSON type
        // alone; the range the worker accepts is held here.
        if (request.key === "delay" && !(Number.isInteger(request.value) && request.value >= 0 && request.value <= 60)) return "refused: setting=delay want=0..60";
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
                windowsAsked += 1;
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
        // The window boxes come from Hyprland's own reply: Quickshell's
        // Hyprland.toplevels can keep a closed window.
        if (name === "screenshot-window" || name === "record-window" || ((name === "screenshot-area" || name === "record") && shell.settings.smart)) {
            const asked = windowsAsked + 1;
            windowsAsked = asked;
            windowDeadline.restart();
            shell.compositor.readWindows(state => root.windowsRead(asked, state));
            publish();
            return "ok";
        }
        return launch(name, output, []);
    }

    function windowsRead(asked, state) {
        if (asked !== windowsAsked || !windowDeadline.running) return;
        windowDeadline.stop();
        if (!state.ok) {
            console.error("capture: " + state.error);
            windowsUnread();
            return;
        }
        launch(action, "", windowRectangles(state.clients, state.monitors));
    }

    function windowsUnread() {
        windowsAsked += 1;
        phase = "idle";
        action = "";
        notice("Capture failed", "Window information could not be read");
        publish();
    }

    function windowRectangles(clients, monitors) {
        return clients.filter(window => window.mapped && !window.hidden && shell.compositor.onScreen(window, monitors) && window.size[0] > 0 && window.size[1] > 0).map(window => ({ x: window.at[0], y: window.at[1], width: window.size[0], height: window.size[1], address: window.address, focus: window.focusHistoryID }));
    }

    function outputRectangles() {
        return outputs === null ? [] : outputs.filter(output => !output.disabled).map(output => ({ name: output.name, x: output.x, y: output.y, width: output.width, height: output.height, scale: output.scale, transform: output.transform }));
    }

    // WINDOWS holds the window boxes a selection offers, from windowsRead.
    function launch(name, output, windows) {
        const selection = ["screenshot-area", "screenshot-window", "screenshot-display", "record", "record-window", "record-display"].indexOf(name) >= 0;
        const focused = selection ? Hyprland.activeToplevel : null;
        const s = shell.settings;
        const request = { action: name, output: output, folder: s.folder, recordFolder: s.recordFolder, audio: s.audio, smart: s.smart, delay: s.delay, cursor: s.cursor, processing: s.processing,
            quality: s.quality, frameRate: s.frameRate, codec: s.codec, constantFrameRate: s.constantFrameRate, recordCursor: s.recordCursor, audioSources: s.audioSources, webcam: s.webcam, webcamDevice: s.webcamDevice,
            postProcess: s.postProcess, ocrLanguages: s.ocrLanguages, editor: s.editor, viewer: s.viewer, player: s.player, browser: s.browser, stateDir: Paths.stateDir, windows: windows, outputs: outputRectangles() };
        const job = workerComponent.createObject(root, { actionName: name, focusAddress: focused === null ? "" : focused.address, command: ["python3", helperPath, JSON.stringify(request)] });
        if (job === null) {
            phase = "idle";
            action = "";
            notice("Capture failed", "The capture worker could not start");
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
        remaining = 0;
    }

    function accept(job, line) {
        let event;
        try { event = JSON.parse(line); } catch (error) { notice("Capture failed", "The capture tool returned an invalid answer"); return; }
        switch (event.event) {
        case "selection-ended":
            restoreFocus(job);
            break;
        case "countdown":
            clearCountdown();
            remaining = event.remaining;
            if (remaining > 0) {
                phase = "delaying";
            } else {
                phase = "capturing";
                // The widget's "Capture in Ns" leaves the bar before the
                // worker takes the frame.
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
            notify(noticeRequest(job, event), event.actions);
            finishAction(job);
            break;
        case "copied":
            job.answered = true;
            notify(noticeRequest(job, event), []);
            finishAction(job);
            break;
        case "cancelled":
            job.answered = true;
            finishAction(job);
            break;
        case "error":
            job.answered = true;
            errorNotice(event);
            finishAction(job);
            break;
        default:
            notice("Capture failed", "The capture tool returned an unknown answer");
        }
        publish();
    }

    function notice(title, message) {
        const reply = shell.notify.send({ title: title, message: String(message).slice(0, 200), tone: "danger", icon: "camera" });
        if (reply !== "ok") console.error("capture: notice " + reply);
    }

    function errorNotice(event) {
        notice(event.reason === "language-data-unavailable" ? "Text capture unavailable" : "Capture failed", event.message);
    }

    // The sender gets labels and hints; only this run retains the worker's
    // argv. A failed post-process keeps the recording as recorded and shows
    // the end of the recorder log.
    function noticeRequest(job, event) {
        const recording = isRecord(job.actionName);
        const text = job.actionName === "text";
        let title = text ? "Text copied" : "Screenshot copied";
        let message = text ? "Text from the selected area is on the clipboard" : "The screenshot is on the clipboard";
        let image = "";
        if (event.event === "saved") {
            title = recording ? "Recording saved" : "Screenshot saved";
            message = event.path;
            image = recording ? event.thumbnail : event.path;
            if (recording && event.processing === "failed") {
                message += "\nProcessing failed, so the recording is kept as recorded.";
                if (event.detail !== "") message += "\n" + event.detail.slice(-Math.max(0, 199 - message.length));
            }
        }
        const hints = { "x-vgs-icon": "camera", "x-vgs-tone": "success" };
        if (image !== "") hints["image-path"] = image;
        return { title: title, message: message.slice(0, 200), hints: hints,
            actions: (event.actions || []).map(action => ({ id: action.id, label: action.label })) };
    }

    // Every persistent sender counts toward the same limit, including a
    // copied capture with no actions. The oldest sender closes first.
    function notify(request, actions) {
        // A list crosses createObject's initial properties as something
        // else, so the run takes its lists after creation.
        const run = noticeComponent.createObject(root);
        if (run === null) {
            console.error("capture: notice=unsent cause=process");
            return;
        }
        run.actions = actions;
        run.request = request;
        run.command = ["python3", helperPath, "--owned", "15", String(Quickshell.processId), "python3", helperPath, "--notify"];
        if (notices.length >= noticesMax) {
            closeNotice(notices[0]);
            notices = notices.slice(1);
        }
        notices = notices.concat([run]);
        run.running = true;
    }

    function closeNotice(run) {
        run.closing = true;
        if (run.running && run.requestSent) run.write("close\n");
    }

    // Cleanup addresses the server that accepted this id. A replacement
    // server may reuse the same numeric id for an unrelated notification.
    function closeKnownNotice(run) {
        if (run.noticeId === 0 || run.serverOwner === "") return;
        Quickshell.execDetached(["gdbus", "call", "--session", "--dest", run.serverOwner, "--object-path", "/org/freedesktop/Notifications",
            "--method", "org.freedesktop.Notifications.CloseNotification", String(run.noticeId)]);
        run.noticeId = 0;
        run.serverOwner = "";
    }

    // Only a typed action from the live sender can use this run's argv.
    function noticeLine(run, line) {
        let event;
        try { event = JSON.parse(line); } catch (error) {
            console.warn("capture: notice=invalid-answer");
            closeNotice(run);
            return;
        }
        if (event === null || typeof event !== "object" || Array.isArray(event)) {
            console.warn("capture: notice=invalid-answer");
            closeNotice(run);
            return;
        }
        if (event.event === "ready" && typeof event.owner === "string" && event.owner.length > 0
                && Number.isInteger(event.id) && event.id > 0 && event.id <= 4294967295 && run.noticeId === 0) {
            run.serverOwner = event.owner;
            run.noticeId = event.id;
            if (run.closing) run.write("close\n");
        } else if (event.event === "action" && typeof event.id === "string" && run.noticeId !== 0 && !run.closing) {
            const action = run.actions.find(item => item.id === event.id);
            if (action === undefined) return;
            const reply = shell.run.detached(action.argv);
            if (reply !== "ok") console.error("capture: action=" + action.id + " " + reply);
        } else if (event.event === "closed" && Number.isInteger(event.reason) && event.reason >= 0 && event.reason <= 4294967295) {
            run.closing = true;
            run.noticeId = 0;
            run.serverOwner = "";
        } else if (event.event === "error" && typeof event.operation === "string" && typeof event.message === "string") {
            console.info("capture: notice=unsent operation=" + event.operation + " " + event.message.replace(/\s+/g, " ").slice(0, 200));
            closeNotice(run);
        } else {
            console.warn("capture: notice=invalid-answer");
            closeNotice(run);
        }
    }

    // A run ended: COMPLETION is its exit, null when it did not start. With
    // no notification server on the bus the sender fails, and the capture
    // stands without its notification.
    function noticeEnded(run, completion, complaint) {
        run.closing = true;
        closeKnownNotice(run);
        notices = notices.filter(item => item !== run);
        if (completion === null || completion.code !== 0 || completion.status !== 0)
            console.info("capture: notice=unsent exit=" + JSON.stringify(completion) + " " + complaint.trim().replace(/\s+/g, " ").slice(0, 200));
        Qt.callLater(() => run.destroy());
    }

    // Quickshell kills a destroyed service's runs with SIGKILL, which
    // closes no notification, so its buttons would stay and do nothing:
    // each waiting notification closes on the server first.
    Component.onDestruction: {
        for (const run of notices) closeKnownNotice(run);
    }

    function finished(job, error) {
        restoreFocus(job);
        if (!job.answered) notice("Capture failed", error || "The capture tool stopped without an answer");
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

    Component {
        id: noticeComponent
        Process {
            id: run
            property var actions: []
            property var request: null
            property double noticeId: 0
            property string serverOwner: ""
            property bool closing: false
            property bool requestSent: false
            property var completion: null
            stdinEnabled: true
            stdout: SplitParser { onRead: line => root.noticeLine(run, line) }
            stderr: StdioCollector { id: complaint }
            onStarted: {
                write(JSON.stringify(request) + "\n");
                requestSent = true;
                if (closing) write("close\n");
            }
            onExited: (code, status) => { completion = { code: code, status: status }; }
            onRunningChanged: if (!running) root.noticeEnded(run, completion, complaint.text)
            // An evicted sender can still be completing its bounded close
            // when the service is destroyed, after it left notices.
            Component.onDestruction: root.closeKnownNotice(run)
        }
    }

    Process {
        id: prober
        property bool again: false
        stdout: SplitParser { onRead: line => root.probed(line) }
        onRunningChanged: if (!running && again) { again = false; root.probe(); }
    }

    Timer {
        id: windowDeadline
        // Hyprland's reply gets as long as the worker's CAPTURE_TIMEOUT
        // gives one tool.
        interval: 10000
        onTriggered: root.windowsUnread()
    }
}
