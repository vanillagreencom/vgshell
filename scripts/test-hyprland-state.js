#!/usr/bin/env node
// Checks for shell/Core/HyprlandState.js, the readings behind the
// `hyprland` capability, loaded under node through bin/lib/qml-library.js
// as the shell loads it. The replies are the shapes Hyprland v0.56.2
// printed in the nested sandbox.
//
// The controls at the end edit a copy of the file, one rule at a time, and
// the suite must fail on every copy. Exit 1 when a row or a control fails.
"use strict";
const fs = require("fs");
const path = require("path");
const { load } = require("../bin/lib/qml-library.js");

const STATE = path.join(__dirname, "..", "shell", "Core", "HyprlandState.js");

let failures = 0;
function report(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { console.log("  ok    " + name); return; }
    failures += 1;
    console.log("  FAIL  " + name + "\n        got  " + g + "\n        want " + w);
}

// `hyprctl -j devices` with one pointer and one keyboard, as the nested
// Hyprland printed it, with a touchpad, a trackpad and a keyboard with no
// active layout added.
const keyboard = (name, extra) => Object.assign({ address: "0x1", name: name, rules: "", model: "", layout: "us,de", variant: "", options: "", active_layout_index: 1, active_keymap: "German", capsLock: false, numLock: false, main: true }, extra || {});
const mouse = name => ({ address: "0x2", name: name, defaultSpeed: 0.0, scrollFactor: -1.0 });
const devicesText = (mice, keyboards) => JSON.stringify({ mice: mice, keyboards: keyboards, tablets: [], touch: [], switches: [] }, null, 4);
// A keyboard with no active layout prints its index bare (src/debug/HyprCtl.cpp).
const noLayoutText = devicesText([], [keyboard("hl-virtual-keyboard-wtype", { active_layout_index: 0, main: false })]).replace('"active_layout_index": 0', '"active_layout_index": none');

// A bind as `hyprctl -j binds` prints one.
const bind = (modmask, key, description, extra) => Object.assign({ locked: false, mouse: false, release: false, repeat: false, longPress: false, non_consuming: false, auto_consuming: false, has_description: description !== "", modmask: modmask, submap: "", submap_universal: "false", key: key, keycode: 0, catch_all: false, description: description, allow_input_capture: false, dispatcher: "__lua", arg: "5" }, extra || {});
const getoption = (option, field, value) => JSON.stringify({ option: option }).slice(0, -1) + ", \"" + field + "\": " + JSON.stringify(value) + ", \"set\": true }";

