#!/usr/bin/env node
// The launcher's decisions, shell/plugins/vgs.launcher/MenuModel.js, under
// node: the menu file judge and its merge with the plugins' rows, the TUI
// rows, routes, ranking, the summon payload, select options and the file
// search helper's output. Every
// expected value is written out by hand. The shipped menu.json is judged
// too, so a defect in it fails here before the launcher logs it.
//
// The controls at the end edit a copy of the model, one rule at a time,
// and require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const dir = path.join(__dirname, "..", "shell", "plugins", "vgs.launcher");
const file = path.join(dir, "MenuModel.js");
const shippedMenu = fs.readFileSync(path.join(dir, "menu.json"), "utf8");
const RUNTIME = "/run/user/1000";
const menuText = items => JSON.stringify({ schemaVersion: 1, items: items });
// The model runs in its own context, whose arrays and objects are not this
// one's; values are compared as JSON.
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message === undefined ? JSON.stringify(want) : message);

// Menu files the judge refuses: [label, text, the start of the error].
const MENU_REFUSED = [
    ["not JSON", "{ nope", "not-json"],
    ["not an object", "[]", "not-object"],
    ["an unknown file key", JSON.stringify({ schemaVersion: 1, items: {}, extra: 1 }), "unknown key \"extra\""],
    ["a missing schema version", JSON.stringify({ items: {} }), "schemaVersion must be 1"],
    ["items that are no object", JSON.stringify({ schemaVersion: 1, items: [] }), "items must be an object"],
    ["an id with capitals", menuText({ Apps: {} }), "items.Apps is not a dotted lower-case id"],
    ["an item that is no object", menuText({ apps: "x" }), "items.apps must be an object"],
    ["an Omarchy action string", menuText({ apps: { action: "omarchy-launch" } }), "items.apps has unknown key \"action\""],
    ["a label that is no string", menuText({ apps: { label: 3 } }), "items.apps.label must be a string"],
    ["an empty label", menuText({ apps: { label: "" } }), "items.apps.label must not be empty"],
    ["an empty unavailable reason", menuText({ apps: { unavailable: "" } }), "items.apps.unavailable must name why"],
    ["aliases that are no list", menuText({ apps: { aliases: "app" } }), "items.apps.aliases must be a list"],
    ["a run that is a shell string", menuText({ apps: { run: "systemctl suspend" } }), "items.apps.run must be a non-empty list"],
    ["an empty run", menuText({ apps: { run: [] } }), "items.apps.run must be a non-empty list"],
    ["a run with an empty argument", menuText({ apps: { run: ["a", ""] } }), "items.apps.run must be a non-empty list"],
    ["a required command with a space", menuText({ apps: { requires: ["a b"] } }), "items.apps.requires must be a list of command names"],
    ["an unknown provider", menuText({ apps: { provider: "fonts" } }), "items.apps.provider must be one of apps, themes"],
    ["a parent that is no id", menuText({ "a.b": { parent: "A" } }), "items.a.b.parent is not an id"],
    ["a target that is no id", menuText({ apps: { target: "../x" } }), "items.apps.target is not an id"],
    ["a tui key that is no string", menuText({ apps: { tui: 3 } }), "items.apps.tui must be a string"],
    ["a tui key with no owner", menuText({ apps: { tui: "pkg-install" } }), "items.apps.tui is not a TUI key"],
    ["a tui key with capitals", menuText({ apps: { tui: "core/Pkg-install" } }), "items.apps.tui is not a TUI key"],
    ["a tui key that climbs", menuText({ apps: { tui: "core/../pkg-install" } }), "items.apps.tui is not a TUI key"],
    ["a tui group that is no string", menuText({ apps: { tuiGroup: ["Update"] } }), "items.apps.tuiGroup must be a string"],
    ["a blank tui group", menuText({ apps: { tuiGroup: " " } }), "items.apps.tuiGroup must be one printable line"],
    ["a tui group of two lines", menuText({ apps: { tuiGroup: "Up\ndate" } }), "items.apps.tuiGroup must be one printable line"]
];

// shell.tui.entries as the core lists it, by key: the core's own TUIs, and
// two plugins' entries in the Update group.
const CORE_ENTRIES = [
    { key: "core/pkg-install", plugin: "core", name: "pkg-install", title: "Install packages", label: "Install packages", icon: "package-plus", group: "Packages" },
    { key: "core/pkg-remove", plugin: "core", name: "pkg-remove", title: "Remove packages", label: "Remove packages", icon: "package-minus", group: "Packages" },
    { key: "core/sudo-grant", plugin: "core", name: "sudo-grant", title: "Passwordless sudo", label: "Passwordless sudo", icon: "shield-alert", group: "System" }
];
const UPDATES = { key: "acme.updates/pipeline", plugin: "acme.updates", name: "pipeline", title: "Update the system", label: "Update", icon: "refresh-cw", group: "Update" };
const ZETA = { key: "zeta.up/all", plugin: "zeta.up", name: "all", title: "Update all", label: "Update all", icon: "refresh-cw", group: "Update" };

