#!/usr/bin/env node
// Table-driven checks for vgs.bluetooth's pure decisions
// (shell/plugins/vgs.bluetooth/BluetoothLogic.js): the rfkill reading, the
// power view and its lines, the power operation's state machine, the
// discovery debt, the pairing steps, the pairing dialog's prompts, the
// device rows and the bar icon. A rename's byte count is qs.Commons'
// SettingValues.utf8Bytes, loaded beside it as the shell does. Each control
// edits a copy of the library and requires this suite to fail with the
// assertion its rule names; the discovery controls include a plain lease
// counter, which leaks a start BlueZ confirms after the last lease ended.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.bluetooth", "BluetoothLogic.js");
const utf8Bytes = load(path.join(__dirname, "..", "shell", "Commons", "SettingValues.js")).utf8Bytes;
const scratch = path.join(__dirname, "..", "tmp", "test-bluetooth-logic-" + process.pid);
const plain = value => JSON.parse(JSON.stringify(value));
const same = (got, want, message) => assert.deepEqual(plain(got), plain(want), message);

function rfkillJson(radios) {
    return JSON.stringify({ rfkilldevices: radios.map((r, i) => ({ id: i, type: r[0], device: "x" + i, soft: r[1], hard: r[2] })) });
}

function verifyRfkill(logic) {
    const rows = [
        ["an unblocked radio", 0, rfkillJson([["bluetooth", "unblocked", "unblocked"]]), { state: "read", radios: 1, soft: false, hard: false }],
        ["a soft block", 0, rfkillJson([["bluetooth", "blocked", "unblocked"]]), { state: "read", radios: 1, soft: true, hard: false }],
        ["a hard block", 0, rfkillJson([["bluetooth", "unblocked", "blocked"]]), { state: "read", radios: 1, soft: false, hard: true }],
        ["a block on any of two radios", 0, rfkillJson([["bluetooth", "blocked", "blocked"], ["bluetooth", "unblocked", "unblocked"]]), { state: "read", radios: 2, soft: true, hard: true }],
        ["another radio type is not Bluetooth", 0, rfkillJson([["wlan", "blocked", "blocked"], ["bluetooth", "unblocked", "unblocked"]]), { state: "read", radios: 1, soft: false, hard: false }],
        ["no Bluetooth radio", 0, rfkillJson([["wlan", "unblocked", "unblocked"]]), { state: "read", radios: 0, soft: false, hard: false }],
        ["a failed run", 1, "", { state: "failed", reason: "exit=1" }],
        ["a failed start", -1, "", { state: "failed", reason: "exit=-1" }],
        ["output that is no JSON", 0, "ID TYPE", { state: "failed", reason: "unparsable" }],
        ["JSON with no device list", 0, "{}", { state: "failed", reason: "shape" }],
        ["a block value rfkill never prints", 0, rfkillJson([["bluetooth", "yes", "unblocked"]]), { state: "failed", reason: "shape" }],
    ];
    for (const [label, code, stdout, want] of rows) same(logic.rfkillReading(code, stdout), want, "rfkill: " + label);
}

const READ = (soft, hard) => ({ state: "read", radios: 1, soft, hard });
const IDLE = { phase: "idle", want: "", fallback: false, reason: "" };
const op = (phase, want, fallback, reason) => ({ phase, want, fallback, reason });

function powerInput(changes) {
    return Object.assign({ rfkillMissing: false, rfkill: READ(false, false), adapters: 1, powered: true, op: IDLE, step: "ready" }, changes);
}

function verifyView(logic) {
    const rows = [
        ["unblocked and powered reads on", {}, "on", true, true],
        ["a soft block reads off though BlueZ has not caught up", { rfkill: READ(true, false) }, "off", false, true],
        ["unblocked and unpowered reads off", { powered: false }, "off", false, true],
        ["a hard block wins and offers nothing", { rfkill: READ(true, true), powered: false }, "hard-blocked", false, false],
        ["a hard block wins over a missing adapter", { rfkill: READ(false, true), adapters: 0 }, "hard-blocked", false, false],
        ["no adapter with the service step needed", { adapters: 0, powered: false, step: "needed" }, "service-needed", false, false],
        ["no adapter on NixOS", { adapters: 0, powered: false, step: "nixos" }, "service-needed", false, false],
        ["no adapter with the service running", { adapters: 0, powered: false, step: "ready" }, "no-adapter", false, false],
        ["no adapter with no unit", { adapters: 0, powered: false, step: "absent" }, "no-adapter", false, false],
        ["rfkill missing wins", { rfkillMissing: true, rfkill: { state: "unread" } }, "rfkill-missing", false, false],
        ["an unblock running", { op: op("unblocking", "on", false, ""), powered: false }, "turning-on", true, false],
        ["a wait running", { op: op("waiting", "on", true, ""), powered: false }, "turning-on", true, false],
        ["a block running", { op: op("blocking", "off", false, "") }, "turning-off", false, false],
        ["a failed On", { op: op("failed", "on", false, "no-power"), powered: false }, "failed", false, true],
        ["a failed Off over a powered adapter reads the power", { op: op("failed", "off", false, "rfkill-failed"), powered: true }, "failed", true, true],
        ["an unreadable switch", { rfkill: { state: "failed", reason: "exit=1" } }, "rfkill-failed", true, true],
        ["an unread switch and a powered adapter", { rfkill: { state: "unread" } }, "on", true, true],
    ];
    for (const [label, changes, key, on, canToggle] of rows) {
        const view = logic.powerView(powerInput(changes));
        same([view.key, view.on, view.canToggle], [key, on, canToggle], "view: " + label);
        assert.ok(typeof view.text === "string" && view.text.length > 0, "view: " + label + " tells the user");
    }
    assert.equal(logic.powerView(powerInput({ adapters: 0, powered: false, step: "needed" })).action, true, "the service step is offered while needed");
    assert.equal(logic.powerView(powerInput({ adapters: 0, powered: false, step: "ready" })).action, false, "the service step is not offered while ready");
    assert.throws(() => logic.powerView(powerInput({ op: op("dancing", "", false, "") })), /power phase/, "an unknown phase is refused");

    // The lines under the switch: a hint for a state that explains itself,
    // an error for a failure or a refused press, none for on and off.
    const failedView = logic.powerView(powerInput({ op: op("failed", "on", false, "no-power"), powered: false }));
    const lines = [
        ["on shows no line", logic.powerView(powerInput({})), "", { hint: "", error: "" }],
        ["a hard block is a hint", logic.powerView(powerInput({ rfkill: READ(false, true) })), "", { hint: "Turned off by a hardware switch", error: "" }],
        ["a failure is an error", failedView, "", { hint: "", error: failedView.text }],
        ["a refused press is an error", logic.powerView(powerInput({})), "Refused.", { hint: "", error: "Refused." }],
        ["before a view, only the press", null, "Refused.", { hint: "", error: "Refused." }],
    ];
    for (const [label, current, problem, want] of lines) same(logic.powerLine(current, problem), want, "powerLine: " + label);
    same([logic.publishedPower({}), logic.publishedPower(null), logic.publishedPower({ bluetooth: { power: { key: "on" } } })], [null, null, { key: "on" }], "the published power");
}

