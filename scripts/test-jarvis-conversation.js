#!/usr/bin/env node
// Pure conversation log contract for the Jarvis console. No daemon runs.
"use strict";
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { load } = require("../bin/lib/qml-library.js");
const file = path.resolve(__dirname, "../shell/plugins/vgs.jarvis/Conversation.js");
const Conversation = load(file);
const entry = (gen, role, text, stage) => ({ gen, role, text, stage, at: gen * 1000, session: "session-" + gen });
const byteLength = rows => Buffer.byteLength(JSON.stringify(rows));

function contract(logic) {
    let log = logic.start();
    assert.deepEqual(log, []);
    log = logic.update(log, entry(1, "assistant", "hel", "partial"));
    assert.deepEqual(log, [entry(1, "assistant", "hel", "partial")]);
    log = logic.update(log, entry(1, "assistant", "hello", "partial"));
    assert.deepEqual(log, [entry(1, "assistant", "hello", "partial")], "open segment is replaced");
    const later = logic.update(log, { ...entry(1, "assistant", "hello", "partial"), at: 2000 });
    assert.equal(later[0].at, 1000, "partial captions retain their first observed time");
    log = logic.update(log, entry(1, "assistant", "hello", "final"));
    assert.deepEqual(log, [entry(1, "assistant", "hello", "final")], "final closes segment");
    log = logic.update(log, entry(1, "assistant", "again", "partial"));
    assert.deepEqual(log, [entry(1, "assistant", "hello", "final"), entry(1, "assistant", "again", "partial")]);
    log = logic.update(log, entry(1, "user", "typed", "final"));
    assert.deepEqual(log, [entry(1, "assistant", "hello", "final"), entry(1, "assistant", "again", "partial"), entry(1, "user", "typed", "final")], "role change appends");
    const nextGen = { ...entry(2, "assistant", "new", "partial"), session: "session-1" };
    let genLog = logic.update([entry(1, "assistant", "old", "partial")], nextGen);
    assert.deepEqual(genLog, [entry(1, "assistant", "old", "partial"), nextGen], "generation change appends within retained brain context");
    let many = [];
    for (let i = 0; i < 80; i++) many = logic.update(many, entry(i, "assistant", "row" + i, "final"));
    assert.equal(many.length, 64);
    assert.equal(many[0].text, "row16");
    let huge = [];
    const chunk = "語".repeat(logic.Protocol.Session.TRANSCRIPT_CHARS);
    for (let i = 0; i < 64; i++) huge = logic.update(huge, entry(i, "assistant", chunk, "final"));
    assert.ok(byteLength(huge) <= 24 * 1024);
    assert.ok(huge.length < 64, "byte ceiling drops oldest rows");
    previewBetweenTurns(logic);
}

// Drive the real preview intent between a user's question and their next
// turn. Its partial and final captions still reach the wire for feedback.
function previewBetweenTurns(logic) {
    const Session = logic.Protocol.Session;
    let state = Session.initial(), log = [], time = 0;
    function dispatch(type, values = {}) {
        const result = Session.reduce(state, { type, at: ++time, ...values });
        state = result.state;
        for (const effect of result.effects.filter(item => item.kind === "transcript"))
            log = logic.update(log, { ...effect, at: time, session: "child:" + state.history.epoch, started: 1 });
        return result.effects;
    }
    const turn = () => ({ op: state.turn.op, gen: state.gen });
    const caption = (text, stage) => dispatch("transcript", { ...turn(), role: "assistant", rev: time, text, stage });
    dispatch("snapshot", { locked: false, configured: true, engine: "chained", settings: { holdToTalk: true } });
    const epoch = state.history.epoch;
    dispatch("say", { text: "Real question" });
    caption("Real answer", "final");
    dispatch("brain-done", turn());
    assert.deepEqual(log.map(row => row.text), ["Real question", "Real answer"]);
    const before = JSON.stringify(log);
    assert.ok(dispatch("preview", { voice: "Fixture" }).some(e => e.kind === "brain-send" && e.preview));
    for (const [text, stage] of [["This is how", "partial"], ["This is how I sound when I answer you.", "final"]]) {
        assert.ok(caption(text, stage).some(e => e.kind === "transcript"), "preview produces its live caption");
        assert.equal(JSON.stringify(log), before, "preview leaves both real turns intact");
    }
    dispatch("brain-done", turn());
    dispatch("say", { text: "Real follow-up" });
    dispatch("conversation-reset", { ...turn(), text: "Real follow-up", reason: "turn-limit" });
    assert.deepEqual(log.map(row => [row.session, row.text]), [["child:" + epoch, "Real question"],
        ["child:" + epoch, "Real answer"], ["child:" + (epoch + 1), "Real follow-up"]]);
}
contract(Conversation);

