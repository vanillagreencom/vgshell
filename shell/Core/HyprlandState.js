.pragma library
.import "PluginLogic.js" as Logic
.import "HyprlandLayer.js" as Layer
.import "Dispatch.js" as Dispatch

// Pure readings behind the `hyprland` capability: Hyprland's input devices,
// the options the layer wrote that read back otherwise, the values the
// user's configuration gave them, the keys bound by something other than
// the layer, the file and line where the user's configuration binds each,
// and the edit that takes such a line out of its file and puts it back,
// which bin/vgshell-hypr-judge runs. HyprlandState.qml runs each request
// and holds what these answer; scripts/test-hyprland-state.js runs this file
// under node. Each reply is in the shape Hyprland v0.56.2 prints
// (src/debug/HyprCtl.cpp).

var DEVICES_REQUEST = ["hyprctl", "-j", "devices"];
var BINDS_REQUEST = ["hyprctl", "-j", "binds"];
var KEY_OPTIONS = ["kb_file", "kb_rules", "kb_model", "kb_layout", "kb_variant", "kb_options"];
var KEYS_REQUEST = ["hyprctl", "--batch", "j/devices;" + KEY_OPTIONS.map(function (name) { return "j/getoption input:" + name; }).join(";")];

// The device owner supplies the resolver's layout. Missing or ambiguous main
// keyboards cannot establish the keycode used by a compositor binding.
function keyRequest(devices, keys) {
    if (devices === null || !Array.isArray(keys) || keys.length === 0 || keys.length > 64)
        return { ok: false, error: "refused: keymap=unavailable" };
    var mains = devices.keyboards.filter(function (keyboard) { return keyboard.main; });
    if (mains.length !== 1 || mains[0].activeLayoutIndex === null)
        return { ok: false, error: "refused: keymap=main-keyboard" };
    var normalized = [];
    for (var key of keys) {
        var read = Logic.hyprlandKey(key);
        if (!read.ok) return { ok: false, error: "refused: keymap=key " + read.error };
        normalized.push(read.key);
    }
    var kb = mains[0];
    return { ok: true, request: { keyboard: { layout: kb.layout, variant: kb.variant,
        options: kb.options, activeLayoutIndex: kb.activeLayoutIndex }, keys: normalized } };
}

// Native codes use the active main keyboard. Hyprland's virtual-keyboard
// translation uses the global input map's first group instead. Both maps
// come from one compositor snapshot; unsupported custom maps are refused.
function keyFacts(text, keys) {
    var parts = Dispatch.batchReplies(text, KEY_OPTIONS.length + 1, "key facts");
    if (!parts.ok) return parts;
    var devices = devicesState(parts.parts[0]);
    if (!devices.ok) return devices;
    var native = keyRequest(devices.devices, keys);
    if (!native.ok) return native;
    var main = devicesRead(parts.parts[0]).value.keyboards.find(function (row) { return row.main; });
    if (main.rules !== "" && main.rules !== "evdev") return { ok: false, error: "refused: keymap=native-rules" };
    if (main.model !== "" && main.model !== "pc105") return { ok: false, error: "refused: keymap=native-model" };
    var global = {};
    for (var i = 0; i < KEY_OPTIONS.length; i++) {
        var read = parsed(parts.parts[i + 1]);
        if (!read.ok || read.value === null || typeof read.value !== "object" || Array.isArray(read.value)
                || read.value.option !== "input:" + KEY_OPTIONS[i] || typeof read.value.str !== "string")
            return { ok: false, error: "refused: keymap=option name=" + KEY_OPTIONS[i] };
        global[KEY_OPTIONS[i]] = read.value.str === "[[EMPTY]]" ? "" : read.value.str;
    }
    if (global.kb_file !== "") return { ok: false, error: "refused: keymap=custom-file" };
    if (global.kb_rules !== "" && global.kb_rules !== "evdev") return { ok: false, error: "refused: keymap=rules" };
    if (global.kb_model !== "" && global.kb_model !== "pc105") return { ok: false, error: "refused: keymap=model" };
    if (global.kb_layout === "") return { ok: false, error: "refused: keymap=layout" };
    var translation = { keyboard: { layout: global.kb_layout, variant: global.kb_variant,
        options: global.kb_options, activeLayoutIndex: 0 }, keys: native.request.keys };
    return { ok: true, devices: devices.devices, request: { keyboard: native.request.keyboard,
        keys: native.request.keys, translation: translation } };
}