// Run a power scenario: each step is [kind, arg, seen]; answers the trail of
// [phase, effects(, reply)] after each step and the last op.
function powerTrail(logic, start, steps) {
    let current = start;
    const trail = [];
    for (const [kind, arg, seen] of steps) {
        let result;
        if (kind === "request") {
            const view = logic.powerView(powerInput({ op: current, powered: seen.powered, rfkill: seen.rfkill }));
            result = logic.powerRequest(current, arg, view);
            trail.push([result.op.phase, result.effects, result.reply]);
        } else {
            result = logic.powerEvent(current, arg, seen);
            trail.push([result.op.phase, result.effects]);
        }
        current = result.op;
    }
    return { op: current, trail };
}

function verifyPower(logic) {
    const wait = logic.POWER_WAIT_MS;
    assert.equal(wait, 2000, "the wait is two seconds");
    const SOFT = { powered: false, rfkill: READ(true, false) };
    const DOWN = { powered: false, rfkill: READ(false, false) };
    const UP = { powered: true, rfkill: READ(false, false) };

    let run = powerTrail(logic, logic.powerIdle(), [
        ["request", "on", SOFT],
        ["event", { type: "rfkill-exit", code: 0 }, DOWN],
        ["event", { type: "observed" }, UP],
    ]);
    same(run.trail, [
        ["unblocking", [{ type: "run", verb: "unblock" }], "ok"],
        ["waiting", [{ type: "read" }, { type: "arm", ms: wait }]],
        ["idle", [{ type: "disarm" }]],
    ], "on unblocks and waits for confirmed power");

    run = powerTrail(logic, logic.powerIdle(), [
        ["request", "on", SOFT],
        ["event", { type: "rfkill-exit", code: 0 }, DOWN],
        ["event", { type: "deadline" }, DOWN],
        ["event", { type: "observed" }, UP],
    ]);
    same(run.trail.map(t => [t[0], t[1]]), [
        ["unblocking", [{ type: "run", verb: "unblock" }]],
        ["waiting", [{ type: "read" }, { type: "arm", ms: wait }]],
        ["waiting", [{ type: "enable" }, { type: "arm", ms: wait }]],
        ["idle", [{ type: "disarm" }]],
    ], "on falls back to setting Powered when the auto power-on does not come");

    run = powerTrail(logic, logic.powerIdle(), [
        ["request", "on", SOFT],
        ["event", { type: "rfkill-exit", code: 0 }, DOWN],
        ["event", { type: "deadline" }, DOWN],
        ["event", { type: "deadline" }, DOWN],
    ]);
    same([run.op, run.trail[3][1]], [op("failed", "on", false, "no-power"), [{ type: "read" }]], "on fails after the fallback's wait");
    // A failure lasts until what was asked for is observed.
    same(logic.powerEvent(run.op, { type: "observed" }, DOWN), { op: run.op, effects: [] }, "a failed On stays while nothing is powered");
    same(logic.powerEvent(run.op, { type: "observed" }, UP), { op: logic.powerIdle(), effects: [] }, "an adapter that powers up late clears the failed On");
    const failedOff = op("failed", "off", false, "rfkill-failed");
    same(logic.powerEvent(failedOff, { type: "observed" }, UP), { op: failedOff, effects: [] }, "a failed Off stays while rfkill reads no block");
    same(logic.powerEvent(failedOff, { type: "observed" }, SOFT), { op: logic.powerIdle(), effects: [] }, "a block read later clears the failed Off");

    run = powerTrail(logic, logic.powerIdle(), [["request", "on", SOFT], ["event", { type: "rfkill-exit", code: 0 }, UP]]);
    same(run.trail[1], ["idle", [{ type: "read" }]], "a power that came before the exit ends the wait at once");
    run = powerTrail(logic, logic.powerIdle(), [["request", "on", SOFT], ["event", { type: "rfkill-exit", code: 1 }, DOWN]]);
    same(run.op, op("failed", "on", false, "rfkill-failed"), "a failed unblock fails");
    run = powerTrail(logic, logic.powerIdle(), [["request", "off", UP], ["event", { type: "rfkill-exit", code: 0 }, SOFT]]);
    same(run.trail, [["blocking", [{ type: "run", verb: "block" }], "ok"], ["idle", [{ type: "read" }]]], "off writes the soft block");
    run = powerTrail(logic, logic.powerIdle(), [["request", "off", UP], ["event", { type: "rfkill-exit", code: 2 }, UP]]);
    same(run.op, failedOff, "a failed block fails Off");

    // A failed operation lets the user try again, either way.
    const failedOn = op("failed", "on", false, "no-power");
    same(logic.powerRequest(failedOn, "on", logic.powerView(powerInput({ op: failedOn, powered: false }))).effects, [{ type: "run", verb: "unblock" }], "on again after a failure");
    same(logic.powerRequest(failedOn, "off", logic.powerView(powerInput({ op: failedOn, powered: false }))).effects, [{ type: "run", verb: "block" }], "off after a failure blocks");

    same(logic.powerRequest(IDLE, "on", logic.powerView(powerInput({}))), { op: IDLE, effects: [], reply: "ok" }, "on while on writes nothing");
    same(logic.powerRequest(IDLE, "off", logic.powerView(powerInput({ rfkill: READ(true, false), powered: false }))), { op: IDLE, effects: [], reply: "ok" }, "off while off writes nothing");
    const refusals = [
        ["a hard block", powerInput({ rfkill: READ(false, true) }), "on", "refused: power=on reason=hard-blocked"],
        ["a missing rfkill", powerInput({ rfkillMissing: true }), "off", "refused: power=off reason=rfkill-missing"],
        ["a running operation", powerInput({ op: op("blocking", "off", false, "") }), "on", "refused: power=on reason=turning-off"],
        ["no adapter", powerInput({ adapters: 0, step: "needed" }), "on", "refused: power=on reason=service-needed"],
        ["a word other than on or off", powerInput({}), "toggle", "refused: power=\"toggle\" want=on|off"],
    ];
    for (const [label, input, want, reply] of refusals) {
        const result = logic.powerRequest(input.op, want, logic.powerView(input));
        same([result.reply, result.effects], [reply, []], "power refuses " + label);
    }
    same(logic.powerEvent(IDLE, { type: "deadline" }, DOWN), { op: IDLE, effects: [] }, "a stale deadline changes nothing");
    same(logic.powerEvent(IDLE, { type: "observed" }, UP), { op: IDLE, effects: [] }, "an observation with no operation changes nothing");
    assert.throws(() => logic.powerEvent(IDLE, { type: "rfkill-exit", code: 0 }, UP), /no rfkill run/, "an exit with no run is an invariant breach");
    assert.throws(() => logic.powerEvent(IDLE, { type: "nap" }, UP), /power event/, "an unknown event is refused");
}

