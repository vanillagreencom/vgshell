.pragma library

// The schema's `list` type and the pads a manifest's `hyprland.pads` names:
// the judge of a list entry and of its value, the Select models of its
// items' `optionsFrom` fields, the judge of `hyprland.pads` and the pads'
// expansion into binds and layer data. Pure: no QML object, no I/O, so
// scripts/test-pads.js runs it under node. PluginLogic.js is its one
// importer and hands it the judges it owns (schemaError, settingError,
// hyprlandKey, NAME_PATTERN), so a name, a key or a flat entry is judged
// in one place. HyprlandLayer.js renders the pads (docs/architecture/hyprland.md).

function hasOwn(obj, key) {
    return obj !== null && typeof obj === "object" && Object.prototype.hasOwnProperty.call(obj, key);
}

function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

// ------------------------------------------------------------- list type

// The first defect of schema entry ENTRY at AT for its list keys, or "". A
// `list` entry holds `items`, a non-empty flat schema of its items' fields,
// and `defaults`, the value of each of those fields a new item takes, which
// SCHEMA_ERROR, PluginLogic's flat judge, judges as it judges a manifest's
// schema and settings, so an item field is any flat entry and nothing more:
// no `list` inside a list, and no field named `name`, which every item
// holds as its unique NAME_PATTERN name. `defaults` names no other field.
// Any other entry carries neither key.
function listEntryError(entry, at, status, schemaError) {
    if (entry.type !== "list")
        return entry.items !== undefined || entry.defaults !== undefined ? at + ".items and .defaults need type list" : "";
    if (!isPlainObject(entry.items) || Object.keys(entry.items).length === 0)
        return at + ".items must be a non-empty object";
    if (!isPlainObject(entry.defaults))
        return at + ".defaults must be an object";
    var fields = Object.keys(entry.items);
    for (var i = 0; i < fields.length; i++) {
        if (fields[i] === "name")
            return at + ".items.name is refused: every item holds its name";
        if (isPlainObject(entry.items[fields[i]]) && entry.items[fields[i]].type === "list")
            return at + ".items." + fields[i] + " must not be a list";
    }
    var extra = Object.keys(entry.defaults).filter(function (key) { return !hasOwn(entry.items, key); });
    if (extra.length > 0)
        return at + ".defaults." + extra[0] + " names no item field";
    var bad = schemaError(entry.items, entry.defaults, status);
    return bad === "" ? "" : at + ".items: " + bad;
}

// Why VALUE does not fit list entry ENTRY, or "": a list of objects, each
// with a NAME_PATTERN `name` no other item holds and every field of
// `items` with a value SETTING_ERROR, PluginLogic's flat judge, accepts,
// and no other key. The reason names the item by its index and the field.
function listValueError(entry, value, settingError, namePattern) {
    if (!Array.isArray(value)) return "want=list";
    var names = [];
    var fields = Object.keys(entry.items);
    for (var i = 0; i < value.length; i++) {
        var item = value[i];
        var at = "item=" + i;
        if (!isPlainObject(item)) return at + " want=object";
        if (typeof item.name !== "string" || !namePattern.test(item.name)) return at + " want=name";
        if (names.indexOf(item.name) !== -1) return at + " name=" + item.name + " want=unique";
        names.push(item.name);
        var keys = Object.keys(item);
        for (var k = 0; k < keys.length; k++) {
            if (keys[k] !== "name" && !hasOwn(entry.items, keys[k])) return at + " field=" + keys[k] + " undeclared";
        }
        for (var f = 0; f < fields.length; f++) {
            if (!hasOwn(item, fields[f])) return at + " field=" + fields[f] + " missing";
            var bad = settingError(entry.items[fields[f]], item[fields[f]]);
            if (bad !== "") return at + " field=" + fields[f] + " " + bad;
        }
    }
    return "";
}

// The Select models of list entry ENTRY's `optionsFrom` fields for VALUE,
// one { field: model } per item in order, MODEL(statusKey, configured)
// being PluginLogic's model of one string setting; none for a value that
// is no list.
function listChoices(entry, value, model) {
    var fields = Object.keys(entry.items).filter(function (key) { return entry.items[key].optionsFrom !== undefined; });
    return (Array.isArray(value) ? value : []).map(function (item) {
        var out = {};
        fields.forEach(function (key) { out[key] = model(entry.items[key].optionsFrom, isPlainObject(item) ? item[key] : undefined); });
        return out;
    });
}

// ------------------------------------------------------------------ pads

// A pad's shortcut is SHORTCUT_PREFIX and its name, which the plugin
// registers through capability `shortcut`; the layer binds it like any
// manifest bind once the plugins row's `keys` gives it a key.
var SHORTCUT_PREFIX = "pad-";

// The item fields the layer renders, each the schema type it must have.
// Any other item field is the plugin's own.
var FIELDS = { "class": "string", width: "number", height: "number", position: "enum", margin: "number", entry: "enum", motion: "enum" };

// Where a pad sits: its anchor across and down, `start`, `center` or
// `end` of the work area.
var POSITIONS = {
    "center": ["center", "center"],
    "top": ["center", "start"],
    "bottom": ["center", "end"],
    "left": ["start", "center"],
    "right": ["end", "center"],
    "top-left": ["start", "start"],
    "top-right": ["end", "start"],
    "bottom-left": ["start", "end"],
    "bottom-right": ["end", "end"]
};
// The side a pad slides in from, and how it moves in and out.
var ENTRIES = ["top", "bottom", "left", "right"];
var MOTIONS = ["slide", "fade", "none"];
var ENUMS = { position: Object.keys(POSITIONS), entry: ENTRIES, motion: MOTIONS };
// The bounds a share field's schema entry stays inside, in percent: a size
// is at least 1 % and at most the whole work area; a margin at most half.
var SHARES = { width: [1, 100], height: [1, 100], margin: [0, 50] };