function suite(lib, check) {
    // rows: [name, text, want]
    const devices = [
        ["a pointer, a touchpad and a keyboard", devicesText([mouse("wl_pointer"), mouse("elan0676:00-04f3:3195-touchpad"), mouse("apple-inc.-magic-trackpad")], [keyboard("wl_keyboard")]), { ok: true, devices: {
            mice: [{ name: "wl_pointer", touchpad: false }, { name: "elan0676:00-04f3:3195-touchpad", touchpad: true }, { name: "apple-inc.-magic-trackpad", touchpad: true }],
            keyboards: [{ name: "wl_keyboard", layout: "us,de", variant: "", options: "", activeKeymap: "German", activeLayoutIndex: 1, main: true }]
        } }],
        ["a keyboard with no active layout", noLayoutText, { ok: true, devices: { mice: [], keyboards: [{ name: "hl-virtual-keyboard-wtype", layout: "us,de", variant: "", options: "", activeKeymap: "German", activeLayoutIndex: null, main: false }] } }],
        ["no JSON", "Couldn't connect to the socket", { ok: false, error: "refused: devices=unparsed " }],
        ["no keyboards list", JSON.stringify({ mice: [] }), { ok: false, error: "refused: devices=shape want=mice,keyboards" }],
        ["a pointer with no name", devicesText([{ address: "0x2" }], []), { ok: false, error: "refused: devices=shape mouse=0" }],
        ["a keyboard with no keymap", devicesText([], [keyboard("k", { active_keymap: 3 })]), { ok: false, error: "refused: devices=shape keyboard=0" }]
    ];
    for (const [name, text, want] of devices) {
        const got = lib.devicesState(text);
        check("devices: " + name, got.ok ? got : { ok: false, error: got.error.slice(0, want.ok ? 0 : want.error.length) }, want);
    }
    const listed = lib.devicesState(devices[0][1]).devices;
    check("touchpads: the pointers named touchpad or trackpad", lib.touchpads(listed), ["elan0676:00-04f3:3195-touchpad", "apple-inc.-magic-trackpad"]);
    check("touchpads: none read yet", lib.touchpads(null), null);
    check("devices request", lib.DEVICES_REQUEST, ["hyprctl", "-j", "devices"]);
    check("binds request", lib.BINDS_REQUEST, ["hyprctl", "-j", "binds"]);

    const written = [
        { id: "acme.mouse", setting: "speed", path: "input.sensitivity", value: 0.35 },
        { id: "acme.mouse", setting: "pad", path: "device.touchpad.enabled", value: false },
        { id: "acme.keys", setting: "rate", path: "input.repeat_rate", value: 40 },
        { id: "acme.keys", setting: "layouts", path: "input.kb_layout", value: "us,de" },
        { id: "acme.mouse", setting: "tap", path: "input.touchpad.tap_to_click", value: false }
    ];
    // The applied groups' options the layer wrote for the core, under id "".
    const core = [
        { id: "", setting: "borderWidth", path: "general.border_size", value: 2 },
        { id: "", setting: "windowRadius", path: "decoration.rounding", value: 12 }
    ];
    const asked = lib.OPTIONS_REQUEST[2].split(";");
    check("options request: one hyprctl batch", lib.OPTIONS_REQUEST.slice(0, 2), ["hyprctl", "--batch"]);
    check("options request: every part a getoption", asked.every(part => /^j\/getoption [a-z_]+(\.[a-z_]+)+$/.test(part)), true);
    check("options request: the written options and an unwritten one among them", ["input.sensitivity", "input.repeat_rate", "input.kb_layout", "input.touchpad.tap_to_click", "input.natural_scroll"].every(path => asked.indexOf("j/getoption " + path) !== -1), true);
    check("options request: not the device row", asked.indexOf("j/getoption device.touchpad.enabled") === -1, true);
    check("options request: each Appearance path among them", ["general.border_size", "decoration.rounding", "animations.enabled"].every(path => asked.indexOf("j/getoption " + path) !== -1), true);
    // Hyprland's reply to the request: VALUES by path, Hyprland's default
    // for the rest, each part as getoption prints it, an empty string as
    // `[[EMPTY]]`.
    const FIELD = { "general.border_size": "int", "decoration.rounding": "int", "input.sensitivity": "float", "input.scroll_factor": "float", "input.touchpad.scroll_factor": "float", "input.repeat_rate": "int", "input.repeat_delay": "int", "misc.vrr": "int",
        "input.kb_layout": "str", "input.kb_variant": "str", "input.kb_options": "str", "input.accel_profile": "str" };
    const replies = values => asked.map(part => part.slice("j/getoption ".length)).map(path => {
        const field = FIELD[path] || "bool";
        const value = Object.prototype.hasOwnProperty.call(values, path) ? values[path] : field === "str" ? "[[EMPTY]]" : field === "bool" ? false : 0;
        return getoption(path, field, value);
    }).join("\n\n\n") + "\n";
    const typed = { "input.sensitivity": 0.35, "input.repeat_rate": 40, "input.kb_layout": "us,de", "input.touchpad.tap_to_click": true, "input.natural_scroll": true };
    // rows: [name, reply, the paths whose value is read, want]
    const reads = [
        ["each option by its type", replies(typed), Object.keys(typed), { ok: true, values: typed, unread: [] }],
        ["an option Hyprland does not know", replies(typed).replace(getoption("input.kb_layout", "str", "us,de"), "no such option"), Object.keys(typed),
            { ok: true, values: { "input.sensitivity": 0.35, "input.repeat_rate": 40, "input.touchpad.tap_to_click": true, "input.natural_scroll": true }, unread: ["refused: options=unread path=input.kb_layout reply=\"no such option\""] }],
        ["an empty string option reads empty", replies(typed), ["input.kb_variant"], { ok: true, values: { "input.kb_variant": "" }, unread: [] }],
        ["each Appearance option by its type", replies({ "decoration.rounding": 10, "general.border_size": 3, "animations.enabled": true }), ["decoration.rounding", "general.border_size", "animations.enabled"],
            { ok: true, values: { "decoration.rounding": 10, "general.border_size": 3, "animations.enabled": true }, unread: [] }],
        ["an Appearance reply of another type", replies(typed).replace(getoption("decoration.rounding", "int", 0), getoption("decoration.rounding", "bool", false)), ["decoration.rounding"], { ok: true, values: {}, unread: ["refused: options=unread path=decoration.rounding "] }],
        ["a reply of another type", replies(typed).replace(getoption("input.repeat_rate", "int", 40), getoption("input.repeat_rate", "float", 40)), ["input.repeat_rate"], { ok: true, values: {}, unread: ["refused: options=unread path=input.repeat_rate "] }],
        ["a reply for another option", replies(typed).replace(getoption("input.sensitivity", "float", 0.35), getoption("input.scroll_factor", "float", 0.35)), ["input.sensitivity"], { ok: true, values: {}, unread: ["refused: options=unread path=input.sensitivity "] }],
        ["a reply missing", replies(typed).split("\n\n\n").slice(1).join("\n\n\n"), [], { ok: false, error: "refused: options=parts count=" + (asked.length - 1) + " want=" + asked.length }]
    ];
    for (const [name, text, paths, want] of reads) {
        const got = lib.optionValues(text);
        check("option values: " + name, got.ok ? {
            ok: true,
            values: Object.fromEntries(paths.filter(p => Object.prototype.hasOwnProperty.call(got.values, p)).map(p => [p, got.values[p]])),
            unread: got.errors.map((e, i) => e.slice(0, want.unread[i] === undefined ? e.length : want.unread[i].length))
        } : { ok: false, error: got.error.slice(0, want.ok ? 0 : want.error.length) }, want);
    }

    // rows: [name, values, want]
    const asWritten = { "input.sensitivity": 0.35, "input.repeat_rate": 40, "input.kb_layout": "us,de", "input.touchpad.tap_to_click": false };
    const overrides = [
        ["each option as written", asWritten, []],
        ["a float within getoption's six places", Object.assign({}, asWritten, { "input.sensitivity": 0.3500004 }), []],
        ["a later user line for each", { "input.sensitivity": -0.5, "input.repeat_rate": 30, "input.kb_layout": "us", "input.touchpad.tap_to_click": true }, [
            { id: "acme.mouse", path: "input.sensitivity" }, { id: "acme.keys", path: "input.repeat_rate" },
            { id: "acme.keys", path: "input.kb_layout" }, { id: "acme.mouse", path: "input.touchpad.tap_to_click" }]],
        ["an option Hyprland did not read", { "input.sensitivity": 0.35, "input.repeat_rate": 40, "input.touchpad.tap_to_click": false }, [{ id: "acme.keys", path: "input.kb_layout" }]]
    ];
    for (const [name, values, want] of overrides) check("overridden: " + name, lib.overridden(written, values), want);
    check("overridden: a core Appearance option read back otherwise", lib.overridden(written.concat(core), Object.assign({}, asWritten, { "general.border_size": 2, "decoration.rounding": 10 })), [{ id: "", path: "decoration.rounding" }]);

    // What a plugin's row shows while it sets none: the keys and values,
    // so a key read as undefined stays visible.
    const mouseOptions = { speed: "input.sensitivity", tap: "input.touchpad.tap_to_click", flow: "input.natural_scroll", pad: "device.touchpad.enabled" };
    const live = { "input.sensitivity": 0.2, "input.touchpad.tap_to_click": false, "input.natural_scroll": true, "input.repeat_rate": 40 };
    // rows: [name, id, values, want]
    const unwritten = [
        ["the options the plugin writes are left out", "acme.mouse", live, [["input.natural_scroll"], { "input.natural_scroll": true }]],
        ["another plugin's written option reads as Hyprland holds it", "acme.other", live, [["input.natural_scroll", "input.sensitivity", "input.touchpad.tap_to_click"], { "input.sensitivity": 0.2, "input.touchpad.tap_to_click": false, "input.natural_scroll": true }]],
        ["an option Hyprland did not read is left out", "acme.other", { "input.sensitivity": 0.2 }, [["input.sensitivity"], { "input.sensitivity": 0.2 }]]
    ];
    for (const [name, id, values, want] of unwritten) {
        const got = lib.unwrittenValues(mouseOptions, written, id, values, []);
        check("unwritten values: " + name, [Object.keys(got).sort(), got], want);
    }
    // The core's Appearance paths reach every holder, with or without
    // options of its own, while the layer writes none of them.
    const appearanceLive = { "general.border_size": 3, "decoration.rounding": 10, "animations.enabled": true, "input.natural_scroll": true };
    check("unwritten values: an Appearance path the layer leaves to the user", lib.unwrittenValues(undefined, written, "acme.pane", appearanceLive, core), { "animations.enabled": true });
    check("unwritten values: every Appearance path while the layer writes none", lib.unwrittenValues({ flow: "input.natural_scroll" }, written, "acme.pane", appearanceLive, []),
        { "input.natural_scroll": true, "general.border_size": 3, "decoration.rounding": 10, "animations.enabled": true });

    // The layer's record of the user's values, as `hyprctl eval` prints the
    // error the request raises with it.
    check("user values request: one eval that raises the layer's answer, or none without the layer", lib.USER_VALUES_REQUEST, ["hyprctl", "eval", "error(hl.__vgs_options == nil and \"vgs-user-values=[]\" or hl.__vgs_options.report(), 0)"]);
    const answer = rows => "error: vgs-user-values=" + JSON.stringify(rows) + "\n";
    // rows: [name, reply, want]
    const userRows = [
        ["no user value", answer([]), { ok: true, values: [] }],
        ["a value per option, in the written order, each with its plugin", answer([{ path: "input.kb_layout", value: "us" }, { path: "input.sensitivity", value: -0.5 }, { path: "input.touchpad.tap_to_click", value: true }]), { ok: true, values: [
            { id: "acme.mouse", path: "input.sensitivity", value: -0.5 }, { id: "acme.keys", path: "input.kb_layout", value: "us" }, { id: "acme.mouse", path: "input.touchpad.tap_to_click", value: true }] }],
        ["a path the layer no longer writes", answer([{ path: "input.natural_scroll", value: true }, { path: "input.repeat_rate", value: 30 }]), { ok: true, values: [{ id: "acme.keys", path: "input.repeat_rate", value: 30 }] }],
        ["the per-device option has no user value", answer([{ path: "device.touchpad.enabled", value: true }]), { ok: true, values: [] }],
        ["a string with an escaped quote", "error: vgs-user-values=[{\"path\":\"input.kb_layout\",\"value\":\"a\\u0022b\"}]", { ok: true, values: [{ id: "acme.keys", path: "input.kb_layout", value: "a\"b" }] }],
        ["another error", "error: [string \"return error(hl.__vgs_options.report(), 0);\"]:1: attempt to call a nil value", { ok: false, error: "refused: user-values=unread reply=" }],
        ["no reply", "", { ok: false, error: "refused: user-values=unread reply=\"\"" }],
        ["no JSON", "error: vgs-user-values=[{", { ok: false, error: "refused: user-values=unparsed " }],
        ["no list", "error: vgs-user-values={}", { ok: false, error: "refused: user-values=shape want=list" }],
        ["a row with no path", answer([{ value: 1 }]), { ok: false, error: "refused: user-values=shape row=0" }],
        ["a value of another type", answer([{ path: "input.sensitivity", value: "fast" }]), { ok: false, error: "refused: user-values=shape path=input.sensitivity want=float" }],
        ["a core Appearance value under the core's id", answer([{ path: "decoration.rounding", value: 10 }]), { ok: true, values: [{ id: "", path: "decoration.rounding", value: 10 }] }],
        ["a core Appearance value of another type", answer([{ path: "decoration.rounding", value: true }]), { ok: false, error: "refused: user-values=shape path=decoration.rounding want=int" }]
    ];
    for (const [name, text, want] of userRows) {
        const got = lib.userValues(written.concat(core), text);
        check("user values: " + name, got.ok ? got : { ok: false, error: got.error.slice(0, want.ok ? 0 : want.error.length) }, want);
    }

    const layerBinds = ["acme.keys:toggle", "acme.keys:talk", "acme.keys:talk.release"];
    // rows: [name, binds, want]
    const foreign = [
        ["the layer's own binds are not foreign", [bind(64, "SPACE", "acme.keys:toggle"), bind(64, "", "acme.keys:talk"), bind(64, "", "acme.keys:talk.release", { release: true })], { ok: true, keys: [] }],
        ["a user bind on the layer's key", [bind(64, "SPACE", "acme.keys:toggle"), bind(64, "space", "")], { ok: true, keys: ["SUPER+SPACE"] }],
        ["modifiers in the key judge's order, each key once", [bind(65, "space", "mine"), bind(77, "F7", ""), bind(65, "SPACE", "")], { ok: true, keys: ["SUPER+CTRL+ALT+SHIFT+F7", "SUPER+SHIFT+SPACE"] }],
        ["a bind in another submap", [bind(64, "N", "", { submap: "vgs:capture" })], { ok: true, keys: [] }],
        ["a bind in the submap named default", [bind(64, "N", "", { submap: "default" })], { ok: true, keys: ["SUPER+N"] }],
        ["a keycode bind by its keycode", [bind(64, "", "", { keycode: 24 })], { ok: true, keys: ["SUPER+code:24"] }],
        ["a bind with neither key nor keycode", [bind(64, "", "")], { ok: true, keys: [] }],
        ["a mouse bind", [bind(64, "mouse:272", "")], { ok: true, keys: [] }],
        ["Num Lock in the mask", [bind(64 | 16, "N", "")], { ok: true, keys: [] }],
        ["no JSON", "ok", { ok: false, error: "refused: binds=unparsed " }],
        ["no list", "{}", { ok: false, error: "refused: binds=shape want=list" }],
        ["a bind with no modmask", [{ submap: "", key: "N", description: "", keycode: 0 }], { ok: false, error: "refused: binds=shape bind=0" }],
        ["a bind with no keycode", [{ submap: "", key: "N", description: "", modmask: 64 }], { ok: false, error: "refused: binds=shape bind=0" }]
    ];
    for (const [name, binds, want] of foreign) {
        const got = lib.foreignBinds(typeof binds === "string" ? binds : JSON.stringify(binds, null, 4), layerBinds);
        check("foreign binds: " + name, got.ok ? got : { ok: false, error: got.error.slice(0, want.ok ? 0 : want.error.length) }, want);
    }

    // The layer's record of the user's binds, as `hyprctl eval` prints the
    // error the request raises with it.
    check("user binds request: one eval that raises the layer's answer, or none without the layer", lib.USER_BINDS_REQUEST, ["hyprctl", "eval", "error(hl.__vgs_binds == nil and \"vgs-user-binds=[]\" or hl.__vgs_binds.report(), 0)"]);
    const record = (file, line, text, modmask, key, keycode) => ({ file: file, line: line, text: text, modmask: modmask, key: key, keycode: keycode });
    const recorded = rows => "error: vgs-user-binds=" + JSON.stringify(rows) + "\n";
    const whole = 'hl.bind("SUPER + F7", hl.dsp.exec_cmd("true"))';
    // rows: [name, reply, want]
    const userBindRows = [
        ["no user bind", recorded([]), { ok: true, binds: [] }],
        ["a whole line binding its key", recorded([record("/h/.config/hypr/hyprland.lua", 2, whole, 64, "F7", 0)]), { ok: true, binds: [{ key: "SUPER+F7", file: "/h/.config/hypr/hyprland.lua", line: 2, text: whole, removable: true }] }],
        ["a call over lines is no whole line", recorded([record("/h/.config/hypr/b.lua", 3, "hl.bind(", 64, "F8", 0)]), { ok: true, binds: [{ key: "SUPER+F8", file: "/h/.config/hypr/b.lua", line: 3, text: "hl.bind(", removable: false }] }],
        ["a line binding another key is not removable for this one", recorded([record("/h/.config/hypr/b.lua", 1, whole, 64, "F9", 0)]), { ok: true, binds: [{ key: "SUPER+F9", file: "/h/.config/hypr/b.lua", line: 1, text: whole, removable: false }] }],
        ["a keycode bind by its keycode, in the order made", recorded([record("/h/.config/hypr/b.lua", 9, 'hl.bind("SUPER + code:24", f)', 64, "", 24), record("/h/.config/hypr/a.lua", 1, whole, 64, "F7", 0)]), { ok: true, binds: [
            { key: "SUPER+code:24", file: "/h/.config/hypr/b.lua", line: 9, text: 'hl.bind("SUPER + code:24", f)', removable: true }, { key: "SUPER+F7", file: "/h/.config/hypr/a.lua", line: 1, text: whole, removable: true }] }],
        ["a whole line outside the hypr directory is not removable", recorded([record("/h/dotfiles/b.lua", 1, whole, 64, "F7", 0)]), { ok: true, binds: [{ key: "SUPER+F7", file: "/h/dotfiles/b.lua", line: 1, text: whole, removable: false }] }],
        ["a bind no key names is left out", recorded([record("/h/.config/hypr/b.lua", 1, whole, 64 | 16, "F7", 0)]), { ok: true, binds: [] }],
        ["another error", "error: attempt to call a nil value", { ok: false, error: "refused: user-binds=unread reply=" }],
        ["no JSON", "error: vgs-user-binds=[{", { ok: false, error: "refused: user-binds=unparsed " }],
        ["no list", "error: vgs-user-binds={}", { ok: false, error: "refused: user-binds=shape want=list" }],
        ["a row with no line", recorded([{ file: "/h/.config/hypr/b.lua", text: whole, modmask: 64, key: "F7", keycode: 0 }]), { ok: false, error: "refused: user-binds=shape row=0" }],
        ["a row at line 0", recorded([record("/h/.config/hypr/b.lua", 0, whole, 64, "F7", 0)]), { ok: false, error: "refused: user-binds=shape row=0" }]
    ];
    for (const [name, text, want] of userBindRows) {
        const got = lib.userBinds(text, "/h/.config/hypr");
        check("user binds: " + name, got.ok ? got : { ok: false, error: got.error.slice(0, want.ok ? 0 : want.error.length) }, want);
    }
    check("bind place: a file under home from ~", lib.bindPlace("/home/u/.config/hypr/b.lua", "/home/u"), "~/.config/hypr/b.lua");
    check("bind place: a file elsewhere as it is", lib.bindPlace("/home/user2/b.lua", "/home/u"), "/home/user2/b.lua");

    // rows: [name, line, want]: the key a line binds as one whole call
    const calls = [
        ["a call with nested parentheses", whole, "SUPER+F7"],
        ["single quotes, a table, a ; and a comment", "  hl.bind('super + q', hl.dsp.window.close(), { description = \"a ( b\" }) ; -- mine", "SUPER+Q"],
        ["a carriage return ends the line", whole + "\r", "SUPER+F7"],
        ["a comment marker inside a string", 'hl.bind("SUPER + F7", f("--"))', "SUPER+F7"],
        ["the call's first line only", "hl.bind(", null],
        ["a further statement after the call", whole + " x = 1", null],
        ["an assigned call", "local b = " + whole, null],
        ["a comment inside the call", 'hl.bind("SUPER + F7", f, -- why', null],
        ["a long string inside the call", 'hl.bind("SUPER + F7", [[x]])', null],
        ["an escape in the key string", 'hl.bind("SUPER + \\x46", f)', null],
        ["a key the judge refuses", 'hl.bind("HYPER + F7", f)', null],
        ["another call", 'hl.unbind("SUPER + F7")', null]
    ];
    for (const [name, line, want] of calls) check("bind call: " + name, lib.bindCall(line), want);

    // rows: [name, text, line, key, want]
    const file = "a = 1\n" + whole + "\nb = 2";
    const removals = [
        ["a middle line goes with its break, beside its neighbours", file, 2, "SUPER+F7", { ok: true, text: "a = 1\nb = 2", undo: { text: whole + "\n", before: "a = 1\n", after: "b = 2" } }],
        ["a last line with no break goes alone", "a = 1\n" + whole, 2, "SUPER+F7", { ok: true, text: "a = 1\n", undo: { text: whole, before: "a = 1\n", after: null } }],
        ["a first line has no line before it", whole + "\nb = 2", 1, "SUPER+F7", { ok: true, text: "b = 2", undo: { text: whole + "\n", before: null, after: "b = 2" } }],
        ["a line binding another key", file, 2, "SUPER+F8", { ok: false, error: "refused: user-bind=not-whole line=2 key=SUPER+F8" }],
        ["a line that is no bind", file, 1, "SUPER+F7", { ok: false, error: "refused: user-bind=not-whole line=1 key=SUPER+F7" }],
        ["a line past the end", file, 4, "SUPER+F7", { ok: false, error: "refused: user-bind=no-line line=4 lines=3" }]
    ];
    for (const [name, text, line, key, want] of removals) check("remove bind line: " + name, lib.removeBindLine(text, line, key), want);
    // Two binds around a block, each removed and put back in either order,
    // as two Keys rows of one page do: each goes back where it stood.
    const block = "a = 1\n\nhl.bind(\"SUPER+Q\", f)\n\nif laptop then\n  x()\nend\n\nhl.bind(\"SUPER+W\", g)\n\n";
    const q = lib.removeBindLine(block, 3, "SUPER+Q");
    const w = lib.removeBindLine(q.text, 8, "SUPER+W");
    const order = (first, firstLine, second, secondLine) => {
        const one = lib.restoreBindLine(w.text, firstLine, first.undo);
        return one.ok ? lib.restoreBindLine(one.text, secondLine, second.undo).text : one.error;
    };
    check("restore bind line: two lines put back in the order removed land where they stood", order(q, 3, w, 9), block);
    check("restore bind line: two lines put back in reverse order land where they stood", order(w, 8, q, 3), block);
    const u = (text, before, after) => ({ text: text, before: before, after: after });
    // rows: [name, text, line, undo, want]
    const restores = [
        ["a middle line goes back byte for byte", "a = 1\nb = 2", 2, u(whole + "\n", "a = 1\n", "b = 2"), { ok: true, text: file, line: 2 }],
        ["a last line with no break goes back last", "a = 1\n", 2, u(whole, "a = 1\n", null), { ok: true, text: "a = 1\n" + whole, line: 2 }],
        ["a first line goes back first", "b = 2", 1, u(whole + "\n", null, "b = 2"), { ok: true, text: whole + "\nb = 2", line: 1 }],
        ["a line whose neighbours meet elsewhere goes there", "z = 0\na = 1\nb = 2", 2, u(whole + "\n", "a = 1\n", "b = 2"), { ok: true, text: "z = 0\na = 1\n" + whole + "\nb = 2", line: 3 }],
        ["the expected line picks among several places", "a = 1\na = 1\na = 1\n", 3, u(whole + "\n", "a = 1\n", "a = 1\n"), { ok: true, text: "a = 1\na = 1\n" + whole + "\na = 1\n", line: 3 }],
        ["several places none expected", "a = 1\na = 1\na = 1\n", 9, u(whole + "\n", "a = 1\n", "a = 1\n"), { ok: false, error: "refused: user-bind=moved line=9 places=2" }],
        ["neighbours that no longer meet", "a = 1\nc = 3\nb = 2", 2, u(whole + "\n", "a = 1\n", "b = 2"), { ok: false, error: "refused: user-bind=moved line=2 places=0" }],
        ["a last line after a line that lost its break", "a = 1", 2, u(whole, "a = 1\n", null), { ok: false, error: "refused: user-bind=moved line=2 places=0" }],
        ["a text that is no bind call", "a = 1\n", 1, u('os.execute("x")\n', null, "a = 1\n"), { ok: false, error: "refused: user-bind=not-whole line=1" }],
        ["a text of two lines", "a = 1\n", 1, u(whole + "\n" + whole + "\n", null, "a = 1\n"), { ok: false, error: "refused: user-bind=not-whole line=1" }],
        ["an undo with no neighbours named", "a = 1\n", 1, { text: whole + "\n" }, { ok: false, error: "refused: user-bind=not-whole line=1" }]
    ];
    for (const [name, text, line, undo, want] of restores) check("restore bind line: " + name, lib.restoreBindLine(text, line, undo), want);
    // rows: [name, file, want]
    const editable = [
        ["a file in the hypr directory", "/h/.config/hypr/binds.lua", true],
        ["a file in a directory under it", "/h/.config/hypr/conf/binds.lua", true],
        ["a file beside the directory", "/h/.config/hypr-old/binds.lua", false],
        ["a file elsewhere", "/h/dotfiles/binds.lua", false],
        ["a file that is not Lua", "/h/.config/hypr/binds.conf", false],
        ["a path that climbs out", "/h/.config/hypr/../binds.lua", false]
    ];
    for (const [name, file, want] of editable) check("bind file editable: " + name, lib.bindFileEditable(file, "/h/.config/hypr"), want);
}

