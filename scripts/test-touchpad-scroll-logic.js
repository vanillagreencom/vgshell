#!/usr/bin/env node
// TouchpadScroll's decisions, shell/Ui/layout/TouchpadScrollLogic.js, under
// node: how far a delta moves a view, where its bounds hold it, which
// deltas a coast is read from, how far it coasts and the velocity a flick
// of that distance needs. Expected values are written out by hand from
// GTK's rule: 2.5 px per pixel of delta, a coast from the mean velocity of
// the last 150 ms that loses 4 of its velocity per second. The controls at
// the end edit a copy of the logic, one rule at a time, and require this
// suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "Ui", "layout", "TouchpadScrollLogic.js");

// Steps: [label, delta, carry before, move, carry after].
const STEPS = [
    ["no delta moves nothing", 0, 0, 0, 0],
    ["four pixels move ten", 4, 0, 10, 0],
    ["one pixel rounds up and owes half", 1, 0, 3, -0.5],
    ["the next pixel pays the half back", 1, -0.5, 2, 0],
    ["one pixel up rounds toward the end and is owed half", -1, 0, -2, -0.5],
    ["a kept fraction alone moves nothing", 0, 0.25, 0, 0.25]
];

// Bounds: [label, value, low, high, held].
const CLAMPS = [
    ["inside", 40, 0, 100, 40],
    ["before the start", -5, 0, 100, 0],
    ["past the end", 130, 0, 100, 100],
    ["a view that fits stays at its start", 30, 0, -200, 0],
    ["a start below zero, as a margin gives", -30, -12, 100, -12]
];

// Histories: [label, history, at, dx, dy, the `at` of each entry kept].
const at = (time, dy) => ({ at: time, dx: 0, dy: dy });
const REMEMBERS = [
    ["the first delta", [], 1000, 0, 3, [1000]],
    ["a delta inside the window keeps the one before", [at(1000, 3)], 1100, 0, 3, [1000, 1100]],
    ["the window's edge is kept", [at(1000, 3)], 1150, 0, 3, [1000, 1150]],
    ["a delta past the window drops the one before", [at(1000, 3)], 1151, 0, 3, [1151]],
    ["only the old ones go", [at(1000, 3), at(1100, 3), at(1200, 3)], 1260, 0, 3, [1200, 1260]]
];

// Coasts: [label, history, lift time, x, y]. 40 px over 100 ms is 400 px a
// second; times 2.5, over a friction of 4, is 250 px.
const COASTS = [
    ["no delta", [], 1000, 0, 0],
    ["one delta has no velocity", [at(1000, 40)], 1000, 0, 0],
    ["two deltas at one time have none", [at(1000, 20), at(1000, 20)], 1000, 0, 0],
    ["400 px a second coasts 250 px", [at(1000, 20), at(1100, 20)], 1100, 0, 250],
    ["toward the start", [at(1000, -20), at(1100, -20)], 1100, 0, -250],
    ["a lift at the window's edge still coasts", [at(1000, 20), at(1100, 20)], 1250, 0, 250],
    ["fingers that rested first do not coast", [at(1000, 20), at(1100, 20)], 1251, 0, 0],
    ["each axis has its own", [{ at: 1000, dx: 10, dy: 0 }, { at: 1050, dx: 10, dy: 4 }], 1050, 250, 50]
];

// Flick velocities: [label, distance, deceleration, velocity]. A flick of
// velocity v stops after v * v / (2 * deceleration).
const FLICKS = [
    ["no distance", 0, 1500, 0],
    ["300 px at Qt's default deceleration", 300, 1500, Math.sqrt(900000)],
    ["toward the start", -300, 1500, -Math.sqrt(900000)],
    ["a platform's own deceleration", 250, 5000, Math.sqrt(2500000)]
];

// The logic's objects come from its own context and a rounded half is -0,
// so each number is compared as a number.
function near(got, want, label) {
    assert.ok(typeof got === "number" && Math.abs(got - want) < 1e-9, `${label}: got ${got}, want ${want}`);
}

