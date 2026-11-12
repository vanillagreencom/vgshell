#!/usr/bin/env node
// The Agent Warden plugin's notices, shell/plugins/vgs.agent-warden/Notices.js,
// under node: when the service owns the notices, which episodes each status
// holds, which are new against the episodes remembered, the notices each
// `notify` setting sends, their words, level and actions, and the
// shell.notify.send options the core admits. The statuses are vsys's
// fixtures, copied into scripts/smoke/fixtures/agent-warden/, read through
// WardenLogic as the service reads them, and every expected value is
// written out by hand. No notice names a scope unit or a process id of its
// status.
//
// The controls at the end edit a copy of the notices, one rule at a time,
// and require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { load } = require("../bin/lib/qml-library.js");
const modules = { "qs.Commons 1.0": { Duration: load(path.join(__dirname, "..", "shell", "Commons", "Duration.js")) } };

const dir = path.join(__dirname, "..", "shell", "plugins", "vgs.agent-warden");
const fixtures = path.join(__dirname, "smoke", "fixtures", "agent-warden");
const PluginLogic = load(path.join(__dirname, "..", "shell", "Core", "PluginLogic.js"));
// The notices run in their own context, whose arrays and objects are not
// this one's; values are compared as JSON.
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message === undefined ? JSON.stringify(want) : message);
const fixture = name => JSON.parse(fs.readFileSync(path.join(fixtures, "status-" + name + ".json"), "utf8"));
const edited = (name, edit) => { const doc = fixture(name); edit(doc); return doc; };

const SCOPE = "agent-warden-100-200.scope";
const NEAR = "near-limit:" + SCOPE;
const STOPPED = "not-checking:agent-warden";

// The detail the service derives from INPUT, a status document or one of
// the service's other reads by kind, at SECONDS after the document's time
// (after T for a read with no document).
const T = 1700000000;
function detailOf(n, input, seconds) {
    const logic = n.ViewLogic.WardenLogic;
    if (typeof input === "string") return logic.derive({ kind: input }, (T + seconds) * 1000);
    const file = logic.readStatus(JSON.stringify(input));
    assert.equal(file.kind, "read", "a status reads: " + JSON.stringify(file));
    return logic.derive(file, (input.time + seconds) * 1000);
}

// The owner of the notices: [label, status, owns].
const OWNS = [
    ["a status that reads", { kind: "read", doc: {} }, true],
    ["no status yet", { kind: "pending" }, false],
    ["no status", { kind: "absent" }, false],
    ["an unreadable status", { kind: "unreadable", cause: "json" }, false],
    ["a major not read", { kind: "schema", schema: "2.0" }, false],
    ["a 1.x from before items", { kind: "old-vsys", schema: "1.2" }, false]
];

// Sequences of statuses through one memory: [label, steps], each step
// [status, seconds after its time, keys opened, memory after]. Each
// sequence starts from no memory.
const SEQUENCES = [
    ["one notice per item, again only after it clears", [
        [fixture("near-limit"), 0, [NEAR], [NEAR]],
        [fixture("near-limit"), 30, [], [NEAR]],
        [fixture("holding-off"), 0, ["memory-full"], ["memory-full"]],
        [fixture("holding-off"), 30, [], ["memory-full"]],
        [fixture("near-limit"), 0, [NEAR], [NEAR]]
    ]],
    ["information opens its episode as a warning does", [
        [fixture("leftover-idle"), 0, ["leftover"], ["leftover"]],
        [fixture("reaped"), 0, ["reaped"], ["reaped"]]
    ]],
    ["a key a status holds twice opens once", [
        [edited("near-limit", d => { d.items.push(d.items[0]); }), 0, [NEAR], [NEAR]]
    ]],
    ["what a status cannot tell stays as it is", [
        [fixture("near-limit"), 0, [NEAR], [NEAR]],
        ["unreadable", 0, [], [NEAR]],
        ["schema", 0, [], [NEAR]],
        ["old-vsys", 0, [], [NEAR]],
        ["absent", 0, [], [NEAR]],
        [fixture("calm"), 0, [], []]
    ]],
    ["a stale status opens its own episode and keeps the rest", [
        [fixture("near-limit"), 0, [NEAR], [NEAR]],
        [fixture("near-limit"), 91, [STOPPED], [NEAR, STOPPED]],
        [fixture("near-limit"), 400, [], [NEAR, STOPPED]],
        ["unreadable", 0, [], [NEAR, STOPPED]],
        [fixture("calm"), 0, [], []],
        [fixture("calm"), 91, [STOPPED], [STOPPED]],
        [fixture("calm"), 10, [], []]
    ]]
];