function resolvedKeys(text, count, requireTranslation) {
    var read = parsed(text);
    if (!read.ok || !read.value || read.value.ok !== true || !Array.isArray(read.value.keys)
            || read.value.keys.length !== count)
        return { ok: false, error: "refused: keymap=unresolved" };
    if (requireTranslation && !Object.prototype.hasOwnProperty.call(read.value, "translation"))
        return { ok: false, error: "refused: keymap=translation" };
    var lists = [read.value.keys];
    if (Object.prototype.hasOwnProperty.call(read.value, "translation")) {
        if (!Array.isArray(read.value.translation) || read.value.translation.length !== count)
            return { ok: false, error: "refused: keymap=translation" };
        lists.push(read.value.translation);
    }
    for (var list of lists) {
        for (var key of list) {
            if (!key || !Array.isArray(key.modifiers) || !key.modifiers.every(function (m) { return Logic.HYPRLAND_MODIFIERS.indexOf(m) !== -1; })
                    || !Number.isInteger(key.keycode) || key.keycode < 8 || typeof key.keysym !== "string" || key.keysym.length === 0
                    || !Number.isInteger(key.codepoint) || key.codepoint < 0 || key.codepoint > 0x10ffff
                    || key.codepoint >= 0xd800 && key.codepoint <= 0xdfff)
                return { ok: false, error: "refused: keymap=reply" };
        }
    }
    return read.value;
}

// hyprctl names no device class, so a pointer is a touchpad when its name
// says so.
var TOUCHPAD = /touchpad|trackpad/i;

// The modifier bits of a bind's `modmask` a Hyprland key can name, in
// src/devices/IKeyboard.hpp; Caps Lock, Num Lock (MOD2), MOD3 and MOD5 have
// no name in PluginLogic.hyprlandKey.
var MODIFIER_BITS = [["SHIFT", 1], ["CTRL", 4], ["ALT", 8], ["SUPER", 64]];
var NAMED_BITS = 1 | 4 | 8 | 64;

function parsed(text) {
    try {
        return { ok: true, value: JSON.parse(text) };
    } catch (e) {
        return { ok: false, error: String(e.message || e) };
    }
}

// All consumers accept Hyprland's bare inactive-layout sentinel through
// this reader, including the raw main-device fields keyFacts needs.
function devicesRead(text) {
    return parsed(String(text).replace(/("active_layout_index": )none\b/g, "$1null"));
}

// `hyprctl -j devices` as the capability's `devices`: { mice: [{ name,
// touchpad }], keyboards: [{ name, layout, variant, options, activeKeymap,
// activeLayoutIndex, main }] }, in Hyprland's order, or { ok: false, error }
// with a keyed line. Hyprland prints a keyboard with no active layout's
// index as a bare `none`, which is no JSON, so it reads as null.
function devicesState(text) {
    var read = devicesRead(text);
    if (!read.ok) return { ok: false, error: "refused: devices=unparsed " + read.error };
    var d = read.value;
    if (d === null || typeof d !== "object" || !Array.isArray(d.mice) || !Array.isArray(d.keyboards))
        return { ok: false, error: "refused: devices=shape want=mice,keyboards" };
    var mice = [];
    for (var m = 0; m < d.mice.length; m++) {
        if (typeof d.mice[m].name !== "string") return { ok: false, error: "refused: devices=shape mouse=" + m };
        mice.push({ name: d.mice[m].name, touchpad: TOUCHPAD.test(d.mice[m].name) });
    }
    var keyboards = [];
    for (var k = 0; k < d.keyboards.length; k++) {
        var kb = d.keyboards[k];
        if (typeof kb.name !== "string" || typeof kb.layout !== "string" || typeof kb.variant !== "string" || typeof kb.options !== "string"
            || typeof kb.active_keymap !== "string" || typeof kb.main !== "boolean"
            || !(kb.active_layout_index === null || Number.isInteger(kb.active_layout_index)))
            return { ok: false, error: "refused: devices=shape keyboard=" + k };
        keyboards.push({ name: kb.name, layout: kb.layout, variant: kb.variant, options: kb.options, activeKeymap: kb.active_keymap, activeLayoutIndex: kb.active_layout_index, main: kb.main });
    }
    return { ok: true, devices: { mice: mice, keyboards: keyboards } };
}

