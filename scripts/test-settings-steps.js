#!/usr/bin/env node
// The Settings page's setup-step rule, shell/plugins/vgs.settings/Steps.js,
// under node: a status row, a presence list's item and a requirement each
// show their step button only while it applies, and an entry that lists a
// plugin's stored keys draws in the Setup section alone. The rows are the core's
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
        pending: { type: "count", label: "Pending", hint: "Read the vendor page.", link: { text: "vendor page", url: "https://vendor.example/pending" } },
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
    ["a state that calls for its step draws it first, with its label", { warden: { tone: "warning", text: "Not set up", action: true } }, [], [["setup", "Set up"], ["configure", "Configure"]]],
    ["a ready state draws every screen in manifest order", { warden: { tone: "ok", text: "Ready" } }, [], [["setup", "Set up again"], ["configure", "Configure"]]],
    ["nothing published draws every screen", {}, [], [["setup", "Set up again"], ["configure", "Configure"]]],
    ["a withheld step keeps its place with the withheld label", { warden: { tone: "warning", text: "Not set up", action: true } }, ["acme-other"], [["setup", "Install requirements"], ["configure", "Configure"]]],
    ["two entries offering one screen draw it once, the first's", { token: "absent", warden: { tone: "warning", text: "Not set up", action: true } }, [], [["setup", "Set up token"], ["configure", "Configure"]]]
];

// MANIFEST with its requirements as the judge hands them on, which a
// withheld step reads.
const NORMAL = Object.assign({}, MANIFEST, { requirements: producer.normalRequirements(MANIFEST.requirements) });

// A page with setup steps: a summary, then two steps of the Setup group,
// and an entry elsewhere that offers the first step's screen too.
const STEPPED = {
    requirements: [],
    tui: {
        keys: { script: "tui/keys.sh", title: "Add key", size: "default", presentation: "full", entry: null, requires: null },
        browser: { script: "tui/browser.sh", title: "Set up browser", size: "default", presentation: "full", entry: null, requires: null },
        accounts: { script: "tui/accounts.sh", title: "Accounts", size: "default", presentation: "full", entry: null, requires: null }
    },
    status: {
        summary: { type: "state", label: "Setup", group: "Setup" },
        model: { type: "state", label: "AI model", group: "Setup", action: { label: "Add key", tui: "keys" } },
        browser: { type: "state", label: "Browser", group: "Setup", action: { label: "Set up browser", tui: "browser" } },
        keyStore: { type: "state", label: "API keys", action: { label: "Add key", tui: "keys" } }
    }
};
const STEPPED_TUIS = [
    { name: "keys", label: "Add key", icon: "key-round", withheld: "" },
    { name: "browser", label: "Set up browser", icon: "globe", withheld: "" },
    { name: "accounts", label: "Accounts", icon: "users", withheld: "" }
];
const TODO = { tone: "warning", text: "To do", action: true };
const DONE = { tone: "ok", text: "Done", action: false };
// [label, manifest, listed screens, published values, the rows as [label,
// step, button name and label or null], the Flow's actions as [name,
// label]].
const ROWS = [
    ["a step to do draws its screen beside it, once", STEPPED, STEPPED_TUIS,
        { summary: { tone: "warning", text: "Not ready" }, model: TODO, browser: DONE, keyStore: { tone: "info", text: "No key", action: true } },
        [["Status", false, null], ["AI model", true, ["keys", "Add key"]], ["Browser", true, null]],
        [["browser", "Set up browser"], ["accounts", "Accounts"]]],
    ["every step done draws no button beside a step", STEPPED, STEPPED_TUIS,
        { summary: { tone: "ok", text: "Ready" }, model: DONE, browser: DONE, keyStore: { tone: "ok", text: "1 key", action: true } },
        [["Status", false, null], ["AI model", true, null], ["Browser", true, null]],
        [["keys", "Add key"], ["browser", "Set up browser"], ["accounts", "Accounts"]]],
    ["two steps to do each draw their own screen", STEPPED, STEPPED_TUIS,
        { summary: { tone: "warning", text: "Not ready" }, model: TODO, browser: TODO },
        [["Status", false, null], ["AI model", true, ["keys", "Add key"]], ["Browser", true, ["browser", "Set up browser"]]],
        [["accounts", "Accounts"]]],
    ["a single Setup entry stays the Status row, its screen in the Flow", MANIFEST, TUIS,
        { warden: { tone: "warning", text: "Not set up", action: true } },
        [["Status", false, null]],
        [["setup", "Set up"], ["configure", "Configure"]]]
];

