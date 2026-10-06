.pragma library

// The outputs Hyprland lists, as the `monitors` capability hands them to a
// plugin, and the monitor rules vgs.displays may set. The rules stay in the
// plugin's data and reach Hyprland only through the generated layer or a
// guarded trial (docs/decisions/D096-vgs-reads-outputs-and-writes-no-monitor-rule.md).
// Pure: no QML object, no I/O, so scripts/test-monitor-logic.js runs it
// under node. MonitorState.qml runs the request and holds what parseOutputs
// answers.

var OUTPUTS_REQUEST = ["hyprctl", "-j", "monitors", "all"];
// The panel support: `systeminfo` has no JSON form in Hyprland 0.56.2.
var SUPPORT_REQUEST = ["hyprctl", "systeminfo"];

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
// mirrorOf, availableModes: [{ width, height, refresh }], currentFormat,
// bitdepth, colorManagementPreset, sdrBrightness, sdrSaturation }] } in
// Hyprland's order, `mirrorOf` the name of the output mirrored or null,
// `bitdepth` 10 while Hyprland scans out a 10-bit format, else 8, or
// { ok: false, error } with a keyed line. Hyprland names the formats it
// sets XRGB2101010, XBGR2101010, XRGB8888 and XBGR8888, else Invalid
// (formatToString in HyprCtl.cpp).
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
            bitdepth: /2101010$/.test(m.currentFormat) ? 10 : 8,
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

// The colour modes Hyprland's `cm` takes (CMType.cpp), and what each needs
// of the panel's EDID before Hyprland 0.56.2 shows it rather than sRGB
// (CMonitor::applyMonitorRuleSoft): `edid` its chromaticity, `hdr` and
// `hdredid` BT.2020 and HDR metadata, the rest BT.2020; `auto` is wide only
// at 10 bits on such a panel.
var COLOUR_MODES = ["auto", "srgb", "wide", "edid", "hdr", "hdredid", "dcip3", "dp3", "adobe"];
var HDR_MODES = ["hdr", "hdredid"];

function colourModes(panel) {
    return COLOUR_MODES.filter(function (mode) {
        if (mode === "srgb") return true;
        if (mode === "edid") return panel.chroma;
        if (HDR_MODES.indexOf(mode) !== -1) return panel.bt2020 && panel.hdr;
        return panel.bt2020;
    });
}

// The lines under each `Panel` line of `systeminfo`, in order: [field, the
// line up to its mark]; a field of "" is read for its shape alone. Hyprland
// 0.56.2 prints each mark as ✔️ or ❌ (SystemInfo::getSystemInfo).
var PANEL_LINE = /^\tPanel (.+?): [0-9]+x[0-9]+, .* -> backend \S+$/;
var PANEL_FIELDS = [["", "\t\texplicit "], ["", "\t\tedid:"], ["hdr", "\t\t\thdr "], ["chroma", "\t\t\tchroma "],
    ["bt2020", "\t\t\tbt2020 "], ["", "\t\tvrr capable "], ["", "\t\tnon-desktop "]];
var MARKS = { "✔️": true, "❌": false };

