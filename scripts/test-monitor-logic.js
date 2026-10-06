#!/usr/bin/env node
// Checks for shell/Core/MonitorLogic.js, the outputs reading behind the
// `monitors` capability, loaded under node through
// bin/lib/qml-library.js as the shell loads it. NESTED_REPLY is the reply
// `hyprctl -j monitors all` printed in the nested sandbox; the other outputs
// are built in the shape `CHyprCtl::getMonitorData` prints.
//
// The layer's guard block runs under `lua` with a stub `hl` that lists the
// outputs a row names and records each output the block turns off and each
// command it runs; Hyprland 0.56.2 on host cachy links Lua 5.5, the `lua`
// on PATH there. A missing interpreter fails the suite.
//
// The controls at the end edit a copy of the file, one rule at a time, and
// the suite must fail on every copy. Exit 1 when a row or a control fails.
"use strict";
const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const { load } = require("../bin/lib/qml-library.js");

const LOGIC = path.join(__dirname, "..", "shell", "Core", "MonitorLogic.js");

let failures = 0;
function report(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { console.log("  ok    " + name); return; }
    failures += 1;
    console.log("  FAIL  " + name + "\n        got  " + g + "\n        want " + w);
}

// Recorded from the nested Hyprland 0.56.2 of scripts/qml-smoke.sh on host
// cachy on 2026-10-01: the Wayland backend's output, with no make, model,
// serial or mode list.
const NESTED_REPLY = `[{
    "id": 0,
    "name": "WAYLAND-1",
    "description": "",
    "make": "",
    "model": "",
    "serial": "",
    "width": 1756,
    "height": 933,
    "physicalWidth": 0,
    "physicalHeight": 0,
    "refreshRate": 60.00000,
    "x": 0,
    "y": 0,
    "activeWorkspace": {
        "id": 1,
        "name": "1"
    },
    "specialWorkspace": {
        "id": 0,
        "name": ""
    },
    "reserved": [0, 28, 0, 0],
    "scale": 1,
    "transform": 0,
    "focused": true,
    "dpmsStatus": true,
    "vrr": false,
    "solitary": "0",
    "solitaryBlockedBy": ["NOTIFICATION","WINDOWED","CANDIDATE"],
    "activelyTearing": false,
    "tearingBlockedBy": ["NOT_TORN","USER","SUPPORT","CANDIDATE"],
    "directScanoutTo": "0",
    "directScanoutBlockedBy": ["USER","SW","CANDIDATE"],
    "disabled": false,
    "currentFormat": "XRGB8888",
    "mirrorOf": "none",
    "availableModes": [],
    "colorManagementPreset": "srgb",
    "sdrBrightness": 1,
    "sdrSaturation": 1,
    "sdrMinLuminance": 0.2,
    "sdrMaxLuminance": 80,
    "hardwareCursorsInUse": false
}]`;

// One output as `monitors -j` prints it: the fields parseOutputs reads, with
// the DRM backend's make, model, serial and mode list.
const monitor = (id, name, extra) => Object.assign({
    id: id, name: name, description: "", make: "Dell Inc.", model: "DELL U2720Q", serial: "", width: 3840, height: 2160,
    physicalWidth: 600, physicalHeight: 340, refreshRate: 59.99700, x: 0, y: 0, scale: 1.5, transform: 0, vrr: false,
    disabled: false, currentFormat: "XRGB8888", mirrorOf: "none",
    availableModes: ["3840x2160@60.00Hz", "3840x2160@30.00Hz", "2560x1440@59.95Hz", "1920x1080@60.00Hz"],
    colorManagementPreset: "srgb", sdrBrightness: 1, sdrSaturation: 1
}, extra || {});
const reply = monitors => JSON.stringify(monitors, null, 4);
// A desk: DP-1 with a serial and commas in its make, DP-2 with none, and
// eDP-1 off.
const DESK = [
    monitor(0, "DP-1", { make: "Dell, Inc.", serial: "8YT0R13" }),
    monitor(1, "DP-2", { x: 2560, model: "LG HDR 4K", scale: 2, availableModes: ["3840x2160@60.00Hz"] }),
    monitor(2, "eDP-1", { make: "BOE", model: "0x0BCA", disabled: true, availableModes: ["2880x1800@120.00Hz", "2880x1800@60.00Hz"], width: 2880, height: 1800 })
];

// The tail of the reply `hyprctl systeminfo` printed in the nested sandbox
// of scripts/qml-smoke.sh on host cachy on 2026-10-06: the Wayland
// backend's output, with no make, model or serial and no EDID.
const NESTED_SYSTEMINFO = "plugins:\n\nExplicit sync: supported\nGL ver: 3.2\nBackend: sessionless\n\nMonitor info:\n"
    + "\tPanel WAYLAND-1: 1755x933, WAYLAND-1    -> backend wayland\n\t\texplicit \u274c\n\t\tedid:\n\t\t\thdr \u274c\n\t\t\tchroma \u274c\n"
    + "\t\t\tbt2020 \u274c\n\t\tvrr capable \u274c\n\t\tnon-desktop \u274c\n\t\t\n\nState:\n\nconfigProvider: lua\nbackend: wayland\n\n\n";

// `hyprctl systeminfo` as SystemInfo::getSystemInfo prints it: the head
// cut short, each panel block, then the state section. A panel is
// [name, { hdr, chroma, bt2020, vrr }], `vrr` the `vrr capable` mark.
const MARK = { true: "\u2714\ufe0f", false: "\u274c" };
const panelBlock = ([name, f]) => "\n\tPanel " + name + ": 3840x2160, " + name + " Dell Inc. DELL U2720Q 8YT0R13 -> backend drm"
    + "\n\t\texplicit " + MARK[true] + "\n\t\tedid:\n\t\t\thdr " + MARK[f.hdr] + "\n\t\t\tchroma " + MARK[f.chroma]
    + "\n\t\t\tbt2020 " + MARK[f.bt2020] + "\n\t\tvrr capable " + MARK[f.vrr] + "\n\t\tnon-desktop " + MARK[false] + "\n\t\t";
const systeminfo = panels => "Hyprland 0.56.2 built from branch main\n\nSystem Information:\nSystem name: Linux\n\nGPU information: \n00:02.0 VGA\n\n"
    + "plugins:\n\nExplicit sync: supported\nGL ver: 3.2\nBackend: drm\n\nMonitor info:" + panels.map(panelBlock).join("") + "\n\nState:\nconfigProvider: lua\nbackend: drm\n\n";
const ALL = { hdr: true, chroma: true, bt2020: true, vrr: true };
const NONE = { hdr: false, chroma: false, bt2020: false, vrr: false };

// The stub world: `reload` clears the handlers, lists OUTPUTS and runs the
// layer text as Hyprland runs the file; `list` changes what
// `hl.get_monitors()` answers; `fire` calls each handler of an event;
// `mark` records where a row's steps stand; `tick` runs the timers set so
// far, as Hyprland's event loop does once its pass returns. Each
// output is [name, description]. The answer is the turned-off outputs
// (`off <output>`) and the commands run (`exec <command>`), in order.
const LUA_STUB = `
local events, outputs, handlers, timers = {}, {}, {}, {}
hl = {
    timer = function(fn, opts) assert(opts.type == "oneshot" and opts.timeout > 0); timers[#timers + 1] = fn end,
    get_monitors = function() return outputs end,
    monitor = function(rule) if rule.disabled == true then events[#events + 1] = "off " .. rule.output end end,
    on = function(name, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end,
    exec_cmd = function(command) events[#events + 1] = "exec " .. command end
}
local function listed(rows)
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = { name = row[1], description = row[2] } end
    return out
end
local function reload(rows) handlers = {}; outputs = listed(rows); assert(load(LAYER))() end
local function list(rows) outputs = listed(rows) end
local function fire(name) for _, fn in ipairs(handlers[name] or {}) do fn() end end
local function mark() events[#events + 1] = "mark" end
local function tick() local due = timers; timers = {}; for _, fn in ipairs(due) do fn() end end
`;

