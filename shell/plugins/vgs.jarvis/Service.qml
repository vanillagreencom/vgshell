import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "." as Jarvis
import "JarvisProtocol.js" as Protocol
import "AccountProviders.js" as Providers
import "Session.js" as Session
import "SetupGate.js" as Gate
import "Conversation.js" as Conversation

Item {
    id: root
    property var shell: null
    property var lifetime: ({ kind: "new", pendingMute: "none" })
    property int retries: 0
    property int childSerial: 0
    property string outputTail: ""
    property string errorTail: ""
    property string cause: ""
    // The daemon writes diagnostics to stderr and keeps running. The last
    // complete line becomes the cause only if the daemon then exits, even
    // when that exit writes no line of its own.
    property string lastDiagnostic: ""
    property var audioHealth: ({ kind: "reading" })
    property var sessionState: null
    property var conversationLog: []
    // The request handlers, built on the first request; see requestHandlers().
    property var requests: null
    property var bubbles: []
    property var indicatorDelivery: ({ kind: "unknown" })
    readonly property string focusedOutput: Hyprland.focusedMonitor === null ? "" : Hyprland.focusedMonitor.name
    readonly property bool bubbleWanted: !lockObservation() && lifetime.kind === "ready" && cause === ""
        && sessionState !== null && Session.indicatorWanted(sessionState)
    readonly property bool indicatorPresented: bubbles.some(item => item !== null && item.presented)
    property double sentRequirementsRevision: -1
    readonly property var requirementsRevision: shell === null ? -1 : shell.requirements.revision
    readonly property bool locked: lockObservation()
    readonly property var effectiveKeys: shell === null ? null : shell.shortcut.keys
    // Whether the daemon plays its tones: the user's choice for the
    // manifest's `feedback` sound event, which the Sounds page sets.
    readonly property bool feedbackSounds: shell !== null && shell.sounds.choices.feedback !== ""
    // The daemon judges one floating task at a time from this run state.
    property var taskPrompts: []
    property var taskResponse: null
    readonly property bool taskTuiRunning: shell !== null && shell.tui.state.task.running
    readonly property string daemon: String(Qt.resolvedUrl("backend/jarvisd.js")).replace(/^file:\/\//, "")
    // Quickshell builds its desktop entry index on first use and fills it
    // after that; reading it here starts the scan before a list request.
    readonly property int desktopEntryCount: DesktopEntries.applications.values.length

    onShellChanged: {
        if (shell === null) return;
        if (lifetime.kind === "new") {
            shell.shortcut.register("talk", "Talk to Jarvis",
                () => intent("talk-down"), () => intent("talk-up"));
            shell.shortcut.register("mute", "Mute Jarvis", () => intent("mute"));
            shell.shortcut.register("stop", "Stop Jarvis", () => intent("stop"));
            shell.shortcut.register("confirm", "Confirm Jarvis", () => confirmApproval(displayedApproval(), "key"));
            shell.shortcut.register("console", "Open Jarvis console", () => summonConsole());
            // The bar widget's click and `vgshell ipc call vgs.jarvis invoke
            // mute` reach the Mute key's intent.
            shell.ipc.handle("mute", () => { intent("mute"); return "ok"; });
            shell.ipc.handle("say", text => say(text));
            shell.ipc.handle("stop", () => { intent("stop"); return "ok"; });
            // The console's Stop button and `vgshell ipc call vgs.jarvis
            // stop-task <id>` stop one coding task. The Stop key does not.
            shell.ipc.handle("stop-task", task => stopTask(task));
            // Task voice and console clients read a bounded index, then one
            // prompt. No model tool can call the answer entry.
            shell.ipc.handle("task-prompts", () => JSON.stringify({ prompts: taskPrompts.map(prompt =>
                ({ task: prompt.task, id: prompt.id, kind: prompt.kind })) }));
            shell.ipc.handle("task-prompt", text => {
                let query;
                try { query = JSON.parse(text); } catch (error) { return "refused: task-prompt=json"; }
                if (query === null || typeof query !== "object") return "refused: task-prompt=shape";
                const prompt = taskPrompts.find(value => value.task === query.task && value.id === query.id);
                return JSON.stringify({ prompt: prompt === undefined ? null : prompt });
            });
            shell.ipc.handle("task-answer", text => respondTask(text));
            shell.ipc.handle("task-response", () => JSON.stringify({ response: taskResponse }));
            shell.layers.show(bubble);
            start();
        }
        else hello();
    }
    onLockedChanged: hello()
    onFeedbackSoundsChanged: hello()
    onEffectiveKeysChanged: hello()
    onTaskTuiRunningChanged: sendTuiState()
    onIndicatorPresentedChanged: {
        const shown = indicatorPresented;
        // Keep every loss edge, but never grant a queued stale presentation.
        Qt.callLater(() => sendIndicator(shown));
    }
    onSessionStateChanged: Qt.callLater(() => sendIndicator(indicatorPresented))

    function attachBubble(item) { bubbles = bubbles.concat([item]); }
    function detachBubble(item) { bubbles = bubbles.filter(found => found !== item); }

    function sendIndicator(shown) {
        if (shell === null || lifetime.kind !== "ready" || sessionState === null || cause !== "" || !child.running) return;
        if (shown && !indicatorPresented) shown = false;
        const kind = shown ? "shown" : "gone";
        if (indicatorDelivery.kind === kind) return;
        try {
            const wire = JSON.stringify({ v: 1, type: "indicator", gen: sessionState.gen,
                revision: shell.manifest.__revision, shown: shown });
            Protocol.accept(wire, "shell");
            indicatorDelivery = { kind: kind };
            child.write(wire + "\n");
        } catch (error) { broken(error.message); }
    }
    onRequirementsRevisionChanged: refreshShell()

    function lockObservation() {
        return shell === null || shell.session === undefined || shell.session.locked !== false;
    }

    function publish(tone, text) {
        const reply = shell.status.set("daemon", { tone: tone, text: text });
        if (reply !== "ok") throw new Error("jarvis: " + reply);
    }

    // The Setup section's summary and required steps for ANSWER
    // (SetupGate.readiness), and the input step from its reader's VALUE.
    function publishSetup(answer) {
        const values = Gate.readiness(answer);
        values.setupModel = Gate.modelStep(values.setupModel, shell.status.values["keys"], accountReader.modelAccess);
        for (const key of Object.keys(values)) {
            const reply = shell.status.set(key, values[key]);
            if (reply !== "ok") throw new Error("jarvis: " + reply);
        }
    }
    function publishInput(value) {
        for (const [key, shown] of [["input", value], ["setupInput", Gate.optionalStep("setupInput", value)]]) {
            const reply = shell.status.set(key, shown);
            if (reply !== "ok") throw new Error("jarvis: " + reply);
        }
    }

    function start() {
        childSerial += 1;
        lifetime = { kind: "starting", pendingMute: lifetime.pendingMute === "none" ? "none" : "waiting" };
        sentRequirementsRevision = -1;
        outputTail = "";
        errorTail = "";
        cause = "";
        lastDiagnostic = "";
        audioHealth = { kind: "reading" };
        sessionState = null;
        indicatorDelivery = { kind: "unknown" };
        const result = shell.status.set("detail", null);
        if (result !== "ok") throw new Error("jarvis: " + result);
        for (const key of ["microphones", "speakers"]) {
            const cleared = shell.status.set(key, []);
            if (cleared !== "ok") throw new Error("jarvis: " + cleared);
        }
        const audioReport = shell.status.set("audio", { tone: "info", text: "Reading devices" });
        if (audioReport !== "ok") throw new Error("jarvis: " + audioReport);
        const quiet = shell.status.set("level", { capture: 0, playback: 0 });
        if (quiet !== "ok") throw new Error("jarvis: " + quiet);
        taskPrompts = [];
        taskResponse = null;
        const idle = shell.status.set("tasks", 0);
        if (idle !== "ok") throw new Error("jarvis: " + idle);
        const memory = shell.status.set("memory", { hidden: true });
        if (memory !== "ok") throw new Error("jarvis: " + memory);
        const silent = shell.status.set("transcript", null);
        if (silent !== "ok") throw new Error("jarvis: " + silent);
        conversationLog = Conversation.start();
        const emptyConversation = shell.status.set("conversation", conversationLog);
        if (emptyConversation !== "ok") throw new Error("jarvis: " + emptyConversation);
        publishInput({ tone: "warning", text: "Input tools unavailable", action: true });
        publishSetup({ kind: "checking" });
        shellStatus({ kind: "checking" });
        child.completion = null;
        child.stdinEnabled = true;
        publish("info", "Starting");
        child.running = true;
    }

    function refreshShell() {
        if (shell === null || lifetime.kind !== "ready" || !child.running
                || requirementsRevision <= sentRequirementsRevision) return;
        sentRequirementsRevision = requirementsRevision;
        send({ type: "requirements-scan", scan: requirementsRevision });
    }

    function hello() {
        if (shell === null || !child.running || cause !== ""
                || (lifetime.kind !== "starting" && lifetime.kind !== "ready")) return;
        const keys = shell.shortcut.keys;
        // Enablement and disposal can change the registry before the instance.
        // A partial key observation is not a complete hello snapshot.
        if (Object.keys(keys).length !== shell.manifest.hyprland.binds.length) return;
        const home = Quickshell.env("HOME");
        const message = {
            v: 1, type: "hello", gen: sessionState === null ? 0 : sessionState.gen,
            // The one place a voice, and a model with no list read, is
            // chosen for a user who chose none.
            settings: Object.assign({}, shell.settings, { sounds: feedbackSounds,
                voiceProvider: Gate.voiceProvider(shell.settings, accountReader.voiceKeys) },
                Providers.unlistedChoice(shell.settings, accountReader.providers[shell.settings.brain])),
            directories: {
                state: Paths.stateDir + "/jarvis",
                data: (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/vgshell/jarvis",
                runtime: Providers.runtimeDirectory(Quickshell.env("XDG_RUNTIME_DIR"))
            },
            revision: shell.manifest.__revision,
            locked: lockObservation(),
            keys: keys
        };
        const wire = JSON.stringify(message);
        try {
            Protocol.accept(wire, "shell");
            child.write(wire + "\n");
        } catch (error) { broken(error.message); }
    }

    function intent(name) {
        if (shell === null || lifetime.kind === "stopped") return;
        if (name === "mute") {
            if (lifetime.kind === "problem") {
                refuseMute(cause);
                return;
            }
            if (lifetime.pendingMute !== "none") return;
            if (lifetime.kind !== "ready" || sessionState === null || cause !== "" || !child.running) {
                lifetime = { kind: lifetime.kind, pendingMute: "waiting" };
                publish("warning", "Mute pending; disabling Jarvis cancels the request");
                notice({ title: "Jarvis mute pending",
                    message: "Waiting for daemon; disabling Jarvis cancels this request.",
                    tone: "warning", icon: "mic", transient: true });
                return;
            }
        }
        if (lifetime.kind !== "ready" || cause !== "" || !child.running) return;
        sendIntent(name);
    }

    function displayedApproval() {
        const item = bubbles.find(item => item !== null && item.approvalPresented);
        return item === undefined ? null : item.displayedHold;
    }

    function shownApproval(item, hold) {
        if (hold === null || !item.approvalPresented || item.displayedHold !== hold
                || sessionState === null || sessionState.approval.kind !== "held"
                || sessionState.approval.id !== hold.id || sessionState.gen !== hold.gen
                || sessionState.approval.digest !== hold.digest
                || lifetime.kind !== "ready" || cause !== "" || !child.running) return;
        send({ type: "shown", id: hold.id });
    }

    function confirmApproval(hold, source) {
        if (hold === null || lifetime.kind !== "ready" || cause !== "" || !child.running) return;
        send({ type: "intent", intent: "confirm", gen: hold.gen, id: hold.id, digest: hold.digest, source: source });
    }

    function cancelApproval(hold) {
        if (hold === null || lifetime.kind !== "ready" || cause !== "" || !child.running) return;
        send({ type: "intent", intent: "cancel", gen: hold.gen, id: hold.id });
    }

    function sendIntent(name) {
        send({ type: "intent", intent: name });
    }

    function summonConsole() {
        if (shell === null) return;
        const reply = shell.surfaces.summon("window", "{}");
        if (reply !== "ok") console.warn("jarvis: console " + reply);
    }

    function protocolKey(message) {
        return String(message).replace(/^jarvis: protocol=/, "");
    }

    function say(text) {
        if (shell === null || lifetime.kind !== "ready" || cause !== "" || !child.running || sessionState === null)
            return "refused: jarvis=not-ready";
        const fields = { type: "intent", intent: "say", text: String(text) };
        try {
            Protocol.accept(JSON.stringify(Object.assign({ v: 1, gen: 0, revision: shell.manifest.__revision }, fields)), "shell");
        } catch (error) { return "refused: say=" + protocolKey(error.message); }
        const refusal = Session.sayRefusal(sessionState);
        if (refusal !== null) return "refused: say=" + refusal;
        send(fields); return "ok";
    }

    function send(fields) {
        try {
            const wire = JSON.stringify(Object.assign({ v: 1,
                gen: sessionState === null ? 0 : sessionState.gen,
                revision: shell.manifest.__revision }, fields));
            Protocol.accept(wire, "shell");
            child.write(wire + "\n");
        } catch (error) { broken(error.message); }
    }

    function stopTask(task) {
        if (shell === null || lifetime.kind !== "ready" || cause !== "" || !child.running)
            return "refused: jarvis=not-ready";
        const fields = { type: "intent", intent: "task-stop", task: String(task) };
        // An id typed at the IPC is the caller's error, not a broken daemon.
        try {
            Protocol.accept(JSON.stringify(Object.assign({ v: 1, gen: 0, revision: shell.manifest.__revision }, fields)), "shell");
        } catch (error) { return "refused: " + error.message; }
        send(fields);
        return "ok";
    }

    function respondTask(text) {
        if (shell === null || lifetime.kind !== "ready" || cause !== "" || !child.running)
            return "refused: jarvis=not-ready";
        if (locked) return "refused: task-answer=locked";
        let response;
        try { response = JSON.parse(text); } catch (error) { return "refused: task-answer=json"; }
        if (response === null || typeof response !== "object") return "refused: task-answer=shape";
        const fields = { type: "intent", intent: "task-respond", task: response.task,
            prompt: response.prompt, answer: response.answer };
        try {
            Protocol.accept(JSON.stringify(Object.assign({ v: 1, gen: 0, revision: shell.manifest.__revision }, fields)), "shell");
        } catch (error) { return "refused: " + error.message; }
        taskResponse = null;
        send(fields);
        return "ok";
    }

    function sendTuiState() {
        if (shell === null || lifetime.kind !== "ready" || cause !== "" || !child.running) return;
        send({ type: "tui-state", name: "task", running: taskTuiRunning });
    }

    function taskAnswer(message) {
        if (message.answer === "stopped") return;
        console.warn("jarvis: task-stop=" + message.answer + " task=" + message.task);
        notice({ title: "Coding task not stopped",
            message: "Task " + message.task + ": " + message.answer, tone: "danger", icon: "mic" });
    }

    // One system notification; the core sends it and no other path draws it.
    function notice(options) {
        const reply = shell.notify.send(options);
        if (reply !== "ok") console.error("jarvis: notice " + reply);
    }

    function shellStatus(availability) {
        const value = availability.kind === "available" ? { tone: "ok", text: "Ready" }
            : availability.kind === "checking" ? { tone: "info", text: "Checking confinement" }
            : { tone: "warning", text: "Unavailable: " + availability.reason, action: availability.reason === "bwrap-missing" };
        const result = shell.status.set("shell", value);
        if (result !== "ok") throw new Error("jarvis: " + result);
    }

    function deliverMute() {
        if (lifetime.kind !== "ready" || lifetime.pendingMute === "none" || sessionState === null) return;
        // An unavailable daemon has no current toggle state. Pending presses
        // request mute on; retries must never toggle a restored mute off.
        if (sessionState.mute.kind === "on") {
            lifetime = { kind: "ready", pendingMute: "none" };
        } else if (sessionState.mute.kind === "off" && lifetime.pendingMute === "waiting") {
            lifetime = { kind: "ready", pendingMute: "sent" };
            sendIntent("mute");
        }
    }

    function refuseMute(reason) {
        notice({ title: "Jarvis mute not saved",
            message: "Mute request could not be saved: " + reason.slice(0, 180),
            tone: "danger", icon: "mic" });
    }

    // One reply per daemon request, from the capability that owns the act.
    // The reply carries the shell's own answer; the daemon reads every
    // effect back from Hyprland itself. Each handler answers {answer, data}.
    function requestHandlers() {
        const handlers = {
            "tui.run": args => ({ answer: shell.tui.run("task", args, () => {
                // A launch can end before its record reports running.
                if (lifetime.kind === "ready" && cause === "" && child.running)
                    send({ type: "tui-state", name: "task", running: false });
            }), data: null }),
            "compositor.reveal": args => ({ answer: shell.compositor.reveal([args[0]], false), data: null }),
            "run.detached": args => ({ answer: shell.run.detached(args), data: null }),
            "desktop.list": () => ({ answer: "ok", data: Protocol.desktopEntries(DesktopEntries.applications.values.map(entryRecord)) }),
            "desktop.launch": args => {
                const entry = DesktopEntries.byId(args[0]);
                const data = entry === null ? null : Protocol.desktopEntry(entryRecord(entry), true);
                if (data === null) return { answer: "refused: desktop=unknown", data: null };
                return { answer: shell.run.detached(DesktopLaunch.entry(entry)), data: data };
            }
        };
        for (const kind of Object.keys(Protocol.REQUESTS)) {
            if (!kind.startsWith("compositor.") || handlers[kind] !== undefined) continue;
            const name = kind.slice("compositor.".length);
            handlers[kind] = args => ({ answer: shell.compositor[name].apply(null, args), data: null });
        }
        return handlers;
    }

    function serve(message) {
        if (message.kind === "input.observe" || message.kind === "input.keys") {
            const serial = childSerial;
            const done = value => {
                if (serial !== childSerial || lifetime.kind !== "ready" || !child.running) return;
                reply(message, { answer: value.ok ? "ok" : value.error, data: value.ok ? value : null });
            };
            try {
                if (message.kind === "input.observe") shell.compositor.observeInput(message.args.length === 0 ? null
                    : { x: message.args[0], y: message.args[1] }, done);
                else {
                    const effective = Object.values(shell.shortcut.keys).filter(key => key !== null);
                    shell.hyprland.resolveKeys(message.args.concat(effective), value => {
                        const current = Object.values(shell.shortcut.keys).filter(key => key !== null);
                        if (JSON.stringify(current) !== JSON.stringify(effective))
                            value = { ok: false, error: "refused: keymap=binds-changed" };
                        else if (value.ok) value = { ok: true, keys: value.keys, translation: value.translation, effective: effective };
                        done(value);
                    });
                }
            } catch (error) { done({ ok: false, error: String(error.message) }); }
            return;
        }
        if (requests === null) requests = requestHandlers();
        const handler = requests[message.kind];
        if (handler === undefined) throw new Error("jarvis: request=unserved kind=" + message.kind);
        let result = { answer: Protocol.lockedRefusal(message.kind, lockObservation()), data: null };
        if (result.answer === "") {
            try { result = handler(message.args); }
            catch (error) {
                // A capability that refuses by throwing answers its message.
                result = { answer: String(error.message), data: null };
            }
        }
        reply(message, result);
    }

    function reply(message, result) {
        const answer = Protocol.answer(result.answer);
        const wire = JSON.stringify({ v: 1, type: "reply", gen: message.gen, revision: message.revision,
            id: message.id, kind: message.kind, answer: answer, data: answer === "ok" ? result.data : null });
        Protocol.accept(wire, "shell");
        child.write(wire + "\n");
    }

    // What a reply says of an entry. The launch itself is DesktopLaunch's.
    function entryRecord(entry) {
        return { id: entry.id, name: entry.name, startupClass: entry.startupClass, noDisplay: entry.noDisplay,
            terminal: entry.runInTerminal };
    }

    // The first offer stands for the unset value (design-system.md
    // § Settings pages), and Jarvis's unset device follows the system
    // default, so a device list leads with that default under PipeWire's own
    // name for it. Settings stores "" for that entry, never the name.
    function deviceOffers(key, devices) {
        if (devices.length === 0) return devices;
        const systemDefault = key === "microphones" ? "@DEFAULT_AUDIO_SOURCE@" : "@DEFAULT_AUDIO_SINK@";
        return [{ label: "System default", value: systemDefault }].concat(devices);
    }

    function broken(reason) {
        cause = reason;
        console.warn(reason);
        child.stdinEnabled = false;
        child.running = false;
    }

    function receive(chunk) {
        if (cause !== "" || lifetime.kind === "stopped") return;
        try {
            const framed = Protocol.feed(outputTail, chunk);
            outputTail = framed.tail;
            for (const line of framed.lines) {
                const message = Protocol.accept(line, "daemon");
                if (message.revision !== shell.manifest.__revision)
                    throw new Error("jarvis: protocol=identity");
                if (message.type === "devices") {
                    for (const key of ["microphones", "speakers"]) {
                        const reply = shell.status.set(key, deviceOffers(key, message[key]));
                        if (reply !== "ok") throw new Error("jarvis: " + reply);
                    }
                    // Audio sends a failure's empty list before its fault, so a
                    // list after a fault is a later discovery.
                    if (audioHealth.kind !== "ready") {
                        audioHealth = { kind: "ready" };
                        const report = shell.status.set("audio", { tone: "ok", text: "Device list ready" });
                        if (report !== "ok") throw new Error("jarvis: " + report);
                    }
                    continue;
                }
                if (message.type === "request") {
                    serve(message);
                    continue;
                }
                if (message.type === "input-ready") {
                    const keys = message.commands.indexOf("wtype") !== -1;
                    const pointer = message.commands.indexOf("wlrctl") !== -1 || message.commands.indexOf("ydotool") !== -1;
                    publishInput({ tone: keys && pointer ? "ok" : "warning",
                        text: "Keys " + (keys ? "ready" : "unavailable") + "; pointer " + (pointer ? "ready" : "unavailable"), action: true });
                    continue;
                }
                if (message.type === "audio-fault") {
                    // The keyed reason goes to the log; the page and the bar
                    // say what stopped.
                    console.warn("jarvis: audio-fault=" + message.reason);
                    audioHealth = { kind: "fault", reason: message.reason };
                    const report = shell.status.set("audio", { tone: "danger", text: "Microphones and speakers unavailable" });
                    if (report !== "ok") throw new Error("jarvis: " + report);
                    continue;
                }
                if (message.type === "shell-status") {
                    shellStatus(message.availability);
                    continue;
                }
                if (message.type === "memory") {
                    const value = message.available ? { hidden: true }
                        : { tone: "warning", text: "Off",
                            hint: "jarvis: memory=sqlite. Memory search needs Node 22.13 or later with SQLite. Jarvis still answers without it." };
                    const reply = shell.status.set("memory", value);
                    if (reply !== "ok") throw new Error("jarvis: " + reply);
                    continue;
                }
                if (message.type === "tasks") {
                    const reply = shell.status.set("tasks", message.count);
                    if (reply !== "ok") throw new Error("jarvis: " + reply);
                    continue;
                }
                if (message.type === "task-prompts") {
                    taskPrompts = message.prompts;
                    continue;
                }
                if (message.type === "task-response") {
                    taskResponse = { task: message.task, prompt: message.prompt, answer: message.answer };
                    continue;
                }
                if (message.type === "task-answer") {
                    taskAnswer(message);
                    continue;
                }
                if (message.type === "level") {
                    if (sessionState !== null && message.gen === sessionState.gen) {
                        const reply = shell.status.set("level", message.level);
                        if (reply !== "ok") throw new Error("jarvis: " + reply);
                    }
                    continue;
                }
                if (message.type === "transcript") {
                    // A caption from an ended conversation never replaces the current one.
                    if (sessionState !== null && message.gen === sessionState.gen) {
                        const reply = shell.status.set("transcript", { gen: message.gen, role: message.role,
                            text: message.text, stage: message.stage, rev: message.rev });
                        if (reply !== "ok") throw new Error("jarvis: " + reply);
                        const segment = { gen: message.gen, role: message.role, text: message.text, stage: message.stage };
                        conversationLog = Conversation.update(conversationLog, segment);
                        const history = shell.status.set("conversation", conversationLog);
                        if (history !== "ok") throw new Error("jarvis: " + history);
                    }
                    continue;
                }
                if (message.type === "state") {
                    // An ordered old lock snapshot can precede the latest
                    // hello's answer. Do not publish it as current state.
                    if ((message.state.gate.reason === "locked") !== lockObservation()) continue;
                    const fault = message.state.fault;
                    if (fault.kind !== "none" && (sessionState === null || JSON.stringify(sessionState.fault) !== JSON.stringify(fault)))
                        console.warn("jarvis: fault=" + fault.reason + " kind=" + fault.kind);
                    sessionState = message.state;
                    const result = shell.status.set("detail", { phase: message.phase, seq: message.seq, state: message.state });
                    if (result !== "ok") throw new Error("jarvis: " + result);
                    deliverMute();
                    continue;
                }
                // An earlier snapshot can answer after the observed lock
                // changed. Wait for the current snapshot's ordered reply.
                if (message.daemon !== (lockObservation() ? "locked" : "ready")) continue;
                lifetime = { kind: "ready", pendingMute: lifetime.pendingMute };
                helloDeadline.stop();
                publish("info", message.daemon === "locked" ? "Locked; no capture" : "Ready; no capture");
                publishSetup({ kind: "answered", causes: message.causes });
                sendTuiState();
                Qt.callLater(() => sendIndicator(indicatorPresented));
                refreshShell();
            }
        } catch (error) { broken(error.message); }
    }

    function ended(completion) {
        helloDeadline.stop();
        if (lifetime.kind === "stopped") return;
        if (outputTail !== "") cause = "jarvis: protocol=unterminated-line";
        if (errorTail !== "") cause = errorTail;
        if (cause === "") cause = "jarvis: daemon=ended";
        const permanent = completion !== null && completion.status === 0 && completion.code === 78;
        // The keyed cause goes to the log; the daemon row says what happened.
        console.warn("jarvis: ended cause=" + cause);
        // The ended child's Session state is no longer current: neither the
        // retry wait nor a problem may show or act on it.
        sessionState = null;
        shellStatus({ kind: "unavailable", reason: "daemon-ended" });
        const stale = shell.status.set("detail", null);
        if (stale !== "ok") throw new Error("jarvis: " + stale);
        if (permanent || retries === 5) {
            if (lifetime.pendingMute !== "none") refuseMute(cause);
            lifetime = { kind: "problem", pendingMute: "none" };
            publish("danger", "Stopped after a problem. Turn Jarvis off and on again.");
            publishSetup({ kind: "stopped" });
            notice({ title: "Jarvis daemon stopped", message: cause.slice(0, 180), tone: "danger", icon: "mic" });
            return;
        }
        // A successful hello does not reset the allowance: a daemon that
        // repeatedly answers then dies cannot restart forever.
        retry.interval = 250 * Math.pow(2, retries);
        retries++;
        lifetime = { kind: "retry", pendingMute: lifetime.pendingMute };
        publish("warning", "Restarting after a problem");
        retry.start();
    }

    Component.onDestruction: {
        lifetime = { kind: "stopped", pendingMute: "none" };
        retry.stop();
        helloDeadline.stop();
        child.stdinEnabled = false;
    }

    Component {
        id: bubble
        Jarvis.Bubble { service: root }
    }

    Process {
        id: child
        property var completion: null
        command: ["node", root.daemon, "--tree", Quickshell.shellDir + "/.."]
        stdinEnabled: true
        clearEnvironment: true
        // The explicit account roots reach the daemon's protected path judge.
        environment: Object.assign({
            PATH: Quickshell.env("PATH"), HOME: Quickshell.env("HOME"),
            XDG_CONFIG_HOME: Quickshell.env("XDG_CONFIG_HOME"), XDG_STATE_HOME: Quickshell.env("XDG_STATE_HOME"),
            XDG_DATA_HOME: Quickshell.env("XDG_DATA_HOME"), XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR"),
            CLAUDE_CONFIG_DIR: Quickshell.env("CLAUDE_CONFIG_DIR"), CODEX_HOME: Quickshell.env("CODEX_HOME"),
            HYPRLAND_INSTANCE_SIGNATURE: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"),
            // The desktop tool executors hand these to their commands alone.
            WAYLAND_DISPLAY: Quickshell.env("WAYLAND_DISPLAY"),
            DBUS_SESSION_BUS_ADDRESS: Quickshell.env("DBUS_SESSION_BUS_ADDRESS"),
            YDOTOOL_SOCKET: Quickshell.env("YDOTOOL_SOCKET"),
            LANG: "C.UTF-8"
        }, AccountDirectories.accountVariables(name => Quickshell.env(name)))
        stdout: SplitParser { splitMarker: ""; onRead: data => root.receive(data) }
        stderr: SplitParser {
            splitMarker: ""
            onRead: data => {
                try {
                    const framed = Protocol.feed(root.errorTail, data);
                    root.errorTail = framed.tail;
                    for (const line of framed.lines) {
                        root.lastDiagnostic = line;
                        console.warn("jarvis: stderr=" + line);
                    }
                } catch (error) { root.broken(error.message); }
            }
        }
        onStarted: {
            root.hello();
            if (root.cause === "") helloDeadline.start();
        }
        onExited: (code, status) => {
            completion = { code: code, status: status };
            if (root.cause === "") root.cause = root.lastDiagnostic !== "" ? root.lastDiagnostic
                : "jarvis: daemon=exit code=" + code + " status=" + status;
        }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            root.ended(done);
        }
    }
    Timer { id: retry; onTriggered: root.start() }
    Timer { id: helloDeadline; interval: 5000; onTriggered: root.broken("jarvis: hello=timeout") }
    // A finished key, account or local voice step can change what the
    // engine judges, so each reader's refresh sends the daemon a fresh
    // snapshot; hello() sends none while the child is not running or broken.
    Jarvis.Keys { shell: root.shell; onRefreshed: root.hello() }
    Jarvis.LocalRuntime { shell: root.shell; onRefreshed: root.hello() }
    Jarvis.BrowserRuntime { shell: root.shell; stepKey: "setupBrowser" }
    Jarvis.Accounts { id: accountReader; shell: root.shell; onRefreshed: root.hello() }
}
