#!/usr/bin/env node
// Table-driven checks for vgs.polkit's pure decisions, PolkitModel.js: the
// title, prompt, identity and note the prompt draws from the agent's
// authentication flow, when its field and accept action answer, which
// flows closing the prompt cancels, which process is another agent, what a
// check answered, and the agent status the service publishes, which the
// core's own judge must admit under the plugin's manifest. Expected values
// are written by hand. Controls edit a copy of
// the module, one rule each, and require this suite to fail.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const plugin = path.join(__dirname, "..", "shell", "plugins", "vgs.polkit");
const file = path.join(plugin, "PolkitModel.js");
const logic = load(path.join(__dirname, "..", "shell", "Core", "PluginLogic.js"));
const judged = logic.validateManifest(JSON.parse(fs.readFileSync(path.join(plugin, "manifest.json"), "utf8")), plugin);
assert.equal(judged.ok, true, "the plugin's manifest is valid");
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), JSON.parse(JSON.stringify(want)), message || "");

// A flow as the agent holds one while PAM waits for a password, with
// FIELDS over it.
const alice = { string: "alice", displayName: "Alice Liddell", isGroup: false };
const wheel = { string: "wheel", displayName: "wheel", isGroup: true };
const flow = fields => Object.assign({
    message: "Authentication is required to change the system time.",
    actionId: "org.freedesktop.timedate1.set-time",
    inputPrompt: "Password: ",
    isResponseRequired: true,
    responseVisible: false,
    supplementaryMessage: "",
    supplementaryIsError: false,
    failed: false,
    isCompleted: false,
    isCancelled: false,
    identities: [alice],
    selectedIdentity: alice
}, fields);