// History reads its fault rows' plain words from WidgetView, whose links
// come from the shell's PageReference.
const historyModules = { "qs.Commons 1.0": { PageReference: load(path.resolve(__dirname, "../shell/Commons/PageReference.js")) } };
const History = load(path.resolve(__dirname, "../shell/plugins/vgs.jarvis/History.js"), historyModules);
const morning = new Date(2026, 10, 1, 9).getTime(), nextDay = new Date(2026, 10, 2, 9).getTime();
const transcript = [
    { ...entry(1, "user", "Voice question", "final"), at: morning, session: "first" },
    { ...entry(1, "assistant", "Answer", "final"), at: morning + 1000, session: "first" },
    { ...entry(3, "user", "Same day, other session", "final"), at: morning + 2000, session: "first" },
    { ...entry(3, "assistant", "Next day", "final"), at: nextDay, session: "first" }
];
const sessions = Conversation.sessions(transcript);
assert.deepEqual(sessions.map(row => [row.title, row.started]), [["Same day, other session", morning + 2000], ["Voice question", morning]]);
for (const word of ["VOICE", "Answer"]) {
    assert.deepEqual(History.search(sessions, word).map(s => s.turns.map(turn => turn.text)), [["Voice question", "Answer"]]);
}
assert.equal(History.search(sessions, "missing").length, 0);
const preview = "This is how I sound when I answer you.";
assert.deepEqual(Conversation.sessions([entry(1, "assistant", preview, "final"), entry(2, "user", preview, "final"),
    { ...entry(3, "assistant", preview, "final"), source: "conversation" }]).map(row => row.id), ["session-3:3", "session-2:2"]);
let retained = [];
for (let i = 0; i < 70; i++)
    retained = Conversation.update(retained, { ...entry(1, i % 2 ? "assistant" : "user", "Message " + i, "final"), started: 200, at: 300 + i });
assert.deepEqual(Conversation.sessions(retained).map(s => [s.title, s.started, s.expired, s.turns.length]), [["Message 0", 200, true, 64]]);
let boundary = [];
for (const [epoch, origin, text] of [[0, 1, "Again"], [0, 2, "At the limit"], [1, 2, "At the limit"], [1, 3, "Again"]])
    boundary = Conversation.update(boundary, { ...entry(1, "user", text, "final"), session: "child:" + epoch, started: epoch, origin,
        source: epoch === 1 && origin === 2 ? "context-reset" : "conversation" });