// A plugin that stores keys: a state and the presence list of its accounts.
const KEYED = {
    requirements: [],
    tui: {},
    secrets: { service: "acme-keys", label: "Acme key" },
    status: {
        check: { type: "state", label: "Check" },
        keys: { type: "presenceList", label: "Acme keys" }
    }
};
// A plugin that stores keys through a setup screen of its own: its manifest
// groups their presence list under Setup, beside a state of that group and
// a presence list that lists no key.
const OWN = {
    requirements: [],
    tui: {},
    status: {
        summary: { type: "state", label: "Setup", group: "Setup" },
        keys: { type: "presenceList", label: "Provider keys", group: "Setup" },
        accounts: { type: "presenceList", label: "Accounts", group: "AI model" }
    }
};
// A presence list's item as a line draws it: [label, item, { tone, text }].
const ITEMS = [
    ["a secret nothing is stored for draws no chip", { label: "A", value: "absent", secret: "acme:a" }, { tone: "", text: "" }],
    ["a stored secret draws its chip", { label: "A", value: "present", secret: "acme:a" }, { tone: "success", text: "Present" }],
    ["a locked secret draws its chip", { label: "A", value: "locked", secret: "acme:a" }, { tone: "info", text: "Locked" }],
    ["a signed-out account keeps its chip", { label: "A", value: "signed-out", secret: "acme:a" }, { tone: "warning", text: "Signed out" }],
    ["an absent item that is no secret keeps its chip", { label: "A", value: "absent" }, { tone: "warning", text: "Absent" }]
];

function verify(logic) {
    const hintSpec = { hintFrom: "warden" };
    for (const [label, values, want] of [
        ["discovery pending", {}, ""],
        ["no supported card", { warden: { tone: "info", text: "Not found", hint: "No supported graphics card found." } }, "No supported graphics card found."],
        ["supported card", { warden: { tone: "ok", text: "Available", hint: "" } }, ""]
    ]) {
        same(logic.settingHint(hintSpec, producer.statusRows(MANIFEST, values, [])), want, "settingHint: " + label);
    }
    same(logic.settingHint(hintSpec, []), "", "a disabled or removed state gives no live hint");
    same(logic.settingHint({ description: "Fixed guidance" }, []), "Fixed guidance", "existing fixed descriptions still draw");
    same(logic.settingHint({}, []), "", "a field without guidance draws none");
    for (const [label, key, values, want] of ENTRIES) {
        const row = producer.statusRows(MANIFEST, values, []).find(entry => entry.key === key);
        same(logic.statusStep(row), want, label);
    }
    // setupEntries: the Setup group's entries alone.
    same(logic.setupEntries(producer.statusRows(MANIFEST, {}, [])).map(entry => entry.key), ["warden"], "the Setup section takes the Setup group's entries");
    // keyEntries and detailEntries: the entry that lists the stored keys
    // draws with the setup, and every other entry on Details.
    const keyed = producer.statusRows(KEYED, {}, []);
    same([logic.keyEntries(keyed).map(entry => entry.key), logic.detailEntries(keyed).map(entry => entry.key)], [["keys"], ["check"]], "the stored keys' entry leaves Details for the Setup section");
    const own = producer.statusRows(OWN, {}, []);
    same([logic.keyEntries(own).map(entry => entry.key), logic.detailEntries(own).map(entry => entry.key), logic.setupEntries(own).map(entry => entry.key)],
        [["keys"], ["summary", "accounts"], ["summary"]], "a presence list grouped under Setup draws as stored keys, off Details and off the step rows");
    const plain = producer.statusRows(MANIFEST, {}, []);
    same([logic.keyEntries(plain).map(entry => entry.key), logic.detailEntries(plain).map(entry => entry.key)], [[], ["token", "warden", "bare", "pending", "accounts"]], "a plugin that stores no key keeps every entry on Details");
    for (const [label, item, want] of ITEMS) {
        const drawn = producer.statusRows(KEYED, { keys: [item] }, []).find(entry => entry.key === "keys").value[0];
        same(logic.itemView(drawn), want, "itemView: " + label);
    }
    // setupButtons: [label, published values, missing requirements, the
    // actions as [name, label]]. The manager row lists setup and
    // configure; a step is drawn first, with its action's label.
    for (const [label, values, missing, want] of BUTTONS) {
        const buttons = logic.setupButtons(TUIS, producer.statusRows(NORMAL, values, missing));
        same(buttons.map(b => [b.name, b.label]), want, "setupButtons: " + label);
    }
    // A withheld screen draws disabled with its reason, but for the step an
    // offered action names, which installs what it lacks.
    const withheld = logic.setupButtons(WITHHELD, producer.statusRows(NORMAL, { warden: { tone: "warning", text: "Not set up", action: true } }, ["acme-other"]));
    same(withheld.map(b => [b.name, b.enabled, b.reason !== ""]), [["setup", true, false], ["configure", false, true]], "setupButtons: a withheld screen draws disabled with a reason, the step stays active");
    same(logic.setupButtons(TUIS, producer.statusRows(NORMAL, {}, [])).map(b => [b.enabled, b.reason]), [[true, ""], [true, ""]], "setupButtons: a screen that lacks nothing takes a press");
    same(new Set(logic.setupButtons(TUIS, producer.statusRows(MANIFEST, { warden: { tone: "warning", text: "Not set up", action: true } }, [])).concat(logic.setupButtons(TUIS, producer.statusRows(MANIFEST, {}, [])))
        .map(b => b.key)).size, 3, "setupButtons: a step and the same screen's plain button are drawn as different buttons");
    // setupRows: the first Setup entry is the Status row, each further one
    // a step under its own label with its offered screen beside it, which
    // the Flow then leaves out.
    for (const [label, manifest, tuis, values, rows, flow] of ROWS) {
        const status = producer.statusRows(manifest, values, []);
        same(logic.setupRows(tuis, status).map(row => [row.label, row.step, row.button === null ? null : [row.button.name, row.button.label]]),
            rows, "setupRows: " + label);
        same(logic.setupButtons(tuis, status).map(b => [b.name, b.label]), flow, "setupButtons beside steps: " + label);
    }
    // statusView: what a line draws of a state, with its lines.
    same(logic.statusView(producer.statusRows(MANIFEST, { warden: { tone: "ok", text: "Ready", lines: ["v1"] } }, []).find(e => e.key === "warden"), String),
        { label: "Warden", hint: "", info: "", link: null, offered: false, tone: "success", text: "Ready", lines: ["v1"], muted: false, items: [] }, "a reported state draws its text, tone and lines");
    same(logic.statusView(producer.statusRows(MANIFEST, {}, []).find(e => e.key === "warden"), String).text, "Not reported", "an unreported entry reads Not reported");
    same(logic.statusView(producer.statusRows(MANIFEST, { pending: 2 }, []).find(e => e.key === "pending"), String).link,
        { text: "vendor page", url: "https://vendor.example/pending" }, "a line draws its entry's link");
    const requirements = producer.requirementRows({ requirements: producer.normalRequirements(MANIFEST.requirements) }, ["acme-tool"]);
    same(requirements.map(logic.requirementApplies), [true, false], "the install step applies to the missing requirement alone");
}

