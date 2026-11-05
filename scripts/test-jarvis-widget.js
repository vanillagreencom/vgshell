#!/usr/bin/env node
// Jarvis's status-only bar projection runs the
// shipped WidgetView.js over Session records. The same input checks status,
// recovery links, system microphone observation and independent voice mute.
// The service callbacks below protect notice and approval-frame identity.
// No process, network, audio or real clock is used.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const vm = require("node:vm");
const { load: loadLibrary } = require("../bin/lib/qml-library.js");
const pageReference = loadLibrary(path.join(__dirname, "..", "shell/Commons/PageReference.js"));
const load = file => loadLibrary(file, { "qs.Commons 1.0": { PageReference: pageReference } });
const dir = path.join(__dirname, "..", "shell/plugins/vgs.jarvis");
const Session = load(path.join(dir, "Session.js"));
const SetupGate = load(path.join(dir, "SetupGate.js"));
const KeyNavLogic = load(path.join(__dirname, "..", "shell/Ui/foundation/KeyNavLogic.js"));
const Lucide = load(path.join(__dirname, "..", "shell/Ui/icons/Lucide.js"));
const manifest = JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf8"));
const copy = value => JSON.parse(JSON.stringify(value));
const KEYS = { talk: "Super+J", "voice-mute": "Super+Ctrl+M", stop: "Super+Ctrl+X", confirm: "Super+Ctrl+Y", deny: null, console: "Super+Alt+C" };
const UNBOUND = Object.fromEntries(Object.keys(KEYS).map(key => [key, null]));
const OPEN = { capture: { kind: "open", gen: 1, op: 2, mode: "conversation" }, conversation: { kind: "active", purpose: "conversation" } };
const THINKING = { turn: { kind: "thinking", gen: 1, op: 4, deadline: 70 } };
function detail(regions = {}) {
    const state = Object.assign(copy(Session.initial()), { gate: { kind: "up" } }, copy(regions));
    assert.equal(Session.validate(state), true, "the fixture follows the current Session record");
    return { phase: Session.phaseOf(state), seq: 1, state };
}
const up = (regions = {}, extra = {}) => ({ daemon: { tone: "info", text: "Ready" }, audio: { tone: "ok", text: "Devices" }, detail: detail(regions), ...extra });
const links = lines => lines.flatMap(line => Array.from(pageReference.references(line).links));
function verify(view) {
    const rows = [
        ["starting", {}, "loading", "loader", "info"],
        ["closed", up(), "ready", "vgs-letter-j", "calm"],
        ["open at rest", up({ conversation: { kind: "active", purpose: "conversation" } }), "ready", "vgs-letter-j", "calm"],
        ["listening", up(OPEN), "listening", "audio-lines", "accent"],
        ["capture opening", up({ capture: { kind: "opening", gen: 1, op: 2, mode: "conversation" } }), "listening", "audio-lines", "accent"],
        ["capture closing", up({ capture: { kind: "closing", gen: 1, op: 2 } }), "listening", "audio-lines", "accent"],
        ["thinking", up(THINKING), "working", "brain", "info"],
        ["cancelling", up({ turn: { kind: "cancelling", gen: 1, op: 4, deadline: 70 } }), "working", "brain", "info"],
        ["speaking", up({ playback: { kind: "playing", gen: 1, op: 5, source: 4, interruptible: true, admission: { kind: "started" }, deadline: null } }), "speaking", "volume-2", "accent"],
        ["confirming", up({ approval: { kind: "held", purpose: "action", gen: 1, op: 6, id: "a1", digest: "d1", deadline: 90, shownAt: null,
            physical: true, text: "Fixture action", tool: "fixture", timeoutMs: 1000, cancellable: false, brain: 4 } }), "working", "brain", "info"],
        ["acting", up({ action: { kind: "running", gen: 1, op: 7, tool: "shell", brain: 4, limit: { kind: "expired" }, cancellation: { kind: "available" } } }), "working", "brain", "info"],
        ["fault", up({ fault: { kind: "error", reason: "brain=stream-error", retry: 0 } }), "problem", "circle-alert", "danger"],
        ["audio fault", up({}, { audio: { tone: "danger", text: "capture-overflow" } }), "problem", "circle-alert", "danger"],
        ["locked", up({ gate: { kind: "down", reason: "locked" } }), "off", "vgs-letter-j", "neutral"],
        ["unconfigured", up({ gate: { kind: "down", reason: "unconfigured" } }), "off", "vgs-letter-j", "neutral"],
        ["system microphone muted", up({}, { microphoneMute: { kind: "ready", muted: true } }), "muted", "mic-off", "neutral"],
        ["system microphone muted while listening", up(OPEN, { microphoneMute: { kind: "ready", muted: true } }), "muted", "mic-off", "neutral"]
    ];
    for (const [label, values, state, icon, tone] of rows) {
        const bar = view.view(values, null);
        assert.deepEqual([bar.state, bar.icon, bar.tone], [state, icon, tone], label);
        assert.ok(Object.hasOwn(Lucide.ICONS, bar.icon), label + ": shipped icon");
        assert.ok(links(bar.tooltipDetails).length <= 1, label + ": at most one recovery link");
        assert.equal(links([bar.tooltip]).length, 0, label + ": status title has no link");
        assert.equal(bar.tooltipDetails.some(line => /AI model:|Voice:|Press |Click |Super\+/.test(line)), false, label + ": status only on the bar");
    }
    assert.equal(view.view(up(), null).tooltip, "Conversation closed");
    assert.equal(view.view(up({ conversation: { kind: "active", purpose: "conversation" } }), null).tooltip, "Conversation open");
    assert.equal(view.view(up({ conversation: { kind: "interrupted", purpose: "conversation" } }), null).tooltip, "Conversation open");
    const values = up({}, { voiceRoute: { tone: "ok", text: "Fixture voice" } });
    values.detail.brain = "Fixture model";
    assert.deepEqual(copy(view.view(values, null).tooltipDetails), [], "status does not expose model or voice details");
    for (const mic of [undefined, { kind: "unavailable" }, { kind: "ready", muted: false }, { kind: "ready", muted: true }])
        for (const voice of [false, true]) {
            const values = up({ voiceMute: { kind: voice ? "on" : "off" } }, mic === undefined ? {} : { microphoneMute: mic });
            const bar = view.view(values, null);
            const drawn = [bar.tooltip].concat(bar.tooltipDetails);
            assert.equal(drawn.filter(text => text === "Microphone muted").length, mic?.muted === true ? 1 : 0);
            assert.equal(drawn.includes("Jarvis's voice muted"), voice, "voice mute stays independent");
            assert.equal(view.microphoneMuted(mic), mic?.kind === "ready" ? mic.muted : null, "unknown source stays unavailable");
        }
    for (const cause of ["home=link", "brain=unselected", "speech=local-not-set-up"]) {
        const setup = SetupGate.readiness({ kind: "answered", causes: [cause] }, { kind: "ready", path: "/fixture" });
        const values = up({ gate: { kind: "down", reason: "unconfigured" } }, setup);
        const bar = view.view(values, null);
        assert.equal(bar.state, "off");
        assert.equal(links(bar.tooltipDetails).length, 1, cause + ": one usable recovery link");
        assert.equal(links(bar.tooltipDetails)[0].page, "vgs.jarvis", cause + ": recovery stays on the plugin page");
    }
    const files = up({ gate: { kind: "down", reason: "unconfigured" } }, {
        setupHome: { tone: "warning", text: "Cannot use folder", hint: "Check " + pageReference.fileReference("AGENTS.md", "/fixture/AGENTS.md")
            + " and " + pageReference.fileReference("skills folder", "/fixture/skills/") }
    });
    const home = view.view(files, null);
    assert.deepEqual(copy(links(home.tooltipDetails).map(link => pageReference.file(link.page))), ["/fixture/AGENTS.md"]);
    assert.ok(pageReference.plain(home.tooltipDetails.join(" ")).includes("skills folder"), "the second target retains its words");
    const summary = SetupGate.sessionSummary({ tone: "ok", text: "Ready" }, { tone: "warning", text: "Cannot start" });
    assert.equal(view.view(up({}, { setup: summary }), null).state, "ready", "optional session never blocks Talk");
    const record = { model: "fixture-model", since: "11:02", offer: { unlock: "1password" }, steps: [], checkedAt: null };
    const resumed = view.view(up({}, { jarvisSession: record }), null);
    assert.equal(resumed.click, "resume");
    assert.equal(resumed.tooltip, "Resume Jarvis from before the restart", "the offer keeps its actionable title");
    record.offer = null;
    assert.deepEqual(copy(view.view(up({}, { jarvisSession: record }), null).tooltipDetails), [], "session model and start time are not bar details");
    const defaults = Object.fromEntries(manifest.hyprland.binds.map(bind => [bind.shortcut, bind.key]));
    assert.deepEqual(copy(view.spelledKeys(defaults, KeyNavLogic.keyCaps)), KEYS);
    assert.deepEqual(copy(view.spelledKeys(null, KeyNavLogic.keyCaps)), UNBOUND);
    assert.deepEqual(copy(view.spelledKeys({}, KeyNavLogic.keyCaps)), UNBOUND);
    for (const mic of [null, false, true])
        for (const voice of [false, true]) {
            const menu = view.menuEntries(mic, voice);
            assert.deepEqual(copy(menu.map(row => row.intent || row.page)), ["voice-mute", "microphone-mute", "stop", "vgs.jarvis"]);
            assert.equal(menu[1].disabledReason !== "", mic === null);
            assert.equal(menu[0].label.startsWith("Unmute"), voice);
            assert.equal(menu[1].label.startsWith("Unmute"), mic === true);
            assert.equal(menu[3].tab, "Settings/Keys");
        }
    const faultKinds = [
        ["thinking-timeout", "slow"], ["device-lost target=fixture", "device"],
        ["brain=stream-error", "brain"], ["net=timeout", "brain"],
        ["speech=local-ready-timeout", "localVoice"], ["speech=dictation-busy", "dictationBusy"],
        ["speech=dictation-failed", "dictation"], ["speech=local-not-ready", "voice"],
        ["playback-source: jarvis: speech=elevenlabs-http status=401", "elevenlabs"],
        ["capture-overflow", "audio"], ["home=link", "home"], ["guidance=home-skills-too-large", "home"],
        ["brain=harness-model-refused model=fixture-model", "model"], ["live=key-refused", "keyRefused"],
        ["engine=unexpected", "other"]
    ];
    for (const [reason, kind] of faultKinds) {
        const fault = { kind: "error", reason, retry: 0 };
        assert.equal(view.faultKind(fault), kind, reason + ": the current producer's category");
        const out = view.view(up({ fault }), null);
        assert.equal(out.state, "problem");
        assert.equal(/(?:jarvis: )?[a-z-]+=[a-z0-9-]/.test(out.tooltip + " " + out.tooltipDetails.join(" ")), false);
    }
    const bent = (change) => { const values = up(); change(values.detail); return values; };
    for (const [values, category] of [
        [bent(d => { d.state.capture = { kind: "ajar" }; }), "capture"],
        [bent(d => { d.state.gate = { kind: "sideways" }; }), "gate"],
        [bent(d => { d.state.gate = { kind: "down", reason: "asleep" }; }), "gate"],
        [bent(d => { d.phase = "dreaming"; }), "phase"],
        [bent(d => { d.phase = "listening"; }), "phase"],
        [bent(d => { d.phase = "error"; }), "fault"]
    ]) assert.throws(() => view.view(values, null), error => error.message.startsWith("jarvis widget: " + category + "="));
    assert.equal(view.approvalPrompt(null), null);
    for (const [tool, purpose, file] of [["files.write", "action", true], ["apps.open", "action", true], ["harness.files", "action", true], ["files.write", "release", false], ["fixture", "action", false]]) {
        const prompt = view.approvalPrompt({ tool, purpose, text: "question\npath\npayload" });
        assert.deepEqual([prompt.filePrompt, prompt.detail, prompt.question, prompt.path, prompt.payload], file
            ? [true, true, "question", "path", "payload"] : [false, false, "question\npath\npayload", "", ""]);
    }
    for (const [label, values, pattern] of [
        ["daemon", { daemon: { tone: "ok", text: "Ready" } }, /daemon=/],
        ["hint", { daemon: { tone: "info", text: "Starting", hint: [] } }, /daemon=/],
        ["audio", { audio: { tone: "warning", text: "Devices" } }, /audio=/],
        ["detail", { detail: "idle" }, /detail=/],
        ["microphone", up({}, { microphoneMute: { kind: "ready" } }), /microphoneMute=/],
        ["session reading", up({}, { jarvisSession: "x" }), /jarvisSession=/]
    ]) assert.throws(() => view.view(values, null), error => pattern.test(error.message), label);
}
const source = fs.readFileSync(path.join(dir, "WidgetView.js"), "utf8");
verify(load(path.join(dir, "WidgetView.js")));
const controls = [
    ["bar loses recovery", '(state === "problem" || state === "off")', 'false'],
    ["microphone guessed unmuted", 'if (value === undefined) return null;', 'if (value === undefined) return false;'],
    ["voice status lost", 'lines.push("Jarvis\'s voice muted")', 'void ("Jarvis\'s voice muted")'],
    ["menu accepts missing source", 'micMuted === null ? "Connect a microphone or choose one in Sound" : ""', '""'],
    ["prompt loses file path", 'path: filePrompt && lines.length > 1 ? lines[1] : ""', 'path: ""'],
    ["report hint shape unchecked", 'if (value.hint !== undefined && typeof value.hint !== "string") refuse(name, value);', ''],
];
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "jarvis-widget-control-"));
try {
    fs.copyFileSync(path.join(dir, "SetupGate.js"), path.join(temp, "SetupGate.js"));
    for (const [label, needle, replacement] of controls) {
        assert.equal(source.split(needle).length, 2, label + ": one mutation target");
        const changed = source.replace(needle, replacement);
        assert.notEqual(changed, source);
        const file = path.join(temp, "WidgetView.js");
        fs.writeFileSync(file, changed);
        assert.throws(() => verify(load(file)), assert.AssertionError, label);
    }
} finally { fs.rmSync(temp, { recursive: true, force: true }); }

