.pragma library

// What the Jarvis bar widget shows, pure so scripts/test-jarvis-widget.js
// runs it under node: the one judge from the status the service publishes
// (`daemon`, `detail`, `audio` and the Setup steps `setupVoice` and
// `setupModel`) to the widget's state, icon, tone and tooltip. A fault
// reads in plain words with what to do (faultText), which the bubble also
// shows; its keyed reason is in the service's log. The first matching
// rule wins:
//   live     capture is not closed: an open microphone always shows
//   problem  the daemon or audio report danger, or Session reads `error`
//   off      no Session state yet: the daemon's own text
//   muted    privacy mute is on, or turning on
//   loading  selected local voice is loading, with the AI model ready
//   working  required Setup steps are checking, with no action to take
//   off      the Session gate is down: one sentence per reason
//   working  Jarvis thinks, speaks, waits for a confirmation or acts
//   ready    Session is idle
// A tone is `calm` (the bar's foreground) or a group of Theme.badge.tone,
// whose foreground the widget draws in. A value outside the shapes the
// service and Session.js produce throws a keyed error; nothing falls back.

var LOOKS = {
    "live": { icon: "audio-lines", tone: "accent" },
    "problem": { icon: "circle-alert", tone: "danger" },
    "off": { icon: "power-off", tone: "neutral" },
    "muted": { icon: "mic-off", tone: "neutral" },
    "loading": { icon: "loader", tone: "info" },
    "working": { icon: "loader", tone: "info" },
    "ready": { icon: "mic", tone: "calm" }
};
// Session's gate-down reasons (Session.js validate).
var GATE_TEXT = {
    "starting": "Jarvis is starting",
    "unconfigured": "Jarvis is not set up. Open Settings > Jarvis.",
    "node": "Jarvis needs Node 22 or later",
    "lock-unknown": "Jarvis is off until the screen lock is known",
    "locked": "Jarvis is off while the screen is locked"
};
// The Session phases (Session.js phaseOf) in which Jarvis is working with
// its microphone closed. A coding task's own count is not in the status
// yet; `acting` is a running tool.
var WORK_TEXT = {
    "thinking": "Jarvis is thinking",
    "speaking": "Jarvis is speaking",
    "confirming": "Jarvis is waiting for your confirmation",
    "acting": "Jarvis is running a task"
};
// The required Setup steps the service publishes (SetupGate.readiness), in
// the engine's order, and what the bar says while one is still to do.
var SETUP_TEXT = [
    ["setupVoice", "Jarvis needs local voice. Set it up in Settings > Jarvis."],
    ["setupModel", "Jarvis needs an AI model. Choose one in Settings > Jarvis."]
];
// A Session fault's kind of failure, by its keyed reason: the first
// pattern that matches wins. Examples are the producers' own reasons:
// Session's thinking-timeout and device-lost, the engine's keyed brain and
// speech causes (ChainedEngine keyed: brain=stream-error, net=timeout,
// speech=local-not-ready) and Audio's capture and playback failures
// (audio-start: ..., device-probe: ..., playback-busy).
var FAULT_KINDS = [
    [/^thinking-timeout$/, "slow"],
    [/^device-lost$/, "device"],
    [/^(brain|net)=/, "brain"],
    [/^speech=/, "voice"],
    [/^(audio-start|device-probe|capture|playback)/, "audio"]
];
// What the bar and the bubble say of each kind: what went wrong, then what
// to do. Only a changed device setting or a restart clears a fault, so a
// device fault asks for a device and every other for a restart.
var RESTART = "Turn Jarvis off and on again in Settings > Jarvis.";
var FAULT_TEXT = {
    "slow": { title: "The AI model took too long to answer", action: RESTART },
    "device": { title: "The microphone or speaker is gone", action: "Connect it again, or choose another in Settings > Jarvis." },
    "brain": { title: "The AI model did not answer", action: RESTART },
    "voice": { title: "Local voice stopped working", action: RESTART },
    "audio": { title: "The microphone or speaker stopped working", action: RESTART },
    "other": { title: "Jarvis stopped after a problem", action: RESTART }
};
// While Session retries a lost device, Jarvis acts by itself.
var RETRYING = { title: "The microphone or speaker is gone", action: "Jarvis is trying it again." };
var AUDIO_TEXT = "Jarvis cannot read the microphones and speakers. " + RESTART;
// The tones Service.qml publishes for `daemon` and for `audio`.
var DAEMON_TONES = ["info", "warning", "danger"];
var AUDIO_TONES = ["info", "ok", "danger"];

function refuse(key, value) {
    throw new Error("jarvis widget: " + key + "=" + JSON.stringify(value) + " unexpected");
}

// A `daemon` or `audio` report, or null before the service published one.
function report(name, value, tones) {
    if (value === undefined) return null;
    if (value === null || typeof value !== "object" || typeof value.text !== "string"
            || tones.indexOf(value.tone) === -1)
        refuse(name, value);
    return value;
}

// Whether CAPTURE, Session's capture region, holds the microphone.
function microphoneOpen(capture) {
    switch (capture === null || typeof capture !== "object" ? undefined : capture.kind) {
    case "closed": return false;
    case "opening": case "open": case "closing": return true;
    default: refuse("capture", capture);
    }
}

// Whether MUTE, Session's mute region, is on or turning on.
function muted(mute) {
    switch (mute === null || typeof mute !== "object" ? undefined : mute.kind) {
    case "off": return false;
    case "muting": case "on": return true;
    default: refuse("mute", mute);
    }
}