// The words, level and actions of one item of each level and of the
// warden's stop: [label, item or null for the stop, notice].
const NOW = T * 1000;
const ITEMS = {
    danger: { kind: "memory-full", key: "memory-full", level: "danger", title: "Agents are close to their memory limit.", detail: "73 of 80 GB in use.", actions: [{ id: "show", label: "Show in vsys", args: [] }] },
    warn: { kind: "near-limit", key: NEAR, level: "warn", title: "claude in vsy-52 is near its memory and task limits.", detail: null,
        actions: [{ id: "show", label: "Show in vsys", args: ["--lane", SCOPE] }, { id: "stop", label: "Stop", args: ["--lane", SCOPE, "--stop"] }, { id: "odd", label: "Odd", args: ["a\nb"] }] },
    info: { kind: "reaped", key: "reaped", level: "info", title: "The warden stopped leftover work from 1 finished agent.", detail: "42 processes had become busy.", actions: [] }
};
const NOTICES = [
    ["a problem", ITEMS.danger, { keys: ["memory-full"], title: "Agents are close to their memory limit.", body: "73 of 80 GB in use.", tone: "danger", icon: "shield-x", urgency: "critical", transient: false, actions: [{ label: "Show in vsys", args: [] }] }],
    // An action the vsys TUI cannot take is not offered.
    ["a warning", ITEMS.warn, { keys: [NEAR], title: "claude in vsy-52 is near its memory and task limits.", body: "", tone: "warning", icon: "shield-alert", urgency: "normal", transient: false,
        actions: [{ label: "Show in vsys", args: ["--lane", SCOPE] }, { label: "Stop", args: ["--lane", SCOPE, "--stop"] }] }],
    // A calm notice, and the stop the bar draws in grey, name no tone, so
    // the card draws the shield in its own ink.
    ["information", ITEMS.info, { keys: ["reaped"], title: "The warden stopped leftover work from 1 finished agent.", body: "42 processes had become busy.", tone: "", icon: "shield", urgency: "low", transient: true, actions: [] }],
    ["the warden stopped", null, { keys: [STOPPED], title: "Agent Warden has stopped checking", body: "The last check was 3m ago, so agent limits are not applied.",
        tone: "", icon: "shield-off", urgency: "normal", transient: false, actions: [] }]
];
const episodeOf = item => item === null ? { key: STOPPED, checkedAt: NOW - 180000 } : { key: item.key, item: item };
const EACH = NOTICES.map(([, item]) => episodeOf(item));
// [mode, the keys of the notices it sends].
const MODES = [
    ["off", []],
    ["problems", [["memory-full"], [NEAR], [STOPPED]]],
    ["everything", [["memory-full"], [NEAR], ["reaped"], [STOPPED]]]
];

function verify(n) {
    for (const [label, status, want] of OWNS) assert.equal(n.owns(status), want, label);

    for (const [label, steps] of SEQUENCES) {
        let memory = [];
        steps.forEach(([input, seconds, opened, after], i) => {
            const result = n.step(memory, n.conditionsOf(detailOf(n, input, seconds)));
            same(result.opened.map(e => e.key), opened, `${label}, step ${i + 1}: opened`);
            same(result.memory, after, `${label}, step ${i + 1}: remembered`);
            assert.equal(result.dropped, 0, `${label}, step ${i + 1}: dropped`);
            memory = JSON.parse(JSON.stringify(result.memory));
        });
    }
    same(n.conditionsOf(detailOf(n, fixture("near-limit"), 0)).open.map(e => e.item.title), ["claude in vsy-52 is near its memory and task limits."], "an item's episode carries the item");
    same(n.conditionsOf(detailOf(n, fixture("calm"), 91)).open, [{ key: STOPPED, checkedAt: NOW }], "a stale status's episode carries its time");
    assert.throws(() => n.conditionsOf({ state: "sleeping", items: [] }), /state="sleeping" unknown/);

    // The ceiling: a full memory takes no new key and sends nothing, and a
    // key that clears makes room.
    assert.equal(n.MAX_EPISODES, 64);
    const full = Array.from({ length: n.MAX_EPISODES }, (_, i) => "reaped:held-" + i);
    const near = { open: [episodeOf(ITEMS.warn)], keep: true };
    same(n.step(full, near), { memory: full, opened: [], dropped: 1 }, "a full memory drops each new episode");
    same(n.step(full.slice(1), near).opened.map(e => e.key), [NEAR], "one free place takes the new episode");
    same(n.step(full, Object.assign({}, near, { keep: false })).opened.map(e => e.key), [NEAR], "keys that cleared make room");

    same(n.forget(["a:1", "b:2", "c:3"], ["b:2", "d:4"]), ["a:1", "c:3"]);

    for (const [label, item, want] of NOTICES) {
        const out = n.notices([episodeOf(item)], "everything", true, NOW);
        same(out, [want], label);
        const options = n.shellOptions(out[0]);
        same(options, Object.assign({ title: want.title, message: want.body, icon: want.icon, urgency: want.urgency, transient: want.transient, wait: false,
            actions: want.actions.map((a, i) => ({ id: String(i), label: a.label })) }, want.tone === "" ? {} : { tone: want.tone }), label + ": options");
        assert.equal(PluginLogic.notifyOptions(JSON.parse(JSON.stringify(options))).ok, true, label + ": the core admits the options");
    }
    for (const [mode, want] of MODES)
        same(n.notices(EACH, mode, true, NOW).map(x => x.keys), want, "notify=" + mode);
    same(n.notices(EACH, "everything", false, NOW).map(x => x.actions), [[], [], [], []], "no action without vsys");
    assert.throws(() => n.notices(EACH, "loud", true, NOW), /notify="loud" unknown/);
    assert.equal(n.HEARTBEAT_MS, 60000, "the heartbeat is touched well inside the warden's 120 s");

    // No notice names a scope unit or a process id of its status.
    for (const name of ["near-limit", "holding-off", "leftover-busy", "leftover-idle", "partial", "reaped"]) {
        const doc = fixture(name);
        const opened = n.step([], n.conditionsOf(detailOf(n, doc, 0))).opened;
        assert.ok(opened.length > 0, name + " opens an episode");
        const drawn = n.notices(opened, "everything", true, doc.time * 1000).map(x => x.title + "\n" + x.body + "\n" + x.actions.map(a => a.label).join("\n")).join("\n");
        for (const secret of secrets(doc)) assert.ok(!drawn.includes(secret), `${name}: a notice names ${secret}`);
    }
}