verify(load(file));

// Each control removes one rule from a copy of the logic and keeps the
// text around it. The suite must fail on every copy.
const CONTROLS = [
    ["a line drops its entry's link", "info: entry.info, link: entry.link, offered:", "info: entry.info, link: null, offered:"],
    ["a live hint is drawn", 'return entry === undefined || entry.report !== "reported" ? "" : entry.hint;', 'return "";'],
    ["a declared action is always offered", "entry.action !== null && entry.action.offered", "entry.action !== null"],
    ["a present requirement still offers its install", "return requirement.state === \"missing\";", "return true;"],
    ["the Setup section takes every group", "entry.group === SETUP_GROUP && !listsKeys(entry)", "!listsKeys(entry)"],
    ["the stored keys draw among the step rows too", "entry.group === SETUP_GROUP && !listsKeys(entry)", "entry.group === SETUP_GROUP"],
    ["every entry draws among the stored keys", "return status.filter(listsKeys);", "return status;"],
    ["the stored keys' entry stays on Details", "return !listsKeys(entry);", "return true;"],
    ["the core's stored keys stay on Details", "return entry.secrets || (", "return ("],
    ["a plugin's own stored keys stay on Details", ' || (entry.type === "presenceList" && entry.group === SETUP_GROUP)', ""],
    ["a Setup state draws among the stored keys", 'entry.type === "presenceList" && entry.group === SETUP_GROUP', "entry.group === SETUP_GROUP"],
    ["a presence list of any group draws among the stored keys", 'entry.type === "presenceList" && entry.group === SETUP_GROUP', 'entry.type === "presenceList"'],
    ["a secret nothing is stored for draws its chip", 'if (item.access === "connect" && item.value === "absent") return { tone: "", text: "" };', ""],
    ["a signed-out account loses its chip", 'item.access === "connect" && item.value === "absent"', 'item.access === "connect"'],
    ["an offered step keeps its screen's label", "add(tui, entry.action.label, true);", "add(tui, tui.label, true);"],
    ["a screen draws twice", "if (tui !== undefined && !has(tui.name))", "if (tui !== undefined)"],
    ["a button's key ignores its label and state", "key: tui.name + \" \" + label + \" \" + enabled,", "key: tui.name,"],
    ["a withheld screen takes a press", "var enabled = offered || tui.withheld === \"\";", "var enabled = true;"],
    ["the step is withheld too", "var enabled = offered || tui.withheld === \"\";", "var enabled = tui.withheld === \"\";"],
    ["a withheld screen gives no reason", "reason: enabled ? \"\" : tui.withheld", "reason: \"\""],
    ["a state draws no lines", "if (entry.value.lines !== undefined) out.lines = entry.value.lines;", ""],
    ["a step drops its button", "button: step ? stepButton(tuis, entry) : null", "button: null"],
    ["a step's screen draws in the Flow too", "beside.indexOf(name) !== -1 || ", ""],
    ["a step reads Status", 'label: step ? entry.label : "Status"', 'label: "Status"'],
    ["a single Setup entry draws as a step", "var step = index > 0;", "var step = true;"]
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
console.log(`test-settings-steps: ok entries=${ENTRIES.length} rows=${ROWS.length} controls=${CONTROLS.length}`);
