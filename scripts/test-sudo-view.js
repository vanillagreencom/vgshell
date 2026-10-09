#!/usr/bin/env node
// The Passwordless Sudo widget's view, shell/plugins/vgs.sudo/SudoView.js,
// under node: which state reads as on, the icon, tone and tooltip each
// state takes, with only no grant read as off and a failed read and NixOS
// each its own, and which notification, if any, each ended grant or revoke
// sends: none when the run changed nothing, the warning one naming the time
// left and the clock time for a timed grant, the warning one for an
// indefinite grant, the success one for a grant turned off, the danger one
// for a revoke that left the grant on, and the unknown one when the read
// after the run failed. The controls at the end edit a copy of the view,
// one rule at a time, and require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.sudo", "SudoView.js");
// The view runs in its own context; values are compared as JSON.
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message);
const timeOf = iso => "at " + iso;
const NOW = Date.parse("2026-10-08T14:00:00Z");
const timed = minutes => new Date(NOW + minutes * 60000).toISOString().replace(/\.000Z$/, "Z");
const state = (s, until) => ({ state: s, until: until === undefined ? "" : until, rootHalf: "current" });

function verify(view) {
    // durationText: [minutes, words].
    for (const [minutes, want] of [[1, "1 minute"], [15, "15 minutes"], [59, "59 minutes"], [60, "1 hour"], [61, "1 hour 1 minute"], [90, "1 hour 30 minutes"], [120, "2 hours"], [1439, "23 hours 59 minutes"], [1440, "1 day"]])
        same(view.durationText(minutes), want, "durationText " + minutes);

    // active, look and tooltip: [name, state, active, [icon, tone], tooltip
    // kind]. The kind is `off`, the one tooltip no grant shows; `unknown`
    // and `nixos`, each its own and never off; `clock`, the deadline's
    // time; `until-off`, an indefinite grant's, which names no time.
    const tips = [
        ["no read yet", null, false, ["circle-question-mark", "neutral"], "unknown"],
        ["unknown", state("unknown"), false, ["circle-question-mark", "neutral"], "unknown"],
        ["no root half", state("absent"), false, ["lock", "bar"], "off"],
        ["inactive", state("inactive"), false, ["lock", "bar"], "off"],
        ["NixOS", state("nixos"), false, ["snowflake", "info"], "nixos"],
        ["timed", state("active", timed(60)), true, ["lock-open", "warning"], "clock"],
        ["indefinite", state("active", "indefinite"), true, ["lock-open", "warning"], "until-off"],
    ];
    const tipOf = {
        off: view.tooltip(state("inactive"), timeOf),
        unknown: view.tooltip(state("unknown"), timeOf),
        nixos: view.tooltip(state("nixos"), timeOf),
    };
    assert.equal(new Set(Object.values(tipOf)).size, 3, "the off, unknown and NixOS tooltips are three: " + JSON.stringify(tipOf));
    for (const [name, s, active, look, kind] of tips) {
        same(view.active(s), active, "active: " + name);
        same([view.look(s).icon, view.look(s).tone], look, "look: " + name);
        const tip = view.tooltip(s, timeOf);
        if (kind === "clock") {
            assert.ok(tip.endsWith(timeOf(s.until)), "tooltip " + name + " ends with the clock time: " + tip);
            assert.ok(!Object.values(tipOf).includes(tip), "tooltip " + name + " is its own");
        } else if (kind === "until-off") {
            assert.ok(!Object.values(tipOf).includes(tip) && tip.indexOf(timeOf(s.until)) === -1, "tooltip " + name + " names no clock time: " + tip);
        } else {
            same(tip, tipOf[kind], "tooltip " + name);
        }
    }

    // notice: [name, action, before, result, want], want null or
    // [tone, icon, the words the message must hold].
    const notices = [
        ["a declined grant", "grant", "inactive", state("inactive"), null],
        ["a cancelled first grant", "grant", "absent", state("absent"), null],
        ["a failed read after a grant", "grant", "inactive", state("unknown"), ["warning", "circle-question-mark", []]],
        ["a failed read after a revoke", "revoke", "active", state("unknown"), ["warning", "circle-question-mark", []]],
        ["a NixOS grant run", "grant", "nixos", state("nixos"), null],
        ["a grant of 1 hour", "grant", "inactive", state("active", timed(60)), ["warning", "lock-open", [view.durationText(60), timeOf(timed(60))]]],
        ["a grant read 20 s late", "grant", "inactive", state("active", timed(15 - 1 / 3)), ["warning", "lock-open", [view.durationText(15)]]],
        ["a grant whose window stayed open 2 minutes", "grant", "inactive", state("active", timed(58)), ["warning", "lock-open", [view.durationText(58)]]],
        ["a first grant", "grant", "absent", state("active", timed(1440)), ["warning", "lock-open", [view.durationText(1440)]]],
        ["an indefinite grant", "grant", "inactive", state("active", "indefinite"), ["warning", "lock-open", []]],
        ["a grant run that revoked", "grant", "active", state("inactive"), ["success", "lock", []]],
        ["a grant run on an active grant that failed", "grant", "active", state("active", "indefinite"), null],
        ["a revoke", "revoke", "active", state("inactive"), ["success", "lock", []]],
        ["a revoke that left the grant on", "revoke", "active", state("active", "indefinite"), ["danger", "lock-open", []]],
        ["a revoke that left a timed grant on", "revoke", "active", state("active", timed(10)), ["danger", "lock-open", []]],
    ];
    for (const [name, action, before, result, want] of notices) {
        const got = view.notice(action, before, result, NOW, timeOf);
        if (want === null) {
            same(got, null, "notice: " + name);
            continue;
        }
        assert.ok(got !== null, "notice: " + name + " sends one");
        same([got.tone, got.icon], want.slice(0, 2), "notice: " + name);
        assert.ok(typeof got.title === "string" && got.title.length > 0, "notice: " + name + " has a title");
        for (const words of want[2]) assert.ok(got.message.indexOf(words) !== -1, "notice: " + name + " names " + words + ": " + got.message);
    }
    const on = view.notice("grant", "inactive", state("active", "indefinite"), NOW, timeOf);
    const timedOn = view.notice("grant", "inactive", state("active", timed(60)), NOW, timeOf);
    assert.notEqual(on.message, timedOn.message, "the indefinite grant's message is its own");
    assert.ok(on.message.indexOf(timeOf("indefinite")) === -1 && !/[0-9]/.test(on.message), "the indefinite grant's message names no time: " + on.message);
    same(on.title, timedOn.title, "both grants share the on title");
    const off = view.notice("revoke", "active", state("inactive"), NOW, timeOf);
    const still = view.notice("revoke", "active", state("active", "indefinite"), NOW, timeOf);
    assert.notEqual(off.title, still.title, "a revoke that failed is titled apart");
}