// The reply to SUPPORT_REQUEST as the capability's `support`: { ok: true,
// support: { <output name>: { hdr, chroma, bt2020, colourModes } } },
// `hdr` the EDID's HDR metadata, `chroma` its chromaticity, `bt2020` its
// BT.2020 colorimetry, or { ok: false, error } with a keyed line. Hyprland
// lists the outputs that are on and mirror nothing, the list
// `hl.get_monitors()` reads. A panel's EDID does not change while it stays
// on its connector.
function parseSupport(text) {
    var lines = String(text).split("\n");
    var i = lines.indexOf("Monitor info:");
    if (i === -1) return { ok: false, error: "refused: support=shape want=monitor-info" };
    var support = {};
    for (i += 1; i < lines.length; i++) {
        if (lines[i].trim() === "") continue;
        var panel = PANEL_LINE.exec(lines[i]);
        if (panel === null) break;
        var entry = {};
        for (var k = 0; k < PANEL_FIELDS.length; k++) {
            var line = lines[i + 1 + k];
            var prefix = PANEL_FIELDS[k][1];
            var name = PANEL_FIELDS[k][0] || prefix.trim().replace(/:$/, "");
            var bad = { ok: false, error: "refused: support=shape panel=" + shown(panel[1]) + " line=" + name };
            if (line === undefined || line.indexOf(prefix) !== 0) return bad;
            var mark = line.slice(prefix.length);
            if (prefix === "\t\tedid:" ? mark !== "" : !hasOwn(MARKS, mark)) return bad;
            if (PANEL_FIELDS[k][0] !== "") entry[PANEL_FIELDS[k][0]] = MARKS[mark];
        }
        entry.colourModes = colourModes(entry);
        support[panel[1]] = entry;
        i += PANEL_FIELDS.length;
    }
    if (lines[i] !== "State:") return { ok: false, error: "refused: support=shape line=" + shown(i < lines.length ? lines[i] : "end") };
    return { ok: true, support: support };
}

// The names of the OUTPUTS that are on and mirror nothing and that SUPPORT,
// null while unread, lists no panel for: what a read of SUPPORT_REQUEST
// would add.
function supportMissing(outputs, support) {
    return outputs.filter(function (output) {
        return !output.disabled && output.mirrorOf === null && !hasOwn(support, output.name);
    }).map(function (output) { return output.name; });
}

// SUPPORT without the panel on connector NAME, which went or was replaced:
// Hyprland posts `monitorremovedv2` and `monitoraddedv2` with
// `<id>,<name>,<description>` (CMonitor::onConnect, onDisconnect).
function supportWithout(support, eventData) {
    var name = String(eventData).split(",")[1];
    if (!isPlainObject(support) || !hasOwn(support, name)) return support;
    var out = Object.assign({}, support);
    delete out[name];
    return out;
}

// Whether RULES name a colour mode the panels must be read to judge.
function supportNeeded(rules) {
    return Object.keys(rules).some(function (id) {
        return isPlainObject(rules[id]) && rules[id].cm !== undefined && rules[id].cm !== "srgb";
    });
}

// `disabled` turns the output off; `mirror` names the output whose picture
// it shows, by identifier or connector, as Hyprland's `mirror` selector
// takes it. A rule that names an output sets both: an absent field means
// on and not mirroring. `cm` is a colour mode, `bitdepth` 8 or 10, and
// `sdrbrightness` and `sdrsaturation` the multipliers Hyprland applies to
// SDR content on an HDR output; a rule that names `cm` sets both, an absent
// one meaning Hyprland's 1. An absent colour field leaves Hyprland's. No
// rule sets `vrr`: Hyprland 0.56.2 applies a rule only when a field
// CMonitorRule::compare reads changed, and compare leaves m_vrr out.
var RULE_KEYS = ["mode", "position", "scale", "transform", "disabled", "mirror", "cm", "bitdepth", "sdrbrightness", "sdrsaturation"];
var SDR_KEYS = ["sdrbrightness", "sdrsaturation"];
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
    if (rule.disabled !== undefined && typeof rule.disabled !== "boolean") return at + ".disabled=shape want=boolean";
    if (rule.mirror !== undefined && (typeof rule.mirror !== "string" || !OUTPUT_NAME.test(rule.mirror))) return at + ".mirror=shape want=identifier";
    return colourRuleError(rule, at);
}

// Hyprland's value parsers take any number for the SDR multipliers and use
// one only above zero (CHyprRenderer's SDR settings); they apply only to an
// HDR mode.
function colourRuleError(rule, at) {
    if (rule.cm !== undefined && COLOUR_MODES.indexOf(rule.cm) === -1) return at + ".cm=shape want=colour-mode";
    if (rule.bitdepth !== undefined && rule.bitdepth !== 8 && rule.bitdepth !== 10) return at + ".bitdepth=shape want=8|10";
    for (var k = 0; k < SDR_KEYS.length; k++) {
        var value = rule[SDR_KEYS[k]];
        if (value === undefined) continue;
        if (typeof value !== "number" || !isFinite(value) || value <= 0) return at + "." + SDR_KEYS[k] + "=shape want=positive";
        if (HDR_MODES.indexOf(rule.cm) === -1) return at + "." + SDR_KEYS[k] + "=outside-hdr";
    }
    return "";
}