// Whether GATE, Session's gate region, is down.
function gateDown(gate) {
    switch (gate === null || typeof gate !== "object" ? undefined : gate.kind) {
    case "up": return false;
    case "down":
        if (!Object.prototype.hasOwnProperty.call(GATE_TEXT, gate.reason)) refuse("gate", gate);
        return true;
    default: refuse("gate", gate);
    }
}

// The kind of FAULT, a Session fault, by FAULT_KINDS.
function faultKind(fault) {
    if (fault === null || typeof fault !== "object" || typeof fault.reason !== "string") refuse("fault", fault);
    for (var i = 0; i < FAULT_KINDS.length; i++)
        if (FAULT_KINDS[i][0].test(fault.reason)) return FAULT_KINDS[i][1];
    return "other";
}

// What FAULT, a Session fault that is not none, says: { title, action }.
function faultText(fault) {
    var kind = faultKind(fault);
    return fault.kind === "retrying" ? RETRYING : FAULT_TEXT[kind];
}

// Publish the approval labels together. QML may settle separate bindings in
// either order when a hold clears; this record is null or complete strings.
function approvalPrompt(hold) {
    if (hold === null) return null;
    var filePrompt = hold.purpose === "action"
        && (hold.tool === "apps.open" || hold.tool.startsWith("files.") || hold.tool === "harness.files");
    var lines = hold.text.split("\n");
    return { filePrompt: filePrompt, question: filePrompt ? lines[0] : hold.text,
        path: filePrompt && lines.length > 1 ? lines[1] : "",
        payload: filePrompt ? lines.slice(2).join("\n") : "", detail: filePrompt && lines.length > 2 };
}

// Whether required step STEP offers its action: true for the voice step,
// the name of the one that applies for the AI model step, whose manifest
// entry declares named actions (SetupGate.readiness).
function offered(step) {
    return step.action === true || typeof step.action === "string";
}

// What the bar says while the gate is down unconfigured: the first
// required step VALUES still holds to do, as SetupGate offers its action.
function unconfiguredText(values) {
    for (var i = 0; i < SETUP_TEXT.length; i++) {
        var step = values[SETUP_TEXT[i][0]];
        if (step && step.tone === "warning" && !offered(step) && step.hint)
            return step.text + ". Open Settings > Jarvis. " + step.hint;
        if (step !== undefined && step !== null && offered(step)) return SETUP_TEXT[i][1];
    }
    return GATE_TEXT.unconfigured;
}

// Only the published Checking and Done steps can explain a closed gate
// without asking the owner to change setup. Missing requirements stay off.
function setupChecking(values) {
    var checking = false;
    for (var i = 0; i < SETUP_TEXT.length; i++) {
        var step = values[SETUP_TEXT[i][0]];
        if (!step || offered(step) || (step.tone !== "info" && step.tone !== "ok")) return false;
        if (step.tone === "info") checking = true;
    }
    return checking;
}

// Voice loading is distinct from the unanswered initial setup check. The
// ready AI step and the absence of setup actions identify the selected plan.
function voiceLoading(values) {
    var voice = values.setupVoice;
    var model = values.setupModel;
    return !!voice && voice.tone === "info" && !offered(voice)
        && !!model && model.tone === "ok" && !offered(model);
}

// The second tooltip line names what a click does to MUTEON, the mute
// region the click toggles, whatever state the icon shows.
function look(state, line, muteOn) {
    var out = LOOKS[state];
    return { state: state, icon: out.icon, tone: out.tone,
        tooltip: line, tooltipDetails: [muteOn ? "Click to unmute" : "Click to mute"] };
}

// The widget's { state, icon, tone, tooltip, tooltipDetails } for VALUES,
// the plugin's status values. A key the service has not published yet is
// undefined.
function view(values) {
    var daemon = report("daemon", values.daemon, DAEMON_TONES);
    var audio = report("audio", values.audio, AUDIO_TONES);
    var detail = values.detail === undefined ? null : values.detail;
    if (detail !== null && (typeof detail !== "object" || typeof detail.phase !== "string"
            || detail.state === null || typeof detail.state !== "object"))
        refuse("detail", detail);
    var state = detail === null ? null : detail.state;
    var muteOn = state !== null && muted(state.mute);
    if (state !== null && microphoneOpen(state.capture)) return look("live", "Jarvis is using the microphone", muteOn);
    if (daemon !== null && daemon.tone === "danger") return look("problem", daemon.text, muteOn);
    if (detail !== null && detail.phase === "error") {
        var text = faultText(state.fault);
        return look("problem", text.title + ". " + text.action, muteOn);
    }
    if (audio !== null && audio.tone === "danger") return look("problem", AUDIO_TEXT, muteOn);
    if (state === null) return look("off", daemon === null ? GATE_TEXT.starting : "Jarvis: " + daemon.text, muteOn);
    if (muteOn) return look("muted", "Jarvis is muted", muteOn);
    var down = gateDown(state.gate);
    if ((!down || state.gate.reason === "unconfigured") && voiceLoading(values))
        return look("loading", "Jarvis is loading its voice", muteOn);
    if (down) {
        if (state.gate.reason === "unconfigured" && setupChecking(values))
            return look("working", "Jarvis is checking setup", muteOn);
        return look("off", state.gate.reason === "unconfigured" ? unconfiguredText(values) : GATE_TEXT[state.gate.reason], muteOn);
    }
    switch (detail.phase) {
    case "thinking": case "speaking": case "confirming": case "acting":
        return look("working", WORK_TEXT[detail.phase], muteOn);
    case "idle":
        return look("ready", "Jarvis is ready", muteOn);
    default:
        // Listening and armed hold capture open, which reads live above;
        // down holds the gate down.
        refuse("phase", detail.phase);
    }
}