function verify(model) {
    const TITLES = [
        ["pkexec names its program", "Authentication is needed to run `/usr/bin/true' as the super user", "Allow /usr/bin/true to run"],
        ["pkexec with straight quotes", "Authentication is required to run '/usr/bin/id' as the user bob", "Allow /usr/bin/id to run"],
        ["another action keeps the default", "Authentication is required to change the system time.", "Administrator access"],
        ["no message", "", "Administrator access"]
    ];
    for (const [label, message, want] of TITLES) assert.equal(model.titleOf(message), want, label);

    const PROMPTS = [["Password: ", "Password"], ["PIN:", "PIN"], ["", "Password"], ["  :  ", "Password"], ["Token code", "Token code"]];
    for (const [text, want] of PROMPTS) assert.equal(model.promptOf(text), want, JSON.stringify(text));

    const IDENTITIES = [
        ["a user's display name", { string: "alice", displayName: "Alice Liddell", isGroup: false }, "Alice Liddell"],
        ["a user with no display name", { string: "alice", displayName: "", isGroup: false }, "alice"],
        ["a group", { string: "wheel", displayName: "wheel", isGroup: true }, "Group wheel"],
        ["no identity", null, ""]
    ];
    for (const [label, identity, want] of IDENTITIES) assert.equal(model.identityOf(identity), want, label);

    assert.equal(model.viewOf(null), null, "no flow draws nothing");
    same(model.viewOf(flow({})), {
        title: "Administrator access", message: "Authentication is required to change the system time.",
        action: "org.freedesktop.timedate1.set-time", identity: "Alice Liddell", identities: ["Alice Liddell"], identityIndex: 0, prompt: "Password", echo: false, inputEnabled: true, waiting: false, note: null
    }, "a flow waiting for the password");
    const VIEWS = [
        ["a submitted response waits", { isResponseRequired: false, inputPrompt: "" }, { inputEnabled: false, waiting: true }],
        ["several identities are offered in order, the selected one found", { identities: [wheel, alice], selectedIdentity: alice }, { identities: ["Group wheel", "Alice Liddell"], identityIndex: 1, identity: "Alice Liddell" }],
        ["a selected identity outside the list is found nowhere", { identities: [wheel], selectedIdentity: alice }, { identityIndex: -1 }],
        ["a flow with no identity list offers none", { identities: undefined }, { identities: [], identityIndex: -1 }],
        ["a flow with no action id names none", { actionId: undefined }, { action: "" }],
        ["a visible response echoes", { responseVisible: true }, { echo: true }],
        ["PAM's error shows in danger", { supplementaryMessage: "Account locked", supplementaryIsError: true }, { note: { text: "Account locked", tone: "danger" } }],
        ["PAM's information shows as a hint", { supplementaryMessage: "Touch the key" }, { note: { text: "Touch the key", tone: "info" } }],
        ["a failed attempt says so", { failed: true }, { note: { text: "The password was not accepted. Try again.", tone: "danger" } }],
        ["PAM's own message wins over the failed note", { failed: true, supplementaryMessage: "2 attempts left", supplementaryIsError: true }, { note: { text: "2 attempts left", tone: "danger" } }]
    ];
    for (const [label, fields, want] of VIEWS) {
        const view = model.viewOf(flow(fields));
        for (const key of Object.keys(want)) same(view[key], want[key], `${label}: ${key}`);
    }

    const found = (...agents) => ({ ok: true, agents: agents, stopped: 0 });
    const acme = { name: "acme-polkit", removable: true }, shared = { name: "shared-polkit", removable: false };
    const ok = model.agentStatus(true, null, false), warning = model.agentStatus(false, found(), false);
    const CHANGES = [
        ["the first state publishes", null, warning, true],
        ["the same state again does not", warning, model.agentStatus(false, found(), false), false],
        ["a new state publishes", warning, ok, true],
        ["another agent's name publishes", model.agentStatus(false, found(acme), false), model.agentStatus(false, found(shared), false), true],
        ["a second agent's line publishes", model.agentStatus(false, found(acme), false), model.agentStatus(false, found(acme, { name: "other-polkit", removable: true }), false), true],
        ["no state publishes nothing", ok, null, false]
    ];
    for (const [label, previous, next, want] of CHANGES) assert.equal(model.statusChanged(previous, next), want, label);

    const CANCELLABLE = [["a live flow", flow({}), true], ["no flow", null, false], ["a completed flow", flow({ isCompleted: true }), false], ["a cancelled flow", flow({ isCancelled: true }), false]];
    for (const [label, value, want] of CANCELLABLE) assert.equal(model.cancellable(value), want, label);

    // Process names as /proc/<pid>/comm holds them, cut to 15 bytes: each
    // agent's is its program's file name in its Arch package, read on
    // 2026-10-04 from archlinux.org's file lists of hyprpolkitagent,
    // polkit-gnome, polkit-kde-agent, lxqt-policykit, lxsession and
    // mate-polkit.
    const NAMES = [
        ["hyprpolkitagent", true], ["polkit-gnome-au", true], ["polkit-kde-auth", true], ["lxqt-policykit-", true], ["lxpolkit", true], ["polkit-mate-aut", true],
        ["polkitd", false], ["polkit-agent-he", false], ["quickshell", false], ["pkexec", false], ["", false], [undefined, false]
    ];
    for (const [comm, want] of NAMES) assert.equal(model.otherAgent(comm), want, `otherAgent ${JSON.stringify(comm)}`);

    const AGENT_NAMES = [
        ["the package", "polkit-gnome", "polkit-gnome-authentication-agent-1", "polkit-gnome"],
        ["the program without a package", null, "polkit-gnome-authentication-agent-1", "polkit-gnome-authentication-agent-1"],
        ["a name with a space or a control character", null, "my agent\n", "my?agent?"],
        ["a long name is cut", null, "p".repeat(80), "p".repeat(64)],
        ["an empty name", null, "", "?"]
    ];
    for (const [label, pkg, program, want] of AGENT_NAMES) assert.equal(model.agentName(pkg, program), want, `agentName: ${label}`);

    const CHECKS = [
        ["a check's answer", 0, '{"agents":[{"name":"acme-polkit","removable":true}],"stopped":1}\n', { ok: true, agents: [acme], stopped: 1 }],
        ["no other agent", 0, '{"agents":[],"stopped":0}\n', found()],
        ["a failed run", 1, '{"agents":[],"stopped":0}\n', { ok: false }],
        ["a run that did not start", null, "", { ok: false }],
        ["no output", 0, "", { ok: false }],
        ["an answer that is no object", 0, "null\n", { ok: false }],
        ["agents that are no list", 0, '{"agents":{},"stopped":0}\n', { ok: false }],
        ["no count of stopped agents", 0, '{"agents":[]}\n', { ok: false }],
        ["an agent without a name", 0, '{"agents":[{"removable":true}],"stopped":0}\n', { ok: false }],
        ["an agent whose removable is no boolean", 0, '{"agents":[{"name":"a","removable":"yes"}],"stopped":0}\n', { ok: false }]
    ];
    for (const [label, code, stdout, want] of CHECKS) same(model.readCheck(code, stdout), want, `readCheck: ${label}`);

    const line = name => "Another app is showing password prompts: " + name + ".";
    const many = Array.from({ length: 40 }, (_, n) => ({ name: "agent-" + n, removable: true }));
    const STATES = [
        ["a registered agent", true, null, false, { tone: "ok", text: "Ready to show password prompts" }],
        ["a registered agent whatever the last check held", true, found(shared), true, { tone: "ok", text: "Ready to show password prompts" }],
        ["an unregistered agent before its check", false, null, true, null],
        ["another agent the package manager removes", false, found(acme), false, { tone: "warning", text: line("acme-polkit"), action: "uninstall" }],
        ["another agent whose package another requires", false, found(shared), false, { tone: "warning", text: line("shared-polkit"), action: "stop" }],
        ["two agents, one line each, one of them required", false, found(acme, shared), false, { tone: "warning", text: line("acme-polkit"), action: "stop", lines: [line("shared-polkit")] }],
        ["two removable agents", false, found(acme, { name: "other-polkit", removable: true }), false, { tone: "warning", text: line("acme-polkit"), action: "uninstall", lines: [line("other-polkit")] }],
        ["another agent while polkit is missing too", false, found(acme), true, { tone: "warning", text: line("acme-polkit"), action: "uninstall" }],
        ["no other agent and no polkit", false, found(), true, { tone: "warning", text: "Polkit is not installed.", action: "install" }],
        ["no other agent with polkit", false, found(), false, { tone: "warning", text: "Password prompts are unavailable. No other app is showing them." }],
        ["a check that gave no answer", false, { ok: false }, true, { tone: "warning", text: "Password prompts are unavailable. VGS could not look for another app." }]
    ];
    for (const [label, registered, check, missing, want] of STATES) {
        const state = model.agentStatus(registered, check, missing);
        same(state, want, `agentStatus: ${label}`);
        if (state !== null) assert.equal(logic.statusWrite(judged.manifest, {}, "agent", state).ok, true, `${label}: the core admits the value under the plugin's manifest`);
    }
    const crowded = model.agentStatus(false, found(...many), false);
    assert.equal(crowded.lines.length, 32, "a crowd of agents keeps the lines a state value may carry");
    assert.equal(logic.statusWrite(judged.manifest, {}, "agent", crowded).ok, true, "the core admits the crowded value");
    for (const value of STATES.map(row => row[4]).filter(value => value !== null)) assert.equal(/may be/.test(value.text), false, "no state guesses");

    const tuiState = (uninstall, stop) => ({ uninstall: { running: false, code: 0, endedAt: uninstall }, stop: { running: false, code: 0, endedAt: stop } });
    assert.equal(model.stepEnds(tuiState(null, null)), model.stepEnds(tuiState(null, null)), "stepEnds: no run, no change");
    assert.notEqual(model.stepEnds(tuiState(5, null)), model.stepEnds(tuiState(null, null)), "stepEnds: an ended uninstall changes it");
    assert.notEqual(model.stepEnds(tuiState(5, 7)), model.stepEnds(tuiState(5, 6)), "stepEnds: an ended stop changes it");
}

