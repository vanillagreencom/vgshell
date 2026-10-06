#!/usr/bin/env node
// The Settings page's setup-step rule, shell/plugins/vgs.settings/Steps.js,
// under node: a status row, a presence list's item and a requirement each
// show their step button only while it applies. The rows are the core's
// own, PluginLogic.statusRows and requirementRows over a manifest written
// here, so the rule is read against what the Settings page is handed; every
// expected value is written out by hand.
//
// The controls at the end edit a copy of the rule, one rule at a time, and
// require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.settings", "Steps.js");
const producer = load(path.join(__dirname, "..", "shell", "Core", "PluginLogic.js"));
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message);

const MANIFEST = {
    requirements: [
        { command: "acme-tool", optional: true, purpose: "A tool" },
        { command: "acme-other", optional: false, purpose: "Another tool" }
    ],
    tui: { setup: { script: "tui/setup.sh", title: "Set up", size: "default", presentation: "full", entry: null, requires: null } },
    status: {
        token: { type: "presence", label: "Token", action: { label: "Set up token", tui: "setup" } },
        warden: { type: "state", label: "Warden", group: "Setup", action: { label: "Set up", tui: "setup" } },
        bare: { type: "state", label: "Bare", action: { label: "Fix", tui: "setup" } },
        pending: { type: "count", label: "Pending" },
        accounts: { type: "presenceList", label: "Accounts" }
    }
};

// A status entry's step: [label, key, published values, { offered }].
const ENTRIES = [
    ["an absent presence offers its step", "token", { token: "absent" }, { offered: true }],
    ["a present presence shows none", "token", { token: "present" }, { offered: false }],
    ["a locked presence shows none", "token", { token: "locked" }, { offered: false }],
    ["a state that calls for its action offers it", "warden", { warden: { tone: "info", text: "Not set up", action: true } }, { offered: true }],
    ["a healthy state shows none", "warden", { warden: { tone: "ok", text: "Running" } }, { offered: false }],
    ["a failing state its writer gives no action shows none", "warden", { warden: { tone: "danger", text: "Could not read status" } }, { offered: false }],
    ["an unreported entry shows none", "warden", {}, { offered: false }],
    ["an offered action without a command offers the button", "bare", { bare: { tone: "warning", text: "Broken", action: true } }, { offered: true }],
    ["an entry without an action offers nothing", "pending", { pending: 3 }, { offered: false }]
];

// The manager row's listed setup screens.
const TUIS = [
    { name: "setup", label: "Set up again", icon: "download", withheld: "" },
    { name: "configure", label: "Configure", icon: "sliders-horizontal", withheld: "" }
];
// The same screens while the requirements both need are missing, as
// PluginLogic.listedTuiRows marks them.
const WITHHELD = TUIS.map(tui => Object.assign({}, tui, { withheld: "Needs acme-other. Install requirements first." }));
const BUTTONS = [
    ["a state that calls for its step draws it first, primary", { warden: { tone: "warning", text: "Not set up", action: true } }, [], [["setup", "Set up", true], ["configure", "Configure", false]]],
    ["a ready state draws every screen secondary, in manifest order", { warden: { tone: "ok", text: "Ready" } }, [], [["setup", "Set up again", false], ["configure", "Configure", false]]],
    ["nothing published draws every screen secondary", {}, [], [["setup", "Set up again", false], ["configure", "Configure", false]]],
    ["a withheld step keeps its place with the withheld label", { warden: { tone: "warning", text: "Not set up", action: true } }, ["acme-other"], [["setup", "Install requirements", true], ["configure", "Configure", false]]],
    ["two entries offering one screen draw it once, the first's", { token: "absent", warden: { tone: "warning", text: "Not set up", action: true } }, [], [["setup", "Set up token", true], ["configure", "Configure", false]]]
];

// MANIFEST with its requirements as the judge hands them on, which a
// withheld step reads.
const NORMAL = Object.assign({}, MANIFEST, { requirements: producer.normalRequirements(MANIFEST.requirements) });

