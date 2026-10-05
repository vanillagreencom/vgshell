#!/usr/bin/env node
// Table-driven checks for shell/Core/Pads.js, the schema's `list` type and
// the pads of a manifest's `hyprland.pads`, loaded under node through
// bin/lib/qml-library.js. The judges Pads.js takes from PluginLogic.js,
// schemaError, settingError, hyprlandKey and NAME_PATTERN, come from the
// shipped PluginLogic.js, so a row judges an item field as the core does;
// PluginLogic's own use of Pads.js is scripts/test-plugin-logic.js's.
// The controls at the end edit a copy of Pads.js, one rule at a time, and
// the suite must fail on every copy. Exit 1 when a row or a control fails.
"use strict";
const fs = require("fs");
const path = require("path");
const { load } = require("../bin/lib/qml-library.js");

const PADS = path.join(__dirname, "..", "shell", "Core", "Pads.js");
const logic = load(path.join(__dirname, "..", "shell", "Core", "PluginLogic.js"));

let failures = 0;
function report(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { console.log("  ok    " + name); return; }
    failures += 1;
    console.log("  FAIL  " + name + "\n        got  " + g + "\n        want " + w);
}

// A library's objects come from another realm, so results compare as JSON.
const plain = value => JSON.parse(JSON.stringify(value === undefined ? null : value));

// The pad item schema a plugin declares: every field the layer renders,
// with the core's options and shares, and a field of the plugin's own.
const items = {
    command: { type: "string", label: "App", presets: [{ value: "foot" }], allowCustom: true },
    "class": { type: "string", label: "Class", presets: [{ value: "org.acme.pad" }], allowCustom: true },
    width: { type: "number", label: "Width", min: 10, max: 100 },
    height: { type: "number", label: "Height", min: 10, max: 100 },
    position: { type: "enum", label: "Position", options: ["center", "top", "bottom-right"] },
    margin: { type: "number", label: "Margin", min: 0, max: 20 },
    entry: { type: "enum", label: "Entry", options: ["top", "left"] },
    motion: { type: "enum", label: "Motion", options: ["slide", "fade", "none"] },
    screen: { type: "string", label: "Screen", optionsFrom: "screens" }
};
const defaults = { command: "foot", "class": "org.acme.pad", width: 60, height: 50, position: "top", margin: 2, entry: "top", motion: "slide", screen: "" };
const entry = { type: "list", label: "Pads", items: items, defaults: defaults };
const status = { screens: { type: "choices", label: "Screens" } };
const pad = (name, patch) => Object.assign({ name: name }, defaults, patch || {});
const withItems = patch => Object.assign({}, entry, { items: Object.assign({}, items, patch) });