// The touchpad names of DEVICES, devicesState's `devices`, in Hyprland's
// order; null while DEVICES is unread.
function touchpads(devices) {
    if (devices === null) return null;
    return devices.mice.filter(function (mouse) { return mouse.touchpad; }).map(function (mouse) { return mouse.name; });
}

// The options of WRITTEN, the layer's `options` result, that `getoption`
// reads: every one but the per-device row.
function readable(written) {
    return written.filter(function (option) { return Layer.OPTIONS[option.path].device === undefined; });
}

// The OPTIONS paths `getoption` reads: every one but the per-device row.
var READABLE = Object.keys(Layer.OPTIONS).filter(function (path) { return Layer.OPTIONS[path].device === undefined; });

// The one `hyprctl --batch` argv that reads every READABLE option: the
// layer's written ones back, and the rest for a plugin that sets none.
var OPTIONS_REQUEST = ["hyprctl", "--batch", READABLE.map(function (path) { return "j/getoption " + path; }).join(";")];

// The reply field getoption prints a value of each OPTIONS type under.
var REPLY_FIELD = { bool: "bool", int: "int", float: "float", string: "str" };

// Whether READ, the value getoption printed, is not WANT, the value the
// layer wrote. getoption prints a float to six places, so two floats within
// a millionth of each other are the same value.
function differs(type, want, read) {
    if (type === "float") return typeof read !== "number" || Math.abs(read - want) > 0.000001;
    return read !== want;
}

// Hyprland's value of each READABLE option, from the reply to
// OPTIONS_REQUEST: { ok: true, values: { path: value }, errors: [...] },
// an option it could not read left out of `values` with a keyed line in
// `errors`, or { ok: false, error } with a keyed line for a whole-batch
// failure.
function optionValues(text) {
    var replies = Dispatch.batchReplies(text, READABLE.length, "options");
    if (!replies.ok) return { ok: false, error: replies.error };
    var values = {};
    var errors = [];
    for (var i = 0; i < READABLE.length; i++) {
        var path = READABLE[i];
        var read = parsed(replies.parts[i]);
        var field = REPLY_FIELD[Layer.OPTIONS[path].type];
        if (!read.ok || read.value === null || typeof read.value !== "object" || read.value.option !== path || !Object.prototype.hasOwnProperty.call(read.value, field)) {
            errors.push("refused: options=unread path=" + path + " reply=" + JSON.stringify(replies.parts[i].slice(0, 120)));
            continue;
        }
        values[path] = read.value[field];
    }
    return { ok: true, values: values, errors: errors };
}

// The options of WRITTEN whose value Hyprland reads back otherwise, from
// VALUES, optionValues' `values`: [{ id, path }] in WRITTEN's order. An
// option VALUES does not hold differs, since no written value is undefined.
function overridden(written, values) {
    return readable(written).filter(function (row) { return differs(Layer.OPTIONS[row.path].type, row.value, values[row.path]); })
        .map(function (row) { return { id: row.id, path: row.path }; });
}

// Hyprland's value, from VALUES, optionValues' `values`, of each option
// OPTIONS, a manifest's `hyprland.options`, maps a setting to that WRITTEN
// holds for no row of plugin ID: what applies while the plugin sets none.
// { path: value }.
function unwrittenValues(options, written, id, values) {
    var mine = written.filter(function (row) { return row.id === id; }).map(function (row) { return row.path; });
    var out = {};
    Object.keys(options).forEach(function (setting) {
        var path = options[setting];
        if (mine.indexOf(path) === -1 && Object.prototype.hasOwnProperty.call(values, path)) out[path] = values[path];
    });
    return out;
}