function verify(logic) {
    for (const [label, key, values, want] of ENTRIES) {
        const row = producer.statusRows(MANIFEST, values, []).find(entry => entry.key === key);
        same(logic.statusStep(row), want, label);
    }
    // setupEntries: the Setup group's entries alone.
    same(logic.setupEntries(producer.statusRows(MANIFEST, {}, [])).map(entry => entry.key), ["warden"], "the Setup section takes the Setup group's entries");
    // setupButtons: [label, published values, missing requirements, the
    // buttons as [name, label, primary]]. The manager row lists setup and
    // configure; a step is drawn first, primary, with its action's label.
    for (const [label, values, missing, want] of BUTTONS) {
        const buttons = logic.setupButtons(TUIS, producer.statusRows(NORMAL, values, missing));
        same(buttons.map(b => [b.name, b.label, b.primary]), want, "setupButtons: " + label);
    }
    // A withheld screen draws disabled with its reason, but for the step an
    // offered action names, which installs what it lacks.
    const withheld = logic.setupButtons(WITHHELD, producer.statusRows(NORMAL, { warden: { tone: "warning", text: "Not set up", action: true } }, ["acme-other"]));
    same(withheld.map(b => [b.name, b.primary, b.enabled, b.reason !== ""]), [["setup", true, true, false], ["configure", false, false, true]], "setupButtons: a withheld screen draws disabled with a reason, the step stays active");
    same(logic.setupButtons(TUIS, producer.statusRows(NORMAL, {}, [])).map(b => [b.enabled, b.reason]), [[true, ""], [true, ""]], "setupButtons: a screen that lacks nothing takes a press");
    same(new Set(logic.setupButtons(TUIS, producer.statusRows(MANIFEST, { warden: { tone: "warning", text: "Not set up", action: true } }, [])).concat(logic.setupButtons(TUIS, producer.statusRows(MANIFEST, {}, [])))
        .map(b => b.key)).size, 3, "setupButtons: a step and the same screen's plain button are drawn as different buttons");
    // statusView: what a line draws of a state, with its lines.
    same(logic.statusView(producer.statusRows(MANIFEST, { warden: { tone: "ok", text: "Ready", lines: ["v1"] } }, []).find(e => e.key === "warden"), String),
        { label: "Warden", hint: "", info: "", offered: false, tone: "success", text: "Ready", lines: ["v1"], muted: false, items: [] }, "a reported state draws its text, tone and lines");
    same(logic.statusView(producer.statusRows(MANIFEST, {}, []).find(e => e.key === "warden"), String).text, "Not reported", "an unreported entry reads Not reported");
    const requirements = producer.requirementRows({ requirements: producer.normalRequirements(MANIFEST.requirements) }, ["acme-tool"]);
    same(requirements.map(logic.requirementApplies), [true, false], "the install step applies to the missing requirement alone");
}

verify(load(file));

// Each control removes one rule from a copy of the logic and keeps the
// text around it. The suite must fail on every copy.
const CONTROLS = [
    ["a declared action is always offered", "entry.action !== null && entry.action.offered", "entry.action !== null"],
    ["a present requirement still offers its install", "return requirement.state === \"missing\";", "return true;"],
    ["the Setup section takes every group", "return entry.group === SETUP_GROUP;", "return true;"],
    ["an offered step draws secondary", "add(tui, entry.action.label, true);", "add(tui, entry.action.label, false);"],
    ["an offered step keeps its screen's label", "add(tui, entry.action.label, true);", "add(tui, tui.label, true);"],
    ["a screen draws twice", "if (tui !== undefined && !has(tui.name))", "if (tui !== undefined)"],
    ["a button's key ignores its prominence and state", "key: tui.name + \" \" + label + \" \" + primary + \" \" + enabled,", "key: tui.name,"],
    ["a withheld screen takes a press", "var enabled = primary || tui.withheld === \"\";", "var enabled = true;"],
    ["the step is withheld too", "var enabled = primary || tui.withheld === \"\";", "var enabled = tui.withheld === \"\";"],
    ["a withheld screen gives no reason", "reason: enabled ? \"\" : tui.withheld", "reason: \"\""],
    ["a state draws no lines", "if (entry.value.lines !== undefined) out.lines = entry.value.lines;", ""]
];

const source = fs.readFileSync(file, "utf8");
const scratchRoot = path.join(__dirname, "..", "tmp");
fs.mkdirSync(scratchRoot, { recursive: true });
const temp = fs.mkdtempSync(path.join(scratchRoot, "settings-steps-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const mutant = path.join(temp, "Steps.js");
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
console.log(`test-settings-steps: ok entries=${ENTRIES.length} controls=${CONTROLS.length}`);
