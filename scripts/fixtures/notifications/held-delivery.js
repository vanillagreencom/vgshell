#!/usr/bin/env node
// Native row control: omit the real rule-held delivery in its disposable
// shell copy. AppSounds and its stream judgement remain the shipped code.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const [action, file, backup] = process.argv.slice(2);
assert.equal(process.argv.length, 5, "expected suppress-held|restore-held SERVICE BACKUP");
assert.equal(fs.lstatSync(file).isSymbolicLink(), false);
const original = "ruleHeldSerials: soundRule.held";
const suppressed = "ruleHeldSerials: []";
if (action === "suppress-held") {
    const source = fs.readFileSync(file, "utf8");
    assert.equal(source.split(original).length, 2, "one actual held delivery binding");
    const changed = source.replace(original, suppressed);
    assert.notEqual(changed, source);
    fs.writeFileSync(backup, source, { flag: "wx" });
    fs.writeFileSync(file, changed);
} else if (action === "restore-held") {
    assert.equal(fs.lstatSync(backup).isSymbolicLink(), false);
    const source = fs.readFileSync(backup, "utf8");
    const current = fs.readFileSync(file, "utf8");
    assert.equal(source.split(original).length, 2);
    assert.equal(current, source.replace(original, suppressed), "restore only this control's own edit");
    fs.writeFileSync(file, source);
    fs.unlinkSync(backup);
} else throw new Error("unknown held-delivery action");