// Run a discovery scenario: each step is [verb, arg, powered, confirmed];
// answers the final state, each step's effects and the lease ids.
function discoveryTrail(logic, label, steps) {
    let state = logic.discoveryIdle();
    const effects = [];
    const ids = [];
    for (const [verb, arg, powered, confirmed] of steps) {
        const ctx = { powered, confirmed };
        let result;
        switch (verb) {
        case "begin": result = logic.discoveryBegin(state, ctx); ids.push(result.id); break;
        case "end": result = logic.discoveryEnd(state, arg, ctx); break;
        case "tick":
            assert.equal(logic.discoveryTickWanted(state, ctx), arg, label + ": the tick runs as wanted before step " + effects.length);
            result = logic.discoveryTick(state, ctx);
            break;
        case "confirmed": result = logic.discoveryConfirmed(state, ctx); break;
        case "replaced": result = logic.discoveryReplaced(state); break;
        case "teardown": result = logic.discoveryTeardown(state, ctx); break;
        default: throw new Error("discovery verb " + verb);
        }
        state = result.state;
        effects.push(result.effects);
    }
    return { state, effects, ids };
}

function verifyDiscovery(logic) {
    assert.equal(logic.DISCOVERY_TICK_MS, 1000, "a 1 s stop interval");
    assert.equal(logic.DISCOVERY_STOP_ATTEMPTS, 3, "three stops");

    let run = discoveryTrail(logic, "a start confirmed after the last release is still stopped", [
        ["begin", null, true, false],
        ["end", 1, true, false],
        ["tick", false, true, false],
        ["confirmed", null, true, true],
        ["tick", true, true, true],
    ]);
    same(run.effects, [["start"], [], [], [], ["stop"]], "a start confirmed after the last release is still stopped");

    run = discoveryTrail(logic, "the stop is written at the end, then retried three times", [
        ["begin", null, true, true],
        ["end", 1, true, true],
        ["tick", true, true, true],
        ["tick", true, true, true],
        ["tick", true, true, true],
        ["tick", true, true, true],
        ["tick", false, true, true],
    ]);
    same(run.effects, [[], ["stop"], ["stop"], ["stop"], ["stop"], [], []], "the stop is written at the end, then retried three times");
    same(run.state, { leases: [], next: 2, owes: false, attempts: 0 }, "past the attempts the debt is dropped");

    // A new lease after a partial retry resets the attempts, so the next
    // last release gets its full three stops; so does a later last end.
    run = discoveryTrail(logic, "a new lease resets the attempts", [
        ["begin", null, true, true],
        ["end", 1, true, true],
        ["tick", true, true, true],
        ["begin", null, true, true],
        ["end", 2, true, true],
        ["tick", true, true, true],
        ["tick", true, true, true],
        ["tick", true, true, true],
        ["tick", true, true, true],
    ]);
    same(run.effects, [[], ["stop"], ["stop"], [], ["stop"], ["stop"], ["stop"], ["stop"], []], "a new lease resets the attempts");
    let state = logic.discoveryBegin(logic.discoveryIdle(), { powered: true, confirmed: true }).state;
    state = logic.discoveryEnd(state, 1, { powered: true, confirmed: true }).state;
    state = logic.discoveryTick(state, { powered: true, confirmed: true }).state;
    state = logic.discoveryBegin(state, { powered: true, confirmed: true }).state;
    state = Object.assign({}, state, { attempts: 2 });
    same(logic.discoveryEnd(state, 2, { powered: true, confirmed: true }).state.attempts, 0, "the last end resets the attempts");

    run = discoveryTrail(logic, "a confirmed stop settles the debt", [
        ["begin", null, true, false],
        ["confirmed", null, true, true],
        ["end", 1, true, true],
        ["confirmed", null, true, false],
        ["confirmed", null, true, true],
        ["tick", false, true, true],
    ]);
    same(run.effects, [["start"], [], ["stop"], [], [], []], "a confirmed stop settles the debt");

    // A session another client starts while a lease waits on an unpowered
    // adapter is adopted when BlueZ confirms it, so the last end stops it.
    run = discoveryTrail(logic, "a session confirmed while a lease is open is adopted", [
        ["begin", null, false, false],
        ["confirmed", null, false, true],
        ["end", 1, false, true],
    ]);
    same(run.effects, [[], [], ["stop"]], "a session confirmed while a lease is open is adopted");

    run = discoveryTrail(logic, "each lease takes its own id", [
        ["begin", null, true, false],
        ["confirmed", null, true, true],
        ["begin", null, true, true],
        ["end", 1, true, true],
        ["end", 2, true, true],
    ]);
    same(run.ids, [1, 2], "each lease takes its own id");
    same(run.effects, [["start"], [], [], [], ["stop"]], "the last lease's end stops");

    state = logic.discoveryBegin(logic.discoveryIdle(), { powered: true, confirmed: false }).state;
    const unknown = logic.discoveryEnd(state, 7, { powered: true, confirmed: false });
    same([unknown.known, unknown.effects, unknown.state], [false, [], state], "an unknown lease is refused");
    state = logic.discoveryEnd(state, 1, { powered: true, confirmed: false }).state;
    same(logic.discoveryEnd(state, 1, { powered: true, confirmed: false }).known, false, "a lease ends once");

    run = discoveryTrail(logic, "a session running at the first lease is adopted", [["begin", null, true, true], ["end", 1, true, true]]);
    same(run.effects, [[], ["stop"]], "a session running at the first lease is adopted");

    run = discoveryTrail(logic, "the tick starts discovery for an open lease", [
        ["begin", null, false, false],
        ["tick", false, false, false],
        ["tick", true, true, false],
        ["confirmed", null, true, true],
        ["tick", false, true, true],
        ["confirmed", null, true, false],
        ["tick", true, true, false],
    ]);
    same(run.effects, [[], [], ["start"], [], [], [], ["start"]], "the tick starts discovery for an open lease");

    run = discoveryTrail(logic, "a replaced adapter's session is not stopped on the new one", [["begin", null, true, false], ["replaced", null, true, false], ["end", 1, true, true], ["tick", false, true, true]]);
    same(run.effects, [["start"], [], [], []], "a replaced adapter's session is not stopped on the new one");
    run = discoveryTrail(logic, "teardown stops a session it owes and leaves nothing", [["begin", null, true, false], ["confirmed", null, true, true], ["teardown", null, true, true]]);
    same([run.effects[2], run.state], [["stop"], logic.discoveryIdle()], "teardown stops a session it owes and leaves nothing");
    run = discoveryTrail(logic, "teardown stops nothing it does not owe", [["begin", null, true, true], ["end", 1, true, true], ["confirmed", null, true, false], ["teardown", null, true, true]]);
    same(run.effects[3], [], "teardown stops nothing it does not owe");
}

