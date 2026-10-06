#!/usr/bin/env node
// The tray's decisions under the same loader as QML: the bucket rule the
// widget draws and the service's choices follow, the pin and hide edits the
// service writes, the names and tooltips, and the menu rows the root level
// leaves out. Each control below plants one defect in a copy of the judge;
// the suite must turn red on every one.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const assert = require("node:assert/strict");
const { load } = require("../bin/lib/qml-library.js");
const file = path.join(__dirname, "../shell/plugins/vgs.tray/TrayLogic.js");
const plain = value => JSON.parse(JSON.stringify(value));

function suite(logic) {
    const item = (id, extra) => Object.assign({ id: id, title: "", tooltipTitle: "", passive: false }, extra);
    const ids = rows => rows.map(row => row.id);

    // The bucket rule, one row per case: the entries, pinned, hidden, and
    // the ids each bucket wants.
    for (const [name, entries, pinned, hidden, want] of [
        ["every item starts in the drawer", [item("a"), item("b")], [], [], { pinned: [], drawer: ["a", "b"], hidden: [], listed: ["a", "b"] }],
        ["a pinned item leaves the drawer", [item("a"), item("b")], ["b"], [], { pinned: ["b"], drawer: ["a"], hidden: [], listed: ["a", "b"] }],
        ["a hidden item shows nowhere", [item("a"), item("b")], [], ["a"], { pinned: [], drawer: ["b"], hidden: ["a"], listed: ["a", "b"] }],
        ["hidden wins over pinned", [item("a"), item("b")], ["a"], ["a"], { pinned: [], drawer: ["b"], hidden: ["a"], listed: ["a", "b"] }],
        ["a passive item takes no bucket", [item("a", { passive: true }), item("b")], ["a"], [], { pinned: [], drawer: ["b"], hidden: [], listed: ["b"] }],
        ["a passive hidden item is not listed", [item("a", { passive: true })], [], ["a"], { pinned: [], drawer: [], hidden: [], listed: [] }],
        ["the tray's order holds in each bucket", [item("c"), item("a"), item("b")], ["b", "c"], [], { pinned: ["c", "b"], drawer: ["a"], hidden: [], listed: ["c", "a", "b"] }],
        ["an id the tray lacks changes nothing", [item("a")], ["gone"], ["also-gone"], { pinned: [], drawer: ["a"], hidden: [], listed: ["a"] }]
    ]) {
        const got = plain(logic.buckets(entries, pinned, hidden));
        assert.deepEqual({ pinned: ids(got.pinned), drawer: ids(got.drawer), hidden: ids(got.hidden), listed: ids(got.listed) }, want, name);
    }
    // Each row carries its place in the tray, so two items of one id each
    // keep their own icon.
    assert.deepEqual(plain(logic.buckets([item("x"), item("x", { passive: true }), item("x")], [], [])).drawer, [{ id: "x", index: 0 }, { id: "x", index: 2 }]);
    // Each row carries the entry's own item, which a delegate draws, so it
    // never reads the tray's list past an app that quit.
    const own = { name: "the tray item" };
    assert.equal(logic.buckets([item("a", { item: own })], [], []).drawer[0].item, own);

    // A setting's ids: in order, each once, an empty item the first offer.
    assert.deepEqual(plain(logic.ids([{ name: "item-1", item: "b" }, { name: "item-2", item: "a" }, { name: "item-3", item: "b" }], "")), ["b", "a"]);
    assert.deepEqual(plain(logic.ids([{ name: "item-1", item: "" }], "first")), ["first"]);
    assert.deepEqual(plain(logic.ids([{ name: "item-1", item: "" }], "")), []);
    for (const value of [null, undefined, "a", {}, 3]) assert.deepEqual(plain(logic.ids(value, "first")), [], "ids of " + JSON.stringify(value));

    // The toggles. Pinning adds a free name and takes the id out of the
    // hidden list; hiding unpins; a second toggle takes the item out.
    const entry = (name, id) => ({ name: name, item: id });
    for (const [name, kind, id, pinned, hidden, want] of [
        ["pin adds the item", "pin", "a", [], [], { pinned: [entry("item-1", "a")], hidden: [] }],
        ["pin takes the lowest free name", "pin", "c", [entry("item-2", "b"), entry("item-3", "x")], [], { pinned: [entry("item-2", "b"), entry("item-3", "x"), entry("item-1", "c")], hidden: [] }],
        ["pin takes the next name", "pin", "c", [entry("item-1", "b")], [], { pinned: [entry("item-1", "b"), entry("item-2", "c")], hidden: [] }],
        ["pin shows a hidden item", "pin", "a", [], [entry("item-1", "a"), entry("item-2", "b")], { pinned: [entry("item-1", "a")], hidden: [entry("item-2", "b")] }],
        ["pin again unpins", "pin", "a", [entry("item-1", "a"), entry("item-2", "b")], [], { pinned: [entry("item-2", "b")], hidden: [] }],
        ["unpin keeps the hidden list", "pin", "a", [entry("item-1", "a")], [entry("item-1", "b")], { pinned: [], hidden: [entry("item-1", "b")] }],
        ["hide adds the item and unpins it", "hide", "a", [entry("item-1", "a")], [], { pinned: [], hidden: [entry("item-1", "a")] }],
        ["hide again shows the item", "hide", "a", [], [entry("item-1", "a")], { pinned: [], hidden: [] }],
        ["a list that is no list reads empty", "hide", "a", null, "x", { pinned: [], hidden: [entry("item-1", "a")] }]
    ]) assert.deepEqual(plain(logic.toggle(kind, id, pinned, hidden, "")), want, name);
    // An empty item names the first offer, so a toggle on that id finds it.
    assert.deepEqual(plain(logic.toggle("pin", "first", [entry("item-1", "")], [], "first")), { pinned: [], hidden: [] });
    // The input lists are left as they were.
    const pinnedIn = [entry("item-1", "a")];
    const hiddenIn = [entry("item-1", "b")];
    logic.toggle("hide", "a", pinnedIn, hiddenIn, "");
    assert.deepEqual(plain([pinnedIn, hiddenIn]), [[entry("item-1", "a")], [entry("item-1", "b")]]);

    // Names and tooltips.
    assert.equal(logic.labelOf(item("org/app", { title: " Chat ", tooltipTitle: "Tip" })), "Chat");
    assert.equal(logic.labelOf(item("org/app", { tooltipTitle: "Tip" })), "Tip");
    assert.equal(logic.labelOf(item("org/app")), "app");
    assert.equal(logic.tooltipOf(item("id", { title: "Title", tooltipTitle: "Tip" })), "Tip");
    assert.equal(logic.tooltipOf(item("id", { title: "Title" })), "Title");
    assert.equal(logic.tooltipOf(item("id")), "id");
    // An item already gone reads as no name, not an error.
    assert.equal(logic.labelOf(null), "");
    assert.equal(logic.tooltipOf(undefined), "");
    for (const [icon, want] of [
        ["image://icon/network-wireless-symbolic", true],
        ["image://icon/audio-volume-high-symbolic?path=/opt/app/icons", true],
        ["image://icon/steam?path=/x-symbolic", false],
        ["image://icon/steam", false],
        ["", false]
    ]) assert.equal(logic.isSymbolic(icon), want, icon);

    // The Settings choices: one per item that is not passive, each id once.
    assert.deepEqual(plain(logic.choices([item("a", { title: "Chat" }), item("b", { passive: true }), item("a", { title: "Twin" }), item("c")])),
        [{ label: "Chat", value: "a" }, { label: "c", value: "c" }]);
    assert.deepEqual(plain(logic.choices([item("a", { title: "two\nlines\u2028here" })])), [{ label: "two lines here", value: "a" }]);
    assert.equal(logic.choices([item("a", { title: "x".repeat(100) })])[0].label.length, logic.LABEL_MAX);
    assert.deepEqual(plain(logic.choices([item(""), item("y".repeat(logic.VALUE_MAX + 1)), item("bad\nid")])), []);
    const many = Array.from({ length: 40 }, (_, n) => item("app-" + n));
    assert.deepEqual(plain(logic.choices(many)).map(row => row.value), many.slice(0, logic.CHOICES_MAX).map(row => row.id));

    // The menu rows the root leaves out.
    const row = (text, extra) => Object.assign({ text: text, hasChildren: false, isSeparator: false }, extra);
    for (const [name, depth, index, entryRow, want] of [
        ["the root's title entry", 0, 0, row("Chat", { hasChildren: true }), true],
        ["the title entry, any case", 0, 0, row("CHAT", { hasChildren: true }), true],
        ["a title entry with no submenu stays", 0, 0, row("Chat"), false],
        ["a submenu named otherwise stays", 0, 0, row("Accounts", { hasChildren: true }), false],
        ["a later title entry stays", 0, 1, row("Chat", { hasChildren: true }), false],
        ["a leading separator", 0, 1, row("", { isSeparator: true }), true],
        ["a later separator stays", 0, 2, row("", { isSeparator: true }), false],
        ["a submenu's first rows stay", 1, 0, row("Chat", { hasChildren: true }), false],
        ["a submenu's leading separator stays", 1, 0, row("", { isSeparator: true }), false]
    ]) assert.equal(logic.rowHidden(depth, index, entryRow, "Chat"), want, name);
}