// Each scope unit and process id fixture DOC carries.
function secrets(doc) {
    const found = [];
    const visit = value => {
        if (Array.isArray(value)) value.forEach(visit);
        else if (value !== null && typeof value === "object")
            for (const [key, inner] of Object.entries(value)) {
                if (key === "scope" && typeof inner === "string") found.push(inner);
                else if (key === "pid" && typeof inner === "number") found.push(String(inner));
                else visit(inner);
            }
    };
    visit(doc);
    return found;
}

verify(load(path.join(dir, "Notices.js"), modules));

// Each control removes one rule from a copy of the notices and keeps the
// text around it. The suite must fail on every copy.
const CONTROLS = [
    ["no episode memory", "        if (next.indexOf(e.key) !== -1) return;\n", ""],
    ["a cleared episode is kept", "var next = memory.filter(function (k) { return conditions.keep || openKeys.indexOf(k) !== -1; });", "var next = memory.slice();"],
    ["what a status cannot tell clears", "if (detail.reason !== \"stale\") return { open: [], keep: true };", "if (detail.reason !== \"stale\") return { open: [], keep: false };"],
    ["a stale status clears the rest", "return { open: [{ key: NOT_CHECKING, checkedAt: detail.checkedAt }], keep: true };", "return { open: [{ key: NOT_CHECKING, checkedAt: detail.checkedAt }], keep: false };"],
    ["no ceiling", "if (next.length >= MAX_EPISODES) {", "if (false) {"],
    ["off ranks above problems", "var MODES = [\"off\", \"problems\", \"everything\"];", "var MODES = [\"problems\", \"off\", \"everything\"];"],
    ["information goes out under problems", "\"info\": \"everything\"", "\"info\": \"problems\""],
    ["a notice takes another level's look", "var look = ViewLogic.LEVEL_LOOKS[e.item.level];", "var look = ViewLogic.LEVEL_LOOKS.warn;"],
    ["a stopped warden waits for everything", "if (sends(\"problems\", mode)) out.push(stopped(e, now));", "if (sends(\"everything\", mode)) out.push(stopped(e, now));"],
    ["a failed send is remembered", "return memory.filter(function (k) { return keys.indexOf(k) === -1; });", "return memory;"],
    ["actions without vsys", "actions: vsys ? ViewLogic.actionsOf(e.item) : []", "actions: ViewLogic.actionsOf(e.item)"],
    ["an action's id is its label", "return { id: String(i), label: a.label };", "return { id: a.label, label: a.label };"],
    ["owns a status it cannot read", "return status.kind === \"read\";", "return status.kind !== \"pending\";"]
];

const sources = {};
for (const name of ["Notices.js", "ViewLogic.js", "WardenLogic.js"]) sources[name] = fs.readFileSync(path.join(dir, name), "utf8");
const scratchRoot = os.tmpdir();
fs.mkdirSync(scratchRoot, { recursive: true });
const temp = fs.mkdtempSync(path.join(scratchRoot, "agent-warden-notices-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(sources["Notices.js"].split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        for (const [name, text] of Object.entries(sources))
            fs.writeFileSync(path.join(temp, name), name === "Notices.js" ? text.replace(needle, () => replacement) : text);
        let failed = false;
        try {
            verify(load(path.join(temp, "Notices.js"), modules));
        } catch (e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the suite passed on notices without that rule`);
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
console.log(`test-agent-warden-notices: ok owns=${OWNS.length} sequences=${SEQUENCES.length} notices=${NOTICES.length} modes=${MODES.length} controls=${CONTROLS.length}`);
