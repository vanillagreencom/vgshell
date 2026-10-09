#!/usr/bin/env node
// Table-driven checks for vgs.mouse's pure decisions, MouseLogic.js, and
// its manifest's Hyprland option map. Expected values are written here by
// hand. Controls edit one rule at a time in a copy and require this suite
// to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const repo = path.join(__dirname, "..");
const logicFile = path.join(repo, "shell", "plugins", "vgs.mouse", "MouseLogic.js");
const manifestFile = path.join(repo, "shell", "plugins", "vgs.mouse", "manifest.json");
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), JSON.parse(JSON.stringify(want)), message);

const OPTION_PATHS = {
    sensitivity: "input.sensitivity",
    accelProfile: "input.accel_profile",
    naturalScroll: "input.natural_scroll",
    leftHanded: "input.left_handed",
    scrollFactor: "input.scroll_factor",
    tapToClick: "input.touchpad.tap_to_click",
    touchpadNaturalScroll: "input.touchpad.natural_scroll",
    disableWhileTyping: "input.touchpad.disable_while_typing",
    clickMethod: "input.touchpad.clickfinger_behavior",
    touchpadScrollFactor: "input.touchpad.scroll_factor",
    touchpadEnabled: "device.touchpad.enabled"
};

const DEVICES = { mice: [
    { name: "logitech-usb-mouse", touchpad: false },
    { name: "elan-touchpad", touchpad: true }
] };

function verify(logic) {
    const manifestOptions = JSON.parse(fs.readFileSync(manifestFile, "utf8")).hyprland.options;
    same(manifestOptions, OPTION_PATHS, "manifest option map");

    assert.equal(logic.hasTouchpad(DEVICES), true, "hasTouchpad: present");
    assert.equal(logic.hasTouchpad({ mice: [{ name: "usb", touchpad: false }] }), false, "hasTouchpad: absent");
    assert.equal(logic.hasTouchpad(null), false, "hasTouchpad: unread");
    same(logic.mice(DEVICES), [
        { name: "logitech-usb-mouse", touchpad: false },
        { name: "elan-touchpad", touchpad: true }
    ], "mice: normalized list");
    same(logic.deviceRows(DEVICES), [
        { key: "logitech-usb-mouse", text: "logitech-usb-mouse", secondary: "Pointer", icon: "mouse", badge: "Pointer" },
        { key: "elan-touchpad", text: "elan-touchpad", secondary: "Touchpad", icon: "touchpad", badge: "Touchpad" }
    ], "deviceRows: rows");
    same(logic.statusValue(DEVICES), { hasTouchpad: true, devices: logic.deviceRows(DEVICES) }, "statusValue: data entry");
    same(logic.overriddenMap(["input.sensitivity", "input.left_handed"]), { "input.sensitivity": true, "input.left_handed": true }, "overriddenMap");
    assert.equal(logic.rowOverridden(["input.sensitivity"], manifestOptions, "sensitivity"), true, "rowOverridden: yes");
    assert.equal(logic.rowOverridden(["input.sensitivity"], manifestOptions, "naturalScroll"), false, "rowOverridden: no");
    assert.equal(logic.rowOverridden(["input.sensitivity"], {}, "sensitivity"), false, "rowOverridden: missing map");
    assert.equal(logic.overriddenText(["input.sensitivity"], manifestOptions, "sensitivity"), "Overridden by your Hyprland config", "overriddenText: yes");
    assert.equal(logic.overriddenText([], manifestOptions, "sensitivity"), "", "overriddenText: no");
    const USER_VALUES = [{ path: "input.sensitivity", value: -0.5 }, { path: "input.natural_scroll", value: true }, { path: "input.left_handed", value: false }, { path: "input.scroll_factor", value: 1.5 }, { path: "input.accel_profile", value: "flat" }];
    assert.equal(logic.userValue(USER_VALUES, manifestOptions, "sensitivity"), -0.5, "userValue: a number");
    assert.equal(logic.userValue(USER_VALUES, manifestOptions, "leftHanded"), false, "userValue: false is a value");
    assert.equal(logic.userValue(USER_VALUES, manifestOptions, "tapToClick"), undefined, "userValue: an option the list does not name");
    assert.equal(logic.userValue(null, manifestOptions, "sensitivity"), undefined, "userValue: unread");
    assert.equal(logic.userValue(USER_VALUES, {}, "sensitivity"), undefined, "userValue: missing map");
    same(["sensitivity", "leftHanded", "tapToClick"].map(key => logic.hasUserValue(USER_VALUES, manifestOptions, key)), [true, true, false], "hasUserValue");
    same([logic.valueText("sensitivity", 0.25), logic.valueText("scrollFactor", 0.25)], ["+0.25×", "0.25×"], "valueText: pointer speed and a factor read as their rows do");
    same([logic.valueText("sensitivity", -0.5), logic.valueText("scrollFactor", 1.5), logic.valueText("naturalScroll", true), logic.valueText("leftHanded", false), logic.valueText("accelProfile", "flat")], ["-0.50×", "1.50×", "on", "off", "flat"], "valueText: each value as its row shows it");
    // The line names the user's value; the sentence around it is not pinned.
    const line = key => logic.warningText(["input.sensitivity", "input.touchpad.tap_to_click"], USER_VALUES, manifestOptions, key);
    assert.ok(line("sensitivity").endsWith(logic.valueText("sensitivity", -0.5)) && line("sensitivity") !== logic.overriddenText(["input.sensitivity"], manifestOptions, "sensitivity"), "warningText: the user's value takes the line over the overridden one");
    assert.ok(line("leftHanded").endsWith("off"), "warningText: a false user value has a line");
    assert.equal(line("tapToClick"), logic.overriddenText(["input.touchpad.tap_to_click"], manifestOptions, "tapToClick"), "warningText: an overridden row with no user value keeps the overridden line");
    assert.equal(line("disableWhileTyping"), "", "warningText: a row with neither has no line");
    // After Use my Hyprland value VGS sets none, the capability names the
    // user's +0.20 and the setting reads its manifest default, 0.
    const SETTINGS = { sensitivity: 0, naturalScroll: true, scrollFactor: 1 };
    const LIVE = { "input.sensitivity": 0.2, "input.natural_scroll": false };
    // rows: [name, values, key, want]
    const shown = [
        ["Hyprland's value while VGS sets none", LIVE, "sensitivity", 0.2],
        ["a false Hyprland value is a value", LIVE, "naturalScroll", false],
        ["the setting where the capability names no value", LIVE, "scrollFactor", 1],
        ["the setting while unread", null, "sensitivity", 0]
    ];
    for (const [name, values, key, want] of shown) assert.equal(logic.shownValue(values, SETTINGS, manifestOptions, key), want, "shownValue: " + name);
    assert.equal(logic.pointerSpeedText(logic.shownValue(LIVE, SETTINGS, manifestOptions, "sensitivity")), "+0.20×", "shownValue: the pointer speed row reads the user's value");
    assert.equal(logic.pointerSpeedText(0.25), "+0.25×", "pointerSpeedText: positive");
    assert.equal(logic.pointerSpeedText(-0.5), "-0.50×", "pointerSpeedText: negative");
    assert.equal(logic.pointerSpeedText("x"), "0.00×", "pointerSpeedText: bad");
    assert.equal(logic.factorText(1.25), "1.25×", "factorText: value");
    assert.equal(logic.factorText("x"), "1.00×", "factorText: bad");
    assert.equal(logic.profileIndex("flat"), 1, "profileIndex: flat");
    assert.equal(logic.profileIndex("adaptive"), 0, "profileIndex: adaptive");
    assert.equal(logic.profileAt(1), "flat", "profileAt: flat");
    assert.equal(logic.profileAt(0), "adaptive", "profileAt: adaptive");
}