verify(load(file));

// Each control removes one rule from a copy of the view and keeps the text
// around it. The suite must fail on every copy.
const CONTROLS = [
    ["only no grant reads as off", '    return "unknown";\n}\n\n// The lock\'s icon', '    return "off";\n}\n\n// The lock\'s icon'],
    ["NixOS is not off", '    case "nixos": return "nixos";\n', ''],
    ["a failed read after a run is not silent", 'if (kind(result) === "unknown")\n        return', 'if (false)\n        return'],
    ["only an active read is on", 'return state !== null && state.state === "active";', "return state !== null;"],
    ["an indefinite tooltip is its own", 'if (state.until === "indefinite")\n        return "Passwordless sudo is on until you turn it off";', ""],
    ["a revoke that left the grant on says so", 'if (action === "revoke" && on)', "if (false)"],
    ["a run that changed nothing sends nothing", 'if (before === "active" || !on)\n        return null;', 'if (before === "active")\n        return null;'],
    ["a grant names the time left", "Math.round((Date.parse(result.until) - nowMs) / 60000)", "15"],
    ["an indefinite grant is its own message", 'if (result.until === "indefinite")\n        return', "if (false)\n        return"],
    ["a day is a day", 'if (minutes === 1440)\n        return "1 day";', ""],
];
const source = fs.readFileSync(file, "utf8");
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "sudo-view-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const copy = path.join(temp, "SudoView.js");
        fs.writeFileSync(copy, source.replace(needle, () => replacement));
        let failed = false;
        try {
            verify(load(copy));
        } catch (e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the suite passed on a view without that rule`);
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
console.log(`test-sudo-view: ok controls=${CONTROLS.length}`);
