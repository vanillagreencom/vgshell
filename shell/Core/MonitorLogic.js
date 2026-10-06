.pragma library

// The outputs Hyprland lists, as the `monitors` capability hands them to a
// plugin, and the monitor rules vgs.displays may set. The rules stay in the
// plugin's data and reach Hyprland only through the generated layer or a
// guarded trial (docs/decisions/D096-vgs-reads-outputs-and-writes-no-monitor-rule.md).
// Pure: no QML object, no I/O, so scripts/test-monitor-logic.js runs it
// under node. MonitorState.qml runs the request and holds what parseOutputs
// answers. Every Hyprland v0.56.2 fact the shapes rest on is in
// docs/architecture/runtime-hyprland.md.

var OUTPUTS_REQUEST = ["hyprctl", "-j", "monitors", "all"];

var AVAILABLE_MODE = /^([0-9]+)x([0-9]+)@([0-9]+\.[0-9]+)Hz$/;

function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function hasOwn(object, key) {
    return object !== null && typeof object === "object" && Object.prototype.hasOwnProperty.call(object, key);
}

// VALUE as a refusal shows it: JSON, cut to 60 characters.
function shown(value) {
    var text = JSON.stringify(value);
    if (text === undefined) text = String(value);
    return text.length > 60 ? text.slice(0, 57) + "..." : text;
}

// What names an output across plugs: `desc:<make> <model>
// <serial>` when Hyprland reads a serial, else the connector name. Hyprland
// matches a `desc:` selector against the output's short description, the three
// joined by spaces, trimmed, with every comma removed
// (CMonitor::onConnect, CMonitor::matchesStaticSelector).
function identifier(output) {
    if (output.serial === "") return output.name;
    return "desc:" + (output.make + " " + output.model + " " + output.serial).trim().replace(/,/g, "");
}

// The reply to OUTPUTS_REQUEST as the capability's `outputs`: { ok: true,
// outputs: [{ identifier, id, name, description, make, model, serial,
// width, height, refreshRate, x, y, scale, transform, vrr, disabled,
// mirrorOf, availableModes: [{ width, height, refresh }], currentFormat }] }
// colorManagementPreset, sdrBrightness, sdrSaturation }] } in Hyprland's
// order, `mirrorOf` the name of the output mirrored or null,
// or { ok: false, error } with a keyed line.
function parseOutputs(text) {
    var list;
    try {
        list = JSON.parse(text);
    } catch (e) {
        return { ok: false, error: "refused: outputs=unparsed " + String(e.message || e) };
    }
    if (!Array.isArray(list)) return { ok: false, error: "refused: outputs=shape want=list" };
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var m = list[i];
        var bad = function (field) { return { ok: false, error: "refused: outputs=shape output=" + i + " field=" + field }; };
        if (!isPlainObject(m)) return bad("object");
        var strings = ["name", "description", "make", "model", "serial", "mirrorOf", "currentFormat", "colorManagementPreset"];
        for (var s = 0; s < strings.length; s++) if (typeof m[strings[s]] !== "string") return bad(strings[s]);
        var whole = ["id", "width", "height", "x", "y", "transform"];
        for (var w = 0; w < whole.length; w++) if (!Number.isInteger(m[whole[w]])) return bad(whole[w]);
        if (typeof m.refreshRate !== "number" || !isFinite(m.refreshRate)) return bad("refreshRate");
        if (typeof m.scale !== "number" || !isFinite(m.scale)) return bad("scale");
        if (typeof m.vrr !== "boolean") return bad("vrr");
        if (typeof m.disabled !== "boolean") return bad("disabled");
        if (typeof m.sdrBrightness !== "number" || !isFinite(m.sdrBrightness)) return bad("sdrBrightness");
        if (typeof m.sdrSaturation !== "number" || !isFinite(m.sdrSaturation)) return bad("sdrSaturation");
        if (!Array.isArray(m.availableModes)) return bad("availableModes");
        var modes = [];
        for (var k = 0; k < m.availableModes.length; k++) {
            var parsed = typeof m.availableModes[k] === "string" ? AVAILABLE_MODE.exec(m.availableModes[k]) : null;
            if (parsed === null) return bad("availableModes");
            modes.push({ width: Number(parsed[1]), height: Number(parsed[2]), refresh: Number(parsed[3]) });
        }
        out.push({
            identifier: "", id: m.id, name: m.name, description: m.description, make: m.make, model: m.model, serial: m.serial,
            width: m.width, height: m.height, refreshRate: m.refreshRate, x: m.x, y: m.y, scale: m.scale, transform: m.transform,
            vrr: m.vrr, disabled: m.disabled, mirrorOf: m.mirrorOf, availableModes: modes, currentFormat: m.currentFormat,
            colorManagementPreset: m.colorManagementPreset, sdrBrightness: m.sdrBrightness, sdrSaturation: m.sdrSaturation
        });
    }
    // `mirrorOf` is the mirrored output's id, or `none`.
    for (var j = 0; j < out.length; j++) {
        out[j].identifier = identifier(out[j]);
        if (out[j].mirrorOf === "none") {
            out[j].mirrorOf = null;
            continue;
        }
        var target = out.filter(function (o) { return String(o.id) === out[j].mirrorOf; });
        if (target.length !== 1) return { ok: false, error: "refused: outputs=shape output=" + j + " mirrorOf=" + shown(out[j].mirrorOf) };
        out[j].mirrorOf = target[0].name;
    }
    return { ok: true, outputs: out };
}

