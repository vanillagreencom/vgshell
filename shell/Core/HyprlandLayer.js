.pragma library

// The Hyprland layer: the one Lua file the shell writes, which hyprland.lua
// runs from the line `vgshell hypr wire` keeps first in it, so the user's
// own unbinds and rule switches after that line act on what it made. Its
// values are applied once the whole configuration has loaded
// (appliedLines). Pure: no QML object, no I/O, so
// scripts/test-hyprland-layer.js runs it under node. HyprlandLayer.qml is
// its one caller, and PluginLogic.hyprlandSection makes every plugin section
// it renders.

// The command that writes the file again, which its header names.
var REGENERATE = "vgshell hypr render";

var CONSENT = {
    title: "Let VGS manage its Hyprland settings?",
    message: "One line at the top of hyprland.lua loads the keys, border colours and blur rules VGS generates. VGS changes no other line of that file.",
    disclosure: "vgshell hypr wire",
    connect: "Connect",
    decline: "Not now"
};

function consentView(consent) {
    if (consent.phase !== "asking") return null;
    return {
        title: CONSENT.title,
        message: CONSENT.message,
        disclosure: CONSENT.disclosure,
        actions: { connect: CONSENT.connect, decline: CONSENT.decline },
        failure: consent.failure,
        busy: consent.queued !== ""
    };
}

// The border colours: [Hyprland table path, theme colour name]. `colours`
// holds each name as Theme publishes a colour, `#aarrggbb`.
var BORDERS = [
    [["general", "col", "active_border"], "accent"],
    [["general", "col", "inactive_border"], "border"],
    [["general", "col", "nogroup_border_active"], "accent"],
    [["general", "col", "nogroup_border"], "borderSubtle"],
    [["group", "col", "border_active"], "accent"],
    [["group", "col", "border_inactive"], "border"],
    [["group", "col", "border_locked_active"], "warning"],
    [["group", "col", "border_locked_inactive"], "border"],
    [["group", "groupbar", "col", "active"], "accent"],
    [["group", "groupbar", "col", "inactive"], "surfaceRaised"],
    [["group", "groupbar", "col", "locked_active"], "warning"],
    [["group", "groupbar", "col", "locked_inactive"], "surfaceRaised"],
    [["group", "groupbar", "text_color"], "onAccent"],
    [["group", "groupbar", "text_color_inactive"], "text"],
    [["group", "groupbar", "text_color_locked_active"], "onWarning"],
    [["group", "groupbar", "text_color_locked_inactive"], "text"]
];

// The floating TUI's size classes, by name, in the order the layer writes
// them. A floating TUI's terminal opens with its class's app-id, which
// bin/vgshell-tui reads from here under node, and the layer writes one window
// rule per class, named `rule`, that floats the window, centres it and
// gives it its preferred width by height, clamped to its output
// (tuiWindowLines). Only the core writes window rules: no plugin sets a
// size or a class pattern.
var TUI_WINDOWS = {
    "default": { appId: "org.vgs.tui", rule: "vgs:tui", width: 875, height: 600 },
    "wide": { appId: "org.vgs.tui.wide", rule: "vgs:tui-wide", width: 1200, height: 720 },
    "tall": { appId: "org.vgs.tui.tall", rule: "vgs:tui-tall", width: 875, height: 900 }
};

// The shell's application windows, the summon host's `window` kind. Every
// toplevel the shell maps carries the process's one app-id, which
// shell.qml's `//@ pragma AppId` line sets and Quickshell 0.3.1 gives no
// window its own, so the class is the shell's and the title names the
// window. The layer writes one window rule, named `rule`, that floats the
// shell's windows and centres them; each keeps the size it asks for.
var APP_WINDOW = { appId: "org.vgs.shell", rule: "vgs:window" };

// Every shell window class comes from these existing declarations.
function inputProtectedClass(value) {
    return value === APP_WINDOW.appId || Object.keys(TUI_WINDOWS).some(function (size) { return value === TUI_WINDOWS[size].appId; });
}

// The Hyprland options a manifest's `hyprland.options` may map a setting
// to: the input keys the Mouse and Keyboard settings set, each by its Lua
// path, which `hyprctl getoption` reads too, with the type and range
// Hyprland v0.56.2 declares for it (src/config/values/ConfigValues.cpp). A
// string row with `choices` takes those values alone. The path is the Lua
// table key, `tap_to_click`, not the hyphenated option name: Hyprland's Lua
// config refuses `["tap-to-click"]` as an unknown key
// (docs/architecture/runtime-hyprland.md). The `device` row is no
// option: Hyprland keeps `enabled` per device, so the layer writes it as one
// `hl.device` per touchpad Hyprland lists.
var OPTIONS = {
    "input.kb_layout": { type: "string" },
    "input.kb_variant": { type: "string" },
    "input.kb_options": { type: "string" },
    "input.repeat_rate": { type: "int", min: 0, max: 200 },
    "input.repeat_delay": { type: "int", min: 0, max: 2000 },
    "input.numlock_by_default": { type: "bool" },
    "input.sensitivity": { type: "float", min: -1, max: 1 },
    "input.accel_profile": { type: "string", choices: ["adaptive", "flat"] },
    "input.natural_scroll": { type: "bool" },
    "input.left_handed": { type: "bool" },
    "input.scroll_factor": { type: "float", min: 0, max: 2 },
    "input.touchpad.tap_to_click": { type: "bool" },
    "input.touchpad.natural_scroll": { type: "bool" },
    "input.touchpad.disable_while_typing": { type: "bool" },
    "input.touchpad.clickfinger_behavior": { type: "bool" },
    "input.touchpad.scroll_factor": { type: "float", min: 0, max: 2 },
    "device.touchpad.enabled": { type: "bool", device: "touchpad" }
};

// The characters a string option's value may hold: those of XKB layout,
// variant and option names, which the user's configuration supplies. A
// quote, a backslash or a line break would end the Lua string.
var OPTION_STRING = /^[A-Za-z0-9_.,:()+-]*$/;

// A touchpad name the layer may write into `hl.device`: printable ASCII but
// the quote and the backslash. Hyprland names a device from its descriptor,
// lower case with spaces and commas as dashes, and keeps every other byte.
var DEVICE_NAME = /^[\x20\x21\x23-\x5b\x5d-\x7e]+$/;

// The values the layer applies once the whole configuration has loaded:
// `table` on `hl` holds `start`, each written option's value as the layer
// loads, before any line of the user's, and `user`, the value the user's
// configuration gave an option, where it changed that option to a value
// other than the one the layer then set. `verb` answers `user` as one
// line, `key`, `=` and a JSON list of { path, value } sorted by path, which
// HyprlandState.js asks for and judges.
var USER_VALUES = { table: "__vgs_options", verb: "report", key: "vgs-user-values" };

var APPEARANCE_GROUPS = ["borders", "radius", "motion", "noGaps"];
// The groups whose values a user's own line would replace: they are applied
// after the configuration. `noGaps` is a workspace rule, which holds where
// it stands.
var APPLIED_GROUPS = ["borders", "radius", "motion"];
var APPEARANCE_DEFAULTS = { borders: true, radius: true, motion: false, noGaps: false };