// The one `hyprctl eval` argv that asks the layer for the user's values
// (HyprlandLayer.USER_VALUES). An eval prints only an error's text, so
// the request raises the
// layer's answer; a session whose hyprland.lua does not load the layer has
// no table and no user value.
var USER_VALUES_REQUEST = ["hyprctl", "eval", "error(hl." + Layer.USER_VALUES.table + " == nil and \"" + Layer.USER_VALUES.key + "=[]\" or hl." + Layer.USER_VALUES.table + "." + Layer.USER_VALUES.verb + "(), 0)"];

// The JavaScript type of a value of each OPTIONS type.
var VALUE_TYPE = { bool: "boolean", int: "number", float: "number", string: "string" };

// The value the user's configuration gave each option of WRITTEN, from the
// reply to USER_VALUES_REQUEST: { ok: true, values: [{ id, path, value }] }
// in WRITTEN's order, or { ok: false, error } with a keyed line. A path the
// reply names that WRITTEN does not hold belongs to a layer since replaced.
function userValues(written, text) {
    var key = Layer.USER_VALUES.key + "=";
    var line = String(text || "").split("\n").filter(function (l) { return l.indexOf(key) !== -1; })[0];
    if (line === undefined) return { ok: false, error: "refused: user-values=unread reply=" + JSON.stringify(String(text || "").slice(0, 120)) };
    var read = parsed(line.slice(line.indexOf(key) + key.length));
    if (!read.ok) return { ok: false, error: "refused: user-values=unparsed " + read.error };
    if (!Array.isArray(read.value)) return { ok: false, error: "refused: user-values=shape want=list" };
    var named = Object.create(null);
    for (var i = 0; i < read.value.length; i++) {
        var row = read.value[i];
        if (row === null || typeof row !== "object" || typeof row.path !== "string")
            return { ok: false, error: "refused: user-values=shape row=" + i };
        named[row.path] = row;
    }
    var rows = readable(written);
    var out = [];
    for (var r = 0; r < rows.length; r++) {
        var path = rows[r].path;
        if (named[path] === undefined) continue;
        if (typeof named[path].value !== VALUE_TYPE[Layer.OPTIONS[path].type])
            return { ok: false, error: "refused: user-values=shape path=" + path + " want=" + Layer.OPTIONS[path].type };
        out.push({ id: rows[r].id, path: path, value: named[path].value });
    }
    return { ok: true, values: out };
}

// The key PluginLogic.hyprlandKey writes for a bind of MODMASK on KEY, the
// keysym name Hyprland prints, or on KEYCODE where KEY is empty, as a
// keycode bind has it; null where no such key names it: a modifier outside
// SHIFT, CTRL, ALT and SUPER, or a name the key judge does not take.
function boundKey(modmask, key, keycode) {
    if ((modmask & ~NAMED_BITS) !== 0) return null;
    var mods = MODIFIER_BITS.filter(function (row) { return (modmask & row[1]) !== 0; }).map(function (row) { return row[0]; });
    var name = key !== "" ? key : keycode > 0 ? "code:" + keycode : "";
    var read = Logic.hyprlandKey(mods.concat([name]).join("+"));
    return read.ok ? read.key : null;
}

