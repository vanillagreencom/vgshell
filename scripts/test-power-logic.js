#!/usr/bin/env node
// Table-driven checks for vgs.power's pure decisions, PowerLogic.js:
// battery presence, battery and profile views, icon bands, time text,
// the profile view read from the daemon's reply, source-change profile
// choice, the setting a bar pick remembers, low-battery latches and the
// notice each latch sends, and Wake on LAN's flag values, wired
// connection list and write rule.
// Controls edit one rule at a time in an exclusively owned temporary copy
// and require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.power", "PowerLogic.js");
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
    const wakeDevices = [
        ["keyboard", 1344, 0, true],
        ["mouse", 1408, 0, true],
        ["keyboard and pointer", 1472, 0, true],
        ["gamepad", 1288, 0, false],
        ["headset", 1028, 0, false],
        ["LE keyboard", 0, 961, true],
        ["LE mouse", 0, 962, true],
        ["LE tablet", 0, 965, true],
        ["LE pen", 0, 967, true],
        ["LE touchpad", 0, 969, true],
        ["LE gamepad", 0, 964, false],
        ["unclassified HID", 0, 960, false]
    ];
    for (const [label, deviceClass, appearance, allowed] of wakeDevices)
        same(logic.bluetoothWakeReading(0, `({'WakeAllowed': <false>, 'Class': <uint32 ${deviceClass}>, 'Appearance': <uint16 ${appearance}>},)`),
            { state: "supported", current: false, allowed }, "Bluetooth wake: " + label);
    same(logic.bluetoothWakeReading(0, "({'WakeAllowed': <true>, 'Class': <uint32 1288>},)"),
        { state: "supported", current: true, allowed: false }, "Bluetooth wake: a gamepad's enabled state must change");
    same(logic.bluetoothWakeReading(0, "({'Class': <uint32 1344>},)"), { state: "unsupported" }, "Bluetooth wake: absent WakeAllowed is unsupported");
    same(logic.bluetoothWakeReading(1, ""), { state: "failed", reason: "read-failed" }, "Bluetooth wake: denied read remains failed");
    same(logic.bluetoothWakeReading(0, "garbage"), { state: "failed", reason: "read-invalid" }, "Bluetooth wake: malformed output cannot be ready");
    same(logic.bluetoothWakeReading(0, "({'WakeAllowed': <'false'>, 'Class': <uint32 1344>},)"),
        { state: "failed", reason: "read-invalid" }, "Bluetooth wake: typed WakeAllowed must be boolean");
    same(logic.bluetoothWakeReading(0, "({'Alias': <\"'WakeAllowed': <true>, 'Class': <uint32 1344>\">, 'Class': <uint32 1288>, 'WakeAllowed': <false>},)"),
        { state: "supported", current: false, allowed: false }, "Bluetooth wake: device name cannot supply a field");
    same(logic.bluetoothWakeReading(0, "({'ServiceData': <{'Class': <uint32 1344>, 'WakeAllowed': <true>}>, 'Class': <uint32 1288>, 'WakeAllowed': <false>},)"),
        { state: "supported", current: false, allowed: false }, "Bluetooth wake: nested service data cannot supply a field");
    assert.equal(logic.wakeSourcesValue(null, { state: "checking" }), null, "Wake sources waits for the system probe");
    for (const state of ["needed", "nixos"])
        assert.equal(logic.wakeSourcesValue({ state, reason: "wake-mismatch" }, { state: "ready" }).action, true, "Wake setup offers the declared action: " + state);
    for (const state of ["absent", "denied", "unknown"])
        assert.equal(logic.wakeSourcesValue({ state, reason: "sysfs-unreadable" }, { state: "ready" }).available, false, "Wake setup preserves unavailable probe: " + state);
    for (const error of ["Error: GDBus.Error:org.freedesktop.DBus.Error.AccessDenied: Rejected send message", "GDBus.Error:org.bluez.Error.NotAuthorized: Not authorized"])
        same(logic.bluetoothWakeFailure("write-failed", error), { state: "failed", reason: "permission-denied" }, "Bluetooth wake: explicit denial category");
    same(logic.bluetoothWakeFailure("read-invalid", ""), { state: "failed", reason: "read-invalid" }, "Bluetooth wake: invalid read keeps its cause");
    const refusedWake = logic.wakeSourcesValue({ state: "ready" }, { state: "failed", reason: "permission-denied" });
    assert.equal(refusedWake.available, false, "A denied Bluetooth write is unavailable");
    assert.equal(refusedWake.action, undefined, "A denied Bluetooth write cannot offer root setup as a fix");
    assert.ok(refusedWake.hint.length > 0, "A denied Bluetooth write gives its reason");
    assert.equal(logic.wakeSourcesValue({ state: "ready" }, { state: "ready" }).tone, "ok", "USB and Bluetooth converge to ready");
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
    same(logic.sourceObserved({ ready: false, onBattery: false }, false, false, true), { state: { ready: false, onBattery: false }, apply: false }, "sourceObserved: waits for a ready reading");
    same(logic.sourceObserved({ ready: false, onBattery: false }, true, true, true), { state: { ready: true, onBattery: true }, apply: false }, "sourceObserved: seeds the first ready reading without applying");
    same(logic.sourceObserved({ ready: true, onBattery: true }, true, false, true), { state: { ready: true, onBattery: false }, apply: true }, "sourceObserved: later source changes apply");
    same(logic.sourceObserved({ ready: true, onBattery: false }, true, true, false), { state: { ready: true, onBattery: true }, apply: false }, "sourceObserved: a source change with no battery (a UPS) records the source and keeps the bar pick");

    // NetworkManager's flag names: magic arms the card, none disarms it.
    assert.equal(logic.wakeTarget(true), "magic", "wakeTarget: on is magic");
    assert.equal(logic.wakeTarget(false), "none", "wakeTarget: off is none, never ignore");
    same(logic.wiredConnections("aa-1:802-3-ethernet\nbb-2:802-11-wireless\ncc-3:802-3-ethernet\n\nweird\\:x:802-3-ethernet\n"), ["aa-1", "cc-3"], "wiredConnections: the wired rows alone, a line with an escaped colon skipped");
    same(logic.wiredConnections(""), [], "wiredConnections: no rows");

    // Each row restores its chosen marker and feeds readings, [present, on,
    // wired devices], in order; writes holds whether each one starts a pass.
    const W = "enp10s0:true", P = true, A = false, ON = true, OFF = false;
    // [label, chosen, readings, writes]
    const WAKE_READINGS = [
        ["the first reading with the setting off writes nothing", false, [[P, OFF, W]], [false]],
        ["the first reading with the setting on writes", false, [[P, ON, W]], [true]],
        ["the first reading with no wired device writes nothing", false, [[A, ON, ""]], [false]],
        ["a device change with the setting never set writes nothing", false, [[P, OFF, W], [P, OFF, W + ",enp11s0:false"]], [false, false]],
        ["a device that appears after a turn on writes", false, [[A, OFF, ""], [A, ON, ""], [P, ON, W]], [false, false, true]],
        ["a device that comes back while on writes", false, [[P, ON, W], [A, ON, ""], [P, ON, W]], [true, false, true]],
        ["a device change while on writes", false, [[P, ON, W], [P, ON, "enp10s0:false"]], [true, true]],
        ["a turn on writes", false, [[P, OFF, W], [P, ON, W]], [false, true]],
        ["a turn off writes", false, [[P, ON, W], [P, OFF, W]], [true, true]],
        ["a device change after a turn off writes", false, [[P, ON, W], [P, OFF, W], [P, OFF, W + ",enp11s0:false"]], [true, true, true]],
        ["a restart with a chosen Off writes a connection added later", true, [[P, OFF, W], [P, OFF, W + ",enp11s0:false"]], [true, true]],
        ["a restart with a chosen Off waits for a wired device", true, [[A, OFF, ""], [P, OFF, W]], [false, true]],
        ["a chosen Off with nothing changed writes nothing", true, [[P, OFF, W], [P, OFF, W]], [true, false]],
        ["a reading with nothing changed writes nothing", false, [[P, ON, W], [P, ON, W]], [true, false]],
        ["a turn off with no wired device writes once one comes back", false, [[P, ON, W], [A, ON, ""], [A, OFF, ""], [P, OFF, W]], [true, false, false, true]],
        ["a turn on and off with no wired device writes nothing once one appears", false, [[P, OFF, W], [A, OFF, ""], [A, ON, ""], [A, OFF, ""], [P, OFF, W]], [false, false, false, false, false]]
    ];
    for (const [label, chosen, readings, writes] of WAKE_READINGS) {
        let state = logic.wakeInitial(chosen);
        const got = readings.map(([present, on, devices]) => {
            const result = logic.wakeObserved(state, present, on, devices);
            state = result.state;
            return result.write;
        });
        same(got, writes, "wakeObserved: " + label);
    }

    for (const on of [true, false]) {
        assert.equal(logic.wakeProblemText("", on), "", "wakeProblemText: a pass that failed nowhere has no text");
        for (const failure of ["list", "read", "write"])
            assert.ok(logic.wakeProblemText(failure, on).length > 0, "wakeProblemText: a failed " + failure + " has text");
        assert.throws(() => logic.wakeProblemText("other", on), "wakeProblemText: an unknown failure is refused");
    }
}

