#!/usr/bin/env node
// Table-driven checks for a manifest's `menu` in shell/Core/PluginLogic.js:
// menuError, which judges the key inside validateManifest; menuRows, every
// enabled plugin's launcher rows with each toggle's label resolved from the
// plugin's settings, which the shortcut capability lists as
// shell.shortcut.menu; and menuActivation, the answer to running a row's
// global through shell.shortcut.activate. The controls at the end edit a
// copy of the judge, one rule at a time, and the suite must fail on every
// copy. Exit 1 when any row or control fails.
"use strict";
const fs = require("fs");
const path = require("path");
const { load } = require("../bin/lib/qml-library.js");

const LOGIC = path.join(__dirname, "..", "shell", "Core", "PluginLogic.js");
const LUCIDE = path.join(__dirname, "..", "shell", "Ui", "icons", "Lucide.js");
const MANAGERS = path.join(__dirname, "..", "shell", "Core", "PackageManagers.js");
const LAYER = path.join(__dirname, "..", "shell", "Core", "HyprlandLayer.js");
const SETTING_VALUES = path.join(__dirname, "..", "shell", "Commons", "SettingValues.js");

let failures = 0;
function report(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { console.log("  ok    " + name); return; }
    failures += 1;
    console.log("  FAIL  " + name + "\n        got  " + g + "\n        want " + w);
}

// The fixture: a category, a row running the plugin's `open` shortcut and a
// toggle row running `gaps`, which reads `noGaps`.
function fixture() {
    return {
        schemaVersion: 1, id: "acme.style", name: "Style", version: "1", author: "a", description: "d",
        kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["shortcut"],
        settings: { noGaps: false, mode: "dark" },
        schema: { noGaps: { type: "boolean", label: "No gaps" }, mode: { type: "enum", label: "Mode", options: ["dark", "light"] } },
        menu: {
            style: { label: "Style", icon: "paintbrush" },
            "style.open": { label: "Open", icon: "palette", aliases: ["themes"], description: "Open the browser", shortcut: "open" },
            "style.gaps": { label: "No gaps", icon: "maximize", shortcut: "gaps", toggle: { setting: "noGaps", label: "Default gaps", icon: "layout-grid" } }
        }
    };
}