function verifyPairing(logic) {
    const step = (state, event) => logic.pairStep(state, event);
    let s = logic.pairIdle();
    let r = step(s, { type: "start", address: "AA", name: "Phone" });
    same([r.state.phase, r.state.name, r.effects], ["leasing", "Phone", ["begin-lease"]], "a pairing takes an agent lease first");
    s = r.state;
    same(step(s, { type: "lease", state: "pending" }).effects, [], "a pending lease waits");
    r = step(s, { type: "lease", state: "ready" });
    same([r.state.phase, r.effects], ["pairing", ["pair"]], "Pair is called once the agent is ready");
    s = r.state;
    same(step(s, { type: "start", address: "BB", name: "Mouse" }).state, s, "a second pairing keeps the first, its device and its name");
    assert.equal(logic.pairText(step(s, { type: "start", address: "BB", name: "Mouse" }).state), "Pairing with Phone", "the line names the first device");
    r = step(s, { type: "pair-ended", open: 1 });
    same([r.state.phase, r.effects], ["pairing", []], "a Pair that answered while a prompt is open keeps pairing");
    s = r.state;
    r = step(s, { type: "prompts", open: 0 });
    same([r.state.phase, r.effects], ["settling", ["arm-settle"]], "the prompt answered, the pairing settles");
    s = r.state;
    r = step(s, { type: "prompts", open: 1 });
    same([r.state.phase, r.effects], ["pairing", ["disarm-settle"]], "a new prompt while settling keeps pairing");
    s = step(r.state, { type: "prompts", open: 0 }).state;
    r = step(s, { type: "paired" });
    same([r.state.phase, r.effects], ["done", ["disarm-settle", "release-lease", "trust-connect"]], "a paired device is trusted and connected and the lease released");
    same(step(r.state, { type: "settled" }).state.phase, "done", "a late settle changes nothing once done");
    same(step(logic.pairIdle(), { type: "paired" }).effects, [], "a device paired with no pairing running does nothing");

    const fail = (events, reason, effects) => {
        let state = step(logic.pairIdle(), { type: "start", address: "AA", name: "Phone" }).state;
        let last = null;
        for (const event of events) {
            last = step(state, event);
            state = last.state;
        }
        same([state.phase, state.reason, last.effects], ["failed", reason, effects], "pairing fails as " + reason);
        assert.ok(logic.pairText(state).length > 0, "a failure tells the user: " + reason);
    };
    fail([{ type: "lease", state: "refused" }], "agent-busy", ["release-lease"]);
    fail([{ type: "lease", state: "ready" }, { type: "pair-ended", open: 0 }, { type: "settled" }], "not-paired", ["release-lease"]);
    fail([{ type: "lease", state: "ready" }, { type: "cancel" }], "canceled", ["disarm-settle", "cancel-pair", "release-lease"]);
    fail([{ type: "lease", state: "ready" }, { type: "gone" }], "gone", ["disarm-settle", "release-lease"]);
    same(step(logic.pairIdle(), { type: "cancel" }).effects, [], "a cancel with no pairing does nothing");
    assert.equal(logic.pairText(logic.pairIdle()), "", "no pairing, no line");
    assert.equal(logic.pairActive(logic.pairIdle()), false, "an idle pairing is not active");
    assert.throws(() => step(logic.pairIdle(), { type: "dance" }), /pair event/, "an unknown event is refused");
}

