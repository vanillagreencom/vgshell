#!/usr/bin/env node
// Native row fixtures change only their disposable shell copy. AppSounds
// and the rule stay shipped code; timer wiring uses a short published hold.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const [action, file, backup] = process.argv.slice(2);
assert.equal(process.argv.length, 5, "expected ACTION FILE BACKUP");
assert.equal(fs.lstatSync(file).isSymbolicLink(), false);
const edits = [
    { apply: "suppress-held", restore: "restore-held", original: "ruleHeldSerials: soundRule.held", changed: "ruleHeldSerials: []" },
    { apply: "short-deadline", restore: "restore-deadline", original: "var APP_SOUND_HOLD = 15000;", changed: "var APP_SOUND_HOLD = 1000;" },
];
const edit = edits.find(entry => entry.apply === action || entry.restore === action);
assert.ok(edit, "unknown native hold fixture action");
const { original, changed: suppressed } = edit;
if (action === edit.apply) {
    const source = fs.readFileSync(file, "utf8");
    assert.equal(source.split(original).length, 2, "one native fixture match");
    const changed = source.replace(original, suppressed);
    assert.notEqual(changed, source);
    fs.writeFileSync(backup, source, { flag: "wx" });
    fs.writeFileSync(file, changed);
} else {
    assert.equal(fs.lstatSync(backup).isSymbolicLink(), false);
    const source = fs.readFileSync(backup, "utf8");
    const current = fs.readFileSync(file, "utf8");
    assert.equal(source.split(original).length, 2);
    assert.equal(current, source.replace(original, suppressed), "restore only this fixture's own edit");
    fs.writeFileSync(file, source);
    fs.unlinkSync(backup);
}
