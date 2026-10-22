#!/usr/bin/env node
// What the Jarvis bar widget shows, shell/plugins/vgs.jarvis/WidgetView.js,
// under node: the state, icon, tone and tooltip for the status values the
// service publishes, the keyed refusal of every value outside them, the
// effective keys and the talk mode. Each Session record comes from
// Session.js's own initial state with the named regions set, passes
// Session.validate, and takes its phase from Session.phaseOf, as the daemon
// publishes it. Every expected value is written out by hand, but for the
// words of a fault, the audio problem and a remaining Setup step: those
// come from the view's own table under the kind or step this suite names.
// No process, network or audio is used.
//
// The controls at the end edit a copy of the view, one rule at a time, and
// require this suite to fail an assertion on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const vm = require("node:vm");
const { load: loadLibrary } = require("../bin/lib/qml-library.js");
const pageReference = loadLibrary(path.join(__dirname, "..", "shell", "Commons", "PageReference.js"));
const load = file => loadLibrary(file, { "qs.Commons 1.0": { PageReference: pageReference } });

const dir = path.join(__dirname, "..", "shell", "plugins", "vgs.jarvis");
const Session = load(path.join(dir, "Session.js"));
const SetupGate = load(path.join(dir, "SetupGate.js"));
const { cloudVoice } = require(path.join(dir, "AccountProviders.js"));
const Lucide = load(path.join(__dirname, "..", "shell", "Ui", "icons", "Lucide.js"));
const KeyNavLogic = load(path.join(__dirname, "..", "shell", "Ui", "foundation", "KeyNavLogic.js"));
const MANIFEST_KEYS = Object.fromEntries(JSON.parse(fs.readFileSync(path.join(__dirname, "..", "shell", "plugins", "vgs.jarvis", "manifest.json"), "utf8"))
    .hyprland.binds.map(bind => [bind.shortcut, bind.key]));
const copy = value => JSON.parse(JSON.stringify(value));
const KEYS = { talk: "Super+Right Alt", mute: "Super+Shift+Right Alt", stop: "Super+Alt+Period", confirm: "Super+Alt+Y", console: "Super+Alt+C" };
const UNBOUND = { talk: null, mute: null, stop: null, confirm: null, console: null };
// The Voice widget's icon, which no Jarvis look takes.
const VOICE_ICON = /iconName: "([a-z0-9-]+)"/.exec(fs.readFileSync(path.join(__dirname, "..", "shell", "plugins", "vgs.voice", "Widget.qml"), "utf8"))[1];

// A detail as the service publishes it: the Session record with REGIONS
// over a raised gate, its phase from Session.phaseOf.
function detail(regions) {
    const s = Object.assign(copy(Session.initial()), { gate: { kind: "up" } }, copy(regions));
    assert.equal(Session.validate(s), true, "fixture is a Session record: " + JSON.stringify(regions));
    return { phase: Session.phaseOf(s), seq: 1, state: s };
}
function named(values, brain) {
    const out = copy(values);
    out.detail.brain = brain;
    return out;
}
const down = reason => ({ gate: { kind: "down", reason } });
const OPEN = { capture: { kind: "open", gen: 1, op: 2, mode: "hold" } };
const CLOSING = { capture: { kind: "closing", gen: 1, op: 3 } };
const FOLLOW_UP = { capture: { kind: "open", gen: 1, op: 2, mode: "follow-up" } };
const THINKING = { turn: { kind: "thinking", gen: 1, op: 4, deadline: 70 } };
const MUTED = { mute: { kind: "on" } };
const READY = { tone: "info", text: "Jarvis is ready; microphone is off" };
const DEVICES = { tone: "ok", text: "Device list ready" };
const FLOOR = { tone: "danger", text: "Stopped after a problem. Turn Jarvis off and on again." };
const HELLO_EXPECTED = { title: "Jarvis did not answer in time", action: "Turn Jarvis off and on again in [Settings > Jarvis](page:vgs.jarvis/Settings)." };
const DAEMON_HELLO = SetupGate.startStatus("jarvis: hello=timeout", true);
const FLOOR_HELLO = SetupGate.startStatus("jarvis: hello=timeout", false);
const START_CAUSES = [
    ["jarvis: hello=timeout", "Jarvis did not answer in time", "Turn Jarvis off and on again in [Settings > Jarvis](page:vgs.jarvis/Settings)."],
    ["jarvis: node=20.19.5 need=22", "Jarvis needs Node 22 or later", "Update Node to version 22 or later, then turn Jarvis off and on again in [Settings > Jarvis](page:vgs.jarvis/Settings)."],
    ["jarvis: daemon=exit code=1 status=0", "Jarvis daemon stopped", "Turn Jarvis off and on again in [Settings > Jarvis](page:vgs.jarvis/Settings)."],
    ["jarvis: protocol=identity", "Jarvis message error", "Turn Jarvis off and on again in [Settings > Jarvis](page:vgs.jarvis/Settings)."]
];
const SETTING_CAUSES = [
    ["speech=local-ready-timeout", "off", "Jarvis needs local voice", ["Local voice timed out: [turn Jarvis off and on again, or set it up again](page:vgs.jarvis/Setup).", "Click or press Super+Alt+C to open the console."]],
    ["setup=probe-timeout", "ready", "Ready to talk", ["Tap or hold Super+Right Alt, then speak.", "Jarvis answers, but its check of the local voice did not finish.", "Click or press Super+Alt+C to open the console."]]
];
const OVERFLOW = { tone: "danger", text: "capture-overflow" };
// A ready Setup summary beside a Jarvis session row that cannot start.
const SESSION_FAULT_SUMMARY = SetupGate.sessionSummary({ tone: "ok", text: "Ready" }, { tone: "warning", text: "Cannot start" });
const SESSION_FAULT_LINE = SetupGate.SESSION_FAULT + ".";
const ARMED = { capture: { kind: "open", gen: 1, op: 2, mode: "armed" } };
const setupReadiness = answer => SetupGate.readiness(answer, { kind: "ready", path: "/home/user/Fixture" });
const VOICE_LOADING = setupReadiness({ kind: "answered", causes: ["speech=local-loading"] });
const VOICE_READY = setupReadiness({ kind: "answered", causes: [] });
const VOICE_CHECKING = setupReadiness({ kind: "checking" });
const PROBE_TIMEOUT = setupReadiness({ kind: "answered", causes: ["setup=probe-timeout"] });
const up = (regions, extra) => Object.assign({ daemon: READY, audio: DEVICES, detail: detail(regions) }, extra);

