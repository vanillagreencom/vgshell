#!/usr/bin/env node
// Exercises the production page judge with PluginLogic manager rows.
// Required work alone creates Setup. Unknown and blocked required work
// stays open; a step the user cannot act on, by its value or because its
// plugin could not start, reads neutral after the open steps and raises no Setup needed; a
// step a missing required tool blocks offers the one install action on its
// own row. Settings draws only values and their stored key lists, and
// optional work, its action and its tools belong on Details. Required
// tools form one persistent step. Every To do step and every Details fact
// that holds work draws an action that takes a press, with the plugin on
// and off; a fact whose feature is set up draws none.
// Expected placements and actions are independent data. The source check
// reaches the actual Setup body: it proves that body declares no boxed
// Button, not rendered behavior. Each control edits production source and
// fails its named assertion.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");
const root = path.join(__dirname, "..");
const file = path.join(root, "shell/plugins/vgs.settings/Steps.js");
const producerFile = path.join(root, "shell/Core/PluginLogic.js");
const pageFile = path.join(root, "shell/plugins/vgs.settings/PluginPage.qml");
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message);
const REVIEW = "Review all missing or outdated tools";
const TURN_ON = "Turn on Fixture";
const schema = {
    feature: { type: "boolean", label: "Feature", description: "Turns the feature on" },
    mode: { type: "boolean", label: "Mode", description: "Changes the mode" }
};
const entry = (label, more) => Object.assign({ label: label, icon: "wrench", group: "Fixture" }, more);
const tui = {
    required: { entry: entry("Set model"), requires: ["required-a"] },
    feature: { entry: entry("Configure feature"), requires: [] },
    configure: { entry: entry("Configure", { settings: true }), requires: [] },
    task: { entry: entry("Sign in"), requires: ["optional-tool"] },
    chore: { entry: entry("Run chore"), requires: [] },
    extra: { entry: entry("Feature action"), requires: [] },
    fixing: { entry: null, requires: [] }
};
const status = {
    model: { type: "state", label: "Model", setup: true, action: { label: "Set model", tui: "required" } },
    home: { type: "state", label: "Home", setup: true, hint: "Choose a home folder first" },
    account: { type: "state", label: "Account", setup: true, actions: { signIn: { label: "Sign in", tui: "task" }, key: { label: "Add key", tui: "required" } } },
    optional: { type: "state", label: "Feature state", action: { label: "Configure feature", tui: "feature" } },
    keys: { type: "presenceList", label: "Provider keys", setting: "feature" },
    ownedState: { type: "state", label: "Owned state", action: { label: "Fix owned", tui: "fixing" } },
    connection: { type: "state", label: "Connection", setup: true },
    connectionKeys: { type: "presenceList", label: "Connection keys", step: "connection" },
    fact: { type: "state", label: "Automatic work" }
};
const ready = { tone: "ok", text: "Ready", action: false };
const blocked = { tone: "warning", text: "Waiting for account" };
const allDone = { model: ready, home: ready, account: ready, connection: ready, ownedState: ready,
    optional: { tone: "warning", text: "Feature unavailable", action: true }, fact: { tone: "danger", text: "Alternative unavailable" } };
const homeUnreported = Object.fromEntries(Object.entries(allDone).filter(([key]) => key !== "home"));
const on = { enabled: true, name: "Fixture", error: "", failed: false };
const off = { enabled: false, name: "Fixture", error: "", failed: false };
// A step the user cannot act on, as its plugin publishes it, and one a
// missing or outdated required tool blocks.
const unavailable = { tone: "warning", text: "No reader on this computer", hint: "Connect a reader to set this up", available: false };
const toolBlocked = { tone: "warning", text: "Needs its tool", action: "tools" };
const items = sections => sections.flatMap(section => section.items);
// What BUTTONS, Steps.detailButtons', offer to press: [label, takes a
// press] per action, in order.
const offers = buttons => [buttons.action, buttons.aside].filter(button => button !== null).map(button => [button.label, button.enabled]);