// The colour mode of OUTPUT's rule against the panel SUPPORT lists: one
// the panel offers. Hyprland lists no support for an output that is off or
// mirrors, and shows sRGB where the panel lacks a mode, so such an output
// is judged by Hyprland alone.
function colourOutputError(rule, output, support, at) {
    if (rule.cm === undefined || rule.cm === "srgb") return "";
    if (output.disabled) return "";
    if (output.mirrorOf !== null) return "";
    if (!isPlainObject(support)) return at + " support=unread";
    if (!hasOwn(support, output.name)) return at + " support=absent";
    if (support[output.name].colourModes.indexOf(rule.cm) === -1) return at + ".cm=unsupported cm=" + rule.cm;
    return "";
}

function ruleFor(rules, output) {
    if (hasOwn(rules, output.name)) return rules[output.name];
    return hasOwn(rules, output.identifier) ? rules[output.identifier] : null;
}

// Whether OUTPUT stays off or mirrors once RULES apply: as the rule that
// names it says, else as Hyprland lists it now.
function effectiveState(rules, output) {
    var rule = ruleFor(rules, output);
    if (rule === null) return { disabled: output.disabled, mirror: output.mirrorOf !== null };
    return { disabled: rule.disabled === true, mirror: rule.mirror !== undefined };
}

function staysOn(rules, output) {
    var state = effectiveState(rules, output);
    return !state.disabled && !state.mirror;
}

// The mirror of rule ID, judged against RULES alone: not its own output,
// not on an output it turns off, and not onto a rule that mirrors or turns
// its output off, since Hyprland mirrors no mirror.
function mirrorRuleError(rules, id, at) {
    var rule = rules[id];
    if (rule.mirror === undefined) return "";
    if (rule.mirror === id) return at + ".mirror=self";
    if (rule.disabled === true) return at + ".mirror=while-off";
    if (!hasOwn(rules, rule.mirror)) return "";
    var target = rules[rule.mirror];
    if (isPlainObject(target) && target.mirror !== undefined) return at + ".mirror=chain target=" + rule.mirror;
    if (isPlainObject(target) && target.disabled === true) return at + ".mirror=target-off target=" + rule.mirror;
    return "";
}

// The mirror of OUTPUT's rule against the listed OUTPUTS: one listed output,
// not OUTPUT itself, that stays on and does not mirror.
function mirrorOutputError(rules, rule, output, outputs, at) {
    if (rule.mirror === undefined) return "";
    var targets = outputsByKey(outputs, rule.mirror);
    if (targets.length === 0) return at + ".mirror=target-absent target=" + rule.mirror;
    if (targets.length > 1 && targets[0].identifier === rule.mirror) return at + ".mirror=target-tiled target=" + rule.mirror;
    if (targets[0].name === output.name) return at + ".mirror=self";
    var state = effectiveState(rules, targets[0]);
    if (state.mirror) return at + ".mirror=chain target=" + rule.mirror;
    if (state.disabled) return at + ".mirror=target-off target=" + rule.mirror;
    return "";
}

