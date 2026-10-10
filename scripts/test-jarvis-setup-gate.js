#!/usr/bin/env node
// Which setup step Jarvis offers while a command its setup needs is missing,
// shell/plugins/vgs.jarvis/SetupGate.js, under node: the value a setup reader
// publishes for its probe's value and the requirements capability's missing
// list, the value of a requirement's own Install row, and the Setup
// section's summary and steps from the daemon's answer, read by their tone,
// action and line count. The shipped account and service callbacks also
// determine the model action. No shell process, network or audio is used.
//
// The controls at the end edit a copy of the library, one rule at a time,
// and require this suite to fail an assertion on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const vm = require("node:vm");
const { load } = require("../bin/lib/qml-library.js");
const judge = load(path.join(__dirname, "..", "shell", "Core", "PluginLogic.js"));
const settings = load(path.join(__dirname, "..", "shell", "plugins", "vgs.settings", "Steps.js"));
const protocol = load(path.join(__dirname, "..", "shell", "plugins", "vgs.jarvis", "JarvisProtocol.js"));

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
// tone, the steps still to do, the steps to do that keep their declared
// hint, the AI model's named action while to do, "key" when left out]. A
// step to do is a warning with its action and, unless its action already
// says what it asks, a hint of its own; a done step is ok with neither. No
// step draws lines: what it asks is description, its hint.
const READINESS = [
    ["ready", { kind: "answered", causes: [] }, "ok", [], []],
    ["nothing set up", { kind: "answered", causes: ["speech=local-not-set-up", "brain=unselected"] }, "warning", ["setupVoice", "setupModel"], ["setupVoice"]],
    ["local voice only", { kind: "answered", causes: ["speech=local-not-ready"] }, "warning", ["setupVoice"], []],
    ["the AI model only", { kind: "answered", causes: ["brain=account-unavailable"] }, "warning", ["setupModel"], []],
    // ChainedEngine's cause while no speech row exists has no hint of its own.
    ["a cause with no hint of its own", { kind: "answered", causes: ["speech=no-adapter"] }, "warning", ["setupVoice"], ["setupVoice"]],
    // A brain cause with no hint of its own takes the step's.
    ["a brain cause with no hint of its own", { kind: "answered", causes: ["brain=unnamed"] }, "warning", ["setupModel"], []],
    ["a signed-out AI model", { kind: "answered", causes: ["brain=signed-out"] }, "warning", ["setupModel"], [], "signIn"],
    ["a Pi older than the Pi brain's floor", { kind: "answered", causes: ["brain=pi-update"] }, "warning", ["setupModel"], []]
];
// Each step's action once done: the voice step's boolean; the AI model's
// manifest entry declares named actions, so its value carries none.
const DONE_ACTION = { setupVoice: false, setupModel: undefined };
// The home folder's causes: Home.js's and Guidance.js's. One without a hint
// of its own takes the step's.
const HOME_CAUSES = ["home=link", "home=path", "home=unwritable", "guidance=home-too-large", "guidance=home-skills-too-large"];
// Each brain cause asks for its own action.
const BRAIN_CAUSES = ["brain=unselected", "brain=account-unavailable", "brain=model-required", "brain=accounts-unreadable", "brain=signed-out",
    "brain=pi-update"];
// The TUI each of the AI model's named actions opens, from the manifest.
const MODEL_TUI = { key: "add-key", signIn: "sign-in" };
const plain = value => JSON.parse(JSON.stringify(value));
// The voice the daemon hears of: [label, the settings a user changed over the
// manifest's own, the stored OpenAI keys the account reader holds or
// undefined while it has no answer, the voice]. A fresh settings file holds
// only the manifest's values.
const KEY = [{ value: "openai-1", label: "OpenAI / fixture" }];
const VOICE = [
    ["a fresh settings file with no key", {}, [], "local"],
    ["a stored key and no choice", { voiceAccount: "openai-1" }, KEY, "realtime"],
    ["a stored key the Realtime key setting does not name", {}, KEY, "local"],
    ["the named key removed", { voiceAccount: "openai-1" }, [], "local"],
    ["the named key before the reader answers", { voiceAccount: "openai-1" }, undefined, "realtime"],
    ["no key before the reader answers", {}, undefined, "local"],
    ["Local chosen beside a stored key", { voiceProvider: "local", voiceAccount: "openai-1" }, KEY, "local"],
    ["Realtime chosen with no key", { voiceProvider: "realtime" }, [], "realtime"],
    ["Always talk mode beside a stored key", { mode: "always", voiceAccount: "openai-1" }, KEY, "local"],
    ["Always talk mode with Realtime chosen", { mode: "always", voiceProvider: "realtime", voiceAccount: "openai-1" }, KEY, "realtime"]
];
// The Voice group's key row: [label, the stored keys or null for a failed
// read, its tone and whether it offers Add key].
const VOICE_KEY = [["no key", [], ["info", true]], ["a stored key", KEY, ["ok", false]], ["keys unread", null, ["warning", true]]];