function suite(ctx, check) {
    // menuError through validateManifest: [name, edit of the fixture, want],
    // `want` the start of the error text or null for an accepted manifest.
    const manifestRows = [
        ["a category, a row and a toggle row", () => {}, null],
        ["a category alone needs no shortcut capability", m => { m.capabilities = []; m.menu = { style: { label: "Style", icon: "paintbrush" } }; }, null],
        ["a tui row needs no shortcut capability", m => { m.capabilities = []; m.menu = { packages: { label: "Packages", icon: "package" }, "packages.install": { label: "Install", icon: "package", tui: "core/pkg-install" } }; }, null],
        ["a tui group row needs no shortcut capability", m => { m.capabilities = []; m.menu = { packages: { label: "Packages", icon: "package" }, "packages.update": { label: "Update", icon: "refresh-cw", tuiGroup: "Update" } }; }, null],
        ["a provider names a launcherRows status key", m => { m.capabilities = ["shortcut", "status"]; m.status = { catalog: { type: "launcherRows", label: "Catalog" } }; m.menu = { tools: { label: "Tools", icon: "blocks", shortcut: "open", provider: "catalog" } }; }, null],
        ["a provider without a shortcut", m => { m.capabilities = ["shortcut", "status"]; m.status = { catalog: { type: "launcherRows", label: "Catalog" } }; m.menu = { tools: { label: "Tools", icon: "blocks", provider: "catalog" } }; }, "menu.tools.provider needs a shortcut"],
        ["a provider with a toggle", m => { m.capabilities = ["shortcut", "status"]; m.status = { catalog: { type: "launcherRows", label: "Catalog" } }; m.menu = { tools: { label: "Tools", icon: "blocks", shortcut: "open", provider: "catalog", toggle: { setting: "noGaps", label: "No gaps" } } }; }, "menu.tools.provider must not declare toggle"],
        ["a provider with a tui", m => { m.capabilities = ["shortcut", "status"]; m.status = { catalog: { type: "launcherRows", label: "Catalog" } }; m.menu = { tools: { label: "Tools", icon: "blocks", shortcut: "open", provider: "catalog", tui: "core/pkg-install" } }; }, "menu.tools.provider must not declare tui or tuiGroup"],
        ["a provider naming text status", m => { m.capabilities = ["shortcut", "status"]; m.status = { catalog: { type: "text", label: "Catalog" } }; m.menu = { tools: { label: "Tools", icon: "blocks", shortcut: "open", provider: "catalog" } }; }, "menu.tools.provider must name a launcherRows status entry"],
        ["a provider naming an undeclared status", m => { m.capabilities = ["shortcut", "status"]; m.status = { other: { type: "launcherRows", label: "Other" } }; m.menu = { tools: { label: "Tools", icon: "blocks", shortcut: "open", provider: "catalog" } }; }, "menu.tools.provider must name a launcherRows status entry"],
        ["a toggle without its own icon", m => { delete m.menu["style.gaps"].toggle.icon; }, null],
        ["a menu that is no object", m => { m.menu = []; }, "menu must be a non-empty object of row ids to rows"],
        ["a menu with no row", m => { m.menu = {}; }, "menu must be a non-empty object of row ids to rows"],
        ["an id with capitals", m => { m.menu.Style = m.menu.style; }, "menu id \"Style\" must be dotted lower-case words"],
        ["an id with an empty part", m => { m.menu["style..x"] = m.menu.style; }, "menu id \"style..x\" must be dotted lower-case words"],
        ["a row that is no object", m => { m.menu.style = "Style"; }, "menu.style must be an object"],
        ["a row with an unknown key", m => { m.menu.style.run = ["true"]; }, "menu.style has unknown key \"run\""],
        ["a row without a label", m => { delete m.menu.style.label; }, "menu.style.label must be a printable line of 1 to 60 characters"],
        ["a label of 61 characters", m => { m.menu.style.label = "x".repeat(61); }, "menu.style.label must be a printable line"],
        ["a label of two lines", m => { m.menu.style.label = "Sty\nle"; }, "menu.style.label must be a printable line"],
        ["a row without an icon", m => { delete m.menu.style.icon; }, "menu.style.icon must name an icon of the shipped set, got undefined"],
        ["an icon outside the set", m => { m.menu.style.icon = "brush-x"; }, "menu.style.icon must name an icon of the shipped set, got \"brush-x\""],
        ["aliases that are no list", m => { m.menu["style.open"].aliases = "themes"; }, "menu.style.open.aliases must be a list of printable lines"],
        ["an empty alias", m => { m.menu["style.open"].aliases = [""]; }, "menu.style.open.aliases must be a list of printable lines"],
        ["a description of two lines", m => { m.menu["style.open"].description = "a\nb"; }, "menu.style.open.description must be a printable line of 1 to 120 characters"],
        ["a description of 121 characters", m => { m.menu["style.open"].description = "x".repeat(121); }, "menu.style.open.description must be a printable line"],
        ["a shortcut that is no name", m => { m.menu["style.open"].shortcut = "acme.style:open"; }, "menu.style.open.shortcut must be a shortcut name, got \"acme.style:open\""],
        ["a shortcut without the capability", m => { m.capabilities = []; }, "menu.style.open.shortcut needs capability shortcut"],
        ["a tui key without an owner", m => { m.menu["style.open"] = { label: "Open", icon: "palette", tui: "pkg-install" }; }, "menu.style.open.tui is not a TUI key"],
        ["a tui group of two lines", m => { m.menu["style.open"] = { label: "Open", icon: "palette", tuiGroup: "Up\ndate" }; }, "menu.style.open.tuiGroup must be a printable line"],
        ["a row with shortcut and tui", m => { m.menu["style.open"].tui = "core/pkg-install"; }, "menu.style.open states shortcut and tui"],
        ["a toggle without a shortcut", m => { delete m.menu["style.gaps"].shortcut; }, "menu.style.gaps.toggle needs a shortcut"],
        ["a toggle with a tui", m => { m.menu["style.gaps"].tui = "core/pkg-install"; }, "menu.style.gaps.toggle must not declare tui or tuiGroup"],
        ["a toggle that is no object", m => { m.menu["style.gaps"].toggle = "noGaps"; }, "menu.style.gaps.toggle must be an object"],
        ["a toggle with an unknown key", m => { m.menu["style.gaps"].toggle.description = "x"; }, "menu.style.gaps.toggle has unknown key \"description\""],
        ["a toggle naming no setting", m => { m.menu["style.gaps"].toggle.setting = "nope"; }, "menu.style.gaps.toggle.setting must name a boolean schema entry, got \"nope\""],
        ["a toggle naming a setting without a schema entry", m => { m.settings.hidden = false; m.menu["style.gaps"].toggle.setting = "hidden"; }, "menu.style.gaps.toggle.setting must name a boolean schema entry, got \"hidden\""],
        ["a toggle naming an enum", m => { m.menu["style.gaps"].toggle.setting = "mode"; }, "menu.style.gaps.toggle.setting must name a boolean schema entry, got \"mode\""],
        ["a toggle without a label", m => { delete m.menu["style.gaps"].toggle.label; }, "menu.style.gaps.toggle.label must be a printable line of 1 to 60 characters"],
        ["a toggle icon outside the set", m => { m.menu["style.gaps"].toggle.icon = "nope"; }, "menu.style.gaps.toggle.icon must name an icon of the shipped set, got \"nope\""]
    ];
    for (const [name, edit, want] of manifestRows) {
        const raw = fixture();
        edit(raw);
        const r = ctx.validateManifest(raw, "/p");
        check("validateManifest: " + name, r.ok ? null : r.error.slice(0, want === null ? 0 : want.length), want);
    }
    const plain = fixture();
    delete plain.menu;
    check("validateManifest: a manifest without a menu carries {}", ctx.validateManifest(plain, "/p").manifest.menu, {});
    const judged = ctx.validateManifest(fixture(), "/p");
    if (!judged.ok) throw new Error("the fixture manifest is refused: " + judged.error);
    const style = judged.manifest;
    check("validateManifest: the menu is carried as declared", style.menu, fixture().menu);

    // menuRows: by plugin id, then in manifest order; a toggle's label
    // follows the plugins row; a disabled plugin lists nothing; a taken id
    // stays with the first plugin by id.
    const bar = ctx.validateManifest({
        schemaVersion: 1, id: "acme.bar", name: "Bar", version: "1", author: "a", description: "d",
        kinds: ["bar", "service"], entryPoints: { bar: "B.qml", service: "S.qml" }, capabilities: ["shortcut", "configure"],
        settings: { hidden: false }, schema: { hidden: { type: "boolean", label: "Hide" } },
        menu: { "style.bar": { label: "Hide bar", icon: "panel-top-close", shortcut: "toggle", toggle: { setting: "hidden", label: "Show bar" } } }
    }, "/b").manifest;
    const later = ctx.validateManifest({
        schemaVersion: 1, id: "zeta.style", name: "Z", version: "1", author: "a", description: "d",
        kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["shortcut"],
        menu: { style: { label: "Other style", icon: "star" }, "style.zeta": { label: "Zeta", icon: "star", shortcut: "go" } }
    }, "/z").manifest;
    const manifests = { "acme.style": style, "acme.bar": bar, "zeta.style": later };
    const labels = (config, enabled) => ctx.menuRows(manifests, enabled, config).rows.map(r => [r.id, r.label, r.icon]);
    check("menuRows: the category's own plugin first, then a row another plugin adds, each fully listed", ctx.menuRows(manifests, ["acme.style", "acme.bar"], {}), {
        rows: [
            { id: "style", plugin: "acme.style", label: "Style", icon: "paintbrush", aliases: [], description: "", shortcut: "", provider: "", tui: "", tuiGroup: "" },
            { id: "style.open", plugin: "acme.style", label: "Open", icon: "palette", aliases: ["themes"], description: "Open the browser", shortcut: "acme.style:open", provider: "", tui: "", tuiGroup: "" },
            { id: "style.gaps", plugin: "acme.style", label: "No gaps", icon: "maximize", aliases: [], description: "", shortcut: "acme.style:gaps", provider: "", tui: "", tuiGroup: "" },
            { id: "style.bar", plugin: "acme.bar", label: "Hide bar", icon: "panel-top-close", aliases: [], description: "", shortcut: "acme.bar:toggle", provider: "", tui: "", tuiGroup: "" }
        ],
        conflicts: []
    });
    // Top-level ids keep the order their first row is listed in, by plugin
    // id; a row under a category no plugin declares keeps its place.
    const tools = ctx.validateManifest({
        schemaVersion: 1, id: "aaa.tools", name: "T", version: "1", author: "a", description: "d",
        kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["shortcut"],
        menu: { "tools.clean": { label: "Clean", icon: "star", shortcut: "clean" }, "style.tidy": { label: "Tidy", icon: "star", shortcut: "tidy" } }
    }, "/t").manifest;
    check("menuRows: top-level ids in the order their first row is listed", ctx.menuRows(Object.assign({ "aaa.tools": tools }, manifests), ["acme.bar", "aaa.tools", "acme.style"], {}).rows.map(r => r.id),
        ["tools.clean", "style", "style.open", "style.gaps", "style.tidy", "style.bar"]);
    check("menuRows: a toggle's setting on shows its label and icon", labels({ plugins: [{ id: "acme.style", noGaps: true }] }, ["acme.style"]).slice(2),
        [["style.gaps", "Default gaps", "layout-grid"]]);
    check("menuRows: a toggle without its own icon keeps the row's", labels({ plugins: [{ id: "acme.bar", hidden: true }] }, ["acme.bar"]),
        [["style.bar", "Show bar", "panel-top-close"]]);
    check("menuRows: only true turns a toggle on", labels({ plugins: [{ id: "acme.style", noGaps: "yes" }] }, ["acme.style"]).slice(2),
        [["style.gaps", "No gaps", "maximize"]]);
    check("menuRows: a toggle reads the plugins row, never a layout entry", labels({ bar: { layout: { left: [{ id: "acme.style", noGaps: true }] } } }, ["acme.style"]).slice(2),
        [["style.gaps", "No gaps", "maximize"]]);
    check("menuRows: a disabled plugin lists nothing", labels({}, ["acme.bar"]), [["style.bar", "Hide bar", "panel-top-close"]]);
    check("menuRows: an enabled id with no manifest lists nothing", labels({}, ["acme.gone"]), []);
    check("menuRows: a taken id stays with the first plugin by id", ctx.menuRows(manifests, ["zeta.style", "acme.style"], {}),
        {
            rows: ctx.menuRows(manifests, ["acme.style"], {}).rows.concat([{ id: "style.zeta", plugin: "zeta.style", label: "Zeta", icon: "star", aliases: [], description: "", shortcut: "zeta.style:go", provider: "", tui: "", tuiGroup: "" }]),
            conflicts: [{ id: "style", plugin: "zeta.style", heldBy: "acme.style" }]
        });

    const providerManifest = ctx.validateManifest({
        schemaVersion: 1, id: "acme.catalog", name: "Catalog", version: "1", author: "a", description: "d",
        kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["shortcut", "status"],
        status: { rows: { type: "launcherRows", label: "Rows" }, moreRows: { type: "launcherRows", label: "More rows" } },
        menu: { catalog: { label: "Catalog", icon: "blocks", shortcut: "open", provider: "rows" }, more: { label: "More", icon: "blocks", shortcut: "open", provider: "moreRows" } }
    }, "/catalog").manifest;
    const providerMenuRows = ctx.menuRows({ "acme.catalog": providerManifest }, ["acme.catalog"], {}).rows;
    const providerValues = { rows: [
        { id: "tools", label: "Tools", icon: "blocks", menu: true },
        { id: "tools.clean", label: "Clean", icon: "sparkles", description: "Clean state", aliases: ["wipe"] }
    ], moreRows: [
        { id: "other", label: "Other", icon: "blocks" }
    ] };
    check("menuRows: provider rows carry their status keys", providerMenuRows, [
        { id: "catalog", plugin: "acme.catalog", label: "Catalog", icon: "blocks", aliases: [], description: "", shortcut: "acme.catalog:open", provider: "rows", tui: "", tuiGroup: "" },
        { id: "more", plugin: "acme.catalog", label: "More", icon: "blocks", aliases: [], description: "", shortcut: "acme.catalog:open", provider: "moreRows", tui: "", tuiGroup: "" }
    ]);
    check("providerRows: a provider row expands published rows", ctx.providerRows(providerMenuRows, "catalog", providerValues), [
        { id: "catalog.tools", label: "Tools", icon: "blocks", description: "", aliases: [], menu: true, shortcut: "acme.catalog:open", item: "tools" },
        { id: "catalog.tools.clean", label: "Clean", icon: "sparkles", description: "Clean state", aliases: ["wipe"], menu: false, shortcut: "acme.catalog:open", item: "tools.clean" }
    ]);
    check("providerRows: an unlisted provider is empty", ctx.providerRows(providerMenuRows, "missing", providerValues), []);
    check("providerRows: an unpublished provider is empty", ctx.providerRows(providerMenuRows, "catalog", {}), []);
    const packagesManifest = ctx.validateManifest({
        schemaVersion: 1, id: "acme.packages", name: "Packages", version: "1", author: "a", description: "d",
        kinds: ["service"], entryPoints: { service: "S.qml" },
        menu: {
            packages: { label: "Packages", icon: "package" },
            "packages.install": { label: "Install", icon: "package", tui: "core/pkg-install" },
            "packages.update": { label: "Update", icon: "refresh-cw", tuiGroup: "Update" }
        }
    }, "/packages").manifest;
    check("menuRows: tui rows carry their key and group", ctx.menuRows({ "acme.packages": packagesManifest }, ["acme.packages"], {}).rows, [
        { id: "packages", plugin: "acme.packages", label: "Packages", icon: "package", aliases: [], description: "", shortcut: "", provider: "", tui: "", tuiGroup: "" },
        { id: "packages.install", plugin: "acme.packages", label: "Install", icon: "package", aliases: [], description: "", shortcut: "", provider: "", tui: "core/pkg-install", tuiGroup: "" },
        { id: "packages.update", plugin: "acme.packages", label: "Update", icon: "refresh-cw", aliases: [], description: "", shortcut: "", provider: "", tui: "", tuiGroup: "Update" }
    ]);

    // menuActivation: a listed row's registered global runs; anything else
    // is refused by key.
    const rows = ctx.menuRows(manifests, ["acme.style"], {}).rows;
    const registered = { "acme.style:open": {}, "acme.style:panel": {} };
    check("menuActivation: a listed, registered global runs", ctx.menuActivation(rows, registered, "acme.style:open"), "ok");
    check("menuActivation: a listed global no instance registered", ctx.menuActivation(rows, registered, "acme.style:gaps"), "refused: shortcut=acme.style:gaps reason=unregistered");
    check("menuActivation: a registered global no row lists", ctx.menuActivation(rows, registered, "acme.style:panel"), "refused: shortcut=acme.style:panel reason=unlisted");
    check("menuActivation: a category's empty global", ctx.menuActivation(rows, { "": {} }, ""), "refused: shortcut=\"\" reason=unlisted");
    check("menuActivation: a key that is no string", ctx.menuActivation(rows, registered, null), "refused: shortcut=null reason=unlisted");
    check("menuActivation: an inherited name is not registered", ctx.menuActivation([{ shortcut: "constructor" }], {}, "constructor"), "refused: shortcut=constructor reason=unregistered");
    check("menuActivation: a listed provider item runs", ctx.menuActivation(providerMenuRows, { "acme.catalog:open": {} }, "acme.catalog:open", "tools.clean", { "acme.catalog": providerValues }), "ok");
    check("menuActivation: a second provider row sharing the shortcut can run its own item", ctx.menuActivation(providerMenuRows, { "acme.catalog:open": {} }, "acme.catalog:open", "other", { "acme.catalog": providerValues }), "ok");
    check("menuActivation: provider values come from the provider's own plugin", ctx.menuActivation(providerMenuRows, { "acme.catalog:open": {} }, "acme.catalog:open", "tools.clean", { "other.plugin": providerValues }), "refused: shortcut=acme.catalog:open item=tools.clean reason=unlisted");
    check("menuActivation: a provider shortcut without item is refused", ctx.menuActivation(providerMenuRows, { "acme.catalog:open": {} }, "acme.catalog:open", undefined, { "acme.catalog": providerValues }), "refused: shortcut=acme.catalog:open reason=unlisted");
    check("menuActivation: an unlisted provider item is refused", ctx.menuActivation(providerMenuRows, { "acme.catalog:open": {} }, "acme.catalog:open", "tools.missing", { "acme.catalog": providerValues }), "refused: shortcut=acme.catalog:open item=tools.missing reason=unlisted");
    check("menuActivation: a provider menu item is refused", ctx.menuActivation(providerMenuRows, { "acme.catalog:open": {} }, "acme.catalog:open", "tools", { "acme.catalog": providerValues }), "refused: shortcut=acme.catalog:open item=tools reason=unlisted");
    check("menuActivation: a listed provider item needs a registration", ctx.menuActivation(providerMenuRows, {}, "acme.catalog:open", "tools.clean", { "acme.catalog": providerValues }), "refused: shortcut=acme.catalog:open reason=unregistered");
}

