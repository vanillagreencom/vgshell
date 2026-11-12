#!/usr/bin/env node
// The Agent Warden plugin's decisions, shell/plugins/vgs.agent-warden/WardenLogic.js,
// under node: reading a warden status file by its schema, the consumer
// state each status means at a moment, with the summary's causes added,
// the warden's Settings row, the values the service publishes and the GB
// figures the plugin's copy shows. The status documents are vsys's own
// fixtures, copied into scripts/smoke/fixtures/agent-warden/, and every
// expected value is written out by hand. It also holds ViewLogic.js's
// judge of an action's arguments to the core's PluginLogic.tuiArgsValid,
// which it copies.
//
// The controls at the end edit a copy of the logic, one rule at a time,
// and require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.agent-warden", "WardenLogic.js");
const manifestFile = path.join(__dirname, "..", "shell", "plugins", "vgs.agent-warden", "manifest.json");
const fixtures = path.join(__dirname, "smoke", "fixtures", "agent-warden");
const producer = load(path.join(__dirname, "..", "shell", "Core", "PluginLogic.js"));
const steps = load(path.join(__dirname, "..", "shell", "plugins", "vgs.settings", "Steps.js"));
// The logic runs in its own context, whose arrays and objects are not this
// one's; values are compared as JSON.
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message === undefined ? JSON.stringify(want) : message);
const fixture = name => JSON.parse(fs.readFileSync(path.join(fixtures, "status-" + name + ".json"), "utf8"));
// A fixture with EDIT applied to a copy of it.
const edited = (name, edit) => { const doc = fixture(name); edit(doc); return doc; };
const manifest = source => {
    const loaded = producer.validateManifest(JSON.parse(fs.readFileSync(source, "utf8")), path.dirname(source));
    assert.equal(loaded.ok, true, "the manifest validates: " + (loaded.error || ""));
    return loaded.manifest;
};

const SLICE = { used: 40802189312, high: 68719476736, max: 85899345920 };
const LANE = { scope: "agent-warden-7-8.scope", label: { tool: "claude", worktree: "vsy-52" }, tasks: 120, tasksMax: 8192, memory: 25769803776, memoryHigh: 68719476736, near: [] };
const SCOPE = "agent-warden-100-200.scope";
// near-limit's one item, as the plugin keeps it.
const NEAR = {
    kind: "near-limit", key: "near-limit:" + SCOPE, level: "warn", title: "claude in vsy-52 is near its memory and task limits.",
    detail: "Memory: 50 of 64 GB; past it the system slows this agent. Tasks: 6200 of 8192 tasks; past it the agent cannot start processes.",
    actions: [{ id: "show", label: "Show in vsys", args: ["--lane", SCOPE] }, { id: "stop", label: "Stop", args: ["--lane", SCOPE, "--stop"] }]
};
const FULL = { kind: "memory-full", key: "memory-full", level: "danger", title: "Agents are close to their memory limit.", detail: "73 of 80 GB in use. The warden holds back 1 agent until memory frees.", actions: [{ id: "show", label: "Show in vsys", args: [] }] };
const LEFTOVER = { kind: "leftover", key: "leftover", level: "info", title: "Leftover work from 5 finished agents is still running.", detail: "5 processes. The warden stops it if it gets busy.", actions: [{ id: "show", label: "Show in vsys", args: [] }] };