function suite(pads, check) {
    // listEntryError: one row per rule, the defect planted in the entry.
    const entryRows = [
        ["a list entry passes", entry, ""],
        ["a flat entry without list keys passes", { type: "boolean", label: "On" }, ""],
        ["items on a flat entry are refused", { type: "boolean", label: "On", items: {} }, "schema.pads.items and .defaults need type list"],
        ["defaults on a flat entry are refused", { type: "boolean", label: "On", defaults: {} }, "schema.pads.items and .defaults need type list"],
        ["a list without items is refused", { type: "list", label: "Pads", defaults: {} }, "schema.pads.items must be a non-empty object"],
        ["a list with empty items is refused", { type: "list", label: "Pads", items: {}, defaults: {} }, "schema.pads.items must be a non-empty object"],
        ["a list without defaults is refused", { type: "list", label: "Pads", items: items }, "schema.pads.defaults must be an object"],
        ["an item field named name is refused", withItems({ name: { type: "boolean", label: "Name" } }), "schema.pads.items.name is refused: every item holds its name"],
        ["a list inside a list is refused", withItems({ inner: { type: "list", label: "Inner", items: { on: { type: "boolean", label: "On" } }, defaults: { on: true } } }), "schema.pads.items.inner must not be a list"],
        ["a default naming no field is refused", Object.assign({}, entry, { defaults: Object.assign({ extra: 1 }, defaults) }), "schema.pads.defaults.extra names no item field"],
        ["an item field the flat judge refuses is refused", withItems({ label: { type: "string", label: "Label" } }), "schema.pads.items: schema.label with type string must declare presets or optionsFrom"],
        ["an item field without a default is refused", withItems({ on: { type: "boolean", label: "On" } }), "schema.pads.items: schema.on has no default in settings"],
        ["an item field's optionsFrom is judged against the status", withItems({ screen: { type: "string", label: "Screen", optionsFrom: "outputs" } }), "schema.pads.items: schema.screen.optionsFrom must name a choices status entry"]
    ];
    for (const [name, spec, want] of entryRows)
        check("listEntryError: " + name, pads.listEntryError(spec, "schema.pads", status, logic.schemaError), want);

    // listValueError: one row per rule, the defect planted in the value.
    const valueRows = [
        ["an empty list fits", [], ""],
        ["two named items fit", [pad("1"), pad("term", { "class": "foot" })], ""],
        ["a value that is no list", {}, "want=list"],
        ["an item that is no object", [pad("1"), "x"], "item=1 want=object"],
        ["an item without a name", [Object.assign({}, defaults)], "item=0 want=name"],
        ["an item whose name is no name", [pad("Pad 1")], "item=0 want=name"],
        ["two items of one name", [pad("1"), pad("1")], "item=1 name=1 want=unique"],
        ["an item with an undeclared field", [Object.assign(pad("1"), { colour: "red" })], "item=0 field=colour undeclared"],
        ["an item without a field", [(() => { const p = pad("1"); delete p.margin; return p; })()], "item=0 field=margin missing"],
        ["an item field out of its bounds", [pad("1", { width: 120 })], "item=0 field=width want=at-most:100"],
        ["an item field outside its enum", [pad("1", { motion: "spin" })], "item=0 field=motion want=one-of:slide|fade|none"]
    ];
    for (const [name, value, want] of valueRows)
        check("listValueError: " + name, pads.listValueError(entry, value, logic.settingError, logic.NAME_PATTERN), want);

    // listChoices: one model per item for each optionsFrom field.
    const model = (from, configured) => [from, configured];
    check("listChoices: one model per item for each optionsFrom field", plain(pads.listChoices(entry, [pad("1", { screen: "DP-1" }), pad("2")], model)), [{ screen: ["screens", "DP-1"] }, { screen: ["screens", ""] }]);
    check("listChoices: a value that is no list has no models", plain(pads.listChoices(entry, "x", model)), []);

    // manifestError: one row per rule, the defect planted in the schema.
    const schemaOf = patch => ({ pads: withItems(patch) });
    const manifestRows = [
        ["absent pads pass", undefined, ["shortcut"], schemaOf({}), ""],
        ["pads naming a list entry pass", "pads", ["shortcut"], schemaOf({}), ""],
        ["pads that are no name", 1, ["shortcut"], schemaOf({}), "hyprland.pads must name a list schema entry, got 1"],
        ["pads naming no entry", "missing", ["shortcut"], schemaOf({}), "hyprland.pads must name a list schema entry, got \"missing\""],
        ["pads naming a flat entry", "on", ["shortcut"], { on: { type: "boolean", label: "On" } }, "hyprland.pads must name a list schema entry, got \"on\""],
        ["pads without capability shortcut", "pads", [], schemaOf({}), "hyprland.pads needs capability shortcut"],
        ["an item without a rendered field", "pads", ["shortcut"], { pads: Object.assign({}, entry, { items: (() => { const i = Object.assign({}, items); delete i.margin; return i; })() }) }, "hyprland.pads item field margin is missing from schema.pads.items"],
        ["a rendered field of another type", "pads", ["shortcut"], schemaOf({ width: { type: "enum", label: "Width", options: ["half"] } }), "hyprland.pads item field width must be a number entry, got enum"],
        ["a position outside the core's", "pads", ["shortcut"], schemaOf({ position: { type: "enum", label: "Position", options: ["top", "middle"] } }), "hyprland.pads item field position option \"middle\" is not one of center, top, bottom, left, right, top-left, top-right, bottom-left, bottom-right"],
        ["an entry side outside the core's", "pads", ["shortcut"], schemaOf({ entry: { type: "enum", label: "Entry", options: ["up"] } }), "hyprland.pads item field entry option \"up\" is not one of top, bottom, left, right"],
        ["a motion outside the core's", "pads", ["shortcut"], schemaOf({ motion: { type: "enum", label: "Motion", options: ["spin"] } }), "hyprland.pads item field motion option \"spin\" is not one of slide, fade, none"],
        ["a size below 1 %", "pads", ["shortcut"], schemaOf({ height: { type: "number", label: "Height", min: 0, max: 100 } }), "hyprland.pads item field height must set min and max within 1 to 100"],
        ["a size over the work area", "pads", ["shortcut"], schemaOf({ width: { type: "number", label: "Width", min: 10, max: 101 } }), "hyprland.pads item field width must set min and max within 1 to 100"],
        ["a size without bounds", "pads", ["shortcut"], schemaOf({ width: { type: "number", label: "Width" } }), "hyprland.pads item field width must set min and max within 1 to 100"],
        ["a margin over half the screen", "pads", ["shortcut"], schemaOf({ margin: { type: "number", label: "Margin", min: 0, max: 60 } }), "hyprland.pads item field margin must set min and max within 0 to 50"]
    ];
    for (const [name, value, capabilities, schema, want] of manifestRows)
        check("manifestError: " + name, pads.manifestError(value, capabilities, schema), want);

    // isPadShortcut: a pad's shortcut under declared pads, whatever pads
    // the setting lists.
    const shortcutRows = [
        ["a pad's shortcut", { pads: "pads" }, "pad-term", true],
        ["a shortcut of a pad not listed yet", { pads: "pads" }, "pad-9", true],
        ["a shortcut without the prefix", { pads: "pads" }, "term", false],
        ["a shortcut of another prefix", { pads: "pads" }, "openterm", false],
        ["the prefix alone", { pads: "pads" }, "pad-", false],
        ["a name the shortcut grammar refuses", { pads: "pads" }, "pad-Term", false],
        ["no declared pads", { binds: [] }, "pad-term", false],
        ["no hyprland key", undefined, "pad-term", false]
    ];
    for (const [name, declared, shortcut, want] of shortcutRows)
        check("isPadShortcut: " + name, pads.isPadShortcut(declared, shortcut, logic.NAME_PATTERN), want);

    // expand: what the pads ask of the layer.
    const schema = { pads: entry };
    const expand = (value, keys) => plain(pads.expand("pads", schema, { pads: value }, keys || {}, logic.hyprlandKey, logic.settingError));
    check("expand: a manifest without pads asks nothing", plain(pads.expand(undefined, schema, {}, {}, logic.hyprlandKey, logic.settingError)), { binds: [], pads: null, refusals: [] });
    check("expand: no pads ask an empty list", expand([]), { binds: [], pads: [], refusals: [] });
    check("expand: a pad's bind takes its key, normalised, and its anchors come from its position", expand([pad("1", { position: "bottom-right" })], { "pad-1": "alt+super+p" }), {
        binds: [{ shortcut: "pad-1", key: "SUPER+ALT+P" }],
        pads: [{ name: "1", "class": "org.acme.pad", width: 60, height: 50, x: "end", y: "end", margin: 2, entry: "top", motion: "slide" }],
        refusals: []
    });
    check("expand: a pad no key is set for is unbound", expand([pad("1")]).binds, [{ shortcut: "pad-1", key: null }]);
    check("expand: a pad unbound in the row is unbound", expand([pad("1")], { "pad-1": null }).binds, [{ shortcut: "pad-1", key: null }]);
    check("expand: a centred pad is centred both ways", expand([pad("1", { position: "center" })]).pads.map(p => [p.x, p.y]), [["center", "center"]]);
    check("expand: a top pad is centred across and starts down", expand([pad("1")]).pads.map(p => [p.x, p.y]), [["center", "start"]]);
    check("expand: an unfit list gives no pad and one refusal", expand([pad("1", { width: 5 })]), { binds: [], pads: [], refusals: [{ name: "", error: "setting pads item=0 field=width want=at-least:10" }] });
    check("expand: a class outside the app-id characters is refused alone", expand([pad("1", { "class": "org.acme\"pad" }), pad("2", { "class": "other" })]), {
        binds: [{ shortcut: "pad-1", key: null }, { shortcut: "pad-2", key: null }],
        pads: [{ name: "2", "class": "other", width: 60, height: 50, x: "center", y: "start", margin: 2, entry: "top", motion: "slide" }],
        refusals: [{ name: "1", error: "class=\"org.acme\\\"pad\" want=^[A-Za-z0-9_.-]+$" }]
    });
    check("expand: a class another pad holds is refused", expand([pad("1"), pad("2")]).refusals, [{ name: "2", error: "class=org.acme.pad held by pad 1" }]);
    check("expand: a pad refused over its class keeps its bind and its key", expand([pad("1"), pad("2")], { "pad-2": "SUPER+ALT+O" }).binds, [{ shortcut: "pad-1", key: null }, { shortcut: "pad-2", key: "SUPER+ALT+O" }]);
    check("expand: a pad refused over its class gives no pad", expand([pad("1"), pad("2")]).pads.map(p => p.name), ["1"]);
    // Each position's anchors across and down, written out here.
    const positionRows = [
        ["center", "center", "center"], ["top", "center", "start"], ["bottom", "center", "end"],
        ["left", "start", "center"], ["right", "end", "center"], ["top-left", "start", "start"],
        ["top-right", "end", "start"], ["bottom-left", "start", "end"], ["bottom-right", "end", "end"]
    ];
    const allPositions = withItems({ position: { type: "enum", label: "Position", options: positionRows.map(r => r[0]) } });
    for (const [position, x, y] of positionRows) {
        const got = plain(pads.expand("pads", { pads: allPositions }, { pads: [pad("1", { position: position })] }, {}, logic.hyprlandKey, logic.settingError)).pads.map(p => [p.x, p.y]);
        check("expand: a " + position + " pad's anchors", got, [[x, y]]);
    }
}

