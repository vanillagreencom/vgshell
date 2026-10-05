#!/usr/bin/env node
// The Settings page's setup-step rule, shell/plugins/vgs.settings/Steps.js,
// under node: a status row, a presence list's item and a requirement each
// show their step, its button and the command behind Show command, only
// while it applies. The rows are the core's own, PluginLogic.statusRows and
// requirementRows over a manifest written here, so the rule is read against
// what the Settings page is handed; every expected value is written out by
// hand.
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

const TOKEN_COMMAND = "secret-tool store service acme account token";
const WARDEN_COMMAND = "acme warden install";
const SLACK_COMMAND = "secret-tool store service acme account slack:T0ACME";
const MANIFEST = {
    requirements: [
        { command: "acme-tool", optional: true, purpose: "A tool" },
        { command: "acme-other", optional: false, purpose: "Another tool" }
    ],
    tui: { setup: { script: "tui/setup.sh", title: "Set up", size: "default", presentation: "full", entry: null, requires: null } },
    status: {
        token: { type: "presence", label: "Token", action: { label: "Set up token", tui: "setup" }, command: TOKEN_COMMAND },
        warden: { type: "state", label: "Warden", action: { label: "Set up", tui: "setup" }, command: WARDEN_COMMAND },
        bare: { type: "state", label: "Bare", action: { label: "Fix", tui: "setup" } },
        pending: { type: "count", label: "Pending" },
        accounts: { type: "presenceList", label: "Accounts" }
    }
};

// A status entry's step: [label, key, published values, { offered, command }].
const ENTRIES = [
    ["an absent presence offers its step and its command", "token", { token: "absent" }, { offered: true, command: TOKEN_COMMAND }],
    ["a present presence shows neither", "token", { token: "present" }, { offered: false, command: "" }],
    ["a locked presence shows neither", "token", { token: "locked" }, { offered: false, command: "" }],
    ["a state that calls for its action offers both", "warden", { warden: { tone: "info", text: "Not set up", action: true } }, { offered: true, command: WARDEN_COMMAND }],
    ["a healthy state shows neither", "warden", { warden: { tone: "ok", text: "Running" } }, { offered: false, command: "" }],
    ["a failing state its writer gives no action shows neither", "warden", { warden: { tone: "danger", text: "Could not read status" } }, { offered: false, command: "" }],
    ["an unreported entry shows neither", "warden", {}, { offered: false, command: "" }],
    ["an offered action without a command offers the button alone", "bare", { bare: { tone: "warning", text: "Broken", action: true } }, { offered: true, command: "" }],
    ["an entry without an action offers nothing", "pending", { pending: 3 }, { offered: false, command: "" }]
];

// A presence list item's command: [label, published item, command drawn].
const ITEMS = [
    ["an absent secret keeps its command beside Connect", { label: "Acme", value: "absent", secret: "slack:T0ACME", command: SLACK_COMMAND }, SLACK_COMMAND],
    ["a stored secret draws Disconnect alone", { label: "Acme", value: "present", secret: "slack:T0ACME", command: SLACK_COMMAND }, ""],
    ["a locked secret draws Disconnect alone", { label: "Acme", value: "locked", secret: "slack:T0ACME", command: SLACK_COMMAND }, ""],
    ["a store that cannot be asked draws no command", { label: "Acme", value: "unavailable", secret: "slack:T0ACME", command: SLACK_COMMAND }, ""],
    ["an item without a secret draws no command", { label: "Globex", value: "absent" }, ""]
];

function verify(logic) {
    for (const [label, key, values, want] of ENTRIES) {
        const row = producer.statusRows(MANIFEST, values, []).find(entry => entry.key === key);
        same(logic.statusStep(row), want, label);
    }
    for (const [label, item, want] of ITEMS) {
        const row = producer.statusRows(MANIFEST, { accounts: [item] }, []).find(entry => entry.key === "accounts");
        assert.equal(logic.itemCommand(row.value[0]), want, label);
    }
    const requirements = producer.requirementRows({ requirements: producer.normalRequirements(MANIFEST.requirements) }, ["acme-tool"]);
    same(requirements.map(logic.requirementApplies), [true, false], "the install step applies to the missing requirement alone");
}

verify(load(file));

// Each control removes one rule from a copy of the logic and keeps the
// text around it. The suite must fail on every copy.
const CONTROLS = [
    ["a present entry still shows its command", "command: offered ? entry.command : \"\"", "command: entry.command"],
    ["a declared action is always offered", "entry.action !== null && entry.action.offered", "entry.action !== null"],
    ["a stored item still shows its command", "return item.access === \"connect\" ? item.command : \"\";", "return item.command;"],
    ["a present requirement still offers its install", "return requirement.state === \"missing\";", "return true;"]
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
console.log(`test-settings-steps: ok entries=${ENTRIES.length} items=${ITEMS.length} controls=${CONTROLS.length}`);
