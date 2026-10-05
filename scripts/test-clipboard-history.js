#!/usr/bin/env node
// Table-driven checks for vgs.clipboard's pure decisions,
// ClipboardHistory.js: what a helper line records, how a copy joins the
// history, the limit, what a pin, a removal and a clear leave, the stored
// form, the image files no entry names, the overlay's rows for a filter
// and the paste chord. Expected values are written here by hand.
// Controls edit one rule at a time in a copy of the logic and require this
// suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.clipboard", "ClipboardHistory.js");
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message);

// An id is 64 hex digits; these repeat four digits so each is distinct.
const id = n => n.toString(16).padStart(4, "0").repeat(16);
const text = (n, value, pinned) => ({ id: id(n), type: "text", pinned: pinned === true, time: 1000 + n, text: value });
const image = (n, mime, pinned) => ({ id: id(n), type: "image", pinned: pinned === true, time: 1000 + n, mime: mime });
const ids = entries => entries.map(entry => entry.id);

function verify(logic) {
    assert.equal(logic.LIMIT, 500, "the history keeps 500 entries");
    assert.equal(logic.ROWS, 50, "the overlay draws 50 rows");
    assert.equal(logic.SHOWN, 8192, "the overlay shows 8192 characters of an entry");

    // ---- a helper line
    const lines = [
        ["text", JSON.stringify({ type: "text", id: id(1), time: 7.9, text: "a\nb" }), { id: id(1), type: "text", pinned: false, time: 7, text: "a\nb" }],
        ["image", JSON.stringify({ type: "image", id: id(2), time: 9, mime: "image/png" }), { id: id(2), type: "image", pinned: false, time: 9, mime: "image/png" }],
        ["not JSON", "{", null],
        ["a list", "[]", null],
        ["white space alone", JSON.stringify({ type: "text", id: id(1), time: 7, text: " \n\t" }), null],
        ["an id that is no digest", JSON.stringify({ type: "text", id: "abc", time: 7, text: "a" }), null],
        ["an upper-case id", JSON.stringify({ type: "text", id: id(171).toUpperCase(), time: 7, text: "a" }), null],
        ["no time", JSON.stringify({ type: "text", id: id(1), text: "a" }), null],
        ["an unknown type", JSON.stringify({ type: "file", id: id(1), time: 7, text: "a" }), null],
        ["an image without its type", JSON.stringify({ type: "image", id: id(2), time: 9 }), null],
        ["a type that is no image", JSON.stringify({ type: "image", id: id(2), time: 9, mime: "text/plain" }), null]
    ];
    for (const [label, line, want] of lines) same(logic.captured(line), want, "captured: " + label);

    // ---- a copy joins the history
    const three = [text(3, "three"), text(2, "two", true), text(1, "one")];
    same(ids(logic.record(three, text(4, "four"))), [id(4), id(3), id(2), id(1)], "record: a new copy is first");
    const again = logic.record(three, Object.assign(text(1, "one"), { time: 5000 }));
    same(ids(again), [id(1), id(3), id(2)], "record: an exact repeat moves to the front and adds no entry");
    assert.equal(again[0].time, 5000, "record: a repeat takes the new copy's time");
    const pinnedAgain = logic.record(three, text(2, "two"));
    same(ids(pinnedAgain), [id(2), id(3), id(1)], "record: a repeat of a pinned entry moves it to the front");
    assert.equal(pinnedAgain[0].pinned, true, "record: a repeat keeps its pin");
    same(ids(three), [id(3), id(2), id(1)], "record: the history handed in is left as it was");

    // ---- the limit
    const many = [];
    for (let n = 0; n < 500; n++) many.push(text(1000 + n, "entry " + n, n === 499));
    const full = logic.record(many, text(1, "new"));
    assert.equal(full.length, 500, "limit: the history holds 500 entries");
    assert.equal(full[0].id, id(1), "limit: the new copy is kept");
    assert.equal(full[499].id, many[499].id, "limit: the oldest entry stays while it is pinned");
    assert.equal(logic.find(full, many[498].id), null, "limit: the oldest entry that is not pinned goes");
    const pins = many.map(entry => Object.assign({}, entry, { pinned: true }));
    same(ids(logic.record(pins, text(1, "new"))), ids(pins), "limit: a history of 500 pins records no new copy");

    // ---- pin, remove, clear
    same(logic.repinned(three, id(3)).map(entry => entry.pinned), [true, true, false], "repinned: pins an entry");
    same(logic.repinned(three, id(2)).map(entry => entry.pinned), [false, false, false], "repinned: lets a pin go");
    same(three.map(entry => entry.pinned), [false, true, false], "repinned: the history handed in is left as it was");
    same(ids(logic.removed(three, id(3))), [id(2), id(1)], "removed: one entry goes");
    same(ids(logic.removed(three, id(9))), [id(3), id(2), id(1)], "removed: an unknown id removes nothing");
    same(ids(logic.cleared(three)), [id(2)], "cleared: the pinned entries stay");
    assert.equal(logic.find(three, id(2)).text, "two", "find: by id");
    assert.equal(logic.find(three, id(9)), null, "find: an unknown id");

    // ---- the stored form
    const mixed = [image(5, "image/png"), text(4, "four", true)];
    same(logic.parse(logic.serialize(mixed)), mixed, "parse: reads what serialize wrote");
    const stored = [
        ["not JSON", "{", []],
        ["empty", "", []],
        ["no entries list", JSON.stringify({ version: 1 }), []],
        ["a list alone", JSON.stringify([text(1, "a")]), []],
        ["a malformed entry is left out", JSON.stringify({ entries: [text(1, "a"), { id: "x" }, null, text(2, "b")] }), [id(1), id(2)]],
        ["the second entry of one id is left out", JSON.stringify({ entries: [text(1, "a"), text(1, "b")] }), [id(1)]]
    ];
    for (const [label, raw, want] of stored) same(ids(logic.parse(raw)), want, "parse: " + label);
    assert.equal(logic.parse(JSON.stringify({ entries: many.concat([text(1, "one more")]) })).length, 500, "parse: a longer stored history is held to the limit");

    // ---- image files
    const pictures = [image(5, "image/png"), text(4, "four"), image(3, "image/jpeg")];
    same(logic.files(pictures), [id(5), id(3)], "files: the image entries' ids");
    same(logic.unused([id(5), id(3), id(3), id(7)], [pictures[0]]), [id(3), id(7)], "unused: the names no entry holds, each once");

    // ---- rows
    const history = [text(6, "Alpha  beta\n\tGAMMA"), image(5, "image/png"), text(4, "delta", true), image(3, "image/svg+xml"), text(2, "beta again")];
    const all = logic.rows(history, "");
    same(ids(all), [id(4), id(6), id(5), id(3), id(2)], "rows: pinned first, then newest first");
    same(all[1], { id: id(6), type: "text", pinned: false, time: 1006, label: "Alpha beta GAMMA", text: "Alpha  beta\n\tGAMMA", mime: "" }, "rows: a text row");
    same(all[2], { id: id(5), type: "image", pinned: false, time: 1005, label: "PNG image", text: "", mime: "image/png" }, "rows: an image row");
    assert.equal(all[3].label, "SVG image", "rows: an image label leaves the type's suffix out");
    const filters = [
        ["a substring", "bet", [id(6), id(2)]],
        ["without case", "GAMMA", [id(6)]],
        ["without case, lower", "alpha", [id(6)]],
        ["white space around the query", "  delta ", [id(4)]],
        ["images by the word", "image", [id(5), id(3)]],
        ["an image by its type", "PNG", [id(5)]],
        ["no match", "omega", []]
    ];
    for (const [label, query, want] of filters) same(ids(logic.rows(history, query)), want, "rows: " + label);
    const crowd = [];
    for (let n = 0; n < 60; n++) crowd.push(text(100 + n, "row " + n));
    assert.equal(logic.rows(crowd, "").length, 50, "rows: at most 50");
    assert.equal(logic.rows(crowd, "row 5").length, 11, "rows: a filter counts its own matches");
    const long = [text(1, "a".repeat(8192) + "TAIL")];
    assert.equal(logic.rows(long, "")[0].text.length, 8192, "rows: 8192 characters of an entry are shown");
    assert.equal(logic.rows(long, "tail").length, 0, "rows: text past the shown characters is not searched");

    // ---- the paste chord
    same(logic.pasteChord(false), ["-M", "ctrl", "-k", "v", "-m", "ctrl"], "pasteChord: an application takes Ctrl+V");
    same(logic.pasteChord(true), ["-M", "ctrl", "-M", "shift", "-k", "v", "-m", "shift", "-m", "ctrl"], "pasteChord: a terminal takes Ctrl+Shift+V");
}