// Documents readStatus refuses: [label, document or text, answer].
const REFUSED = [
    ["text that is not JSON", "{", { kind: "unreadable", cause: "json" }],
    ["a list", "[]", { kind: "unreadable", cause: "field=root" }],
    ["no schema", edited("calm", d => { delete d.schema; }), { kind: "unreadable", cause: "field=schema" }],
    ["a schema without a minor", edited("calm", d => { d.schema = "1"; }), { kind: "unreadable", cause: "field=schema" }],
    ["a newer major", edited("calm", d => { d.schema = "2.0"; }), { kind: "schema", schema: "2.0" }],
    ["an older major", edited("calm", d => { d.schema = "0.9"; }), { kind: "schema", schema: "0.9" }],
    ["a 1.x from before items", edited("calm", d => { d.schema = "1.2"; delete d.items; }), { kind: "old-vsys", schema: "1.2" }],
    ["a time that is a string", edited("calm", d => { d.time = "1700000000"; }), { kind: "unreadable", cause: "field=time" }],
    ["a slice that is a list", edited("calm", d => { d.slice = []; }), { kind: "unreadable", cause: "field=slice" }],
    ["a slice limit that is a word", edited("calm", d => { d.slice.high = "big"; }), { kind: "unreadable", cause: "field=slice.high" }],
    ["lanes that are a word", edited("calm", d => { d.lanes = "none"; }), { kind: "unreadable", cause: "field=lanes" }],
    ["a lane tool that is a number", edited("calm", d => { d.lanes[0].label.tool = 5; }), { kind: "unreadable", cause: "field=lanes[0].label.tool" }],
    ["a lane without a scope", edited("calm", d => { delete d.lanes[0].scope; }), { kind: "unreadable", cause: "field=lanes[0].scope" }],
    ["an orphan scope that is a number", edited("leftover-idle", d => { d.orphans[0].scope = 7; }), { kind: "unreadable", cause: "field=orphans[0].scope" }],
    ["items that are null", edited("calm", d => { d.items = null; }), { kind: "unreadable", cause: "field=items" }],
    ["an item without a key", edited("near-limit", d => { delete d.items[0].key; }), { kind: "unreadable", cause: "field=items[0].key" }],
    ["an item at a level the contract does not fix", edited("near-limit", d => { d.items[0].level = "fatal"; }), { kind: "unreadable", cause: "field=items[0].level" }],
    ["an item with an empty title", edited("near-limit", d => { d.items[0].title = ""; }), { kind: "unreadable", cause: "field=items[0].title" }],
    ["an item detail that is a number", edited("near-limit", d => { d.items[0].detail = 3; }), { kind: "unreadable", cause: "field=items[0].detail" }],
    ["item actions that are no list", edited("near-limit", d => { d.items[0].actions = {}; }), { kind: "unreadable", cause: "field=items[0].actions" }],
    ["an action without a label", edited("near-limit", d => { delete d.items[0].actions[1].label; }), { kind: "unreadable", cause: "field=items[0].actions[1].label" }]
];

const T = 1700000000;
const MS = T * 1000;
// Documents at their moments and the detail derive answers: [label, doc,
// now, detail]. Every fixture is read through readStatus first.
const DERIVED = [
    ["calm at its own time", fixture("calm"), MS, { state: "calm", reason: null, checkedAt: MS, agents: 1, items: [], memory: SLICE }],
    ["calm 90 s later is still fresh", fixture("calm"), MS + 90000, { state: "calm", reason: null, checkedAt: MS, agents: 1, items: [], memory: SLICE }],
    ["calm past 90 s is stale, keeping its time and count", fixture("calm"), MS + 90001, { state: "not-checking", reason: "stale", checkedAt: MS, agents: 1, items: [], memory: null }],
    ["a time past 90 s ahead is stale", fixture("calm"), MS - 90001, { state: "not-checking", reason: "stale", checkedAt: MS, agents: 1, items: [], memory: null }],
    ["a lane near its limits is a warning", fixture("near-limit"), MS + 30000, { state: "warn", reason: null, checkedAt: MS + 30000, agents: 1, items: [NEAR], memory: SLICE }],
    ["memory nearly full is a problem", fixture("holding-off"), MS + 60000, { state: "danger", reason: null, checkedAt: MS + 60000, agents: 1, items: [FULL], memory: { used: 78383153152, high: 68719476736, max: 85899345920 } }],
    ["idle leftover work is information, and none of its lanes is an agent", fixture("leftover-idle"), MS + 210000, { state: "info", reason: null, checkedAt: MS + 210000, agents: 1, items: [LEFTOVER], memory: SLICE }],
    ["a field an item adds is not kept", edited("leftover-idle", d => { d.items[0].since = 5; d.items[0].actions[0].confirm = true; }), MS + 210000, { state: "info", reason: null, checkedAt: MS + 210000, agents: 1, items: [LEFTOVER], memory: SLICE }],
    ["leftover work is not an agent", edited("calm", d => { d.lanes.push(Object.assign({}, LANE)); d.orphans = [{ scope: LANE.scope, processes: 3, cores: 0, since: T, harmful: false }]; }), MS, { state: "calm", reason: null, checkedAt: MS, agents: 1, items: [], memory: SLICE }],
    ["a lane without an agent is not one", edited("calm", d => { d.lanes.push(Object.assign({}, LANE, { label: { tool: null, worktree: null } })); }), MS, { state: "calm", reason: null, checkedAt: MS, agents: 1, items: [], memory: SLICE }],
    ["unlisted lanes leave the count unknown", edited("calm", d => { d.lanes = null; }), MS, { state: "calm", reason: null, checkedAt: MS, agents: null, items: [], memory: SLICE }],
    ["an absent slice has no meter", edited("calm", d => { d.slice = null; }), MS, { state: "calm", reason: null, checkedAt: MS, agents: 1, items: [], memory: null }],
    ["an unlimited slice has no bounds", edited("calm", d => { d.slice.high = "max"; d.slice.max = "max"; }), MS, { state: "calm", reason: null, checkedAt: MS, agents: 1, items: [], memory: { used: 40802189312, high: null, max: null } }],
    ["a newer minor's fields are skipped", edited("calm", d => { d.schema = "1.9"; d.extra = { any: 1 }; }), MS, { state: "calm", reason: null, checkedAt: MS, agents: 1, items: [], memory: SLICE }]
];