suite(load(PADS), report);

// Each control removes one rule from a copy of Pads.js and keeps the text
// around it. The suite must fail on every copy.
const CONTROLS = [
    ["list keys need type list", "return entry.items !== undefined || entry.defaults !== undefined ? at + \".items and .defaults need type list\" : \"\";", "return \"\";"],
    ["a list needs items", "if (!isPlainObject(entry.items) || Object.keys(entry.items).length === 0)", "if (!isPlainObject(entry.items))"],
    ["a list needs defaults", "if (!isPlainObject(entry.defaults))\n        return at + \".defaults must be an object\";", "if (entry.defaults === undefined)\n        entry.defaults = {};"],
    ["no item field is named name", "if (fields[i] === \"name\")", "if (false)"],
    ["no list inside a list", "&& entry.items[fields[i]].type === \"list\")", "&& false)"],
    ["defaults name item fields", "return !hasOwn(entry.items, key); });", "return false; });"],
    ["items are judged as a flat schema", "var bad = schemaError(entry.items, entry.defaults, status);", "var bad = \"\";"],
    ["a value is a list", "if (!Array.isArray(value)) return \"want=list\";", "if (!Array.isArray(value)) return \"\";"],
    ["an item is an object", "if (!isPlainObject(item)) return at + \" want=object\";", "if (!isPlainObject(item)) continue;"],
    ["an item has a name", "if (typeof item.name !== \"string\" || !namePattern.test(item.name)) return at + \" want=name\";", "if (typeof item.name !== \"string\") return at + \" want=name\";"],
    ["names are unique", "if (names.indexOf(item.name) !== -1) return at", "if (false) return at"],
    ["an item holds declared fields alone", "if (keys[k] !== \"name\" && !hasOwn(entry.items, keys[k])) return", "if (false) return"],
    ["an item holds every field", "if (!hasOwn(item, fields[f])) return at + \" field=\" + fields[f] + \" missing\";", ""],
    ["an item's fields are judged", "var bad = settingError(entry.items[fields[f]], item[fields[f]]);", "var bad = \"\";"],
    ["choices follow optionsFrom fields", "return entry.items[key].optionsFrom !== undefined; });", "return false; });"],
    ["absent pads pass", "if (pads === undefined)\n        return \"\";", "if (pads === undefined)\n        return \"hyprland.pads is absent\";"],
    ["pads name a list entry", "|| schema[pads].type !== \"list\")", ")"],
    ["pads need capability shortcut", "if (capabilities.indexOf(\"shortcut\") === -1)", "if (false)"],
    ["every rendered field is declared", "if (!hasOwn(items, field))\n            return at + \" is missing", "if (false)\n            return at + \" is missing"],
    ["every rendered field has its type", "if (items[field].type !== FIELDS[field])", "if (false)"],
    ["enum options are the core's", "return ENUMS[field].indexOf(option) === -1; });", "return false; });"],
    ["shares keep their bounds", "!(items[field].min >= SHARES[field][0] && items[field].max <= SHARES[field][1])", "false"],
    ["a pad shortcut needs declared pads", "isPlainObject(declared) && typeof declared.pads === \"string\" && ", "isPlainObject(declared) && "],
    ["a pad shortcut has the prefix", "shortcut.indexOf(SHORTCUT_PREFIX) === 0 && ", ""],
    ["a pad shortcut names a name", "&& namePattern.test(shortcut.slice(SHORTCUT_PREFIX.length));", ";"],
    ["no declared pads ask nothing", "if (setting === undefined) return { binds: [], pads: null, refusals: [] };", "if (setting === undefined) return { binds: [], pads: [], refusals: [] };"],
    ["an unfit value gives no pad", "if (unfit !== \"\") return", "if (false) return"],
    ["a class is judged", "if (!CLASS.test(item[\"class\"])) {", "if (false) {"],
    ["a class is held once", "if (hasOwn(classes, item[\"class\"])) {", "if (false) {"],
    ["a pad's key comes from the row", "var key = hasOwn(keys, shortcut) && keys[shortcut] !== null ? hyprlandKey(keys[shortcut]) : null;", "var key = null;"],
    ["a pad's key is normalised", "key: key === null ? null : key.key", "key: key === null ? null : keys[shortcut]"],
    ["a position gives both anchors", "\"bottom-right\": [\"end\", \"end\"]", "\"bottom-right\": [\"end\", \"start\"]"],
    ["a top pad starts down", "\"top\": [\"center\", \"start\"],", "\"top\": [\"start\", \"start\"],"],
    ["a right pad ends across", "\"right\": [\"end\", \"center\"],", "\"right\": [\"start\", \"center\"],"],
    ["a refused pad keeps its bind", "        out.binds.push({ shortcut: shortcut, key: key === null ? null : key.key });\n        if (!CLASS.test", "        if (!CLASS.test"]
];

fs.mkdirSync(path.join(__dirname, "..", "tmp"), { recursive: true });
const temp = fs.mkdtempSync(path.join(__dirname, "..", "tmp", "pads-control-"));
try {
    const source = fs.readFileSync(PADS, "utf8");
    for (const [label, needle, replacement] of CONTROLS) {
        const count = source.split(needle).length - 1;
        if (count !== 1) { report("control: " + label + ": the text to replace occurs once", count, 1); continue; }
        const mutant = path.join(temp, "Pads.js");
        fs.writeFileSync(mutant, source.replace(needle, () => replacement));
        // Loaded outside the try, so a copy that does not evaluate fails the
        // suite instead of passing for a control.
        const pads = load(mutant);
        let red = 0;
        try {
            suite(pads, (name, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) red += 1; });
        } catch (e) {
            red += 1;
        }
        report("control: the suite fails without the rule: " + label, red > 0, true);
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}

if (failures > 0) { console.log("test-pads: " + failures + " failing"); process.exit(1); }
console.log("test-pads: ok controls=" + CONTROLS.length);
