#!/usr/bin/env node
// What the Jarvis bar widget shows, shell/plugins/vgs.jarvis/WidgetView.js,
// under node: the state, icon, tone and tooltip for the status values the
// service publishes, and the keyed refusal of every value outside them.
// Each Session record comes from Session.js's own initial state with the
// named regions set, passes Session.validate, and takes its phase from
// Session.phaseOf, as the daemon publishes it. Every expected value is
// written out by hand, but for the words of a fault, the audio problem and
// a remaining Setup step: those come from the view's own table under the
// kind or step this suite names, and no tooltip carries a keyed cause. No
// process, file, network or audio is used.
//
// The controls at the end edit a copy of the view, one rule at a time, and
// require this suite to fail an assertion on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { load } = require("../bin/lib/qml-library.js");

const dir = path.join(__dirname, "..", "shell", "plugins", "vgs.jarvis");
const Session = load(path.join(dir, "Session.js"));
const SetupGate = load(path.join(dir, "SetupGate.js"));
const Lucide = load(path.join(__dirname, "..", "shell", "Ui", "icons", "Lucide.js"));
const copy = value => JSON.parse(JSON.stringify(value));

// A detail as the service publishes it: the Session record with REGIONS
// over a raised gate, its phase from Session.phaseOf.
function detail(regions) {
    const s = Object.assign(copy(Session.initial()), { gate: { kind: "up" } }, copy(regions));
    assert.equal(Session.validate(s), true, "fixture is a Session record: " + JSON.stringify(regions));
    return { phase: Session.phaseOf(s), seq: 1, state: s };
}
const down = reason => ({ gate: { kind: "down", reason } });
const OPEN = { capture: { kind: "open", gen: 1, op: 2, mode: "hold" } };
const CLOSING = { capture: { kind: "closing", gen: 1, op: 3 } };
const THINKING = { turn: { kind: "thinking", gen: 1, op: 4, deadline: 70 } };
const MUTED = { mute: { kind: "on" } };
const READY = { tone: "info", text: "Ready; no capture" };
const DEVICES = { tone: "ok", text: "Device list ready" };
const FLOOR = { tone: "danger", text: "Stopped after a problem. Turn Jarvis off and on again." };
const OVERFLOW = { tone: "danger", text: "capture-overflow" };
const up = (regions, extra) => Object.assign({ daemon: READY, audio: DEVICES, detail: detail(regions) }, extra);

