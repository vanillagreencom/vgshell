import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "." as Jarvis
import "JarvisProtocol.js" as Protocol
import "AccountProviders.js" as Providers
import "Session.js" as Session
import "SetupGate.js" as Gate
import "WidgetView.js" as View
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
    property var setupAnswer: ({ kind: "checking" })
    // The daemon's last personality message, null before one: its row
    // follows the status after it too (SetupGate.personalityRow).
    property var personalityShown: null
    // The daemon's last start-text message's size, null before one: its row
    // follows the status after it too.
    property var startTextShown: null
    // The Voice step's last published value, which shapes the Local voice
    // row (SetupGate.localVoiceStep).
    property var voiceStep: Gate.readiness({ kind: "checking" }).setupVoice
    // How many voices the daemon offers the Voice setting, from its last
    // voices message; 0 before one.
    property int voiceOffers: 0
    // The facts the ElevenLabs voices row and the Voice provider hint follow,
    // as text, so only a changed fact publishes them again.
    readonly property string elevenLabsFacts: shell === null ? "" : JSON.stringify([voiceProvider,
        accountReader.voiceKeys === undefined ? null : accountReader.voiceKeys, shell.settings.voiceAccount, setupAnswer, voiceOffers])
    onElevenLabsFactsChanged: publishElevenLabs()
    // Whether the settings `shell` holds name a Voice provider of this
    // version: onShellChanged sets it once it finds no provider stored as
    // "auto" before VGS-1953, which migrateVoiceProvider rewrites first.
    property bool voiceSettled: false
    // The voice the daemon runs, the Voice provider setting, "" without a
    // shell and until voiceSettled, so no reader meets the old form.
    readonly property string voiceProvider: voiceSettled && shell !== null ? shell.settings.voiceProvider : ""
    onVoiceProviderChanged: publishVoiceRoute()
    property var homeMessage: ({ homes: [], current: "" })
    property var homePathRead: ({ kind: "empty" })
    onHomePathReadChanged: {
        if (shell === null) return;
        if (personalityShown !== null) publishPersonality();
        if (startTextShown !== null) publishStartText();
    }
    readonly property string selectedHome: shell === null ? "" : shell.settings.home
    onSelectedHomeChanged: resolveHomePath()
    // The request handlers, built on the first request; see requestHandlers().
    property var requests: null
    property var bubbles: []
    property var indicatorDelivery: ({ kind: "unknown" })
    readonly property string focusedOutput: Hyprland.focusedMonitor === null ? "" : Hyprland.focusedMonitor.name
    readonly property bool bubbleWanted: !lockObservation() && lifetime.kind === "ready" && cause === ""
        && sessionState !== null && Session.indicatorWanted(sessionState)
    readonly property bool indicatorPresented: bubbles.some(item => item !== null && item.presented)
    // The console's box while a request waits for an answer, so the bubble
    // on that output can stand clear of the message field: { output, x, y,
    // width, height } in the logical pixels of a passive layer there, which
    // covers the output less the edges Hyprland reserves; null otherwise.
    property var consoleBox: null
    // The hold key the last finished read answers, the box's, none's or a
    // failure's alike: the bubble acknowledges no frame drawn before the
    // placement for the current hold is known.
    property string consoleKey: ""
    property int consoleReads: 0
    readonly property string heldKey: sessionState !== null && sessionState.approval.kind === "held"
        ? sessionState.gen + ":" + sessionState.approval.id : ""
    onHeldKeyChanged: readConsoleBox()
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
    // File actions publish their editor's completion in the plugin's edit
    // state (TuiRunner.editFor). A folder open has no editor run.
    readonly property var homeEditEndedAt: shell === null ? null : shell.tui.state.edit.endedAt
    onHomeEditEndedAtChanged: if (homeEditEndedAt !== null) hello()
    readonly property string daemon: String(Qt.resolvedUrl("backend/jarvisd.js")).replace(/^file:\/\//, "")
    // The core's one recording (D106), which the local voice's final words
    // come from (D064): a new copy after each change, and the cause the
    // daemon holds the local voice with while it cannot start
    // (SetupGate.dictationCause), which each hello carries.
    readonly property var dictationState: shell === null ? null : shell.dictation.state
    readonly property string dictationCause: shell === null ? ""
        : Gate.dictationCause(voiceProvider, dictationState)
    onDictationCauseChanged: hello()
    // The daemon's dictation start that waits for the core's read after the
    // last recording's command, { message, serial }, or null.
    property var pendingStart: null
    onDictationStateChanged: startDictation(false)
    // Quickshell builds its desktop entry index on first use and fills it
    // after that; reading it here starts the scan before a list request.
    readonly property int desktopEntryCount: DesktopEntries.applications.values.length
    // Each opening of the Jarvis Settings page judges the home again, so the
    // Personality row reads AGENTS.md as it is now.
    readonly property bool pageViewed: shell !== null && shell.status.viewed
    onPageViewedChanged: if (pageViewed) hello()

    // Qt runs this handler before the bindings that read `shell` (checked
    // with qmltestrunner on Qt 6.12), so a stored "auto" is rewritten
    // before they read the provider, and voiceSettled withholds it from a
    // binding either way. The rewrite publishes new settings, which the core
    // hands back as a new `shell` once this handler returns (Plugins.qml).
    onShellChanged: {
        voiceSettled = shell !== null && migrateVoiceProvider();
        if (!voiceSettled) return;
        if (lifetime.kind === "new") {
            shell.shortcut.register("talk", "Talk to Jarvis",
                () => intent("talk-down"), () => intent("talk-up"));
            shell.shortcut.register("mute", "Mute Jarvis", () => intent("mute"));
            shell.shortcut.register("stop", "Stop Jarvis", () => intent("stop"));
            shell.shortcut.register("confirm", "Confirm Jarvis", () => confirmApproval(displayedApproval(), "key"));
            shell.shortcut.register("console", "Open Jarvis console", () => summonConsole());
            shell.shortcut.register("home", "Switch Jarvis home", item => switchHome(item));
            // The bar widget's click and `vgshell ipc call vgs.jarvis invoke
            // mute` reach the Mute key's intent.
            shell.ipc.handle("mute", () => { intent("mute"); return "ok"; });
            // The local voice setup's release (tui/setup-local.sh, localSetup).
            shell.ipc.handle("local-setup", step => localSetup(step));
            // The bar widget's click opens the console, as the Console key does.
            shell.ipc.handle("console", () => { summonConsole(); return "ok"; });
            shell.ipc.handle("say", text => say(text));
            shell.ipc.handle("stop", () => { intent("stop"); return "ok"; });
            shell.ipc.handle("check-microphone", () => {
                if (locked || !Session.canCheck(sessionState)) return "refused: microphone-check=unavailable";
                intent("voice-check");
                return "ok";
            });
            // The speaker beside each offer of the Voice list plays it.
            const previews = shell.status.handlePreview("voice", value => previewVoice(value));
            if (previews !== "ok") console.warn("jarvis: preview=" + previews);
            // A choice on the Jarvis page of the Local voice model or the
            // Voice provider may open a setup window (voiceChosen); no other
            // change of either does.
            for (const key of ["localTier", "voiceProvider"]) {
                const choices = shell.status.handleChoice(key, (value, previous) => voiceChosen(key, value, previous));
                if (choices !== "ok") console.warn("jarvis: choice=" + key + " " + choices);
            }
            // The Edit action's screen opens the file this answers.
            shell.ipc.handle("personality-file", () => personalityFile());
            shell.ipc.handle("memory-confirm", text => memoryIntent("memory-confirm", text));
            shell.ipc.handle("memory-discard", text => memoryIntent("memory-discard", text));
            // The console's Stop button and `vgshell ipc call vgs.jarvis
            // stop-task <id>` stop one coding task. The Stop key does not.
            shell.ipc.handle("stop-task", task => stopTask(task));
            shell.ipc.handle("open-task", task => openTask(task));
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
    onLockedChanged: {
        if (locked) {
            startDictation(true);
            cancelDictation();
        }
        hello();
    }
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
        return publishDaemon({ tone: tone, text: text });
    }
    function publishDaemon(value) {
        const reply = shell.status.set("daemon", value);
        if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
        return reply === "ok";
    }

    // The Setup section's summary and required steps for ANSWER
    // (SetupGate.readiness), the summary beside the Jarvis session row
    // (SetupGate.sessionSummary).
    function publishSetup(answer) {
        setupAnswer = answer;
        if (voiceProvider === "") return false;
        const setupCause = localRuntime.setupCause;
        const merged = answer.kind === "answered" && setupCause !== "" && answer.causes.indexOf(setupCause) === -1
            ? { kind: "answered", causes: [setupCause].concat(answer.causes) }
            : answer;
        const values = Gate.readiness(merged, homePathRead, homeRepair.result);
        values.setupHome = Gate.homeRepairResult(values.setupHome, homeRepair.result);
        values.homePath = homePathRead.kind === "ready" ? homePathRead.path : "";
        values.setup = Gate.sessionSummary(values.setup, Gate.sessionStart(shell.settings.startAtBoot, sessionStart.result));
        values.setupVoice = Gate.dictationSetup(values.setupVoice, dictationState);
        const provider = voiceProvider;
        const voice = Providers.cloudVoice(provider);
        const talk = Gate.talkHint(shell.settings.mode, View.spelledKeys(shell.shortcut.keys, KeyNavLogic.keyCaps).talk);
        values.setupVoice = Gate.voiceCheck(values.setupVoice, sessionState === null ? null : sessionState.check, talk);
        values.setupVoice = Gate.setupValue(values.setupVoice, Gate.actionRequires(values.setupVoice, shell.manifest), shell.requirements.missing, true);
        values.setupVoice = Gate.voiceStep(values.setupVoice, { provider: provider, voice: voice, causes: merged.kind === "answered" ? merged.causes : [], talk: talk,
            keys: accountReader.voiceKeys === undefined ? 0 : Gate.voiceKeys(accountReader.voiceKeys, voice).length,
            size: localTier.pickSize, failure: Gate.localFailure(localRuntime.reading, localTier.wantedTier, localTier.readyTier) });
        values.setupModel = Gate.modelStep(values.setupModel, shell.status.values["keys"], accountReader.modelAccess);
        values.setupModel = Gate.modelDone(values.setupModel, shell.status.values["brains"], shell.settings.brain);
        for (const key of Object.keys(values)) {
            const reply = shell.status.set(key, values[key]);
            if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
            if (reply !== "ok") return false;
        }
        // The Local voice row is shaped beside the Voice step: a changed
        // Voice step publishes it again.
        if (JSON.stringify(values.setupVoice) !== JSON.stringify(voiceStep)) {
            voiceStep = values.setupVoice;
            if (!localRuntime.republish()) return false;
        }
        return true;
    }
    function publishShellSetup() {
        return publishSetup(setupAnswer);
    }
    // The optional input step, its reader's VALUE unchanged: the Settings
    // page draws an optional step's chip itself (Steps.stepView).
    function publishInput(value) {
        const reply = shell.status.set("input", value);
        if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
        return reply === "ok";
    }

    function start() {
        childSerial += 1;
        lifetime = { kind: "starting", pendingMute: lifetime.pendingMute === "none" ? "none" : "waiting" };
        sentRequirementsRevision = -1;
        outputTail = "";
        errorTail = "";
        cause = "";
        lastDiagnostic = "";
        setupAnswer = { kind: "checking" };
        personalityShown = null;
        startTextShown = null;
        voiceOffers = 0;
        audioHealth = { kind: "reading" };
        sessionState = null;
        indicatorDelivery = { kind: "unknown" };
        const result = shell.status.set("detail", null);
        if (!shell.status.isOk(result)) throw new Error("jarvis: " + result);
        if (result !== "ok") return;
        for (const key of ["microphones", "speakers", "voices"]) {
            const cleared = shell.status.set(key, []);
            if (!shell.status.isOk(cleared)) throw new Error("jarvis: " + cleared);
        }
        if (!publishHomes({ homes: [], current: "" })) return;
        const audioReport = shell.status.set("audio", { tone: "info", text: "Reading devices" });
        if (!shell.status.isOk(audioReport)) throw new Error("jarvis: " + audioReport);
        const quiet = shell.status.set("level", { capture: 0, playback: 0 });
        if (!shell.status.isOk(quiet)) throw new Error("jarvis: " + quiet);
        taskPrompts = [];
        taskResponse = null;
        const idle = shell.status.set("tasks", 0);
        if (!shell.status.isOk(idle)) throw new Error("jarvis: " + idle);
        for (const key of ["personality", "startText"]) {
            const unread = shell.status.set(key, { hidden: true });
            if (!shell.status.isOk(unread)) throw new Error("jarvis: " + unread);
        }
        const memory = shell.status.set("memory", { hidden: true });
        if (!shell.status.isOk(memory)) throw new Error("jarvis: " + memory);
        const inbox = shell.status.set("memoryInbox", []);
        if (!shell.status.isOk(inbox)) throw new Error("jarvis: " + inbox);
        const silent = shell.status.set("transcript", null);
        if (!shell.status.isOk(silent)) throw new Error("jarvis: " + silent);
        conversationLog = Conversation.start();
        const emptyConversation = shell.status.set("conversation", conversationLog);
        if (!shell.status.isOk(emptyConversation)) throw new Error("jarvis: " + emptyConversation);
        if (!publishInput({ tone: "warning", text: "Input tools unavailable", action: true })) return;
        if (!publishSetup({ kind: "checking" })) return;
        if (!shellStatus({ kind: "checking" })) return;
        child.completion = null;
        child.stdinEnabled = true;
        if (!publish("info", "Jarvis is starting")) return;
        child.running = true;
    }

    function refreshShell() {
        if (shell === null || lifetime.kind !== "ready" || !child.running
                || requirementsRevision <= sentRequirementsRevision) return;
        sentRequirementsRevision = requirementsRevision;
        send({ type: "requirements-scan", scan: requirementsRevision });
    }

    function hello() {
        if (voiceProvider === "" || !child.running || cause !== ""
                || (lifetime.kind !== "starting" && lifetime.kind !== "ready")) return;
        const keys = shell.shortcut.keys;
        // Enablement and disposal can change the registry before the instance.
        // A partial key observation is not a complete hello snapshot.
        if (Object.keys(keys).length !== shell.manifest.hyprland.binds.length) return;
        const home = Quickshell.env("HOME");
        // The Local voice choice is the page's download request, which
        // LocalTier owns; the daemon loads the tier setup left ready.
        const settings = Object.assign({}, shell.settings);
        delete settings.localTier;
        // SessionStart owns the boot session's two settings.
        delete settings.startAtBoot;
        delete settings.bootSession;
        const message = {
            v: 1, type: "hello", gen: sessionState === null ? 0 : sessionState.gen,
            // The one place a voice is chosen for a user who chose none, and
            // where a model with no list read is. The daemon repeats the
            // model choice by the account it resolves, for a hello sent
            // before the account reader's first answer.
            settings: Object.assign(settings, { sounds: feedbackSounds,
                voiceProvider: voiceProvider, dictation: dictationCause },
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
        } catch (error) { broken(error.message); return; }
        if (localSetupRelease !== "none" && localSetupChild !== childSerial) sendLocalSetup(true);
    }

    function intent(name) {
        if (shell === null) return;
        if (name === "stop" && (lifetime.kind !== "ready" || cause !== "" || !child.running)) {
            lifetime = { kind: "stopped", pendingMute: "none" };
            retry.stop();
            helloDeadline.stop();
            pendingStart = null;
            startWait.stop();
            cancelDictation();
            sessionState = null;
            child.stdinEnabled = false;
            if (child.running) stopDeadline.restart();
            const stale = shell.status.set("detail", null);
            if (!shell.status.isOk(stale)) throw new Error("jarvis: " + stale);
            if (stale !== "ok") return;
            publishDaemon({ tone: "warning", text: "Jarvis stopped", hint: Gate.START_RESTART });
            notice({ title: "Jarvis stopped", message: Gate.sentence(Gate.START_RESTART),
                tone: "info", icon: "vgs-letter-j" });
            return;
        }
        if (name === "mute") {
            if (lifetime.kind === "problem" || lifetime.kind === "stopped") {
                notice(Gate.muteRefusedNotice(cause));
                return;
            }
            if (lifetime.pendingMute !== "none") return;
            if (lifetime.kind !== "ready" || sessionState === null || cause !== "" || !child.running) {
                lifetime = { kind: lifetime.kind, pendingMute: "waiting" };
                if (!publish("warning", "Jarvis will mute when it is ready; turning Jarvis off cancels this request")) return;
                notice({ title: "Jarvis mute pending",
                    message: "Waiting for daemon; disabling Jarvis cancels this request.",
                    tone: "warning", icon: "vgs-letter-j", transient: true });
                return;
            }
        }
        if (lifetime.kind !== "ready" || cause !== "" || !child.running) {
            notice({ title: "Jarvis is not ready", message: "Check [Settings > Jarvis](page:vgs.jarvis/Settings) before trying again.",
                tone: "warning", icon: "vgs-letter-j", transient: true });
            return;
        }
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

    function memoryIntent(name, text) {
        if (shell === null || lifetime.kind !== "ready" || cause !== "" || !child.running)
            return "refused: jarvis=not-ready";
        let request;
        try { request = JSON.parse(text); } catch (error) { return "refused: memory=json"; }
        if (request === null || typeof request !== "object") return "refused: memory=shape";
        const fields = { type: "intent", intent: name, id: request.id, hash: request.hash };
        try {
            Protocol.accept(JSON.stringify(Object.assign({ v: 1, gen: 0, revision: shell.manifest.__revision }, fields)), "shell");
        } catch (error) { return "refused: " + error.message; }
        send(fields);
        return "ok";
    }

    // The console is the one mapped client of the shell's app-id,
    // `org.vgs.shell`, titled with this plugin's name, as the window host
    // titles it (vgs.settings Window.fitWindow reads its own the same way),
    // and on the screen as the compositor's onScreen judges it: a console
    // on a workspace no output shows covers nothing. A reply after the hold
    // ended, or behind a newer read, sets nothing.
    function readConsoleBox() {
        const key = heldKey;
        const serial = ++consoleReads;
        const answer = box => { consoleBox = box; consoleKey = key; };
        if (key === "" || shell === null) return answer(null);
        shell.compositor.readWindows(state => {
            if (serial !== consoleReads || key !== heldKey) return;
            const failed = why => { answer(null); console.warn("jarvis: console-box=" + why); };
            if (!state.ok) return failed(state.error);
            const own = state.clients.filter(c => c.class === "org.vgs.shell" && c.title === shell.manifest.name && c.mapped);
            if (own.length === 0) return answer(null);
            if (own.length !== 1) return failed("clients=" + own.length);
            const client = own[0];
            if (!shell.compositor.onScreen(client, state.monitors)) return answer(null);
            const monitors = state.monitors.filter(m => m.id === client.monitor);
            if (monitors.length !== 1) return failed("monitors=" + monitors.length + " id=" + client.monitor);
            const monitor = monitors[0];
            const reserved = monitor.reserved;
            if (!Array.isArray(reserved) || reserved.length !== 4 || !reserved.every(n => Number.isFinite(n)))
                return failed("reserved monitor=" + monitor.name);
            answer({ output: monitor.name, x: client.at[0] - monitor.x - reserved[0],
                y: client.at[1] - monitor.y - reserved[1], width: client.size[0], height: client.size[1] });
        });
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

    // The local voice's release for a setup-local run, which its window asks
    // for before it installs: the daemon's local speech sidecar holds
    // local-setup.lock shared for its whole life, and the install takes it
    // alone. "none"; "waiting" from the ask until the daemon answers that the
    // sidecar has exited, or the daemon itself has, since its children die
    // with it; "released" until the run ends, which sends the end. A daemon
    // started since the ask is told again after its hello (localSetupChild).
    property string localSetupRelease: "none"
    // The childSerial of the daemon last told the run started.
    property int localSetupChild: -1
    readonly property bool localSetupRunning: shell !== null && shell.tui.state["setup-local"] !== undefined && shell.tui.state["setup-local"].running
    onLocalSetupRunningChanged: {
        if (localSetupRunning || localSetupRelease === "none") return;
        localSetupRelease = "none";
        sendLocalSetup(false);
    }
    readonly property bool daemonRunning: child.running
    onDaemonRunningChanged: if (!daemonRunning && localSetupRelease === "waiting") localSetupRelease = "released"
    function sendLocalSetup(running) {
        if (shell === null || cause !== "" || !child.running) return false;
        localSetupChild = childSerial;
        send({ type: "local-setup", running: running });
        return true;
    }
    // The run's ask, STEP: `begin` tells the daemon and answers `waiting`,
    // refused outside a setup-local run, which the core reports live from
    // its launch, or while no daemon runs, which holds no sidecar, so the
    // window installs at once; `state` answers `waiting` or
    // `released`. A daemon still starting may start its sidecar, so its ask
    // waits: its hello, or its readiness for a hello already sent, tells it.
    function localSetup(step) {
        if (step === "state") return localSetupRelease === "none" ? "refused: local-setup=not-asked" : localSetupRelease;
        if (step !== "begin") return "refused: local-setup=" + step;
        if (!localSetupRunning) return "refused: local-setup=no-run";
        if (localSetupRelease !== "none") return localSetupRelease;
        if (!child.running || cause !== "" || lifetime.kind !== "ready" && lifetime.kind !== "starting")
            return "refused: jarvis=not-running";
        localSetupRelease = "waiting";
        if (lifetime.kind === "ready") sendLocalSetup(true);
        return "waiting";
    }
    onLifetimeChanged: if (lifetime.kind === "ready" && localSetupRelease === "waiting" && localSetupChild !== childSerial) sendLocalSetup(true)

    // Play VOICE, an offer of the Voice list, in the voice provider now
    // chosen: one fixed sentence, through the daemon's one preview route.
    // A cloud voice speaks it with the user's key; the Voice field's info
    // says so (Q5: one click plays, with no question).
    function previewVoice(voice) {
        if (shell === null || lifetime.kind !== "ready" || cause !== "" || !child.running || sessionState === null)
            return "refused: jarvis=not-ready";
        const refusal = Session.previewRefusal(sessionState);
        if (refusal !== null) return "refused: preview=" + refusal;
        if (typeof voice !== "string" || voice === "") return "refused: preview=voice";
        send({ type: "intent", intent: "preview", voice: voice });
        return "ok";
    }

    // The user chose VALUE for the field KEY on the Jarvis page in place of
    // PREVIOUS (the core's choice hook). A Local voice model may open the
    // local voice's download (LocalTier.chosen). A Voice provider opens at
    // most one window, which SetupGate.providerWindow names: Add a key for
    // a cloud voice with none of its keys stored, else the download for a
    // voice that hears on this computer with no tier ready.
    function voiceChosen(key, value, previous) {
        if (key === "localTier") {
            localTier.chosen(value);
            return;
        }
        switch (Gate.providerWindow(previous, value, localTier.reading, accountReader.voiceKeys, Providers.cloudVoice(value))) {
        case "add-voice-key": {
            const answer = shell.tui.run("add-voice-key", []);
            if (answer !== "ok") console.warn("jarvis: add-voice-key=" + answer);
            return;
        }
        case "setup-local":
            localTier.setUp();
            return;
        case null:
            return;
        default:
            throw new Error("jarvis: provider-window unexpected");
        }
    }

    // The read-only folder command uses Home.resolve, the daemon's path
    // owner, even while that folder's contents fail its setup check.
    function resolveHomePath() {
        homePathRead = { kind: selectedHome === "" ? "empty" : "reading" };
        if (shell !== null) publishSetup(setupAnswer);
        if (homePathProbe.running || selectedHome === "") return;
        homePathProbe.selected = selectedHome;
        homePathProbe.code = -1;
        homePathProbe.output = "";
        homePathProbe.timedOut = false;
        homePathProbe.running = true;
        homePathDeadline.restart();
    }

    function homePathFinished() {
        homePathDeadline.stop();
        if (homePathProbe.selected !== selectedHome) { resolveHomePath(); return; }
        homePathRead = homePathProbe.code === 0 && !homePathProbe.timedOut && homePathProbe.output.endsWith("\n")
            ? { kind: "ready", path: homePathProbe.output.slice(0, -1) } : { kind: "failed" };
        if (shell !== null) publishSetup(setupAnswer);
    }

    function personalityFile() {
        return homePathRead.kind === "ready" ? homePathRead.path + "/AGENTS.md" : "refused: home=none";
    }

    // The ElevenLabs voices row: the user's step until a key is chosen, then
    // the key's voice list as the daemon last reported it.
    function publishElevenLabs() {
        if (shell === null) return;
        const reply = shell.status.set("elevenLabs", Gate.elevenLabsStep({ provider: voiceProvider,
            keys: accountReader.voiceKeys, account: shell.settings.voiceAccount, answer: setupAnswer, voices: voiceOffers }));
        if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
    }

    // The Voice provider field's hint, from the provider the user chose.
    // Whether the settings name a Voice provider of this version. A provider
    // stored as "auto" before VGS-1953 is rewritten in place on this first
    // read (D107), the only reader of that form, and answers false: the
    // rewritten settings arrive as the next `shell`.
    function migrateVoiceProvider() {
        if (shell.settings.voiceProvider !== "auto") return true;
        const reply = shell.configure.set("voiceProvider", Gate.autoVoiceProvider(shell.settings));
        if (reply !== "ok") console.warn("jarvis: voice-provider-migration=" + reply);
        return false;
    }
    function publishVoiceRoute() {
        if (voiceProvider === "") return;
        const reply = shell.status.set("voiceRoute", Gate.voiceRoute(voiceProvider, Providers.cloudVoice(voiceProvider)));
        if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
    }


    // The Personality row from the last personality message and the last
    // status's causes, which say whether AGENTS.md is over its budget.
    function publishPersonality() {
        if (personalityShown === null) return true;
        const reply = shell.status.set("personality",
            Gate.personalityRow(personalityShown, setupAnswer.kind === "answered" ? setupAnswer.causes : [], homePathRead));
        if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
        return reply === "ok";
    }

    // The Start text size row from the last start-text message, each home
    // layer a line, and the last status's cautions, which name each text
    // over its budget.
    readonly property var startTextNames: ({ "home/persona": "Persona", "home/AGENTS.md": "Instructions", "home/skills": "Skills",
        "home/MEMORY.md": "Memory index", "home/state": "Working folder" })
    readonly property var startTextOver: ({ "guidance=persona-over-budget": "home/persona", "guidance=agents-over-budget": "home/AGENTS.md",
        "guidance=skills-over-budget": "home/skills", "guidance=memory-over-budget": "home/MEMORY.md", "guidance=start-over-budget": "start" })
    function publishStartText() {
        if (startTextShown === null) return true;
        const causes = setupAnswer.kind === "answered" ? setupAnswer.causes : [];
        const over = causes.filter(cause => startTextOver.hasOwnProperty(cause)).map(cause => startTextOver[cause]);
        // The copy is English, so its numbers group as English does.
        const count = (tokens, name) => tokens.toLocaleString(Qt.locale("en_US"), "f", 0) + " tokens"
            + (over.indexOf(name) === -1 ? "" : ", over its budget");
        const size = startTextShown;
        const value = size.kind === "unreadable" ? { tone: "warning", text: "Cannot be read",
                hint: "Check your " + Gate.homeReference("Home folder", homePathRead, "/") }
            : size.layers.length === 0 ? { tone: "info", text: "About " + count(size.tokens, "start"),
                hint: "Only Jarvis's own guidance until [Home folder](page:vgs.jarvis/Settings/home) sets a folder" }
            : { tone: "info", text: "About " + count(size.tokens, "start"),
                lines: size.layers.map(layer => startTextNames[layer.layer] + ": about " + count(layer.tokens, layer.layer)),
                info: Gate.startTextInfo(size.layers, causes, homePathRead) };
        const reply = shell.status.set("startText", value);
        if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
        return reply === "ok";
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

    function openTask(task) {
        if (shell === null || lifetime.kind !== "ready" || cause !== "" || !child.running)
            return "refused: jarvis=not-ready";
        if (locked) return "refused: task-open=locked";
        const fields = { type: "intent", intent: "task-open", task: String(task) };
        try {
            Protocol.accept(JSON.stringify(Object.assign({ v: 1, gen: 0, revision: shell.manifest.__revision }, fields)), "shell");
        } catch (error) { return "refused: " + error.message; }
        send(fields);
        return "ok";
    }

    function taskOpened(message) {
        if (locked) return;
        if (message.answer === "tmux") {
            const reply = shell.tui.run("task-view", [message.task], result => {
                if (result.code !== 0 || result.reason !== null)
                    taskOpenFailed(message.task, result.reason === null ? "exit-" + result.code : result.reason);
            });
            if (reply !== "ok") taskOpenFailed(message.task, reply);
            return;
        } else if (message.answer === "floating") {
            notice({ title: "Coding task", message: "This task runs in the floating terminal", tone: "info", icon: "terminal" });
            return;
        }
        taskOpenFailed(message.task, message.answer);
    }

    function taskOpenFailed(task, reason) {
        console.warn("jarvis: task-open=" + reason + " task=" + task);
        notice({ title: "Coding task not opened", message: "The coding task could not be opened.", tone: "danger", icon: "terminal" });
    }

    function sendTuiState() {
        if (shell === null || lifetime.kind !== "ready" || cause !== "" || !child.running) return;
        send({ type: "tui-state", name: "task", running: taskTuiRunning });
    }

    function taskAnswer(message) {
        if (message.answer === "stopped") return;
        console.warn("jarvis: task-stop=" + message.answer + " task=" + message.task);
        notice({ title: "Coding task not stopped",
            message: message.answer === "stop-in-flight" ? "This coding task is already stopping."
                : message.answer === "already-ended" ? "This coding task has already ended."
                : message.answer === "not-alive" ? "Jarvis could not find a running program for this coding task."
                : message.answer === "task-unknown" ? "Jarvis could not find this coding task."
                : message.answer === "identity-mismatch" ? "Jarvis could not confirm which programs belong to this coding task."
                : message.answer === "daemon-ending" ? "Jarvis is stopping. Try again after you turn Jarvis on."
                : "Jarvis could not stop this coding task. Open its terminal to check it.", tone: "danger", icon: "vgs-letter-j" });
    }

    // One system notification; the core sends it and no other path draws it.
    function notice(options) {
        const reply = shell.notify.send(options);
        if (reply !== "ok") console.error("jarvis: notice " + reply);
    }

    function shellStatus(availability) {
        const value = availability.kind === "available" ? { tone: "ok", text: "Ready" }
            : availability.kind === "checking" ? { tone: "info", text: "Checking" }
            : { tone: "warning", text: availability.reason === "bwrap-missing" ? "Needs bwrap" : "Unavailable", hint: availability.reason === "bwrap-missing"
                ? "[Review all missing or outdated tools on Setup](page:vgs.jarvis/Setup) to enable shell commands"
                : availability.reason === "public-runtime" ? "Jarvis could not prepare shell commands: turn Jarvis off and on again in [Settings](page:vgs.jarvis/Settings)"
                : "This system cannot run protected shell commands" };
        const result = shell.status.set("shell", value);
        if (!shell.status.isOk(result)) throw new Error("jarvis: " + result);
        return result === "ok";
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
            },
            "dictation.cancel": () => ({ answer: shell.dictation.cancel(), data: null })
        };
        for (const kind of Object.keys(Protocol.REQUESTS)) {
            if (!kind.startsWith("compositor.") || handlers[kind] !== undefined) continue;
            const name = kind.slice("compositor.".length);
            handlers[kind] = args => ({ answer: shell.compositor[name].apply(null, args), data: null });
        }
        return handlers;
    }

    function serve(message) {
        if (message.kind === "dictation.start") {
            queueStart(message);
            return;
        }
        // The stop answers once voxtype wrote its words, in the core's
        // callback; a reply after the daemon ended is not sent.
        if (message.kind === "dictation.stop") {
            const serial = childSerial;
            const done = result => {
                if (serial === childSerial && lifetime.kind === "ready" && child.running) reply(message, result);
            };
            const answer = shell.dictation.stop(result => done(dictationWords(result)));
            if (answer !== "ok") done({ answer: answer, data: null });
            return;
        }
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

    // The stop reply for the core's RESULT: voxtype's words, "" for none,
    // or the keyed failure. A text recording is never typed.
    function dictationWords(result) {
        if (result.kind === "empty") return { answer: "ok", data: { text: "" } };
        if (result.kind !== "text") return { answer: "refused: dictation=" + result.kind
            + (result.kind === "failed" ? " reason=" + result.reason : ""), data: null };
        if (result.text.length > Protocol.TEXT_MAX) return { answer: "refused: dictation=text-long", data: null };
        return { answer: "ok", data: { text: result.text } };
    }

    // A start waits while the core reads voxtype after the last recording's
    // command (state phase `unread`), when the core refuses a start; an older
    // start still waiting answers first.
    function queueStart(message) {
        if (pendingStart !== null) startDictation(true);
        pendingStart = { message: message, serial: childSerial };
        startWait.restart();
        startDictation(false);
    }

    // Answers the waiting start once the core's read ended, or with what the
    // core then answers once WAITED says the bound passed. The recording
    // records to the core's file and hands its words to the stop, never to
    // voxtype's output; a locked session starts none.
    function startDictation(waited) {
        const pending = pendingStart;
        if (pending === null || !waited && shell.dictation.state.phase === "unread") return;
        pendingStart = null;
        startWait.stop();
        if (pending.serial !== childSerial || lifetime.kind !== "ready" || !child.running) return;
        const refusal = lockObservation() ? "refused: locked" : Gate.dictationRefusal(shell.dictation.state);
        reply(pending.message, { answer: refusal !== "" ? refusal : shell.dictation.start("text"), data: null });
    }

    // Ends the recording this plugin holds, when the daemon that asked for
    // it ended, the session locked or the plugin is released.
    function cancelDictation() {
        if (shell === null || dictationState === null || dictationState.holder !== shell.manifest.id) return;
        const answer = shell.dictation.cancel();
        if (answer !== "ok") console.warn("jarvis: dictation-cancel " + answer);
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
    function homeOffers(homes) {
        const offers = [{ label: "None", value: "none" }].concat(homes);
        if (!offers.some(choice => choice.value === "~/Jarvis"))
            offers.push({ label: "~/Jarvis", value: "~/Jarvis" });
        return offers;
    }

    function publishHomes(message) {
        homeMessage = message;
        const rows = message.homes.map(choice => Object.assign({ id: choice.id, label: choice.label,
            icon: choice.value === message.current ? "folder-check" : "folder" },
            choice.value === message.current ? { description: "Current" } : {}));
        for (const [key, value] of [["homes", homeOffers(message.homes.map(choice => ({ label: choice.label, value: choice.value })))], ["homeRows", rows]]) {
            const reply = shell.status.set(key, value);
            if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
            if (reply !== "ok") return false;
        }
        return true;
    }

    function switchHome(item) {
        const choice = homeMessage.homes.find(row => row.id === item);
        if (choice === undefined) return "refused: home=" + item + " reason=unlisted";
        const reply = shell.configure.set("home", choice.value);
        if (reply !== "ok") {
            console.warn("jarvis: home-setting " + reply);
            notice({ title: "Jarvis home not changed", message: "The Home folder setting could not be saved.",
                tone: "danger", icon: "folder" });
        }
        return reply;
    }

    function broken(reason) {
        cause = reason;
        console.warn(reason);
        if (shell !== null && lifetime.kind !== "stopped") {
            publishDaemon(Gate.startStatus(cause, true));
            publishSetup({ kind: "problem", cause, action: Gate.RETRYING_START });
        }
        child.stdinEnabled = false;
        child.running = false;
        stopDeadline.restart();
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
                        if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
                        if (reply !== "ok") return;
                    }
                    // Audio sends a failure's empty list before its fault, so a
                    // list after a fault is a later discovery.
                    if (audioHealth.kind !== "ready") {
                        audioHealth = { kind: "ready" };
                        const report = shell.status.set("audio", { tone: "ok", text: "Device list ready" });
                        if (!shell.status.isOk(report)) throw new Error("jarvis: " + report);
                        if (report !== "ok") return;
                    }
                    continue;
                }
                if (message.type === "homes") {
                    if (!publishHomes(message)) return;
                    fleetRuntime.refresh();
                    continue;
                }
                if (message.type === "voices") {
                    const reply = shell.status.set("voices", message.voices);
                    if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
                    if (reply !== "ok") return;
                    voiceOffers = message.voices.length;
                    continue;
                }
                if (message.type === "personality") {
                    personalityShown = message.personality;
                    if (!publishPersonality()) return;
                    continue;
                }
                if (message.type === "start-text") {
                    startTextShown = message.size;
                    if (!publishStartText()) return;
                    continue;
                }
                if (message.type === "request") {
                    serve(message);
                    continue;
                }
                if (message.type === "input-ready") {
                    const keys = message.commands.indexOf("wtype") !== -1;
                    const pointer = message.commands.indexOf("wlrctl") !== -1 || message.commands.indexOf("ydotool") !== -1;
                    if (!publishInput({ tone: keys && pointer ? "ok" : "warning",
                        text: "Keys " + (keys ? "ready" : "unavailable") + "; pointer " + (pointer ? "ready" : "unavailable"), action: true })) return;
                    continue;
                }
                if (message.type === "audio-fault") {
                    // The keyed reason goes to the log; the page and the bar
                    // say what stopped.
                    console.warn("jarvis: audio-fault=" + message.reason);
                    audioHealth = { kind: "fault", reason: message.reason };
                    const report = shell.status.set("audio", { tone: "danger", text: "Microphones and speakers unavailable" });
                    if (!shell.status.isOk(report)) throw new Error("jarvis: " + report);
                    if (report !== "ok") return;
                    continue;
                }
                if (message.type === "shell-status") {
                    if (!shellStatus(message.availability)) return;
                    continue;
                }
                if (message.type === "memory") {
                    const reply = shell.status.set("memory", { tone: "warning", text: "Off",
                        hint: "Memory search needs Node 22.13 or later with SQLite. Jarvis still answers without it." });
                    if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
                    if (reply !== "ok") return;
                    continue;
                }
                if (message.type === "memory-inbox") {
                    const reply = shell.status.set("memoryInbox", message.entries);
                    if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
                    if (reply !== "ok") return;
                    continue;
                }
                if (message.type === "local-setup") {
                    if (localSetupRelease === "waiting") localSetupRelease = "released";
                    continue;
                }
                if (message.type === "tasks") {
                    const reply = shell.status.set("tasks", message.count);
                    if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
                    if (reply !== "ok") return;
                    continue;
                }
                if (message.type === "task-list" || message.type === "audit-failures") {
                    const reply = shell.status.set(message.type === "task-list" ? "taskList" : "auditFailures", message.rows);
                    if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
                    if (reply !== "ok") return;
                    continue;
                }
                if (message.type === "task-open") {
                    taskOpened(message);
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
                        if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
                        if (reply !== "ok") return;
                    }
                    continue;
                }
                if (message.type === "transcript") {
                    // A caption from an ended conversation never replaces the current one.
                    if (sessionState !== null && message.gen === sessionState.gen) {
                        const reply = shell.status.set("transcript", { gen: message.gen, role: message.role,
                            text: message.text, stage: message.stage, rev: message.rev });
                        if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
                        if (reply !== "ok") return;
                        const segment = { gen: message.gen, role: message.role, text: message.text, stage: message.stage };
                        conversationLog = Conversation.update(conversationLog, segment);
                        const history = shell.status.set("conversation", conversationLog);
                        if (!shell.status.isOk(history)) throw new Error("jarvis: " + history);
                        if (history !== "ok") return;
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
                    if (!publishShellSetup()) return;
                    const result = shell.status.set("detail", { phase: message.phase, seq: message.seq, state: message.state, brain: message.brain });
                    if (!shell.status.isOk(result)) throw new Error("jarvis: " + result);
                    if (result !== "ok") return;
                    deliverMute();
                    continue;
                }
                // An earlier snapshot can answer after the observed lock
                // changed. Wait for the current snapshot's ordered reply.
                if (message.daemon !== (lockObservation() ? "locked" : "ready")) continue;
                lifetime = { kind: "ready", pendingMute: lifetime.pendingMute };
                helloDeadline.stop();
                if (!publish("info", message.daemon === "locked" ? "Jarvis is locked; microphone is off" : "Jarvis is ready; microphone is off")) return;
                // A home text over its budget is a caution of the home step.
                if (!publishSetup({ kind: "answered", causes: message.cautions.concat(message.causes) })) return;
                if (!publishPersonality() || !publishStartText()) return;
                sendTuiState();
                Qt.callLater(() => sendIndicator(indicatorPresented));
                refreshShell();
            }
        } catch (error) { broken(error.message); }
    }

    function ended(completion) {
        helloDeadline.stop();
        stopDeadline.stop();
        if (lifetime.kind === "stopped") return;
        if (outputTail !== "") cause = "jarvis: protocol=unterminated-line";
        if (errorTail !== "") cause = errorTail;
        if (cause === "") cause = "jarvis: daemon=ended";
        const permanent = completion !== null && completion.status === 0 && completion.code === 78;
        // The keyed cause goes to the log; the daemon row says what happened.
        console.warn("jarvis: ended cause=" + cause);
        pendingStart = null;
        startWait.stop();
        cancelDictation();
        // The ended child's Session state is no longer current: neither the
        // retry wait nor a problem may show or act on it.
        sessionState = null;
        shellStatus({ kind: "unavailable", reason: "daemon-ended" });
        const stale = shell.status.set("detail", null);
        if (!shell.status.isOk(stale)) throw new Error("jarvis: " + stale);
        if (stale !== "ok") return;
        if (permanent || retries === 5) {
            if (lifetime.pendingMute !== "none") notice(Gate.muteRefusedNotice(cause));
            lifetime = { kind: "problem", pendingMute: "none" };
            publishDaemon(Gate.startStatus(cause, false));
            publishSetup({ kind: "problem", cause });
            notice(Gate.stoppedNotice(cause));
            return;
        }
        // A successful hello does not reset the allowance: a daemon that
        // repeatedly answers then dies cannot restart forever.
        retry.interval = 250 * Math.pow(2, retries);
        retries++;
        lifetime = { kind: "retry", pendingMute: lifetime.pendingMute };
        publishDaemon(Gate.startStatus(cause, true));
        publishSetup({ kind: "problem", cause, action: Gate.RETRYING_START });
        retry.start();
    }

    // The user turned Jarvis off: the one teardown that also stops the
    // user's Jarvis session. The destruction below follows it, as it
    // follows a reload, which stops no session.
    function turnedOff() { sessionStart.turnedOff(); }

    Component.onDestruction: {
        cancelDictation();
        lifetime = { kind: "stopped", pendingMute: "none" };
        retry.stop();
        helloDeadline.stop();
        stopDeadline.stop();
        child.stdinEnabled = false;
    }

    Component {
        id: bubble
        Jarvis.Bubble { service: root }
    }

    // While a request is held, the console's box is read again when a window
    // maps, closes or moves to another workspace, or an output shows another
    // workspace or opens or closes a special one: Hyprland posts movewindowv2
    // from CWindow::moveToWorkspace alone (v0.56.2
    // src/desktop/view/Window.cpp:534-580) and no event for a floating drag
    // or resize, so a console dragged into the bubble during one request is
    // followed at the next read, not live. rawEvent: Quickshell 0.3.1,
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/Hyprland
    Connections {
        target: Hyprland
        enabled: root.heldKey !== ""
        function onRawEvent(event) {
            if (event.name === "openwindow" || event.name === "closewindow" || event.name === "movewindowv2"
                    || event.name === "workspacev2" || event.name === "activespecial")
                root.readConsoleBox();
        }
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
            // A test run's marker and its trace path: under both, and only
            // then, the engine writes what the brain wrote (ChainedEngine.js).
            VGS_TEST_RUN: Quickshell.env("VGS_TEST_RUN"), VGS_JARVIS_TRACE: Quickshell.env("VGS_JARVIS_TRACE"),
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
    // Start bound: 108750 ms. It is 6 hello attempts x 5000 ms, six
    // forced-stop waits x 1000 ms, plus
    // retry backoff of 250+500+1000+2000+4000 ms, plus LocalSpeech.js
    // ready bound of 60000 ms, plus the setup probe bound of 10000 ms.
    // scripts/jarvis-selftest.sh --cold 10 on this machine on 2026-10-10
    // measured the setting place only: median 427.5 ms, max 478 ms, CPU
    // pressure some avg10=0.00 avg60=0.17 avg300=2.16.
    Timer { id: retry; onTriggered: root.start() }
    Timer { id: helloDeadline; interval: 5000; onTriggered: root.broken("jarvis: hello=timeout") }
    // A dictation start's wait for the core's read: one `voxtype status`
    // run after the last recording's command. It is the time the core gives
    // a daemon to take a cancel (DictationModel.js GRACE_MS, 2000 ms), a
    // bound on one voxtype command; no reading measured the read itself.
    Timer { id: startWait; interval: 2000; onTriggered: root.startDictation(true) }
    Timer {
        id: stopDeadline
        interval: 1000
        // Quickshell.Io Process.signal(int) is in the installed 0.3.1
        // quickshell-io.qmltypes. SIGKILL bounds a child that ignores the
        // SIGTERM sent by running=false after a hello timeout.
        onTriggered: if (child.running) child.signal(9)
    }
    // A finished key, account or local voice step can change what the
    // engine judges, so each reader's refresh sends the daemon a fresh
    // snapshot; hello() sends none while the child is not running or broken.
    Jarvis.Keys { shell: root.shell; onRefreshed: root.hello() }
    // A tier setup changes whether the cloned voice can run, so the clone
    // row reads again after each local voice check.
    // Local voice is required only while it is the voice the daemon runs,
    // so the row reads again when that voice changes.
    Jarvis.LocalRuntime {
        id: localRuntime
        readonly property string provider: root.voiceProvider
        shell: root.shell
        // The binding's value is the function: QML records the properties
        // a binding reads while it evaluates (Qt 6 Property Binding), so
        // root.voiceStep, read when the reader calls it, is no dependency.
        // publishSetup republishes the row after each Voice step value.
        shape: value => Gate.localVoiceStep(value, localRuntime.provider, root.voiceStep)
        onProviderChanged: refresh()
        onRefreshed: {
            if (!root.publishShellSetup()) return;
            root.hello();
            cloneRuntime.refresh();
        }
    }
    // The Voice step names the download size and a failed setup from the
    // tier reading, which can arrive after the setup answer.
    Jarvis.LocalTier { id: localTier; shell: root.shell; onReadingChanged: root.publishShellSetup() }
    Jarvis.CloneRuntime {
        id: cloneRuntime
        shell: root.shell
        provider: root.voiceProvider
        onRefreshed: root.hello()
    }
    Jarvis.BrowserRuntime { shell: root.shell }
    Jarvis.FleetRuntime { id: fleetRuntime; shell: root.shell }
    Jarvis.HomeRepair {
        id: homeRepair
        shell: root.shell
        wanted: root.setupAnswer.kind === "answered" && root.setupAnswer.causes.indexOf("home=package") !== -1
        onResultChanged: if (root.shell !== null) root.publishShellSetup()
        onRecheck: root.hello()
    }
    Process {
        id: homePathProbe
        property string selected: ""
        property string output: ""
        property int code: -1
        property bool timedOut: false
        command: ["node", fleetRuntime.program, "--tree", Quickshell.shellDir + "/..", "folder", selected]
        clearEnvironment: true
        environment: ({ PATH: Quickshell.env("PATH"), HOME: Quickshell.env("HOME"), LANG: "C.UTF-8" })
        stdout: StdioCollector { onStreamFinished: homePathProbe.output = text }
        stderr: StdioCollector {}
        // As in LocalRuntime: failed starts end through runningChanged;
        // successful exits supply their code before the end handler.
        onExited: (code, status) => homePathProbe.code = status === 0 ? code : -1
        onRunningChanged: if (!running) root.homePathFinished()
    }
    Timer {
        id: homePathDeadline
        // The folder probe is read-only. Reuse the local setup reader's
        // bound so a stuck helper cannot keep the file action waiting.
        interval: 10000
        repeat: false
        onTriggered: { homePathProbe.timedOut = true; homePathProbe.running = false; }
    }
    // The Setup summary names a session that cannot start.
    Jarvis.SessionStart { id: sessionStart; shell: root.shell; onResultChanged: root.publishShellSetup() }
    Jarvis.PowerWait { shell: root.shell; session: sessionStart; focusedOutput: root.focusedOutput }
    Jarvis.Accounts { id: accountReader; shell: root.shell; onRefreshed: root.hello() }
}