var RULE_KEYS = ["disabled", "mode", "position", "scale", "transform"];
var OUTPUT_NAME = /^[\x20\x21\x23-\x5b\x5d-\x7e]{1,512}$/;
var TRANSFORMS = [
    { value: 0, label: "Normal" },
    { value: 1, label: "90°" },
    { value: 2, label: "180°" },
    { value: 3, label: "270°" },
    { value: 4, label: "Flipped" },
    { value: 5, label: "Flipped 90°" },
    { value: 6, label: "Flipped 180°" },
    { value: 7, label: "Flipped 270°" }
];
var SCALE_CANDIDATES = [1, 1.25, 4 / 3, 1.5, 1.6, 5 / 3, 1.75, 2, 2.25, 2.5, 3];

function modeOf(output) {
    return { width: output.width, height: output.height, refresh: output.refreshRate };
}

function positionOf(output) {
    return { x: output.x, y: output.y };
}

function sameMode(a, b) {
    return a.width === b.width && a.height === b.height && Math.abs(a.refresh - b.refresh) <= 0.015;
}

function scaleFits(mode, scale) {
    if (typeof scale !== "number" || !isFinite(scale) || scale <= 0) return false;
    var w = mode.width / scale;
    var h = mode.height / scale;
    return Math.abs(w - Math.round(w)) <= 0.001 && Math.abs(h - Math.round(h)) <= 0.001;
}

function scaleChoices(mode, current) {
    var out = [];
    SCALE_CANDIDATES.concat([current]).forEach(function (scale) {
        if (!scaleFits(mode, scale)) return;
        if (!out.some(function (seen) { return Math.abs(seen - scale) < 0.000001; })) out.push(scale);
    });
    return out.sort(function (a, b) { return a - b; }).map(function (scale) {
        return { label: scaleLabel(scale), value: scale };
    });
}

function scaleLabel(scale) {
    var rounded = Math.round(scale * 1000) / 1000;
    return String(rounded).replace(/(\.[0-9]*?)0+$/, "$1").replace(/\.$/, "") + "×";
}

function outputByIdentifier(outputs, id) {
    for (var i = 0; i < outputs.length; i++) if (outputs[i].identifier === id) return outputs[i];
    return null;
}

function normalizedRule(output, rule) {
    var currentMode = modeOf(output);
    var mode = rule.mode === undefined ? currentMode : rule.mode;
    return {
        disabled: rule.disabled === undefined ? output.disabled : rule.disabled,
        mode: { width: mode.width, height: mode.height, refresh: mode.refresh },
        position: rule.position === undefined ? positionOf(output) : { x: rule.position.x, y: rule.position.y },
        scale: rule.scale === undefined ? output.scale : rule.scale,
        transform: rule.transform === undefined ? output.transform : rule.transform
    };
}

function modeError(mode, at) {
    if (!isPlainObject(mode)) return at + ".mode must be an object";
    if (!Number.isInteger(mode.width) || mode.width <= 0) return at + ".mode.width must be a positive integer";
    if (!Number.isInteger(mode.height) || mode.height <= 0) return at + ".mode.height must be a positive integer";
    if (typeof mode.refresh !== "number" || !isFinite(mode.refresh) || mode.refresh <= 0) return at + ".mode.refresh must be a positive number";
    return "";
}

function ruleError(rule, at) {
    if (!isPlainObject(rule)) return at + " must be an object";
    var keys = Object.keys(rule);
    for (var k = 0; k < keys.length; k++) if (RULE_KEYS.indexOf(keys[k]) === -1) return at + " has unknown key " + JSON.stringify(keys[k]);
    if (rule.disabled !== undefined && typeof rule.disabled !== "boolean") return at + ".disabled must be a boolean";
    if (rule.mode !== undefined) {
        var badMode = modeError(rule.mode, at);
        if (badMode !== "") return badMode;
    }
    if (rule.position !== undefined) {
        if (!isPlainObject(rule.position)) return at + ".position must be an object";
        if (!Number.isInteger(rule.position.x)) return at + ".position.x must be an integer";
        if (!Number.isInteger(rule.position.y)) return at + ".position.y must be an integer";
    }
    if (rule.scale !== undefined && (typeof rule.scale !== "number" || !isFinite(rule.scale) || rule.scale <= 0)) return at + ".scale must be a positive number";
    if (rule.transform !== undefined && (!Number.isInteger(rule.transform) || rule.transform < 0 || rule.transform > 7)) return at + ".transform must be 0-7";
    return "";
}

