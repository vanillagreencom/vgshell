#!/usr/bin/env node
// Table-driven checks for vgs.power's pure decisions, PowerLogic.js:
// battery presence, battery and profile views, icon bands, time text,
// the profile view read from the daemon's reply, source-change profile
// choice, the setting a bar pick remembers, low-battery latches and the
// notice each latch sends, the logind resume signal line, and Wake on
// LAN's flag values, wired connection list and write rule; the power
// menu's availability reads, their replies and offers, and its 3000 ms
// confirmation hold over injected time.
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
    for (const [code, text, allowed] of [
        [0, "('yes',)", true], [0, "('yes',)\n", true],
        [0, "('no',)", false], [0, "('na',)", false], [0, "('challenge',)", false],
        [1, "('yes',)", false], [-1, "('yes',)", false],
        [0, "yes", false], [0, "('yes',) extra", false], [0, "", false]
    ]) assert.equal(logic.sleepAllowed(code, text), allowed, `sleepAllowed: code=${code} text=${text}`);
    const sleepCases = [
        [{}, [], ["", "", ""]],
        [{ suspend: true }, ["suspend"], ["Suspend", "", ""]],
        [{ suspend: true, hibernate: true }, ["suspend", "hibernate"], ["Suspend", "Hibernate", ""]],
        [{ hibernate: true, "suspend-then-hibernate": true }, ["hibernate", "suspend-then-hibernate"], ["", "Hibernate", "SuspendThenHibernate"]]
    ];
    for (const [allowed, choices, methods] of sleepCases) {
        same(logic.sleepChoices(allowed).map(choice => choice.value), choices, "sleepChoices: yes-only offers");
        same(["suspend", "hibernate", "suspend-then-hibernate"].map(action => logic.sleepMethod(action, allowed)), methods, "sleepMethod: only supported fixed methods");
        assert.equal(logic.sleepMethod("reboot", allowed), "", "sleepMethod: unknown saved setting authorizes nothing");
    }
    const prepareForSleep = [
        ["the standard resume signal", "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,)", true],
        ["the standard sleep signal", "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)", false],
        ["a different logind signal", "/org/freedesktop/login1: org.freedesktop.login1.Manager.Sleeping (false,)", false],
        ["a line with a trailing payload", "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,) extra", false],
        ["a partial signal line", "org.freedesktop.login1.Manager.PrepareForSleep (false,)", false],
        ["an empty line", "", false],
        ["a missing line", null, false]
    ];
    for (const [label, line, want] of prepareForSleep)
        assert.equal(logic.isPrepareForSleepResume(line), want, "isPrepareForSleepResume: " + label);

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

    verifyMenu(logic);
}