// Hyprland animation presets VGS owns. `smooth` sets window, layer and fade
// timings and gives workspaces a leaf too, so the preset is complete for
// this layer's scope.
var MOTION = {
    none: { curves: {}, animations: [] },
    snappy: {
        curves: {
            vgsSnappy: [[0.15, 0], [0.1, 1]],
            vgsLinear: [[0, 0], [1, 1]]
        },
        animations: [
            { leaf: "windows", speed: 1.8, bezier: "vgsSnappy" },
            { leaf: "windowsIn", speed: 2.0, bezier: "vgsSnappy", style: "popin 85%" },
            { leaf: "windowsOut", speed: 1.0, bezier: "vgsLinear", style: "popin 85%" },
            { leaf: "layers", speed: 1.8, bezier: "vgsSnappy" },
            { leaf: "layersIn", speed: 2.0, bezier: "vgsSnappy", style: "fade" },
            { leaf: "layersOut", speed: 1.0, bezier: "vgsLinear", style: "fade" },
            { leaf: "fadeIn", speed: 1.0, bezier: "vgsSnappy" },
            { leaf: "fadeOut", speed: 0.8, bezier: "vgsLinear" },
            { leaf: "fade", speed: 1.5, bezier: "vgsSnappy" },
            { leaf: "fadeLayersIn", speed: 1.0, bezier: "vgsSnappy" },
            { leaf: "fadeLayersOut", speed: 0.8, bezier: "vgsLinear" },
            { leaf: "workspaces", speed: 1.6, bezier: "vgsSnappy", style: "slide" }
        ]
    },
    smooth: {
        curves: {
            vgsEaseOutQuint: [[0.23, 1], [0.32, 1]],
            vgsAlmostLinear: [[0.5, 0.5], [0.75, 1.0]],
            vgsQuick: [[0.15, 0], [0.1, 1]],
            vgsLinear: [[0, 0], [1, 1]]
        },
        animations: [
            { leaf: "windows", speed: 3.79, bezier: "vgsEaseOutQuint" },
            { leaf: "windowsIn", speed: 4.1, bezier: "vgsEaseOutQuint", style: "popin 87%" },
            { leaf: "windowsOut", speed: 1.49, bezier: "vgsLinear", style: "popin 87%" },
            { leaf: "layers", speed: 3.81, bezier: "vgsEaseOutQuint" },
            { leaf: "layersIn", speed: 4, bezier: "vgsEaseOutQuint", style: "fade" },
            { leaf: "layersOut", speed: 1.5, bezier: "vgsLinear", style: "fade" },
            { leaf: "fadeIn", speed: 1.73, bezier: "vgsAlmostLinear" },
            { leaf: "fadeOut", speed: 1.46, bezier: "vgsAlmostLinear" },
            { leaf: "fade", speed: 3.03, bezier: "vgsQuick" },
            { leaf: "fadeLayersIn", speed: 1.79, bezier: "vgsAlmostLinear" },
            { leaf: "fadeLayersOut", speed: 1.39, bezier: "vgsAlmostLinear" },
            { leaf: "workspaces", speed: 3.5, bezier: "vgsEaseOutQuint", style: "slide" }
        ]
    }
};

// Full-screen overlay keyboard capture. The generated layer loads first in
// hyprland.lua, so it can learn focus dispatchers the user builds after it.
var OVERLAY_CAPTURE = {
    submap: "vgs:capture",
    namespace: "vgs:overlay",
    appid: "vgs",
    shortcuts: { left: "overlay-left", right: "overlay-right", up: "overlay-up", down: "overlay-down" }
};

// The key capture pass-through: while the Settings key field captures a
// combo, the shell asks Hyprland through Dispatch.js to enter `submap`,
// whose one bind is `cancel`, so every other key, a combo a default-map bind
// holds included, reaches the focused shell window. Hyprland leaves it on
// its own on `cancel`, when the window that entered it closes, a killed
// shell's included, after `timeoutMs` and whenever the layer runs again; the
// shell leaves it on commit and teardown. `timeoutMs` bounds how long a
// wedged shell holds every bind: long enough to find and press a chord.
// `table` is the name of the Lua table on `hl` that holds the submap's
// state and its two functions, named by `verbs`, which Dispatch.js calls.
var KEY_PASSTHROUGH = {
    submap: "vgs:passthrough",
    cancel: "Escape",
    description: "vgs:passthrough-cancel",
    timeoutMs: 10000,
    table: "__vgs_key_passthrough",
    verbs: { enter: "enter", leave: "leave" }
};

// The pads a plugin's `hyprland.pads` setting lists (Pads.js): each pad's
// window lives in the special workspace `workspace` and its name, tiled
// and sized by that workspace's gaps, and `table` on `hl` holds `verb`, the
// function Dispatch.padRequest calls with a pad's name and a screen. The
// pads move in and out on `curve`, a copy of the theme's motion preset's
// workspace curve.
// The toggle's refusals are `vgs-pad=<answer>` with ANSWERS' keys:
// `no-pad` for a name the table does not hold, `no-window` for a pad whose
// workspace holds no window, `no-screen` for a screen Hyprland does not
// list. A plugin reads Hyprland's answer by this key.
var PADS = {
    table: "__vgs_pads",
    verb: "toggle",
    workspace: "special:vgs-pad-",
    curve: "vgsPad",
    answers: ["no-pad", "no-window", "no-screen"]
};

function overlayCaptureDirections() {
    return ["left", "right", "up", "down"];
}

function overlayCaptureGlobal(direction) {
    var name = OVERLAY_CAPTURE.shortcuts[direction];
    if (name === undefined) throw new Error("HyprlandLayer: overlay direction " + JSON.stringify(direction) + " unknown");
    return OVERLAY_CAPTURE.appid + ":" + name;
}