verify(load(file));

const CONTROLS = [
    ["a repeat adds no second entry", "        if (entries[i].id === entry.id) first.pinned = entries[i].pinned;\n        else rest.push(entries[i]);", "        rest.push(entries[i]);"],
    ["a repeat keeps its pin", "if (entries[i].id === entry.id) first.pinned = entries[i].pinned;", "if (entries[i].id === entry.id) first.pinned = false;"],
    ["the history is held to the limit", "    return trimmed([first].concat(rest));", "    return [first].concat(rest);"],
    ["a pin outlives the limit", "            if (!out[i].pinned) { drop = i; break; }", "            if (false) { drop = i; break; }"],
    ["a clear keeps the pins", "return entries.filter(function (entry) { return entry.pinned; });", "return [];"],
    ["a pin sorts first", "if (entry.pinned !== (pass === 0)) continue;", "if (pass !== 0) continue;"],
    ["the filter matches a substring", "if (needle !== \"\" && searched.toLowerCase().indexOf(needle) === -1) continue;", "if (needle !== \"\" && searched.toLowerCase() !== needle) continue;"],
    ["the filter ignores case", "if (needle !== \"\" && searched.toLowerCase().indexOf(needle) === -1) continue;", "if (needle !== \"\" && searched.indexOf(needle) === -1) continue;"],
    ["the rows end at 50", "var ROWS = 50;", "var ROWS = 60;"],
    ["the shown text ends at 8192 characters", "var shown = image ? \"\" : entry.text.slice(0, SHOWN);", "var shown = image ? \"\" : entry.text;"],
    ["an image entry names an image type", "if (typeof value.mime !== \"string\" || !MIME.test(value.mime)) return null;", "if (typeof value.mime !== \"string\") return null;"],
    ["an image file is named by its entry's id", "if (entries[i].type === \"image\") out.push(entries[i].id);", "if (entries[i].type === \"image\") out.push(entries[i].mime);"],
    ["a stored id counts once", "if (entry === null || seen[entry.id] === true) continue;", "if (entry === null) continue;"],
    ["a file an entry names is in use", "return kept[name] !== true && names.indexOf(name) === at;", "return names.indexOf(name) === at;"],
    ["a terminal takes the shift chord", "return terminal ? [\"-M\", \"ctrl\", \"-M\", \"shift\", \"-k\", \"v\", \"-m\", \"shift\", \"-m\", \"ctrl\"] : ", "return "]
];

const source = fs.readFileSync(file, "utf8");
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "clipboard-history-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const mutant = path.join(temp, "ClipboardHistory.js");
        fs.writeFileSync(mutant, source.replace(needle, () => replacement));
        let failed = false;
        try {
            verify(load(mutant));
        } catch (e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the suite passed on the mutated logic`);
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
console.log(`test-clipboard-history: ok controls=${CONTROLS.length}`);