suite(load(STATE), report);

// Each control removes one rule from a copy of the file and keeps the text
// around it; the suite must fail on every copy. The copy sits in a
// temporary tree beside the libraries it imports.
const CONTROLS = [
    ["a bare none index reads as null", '.replace(/("active_layout_index": )none\\b/g, "$1null")', ""],
    ["devices need both lists", " || !Array.isArray(d.mice) || !Array.isArray(d.keyboards))", ")"],
    ["a pointer has a name", 'if (typeof d.mice[m].name !== "string") return', "if (false) return"],
    ["a keyboard's fields are judged", '|| typeof kb.active_keymap !== "string" || typeof kb.main !== "boolean"', ""],
    ["a touchpad is named so", "var TOUCHPAD = /touchpad|trackpad/i;", "var TOUCHPAD = /touchpad/;"],
    ["touchpads are the pointers named so", "return devices.mice.filter(function (mouse) { return mouse.touchpad; })", "return devices.mice.filter(function (mouse) { return true; })"],
    ["unread devices have no touchpads", "if (devices === null) return null;", "if (devices === null) return [];"],
    ["the device row is not read back", "return Layer.readType(option.path) !== null; });", "return true; });"],
    ["the request reads no device row", ".filter(function (path) { return Layer.readType(path) !== null; });", ";"],
    ["the request reads the Appearance paths", ".concat(Object.keys(Layer.APPEARANCE_PATHS).map(function (group) { return Layer.APPEARANCE_PATHS[group].path; }))", ""],
    ["one reply per option", 'var replies = Dispatch.batchReplies(text, READABLE.length, "options");', 'var replies = { ok: true, parts: String(text).split("\\n\\n\\n").map(function (part) { return part.trim(); }).filter(function (part) { return part !== ""; }) };'],
    ["each reply names its option", "read.value.option !== path || ", ""],
    ["an empty string option reads empty", 'values[path] = field === "str" ? optionString(read.value.str) : read.value[field];', "values[path] = read.value[field];"],
    ["an unread option has no value", "replies.parts[i].slice(0, 120)));\n            continue;", "replies.parts[i].slice(0, 120)));"],
    ["each reply holds its type's field", " || !Object.prototype.hasOwnProperty.call(read.value, field))", ")"],
    ["a float within a millionth is the same", "Math.abs(read - want) > 0.000001", "read !== want"],
    ["a differing value is overridden", "return differs(Layer.readType(row.path), row.value, values[row.path]);", "return false;"],
    ["a written option has no unwritten value", "if (held.indexOf(path) === -1 && ", "if ("],
    ["a plugin's options are its own", "take(options[setting], mine);", "take(options[setting], core);"],
    ["the Appearance paths reach every holder", "Object.keys(Layer.APPEARANCE_PATHS).forEach(function (group) { take(Layer.APPEARANCE_PATHS[group].path, core); });", ""],
    ["only the plugin's own rows are its written ones", "return row.id === id; })", "return true; })"],
    ["an option Hyprland did not read has no unwritten value", " && Object.prototype.hasOwnProperty.call(values, path)) out[path]", ") out[path]"],
    ["a session without the layer has no user value", 'hl." + Layer.USER_VALUES.table + " == nil and \\"" + Layer.USER_VALUES.key + "=[]\\" or ', ""],
    ["the answer is read by its key", 'if (line === undefined) return { ok: false, error: "refused: user-values=unread', 'if (false) return { ok: false, error: "refused: user-values=unread'],
    ["the answer is a list", 'if (!Array.isArray(read.value)) return { ok: false, error: "refused: user-values=shape want=list" };', ""],
    ["a user value row names a path", '|| typeof row.path !== "string")', ")"],
    ["a user value has its option's type", "if (typeof named[path].value !== VALUE_TYPE[Layer.readType(path)])", "if (false)"],
    ["a user value carries its plugin", "out.push({ id: rows[r].id, path: path, value: named[path].value });", "out.push({ path: path, value: named[path].value });"],
    ["only the default submap", '(bind.submap !== "" && bind.submap !== "default") || ', ""],
    ["the submap named default counts", ' && bind.submap !== "default")', ")"],
    ["the layer's binds are not foreign", " || descriptions.indexOf(bind.description) !== -1) continue;", ") continue;"],
    ["an unnamed modifier is left out", "if ((modmask & ~NAMED_BITS) !== 0) return null;", ""],
    ["the modifiers are read from the mask", "return (modmask & row[1]) !== 0; })", "return false; })"],
    ["the key judge normalises", "return read.ok ? read.key : null;", "return mods.concat([name]).join(\"+\");"],
    ["each foreign key once", "if (key !== null && keys.indexOf(key) === -1) keys.push(key);", "if (key !== null) keys.push(key);"],
    ["the keys are sorted", "return { ok: true, keys: keys.sort() };", "return { ok: true, keys: keys };"],
    ["a bind's shape is judged", '|| typeof bind.description !== "string" || !Number.isInteger(bind.modmask) || !Number.isInteger(bind.keycode))', ")"],
    ["a keycode bind names its keycode", 'var name = key !== "" ? key : keycode > 0 ? "code:" + keycode : "";', "var name = key;"],
    ["a session without the layer has no user bind", 'hl." + Layer.USER_BINDS.table + " == nil and \\"" + Layer.USER_BINDS.key + "=[]\\" or ', ""],
    ["the user binds are read by their key", 'if (line === undefined) return { ok: false, error: "refused: user-binds=unread', 'if (false) return { ok: false, error: "refused: user-binds=unread'],
    ["the user binds are a list", 'if (!Array.isArray(read.value)) return { ok: false, error: "refused: user-binds=shape want=list" };', ""],
    ["a user bind's line is a positive whole number", '|| !Number.isInteger(row.line) || row.line < 1', ""],
    ["a user bind no key names is left out", "if (key === null) continue;", ""],
    ["a user bind is removable only as a whole call of its key", "removable: bindCall(row.text) === key", "removable: true"],
    ["a place under home starts with ~", 'return home !== "" && file.indexOf(home + "/") === 0 ? "~" + file.slice(home.length) : file;', "return file;"],
    ["a whole call starts the line", "var BIND_CALL = /^\\s*hl\\.bind", "var BIND_CALL = /hl\\.bind"],
    ["a string inside the call is skipped", 'if (c === "\\\\") i++;\n            else if (c === quote) quote = null;', 'quote = null;'],
    ["a comment or long bracket inside the call is refused", 'else if (c === "-" && text[i + 1] === "-" || c === "[" && /^\\[=*\\[/.test(text.slice(i))) {\n            return null;', 'else if (false) {\n            return null;'],
    ["nothing but a ; and a comment follows the call", "if (depth !== 0 || !/^\\s*;?\\s*(?:--(?!\\[=*\\[).*)?\\r?$/.test(text.slice(i))) return null;", "if (depth !== 0) return null;"],
    ["a removed line is a whole call of its key", "if (bindCall(lines[line - 1].replace(/\\n$/, \"\")) !== key)", "if (false)"],
    ["a removed line is in the file", "if (!Number.isInteger(line) || line < 1 || line > lines.length)\n", "if (!Number.isInteger(line) || line < 1)\n"],
    ["a removal names its neighbours", "before: line > 1 ? lines[line - 2] : null, after: line < lines.length ? lines[line] : null", "before: null, after: null"],
    ["a restored text is one whole call", '|| bindCall(undo.text.replace(/\\n$/, "")) === null || ', "|| "],
    ["a restored line goes where its neighbours meet", "(undo.before === null ? at === 1 : lines[at - 2] === undo.before)\n", "true\n"],
    ["a restored line goes before the line after it", "&& (undo.after === null ? at === lines.length + 1 : lines[at - 1] === undo.after))", ")"],
    ["the expected line picks among places", "places.indexOf(line) !== -1 ? line : places.length === 1", "places.length >= 1"],
    ["several places none expected are refused", "places.length === 1 ? places[0] : null", "places.length > 0 ? places[0] : null"],
    ["a bind file is under the hypr directory", 'return file.indexOf(hyprDir + "/") === 0 && ', "return "],
    ["a bind file is Lua", '&& /\\.lua$/.test(file) && ', "&& "],
    ["a bind file names no climbing segment", ' && !/\\/\\.\\.?(\\/|$)/.test(file);', ";"],
    ["a user bind outside the hypr directory is not removable", " && bindFileEditable(row.file, hyprDir) });", " });"],
    ["the lines keep their breaks", "return text.match(/[^\\n]*\\n|[^\\n]+$/g) || [];", "return text.split(\"\\n\");"]
];