// The summary's causes over a derived state: [label, file or doc, now,
// causes, the state withCauses answers]. Only a cause's level counts.
const CAUSES = [
    ["a calm status with a clear summary", fixture("calm"), MS, [], "calm"],
    ["a calm status with a summary warning", fixture("calm"), MS, [{ level: "warn" }], "warn"],
    ["information with a summary problem", fixture("leftover-idle"), MS + 210000, [{ level: "danger" }], "danger"],
    ["a problem with a summary warning", fixture("holding-off"), MS + 60000, [{ level: "warn" }], "danger"],
    ["a calm status before a summary was read", fixture("calm"), MS, null, "calm"],
    ["a stale status keeps its state", fixture("calm"), MS + 90001, [{ level: "danger" }], "not-checking"],
    ["no warden keeps its state", { kind: "absent" }, MS, [{ level: "warn" }], "not-set-up"],
    ["an unreadable status keeps its state", { kind: "unreadable" }, MS, [{ level: "warn" }], "not-checking"]
];

// The next moment derive's answer can change with the file unchanged:
// [label, doc, now, moment]. Each moment is checked from both sides: the
// answer a millisecond before it is the answer at now, and the answer at
// it differs.
const NEXT = [
    ["a fresh status turns stale past 90 s", fixture("calm"), MS, MS + 90001],
    ["a status at its last fresh moment turns stale next", fixture("calm"), MS + 90000, MS + 90001],
    ["a status dated ahead turns fresh 90 s before its time", fixture("calm"), MS - 100000, MS - 90000]
];
// Statuses only a new read can change: [label, file or doc, now].
const NO_NEXT = [
    ["a status stale in the past", fixture("calm"), MS + 90001],
    ["nothing read yet", { kind: "pending" }, MS],
    ["no warden", { kind: "absent" }, MS],
    ["an unreadable status", { kind: "unreadable", cause: "json" }, MS],
    ["a major not read", { kind: "schema", schema: "2.0" }, MS],
    ["a 1.x from before items", { kind: "old-vsys", schema: "1.2" }, MS]
];