suite(load(LOGIC), report);

// Each control removes one rule from a copy of the judge and keeps the text
// around it; the suite must fail on every copy.
const CONTROLS = [
    ["menu is a manifest key", "\"tui\", \"menu\", \"secrets\"", "\"tui\", \"secrets\""],
    ["the menu is judged", "var badMenu = menuError(raw.menu, capabilities, schema, raw.status === undefined ? {} : raw.status);", "var badMenu = \"\";"],
    ["the menu is carried", "manifest.menu = raw.menu === undefined ? {} : clone(raw.menu);", "manifest.menu = {};"],
    ["a menu is a non-empty object", "if (!isPlainObject(menu) || Object.keys(menu).length === 0)", "if (false)"],
    ["a row id is dotted", "if (!MENU_ID_PATTERN.test(id))", "if (false)"],
    ["a row is an object", "if (!isPlainObject(item))\n            return at + \" must be an object\";\n        var keys = Object.keys(item);\n        for (var k = 0; k < keys.length; k++) {\n            if (MENU_ROW_KEYS", "if (false)\n            return at + \" must be an object\";\n        var keys = Object.keys(row);\n        for (var k = 0; k < keys.length; k++) {\n            if (MENU_ROW_KEYS"],
    ["a row has only its keys", "if (MENU_ROW_KEYS.indexOf(keys[k]) === -1)", "if (false)"],
    ["tui is a menu row key", "\"shortcut\", \"tui\", \"tuiGroup\", \"toggle\"", "\"shortcut\", \"toggle\""],
    ["a provider names launcher rows", "status[item.provider].type !== \"launcherRows\")", "false)"],
    ["a provider needs a shortcut", "if (item.shortcut === undefined)\n                return at + \".provider needs a shortcut\";", "if (false)\n                return at + \".provider needs a shortcut\";"],
    ["a provider refuses toggle", "if (item.toggle !== undefined)\n                return at + \".provider must not declare toggle\";", "if (false)\n                return at + \".provider must not declare toggle\";"],
    ["a provider refuses tui rows", "if (item.tui !== undefined || item.tuiGroup !== undefined)\n                return at + \".provider must not declare tui or tuiGroup\";", "if (false)\n                return at + \".provider must not declare tui or tuiGroup\";"],
    ["a row label is printable", "if (!isPrintableLine(item.label, MENU_TEXT_MAX))", "if (false)"],
    ["a row icon is shipped", "if (typeof item.icon !== \"string\" || !hasOwn(Lucide.ICONS, item.icon))", "if (false)"],
    ["aliases are printable", "if (item.aliases !== undefined && (!Array.isArray(item.aliases) || !item.aliases.every(", "if (false && (!Array.isArray(item.aliases) || !item.aliases.every("],
    ["a description is printable", "if (item.description !== undefined && !isPrintableLine(item.description, MENU_DESCRIPTION_MAX))", "if (false)"],
    ["a shortcut is a name", "if (typeof item.shortcut !== \"string\" || !NAME_PATTERN.test(item.shortcut))", "if (false)"],
    ["a shortcut needs the capability", "if (capabilities.indexOf(\"shortcut\") === -1)\n                return at + \".shortcut", "if (false)\n                return at + \".shortcut"],
    ["a tui key is valid", "if (item.tui !== undefined && !tuiKeyValid(item.tui))", "if (false)"],
    ["a tui group is printable", "if (item.tuiGroup !== undefined && !isPrintableLine(item.tuiGroup, MENU_TEXT_MAX))", "if (false)"],
    ["one row kind is stated", "if (kindKeys.length > 1)", "if (false)"],
    ["a toggle needs a shortcut", "if (item.shortcut === undefined)\n            return at + \".toggle needs a shortcut\";", "if (false)\n            return at + \".toggle needs a shortcut\";"],
    ["a toggle refuses tui rows", "if (item.tui !== undefined || item.tuiGroup !== undefined)\n            return at + \".toggle must not declare tui or tuiGroup\";", "if (false)\n            return at + \".toggle must not declare tui or tuiGroup\";"],
    ["a toggle is an object", "if (!isPlainObject(toggle))", "if (false)"],
    ["a toggle has only its keys", "if (MENU_TOGGLE_KEYS.indexOf(toggleKeys[t]) === -1)", "if (false)"],
    ["a toggle names a schema entry", "|| !hasOwn(schema, toggle.setting) || schema[toggle.setting].type", "|| !hasOwn(schema, toggle.setting) || false && schema[toggle.setting].type"],
    ["a toggle label is printable", "if (!isPrintableLine(toggle.label, MENU_TEXT_MAX))", "if (false)"],
    ["a toggle icon is shipped", "if (toggle.icon !== undefined && (typeof toggle.icon !== \"string\" || !hasOwn(Lucide.ICONS, toggle.icon)))", "if (false)"],
    ["rows go by plugin id", "enabledIds.filter(function (id) { return hasOwn(manifests, id); }).sort().forEach(", "enabledIds.filter(function (id) { return hasOwn(manifests, id); }).forEach("],
    ["a taken id stays with its first plugin", "if (owners[id] !== undefined) {", "if (false) {"],
    ["only true turns a toggle on", "settings[row.toggle.setting] === true;", "!!settings[row.toggle.setting];"],
    ["a toggle reads the plugins row", "var settings = settingsFor(config, manifest, \"plugins\", null);\n        ids.forEach(", "var settings = settingsFor(config, manifest, \"layout\", layoutEntryOf(config, manifest.id));\n        ids.forEach("],
    ["a toggle shows its label", "label: on ? row.toggle.label : row.label,", "label: row.label,"],
    ["a toggle shows its icon", "icon: on && row.toggle.icon !== undefined ? row.toggle.icon : row.icon,", "icon: on ? row.toggle.icon : row.icon,"],
    ["a row names its plugin's global", "shortcut: row.shortcut === undefined ? \"\" : plugin + \":\" + row.shortcut", "shortcut: row.shortcut === undefined ? \"\" : row.shortcut"],
    ["menuRows carries provider", "provider: row.provider === undefined ? \"\" : row.provider", "provider: \"\""],
    ["menuRows carries tui rows", "tui: row.tui === undefined ? \"\" : row.tui,\n                tuiGroup: row.tuiGroup === undefined ? \"\" : row.tuiGroup", "tui: \"\",\n                tuiGroup: \"\""],
    ["provider rows need published values", "if (parent === null || !isPlainObject(values) || !Array.isArray(values[parent.provider])) return [];", "if (parent === null) return [];"],
    ["provider item keeps id", "item: item.id", "item: row.id"],
    ["provider activation rejects menus", "published.id === item && published.menu !== true", "published.id === item"],
    ["provider activation checks every matching provider", "if (providerItemListed(row, values, item)) listed = true;", "listed = providerItemListed(row, values, item); break;"],
    ["provider activation reads the owning plugin's values", "hasOwn(valuesByPlugin, row.plugin) ? valuesByPlugin[row.plugin]", "hasOwn(valuesByPlugin, Object.keys(valuesByPlugin)[0]) ? valuesByPlugin[Object.keys(valuesByPlugin)[0]]"],
    ["plain activation excludes provider rows", "row.shortcut === key && (row.provider === undefined || row.provider === \"\")", "row.shortcut === key"],
    ["a category's own plugin's rows come first", ".concat(byTop[top].filter(function (row) { return row.plugin === owner; }), byTop[top].filter(function (row) { return row.plugin !== owner; }));", ".concat(byTop[top]);"],
    ["rows gather under their top-level id", "return { rows: ordered, conflicts: conflicts };", "return { rows: rows, conflicts: conflicts };"],
    ["a run is listed", "if (!listed)\n        return \"refused: shortcut=\"", "if (false)\n        return \"refused: shortcut=\""],
    ["a category's empty global is not listed", "typeof key === \"string\" && key !== \"\" && rows.some(", "typeof key === \"string\" && rows.some("],
    ["a run is registered", "if (!hasOwn(registered, key))\n        return \"refused: shortcut=\" + tuiLabel(key) + \" reason=unregistered\";\n    return \"ok\";\n}", "if (!(key in registered))\n        return \"refused: shortcut=\" + tuiLabel(key) + \" reason=unregistered\";\n    return \"ok\";\n}"]
];