suite(load(file));
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "tray-logic-"));
try {
    const source = fs.readFileSync(file, "utf8");
    for (const [name, needle, replacement] of [
        ["pinned wins over hidden", "if (hidden.indexOf(entry.id) !== -1) out.hidden.push(row);\n        else if (pinned.indexOf(entry.id) !== -1) out.pinned.push(row);",
            "if (pinned.indexOf(entry.id) !== -1) out.pinned.push(row);\n        else if (hidden.indexOf(entry.id) !== -1) out.hidden.push(row);"],
        ["a passive item keeps its bucket", "if (entry.passive) continue;\n        var row", "var row"],
        ["pinning keeps the item hidden", "var nextOther = named ? other.slice() : without(other, id, firstOffer);", "var nextOther = other.slice();"],
        ["a toggle never takes the item out", "var nextOwn = named ? without(own, id, firstOffer) :", "var nextOwn = named ? own.slice() :"],
        ["a new item takes a taken name", 'if (taken.indexOf("item-" + n) === -1) return "item-" + n;', 'return "item-" + (list.length + 1);'],
        ["an empty item names no offer", 'return id !== "" ? id : (firstOffer || "");', "return id;"],
        ["a choice repeats an id", "|| seen.indexOf(id) !== -1) continue;", ") continue;"],
        ["the root keeps a leading separator", "return row.isSeparator === true && index <= 1;", "return false;"],
        ["a row drops its item", "var row = { id: entry.id, index: i, item: entry.item };", "var row = { id: entry.id, index: i };"]
    ]) {
        assert.equal(source.split(needle).length - 1, 1, name + " mutation must match once");
        const mutant = path.join(scratch, "TrayLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, replacement));
        assert.throws(() => suite(load(mutant)), assert.AssertionError, "control: " + name);
        console.log("tray-logic: control=" + name + " red");
    }
} finally { fs.rmSync(scratch, { recursive: true, force: true }); }
console.log("tray-logic: passed");