// The service owns notice deduplication across daemon and conversation
// lifetimes. Run its shipped callback, with the same settings held read-only.
{
    const source = fs.readFileSync(path.join(dir, "Service.qml"), "utf8");
    const matches = [...source.matchAll(/^    function modelFallback\(message\) \{\n[\s\S]*?^    \}/gm)];
    assert.equal(matches.length, 1);
    const backup = Object.freeze({ model: "claude-opus-5-5" });
    const notices = [], settings = Object.freeze({ model: "claude-opus-5.5", fallbacks: Object.freeze([backup]) });
    const saved = JSON.stringify(settings);
    const ctx = vm.createContext({ shell: { settings }, sessionState: { gen: 7 }, modelNotices: new Set(),
        View: load(path.join(dir, "WidgetView.js")), notice: value => notices.push(value) });
    const deliver = vm.runInContext("(" + matches[0][0] + ")", ctx);
    const choice = { saved: settings.model, used: "claude-fable-5-1" };
    for (const gen of [7, 8, 9]) {
        ctx.sessionState = { gen };
        deliver({ ...choice, gen });
    }
    deliver({ ...choice, gen: 8, saved: backup.model });
    assert.equal(notices.length, 1, "one notice for a saved value across conversations and daemon messages");
    for (const gen of [10, 11, 12]) {
        ctx.sessionState = { gen };
        deliver({ ...choice, gen, saved: backup.model });
    }
    assert.equal(notices.length, 2, "a refused last backup also gets one notice");
    assert.equal(JSON.stringify(settings), saved, "primary and backup settings stay as written");
    ctx.shell.settings = Object.freeze({ model: "", fallbacks: Object.freeze([]) });
    deliver({ ...choice, gen: 12, saved: "claude-fable-5-1", used: "" });
    assert.equal(notices.length, 2, "an inferred model with no stored choice raises no saved-choice notice");
    ctx.shell.settings = Object.freeze({ model: "claude-fable-5-1", fallbacks: Object.freeze([]) });
    deliver({ ...choice, gen: 12, saved: "claude-fable-5-1", used: "" });
    assert.equal(notices.length, 3, "saving that same value later still gets its notice");
    for (const [index, model, field] of [[0, choice.saved, "model"], [1, backup.model, "fallbacks"]]) {
        for (const value of [model, choice.used]) assert.ok(notices[index].message.includes(value));
        assert.equal(notices[index].tone, "info");
        const links = pageReference.references(notices[index].message).links;
        assert.equal(links.length, 1);
        assert.deepEqual([links[0].page, links[0].tab], ["vgs.jarvis", "Settings/" + field]);
    }
    assert.equal(pageReference.references(ctx.View.modelFallbackNotice({ saved: choice.saved, used: "" }).message).links.length, 1);
}

