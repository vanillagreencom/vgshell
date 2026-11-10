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
const entry = (gen, role, text, stage) => ({ gen, role, text, stage, at: gen * 1000, session: "session-" + gen, startedAt: gen * 1000 });
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
    let genLog = logic.update([entry(1, "assistant", "old", "partial")], entry(2, "assistant", "new", "partial"));
    assert.deepEqual(genLog, [entry(1, "assistant", "old", "partial"), entry(2, "assistant", "new", "partial")], "generation change appends");
    let many = [];
    for (let i = 0; i < 80; i++) many = logic.update(many, entry(i, "assistant", "row" + i, "final"));
    assert.equal(many.length, 64);
    assert.equal(many[0].text, "row16");
    let huge = [];
    const chunk = "語".repeat(logic.Protocol.Session.TRANSCRIPT_CHARS);
    for (let i = 0; i < 64; i++) huge = logic.update(huge, entry(i, "assistant", chunk, "final"));
    assert.ok(byteLength(huge) <= 24 * 1024);
    assert.ok(huge.length < 64, "byte ceiling drops oldest rows");
}
contract(Conversation);

// History reads its fault rows' plain words from WidgetView, whose links
// come from the shell's PageReference.
const historyModules = { "qs.Commons 1.0": { PageReference: load(path.resolve(__dirname, "../shell/Commons/PageReference.js")) } };
const History = load(path.resolve(__dirname, "../shell/plugins/vgs.jarvis/History.js"), historyModules);
const morning = new Date(2026, 10, 1, 9).getTime(), nextDay = new Date(2026, 10, 2, 9).getTime();
const transcript = [
    { ...entry(1, "user", "Voice question", "final"), at: morning, startedAt: morning, session: "first" },
    { ...entry(2, "assistant", "Answer", "final"), at: morning + 1000, startedAt: morning, session: "first" },
    { ...entry(3, "user", "Same day, other session", "final"), at: morning + 2000, session: "second" },
    { ...entry(4, "assistant", "Next day", "final"), at: nextDay, session: "first" }
];
assert.equal(History.conversations(transcript, "").length, 3, "days and session identities both delimit groups");
assert.equal(History.conversations(transcript, "VOICE")[0].rows[0].text, "Voice question");
assert.equal(History.conversations(transcript, "missing").length, 0);
assert.equal(History.conversations(transcript, "")[0].at, nextDay, "newest groups first");
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
    control("count-ceiling", "while (rows.length > MAX_ENTRIES) rows.shift();", "");
    control("byte-ceiling", "while (rows.length > 0 && Protocol.bytes(JSON.stringify(rows)) > MAX_BYTES) rows.shift();", "");
} finally { fs.rmSync(root, { recursive: true, force: true }); }
console.log("test-jarvis-conversation: ok controls=" + controls);
