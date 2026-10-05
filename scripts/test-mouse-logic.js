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
const pluginLogicFile = path.join(repo, "shell", "Core", "PluginLogic.js");
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

function manifestWithOptions(options) {
    const manifest = JSON.parse(fs.readFileSync(manifestFile, "utf8"));
    manifest.hyprland.options = options;
    return manifest;
}

function verify(logic) {
    same(logic.OPTION_PATHS, OPTION_PATHS, "MouseLogic option map");
    same(JSON.parse(fs.readFileSync(manifestFile, "utf8")).hyprland.options, OPTION_PATHS, "manifest option map");

    const pluginLogic = load(pluginLogicFile);
    const judged = pluginLogic.validateManifest(JSON.parse(fs.readFileSync(manifestFile, "utf8")), "shell/plugins/vgs.mouse");
    assert.equal(judged.ok, true, judged.error);
    const section = pluginLogic.hyprlandSection({ plugins: [{ id: "vgs.mouse", sensitivity: 0.25, naturalScroll: true }] }, judged.manifest);
    same(section.options, [
        { kind: "set", setting: "sensitivity", path: "input.sensitivity", value: 0.25, lua: "0.25" },
        { kind: "set", setting: "naturalScroll", path: "input.natural_scroll", value: true, lua: "true" }
    ], "PluginLogic writes only options the plugins row sets");
    const badMap = pluginLogic.validateManifest(manifestWithOptions(Object.assign({}, OPTION_PATHS, { leftHanded: "input.natural_scroll" })), "shell/plugins/vgs.mouse");
    assert.equal(badMap.ok, false, "duplicate option map must fail");
    assert.match(badMap.error, /sets input\.natural_scroll, which another setting sets already/, "duplicate option map error");

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
    assert.equal(logic.rowOverridden(["input.sensitivity"], "sensitivity"), true, "rowOverridden: yes");
    assert.equal(logic.rowOverridden(["input.sensitivity"], "naturalScroll"), false, "rowOverridden: no");
    assert.equal(logic.overriddenText(["input.sensitivity"], "sensitivity"), "Overridden by your Hyprland config", "overriddenText: yes");
    assert.equal(logic.overriddenText([], "sensitivity"), "", "overriddenText: no");
    assert.equal(logic.pointerSpeedText(0.25), "+0.25×", "pointerSpeedText: positive");
    assert.equal(logic.pointerSpeedText(-0.5), "-0.50×", "pointerSpeedText: negative");
    assert.equal(logic.pointerSpeedText("x"), "0.00×", "pointerSpeedText: bad");
    assert.equal(logic.factorText(1.25), "1.25×", "factorText: value");
    assert.equal(logic.factorText("x"), "1.00×", "factorText: bad");
    assert.equal(logic.profileIndex("flat"), 1, "profileIndex: flat");
    assert.equal(logic.profileIndex("adaptive"), 0, "profileIndex: adaptive");
    assert.equal(logic.profileAt(1), "flat", "profileAt: flat");
    assert.equal(logic.profileAt(0), "adaptive", "profileAt: adaptive");
    assert.equal(logic.replyProblem("refused: setting"), true, "replyProblem: refused");
    assert.equal(logic.replyProblem("unknown: field"), true, "replyProblem: unknown");
    assert.equal(logic.replyProblem("ok"), false, "replyProblem: ok");
}

verify(load(logicFile));

const CONTROLS = [
    ["touchpad presence", `return mice(devices).some(function (mouse) { return mouse.touchpad; });`, `return false;`],
    ["device row icon", `icon: mouse.touchpad ? "touchpad" : "mouse"`, `icon: "mouse"`],
    ["status carries touchpad flag", `return { hasTouchpad: hasTouchpad(devices), devices: rows };`, `return { hasTouchpad: false, devices: rows };`],
    ["overridden map", `for (var i = 0; i < paths.length; i++) out[paths[i]] = true;`, `for (var i = 0; i < paths.length; i++) out[i] = true;`],
    ["overridden text", `return rowOverridden(paths, key) ? "Overridden by your Hyprland config" : "";`, `return "";`],
    ["pointer speed sign", `return (n > 0 ? "+" : "") + n.toFixed(2) + "×";`, `return n.toFixed(2) + "×";`],
    ["factor default", `if (!isFinite(n)) n = 1;`, `if (!isFinite(n)) n = 0;`],
    ["profile index", `return value === "flat" ? 1 : 0;`, `return 0;`],
    ["profile value", `return index === 1 ? "flat" : "adaptive";`, `return "adaptive";`],
    ["reply refusal", `return /^(refused|unknown|error):/.test(String(reply));`, `return /^(unknown|error):/.test(String(reply));`],
    ["logic option map", `sensitivity: "input.sensitivity"`, `sensitivity: "input.left_handed"`]
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