// shell.shortcut.menu as the core lists it: vgs.themes' Style category and
// Theme row, vgs.bar's row under Style, and a third plugin's row whose id
// the shipped menu holds.
const STYLE = { id: "style", plugin: "vgs.themes", label: "Style", icon: "paintbrush", aliases: [], description: "", shortcut: "" };
const THEME = { id: "style.theme", plugin: "vgs.themes", label: "Theme", icon: "palette", aliases: ["themes"], description: "", shortcut: "vgs.themes:themes" };
const BAR = { id: "style.bar", plugin: "vgs.bar", label: "Hide top bar", icon: "panel-top-close", aliases: [], description: "Give the bar's space to windows", shortcut: "vgs.bar:toggle" };
const TAKEN = { id: "system", plugin: "acme.taken", label: "Mine", icon: "star", aliases: [], description: "", shortcut: "acme.taken:go" };

// Payloads the judge refuses: [label, text, the start of the error].
const PAYLOAD_REFUSED = [
    ["not JSON", "nope", "payload=not-json"],
    ["a list", "[1]", "payload=not-object"],
    ["an Omarchy key", JSON.stringify({ fontFamily: "x" }), "payload=unknown-key key=fontFamily"],
    ["an unknown mode", JSON.stringify({ mode: "dmenu" }), "payload=mode got=\"dmenu\""],
    ["a menu that is no string", JSON.stringify({ menu: 3 }), "payload=menu want=string"],
    ["a width out of range", JSON.stringify({ mode: "select", width: 0, selectionFile: RUNTIME + "/a", doneFile: RUNTIME + "/b" }), "payload=width want=1..4096"],
    ["a picker without a done file", JSON.stringify({ mode: "select", selectionFile: RUNTIME + "/a" }), "payload=doneFile missing"],
    ["a picker writing outside the runtime directory", JSON.stringify({ mode: "select", selectionFile: "/tmp/a", doneFile: RUNTIME + "/b" }), "payload=selectionFile outside=" + RUNTIME],
    ["a picker path climbing out", JSON.stringify({ mode: "select", selectionFile: RUNTIME + "/../etc/a", doneFile: RUNTIME + "/b" }), "payload=selectionFile outside="],
    ["a picker path with a newline", JSON.stringify({ mode: "select", selectionFile: RUNTIME + "/a\nb", doneFile: RUNTIME + "/b" }), "payload=selectionFile outside="],
    ["one file for both answers", JSON.stringify({ mode: "select", selectionFile: RUNTIME + "/a", doneFile: RUNTIME + "/a" }), "payload=doneFile same-as=selectionFile"],
    ["a picker with a route", JSON.stringify({ mode: "select", menu: "apps", selectionFile: RUNTIME + "/a", doneFile: RUNTIME + "/b" }), "payload=select takes no menu or query"],
    ["picker keys on a menu", JSON.stringify({ prompt: "x" }), "payload=prompt needs mode=select|input"],
    ["options on an input", JSON.stringify({ mode: "input", options: ["a"], selectionFile: RUNTIME + "/a", doneFile: RUNTIME + "/b" }), "payload=options needs mode=select"],
    ["options that are no strings", JSON.stringify({ mode: "select", options: [1], selectionFile: RUNTIME + "/a", doneFile: RUNTIME + "/b" }), "payload=options want=list-of-strings"],
    ["more options than the card holds", JSON.stringify({ mode: "select", options: Array(2001).fill("x"), selectionFile: RUNTIME + "/a", doneFile: RUNTIME + "/b" }), "payload=options count=2001 max=2000"]
];