const CLICK = "Click or press Super+Alt+C to open the console.";
const UNMUTE = "Press Super+Shift+Right Alt to unmute.";
const HOLD = "Tap or hold Super+Right Alt, then speak.";
const STOP = "Press Super+Alt+Period to stop.";
const CONFIRM = "Confirm on screen, or press Super+Alt+Y.";
const fault = kind => v => v.FAULT_TEXT[kind];
const retrying = v => v.RETRYING;
const audioText = v => v.AUDIO_TEXT;
const setupStep = key => v => v.SETUP_TEXT.find(([name]) => name === key)[1];
const unconfigured = v => v.GATE_TEXT.unconfigured;
const WITH = (line, details) => v => [line(v).title, [line(v).action].concat(details)];
function expected(row, view) {
    const tip = typeof row[3] === "function" ? row[3](view) : row[3];
    return [row[0], row[1], row[2], tip[0], tip[1]];
}
const tip = (title, details) => [title, details];
// The Setup steps as the service publishes them (SetupGate.readiness).
const TODO = { tone: "warning", text: "To do", lines: ["fixture line"], action: true };
const DONE = { tone: "ok", text: "Done", action: false };
const MODEL_TODO = { tone: "warning", text: "To do", hint: "fixture hint", action: "key" };
const MODEL_SIGN_IN = { tone: "warning", text: "To do", hint: "fixture hint", action: "signIn" };
const MODEL_DONE = { tone: "ok", text: "Done" };
// [label, status values, [state, icon, tone, [tooltip title, detail lines]]].
const CASES = [
    ["nothing published yet", {}, ["loading", "loader", "info", tip("Jarvis is starting", ["Wait for Jarvis to start.", CLICK])]],
    ["starting before the first state", { daemon: { tone: "info", text: "Jarvis is starting" }, detail: null, audio: { tone: "info", text: "Reading devices" } },
        ["loading", "loader", "info", tip("Jarvis is starting", ["Wait for Jarvis to start.", CLICK])]],
    ["restarting", { daemon: DAEMON_HELLO, detail: null },
        ["problem", "circle-alert", "danger", tip(HELLO_EXPECTED.title, ["Jarvis is trying again by itself.", CLICK])]],
    ["mute pending", { daemon: { tone: "warning", text: "Jarvis will mute when it is ready; turning Jarvis off cancels this request" }, detail: null },
        ["loading", "loader", "info", tip("Jarvis is starting", ["Wait for Jarvis to start.", CLICK])]],
    ["ready", up({}), ["ready", "vgs-letter-j", "calm", tip("Ready to talk", [HOLD, CLICK])]],
    ["listening", up(OPEN), ["listening", "audio-lines", "accent", tip("Jarvis is listening", ["Speak now.", CLICK])]],
    ["listening for a follow-up", up(FOLLOW_UP),
        ["listening", "audio-lines", "accent", tip("Jarvis is listening for a follow-up", ["Speak now. No wake word needed.", CLICK])]],
    ["capture opening", up({ capture: { kind: "opening", gen: 1, op: 2, mode: "conversation" } }),
        ["listening", "audio-lines", "accent", tip("Jarvis is listening", ["Speak now.", CLICK])]],
    ["armed before the first setup status", up(ARMED),
        ["loading", "loader", "info", tip("Jarvis is loading its voice", ["Wait for local voice to load.", CLICK])]],
    ["armed while setup is checking", up(ARMED, VOICE_CHECKING),
        ["loading", "loader", "info", tip("Jarvis is loading its voice", ["Wait for local voice to load.", CLICK])]],
    ["armed after a setup probe timeout", up(ARMED, PROBE_TIMEOUT),
        ["listening", "audio-lines", "accent", tip("Jarvis is listening for Hey Jarvis", ["Say Hey Jarvis.", CLICK])]],
    ["armed with its voice step to do", up(ARMED, { setupVoice: TODO, setupModel: MODEL_DONE }),
        ["listening", "audio-lines", "accent", tip("Jarvis is listening for Hey Jarvis", ["Say Hey Jarvis.", CLICK])]],
    ["armed while the voice loads", up(ARMED, VOICE_LOADING),
        ["loading", "loader", "info", tip("Jarvis is loading its voice", ["Wait for local voice to load.", CLICK])]],
    ["armed with its voice ready", up(ARMED, VOICE_READY),
        ["listening", "audio-lines", "accent", tip("Jarvis is listening for Hey Jarvis", ["Say Hey Jarvis.", CLICK])]],
    ["an armed capture opening while the voice loads", up({ capture: { kind: "opening", gen: 1, op: 2, mode: "armed" } }, VOICE_LOADING),
        ["loading", "loader", "info", tip("Jarvis is loading its voice", ["Wait for local voice to load.", CLICK])]],
    ["armed with its voice ready and its microphone not checked", up({ ...ARMED, check: { kind: "ready" } },
        { ...VOICE_READY, setupVoice: SetupGate.voiceCheck(VOICE_READY.setupVoice, { kind: "ready" }) }),
        ["listening", "audio-lines", "accent", tip("Jarvis is listening for Hey Jarvis", ["Say Hey Jarvis.", CLICK])]],
    ["muting while capture closes", up({ mute: { kind: "muting" }, ...CLOSING }),
        ["listening", "audio-lines", "accent", tip("Jarvis is listening", ["Speak now.", CLICK])]],
    ["capture closing after a lock", up({ ...down("locked"), ...CLOSING }),
        ["listening", "audio-lines", "accent", tip("Jarvis is listening", ["Speak now.", CLICK])]],
    ["listening over an audio problem", up(OPEN, { audio: OVERFLOW }),
        ["listening", "audio-lines", "accent", tip("Jarvis is listening", ["Speak now.", CLICK])]],
    ["permanent daemon problem", { daemon: FLOOR_HELLO, detail: null, audio: DEVICES },
        ["problem", "circle-alert", "danger", tip(HELLO_EXPECTED.title, [HELLO_EXPECTED.action, CLICK])]],
    ["Session error", up({ fault: { kind: "error", reason: "thinking-timeout", retry: 0 } }),
        ["problem", "circle-alert", "danger", WITH(fault("slow"), [CLICK])]],
    ["Session retrying a lost device", up({ fault: { kind: "retrying", reason: "device-lost", retry: 1 } }),
        ["problem", "circle-alert", "danger", WITH(retrying, [CLICK])]],
    ["audio fault", up({}, { audio: OVERFLOW }), ["problem", "circle-alert", "danger", WITH(audioText, [CLICK])]],
    ["audio fault before the first state", { daemon: { tone: "info", text: "Jarvis is starting" }, detail: null, audio: OVERFLOW },
        ["problem", "circle-alert", "danger", WITH(audioText, [CLICK])]],
    ["problem over mute", up(MUTED, { audio: OVERFLOW }), ["problem", "circle-alert", "danger", WITH(audioText, [CLICK])]],
    ["Session error while muted", up({ ...MUTED, fault: { kind: "error", reason: "thinking-timeout", retry: 0 } }),
        ["problem", "circle-alert", "danger", WITH(fault("slow"), [CLICK])]],
    ...[["a lost device", "device-lost", "device"], ["a brain stream error", "brain=stream-error", "brain"],
        ["a harness exit", "brain=harness-exit", "brain"], ["a network refusal", "net=timeout", "brain"],
        ["local speech ready timeout", "speech=local-ready-timeout", "localVoice"], ["local speech not ready", "speech=local-not-ready", "voice"],
        ["another speech fault", "speech=live-key-required", "voice"],
        ["a capture start", "audio-start: device-busy", "audio"],
        ["an ElevenLabs reply ElevenLabs refused", "playback-source: jarvis: speech=elevenlabs-http status=401", "elevenlabs"],
        ["another playback source failure", "playback-source: jarvis: speech=local-synthesis-timeout", "audio"],
        ["a device probe", "device-probe: pw-dump-exit", "audio"], ["a busy player", "playback-busy", "audio"],
        ["a home skill set over its entry bound", "guidance=home-skills-too-large", "home"],
        ["a link in the home folder", "home=link", "home"],
        ["a cloud voice that heard only silence", "live=input-silent", "inputSilent"],
        ["a cloud voice that heard no words", "live=unheard", "unheard"],
        ["another cloud voice fault", "live=disconnected code=1006", "other"],
        ["an unexpected engine failure", "engine=unexpected", "other"]].map(([label, reason, kind]) =>
        [label, up({ fault: { kind: "error", reason, retry: 0 } }), ["problem", "circle-alert", "danger", WITH(fault(kind), [CLICK])]]),
    // The local voice records through the core's dictation and hears the
    // system default microphone.
    ...[["a dictation recording Voice holds", "speech=dictation-busy", "dictationBusy"],
        ["a dictation start the core refuses", "speech=dictation-daemon-failed", "dictation"],
        ["a dictation stop that failed", "speech=dictation-failed", "dictation"],
        ["a lost device for the local voice", "device-lost", "defaultDevice"],
        ["the sidecar's own fault", "speech=local-not-ready", "voice"]].map(([label, reason, kind]) =>
        [label, up({ engine: { kind: "dictation" }, fault: { kind: "error", reason, retry: 0 } }),
            ["problem", "circle-alert", "danger", WITH(fault(kind), [CLICK])]]),
    // A model its app refused reads with the model's name, from the reason.
    ["a refused model", up({ fault: { kind: "error", reason: "brain=harness-model-refused model=claude-fable-5-1", retry: 0 } }),
        ["problem", "circle-alert", "danger", WITH(v => ({ title: v.FAULT_TEXT.model.title + " claude-fable-5-1", action: v.FAULT_TEXT.model.action }), [CLICK])]],
    ["muted", up(MUTED), ["muted", "mic-off", "neutral", tip("Jarvis is muted", [UNMUTE, CLICK])]],
    ["muted while locked", up({ ...MUTED, ...down("locked") }), ["muted", "mic-off", "neutral", tip("Jarvis is muted", [UNMUTE, CLICK])]],
    ["muted over a cancelling turn", up({ ...MUTED, turn: { kind: "cancelling", gen: 1, op: 4, deadline: 70 } }),
        ["muted", "mic-off", "neutral", tip("Jarvis is muted", [UNMUTE, CLICK])]],
    ["muting with capture closed", up({ mute: { kind: "muting" } }), ["muted", "mic-off", "neutral", tip("Jarvis is muted", [UNMUTE, CLICK])]],
    ["gate starting", up(down("starting")), ["loading", "loader", "info", tip("Jarvis is starting", ["Wait for Jarvis to start.", CLICK])]],
    ["gate unconfigured, nothing published", up(down("unconfigured")), ["off", "vgs-letter-j", "neutral", WITH(unconfigured, [CLICK])]],
    ["local voice to do", up(down("unconfigured"), { setupVoice: TODO, setupModel: MODEL_TODO }),
        ["off", "vgs-letter-j", "neutral", WITH(setupStep("setupVoice"), [CLICK])]],
    ["the AI model to do", up(down("unconfigured"), { setupVoice: DONE, setupModel: MODEL_TODO }),
        ["off", "vgs-letter-j", "neutral", WITH(setupStep("setupModel"), [CLICK])]],
    ["the AI model to sign in", up(down("unconfigured"), { setupVoice: DONE, setupModel: MODEL_SIGN_IN }),
        ["off", "vgs-letter-j", "neutral", WITH(setupStep("setupModel"), [CLICK])]],
    ["gate node", up(down("node")), ["off", "vgs-letter-j", "neutral", tip("Jarvis needs Node 22 or later", ["Use the requirement notice to install Node.", CLICK])]],
    ["gate lock unknown", up(down("lock-unknown")), ["off", "vgs-letter-j", "neutral", tip("Jarvis is checking the screen lock", ["Wait for the screen lock check.", CLICK])]],
    ["gate locked", up(down("locked")), ["off", "vgs-letter-j", "neutral", tip("Jarvis is off while the screen is locked", ["Unlock the screen to use Jarvis.", CLICK])]],
    ["thinking", up(THINKING), ["working", "brain", "info", tip("Jarvis is thinking", [STOP, CLICK])]],
    ["thinking names the model", named(up(THINKING), "Fable 5.1"), ["working", "brain", "info", tip("Jarvis is thinking", [STOP, "AI model: Fable 5.1", CLICK])]],
    ["cancelling a turn", up({ turn: { kind: "cancelling", gen: 1, op: 4, deadline: 70 } }), ["working", "brain", "info", tip("Jarvis is thinking", [STOP, CLICK])]],
    ["speaking", up({ playback: { kind: "playing", gen: 1, op: 5, source: 4, interruptible: true, admission: { kind: "started" }, deadline: null } }),
        ["speaking", "volume-2", "accent", tip("Jarvis is speaking", [STOP, CLICK])]],
    ["speaking names the model", named(up({ playback: { kind: "playing", gen: 1, op: 5, source: 4, interruptible: true, admission: { kind: "started" }, deadline: null } }), "Fable 5.1"),
        ["speaking", "volume-2", "accent", tip("Jarvis is speaking", [STOP, "AI model: Fable 5.1", CLICK])]],
    ["ready names the model", named(up({}), "Fable 5.1"), ["ready", "vgs-letter-j", "calm", tip("Ready to talk", [HOLD, "AI model: Fable 5.1", CLICK])]],
    // One fact a line: what to do, the AI model, the voice, what a click does.
    ["ready names the model and the voice", named(up({}, { voiceRoute: { tone: "ok", text: "Gemini Live" } }), "Claude Opus 5.5"),
        ["ready", "vgs-letter-j", "calm", tip("Ready to talk", [HOLD, "AI model: Claude Opus 5.5", "Voice: Gemini Live", CLICK])]],
    // A Jarvis session that cannot start: one line, the one link, beside
    // the ready title (SetupGate.sessionSummary).
    ["ready beside a session that cannot start", up({}, { setup: SESSION_FAULT_SUMMARY }),
        ["ready", "vgs-letter-j", "calm", tip("Ready to talk", [HOLD, SESSION_FAULT_LINE, CLICK])]],
    ["a session fault beside an unbound Talk key keeps the first link", up({}, { setup: SESSION_FAULT_SUMMARY }),
        ["ready", "vgs-letter-j", "calm", tip("Ready to talk", ["Set the [Talk key](page:vgs.jarvis/Settings) in the Keys section.", "Jarvis session cannot start.", "Click to open the console."])], UNBOUND],
    ["a refused key names the voice's company", up({ fault: { kind: "error", reason: "live=key-refused", retry: 0 } }, { voiceRoute: { tone: "ok", text: "Gemini Live" } }),
        ["problem", "circle-alert", "danger", tip("Gemini refused your key", ["Add a new key in [Voice key](page:vgs.jarvis/Settings/voiceAccount).", "Voice: Gemini Live", CLICK])], KEYS, cloudVoice("gemini")],
    ["a local voice setup reads as its own loading", up({}, setupReadiness({ kind: "answered", causes: ["speech=local-setting-up"] })),
        ["loading", "loader", "info", tip("Jarvis is setting up its local voice", ["Wait for the setup to finish.", CLICK])]],
    // The Voice step SetupGate words for a refused key is a problem to fix.
    ["a refused key in the Voice step names the voice's company", up(down("unconfigured"), { ...setupReadiness({ kind: "answered", causes: ["speech=live-key-refused"] }),
        setupVoice: SetupGate.voiceStep({ tone: "warning", text: "To do" }, { provider: "gemini", voice: cloudVoice("gemini"), causes: ["speech=live-key-refused"], talk: "", keys: 1, size: "", failure: null }) }),
        ["problem", "circle-alert", "danger", tip("Gemini refused your key", ["Add a new key in [Voice key](page:vgs.jarvis/Settings/voiceAccount).", CLICK])], KEYS, cloudVoice("gemini")],
    ["a refused key under a voice the user since left", up({ fault: { kind: "error", reason: "live=key-refused", retry: 0 } }),
        ["problem", "circle-alert", "danger", tip("The voice service refused your key", ["Add a new key in [Voice key](page:vgs.jarvis/Settings/voiceAccount).", CLICK])]],
    ["confirming", up({ approval: { kind: "held", purpose: "action", gen: 1, op: 6, id: "a1", digest: "d1", deadline: 90, shownAt: null,
        physical: true, text: "Fixture action", tool: "fixture", timeoutMs: 1000, cancellable: false, brain: 4 } }),
        ["working", "brain", "info", tip("Jarvis is waiting for your confirmation", [CONFIRM, CLICK])]],
    ["acting", up({ action: { kind: "running", gen: 1, op: 7, tool: "shell", brain: 4, limit: { kind: "expired" }, cancellation: { kind: "available" } } }),
        ["working", "brain", "info", tip("Jarvis is running a task", [STOP, CLICK])]]
];