const MUTE = "\nClick to mute";
const UNMUTE = "\nClick to unmute";
// A tooltip the view words from one of its own tables: the kind of fault,
// the retry, the audio problem or the Setup step this suite names by hand.
const fault = kind => v => v.FAULT_TEXT[kind].title + ". " + v.FAULT_TEXT[kind].action;
const retrying = v => v.RETRYING.title + ". " + v.RETRYING.action;
const audioText = v => v.AUDIO_TEXT;
const setupStep = key => v => v.SETUP_TEXT.find(([name]) => name === key)[1];
const unconfigured = v => v.GATE_TEXT.unconfigured;
function splitTooltip(row, view) {
    const parts = (typeof row[3] === "function" ? row[3](view) : row[3]).split("\n");
    return [row[0], row[1], row[2], parts[0], [parts[1]]];
}
const WITH = (line, details) => v => line(v) + details;
// The Setup steps as the service publishes them (SetupGate.readiness).
const TODO = { tone: "warning", text: "To do", lines: ["fixture line"], action: true };
const DONE = { tone: "ok", text: "Done", action: false };
// [label, status values, [state, icon, tone, tooltip title plus detail]].
const CASES = [
    ["nothing published yet", {}, ["off", "power-off", "neutral", "Jarvis is starting" + MUTE]],
    ["starting before the first state", { daemon: { tone: "info", text: "Starting" }, detail: null, audio: { tone: "info", text: "Reading devices" } },
        ["off", "power-off", "neutral", "Jarvis: Starting" + MUTE]],
    ["restarting", { daemon: { tone: "warning", text: "Restarting after a problem" }, detail: null },
        ["off", "power-off", "neutral", "Jarvis: Restarting after a problem" + MUTE]],
    ["mute pending", { daemon: { tone: "warning", text: "Mute pending; disabling Jarvis cancels the request" }, detail: null },
        ["off", "power-off", "neutral", "Jarvis: Mute pending; disabling Jarvis cancels the request" + MUTE]],
    ["ready", up({}), ["ready", "mic", "calm", "Jarvis is ready" + MUTE]],
    ["listening", up(OPEN), ["live", "audio-lines", "accent", "Jarvis is using the microphone" + MUTE]],
    ["capture opening", up({ capture: { kind: "opening", gen: 1, op: 2, mode: "conversation" } }),
        ["live", "audio-lines", "accent", "Jarvis is using the microphone" + MUTE]],
    ["armed", up({ capture: { kind: "open", gen: 1, op: 2, mode: "armed" } }),
        ["live", "audio-lines", "accent", "Jarvis is using the microphone" + MUTE]],
    ["muting while capture closes", up({ mute: { kind: "muting" }, ...CLOSING }),
        ["live", "audio-lines", "accent", "Jarvis is using the microphone" + UNMUTE]],
    ["capture closing after a lock", up({ ...down("locked"), ...CLOSING }),
        ["live", "audio-lines", "accent", "Jarvis is using the microphone" + MUTE]],
    ["live over an audio problem", up(OPEN, { audio: OVERFLOW }),
        ["live", "audio-lines", "accent", "Jarvis is using the microphone" + MUTE]],
    ["permanent daemon problem", { daemon: FLOOR, detail: null, audio: DEVICES },
        ["problem", "circle-alert", "danger", "Stopped after a problem. Turn Jarvis off and on again." + MUTE]],
    ["Session error", up({ fault: { kind: "error", reason: "thinking-timeout", retry: 0 } }),
        ["problem", "circle-alert", "danger", WITH(fault("slow"), MUTE)]],
    ["Session retrying a lost device", up({ fault: { kind: "retrying", reason: "device-lost", retry: 1 } }),
        ["problem", "circle-alert", "danger", WITH(retrying, MUTE)]],
    ["audio fault", up({}, { audio: OVERFLOW }),
        ["problem", "circle-alert", "danger", WITH(audioText, MUTE)]],
    ["audio fault before the first state", { daemon: { tone: "info", text: "Starting" }, detail: null, audio: OVERFLOW },
        ["problem", "circle-alert", "danger", WITH(audioText, MUTE)]],
    ["problem over mute", up(MUTED, { audio: OVERFLOW }),
        ["problem", "circle-alert", "danger", WITH(audioText, UNMUTE)]],
    ["Session error while muted", up({ ...MUTED, fault: { kind: "error", reason: "thinking-timeout", retry: 0 } }),
        ["problem", "circle-alert", "danger", WITH(fault("slow"), UNMUTE)]],
    // Each producer's keyed reason reads as its kind of failure.
    ...[["a lost device", "device-lost", "device"], ["a brain stream error", "brain=stream-error", "brain"],
        ["a harness exit", "brain=harness-exit", "brain"], ["a network refusal", "net=timeout", "brain"],
        ["local speech", "speech=local-not-ready", "voice"], ["a capture start", "audio-start: device-busy", "audio"],
        ["a device probe", "device-probe: pw-dump-exit", "audio"], ["a busy player", "playback-busy", "audio"],
        ["an unexpected engine failure", "engine=unexpected", "other"]].map(([label, reason, kind]) =>
        [label, up({ fault: { kind: "error", reason, retry: 0 } }), ["problem", "circle-alert", "danger", WITH(fault(kind), MUTE)]]),
    ["muted", up(MUTED), ["muted", "mic-off", "neutral", "Jarvis is muted" + UNMUTE]],
    ["muted while locked", up({ ...MUTED, ...down("locked") }), ["muted", "mic-off", "neutral", "Jarvis is muted" + UNMUTE]],
    ["muted over a cancelling turn", up({ ...MUTED, turn: { kind: "cancelling", gen: 1, op: 4, deadline: 70 } }),
        ["muted", "mic-off", "neutral", "Jarvis is muted" + UNMUTE]],
    ["muting with capture closed", up({ mute: { kind: "muting" } }), ["muted", "mic-off", "neutral", "Jarvis is muted" + UNMUTE]],
    ["gate starting", up(down("starting")), ["off", "power-off", "neutral", "Jarvis is starting" + MUTE]],
    ["gate unconfigured, nothing published", up(down("unconfigured")), ["off", "power-off", "neutral", WITH(unconfigured, MUTE)]],
    ["local voice to do", up(down("unconfigured"), { setupVoice: TODO, setupModel: TODO }),
        ["off", "power-off", "neutral", WITH(setupStep("setupVoice"), MUTE)]],
    ["the AI model to do", up(down("unconfigured"), { setupVoice: DONE, setupModel: TODO }),
        ["off", "power-off", "neutral", WITH(setupStep("setupModel"), MUTE)]],
    ["gate node", up(down("node")), ["off", "power-off", "neutral", "Jarvis needs Node 22 or later" + MUTE]],
    ["gate lock unknown", up(down("lock-unknown")), ["off", "power-off", "neutral", "Jarvis is off until the screen lock is known" + MUTE]],
    ["gate locked", up(down("locked")), ["off", "power-off", "neutral", "Jarvis is off while the screen is locked" + MUTE]],
    ["thinking", up(THINKING), ["working", "loader", "info", "Jarvis is thinking" + MUTE]],
    ["cancelling a turn", up({ turn: { kind: "cancelling", gen: 1, op: 4, deadline: 70 } }), ["working", "loader", "info", "Jarvis is thinking" + MUTE]],
    ["speaking", up({ playback: { kind: "playing", gen: 1, op: 5, source: 4, interruptible: true, admission: { kind: "started" }, deadline: null } }),
        ["working", "loader", "info", "Jarvis is speaking" + MUTE]],
    ["confirming", up({ approval: { kind: "held", purpose: "action", gen: 1, op: 6, id: "a1", digest: "d1", deadline: 90, shownAt: null,
        physical: true, text: "Fixture action", tool: "fixture", timeoutMs: 1000, cancellable: false, brain: 4 } }),
        ["working", "loader", "info", "Jarvis is waiting for your confirmation" + MUTE]],
    ["acting", up({ action: { kind: "running", gen: 1, op: 7, tool: "shell", brain: 4, limit: { kind: "expired" }, cancellation: { kind: "available" } } }),
        ["working", "loader", "info", "Jarvis is running a task" + MUTE]]
];