// Execute the shipped Details row accessor and the shipped Settings row
// projection against the same published status. This checks their source
// selection; the nested smoke and pictures check the rendered consumers.
const pageFile = path.join(path.dirname(file), "..", "vgs.settings", "PluginPage.qml");
const serviceFile = path.join(path.dirname(file), "Service.qml");
const accountsFile = path.join(path.dirname(file), "Accounts.qml");
const words = require(path.join(path.dirname(file), "AccountStatus.js"));
const UNSELECTED = { kind: "answered", causes: ["brain=unselected"] };
const SIGNED_OUT = { kind: "answered", causes: ["brain=signed-out"] };
// want: the AI model step's tone and the named action it offers, undefined
// for none. An app is an account row of the helper's status: signIn is
// whether Sign in serves its signed-out account.
const MODEL = [
    { name: "key only before model discovery", keys: [{ value: "present" }], apps: [], answer: UNSELECTED, want: ["warning", undefined] },
    { name: "signed-in app before model discovery", keys: [], apps: [{ source: "cli", state: "signed-in" }], answer: UNSELECTED, want: ["warning", undefined] },
    { name: "verified app", keys: [], apps: [{ source: "cli", state: "verified" }], answer: UNSELECTED, want: ["warning", undefined] },
    { name: "app verification pending", keys: [], apps: [{ source: "cli", state: "verifying" }], answer: UNSELECTED, want: ["warning", undefined] },
    { name: "neither key nor app", keys: [], apps: [], answer: UNSELECTED, want: ["warning", "key"] },
    { name: "found app folder Sign in does not serve", keys: [], apps: [{ source: "cli", state: "found" }], answer: UNSELECTED, want: ["warning", "key"] },
    { name: "signed-out app folder", keys: [], apps: [{ source: "cli", state: "found", signIn: true }], answer: UNSELECTED, want: ["warning", "signIn"] },
    { name: "signed-out app beside a signed-in one", keys: [], apps: [{ source: "cli", state: "found", signIn: true }, { source: "cli", state: "signed-in" }],
        answer: UNSELECTED, want: ["warning", undefined] },
    { name: "signed-out app beside a key", keys: [{ value: "present" }], apps: [{ source: "cli", state: "found", signIn: true }], answer: UNSELECTED, want: ["warning", undefined] },
    { name: "signed-out AI model chosen", keys: [{ value: "present" }], apps: [{ source: "cli", state: "signed-in" }], answer: SIGNED_OUT, want: ["warning", "signIn"] },
    { name: "unchecked app folder", keys: [], apps: [{ source: "cli", state: "unchecked" }], answer: UNSELECTED, want: ["warning", "key"] },
    { name: "locked key", keys: [{ value: "locked" }], apps: [], answer: UNSELECTED, want: ["warning", undefined] },
    { name: "unavailable key reader", keys: [{ value: "unavailable" }], apps: [], answer: UNSELECTED, want: ["warning", undefined] },
    { name: "key reader has not answered", keys: undefined, apps: [], answer: UNSELECTED, want: ["warning", undefined] },
    { name: "app reader failed", keys: [], apps: [], code: 1, answer: UNSELECTED, want: ["warning", undefined] },
    { name: "selected model", keys: [{ value: "present" }], apps: [], answer: { kind: "answered", causes: [] }, want: ["ok", undefined] },
    { name: "checking", keys: [], apps: [], answer: { kind: "checking" }, want: ["info", undefined] }
];