verify(load(file));

const CONTROLS = [
    ["gamepad wake is disabled", "return { state: \"supported\", current: fields.WakeAllowed === \"true\", allowed: allowed };", "return { state: \"supported\", current: fields.WakeAllowed === \"true\", allowed: true };"],
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
    ["a source change with no battery applies nothing", "return { state: { ready: true, onBattery: onBattery === true }, apply: batteryPresent === true };", "return { state: { ready: true, onBattery: onBattery === true }, apply: true };"],
    ["off writes none", "    off: \"none\"\n", "    off: \"ignore\"\n"],
    ["the first pass waits for the setting on", "return { present: false, wired: \"\", written: false, chosen: chosen === true };", "return { present: false, wired: \"\", written: null, chosen: chosen === true };"],
    ["the state keeps the setting the last pass wrote", "written: write ? reading.on : previous.written", "written: reading.on"],
    ["a device change waits for a chosen value", "(previous.chosen && moved)", "moved"],
    ["a restart restores the chosen marker", "chosen: chosen === true", "chosen: false"],
    ["a wired list keeps the wired rows alone", "fields.length === 2 && fields[0] !== \"\" && fields[1] === \"802-3-ethernet\"", "fields.length === 2 && fields[0] !== \"\""],
    ["first ready source reading does not apply", "if (state.ready !== true) return { state: { ready: true, onBattery: onBattery === true }, apply: false };", "if (state.ready !== true) return { state: { ready: true, onBattery: onBattery === true }, apply: true };"]
];

const source = fs.readFileSync(file, "utf8");
const controlRoot = fs.mkdtempSync(path.join(os.tmpdir(), "test-power-logic-controls-"));
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