// Judge the saved or trial monitor RULES, keyed by output identifier. With
// OUTPUTS, this also proves every mode is offered by that output, the scale
// makes whole logical pixels, each mirror shows a listed output that stays
// on, at least one listed output stays on and mirrors nothing, and each
// colour field fits the panel SUPPORT lists.
function rulesError(rules, outputs, support) {
    if (!isPlainObject(rules)) return "refused: monitors=shape want=object";
    var ids = Object.keys(rules);
    for (var i = 0; i < ids.length; i++) {
        var id = ids[i];
        var at = "monitors." + id;
        if (!OUTPUT_NAME.test(id)) return "refused: " + at + " identifier refused";
        var rule = rules[id];
        var bad = ruleError(rule, at);
        if (bad !== "") return "refused: " + bad;
        var badMirror = mirrorRuleError(rules, id, at);
        if (badMirror !== "") return "refused: " + badMirror;
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
            var badTarget = mirrorOutputError(rules, rule, output, outputs, at);
            if (badTarget !== "") return "refused: " + badTarget;
            var badColour = colourOutputError(rule, output, support, at);
            if (badColour !== "") return "refused: " + badColour;
        }
    }
    if (Array.isArray(outputs) && !outputs.some(function (output) { return staysOn(rules, output); })) return "refused: monitors.layout=all-off";
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