// The keys `hyprctl -j binds` binds in the default submap, which it names
// "" or "default", by something
// other than the layer: each bind whose description is not one of
// DESCRIPTIONS, the layer's `binds`, as boundKey writes it, sorted, each
// once. A keycode bind, which binds -j prints with an empty key, is its
// keycode. A bind boundKey cannot name is left out: a mouse bind or a
// modifier outside SHIFT, CTRL, ALT and SUPER. { ok: true, keys } or
// { ok: false, error } with a keyed line.
function foreignBinds(text, descriptions) {
    var read = parsed(text);
    if (!read.ok) return { ok: false, error: "refused: binds=unparsed " + read.error };
    if (!Array.isArray(read.value)) return { ok: false, error: "refused: binds=shape want=list" };
    var keys = [];
    for (var i = 0; i < read.value.length; i++) {
        var bind = read.value[i];
        if (bind === null || typeof bind !== "object" || typeof bind.submap !== "string" || typeof bind.key !== "string"
            || typeof bind.description !== "string" || !Number.isInteger(bind.modmask) || !Number.isInteger(bind.keycode))
            return { ok: false, error: "refused: binds=shape bind=" + i };
        if ((bind.submap !== "" && bind.submap !== "default") || descriptions.indexOf(bind.description) !== -1) continue;
        var key = boundKey(bind.modmask, bind.key, bind.keycode);
        if (key !== null && keys.indexOf(key) === -1) keys.push(key);
    }
    return { ok: true, keys: keys.sort() };
}

// The one `hyprctl eval` argv that asks the layer where the user's
// configuration binds each key (HyprlandLayer.USER_BINDS), raised as
// USER_VALUES_REQUEST raises its answer; a session whose hyprland.lua does
// not load the layer has no record.
var USER_BINDS_REQUEST = ["hyprctl", "eval", "error(hl." + Layer.USER_BINDS.table + " == nil and \"" + Layer.USER_BINDS.key + "=[]\" or hl." + Layer.USER_BINDS.table + "." + Layer.USER_BINDS.verb + "(), 0)"];

// The binds the user's configuration makes, from the reply to
// USER_BINDS_REQUEST: { ok: true, binds: [{ key, file, line, text,
// removable }] } in the order they were made, each `key` as boundKey
// writes it, or { ok: false, error } with a keyed line. A bind boundKey
// cannot name is left out. `removable` says the line is one whole call
// that binds that key (bindCall) in a file under HYPR_DIR
// (bindFileEditable), the only line `vgshell hypr remove-bind` takes.
function userBinds(text, hyprDir) {
    var marker = Layer.USER_BINDS.key + "=";
    var line = String(text || "").split("\n").filter(function (l) { return l.indexOf(marker) !== -1; })[0];
    if (line === undefined) return { ok: false, error: "refused: user-binds=unread reply=" + JSON.stringify(String(text || "").slice(0, 120)) };
    var read = parsed(line.slice(line.indexOf(marker) + marker.length));
    if (!read.ok) return { ok: false, error: "refused: user-binds=unparsed " + read.error };
    if (!Array.isArray(read.value)) return { ok: false, error: "refused: user-binds=shape want=list" };
    var out = [];
    for (var i = 0; i < read.value.length; i++) {
        var row = read.value[i];
        if (row === null || typeof row !== "object" || typeof row.file !== "string" || !Number.isInteger(row.line) || row.line < 1
            || typeof row.text !== "string" || !Number.isInteger(row.modmask) || typeof row.key !== "string" || !Number.isInteger(row.keycode))
            return { ok: false, error: "refused: user-binds=shape row=" + i };
        var key = boundKey(row.modmask, row.key, row.keycode);
        if (key === null) continue;
        out.push({ key: key, file: row.file, line: row.line, text: row.text, removable: bindCall(row.text) === key && bindFileEditable(row.file, hyprDir) });
    }
    return { ok: true, binds: out };
}

// FILE as a notice names it: under HOME, from `~`.
function bindPlace(file, home) {
    return home !== "" && file.indexOf(home + "/") === 0 ? "~" + file.slice(home.length) : file;
}

// A line that is one whole `hl.bind` call: the key string first, in quotes
// that hold no escape, then the rest of the call, then at most a `;` and a
// comment. Removing such a line removes one bind and leaves the file's
// other statements as they were.
var BIND_CALL = /^\s*hl\.bind\s*\(\s*(?:"([^"\\]*)"|'([^'\\]*)')/;