// The warden's Settings row per state: [label, detail fields, row].
const ROWS = [
    ["a calm warden", { state: "calm" }, { tone: "ok", text: "Running" }],
    ["information needs no step", { state: "info" }, { tone: "ok", text: "Running" }],
    ["a warning is not a healthy check", { state: "warn" }, { tone: "warning", text: "Warnings need attention" }],
    ["a problem", { state: "danger" }, { tone: "danger", text: "Problems need attention" }],
    ["a stale status", { state: "not-checking", reason: "stale" }, { tone: "warning", text: "Stopped checking" }],
    ["an unreadable status", { state: "not-checking", reason: "unreadable" }, { tone: "danger", text: "Could not read status" }],
    ["a major not read", { state: "not-checking", reason: "schema" }, { tone: "warning", text: "Update VGS to read this status" }],
    ["a vsys from before items", { state: "not-checking", reason: "old-vsys" }, { tone: "warning", text: "Needs a newer vsys" }],
    ["no warden", { state: "not-set-up" }, { tone: "info", text: "Not set up" }]
];

// GB figures: [bytes, shown].
const GIB = [[null, null], [0, 0], [536870912, 0.5], [9.94 * 1073741824, 9.9], [9.96 * 1073741824, 10], [25769803776, 24], [53687091200, 50], [111.6 * 1073741824, 112]];

function read(logic, doc) {
    const answer = logic.readStatus(JSON.stringify(doc));
    assert.equal(answer.kind, "read", "a fixture reads: " + JSON.stringify(answer));
    return { kind: "read", doc: answer.doc };
}