function verify(model) {
    assert.equal(model.actionErrorText("refused: tui=core/pkg-install reason=launcher-missing"), "The setup window could not open. VGS is missing its terminal launcher, xdg-terminal-exec. Reinstall VGS to restore it.");
    assert.equal(model.actionErrorText("refused: tui=core/pkg-install reason=launcher-failed"), "VGS could not open this action. Try again.");
    // Producer diagnostics never cross the display boundary.
    for (const diagnostic of ["file-search: missing=fd,fzf", "file-search: refresh=busy", "file-search: vanished=/file", "file-search: mime=x error=gio-status-1", "file-search: index=f error=unreadable", "file-search: start=failed", "unexpected: key=value"]) {
        const text = model.fileErrorText(diagnostic);
        assert.ok(text.length > 0, "a failed operation must tell the user");
        assert.doesNotMatch(text, /[a-z][a-z-]*=|start-failed|output-unreadable/, "diagnostic fields stay in logs");
    }

    // The shipped menu is accepted and merges alone.
    const shipped = model.parseMenu(shippedMenu);
    assert.equal(shipped.ok, true, shipped.error);
    const alone = model.mergeMenuSources(shipped.entries, []);
    assert.equal(alone.ok, true, alone.error);
    assert.equal(alone.itemOrder[0], "root", "a menu without a root gets one first");
    assert.equal(alone.items.apps.provider, "apps");
    same(alone.items["tools.screenshot"].run, ["vgsh", "ipc", "call", "vgs.capture", "invoke", "screenshot-area", "{}"], "Screenshot asks the capture service");
    assert.equal(alone.items["system.reboot"].kind, "action");
    assert.equal(alone.items["system.reboot"].parent, "system");
    same(["install", "remove", "update"].map(id => [alone.items[id].kind, alone.items[id].tui, alone.items[id].tuiGroup]),
        [["tui", "core/pkg-install", ""], ["tui", "core/pkg-remove", ""], ["tui", "", "Update"]]);
    // Lock asks the shell's own lock through `vgsh lock`: loginctl only
    // asks a logind listener the shell does not provide. Without vgsh on
    // PATH the row says so.
    same(alone.items["system.lock"].run, ["vgsh", "lock"]);
    same(alone.items["system.lock"].requires, ["vgsh"]);
    same(model.menuRows(alone.items, alone.itemOrder, "system", ["vgsh"]).filter(r => r.label === "Lock").map(r => [r.kind, r.detail]), [["unavailable", "needs vgsh"]]);

    for (const [label, text, start] of MENU_REFUSED) {
        const result = model.parseMenu(text);
        assert.equal(result.ok, false, label);
        assert.ok(result.error.startsWith(start), `${label}: ${result.error}`);
    }

    // The user file merges per key: one label changes, the row keeps the
    // shipped keys; a new row is appended; a row stating two kinds refuses.
    const user = model.parseMenu(menuText({ system: { label: "Power" }, "tools.mine": { label: "Mine", run: ["true"] } }));
    const merged = model.mergeMenuSources(shipped.entries, user.entries);
    assert.equal(merged.ok, true);
    assert.equal(merged.items.system.label, "Power");
    same(merged.items.system.aliases, ["power-menu", "power"]);
    assert.equal(merged.items["tools.mine"].parent, "tools");
    assert.equal(merged.itemOrder[merged.itemOrder.length - 1], "tools.mine");
    const both = model.mergeMenuSources(shipped.entries, model.parseMenu(menuText({ "system.reboot": { target: "apps" } })).entries);
    assert.equal(both.ok, false);
    assert.equal(both.error, "items.system.reboot states run and target");
    assert.equal(model.mergeMenuSources([], model.parseMenu(menuText({ x: { parent: "" } })).entries).items.x.parent, "");
    const tuiRun = model.mergeMenuSources(shipped.entries, model.parseMenu(menuText({ install: { run: ["true"] } })).entries);
    assert.equal(tuiRun.error, "items.install states run and tui");
    const keyAndGroup = model.mergeMenuSources(shipped.entries, model.parseMenu(menuText({ update: { tui: "core/pkg-install" } })).entries);
    assert.equal(keyAndGroup.error, "items.update states tui and tuiGroup");
    const otherKey = model.mergeMenuSources(shipped.entries, model.parseMenu(menuText({ install: { tui: "acme.tui/hello" } })).entries);
    assert.equal(otherKey.ok, true, "a user row may point a shipped tui row at another key");
    assert.equal(otherKey.items.install.tui, "acme.tui/hello");

    // TUI rows: a key opens when listed, a group opens its first listed
    // entry in the list's order, and a row that resolves to nothing hides.
    const judgedTuis = model.parseMenu(menuText({ a: { tui: "core/pkg-install" }, b: { tui: "acme.tui/hello" }, c: { tuiGroup: "Update" } }));
    assert.equal(judgedTuis.ok, true, judgedTuis.error);
    const tuiKeys = (from, entries) => {
        const resolved = model.resolveTuiRows(from.items, from.itemOrder, entries);
        return ["install", "remove", "update"].map(id => resolved[id].tuiKey);
    };
    same(tuiKeys(alone, CORE_ENTRIES), ["core/pkg-install", "core/pkg-remove", ""], "no Update entry leaves update unresolved");
    same(tuiKeys(alone, CORE_ENTRIES.concat([UPDATES])), ["core/pkg-install", "core/pkg-remove", "acme.updates/pipeline"]);
    same(tuiKeys(alone, [ZETA, UPDATES]), ["", "", "zeta.up/all"], "the first Update entry in the list wins");
    same(tuiKeys(alone, [UPDATES, ZETA]), ["", "", "acme.updates/pipeline"], "the first Update entry in the list wins");
    same(tuiKeys(alone, [Object.assign({}, UPDATES, { key: "core/pkg-install", group: "Packages" })]), ["core/pkg-install", "", ""], "a key row matches by key, never by group");
    const enabled = model.resolveTuiRows(alone.items, alone.itemOrder, CORE_ENTRIES.concat([UPDATES]));
    assert.equal(alone.items.update.tuiKey, "", "the map handed in is never written");
    same(model.menuRows(enabled, alone.itemOrder, "root", []).filter(r => r.kind === "tui").map(r => r.label), ["Install", "Remove", "Update"]);
    same(tuiKeys({ items: enabled, itemOrder: alone.itemOrder }, CORE_ENTRIES), ["core/pkg-install", "core/pkg-remove", ""], "a disabled plugin's entry leaving the list unresolves the row");
    const disabled = model.resolveTuiRows(enabled, alone.itemOrder, CORE_ENTRIES);
    same(model.menuRows(disabled, alone.itemOrder, "root", []).filter(r => r.kind === "tui").map(r => r.label), ["Install", "Remove"], "an unresolved row is hidden");
    same(model.searchRows(disabled, alone.itemOrder, "root", "update", []).map(r => r.label), [], "an unresolved row is hidden from search");
    same(model.menuRows(model.resolveTuiRows(alone.items, alone.itemOrder, []), alone.itemOrder, "root", []).filter(r => r.kind === "tui"), [], "an empty list hides every tui row");

    // Plugin rows: a row with a shortcut runs it, one without is a
    // category; they merge after the shipped menu and before the user's,
    // which can relabel one; a plugin row cannot take a shipped id.
    same(model.pluginEntries([STYLE, THEME, BAR]), [
        { id: "style", raw: { label: "Style", icon: "paintbrush", aliases: [] } },
        { id: "style.theme", raw: { label: "Theme", icon: "palette", aliases: ["themes"], shortcut: "vgs.themes:themes" } },
        { id: "style.bar", raw: { label: "Hide top bar", icon: "panel-top-close", aliases: [], description: "Give the bar's space to windows", shortcut: "vgs.bar:toggle" } }
    ]);
    const plugged = model.mergeMenuSources(shipped.entries, [], model.pluginEntries([STYLE, THEME, BAR, TAKEN]));
    assert.equal(plugged.ok, true, plugged.error);
    same(plugged.refused, ["system"], "a plugin row with a shipped id is refused");
    assert.equal(plugged.items.system.label, "System", "the shipped row stands");
    same(["style", "style.theme", "style.bar"].map(id => [plugged.items[id].kind, plugged.items[id].parent, plugged.items[id].shortcut]),
        [["menu", "root", ""], ["shortcut", "style", "vgs.themes:themes"], ["shortcut", "style", "vgs.bar:toggle"]]);
    same(model.menuRows(plugged.items, plugged.itemOrder, "root", []).map(r => [r.kind, r.label]),
        [["menu", "Apps"], ["menu", "System"], ["menu", "Tools"], ["menu", "Style"]], "plugin rows follow the shipped rows; unresolved tui rows hide");
    same(model.menuRows(plugged.items, plugged.itemOrder, "style", []).map(r => [r.kind, r.label, r.detail]),
        [["shortcut", "Theme", ""], ["shortcut", "Hide top bar", "Give the bar's space to windows"]]);
    same(model.searchRows(plugged.items, plugged.itemOrder, "root", "top bar", []).map(r => [r.kind, r.label]), [["shortcut", "Hide top bar"]], "a search finds a plugin row");
    const relabelled = model.mergeMenuSources(shipped.entries, model.parseMenu(menuText({ "style.theme": { label: "Pick a theme" } })).entries, model.pluginEntries([STYLE, THEME]));
    same([relabelled.items["style.theme"].label, relabelled.items["style.theme"].shortcut], ["Pick a theme", "vgs.themes:themes"], "the user's file relabels a plugin row");
    // A user row with a kind of its own replaces a plugin row's kind and
    // keeps its other keys; one that states two kinds itself is refused,
    // and a shipped row's kind is never replaced.
    const runOnPlugin = model.mergeMenuSources(shipped.entries, model.parseMenu(menuText({ "style.theme": { run: ["waypaper"] } })).entries, model.pluginEntries([STYLE, THEME]));
    assert.equal(runOnPlugin.ok, true, runOnPlugin.error);
    same([runOnPlugin.items["style.theme"].kind, runOnPlugin.items["style.theme"].run, runOnPlugin.items["style.theme"].shortcut, runOnPlugin.items["style.theme"].label], ["action", ["waypaper"], "", "Theme"]);
    const tuiOnPlugin = model.mergeMenuSources(shipped.entries, model.parseMenu(menuText({ "style.theme": { tui: "core/pkg-install" } })).entries, model.pluginEntries([STYLE, THEME]));
    same([tuiOnPlugin.items["style.theme"].kind, tuiOnPlugin.items["style.theme"].tui], ["tui", "core/pkg-install"]);
    const twoOnPlugin = model.mergeMenuSources(shipped.entries, model.parseMenu(menuText({ "style.theme": { run: ["true"], target: "apps" } })).entries, model.pluginEntries([STYLE, THEME]));
    assert.equal(twoOnPlugin.error, "items.style.theme states run and target");
    // The launcher's merge: a refused user file leaves its rows out and names
    // why; an accepted one carries no error, so its notice goes.
    const refusedMerge = model.mergeMenu(shipped.entries, model.parseMenu(menuText({ "install": { run: ["true"] }, "tools.mine": { label: "Mine", run: ["true"] } })).entries, model.pluginEntries([STYLE, THEME]));
    same([refusedMerge.ok, refusedMerge.error, "tools.mine" in refusedMerge.items, refusedMerge.items["style.theme"].kind], [true, "items.install states run and tui", false, "shortcut"]);
    const acceptedMerge = model.mergeMenu(shipped.entries, model.parseMenu(menuText({ "tools.mine": { label: "Mine", run: ["true"] } })).entries, model.pluginEntries([STYLE, THEME]));
    same([acceptedMerge.error, acceptedMerge.items["tools.mine"].kind], ["", "action"]);
    same(model.menuNotices({}, ""), [], "no refusal shows no notice");
    same(model.menuNotices({}, "items.install states run and tui"), [{ source: "user", error: "items.install states run and tui" }], "a merge refusal shows under the user's file");
    same(model.menuNotices({ user: "not-json: x" }, "items.install states run and tui"), [{ source: "user", error: "not-json: x" }], "a read refusal of the user's file stands for it");
    same(model.menuNotices({ user: "not-json: x", shipped: "not-object" }, ""), [{ source: "shipped", error: "not-object" }, { source: "user", error: "not-json: x" }], "the shipped file's refusal shows first");
    // Routes: an action row or a plugin's row, by id or alias, runs without
    // opening; a menu opens; an unknown route opens the root.
    same(model.routeTarget(plugged.items, plugged.itemOrder, "themes"), { action: "shortcut", shortcut: "vgs.themes:themes" });
    same(model.routeTarget(plugged.items, plugged.itemOrder, "style.theme"), { action: "shortcut", shortcut: "vgs.themes:themes" });
    same(model.routeTarget(plugged.items, plugged.itemOrder, "system.reboot"), { action: "run", run: ["systemctl", "reboot"] });
    same(model.routeTarget(plugged.items, plugged.itemOrder, "power"), { action: "open", menu: "system" });
    same(model.routeTarget(plugged.items, plugged.itemOrder, "style"), { action: "open", menu: "style" });
    same(model.routeTarget(plugged.items, plugged.itemOrder, "nowhere"), { action: "open", menu: "root" });
    const linked = model.mergeMenuSources([], model.parseMenu(menuText({ a: { label: "A", run: ["true"] }, b: { label: "B", target: "a" } })).entries);
    same(model.routeTarget(linked.items, linked.itemOrder, "b"), { action: "open", menu: "a" });
    // A row whose parent, or any parent above it, is not in the menu is
    // hidden from its menu and from search: the bar's row leaves with the
    // Style category vgs.themes declares.
    const orphan = model.mergeMenuSources(shipped.entries, [], model.pluginEntries([BAR]));
    same(model.menuRows(orphan.items, orphan.itemOrder, "root", []).map(r => r.label), ["Apps", "System", "Tools"]);
    same(model.searchRows(orphan.items, orphan.itemOrder, "root", "top bar", []), [], "an orphaned row is hidden from search");
    const deep = model.mergeMenuSources([], model.parseMenu(menuText({ "a.b": { label: "B" }, "a.b.c": { label: "C", run: ["true"] } })).entries);
    same(model.searchRows(deep.items, deep.itemOrder, "root", "c", []), [], "a row whose grandparent is missing is hidden");
    same(model.menuRows(model.mergeMenuSources([], [], model.pluginEntries([STYLE])).items, ["root", "style"], "root", []), [], "a category with no row is hidden");

    // Routes: an id, an alias, a link's id, and an app's keyword that must
    // not shadow a menu.
    const items = model.resolveTuiRows(merged.items, merged.itemOrder, CORE_ENTRIES);
    const order = merged.itemOrder;
    assert.equal(model.resolveRoute(items, order, ""), "root");
    assert.equal(model.resolveRoute(items, order, "Menu"), "root");
    assert.equal(model.resolveRoute(items, order, "system"), "system");
    assert.equal(model.resolveRoute(items, order, "power_menu"), "system");
    assert.equal(model.resolveRoute(items, order, "nowhere"), "nowhere");
    const shadow = model.mergeMenuSources([], model.parseMenu(menuText({ a: { aliases: ["b"], run: ["true"] }, b: { run: ["true"] } })).entries);
    assert.equal(model.resolveRoute(shadow.items, shadow.itemOrder, "b"), "b", "an exact id wins over an alias");
    const withApps = model.swapProviderRows(items, order, "apps", [model.appRow("apps", { id: "htop", name: "Htop", keywords: ["system", "monitor"], icon: "htop" })]);
    assert.equal(model.resolveRoute(withApps.items, withApps.itemOrder, "monitor"), "monitor", "an app keyword is never a route");
    assert.equal(withApps.items["apps.htop"].appId, "htop");
    assert.equal(items["apps.htop"], undefined, "the maps handed in are never written");

    // A provider's rows are swapped whole, and a taken id is listed once.
    const again = model.swapProviderRows(withApps.items, withApps.itemOrder, "apps", [model.appRow("apps", { id: "zen", name: "Zen Browser" }), model.appRow("apps", { id: "zen", name: "Zen Twice" })]);
    assert.equal(again.items["apps.htop"], undefined);
    assert.equal(again.itemOrder.filter(id => id === "apps.zen").length, 1);
    assert.equal(again.items["apps.zen"].label, "Zen Browser");

    // An application list change swaps every loaded apps menu in one step,
    // an application that left included, and answers one consistent pair.
    // A loaded menu of another provider keeps its rows.
    const twoMenus = model.mergeMenuSources([], model.parseMenu(menuText({ apps: { provider: "apps" }, games: { provider: "apps" }, more: { provider: "apps" }, tools: { label: "Tools" }, looks: { provider: "themes" } })).entries);
    const looks = model.swapProviderRows(twoMenus.items, twoMenus.itemOrder, "looks", [model.themeRow("looks", { name: "vgs", source: "shipped", state: "ok", reason: null, current: true })]);
    const appsLoaded = { apps: true, games: true, looks: true };
    const firstApps = model.swapAppMenus(looks.items, looks.itemOrder, appsLoaded, [{ id: "a", name: "Alpha" }, { id: "b", name: "Beta" }]);
    same(firstApps.itemOrder, ["root", "apps", "games", "more", "tools", "looks", "looks.vgs", "apps.a", "apps.b", "games.a", "games.b"]);
    const left = model.swapAppMenus(firstApps.items, firstApps.itemOrder, appsLoaded, [{ id: "a", name: "Alpha" }, { id: "c", name: "Gamma" }]);
    same(left.itemOrder, ["root", "apps", "games", "more", "tools", "looks", "looks.vgs", "apps.a", "apps.c", "games.a", "games.c"], "a menu that is not loaded, or not apps, gets no app rows");
    assert.equal(left.items["looks.vgs"].kind, "theme", "a themes menu keeps its rows");
    same(Object.keys(left.items).sort(), [...left.itemOrder].sort(), "the items and the order hold the same ids");
    same([left.items["apps.c"].label, left.items["games.a"].parent], ["Gamma", "games"]);
    const unloaded = model.swapAppMenus(firstApps.items, firstApps.itemOrder, {}, []);
    assert.equal(unloaded.items, firstApps.items, "with no apps menu loaded the maps handed in come back");
    assert.equal(unloaded.itemOrder, firstApps.itemOrder);

    // Theme packages: the current one is checked; a refused one shows why.
    const themes = model.swapProviderRows(again.items, again.itemOrder, "style.theme", [
        model.themeRow("style.theme", { name: "vgs", source: "shipped", state: "ok", reason: null, current: true }),
        model.themeRow("style.theme", { name: "broken", source: "installed", state: "refused", reason: "name-mismatch", current: false })
    ]);
    assert.equal(themes.items["style.theme.vgs"].kind, "theme");
    assert.equal(themes.items["style.theme.vgs"].icon, "check");
    assert.equal(themes.items["style.theme.broken"].kind, "unavailable");
    assert.equal(themes.items["style.theme.broken"].description, "Unavailable");

    // Search and rank: an app named with the whole word wins over an exact
    // menu label; deeper matches sit after direct ones in the drilldown.
    const found = model.searchRows(again.items, again.itemOrder, "root", "zen", []);
    same(found.map(r => [r.kind, r.label]), [["app", "Zen Browser"]]);
    const zen = model.mergeMenuSources([], model.parseMenu(menuText({ install: { label: "Install" }, "install.zen": { label: "Zen", run: ["true"] }, apps: { provider: "apps" } })).entries);
    const zenApps = model.swapProviderRows(zen.items, zen.itemOrder, "apps", [model.appRow("apps", { id: "zen", name: "Zen Browser" })]);
    same(model.searchRows(zenApps.items, zenApps.itemOrder, "root", "zen", []).map(r => [r.kind, r.label]), [["app", "Zen Browser"], ["action", "Zen"]], "an app named with the whole word beats an exact menu label");
    const reboot = model.searchRows(again.items, again.itemOrder, "root", "reb", []);
    same(reboot.map(r => [r.label, r.detail, r.section]), [["Reboot", "Power", ""]]);
    const re = model.searchRows(again.items, again.itemOrder, "root", "re", []);
    same(re.map(r => [r.label, r.section]), [["Remove", ""], ["Reboot", "drilldown"], ["Screenshot", "drilldown"]]);
    same(model.searchRows(again.items, again.itemOrder, "system", "lock", []).map(r => r.label), ["Lock"]);
    assert.equal(model.matchesQuery(alone.items.system, "power"), true, "an alias matches");
    assert.equal(model.matchesQuery(again.items["tools.screenshot"], "region"), true, "a whole description word matches");
    assert.equal(model.matchesQuery(again.items["tools.screenshot"], "regi"), false, "a part of a description word does not");

    // Menu rows: in file order, a menu with no visible row hidden, apps by
    // label, a missing command named.
    const roots = model.menuRows(again.items, again.itemOrder, "root", []);
    same(roots.map(r => r.label), ["Apps", "Power", "Tools", "Install", "Remove"]);
    const lacking = model.menuRows(again.items, again.itemOrder, "tools", ["grim"]);
    same(lacking.filter(r => r.kind === "unavailable").map(r => [r.label, r.detail]), [], "Capture owns missing-tool setup");
    assert.equal(lacking.find(r => r.label === "Screenshot").kind, "action");
    const empty = model.mergeMenuSources([], model.parseMenu(menuText({ bare: {} })).entries);
    same(model.menuRows(empty.items, empty.itemOrder, "root", []), [], "a static menu with no row is hidden");
    const sorted = model.swapProviderRows(again.items, again.itemOrder, "apps", [model.appRow("apps", { id: "b", name: "beta" }), model.appRow("apps", { id: "a", name: "Alpha" })]);
    same(model.menuRows(sorted.items, sorted.itemOrder, "apps", []).map(r => r.label), ["Alpha", "beta"]);
    assert.equal(model.pathFor(again.items, "system.reboot"), "Power \u203a Reboot");
    assert.equal(model.depthFor(again.items, "system.reboot"), 1);
    const cycle = model.mergeMenuSources([], model.parseMenu(menuText({ a: { parent: "b" }, b: { parent: "a" } })).entries);
    assert.equal(model.depthFor(cycle.items, "a"), 32, "a parent cycle stops at the depth limit");
    assert.equal(model.isDescendantOf(cycle.items, "a", "root"), true);
    assert.equal(model.isDescendantOf(cycle.items, "a", "c"), false);

    // Theme apply results.
    for (const [state, want] of [["applied", true], ["unchanged", true], ["partial", false], ["failed", false], ["", false]])
        assert.equal(model.applySucceeded({ state: state, shell: "unchanged", targets: [], theme: "vgs", reason: null }), want, "apply state " + state);
    assert.equal(model.applySucceeded(null), false, "no result is no success");

    // Payloads.
    const bare = model.parsePayload("", RUNTIME);
    assert.equal(bare.ok, true);
    same([bare.payload.mode, bare.payload.menu, bare.payload.query], ["menu", "root", ""]);
    const pick = model.parsePayload(JSON.stringify({ mode: "select", options: ["a", "b"], selectionFile: RUNTIME + "/s", doneFile: RUNTIME + "/d", width: 420 }), RUNTIME);
    assert.equal(pick.ok, true, pick.error);
    same([pick.payload.prompt, pick.payload.width, pick.payload.options], ["Select", 420, ["a", "b"]]);
    const input = model.parsePayload(JSON.stringify({ mode: "input", selectionFile: RUNTIME + "/s", doneFile: RUNTIME + "/d" }), RUNTIME + "/");
    assert.equal(input.ok, true, input.error);
    assert.equal(input.payload.prompt, "Input");
    for (const [label, text, start] of PAYLOAD_REFUSED) {
        const result = model.parsePayload(text, RUNTIME);
        assert.equal(result.ok, false, label);
        assert.ok(result.error.startsWith(start), `${label}: ${result.error}`);
    }
    assert.equal(model.parsePayload(JSON.stringify({ mode: "select", selectionFile: RUNTIME + "/s", doneFile: RUNTIME + "/d" }), "").ok, false, "no runtime directory admits no file");

    // Options and selections.
    same(model.parseOption("plain"), { icon: "", label: "plain", detail: "" });
    same(model.parseOption("g\tlabel\tdetail\tmore"), { icon: "g", label: "label", detail: "detail\tmore" });
    const options = model.optionRows(["alpha", "g\tbeta\tsecond", "gamma"], "SEC");
    same(options.map(r => [r.itemId, r.label, r.detail]), [["option.1", "beta", "second"]]);
    assert.equal(model.selectionOf(options[0]), "beta\tsecond");
    assert.equal(model.selectionOf({ label: "alpha", detail: "" }), "alpha");
    assert.equal(model.dropWord("open the file "), "open the ");
    assert.equal(model.dropWord("one"), "");

    // File search.
    same(model.fileMode("f: report "), { mode: "f", query: "report" });
    same(model.fileMode("F:docs"), { mode: "d", query: "docs" });
    same(model.fileMode("ff"), { mode: "", query: "" });
    const hits = model.parseFileResults([
        "100\ttext/plain\t/home/u/a/notes.txt",
        "300\ttext/plain\t/home/u/b/notes.txt",
        "200\tinode/directory\t/home/u/docs",
        "junk line",
        "x\ttext/plain\t/home/u/c",
        "1\ttext/plain\trelative/path",
        "50\ttext/plain\t/top.txt",
        ""
    ].join("\n"), "/home/u");
    same(hits.rows.map(r => [r.name, r.dir, r.mtime]), [["notes.txt", "~/b", 300], ["notes.txt", "~/a", 100], ["docs", "~", 200], ["top.txt", "/", 50]]);
    assert.equal(hits.malformed, 3);
    const constructor = model.parseFileResults("1\ttext/plain\t/x/constructor", "/home/u");
    same(constructor.rows.map(r => r.name), ["constructor"], "a file named like an object key is a name");
    const apps = model.parseOpenWith("other\t/usr/share/applications/b.desktop\ndefault\t/usr/share/applications/a.desktop\nnoise\n");
    same(apps.map(a => [a.id, a.isDefault]), [["a", true], ["b", false]]);
}
verify(load(file));