function layoutError(rules, outputs, support) {
    var bad = rulesError(rules, outputs, support);
    if (bad !== "") return bad;
    var rects = [];
    outputs.filter(function (output) { return staysOn(rules, output); }).forEach(function (output) {
        var rect = logicalRect(normalizedRule(output, ruleFor(rules, output) || {}));
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

function ruleFields(id, rule) {
    var fields = ["output = " + luaString(id)];
    if (rule.mode !== undefined) fields.push("mode = " + luaString(modeText(rule.mode)));
    if (rule.position !== undefined) fields.push("position = " + luaString(positionText(rule.position)));
    if (rule.scale !== undefined) fields.push("scale = " + luaNumber(rule.scale));
    if (rule.transform !== undefined) fields.push("transform = " + rule.transform);
    if (rule.cm !== undefined) fields.push("cm = " + luaString(rule.cm));
    if (rule.bitdepth !== undefined) fields.push("bitdepth = " + luaNumber(rule.bitdepth));
    SDR_KEYS.forEach(function (key) { if (rule[key] !== undefined) fields.push(key + " = " + luaNumber(rule[key])); });
    return fields;
}

function monitorCall(fields) {
    return "hl.monitor({ " + fields.join(", ") + " })";
}

// The layer's rule for ID: `disabled` is left to the guard block, which
// turns the output off only while another output stays on.
function ruleLine(id, rule) {
    var fields = ruleFields(id, rule);
    if (rule.mirror !== undefined) fields.push("mirror = " + luaString(rule.mirror));
    return monitorCall(fields);
}

// A trial or restore rule for ID: `disabled` and `mirror` written, and the
// SDR multipliers beside a `cm`, so an eval undoes the rule an earlier eval
// merged into, and no handler, since every eval would add one. A restore
// names every colour field its trial named. The judge has proved another
// output stays on.
function evalLine(id, rule) {
    var fields = ruleFields(id, rule);
    if (rule.cm !== undefined) SDR_KEYS.forEach(function (key) { if (rule[key] === undefined) fields.push(key + " = 1"); });
    fields.push("disabled = " + (rule.disabled === true ? "true" : "false"));
    fields.push("mirror = " + (rule.mirror === undefined ? "\"\"" : luaString(rule.mirror)));
    return monitorCall(fields);
}

function luaList(ids) {
    return "{ " + ids.map(luaString).join(", ") + " }";
}

// The one reload that turns outputs back on, for the layer's guard and a
// trial's restore alike: once no output but FALLBACK is lit and GATE, a Lua
// condition, holds; "" for none. A rule set while only FALLBACK
// is lit never applies, and a reload reruns the saved layer. Hyprland 0.56.2
// turns outputs off and on one by one in list order inside
// ensureMonitorStatus (MonitorRuleManager.cpp), posting `monitor.removed`
// for each output a rule turns off, so the outputs are read from a oneshot
// timer, which the event loop runs once that pass has returned; any timeout
// above zero does (docs/architecture/hyprland.md § Configuration layer).
function relightLines(gate) {
    return [
        "hl.timer(function()",
        "    -- A rule set from a handler waits for a render tick that never comes with only FALLBACK left, so a reload turns the outputs back on; it goes when Hyprland applies such a rule at once.",
        "    for _, m in ipairs(hl.get_monitors()) do",
        "        if m.name ~= \"FALLBACK\" then return end",
        "    end",
        gate === "" ? "    hl.exec_cmd(\"hyprctl reload\")" : "    if " + gate + " then hl.exec_cmd(\"hyprctl reload\") end",
        "end, { timeout = 1, type = \"oneshot\" })"
    ];
}

// The layer turns an output off only while another output stays on, so a
// laptop that starts or is left undocked never stays dark. The layer runs
// before Hyprland lists any output at start, so the check runs again as each
// output comes; Hyprland 0.56.2 lists enabled outputs that mirror nothing,
// or FALLBACK when none is left, in `hl.get_monitors()`, each with the short
// description a `desc:` identifier names (docs/architecture/hyprland.md § Configuration layer).
function guardLines(rules, ids) {
    var off = ids.filter(function (id) { return rules[id].disabled === true; });
    if (off.length === 0) return [];
    var mirroring = ids.filter(function (id) { return rules[id].mirror !== undefined; });
    return [
        "do",
        "    local vgs_monitors_off = " + luaList(off),
        "    local vgs_monitors_mirroring = " + luaList(mirroring),
        "    local vgs_monitors_applied = false",
        "    local function vgs_monitors_named(m, ids)",
        "        for _, id in ipairs(ids) do",
        "            if m.name == id or \"desc:\" .. m.description == id then return true end",
        "        end",
        "        return false",
        "    end",
        "    local function vgs_monitors_others_on()",
        "        for _, m in ipairs(hl.get_monitors()) do",
        "            if m.name ~= \"FALLBACK\" and not vgs_monitors_named(m, vgs_monitors_off) and not vgs_monitors_named(m, vgs_monitors_mirroring) then return true end",
        "        end",
        "        return false",
        "    end",
        "    local function vgs_monitors_apply()",
        "        if vgs_monitors_applied or not vgs_monitors_others_on() then return end",
        "        for _, id in ipairs(vgs_monitors_off) do " + monitorCall(["output = id", "disabled = true"]) + " end",
        "        vgs_monitors_applied = true",
        "    end",
        "    vgs_monitors_apply()",
        "    hl.on(\"monitor.added\", vgs_monitors_apply)",
        "    hl.on(\"monitor.removed\", function()"
    ].concat(relightLines("vgs_monitors_applied").map(function (line) { return "        " + line; }), [
        "    end)",
        "end"
    ]);
}

function rulesLines(rules) {
    var bad = rulesError(rules, null);
    if (bad !== "") return { ok: false, error: bad, lines: [] };
    var ids = Object.keys(rules).sort();
    return { ok: true, lines: ids.map(function (id) { return ruleLine(id, rules[id]); }).concat(guardLines(rules, ids)) };
}

// A trial of RULES over the owner's SAVED rules: { ok: true, lua, kept,
// restore, restoreRules }, `kept` the set Keep saves, SAVED with RULES over
// them, `restore` the Lua that puts back the outputs RULES name as OUTPUTS
// list them, and the reload once none but FALLBACK is lit, or { ok: false,
// error }. RULES are judged against the listed OUTPUTS and the panel
// SUPPORT, and `kept` as the settings write judges it, so a trial never
// shows what Keep cannot save.
function trialPlan(saved, rules, outputs, support) {
    var bad = layoutError(rules, outputs, support);
    if (bad !== "") return { ok: false, error: bad };
    var kept = Object.assign({}, saved, rules);
    var badKept = rulesError(kept, null);
    if (badKept !== "") return { ok: false, error: badKept };
    var trial = rulesLua(rules);
    if (!trial.ok) return trial;
    var restoreRules = captureRules(outputs, rules);
    var restore = rulesLua(restoreRules);
    if (!restore.ok) return restore;
    return { ok: true, lua: trial.lua, kept: kept, restore: restore.lua + "\n" + relightLines("").join("\n"), restoreRules: restoreRules };
}

function rulesLua(rules) {
    var bad = rulesError(rules, null);
    if (bad !== "") return { ok: false, error: bad };
    return { ok: true, lua: Object.keys(rules).sort().map(function (id) { return evalLine(id, rules[id]); }).join("\n") };
}

// The identifier that names the output NAME, or NAME itself where a tiled
// group shares that identifier.
function mirrorTarget(outputs, name) {
    var target = outputs.filter(function (output) { return output.name === name; })[0];
    return outputs.filter(function (output) { return output.identifier === target.identifier; }).length > 1 ? name : target.identifier;
}

function liveSdr(output) {
    return { sdrbrightness: output.sdrBrightness, sdrsaturation: output.sdrSaturation };
}

// The outputs RULES name as OUTPUTS list them, by connector: each one's
// mode, position, scale, orientation, off and mirror state, and each colour
// field its rule names, so a restore sets back what the trial set and
// leaves the rest as Hyprland holds it.
function captureRules(outputs, rules) {
    var selected = {};
    Object.keys(rules).forEach(function (id) {
        var named = rules[id];
        outputsByKey(outputs, id).forEach(function (output) {
            var rule = {
                mode: modeOf(output),
                position: positionOf(output),
                scale: output.scale,
                transform: output.transform
            };
            if (output.width <= 0 || output.height <= 0) delete rule.mode;
            if (output.disabled) rule.disabled = true;
            if (output.mirrorOf !== null) rule.mirror = mirrorTarget(outputs, output.mirrorOf);
            if (named.cm !== undefined) {
                rule.cm = output.colorManagementPreset;
                var live = liveSdr(output);
                if (HDR_MODES.indexOf(rule.cm) !== -1) SDR_KEYS.forEach(function (key) { if (live[key] > 0) rule[key] = live[key]; });
            }
            if (named.bitdepth !== undefined) rule.bitdepth = output.bitdepth;
            selected[output.name] = rule;
        });
    });
    return selected;
}

// Whether the colour of OUTPUT, on and mirroring nothing, differs from the
// fields RULE names. Hyprland lists the colour mode it shows, so a mode it
// fell back from reads as changed; `auto` shows wide or sRGB.
function colourOverridden(rule, output) {
    if (output.disabled) return false;
    if (output.mirrorOf !== null) return false;
    if (rule.cm !== undefined) {
        var shows = rule.cm === "auto" ? ["wide", "srgb"] : [rule.cm];
        if (shows.indexOf(output.colorManagementPreset) === -1) return true;
        var live = liveSdr(output);
        if (HDR_MODES.indexOf(rule.cm) !== -1 && SDR_KEYS.some(function (key) {
            return Math.abs((rule[key] === undefined ? 1 : rule[key]) - live[key]) > 0.0001;
        })) return true;
    }
    return rule.bitdepth !== undefined && rule.bitdepth !== output.bitdepth;
}

// Whether OUTPUT, as Hyprland lists it among OUTPUTS, differs from the saved
// RULE. An output the rule turns off reads as kept while no other output is
// on, since the layer then leaves it on.
function overridden(rule, output, outputs) {
    var current = normalizedRule(output, {});
    var saved = normalizedRule(output, rule);
    var othersOn = outputs.some(function (other) { return other.name !== output.name && !other.disabled && other.mirrorOf === null; });
    var mirrored = rule.mirror === undefined ? output.mirrorOf === null
        : output.mirrorOf !== null && outputsByKey(outputs, rule.mirror).some(function (target) { return target.name === output.mirrorOf; });
    return (rule.disabled === true ? othersOn && !output.disabled : output.disabled)
        || !mirrored
        || !sameMode(saved.mode, current.mode)
        || Math.abs(saved.scale - current.scale) > 0.000001
        || saved.transform !== current.transform
        || saved.position.x !== current.position.x
        || saved.position.y !== current.position.y
        || colourOverridden(rule, output);
}