function bent(regions, change) {
    const values = up(regions);
    change(values.detail);
    return values;
}
const REFUSALS = [
    ["daemon tone outside its set", { daemon: { tone: "ok", text: "Ready" } }, /^jarvis widget: daemon=\{"tone":"ok","text":"Ready"\} unexpected$/],
    ["daemon without text", { daemon: { tone: "info" } }, /^jarvis widget: daemon=/],
    ["daemon null", { daemon: null }, /^jarvis widget: daemon=null unexpected$/],
    ["daemon hint not text", { daemon: { tone: "warning", text: "Retrying", hint: ["Wait."] } }, /^jarvis widget: daemon=/],
    ["audio tone outside its set", { audio: { tone: "warning", text: "Reading devices" } }, /^jarvis widget: audio=/],
    ["detail not a record", { detail: "idle" }, /^jarvis widget: detail="idle" unexpected$/],
    ["detail without a state", { detail: { phase: "idle", seq: 1, state: null } }, /^jarvis widget: detail=/],
    ["unknown capture", bent({}, d => { d.state.capture = { kind: "ajar" }; }), /^jarvis widget: capture=\{"kind":"ajar"\} unexpected$/],
    ["unknown mute", bent({}, d => { d.state.mute = { kind: "maybe" }; }), /^jarvis widget: mute=/],
    ["unknown gate kind", bent({}, d => { d.state.gate = { kind: "sideways" }; }), /^jarvis widget: gate=/],
    ["unknown gate reason", bent(down("locked"), d => { d.state.gate.reason = "asleep"; }), /^jarvis widget: gate=\{"kind":"down","reason":"asleep"\} unexpected$/],
    ["listening with capture closed", bent({}, d => { d.phase = "listening"; }), /^jarvis widget: phase="listening" unexpected$/],
    ["down with the gate up", bent({}, d => { d.phase = "down"; }), /^jarvis widget: phase="down" unexpected$/],
    ["unknown phase", bent({}, d => { d.phase = "dreaming"; }), /^jarvis widget: phase="dreaming" unexpected$/],
    ["error without a fault", bent({}, d => { d.phase = "error"; }), /^jarvis widget: fault=\{"kind":"none"\} unexpected$/],
    ["keys missing talk", up({}), /^jarvis widget: keys=/, { mute: "M", stop: "S", confirm: "C" }],
    ["keys string instead of record", up({}), /^jarvis widget: keys="keys" unexpected$/, "keys"],
    ["mode outside manifest options", up({}), /^jarvis widget: mode="tap" unexpected$/, KEYS, "tap"]
];