function verifyPrompts(logic) {
    const entry = (kind, extra) => Object.assign({ id: 1, kind, code: "", service: "", entered: 0 }, extra);
    // Each kind's field, its accept answer and its dismissal, by hand.
    const kinds = [
        ["confirm", entry("confirm", { code: "004821" }), "", "", { answer: true }, { answer: false, cancels: true }],
        ["pin", entry("pin"), "PIN", "0000", { answer: "0000" }, { answer: false, cancels: true }],
        ["passkey-entry", entry("passkey-entry"), "Passkey", "123456", { answer: 123456 }, { answer: false, cancels: true }],
        ["passkey-display", entry("passkey-display", { code: "246810" }), "", "", { answer: true }, { answer: true, cancels: true }],
        ["authorize", entry("authorize"), "", "", { answer: true }, { answer: false, cancels: true }],
        ["cancel", entry("cancel"), "", "", { answer: true }, { answer: true, cancels: false }],
        ["rename", null, "Name", "  Desk  ", { answer: "Desk" }, { answer: null, cancels: false }],
    ];
    for (const [kind, request, field, text, accepted, dismissed] of kinds) {
        const view = logic.promptView(kind, "Phone", request, text);
        assert.equal(view.field, field, "prompt " + kind + ": its field");
        assert.ok(view.title.length > 0 && view.message.length > 0, "prompt " + kind + ": a title and a message");
        same(logic.promptAccept(kind, text, utf8Bytes), accepted, "prompt " + kind + ": its accept answer");
        same(logic.promptDismiss(kind), dismissed, "prompt " + kind + ": its dismissal");
    }
    assert.ok(logic.promptView("confirm", "Phone", entry("confirm", { code: "004821" }), "").message.includes("004821"), "a confirm prompt shows its code");
    assert.ok(logic.promptView("passkey-display", "Phone", entry("passkey-display", { code: "246810", entered: 2 }), "").message.includes("246810"), "a code to type shows the code");
    same(logic.promptView("pin", "Phone", entry("pin"), " ").actions.map(a => a.enabled), [true, false], "a blank PIN disables Pair");
    same(logic.promptView("pin", "Phone", entry("pin"), "1").actions.map(a => a.enabled), [true, true], "a typed PIN enables Pair");
    same(logic.promptView("rename", "Phone", null, "").actions.map(a => a.enabled), [true, false], "a blank name disables Rename");
    same(logic.promptAccept("passkey-entry", "12a", utf8Bytes), { error: "Enter a number from 0 to 999999." }, "a passkey that is no number is refused");
    same(logic.promptAccept("passkey-entry", "1234567", utf8Bytes), { error: "Enter a number from 0 to 999999." }, "a passkey of seven digits is refused");
    same(logic.promptAccept("rename", "   ", utf8Bytes), { error: "Enter a name." }, "an empty name is refused as empty");
    same(logic.promptAccept("rename", "é".repeat(125), utf8Bytes), { error: "Enter a shorter name." }, "a long name is refused as too long");
    same([logic.aliasOf("é".repeat(124), utf8Bytes), logic.aliasOf("é".repeat(125), utf8Bytes), logic.aliasOf(" ", utf8Bytes)],
        [{ alias: "é".repeat(124) }, { refused: "too-long" }, { refused: "empty" }], "a rename is held to 248 bytes");
    assert.notEqual(logic.promptRefusal("pin"), logic.promptRefusal("confirm"), "a refused PIN says what a PIN takes");
    assert.throws(() => logic.promptView("dance", "Phone", null, ""), /prompt kind/, "an unknown prompt kind is refused");
}