// The window class a pad matches: an app-id's characters. The layer writes
// it anchored with each dot escaped, so it matches that class alone.
var CLASS = /^[A-Za-z0-9_.-]+$/;

// The first defect of a manifest's `hyprland.pads`, or "": absent, or the
// name of a `list` schema entry whose items hold every field of FIELDS with its type,
// each enum's options among the core's and each share's `min` and `max`
// inside SHARES. Pads bind shortcuts, so they need capability `shortcut`.
function manifestError(pads, capabilities, schema) {
    if (pads === undefined)
        return "";
    if (typeof pads !== "string" || !hasOwn(schema, pads) || schema[pads].type !== "list")
        return "hyprland.pads must name a list schema entry, got " + JSON.stringify(pads);
    if (capabilities.indexOf("shortcut") === -1)
        return "hyprland.pads needs capability shortcut";
    var items = schema[pads].items;
    var fields = Object.keys(FIELDS);
    for (var i = 0; i < fields.length; i++) {
        var field = fields[i];
        var at = "hyprland.pads item field " + field;
        if (!hasOwn(items, field))
            return at + " is missing from schema." + pads + ".items";
        if (items[field].type !== FIELDS[field])
            return at + " must be a " + FIELDS[field] + " entry, got " + items[field].type;
        if (hasOwn(ENUMS, field)) {
            var foreign = items[field].options.filter(function (option) { return ENUMS[field].indexOf(option) === -1; });
            if (foreign.length > 0)
                return at + " option " + JSON.stringify(foreign[0]) + " is not one of " + ENUMS[field].join(", ");
        }
        if (hasOwn(SHARES, field) && !(items[field].min >= SHARES[field][0] && items[field].max <= SHARES[field][1]))
            return at + " must set min and max within " + SHARES[field][0] + " to " + SHARES[field][1];
    }
    return "";
}

// Whether SHORTCUT is a pad's under a manifest's `hyprland` declaration
// DECLARED: its pads are declared and the name after SHORTCUT_PREFIX is a
// name. A pad's key may be set before the pad exists and outlives it, so
// a removed pad that comes back keeps its key.
function isPadShortcut(declared, shortcut, namePattern) {
    return isPlainObject(declared) && typeof declared.pads === "string" && typeof shortcut === "string"
        && shortcut.indexOf(SHORTCUT_PREFIX) === 0 && namePattern.test(shortcut.slice(SHORTCUT_PREFIX.length));
}

// What the pads of a manifest ask of Hyprland: { binds, pads, refusals }.
// SETTING is the `hyprland.pads` setting name, or undefined when the
// manifest declares none: no binds, `pads` null. Else its value in
// SETTINGS, the plugin's effective settings, is judged against its entry in
// SCHEMA by SETTING_ERROR, PluginLogic's judge: an unfit value gives no pad
// and one refusal. Each fitting item gives one bind { shortcut, key } per
// key that KEYS, the plugins row's `keys`, gives its shortcut through
// HYPRLAND_KEY, else one bind with null, which writes no bind, and a pad
// { name, class, width, height, x, y, margin, entry, motion } for the layer. An item whose
// class holds a character outside CLASS, or which another item's class
// holds already, gives no pad and a refusal { name, error }; it keeps its
// bind, so its key stays set and its press reaches the plugin, which the
// layer answers that it holds no such pad.
function expand(setting, schema, settings, keys, hyprlandKey, settingError) {
    if (setting === undefined) return { binds: [], pads: null, refusals: [] };
    var value = settings[setting];
    var unfit = settingError(schema[setting], value);
    if (unfit !== "") return { binds: [], pads: [], refusals: [{ name: "", error: "setting " + setting + " " + unfit }] };
    var out = { binds: [], pads: [], refusals: [] };
    var classes = {};
    value.forEach(function (item) {
        var shortcut = SHORTCUT_PREFIX + item.name;
        var values = hasOwn(keys, shortcut) && keys[shortcut] !== null ? (Array.isArray(keys[shortcut]) ? keys[shortcut] : [keys[shortcut]]) : [null];
        values.forEach(function (value) {
            var key = value === null ? null : hyprlandKey(value);
            if (key !== null && !key.ok)
                throw new Error("Pads.expand: keys." + shortcut + " passed configError but " + key.error);
            out.binds.push({ shortcut: shortcut, key: key === null ? null : key.key });
        });
        if (!CLASS.test(item["class"])) {
            out.refusals.push({ name: item.name, error: "class=" + JSON.stringify(item["class"]) + " want=" + CLASS.source });
            return;
        }
        if (hasOwn(classes, item["class"])) {
            out.refusals.push({ name: item.name, error: "class=" + item["class"] + " held by pad " + classes[item["class"]] });
            return;
        }
        classes[item["class"]] = item.name;
        var anchor = POSITIONS[item.position];
        out.pads.push({ name: item.name, "class": item["class"], width: item.width, height: item.height, x: anchor[0], y: anchor[1],
            margin: item.margin, entry: item.entry, motion: item.motion });
    });
    return out;
}