function callView(view, values, keys = KEYS, mode = "hold", voice = null) {
    return view.view(copy(values), copy(keys), mode, voice);
}

function verify(view) {
    const loading = setupReadiness({ kind: "answered", causes: ["speech=local-loading"] });
    const checking = setupReadiness({ kind: "checking" });
    for (const [label, values, want] of [
        ["speech loading", up(down("unconfigured"), loading), ["loading", "loader", "info"]],
        ["loading admitted", up({}, loading), ["loading", "loader", "info"]],
        ["setup checking", up(down("unconfigured"), checking), ["loading", "loader", "info"]],
        ["loading with open microphone", up({ ...down("unconfigured"), ...OPEN }, loading), ["listening", "audio-lines", "accent"]],
        ["loading with daemon danger", up(down("unconfigured"), { ...loading, daemon: FLOOR }), ["problem", "circle-alert", "danger"]],
        ["loading with audio danger", up(down("unconfigured"), { ...loading, audio: OVERFLOW }), ["problem", "circle-alert", "danger"]],
        ["checking setup with Session fault", up({ fault: { kind: "error", reason: "brain=stream-error", retry: 0 } }, loading), ["problem", "circle-alert", "danger"]],
        ["loading while muted", up({ ...down("unconfigured"), ...MUTED }, loading), ["muted", "mic-off", "neutral"]],
        ["loading with missing model", up(down("unconfigured"), setupReadiness({ kind: "answered", causes: ["speech=local-loading", "brain=unselected"] })), ["off", "vgs-letter-j", "neutral"]],
        ["missing command with no setup action", up(down("unconfigured"), { setupVoice: { tone: "warning", action: false }, setupModel: MODEL_DONE }), ["off", "vgs-letter-j", "neutral"]],
        ["missing command while model checks", up(down("unconfigured"), { setupVoice: { tone: "warning", action: false }, setupModel: checking.setupModel }), ["off", "vgs-letter-j", "neutral"]],
        ["checking tone with setup action", up(down("unconfigured"), { setupVoice: { tone: "info", action: true }, setupModel: MODEL_DONE }), ["off", "vgs-letter-j", "neutral"]],
        ["unpublished model while voice checks", up(down("unconfigured"), { setupVoice: loading.setupVoice }), ["off", "vgs-letter-j", "neutral"]],
        ["both steps done with gate down", up(down("unconfigured"), setupReadiness({ kind: "answered", causes: [] })), ["off", "vgs-letter-j", "neutral"]],
        ["loading while locked", up(down("locked"), loading), ["off", "vgs-letter-j", "neutral"]]
    ]) {
        let out;
        assert.doesNotThrow(() => { out = callView(view, values); }, label);
        assert.deepEqual([out.state, out.icon, out.tone], want, label);
    }
    // Ready says how to talk in the one sentence the Voice step and the
    // console say it with (SetupGate.talkHint), in every mode, bound or not.
    for (const mode of ["hold", "toggle", "always"])
        for (const keys of [KEYS, UNBOUND])
            assert.equal(callView(view, up({}), keys, mode).tooltipDetails[0], SetupGate.talkHint(mode, keys.talk) + ".", mode + ": ready names the talk sentence");
    assert.deepEqual(copy(callView(view, up(MUTED), UNBOUND).tooltipDetails.slice(-1)), ["Click to open the console."], "an unbound Console key leaves the click");
    assert.deepEqual([
        callView(view, up({}), UNBOUND, "hold").tooltipDetails[0],
        callView(view, up(THINKING), UNBOUND).tooltipDetails[0],
        callView(view, up({ approval: { kind: "held", purpose: "action", gen: 1, op: 6, id: "a1", digest: "d1", deadline: 90, shownAt: null, physical: true, text: "Fixture action", tool: "fixture", timeoutMs: 1000, cancellable: false, brain: 4 } }), UNBOUND).tooltipDetails[0],
        callView(view, up(MUTED), UNBOUND).tooltipDetails[0]
    ], ["Set the [Talk key](page:vgs.jarvis/Settings) in the Keys section.", "Set Stop key in [Settings > Jarvis > Keys](page:vgs.jarvis/Keys).",
        "Confirm on screen, or set [Confirm key in Settings > Jarvis](page:vgs.jarvis/Keys).", "Unmute Jarvis from its right-click menu."],
        "unbound keys tell the user to set that key");

    // The keys as the widget and the console hand them in: the manifest's
    // default binds spelled by the shell's own KeyNavLogic.
    assert.deepEqual(copy(view.spelledKeys(MANIFEST_KEYS, KeyNavLogic.keyCaps)), KEYS, "the default keys spell as people read them");
    assert.deepEqual(copy(view.spelledKeys(null, KeyNavLogic.keyCaps)), UNBOUND, "no shell reads as no key");
    assert.deepEqual(view.spelledKeys({ ...MANIFEST_KEYS, stop: null }, KeyNavLogic.keyCaps).stop, null, "an unbound key stays unbound");
    assert.deepEqual(copy(view.spelledKeys({}, KeyNavLogic.keyCaps)), UNBOUND, "an absent key reads unbound, not spelled empty");

    assert.equal(view.approvalPrompt(null), null);
    for (const tool of ["files.delete", "apps.open", "harness.files", "filesOther", "fixture"]) {
        for (const purpose of ["action", "release"]) {
            const prompt = view.approvalPrompt({ tool, purpose, text: "A\nBB\nCCC" });
            const file = purpose === "action" && ["files.delete", "apps.open", "harness.files"].includes(tool);
            assert.equal(prompt.filePrompt, file);
            assert.equal(prompt.detail, file);
            assert.deepEqual([prompt.question, prompt.path, prompt.payload].map(value => Buffer.byteLength(value)),
                file ? [1, 2, 3] : [8, 0, 0]);
        }
    }
    const incomplete = view.approvalPrompt({ tool: "files.delete", purpose: "action", text: "A" });
    assert.equal(incomplete.detail, false);
    assert.deepEqual([incomplete.question, incomplete.path, incomplete.payload].map(value => Buffer.byteLength(value)), [1, 0, 0]);
    assert.deepEqual(Object.keys(view.LOOKS).sort(), ["listening", "loading", "muted", "off", "problem", "ready", "speaking", "working"], "the widget states");
    // Jarvis's own J at rest and ready, as on every Jarvis surface; every
    // other state its own icon; none the Voice widget's microphone.
    assert.deepEqual([view.LOOKS.off.icon, view.LOOKS.ready.icon], ["vgs-letter-j", "vgs-letter-j"], "off and ready draw the J");
    const icons = [];
    for (const [state, look] of Object.entries(view.LOOKS)) {
        assert.ok(Object.prototype.hasOwnProperty.call(Lucide.ICONS, look.icon), state + ": icon " + look.icon + " ships");
        assert.notEqual(look.icon, VOICE_ICON, state + ": the icon differs from the Voice widget's");
        if (state !== "off") icons.push(look.icon);
    }
    assert.equal(new Set(icons).size, icons.length, "each state but off has its own icon");
    for (const [label, values, want, keys = KEYS, voice = null] of CASES) {
        let got;
        try {
            const out = callView(view, values, keys, "hold", voice);
            got = [out.state, out.icon, out.tone, out.tooltip, out.tooltipDetails];
        } catch (e) {
            got = "threw: " + e.message;
        }
        assert.deepEqual(copy(got), expected(want, view), label);
        if (typeof got !== "string") assert.equal(/[a-z-]+=[a-z0-9-]/.test(got[3]), false, label + ": no keyed cause on screen");
        if (typeof got !== "string") tooltipRules(label, got[0], got[3], got[4]);
    }
    for (const kind of ["slow", "device", "defaultDevice", "home", "brain", "localVoice", "dictationBusy", "dictation", "voice", "audio", "inputSilent", "keyRefused", "unheard", "other"])
        assert.equal(typeof view.FAULT_TEXT[kind].title === "string" && typeof view.FAULT_TEXT[kind].action === "string", true, kind);
    // The silent microphone's action opens the Microphone field (R24).
    assert.deepEqual([pageReference.parse(view.FAULT_TEXT.inputSilent.action).page, pageReference.parse(view.FAULT_TEXT.inputSilent.action).tab],
        ["vgs.jarvis", "Settings/microphone"], "the silent microphone links its field");
    // A home folder fault's one link opens its Setup row, which links each
    // file to check.
    const home = callView(view, up({ fault: { kind: "error", reason: "home=link", retry: 0 } }, { homePath: "/home/user/Fixture" }));
    assert.deepEqual(copy(pageReference.references(home.tooltipDetails[0]).links.map(link => [link.page, link.tab])),
        [["vgs.jarvis", "Setup/setupHome"]], "the home folder fault links its Setup row");
    tooltipRules("a home folder fault", home.state, home.tooltip, home.tooltipDetails);
    // A step hint that names two files keeps the first as the link.
    const twoFiles = callView(view, up(down("unconfigured"), { ...setupReadiness({ kind: "answered", causes: ["brain=unselected"] }),
        setupHome: { tone: "warning", text: "Cannot use folder", hint: "Check " + pageReference.fileReference("AGENTS.md", "/home/user/Fixture/AGENTS.md")
            + " and the " + pageReference.fileReference("skills folder", "/home/user/Fixture/skills/") } }));
    assert.deepEqual(copy(twoFiles.tooltipDetails.flatMap(text => pageReference.references(text).links.map(link => pageReference.file(link.page)))),
        ["/home/user/Fixture/AGENTS.md"], "a two-file hint keeps one link");
    assert.equal(twoFiles.tooltipDetails.some(text => pageReference.plain(text).includes("and the skills folder")), true, "the second file keeps its words");
    tooltipRules("a two-file hint", twoFiles.state, twoFiles.tooltip, twoFiles.tooltipDetails);
    const words = [view.GATE_TEXT.unconfigured.action, ...view.SETUP_TEXT.map(([, line]) => line.action)];
    assert.equal(new Set(words).size, words.length, "each remaining step says its own sentence");
    assert.deepEqual(words.map(text => [pageReference.parse(text).page, pageReference.parse(text).tab]),
        [["vgs.jarvis", "Setup"], ["vgs.jarvis", "Setup/setupVoice"], ["vgs.jarvis", "Settings/brain"]], "unconfigured tooltip links open the page's named row");
    for (const [label, values, pattern, keys = KEYS, mode = "hold"] of REFUSALS)
        assert.throws(() => callView(view, values, keys, mode), error => pattern.test(error.message), label);
    for (const cause of ["speech=local-memory-insufficient", "speech=local-memory-unavailable"]) {
        const status = setupReadiness({ kind: "answered", causes: [cause] });
        const got = callView(view, up(down("unconfigured"), status));
        assert.deepEqual([got.state, got.icon, got.tone], ["off", "vgs-letter-j", "neutral"]);
        assert.equal(got.tooltip.startsWith(status.setupVoice.text), true);
        assert.equal(got.tooltipDetails[0].includes(status.setupVoice.hint), true, "the widget carries the published recovery explanation");
    }
    for (const causes of [["home=link", "brain=unselected"], ["guidance=home-skills-too-large", "speech=local-loading"]]) {
        const status = setupReadiness({ kind: "answered", causes });
        const got = callView(view, up(down("unconfigured"), status));
        assert.deepEqual([got.state, got.icon, got.tone], ["off", "vgs-letter-j", "neutral"], causes[0]);
        assert.equal(got.tooltipDetails[0].includes(status.setupHome.hint), true, causes[0] + ": the widget says what to change in the home folder");
    }
    // A failed start, retrying and stopped: its title and hint, never its key.
    for (const [cause, title, action] of START_CAUSES) {
        for (const [retrying, hint] of [[true, "Jarvis is trying again by itself."], [false, action]]) {
            const got = callView(view, { daemon: SetupGate.startStatus(cause, retrying), detail: null });
            assert.deepEqual(copy([got.state, got.icon, got.tone, got.tooltip, got.tooltipDetails]),
                ["problem", "circle-alert", "danger", title, [hint, CLICK]], cause + " retrying=" + retrying);
        }
    }
    for (const [cause, state, title, details] of SETTING_CAUSES) {
        const status = setupReadiness({ kind: "answered", causes: [cause] });
        const values = state === "off" ? up(down("unconfigured"), status) : up({}, status);
        const got = callView(view, values);
        assert.deepEqual(copy([got.state, got.tooltip, got.tooltipDetails]), [state, title, details], cause);
    }
    // Every caution a ready Setup summary carries, alone and beside the
    // session fault, reads as one ready tooltip with one link.
    for (const cause of Object.keys(SetupGate.CAUTION)) {
        const summary = setupReadiness({ kind: "answered", causes: [cause] }).setup;
        for (const [label, setup] of [[cause, summary], [cause + " and the session fault", SetupGate.sessionSummary(summary, { tone: "danger", text: "Cannot start" })]])
            for (const keys of [KEYS, UNBOUND]) {
                const got = callView(view, up({}, { setup }), keys);
                assert.equal(got.state, "ready", label);
                tooltipRules(label, got.state, got.tooltip, got.tooltipDetails);
            }
    }
    const idle = callView(view, up(down("unconfigured"), { ...setupReadiness({ kind: "answered", causes: ["brain=unselected"] }), setupHome: { tone: "ok", text: "Done", hint: "fixture" } }));
    assert.equal(idle.tooltipDetails.join(" ").includes("fixture"), false);
    verifySession(view);
}

