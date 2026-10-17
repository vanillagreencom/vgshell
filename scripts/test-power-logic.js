#!/usr/bin/env node
// Table-driven checks for vgs.power's pure decisions, PowerLogic.js:
// battery presence, battery and profile views, icon bands, time text,
// the profile view read from the daemon's reply, source-change profile
// choice, the setting a bar pick remembers, low-battery latches and the
// notice each latch sends.
// Controls edit one rule at a time in a copy of the logic under repo tmp
// and require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.power", "PowerLogic.js");
const controlRoot = path.join(__dirname, "..", "tmp", "test-power-logic-controls");
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message);

function device(overrides) {
    return Object.assign({
        isPresent: true,
        isLaptopBattery: true,
        percentage: 0.51,
        state: 2,
        timeToEmpty: 5400,
        timeToFull: 0
    }, overrides || {});
}

function verify(logic) {
    assert.equal(logic.batteryPresent(device()), true, "a present laptop battery is present");
    assert.equal(logic.batteryPresent(device({ isPresent: false })), false, "an absent battery is not present");
    assert.equal(logic.batteryPresent(device({ isLaptopBattery: false })), false, "a UPS display device is not a laptop battery");
    assert.equal(logic.batteryPresent(null), false, "no display device is not present");

    same(logic.batteryView(device(), true), {
        present: true,
        level: 51,
        charging: false,
        state: "discharging",
        secondsToEmpty: 5400,
        secondsToFull: 0
    }, "batteryView: discharging laptop");
    same(logic.batteryView(device({ percentage: 0.876, state: 1, timeToEmpty: 0, timeToFull: 3600 }), false), {
        present: true,
        level: 88,
        charging: true,
        state: "charging",
        secondsToEmpty: 0,
        secondsToFull: 3600
    }, "batteryView: charging laptop");
    assert.equal(logic.batteryView(device({ state: 4 }), false).charging, false, "batteryView: AC power alone is not charging");
    assert.equal(logic.batteryView(device({ state: 5 }), false).charging, false, "batteryView: pending charge is not charging");
    same(logic.batteryView(device({ isLaptopBattery: false }), true), {
        present: false,
        level: 0,
        charging: false,
        state: "absent",
        secondsToEmpty: 0,
        secondsToFull: 0
    }, "batteryView: desktop or UPS display device");

    const icons = [
        [5, false, "battery-warning"],
        [10, false, "battery-warning"],
        [11, false, "battery-low"],
        [34, false, "battery-low"],
        [35, false, "battery-medium"],
        [79, false, "battery-medium"],
        [80, false, "battery-full"],
        [12, true, "battery-charging"]
    ];
    for (const [level, charging, want] of icons)
        assert.equal(logic.batteryIcon(level, charging), want, `batteryIcon ${level} ${charging}`);

    // The mock daemon's reply as gdbus 2.88.3 printed it, then one with a
    // hold on a profile, a profile outside the interface's three and no
    // performance profile.
    const three = "({'ActiveProfile': <'balanced'>, 'PerformanceDegraded': <''>, 'Profiles': <[{'Profile': <'power-saver'>, 'Driver': <'dbusmock'>}, {'Profile': <'balanced'>, 'Driver': <'dbusmock'>}, {'Profile': <'performance'>, 'Driver': <'dbusmock'>}]>, 'Actions': <@as []>, 'ActiveProfileHolds': <@a(aa{sv}) []>},)";
    const held = "({'ActiveProfileHolds': <[{'ApplicationId': <'acme'>, 'Profile': <'performance'>, 'Reason': <'r'>}]>, 'ActiveProfile': <'power-saver'>, 'Profiles': <[{'Profile': <'power-saver'>, 'Driver': <'x'>}, {'Profile': <'turbo'>, 'Driver': <'x'>}, {'Profile': <'balanced'>, 'Driver': <'x'>}]>},)";
    const unavailable = { available: false, active: "balanced", choices: [] };
    const views = [
        ["the daemon's three profiles in its order", three, { available: true, active: "balanced", choices: ["power-saver", "balanced", "performance"] }],
        ["a held profile is no offered profile", held, { available: true, active: "power-saver", choices: ["power-saver", "balanced"] }],
        ["a failed read", "", unavailable],
        ["a reply with no profile list", "({'ActiveProfile': <'balanced'>, 'Profiles': <@aa{sv} []>},)", unavailable],
        ["an active profile the daemon does not offer", held.replace("'ActiveProfile': <'power-saver'>", "'ActiveProfile': <'performance'>"), unavailable]
    ];
    for (const [label, text, want] of views) same(logic.profileView(text), want, "profileView: " + label);
    same(logic.profileMarked(logic.profileView(three), "performance"), { available: true, active: "performance", choices: ["power-saver", "balanced", "performance"] }, "profileMarked: marks the asked profile");
    assert.equal(logic.availableProfile("performance", ["power-saver", "balanced"]), "balanced", "automatic performance falls back when unavailable");
    assert.equal(logic.availableProfile("power-saver", ["power-saver", "balanced"]), "power-saver", "power saver stays available");
    assert.equal(logic.availableProfile("turbo", ["power-saver", "balanced", "performance"]), "balanced", "unknown profile falls back");

    const settings = { chargerProfile: "performance", batteryProfile: "power-saver" };
    assert.equal(logic.profileForSource(false, settings, ["power-saver", "balanced", "performance"]), "performance", "source change applies the charger profile");
    assert.equal(logic.profileForSource(true, settings, ["power-saver", "balanced", "performance"]), "power-saver", "source change applies the battery profile");
    assert.equal(logic.profileForSource(false, settings, ["power-saver", "balanced"]), "balanced", "source change falls back from performance");
    // The setting a bar pick remembers: [battery present, on battery, key].
    for (const [present, onBattery, want] of [
        [true, false, "chargerProfile"],
        [true, true, "batteryProfile"],
        [false, false, ""],
        [false, true, ""]
    ]) assert.equal(logic.rememberedSetting(present, onBattery), want, `rememberedSetting: present=${present} onBattery=${onBattery}`);

    assert.equal(logic.stateLabel({ present: true, charging: true, state: "charging" }), "Charging", "stateLabel: charging");
    assert.equal(logic.stateLabel({ present: true, charging: false, state: "discharging" }), "On battery", "stateLabel: discharging");
    assert.equal(logic.stateLabel({ present: true, charging: false, state: "fully-charged" }), "Fully charged", "stateLabel: full");
    assert.equal(logic.stateLabel({ present: true, charging: false, state: "pending-charge" }), "Plugged in, not charging", "stateLabel: pending charge");
    assert.equal(logic.timeText({ present: true, charging: false, state: "discharging", secondsToEmpty: 9000 }), "2 h 30 min left", "timeText: time to empty");
    assert.equal(logic.timeText({ present: true, charging: true, state: "charging", secondsToFull: 2400 }), "40 min to full", "timeText: time to full");
    assert.equal(logic.timeText({ present: true, charging: false, state: "pending-charge", secondsToFull: 2400 }), "", "timeText: pending charge has no time to full");
    assert.equal(logic.timeText({ present: true, charging: true, state: "charging", secondsToFull: 0 }), "", "timeText: unknown time");

    const widget = logic.widgetView({ battery: { present: true, level: 51, charging: false, state: "discharging" }, profile: { available: true, active: "balanced" } });
    same(widget, {
        shown: true,
        batteryShown: true,
        profileShown: true,
        batteryIcon: "battery-medium",
        profileIcon: "gauge",
        levelText: "51%",
        tooltip: "51% On battery · Balanced"
    }, "widgetView: laptop");
    same(logic.widgetView({ battery: { present: false }, profile: { available: true, active: "performance" } }), {
        shown: true,
        batteryShown: false,
        profileShown: true,
        batteryIcon: "battery-warning",
        profileIcon: "zap",
        levelText: "0%",
        tooltip: "Performance"
    }, "widgetView: desktop with profile");
    same(logic.widgetView({ battery: { present: false }, profile: { available: false, active: "balanced" } }).shown, false, "widgetView: nothing to draw");

    let latch = logic.latchInitial();
    let result = logic.notices(latch, 19, true, 20, 10);
    same(result.notices, [{ threshold: "low", urgency: "normal", level: 19 }], "low crossing sends one normal notice");
    latch = result.latch;
    result = logic.notices(latch, 18, true, 20, 10);
    same(result.notices, [], "same discharge does not send low twice");
    latch = result.latch;
    result = logic.notices(latch, 21, true, 20, 10);
    same(result.notices, [], "a level bounce above low does not rearm while discharging");
    latch = result.latch;
    result = logic.notices(latch, 19, true, 20, 10);
    same(result.notices, [], "a level bounce below low sends no second low notice");
    latch = result.latch;
    result = logic.notices(latch, 9, true, 20, 10);
    same(result.notices, [{ threshold: "critical", urgency: "critical", level: 9 }], "critical crossing sends one critical notice");
    latch = result.latch;
    result = logic.notices(latch, 8, true, 20, 10);
    same(result.notices, [], "same discharge does not send critical twice");
    latch = logic.notices(latch, 30, false, 20, 10).latch;
    result = logic.notices(latch, 19, true, 20, 10);
    same(result.notices, [{ threshold: "low", urgency: "normal", level: 19 }], "charging rearms low");
    result = logic.notices(logic.latchInitial(), 8, true, 20, 10);
    same(result.notices, [{ threshold: "critical", urgency: "critical", level: 8 }], "starting below both thresholds sends only critical");
    same(result.latch, { low: true, critical: true }, "starting below both latches both thresholds");
    const low = logic.noticePayload({ threshold: "low", urgency: "normal", level: 19 });
    const critical = logic.noticePayload({ threshold: "critical", urgency: "critical", level: 9 });
    same([low.tone, low.icon, low.urgency], ["warning", "battery-low", "normal"], "noticePayload: the low notice is a warning");
    same([critical.tone, critical.icon, critical.urgency], ["danger", "battery-warning", "critical"], "noticePayload: the critical notice is danger");
    assert.ok(typeof low.title === "string" && low.title !== "", "noticePayload: the low notice has a title");
    assert.notEqual(low.title, critical.title, "noticePayload: each state has its own title");
    same(logic.sourceObserved({ ready: false, onBattery: false }, false, false), { state: { ready: false, onBattery: false }, apply: false }, "sourceObserved: waits for a ready reading");
    same(logic.sourceObserved({ ready: false, onBattery: false }, true, true), { state: { ready: true, onBattery: true }, apply: false }, "sourceObserved: seeds the first ready reading without applying");
    same(logic.sourceObserved({ ready: true, onBattery: true }, true, false), { state: { ready: true, onBattery: false }, apply: true }, "sourceObserved: later source changes apply");
}