fs.mkdirSync(path.join(__dirname, "..", "tmp"), { recursive: true });
const temp = fs.mkdtempSync(path.join(__dirname, "..", "tmp", "hyprland-state-control-"));
try {
    fs.mkdirSync(path.join(temp, "shell", "Core"), { recursive: true });
    fs.mkdirSync(path.join(temp, "shell", "Ui", "icons"), { recursive: true });
    fs.mkdirSync(path.join(temp, "shell", "Commons"), { recursive: true });
    for (const name of ["PluginLogic.js", "HyprlandLayer.js", "MonitorLogic.js", "Pads.js", "PackageManagers.js", "Dispatch.js"])
        fs.symlinkSync(path.join(__dirname, "..", "shell", "Core", name), path.join(temp, "shell", "Core", name));
    fs.symlinkSync(path.join(__dirname, "..", "shell", "Ui", "icons", "Lucide.js"), path.join(temp, "shell", "Ui", "icons", "Lucide.js"));
    fs.symlinkSync(path.join(__dirname, "..", "shell", "Commons", "SettingValues.js"), path.join(temp, "shell", "Commons", "SettingValues.js"));
    const source = fs.readFileSync(STATE, "utf8");
    for (const [label, needle, replacement] of CONTROLS) {
        const count = source.split(needle).length - 1;
        if (count !== 1) { report("control: " + label + ": the text to replace occurs once", count, 1); continue; }
        const mutant = path.join(temp, "shell", "Core", "HyprlandState.js");
        fs.writeFileSync(mutant, source.replace(needle, () => replacement));
        // Loaded outside the try, so a copy that does not evaluate fails the
        // suite instead of passing for a control.
        const lib = load(mutant);
        let red = 0;
        try {
            suite(lib, (name, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) red += 1; });
        } catch (e) {
            red += 1;
        }
        report("control: the suite fails without the rule: " + label, red > 0, true);
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}

if (failures > 0) { console.log("test-hyprland-state: " + failures + " failing"); process.exit(1); }
console.log("test-hyprland-state: ok");
