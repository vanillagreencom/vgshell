#!/usr/bin/env node
// Checks for the Hyprland layer's decisions: the manifest's `hyprland` key
// and the key grammar in shell/Core/PluginLogic.js, a plugins row's `keys`
// under PluginLogic.configError, PluginLogic.hyprlandSection with the input
// options a plugins row sets, the text
// shell/Core/HyprlandLayer.js renders, and the writer's sequence,
// HyprlandLayer.step. Both files load under node through
// bin/lib/qml-library.js, as the shell loads them.
//
// The controls at the end edit a copy of one file, one rule at a time, and
// the suite must fail on every copy. Exit 1 when a row or a control fails.
"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { load } = require("../bin/lib/qml-library.js");

// A library's objects come from another realm, so they are compared as the
// JSON they write.
const same = (got, want, message) => assert.deepStrictEqual(JSON.parse(JSON.stringify(got === undefined ? null : got)), JSON.parse(JSON.stringify(want === undefined ? null : want)), message);

const logicFile = path.join(__dirname, "..", "shell", "Core", "PluginLogic.js");
const layerFile = path.join(__dirname, "..", "shell", "Core", "HyprlandLayer.js");
const shellFile = path.join(__dirname, "..", "shell", "shell.qml");

const service = { schemaVersion: 1, id: "acme.keys", name: "K", version: "1.0.0", author: "a", description: "d", kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["shortcut"] };
const overlayRule = { namespace: "^vgs:overlay$", blur: true, ignoreAlpha: 0.6 };
const toggle = { shortcut: "toggle", key: "SUPER+SPACE" };
// The border colours as Theme publishes them, `#aarrggbb`.
const colours = { accent: "#ff5a3659", border: "#80112233", borderSubtle: "#ff222222", warning: "#ffffaa00", surfaceRaised: "#ff333333", onAccent: "#ff000000", text: "#ffeeeeee", onWarning: "#ff010101" };
const theme = { colours, hyprland: { border: { size: 4 }, window: { radius: 8, roundingPower: 3 }, motion: { preset: "snappy" }, shadow: { color: "#99000088" } }, motionScale: 2, tuiMargins: { bar: 30, gutter: 10 } };
// The floating TUIs' window rules as the layer writes them, byte for byte:
// in the Lua literal `\\.` is the regex `\.`, a literal dot. Each size is
// the class's preferred size, at most the output less the fixture's 10 px
// gutter a side and, in height, less its 30 px bar. Hyprland v0.56.2 reads
// these fields back in scripts/smoke/rows/hyprland.sh.
// No window gaps as the layer writes it while its switch is on: zero gaps
// as a workspace rule on the empty selector, which matches every
// workspace, so a user's `general` gaps after the loading line leave it in
// force. Hyprland v0.56.2 reads it back in scripts/smoke/rows/style.sh.
const NO_GAPS_SECTION = [
    "-- Window gaps: none on every workspace.",
    "hl.workspace_rule({ workspace = \"\", gaps_in = 0, gaps_out = 0 })"
];
const NO_GAPS_OFF = "-- Theme appearance: noGaps left to the user's config; core default is off.";
const TUI_SECTION = [
    "-- Floating TUIs: each size class's app-id floats, centred, at its size, clamped to its output.",
    "hl.window_rule({ name = \"vgs:tui\", match = { class = \"^org\\\\.vgs\\\\.tui$\" }, float = true, center = true, size = { \"min(875,monitor_w-20)\", \"min(600,monitor_h-50)\" } })",
    "hl.window_rule({ name = \"vgs:tui-wide\", match = { class = \"^org\\\\.vgs\\\\.tui\\\\.wide$\" }, float = true, center = true, size = { \"min(1200,monitor_w-20)\", \"min(720,monitor_h-50)\" } })",
    "hl.window_rule({ name = \"vgs:tui-tall\", match = { class = \"^org\\\\.vgs\\\\.tui\\\\.tall$\" }, float = true, center = true, size = { \"min(875,monitor_w-20)\", \"min(900,monitor_h-50)\" } })"
];
// The shell's application window rule, byte for byte: no size, so each
// window keeps the size it asks for.
const APP_SECTION = [
    "-- Application windows: the shell's windows float, centred, at the size they ask.",
    "hl.window_rule({ name = \"vgs:window\", match = { class = \"^org\\\\.vgs\\\\.shell$\" }, float = true, center = true })"
];
const TAP_SECTION = [
    "-- Tap shortcuts: a lone key press and release inside Hyprland's repeat delay sends the shortcut.",
    "do",
    "    hl.__vgs_tap = { held = {}, armed = nil, gate = nil }",
    "    hl.on(\"input.keyboard.key\", function(code, ms, state)",
    "        local tap = hl.__vgs_tap",
    "        if state == 1 then",
    "            for held in pairs(tap.held) do if not hl.is_key_down(held) then tap.held[held] = nil end end",
    "            if next(tap.held) == nil then tap.armed, tap.gate = { code = code, ms = ms }, nil else tap.armed = nil end",
    "            tap.held[code] = true",
    "        elseif state == 0 then",
    "            tap.held[code] = nil",
    "            local armed, gate = tap.armed, tap.gate",
    "            tap.armed, tap.gate = nil, nil",
    "            if armed ~= nil and armed.code == code and gate ~= nil and ms - armed.ms < hl.get_config(\"input.repeat_delay\") then",
    "                hl.dispatch(hl.dsp.global(gate))",
    "            end",
    "        end",
    "    end)",
    "end"
];
// The session lock's restore, byte for byte, so a shell started after a
// crash while locked locks again.
const LOCK_SECTION = [
    "-- Session lock: a restarted shell takes over a lock whose client died.",
    "hl.config({ misc = { allow_session_lock_restore = true } })"
];

// The user binds' recorder, byte for byte: it wraps hl.bind once, calls
// Hyprland's own hl.bind from a chunk at the user's file and line so a
// bind's error names them, records the file and line of each
// default-submap bind made outside the layer, and its report reads each
// line's text. scripts/smoke/rows/hyprland-options.sh reads the record and
// a broken bind's error back from the nested Hyprland v0.56.2.
const USER_BINDS_SECTION = [
    "-- User binds: where the user's configuration binds each key, which the shell names beside a key it also binds.",
    "do",
    "    local binds = hl.__vgs_binds or {}",
    "    hl.__vgs_binds = binds",
    "    binds.layer = debug.getinfo(1, \"S\").source",
    "    binds.rows = {}",
    "    binds.sites = {}",
    "    local function json(value)",
    "        return \"\\\"\" .. string.gsub(value, \"[%c\\\"\\\\]\", function(c) return string.format(\"\\\\u%04x\", string.byte(c)) end) .. \"\\\"\"",
    "    end",
    "    if not binds.wrapped then",
    "        binds.wrapped = true",
    "        binds.bind = hl.bind",
    "        local function caller()",
    "            local level = 1",
    "            while true do",
    "                local info = debug.getinfo(level, \"Sl\")",
    "                if info == nil then return nil end",
    "                if info.what ~= \"C\" and not (info.source == binds.layer and info.what ~= \"main\") then",
    "                    if info.source == binds.layer or string.sub(info.source, 1, 1) ~= \"@\" or info.currentline < 1 then return nil end",
    "                    local site = info.source .. \":\" .. info.currentline",
    "                    if binds.sites[site] == nil then",
    "                        binds.sites[site] = assert(load(string.rep(\"\\n\", info.currentline - 1) .. \"local bind = ... return (bind(select(2, ...)))\", info.source, \"t\"))",
    "                    end",
    "                    return binds.sites[site], info",
    "                end",
    "                level = level + 1",
    "            end",
    "        end",
    "        hl.bind = function(...)",
    "            local found, call, info = pcall(caller)",
    "            if not found or call == nil then return binds.bind(...) end",
    "            local bind = call(binds.bind, ...)",
    "            pcall(function()",
    "                if bind == nil or (bind.submap ~= \"\" and bind.submap ~= \"default\") then return end",
    "                binds.rows[#binds.rows + 1] = { file = string.sub(info.source, 2), line = info.currentline, modmask = bind.modmask, key = bind.key, keycode = bind.keycode }",
    "            end)",
    "            return bind",
    "        end",
    "    end",
    "    function binds.report()",
    "        local files, out = {}, {}",
    "        for _, row in ipairs(binds.rows) do",
    "            if files[row.file] == nil then",
    "                local lines = {}",
    "                local handle = io.open(row.file, \"rb\")",
    "                if handle ~= nil then",
    "                    for text in handle:lines() do lines[#lines + 1] = text end",
    "                    handle:close()",
    "                end",
    "                files[row.file] = lines",
    "            end",
    "            out[#out + 1] = \"{\\\"file\\\":\" .. json(row.file) .. \",\\\"line\\\":\" .. row.line .. \",\\\"text\\\":\" .. json(files[row.file][row.line] or \"\") .. \",\\\"modmask\\\":\" .. row.modmask .. \",\\\"key\\\":\" .. json(row.key) .. \",\\\"keycode\\\":\" .. row.keycode .. \"}\"",
    "        end",
    "        return \"vgs-user-binds=[\" .. table.concat(out, \",\") .. \"]\"",
    "    end",
    "end"
];
// The index of the last line of the core's sections in LINES.
const coreEnd = lines => lines.indexOf(LOCK_SECTION[0]) + LOCK_SECTION.length - 1;

// The key capture pass-through, byte for byte: its submap's one bind is
// Escape, so every other key reaches the focused app or shell window.
// Hyprland leaves it on Escape, after the 10 s timer and when the layer runs
// again; captures entered through `enter` also leave on that window's close.
// `enter` refuses unless a shell window has the focus, `enterAnyWindow`
// records no window, and `leave` resets this submap alone.
// scripts/smoke/rows/key-passthrough.sh reads each exit back from the
// nested Hyprland v0.56.2.
const PASSTHROUGH_SECTION = [
    "-- Key capture pass-through: a capture takes every key but Escape.",
    "do",
    "    local passthrough = { submap = \"vgs:passthrough\", class = \"org.vgs.shell\" }",
    "    hl.__vgs_key_passthrough = passthrough",
    "    hl.define_submap(passthrough.submap, function()",
    "        hl.bind(\"Escape\", hl.dsp.submap(\"reset\"), { description = \"vgs:passthrough-cancel\" })",
    "    end)",
    "    function passthrough.leave()",
    "        if hl.get_current_submap() == passthrough.submap then hl.dispatch(hl.dsp.submap(\"reset\")) end",
    "    end",
    "    function passthrough.enter()",
    "        local window = hl.get_active_window()",
    "        if window == nil or window.class ~= passthrough.class then error(\"vgs:passthrough: the focused window is not a vgs window\") end",
    "        passthrough.window = window.address",
    "        hl.dispatch(hl.dsp.submap(passthrough.submap))",
    "    end",
    "    function passthrough.enterAnyWindow()",
    "        passthrough.window = nil",
    "        hl.dispatch(hl.dsp.submap(passthrough.submap))",
    "    end",
    "    passthrough.timer = hl.timer(function()",
    "        passthrough.timer:set_enabled(false)",
    "        passthrough.leave()",
    "    end, { timeout = 10000, type = \"repeat\" })",
    "    passthrough.timer:set_enabled(false)",
    "    hl.on(\"keybinds.submap\", function(name)",
    "        passthrough.timer:set_enabled(name == passthrough.submap)",
    "        if name ~= passthrough.submap then passthrough.window = nil end",
    "    end)",
    "    hl.on(\"window.close\", function(window)",
    "        if window ~= nil and window.address == passthrough.window then passthrough.leave() end",
    "    end)",
    "    passthrough.leave()",
    "end"
];

// The section that applies VALUES once the whole configuration has loaded,
// byte for byte: as the layer loads it reads each of PATHS, and Hyprland's
// `config.reloaded` callback reads them again, sets VALUES and keeps the
// reading between as the user's where the user's configuration changed it
// to something else. scripts/smoke/rows/hyprland-options.sh reads the values
// and the record back from the nested Hyprland v0.56.2.
function appliedSection(paths, values) {
    return [
        "-- Applied once the whole configuration has loaded: each value holds over the user's own line for it.",
        "do",
        "    local options = { start = {}, user = {} }",
        "    hl.__vgs_options = options",
        "    for _, path in ipairs({ " + paths.map(p => "\"" + p + "\"").join(", ") + " }) do options.start[path] = hl.get_config(path) end",
        "    local function json(value)",
        "        if type(value) ~= \"string\" then return tostring(value) end",
        "        return \"\\\"\" .. string.gsub(value, \"[%c\\\"\\\\]\", function(c) return string.format(\"\\\\u%04x\", string.byte(c)) end) .. \"\\\"\"",
        "    end",
        "    function options.report()",
        "        local rows = {}",
        "        for path, value in pairs(options.user) do rows[#rows + 1] = \"{\\\"path\\\":\\\"\" .. path .. \"\\\",\\\"value\\\":\" .. json(value) .. \"}\" end",
        "        table.sort(rows)",
        "        return \"vgs-user-values=[\" .. table.concat(rows, \",\") .. \"]\"",
        "    end",
        "    hl.on(\"config.reloaded\", function()",
        "        local theirs = {}",
        "        for path in pairs(options.start) do theirs[path] = hl.get_config(path) end",
        ...values.map(line => "        " + line),
        "        for path, start in pairs(options.start) do",
        "            if theirs[path] ~= start and theirs[path] ~= hl.get_config(path) then options.user[path] = theirs[path] end",
        "        end",
        "    end)",
        "end"
    ];
}
const APPLIED_AT = 8;
const APPLIED_OPEN = 18;
const APPLIED_CLOSE = 5;

function captureSection(pluginLines) {
    return [
        "-- Overlay keyboard capture: full-screen vgs overlays own keys through a submap.",
        "do",
        "    local capture = hl.__vgs_overlay_capture or { directions = setmetatable({}, { __mode = \"k\" }) }",
        "    hl.__vgs_overlay_capture = capture",
        "    capture.submap = \"vgs:capture\"",
        "    capture.namespace = \"vgs:overlay\"",
        "    capture.globals = { left = \"vgs:overlay-left\", right = \"vgs:overlay-right\", up = \"vgs:overlay-up\", down = \"vgs:overlay-down\", l = \"vgs:overlay-left\", r = \"vgs:overlay-right\", u = \"vgs:overlay-up\", d = \"vgs:overlay-down\" }",
        "    hl.define_submap(capture.submap, function()",
        ...pluginLines,
        "    end)",
        "    local function vgs_overlay_capture_open(closing)",
        "        for _, layer in ipairs(hl.get_layers()) do",
        "            if layer ~= closing and layer.namespace == capture.namespace and layer.mapped then return true end",
        "        end",
        "        return false",
        "    end",
        "    local function vgs_overlay_capture_update(closing)",
        "        if vgs_overlay_capture_open(closing) then",
        "            hl.dispatch(hl.dsp.submap(capture.submap))",
        "        elseif hl.get_current_submap() == capture.submap then",
        "            hl.dispatch(hl.dsp.submap(\"reset\"))",
        "        end",
        "    end",
        "    if not capture.wrapped then",
        "        capture.wrapped = true",
        "        capture.focus = hl.dsp.focus",
        "        capture.bind = hl.bind",
        "        hl.dsp.focus = function(opts)",
        "            local dispatcher = capture.focus(opts)",
        "            pcall(function()",
        "                if type(opts) == \"table\" and type(opts.direction) == \"string\" and capture.globals[opts.direction] ~= nil then",
        "                    capture.directions[dispatcher] = opts.direction",
        "                end",
        "            end)",
        "            return dispatcher",
        "        end",
        "        hl.bind = function(keys, dispatcher, opts)",
        "            local bind = capture.bind(keys, dispatcher, opts)",
        "            pcall(function()",
        "                local direction = capture.directions[dispatcher]",
        "                local in_default = bind ~= nil and (bind.submap == nil or bind.submap == \"\" or bind.submap == \"default\")",
        "                if direction ~= nil and in_default then",
        "                    hl.define_submap(capture.submap, function()",
        "                        capture.bind(keys, hl.dsp.global(capture.globals[direction]), { description = capture.globals[direction] })",
        "                    end)",
        "                end",
        "            end)",
        "            return bind",
        "        end",
        "    end",
        "    if not capture.events then",
        "        capture.events = true",
        "        hl.on(\"layer.opened\", function() vgs_overlay_capture_update() end)",
        "        hl.on(\"layer.closed\", function(layer)",
        "            vgs_overlay_capture_update(layer)",
        "        end)",
        "        hl.on(\"config.reloaded\", vgs_overlay_capture_update)",
        "    end",
        "    vgs_overlay_capture_update()",
        "end"
    ];
}

// The app-id shell.qml's leading pragmas give every toplevel, read as
// Quickshell 0.3.1 reads them (src/launch/launch.cpp): each `//@ pragma`
// line up to the first line that starts with `import`, the last AppId
// winning; null when none sets it, which Quickshell reads as org.quickshell.
function pragmaAppId(text) {
    let appId = null;
    for (const raw of text.split("\n")) {
        const line = raw.trim();
        if (line.startsWith("import")) break;
        if (line.startsWith("//@ pragma AppId ")) appId = line.slice("//@ pragma AppId ".length).trim();
    }
    return appId;
}

// hyprlandKey rows: [text, want key or the start of the error].
const KEYS = [
    ["SUPER+SPACE", { key: "SUPER+SPACE" }],
    ["super + space", { key: "SUPER+SPACE" }],
    ["SHIFT+SUPER+n", { key: "SUPER+SHIFT+N" }],
    ["ALT+CTRL+SHIFT+SUPER+F1", { key: "SUPER+CTRL+ALT+SHIFT+F1" }],
    ["F12", { key: "F12" }],
    ["XF86AudioMute", { key: "XF86AUDIOMUTE" }],
    ["super + CoDe:00108", { key: "SUPER+code:108" }],
    ["SHIFT+SUPER+code:108", { key: "SUPER+SHIFT+code:108" }],
    ["code:0", { key: "code:0" }],
    ["code:4294967295", { key: "code:4294967295" }],
    ["code:4294967296", { error: "names no key" }],
    ["code:", { error: "names no key" }],
    ["code:-108", { error: "names no key" }],
    ["code:1.08", { error: "names no key" }],
    ["code:1e2", { error: "names no key" }],
    ["code:108x", { error: "names no key" }],
    ["code: 108", { error: "names no key" }],
    ["code:108+N", { error: "has the unknown modifier" }],
    ["mouse:108", { error: "names no key" }],
    [7, { error: "must be a string" }],
    ["SUPER+", { error: "has an empty part" }],
    ["SUPER++N", { error: "has an empty part" }],
    ["SUPER", { error: "ends in the modifier SUPER" }],
    ["SUPER+HYPER+N", { error: "has the unknown modifier \"HYPER\"" }],
    ["SUPER+super+N", { error: "repeats the modifier SUPER" }],
    ["SUPER+a-b", { error: "names no key" }],
    ["SUPER+\"", { error: "names no key" }]
];