function luaEvents(lines, steps) {
    const text = lines.join("\n");
    if (text.includes("]==]")) throw new Error("layer text holds the long-string end");
    const program = "LAYER = [==[\n" + text + "\n]==]\n" + LUA_STUB
        + steps.map(([verb, arg]) => verb === "mark" || verb === "tick" ? verb + "()" : verb === "fire" ? "fire(" + JSON.stringify(arg) + ")"
            : verb + "({ " + arg.map(([name, description]) => "{ " + JSON.stringify(name) + ", " + JSON.stringify(description || "") + " }").join(", ") + " })").join("\n")
        + "\nfor _, event in ipairs(events) do print(event) end\n";
    const run = childProcess.spawnSync("lua", ["-"], { input: program, encoding: "utf8", timeout: 10000 });
    if (run.error) throw new Error("lua=" + (run.error.code === "ENOENT" ? "absent" : run.error.message));
    if (run.status !== 0) return { status: run.status, stderr: run.stderr.trim() };
    return run.stdout.split("\n").filter(line => line !== "");
}

function suite(lib, check) {
    const nested = lib.parseOutputs(NESTED_REPLY);
    check("parseOutputs: the nested reply", nested, { ok: true, outputs: [{
        identifier: "WAYLAND-1", id: 0, name: "WAYLAND-1", description: "", make: "", model: "", serial: "", width: 1756, height: 933,
        refreshRate: 60, x: 0, y: 0, scale: 1, transform: 0, vrr: false, disabled: false, mirrorOf: null, availableModes: [], currentFormat: "XRGB8888",
        bitdepth: 8, colorManagementPreset: "srgb", sdrBrightness: 1, sdrSaturation: 1
    }] });
    const desk = lib.parseOutputs(reply(DESK));
    check("parseOutputs: a mode list parsed to numbers", desk.ok ? desk.outputs[1].availableModes : desk, [{ width: 3840, height: 2160, refresh: 60 }]);
    const mirrored = lib.parseOutputs(reply([DESK[0], monitor(1, "DP-2", { mirrorOf: "0" })]));
    check("parseOutputs: mirrorOf names the mirrored output", mirrored.ok ? mirrored.outputs.map(o => o.mirrorOf) : mirrored, [null, "DP-1"]);
    // rows: [name, text, the error's start]
    const unparsed = [
        ["no JSON", "Couldn't connect to the socket", "refused: outputs=unparsed "],
        ["no list", "{}", "refused: outputs=shape want=list"],
        ["a name that is no string", reply([monitor(0, 7)]), "refused: outputs=shape output=0 field=name"],
        ["a fractional width", reply([monitor(0, "DP-1", { width: 1.5 })]), "refused: outputs=shape output=0 field=width"],
        ["a mode Hyprland never prints", reply([monitor(0, "DP-1", { availableModes: ["3840x2160"] })]), "refused: outputs=shape output=0 field=availableModes"],
        ["a vrr that is no boolean", reply([monitor(0, "DP-1", { vrr: 1 })]), "refused: outputs=shape output=0 field=vrr"],
        ["a refresh rate that is no number", reply([monitor(0, "DP-1", { refreshRate: "60" })]), "refused: outputs=shape output=0 field=refreshRate"],
        ["a scale that is no number", reply([monitor(0, "DP-1", { scale: null })]), "refused: outputs=shape output=0 field=scale"],
        ["a disabled that is no boolean", reply([monitor(0, "DP-1", { disabled: 0 })]), "refused: outputs=shape output=0 field=disabled"],
        ["a mode list that is no list", reply([monitor(0, "DP-1", { availableModes: {} })]), "refused: outputs=shape output=0 field=availableModes"],
        ["an output that is no object", "[7]", "refused: outputs=shape output=0 field=object"],
        ["a mirror of an id no output has", reply([monitor(0, "DP-1", { mirrorOf: "4" })]), "refused: outputs=shape output=0 mirrorOf=\"4\""]
    ];
    for (const [name, text, want] of unparsed) {
        const got = lib.parseOutputs(text);
        check("parseOutputs refuses " + name, got.ok ? got : got.error.slice(0, want.length), want);
    }

    // rows: [name, output fields, identifier]
    const identifiers = [
        ["a serial keys by description", { name: "DP-1", make: "Dell Inc.", model: "DELL U2720Q", serial: "8YT0R13" }, "desc:Dell Inc. DELL U2720Q 8YT0R13"],
        ["commas leave the description", { name: "DP-1", make: "Dell, Inc.", model: "U2720Q", serial: "8YT,0R13" }, "desc:Dell Inc. U2720Q 8YT0R13"],
        ["an empty make leaves no space", { name: "DP-1", make: "", model: "", serial: "0x030B1303" }, "desc:0x030B1303"],
        ["no serial keys by connector", { name: "DP-2", make: "LG", model: "HDR 4K", serial: "" }, "DP-2"]
    ];
    for (const [name, output, want] of identifiers) check("identifier: " + name, lib.identifier(output), want);
    check("identifier: each parsed output carries its own", desk.ok ? desk.outputs.map(o => o.identifier) : desk, ["desc:Dell Inc. DELL U2720Q 8YT0R13", "DP-2", "eDP-1"]);
    check("outputs request", lib.OUTPUTS_REQUEST, ["hyprctl", "-j", "monitors", "all"]);

    const outputs = desk.outputs;
    const goodRules = {
        "desc:Dell Inc. DELL U2720Q 8YT0R13": { mode: { width: 3840, height: 2160, refresh: 60 }, position: { x: 0, y: 0 }, scale: 1.5, transform: 0 },
        "DP-2": { mode: { width: 3840, height: 2160, refresh: 60 }, position: { x: 2560, y: 0 }, scale: 2, transform: 1 }
    };
    check("rulesError accepts available modes and whole logical pixels", lib.rulesError(goodRules, outputs), "");
    check("rulesLines renders monitor rules", lib.rulesLines(goodRules), { ok: true, lines: [
        'hl.monitor({ output = "DP-2", mode = "3840x2160@60", position = "2560x0", scale = 2, transform = 1 })',
        'hl.monitor({ output = "desc:Dell Inc. DELL U2720Q 8YT0R13", mode = "3840x2160@60", position = "0x0", scale = 1.5, transform = 0 })'
    ] });
    check("captureRules records explicit restore fields", lib.captureRules(outputs, { "DP-2": {} }), { "DP-2": { mode: { width: 3840, height: 2160, refresh: 59.997 }, position: { x: 2560, y: 0 }, scale: 2, transform: 0 } });
    check("overridden: live output differs from saved rule", lib.overridden({ scale: 1 }, outputs[1], outputs), true);
    check("overridden: live output equals saved rule within refresh tolerance", lib.overridden(lib.captureRules(outputs, { "DP-2": {} })["DP-2"], outputs[1], outputs), false);
    const ruleRefusals = [
        ["mode outside availableModes", { "DP-2": { mode: { width: 1920, height: 1080, refresh: 60 } } }, "refused: monitors.DP-2.mode unavailable"],
        ["fractional logical pixels", { "DP-2": { mode: { width: 3840, height: 2160, refresh: 60 }, scale: 1.3 } }, "refused: monitors.DP-2.scale fractional-logical-pixels"],
        ["Lua text injection through an identifier", { "DP-1\"": { scale: 1 } }, "refused: monitors.DP-1\" identifier refused"]
    ];
    for (const [name, rules, want] of ruleRefusals) check("rulesError refuses " + name, lib.rulesError(rules, outputs), want);
    const tiled = lib.parseOutputs(reply([DESK[0], monitor(3, "DP-5", { make: "Dell, Inc.", serial: "8YT0R13", x: 3840 })])).outputs;
    check("rulesError refuses a tiled output group", lib.rulesError({ "desc:Dell Inc. DELL U2720Q 8YT0R13": { scale: 2 } }, tiled), "refused: monitors.desc:Dell Inc. DELL U2720Q 8YT0R13 output=tiled");
    check("rulesError accepts a mode when Hyprland lists no modes", lib.rulesError({ "WAYLAND-1": { mode: { width: 1754, height: 932, refresh: 60 }, scale: 2 } }, nested.outputs), "");
    check("rulesError accepts a position-only rule for an unsized headless output", lib.rulesError({ "SMOKE-DISPLAYS-MODES": { position: { x: 128, y: 0 } } },
        [monitor(3, "SMOKE-DISPLAYS-MODES", { width: 0, height: 0 })]), "");
    check("layoutError refuses overlap", lib.layoutError({ "DP-2": { position: { x: 0, y: 0 } } }, outputs), "refused: monitors.layout=overlap a=DP-1 b=DP-2");
    check("layoutError refuses a gap", lib.layoutError({ "DP-2": { position: { x: 5000, y: 0 } } }, outputs), "refused: monitors.layout=gap");
    check("layoutError ignores an unsized nested headless output", lib.layoutError({ "DP-2": { position: { x: 2560, y: 0 } } },
        outputs.concat(lib.parseOutputs(reply([monitor(3, "SMOKE-DISPLAYS-MODES", { width: 0, height: 0 })])).outputs)), "");
    check("logicalRect swaps rotated sides", lib.logicalRect({ mode: { width: 100, height: 50, refresh: 60 }, position: { x: 0, y: 0 }, scale: 1, transform: 1 }), { x: 0, y: 0, width: 50, height: 100 });
    check("captureRules can capture tiled connectors separately", lib.captureRules(tiled, { "DP-1": {}, "DP-5": {} }), { "DP-1": { mode: { width: 3840, height: 2160, refresh: 59.997 }, position: { x: 0, y: 0 }, scale: 1.5, transform: 0 }, "DP-5": { mode: { width: 3840, height: 2160, refresh: 59.997 }, position: { x: 3840, y: 0 }, scale: 1.5, transform: 0 } });
    // Turning an output off and mirroring one, judged without outputs.
    // rows: [name, rules, refusal]
    const DELL = "desc:Dell Inc. DELL U2720Q 8YT0R13";
    const ruleShapes = [
        ["disabled that is no boolean", { "DP-2": { disabled: 1 } }, "refused: monitors.DP-2.disabled=shape want=boolean"],
        ["an empty mirror", { "DP-2": { mirror: "" } }, "refused: monitors.DP-2.mirror=shape want=identifier"],
        ["Lua text injection through a mirror", { "DP-2": { mirror: "DP-1\"" } }, "refused: monitors.DP-2.mirror=shape want=identifier"],
        ["a mirror of its own rule", { "DP-2": { mirror: "DP-2" } }, "refused: monitors.DP-2.mirror=self"],
        ["a mirror on an output it turns off", { "DP-2": { disabled: true, mirror: "DP-1" } }, "refused: monitors.DP-2.mirror=while-off"],
        ["a mirror of a mirror", { "DP-2": { mirror: "DP-1" }, "DP-1": { mirror: "eDP-1" } }, "refused: monitors.DP-2.mirror=chain target=DP-1"],
        ["a mirror of an output its rule turns off", { "DP-2": { mirror: "DP-1" }, "DP-1": { disabled: true } }, "refused: monitors.DP-2.mirror=target-off target=DP-1"],
        ["nothing for a mirror whose target has no rule", { "DP-2": { mirror: "DP-1" } }, ""],
        ["nothing for an output turned on", { "DP-2": { disabled: false } }, ""]
    ];
    for (const [name, rules, want] of ruleShapes) check("rulesError without outputs: " + name, lib.rulesError(rules, null), want);
    const mirroring = lib.parseOutputs(reply([DESK[0], monitor(1, "DP-2", { x: 2560, scale: 2, mirrorOf: "0" }), DESK[2]])).outputs;
    const tiledDesk = tiled.concat(outputs.slice(1));
    // Against the listed outputs. rows: [name, rules, outputs, refusal]
    const outputRefusals = [
        ["a mirror of an output nobody listed", { "DP-2": { mirror: "HDMI-A-1" } }, outputs, "refused: monitors.DP-2.mirror=target-absent target=HDMI-A-1"],
        ["a mirror of a tiled group", { "DP-2": { mirror: DELL } }, tiledDesk, "refused: monitors.DP-2.mirror=target-tiled target=" + DELL],
        ["a mirror of its own output by another name", { [DELL]: { mirror: "DP-1" } }, outputs, "refused: monitors." + DELL + ".mirror=self"],
        ["a mirror of an output Hyprland keeps off", { "DP-2": { mirror: "eDP-1" } }, outputs, "refused: monitors.DP-2.mirror=target-off target=eDP-1"],
        ["a mirror of an output a rule by identifier turns off", { "DP-2": { mirror: "DP-1" }, [DELL]: { disabled: true } }, outputs, "refused: monitors.DP-2.mirror=target-off target=DP-1"],
        ["a mirror of an output Hyprland mirrors", { "eDP-1": { mirror: "DP-2" } }, mirroring, "refused: monitors.eDP-1.mirror=chain target=DP-2"],
        ["every output off", { [DELL]: { disabled: true }, "DP-2": { disabled: true } }, outputs, "refused: monitors.layout=all-off"],
        ["one output on", { [DELL]: { disabled: true } }, outputs, ""],
        ["an output a rule turns back on", { [DELL]: { disabled: true }, "DP-2": { disabled: true }, "eDP-1": { disabled: false } }, outputs, ""],
        ["a mirror of an output that stays on", { "DP-2": { mirror: DELL } }, outputs, ""],
        ["a rule that stops a mirror", { "DP-2": { scale: 2 } }, mirroring, ""]
    ];
    for (const [name, rules, list, want] of outputRefusals) check("rulesError with outputs: " + name, lib.rulesError(rules, list), want);
    check("layoutError leaves out an output turned off", lib.layoutError({ [DELL]: { disabled: true }, "DP-2": { position: { x: 0, y: 0 } } }, outputs), "");
    check("layoutError leaves out a mirroring output", lib.layoutError({ "DP-2": { position: { x: 0, y: 0 }, mirror: DELL } }, outputs), "");
    check("layoutError refuses every output off", lib.layoutError({ [DELL]: { disabled: true }, "DP-2": { disabled: true } }, outputs), "refused: monitors.layout=all-off");

    check("rulesLines writes a mirror and leaves disabled to the guard", lib.rulesLines({ "DP-2": { scale: 2, mirror: DELL }, "eDP-1": { scale: 1, disabled: true } }).lines.slice(0, 3), [
        'hl.monitor({ output = "DP-2", scale = 2, mirror = "' + DELL + '" })',
        'hl.monitor({ output = "eDP-1", scale = 1 })',
        "do"
    ]);
    check("rulesLua writes disabled and mirror on every rule", lib.rulesLua({ "DP-2": { scale: 2, mirror: DELL }, "eDP-1": { disabled: true }, "HDMI-A-1": { scale: 1 } }), { ok: true, lua: [
        'hl.monitor({ output = "DP-2", scale = 2, disabled = false, mirror = "' + DELL + '" })',
        'hl.monitor({ output = "HDMI-A-1", scale = 1, disabled = false, mirror = "" })',
        'hl.monitor({ output = "eDP-1", disabled = true, mirror = "" })'
    ].join("\n") });
    check("rulesLua refuses what the judge refuses", lib.rulesLua({ "DP-2": { mirror: "DP-2" } }), { ok: false, error: "refused: monitors.DP-2.mirror=self" });
    check("rulesLua holds no handler", /hl\.on\(/.test(lib.rulesLua({ "eDP-1": { disabled: true }, "DP-2": { scale: 1 } }).lua), false);

    // The guard block, run under Lua. rows: [name, rules, steps, events]
    const laptop = ["eDP-1", "BOE 0x0BCA"], dock = ["DP-1", "Dell U2720Q"], fallback = ["FALLBACK", ""], side = ["DP-2", "LG"];
    const offLaptop = { "eDP-1": { scale: 1, disabled: true } };
    const guardRows = [
        ["boot: no output at load, the laptop, then a dock turns the laptop off once", offLaptop,
            [["reload", []], ["list", [laptop]], ["fire", "monitor.added"], ["list", [laptop, dock]], ["fire", "monitor.added"], ["list", [dock, side]], ["fire", "monitor.added"]],
            ["off eDP-1"]],
        ["undock: the last other output goes and the layer reloads", offLaptop,
            [["reload", [laptop, dock]], ["list", [dock]], ["fire", "monitor.removed"], ["tick"], ["mark"], ["list", [fallback]], ["fire", "monitor.removed"], ["tick"]],
            ["off eDP-1", "mark", "exec hyprctl reload"]],
        ["a trial that lights the laptop and turns the dock off keeps the trial", offLaptop,
            [["reload", [laptop, dock]], ["list", [laptop]], ["fire", "monitor.removed"], ["tick"]],
            ["off eDP-1"]],
        ["a removal read before the pass ends reloads nothing", offLaptop,
            [["reload", [laptop, dock]], ["list", [fallback]], ["fire", "monitor.removed"], ["list", [laptop]], ["tick"]],
            ["off eDP-1"]],
        ["a reload with the laptop alone leaves it on", offLaptop,
            [["reload", [laptop]], ["fire", "monitor.removed"], ["tick"]],
            []],
        ["FALLBACK keeps nothing on, and the layer reloads nothing it did not turn off", offLaptop,
            [["reload", [fallback]], ["fire", "monitor.added"], ["fire", "monitor.removed"], ["tick"]],
            []],
        ["an output a rule mirrors keeps nothing on", Object.assign({ "DP-2": { scale: 1, mirror: "eDP-1" } }, { "DP-1": { scale: 1, disabled: true } }),
            [["reload", [dock, side]]],
            []],
        ["a desc: rule names its output by short description", { "desc:BOE 0x0BCA": { scale: 1, disabled: true } },
            [["reload", [laptop]], ["fire", "monitor.added"], ["mark"], ["list", [laptop, dock]], ["fire", "monitor.added"]],
            ["mark", "off desc:BOE 0x0BCA"]],
        ["no rule turns an output off: no guard", { "eDP-1": { scale: 1 } },
            [["reload", [laptop, dock]], ["list", [laptop]], ["fire", "monitor.removed"], ["tick"]],
            []]
    ];
    for (const [name, rules, steps, want] of guardRows) check("guard block: " + name, luaEvents(lib.rulesLines(rules).lines, steps), want);

    // A trial is judged as Keep's save is: the saved rules with the trial's
    // over them, without outputs. The office: the laptop panel, with no
    // serial, and HDMI-A-1.
    const office = lib.parseOutputs(reply([DESK[2], monitor(1, "HDMI-A-1", { x: 1920, scale: 2 })].map(o => Object.assign({}, o, { disabled: false })))).outputs;
    const offPanel = { "eDP-1": { disabled: true } };
    check("trialPlan refuses a trial Keep could not save: a saved mirror of the panel it turns off",
        lib.trialPlan({ "DP-1": { mirror: "eDP-1" } }, offPanel, office), { ok: false, error: "refused: monitors.DP-1.mirror=target-off target=eDP-1" });
    const plan = lib.trialPlan({ "HDMI-A-1": { scale: 2 }, "eDP-1": { scale: 1.5 } }, offPanel, office);
    check("trialPlan keeps the saved rules under the trial's", [plan.ok, plan.lua, plan.kept, plan.restoreRules],
        [true, lib.rulesLua(offPanel).lua, { "HDMI-A-1": { scale: 2 }, "eDP-1": { disabled: true } }, lib.captureRules(office, { "eDP-1": {} })]);
    check("trialPlan's restore starts with the captured rules", plan.restore.indexOf(lib.rulesLua(lib.captureRules(office, { "eDP-1": {} })).lua + "\n"), 0);
    // The restore, run under Lua after the trial's outputs change.
    // rows: [name, outputs lit once the restore's pass ends, events]
    const restoreRows = [
        ["the dock went during the trial: only FALLBACK is lit, so it reloads", [["FALLBACK", ""]], ["exec hyprctl reload"]],
        ["another output is lit: no reload", [["HDMI-A-1", ""]], []]
    ];
    for (const [name, lit, want] of restoreRows) check("restore: " + name, luaEvents([plan.restore], [["reload", lit], ["tick"]]), want);
    check("trialPlan judges the trial against the outputs first", lib.trialPlan({}, { "eDP-1": { disabled: true }, "HDMI-A-1": { disabled: true } }, office),
        { ok: false, error: "refused: monitors.layout=all-off" });
    check("captureRules records an output that is off", lib.captureRules(outputs, { "eDP-1": {} }),
        { "eDP-1": { mode: { width: 2880, height: 1800, refresh: 59.997 }, position: { x: 0, y: 0 }, scale: 1.5, transform: 0, disabled: true } });
    check("captureRules records a mirror by the target's identifier", lib.captureRules(mirroring, { "DP-2": {} })["DP-2"].mirror, DELL);
    check("captureRules records a mirror of a tiled member by connector",
        lib.captureRules(lib.parseOutputs(reply([DESK[0], monitor(3, "DP-5", { make: "Dell, Inc.", serial: "8YT0R13", x: 3840 }), monitor(4, "HDMI-A-1", { mirrorOf: "3" })])).outputs, { "HDMI-A-1": {} })["HDMI-A-1"].mirror, "DP-5");
    check("captureRules records no field for an output on", Object.keys(lib.captureRules(outputs, { "DP-2": {} })["DP-2"]), ["mode", "position", "scale", "transform"]);
    // rows: [name, rule, output index, outputs, overridden]
    const overrides = [
        ["a rule that turns an output off while another is on", { disabled: true }, 1, outputs, true],
        ["a rule that turns the only output off", { disabled: true }, 0, lib.parseOutputs(reply([DESK[0], DESK[2]])).outputs, false],
        ["an output off that the rule keeps off", { disabled: true }, 2, outputs, false],
        ["an output off that the rule turns on", {}, 2, outputs, true],
        ["a mirror Hyprland shows", { mirror: DELL }, 1, mirroring, false],
        ["a mirror Hyprland does not show", { mirror: DELL }, 1, outputs, true],
        ["a mirror of another output", { mirror: "eDP-1" }, 1, mirroring, true],
        ["a mirror the rule does not name", {}, 1, mirroring, true]
    ];
    for (const [name, rule, index, list, want] of overrides) {
        const live = list[index];
        const current = { mode: { width: live.width, height: live.height, refresh: live.refreshRate }, position: { x: live.x, y: live.y }, scale: live.scale, transform: live.transform };
        check("overridden: " + name, lib.overridden(Object.assign(current, rule), live, list), want);
    }
    check("captureRules skips an invalid mode for an unsized nested headless output", lib.captureRules(lib.parseOutputs(reply([monitor(3, "SMOKE-DISPLAYS-MODES", { width: 0, height: 0 })])).outputs, { "SMOKE-DISPLAYS-MODES": {} }),
        { "SMOKE-DISPLAYS-MODES": { position: { x: 0, y: 0 }, scale: 1.5, transform: 0 } });

    colourSuite(lib, check, outputs);
}

// Colour mode, depth and HDR levels, and the panel support they need.
function colourSuite(lib, check, outputs) {
    check("support request", lib.SUPPORT_REQUEST, ["hyprctl", "systeminfo"]);
    // rows: [name, panels, support]
    const reads = [
        ["a panel that takes everything", [["DP-1", ALL]], { "DP-1": { hdr: true, chroma: true, bt2020: true, colourModes: ["auto", "srgb", "wide", "edid", "hdr", "hdredid", "dcip3", "dp3", "adobe"] } }],
        ["a panel that takes nothing", [["DP-1", NONE]], { "DP-1": { hdr: false, chroma: false, bt2020: false, colourModes: ["srgb"] } }],
        ["two panels, each its own", [["DP-1", Object.assign({}, NONE, { chroma: true })], ["eDP-1", Object.assign({}, NONE, { bt2020: true, vrr: true })]],
            { "DP-1": { hdr: false, chroma: true, bt2020: false, colourModes: ["srgb", "edid"] }, "eDP-1": { hdr: false, chroma: false, bt2020: true, colourModes: ["auto", "srgb", "wide", "dcip3", "dp3", "adobe"] } }],
        ["no panel", [], {}]
    ];
    for (const [name, panels, want] of reads) check("parseSupport: " + name, lib.parseSupport(systeminfo(panels)), { ok: true, support: want });
    check("parseSupport: the nested reply", lib.parseSupport(NESTED_SYSTEMINFO), { ok: true, support: { "WAYLAND-1": { hdr: false, chroma: false, bt2020: false, colourModes: ["srgb"] } } });
    const full = systeminfo([["DP-1", ALL]]);
    // rows: [name, text, refusal]
    const supportRefusals = [
        ["a panel missing a line", full.replace("\n\t\t\tbt2020 " + MARK[true], ""), "refused: support=shape panel=\"DP-1\" line=bt2020"],
        ["a line under another name", full.replace("\t\t\tchroma ", "\t\t\tchromo "), "refused: support=shape panel=\"DP-1\" line=chroma"],
        ["a mark Hyprland never prints", full.replace("vrr capable " + MARK[true], "vrr capable yes"), "refused: support=shape panel=\"DP-1\" line=vrr capable"],
        ["an edid line that carries a mark", full.replace("\t\tedid:", "\t\tedid: " + MARK[true]), "refused: support=shape panel=\"DP-1\" line=edid"],
        ["no monitor section", "Couldn't connect to the socket", "refused: support=shape want=monitor-info"],
        ["a section that ends before the state", full.slice(0, full.indexOf("\n\nState:")), "refused: support=shape line=\"end\""],
        ["a panel line in another shape", full.replace("\tPanel DP-1: 3840x2160, ", "\tPanel DP-1 "), "refused: support=shape line=\"\\tPanel DP-1 DP-1 Dell Inc. DELL U2720Q 8YT0R13 -> backe..."]
    ];
    for (const [name, text, want] of supportRefusals) check("parseSupport refuses " + name, lib.parseSupport(text), { ok: false, error: want });
    // rows: [name, panel flags, colour modes]
    const offered = [
        ["BT.2020 without HDR metadata", { hdr: false, chroma: false, bt2020: true }, ["auto", "srgb", "wide", "dcip3", "dp3", "adobe"]],
        ["HDR metadata without BT.2020", { hdr: true, chroma: false, bt2020: false }, ["srgb"]],
        ["chromaticity alone", { hdr: false, chroma: true, bt2020: false }, ["srgb", "edid"]],
        ["BT.2020 and HDR metadata", { hdr: true, chroma: false, bt2020: true }, ["auto", "srgb", "wide", "hdr", "hdredid", "dcip3", "dp3", "adobe"]]
    ];
    for (const [name, panel, want] of offered) check("colourModes: " + name, lib.colourModes(panel), want);

    const tenBit = lib.parseOutputs(reply([monitor(0, "DP-1", { currentFormat: "XBGR2101010" })]));
    check("parseOutputs: a 10-bit format reads as depth 10", tenBit.ok ? tenBit.outputs[0].bitdepth : tenBit, 10);
    // Judged without outputs. rows: [name, rule, refusal]
    const shapes = [
        ["a colour mode Hyprland lacks", { cm: "rec709" }, "refused: monitors.DP-2.cm=shape want=colour-mode"],
        ["a depth of 12", { bitdepth: 12 }, "refused: monitors.DP-2.bitdepth=shape want=8|10"],
        ["an HDR brightness of 0", { cm: "hdr", sdrbrightness: 0 }, "refused: monitors.DP-2.sdrbrightness=shape want=positive"],
        ["an HDR saturation that is no number", { cm: "hdr", sdrsaturation: "1" }, "refused: monitors.DP-2.sdrsaturation=shape want=positive"],
        ["an HDR level outside an HDR mode", { cm: "wide", sdrbrightness: 1.2 }, "refused: monitors.DP-2.sdrbrightness=outside-hdr"],
        ["an HDR level with no colour mode", { sdrsaturation: 1.2 }, "refused: monitors.DP-2.sdrsaturation=outside-hdr"],
        ["variable refresh, which Hyprland never applies alone", { vrr: 1 }, "refused: monitors.DP-2 has unknown key \"vrr\""],
        ["every colour field Hyprland takes", { cm: "hdredid", bitdepth: 10, sdrbrightness: 1.5, sdrsaturation: 0.8 }, ""]
    ];
    for (const [name, rule, want] of shapes) check("rulesError without outputs: " + name, lib.rulesError({ "DP-2": rule }, null), want);

    // Judged against the outputs and the panels. DP-1 takes everything,
    // DP-2 nothing, eDP-1 is off. rows: [name, rule, support, refusal]
    const panels = { "DP-1": lib.parseSupport(systeminfo([["DP-1", ALL]])).support["DP-1"], "DP-2": lib.parseSupport(systeminfo([["DP-2", NONE]])).support["DP-2"] };
    const DELL = "desc:Dell Inc. DELL U2720Q 8YT0R13";
    const fits = [
        ["HDR on a panel without it", { "DP-2": { cm: "hdr" } }, panels, "refused: monitors.DP-2.cm=unsupported cm=hdr"],
        ["the display's own colours without its chromaticity", { "DP-2": { cm: "edid" } }, panels, "refused: monitors.DP-2.cm=unsupported cm=edid"],
        ["a wide mode before the panels are read", { [DELL]: { cm: "wide" } }, null, "refused: monitors." + DELL + " support=unread"],
        ["a wide mode on an output the panels leave out", { [DELL]: { cm: "wide" } }, { "DP-2": panels["DP-2"] }, "refused: monitors." + DELL + " support=absent"],
        ["sRGB before the panels are read", { "DP-2": { cm: "srgb" } }, null, ""],
        ["HDR on a panel that takes it", { [DELL]: { cm: "hdr", sdrbrightness: 1.4 } }, panels, ""],
        ["a colour mode for an output that is off", { "eDP-1": { cm: "hdr" } }, panels, ""]
    ];
    for (const [name, rules, support, want] of fits) check("rulesError with panels: " + name, lib.rulesError(rules, outputs, support), want);
    const mirroring = lib.parseOutputs(reply([DESK[0], monitor(1, "DP-2", { x: 2560, scale: 2, mirrorOf: "0" }), DESK[2]])).outputs;
    check("rulesError with panels: a colour mode for an output that mirrors", lib.rulesError({ "DP-2": { cm: "wide" } }, mirroring, { "DP-1": panels["DP-1"] }), "");

    // rows: [name, outputs, support, names to read]
    const missing = [
        ["every output that is on before a read", outputs, null, ["DP-1", "DP-2"]],
        ["an output the panels lack", outputs, { "DP-1": panels["DP-1"] }, ["DP-2"]],
        ["none for an output that mirrors", mirroring, { "DP-1": panels["DP-1"] }, []]
    ];
    for (const [name, list, support, want] of missing) check("supportMissing: " + name, lib.supportMissing(list, support), want);
    // rows: [name, support, event data, support after]
    const drops = [
        ["the panel of the connector an event names", panels, "3,DP-2,LG HDR 4K", { "DP-1": panels["DP-1"] }],
        ["a description with commas", { "DP-2": panels["DP-2"] }, "4,DP-2,Dell, Inc. U2720Q", {}],
        ["nothing for a connector it lacks", { "DP-1": panels["DP-1"] }, "5,HDMI-A-1,Dell, Inc. X", { "DP-1": panels["DP-1"] }],
        ["nothing before a read", null, "3,DP-2,LG HDR 4K", null]
    ];
    for (const [name, support, data, want] of drops) check("supportWithout: " + name, lib.supportWithout(support, data), want);
    check("supportNeeded: sRGB and no colour mode need no panel", lib.supportNeeded({ "DP-1": { cm: "srgb" }, "DP-2": { scale: 1 } }), false);
    check("supportNeeded: a wide mode needs one", lib.supportNeeded({ "DP-1": { scale: 1 }, "DP-2": { cm: "wide" } }), true);
    const office = lib.parseOutputs(reply([DESK[2], monitor(1, "HDMI-A-1", { x: 1920, scale: 2 })].map(o => Object.assign({}, o, { disabled: false })))).outputs;
    check("trialPlan judges a colour mode against the panels", lib.trialPlan({}, { "HDMI-A-1": { cm: "hdr" } }, office, { "HDMI-A-1": panels["DP-2"], "eDP-1": panels["DP-2"] }),
        { ok: false, error: "refused: monitors.HDMI-A-1.cm=unsupported cm=hdr" });

    check("rulesLines renders each colour field", lib.rulesLines({ "DP-2": { scale: 2, cm: "hdr", bitdepth: 10, sdrbrightness: 1.25, sdrsaturation: 0.9 } }).lines, [
        'hl.monitor({ output = "DP-2", scale = 2, cm = "hdr", bitdepth = 10, sdrbrightness = 1.25, sdrsaturation = 0.9 })'
    ]);
    check("rulesLines leaves out a colour field the rule does not name", lib.rulesLines({ "DP-2": { cm: "wide" } }).lines, ['hl.monitor({ output = "DP-2", cm = "wide" })']);
    check("rulesLua writes the HDR levels beside a colour mode", lib.rulesLua({ "DP-2": { cm: "srgb" }, "DP-1": { cm: "hdr", sdrbrightness: 1.5 }, "eDP-1": { bitdepth: 10 } }), { ok: true, lua: [
        'hl.monitor({ output = "DP-1", cm = "hdr", sdrbrightness = 1.5, sdrsaturation = 1, disabled = false, mirror = "" })',
        'hl.monitor({ output = "DP-2", cm = "srgb", sdrbrightness = 1, sdrsaturation = 1, disabled = false, mirror = "" })',
        'hl.monitor({ output = "eDP-1", bitdepth = 10, disabled = false, mirror = "" })'
    ].join("\n") });

    // The restore takes back each colour field the trial names, as
    // Hyprland lists it. rows: [name, live fields, trial rule, captured colour]
    const base = ["mode", "position", "scale", "transform"];
    const captures = [
        ["the colour mode alone", {}, { cm: "wide" }, { cm: "srgb" }],
        ["the HDR levels Hyprland shows beside an HDR mode", { colorManagementPreset: "hdr", sdrBrightness: 1.3, sdrSaturation: 1.1 }, { cm: "srgb" }, { cm: "hdr", sdrbrightness: 1.3, sdrsaturation: 1.1 }],
        ["a 10-bit depth", { currentFormat: "XRGB2101010" }, { bitdepth: 8 }, { bitdepth: 10 }],
        ["no colour field for a trial that names none", { colorManagementPreset: "hdr", currentFormat: "XRGB2101010" }, { scale: 2 }, {}]
    ];
    for (const [name, live, rule, want] of captures) {
        const list = lib.parseOutputs(reply([monitor(0, "DP-1", live)])).outputs;
        const got = lib.captureRules(list, { "DP-1": rule })["DP-1"];
        const colour = {};
        Object.keys(got).filter(key => base.indexOf(key) === -1).forEach(key => { colour[key] = got[key]; });
        check("captureRules: " + name, colour, want);
    }

    // rows: [name, rule, live fields, overridden]
    const overrides = [
        ["a colour mode Hyprland fell back from", { cm: "hdr" }, {}, true],
        ["a colour mode Hyprland shows", { cm: "wide" }, { colorManagementPreset: "wide" }, false],
        ["auto shown as wide", { cm: "auto" }, { colorManagementPreset: "wide" }, false],
        ["auto shown as sRGB", { cm: "auto" }, {}, false],
        ["an HDR level Hyprland does not show", { cm: "hdr", sdrbrightness: 1.5 }, { colorManagementPreset: "hdr" }, true],
        ["an HDR level left at 1", { cm: "hdr" }, { colorManagementPreset: "hdr", sdrSaturation: 1.2 }, true],
        ["a depth Hyprland could not set", { bitdepth: 10 }, {}, true],
        ["a depth Hyprland shows", { bitdepth: 10 }, { currentFormat: "XRGB2101010" }, false],
        ["a colour mode on an output that is off", { cm: "hdr", disabled: true }, { disabled: true }, false],
        ["a colour mode on an output that mirrors", { cm: "hdr", mirror: "DP-2" }, { mirrorOf: "1" }, false]
    ];
    for (const [name, rule, live, want] of overrides) {
        const list = lib.parseOutputs(reply([monitor(0, "DP-1", live), monitor(1, "DP-2", { x: 3840 })])).outputs;
        const output = list[0];
        const current = { mode: { width: output.width, height: output.height, refresh: output.refreshRate }, position: { x: output.x, y: output.y }, scale: output.scale, transform: output.transform };
        check("overridden: " + name, lib.overridden(Object.assign(current, rule), output, list), want);
    }
}

suite(load(LOGIC), report);

// Each control removes one rule from a copy of the file and keeps the text
// around it; the suite must fail on every copy.
const CONTROLS = [
    ["a serial keys by description", 'if (output.serial === "") return output.name;', "return output.name;"],
    ["commas leave the identifier", '.trim().replace(/,/g, "");', ".trim();"],
    ["the description is trimmed", ' + output.serial).trim().replace', " + output.serial).replace"],
    ["outputs are a list", 'if (!Array.isArray(list)) return { ok: false, error: "refused: outputs=shape want=list" };', ""],
    ["an output's strings are judged", 'for (var s = 0; s < strings.length; s++) if (typeof m[strings[s]] !== "string") return bad(strings[s]);', ""],
    ["an output's whole numbers are judged", "for (var w = 0; w < whole.length; w++) if (!Number.isInteger(m[whole[w]])) return bad(whole[w]);", ""],
    ["vrr is a boolean", 'if (typeof m.vrr !== "boolean") return bad("vrr");', ""],
    ["a refresh rate is a number", 'if (typeof m.refreshRate !== "number" || !isFinite(m.refreshRate)) return bad("refreshRate");', ""],
    ["a scale is a number", 'if (typeof m.scale !== "number" || !isFinite(m.scale)) return bad("scale");', ""],
    ["disabled is a boolean in a reply", 'if (typeof m.disabled !== "boolean") return bad("disabled");', ""],
    ["a mode list is a list", 'if (!Array.isArray(m.availableModes)) return bad("availableModes");', ""],
    ["an output is an object", 'if (!isPlainObject(m)) return bad("object");', ""],
    ["a listed mode parses", 'if (parsed === null) return bad("availableModes");', "if (parsed === null) continue;"],
    ["mirrorOf names the mirrored output", "out[j].mirrorOf = target[0].name;", "out[j].mirrorOf = out[j].mirrorOf;"],
    ["mirrorOf names an output", 'if (target.length !== 1) return { ok: false, error: "refused: outputs=shape output=" + j', 'if (false) return { ok: false, error: "refused: outputs=shape output=" + j']
    ,["fractional logical pixels accepted", "if (!scaleFits(normalized.mode, normalized.scale))", "if (false)"],
    ["mode outside availableModes accepted", "if (rule.mode !== undefined && modes.length > 0 && !modes.some(function (mode) { return sameMode(mode, normalized.mode); }))", "if (false)"],
    ["tiled output groups accepted", 'if (matching.length > 1 && matching[0].identifier === id) return "refused: " + at + " output=tiled";', ""],
    ["Lua text injection through a field", "if (!OUTPUT_NAME.test(id)) return \"refused: \" + at + \" identifier refused\";", "if (false) return \"refused: \" + at + \" identifier refused\";"],
    ["restore missing a field", "scale: output.scale,", ""],
    ["unsized restore keeps an invalid mode", "if (output.width <= 0 || output.height <= 0) delete rule.mode;", ""],
    ["overlap accepted", "if (overlap(rects[i].rect, rects[j].rect)) return \"refused: monitors.layout=overlap a=\" + rects[i].id + \" b=\" + rects[j].id;", ""],
    ["gap accepted", "if (seen.length !== rects.length) return \"refused: monitors.layout=gap\";", ""],
    ["unsized output blocks a layout", "if (rect.width > 0 && rect.height > 0) rects.push({ id: output.name, rect: rect });", "rects.push({ id: output.name, rect: rect });"],
    ["rotated side swap lost", "if (sideSwapped(rule.transform)) return { width: height, height: width };", ""],
    ["disabled is a boolean in a rule", 'if (rule.disabled !== undefined && typeof rule.disabled !== "boolean")', "if (false)"],
    ["a mirror is an output identifier", 'if (rule.mirror !== undefined && (typeof rule.mirror !== "string" || !OUTPUT_NAME.test(rule.mirror)))', "if (false)"],
    ["a rule mirrors itself", 'if (rule.mirror === id) return at + ".mirror=self";', ""],
    ["a rule mirrors while off", 'if (rule.disabled === true) return at + ".mirror=while-off";', ""],
    ["a rule mirrors a mirror rule", 'if (isPlainObject(target) && target.mirror !== undefined) return at + ".mirror=chain target=" + rule.mirror;', ""],
    ["a rule mirrors a rule that turns off", 'if (isPlainObject(target) && target.disabled === true) return at + ".mirror=target-off target=" + rule.mirror;', ""],
    ["a mirror names no listed output", 'if (targets.length === 0) return at + ".mirror=target-absent target=" + rule.mirror;', ""],
    ["a mirror names a tiled group", 'if (targets.length > 1 && targets[0].identifier === rule.mirror) return at + ".mirror=target-tiled target=" + rule.mirror;', ""],
    ["a mirror names its own output", 'if (targets[0].name === output.name) return at + ".mirror=self";', ""],
    ["a mirror shows a mirroring output", 'if (state.mirror) return at + ".mirror=chain target=" + rule.mirror;', ""],
    ["a mirror shows an output that is off", 'if (state.disabled) return at + ".mirror=target-off target=" + rule.mirror;', ""],
    ["every output off accepted", 'if (Array.isArray(outputs) && !outputs.some(function (output) { return staysOn(rules, output); })) return "refused: monitors.layout=all-off";', ""],
    ["a rule's state loses to Hyprland's", "if (rule === null) return { disabled: output.disabled, mirror: output.mirrorOf !== null };", "return { disabled: output.disabled, mirror: output.mirrorOf !== null };"],
    ["the layout draws outputs that are off", "outputs.filter(function (output) { return staysOn(rules, output); }).forEach(", "outputs.filter(function (output) { return !output.disabled; }).forEach("],
    ["the layer line drops the mirror", 'if (rule.mirror !== undefined) fields.push("mirror = " + luaString(rule.mirror));', ""],
    ["an eval leaves disabled out", 'fields.push("disabled = " + (rule.disabled === true ? "true" : "false"));', ""],
    ["an eval leaves an empty mirror out", 'fields.push("mirror = " + (rule.mirror === undefined ? "\\"\\"" : luaString(rule.mirror)));', 'if (rule.mirror !== undefined) fields.push("mirror = " + luaString(rule.mirror));'],
    ["a layer with nothing off holds a guard", "if (off.length === 0) return [];", ""],
    ["the guard counts FALLBACK as on", 'if m.name ~= \\"FALLBACK\\" and not', "if not"],
    ["the guard counts a mirroring output as on", " and not vgs_monitors_named(m, vgs_monitors_mirroring) then return true end", " then return true end"],
    ["the guard matches no desc: identifier", ' or \\"desc:\\" .. m.description == id', ""],
    ["the guard waits for an output at load", '"    vgs_monitors_apply()",', ""],
    ["the guard waits for no output to come", '"    hl.on(\\"monitor.added\\", vgs_monitors_apply)",', ""],
    ["the guard turns outputs off twice", "if vgs_monitors_applied or not vgs_monitors_others_on() then return end", "if not vgs_monitors_others_on() then return end"],
    ["the guard never reloads", 'then hl.exec_cmd(\\"hyprctl reload\\") end', "then end"],
    ["the guard reloads with nothing it turned off", 'relightLines("vgs_monitors_applied")', 'relightLines("")'],
    ["the reload ignores a lit output", '        "        if m.name ~= \\"FALLBACK\\" then return end",\n', ""],
    ["the reload counts FALLBACK as lit", 'm.name ~= \\"FALLBACK\\" then return end', "true then return end"],
    ["the reload reads the outputs before the pass ends", '"hl.timer(function()",', '"(function(f) f() end)(function()",'],
    ["a restore never reloads", 'restore: restore.lua + "\\n" + relightLines("").join("\\n")', "restore: restore.lua"],
    ["a trial ignores the saved rules", "var badKept = rulesError(kept, null);", 'var badKept = "";'],
    ["Keep saves the trial alone", "var kept = Object.assign({}, saved, rules);", "var kept = rules;"],
    ["restore leaves an output off on", "if (output.disabled) rule.disabled = true;", ""],
    ["restore drops a mirror", "if (output.mirrorOf !== null) rule.mirror = mirrorTarget(outputs, output.mirrorOf);", ""],
    ["restore names a tiled mirror by its group", "return outputs.filter(function (output) { return output.identifier === target.identifier; }).length > 1 ? name : target.identifier;", "return target.identifier;"],
    ["overridden ignores disabled", "return (rule.disabled === true ? othersOn && !output.disabled : output.disabled)\n        || !mirrored", "return !mirrored"],
    ["overridden flags an off rule the layer left on", "rule.disabled === true ? othersOn && !output.disabled", "rule.disabled === true ? !output.disabled"],
    ["overridden ignores the mirror", "        || !mirrored\n", "\n"],
    ["overridden ignores the mirror's target", "output.mirrorOf !== null && outputsByKey(outputs, rule.mirror).some(function (target) { return target.name === output.mirrorOf; })", "output.mirrorOf !== null"],
    ["the panels need no monitor section", 'if (i === -1) return { ok: false, error: "refused: support=shape want=monitor-info" };', ""],
    ["a panel line under another name reads", "if (line === undefined || line.indexOf(prefix) !== 0) return bad;", "if (line === undefined) return bad;"],
    ["a panel takes any mark", "!hasOwn(MARKS, mark)) return bad;", "false) return bad;"],
    ["the edid line takes a mark", 'prefix === "\\t\\tedid:" ? mark !== "" :', 'prefix === "\\t\\tedid:" ? false :'],
    ["the panels need no state section after them", 'if (lines[i] !== "State:") return', "if (false) return"],
    ["a blank line ends the panels", 'if (lines[i].trim() === "") continue;', ""],
    ["a panel's marks are lost", "entry[PANEL_FIELDS[k][0]] = MARKS[mark];", "entry[PANEL_FIELDS[k][0]] = true;"],
    ["sRGB needs BT.2020", 'if (mode === "srgb") return true;', ""],
    ["the display's own colours need BT.2020", 'if (mode === "edid") return panel.chroma;', ""],
    ["HDR needs no HDR metadata", "return panel.bt2020 && panel.hdr;", "return panel.bt2020;"],
    ["HDR needs no BT.2020", "return panel.bt2020 && panel.hdr;", "return panel.hdr;"],
    ["a 10-bit format reads as 8", "bitdepth: /2101010$/.test(m.currentFormat) ? 10 : 8,", "bitdepth: 8,"],
    ["any colour mode is a rule", "if (rule.cm !== undefined && COLOUR_MODES.indexOf(rule.cm) === -1)", "if (false)"],
    ["any depth is a rule", "if (rule.bitdepth !== undefined && rule.bitdepth !== 8 && rule.bitdepth !== 10)", "if (false)"],
    ["an HDR level of 0 is a rule", '|| value <= 0) return at + "." + SDR_KEYS[k]', ') return at + "." + SDR_KEYS[k]'],
    ["an HDR level need be no number", 'if (typeof value !== "number" || !isFinite(value) || value <= 0)', "if (value <= 0)"],
    ["an HDR level holds outside an HDR mode", 'if (HDR_MODES.indexOf(rule.cm) === -1) return at + "." + SDR_KEYS[k] + "=outside-hdr";', ""],
    ["a judge that ignores the panels lets HDR through", "if (support[output.name].colourModes.indexOf(rule.cm) === -1)", "if (false)"],
    ["an unread panel list reads as absent", 'if (!isPlainObject(support)) return at + " support=unread";', ""],
    ["an output the panels leave out is judged", 'if (!hasOwn(support, output.name)) return at + " support=absent";', ""],
    ["sRGB needs the panels", 'if (rule.cm === undefined || rule.cm === "srgb") return "";', 'if (rule.cm === undefined) return "";'],
    ["an output that is off needs the panels", 'if (output.disabled) return "";', ""],
    ["an output that mirrors needs the panels", 'if (output.mirrorOf !== null) return "";', ""],
    ["a trial ignores the panels", "var bad = rulesError(rules, outputs, support);", "var bad = rulesError(rules, outputs);"],
    ["the layer line drops the colour mode", 'if (rule.cm !== undefined) fields.push("cm = " + luaString(rule.cm));', ""],
    ["the layer line drops the depth", 'if (rule.bitdepth !== undefined) fields.push("bitdepth = " + luaNumber(rule.bitdepth));', ""],
    ["the layer line drops the HDR levels", 'SDR_KEYS.forEach(function (key) { if (rule[key] !== undefined) fields.push(key + " = " + luaNumber(rule[key])); });', ""],
    ["an eval leaves the HDR levels out beside a colour mode", 'if (rule.cm !== undefined) SDR_KEYS.forEach(function (key) { if (rule[key] === undefined) fields.push(key + " = 1"); });', ""],
    ["a restore puts the trial's colour mode back", "rule.cm = output.colorManagementPreset;", "rule.cm = named.cm;"],
    ["a restore drops the HDR levels", "if (HDR_MODES.indexOf(rule.cm) !== -1) SDR_KEYS.forEach(function (key) { if (live[key] > 0) rule[key] = live[key]; });", ""],
    ["a restore drops the depth", "if (named.bitdepth !== undefined) rule.bitdepth = output.bitdepth;", ""],
    ["a restore sets a colour mode the trial left", "if (named.cm !== undefined) {", "if (true) {"],
    ["overridden ignores the colour mode", "if (shows.indexOf(output.colorManagementPreset) === -1) return true;", ""],
    ["overridden reads auto as itself", 'var shows = rule.cm === "auto" ? ["wide", "srgb"] : [rule.cm];', "var shows = [rule.cm];"],
    ["overridden ignores the HDR levels", "return Math.abs((rule[key] === undefined ? 1 : rule[key]) - live[key]) > 0.0001;", "return false;"],
    ["overridden reads an absent HDR level as Hyprland's", "(rule[key] === undefined ? 1 : rule[key])", "(rule[key] === undefined ? live[key] : rule[key])"],
    ["overridden ignores the depth", "return rule.bitdepth !== undefined && rule.bitdepth !== output.bitdepth;", "return false;"],
    ["overridden reads the colour of an output that is off", "if (output.disabled) return false;", ""],
    ["overridden reads the colour of an output that mirrors", "if (output.mirrorOf !== null) return false;", ""],
    ["variable refresh is a rule key", '"sdrbrightness", "sdrsaturation"];\nvar SDR_KEYS', '"sdrbrightness", "sdrsaturation", "vrr"];\nvar SDR_KEYS'],
    ["an output that is off reads as missing", "return !output.disabled && output.mirrorOf === null && !hasOwn(support, output.name);", "return output.mirrorOf === null && !hasOwn(support, output.name);"],
    ["an output that mirrors reads as missing", "return !output.disabled && output.mirrorOf === null && !hasOwn(support, output.name);", "return !output.disabled && !hasOwn(support, output.name);"],
    ["a panel read reads as missing", "return !output.disabled && output.mirrorOf === null && !hasOwn(support, output.name);", "return !output.disabled && output.mirrorOf === null;"],
    ["an event's id names the connector", 'var name = String(eventData).split(",")[1];', 'var name = String(eventData).split(",")[0];'],
    ["an event drops no panel", "delete out[name];", ""],
    ["sRGB needs a panel read", ' && rules[id].cm !== "srgb";', ";"],
    ["a rule with no colour mode needs a panel read", "&& rules[id].cm !== undefined && rules[id].cm", "&& rules[id].cm"]
];

fs.mkdirSync(path.join(__dirname, "..", "tmp"), { recursive: true });
const temp = fs.mkdtempSync(path.join(__dirname, "..", "tmp", "monitor-logic-control-"));
try {
    const source = fs.readFileSync(LOGIC, "utf8");
    const mutant = path.join(temp, "MonitorLogic.js");
    for (const [label, needle, replacement, expected] of CONTROLS) {
        const count = source.split(needle).length - 1;
        if (count !== 1) { report("control: " + label + ": the text to replace occurs once", count, 1); continue; }
        const edited = source.replace(needle, () => replacement);
        if (edited === source) { report("control: " + label + ": the copy differs", false, true); continue; }
        fs.writeFileSync(mutant, edited);
        // Loaded outside the try, so a copy that does not evaluate fails the
        // suite instead of passing for a control.
        const lib = load(mutant);
        // A control that names its check passes only when that check
        // reads otherwise; a throw is no red for it.
        const reds = [];
        let thrown = null;
        try {
            suite(lib, (name, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) reds.push(name); });
        } catch (e) {
            thrown = String(e.message || e);
        }
        if (expected === undefined) report("control: the suite fails without the rule: " + label, reds.length > 0 || thrown !== null, true);
        else report("control: " + label + " turns red: " + expected, { red: reds.includes(expected), thrown: thrown }, { red: true, thrown: null });
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}

if (failures > 0) { console.log("test-monitor-logic: " + failures + " failing"); process.exit(1); }
console.log("test-monitor-logic: ok");