// What every drawn tooltip holds: one link at most, none in the title,
// and under the ready title no line that says Jarvis is not ready.
function tooltipRules(label, state, title, details) {
    assert.equal(pageReference.references(title).links.length, 0, label + ": no link in the title");
    assert.ok(details.reduce((sum, text) => sum + pageReference.references(text).links.length, 0) <= 1, label + ": one link at most");
    if (state === "ready") assert.equal(details.some(text => /not (ready|set up)/i.test(pageReference.plain(text))), false, label + ": no not-ready line beside Ready");
}

// The Jarvis session's reading (SetupGate.sessionRecord, published as
// `jarvisSession`): the offer names the Resume and what a click does
// before the click, the 1Password unlock when the record needs it, and
// the Mute key in place of the click; a running session's model and time
// and each resume step's outcome add lines. The state's look is kept.
function verifySession(view) {
    const reading = more => ({ model: null, since: null, offer: null, steps: [], checkedAt: null, ...more });
    const ready = callView(view, up({}));
    assert.equal(ready.click, "console", "a click opens the console without the offer");
    const plainReading = callView(view, up({}, { jarvisSession: reading() }));
    assert.deepEqual(copy([plainReading.tooltip, plainReading.tooltipDetails, plainReading.click]), copy([ready.tooltip, ready.tooltipDetails, "console"]),
        "an empty reading changes nothing");
    for (const [unlock, keys] of [[null, KEYS], ["1password", KEYS], [null, UNBOUND]]) {
        const label = "offer unlock=" + unlock + " keys=" + (keys === KEYS ? "bound" : "unbound");
        const got = callView(view, up({}, { jarvisSession: reading({ offer: { unlock } }) }), keys);
        const base = callView(view, up({}), keys);
        assert.deepEqual([got.state, got.icon, got.tone, got.click], [base.state, base.icon, base.tone, "resume"], label + ": the state's look, a click resumes");
        assert.equal(got.tooltip, view.RESUME_TITLE, label + ": the tooltip names the offer");
        assert.equal(got.tooltipDetails[0], view.RESUME_CLICK, label + ": the first line says what a click does");
        assert.equal(got.tooltipDetails.includes(view.RESUME_UNLOCK["1password"]), unlock === "1password", label + ": the unlock line");
        assert.equal(got.tooltipDetails.some(text => /^Click/.test(text) && text !== view.RESUME_CLICK), false, label + ": no line says a click mutes");
        // An earlier line's link leaves this line its words (oneLink).
        assert.equal(pageReference.plain(got.tooltipDetails[got.tooltipDetails.length - 1]), pageReference.plain(view.keyLine(false, keys)),
            label + ": the last line names the Mute key");
        tooltipRules(label, got.state, got.tooltip, got.tooltipDetails);
    }
    const muted = callView(view, up(MUTED, { jarvisSession: reading({ offer: { unlock: null } }) }));
    assert.equal(muted.tooltipDetails[muted.tooltipDetails.length - 1], view.keyLine(true, KEYS), "a muted offer names the key to unmute");
    const steps = [{ kind: "delegate", name: "jarvis", outcome: "resumed", cause: null }, { kind: "overseer", name: "vgshell", outcome: "pending", cause: null },
        { kind: "lane", name: "VGS-1", outcome: "failed", cause: "The app asked for a sign-in" }];
    const running = callView(view, up({}, { jarvisSession: reading({ model: "claude-fable-5-1", since: "11:02", steps }) }));
    assert.equal(running.click, "console", "a resume that started leaves the click to the console");
    assert.deepEqual(copy(running.tooltipDetails), copy(ready.tooltipDetails.slice(0, -1).concat(
        ["Jarvis session running since 11:02."], steps.map(view.stepLine), ready.tooltipDetails.slice(-1))),
        "the time and each step, before the click line");
    // Beside the session fault, the running line follows the fault line.
    const faulted = callView(view, up({}, { setup: SESSION_FAULT_SUMMARY, jarvisSession: reading({ since: "09:14" }) }));
    assert.deepEqual(copy(faulted.tooltipDetails), [HOLD, SESSION_FAULT_LINE, "Jarvis session running since 09:14.", CLICK], "the fault, then the time");
    assert.deepEqual(steps.map(step => view.stepLine(step).includes(step.name)), [false, true, true], "an overseer and a lane are named");
    assert.equal(view.stepLine(steps[2]).includes(steps[2].cause), true, "a failed step shows its cause");
    assert.notEqual(view.stepLine(steps[0]), view.stepLine({ ...steps[0], outcome: "pending" }), "each outcome reads apart");
    // Once the service stopped reading the pending steps, one line says when
    // it read them last, after the steps it still shows.
    const stale = callView(view, up({}, { jarvisSession: reading({ steps: [steps[0]], checkedAt: "11:12" }) }));
    assert.deepEqual(copy(stale.tooltipDetails), copy(ready.tooltipDetails.slice(0, -1).concat([view.stepLine(steps[0]), view.checkedLine("11:12")],
        ready.tooltipDetails.slice(-1))), "the last read's time after the steps");
    assert.equal(view.checkedLine("11:12").includes("11:12"), true, "the line names the time");
    for (const [name, bad] of [["offer", { offer: { unlock: "keyring" } }], ["steps", { steps: [{ kind: "task", name: "x", outcome: "pending", cause: null }] }],
        ["outcome", { steps: [{ ...steps[0], outcome: "done" }] }], ["model", { model: 1 }], ["checkedAt", { checkedAt: 1112 }], ["shape", null]])
        assert.throws(() => callView(view, up({}, { jarvisSession: bad === null ? "x" : reading(bad) })), /jarvis widget: jarvisSession=/, "a reading outside its shape: " + name);
}