function verify(logic) {
    same(logic.STATES, ["calm", "info", "warn", "danger", "not-checking", "not-set-up"]);
    for (const name of fs.readdirSync(fixtures).filter(n => /^status-.*\.json$/.test(n)))
        assert.equal(logic.readStatus(fs.readFileSync(path.join(fixtures, name), "utf8")).kind, "read", "vsys fixture " + name + " reads");
    for (const [label, doc, want] of REFUSED)
        same(logic.readStatus(typeof doc === "string" ? doc : JSON.stringify(doc)), want, label);

    const reached = new Set();
    for (const [label, doc, now, want] of DERIVED) {
        const got = logic.derive(read(logic, doc), now);
        same(got, want, label);
        reached.add(got.state);
    }
    same(logic.derive({ kind: "pending" }, MS), null);
    const absent = logic.derive({ kind: "absent" }, MS);
    same(absent, { state: "not-set-up", reason: null, checkedAt: null, agents: null, items: [], memory: null });
    reached.add(absent.state);
    for (const [kind, reason] of [["unreadable", "unreadable"], ["schema", "schema"], ["old-vsys", "old-vsys"]])
        same(logic.derive({ kind: kind }, MS), { state: "not-checking", reason: reason, checkedAt: null, agents: null, items: [], memory: null }, kind);
    same([...reached].sort(), [...logic.STATES].sort(), "the tables reach every state");
    assert.throws(() => logic.derive({ kind: "later" }, MS), /file kind="later" unknown/);

    same(logic.withCauses(null, []), null, "no detail before a read");
    for (const [label, input, now, causes, want] of CAUSES) {
        const detail = logic.derive(input.kind === undefined ? read(logic, input) : input, now);
        const got = JSON.parse(JSON.stringify(logic.withCauses(detail, causes)));
        same([got.state, got.causes], [want, causes], label);
        same(Object.assign({}, got, { state: detail.state, causes: undefined }), JSON.parse(JSON.stringify(detail)), label + ": the rest of the detail stays");
    }

    for (const [label, doc, now, want] of NEXT) {
        const file = read(logic, doc);
        assert.equal(logic.nextChange(file, now), want, label);
        same(logic.derive(file, want - 1), JSON.parse(JSON.stringify(logic.derive(file, now))), label + ": unchanged until the moment");
        assert.notDeepEqual(JSON.parse(JSON.stringify(logic.derive(file, want))), JSON.parse(JSON.stringify(logic.derive(file, now))), label + ": changed at the moment");
    }
    for (const [label, input, now] of NO_NEXT)
        assert.equal(logic.nextChange(input.kind === undefined ? read(logic, input) : input, now), null, label);

    for (const [label, fields, want] of ROWS)
        same(logic.wardenRow(Object.assign({ reason: null, agents: null, checkedAt: null, items: [] }, fields)), want, label);
    assert.throws(() => logic.wardenRow({ state: "sleeping", items: [] }), /state="sleeping" unknown/);
    assert.throws(() => logic.wardenRow({ state: "not-checking", reason: "tired", items: [] }), /reason="tired" unknown/);

    // Published values: every declared key the detail tells.
    const calm = logic.derive(read(logic, fixture("calm")), MS);
    // A healthy warden's row carries no action. Its setup step reads done.
    same(logic.published(calm, []), { warden: { tone: "ok", text: "Running" }, setup: { tone: "ok", text: "Done" }, detail: JSON.parse(JSON.stringify(calm)), agents: 1, lastCheck: MS });
    same(logic.published(calm, ["vsys"]).warden, { tone: "ok", text: "Running" });
    same(logic.published(calm, ["vsys"]).setup, { tone: "ok", text: "Done" });
    // The setup row offers Set up exactly where the flyout's step is the
    // setup TUI: a warden not set up, with vsys present. Without vsys it
    // offers the missing tools' Review, the tools action. A row's hint is
    // its words, compared only for presence.
    const stateOf = (state, reason) => Object.assign(logic.derive({ kind: "absent" }, MS), { state: state, reason: reason === undefined ? null : reason });
    for (const [label, detail, missing, want, hinted] of [
        ["not set up with vsys", stateOf("not-set-up"), [], { tone: "warning", text: "Not set up", action: true }, false],
        ["not set up without vsys", stateOf("not-set-up"), ["vsys"], { tone: "warning", text: "Not set up", action: "tools" }, true],
        ["stopped checking", stateOf("not-checking", "stale"), [], { tone: "ok", text: "Done" }, false],
    ]) {
        const row = JSON.parse(JSON.stringify(logic.published(detail, missing).setup));
        assert.equal(typeof row.hint === "string", hinted, "setup row hint, " + label);
        delete row.hint;
        same(row, want, "setup row, " + label);
    }
    same(logic.published(stateOf("not-set-up"), []).warden, { tone: "info", text: "Not set up" }, "the warden row reads not set up without offering setup");
    for (const [label, detail, missing, want] of [
        ["not set up with vsys", stateOf("not-set-up"), [], "setup"],
        ["not set up without vsys", stateOf("not-set-up"), ["vsys"], "get-vsys"],
        ["stopped checking", stateOf("not-checking", "stale"), [], "start"],
        ["unreadable", stateOf("not-checking", "unreadable"), [], null],
        ["a vsys from before items", stateOf("not-checking", "old-vsys"), [], null],
        ["checking", calm, [], null],
    ]) assert.equal(logic.setupStep(detail, missing.indexOf("vsys") !== -1), want, "setup step, " + label);
    const unset = logic.derive({ kind: "absent" }, MS);
    same(Object.keys(logic.published(unset, ["vsys"])).sort(), ["detail", "setup", "warden"], "an unset warden publishes no count and no time");
    const unlisted = logic.derive(read(logic, edited("calm", d => { d.lanes = null; })), MS);
    same(Object.keys(logic.published(unlisted, [])).sort(), ["detail", "lastCheck", "setup", "warden"], "unlisted lanes publish no count");

    verifyPlacement(logic, manifestFile);

    for (const [bytes, want] of GIB) assert.equal(logic.gib(bytes), want, "gib " + bytes);
}