// Execute Bubble's shipped callbacks with controlled GUI/render ordering.
// The nested bubble row proves rendering; this case proves which queued frame
// may acknowledge a real Session hold, without a second frame owner.
function approvalFrames(source) {
    let state = detail({ conversation: { kind: "active", purpose: "conversation" }, gen: 1, ...THINKING }).state;
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
    root.width = 800;
    root.height = 600;
    root.overlay = { x: 16, y: 16, width: 400, height: 300 };
    const approvalText = { x: 0, y: 0, width: 360, height: 40, implicitHeight: 40 };
    Object.defineProperty(approvalText, "text", { get: () => root.hold?.text ?? "" });
    const ctx = vm.createContext({ root, approvalText, Qt: { callLater: fn => later.push(fn) } });
    // The shipped binding, evaluated like the callbacks, so a frame gates on
    // the column Bubble itself calls whole.
    const whole = [...source.matchAll(/^    readonly property bool approvalWhole: ([\s\S]*?)\n(?=    \S)/gm)];
    assert.equal(whole.length, 1, "one shipped Bubble binding: approvalWhole");
    const approvalWhole = vm.runInContext("(function() { with(root) { return (" + whole[0][1] + "); } })", ctx);
    Object.defineProperty(root, "approvalWhole", { get: approvalWhole });
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
    approvalText.height = approvalText.implicitHeight - 1;
    root.approvalPolished();
    root.approvalSynchronized();
    root.approvalSwapped();
    flush();
    assert.equal(state.approval.shownAt, null, "a frame that clips the request's column cannot acknowledge");
    approvalText.height = approvalText.implicitHeight;
    root.approvalPolished();
    root.approvalSynchronized();
    root.approvalSwapped();
    flush();
    assert.notEqual(state.approval.shownAt, null, "the placed whole frame acknowledges its request");
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
const wholeNeedle = "\n        && approvalText.height >= approvalText.implicitHeight";
assert.equal(bubble.split(wholeNeedle).length, 2, "one whole-column control match");
assert.throws(() => approvalFrames(bubble.replace(wholeNeedle, "")), assert.AssertionError,
    "a frame that clips the request's column must fail the whole-column assertion");
console.log(`test-jarvis-widget: ok frame-controls=3 frame-control=detected`);
