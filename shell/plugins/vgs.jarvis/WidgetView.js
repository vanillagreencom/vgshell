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
// An offered setup step whose state names its own result, local voice
// that timed out, keeps its setup title and shows its hint while Jarvis is
// off; a ready Setup summary's caution shows under ready.
// A tone is `calm` or a Theme.color state role, `neutral` being textMuted.
// The Jarvis session's reading (`jarvisSession`, SetupGate.sessionRecord)
// adds to the state's tooltip: its model, since when it runs, and each step
// of a resume after a machine restart. While the Resume offer stands, the
// tooltip names it first and `click` is "resume": a click resumes, and the
// Mute key alone mutes. Else `click` is "mute".
// A value outside the shapes the service and Session.js produce throws a
// keyed error; nothing falls back.

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
    "unconfigured": { title: "Jarvis is not set up", action: "Open [Settings > Jarvis](page:vgs.jarvis/Setup)." },
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
    ["setupVoice", { title: "Jarvis needs local voice", action: "Set it up in [Settings > Jarvis](page:vgs.jarvis/Setup)." }],
    ["setupModel", { title: "Jarvis needs an AI model", action: "Choose one under [AI model in Settings > Jarvis](page:vgs.jarvis/Settings)." }]
];
// A Session fault's kind of failure, by its keyed reason: the first
// pattern that matches wins. Examples are the producers' own reasons:
// Session's thinking-timeout and device-lost, the engine's keyed brain and
// speech causes (ChainedEngine keyed: brain=stream-error, net=timeout,
// speech=local-ready-timeout), the home folder causes of a conversation's
// first turn (home=link, guidance=home-skills-too-large; a home text over
// its budget is no fault) and Audio's capture and
// playback failures (audio-start: ..., device-probe: ..., playback-busy).
// A model its app refused carries the model's name (ClaudeCode:
// brain=harness-model-refused model=claude-fable-5-1).
var MODEL_REFUSED = /^brain=harness-model-refused model=(.*)$/;
var FAULT_KINDS = [
    [/^thinking-timeout$/, "slow"],
    [/^device-lost$/, "device"],
    [/^(home=|guidance=home-)/, "home"],
    [MODEL_REFUSED, "model"],
    [/^(brain|net)=/, "brain"],
    [/^speech=local-ready-timeout$/, "localVoice"],
    [/^speech=dictation-busy$/, "dictationBusy"],
    [/^speech=dictation-/, "dictation"],
    [/^speech=/, "voice"],
    // The ElevenLabs voice fails a reply's playback with its own keyed cause
    // (ElevenLabs.js), which Audio carries behind its source prefix.
    [/^playback-source: jarvis: speech=elevenlabs-/, "elevenlabs"],
    [/^(audio-start|device-probe|capture|playback)/, "audio"]
];
// What the bar and the bubble say of each kind: what went wrong, then what
// to do. Only a changed device setting or a restart clears a fault, so a
// device fault asks for a device and every other for a restart. A home
// folder fault asks for the folder: Jarvis reads it again at the next
// request. A refused model asks for another: a changed model clears the
// fault, and its title ends with the model's name. A dictation fault, the
// core's recording refused or failed, clears at the next Talk.
var RESTART = "Turn Jarvis off and on again in [Settings > Jarvis](page:vgs.jarvis/Settings).";
var FAULT_TEXT = {
    "slow": { title: "The AI model took too long to answer", action: RESTART },
    "device": { title: "The microphone or speaker is gone", action: "Connect it again, or choose another under [Audio in Settings > Jarvis](page:vgs.jarvis/Settings)." },
    // The local voice hears the system default microphone, as dictation does.
    "defaultDevice": { title: "The microphone or speaker is gone", action: "Connect it again, or choose another default microphone in [System > Sound](page:vgs.sound)." },
    "home": { title: "Jarvis cannot use the home folder", action: "Check AGENTS.md, MEMORY.md and the skills in the folder, or [choose another Home folder](page:vgs.jarvis/Settings)." },
    "brain": { title: "The AI model did not answer", action: RESTART },
    "model": { title: "The AI app cannot use the model", action: "Choose another model under [AI model in Settings > Jarvis](page:vgs.jarvis/Settings)." },
    "localVoice": { title: "Local voice did not get ready in time", action: "Turn Jarvis off and on again, or set it up again in [Settings > Jarvis](page:vgs.jarvis/Setup)." },
    "voice": { title: "Local voice stopped working", action: RESTART },
    "elevenlabs": { title: "ElevenLabs did not speak the reply", action: "Check your ElevenLabs key and its credits, then turn Jarvis off and on again in [Settings > Jarvis](page:vgs.jarvis/Settings)." },
    "dictationBusy": { title: "Voice is recording", action: "Talk to Jarvis again when Voice stops recording." },
    "dictation": { title: "Dictation did not record", action: "Check dictation in [Settings > Voice](page:vgs.voice/Setup), then talk again." },
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
    if (value.lines !== undefined && (!Array.isArray(value.lines) || value.lines.some(function (line) { return typeof line !== "string"; })))
        refuse(name, value);
    if (value.hint !== undefined && typeof value.hint !== "string") refuse(name, value);
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
// ENGINE is Session's engine word: a dictation engine hears the default
// microphone, not the Microphone setting.
function faultText(fault, engine) {
    var kind = faultKind(fault);
    if (kind === "device" && engine === "dictation") kind = "defaultDevice";
    if (kind === "model") return { title: FAULT_TEXT.model.title + " " + MODEL_REFUSED.exec(fault.reason)[1], action: FAULT_TEXT.model.action };
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

// The Voice step's state while local voice did not get ready in time
// (SetupGate.TIMED_OUT): set up, so its hint, not Set it up, is the action.
function timedOut(step) {
    return step.text === "Timed out";
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
    return { title: values.setupHome.text, action: values.setupHome.hint };
}

// What the bar says while the gate is down unconfigured: the first
// required step VALUES still holds to do, as SetupGate offers its action.
function unconfiguredText(values) {
    for (var i = 0; i < SETUP_TEXT.length; i++) {
        var step = values[SETUP_TEXT[i][0]];
        if (step && step.tone === "warning" && offered(step) && step.hint && timedOut(step))
            return { title: SETUP_TEXT[i][1].title, action: step.hint };
        if (step && step.tone === "warning" && !offered(step) && step.hint)
            return { title: step.text, action: step.hint };
        if (step !== undefined && step !== null && offered(step)) return SETUP_TEXT[i][1];
    }
    return GATE_TEXT.unconfigured;
}

// The caution of a ready Setup summary: SetupGate gives a ready summary a
// hint only for a cause that leaves Jarvis taking requests.
function setupCaution(values) {
    var setup = values.setup;
    return !!setup && setup.tone === "ok" && typeof setup.hint === "string" ? setup.hint : null;
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

// The daemon has not answered for the voice: no status yet, Checking or
// Loading. A ready voice's microphone check row is info too, and offers its
// action.
function voicePending(values) {
    var voice = values.setupVoice;
    return !voice || (voice.tone === "info" && !offered(voice));
}

function keySetting(name) {
    return "Set " + name + " key in [Settings > Jarvis > Keys](page:vgs.jarvis/Keys).";
}

function readyAction(mode, keys) {
    if (mode === "hold") return keys.talk === null ? keySetting("Talk") : "Hold " + keys.talk + " and speak.";
    if (mode === "toggle") return keys.talk === null ? keySetting("Talk") : "Press " + keys.talk + " to start talking.";
    return keys.talk === null ? "Say Hey Jarvis, or set [Talk key in Settings > Jarvis](page:vgs.jarvis/Keys)."
        : "Say Hey Jarvis, or press " + keys.talk + ".";
}

function stopAction(keys) {
    return keys.stop === null ? keySetting("Stop") : "Press " + keys.stop + " to stop.";
}

function confirmAction(keys) {
    return keys.confirm === null ? "Confirm on screen, or set [Confirm key in Settings > Jarvis](page:vgs.jarvis/Keys)."
        : "Confirm on screen, or press " + keys.confirm + ".";
}

// The last tooltip line names what a click does to MUTEON, the mute region
// the click toggles, whatever state the icon shows.
function clickLine(muteOn, keys) {
    var verb = muteOn ? "unmute" : "mute";
    return keys.mute === null ? "Click, or set [Mute key in Settings > Jarvis](page:vgs.jarvis/Keys), to " + verb + "."
        : "Click or press " + keys.mute + " to " + verb + ".";
}

// A tooltip line is a sentence: one taken from a status hint, which ends
// with no full stop while it is one sentence, takes one here.
function line(text) {
    return /\.$/.test(text) ? text : text + ".";
}

function look(state, title, details, muteOn, keys) {
    var out = LOOKS[state];
    var lines = details.map(line);
    if (state !== "muted") lines.push(clickLine(muteOn, keys));
    return { state: state, icon: out.icon, tone: out.tone,
        tooltip: title, tooltipDetails: lines };
}

function textLook(state, text, muteOn, keys) {
    return look(state, text.title, [text.action], muteOn, keys);
}

// A report's lines hold its keyed cause for the Daemon row; the tooltip
// says its title and hint.
function reportLook(state, report, muteOn, keys) {
    return look(state, report.text, [report.hint === undefined ? RESTART : report.hint], muteOn, keys);
}

// The Resume offer's words. A step's kind names it in the tooltip.
var RESUME_TITLE = "Resume Jarvis from before the restart";
var RESUME_CLICK = "Click to resume the Jarvis session, then each overseer and lane it ran, one at a time.";
var RESUME_UNLOCK = { "1password": "Resume asks you once to unlock 1Password first." };
var STEP_NAMES = {
    "delegate": function () { return "the Jarvis session"; },
    "overseer": function (name) { return "overseer " + name; },
    "lane": function (name) { return "lane " + name; }
};

// VALUE, the `jarvisSession` status, or null while the service has
// published none.
function sessionReading(value) {
    if (value === undefined || value === null) return null;
    var text = function (field) { return field === null || typeof field === "string"; };
    if (typeof value !== "object" || !text(value.model) || !text(value.since) || !Array.isArray(value.steps)
            || (value.offer !== null && (typeof value.offer !== "object" || (value.offer.unlock !== null && !hasOwn(RESUME_UNLOCK, value.offer.unlock)))))
        refuse("jarvisSession", value);
    for (var i = 0; i < value.steps.length; i++) {
        var step = value.steps[i];
        if (step === null || typeof step !== "object" || !hasOwn(STEP_NAMES, step.kind) || typeof step.name !== "string"
                || ["pending", "resumed", "failed"].indexOf(step.outcome) === -1 || !text(step.cause))
            refuse("jarvisSession", value);
    }
    return value;
}

// One tooltip line for STEP, a resume step.
function stepLine(step) {
    var name = STEP_NAMES[step.kind](step.name);
    if (step.outcome === "pending") return "Waiting to resume " + name + ".";
    if (step.outcome === "resumed") return "Resumed " + name + ".";
    return "Could not resume " + name + (step.cause === null || step.cause === "" ? "." : ": " + line(step.cause));
}

// What the Mute key does while a click resumes.
function keyLine(muteOn, keys) {
    var action = muteOn ? "unmute" : "mute";
    return keys.mute === null ? "Set [Mute key in Settings > Jarvis](page:vgs.jarvis/Keys) to " + action + "."
        : "Press " + keys.mute + " to " + action + ".";
}

// The widget's { state, icon, tone, tooltip, tooltipDetails, click } for
// VALUES, the plugin's status values, KEYS, the already-spelled effective
// shortcut keys, and MODE, the talk mode. A key the service has not
// published yet is undefined.
function view(values, keys, mode) {
    var base = stateView(values, keys, mode);
    var session = sessionReading(values.jarvisSession);
    var out = { state: base.state, icon: base.icon, tone: base.tone, tooltip: base.tooltip,
        tooltipDetails: base.tooltipDetails, click: "mute" };
    if (session === null) return out;
    // The state's last line names what a click does (clickLine).
    var details = base.tooltipDetails.slice(0, -1);
    if (session.offer !== null) {
        var detail = values.detail === undefined ? null : values.detail;
        var muteOn = detail !== null && muted(detail.state.mute);
        out.tooltip = RESUME_TITLE;
        out.tooltipDetails = [RESUME_CLICK].concat(session.offer.unlock === null ? [] : [RESUME_UNLOCK[session.offer.unlock]],
            [line(base.tooltip)], details, [keyLine(muteOn, shortcutKeys(keys))]);
        out.click = "resume";
        return out;
    }
    var running = [];
    if (session.model !== null) running.push("Jarvis session model: " + session.model + ".");
    if (session.since !== null) running.push("Jarvis session running since " + session.since + ".");
    out.tooltipDetails = details.concat(running, session.steps.map(stepLine), base.tooltipDetails.slice(-1));
    return out;
}

// The state's look, without the Jarvis session's reading.
function stateView(values, keys, mode) {
    var effectiveKeys = shortcutKeys(keys);
    var effectiveMode = talkMode(mode);
    var daemon = report("daemon", values.daemon, DAEMON_TONES);
    var audio = report("audio", values.audio, AUDIO_TONES);
    var detail = values.detail === undefined ? null : values.detail;
    if (detail !== null && (typeof detail !== "object" || typeof detail.phase !== "string"
            || detail.state === null || typeof detail.state !== "object"
            || (detail.brain !== undefined && typeof detail.brain !== "string")))
        refuse("detail", detail);
    var state = detail === null ? null : detail.state;
    var brain = detail === null || detail.brain === undefined ? "" : detail.brain;
    function withBrain(value) {
        if (brain === "") return value;
        return { state: value.state, icon: value.icon, tone: value.tone, tooltip: value.tooltip,
            tooltipDetails: ["AI model: " + brain].concat(value.tooltipDetails) };
    }
    var muteOn = state !== null && muted(state.mute);
    // The wake-word capture, from its opening: Session's phase reads armed
    // only once it is open.
    var armed = state !== null && state.capture !== null && typeof state.capture === "object" && state.capture.mode === "armed"
        && (state.capture.kind === "opening" || (state.capture.kind === "open" && detail.phase === "armed"));
    var followUp = state !== null && state.capture !== null && typeof state.capture === "object" && state.capture.mode === "follow-up"
        && (state.capture.kind === "opening" || state.capture.kind === "open");
    // The local sidecar drops every wake frame until its voice is ready, so
    // an armed capture over a pending voice reads loading below.
    if (state !== null && !(armed && voicePending(values)) && microphoneOpen(state.capture)) return withBrain(look("listening",
        armed ? "Jarvis is listening for Hey Jarvis" : followUp ? "Jarvis is listening for a follow-up" : "Jarvis is listening",
        [armed ? "Say Hey Jarvis." : followUp ? "Speak now. No wake word needed." : "Speak now."], muteOn, effectiveKeys));
    if (daemon !== null && daemon.tone === "danger") return withBrain(reportLook("problem", daemon, muteOn, effectiveKeys));
    if (daemon !== null && daemon.tone === "warning" && daemon.hint !== undefined) return withBrain(reportLook("problem", daemon, muteOn, effectiveKeys));
    if (detail !== null && detail.phase === "error") return withBrain(textLook("problem", faultText(state.fault, state.engine.kind), muteOn, effectiveKeys));
    if (audio !== null && audio.tone === "danger") return withBrain(textLook("problem", AUDIO_TEXT, muteOn, effectiveKeys));
    if (state === null) return textLook("loading", GATE_TEXT.starting, muteOn, effectiveKeys);
    var down = gateDown(state.gate);
    if (down && state.gate.reason === "starting") return withBrain(textLook("loading", GATE_TEXT.starting, muteOn, effectiveKeys));
    if (muteOn) return withBrain(look("muted", "Jarvis is muted", [clickLine(true, effectiveKeys)], muteOn, effectiveKeys));
    // No voice or setup state reads over a home folder the daemon refuses.
    if (down && state.gate.reason === "unconfigured" && homeRefused(values)) return withBrain(textLook("off", homeText(values), muteOn, effectiveKeys));
    if (down && state.gate.reason === "unconfigured" && setupChecking(values))
        return withBrain(look("loading", "Jarvis is checking setup", ["Wait for the check to finish."], muteOn, effectiveKeys));
    if ((!down || state.gate.reason === "unconfigured") && (armed || voiceLoading(values)))
        return withBrain(look("loading", "Jarvis is loading its voice", ["Wait for local voice to load."], muteOn, effectiveKeys));
    if (down) return withBrain(textLook("off", state.gate.reason === "unconfigured" ? unconfiguredText(values) : GATE_TEXT[state.gate.reason], muteOn, effectiveKeys));
    switch (detail.phase) {
    case "thinking":
        return withBrain(look("working", WORK_TEXT[detail.phase], [stopAction(effectiveKeys)], muteOn, effectiveKeys));
    case "confirming":
        return withBrain(look("working", WORK_TEXT[detail.phase], [confirmAction(effectiveKeys)], muteOn, effectiveKeys));
    case "acting":
        return withBrain(look("working", WORK_TEXT[detail.phase], [stopAction(effectiveKeys)], muteOn, effectiveKeys));
    case "speaking":
        return withBrain(look("speaking", "Jarvis is speaking", [stopAction(effectiveKeys)], muteOn, effectiveKeys));
    case "idle":
        var hint = setupCaution(values);
        return withBrain(look("ready", "Jarvis is ready", hint === null ? [readyAction(effectiveMode, effectiveKeys)]
            : [readyAction(effectiveMode, effectiveKeys), hint], muteOn, effectiveKeys));
    default:
        // Listening and armed hold capture open, which reads listening above;
        // down holds the gate down.
        refuse("phase", detail.phase);
    }
}