// The power menu: which reads a pass makes, which replies offer an
// action, the published reading, and the 3000 ms hold over injected
// monotonic time.
function verifyMenu(logic) {
    const keysOf = reads => reads.map(read => read.key);
    same(keysOf(logic.availabilityReads("")), ["suspend", "hibernate", "suspend-then-hibernate", "reboot", "poweroff", "logout"],
        "availabilityReads: no seat path asks no display manager");
    for (const seat of [undefined, "relative/Seat0", "/org/freedesktop/DisplayManager/Seat0 extra", "/"])
        assert.ok(keysOf(logic.availabilityReads(seat)).indexOf("switch-user") === -1, "availabilityReads: no read for seat " + seat);
    const seatRead = logic.availabilityReads("/org/freedesktop/DisplayManager/Seat0").find(read => read.key === "switch-user");
    same(seatRead.args, ["--system", "--dest", "org.freedesktop.DisplayManager", "--object-path", "/org/freedesktop/DisplayManager/Seat0",
        "--method", "org.freedesktop.DBus.Properties.Get", "org.freedesktop.DisplayManager.Seat", "CanSwitch"], "availabilityReads: the seat's CanSwitch");
    same(logic.availabilityReads("").find(read => read.key === "reboot").args.slice(-1), ["org.freedesktop.login1.Manager.CanReboot"], "availabilityReads: reboot asks CanReboot");
    same(logic.availabilityReads("").find(read => read.key === "poweroff").args.slice(-1), ["org.freedesktop.login1.Manager.CanPowerOff"], "availabilityReads: poweroff asks CanPowerOff");
    same(logic.availabilityReads("").find(read => read.key === "logout").args.slice(4), ["/org/freedesktop/login1/user/self",
        "--method", "org.freedesktop.DBus.Properties.Get", "org.freedesktop.login1.User", "Display"], "availabilityReads: logout asks the user's Display");

    for (const [judge, code, text, want] of [
        ["can", 0, "('yes',)", true], ["can", 0, "('challenge',)", false],
        ["session", 0, "(<('2', objectpath '/org/freedesktop/login1/session/_32')>,)\n", true],
        ["session", 0, "(<('c1', objectpath '/org/freedesktop/login1/session/c1')>,)", true],
        ["session", 0, "(<('', objectpath '/')>,)", false],
        ["session", 1, "(<('2', objectpath '/org/freedesktop/login1/session/_32')>,)", false],
        ["session", 0, "", false],
        ["true", 0, "(<true>,)\n", true], ["true", 0, "(<false>,)", false], ["true", 1, "(<true>,)", false], ["true", 0, "true", false]
    ]) assert.equal(logic.readAnswer(judge, code, text), want, `readAnswer: ${judge} code=${code} text=${text}`);
    assert.throws(() => logic.readAnswer("other", 0, ""), "readAnswer: an unknown judge is refused");

    const every = { logout: true, suspend: true, hibernate: true, "suspend-then-hibernate": true, reboot: true, poweroff: true, "switch-user": true };
    same(logic.actionsView(0, false, every), { state: "checking", offered: [] }, "actionsView: nothing before the first pass");
    same(logic.actionsView(1, false, every), { state: "failed", offered: [] }, "actionsView: a pass with no answer is failed");
    same(logic.actionsView(2, true, every).offered, ["logout", "suspend", "hibernate", "reboot", "poweroff", "switch-user"], "actionsView: menu order");
    same(logic.actionsView(1, true, { reboot: true, suspend: false, poweroff: true, "suspend-then-hibernate": true }),
        { state: "ready", offered: ["reboot", "poweroff"] }, "actionsView: only true offers, and no menu row for suspend then hibernate");
    const notices = {};
    for (const [id, kind] of [["reboot", "busy"], ["logout", "failed"], ["other", "unavailable"]]) {
        const notice = logic.actionFailurePayload(id, kind);
        notices[kind] = notice.message;
        assert.equal(notice.tone, "danger", "actionFailurePayload: a failed action is danger: " + id);
        assert.ok(typeof notice.title === "string" && notice.title.length > 0 && typeof notice.message === "string" && notice.message.length > 0, "actionFailurePayload: a notice has its text: " + id);
    }
    assert.equal(new Set(Object.values(notices)).size, 3, "actionFailurePayload: each kind has its own message");
    assert.throws(() => logic.actionFailurePayload("reboot", "argv=[] exit=1 stderr=\"reason=busy\""), "actionFailurePayload: a log line is no kind");
    same(logic.POWER_ACTIONS.map(action => action.label), ["Log out", "Suspend", "Hibernate", "Reboot", "Shut down", "Switch user"], "POWER_ACTIONS: titles");

    // Each row is [event, ...arguments]; a press carries its own time
    // and `at` asks whether the hold fires at that time, then reads the
    // phase and the fill.
    const press = (t, source, action) => ["pressAt", source, action, t];
    const play = rows => {
        let hold = logic.holdIdle();
        const fired = [];
        const trace = [];
        for (const row of rows) {
            const [event, a, b, t] = row;
            if (event === "pressAt") hold = logic.holdPress(hold, a, b, t);
            else if (event === "release") hold = logic.holdRelease(hold, a);
            else if (event === "cancel") hold = logic.holdCancel(hold);
            else if (event === "at") {
                const result = logic.holdFire(hold, a);
                hold = result.hold;
                if (result.fire !== "") fired.push([result.fire, a]);
                trace.push([a, hold.phase, logic.holdProgress(hold, a)]);
            } else throw new Error("unknown step " + event);
        }
        return { fired, trace, phase: hold.phase };
    };
    const HOLDS = [
        ["fires only at 3000 ms of continuous hold",
            [press(0, "key:space", "reboot"), ["at", 1500], ["at", 2999], ["at", 3000], ["at", 3500]],
            [["reboot", 3000]], [[1500, "holding", 0.5], [2999, "holding", 2999 / 3000], [3000, "spent", 1], [3500, "spent", 1]], "spent"],
        ["fractional time: 2999.9 ms held is not yet due",
            [press(0.4, "key:space", "reboot"), ["at", 3000.3], ["at", 3000.4]],
            [["reboot", 3000.4]], [[3000.3, "holding", 2999.9 / 3000], [3000.4, "spent", 1]], "spent"],
        ["a timer that runs late fires once, late",
            [press(100, "pointer", "logout"), ["at", 3400], ["at", 3401]],
            [["logout", 3400]], [[3400, "spent", 1], [3401, "spent", 1]], "spent"],
        ["a release one millisecond early fires nothing",
            [press(0, "key:return", "poweroff"), ["at", 2000], ["release", "key:return"], ["at", 3000], ["at", 6000]],
            [], [[2000, "holding", 2000 / 3000], [3000, "idle", 0], [6000, "idle", 0]], "idle"],
        ["a release just before the deadline fires nothing",
            [press(0, "key:space", "suspend"), ["at", 2999], ["release", "key:space"], ["at", 3000]],
            [], [[2999, "holding", 2999 / 3000], [3000, "idle", 0]], "idle"],
        ["a cancel, for Escape or focus loss, fires nothing and needs a fresh press",
            [press(0, "key:space", "logout"), ["at", 1000], ["cancel"], ["at", 3000], press(3500, "key:space", "logout"), ["at", 6500],
                ["release", "key:space"], press(7000, "key:space", "logout"), ["at", 9999], ["at", 10000]],
            [["logout", 10000]], [[1000, "holding", 1000 / 3000], [3000, "spent", 0], [6500, "spent", 0], [9999, "holding", 2999 / 3000], [10000, "spent", 1]], "spent"],
        ["no selected action starts no hold",
            [press(0, "key:space", ""), ["at", 3000], ["at", 9000]],
            [], [[3000, "idle", 0], [9000, "idle", 0]], "idle"],
        ["a repeated press of the held source adds no time",
            [press(0, "key:space", "reboot"), press(1000, "key:space", "reboot"), press(2000, "key:space", "reboot"), ["at", 3000]],
            [["reboot", 3000]], [[3000, "spent", 1]], "spent"],
        ["a second source cancels, and both must be released",
            [press(0, "key:space", "reboot"), press(1000, "key:return", "reboot"), ["at", 3000], ["release", "key:space"],
                press(3100, "key:space", "reboot"), ["release", "key:space"], ["at", 6100], ["release", "key:return"],
                press(6200, "pointer", "reboot"), ["at", 9199], ["at", 9200]],
            [["reboot", 9200]], [[3000, "spent", 0], [6100, "spent", 0], [9199, "holding", 2999 / 3000], [9200, "spent", 1]], "spent"],
        ["a fired hold stays spent until its source is released",
            [press(0, "key:space", "suspend"), ["at", 3000], press(3100, "key:space", "suspend"), ["at", 6100], ["release", "key:space"], ["at", 6200]],
            [["suspend", 3000]], [[3000, "spent", 1], [6100, "spent", 1], [6200, "idle", 0]], "idle"],
        ["a refusal after firing clears the fill",
            [press(0, "pointer", "hibernate"), ["at", 3000], ["cancel"], ["at", 3001]],
            [["hibernate", 3000]], [[3000, "spent", 1], [3001, "spent", 0]], "spent"],
        ["a release of a key the hold never saw changes nothing",
            [press(0, "key:space", "logout"), ["release", "key:return"], ["at", 3000]],
            [["logout", 3000]], [[3000, "spent", 1]], "spent"]
    ];
    for (const [label, rows, fired, trace, phase] of HOLDS) {
        const got = play(rows);
        same(got.fired, fired, "hold fires: " + label);
        same(got.trace, trace, "hold trace: " + label);
        assert.equal(got.phase, phase, "hold phase: " + label);
    }
    assert.equal(logic.holdRemaining(logic.holdIdle(), 0), -1, "holdRemaining: no hold");
    assert.equal(logic.holdRemaining(logic.holdPress(logic.holdIdle(), "pointer", "reboot", 500), 1500), 2000, "holdRemaining: the rest of the 3000 ms");
    assert.throws(() => logic.holdPress({ phase: "other" }, "pointer", "reboot", 0), "holdPress: an unknown phase is refused");
}