function verifyDevices(logic) {
    const device = (address, name, extra) => Object.assign({ address, name, deviceName: name, icon: "", connected: false, paired: false, bonded: false, trusted: false, pairing: false, batteryAvailable: false, battery: 0 }, extra);
    const lists = logic.deviceRows([
        device("00:00:00:00:00:03", "Zed Speaker", { paired: true, icon: "audio-card" }),
        device("00:00:00:00:00:01", "Headphones", { paired: true, connected: true, icon: "audio-headphones", batteryAvailable: true, battery: 0.5 }),
        device("00:00:00:00:00:02", "Keyboard", { icon: "input-keyboard" }),
        device("00:00:00:00:00:04", "00:00:00:00:00:04", {}),
        device("00:00:00:00:00:05", "", {}),
        device("00:00:00:00:00:06", "", { trusted: true }),
        device("00:00:00:00:00:07", "1b2c3d4e-0000-1000-8000-00805f9b34fb", {}),
        device("00:00:00:00:00:08", "Watch", { bonded: true }),
        device("00:00:00:00:00:09", "Pen", { pairing: true }),
    ]);
    same(lists.mine.map(r => [r.key, r.text, r.iconName, r.secondary]), [
        ["00:00:00:00:00:06", "00:00:00:00:00:06", "bluetooth", "Not paired"],
        ["00:00:00:00:00:01", "Headphones", "headphones", "Connected"],
        ["00:00:00:00:00:08", "Watch", "bluetooth", "Not connected"],
        ["00:00:00:00:00:03", "Zed Speaker", "speaker", "Not connected"],
    ], "your devices: paired, bonded or trusted, sorted by name, a nameless one by address");
    same(lists.nearby.map(r => [r.key, r.text, r.iconName, r.secondary]), [
        ["00:00:00:00:00:02", "Keyboard", "keyboard", "Not paired"],
        ["00:00:00:00:00:09", "Pen", "bluetooth", "Pairing"],
    ], "nearby: only devices that name themselves, neither an address nor a UUID");
    same(lists.mine[1].battery, 0.5, "a battery level is carried");
    assert.ok(Number.isNaN(lists.mine[3].battery), "no battery reads as none");
    same(logic.deviceAt([device("A", "x"), device("B", "y")], "B").name, "y", "deviceAt finds by address");
    same(logic.deviceAt([device("A", "x")], "C"), null, "deviceAt answers null for none");
    same([logic.mineAction({ connected: true }), logic.mineAction({ connected: false })],
        [{ text: "Disconnect", variant: "secondary" }, { text: "Connect", variant: "primary" }], "your device's action");
    same([logic.nearbyAction({ pairing: false }, false), logic.nearbyAction({ pairing: true }, false), logic.nearbyAction({ pairing: false }, true)],
        [{ text: "Pair", variant: "primary" }, null, null], "Pair hides while any pairing runs");
    same(logic.mineMenu({ trusted: true }).map(e => e.key), ["rename", "untrust", "forget"], "a trusted device's menu");
    same(logic.mineMenu({ trusted: false }).map(e => e.key), ["rename", "trust", "forget"], "an untrusted device's menu");
}

function verifyBar(logic) {
    const on = { key: "on", on: true, text: "On" }, off = { key: "off", on: false, text: "Off" };
    const rows = [
        ["before the service published", null, 0, false, { shown: false, icon: "bluetooth", count: "", tooltip: "Bluetooth" }],
        ["on with nothing connected", on, 0, false, { shown: true, icon: "bluetooth", count: "", tooltip: "Bluetooth: On" }],
        ["on with two connected", on, 2, false, { shown: true, icon: "bluetooth-connected", count: "2", tooltip: "Bluetooth: 2 connected" }],
        ["off with devices still listed connected", off, 1, false, { shown: true, icon: "bluetooth-off", count: "", tooltip: "Bluetooth: Off" }],
        ["off with Hide when off", off, 0, true, { shown: false, icon: "bluetooth-off", count: "", tooltip: "Bluetooth: Off" }],
        ["on with Hide when off", on, 0, true, { shown: true, icon: "bluetooth", count: "", tooltip: "Bluetooth: On" }],
        ["no adapter", { key: "no-adapter", on: false, text: "No Bluetooth adapter found" }, 0, false, { shown: false, icon: "bluetooth-off", count: "", tooltip: "Bluetooth: No Bluetooth adapter found" }],
        ["the service stopped", { key: "service-needed", on: false, text: "The Bluetooth service is off." }, 0, false, { shown: false, icon: "bluetooth-off", count: "", tooltip: "Bluetooth: The Bluetooth service is off." }],
    ];
    for (const [label, power, connected, hide, want] of rows) same(logic.barView(power, connected, hide), want, "bar: " + label);
}

