.pragma library

// What the Jarvis bar widget shows, pure so scripts/test-jarvis-widget.js
// runs it under node. This is the one judge from the service status values
// (`daemon`, `detail`, `audio` and Setup steps), the spelled shortcut keys
// and the talk mode to the widget state, icon, tone and tooltip. The state
// table is closed: off, loading, ready, listening, working, speaking,
// muted and problem. The first matching rule wins:
//   listening  capture is not closed: an open microphone always shows
//   problem    the daemon or audio report danger, or Session reads `error`
//   loading    no Session state yet, or the gate is starting
//   muted      privacy mute is on, or turning on
//   off        a refused home folder needs a settings action
//   loading    setup checks or local voice loads
//   off        a gate reason or setup step needs an action before Jarvis can listen
//   working    Jarvis thinks, waits for confirmation or runs a task
//   speaking   playback is speaking
//   ready      Session is idle
// A tone is `calm` or a group of Theme.badge.tone. A value outside the
// shapes the service and Session.js produce throws a keyed error; nothing
// falls back.

var LOOKS = {
    "off": { icon: "power-off", tone: "neutral" },
    "loading": { icon: "loader", tone: "info" },
    "ready": { icon: "mic", tone: "calm" },
    "listening": { icon: "audio-lines", tone: "accent" },
    "working": { icon: "brain", tone: "info" },
    "speaking": { icon: "volume-2", tone: "accent" },
    "muted": { icon: "mic-off", tone: "neutral" },
    "problem": { icon: "circle-alert", tone: "danger" }
};
// Session's gate-down reasons (Session.js validate).
var GATE_TEXT = {
    "starting": { title: "Jarvis is starting", action: "Wait for Jarvis to start." },
    "unconfigured": { title: "Jarvis is not set up", action: "Open Settings > Jarvis." },
    "node": { title: "Jarvis needs Node 22 or later", action: "Use the requirement notice to install Node." },
    "lock-unknown": { title: "Jarvis is checking the screen lock", action: "Wait for the screen lock check." },
    "locked": { title: "Jarvis is off while the screen is locked", action: "Unlock the screen to use Jarvis." }
};
// The Session phases (Session.js phaseOf) in which Jarvis is working with
// its microphone closed. `acting` is a running tool.
var WORK_TEXT = {
    "thinking": "Jarvis is thinking",
    "confirming": "Jarvis is waiting for your confirmation",
    "acting": "Jarvis is running a task"
};
// The required Setup steps the service publishes (SetupGate.readiness), in
// the engine's order, and what the bar says while one is still to do.
var SETUP_TEXT = [
    ["setupVoice", { title: "Jarvis needs local voice", action: "Set it up in Settings > Jarvis." }],
    ["setupModel", { title: "Jarvis needs an AI model", action: "Choose one in Settings > Jarvis." }]
];
// A Session fault's kind of failure, by its keyed reason: the first
// pattern that matches wins. Examples are the producers' own reasons:
// Session's thinking-timeout and device-lost, the engine's keyed brain and
// speech causes (ChainedEngine keyed: brain=stream-error, net=timeout,
// speech=local-not-ready), the home folder causes of a conversation's
// first turn (home=link, guidance=home-too-large) and Audio's capture and
// playback failures (audio-start: ..., device-probe: ..., playback-busy).
var FAULT_KINDS = [
    [/^thinking-timeout$/, "slow"],
    [/^device-lost$/, "device"],
    [/^(home=|guidance=home-)/, "home"],
    [/^(brain|net)=/, "brain"],
    [/^speech=/, "voice"],
    [/^(audio-start|device-probe|capture|playback)/, "audio"]
];
// What the bar and the bubble say of each kind: what went wrong, then what
// to do. Only a changed device setting or a restart clears a fault, so a
// device fault asks for a device and every other for a restart. A home
// folder fault asks for the folder: Jarvis reads it again at the next
// request.
var RESTART = "Turn Jarvis off and on again in Settings > Jarvis.";
var FAULT_TEXT = {
    "slow": { title: "The AI model took too long to answer", action: RESTART },
    "device": { title: "The microphone or speaker is gone", action: "Connect it again, or choose another in Settings > Jarvis." },
    "home": { title: "Jarvis cannot use the home folder", action: "Check AGENTS.md, MEMORY.md and the skills in the folder, or choose another folder in Settings > Jarvis." },
    "brain": { title: "The AI model did not answer", action: RESTART },
    "voice": { title: "Local voice stopped working", action: RESTART },
    "audio": { title: "The microphone or speaker stopped working", action: RESTART },
    "other": { title: "Jarvis stopped after a problem", action: RESTART }
};
// While Session retries a lost device, Jarvis acts by itself.
var RETRYING = { title: "The microphone or speaker is gone", action: "Jarvis is trying it again." };
var AUDIO_TEXT = { title: "Jarvis cannot read the microphones and speakers", action: RESTART };
var DAEMON_TEXT = { title: "Jarvis stopped after a problem", action: RESTART };
// The tones Service.qml publishes for `daemon` and for `audio`.
var DAEMON_TONES = ["info", "warning", "danger"];
var AUDIO_TONES = ["info", "ok", "danger"];