// The key, as PluginLogic.hyprlandKey writes it, that TEXT, one line with
// no line break, binds when it is one whole `hl.bind` call; else null. A
// long bracket or a comment inside the call, which could hide its end, is
// no whole call.
function bindCall(text) {
    var head = BIND_CALL.exec(text);
    if (head === null) return null;
    var depth = 1;
    var quote = null;
    var i = head[0].length;
    for (; i < text.length && depth > 0; i++) {
        var c = text[i];
        if (quote !== null) {
            if (c === "\\") i++;
            else if (c === quote) quote = null;
        } else if (c === "\"" || c === "'") {
            quote = c;
        } else if (c === "-" && text[i + 1] === "-" || c === "[" && /^\[=*\[/.test(text.slice(i))) {
            return null;
        } else if ("({[".indexOf(c) !== -1) {
            depth++;
        } else if (")}]".indexOf(c) !== -1) {
            depth--;
        }
    }
    if (depth !== 0 || !/^\s*;?\s*(?:--(?!\[=*\[).*)?\r?$/.test(text.slice(i))) return null;
    var key = Logic.hyprlandKey(head[1] !== undefined ? head[1] : head[2]);
    return key.ok ? key.key : null;
}

// TEXT's lines, each with its line break; a last line without one is kept
// as it is, so joining them gives TEXT back byte for byte.
function fileLines(text) {
    return text.match(/[^\n]*\n|[^\n]+$/g) || [];
}

// TEXT, a file's bytes, without line LINE, which must be one whole
// `hl.bind` call binding KEY (bindCall): { ok: true, text, undo }, or
// { ok: false, error } with a keyed line. UNDO is what restoreBindLine
// takes: { text, before, after }, the removed line and the lines on either
// side of it, each with its line break, null at the file's start or end.
function removeBindLine(text, line, key) {
    var lines = fileLines(text);
    if (!Number.isInteger(line) || line < 1 || line > lines.length)
        return { ok: false, error: "refused: user-bind=no-line line=" + line + " lines=" + lines.length };
    if (bindCall(lines[line - 1].replace(/\n$/, "")) !== key)
        return { ok: false, error: "refused: user-bind=not-whole line=" + line + " key=" + key };
    var undo = { text: lines[line - 1], before: line > 1 ? lines[line - 2] : null, after: line < lines.length ? lines[line] : null };
    lines.splice(line - 1, 1);
    return { ok: true, text: lines.join(""), undo: undo };
}

// TEXT with UNDO's line, a removeBindLine answer, back between the two
// lines it stood between: { ok: true, text, line } or { ok: false, error }
// with a keyed line. The line must still be one whole `hl.bind` call. LINE
// is where the caller expects it; it decides only among several places
// where those two lines still meet, and where they meet nowhere, or in
// several places none of them LINE, the file stays unchanged rather than
// take the line in another place.
function restoreBindLine(text, line, undo) {
    var lines = fileLines(text);
    var nullOrString = function (v) { return v === null || typeof v === "string"; };
    if (undo === null || typeof undo !== "object" || typeof undo.text !== "string" || !/^[^\n]*\n?$/.test(undo.text)
        || bindCall(undo.text.replace(/\n$/, "")) === null || !nullOrString(undo.before) || !nullOrString(undo.after))
        return { ok: false, error: "refused: user-bind=not-whole line=" + line };
    var places = [];
    for (var at = 1; at <= lines.length + 1; at++) {
        if ((undo.before === null ? at === 1 : lines[at - 2] === undo.before)
            && (undo.after === null ? at === lines.length + 1 : lines[at - 1] === undo.after))
            places.push(at);
    }
    var place = places.indexOf(line) !== -1 ? line : places.length === 1 ? places[0] : null;
    if (place === null)
        return { ok: false, error: "refused: user-bind=moved line=" + line + " places=" + places.length };
    lines.splice(place - 1, 0, undo.text);
    return { ok: true, text: lines.join(""), line: place };
}

// Whether FILE, an absolute path, names a user file a bind line may be
// taken out of: a `.lua` file under HYPR_DIR, the user's Hyprland
// directory, through no `.` or `..` segment.
function bindFileEditable(file, hyprDir) {
    return file.indexOf(hyprDir + "/") === 0 && /\.lua$/.test(file) && !/\/\.\.?(\/|$)/.test(file);
}