verify(load(file));

const CONTROLS = [
    ["the pkexec program names the title", 'return match ? "Allow " + match[1] + " to run" : DEFAULT_TITLE;', "return DEFAULT_TITLE;"],
    ["the prompt drops its colon", ".replace(/[\\s:]+$/, \"\")", ".replace(/$^/, \"\")"],
    ["a group reads as a group", "if (identity.isGroup === true) return", "if (false) return"],
    ["a display name wins over the login name", 'return display !== "" ? display : name;', "return name;"],
    ["PAM's error message takes the danger tone", 'flow.supplementaryIsError === true ? "danger" : "info"', '"info"'],
    ["a failed attempt shows a note", "if (flow.failed === true) return", "if (false) return"],
    ["the field waits while PAM works", "inputEnabled: required,", "inputEnabled: true,"],
    ["the echo follows responseVisible", "echo: flow.responseVisible === true,", "echo: false,"],
    ["no flow draws nothing", "if (flow === null || flow === undefined) return null;", "if (flow === undefined) return null;"],
    ["a cancelled flow is not cancelled again", " && flow.isCancelled !== true", ""],
    ["a completed flow is not cancelled", " && flow.isCompleted !== true", ""],
    ["the action id is shown", "action: String(flow.actionId || \"\"),", "action: \"\","],
    ["every identity is offered", "for (var i = 0; i < list.length; i++) out.push(identityOf(list[i]));", "if (list.length > 0) out.push(identityOf(list[0]));"],
    ["the selected identity is found by its object", "if (list[i] === flow.selectedIdentity) return i;", "if (i === 0) return i;"],
    ["an unchanged state is not published again", "return previous === null || JSON.stringify(previous) !== JSON.stringify(next);", "return true;"],
    ["a state's further line publishes", "return previous === null || JSON.stringify(previous) !== JSON.stringify(next);", "return previous === null || previous.tone !== next.tone || previous.text !== next.text;"],
    ["polkitd is no agent", 'var NOT_AGENTS = ["polkitd", "polkit-agent-he"];', 'var NOT_AGENTS = ["polkit-agent-he"];'],
    ["the helper is no agent", 'var NOT_AGENTS = ["polkitd", "polkit-agent-he"];', 'var NOT_AGENTS = ["polkitd"];'],
    ["an agent named policykit is one", "var AGENT_NAME = /polkit|policykit/i;", "var AGENT_NAME = /polkit/i;"],
    ["a name is one printable word", '.replace(/[^!-~]/g, "?")', ""],
    ["a name is cut", ".slice(0, 64);", ";"],
    ["a failed check is no answer", "if (code !== 0) return { ok: false };", ""],
    ["a check's agents are a list", "!Array.isArray(answer.agents) || ", ""],
    ["a check's agent says whether it is removable", ' || typeof agent.removable !== "boolean"', ""],
    ["a check counts the agents it ended", ' || typeof answer.stopped !== "number"', ""],
    ["a registered agent is ready whatever the check", 'if (registered === true) return { tone: "ok", text: READY };\n', ""],
    ["an unchecked session says nothing", "    if (check === null) return null;\n", ""],
    ["a failed check is not read as no agent", "    if (!check.ok) return", "    if (false) return"],
    ["one required agent turns Uninstall into Stop", 'check.agents.every(function (agent) { return agent.removable; }) ? "uninstall" : "stop"', 'check.agents.some(function (agent) { return agent.removable; }) ? "uninstall" : "stop"'],
    ["each agent has its line", "if (lines.length > 1) value.lines = lines.slice(1);", ""],
    ["the lines keep the status ceiling", "check.agents.slice(0, LINES_MAX + 1)", "check.agents"],
    ["another agent comes before a missing polkit", "    if (check.agents.length > 0) {", "    if (check.agents.length > 0 && polkitMissing !== true) {"],
    ["a missing polkit offers Install", 'if (polkitMissing === true) return { tone: "warning", text: "Polkit is not installed.", action: "install" };', ""],
    ["a stop's end is a step's end", 'return ["uninstall", "stop"].map(', 'return ["uninstall"].map('],
    ["no state is never published", "    if (next === null) return false;\n", ""],
    ["an unregistered agent warns", 'if (registered === true) return { tone: "ok"', 'if (true) return { tone: "ok"']
];
const scratch = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "test-polkit-model-")));
try {
    const source = fs.readFileSync(file, "utf8");
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length - 1, 1, `control pattern occurs once: ${label}`);
        const mutant = path.join(scratch, "PolkitModel.js");
        fs.writeFileSync(mutant, source.replace(needle, replacement));
        let red = false;
        try { verify(load(mutant)); } catch (e) { red = true; }
        assert.equal(red, true, `control passed the suite: ${label}`);
    }
} finally {
    fs.rmSync(scratch, { recursive: true, force: true });
}

console.log(`test-polkit-model: ok controls=${CONTROLS.length}`);