// A Theme colour, `#aarrggbb`, as Hyprland reads one: `rgba(rrggbbaa)`.
function hyprColour(name, value) {
    if (typeof value !== "string" || !/^#[0-9a-fA-F]{8}$/.test(value))
        throw new Error("HyprlandLayer: colour " + name + " must be #aarrggbb, got " + JSON.stringify(value));
    return "rgba(" + value.slice(3, 9) + value.slice(1, 3) + ")";
}

// TEXT for one comment line. Plugin and theme metadata reach a comment, so
// every character that could end the comment or escape the file's text is
// replaced: a newline there would put plugin text into the compositor's Lua.
function commentText(text) {
    return String(text).replace(/[^\x20-\x7e]/g, "?");
}

// The key `SUPER+SPACE` as a Hyprland bind names it, `SUPER + SPACE`.
function bindKeys(key) {
    return key.split("+").join(" + ");
}

function luaNumber(value) {
    if (typeof value !== "number" || !isFinite(value))
        throw new Error("HyprlandLayer: number must be finite, got " + JSON.stringify(value));
    var rounded = Math.round(value * 100) / 100;
    return Math.abs(rounded - Math.round(rounded)) < 0.000001 ? String(Math.round(rounded)) : String(rounded);
}

function boundedWhole(value, min, max) {
    return Math.max(min, Math.min(max, Math.round(value)));
}

// The nested table TREE, built from BORDERS, as Lua lines at DEPTH.
function tableLines(tree, depth) {
    var pad = new Array(depth + 1).join("    ");
    var lines = [];
    Object.keys(tree).forEach(function (name) {
        if (typeof tree[name] === "string") {
            lines.push(pad + name + " = \"" + tree[name] + "\",");
        } else if (typeof tree[name] === "number") {
            lines.push(pad + name + " = " + luaNumber(tree[name]) + ",");
        } else if (typeof tree[name] === "boolean") {
            lines.push(pad + name + " = " + (tree[name] ? "true" : "false") + ",");
        } else {
            lines.push(pad + name + " = {");
            lines = lines.concat(tableLines(tree[name], depth + 1));
            lines.push(pad + "},");
        }
    });
    return lines;
}

function borderLines(theme, themeName) {
    var tree = {};
    BORDERS.forEach(function (row) {
        var node = tree;
        var path = row[0];
        for (var i = 0; i < path.length - 1; i++) {
            if (node[path[i]] === undefined) node[path[i]] = {};
            node = node[path[i]];
        }
        node[path[path.length - 1]] = hyprColour(row[1], theme.colours[row[1]]);
    });
    tree.general.border_size = theme.hyprland.border.size;
    tree.decoration = { shadow: { color: hyprColour("hyprland.shadow.color", theme.hyprland.shadow.color) } };
    return ["-- Theme " + commentText(themeName) + ": window, group and group bar borders.", "hl.config({"]
        .concat(tableLines(tree, 1), ["})"]);
}

function radiusLines(theme, highestScale) {
    var radius = theme.hyprland.window.radius;
    var scale = typeof highestScale === "number" && isFinite(highestScale) && highestScale > 0 ? highestScale : 1;
    var groupbar = boundedWhole(radius * scale, 0, 20);
    return [
        "-- Theme appearance: corner radius.",
        "-- Group tabs use the window radius times the highest monitor scale (" + luaNumber(scale) + "), bounded to 20.",
        "hl.config({",
        "    decoration = {",
        "        rounding = " + luaNumber(radius) + ",",
        "        rounding_power = " + luaNumber(theme.hyprland.window.roundingPower) + ",",
        "    },",
        "    group = {",
        "        groupbar = {",
        "            rounding = " + luaNumber(groupbar) + ",",
        "            gradient_rounding = " + luaNumber(groupbar) + ",",
        "        },",
        "    },",
        "})"
    ];
}

function motionLines(theme) {
    var preset = theme.hyprland.motion.preset;
    var scale = theme.motionScale;
    if (scale === 0 || preset === "none")
        return ["-- Theme appearance: window animations.", "hl.config({ animations = { enabled = false } })"];
    var row = MOTION[preset];
    if (row === undefined)
        throw new Error("HyprlandLayer: motion preset " + JSON.stringify(preset) + " is not known");
    var lines = ["-- Theme appearance: window animations.", "hl.config({ animations = { enabled = true } })"];
    Object.keys(row.curves).forEach(function (name) {
        var points = row.curves[name];
        lines.push("hl.curve(\"" + name + "\", { type = \"bezier\", points = { { " + luaNumber(points[0][0]) + ", " + luaNumber(points[0][1]) + " }, { " + luaNumber(points[1][0]) + ", " + luaNumber(points[1][1]) + " } } })");
    });
    row.animations.forEach(function (animation) {
        var speed = Math.max(0.01, animation.speed * scale);
        var fields = ["leaf = \"" + animation.leaf + "\"", "enabled = true", "speed = " + luaNumber(speed), "bezier = \"" + animation.bezier + "\""];
        if (animation.style !== undefined) fields.push("style = \"" + animation.style + "\"");
        lines.push("hl.animation({ " + fields.join(", ") + " })");
    });
    return lines;
}

// No window gaps: zero inner and outer gaps on every workspace. Workspace
// rules, not `general` gaps, so a user's own `general.gaps_*` after the
// loading line leaves the switch in force; the empty selector matches every
// workspace, special ones included (runtime-hyprland.md). Off, the layer
// writes no gaps and the user's or Hyprland's own apply, whatever the theme.
function noGapsLines() {
    return [
        "-- Window gaps: none on every workspace.",
        "hl.workspace_rule({ workspace = \"\", gaps_in = 0, gaps_out = 0 })"
    ];
}

function appearanceOwner(sections) {
    var owners = sections.filter(function (section) {
        return section.appearance !== undefined && Object.keys(section.appearance).length > 0;
    }).sort(function (a, b) { return a.id < b.id ? -1 : a.id > b.id ? 1 : 0; });
    return { owner: owners.length === 0 ? null : owners[0], conflicts: owners.slice(1).map(function (section) { return { id: section.id, heldBy: owners[0].id }; }) };
}

function groupSwitches(sections) {
    var resolved = appearanceOwner(sections);
    var groups = {};
    APPEARANCE_GROUPS.forEach(function (group) {
        if (resolved.owner !== null && resolved.owner.appearance[group] !== undefined)
            groups[group] = resolved.owner.appearance[group];
        else
            groups[group] = { setting: "core default", enabled: APPEARANCE_DEFAULTS[group] };
    });
    return { groups: groups, owner: resolved.owner, conflicts: resolved.conflicts };
}

function disabledGroupLine(group, setting) {
    return "-- Theme appearance: " + group + " left to the user's config; " + commentText(setting) + " is off.";
}

// The Lua string literal of the class pattern that matches APP_ID alone: the
// pattern is anchored and each dot is escaped for the regex, then that
// backslash for Lua, so the rule and the app-id cannot differ.
function classLiteral(appId) {
    return "\"^" + appId.split(".").join("\\\\.") + "$\"";
}

// One margin of MARGINS, a length in logical pixels, refused unless it is a
// finite number of at least 0.
function tuiMargin(margins, name) {
    var value = margins === undefined || margins === null ? undefined : margins[name];
    if (typeof value !== "number" || !isFinite(value) || value < 0)
        throw new Error("HyprlandLayer: tuiMargins." + name + " must be a finite number of at least 0, got " + JSON.stringify(value));
    return value;
}

// MARGINS is { bar, gutter }: Theme.bar.height and size.window.gutter. Each
// size is two Hyprland expressions, which v0.56.2 evaluates against the
// monitor's logical size when the window maps: the preferred size, never
// wider than the output less `gutter` a side, nor taller than the output
// less the bar and `gutter` a side. Hyprland offers no reserved-area
// variable, so the bar's height is taken whether or not a bar is up, and a
// screen with no bar leaves a clamped TUI that many pixels short.
function tuiWindowLines(margins) {
    var across = luaNumber(2 * tuiMargin(margins, "gutter"));
    var down = luaNumber(tuiMargin(margins, "bar") + 2 * tuiMargin(margins, "gutter"));
    return ["-- Floating TUIs: each size class's app-id floats, centred, at its size, clamped to its output."].concat(Object.keys(TUI_WINDOWS).map(function (size) {
        var row = TUI_WINDOWS[size];
        var width = "\"min(" + luaNumber(row.width) + ",monitor_w-" + across + ")\"";
        var height = "\"min(" + luaNumber(row.height) + ",monitor_h-" + down + ")\"";
        return "hl.window_rule({ name = \"" + row.rule + "\", match = { class = " + classLiteral(row.appId) + " }, float = true, center = true, size = { " + width + ", " + height + " } })";
    }));
}

function appWindowLines() {
    return [
        "-- Application windows: the shell's windows float, centred, at the size they ask.",
        "hl.window_rule({ name = \"" + APP_WINDOW.rule + "\", match = { class = " + classLiteral(APP_WINDOW.appId) + " }, float = true, center = true })"
    ];
}


// One conflict judge for default-map binds, overlay capture and shortcut
// key reads. Each declared shortcut has its normalized key or null.
function resolveBinds(sections) {
    var held = Object.create(null);
    var keys = Object.create(null);
    var conflicts = [];
    var rows = sections.slice().sort(function (a, b) { return a.id < b.id ? -1 : a.id > b.id ? 1 : 0; }).map(function (section) {
        keys[section.id] = Object.create(null);
        var bindRows = section.binds.map(function (bind) {
            var global = section.id + ":" + bind.shortcut;
            keys[section.id][bind.shortcut] = null;
            if (bind.key === null) return { kind: "unbound", bind: bind, global: global };
            if (held[bind.key] !== undefined) {
                conflicts.push({ id: section.id, shortcut: bind.shortcut, key: bind.key, heldBy: held[bind.key] });
                return { kind: "skipped", bind: bind, global: global, heldBy: held[bind.key] };
            }
            held[bind.key] = section.id;
            keys[section.id][bind.shortcut] = bind.key;
            return { kind: "bound", bind: bind, global: global };
        });
        return { section: section, binds: bindRows };
    });
    return { sections: rows, keys: keys, conflicts: conflicts };
}

// A dot is outside the public registration-name grammar, so the companion
// cannot collide with a shortcut a plugin registers.
function releaseShortcutName(name) {
    return name + ".release";
}

// The hold companion's global of a bound ENTRY, or null for a bind
// without `hold`.
function releaseGlobal(entry) {
    return entry.bind.hold === true ? releaseShortcutName(entry.global) : null;
}

function shortcutBindLines(entry) {
    var global = entry.global;
    var lines = ["hl.bind(\"" + bindKeys(entry.bind.key) + "\", hl.dsp.global(\"" + global + "\"), { description = \"" + global + "\" })"];
    var release = releaseGlobal(entry);
    if (release !== null) {
        lines.push("hl.bind(\"" + bindKeys(entry.bind.key) + "\", hl.dsp.global(\"" + release + "\"), { description = \"" + release + "\", release = true, non_consuming = true, transparent = true, ignore_mods = true })");
    }
    return lines;
}

function overlayCapturePluginBindLines(plan) {
    var lines = [];
    plan.sections.forEach(function (row) {
        row.binds.forEach(function (entry) {
            if (entry.kind === "bound")
                lines = lines.concat(shortcutBindLines(entry).map(function (line) { return "    " + line; }));
        });
    });
    return lines;
}

function overlayCaptureLines(plan) {
    var submap = OVERLAY_CAPTURE.submap;
    var namespace = OVERLAY_CAPTURE.namespace;
    var globals = {};
    overlayCaptureDirections().forEach(function (direction) { globals[direction] = overlayCaptureGlobal(direction); });
    return [
        "-- Overlay keyboard capture: full-screen vgs overlays own keys through a submap.",
        "do",
        "    local capture = hl.__vgs_overlay_capture or { directions = setmetatable({}, { __mode = \"k\" }) }",
        "    hl.__vgs_overlay_capture = capture",
        "    capture.submap = \"" + submap + "\"",
        "    capture.namespace = \"" + namespace + "\"",
        "    capture.globals = { left = \"" + globals.left + "\", right = \"" + globals.right + "\", up = \"" + globals.up + "\", down = \"" + globals.down + "\", l = \"" + globals.left + "\", r = \"" + globals.right + "\", u = \"" + globals.up + "\", d = \"" + globals.down + "\" }",
        "    hl.define_submap(capture.submap, function()"
    ].concat(overlayCapturePluginBindLines(plan), [
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
    ]);
}

// The session lock: a new lock client may take over a lock whose client
// died, so a shell started after a crash while locked locks the session
// again. Hyprland keeps the session
// locked either way; without it only a TTY clears the dead lock.
function sessionLockLines() {
    return [
        "-- Session lock: a restarted shell takes over a lock whose client died.",
        "hl.config({ misc = { allow_session_lock_restore = true } })"
    ];
}

// The key capture pass-through's submap, KEY_PASSTHROUGH. Its two functions
// on `hl.<table>` are what Dispatch.js asks for: `enter`
// refuses unless a shell window has the focus and records that window, and
// `leave` resets only this submap. One repeating timer, armed while the
// submap is current and disarmed as it fires, is the timeout; the window
// close hook covers a shell that dies with its window mapped.
function keyPassthroughLines() {
    var p = KEY_PASSTHROUGH;
    return [
        "-- Key capture pass-through: a vgs window that captures a key combo takes every key but " + p.cancel + ".",
        "do",
        "    local passthrough = { submap = \"" + p.submap + "\", class = \"" + APP_WINDOW.appId + "\" }",
        "    hl." + p.table + " = passthrough",
        "    hl.define_submap(passthrough.submap, function()",
        "        hl.bind(\"" + p.cancel + "\", hl.dsp.submap(\"reset\"), { description = \"" + p.description + "\" })",
        "    end)",
        "    function passthrough." + p.verbs.leave + "()",
        "        if hl.get_current_submap() == passthrough.submap then hl.dispatch(hl.dsp.submap(\"reset\")) end",
        "    end",
        "    function passthrough." + p.verbs.enter + "()",
        "        local window = hl.get_active_window()",
        "        if window == nil or window.class ~= passthrough.class then error(\"" + p.submap + ": the focused window is not a vgs window\") end",
        "        passthrough.window = window.address",
        "        hl.dispatch(hl.dsp.submap(passthrough.submap))",
        "    end",
        "    passthrough.timer = hl.timer(function()",
        "        passthrough.timer:set_enabled(false)",
        "        passthrough." + p.verbs.leave + "()",
        "    end, { timeout = " + p.timeoutMs + ", type = \"repeat\" })",
        "    passthrough.timer:set_enabled(false)",
        "    hl.on(\"keybinds.submap\", function(name)",
        "        passthrough.timer:set_enabled(name == passthrough.submap)",
        "        if name ~= passthrough.submap then passthrough.window = nil end",
        "    end)",
        "    hl.on(\"window.close\", function(window)",
        "        if window ~= nil and window.address == passthrough.window then passthrough." + p.verbs.leave + "() end",
        "    end)",
        "    passthrough." + p.verbs.leave + "()",
        "end"
    ];
}

// The motion a pad moves with under THEME: the speed and the bezier points
// of the `workspaces` leaf of the theme's motion preset, the speed scaled
// by its motion scale, or null while the theme moves nothing.
function padMotion(theme) {
    var preset = theme.hyprland.motion.preset;
    if (theme.motionScale === 0 || preset === "none") return null;
    var row = MOTION[preset];
    if (row === undefined)
        throw new Error("HyprlandLayer: motion preset " + JSON.stringify(preset) + " is not known");
    var leaf = row.animations.filter(function (animation) { return animation.leaf === "workspaces"; })[0];
    return { speed: Math.max(0.01, leaf.speed * theme.motionScale), points: row.curves[leaf.bezier] };
}

// The pads of SECTION, a section whose `pads` is a list, under MOTION
// (padMotion): a table of each pad's judged values, one window rule per
// pad that maps its class's windows hidden, tiled and unfocused into the
// pad's special workspace, and the functions on `hl.<PADS.table>`.
// `toggle(name, screen)` answers the function hl.dispatch runs, since
// `hyprctl dispatch X` runs `return hl.dispatch(X)` in a Lua session: it
// hides a shown pad and gives the focus back to the window that had it;
// it refuses a pad whose workspace holds no window; otherwise it moves
// the workspace to SCREEN's monitor, or the focused one for "", writes
// that workspace's gaps from the pad's shares of the monitor's work area,
// sets the special workspace leaves to the pad's motion, shows it there
// and focuses its window, all inside one Lua call. A `window.active` hook
// hides a shown pad once the focus moves to a window outside it, and a
// layout change, or the layer running again, fits each shown pad to its
// monitor again (runtime-hyprland-pads.md).
function padLines(section, motion) {
    var p = PADS;
    var lines = [
        "-- " + section.id + " " + commentText(section.version) + ": pads from its manifest",
        "do",
        "    local pads = { list = {}, before = {}, prefix = \"" + p.workspace + "\", motion = " + (motion === null ? "nil" : "{ speed = " + luaNumber(motion.speed) + ", bezier = \"" + p.curve + "\" }") + " }",
        "    hl." + p.table + " = pads"
    ];
    if (motion !== null)
        lines.push("    hl.curve(\"" + p.curve + "\", { type = \"bezier\", points = { { " + luaNumber(motion.points[0][0]) + ", " + luaNumber(motion.points[0][1]) + " }, { " + luaNumber(motion.points[1][0]) + ", " + luaNumber(motion.points[1][1]) + " } } })");
    section.pads.forEach(function (pad) {
        lines.push("    pads.list[\"" + pad.name + "\"] = { x = \"" + pad.x + "\", y = \"" + pad.y + "\", width = " + luaNumber(pad.width) + ", height = " + luaNumber(pad.height) + ", margin = " + luaNumber(pad.margin) + ", entry = \"" + pad.entry + "\", motion = \"" + pad.motion + "\" }");
        lines.push("    hl.window_rule({ name = \"" + section.id + ":pad-" + pad.name + "\", match = { class = " + classLiteral(pad["class"]) + " }, workspace = \"" + p.workspace + pad.name + " silent\", tile = true, no_initial_focus = true, suppress_event = \"activate activatefocus\" })");
    });
    return lines.concat([
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
        "    function pads." + p.verb + "(name, screen)",
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
    ]);
}

// The pads' sweep, written after every plugin section: as the layer loads,
// each window in a pad's workspace whose pad the table does not hold, as
// after the pad's removal or its plugin's disabling, moves to the focused
// workspace, so no app stays where no key reaches it.
function padSweepLines() {
    return [
        "-- Pads: a window in a pad's workspace that no pad holds comes to the focused workspace.",
        "do",
        "    local pads = hl." + PADS.table + " ~= nil and hl." + PADS.table + ".list or {}",
        "    local active = hl.get_active_workspace()",
        "    for _, window in ipairs(hl.get_windows()) do",
        "        local name = window.workspace ~= nil and string.match(window.workspace.name, \"^" + PADS.workspace.replace(/-/g, "%-") + "(.+)$\") or nil",
        "        if name ~= nil and pads[name] == nil and active ~= nil then",
        "            hl.dispatch(hl.dsp.window.move({ workspace = tostring(active.id), window = \"address:\" .. window.address, follow = false }))",
        "        end",
        "    end",
        "end"
    ];
}

// A layer rule as data: its namespace and effects, which two plugins
// declaring the same rule share.
function ruleKey(rule) {
    return JSON.stringify([rule.namespace, rule.blur === undefined ? null : rule.blur, rule.ignoreAlpha === undefined ? null : rule.ignoreAlpha]);
}

function ruleLine(id, rule) {
    var name = id + ":" + rule.namespace.slice(5, -1);
    var fields = ["name = \"" + name + "\"", "match = { namespace = \"" + rule.namespace + "\" }"];
    if (rule.blur !== undefined) fields.push("blur = " + (rule.blur ? "true" : "false"));
    if (rule.ignoreAlpha !== undefined) fields.push("ignore_alpha = " + String(rule.ignoreAlpha));
    return "hl.layer_rule({ " + fields.join(", ") + " })";
}

// The Lua literal of VALUE for option row ROW: { ok: true, lua } or
// { ok: false, error }. VALUE fitted the setting's schema entry, whose type
// PluginLogic matched to the row's, so a value of another type breaks that
// invariant; a fractional `int` and a string outside OPTION_STRING are a
// user's values the schema admits.
function optionLiteral(row, value) {
    switch (row.type) {
    case "bool":
        if (typeof value === "boolean") return { ok: true, lua: value ? "true" : "false" };
        break;
    case "int":
        if (typeof value === "number" && Number.isInteger(value)) return { ok: true, lua: String(value) };
        if (typeof value === "number") return { ok: false, error: "want=whole-number" };
        break;
    case "float":
        if (typeof value === "number" && isFinite(value)) return { ok: true, lua: String(value) };
        break;
    case "string":
        if (typeof value === "string") return OPTION_STRING.test(value) ? { ok: true, lua: "\"" + value + "\"" } : { ok: false, error: "want=characters:" + OPTION_STRING.source };
        break;
    default:
        throw new Error("HyprlandLayer: option type " + JSON.stringify(row.type) + " has no literal");
    }
    throw new Error("HyprlandLayer: option value " + JSON.stringify(value) + " fitted its schema but is no " + row.type);
}

// The `hl.config` table text of TREE, nested objects of Lua literals keyed
// in the order each key was first set.
function optionTree(tree) {
    return Object.keys(tree).map(function (key) {
        return key + " = " + (typeof tree[key] === "string" ? tree[key] : "{ " + optionTree(tree[key]) + " }");
    }).join(", ");
}

// Whether a section sets an option the layer writes per touchpad, so the
// shell reads Hyprland's devices for it.
function wantsTouchpads(sections) {
    return sections.some(function (section) {
        return section.options.some(function (option) { return OPTIONS[option.path].device === "touchpad"; });
    });
}

// The descriptions of the binds the layer writes in the default submap:
// each bound shortcut's global and its hold companion's.
function boundDescriptions(plan) {
    var out = [];
    plan.sections.forEach(function (row) {
        row.binds.forEach(function (entry) {
            if (entry.kind !== "bound") return;
            out.push(entry.global);
            var release = releaseGlobal(entry);
            if (release !== null) out.push(release);
        });
    });
    return out;
}

// Resolution makes fresh maps per read, so plugin mutations stay local.
// An undeclared name is absent; no enabled section means an empty map.
function shortcutKeys(sections, id) {
    var resolved = resolveBinds(sections);
    return resolved.keys[id] || Object.create(null);
}

// One plugin section's options, as PluginLogic.hyprlandSection lists the
// ones its plugins row sets, appended to OUT: `applied`, one `hl.config({
// input = ... })` line holding every option written, in the manifest's
// order, for appliedLines, and `placed`, one `hl.device` line per touchpad
// for the device row, then a comment for each option not written, which
// stay with the plugin's section. HELD maps each path written so far to its
// plugin, so a path two plugins set stays with the first by id. TOUCHPADS
// is the touchpad names Hyprland lists, or null while they are unread.
function optionLines(section, held, touchpads, touchpadFailure, out) {
    var tree = {};
    var devices = [];
    var notes = [];
    section.options.forEach(function (option) {
        var name = section.id + ":" + option.setting;
        var refuse = function (error) {
            out.refusals.push({ id: section.id, setting: option.setting, path: option.path, error: error });
            notes.push("-- skipped " + commentText(option.path) + " for " + commentText(name) + ": " + commentText(error));
        };
        switch (option.kind) {
        case "unfit":
            refuse(option.error);
            return;
        case "set":
            break;
        default:
            throw new Error("HyprlandLayer: option kind " + JSON.stringify(option.kind) + " is not one of set, unfit");
        }
        if (!Object.prototype.hasOwnProperty.call(OPTIONS, option.path))
            throw new Error("HyprlandLayer: option path " + JSON.stringify(option.path) + " is not one of OPTIONS");
        if (held[option.path] !== undefined) {
            out.conflicts.push({ id: section.id, setting: option.setting, path: option.path, heldBy: held[option.path] });
            notes.push("-- skipped " + commentText(option.path) + " for " + commentText(name) + ": already set by " + commentText(held[option.path]));
            return;
        }
        var row = OPTIONS[option.path];
        if (typeof option.lua !== "string")
            throw new Error("HyprlandLayer: option " + JSON.stringify(option.path) + " was not judged to a Lua literal");
        var recordWritten = function () {
            held[option.path] = section.id;
            out.written.push({ id: section.id, setting: option.setting, path: option.path, value: option.value });
        };
        if (row.device === "touchpad") {
            if (touchpads === null || touchpads === undefined) {
                if (touchpadFailure !== "") refuse("touchpads unread: " + touchpadFailure);
                devices.push("-- " + commentText(option.path) + " for " + commentText(name) + ": Hyprland's touchpads are not read yet");
                return;
            }
            if (touchpads.length === 0) {
                refuse("Hyprland lists no touchpad");
                devices.push("-- " + commentText(option.path) + " for " + commentText(name) + ": Hyprland lists no touchpad");
                return;
            }
            var wrote = false;
            touchpads.forEach(function (touchpad) {
                if (DEVICE_NAME.test(touchpad)) {
                    devices.push("hl.device({ name = \"" + touchpad + "\", enabled = " + option.lua + " })");
                    wrote = true;
                } else {
                    out.refusals.push({ id: section.id, setting: option.setting, path: option.path, error: "touchpad name refused" });
                    devices.push("-- skipped touchpad " + commentText(touchpad) + " for " + commentText(name) + ": its name holds a quote, a backslash or a control character");
                }
            });
            if (wrote) {
                recordWritten();
            }
            return;
        }
        recordWritten();
        var parts = option.path.split(".");
        var node = tree;
        for (var i = 0; i < parts.length - 1; i++) {
            if (node[parts[i]] === undefined) node[parts[i]] = {};
            node = node[parts[i]];
        }
        node[parts[parts.length - 1]] = option.lua;
    });
    return { applied: Object.keys(tree).length > 0 ? ["hl.config({ " + optionTree(tree) + " })"] : [], placed: devices.concat(notes) };
}

// The section that applies VALUES, Lua lines, once the whole configuration
// has loaded: Hyprland runs a `config.reloaded` callback at the end of every
// load, the first included, so a value set there holds over the user's own
// line for it, and the user's other keys of the same table keep theirs.
// PATHS are the options among VALUES that `getoption` reads. As the layer
// loads, the first line of hyprland.lua, it reads each one's value; the
// callback reads each again before VALUES and after, and keeps the middle
// reading as the user's where it is neither the first nor the last
// (USER_VALUES). An option the user's configuration leaves alone, or sets
// to the value the layer sets or to Hyprland's own default, has no user
// value: `hl.get_config` answers a value and not whether a line set it.
function appliedLines(values, paths) {
    var u = USER_VALUES;
    return [
        "-- Applied once the whole configuration has loaded: each value holds over the user's own line for it.",
        "do",
        "    local options = { start = {}, user = {} }",
        "    hl." + u.table + " = options",
        "    for _, path in ipairs({ " + paths.map(function (path) { return "\"" + path + "\""; }).join(", ") + " }) do options.start[path] = hl.get_config(path) end",
        "    local function json(value)",
        "        if type(value) ~= \"string\" then return tostring(value) end",
        "        return \"\\\"\" .. string.gsub(value, \"[%c\\\"\\\\]\", function(c) return string.format(\"\\\\u%04x\", string.byte(c)) end) .. \"\\\"\"",
        "    end",
        "    function options." + u.verb + "()",
        "        local rows = {}",
        "        for path, value in pairs(options.user) do rows[#rows + 1] = \"{\\\"path\\\":\\\"\" .. path .. \"\\\",\\\"value\\\":\" .. json(value) .. \"}\" end",
        "        table.sort(rows)",
        "        return \"" + u.key + "=[\" .. table.concat(rows, \",\") .. \"]\"",
        "    end",
        "    hl.on(\"config.reloaded\", function()",
        "        local theirs = {}",
        "        for path in pairs(options.start) do theirs[path] = hl.get_config(path) end"
    ].concat(values.map(function (line) { return "        " + line; }), [
        "        for path, start in pairs(options.start) do",
        "            if theirs[path] ~= start and theirs[path] ~= hl.get_config(path) then options.user[path] = theirs[path] end",
        "        end",
        "    end)",
        "end"
    ]);
}

// The layer's text and the binds, options or appearance owner declarations
// it could not write.
//
// SECTIONS are PluginLogic.hyprlandSection results for the enabled plugins,
// in any order; they are written by plugin id, a section that asks nothing
// not at all. Each written section opens with its plugin's id and version,
// then its layer rules, then its binds, then, for the first section by id
// whose `pads` is a list, its pads (padLines); a later one's are a comment,
// since the pads' functions are one table on `hl`. A key two sections bind goes to the
// first by id: the later bind becomes a `skipped` comment and one conflict,
// { id, shortcut, key, heldBy }. A bind whose key the user set to null
// becomes an `unbound` comment. A layer rule an earlier section already
// wrote, the same namespace and effects, is written once. THEME gives the
// theme's colours and Hyprland tokens, and `tuiMargins`, the margins
// tuiWindowLines keeps the floating TUIs from the output's edges. After
// the header comes appliedLines: the APPLIED_GROUPS whose switch is on, in
// order, then each section's `hl.config` options line under its heading.
// A group whose switch is off is a comment after it, and `noGaps` follows
// them, written where it stands. The floating
// TUIs' window rules follow them, then the shell's application window
// rule, the overlay capture, the key capture pass-through and the session
// lock's restore, before any plugin section, whatever the sections. A
// section whose plugins row sets options is preceded by its options
// section, the touchpad lines and comments of optionLines, when it has
// any; an option two sections set goes to the first by
// id. TOUCHPADS is the touchpad names Hyprland lists, or null while unread.
// The pads' sweep, padSweepLines, ends the file whatever the sections.
// The result also lists each option written,
// as { id, setting, path, value }, each one skipped as a conflict, { id,
// setting, path, heldBy }, or refused, { id, setting, path, error },
// `padConflicts`, each section whose pads a section before it by id
// defines, { id, heldBy }, and `binds`, the description of every bind
// written in the default submap.
function render(sections, theme, themeName, highestScale, touchpads, touchpadFailure) {
    var plan = resolveBinds(sections);
    var switches = groupSwitches(sections);
    var applied = [];
    var groups = [];
    var groupLines = { borders: function () { return borderLines(theme, themeName); }, radius: function () { return radiusLines(theme, highestScale); }, motion: function () { return motionLines(theme); } };
    APPLIED_GROUPS.forEach(function (group) {
        if (switches.groups[group].enabled) applied = applied.concat(groupLines[group]());
        else groups.push(disabledGroupLine(group, switches.groups[group].setting), "");
    });
    if (switches.groups.noGaps.enabled) groups = groups.concat(noGapsLines());
    else groups.push(disabledGroupLine("noGaps", switches.groups.noGaps.setting));
    var lines = [""].concat(groups, [""], tuiWindowLines(theme.tuiMargins), [""], appWindowLines(), [""], overlayCaptureLines(plan), [""], keyPassthroughLines(), [""], sessionLockLines());
    var written = Object.create(null);
    var options = { written: [], conflicts: [], refusals: [] };
    var optionsHeld = Object.create(null);
    var padsOwner = null;
    var padConflicts = [];
    plan.sections.forEach(function (row) {
        var section = row.section;
        if (section.options.length > 0) {
            var heading = "-- " + section.id + " " + commentText(section.version) + ": input options its settings set";
            var optionText = optionLines(section, optionsHeld, touchpads, touchpadFailure || "", options);
            if (optionText.applied.length > 0) applied = applied.concat([heading], optionText.applied);
            if (optionText.placed.length > 0) lines = lines.concat(["", heading], optionText.placed);
        }
        if (section.binds.length === 0 && section.layerRules.length === 0 && !Array.isArray(section.pads)) return;
        lines.push("", "-- " + section.id + " " + commentText(section.version) + ": binds and layer rules from its manifest");
        section.layerRules.forEach(function (rule) {
            var key = ruleKey(rule);
            if (written[key] !== undefined) {
                lines.push("-- layer rule for " + rule.namespace + " already written by " + written[key]);
                return;
            }
            written[key] = section.id;
            lines.push(ruleLine(section.id, rule));
        });
        row.binds.forEach(function (entry) {
            if (entry.kind === "unbound") {
                lines.push("-- unbound " + entry.global + ": shell.json sets its key to null");
                return;
            }
            if (entry.kind === "skipped") {
                lines.push("-- skipped " + entry.bind.key + ": already bound by " + entry.heldBy);
                return;
            }
            lines = lines.concat(shortcutBindLines(entry));
        });
        if (!Array.isArray(section.pads)) return;
        if (padsOwner !== null) {
            lines.push("-- pads of " + section.id + " skipped: " + padsOwner + " defines them");
            padConflicts.push({ id: section.id, heldBy: padsOwner });
            return;
        }
        padsOwner = section.id;
        lines = lines.concat([""], padLines(section, padMotion(theme)));
    });
    var paths = options.written.filter(function (option) { return OPTIONS[option.path].device === undefined; }).map(function (option) { return option.path; });
    lines = [
        "-- Generated by the vgs shell; an edit here is lost. The shell writes this",
        "-- file again when a plugin, shell.json or the theme changes, and",
        "-- `" + REGENERATE + "` writes it on demand. hyprland.lua runs it from the",
        "-- line `vgshell hypr wire` keeps first there, so an unbind or a rule",
        "-- switch after that line acts on what this file made.",
        ""
    ].concat(appliedLines(applied, paths), lines);
    lines = lines.concat([""], padSweepLines());
    return {
        text: lines.join("\n") + "\n",
        conflicts: plan.conflicts,
        appearanceConflicts: switches.conflicts,
        padConflicts: padConflicts,
        options: options.written,
        optionConflicts: options.conflicts,
        optionRefusals: options.refusals,
        binds: boundDescriptions(plan)
    };
}

// The writer's sequence, HyprlandLayer.qml's one decision about what to do
// next: step(state, event, text) answers { state, action }, and the QML runs
// the action and feeds its result back as the next event. TEXT is the
// rendered layer, or null before the inputs are ready.
//
// A cycle reads the file when it must, makes the directory, writes the text
// and reloads Hyprland. Once one write-and-reload cycle completes, the
// machine probes hyprland.lua and asks before it wires the loading line.
// Quickshell's FileView writes nothing, and
// reports nothing, for the bytes it last read or wrote, and it keeps the
// bytes of a failed write as those; so a failed write leaves the view
// `stale`, and the next cycle reads the file before any write. A text whose
// directory or write failed is not written again until the text changes or
// a render forces it, so an unwritable directory costs one attempt per
// change, never a loop. A render asked while a step runs is queued in
// `queuedForce` and starts its own cycle, a read first, once the step ends.
//
// State: phase (`reading`, `idle`, `preparing`, `writing`, `reloading`,
// `probing`, `checkingDecline`, `declining`, `wiring`);
// onDisk, the bytes last read or written, null when absent or unreadable,
// undefined before the first read ends; stale; queuedForce; forcing, which
// writes and reloads whatever the bytes; pending, the text being written;
// failedText; failure, the last step's keyed failure, "" once a cycle
// completes; reloadOwner, `layer` for the layer writer and `wire` for a
// Connect reload; consent, a tagged state for the Hyprland wiring question.
// Actions: `none`, `read`, `mkdir`, `write` (state.pending), `reload`,
// `probe`, `checkDecline`, `ask`, `decline` and `wire`.
function initialState() {
    return {
        phase: "reading",
        onDisk: undefined,
        stale: false,
        queuedForce: false,
        forcing: false,
        pending: "",
        failedText: null,
        failure: "",
        reloadOwner: "",
        consent: { phase: "pending", queued: "", failure: "" }
    };
}

function withChanges(state, changes) {
    var out = {};
    Object.keys(state).forEach(function (key) { out[key] = state[key]; });
    Object.keys(changes).forEach(function (key) { out[key] = changes[key]; });
    return out;
}

function expectPhase(state, event, phase) {
    if (state.phase !== phase)
        throw new Error("HyprlandLayer.step: event " + event.type + " arrived in phase " + state.phase + ", want " + phase);
}

function consentChanges(state, changes) {
    return withChanges(state, { consent: withChanges(state.consent, changes) });
}

// An idle writer: start the next cycle, or rest.
function begin(state, text) {
    if (state.queuedForce || state.stale)
        return { state: withChanges(state, { phase: "reading", forcing: state.forcing || state.queuedForce, queuedForce: false, stale: false }), action: "read" };
    if (text !== null && (state.forcing || (text !== state.onDisk && text !== state.failedText)))
        return { state: withChanges(state, { phase: "preparing", pending: text }), action: "mkdir" };
    if (state.consent.phase === "asking" && state.consent.queued === "connect")
        return { state: withChanges(state, { phase: "wiring" }), action: "wire" };
    if (state.consent.phase === "asking" && state.consent.queued === "decline")
        return { state: withChanges(state, { phase: "declining" }), action: "decline" };
    if (state.consent.phase === "pending" && text !== null && text === state.onDisk)
        return { state: withChanges(state, { phase: "probing" }), action: "probe" };
    if (state.consent.phase === "unwired")
        return { state: withChanges(state, { phase: "checkingDecline" }), action: "checkDecline" };
    return { state: withChanges(state, { forcing: false }), action: "none" };
}

// The bytes are on disk: reload the layer after every write.
function written(state) {
    var next = withChanges(state, { onDisk: state.pending, failedText: null });
    return { state: withChanges(next, { phase: "reloading", reloadOwner: "layer" }), action: "reload" };
}

function idleDecision(state, failure, text, clearForcing) {
    return begin(withChanges(state, { phase: "idle", failure: failure, forcing: clearForcing ? false : state.forcing, reloadOwner: "" }), text);
}

// EVENT is one of { type: "loaded", content }, { type: "loadFailed",
// notFound, detail }, { type: "render" } (the text changed), { type: "force" }
// (a render request), { type: "mkdirDone", failure }, { type: "saved" },
// { type: "saveFailed", failure }, { type: "reloadDone", failure },
// { type: "probeDone", answer|failure }, { type: "declineChecked",
// declined|failure }, { type: "connect" }, { type: "decline" },
// { type: "declineDone", failure } and { type: "wireDone", failure }, a
// failure being "" when the step worked.
function step(state, event, text) {
    switch (event.type) {
    case "loaded":
        expectPhase(state, event, "reading");
        return idleDecision(withChanges(state, { onDisk: event.content }), state.failure, text, false);
    case "loadFailed":
        expectPhase(state, event, "reading");
        return idleDecision(withChanges(state, {
            onDisk: null,
            failure: event.notFound ? state.failure : "read=failed " + event.detail
        }), event.notFound ? state.failure : "read=failed " + event.detail, text, false);
    case "render":
        return state.phase === "idle" ? begin(state, text) : { state: state, action: "none" };
    case "force":
        var queued = withChanges(state, { queuedForce: true });
        return state.phase === "idle" ? begin(queued, text) : { state: queued, action: "none" };
    case "mkdirDone":
        expectPhase(state, event, "preparing");
        if (event.failure !== "") return idleDecision(withChanges(state, { failedText: state.pending }), event.failure, text, true);
        // FileView skips the bytes it holds already, and reports nothing.
        if (state.pending === state.onDisk) return written(withChanges(state, { phase: "writing" }));
        return { state: withChanges(state, { phase: "writing" }), action: "write" };
    case "saved":
        expectPhase(state, event, "writing");
        return written(state);
    case "saveFailed":
        expectPhase(state, event, "writing");
        return idleDecision(withChanges(state, { stale: true, failedText: state.pending }), event.failure, text, true);
    case "reloadDone":
        expectPhase(state, event, "reloading");
        if (state.reloadOwner === "wire") {
            if (event.failure !== "")
                return idleDecision(consentChanges(state, { phase: "asking", queued: "", failure: event.failure }), event.failure, text, true);
            return idleDecision(consentChanges(state, { phase: "wired", queued: "", failure: "" }), "", text, true);
        }
        if (state.reloadOwner === "layer")
            return idleDecision(state, event.failure, text, true);
        throw new Error("HyprlandLayer.step: reload owner " + JSON.stringify(state.reloadOwner) + " is not one of layer, wire");
    case "probeDone":
        expectPhase(state, event, "probing");
        if (event.failure !== undefined && event.failure !== "")
            return idleDecision(consentChanges(state, { phase: "settled", queued: "", failure: "" }), event.failure, text);
        switch (event.answer) {
        case "wired":
            return idleDecision(consentChanges(state, { phase: "wired", queued: "", failure: "" }), state.failure, text);
        case "absent":
            return idleDecision(consentChanges(state, { phase: "settled", queued: "", failure: "" }), state.failure, text);
        case "unwired":
            return idleDecision(consentChanges(state, { phase: "unwired", queued: "", failure: "" }), state.failure, text);
        }
        throw new Error("HyprlandLayer.step: unknown probe answer " + JSON.stringify(event.answer));
    case "declineChecked":
        expectPhase(state, event, "checkingDecline");
        if (event.failure !== undefined && event.failure !== "")
            return idleDecision(consentChanges(state, { phase: "settled", queued: "", failure: "" }), event.failure, text);
        if (event.declined) return idleDecision(consentChanges(state, { phase: "declined", queued: "", failure: "" }), state.failure, text);
        return idleDecision(consentChanges(state, { phase: "asking", queued: "", failure: "" }), state.failure, text);
    case "connect":
        if (state.consent.phase !== "asking")
            throw new Error("HyprlandLayer.step: event connect arrived in consent phase " + state.consent.phase + ", want asking");
        if (state.consent.queued !== "") return { state: state, action: "none" };
        return state.phase === "idle" ? begin(consentChanges(state, { queued: "connect", failure: "" }), text) : { state: consentChanges(state, { queued: "connect", failure: "" }), action: "none" };
    case "decline":
        if (state.consent.phase !== "asking")
            throw new Error("HyprlandLayer.step: event decline arrived in consent phase " + state.consent.phase + ", want asking");
        if (state.consent.queued !== "") return { state: state, action: "none" };
        return state.phase === "idle" ? begin(consentChanges(state, { queued: "decline", failure: "" }), text) : { state: consentChanges(state, { queued: "decline", failure: "" }), action: "none" };
    case "declineDone":
        expectPhase(state, event, "declining");
        return idleDecision(consentChanges(state, { phase: "declined", queued: "", failure: "" }), event.failure, text);
    case "wireDone":
        expectPhase(state, event, "wiring");
        if (event.failure !== "")
            return idleDecision(consentChanges(state, { phase: "asking", queued: "", failure: event.failure }), event.failure, text);
        return { state: withChanges(consentChanges(state, { phase: "asking", queued: "connect", failure: "" }), { phase: "reloading", reloadOwner: "wire" }), action: "reload" };
    }
    throw new Error("HyprlandLayer.step: unknown event " + JSON.stringify(event.type));
}