function verify(logic) {
    for (const [label, delta, carry, move, left] of STEPS) {
        const got = logic.step(delta, carry);
        near(got.move, move, `step: ${label}: move`);
        near(got.carry, left, `step: ${label}: carry`);
        assert.ok(Number.isInteger(got.move), `step: ${label}: a whole pixel`);
    }
    for (const [label, value, low, high, want] of CLAMPS)
        near(logic.clamp(value, low, high), want, `clamp: ${label}`);
    for (const [label, history, time, dx, dy, want] of REMEMBERS) {
        const before = JSON.stringify(history);
        const kept = logic.remember(history, time, dx, dy);
        assert.equal(JSON.stringify(kept.map(entry => entry.at)), JSON.stringify(want), `remember: ${label}`);
        assert.equal(JSON.stringify(kept[kept.length - 1]), JSON.stringify({ at: time, dx: dx, dy: dy }), `remember: ${label}: the new entry`);
        assert.equal(JSON.stringify(history), before, `remember: ${label}: the history handed in is unchanged`);
    }
    for (const [label, history, time, x, y] of COASTS) {
        const got = logic.coast(history, time);
        near(got.x, x, `coast: ${label}: x`);
        near(got.y, y, `coast: ${label}: y`);
    }
    for (const [label, distance, deceleration, want] of FLICKS)
        near(logic.flickVelocity(distance, deceleration), want, `flick: ${label}`);
}
verify(load(file));

// Each control removes one rule from a copy of the logic and keeps the text
// around it. The suite must fail on every copy.
const CONTROLS = [
    ["the gain", "const exact = delta * GAIN + carry;", "const exact = delta + carry;"],
    ["the kept fraction", "const exact = delta * GAIN + carry;", "const exact = delta * GAIN;"],
    ["whole pixels", "const move = Math.round(exact);", "const move = exact;"],
    ["the start bound", "return Math.max(low, Math.min(high, value));", "return Math.min(high, value);"],
    ["the end bound", "return Math.max(low, Math.min(high, value));", "return Math.max(low, value);"],
    ["a range with no room", "return Math.max(low, Math.min(high, value));", "return Math.min(high, Math.max(low, value));"],
    ["the velocity window", "entry.at >= at - VELOCITY_WINDOW_MS", "true"],
    ["no delta coasts nothing", "if (history.length === 0) return { x: 0, y: 0 };", "if (history.length === 0) return { x: 1, y: 1 };"],
    ["deltas of one moment", "if (span <= 0 || at - last.at > VELOCITY_WINDOW_MS) return { x: 0, y: 0 };", "if (at - last.at > VELOCITY_WINDOW_MS) return { x: 0, y: 0 };"],
    ["rested fingers", "if (span <= 0 || at - last.at > VELOCITY_WINDOW_MS) return { x: 0, y: 0 };", "if (span <= 0) return { x: 0, y: 0 };"],
    ["the coast's gain", "const scale = 1000 / span * GAIN / FRICTION;", "const scale = 1000 / span / FRICTION;"],
    ["the coast's friction", "const scale = 1000 / span * GAIN / FRICTION;", "const scale = 1000 / span * GAIN;"],
    ["the flick's direction", "return Math.sign(distance) * Math.sqrt(2 * deceleration * Math.abs(distance));", "return Math.sqrt(2 * deceleration * Math.abs(distance));"],
    ["the flick's deceleration", "return Math.sign(distance) * Math.sqrt(2 * deceleration * Math.abs(distance));", "return Math.sign(distance) * Math.sqrt(2 * Math.abs(distance));"]
];

const source = fs.readFileSync(file, "utf8");
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "touchpad-scroll-logic-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const mutant = path.join(temp, "TouchpadScrollLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, () => replacement));
        let failed = false;
        try {
            verify(load(mutant));
        } catch (e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the suite passed on a copy without that rule`);
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
console.log(`test-touchpad-scroll-logic: ok steps=${STEPS.length} clamps=${CLAMPS.length} remembers=${REMEMBERS.length} coasts=${COASTS.length} flicks=${FLICKS.length} controls=${CONTROLS.length}`);