function refuse(key, value) {
    throw new Error("jarvis widget: " + key + "=" + JSON.stringify(value) + " unexpected");
}

function hasOwn(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
}

// A `daemon` or `audio` report, or null before the service published one.
function report(name, value, tones) {
    if (value === undefined) return null;
    if (value === null || typeof value !== "object" || typeof value.text !== "string"
            || tones.indexOf(value.tone) === -1)
        refuse(name, value);
    return value;
}

// KEYS, shell.shortcut.keys or null, as people read each key a tooltip
// names; CAPS is KeyNavLogic.keyCaps, which the callers' qs.Ui import holds.
// A name absent from the map is no key in effect: the nested smoke
// (jarvis-bubble row, 2026-10-10) read an empty map while the plugin is
// enabled or disabled, before the registry holds its binds.
function spelledKeys(keys, caps) {
    var out = {};
    var names = ["talk", "mute", "stop", "confirm"];
    for (var i = 0; i < names.length; i++) {
        var key = keys === null ? null : keys[names[i]];
        out[names[i]] = key === null || key === undefined ? null : caps(key).join("+");
    }
    return out;
}

function shortcutKeys(value) {
    if (value === null || typeof value !== "object" || Array.isArray(value)) refuse("keys", value);
    var names = ["talk", "mute", "stop", "confirm"];
    for (var i = 0; i < names.length; i++) {
        var name = names[i];
        if (!hasOwn(value, name) || (value[name] !== null && typeof value[name] !== "string")) refuse("keys", value);
    }
    return value;
}

function talkMode(value) {
    if (["hold", "toggle", "always"].indexOf(value) === -1) refuse("mode", value);
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
        if (!hasOwn(GATE_TEXT, gate.reason)) refuse("gate", gate);
        return true;
    default: refuse("gate", gate);
    }
}