// validateManifest rows over `service`: [name, patch, want error start or null].
const MANIFESTS = [
    ["binds and a layer rule", { hyprland: { binds: [toggle], layerRules: [overlayRule] } }, null],
    ["a layer rule alone, with no shortcut capability", { capabilities: [], hyprland: { layerRules: [{ namespace: "^vgs:layer$", blur: true }] } }, null],
    ["a rule setting ignoreAlpha alone", { hyprland: { layerRules: [{ namespace: "^vgs:layer$", ignoreAlpha: 0 }] } }, null],
    ["hyprland not an object", { hyprland: [] }, "hyprland must be an object"],
    ["hyprland with an unknown key", { hyprland: { binds: [toggle], windowRules: [] } }, "hyprland has unknown key \"windowRules\""],
    ["binds not a list", { hyprland: { binds: toggle } }, "hyprland.binds must be a list"],
    ["layerRules not a list", { hyprland: { layerRules: overlayRule } }, "hyprland.layerRules must be a list"],
    ["no binds, rules, appearance, options, pads or monitors", { hyprland: { binds: [], layerRules: [] } }, "hyprland declares no binds, layer rules, appearance, options, pads or monitors"],
    ["appearance alone", { capabilities: ["theme"], settings: { setBorders: true }, schema: { setBorders: { type: "boolean", label: "Set borders" } }, hyprland: { appearance: { borders: "setBorders" } } }, null],
    ["appearance unknown group", { capabilities: ["theme"], settings: { setBorders: true }, schema: { setBorders: { type: "boolean", label: "Set borders" } }, hyprland: { appearance: { gaps: "setBorders" } } }, "hyprland.appearance.gaps must be one of borders, radius, motion, noGaps"],
    ["appearance noGaps", { capabilities: ["theme"], settings: { noGaps: false }, schema: { noGaps: { type: "boolean", label: "No gaps" } }, hyprland: { appearance: { noGaps: "noGaps" } } }, null],
    ["appearance missing schema key", { capabilities: ["theme"], settings: { setBorders: true }, schema: { setBorders: { type: "boolean", label: "Set borders" } }, hyprland: { appearance: { borders: "missing" } } }, "hyprland.appearance.borders names no schema entry \"missing\""],
    ["appearance non-boolean schema key", { capabilities: ["theme"], settings: { setBorders: "yes" }, schema: { setBorders: { type: "string", label: "Set borders", presets: [{ value: "yes" }] } }, hyprland: { appearance: { borders: "setBorders" } } }, "hyprland.appearance.borders must name a boolean schema entry"],
    ["appearance without theme capability", { settings: { setBorders: true }, schema: { setBorders: { type: "boolean", label: "Set borders" } }, hyprland: { appearance: { borders: "setBorders" } } }, "hyprland.appearance needs capability theme"],
    ["appearance empty", { capabilities: ["theme"], hyprland: { appearance: {} } }, "hyprland.appearance must be a non-empty object"],
    ["binds without capability shortcut", { capabilities: [], hyprland: { binds: [toggle] } }, "hyprland.binds needs capability shortcut"],
    ["a bind that is no object", { hyprland: { binds: ["toggle"] } }, "hyprland.binds.0 must be an object"],
    ["a bind with an unknown key", { hyprland: { binds: [{ shortcut: "toggle", key: "SUPER+N", lua: "x" }] } }, "hyprland.binds.0 has unknown key \"lua\""],
    ["a bind naming no shortcut", { hyprland: { binds: [{ key: "SUPER+N" }] } }, "hyprland.binds.0.shortcut must be a shortcut name"],
    ["a malformed shortcut name", { hyprland: { binds: [{ shortcut: "Toggle", key: "SUPER+N" }] } }, "hyprland.binds.0.shortcut must be a shortcut name"],
    ["a shortcut bound twice", { hyprland: { binds: [toggle, { shortcut: "toggle", key: "SUPER+N" }] } }, "hyprland.binds.1.shortcut toggle is bound twice"],
    ["a key the grammar refuses", { hyprland: { binds: [{ shortcut: "toggle", key: "SUPER+" }] } }, "hyprland.binds.0.key has an empty part"],
    ["a modifier after the key", { hyprland: { binds: [toggle, { shortcut: "open", key: "space+super" }] } }, "hyprland.binds.1.key ends in the modifier SUPER"],
    ["one key bound twice", { hyprland: { binds: [toggle, { shortcut: "open", key: "super + space" }] } }, "hyprland.binds.1.key SUPER+SPACE is bound twice"],
    ["a keycode bind", { hyprland: { binds: [{ shortcut: "talk", key: "SUPER+code:108" }] } }, null],
    ["a null default key", { hyprland: { binds: [{ shortcut: "talk", key: null }] } }, null],
    ["a hold bind", { hyprland: { binds: [{ shortcut: "talk", key: "SUPER+code:108", hold: true }] } }, null],
    ["a non-hold bind", { hyprland: { binds: [{ shortcut: "talk", key: "SUPER+code:108", hold: false }] } }, null],
    ["hold is not a boolean", { hyprland: { binds: [{ shortcut: "talk", key: "SUPER+code:108", hold: "yes" }] } }, "hyprland.binds.0.hold must be a boolean"],
    ["a tap bind", { hyprland: { binds: [{ shortcut: "tap", key: "code:108", tap: true }] } }, null],
    ["a non-tap bind", { hyprland: { binds: [{ shortcut: "tap", key: "code:108", tap: false }] } }, null],
    ["tap is not a boolean", { hyprland: { binds: [{ shortcut: "tap", key: "code:108", tap: "yes" }] } }, "hyprland.binds.0.tap must be a boolean"],
    ["tap and hold conflict", { hyprland: { binds: [{ shortcut: "tap", key: "code:108", tap: true, hold: true }] } }, "hyprland.binds.0 must not set tap and hold together"],
    ["tap needs a lone key", { hyprland: { binds: [{ shortcut: "tap", key: "SUPER+code:108", tap: true }] } }, "hyprland.binds.0.key SUPER+code:108 must be a lone key for tap"],
    ["one keycode bound twice", { hyprland: { binds: [{ shortcut: "talk", key: "SUPER+code:108" }, { shortcut: "mute", key: "super+CODE:00108" }] } }, "hyprland.binds.1.key SUPER+code:108 is bound twice"],
    ["a rule that is no object", { hyprland: { layerRules: ["^vgs:overlay$"] } }, "hyprland.layerRules.0 must be an object"],
    ["a rule with an unknown key", { hyprland: { layerRules: [{ namespace: "^vgs:overlay$", blur: true, xray: true }] } }, "hyprland.layerRules.0 has unknown key \"xray\""],
    ["an unanchored namespace", { hyprland: { layerRules: [{ namespace: "vgs:overlay", blur: true }] } }, "hyprland.layerRules.0.namespace must be ^vgs:<name>$"],
    ["another application's namespace", { hyprland: { layerRules: [{ namespace: "^waybar$", blur: true }] } }, "hyprland.layerRules.0.namespace must be ^vgs:<name>$"],
    ["a namespace pattern wider than one name", { hyprland: { layerRules: [{ namespace: "^vgs:.*$", blur: true }] } }, "hyprland.layerRules.0.namespace must be ^vgs:<name>$"],
    ["a namespace with a rule already", { hyprland: { layerRules: [overlayRule, { namespace: "^vgs:overlay$", blur: false }] } }, "hyprland.layerRules.1.namespace ^vgs:overlay$ has a rule already"],
    ["a rule with no effect", { hyprland: { layerRules: [{ namespace: "^vgs:overlay$" }] } }, "hyprland.layerRules.0 sets neither blur nor ignoreAlpha"],
    ["blur not a boolean", { hyprland: { layerRules: [{ namespace: "^vgs:overlay$", blur: "yes" }] } }, "hyprland.layerRules.0.blur must be a boolean"],
    ["ignoreAlpha above 1", { hyprland: { layerRules: [{ namespace: "^vgs:overlay$", ignoreAlpha: 1.5 }] } }, "hyprland.layerRules.0.ignoreAlpha must be a number from 0 to 1"],
    ["ignoreAlpha below 0", { hyprland: { layerRules: [{ namespace: "^vgs:overlay$", ignoreAlpha: -0.1 }] } }, "hyprland.layerRules.0.ignoreAlpha must be a number from 0 to 1"],
    ["ignoreAlpha a string", { hyprland: { layerRules: [{ namespace: "^vgs:overlay$", ignoreAlpha: "0.6" }] } }, "hyprland.layerRules.0.ignoreAlpha must be a number from 0 to 1"],
    ["a default setting named keys", { settings: { keys: {} } }, "settings must not carry a keys key"]
];

// configError rows over a plugins row's `keys`: [name, keys, want error start or ""].
const CONFIG_KEYS = [
    ["a key and an unbinding null", { toggle: "super+space", inbox: null }, ""],
    ["a name no bind declares", { later: "SUPER+L" }, ""],
    ["a rebound keycode", { toggle: "super+CODE:00108" }, ""],
    ["a malformed rebound keycode", { toggle: "SUPER+code:108x" }, "plugins.0.keys.toggle names no key"],
    ["keys not an object", ["SUPER+SPACE"], "plugins.0.keys must be an object"],
    ["a malformed name", { Toggle: "SUPER+SPACE" }, "plugins.0.keys.Toggle is not a shortcut name"],
    ["a key the grammar refuses", { toggle: "SUPER+" }, "plugins.0.keys.toggle has an empty part"],
    ["a key that is a number", { toggle: 32 }, "plugins.0.keys.toggle must be a string"],
    ["an empty key list", { toggle: [] }, "plugins.0.keys.toggle must not be an empty list"],
    ["a key list entry the grammar refuses", { toggle: ["SUPER+K", "SUPER+"] }, "plugins.0.keys.toggle.1 has an empty part"]
];

function manifestOf(logic, patch) {
    const r = logic.validateManifest(Object.assign(JSON.parse(JSON.stringify(service)), patch), "/p");
    assert.ok(r.ok, "fixture manifest refused: " + r.error);
    return r.manifest;
}

// The pads' sweep, byte for byte, which ends every layer: a window in a
// pad's workspace whose pad the table does not hold, as after the pad's
// removal or its plugin's disabling, comes to the focused workspace.
// scripts/smoke/rows/scratchpads.sh reads both cases back.
const SWEEP_SECTION = [
    "-- Pads: a window in a pad's workspace that no pad holds comes to the focused workspace.",
    "do",
    "    local pads = hl.__vgs_pads ~= nil and hl.__vgs_pads.list or {}",
    "    local active = hl.get_active_workspace()",
    "    for _, window in ipairs(hl.get_windows()) do",
    "        local name = window.workspace ~= nil and string.match(window.workspace.name, \"^special:vgs%-pad%-(.+)$\") or nil",
    "        if name ~= nil and pads[name] == nil and active ~= nil then",
    "            hl.dispatch(hl.dsp.window.move({ workspace = tostring(active.id), window = \"address:\" .. window.address, follow = false }))",
    "        end",
    "    end",
    "end"
];
// The pads of a plugin's `hyprland.pads`, byte for byte, for the pads
// fixture below under the test theme: a table of each pad's judged values,
// one window rule per pad that maps its class's windows hidden, tiled and
// unfocused into its special workspace, and the functions the toggle
// request calls (Dispatch.padRequest), on the curve and speed of the
// theme's preset's workspace leaf. scripts/smoke/rows/scratchpads.sh reads
// each behaviour back from the nested Hyprland v0.56.2.
const PADS_SECTION = [
    "-- acme.pads 1.0.0: pads from its manifest",
    "do",
    "    local pads = { list = {}, before = {}, prefix = \"special:vgs-pad-\", motion = { speed = 3.2, bezier = \"vgsPad\" } }",
    "    hl.__vgs_pads = pads",
    "    hl.curve(\"vgsPad\", { type = \"bezier\", points = { { 0.15, 0 }, { 0.1, 1 } } })",
    "    pads.list[\"1\"] = { x = \"center\", y = \"start\", width = 60, height = 50, margin = 2, entry = \"top\", motion = \"slide\" }",
    "    hl.window_rule({ name = \"acme.pads:pad-1\", match = { class = \"^org\\\\.acme\\\\.pad$\" }, workspace = \"special:vgs-pad-1 silent\", tile = true, no_initial_focus = true, suppress_event = \"activate activatefocus\" })",
    "    pads.list[\"term\"] = { x = \"end\", y = \"end\", width = 40.5, height = 50, margin = 2, entry = \"left\", motion = \"none\" }",
    "    hl.window_rule({ name = \"acme.pads:pad-term\", match = { class = \"^foot\\\\.term$\" }, workspace = \"special:vgs-pad-term silent\", tile = true, no_initial_focus = true, suppress_event = \"activate activatefocus\" })",
    "    local opposite = { top = \"bottom\", bottom = \"top\", left = \"right\", right = \"left\" }",
    "    local function offset(anchor, free, margin)",
    "        if anchor == \"start\" then return math.min(margin, free) end",
    "        if anchor == \"end\" then return math.max(free - margin, 0) end",
    "        return math.floor(free / 2)",
    "    end",
    "    local function fit(name, mon)",
    "        local pad = pads.list[name]",
    "        if mon.scale == nil or mon.scale <= 0 then return end",
    "        local width, height = mon.width, mon.height",
    "        if mon.transform % 2 == 1 then width, height = height, width end",
    "        local reserved = mon.reserved",
    "        width = math.floor(width / mon.scale - reserved.left - reserved.right)",
    "        height = math.floor(height / mon.scale - reserved.top - reserved.bottom)",
    "        local w, h = math.floor(width * pad.width / 100), math.floor(height * pad.height / 100)",
    "        local margin = math.floor(math.min(width, height) * pad.margin / 100)",
    "        local left, top = offset(pad.x, width - w, margin), offset(pad.y, height - h, margin)",
    "        hl.workspace_rule({ workspace = pads.prefix .. name, gaps_in = 0, gaps_out = { top = top, right = width - w - left, bottom = height - h - top, left = left } })",
    "        hl.exec_scheduled_prop_refresh_immediately()",
    "    end",
    "    local function animate(name)",
    "        local pad = pads.list[name]",
    "        if pads.motion == nil or pad.motion == \"none\" then",
    "            hl.animation({ leaf = \"specialWorkspaceIn\", enabled = false })",
    "            hl.animation({ leaf = \"specialWorkspaceOut\", enabled = false })",
    "            return",
    "        end",
    "        local into, out = \"fade\", \"fade\"",
    "        if pad.motion == \"slide\" then into, out = \"slide \" .. pad.entry, \"slide \" .. opposite[pad.entry] end",
    "        hl.animation({ leaf = \"specialWorkspaceIn\", enabled = true, speed = pads.motion.speed, bezier = pads.motion.bezier, style = into })",
    "        hl.animation({ leaf = \"specialWorkspaceOut\", enabled = true, speed = pads.motion.speed, bezier = pads.motion.bezier, style = out })",
    "    end",
    "    local function hide(name, mon, refocus)",
    "        animate(name)",
    "        mon:set_special_workspace({})",
    "        local before = pads.before[name] ~= nil and hl.get_window(\"address:\" .. pads.before[name]) or nil",
    "        pads.before[name] = nil",
    "        if refocus and before ~= nil and before.workspace ~= nil and before.workspace.visible then hl.dispatch(hl.dsp.focus({ window = \"address:\" .. before.address })) end",
    "    end",
    "    local function shown(name)",
    "        local ws = hl.get_workspace(pads.prefix .. name)",
    "        if ws ~= nil and ws.visible and ws.monitor ~= nil then return ws end",
    "        return nil",
    "    end",
    "    function pads.toggle(name, screen)",
    "        return function()",
    "            if pads.list[name] == nil then error(\"vgs-pad=no-pad name=\" .. name) end",
    "            local id = pads.prefix .. name",
    "            local visible = shown(name)",
    "            if visible ~= nil then return hide(name, visible.monitor, true) end",
    "            local ws = hl.get_workspace(id)",
    "            if ws == nil or ws.windows == 0 then error(\"vgs-pad=no-window name=\" .. name) end",
    "            local mon = screen == \"\" and hl.get_active_monitor() or hl.get_monitor(screen)",
    "            if mon == nil then error(\"vgs-pad=no-screen screen=\" .. screen) end",
    "            if ws.monitor == nil or ws.monitor.name ~= mon.name then hl.dispatch(hl.dsp.workspace.move({ workspace = id, monitor = mon.name })) end",
    "            fit(name, mon)",
    "            animate(name)",
    "            local active = hl.get_active_window()",
    "            pads.before[name] = active ~= nil and active.workspace ~= nil and active.workspace.name ~= id and active.address or nil",
    "            mon:set_special_workspace({ workspace = id })",
    "            local windows = hl.get_workspace_windows(id)",
    "            if windows[1] ~= nil then hl.dispatch(hl.dsp.focus({ window = \"address:\" .. windows[1].address })) end",
    "        end",
    "    end",
    "    hl.on(\"window.active\", function(window)",
    "        if window == nil then return end",
    "        local current = window.workspace ~= nil and window.workspace.name or \"\"",
    "        for name in pairs(pads.list) do",
    "            local visible = shown(name)",
    "            if visible ~= nil and current ~= pads.prefix .. name then hide(name, visible.monitor, false) end",
    "        end",
    "    end)",
    "    local function refit()",
    "        for name in pairs(pads.list) do",
    "            local visible = shown(name)",
    "            if visible ~= nil then fit(name, visible.monitor) end",
    "        end",
    "    end",
    "    hl.on(\"monitor.layout_changed\", refit)",
    "    refit()",
    "end"
];
// The pads fixture: a list setting of two pads, the first with its key.
function padsFixture(logic, id, pads) {
    const items = { "class": { type: "string", label: "Class", presets: [{ value: "org.acme.pad" }], allowCustom: true }, width: { type: "number", label: "Width", min: 10, max: 100 }, height: { type: "number", label: "Height", min: 10, max: 100 },
        position: { type: "enum", label: "Position", options: ["center", "top", "bottom-right"] }, margin: { type: "number", label: "Margin", min: 0, max: 20 }, entry: { type: "enum", label: "Entry", options: ["top", "left"] }, motion: { type: "enum", label: "Motion", options: ["slide", "none"] } };
    const defaults = { "class": "org.acme.pad", width: 60, height: 50, position: "top", margin: 2, entry: "top", motion: "slide" };
    const judged = logic.validateManifest({ schemaVersion: 1, id: id, name: "P", version: "1.0.0", author: "a", description: "d", kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["shortcut"], settings: { pads: [] }, schema: { pads: { type: "list", label: "Pads", items: items, defaults: defaults } }, hyprland: { pads: "pads" } }, "/p");
    assert.ok(judged.ok, "the pads fixture manifest passes: " + judged.error);
    const value = pads !== undefined ? pads : [Object.assign({ name: "1" }, defaults), Object.assign({ name: "term" }, defaults, { "class": "foot.term", position: "bottom-right", width: 40.5, motion: "none", entry: "left" })];
    return logic.hyprlandSection({ plugins: [{ id: id, pads: value, keys: { "pad-1": "SUPER+ALT+P" } }] }, judged.manifest);
}