verify(load(file));

const CONTROLS = [
    ["one notice per threshold latches low", "if (!next.low) out.push({ threshold: \"low\", urgency: \"normal\", level: n });\n        next.low = true;", "if (!next.low) out.push({ threshold: \"low\", urgency: \"normal\", level: n });\n        next.low = false;"],
    ["source change applies the new source", "var key = onBattery === true ? \"batteryProfile\" : \"chargerProfile\";", "var key = onBattery === true ? \"chargerProfile\" : \"chargerProfile\";"],
    ["charging reads the device state", "return onBattery !== true && device.state === STATE.Charging;", "return onBattery !== true;"],
    ["battery present needs a laptop battery", "return !!(device && device.isPresent === true && device.isLaptopBattery === true);", "return !!(device && device.isPresent === true);"],
    ["a profile the daemon does not offer falls back", "return choices.indexOf(name) === -1 ? PROFILE.balanced : name;", "return name;"],
    ["the choices are the daemon's Profiles alone", "var list = /'Profiles': <\\[(.*?)\\]>/.exec(source);", "var list = [source, source];"],
    ["an active profile outside the choices is unavailable", "if (active === null || choices.indexOf(active[1]) === -1)", "if (active === null)"],
    ["critical at start latches low", "        next.critical = true;\n        next.low = true;\n    } else if (n <= low) {", "        next.critical = true;\n        next.low = false;\n    } else if (n <= low) {"],
    ["a level bounce does not rearm low", "    if (discharging !== true) return { notices: out, latch: latchInitial() };\n    if (n <= critical) {", "    if (discharging !== true) return { notices: out, latch: latchInitial() };\n    if (n > low) next.low = false;\n    if (n <= critical) {"],
    ["the critical notice is danger", "tone: critical ? \"danger\" : \"warning\",", "tone: \"warning\","],
    ["each notice state has its own title", "title: critical ? \"Battery critical\" : \"Battery low\",", "title: \"Battery low\","],
    ["a bar pick with no battery remembers nothing", "if (batteryPresent !== true) return \"\";", "if (false) return \"\";"],
    ["a bar pick remembers the current source's profile", "return onBattery === true ? \"batteryProfile\" : \"chargerProfile\";\n}", "return \"chargerProfile\";\n}"],
    ["first ready source reading does not apply", "if (state.ready !== true) return { state: { ready: true, onBattery: onBattery === true }, apply: false };", "if (state.ready !== true) return { state: { ready: true, onBattery: onBattery === true }, apply: true };"]
];

const source = fs.readFileSync(file, "utf8");
fs.rmSync(controlRoot, { recursive: true, force: true });
fs.mkdirSync(controlRoot, { recursive: true });
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const mutant = path.join(controlRoot, "PowerLogic.js");
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
    fs.rmSync(controlRoot, { recursive: true, force: true });
}
console.log(`test-power-logic: ok controls=${CONTROLS.length}`);