// Each control removes one rule from a copy of the model and keeps the
// text around it. The suite must fail on every copy.
const CONTROLS = [
    ["a missing launcher needs installation repair", 'if (/reason=launcher-missing/.test(String(reason)))', 'if (false)'],
    ["diagnostics stay out of display text", 'function fileErrorText(reason) {', 'function fileErrorText(reason) { return String(reason);'],
    ["unknown item key", "if (ITEM_KEYS.indexOf(keys[i]) === -1) return at", "if (false) return at"],
    ["run list", 'if (hasOwn(raw, "run") && !(isStringList(raw.run) && raw.run.length > 0))', 'if (false)'],
    ["requires names", 'if (hasOwn(raw, "requires") && !isStringList(raw.requires, COMMAND_PATTERN))', "if (false)"],
    ["schema version", "if (document.schemaVersion !== SCHEMA_VERSION)", "if (false)"],
    ["merge per key", "merged[entry.id][key] = entry.raw[key];", "merged[entry.id] = entry.raw;"],
    ["one kind per row", "if (stated.length > 1)", "if (false)"],
    ["tui exclusive", '"provider", "unavailable", "tui", "tuiGroup", "shortcut"]', '"provider", "unavailable", "shortcut"]'],
    ["shortcut exclusive", '"tui", "tuiGroup", "shortcut"]', '"tui", "tuiGroup"]'],
    ["shortcut kind", 'hasOwn(raw, "shortcut") ? "shortcut"', 'false ? "shortcut"'],
    ["a category runs nothing", 'if (row.shortcut !== "") raw.shortcut = row.shortcut;', "raw.shortcut = row.shortcut;"],
    ["a plugin row takes no shipped id", "if (shippedIds.indexOf(entry.id) === -1) return true;", "return true;"],
    ["plugin rows merge before the user's", "var sources = [shipped || [], plugins, user || []];", "var sources = [shipped || [], user || [], plugins];"],
    ["a user kind replaces a plugin row's", "if (s === 2 && pluginIds.indexOf(entry.id) !== -1 && KIND_KEYS.some(", "if (false && KIND_KEYS.some("],
    ["only a plugin row's kind is replaced", "if (s === 2 && pluginIds.indexOf(entry.id) !== -1 && KIND_KEYS.some(", "if (s === 2 && KIND_KEYS.some("],
    ["an accepted merge carries no error", 'if (merged.ok) return Object.assign(merged, { error: "" });', 'if (merged.ok) return Object.assign(merged, { error: "stale" });'],
    ["a refused merge leaves the user's file out", "var fallback = mergeMenuSources(shipped, [], plugin);", "var fallback = mergeMenuSources(shipped, (user || []).filter(function (entry) { return entry.id !== \"install\"; }), plugin);"],
    ["a merge refusal shows a notice", 'if (mergeError !== "" && !hasOwn(refusals, "user")) out.push(', "if (false) out.push("],
    ["a read refusal stands for the user's file", 'if (mergeError !== "" && !hasOwn(refusals, "user")) out.push(', 'if (mergeError !== "") out.push('],
    ["a plugin row's route runs it", 'if (entry !== undefined && entry.kind === "shortcut") return', "if (false) return"],
    ["an action route runs it", 'if (entry !== undefined && entry.kind === "action") return', "if (false) return"],
    ["a link route opens its target", 'var target = entry !== undefined && entry.kind === "link" ? entry.target : id;', "var target = id;"],
    ["an orphan is hidden", "if (!isAttached(items, entry)) return false;", ""],
    ["every parent up to the root", "current = items[current.parent];\n        if (current === undefined) return false;", "return hasOwn(items, current.parent);"],
    ["tui key shape", 'if (hasOwn(raw, "tui") && !TUI_KEY_PATTERN.test(raw.tui))', "if (false)"],
    ["tui group printable", 'if (hasOwn(raw, "tuiGroup") && (raw.tuiGroup.trim().length === 0 || CONTROL_PATTERN.test(raw.tuiGroup)))', "if (false)"],
    ["tui kind", 'hasOwn(raw, "tui") || hasOwn(raw, "tuiGroup") ? "tui"', 'false ? "tui"'],
    ["listed key", "entries[i].key === entry.tui :", "true :"],
    ["group match", "entries[i].group === entry.tuiGroup)", 'entries[i].group !== "")'],
    ["first in list", "for (var i = 0; i < entries.length; i++) {\n        if (entry.tui", "for (var i = entries.length - 1; i >= 0; i--) {\n        if (entry.tui"],
    ["resolution is fresh", "Object.assign({}, entry, { tuiKey: tuiKeyFor(entry, entries) })", "(entry.tuiKey = tuiKeyFor(entry, entries), entry)"],
    ["unresolved hidden", 'if (entry.kind === "tui") return entry.tuiKey !== "";', 'if (entry.kind === "tui") return true;'],
    ["exact id first", "if (hasOwn(items, raw)) return raw;", ""],
    ["apps are no route", 'if (entry.kind === "app") continue;\n        for', "for"],
    ["handed maps unwritten", "var row = Object.assign({}, rows[j], { providerMenu: menuId, order: nextOrder.length });", "var row = rows[j]; row.providerMenu = menuId; row.order = nextOrder.length; items[row.id] = row;"],
    ["taken id once", "if (hasOwn(nextItems, rows[j].id)) continue;", ""],
    ["apps menus picked before the first swap",
        "var menus = itemOrder.filter(function (id) { return items[id].provider === \"apps\" && loaded[id] === true; });\n    var next = { items: items, itemOrder: itemOrder };\n    for (var i = 0; i < menus.length; i++) {\n        var menuId = menus[i];",
        "var next = { items: items, itemOrder: itemOrder };\n    for (var i = 0; i < itemOrder.length; i++) {\n        var menuId = itemOrder[i];\n        if (!(next.items[menuId].provider === \"apps\" && loaded[menuId] === true)) continue;"],
    ["only loaded apps menus swap", "loaded[id] === true; });", "true; });"],
    ["only apps menus swap", 'return items[id].provider === "apps" && loaded', "return loaded"],
    ["whole app word", 'else if (entry.kind === "app" && label.split(/\\s+/).indexOf(needle) >= 0) score = 0;', ""],
    ["drilldown section", 'for (var d = 0; d < deeper.length; d++) deeper[d].section = "drilldown";', ""],
    ["missing command", 'kind: lacking !== "" ? "unavailable" : entry.kind,', "kind: entry.kind,"],
    ["hidden empty menu", "if (child.parent === target && isVisible(items, itemOrder, child, guard + 1)) return true;", "return true;"],
    ["depth limit", "while (current && current.parent && current.parent !== \"root\" && depth < DEPTH_LIMIT)", "while (current && current.parent && current.parent !== \"root\" && depth < 1000)"],
    ["payload unknown key", "if (PAYLOAD_KEYS.indexOf(keys[i]) === -1) return", "if (false) return"],
    ["payload inside runtime", "if (!insideDirectory(file, runtimeDir))", "if (false)"],
    ["payload no climbing", 'if (parts[i] === "" || parts[i] === "." || parts[i] === "..") return false;', ""],
    ["payload distinct files", "if (raw.selectionFile === raw.doneFile)", "if (false)"],
    ["payload options ceiling", "if (options.length > OPTIONS_MAX)", "if (false)"],
    ["option glyph", 'var icon = parts.length > 1 ? parts.shift() : "";', 'var icon = "";'],
    ["newest first", "return b.mtime - a.mtime;", "return 0;"],
    ["malformed counted", 'if (parts.length < 3 || !/^[0-9]+$/.test(parts[0]) || path.charAt(0) !== "/") {', "if (parts.length < 3) {"],
    ["default first", "return (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0);", "return 0;"],
    ["unchanged apply succeeds", '(result.state === "applied" || result.state === "unchanged")', '(result.state === "applied")'],
    ["only success succeeds", '(result.state === "applied" || result.state === "unchanged")', '(result.state !== "failed")']
];

const source = fs.readFileSync(file, "utf8");
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "launcher-model-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const mutant = path.join(temp, "MenuModel.js");
        fs.writeFileSync(mutant, source.replace(needle, () => replacement));
        let failed = false;
        try {
            verify(load(mutant));
        } catch (e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the suite passed on a model without that rule`);
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
console.log(`test-launcher-model: ok menus=${MENU_REFUSED.length} payloads=${PAYLOAD_REFUSED.length} controls=${CONTROLS.length}`);