assert.deepEqual(History.search(Conversation.sessions(boundary), "limit").map(s => s.turns.map(row => row.text)), [["At the limit", "Again"]]);
assert.equal(History.search(Conversation.sessions(boundary), "Again").length, 2, "separate requests may repeat the same words");
// A reset transfers only the input that crossed the limit. An evicted
// older question belongs to the previous session; an evicted first
// segment of the boundary question belongs to the new one.
for (const large of [false, true]) {
    let log = [];
    const add = (session, origin, text, source = "conversation") => {
        log = Conversation.update(log, { ...entry(1, "user", text, "final"), started: 20, session, origin, source });
    };
    add("old", "2:earlier", "Earlier title");
    const first = "Opening question " + "a".repeat(4079);
    add("old", "2:boundary", first);
    if (large) {
        for (let i = 0; i < 15; i++) add("old", "2:boundary", "Later segment " + "b".repeat(4082));
    } else {
        // The count ceiling drops only the preceding unrelated question.
        for (let i = 0; i < 63; i++) add("old", "2:other-" + i, "Short");
    }
    assert.ok(log[0].expired);
    add("new", "2:boundary", first, "context-reset");
    const moved = Conversation.sessions(log).find(session => session.id === "new:1");
    assert.equal(moved.expired, large);
    assert.equal(moved.title, "Opening question " + "a".repeat(46) + "…");
    assert.equal(moved.turns.some(row => row.text === first), !large);
}
{
    const Session = Conversation.Protocol.Session;
    let state = Session.initial(), log = [], at = 0;
    function send(type, fields = {}) {
        const result = Session.reduce(state, { at: ++at, type, ...fields });
        state = result.state;
        for (const caption of result.effects.filter(e => e.kind === "transcript"))
            log = Conversation.update(log, { ...caption, at, started: state.history.epoch, session: "native:" + state.history.epoch });
    }
    send("snapshot", { engine: "duplex", locked: false, configured: true, settings: {} });
    send("indicator", { shown: true, bar: "gone", gen: state.gen });
    send("toggle");
    const speech = { gen: state.gen, op: state.speech.op };
    const caption = (item, text, stage) => send("transcript", { ...speech, item, role: "user", text, stage, rev: at });
    caption("earlier", "Again", "final");
    caption("limit", "At the limit", "final");
    caption("limit", "second seg", "partial");
    send("delegation", { ...speech, id: "limit", text: "At the limit second segment" });
    send("conversation-reset", { gen: state.gen, op: state.turn.op, reason: "turn-limit", text: "At the limit second segment" });
    caption("limit", "second segment", "final");
    const found = History.search(Conversation.sessions(log), "limit");
    assert.deepEqual(found.map(session => session.turns.map(turn => turn.text)), [["At the limit", "second segment"]]);
    assert.deepEqual(Conversation.sessions(log)[1].turns.map(turn => turn.text), ["Again"]);
}
const refusal = { time: new Date(morning).toISOString(), tool: "files.delete", decision: "refuse", outcome: "cancelled", refusal: "identity", cause: null };
const shown = History.problems([refusal], "")[0];
assert.equal(shown.title, "Deleting a file was refused.");
assert.equal(shown.body, "The request changed before approval.");
assert.equal(shown.action, "Ask Jarvis again");
assert.equal(History.problems([refusal], "missing filename").length, 0, "the audit never supplies an invented filename");
// Audit publishes only current voice failure categories after its migration.
for (const cause of ["key-refused", "voice-stopped"]) {
    const voice = History.problems([{ ...refusal, tool: "release", decision: "send", outcome: "failed", refusal: null, cause }], "voice")[0];
    assert.equal(voice.title, "Voice stopped.");
    assert.equal(typeof voice.body, "string");
    assert.equal(voice.settings, true);
}
const failedRelease = History.problem({ ...refusal, tool: "release", decision: "send", outcome: "failed", refusal: null });
assert.equal(failedRelease.settings, false, "a failed release without a current cause offers no voice setting");
assert.equal(typeof failedRelease.body, "string");
assert.equal(History.tasks([{ goal: "Fix console", agent: "runtime", state: "working" }], "RUNTIME").length, 1);

function operationContract(history) {
    // Discover every shipped tool and browser effect from the producer,
    // including null effects from refusals before argument refinement.
    const Tools = require("../shell/plugins/vgs.jarvis/backend/Tools.js");
    assert.ok(Object.hasOwn(Tools.TABLE, "files.read"));
    assert.equal(Object.hasOwn(Tools.TABLE, "unknown"), false);
    for (const [tool, spec] of Object.entries(Tools.TABLE)) {
        const effects = tool === "browser" ? Object.values(Tools.BROWSER).map(value => value.effect) : [spec.effect ?? null];
        for (const effect of new Set([null, ...effects])) {
            const title = history.problem({ ...refusal, tool, effect }).title;
            assert.ok(!title.startsWith("The action"), "published operation needs a label: " + tool + "/" + effect);
        }
    }
    const cases = [
        ["files.read", "read", "file", "Reading a file was refused."],
        ["shell.argv", "exec", "command", "Running a command was refused."],
        ["shell.argv", "external", "network", "Running a command with network access was refused."],
        ["browser", "read", "page", "Reading a web page was refused."],
        ["browser", "input", "interacting", "Interacting with a web page was refused."],
        ["browser", "external", "form", "Submitting a web form was refused."]
    ];
    for (const [tool, effect, query, title] of cases) {
        const rows = history.problems([{ ...refusal, tool, effect }], query);
        assert.equal(rows.length, 1, "search retains operation/effect meaning");
        assert.equal(rows[0].title, title);
        assert.equal(history.problems([{ ...refusal, tool, effect }], "private filename").length, 0);
    }
    assert.equal(history.problem({ ...refusal, tool: "unknown" }).title, "The action was refused.");
}
operationContract(History);

