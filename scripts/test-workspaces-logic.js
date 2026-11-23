#!/usr/bin/env node
// Table-driven checks for the pills one bar's Workspaces widget draws
// (shell/plugins/vgs.workspaces/WorkspacesLogic.js): which workspaces each
// display's bar shows, with and without Split by display and Show empty
// workspaces, and which one it lights. The world is the owner's home:
// DP-2 holds workspace 1, DP-1 holds 2 and 3, and the workspace rules put
// 1 on DP-2, 2 to 9 on DP-1 and three special workspaces on DP-1, as
// HyprlandState.workspaceRules reads them. Expected values are written
// here by hand. Controls edit one rule in a copy of the logic and require
// this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.workspaces", "WorkspacesLogic.js");
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), JSON.parse(JSON.stringify(want)), message);

// Workspaces.items: 2 is the focused one, on DP-1; DP-2 shows 1.
const items = [{ id: 1, output: "DP-2", active: true }, { id: 2, output: "DP-1", active: true }, { id: 3, output: "DP-1", active: false }];
const monitors = [{ name: "DP-1", description: "Dell Inc. DELL U2720Q 1" }, { name: "DP-2", description: "LG Electronics LG ULTRAGEAR 2" }];
const rule = (workspace, monitor) => ({ workspace: workspace, id: /^[0-9]+$/.test(workspace) && Number(workspace) > 0 ? Number(workspace) : null, monitor: monitor });
const ownerRules = [rule("1", "DP-2")].concat([2, 3, 4, 5, 6, 7, 8, 9].map(n => rule(String(n), "DP-1")))
    .concat(["special:scratch", "special:music", "special:notes"].map(name => rule(name, "DP-1")));
const pill = (id, active) => ({ id: id, active: active === true });
const empties = from => [4, 5, 6, 7, 8, 9].filter(n => n >= from).map(n => pill(n));

function verify(lib) {
    // rows: [name, items, rules, screen, want]
    const rows = [
        ["off: every bar shows every workspace and lights the focused one", items, null, "", [pill(1), pill(2, true), pill(3)]],
        ["split: DP-2's bar shows 1 and lights it", items, null, "DP-2", [pill(1, true)]],
        ["split: DP-1's bar shows 2 and 3 and lights the one it shows", items, null, "DP-1", [pill(2, true), pill(3)]],
        ["a workspace with no known monitor is on no split bar", [{ id: 5, output: "", active: false }], null, "DP-1", []],
        ["empty: every bar adds the rules' empty workspaces, not the special ones", items, ownerRules, "", [pill(1), pill(2, true), pill(3)].concat(empties(4))],
        ["empty and split: DP-1's bar adds the empty ones its rules name", items, ownerRules, "DP-1", [pill(2, true), pill(3)].concat(empties(4))],
        ["empty and split: DP-2's bar adds none", items, ownerRules, "DP-2", [pill(1, true)]],
        ["a held workspace keeps its own monitor over its rule's", [{ id: 4, output: "DP-2", active: true }], [rule("4", "DP-1")], "DP-2", [pill(4, true)]],
        ["a rule with no monitor shows on every bar while not split", [], [rule("100", "")], "", [pill(100)]],
        ["a rule with no monitor shows on no split bar", [], [rule("100", "")], "DP-1", []],
        ["the first rule for a workspace places it", [], [rule("6", "DP-2"), rule("6", "DP-1")], "DP-1", []],
        ["a rule naming its monitor by description finds the output", [], [rule("7", "desc:LG Electronics")], "DP-2", [pill(7)]],
        ["a description no monitor starts with places nowhere", [], [rule("7", "desc:Samsung")], "DP-2", []],
        ["a rule for a monitor not connected shows on no split bar", [], [rule("8", "HDMI-A-1")], "DP-1", []],
        ["an empty workspace stands in id order among the held ones", [{ id: 3, output: "DP-1", active: true }], [rule("1", "DP-1")], "", [pill(1), pill(3)]],
        ["no workspace and no rule", [], [], "", []],
    ];
    for (const [name, has, rules, screen, want] of rows)
        same(lib.pills(has, rules, monitors, screen, 2), want, name);
}

verify(load(file));

const CONTROLS = [
    ["a split bar keeps only its own monitor's workspaces", 'if (screen === "" || items[i].output === screen)', "if (true)"],
    ["a split bar lights the workspace its monitor shows", 'active: screen === "" ? items[i].id === focusedId : items[i].active', "active: items[i].id === focusedId"],
    ["a held workspace is not added again from its rule", "rule.id === null || held[rule.id] === true || ", "rule.id === null || "],
    ["a special or named rule adds no pill", "if (rule.id === null || ", "if ("],
    ["only the first rule for a workspace places it", " || named[rule.id] === true) continue;", ") continue;"],
    ["a desc: monitor is matched by its description's start", "if (monitors[i].description.indexOf(start) === 0) return monitors[i].name;", "if (monitors[i].description === start) return monitors[i].name;"],
    ["the pills are in id order", "out.sort(function (a, b) { return a.id - b.id; });", ""],
];

const source = fs.readFileSync(file, "utf8");
fs.mkdirSync(os.tmpdir(), { recursive: true });
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "workspaces-logic-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const mutant = path.join(temp, "WorkspacesLogic.js");
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
console.log(`test-workspaces-logic: ok controls=${CONTROLS.length}`);