verify(load(logicFile));

const CONTROLS = [
    ["touchpad presence", `return mice(devices).some(function (mouse) { return mouse.touchpad; });`, `return false;`],
    ["device row icon", `icon: mouse.touchpad ? "touchpad" : "mouse"`, `icon: "mouse"`],
    ["status carries touchpad flag", `return { hasTouchpad: hasTouchpad(devices), devices: rows };`, `return { hasTouchpad: false, devices: rows };`],
    ["overridden map", `for (var i = 0; i < paths.length; i++) out[paths[i]] = true;`, `for (var i = 0; i < paths.length; i++) out[i] = true;`],
    ["overridden path lookup", `return path !== undefined && overriddenMap(paths)[path] === true;`, `return overriddenMap(paths)[key] === true;`],
    ["overridden text", `return rowOverridden(paths, options, key) ? "Overridden by your Hyprland config" : "";`, `return "";`],
    ["user value path lookup", `if (values[i].path === path) return values[i].value;`, `if (values[i].path === key) return values[i].value;`],
    ["a false user value is a value", `return userValue(values, options, key) !== undefined;`, `return !!userValue(values, options, key);`],
    ["a switch value reads on or off", `if (typeof value === "boolean") return value ? "on" : "off";`, `if (typeof value === "boolean") return String(value);`],
    ["pointer speed reads as its row does", `return key === "sensitivity" ? pointerSpeedText(value) : factorText(value);`, `return factorText(value);`],
    ["the user's value takes the line", `if (value !== undefined) return "Hyprland config sets " + valueText(key, value);`, `if (value) return "Hyprland config sets " + valueText(key, value);`],
    ["a row with no user value keeps the overridden line", `    return overriddenText(paths, options, key);\n}\n\nfunction pointerSpeedText`, `    return "";\n}\n\nfunction pointerSpeedText`],
    ["the row reads Hyprland's value while VGS sets none", `if (values !== null && values !== undefined && path !== undefined && Object.prototype.hasOwnProperty.call(values, path)) return values[path];`, ``],
    ["the value is found by the setting's option path", `Object.prototype.hasOwnProperty.call(values, path)) return values[path];`, `Object.prototype.hasOwnProperty.call(values, key)) return values[key];`],
    ["pointer speed sign", `return (n > 0 ? "+" : "") + n.toFixed(2) + "×";`, `return n.toFixed(2) + "×";`],
    ["factor default", `if (!isFinite(n)) n = 1;`, `if (!isFinite(n)) n = 0;`],
    ["profile index", `return value === "flat" ? 1 : 0;`, `return 0;`],
    ["profile value", `return index === 1 ? "flat" : "adaptive";`, `return "adaptive";`]
];

const source = fs.readFileSync(logicFile, "utf8");
const tempRoot = path.join(repo, "tmp");
fs.mkdirSync(tempRoot, { recursive: true });
const temp = fs.mkdtempSync(path.join(tempRoot, "mouse-logic-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const mutant = path.join(temp, "MouseLogic.js");
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
    fs.rmSync(temp, { recursive: true, force: true });
}
console.log(`test-mouse-logic: ok controls=${CONTROLS.length}`);
