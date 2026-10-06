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
        warden: { type: "state", label: "Warden", action: { label: "Set up", tui: "setup" } },
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

function verify(logic) {
    for (const [label, key, values, want] of ENTRIES) {
        const row = producer.statusRows(MANIFEST, values, []).find(entry => entry.key === key);
        same(logic.statusStep(row), want, label);
    }
    const requirements = producer.requirementRows({ requirements: producer.normalRequirements(MANIFEST.requirements) }, ["acme-tool"]);
    same(requirements.map(logic.requirementApplies), [true, false], "the install step applies to the missing requirement alone");
}

verify(load(file));

// Each control removes one rule from a copy of the logic and keeps the
// text around it. The suite must fail on every copy.
const CONTROLS = [
    ["a declared action is always offered", "entry.action !== null && entry.action.offered", "entry.action !== null"],
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
console.log(`test-settings-steps: ok entries=${ENTRIES.length} controls=${CONTROLS.length}`);