// The kind of FAULT, a Session fault, by FAULT_KINDS.
function faultKind(fault) {
    if (fault === null || typeof fault !== "object" || (fault.kind !== "error" && fault.kind !== "retrying")
            || typeof fault.reason !== "string") refuse("fault", fault);
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

// Whether the daemon refuses the home folder the user chose: the step
// SetupGate publishes only then, the first in the engine's order, which
// offers no action and says what to change.
function homeRefused(values) {
    var home = values.setupHome;
    return !!home && home.tone === "warning" && typeof home.hint === "string" && home.hint !== "";
}

// What the bar says of a refused home folder: its step's own words.
function homeText(values) {
    return { title: values.setupHome.text, action: "Open Settings > Jarvis. " + values.setupHome.hint };
}

// What the bar says while the gate is down unconfigured: the first
// required step VALUES still holds to do, as SetupGate offers its action.
function unconfiguredText(values) {
    for (var i = 0; i < SETUP_TEXT.length; i++) {
        var step = values[SETUP_TEXT[i][0]];
        if (step && step.tone === "warning" && !offered(step) && step.hint)
            return { title: step.text, action: "Open Settings > Jarvis. " + step.hint };
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

function keySetting(name) {
    return "Set " + name + " key in Settings > Jarvis.";
}

function readyAction(mode, keys) {
    if (mode === "hold") return keys.talk === null ? keySetting("Talk") : "Hold " + keys.talk + " and speak.";
    if (mode === "toggle") return keys.talk === null ? keySetting("Talk") : "Press " + keys.talk + " to start talking.";
    return keys.talk === null ? "Say Hey Jarvis, or set Talk key in Settings > Jarvis."
        : "Say Hey Jarvis, or press " + keys.talk + ".";
}

function stopAction(keys) {
    return keys.stop === null ? keySetting("Stop") : "Press " + keys.stop + " to stop.";
}

function confirmAction(keys) {
    return keys.confirm === null ? "Confirm on screen, or set Confirm key in Settings > Jarvis."
        : "Confirm on screen, or press " + keys.confirm + ".";
}

// The last tooltip line names what a click does to MUTEON, the mute region
// the click toggles, whatever state the icon shows.
function clickLine(muteOn, keys) {
    var verb = muteOn ? "unmute" : "mute";
    return keys.mute === null ? "Click, or set Mute key in Settings > Jarvis, to " + verb + "."
        : "Click or press " + keys.mute + " to " + verb + ".";
}

function look(state, title, details, muteOn, keys) {
    var out = LOOKS[state];
    var lines = details.slice();
    if (state !== "muted") lines.push(clickLine(muteOn, keys));
    return { state: state, icon: out.icon, tone: out.tone,
        tooltip: title, tooltipDetails: lines };
}

function textLook(state, text, muteOn, keys) {
    return look(state, text.title, [text.action], muteOn, keys);
}

// The widget's { state, icon, tone, tooltip, tooltipDetails } for VALUES,
// the plugin's status values, KEYS, the already-spelled effective shortcut
// keys, and MODE, the talk mode. A key the service has not published yet is
// undefined.
function view(values, keys, mode) {
    var effectiveKeys = shortcutKeys(keys);
    var effectiveMode = talkMode(mode);
    var daemon = report("daemon", values.daemon, DAEMON_TONES);
    var audio = report("audio", values.audio, AUDIO_TONES);
    var detail = values.detail === undefined ? null : values.detail;
    if (detail !== null && (typeof detail !== "object" || typeof detail.phase !== "string"
            || detail.state === null || typeof detail.state !== "object"))
        refuse("detail", detail);
    var state = detail === null ? null : detail.state;
    var muteOn = state !== null && muted(state.mute);
    var armed = state !== null && state.capture !== null && typeof state.capture === "object" && state.capture.kind === "open" && state.capture.mode === "armed" && detail.phase === "armed";
    if (state !== null && microphoneOpen(state.capture)) return look("listening", armed ? "Jarvis is listening for Hey Jarvis" : "Jarvis is listening",
        [armed ? "Say Hey Jarvis." : "Speak now."], muteOn, effectiveKeys);
    if (daemon !== null && daemon.tone === "danger") return textLook("problem", DAEMON_TEXT, muteOn, effectiveKeys);
    if (detail !== null && detail.phase === "error") return textLook("problem", faultText(state.fault), muteOn, effectiveKeys);
    if (audio !== null && audio.tone === "danger") return textLook("problem", AUDIO_TEXT, muteOn, effectiveKeys);
    if (state === null) return textLook("loading", GATE_TEXT.starting, muteOn, effectiveKeys);
    var down = gateDown(state.gate);
    if (down && state.gate.reason === "starting") return textLook("loading", GATE_TEXT.starting, muteOn, effectiveKeys);
    if (muteOn) return look("muted", "Jarvis is muted", [clickLine(true, effectiveKeys)], muteOn, effectiveKeys);
    // No voice or setup state reads over a home folder the daemon refuses.
    if (down && state.gate.reason === "unconfigured" && homeRefused(values)) return textLook("off", homeText(values), muteOn, effectiveKeys);
    if (down && state.gate.reason === "unconfigured" && setupChecking(values))
        return look("loading", "Jarvis is checking setup", ["Wait for the check to finish."], muteOn, effectiveKeys);
    if ((!down || state.gate.reason === "unconfigured") && voiceLoading(values))
        return look("loading", "Jarvis is loading its voice", ["Wait for local voice to load."], muteOn, effectiveKeys);
    if (down) return textLook("off", state.gate.reason === "unconfigured" ? unconfiguredText(values) : GATE_TEXT[state.gate.reason], muteOn, effectiveKeys);
    switch (detail.phase) {
    case "thinking":
        return look("working", WORK_TEXT[detail.phase], [stopAction(effectiveKeys)], muteOn, effectiveKeys);
    case "confirming":
        return look("working", WORK_TEXT[detail.phase], [confirmAction(effectiveKeys)], muteOn, effectiveKeys);
    case "acting":
        return look("working", WORK_TEXT[detail.phase], [stopAction(effectiveKeys)], muteOn, effectiveKeys);
    case "speaking":
        return look("speaking", "Jarvis is speaking", [stopAction(effectiveKeys)], muteOn, effectiveKeys);
    case "idle":
        return look("ready", "Jarvis is ready", [readyAction(effectiveMode, effectiveKeys)], muteOn, effectiveKeys);
    default:
        // Listening and armed hold capture open, which reads listening above;
        // down holds the gate down.
        refuse("phase", detail.phase);
    }
}