// Judge the saved or trial monitor RULES, keyed by output identifier. With
// OUTPUTS, this also proves every mode is offered by that output, the scale
// makes whole logical pixels, and at least one output remains enabled.
function rulesError(rules, outputs) {
    if (!isPlainObject(rules)) return "refused: monitors=shape want=object";
    var ids = Object.keys(rules);
    var enabled = 0;
    for (var i = 0; i < ids.length; i++) {
        var id = ids[i];
        var at = "monitors." + id;
        if (!OUTPUT_NAME.test(id)) return "refused: " + at + " identifier refused";
        var rule = rules[id];
        var bad = ruleError(rule, at);
        if (bad !== "") return "refused: " + bad;
        if (Array.isArray(outputs)) {
            var output = outputByIdentifier(outputs, id);
            if (output === null) return "refused: " + at + " output=absent";
            var normalized = normalizedRule(output, rule);
            var modes = output.availableModes;
            if (modes.length > 0 && !modes.some(function (mode) { return sameMode(mode, normalized.mode); }))
                return "refused: " + at + ".mode unavailable";
            if (!scaleFits(normalized.mode, normalized.scale))
                return "refused: " + at + ".scale fractional-logical-pixels";
        }
    }
    if (Array.isArray(outputs)) {
        for (var o = 0; o < outputs.length; o++) {
            var out = outputs[o];
            var r = hasOwn(rules, out.identifier) ? rules[out.identifier] : {};
            if (!normalizedRule(out, r).disabled) enabled += 1;
        }
        if (outputs.length > 0 && enabled === 0) return "refused: monitors=all-disabled";
    } else if (ids.length > 0 && ids.every(function (id) { return rules[id].disabled === true; })) {
        return "refused: monitors=all-disabled";
    }
    return "";
}

function luaString(value) {
    if (!OUTPUT_NAME.test(value)) throw new Error("MonitorLogic: refused Lua string " + shown(value));
    return "\"" + value + "\"";
}

function luaNumber(value) {
    if (typeof value !== "number" || !isFinite(value)) throw new Error("MonitorLogic: refused Lua number " + shown(value));
    var rounded = Math.round(value * 1000000) / 1000000;
    return Math.abs(rounded - Math.round(rounded)) < 0.000001 ? String(Math.round(rounded)) : String(rounded);
}

function modeText(mode) {
    return mode.width + "x" + mode.height + "@" + luaNumber(mode.refresh);
}

function positionText(position) {
    return position.x + "x" + position.y;
}

function ruleLine(id, rule) {
    var fields = ["output = " + luaString(id)];
    if (rule.mode !== undefined) fields.push("mode = " + luaString(modeText(rule.mode)));
    if (rule.position !== undefined) fields.push("position = " + luaString(positionText(rule.position)));
    if (rule.scale !== undefined) fields.push("scale = " + luaNumber(rule.scale));
    if (rule.transform !== undefined) fields.push("transform = " + rule.transform);
    if (rule.disabled !== undefined) fields.push("disabled = " + (rule.disabled ? "true" : "false"));
    return "hl." + "monitor({ " + fields.join(", ") + " })";
}

function rulesLines(rules) {
    var bad = rulesError(rules, null);
    if (bad !== "") return { ok: false, error: bad, lines: [] };
    return { ok: true, lines: Object.keys(rules).sort().map(function (id) { return ruleLine(id, rules[id]); }) };
}

function rulesLua(rules) {
    var rendered = rulesLines(rules);
    return rendered.ok ? { ok: true, lua: rendered.lines.join("\n") } : { ok: false, error: rendered.error };
}

function captureRules(outputs, ids) {
    var selected = {};
    ids.forEach(function (id) {
        var output = outputByIdentifier(outputs, id);
        if (output === null) return;
        selected[id] = {
            disabled: output.disabled,
            mode: modeOf(output),
            position: positionOf(output),
            scale: output.scale,
            transform: output.transform
        };
    });
    return selected;
}

function overridden(rule, output) {
    var current = normalizedRule(output, {});
    var saved = normalizedRule(output, rule);
    return saved.disabled !== current.disabled
        || !sameMode(saved.mode, current.mode)
        || Math.abs(saved.scale - current.scale) > 0.000001
        || saved.transform !== current.transform
        || saved.position.x !== current.position.x
        || saved.position.y !== current.position.y;
}