function verify(logic) {
    verifyRfkill(logic);
    verifyView(logic);
    verifyPower(logic);
    verifyDiscovery(logic);
    verifyPairing(logic);
    verifyPrompts(logic);
    verifyDevices(logic);
    verifyBar(logic);
}

verify(load(file));

// Each control: its rule, the text it edits, the edit, and the message of
// the assertion that must fail on the copy.
const controls = [
    ["a plain lease counter leaks a late-confirmed start", 'return { state: withState(state, { attempts: state.attempts + 1 }), effects: ["stop"] };', "return { state: state, effects: [] };", "a start confirmed after the last release is still stopped"],
    ["the stop retries are bounded", "if (state.attempts >= DISCOVERY_STOP_ATTEMPTS)", "if (false)", "the stop is written at the end, then retried three times"],
    ["the last end resets the attempts", "    next.attempts = 0;\n", "", "a new lease resets the attempts"],
    ["a start incurs the debt", 'effects.push("start");\n        next.owes = true;', 'effects.push("start");', "a start confirmed after the last release is still stopped"],
    ["a running session is adopted", "    if (ctx.confirmed) next.owes = true;\n", "", "the stop is written at the end, then retried three times"],
    ["a session confirmed while a lease is open is adopted", "if (state.leases.length > 0 && ctx.confirmed) return { state: withState(state, { owes: true }), effects: [] };", "", "a session confirmed while a lease is open is adopted"],
    ["the last end stops a confirmed session at once", 'effects: next.owes && ctx.confirmed ? ["stop"] : [], known: true', "effects: [], known: true", "the stop is written at the end, then retried three times"],
    ["only the last end stops", "    if (leases.length > 0) return { state: next, effects: [], known: true };\n", "", "the last lease's end stops"],
    ["a confirmed stop settles the debt", "if (state.leases.length === 0 && !ctx.confirmed) return", "if (false) return", "a confirmed stop settles the debt"],
    ["a lease restarts discovery on a tick", 'return { state: withState(state, { owes: true }), effects: ["start"] };', "return { state: state, effects: [] };", "the tick starts discovery for an open lease"],
    ["replacement clears the debt", "function discoveryReplaced(state) {\n    return { state: withState(state, { owes: false, attempts: 0 }), effects: [] };", "function discoveryReplaced(state) {\n    return { state: state, effects: [] };", "a replaced adapter's session is not stopped on the new one"],
    ["teardown stops what it owes", 'return { state: discoveryIdle(), effects: state.owes && ctx.confirmed ? ["stop"] : [] };', "return { state: discoveryIdle(), effects: [] };", "teardown stops a session it owes"],
    ["on waits for confirmed power", 'return { op: opOf("waiting", "on", false, ""), effects: [{ type: "read" }, { type: "arm", ms: POWER_WAIT_MS }] };', "return { op: powerIdle(), effects: [{ type: \"read\" }] };", "on unblocks and waits for confirmed power"],
    ["on falls back to Powered", 'if (!op.fallback) return { op: opOf("waiting", "on", true, ""), effects: [{ type: "enable" }, { type: "arm", ms: POWER_WAIT_MS }] };', 'if (!op.fallback) return failed("on", "no-power");', "on falls back to setting Powered"],
    ["the fallback's wait can fail", 'return failed("on", "no-power");', "return { op: powerIdle(), effects: [] };", "on fails after the fallback's wait"],
    ["confirmed power ends the wait", 'if (op.phase === "waiting" && seen.powered) return { op: powerIdle(), effects: [{ type: "disarm" }] };', "", "on unblocks and waits for confirmed power"],
    ["an observed power clears a failure", 'if (op.phase === "failed" && reached(op.want, seen)) return { op: powerIdle(), effects: [] };', "", "an adapter that powers up late clears the failed On"],
    ["a failed Off waits for the block", "return seen.rfkill.state === \"read\" && seen.rfkill.soft;", "return true;", "a failed Off stays while rfkill reads no block"],
    ["a failed view reads the observed power", 'view("failed", { on: input.powered, text: FAILURE_TEXT[input.op.reason] })', 'view("failed", { text: FAILURE_TEXT[input.op.reason] })', "a failed Off over a powered adapter reads the power"],
    ["off writes the soft block", 'effects: [{ type: "run", verb: "block" }], reply: "ok" };', 'effects: [{ type: "run", verb: "unblock" }], reply: "ok" };', "off writes the soft block"],
    ["a failed block fails", 'return event.code === 0 ? { op: powerIdle(), effects: [{ type: "read" }] } : failed("off", "rfkill-failed");', 'return { op: powerIdle(), effects: [{ type: "read" }] };', "a failed block fails Off"],
    ["a hard block wins", "if (read && rfkill.hard)", "if (false)", "view: a hard block wins"],
    ["a refused press writes nothing", "if (!current.canToggle) return", "if (false) return", "power refuses a hard block"],
    ["a soft block reads off", "    if (read && rfkill.soft) return view(\"off\", {});\n", "", "view: a soft block reads off"],
    ["no adapter offers the service step", 'input.step === "needed" || input.step === "nixos" ? "service-needed" : "no-adapter"', '"no-adapter"', "view: no adapter with the service step needed"],
    ["a hint line shows its text", 'hint: current.shows === "hint" ? current.text : "",', 'hint: "",', "powerLine: a hard block is a hint"],
    ["a refused press wins the error line", 'error: problem !== "" ? problem : current.shows === "error" ? current.text : ""', 'error: current.shows === "error" ? current.text : ""', "powerLine: a refused press is an error"],
    ["any radio's soft block counts", 'soft = soft || row.soft === "blocked";', 'soft = row.soft === "blocked";', "rfkill: a block on any of two radios"],
    ["only Bluetooth radios count", 'row.type !== "bluetooth"', "false", "rfkill: another radio type is not Bluetooth"],
    ["a failed rfkill read is no reading", 'if (code !== 0) return { state: "failed", reason: "exit=" + code };', "", "rfkill: a failed run"],
    ["an ended Pair with no prompt settles", 'return { state: pairWith(state, { phase: "settling", ended: true }), effects: ["arm-settle"] };', "return { state: pairWith(state, { ended: true }), effects: [] };", "pairing fails as not-paired"],
    ["an open prompt keeps the pairing", "if (event.open > 0) return { state: pairWith(state, { ended: true }), effects: [] };", "", "a Pair that answered while a prompt is open keeps pairing"],
    ["a paired device is trusted and connected", 'effects: ["disarm-settle", "release-lease", "trust-connect"]', 'effects: ["disarm-settle", "release-lease"]', "a paired device is trusted and connected"],
    ["a refused agent lease fails the pairing", 'if (event.state === "refused")', "if (false)", "pairing fails as agent-busy"],
    ["one pairing at a time keeps its name", "        if (pairActive(state)) return { state: state, effects: [] };\n        return { state: { phase: \"leasing\"", "        return { state: { phase: \"leasing\"", "a second pairing keeps the first, its device and its name"],
    ["a paired event needs a pairing", "        if (!pairActive(state)) return { state: state, effects: [] };\n        return { state: pairWith(state, { phase: \"done\" })", "        return { state: pairWith(state, { phase: \"done\" })", "a device paired with no pairing running does nothing"],
    ["a dismissed code to type is answered true", '"passkey-display": {\n        field: "", accept: "true", dismiss: true,', '"passkey-display": {\n        field: "", accept: "true", dismiss: false,', "prompt passkey-display: its dismissal"],
    ["a dismissed cancel ends no pairing", 'field: "", accept: "true", dismiss: true, cancels: false,', 'field: "", accept: "true", dismiss: true, cancels: true,', "prompt cancel: its dismissal"],
    ["a passkey is a number", 'case "number":\n        if (!/^[0-9]{1,6}$/.test(fieldText)) return { error: "Enter a number from 0 to 999999." };\n        return { answer: Number(fieldText) };', 'case "number":\n        return { answer: fieldText };', "prompt passkey-entry: its accept answer"],
    ["an accept that needs the field is disabled while it is blank", "enabled: !(action.needsField === true && blank)", "enabled: true", "a blank PIN disables Pair"],
    ["an empty name is refused as empty", 'if (value === "") return { refused: "empty" };', "", "an empty name is refused as empty"],
    ["a rename is held to BlueZ's length", 'if (utf8Bytes(value) > ALIAS_MAX_BYTES) return { refused: "too-long" };', "", "a long name is refused as too long"],
    ["a nameless nearby device is hidden", "if (!known && !namesItself(d)) continue;", "", "nearby: only devices that name themselves"],
    ["a UUID is no name", "return !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(label);", "return true;", "nearby: only devices that name themselves"],
    ["a bonded device is yours", "var known = d.paired || d.bonded || d.trusted;", "var known = d.paired || d.trusted;", "your devices: paired, bonded or trusted"],
    ["a pairing device reads Pairing", 'if (d.pairing) return "Pairing";', "", "nearby: only devices that name themselves"],
    ["Pair hides while another device pairs", "return pairing || row.pairing ? null", "return row.pairing ? null", "Pair hides while any pairing runs"],
    ["the bar hides with Hide when off while off", "!(hideWhenOff && !power.on)", "true", "bar: off with Hide when off"],
    ["the bar counts only while on", "var linked = power.on && connected > 0;", "var linked = connected > 0;", "bar: off with devices still listed connected"],
];

function failsWith(mutantFile, message) {
    try {
        verify(load(mutantFile));
    } catch (e) {
        if (!(e instanceof assert.AssertionError)) return "threw " + e.constructor.name + ": " + e.message;
        return e.message.includes(message) ? "" : "failed elsewhere: " + e.message.split("\n")[0];
    }
    return "passed";
}

fs.rmSync(scratch, { recursive: true, force: true });
fs.mkdirSync(scratch, { recursive: true });
try {
    const source = fs.readFileSync(file, "utf8");
    for (const [label, needle, replacement, message] of controls) {
        const count = source.split(needle).length - 1;
        assert.equal(count, 1, "control pattern occurs once: " + label);
        const mutant = path.join(scratch, "BluetoothLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, () => replacement));
        const outcome = failsWith(mutant, message);
        assert.equal(outcome, "", "control " + JSON.stringify(label) + " must fail on " + JSON.stringify(message));
    }
} finally {
    fs.rmSync(scratch, { recursive: true, force: true });
}

console.log("test-bluetooth-logic: ok controls=" + controls.length);
