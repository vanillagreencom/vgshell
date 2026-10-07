#!/usr/bin/env node
// Which setup step Jarvis offers while a command its setup needs is missing,
// shell/plugins/vgs.jarvis/SetupGate.js, under node: the value a setup reader
// publishes for its probe's value and the requirements capability's missing
// list, the value of a requirement's own Install row, and the Setup
// section's summary and steps from the daemon's answer, read by their tone,
// action and line count. Every expected value is written out by hand. No
// process, file or network is used.
//
// The controls at the end edit a copy of the library, one rule at a time,
// and require this suite to fail an assertion on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.jarvis", "SetupGate.js");
const ABSENT = { tone: "warning", text: "Browser needs setup", action: true };
const READY = { tone: "ok", text: "Private browser ready", action: false };
// [label, probe value, requires, missing, null for the probe value itself or
// the commands the withheld value names].
const SETUP = [
    ["nothing required", ABSENT, [], ["agent-browser"], null],
    ["required and found", ABSENT, ["agent-browser"], [], null],
    ["another command missing", ABSENT, ["agent-browser"], ["bwrap", "uv"], null],
    ["ready with its command found", READY, ["agent-browser"], ["bwrap"], null],
    ["required and missing", ABSENT, ["agent-browser"], ["bwrap", "agent-browser"], ["agent-browser"]],
    ["ready yet missing", READY, ["agent-browser"], ["agent-browser"], ["agent-browser"]],
    ["two of three missing", ABSENT, ["node", "agent-browser", "chromium"], ["chromium", "node"], ["node", "chromium"]]
];
// [label, command, missing, expected value].
const REQUIREMENT = [
    ["found", "agent-browser", [], { tone: "ok", text: "Installed", action: false }],
    ["another command missing", "agent-browser", ["bwrap"], { tone: "ok", text: "Installed", action: false }],
    ["missing", "agent-browser", ["bwrap", "agent-browser"], { tone: "warning", text: "Not installed", action: true }]
];

// The Setup section from the daemon's answer: [label, answer, the summary's
// tone, the steps still to do]. A step to do is a warning with one line and
// its action; a done step is ok with none.
const READINESS = [
    ["ready", { kind: "answered", causes: [] }, "ok", []],
    ["nothing set up", { kind: "answered", causes: ["speech=local-not-set-up", "brain=unselected"] }, "warning", ["setupVoice", "setupModel"]],
    ["local voice only", { kind: "answered", causes: ["speech=local-not-ready"] }, "warning", ["setupVoice"]],
    ["the AI model only", { kind: "answered", causes: ["brain=account-unavailable"] }, "warning", ["setupModel"]],
    // ChainedEngine's cause while no speech row exists has no line of its own.
    ["a cause with no line of its own", { kind: "answered", causes: ["speech=no-adapter"] }, "warning", ["setupVoice"]]
];
// Each brain cause asks for its own action.
const BRAIN_CAUSES = ["brain=unselected", "brain=account-unavailable", "brain=model-required", "brain=accounts-unreadable"];
const plain = value => JSON.parse(JSON.stringify(value));

function verifyReadiness(gate) {
    for (const [label, answer, tone, todo] of READINESS) {
        const got = plain(gate.readiness(answer));
        assert.deepEqual(Object.keys(got).sort(), ["setup", "setupModel", "setupVoice"], label);
        assert.equal(got.setup.tone, tone, label + ": the summary");
        assert.equal(got.setup.action, undefined, label + ": the summary offers no step");
        for (const key of ["setupVoice", "setupModel"]) {
            const step = got[key];
            const open = todo.includes(key);
            assert.deepEqual([step.tone, step.action, (step.lines || []).length], open ? ["warning", true, 1] : ["ok", false, 0], label + ": " + key);
            if (open) assert.equal(typeof step.lines[0] === "string" && step.lines[0] !== "" && !/=/.test(step.lines[0]), true,
                label + ": a plain line, no keyed cause on screen");
        }
    }
    const lines = BRAIN_CAUSES.map(cause => plain(gate.readiness({ kind: "answered", causes: [cause] })).setupModel.lines[0]);
    assert.equal(new Set(lines).size, BRAIN_CAUSES.length, "each brain cause says its own line");
    // Before the daemon answers nothing reads ready or to do.
    const checking = plain(gate.readiness({ kind: "checking" }));
    for (const key of ["setup", "setupVoice", "setupModel"])
        assert.deepEqual([checking[key].tone, checking[key].action], ["info", false], "checking: " + key);
    const stopped = plain(gate.readiness({ kind: "stopped" }));
    assert.deepEqual([Object.keys(stopped), stopped.setup.tone], [["setup"], "danger"], "a stopped daemon leaves the steps");
    assert.throws(() => gate.readiness({ kind: "answered", causes: ["voice=missing"] }), /^Error: jarvis-setup: cause=voice=missing/);
    // An optional step: done while its reader is ok, else optional with
    // its reader's action.
    for (const [label, key, value, want] of [
        ["browser ready", "setupBrowser", READY, ["ok", false, 0]],
        ["browser to set up", "setupBrowser", ABSENT, ["info", true, 1]],
        ["browser withheld", "setupBrowser", { tone: "warning", text: "Needs agent-browser", action: false }, ["info", false, 1]],
        ["input ready", "setupInput", { tone: "ok", text: "Keys ready; pointer ready", action: true }, ["ok", false, 0]],
        ["input missing", "setupInput", { tone: "warning", text: "Input tools unavailable", action: true }, ["info", true, 1]]]) {
        const got = plain(gate.optionalStep(key, value));
        assert.deepEqual([got.tone, got.action, (got.lines || []).length], want, label);
    }
    assert.throws(() => gate.optionalStep("setupModel", READY), /step=setupModel is not optional/);
}