// A status whose detail's state has the named change applied after
// Session built it, for the shapes Session never publishes.
function bent(regions, change) {
    const values = up(regions);
    change(values.detail);
    return values;
}
// [label, status values, the keyed refusal].
const REFUSALS = [
    ["daemon tone outside its set", { daemon: { tone: "ok", text: "Ready" } }, /^jarvis widget: daemon=\{"tone":"ok","text":"Ready"\} unexpected$/],
    ["daemon without text", { daemon: { tone: "info" } }, /^jarvis widget: daemon=/],
    ["daemon null", { daemon: null }, /^jarvis widget: daemon=null unexpected$/],
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
    ["error without a fault", bent({}, d => { d.phase = "error"; }), /^jarvis widget: fault=\{"kind":"none"\} unexpected$/]
];

function verify(view) {
    const loading = SetupGate.readiness({ kind: "answered", causes: ["speech=local-loading"] });
    const checking = SetupGate.readiness({ kind: "checking" });
    for (const [label, values, want] of [
        ["speech loading", up(down("unconfigured"), loading), ["working", "loader", "info"]],
        ["setup checking", up(down("unconfigured"), checking), ["working", "loader", "info"]],
        ["loading with open microphone", up({ ...down("unconfigured"), ...OPEN }, loading), ["live", "audio-lines", "accent"]],
        ["loading with daemon danger", up(down("unconfigured"), { ...loading, daemon: FLOOR }), ["problem", "circle-alert", "danger"]],
        ["loading with audio danger", up(down("unconfigured"), { ...loading, audio: OVERFLOW }), ["problem", "circle-alert", "danger"]],
        ["checking setup with Session fault", up({ fault: { kind: "error", reason: "brain=stream-error", retry: 0 } }, loading), ["problem", "circle-alert", "danger"]],
        ["loading while muted", up({ ...down("unconfigured"), ...MUTED }, loading), ["muted", "mic-off", "neutral"]],
        ["loading with missing model", up(down("unconfigured"), SetupGate.readiness({ kind: "answered", causes: ["speech=local-loading", "brain=unselected"] })), ["off", "power-off", "neutral"]],
        ["missing command with no setup action", up(down("unconfigured"), { setupVoice: { tone: "warning", action: false }, setupModel: DONE }), ["off", "power-off", "neutral"]],
        ["missing command while model checks", up(down("unconfigured"), { setupVoice: { tone: "warning", action: false }, setupModel: checking.setupModel }), ["off", "power-off", "neutral"]],
        ["checking tone with setup action", up(down("unconfigured"), { setupVoice: { tone: "info", action: true }, setupModel: DONE }), ["off", "power-off", "neutral"]],
        ["unpublished model while voice checks", up(down("unconfigured"), { setupVoice: loading.setupVoice }), ["off", "power-off", "neutral"]],
        ["both steps done with gate down", up(down("unconfigured"), SetupGate.readiness({ kind: "answered", causes: [] })), ["off", "power-off", "neutral"]],
        ["loading while locked", up(down("locked"), loading), ["off", "power-off", "neutral"]]
    ]) {
        let out;
        assert.doesNotThrow(() => { out = view.view(copy(values)); }, label);
        assert.deepEqual([out.state, out.icon, out.tone], want, label);
    }
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
    assert.deepEqual(Object.keys(view.LOOKS).sort(), ["live", "muted", "off", "problem", "ready", "working"], "the six widget states");
    for (const [state, look] of Object.entries(view.LOOKS))
        assert.ok(Object.prototype.hasOwnProperty.call(Lucide.ICONS, look.icon), state + ": icon " + look.icon + " ships");
    for (const [label, values, want] of CASES) {
        let got;
        try {
            const out = view.view(copy(values));
            got = [out.state, out.icon, out.tone, out.tooltip, out.tooltipDetails];
        } catch (e) {
            got = "threw: " + e.message;
        }
        assert.deepEqual(copy(got), splitTooltip(want, view), label);
        // A keyed cause stays in the log: no tooltip carries one.
        if (typeof got !== "string") assert.equal(/[a-z-]+=[a-z0-9-]/.test(got[3]), false, label + ": no keyed cause on screen");
    }
    // Each kind and step the suite names has its own words.
    for (const kind of ["slow", "device", "brain", "voice", "audio", "other"])
        assert.equal(typeof view.FAULT_TEXT[kind].title === "string" && typeof view.FAULT_TEXT[kind].action === "string", true, kind);
    const words = [view.GATE_TEXT.unconfigured, ...view.SETUP_TEXT.map(([, line]) => line)];
    assert.equal(new Set(words).size, words.length, "each remaining step says its own sentence");
    for (const [label, values, pattern] of REFUSALS)
        assert.throws(() => view.view(copy(values)), error => pattern.test(error.message), label);
}

