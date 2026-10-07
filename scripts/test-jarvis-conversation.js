#!/usr/bin/env node
// Pure conversation log contract for the Jarvis console. No daemon runs.
"use strict";
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");
const file = path.resolve(__dirname, "../shell/plugins/vgs.jarvis/Conversation.js");
const Conversation = load(file);
const entry = (gen, role, text, stage) => ({ gen, role, text, stage });
const byteLength = rows => Buffer.byteLength(JSON.stringify(rows));

function contract(logic) {
    let log = logic.start();
    assert.deepEqual(log, []);
    log = logic.update(log, entry(1, "assistant", "hel", "partial"));
    assert.deepEqual(log, [entry(1, "assistant", "hel", "partial")]);
    log = logic.update(log, entry(1, "assistant", "hello", "partial"));
    assert.deepEqual(log, [entry(1, "assistant", "hello", "partial")], "open segment is replaced");
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

const parent = path.resolve(__dirname, "../tmp");
fs.mkdirSync(parent, { recursive: true });
const root = fs.mkdtempSync(path.join(parent, "jc-"));
const source = fs.readFileSync(file, "utf8");
fs.copyFileSync(path.resolve(__dirname, "../shell/plugins/vgs.jarvis/JarvisProtocol.js"), path.join(root, "JarvisProtocol.js"));
fs.copyFileSync(path.resolve(__dirname, "../shell/plugins/vgs.jarvis/Session.js"), path.join(root, "Session.js"));
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
    control("replace-open", "if (last !== null && open(last) && sameSegment(last, next))", "if (false && last !== null && open(last) && sameSegment(last, next))");
    control("close-final", "return entry.stage === \"partial\";", "return true;");
    control("same-role", "a.gen === b.gen && a.role === b.role", "a.gen === b.gen");
    control("same-gen", "a.gen === b.gen && a.role === b.role", "a.role === b.role");
    control("count-ceiling", "while (rows.length > MAX_ENTRIES) rows.shift();", "");
    control("byte-ceiling", "while (rows.length > 0 && Protocol.bytes(JSON.stringify(rows)) > MAX_BYTES) rows.shift();", "");
} finally { fs.rmSync(root, { recursive: true, force: true }); }
console.log("test-jarvis-conversation: ok controls=" + controls);
