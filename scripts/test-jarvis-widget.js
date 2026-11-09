#!/usr/bin/env node
// Jarvis's status-only bar projection runs the
// shipped WidgetView.js over Session records. The same input checks status,
// recovery links, system microphone observation and independent voice mute.
// Tooltip wording is product output: VGS-2312 requires the state-only title
// and forbids shortcut, selected-model and selected-voice details.
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
const PluginLogic = load(path.join(__dirname, "..", "shell/Core/PluginLogic.js"));
const keyNames = Object.assign(KeyNavLogic.symbolNames(PluginLogic.CAPTURE_KEY_NAMES), { "CODE:44": { keysym: "j", codepoint: 106 } });
const ShortcutLabels = { keyCaps: key => KeyNavLogic.keyCaps(key, keyNames) };
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
        ["starting", {}, "loading", "info", "info", "Starting", 0],
        ["closed", up(), "ready", "calm", "", "Ready", 0],
        ["open at rest", up({ conversation: { kind: "active", purpose: "conversation" } }), "ready", "calm", "", "Ready", 0],
        ["listening", up(OPEN), "listening", "accent", "success", "Listening", 0],
        ["capture opening", up({ capture: { kind: "opening", gen: 1, op: 2, mode: "conversation" } }), "listening", "accent", "success", "Listening", 0],
        ["capture closing", up({ capture: { kind: "closing", gen: 1, op: 2 } }), "listening", "accent", "success", "Listening", 0],
        ["thinking", up(THINKING), "working", "info", "info", "Thinking", 0],
        ["cancelling", up({ turn: { kind: "cancelling", gen: 1, op: 4, deadline: 70 } }), "working", "info", "info", "Thinking", 0],
        ["speaking", up({ playback: { kind: "playing", gen: 1, op: 5, source: 4, interruptible: true, admission: { kind: "started" }, deadline: null } }), "speaking", "accent", "success", "Speaking", 0],
        ["confirming", up({ approval: { kind: "held", purpose: "action", gen: 1, op: 6, id: "a1", digest: "d1", deadline: 90, shownAt: null,
            physical: true, text: "Fixture action", tool: "fixture", timeoutMs: 1000, cancellable: false, brain: 4 } }), "working", "info", "info", "Waiting for confirmation", 0],
        ["acting", up({ action: { kind: "running", gen: 1, op: 7, tool: "shell", brain: 4, limit: { kind: "expired" }, cancellation: { kind: "available" } } }), "working", "info", "info", "Running a task", 0],
        ["fault", up({ fault: { kind: "error", reason: "brain=stream-error", retry: 0 } }), "problem", "danger", "danger", "Problem", 1],
        ["audio fault", up({}, { audio: { tone: "danger", text: "capture-overflow" } }), "problem", "danger", "danger", "Problem", 1],
        ["daemon retry", up({}, { daemon: { tone: "warning", text: "Restarting", hint: "Jarvis is trying again by itself" } }), "problem", "danger", "danger", "Problem", 1],
        ["locked", up({ gate: { kind: "down", reason: "locked" } }), "off", "neutral", "warning", "Screen locked", 0],
        ["lock unknown", up({ gate: { kind: "down", reason: "lock-unknown" } }), "off", "neutral", "warning", "Checking screen lock", 0],
        ["node missing", up({ gate: { kind: "down", reason: "node" } }), "off", "neutral", "warning", "Not set up", 1],
        ["unconfigured", up({ gate: { kind: "down", reason: "unconfigured" } }), "off", "neutral", "warning", "Not set up", 1],
        ["system microphone muted", up({}, { microphoneMute: { kind: "ready", muted: true } }), "muted", "neutral", "warning", "Microphone muted", 0],
        ["system microphone muted while listening", up(OPEN, { microphoneMute: { kind: "ready", muted: true } }), "muted", "neutral", "warning", "Microphone muted", 0]
    ];
    for (const [label, values, state, tone, stateDot, title, actionLines] of rows) {
        const bar = view.view(values, null);
        assert.deepEqual([bar.state, bar.icon, bar.tone, bar.stateDot], [state, "vgs-letter-j", tone, stateDot], label);
        assert.ok(Object.hasOwn(Lucide.ICONS, bar.icon), label + ": shipped icon");
        assert.equal(bar.tooltip, "Jarvis: " + title, label + ": state-only product title");
        assert.equal(bar.tooltipDetails.length, actionLines, label + ": only the required action line");
        assert.equal(links(bar.tooltipDetails).length, actionLines, label + ": one link per action");
        assert.equal(links([bar.tooltip]).length, 0, label + ": status title has no link");
        assert.equal([bar.tooltip].concat(bar.tooltipDetails).some(line => /AI model:|Voice:|Press |Click |Tap or hold |Super\+/.test(line)), false, label + ": status only on the bar");
        if (values.detail !== undefined) {
            const hiddenValues = copy(values);
            hiddenValues.detail.state.visibility = { kind: "hidden" };
            const hidden = view.view(hiddenValues, null);
            assert.deepEqual([hidden.icon, hidden.stateDot, hidden.tooltip],
                ["vgs-letter-j-hidden", stateDot, bar.tooltip + " (hidden)"], label + ": held icon is independent of live state");
        }
    }
    const demand = Session.reduce(Session.reduce(Session.initial(), { type: "snapshot", at: 0,
        locked: false, configured: true, settings: {}, engine: "chained" }).state, { type: "hidden", at: 1 }).state;
    const waiting = Session.reduce(demand, { type: "talk-down", at: 2 }).state;
    assert.equal(waiting.capture.kind, "closed");
    const badge = view.view(up(waiting), null);
    assert.deepEqual([badge.state, badge.icon, badge.stateDot], ["listening", "vgs-letter-j-hidden", "success"],
        "real capture demand draws the listening badge before the host may admit it");
    assert.equal(view.view(up({ conversation: { kind: "interrupted", purpose: "conversation" } }), null).tooltip, "Jarvis: Ready");
    const values = up({}, { voiceRoute: { tone: "ok", text: "Fixture voice" } });
    values.detail.brain = "Fixture model";
    assert.deepEqual(copy(view.view(values, null).tooltipDetails), [], "status does not expose model or voice details");
    for (const mic of [undefined, { kind: "unavailable" }, { kind: "ready", muted: false }, { kind: "ready", muted: true }])
        for (const voice of [false, true]) {
            const values = up({ voiceMute: { kind: voice ? "on" : "off" } }, mic === undefined ? {} : { microphoneMute: mic });
            const bar = view.view(values, null);
            assert.equal(bar.tooltip, mic?.muted === true ? "Jarvis: Microphone muted" : "Jarvis: Ready");
            assert.deepEqual(copy(bar.tooltipDetails), [], "voice mute adds no tooltip detail");
            assert.equal(view.microphoneMuted(mic), mic?.kind === "ready" ? mic.muted : null, "unknown source stays unavailable");
            assert.equal(view.menuEntries(view.microphoneMuted(mic), voice)[0].intent, "voice-mute", "voice mute remains a menu action");
        }
    for (const cause of ["home=link", "brain=unselected", "speech=local-not-set-up"]) {
        const setup = SetupGate.readiness({ kind: "answered", causes: [cause] }, { kind: "ready", path: "/fixture" });
        const values = up({ gate: { kind: "down", reason: "unconfigured" } }, setup);
        const bar = view.view(values, null);
        assert.equal(bar.state, "off");
        assert.equal(links(bar.tooltipDetails).length, 1, cause + ": one usable recovery link");
        const target = links(bar.tooltipDetails)[0];
        if (cause === "home=link")
            assert.equal(pageReference.file(target.page), "/fixture/", cause + ": recovery opens the chosen Home folder");
        else assert.equal(target.page, "vgs.jarvis", cause + ": recovery stays on the plugin page");
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
    const defaults = Object.fromEntries(manifest.hyprland.binds.map(bind => [bind.shortcut, bind.key]));
    assert.deepEqual(copy(view.spelledKeys(defaults, ShortcutLabels.keyCaps)), KEYS);
    assert.deepEqual(copy(view.spelledKeys(null, ShortcutLabels.keyCaps)), UNBOUND);
    assert.deepEqual(copy(view.spelledKeys({}, ShortcutLabels.keyCaps)), UNBOUND);
    for (const mic of [null, false, true])
        for (const voice of [false, true]) {
            const menu = view.menuEntries(mic, voice, false, "indicator");
            assert.deepEqual(copy(menu.map(row => row.intent || row.page)), ["voice-mute", "microphone-mute", "stop", "new-conversation", "hide", "vgs.jarvis"]);
            assert.equal(menu[1].disabledReason !== "", mic === null);
            assert.equal(menu[0].label.startsWith("Unmute"), voice);
            assert.equal(menu[1].label.startsWith("Unmute"), mic === true);
            assert.ok(Object.hasOwn(Lucide.ICONS, menu[3].icon));
            assert.equal(menu[5].tab, "Settings/Keys");
        }
    for (const hidden of [false, true]) for (const block of [null, "indicator", "not-ready"]) {
        const row = view.menuEntries(false, false, hidden, block)[4];
        assert.equal(row.intent, hidden ? "show" : "hide");
        assert.equal(row.disabledReason !== "", !hidden && block !== null);
        assert.ok(Object.hasOwn(Lucide.ICONS, row.icon));
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
        assert.equal(out.tooltip, "Jarvis: Problem", "the state title exposes no model, voice or provider detail");
        assert.equal(out.tooltipDetails.length, 1, reason + ": exactly one action line");
        assert.equal(links(out.tooltipDetails).length, 1, reason + ": exactly one recovery link");
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
        ["microphone", up({}, { microphoneMute: { kind: "ready" } }), /microphoneMute=/]
    ]) assert.throws(() => view.view(values, null), error => pattern.test(error.message), label);
    verifyReplyCard(view);
}
// The reply card under the J (VGS-2339): while Jarvis Voice is muted or the
// orb is hidden, a fault, or the newest row of the current conversation
// when it is Jarvis's; a new answer is a new key; the answer settles once
// Jarvis neither thinks nor speaks.
function verifyReplyCard(view) {
    const row = (role, at, session = "1:0") => ({ gen: 1, role, text: role + " " + at, stage: "final", at, session, startedAt: 10 });
    const log = [row("user", 10), row("assistant", 20)];
    const muted = { voiceMute: { kind: "on" } };
    const hidden = { visibility: { kind: "hidden" } };
    const speaking = { playback: { kind: "playing", gen: 1, op: 5, source: 4, interruptible: true, admission: { kind: "started" }, deadline: null } };
    const fault = { fault: { kind: "error", reason: "brain=stream-error", retry: 0 } };
    const card = (regions, rows = log, session = "1:0") => view.replyCard(rows, detail(regions).state, session);
    assert.equal(card({}), null, "voice on and orb shown: no card");
    assert.deepEqual(card(muted), { key: "1:20", answer: { gen: 1, at: 20 }, fault: false, settled: true }, "muted: the newest answer");
    assert.deepEqual(card(hidden), { key: "1:20", answer: { gen: 1, at: 20 }, fault: false, settled: true }, "orb hidden: the newest answer");
    assert.deepEqual(card({ ...muted, ...hidden }), card(muted), "muted and hidden: the same card");
    assert.equal(card(muted, [row("assistant", 5), row("user", 30)]), null, "the user's words after an answer show no card");
    assert.equal(card(muted, log, "2:0"), null, "another conversation's rows show no card");
    assert.equal(card(muted, null), null, "no conversation log shows no card");
    assert.equal(card(muted, log.concat([row("assistant", 40)])).key, "1:40", "a newer answer replaces the card");
    assert.equal(card({ ...hidden, ...speaking }).settled, false, "an answer still spoken is not settled");
    assert.equal(card({ ...muted, ...THINKING }).settled, false, "an answer while Jarvis thinks again is not settled");
    assert.deepEqual(card({ ...hidden, ...fault }), { key: "fault:0:brain=stream-error", answer: null, fault: true, settled: true },
        "a fault reads on the card with no answer to open at");
    assert.equal(card(fault), null, "a fault with the voice on and the orb shown is the overlay's");
}
const source = fs.readFileSync(path.join(dir, "WidgetView.js"), "utf8");
verify(load(path.join(dir, "WidgetView.js")));
// Execute the service's reset notification owner. Repeated state snapshots
// cannot repeat the explanation, while a later reset has its own identity.
{
    const service = fs.readFileSync(path.join(dir, "Service.qml"), "utf8");
    const matches = [...service.matchAll(/^    function conversationChanged\(previous, current\) \{\n[\s\S]*?^    \}/gm)];
    assert.equal(matches.length, 1);
    const notices = [];
    const ctx = vm.createContext({ View: load(path.join(dir, "WidgetView.js")), notice: value => notices.push(value) });
    const deliver = vm.runInContext("(" + matches[0][0] + ")", ctx);
    let previous = { history: { kind: "current", epoch: 1 } };
    deliver(null, previous);
    assert.equal(notices.length, 0, "startup is not a reset");
    for (const [epoch, reason] of [[2, "requested"], [3, "turn-limit"]]) {
        const current = { history: { kind: "reset", epoch, reason } };
        deliver(previous, current);
        const expected = notices.length;
        deliver(current, current);
        assert.equal(notices.length, expected, "a repeated state keeps one explanation");
        previous = current;
    }
    assert.equal(notices.length, 2);
    for (const notice of notices) {
        assert.equal(notice.tone, "info");
        assert.ok(notice.message.length > 0);
        assert.ok(Object.hasOwn(Lucide.ICONS, notice.icon));
    }
    assert.notEqual(notices[0].message, notices[1].message, "automatic reset explains its different cause");
}
const controls = [
    ["bar loses recovery", '(state === "problem" || state === "off")', 'false'],
    ["bar changes the J while listening", '"listening": { icon: "vgs-letter-j"', '"listening": { icon: "audio-lines"'],
    ["bar loses state dots", 'stateDot: style.stateDot', 'stateDot: ""'],
    ["hidden icon lost", 'out.icon = "vgs-letter-j-hidden";', 'out.icon = "vgs-letter-j";'],
    ["badge waits for capture", 'Session.captureWanted(state)', 'false'],
    ["hide without an indicator", 'hideBlock === "indicator"', 'false'],
    ["bar restores shortcut guidance", 'tooltipDetails: recovery', 'tooltipDetails: recovery.concat(["Tap or hold Super+J to talk."])'],
    ["bar loses its state prefix", 'tooltip: "Jarvis: " + ', 'tooltip: "" + '],
    ["microphone guessed unmuted", 'function microphoneMuted(value) {\n    if (value === undefined) return null;', 'function microphoneMuted(value) {\n    if (value === undefined) return false;'],
    ["menu accepts missing source", 'micMuted === null ? "Connect a microphone or choose one in Sound" : ""', '""'],
    ["prompt loses file path", 'path: filePrompt && lines.length > 1 ? lines[1] : ""', 'path: ""'],
    ["report hint shape unchecked", 'if (value.hint !== undefined && typeof value.hint !== "string") refuse(name, value);', ''],
    ["reply card while the voice is on and the orb shows", 'if (state.voiceMute.kind !== "on" && state.visibility.kind !== "hidden") return null;', ''],
    ["reply card for another conversation", 'return row.session === session;', 'return true;'],
    ["reply card for the user's words", 'if (last === null || last.role !== "assistant") return null;', 'if (last === null) return null;'],
    ["reply card keeps the first answer", 'return { key: last.gen + ":" + last.at,', 'return { key: String(last.gen),'],
    ["reply card settles while Jarvis speaks", 'settled: phase !== "speaking" && phase !== "thinking"', 'settled: true'],
    ["reply card opens a fault's console", 'answer: null, fault: true, settled: true', 'answer: { gen: state.gen, at: 0 }, fault: true, settled: true'],
];
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "jarvis-widget-control-"));
try {
    fs.copyFileSync(path.join(dir, "SetupGate.js"), path.join(temp, "SetupGate.js"));
    fs.copyFileSync(path.join(dir, "Session.js"), path.join(temp, "Session.js"));
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
// The core's existing presentation owner observes real BarItems. Execute its
// shipped geometry and frame callbacks with explicit Qt boundary stand-ins;
// QML fixtures and the nested row still owe the real render/wire proof.
const barHostFile = path.join(__dirname, "../shell/Hosts/BarHost.qml");
const barHost = fs.readFileSync(barHostFile, "utf8");
// The bar host publishes each bar widget's declared cover, as Jarvis's reply
// card declares its box under the J: on the output, `x` across it and `top`
// and `bottom` counted down from the bar's bottom edge; an empty cover, a
// hidden widget, another kind or an unmapped bar publishes none.
function barCovers(source) {
    const found = [...source.matchAll(/^            function observeCovers\(\) \{\n[\s\S]*?^            \}/gm)];
    assert.equal(found.length, 1, "observeCovers: one shipped host reader");
    const screen = { name: "DP-1" };
    const widget = (cover, extra = {}) => ({ x: 1500, y: 0, width: 40, height: 28, visible: true, parent: { x: 0 }, cover, ...extra });
    const card = { x: -320, y: 32, width: 360, height: 120 };
    const empty = { x: 0, y: 0, width: 0, height: 0 };
    const ctx = vm.createContext({ windowTransform: null, visible: true, backingWindowVisible: true, screen, height: 28,
        host: { screenPresent: true, screen, hostKey: "bar:DP-1" }, itemRect: item => ({ x: item.x, y: item.y }),
        Plugins: { built: { "bar:DP-1": [
            { origin: "core", kind: "bar-widget", instance: widget(card) },
            { origin: "core", kind: "bar-widget", instance: widget(empty) },
            { origin: "core", kind: "bar-widget", instance: widget(card, { visible: false }) },
            { origin: "plugin", kind: "bar-widget", instance: widget(card) },
            { origin: "core", kind: "panel", instance: widget(card) }
        ] } } });
    const observe = vm.runInContext("(" + found[0][0] + ")", ctx);
    assert.deepEqual(copy(observe()), [{ output: "DP-1", x: 1180, width: 360, top: 4, bottom: 124 }]);
    ctx.visible = false;
    assert.deepEqual(copy(observe()), [], "an unmapped bar publishes no cover");
}
barCovers(barHost);
for (const [label, needle, replacement] of [
    ["covers counted from the bar's top", "top: at.y + cover.y - height, bottom: at.y + cover.y + cover.height - height", "top: at.y + cover.y, bottom: at.y + cover.y + cover.height"],
    ["covers of an unmapped bar", "if (!visible || !backingWindowVisible || !host.screenPresent || screen !== host.screen) return [];\n                const out = [];\n                for (const row of Plugins.built[host.hostKey] || []) {\n                    if (row.origin !== \"core\" || row.kind !== \"bar-widget\") continue;\n                    const widget = row.instance;\n                    const cover", "const out = [];\n                for (const row of Plugins.built[host.hostKey] || []) {\n                    if (row.origin !== \"core\" || row.kind !== \"bar-widget\") continue;\n                    const widget = row.instance;\n                    const cover"],
    ["covers of a hidden widget", "if (!(cover.width > 0 && cover.height > 0) || !widget.visible) continue;", "if (!(cover.width > 0 && cover.height > 0)) continue;"]
]) {
    assert.equal(barHost.split(needle).length, 2, label + ": one cover control target");
    assert.throws(() => barCovers(barHost.replace(needle, replacement)), assert.AssertionError, label);
}
function barFrames(source) {
    const later = [], publications = [];
    const ctx = vm.createContext({ frameEpoch: 0, frames: [], synchronizedFrame: null, candidates: [],
        visible: true, backingWindowVisible: true, observationHost: "bar:focused", host: { hostKey: "bar:focused" },
        Layers: { setBarFrame: (host, rows) => publications.push(copy(rows)) },
        Qt: { callLater: fn => later.push(fn) } });
    for (const name of ["invalidateFrame", "whole", "framePolished", "frameSynchronized", "frameSwapped"]) {
        const found = [...source.matchAll(new RegExp("^            function " + name + "\\([^\\n]*\\) \\{\\n[\\s\\S]*?^            \\}", "gm"))];
        assert.equal(found.length, 1, name + ": one shipped host callback");
        ctx[name] = vm.runInContext("(" + found[0][0] + ")", ctx);
    }
    const flush = () => { while (later.length) later.shift()(); };
    const row = { plugin: "fixture.indicator", revision: "a", output: "focused", key: "1", dot: "success" };
    ctx.candidates = [row];
    ctx.framePolished();
    assert.deepEqual(publications, [], "existence and polish grant no presentation");
    ctx.frameSynchronized();
    assert.deepEqual(publications, [], "sync without swap grants nothing");
    ctx.frameSwapped();
    flush();
    assert.deepEqual(publications.at(-1), [row]);
    for (const change of ["widget removed", "bar unmapped", "badge disappeared", "new generation", "wrong output"]) {
        ctx.framePolished();
        ctx.frameSynchronized();
        ctx.frameSwapped();
        ctx.candidates = [];
        ctx.invalidateFrame();
        flush();
        assert.deepEqual(publications.at(-1), [], change + ": an old queued frame cannot re-grant");
        ctx.candidates = [{ ...row, key: change }];
        ctx.framePolished();
        ctx.frameSynchronized();
        ctx.frameSwapped();
        flush();
        assert.deepEqual(publications.at(-1), copy(ctx.candidates));
    }
    // Qt's mapToItem is the dependency here, not another geometry judge.
    // These synthetic, untransformed items map by their parent offsets.
    const item = (parent, extra = {}) => ({ parent, x: 0, y: 0, width: 40, height: 24,
        visible: true, opacity: 1, scale: 1, rotation: 0, transform: [], clip: false,
        mapToItem(ancestor, x, y) {
            for (let node = this; node !== ancestor; node = node.parent) {
                assert.notEqual(node, null, "mapping reaches its known ancestor");
                x += node.x; y += node.y;
            }
            return { x, y };
        }, ...extra });
    ctx.contentItem = item(null, { width: 400, height: 40 });
    const widget = item(ctx.contentItem);
    const target = item(widget);
    assert.equal(ctx.whole(target, widget), true);
    for (const [node, key, value] of [
        [target, "visible", false], [widget, "visible", false], [widget, "opacity", 0],
        [widget, "x", -1], [widget, "x", 380], [widget, "scale", 0.5], [widget, "rotation", 10],
        [target, "width", 0]
    ]) {
        const old = node[key]; node[key] = value;
        assert.equal(ctx.whole(target, widget), false, key + ": only a whole visible indicator counts");
        node[key] = old;
    }
    widget.clip = true;
    widget.width = target.width - 1;
    assert.equal(ctx.whole(target, widget), false, "section clipping revokes presentation");
    widget.width = target.width;
    widget.shownX = 1;
    widget.shownWidth = widget.width - 1;
    assert.equal(ctx.whole(target, widget), false, "scroller and fade cover is not a presented widget");
    delete widget.shownX;
    delete widget.shownWidth;
    assert.equal(ctx.whole(target, item(null)), false, "foreign item is not this widget's indicator");
}
barFrames(barHost);
for (const [needle, replacement] of [
    ["drawn.epoch !== frameEpoch || ", ""],
    ["!at.visible || ", ""]
]) {
    assert.equal(barHost.split(needle).length, 2, "one host presentation control target");
    assert.throws(() => barFrames(barHost.replace(needle, replacement)), assert.AssertionError,
        "the host guard's removal must falsify its fixture");
}
{
    const source = fs.readFileSync(path.join(__dirname, "../shell/Core/Layers.qml"), "utf8");
    const found = [...source.matchAll(/^    function barIndicators\(ctx\) \{\n[\s\S]*?^    \}/gm)];
    assert.equal(found.length, 1, "one core publication reader");
    const records = {
        first: [{ plugin: "fixture.indicator", revision: "a", output: "one", key: "7:listening", dot: "success" }],
        second: [{ plugin: "other.indicator", revision: "a", output: "two", key: "7:listening", dot: "success" },
            { plugin: "fixture.indicator", revision: "old", output: "two", key: "7:listening", dot: "success" },
            { plugin: "fixture.indicator", revision: "a", output: "two", key: "7:present", dot: "" }],
        empty: []
    };
    const ctx = vm.createContext({ barFrames: records });
    // The nested QML run has no Array.flat. Exercise the shipped reader with
    // that API absent rather than borrowing Node's larger array API.
    vm.runInContext("Array.prototype.flat = undefined;", ctx);
    const read = vm.runInContext("(" + found[0][0] + ")", ctx);
    const consumer = { active: true, id: "fixture.indicator", manifest: { __revision: "a" } };
    const rows = read(consumer);
    assert.deepEqual(copy(rows), [{ output: "one", key: "7:listening", dot: "success" },
        { output: "two", key: "7:present", dot: "" }],
        "only this plugin and source revision can consume the host's frames");
    assert.ok(Object.isFrozen(rows) && rows.every(Object.isFrozen), "the consumer cannot mutate core presentation records");
    assert.deepEqual(copy(read({ ...consumer, active: false })), [], "retired provider grants nothing");
}
// Forced renewal recovery uses the real Service wire receiver and its existing
// notification owner. Ordinary captions never stand in for delivery.
function renewalNotices(source) {
    const protocol = load(path.join(dir, "JarvisProtocol.js"));
    for (const [label, state, generation, expected] of [
        ...["shown", "hidden"].flatMap(visibility => ["off", "on"].map(voiceMute => [
            visibility + "/" + voiceMute,
            { gen: 7, conversation: { kind: "active", purpose: "conversation" },
                visibility: { kind: visibility }, voiceMute: { kind: voiceMute } }, 7, 1
        ])),
        ["ended", { gen: 7, conversation: { kind: "ended" } }, 7, 0],
        ["stale", { gen: 8, conversation: { kind: "active", purpose: "conversation" } }, 7, 0],
        ["no-state", null, 7, 0]
    ]) {
        const notices = [];
        const ctx = vm.createContext({ Protocol: protocol, sessionState: state, cause: "", lifetime: { kind: "ready" }, outputTail: "",
            shell: { manifest: { __revision: "a".repeat(64) }, notify: { send: value => { notices.push(copy(value)); return "ok"; } },
                status: { set: () => assert.fail("renewal recovery is not a caption or a model turn") } },
            broken: value => assert.fail(value), console: { error: value => assert.fail(value) } });
        for (const name of ["receive", "voiceRenewal", "notice"]) {
            const found = source.match(new RegExp("^    function " + name + "\\([^\\n]*\\) \\{\\n[\\s\\S]*?^    \\}", "m"));
            assert.ok(found, name + ": shipped notification route");
            ctx[name] = vm.runInContext("(" + found[0] + ")", ctx);
        }
        ctx.receive(JSON.stringify({ v: 1, type: "voice-renewal", revision: "a".repeat(64), gen: generation }) + "\n");
        assert.equal(notices.length, expected, label + ": forced renewal reaches the user independently of hidden/voice state");
        if (expected) {
            assert.equal(notices[0].tone, "warning");
            assert.equal(notices[0].icon, "vgs-letter-j");
            assert.ok(notices[0].message.length > 0);
        }
    }
}
{
    const service = fs.readFileSync(path.join(dir, "Service.qml"), "utf8");
    renewalNotices(service);
    for (const [needle, replacement] of [
        ['message.gen !== sessionState.gen || sessionState.conversation.kind === "ended"',
            'sessionState.conversation.kind === "ended"'],
        ['        notice({ title: "Jarvis needs you to repeat that",', '        return; notice({ title: "Jarvis needs you to repeat that",']
    ]) {
        assert.equal(service.split(needle).length, 2, "one renewal notice control target");
        assert.throws(() => renewalNotices(service.replace(needle, replacement)), assert.AssertionError,
            "renewal notice control must falsify delivery or identity");
    }
}
// Service selection consumes host evidence for this generation and focused
// output. Its ordered wire retains loss edges, even if a badge returns before
// the queued callback runs. No widget callback produces this input.
function verifyIndicatorDelivery(service) {
    const found = [...service.matchAll(/^    readonly property string barIndicator: \{\n([\s\S]*?)^    \}/gm)];
    assert.equal(found.length, 1, "one service bar observation");
    const ctx = vm.createContext({ locked: false, lifetime: { kind: "ready" }, cause: "", focusedOutput: "focused",
        sessionState: { gen: 7 }, barPresentations: [] });
    const observe = vm.runInContext("(function() {" + found[0][1] + "})", ctx);
    const frame = { output: "focused", key: "7:listening", dot: "success" };
    for (const [rows, expected] of [
        [[], "gone"], [[frame], "listening"], [[{ ...frame, dot: "" }], "present"],
        [[{ ...frame, dot: "warning" }], "present"], [[{ ...frame, output: "other" }], "gone"],
        [[{ ...frame, key: "6:listening" }], "gone"], [[{ ...frame, key: "7:present" }], "present"]
    ]) {
        ctx.barPresentations = rows;
        assert.equal(observe(), expected);
    }
    ctx.barPresentations = [frame];
    ctx.locked = true;
    assert.equal(observe(), "gone", "screen lock never leaves an indicator grant");
    ctx.locked = false;
    const wires = [];
    Object.assign(ctx, { destroying: false, shell: { manifest: { __revision: "a".repeat(64) } }, indicatorDelivery: { kind: "unknown" },
        indicatorPresented: false, barIndicator: "listening", Protocol: load(path.join(dir, "JarvisProtocol.js")),
        child: { running: true, write: wire => wires.push(JSON.parse(wire)) }, broken: reason => assert.fail(reason) });
    const callback = [...service.matchAll(/^    function sendIndicator\(observation\) \{\n[\s\S]*?^    \}/gm)];
    assert.equal(callback.length, 1);
    const deliver = vm.runInContext("(" + callback[0][0] + ")", ctx);
    deliver({ shown: false, bar: "gone" });
    assert.equal(wires.at(-1).bar, "gone", "queued loss survives a returned badge");
    deliver({ shown: false, bar: "listening" });
    assert.equal(wires.at(-1).bar, "listening");
    ctx.barIndicator = "gone";
    deliver({ shown: true, bar: "listening" });
    assert.deepEqual([wires.at(-1).shown, wires.at(-1).bar], [false, "gone"], "queued positive cannot override current loss");
    ctx.barIndicator = "listening";
    ctx.sessionState = { gen: 8 };
    deliver({ shown: false, bar: "listening" });
    assert.equal(wires.at(-1).gen, 8, "unchanged presentation resends for the new generation");
    ctx.sendIndicator = deliver;
    ctx.indicatorObservations = [];
    ctx.root = ctx;
    const scheduled = new Set();
    ctx.Qt = { callLater: fn => scheduled.add(fn) };
    for (const name of ["queueIndicator", "flushIndicators"]) {
        const method = [...service.matchAll(new RegExp("^    function " + name + "\\(\\) \\{\\n[\\s\\S]*?^    \\}", "gm"))];
        assert.equal(method.length, 1, name + ": one existing service owner");
        ctx[name] = vm.runInContext("(" + method[0][0] + ")", ctx);
    }
    ctx.barIndicator = "gone";
    ctx.queueIndicator();
    ctx.barIndicator = "listening";
    ctx.queueIndicator();
    assert.equal(scheduled.size, 1, "the QObject-owned drain is coalesced");
    const beforeDrain = wires.length;
    for (const fn of scheduled) fn();
    scheduled.clear();
    assert.deepEqual(wires.slice(beforeDrain).map(wire => wire.bar), ["gone", "listening"], "coalescing retains the loss-return sequence");
    ctx.destroying = true;
    ctx.queueIndicator();
    deliver({ shown: true, bar: "listening" });
    assert.equal(scheduled.size, 0, "teardown schedules no new callback");
    assert.equal(wires.length, beforeDrain + 2, "teardown writes no new grant");
    ctx.destroying = false;
    const visibility = [...service.matchAll(/^    function setVisibility\(name\) \{\n[\s\S]*?^    \}/gm)];
    assert.equal(visibility.length, 1);
    const order = [];
    Object.assign(ctx, { sendIndicator: value => order.push(["indicator", value.bar]),
        sendIntent: name => order.push(["intent", name]) });
    const choose = vm.runInContext("(" + visibility[0][0] + ")", ctx);
    ctx.barIndicator = "gone";
    assert.equal(choose("hide"), "refused: hide=indicator");
    assert.deepEqual(order, []);
    assert.equal(choose("show"), "ok", "Show is the recovery route without a bar widget");
    assert.deepEqual(order, [["indicator", "gone"], ["intent", "show"]]);
    order.length = 0;
    ctx.barIndicator = "present";
    assert.equal(choose("hide"), "ok");
    assert.deepEqual(order, [["indicator", "present"], ["intent", "hide"]], "fresh host evidence precedes Hide");
}
{
    const service = fs.readFileSync(path.join(dir, "Service.qml"), "utf8");
    verifyIndicatorDelivery(service);
    for (const [label, needle, replacement] of [
        ["loss-overwritten", "indicatorObservations.push({ shown: indicatorPresented, bar: barIndicator });",
            "indicatorObservations = [{ shown: indicatorPresented, bar: barIndicator }];"],
        ["queue-after-release", "if (destroying) return;", "if (false) return;"]
    ]) {
        assert.equal(service.split(needle).length, 2, label + ": one owner control target");
        assert.throws(() => verifyIndicatorDelivery(service.replace(needle, replacement)), assert.AssertionError,
            label + ": the real owner must fail its existing sequence assertion");
    }
}
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
