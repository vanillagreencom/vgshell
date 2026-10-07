#!/usr/bin/env node
// Pure conversation log contract for the Jarvis console. No daemon runs.
"use strict";
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");
const file = path.resolve(__dirname, "../shell/plugins/vgs.jarvis/Conversation.js");
const Conversation = load(file);
const Protocol = load(path.resolve(__dirname, "../shell/plugins/vgs.jarvis/JarvisProtocol.js"));
const entry = (gen, role, text, stage) => ({ gen, role, text, stage });

let log = Conversation.start();
assert.deepEqual(log, []);
log = Conversation.update(log, entry(1, "assistant", "hel", "partial"));
assert.deepEqual(log, [entry(1, "assistant", "hel", "partial")]);
log = Conversation.update(log, entry(1, "assistant", "hello", "partial"));
assert.deepEqual(log, [entry(1, "assistant", "hello", "partial")], "open segment is replaced");
log = Conversation.update(log, entry(1, "assistant", "hello", "final"));
assert.deepEqual(log, [entry(1, "assistant", "hello", "final")], "final closes segment");
log = Conversation.update(log, entry(1, "assistant", "again", "partial"));
assert.deepEqual(log, [entry(1, "assistant", "hello", "final"), entry(1, "assistant", "again", "partial")]);
log = Conversation.update(log, entry(1, "user", "typed", "final"));
assert.deepEqual(log.at(-1), entry(1, "user", "typed", "final"), "role change appends");
log = Conversation.update(log, entry(2, "user", "new", "partial"));
assert.deepEqual(log.at(-1), entry(2, "user", "new", "partial"), "generation change appends");
let many = [];
for (let i = 0; i < 80; i++) many = Conversation.update(many, entry(i, "assistant", "row" + i, "final"));
assert.equal(many.length, 64);
assert.equal(many[0].text, "row16");
let huge = [];
for (let i = 0; i < 64; i++) huge = Conversation.update(huge, entry(i, "assistant", "x".repeat(1200), "final"));
assert.ok(Protocol.bytes(JSON.stringify(huge)) <= 48 * 1024);
assert.ok(huge.length < 64, "byte ceiling drops oldest rows");

const parent = path.resolve(__dirname, "../tmp");
fs.mkdirSync(parent, { recursive: true });
const root = fs.mkdtempSync(path.join(parent, "jc-"));
const source = fs.readFileSync(file, "utf8");
fs.copyFileSync(path.resolve(__dirname, "../shell/plugins/vgs.jarvis/JarvisProtocol.js"), path.join(root, "JarvisProtocol.js"));
fs.copyFileSync(path.resolve(__dirname, "../shell/plugins/vgs.jarvis/Session.js"), path.join(root, "Session.js"));
let controls = 0;
try {
    function control(name, needle, replacement, check) {
        assert.equal(source.split(needle).length - 1, 1, name + " mutation match");
        const changed = source.replace(needle, replacement);
        assert.notEqual(changed, source);
        const copy = path.join(root, name + ".js");
        fs.writeFileSync(copy, changed);
        assert.throws(() => check(load(copy)), assert.AssertionError, name + " must turn red");
        controls++;
    }
    control("replace-open", "if (last !== null && open(last) && sameSegment(last, next))", "if (false && last !== null && open(last) && sameSegment(last, next))", logic => {
        let rows = logic.update([], entry(1, "assistant", "a", "partial"));
        rows = logic.update(rows, entry(1, "assistant", "ab", "partial"));
        assert.deepEqual(rows, [entry(1, "assistant", "ab", "partial")]);
    });
    control("close-final", "return entry.stage === \"partial\";", "return true;", logic => {
        let rows = logic.update([], entry(1, "assistant", "a", "partial"));
        rows = logic.update(rows, entry(1, "assistant", "a", "final"));
        rows = logic.update(rows, entry(1, "assistant", "b", "partial"));
        assert.equal(rows.length, 2);
    });
    control("gen-change", "a.gen === b.gen && a.role === b.role", "a.role === b.role", logic => {
        let rows = logic.update([], entry(1, "user", "a", "partial"));
        rows = logic.update(rows, entry(2, "user", "b", "partial"));
        assert.equal(rows.length, 2);
    });
    control("count-ceiling", "while (rows.length > MAX_ENTRIES) rows.shift();", "", logic => {
        let rows = [];
        for (let i = 0; i < 80; i++) rows = logic.update(rows, entry(i, "assistant", "row" + i, "final"));
        assert.equal(rows.length, 64);
    });
    control("byte-ceiling", "while (rows.length > 0 && Protocol.bytes(JSON.stringify(rows)) > MAX_BYTES) rows.shift();", "", logic => {
        let rows = [];
        for (let i = 0; i < 64; i++) rows = logic.update(rows, entry(i, "assistant", "x".repeat(1200), "final"));
        assert.ok(Protocol.bytes(JSON.stringify(rows)) <= 48 * 1024);
    });
} finally { fs.rmSync(root, { recursive: true, force: true }); }
console.log("test-jarvis-conversation: ok controls=" + controls);