// A conversation stopped by an account, model or setup fault fails the same
// way when asked again, so its row opens Jarvis Settings (Console.qml reads
// settings), named as the voice row's Settings action is. A restarted row and
// any other stopped row keep asking again.
function faultContract(history) {
    const fault = (category, action) => history.problem({ time: refusal.time, kind: "fault", cause: "net=request", status: null, category, action });
    for (const [category, stoppedOffersSettings] of [["account", true], ["model", true], ["setup", true], ["connection", false],
        ["reply-cut", false], ["service", false], ["app-stopped", false], ["other", false]]) {
        for (const action of ["restarted", "stopped"]) {
            const settings = action === "stopped" && stoppedOffersSettings, shown = fault(category, action);
            assert.equal(shown.settings, settings, category + " " + action);
            assert.equal(shown.action, settings ? "Jarvis settings" : "Ask Jarvis again", category + " " + action);
        }
    }
}
faultContract(History);


const parent = os.tmpdir();
fs.mkdirSync(parent, { recursive: true });
const root = fs.mkdtempSync(path.join(parent, "jc-"));
const source = fs.readFileSync(file, "utf8");
fs.copyFileSync(path.resolve(__dirname, "../shell/plugins/vgs.jarvis/JarvisProtocol.js"), path.join(root, "JarvisProtocol.js"));
for (const name of ["Session.js", "WidgetView.js", "SetupGate.js"])
    fs.copyFileSync(path.resolve(__dirname, "../shell/plugins/vgs.jarvis", name), path.join(root, name));
let controls = 0;
try {
    function control(name, needle, replacement) {
        assert.equal(source.split(needle).length - 1, 1, name + " mutation match");
        const changed = source.replace(needle, replacement);
        assert.notEqual(changed, source);
        const copy = path.join(root, name + ".js");
        fs.writeFileSync(copy, changed);
        assert.throws(() => contract(load(copy)), assert.AssertionError, name + " must turn red");
        controls++;
    }
    const historyFile = path.resolve(__dirname, "../shell/plugins/vgs.jarvis/History.js");
    const historySource = fs.readFileSync(historyFile, "utf8"), historyNeedle = "title: operation(row) + outcome";
    assert.equal(historySource.split(historyNeedle).length - 1, 1);
    const historyCopy = path.join(root, "History.js");
    fs.writeFileSync(historyCopy, historySource.replace(historyNeedle, 'title: "The action" + outcome'));
    assert.throws(() => operationContract(load(historyCopy, historyModules)), assert.AssertionError,
        "control: dropping published operation labels must fail");
    controls++;
    const settingsNeedle = 'var settings = row.action === "stopped" && ';
    assert.equal(historySource.split(settingsNeedle).length - 1, 1);
    for (const [name, replacement] of [["no-settings", "var settings = false && "], ["restart-settings", "var settings = "]]) {
        fs.writeFileSync(historyCopy, historySource.replace(settingsNeedle, replacement));
        assert.throws(() => faultContract(load(historyCopy, historyModules)), assert.AssertionError, "control: " + name + " must fail");
        controls++;
    }
    control("replace-open", "if (last !== null && open(last) && sameSegment(last, next))", "if (false && last !== null && open(last) && sameSegment(last, next))");
    control("close-final", "return entry.stage === \"partial\";", "return true;");
    control("same-role", "a.gen === b.gen && a.role === b.role", "a.gen === b.gen");
    control("same-gen", "a.gen === b.gen && a.role === b.role", "a.role === b.role");
    control("count-ceiling", "while (rows.length > MAX_ENTRIES) dropOldest(rows);", "");
    control("byte-ceiling", "while (rows.length > 0 && Protocol.bytes(JSON.stringify(rows)) > MAX_BYTES) dropOldest(rows);", "");
    control("preview-admission", 'if (segment.source === "preview") return log;', "");
} finally { fs.rmSync(root, { recursive: true, force: true }); }
console.log("test-jarvis-conversation: ok controls=" + controls);