function verifyPlacement(logic, source) {
    const checked = manifest(source);
    const base = logic.derive({ kind: "absent" }, MS);
    const detailOf = (state, reason) => Object.assign({}, base, { state, reason: reason === undefined ? null : reason, items: state === "danger" ? [FULL] : [] });
    // [label, detail, missing commands, the Setup step's button kind or
    // null, setupNeeds open]: "status" is the step's own Set up, "tools"
    // the Review of the missing tools.
    const rows = [
        ["not set up with vsys", detailOf("not-set-up"), [], "status", true],
        ["not set up without vsys", detailOf("not-set-up"), ["vsys"], "tools", true],
        ["calm", detailOf("calm"), [], null, false],
        ["warn", detailOf("warn"), [], null, false],
        ["danger", detailOf("danger"), [], null, false],
        ["stale", detailOf("not-checking", "stale"), [], null, false],
        ["unreadable", detailOf("not-checking", "unreadable"), [], null, false],
        ["schema", detailOf("not-checking", "schema"), [], null, false],
    ];
    for (const [label, detail, missing, buttonKind, needsOpen] of rows) {
        const values = logic.published(detail, missing);
        // The core's status write admits each value the service publishes.
        Object.keys(values).reduce((held, key) => {
            const written = producer.statusWrite(checked, held, key, values[key]);
            assert.equal(written.ok, true, "the status write admits " + key + ": " + label + ": " + written.error);
            return written.values;
        }, {});
        const status = producer.statusRows(checked, values);
        const requirements = producer.requirementRows(checked, missing, {});
        const warden = steps.detailEntries(status).find(entry => entry.key === "warden");
        assert.notEqual(warden, undefined, "Details keeps the warden reading: " + label);
        // The reading offers no press of its own, on or off: Set up is the
        // Setup step's alone.
        same([true, false].map(enabled => steps.detailButtons(warden, { enabled, name: "Agent Warden" }).action), [null, null],
            "the warden reading offers no action: " + label);
        const section = steps.setupSections(producer.listedTuis(checked), status, requirements, { enabled: true, failed: false }).find(row => row.title === "Setup");
        assert.notEqual(section, undefined, "Setup section exists: " + label);
        const setup = section.items.find(item => item.key === "setup");
        assert.notEqual(setup, undefined, "the setup step is on Setup: " + label);
        assert.equal(steps.detailEntries(status).some(entry => entry.key === "setup"), false, "setup is never on Details: " + label);
        assert.equal(setup.button === null ? null : setup.button.kind, buttonKind, "setup button matches the open setup step: " + label);
        same(steps.setupNeeds(status, requirements, true).open, needsOpen, "setupNeeds.open: " + label);
    }
}

verify(load(file));

// Each control removes one rule from a copy of the logic and keeps the
// text around it. The suite must fail on every copy.
const CONTROLS = [
    ["staleness ignored", "if (Math.abs(now - checkedAt) > STALE_AFTER_MS) {", "if (false) {"],
    ["a future time is fresh", "Math.abs(now - checkedAt)", "(now - checkedAt)"],
    ["an unknown major is read", "if (Number(version[1]) !== SUPPORTED_MAJOR) return", "if (false) return"],
    ["a status from before items is read", "if (Number(version[2]) < ITEMS_MINOR) return", "if (false) return"],
    ["fields go unchecked", "var field = shapeError(doc);", "var field = \"\";"],
    ["any item level is read", "[\"level\", function (v) { return LEVELS.indexOf(v) !== -1; }]", "[\"level\", function (v) { return true; }]"],
    ["an action without a label is read", "return firstFailing(action, [[\"id\", nonEmpty], [\"label\", nonEmpty]]);", "return \"\";"],
    ["information reads as calm", "has(\"info\") ? \"info\" : ", ""],
    ["the summary's causes are ignored", "out.state = stateOf(detail.items.concat(causes));", "out.state = stateOf(detail.items);"],
    ["the causes raise a state that is not fresh", "if (causes !== null && [\"calm\", \"info\", \"warn\", \"danger\"].indexOf(detail.state) !== -1)", "if (causes !== null)"],
    ["no stale moment", "return checkedAt + STALE_AFTER_MS + 1;", "return null;"],
    ["no moment for a status dated ahead", "if (checkedAt - now > STALE_AFTER_MS) return checkedAt - STALE_AFTER_MS;", ""],
    ["a past stale status sets a moment", "if (now - checkedAt > STALE_AFTER_MS) return null;", ""],
    ["leftover work counts as an agent", " && orphans.indexOf(lane.scope) === -1", ""],
    ["an unidentified lane counts as an agent", "lane.label.tool !== null && ", ""],
    ["an unknown count is published", "if (detail.agents !== null) out.agents", "out.agents"],
    ["GB always one decimal", "return value < 10 ?", "return true ?"],
    ["the setup step never offers Set up", "if (step === \"setup\") row.action = true;", ""],
    ["the setup step without vsys offers no Review", "row.action = \"tools\";", ""],
    ["Set up offered without vsys", "return vsysMissing ? \"get-vsys\" : \"setup\";", "return \"setup\";"],
    ["a healthy warden reads as a warning", "return { tone: \"ok\", text: \"Running\" };", "return { tone: \"warning\", text: \"Running\" };"],
    ["a warning reads as healthy", "case \"warn\": return { tone: \"warning\", text: \"Warnings need attention\" };", "case \"warn\": return { tone: \"ok\", text: \"Running\" };"],
    ["a healthy setup step offers Set up", "return { tone: \"ok\", text: \"Done\" };", "return { tone: \"ok\", text: \"Done\", action: true };"],
    ["the warden row carries Set up again", "var out = { warden: wardenRow(detail), setup: setup, detail: detail };", "var out = { warden: Object.assign(wardenRow(detail), { action: true }), setup: setup, detail: detail };"],
    ["vsys is published as a status value", "var out = { warden: wardenRow(detail), setup: setup, detail: detail };", "var out = { warden: wardenRow(detail), setup: setup, vsys: \"present\", detail: detail };"]
];