const scratchRoot = path.join(__dirname, "..", "tmp");
fs.mkdirSync(scratchRoot, { recursive: true });
const temp = fs.mkdtempSync(path.join(scratchRoot, "plugin-menu-control-"));
try {
    fs.mkdirSync(path.join(temp, "shell", "Core"), { recursive: true });
    fs.mkdirSync(path.join(temp, "shell", "Ui", "icons"), { recursive: true });
    fs.mkdirSync(path.join(temp, "shell", "Commons"), { recursive: true });
    fs.symlinkSync(LUCIDE, path.join(temp, "shell", "Ui", "icons", "Lucide.js"));
    fs.symlinkSync(MANAGERS, path.join(temp, "shell", "Core", "PackageManagers.js"));
    fs.symlinkSync(LAYER, path.join(temp, "shell", "Core", "HyprlandLayer.js"));
    fs.symlinkSync(path.join(path.dirname(LAYER), "Pads.js"), path.join(temp, "shell", "Core", "Pads.js"));
    fs.symlinkSync(SETTING_VALUES, path.join(temp, "shell", "Commons", "SettingValues.js"));
    const source = fs.readFileSync(LOGIC, "utf8");
    for (const [label, needle, replacement] of CONTROLS) {
        const count = source.split(needle).length - 1;
        if (count !== 1) { report("control: " + label + ": the text to replace occurs once", count, 1); continue; }
        const mutant = path.join(temp, "shell", "Core", "PluginLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, () => replacement));
        // Loaded outside the try, so a copy that does not evaluate fails the
        // suite instead of passing for a control.
        const ctx = load(mutant);
        let red = 0;
        try {
            suite(ctx, (name, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) red += 1; });
        } catch (e) {
            red += 1;
        }
        report("control: the suite fails without the rule: " + label, red > 0, true);
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}

if (failures > 0) { console.log("test-plugin-menu: " + failures + " failing"); process.exit(1); }
console.log("test-plugin-menu: ok controls=" + CONTROLS.length);
