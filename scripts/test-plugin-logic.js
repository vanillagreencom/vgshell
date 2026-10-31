#!/usr/bin/env node
// Table-driven checks for shell/Core/PluginLogic.js and the configuration
// judge it imports, shell/Core/ConfigLogic.js, loaded under node through
// bin/lib/qml-library.js. The controls at the end edit a copy of either
// judge, one rule at a time, and the suite must fail on every copy. Exit 1 when any
// row or control fails.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const vm = require("vm");
const { load } = require("../bin/lib/qml-library.js");

const LOGIC = path.join(__dirname, "..", "shell", "Core", "PluginLogic.js");
const CONFIG = path.join(__dirname, "..", "shell", "Core", "ConfigLogic.js");
const LUCIDE = path.join(__dirname, "..", "shell", "Ui", "icons", "Lucide.js");
const MANAGERS = path.join(__dirname, "..", "shell", "Core", "PackageManagers.js");
const LAYER = path.join(__dirname, "..", "shell", "Core", "HyprlandLayer.js");
const PADS = path.join(__dirname, "..", "shell", "Core", "Pads.js");
const SETTING_VALUES = path.join(__dirname, "..", "shell", "Commons", "SettingValues.js");
const PAGE_REFERENCE = path.join(__dirname, "..", "shell", "Commons", "PageReference.js");
// The core's own requirements, judged by the function a manifest's are.
const CORE_REQUIREMENTS = path.join(__dirname, "..", "config", "requirements.json");
// The bundled plugins, whose manifests' formerIds build the rename map the
// shell reads.
const PLUGINS_DIR = path.join(__dirname, "..", "shell", "plugins");
// The sounds the core ships, which PluginLogic.SOUNDS names.
const SOUND_DIR = path.join(__dirname, "..", "shell", "assets", "sounds");
// The capability providers, whose providersFor the suite runs over the judge.
const CAPABILITIES_SOURCE = fs.readFileSync(path.join(__dirname, "..", "shell", "Core", "Capabilities.qml"), "utf8");
const PROVIDERS_LOOP = "for (const name of Logic.instanceCapabilities(ctx.manifest, ctx.kind)) {";

// What Capabilities.providersFor, cut from SOURCE and run over the judge
// LOGIC, holds and hands an instance of KIND of MANIFEST: { held,
// providers }, each a list of capability names.
function providersHeld(source, logic, manifest, kind) {
    const match = source.match(/\n    function providersFor\(ctx\) \{([\s\S]*?)\n    \}\n/);
    if (match === null) return "providersFor-not-found";
    const held = [];
    const providersFor = vm.runInNewContext("(function (ctx) {" + match[1] + "\n})", {
        Logic: logic, factories: { hyprland: () => ({}), notify: () => ({}) },
        acquire: name => held.push(name), root: { release: () => {} }
    });
    const providers = providersFor({ id: manifest.id, manifest: manifest, kind: kind, onDispose: () => {} });
    return { held: held, providers: Object.keys(providers) };
}

const consentViews = load(LOGIC);
const asking = { phase: "asking", queued: "", failure: "" };
const questionLink = consentViews.consentSlotView(asking, "seen", {}, []).link;
const welcomeLink = consentViews.consentSlotView(asking, "unseen", {}, []).link;
require("node:assert/strict").deepEqual(JSON.parse(JSON.stringify(questionLink)), { text: welcomeLink.text, path: "hypr/hyprland.lua" }, "the question opens the same configuration file as the welcome");

let failures = 0;
function report(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { console.log("  ok    " + name); return; }
    failures += 1;
    console.log("  FAIL  " + name + "\n        got  " + g + "\n        want " + w);
}

// Manifest writers and status publishers share the info contract.
function infoLines(ctx, check) {
    for (const [name, info, accepted] of [
        ["two lines", "One point.\nAnother point.", true],
        ["references on both lines", "Open [Appearance](page:vgs.appearance).\nOpen [Themes](page:vgs.themes).", true],
        ["empty line", "One.\n\nTwo.", false],
        ["leading line feed", "\nOne.", false],
        ["trailing line feed", "One.\n", false],
        ["carriage return", "One.\rTwo.", false],
        ["tab", "One.\tTwo.", false],
        ["line feed counts toward limit", "x".repeat(199) + "\n" + "y".repeat(200), true],
        ["total limit", "x".repeat(200) + "\n" + "y".repeat(200), false],
        ["control in reference target", "Open [Appearance](page:vgs.\tappearance).\nTwo.", false],
    ]) {
        check("info lines: schema: " + name, ctx.schemaError({ a: { type: "boolean", label: "A", info } }, { a: true }, {}) === "", accepted);
        check("info lines: status declaration: " + name, ctx.statusError({ a: { type: "text", label: "A", info } }, ["status"], {}, {}) === "", accepted);
        check("info lines: published state: " + name, ctx.statusValueFits("state", { tone: "ok", text: "Ready", info }), accepted);
        check("info lines: published key list: " + name, ctx.statusListItemFits({ label: "Key", value: "present", info }), accepted);
    }
}

// The new requirement uses the existing normalized identity and notice
// contract. File discovery belongs to scripts/test-vgshell-scan.py.
function nmVpnRequirements(ctx, check) {
    const service = "org.freedesktop.NetworkManager.openvpn";
    const vpn = { service, label: "OpenVPN plugin" };
    const raw = { schemaVersion: 1, id: "acme.vpn", name: "VPN", version: "1", author: "A", description: "VPN",
        kinds: ["service"], entryPoints: { service: "Service.qml" } };
    for (const [name, requirement, accepted] of [
        ["service", { nmVpn: vpn }, true],
        ["not an object", { nmVpn: service }, false],
        ["unknown member", { nmVpn: { ...vpn, path: "/usr/lib/NetworkManager/VPN" } }, false],
        ["missing service", { nmVpn: { label: vpn.label } }, false],
        ["another namespace", { nmVpn: { ...vpn, service: "org.example.openvpn" } }, false],
        ["invalid service", { nmVpn: { ...vpn, service: "org.freedesktop.NetworkManager.1bad" } }, false],
        ["missing label", { nmVpn: { service } }, false],
        ["long label", { nmVpn: { ...vpn, label: "x".repeat(41) } }, false],
        ["control in label", { nmVpn: { ...vpn, label: "OpenVPN\nplugin" } }, false],
        ["command too", { nmVpn: vpn, command: "openvpn" }, false],
        ["dbus too", { nmVpn: vpn, dbus: { bus: "system", name: service, label: vpn.label } }, false],
        ["floor", { nmVpn: vpn, floor: "1.0.0" }, false]
    ]) {
        const result = ctx.validateManifest({ ...raw, requirements: [{ ...requirement, purpose: "Connects VPN profiles" }] }, "/p");
        check("nmVpn: " + name, result.ok, accepted);
    }
    const result = ctx.validateManifest({ ...raw, requirements: [{ nmVpn: vpn, purpose: "Connects VPN profiles", optional: true, packages: { pacman: "networkmanager-openvpn" } }] }, "/p");
    check("nmVpn: normalized manifest", result.ok, true);
    if (!result.ok) return;
    check("nmVpn: shared identity", result.manifest.requirements, [{ name: service, title: vpn.label, bus: null,
        packages: { pacman: "networkmanager-openvpn" }, optional: true, purpose: "Connects VPN profiles", floor: null, onRequest: false }]);
    for (const [missing, state] of [[[], "present"], [[service], "missing"]]) {
        check("nmVpn: scan reads " + state, ctx.requirementRows(result.manifest, missing, {}).map(row => [row.name, row.state]), [[service, state]]);
    }
    check("nmVpn: shared install notice", ctx.noticeView(result.manifest, [service], {}, { commands: [service], required: [] },
        { primary: { id: "pacman", binary: "pacman" }, overlays: [], sources: [] }).rows.map(row => [row.name, row.package]), [[service, { manager: "pacman", name: "networkmanager-openvpn" }]]);
    check("nmVpn: duplicate across forms", ctx.validateManifest({ ...raw, requirements: [
        { nmVpn: vpn, purpose: "Connects VPN profiles" }, { dbus: { bus: "system", name: service, label: vpn.label }, purpose: "Connects VPN profiles" }
    ] }, "/p").ok, false);
}

// Every row against one loaded judge, `ctx`, and the configuration judge it
// imports, `configLogic`, each result handed to `check`.
function unplacedMounts(ctx, check) {
    const raw = { schemaVersion: 1, id: "acme.record", name: "Record", version: "1", author: "a", description: "d", kinds: ["service", "bar-widget"], entryPoints: { service: "S.qml", "bar-widget": "W.qml" }, unplacedSection: "center" };
    const judged = ctx.validateManifest(raw, "/p");
    check("unplaced mounts: manifest admitted", judged.ok, true);
    if (!judged.ok) return;
    const manifests = { "acme.record": judged.manifest };
    const configured = section => ({ plugins: [{ id: "acme.record" }], bar: { layout: { left: [], center: [{ id: "other.clock" }], right: [], [section]: [{ id: "acme.record" }] } } });
    const absent = { plugins: [{ id: "acme.record" }], bar: { layout: { left: [], center: [], right: [] } } };
    for (const [name, config, want] of [
        ["enabled unplaced widget is temporary", absent, { left: [], center: [{ id: "acme.record", transient: true }], right: [] }],
        ["disabled widget is absent", Object.assign({}, absent, { disabledPlugins: ["acme.record"] }), { left: [], center: [], right: [] }],
        ["unlisted third-party widget is absent", { bar: absent.bar }, { left: [], center: [], right: [] }],
        ...["left", "center", "right"].map(section => ["saved " + section + " suppresses temporary mount", configured(section), { left: [], center: [], right: [], [section]: [{ id: "acme.record" }] }])
    ]) check("unplaced mounts: " + name, ctx.effectiveLayout(config, manifests, "bar"), want);
    const withNeighbor = Object.assign({}, manifests, { "other.clock": { id: "other.clock", kinds: ["bar-widget"] } });
    const neighbor = { plugins: absent.plugins, bar: { layout: { center: [{ id: "other.clock" }] } } };
    check("unplaced mounts: prepended before saved widgets", ctx.effectiveLayout(neighbor, withNeighbor, "bar").center, [{ id: "acme.record", transient: true }, { id: "other.clock" }]);
    const before = JSON.stringify(neighbor);
    ctx.effectiveLayout(neighbor, withNeighbor, "bar").center[0].id = "changed";
    check("unplaced mounts: saved configuration untouched", JSON.stringify(neighbor), before);
}

function suite(ctx, configLogic, check) {
    unplacedMounts(ctx, check);
    nmVpnRequirements(ctx, check);
    infoLines(ctx, check);
    // Published state and key-list hints use the same visible words as their
    // declarations; the encoded target does not draw in either view.
    for (const [name, text, max, accepted] of [
        ["long target", "Open [notes](file:%2F" + "folder%20".repeat(80) + "notes.md)", 200, true],
        ["long hint words", "[" + "x".repeat(201) + "](file:a.md)", 200, false],
        ["long info words", "[" + "x".repeat(401) + "](file:a.md)", 400, false],
        ["whole reference bound", "[notes](file:" + "a".repeat(65536) + ")", 400, false]
    ]) {
        const field = max === 200 ? "hint" : "info";
        const state = { tone: "ok", text: "Ready", [field]: text };
        const item = { label: "Key", value: "present", [field]: text };
        check("status reference state: " + name, ctx.statusValueFits("state", state), accepted);
        check("status reference key list: " + name, ctx.statusListItemFits(item), accepted);
    }
    // Where each status entry draws (pagePlacementError): [name, status,
    // whether the plugin declares secrets, accepted]. Settings takes only
    // a stored key list; every other entry, its action with it, is a
    // Details fact.
    const modeSchema = { mode: { type: "boolean", label: "Mode" } };
    const requiredStatus = { ready: { type: "state", label: "Ready", setup: true } };
    const pagePlacementRows = [
        ["required state", requiredStatus, false, true],
        ["a stored key list beside its field", { keys: { type: "presenceList", label: "Keys", setting: "mode" } }, true, true],
        ["a state beside a field", { optional: { type: "state", label: "Optional", setting: "mode", action: { label: "Fix", tui: "fix" } } }, true, false],
        ["a key list of a plugin that stores no key beside a field", { keys: { type: "presenceList", label: "Keys", setting: "mode" } }, false, false],
        ["a stored key list beside no field", { keys: { type: "presenceList", label: "Keys", setting: "missing" } }, true, false],
        ["a hidden stored key list beside a field", { keys: { type: "presenceList", label: "Keys", hidden: true, setting: "mode" } }, true, false],
        ["required setup flag type", { ready: { type: "state", label: "Ready", setup: "yes" } }, false, false],
        ["hidden required step", { ready: { type: "state", label: "Ready", hidden: true, setup: true } }, false, false],
        ["required step value type", { ready: { type: "count", label: "Ready", setup: true } }, false, false],
        ["optional state step", { extra: { type: "state", label: "Extra", setup: "optional", action: { label: "Fix", tui: "fix" } } }, false, true],
        ["optional presence step", { extra: { type: "presence", label: "Extra", setup: "optional" } }, false, true],
        ["optional setup flag spelt in another case", { extra: { type: "state", label: "Extra", setup: "Optional" } }, false, false],
        ["hidden optional step", { extra: { type: "state", label: "Extra", hidden: true, setup: "optional" } }, false, false],
        ["optional step value type", { extra: { type: "count", label: "Extra", setup: "optional" } }, false, false],
        ["key list beside an optional step", { extra: { type: "state", label: "Extra", setup: "optional" }, keys: { type: "presenceList", label: "Keys", step: "extra" } }, true, false],
        ["a setup word other than optional", { extra: { type: "state", label: "Extra", setup: "required" } }, false, false],
        ["connection keys", { ...requiredStatus, keys: { type: "presenceList", label: "Keys", step: "ready" } }, true, true],
        ["key step reference", { keys: { type: "presenceList", label: "Keys", step: "missing" } }, true, false],
        ["key step refers to required work", { ready: { type: "state", label: "Ready" }, keys: { type: "presenceList", label: "Keys", step: "ready" } }, true, false],
        ["key association value type", { ...requiredStatus, keys: { type: "text", label: "Keys", step: "ready" } }, true, false],
        ["one status place", { ...requiredStatus, keys: { type: "presenceList", label: "Keys", step: "ready", setting: "mode" } }, true, false],
        ["connection keys with a hint Setup never draws", { ...requiredStatus, keys: { type: "presenceList", label: "Keys", step: "ready", hint: "Paste both keys" } }, true, false],
        ["connection keys with an info Setup never draws", { ...requiredStatus, keys: { type: "presenceList", label: "Keys", step: "ready", info: "Both keys come from Google Cloud." } }, true, false],
        ["hidden plugin-owned action needs no manager row", { optional: { type: "state", label: "Optional", hidden: true, action: { label: "Fix", tui: "fix" } } }, false, true],
        ["an optional feature's action beside its fact on Details", { optional: { type: "state", label: "Optional", action: { label: "Fix", tui: "fix" } } }, false, true]
    ];
    for (const [name, status, secrets, accepted] of pagePlacementRows)
        check("pagePlacement: " + name, ctx.pagePlacementError(status, modeSchema, secrets) === "", accepted);
    // Every non-value Settings placement key a manifest may carry is
    // refused at its path, naming the key: [name, a change to a plain
    // service with a `mode` switch, a `fix` screen and a stored `keys`
    // list, the refusal's start, "" for none].
    const fix = { script: "tui/fix.sh", title: "Fix" };
    const placementBase = () => ({ schemaVersion: 1, id: "acme.placed", name: "Placed", version: "1", author: "A", description: "A", kinds: ["service"], entryPoints: { service: "Service.qml" },
        capabilities: ["secrets", "status", "tui"], secrets: { service: "acme-placed", label: "Acme key" },
        schema: { mode: { type: "boolean", label: "Mode" } }, settings: { mode: false },
        tui: { fix: Object.assign({ entry: { label: "Fix", icon: "wrench", group: "Acme" } }, fix) },
        status: { keys: { type: "presenceList", label: "Keys", setting: "mode" }, health: { type: "state", label: "Health", action: { label: "Fix", tui: "fix" } } },
        requirements: [{ command: "acme-tool", purpose: "Feature", optional: true }] });
    for (const [name, plant, refusal] of [
        ["the stored key list beside its field and the action on Details", m => m, ""],
        ["a status entry beside a field", m => { m.status.health.setting = "mode"; }, "status.health.setting needs a stored key list"],
        ["a schema field of type action", m => { m.schema.feature = { type: "action", label: "Feature" }; }, "schema.feature.type must be one of string, number, boolean, enum, list, got \"action\""],
        ["a requirement beside a field", m => { m.requirements[0].setting = "mode"; }, "requirements.0 has unknown key \"setting\""],
        ["a listed screen beside a field", m => { m.tui.fix.entry.setting = "mode"; }, "tui.fix.entry has unknown key \"setting\""],
        ["a field's hint read from a status entry", m => { m.schema.mode.hintFrom = "health"; }, "schema.mode has unknown key \"hintFrom\""]
    ]) {
        const raw = placementBase();
        plant(raw);
        const judged = ctx.validateManifest(raw, "/p");
        check("placement: " + name, judged.ok ? "" : judged.error.slice(0, refusal.length || judged.error.length), refusal);
    }
    // The rows a Settings page draws (fieldRows) and the judge of them
    // (pageRowsError). Each row: [name, the manifest's keys over a plain
    // service with a `mode` switch and a stored key list beside it, the
    // refusal's path and rule, "" for none].
    const rowsBase = { schemaVersion: 1, id: "acme.rows", name: "Rows", version: "1", author: "A", description: "A", kinds: ["service"], entryPoints: { service: "Service.qml" }, capabilities: ["secrets", "status", "tui"],
        secrets: { service: "acme-rows", label: "Acme key" },
        schema: { mode: { type: "boolean", label: "Mode", group: "Main" } }, settings: { mode: false },
        tui: { fix: fix }, status: { keys: { type: "presenceList", label: "Keys", setting: "mode" } } };
    const withPageRows = keys => Object.assign({}, rowsBase, keys, { schema: Object.assign({}, rowsBase.schema, keys.schema || {}),
        tui: Object.assign({}, rowsBase.tui, keys.tui || {}), status: Object.assign({}, rowsBase.status, keys.status || {}), settings: Object.assign({}, rowsBase.settings, keys.settings || {}) });
    for (const [name, keys, refusal] of [
        ["one label for two fields of one section", { schema: { again: { type: "boolean", label: "mode", group: "Main" } }, settings: { again: false } }, "schema.again page-row=duplicate-label"],
        ["one label in two sections", { schema: { again: { type: "boolean", label: "Mode", group: "Other" } }, settings: { again: false } }, ""],
        ["a key list labelled like its field", { status: { keys: { type: "presenceList", label: "Mode", setting: "mode" } } }, "status.keys page-row=duplicate-label"],
        ["a field labelled like a key list of its section", { schema: { again: { type: "boolean", label: "Again", group: "Main" } }, settings: { again: false }, status: { keys: { type: "presenceList", label: "again", setting: "mode" } } }, "schema.again page-row=duplicate-label"],
        ["a field labelled as the page labels its own row", { schema: { again: { type: "boolean", label: "More settings" } }, settings: { again: false } }, "schema.again page-row=page-label"],
        ["one configuration screen", { tui: { configure: Object.assign({ entry: { label: "Configure", icon: "wrench", group: "Acme", settings: true } }, fix) } }, ""],
        ["two configuration screens, each a More settings row", { tui: { configure: Object.assign({ entry: { label: "Configure", icon: "wrench", group: "Acme", settings: true } }, fix), tune: Object.assign({ entry: { label: "Tune", icon: "wrench", group: "Acme", settings: true } }, fix) } }, "tui.tune.entry page-row=duplicate-label"],
        ["a configuration screen a status entry opens beside another", { tui: { configure: Object.assign({ entry: { label: "Configure", icon: "wrench", group: "Acme", settings: true } }, fix), tune: Object.assign({ entry: { label: "Tune", icon: "wrench", group: "Acme", settings: true } }, fix) },
            status: { fixing: { type: "state", label: "Fixing", action: { label: "Tune", tui: "tune" } } } }, ""],
        ["each page label the page draws itself", { schema: { again: { type: "boolean", label: "Show on the bar", group: "Other" } }, settings: { again: false } }, "schema.again page-row=page-label"]
    ]) {
        const judged = ctx.validateManifest(withPageRows(keys), "/p");
        check("pageRows: " + name, judged.ok ? "" : refusal === "" ? judged.error : judged.error.slice(0, refusal.length), refusal);
    }
    const drawn = ctx.validateManifest(withPageRows({
        schema: { other: { type: "boolean", label: "Other" } }, settings: { other: true },
        status: { fact: { type: "state", label: "Fact", action: { label: "Fix", tui: "fix" } }, gone: { type: "data", label: "Data" } }
    }), "/p");
    check("fieldRows: each field's stored key lists, in schema order", drawn.ok ? drawn.manifest.fieldRows : drawn.error, [
        { key: "mode", section: "Main", list: false, keyLists: ["keys"], groups: [] },
        { key: "other", section: "", list: false, keyLists: [], groups: [] }]);
    // The defects first-party manifests held before their rows were judged,
    // planted again in the shipped manifest: each is refused at its path by
    // its rule.
    const firstParty = id => JSON.parse(fs.readFileSync(path.join(__dirname, "../shell/plugins/" + id + "/manifest.json"), "utf8"));
    for (const [name, id, plant, refusal] of [
        ["AI Usage with its gateway key list twice beside its field", "vgs.ai-usage", m => { m.status.gatewayKeyAgain = Object.assign({}, m.status.gatewayKey); }, "status.gatewayKeyAgain page-row=duplicate-label"],
        ["Jarvis with its provider key line beside the AI model field", "vgs.jarvis", m => { m.status.keys.setting = "brain"; }, "status.keys.setting needs a stored key list"],
        ["Printers with its helper listed by its bus name", "vgs.printers", m => { delete m.requirements.find(r => r.dbus !== undefined).dbus.label; }, "requirements.4.dbus.label must"],
        ["Voice with its speech model a Settings action field again", "vgs.voice", m => { m.schema.speechModel = { type: "action", label: "Speech model", description: "Choose the model that hears your dictation" }; }, "schema.speechModel.type must be one of"]
    ]) {
        const raw = firstParty(id);
        check("pageRows: shipped " + id + " is judged ok", ctx.validateManifest(raw, "/p").ok, true);
        plant(raw);
        const judged = ctx.validateManifest(raw, "/p");
        check("pageRows: " + name, judged.ok ? "" : refusal === "" ? judged.error : judged.error.slice(0, refusal.length), refusal);
    }
    // The pages whose optional actions left Settings for Details: each
    // shipped manifest is judged as it stands.
    for (const id of ["vgs.ai-usage", "vgs.automations", "vgs.bar", "vgs.capture", "vgs.displays", "vgs.greeter", "vgs.notifications", "vgs.printers",
        "vgs.scratchpads", "vgs.sysmon", "vgs.themes", "vgs.traffic", "vgs.updates", "vgs.voice", "vgs.vpn"]) {
        const judged = ctx.validateManifest(firstParty(id), "/p");
        check("bundled manifest: shipped " + id + " is judged ok", judged.ok ? "" : judged.error, "");
    }
    const dictationRaw = { schemaVersion: 1, id: "acme.dictation", name: "D", version: "1", author: "a", description: "d", kinds: ["service"], entryPoints: { service: "Service.qml" }, capabilities: ["dictation", "status"], status: { setup: { type: "presence", label: "Setup", setup: true, action: { label: "Set up", dictation: "setup" } } } };
    for (const [capability, value, accepted] of [[true, "setup", true], [false, "setup", false], [true, "restart", false], [true, null, false], [true, 1, false]]) {
        const raw = JSON.parse(JSON.stringify(dictationRaw));
        raw.capabilities = capability ? ["dictation", "status"] : ["status"];
        raw.status.setup.action.dictation = value;
        check("dictation action: capability=" + capability + " value=" + value, ctx.validateManifest(raw, "/p").ok, accepted);
    }
    const dictationManifest = ctx.validateManifest(dictationRaw, "/p").manifest;
    check("dictation setup opens the core TUI", ctx.statusActionRequest(dictationManifest, "acme.dictation", true, { setup: "absent" }, "setup"), { ok: true, kind: "core", name: "dictation-setup" });
    // A `rows` entry: the fixture acme.rows as it ships, then its manifest
    // with one defect planted, each refused at its path by its rule.
    const rowsRaw = () => JSON.parse(fs.readFileSync(path.join(__dirname, "smoke/fixtures/plugins/acme.rows/manifest.json"), "utf8"));
    for (const [name, plant, refusal] of [
        ["the fixture's Settings list of rows with Add and Remove", m => m, ""],
        ["a row action that names no declared TUI", m => { m.status.pairs.rowActions.remove.tui = "gone"; }, "status.pairs.rowActions.remove.tui must name a script of the manifest's tui key"],
        ["a row action that opens a system step", m => { m.capabilities.push("system"); m.systemSteps = ["i2c-dev"]; m.status.pairs.rowActions.remove = { label: "Remove", system: "i2c-dev" }; }, "status.pairs.rowActions.remove must name a tui"],
        ["a row action that opens a listed screen", m => { m.tui.remove.entry = { label: "Remove a pair", icon: "trash", group: "Rows" }; }, "status.pairs.rowActions.remove.tui must name a script with no entry"],
        ["row actions that are none", m => { m.status.pairs.rowActions = {}; }, "status.pairs.rowActions must be an object of one or more actions"],
        ["a row action named as no status key is", m => { m.status.pairs.rowActions = { "Remove-it": { label: "Remove", tui: "remove" } }; }, "status.pairs.rowActions key \"Remove-it\" must match"],
        ["row actions on a state", m => { m.status.state = { type: "state", label: "State", rowActions: { remove: { label: "Remove", tui: "remove" } } }; }, "status.state.rowActions needs type rows"],
        ["a row mark on a state", m => { m.status.state = { type: "state", label: "State", icon: "folder" }; }, "status.state.icon needs type rows"],
        ["a row mark the shipped set lacks", m => { m.status.pairs.icon = "no-such-mark"; }, "status.pairs.icon must name an icon of the shipped set"],
        ["a rows entry in a group", m => { m.status.pairs.group = "Sync"; }, "status.pairs.group cannot be on a rows entry"],
        ["a rows entry on Settings the user cannot change", m => { delete m.status.pairs.action; delete m.status.pairs.rowActions; }, "status.pairs.settings needs a rows entry the user changes"],
        ["a state on Settings", m => { m.status.state = { type: "state", label: "State", settings: true, action: { label: "Fix", tui: "add" } }; }, "status.state.settings needs a rows entry the user changes"],
        ["a Settings placement that is no boolean", m => { m.status.pairs.settings = "yes"; }, "status.pairs.settings must be a boolean"],
        ["a hidden rows entry on Settings", m => { m.status.pairs.hidden = true; }, "status.pairs.settings needs a displayed status"],
        ["a rows entry of facts on Details", m => { delete m.status.pairs.settings; delete m.status.pairs.action; delete m.status.pairs.rowActions; }, ""]
    ]) {
        const raw = rowsRaw();
        plant(raw);
        const judged = ctx.validateManifest(raw, "/p");
        check("rows: " + name, judged.ok ? "" : judged.error.slice(0, refusal.length || judged.error.length), refusal);
    }
    // A stored key list's `sourceAction`, on a generic plugin: its key list
    // beside its field offers the script that makes a key, then the same
    // manifest with one defect planted, each refused at its path by its
    // rule. No plugin id or product name reaches the judge.
    const keysRaw = () => ({ schemaVersion: 1, id: "acme.keys", name: "Keys", version: "1", author: "a", description: "d", kinds: ["service"], entryPoints: { service: "Service.qml" },
        capabilities: ["status", "secrets", "tui"], secrets: { service: "acme-keys", label: "Acme key" },
        tui: { make: { script: "tui/make.sh", title: "Make a key" }, listed: { script: "tui/listed.sh", title: "Listed", entry: { label: "Open listed", icon: "wrench", group: "Tools" } } },
        settings: { sync: false }, schema: { sync: { type: "boolean", label: "Sync" } },
        status: { connection: { type: "state", label: "Connection", setup: true },
            keys: { type: "presenceList", label: "Accounts", hint: "No account is listed yet", setting: "sync", sourceAction: { label: "Make key", tui: "make" } } } });
    const stepKeys = m => { delete m.status.keys.setting; delete m.status.keys.hint; m.status.keys.step = "connection"; };
    for (const [name, plant, refusal] of [
        ["a key list beside its field offers its source", m => m, ""],
        ["a key list under its step offers its source", stepKeys, ""],
        ["a source on a state", m => { m.status.connection.sourceAction = { label: "Make key", tui: "make" }; }, "status.connection.sourceAction needs type presenceList"],
        ["a source that is no object", m => { m.status.keys.sourceAction = "make"; }, "status.keys.sourceAction must be an object"],
        ["a source with arguments of its own", m => { m.status.keys.sourceAction.args = ["--all"]; }, "status.keys.sourceAction has unknown key \"args\""],
        ["a source that is a command", m => { m.status.keys.sourceAction = { label: "Make key", command: "make-key" }; }, "status.keys.sourceAction has unknown key \"command\""],
        ["a source that opens a system step", m => { m.status.keys.sourceAction = { label: "Make key", system: "i2c-dev" }; }, "status.keys.sourceAction has unknown key \"system\""],
        ["a source with no label", m => { delete m.status.keys.sourceAction.label; }, "status.keys.sourceAction.label must be a printable line"],
        ["a source with a two-line label", m => { m.status.keys.sourceAction.label = "Make\nkey"; }, "status.keys.sourceAction.label must be a printable line"],
        ["a source with no script", m => { delete m.status.keys.sourceAction.tui; }, "status.keys.sourceAction.tui must name a script"],
        ["a source naming an undeclared script", m => { m.status.keys.sourceAction.tui = "gone"; }, "status.keys.sourceAction.tui must name a script"],
        ["a source naming a listed screen", m => { m.status.keys.sourceAction.tui = "listed"; }, "status.keys.sourceAction.tui must name a script with no entry"],
        ["a source on a key list no field or step holds", m => { delete m.status.keys.setting; }, "status.keys.sourceAction needs a displayed stored key list"],
        ["a source on a hidden key list under its step", m => { stepKeys(m); m.status.keys.hidden = true; }, "status.keys.sourceAction needs a displayed stored key list"],
        ["a source on a list of a plugin that stores no key", m => { stepKeys(m); delete m.secrets; m.capabilities = ["status", "tui"]; }, "status.keys.sourceAction needs a displayed stored key list"]
    ]) {
        const raw = keysRaw();
        plant(raw);
        const judged = ctx.validateManifest(raw, "/p");
        check("sourceAction: " + name, judged.ok ? "" : judged.error.slice(0, refusal.length || judged.error.length), refusal);
    }
    const keysManifest = ctx.validateManifest(keysRaw(), "/p").manifest;
    const keysRow = ctx.statusRows(keysManifest, {}).find(row => row.key === "keys");
    check("sourceAction: a key list's row carries its source", ([keysRow.sourceAction, keysRow.declaredTuis]), [{ label: "Make key", tui: "make" }, ["make"]]);
    check("sourceAction: a row without one carries none", ctx.statusRows(keysManifest, {}).find(row => row.key === "connection").sourceAction, null);
    // The manager's act on one key's source: [name, enabled, values,
    // account, row action, want]. The script's two arguments are the
    // account and the label of the item published for it now.
    const keyItems = [{ label: "Acme Corp (acme)", value: "absent", secret: "acme:T1" }, { label: "Globex", value: "unavailable", secret: "acme:T2" }, { label: "Shared", value: "present" }];
    const sourceTui = args => ({ ok: true, kind: "tui", name: "make", args: args });
    const sourceRefused = reason => ({ ok: false, answer: "refused: action=keys reason=" + reason });
    for (const [name, enabled, values, account, rowAction, want] of [
        ["an absent key's source opens with its account and label", true, { keys: keyItems }, "acme:T1", "source", sourceTui(["acme:T1", "Acme Corp (acme)"])],
        ["a key the store cannot ask still offers its source", true, { keys: keyItems }, "acme:T2", "source", sourceTui(["acme:T2", "Globex"])],
        ["the label is the one published at the press", true, { keys: [Object.assign({}, keyItems[0], { label: "Acme Renamed" })] }, "acme:T1", "source", sourceTui(["acme:T1", "Acme Renamed"])],
        ["a plugin that is off opens no source", false, { keys: keyItems }, "acme:T1", "source", sourceRefused("disabled")],
        ["an account no item lists opens nothing", true, { keys: keyItems }, "acme:T9", "source", sourceRefused("row-changed")],
        ["a label is no account", true, { keys: keyItems }, "Shared", "source", sourceRefused("row-changed")],
        ["an account that left the list opens nothing", true, { keys: [keyItems[1]] }, "acme:T1", "source", sourceRefused("row-changed")],
        ["an unreported list opens nothing", true, {}, "acme:T1", "source", sourceRefused("row-changed")],
        ["another row action on a key list is undeclared", true, { keys: keyItems }, "acme:T1", "remove", sourceRefused("undeclared")],
        ["a key list's act with no account is undeclared", true, { keys: keyItems }, undefined, undefined, sourceRefused("undeclared")]
    ]) check("sourceAction: " + name, ctx.statusActionRequest(keysManifest, "acme.keys", enabled, values, "keys", account, rowAction), want);
    const sourceless = keysRaw();
    delete sourceless.status.keys.sourceAction;
    check("sourceAction: a key list that declares none opens nothing", ctx.statusActionRequest(ctx.validateManifest(sourceless, "/p").manifest, "acme.keys", true, { keys: keyItems }, "keys", "acme:T1", "source"), sourceRefused("undeclared"));
    // Each published `rows` value the judge takes or refuses: [name, the
    // value, accepted].
    const rowsManifest = ctx.validateManifest(rowsRaw(), "/p").manifest;
    const pair = (id, extra) => Object.assign({ id: id, label: "Pair " + id, secondary: "Drive/" + id + " ⇄ ~/" + id, state: { tone: "ok", text: "Up to date" }, actions: ["remove"] }, extra);
    const noId = pair("a");
    delete noId.id;
    for (const [name, value, accepted] of [
        ["two rows", [pair("a"), pair("b", { state: { tone: "warning", text: "1 to review" } })], true],
        ["an empty list", [], true],
        ["a row with its label alone", [{ id: "a", label: "A" }], true],
        ["a row with no id", [noId], false],
        ["a row with an empty id", [pair("")], false],
        ["a row whose id holds a control character", [pair("a\nb")], false],
        ["a row whose id is longer than one TUI argument", [pair("x".repeat(257))], false],
        ["two rows of one id", [pair("a"), pair("a")], false],
        ["a row with no label", [{ id: "a" }], false],
        ["a row with an unknown key", [pair("a", { tone: "ok" })], false],
        ["a row whose state has an unknown tone", [pair("a", { state: { tone: "bad", text: "Bad" } })], false],
        ["a row whose state has no text", [pair("a", { state: { tone: "ok" } })], false],
        ["a row offering an undeclared row action", [pair("a", { actions: ["open"] })], false],
        ["a row offering its row action twice", [pair("a", { actions: ["remove", "remove"] })], false],
        ["a list longer than the status list ceiling", Array.from({ length: 65 }, (_, i) => pair("p" + i)), false]
    ])
        check("rows value: " + name, ctx.statusWrite(rowsManifest, {}, "pairs", value).ok, accepted);
    const published = ctx.statusWrite(rowsManifest, {}, "pairs", [pair("a", { state: { tone: "warning", text: "1 to review" } }), pair("b"), { id: "c", label: "C" }]).values;
    const rowsRow = ctx.statusRows(rowsManifest, published)[0];
    check("rows: the Status row carries each row, its chip and its row actions", [rowsRow.settings, rowsRow.icon, rowsRow.declaredTuis, rowsRow.action, rowsRow.value], [true, "folder-sync", ["add", "remove"],
        { label: "Add a folder pair", icon: "", tone: "", offered: true, tui: "add" }, [
            { id: "a", label: "Pair a", secondary: "Drive/a ⇄ ~/a", state: "1 to review", tone: "warning", chip: true, actions: [{ name: "remove", label: "Remove", tone: "danger", icon: "" }] },
            { id: "b", label: "Pair b", secondary: "Drive/b ⇄ ~/b", state: "Up to date", tone: "success", chip: false, actions: [{ name: "remove", label: "Remove", tone: "danger", icon: "" }] },
            { id: "c", label: "C", secondary: "", state: "", tone: "", chip: false, actions: [] }]]);
    // The act on a row: [name, enabled, values, row, row action, answer].
    for (const [name, enabled, values, row, rowAction, want] of [
        ["a row's Remove opens its TUI with the row's id", true, published, "b", "remove", { ok: true, kind: "tui", name: "remove", args: ["b"] }],
        ["the list's Add opens its TUI with no argument", true, published, undefined, undefined, { ok: true, kind: "tui", name: "add" }],
        ["a row action the entry does not declare", true, published, "b", "open", { ok: false, answer: "refused: action=pairs reason=undeclared" }],
        ["a row action with no name", true, published, "b", undefined, { ok: false, answer: "refused: action=pairs reason=undeclared" }],
        ["a row action of a disabled plugin", false, published, "b", "remove", { ok: false, answer: "refused: action=pairs reason=disabled" }],
        ["a row action on a row the list does not hold", true, published, "gone", "remove", { ok: false, answer: "refused: action=pairs reason=row-changed" }],
        ["a row action the row does not offer", true, published, "c", "remove", { ok: false, answer: "refused: action=pairs reason=row-changed" }],
        ["a row action before the list is reported", true, {}, "b", "remove", { ok: false, answer: "refused: action=pairs reason=row-changed" }]
    ])
        check("rows act: " + name, ctx.statusActionRequest(rowsManifest, "acme.rows", enabled, values, "pairs", row, rowAction), want);
    // A `plain` state and a `setupGuide`: the acme.rows fixture with a
    // Setup step and an account beside its list, then one defect planted.
    const guidedRaw = () => {
        const m = rowsRaw();
        m.status.signIn = { type: "state", label: "Sign in", setup: true, action: { label: "Sign in", tui: "add" } };
        m.status.account = { type: "state", label: "Account", plain: true, action: { label: "Sign out", tui: "remove", tone: "danger", icon: "log-out" } };
        m.setupGuide = { title: "Rows needs keys from your own account", text: "It takes about 5 minutes.", link: "Open the guide", readme: "get-your-keys" };
        return m;
    };
    for (const [name, plant, refusal] of [
        ["a plain account and a guide over a Setup step", m => m, ""],
        ["plain that is no boolean", m => { m.status.account.plain = "yes"; }, "status.account.plain must be a boolean"],
        ["a plain list of rows", m => { m.status.pairs.plain = true; }, "status.pairs.plain needs a state entry that is no Setup step"],
        ["a plain Setup step", m => { m.status.signIn.plain = true; }, "status.signIn.plain needs a state entry that is no Setup step"],
        ["a plain optional Setup step", m => { m.status.signIn.plain = true; m.status.signIn.setup = "optional"; }, "status.signIn.plain needs a state entry that is no Setup step"],
        ["a guide that is no object", m => { m.setupGuide = "read me"; }, "setupGuide must be an object"],
        ["a guide with an unknown key", m => { m.setupGuide.url = "https://example.com"; }, "setupGuide has unknown key \"url\""],
        ["a guide with no title", m => { delete m.setupGuide.title; }, "setupGuide.title must be a printable line"],
        ["a guide title past its ceiling", m => { m.setupGuide.title = "x".repeat(81); }, "setupGuide.title must be a printable line"],
        ["a guide text on two lines", m => { m.setupGuide.text = "a\nb"; }, "setupGuide.text must be a printable line"],
        ["a guide with no link words", m => { m.setupGuide.link = ""; }, "setupGuide.link must be a printable line"],
        ["a guide anchor in heading case", m => { m.setupGuide.readme = "Get your keys"; }, "setupGuide.readme must be a README heading anchor"],
        ["a guide anchor with a leading #", m => { m.setupGuide.readme = "#get-your-keys"; }, "setupGuide.readme must be a README heading anchor"],
        ["a guide anchor of doubled dashes", m => { m.setupGuide.readme = "get--keys"; }, "setupGuide.readme must be a README heading anchor"],
        ["a guide with no Setup step to head", m => { delete m.status.signIn; }, "setupGuide needs a required Setup step"],
        ["a guide over an optional step alone", m => { m.status.signIn.setup = "optional"; }, "setupGuide needs a required Setup step"],
        ["a plain optional step", m => { m.status.extra = { type: "state", label: "Extra", setup: "optional", plain: true }; }, "status.extra.plain needs a state entry that is no Setup step"]
    ]) {
        const raw = guidedRaw();
        plant(raw);
        const judged = ctx.validateManifest(raw, "/p");
        check("guided: " + name, judged.ok ? "" : judged.error.slice(0, refusal.length || judged.error.length), refusal);
    }
    const guided = ctx.validateManifest(guidedRaw(), "/p").manifest;
    // A plain state draws as text while it needs nothing, and as its chip
    // while it needs the user; a state that is not plain keeps its chip.
    const accountTone = (entry, tone) => ctx.statusRows(guided, { [entry]: { tone: tone, text: "a.person@example.com", action: true } }).find(row => row.key === entry).tone;
    check("plain: a calm state draws as text", ["ok", "info"].map(tone => accountTone("account", tone)), ["", ""]);
    check("plain: a state that needs the user keeps its chip", ["warning", "danger"].map(tone => accountTone("account", tone)), ["warning", "danger"]);
    check("plain: a state that is not plain keeps its chip", accountTone("signIn", "ok"), "success");
    // An optional step (setup "optional") beside the required one: what a
    // value may say of each, and the step each row names.
    const stepsRaw = guidedRaw();
    stepsRaw.status.extra = { type: "state", label: "Extra", setup: "optional", action: { label: "Add", tui: "add" } };
    const steps = ctx.validateManifest(stepsRaw, "/p").manifest;
    const cannot = { tone: "warning", text: "No reader", hint: "Connect a reader to set this up", available: false };
    for (const [name, key, value, accepted] of [
        ["a required step hides", "signIn", { hidden: true }, false],
        ["an optional step that cannot apply hides", "extra", { hidden: true }, true],
        ["a required step the user cannot act on", "signIn", cannot, true],
        ["an optional step the user cannot act on", "extra", cannot, true],
        ["a Details reading the user cannot act on", "account", cannot, false],
        ["an optional step offers its action", "extra", { tone: "warning", text: "Not added", action: true }, true]
    ]) check("optional step value: " + name, ctx.statusWrite(steps, {}, key, value).ok, accepted);
    check("optional step: each row names its step", ctx.statusRows(steps, {}).filter(row => ["signIn", "extra", "account"].indexOf(row.key) !== -1).map(row => [row.key, row.setup]),
        [["signIn", "required"], ["account", ""], ["extra", "optional"]]);
    // The guide a page draws: its README section's address, or no address
    // for a plugin with no README to open.
    check("setupGuideRow: the README section", ctx.setupGuideRow(guided, "https://example.com/acme.rows/README.md"),
        { title: "Rows needs keys from your own account", text: "It takes about 5 minutes.", link: "Open the guide", url: "https://example.com/acme.rows/README.md#get-your-keys" });
    check("setupGuideRow: no README to open", ctx.setupGuideRow(guided, "").url, "");
    check("setupGuideRow: no guide", ctx.setupGuideRow(rowsManifest, "https://example.com/README.md"), null);
    const bar = { schemaVersion: 1, id: "vgs.bar", name: "Bar", version: "0.1.0", author: "VGS", description: "d", kinds: ["bar"], entryPoints: { bar: "Bar.qml" } };
    const clock = { schemaVersion: 1, id: "vgs.clock", name: "Clock", version: "0.1.0", author: "VGS", description: "d", kinds: ["bar-widget"], entryPoints: { "bar-widget": "Widget.qml" }, defaultSection: "center" };
    const svc = { schemaVersion: 1, id: "acme.svc", name: "S", version: "1", author: "a", description: "d", kinds: ["service"], entryPoints: { service: "S.qml" }, settings: { x: 0 } };

    // An enum of a Local option and three Cloud ones, the Settings shape of
    // a provider choice, and a choices string with an Add entry and a
    // preview, each changed by PLANT.
    const grouped = (plant = () => {}) => {
        const entry = { type: "enum", label: "Side", groupLabel: "Cloud kind", options: [{ value: "local", label: "Local", group: "Local" },
            { value: "a", label: "A", group: "Cloud" }, { value: "b", label: "B", group: "Cloud" }, { value: "c", label: "C", group: "Cloud" }] };
        plant(entry);
        return entry;
    };
    const offering = (plant = () => {}) => {
        const patch = { capabilities: ["status", "tui"], status: { voices: { type: "choices", label: "Voices" } }, tui: { "add-voice": { script: "tui/add.sh", title: "Add a voice" } },
            settings: { voice: "" }, schema: { voice: { type: "string", label: "Voice", optionsFrom: "voices", addChoice: { label: "Add a voice", tui: "add-voice" }, preview: true } } };
        plant(patch);
        return patch;
    };
    // The groups a grouped enum's row draws, in order, and the request an
    // Add entry makes of the manager (addChoiceRequest).
    const offered = ctx.validateManifest(Object.assign({}, svc, offering(m => { m.settings.side = "local"; m.schema.side = grouped(); })), "/p");
    check("fieldRows: a grouped enum's groups, each with its values in order", offered.ok ? offered.manifest.fieldRows.map(row => [row.key, row.groups]) : offered.error,
        [["voice", []], ["side", [{ name: "Local", values: ["local"] }, { name: "Cloud", values: ["a", "b", "c"] }]]]);
    for (const [name, manifest, enabled, key, want] of [
        ["an Add entry opens its screen", offered.manifest, true, "voice", { ok: true, kind: "tui", name: "add-voice" }],
        ["an Add entry of a plugin that is off", offered.manifest, false, "voice", { ok: false, answer: "refused: tui=add-voice reason=disabled" }],
        ["a field with no Add entry", offered.manifest, true, "side", { ok: false, answer: "refused: add-choice=side reason=undeclared" }],
        ["a field the schema lacks", offered.manifest, true, "gone", { ok: false, answer: "refused: add-choice=gone reason=undeclared" }],
        ["a key that is no status key", offered.manifest, true, "a b", { ok: false, answer: "refused: add-choice=\"a b\" reason=undeclared" }],
        ["an unknown plugin", null, true, "voice", { ok: false, answer: "unknown: acme.svc" }]
    ]) check("addChoiceRequest: " + name, ctx.addChoiceRequest(manifest, "acme.svc", enabled, key), want);
    // validateManifest: one row per rule, defect planted in `patch`. A refusal
    // row pins the start of the error text, so a neighbouring rule catching the
    // same fixture does not pass for it.
    const manifestRows = [
        ["valid bar manifest", {}, null],
        ["valid cover manifest", { kinds: ["cover"], entryPoints: { cover: "Cover.qml" } }, null],
        ["valid pane manifest", { kinds: ["pane"], entryPoints: { pane: "Pane.qml" }, pane: { group: "System", order: 10 } }, null],
        ["kind pane without pane key", { kinds: ["pane"], entryPoints: { pane: "Pane.qml" } }, "kind pane needs a pane declaration"],
        ["pane key without pane kind", { pane: { group: "System", order: 10 } }, "pane needs kind pane"],
        ["pane key with unknown key", { kinds: ["pane"], entryPoints: { pane: "Pane.qml" }, pane: { group: "System", order: 10, x: 1 } }, "pane has unknown key"],
        ["pane group is one printable line", { kinds: ["pane"], entryPoints: { pane: "Pane.qml" }, pane: { group: "", order: 10 } }, "pane.group must be a printable line"],
        ["pane group is capped at 60 characters", { kinds: ["pane"], entryPoints: { pane: "Pane.qml" }, pane: { group: "x".repeat(61), order: 10 } }, "pane.group must be a printable line"],
        ["pane must be an object", { kinds: ["pane"], entryPoints: { pane: "Pane.qml" }, pane: null }, "pane must be an object"],
        ["pane order is finite", { kinds: ["pane"], entryPoints: { pane: "Pane.qml" }, pane: { group: "System", order: null } }, "pane.order must be a finite number"],
        ["session is a shared capability", { capabilities: ["session"] }, null],
        ["unknown top-level key", { keepLoaded: true }, "unknown key"],
        ["schemaVersion 2", { schemaVersion: 2 }, "schemaVersion must be 1"],
        ["id without namespace", { id: "bar" }, "id must be dotted"],
        ["id with uppercase", { id: "vgs.Bar" }, "id must be dotted"],
        ["splitFrom a dotted source", { splitFrom: "acme.source" }, null],
        ...[null, [], {}, 4, true, "", "source", "acme.source/child", "acme..source"].map(value =>
            ["splitFrom invalid " + JSON.stringify(value), { splitFrom: value }, "splitFrom must be dotted"]),
        ["splitFrom own id", { splitFrom: "vgs.bar" }, "splitFrom must differ"],
        ["splitFrom a former id", { splitFrom: "acme.source", formerIds: ["acme.source"] }, "splitFrom must differ"],
        ["formerIds naming two earlier ids", { formerIds: ["vgs.old-bar", "acme.bar"] }, null],
        ["formerIds not a list", { formerIds: "vgs.old-bar" }, "formerIds must be a non-empty list"],
        ["formerIds empty", { formerIds: [] }, "formerIds must be a non-empty list"],
        ["formerIds holding an undotted id", { formerIds: ["bar"] }, "formerIds.0 must be dotted"],
        ["formerIds holding a non-string", { formerIds: ["vgs.old-bar", 3] }, "formerIds.1 must be dotted"],
        ["formerIds holding the plugin's own id", { formerIds: ["vgs.bar"] }, "formerIds.0 is the plugin's own id"],
        ["formerIds naming one id twice", { formerIds: ["vgs.old-bar", "vgs.old-bar"] }, "formerIds lists vgs.old-bar twice"],
        ["missing description", { description: "" }, "description must be"],
        ["empty kinds", { kinds: [] }, "kinds must be a non-empty array"],
        ["unknown kind", { kinds: ["widget"] }, "unknown kind"],
        ["kind declared twice", { kinds: ["bar", "bar"] }, "kind \"bar\" is declared twice"],
        ["license empty", { license: "" }, "license must be a non-empty string"],
        ["entryPoints not an object", { entryPoints: "Bar.qml" }, "entryPoints must be an object"],
        ["entry point missing for kind", { entryPoints: {} }, "entryPoints.bar is required"],
        ["entry point for an undeclared kind", { entryPoints: { bar: "Bar.qml", service: "S.qml" } }, "entryPoints.service names a kind"],
        ["entry point escapes directory", { entryPoints: { bar: "../x.qml" } }, "entryPoints.bar must stay inside"],
        ["entry point absolute", { entryPoints: { bar: "/etc/x.qml" } }, "entryPoints.bar must stay inside"],
        ["requires is refused by name", { requires: ["vgs.bar"] }, "requires is refused: a plugin names no other plugin (D005)"],
        ["requirements declaring a command", { requirements: [{ command: "gum", packages: { pacman: "gum", aur: "gum-bin", dnf: "gum" }, optional: true, purpose: "Draws the update dialogs" }] }, null],
        ["requirements declaring a D-Bus name", { requirements: [{ dbus: { bus: "system", name: "org.freedesktop.UPower.PowerProfiles", label: "Power profiles service" }, packages: { dnf: "ppd-service" }, purpose: "Switches the power profile" }] }, null],
        ["a D-Bus requirement without the label a page lists it by", { requirements: [{ dbus: { bus: "system", name: "org.freedesktop.UPower.PowerProfiles" }, purpose: "p" }] }, "requirements.0.dbus.label must be a printable line"],
        ["a D-Bus requirement whose label runs past a short name", { requirements: [{ dbus: { bus: "system", name: "org.freedesktop.UPower.PowerProfiles", label: "x".repeat(41) }, purpose: "p" }] }, "requirements.0.dbus.label must be a printable line"],
        ["requirements with only a command and a purpose", { requirements: [{ command: "notify-send", purpose: "Sends notices" }] }, null],
        ["a requirement purpose of one sentence with a full stop is refused", { requirements: [{ command: "gum", purpose: "Draws the update dialogs." }] }, "requirements.0.purpose must end with no full stop"],
        ["a requirement purpose of two sentences, each with its full stop", { requirements: [{ command: "gum", purpose: "Draws the update dialogs. It needs a terminal." }] }, null],
        ["requirements not a list", { requirements: { command: "gum" } }, "requirements must be a list"],
        ["a requirement that is a plugin id string", { requirements: ["vgs.settings"] }, "requirements.0 must be an object"],
        ["a requirement with an unknown key", { requirements: [{ command: "gum", purpose: "p", plugin: "vgs.settings" }] }, "requirements.0 has unknown key \"plugin\""],
        ["a requirement with command and dbus", { requirements: [{ command: "gum", dbus: { bus: "system", name: "org.freedesktop.UPower.PowerProfiles" }, purpose: "p" }] }, "requirements.0 must name exactly one of command, dbus or nmVpn"],
        ["a requirement command that is a path", { requirements: [{ command: "/usr/bin/gum", purpose: "p" }] }, "requirements.0.command must be a bare command name looked up on PATH, got \"/usr/bin/gum\""],
        ["a requirement without an identity", { requirements: [{ purpose: "p" }] }, "requirements.0 must name exactly one of command, dbus or nmVpn"],
        ["a requirement command spelt as a plugin id", { requirements: [{ command: "vgs.settings", purpose: "p" }] }, "requirements.0.command \"vgs.settings\" is spelt as a plugin id: a requirement names a command or D-Bus name, never a plugin (D005)"],
        ["a requirement dbus bus outside the table", { requirements: [{ dbus: { bus: "starter", name: "org.freedesktop.UPower.PowerProfiles" }, purpose: "p" }] }, "requirements.0.dbus.bus must be one of system, session"],
        ["a requirement dbus name with one element", { requirements: [{ dbus: { bus: "system", name: "org" }, purpose: "p" }] }, "requirements.0.dbus.name must be a well-known D-Bus name"],
        ["a requirement dbus name with a leading digit element", { requirements: [{ dbus: { bus: "system", name: "org.1bad" }, purpose: "p" }] }, "requirements.0.dbus.name must be a well-known D-Bus name"],
        ["a requirement dbus name with a unique-name prefix", { requirements: [{ dbus: { bus: "system", name: ":1.5" }, purpose: "p" }] }, "requirements.0.dbus.name must be a well-known D-Bus name"],
        ["a requirement dbus with an unknown key", { requirements: [{ dbus: { bus: "system", name: "org.freedesktop.UPower.PowerProfiles", path: "/" }, purpose: "p" }] }, "requirements.0.dbus has unknown key \"path\""],
        ["a requirement command declared twice", { requirements: [{ command: "gum", purpose: "p" }, { command: "gum", purpose: "q" }] }, "requirements.1.command \"gum\" is declared twice"],
        ["a requirement name declared twice across command and dbus", { requirements: [{ command: "org.freedesktop.UPower.PowerProfiles", purpose: "p" }, { dbus: { bus: "system", name: "org.freedesktop.UPower.PowerProfiles", label: "Power profiles" }, purpose: "q" }] }, "requirements.1.dbus.name \"org.freedesktop.UPower.PowerProfiles\" is declared twice"],
        ["requirement packages not an object", { requirements: [{ command: "gum", packages: ["gum"], purpose: "p" }] }, "requirements.0.packages must be an object of manager ids to package names"],
        ["requirement packages naming an unknown manager", { requirements: [{ command: "gum", packages: { zypper: "gum" }, purpose: "p" }] }, "requirements.0.packages names the unknown manager \"zypper\""],
        ["a requirement package starting with a dash", { requirements: [{ command: "gum", packages: { pacman: "-Sy" }, purpose: "p" }] }, "requirements.0.packages.pacman must be a package name"],
        ["a requirement package with a space", { requirements: [{ command: "gum", packages: { apt: "gum fzf" }, purpose: "p" }] }, "requirements.0.packages.apt must be a package name"],
        ["requirement optional not a boolean", { requirements: [{ command: "gum", optional: "yes", purpose: "p" }] }, "requirements.0.optional must be a boolean when present"],
        ["a requirement without a purpose", { requirements: [{ command: "gum" }] }, "requirements.0.purpose must be one printable line of 1 to 120 characters"],
        ["a blank requirement purpose", { requirements: [{ command: "gum", purpose: "  " }] }, "requirements.0.purpose must be one printable line"],
        ["a requirement purpose with a newline", { requirements: [{ command: "gum", purpose: "one\ntwo" }] }, "requirements.0.purpose must be one printable line"],
        ["a requirement purpose of 121 characters", { requirements: [{ command: "gum", purpose: "p".repeat(121) }] }, "requirements.0.purpose must be one printable line"],
        ["a requirement purpose of 120 characters", { requirements: [{ command: "gum", purpose: "p".repeat(120) }] }, null],
        ["a requirement with a floor", { requirements: [{ command: "gum", floor: "0.14.5", purpose: "p" }] }, null],
        ["a floor on a D-Bus name", { requirements: [{ dbus: { bus: "system", name: "org.freedesktop.UPower.PowerProfiles", label: "Power profiles" }, floor: "1.0.0", purpose: "p" }] }, "requirements.0.floor needs a command"],
        ["a floor of two numbers", { requirements: [{ command: "gum", floor: "0.14", purpose: "p" }] }, "requirements.0.floor must be a version of three dotted numbers, got \"0.14\""],
        ["a floor with a leading zero", { requirements: [{ command: "gum", floor: "0.014.5", purpose: "p" }] }, "requirements.0.floor must be a version of three dotted numbers"],
        ["a floor that is a list of one version", { requirements: [{ command: "gum", floor: ["0.14.5"], purpose: "p" }] }, "requirements.0.floor must be a version of three dotted numbers, got [\"0.14.5\"]"],
        ["a required requirement installed on request", { requirements: [{ command: "gum", packages: { aur: "gum-bin" }, install: "on-request", purpose: "p" }] }, null],
        ["an install value other than on-request", { requirements: [{ command: "gum", packages: { aur: "gum-bin" }, install: "always", purpose: "p" }] }, "requirements.0.install must be \"on-request\" when present, got \"always\""],
        ["an optional requirement installed on request", { requirements: [{ command: "gum", packages: { aur: "gum-bin" }, optional: true, install: "on-request", purpose: "p" }] }, "requirements.0.install needs a required entry"],
        ["a requirement installed on request with no packages", { requirements: [{ command: "gum", install: "on-request", purpose: "p" }] }, "requirements.0.install needs packages"],
        ["a requirement installed on request with a floor", { requirements: [{ command: "gum", packages: { aur: "gum-bin" }, floor: "0.14.5", install: "on-request", purpose: "p" }] }, "requirements.0.install cannot stand beside a floor"],
        ["a shortcut bind without a default key", { capabilities: ["shortcut"], hyprland: { binds: [{ shortcut: "start", key: null }] } }, null],
        ["appearance naming a .js file", { appearance: "Appearance.js" }, null],
        ["appearance naming a nested .js file", { appearance: "look/Appearance.js" }, null],
        ["appearance not a string", { appearance: { tokens: {} } }, "appearance must name a .js file"],
        ["appearance naming a QML file", { appearance: "Appearance.qml" }, "appearance must name a .js file"],
        ["appearance escaping the directory", { appearance: "../Appearance.js" }, "appearance must stay inside"],
        ["appearance absolute", { appearance: "/etc/Appearance.js" }, "appearance must stay inside"],
        ["capabilities not an array", { capabilities: "compositor" }, "capabilities must be an array"],
        ["unknown capability", { capabilities: ["network"] }, "unknown capability"],
        ["settings not an object", { settings: [] }, "settings must be an object"],
        ["settings carrying an id", { settings: { id: "x" } }, "settings must not carry an id key"],
        ["settings placement outside PLACEMENTS", { settings: { placement: "middle" } }, "settings.placement must be one of"],
        ["settings placement in PLACEMENTS", { settings: { placement: "top-right" } }, null],
        ["defaultSection without the widget kind", { defaultSection: "left" }, "defaultSection needs kind bar-widget"],
        ["unplacedSection without the widget kind", { unplacedSection: "center" }, "unplacedSection needs kind bar-widget"],
        ["unplacedSection unknown", { kinds: ["bar-widget"], entryPoints: { "bar-widget": "W.qml" }, unplacedSection: "top" }, "unplacedSection must be one of"],
        ["unplacedSection not text", { kinds: ["bar-widget"], entryPoints: { "bar-widget": "W.qml" }, unplacedSection: null }, "unplacedSection must be one of"],
        ["alwaysOn on a first-party service", { id: "vgs.always", kinds: ["service"], entryPoints: { service: "S.qml" }, alwaysOn: true }, null],
        ["alwaysOn false on a third-party service", { id: "acme.always", kinds: ["service"], entryPoints: { service: "S.qml" }, alwaysOn: false }, null],
        ["alwaysOn not a boolean", { id: "vgs.always", kinds: ["service"], entryPoints: { service: "S.qml" }, alwaysOn: "yes" }, "alwaysOn must be a boolean"],
        ["alwaysOn on a third-party service", { id: "acme.always", kinds: ["service"], entryPoints: { service: "S.qml" }, alwaysOn: true }, "alwaysOn needs the first-party rule"],
        ["alwaysOn on a bar", { alwaysOn: true }, "alwaysOn needs the first-party rule"],
        ["alwaysOn on a widget-only plugin", { kinds: ["bar-widget"], entryPoints: { "bar-widget": "W.qml" }, alwaysOn: true }, "alwaysOn needs the first-party rule"],
        ["defaultSection unknown", { kinds: ["bar-widget"], entryPoints: { "bar-widget": "W.qml" }, defaultSection: "top" }, "defaultSection must be one of"],
        ["known capability", { capabilities: ["compositor"] }, null],
        ["a tap bind", { capabilities: ["shortcut"], hyprland: { binds: [{ shortcut: "tap", key: "code:108", tap: true }] } }, null],
        ["a null default key", { capabilities: ["shortcut"], hyprland: { binds: [{ shortcut: "tap", key: null, tap: true }] } }, null],
        ["a bind with an explanation", { capabilities: ["shortcut"], hyprland: { binds: [{ shortcut: "tap", key: null, info: "Tap to talk." }] } }, null],
        ["an empty bind explanation is refused", { capabilities: ["shortcut"], hyprland: { binds: [{ shortcut: "tap", key: null, info: "" }] } }, "hyprland.binds.0.info must be a non-empty string"],
        ["a non-string bind explanation is refused", { capabilities: ["shortcut"], hyprland: { binds: [{ shortcut: "tap", key: null, info: ["Tap"] }] } }, "hyprland.binds.0.info must be a non-empty string"],
        ["a non-boolean tap is refused", { capabilities: ["shortcut"], hyprland: { binds: [{ shortcut: "tap", key: "code:108", tap: "yes" }] } }, "hyprland.binds.0.tap must be a boolean"],
        ["tap and hold together are refused", { capabilities: ["shortcut"], hyprland: { binds: [{ shortcut: "tap", key: "code:108", tap: true, hold: true }] } }, "hyprland.binds.0 must not set tap and hold together"],
        ["a tap manifest key with modifiers is refused", { capabilities: ["shortcut"], hyprland: { binds: [{ shortcut: "tap", key: "SUPER+code:108", tap: true }] } }, "hyprland.binds.0.key SUPER+code:108 must be a lone key for tap"],
        ["schema not an object", { schema: [] }, "schema must be an object"],
        ["schema entry carrying the id key", { schema: { id: { type: "string", label: "x" } } }, "schema must not carry an id key"],
        ["schema entry not an object", { settings: { a: "x" }, schema: { a: "string" } }, "schema.a must be an object"],
        ["schema entry with an unknown key", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", bogus: 1 } } }, "schema.a has unknown key"],
        ["icon naming a shipped icon", { icon: "settings" }, null],
        ["icon naming no shipped icon", { icon: "not-an-icon" }, "icon must name an icon of the shipped set"],
        ["icon that is not a string", { icon: 3 }, "icon must name an icon of the shipped set"],
        ["icon naming a prototype member", { icon: "constructor" }, "icon must name an icon of the shipped set"],
        ["a bounded, grouped number entry", { settings: { a: 8 }, schema: { a: { type: "number", label: "A", min: 2, max: 30, step: 1, group: "Timing" } } }, null],
        ["a number bounded on one side", { settings: { a: 8 }, schema: { a: { type: "number", label: "A", min: 0 } } }, null],
        ["a grouped string entry", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", presets: [{ value: "x" }], group: "Look" } } }, null],
        ["a schema entry with info", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", info: "What this switch changes." } } }, null],
        ["a schema info that is not a string", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", info: 1 } } }, "schema.a.info must be printable lines"],
        ["an empty schema info", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", info: "" } } }, "schema.a.info must be printable lines"],
        ["a schema info with a control character", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", info: "A\u001bB" } } }, "schema.a.info must be printable lines"],
        ["a schema info of 401 characters", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", info: "x".repeat(401) } } }, "schema.a.info must be printable lines"],
        ["a schema info of 400 characters", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", info: "x".repeat(400) } } }, null],
        ["a label of one 17-character word fits", { settings: { a: true }, schema: { a: { type: "boolean", label: "x".repeat(17) } } }, null],
        ["a label word longer than a line is refused", { settings: { a: true }, schema: { a: { type: "boolean", label: "x".repeat(18) } } }, "schema.a.label must fit 2 lines of 17 characters"],
        ["a label of three lines is refused", { settings: { a: true }, schema: { a: { type: "boolean", label: "Trim and level finished recordings" } } }, "schema.a.label must fit 2 lines of 17 characters"],
        ["a space at a line's end takes no room", { settings: { a: true }, schema: { a: { type: "boolean", label: "Click to select a window or display" } } }, null],
        ["a label line breaks after a hyphen", { settings: { a: true }, schema: { a: { type: "boolean", label: "Review third-party packages" } } }, null],
        ["a hyphen before a digit keeps its word", { settings: { a: true }, schema: { a: { type: "boolean", label: "x".repeat(16) + "-1" } } }, "schema.a.label must fit 2 lines of 17 characters"],
        ["a label of 14 characters fits without an info mark", { settings: { a: true }, schema: { a: { type: "boolean", label: "x".repeat(14) } } }, null],
        ["a label of 13 characters fits beside an info mark", { settings: { a: true }, schema: { a: { type: "boolean", label: "x".repeat(13), info: "Why it matters." } } }, null],
        ["a label of 14 characters is refused beside an info mark", { settings: { a: true }, schema: { a: { type: "boolean", label: "x".repeat(14), info: "Why it matters." } } }, "schema.a.label must fit 2 lines of 13 characters"],
        ["a list label is its section's title and not judged", { settings: { a: [] }, schema: { a: { type: "list", label: "Trim and level finished recordings", items: { enabled: { type: "boolean", label: "Enabled" } }, defaults: { enabled: true } } } }, null],
        ["a list item label is judged", { settings: { a: [] }, schema: { a: { type: "list", label: "A", items: { enabled: { type: "boolean", label: "Trim and level finished recordings" } }, defaults: { enabled: true } } } }, "schema.a.items: schema.enabled.label must fit 2 lines of 17 characters"],
        ["a schema entry with a tooltip", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", tooltip: "What this switch changes." } } }, null],
        ["a list item field with a tooltip", { settings: { a: [] }, schema: { a: { type: "list", label: "A", items: { enabled: { type: "boolean", label: "Enabled", tooltip: "Uses this item." } }, defaults: { enabled: true } } } }, null],
        ["a tooltip belongs to a flat field", { settings: { a: [] }, schema: { a: { type: "list", label: "A", tooltip: "Lists them.", items: { enabled: { type: "boolean", label: "Enabled" } }, defaults: { enabled: true } } } }, "schema.a.tooltip needs a flat setting"],
        ["a tooltip that is not a string", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", tooltip: 1 } } }, "schema.a.tooltip must be a printable line"],
        ["an empty tooltip", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", tooltip: "" } } }, "schema.a.tooltip must be a printable line"],
        ["a tooltip with a line break", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", tooltip: "One.\nTwo." } } }, "schema.a.tooltip must be a printable line"],
        ["a tooltip of 121 characters", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", tooltip: "x".repeat(121) } } }, "schema.a.tooltip must be a printable line"],
        ["a tooltip of 120 characters", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", tooltip: "x".repeat(120) } } }, null],
        ["min on a string entry", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", presets: [{ value: "x" }], min: 1 } } }, "schema.a.min needs type number"],
        ["step on a boolean entry", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", step: 1 } } }, "schema.a.step needs type number"],
        ["max on an enum entry", { settings: { a: "x" }, schema: { a: { type: "enum", label: "A", options: [{ value: "x", label: "X" }], max: 1 } } }, "schema.a.max needs type number"],
        ["a min that is not a number", { settings: { a: 8 }, schema: { a: { type: "number", label: "A", min: "1" } } }, "schema.a.min must be a finite number"],
        ["a max that is not finite", { settings: { a: 8 }, schema: { a: { type: "number", label: "A", max: null } } }, "schema.a.max must be a finite number"],
        ["min equal to max", { settings: { a: 8 }, schema: { a: { type: "number", label: "A", min: 8, max: 8 } } }, "schema.a.min must be less than max"],
        ["min above max", { settings: { a: 8 }, schema: { a: { type: "number", label: "A", min: 30, max: 2 } } }, "schema.a.min must be less than max"],
        ["a zero step", { settings: { a: 8 }, schema: { a: { type: "number", label: "A", step: 0 } } }, "schema.a.step must be positive"],
        ["a negative step", { settings: { a: 8 }, schema: { a: { type: "number", label: "A", step: -1 } } }, "schema.a.step must be positive"],
        ["an empty group", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", presets: [{ value: "x" }], group: "" } } }, "schema.a.group must be a non-empty string"],
        ["a group that is not a string", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", presets: [{ value: "x" }], group: 2 } } }, "schema.a.group must be a non-empty string"],
        ["a default under its min", { settings: { a: 1 }, schema: { a: { type: "number", label: "A", min: 2, max: 30 } } }, "settings.a does not fit its schema: want=at-least:2"],
        ["a default over its max", { settings: { a: 31 }, schema: { a: { type: "number", label: "A", min: 2, max: 30 } } }, "settings.a does not fit its schema: want=at-most:30"],
        ["a default off its step fits", { settings: { a: 2.5 }, schema: { a: { type: "number", label: "A", min: 2, max: 30, step: 1 } } }, null],
        ["schema entry with an unknown type", { settings: { a: "x" }, schema: { a: { type: "color", label: "A" } } }, "schema.a.type must be one of"],
        ["schema entry without a label", { settings: { a: "x" }, schema: { a: { type: "string", presets: [{ value: "x" }] } } }, "schema.a.label must be a non-empty string"],
        ["schema entry with a non-string description", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", presets: [{ value: "x" }], description: 1 } } }, "schema.a.description must be a string"],
        ["a one-sentence description with a full stop is refused", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Shows the clock." } } }, "schema.a.description must end with no full stop"],
        ["a one-sentence description without a full stop", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Shows the clock" } } }, null],
        ["a two-sentence description whose last sentence lacks its full stop is refused", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Shows the clock. A press opens the calendar" } } }, "schema.a.description must end with no full stop"],
        ["a two-sentence description with both full stops", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Shows the clock. A press opens the calendar." } } }, null],
        ["a list item's description is judged", { settings: { a: [] }, schema: { a: { type: "list", label: "A", items: { enabled: { type: "boolean", label: "Enabled", description: "Uses this item." } }, defaults: { enabled: true } } } }, "schema.a.items: schema.enabled.description must end with no full stop"],
        ["a description link to an https address", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "OpenAI", url: "https://platform.openai.com/api-keys" } } } }, null],
        ["a description link to an https address with a port, query and fragment", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "OpenAI", url: "https://example.org:8443/keys?tab=new#create" } } } }, null],
        ["a description link that is not an object", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: "https://platform.openai.com/api-keys" } } }, "schema.a.link must be an object"],
        ["a description link with an unknown key", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "OpenAI", url: "https://platform.openai.com/", label: "x" } } } }, "schema.a.link has unknown key \"label\""],
        ["a description link without text", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { url: "https://platform.openai.com/" } } } }, "schema.a.link.text must be a printable line of 1 to 60 characters"],
        ["a description link text with a control character", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "Open\u001bAI", url: "https://platform.openai.com/" } } } }, "schema.a.link.text must be a printable line"],
        ["a description link text of 61 characters", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "x".repeat(61), url: "https://platform.openai.com/" } } } }, "schema.a.link.text must be a printable line"],
        ["a description link text its description lacks", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "Anthropic", url: "https://platform.openai.com/" } } } }, "schema.a.link.text must be words of its description"],
        ["a description link with an http address", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "OpenAI", url: "http://platform.openai.com/" } } } }, "schema.a.link.url must be an https address of at most 2048 characters"],
        ["a description link with a file address", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "OpenAI", url: "file:///etc/passwd" } } } }, "schema.a.link.url must be an https address"],
        ["a description link with a javascript address", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "OpenAI", url: "javascript:alert(1)" } } } }, "schema.a.link.url must be an https address"],
        ["a description link with an upper-case scheme", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "OpenAI", url: "HTTPS://platform.openai.com/" } } } }, "schema.a.link.url must be an https address"],
        ["a description link with no host", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "OpenAI", url: "https:///keys" } } } }, "schema.a.link.url must be an https address"],
        ["a description link with a user part", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "OpenAI", url: "https://me@platform.openai.com/" } } } }, "schema.a.link.url must be an https address"],
        ["a description link with a space", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "OpenAI", url: "https://platform.openai.com/api keys" } } } }, "schema.a.link.url must be an https address"],
        ["a description link with an option-like address", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "OpenAI", url: "--help" } } } }, "schema.a.link.url must be an https address"],
        ["a description link address that is not a string", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "OpenAI", url: ["https://platform.openai.com/"] } } } }, "schema.a.link.url must be an https address"],
        ["a description link address of 2049 characters", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "OpenAI", url: "https://a.org/" + "x".repeat(2035) } } } }, "schema.a.link.url must be an https address of at most 2048 characters"],
        ["a description link address of 2048 characters", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Get a key at OpenAI", link: { text: "OpenAI", url: "https://a.org/" + "x".repeat(2034) } } } }, null],
        ["a description link needs its description", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", link: { text: "OpenAI", url: "https://platform.openai.com/" } } } }, "schema.a.link.text must be words of its description"],
        ["a description link belongs to a flat field", { settings: { a: [] }, schema: { a: { type: "list", label: "A", description: "Get a key at OpenAI", link: { text: "OpenAI", url: "https://platform.openai.com/" }, items: { enabled: { type: "boolean", label: "Enabled" } }, defaults: { enabled: true } } } }, "schema.a.link needs a flat setting"],
        ["a description link refuses the old pane key", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Tones are set in Appearance → Sounds", link: { text: "Appearance → Sounds", pane: "vgs.sounds" } } } }, "schema.a.link has unknown key \"pane\""],
        ["a description link refuses the old pane key beside an address", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Tones are set in Appearance → Sounds", link: { text: "Appearance → Sounds", url: "https://example.org/", pane: "vgs.sounds" } } } }, "schema.a.link has unknown key \"pane\""],
        ["a description link needs an address", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", description: "Tones are set in Appearance → Sounds", link: { text: "Appearance → Sounds" } } } }, "schema.a.link.url must be an https address"],
        ["a list item's description link is judged", { settings: { a: [] }, schema: { a: { type: "list", label: "A", items: { enabled: { type: "boolean", label: "Enabled", description: "Get a key at OpenAI", link: { text: "OpenAI", url: "http://platform.openai.com/" } } }, defaults: { enabled: true } } } }, "schema.a.items: schema.enabled.link.url must be an https address"],
        ["enum entry without options", { settings: { a: "x" }, schema: { a: { type: "enum", label: "A" } } }, "schema.a.options must be a non-empty array"],
        ["enum entry with a repeated option", { settings: { a: "x" }, schema: { a: { type: "enum", label: "A", options: [{ value: "x", label: "X" }, { value: "x", label: "Y" }] } } }, "schema.a.options must hold distinct values"],
        ["an enum option that is a plain string", { settings: { a: "x" }, schema: { a: { type: "enum", label: "A", options: ["x"] } } }, "schema.a.options.0 must be an object"],
        ["an enum option without a label", { settings: { a: "x" }, schema: { a: { type: "enum", label: "A", options: [{ value: "x" }] } } }, "schema.a.options.0.label must be a printable line"],
        ["an enum option without a value", { settings: { a: "x" }, schema: { a: { type: "enum", label: "A", options: [{ label: "X" }] } } }, "schema.a.options.0.value must be a non-empty string"],
        ["an enum option with an empty value", { settings: { a: "" }, schema: { a: { type: "enum", label: "A", options: [{ value: "", label: "None" }] } } }, "schema.a.options.0.value must be a non-empty string"],
        ["an enum option with a label of two lines", { settings: { a: "x" }, schema: { a: { type: "enum", label: "A", options: [{ value: "x", label: "A\nB" }] } } }, "schema.a.options.0.label must be a printable line"],
        ["an enum option with an unknown key", { settings: { a: "x" }, schema: { a: { type: "enum", label: "A", options: [{ value: "x", label: "X", name: "X" }] } } }, "schema.a.options.0 has unknown key \"name\""],
        ["options on a non-enum entry", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", options: ["x"] } } }, "schema.a.options needs type enum"],
        ["a string takes choices from status", { capabilities: ["status"], status: { devices: { type: "choices", label: "Devices" } }, settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: "devices" } } }, null],
        ["a configured choice need not be offered", { capabilities: ["status"], status: { devices: { type: "choices", label: "Devices", hidden: true } }, settings: { a: "removed" }, schema: { a: { type: "string", label: "A", optionsFrom: "devices" } } }, null],
        ["optionsFrom on a number", { settings: { a: 1 }, schema: { a: { type: "number", label: "A", optionsFrom: "devices" } } }, "schema.a.optionsFrom needs type string"],
        ["optionsFrom on an enum", { settings: { a: "x" }, schema: { a: { type: "enum", label: "A", options: [{ value: "x", label: "X" }], optionsFrom: "devices" } } }, "schema.a.optionsFrom needs type string"],
        ["optionsFrom on a boolean", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", optionsFrom: "devices" } } }, "schema.a.optionsFrom needs type string"],
        ["optionsFrom not a string", { settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: 3 } } }, "schema.a.optionsFrom must name a status key"],
        ["optionsFrom empty", { settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: "" } } }, "schema.a.optionsFrom must name a status key"],
        ["optionsFrom with a malformed key", { settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: "a b" } } }, "schema.a.optionsFrom must name a status key"],
        ["optionsFrom undeclared", { settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: "devices" } } }, "schema.a.optionsFrom must name a choices status entry"],
        ["optionsFrom inherited", { settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: "constructor" } } }, "schema.a.optionsFrom must name a choices status entry"],
        ["optionsFrom names text", { capabilities: ["status"], status: { devices: { type: "text", label: "Devices" } }, settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: "devices" } } }, "schema.a.optionsFrom must name a choices status entry"],
        ["options and optionsFrom cannot coexist", { capabilities: ["status"], status: { devices: { type: "choices", label: "Devices" } }, settings: { a: "" }, schema: { a: { type: "string", label: "A", options: ["x"], optionsFrom: "devices" } } }, "schema.a.options needs type enum"],
        ["a string entry needs presets or optionsFrom", { settings: { a: "x" }, schema: { a: { type: "string", label: "A" } } }, "schema.a with type string must declare presets or optionsFrom"],
        ["presets and optionsFrom cannot coexist", { capabilities: ["status"], status: { devices: { type: "choices", label: "Devices" } }, settings: { a: "x" }, schema: { a: { type: "string", label: "A", presets: [{ value: "x" }], optionsFrom: "devices" } } }, "schema.a must not declare both presets and optionsFrom"],
        ["a choices string takes a placeholder", { capabilities: ["status"], status: { devices: { type: "choices", label: "Devices" } }, settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: "devices", placeholder: "Choose a device" } } }, null],
        ["a placeholder of 60 characters", { capabilities: ["status"], status: { devices: { type: "choices", label: "Devices" } }, settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: "devices", placeholder: "p".repeat(60) } } }, null],
        ["a list item field takes a placeholder", { capabilities: ["status"], status: { devices: { type: "choices", label: "Devices" } }, settings: { a: [] }, schema: { a: { type: "list", label: "A", items: { device: { type: "string", label: "Device", optionsFrom: "devices", placeholder: "Choose a device" } }, defaults: { device: "" } } } }, null],
        ["a placeholder needs optionsFrom", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", presets: [{ value: "x" }], placeholder: "Choose" } } }, "schema.a.placeholder needs optionsFrom"],
        ["a choices string may hide while nothing is offered", { capabilities: ["status"], status: { devices: { type: "choices", label: "Devices" } }, settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: "devices", hideEmpty: true } } }, null],
        ["hideEmpty needs optionsFrom", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", presets: [{ value: "x" }], hideEmpty: true } } }, "schema.a.hideEmpty needs optionsFrom"],
        ["a hideEmpty that is no boolean", { capabilities: ["status"], status: { devices: { type: "choices", label: "Devices" } }, settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: "devices", hideEmpty: "yes" } } }, "schema.a.hideEmpty must be a boolean"],
        ["a field shown while a presence entry reads present", { capabilities: ["status"], status: { battery: { type: "presence", label: "Battery" } }, settings: { a: true }, schema: { a: { type: "boolean", label: "A", shownWhen: "battery" } } }, null],
        ["a field shown while a hidden presence entry reads present", { capabilities: ["status"], status: { battery: { type: "presence", label: "Battery", hidden: true } }, settings: { a: 20 }, schema: { a: { type: "number", label: "A", presets: [{ value: 20 }], shownWhen: "battery" } } }, null],
        ["a shownWhen naming no status entry", { capabilities: ["status"], status: { battery: { type: "presence", label: "Battery" } }, settings: { a: true }, schema: { a: { type: "boolean", label: "A", shownWhen: "lid" } } }, "schema.a.shownWhen must name a presence status entry"],
        ["a shownWhen without a status declaration", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", shownWhen: "battery" } } }, "schema.a.shownWhen must name a presence status entry"],
        ["a shownWhen naming a state entry", { capabilities: ["status"], status: { battery: { type: "state", label: "Battery" } }, settings: { a: true }, schema: { a: { type: "boolean", label: "A", shownWhen: "battery" } } }, "schema.a.shownWhen must name a presence status entry"],
        ["a shownWhen naming a key list", { capabilities: ["status"], status: { battery: { type: "presenceList", label: "Battery" } }, settings: { a: true }, schema: { a: { type: "boolean", label: "A", shownWhen: "battery" } } }, "schema.a.shownWhen must name a presence status entry"],
        ["a shownWhen that is no string", { capabilities: ["status"], status: { battery: { type: "presence", label: "Battery" } }, settings: { a: true }, schema: { a: { type: "boolean", label: "A", shownWhen: ["battery"] } } }, "schema.a.shownWhen must name a presence status entry"],
        ["a field shown by an enum setting", { settings: { side: "local", a: true }, schema: { side: { type: "enum", label: "Side", options: [{ value: "local", label: "Local" }, { value: "cloud", label: "Cloud" }] }, a: { type: "boolean", label: "A", shownWhen: { setting: "side", in: ["cloud"] } } } }, null],
        ["a setting gate on a string field", { settings: { side: "x", a: true }, schema: { side: { type: "string", label: "Side", presets: [{ value: "x" }] }, a: { type: "boolean", label: "A", shownWhen: { setting: "side", in: ["x"] } } } }, "schema.a.shownWhen.setting must name an enum or boolean schema field"],
        ["a setting gate on a gated field", { settings: { on: true, side: true, a: true }, schema: { on: { type: "boolean", label: "On" }, side: { type: "boolean", label: "Side", shownWhen: { setting: "on", in: [true] } }, a: { type: "boolean", label: "A", shownWhen: { setting: "side", in: [true] } } } }, "schema.a.shownWhen.setting must name a field that is always shown"],
        ["a setting gate with no values", { settings: { on: true, a: true }, schema: { on: { type: "boolean", label: "On" }, a: { type: "boolean", label: "A", shownWhen: { setting: "on", in: [] } } } }, "schema.a.shownWhen.in must be a non-empty list"],
        ["a setting gate with a value the setting cannot hold", { settings: { on: true, a: true }, schema: { on: { type: "boolean", label: "On" }, a: { type: "boolean", label: "A", shownWhen: { setting: "on", in: ["yes"] } } } }, "schema.a.shownWhen.in.0 is no value of on"],
        ["a setting gate with an unknown key", { settings: { on: true, a: true }, schema: { on: { type: "boolean", label: "On" }, a: { type: "boolean", label: "A", shownWhen: { setting: "on", in: [true], when: 1 } } } }, "schema.a.shownWhen has unknown key"],
        ["a list that is shown when", { capabilities: ["status"], status: { battery: { type: "presence", label: "Battery" } }, settings: { a: [] }, schema: { a: { type: "list", label: "A", shownWhen: "battery", items: { on: { type: "boolean", label: "On" } }, defaults: { on: true } } } }, "schema.a.shownWhen needs a flat setting"],
        ["a list item field that is shown when", { capabilities: ["status"], status: { battery: { type: "presence", label: "Battery" } }, settings: { a: [] }, schema: { a: { type: "list", label: "A", items: { on: { type: "boolean", label: "On", shownWhen: "battery" } }, defaults: { on: true } } } }, "schema.a.items.on.shownWhen is refused: an item draws every field"],
        // An enum's option groups (optionGroupsError) and the select's own
        // entries (addChoice, preview).
        ["an enum of a one-option group and a many-option group", { settings: { side: "local" }, schema: { side: grouped() } }, null],
        ["an enum of two one-option groups", { settings: { side: "a" }, schema: { side: { type: "enum", label: "Side", options: [{ value: "a", label: "A", group: "A" }, { value: "b", label: "B", group: "B" }] } } }, null],
        ["options of which only some declare a group", { settings: { side: "local" }, schema: { side: grouped(e => { delete e.options[1].group; }) } }, "schema.side.options must all declare group, or none"],
        ["a group that is no printable word", { settings: { side: "local" }, schema: { side: grouped(e => { e.options[0].group = "x".repeat(17); }) } }, "schema.side.options group must be a printable line of 1 to 16"],
        ["one group's options apart", { settings: { side: "local" }, schema: { side: grouped(e => { e.options.push({ value: "near", label: "Near", group: "Local" }); }) } }, "schema.side.options of one group must stand together"],
        ["one group", { settings: { side: "local" }, schema: { side: grouped(e => { e.options.forEach(o => { o.group = "Cloud"; }); }) } }, "schema.side.options must form 2 to 3 groups"],
        ["four groups", { settings: { side: "local" }, schema: { side: grouped(e => { e.options.forEach((o, i) => { o.group = "G" + i; }); delete e.groupLabel; }) } }, "schema.side.options must form 2 to 3 groups"],
        ["two groups of several options", { settings: { side: "local" }, schema: { side: grouped(e => { e.options.push({ value: "near", label: "Near", group: "Local" }); e.options.splice(1, 0, e.options.pop()); }) } }, "schema.side.options may hold several options in one group only"],
        ["a many-option group with no groupLabel", { settings: { side: "local" }, schema: { side: grouped(e => { delete e.groupLabel; }) } }, "schema.side.groupLabel labels the select of a group of several options"],
        ["a groupLabel over one-option groups", { settings: { side: "a" }, schema: { side: { type: "enum", label: "Side", groupLabel: "Kind", options: [{ value: "a", label: "A", group: "A" }, { value: "b", label: "B", group: "B" }] } } }, "schema.side.groupLabel labels the select of a group of several options"],
        ["a groupLabel over options with no group", { settings: { side: "a" }, schema: { side: { type: "enum", label: "Side", groupLabel: "Kind", options: [{ value: "a", label: "A" }, { value: "b", label: "B" }] } } }, "schema.side.groupLabel needs options that declare group"],
        ["a groupLabel on a boolean", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", groupLabel: "Kind" } } }, "schema.a.groupLabel needs type enum"],
        ["a groupLabel on two lines", { settings: { side: "local" }, schema: { side: grouped(e => { e.groupLabel = "Cloud\nvoice"; }) } }, "schema.side.groupLabel must be a printable line"],
        ["a list item enum of groups", { settings: { a: [] }, schema: { a: { type: "list", label: "A", items: { side: grouped() }, defaults: { side: "local" } } } }, "schema.a.items.side.groupLabel is refused: an item draws a plain control"],
        ["a list item enum of groups with no label", { settings: { a: [] }, schema: { a: { type: "list", label: "A", items: { side: { type: "enum", label: "Side", options: [{ value: "a", label: "A", group: "A" }, { value: "b", label: "B", group: "B" }] } }, defaults: { side: "a" } } } }, "schema.a.items.side.options group is refused: an item draws a plain control"],
        ["an Add entry and a preview on a choices string", offering(), null],
        ["an Add entry on a string with no choices", offering(m => { delete m.schema.voice.optionsFrom; delete m.schema.voice.preview; m.schema.voice.presets = [{ value: "a" }]; m.settings.voice = "a"; }), "schema.voice.addChoice needs optionsFrom"],
        ["an Add entry with an unknown key", offering(m => { m.schema.voice.addChoice.icon = "plus"; }), "schema.voice.addChoice must be { label, tui }"],
        ["an Add entry with no label", offering(m => { delete m.schema.voice.addChoice.label; }), "schema.voice.addChoice.label must be a printable line"],
        ["an Add entry whose tui is no name", offering(m => { m.schema.voice.addChoice.tui = 3; }), "schema.voice.addChoice.tui must name a script"],
        ["an Add entry naming an undeclared screen", offering(m => { m.schema.voice.addChoice.tui = "other"; }), "schema.voice.addChoice.tui must name a script of the manifest's tui key, got \"other\""],
        ["a preview that is false", offering(m => { m.schema.voice.preview = false; }), "schema.voice.preview must be true, on a field with optionsFrom"],
        ["a preview on a string with no choices", offering(m => { delete m.schema.voice.optionsFrom; delete m.schema.voice.addChoice; m.schema.voice.presets = [{ value: "a" }]; m.settings.voice = "a"; }), "schema.voice.preview must be true, on a field with optionsFrom"],
        ["a list item Add entry", offering(m => { m.schema.list = { type: "list", label: "List", items: { voice: m.schema.voice }, defaults: { voice: "" } }; m.settings.list = []; delete m.schema.voice; delete m.settings.voice; }), "schema.list.items.voice.addChoice is refused: an item draws a plain control"],
        ["a field with hidden failure text", { capabilities: ["status"], status: { failure: { type: "text", label: "Failure", hidden: true } }, settings: { a: true }, schema: { a: { type: "boolean", label: "A", problem: "failure" } } }, null],
        ["a field with drawn failure text", { capabilities: ["status"], status: { failure: { type: "text", label: "Failure" } }, settings: { a: 20 }, schema: { a: { type: "number", label: "A", presets: [{ value: 20 }], problem: "failure" } } }, null],
        ["a problem naming no status entry", { capabilities: ["status"], status: { failure: { type: "text", label: "Failure" } }, settings: { a: true }, schema: { a: { type: "boolean", label: "A", problem: "missing" } } }, "schema.a.problem must name a text status entry"],
        ["a problem without status", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", problem: "failure" } } }, "schema.a.problem must name a text status entry"],
        ["a problem that is no string", { capabilities: ["status"], status: { failure: { type: "text", label: "Failure" } }, settings: { a: true }, schema: { a: { type: "boolean", label: "A", problem: ["failure"] } } }, "schema.a.problem must name a text status entry"],
        ["a problem naming a presence entry", { capabilities: ["status"], status: { failure: { type: "presence", label: "Failure" } }, settings: { a: true }, schema: { a: { type: "boolean", label: "A", problem: "failure" } } }, "schema.a.problem must name a text status entry"],
        ["a list with a problem", { capabilities: ["status"], status: { failure: { type: "text", label: "Failure" } }, settings: { a: [] }, schema: { a: { type: "list", label: "A", problem: "failure", items: { on: { type: "boolean", label: "On" } }, defaults: { on: true } } } }, "schema.a.problem needs a flat setting"],
        ["a list item field with a problem", { capabilities: ["status"], status: { failure: { type: "text", label: "Failure" } }, settings: { a: [] }, schema: { a: { type: "list", label: "A", items: { on: { type: "boolean", label: "On", problem: "failure" } }, defaults: { on: true } } } }, "schema.a.items.on.problem is refused: a problem names a setting, not a list item"],
        ["a placeholder that is not a string", { capabilities: ["status"], status: { devices: { type: "choices", label: "Devices" } }, settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: "devices", placeholder: 3 } } }, "schema.a.placeholder must be a printable line"],
        ["an empty placeholder", { capabilities: ["status"], status: { devices: { type: "choices", label: "Devices" } }, settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: "devices", placeholder: "" } } }, "schema.a.placeholder must be a printable line"],
        ["a placeholder with a newline", { capabilities: ["status"], status: { devices: { type: "choices", label: "Devices" } }, settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: "devices", placeholder: "Choose\na device" } } }, "schema.a.placeholder must be a printable line"],
        ["a placeholder with a control character", { capabilities: ["status"], status: { devices: { type: "choices", label: "Devices" } }, settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: "devices", placeholder: "Choose\u0007" } } }, "schema.a.placeholder must be a printable line"],
        ["a placeholder of 61 characters", { capabilities: ["status"], status: { devices: { type: "choices", label: "Devices" } }, settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: "devices", placeholder: "p".repeat(61) } } }, "schema.a.placeholder must be a printable line"],
        ["presets need string or number", { settings: { a: true }, schema: { a: { type: "boolean", label: "A", presets: [{ value: true }] } } }, "schema.a.presets needs type string or number"],
        ["presets must be non-empty", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", presets: [] } } }, "schema.a.presets must be a non-empty array"],
        ["preset rows are objects", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", presets: ["x"] } } }, "schema.a.presets.0 must be an object"],
        ["preset rows have known keys", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", presets: [{ value: "x", name: "X" }] } } }, "schema.a.presets.0 has unknown key \"name\""],
        ["preset value is required", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", presets: [{ label: "X" }] } } }, "schema.a.presets.0.value is required"],
        ["preset label is printable", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", presets: [{ value: "x", label: "A\nB" }] } } }, "schema.a.presets.0.label must be a printable line"],
        ["empty preset needs a label", { settings: { a: "" }, schema: { a: { type: "string", label: "A", presets: [{ value: "" }] } } }, "schema.a.presets.0.label is required when value is empty"],
        ["preset values are distinct", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", presets: [{ value: "x" }, { value: "x" }] } } }, "schema.a.presets must hold distinct values"],
        ["preset value fits schema", { settings: { a: 2 }, schema: { a: { type: "number", label: "A", min: 2, max: 4, presets: [{ value: 1 }] } } }, "schema.a.presets.0.value does not fit its schema: want=at-least:2"],
        ["allowCustom beside presets", { settings: { a: "y" }, schema: { a: { type: "string", label: "A", presets: [{ value: "x" }], allowCustom: true } } }, null],
        ["allowCustom beside optionsFrom", { capabilities: ["status"], status: { devices: { type: "choices", label: "Devices" } }, settings: { a: "" }, schema: { a: { type: "string", label: "A", optionsFrom: "devices", allowCustom: true } } }, null],
        ["allowCustom on a string needs presets or optionsFrom", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", allowCustom: true } } }, "schema.a.allowCustom needs presets or optionsFrom"],
        ["allowCustom on a number without presets is refused", { settings: { a: 2 }, schema: { a: { type: "number", label: "A", allowCustom: true } } }, "schema.a.allowCustom needs presets or optionsFrom"],
        ["allowCustom is boolean", { settings: { a: 2 }, schema: { a: { type: "number", label: "A", presets: [{ value: 2 }], allowCustom: "yes" } } }, "schema.a.allowCustom must be a boolean"],
        ["format needs string", { settings: { a: 2 }, schema: { a: { type: "number", label: "A", presets: [{ value: 2 }], format: "datetime" } } }, "schema.a.format needs type string"],
        ["format needs presets", { settings: { a: "HH:mm" }, schema: { a: { type: "string", label: "A", format: "datetime" } } }, "schema.a.format needs presets"],
        ["format names datetime", { settings: { a: "HH:mm" }, schema: { a: { type: "string", label: "A", presets: [{ value: "HH:mm" }], format: "strftime" } } }, "schema.a.format must be one of datetime"],
        ["datetime presets are judged", { settings: { a: "HH:mm" }, schema: { a: { type: "string", label: "A", presets: [{ value: "'abc" }], format: "datetime" } } }, "schema.a.presets.0.value does not fit its schema: want=datetime-format reason=unclosed-quote"],
        ["unit needs number", { settings: { a: "x" }, schema: { a: { type: "string", label: "A", presets: [{ value: "x" }], unit: "seconds" } } }, "schema.a.unit needs type number"],
        ["unit is known", { settings: { a: 2 }, schema: { a: { type: "number", label: "A", unit: "weeks" } } }, "schema.a.unit must be one of seconds, minutes, hours, days, %"],
        ["schema entry without a default", { schema: { a: { type: "string", label: "A", presets: [{ value: "x" }] } } }, "schema.a has no default in settings"],
        ["default of the wrong type", { settings: { a: 3 }, schema: { a: { type: "string", label: "A", presets: [{ value: "x" }] } } }, "settings.a does not fit its schema: want=string"],
        ["enum default outside its options", { settings: { a: "z" }, schema: { a: { type: "enum", label: "A", options: [{ value: "x", label: "X" }, { value: "y", label: "Y" }] } } }, "settings.a does not fit its schema: want=one-of:x|y"],
        ["configure without a schema", { capabilities: ["configure"] }, "capability configure needs a schema"],
        ["configure with a schema", { capabilities: ["configure"], settings: { a: true }, schema: { a: { type: "boolean", label: "A" } } }, null],
        ["status with every entry key", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { slackToken: { type: "presence", label: "Slack token", setup: true, group: "Slack", hint: "h", action: { label: "Set up", tui: "setup" }, hidden: false }, detail: { type: "data", label: "Detail" }, catalog: { type: "launcherRows", label: "Catalog" } } }, null],
        ["status not an object", { capabilities: ["status"], status: [] }, "status must be an object"],
        ["status with no entry", { capabilities: ["status"], status: {} }, "status must declare at least one entry"],
        ["status without capability status", { status: { a: { type: "text", label: "A" } } }, "status needs capability status"],
        ["capability status without a status", { capabilities: ["status"] }, "capability status needs a status declaration"],
        ["a status key with a dash", { capabilities: ["status"], status: { "slack-token": { type: "text", label: "A" } } }, "status key \"slack-token\" must match"],
        ["a status key starting upper case", { capabilities: ["status"], status: { Token: { type: "text", label: "A" } } }, "status key \"Token\" must match"],
        ["a status entry not an object", { capabilities: ["status"], status: { a: "text" } }, "status.a must be an object"],
        ["a status entry with an unknown key", { capabilities: ["status"], status: { a: { type: "text", label: "A", run: true } } }, "status.a has unknown key \"run\""],
        ["a status entry with an unknown type", { capabilities: ["status"], status: { a: { type: "secret", label: "A" } } }, "status.a.type must be one of presence, presenceList, state, text, count, time, data, choices, launcherRows, rows"],
        ["a presenceList entry with its group and hint", { capabilities: ["status"], status: { tokens: { type: "presenceList", label: "Tokens", group: "Slack", hint: "h" } } }, null],
        ["a status entry without a label", { capabilities: ["status"], status: { a: { type: "text" } } }, "status.a.label must be a printable line of 1 to 60"],
        ["a status label of 61 characters", { capabilities: ["status"], status: { a: { type: "text", label: "x".repeat(61) } } }, "status.a.label must be a printable line of 1 to 60"],
        ["a status label of 60 characters", { capabilities: ["status"], status: { a: { type: "text", label: "x".repeat(60) } } }, null],
        ["a status label with a newline", { capabilities: ["status"], status: { a: { type: "text", label: "A\nB" } } }, "status.a.label must be a printable line"],
        ["an empty status group", { capabilities: ["status"], status: { a: { type: "text", label: "A", group: "" } } }, "status.a.group must be a printable line of 1 to 60"],
        ["a status hint counts words, not a long encoded target", { capabilities: ["status"], status: { a: { type: "text", label: "A", hint: "Open [notes](file:%2F" + "folder%20".repeat(80) + "notes.md)" } } }, null],
        ["a status info counts words, not a long encoded target", { capabilities: ["status"], status: { a: { type: "text", label: "A", info: "Open [notes](file:%2F" + "folder%20".repeat(80) + "notes.md)." } } }, null],
        ["a status hint refuses excess visible link words", { capabilities: ["status"], status: { a: { type: "text", label: "A", hint: "[" + "x".repeat(201) + "](file:a.md)" } } }, "status.a.hint must be a printable line"],
        ["a status info refuses excess visible link words", { capabilities: ["status"], status: { a: { type: "text", label: "A", info: "[" + "x".repeat(401) + "](file:a.md)" } } }, "status.a.info must be printable lines"],
        ["a status hint bounds its whole stored reference", { capabilities: ["status"], status: { a: { type: "text", label: "A", hint: "[notes](file:" + "a".repeat(65536) + ")" } } }, "status.a.hint must be a printable line"],
        ["a status info bounds its whole stored reference", { capabilities: ["status"], status: { a: { type: "text", label: "A", info: "[notes](file:" + "a".repeat(65536) + ")" } } }, "status.a.info must be printable lines"],
        ["a status hint of 201 characters", { capabilities: ["status"], status: { a: { type: "text", label: "A", hint: "x".repeat(201) } } }, "status.a.hint must be a printable line of 1 to 200"],
        ["a status hint of 200 characters", { capabilities: ["status"], status: { a: { type: "text", label: "A", hint: "x".repeat(200) } } }, null],
        ["a status hint of one sentence with a full stop is refused", { capabilities: ["status"], status: { a: { type: "text", label: "A", hint: "Connect the account." } } }, "status.a.hint must end with no full stop"],
        ["a status hint of one sentence without a full stop", { capabilities: ["status"], status: { a: { type: "text", label: "A", hint: "Connect the account" } } }, null],
        ["a status entry with info", { capabilities: ["status"], status: { a: { type: "text", label: "A", info: "What this status means." } } }, null],
        ["a status info that is not a string", { capabilities: ["status"], status: { a: { type: "text", label: "A", info: 1 } } }, "status.a.info must be printable lines"],
        ["an empty status info", { capabilities: ["status"], status: { a: { type: "text", label: "A", info: "" } } }, "status.a.info must be printable lines"],
        ["a status hint link to an https address", { capabilities: ["status"], status: { a: { type: "state", label: "A", hint: "Open GitHub settings", link: { text: "GitHub settings", url: "https://github.com/settings" } } } }, null],
        ["a status hint link text its hint lacks", { capabilities: ["status"], status: { a: { type: "state", label: "A", hint: "Open the settings", link: { text: "GitHub settings", url: "https://github.com/settings" } } } }, "status.a.link.text must be words of its hint"],
        ["a status hint link needs its hint", { capabilities: ["status"], status: { a: { type: "state", label: "A", link: { text: "GitHub settings", url: "https://github.com/settings" } } } }, "status.a.link.text must be words of its hint"],
        ["a status hint link refuses the old pane key", { capabilities: ["status"], status: { a: { type: "state", label: "A", hint: "Open the Sounds page", link: { text: "Sounds page", pane: "vgs.sounds" } } } }, "status.a.link has unknown key \"pane\""],
        ["a status hint link with an http address", { capabilities: ["status"], status: { a: { type: "state", label: "A", hint: "Open GitHub settings", link: { text: "GitHub settings", url: "http://github.com/settings" } } } }, "status.a.link.url must be an https address"],
        ["a status info with a control character", { capabilities: ["status"], status: { a: { type: "text", label: "A", info: "A\u001bB" } } }, "status.a.info must be printable lines"],
        ["a status info of 401 characters", { capabilities: ["status"], status: { a: { type: "text", label: "A", info: "x".repeat(401) } } }, "status.a.info must be printable lines"],
        ["a status info of 400 characters", { capabilities: ["status"], status: { a: { type: "text", label: "A", info: "x".repeat(400) } } }, null],
        ["a state action opening the plugin's own TUI", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Set up", tui: "setup" } } } }, null],
        ["a presence action naming install, though its command is a declared requirement", { capabilities: ["status"], requirements: [{ command: "vsys", purpose: "p" }], status: { a: { type: "presence", label: "A", setup: true, action: { label: "Install", install: ["vsys"] } } } }, "status.a.action has unknown key \"install\""],
        ["a named action naming install", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, requirements: [{ command: "gum", purpose: "q" }], status: { a: { type: "state", label: "A", setup: true, actions: { fix: { label: "Fix", tui: "setup" }, get: { label: "Install", install: ["gum"] } } } } }, "status.a.actions.get has unknown key \"install\""],
        ["an action on a count", { capabilities: ["status"], status: { a: { type: "count", label: "A", action: { label: "Install", tui: "setup" } } } }, "status.a.action needs a type whose value says when it applies, one of presence, state"],
        ["an action on a presence list", { capabilities: ["status"], status: { a: { type: "presenceList", label: "A", action: { label: "Install", tui: "setup" } } } }, "status.a.action needs a type whose value says when it applies"],
        ["an action that is a string", { capabilities: ["status"], status: { a: { type: "state", label: "A", setup: true, action: "setup" } } }, "status.a.action must be an object"],
        ["an action with an unknown key", { capabilities: ["status"], status: { a: { type: "state", label: "A", setup: true, action: { label: "Run", run: ["sh"] } } } }, "status.a.action has unknown key \"run\""],
        ["an action without a label", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, action: { tui: "setup" } } } }, "status.a.action.label must be a printable line of 1 to 60"],
        ["an action label of 61 characters", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "x".repeat(61), tui: "setup" } } } }, "status.a.action.label must be a printable line"],
        ["an action naming neither", { capabilities: ["status"], status: { a: { type: "state", label: "A", setup: true, action: { label: "Go" } } } }, "status.a.action must name exactly one of tui, system, undo, dictation, file"],
        ["a state with two named actions", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, actions: { fix: { label: "Fix", tui: "setup" }, get: { label: "Redo", tui: "setup" } } } } }, null],
        // An aside: one more TUI action a state step's row draws beside
        // its step, opening a listed screen (Jarvis's Remove key).
        ["an aside on a state step", { capabilities: ["status", "tui"], tui: { add: { script: "tui/add.sh", title: "Add" }, remove: { script: "tui/remove.sh", title: "Remove", entry: { label: "Remove", icon: "trash", group: "Acme" } } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Add", tui: "add" }, aside: { label: "Remove", tui: "remove", tone: "danger" } } } }, null],
        ["an aside on a presence", { capabilities: ["status", "tui"], tui: { add: { script: "tui/add.sh", title: "Add" }, remove: { script: "tui/remove.sh", title: "Remove", entry: { label: "Remove", icon: "trash", group: "Acme" } } }, status: { a: { type: "presence", label: "A", setup: true, action: { label: "Add", tui: "add" }, aside: { label: "Remove", tui: "remove" } } } }, "status.a.aside needs type state, whose value says when it applies"],
        ["an aside on a data entry", { capabilities: ["status", "tui"], tui: { remove: { script: "tui/remove.sh", title: "Remove", entry: { label: "Remove", icon: "trash", group: "Acme" } } }, status: { a: { type: "data", label: "A", aside: { label: "Remove", tui: "remove" } } } }, "status.a.aside needs a type Settings draws"],
        ["an aside with no step beside it", { capabilities: ["status", "tui"], tui: { remove: { script: "tui/remove.sh", title: "Remove", entry: { label: "Remove", icon: "trash", group: "Acme" } } }, status: { a: { type: "state", label: "A", aside: { label: "Remove", tui: "remove" } } } }, "status.a.aside needs the entry's action or actions"],
        ["an aside with a system route", { capabilities: ["status", "tui", "system"], systemSteps: ["i2c-dev"], tui: { add: { script: "tui/add.sh", title: "Add" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Add", tui: "add" }, aside: { label: "Allow", system: "i2c-dev" } } } }, "status.a.aside must name a tui"],
        ["an aside naming a TUI with no entry", { capabilities: ["status", "tui"], tui: { add: { script: "tui/add.sh", title: "Add" }, remove: { script: "tui/remove.sh", title: "Remove" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Add", tui: "add" }, aside: { label: "Remove", tui: "remove" } } } }, "status.a.aside.tui must name a script with an entry"],
        ["an aside the action judge refuses", { capabilities: ["status", "tui"], tui: { add: { script: "tui/add.sh", title: "Add" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Add", tui: "add" }, aside: { label: "Remove", tui: "gone" } } } }, "status.a.aside.tui must name a script of the manifest's tui key"],
        ["named actions on a presence", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "presence", label: "A", setup: true, actions: { fix: { label: "Fix", tui: "setup" }, get: { label: "Redo", tui: "setup" } } } } }, "status.a.actions needs type state, whose value names the one that applies"],
        ["an action beside named actions", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Fix", tui: "setup" }, actions: { fix: { label: "Fix", tui: "setup" }, get: { label: "Redo", tui: "setup" } } } } }, "status.a declares both action and actions"],
        ["a danger action", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Sign out", tui: "setup", tone: "danger" } } } }, null],
        ["a named danger action", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, requirements: [{ command: "gum", purpose: "q" }], status: { a: { type: "state", label: "A", setup: true, actions: { fix: { label: "Fix", tui: "setup" }, out: { label: "Sign out", tui: "setup", tone: "danger" } } } } }, null],
        // A danger action that removes nothing names its own mark from
        // the shipped icon set; only a danger action draws one.
        ["a danger action naming its mark", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Sign out", tui: "setup", tone: "danger", icon: "log-out" } } } }, null],
        ["a danger action naming an icon the set lacks", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Sign out", tui: "setup", tone: "danger", icon: "door-exit" } } } }, "status.a.action.icon must name an icon of the shipped set, shell/Ui/icons/Lucide.js, got \"door-exit\""],
        ["a danger action naming an inherited icon name", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Sign out", tui: "setup", tone: "danger", icon: "constructor" } } } }, "status.a.action.icon must name an icon of the shipped set"],
        ["a danger action naming an icon that is not a string", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Sign out", tui: "setup", tone: "danger", icon: ["log-out"] } } } }, "status.a.action.icon must name an icon of the shipped set"],
        ["an accent action naming a mark", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Sign in", tui: "setup", icon: "log-in" } } } }, "status.a.action.icon needs tone danger"],
        ["an aside naming a mark the set lacks", { capabilities: ["status", "tui"], tui: { add: { script: "tui/add.sh", title: "Add" }, remove: { script: "tui/remove.sh", title: "Remove", entry: { label: "Remove", icon: "trash", group: "Acme" } } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Add", tui: "add" }, aside: { label: "Remove", tui: "remove", tone: "danger", icon: "bin" } } } }, "status.a.aside.icon must name an icon of the shipped set"],
        ["an action of another tone", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Fix", tui: "setup", tone: "warning" } } } }, "status.a.action.tone must be one of danger, got \"warning\""],
        ["an action of an empty tone", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Fix", tui: "setup", tone: "" } } } }, "status.a.action.tone must be one of danger"],
        ["a named action of another tone", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, actions: { fix: { label: "Fix", tui: "setup", tone: "accent" }, get: { label: "Redo", tui: "setup" } } } } }, "status.a.actions.fix.tone must be one of danger"],
        ["one named action", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, requirements: [{ command: "gum", purpose: "q" }], status: { a: { type: "state", label: "A", setup: true, actions: { fix: { label: "Fix", tui: "setup" } } } } }, "status.a.actions must be an object of two or more actions; one action is the entry's action"],
        ["named actions that are a list", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, actions: [{ label: "Fix", tui: "setup" }, { label: "Redo", tui: "setup" }] } } }, "status.a.actions must be an object of two or more actions"],
        ["a named action whose name is no identifier", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, actions: { "fix it": { label: "Fix", tui: "setup" }, get: { label: "Redo", tui: "setup" } } } } }, "status.a.actions key \"fix it\" must match"],
        ["a named action opening an undeclared TUI", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, actions: { fix: { label: "Fix", tui: "nope" }, get: { label: "Redo", tui: "setup" } } } } }, "status.a.actions.fix.tui must name a script of the manifest's tui key, got \"nope\""],
        ["an action naming an undeclared TUI", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Go", tui: "other" } } } }, "status.a.action.tui must name a script of the manifest's tui key, got \"other\""],
        ["an action naming a TUI with no tui key", { capabilities: ["status"], status: { a: { type: "state", label: "A", setup: true, action: { label: "Go", tui: "setup" } } } }, "status.a.action.tui must name a script of the manifest's tui key"],
        ["an action naming an inherited TUI name", { capabilities: ["status", "tui"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Go", tui: "constructor" } } } }, "status.a.action.tui must name a script of the manifest's tui key"],
        ["a data entry with an action", { capabilities: ["status"], status: { a: { type: "data", label: "A", action: { label: "Go", tui: "setup" } } } }, "status.a.action needs a type whose value says when it applies"],
        // systemSteps (D081): steps of the core's closed table, read through capability system.
        ["systemSteps naming two steps", { capabilities: ["system"], systemSteps: ["apple-displays", "i2c-dev"] }, null],
        ["every step of the table", { capabilities: ["system"], systemSteps: ["apple-displays", "i2c-dev", "service-bluetooth", "service-tailscaled", "service-cups", "tailscale-operator", "tailscale-account-add", "greeter", "bandwhich-capture", "reboot-notice", "voxtype-engine"] }, null],
        ["systemSteps that is not a list", { capabilities: ["system"], systemSteps: "i2c-dev" }, "systemSteps must be a non-empty list of steps of the core's table"],
        ["an empty systemSteps", { capabilities: ["system"], systemSteps: [] }, "systemSteps must be a non-empty list"],
        ["a step outside the table", { capabilities: ["system"], systemSteps: ["etc-shadow"] }, "systemSteps.0 must be one of"],
        ["a step that is not a string", { capabilities: ["system"], systemSteps: ["i2c-dev", 3] }, "systemSteps.1 must be one of"],
        ["a step named twice", { capabilities: ["system"], systemSteps: ["i2c-dev", "i2c-dev"] }, "systemSteps.1 repeats \"i2c-dev\""],
        ["systemSteps without capability system", { systemSteps: ["i2c-dev"] }, "systemSteps needs capability system"],
        ["capability system without systemSteps", { capabilities: ["system"] }, "capability system needs a systemSteps declaration"],
        ["a state action applying a declared step", { capabilities: ["status", "system"], systemSteps: ["apple-displays"], status: { apple: { type: "state", label: "Apple displays", setup: true, action: { label: "Allow", system: "apple-displays" } } } }, null],
        ["a presence action applying a declared step", { capabilities: ["status", "system"], systemSteps: ["i2c-dev"], status: { ddc: { type: "presence", label: "DDC", setup: true, action: { label: "Allow", system: "i2c-dev" } } } }, null],
        ["an action applying a step the manifest does not declare", { capabilities: ["status", "system"], systemSteps: ["i2c-dev"], status: { apple: { type: "state", label: "A", setup: true, action: { label: "Allow", system: "apple-displays" } } } }, "status.apple.action.system must name a step of the manifest's systemSteps, got \"apple-displays\""],
        ["an action applying a step with no systemSteps", { capabilities: ["status"], status: { apple: { type: "state", label: "A", setup: true, action: { label: "Allow", system: "apple-displays" } } } }, "status.apple.action.system must name a step of the manifest's systemSteps"],
        ["an action applying a step outside the table", { capabilities: ["status", "system"], systemSteps: ["i2c-dev"], status: { a: { type: "state", label: "A", setup: true, action: { label: "Allow", system: "etc-shadow" } } } }, "status.a.action.system must name a step of the manifest's systemSteps, got \"etc-shadow\""],
        ["an action naming a system step and a TUI", { capabilities: ["status", "system", "tui"], systemSteps: ["i2c-dev"], tui: { setup: { script: "tui/setup.sh", title: "Set up" } }, status: { a: { type: "state", label: "A", setup: true, action: { label: "Go", tui: "setup", system: "i2c-dev" } } } }, "status.a.action must name exactly one of tui, system, undo, dictation, file"],
        ["a state action undoing a declared step", { capabilities: ["status", "system"], systemSteps: ["reboot-notice"], status: { notice: { type: "state", label: "Reboot notice", setup: true, actions: { off: { label: "Turn off", system: "reboot-notice" }, on: { label: "Turn on", undo: "reboot-notice" } } } } }, null],
        ["an action undoing a step the manifest does not declare", { capabilities: ["status", "system"], systemSteps: ["i2c-dev"], status: { a: { type: "state", label: "A", setup: true, action: { label: "Undo", undo: "reboot-notice" } } } }, "status.a.action.undo must name a step of the manifest's systemSteps, got \"reboot-notice\""],
        ["an action undoing a step with no systemSteps", { capabilities: ["status"], status: { a: { type: "state", label: "A", setup: true, action: { label: "Undo", undo: "reboot-notice" } } } }, "status.a.action.undo must name a step of the manifest's systemSteps"],
        ["an action applying and undoing a step", { capabilities: ["status", "system"], systemSteps: ["i2c-dev"], status: { a: { type: "state", label: "A", setup: true, action: { label: "Go", system: "i2c-dev", undo: "i2c-dev" } } } }, "status.a.action must name exactly one of tui, system, undo, dictation, file"],
        ["an action naming a system step that is a list", { capabilities: ["status", "system"], systemSteps: ["i2c-dev"], status: { a: { type: "state", label: "A", setup: true, action: { label: "Go", system: ["i2c-dev"] } } } }, "status.a.action.system must name a step of the manifest's systemSteps"],
        ["secrets beside a presence list", { capabilities: ["status", "secrets"], secrets: { service: "acme-sync", label: "Acme token" }, status: { tokens: { type: "presenceList", label: "Tokens" } } }, null],
        ["secrets not an object", { capabilities: ["status", "secrets"], secrets: "acme", status: { tokens: { type: "presenceList", label: "Tokens" } } }, "secrets must be an object"],
        ["secrets with an unknown key", { capabilities: ["status", "secrets"], secrets: { service: "acme", label: "L", schema: "x" }, status: { tokens: { type: "presenceList", label: "Tokens" } } }, "secrets has unknown key \"schema\""],
        ["a secrets service with a dot", { capabilities: ["status", "secrets"], secrets: { service: "acme.sync", label: "L" }, status: { tokens: { type: "presenceList", label: "Tokens" } } }, "secrets.service must match"],
        ["a secrets service of 65 characters", { capabilities: ["status", "secrets"], secrets: { service: "a".repeat(65), label: "L" }, status: { tokens: { type: "presenceList", label: "Tokens" } } }, "secrets.service must match"],
        ["a secrets service of 64 characters", { capabilities: ["status", "secrets"], secrets: { service: "a".repeat(64), label: "L" }, status: { tokens: { type: "presenceList", label: "Tokens" } } }, null],
        ["a secrets label with a newline", { capabilities: ["status", "secrets"], secrets: { service: "acme", label: "A\nB" }, status: { tokens: { type: "presenceList", label: "Tokens" } } }, "secrets.label must be a printable line of 1 to 60"],
        ["secrets without capability secrets", { capabilities: ["status"], secrets: { service: "acme", label: "L" }, status: { tokens: { type: "presenceList", label: "Tokens" } } }, "secrets needs capability secrets"],
        ["capability secrets without secrets", { capabilities: ["secrets"] }, "capability secrets needs a secrets declaration"],
        ["secrets with no presence list to list them", { capabilities: ["status", "secrets"], secrets: { service: "acme", label: "L" }, status: { token: { type: "presence", label: "Token" } } }, "secrets needs a presenceList status entry to list its items"],
        ["secrets with no status", { capabilities: ["secrets"], secrets: { service: "acme", label: "L" } }, "secrets needs a presenceList status entry to list its items"],
        ["a status hidden that is not a boolean", { capabilities: ["status"], status: { a: { type: "text", label: "A", hidden: "yes" } } }, "status.a.hidden must be a boolean"],
        ["a data entry with a hint", { capabilities: ["status"], status: { a: { type: "data", label: "A", hint: "h" } } }, "status.a.hint needs a type Settings draws"],
        ["a data entry with info", { capabilities: ["status"], status: { a: { type: "data", label: "A", info: "h" } } }, "status.a.info needs a type Settings draws"],
        ["a data entry that is hidden", { capabilities: ["status"], status: { a: { type: "data", label: "A", hidden: true } } }, "status.a.hidden needs a type Settings draws"],
        ["a launcherRows entry with a group", { capabilities: ["status"], status: { a: { type: "launcherRows", label: "A", group: "Launch" } } }, "status.a.group needs a type Settings draws"],
        ["a launcherRows entry with an action", { capabilities: ["status"], status: { a: { type: "launcherRows", label: "A", action: { label: "Go", tui: "setup" } } } }, "status.a.action needs a type whose value says when it applies"],
    ];
    for (const [name, patch, want] of manifestRows) {
        const raw = Object.assign(JSON.parse(JSON.stringify(bar)), patch);
        const r = ctx.validateManifest(raw, "/p");
        check("validateManifest: " + name, r.ok ? null : r.error.slice(0, want === null ? 0 : want.length), want === null ? null : want);
    }
    // The fields a page withholds (withheldFields): [name, published
    // values, the withheld keys]. `low` waits on the battery, `lid` on the
    // lid, and `kept` on nothing.
    const gated = { schema: { low: { type: "boolean", label: "Low", shownWhen: "battery" }, kept: { type: "boolean", label: "Kept" }, lid: { type: "boolean", label: "Lid", shownWhen: "lid" } } };
    for (const [name, values, want] of [
        ["every entry present", { battery: "present", lid: "present" }, []],
        ["every entry absent", { battery: "absent", lid: "absent" }, ["low", "lid"]],
        ["before the first publish", {}, ["low", "lid"]],
        ["one entry present", { battery: "present", lid: "absent" }, ["lid"]],
        ["a presence that is not present", { battery: "unavailable", lid: "present" }, ["low"]],
    ]) check("withheldFields: " + name, ctx.withheldFields(gated, values, {}), want);
    // A field gated on a setting follows its value, whatever is published.
    const sided = { schema: { side: { type: "enum", label: "Side", options: [{ value: "local", label: "L" }, { value: "cloud", label: "C" }] },
        key: { type: "boolean", label: "Key", shownWhen: { setting: "side", in: ["cloud"] } }, tier: { type: "boolean", label: "Tier", shownWhen: { setting: "side", in: ["local"] } } } };
    for (const [name, settings, want] of [
        ["the local side hides the cloud field", { side: "local" }, ["key"]],
        ["the cloud side hides the local field", { side: "cloud" }, ["tier"]],
    ]) check("withheldFields: " + name, ctx.withheldFields(sided, {}, settings), want);
    // Power's service reports a failure, clears it after success, and loses
    // its status when disabled. Each transition must reach the same field.
    const problems = { schema: { wake: { type: "boolean", label: "Wake", problem: "failure" }, kept: { type: "boolean", label: "Kept" } } };
    for (const [name, values, want] of [
        ["reported failure", { failure: "failed" }, { wake: "failed" }],
        ["successful pass", { failure: "" }, { wake: "" }],
        ["before publish or after disable", {}, { wake: "" }],
        ["unmapped status", { failure: "failed", other: "other failure" }, { wake: "failed" }],
    ]) check("fieldProblems: " + name, ctx.fieldProblems(problems, values), want);
    // Capture declares atomic presets but keeps joined and custom strings.
    const joined = { type: "string", label: "Languages", separator: "+", allowCustom: true, presets: [{ value: "eng" }, { value: "deu" }, { value: "fra" }] };
    for (const [name, patch, value, accepted] of [
        ["joined value", {}, "deu+fra", true],
        ["custom value", {}, "fra+lat+deu", true],
        ["empty selection", {}, "", true],
        ["separator type", { separator: 2 }, "eng", false],
        ["empty separator", { separator: "" }, "eng", false],
        ["separator control character", { separator: "\n" }, "eng", false],
        ["setting type", { type: "number", presets: [{ value: 2 }] }, 2, false],
        ["dynamic choices", { presets: undefined, optionsFrom: "languages" }, "eng", false],
        ["custom values required", { allowCustom: false }, "eng", false],
        ["formatted string", { format: "datetime" }, "eng", false],
        ["empty atom", { presets: [{ value: "", label: "Empty" }] }, "eng", false],
        ["joined atom", { presets: [{ value: "eng+deu" }] }, "eng", false],
        ["duplicate atom", { presets: [{ value: "eng" }, { value: "eng" }] }, "eng", false]
    ]) {
        const raw = Object.assign({}, svc, { capabilities: ["status"], status: { languages: { type: "choices", label: "Languages" } }, settings: { languages: value }, schema: { languages: Object.assign({}, joined, patch) } });
        check("joined presets: " + name, ctx.validateManifest(raw, "/p").ok, accepted);
    }
    // A shipped manifest the judge accepts is refused once a full stop is
    // planted on one of its one-sentence hints, a list item's description.
    const trayFile = path.join(__dirname, "..", "shell", "plugins", "vgs.tray", "manifest.json");
    const trayPlanted = JSON.parse(fs.readFileSync(trayFile, "utf8"));
    trayPlanted.schema.hidden.items.item.description += ".";
    const trayRefusal = ctx.validateManifest(trayPlanted, "/p");
    const trayWant = "schema.hidden.items: schema.item.description must end with no full stop";
    check("validateManifest: a shipped manifest with a full stop planted on a one-sentence hint is refused",
        [ctx.validateManifest(JSON.parse(fs.readFileSync(trayFile, "utf8")), "/p").ok, trayRefusal.ok ? "" : trayRefusal.error.slice(0, trayWant.length)], [true, trayWant]);
    // No status action installs a requirement, a declared one included: the
    // page's Requirements section holds the one install action. The whole
    // refusal names the keys an action takes.
    const installAction = ctx.validateManifest(Object.assign(JSON.parse(JSON.stringify(bar)), { capabilities: ["status"], requirements: [{ command: "x", purpose: "p" }],
        status: { a: { type: "state", label: "A", setup: true, action: { label: "Install", install: ["x"] } } } }), "/p");
    check("validateManifest: an install action is refused", [installAction.ok, installAction.error],
        [false, "status.a.action has unknown key \"install\"; an action takes label, tone, icon, tui, system, undo, dictation, file"]);
    // hyprland.options rows over a service whose schema holds one entry of
    // each kind an option path takes: [name, options, schema patch, want].
    const optionSettings = { sensitivity: 0, rate: 25, tap: true, natural: false, layouts: "us", profile: "flat" };
    const optionSchema = {
        sensitivity: { type: "number", label: "S", min: -1, max: 1, step: 0.05 },
        rate: { type: "number", label: "R", min: 1, max: 100, step: 1 },
        tap: { type: "boolean", label: "T" },
        natural: { type: "boolean", label: "N" },
        layouts: { type: "string", label: "L", presets: [{ value: "us" }, { value: "us,de" }], allowCustom: true },
        profile: { type: "enum", label: "P", options: [{ value: "flat", label: "Flat" }, { value: "adaptive", label: "Adaptive" }] }
    };
    const optionRows = [
        ["an option of each type", { sensitivity: "input.sensitivity", rate: "input.repeat_rate", tap: "input.touchpad.tap_to_click", layouts: "input.kb_layout", profile: "input.accel_profile" }, {}, null],
        ["the touchpad's enabled through its device", { tap: "device.touchpad.enabled" }, {}, null],
        ["an enum for a free string", { profile: "input.kb_options" }, {}, null],
        ["options not an object", ["input.sensitivity"], {}, "hyprland.options must be a non-empty object"],
        ["options empty", {}, {}, "hyprland.options must be a non-empty object"],
        ["a path outside the table", { tap: "input.touchpad.drag_lock" }, {}, "hyprland.options.tap must be one of"],
        ["the hyphenated option name, which Lua refuses", { tap: "input.touchpad.tap-to-click" }, {}, "hyprland.options.tap must be one of"],
        ["a path that is no string", { tap: true }, {}, "hyprland.options.tap must be one of"],
        ["an inherited path", { tap: "constructor" }, {}, "hyprland.options.tap must be one of"],
        ["one path for two settings", { tap: "input.natural_scroll", natural: "input.natural_scroll" }, {}, "hyprland.options.natural sets input.natural_scroll, which another setting sets already"],
        ["a setting with no schema entry", { lefty: "input.left_handed" }, {}, "hyprland.options.lefty names no schema entry \"lefty\""],
        ["a boolean path for a number", { rate: "input.left_handed" }, {}, "hyprland.options.rate needs a boolean schema entry, got number"],
        ["a number path for a boolean", { tap: "input.scroll_factor" }, {}, "hyprland.options.tap needs a number schema entry, got boolean"],
        ["a float without a max", { sensitivity: "input.sensitivity" }, { sensitivity: { type: "number", label: "S", min: -1 } }, "hyprland.options.sensitivity needs min and max within -1 to 1"],
        ["a float below Hyprland's range", { sensitivity: "input.sensitivity" }, { sensitivity: { type: "number", label: "S", min: -2, max: 1 } }, "hyprland.options.sensitivity needs min and max within -1 to 1"],
        ["a float above Hyprland's range", { sensitivity: "input.scroll_factor" }, { sensitivity: { type: "number", label: "S", min: 0, max: 3 } }, "hyprland.options.sensitivity needs min and max within 0 to 2"],
        ["an int with a fractional step", { rate: "input.repeat_rate" }, { rate: { type: "number", label: "R", min: 1, max: 100, step: 0.5 } }, "hyprland.options.rate needs a whole min, max and step"],
        ["an int with a fractional bound", { rate: "input.repeat_delay" }, { rate: { type: "number", label: "R", min: 1.5, max: 100 } }, "hyprland.options.rate needs a whole min, max and step"],
        ["a string for a path with choices", { layouts: "input.accel_profile" }, {}, "hyprland.options.layouts needs an enum schema entry, got string"],
        ["an enum offering a value outside the choices", { profile: "input.accel_profile" }, { profile: { type: "enum", label: "P", options: [{ value: "flat", label: "Flat" }, { value: "custom", label: "Custom" }] } }, "hyprland.options.profile offers \"custom\", not one of adaptive, flat"],
        ["a boolean for a free string", { tap: "input.kb_layout" }, {}, "hyprland.options.tap needs a string or enum schema entry, got boolean"]
    ];
    for (const [name, options, schemaPatch, want] of optionRows) {
        const raw = Object.assign(JSON.parse(JSON.stringify(svc)), { capabilities: ["hyprland"], settings: optionSettings, schema: Object.assign({}, optionSchema, schemaPatch), hyprland: { options: options } });
        const r = ctx.validateManifest(raw, "/p");
        check("hyprland.options: " + name, r.ok ? null : r.error.slice(0, want === null ? 0 : want.length), want);
    }
    check("hyprland.options needs no hyprland capability", ctx.validateManifest(Object.assign({}, svc, { settings: optionSettings, schema: optionSchema, hyprland: { options: { sensitivity: "input.sensitivity" } } }), "/p").ok, true);
    check("hyprland.options setting names are schema setting names", ctx.validateManifest(Object.assign({}, svc, { capabilities: ["hyprland"], settings: Object.assign({}, optionSettings, { "bad\nos.exit()": "us" }), schema: Object.assign({}, optionSchema, { "bad\nos.exit()": { type: "string", label: "Bad", presets: [{ value: "us" }] } }), hyprland: { options: { "bad\nos.exit()": "input.kb_layout" } } }), "/p").error, "hyprland.options.bad\nos.exit() must be a setting name");
    const monitorManifest = Object.assign({}, svc, { capabilities: ["monitors"], settings: { outputs: {} }, hyprland: { monitors: "outputs" } });
    check("hyprland.monitors is judged", ctx.validateManifest(monitorManifest, "/p").ok, true);
    check("hyprland.monitors needs the monitors capability", ctx.validateManifest(Object.assign({}, svc, { settings: { outputs: {} }, hyprland: { monitors: "outputs" } }), "/p").error, "hyprland.monitors needs capability monitors");
    check("hyprland.monitors setting must exist", ctx.validateManifest(Object.assign({}, svc, { capabilities: ["monitors"], settings: {}, hyprland: { monitors: "outputs" } }), "/p").error, "hyprland.monitors names no settings key \"outputs\"");
    check("hyprland.monitors has no schema row", ctx.validateManifest(Object.assign({}, svc, { capabilities: ["monitors"], settings: { outputs: false }, schema: { outputs: { type: "boolean", label: "Outputs" } }, hyprland: { monitors: "outputs" } }), "/p").error, "hyprland.monitors must not name a schema entry");
    check("hyprland.monitors default is judged", ctx.validateManifest(Object.assign({}, svc, { capabilities: ["monitors"], settings: { outputs: { "DP-1\"": { disabled: false } } }, hyprland: { monitors: "outputs" } }), "/p").error, "hyprland.monitors default.DP-1\" identifier refused");
    check("hyprland is a known capability", ctx.validateManifest(Object.assign({}, svc, { capabilities: ["hyprland"] }), "/p").ok, true);
    check("monitors is a known capability", ctx.validateManifest(Object.assign({}, svc, { capabilities: ["monitors"] }), "/p").ok, true);
    check("appearance is a known capability", ctx.validateManifest(Object.assign({}, svc, { capabilities: ["appearance"] }), "/p").ok, true);
    check("appearance is not exclusive", ctx.EXCLUSIVE_CAPABILITIES.indexOf("appearance"), -1);
    check("panes is a known capability on a window", ctx.validateManifest(Object.assign({}, svc, { kinds: ["window"], entryPoints: { window: "Window.qml" }, capabilities: ["panes"] }), "/p").ok, true);
    check("panes needs kind window", ctx.validateManifest(Object.assign({}, svc, { capabilities: ["panes"] }), "/p").error, "capability panes needs kind window");
    // idleStages refusals: [name, idleStages, capabilities, the refusal's
    // path, null for accepted], over a service with a number `after`, from
    // 0, an unbounded number `gap` and a boolean `on`.
    const idleRaw = (idleStages, capabilities) => Object.assign({}, svc, { capabilities: capabilities, idleStages: idleStages,
        settings: { after: 60, gap: 4, on: true },
        schema: { after: { type: "number", label: "After", min: 0 }, gap: { type: "number", label: "Gap" }, on: { type: "boolean", label: "On" } } });
    for (const [name, idleStages, capabilities, want] of [
        ["a stage and its time", { lock: { seconds: "after" } }, ["idle"], null],
        ["a stage with an enabled setting", { screensaver: { seconds: "after", enabled: "on" } }, ["idle"], null],
        ["every stage of the set", { dim: { seconds: "after" }, screensaver: { seconds: "after" }, lock: { seconds: "after" }, displayOff: { seconds: "after" }, sleep: { seconds: "after" } }, ["idle"], null],
        ["a list", [], ["idle"], "idleStages"],
        ["no stage", {}, ["idle"], "idleStages"],
        ["no capability idle", { lock: { seconds: "after" } }, [], "idleStages"],
        ["a stage outside the set", { nap: { seconds: "after" } }, ["idle"], "idleStages.nap"],
        ["an inherited name", { constructor: { seconds: "after" } }, ["idle"], "idleStages.constructor"],
        ["a stage that is no object", { lock: "after" }, ["idle"], "idleStages.lock"],
        ["an unknown key", { lock: { seconds: "after", after: "gap" } }, ["idle"], "idleStages.lock"],
        ["no time", { lock: { enabled: "on" } }, ["idle"], "idleStages.lock.seconds"],
        ["a time with no schema entry", { lock: { seconds: "x" } }, ["idle"], "idleStages.lock.seconds"],
        ["a boolean time", { lock: { seconds: "on" } }, ["idle"], "idleStages.lock.seconds"],
        ["a time with no min", { lock: { seconds: "gap" } }, ["idle"], "idleStages.lock.seconds"],
        ["an enabled setting that is no boolean", { lock: { seconds: "after", enabled: "gap" } }, ["idle"], "idleStages.lock.enabled"],
        ["an enabled setting with no schema entry", { lock: { seconds: "after", enabled: "x" } }, ["idle"], "idleStages.lock.enabled"]
    ]) {
        const r = ctx.validateManifest(idleRaw(idleStages, capabilities), "/p");
        check("idleStages: " + name, r.ok ? null : r.error.slice(0, want.length + 1), want === null ? null : want + " ");
    }
    check("idleStages: a manifest without the key reads none", ctx.validateManifest(svc, "/p").manifest.idleStages, {});
    // The record over plugins that each own the stages given: [name, plugins
    // as [id, { stage: [seconds, enabled] }], the record as [stage, plugin,
    // seconds, before]]. Ids are handed unsorted.
    const stageOwner = (id, stages) => {
        const settings = {}, schema = {}, idleStages = {};
        for (const [stage, [seconds, enabled]] of Object.entries(stages)) {
            settings[stage + "Seconds"] = seconds;
            schema[stage + "Seconds"] = { type: "number", label: stage + " time", min: 0 };
            idleStages[stage] = { seconds: stage + "Seconds" };
            if (enabled === undefined) continue;
            settings[stage + "On"] = enabled;
            schema[stage + "On"] = { type: "boolean", label: stage + " on" };
            idleStages[stage].enabled = stage + "On";
        }
        return ctx.validateManifest(Object.assign({}, svc, { id: id, capabilities: ["idle"], settings: settings, schema: schema, idleStages: idleStages }), "/p").manifest;
    };
    const stageRecord = (plugins, config) => {
        const manifests = Object.create(null);
        for (const [id, stages] of plugins) manifests[id] = stageOwner(id, stages);
        return ctx.idleStages(manifests, plugins.map(p => p[0]), config || { version: 3, plugins: [] });
    };
    const stageRows = record => record.stages.map(s => [s.stage, s.plugin, s.seconds, s.before]);
    for (const [name, plugins, want] of [
        ["the lock before the screensaver", [["acme.lock", { lock: [120] }], ["acme.saver", { screensaver: [300] }]],
            [["screensaver", "acme.saver", 300, []], ["lock", "acme.lock", 120, ["screensaver"]]]],
        ["display off before the dim", [["acme.power", { displayOff: [60] }], ["acme.dim", { dim: [300] }]],
            [["dim", "acme.dim", 300, []], ["displayOff", "acme.power", 60, ["dim"]]]],
        ["a Never stage fires before none and none before it", [["acme.a", { dim: [0], screensaver: [60], lock: [0] }]],
            [["dim", "acme.a", 0, []], ["screensaver", "acme.a", 60, []], ["lock", "acme.a", 0, []]]],
        ["a stage turned off reads Never", [["acme.a", { screensaver: [300, false], lock: [120] }]],
            [["screensaver", "acme.a", 0, []], ["lock", "acme.a", 120, []]]],
        ["a stage turned on reads its time", [["acme.a", { screensaver: [300, true], lock: [120] }]],
            [["screensaver", "acme.a", 300, []], ["lock", "acme.a", 120, ["screensaver"]]]],
        ["two stages at one time fire together", [["acme.a", { dim: [60], screensaver: [60] }]],
            [["dim", "acme.a", 60, []], ["screensaver", "acme.a", 60, []]]],
        ["a late stage before two earlier ones", [["acme.a", { sleep: [100], dim: [300], screensaver: [200] }]],
            [["dim", "acme.a", 300, []], ["screensaver", "acme.a", 200, ["dim"]], ["sleep", "acme.a", 100, ["dim", "screensaver"]]]],
        ["the first by id owns a stage two declare", [["acme.b", { lock: [60] }], ["acme.a", { lock: [600] }]],
            [["lock", "acme.a", 600, []]]]
    ])
        check("idleStages: " + name, stageRows(stageRecord(plugins)), want);
    const contested = stageRecord([["acme.b", { lock: [60] }], ["acme.a", { lock: [600] }]]);
    check("idleStages: the later declarer of a stage is a problem", contested.problems.map(p => p.plugin), ["acme.b"]);
    check("idleStages: the record is frozen", Object.isFrozen(contested.stages) && Object.isFrozen(contested.stages[0]) && Object.isFrozen(contested.stages[0].before), true);
    check("idleStages: a plugin not enabled owns no stage", stageRows(ctx.idleStages({ "acme.a": stageOwner("acme.a", { lock: [60] }) }, [], { version: 3, plugins: [] })), []);
    const unfit = stageRecord([["acme.a", { dim: [60], lock: [120] }]], { version: 3, plugins: [{ id: "acme.a", lockSeconds: "soon" }] });
    check("idleStages: a stored time that does not fit leaves its stage out", stageRows(unfit), [["dim", "acme.a", 60, []]]);
    check("idleStages: a stored time that does not fit is a problem", unfit.problems.map(p => p.plugin), ["acme.a"]);
    // The bundled owners, read from their shipped manifests: their defaults
    // fire in order, and the lock set to Never fires before none.
    const bundledStages = Object.create(null);
    for (const id of ["vgs.displays", "vgs.lock", "vgs.screensaver"])
        bundledStages[id] = ctx.validateManifest(JSON.parse(fs.readFileSync(path.join(PLUGINS_DIR, id, "manifest.json"), "utf8")), "/p").manifest;
    const bundledRows = config => ctx.idleStages(bundledStages, Object.keys(bundledStages), config).stages.map(s => [s.stage, s.plugin, s.setting, s.seconds, s.before]);
    check("idleStages: the bundled defaults read no before", bundledRows({ version: 3, plugins: [] }),
        [["dim", "vgs.displays", "dimAfterSeconds", 120, []], ["screensaver", "vgs.screensaver", "idleSeconds", 150, []], ["lock", "vgs.lock", "idleLockSeconds", 300, []]]);
    check("idleStages: the bundled lock set to Never reads 0", bundledRows({ version: 3, plugins: [{ id: "vgs.lock", idleLockSeconds: 0 }, { id: "vgs.screensaver", idleSeconds: 600 }] }),
        [["dim", "vgs.displays", "dimAfterSeconds", 120, []], ["screensaver", "vgs.screensaver", "idleSeconds", 600, []], ["lock", "vgs.lock", "idleLockSeconds", 0, []]]);
    // The secure cover's judges. Stage rows are [stage, plugin, seconds].
    const coverStages = rows => rows.map(([stage, plugin, seconds]) => ({ stage: stage, plugin: plugin, setting: "s", seconds: seconds, before: [] }));
    const saverAndLock = coverStages([["screensaver", "acme.saver", 150], ["lock", "acme.lock", 300]]);
    for (const [name, stage, owner, onChange, want] of [
        ["the owner holds its stage watch", "lock", "acme.lock", () => {}, ""],
        ["another plugin holds no watch of the stage", "lock", "acme.saver", () => {}, "refused: idle-stage=lock owner=acme.lock"],
        ["a stage no plugin owns is refused", "sleep", "acme.lock", () => {}, "refused: idle-stage=sleep owner=none"],
        ["an unknown stage is refused", "nap", "acme.lock", () => {}, 'refused: idle-stage="nap" want=dim|screensaver|lock|displayOff|sleep'],
        ["a handler that is no function is refused", "lock", "acme.lock", null, "refused: idle-handler=not-a-function"]
    ])
        check("idleStageWatchRefusal: " + name, ctx.idleStageWatchRefusal(saverAndLock, owner, stage, onChange), want);
    for (const [name, request, want] of [
        ["manual", { cause: "manual" }, ""],
        ["sleep", { cause: "sleep" }, ""],
        ["restore", { cause: "restore" }, ""],
        ["idle with a ticket", { cause: "idle", ticket: Object.freeze({}) }, ""],
        ["no request, as a caller of the old route sends", undefined, "refused: lock-request=undefined want=object"],
        ["a bare cause word", "manual", 'refused: lock-request="manual" want=object'],
        ["no cause", {}, "refused: lock-cause=undefined want=idle|manual|sleep|restore"],
        ["an unknown cause", { cause: "later" }, 'refused: lock-cause="later" want=idle|manual|sleep|restore'],
        ["idle without a ticket", { cause: "idle" }, "refused: lock-request=cause want=cause,ticket"],
        ["idle with a null ticket", { cause: "idle", ticket: null }, "refused: lock-ticket=null want=object"],
        ["idle with a string ticket", { cause: "idle", ticket: "t" }, 'refused: lock-ticket="t" want=object'],
        ["manual carrying a ticket", { cause: "manual", ticket: {} }, "refused: lock-request=cause,ticket want=cause"],
        ["an extra key", { cause: "sleep", now: true }, "refused: lock-request=cause,now want=cause"]
    ])
        check("lockRequestRefusal: " + name, ctx.lockRequestRefusal(request), want);
    const coverManifests = { "acme.saver": { kinds: ["service", "cover"] }, "acme.plain": { kinds: ["service"] }, "acme.lock": { kinds: ["service"] } };
    for (const [name, stages, want] of [
        ["the screensaver owner's cover", saverAndLock, "acme.saver"],
        ["a screensaver owner with no cover kind", coverStages([["screensaver", "acme.plain", 150]]), ""],
        ["no screensaver stage", coverStages([["lock", "acme.lock", 300]]), ""],
        ["a stage owner the manifests do not hold", coverStages([["screensaver", "acme.gone", 150]]), ""]
    ])
        check("coverOwner: " + name, ctx.coverOwner(stages, coverManifests), want);
    for (const [name, rows, owner, want] of [
        ["equal positive times", [["screensaver", "acme.saver", 300], ["lock", "acme.lock", 300]], "acme.saver", true],
        ["the screensaver earlier", [["screensaver", "acme.saver", 150], ["lock", "acme.lock", 300]], "acme.saver", false],
        ["the screensaver later", [["screensaver", "acme.saver", 600], ["lock", "acme.lock", 300]], "acme.saver", false],
        ["both at Never", [["screensaver", "acme.saver", 0], ["lock", "acme.lock", 0]], "acme.saver", false],
        ["no cover owner", [["screensaver", "acme.saver", 300], ["lock", "acme.lock", 300]], "", false],
        ["another plugin's screensaver stage", [["screensaver", "acme.other", 300], ["lock", "acme.lock", 300]], "acme.saver", false],
        ["no lock stage", [["screensaver", "acme.saver", 300]], "acme.saver", false]
    ])
        check("coverStartsWithLock: " + name, ctx.coverStartsWithLock(coverStages(rows), owner), want);
    const present = over => ctx.coverPresentAnswer(Object.assign({ caller: "acme.saver", owner: "acme.saver", ticket: "none", built: true, displaysOff: false, locked: false, placement: "none" }, over));
    for (const [name, over, want] of [
        ["a manual start", {}, { answer: "ok", start: true }],
        ["an idle start", { ticket: "valid" }, { answer: "ok", start: true }],
        ["another plugin", { caller: "acme.other" }, { answer: "refused: cover=not-owner", start: false }],
        ["no owner", { owner: "" }, { answer: "refused: cover=not-owner", start: false }],
        ["a revoked ticket", { ticket: "stale" }, { answer: "refused: cover=idle-ticket-stale", start: false }],
        ["a revoked ticket while running", { ticket: "stale", placement: "desktop" }, { answer: "refused: cover=idle-ticket-stale", start: false }],
        ["a second callback while on the desktop", { ticket: "valid", placement: "desktop" }, { answer: "ok", start: false }],
        ["a second callback while held in the lock", { ticket: "valid", placement: "secure", locked: true }, { answer: "ok", start: false }],
        ["no cover instance built", { built: false }, { answer: "refused: cover=not-built", start: false }],
        ["no cover instance built for an idle start", { ticket: "valid", built: false }, { answer: "refused: cover=not-built", start: false }],
        ["the panels off", { displaysOff: true }, { answer: "refused: cover=displays-off", start: false }],
        ["a locked session", { ticket: "valid", locked: true }, { answer: "refused: cover=locked", start: false }]
    ])
        check("coverPresentAnswer: " + name, present(over), want);
    for (const [name, args, want] of [
        ["an idle lock over a desktop cover", ["idle", false, "desktop", false, false, true], "transfer"],
        ["an idle lock at equal times", ["idle", false, "none", true, false, true], "start"],
        ["an idle lock at equal times behind dark panels", ["idle", false, "none", true, true, true], "keep"],
        ["an idle lock at equal times with no cover instance built", ["idle", false, "none", true, false, false], "keep"],
        ["an idle lock at other times", ["idle", false, "none", false, false, true], "keep"],
        ["a late idle request over a held lock", ["idle", true, "none", true, false, true], "keep"],
        ["a late idle request while the cover is in the lock", ["idle", true, "secure", true, false, true], "keep"],
        ["a manual lock over a desktop cover", ["manual", false, "desktop", true, false, true], "dismiss"],
        ["a sleep lock over a cover in the lock", ["sleep", true, "secure", true, false, true], "dismiss"],
        ["a restore over a cover in the lock", ["restore", true, "secure", false, false, true], "dismiss"],
        ["a manual lock with no cover", ["manual", false, "none", true, false, true], "keep"]
    ])
        check("coverOnLock: " + name, ctx.coverOnLock.apply(null, args), want);
    check("cover is a capability and not exclusive", [ctx.CAPABILITIES.indexOf("cover") !== -1, ctx.EXCLUSIVE_CAPABILITIES.indexOf("cover")], [true, -1]);
    // capabilityKinds rows: [name, capabilities, capabilityKinds, want], over
    // a plugin of kinds pane, service and window. A refusal pins the start of
    // the error text, as manifestRows does.
    const kindsRaw = Object.assign({}, svc, { kinds: ["pane", "service", "window"], entryPoints: { pane: "Pane.qml", service: "Service.qml", window: "Window.qml" }, pane: { group: "System", order: 1 } });
    const capabilityKindsRows = [
        ["one kind holds a capability", ["hyprland", "notify"], { hyprland: ["pane"] }, null],
        ["two of three kinds hold a capability", ["hyprland", "notify"], { hyprland: ["pane", "window"], notify: ["service"] }, null],
        ["panes kept to the window", ["panes"], { panes: ["window"] }, null],
        ["not an object", ["hyprland"], [["hyprland", "pane"]], "capabilityKinds must be an object"],
        ["an unknown capability", ["hyprland"], { network: ["pane"] }, "capabilityKinds.network names a capability capabilities does not list"],
        ["a capability capabilities does not list", ["notify"], { hyprland: ["pane"] }, "capabilityKinds.hyprland names a capability capabilities does not list"],
        ["a kind outside kinds", ["hyprland"], { hyprland: ["bar-widget"] }, "capabilityKinds.hyprland names \"bar-widget\", a kind the manifest does not declare"],
        ["a kind that is no kind", ["hyprland"], { hyprland: ["panel "] }, "capabilityKinds.hyprland names \"panel \", a kind the manifest does not declare"],
        ["an empty list", ["hyprland"], { hyprland: [] }, "capabilityKinds.hyprland must be a non-empty list of kinds"],
        ["a kind string, not a list", ["hyprland"], { hyprland: "pane" }, "capabilityKinds.hyprland must be a non-empty list of kinds"],
        ["a kind twice", ["hyprland"], { hyprland: ["pane", "pane"] }, "capabilityKinds.hyprland lists kind pane twice"],
        ["every kind", ["hyprland"], { hyprland: ["window", "pane", "service"] }, "capabilityKinds.hyprland lists every kind; leave it out"],
        ["panes away from the window", ["panes"], { panes: ["service"] }, "capabilityKinds.panes must list kind window"]
    ];
    for (const [name, capabilities, capabilityKinds, want] of capabilityKindsRows) {
        const r = ctx.validateManifest(Object.assign({}, kindsRaw, { capabilities: capabilities, capabilityKinds: capabilityKinds }), "/p");
        check("capabilityKinds: " + name, r.ok ? null : r.error.slice(0, want === null ? 0 : want.length), want);
    }
    // instanceCapabilities rows: [kind, want] over one manifest, in the
    // order capabilities lists them; an undeclared capabilityKinds holds
    // every capability for every kind.
    const perKind = ctx.validateManifest(Object.assign({}, kindsRaw, { capabilities: ["appearance", "compositor", "hyprland", "notify"], capabilityKinds: { hyprland: ["pane"], compositor: ["service", "window"] } }), "/p").manifest;
    check("a normalised manifest carries its capabilityKinds", perKind.capabilityKinds, { hyprland: ["pane"], compositor: ["service", "window"] });
    for (const [kind, want] of [["pane", ["appearance", "hyprland", "notify"]], ["service", ["appearance", "compositor", "notify"]], ["window", ["appearance", "compositor", "notify"]]])
        check("instanceCapabilities: " + kind, ctx.instanceCapabilities(perKind, kind), want);
    const flat = ctx.validateManifest(Object.assign({}, kindsRaw, { capabilities: ["hyprland", "notify"] }), "/p").manifest;
    check("a manifest without capabilityKinds normalises to none", flat.capabilityKinds, {});
    for (const kind of kindsRaw.kinds)
        check("instanceCapabilities without capabilityKinds: " + kind, ctx.instanceCapabilities(flat, kind), ["hyprland", "notify"]);
    const paneOnly = ctx.validateManifest(Object.assign({}, kindsRaw, { capabilities: ["hyprland", "notify"], capabilityKinds: { hyprland: ["pane"] } }), "/p").manifest;
    for (const [kind, want] of [["service", ["notify"]], ["pane", ["hyprland", "notify"]]])
        check("providersFor: a " + kind + " instance holds its kind's capabilities", providersHeld(CAPABILITIES_SOURCE, ctx, paneOnly, kind), { held: want, providers: want });
    check("a normalised manifest carries its options", (() => {
        const m = ctx.validateManifest(Object.assign({}, svc, { capabilities: ["hyprland"], settings: optionSettings, schema: optionSchema, hyprland: { options: { sensitivity: "input.sensitivity" } } }), "/p").manifest;
        return m.hyprland.options;
    })(), { sensitivity: "input.sensitivity" });
    check("a normalised manifest carries its monitor setting", ctx.validateManifest(monitorManifest, "/p").manifest.hyprland.monitors, "outputs");
    check("validateManifest does not alias its input", (() => { const raw = JSON.parse(JSON.stringify(bar)); const m = ctx.validateManifest(raw, "/p").manifest; m.kinds.push("x"); return raw.kinds; })(), ["bar"]);
    check("validateManifest normalizes capabilities and settings", (() => { const m = ctx.validateManifest(bar, "/p").manifest; return [m.capabilities, m.settings, m.defaultSection]; })(), [[], {}, undefined]);
    check("validateManifest normalizes an absent schema to an object", ctx.validateManifest(bar, "/p").manifest.schema, {});
    check("validateManifest normalizes an absent status to an object", ctx.validateManifest(bar, "/p").manifest.status, {});
    check("validateManifest records sourceDir", ctx.validateManifest(bar, "/p").manifest.__sourceDir, "/p");
    check("validateManifest normalizes absent requirements to a list", ctx.validateManifest(bar, "/p").manifest.requirements, []);
    check("validateManifest normalizes an absent systemSteps to a list", ctx.validateManifest(bar, "/p").manifest.systemSteps, []);
    check("validateManifest keeps the declared systemSteps", ctx.validateManifest(Object.assign({}, bar, { capabilities: ["system"], systemSteps: ["i2c-dev", "apple-displays"] }), "/p").manifest.systemSteps, ["i2c-dev", "apple-displays"]);
    check("the system step table is bin/vgshell-system's", ctx.SYSTEM_STEPS, ["apple-displays", "disk-sleep", "i2c-dev", "service-bluetooth", "service-tailscaled", "service-cups", "tailscale-operator", "tailscale-account-add", "greeter", "bandwhich-capture", "reboot-notice", "voxtype-engine", "vgs-quickshell-repository", "wake-sources"]);
    const trafficManifest = ctx.validateManifest(JSON.parse(fs.readFileSync(path.join(__dirname, "../shell/plugins/vgs.traffic/manifest.json"), "utf8")), "/traffic");
    check("traffic declares its judged capture system step", trafficManifest.ok, true);
    if (trafficManifest.ok) {
        const view = ctx.noticeView(trafficManifest.manifest, ["bandwhich"], {}, { commands: ["bandwhich"], required: ["bandwhich"] }, { primary: { id: "dnf", binary: "dnf" }, overlays: [], sources: [] });
        check("stock Fedora has no invented install plan for bandwhich", [view.install, view.rows[0].package, view.rows[0].name, view.rows[0].optional, view.satisfied], [null, null, "bandwhich", true, false]);
    }
    const required = ctx.validateManifest(Object.assign({}, bar, { requirements: [{ command: "gum", purpose: "Dialogs" }, { command: "checkupdates", packages: { pacman: "pacman-contrib" }, optional: true, purpose: "Counts updates" }, { dbus: { bus: "system", name: "org.freedesktop.UPower.PowerProfiles", label: "Power profiles service" }, packages: { dnf: "ppd-service" }, purpose: "Switches the power profile" }] }), "/p").manifest;
    check("validateManifest gives every requirement its packages and optional", required.requirements,
        [{ name: "gum", title: "gum", bus: null, packages: {}, optional: false, purpose: "Dialogs", floor: null, onRequest: false }, { name: "checkupdates", title: "checkupdates", bus: null, packages: { pacman: "pacman-contrib" }, optional: true, purpose: "Counts updates", floor: null, onRequest: false }, { name: "org.freedesktop.UPower.PowerProfiles", title: "Power profiles service", bus: "system", packages: { dnf: "ppd-service" }, optional: false, purpose: "Switches the power profile", floor: null, onRequest: false }]);
    check("validateManifest carries an on-request install as a required entry", ctx.validateManifest(Object.assign({}, bar, { requirements: [{ command: "gum", packages: { aur: "gum-bin" }, install: "on-request", purpose: "Dialogs" }] }), "/p").manifest.requirements.map(r => [r.name, r.optional, r.onRequest]), [["gum", false, true]]);
    check("requirementRows: a command the scan did not find is missing, every other present", ctx.requirementRows(required, ["checkupdates", "vsys"], {}).map(r => [r.name, r.bus, r.state]), [["gum", null, "present"], ["checkupdates", null, "missing"], ["org.freedesktop.UPower.PowerProfiles", "system", "present"]]);
    check("requirementRows: a bus name the scan did not find is missing", ctx.requirementRows(required, ["org.freedesktop.UPower.PowerProfiles"], {}).map(r => [r.name, r.state]), [["gum", "present"], ["checkupdates", "present"], ["org.freedesktop.UPower.PowerProfiles", "missing"]]);
    check("requirementRows: every requirement is present when the scan missed none", ctx.requirementRows(required, [], {}).map(r => r.state), ["present", "present", "present"]);
    check("requirementRows does not alias the manifest", (() => { ctx.requirementRows(required, [], {})[1].packages.apt = "x"; return required.requirements[1].packages; })(), { pacman: "pacman-contrib" });
    // A floor: vgs-tool needs 1.10.1, vgs-free declares none. Each row is
    // [name, the scan's missing names, the line it read for vgs-tool or
    // undefined for no read, vgs-tool's state].
    const floored = ctx.validateManifest(Object.assign({}, bar, { requirements: [{ command: "vgs-tool", packages: { pacman: "tool" }, floor: "1.10.1", purpose: "Runs" }, { command: "vgs-free", optional: true, purpose: "No floor" }] }), "/p").manifest;
    check("validateManifest keeps a requirement's floor, and null without one", floored.requirements.map(r => r.floor), ["1.10.1", null]);
    const floorRows = [
        ["a lower minor is outdated, read as a number", [], "vgs-tool 1.9.12", "outdated"],
        ["a lower major is outdated", [], "0.99.99", "outdated"],
        ["a lower patch is outdated", [], "1.10.0", "outdated"],
        ["the floor itself is present", [], "1.10.1", "present"],
        ["a higher patch is present", [], "1.10.2", "present"],
        ["a higher minor with a lower patch is present", [], "1.11.0", "present"],
        ["a higher major with a lower minor is present", [], "vgs-tool 2.0.0", "present"],
        ["a name before the version and a mark after it are read past", [], "tool v1.10.1-rc1 (linux)", "present"],
        ["a line with no version says nothing", [], "unknown option --version", "present"],
        ["a read that failed says nothing", [], null, "present"],
        ["a command the scan read no version of is present", [], undefined, "present"],
        ["a missing command is missing whatever was read", ["vgs-tool"], "1.0.0", "missing"]
    ];
    for (const [name, missing, line, want] of floorRows) {
        const versions = line === undefined ? {} : { "vgs-tool": line, "vgs-free": "0.0.1" };
        check("requirementRows: " + name, ctx.requirementRows(floored, missing, versions).map(r => r.state), [want, "present"]);
    }
    // noticeRequest by the state of vgs-tool: [name, missing, line, trigger,
    // commands, want as [answer, commands, required]], then what the notice
    // shows on a pacman system.
    const pacmanOnly = { primary: { id: "pacman", binary: "pacman" }, overlays: [], sources: [] };
    const floorNotices = [
        ["a request lists and requires an outdated command", [], "1.9.12", "requested", undefined, ["ok", ["vgs-tool"], ["vgs-tool"]]],
        ["a choice of an outdated command raises its notice", [], "1.9.12", "chosen", ["vgs-tool"], ["ok", ["vgs-tool"], ["vgs-tool"]]],
        ["a command at its floor is satisfied", [], "1.10.1", "chosen", ["vgs-tool"], ["satisfied", [], []]],
        ["a command above its floor is satisfied", [], "2.0.0", "installed", undefined, ["satisfied", [], []]],
        ["a missing command is listed as before", ["vgs-tool"], undefined, "chosen", ["vgs-tool"], ["ok", ["vgs-tool"], ["vgs-tool"]]]
    ];
    for (const [name, missing, line, trigger, commands, want] of floorNotices) {
        const r = ctx.noticeRequest(floored, missing, line === undefined ? {} : { "vgs-tool": line }, trigger, commands);
        check("noticeRequest: " + name, [r.answer, r.commands, r.required], want);
    }
    const toolNotice = { commands: ["vgs-tool"], required: ["vgs-tool"] };
    const shows = (missing, versions) => { const v = ctx.noticeView(floored, missing, versions, toolNotice, pacmanOnly); return [v.satisfied, v.rows.map(r => [r.name, r.state]), v.drawn.map(g => [g.chip, g.update]), v.run === null ? null : [v.run.action, v.run.args]]; };
    check("noticeView: an outdated command is offered its update, and no install", shows([], { "vgs-tool": "1.9.12" }), [false, [["vgs-tool", "outdated"]], [["tool", true]], ["update", ["tool"]]]);
    check("noticeView: a missing command is offered its install, and no update", shows(["vgs-tool"], {}), [false, [["vgs-tool", "missing"]], [["tool", false]], ["install", ["tool"]]]);
    check("noticeView: a command at its floor satisfies the notice", shows([], { "vgs-tool": "1.10.1" }), [true, [], [], null]);
    check("noticeSettle: an outdated command keeps its notice, and its floor closes it",
        [{ "vgs-tool": "1.9.12" }, { "vgs-tool": "1.10.1" }].map(versions => ctx.noticeSettle([Object.assign({ id: "vgs.bar" }, toolNotice)], { "vgs.bar": floored }, {}, versions, "").length), [1, 0]);
    // versionCommands: the core's and the enabled plugins' floored commands
    // the scan found, each once; a disabled plugin's and a missing one stay out.
    const owners = { core: ctx.coreOwner([{ name: "git", bus: null, packages: {}, optional: false, purpose: "p", floor: "2.0.0" }, { name: "gum", bus: null, packages: {}, optional: false, purpose: "p", floor: null }]),
        "acme.on": { requirements: [{ name: "vgs-tool", floor: "1.0.0" }, { name: "git", floor: "2.1.0" }, { name: "vgs-gone", floor: "1.0.0" }] }, "acme.off": { requirements: [{ name: "vgs-off", floor: "1.0.0" }] } };
    check("versionCommands reads the floored commands of the core and the enabled plugins", ctx.versionCommands(owners, { "acme.on": ["vgs-gone"] }, ["acme.on"]), ["git", "vgs-tool"]);
    // versionsRead: [name, completion, stdout, want].
    const readRows = [
        ["an answer is each command's line or null", { code: 0, status: 0 }, "{\"pi\":\"1.1.0\",\"gone\":null}", { ok: true, versions: { pi: "1.1.0", gone: null } }],
        ["a run that never started", null, "", { ok: false, line: "plugins: versions=unstarted" }],
        ["a run that failed", { code: 2, status: 0 }, "{}", { ok: false, line: "plugins: versions=failed exit=2 status=0" }],
        ["a run that crashed", { code: 0, status: 1 }, "{}", { ok: false, line: "plugins: versions=failed exit=0 status=1" }],
        ["output that is no JSON", { code: 0, status: 0 }, "pi 1.1.0", { ok: false, line: "plugins: versions=unparseable" }],
        ["a list", { code: 0, status: 0 }, "[]", { ok: false, line: "plugins: versions=malformed" }],
        ["a value that is no line", { code: 0, status: 0 }, "{\"pi\":1}", { ok: false, line: "plugins: versions=malformed" }]
    ];
    for (const [name, completion, stdout, want] of readRows)
        check("versionsRead: " + name, ctx.versionsRead(completion, stdout), want);
    check("the core's config/requirements.json passes the requirements judge", ctx.requirementsError(JSON.parse(fs.readFileSync(CORE_REQUIREMENTS, "utf8"))), "");

    // configError rows: [name, config, want]. A refusal row pins the start of
    // the error text.
    const configRows = [
        ["an empty object passes", {}, ""],
        ["every key of the table, well formed, passes", { version: 3, bar: { id: "vgs.bar", layout: { left: [{ id: "a.b" }], center: [], right: [] } }, plugins: [{ id: "a.c", x: 1 }], disabledPlugins: ["a.d"], disabledTargets: ["foot"] }, ""],
        ["a key outside the table is carried", { unrelated: { any: 1 } }, ""],
        ["a list is not a config", [], "config must be an object"],
        ["null is not a config", null, "config must be an object"],
        ["version 1", { version: 1 }, "version must be 3"],
        ["version 4", { version: 4 }, "version must be 3"],
        ["plugins not a list", { plugins: {} }, "plugins must be a list"],
        ["a plugins row without an id", { plugins: [{ id: "a.b" }, { x: 1 }] }, "plugins.1 must be an object with a string id"],
        ["a plugins row that is a string", { plugins: ["a.b"] }, "plugins.0 must be an object with a string id"],
        ["disabledPlugins not a list", { disabledPlugins: "a.b" }, "disabledPlugins must be a list"],
        ["a disabledPlugins entry that is not a string", { disabledPlugins: ["a.b", 1] }, "disabledPlugins.1 must be a string"],
        ["disabledTargets not a list", { disabledTargets: "foot" }, "disabledTargets must be a list"],
        ["a disabledTargets entry that is not a string", { disabledTargets: ["foot", null] }, "disabledTargets.1 must be a string"],
        ["bar not an object", { bar: "vgs.bar" }, "bar must be an object"],
        ["bar.id not a string", { bar: { id: 1 } }, "bar.id must be a string"],
        ["bar.layout not an object", { bar: { layout: [] } }, "bar.layout must be an object"],
        ["a section not a list", { bar: { layout: { left: { id: "a.b" } } } }, "bar.layout.left must be a list"],
        ["a layout row without an id", { bar: { layout: { center: [{ format: "x" }] } } }, "bar.layout.center.0 must be an object with a string id"],
        ["a layout row with a numeric id", { bar: { layout: { right: [{ id: 3 }] } } }, "bar.layout.right.0 must be an object with a string id"],
        ["a layout row with a setting beside its id", { bar: { layout: { left: [{ id: "a.b" }], center: [{ id: "a.c" }, { id: "a.d", format: "HH:mm" }] } } }, "bar.layout.center.1 has key \"format\" beside its id"],
        ["a layout row with a plugins row's keys beside its id", { bar: { layout: { right: [{ id: "a.b", keys: {} }] } } }, "bar.layout.right.0 has key \"keys\" beside its id"],
        ["packages with each elevation command passes", { packages: { elevate: "run0" } }, ""],
        ["packages without elevate passes", { packages: {} }, ""],
        ["packages not an object", { packages: ["sudo"] }, "packages must be an object"],
        ["an elevate outside sudo, doas and run0", { packages: { elevate: "pkexec" } }, "packages.elevate must be one of sudo, doas, run0, got \"pkexec\""],
        ["an elevate that is not a string", { packages: { elevate: true } }, "packages.elevate must be one of sudo, doas, run0, got true"],
        ["welcome key lines pass", { welcome: { keys: [{ id: "a.b", shortcut: "toggle", text: "shows the keys." }] } }, ""],
        ["welcome with no key lines passes", { welcome: { keys: [] } }, ""],
        ["welcome not an object", { welcome: [] }, "welcome must be an object"],
        ["welcome without keys", { welcome: {} }, "welcome.keys must be a list"],
        ["a welcome key line without an id", { welcome: { keys: [{ shortcut: "toggle", text: "t" }] } }, "welcome.keys.0 must be an object with a string id"],
        ["a welcome key line without a shortcut", { welcome: { keys: [{ id: "a.b", text: "t" }] } }, "welcome.keys.0 must hold a string shortcut and a non-empty string text"],
        ["a welcome key line with empty text", { welcome: { keys: [{ id: "a.b", shortcut: "toggle", text: "" }] } }, "welcome.keys.0 must hold a string shortcut and a non-empty string text"],
        ["a manager id passes", { manager: { id: "a.b" } }, ""],
        ["manager not an object", { manager: "a.b" }, "manager must be an object"],
        ["manager without an id", { manager: {} }, "manager.id must be a string"],
        ["a manager id that is not a string", { manager: { id: 3 } }, "manager.id must be a string"],
        ["a shortcut key list passes", { plugins: [{ id: "a.b", keys: { tap: ["code:108", "code:105"] } }] }, ""],
        ["an empty shortcut key list is refused", { plugins: [{ id: "a.b", keys: { tap: [] } }] }, "plugins.0.keys.tap must not be an empty list"],
        ["a bad shortcut key list entry names its index", { plugins: [{ id: "a.b", keys: { tap: ["code:108", "SUPER+"] } }] }, "plugins.0.keys.tap.1 has an empty part"],
        ["a repeated shortcut key list entry is refused", { plugins: [{ id: "a.b", keys: { tap: ["CODE:00108", "code:108"] } }] }, "plugins.0.keys.tap.1 repeats code:108"],
        // Members are judged where the theme resolves them, so a bad one
        // blocks no other key of the file.
        ["appearance values pass", { appearance: { windowRadius: 12, motion: false } }, ""],
        ["an appearance member the theme refuses passes the file", { appearance: { windowRadius: 99 } }, ""],
        ["appearance not an object", { appearance: [12] }, "appearance must be an object"],
        ["appearance null", { appearance: null }, "appearance must be an object"],
    ];
    for (const [name, config, want] of configRows) {
        const got = configLogic.configError(config);
        check("configError: " + name, got.slice(0, want === "" ? got.length : want.length), want);
    }
    // The shipped file itself: Config.ready waits for a shipped file this judge
    // passes, so a refused config/shell.json leaves every screen without a bar.
    check("configError: the repository's config/shell.json passes", configLogic.configError(JSON.parse(require("fs").readFileSync(path.join(__dirname, "..", "config", "shell.json"), "utf8"))), "");

    // migrateConfig rows: [name, user file, want file, want migrated, the
    // judge's verdict on the result]. A version 1 file's layout entries
    // keep their ids alone, and every other key moves into the plugins row
    // of its id, where the row's own value wins. No row reads a manifest, so
    // a plugin that is not installed moves the same way.
    const v1 = (layout, rest) => Object.assign({ version: 1, bar: { id: "vgs.bar", layout: layout } }, rest || {});
    const v2 = (layout, rest) => Object.assign({ version: 3, bar: { id: "vgs.bar", layout: layout } }, rest || {});
    const migrateRows = [
        ["a key the row lacks moves into the row",
            v1({ left: [], center: [{ id: "a.b", format: "HH:mm" }], right: [] }, { plugins: [{ id: "a.b", other: 1 }] }),
            v2({ left: [], center: [{ id: "a.b" }], right: [] }, { plugins: [{ id: "a.b", other: 1, format: "HH:mm" }] }), true, ""],
        ["the row's value wins over the entry's",
            v1({ left: [{ id: "a.b", format: "entry", size: 3 }], center: [], right: [] }, { plugins: [{ id: "a.b", format: "row" }] }),
            v2({ left: [{ id: "a.b" }], center: [], right: [] }, { plugins: [{ id: "a.b", format: "row", size: 3 }] }), true, ""],
        ["a row the file lacks is appended",
            v1({ right: [{ id: "a.b", on: true }] }, { plugins: [{ id: "z.z" }] }),
            v2({ right: [{ id: "a.b" }] }, { plugins: [{ id: "z.z" }, { id: "a.b", on: true }] }), true, ""],
        ["a file with no plugins key gains the row",
            v1({ right: [{ id: "a.b", on: true }] }),
            v2({ right: [{ id: "a.b" }] }, { plugins: [{ id: "a.b", on: true }] }), true, ""],
        ["of two entries with one id, the first in section order wins",
            v1({ right: [{ id: "a.b", k: "right" }], left: [{ id: "a.b", k: "left", only: "left" }] }),
            v2({ right: [{ id: "a.b" }], left: [{ id: "a.b" }] }, { plugins: [{ id: "a.b", k: "left", only: "left" }] }), true, ""],
        ["of two entries with one id in one section, the first wins",
            v1({ center: [{ id: "a.b", k: "first" }, { id: "c.d" }, { id: "a.b", k: "second", later: 2 }] }),
            v2({ center: [{ id: "a.b" }, { id: "c.d" }, { id: "a.b" }] }, { plugins: [{ id: "a.b", k: "first", later: 2 }] }), true, ""],
        ["every section moves, each entry into its own row",
            v1({ left: [{ id: "l.l", a: 1 }], center: [{ id: "c.c", b: 2 }], right: [{ id: "r.r", c: [3] }] }),
            v2({ left: [{ id: "l.l" }], center: [{ id: "c.c" }], right: [{ id: "r.r" }] }, { plugins: [{ id: "l.l", a: 1 }, { id: "c.c", b: 2 }, { id: "r.r", c: [3] }] }), true, ""],
        ["a plugin that is not installed moves the same way, keys included",
            v1({ right: [{ id: "gone.plugin", keys: { toggle: "SUPER+G" }, mode: "x" }] }),
            v2({ right: [{ id: "gone.plugin" }] }, { plugins: [{ id: "gone.plugin", keys: { toggle: "SUPER+G" }, mode: "x" }] }), true, ""],
        ["every other key stays as it was",
            v1({ left: [{ id: "a.b", n: 1 }] }, { disabledPlugins: ["c.d"], unrelated: { keep: true }, appearance: { motion: false } }),
            v2({ left: [{ id: "a.b" }] }, { disabledPlugins: ["c.d"], unrelated: { keep: true }, appearance: { motion: false }, plugins: [{ id: "a.b", n: 1 }] }), true, ""],
        ["a version 1 file with nothing to move takes version 2",
            { version: 1, plugins: [{ id: "a.b", x: 1 }] }, { version: 3, plugins: [{ id: "a.b", x: 1 }] }, true, ""],
        ["a version 1 file with no bar key moves nothing",
            { version: 1, disabledPlugins: [] }, { version: 3, disabledPlugins: [] }, true, ""],
        ["an unversioned file with a key in an entry is migrated",
            { bar: { layout: { right: [{ id: "a.b", on: false }] } } }, { bar: { layout: { right: [{ id: "a.b" }] } }, plugins: [{ id: "a.b", on: false }], version: 3 }, true, ""],
        ["an unversioned file with nothing to move is left as it is",
            { bar: { layout: { right: [{ id: "a.b" }] } } }, { bar: { layout: { right: [{ id: "a.b" }] } } }, false, ""],
        ["a current file is left as it is",
            v2({ right: [{ id: "a.b" }] }, { plugins: [{ id: "a.b", on: true }] }), v2({ right: [{ id: "a.b" }] }, { plugins: [{ id: "a.b", on: true }] }), false, ""],
        ["a current file with a key in an entry is left for the judge",
            v2({ right: [{ id: "a.b", on: true }] }), v2({ right: [{ id: "a.b", on: true }] }), false, "bar.layout.right.0 has key \"on\" beside its id; a setting belongs in its plugins[] row"],
        ["version 2 does not repeat the layout conversion",
            { version: 2, bar: { layout: { right: [{ id: "a.b", on: true }] } } }, { version: 3, bar: { layout: { right: [{ id: "a.b", on: true }] } } }, true, "bar.layout.right.0 has key \"on\" beside its id; a setting belongs in its plugins[] row"],
        ["a later version is left for the judge",
            { version: 4, bar: { layout: { right: [{ id: "a.b", on: true }] } } }, { version: 4, bar: { layout: { right: [{ id: "a.b", on: true }] } } }, false, "version must be 3, got 4"],
        ["a version 1 entry that is no object is left for the judge",
            v1({ center: ["a.b", { id: "c.d", k: 1 }] }), v2({ center: ["a.b", { id: "c.d" }] }, { plugins: [{ id: "c.d", k: 1 }] }), true, "bar.layout.center.0 must be an object with a string id"],
        ["a version 1 plugins key that is no list is left for the judge",
            v1({ right: [{ id: "a.b", on: true }] }, { plugins: {} }), v2({ right: [{ id: "a.b", on: true }] }, { plugins: {} }), true, "plugins must be a list"],
        ["a list is left for the judge", [], [], false, "config must be an object"],
    ];
    for (const [name, user, want, migrated, verdict] of migrateRows) {
        const before = JSON.stringify(user);
        const got = configLogic.migrateConfig(user, "acme.updates");
        check("migrateConfig: " + name, got, { config: want, migrated: migrated });
        check("migrateConfig leaves its input: " + name, JSON.stringify(user), before);
        check("migrateConfig result judged: " + name, configLogic.configError(got.config), verdict);
    }

    const source = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "config", "shell.json"))).packageReviewSettingsSource;
    check("package review migration context is retained", typeof source === "string" && source !== "", true);
    const reviewRows = [
        ["stored on", { reviewThirdParty: true }, {}, { enabled: true }],
        ["stored off", { reviewThirdParty: false }, {}, { enabled: false }],
        ["absent", {}, {}, {}],
        ["destination false", { reviewThirdParty: true }, { enabled: false }, { enabled: false }],
        ["destination true", { reviewThirdParty: false }, { enabled: true }, { enabled: true }],
        ["empty destination strings", { reviewAgent: "codex", reviewCommand: "codex custom" }, { agent: "", command: "" }, { agent: "", command: "" }],
        ["mixed fields", { reviewThirdParty: false, reviewAgent: "unavailable", reviewCommand: "other --arg" }, { command: "" }, { command: "", enabled: false, agent: "unavailable" }],
        ["old only", { reviewThirdParty: true, reviewAgent: "missing", reviewCommand: "missing --arg" }, {}, { enabled: true, agent: "missing", command: "missing --arg" }],
        ["new only", {}, { agent: "codex", command: "" }, { agent: "codex", command: "" }],
    ];
    for (const version of [undefined, 1, 2]) {
        for (const [name, old, destination, expected] of reviewRows) {
            const user = { plugins: [{ id: source, keep: false, ...old }], disabledPlugins: [source], packages: { elevate: "doas", review: destination }, unrelated: { keep: true } };
            if (version !== undefined) user.version = version;
            if (version === 1) user.bar = { layout: { right: [{ id: source, fromLayout: 4 }] } };
            const before = JSON.stringify(user);
            const result = configLogic.migrateConfig(user, source);
            check("review transfer: " + version + " " + name, result.config.packages.review, expected);
            check("review transfer source removed: " + version + " " + name, result.config.plugins[0], version === 1 ? { id: source, keep: false, fromLayout: 4 } : { id: source, keep: false });
            check("review transfer preserves user input: " + version + " " + name, JSON.stringify(user), before);
            check("review transfer preserves unrelated: " + version + " " + name, [result.config.packages.elevate, result.config.disabledPlugins, result.config.unrelated], ["doas", [source], { keep: true }]);
            check("review transfer judged: " + version + " " + name, configLogic.configError(result.config), "");
            const edited = configLogic.withPackageReview(result.config, result.config.packages.review);
            check("unchanged editor preserves preference presence: " + version + " " + name, Object.hasOwn(edited.config.packages.review, "enabled"), Object.hasOwn(expected, "enabled"));
        }
        for (const field of ["reviewThirdParty", "reviewAgent", "reviewCommand"]) {
            const user = { version, plugins: [{ id: source, [field]: null }] };
            const result = configLogic.migrateConfig(user, source);
            check("invalid old selection refuses: " + version + " " + field, typeof result.error === "string" && result.error !== "", true);
            check("invalid old selection retained: " + version + " " + field, result.config, user);
        }
        const absent = configLogic.migrateConfig({ version, unrelated: 1 }, source).config;
        check("absent plugin creates no review setting: " + version, Object.hasOwn(absent, "packages"), false);
    }
    const redirected = configLogic.migrateConfig({ version: 2, packageReviewSettingsSource: "other.plugin", plugins: [
        { id: source, reviewThirdParty: false, reviewAgent: "codex" },
        { id: "other.plugin", reviewThirdParty: true }
    ] }, source);
    check("review transfer ignores user source override", redirected.config.packages.review, { enabled: false, agent: "codex" });
    check("review transfer leaves unrelated plugin fields", redirected.config.plugins[1], { id: "other.plugin", reviewThirdParty: true });
    for (const version of [undefined, 1]) {
        const movedLayout = configLogic.migrateConfig({ version, bar: { layout: { right: [{ id: source, reviewThirdParty: false, reviewAgent: "codex", keep: 9 }] } } }, source);
        check("review transfer consumes retained layout converter " + version, movedLayout.config.packages.review, { enabled: false, agent: "codex" });
        check("review transfer retains unrelated moved layout key " + version, movedLayout.config.plugins[0], { id: source, keep: 9 });
        check("review transfer removes layout fields " + version, movedLayout.config.bar.layout.right, [{ id: source }]);
    }
    for (const bad of [null, [], { enabled: null }, { enabled: "false" }, { agent: false }, { command: [] }, { extra: 1 }]) {
        check("invalid review editor refused: " + JSON.stringify(bad), configLogic.withPackageReview(null, bad).ok, false);
        check("invalid review config refused: " + JSON.stringify(bad), configLogic.configError({ packages: { review: bad } }) !== "", true);
    }

    // formerIdClaims rows: [name, manifests in scan order, { renames,
    // ignored }]. A manifest whose directory is under /bundled/ is bundled,
    // any other installed. Only a bundled claim renames; an installed
    // manifest's claims are left out once per manifest, a claim of a scanned
    // plugin's id is left out, and of two bundled claims of one former id the
    // first in scan order wins. No claim refuses its manifest.
    const declaring = (id, formerIds, dir) => ctx.validateManifest({ schemaVersion: 1, id: id, name: "N", version: "1", author: "a", description: "d", kinds: ["service"], entryPoints: { service: "S.qml" }, formerIds: formerIds }, dir === undefined ? "/user/" + id : dir).manifest;
    const bundledDeclaring = (id, formerIds) => declaring(id, formerIds, "/bundled/" + id);
    const plainAt = (id, dir) => ctx.validateManifest({ schemaVersion: 1, id: id, name: "N", version: "1", author: "a", description: "d", kinds: ["service"], entryPoints: { service: "S.qml" } }, dir).manifest;
    const plain = plainAt("acme.plain", "/user/acme.plain");
    const scanOrder = list => { const map = Object.create(null); list.forEach(m => { map[m.id] = m; }); return map; };
    const claimSource = m => m.__sourceDir.indexOf("/bundled/") === 0 ? "bundled" : "installed";
    for (const [name, manifests, want] of [
        ["each bundled former id maps to its declaring plugin", [bundledDeclaring("acme.new", ["acme.old", "acme.older"]), plain], { renames: { "acme.old": "acme.new", "acme.older": "acme.new" }, ignored: [] }],
        ["an installed manifest's former ids rename nothing and are left out once", [declaring("acme.new", ["acme.old", "acme.older"]), plain],
            { renames: {}, ignored: [{ id: "acme.new", reason: "installed", formerIds: ["acme.old", "acme.older"] }] }],
        ["the first bundled claim of a former id in scan order wins", [bundledDeclaring("acme.first", ["acme.old"]), bundledDeclaring("acme.second", ["acme.old", "acme.other"])],
            { renames: { "acme.old": "acme.first", "acme.other": "acme.second" }, ignored: [{ id: "acme.second", reason: "claimed", formerIds: ["acme.old"] }] }],
        ["a bundled claim of an installed plugin's live id is left out", [plain, bundledDeclaring("acme.new", ["acme.plain", "acme.old"])],
            { renames: { "acme.old": "acme.new" }, ignored: [{ id: "acme.new", reason: "scanned", formerIds: ["acme.plain"] }] }],
        ["a scan with no declaration renames nothing", [plain, plainAt("acme.shipped", "/bundled/acme.shipped")], { renames: {}, ignored: [] }],
        ["an empty scan renames nothing", [], { renames: {}, ignored: [] }],
    ])
        check("formerIdClaims: " + name, ctx.formerIdClaims(scanOrder(manifests), claimSource), Object.assign({}, want, { splits: [] }));
    // A plugin the user removed leaves its plugins[] row; an installed
    // plugin that names that id in formerIds takes no rename, so the opt-in
    // `plugin add` asks for still holds and the plugin stays off.
    {
        const installed = declaring("acme.drive", ["acme.foo"]);
        const leftover = { version: 3, plugins: [{ id: "acme.foo", x: 1 }] };
        const claims = ctx.formerIdClaims(scanOrder([installed]), claimSource);
        const renamed = configLogic.renamePlugins(leftover, claims.renames);
        check("formerIdClaims: an installed claim of a leftover row renames nothing", renamed, { config: leftover, renamed: false });
        check("formerIdClaims: an installed plugin claiming a leftover row stays off", ctx.isEnabled(renamed.config, installed, "vgs.bar"), false);
    }

    // A source may still ship: splits copy only bundled declarations, and
    // the ignored record gives Registry one log for an installed claim.
    const splitManifest = Object.assign({}, plain, { id: "acme.split", splitFrom: "acme.plain", settings: { keep: false, count: 1 } });
    for (const source of ["bundled", "installed"]) {
        const claims = ctx.formerIdClaims(scanOrder([plain, splitManifest]), () => source);
        check("split claims: " + source, claims, source === "bundled"
            ? { renames: {}, ignored: [], splits: [{ from: "acme.plain", to: "acme.split", keys: ["keep", "count"] }] }
            : { renames: {}, ignored: [{ id: "acme.split", reason: "installed", formerIds: [], splitFrom: "acme.plain" }], splits: [] });
    }
    const splits = [{ from: "acme.source", to: "acme.split", keys: ["keep", "count"] }];
    const sourceRow = { id: "acme.source", keep: false, count: 0, retired: 9, keys: { toggle: "SUPER+S" } };
    const splitRows = [
        ["no source reference still records the split", { version: 3 }, { version: 3, plugins: [{ id: "acme.split" }] }],
        ["source settings copy only declared keys, including falsy values", { plugins: [sourceRow] }, { plugins: [sourceRow, { id: "acme.split", keep: false, count: 0 }] }],
        ["a disable alone also gains the marker", { disabledPlugins: ["acme.source"] }, { disabledPlugins: ["acme.source", "acme.split"], plugins: [{ id: "acme.split" }] }],
        ["every placement copies immediately before its source", { bar: { layout: { left: [{ id: "acme.source" }], center: [{ id: "acme.other" }, { id: "acme.source" }], right: [{ id: "acme.source" }, { id: "acme.source" }] } } }, { bar: { layout: { left: [{ id: "acme.split" }, { id: "acme.source" }], center: [{ id: "acme.other" }, { id: "acme.split" }, { id: "acme.source" }], right: [{ id: "acme.split" }, { id: "acme.source" }, { id: "acme.split" }, { id: "acme.source" }] } }, plugins: [{ id: "acme.split" }] }],
        ...[{ plugins: [{ id: "acme.split", keep: true }] }, { disabledPlugins: ["acme.split"] }, ...["left", "center", "right"].map(section => ({ bar: { layout: { [section]: [{ id: "acme.split" }] } } }))].map(user => ["target already named " + JSON.stringify(user), user, user]),
    ];
    for (const [name, user, want] of splitRows) {
        const before = JSON.stringify(user);
        const result = configLogic.splitPlugins(user, splits);
        check("splitPlugins: " + name, result.config, want);
        check("splitPlugins leaves input: " + name, JSON.stringify(user), before);
        check("splitPlugins repeated read: " + name, configLogic.splitPlugins(result.config, splits), { config: want, split: false });
    }
    const splitTarget = Object.assign({}, splitManifest, { id: "acme.split" });
    const copiedDisable = configLogic.splitPlugins({ disabledPlugins: ["acme.source"] }, splits).config;
    const enabledSplit = ctx.withEnabled(copiedDisable, splitTarget, true, copiedDisable);
    check("splitPlugins: enabling the target survives a re-read", configLogic.splitPlugins(enabledSplit, splits).config.disabledPlugins, ["acme.source"]);
    const firstWrite = ctx.withEnabled(null, Object.assign({}, plain, { id: "acme.source" }), false, {});
    const marked = configLogic.splitPlugins(firstWrite, splits, true).config;
    check("splitPlugins: missing file then source disable survives restart", configLogic.splitPlugins(marked, splits).config, { version: 3, disabledPlugins: ["acme.source"], plugins: [{ id: "acme.split" }] });

    // renamePlugins rows: [name, user file, rename map, want file, want
    // renamed]. A plugins[] row, a disabledPlugins entry and a layout entry
    // in each section take the new id; every other key, and an id the map
    // does not hold, stays as it is.
    const driveRenames = { "vgs.cloud-sync": "vgs.google-drive" };
    const renameRows = [
        ["vgs.cloud-sync enabled, disabled and placed becomes vgs.google-drive in the same places",
            v2({ left: [{ id: "a.b" }], center: [], right: [{ id: "c.d" }, { id: "vgs.cloud-sync" }] }, { plugins: [{ id: "a.b" }, { id: "vgs.cloud-sync", x: 1 }], disabledPlugins: ["c.d", "vgs.cloud-sync"] }), driveRenames,
            v2({ left: [{ id: "a.b" }], center: [], right: [{ id: "c.d" }, { id: "vgs.google-drive" }] }, { plugins: [{ id: "a.b" }, { id: "vgs.google-drive", x: 1 }], disabledPlugins: ["c.d", "vgs.google-drive"] }), true],
        ["a former id placed in every section is renamed in each",
            v2({ left: [{ id: "acme.old" }], center: [{ id: "acme.old" }], right: [{ id: "acme.old" }] }), { "acme.old": "acme.new" },
            v2({ left: [{ id: "acme.new" }], center: [{ id: "acme.new" }], right: [{ id: "acme.new" }] }), true],
        ["a former id in disabledPlugins alone is renamed",
            { version: 3, disabledPlugins: ["acme.old"] }, { "acme.old": "acme.new" }, { version: 3, disabledPlugins: ["acme.new"] }, true],
        ["an id of a plugin that is not installed stays",
            v2({ right: [{ id: "gone.plugin" }] }, { plugins: [{ id: "gone.plugin", x: 1 }], disabledPlugins: ["gone.plugin"] }), { "acme.old": "acme.new" },
            v2({ right: [{ id: "gone.plugin" }] }, { plugins: [{ id: "gone.plugin", x: 1 }], disabledPlugins: ["gone.plugin"] }), false],
        ["an empty map renames nothing",
            { version: 3, disabledPlugins: ["acme.old"] }, {}, { version: 3, disabledPlugins: ["acme.old"] }, false],
        ["every other key naming a former id stays",
            { version: 3, sounds: { "acme.old": { ping: "pop" } }, manager: { id: "acme.old" }, bar: { id: "acme.old" }, welcome: { keys: [{ id: "acme.old", shortcut: "S", text: "t" }] } }, { "acme.old": "acme.new" },
            { version: 3, sounds: { "acme.old": { ping: "pop" } }, manager: { id: "acme.old" }, bar: { id: "acme.old" }, welcome: { keys: [{ id: "acme.old", shortcut: "S", text: "t" }] } }, false],
        ["a row or entry that is no object is left for the judge",
            v2({ right: ["acme.old"] }, { plugins: ["acme.old"] }), { "acme.old": "acme.new" }, v2({ right: ["acme.old"] }, { plugins: ["acme.old"] }), false],
        ["a list is left for the judge", [], { "acme.old": "acme.new" }, [], false],
    ];
    for (const [name, user, renames, want, renamed] of renameRows) {
        const before = JSON.stringify(user);
        check("renamePlugins: " + name, configLogic.renamePlugins(user, renames), { config: want, renamed: renamed });
        check("renamePlugins leaves its input: " + name, JSON.stringify(user), before);
    }

    const shipped = { version: 3, bar: { id: "vgs.bar", layout: { left: [{ id: "vgs.workspaces" }], center: [{ id: "vgs.clock" }], right: [] } }, plugins: [{ id: "acme.svc", x: 1 }], disabledPlugins: [] };

    // effectiveConfig rows: [name, user, path, want]
    const mergeRows = [
        ["no user file keeps shipped", null, "bar.id", "vgs.bar"],
        ["user bar replaces whole", { bar: { id: "other.bar" } }, "bar.layout", undefined],
        ["user plugin entry wins by id", { plugins: [{ id: "acme.svc", x: 2 }] }, "plugins.0.x", 2],
        ["shipped plugin entry survives", { plugins: [{ id: "b.c" }] }, "plugins.0.id", "acme.svc"],
        ["user plugin entry appended", { plugins: [{ id: "b.c" }] }, "plugins.1.id", "b.c"],
        ["user disabled list replaces", { disabledPlugins: ["vgs.clock"] }, "disabledPlugins.0", "vgs.clock"],
    ];
    function dig(obj, p) { return p.split(".").reduce((o, k) => (o === undefined ? undefined : o[k]), obj); }
    for (const [name, user, p, want] of mergeRows) {
        check("effectiveConfig: " + name, dig(configLogic.effectiveConfig(shipped, user), p), want);
    }
    check("effectiveConfig does not alias shipped", (() => { const c = configLogic.effectiveConfig(shipped, null); c.bar.id = "x"; return shipped.bar.id; })(), "vgs.bar");
    check("effectiveConfig does not alias the user file", (() => { const user = { bar: { id: "u.bar" } }; const c = configLogic.effectiveConfig(shipped, user); c.bar.id = "x"; return user.bar.id; })(), "u.bar");
    check("managerId reads the manager's id", ctx.managerId({ manager: { id: "a.b" } }), "a.b");
    check("managerId is empty for a file that names none", ctx.managerId({}), "");
    check("managerId is empty for an id that is not a string", ctx.managerId({ manager: { id: 3 } }), "");
    check("activeBarId falls back on an empty id", ctx.activeBarId({ bar: { id: "" } }, "vgs.bar"), "vgs.bar");
    check("layoutIds keeps section order left, center, right", ctx.layoutIds({ bar: { layout: { right: [{ id: "r" }], center: [{ id: "c" }], left: [{ id: "l" }] } } }), ["l", "c", "r"]);

    const manifests = {};
    for (const raw of [bar, clock, svc]) manifests[raw.id] = ctx.validateManifest(raw, "/p").manifest;
    manifests["vgs.workspaces"] = ctx.validateManifest(Object.assign({}, clock, { id: "vgs.workspaces", defaultSection: "left" }), "/p").manifest;
    manifests["vgs.svc"] = ctx.validateManifest(Object.assign({}, svc, { id: "vgs.svc", settings: {} }), "/p").manifest;
    manifests["acme.bar"] = ctx.validateManifest(Object.assign({}, bar, { id: "acme.bar" }), "/p").manifest;
    manifests["vgs.barpanel"] = ctx.validateManifest(Object.assign({}, bar, { id: "vgs.barpanel", kinds: ["bar", "panel"], entryPoints: { bar: "Bar.qml", panel: "P.qml" } }), "/p").manifest;
    const noSection = Object.assign({}, clock, { id: "acme.widget", settings: { size: 3, tags: ["a"] } });
    delete noSection.defaultSection;
    manifests["acme.widget"] = ctx.validateManifest(noSection, "/p").manifest;
    manifests["vgs.widgetpanel"] = ctx.validateManifest(Object.assign({}, clock, { id: "vgs.widgetpanel", kinds: ["bar-widget", "panel"], entryPoints: { "bar-widget": "W.qml", panel: "P.qml" }, defaultSection: "right" }), "/p").manifest;
    manifests["acme.both"] = ctx.validateManifest({ schemaVersion: 1, id: "acme.both", name: "B", version: "1", author: "a", description: "d", kinds: ["service", "bar-widget"], entryPoints: { service: "S.qml", "bar-widget": "W.qml" }, defaultSection: "right", settings: { label: "probe" } }, "/p").manifest;
    manifests["acme.pane"] = ctx.validateManifest({ schemaVersion: 1, id: "acme.pane", name: "Pane", version: "1", author: "a", description: "d", kinds: ["service", "bar-widget", "pane"], entryPoints: { service: "S.qml", "bar-widget": "W.qml", pane: "Pane.qml" }, defaultSection: "right", pane: { group: "System", order: 2 }, settings: { label: "probe" }, schema: { label: { type: "string", label: "Label", presets: [{ value: "probe" }], allowCustom: true } }, capabilities: ["configure"] }, "/p").manifest;
    for (const id of Object.keys(manifests)) if (manifests[id] === undefined) { throw new Error("fixture manifest refused: " + id); }

    // isEnabled rows: [name, config, id, want]
    const enabledRows = [
        ["active bar enabled", shipped, "vgs.bar", true],
        ["placed widget enabled", shipped, "vgs.clock", true],
        ["listed third-party service enabled", shipped, "acme.svc", true],
        ["unplaced widget disabled", configLogic.effectiveConfig(shipped, { bar: { id: "vgs.bar", layout: { left: [], center: [], right: [] } } }), "vgs.clock", false],
        ["unlisted third-party disabled", configLogic.effectiveConfig(Object.assign({}, shipped, { plugins: [] }), null), "acme.svc", false],
        ["shipped listing survives an empty user list", configLogic.effectiveConfig(shipped, { plugins: [] }), "acme.svc", true],
        ["disabledPlugins wins over placement", configLogic.effectiveConfig(shipped, { disabledPlugins: ["vgs.clock"] }), "vgs.clock", false],
        ["bar id absent falls to default", configLogic.effectiveConfig(shipped, { bar: {} }), "vgs.bar", true],
        ["other active bar disables default bar", configLogic.effectiveConfig(shipped, { bar: { id: "other.bar" } }), "vgs.bar", false],
        ["first-party service enabled unlisted", shipped, "vgs.svc", true],
        ["first-party service disabled when listed", configLogic.effectiveConfig(shipped, { disabledPlugins: ["vgs.svc"] }), "vgs.svc", false],
        ["first-party widget is not enabled unplaced", shipped, "acme.widget", false],
        ["a placed widget listed in disabledPlugins is disabled", configLogic.effectiveConfig(shipped, { disabledPlugins: ["vgs.workspaces"] }), "vgs.workspaces", false],
        ["an inactive bar listed for its settings is not enabled", configLogic.effectiveConfig(shipped, { plugins: [{ id: "acme.bar", x: 1 }] }), "acme.bar", false],
        ["an unplaced widget listed for its settings is not enabled", configLogic.effectiveConfig(shipped, { plugins: [{ id: "acme.widget", size: 1 }] }), "acme.widget", false],
        ["an inactive first-party bar with a panel kind is not enabled", configLogic.effectiveConfig(shipped, { bar: { id: "acme.bar" } }), "vgs.barpanel", false],
        ["the active first-party bar with a panel kind is enabled", configLogic.effectiveConfig(shipped, { bar: { id: "vgs.barpanel" } }), "vgs.barpanel", true],
        ["a first-party widget with a panel kind is enabled unplaced", shipped, "vgs.widgetpanel", true],
    ];
    for (const [name, config, id, want] of enabledRows) {
        check("isEnabled: " + name, ctx.isEnabled(config, manifests[id], "vgs.bar"), want);
    }

    check("hiddenByDisabling the active bar names its enabled widgets", ctx.hiddenByDisabling(manifests, shipped, "vgs.bar", "vgs.bar"), ["vgs.clock", "vgs.workspaces"]);
    check("hiddenByDisabling ignores disabled widgets", ctx.hiddenByDisabling(manifests, configLogic.effectiveConfig(shipped, { disabledPlugins: ["vgs.clock"] }), "vgs.bar", "vgs.bar"), ["vgs.workspaces"]);
    check("hiddenByDisabling an inactive bar is empty", ctx.hiddenByDisabling(manifests, configLogic.effectiveConfig(shipped, { bar: { id: "other.bar" } }), "vgs.bar", "vgs.bar"), []);
    check("hiddenByDisabling a widget is empty", ctx.hiddenByDisabling(manifests, shipped, "vgs.clock", "vgs.bar"), []);
    check("hiddenByDisabling leaves out an enabled widget the layout does not place", ctx.hiddenByDisabling(manifests, shipped, "vgs.bar", "vgs.bar").indexOf("vgs.widgetpanel"), -1);
    check("hiddenByDisabling names a placed first-party widget with a panel kind", ctx.hiddenByDisabling(manifests, configLogic.effectiveConfig(shipped, { bar: { id: "vgs.bar", layout: { left: [], center: [], right: [{ id: "vgs.widgetpanel" }] } } }), "vgs.bar", "vgs.bar"), ["vgs.widgetpanel"]);
    check("hiddenByDisabling sorts ids", ctx.hiddenByDisabling(manifests, configLogic.effectiveConfig(shipped, { bar: { id: "vgs.bar", layout: { left: [{ id: "vgs.workspaces" }], center: [{ id: "vgs.clock" }], right: [{ id: "acme.widget" }] } } }), "vgs.bar", "vgs.bar"), ["acme.widget", "vgs.clock", "vgs.workspaces"]);
    check("hiddenByDisabling ignores a prototype name", ctx.hiddenByDisabling(manifests, shipped, "constructor", "vgs.bar"), []);
    check("hasOwn rejects a prototype name", ctx.hasOwn(manifests, "toString"), false);

    // effectiveLayout: placement filtered by enablement, entries copied.
    const layoutRows = [
        ["shipped layout shows both widgets", shipped, { left: [{ id: "vgs.workspaces" }], center: [{ id: "vgs.clock" }], right: [] }],
        ["a disabled widget leaves its section and its entry stays in the file", configLogic.effectiveConfig(shipped, { disabledPlugins: ["vgs.clock"] }), { left: [{ id: "vgs.workspaces" }], center: [], right: [] }],
        ["an unknown id is not shown", configLogic.effectiveConfig(shipped, { bar: { id: "vgs.bar", layout: { left: [{ id: "nope.x" }, { id: "vgs.workspaces" }], center: [], right: [] } } }), { left: [{ id: "vgs.workspaces" }], center: [], right: [] }],
        ["a plugin without the widget kind is not shown", configLogic.effectiveConfig(shipped, { bar: { id: "vgs.bar", layout: { left: [{ id: "acme.svc" }], center: [], right: [] } } }), { left: [], center: [], right: [] }],
        ["entries keep their settings keys", configLogic.effectiveConfig(shipped, { bar: { id: "vgs.bar", layout: { left: [], center: [{ id: "vgs.clock", format: "HH:mm" }], right: [] } } }), { left: [], center: [{ id: "vgs.clock", format: "HH:mm" }], right: [] }],
        ["a missing section reads as empty", configLogic.effectiveConfig(shipped, { bar: { id: "vgs.bar", layout: { left: [{ id: "vgs.workspaces" }] } } }), { left: [{ id: "vgs.workspaces" }], center: [], right: [] }],
    ];
    for (const [name, config, want] of layoutRows) {
        check("effectiveLayout: " + name, ctx.effectiveLayout(config, manifests, "vgs.bar"), want);
    }
    check("effectiveLayout does not alias the configuration", (() => { const c = configLogic.effectiveConfig(shipped, null); ctx.effectiveLayout(c, manifests, "vgs.bar").left[0].x = 1; return c.bar.layout.left[0].x; })(), undefined);

    const builtinNames = ["left-workspaces", "center-clock"];
    const builtinConfig = { bar: { id: "vgs.bar", layout: {
        left: [{ id: "acme.widget" }, { id: "vgs.bar/left-workspaces" }],
        center: [{ id: "vgs.bar/center-clock" }], right: [] } } };
    for (const [name, config, names, want] of [
        ["registered builtin shares plugin order", builtinConfig, builtinNames, builtinConfig.bar.layout],
        ["no catalogue admits no builtin", builtinConfig, [], { left: [{ id: "acme.widget" }], center: [], right: [] }],
        ["foreign and unknown registration IDs are ignored", { bar: { id: "vgs.bar", layout: { left: [{ id: "alt.bar/center-clock" }, { id: "vgs.bar/unknown" }], center: [], right: [] } } }, builtinNames, { left: [], center: [], right: [] }],
        ["a registration appears once across sections", { bar: { id: "vgs.bar", layout: { left: [{ id: "vgs.bar/center-clock" }], center: [{ id: "vgs.bar/center-clock" }], right: [] } } }, builtinNames, { left: [{ id: "vgs.bar/center-clock" }], center: [], right: [] }],
        ["disabled active bar exposes no builtin", Object.assign({ disabledPlugins: ["vgs.bar"] }, builtinConfig), builtinNames, { left: [{ id: "acme.widget" }], center: [], right: [] }],
    ]) check("effectiveLayout builtin: " + name, ctx.effectiveLayout(config, manifests, "vgs.bar", names), want);
    for (const [name, config, id, section, index, want] of [
        ["builtin moves with its active bar owner", builtinConfig, "vgs.bar/center-clock", "left", 0, ""],
        ["builtin needs its advertised name", builtinConfig, "vgs.bar/unknown", "left", 0, "refused: moved=vgs.bar/unknown reason=no-bar-widget"],
        ["builtin needs placement", { bar: { id: "vgs.bar", layout: {} } }, "vgs.bar/center-clock", "left", 0, "refused: moved=vgs.bar/center-clock reason=unplaced"],
        ["builtin uses the same section guard", builtinConfig, "vgs.bar/center-clock", "top", 0, 'refused: section="top" want=left|center|right'],
        ["builtin uses the same index guard", builtinConfig, "vgs.bar/center-clock", "left", -1, "refused: index=-1 want=integer>=0"],
    ]) check("moveRefusal builtin: " + name, ctx.moveRefusal(config, manifests["vgs.bar"], section, index, "vgs.bar", builtinNames, id), want);
    check("withMoved keeps builtin identity across sections", ctx.withMoved({}, manifests["vgs.bar"], null, "right", 0, builtinConfig, "vgs.bar/center-clock").bar.layout,
        { left: builtinConfig.bar.layout.left, center: [], right: [{ id: "vgs.bar/center-clock" }] });
    for (const [name, id, names, want] of [
        ["registered builtin can be hidden", "vgs.bar/center-clock", builtinNames, ""],
        ["unknown builtin cannot be placed", "vgs.bar/unknown", builtinNames, "refused: placed=vgs.bar/unknown reason=no-bar-widget"],
        ["foreign builtin cannot be placed", "alt.bar/center-clock", builtinNames, "refused: placed=alt.bar/center-clock reason=no-bar-widget"],
        ["builtin needs its catalogue", "vgs.bar/center-clock", [], "refused: placed=vgs.bar/center-clock reason=no-bar-widget"],
    ]) check("placedRefusal builtin: " + name, ctx.placedRefusal(builtinConfig, manifests["vgs.bar"], "vgs.bar", names, id), want);
    const hiddenBuiltin = ctx.withPlaced({}, manifests["vgs.bar"], false, builtinConfig, "vgs.bar/center-clock");
    check("builtin Hide removes its ordinary entry", hiddenBuiltin.bar.layout,
        { left: builtinConfig.bar.layout.left, center: [], right: [] });
    check("builtin Hide creates no independent settings row", hiddenBuiltin.plugins, undefined);
    check("builtin Hide keeps owner enablement", ctx.isEnabled(configLogic.effectiveConfig(builtinConfig, hiddenBuiltin), manifests["vgs.bar"], "vgs.bar"), true);
    check("builtin placement restores only an ordinary entry", ctx.withPlaced(hiddenBuiltin, manifests["vgs.bar"], true,
        configLogic.effectiveConfig(builtinConfig, hiddenBuiltin), "vgs.bar/center-clock").bar.layout.center, [{ id: "vgs.bar/center-clock" }]);
    // Builtin families: one registration per placed `<family>-<n>`.
    const families = ["gap", "separator"];
    const familyConfig = { bar: { id: "vgs.bar", layout: {
        left: [{ id: "vgs.bar/gap-2" }, { id: "vgs.bar/left-workspaces" }, { id: "vgs.bar/separator-1" }],
        center: [{ id: "vgs.bar/gap-7" }, { id: "alt.bar/gap-9" }, { id: "vgs.bar/gap-02" }, { id: "vgs.bar/rule-1" }, { id: "vgs.bar/gap-0" }],
        right: [{ id: "vgs.bar/gap-2" }] } } };
    for (const [name, member, want] of [
        ["a declared family member", "gap-3", "gap"],
        ["another declared family", "separator-12", "separator"],
        ["an undeclared family", "rule-1", ""],
        ["a bare family name", "gap", ""],
        ["a zero number", "gap-0", ""],
        ["a leading zero", "gap-02", ""],
        ["a fixed builtin", "center-clock", ""],
    ]) check("builtinFamilyOf: " + name, ctx.builtinFamilyOf(member, families), want);
    check("placedFamilyNames: the bar's members once each in section order", ctx.placedFamilyNames(familyConfig, "vgs.bar", families), ["gap-2", "separator-1", "gap-7"]);
    check("placedFamilyNames: no families admit no member", ctx.placedFamilyNames(familyConfig, "vgs.bar", []), []);
    check("nextFamilyName: one past the highest placed member", ctx.nextFamilyName(familyConfig, "vgs.bar", "gap"), "gap-8");
    check("nextFamilyName: a family with no member starts at one", ctx.nextFamilyName(builtinConfig, "vgs.bar", "gap"), "gap-1");
    check("nextFamilyName: another bar's members do not count", ctx.nextFamilyName({ bar: { id: "vgs.bar", layout: { left: [{ id: "alt.bar/gap-4" }] } } }, "vgs.bar", "gap"), "gap-1");
    const familyNames = builtinNames.concat(ctx.placedFamilyNames(familyConfig, "vgs.bar", families));
    check("effectiveLayout builtin: placed family members share plugin order", ctx.effectiveLayout(familyConfig, manifests, "vgs.bar", familyNames),
        { left: [{ id: "vgs.bar/gap-2" }, { id: "vgs.bar/left-workspaces" }, { id: "vgs.bar/separator-1" }], center: [{ id: "vgs.bar/gap-7" }], right: [] });
    check("placedRefusal builtin: a placed family member can be removed", ctx.placedRefusal(familyConfig, manifests["vgs.bar"], "vgs.bar", familyNames, "vgs.bar/separator-1"), "");
    check("moveRefusal builtin: a placed family member moves", ctx.moveRefusal(familyConfig, manifests["vgs.bar"], "right", 0, "vgs.bar", familyNames, "vgs.bar/gap-7"), "");
    const removedGap = ctx.withPlaced({}, manifests["vgs.bar"], false, familyConfig, "vgs.bar/gap-7");
    check("withPlaced: removing one member leaves the others", removedGap.bar.layout.center, familyConfig.bar.layout.center.slice(1));
    check("withPlaced: removing a member writes no plugins row", removedGap.plugins, undefined);
    for (const [name, user, section, index, want] of [
        ["inserts at the index", builtinConfig, "left", 1, [{ id: "acme.widget" }, { id: "vgs.bar/gap-1" }, { id: "vgs.bar/left-workspaces" }]],
        ["an index past the end appends", builtinConfig, "left", 9, [{ id: "acme.widget" }, { id: "vgs.bar/left-workspaces" }, { id: "vgs.bar/gap-1" }]],
        ["a missing section is created", { bar: { id: "vgs.bar", layout: { left: [] } } }, "right", 0, [{ id: "vgs.bar/gap-1" }]],
    ]) check("withBuiltinAt: " + name, ctx.withBuiltinAt(user, "vgs.bar/gap-1", section, index, user).bar.layout[section], want);
    check("withBuiltinAt: seeds the user bar from the effective bar", ctx.withBuiltinAt(null, "vgs.bar/gap-1", "center", 0, builtinConfig).bar.layout,
        { left: builtinConfig.bar.layout.left, center: [{ id: "vgs.bar/gap-1" }, { id: "vgs.bar/center-clock" }], right: [] });
    check("withBuiltinAt does not alias the user file", (() => { const u = ctx.clone(builtinConfig); ctx.withBuiltinAt(u, "vgs.bar/gap-1", "right", 0, u); return u.bar.layout.right; })(), []);
    const builtinDefaults = { bar: { id: "vgs.bar", layout: {
        left: [{ id: "acme.widget" }, { id: "vgs.bar/left-workspaces" }, { id: "acme.tick" }],
        center: [{ id: "vgs.bar/center-clock" }], right: [] } } };
    for (const [name, id, layout, expected] of [
        ["restores between declared neighbours", "vgs.bar/left-workspaces", { left: [{ id: "acme.widget" }, { id: "acme.tick" }, { id: "acme.extra" }], center: [], right: [] },
            { left: [{ id: "acme.widget" }, { id: "vgs.bar/left-workspaces" }, { id: "acme.tick" }, { id: "acme.extra" }], center: [], right: [] }],
        ["restores before a remaining next neighbour", "vgs.bar/left-workspaces", { left: [{ id: "acme.extra" }, { id: "acme.other" }, { id: "acme.tick" }], center: [], right: [] },
            { left: [{ id: "acme.extra" }, { id: "acme.other" }, { id: "vgs.bar/left-workspaces" }, { id: "acme.tick" }], center: [], right: [] }],
        ["restores after a remaining previous neighbour", "vgs.bar/left-workspaces", { left: [{ id: "acme.extra" }, { id: "acme.widget" }, { id: "acme.other" }], center: [], right: [] },
            { left: [{ id: "acme.extra" }, { id: "acme.widget" }, { id: "vgs.bar/left-workspaces" }, { id: "acme.other" }], center: [], right: [] }],
        ["restores at declared position without neighbours", "vgs.bar/left-workspaces", { left: [{ id: "acme.extra" }, { id: "acme.other" }], center: [], right: [] },
            { left: [{ id: "acme.extra" }, { id: "vgs.bar/left-workspaces" }, { id: "acme.other" }], center: [], right: [] }],
        ["restores clock at its default before automatic widgets", "vgs.bar/center-clock", { left: [], center: [{ id: "acme.extra" }], right: [] },
            { left: [], center: [{ id: "vgs.bar/center-clock" }, { id: "acme.extra" }], right: [] }],
    ]) {
        const user = { version: 3, bar: { id: "vgs.bar", layout }, plugins: [{ id: "vgs.bar", clockFormat: "HH:mm" }], disabledPlugins: [], unrelated: { keep: true } };
        const restored = ctx.withPlaced(user, manifests["vgs.bar"], true, user, id, builtinDefaults);
        check("builtin default restore: " + name, restored, Object.assign({}, user, { bar: { id: "vgs.bar", layout: expected } }));
        check("builtin restore twice is once: " + name, ctx.withPlaced(restored, manifests["vgs.bar"], true, restored, id, builtinDefaults), restored);
    }
    const relocatedDefault = { bar: { layout: { left: [], center: [], right: [{ id: "vgs.bar/left-workspaces" }] } } };
    check("builtin default restoration never infers section from its ID", ctx.withPlaced({}, manifests["vgs.bar"], true,
        { bar: { layout: { left: [], center: [], right: [] } } }, "vgs.bar/left-workspaces", relocatedDefault).bar.layout,
        { left: [], center: [], right: [{ id: "vgs.bar/left-workspaces" }] });

    // settingsFor: manifest defaults under the plugins row, for every kind.
    check("settingsFor merges the plugins row over defaults", ctx.settingsFor(configLogic.effectiveConfig(shipped, { plugins: [{ id: "acme.widget", size: 9 }] }), manifests["acme.widget"]), { size: 9, tags: ["a"] });
    check("settingsFor drops the id key", ctx.settingsFor(configLogic.effectiveConfig(shipped, { plugins: [{ id: "acme.widget" }] }), manifests["acme.widget"]).id, undefined);
    check("settingsFor reads the plugins entry for a service", ctx.settingsFor(configLogic.effectiveConfig(shipped, { plugins: [{ id: "acme.svc", x: 2 }] }), manifests["acme.svc"]), { x: 2 });
    check("settingsFor is empty with no entry and no defaults", ctx.settingsFor(shipped, manifests["vgs.svc"]), {});
    check("settingsFor gives a widget the manifest defaults with no row", ctx.settingsFor(shipped, manifests["acme.both"]), { label: "probe" });
    // The manager's page, the service and the widget of a placed
    // widget-plus-service read one value: the row's.
    const placedRow = configLogic.effectiveConfig(shipped, { bar: { id: "vgs.bar", layout: { left: [], center: [{ id: "acme.both" }], right: [] } }, plugins: [{ id: "acme.both", label: "row" }] });
    check("settingsFor gives a placed widget-plus-service its plugins row", ctx.settingsFor(placedRow, manifests["acme.both"]), { label: "row" });
    check("settingsFor does not alias the row", (() => { const c = { plugins: [{ id: "acme.widget", tags: ["z"] }] }; const s2 = ctx.settingsFor(c, manifests["acme.widget"]); s2.tags.push("y"); return c.plugins[0].tags; })(), ["z"]);
    check("settingsFor ignores undeclared and reserved keys", ctx.settingsFor({ plugins: [{ id: "acme.widget", size: 0, retired: "unused", keys: { toggle: "SUPER+A" } }] }, manifests["acme.widget"]), { size: 0, tags: ["a"] });
    const unreadValue = { id: "acme.widget", size: 0, keys: { toggle: "SUPER+A" } };
    Object.defineProperty(unreadValue, "retired", { enumerable: true, get() { throw new Error("undeclared value read"); } });
    check("settingsFor never reads an undeclared value", ctx.settingsFor({ plugins: [unreadValue] }, manifests["acme.widget"]), { size: 0, tags: ["a"] });
    for (const stored of [false, true]) {
        const copied = ctx.copyEntrySettings({}, unreadValue, manifests["acme.widget"], stored);
        check("copyEntrySettings reads only declared and retained reserved values: stored=" + stored, copied, stored ? { id: "acme.widget", size: 0, keys: { toggle: "SUPER+A" } } : { size: 0 });
        if (stored) copied.keys.toggle = "SUPER+B";
        check("copyEntrySettings does not alias retained reserved values: stored=" + stored, unreadValue.keys, { toggle: "SUPER+A" });
    }
    const prototypeEntry = JSON.parse('{"id":"vgs.bar","constructor":1,"__proto__":2}');
    check("copyEntrySettings excludes inherited declaration names", ctx.copyEntrySettings({}, prototypeEntry, manifests["vgs.bar"], true), { id: "vgs.bar" });

    // withEnabled rows: [name, user, effective, id, enabled, path, want].
    // `effective` is the merged configuration the manager reads presence from.
    const placedClock = { version: 3, bar: { id: "vgs.bar", layout: { left: [{ id: "vgs.workspaces" }], center: [{ id: "vgs.clock" }], right: [] } }, plugins: [{ id: "vgs.clock", format: "HH:mm:ss" }] };
    const listedSvc = { version: 3, plugins: [{ id: "acme.svc", x: 1 }] };
    const withRows = [
        ["disable preserves inherited disabled plugins", null, Object.assign({}, shipped, { disabledPlugins: ["vgs.clock"] }), "acme.svc", false, "disabledPlugins", ["vgs.clock", "acme.svc"]],
        ["enable removes only its inherited disabled entry", null, Object.assign({}, shipped, { disabledPlugins: ["vgs.clock", "acme.svc"] }), "acme.svc", true, "disabledPlugins", ["vgs.clock"]],
        ["an explicit empty disabled list overrides shipped entries", { disabledPlugins: [] }, configLogic.effectiveConfig(Object.assign({}, shipped, { disabledPlugins: ["vgs.clock"] }), { disabledPlugins: [] }), "acme.svc", false, "disabledPlugins", ["acme.svc"]],
        ["disable bar lists it", null, shipped, "vgs.bar", false, "disabledPlugins", ["vgs.bar"]],
        ["disable twice lists it once", { disabledPlugins: ["vgs.bar"] }, shipped, "vgs.bar", false, "disabledPlugins", ["vgs.bar"]],
        ["enable bar unlists it", { disabledPlugins: ["vgs.bar"] }, shipped, "vgs.bar", true, "disabledPlugins", []],
        ["disable bar leaves the bar key alone", null, shipped, "vgs.bar", false, "bar", undefined],
        ["disable widget keeps its placement", placedClock, configLogic.effectiveConfig(shipped, placedClock), "vgs.clock", false, "bar.layout.center", [{ id: "vgs.clock" }]],
        ["disable widget keeps its settings row", placedClock, configLogic.effectiveConfig(shipped, placedClock), "vgs.clock", false, "plugins", [{ id: "vgs.clock", format: "HH:mm:ss" }]],
        ["disable widget only lists it", placedClock, configLogic.effectiveConfig(shipped, placedClock), "vgs.clock", false, "disabledPlugins", ["vgs.clock"]],
        ["re-enable a placed widget changes only the disabled list", Object.assign({ disabledPlugins: ["vgs.clock"] }, placedClock), configLogic.effectiveConfig(shipped, Object.assign({ disabledPlugins: ["vgs.clock"] }, placedClock)), "vgs.clock", true, "bar", placedClock.bar],
        ["enable a placed widget is idempotent", placedClock, configLogic.effectiveConfig(shipped, placedClock), "vgs.clock", true, "bar", placedClock.bar],
        ["enable an unplaced widget places it in its default section", null, configLogic.effectiveConfig(shipped, { bar: { id: "vgs.bar", layout: { left: [], center: [], right: [] } } }), "vgs.workspaces", true, "bar.layout.left.0.id", "vgs.workspaces"],
        ["enable an unplaced widget seeds the user bar from the effective bar", null, shipped, "acme.widget", true, "bar.layout.left", [{ id: "vgs.workspaces" }]],
        ["enable an unplaced widget keeps the effective bar id", null, shipped, "acme.widget", true, "bar.id", "vgs.bar"],
        ["a user bar key is not reseeded", { bar: { layout: { left: [], center: [], right: [] } } }, configLogic.effectiveConfig(shipped, { bar: { layout: { left: [], center: [], right: [] } } }), "acme.widget", true, "bar.layout.left", []],
        ["no default section places in center", null, shipped, "acme.widget", true, "bar.layout.center.1.id", "acme.widget"],
        ["a manifest default section is used", null, configLogic.effectiveConfig(shipped, { bar: { id: "vgs.bar", layout: { left: [], center: [], right: [] } } }), "acme.both", true, "bar.layout.right.0.id", "acme.both"],
        ["enable third-party service lists it", null, configLogic.effectiveConfig(Object.assign({}, shipped, { plugins: [] }), null), "acme.svc", true, "plugins", [{ id: "acme.svc" }]],
        ["enable a listed third-party service keeps its row", listedSvc, configLogic.effectiveConfig(shipped, listedSvc), "acme.svc", true, "plugins", [{ id: "acme.svc", x: 1 }]],
        ["disable third-party service keeps its row", listedSvc, configLogic.effectiveConfig(shipped, listedSvc), "acme.svc", false, "plugins", [{ id: "acme.svc", x: 1 }]],
        ["disable third-party service lists it", listedSvc, configLogic.effectiveConfig(shipped, listedSvc), "acme.svc", false, "disabledPlugins", ["acme.svc"]],
        ["enable first-party service does not list it in plugins", { disabledPlugins: ["vgs.svc"] }, shipped, "vgs.svc", true, "plugins", undefined],
        ["writes version 3", null, shipped, "acme.svc", true, "version", 3],
        ["enable bar sets it active", null, shipped, "acme.bar", true, "bar.id", "acme.bar"],
        ["enable bar seeds the layout from the effective bar", null, shipped, "acme.bar", true, "bar.layout.center.0.id", "vgs.clock"],
        ["enable the active bar changes nothing but the disabled list", { disabledPlugins: ["vgs.bar"] }, shipped, "vgs.bar", true, "bar", undefined],
        ["enable bar does not list it in plugins", null, shipped, "acme.bar", true, "plugins", undefined],
        ["enable widget does not list it in plugins", null, shipped, "acme.widget", true, "plugins", undefined],
        ["enable a widget-plus-service plugin places it and does not list it", null, shipped, "acme.both", true, "plugins", undefined],
        ["enable an unplaced widget places an entry holding its id alone", null, configLogic.effectiveConfig(shipped, { plugins: [{ id: "acme.both", label: "row", keys: {} }] }), "acme.both", true, "bar.layout.right", [{ id: "acme.both" }]],
    ];
    for (const [name, user, effective, id, enabled, p, want] of withRows) {
        check("withEnabled: " + name, dig(ctx.withEnabled(user, manifests[id], enabled, effective), p), want);
    }
    check("withEnabled does not alias the user file", (() => { const u = { bar: { layout: { left: [], center: [], right: [] } } }; ctx.withEnabled(u, manifests["acme.widget"], true, configLogic.effectiveConfig(shipped, u)); return u.bar.layout.center; })(), []);

    // isPlaced rows: [name, config, id, want]. Placement reads apart from
    // enablement.
    const placedRows = [
        ["a widget in a section is placed", shipped, "vgs.clock", true],
        ["a widget in no section is unplaced", shipped, "acme.widget", false],
        ["a disabled widget's entry still reads placed", configLogic.effectiveConfig(shipped, { disabledPlugins: ["vgs.clock"] }), "vgs.clock", true],
        ["an entry of a plugin without the widget kind is no placement", configLogic.effectiveConfig(shipped, { bar: { id: "vgs.bar", layout: { left: [{ id: "acme.svc" }], center: [], right: [] } } }), "acme.svc", false],
    ];
    for (const [name, config, id, want] of placedRows) check("isPlaced: " + name, ctx.isPlaced(config, manifests[id]), want);

    // placedRefusal rows: [name, config, id, want].
    const placedRefusalRows = [
        ["an enabled placed widget may be unplaced", shipped, "vgs.clock", ""],
        ["an enabled unplaced widget-plus-panel may be placed", shipped, "vgs.widgetpanel", ""],
        ["a service has no widget", shipped, "acme.svc", "refused: placed=acme.svc reason=no-bar-widget"],
        ["a bar has no widget", shipped, "vgs.bar", "refused: placed=vgs.bar reason=no-bar-widget"],
        ["a disabled widget is refused", configLogic.effectiveConfig(shipped, { disabledPlugins: ["vgs.clock"] }), "vgs.clock", "refused: placed=vgs.clock reason=disabled"],
        ["an unplaced widget-only plugin is disabled", shipped, "acme.widget", "refused: placed=acme.widget reason=disabled"],
    ];
    for (const [name, config, id, want] of placedRefusalRows) check("placedRefusal: " + name, ctx.placedRefusal(config, manifests[id], "vgs.bar"), want);

    // withPlaced rows: [name, user, effective, id, placed, path, want].
    const placedBoth = { version: 3, bar: { id: "vgs.bar", layout: { left: [{ id: "acme.both" }], center: [{ id: "vgs.clock" }], right: [{ id: "acme.both" }] } } };
    const placedPanel = { version: 3, bar: { id: "vgs.bar", layout: { left: [], center: [{ id: "vgs.clock" }], right: [{ id: "vgs.widgetpanel" }] } } };
    const inheritedDisabled = Object.assign({}, shipped, { disabledPlugins: ["vgs.workspaces"] });
    const placeRows = [
        ["place puts the widget in its default section", null, shipped, "acme.both", true, "bar.layout.right", [{ id: "acme.both" }]],
        ["place puts a widget with no default section in center", null, shipped, "acme.widget", true, "bar.layout.center", [{ id: "vgs.clock" }, { id: "acme.widget" }]],
        ["place seeds the user bar from the effective bar", null, shipped, "acme.both", true, "bar.layout.left", [{ id: "vgs.workspaces" }]],
        ["place puts an entry holding its id alone", null, configLogic.effectiveConfig(shipped, { plugins: [{ id: "acme.both", label: "row", keys: {} }] }), "acme.both", true, "bar.layout.right", [{ id: "acme.both" }]],
        ["place lists nothing in plugins", null, shipped, "acme.both", true, "plugins", undefined],
        ["place a placed widget changes nothing", placedBoth, configLogic.effectiveConfig(shipped, placedBoth), "acme.both", true, "bar", placedBoth.bar],
        ["place keeps the user's disabled list", { disabledPlugins: ["vgs.svc"] }, configLogic.effectiveConfig(shipped, { disabledPlugins: ["vgs.svc"] }), "acme.both", true, "disabledPlugins", ["vgs.svc"]],
        ["place writes no inherited disabled list", null, inheritedDisabled, "acme.both", true, "disabledPlugins", undefined],
        ["place writes version 3", null, shipped, "acme.both", true, "version", 3],
        ["unplace removes every entry in every section and keeps other widgets", placedBoth, configLogic.effectiveConfig(shipped, placedBoth), "acme.both", false, "bar.layout", { left: [], center: [{ id: "vgs.clock" }], right: [] }],
        ["unplace keeps the bar id", placedBoth, configLogic.effectiveConfig(shipped, placedBoth), "acme.both", false, "bar.id", "vgs.bar"],
        ["unplace seeds the user bar from the effective bar", null, shipped, "vgs.clock", false, "bar.layout", { left: [{ id: "vgs.workspaces" }], center: [], right: [] }],
        ["unplace a third-party widget-plus-service lists it", placedBoth, configLogic.effectiveConfig(shipped, placedBoth), "acme.both", false, "plugins", [{ id: "acme.both" }]],
        ["unplace a listed third-party widget-plus-service keeps its row", Object.assign({ plugins: [{ id: "acme.both", label: "row" }] }, placedBoth), configLogic.effectiveConfig(shipped, Object.assign({ plugins: [{ id: "acme.both", label: "row" }] }, placedBoth)), "acme.both", false, "plugins", [{ id: "acme.both", label: "row" }]],
        ["unplace a first-party widget-plus-panel lists it", placedPanel, configLogic.effectiveConfig(shipped, placedPanel), "vgs.widgetpanel", false, "plugins", [{ id: "vgs.widgetpanel" }]],
        ["unplace a widget-only plugin lists it", null, shipped, "vgs.clock", false, "plugins", [{ id: "vgs.clock" }]],
        ["unplace an unplaced widget changes nothing", null, shipped, "acme.both", false, "bar", undefined],
        ["unplace keeps the user's disabled list", Object.assign({ disabledPlugins: ["vgs.svc"] }, placedBoth), configLogic.effectiveConfig(shipped, Object.assign({ disabledPlugins: ["vgs.svc"] }, placedBoth)), "acme.both", false, "disabledPlugins", ["vgs.svc"]],
        ["unplace writes no inherited disabled list", null, inheritedDisabled, "vgs.clock", false, "disabledPlugins", undefined],
    ];
    for (const [name, user, effective, id, placed, p, want] of placeRows) {
        check("withPlaced: " + name, dig(ctx.withPlaced(user, manifests[id], placed, effective), p), want);
    }
    // Enablement after an unplace, read from the merged result.
    const unplacedEnabled = (user, id) => ctx.isEnabled(configLogic.effectiveConfig(shipped, ctx.withPlaced(user, manifests[id], false, configLogic.effectiveConfig(shipped, user))), manifests[id], "vgs.bar");
    check("withPlaced: a third-party widget-plus-service stays enabled once unplaced", unplacedEnabled(placedBoth, "acme.both"), true);
    check("withPlaced: a first-party widget-plus-panel stays enabled once unplaced", unplacedEnabled(placedPanel, "vgs.widgetpanel"), true);
    check("withPlaced: a widget-only plugin reads disabled once unplaced", unplacedEnabled(null, "vgs.clock"), false);
    // Applying an edit twice gives the file applying it once gives.
    const twice = (user, id, placed) => {
        const once = ctx.withPlaced(user, manifests[id], placed, configLogic.effectiveConfig(shipped, user));
        return JSON.stringify(ctx.withPlaced(once, manifests[id], placed, configLogic.effectiveConfig(shipped, once))) === JSON.stringify(once);
    };
    check("withPlaced: placing twice is placing once", twice(null, "acme.both", true), true);
    check("withPlaced: unplacing twice is unplacing once", twice(placedBoth, "acme.both", false), true);
    check("withPlaced does not alias the user file on place", (() => { const u = { bar: { layout: { left: [], center: [], right: [] } } }; ctx.withPlaced(u, manifests["acme.both"], true, configLogic.effectiveConfig(shipped, u)); return u.bar.layout.right; })(), []);
    // A third-party plugin whose only kind is bar-widget: unplacing lists a
    // row, it still reads disabled, and the disabled list stays the user's.
    const placedWidget = { version: 3, disabledPlugins: ["vgs.svc"], bar: { id: "vgs.bar", layout: { left: [], center: [{ id: "vgs.clock" }], right: [{ id: "acme.widget" }] } } };
    const unplacedWidget = ctx.withPlaced(placedWidget, manifests["acme.widget"], false, configLogic.effectiveConfig(shipped, placedWidget));
    check("withPlaced: unplace a third-party widget-only plugin lists it", unplacedWidget.plugins, [{ id: "acme.widget" }]);
    check("withPlaced: unplace a third-party widget-only plugin keeps the user's disabled list", unplacedWidget.disabledPlugins, ["vgs.svc"]);
    check("withPlaced: a third-party widget-only plugin reads disabled once unplaced", ctx.isEnabled(configLogic.effectiveConfig(shipped, unplacedWidget), manifests["acme.widget"], "vgs.bar"), false);

    // moveRefusal rows: [name, config, id, section, index, want].
    const movedConfig = { version: 3, bar: { id: "vgs.bar", layout: { left: [{ id: "acme.both" }], center: [{ id: "vgs.clock" }], right: [] } } };
    const moveRefusalRows = [
        ["a placed widget may move", movedConfig, "acme.both", "right", 0, ""],
        ["a service has no widget", movedConfig, "acme.svc", "right", 0, "refused: moved=acme.svc reason=no-bar-widget"],
        ["a disabled widget is refused", configLogic.effectiveConfig(shipped, Object.assign({ disabledPlugins: ["acme.both"] }, movedConfig)), "acme.both", "right", 0, "refused: moved=acme.both reason=disabled"],
        ["an unplaced widget is refused", shipped, "acme.both", "right", 0, "refused: moved=acme.both reason=unplaced"],
        ["an unknown section is refused", movedConfig, "acme.both", "top", 0, "refused: section=\"top\" want=left|center|right"],
        ["a negative index is refused", movedConfig, "acme.both", "right", -1, "refused: index=-1 want=integer>=0"],
        ["a fractional index is refused", movedConfig, "acme.both", "right", 1.5, "refused: index=1.5 want=integer>=0"],
    ];
    for (const [name, config, id, section, index, want] of moveRefusalRows)
        check("moveRefusal: " + name, ctx.moveRefusal(config, manifests[id], section, index, "vgs.bar"), want);

    // Entries hold their ids alone, so each row tells two entries of one id
    // apart by where they stand.
    const moveUser = { version: 3, bar: { id: "vgs.bar", layout: {
        left: [{ id: "vgs.workspaces" }, { id: "acme.both" }, { id: "acme.widget" }],
        center: [{ id: "vgs.clock" }, { id: "acme.both" }],
        right: []
    } }, plugins: [{ id: "acme.both", label: "row" }] };
    const moveEffective = configLogic.effectiveConfig(shipped, moveUser);
    const ws = { id: "vgs.workspaces" }, both = { id: "acme.both" }, widget = { id: "acme.widget" }, clockEntry = { id: "vgs.clock" };
    const moveRows = [
        ["within a section forward", moveUser, moveEffective, { section: "left", nth: 0 }, "left", 2, { left: [ws, widget, both], center: [clockEntry, both], right: [] }],
        ["within a section back", moveUser, moveEffective, { section: "left", nth: 0 }, "left", 0, { left: [both, ws, widget], center: [clockEntry, both], right: [] }],
        ["across sections", moveUser, moveEffective, { section: "left", nth: 0 }, "right", 0, { left: [ws, widget], center: [clockEntry, both], right: [both] }],
        ["into an empty section", moveUser, moveEffective, { section: "center", nth: 0 }, "right", 0, { left: [ws, both, widget], center: [clockEntry], right: [both] }],
        ["index past the end clamps", moveUser, moveEffective, { section: "left", nth: 0 }, "center", 99, { left: [ws, widget], center: [clockEntry, both, both], right: [] }],
        ["the source section's entry moves, not another section's", moveUser, moveEffective, { section: "center", nth: 0 }, "left", 1, { left: [ws, both, both, widget], center: [clockEntry], right: [] }],
        ["a null source moves the first entry in section order", moveUser, moveEffective, null, "right", 0, { left: [ws, widget], center: [clockEntry, both], right: [both] }],
    ];
    for (const [name, user, effective, from, section, index, want] of moveRows)
        check("withMoved: " + name, ctx.withMoved(user, manifests["acme.both"], from, section, index, effective).bar.layout, want);
    check("withMoved: a move keeps the plugins row", ctx.withMoved(moveUser, manifests["acme.both"], { section: "left", nth: 0 }, "right", 0, moveEffective).plugins, [{ id: "acme.both", label: "row" }]);
    const duplicateMoveUser = { version: 3, bar: { id: "vgs.bar", layout: { left: [{ id: "acme.both" }, { id: "vgs.workspaces" }, { id: "acme.both" }], center: [], right: [] } } };
    check("withMoved: from nth 1 moves the second copy", ctx.withMoved(duplicateMoveUser, manifests["acme.both"], { section: "left", nth: 1 }, "right", 0, configLogic.effectiveConfig(shipped, duplicateMoveUser)).bar.layout,
        { left: [both, ws], center: [], right: [both] });
    check("withMoved: seeds the user bar from the effective bar", ctx.withMoved(null, manifests["vgs.clock"], null, "right", 0, shipped).bar.layout.right, [{ id: "vgs.clock" }]);
    check("withMoved does not alias the user file", (() => { const u = ctx.clone(moveUser); const out = ctx.withMoved(u, manifests["acme.both"], { section: "left", nth: 0 }, "right", 0, moveEffective); out.bar.layout.right[0].id = "moved"; return u.bar.layout.left[1].id; })(), "acme.both");
    check("withMoved: moving to the same slot keeps the layout", ctx.withMoved(moveUser, manifests["acme.both"], { section: "left", nth: 0 }, "left", 1, moveEffective).bar.layout, moveUser.bar.layout);

    const dropSections = {
        left: { x: 0, width: 300, widgets: [{ x: 20, width: 40, locator: { id: "a.one", section: "left", nth: 0 } }, { x: 90, width: 40, locator: { id: "a.two", section: "left", nth: 0 } }] },
        center: { x: 300, width: 300, widgets: [{ x: 360, width: 40, locator: { id: "a.three", section: "center", nth: 0 } }] },
        right: { x: 600, width: 300, widgets: [] }
    };
    const dropRows = [
        ["left zone before first centre", 900, 30, "left", { id: "a.one", section: "left", nth: 0 }, 20],
        ["left zone after a centre", 900, 80, "left", { id: "a.two", section: "left", nth: 0 }, 90],
        ["left zone at end", 900, 200, "left", null, 130],
        ["center zone", 900, 360, "center", { id: "a.three", section: "center", nth: 0 }, 360],
        ["right empty zone", 900, 760, "right", null, 750],
    ];
    for (const [name, width, x, section, before, markerX] of dropRows) {
        const got = ctx.barDropTarget(width, x, dropSections);
        check("barDropTarget: " + name, [got.section, got.before, got.markerX], [section, before, markerX]);
    }
    // A right section the bar scrolls: its view runs from beside the
    // centre to the bar edge, left of two thirds too; it shows a.s1 to
    // a.s3 whole; a.h1 lies under the start button and a.a1 after them.
    const right = (id, x) => ({ x: x, width: 40, locator: { id: id, section: "right", nth: 0 } });
    const scrolledSections = {
        left: { x: 0, width: 100, widgets: [] },
        center: { x: 400, width: 100, widgets: [{ x: 400, width: 100, locator: { id: "a.clock", section: "center", nth: 0 } }] },
        right: { x: 440, width: 440, view: { x: 520, width: 360 }, shown: { x: 556, width: 288 },
            widgets: [right("a.h1", 515), right("a.s1", 560), right("a.s2", 650), right("a.s3", 790), right("a.a1", 838)] }
    };
    const scrolledRows = [
        ["a side view left of two thirds takes the drop", 570, "right", "a.s1", 560],
        ["before the first shown widget lands before it, not among the hidden", 530, "right", "a.s1", 560],
        ["between shown widgets lands between them", 640, "right", "a.s2", 650],
        ["past the last shown widget lands beside it, before the hidden next", 860, "right", "a.a1", 830],
        ["the gap beside the view keeps the thirds", 510, "center", null, 500],
    ];
    for (const [name, x, section, before, markerX] of scrolledRows) {
        const got = ctx.barDropTarget(900, x, scrolledSections);
        check("barDropTarget: " + name, [got.section, got.before === null ? null : got.before.id, got.markerX], [section, before, markerX]);
    }
    const indexConfig = { bar: { layout: { left: [{ id: "a.one" }, { id: "a.two" }, { id: "a.one" }], center: [{ id: "a.three" }], right: [] } } };
    check("barDropIndex: before maps to the index after removal", ctx.barDropIndex(indexConfig, "left", { id: "a.one", section: "left", nth: 1 }, { section: "left", nth: 0 }, "a.one"), 1);
    check("barDropIndex: before in another section keeps its index", ctx.barDropIndex(indexConfig, "left", { id: "a.two", section: "left", nth: 0 }, { section: "center", nth: 0 }, "a.three"), 1);
    check("barDropIndex: before nth 1 selects the second matching locator", ctx.barDropIndex(indexConfig, "left", { id: "a.one", section: "left", nth: 1 }, { section: "center", nth: 0 }, "a.three"), 2);
    check("barDropIndex: a null before maps to the end after removal", ctx.barDropIndex(indexConfig, "left", null, { section: "left", nth: 0 }, "a.one"), 2);

    // firstPresence: an unnamed widget is placed; a plugin the user
    // disabled, hid (its row), already placed or without a widget is not.
    const presenceRows = [
        ["every unnamed widget, sorted", shipped, ["acme.both", "acme.pane", "acme.widget", "vgs.widgetpanel"]],
        ["a widget with a plugins row keeps no presence", configLogic.effectiveConfig(shipped, { plugins: [{ id: "acme.both" }] }), ["acme.pane", "acme.widget", "vgs.widgetpanel"]],
        ["a disabled widget keeps no presence", configLogic.effectiveConfig(shipped, { disabledPlugins: ["acme.widget"] }), ["acme.both", "acme.pane", "vgs.widgetpanel"]],
        ["a placed widget is not placed again", configLogic.effectiveConfig(shipped, { bar: { id: "vgs.bar", layout: { left: [], center: [], right: [{ id: "acme.pane" }] } } }), ["acme.both", "acme.widget", "vgs.clock", "vgs.widgetpanel", "vgs.workspaces"]],
    ];
    for (const [name, config, want] of presenceRows) check("firstPresence: " + name, ctx.firstPresence(manifests, config), want);
    check("firstPresence: a plugin with no widget is never placed", ctx.firstPresence({ "vgs.svc": manifests["vgs.svc"] }, shipped), []);
    // landsShown rows: [id, want]. What `vgshell plugin add` tells the user.
    for (const [id, want] of [["acme.both", true], ["acme.widget", true], ["vgs.widgetpanel", true], ["acme.svc", false], ["vgs.bar", false]])
        check("landsShown: " + id, ctx.landsShown(manifests[id]), want);
    const given = ctx.withFirstPresence(null, manifests, shipped);
    check("withFirstPresence: places each widget at the end of its default section", given.bar.layout, { left: [{ id: "vgs.workspaces" }], center: [{ id: "vgs.clock" }, { id: "acme.widget" }], right: [{ id: "acme.both" }, { id: "acme.pane" }, { id: "vgs.widgetpanel" }] });
    check("withFirstPresence: lists nothing and disables nothing", [given.plugins, given.disabledPlugins], [undefined, undefined]);
    check("withFirstPresence: every placed widget reads enabled", ["acme.both", "acme.widget", "vgs.widgetpanel"].map(id => ctx.isEnabled(configLogic.effectiveConfig(shipped, given), manifests[id], "vgs.bar")), [true, true, true]);
    check("withFirstPresence: a second pass names nothing", ctx.firstPresence(manifests, configLogic.effectiveConfig(shipped, given)), []);
    // A widget the user hid stays out when an update brings a new widget:
    // only the new one is placed, and a restart, which reads the same file,
    // names nothing.
    const hidden = ctx.withPlaced(given, manifests["vgs.widgetpanel"], false, configLogic.effectiveConfig(shipped, given));
    const fresh = ctx.validateManifest(Object.assign({}, clock, { id: "vgs.fresh", defaultSection: "right" }), "/p").manifest;
    const updated = Object.assign({}, manifests, { "vgs.fresh": fresh });
    check("firstPresence: after a hide and an update only the new widget is named", ctx.firstPresence(updated, configLogic.effectiveConfig(shipped, hidden)), ["vgs.fresh"]);
    const afterUpdate = ctx.withFirstPresence(hidden, updated, configLogic.effectiveConfig(shipped, hidden));
    check("withFirstPresence: after a hide and an update the new widget is placed and the hidden one is not", ["vgs.fresh", "vgs.widgetpanel"].map(id => ctx.isPlaced(configLogic.effectiveConfig(shipped, afterUpdate), updated[id])), [true, false]);
    check("firstPresence: a restart over the written file names nothing", ctx.firstPresence(updated, configLogic.effectiveConfig(shipped, afterUpdate)), []);

    // enablementRule rows: [id, want].
    for (const [id, want] of [["vgs.bar", "bar"], ["vgs.barpanel", "bar"], ["vgs.clock", "widget"], ["acme.widget", "widget"], ["vgs.svc", "first-party"], ["vgs.widgetpanel", "first-party"], ["acme.svc", "row"], ["acme.both", "row"]])
        check("enablementRule: " + id, ctx.enablementRule(manifests[id]), want);
    // A plugin whose manifest sets `alwaysOn` stays on whatever the
    // configuration lists, and the core refuses to disable it.
    const alwaysOn = ctx.validateManifest(Object.assign({}, svc, { id: "vgs.always", alwaysOn: true }), "/p").manifest;
    check("isEnabled: an alwaysOn plugin listed in disabledPlugins is on", ctx.isEnabled(configLogic.effectiveConfig(shipped, { disabledPlugins: ["vgs.always"] }), alwaysOn, "vgs.bar"), true);
    check("isEnabled: a plugin without alwaysOn listed in disabledPlugins is off", ctx.isEnabled(configLogic.effectiveConfig(shipped, { disabledPlugins: ["vgs.svc"] }), manifests["vgs.svc"], "vgs.bar"), false);
    check("enabledRefusal: an alwaysOn plugin refuses a disable", ctx.enabledRefusal(alwaysOn, false), "refused: enabled=vgs.always reason=always-on");
    check("enabledRefusal: an alwaysOn plugin takes an enable", ctx.enabledRefusal(alwaysOn, true), "");
    check("enabledRefusal: a plugin without alwaysOn takes a disable", ctx.enabledRefusal(manifests["vgs.svc"], false), "");
    const alwaysWidget = ctx.validateManifest(Object.assign({}, svc, { id: "vgs.alwayswidget", kinds: ["service", "bar-widget"], entryPoints: { service: "S.qml", "bar-widget": "W.qml" }, alwaysOn: true }), "/p").manifest;
    const alwaysPlaced = configLogic.effectiveConfig(shipped, { disabledPlugins: ["vgs.alwayswidget"], bar: { id: "vgs.bar", layout: { left: [], center: [], right: [{ id: "vgs.alwayswidget" }] } } });
    check("moveRefusal: an alwaysOn widget a disabledPlugins row names still moves", ctx.moveRefusal(alwaysPlaced, alwaysWidget, "left", 0, "vgs.bar"), "");
    // Plugins, the manager, is the plugin the owner made always on.
    const shippedSettings = ctx.validateManifest(JSON.parse(fs.readFileSync(path.join(__dirname, "..", "shell", "plugins", "vgs.settings", "manifest.json"), "utf8")), "/p");
    check("enabledRefusal: the shipped Plugins manifest refuses a disable", shippedSettings.ok ? ctx.enabledRefusal(shippedSettings.manifest, false) : shippedSettings.error, "refused: enabled=vgs.settings reason=always-on");

    // The enum values a configuration written under the plain-string
    // option form may hold: [plugin, setting, list item field or null,
    // values]. Each still writes and reads back as it is.
    const STORED_ENUMS = [
        ["vgs.agent-warden", "notify", null, ["problems", "everything", "off"]],
        ["vgs.ai-usage", "view", null, ["compact", "full"]],
        ["vgs.capture", "processing", null, ["save-copy", "copy", "save"]],
        ["vgs.capture", "audio", null, ["none", "desktop", "microphone", "both"]],
        ["vgs.capture", "quality", null, ["medium", "high", "very_high", "ultra"]],
        ["vgs.capture", "codec", null, ["auto", "h264", "hevc", "av1", "vp9"]],
        ["vgs.displays", "keysTarget", null, ["focused", "all"]],
        ["vgs.jarvis", "mode", null, ["hold", "toggle", "always"]],
        ["vgs.jarvis", "voiceProvider", null, ["local", "realtime", "gemini", "elevenlabs"]],
        ["vgs.jarvis", "taskTerminal", null, ["auto", "tmux", "floating"]],
        ["vgs.jarvis", "cloudVision", null, ["ask", "allow", "never"]],
        ["vgs.mouse", "accelProfile", null, ["adaptive", "flat"]],
        ["vgs.notifications", "position", null, ["top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right"]],
        ["vgs.power", "chargerProfile", null, ["power-saver", "balanced", "performance"]],
        ["vgs.power", "batteryProfile", null, ["power-saver", "balanced", "performance"]],
        ["vgs.scratchpads", "pads", "position", ["center", "top", "bottom", "left", "right", "top-left", "top-right", "bottom-left", "bottom-right"]],
        ["vgs.scratchpads", "pads", "entry", ["top", "bottom", "left", "right"]],
        ["vgs.scratchpads", "pads", "motion", ["slide", "fade", "none"]],
        ["vgs.sysmon", "layout", null, ["Stacked", "One line"]],
        ["vgs.sysmon", "labelStyle", null, ["icons", "text"]],
        ["vgs.sysmon", "temperatureUnit", null, ["Celsius", "Fahrenheit"]],
        ["vgs.sysmon", "memoryUnit", null, ["percent", "used"]],
        ["vgs.themes", "placement", null, ["top-left", "top", "top-right", "left", "center", "right", "bottom-left", "bottom", "bottom-right"]],
        ["vgs.traffic", "layout", null, ["Stacked", "One line"]],
        ["vgs.traffic", "labelStyle", null, ["icons", "text"]],
        ["vgs.traffic", "show", null, ["both", "download", "upload"]],
        ["vgs.updates", "snapshot", null, ["auto", "off"]],
        ["vgs.voice", "osd", null, ["plasma", "ring", "off"]]
    ];
    for (const [id, key, field, values] of STORED_ENUMS) {
        const judged = ctx.validateManifest(JSON.parse(fs.readFileSync(path.join(__dirname, "..", "shell", "plugins", id, "manifest.json"), "utf8")), "/p");
        const got = !judged.ok ? [judged.error] : values.map(value => {
            const stored = field === null ? value : [Object.assign({ name: "stored" }, judged.manifest.schema[key].defaults, { [field]: value })];
            const refusal = ctx.settingRefusal(judged.manifest, key, stored);
            const read = refusal !== "" ? refusal : ctx.settingsFor({ plugins: [{ id: id, [key]: stored }] }, judged.manifest)[key];
            return field === null || typeof read === "string" ? read : read[0][field];
        });
        check("a stored enum value reads unchanged: " + id + " " + key + (field === null ? "" : "." + field), got, values);
    }

    // A plugin with a settings schema, for the setting rows.
    const tunable = ctx.validateManifest({ schemaVersion: 1, id: "acme.tune", name: "T", version: "1", author: "a", description: "d", kinds: ["service", "bar-widget"], entryPoints: { service: "S.qml", "bar-widget": "W.qml" },
        settings: { label: "x", size: 2, on: true, mode: "a", free: 1, limit: 8, box: { a: 1 } },
        schema: { label: { type: "string", label: "Label", presets: [{ value: "x" }], allowCustom: true }, size: { type: "number", label: "Size" }, on: { type: "boolean", label: "On" }, mode: { type: "enum", label: "Mode", options: [{ value: "a", label: "A" }, { value: "b", label: "B" }] }, limit: { type: "number", label: "Limit", min: 2, max: 30, step: 1, group: "Timing" } } }, "/p").manifest;
    if (tunable === undefined) throw new Error("fixture manifest refused: acme.tune");

    // settingRefusal rows: [name, key, value, want]
    // notifyOptions: one row per rule. A refusal row names the key its
    // error starts with.
    const notifyRows = [
        ["a title alone", { title: "Saved" }, { ok: true, value: { title: "Saved", message: "", tone: "", icon: "", urgency: "normal", transient: false } }],
        ["every key", { title: "Saved", message: "to disk", tone: "success", icon: "circle-check", urgency: "low", transient: true }, { ok: true, value: { title: "Saved", message: "to disk", tone: "success", icon: "circle-check", urgency: "low", transient: true } }],
        ["a message at the ceiling", { title: "t", message: "x".repeat(600) }, { ok: true, value: { title: "t", message: "x".repeat(600), tone: "", icon: "", urgency: "normal", transient: false } }],
        ["not an object", "Saved", "options"],
        ["an unknown key", { title: "Saved", duration: 0 }, "duration"],
        ["a missing title", { message: "x" }, "title"],
        ["a title that is not a string", { title: 4 }, "title"],
        ["a blank title", { title: " " }, "title"],
        ["a title past the ceiling", { title: "x".repeat(121) }, "title"],
        ["a message that is not a string", { title: "t", message: 4 }, "message"],
        ["a message past the ceiling", { title: "t", message: "x".repeat(601) }, "message"],
        ["a tone the hint does not take", { title: "t", tone: "neutral" }, "tone"],
        ["an icon that is not a string", { title: "t", icon: ["camera"] }, "icon"],
        ["an icon outside the Lucide grammar", { title: "t", icon: "Camera" }, "icon"],
        ["an icon past the ceiling", { title: "t", icon: "a".repeat(65) }, "icon"],
        ["an unknown urgency", { title: "t", urgency: "high" }, "urgency"],
        ["a transient that is not a boolean", { title: "t", transient: "yes" }, "transient"]
    ];
    for (const [name, raw, want] of notifyRows) {
        const got = ctx.notifyOptions(raw);
        if (typeof want === "string") check("notifyOptions: " + name, got.ok === false && got.error.split(" ")[0] === want, true);
        else check("notifyOptions: " + name, got, want);
    }
    // notifyArgv: [name, options, argv]. The message is a body the server
    // reads as markup, so its `&`, `<` and `>` arrive escaped. A page
    // reference reads as its words, and one that names a page also rides
    // whole in x-vgs-page.
    const notifyArgvRows = [
        ["the defaults", { title: "Saved" }, ["notify-send", "--app-name=Acme", "--urgency=normal", "--hint=string:x-vgs-click:none", "--hint=string:x-vgs-plugin:acme.probe", "--", "Saved", ""]],
        ["every key", { title: "Saved", message: "to disk", tone: "danger", icon: "camera", urgency: "critical", transient: true },
            ["notify-send", "--app-name=Acme", "--urgency=critical", "--hint=string:x-vgs-click:none", "--hint=string:x-vgs-plugin:acme.probe", "--hint=string:x-vgs-tone:danger", "--hint=string:x-vgs-icon:camera", "--transient", "--", "Saved", "to disk"]],
        ["markup in the message", { title: "<b>a</b> & b", message: "<b>bold</b> & a>b" },
            ["notify-send", "--app-name=Acme", "--urgency=normal", "--hint=string:x-vgs-click:none", "--hint=string:x-vgs-plugin:acme.probe", "--", "<b>a</b> & b", "&lt;b&gt;bold&lt;/b&gt; &amp; a&gt;b"]],
        ["a title that starts like an option", { title: "--urgency=low" }, ["notify-send", "--app-name=Acme", "--urgency=normal", "--hint=string:x-vgs-click:none", "--hint=string:x-vgs-plugin:acme.probe", "--", "--urgency=low", ""]],
        ["a page reference in the message", { title: "Voice", message: "Set it up on the [Voice page](page:vgs.voice/Setup)." },
            ["notify-send", "--app-name=Acme", "--urgency=normal", "--hint=string:x-vgs-click:none", "--hint=string:x-vgs-plugin:acme.probe", "--hint=string:x-vgs-page:[Voice page](page:vgs.voice/Setup)", "--", "Voice", "Set it up on the Voice page."]],
        ["a page reference with no tab", { title: "Voice", message: "[Voice](page:vgs.voice) is off." },
            ["notify-send", "--app-name=Acme", "--urgency=normal", "--hint=string:x-vgs-click:none", "--hint=string:x-vgs-plugin:acme.probe", "--hint=string:x-vgs-page:[Voice](page:vgs.voice)", "--", "Voice", "Voice is off."]],
        ["a reference to no page", { title: "Voice", message: "Turn it on in [Plugins](page:)." },
            ["notify-send", "--app-name=Acme", "--urgency=normal", "--hint=string:x-vgs-click:none", "--hint=string:x-vgs-plugin:acme.probe", "--", "Voice", "Turn it on in Plugins."]],
        ["a page reference beside markup", { title: "Voice", message: "<b>[Voice](page:vgs.voice)</b> & a>b" },
            ["notify-send", "--app-name=Acme", "--urgency=normal", "--hint=string:x-vgs-click:none", "--hint=string:x-vgs-plugin:acme.probe", "--hint=string:x-vgs-page:[Voice](page:vgs.voice)", "--", "Voice", "&lt;b&gt;Voice&lt;/b&gt; &amp; a&gt;b"]]
    ];
    for (const [name, raw, want] of notifyArgvRows) {
        const judged = ctx.notifyOptions(raw);
        check("notifyArgv: " + name, judged.ok ? ctx.notifyArgv("acme.probe", "Acme", judged.value) : judged.error, want);
    }
    check("the notify run ceiling is a whole number above zero", Number.isInteger(ctx.NOTIFY_RUNS_MAX) && ctx.NOTIFY_RUNS_MAX > 0, true);
    check("notify is a capability", ctx.CAPABILITIES.indexOf("notify") !== -1, true);
    check("theme is a capability", ctx.CAPABILITIES.indexOf("theme") !== -1, true);
    check("layers is a capability", ctx.CAPABILITIES.indexOf("layers") !== -1, true);
    check("requirements is a capability", ctx.CAPABILITIES.indexOf("requirements") !== -1, true);
    check("session readers coexist with a lock holder", ctx.lendRefusal({ lock: "acme.locker", session: "acme.other" }, { id: "acme.reader", capabilities: ["session"] }), "");
    check("idle is a capability", ctx.CAPABILITIES.indexOf("idle") !== -1, true);
    const handler = () => {};
    const idleRows = [
        ["one second", 1, handler, ""],
        ["a day", 86400, handler, ""],
        ["zero seconds", 0, handler, "refused: idle-timeout=0 want=1..86400"],
        ["past a day", 86401, handler, "refused: idle-timeout=86401 want=1..86400"],
        ["a fraction", 1.5, handler, "refused: idle-timeout=1.5 want=1..86400"],
        ["a string", "300", handler, "refused: idle-timeout=\"300\" want=1..86400"],
        ["no handler", 300, null, "refused: idle-handler=not-a-function"]
    ];
    for (const [name, seconds, onChange, want] of idleRows) check("idleWatchRefusal: " + name, ctx.idleWatchRefusal(seconds, onChange), want);

    const refusalRows = [
        ["a string fits a string entry", "label", "y", ""],
        ["a number fits a number entry", "size", 3.5, ""],
        ["a boolean fits a boolean entry", "on", false, ""],
        ["an option fits an enum entry", "mode", "b", ""],
        ["a setting with no schema entry takes a value of its default's type", "free", 2, ""],
        ["a setting with no schema entry refuses another type", "free", "2", "refused: setting=free want=number"],
        ["a setting with no schema entry refuses a number JSON cannot hold", "free", Infinity, "refused: setting=free want=number"],
        ["an object setting with no schema entry refuses null", "box", null, "refused: setting=box want=object"],
        ["an object setting with no schema entry refuses a list", "box", [], "refused: setting=box want=object"],
        ["a key the manifest does not declare is undeclared", "absent", 2, "refused: setting=absent undeclared"],
        ["a prototype name is undeclared", "constructor", 1, "refused: setting=constructor undeclared"],
        ["a number is not a string", "label", 1, "refused: setting=label want=string"],
        ["a numeric string is not a number", "size", "3", "refused: setting=size want=number"],
        ["NaN is not a number", "size", NaN, "refused: setting=size want=number"],
        ["a string is not a boolean", "on", "true", "refused: setting=on want=boolean"],
        ["a value outside the options", "mode", "c", "refused: setting=mode want=one-of:a|b"],
        ["a bounded number at its min fits", "limit", 2, ""],
        ["a bounded number at its max fits", "limit", 30, ""],
        ["a bounded number off its step fits", "limit", 2.5, ""],
        ["a number under the min is refused", "limit", 1, "refused: setting=limit want=at-least:2"],
        ["a number over the max is refused", "limit", 31, "refused: setting=limit want=at-most:30"],
        ["a bounded entry still wants a number", "limit", "8", "refused: setting=limit want=number"],
    ];
    for (const [name, key, value, want] of refusalRows) {
        check("settingRefusal: " + name, ctx.settingRefusal(tunable, key, value), want);
    }
    const presetManifest = ctx.validateManifest({ schemaVersion: 1, id: "acme.presets", name: "P", version: "1", author: "a", description: "d", kinds: ["service"], entryPoints: { service: "S.qml" },
        settings: { mode: "short", delay: 60, clock: "HH:mm" },
        schema: {
            mode: { type: "string", label: "Mode", presets: [{ value: "short" }, { value: "long" }] },
            delay: { type: "number", label: "Delay", presets: [{ value: 60 }, { value: 300 }], unit: "seconds" },
            clock: { type: "string", label: "Clock", presets: [{ value: "HH:mm" }], allowCustom: true, format: "datetime" }
        } }, "/p").manifest;
    if (presetManifest === undefined) throw new Error("fixture manifest refused: acme.presets");
    const presetRefusals = [
        ["a preset string fits", "mode", "long", ""],
        ["a non-preset string is refused", "mode", "other", "refused: setting=mode want=one-of-presets"],
        ["a preset number fits", "delay", 300, ""],
        ["a non-preset number is refused", "delay", 120, "refused: setting=delay want=one-of-presets"],
        ["a custom datetime format fits", "clock", "ddd HH:mm", ""],
        ["a bad datetime format is refused", "clock", "'abc", "refused: setting=clock want=datetime-format reason=unclosed-quote"],
    ];
    for (const [name, key, value, want] of presetRefusals) {
        check("settingRefusal presets: " + name, ctx.settingRefusal(presetManifest, key, value), want);
    }

    // barShown: [name, bar instance, want], the one answer BarHost maps a
    // bar's window on and the service gate counts a bar by.
    for (const [name, instance, want] of [["a bar being built", null, true], ["a bar without the property", {}, true], ["a shown bar", { shown: true }, true], ["a hidden bar", { shown: false }, false]])
        check("barShown: " + name, ctx.barShown(instance), want);

    for (const [kind, instance, want] of [
        ["background", null, false],
        ["background", {}, true],
        ["background", { shown: true }, true],
        ["background", { shown: false }, false],
        ["cover", null, false],
        ["cover", {}, false],
        ["cover", { shown: false }, false],
        ["cover", { shown: true }, true],
        ["service", { shown: true }, false],
    ])
        check("perScreenLayerShown: " + kind + " " + JSON.stringify(instance), ctx.perScreenLayerShown(kind, instance), want);
    check("perScreenLayerTakesKeyboard: first cover takes keyboard", ctx.perScreenLayerTakesKeyboard("cover", [{ name: "A" }, { name: "B" }], { name: "A" }), true);
    check("perScreenLayerTakesKeyboard: second cover takes no keyboard", ctx.perScreenLayerTakesKeyboard("cover", [{ name: "A" }, { name: "B" }], { name: "B" }), false);
    // Quickshell.screens is a QML list, which is no JS Array.
    check("perScreenLayerTakesKeyboard: a list that is no Array still gives the first cover keyboard", ctx.perScreenLayerTakesKeyboard("cover", { length: 2, 0: { name: "A" }, 1: { name: "B" } }, { name: "A" }), true);
    check("perScreenLayerTakesKeyboard: backgrounds take no keyboard", ctx.perScreenLayerTakesKeyboard("background", [{ name: "A" }], { name: "A" }), false);

    const paneRowsManifests = {};
    function paneManifest(id, name, group, order, extra) {
        return ctx.validateManifest(Object.assign({ schemaVersion: 1, id: id, name: name, version: "1", author: "a", description: "d", kinds: ["pane"], entryPoints: { pane: "Pane.qml" }, pane: { group: group, order: order } }, extra || {}), "/p").manifest;
    }
    paneRowsManifests["acme.beta"] = paneManifest("acme.beta", "Beta", "System", 2);
    paneRowsManifests["acme.alpha"] = paneManifest("acme.alpha", "Alpha", "System", 2);
    paneRowsManifests["acme.zed"] = paneManifest("acme.zed", "Alpha", "System", 2);
    paneRowsManifests["acme.user"] = paneManifest("acme.user", "User", "User", 1);
    paneRowsManifests["acme.widgetpane"] = paneManifest("acme.widgetpane", "Widget Pane", "System", 1, { kinds: ["bar-widget", "pane"], entryPoints: { "bar-widget": "Widget.qml", pane: "Pane.qml" }, defaultSection: "right", icon: "settings" });
    paneRowsManifests["acme.disabled"] = paneManifest("acme.disabled", "Disabled", "System", 0);
    paneRowsManifests["acme.svc"] = manifests["acme.svc"];
    const paneConfig = configLogic.effectiveConfig(shipped, { bar: { id: "vgs.bar", layout: { left: [], center: [], right: [{ id: "acme.widgetpane" }] } }, plugins: [{ id: "acme.beta" }, { id: "acme.alpha" }, { id: "acme.zed" }, { id: "acme.user" }, { id: "acme.disabled" }], disabledPlugins: ["acme.disabled"] });
    check("paneRows: enabled panes are grouped, ordered, named and tied by id", ctx.paneRows(paneConfig, paneRowsManifests, "vgs.bar").map(r => [r.id, r.group, r.order, r.placed, r.hasWidget, r.icon]),
        [["acme.widgetpane", "System", 1, true, true, "settings"], ["acme.alpha", "System", 2, false, false, "package"], ["acme.zed", "System", 2, false, false, "package"], ["acme.beta", "System", 2, false, false, "package"], ["acme.user", "User", 1, false, false, "package"]]);
    const holderManifests = {
        "acme.host-b": ctx.validateManifest(Object.assign({}, bar, { id: "acme.host-b", kinds: ["window"], entryPoints: { window: "Window.qml" }, capabilities: ["panes"] }), "/p").manifest,
        "acme.host-a": ctx.validateManifest(Object.assign({}, bar, { id: "acme.host-a", kinds: ["window"], entryPoints: { window: "Window.qml" }, capabilities: ["panes"] }), "/p").manifest,
        "acme.disabled-host": ctx.validateManifest(Object.assign({}, bar, { id: "acme.disabled-host", kinds: ["window"], entryPoints: { window: "Window.qml" }, capabilities: ["panes"] }), "/p").manifest,
    };
    const holderConfig = { plugins: [{ id: "acme.host-b" }, { id: "acme.host-a" }, { id: "acme.disabled-host" }], disabledPlugins: ["acme.disabled-host"] };
    check("panesHolderId: the enabled holder is selected by id", ctx.panesHolderId(holderConfig, holderManifests, "vgs.bar"), "acme.host-a");
    check("panesHolderId: no enabled holder is empty", ctx.panesHolderId({ plugins: [] }, holderManifests, "vgs.bar"), "");

    // withSetting rows: [name, user, effective, path, want]. The row is the
    // one place a setting lives, a placed widget's included.
    const tunePlaced = configLogic.effectiveConfig(shipped, { bar: { id: "vgs.bar", layout: { left: [], center: [], right: [{ id: "acme.tune" }] } } });
    const shippedTune = Object.assign({}, tunePlaced, { plugins: [{ id: "acme.tune", size: 9 }] });
    const settingRows = [
        ["adds a row with the id", null, tunePlaced, "plugins", [{ id: "acme.tune", label: "new" }]],
        ["seeds the row from the effective row", null, shippedTune, "plugins", [{ id: "acme.tune", size: 9, label: "new" }]],
        ["updates the user row in place", { plugins: [{ id: "acme.tune", size: 4 }, { id: "b.c" }] }, shippedTune, "plugins", [{ id: "acme.tune", size: 4, label: "new" }, { id: "b.c" }]],
        ["leaves a placed widget's layout entry alone", { bar: { id: "vgs.bar", layout: { left: [], center: [], right: [{ id: "acme.tune" }] } } }, tunePlaced, "bar.layout.right", [{ id: "acme.tune" }]],
        ["seeds no bar key", null, tunePlaced, "bar", undefined],
        ["writes version 3", null, tunePlaced, "version", 3],
    ];
    for (const [name, user, effective, p, want] of settingRows) {
        check("withSetting: " + name, dig(ctx.withSetting(user, tunable, "label", "new", effective), p), want);
    }
    check("withSetting does not alias the user file", (() => { const u = { plugins: [{ id: "acme.tune", size: 4 }] }; ctx.withSetting(u, tunable, "label", "new", shippedTune); return u.plugins[0]; })(), { id: "acme.tune", size: 4 });

    // withoutSetting rows: [name, user, path, want]
    const labelled = { bar: { id: "vgs.bar", layout: { left: [{ id: "acme.tune" }], center: [{ id: "b.c" }], right: [] } }, plugins: [{ id: "acme.tune", label: "p", size: 4 }, { id: "b.c", label: "other" }] };
    const unsetRows = [
        ["removes the key from the row and keeps its others", labelled, "plugins", [{ id: "acme.tune", size: 4 }, { id: "b.c", label: "other" }]],
        ["leaves the layout alone", labelled, "bar.layout", { left: [{ id: "acme.tune" }], center: [{ id: "b.c" }], right: [] }],
        ["a file with no row seeds none", null, "plugins", undefined],
        ["a file with no bar seeds none", null, "bar", undefined],
        ["writes version 3", null, "version", 3],
    ];
    for (const [name, user, p, want] of unsetRows) {
        check("withoutSetting: " + name, dig(ctx.withoutSetting(user, tunable, "label"), p), want);
    }
    // Both ordinary writers must filter the row they update, and keep every
    // other row and key intact.
    const savedTune = { version: 3, extra: "kept", plugins: [
        { id: "acme.tune", label: "p", size: 0, on: false, retired: "old", keys: { toggle: "SUPER+A" } },
        { id: "acme.gone", retired: "unrelated" }
    ], bar: { layout: { left: [{ id: "acme.tune" }], center: [], right: [] } } };
    const savedBefore = JSON.stringify(savedTune);
    const writeRows = [
        ["set", "set", "plugins.0", { id: "acme.tune", label: "new", size: 0, on: false, keys: { toggle: "SUPER+A" } }],
        ["reset", "reset", "plugins.0", { id: "acme.tune", size: 0, on: false, keys: { toggle: "SUPER+A" } }],
        ["set inherited", "seed", "plugins.0", { id: "acme.tune", label: "new", size: 0, on: false, keys: { toggle: "SUPER+A" } }],
    ];
    for (const [name, operation, at, want] of writeRows) {
        const out = operation === "reset" ? ctx.withoutSetting(savedTune, tunable, "label")
            : ctx.withSetting(operation === "seed" ? null : savedTune, tunable, "label", "new", savedTune);
        check("ordinary setting write silently drops retired keys: " + name, dig(out, at), want);
        check("ordinary setting write leaves caller data intact: " + name, JSON.stringify(savedTune), savedBefore);
        if (operation !== "seed") {
            check("ordinary setting write keeps unknown ids: " + name, out.plugins[1], { id: "acme.gone", retired: "unrelated" });
            check("ordinary setting write keeps unrelated top-level keys: " + name, out.extra, "kept");
            check("ordinary setting write leaves the layout intact: " + name, out.bar, savedTune.bar);
        }
    }
    check("withoutSetting does not alias the user file", (() => { const u = { plugins: [{ id: "acme.tune", label: "p" }] }; ctx.withoutSetting(u, tunable, "label"); return u.plugins[0]; })(), { id: "acme.tune", label: "p" });

    // lendRefusal rows: [name, held, capabilities, want]
    const lendRows = [
        ["a free exclusive capability lends", {}, ["lock"], ""],
        ["an exclusive capability held by another plugin refuses", { lock: "acme.other" }, ["lock", "run"], "refused: capability=lock held-by=acme.other"],
        ["a plugin may hold what it already holds", { polkit: "acme.tune" }, ["polkit"], ""],
        ["a shared capability is never refused", { lock: "acme.other" }, ["run", "screens"], ""],
        ["the Bluetooth agent held by another plugin refuses", { bluetoothAgent: "acme.other" }, ["bluetoothAgent", "ipc"], "refused: capability=bluetoothAgent held-by=acme.other"],
        ["the outputs reading serves every plugin that names it", { monitors: "acme.other" }, ["monitors", "ipc"], ""],
        ["the panes holder serves one plugin", { panes: "acme.other" }, ["panes", "ipc"], "refused: capability=panes held-by=acme.other"],
    ];
    for (const [name, held, capabilities, want] of lendRows) {
        check("lendRefusal: " + name, ctx.lendRefusal(held, Object.assign({}, tunable, { capabilities: capabilities })), want);
    }

    // unknownIds rows: [name, config, want]. `manifests` knows vgs.bar,
    // vgs.clock, vgs.workspaces, vgs.svc and acme.svc.
    const unknownRows = [
        ["a configuration naming only known ids reports none", { disabledPlugins: ["vgs.clock"], plugins: [{ id: "acme.svc" }] }, []],
        ["a disabled id no plugin has is reported under disabledPlugins", { disabledPlugins: ["vgs.clock", "vgs.background"] }, [{ id: "vgs.background", key: "disabledPlugins" }]],
        ["a plugins row no plugin has is reported under plugins", { plugins: [{ id: "acme.svc" }, { id: "vgs.background", x: 1 }] }, [{ id: "vgs.background", key: "plugins" }]],
        ["an id in both keys is reported once per key, disabledPlugins first", { plugins: [{ id: "acme.gone" }], disabledPlugins: ["acme.gone"] }, [{ id: "acme.gone", key: "disabledPlugins" }, { id: "acme.gone", key: "plugins" }]],
        ["an id listed twice in one key is reported once", { disabledPlugins: ["acme.gone", "acme.gone"] }, [{ id: "acme.gone", key: "disabledPlugins" }]],
        ["ids are reported in list order", { disabledPlugins: ["b.gone", "a.gone"] }, [{ id: "b.gone", key: "disabledPlugins" }, { id: "a.gone", key: "disabledPlugins" }]],
        ["a configuration without either key reports none", {}, []],
    ];
    for (const [name, config, want] of unknownRows) {
        check("unknownIds: " + name, ctx.unknownIds(config, manifests), want);
    }

    // surfacePlacement rows: [name, kind, settings, want subset]
    const placementRows = [
        ["an overlay fills its screen on the overlay layer", "overlay", {}, { anchors: { top: true, bottom: true, left: true, right: true }, exclusion: "ignore", layer: "overlay", placement: "fill" }],
        ["no placement setting centres on the whole monitor", "panel", {}, { anchors: { top: false, bottom: false, left: false, right: false }, exclusion: "ignore", layer: "top", placement: "center" }],
        ["center ignores reserved space", "menu", { placement: "center" }, { exclusion: "ignore", placement: "center" }],
        ["top-right keeps clear of reserved space", "panel", { placement: "top-right" }, { exclusion: "normal" }],
        ["top-right keeps a gap from both edges", "panel", { placement: "top-right" }, { anchors: { top: true, bottom: false, left: false, right: true }, margins: { top: 8, bottom: 0, left: 0, right: 8 }, placement: "top-right" }],
        ["bottom anchors one edge", "menu", { placement: "bottom" }, { anchors: { top: false, bottom: true, left: false, right: false }, layer: "overlay", placement: "bottom" }],
        ["an unknown placement is reported and centres", "panel", { placement: "middle" }, { placement: "center", error: "placement=\"middle\" unknown" }],
    ];
    for (const [name, kind, settings, want] of placementRows) {
        const got = ctx.surfacePlacement(kind, settings, 8);
        const picked = {};
        for (const k of Object.keys(want)) picked[k] = got[k];
        check("surfacePlacement: " + name, picked, want);
    }

    // A plugin with two Hyprland binds, for the key rows.
    const keyed = ctx.validateManifest({ schemaVersion: 1, id: "acme.keys", name: "K", version: "1", author: "a", description: "d", kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["shortcut"],
        hyprland: { binds: [{ shortcut: "toggle", key: "super+m", info: "Opens or closes it." }, { shortcut: "peek", key: "SUPER+P" }] } }, "/p").manifest;
    if (keyed === undefined) throw new Error("fixture manifest refused: acme.keys");
    const tapKeyed = ctx.validateManifest({ schemaVersion: 1, id: "acme.tap", name: "T", version: "1", author: "a", description: "d", kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["shortcut"],
        hyprland: { binds: [{ shortcut: "tap", key: null, tap: true }] } }, "/p").manifest;
    if (tapKeyed === undefined) throw new Error("fixture manifest refused: acme.tap");

    // keyRefusal rows: [name, manifest, shortcut, key, want]
    const keyRefusalRows = [
        ["a declared shortcut takes a key", keyed, "toggle", "ctrl+super+k", ""],
        ["Settings accepts a keycode", keyed, "toggle", "shift+super+CODE:00108", ""],
        ["null unbinds a declared shortcut", keyed, "toggle", null, ""],
        ["undefined resets a declared shortcut", keyed, "toggle", undefined, ""],
        ["a tap shortcut takes a lone key", tapKeyed, "tap", "code:108", ""],
        ["a tap shortcut takes a list of lone keys", tapKeyed, "tap", ["CODE:00108", "code:105"], ""],
        ["an empty key list is refused", keyed, "toggle", [], "refused: key=toggle must not be an empty list"],
        ["a bad key list entry names its index", keyed, "toggle", ["SUPER+K", "SUPER+"], "refused: key=toggle.1 has an empty part: \"SUPER+\""],
        ["a repeated key list entry is refused", keyed, "toggle", ["CODE:00108", "code:108"], "refused: key=toggle.1 repeats code:108"],
        ["a tap shortcut refuses modifiers", tapKeyed, "tap", "SUPER+code:108", "refused: key=tap tap-lone-key"],
        ["a tap shortcut refuses modifiers in a list", tapKeyed, "tap", ["code:108", "SUPER+code:105"], "refused: key=tap.1 tap-lone-key"],
        ["an undeclared shortcut is refused", keyed, "other", "SUPER+K", "refused: key=other undeclared"],
        ["a prototype name is undeclared", keyed, "constructor", "SUPER+K", "refused: key=constructor undeclared"],
        ["a plugin without binds declares none", manifests["acme.svc"], "toggle", "SUPER+K", "refused: key=toggle undeclared"],
        ["a key that is not a string or list is refused", keyed, "toggle", 5, "refused: key=toggle want=string-list-or-null"],
        ["a malformed key is refused with the key judge's words", keyed, "toggle", "SUPER+", "refused: key=toggle has an empty part: \"SUPER+\""],
    ];
    for (const [name, manifest, shortcut, key, want] of keyRefusalRows) {
        check("keyRefusal: " + name, ctx.keyRefusal(manifest, shortcut, key), want);
    }

    // withKey rows: [name, user, effective, shortcut, key, path, want]
    const keyRow = { version: 3, plugins: [{ id: "acme.keys", x: 1, keys: { toggle: "SUPER+K" } }] };
    const keyRows = [
        ["a key is written normalised into a new row", null, {}, "toggle", "ctrl+super+k", "plugins", [{ id: "acme.keys", keys: { toggle: "SUPER+CTRL+K" } }]],
        ["Settings writes a normalized keycode", null, {}, "toggle", "shift+super+CODE:00108", "plugins", [{ id: "acme.keys", keys: { toggle: "SUPER+SHIFT+code:108" } }]],
        ["a key list is written normalised into a new row", null, {}, "toggle", ["shift+super+CODE:00108", "code:105"], "plugins", [{ id: "acme.keys", keys: { toggle: ["SUPER+SHIFT+code:108", "code:105"] } }]],
        ["a one-key list is written as one string", null, {}, "toggle", ["code:105"], "plugins", [{ id: "acme.keys", keys: { toggle: "code:105" } }]],
        ["null is written as an unbind", null, {}, "toggle", null, "plugins", [{ id: "acme.keys", keys: { toggle: null } }]],
        ["the row is seeded from the effective row", null, { plugins: [{ id: "acme.keys", x: 1 }] }, "peek", "SUPER+Q", "plugins", [{ id: "acme.keys", x: 1, keys: { peek: "SUPER+Q" } }]],
        ["the user row is updated in place", { plugins: [{ id: "b.c" }, { id: "acme.keys", keys: { peek: "SUPER+Q" } }] }, {}, "toggle", "SUPER+K", "plugins", [{ id: "b.c" }, { id: "acme.keys", keys: { peek: "SUPER+Q", toggle: "SUPER+K" } }]],
        ["a reset removes the entry alone", { plugins: [{ id: "acme.keys", keys: { toggle: "SUPER+K", peek: "SUPER+Q" } }] }, {}, "toggle", undefined, "plugins", [{ id: "acme.keys", keys: { peek: "SUPER+Q" } }]],
        ["a reset of the last entry removes keys", { plugins: [{ id: "acme.keys", keys: { toggle: "SUPER+K" } }] }, {}, "toggle", undefined, "plugins", [{ id: "acme.keys" }]],
        ["a reset no row needs writes no row", null, {}, "toggle", undefined, "plugins", undefined],
        ["a reset seeds from an effective row that holds the entry", null, keyRow, "toggle", undefined, "plugins", [{ id: "acme.keys", x: 1 }]],
        ["writes version 3", null, {}, "toggle", "SUPER+K", "version", 3],
    ];
    for (const [name, user, effective, shortcut, key, p, want] of keyRows) {
        check("withKey: " + name, dig(ctx.withKey(user, keyed, shortcut, key, effective), p), want);
    }
    // withAppearance rows: [name, user, effective, key, value, want file]
    const appearanceRows = [
        ["a value is written into a new file", null, {}, "windowRadius", 12, { version: 3, appearance: { windowRadius: 12 } }],
        ["a value joins the user's others and leaves other keys", { version: 3, plugins: [{ id: "a.b" }], appearance: { motion: false } }, {}, "windowRadius", "hyprland", { version: 3, plugins: [{ id: "a.b" }], appearance: { motion: false, windowRadius: "hyprland" } }],
        ["a value replaces the user's", { appearance: { windowRadius: 4 } }, {}, "windowRadius", 8, { appearance: { windowRadius: 8 }, version: 3 }],
        ["the user key is seeded from the effective one", null, { appearance: { motion: false } }, "windowRadius", 6, { version: 3, appearance: { motion: false, windowRadius: 6 } }],
        ["an unset removes the member alone", { appearance: { windowRadius: 4, motion: true } }, {}, "windowRadius", undefined, { appearance: { motion: true }, version: 3 }],
        ["an unset of the last member removes the key", { version: 3, appearance: { windowRadius: 4 } }, {}, "windowRadius", undefined, { version: 3 }],
    ];
    for (const [name, user, effective, key, value, want] of appearanceRows) {
        check("withAppearance: " + name, ctx.withAppearance(user, effective, key, value), want);
    }
    check("withAppearance does not alias the user file", (() => { const u = { appearance: { motion: true } }; ctx.withAppearance(u, {}, "motion", false); return u; })(), { appearance: { motion: true } });

    // Sound events: a manifest's `sounds` key, shell.json `sounds`, and
    // the requests the sound service makes of the judge.
    const sounding = (sounds, patch) => Object.assign({}, svc, { capabilities: ["sounds"], sounds: sounds }, patch || {});
    const ping = { label: "Ping", default: "chime" };
    const relay = { label: "Relay", own: "Acme relay", held: true };
    // [name, manifest, want]: null passes, else the start of the refusal.
    const soundManifestRows = [
        ["a sound event passes", sounding({ ping: ping }), null],
        ["an event that is off by default passes", sounding({ ping: { label: "Ping", description: "Plays on a ping", default: "" } }), null],
        ["an event the plugin sounds itself passes", sounding({ tone: { label: "Tone", own: "Acme tone", default: "own" } }), null],
        ["an own event that is off by default passes", sounding({ tone: { label: "Tone", own: "Acme tone", default: "" } }), null],
        ["sounds not an object", sounding([ping]), "sounds must be a non-empty object"],
        ["sounds with no event", sounding({}), "sounds must be a non-empty object"],
        ["sounds without the capability", sounding({ ping: ping }, { capabilities: [] }), "sounds needs capability sounds"],
        ["the capability without sounds", Object.assign({}, svc, { capabilities: ["sounds"] }), "capability sounds needs a sounds declaration"],
        ["a malformed event name", sounding({ "Ping!": ping }), "sounds has malformed event name \"Ping!\""],
        ["an event that is no object", sounding({ ping: "chime" }), "sounds.ping must be an object"],
        ["an event with an unknown key", sounding({ ping: Object.assign({ file: "x.wav" }, ping) }), "sounds.ping has unknown key \"file\""],
        ["an event without a label", sounding({ ping: { default: "chime" } }), "sounds.ping.label must be a printable line"],
        ["an event with a two-line description", sounding({ ping: Object.assign({ description: "a\nb" }, ping) }), "sounds.ping.description must be a printable line"],
        ["an event description of one sentence with a full stop is refused", sounding({ ping: Object.assign({ description: "Plays on a ping." }, ping) }), "sounds.ping.description must end with no full stop"],
        ["an event description of two sentences, each with its full stop", sounding({ ping: Object.assign({ description: "Plays on a ping. It is short." }, ping) }), null],
        ["an own name that is empty", sounding({ tone: { label: "Tone", own: "", default: "own" } }), "sounds.tone.own must be a printable line"],
        ["an event without a default", sounding({ ping: { label: "Ping" } }), "sounds.ping.default must be a sound of the core's set or \"\", got undefined"],
        ["a default the core's set lacks", sounding({ ping: { label: "Ping", default: "gong" } }), "sounds.ping.default must be a sound of the core's set or \"\", got \"gong\""],
        ["a default that is a file path", sounding({ ping: { label: "Ping", default: "/usr/share/sounds/x.oga" } }), "sounds.ping.default must be a sound of the core's set"],
        ["a core sound as an own event's default", sounding({ tone: { label: "Tone", own: "Acme tone", default: "chime" } }), "sounds.tone.default must be \"own\" or \"\", got \"chime\""],
        ["own as a played event's default", sounding({ ping: { label: "Ping", default: "own" } }), "sounds.ping.default must be a sound of the core's set"],
        ["an own event whose value the plugin holds passes", sounding({ relay: relay }), null],
        ["held that is not true", sounding({ relay: Object.assign({}, relay, { held: false }) }), "sounds.relay.held must be true"],
        ["a held event the core would play", sounding({ relay: { label: "Relay", held: true } }), "sounds.relay.held needs own"],
        ["a held event with a default", sounding({ relay: Object.assign({ default: "own" }, relay) }), "sounds.relay.default must be absent beside held"],
    ];
    for (const [name, raw, want] of soundManifestRows) {
        const r = ctx.validateManifest(raw, "/p");
        check("validateManifest sounds: " + name, r.ok ? null : r.error.slice(0, want === null ? 0 : want.length), want);
    }
    check("validateManifest normalizes absent sounds to an object", ctx.validateManifest(svc, "/p").manifest.sounds, {});
    check("soundSettings is a known capability and not exclusive", [ctx.validateManifest(Object.assign({}, svc, { capabilities: ["soundSettings"] }), "/p").ok, ctx.EXCLUSIVE_CAPABILITIES.indexOf("soundSettings")], [true, -1]);
    check("dictation is a known capability and not exclusive", [ctx.validateManifest(Object.assign({}, svc, { capabilities: ["dictation"] }), "/p").ok, ctx.EXCLUSIVE_CAPABILITIES.indexOf("dictation")], [true, -1]);
    // The table against the tree: every sound names a shipped file, and
    // every shipped file is a sound a choice can name, beside the one
    // record of the sounds' origin and licence.
    const shippedSoundFiles = fs.readdirSync(SOUND_DIR);
    const soundFiles = shippedSoundFiles.filter(f => f !== "LICENSE").sort();
    check("the sounds' origin and licence record ships beside them", shippedSoundFiles.length - soundFiles.length, 1);
    check("every sound of the set names a shipped file, and every shipped file is in the set", ctx.SOUNDS.map(s => s.file).sort(), soundFiles);
    check("the set holds a sound", soundFiles.length > 0, true);
    check("sound ids are unique and none is the own value", [new Set(ctx.SOUNDS.map(s => s.id)).size, ctx.SOUNDS.some(s => s.id === ctx.SOUND_OWN || s.id === ctx.SOUND_OFF)], [ctx.SOUNDS.length, false]);

    const soundConfigRows = [
        ["sound choices pass", { sounds: { "acme.svc": { ping: "pop", tone: "" } } }, ""],
        ["a choice the core's set lacks passes the file", { sounds: { "acme.svc": { ping: "gong" } } }, ""],
        ["sounds not an object", { sounds: ["pop"] }, "sounds must be an object"],
        ["a plugin's choices not an object", { sounds: { "acme.svc": "pop" } }, "sounds.acme.svc must be an object"],
        ["a choice that is no string", { sounds: { "acme.svc": { ping: false } } }, "sounds.acme.svc.ping must be a string"],
    ];
    for (const [name, config, want] of soundConfigRows) check("configError: " + name, configLogic.configError(config), want);

    const noisy = ctx.validateManifest(sounding({ ping: ping, quiet: { label: "Quiet", description: "Plays rarely", default: "" }, tone: { label: "Tone", own: "Acme tone", default: "own" }, relay: relay }), "/p").manifest;
    // What each kind of event takes, as the page offers it.
    const coreOffers = [{ value: "", label: "Off", playable: false }, { value: "chime", label: "Chime", playable: true }, { value: "ping", label: "Ping", playable: true }, { value: "pop", label: "Pop", playable: true }];
    const ownOffers = name => [{ value: "", label: "Off", playable: false }, { value: "own", label: name, playable: false }];
    check("soundOffers: a played event takes Off and every sound of the set, each playable", ctx.soundOffers(noisy.sounds.ping), coreOffers);
    check("soundOffers: an own event takes Off and the plugin's own sound, neither playable", ctx.soundOffers(noisy.sounds.tone), ownOffers("Acme tone"));
    check("soundHeld: the held event alone", ["ping", "tone", "relay", "gong"].map(event => ctx.soundHeld(noisy, event)), [false, false, true, false]);
    const chosen = choices => ({ plugins: [{ id: "acme.svc" }], sounds: { "acme.svc": choices } });
    // soundValue rows: [name, config, event, want]
    const soundValueRows = [
        ["the manifest's default sounds with no choice", {}, "ping", "chime"],
        ["an event that is off by default stays off", {}, "quiet", ""],
        ["the user's sound replaces the default", chosen({ ping: "pop" }), "ping", "pop"],
        ["the user's off replaces the default", chosen({ ping: "" }), "ping", ""],
        ["the user turns an off event on", chosen({ quiet: "ping" }), "quiet", "ping"],
        ["a choice the set lacks reads as the default", chosen({ ping: "gong" }), "ping", "chime"],
        ["a choice that is no string reads as the default", chosen({ ping: 3 }), "ping", "chime"],
        ["another plugin's choice does not apply", { sounds: { "acme.other": { ping: "pop" }, "acme.svc": { quiet: "ping" } } }, "ping", "chime"],
        ["an own event keeps its own sound", {}, "tone", "own"],
        ["an own event is turned off", chosen({ tone: "" }), "tone", ""],
        ["a core sound is no choice for an own event", chosen({ tone: "pop" }), "tone", "own"],
        ["own is no choice for a played event", chosen({ ping: "own" }), "ping", "chime"],
    ];
    for (const [name, config, event, want] of soundValueRows) check("soundValue: " + name, ctx.soundValue(config, noisy, event), want);
    check("soundChoices: every event the core stores under the user's choices, and no held one", ctx.soundChoices(chosen({ ping: "pop", tone: "", relay: "" }), noisy), { ping: "pop", quiet: "", tone: "" });

    // soundRequest rows: [name, config, event, want]
    const soundRequestRows = [
        ["a declared event plays its sound", {}, "ping", { ok: true, sound: "chime" }],
        ["the user's sound plays", chosen({ ping: "ping" }), "ping", { ok: true, sound: "ping" }],
        ["a held event is not played by the core", {}, "relay", { ok: false, answer: "refused: sound=relay reason=own" }],
        ["an event that is off answers off", chosen({ ping: "" }), "ping", { ok: false, answer: "off" }],
        ["an undeclared event is refused", {}, "gong", { ok: false, answer: "refused: sound=gong reason=undeclared" }],
        ["a name that is no string is refused on one line", {}, { a: "\n" }, { ok: false, answer: "refused: sound={\"a\":\"\\n\"} reason=undeclared" }],
        ["an inherited name is no event", {}, "constructor", { ok: false, answer: "refused: sound=constructor reason=undeclared" }],
        ["an event the plugin sounds itself is refused", {}, "tone", { ok: false, answer: "refused: sound=tone reason=own" }],
    ];
    for (const [name, config, event, want] of soundRequestRows) check("soundRequest: " + name, ctx.soundRequest(config, noisy, event), want);

    // soundEdit rows: [name, user, effective, event, value, want]
    const soundEditRows = [
        ["a choice is written into a new file", null, {}, "ping", "pop", { ok: true, user: { version: 3, sounds: { "acme.svc": { ping: "pop" } } } }],
        ["off is written", null, {}, "ping", "", { ok: true, user: { version: 3, sounds: { "acme.svc": { ping: "" } } } }],
        ["a choice joins the plugin's others and leaves other keys", { version: 3, plugins: [{ id: "a.b" }], sounds: { "acme.svc": { quiet: "ping" }, "acme.other": { x: "pop" } } }, {}, "ping", "pop", { ok: true, user: { version: 3, plugins: [{ id: "a.b" }], sounds: { "acme.svc": { quiet: "ping", ping: "pop" }, "acme.other": { x: "pop" } } } }],
        ["the user key is seeded from the effective one", null, { sounds: { "acme.other": { x: "pop" } } }, "ping", "pop", { ok: true, user: { version: 3, sounds: { "acme.other": { x: "pop" }, "acme.svc": { ping: "pop" } } } }],
        ["the default removes the choice alone", { sounds: { "acme.svc": { ping: "pop", quiet: "ping" } } }, {}, "ping", "chime", { ok: true, user: { sounds: { "acme.svc": { quiet: "ping" } }, version: 3 } }],
        ["the default of the plugin's last choice removes its object", { version: 3, sounds: { "acme.svc": { ping: "pop" }, "acme.other": { x: "pop" } } }, {}, "ping", "chime", { ok: true, user: { version: 3, sounds: { "acme.other": { x: "pop" } } } }],
        ["the default of the last choice removes the key", { version: 3, sounds: { "acme.svc": { ping: "pop" } } }, {}, "ping", "chime", { ok: true, user: { version: 3 } }],
        ["an own event is turned off", null, {}, "tone", "", { ok: true, user: { version: 3, sounds: { "acme.svc": { tone: "" } } } }],
        ["a sound the set lacks is refused", null, {}, "ping", "gong", { ok: false, answer: "refused: sound=ping reason=value" }],
        ["a value that is no string is refused", null, {}, "ping", true, { ok: false, answer: "refused: sound=ping reason=value" }],
        ["a core sound for an own event is refused", null, {}, "tone", "pop", { ok: false, answer: "refused: sound=tone reason=value" }],
        ["an undeclared event is refused", null, {}, "gong", "pop", { ok: false, answer: "refused: sound=gong reason=undeclared" }],
        ["a held event's choice writes no file", { version: 3 }, {}, "relay", "", { ok: true, held: true }],
        ["a held event's choice is judged first", null, {}, "relay", "pop", { ok: false, answer: "refused: sound=relay reason=value" }],
    ];
    for (const [name, user, effective, event, value, want] of soundEditRows) check("soundEdit: " + name, ctx.soundEdit(user, effective, noisy, "acme.svc", event, value), want);
    check("soundEdit: an id no enabled plugin has is unknown", ctx.soundEdit(null, {}, null, "acme.gone", "ping", "pop"), { ok: false, answer: "unknown: acme.gone" });
    check("soundEdit does not alias the user file", (() => { const u = { sounds: { "acme.svc": { ping: "pop" } } }; ctx.soundEdit(u, {}, noisy, "acme.svc", "ping", ""); return u; })(), { sounds: { "acme.svc": { ping: "pop" } } });

    // soundReport rows: [name, event, value, problem, want]
    const soundReportRows = [
        ["the plugin's own sound is stated", "relay", "own", "", { ok: true, state: { value: "own", problem: "" } }],
        ["off is stated with the reason a choice did not take effect", "relay", "", "The file is a link.", { ok: true, state: { value: "", problem: "The file is a link." } }],
        ["an unread value is stated", "relay", null, "Not set up.", { ok: true, state: { value: null, problem: "Not set up." } }],
        ["an undeclared event is refused", "gong", "own", "", { ok: false, answer: "refused: sound=gong reason=undeclared" }],
        ["an event the core stores is refused", "tone", "own", "", { ok: false, answer: "refused: sound=tone reason=stored" }],
        ["a value the event does not take is refused", "relay", "pop", "", { ok: false, answer: "refused: sound=relay reason=value" }],
        ["a value that is undefined is refused", "relay", undefined, "", { ok: false, answer: "refused: sound=relay reason=value" }],
        ["a two-line problem is refused", "relay", "own", "a\nb", { ok: false, answer: "refused: sound=relay reason=problem" }],
        ["a problem that is no string is refused", "relay", "own", null, { ok: false, answer: "refused: sound=relay reason=problem" }],
    ];
    for (const [name, event, value, problem, want] of soundReportRows) check("soundReport: " + name, ctx.soundReport(noisy, event, value, problem), want);

    const soundManifests = Object.create(null);
    soundManifests["acme.svc"] = noisy;
    soundManifests["acme.zed"] = ctx.validateManifest(Object.assign({}, svc, { id: "acme.zed", name: "Alpha", icon: "bell", capabilities: ["sounds"], sounds: { beep: { label: "Beep", default: "pop" } } }), "/p").manifest;
    soundManifests["acme.mute"] = ctx.validateManifest(Object.assign({}, svc, { id: "acme.mute", name: "Mute" }), "/p").manifest;
    soundManifests["acme.off"] = ctx.validateManifest(Object.assign({}, svc, { id: "acme.off", name: "Off", capabilities: ["sounds"], sounds: { beep: { label: "Beep", default: "pop" } } }), "/p").manifest;
    // The stored choice for the held event is one a hand edit could leave:
    // the row reads the plugin's statement and never the file.
    const soundConfig = { plugins: [{ id: "acme.svc" }, { id: "acme.zed" }, { id: "acme.mute" }], sounds: { "acme.svc": { ping: "", relay: "" } } };
    const soundRowsWith = held => ctx.soundRows(soundConfig, soundManifests, "vgs.bar", held);
    const heldRow = (value, problem) => ({ id: "acme.svc", plugin: "S", event: "relay", label: "Relay", description: "", value: value, offers: ownOffers("Acme relay"), testable: false, problem: problem });
    check("soundRows: enabled plugins by name, each event in manifest order, with what it sounds and takes", soundRowsWith({}), [
        { id: "acme.zed", plugin: "Alpha", event: "beep", label: "Beep", description: "", value: "pop", offers: coreOffers, testable: true, problem: "" },
        { id: "acme.svc", plugin: "S", event: "ping", label: "Ping", description: "", value: "", offers: coreOffers, testable: true, problem: "" },
        { id: "acme.svc", plugin: "S", event: "quiet", label: "Quiet", description: "Plays rarely", value: "", offers: coreOffers, testable: true, problem: "" },
        { id: "acme.svc", plugin: "S", event: "tone", label: "Tone", description: "", value: "own", offers: ownOffers("Acme tone"), testable: false, problem: "" },
        heldRow(null, ""),
    ]);
    // soundRows held rows: [name, held, the held event's row]
    const soundHeldRows = [
        ["a held event reads what its plugin stated", { "acme.svc": { relay: { value: "own", problem: "" } } }, heldRow("own", "")],
        ["a held event shows its plugin's problem", { "acme.svc": { relay: { value: "", problem: "The file is a link." } } }, heldRow("", "The file is a link.")],
        ["a held event its plugin cannot read has no value", { "acme.svc": { relay: { value: null, problem: "Not set up." } } }, heldRow(null, "Not set up.")],
        ["another plugin's statement is not this event's", { "acme.zed": { relay: { value: "own", problem: "x" } } }, heldRow(null, "")],
        ["a statement for an event the core stores is not read", { "acme.svc": { tone: { value: "", problem: "x" } } }, heldRow(null, "")],
    ];
    for (const [name, held, want] of soundHeldRows) check("soundRows: " + name, soundRowsWith(held)[4], want);
    check("soundRows: a statement for an event the core stores changes no row", soundRowsWith({ "acme.svc": { tone: { value: "", problem: "x" } } })[3], { id: "acme.svc", plugin: "S", event: "tone", label: "Tone", description: "", value: "own", offers: ownOffers("Acme tone"), testable: false, problem: "" });
    check("soundArgv: the player, the event role and the sound's file", ctx.soundArgv("/s/assets/sounds", "pop"), ["pw-play", "--media-role", "Notification", "/s/assets/sounds/pop.wav"]);
    check("soundArgv: a sound the set lacks has no argv", ctx.soundArgv("/s", "gong"), null);

    check("withKey does not alias the user file", (() => { const u = { plugins: [{ id: "acme.keys", keys: { toggle: "SUPER+K" } }] }; ctx.withKey(u, keyed, "toggle", null, {}); return u.plugins[0]; })(), { id: "acme.keys", keys: { toggle: "SUPER+K" } });

    // bindRows: the key in effect, the manifest's key, the registered description and the manifest's explanation.
    check("bindRows: each bind with its key in effect, its default, its description and its explanation", ctx.bindRows({ plugins: [{ id: "acme.keys", keys: { toggle: null } }] }, keyed, { "acme.keys:toggle": "Open" }),
        [{ shortcut: "toggle", key: null, keys: [], default: "SUPER+M", description: "Open", info: "Opens or closes it." }, { shortcut: "peek", key: "SUPER+P", keys: ["SUPER+P"], default: "SUPER+P", description: "", info: "" }]);
    check("bindRows: a rebound key is the one in effect", ctx.bindRows({ plugins: [{ id: "acme.keys", keys: { peek: "shift+super+p" } }] }, keyed, {})[1], { shortcut: "peek", key: "SUPER+SHIFT+P", keys: ["SUPER+SHIFT+P"], default: "SUPER+P", description: "", info: "" });
    check("bindRows: a two-key shortcut is one row with both keys", ctx.bindRows({ plugins: [{ id: "acme.keys", keys: { toggle: ["code:108", "code:105"] } }] }, keyed, { "acme.keys:toggle": "Open" })[0],
        { shortcut: "toggle", key: "code:108", keys: ["code:108", "code:105"], default: "SUPER+M", description: "Open", info: "Opens or closes it." });
    check("bindRows: a plugin without binds has none", ctx.bindRows({}, manifests["acme.svc"], {}), []);
    const tapDefaults = ctx.validateManifest({ schemaVersion: 1, id: "acme.tap", name: "T", version: "1", author: "a", description: "d", kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["shortcut"],
        hyprland: { binds: [{ shortcut: "tap", key: ["CODE:00108", "code:105"], tap: true }] } }, "/p").manifest;
    if (tapDefaults === undefined) throw new Error("fixture manifest refused: acme.tap with a default key list");
    // bindRows over a default key list: [name, plugins row keys, want row]
    for (const [name, keys, want] of [
        ["a default key list is every key in effect and the default", undefined, { shortcut: "tap", key: "code:108", keys: ["code:108", "code:105"], default: ["code:108", "code:105"], description: "", info: "" }],
        ["a row key wins over a default key list", { tap: "code:97" }, { shortcut: "tap", key: "code:97", keys: ["code:97"], default: ["code:108", "code:105"], description: "", info: "" }],
        ["a row null unbinds a default key list", { tap: null }, { shortcut: "tap", key: null, keys: [], default: ["code:108", "code:105"], description: "", info: "" }],
    ]) {
        check("bindRows: " + name, ctx.bindRows({ plugins: [keys === undefined ? { id: "acme.tap" } : { id: "acme.tap", keys }] }, tapDefaults, {})[0], want);
    }

    check("pluginIcon: a manifest's icon", ctx.pluginIcon(ctx.validateManifest(Object.assign({}, svc, { icon: "bell" }), "/p").manifest), "bell");
    check("pluginIcon: a plugin without one is listed as a package", ctx.pluginIcon(manifests["acme.svc"]), "package");

    check("SUMMONABLE_KINDS are kinds", ctx.SUMMONABLE_KINDS.every(k => ctx.KINDS.indexOf(k) !== -1), true);
    check("window is a summonable kind", ctx.SUMMONABLE_KINDS.indexOf("window"), 3);

    function openManifest(id, kinds) {
        const entryPoints = {};
        for (const kind of kinds) entryPoints[kind] = kind[0].toUpperCase() + kind.slice(1) + ".qml";
        const result = ctx.validateManifest({ schemaVersion: 1, id: id, name: id, version: "1", author: "a", description: "d", kinds: kinds, entryPoints: entryPoints }, "/p");
        if (!result.ok) throw new Error("fixture manifest refused: " + id + ": " + result.error);
        return result.manifest;
    }
    const openManifests = {
        window: openManifest("acme.window", ["window"]),
        panel: openManifest("acme.panel", ["panel"]),
        both: openManifest("acme.both", ["window", "panel"]),
        overlay: openManifest("acme.overlay", ["overlay"]),
        widgetService: openManifest("acme.widget-service", ["bar-widget", "service"]),
        service: manifests["acme.svc"]
    };
    const openKindRows = [
        ["window only", openManifests.window, "window"],
        ["panel only", openManifests.panel, "panel"],
        ["window plus panel", openManifests.both, "window"],
        ["overlay only", openManifests.overlay, ""],
        ["bar widget plus service", openManifests.widgetService, ""],
        ["service only", openManifests.service, ""],
    ];
    for (const [name, manifest, want] of openKindRows)
        check("openKind: " + name, ctx.openKind(manifest), want);
    const openRequestRows = [
        ["null manifest", null, "acme.missing", { ok: false, answer: "unknown: acme.missing" }],
        ["no surface", openManifests.service, "acme.svc", { ok: false, answer: "refused: open=acme.svc reason=no-surface" }],
        ["window", openManifests.window, "acme.window", { ok: true, kind: "summon", surface: "window" }],
    ];
    for (const [name, manifest, id, want] of openRequestRows)
        check("openRequest: " + name, ctx.openRequest(manifest, id), want);

    // summonSurface rows: [name, kind, anchored, want]. An application
    // window is a toplevel whatever the anchor; every other summonable kind
    // is a popup under its anchor and a layer surface without one.
    const surfaceRows = [
        ["a window without an anchor is a toplevel", "window", false, "window"],
        ["an anchored window is still a toplevel", "window", true, "window"],
        ["an anchored panel is a popup", "panel", true, "popup"],
        ["an unanchored panel is a layer surface", "panel", false, "layer"],
        ["an anchored menu is a popup", "menu", true, "popup"],
        ["an unanchored overlay is a layer surface", "overlay", false, "layer"],
    ];
    for (const [name, kind, anchored, want] of surfaceRows)
        check("summonSurface: " + name, ctx.summonSurface(kind, anchored), want);
    check("summonSurface refuses a kind no host summons", (() => { try { return ctx.summonSurface("background", false); } catch (e) { return e.message; } })(), "summonSurface: kind \"background\" is not summonable");

    check("capturesOverlayKeyboard: unanchored overlay captures", ctx.capturesOverlayKeyboard("overlay", false), true);
    check("capturesOverlayKeyboard: anchored overlay does not capture", ctx.capturesOverlayKeyboard("overlay", true), false);
    check("capturesOverlayKeyboard: panel does not capture", ctx.capturesOverlayKeyboard("panel", false), false);
    check("capturesOverlayKeyboard refuses a kind no host summons", (() => { try { return ctx.capturesOverlayKeyboard("background", false); } catch (e) { return e.message; } })(), "capturesOverlayKeyboard: kind \"background\" is not summonable");
    check("layerKeyboardFocus: capturing overlay is exclusive", ctx.layerKeyboardFocus("overlay", false), "exclusive");
    check("layerKeyboardFocus: non-capturing layer is on demand", ctx.layerKeyboardFocus("panel", false), "on-demand");
    check("layerCatchesOutside: a panel layer catches a press beside it", ctx.layerCatchesOutside("panel"), true);
    check("layerCatchesOutside: a menu layer catches a press beside it", ctx.layerCatchesOutside("menu"), true);
    check("layerCatchesOutside: an overlay layer catches nothing", ctx.layerCatchesOutside("overlay"), false);
    check("layerCatchesOutside refuses a kind never built as a layer", (() => { try { return ctx.layerCatchesOutside("window"); } catch (e) { return e.message; } })(), "layerCatchesOutside: kind \"window\" is never a layer summon");

    // The `list` type and `hyprland.pads` as PluginLogic judges and expands
    // them through Pads.js, whose own rules scripts/test-pads.js holds.
    const padItems = { "class": { type: "string", label: "Class", presets: [{ value: "org.acme.pad" }], allowCustom: true }, width: { type: "number", label: "Width", min: 10, max: 100 },
        height: { type: "number", label: "Height", min: 10, max: 100 }, position: { type: "enum", label: "Position", options: [{ value: "center", label: "Center" }, { value: "top", label: "Top" }] }, margin: { type: "number", label: "Margin", min: 0, max: 20 },
        entry: { type: "enum", label: "Entry", options: [{ value: "top", label: "Top" }, { value: "left", label: "Left" }] }, motion: { type: "enum", label: "Motion", options: [{ value: "slide", label: "Slide" }, { value: "none", label: "None" }] } };
    const padDefaults = { "class": "org.acme.pad", width: 60, height: 50, position: "top", margin: 2, entry: "top", motion: "slide" };
    const padSchema = { pads: { type: "list", label: "Pads", items: padItems, defaults: padDefaults } };
    const padsRaw = Object.assign({}, svc, { id: "acme.pads", capabilities: ["shortcut"], settings: { pads: [] }, schema: padSchema, hyprland: { pads: "pads" } });
    const padsManifest = ctx.validateManifest(padsRaw, "/p");
    check("validateManifest: a list setting and pads naming it pass", padsManifest.ok ? null : padsManifest.error, null);
    const listRows = [
        ["a list entry's items are judged", { schema: { pads: { type: "list", label: "Pads", items: {}, defaults: {} } }, hyprland: undefined }, "schema.pads.items must be a non-empty object"],
        ["items on a flat entry are refused", { settings: { pads: [], on: true }, schema: Object.assign({ on: { type: "boolean", label: "On", items: {} } }, padSchema) }, "schema.on.items and .defaults need type list"],
        ["a list's default is judged as a list", { settings: { pads: {} } }, "settings.pads does not fit its schema: want=list"],
        ["pads naming no list entry are refused", { hyprland: { pads: "missing" } }, "hyprland.pads must name a list schema entry, got \"missing\""],
        ["pads alone declare something", { hyprland: { pads: "pads", binds: [] } }, null]
    ];
    for (const [name, patch, want] of listRows) {
        const r = ctx.validateManifest(Object.assign({}, padsRaw, patch), "/p");
        check("validateManifest: " + name, r.ok ? null : r.error, want);
    }
    const pad = Object.assign({ name: "1" }, padDefaults);
    check("settingRefusal: a list value of items that fit is written", ctx.settingRefusal(padsManifest.manifest, "pads", [pad]), "");
    check("settingRefusal: a list item's field is judged", ctx.settingRefusal(padsManifest.manifest, "pads", [Object.assign({}, pad, { width: 5 })]), "refused: setting=pads item=0 field=width want=at-least:10");
    const padConfig = { plugins: [{ id: "acme.pads", pads: [pad, Object.assign({}, pad, { name: "2", "class": "org.acme.other" }), Object.assign({}, pad, { name: "3" })], keys: { "pad-1": ["alt+super+p", "code:105"], "pad-7": "SUPER+7", stray: null } }] };
    const padSection = ctx.hyprlandSection(padConfig, padsManifest.manifest);
    check("hyprlandSection: each pad ends the binds with its key", padSection.binds, [{ shortcut: "pad-1", key: "SUPER+ALT+P" }, { shortcut: "pad-1", key: "code:105" }, { shortcut: "pad-2", key: null }, { shortcut: "pad-3", key: null }]);
    check("hyprlandSection: each pad is handed to the layer", padSection.pads.map(p => p.name), ["1", "2"]);
    check("hyprlandSection: a pad the core refuses is listed", padSection.padRefusals, [{ name: "3", error: "class=org.acme.pad held by pad 1" }]);
    check("hyprlandSection: a pad's key is no unknown key, another name is", padSection.unknownKeys, ["stray"]);
    check("hyprlandSection: a manifest without pads hands none", ctx.hyprlandSection({}, manifests["acme.svc"]).pads, null);
    check("hyprlandSection: monitor rules are handed to the layer", ctx.hyprlandSection({ plugins: [{ id: "acme.svc", outputs: { "DP-1": { scale: 1 } } }] }, ctx.validateManifest(monitorManifest, "/p").manifest).monitors,
      { kind: "set", setting: "outputs", value: { "DP-1": { scale: 1 } } });
    const ownerMap = {
      "acme.svc": ctx.validateManifest(monitorManifest, "/p").manifest,
      "acme.other": ctx.validateManifest(Object.assign({}, monitorManifest, { id: "acme.other" }), "/p").manifest
    };
    check("monitor rule owner is unique", ctx.monitorRuleOwner(ownerMap, ["acme.svc"], {}), "acme.svc");
    check("a second monitor rule owner keeps the holder", ctx.monitorRuleOwner(ownerMap, ["acme.svc", "acme.other"], { monitors: "acme.svc" }), "acme.svc");
    check("a second monitor rule owner is refused", ctx.monitorRuleRefusal(ownerMap, ["acme.svc", "acme.other"], { monitors: "acme.svc" }, "acme.other"), "refused: hyprland.monitors=acme.other held-by=acme.svc");
    check("the held monitor rule owner is not refused", ctx.monitorRuleRefusal(ownerMap, ["acme.svc", "acme.other"], { monitors: "acme.svc" }, "acme.svc"), "");
    check("keyRefusal: a pad's key is written", ctx.keyRefusal(padsManifest.manifest, "pad-9", "SUPER+9"), "");
    check("keyRefusal: a pad's key is judged", ctx.keyRefusal(padsManifest.manifest, "pad-9", "SUPER+"), "refused: key=pad-9 has an empty part: \"SUPER+\"");
    check("keyRefusal: a shortcut of no pad is undeclared", ctx.keyRefusal(padsManifest.manifest, "toggle", "SUPER+9"), "refused: key=toggle undeclared");
    check("bindRows: a pad's key has no default", ctx.bindRows(padConfig, padsManifest.manifest, { "acme.pads:pad-1": "Show or hide pad 1" }),
        [{ shortcut: "pad-1", key: "SUPER+ALT+P", keys: ["SUPER+ALT+P", "code:105"], default: null, description: "Show or hide pad 1", info: "" }, { shortcut: "pad-2", key: null, keys: [], default: null, description: "", info: "" }, { shortcut: "pad-3", key: null, keys: [], default: null, description: "", info: "" }]);

    // The `sudo` capability: the grant durations the core TUI takes, and
    // what one run of `vgshell-sudo-grant status` reads as.
    check("sudo is a capability", ctx.CAPABILITIES.indexOf("sudo") !== -1, true);
    const durationRows = [
        ["15", true], ["1", true], ["1440", true], ["indefinite", true],
        ["1441", false], ["0", false], ["015", false], ["", false], [" 15", false], ["60\n", false],
        ["1.5", false], ["Indefinite", false], [15, false], [null, false], [undefined, false],
    ];
    for (const [value, want] of durationRows)
        check("sudoDurationValid: " + JSON.stringify(value), ctx.sudoDurationValid(value), want);
    const sudoDone = { code: 0, status: 0 };
    const sudoUnknown = line => ({ state: "unknown", until: "", rootHalf: "", line: line });
    const sudoRows = [
        ["a timed grant", sudoDone, "sudo-grant=active until=2026-10-08T22:07:25Z root-half=current\n", "", { state: "active", until: "2026-10-08T22:07:25Z", rootHalf: "current", line: "" }],
        ["an indefinite grant through a stale root half", sudoDone, "sudo-grant=active until=indefinite root-half=stale\n", "", { state: "active", until: "indefinite", rootHalf: "stale", line: "" }],
        ["no grant", sudoDone, "sudo-grant=inactive root-half=current\n", "", { state: "inactive", until: "", rootHalf: "current", line: "" }],
        ["no root half", sudoDone, "sudo-grant=inactive root-half=absent\n", "", { state: "absent", until: "", rootHalf: "absent", line: "" }],
        ["NixOS", sudoDone, "sudo-grant=skipped=nixos-config\n", "", { state: "nixos", until: "", rootHalf: "", line: "" }],
        ["a run that never started", null, "", "", sudoUnknown("sudo: read=unstarted")],
        ["a refusal", { code: 1, status: 0 }, "", "vgs-sudo-grant: refused: sudo=unsupported\nmore", sudoUnknown("sudo: read=failed exit=1 status=0 vgs-sudo-grant: refused: sudo=unsupported")],
        ["a crash", { code: 0, status: 1 }, "sudo-grant=inactive root-half=current\n", "", sudoUnknown("sudo: read=failed exit=0 status=1 ")],
        ["a deadline that is no time", sudoDone, "sudo-grant=active until=soon root-half=current\n", "", sudoUnknown("sudo: read=malformed line=\"sudo-grant=active until=soon root-half=current\"")],
        ["an active grant with no root half", sudoDone, "sudo-grant=active until=indefinite root-half=absent\n", "", sudoUnknown("sudo: read=malformed line=\"sudo-grant=active until=indefinite root-half=absent\"")],
        ["a second line", sudoDone, "sudo-grant=inactive root-half=current\nmore\n", "", sudoUnknown("sudo: read=malformed line=\"sudo-grant=inactive root-half=current\"")],
        ["nothing printed", sudoDone, "", "", sudoUnknown("sudo: read=malformed line=\"\"")],
    ];
    for (const [name, completion, stdout, stderr, want] of sudoRows)
        check("sudoReport: " + name, ctx.sudoReport(completion, stdout, stderr), want);

    // The configuration judgement lives in ConfigLogic.js alone: PluginLogic
    // holds no copy of a moved name and no alias of a ConfigLogic member, and
    // calls through the ConfigLogic it imports.
    const moved = ["SECTIONS", "NAME_PATTERN", "HYPRLAND_MODIFIERS", "HYPRLAND_KEY_NAME", "CONFIG_VERSION", "configError", "migrateConfig", "effectiveConfig", "hyprlandKey", "keyValueError", "keysError", "keyHasModifiers"];
    check("ConfigLogic holds every moved name", moved.filter(name => !(name in configLogic)), []);
    check("PluginLogic holds no moved name", moved.filter(name => name in ctx), []);
    const shared = Object.values(ctx.ConfigLogic).filter(value => value !== null && (typeof value === "object" || typeof value === "function"));
    check("PluginLogic aliases no ConfigLogic member", Object.keys(ctx).filter(name => name !== "ConfigLogic" && shared.includes(ctx[name])), []);
    check("PluginLogic imports the ConfigLogic library", Object.keys(ctx.ConfigLogic).sort(), Object.keys(configLogic).sort());
    const sections = ctx.ConfigLogic.SECTIONS;
    ctx.ConfigLogic.SECTIONS = ["right"];
    try {
        check("PluginLogic reads the sections through ConfigLogic", ctx.layoutIds({ bar: { layout: { left: [{ id: "a" }], right: [{ id: "b" }] } } }), ["b"]);
    } finally {
        ctx.ConfigLogic.SECTIONS = sections;
    }
}

suite(load(LOGIC), load(CONFIG), report);

// The Updates service publishes this actionless state for a foreign hook.
// Exercise its shipped declaration through the manager's actual row projection.
function verifyUpdatesNoticeOwner(raw) {
    const assert = require("node:assert/strict");
    const logic = load(LOGIC);
    const manifest = logic.validateManifest(raw, "/updates").manifest;
    const reference = load(PAGE_REFERENCE);
    const value = { tone: "warning", text: "Foreign hook", hint: reference.fileReference("Hook file", "/etc/pacman.d/hooks/cachyos-reboot-required.hook") };
    const prior = {};
    const written = logic.statusWrite(manifest, prior, "rebootNoticeOwner", value);
    const row = logic.statusRows(manifest, written.ok ? written.values : prior).find(row => row.key === "rebootNoticeOwner");
    assert.ok(row, "the denied owner reading reaches Details");
    assert.equal(written.ok, true);
    assert.deepEqual([row.setup, row.settings, row.setting, row.action], ["", false, "", null]);
    assert.equal(row.tone, "warning");
    assert.equal(row.value.text, value.text);
    assert.equal(row.hint, value.hint);
    assert.equal(reference.file(reference.parse(row.hint).page), "/etc/pacman.d/hooks/cachyos-reboot-required.hook");
    assert.equal(manifest.status.rebootNotice.hidden, true, "the actionable setting remains off Details");
    assert.equal(manifest.schema.rebootNotice.hideEmpty, true, "a denied hook offers no empty selector");
}
const updatesManifest = JSON.parse(fs.readFileSync(path.join(PLUGINS_DIR, "vgs.updates/manifest.json"), "utf8"));
verifyUpdatesNoticeOwner(updatesManifest);
const withoutNoticeOwner = JSON.parse(JSON.stringify(updatesManifest));
delete withoutNoticeOwner.status.rebootNoticeOwner;
require("node:assert/strict").throws(() => verifyUpdatesNoticeOwner(withoutNoticeOwner), require("node:assert/strict").AssertionError,
    "the baseline declaration without an owner reading fails the denied-row assertion");

// The map the bundled manifests build renames a Cloud Sync user file
// enabled, disabled and placed, so the rename the shell runs at its first
// start after the update comes from the shipped manifest. Run once, outside
// the controls, which the rows above cover.
{
    const logic = load(LOGIC), configLogic = load(CONFIG);
    const bundled = Object.create(null);
    for (const name of fs.readdirSync(PLUGINS_DIR).sort()) {
        const file = path.join(PLUGINS_DIR, name, "manifest.json");
        if (!fs.existsSync(file)) continue;
        const r = logic.validateManifest(JSON.parse(fs.readFileSync(file, "utf8")), path.dirname(file));
        if (r.ok) bundled[r.manifest.id] = r.manifest;
    }
    const layout = right => ({ id: "vgs.bar", layout: { left: [], center: [], right: right } });
    const user = { version: 3, bar: layout([{ id: "c.d" }, { id: "vgs.cloud-sync" }]), plugins: [{ id: "vgs.cloud-sync", x: 1 }], disabledPlugins: ["c.d", "vgs.cloud-sync"] };
    const want = { version: 3, bar: layout([{ id: "c.d" }, { id: "vgs.google-drive" }]), plugins: [{ id: "vgs.google-drive", x: 1 }], disabledPlugins: ["c.d", "vgs.google-drive"] };
    const sourceOf = m => m.__sourceDir.indexOf(PLUGINS_DIR + "/") === 0 ? "bundled" : "installed";
    const claims = logic.formerIdClaims(bundled, sourceOf);
    report("renamePlugins: the bundled manifests rename vgs.cloud-sync to vgs.google-drive", configLogic.renamePlugins(user, claims.renames), { config: want, renamed: true });
    // An installed plugin that claims the bundled former id and the bundled
    // live id takes neither.
    const thief = logic.validateManifest({ schemaVersion: 1, id: "acme.drive", name: "N", version: "1", author: "a", description: "d", kinds: ["service"], entryPoints: { service: "S.qml" }, formerIds: ["vgs.cloud-sync", "vgs.google-drive"] }, "/home/u/.config/vgshell/plugins/acme.drive").manifest;
    const scan = Object.assign(Object.create(null), { "acme.drive": thief }, bundled);
    const thiefClaims = logic.formerIdClaims(scan, sourceOf);
    report("formerIdClaims: an installed claim leaves the bundled rename of vgs.cloud-sync", configLogic.renamePlugins(user, thiefClaims.renames), { config: want, renamed: true });
    report("formerIdClaims: an installed claim of vgs.cloud-sync and vgs.google-drive is left out", thiefClaims.ignored,
        [{ id: "acme.drive", reason: "installed", formerIds: ["vgs.cloud-sync", "vgs.google-drive"] }]);
}

// Each control removes one rule from a copy of a judge and keeps the text
// around it; the suite must fail on every copy. The copy sits at the
// judge's own place in a temporary tree, beside the other judge, the icon
// set, the package-manager table and the Hyprland layer's table they import.
const CONTROLS = [
    ["an unplaced widget is mounted", 'out[manifest.unplacedSection].unshift({ id: id, transient: true });', 'out[manifest.unplacedSection].slice();', "unplaced mounts:"],
    ["splitFrom refuses its own id", "raw.splitFrom === raw.id ||", "false ||", "validateManifest:"],
    ["idleStages is a manifest key", '"schema", "idleStages", "defaultSection"', '"schema", "defaultSection"'],
    ["idle stages need capability idle", 'if (capabilities.indexOf("idle") === -1)\n        return "idleStages needs', 'if (false)\n        return "idleStages needs'],
    ["a stage outside the set goes unjudged", "if (IDLE_STAGES.indexOf(stages[i]) === -1)", "if (false)"],
    ["a stage's time needs no min", "!(seconds.min >= 0)", "false"],
    ["a stage's enabled setting goes unjudged", "if (entry.enabled !== undefined && !(", "if (false && !("],
    ["the record takes the enabled ids in the order given", "var declarers = enabledIds.filter(function (id) { return hasOwn(manifests, id); }).sort();", "var declarers = enabledIds.filter(function (id) { return hasOwn(manifests, id); });"],
    ["a stage turned off keeps its time", "seconds: on ? settings[entry.seconds] : 0", "seconds: settings[entry.seconds]"],
    ["a stored time that does not fit is lent", 'if (unfit !== "") {\n                skipped(', 'if (false) {\n                skipped('],
    ["two stages at one time fire one before the other", "earlier.seconds > entry.seconds", "earlier.seconds >= entry.seconds"],
    ["a Never stage fires before later ones", "var before = entry.seconds === 0 ? [] : stages", "var before = stages"],
    ["the record is not frozen", "stages: frozenJson(idleStagesBefore(stages))", "stages: idleStagesBefore(stages)"],
    ["joined presets refuse a combined atom", "preset.value.indexOf(entry.separator) !== -1", "false"],
    ["manifest invokes page judge", 'if (badPlacement !== "") return { ok: false, error: badPlacement };', 'if (false) return { ok: false, error: badPlacement };'],
    ["manifest drops its page rows' judge", 'if (badRows !== "") return { ok: false, error: badRows };', 'if (false) return { ok: false, error: badRows };'],
    ["the page's own labels go unjudged", "if (own.indexOf(label) !== -1)", "if (false)"],
    ["a repeated label goes unjudged", "if (drawn[scope].indexOf(label) !== -1)", "if (false)"],
    ["labels are judged across sections", 'var scope = row.list ? "list " + row.key : "section " + row.section;', 'var scope = "page";'],
    ["labels are judged with their case", "var label = String(labels[l][1]).toLowerCase();", "var label = String(labels[l][1]);"],
    ["a declared configuration screen counts as a More settings row", "entry.settings === true && declared.indexOf(name) === -1; })", "entry.settings === true; })"],
    ["a D-Bus requirement needs no label", "if (!isPrintableLine(requirement.dbus.label, REQUIREMENT_LABEL_MAX))", "if (false)"],
    ["two configuration screens draw two More settings rows", "if (configuring.length > 1)", "if (false)"],
    ["a status entry that is no stored key list is drawn on Settings", 'if (entry.type !== "presenceList" || !secrets) return at + ".setting needs a stored key list', 'if (false) return at + ".setting needs a stored key list'],
    ["a stored key list names a real field", 'typeof entry.setting !== "string" || !hasOwn(schema, entry.setting)', 'false'],
    ["a stored key list on Settings is displayed", 'if (entry.hidden === true) return at + ".setting needs a displayed status";', 'if (false) return at + ".setting needs a displayed status";'],
    ["setup declaration is boolean or optional", 'entry.setup !== undefined && typeof entry.setup !== "boolean" && entry.setup !== SETUP_OPTIONAL', 'false'],
    ["required step is displayed", 'entry.hidden === true || ["state", "presence"].indexOf(entry.type) === -1', 'false'],
    ["keys name a required step", 'typeof entry.step !== "string" || !hasOwn(status, entry.step) || status[entry.step].setup !== true', 'false'],
    ["key association holds keys", 'if (entry.type !== "presenceList") return at + ".step needs a key list";', 'if (false) return at + ".step needs a key list";'],
    ["connection keys declare nothing Setup never draws", 'if (undrawn !== undefined) return at + "." + undrawn', 'if (false) return at + "." + undrawn'],
    ["status has one place", '(setupStep(entry) !== "" ? 1 : 0) + (entry.setting !== undefined ? 1 : 0) + (entry.step !== undefined ? 1 : 0) > 1', 'false'],
    ["a row action may open no tui", "if (entry.rowActions[names[i]].tui === undefined)", "if (false)"],
    ["a row action may open a listed screen", "if (isPlainObject(tui[entry.rowActions[names[i]].tui].entry))", "if (false)"],
    ["a published row needs no id", 'return typeof row.id === "string" && tuiArgsValid([row.id])', "return true"],
    ["two rows may share an id", " || rowIds.indexOf(value[w].id) !== -1", ""],
    ["a row may offer an undeclared row action", "return entry.rowActions !== undefined && hasOwn(entry.rowActions, name);", "return true;"],
    ["any entry may stand on Settings", 'if (entry.type !== "rows" || (entry.action === undefined && entry.rowActions === undefined)) return at + ".settings needs', 'if (false) return at + ".settings needs'],
    ["a row action hands its TUI no row id", "args: [row] };", "args: [] };"],
    ["sourceAction is a status entry key", "\"plain\", \"sourceAction\"];", "\"plain\"];"],
    ["a source action may name a listed screen", "if (isPlainObject(tui[source.tui].entry))\n        return at + \".sourceAction.tui", "if (false)\n        return at + \".sourceAction.tui"],
    ["a source action may stand on a list no page attaches", " || (entry.setting === undefined && entry.step === undefined)))", "))"],
    ["a source action hands its script the caller's account alone", "args: [row, item.label] };", "args: [row] };"],
    ["a source action opens for any listed item", "return published.secret !== undefined && published.secret === row; });", "return true; });"],
    ["a source action runs while its plugin is off", "if (!enabled)\n            return { ok: false, answer: statusActionRefusal(key, \"disabled\") };\n        var item", "var item"],
    ["a key list's row carries no source", "sourceAction: entry.sourceAction === undefined ? null : { label: entry.sourceAction.label, tui: entry.sourceAction.tui },", "sourceAction: null,"],
    ["a row action runs on a row that does not offer it", "return published.id === row && published.actions !== undefined && published.actions.indexOf(rowAction) !== -1;", "return true;"],
    ["a row's state is never a chip", 'var STATUS_ROW_CHIP_TONES = ["warning", "danger"];', "var STATUS_ROW_CHIP_TONES = [];"],
    ["a schema field may be an action", 'var SETTING_TYPES = ["string", "number", "boolean", "enum", "list"];', 'var SETTING_TYPES = ["string", "number", "boolean", "enum", "list", "action"];'],
    ["a requirement may sit beside a field", '"floor", "install"];', '"floor", "install", "setting"];'],
    ["a listed screen may sit beside a field", 'var TUI_ENTRY_KEYS = ["label", "icon", "group", "settings"];', 'var TUI_ENTRY_KEYS = ["label", "icon", "group", "setting", "settings"];'],
    ["a field may read its hint from a status entry", 'var SCHEMA_ENTRY_KEYS = ["type", "label", "description", "info",', 'var SCHEMA_ENTRY_KEYS = ["type", "label", "description", "hintFrom", "info",'],

    ["a hint's sentences end where a mark meets a space", "var parts = text.split(/([.?!]) +/);", "var parts = [text];"],
    ["a one-sentence hint ends with no full stop", "return !/\\.$/.test(text);", "return true;"],
    ["each sentence of a longer hint ends with one", "return sentences.every(function (sentence) { return /[.?!]$/.test(sentence); });", "return true;"],
    ["a schema description keeps the hint rule", "if (entry.description !== undefined && !hintFits(entry.description))", "if (false)"],
    ["a status hint keeps the hint rule", "if (entry.hint !== undefined && !hintFits(PageReference.plain(entry.hint)))", "if (false)"],
    ["a sound event description keeps the hint rule", "if (event.description !== undefined && !hintFits(event.description))", "if (false)"],
    ["a requirement purpose keeps the hint rule", "if (!hintFits(requirement.purpose))", "if (false)"],
    ["sudo is a capability", '"monitors", "sudo", ', '"monitors", '],
    ["a grant longer than a day is refused", "Number(duration) <= SUDO_MINUTES_MAX", "true"],
    ["a sudo read that fails is unknown", 'completion.code !== 0)\n        return failed("sudo: read=failed', 'completion.code !== 0 && false)\n        return failed("sudo: read=failed'],
    ["a sudo deadline is an ISO time", "(indefinite|[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)", "(indefinite|[^ ]+)"],
    ["no sudo root half reads absent", 'return { state: "absent", until: "", rootHalf: "absent", line: "" };', 'return { state: "inactive", until: "", rootHalf: "absent", line: "" };'],
    ["a setting with no schema entry takes only its default's type", 'return keptType(value) === want ? "" : "refused: setting=" + key + " want=" + want;', 'return "";'],
    ["a key the manifest does not declare is not writable", '        if (!hasOwn(manifest.settings, key))\n            return "refused: setting=" + key + " undeclared";\n', ""],
    ["a number JSON cannot hold is no number", '    if (typeof value === "number" && !isFinite(value)) return "non-finite";\n', ""],
    ["undeclared settings never reach runtime or ordinary writes", "if (hasOwn(manifest.settings, k) || (stored && ENTRY_RESERVED_KEYS.indexOf(k) !== -1))", "if (stored || ENTRY_RESERVED_KEYS.indexOf(k) === -1)"],
    ["stored entries retain reserved keys", "stored && ENTRY_RESERVED_KEYS.indexOf(k) !== -1", "false && stored && ENTRY_RESERVED_KEYS.indexOf(k) !== -1"],
    ["builtin placement needs the active catalogue", 'builtinNames.indexOf(id.slice(prefix.length)) !== -1', 'true'],
    ["a family member is numbered from one", "/^([a-z][a-z0-9]*)-([1-9][0-9]*)$/", "/^([a-z][a-z0-9]*)-([0-9]+)$/"],
    ["a family member needs a declared family", "families.indexOf(match[1]) !== -1 ? match[1]", "true ? match[1]"],
    ["family members belong to their own bar", "var name = id.slice(0, prefix.length) === prefix ? id.slice(prefix.length) : \"\";", "var name = id.slice(id.indexOf(\"/\") + 1);"],
    ["family members are listed once", "if (builtinFamilyOf(name, families) !== \"\" && out.indexOf(name) === -1) out.push(name);", "if (builtinFamilyOf(name, families) !== \"\") out.push(name);"],
    ["the next member follows the highest", "return family + \"-\" + (highest + 1);", "return family + \"-\" + highest;"],
    ["a new builtin lands at its index", "target.splice(Math.max(0, Math.min(index, target.length)), 0, { id: id });", "target.push({ id: id });"],
    ["builtin placement needs the active bar prefix", 'id.indexOf(prefix) === 0', 'true'],
    ["builtin placement needs an enabled owner", 'isEnabled(config, bar, defaultBarId)', 'true'],
    ["builtin registration appears once", 'if (seenBuiltins.indexOf(entry.id) !== -1) return false;', ''],
    ["builtin and plugin entries keep declared order", '}).map(clone);\n    });\n    // Temporary mounts', '}).map(clone).reverse();\n    });\n    // Temporary mounts'],
    ["a schema entry may declare a link", '"tooltip", "link", "options"', '"tooltip", "options"'],
    ["a status entry may declare a link", 'var STATUS_ENTRY_KEYS = ["type", "label", "group", "hint", "info", "link",', 'var STATUS_ENTRY_KEYS = ["type", "label", "group", "hint", "info",'],
    ["a status hint link is judged", 'var statusLink = linkError(entry, at, "hint");', 'var statusLink = "";'],
    ["a status hint link reads the hint", 'linkError(entry, at, "hint")', 'linkError(entry, at, "label")'],
    ["a description link is an object", 'if (!isPlainObject(link))\n        return at + ".link must be an object";', 'if (false)\n        return at + ".link must be an object";'],
    ["a description link carries only text and url", 'if (LINK_KEYS.indexOf(linkKeys[k]) === -1)', 'if (false)'],
    ["a description link belongs to a flat field", 'if (entry.type === "list")\n        return at + ".link needs a flat setting";', 'if (false)\n        return at + ".link needs a flat setting";'],
    ["a description link text is a printable line", 'if (!isPrintableLine(link.text, LINK_TEXT_MAX))', 'if (false)'],
    ["a description link text is words of its description", 'if (typeof entry[field] !== "string" || entry[field].indexOf(link.text) === -1)', 'if (false)'],
    ["a description link address is https", 'var LINK_URL_PATTERN = /^https:', 'var LINK_URL_PATTERN = /^[a-zA-Z]+:'],
    ["a description link address has a host of its own", '[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)*(:[0-9]{1,5})?([/?#][!-~]*)?$/;', '[!-~]*$/;'],
    ["a description link address is bounded", 'link.url.length > LINK_URL_MAX || ', ''],
    ["a description link address is a string", 'typeof link.url !== "string" || ', ''],
    ["a description link refuses the old pane key", 'var LINK_KEYS = ["text", "url"];', 'var LINK_KEYS = ["text", "url", "pane"];'],
    ["session is a known capability", '"lock", "session",', '"lock", ("session" && "planted"),'],
    ["session is not exclusive", 'var EXCLUSIVE_CAPABILITIES = ["lock", "polkit", "bluetoothAgent", "panes"];', 'var EXCLUSIVE_CAPABILITIES = ["lock", "polkit", "bluetoothAgent", "panes"].concat(["session"]);'],
    ["the Bluetooth agent is exclusive", 'var EXCLUSIVE_CAPABILITIES = ["lock", "polkit", "bluetoothAgent", "panes"];', 'var EXCLUSIVE_CAPABILITIES = ["lock", "polkit", "panes"];'],
    ["monitors is not exclusive", 'var EXCLUSIVE_CAPABILITIES = ["lock", "polkit", "bluetoothAgent", "panes"];', 'var EXCLUSIVE_CAPABILITIES = ["lock", "polkit", "bluetoothAgent", "monitors", "panes"];'],
    ["panes is exclusive", 'var EXCLUSIVE_CAPABILITIES = ["lock", "polkit", "bluetoothAgent", "panes"];', 'var EXCLUSIVE_CAPABILITIES = ["lock", "polkit", "bluetoothAgent"];'],
    ["monitors is a capability", "\"hyprland\", \"bluetoothAgent\", \"monitors\", ", "\"hyprland\", \"bluetoothAgent\", "],
    ["appearance is a capability", "\"sudo\", \"appearance\", \"sounds\"", "\"sudo\", \"sounds\""],
    ["an appearance value is set", "else appearance[key] = clone(value);", "else appearance[key] = undefined;"],
    ["an appearance unset removes the member", "if (value === undefined) delete appearance[key];", "if (false) delete appearance[key];"],
    ["an empty appearance is removed", "if (Object.keys(appearance).length > 0) out.appearance = appearance;\n    else delete out.appearance;", "out.appearance = appearance;"],
    ["the appearance key is seeded from the effective one", ": isPlainObject(effective) && isPlainObject(effective.appearance) ? clone(effective.appearance) : {};", ": {};"],
    ["hyprland monitors is a key", 'var HYPRLAND_KEYS = ["binds", "layerRules", "appearance", "options", "pads", "monitors"];', 'var HYPRLAND_KEYS = ["binds", "layerRules", "appearance", "options", "pads"];'],
    ["optionsFrom needs a string", "if (entry.type !== \"string\")\n                return at + \".optionsFrom needs type string\";", "if (false)\n                return at + \".optionsFrom needs type string\";"],
    ["hyprland monitors need the capability", "if (monitors !== undefined && capabilities.indexOf(\"monitors\") === -1)\n        return \"hyprland.monitors needs capability monitors\";", "if (false)\n        return \"hyprland.monitors needs capability monitors\";"],
    ["hyprland monitors setting must exist", "if (!hasOwn(settings, raw.hyprland.monitors))\n                return { ok: false, error: \"hyprland.monitors names no settings key \" + JSON.stringify(raw.hyprland.monitors) };", "if (false)\n                return { ok: false, error: \"hyprland.monitors names no settings key \" + JSON.stringify(raw.hyprland.monitors) };"],
    ["hyprland monitors has no schema row", "if (hasOwn(schema, raw.hyprland.monitors))\n                return { ok: false, error: \"hyprland.monitors must not name a schema entry\" };", "if (false)\n                return { ok: false, error: \"hyprland.monitors must not name a schema entry\" };"],
    ["a second monitor owner is refused", "return owner !== \"\" && id !== owner && monitorRuleOwners(manifests, enabledIds).indexOf(id) !== -1 ? \"refused: hyprland.monitors=\" + id + \" held-by=\" + owner : \"\";", "return \"\";"],
    ["hyprland option names are setting names", "if (!STATUS_KEY_PATTERN.test(name))\n            return at + \" must be a setting name\";", "if (false)\n            return at + \" must be a setting name\";"],
    ["optionsFrom names a status key", "if (typeof entry.optionsFrom !== \"string\" || !STATUS_KEY_PATTERN.test(entry.optionsFrom))", "if (false)"],
    ["optionsFrom names its own choices entry", "if (!hasOwn(status, entry.optionsFrom) || status[entry.optionsFrom].type !== \"choices\")", "if (false)"],
    ["a string entry needs presets or optionsFrom", "if (entry.type === \"string\" && entry.presets === undefined && entry.optionsFrom === undefined)", "if (false)"],
    ["presets and optionsFrom cannot coexist", "if (entry.presets !== undefined && entry.optionsFrom !== undefined)", "if (false)"],
    ["presets need a string or number", "if (entry.type !== \"string\" && entry.type !== \"number\")\n                return at + \".presets needs type string or number\";", "if (false)\n                return at + \".presets needs type string or number\";"],
    ["presets are a non-empty list", "if (!Array.isArray(entry.presets) || entry.presets.length === 0)", "if (false)"],
    ["a preset is an object", "if (!isPlainObject(preset))\n                    return presetAt + \" must be an object\";", "if (false)\n                    return presetAt + \" must be an object\";"],
    ["a preset carries known keys", "if (PRESET_KEYS.indexOf(presetKeys[pk]) === -1)", "if (false)"],
    ["a preset has a value", "if (!hasOwn(preset, \"value\"))\n                    return presetAt + \".value is required\";", "if (false)\n                    return presetAt + \".value is required\";"],
    ["a preset label is printable", "if (preset.label !== undefined && !isPrintableLine(preset.label, PRESET_LABEL_MAX))", "if (false)"],
    ["an empty preset value has a label", "if (preset.value === \"\" && preset.label === undefined)", "if (false)"],
    ["preset values are distinct", "if (seenPresets.indexOf(presetKey) !== -1)", "if (false)"],
    ["preset values fit the schema", "if (badPreset !== \"\")\n                    return presetAt + \".value does not fit its schema: \" + badPreset;", "if (false)\n                    return presetAt + \".value does not fit its schema: \" + badPreset;"],
    ["allowCustom needs presets or optionsFrom", "if (entry.allowCustom !== undefined && entry.presets === undefined && entry.optionsFrom === undefined)", "if (false)"],
    ["allowCustom goes beside optionsFrom", "if (entry.allowCustom !== undefined && entry.presets === undefined && entry.optionsFrom === undefined)", "if (entry.allowCustom !== undefined && entry.presets === undefined)"],
    ["allowCustom is boolean", "if (typeof entry.allowCustom !== \"boolean\")\n                return at + \".allowCustom must be a boolean\";", "if (false)\n                return at + \".allowCustom must be a boolean\";"],
    ["format needs type string", "if (entry.type !== \"string\")\n                return at + \".format needs type string\";", "if (false)\n                return at + \".format needs type string\";"],
    ["format needs presets", "if (entry.format !== undefined && entry.presets === undefined)", "if (false)"],
    ["format names a known format", "if (SettingValues.FORMATS.indexOf(entry.format) === -1)", "if (false)"],
    ["unit needs type number", "if (entry.type !== \"number\")\n                return at + \".unit needs type number\";", "if (false)\n                return at + \".unit needs type number\";"],
    ["unit names a known unit", "if (SettingValues.UNITS.indexOf(entry.unit) === -1)", "if (false)"],
    ["datetime settings are judged", "if (entry.format === \"datetime\") {\n            var problem = SettingValues.datetimeFormatProblem(value);", "if (false) {\n            var problem = SettingValues.datetimeFormatProblem(value);"],
    ["preset settings without custom accept only presets", "return entry.presets !== undefined && entry.allowCustom !== true && presetValues(entry).indexOf(value) === -1 ? \"want=one-of-presets\" : \"\";", "return \"\";"],
    ["icon is a manifest key", "\"license\", \"icon\", \"kinds\"", "\"license\", \"kinds\""],
    ["icon names a shipped icon", "!hasOwn(Lucide.ICONS, raw.icon)", "false"],
    ["bounds need a number entry", "if (entry.type !== \"number\")\n                return at + \".\" + bound + \" needs type number\";", "if (false)\n                return at + \".\" + bound + \" needs type number\";"],
    ["bounds are finite numbers", "if (typeof entry[bound] !== \"number\" || !isFinite(entry[bound]))", "if (false)"],
    ["min below max", "!(entry.min < entry.max)", "false"],
    ["step positive", "!(entry.step > 0)", "false"],
    ["group a non-empty string", "(typeof entry.group !== \"string\" || entry.group.length === 0)", "false"],
    ["schema info is judged", "        var schemaInfo = infoError(entry.info, at);\n        if (schemaInfo !== \"\")\n            return schemaInfo;\n", ""],
    ["a number under min does not fit", "if (entry.min !== undefined && value < entry.min) return", "if (false) return"],
    ["a number over max does not fit", "if (entry.max !== undefined && value > entry.max) return", "if (false) return"],
    ["a key needs a declared bind", "if (bind === undefined && !Pads.isPadShortcut(manifest.hyprland, shortcut, ConfigLogic.NAME_PATTERN))", "if (false)"],
    ["a key is a string, list or null", "if (typeof key !== \"string\" && !Array.isArray(key))\n        return \"refused: key=\" + shortcut + \" want=string-list-or-null\";", "if (false)\n        return \"refused: key=\" + shortcut + \" want=string-list-or-null\";"],
    ["a written key is normalised", "row.keys[shortcut] = keyRowValue(key);", "row.keys[shortcut] = key;"],
    ["null unbinds", "return value === null ? null : keyWriteValue(value);", "return keyWriteValue(value);"],
    ["an unset removes the key from the plugins row", "        delete row[key];", ""],
    ["a reset removes the entry", "            delete row.keys[shortcut];\n", ""],
    ["an empty keys is removed", "if (Object.keys(row.keys).length === 0) delete row.keys;", ""],
    ["a reset the row does not need changes nothing", "if (!needed)\n            return out;", "if (false)\n            return out;"],
    ["a key row is seeded from the effective row", "row = shippedRow !== undefined ? clone(shippedRow) : { id: manifest.id };\n        out.plugins = (", "row = { id: manifest.id };\n        out.plugins = ("],
    ["a bind row carries its registered description", "hasOwn(descriptions, name) ? descriptions[name] : \"\"", "\"\""],
    ["a bind row carries the manifest's key", "\"default\": hasOwn(defaultsByShortcut, bind.shortcut) ? defaultsByShortcut[bind.shortcut] : null", "\"default\": bind.key"],
    ["a bind row carries every effective key", "keys: row.keys", "keys: []"],
    ["a plugin without an icon is listed with the default", ": DEFAULT_ICON;", ": \"\";"],
    ["status is a manifest key", "\"requirements\", \"status\", \"tui\", \"menu\", \"secrets\", ", "\"requirements\", \"tui\", \"menu\", \"secrets\", "],
    ["secrets is a manifest key", "\"tui\", \"menu\", \"secrets\", ", "\"tui\", \"menu\", "],
    ["secrets is a capability", "\"doctor\", \"secrets\", ", "\"doctor\", "],
    ["hyprland is a capability", "\"secrets\", \"hyprland\", ", "\"secrets\", "],
    ["options is a hyprland key", 'var HYPRLAND_KEYS = ["binds", "layerRules", "appearance", "options", "pads", "monitors"];', 'var HYPRLAND_KEYS = ["binds", "layerRules", "appearance", "pads", "monitors"];'],
    ["options alone declare something", "appearance === undefined && options === undefined && hyprland.pads === undefined && monitors === undefined", "appearance === undefined && hyprland.pads === undefined && monitors === undefined"],
    ["options are judged", "return hyprlandOptionsError(options, schema);", "return \"\";"],
    ["options are a non-empty object", "if (!isPlainObject(options) || Object.keys(options).length === 0)", "if (false)"],
    ["an option names a table path", "if (typeof path !== \"string\" || !hasOwn(HyprlandLayer.OPTIONS, path))", "if (typeof path !== \"string\")"],
    ["an option path once", "if (paths.indexOf(path) !== -1)", "if (false)"],
    ["an option names a schema entry", "if (!hasOwn(schema, name))", "if (false)"],
    ["a boolean option takes a boolean", "return entry.type === \"boolean\" ? \"\" : \"needs a boolean", "return true ? \"\" : \"needs a boolean"],
    ["a number option takes a number", "if (entry.type !== \"number\")\n            return \"needs a number", "if (false)\n            return \"needs a number"],
    ["a number option is bounded", "entry.min === undefined || entry.max === undefined || ", ""],
    ["a number option lies in Hyprland's range", " || entry.min < row.min || entry.max > row.max)", ")"],
    ["an int option is whole", "if (row.type === \"int\" && !(", "if (false && !("],
    ["an int option's step is whole", " && (entry.step === undefined || Number.isInteger(entry.step))))", "))"],
    ["a choice option takes an enum", "if (entry.type !== \"enum\")\n            return \"needs an enum", "if (false)\n            return \"needs an enum"],
    ["a choice option offers its choices alone", "if (row.choices.indexOf(offered[o]) === -1)", "if (false)"],
    ["an enum option is an object, never a plain string", "if (!isPlainObject(option))", "if (false)"],
    ["an enum option carries only value and label", "if (OPTION_KEYS.indexOf(optionKeys[ok]) === -1)", "if (false)"],
    ["an enum option has a value", "if (typeof option.value !== \"string\" || option.value.length === 0)", "if (false)"],
    ["an enum option has a label", "if (!isPrintableLine(option.label, PRESET_LABEL_MAX))", "if (false)"],
    ["enum option values are distinct", "if (seenOptions.indexOf(option.value) !== -1)", "if (false)"],
    ["an enum stores its option values", "return entry.options.map(function (option) { return option.value; });", "return entry.options.map(function (option) { return option.label; });"],
    ["a free string option takes a string or an enum", "return entry.type === \"string\" || entry.type === \"enum\" ? \"\" : \"needs a string", "return true ? \"\" : \"needs a string"],
    ["a manifest carries its options", "options: clone(raw.hyprland.options || {})", "options: {}"],
    ["dictation actions need the capability", 'if (capabilities.indexOf("dictation") === -1)', 'if (false)'],
    ["dictation actions take setup alone", 'if (action.dictation !== "setup")', 'if (false)'],
    ["dictation actions route to core", 'if (action.dictation !== undefined)\n        return { ok: true, kind: "core", name: "dictation-setup" };', 'if (action.dictation !== undefined)\n        return { ok: true, kind: "tui", name: "setup" };'],
    ["an action is judged", "var badAction = statusActionError(entry.type, declared[a].action, at + declared[a].at, tui, system, capabilities);", "var badAction = \"\";"],
    ["an aside sits on a state", "if (entry.type !== \"state\")\n        return at + \".aside needs", "if (false)\n        return at + \".aside needs"],
    ["an aside is never on an undrawn type", 'var drawn = ["group", "hint", "info", "link", "hidden", "action", "actions", "aside"];', 'var drawn = ["group", "hint", "info", "link", "hidden", "action", "actions"];'],
    ["an aside sits beside a step", "if (entry.action === undefined && entry.actions === undefined)\n        return at + \".aside", "if (false)\n        return at + \".aside"],
    ["an aside is judged as an action", "var badAction = statusActionError(entry.type, entry.aside, at + \".aside\", tui, system, capabilities);", "var badAction = \"\";"],
    ["an aside routes to a tui", "if (entry.aside.tui === undefined)\n        return", "if (false)\n        return"],
    ["an aside opens a listed screen", "if (!isPlainObject(tui[entry.aside.tui].entry))", "if (false)"],
    ["an action sits on a presence or a state", "if (STATUS_ACTION_TYPES.indexOf(type) === -1)\n        return at + \" needs a type", "if (false)\n        return at + \" needs a type"],
    ["named actions sit on a state", "if (entry.type !== \"state\")\n                return at + \".actions needs", "if (false)\n                return at + \".actions needs"],
    ["an entry declares an action or named actions", "if (entry.action !== undefined && entry.actions !== undefined)", "if (false)"],
    ["named actions are two or more", "if (!isPlainObject(entry.actions) || Object.keys(entry.actions).length < 2)", "if (!isPlainObject(entry.actions))"],
    ["a named action's name is an identifier", "if (declared[a].name !== null && !STATUS_KEY_PATTERN.test(declared[a].name))", "if (false)"],
    ["an action may carry a tone", 'var STATUS_ACTION_KEYS = ["label", "tone", "icon"].concat(STATUS_ACTION_ROUTES);', 'var STATUS_ACTION_KEYS = ["label", "icon"].concat(STATUS_ACTION_ROUTES);'],
    ["an action may carry a mark", 'var STATUS_ACTION_KEYS = ["label", "tone", "icon"].concat(STATUS_ACTION_ROUTES);', 'var STATUS_ACTION_KEYS = ["label", "tone"].concat(STATUS_ACTION_ROUTES);'],
    ["an action's tone is danger alone", "if (action.tone !== undefined && STATUS_ACTION_TONES.indexOf(action.tone) === -1)", "if (false)"],
    ["an action's mark goes unjudged against the icon set", "if (action.icon !== undefined && (typeof action.icon !== \"string\" || !hasOwn(Lucide.ICONS, action.icon)))", "if (false)"],
    ["an accent action names a mark", "if (action.icon !== undefined && action.tone !== \"danger\")", "if (false)"],
    ["an action is an object", "if (!isPlainObject(action))\n        return at + \" must be an object\";", "if (false)\n        return at + \" must be an object\";"],
    ["an action has only its keys", "if (STATUS_ACTION_KEYS.indexOf(keys[i]) === -1)", "if (false)"],
    ["an action label is a printable line", "if (!isPrintableLine(action.label, STATUS_LABEL_MAX))\n        return at + \".label", "if (false)\n        return at + \".label"],
    ["an action names exactly one route", "return action[route] !== undefined; }).length !== 1)", "return action[route] !== undefined; }).length > 1)"],
    ["an action names a route", "return action[route] !== undefined; }).length !== 1)", "return action[route] !== undefined; }).length < 0)"],
    ["an action system step is a declared one", "if (typeof action[stepRoute] !== \"string\" || !Array.isArray(system) || system.indexOf(action[stepRoute]) === -1)", "if (false)"],
    ["an undo is a step route", "var stepRoute = action.system !== undefined ? \"system\" : action.undo !== undefined ? \"undo\" : null;", "var stepRoute = action.system !== undefined ? \"system\" : null;"],
    ["system is a capability", "\"tui\", \"system\", \"requirements\"", "\"tui\", \"requirements\""],
    ["capabilityKinds is judged", "var badCapabilityKinds = capabilityKindsError(capabilityKinds, capabilities, raw.kinds);", "var badCapabilityKinds = \"\";"],
    ["an instance holds only the capabilities its kind is given", "return !hasOwn(manifest.capabilityKinds, name) || manifest.capabilityKinds[name].indexOf(kind) !== -1;", "return true;"],
    ["systemSteps is a manifest key", "\"capabilityKinds\", \"systemSteps\", \"settings\"", "\"capabilityKinds\", \"settings\""],
    ["systemSteps is judged", "var badSteps = systemStepsError(raw.systemSteps, capabilities);", "var badSteps = \"\";"],
    ["capability system needs systemSteps", "} else if (capabilities.indexOf(\"system\") !== -1) {", "} else if (false) {"],
    ["systemSteps is a non-empty list", "if (!Array.isArray(steps) || steps.length === 0)\n        return \"systemSteps must", "if (false)\n        return \"systemSteps must"],
    ["systemSteps needs capability system", "if (capabilities.indexOf(\"system\") === -1)\n        return \"systemSteps needs", "if (false)\n        return \"systemSteps needs"],
    ["a step is one of the table", "if (typeof steps[i] !== \"string\" || SYSTEM_STEPS.indexOf(steps[i]) === -1)", "if (false)"],
    ["a step is declared once", "if (steps.indexOf(steps[i]) !== i)", "if (false)"],
    ["an absent systemSteps is normalised", "manifest.systemSteps = raw.systemSteps === undefined ? [] : raw.systemSteps.slice();", "manifest.systemSteps = raw.systemSteps;"],
    ["an action TUI is the manifest's own", "if (typeof action.tui !== \"string\" || !isPlainObject(tui) || !hasOwn(tui, action.tui))", "if (false)"],
    ["install is no action route", "var STATUS_ACTION_ROUTES = [\"tui\", \"system\", \"undo\", \"dictation\", \"file\"];", "var STATUS_ACTION_ROUTES = [\"tui\", \"install\", \"system\", \"undo\", \"dictation\", \"file\"];"],
    ["secrets are judged", "var badSecrets = secretsError(raw.secrets, capabilities, raw.status);", "var badSecrets = \"\";"],
    ["capability secrets needs secrets", "} else if (capabilities.indexOf(\"secrets\") !== -1) {", "} else if (false) {"],
    ["secrets is an object", "if (!isPlainObject(secrets))\n        return \"secrets must be an object\";", "if (false)\n        return \"secrets must be an object\";"],
    ["secrets has only its keys", "if (SECRETS_KEYS.indexOf(keys[i]) === -1)", "if (false)"],
    ["a secrets service matches its pattern", "if (typeof secrets.service !== \"string\" || !SECRET_SERVICE_PATTERN.test(secrets.service))", "if (false)"],
    ["a secrets label is a printable line", "if (!isPrintableLine(secrets.label, STATUS_LABEL_MAX))\n        return \"secrets.label", "if (false)\n        return \"secrets.label"],
    ["secrets need capability secrets", "if (capabilities.indexOf(\"secrets\") === -1)\n        return \"secrets needs capability secrets\";", "if (false)\n        return \"secrets needs capability secrets\";"],
    ["secrets need a presence list", "if (lists.length === 0)", "if (false)"],
    ["status needs capability status", "if (capabilities.indexOf(\"status\") === -1)\n        return \"status needs capability status\";", "if (false)\n        return \"status needs capability status\";"],
    ["capability status needs a status", "} else if (capabilities.indexOf(\"status\") !== -1) {", "} else if (false) {"],
    ["a status declaration holds an entry", "if (keys.length === 0)\n        return \"status must declare", "if (false)\n        return \"status must declare"],
    ["a status key matches its pattern", "if (!STATUS_KEY_PATTERN.test(key))\n            return \"status key \"", "if (false)\n            return \"status key \""],
    ["a status entry has only known keys", "if (STATUS_ENTRY_KEYS.indexOf(entryKeys[u]) === -1)", "if (false)"],
    ["a status entry names a known type", "if (STATUS_TYPES.indexOf(entry.type) === -1)\n            return at", "if (false)\n            return at"],
    ["a status label is a printable line", "if (!isPrintableLine(entry.label, STATUS_LABEL_MAX))", "if (false)"],
    ["a status group is a printable line", "if (entry.group !== undefined && !isPrintableLine(entry.group, STATUS_LABEL_MAX))", "if (false)"],
    ["status links count visible words", "isPrintableLine(PageReference.plain(text), max)", "isPrintableLine(text, max)"],
    ["status link words still obey their limit", "isPrintableLine(PageReference.plain(text), max)", "true"],
    ["status links keep a whole-string limit", "isPrintableLine(text, STATUS_MAX_BYTES) && ", ""],
    ["a status hint is a printable line", "if (entry.hint !== undefined && !statusReferenceFits(entry.hint, STATUS_HINT_MAX))", "if (false)"],
    ["status info is judged", "        var statusInfo = infoError(entry.info, at, true);\n        if (statusInfo !== \"\")\n            return statusInfo;\n", ""],
    ["a printable line holds no control character", "!SettingValues.CONTROL_OR_SEPARATOR.test(text)", "true"],
    ["a printable line has a ceiling", 'typeof text === "string" && text.length > 0 && text.length <= max &&', 'typeof text === "string" && text.length > 0 &&'],
    ["status hidden is a boolean", "if (entry.hidden !== undefined && typeof entry.hidden !== \"boolean\")", "if (false)"],
    ["a data entry is never drawn", "if (entry[drawn[d]] !== undefined)", "if (false)"],
    ["a launcherRows entry is never drawn", "if (entry.type === \"data\" || entry.type === \"launcherRows\")", "if (entry.type === \"data\")"],
    ["an absent status is normalised", "manifest.status = raw.status === undefined ? {} : clone(raw.status);", "manifest.status = clone(raw.status);"],
    ["window is a kind", "\"menu\", \"window\", \"pane\", \"service\"", "\"menu\", \"pane\", \"service\""],
    ["cover is a kind", "\"service\", \"background\", \"cover\"", "\"service\", \"background\""],
    ["cover maps only when shown true", "if (kind === \"cover\")\n        return instance.shown === true;", "if (kind === \"cover\")\n        return instance.shown !== false;"],
    ["background maps instances without shown", "if (kind === \"background\")\n        return instance.shown !== false;", "if (kind === \"background\")\n        return instance.shown === true;"],
    ["only first cover takes keyboard", "return kind === \"cover\" && screens.length > 0 && screen !== null && screens[0].name === screen.name;", "return kind === \"cover\";"],
    ["a QML screen list gives the first cover keyboard", "return kind === \"cover\" && screens.length > 0", "return kind === \"cover\" && Array.isArray(screens) && screens.length > 0"],
    ["pane is a kind", "\"window\", \"pane\", \"service\"", "\"window\", \"service\""],
    ["pane is a manifest key", "\"defaultSection\", \"pane\", \"appearance\"", "\"defaultSection\", \"appearance\""],
    ["pane key needs kind pane", "if (kinds.indexOf(\"pane\") === -1)\n        return \"pane needs kind pane\";", "if (false)\n        return \"pane needs kind pane\";"],
    ["pane key needs an object", "if (!isPlainObject(pane))\n        return \"pane must be an object\";", "if (false)\n        return \"pane must be an object\";"],
    ["pane key has only known keys", "if (PANE_KEYS.indexOf(keys[i]) === -1)", "if (false)"],
    ["pane group is printable", "if (!isPrintableLine(pane.group, PANE_GROUP_MAX))", "if (false)"],
    ["pane order is finite", "if (typeof pane.order !== \"number\" || !isFinite(pane.order))", "if (false)"],
    ["kind pane needs pane key", "} else if (raw.kinds.indexOf(\"pane\") !== -1) {", "} else if (false) {"],
    ["capability panes needs window", "if (capabilities.indexOf(\"panes\") !== -1 && raw.kinds.indexOf(\"window\") === -1)", "if (false)"],
    ["pane rows filter pane kind", "return manifests[id].kinds.indexOf(\"pane\") !== -1 && isEnabled(config, manifests[id], defaultBarId);", "return isEnabled(config, manifests[id], defaultBarId);"],
    ["pane rows filter and order by group, order, name and id", "    }).sort(function (a, b) {\n        if (a.group !== b.group) return a.group < b.group ? -1 : 1;\n        if (a.order !== b.order) return a.order - b.order;\n        if (a.name !== b.name) return a.name < b.name ? -1 : 1;\n        return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;\n    });", "    });"],
    ["panes holder is an enabled window", "return manifest.capabilities.indexOf(\"panes\") !== -1 && isEnabled(config, manifest, defaultBarId);", "return manifest.capabilities.indexOf(\"panes\") !== -1;"],
    ["window is summonable", "\"menu\", \"window\"];", "\"menu\"];"],
    ["a window is a toplevel", "if (kind === \"window\") return \"window\";", ""],
    ["an anchored window is a toplevel", "if (kind === \"window\") return \"window\";", "if (kind === \"window\" && !anchored) return \"window\";"],
    ["an anchored summon is a popup", "return anchored ? \"popup\" : \"layer\";", "return \"layer\";"],
    ["a kind no host summons is refused a surface", "if (SUMMONABLE_KINDS.indexOf(kind) === -1)\n        throw new Error(\"summonSurface", "if (false)\n        throw new Error(\"summonSurface"],
    ["only full-screen overlays capture the keyboard", "return kind === \"overlay\" && !anchored;", "return kind === \"overlay\";"],
    ["keyboard capture refuses an unsummonable kind", "if (SUMMONABLE_KINDS.indexOf(kind) === -1)\n        throw new Error(\"capturesOverlayKeyboard", "if (false)\n        throw new Error(\"capturesOverlayKeyboard"],
    ["capturing layers take exclusive focus", "return capturesOverlayKeyboard(kind, anchored) ? \"exclusive\" : \"on-demand\";", "return \"on-demand\";"],
    ["a panel or menu layer catches a press beside it", "return !capturesOverlayKeyboard(kind, false);", "return false;"],
    ["an overlay layer catches nothing", "return !capturesOverlayKeyboard(kind, false);", "return true;"],
    ["the catcher refuses a kind never built as a layer", "if (summonSurface(kind, false) !== \"layer\")\n        throw new Error(\"layerCatchesOutside", "if (false)\n        throw new Error(\"layerCatchesOutside"],
    ["a centred surface ignores reserved space", "exclusion: placement === \"center\" ? \"ignore\" : \"normal\"", "exclusion: \"normal\""],
    ["requires is refused by name", "if (hasOwn(raw, \"requires\"))", "if (false)"],
    ["shortcut bind can omit its default key", "if (bind.key === null)\n            continue;", "if (false)\n            continue;"],
    ["requirements is a manifest key", "\"hyprland\", \"requirements\", ", "\"hyprland\", "],
    ["requirements is a list", "if (!Array.isArray(requirements))\n        return \"requirements must be a list\";", "if (false)\n        return \"requirements must be a list\";"],
    ["a requirement is an object", "if (!isPlainObject(requirement))", "if (false)"],
    ["a requirement carries known keys", "if (REQUIREMENT_KEYS.indexOf(keys[k]) === -1)", "if (false)"],
    ["a requirement names one identity", "if (Number(hasCommand) + Number(hasDbus) + Number(hasNmVpn) !== 1)", "if (false)"],
    ["a NetworkManager VPN service needs its namespace", "service.indexOf(NM_VPN_SERVICE_PREFIX) !== 0", "false", "nmVpn:"],
    ["a requirement command is a bare command name", "if (!PackageManagers.validCommand(requirement.command))", "if (false)"],
    ["a requirement command is never a plugin id", "if (ID_PATTERN.test(requirement.command))", "if (false)"],
    ["a requirement dbus bus is system or session", "if (REQUIREMENT_BUSES.indexOf(requirement.dbus.bus) === -1)", "if (false)"],
    ["a requirement dbus name is well known", "if (!dbusNameValid(requirement.dbus.name))", "if (false)"],
    ["a requirement dbus carries known keys", "if (REQUIREMENT_DBUS_KEYS.indexOf(keys[k]) === -1)", "if (false)"],
    ["a requirement name is declared once", "if (names.indexOf(identity.name) !== -1)", "if (false)"],
    ["requirement packages is an object", "if (!isPlainObject(requirement.packages))", "if (false)"],
    ["requirement packages name known managers", "if (PackageManagers.managerRow(managers[m]) === null)", "if (false)"],
    ["a requirement package name is judged", "if (!PackageManagers.validName(requirement.packages[managers[m]]))", "if (false)"],
    ["requirement optional is a boolean", "typeof requirement.optional !== \"boolean\"", "false"],
    ["a requirement purpose is a string", "typeof requirement.purpose !== \"string\" || ", ""],
    ["a requirement purpose is not blank", "requirement.purpose.trim().length === 0 || ", ""],
    ["a requirement purpose is at most 120 characters", "Array.from(requirement.purpose).length > REQUIREMENT_PURPOSE_MAX || ", ""],
    ["a requirement purpose holds no control character", " || CONTROL_CHARACTER.test(requirement.purpose))", ")"],
    ["an absent requirement packages is normalized", "packages: entry.packages === undefined ? {} : clone(entry.packages)", "packages: clone(entry.packages)"],
    ["an absent requirement optional is normalized", "optional: entry.optional === true", "optional: entry.optional"],
    ["a requirement's normalized identity is its name", "return { name: requirementName(entry), title:", "return { name: entry.command, title:"],
    ["a D-Bus requirement is listed by its name", "title: title,", "title: requirementName(entry),"],
    ["a manifest carries its requirements normalized", "manifest.requirements = normalRequirements(requirements);", ""],
    ["an idle watch takes one second at least", "seconds < 1 || ", ""],
    ["an idle watch takes a day at most", " || seconds > IDLE_WATCH_MAX_SECONDS)", ")"],
    ["an idle watch takes whole seconds", "!Number.isInteger(seconds) || ", ""],
    ["an idle watch needs a handler", "IDLE_WATCH_MAX_SECONDS;\n    if (typeof onChange !== \"function\") return \"refused: idle-handler=not-a-function\";", "IDLE_WATCH_MAX_SECONDS;"],
    ["only the stage owner holds a stage watch", "if (row === null || row.plugin !== owner)", "if (row === null)"],
    ["an idle lock request carries an object ticket", "if (request.cause === \"idle\" && (request.ticket === null || typeof request.ticket !== \"object\"))", "if (false)"],
    ["a locked session takes no new cover", "if (request.locked) return refuse(\"locked\");", ""],
    ["a cover no instance draws is never presented", "if (!request.built) return refuse(\"not-built\");", ""],
    ["a cover starts with the lock only while built", "return startsWithLock && !displaysOff && built ? \"start\" : \"keep\";", "return startsWithLock && !displaysOff ? \"start\" : \"keep\";"],
    ["a revoked ticket starts no cover", "if (request.ticket === \"stale\") return refuse(\"idle-ticket-stale\");", ""],
    ["only an idle lock of an unlocked session covers it", "if (wasLocked || placement === \"secure\") return \"keep\";", ""],
    ["a manual, sleep or restore lock ends the cover", "if (cause !== \"idle\") return placement === \"none\" ? \"keep\" : \"dismiss\";", "if (cause !== \"idle\") return \"keep\";"],
    ["a cover starts with the lock only at equal times", "&& saver.seconds > 0 && saver.seconds === lock.seconds;", "&& saver.seconds > 0;"],
    ["a requirement the scan missed is reported missing", "if (missing.indexOf(entry.name) !== -1) return \"missing\";", ""],
    ["a version below its floor is outdated", "if (part < least) return \"outdated\";", ""],
    ["a version at its floor is present", "if (part < least) return \"outdated\";", "if (part <= least) return \"outdated\";"],
    ["a version above its floor is present", "if (part > least) break;", ""],
    ["a requirement without a floor is never outdated", "var read = entry.floor !== null && typeof", "var read = typeof"],
    ["a notice lists an outdated command", "var lacking = rows.filter(function (row) { return row.state !== \"present\"; });", "var lacking = rows.filter(function (row) { return row.state === \"missing\"; });"],
    ["a view lists an outdated command", "requirementRows(manifest, missing, versions).filter(function (row) { return row.state !== \"present\"; });\n    var rows", "requirementRows(manifest, missing, versions).filter(function (row) { return row.state === \"missing\"; });\n    var rows"],
    ["an update is offered for the outdated rows alone", "e.chip === name && e.update; });", "e.chip === name; });"],
    ["an entry is an update while each of its rows is outdated", "var update = row.state === \"outdated\";", "var update = false;"],
    ["a floor is three dotted numbers", "!REQUIREMENT_FLOOR.test(requirement.floor)", "false"],
    ["a floor is a string", "typeof requirement.floor !== \"string\" || ", ""],
    ["a floor needs a command", "if (requirement.floor !== undefined && requirement.command === undefined)", "if (false)"],
    ["floor is a requirement key", "\"optional\", \"purpose\", \"floor\", \"install\"];", "\"optional\", \"purpose\", \"install\"];"],
    ["install is a requirement key", "\"floor\", \"install\"];", "\"floor\"];"],
    ["any install value is accepted", "if (requirement.install !== REQUIREMENT_ON_REQUEST)\n", "if (false)\n"],
    ["an optional requirement may be installed on request", "if (requirement.optional === true)\n                return at + \".install needs a required entry", "if (false)\n                return at + \".install needs a required entry"],
    ["an on-request requirement needs no packages", "if (requirement.packages === undefined)\n                return at + \".install needs packages", "if (false)\n                return at + \".install needs packages"],
    ["an on-request requirement may carry a floor", "if (requirement.floor !== undefined)\n                return at + \".install cannot stand", "if (false)\n                return at + \".install cannot stand"],
    ["an on-request install is not normalized", "onRequest: entry.install === REQUIREMENT_ON_REQUEST", "onRequest: false"],
    ["an absent floor is normalized", "floor: entry.floor === undefined ? null : entry.floor", "floor: entry.floor"],
    ["a disabled plugin's version is not read", "if (id !== CORE_OWNER && enabled.indexOf(id) === -1) return;", ""],
    ["a missing command's version is not read", "entry.floor !== null && lacking.indexOf(entry.name) === -1 && out.indexOf", "entry.floor !== null && out.indexOf"],
    ["a version read that crashed is no answer", "if (completion.status !== 0 || completion.code !== 0)\n        return { ok: false, line: \"plugins: versions=failed", "if (completion.code !== 0)\n        return { ok: false, line: \"plugins: versions=failed"],
    ["a version answer maps commands to lines", " || !Object.keys(read).every(function (command) { return read[command] === null || typeof read[command] === \"string\"; }))", ")"],
    ["placing never writes disabledPlugins", "function withPlaced(user, manifest, placed, effective, id, shipped) {\n    id = id === undefined ? manifest.id : id;\n    var out = isPlainObject(user) ? clone(user) : {};", "function withPlaced(user, manifest, placed, effective, id, shipped) {\n    id = id === undefined ? manifest.id : id;\n    var out = isPlainObject(user) ? clone(user) : {};\n    out.disabledPlugins = Array.isArray(effective.disabledPlugins) ? effective.disabledPlugins.slice() : [];"],
    ["a widget already as asked changes nothing", "if (placed === (layoutPositionOf(effective, id, null) !== null))\n        return out;", "if (false)\n        return out;"],
    ["unplacing removes the entries", "return entry.id !== id; });", "return true; });"],
    ["unplacing lists a plugin with no row", "    seedUserBar(out, effective);\n    if (id === manifest.id && pluginRow(effective, id) === undefined) {", "    seedUserBar(out, effective);\n    if (false) {"],
    ["unplacing a builtin creates no independent row", "if (id === manifest.id && pluginRow(effective, id) === undefined) {", "if (pluginRow(effective, id) === undefined) {"],
    ["builtin restore uses its declared location", "id === manifest.id || shipped === undefined ? null : layoutPositionOf(shipped, id, null)", "null"],
    ["builtin restore follows its next declared neighbour", "at = following; break;", "break;"],
    ["builtin restore follows its previous declared neighbour", "at = preceding + 1; break;", "break;"],
    ["moving refuses a plugin without a widget", "if (!builtin && manifest.kinds.indexOf(\"bar-widget\") === -1)\n        return \"refused: moved=\" + id + \" reason=no-bar-widget\";", "if (false)\n        return \"refused: moved=\" + id + \" reason=no-bar-widget\";"],
    ["moving refuses a disabled widget", "if (placed && !isEnabled(config, manifest, defaultBarId))\n        return \"refused: moved=\" + id + \" reason=disabled\";", "if (false)\n        return \"refused: moved=\" + id + \" reason=disabled\";"],
    ["moving refuses an unplaced widget", "if (!placed)\n        return \"refused: moved=\"", "if (false)\n        return \"refused: moved=\""],
    ["moving refuses an unknown section", "if (ConfigLogic.SECTIONS.indexOf(section) === -1)\n        return \"refused: section=\" + JSON.stringify(section) + \" want=left|center|right\";", "if (false)\n        return \"refused: section=\" + JSON.stringify(section) + \" want=left|center|right\";"],
    ["moving refuses a bad index", "if (typeof index !== \"number\" || !Number.isInteger(index) || index < 0)\n        return \"refused: index=\" + JSON.stringify(index) + \" want=integer>=0\";", "if (false)\n        return \"refused: index=\" + JSON.stringify(index) + \" want=integer>=0\";"],
    ["moving uses the locator nth", "if (seen === locator.nth) return { section: locator.section, index: i, nth: locator.nth, entry: entries[i] };", "if (seen === 0) return { section: locator.section, index: i, nth: locator.nth, entry: entries[i] };"],
    ["moving uses the requested index", "target.splice(at, 0, entry);", "target.push(entry);"],
    ["moving removes the source entry", "var entry = out.bar.layout[source.section].splice(source.index, 1)[0];", "var entry = clone(out.bar.layout[source.section][source.index]);"],
    ["drop target uses the bar zone", "var section = x < width / 3 ? \"left\" : x < 2 * width / 3 ? \"center\" : \"right\";", "var section = \"left\";"],
    ["drop index removes the source before counting", "var removes = isPlainObject(from) && from.section === section && entry.id === movingId && from.nth === nth;", "var removes = false;"],
    ["drop index matches locator nth", "return isPlainObject(locator) && locator.section === section && locator.id === id && locator.nth === nth;", "return isPlainObject(locator) && locator.section === section && locator.id === id;"],
    ["an unnamed widget takes its first presence", "return !isPlaced(effective, m) && pluginRow(effective, id) === undefined;", "return false;"],
    ["a widget with a plugins row keeps no presence", "return !isPlaced(effective, m) && pluginRow(effective, id) === undefined;", "return !isPlaced(effective, m);"],
    ["a placed widget takes no second presence", "return !isPlaced(effective, m) && pluginRow(effective, id) === undefined;", "return pluginRow(effective, id) === undefined;"],
    ["a disabled widget keeps no presence", "if (!landsShown(m) || disabled.indexOf(id) !== -1)", "if (!landsShown(m))"],
    ["a widget that lands shown takes its first presence", "if (!landsShown(m) || disabled.indexOf(id) !== -1)", "if (disabled.indexOf(id) !== -1)"],
    ["a plugin with no widget lands disabled", "return manifest.kinds.indexOf(\"bar-widget\") !== -1;", "return true;"],
    ["the first presence places each widget", "forEach(function (id) { placeWidget(out, manifests[id], effective); });", "forEach(function (id) {});"],
    ["a third-party plugin of another kind is enabled by its row", "return manifest.id.indexOf(FIRST_PARTY_PREFIX) === 0 ? \"first-party\" : \"row\";", "return \"first-party\";"],
    ["a first-party plugin of another kind is enabled unlisted", "return manifest.id.indexOf(FIRST_PARTY_PREFIX) === 0 ? \"first-party\" : \"row\";", "return \"row\";"],
    ["moving reads enablement from isEnabled", "placed && !isEnabled(config, manifest, defaultBarId)", "placed && (Array.isArray(config.disabledPlugins) ? config.disabledPlugins : []).indexOf(manifest.id) !== -1"],
    ["alwaysOn is a manifest key", "\"sounds\", \"alwaysOn\", \"setupGuide\",", "\"sounds\", \"setupGuide\","],
    ["setupGuide is a manifest key", "\"alwaysOn\", \"setupGuide\",", "\"alwaysOn\","],
    ["a guide anchor is a README heading's", "|| !README_ANCHOR.test(guide.readme))", ")"],
    ["a guide heads a Setup step", "if (!Object.keys(status).some(function (key) { return status[key].setup === true; }))\n        return \"setupGuide needs", "if (false)\n        return \"setupGuide needs"],
    ["a guide links its README section", "url: readme === \"\" ? \"\" : readme + \"#\" + guide.readme", "url: readme"],
    ["plain is a status entry key", "\"icon\", \"rowActions\", \"plain\", \"sourceAction\"];", "\"icon\", \"rowActions\", \"sourceAction\"];"],
    ["plain needs a state that is no Setup step", "if (entry.type !== \"state\" || setupStep(entry) !== \"\")\n                return at + \".plain", "if (false)\n                return at + \".plain"],
    ["a plain state draws as text only while it needs nothing", "if (entry.plain === true && STATUS_ROW_CHIP_TONES.indexOf(value.tone) === -1) return \"\";", "if (entry.plain === true) return \"\";"],
    ["a plain state draws as text", "if (entry.plain === true && STATUS_ROW_CHIP_TONES.indexOf(value.tone) === -1) return \"\";", ""],
    ["alwaysOn is a boolean", "if (typeof raw.alwaysOn !== \"boolean\")", "if (false)"],
    ["alwaysOn needs the first-party rule", "if (raw.alwaysOn && enablementRule(raw) !== \"first-party\")", "if (false)"],
    ["an alwaysOn plugin is enabled whatever the configuration lists", "if (manifest.alwaysOn === true)\n        return true;", ""],
    ["an alwaysOn plugin refuses a disable", "if (!enabled && manifest.alwaysOn === true)", "if (false)"],
    ["an alwaysOn plugin takes an enable", "if (!enabled && manifest.alwaysOn === true)", "if (manifest.alwaysOn === true)"],
    ["a widget-only plugin is enabled only by its placement", "if (manifest.kinds.every(function (k) { return k === \"bar-widget\"; })) return \"widget\";", ""],
    ["a copied entry setting shares nothing with its source", "target[k] = clone(entry[k]);", "target[k] = entry[k];"],
    ["open chooses a window over a panel", "if (manifest.kinds.indexOf(\"window\") !== -1) return \"window\";\n    if (manifest.kinds.indexOf(\"panel\") !== -1) return \"panel\";", "if (manifest.kinds.indexOf(\"panel\") !== -1) return \"panel\";\n    if (manifest.kinds.indexOf(\"window\") !== -1) return \"window\";"],
    ["a disabled plugin's placement is refused", "if (!isEnabled(config, manifest, defaultBarId))\n        return \"refused: placed=\"", "if (false)\n        return \"refused: placed=\""],
    ["a plugin without a widget is refused placement", "if (!builtin && manifest.kinds.indexOf(\"bar-widget\") === -1)\n        return \"refused: placed=\"", "if (false)\n        return \"refused: placed=\""],
    ["a hidden bar maps no surface", "return instance === null || instance.shown !== false;", "return true;"],
    ["a bar being built maps its surface", "return instance === null || instance.shown !== false;", "return instance !== null && instance.shown !== false;"],
    ["a list entry's keys are judged", "var listBad = Pads.listEntryError(entry, at, status, schemaError);", "var listBad = \"\";"],
    ["a list value is judged", "if (entry.type === \"list\") return Pads.listValueError(entry, value, settingError, ConfigLogic.NAME_PATTERN);", "if (entry.type === \"list\") return \"\";"],
    ["list is a setting type", "\"enum\", \"list\"];", "\"enum\"];"],
    ["items and defaults are schema entry keys", ", \"items\", \"defaults\", \"placeholder\", \"hideEmpty\",", ", \"placeholder\", \"hideEmpty\","],
    ["placeholder is a schema entry key", ", \"defaults\", \"placeholder\", \"hideEmpty\",", ", \"defaults\", \"hideEmpty\","],
    ["tooltip is a schema entry key", "\"info\", \"tooltip\", \"link\"", "\"info\", \"link\""],
    ["a tooltip needs a flat setting", "if (entry.type === \"list\")\n                return at + \".tooltip needs a flat setting\";", "if (false)\n                return at + \".tooltip needs a flat setting\";"],
    ["a tooltip is a printable line", "if (!isPrintableLine(entry.tooltip, TOOLTIP_MAX))", "if (false)"],
    ["a label fits its lines", " && labelLines(entry.label, lineCharacters) > LABEL_LINES)", " && false)"],
    ["an info mark narrows the label", "var lineCharacters = entry.info === undefined ? LABEL_LINE_CHARACTERS : INFO_LABEL_LINE_CHARACTERS;", "var lineCharacters = LABEL_LINE_CHARACTERS;"],
    ["a list label is not judged", "if (entry.type !== \"list\" && labelLines(", "if (labelLines("],
    ["a word longer than a line does not fit", "if (ink > perLine)\n            return Infinity;", "if (false)\n            return Infinity;"],
    ["a label that does not fit a line takes another", "lines += 1;", "lines += 0;"],
    ["a space at a line's end takes no room", "var ink = segments[i].replace(/ +$/, \"\").length;", "var ink = segments[i].length;"],
    ["a line breaks after a hyphen", "var segments = text.match(", "var segments = text.replace(/-/g, \"_\").match("],
    ["a hyphen before a digit keeps its word", "(?:[^ -]|-(?=[0-9]))*", "[^ -]*"],
    ["hideEmpty is a schema entry key", ", \"placeholder\", \"hideEmpty\", \"groupLabel\"", ", \"placeholder\", \"groupLabel\""],
    ["hideEmpty needs optionsFrom", "if (entry.optionsFrom === undefined)\n                return at + \".hideEmpty needs optionsFrom\";", "if (false)\n                return at + \".hideEmpty needs optionsFrom\";"],
    ["hideEmpty is a boolean", "if (typeof entry.hideEmpty !== \"boolean\")", "if (false)"],
    ["shownWhen is a schema entry key", "\"group\", \"shownWhen\", \"problem\"", "\"group\", \"problem\""],
    ["problem is a schema entry key", "\"shownWhen\", \"problem\", \"items\"", "\"shownWhen\", \"items\""],
    ["problem needs a flat setting", "if (entry.type === \"list\")\n                return at + \".problem needs a flat setting\";", "if (false)\n                return at + \".problem needs a flat setting\";"],
    ["problem is a string", "if (typeof entry.problem !== \"string\" || ", "if ("],
    ["problem names a text entry", " || status[entry.problem].type !== \"text\")", ")"],
    ["problem carries its published text", "hasOwn(values, problem) ? values[problem] : \"\"", "hasOwn(values, problem) ? \"\" : \"\""],
    ["an unreported problem is empty", "hasOwn(values, problem) ? values[problem] : \"\"", "values[problem]"],
    ["shownWhen needs a flat setting", "if (entry.type === \"list\")\n                return at + \".shownWhen needs a flat setting\";", "if (false)\n                return at + \".shownWhen needs a flat setting\";"],
    ["shownWhen names a presence entry", " && status[shown].type === \"presence\" ? \"\"", " ? \"\""],
    ["a setting gate names an enum or boolean", "(gate.type !== \"enum\" && gate.type !== \"boolean\")", "false"],
    ["a setting gate is always shown", "if (gate.shownWhen !== undefined)\n        return", "if (false)\n        return"],
    ["a setting gate's values fit it", "if (settingError(gate, shown.in[v]) !== \"\") return", "if (false) return"],
    ["a present entry shows its field", "values[shown] === \"present\")", "values[shown] !== \"absent\")"],
    ["an unreported entry withholds its field", "!(hasOwn(values, shown) && values[shown] === \"present\")", "(hasOwn(values, shown) && values[shown] !== \"present\")"],
    ["a field without shownWhen is never withheld", "if (shown === undefined) return false;", ""],
    ["a setting gate follows the setting", "return shown.in.indexOf(settings[shown.setting]) === -1;", "return false;"],
    ["an option names its group", 'var OPTION_KEYS = ["value", "label", "group"];', 'var OPTION_KEYS = ["value", "label"];'],
    ["options all declare a group or none", "if (grouped !== entry.options.length)", "if (false)"],
    ["one group's options stand together", "if (order[i] !== order[i - 1] && order.indexOf(order[i]) < i) return", "if (false) return"],
    ["groups are counted", "if (groups.length < OPTION_GROUPS_MIN || groups.length > OPTION_GROUPS_MAX)", "if (false)"],
    ["one group holds several options", "if (many.length > 1)", "if (false)"],
    ["a group of several options is labelled", "if ((many.length === 1) !== (entry.groupLabel !== undefined))", "if (false)"],
    ["a grouped row carries its groups", "groups: schema[key].type !== \"enum\" ? [] : groupsOf(schema[key])", "groups: [] && groupsOf(schema[key])"],
    ["an Add entry needs optionsFrom", "if (entry.optionsFrom === undefined)\n                return at + \".addChoice needs optionsFrom\";", "if (false)\n                return at + \".addChoice needs optionsFrom\";"],
    ["an Add entry's screen is declared", "return schema[key].addChoice !== undefined && !(isPlainObject(raw.tui) && hasOwn(raw.tui, schema[key].addChoice.tui));", "return false;"],
    ["an Add entry of a plugin that is off opens nothing", "if (!enabled)\n        return { ok: false, answer: tuiRefusal(entry.addChoice.tui, \"disabled\").answer };", ""],
    ["a preview needs optionsFrom", "(entry.preview !== true || entry.optionsFrom === undefined)", "(entry.preview !== true)"],
    ["an optional step is no required one", 'return entry.setup === true ? "required" : entry.setup === SETUP_OPTIONAL ? "optional" : "";', 'return entry.setup === true || entry.setup === SETUP_OPTIONAL ? "required" : "";'],
    ["only a Setup step says the user cannot act on it", "if (value.available === false && (setupStep(entry) === \"\" || ", "if (value.available === false && ("],
    ["a required step never hides", "if (entry.setup === true && statusStateHidden(value)) return false;", "if (statusStateHidden(value)) return false;"],
    ["a placeholder needs optionsFrom", "if (entry.optionsFrom === undefined)\n                return at + \".placeholder needs optionsFrom\";", "if (false)\n                return at + \".placeholder needs optionsFrom\";"],
    ["a placeholder is a bounded printable line", "if (!isPrintableLine(entry.placeholder, STATUS_LABEL_MAX))", "if (false)"],
    ["pads are a hyprland key", 'var HYPRLAND_KEYS = ["binds", "layerRules", "appearance", "options", "pads", "monitors"];', 'var HYPRLAND_KEYS = ["binds", "layerRules", "appearance", "options", "monitors"];'],
    ["pads are judged", "var padsBad = Pads.manifestError(hyprland.pads, capabilities, schema);", "var padsBad = \"\";"],
    ["a manifest carries its pads", "            pads: raw.hyprland.pads,\n", "            pads: undefined,\n"],
    ["pads are expanded", "var pads = Pads.expand(declared.pads, manifest.schema, settings, keys, ConfigLogic.hyprlandKey, settingError);", "var pads = Pads.expand(undefined, manifest.schema, settings, keys, ConfigLogic.hyprlandKey, settingError);"],
    ["pad binds end the binds", "binds: binds.concat(pads.binds),", "binds: binds,"],
    ["pad refusals are handed on", "padRefusals: pads.refusals,", "padRefusals: [],"],
    ["a pad's key is no unknown key", " && !Pads.isPadShortcut(declared, name, ConfigLogic.NAME_PATTERN); }).sort()", "; }).sort()"],
    ["a pad's key is declared", " && !Pads.isPadShortcut(manifest.hyprland, shortcut, ConfigLogic.NAME_PATTERN))\n        return \"refused: key=", ")\n        return \"refused: key="],
    ["placement needs the widget kind", "return manifest.kinds.indexOf(\"bar-widget\") !== -1 && layoutIds(config).indexOf(manifest.id) !== -1;", "return layoutIds(config).indexOf(manifest.id) !== -1;"],
    ["a bind explanation must be text", "if (bind.info !== undefined && (typeof bind.info !== \"string\" || bind.info.length === 0))", "if (false)"],
    ["a bind keeps its explanation", "if (bind.info !== undefined) result.info = bind.info;", ""],
    ["a Keys row carries its bind's explanation", "if (bind.info !== undefined) infoByShortcut[bind.shortcut] = bind.info;", ""],
    ["notify is a capability", '"panes", "notify", "theme"', '"panes", "theme"'],
    ["notify options are an object", "if (!isPlainObject(raw))\n        return { ok: false, error: \"options want=object\" };", "if (false)\n        return { ok: false, error: \"options want=object\" };"],
    ["notify refuses an unknown key", "if (NOTIFY_KEYS.indexOf(keys[i]) === -1)", "if (false)"],
    ["a notice body holds a page reference's words", "var message = reference.text.replace(", "var message = judged.message.replace("],
    ["a page reference rides in x-vgs-page", 'if (reference.page !== "") argv.push(', 'if (false) argv.push('],
    ["a reference to no page adds no hint", 'if (reference.page !== "") argv.push(', 'if (reference.reference !== "") argv.push('],
    ["a notify title is a string", 'if (typeof raw.title !== "string" || raw.title.trim()', 'if (typeof raw.title === "planted" || raw.title.trim'],
    ["a notify title is not blank", 'raw.title.trim() === "" || raw.title.length > NOTIFY_TITLE_MAX', 'raw.title.length > NOTIFY_TITLE_MAX'],
    ["a notify title has a ceiling", '|| raw.title.length > NOTIFY_TITLE_MAX)', ')'],
    ["a notify message is a string", '(typeof raw.message !== "string" || raw.message.length > NOTIFY_MESSAGE_MAX)', '(raw.message.length > NOTIFY_MESSAGE_MAX)'],
    ["a notify message has a ceiling", '|| raw.message.length > NOTIFY_MESSAGE_MAX)', ')'],
    ["a notify tone is one the hint takes", "if (raw.tone !== undefined && NOTIFY_TONES.indexOf(raw.tone) === -1)", "if (false)"],
    ["a notify icon is a string", 'if (raw.icon !== undefined && !(typeof raw.icon === "string" && ', 'if (raw.icon !== undefined && !(String(raw.icon) && '],
    ["a notify icon has a ceiling", "raw.icon.length <= NOTIFY_ICON_MAX && NOTIFY_ICON.test(raw.icon)", "NOTIFY_ICON.test(raw.icon)"],
    ["a notify icon is a Lucide name", "&& NOTIFY_ICON.test(raw.icon)))", "))"],
    ["a notify urgency is known", "if (raw.urgency !== undefined && NOTIFY_URGENCIES.indexOf(raw.urgency) === -1)", "if (false)"],
    ["notify transient is a boolean", 'if (raw.transient !== undefined && typeof raw.transient !== "boolean")', "if (false)"],
    ["a notify click only dismisses", '"--hint=string:x-vgs-click:none", ', ''],
    ["a notify names its plugin", ', "--hint=string:x-vgs-plugin:" + pluginId];', '];'],
    ["a notify tone is a hint", 'if (judged.tone !== "") argv.push("--hint=string:x-vgs-tone:" + judged.tone);', ''],
    ["a notify icon is a hint", 'if (judged.icon !== "") argv.push("--hint=string:x-vgs-icon:" + judged.icon);', ''],
    ["a transient notify skips History", 'if (judged.transient) argv.push("--transient");', ''],
    ["a notify message escapes &", '.replace(/&/g, "&amp;")', ''],
    ["a notify message escapes <", '.replace(/</g, "&lt;")', ''],
    ["a notify message escapes >", '.replace(/>/g, "&gt;");', ';'],
    ["a notify title ends the options", 'return argv.concat(["--", judged.title, message]);', 'return argv.concat([judged.title, message]);'],
    ["sounds is a manifest key", '"secrets", "sounds", "alwaysOn",', '"secrets", "alwaysOn",'],
    ["sounds is a capability", '"appearance", "sounds", "soundSettings", ', '"appearance", "soundSettings", '],
    ["soundSettings is a capability", '"appearance", "sounds", "soundSettings", ', '"appearance", "sounds", '],
    ["dictation is a capability", '"soundSettings", "dictation"];', '"soundSettings"];'],
    ["dictation is not exclusive", 'var EXCLUSIVE_CAPABILITIES = ["lock", "polkit", "bluetoothAgent", "panes"];', 'var EXCLUSIVE_CAPABILITIES = ["lock", "polkit", "bluetoothAgent", "panes", "dictation"];'],
    ["sounds is a non-empty object", "if (!isPlainObject(sounds) || Object.keys(sounds).length === 0)", "if (false)"],
    ["sounds holds an event", "if (!isPlainObject(sounds) || Object.keys(sounds).length === 0)", "if (!isPlainObject(sounds))"],
    ["sounds needs its capability", 'if (capabilities.indexOf("sounds") === -1)\n        return "sounds needs capability sounds";', ""],
    ["the sounds capability needs the key", '} else if (capabilities.indexOf("sounds") !== -1) {', "} else if (false) {"],
    ["a sound event name is judged", 'if (!ConfigLogic.NAME_PATTERN.test(name))\n            return "sounds has malformed event name "', 'if (false)\n            return "sounds has malformed event name "'],
    ["a sound event is an object", 'if (!isPlainObject(event))\n            return at + " must be an object";', ""],
    ["a sound event's keys are known", "if (SOUND_EVENT_KEYS.indexOf(keys[k]) === -1)", "if (false)"],
    ["a sound event has a label", "if (!isPrintableLine(event.label, STATUS_LABEL_MAX))", "if (false)"],
    ["a sound event's description is one line", "if (event.description !== undefined && !isPrintableLine(event.description, STATUS_HINT_MAX))", "if (false)"],
    ["an own sound has a name", "if (event.own !== undefined && !isPrintableLine(event.own, STATUS_LABEL_MAX))", "if (false)"],
    ["a sound event's default is judged", 'if (typeof event["default"] !== "string" || !soundValueFits(event, event["default"]))', "if (false)"],
    ["an event takes its offers alone", "return soundOffers(entry).some(function (offer) { return offer.value === value; });", "return typeof value === \"string\";"],
    ["an own event takes its own sound alone", "if (entry.own !== undefined)\n        return off.concat([{ value: SOUND_OWN, label: entry.own, playable: false }]);", ""],
    ["a played event does not take the own value", "    return off.concat(SOUNDS.map(function (sound) { return { value: sound.id, label: sound.label, playable: true }; }));", "    return off.concat([{ value: SOUND_OWN, label: SOUND_OWN, playable: false }], SOUNDS.map(function (sound) { return { value: sound.id, label: sound.label, playable: true }; }));"],
    ["off is a value every event takes", "var off = [{ value: SOUND_OFF, label: SOUND_OFF_LABEL, playable: false }];", "var off = [];"],
    ["a sound of the set is playable", "label: sound.label, playable: true };", "label: sound.label, playable: false };"],
    ["a row with a playable offer is testable", "testable: offers.some(function (offer) { return offer.playable; }),", "testable: false,"],
    ["held is true alone", "if (event.held !== true)", "if (false)"],
    ["held needs own", "if (event.own === undefined)\n                return at + \".held needs own\";", ""],
    ["a held event takes no default", "if (event[\"default\"] !== undefined)", "if (false)"],
    ["a held event needs no default", "beside held: the plugin states the value\";\n            continue;", "beside held: the plugin states the value\";"],
    ["a held event is the manifest's alone", "return hasOwn(manifest.sounds, event) && manifest.sounds[event].held === true;", "return hasOwn(manifest.sounds, event) && manifest.sounds[event].own !== undefined;"],
    ["a held event is lent no stored choice", "if (!soundHeld(manifest, event)) out[event] = soundValue(config, manifest, event);", "out[event] = soundValue(config, manifest, event);"],
    ["a held row reads its plugin's statement", "var stated = soundHeld(manifest, event) && hasOwn(held, id) && hasOwn(held[id], event) ? held[id][event] : null;", "var stated = null;"],
    ["a statement is read for a held event alone", "var stated = soundHeld(manifest, event) && hasOwn(held, id)", "var stated = hasOwn(held, id)"],
    ["a held row shows its plugin's problem", "problem: stated === null ? \"\" : stated.problem", "problem: \"\""],
    ["a held event's choice writes no file", "if (soundHeld(manifest, event))\n        return { ok: true, held: true };", ""],
    ["a statement names a declared event", "if (typeof event !== \"string\" || !hasOwn(manifest.sounds, event))\n        return { ok: false, answer: soundRefusal(event, \"undeclared\") };\n    if (!soundHeld(manifest, event))", "if (!soundHeld(manifest, event))"],
    ["a statement names a held event", "if (!soundHeld(manifest, event))\n        return { ok: false, answer: soundRefusal(event, \"stored\") };", ""],
    ["a statement's value is judged", "if (value !== null && !soundValueFits(manifest.sounds[event], value))", "if (false)"],
    ["a statement's problem is one printable line", "if (problem !== \"\" && !isPrintableLine(problem, STATUS_HINT_MAX))", "if (false)"],
    ["a manifest carries its sounds", "manifest.sounds = raw.sounds === undefined ? {} : clone(raw.sounds);", ""],
    ["a sound choice that fits replaces the default", 'return soundValueFits(entry, chosen) ? chosen : entry["default"];', 'return entry["default"];'],
    ["a sound choice that does not fit reads as the default", 'return soundValueFits(entry, chosen) ? chosen : entry["default"];', 'return chosen !== undefined ? chosen : entry["default"];'],
    ["a sound choice is the plugin's own", "? config.sounds[manifest.id][event] : undefined;", "? config.sounds[Object.keys(config.sounds)[0]][event] : undefined;"],
    ["sound rows list enabled plugins alone", "return Object.keys(manifests[id].sounds).length > 0 && isEnabled(config, manifests[id], defaultBarId);", "return Object.keys(manifests[id].sounds).length > 0;"],
    ["sound rows sort by plugin name", "var left = manifests[a].name, right = manifests[b].name;\n        if (left !== right) return left < right ? -1 : 1;", "var left = manifests[a].name, right = manifests[b].name;"],
    ["a sound row carries what the event sounds now", "value: !soundHeld(manifest, event) ? soundValue(config, manifest, event) : stated", "value: !soundHeld(manifest, event) ? entry[\"default\"] : stated"],
    ["a held row never reads the stored choice", "value: !soundHeld(manifest, event) ? soundValue(config, manifest, event) : stated", "value: stated === null ? soundValue(config, manifest, event) : stated"],
    ["an undeclared sound event is not played", "if (typeof event !== \"string\" || !hasOwn(manifest.sounds, event))\n        return { ok: false, answer: soundRefusal(event, \"undeclared\") };\n    if (manifest.sounds[event].own !== undefined)", "if (typeof event !== \"string\" || manifest.sounds[event] === undefined)\n        return { ok: false, answer: soundRefusal(event, \"undeclared\") };\n    if (manifest.sounds[event].own !== undefined)"],
    ["an own sound event is not played by the core", "if (manifest.sounds[event].own !== undefined)\n        return { ok: false, answer: soundRefusal(event, \"own\") };", ""],
    ["an event that is off plays nothing", "return value === SOUND_OFF ? { ok: false, answer: \"off\" } : { ok: true, sound: value };", "return { ok: true, sound: value };"],
    ["a sound refusal stays one line", "(typeof event === \"string\" && ConfigLogic.NAME_PATTERN.test(event) ? event : JSON.stringify(event)) + \" reason=\" + reason;", "event + \" reason=\" + reason;"],
    ["a sound edit of an unknown plugin is refused", "if (manifest === null)\n        return { ok: false, answer: \"unknown: \" + id };\n    if (typeof event !== \"string\" || !hasOwn(manifest.sounds, event))\n        return { ok: false, answer: soundRefusal(event, \"undeclared\") };\n    if (!soundValueFits", "if (typeof event !== \"string\" || !hasOwn(manifest.sounds, event))\n        return { ok: false, answer: soundRefusal(event, \"undeclared\") };\n    if (!soundValueFits"],
    ["a sound edit judges its value", "if (!soundValueFits(manifest.sounds[event], value))\n        return { ok: false, answer: soundRefusal(event, \"value\") };", ""],
    ["a sound edit equal to the default removes the choice", "if (value === manifest.sounds[event][\"default\"]) delete own[event];\n    else own[event] = value;", "own[event] = value;"],
    ["a plugin's empty sound choices are removed", "if (Object.keys(own).length > 0) sounds[id] = own;\n    else delete sounds[id];", "sounds[id] = own;"],
    ["an empty sounds key is removed", "if (Object.keys(sounds).length > 0) out.sounds = sounds;\n    else delete out.sounds;", "out.sounds = sounds;"],
    ["the sounds key is seeded from the effective one", ": isPlainObject(effective) && isPlainObject(effective.sounds) ? clone(effective.sounds) : {};", ": {};"],
    ["a sound plays with the event role", '["pw-play", "--media-role", "Notification", directory + "/" + entry.file]', '["pw-play", directory + "/" + entry.file]'],
    ["a sound the set lacks has no argv", 'return entry === null ? null : ["pw-play"', 'return entry === null ? ["pw-play"] : ["pw-play"'],
    ["a side view takes the drop over it", "x >= view.x && x < view.x + view.width) section = side;", "false) section = side;"],
    ["a scrolled section slots among its shown widgets", "widgets = widgets.filter(function (widget) { return widget.x >= low && widget.x + widget.width <= high; });", ""],
    ["a drop past the shown widgets lands before the hidden next", "var target = slot < widgets.length ? widgets[slot] : next;", "var target = slot < widgets.length ? widgets[slot] : null;"],
    ["PluginLogic keeps no copy of a moved name", "var KINDS = [", "var SECTIONS = [\"left\", \"center\", \"right\"];\nvar KINDS = ["],
    ["PluginLogic keeps no alias of ConfigLogic", "var KINDS = [", "var judgeConfig = ConfigLogic.configError;\nvar KINDS = ["],
    ["formerIds may not hold the plugin's own id", "if (former === raw.id)", "if (false)"],
    ["the first claim of a former id wins", "else if (hasOwn(renames, former))", "else if (false)"],
    ["a claim of a scanned plugin's id is left out", "if (hasOwn(manifests, former))", "if (false)"],
    ["an installed claim renames nothing", 'if (sourceOf(manifests[id]) !== "bundled") {', "if (false) {"],
    ["PluginLogic reads the sections through ConfigLogic", "    ConfigLogic.SECTIONS.forEach(function (section) {\n        sectionEntries(config, section)", "    [\"left\", \"center\", \"right\"].forEach(function (section) {\n        sectionEntries(config, section)"],
];

// The controls on ConfigLogic.js, the configuration judge PluginLogic.js imports.
// The list judge's rules the rows above reach through validateManifest;
// scripts/test-pads.js holds the rest.
const PADS_CONTROLS = [
    ["an item field declares no select entries", "if (plain !== undefined)\n            return", "if (false)\n            return"],
    ["an item enum declares no option groups", "&& entry.items[fields[i]].options.some(function (option) { return isPlainObject(option) && option.group !== undefined; }))", "&& false)"]
];
const CONFIG_CONTROLS = [
    ["review destination presence wins", "if (!hasOwn(out.packages.review, key)) out.packages.review[key] = row[old];", "if (!out.packages.review[key]) out.packages.review[key] = row[old];", "review transfer:"],
    ["a split always records its target", "        rows.push(target);", "        if (source) rows.push(target);", "splitPlugins:"],
    ["appearance is an object", "if (config.appearance !== undefined && !isPlainObject(config.appearance))", "if (false)"],
    ["packages is an object", "if (!isPlainObject(config.packages))\n            return \"packages must be an object\";", "if (false)\n            return \"packages must be an object\";"],
    ["welcome is an object", "        if (!isPlainObject(config.welcome))\n            return \"welcome must be an object\";\n", ""],
    ["welcome key lines are rows with ids", "        if ((bad = rows(config.welcome.keys, \"welcome.keys\")) !== \"\")\n            return bad;\n", ""],
    ["a welcome key line holds a shortcut and text", "typeof line.shortcut !== \"string\" || typeof line.text !== \"string\" || line.text === \"\"", "false"],
    ["packages.elevate is an elevation command", "config.packages.elevate !== undefined && PackageManagers.ELEVATORS.indexOf(config.packages.elevate) === -1", "false"],
    ["a key string is judged", "if (!key.ok)\n            return itemAt + \" \" + key.error;", "if (false)\n            return itemAt + \" \" + key.error;"],
    ["an empty key list is refused", "if (Array.isArray(value) && value.length === 0)\n        return at + \" must not be an empty list\";", "if (false)\n        return at + \" must not be an empty list\";"],
    ["a key list entry is not repeated", "if (seen[key.key] !== undefined)\n            return itemAt + \" repeats \" + key.key;", "if (false)\n            return itemAt + \" repeats \" + key.key;"],
    ["a tap key from settings is lone", "if (tap === true && keyHasModifiers(key.key))", "if (false)"],
    ["config sounds is an object", 'if (!isPlainObject(config.sounds))\n            return "sounds must be an object";', ""],
    ["a plugin's sound choices are an object", 'if (!isPlainObject(chosen))\n                return "sounds." + soundIds[d] + " must be an object";', ""],
    ["a sound choice is a string", 'if (typeof chosen[events[v]] !== "string")', "if (false)"],
    ["a layout entry holds its id alone", "if (extra.length > 0)\n                        return", "if (false)\n                        return"],
    ["a migration lets the row's value win", "if (!hasOwn(row, k)) row[k] = entry[k];", "row[k] = entry[k];"],
    ["a migrated entry keeps its id alone", "            return { id: entry.id };\n        });", "            return entry;\n        });"],
    ["a migration appends the row the file lacks", "                row = { id: entry.id };\n                out.plugins.push(row);", "                row = { id: entry.id };"],
    ["a migration reads every section", "    SECTIONS.forEach(function (section) {\n        if (!Array.isArray(layout[section])) return;\n        layout[section] = layout[section].map(", "    [\"left\"].forEach(function (section) {\n        if (!Array.isArray(layout[section])) return;\n        layout[section] = layout[section].map("],
    ["a migrated file takes this version", "    out.version = CONFIG_VERSION;\n    return { config: out, migrated: true };", "    return { config: out, migrated: true };"],
    ["a migration leaves its input", "    var out = clone(config);\n    var layout = isPlainObject(out.bar)", "    var out = config;\n    var layout = isPlainObject(out.bar)"],
    ["only a version 1 or unversioned file migrates", "(config.version !== 1 && config.version !== undefined)", "(config.version === 3)"],
    ["an unversioned file with nothing to move is left", "    if (config.version === undefined && !moved)\n        return same;\n", ""],
    ["a rename reaches disabledPlugins", "if (Array.isArray(out.disabledPlugins)) out.disabledPlugins = out.disabledPlugins.map(renamedId);", ""],
    ["a rename reaches plugins rows", "    renameRows(out.plugins);\n", ""],
    ["a rename reaches every layout section", "SECTIONS.forEach(function (section) { renameRows(layout[section]); });", "[\"right\"].forEach(function (section) { renameRows(layout[section]); });"],
    ["a rename leaves its input", "    var out = clone(config);\n    var renamed = false;", "    var out = config;\n    var renamed = false;"],
];

const temp = fs.mkdtempSync(path.join(os.tmpdir(), "plugin-logic-control-"));
try {
    fs.mkdirSync(path.join(temp, "shell", "Core"), { recursive: true });
    fs.mkdirSync(path.join(temp, "shell", "Commons"), { recursive: true });
    fs.mkdirSync(path.join(temp, "shell", "Ui", "icons"), { recursive: true });
    fs.symlinkSync(SETTING_VALUES, path.join(temp, "shell", "Commons", "SettingValues.js"));
    fs.symlinkSync(PAGE_REFERENCE, path.join(temp, "shell", "Commons", "PageReference.js"));
    fs.symlinkSync(LUCIDE, path.join(temp, "shell", "Ui", "icons", "Lucide.js"));
    fs.symlinkSync(path.join(path.dirname(LUCIDE), "Own.js"), path.join(temp, "shell", "Ui", "icons", "Own.js"));
    fs.symlinkSync(MANAGERS, path.join(temp, "shell", "Core", "PackageManagers.js"));
    fs.symlinkSync(LAYER, path.join(temp, "shell", "Core", "HyprlandLayer.js"));
    fs.symlinkSync(path.join(path.dirname(LAYER), "MonitorLogic.js"), path.join(temp, "shell", "Core", "MonitorLogic.js"));
    const sources = { [LOGIC]: fs.readFileSync(LOGIC, "utf8"), [CONFIG]: fs.readFileSync(CONFIG, "utf8"), [PADS]: fs.readFileSync(PADS, "utf8") };
    const copyOf = file => path.join(temp, "shell", "Core", path.basename(file));
    for (const [file, controls] of [[LOGIC, CONTROLS], [CONFIG, CONFIG_CONTROLS], [PADS, PADS_CONTROLS]]) {
        for (const [label, needle, replacement, filter] of controls) {
            const count = sources[file].split(needle).length - 1;
            if (count !== 1) { report("control: " + label + ": the text to replace occurs once", count, 1); continue; }
            for (const [other, text] of Object.entries(sources)) fs.writeFileSync(copyOf(other), text);
            fs.writeFileSync(copyOf(file), sources[file].replace(needle, () => replacement));
            // Loaded outside the try, so a copy that does not evaluate fails the
            // suite instead of passing for a control.
            const ctx = load(copyOf(LOGIC));
            const configLogic = load(copyOf(CONFIG));
            let red = 0;
            try {
                const check = (name, got, want) => { if ((!filter || name.includes(filter)) && JSON.stringify(got) !== JSON.stringify(want)) red += 1; };
                if (filter === "unplaced mounts:") unplacedMounts(ctx, check);
                else if (filter === "nmVpn:") nmVpnRequirements(ctx, check);
                else suite(ctx, configLogic, check);
            } catch (e) {
                red += 1;
            }
            report("control: the suite fails without the rule: " + label, red > 0, true);
        }
    }
    // providersFor that builds every capability for every kind hands the
    // service the pane's hyprland.
    const loops = CAPABILITIES_SOURCE.split(PROVIDERS_LOOP).length - 1;
    report("control: providersFor's loop occurs once", loops, 1);
    const logic = load(LOGIC);
    const paneOnly = logic.validateManifest({ schemaVersion: 1, id: "acme.kinds", name: "K", version: "1", author: "a", description: "d", kinds: ["pane", "service"], entryPoints: { pane: "Pane.qml", service: "Service.qml" }, pane: { group: "System", order: 1 }, capabilities: ["hyprland", "notify"], capabilityKinds: { hyprland: ["pane"] } }, "/p").manifest;
    const flatLoop = CAPABILITIES_SOURCE.replace(PROVIDERS_LOOP, () => "for (const name of ctx.manifest.capabilities) {");
    report("control: a providersFor that ignores the kind hands the service hyprland", JSON.stringify(providersHeld(flatLoop, logic, paneOnly, "service")), JSON.stringify({ held: ["hyprland", "notify"], providers: ["hyprland", "notify"] }));
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}

if (failures > 0) { console.log("test-plugin-logic: " + failures + " failing"); process.exit(1); }
console.log("test-plugin-logic: ok");
