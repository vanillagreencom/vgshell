#!/usr/bin/env node
// Controls for shell/Core/IpcPages.qml, the core pager of IPC replies.
// The suite runs the file's own `answer` and `page` under vm over a fresh
// pager per case: a reply at the bound stays whole, one past it pages and
// reads back whole, a slice never ends on a high surrogate, the ninth
// paged reply evicts the first, an index out of range is refused, and the
// last page drops its reply. Each rule has a must-fail control on a copy
// of the source.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const file = path.join(__dirname, "..", "shell", "Core", "IpcPages.qml");
const source = fs.readFileSync(file, "utf8");

// A pager built from SOURCE: its two functions and its two bounds, the
// rest of its state fresh.
function pager(text) {
    const bound = name => {
        const found = [...text.matchAll(new RegExp("^    readonly property int " + name + ": (\\d+)$", "gm"))];
        assert.equal(found.length, 1, `extractor: one actual IpcPages.${name}`);
        return Number(found[0][1]);
    };
    const root = { replyChars: bound("replyChars"), keptReplies: bound("keptReplies"), nextId: 1, slicesById: {}, order: [] };
    const ctx = vm.createContext({ root });
    for (const name of ["answer", "page"]) {
        const found = [...text.matchAll(new RegExp("^    function " + name + "\\([^\\n]*\\) \\{\\n[\\s\\S]*?^    \\}", "gm"))];
        assert.equal(found.length, 1, `extractor: one actual IpcPages.${name}`);
        vm.runInContext(found[0][0], ctx);
    }
    return { root, answer: ctx.answer, page: ctx.page };
}

// Every page of reply ID, read in order: [replies, document].
function readAll(p, id) {
    const replies = [];
    let document = "";
    for (let index = 0; ; index++) {
        const reply = p.page(id, index);
        replies.push(reply);
        const match = /^([0-9]+) ([\s\S]*)$/.exec(reply);
        if (match === null) return [replies, null];
        document += match[2];
        if (index + 1 >= Number(match[1])) return [replies, document];
    }
}

const bound = pager(source).root.replyChars;
const highSurrogate = code => code >= 0xd800 && code <= 0xdbff;
// One row per rule: [name, check(p) -> problem text or ""].
const CASES = [
    ["a reply at the bound stays whole", p => {
        const text = "x".repeat(bound);
        return p.answer(text) === text ? "" : "the reply at the bound was paged";
    }],
    ["a reply past the bound pages and reads back whole", p => {
        const text = "y".repeat(bound + 1);
        const id = /^paged=([0-9]+)$/.exec(p.answer(text));
        if (id === null) return "no paged=<id> answer";
        const [replies, document] = readAll(p, id[1]);
        if (document !== text) return "reassembly differs: " + replies.map(r => r.slice(0, 12)).join(" | ");
        return replies.length === 2 ? "" : "pages=" + replies.length;
    }],
    ["a surrogate pair across a slice end stays whole", p => {
        const sliceChars = bound - 16;
        const text = "a".repeat(sliceChars - 1) + "\u{1F600}" + "b".repeat(bound);
        const id = /^paged=([0-9]+)$/.exec(p.answer(text));
        if (id === null) return "no paged=<id> answer";
        const [replies, document] = readAll(p, id[1]);
        const split = replies.slice(0, -1).find(r => highSurrogate(r.charCodeAt(r.length - 1)));
        if (split !== undefined) return "a slice ends on a high surrogate";
        return document === text ? "" : "reassembly differs";
    }],
    ["the ninth paged reply evicts the first", p => {
        const ids = [];
        for (let n = 0; n < 9; n++) ids.push(/^paged=([0-9]+)$/.exec(p.answer("z".repeat(bound + 1)))[1]);
        const first = p.page(ids[0], 0);
        const ninth = p.page(ids[8], 0);
        return first === "absent" && ninth.startsWith("2 ") ? "" : `first=${first.slice(0, 12)} ninth=${ninth.slice(0, 12)}`;
    }],
    ["an index out of range is refused", p => {
        const id = /^paged=([0-9]+)$/.exec(p.answer("w".repeat(bound + 1)))[1];
        const got = [p.page(id, 2), p.page(id, -1)];
        const want = ["refused: page=2 pages=2", "refused: page=-1 pages=2"];
        return JSON.stringify(got) === JSON.stringify(want) ? "" : "got " + JSON.stringify(got.map(r => String(r).slice(0, 30)));
    }],
    ["the last page drops its reply", p => {
        const id = /^paged=([0-9]+)$/.exec(p.answer("v".repeat(bound + 1)))[1];
        readAll(p, id);
        const again = p.page(id, 0);
        return again === "absent" ? "" : "a reread answered " + again.slice(0, 12);
    }],
];

// The problems SOURCE's pager shows over every case, one line each.
function problems(text) {
    const out = [];
    for (const [name, check] of CASES) {
        let problem;
        try { problem = check(pager(text)); } catch (e) { problem = "raised " + e.message; }
        if (problem !== "") out.push(name + ": " + problem);
    }
    return out;
}

let failures = 0;
const ok = text => console.log("  ok    " + text);
const fail = text => { failures++; console.log("  FAIL  " + text); };

const found = problems(source);
if (found.length === 0) ok(`the pager keeps every rule (${CASES.length} cases)`);
else for (const line of found) fail(line);

// [rule, the text in IpcPages.qml, its replacement]: each copy keeps the
// rule's text and removes its behaviour.
const CONTROLS = [
    ["the bound", "text.length <= root.replyChars", "text.length < root.replyChars"],
    ["the surrogate rule", "if (before >= 0xd800 && before <= 0xdbff) end -= 1;", "if (false) end -= 1;"],
    ["the eviction", "while (root.order.length > root.keptReplies)", "while (false)"],
    ["the range refusal", "if (index < 0 || index >= pages) return", "if (false) return"],
    ["the drop after the last page", "if (index === pages - 1) {", "if (false) {"],
];
for (const [rule, needle, replacement] of CONTROLS) {
    const count = source.split(needle).length - 1;
    if (count !== 1) { fail(`control: ${rule}: the text occurs ${count} times, not once`); continue; }
    const copy = source.replace(needle, replacement);
    assert.notEqual(copy, source);
    if (problems(copy).length > 0) ok(`control: a pager without ${rule} breaks the table`);
    else fail(`control: a pager without ${rule} keeps every case`);
}

if (failures > 0) { console.log(`test-ipc-pages: failed=${failures}`); process.exit(1); }
console.log(`test-ipc-pages: ok cases=${CASES.length} controls=${CONTROLS.length}`);