verify(load(path.join(dir, "WidgetView.js")));

// Each control removes one rule from a copy of the view and keeps the text
// around it: [label, needle, replacement].
const CONTROLS = [
    ["checking setup reads off", 'state.gate.reason === "unconfigured" && setupChecking(values)', 'state.gate.reason === "unconfigured" && false'],
    ["checking hides an offered setup action", 'step.action !== false', 'false'],
    ["missing requirements read checking", '(step.tone !== "info" && step.tone !== "ok")', 'false'],
    ["done steps read checking", 'return checking;', 'return true;'],
    ["cleared prompt retains a record", "if (hold === null) return null;", "if (hold === null) return {};"],
    ["file prompt loses its path", 'path: filePrompt && lines.length > 1 ? lines[1] : ""', 'path: filePrompt && lines.length > 1 ? lines[0] : ""'],
    ["file prompt repeats its path as detail", 'lines.slice(2).join("\\n")', 'lines.slice(1).join("\\n")'],
    ["detail flag is dropped", 'detail: filePrompt && lines.length > 2', 'detail: false'],
    ["an open microphone is not live", "microphoneOpen(state.capture)) return", "false) return"],
    ["a daemon problem is not a problem", 'daemon.tone === "danger") return', 'false) return'],
    ["a Session error is not a problem", 'detail.phase === "error") {', 'false) {'],
    ["an audio problem is not a problem", 'audio.tone === "danger") return', 'false) return'],
    ["no state yet is not off", "if (state === null) return look(\"off\"", "if (false) return look(\"off\""],
    ["the daemon text is not shown before a state", '"Jarvis: " + daemon.text', 'GATE_TEXT.starting'],
    ["mute is not shown", "if (muteOn) return look(\"muted\"", "if (false) return look(\"muted\""],
    ["muting is not muted", 'case "muting": case "on": return true;', 'case "on": return true;'],
    ["a lowered gate is not off", "if (gateDown(state.gate))", "if (false)"],
    ["working phases read ready", 'return look("working", WORK_TEXT[detail.phase], muteOn);', 'return look("ready", "Jarvis is ready", muteOn);'],
    ["the click line follows the icon, not the mute region", 'muteOn ? "Click to unmute" : "Click to mute"', 'state === "muted" ? "Click to unmute" : "Click to mute"'],
    ["the click line never offers unmute", 'muteOn ? "Click to unmute" : "Click to mute"', '"Click to mute"'],
    ["any report tone is accepted", "tones.indexOf(value.tone) === -1", "false"],
    ["an unknown capture is closed", 'default: refuse("capture", capture);', "default: return false;"],
    ["an unknown gate reason is off", 'if (!Object.prototype.hasOwnProperty.call(GATE_TEXT, gate.reason)) refuse("gate", gate);', ""],
    ["an unexpected phase reads ready", 'refuse("phase", detail.phase);', 'return look("ready", "Jarvis is ready", muteOn);'],
    ["a fault shows its keyed reason", 'return look("problem", text.title + ". " + text.action, muteOn);',
        'return look("problem", "Problem: " + state.fault.reason, muteOn);'],
    ["a brain fault reads as another", '[/^(brain|net)=/, "brain"],', ""],
    ["a slow answer reads as another", '[/^thinking-timeout$/, "slow"],', ""],
    ["a retry asks for a restart", 'fault.kind === "retrying" ? RETRYING : FAULT_TEXT[kind]', "FAULT_TEXT[kind]"],
    ["an audio problem shows its text", 'look("problem", AUDIO_TEXT, muteOn)', 'look("problem", "Audio problem: " + audio.text, muteOn)'],
    ["an unconfigured gate names no step", 'state.gate.reason === "unconfigured" ? unconfiguredText(values) : GATE_TEXT[state.gate.reason]',
        "GATE_TEXT[state.gate.reason]"],
    ["a step done reads as to do", "step.action === true", "step.action !== undefined"],
    ["the AI model reads before local voice", "function unconfiguredText(values) {\n    for (var i = 0; i < SETUP_TEXT.length; i++) {", "function unconfiguredText(values) {\n    for (var i = SETUP_TEXT.length - 1; i >= 0; i--) {"]
];