const source = fs.readFileSync(file, "utf8");
const scratchRoot = os.tmpdir();
fs.mkdirSync(scratchRoot, { recursive: true });
const temp = fs.mkdtempSync(path.join(scratchRoot, "agent-warden-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const mutant = path.join(temp, "WardenLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, () => replacement));
        let failed = false;
        try {
            verify(load(mutant));
        } catch (e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the suite passed on logic without that rule`);
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}

const manifestSource = fs.readFileSync(manifestFile, "utf8");
const manifestTemp = fs.mkdtempSync(path.join(scratchRoot, "agent-warden-manifest-control-"));
try {
    const mutant = path.join(manifestTemp, "manifest.json");
    const doc = JSON.parse(manifestSource);
    doc.status.warden.action = { label: "Set up", tui: "setup" };
    fs.writeFileSync(mutant, JSON.stringify(doc, null, 2));
    let failed = false;
    try {
        verifyPlacement(load(file), mutant);
    } catch (e) {
        failed = true;
    }
    assert.ok(failed, "control \"warden action in manifest\": the placement check passed with the action back on warden");
} finally {
    fs.rmSync(manifestTemp, { recursive: true, force: true });
}

// The `open` judge in ViewLogic.js copies PluginLogic.tuiArgsValid, which
// shell.tui.run applies again at the press. On each list both answer
// alike, so the flyout neither offers an action whose arguments the core
// refuses nor hides one it runs. An absent list is left out: the core
// reads it as none, and the view refuses an action or cause that lacks
// one.
const view = load(path.join(path.dirname(file), "ViewLogic.js"), { "qs.Commons 1.0": {} });
const OPEN_EDGES = [
    [], ["--lane", "claude-vgs"], Array(16).fill("a"), Array(17).fill("a"), ["a".repeat(256)], ["a".repeat(257)],
    ["\u{1F600}".repeat(256)], ["\u{1F600}".repeat(257)], ["a", ""], ["a\nb"], ["a\tb"], ["a\u007fb"], ["a\u0085b"], ["a\u009fb"], ["a b"],
    ["$(touch x)", "a b"], [3], [null], [{ length: 1 }], null, "abc", { 0: "a", length: 1 }
];
for (const open of OPEN_EDGES)
    assert.equal(view.openValid(open), producer.tuiArgsValid(open), "the view judges open " + JSON.stringify(open).slice(0, 40) + " as the core does");
assert.ok(OPEN_EDGES.some(open => producer.tuiArgsValid(open)) && OPEN_EDGES.some(open => !producer.tuiArgsValid(open)), "the edges hold lists the core admits and lists it refuses");

console.log(`test-agent-warden-logic: ok refused=${REFUSED.length} derived=${DERIVED.length} causes=${CAUSES.length} next=${NEXT.length + NO_NEXT.length} controls=${CONTROLS.length + 1}`);