verify(load(path.join(dir, "WidgetView.js")));

// Every icon a Jarvis notice, menu row or launcher entry names, read from
// the sources that write them: Service.qml and SetupGate.js notices, the
// widget's right-click rows (Widget.qml frameActions), and the manifest's
// icon, menu and TUI entries. A source check: it proves the names written,
// not what a card draws.
const ICON_SOURCES = ["Service.qml", "SetupGate.js", "Widget.qml", "manifest.json"];
function surfaceIcons(sources) {
    const out = [];
    for (const [name, text] of Object.entries(sources))
        for (const match of text.matchAll(/\bicon"?\s*:\s*([^,}\n]+)/g))
            for (const literal of match[1].matchAll(/"([a-z0-9-]+)"/g)) out.push([name, literal[1]]);
    return out;
}
function verifySurfaceIcons(sources) {
    const icons = surfaceIcons(sources);
    // A floor that a broken reader fails: the manifest's icon, the console
    // menu row, a Service notice, a SetupGate notice and the Unmute row.
    for (const [file, icon] of [["manifest.json", "vgs-letter-j"], ["Service.qml", "vgs-letter-j"], ["SetupGate.js", "vgs-letter-j"], ["Widget.qml", "mic-off"]])
        assert.ok(icons.some(([name, value]) => name === file && value === icon), "the icon reader finds " + icon + " in " + file);
    for (const [file, icon] of icons) assert.notEqual(icon, VOICE_ICON, file + ": a Jarvis surface names the Voice widget's icon");
}
const iconSources = Object.fromEntries(ICON_SOURCES.map(name => [name, fs.readFileSync(path.join(dir, name), "utf8")]));
verifySurfaceIcons(iconSources);
assert.throws(() => verifySurfaceIcons({ ...iconSources, "Service.qml": iconSources["Service.qml"] + '\nnotice({ title: "x", tone: "info", icon: "mic" });' }),
    assert.AssertionError, "a notice that names mic fails the icon check");
assert.throws(() => verifySurfaceIcons({ ...iconSources, "Widget.qml": iconSources["Widget.qml"].replace('"vgs-letter-j" : "mic-off"', '"mic" : "mic-off"') }),
    assert.AssertionError, "an Unmute row that names mic fails the icon check");

// Each control removes one rule from a copy of the view and keeps the text
// around it: [label, needle, replacement].
const CONTROLS = [
    ["the offer leaves the click to mute", 'out.click = "resume";', ""],
    ["the offer keeps the click line", "var details = base.tooltipDetails.slice(0, -1);", "var details = base.tooltipDetails;"],
    ["the unlock line is dropped", "out.tooltipDetails = [RESUME_CLICK].concat(session.offer.unlock === null ? [] : [RESUME_UNLOCK[session.offer.unlock]],", "out.tooltipDetails = [RESUME_CLICK].concat([],"],
    ["the steps are dropped", "running, session.steps.map(stepLine)", "running, []"],
    ["the last read's time is dropped", "session.checkedAt === null ? [] : [checkedLine(session.checkedAt)]", "[]"],
    ["a failed step hides its cause", 'step.cause === null || step.cause === "" ? "." : ": " + line(step.cause)', '"."', "a failed step shows its cause"],
    ["an ElevenLabs refusal reads as a broken speaker", '    [/^playback-source: jarvis: speech=elevenlabs-/, "elevenlabs"],\n', ''],
    ["memory explanation discarded", 'return { title: step.text === Gate.TO_DO ? SETUP_TEXT[i][1].title : step.text, action: step.hint };', 'return GATE_TEXT.unconfigured;'],
    ["checking setup reads off", 'state.gate.reason === "unconfigured" && setupChecking(values)', 'state.gate.reason === "unconfigured" && false'],
    ["checking hides an offered setup action", '!step || offered(step) ||', '!step ||'],
    ["a refused home folder reads as another step", 'if (down && state.gate.reason === "unconfigured" && homeRefused(values)) return withBrain(textLook("off", homeText(values), muteOn, effectiveKeys));', ''],
    ["a home folder step with nothing to ask reads refused", 'return !!home && home.tone === "warning" && ', 'return !!home && '],
    ["missing requirements read checking", '(step.tone !== "info" && step.tone !== "ok")', 'false'],
    ["done steps read checking", 'return checking;', 'return true;'],
    ["cleared prompt retains a record", "if (hold === null) return null;", "if (hold === null) return {};"],
    ["file prompt loses its path", 'path: filePrompt && lines.length > 1 ? lines[1] : ""', 'path: filePrompt && lines.length > 1 ? lines[0] : ""'],
    ["file prompt repeats its path as detail", 'lines.slice(2).join("\\n")', 'lines.slice(1).join("\\n")'],
    ["detail flag is dropped", 'detail: filePrompt && lines.length > 2', 'detail: false'],
    ["an open microphone is not listening", "microphoneOpen(state.capture)) return", "false) return"],
    ["a follow-up sounds like a normal capture", 'followUp ? "Jarvis is listening for a follow-up" : "Jarvis is listening"',
        'false ? "Jarvis is listening for a follow-up" : "Jarvis is listening"'],
    ["an armed capture reads listening while the voice loads", "!(armed && voicePending(values)) && microphoneOpen", "microphoneOpen"],
    ["an armed capture reads listening before the voice status", "!(armed && voicePending(values)) && microphoneOpen", "!(armed && voiceLoading(values)) && microphoneOpen"],
    ["an armed pending voice reaches the phase table", '&& (armed || voiceLoading(values)))', '&& voiceLoading(values))'],
    ["an answered voice step reads pending", 'return !voice || (voice.tone === "info" && !offered(voice));', 'return !voice || voice.tone !== "ok";'],
    ["an unchecked microphone reads as a pending voice", '(voice.tone === "info" && !offered(voice))', 'voice.tone === "info"'],
    ["an opening armed capture reads listening while the voice loads", '(state.capture.kind === "opening" || (', '(false || ('],
    ["a daemon problem is not a problem", 'daemon.tone === "danger") return', 'false) return'],
    ["a retrying daemon problem is not a problem", 'daemon.tone === "warning" && daemon.hint !== undefined) return', 'false) return'],
    ["a Session error is not a problem", 'detail.phase === "error") return', 'false) return'],
    ["an audio problem is not a problem", 'audio.tone === "danger") return', 'false) return'],
    ["no state yet is not loading", 'if (state === null) return textLook("loading"', 'if (false) return textLook("loading"'],
    ["mute is not shown", 'if (muteOn) return withBrain(look("muted"', 'if (false) return withBrain(look("muted"'],
    ["muting is not muted", 'case "muting": case "on": return true;', 'case "on": return true;'],
    ["a lowered gate is not off", 'if (down) return withBrain(textLook("off"', 'if (false) return withBrain(textLook("off"'],
    ["loading reads ready", 'look("loading", "Jarvis is loading its voice", ["Wait for local voice to load."], muteOn, effectiveKeys)', 'look("ready", "Ready to talk", [Gate.talkHint(effectiveMode, effectiveKeys.talk) + "."], muteOn, effectiveKeys)'],
    ["loading overrides a privacy gate", '(!down || state.gate.reason === "unconfigured") && (armed || voiceLoading(values))', '(armed || voiceLoading(values))'],
    ["thinking reads speaking", 'case "thinking":\n        return withBrain(look("working", WORK_TEXT[detail.phase], [stopAction(effectiveKeys)], muteOn, effectiveKeys));', 'case "thinking":\n        return withBrain(look("speaking", "Jarvis is speaking", [stopAction(effectiveKeys)], muteOn, effectiveKeys));'],
    ["speaking reads working", 'return withBrain(look("speaking", "Jarvis is speaking", [stopAction(effectiveKeys)], muteOn, effectiveKeys));', 'return withBrain(look("working", "Jarvis is speaking", [stopAction(effectiveKeys)], muteOn, effectiveKeys));'],
    ["the muted look names no way to unmute", '[unmuteLine(effectiveKeys)]', '[]'],
    ["any report tone is accepted", "tones.indexOf(value.tone) === -1", "false"],
    ["any report hint is accepted", 'if (value.hint !== undefined && typeof value.hint !== "string") refuse(name, value);', ""],
    ["the tooltip shows the keyed cause", '[report.hint === undefined ? RESTART : report.hint]', 'report.lines === undefined ? [RESTART] : report.lines'],
    ["an unknown capture is closed", 'default: refuse("capture", capture);', "default: return false;"],
    ["an unknown gate reason is off", 'if (!hasOwn(GATE_TEXT, gate.reason)) refuse("gate", gate);', ""],
    ["an unexpected phase reads ready", 'refuse("phase", detail.phase);', 'return withBrain(look("ready", "Ready to talk", [Gate.talkHint(effectiveMode, effectiveKeys.talk) + "."], muteOn, effectiveKeys));'],
    ["a fault shows its keyed reason", 'return fault.kind === "retrying" ? RETRYING : FAULT_TEXT[kind];', 'return { title: "Problem: " + fault.reason, action: RESTART };'],
    ["a brain fault reads as another", '[/^(brain|net)=/, "brain"],', ""],
    ["local voice timeout reads as generic speech", '[/^speech=local-ready-timeout$/, "localVoice"],\n', ""],
    ["a refused model reads as any brain fault", '    [MODEL_REFUSED, "model"],\n', ""],
    ["a refused model is not named", 'title: FAULT_TEXT.model.title + " " + MODEL_REFUSED.exec(fault.reason)[1]', "title: FAULT_TEXT.model.title"],
    ["a home folder fault reads as another", '[/^(home=|guidance=home-)/, "home"],', ""],
    ["a home text fault reads as another", '[/^(home=|guidance=home-)/, "home"],', '[/^home=/, "home"],'],
    ["a slow answer reads as another", '[/^thinking-timeout$/, "slow"],', ""],
    ["a retry asks for a restart", 'fault.kind === "retrying" ? RETRYING : FAULT_TEXT[kind]', "FAULT_TEXT[kind]"],
    ["a dictation fault asks for a restart", '    [/^speech=dictation-/, "dictation"],\n', ""],
    ["a busy dictation reads as a failed one", '    [/^speech=dictation-busy$/, "dictationBusy"],\n', ""],
    ["the local voice's lost device names the setting", 'if (kind === "device" && engine === "dictation") kind = "defaultDevice";', ""],
    ["an audio problem shows its text", 'return withBrain(textLook("problem", AUDIO_TEXT, muteOn, effectiveKeys))', 'return withBrain(look("problem", "Audio problem: " + audio.text, [RESTART], muteOn, effectiveKeys))'],
    ["an unconfigured gate names no step", 'state.gate.reason === "unconfigured" ? unconfiguredText(values) : GATE_TEXT[state.gate.reason]', 'GATE_TEXT[state.gate.reason]'],
    ["every offered step shows its hint", 'return step.text === "Timed out";', "return true;"],
    ["an offered step title reads generic", 'if (step && step.tone === "warning" && offered(step) && step.hint && timedOut(step))\n            return { title: SETUP_TEXT[i][1].title, action: step.hint };', ''],
    ["ready drops setup cause hint", 'if (hint !== null) ready.tooltipDetails', 'if (false) ready.tooltipDetails'],
    ["the caution line keeps no full stop", '.concat([line(hint)], ready.tooltipDetails.slice(-1))', '.concat([hint], ready.tooltipDetails.slice(-1))'],
    ["a tooltip keeps every link", "out.tooltipDetails = oneLink(out.tooltipDetails);", ""],
    ["the linked line keeps every link", "return found.text.slice(0, first.start) + first.reference + found.text.slice(first.end);", "return text;"],
    ["a home fault links each file", 'action: "See what to change in [Setup > Home folder](page:vgs.jarvis/Setup/setupHome)." },',
        'action: "Check [AGENTS.md](file:%2Fhome%2Fuser%2FFixture%2FAGENTS.md) and the [skills folder](file:%2Fhome%2Fuser%2FFixture%2Fskills%2F)." },'],
    ["ready draws the Voice widget's microphone", '"ready": { icon: "vgs-letter-j", tone: "calm" }', '"ready": { icon: "mic", tone: "calm" }'],
    ["the silent microphone links no field", '"Choose a working microphone in [Microphone](page:vgs.jarvis/Settings/microphone), then talk again."', '"Choose a working microphone in Settings, then talk again."'],
    ["a refused key names no company", 'if (kind === "keyRefused") return keyRefusedText(voice);', ""],
    ["a refused key reads as a missing one", 'values.setupVoice && values.setupVoice.text === Gate.KEY_REFUSED', "false"],
    ["a local setup reads as loading", 'values.setupVoice.text === Gate.SETTING_UP.text', "false"],
    ["the voice is not a line", '.concat(route === "" ? [] : ["Voice: " + route])', ""],
    ["a step done reads as to do", 'return step.action === true || typeof step.action === "string";', "return step.action !== undefined;"],
    ["a step action is ignored", 'return step.action === true || typeof step.action === "string";', "return false;"],
    ["the AI model reads before local voice", "for (var i = 0; i < SETUP_TEXT.length; i++) {\n        var step = values[SETUP_TEXT[i][0]];\n        if (step && step.tone",
        "for (var i = SETUP_TEXT.length - 1; i >= 0; i--) {\n        var step = values[SETUP_TEXT[i][0]];\n        if (step && step.tone"],
    ["keys are not spelled", 'key === null || key === undefined ? null : caps(key).join("+");', 'key;'],
    ["an absent key spells empty", 'key === null || key === undefined ? null : caps(key).join("+");', 'key === null ? null : caps(key).join("+");'],
    ["shared icons are accepted", '"working": { icon: "brain", tone: "info" }', '"working": { icon: "loader", tone: "info" }'],
    ["ready words its own talk line", '[Gate.talkHint(effectiveMode, effectiveKeys.talk) + "."]', '[effectiveKeys.talk === null ? keySetting("Talk") : "Press " + effectiveKeys.talk + " to start talking."]'],
    ["unbound stop key names no setting", 'return keys.stop === null ? keySetting("Stop") : "Press " + keys.stop + " to stop.";', 'return keys.stop === null ? "Press Stop to stop." : "Press " + keys.stop + " to stop.";'],
    ["unbound confirm key names no setting", 'return keys.confirm === null ? "Confirm on screen, or set [Confirm key in Settings > Jarvis](page:vgs.jarvis/Keys)."', 'return keys.confirm === null ? "Confirm on screen, or press Confirm."'],
    ["a hint becomes a tooltip line with no full stop", "var lines = details.map(line);", "var lines = details.slice();"],
    ["unbound mute key names no menu", 'return keys.mute === null ? "Unmute Jarvis from its right-click menu."', 'return keys.mute === null ? "Press Mute to unmute."'],
    ["unbound console key names a key", 'return keys.console === null ? "Click to open the console."', 'return keys.console === null ? "Click or press Console to open the console."']
];

const source = fs.readFileSync(path.join(dir, "WidgetView.js"), "utf8");
const scratchRoot = os.tmpdir();
fs.mkdirSync(scratchRoot, { recursive: true });
const temp = fs.mkdtempSync(path.join(scratchRoot, "jarvis-widget-control-"));
// The copy imports SetupGate.js beside it, as the shipped file does.
fs.copyFileSync(path.join(dir, "SetupGate.js"), path.join(temp, "SetupGate.js"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const changed = source.replace(needle, () => replacement);
        assert.notEqual(changed, source, `control "${label}": the copy changed`);
        const file = path.join(temp, "WidgetView.js");
        fs.writeFileSync(file, changed);
        let failure = null;
        try {
            verify(load(file));
        } catch (e) {
            failure = e;
        }
        assert.ok(failure instanceof assert.AssertionError, `control "${label}": the suite passed on a copy without that rule` +
            (failure === null ? "" : ", or failed on something other than an assertion: " + failure));
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}

// Execute Bubble's shipped callbacks with controlled GUI/render ordering.
// The nested bubble row proves rendering; this case proves which queued frame
// may acknowledge a real Session hold, without a second frame owner.
function approvalFrames(source) {
    let state = detail({ conversation: { kind: "active" }, gen: 1, ...THINKING }).state;
    let at = 0;
    const dispatch = e => {
        const result = Session.reduce(state, { ...e, at });
        state = result.state;
        return result.effects;
    };
    const later = [];
    const root = { shown: true, visible: true, presented: true, placed: true, displayedHold: null,
        approvalFrames: [], synchronizedHold: null,
        service: { shownApproval: (bubble, hold) => dispatch({ type: "shown", gen: hold.gen, op: hold.op, id: hold.id }) } };
    Object.defineProperty(root, "hold", { get: () => state.approval.kind === "held" ? state.approval : null });
    const approvalText = { height: 40, implicitHeight: 40 };
    Object.defineProperty(approvalText, "text", { get: () => root.hold?.text ?? "" });
    const ctx = vm.createContext({ root, approvalText, Qt: { callLater: fn => later.push(fn) } });
    for (const name of ["approvalPolished", "approvalSynchronized", "approvalSwapped"]) {
        const matches = [...source.matchAll(new RegExp("^    function " + name + "\\(\\) \\{\\n[\\s\\S]*?^    \\}", "gm"))];
        assert.equal(matches.length, 1, "one shipped Bubble callback: " + name);
        const run = vm.runInContext("(function() { with(root) { return (" + matches[0][0] + ").call(root); } })", ctx);
        root[name] = run;
    }
    const flush = () => { while (later.length) later.shift()(); };
    const propose = id => dispatch({ type: "approval", gen: 1, op: 4, id, digest: id, purpose: "action",
        text: "Fixture action", physical: false, tool: "fixture", timeoutMs: 1000, cancellable: false });
    const confirm = h => dispatch({ type: "confirm", gen: h.gen, id: h.id, digest: h.digest, source: "button" });

    root.approvalPolished();
    propose("first");
    const h = root.hold;
    root.approvalPolished();
    root.approvalSynchronized();
    root.approvalSwapped();
    flush();
    assert.equal(state.approval.shownAt, null, "an earlier frame cannot acknowledge a newer request");
    at = 1000;
    assert.equal(confirm(h).find(e => e.kind === "confirm-refused")?.reason, "early",
        "confirmation stays refused until the request's frame completes");
    root.approvalSynchronized();
    root.approvalSwapped();
    flush();
    assert.equal(state.approval.shownAt, 1000, "the matching frame acknowledges its request");
    at += Session.APPROVAL_DRAW_MS;
    assert.ok(confirm(h).some(e => e.kind === "tool-start"), "the matching frame starts the full draw interval");

    state.action = { kind: "none" };
    propose("second");
    root.displayedHold = null;
    root.approvalPolished();
    root.approvalSynchronized();
    root.approvalSwapped();
    dispatch({ type: "approval-cancel", gen: 1, id: "second" });
    propose("third");
    flush();
    assert.equal(state.approval.shownAt, null, "a deferred acknowledgment cannot cross request replacement");
    root.presented = false;
    root.approvalPolished();
    root.approvalSynchronized();
    root.approvalSwapped();
    flush();
    assert.equal(state.approval.shownAt, null, "a hidden host cannot acknowledge");
    root.presented = true;
    root.placed = false;
    root.approvalPolished();
    root.approvalSynchronized();
    root.approvalSwapped();
    flush();
    assert.equal(state.approval.shownAt, null, "a frame drawn before the placement is known cannot acknowledge");
    root.placed = true;
    root.approvalPolished();
    root.approvalSynchronized();
    root.approvalSwapped();
    flush();
    assert.notEqual(state.approval.shownAt, null, "the placed frame acknowledges its request");
}
const bubble = fs.readFileSync(path.join(dir, "Bubble.qml"), "utf8");
approvalFrames(bubble);
const frameNeedle = "const drawn = synchronizedHold;";
assert.equal(bubble.split(frameNeedle).length, 2, "one frame identity control match");
assert.throws(() => approvalFrames(bubble.replace(frameNeedle, "const drawn = root.hold;")), assert.AssertionError,
    "delivery from the current hold must fail the earlier-frame assertion");
const placedNeedle = "visible && placed && ";
assert.equal(bubble.split(placedNeedle).length, 2, "one placement control match");
assert.throws(() => approvalFrames(bubble.replace(placedNeedle, "visible && ")), assert.AssertionError,
    "a frame drawn before the placement must fail the placement assertion");
console.log(`test-jarvis-widget: ok cases=${CASES.length + START_CAUSES.length} refusals=${REFUSALS.length} controls=${CONTROLS.length + 4} frame-control=detected`);