function verify(logic, layer, shellText) {
    const lines = out => out.text.split("\n");
    for (const [text, want] of KEYS) {
        const got = logic.hyprlandKey(text);
        if (want.key !== undefined) same(got, { ok: true, key: want.key }, "hyprlandKey " + JSON.stringify(text));
        else assert.ok(!got.ok && got.error.startsWith(want.error), "hyprlandKey " + JSON.stringify(text) + " refused with " + JSON.stringify(want.error) + ", got " + JSON.stringify(got));
    }
    for (const [name, patch, want] of MANIFESTS) {
        const r = logic.validateManifest(Object.assign(JSON.parse(JSON.stringify(service)), patch), "/p");
        if (want === null) assert.ok(r.ok, "manifest " + name + " accepted, got " + r.error);
        else assert.ok(!r.ok && r.error.startsWith(want), "manifest " + name + " refused with " + JSON.stringify(want) + ", got " + JSON.stringify(r.ok ? "accepted" : r.error));
    }
    const declared = manifestOf(logic, { hyprland: { binds: [{ shortcut: "toggle", key: "super + space" }, { shortcut: "inbox", key: "SUPER+N" }], layerRules: [overlayRule] } });
    const keycode = manifestOf(logic, { hyprland: { binds: [{ shortcut: "talk", key: "super+CODE:00108" }] } });
    same(keycode.hyprland.binds, [{ shortcut: "talk", key: "SUPER+code:108" }], "manifest keycode normalized");
    const other = Object.assign({}, keycode, { id: "acme.other" });
    for (const [label, config, want] of [
        ["default", {}, { talk: "SUPER+code:108" }],
        ["rebound", { plugins: [{ id: "acme.keys", keys: { talk: "shift+super+CODE:00108", ghost: "SUPER+F1" } }] }, { talk: "SUPER+SHIFT+code:108" }],
        ["unbound", { plugins: [{ id: "acme.keys", keys: { talk: null } }] }, { talk: null }]
    ]) {
        const sections = [logic.hyprlandSection(config, keycode)];
        same(layer.shortcutKeys(sections, keycode.id), want, "shortcut keys " + label);
        const read = layer.shortcutKeys(sections, keycode.id);
        read.talk = "planted";
        read.ghost = "planted";
        same(layer.shortcutKeys(sections, keycode.id), want, "shortcut keys mutation " + label);
        assert.strictEqual(layer.shortcutKeys(sections, keycode.id).missing, undefined, "undeclared shortcut absent");
        assert.strictEqual(layer.shortcutKeys(sections, keycode.id).constructor, undefined, "inherited names are no shortcuts");
        same(layer.shortcutKeys(sections, other.id), {}, "other plugin cannot read keys");
    }
    const colliding = [logic.hyprlandSection({}, other), logic.hyprlandSection({}, keycode)];
    same(layer.shortcutKeys(colliding, other.id), { talk: null }, "conflicting key is not an effective bind");
    same(layer.shortcutKeys(colliding, keycode.id), { talk: "SUPER+code:108" }, "first id owns the keycode");
    same(layer.shortcutKeys([], keycode.id), {}, "no enabled section has no keys");
    const unbound = colliding.map(section => Object.assign({}, section, { binds: [{ shortcut: "talk", key: null }] }));
    same(layer.resolveBinds(unbound).conflicts, [], "unbound shortcuts claim no key");
    same(layer.shortcutKeys([logic.hyprlandSection({}, manifestOf(logic, {}))], keycode.id), {}, "manifest without binds has no keys");
    const keycodeText = layer.render(colliding, theme, "probe").text;
    assert.ok(keycodeText.includes('hl.bind("SUPER + code:108", hl.dsp.global("acme.keys:talk"), { description = "acme.keys:talk" })'), "renderer preserves lower-case code prefix");
    assert.ok(keycodeText.includes("-- skipped SUPER+code:108: already bound by acme.keys"), "renderer shares the keycode conflict judge");
    const holdManifest = manifestOf(logic, { hyprland: { binds: [{ shortcut: "talk", key: "super+CODE:00108", hold: true }] } });
    same(holdManifest.hyprland.binds, [{ shortcut: "talk", key: "SUPER+code:108", hold: true }], "manifest retains hold");
    const tapManifest = manifestOf(logic, { hyprland: { binds: [{ shortcut: "tap", key: "CODE:00108", tap: true }] } });
    same(tapManifest.hyprland.binds, [{ shortcut: "tap", key: "code:108", tap: true }], "manifest retains tap");
    const nullManifest = manifestOf(logic, { hyprland: { binds: [{ shortcut: "tap", key: null, tap: true }] } });
    same(nullManifest.hyprland.binds, [{ shortcut: "tap", key: null, tap: true }], "manifest retains a null default key");
    assert.equal(layer.releaseShortcutName("talk"), "talk.release", "companion cannot be a public registration name");
    const tapList = logic.hyprlandSection({ plugins: [{ id: "acme.keys", keys: { tap: ["code:108", "code:105"] } }] }, tapManifest);
    same(tapList.binds, [{ shortcut: "tap", key: "code:108", tap: true }, { shortcut: "tap", key: "code:105", tap: true }], "tap list expands to one bind per key");
    same(layer.shortcutKeys([tapList], "acme.keys"), { tap: "code:108" }, "shortcut keys read the first tap key");
    const tapListLines = lines(layer.render([tapList], theme, "tap-list"));
    assert.equal(tapListLines.filter(line => line === 'hl.bind("code:108", function() hl.__vgs_tap.gate = "acme.keys:tap" end, { description = "acme.keys:tap", non_consuming = true, transparent = true, ignore_mods = true })').length, 1, "tap list writes the first gate");
    assert.equal(tapListLines.filter(line => line === 'hl.bind("code:105", function() hl.__vgs_tap.gate = "acme.keys:tap" end, { description = "acme.keys:tap", non_consuming = true, transparent = true, ignore_mods = true })').length, 1, "tap list writes the second gate");
    assert.equal(tapListLines.filter(line => line === "    hl.__vgs_tap = { held = {}, armed = nil, gate = nil }").length, 1, "tap list writes one tracker");
    for (const [label, keys, key] of [
        ["default", {}, "SUPER+code:108"],
        ["rebound", { talk: "SUPER+SHIFT+code:108" }, "SUPER+SHIFT+code:108"],
        ["unbound", { talk: null }, null]
    ]) {
        const section = logic.hyprlandSection({ plugins: [{ id: "acme.keys", keys }] }, holdManifest);
        same(section.binds, [{ shortcut: "talk", key, hold: true }], "effective hold " + label);
        const text = layer.render([section], theme, "hold").text;
        const releaseLine = 'hl.bind("' + (key || "").split("+").join(" + ") + '", hl.dsp.global("acme.keys:talk.release"), { description = "acme.keys:talk.release", release = true, non_consuming = true, transparent = true, ignore_mods = true })';
        if (key === null) assert.ok(!text.includes("talk.release"), "unbound hold writes neither companion");
        else {
            assert.ok(text.split("\n").includes(releaseLine), "default map release flags " + label);
            assert.ok(text.split("\n").includes("    " + releaseLine), "overlay map release flags " + label);
        }
    }
    const holdList = logic.hyprlandSection({ plugins: [{ id: "acme.keys", keys: { talk: ["SUPER+code:108", "CTRL+code:105"] } }] }, holdManifest);
    same(holdList.binds, [{ shortcut: "talk", key: "SUPER+code:108", hold: true }, { shortcut: "talk", key: "CTRL+code:105", hold: true }], "hold list expands to one bind per key");
    same(layer.shortcutKeys([holdList], "acme.keys"), { talk: "SUPER+code:108" }, "shortcut keys read the first hold key");
    const holdListLines = lines(layer.render([holdList], theme, "hold-list"));
    const holdPress108 = 'hl.bind("SUPER + code:108", hl.dsp.global("acme.keys:talk"), { description = "acme.keys:talk" })';
    const holdPress105 = 'hl.bind("CTRL + code:105", hl.dsp.global("acme.keys:talk"), { description = "acme.keys:talk" })';
    const holdRelease108 = 'hl.bind("SUPER + code:108", hl.dsp.global("acme.keys:talk.release"), { description = "acme.keys:talk.release", release = true, non_consuming = true, transparent = true, ignore_mods = true })';
    const holdRelease105 = 'hl.bind("CTRL + code:105", hl.dsp.global("acme.keys:talk.release"), { description = "acme.keys:talk.release", release = true, non_consuming = true, transparent = true, ignore_mods = true })';
    assert.equal(holdListLines.filter(line => line === holdPress108).length, 1, "hold list writes the first press");
    assert.equal(holdListLines.filter(line => line === holdPress105).length, 1, "hold list writes the second press");
    assert.equal(holdListLines.filter(line => line === holdRelease108).length, 1, "hold list writes the first release");
    assert.equal(holdListLines.filter(line => line === holdRelease105).length, 1, "hold list writes the second release");
    const losingHold = Object.assign({}, logic.hyprlandSection({}, holdManifest), { id: "acme.other" });
    assert.ok(!layer.render([logic.hyprlandSection({}, holdManifest), losingHold], theme, "hold").text.includes("acme.other:talk.release"), "conflict skips both hold binds");
    assert.ok(!keycodeText.includes("talk.release"), "ordinary bind has no release companion");
    const tapSection = logic.hyprlandSection({}, tapManifest);
    const tapText = layer.render([tapSection], theme, "tap").text.split("\n");
    const tapBind = 'hl.bind("code:108", function() hl.__vgs_tap.gate = "acme.keys:tap" end, { description = "acme.keys:tap", non_consuming = true, transparent = true, ignore_mods = true })';
    assert.ok(tapText.indexOf(TAP_SECTION[0]) > tapText.indexOf(APP_SECTION[0]), "the tap tracker follows application windows");
    same(tapText.slice(tapText.indexOf(TAP_SECTION[0]), tapText.indexOf(TAP_SECTION[0]) + TAP_SECTION.length), TAP_SECTION, "the tap tracker is written byte for byte");
    assert.ok(tapText.indexOf(TAP_SECTION[0]) < tapText.indexOf("    " + tapBind), "the tap tracker precedes overlay tap binds");
    assert.ok(tapText.indexOf(TAP_SECTION[0]) < tapText.indexOf(tapBind), "the tap tracker precedes default tap binds");
    assert.equal(tapText.filter(line => line === TAP_SECTION[0]).length, 1, "the tap tracker is written once");
    assert.ok(tapText.includes(tapBind), "default map tap bind records the gate");
    assert.ok(tapText.includes("    " + tapBind), "overlay map tap bind records the gate");
    assert.ok(!tapText.some(line => line.includes('hl.dsp.global("acme.keys:tap")')), "tap binds do not dispatch on press");
    assert.ok(!layer.render([logic.hyprlandSection({}, nullManifest)], theme, "tap").text.split("\n").includes(TAP_SECTION[0]), "an unbound tap writes no tracker");
    const tapOverride = logic.hyprlandSection({ plugins: [{ id: "acme.keys", keys: { tap: "SUPER+code:108" } }] }, tapManifest);
    const tapOverrideText = layer.render([tapOverride], theme, "tap").text.split("\n");
    assert.ok(tapOverrideText.includes("-- skipped SUPER+code:108: tap key must be a lone key with no modifiers"), "a tap override with modifiers is a visible comment");
    assert.ok(!tapOverrideText.some(line => line.includes('function() hl.__vgs_tap.gate = "acme.keys:tap"')), "a tap override with modifiers writes no bind");
    same(layer.shortcutKeys([tapOverride], "acme.keys"), { tap: null }, "a refused tap override is not an effective key");
    same(declared.hyprland, { binds: [{ shortcut: "toggle", key: "SUPER+SPACE" }, { shortcut: "inbox", key: "SUPER+N" }], layerRules: [overlayRule], appearance: {}, options: {} }, "a normalised manifest holds normalised keys");
    same(manifestOf(logic, { hyprland: { layerRules: [overlayRule] } }).hyprland.binds, [], "a normalised manifest without binds holds none");
    assert.strictEqual(manifestOf(logic, {}).hyprland, undefined, "a manifest declaring no hyprland key carries none");

    for (const [name, keys, want] of CONFIG_KEYS) {
        const got = logic.configError({ plugins: [{ id: "acme.keys", keys: keys }] });
        assert.ok(want === "" ? got === "" : got.startsWith(want), "configError " + name + ": want " + JSON.stringify(want) + ", got " + JSON.stringify(got));
    }
    const config = { plugins: [{ id: "acme.keys", keys: { toggle: "ctrl+super+t", inbox: null, later: "SUPER+L", early: null }, size: 3 }] };
    same(logic.settingsFor(config, declared, "plugins", null), { size: 3 }, "a plugins row's keys are no setting");
    same(logic.hyprlandSection(config, declared), {
        id: "acme.keys", version: "1.0.0",
        binds: [{ shortcut: "toggle", key: "SUPER+CTRL+T" }, { shortcut: "inbox", key: null }],
        layerRules: [overlayRule],
        appearance: {},
        options: [],
        monitors: null,
        pads: null,
        padRefusals: [],
        unknownKeys: ["early", "later"]
    }, "hyprlandSection takes the row's keys over the manifest's and names the unknown ones");
    same(logic.hyprlandSection({}, declared).binds, declared.hyprland.binds, "hyprlandSection keeps the manifest's keys without a row");
    same(logic.hyprlandSection(config, manifestOf(logic, {})), { id: "acme.keys", version: "1.0.0", binds: [], layerRules: [], appearance: {}, options: [], monitors: null, pads: null, padRefusals: [], unknownKeys: ["early", "inbox", "later", "toggle"] }, "a manifest asking nothing leaves every row name unknown");
    const appearanceManifest = manifestOf(logic, { capabilities: ["theme"], settings: { setBorders: true, setMotion: false }, schema: { setBorders: { type: "boolean", label: "Set borders" }, setMotion: { type: "boolean", label: "Set motion" } }, hyprland: { appearance: { borders: "setBorders", motion: "setMotion" } } });
    const gapsManifest = manifestOf(logic, { capabilities: ["theme"], settings: { noGaps: false }, schema: { noGaps: { type: "boolean", label: "No gaps" } }, hyprland: { appearance: { noGaps: "noGaps" } } });
    same(logic.hyprlandSection({ plugins: [{ id: "acme.keys", noGaps: true }] }, gapsManifest).appearance, { noGaps: { setting: "noGaps", enabled: true } }, "hyprlandSection resolves the gaps switch from the plugins row");
    same(logic.hyprlandSection({}, gapsManifest).appearance, { noGaps: { setting: "noGaps", enabled: false } }, "the gaps switch defaults to the manifest's off");
    same(logic.hyprlandSection({ plugins: [{ id: "acme.keys", setBorders: false, setMotion: true }] }, appearanceManifest).appearance, {
        borders: { setting: "setBorders", enabled: false },
        motion: { setting: "setMotion", enabled: true }
    }, "hyprlandSection resolves appearance switches from effective plugin settings");

    const section = (id, binds, layerRules, version, appearance) => ({ id: id, version: version || "1.0.0", binds: binds, layerRules: layerRules, appearance: appearance || {}, options: [], monitors: null, unknownKeys: [] });
    const lines = out => out.text.split("\n");
    // The values a layer applies once the configuration has loaded: the
    // lines inside its callback, without their indent. The section starts
    // after the header and its end is the first line that closes a block
    // at no indent.
    const applied = out => {
        const all = lines(out);
        const end = all.indexOf("end", APPLIED_AT);
        const frame = appliedSection([], []);
        same(all.slice(APPLIED_AT, APPLIED_AT + APPLIED_OPEN).filter((line, i) => i !== 4), frame.slice(0, APPLIED_OPEN).filter((line, i) => i !== 4), "the applied section opens after the header");
        same(all.slice(end + 1 - APPLIED_CLOSE, end + 2), [...frame.slice(frame.length - APPLIED_CLOSE), ""], "the applied section closes before the next section");
        return all.slice(APPLIED_AT + APPLIED_OPEN, end + 1 - APPLIED_CLOSE).map(line => {
            assert.ok(line.startsWith("        "), "an applied line sits inside the callback: " + line);
            return line.slice(8);
        });
    };
    const placed = out => lines(out).slice(lines(out).indexOf("end", APPLIED_AT) + 1);
    same(layer.USER_VALUES, { table: "__vgs_options", verb: "report", key: "vgs-user-values" }, "the applied section names its Lua table, its report and the key of its answer");
    const bare = layer.render([], theme, "vgs", 2);
    const bareLines = lines(bare);
    assert.ok(bareLines.includes('hl.on("hyprland.start", function () hl.exec_cmd("vgshell start") end)'), "the layer starts VGS by its command name when Hyprland starts");
    const allOff = { borders: { setting: "b", enabled: false }, radius: { setting: "r", enabled: false }, motion: { setting: "m", enabled: false } };
    const quiet = lines(layer.render([section("vgs.themes", [], [], "1.0.0", allOff)], theme, "vgs", 1));
    same(quiet.slice(APPLIED_AT, quiet.indexOf(TUI_SECTION[0])), [
        ...appliedSection([], []),
        "",
        "-- Theme appearance: borders left to the user's config; b is off.",
        "",
        "-- Theme appearance: radius left to the user's config; r is off.",
        "",
        "-- Theme appearance: motion left to the user's config; m is off.",
        "",
        NO_GAPS_OFF,
        ""
    ], "with every group off the applied section sets nothing, byte for byte, and each group is a comment after it");
    same(applied(bare).filter(line => line.startsWith("-- ")), ["-- Theme vgs: window, group and group bar borders.", "-- Theme appearance: corner radius.", "-- Group tabs use the window radius times the highest monitor scale (2), bounded to 20."], "the groups that are on are applied in order");
    same(placed(bare).filter(line => /hl\.config\(\{$|border_size|rounding|hl\.animation|hl\.curve|animations = /.test(line)), [], "a group that is on writes none of its values where a user's line would replace them");
    assert.ok(applied(bare).indexOf("-- Theme vgs: window, group and group bar borders.") < applied(bare).indexOf("-- Theme appearance: corner radius."), "borders are before radius");
    assert.ok(lines(bare).indexOf("end", APPLIED_AT) < lines(bare).indexOf("-- Theme appearance: motion left to the user's config; core default is off."), "the applied groups are before the motion comment");
    assert.ok(bareLines.indexOf("-- Theme appearance: motion left to the user's config; core default is off.") < bareLines.indexOf(NO_GAPS_OFF), "motion is before the gaps switch");
    assert.ok(bareLines.indexOf(NO_GAPS_OFF) !== -1 && bareLines.indexOf(NO_GAPS_OFF) < bareLines.indexOf(TUI_SECTION[0]), "theme appearance, gaps last, is before floating TUIs");
    assert.ok(!bareLines.some(line => line.indexOf("hl.workspace_rule(") !== -1), "with no owner the layer writes no gap rule");
    // No window gaps: on, the two lines after motion and before the
    // floating TUIs; off, one comment and no rule, whatever the theme.
    const gapsSection = on => section("vgs.themes", [], [], "1.0.0", { noGaps: { setting: "noWindowGaps", enabled: on } });
    const gapsOn = lines(layer.render([gapsSection(true)], theme, "vgs", 1));
    const gapsAt = gapsOn.indexOf(NO_GAPS_SECTION[0]);
    same(gapsOn.slice(gapsAt, gapsAt + NO_GAPS_SECTION.length + 2), [...NO_GAPS_SECTION, "", TUI_SECTION[0]], "no window gaps writes its workspace rule just before the floating TUIs");
    assert.ok(gapsAt > gapsOn.indexOf("-- Theme appearance: motion left to the user's config; core default is off."), "no window gaps follows motion");
    const gapsOff = lines(layer.render([gapsSection(false)], theme, "vgs", 1));
    assert.ok(gapsOff.includes("-- Theme appearance: noGaps left to the user's config; noWindowGaps is off."), "the gaps switch off names its setting");
    assert.ok(!gapsOff.some(line => line.indexOf("hl.workspace_rule(") !== -1 || line.indexOf("gaps_") !== -1), "the gaps switch off writes no gaps");
    const otherTheme = JSON.parse(JSON.stringify(theme));
    otherTheme.hyprland.border.size = 1;
    const gapsOther = lines(layer.render([gapsSection(true)], otherTheme, "dusk", 1));
    same(gapsOther.slice(gapsOther.indexOf(NO_GAPS_SECTION[0]), gapsOther.indexOf(NO_GAPS_SECTION[0]) + NO_GAPS_SECTION.length), NO_GAPS_SECTION, "another theme leaves the gap rule as it was");
    assert.ok(bareLines.indexOf(TUI_SECTION[0]) < bareLines.indexOf(APP_SECTION[0]), "floating TUIs are before application windows");
    same(bareLines.slice(bareLines.indexOf(TUI_SECTION[0])), [...TUI_SECTION, "", ...APP_SECTION, "", ...USER_BINDS_SECTION, "", ...captureSection([]), "", ...PASSTHROUGH_SECTION, "", ...LOCK_SECTION, "", ...SWEEP_SECTION, ""], "a layer with no plugin section ends with the floating TUIs window rules, the application window rule, the user binds' recorder, overlay capture, the key capture pass-through, the session lock's restore, then the pads' sweep");
    // Pads: the section of the first plugin by id whose pads are declared,
    // after its binds, its motion from the theme.
    same(layer.PADS, { table: "__vgs_pads", verb: "toggle", workspace: "special:vgs-pad-", curve: "vgsPad", answers: ["no-pad", "no-window", "no-screen"] }, "the pads name their Lua table, toggle, workspace prefix, curve and the keys of their refusals");
    const padsLines = lines(layer.render([padsFixture(logic, "acme.pads")], theme, "vgs", 1, null, ""));
    const padsAt = padsLines.indexOf(PADS_SECTION[0]);
    same(padsLines.slice(padsAt, padsAt + PADS_SECTION.length), PADS_SECTION, "the pads section is written byte for byte");
    assert.ok(padsAt > padsLines.indexOf("hl.bind(\"SUPER + ALT + P\", hl.dsp.global(\"acme.pads:pad-1\"), { description = \"acme.pads:pad-1\" })") && padsAt > coreEnd(padsLines), "the pads follow the plugin's binds and the core's sections");
    const padsOf = (out, line) => lines(out).filter(l => l.startsWith(line));
    const stillTheme = Object.assign({}, theme, { motionScale: 0 });
    same(padsOf(layer.render([padsFixture(logic, "acme.pads")], stillTheme, "vgs", 1, null, ""), "    local pads = { list"), ["    local pads = { list = {}, before = {}, prefix = \"special:vgs-pad-\", motion = nil }"], "a theme that moves nothing gives the pads no motion");
    same(padsOf(layer.render([padsFixture(logic, "acme.pads")], stillTheme, "vgs", 1, null, ""), "    hl.curve("), [], "a theme that moves nothing writes no pad curve");
    const noneTheme = Object.assign({}, theme, { hyprland: Object.assign({}, theme.hyprland, { motion: { preset: "none" } }) });
    same(padsOf(layer.render([padsFixture(logic, "acme.pads")], noneTheme, "vgs", 1, null, ""), "    local pads = { list"), ["    local pads = { list = {}, before = {}, prefix = \"special:vgs-pad-\", motion = nil }"], "the none preset gives the pads no motion");
    const smoothTheme = Object.assign({}, theme, { motionScale: 1, hyprland: Object.assign({}, theme.hyprland, { motion: { preset: "smooth" } }) });
    same(padsOf(layer.render([padsFixture(logic, "acme.pads")], smoothTheme, "vgs", 1, null, ""), "    hl.curve(").concat(padsOf(layer.render([padsFixture(logic, "acme.pads")], smoothTheme, "vgs", 1, null, ""), "    local pads = { list")),
        ["    hl.curve(\"vgsPad\", { type = \"bezier\", points = { { 0.23, 1 }, { 0.32, 1 } } })", "    local pads = { list = {}, before = {}, prefix = \"special:vgs-pad-\", motion = { speed = 3.5, bezier = \"vgsPad\" } }"], "the smooth preset's workspace leaf gives the pads its curve and speed");
    const emptyPads = lines(layer.render([padsFixture(logic, "acme.pads", [])], theme, "vgs", 1, null, ""));
    same([emptyPads.includes(PADS_SECTION[0]), emptyPads.filter(l => l.startsWith("    pads.list[")), emptyPads.includes("    function pads.toggle(name, screen)")], [true, [], true], "a plugin with no pads still defines the pads' functions");
    const twoOwners = lines(layer.render([padsFixture(logic, "acme.zpads"), padsFixture(logic, "acme.pads")], theme, "vgs", 1, null, ""));
    same([twoOwners.filter(l => l === "    hl.__vgs_pads = pads").length, twoOwners.includes("-- pads of acme.zpads skipped: acme.pads defines them"), twoOwners.includes(PADS_SECTION[0])], [1, true, true], "the first plugin by id defines the pads and a later one's are a comment");
    same(lines(layer.render([section("acme.keys", [toggle], [])], theme, "vgs", 1, null, "")).some(l => l.includes("hl.__vgs_pads = pads")), false, "a plugin without pads writes no pads");
    same(layer.render([padsFixture(logic, "acme.zpads"), padsFixture(logic, "acme.pads")], theme, "vgs", 1, null, "").padConflicts, [{ id: "acme.zpads", heldBy: "acme.pads" }], "a plugin whose pads another defines is reported");
    same(layer.render([padsFixture(logic, "acme.pads")], theme, "vgs", 1, null, "").padConflicts, [], "one plugin's pads report nothing");
    const sweptLines = lines(layer.render([padsFixture(logic, "acme.pads")], theme, "vgs", 1, null, ""));
    same(sweptLines.slice(sweptLines.length - SWEEP_SECTION.length - 1), [...SWEEP_SECTION, ""], "the pads' sweep ends a layer with pads, after them");
    same(layer.KEY_PASSTHROUGH, { submap: "vgs:passthrough", cancel: "Escape", description: "vgs:passthrough-cancel", timeoutMs: 10000, table: "__vgs_key_passthrough", verbs: { enter: "enter", enterAnyWindow: "enterAnyWindow", leave: "leave" } }, "the key capture pass-through names its submap, cancel key, bind description, timeout, Lua table and verbs");
    // Monitor rules: only the declared owner writes the one section.
    const monitorCalls = out => lines(out).filter(line => /hl\.monitor\s*\(/.test(line));
    same(monitorCalls(bare), [], "a layer with no plugin section writes no monitor rule");
    const monitorSection = Object.assign(section("vgs.displays", [], []), { monitors: { kind: "set", setting: "outputs", value: { "DP-2": { mode: { width: 3840, height: 2160, refresh: 60 }, position: { x: 0, y: 0 }, scale: 2, transform: 0 } } } });
    const monitorOut = layer.render([monitorSection], theme, "vgs", 1, null, "");
    same(monitorCalls(monitorOut), ['hl.monitor({ output = "DP-2", mode = "3840x2160@60", position = "0x0", scale = 2, transform = 0 })'], "the monitors section writes the judged rule");
    assert.ok(lines(monitorOut).indexOf("-- vgs.displays 1.0.0: monitor rules from its settings") > coreEnd(lines(monitorOut)), "the monitors section follows the core sections");
    const refusedMonitor = Object.assign(section("vgs.displays", [], []), { monitors: { kind: "unfit", setting: "outputs", error: "refused: monitors.DP-2\" identifier refused" } });
    same([monitorCalls(layer.render([refusedMonitor], theme, "vgs", 1, null, "")).length, layer.render([refusedMonitor], theme, "vgs", 1, null, "").monitorRefusals.length], [0, 1], "a refused monitor rule writes no hl.monitor");
    const otherMonitor = Object.assign(section("acme.monitors", [], []), { monitors: { kind: "set", setting: "outputs", value: { "DP-3": { scale: 1 } } } });
    same(layer.render([otherMonitor, monitorSection], theme, "vgs", 1, null, "").monitorConflicts, [{ id: "vgs.displays", heldBy: "acme.monitors" }], "a second monitor owner is reported");
    same(layer.OVERLAY_CAPTURE, { submap: "vgs:capture", namespace: "vgs:overlay", appid: "vgs", shortcuts: { left: "overlay-left", right: "overlay-right", up: "overlay-up", down: "overlay-down" } }, "the overlay capture names its submap, namespace and shortcuts");
    same(layer.overlayCaptureDirections(), ["left", "right", "up", "down"], "the overlay capture direction list");
    assert.equal(layer.overlayCaptureGlobal("left"), "vgs:overlay-left", "the overlay capture global is derived");
    assert.throws(() => layer.overlayCaptureGlobal("next"), /overlay direction/, "unknown overlay directions are refused");
    same(layer.APP_WINDOW, { appId: "org.vgs.shell", rule: "vgs:window" }, "the application windows' app-id and rule name");
    same(pragmaAppId(shellText), layer.APP_WINDOW.appId, "shell.qml's AppId pragma is the application windows' app-id");
    assert.ok(lines(bare).some(line => line.includes("`" + layer.REGENERATE + "`")), "the header names the regenerate command");
    assert.strictEqual(layer.REGENERATE, "vgshell hypr render", "the regenerate command is the runner's verb");
    assert.ok(applied(bare).includes("-- Theme vgs: window, group and group bar borders."), "the border block names its theme");
    assert.ok(applied(bare).includes("            active_border = \"rgba(5a3659ff)\","), "a #aarrggbb accent is written rgba(rrggbbaa)");
    assert.ok(applied(bare).includes("            inactive_border = \"rgba(11223380)\","), "the border keeps its alpha last");
    assert.ok(applied(bare).includes("            text_color_locked_active = \"rgba(010101ff)\","), "the group bar's text colour is written");
    assert.ok(applied(bare).includes("        border_size = 4,"), "the border block writes the theme's border size");
    assert.ok(applied(bare).includes("            color = \"rgba(00008899)\","), "the border block writes the theme's shadow colour");
    assert.ok(applied(bare).includes("        rounding = 8,"), "the radius block writes the theme's window radius");
    assert.ok(applied(bare).includes("        rounding_power = 3,"), "the radius block writes the theme's rounding power");
    assert.ok(applied(bare).includes("            rounding = 16,"), "the radius block scales group bar rounding");
    assert.throws(() => layer.render([], Object.assign({}, theme, { colours: Object.assign({}, colours, { accent: "#5a36" }) }), "vgs", 1), /colour accent must be #aarrggbb/, "a colour Theme never publishes is refused");
    // A margin Theme never publishes is refused by name, never written.
    [
        ["absent margins", undefined, /tuiMargins\.gutter must be a finite number of at least 0, got undefined/],
        ["absent bar", { gutter: 10 }, /tuiMargins\.bar must be a finite number of at least 0, got undefined/],
        ["negative bar", { bar: -1, gutter: 10 }, /tuiMargins\.bar must be a finite number of at least 0, got -1/],
        ["negative gutter", { bar: 30, gutter: -0.5 }, /tuiMargins\.gutter must be a finite number of at least 0, got -0\.5/],
        ["infinite gutter", { bar: 30, gutter: Infinity }, /tuiMargins\.gutter must be a finite number of at least 0, got null/],
        ["NaN bar", { bar: NaN, gutter: 10 }, /tuiMargins\.bar must be a finite number of at least 0, got null/],
        ["string bar", { bar: "28", gutter: 10 }, /tuiMargins\.bar must be a finite number of at least 0, got "28"/]
    ].forEach(([label, margins, error]) => {
        assert.throws(() => layer.render([], Object.assign({}, theme, { tuiMargins: margins }), "vgs", 1), error, label + " is refused");
    });
    assert.ok(lines(layer.render([], Object.assign({}, theme, { tuiMargins: { bar: 0, gutter: 0 } }), "vgs", 1)).includes("hl.window_rule({ name = \"vgs:tui-tall\", match = { class = \"^org\\\\.vgs\\\\.tui\\\\.tall$\" }, float = true, center = true, size = { \"min(875,monitor_w-0)\", \"min(900,monitor_h-0)\" } })"), "zero margins clamp to the whole output");

    const motionSection = section("vgs.themes", [], [], "1.0.0", {
        borders: { setting: "setWindowBorders", enabled: false },
        radius: { setting: "setCornerRadius", enabled: false },
        motion: { setting: "setWindowAnimations", enabled: true }
    });
    const switched = layer.render([motionSection], theme, "vgs", 1.5);
    const switchedLines = lines(switched);
    same(applied(switched)[0], "-- Theme appearance: window animations.", "with borders and radius off the motion group is the first value applied");
    assert.ok(!switchedLines.some(line => line.indexOf("border_size = 4") !== -1), "a disabled border group writes no border size");
    assert.ok(!switchedLines.some(line => line.indexOf("rounding = 8") !== -1), "a disabled radius group writes no radius");
    assert.ok(switchedLines.includes("-- Theme appearance: borders left to the user's config; setWindowBorders is off."), "a disabled border group names its switch");
    const motionRows = [
        {
            name: "snappy",
            scale: 2,
            present: [
                "hl.curve(\"vgsSnappy\", { type = \"bezier\", points = { { 0.15, 0 }, { 0.1, 1 } } })",
                "hl.curve(\"vgsLinear\", { type = \"bezier\", points = { { 0, 0 }, { 1, 1 } } })",
                "hl.animation({ leaf = \"windows\", enabled = true, speed = 3.6, bezier = \"vgsSnappy\" })"
            ],
            absent: []
        },
        {
            name: "smooth",
            scale: 1,
            present: [
                "hl.curve(\"vgsEaseOutQuint\", { type = \"bezier\", points = { { 0.23, 1 }, { 0.32, 1 } } })",
                "hl.curve(\"vgsAlmostLinear\", { type = \"bezier\", points = { { 0.5, 0.5 }, { 0.75, 1 } } })",
                "hl.curve(\"vgsQuick\", { type = \"bezier\", points = { { 0.15, 0 }, { 0.1, 1 } } })",
                "hl.curve(\"vgsLinear\", { type = \"bezier\", points = { { 0, 0 }, { 1, 1 } } })",
                "hl.animation({ leaf = \"windows\", enabled = true, speed = 3.79, bezier = \"vgsEaseOutQuint\" })",
                "hl.animation({ leaf = \"windowsIn\", enabled = true, speed = 4.1, bezier = \"vgsEaseOutQuint\", style = \"popin 87%\" })"
            ],
            absent: []
        },
        {
            name: "none",
            scale: 1,
            present: ["hl.config({ animations = { enabled = false } })"],
            absent: ["hl.animation({ "]
        }
    ];
    for (const row of motionRows) {
        const motionTheme = JSON.parse(JSON.stringify(theme));
        motionTheme.hyprland.motion.preset = row.name;
        motionTheme.motionScale = row.scale;
        const motionLines = applied(layer.render([motionSection], motionTheme, "vgs", 1));
        for (const want of row.present)
            assert.ok(motionLines.includes(want), `motion preset ${row.name} writes ${want}`);
        for (const forbidden of row.absent)
            assert.ok(!motionLines.some(line => line.indexOf(forbidden) !== -1), `motion preset ${row.name} omits ${forbidden}`);
    }
    const switchOn = layer.render([section("vgs.themes", [], [], "1.0.0", { borders: { setting: "setWindowBorders", enabled: true }, radius: { setting: "setCornerRadius", enabled: false }, motion: { setting: "setWindowAnimations", enabled: false } })], theme, "vgs", 1);
    const switchOff = layer.render([section("vgs.themes", [], [], "1.0.0", { borders: { setting: "setWindowBorders", enabled: false }, radius: { setting: "setCornerRadius", enabled: false }, motion: { setting: "setWindowAnimations", enabled: false } })], theme, "vgs", 1);
    assert.notStrictEqual(switchOn.text, switchOff.text, "a switch change changes the rendered layer text");
    assert.ok(applied(switchOn).includes("        border_size = 4,"), "the on switch applies the theme border value");
    assert.ok(!switchOff.text.includes("border_size"), "the off switch writes no border value");
    const still = layer.render([section("vgs.themes", [], [], "1.0.0", { motion: { setting: "setWindowAnimations", enabled: true } })], Object.assign({}, theme, { motionScale: 0 }), "vgs", 1);
    assert.ok(applied(still).includes("hl.config({ animations = { enabled = false } })"), "motion scale 0 disables animations");
    const firstOwner = layer.render([
        section("vgs.themes", [], [], "1.0.0", { borders: { setting: "b", enabled: false }, radius: { setting: "r", enabled: false } }),
        section("acme.theme", [], [], "1.0.0", { borders: { setting: "a", enabled: true } })
    ], theme, "vgs", 1);
    same(firstOwner.appearanceConflicts, [{ id: "vgs.themes", heldBy: "acme.theme" }], "the first appearance owner by id wins");
    assert.ok(!lines(firstOwner).includes("-- Theme appearance: radius left to the user's config; r is off."), "a later appearance owner is ignored");

    const out = layer.render([
        section("vgs.notes", [{ shortcut: "inbox", key: "SUPER+N" }, { shortcut: "open", key: "SUPER+SPACE" }], [{ namespace: "^vgs:layer$", blur: true, ignoreAlpha: 0.6 }, overlayRule]),
        section("acme.keys", [{ shortcut: "toggle", key: "SUPER+SPACE" }, { shortcut: "gone", key: null }], [overlayRule, { namespace: "^vgs:layer$", blur: false }], "2\nos.exit()"),
        section("acme.quiet", [], [])
    ], theme, "night\nos.exit()", 1);
    const text = lines(out);
    const tail = text.slice(text.indexOf(TUI_SECTION[0]));
    same(tail, [
        ...TUI_SECTION,
        "",
        ...APP_SECTION,
        "",
        ...USER_BINDS_SECTION,
        "",
        ...captureSection([
            "    hl.bind(\"SUPER + SPACE\", hl.dsp.global(\"acme.keys:toggle\"), { description = \"acme.keys:toggle\" })",
            "    hl.bind(\"SUPER + N\", hl.dsp.global(\"vgs.notes:inbox\"), { description = \"vgs.notes:inbox\" })",
        ]),
        "",
        ...PASSTHROUGH_SECTION,
        "",
        ...LOCK_SECTION,
        "",
        "-- acme.keys 2?os.exit(): binds and layer rules from its manifest",
        "hl.layer_rule({ name = \"acme.keys:overlay\", match = { namespace = \"^vgs:overlay$\" }, blur = true, ignore_alpha = 0.6 })",
        "hl.layer_rule({ name = \"acme.keys:layer\", match = { namespace = \"^vgs:layer$\" }, blur = false })",
        "hl.bind(\"SUPER + SPACE\", hl.dsp.global(\"acme.keys:toggle\"), { description = \"acme.keys:toggle\" })",
        "-- unbound acme.keys:gone: no key is set",
        "",
        "-- vgs.notes 1.0.0: binds and layer rules from its manifest",
        "hl.layer_rule({ name = \"vgs.notes:layer\", match = { namespace = \"^vgs:layer$\" }, blur = true, ignore_alpha = 0.6 })",
        "-- layer rule for ^vgs:overlay$ already written by acme.keys",
        "hl.bind(\"SUPER + N\", hl.dsp.global(\"vgs.notes:inbox\"), { description = \"vgs.notes:inbox\" })",
        "-- skipped SUPER+SPACE: already bound by acme.keys",
        "",
        ...SWEEP_SECTION,
        ""
    ], "the floating TUIs' rules, then sections by id, rules then binds, a key to the first id, an identical rule once, a differing one twice");
    assert.ok(applied(out).includes("-- Theme night?os.exit(): window, group and group bar borders."), "a theme name cannot leave its comment");
    same(out.conflicts, [{ id: "vgs.notes", shortcut: "open", key: "SUPER+SPACE", heldBy: "acme.keys" }], "the skipped bind is the one conflict");

    // Input options: what hyprlandSection lists from the plugins row, and the
    // section the layer writes from it.
    const optionManifest = manifestOf(logic, {
        capabilities: ["shortcut", "hyprland"],
        settings: { sensitivity: 0, natural: false, tap: true, layouts: "us", rate: 25, touchpad: true },
        schema: {
            sensitivity: { type: "number", label: "S", min: -1, max: 1, step: 0.05 },
            natural: { type: "boolean", label: "N" },
            tap: { type: "boolean", label: "T" },
            layouts: { type: "string", label: "L", presets: [{ value: "us" }, { value: "us,de" }], allowCustom: true },
            rate: { type: "number", label: "R", min: 0, max: 200, step: 1 },
            touchpad: { type: "boolean", label: "P" }
        },
        hyprland: { binds: [toggle], options: { sensitivity: "input.sensitivity", natural: "input.natural_scroll", tap: "input.touchpad.tap_to_click", layouts: "input.kb_layout", rate: "input.repeat_rate", touchpad: "device.touchpad.enabled" } }
    });
    const optionConfig = row => ({ plugins: [Object.assign({ id: "acme.keys" }, row)] });
    same(logic.hyprlandSection(optionConfig({ sensitivity: 0.35, tap: false, layouts: "us,de" }), optionManifest).options, [
        { kind: "set", setting: "sensitivity", path: "input.sensitivity", value: 0.35, lua: "0.35" },
        { kind: "set", setting: "tap", path: "input.touchpad.tap_to_click", value: false, lua: "false" },
        { kind: "set", setting: "layouts", path: "input.kb_layout", value: "us,de", lua: "\"us,de\"" }
    ], "hyprlandSection lists only the options the plugins row sets, in the manifest's order");
    const enumOptionManifest = manifestOf(logic, {
        capabilities: ["hyprland"],
        settings: { layouts: "us" },
        schema: { layouts: { type: "enum", label: "L", options: ["us", "us\nos.exit()"] } },
        hyprland: { options: { layouts: "input.kb_layout" } }
    });
    same(logic.hyprlandSection(optionConfig({ layouts: "us\nos.exit()" }), enumOptionManifest).options,
        [{ kind: "unfit", setting: "layouts", path: "input.kb_layout", error: "want=characters:^[A-Za-z0-9_.,:()+-]*$" }],
        "hyprlandSection judges an enum value through the Lua literal judge");
    same(logic.hyprlandSection({}, optionManifest).options, [], "a plugin with no plugins row sets no option");
    same(logic.hyprlandSection(optionConfig({ sensitivity: 3 }), optionManifest).options, [{ kind: "unfit", setting: "sensitivity", path: "input.sensitivity", error: "want=at-most:1" }], "a set value outside its schema entry is unfit");
    const optionSection = row => logic.hyprlandSection(optionConfig(row), optionManifest);
    const optionText = (sections, touchpads) => layer.render(sections, theme, "vgs", 1, touchpads);
    const optionsOut = optionText([optionSection({ sensitivity: 0.35, tap: false, layouts: "us,de" })], null);
    const optionsTail = lines(optionsOut).slice(coreEnd(lines(optionsOut)) + 1);
    same(applied(optionsOut).slice(-2), [
        "-- acme.keys 1.0.0: input options its settings set",
        "hl.config({ input = { sensitivity = 0.35, touchpad = { tap_to_click = false }, kb_layout = \"us,de\" } })"
    ], "the set options are one hl.config, in the manifest's order, applied after the theme's groups");
    same(lines(optionsOut)[APPLIED_AT + 4], "    for _, path in ipairs({ \"input.sensitivity\", \"input.touchpad.tap_to_click\", \"input.kb_layout\" }) do options.start[path] = hl.get_config(path) end", "the layer reads each written option as it loads");
    const quietOptions = lines(layer.render([Object.assign({}, optionSection({ sensitivity: 0.35, touchpad: false }), { appearance: allOff })], theme, "vgs", 1, ["elan-touchpad"]));
    same(quietOptions.slice(APPLIED_AT, quietOptions.indexOf("-- Theme appearance: borders left to the user's config; b is off.") - 1),
        appliedSection(["input.sensitivity"], ["-- acme.keys 1.0.0: input options its settings set", "hl.config({ input = { sensitivity = 0.35 } })"]),
        "the applied section holds the options line, byte for byte, and reads no per-device option");
    same(quietOptions.slice(coreEnd(quietOptions) + 1, coreEnd(quietOptions) + 4), ["", "-- acme.keys 1.0.0: input options its settings set", "hl.device({ name = \"elan-touchpad\", enabled = false })"], "a touchpad's line stays with its plugin's section");
    same(optionsTail, [
        "",
        "-- acme.keys 1.0.0: binds and layer rules from its manifest",
        "hl.bind(\"SUPER + SPACE\", hl.dsp.global(\"acme.keys:toggle\"), { description = \"acme.keys:toggle\" })",
        "",
        ...SWEEP_SECTION,
        ""
    ], "a section whose options are all applied writes no options heading before its binds");
    assert.ok(!optionsOut.text.includes("tap-to-click"), "the layer writes the Lua name tap_to_click, never the hyphenated option name");
    assert.ok(!optionsOut.text.includes("natural_scroll") && !optionsOut.text.includes("repeat_rate"), "an option the plugins row does not set is not written");
    same(layer.optionLiteral(layer.OPTIONS["input.repeat_rate"], 2.5), { ok: false, error: "want=whole-number" }, "the option literal judge refuses a fractional int");
    same(layer.optionLiteral(layer.OPTIONS["input.kb_layout"], "us\nos.exit()"), { ok: false, error: "want=characters:^[A-Za-z0-9_.,:()+-]*$" }, "the option literal judge refuses a string that can leave Lua");
    const injectedOptionComment = optionText([Object.assign({}, optionSection({}), { options: [{ kind: "unfit", setting: "bad\nos.exit()", path: "input.kb_layout", error: "want=one\nos.exit()" }] })], null).text;
    assert.ok(injectedOptionComment.includes("-- skipped input.kb_layout for acme.keys:bad?os.exit(): want=one?os.exit()"), "option comments replace newlines in setting names and errors");
    assert.ok(!injectedOptionComment.includes("\nos.exit()"), "option comments cannot start Lua on another line");
    same(optionsOut.options, [
        { id: "acme.keys", setting: "sensitivity", path: "input.sensitivity", value: 0.35 },
        { id: "acme.keys", setting: "tap", path: "input.touchpad.tap_to_click", value: false },
        { id: "acme.keys", setting: "layouts", path: "input.kb_layout", value: "us,de" }
    ], "the render lists each option it wrote");
    same(optionsOut.binds, ["acme.keys:toggle"], "the render lists the description of each bind it wrote");
    same([optionsOut.optionConflicts, optionsOut.optionRefusals], [[], []], "a clean options section reports nothing");
    assert.ok(!optionText([optionSection({})], null).text.includes("-- acme.keys 1.0.0: input options its settings set"), "a plugins row that sets no option writes no options section");
    // rows: [name, plugins row, touchpads, lines the options section ends with, refusals]
    const optionRows = [
        ["a fractional int is refused", { rate: 2.5 }, null, ["-- skipped input.repeat_rate for acme.keys:rate: want=whole-number"], [{ id: "acme.keys", setting: "rate", path: "input.repeat_rate", error: "want=whole-number" }]],
        ["a string that would end the Lua string is refused", { layouts: "us\"), os.exit(" }, null, ["-- skipped input.kb_layout for acme.keys:layouts: want=characters:^[A-Za-z0-9_.,:()+-]*$"], [{ id: "acme.keys", setting: "layouts", path: "input.kb_layout", error: "want=characters:^[A-Za-z0-9_.,:()+-]*$" }]],
        ["an unfit value is skipped with its reason", { sensitivity: 3 }, null, ["-- skipped input.sensitivity for acme.keys:sensitivity: want=at-most:1"], [{ id: "acme.keys", setting: "sensitivity", path: "input.sensitivity", error: "want=at-most:1" }]],
        ["the touchpad is written per touchpad Hyprland lists", { touchpad: false }, ["elan0676:00-04f3:3195-touchpad", "apple-trackpad\"x"], ["hl.device({ name = \"elan0676:00-04f3:3195-touchpad\", enabled = false })", "-- skipped touchpad apple-trackpad\"x for acme.keys:touchpad: its name holds a quote, a backslash or a control character"], [{ id: "acme.keys", setting: "touchpad", path: "device.touchpad.enabled", error: "touchpad name refused" }]],
        ["no touchpad listed writes none", { touchpad: false }, [], ["-- device.touchpad.enabled for acme.keys:touchpad: Hyprland lists no touchpad", "-- skipped device.touchpad.enabled for acme.keys:touchpad: Hyprland lists no touchpad"], [{ id: "acme.keys", setting: "touchpad", path: "device.touchpad.enabled", error: "Hyprland lists no touchpad" }]],
        ["unread touchpads write none", { touchpad: true }, null, ["-- device.touchpad.enabled for acme.keys:touchpad: Hyprland's touchpads are not read yet"], []]
    ];
    for (const [name, row, touchpads, want, refusals] of optionRows) {
        const out = optionText([optionSection(row)], touchpads);
        const text = lines(out);
        const start = text.indexOf("-- acme.keys 1.0.0: input options its settings set") + 1;
        same(text.slice(start, start + want.length), want, "options: " + name);
        same(out.optionRefusals, refusals, "options: " + name + ": refusals");
    }
    const rival = Object.assign({}, optionSection({ sensitivity: -0.5 }), { id: "acme.other" });
    const contested = optionText([optionSection({ sensitivity: 0.35 }), rival], null);
    const contestedLines = lines(contested);
    same(applied(contested).slice(-2), ["-- acme.keys 1.0.0: input options its settings set", "hl.config({ input = { sensitivity = 0.35 } })"], "the first plugin by id applies the path two plugins set");
    same(contestedLines.slice(contestedLines.indexOf("-- acme.keys 1.0.0: binds and layer rules from its manifest")), [
        "-- acme.keys 1.0.0: binds and layer rules from its manifest",
        "hl.bind(\"SUPER + SPACE\", hl.dsp.global(\"acme.keys:toggle\"), { description = \"acme.keys:toggle\" })",
        "",
        "-- acme.other 1.0.0: input options its settings set",
        "-- skipped input.sensitivity for acme.other:sensitivity: already set by acme.keys",
        "",
        "-- acme.other 1.0.0: binds and layer rules from its manifest",
        "-- skipped SUPER+SPACE: already bound by acme.keys",
        "",
        ...SWEEP_SECTION,
        ""
    ], "sections by id, and a path two plugins set stays with the first by id");
    same(contested.optionConflicts, [{ id: "acme.other", setting: "sensitivity", path: "input.sensitivity", heldBy: "acme.keys" }], "the skipped option is the one option conflict");
    same([layer.wantsTouchpads([optionSection({ touchpad: false })]), layer.wantsTouchpads([optionSection({ tap: false })]), layer.wantsTouchpads([])], [true, false, false], "only a set touchpad option asks for the touchpads");
    assert.throws(() => optionText([Object.assign({}, optionSection({}), { options: [{ kind: "set", setting: "x", path: "input.nope", value: true, lua: "true" }] })], null), /option path "input.nope" is not one of OPTIONS/, "a path outside the table never reaches the text");
    for (const [name, events, wantActions, wantState] of SEQUENCES) {
        let state = layer.initialState();
        const actions = [];
        for (const [event, text] of events) {
            let next;
            try {
                next = layer.step(state, event, text);
            } catch (e) {
                e.message = "step " + name + ": " + e.message;
                throw e;
            }
            state = next.state;
            actions.push(next.action);
        }
        same(actions, wantActions, "step " + name + ": actions");
        const picked = {};
        for (const key of Object.keys(wantState)) picked[key] = state[key];
        same(picked, wantState, "step " + name + ": state");
    }
    assert.throws(() => layer.step(layer.initialState(), { type: "saved" }, "T1"), /event saved arrived in phase reading, want writing/, "a step result out of its phase is refused");
    assert.throws(() => layer.step(layer.initialState(), { type: "later" }, "T1"), /unknown event "later"/, "an unknown event is refused");
    same(layer.consentView({ phase: "asking", queued: "connect", failure: "reload=failed" }).busy, true, "a queued consent answer makes the dialog busy");
    same(layer.consentView({ phase: "asking", queued: "", failure: "" }).busy, false, "an unanswered consent dialog is not busy");
}

// HyprlandLayer.step rows: [name, [[event, text]...], actions, state subset].
// T0 is what the file held, T1 and T2 what the shell renders.
const loaded = content => ({ type: "loaded", content: content });
const absent = { type: "loadFailed", notFound: true, detail: "" };
const render = { type: "render" };
const force = { type: "force" };
const mkdirOk = { type: "mkdirDone", failure: "" };
const saved = { type: "saved" };
const saveFailed = { type: "saveFailed", failure: "write=failed error=4" };
const reloaded = { type: "reloadDone", failure: "" };
const probeUnwired = { type: "probeDone", answer: "unwired", failure: "" };
const probeWired = { type: "probeDone", answer: "wired", failure: "" };
const probeAbsent = { type: "probeDone", answer: "absent", failure: "" };
const probeFailed = { type: "probeDone", answer: "", failure: "probe=failed status=1" };
const notDeclined = { type: "declineChecked", declined: false, failure: "" };
const declined = { type: "declineChecked", declined: true, failure: "" };
const SEQUENCES = [
    ["a first completed write and reload probes and asks when unwired",
        [[absent, "T1"], [mkdirOk, "T1"], [saved, "T1"], [reloaded, "T1"], [probeUnwired, "T1"], [notDeclined, "T1"]],
        ["mkdir", "write", "reload", "probe", "checkDecline", "none"], { phase: "idle", onDisk: "T1", failure: "", consent: { phase: "asking", queued: "", failure: "" } }],
    ["a wired probe settles",
        [[loaded("T0"), "T1"], [mkdirOk, "T1"], [saved, "T1"], [reloaded, "T1"], [probeWired, "T1"]],
        ["mkdir", "write", "reload", "probe", "none"], { phase: "idle", consent: { phase: "wired", queued: "", failure: "" } }],
    ["an absent hyprland.lua probe settles",
        [[loaded("T0"), "T1"], [mkdirOk, "T1"], [saved, "T1"], [reloaded, "T1"], [probeAbsent, "T1"]],
        ["mkdir", "write", "reload", "probe", "none"], { phase: "idle", consent: { phase: "settled", queued: "", failure: "" } }],
    ["a probe failure is reported and raises no question",
        [[loaded("T0"), "T1"], [mkdirOk, "T1"], [saved, "T1"], [reloaded, "T1"], [probeFailed, "T1"]],
        ["mkdir", "write", "reload", "probe", "none"], { phase: "idle", failure: "probe=failed status=1", consent: { phase: "settled", queued: "", failure: "" } }],
    ["a Hyprland-session decline marker suppresses the question",
        [[loaded("T0"), "T1"], [mkdirOk, "T1"], [saved, "T1"], [reloaded, "T1"], [probeUnwired, "T1"], [declined, "T1"]],
        ["mkdir", "write", "reload", "probe", "checkDecline", "none"], { phase: "idle", consent: { phase: "declined", queued: "", failure: "" } }],
    ["decline writes the marker and closes the question",
        [[loaded("T0"), "T1"], [mkdirOk, "T1"], [saved, "T1"], [reloaded, "T1"], [probeUnwired, "T1"], [notDeclined, "T1"], [{ type: "decline" }, "T1"], [{ type: "declineDone", failure: "" }, "T1"]],
        ["mkdir", "write", "reload", "probe", "checkDecline", "none", "decline", "none"], { phase: "idle", consent: { phase: "declined", queued: "", failure: "" } }],
    ["a marker write failure is reported but still closes the question",
        [[loaded("T0"), "T1"], [mkdirOk, "T1"], [saved, "T1"], [reloaded, "T1"], [probeUnwired, "T1"], [notDeclined, "T1"], [{ type: "decline" }, "T1"], [{ type: "declineDone", failure: "decline-marker-write=failed path=p" }, "T1"]],
        ["mkdir", "write", "reload", "probe", "checkDecline", "none", "decline", "none"], { phase: "idle", failure: "decline-marker-write=failed path=p", consent: { phase: "declined", queued: "", failure: "" } }],
    ["connect wires and reloads",
        [[loaded("T0"), "T1"], [mkdirOk, "T1"], [saved, "T1"], [reloaded, "T1"], [probeUnwired, "T1"], [notDeclined, "T1"], [{ type: "connect" }, "T1"], [{ type: "wireDone", failure: "" }, "T1"], [reloaded, "T1"]],
        ["mkdir", "write", "reload", "probe", "checkDecline", "none", "wire", "reload", "none"], { phase: "idle", consent: { phase: "wired", queued: "", failure: "" } }],
    ["a reload failure after wire keeps asking and Connect retries",
        [[loaded("T0"), "T1"], [mkdirOk, "T1"], [saved, "T1"], [reloaded, "T1"], [probeUnwired, "T1"], [notDeclined, "T1"], [{ type: "connect" }, "T1"], [{ type: "wireDone", failure: "" }, "T1"], [{ type: "reloadDone", failure: "reload=failed status=1" }, "T1"], [{ type: "connect" }, "T1"], [{ type: "wireDone", failure: "" }, "T1"], [reloaded, "T1"]],
        ["mkdir", "write", "reload", "probe", "checkDecline", "none", "wire", "reload", "none", "wire", "reload", "none"], { phase: "idle", failure: "", consent: { phase: "wired", queued: "", failure: "" } }],
    ["a wire failure keeps the question open",
        [[loaded("T0"), "T1"], [mkdirOk, "T1"], [saved, "T1"], [reloaded, "T1"], [probeUnwired, "T1"], [notDeclined, "T1"], [{ type: "connect" }, "T1"], [{ type: "wireDone", failure: "wire=failed status=1" }, "T1"]],
        ["mkdir", "write", "reload", "probe", "checkDecline", "none", "wire", "none"], { phase: "idle", failure: "wire=failed status=1", consent: { phase: "asking", queued: "", failure: "wire=failed status=1" } }],
    ["Not now after Connect is ignored while wire runs",
        [[loaded("T1"), "T1"], [probeUnwired, "T1"], [notDeclined, "T1"], [{ type: "connect" }, "T1"], [{ type: "decline" }, "T1"], [{ type: "wireDone", failure: "" }, "T1"], [reloaded, "T1"]],
        ["probe", "checkDecline", "none", "wire", "none", "reload", "none"], { phase: "idle", consent: { phase: "wired", queued: "", failure: "" } }],
    ["Not now cannot replace a running Connect",
        [[loaded("T1"), "T1"], [probeUnwired, "T1"], [notDeclined, "T1"], [{ type: "connect" }, "T1"], [{ type: "decline" }, "T1"]],
        ["probe", "checkDecline", "none", "wire", "none"], { phase: "wiring", consent: { phase: "asking", queued: "connect", failure: "" } }],
    ["Connect after Not now is ignored while marker write runs",
        [[loaded("T1"), "T1"], [probeUnwired, "T1"], [notDeclined, "T1"], [{ type: "decline" }, "T1"], [{ type: "connect" }, "T1"], [{ type: "declineDone", failure: "" }, "T1"]],
        ["probe", "checkDecline", "none", "decline", "none", "none"], { phase: "idle", consent: { phase: "declined", queued: "", failure: "" } }],
    ["Connect cannot replace a running Not now",
        [[loaded("T1"), "T1"], [probeUnwired, "T1"], [notDeclined, "T1"], [{ type: "decline" }, "T1"], [{ type: "connect" }, "T1"]],
        ["probe", "checkDecline", "none", "decline", "none"], { phase: "declining", consent: { phase: "asking", queued: "decline", failure: "" } }],
    ["connect during a write waits for the step to end",
        [[loaded("T0"), "T1"], [mkdirOk, "T1"], [saved, "T1"], [reloaded, "T1"], [probeUnwired, "T1"], [notDeclined, "T1"], [force, "T2"], [loaded("T1"), "T2"], [{ type: "connect" }, "T2"], [mkdirOk, "T2"], [saved, "T2"], [reloaded, "T2"], [{ type: "wireDone", failure: "" }, "T2"], [reloaded, "T2"]],
        ["mkdir", "write", "reload", "probe", "checkDecline", "none", "read", "mkdir", "none", "write", "reload", "wire", "reload", "none"], { phase: "idle", onDisk: "T2", consent: { phase: "wired", queued: "", failure: "" } }],
    ["decline during a write waits for the step to end",
        [[loaded("T0"), "T1"], [mkdirOk, "T1"], [saved, "T1"], [reloaded, "T1"], [probeUnwired, "T1"], [notDeclined, "T1"], [force, "T2"], [loaded("T1"), "T2"], [{ type: "decline" }, "T2"], [mkdirOk, "T2"], [saved, "T2"], [reloaded, "T2"], [{ type: "declineDone", failure: "" }, "T2"]],
        ["mkdir", "write", "reload", "probe", "checkDecline", "none", "read", "mkdir", "none", "write", "reload", "decline", "none"], { phase: "idle", onDisk: "T2", consent: { phase: "declined", queued: "", failure: "" } }],
    ["a render during the probe writes before the marker check",
        [[loaded("T1"), "T1"], [render, "T2"], [probeUnwired, "T2"], [mkdirOk, "T2"], [saved, "T2"], [reloaded, "T2"]],
        ["probe", "none", "mkdir", "write", "reload", "checkDecline"], { phase: "checkingDecline", onDisk: "T2", consent: { phase: "unwired", queued: "", failure: "" } }],
    ["a force during the probe reads before the marker check",
        [[loaded("T1"), "T1"], [force, "T1"], [probeUnwired, "T1"], [loaded("T1"), "T1"], [mkdirOk, "T1"], [reloaded, "T1"]],
        ["probe", "none", "read", "mkdir", "reload", "checkDecline"], { phase: "checkingDecline", onDisk: "T1", consent: { phase: "unwired", queued: "", failure: "" } }],
    ["a render during the marker check writes before asking",
        [[loaded("T1"), "T1"], [probeUnwired, "T1"], [render, "T2"], [notDeclined, "T2"]],
        ["probe", "checkDecline", "none", "mkdir"], { phase: "preparing", pending: "T2", consent: { phase: "asking", queued: "", failure: "" } }],
    ["a force during marker write reads after the marker is written",
        [[loaded("T1"), "T1"], [probeUnwired, "T1"], [notDeclined, "T1"], [{ type: "decline" }, "T1"], [force, "T1"], [{ type: "declineDone", failure: "" }, "T1"]],
        ["probe", "checkDecline", "none", "decline", "none", "read"], { phase: "reading", consent: { phase: "declined", queued: "", failure: "" } }],
    ["a render during wire writes after the wire reload",
        [[loaded("T1"), "T1"], [probeUnwired, "T1"], [notDeclined, "T1"], [{ type: "connect" }, "T1"], [render, "T2"], [{ type: "wireDone", failure: "" }, "T2"], [reloaded, "T2"]],
        ["probe", "checkDecline", "none", "wire", "none", "reload", "mkdir"], { phase: "preparing", pending: "T2", consent: { phase: "wired", queued: "", failure: "" } }],
    ["an unchanged layer at start is probed", [[loaded("T1"), "T1"]], ["probe"], { phase: "probing", onDisk: "T1", consent: { phase: "pending", queued: "", failure: "" } }],
    ["a changed file is written and reloaded, not wired",
        [[loaded("T0"), "T1"], [mkdirOk, "T1"], [saved, "T1"]],
        ["mkdir", "write", "reload"], { phase: "reloading", onDisk: "T1" }],
    ["a render during a cycle waits for it, then writes its text",
        [[loaded("T0"), "T1"], [render, "T2"], [mkdirOk, "T2"], [saved, "T2"], [reloaded, "T2"], [mkdirOk, "T2"]],
        ["mkdir", "none", "write", "reload", "mkdir", "write"], { phase: "writing", pending: "T2", onDisk: "T1" }],
    ["a failed save reads the file before another write and retries its text only once the text changes",
        [[loaded("T0"), "T1"], [mkdirOk, "T1"], [saveFailed, "T1"], [loaded("T0"), "T1"], [render, "T1"], [render, "T2"], [mkdirOk, "T2"], [saved, "T2"], [reloaded, "T2"]],
        ["mkdir", "write", "read", "none", "none", "mkdir", "write", "reload", "probe"], { phase: "probing", onDisk: "T2", failedText: null, stale: false, failure: "", consent: { phase: "pending", queued: "", failure: "" } }],
    ["a render after a failed save rereads and writes the same text again",
        [[loaded("T0"), "T1"], [mkdirOk, "T1"], [saveFailed, "T1"], [loaded("T0"), "T1"], [force, "T1"], [loaded("T0"), "T1"], [mkdirOk, "T1"], [saved, "T1"], [reloaded, "T1"]],
        ["mkdir", "write", "read", "none", "read", "mkdir", "write", "reload", "probe"], { phase: "probing", onDisk: "T1", forcing: false, failedText: null, consent: { phase: "pending", queued: "", failure: "" } }],
    ["a failed mkdir tries its text once",
        [[loaded("T0"), "T1"], [{ type: "mkdirDone", failure: "mkdir=failed status=1" }, "T1"], [render, "T1"]],
        ["mkdir", "none", "none"], { phase: "idle", failedText: "T1", failure: "mkdir=failed status=1" }],
    ["a render during a reload, after the file was removed, writes it again",
        [[loaded("T0"), "T1"], [mkdirOk, "T1"], [saved, "T1"], [force, "T1"], [reloaded, "T1"], [absent, "T1"], [mkdirOk, "T1"], [saved, "T1"], [reloaded, "T1"]],
        ["mkdir", "write", "reload", "none", "read", "mkdir", "write", "reload", "probe"], { phase: "probing", onDisk: "T1", queuedForce: false, forcing: false, consent: { phase: "pending", queued: "", failure: "" } }],
    ["a render of unchanged bytes reloads without a write",
        [[loaded("T1"), "T1"], [probeWired, "T1"], [force, "T1"], [loaded("T1"), "T1"], [mkdirOk, "T1"], [reloaded, "T1"]],
        ["probe", "none", "read", "mkdir", "reload", "none"], { phase: "idle", onDisk: "T1", forcing: false, consent: { phase: "wired", queued: "", failure: "" } }],
    ["a first read before the text waits, and wires after the first write",
        [[absent, null], [render, "T1"], [mkdirOk, "T1"], [saved, "T1"]],
        ["none", "mkdir", "write", "reload"], { phase: "reloading" }],
    ["an unreadable file is reported and written",
        [[{ type: "loadFailed", notFound: false, detail: "error=3" }, "T1"]],
        ["mkdir"], { onDisk: null, failure: "read=failed error=3" }],
    ["a reread that finds no file is no first run",
        [[loaded("T1"), "T1"], [probeWired, "T1"], [force, "T1"], [absent, "T1"], [mkdirOk, "T1"], [saved, "T1"]],
        ["probe", "none", "read", "mkdir", "write", "reload"], { phase: "reloading" }]
];

const shellText = fs.readFileSync(shellFile, "utf8");
verify(load(logicFile), load(layerFile), shellText);

// Each control removes one rule from a copy of one file and keeps the text
// around it. The suite must fail on every copy.
const CONTROLS = [
    [logicFile, "hyprland is a manifest key", "\"appearance\", \"hyprland\", ", "\"appearance\", "],
    [logicFile, "key parts upper case", "return part.trim().toUpperCase();", "return part.trim();"],
    [logicFile, "modifier order", "var ordered = HYPRLAND_MODIFIERS.filter(function (mod) { return mods.indexOf(mod) !== -1; });", "var ordered = mods;"],
    [logicFile, "key string", "if (typeof text !== \"string\")\n        return { ok: false, error: \"must be a string", "if (false)\n        return { ok: false, error: \"must be a string"],
    [logicFile, "key empty part", "if (parts.some(function (part) { return part.length === 0; }))", "if (false)"],
    [logicFile, "key not a modifier", "if (HYPRLAND_MODIFIERS.indexOf(name) !== -1)\n        return", "if (false)\n        return"],
    [logicFile, "key name", "if (!HYPRLAND_KEY_NAME.test(name))", "if (false)"],
    [logicFile, "known modifier", "if (HYPRLAND_MODIFIERS.indexOf(mods[i]) === -1)", "if (false)"],
    [logicFile, "modifier once", "if (mods.indexOf(mods[i]) !== i)", "if (false)"],
    [logicFile, "hyprland object", "if (!isPlainObject(hyprland))", "if (false)"],
    [logicFile, "hyprland keys", "if (HYPRLAND_KEYS.indexOf(keys[u]) === -1)", "if (false)"],
    [logicFile, "binds list", "if (!Array.isArray(binds))", "if (false)"],
    [logicFile, "rules list", "if (!Array.isArray(rules))", "if (false)"],
    [logicFile, "declares something", "if (binds.length === 0 && rules.length === 0 && appearance === undefined && options === undefined && hyprland.pads === undefined && monitors === undefined)", "if (false)"],
    [logicFile, "binds need shortcut", "if (binds.length > 0 && capabilities.indexOf(\"shortcut\") === -1)", "if (false)"],
    [logicFile, "bind object", "if (!isPlainObject(bind))", "if (false)"],
    [logicFile, "bind keys", "if (HYPRLAND_BIND_KEYS.indexOf(bindKeys[k]) === -1)", "if (false)"],
    [logicFile, "shortcut name", "if (typeof bind.shortcut !== \"string\" || !NAME_PATTERN.test(bind.shortcut))", "if (typeof bind.shortcut !== \"string\")"],
    [logicFile, "shortcut once", "if (shortcuts.indexOf(bind.shortcut) !== -1)", "if (false)"],
    [logicFile, "hold boolean", "if (bind.hold !== undefined && typeof bind.hold !== \"boolean\")", "if (false)"],
    [logicFile, "tap boolean", "if (bind.tap !== undefined && typeof bind.tap !== \"boolean\")", "if (false)"],
    [logicFile, "tap excludes hold", "if (bind.tap === true && bind.hold === true)", "if (false)"],
    [logicFile, "tap manifest key is lone", "if (bind.tap === true && keyHasModifiers(key.key))\n            return at + \".key \" + key.key + \" must be a lone key for tap\";", "if (false)\n            return at + \".key \" + key.key + \" must be a lone key for tap\";"],
    [logicFile, "hold retained", "if (bind.hold === true) result.hold = true;", "if (false) result.hold = true;"],
    [logicFile, "tap retained", "if (bind.tap === true) result.tap = true;", "if (false) result.tap = true;"],
    [layerFile, "hold release emitted", "return entry.bind.hold === true ? releaseShortcutName", "return false ? releaseShortcutName"],
    [layerFile, "release ignores live modifiers", "release = true, non_consuming = true, transparent = true, ignore_mods = true", "release = true, non_consuming = true, transparent = true, ignore_mods = false"],
    [layerFile, "release does not consume input", "release = true, non_consuming = true, transparent = true, ignore_mods = true", "release = true, non_consuming = false, transparent = true, ignore_mods = true"],
    [layerFile, "release is not shadowed", "release = true, non_consuming = true, transparent = true, ignore_mods = true", "release = true, non_consuming = true, transparent = false, ignore_mods = true"],
    [layerFile, "release runs on key up", "release = true, non_consuming = true, transparent = true, ignore_mods = true", "release = false, non_consuming = true, transparent = true, ignore_mods = true"],
    [logicFile, "bind key judged", "if (!key.ok)\n            return at + \".key \" + key.error;", "if (false)\n            return at + \".key \" + key.error;"],
    [logicFile, "key once", "if (boundKeys.indexOf(key.key) !== -1)", "if (false)"],
    [logicFile, "rule object", "if (!isPlainObject(rule))\n            return where + \" must be an object\";", "if (false)\n            return where + \" must be an object\";"],
    [logicFile, "rule keys", "if (HYPRLAND_RULE_KEYS.indexOf(ruleKeys[q]) === -1)", "if (false)"],
    [logicFile, "namespace anchored", "var HYPRLAND_NAMESPACE = /^\\^vgs:[a-z][a-z0-9-]*\\$$/;", "var HYPRLAND_NAMESPACE = /vgshell:/;"],
    [logicFile, "namespace once", "if (namespaces.indexOf(rule.namespace) !== -1)", "if (false)"],
    [logicFile, "rule has an effect", "if (rule.blur === undefined && rule.ignoreAlpha === undefined)", "if (false)"],
    [logicFile, "blur boolean", "if (rule.blur !== undefined && typeof rule.blur !== \"boolean\")", "if (false)"],
    [logicFile, "ignoreAlpha range", "rule.ignoreAlpha < 0 || rule.ignoreAlpha > 1))", "false))"],
    [logicFile, "appearance object", "if (!isPlainObject(appearance) || Object.keys(appearance).length === 0)", "if (false)"],
    [logicFile, "appearance needs theme", "if (capabilities.indexOf(\"theme\") === -1)", "if (false)"],
    [logicFile, "appearance known group", "if (HYPRLAND_APPEARANCE_GROUPS.indexOf(group) === -1)", "if (false)"],
    [logicFile, "appearance schema key", "if (!hasOwn(schema, setting))", "if (false)"],
    [logicFile, "appearance boolean setting", "if (schema[setting].type !== \"boolean\")", "if (false)"],
    [logicFile, "keys setting reserved", "if (hasOwn(settings, \"keys\"))", "if (false)"],
    [logicFile, "manifest keys normalised", "var result = { shortcut: bind.shortcut, key: bind.key === null ? null : hyprlandKey(bind.key).key };", "var result = { shortcut: bind.shortcut, key: bind.key };"],
    [logicFile, "config keys judged", "if (config.plugins[p].keys !== undefined && (bad = keysError(", "if (false && (bad = keysError("],
    [logicFile, "keys object", "if (!isPlainObject(keys))\n        return at + \" must be an object\";", "if (false)\n        return at + \" must be an object\";"],
    [logicFile, "keys names", "if (!NAME_PATTERN.test(names[i]))", "if (false)"],
    [logicFile, "keys null unbinds", "if (keys[names[i]] === null)\n            continue;", "if (false)\n            continue;"],
    [logicFile, "keys values", "if (!key.ok)\n            return itemAt + \" \" + key.error;", "if (false)\n            return itemAt + \" \" + key.error;"],
    [logicFile, "keys empty lists", "if (Array.isArray(value) && value.length === 0)\n        return at + \" must not be an empty list\";", "if (false)\n        return at + \" must not be an empty list\";"],
    [logicFile, "keys no setting", "var ENTRY_RESERVED_KEYS = [\"id\", \"keys\"];", "var ENTRY_RESERVED_KEYS = [\"id\"];"],
    [logicFile, "row key wins", "if (!hasOwn(keys, bind.shortcut)) {\n            binds.push(Object.assign({}, bind));\n            return;\n        }", "binds.push(Object.assign({}, bind));\n            return;"],
    [logicFile, "null unbinds", "if (keys[bind.shortcut] === null) {\n            binds.push(Object.assign({}, bind, { key: null }));\n            return;\n        }", ""],
    [logicFile, "key lists expand to binds", "keyValues(keys[bind.shortcut]).forEach(function (value) {", "[keyValues(keys[bind.shortcut])[0]].forEach(function (value) {"],
    [logicFile, "row key normalised", "var result = Object.assign({}, bind, { key: key.key });", "var result = Object.assign({}, bind, { key: keys[bind.shortcut] });"],
    [logicFile, "tap override key is refused", "if (bind.tap === true && keyHasModifiers(key.key))\n                result.error = \"tap key must be a lone key with no modifiers\";", "if (false)\n                result.error = \"tap key must be a lone key with no modifiers\";"],
    [logicFile, "unknown keys", "return names.indexOf(name) === -1 && !Pads.isPadShortcut(declared, name, NAME_PATTERN); }).sort()", "return false; }).sort()"],
    [logicFile, "appearance setting resolved", "appearance[group] = { setting: setting, enabled: settings[setting] === true };", "appearance[group] = { setting: setting, enabled: true };"],
    [layerFile, "sections by id", "var rows = sections.slice().sort(function (a, b) { return a.id < b.id ? -1 : a.id > b.id ? 1 : 0; }).map(", "var rows = sections.slice().map("],
    [layerFile, "empty section unwritten", "if (section.binds.length === 0 && section.layerRules.length === 0 && !Array.isArray(section.pads)) return;", ""],
    [layerFile, "first id keeps a key", "if (held[bind.key] !== undefined) {", "if (false) {"],
    [layerFile, "unbound bind", "if (bind.key === null) return { kind: \"unbound\"", "if (false) return { kind: \"unbound\""],
    [layerFile, "refused bind", "if (bind.error !== undefined) return { kind: \"refused\"", "if (false) return { kind: \"refused\""],
    [logicFile, "keycode grammar", "/^CODE:[0-9]+$/", "/^CODE:.+$/"],
    [logicFile, "keycode uint32", " && Number(name.slice(5)) <= 4294967295", ""],
    [logicFile, "keycode lower-case prefix", 'name = "code:" + String(Number(name.slice(5)));', 'name = "CODE:" + String(Number(name.slice(5)));'],
    [logicFile, "keycode leading zeros", 'String(Number(name.slice(5)))', 'name.slice(5)'],
    [layerFile, "shortcut read respects conflicts", 'if (held[bind.key] !== undefined) {\n                conflicts.push', 'if (held[bind.key] !== undefined) {\n                keys[section.id][bind.shortcut] = bind.key;\n                conflicts.push'],
    [layerFile, "shortcut read keeps the first key", "if (keys[section.id][bind.shortcut] === null)\n                keys[section.id][bind.shortcut] = bind.key;", "keys[section.id][bind.shortcut] = bind.key;"],
    [layerFile, "shortcut map has no inherited names", 'keys[section.id] = Object.create(null);', 'keys[section.id] = {};'],
    [layerFile, "tap tracker emitted", "if (tapTrackerWanted(plan)) lines = lines.concat([\"\"], tapTrackerLines());", "if (false) lines = lines.concat([\"\"], tapTrackerLines());"],
    [layerFile, "tap bind gates", "function() hl.__vgs_tap.gate = \\\"\" + global + \"\\\" end", "hl.dsp.global(\\\"\" + global + \"\\\")"],
    [layerFile, "tap bind is non-consuming", "function() hl.__vgs_tap.gate = \\\"\" + global + \"\\\" end, { description = \\\"\" + global + \"\\\", non_consuming = true, transparent = true, ignore_mods = true", "function() hl.__vgs_tap.gate = \\\"\" + global + \"\\\" end, { description = \\\"\" + global + \"\\\", non_consuming = false, transparent = true, ignore_mods = true"],
    [layerFile, "tap press disarms chords", " else tap.armed = nil end", " end"],
    [layerFile, "tap arms only a lone press", "if next(tap.held) == nil then", "if true then"],
    [layerFile, "tap checks repeat delay", "ms - armed.ms < hl.get_config(\\\"input.repeat_delay\\\")", "true"],
    [layerFile, "identical rule once", "if (written[key] !== undefined) {", "if (false) {"],
    [layerFile, "rule effects compared", "return JSON.stringify([rule.namespace, rule.blur", "return JSON.stringify([rule.namespace]); ([rule.namespace, rule.blur"],
    [layerFile, "comment text", "return String(text).replace(/[^\\x20-\\x7e]/g, \"?\");", "return String(text);"],
    [layerFile, "colour order", "return \"rgba(\" + value.slice(3, 9) + value.slice(1, 3) + \")\";", "return \"rgba(\" + value.slice(1, 9) + \")\";"],
    [layerFile, "colour judged", "if (typeof value !== \"string\" || !/^#[0-9a-fA-F]{8}$/.test(value))", "if (false)"],
    [layerFile, "bind keys spaced", "return key.split(\"+\").join(\" + \");", "return key;"],
    [layerFile, "border size written", "tree.general.border_size = theme.hyprland.border.size;", "tree.general.border_size = 2;"],
    [layerFile, "shadow colour written", "tree.decoration = { shadow: { color: hyprColour(\"hyprland.shadow.color\", theme.hyprland.shadow.color) } };", "tree.decoration = { shadow: { color: hyprColour(\"hyprland.shadow.color\", theme.colours.border) } };"],
    [layerFile, "groupbar radius scaled", "var groupbar = boundedWhole(radius * scale, 0, 20);", "var groupbar = radius;"],
    [layerFile, "motion scale zero disables", "if (scale === 0 || preset === \"none\")", "if (preset === \"none\")"],
    [layerFile, "motion speed scales", "var speed = Math.max(0.01, animation.speed * scale);", "var speed = Math.max(0.01, animation.speed);"],
    [layerFile, "smooth motion preset", "    smooth: {\n        curves: {", "    silky: {\n        curves: {"],
    [layerFile, "appearance defaults", "var APPEARANCE_DEFAULTS = { borders: true, radius: true, motion: false, noGaps: false };", "var APPEARANCE_DEFAULTS = { borders: true, radius: true, motion: true, noGaps: false };"],
    [layerFile, "no window gaps defaults off", "var APPEARANCE_DEFAULTS = { borders: true, radius: true, motion: false, noGaps: false };", "var APPEARANCE_DEFAULTS = { borders: true, radius: true, motion: false, noGaps: true };"],
    [layerFile, "no window gaps is an appearance group", "var APPEARANCE_GROUPS = [\"borders\", \"radius\", \"motion\", \"noGaps\"];", "var APPEARANCE_GROUPS = [\"borders\", \"radius\", \"motion\"];"],
    [layerFile, "no window gaps is written while on", "if (switches.groups.noGaps.enabled) groups = groups.concat(noGapsLines());", "if (false) groups = groups.concat(noGapsLines());"],
    [layerFile, "zero gaps are a workspace rule", "\"hl.workspace_rule({ workspace = \\\"\\\", gaps_in = 0, gaps_out = 0 })\"", "\"hl.config({ general = { gaps_in = 0, gaps_out = 0 } })\""],
    [layerFile, "the gap rule matches every workspace", "workspace = \\\"\\\", gaps_in", "workspace = \\\"s[false]\\\", gaps_in"],
    [layerFile, "appearance owner sorted", "}).sort(function (a, b) { return a.id < b.id ? -1 : a.id > b.id ? 1 : 0; });", "});"],
    [layerFile, "floating TUI rules written", "[\"\"], tuiWindowLines(theme.tuiMargins), [\"\"], appWindowLines());", "[\"\"], appWindowLines());"],
    [layerFile, "floating TUI rules after appearance", "var lines = [\"\"].concat(groups, [\"\"], tuiWindowLines(theme.tuiMargins), [\"\"], appWindowLines());", "var lines = [\"\"].concat(tuiWindowLines(theme.tuiMargins), [\"\"], groups, [\"\"], appWindowLines());"],
    [layerFile, "floating TUI width keeps the gutter", "var across = luaNumber(2 * tuiMargin(margins, \"gutter\"));", "var across = luaNumber(0 * tuiMargin(margins, \"gutter\"));"],
    [layerFile, "floating TUI height keeps the bar", "var down = luaNumber(tuiMargin(margins, \"bar\") + 2 * tuiMargin(margins, \"gutter\"));", "var down = luaNumber(0 * tuiMargin(margins, \"bar\") + 2 * tuiMargin(margins, \"gutter\"));"],
    [layerFile, "floating TUI size is clamped", "size = { \" + width + \", \" + height + \" } })\";", "size = { \" + row.width + \", \" + row.height + \" } })\";"],
    [layerFile, "a negative TUI margin is refused", "if (typeof value !== \"number\" || !isFinite(value) || value < 0)", "if (typeof value !== \"number\" || !isFinite(value))"],
    [layerFile, "floating TUI class escapes each dot", ".join(\"\\\\\\\\.\")", ".join(\".\")"],
    [layerFile, "floating TUI class anchored", "return \"\\\"^\" + appId.split(\".\").join(\"\\\\\\\\.\") + \"$\\\"\";", "return \"\\\"\" + appId.split(\".\").join(\"\\\\\\\\.\") + \"\\\"\";"],
    [layerFile, "application window rule written", "tuiWindowLines(theme.tuiMargins), [\"\"], appWindowLines());", "tuiWindowLines(theme.tuiMargins));"],
    [layerFile, "application window rule after the TUIs", "tuiWindowLines(theme.tuiMargins), [\"\"], appWindowLines());", "appWindowLines(), [\"\"], tuiWindowLines(theme.tuiMargins));"],
    [layerFile, "session lock restore written", "keyPassthroughLines(), [\"\"], sessionLockLines());", "keyPassthroughLines());"],
    [layerFile, "user binds' recorder written", "[\"\"], userBindLines(), [\"\"], overlayCaptureLines(plan)", "[\"\"], overlayCaptureLines(plan)"],
    [layerFile, "user binds' recorder records the user's call sites", "binds.rows[#binds.rows + 1] = { file = ", "local _ = { file = "],
    [layerFile, "user binds' recorder calls hl.bind at the user's call site", "local bind = call(binds.bind, ...)", "local bind = binds.bind(...)"],
    [layerFile, "monitor rules rendered", "return [\"-- \" + section.id + \" \" + commentText(section.version) + \": monitor rules from its settings\"].concat(rendered.lines);", "return [];"],
    [layerFile, "refused monitor rules skipped", "if (section.monitors.kind === \"unfit\") {", "if (false) {"],
    [layerFile, "monitor rules have one owner", "var owners = sections.filter(function (section) { return section.monitors !== null && section.monitors !== undefined; })", "var owners = []"],
    [layerFile, "key pass-through written", "[\"\"], keyPassthroughLines(), [\"\"], sessionLockLines()", "[\"\"], sessionLockLines()"],
    [layerFile, "key pass-through before the lock restore", "[\"\"], overlayCaptureLines(plan), [\"\"], keyPassthroughLines(), [\"\"], sessionLockLines());", "[\"\"], overlayCaptureLines(plan), [\"\"], sessionLockLines(), [\"\"], keyPassthroughLines());"],
    [layerFile, "key pass-through cancels on Escape", "hl.dsp.submap(\\\"reset\\\"), { description = ", "hl.dsp.exec_cmd(\\\"true\\\"), { description = "],
    [layerFile, "key pass-through leaves only its submap", "        \"        if hl.get_current_submap() == passthrough.submap then hl.dispatch(hl.dsp.submap(\\\"reset\\\")) end\",", "        \"        hl.dispatch(hl.dsp.submap(\\\"reset\\\"))\","],
    [layerFile, "key pass-through enters only from a shell window", "if window == nil or window.class ~= passthrough.class then error(", "if window == nil then error("],
    [layerFile, "key pass-through records the entering window", "        \"        passthrough.window = window.address\",", ""],
    [layerFile, "key pass-through window-free enter forgets the window", "        \"        passthrough.window = nil\",", ""],
    [layerFile, "key pass-through times out", "        \"        passthrough.timer:set_enabled(name == passthrough.submap)\",", "        \"        passthrough.timer:set_enabled(false)\","],
    [layerFile, "key pass-through timer stops as it fires", "        \"        passthrough.timer:set_enabled(false)\",\n        \"        passthrough.\" + p.verbs.leave + \"()\",", "        \"        passthrough.\" + p.verbs.leave + \"()\","],
    [layerFile, "key pass-through leaves on its window's close", "if window ~= nil and window.address == passthrough.window then passthrough.\" + p.verbs.leave + \"() end", "local _ = window"],
    [layerFile, "key pass-through leaves when the layer runs", "        \"    passthrough.\" + p.verbs.leave + \"()\",\n        \"end\"", "        \"end\""],
    [layerFile, "key pass-through timeout", "timeoutMs: 10000,", "timeoutMs: 60000,"],
    [layerFile, "session lock restore allowed", "misc = { allow_session_lock_restore = true }", "misc = { allow_session_lock_restore = false }"],
    [layerFile, "application window class is the shell's app-id", "match = { class = \" + classLiteral(APP_WINDOW.appId) + \" }", "match = { class = \" + classLiteral(\"org.quickshell\") + \" }"],
    [shellFile, "shell.qml sets the shell's app-id", "//@ pragma AppId org.vgs.shell\n", ""],
    [shellFile, "shell.qml's app-id is the layer's", "//@ pragma AppId org.vgs.shell\n", "//@ pragma AppId org.vgs.other\n"],
    [shellFile, "the app-id pragma comes before the imports", "//@ pragma AppId org.vgs.shell\nimport QtQuick\n", "import QtQuick\n//@ pragma AppId org.vgs.shell\n"],
    [layerFile, "overlay capture section written", "userBindLines(), [\"\"], overlayCaptureLines(plan), [\"\"], keyPassthroughLines(),", "userBindLines(), [\"\"], keyPassthroughLines(),"],
    [layerFile, "capture binds enabled plugin shortcuts", "].concat(overlayCapturePluginBindLines(plan), [", "].concat([], ["],
    [layerFile, "capture wraps focus dispatchers", "hl.dsp.focus = function(opts)", "hl.dsp.focus = capture.focus --"],
    [layerFile, "capture wraps binds", "hl.bind = function(keys, dispatcher, opts)", "hl.bind = capture.bind --"],
    [layerFile, "capture tracks overlay layers", "layer.namespace == capture.namespace and layer.mapped", "false"],
    [layerFile, "capture resets only its submap", "elseif hl.get_current_submap() == capture.submap then", "else"],
    [layerFile, "capture listens for layer close", "hl.on(\\\"layer.closed\\\", function(layer)", "-- no layer close"],
    [layerFile, "capture listens for config reload", "hl.on(\\\"config.reloaded\\\", vgs_overlay_capture_update)", "-- no config reload"],
    [layerFile, "a stale view is read first", "if (state.queuedForce || state.stale)", "if (state.queuedForce)"],
    [layerFile, "a queued render reads first", "if (state.queuedForce || state.stale)", "if (state.stale)"],
    [layerFile, "a queued render forces its cycle", "forcing: state.forcing || state.queuedForce,", "forcing: state.forcing,"],
    [layerFile, "a failed text waits for a change", "text !== state.failedText", "true"],
    [layerFile, "a forced cycle writes whatever the bytes", "state.forcing || (text !== state.onDisk", "(text !== state.onDisk"],
    [layerFile, "a failed save leaves the view stale", "withChanges(state, { stale: true, failedText: state.pending })", "withChanges(state, { failedText: state.pending })"],
    [layerFile, "a failed mkdir keeps its text", "return idleDecision(withChanges(state, { failedText: state.pending }), event.failure, text, true);", "return idleDecision(state, event.failure, text, true);"],
    [layerFile, "held bytes skip the write", "if (state.pending === state.onDisk) return written(", "if (false) return written("],
    [layerFile, "a write clears the failed text", "{ onDisk: state.pending, failedText: null }", "{ onDisk: state.pending }"],
    [layerFile, "an unchanged layer probes once", "state.consent.phase === \"pending\" && text !== null && text === state.onDisk", "false"],
    [layerFile, "an unwired probe checks the decline marker", "return idleDecision(consentChanges(state, { phase: \"unwired\", queued: \"\", failure: \"\" }), state.failure, text);", "return idleDecision(consentChanges(state, { phase: \"asking\", queued: \"\", failure: \"\" }), state.failure, text);"],
    [layerFile, "a declined marker suppresses the question", "if (event.declined) return idleDecision(consentChanges(state, { phase: \"declined\", queued: \"\", failure: \"\" }), state.failure, text);", "if (false) return idleDecision(consentChanges(state, { phase: \"declined\", queued: \"\", failure: \"\" }), state.failure, text);"],
    [layerFile, "decline records the marker", "return state.phase === \"idle\" ? begin(consentChanges(state, { queued: \"decline\", failure: \"\" }), text) : { state: consentChanges(state, { queued: \"decline\", failure: \"\" }), action: \"none\" };", "return idleDecision(consentChanges(state, { phase: \"declined\", queued: \"\", failure: \"\" }), state.failure, text);"],
    [layerFile, "connect during a step waits", "return state.phase === \"idle\" ? begin(consentChanges(state, { queued: \"connect\", failure: \"\" }), text) : { state: consentChanges(state, { queued: \"connect\", failure: \"\" }), action: \"none\" };", "return begin(consentChanges(state, { queued: \"connect\", failure: \"\" }), text);"],
    [layerFile, "first consent answer keeps connect", "case \"decline\":\n        if (state.consent.phase !== \"asking\")\n            throw new Error(\"HyprlandLayer.step: event decline arrived in consent phase \" + state.consent.phase + \", want asking\");\n        if (state.consent.queued !== \"\") return { state: state, action: \"none\" };", "case \"decline\":\n        if (state.consent.phase !== \"asking\")\n            throw new Error(\"HyprlandLayer.step: event decline arrived in consent phase \" + state.consent.phase + \", want asking\");\n        if (false) return { state: state, action: \"none\" };"],
    [layerFile, "first consent answer keeps decline", "case \"connect\":\n        if (state.consent.phase !== \"asking\")\n            throw new Error(\"HyprlandLayer.step: event connect arrived in consent phase \" + state.consent.phase + \", want asking\");\n        if (state.consent.queued !== \"\") return { state: state, action: \"none\" };", "case \"connect\":\n        if (state.consent.phase !== \"asking\")\n            throw new Error(\"HyprlandLayer.step: event connect arrived in consent phase \" + state.consent.phase + \", want asking\");\n        if (false) return { state: state, action: \"none\" };"],
    [layerFile, "a queued connect runs after the step", "state.consent.phase === \"asking\" && state.consent.queued === \"connect\"", "false"],
    [layerFile, "wire failure keeps asking", "return idleDecision(consentChanges(state, { phase: \"asking\", queued: \"\", failure: event.failure }), event.failure, text);", "return idleDecision(consentChanges(state, { phase: \"settled\", queued: \"\", failure: \"\" }), event.failure, text);"],
    [layerFile, "wire reload failure keeps asking", "if (event.failure !== \"\")\n                return idleDecision(consentChanges(state, { phase: \"asking\", queued: \"\", failure: event.failure }), event.failure, text, true);\n            return idleDecision(consentChanges(state, { phase: \"wired\", queued: \"\", failure: \"\" }), \"\", text, true);", "if (event.failure !== \"\")\n                return idleDecision(consentChanges(state, { phase: \"wired\", queued: \"\", failure: event.failure }), event.failure, text, true);\n            return idleDecision(consentChanges(state, { phase: \"wired\", queued: \"\", failure: \"\" }), \"\", text, true);"],
    [layerFile, "probe failure is reported", "case \"probeDone\":\n        expectPhase(state, event, \"probing\");\n        if (event.failure !== undefined && event.failure !== \"\")\n            return idleDecision(consentChanges(state, { phase: \"settled\", queued: \"\", failure: \"\" }), event.failure, text);", "case \"probeDone\":\n        expectPhase(state, event, \"probing\");\n        if (event.failure !== undefined && event.failure !== \"\")\n            return idleDecision(consentChanges(state, { phase: \"settled\", queued: \"\", failure: \"\" }), state.failure, text);"],
    [layerFile, "a settled cycle stops forcing", "forcing: clearForcing ? false : state.forcing", "forcing: state.forcing"],
    [layerFile, "a render waits for the step", "return state.phase === \"idle\" ? begin(state, text) : { state: state, action: \"none\" };", "return begin(state, text);"],
    [layerFile, "a render request starts when idle", "return state.phase === \"idle\" ? begin(queued, text) : { state: queued, action: \"none\" };", "return { state: queued, action: \"none\" };"],
    [layerFile, "a result out of its phase is refused", "if (state.phase !== phase)", "if (false)"],
    [logicFile, "only a set option is listed", "if (row === undefined || !hasOwn(row, setting)) return;", "if (row === undefined) return;"],
    [logicFile, "an option value is judged by its schema entry", "var unfit = settingError(manifest.schema[setting], row[setting]);", "var unfit = \"\";"],
    [logicFile, "an option value is judged by its Lua literal", "var literal = HyprlandLayer.optionLiteral(HyprlandLayer.OPTIONS[path], row[setting]);", "var literal = { ok: true, lua: JSON.stringify(row[setting]) };"],
    [layerFile, "the options section is written", "if (section.options.length > 0) {", "if (false) {"],
    [layerFile, "the applied section is written", "].concat(appliedLines(applied, paths), lines);", "].concat(lines);"],
    [layerFile, "the values are applied after the configuration, not inline", "].concat(appliedLines(applied, paths), lines);", "].concat(applied, lines);"],
    [layerFile, "the applied section follows the header", "].concat(appliedLines(applied, paths), lines);", "].concat(lines, appliedLines(applied, paths));"],
    [layerFile, "the layer starts VGS when Hyprland starts", "        START_LINE,\n", ""],
    [layerFile, "the login start uses the start verb", 'hl.exec_cmd(\\"vgshell start\\")', 'hl.exec_cmd(\\"vgshell run\\")'],
    [layerFile, "the values sit inside the callback", "].concat(values.map(function (line) { return \"        \" + line; }), [", "].concat(["],
    [layerFile, "a group that is on is applied", "if (switches.groups[group].enabled) applied = applied.concat(groupLines[group]());", "if (switches.groups[group].enabled) groups = groups.concat(groupLines[group](), [\"\"]);"],
    [layerFile, "an options line is applied", "if (optionText.applied.length > 0) applied = applied.concat([heading], optionText.applied);", "if (optionText.applied.length > 0) lines = lines.concat([\"\", heading], optionText.applied);"],
    [layerFile, "a per-device option is not read as a user value", "var paths = options.written.filter(function (option) { return OPTIONS[option.path].device === undefined; })", "var paths = options.written.filter(function (option) { return true; })"],
    [layerFile, "the user's value is read before the layer's", ",\n        \"        for path in pairs(options.start) do theirs[path] = hl.get_config(path) end\"\n    ].concat(", "\n    ].concat("],
    [layerFile, "a value the user's configuration left alone is no user value", "if theirs[path] ~= start and theirs[path] ~= hl.get_config(path) then", "if theirs[path] ~= hl.get_config(path) then"],
    [layerFile, "the options section precedes the binds", "    plan.sections.forEach(function (row) {\n        var section = row.section;\n        if (section.options.length > 0) {", "    plan.sections.slice().reverse().forEach(function (row) {\n        var section = row.section;\n        if (section.options.length > 0) {"],
    [layerFile, "options keep the manifest's order", "return Object.keys(tree).map(function (key) {", "return Object.keys(tree).sort().map(function (key) {"],
    [layerFile, "the Lua name, not the hyphenated option name", "\"input.touchpad.tap_to_click\": { type: \"bool\" },", "\"input.touchpad.tap-to-click\": { type: \"bool\" },"],
    [layerFile, "a path outside the table is refused", "if (!Object.prototype.hasOwnProperty.call(OPTIONS, option.path))\n            throw", "if (false)\n            throw"],
    [layerFile, "the first plugin by id keeps a path", "if (held[option.path] !== undefined) {", "if (false) {"],
    [layerFile, "an unfit option is reported", "case \"unfit\":\n            refuse(option.error);", "case \"unfit\":\n            void (option.error);"],
    [layerFile, "an int is whole", "if (typeof value === \"number\" && Number.isInteger(value)) return { ok: true, lua: String(value) };", "if (typeof value === \"number\") return { ok: true, lua: String(value) };"],
    [layerFile, "a string keeps to its characters", "return OPTION_STRING.test(value) ?", "return true ?"],
    [layerFile, "the touchpad option is per device", "if (row.device === \"touchpad\") {", "if (false) {"],
    [layerFile, "a touchpad name is judged", "if (DEVICE_NAME.test(touchpad))", "if (true)"],
    [layerFile, "the written options are listed", "out.written.push({ id: section.id, setting: option.setting, path: option.path, value: option.value });", ""],
    [layerFile, "the written binds are listed", "            out.push(entry.global);\n", ""],
    [layerFile, "a set touchpad option asks for the touchpads", "return OPTIONS[option.path].device === \"touchpad\"; });", "return false; });"],
    [layerFile, "the pads section is written", "lines = lines.concat([\"\"], padLines(section, padMotion(theme)));", ""],
    [layerFile, "the first plugin by id defines the pads", "if (padsOwner !== null) {", "if (false) {"],
    [layerFile, "a pads-only section is written", " && !Array.isArray(section.pads)) return;", ") return;"],
    [layerFile, "a pad's window maps into its workspace hidden", " silent\\\", tile = true", "\\\", tile = true"],
    [layerFile, "a pad's window tiles", "tile = true, no_initial_focus", "tile = false, no_initial_focus"],
    [layerFile, "a pad's window takes no focus as it maps", "no_initial_focus = true", "no_initial_focus = false"],
    [layerFile, "a pad's class is anchored and escaped", "match = { class = \" + classLiteral(pad[\"class\"]) + \" }", "match = { class = \\\"\" + pad[\"class\"] + \"\\\" }"],
    [layerFile, "a pad's toggle answers a function", "        \"        return function()\",", "        \"        do\","],
    [layerFile, "a pad without a window is refused", "            if ws == nil or ws.windows == 0 then error(", "            if ws == nil then error("],
    [layerFile, "a hidden pad moves to its screen first", "then hl.dispatch(hl.dsp.workspace.move({ workspace = id, monitor = mon.name })) end", "then end"],
    [layerFile, "a shown pad hides and gives the focus back", "if visible ~= nil then return hide(name, visible.monitor, true) end", "if visible ~= nil then return hide(name, visible.monitor, false) end"],
    [layerFile, "a pad hides when the focus leaves it", "            if visible ~= nil and current ~= pads.prefix .. name then hide(name, visible.monitor, false) end", "            if false then hide(name, visible.monitor, false) end"],
    [layerFile, "a layout change fits the shown pads", "        \"    hl.on(\\\"monitor.layout_changed\\\", refit)\",", ""],
    [layerFile, "the work area leaves the reserved space", "width = math.floor(width / mon.scale - reserved.left - reserved.right)", "width = math.floor(width / mon.scale)"],
    [layerFile, "the work area is logical", "width = math.floor(width / mon.scale - reserved.left", "width = math.floor(width - reserved.left"],
    [layerFile, "a quarter turn swaps the work area", "        \"        if mon.transform % 2 == 1 then width, height = height, width end\",", ""],
    [layerFile, "an anchored side keeps its margin", "if anchor == \\\"start\\\" then return math.min(margin, free) end", "if anchor == \\\"start\\\" then return 0 end"],
    [layerFile, "a pad leaves toward its entry side", "\"slide \\\" .. opposite[pad.entry]", "\"slide \\\" .. pad.entry"],
    [layerFile, "a still theme moves no pad", "if (theme.motionScale === 0 || preset === \"none\") return null;", "if (preset === \"none\") return null;"],
    [layerFile, "a pad moves on the preset's workspace leaf", "return animation.leaf === \"workspaces\"; })[0];", "return animation.leaf === \"windows\"; })[0];"],
    [layerFile, "a pad's speed follows the motion scale", "speed: Math.max(0.01, leaf.speed * theme.motionScale)", "speed: Math.max(0.01, leaf.speed)"],
    [layerFile, "the focus a pad gives back is never its own window", "active.workspace ~= nil and active.workspace.name ~= id and active.address", "active.address"],
    [layerFile, "a hidden pad gives the focus back only to a shown window", "before.workspace ~= nil and before.workspace.visible then", "true then"],
    [layerFile, "the pads' sweep is written", "    lines = lines.concat([\"\"], padSweepLines());\n", ""],
    [layerFile, "the sweep moves only a pad the table does not hold", "if name ~= nil and pads[name] == nil and active ~= nil then", "if name ~= nil and active ~= nil then"],
    [layerFile, "the sweep reads the pads' workspaces", "string.match(window.workspace.name, \\\"^\" + PADS.workspace", "string.match(window.workspace.name, \\\"^special:\" + PADS.workspace"],
    [layerFile, "a skipped plugin's pads are reported", "padConflicts.push({ id: section.id, heldBy: padsOwner });", ""],
    [layerFile, "a refusal names its key", "error(\\\"vgs-pad=no-window name=\\\" .. name)", "error(\\\"vgs-pad: holds no window \\\" .. name)"],
    [layerFile, "an unreadable file is reported", "event.notFound ? state.failure : \"read=failed \" + event.detail, text", "state.failure, text"]
];

// A copy sits at its file's own place in a temporary tree, beside the icon
// set, the package-manager table and the layer PluginLogic.js imports.
fs.mkdirSync(path.join(__dirname, "..", "tmp"), { recursive: true });
const temp = fs.mkdtempSync(path.join(__dirname, "..", "tmp", "hyprland-layer-control-"));
try {
    fs.mkdirSync(path.join(temp, "shell", "Core"), { recursive: true });
    fs.mkdirSync(path.join(temp, "shell", "Commons"), { recursive: true });
    fs.mkdirSync(path.join(temp, "shell", "Ui", "icons"), { recursive: true });
    fs.symlinkSync(path.join(__dirname, "..", "shell", "Commons", "SettingValues.js"), path.join(temp, "shell", "Commons", "SettingValues.js"));
    fs.symlinkSync(path.join(__dirname, "..", "shell", "Ui", "icons", "Lucide.js"), path.join(temp, "shell", "Ui", "icons", "Lucide.js"));
    fs.symlinkSync(path.join(__dirname, "..", "shell", "Core", "PackageManagers.js"), path.join(temp, "shell", "Core", "PackageManagers.js"));
    fs.symlinkSync(layerFile, path.join(temp, "shell", "Core", "HyprlandLayer.js"));
    fs.symlinkSync(path.join(__dirname, "..", "shell", "Core", "MonitorLogic.js"), path.join(temp, "shell", "Core", "MonitorLogic.js"));
    fs.symlinkSync(path.join(__dirname, "..", "shell", "Core", "Pads.js"), path.join(temp, "shell", "Core", "Pads.js"));
    CONTROLS.forEach(([file, label, needle, replacement], index) => {
        const source = fs.readFileSync(file, "utf8");
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once in ${path.basename(file)}`);
        const mutant = path.join(temp, "shell", "Core", `${index}-${path.basename(file)}`);
        fs.writeFileSync(mutant, source.replace(needle, () => replacement));
        // Loaded outside the try, so a copy that does not evaluate fails the
        // suite instead of passing for a control.
        const logic = load(file === logicFile ? mutant : logicFile);
        const layer = load(file === layerFile ? mutant : layerFile);
        let failed = false;
        try {
            verify(logic, layer, file === shellFile ? fs.readFileSync(mutant, "utf8") : shellText);
        } catch (e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the suite passed on ${path.basename(file)} without that rule`);
    });
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
console.log(`test-hyprland-layer: ok keys=${KEYS.length} manifests=${MANIFESTS.length} config=${CONFIG_KEYS.length} steps=${SEQUENCES.length} controls=${CONTROLS.length}`);