// Run both shipped publication functions. Accounts supplies typed sign-in
// facts; Service publishes the model row without relying on offered models.
function verifyModelConsumers(gate, serviceSource, accountsSource) {
    const publishAccounts = accountsSource.match(/^    function publish\(\) \{\n[\s\S]*?^    \}/m);
    const publishSetup = serviceSource.match(/^    function publishSetup\(answer\) \{\n[\s\S]*?^    \}/m);
    assert.ok(publishAccounts && publishSetup);
    const accessor = fs.readFileSync(pageFile, "utf8").match(/function statusEntry\(key\) \{[\s\S]*?\n    \}/);
    assert.ok(accessor, "the Details accessor is present");
    const manifest = judge.validateManifest(JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8")), path.dirname(file)).manifest;
    for (const row of MODEL) {
        const values = row.keys === undefined ? {} : { keys: row.keys.map(key => ({ label: "Fixture key", ...key })) };
        if (row.keys !== undefined) assert.equal(judge.statusWrite(manifest, {}, "keys", values.keys).ok, true);
        const shell = { settings: { voiceAccount: "" }, status: { values, set: (key, value) => {
            const accepted = judge.statusWrite(manifest, values, key, value);
            assert.equal(accepted.ok, true, row.name + ": accepted status " + key);
            values[key] = value;
            return "ok";
        } } };
        const root = { shell, modelAccess: { kind: "checking" }, pending: false,
            completion: { kind: "exited", code: row.code ?? 0 }, diagnostic: { kind: "collected", text: "" },
            output: JSON.stringify({ accounts: row.apps.map(app => ({ label: "Fixture app", value: "present", plan: "", email: "", mismatch: false, signIn: false, ...app })),
                brains: [], voiceAccounts: [], search: { found: row.apps.length, partial: "" } }), refreshed: () => {} };
        vm.runInNewContext("(function() { with(root) { return (" + publishAccounts[0] + ").call(root); } })()",
            { root, Gate: gate, Words: words, Providers: { probeFailure: () => "jarvis-accounts: probe=failed" }, console: { warn: () => {} } });
        vm.runInNewContext("(" + publishSetup[0] + ")", { Gate: gate, shell, accountReader: root })(row.answer);
        try {
            assert.deepEqual([values.setupModel.tone, values.setupModel.action], row.want, row.name);
            const entry = judge.statusRows(manifest, values, []).find(item => item.key === "setupModel");
            assert.equal(entry.action.offered, row.want[1] !== undefined, row.name + ": the actual row action");
            const setupRow = settings.setupRows([{ name: "add-key" }, { name: "sign-in" }], judge.statusRows(manifest, values, []))
                .find(item => item.entry.key === "setupModel");
            assert.equal(setupRow.button === null ? undefined : setupRow.button.name, MODEL_TUI[row.want[1]], row.name + ": Settings link");
            // A signed-out app replaces the cause's hint with its own.
            if (row.answer === UNSELECTED) {
                const detailsEntry = vm.runInNewContext("(" + accessor[0] + ")", { row: { status: judge.statusRows(manifest, values, []) } })("setupModel");
                const unselected = gate.readiness(UNSELECTED).setupModel.hint;
                for (const [consumer, actual] of [["Settings", setupRow.entry], ["Details", detailsEntry]]) {
                    const hint = settings.statusView(actual, String).hint;
                    if (row.want[1] !== "signIn")
                        assert.equal(hint, "Choose an AI model in Settings > AI model.", row.name + ": " + consumer + " AI model hint");
                    else assert.deepEqual([typeof hint, hint === unselected], ["string", false],
                        row.name + ": " + consumer + " signed-out hint replaces the unselected one");
                }
            }
        } catch (error) {
            error.check = "setup-model-action";
            error.case = row.name;
            throw error;
        }
    }
}
// Run the shipped hello and the shipped account publication: the daemon's
// own protocol judge accepts each hello, whose voice is the row's, and the
// Voice group's key row offers Add key until a key is stored.
function verifyVoice(gate, serviceSource, accountsSource) {
    const hello = serviceSource.match(/^    function hello\(\) \{\n[\s\S]*?^    \}/m);
    const publishAccounts = accountsSource.match(/^    function publish\(\) \{\n[\s\S]*?^    \}/m);
    assert.ok(hello && publishAccounts);
    const manifest = judge.validateManifest(JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8")), path.dirname(file)).manifest;
    const keys = Object.fromEntries(manifest.hyprland.binds.map(bind => [bind.shortcut, bind.key]));
    try {
        for (const [label, changed, offered, want] of VOICE) {
            const settings = { ...plain(manifest.settings), ...changed };
            let wire = null;
            const root = { accountReader: { voiceKeys: offered }, shell: { settings,
                shortcut: { keys }, manifest: { hyprland: manifest.hyprland, __revision: "a".repeat(64) } },
                child: { running: true, write: text => { wire = text; } }, cause: "", lifetime: { kind: "starting" }, sessionState: null,
                feedbackSounds: false, lockObservation: () => false, broken: reason => assert.fail(label + ": the daemon refuses the hello: " + reason) };
            vm.runInNewContext("(function() { with(root) { return (" + hello[0] + ").call(root); } })()", { root, Gate: gate, Protocol: protocol,
                Quickshell: { env: name => "/fixture/" + name }, Paths: { stateDir: "/fixture/state" }, Providers: { runtimeDirectory: () => "/fixture/run" } });
            assert.equal(JSON.parse(wire).settings.voiceProvider, want, label);
        }
        assert.equal(plain(gate.readiness({ kind: "answered", causes: [] })).setup.tone, "ok", "no cause, as a fresh install with its local voice set up: ready");
        for (const [label, offered, want] of VOICE_KEY) {
            const values = {};
            const shell = { settings: { voiceAccount: "openai-1" }, status: { values, set: (key, value) => {
                assert.equal(judge.statusWrite(manifest, values, key, value).ok, true, label + ": accepted status " + key);
                values[key] = value;
                return "ok";
            } } };
            const root = { shell, modelAccess: { kind: "checking" }, voiceKeys: "unread", pending: false, completion: { kind: "exited", code: offered === null ? 1 : 0 },
                diagnostic: { kind: "collected", text: "" }, refreshed: () => {},
                output: JSON.stringify({ accounts: [], brains: [], voiceAccounts: offered ?? [], search: { found: 0, partial: "" } }) };
            vm.runInNewContext("(function() { with(root) { return (" + publishAccounts[0] + ").call(root); } })()",
                { root, Gate: gate, Words: words, Providers: { probeFailure: () => "jarvis-accounts: probe=failed" }, console: { warn: () => {} } });
            assert.deepEqual(plain({ keys: root.voiceKeys }), plain({ keys: offered ?? undefined }), label + ": the keys the reader hands the service");
            const entry = judge.statusRows(manifest, values, []).find(item => item.key === "voiceKey");
            assert.deepEqual(plain([entry.group, entry.tone, entry.action.offered, entry.action.tui]),
                ["Voice", { info: "info", ok: "success", warning: "warning" }[want[0]], want[1], want[1] ? "add-key" : ""], label + ": the Voice group's key row");
            assert.equal(typeof entry.hint === "string" && entry.hint !== "", true, label + ": the row says what the key unlocks");
        }
    } catch (error) {
        error.check = "voice-default";
        throw error;
    }
}
function verifyVoiceConsumers(gate, pageSource) {
    const accessor = pageSource.match(/function statusEntry\(key\) \{[\s\S]*?\n    \}/);
    assert.ok(accessor, "the Details accessor is present");
    const manifest = judge.validateManifest(JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8")), path.dirname(file)).manifest;
    for (const [provider, causes, expected] of [
        ["realtime", ["brain=unselected"], ["success", false]],
        ["local", ["brain=unselected", "speech=local-not-set-up"], ["warning", true]]
    ]) {
        const values = { ...plain(gate.readiness({ kind: "answered", causes })),
            localRuntime: { tone: "warning", text: "Not set up", action: true } };
        const row = { status: judge.statusRows(manifest, values, []) };
        const detailsEntry = vm.runInNewContext("(" + accessor[0] + ")", { row })("setupVoice");
        const settingsEntry = settings.setupRows([], row.status).find(item => item.entry.key === "setupVoice").entry;
        try {
            assert.equal(detailsEntry, settingsEntry);
            assert.deepEqual(plain([detailsEntry.tone, detailsEntry.action.offered]), expected);
            assert.deepEqual(plain(settings.statusView(detailsEntry, String)), plain(settings.statusView(settingsEntry, String)));
        } catch (error) {
            error.check = "setup-voice-consumer-source";
            error.provider = provider;
            throw error;
        }
    }
}

function verifyReadiness(gate) {
    for (const [label, answer, tone, todo, declared, model] of READINESS) {
        const got = plain(gate.readiness(answer));
        assert.deepEqual(Object.keys(got).sort(), ["setup", "setupHome", "setupModel", "setupVoice"], label);
        assert.deepEqual(got.setupHome, { hidden: true }, label + ": the home folder step stays off the page");
        assert.equal(got.setup.tone, tone, label + ": the summary");
        assert.equal(got.setup.action, undefined, label + ": the summary offers no step");
        for (const key of ["setupVoice", "setupModel"]) {
            const step = got[key];
            const open = todo.includes(key);
            const action = key === "setupModel" ? model ?? "key" : true;
            assert.deepEqual([step.tone, step.action, step.lines], open ? ["warning", action, undefined] : ["ok", DONE_ACTION[key], undefined], label + ": " + key);
            if (!open || declared.includes(key)) assert.equal(step.hint, undefined, label + ": " + key + " keeps its declared hint");
            else assert.equal(typeof step.hint === "string" && step.hint !== "" && !/=/.test(step.hint), true,
                label + ": a plain hint, no keyed cause on screen");
        }
    }
    const lines = BRAIN_CAUSES.map(cause => plain(gate.readiness({ kind: "answered", causes: [cause] })).setupModel.hint);
    for (const cause of ["speech=local-memory-insufficient", "speech=local-memory-unavailable"]) {
        const got = plain(gate.readiness({ kind: "answered", causes: [cause] }));
        assert.deepEqual([got.setup.tone, got.setupVoice.tone, got.setupVoice.action, got.setupModel.tone],
            ["warning", "warning", false, "ok"], "memory refuses capture without reinstall action");
        assert.equal(got.setupVoice.lines, undefined, "recovery is no state badge");
        assert.equal(typeof got.setupVoice.hint, "string");
        assert.notEqual(got.setupVoice.hint.trim(), "", "memory refusal carries guidance");
    }
    assert.equal(new Set(lines).size, BRAIN_CAUSES.length, "each brain cause says its own hint");
    for (const cause of ["speech=live-account-unselected", "speech=live-account-unreadable", "speech=live-key-required", "speech=always-local-voice"]) {
        const got = plain(gate.readiness({ kind: "answered", causes: [cause] }));
        assert.deepEqual([got.setupVoice.tone, got.setupVoice.action, typeof got.setupVoice.hint], ["warning", false, "string"],
            "Realtime voice setup never starts local model installation");
        assert.deepEqual(got.setupModel, { tone: "ok", text: "Done" });
    }
    // Before the daemon answers nothing reads ready or to do.
    const checking = plain(gate.readiness({ kind: "checking" }));
    assert.deepEqual([checking.setup.tone, checking.setup.action], ["info", undefined], "checking: setup");
    for (const key of ["setupVoice", "setupModel"])
        assert.deepEqual([checking[key].tone, checking[key].action], ["info", DONE_ACTION[key]], "checking: " + key);
    assert.equal(gate.readiness({ kind: "checking" }).setupVoice, gate.CHECKING);
    assert.equal(gate.readiness({ kind: "answered", causes: ["speech=local-loading"] }).setupVoice, gate.LOADING);
    assert.equal(gate.readiness({ kind: "answered", causes: ["speech=local-loading"] }).setup, gate.LOADING_SUMMARY);
    assert.notEqual(gate.LOADING, gate.CHECKING, "loading and initial checking have distinct values");
    for (const causes of [["speech=local-loading"], ["speech=local-loading", "brain=unselected"]]) {
        const loading = plain(gate.readiness({ kind: "answered", causes }));
        assert.deepEqual([loading.setupVoice.tone, loading.setupVoice.action], ["info", false]);
        assert.equal(loading.setup.tone, causes.length === 1 ? "info" : "warning");
        assert.equal(loading.setup.action, undefined);
        assert.deepEqual([loading.setupModel.tone, loading.setupModel.action], causes.length === 1 ? ["ok", undefined] : ["warning", "key"]);
    }
    // A stopped daemon runs no check: its steps claim none and offer none.
    const stopped = plain(gate.readiness({ kind: "stopped" }));
    assert.deepEqual(Object.keys(stopped).sort(), ["setup", "setupHome", "setupModel", "setupVoice"], "stopped");
    assert.deepEqual([stopped.setupHome, checking.setupHome], [{ hidden: true }, { hidden: true }], "no home folder step without an answer");
    // A refused home folder is the one step to do, with what to change and
    // no action of its own; the voice and the AI model stay done.
    const homeHints = HOME_CAUSES.map(cause => {
        const got = plain(gate.readiness({ kind: "answered", causes: [cause] }));
        assert.deepEqual([got.setup.tone, got.setupHome.tone, got.setupHome.action, got.setupHome.lines, got.setupVoice.tone, got.setupModel.tone],
            ["warning", "warning", undefined, undefined, "ok", "ok"], cause);
        assert.equal(typeof got.setupHome.hint === "string" && got.setupHome.hint !== "" && !/=/.test(got.setupHome.hint), true,
            cause + ": a plain hint, no keyed cause on screen");
        return got.setupHome.hint;
    });
    assert.equal(new Set(homeHints).size, HOME_CAUSES.length, "each home cause says its own hint");
    // The Copilot Memory row shows for a usable GitHub Copilot account alone.
    const account = (provider, value) => ({ provider, value });
    for (const [label, accounts, shown] of [
        ["no account", [], false], ["another app", [account("claude", "present")], false],
        ["a signed-out Copilot", [account("copilot", "signed-out")], false],
        ["a Copilot account", [account("codex", "present"), account("copilot", "present")], true]]) {
        const got = plain(gate.copilotMemory(accounts));
        assert.deepEqual([got.hidden === true, got.tone], shown ? [false, "info"] : [true, undefined], label);
        assert.equal(got.action, undefined, label + ": the user's step runs on GitHub, with no action here");
    }
    assert.equal(stopped.setup.tone, "danger", "stopped: the summary");
    assert.deepEqual([stopped.setup.lines, typeof stopped.setup.hint], [undefined, "string"], "stopped: the summary says why as its hint");
    for (const key of ["setupVoice", "setupModel"])
        assert.deepEqual([stopped[key].tone === checking[key].tone, stopped[key].action], [false, DONE_ACTION[key]], "stopped: " + key);
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
        { kind: "answered", causes: ["speech=local-memory-unavailable"] }], HOME_CAUSES.map(cause => ({ kind: "answered", causes: [cause] })));
    for (const accounts of [[], [{ provider: "copilot", value: "present" }]])
        assert.equal(judge.statusWrite(manifest, {}, "copilotMemory", plain(gate.copilotMemory(accounts))).ok, true, "the manifest judge accepts copilotMemory");
    // The row's link is words of its declared hint, to GitHub alone.
    const memory = judge.statusRows(manifest, { copilotMemory: plain(gate.copilotMemory([{ provider: "copilot", value: "present" }])) }, [])
        .find(entry => entry.key === "copilotMemory");
    assert.equal(memory.hint.includes(memory.link.text) && new URL(memory.link.url).hostname === "github.com", true);
    assert.equal(settings.statusView(memory, String).link.url, memory.link.url, "Settings draws the row's link");
    assert.equal(judge.statusRows(manifest, { copilotMemory: plain(gate.copilotMemory([])) }, []).some(entry => entry.key === "copilotMemory"), false,
        "no Copilot account, no row");
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
    verifyModelConsumers(gate, fs.readFileSync(serviceFile, "utf8"), fs.readFileSync(accountsFile, "utf8"));
    verifyVoice(gate, fs.readFileSync(serviceFile, "utf8"), fs.readFileSync(accountsFile, "utf8"));
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
const pageSource = fs.readFileSync(pageFile, "utf8");
verifyVoiceConsumers(load(file), pageSource);
console.log("test-jarvis-setup-gate: consumer=Settings,Details hint=Choose an AI model in Settings > AI model.");

// Each control removes one rule from a copy and keeps the text around it:
// [label, needle, replacement].
const CONTROLS = [
    ["the AI model hint names the Settings field", '"brain=unselected": "Choose an AI model in Settings > AI model."', '"brain=unselected": "Choose an AI model in Settings."', "Settings AI model hint"],
    ["present keys still offer Add key", 'var absent = keys !== undefined && keys.every(function (key) { return key.value === "absent"; });', 'var absent = keys !== undefined;'],
    ["a signed-in app still offers Add key", 'access.kind === "absent"', 'access.kind !== "checking"'],
    ["a signed-out cause offers Add key", '(cause === "brain=signed-out" ? "signIn" : "key")', '"key"', "a signed-out AI model: setupModel"],
    ["a signed-out cause loses Sign in beside a key", 'if (value.action !== "key") return value;', "if (value.action === undefined) return value;"],
    ["a signed-out app offers Add key", 'if (absent && access.kind === "signed-out") return', "if (false) return"],
    ["a signed-out app keeps the unselected hint", "{ hint: SIGNED_OUT_HINT, action: \"signIn\" }", "{ action: \"signIn\" }",
        "signed-out hint replaces the unselected one"],
    ["a signed-out app reads as none", 'account.signIn === true; }) ? "signed-out"', 'false; }) ? "signed-out"'],
    ["a merely found app suppresses Add key", '["signed-in", "verified", "verifying"].indexOf(account.state) !== -1', '["found", "unchecked", "signed-in", "verified", "verifying"].indexOf(account.state) !== -1'],
    ["checking account discovery offers Add key", 'access.kind === "absent"', 'access.kind !== "present"'],
    ["memory guidance is a badge", "out.setupVoice = MEMORY[cause];", "out.setupVoice = Object.assign({}, MEMORY[cause], { lines: [MEMORY[cause].hint], hint: undefined });"],
    ["optional guidance is a badge", "action: value.action === true };", 'lines: ["fixture guidance"], action: value.action === true };'],
    ["optional guidance changes with state", "action: value.action === true };", 'hint: "fixture guidance", action: value.action === true };'],
    ["memory refusal offers reinstall", 'if (Object.prototype.hasOwnProperty.call(MEMORY, cause)) {', 'if (false) {'],
    ["loading is initial checking", "out.setupVoice = LOADING;", "out.setupVoice = CHECKING;"],
    ["loading offers setup", 'if (cause === "speech=local-loading") {', 'if (false) {'],
    ["a stored key replaces the voice the user chose", 'if (settings.voiceProvider !== "auto") return settings.voiceProvider;', 'if (false) return settings.voiceProvider;'],
    ["no named key runs Realtime", ' || settings.voiceAccount === "") return "local";', ') return "local";'],
    ["a removed key keeps Realtime", "offered.some(function (key) { return key.value === settings.voiceAccount; })", "true"],
    ["a start loads the local voice beside a named key", "var stored = offered === undefined || ", "var stored = offered !== undefined && "],
    ["Always talk mode runs Realtime", 'if (settings.mode === "always" || ', "if ("],
    ["no key offers no Add key", 'text: "No key stored", action: true }', 'text: "No key stored", action: false }'],
    ["a stored key still offers Add key", 'text: "Key stored", action: false }', 'text: "Key stored", action: true }'],
    ["a failed key read offers no Add key", 'text: "Could not check", action: true }', 'text: "Could not check", action: false }'],
    ["a missing command does not withhold setup", "return missing.indexOf(command) !== -1; });", "return false; });"],
    ["the withheld step keeps its action", 'lacking.join(" and "), action: false', 'lacking.join(" and "), action: value.action'],
    ["any missing command withholds setup", "var lacking = requires.filter(", "var lacking = missing.filter("],
    ["the withheld text names every required command", 'lacking.join(" and ")', 'requires.join(" and ")'],
    ["a missing requirement offers no install", 'if (missing.indexOf(command) === -1) return { tone: "ok"', 'if (true) return { tone: "ok"'],
    ["a found requirement offers its install", 'if (missing.indexOf(command) === -1) return { tone: "ok"', 'if (false) return { tone: "ok"'],
    ["the Realtime voice offers the local install action", 'return cause.indexOf("speech=live-") !== 0 && ', 'return true && '],
    ["Always mode offers the local install action", ' && cause !== "speech=always-local-voice";', ";"],
    ["Always mode has no hint of its own", '    "speech=always-local-voice": ', '    "speech=always-local-voice-unused": '],
    ["a cause marks no step", "out[REQUIRED[step]] = hint === undefined", "void (hint === undefined)"],
    ["a cause marks the other step", 'speech: "setupVoice", brain: "setupModel" };', 'speech: "setupModel", brain: "setupVoice" };'],
    ["a home cause marks no step", 'if (REQUIRED[step] === "setupHome") {', 'if (false) {'],
    ["a home text cause marks the voice step", 'guidance: "setupHome", ', 'guidance: "setupVoice", '],
    ["the home causes share one hint", "hint: Object.prototype.hasOwnProperty.call(HOME_TODO, cause) ? HOME_TODO[cause] : HOME_STEP_TODO };", "hint: HOME_STEP_TODO };"],
    ["the home folder step always shows", "var HOME_READY = { hidden: true };", 'var HOME_READY = { tone: "ok", text: "Done" };'],
    ["the home folder step offers an action", 'out.setupHome = { tone: "warning", text: "To do",', 'out.setupHome = { tone: "warning", text: "To do", action: true,'],
    ["any account shows Copilot Memory", 'account.provider === "copilot" && ', ""],
    ["a signed-out Copilot shows Copilot Memory", ' && account.value === "present"; })', "; })"],
    ["a Pi older than its floor takes the step's hint", '    "brain=pi-update": ', '    "brain=pi-update-removed": '],
    ["the brain causes share one hint", "var hint = Object.prototype.hasOwnProperty.call(TODO, cause) ? TODO[cause] : STEP_TODO[step];", "var hint = STEP_TODO[step];"],
    ["an unknown cause has no hint", "var hint = Object.prototype.hasOwnProperty.call(TODO, cause) ? TODO[cause] : STEP_TODO[step];", "var hint = TODO[cause];"],
    ["local voice repeats its action as its hint", "var STEP_TODO = { brain:", 'var STEP_TODO = { speech: "fixture repeat", brain:'],
    ["a step to do draws its hint as a line", ': { tone: "warning", text: "To do", hint: hint, action: action };', ': { tone: "warning", text: "To do", lines: [hint], action: action };', "nothing set up: setupModel"],
    ["a stopped summary draws its reason as a line", 'hint: "Jarvis stopped after a problem. Turn Jarvis off and on again." }', 'lines: ["Jarvis stopped after a problem. Turn Jarvis off and on again."] }'],
    ["causes leave the summary ready", 'setup: answer.causes.length === 0 ? { tone: "ok", text: "Ready" }', 'setup: true ? { tone: "ok", text: "Ready" }'],
    ["checking reads done", 'return { setup: CHECKING_SUMMARY, setupHome: HOME_READY, setupVoice: CHECKING, setupModel: noAction(CHECKING) };', 'return { setup: CHECKING_SUMMARY, setupHome: HOME_READY, setupVoice: DONE, setupModel: noAction(DONE) };'],
    ["an optional step reads done when not ok", 'if (value.tone === "ok") return DONE;', "if (true) return DONE;"],
    ["an optional step drops its action", "action: value.action === true };", "action: false };"],
    ["the checking summary offers a step", "return { setup: CHECKING_SUMMARY,", "return { setup: CHECKING,"],
    ["a stopped daemon's steps read checking", "setupVoice: UNCHECKED, setupModel: noAction(UNCHECKED) };", "setupVoice: CHECKING, setupModel: noAction(CHECKING) };"],
    ["a cause naming no step is taken", 'if (!Object.prototype.hasOwnProperty.call(REQUIRED, step)) throw new Error("jarvis-setup: cause=" + cause + " names no step");', ""],
    ["a required step reads as optional", 'if (!Object.prototype.hasOwnProperty.call(OPTIONAL, key)) throw new Error("jarvis-setup: step=" + key + " is not optional");', ""]
];

const source = fs.readFileSync(file, "utf8");
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "jarvis-setup-gate-control-"));
try {
    const serviceSource = fs.readFileSync(serviceFile, "utf8");
    const accountsSource = fs.readFileSync(accountsFile, "utf8");
    for (const [target, original, needle, replacement] of [
        ["Service.qml", serviceSource, 'values.setupModel = Gate.modelStep(values.setupModel, shell.status.values["keys"], accountReader.modelAccess);', 'values.setupModel = values.setupModel;'],
        ["Accounts.qml", accountsSource, 'modelAccess = Gate.accountAccess(value.accounts);', 'modelAccess = { kind: "absent" };']
    ]) {
        assert.equal(original.split(needle).length, 2);
        const changed = original.replace(needle, replacement);
        assert.notEqual(changed, original);
        const copy = path.join(temp, target);
        fs.writeFileSync(copy, changed);
        let failure = null;
        try { verifyModelConsumers(load(file), target === "Service.qml" ? fs.readFileSync(copy, "utf8") : serviceSource,
            target === "Accounts.qml" ? fs.readFileSync(copy, "utf8") : accountsSource); }
        catch (error) { failure = error; }
        assert.ok(failure instanceof assert.AssertionError);
        assert.equal(failure.check, "setup-model-action");
        console.log("test-jarvis-setup-gate: control=" + target + " check=setup-model-action rejected=true");
    }
    for (const [target, original, needle, replacement] of [
        ["Service.qml", serviceSource, "voiceProvider: Gate.voiceProvider(shell.settings, accountReader.voiceKeys) }),", "voiceProvider: shell.settings.voiceProvider }),"],
        ["Accounts.qml", accountsSource, "voiceKeys = value.voiceAccounts;", "voiceKeys = [];"],
        ["Accounts.qml", accountsSource, "voiceKeys = undefined;", "voiceKeys = [];"],
        ["Accounts.qml", accountsSource, "Gate.voiceKey(value.voiceAccounts)", "Gate.voiceKey([])"],
        ["Accounts.qml", accountsSource, "Gate.voiceKey(null)", "Gate.voiceKey([])"]
    ]) {
        assert.equal(original.split(needle).length, 2);
        let failure = null;
        try { verifyVoice(load(file), target === "Service.qml" ? original.replace(needle, replacement) : serviceSource,
            target === "Accounts.qml" ? original.replace(needle, replacement) : accountsSource); }
        catch (error) { failure = error; }
        assert.ok(failure instanceof assert.AssertionError);
        assert.equal(failure.check, "voice-default");
        console.log("test-jarvis-setup-gate: control=" + target + " check=voice-default rejected=true");
    }
    const needle = "row.status.find(entry => entry.key === key)";
    assert.equal(pageSource.split(needle).length, 2);
    const secondSource = pageSource.replace(needle, 'row.status.find(entry => entry.key === (key === "setupVoice" ? "localRuntime" : key))');
    assert.notEqual(secondSource, pageSource);
    const pageCopy = path.join(temp, "PluginPage.qml");
    fs.writeFileSync(pageCopy, secondSource);
    let failure = null;
    try { verifyVoiceConsumers(load(file), fs.readFileSync(pageCopy, "utf8")); }
    catch (error) { failure = error; }
    assert.ok(failure instanceof assert.AssertionError);
    assert.equal(failure.check, "setup-voice-consumer-source");
    assert.equal(failure.provider, "realtime");
    console.log("test-jarvis-setup-gate: control=second-voice-source check=setup-voice-consumer-source provider=realtime rejected=true");
    for (const [label, needle, replacement, assertion] of CONTROLS) {
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
        if (assertion !== undefined) assert.equal(failure.message.includes(assertion), true, label + ": the intended assertion fails");
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
console.log(`test-jarvis-setup-gate: ok cases=${SETUP.length + REQUIREMENT.length + READINESS.length + MODEL.length + VOICE.length + VOICE_KEY.length} controls=${CONTROLS.length + 8}`);
