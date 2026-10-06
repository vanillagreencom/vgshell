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

var RULE_KEYS = ["mode", "position", "scale", "transform"];
var OUTPUT_NAME = /^[\x20\x21\x23-\x5b\x5d-\x7e]{1,512}$/;

function modeOf(output) {
    return { width: output.width, height: output.height, refresh: output.refreshRate };
}

function positionOf(output) {
    return { x: output.x, y: output.y };
}

function sideSwapped(transform) {
    return [1, 3, 5, 7].indexOf(transform) !== -1;
}

function logicalSize(rule) {
    var scale = rule.scale;
    var width = rule.mode.width / scale;
    var height = rule.mode.height / scale;
    if (sideSwapped(rule.transform)) return { width: height, height: width };
    return { width: width, height: height };
}

function logicalRect(rule) {
    var size = logicalSize(rule);
    return { x: rule.position.x, y: rule.position.y, width: size.width, height: size.height };
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

function outputByIdentifier(outputs, id) {
    for (var i = 0; i < outputs.length; i++) if (outputs[i].identifier === id) return outputs[i];
    return null;
}

function outputsByKey(outputs, id) {
    return outputs.filter(function (o) { return o.identifier === id || o.name === id; });
}

function normalizedRule(output, rule) {
    var currentMode = modeOf(output);
    var mode = rule.mode === undefined ? currentMode : rule.mode;
    return {
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
    for (var i = 0; i < ids.length; i++) {
        var id = ids[i];
        var at = "monitors." + id;
        if (!OUTPUT_NAME.test(id)) return "refused: " + at + " identifier refused";
        var rule = rules[id];
        var bad = ruleError(rule, at);
        if (bad !== "") return "refused: " + bad;
        if (Array.isArray(outputs)) {
            var matching = outputsByKey(outputs, id);
            if (matching.length === 0) return "refused: " + at + " output=absent";
            if (matching.length > 1 && matching[0].identifier === id) return "refused: " + at + " output=tiled";
            var output = matching[0];
            var normalized = normalizedRule(output, rule);
            var modes = output.availableModes;
            if (rule.mode !== undefined && modes.length > 0 && !modes.some(function (mode) { return sameMode(mode, normalized.mode); }))
                return "refused: " + at + ".mode unavailable";
            if (!scaleFits(normalized.mode, normalized.scale))
                return "refused: " + at + ".scale fractional-logical-pixels";
        }
    }
    return "";
}

function overlap(a, b) {
    return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
}

function sharesEdge(a, b) {
    var vertical = (Math.abs(a.x + a.width - b.x) <= 0.001 || Math.abs(b.x + b.width - a.x) <= 0.001)
        && a.y < b.y + b.height && b.y < a.y + a.height;
    var horizontal = (Math.abs(a.y + a.height - b.y) <= 0.001 || Math.abs(b.y + b.height - a.y) <= 0.001)
        && a.x < b.x + b.width && b.x < a.x + a.width;
    return vertical || horizontal;
}

function layoutError(rules, outputs) {
    var bad = rulesError(rules, outputs);
    if (bad !== "") return bad;
    var rects = [];
    outputs.filter(function (output) { return !output.disabled; }).forEach(function (output) {
        var rule = hasOwn(rules, output.name) ? rules[output.name] : hasOwn(rules, output.identifier) ? rules[output.identifier] : {};
        var rect = logicalRect(normalizedRule(output, rule));
        if (rect.width > 0 && rect.height > 0) rects.push({ id: output.name, rect: rect });
    });
    for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
            if (overlap(rects[i].rect, rects[j].rect)) return "refused: monitors.layout=overlap a=" + rects[i].id + " b=" + rects[j].id;
        }
    }
    if (rects.length > 1) {
        var seen = [0];
        for (var changed = true; changed;) {
            changed = false;
            for (var r = 0; r < rects.length; r++) {
                if (seen.indexOf(r) !== -1) continue;
                if (seen.some(function (s) { return sharesEdge(rects[r].rect, rects[s].rect); })) {
                    seen.push(r);
                    changed = true;
                }
            }
        }
        if (seen.length !== rects.length) return "refused: monitors.layout=gap";
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
    return "hl.monitor({ " + fields.join(", ") + " })";
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
        outputsByKey(outputs, id).forEach(function (output) {
            var rule = {
                mode: modeOf(output),
                position: positionOf(output),
                scale: output.scale,
                transform: output.transform
            };
            if (output.width <= 0 || output.height <= 0) delete rule.mode;
            selected[output.name] = rule;
        });
    });
    return selected;
}

function overridden(rule, output) {
    var current = normalizedRule(output, {});
    var saved = normalizedRule(output, rule);
    return !sameMode(saved.mode, current.mode)
        || Math.abs(saved.scale - current.scale) > 0.000001
        || saved.transform !== current.transform
        || saved.position.x !== current.position.x
        || saved.position.y !== current.position.y;
}
