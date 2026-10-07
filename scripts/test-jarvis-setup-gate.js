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
const judge = load(path.join(__dirname, "..", "shell", "Core", "PluginLogic.js"));
const settings = load(path.join(__dirname, "..", "shell", "plugins", "vgs.settings", "Steps.js"));

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
    for (const cause of ["speech=local-memory-insufficient", "speech=local-memory-unavailable"]) {
        const got = plain(gate.readiness({ kind: "answered", causes: [cause] }));
        assert.deepEqual([got.setup.tone, got.setupVoice.tone, got.setupVoice.action, got.setupModel.tone],
            ["warning", "warning", false, "ok"], "memory refuses capture without reinstall action");
        assert.equal(got.setupVoice.lines, undefined, "recovery is no state badge");
        assert.equal(typeof got.setupVoice.hint, "string");
        assert.notEqual(got.setupVoice.hint.trim(), "", "memory refusal carries guidance");
    }
    assert.equal(new Set(lines).size, BRAIN_CAUSES.length, "each brain cause says its own line");
    // Before the daemon answers nothing reads ready or to do.
    const checking = plain(gate.readiness({ kind: "checking" }));
    assert.deepEqual([checking.setup.tone, checking.setup.action], ["info", undefined], "checking: setup");
    for (const key of ["setupVoice", "setupModel"])
        assert.deepEqual([checking[key].tone, checking[key].action], ["info", false], "checking: " + key);
    assert.equal(gate.readiness({ kind: "checking" }).setupVoice, gate.CHECKING);
    assert.equal(gate.readiness({ kind: "answered", causes: ["speech=local-loading"] }).setupVoice, gate.LOADING);
    assert.equal(gate.readiness({ kind: "answered", causes: ["speech=local-loading"] }).setup, gate.LOADING_SUMMARY);
    assert.notEqual(gate.LOADING, gate.CHECKING, "loading and initial checking have distinct values");
    for (const causes of [["speech=local-loading"], ["speech=local-loading", "brain=unselected"]]) {
        const loading = plain(gate.readiness({ kind: "answered", causes }));
        assert.deepEqual([loading.setupVoice.tone, loading.setupVoice.action], ["info", false]);
        assert.equal(loading.setup.tone, causes.length === 1 ? "info" : "warning");
        assert.equal(loading.setup.action, undefined);
        assert.deepEqual([loading.setupModel.tone, loading.setupModel.action], causes.length === 1 ? ["ok", false] : ["warning", true]);
    }
    // A stopped daemon runs no check: its steps claim none and offer none.
    const stopped = plain(gate.readiness({ kind: "stopped" }));
    assert.deepEqual(Object.keys(stopped).sort(), ["setup", "setupModel", "setupVoice"], "stopped");
    assert.equal(stopped.setup.tone, "danger", "stopped: the summary");
    for (const key of ["setupVoice", "setupModel"])
        assert.deepEqual([stopped[key].tone === checking[key].tone, stopped[key].action], [false, false], "stopped: " + key);
    assert.throws(() => gate.readiness({ kind: "answered", causes: ["voice=missing"] }), /^Error: jarvis-setup: cause=voice=missing/);
    // An optional step: done while its reader is ok, else optional with
    // its reader's action.
    for (const [label, key, value, want] of [
        ["browser ready", "setupBrowser", READY, ["ok", false]],
        ["browser to set up", "setupBrowser", ABSENT, ["info", true]],
        ["browser withheld", "setupBrowser", { tone: "warning", text: "Needs agent-browser", action: false }, ["info", false]],
        ["input ready", "setupInput", { tone: "ok", text: "Keys ready; pointer ready", action: true }, ["ok", false]],
        ["input missing", "setupInput", { tone: "warning", text: "Input tools unavailable", action: true }, ["info", true]]]) {
        const got = plain(gate.optionalStep(key, value));
        assert.deepEqual([got.tone, got.action], want, label);
        assert.equal(typeof got.text, "string");
        assert.notEqual(got.text.trim(), "", "an optional step carries a state label");
        assert.equal(got.hint, undefined, "optional guidance stays in the manifest");
        assert.equal(got.lines, undefined, "optional guidance is no state badge");
    }
    assert.throws(() => gate.optionalStep("setupModel", READY), /step=setupModel is not optional/);
    // Every value the service publishes is one the manifest judge accepts
    // for its entry, so a refused write cannot stop the service's start.
    const manifest = judge.validateManifest(JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8")), path.dirname(file)).manifest;
    const answers = READINESS.map(row => row[1]).concat([{ kind: "checking" }, { kind: "stopped" },
        { kind: "answered", causes: ["speech=local-memory-insufficient"] },
        { kind: "answered", causes: ["speech=local-memory-unavailable"] }]);
    for (const answer of answers)
        for (const [key, value] of Object.entries(plain(gate.readiness(answer))))
            assert.equal(judge.statusWrite(manifest, {}, key, value).ok, true, "the manifest judge accepts " + key + " for " + JSON.stringify(answer));
    for (const [key, value] of [["setupBrowser", READY], ["setupBrowser", ABSENT], ["setupInput", ABSENT]])
        assert.equal(judge.statusWrite(manifest, {}, key, plain(gate.optionalStep(key, value))).ok, true, "the manifest judge accepts " + key);
    const published = {
        ...plain(gate.readiness({ kind: "answered", causes: ["speech=local-memory-insufficient"] })),
        setupBrowser: plain(gate.optionalStep("setupBrowser", ABSENT)),
        setupInput: plain(gate.optionalStep("setupInput", ABSENT))
    };
    const fixtureManifest = plain(manifest);
    published.setupVoice.hint = "fixture state voice guidance";
    for (const key of ["setupVoice", "setupBrowser", "setupInput"]) {
        fixtureManifest.status[key].hint = "fixture declaration " + key;
        if (key !== "setupVoice") {
            assert.equal(published[key].hint, undefined, "optional guidance stays in the manifest");
            assert.equal(typeof manifest.status[key].hint, "string");
            assert.notEqual(manifest.status[key].hint.trim(), "", "the manifest owns the guidance");
        }
        const hint = key === "setupVoice" ? "fixture state voice guidance" : "fixture declaration " + key;
        const accepted = judge.statusWrite(fixtureManifest, {}, key, published[key]);
        assert.equal(accepted.ok, true);
        const row = judge.statusRows(fixtureManifest, accepted.values, []).find(entry => entry.key === key);
        const view = settings.statusView(row, String);
        assert.deepEqual(plain([view.hint, view.lines]), [hint, []], "Settings draws one badge with plain guidance: " + key);
    }
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
    ["memory guidance is a badge", "out.setupVoice = MEMORY[cause];", "out.setupVoice = Object.assign({}, MEMORY[cause], { lines: [MEMORY[cause].hint], hint: undefined });"],
    ["optional guidance is a badge", "action: value.action === true };", 'lines: ["fixture guidance"], action: value.action === true };'],
    ["optional guidance changes with state", "action: value.action === true };", 'hint: "fixture guidance", action: value.action === true };'],
    ["memory refusal offers reinstall", 'if (Object.prototype.hasOwnProperty.call(MEMORY, cause)) {', 'if (false) {'],
    ["loading is initial checking", "out.setupVoice = LOADING;", "out.setupVoice = CHECKING;"],
    ["loading offers setup", 'if (cause === "speech=local-loading") {', 'if (false) {'],
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
    ["checking reads done", 'return { setup: CHECKING_SUMMARY, setupVoice: CHECKING, setupModel: CHECKING };', 'return { setup: CHECKING_SUMMARY, setupVoice: DONE, setupModel: DONE };'],
    ["an optional step reads done when not ok", 'if (value.tone === "ok") return DONE;', "if (true) return DONE;"],
    ["an optional step drops its action", "action: value.action === true };", "action: false };"],
    ["the checking summary offers a step", "return { setup: CHECKING_SUMMARY,", "return { setup: CHECKING,"],
    ["a stopped daemon's steps read checking", "setupVoice: UNCHECKED, setupModel: UNCHECKED };", "setupVoice: CHECKING, setupModel: CHECKING };"],
    ["a cause naming no step is taken", 'if (!Object.prototype.hasOwnProperty.call(REQUIRED, step)) throw new Error("jarvis-setup: cause=" + cause + " names no step");', ""],
    ["a required step reads as optional", 'if (!Object.prototype.hasOwnProperty.call(OPTIONAL, key)) throw new Error("jarvis-setup: step=" + key + " is not optional");', ""]
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