function verify(logic, producer) {
    const manifest = {
        status: status, tui: tui,
        requirements: producer.normalRequirements([
            { command: "required-a", purpose: "Basic work" },
            { command: "required-b", purpose: "Basic work" },
            { command: "optional-tool", optional: true, purpose: "Optional feature" },
            { dbus: { bus: "system", name: "org.example.Tool", label: "Tool service" }, optional: true, purpose: "Its own feature" },
            { command: "automatic-tool", optional: true, purpose: "Automatic alternative" }
        ])
    };
    const fields = producer.fieldRows(schema, status);
    const screens = producer.listedTuis(manifest);
    const rows = values => producer.statusRows(manifest, values);
    const requirements = missing => producer.requirementRows(manifest, missing, {});
    const page = (values, missing) => ({ schema: schema, status: rows(values), tuis: screens, requirements: requirements(missing) });
    const lines = (values, missing) => fields.flatMap(field => logic.featureRow(field, page(values, missing)).map(line => [field.key, line.kind, line.key]));
    const buttonsOf = (key, values, plugin) => logic.detailButtons(rows(values).find(entry => entry.key === key), plugin);

    const status0 = rows(allDone), sections = logic.setupSections(screens, status0);
    same(items(sections).map(item => item.key), ["model", "home", "account", "connection", "connectionKeys"], "optional entries never draw on Setup");
    same(lines(allDone, ["optional-tool"]), [["feature", "keys", "keys"]], "a Settings field draws its stored key list alone: no state, tools or screens line");
    same(logic.detailEntries(status0).map(entry => entry.key), ["optional", "ownedState", "fact"], "Details lists each former Settings entry and excludes Setup steps and Settings key lists");
    same(logic.setupTab(sections, []), true, "completed required steps keep Setup");
    same(logic.setupTab([], requirements([])), true, "present required tools keep Setup");
    const optionalOnly = requirements(["optional-tool"]).filter(row => row.optional);
    same(logic.setupTab([], optionalOnly), false, "optional tools never create Setup");
    same(logic.requirementStep(optionalOnly), null, "optional tools never create the Tools step");
    same(logic.detailRequirements(requirements([])).map(row => row.name), ["optional-tool", "org.example.Tool", "automatic-tool"], "every optional tool is on Details");
    for (const [label, missing, want] of [
        ["a missing optional tool", ["optional-tool"], REVIEW],
        ["a missing required tool alone", ["required-a"], null],
        ["every tool present", [], null]
    ]) {
        const review = logic.toolsReview(logic.detailRequirements(requirements(missing)));
        same(review === null ? null : review.label, want, "Details Tools: " + label);
    }
    for (const [label, values, missing, enabled, expected] of [
        ["all required work ready", allDone, [], true, false],
        ["only Home blocked", Object.assign({}, allDone, { home: blocked }), [], true, true],
        ["Home not reported", homeUnreported, [], true, true],
        ["failed required step", Object.assign({}, allDone, { model: { tone: "danger", text: "Refused" } }), [], true, true],
        ["required tool missing", allDone, ["required-a"], true, true],
        ["only optional tool missing", allDone, ["optional-tool"], true, false],
        ["only Home not available", Object.assign({}, allDone, { home: unavailable }), [], true, false],
        ["Home blocked by a missing tool", Object.assign({}, allDone, { home: toolBlocked }), ["required-a"], true, true],
        ["disabled plugin", {}, ["required-a"], false, false]
    ]) same(logic.setupNeeds(rows(values), requirements(missing), enabled), { open: expected }, "readiness: " + label);
    for (const [label, missing, want] of [
        ["present", [], [true, "Tools", "Done", "success", null]],
        ["missing", ["required-a", "required-b", "optional-tool"], [false, "Tools", "To do", "warning", [REVIEW, true]]]
    ]) {
        const step = logic.requirementStep(requirements(missing));
        assert.notEqual(step, null, "Tools: " + label);
        same([step.done, step.label, step.text, step.tone, step.button === null ? null : [step.button.label, step.button.enabled]], want, "Tools: " + label);
        if (missing.length) same(step.hint, "required-a (missing), required-b (missing)", "Tools names only required tools");
    }
    const outdated = requirements([]).map(row => Object.assign({}, row, { state: row.name === "required-b" ? "outdated" : "present" }));
    same(logic.requirementStep(outdated).done, false, "outdated required tools stay open");
    same(logic.requirementStep(outdated).hint, "required-b (outdated)", "Tools identifies outdated tools");
    same(logic.setupNeeds(status0, outdated, true), { open: true }, "outdated required tools warn");
    same(items(logic.setupSections(screens, status0, requirements(["required-a"]))).map(item => item.key), ["required-tools", "model", "home", "account", "connection", "connectionKeys"], "pending Tools precede completed required steps");
    same(items(logic.setupSections(screens, status0, requirements([]))).map(item => item.key), ["model", "home", "account", "connection", "connectionKeys", "required-tools"], "completed Tools retain their one step");
    const openRows = rows(Object.assign({}, allDone, { home: blocked, model: { tone: "warning", text: "Needs a key", action: true, lines: ["Open Settings"] } }));
    same(items(logic.setupSections(screens, rows(Object.assign({}, allDone, { home: blocked })))).map(item => item.key), ["home", "model", "account", "connection", "connectionKeys"], "Home-only blocker is first");
    const model = openRows.find(entry => entry.key === "model"), view = logic.stepView(model, String, on);
    same([view.text, view.tone, view.lines], ["To do", "warning", ["Needs a key", "Open Settings"]], "pending chip keeps explanation");
    const complete = logic.stepView(status0.find(entry => entry.key === "model"), String, on);
    same([complete.text, complete.tone], ["Done", "success"], "completed chip uses two-state vocabulary");
    same(logic.stepView(rows({}).find(entry => entry.key === "home"), String, off).text, "To do", "unreported required chip stays To do");

    // Setup steps: what each To do step offers to press, with the plugin
    // on and off. The page draws a step's own action while on and Turn on
    // while off (Steps.lineAction); the Tools step's Review takes a press
    // in every state.
    const stepOffers = (values, missing, plugin) => items(logic.setupSections(screens, rows(values), requirements(missing))).filter(item => !item.keys).map(item => {
        const button = item.tools === true ? item.button : logic.lineAction(item.button, logic.stepOpen(item.entry), plugin);
        return [item.key, button === null ? null : [button.label, button.enabled]];
    });
    same(stepOffers({}, ["required-a"], off), [["model", [TURN_ON, true]], ["home", [TURN_ON, true]], ["account", [TURN_ON, true]], ["connection", [TURN_ON, true]], ["required-tools", [REVIEW, true]]],
        "off: every To do step offers Turn on Fixture");
    same(stepOffers(Object.assign({}, allDone, { model: { tone: "warning", text: "Needs a key", action: true } }), [], on).find(([key]) => key === "model"), ["model", ["Set model", true]],
        "on: an offered step draws its own action");
    // Account's Sign in opens a screen that needs a missing optional tool;
    // the step offers it, and its press asks for the tool first.
    const signIn = rows(Object.assign({}, allDone, { account: { tone: "warning", text: "Signed out", action: "signIn" } })).find(entry => entry.key === "account");
    const signInButton = logic.stepButton(signIn);
    same([signInButton === null ? null : [signInButton.label, signInButton.enabled, signInButton.kind], signIn.hint.includes(REVIEW)],
        [["Sign in", true, "status"], false], "on: a step whose screen lacks an optional tool offers its own action");
    // A danger action's mark reaches the button the line draws (RowAction's `markName`).
    const signOut = { key: "account", action: { label: "Sign out", icon: "log-out", tone: "danger", offered: true, tui: "out" }, aside: { label: "Remove key", icon: "key", tone: "danger", offered: true, tui: "remove" } };
    same([logic.stepButton(signOut).icon, logic.asideButton(signOut).icon], ["log-out", "key"], "on: a step's action and aside carry their marks");
    const byHand = rows(Object.assign({}, allDone, { home: blocked })).find(entry => entry.key === "home");
    same([logic.stepButton(byHand), logic.stepView(byHand, String, on).hint], [null, status.home.hint], "on: a by-hand step draws its explanation");
    const waiting = logic.stepView(rows({}).find(entry => entry.key === "home"), String, on);
    same([logic.stepReading(rows({}).find(entry => entry.key === "home"), on), waiting.tone, waiting.lines.length, typeof waiting.lines[0]], ["todo", "warning", 1, "string"],
        "on, unreported: the step stays To do and names the wait on one line");
    same(logic.stepView(rows({}).find(entry => entry.key === "home"), String, off).lines, [], "off: an unreported step names no wait");

    // The neutral reading: a required step the user cannot act on, by its
    // value, or because the plugin, on, could not start, a failed build or
    // a refusal, which turning it off and on does not mend. [name, values, missing tools,
    // the plugin, Home's reading and chip tone, the step order].
    const failed = Object.assign({}, on, { error: "This plugin could not start.", failed: true });
    const refused = Object.assign({}, on, { error: "Another plugin uses this feature.", failed: true });
    const accountOpen = { tone: "warning", text: "Signed out", action: "signIn" };
    for (const [name, values, missing, plugin, reading, order] of [
        ["by its value, between To do and Done", Object.assign({}, allDone, { model: { tone: "warning", text: "Needs a key", action: true }, account: accountOpen, home: unavailable }), [], on,
            ["unavailable", "neutral"], ["model", "account", "home", "connection", "connectionKeys", "required-tools"]],
        ["by its value, after a pending Tools step", Object.assign({}, allDone, { account: accountOpen, home: unavailable }), ["required-a"], on,
            ["unavailable", "neutral"], ["account", "required-tools", "home", "model", "connection", "connectionKeys"]],
        ["after a failed build", {}, ["required-a"], failed,
            ["unavailable", "neutral"], ["required-tools", "model", "home", "account", "connection", "connectionKeys"]],
        ["while refused", {}, ["required-a"], refused,
            ["unavailable", "neutral"], ["required-tools", "model", "home", "account", "connection", "connectionKeys"]]
    ]) {
        const status = rows(values), home = status.find(entry => entry.key === "home");
        same([logic.stepReading(home, plugin), logic.stepView(home, String, plugin).tone], reading, "Not available " + name + ": the chip");
        same(items(logic.setupSections(screens, status, requirements(missing), plugin)).map(item => item.key), order, "Not available " + name + ": the order");
        same(logic.lineAction(logic.stepButton(home, requirements(missing)), logic.stepOpen(home), plugin), null, "Not available " + name + ": no action");
    }
    const neutral = logic.stepView(rows(Object.assign({}, allDone, { home: unavailable })).find(entry => entry.key === "home"), String, on);
    same([neutral.hint, neutral.lines], [unavailable.hint, [unavailable.text]], "Not available by its value: the step says why and what changes it");
    for (const [name, plugin] of [["after a failed build", failed], ["while refused", refused]]) {
        const view = logic.stepView(rows({}).find(entry => entry.key === "home"), String, plugin);
        same([view.lines, view.hint, view.link], [[plugin.error], "", null], "Not available " + name + ": the step draws the plain line alone");
    }
    same(items(logic.setupSections(screens, rows({}), requirements([]), failed)).filter(item => !item.keys && item.tools !== true)
        .map(item => logic.lineAction(logic.stepButton(item.entry, requirements([])), logic.stepOpen(item.entry), failed)), [null, null, null, null], "after a failed build no step draws an action");
    // Setup needed, as the Plugins list, the row's tab and the Setup tab
    // read it from the row's errors (Registry.managerRows): [name, errors,
    // missing tools, Setup needed], Home unreported throughout.
    const buildLine = "build failed: service: file:///fixture/Service.qml:12: No such type";
    const refusalLine = "refused: capability=fixture.audio held-by=acme.other";
    for (const [name, errors, missing, needed] of [
        ["after a failed build", [buildLine], [], false],
        ["after a failed build, a required tool missing", [buildLine], ["required-a"], true],
        ["built", [], [], true],
        ["refused", [refusalLine], [], false]
    ]) same(logic.setupNeeds(rows(homeUnreported), requirements(missing), true, logic.startFailed(errors)).open, needed, "Setup needed " + name);

    // A step a missing or outdated required tool blocks: [name, missing
    // tools, the action kind on Home's own row, Setup needed]. The step
    // stays To do until its plugin publishes again after the scan that
    // found its tool; Review is offered only while a required tool lacks.
    for (const [name, missing, want, needed] of [
        ["a missing required tool", ["required-a"], "tools", true],
        ["an outdated required tool", null, "tools", true],
        ["a missing optional tool alone", ["optional-tool"], null, true],
        ["every required tool present", [], null, true]
    ]) {
        const reqs = missing === null ? outdated : requirements(missing);
        const status = rows(Object.assign({}, allDone, { home: toolBlocked }));
        const home = items(logic.setupSections(screens, status, reqs, on)).find(item => item.key === "home");
        same([home.button === null ? null : home.button.kind, logic.setupNeeds(status, reqs, true).open], [want, needed], "tools: " + name);
        const drawn = logic.lineAction(logic.stepButton(home.entry, reqs), logic.stepOpen(home.entry), on);
        same(drawn === null ? null : [drawn.kind, drawn.enabled], want === null ? null : ["tools", true], "tools: " + name + ": the step's own row draws Review");
    }
    same(items(sections).find(item => item.key === "model").button, null, "unoffered required action draws nowhere");
    // Rescans restart the smoke publisher. Its absent check is unreported,
    // not an offered action blocked by a tool. The action owner reads only
    // the published state; missing tools are handled on its press.
    for (const [name, key, values, missing, plugin, want] of [
        ["required tool present", "model", { model: { tone: "warning", text: "Needs setup", action: true } }, [], on, ["status", true]],
        ["required tool missing", "model", { model: { tone: "warning", text: "Needs setup", action: true } }, ["required-a"], on, ["status", true]],
        ["optional tool missing", "account", { account: { tone: "warning", text: "Signed out", action: "signIn" } }, ["optional-tool"], on, ["status", true]],
        ["required tool outdated", "model", { model: { tone: "warning", text: "Needs setup", action: true } }, [], on, ["status", true]],
        ["reported without action", "model", { model: blocked }, ["required-a"], on, null],
        ["completed", "model", { model: ready }, ["required-a"], on, null],
        ["unreported after rescan", "model", {}, ["required-a"], on, null],
        ["by-hand explanation", "home", { home: blocked }, ["required-a"], on, null],
        ["disabled", "model", {}, ["required-a"], off, ["enable", true]]
    ]) {
        const current = page(values, missing);
        if (name === "required tool outdated") current.requirements = outdated;
        const currentEntry = current.status.find(entry => entry.key === key);
        const button = logic.lineAction(logic.stepButton(currentEntry), logic.stepOpen(currentEntry), plugin);
        same(button === null ? null : [button.kind, button.enabled], want, "step action owner: " + name);
    }

    // The status value judge: [name, the manifest, entry, value, admitted].
    const noRequiredTool = Object.assign({}, manifest, { requirements: manifest.requirements.filter(row => row.optional) });
    for (const [name, judged, key, value, admitted] of [
        ["tools on a required step of a plugin with a required tool", manifest, "home", toolBlocked, true],
        ["tools on a plugin with no required tool", noRequiredTool, "home", toolBlocked, false],
        ["tools on a Details fact", manifest, "fact", toolBlocked, false],
        ["Not available on a required step", manifest, "home", unavailable, true],
        ["Not available on a Details fact", manifest, "fact", unavailable, false],
        ["Not available on a done step", manifest, "home", Object.assign({}, unavailable, { tone: "ok" }), false],
        ["Not available with an action", manifest, "model", Object.assign({}, unavailable, { action: true }), false],
        ["Not available with tools", manifest, "home", Object.assign({}, unavailable, { action: "tools" }), false],
        ["available true", manifest, "home", Object.assign({}, unavailable, { available: true }), false],
        ["Not available with no hint", manifest, "home", (({ hint, ...value }) => value)(unavailable), false]
    ]) same(producer.statusWrite(judged, {}, key, value).ok, admitted, "judge: " + name);
    // A `tools` value adds no second install route: the entry's own act
    // offers nothing for it, whether it declares one action or several.
    for (const key of ["model", "account"]) {
        const values = Object.assign({}, allDone, { [key]: toolBlocked });
        let request = null;
        assert.doesNotThrow(() => { request = producer.statusActionRequest(manifest, "fixture", true, values, key); }, "act on a tools value: " + key);
        same(request, { ok: false, answer: producer.statusActionRefusal(key, "not-offered") }, "act on a tools value: " + key);
        same(rows(values).find(entry => entry.key === key).action.offered, false, "act on a tools value: " + key + ": its declared action is not offered");
    }

    // A file action and a value's own info. A Setup step that declares a
    // file action offers it as its status action, and the act opens its
    // path as the plugin's own edit run; a state value's `info` stands in
    // the entry's while present, judged as an entry's.
    const filedStatus = Object.assign({}, status, { notes: { type: "state", label: "Notes", setup: true, info: "Notes hold what the fixture reads",
        action: { label: "Open notes", file: "~/.local/share/fixture/notes.md" } } });
    const filed = Object.assign({}, manifest, { status: filedStatus });
    const tooLong = { tone: "warning", text: "Notes are too long", action: true, info: "The fixture reads the first 4 KB of the notes, so the rest never reaches it" };
    same(producer.statusError(filedStatus, ["status", "tui"], tui, undefined), "", "file action: a file action is admitted");
    for (const [name, path, scripts] of [
        ["a path that climbs out", "~/../notes.md", tui],
        ["a path with a control character", "notes\n.md", tui],
        ["an empty path", "", tui],
        ["a path that is no string", 3, tui],
        ["a manifest whose script is named edit", "~/notes.md", Object.assign({ edit: { entry: null, requires: [] } }, tui)]
    ]) {
        const bad = Object.assign({}, filedStatus, { notes: Object.assign({}, filedStatus.notes, { action: { label: "Open notes", file: path } }) });
        assert.ok(producer.statusError(bad, ["status", "tui"], scripts, undefined).startsWith("status.notes.action.file "), "file action: " + name + " is refused at its path");
    }
    same(producer.statusActionRequest(filed, "fixture", true, { notes: tooLong }, "notes"), { ok: true, kind: "file", path: "~/.local/share/fixture/notes.md" }, "file action: the act opens the declared path");
    same(producer.statusActionRequest(filed, "fixture", true, { notes: ready }, "notes"), { ok: false, answer: producer.statusActionRefusal("notes", "not-offered") }, "file action: a done step offers no file");
    const filedRows = values => producer.statusRows(filed, values);
    const notesStep = values => items(logic.setupSections(screens, filedRows(values), manifest.requirements, on)).find(item => item.key === "notes");
    same(((b) => [b.kind, b.label, b.enabled])(notesStep({ notes: tooLong }).button), ["status", "Open notes", true], "file action: a Setup step offers Open file on the status route");
    same(notesStep({ notes: ready }).button, null, "file action: a done step offers no file");
    same(producer.statusWrite(filed, {}, "notes", tooLong).ok, true, "value info: a value with its own info is admitted");
    for (const [name, info] of [["empty", ""], ["past the bound", "x".repeat(producer.INFO_MAX + 1)], ["two lines", "a\nb"], ["no string", 4]])
        same(producer.statusWrite(filed, {}, "notes", Object.assign({}, tooLong, { info: info })).ok, false, "value info: an info " + name + " is refused");
    same(filedRows({ notes: tooLong }).find(row => row.key === "notes").info, tooLong.info, "value info: a value's info stands in the entry's");
    same(filedRows({ notes: ready }).find(row => row.key === "notes").info, "Notes hold what the fixture reads", "value info: without its own info the entry's applies");
    same(filedRows({}).find(row => row.key === "notes").info, "Notes hold what the fixture reads", "value info: an unreported step reads the entry's info");
    same(logic.stepView(notesStep({ notes: tooLong }).entry, String, on).info, tooLong.info, "value info: the Setup step draws the value's info");

    // Details facts: [name, entry, published values, the plugin, what the
    // fact offers]. A former Settings entry keeps its action beside its
    // fact: a fact that holds work offers a press, Turn on while the
    // plugin is off, and one whose feature is set up offers none.
    for (const [name, key, values, plugin, want] of [
        ["off: a former Settings entry offers Turn on", "optional", {}, off, [[TURN_ON, true]]],
        ["off: a fact that declares no action offers nothing", "fact", {}, off, []],
        ["on: a former Settings entry offers its action", "optional", allDone, on, [["Configure feature", true]]],
        ["on: a fact whose feature is set up offers nothing", "optional", Object.assign({}, allDone, { optional: ready }), on, []],
        ["on: a fact not reported yet offers nothing", "ownedState", {}, on, []],
        ["on: a fact that declares no action offers nothing", "fact", allDone, on, []]
    ]) same(offers(buttonsOf(key, values, plugin)), want, "Details: " + name);
    same(buttonsOf("optional", allDone, on).action.kind, "status", "Details: a fact's action takes the status route its entry's replies are kept under");
    same(logic.freeScreens(screens, status0, "Settings", on).map(screen => screen.name), ["configure"], "settings screens stay in More settings");
    same(logic.freeScreens(screens, status0, "Details", on).map(screen => [screen.name, screen.enabled]), [["chore", true], ["extra", true]], "task screens alone stay in Details");
    for (const place of ["Settings", "Details"]) {
        const held = logic.freeScreens(screens, status0, place, off);
        same([held.every(screen => !screen.enabled && screen.reason === logic.offReason(off.name)), logic.withheldHint(held)], [true, logic.offReason(off.name)], "off: " + place + " screens take no press and name why");
        same(logic.withheldHint(logic.freeScreens(screens, status0, place, on)), "", "on: " + place + " screens name no reason");
    }
    same(logic.itemView({ access: "connect", value: "absent", tone: "info" }), { tone: "", text: "" }, "absent stored key gives Add key its place");
    same(logic.itemView({ access: "disconnect", value: "present", tone: "success" }, true), { tone: "success", text: "Done", reason: "" }, "required stored key uses Done");
    same(logic.itemView({ access: "connect", value: "locked", tone: "info" }, true), { tone: "warning", text: "To do", reason: "Locked" }, "required blocked key keeps its reason outside the chip");
    same(logic.itemsKeyed([{ secret: "provider:key", label: "Provider" }, { secret: "", label: "Local" }, { secret: "", label: "Local" }]).map(item => item.key), ["secret provider:key", "label Local", "label Local 2"], "stored key rows keep stable identities");
}