const source = fs.readFileSync(path.join(dir, "WidgetView.js"), "utf8");
const scratchRoot = path.join(__dirname, "..", "tmp");
fs.mkdirSync(scratchRoot, { recursive: true });
const temp = fs.mkdtempSync(path.join(scratchRoot, "jarvis-widget-control-"));
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
    const root = { shown: true, visible: true, presented: true, displayedHold: null,
        approvalFrames: [], synchronizedHold: null,
        service: { shownApproval: (bubble, hold) => dispatch({ type: "shown", gen: hold.gen, op: hold.op, id: hold.id }) } };
    Object.defineProperty(root, "hold", { get: () => state.approval.kind === "held" ? state.approval : null });
    const approvalText = { height: 40, implicitHeight: 40 };
    Object.defineProperty(approvalText, "text", { get: () => root.hold?.text ?? "" });
    const ctx = vm.createContext({ root, approvalText, Qt: { callLater: fn => later.push(fn) } });
    // QML's indentation bounds each actual function. Refuse a missing or
    // duplicate extractor match before testing any callback.
    for (const name of ["approvalPolished", "approvalSynchronized", "approvalSwapped"]) {
        const matches = [...source.matchAll(new RegExp("^    function " + name + "\\(\\) \\{\\n[\\s\\S]*?^    \\}", "gm"))];
        assert.equal(matches.length, 1, "one shipped Bubble callback: " + name);
        // QML exposes root properties as local names in a handler.
        const run = vm.runInContext("(function() { with(root) { return (" + matches[0][0] + ").call(root); } })", ctx);
        root[name] = run;
    }
    const flush = () => { while (later.length) later.shift()(); };
    const propose = id => dispatch({ type: "approval", gen: 1, op: 4, id, digest: id, purpose: "action",
        text: "Fixture action", physical: false, tool: "fixture", timeoutMs: 1000, cancellable: false });
    const confirm = h => dispatch({ type: "confirm", gen: h.gen, id: h.id, digest: h.digest, source: "button" });

    root.approvalPolished(); // Earlier frame contains no request.
    propose("first");
    const h = root.hold;
    root.approvalPolished(); // Newer GUI state exists before old callbacks run.
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
}
const bubble = fs.readFileSync(path.join(dir, "Bubble.qml"), "utf8");
approvalFrames(bubble);
const frameNeedle = "const drawn = synchronizedHold;";
assert.equal(bubble.split(frameNeedle).length, 2, "one frame identity control match");
assert.throws(() => approvalFrames(bubble.replace(frameNeedle, "const drawn = root.hold;")), assert.AssertionError,
    "delivery from the current hold must fail the earlier-frame assertion");
console.log(`test-jarvis-widget: ok cases=${CASES.length} refusals=${REFUSALS.length} controls=${CONTROLS.length + 1} frame-control=detected`);
