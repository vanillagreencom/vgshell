.pragma library
.import qs.Commons 1.0 as Commons
.import "SetupGate.js" as Gate
.import "Session.js" as Session

// One state classification for the widget from the service and Session.
// view() draws status and the existing recovery link. The console owns
// its own information and does not read the bar tooltip.
// Unsupported values refuse instead of manufacturing a ready state.

var LOOKS = {
    "off": { icon: "vgs-letter-j", tone: "neutral", stateDot: "warning", title: "Not set up" },
    "loading": { icon: "vgs-letter-j", tone: "info", stateDot: "info", title: "Starting" },
    "ready": { icon: "vgs-letter-j", tone: "calm", stateDot: "", title: "Ready" },
    "listening": { icon: "vgs-letter-j", tone: "accent", stateDot: "success", title: "Listening" },
    "working": { icon: "vgs-letter-j", tone: "info", stateDot: "info", title: "Working" },
    "speaking": { icon: "vgs-letter-j", tone: "accent", stateDot: "success", title: "Speaking" },
    "muted": { icon: "vgs-letter-j", tone: "neutral", stateDot: "warning", title: "Microphone muted" },
    "problem": { icon: "vgs-letter-j", tone: "danger", stateDot: "danger", title: "Problem" }
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
    "thinking": "Thinking",
    "confirming": "Waiting for confirmation",
    "acting": "Running a task"
};
// The required Setup steps the service publishes (SetupGate.readiness), in
// the engine's order, and what the bar says while one is still to do.
var SETUP_TEXT = [
    ["setupVoice", { title: "Jarvis needs local voice", action: "Set it up in [Setup > Voice](page:vgs.jarvis/Setup/setupVoice)." }],
    ["setupModel", { title: "Jarvis needs an AI model", action: "Choose one in [Account under AI model](page:vgs.jarvis/Settings/brain)." }]
];
// The Voice step's state while the cloud voice has no key, or refused the
// one it has (SetupGate.voiceStep), and what the bar says then.
var VOICE_KEY_TEXT = { title: "Jarvis needs a voice key", action: "Add a key in [Voice key](page:vgs.jarvis/Settings/voiceAccount)." };
var KEY_REFUSED_ACTION = "Add a new key in [Voice key](page:vgs.jarvis/Settings/voiceAccount).";
// What the bar says of a refused key, naming the company of VOICE, the
// chosen cloud voice (AccountProviders.cloudVoice); null once the user has
// left the cloud voice whose refusal still stands.
function keyRefusedText(voice) {
    return { title: (voice === null ? "The voice service" : voice.company) + " refused your key", action: KEY_REFUSED_ACTION };
}
// A Session fault's kind of failure, by its keyed reason: the first
// pattern that matches wins. Examples are the producers' own reasons:
// Session's thinking-timeout and device-lost, the engine's keyed brain and
// speech causes (ChainedEngine keyed: brain=stream-error, net=timeout,
// speech=local-ready-timeout), the home folder causes of a conversation's
// first turn (home=link, guidance=home-skills-too-large; a home text over
// its budget is no fault) and Audio's capture and
// playback failures (audio-start: ..., device-probe: ..., playback-busy),
// and a cloud voice whose transport failed.
// A model its app refused carries the model's name (ClaudeCode:
// brain=harness-model-refused model=claude-fable-5-1), and a lost device
// what was missing and what Audio's read held (device-lost target=...).
var MODEL_REFUSED = /^brain=harness-model-refused model=(.*)$/;
function modelFallbackNotice(choice, field) {
    return { title: "Jarvis used another model", tone: "info", icon: "vgs-letter-j",
        message: "The AI app refused " + choice.saved + ". Jarvis answered with " + (choice.used || "the app's default model")
            + ". Your saved choice is unchanged. [Choose a model](page:vgs.jarvis/Settings/" + (field || "model") + ")." };
}
var FAULT_KINDS = [
    [/^thinking-timeout$/, "slow"],
    [/^live=key-refused$/, "keyRefused"],
    [/^device-lost /, "device"],
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
// folder fault opens the Home folder step, whose row links each file to
// check: Jarvis reads the folder again at the next request. A refused model asks for another: a changed model clears the
// fault, and its title ends with the model's name. A dictation fault, the
// core's recording refused or failed, clears at the next Talk.
var RESTART = "Turn Jarvis off and on again in [Settings > Jarvis](page:vgs.jarvis/Settings).";
var FAULT_TEXT = {
    "slow": { title: "The AI model took too long to answer", action: RESTART },
    "device": { title: "The microphone or speaker is gone", action: "Connect it again, or choose another under [Audio in Settings > Jarvis](page:vgs.jarvis/Settings)." },
    // The local voice hears the system default microphone, as dictation does.
    "defaultDevice": { title: "The microphone or speaker is gone", action: "Connect it again, or choose another default microphone in [System > Sound](page:vgs.sound)." },
    "home": { title: "Jarvis cannot use the home folder", action: "See what to change in [Setup > Home folder](page:vgs.jarvis/Setup/setupHome)." },
    "brain": { title: "The AI model did not answer", action: RESTART },
    "model": { title: "The AI app cannot use the model", action: "Choose another model under [AI model in Settings > Jarvis](page:vgs.jarvis/Settings)." },
    "localVoice": { title: "Local voice did not get ready in time", action: "Turn Jarvis off and on again, or set it up again in [Settings > Jarvis](page:vgs.jarvis/Setup)." },
    "voice": { title: "Local voice stopped working", action: RESTART },
    "elevenlabs": { title: "ElevenLabs did not speak the reply", action: "Check your ElevenLabs key and its credits, then turn Jarvis off and on again in [Settings > Jarvis](page:vgs.jarvis/Settings)." },
    "dictationBusy": { title: "Voice is recording", action: "Talk to Jarvis again when Voice stops recording." },
    "dictation": { title: "Dictation did not record", action: "Check dictation in [Settings > Voice](page:vgs.voice/Setup), then talk again." },
    "audio": { title: "The microphone or speaker stopped working", action: RESTART },
    // A cloud voice refused the key at its handshake; the next key clears it.
    "keyRefused": { title: "The voice service refused your key", action: KEY_REFUSED_ACTION },
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
// names; CAPS is ShortcutLabels.keyCaps, which the callers' qs.Ui import holds.
// A name absent from the map is no key in effect: the nested smoke
// (jarvis-bubble row, 2026-10-10) read an empty map while the plugin is
// enabled or disabled, before the registry holds its binds.
function spelledKeys(keys, caps) {
    var out = {};
    var names = ["talk", "voice-mute", "stop", "confirm", "deny", "console"];
    for (var i = 0; i < names.length; i++) {
        var key = keys === null ? null : keys[names[i]];
        out[names[i]] = key === null || key === undefined ? null : caps(key).join("+");
    }
    return out;
}

// Whether CAPTURE, Session's capture region, holds the microphone.
function microphoneOpen(capture) {
    switch (capture === null || typeof capture !== "object" ? undefined : capture.kind) {
    case "closed": return false;
    case "opening": case "open": case "closing": return true;
    default: refuse("capture", capture);
    }
}

// The service's current system input reading. Absence is the initial
// unpublished observation; an unbound or missing node stays unknown.
function microphoneMuted(value) {
    if (value === undefined) return null;
    if (value !== null && value.kind === "unavailable") return null;
    if (value === null || value.kind !== "ready" || typeof value.muted !== "boolean") refuse("microphoneMute", value);
    return value.muted;
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
// microphone, not the Microphone setting. VOICE (keyRefusedText) names
// the company of a refused key.
function faultText(fault, engine, voice) {
    var kind = faultKind(fault);
    if (kind === "keyRefused") return keyRefusedText(voice);
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
// A refused key reads as a problem before this (stateView).
function unconfiguredText(values) {
    var voice = values.setupVoice;
    if (voice && voice.tone === "warning" && voice.action === "key") return VOICE_KEY_TEXT;
    for (var i = 0; i < SETUP_TEXT.length; i++) {
        var step = values[SETUP_TEXT[i][0]];
        if (step && step.tone === "warning" && offered(step) && step.hint && timedOut(step))
            return { title: SETUP_TEXT[i][1].title, action: step.hint };
        // A step's chip word is no title: the bar names what Jarvis needs.
        if (step && step.tone === "warning" && !offered(step) && step.hint)
            return { title: step.text === Gate.TO_DO ? SETUP_TEXT[i][1].title : step.text, action: step.hint };
        if (step !== undefined && step !== null && offered(step)) return SETUP_TEXT[i][1];
    }
    return GATE_TEXT.unconfigured;
}

function setupChecking(values) {
    var checking = false;
    for (var i = 0; i < SETUP_TEXT.length; i++) {
        var step = values[SETUP_TEXT[i][0]];
        if (!step || offered(step) || (step.tone !== "info" && step.tone !== "ok")) return false;
        if (step.tone === "info") checking = true;
    }
    return checking;
}

function voiceLoading(values) {
    var voice = values.setupVoice;
    var model = values.setupModel;
    return !!voice && voice.tone === "info" && !offered(voice)
        && !!model && model.tone === "ok" && !offered(model);
}

function menuEntries(micMuted, voiceMuted, hidden, hideBlock) {
    return [
        { label: voiceMuted ? "Unmute Jarvis's voice" : "Mute Jarvis's voice", icon: voiceMuted ? "volume-2" : "volume-x", intent: "voice-mute" },
        { label: micMuted === true ? "Unmute microphone" : "Mute microphone", icon: micMuted === true ? "mic-off" : "mic", intent: "microphone-mute",
            disabledReason: micMuted === null ? "Connect a microphone or choose one in Sound" : "" },
        { label: "Stop Jarvis", icon: "square", intent: "stop" },
        { label: "New conversation", icon: "message-circle-plus", intent: "new-conversation" },
        { label: hidden ? "Show Jarvis" : "Hide Jarvis", icon: hidden ? "eye" : "eye-off", intent: hidden ? "show" : "hide",
            disabledReason: hidden ? "" : hideBlock === "indicator"
                ? "Show the Jarvis widget in the bar on the focused screen first"
                : hideBlock === "not-ready" ? "Wait for Jarvis to start" : "" },
        { label: "Key hints", icon: "keyboard", page: "vgs.jarvis", tab: "Settings/Keys" }
    ];
}

function conversationResetNotice(reason) {
    if (["requested", "turn-limit"].indexOf(reason) === -1) refuse("conversation-reset", reason);
    return { title: "New conversation", tone: "info", icon: "message-circle-plus",
        message: reason === "turn-limit"
            ? "Jarvis reached this conversation's memory limit and started fresh. Your new message is still being answered. Earlier messages remain in the console's History."
            : "Jarvis started a fresh conversation. Earlier messages remain in the console's History." };
}

function look(state, title, action) {
    var style = LOOKS[state];
    var recovery = [];
    if ((state === "problem" || state === "off") && typeof action === "string") {
        var parsed = Commons.PageReference.references(action);
        // Some faults only offer waiting or an automatic retry. Keep that
        // action, with the existing Settings route as its one recovery link.
        if (parsed.links.length === 0)
            parsed = Commons.PageReference.references(action + " Open [Settings > Jarvis](page:vgs.jarvis/Settings).");
        var first = parsed.links[0];
        recovery.push(parsed.text.slice(0, first.start) + first.reference + parsed.text.slice(first.end));
    }
    return { state: state, icon: style.icon, tone: style.tone, stateDot: style.stateDot,
        tooltip: "Jarvis: " + (title === undefined ? style.title : title), tooltipDetails: recovery };
}

function textLook(state, text) { return look(state, undefined, text.action); }
function reportLook(state, value) { return look(state, undefined, value.hint === undefined ? RESTART : value.hint); }

// One status reading for the bar. Key hints and the console's model and
// voice information belong to their own views.
function view(values, voice) {
    var out = stateView(values, voice);
    var detail = values.detail;
    if (detail !== undefined && detail !== null && detail.state.visibility.kind === "hidden") {
        out.icon = "vgs-letter-j-hidden";
        out.tooltip += " (hidden)";
    }
    return out;
}

function stateView(values, voice) {
    var daemon = report("daemon", values.daemon, DAEMON_TONES);
    var audio = report("audio", values.audio, AUDIO_TONES);
    var detail = values.detail === undefined ? null : values.detail;
    if (detail !== null && (typeof detail !== "object" || typeof detail.phase !== "string"
            || detail.state === null || typeof detail.state !== "object")) refuse("detail", detail);
    var state = detail === null ? null : detail.state;
    var micMuted = microphoneMuted(values.microphoneMute) === true;
    if (state !== null && microphoneOpen(state.capture)) return look(micMuted ? "muted" : "listening");
    // Demand draws the badge before admission; otherwise a hidden startup
    // waits for a badge that itself waits for the microphone.
    if (state !== null && Session.captureWanted(state)) return look(micMuted ? "muted" : "listening");
    if (daemon !== null && (daemon.tone === "danger" || daemon.tone === "warning" && daemon.hint !== undefined)) return reportLook("problem", daemon);
    if (detail !== null && detail.phase === "error") return textLook("problem", faultText(state.fault, state.engine.kind, voice));
    if (audio !== null && audio.tone === "danger") return textLook("problem", AUDIO_TEXT);
    if (state === null) return textLook("loading", GATE_TEXT.starting);
    var down = gateDown(state.gate);
    if (down && state.gate.reason === "starting") return textLook("loading", GATE_TEXT.starting);
    if (micMuted) return look("muted");
    if (down && state.gate.reason === "unconfigured" && homeRefused(values)) return textLook("off", homeText(values));
    if (down && state.gate.reason === "unconfigured" && setupChecking(values)) return look("loading", "Checking setup");
    if ((!down || state.gate.reason === "unconfigured") && voiceLoading(values)) return look("loading",
        values.setupVoice && values.setupVoice.text === Gate.SETTING_UP.text ? "Setting up" : "Loading");
    if (down && state.gate.reason === "unconfigured" && values.setupVoice && values.setupVoice.text === Gate.KEY_REFUSED) return textLook("problem", keyRefusedText(voice));
    if (down) {
        if (state.gate.reason === "unconfigured") return textLook("off", unconfiguredText(values));
        if (state.gate.reason === "node") return textLook("off", GATE_TEXT.node);
        return look("off", state.gate.reason === "locked" ? "Screen locked" : "Checking screen lock");
    }
    switch (detail.phase) {
    case "thinking": case "confirming": case "acting": return look("working", WORK_TEXT[detail.phase]);
    case "speaking": return look("speaking");
    case "idle": return look("ready");
    default: refuse("phase", detail.phase);
    }
}

// Whether conversation row ROW is the answer {gen, at} a reply card names.
function isAnswer(row, answer) {
    return answer !== null && row.role === "assistant" && row.gen === answer.gen && row.at === answer.at;
}

// Whether Jarvis has finished the turn in STATE: its turn no longer thinks
// and its words are no longer spoken. A running tool and a held request run
// inside the thinking turn, whose phase reads acting or confirming, and keep
// its caption open, so its words are not the whole answer yet.
function turnSettled(state) {
    return state.turn.kind !== "thinking" && state.turn.kind !== "cancelling" && Session.phaseOf(state) !== "speaking";
}

// What Jarvis's reply card under the bar J shows (Service.qml), or null:
// the card's whole decision, which the card only draws. While Jarvis Voice
// is muted or the orb is hidden: a fault in its plain words (`fault`,
// {title, action}), or the newest row of conversation SESSION when it is
// Jarvis's, drawn as the words Jarvis speaks while the voice speaks
// CAPTION, the transcript status (`follow`), or as the answer otherwise.
// `key` names one card, so a new answer replaces it; `answer` is the row
// the console opens at, null for a fault; `settled` is whether the turn has
// finished, when the card's hold may start. VOICE is the cloud voice the
// fault words name (AccountProviders.cloudVoice).
function replyCard(log, state, session, caption, voice) {
    if (state === null || !Array.isArray(log)) return null;
    var muted = state.voiceMute.kind === "on";
    if (!muted && state.visibility.kind !== "hidden") return null;
    var phase = Session.phaseOf(state);
    if (phase === "error") {
        var words = faultText(state.fault, state.engine.kind, voice);
        return { key: "fault:" + state.gen + ":" + state.fault.reason, answer: null, mode: "fault",
            fault: { title: words.title, action: words.action }, settled: true };
    }
    var rows = log.filter(function (row) { return row.session === session; });
    var last = rows.length === 0 ? null : rows[rows.length - 1];
    if (last === null || last.role !== "assistant") return null;
    var speaking = !muted && phase === "speaking" && caption !== null && caption.role === "assistant" && caption.gen === last.gen;
    return { key: last.gen + ":" + last.at, answer: { gen: last.gen, at: last.at }, mode: speaking ? "follow" : "answer",
        fault: null, settled: turnSettled(state) };
}