verify(load(file));

const CONTROLS = [
    ["the hold is exactly 3000 ms, not less", "var HOLD_MS = 3000;", "var HOLD_MS = 2999;"],
    ["the hold is exactly 3000 ms, not more", "var HOLD_MS = 3000;", "var HOLD_MS = 3001;"],
    ["a release ends the hold", "if (hold.phase === \"holding\") return source === hold.source ? holdIdle() : hold;", "if (hold.phase === \"holding\") return hold;"],
    ["a cancel fires nothing", "if (hold.phase === \"holding\") return { phase: \"spent\", held: [hold.source], fired: false };", "if (false) return { phase: \"spent\", held: [hold.source], fired: false };"],
    ["a repeated press keeps the start", "return source === hold.source ? hold : { phase: \"spent\", held: [hold.source, source], fired: false };", "return source === hold.source ? { phase: \"holding\", action: hold.action, source: source, start: now } : { phase: \"spent\", held: [hold.source, source], fired: false };"],
    ["a second source cancels the hold", "return source === hold.source ? hold : { phase: \"spent\", held: [hold.source, source], fired: false };", "return hold;"],
    ["every held source is released before a fresh hold", "return held.length === 0 ? holdIdle() : { phase: \"spent\", held: held, fired: hold.fired };", "return holdIdle();"],
    ["no selection starts no hold", "return action === \"\" ? hold : { phase: \"holding\"", "return false ? hold : { phase: \"holding\""],
    ["the fill is linear in the time held", "Math.max(0, (now - hold.start) / HOLD_MS)", "Math.max(0, Math.sqrt((now - hold.start) / HOLD_MS))"],
    ["a refusal clears a fired fill", "if (hold.phase === \"spent\") return { phase: \"spent\", held: hold.held, fired: false };", "if (false) return hold;"],
    ["a log out read needs a session id", "/^\\(<\\('[^']+', objectpath", "/^\\(<\\('[^']*', objectpath"],
    ["switch user needs a seat path", "if (/^(\\/[A-Za-z0-9_]+)+$/.test(String(seatPath)))", "if (true)"],
    ["switch user needs CanSwitch true", "if (judge === \"true\") return code === 0 && /^\\(<true>,\\)\\s*$/.test(String(text));", "if (judge === \"true\") return code === 0;"],
    ["a pass with no answer is failed", "if (!answered) return { state: \"failed\", offered: [] };", "if (false) return { state: \"failed\", offered: [] };"],
    ["each failure kind has its own message", "unavailable: \"This action is not available on this computer now.\",", "unavailable: \"Another power action is running. Wait for it to finish.\","],
    ["an unknown failure kind is refused", "if (!hasOwn(messages, kind)) throw", "if (false) throw"],
    ["the menu offers only allowed actions", "return allowed[action.id] === true; })\n        .map(function (action) { return action.id; })", "return true; })\n        .map(function (action) { return action.id; })"],
    ["sleep capability needs yes", "return code === 0 && /^\\('yes',\\)\\s*$/.test(String(text));", "return code === 0;"],
    ["sleep request needs the selected capability", "entry !== undefined && allowed[action] === true ? entry.method", "entry !== undefined ? entry.method"],
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
    const wakeHelper = /function isPrepareForSleepResume\(line\)\s*\{[\s\S]*?\n\}/g;
    const wakeMatches = [...source.matchAll(wakeHelper)];
    assert.equal(wakeMatches.length, 1, "control \"resume line is classified\": the helper body must occur once");
    const wakeMutant = path.join(controlRoot, "PowerLogic-resume-mutant.js");
    fs.writeFileSync(wakeMutant, source.replace(wakeHelper, "function isPrepareForSleepResume(line) {\n    return true;\n}"));
    let wakeFailed = false;
    try {
        verify(load(wakeMutant));
    } catch (e) {
        wakeFailed = true;
    }
    assert.ok(wakeFailed, "control \"resume line is classified\": the suite passed when every line was treated as a resume");
} finally {
    fs.rmSync(controlRoot, { recursive: true, force: true });
}
console.log(`test-power-logic: ok controls=${CONTROLS.length + 1}`);