// Mask comments and strings before counting braces, so explanatory text
// cannot change the source check's reach.
function setupBody(source) {
    const masked = source.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/g, text => text.replace(/[^\n]/g, " "));
    const match = /\bColumn\s*\{\s*id:\s*setupPage\b/.exec(masked);
    assert.ok(match, "Setup source check locates the actual Setup body");
    const start = masked.indexOf("{", match.index);
    let depth = 1, end = start + 1;
    for (; depth > 0 && end < masked.length; end++) {
        if (masked[end] === "{") depth++;
        if (masked[end] === "}") depth--;
    }
    assert.equal(depth, 0, "Setup source check reaches the body's closing brace");
    return masked.slice(start + 1, end - 1);
}
function verifyPage(source) { assert.doesNotMatch(setupBody(source), /\bButton\s*\{/, "Setup actions never declare a boxed Button"); }
verify(load(file), load(producerFile));
verifyPage(fs.readFileSync(pageFile, "utf8"));
const controls = [
    ["optional-on-Setup", 'return entry.setup === true;', 'return entry.setup === true || entry.setting !== "";', "optional entries never draw on Setup"],
    ["Details duplicates required step", '!declaresStep(entry) && ', '', "Details lists each former Settings entry"],
    ["blocked required work marked done", 'return entry.report !== "reported" || (entry.tone !== "success" && entry.value.available !== false);', 'return entry.report !== "reported";', "only Home blocked"],
    ["unknown required work marked done", 'return entry.report !== "reported" || (entry.tone !== "success" && entry.value.available !== false);', 'return entry.report === "reported" && entry.tone !== "success";', "Home not reported"],
    ["Not available counts as open", '(entry.tone !== "success" && entry.value.available !== false)', 'entry.tone !== "success"', "readiness: only Home not available"],
    ["Not available sorts with To do", 'var STEP_RANKS = { todo: 0, unavailable: 1, done: 2 };', 'var STEP_RANKS = { todo: 0, unavailable: 0, done: 2 };', "Not available by its value, between To do and Done: the order"],
    ["Not available sorts with Done", 'var STEP_RANKS = { todo: 0, unavailable: 1, done: 2 };', 'var STEP_RANKS = { todo: 0, unavailable: 2, done: 2 };', "Not available by its value, after a pending Tools step: the order"],
    ["Not available reads To do", 'unavailable: { text: "Not available", tone: "neutral" }', 'unavailable: { text: "Not available", tone: "warning" }', "Not available by its value, between To do and Done: the chip"],
    ["a failed build reads To do", 'if (entry.report !== "reported" && plugin !== undefined && plugin.enabled && plugin.failed) return "unavailable";', '', "Not available after a failed build: the chip"],
    ["Setup needed ignores a failed build", 'var plugin = { enabled: enabled, failed: failed === true };', 'var plugin = { enabled: enabled, failed: false };', "Setup needed after a failed build"],
    ["a refusal reads To do", 'return line.startsWith("build failed: ") || line.startsWith("refused: ");', 'return line.startsWith("build failed: ");', "Setup needed refused"],
    ["a tools step offers nothing", 'return requiredLacking(requirements).length > 0 ? reviewButton() : null;', 'return null;', "tools: a missing required tool"],
    ["a tools step offers Review with no required tool lacking", 'return requiredLacking(requirements).length > 0 ? reviewButton() : null;', 'return reviewButton();', "tools: a missing optional tool alone"],
    ["optional tool creates Setup", 'requirements.some(function (row) { return !row.optional; })', 'requirements.length > 0', "optional tools never create Setup"],
    ["optional tool becomes required Tools", 'requirements.filter(function (row) { return !row.optional; })', 'requirements.slice()', "optional tools never create the Tools step"],
    ["ready tools drop Tools", 'if (required.length === 0) return null;', 'if (required.length === 0 || required.every(function (row) { return row.state === "present"; })) return null;', "Tools: present"],
    ["optional tool warns", 'return !row.optional && requirementApplies(row);', 'return requirementApplies(row);', "only optional tool missing"],
    ["disabled plugin warns", 'open: enabled && (', 'open: (', "disabled plugin"],
    ["outdated tool passes", 'return requirement.state !== "present";', 'return requirement.state === "missing";', "outdated required tools stay open"],
    ["pending chip leaks status words", 'view.text = chip.text;', 'view.text = entry.value.text;', "pending chip keeps explanation"],
    ["completed chip stays pending", 'view.text = chip.text;', 'view.text = STEP_CHIPS.todo.text;', "completed chip uses two-state vocabulary"],
    ["open steps follow completed ones", 'return rank(a.entry) - rank(b.entry) || a.index - b.index;', 'return rank(b.entry) - rank(a.entry) || a.index - b.index;', "Home-only blocker is first"],
    ["pending Tools follow completed steps", 'if (!tools.done && firstDone !== -1)', 'if (false)', "pending Tools precede completed required steps"],
    ["keys leave their required step", 'keyList.step === entry.key', 'false', "optional entries never draw on Setup"],
    ["unoffered action is drawn", 'entry.action === null || !entry.action.offered', 'entry.action === null', "after a failed build no step draws an action"],
    ["a primary status action uses a separate screen reply", 'return { kind: "status", key: entry.key', 'return { kind: "tui", key: entry.key', "on: a step whose screen lacks an optional tool offers its own action"],
    ["More settings leaves Settings", 'place === "Settings" ? tui.settings', 'place === "Settings" ? false', "settings screens stay in More settings"],
    ["required keys keep ordinary chips", 'if (setup) {', 'if (false) {', "required stored key uses Done"],
    ["a plugin that is off offers nothing", 'if (!plugin.enabled) return open ? turnOn(plugin.name) : null;', 'if (!plugin.enabled) return null;', "off: every To do step offers Turn on Fixture"],
    ["a screen that is off names no reason", 'reason: plugin.enabled ? "" : offReason(plugin.name)', 'reason: ""', "off: Settings screens take no press and name why"],
    ["a screen takes a press while the plugin is off", 'enabled: plugin.enabled, reason:', 'enabled: true, reason:', "off: Settings screens take no press and name why"],
    ["a Settings field draws a line for each entry with an action", 'lines.push({ slot: "keys " + key, kind: "keys", key: key });\n    });', 'lines.push({ slot: "keys " + key, kind: "keys", key: key });\n    });\n    row.status.forEach(function (entry) { if (entry.action !== null) lines.push({ slot: "own " + entry.key, kind: "keys", key: entry.key }); });', "a Settings field draws its stored key list alone"],
    ["Details drops a fact with an action", 'entry.setting === "" && entry.step === "" && entry.type !== "rows";', 'entry.setting === "" && entry.step === "" && entry.type !== "rows" && entry.action === null;', "Details lists each former Settings entry"],
    ["a Details fact offers no action", 'action: lineAction(stepButton(entry), entry.action !== null, plugin)', 'action: lineAction(null, entry.action !== null, plugin)', "Details: on: a former Settings entry offers its action"],
    ["a Details fact offers no Turn on while the plugin is off", 'action: lineAction(stepButton(entry), entry.action !== null, plugin)', 'action: lineAction(stepButton(entry), false, plugin)', "Details: off: a former Settings entry offers Turn on"],
    ["a Details fact draws its declared action dead", 'action: lineAction(stepButton(entry), entry.action !== null, plugin)', 'action: lineAction(stepButton(entry) || (entry.action === null ? null : { kind: "status", key: "dead", name: "", label: entry.action.label, tone: "", enabled: false, reason: "" }), entry.action !== null, plugin)', "Details: on: a fact whose feature is set up offers nothing"],
    ["optional tools leave Details", 'return requirements.filter(function (entry) { return entry.optional; });', 'return requirements.filter(function (entry) { return entry.optional && entry.name === "automatic-tool"; });', "every optional tool is on Details"],
    ["Details Tools offers no Review", 'return requirements.some(requirementApplies) ? reviewButton() : null;', 'return null;', "Details Tools: a missing optional tool"],
    ["Details Tools offers Review with every optional tool present", 'return requirements.some(requirementApplies) ? reviewButton() : null;', 'return reviewButton();', "Details Tools: a missing required tool alone"],
    ["an unreported step names no wait", 'if (entry.report !== "reported" && plugin.enabled)', 'if (false)', "on, unreported: the step stays To do and names the wait"],
    ["a start error reads as a wait", 'plugin.error !== "" ? plugin.error : ', '', "Not available after a failed build: the step draws the plain line alone"],
    ["a step that could not start keeps the declaration's hint", 'if (entry.report !== "reported" && reading === "unavailable") {', 'if (false) {', "Not available after a failed build: the step draws the plain line alone"],
];
// Each producer control edits PluginLogic, whose rows the page draws.
const producerControls = [
    ["a step whose screen needs an optional tool is withheld", "            action: statusRowAction(entry, value),",
        "            action: statusRowAction(entry, statusEntryActions(entry).some(function (a) { return a.action.tui !== undefined && (manifest.tui[a.action.tui].requires || []).some(function (name) { return manifest.requirements.some(function (r) { return r.optional && r.name === name; }); }); }) ? null : value),",
        "on: a step whose screen lacks an optional tool offers its own action"],
    ["tools on a plugin with no required tool passes", 'return entry.setup === true && manifest.requirements.some(function (row) { return !row.optional; });', 'return entry.setup === true;',
        "judge: tools on a plugin with no required tool"],
    ["tools on a Details fact passes", 'return entry.setup === true && manifest.requirements.some(function (row) { return !row.optional; });', 'return manifest.requirements.some(function (row) { return !row.optional; });',
        "judge: tools on a Details fact"],
    ["Not available on a Details fact passes", 'value.available === false && (entry.setup !== true || ', 'value.available === false && (false || ', "judge: Not available on a Details fact"],
    ["Not available with an action passes", ' || (value.action !== undefined && value.action !== false) || ', ' || ', "judge: Not available with an action"],
    ["Not available with no hint passes", ' || value.aside === true\n            || value.hint === undefined))', ' || value.aside === true))', "judge: Not available with no hint"],
    ["available true passes", '&& (value.available === undefined || value.available === false);', ';', "judge: available true"],
    ["a tools value offers a declared action", '        if (value.action === STATUS_TOOLS_ACTION) return null;\n', '', "act on a tools value: account"],
    ["no info key in a state value", '"available", "info"];', '"available"];', "value info: a value with its own info is admitted"],
    ["a value's info is not judged", '            && infoError(value.info, "") === ""\n', '', "value info: an info empty is refused"],
    ["the entry's info stands over the value's", '        var info = entry.type === "state" && value !== null && value.info !== undefined\n            ? value.info : entry.info', '        var info = false\n            ? value.info : entry.info', "value info: a value's info stands in the entry's"],
    ["no file route", 'var STATUS_ACTION_ROUTES = ["tui", "system", "undo", "dictation", "file"];', 'var STATUS_ACTION_ROUTES = ["tui", "system", "undo", "dictation"];', "file action: a file action is admitted"],
    ["a file act opens a script", '    if (action.file !== undefined)\n        return { ok: true, kind: "file", path: action.file };\n', '', "file action: the act opens the declared path"],
    ["a file path is not judged", '        if (typeof action.file !== "string" || !editArgs(action.file).ok)', '        if (typeof action.file !== "string")', "file action: a path that climbs out is refused at its path"],
    ["a file action beside a script named edit", '        if (isPlainObject(tui) && hasOwn(tui, STATUS_FILE_TUI))', '        if (false)', "file action: a manifest whose script is named edit is refused at its path"]
];
const temp = fs.mkdtempSync(path.join("/tmp", "settings-steps-control-"));
function mustFail(label, run, message) {
    let failed = false;
    try { run(); } catch (error) {
        assert.ok(error instanceof assert.AssertionError, `${label}: control must fail an assertion, not loading or execution: ${error}`);
        assert.ok(error.message.includes(message), `${label}: its named rule must reject the defect: ${error.message}`);
        failed = true;
    }
    assert.ok(failed, `${label}: the planted defect passed`);
}
function mutant(source, label, needle, replacement, name) {
    assert.equal(source.split(needle).length, 2, `${label}: source mutation must match once`);
    const copy = path.join(temp, name);
    fs.writeFileSync(copy, source.replace(needle, () => replacement));
    return copy;
}
try {
    const source = fs.readFileSync(file, "utf8"), producerSource = fs.readFileSync(producerFile, "utf8");
    for (const [label, needle, replacement, failure] of controls)
        mustFail(label, () => verify(load(mutant(source, label, needle, replacement, "Steps.js")), load(producerFile)), failure);
    // The producer's copy imports its neighbours by relative path, so it
    // stands in a tree of links to theirs.
    const core = path.join(temp, "shell", "Core");
    fs.mkdirSync(core, { recursive: true });
    for (const dir of ["Commons", "Ui"]) fs.symlinkSync(path.join(root, "shell", dir), path.join(temp, "shell", dir));
    for (const name of fs.readdirSync(path.join(root, "shell", "Core")).filter(name => name.endsWith(".js") && name !== "PluginLogic.js"))
        fs.symlinkSync(path.join(root, "shell", "Core", name), path.join(core, name));
    for (const [label, needle, replacement, failure] of producerControls)
        mustFail(label, () => verify(load(file), load(mutant(producerSource, label, needle, replacement, path.join("shell", "Core", "PluginLogic.js")))), failure);
    const page = fs.readFileSync(pageFile, "utf8"), needle = "id: setupPage";
    assert.equal(page.split(needle).length, 2, "boxed-action-on-Setup: production body must match once");
    const pageMutant = path.join(temp, "PluginPage.qml");
    fs.writeFileSync(pageMutant, page.replace(needle, needle + '\n Button { text: "Set up" }'));
    mustFail("boxed-action-on-Setup", () => verifyPage(fs.readFileSync(pageMutant, "utf8")), "Setup actions never declare a boxed Button");
} finally { fs.rmSync(temp, { recursive: true, force: true }); }
console.log(`test-settings-steps: ok controls=${controls.length + producerControls.length + 1}`);