function verify(gate) {
    verifyReadiness(gate);
    for (const [label, value, requires, missing, names] of SETUP) {
        const got = gate.setupValue(value, requires, missing);
        if (names === null) {
            assert.equal(got, value, label + ": the probe value is published as it is");
            continue;
        }
        assert.equal(got.tone, "warning", label);
        assert.equal(got.action, false, label + ": the setup step is withheld");
        for (const command of requires)
            assert.equal(got.text.includes(command), names.includes(command), label + ": the text names " + command + " only while it is missing");
        const at = names.map(command => got.text.indexOf(command));
        assert.deepEqual(at, [...at].sort((x, y) => x - y), label + ": the missing commands in declaration order");
    }
    for (const [label, command, missing, want] of REQUIREMENT)
        // The library's objects come from its own context; compare a copy.
        assert.deepEqual(JSON.parse(JSON.stringify(gate.requirementValue(command, missing))), want, label);
}

verify(load(file));

// Each control removes one rule from a copy and keeps the text around it:
// [label, needle, replacement].
const CONTROLS = [
    ["a missing command does not withhold setup", "return missing.indexOf(command) !== -1; });", "return false; });"],
    ["the withheld step keeps its action", 'lacking.join(" and "), action: false', 'lacking.join(" and "), action: value.action'],
    ["any missing command withholds setup", "var lacking = requires.filter(", "var lacking = missing.filter("],
    ["the withheld text names every required command", 'lacking.join(" and ")', 'requires.join(" and ")'],
    ["a missing requirement offers no install", 'if (missing.indexOf(command) === -1) return { tone: "ok"', 'if (true) return { tone: "ok"'],
    ["a found requirement offers its install", 'if (missing.indexOf(command) === -1) return { tone: "ok"', 'if (false) return { tone: "ok"'],
    ["a cause marks no step", "out[REQUIRED[step]] = {", "void {"],
    ["a cause marks the other step", 'var REQUIRED = { speech: "setupVoice", brain: "setupModel" };', 'var REQUIRED = { speech: "setupModel", brain: "setupVoice" };'],
    ["the brain causes share one line", "var line = Object.prototype.hasOwnProperty.call(TODO, cause) ? TODO[cause] : STEP_TODO[step];", "var line = STEP_TODO[step];"],
    ["an unknown cause has no line", "var line = Object.prototype.hasOwnProperty.call(TODO, cause) ? TODO[cause] : STEP_TODO[step];", "var line = TODO[cause];"],
    ["causes leave the summary ready", 'setup: answer.causes.length === 0 ? { tone: "ok", text: "Ready" }', 'setup: true ? { tone: "ok", text: "Ready" }'],
    ["checking reads done", 'return { setup: CHECKING, setupVoice: CHECKING, setupModel: CHECKING };', 'return { setup: CHECKING, setupVoice: DONE, setupModel: DONE };'],
    ["an optional step reads done when not ok", 'if (value.tone === "ok") return DONE;', "if (true) return DONE;"],
    ["an optional step drops its action", "action: value.action === true };", "action: false };"]
];

const source = fs.readFileSync(file, "utf8");
const scratchRoot = path.join(__dirname, "..", "tmp");
fs.mkdirSync(scratchRoot, { recursive: true });
const temp = fs.mkdtempSync(path.join(scratchRoot, "jarvis-setup-gate-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const changed = source.replace(needle, () => replacement);
        assert.notEqual(changed, source, `control "${label}": the copy changed`);
        const copy = path.join(temp, "SetupGate.js");
        fs.writeFileSync(copy, changed);
        let failure = null;
        try {
            verify(load(copy));
        } catch (e) {
            failure = e;
        }
        assert.ok(failure instanceof assert.AssertionError, `control "${label}": the suite passed on a copy without that rule` +
            (failure === null ? "" : ", or failed on something other than an assertion: " + failure));
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
console.log(`test-jarvis-setup-gate: ok cases=${SETUP.length + REQUIREMENT.length + READINESS.length} controls=${CONTROLS.length}`);
