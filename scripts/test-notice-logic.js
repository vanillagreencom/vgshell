#!/usr/bin/env node
// Table-driven checks for the requirement notice's decisions in
// shell/Core/PluginLogic.js: what each trigger asks for, whose notice the
// doctor capability may ask for, how the queue
// merges, rests and fills, which notices a scan keeps, what the shown
// notice lists and installs, and
// how a detection's answer is read, and what the consent slot draws: the
// first-start welcome, its key rows and when it is seen. The file loads under node through
// bin/lib/qml-library.js, as the shell loads it. The controls at the end
// edit a copy of the judge, one rule at a time, and the suite must fail on
// every copy. Exit 1 when a row or a control fails.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const { load } = require("../bin/lib/qml-library.js");

const CORE = path.join(__dirname, "..", "shell", "Core");
const LOGIC = path.join(CORE, "PluginLogic.js");
const IMPORTS = [
    [path.join(__dirname, "..", "shell", "Ui", "icons", "Lucide.js"), path.join("shell", "Ui", "icons", "Lucide.js")],
    [path.join(__dirname, "..", "shell", "Ui", "icons", "Own.js"), path.join("shell", "Ui", "icons", "Own.js")],
    [path.join(CORE, "ConfigLogic.js"), path.join("shell", "Core", "ConfigLogic.js")],
    [path.join(CORE, "PackageManagers.js"), path.join("shell", "Core", "PackageManagers.js")],
    [path.join(CORE, "HyprlandLayer.js"), path.join("shell", "Core", "HyprlandLayer.js")],
    [path.join(CORE, "MonitorLogic.js"), path.join("shell", "Core", "MonitorLogic.js")],
    [path.join(CORE, "Pads.js"), path.join("shell", "Core", "Pads.js")],
    [path.join(__dirname, "..", "shell", "Commons", "SettingValues.js"), path.join("shell", "Commons", "SettingValues.js")],
    [path.join(__dirname, "..", "shell", "Commons", "PageReference.js"), path.join("shell", "Commons", "PageReference.js")],
];

let failures = 0;
function report(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { console.log("  ok    " + name); return; }
    failures += 1;
    console.log("  FAIL  " + name + "\n        got  " + g + "\n        want " + w);
}

const PACMAN = { id: "pacman", binary: "pacman" };
const PARU = { id: "aur", binary: "paru" };
const NIX = { id: "nix", binary: "nix" };
const ARCH = { primary: PACMAN, overlays: [PARU], sources: [] };

// Every row against one loaded judge, `ctx`, each result handed to `check`.
function suite(ctx, check) {
    const needs = ctx.validateManifest({
        schemaVersion: 1, id: "acme.needs", name: "Needs", version: "1", author: "a", description: "d",
        kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["requirements"],
        requirements: [
            { command: "vgs-one", packages: { pacman: "one" }, purpose: "First" },
            { command: "vgs-two", packages: { aur: "two-git" }, optional: true, purpose: "Second" },
            { command: "vgs-bare", optional: true, purpose: "No package" },
            { command: "sh", packages: { pacman: "bash" }, purpose: "Present" },
            { command: "vgs-nix", packages: { nix: "nix-one" }, purpose: "Nix" },
        ],
    }, "/p").manifest;
    const allMissing = ["vgs-one", "vgs-two", "vgs-bare", "vgs-nix"];

    // noticeRequest: [name, missing, trigger, commands, want as
    // [answer, commands, required]].
    const requestRows = [
        ["installed lists every missing command and requires the needed ones", allMissing, "installed", undefined, ["ok", ["vgs-one", "vgs-two", "vgs-bare", "vgs-nix"], ["vgs-one", "vgs-nix"]]],
        ["enabled asks as installed does", allMissing, "enabled", undefined, ["ok", ["vgs-one", "vgs-two", "vgs-bare", "vgs-nix"], ["vgs-one", "vgs-nix"]]],
        ["only optional commands missing raise no notice", ["vgs-two", "vgs-bare"], "enabled", undefined, ["satisfied", ["vgs-two", "vgs-bare"], []]],
        ["nothing missing raises no notice", [], "installed", undefined, ["satisfied", [], []]],
        ["a request lists and requires every missing command, optional ones too", allMissing, "requested", undefined, ["ok", ["vgs-one", "vgs-two", "vgs-bare", "vgs-nix"], ["vgs-one", "vgs-two", "vgs-bare", "vgs-nix"]]],
        ["a request with only optional commands missing raises the notice", ["vgs-two", "vgs-bare"], "requested", undefined, ["ok", ["vgs-two", "vgs-bare"], ["vgs-two", "vgs-bare"]]],
        ["a request with nothing missing is satisfied", [], "requested", undefined, ["satisfied", [], []]],
        ["an offer lists and requires its missing commands, optional ones too", allMissing, "offered", ["vgs-two", "vgs-one"], ["ok", ["vgs-one", "vgs-two"], ["vgs-one", "vgs-two"]]],
        ["an offer of present commands is satisfied", allMissing, "offered", ["sh"], ["satisfied", [], []]],
        ["an offer of a command it did not declare", allMissing, "offered", ["vgs-one", "pacman"], ["refused: requirement=pacman reason=undeclared", [], []]],
        ["an undeclared command is named even when unprintable", allMissing, "offered", ["a b"], ["refused: requirement=\"a b\" reason=undeclared", [], []]],
        ["an offer that is not a list", allMissing, "offered", "vgs-one", ["refused: requirements=malformed", [], []]],
        ["an empty offer", allMissing, "offered", [], ["refused: requirements=malformed", [], []]],
        ["an offer holding a number", allMissing, "offered", ["vgs-one", 7], ["refused: requirements=malformed", [], []]],
        ["an offer of seventeen commands", allMissing, "offered", Array(17).fill("vgs-one"), ["refused: requirements=malformed", [], []]],
        ["an offer of sixteen commands", allMissing, "offered", Array(16).fill("vgs-one"), ["ok", ["vgs-one"], ["vgs-one"]]],
        ["a suggestion lists and requires its missing commands, optional ones too", allMissing, "suggested", ["vgs-two", "vgs-one"], ["ok", ["vgs-one", "vgs-two"], ["vgs-one", "vgs-two"]]],
        ["a suggestion that is not a list", allMissing, "suggested", "vgs-one", ["refused: requirements=malformed", [], []]],
        ["a choice lists and requires its missing commands, optional ones too", allMissing, "chosen", ["vgs-bare"], ["ok", ["vgs-bare"], ["vgs-bare"]]],
        ["a choice of a command the owner did not declare", allMissing, "chosen", ["pacman"], ["refused: requirement=pacman reason=undeclared", [], []]],
        ["a choice that is not a list", allMissing, "chosen", "vgs-one", ["refused: requirements=malformed", [], []]],
    ];
    for (const [name, missing, trigger, commands, want] of requestRows) {
        const r = ctx.noticeRequest(needs, missing, {}, trigger, commands);
        check("noticeRequest: " + name, [r.answer, r.commands, r.required], want);
    }
    check("noticeRequest throws on a trigger no rule covers", (() => { try { ctx.noticeRequest(needs, [], {}, "asked", undefined); return "answered"; } catch (e) { return e.message; } })(), "notices: trigger \"asked\" is not one of installed, enabled, offered, suggested, requested, chosen");

    // The triggers over a command below its floor: [name, missing, trigger,
    // commands, want]. vgs-old reads 1.9.0 under the floor 2.0.0.
    const floored = ctx.validateManifest({
        schemaVersion: 1, id: "acme.floor", name: "Floor", version: "1", author: "a", description: "d",
        kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["requirements"],
        requirements: [
            { command: "vgs-far", packages: { aur: "far-git" }, floor: "1.2.0", purpose: "Far" },
            { command: "vgs-old", packages: { pacman: "old", mise: "npm:vgs-old" }, floor: "2.0.0", purpose: "Old" },
            { command: "vgs-one", packages: { pacman: "one" }, purpose: "First" },
        ],
    }, "/p").manifest;
    const below = { "vgs-old": "vgs-old 1.9.0", "vgs-far": "1.2.0" };
    const outdatedRows = [
        ["enabling a plugin whose only lack is an outdated command raises no notice", [], "enabled", undefined, ["satisfied", [], []]],
        ["installing one raises none either", [], "installed", undefined, ["satisfied", [], []]],
        ["enabled lists a missing command beside an outdated one, and not the outdated one", ["vgs-one"], "enabled", undefined, ["ok", ["vgs-one"], ["vgs-one"]]],
        ["a request lists and requires the outdated command", [], "requested", undefined, ["ok", ["vgs-old"], ["vgs-old"]]],
        ["an offer lists and requires the outdated command", [], "offered", ["vgs-old", "vgs-far"], ["ok", ["vgs-old"], ["vgs-old"]]],
        ["a choice lists and requires the outdated command", [], "chosen", ["vgs-old"], ["ok", ["vgs-old"], ["vgs-old"]]],
    ];
    for (const [name, missing, trigger, commands, want] of outdatedRows) {
        const r = ctx.noticeRequest(floored, missing, below, trigger, commands);
        check("noticeRequest: " + name, [r.answer, r.commands, r.required], want);
    }

    // noticeUnchanged: [name, missing, versions, the press that ran as its
    // manager, installs and updates, want]. Each package of the press is
    // judged alone and named by its package, not its command. The notice
    // lists all three commands; on ARCH pacman provides vgs-old as old and
    // vgs-one as one, and paru provides vgs-far as far-git, which the
    // manifest declares first.
    const three = { commands: ["vgs-old", "vgs-one", "vgs-far"], required: ["vgs-old", "vgs-one", "vgs-far"] };
    const farBelow = { "vgs-old": "2.0.0", "vgs-far": "far 1.1.9 (linux)" };
    const atFloor = { "vgs-old": "2.0.0", "vgs-far": "1.2.0" };
    const oldLeft = { kind: "outdated", name: "old", version: "1.9.0", floor: "2.0.0" };
    const oneLeft = { kind: "missing", name: "one", optional: false };
    const unchanged = (...left) => ({ kind: "unchanged", left });
    const unchangedRows = [
        ["an update that left the version it read is named with that version and the floor", [], below, "pacman", [], ["old"], unchanged(oldLeft)],
        ["the primary's update is named by its own package, behind an overlay's declared first", [], { "vgs-old": "1.9.0", "vgs-far": "1.1.9" }, "pacman", [], ["old"], unchanged(oldLeft)],
        ["an update that reached the floor left nothing", [], atFloor, "pacman", [], ["old"], null],
        ["an update that reached the floor left nothing, with the next manager's still owed", [], farBelow, "pacman", [], ["old"], null],
        ["an overlay's update that left its version is named by its own package", [], farBelow, "aur", [], ["far-git"], unchanged({ kind: "outdated", name: "far-git", version: "1.1.9", floor: "1.2.0" })],
        ["an install that left its command missing is named by its package", ["vgs-one"], atFloor, "pacman", ["one"], [], unchanged(oneLeft)],
        ["an install that found its command left nothing, with an update it did not run still owed", [], below, "pacman", ["one"], [], null],
        ["a package the press updated is not named for a command that went missing", ["vgs-old"], atFloor, "pacman", [], ["old"], null],
        ["a package the press installed below its floor changed, and is not named", [], below, "pacman", ["old"], [], null],
        ["a press of both that changed nothing names both packages, in declaration order", ["vgs-one"], below, "pacman", ["one"], ["old"], unchanged(oldLeft, oneLeft)],
        ["a press of both that installed and left its update names the outdated package alone", [], below, "pacman", ["one"], ["old"], unchanged(oldLeft)],
        ["a press of both that updated and left its install names the missing package alone", ["vgs-one"], atFloor, "pacman", ["one"], ["old"], unchanged(oneLeft)],
        ["a press of both that did both left nothing", [], atFloor, "pacman", ["one"], ["old"], null],
    ];
    for (const [name, missing, versions, manager, installs, updates, want] of unchangedRows)
        check("noticeUnchanged: " + name, ctx.noticeUnchanged(floored, missing, versions, three, ARCH, { manager, installs, updates }), want);
    check("noticeUnchanged: no answer from detection names nothing", ctx.noticeUnchanged(floored, [], below, three, null, { manager: "pacman", installs: [], updates: ["old"] }), null);
    // A manifest that declares its missing requirement before its outdated
    // one: the answer follows the requirement's state, not the press's action.
    const missingFirst = ctx.validateManifest({
        schemaVersion: 1, id: "acme.first", name: "First", version: "1", author: "a", description: "d",
        kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["requirements"],
        requirements: [
            { command: "vgs-one", packages: { pacman: "one" }, purpose: "First" },
            { command: "vgs-old", packages: { pacman: "old" }, floor: "2.0.0", purpose: "Old" },
        ],
    }, "/p").manifest;
    const firstNotice = { commands: ["vgs-one", "vgs-old"], required: ["vgs-one", "vgs-old"] };
    const firstRun = ctx.noticeView(missingFirst, ["vgs-one"], below, firstNotice, ARCH).run;
    check("noticeUnchanged: a press of both that changed nothing names a missing package declared first before the outdated one", [firstRun.action, ctx.noticeUnchanged(missingFirst, ["vgs-one"], below, firstNotice, ARCH, firstRun)], ["update", unchanged(oneLeft, oldLeft)]);
    // Two commands of one package, both below their floors, and a command
    // vgs-vox whose package is vox-bin: an update that changed nothing
    // names the package once, with its first requirement's version and floor.
    const vox = ctx.validateManifest({
        schemaVersion: 1, id: "acme.vox", name: "Vox", version: "1", author: "a", description: "d",
        kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["requirements"],
        requirements: [
            { command: "vgs-vox", packages: { aur: "vox-bin" }, floor: "2.0.0", purpose: "Voice" },
            { command: "vgs-voxctl", packages: { aur: "vox-bin" }, floor: "3.0.0", purpose: "Control" },
        ],
    }, "/p").manifest;
    const voxNotice = { commands: ["vgs-vox", "vgs-voxctl"], required: ["vgs-vox", "vgs-voxctl"] };
    const voxBelow = { "vgs-vox": "1.0.0", "vgs-voxctl": "1.5.0" };
    const voxRun = ctx.noticeView(vox, [], voxBelow, voxNotice, ARCH).run;
    check("noticeUnchanged: two commands of one package left outdated name the package once", [voxRun.args, ctx.noticeUnchanged(vox, [], voxBelow, voxNotice, ARCH, voxRun)], [["--manager", "aur", "vox-bin"], unchanged({ kind: "outdated", name: "vox-bin", version: "1.0.0", floor: "2.0.0" })]);
    const HELD_MISE = { primary: PACMAN, overlays: [PARU], sources: [{ id: "mise", binary: "mise" }], holders: { "vgs-old": { path: "/home/method/.local/bin/vgs-old", owners: { pacman: null, mise: "npm:vgs-old" } } } };
    const heldView = ctx.noticeView(floored, [], below, { id: "acme.floor", commands: ["vgs-old"], required: ["vgs-old"] }, HELD_MISE);
    check("noticeView: an outdated command held by the second manager updates through that manager", [heldView.rows.map(r => r.name + " (" + r.package.manager + "/" + r.package.name + "): " + r.purpose), heldView.run.action, heldView.run.args], [["vgs-old (mise/npm:vgs-old): Old"], "update", ["--manager", "mise", "npm:vgs-old"]]);

    // noticeView's press: [name, missing, versions, want as [action, args,
    // installs, updates], the entries listed as chip and update, the later
    // entries as manager and chip]. One press runs one manager's packages,
    // the missing and the outdated.
    const pressRows = [
        ["a missing and an outdated package of one manager are one press that names both", ["vgs-one"], below,
            ["update", ["old", "--install", "one"], ["one"], ["old"]], [["old", true], ["one", false]], []],
        ["a second manager's package waits for a later press", ["vgs-one"], { "vgs-old": "1.9.0", "vgs-far": "1.1.9" },
            ["update", ["old", "--install", "one"], ["one"], ["old"]], [["old", true], ["one", false]], [["aur", "far-git"]]],
        ["a manager with an update is pressed before the primary's install", ["vgs-one"], farBelow,
            ["update", ["--manager", "aur", "far-git"], [], ["far-git"]], [["far-git", true]], [["pacman", "one"]]],
        ["missing packages alone are an install", ["vgs-one"], { "vgs-old": "2.0.0", "vgs-far": "1.2.0" },
            ["install", ["one"], ["one"], []], [["one", false]], []],
        ["outdated packages alone are an update with no install", [], below,
            ["update", ["old"], [], ["old"]], [["old", true]], []],
    ];
    // The entries a view draws for its own step, and those it draws for
    // later presses as manager and chip.
    const stepOf = v => v.drawn.filter(e => !e.later);
    const laterOf = v => v.drawn.filter(e => e.later).map(e => [e.manager, e.chip]);
    // One name under two managers is two packages: the AUR one, outdated,
    // gives the primary's missing one no update.
    const twins = ctx.validateManifest({
        schemaVersion: 1, id: "acme.twins", name: "Twins", version: "1", author: "a", description: "d",
        kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["requirements"],
        requirements: [
            { command: "vgs-here", packages: { pacman: "twin" }, purpose: "Here" },
            { command: "vgs-there", packages: { aur: "twin" }, floor: "2.0.0", purpose: "There" },
        ],
    }, "/p").manifest;
    const twinView = ctx.noticeView(twins, ["vgs-here"], { "vgs-there": "1.0.0" }, { commands: ["vgs-here", "vgs-there"], required: ["vgs-here"] }, ARCH);
    check("noticeView press: a package is updated only through its own manager", [twinView.run.action, twinView.run.args, stepOf(twinView).map(g => [g.manager, g.chip, g.update]), laterOf(twinView)], ["update", ["--manager", "aur", "twin"], [["aur", "twin", true]], [["pacman", "twin"]]]);
    check("noticeUnchanged: a package of another manager with the name the press installed is not named", ctx.noticeUnchanged(twins, ["vgs-there"], {}, { commands: ["vgs-here", "vgs-there"], required: ["vgs-here"] }, ARCH, { manager: "pacman", installs: ["twin"], updates: [] }), null);
    for (const [name, missing, versions, run, groups, later] of pressRows) {
        const v = ctx.noticeView(floored, missing, versions, three, ARCH);
        check("noticeView press: " + name, [[v.run.action, v.run.args, v.run.installs, v.run.updates], stepOf(v).map(g => [g.chip, g.update]), laterOf(v)], [run, groups, later]);
    }
    // Three required packages, one for each manager that installs here
    // (VGS-1490), declared in another order than the presses take them:
    // the press installs the primary's, and the view names the other two,
    // each with its manager, in the order the next presses offer them.
    const MISE_TOO = { primary: PACMAN, overlays: [PARU], sources: [{ id: "mise", binary: "mise" }] };
    const world = ctx.validateManifest({
        schemaVersion: 1, id: "acme.world", name: "World", version: "1", author: "a", description: "d",
        kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["requirements"],
        requirements: [
            { command: "pi", packages: { mise: "npm:pi" }, purpose: "Agent" },
            { command: "agent-browser", packages: { aur: "agent-browser-bin" }, purpose: "Browser" },
            { command: "gum", packages: { pacman: "gum" }, purpose: "Dialogs" },
        ],
    }, "/p").manifest;
    const worldNames = ["pi", "agent-browser", "gum"];
    const worldView = ctx.noticeView(world, worldNames, {}, { commands: worldNames, required: worldNames }, MISE_TOO);
    check("noticeView press: a notice of three managers names every package with its manager across its step and the later ones, in press order",
        [worldView.run.args, stepOf(worldView).map(e => [e.manager, e.chip]), laterOf(worldView), worldView.drawn.filter(e => e.later).map(e => [e.packaged, e.update, e.purposes])],
        [["gum"], [["pacman", "gum"]], [["aur", "agent-browser-bin"], ["mise", "npm:pi"]], [[true, false, ["Browser"]], [true, false, ["Agent"]]]]);
    // A required package for each of two managers and an optional one of a
    // third that the presses reach after them: the notice closes once the
    // second press finds its package, so the optional one is not offered.
    const reach = ctx.validateManifest({
        schemaVersion: 1, id: "acme.reach", name: "Reach", version: "1", author: "a", description: "d",
        kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["requirements"],
        requirements: [
            { command: "gum", packages: { pacman: "gum" }, purpose: "Dialogs" },
            { command: "pi", packages: { mise: "npm:pi" }, optional: true, purpose: "Agent" },
            { command: "agent-browser", packages: { aur: "agent-browser-bin" }, purpose: "Browser" },
        ],
    }, "/p").manifest;
    const reachView = ctx.noticeView(reach, ["gum", "pi", "agent-browser"], {}, { commands: ["gum", "pi", "agent-browser"], required: ["gum", "agent-browser"] }, MISE_TOO);
    check("noticeView press: later stops at the last manager that holds a required package",
        [reachView.run.args, laterOf(reachView)], [["gum"], [["aur", "agent-browser-bin"]]]);
    // noticeTitle: [name, view, want as the verb, the count and the noun
    // the title reads]. The count is the number of entries the view draws
    // whose chip reads Missing or Outdated, its later ones included, so an
    // outdated optional entry counts and a missing optional one does not; a
    // view of missing optional entries alone counts them all under "can
    // use".
    const titleReads = t => { const m = / (needs|can use) (one|\d+) (update|package|requirement)s?$/.exec(t); return m === null ? t : [m[1], m[2] === "one" ? 1 : Number(m[2]), m[3]]; };
    const optionalView = ctx.noticeView(needs, ["vgs-two"], {}, { id: "acme.needs", commands: ["vgs-two"], required: ["vgs-two"] }, ARCH);
    const mixed = ctx.validateManifest({
        schemaVersion: 1, id: "acme.mixed", name: "Mixed", version: "1", author: "a", description: "d",
        kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["requirements"],
        requirements: [
            { command: "vgs-old", packages: { pacman: "old" }, floor: "2.0.0", purpose: "Old" },
            { command: "vgs-pi", packages: { pacman: "pi" }, floor: "1.1.0", optional: true, purpose: "Pi" },
            { command: "vgs-vox", packages: { pacman: "vox" }, optional: true, purpose: "Vox" },
        ],
    }, "/p").manifest;
    const mixedNames = ["vgs-old", "vgs-pi", "vgs-vox"];
    const mixedView = ctx.noticeView(mixed, ["vgs-vox"], { "vgs-old": "1.9.0", "vgs-pi": "1.0.2" }, { id: "acme.mixed", commands: mixedNames, required: mixedNames }, ARCH);
    const titleRows = [
        ["a notice with later entries counts them beside its step's", worldView, ["needs", 3, "package"]],
        ["a notice without later entries counts its step's", ctx.noticeView(floored, ["vgs-one"], below, three, ARCH), ["needs", 2, "package"]],
        ["a notice of updates alone counts updates", ctx.noticeView(floored, [], below, three, ARCH), ["needs", 1, "update"]],
        ["a notice with no package counts requirements, its optional ones left out", ctx.noticeView(needs, allMissing, {}, { id: "acme.needs", commands: allMissing, required: ["vgs-one"] }, null), ["needs", 2, "requirement"]],
        ["a notice of a required package and an optional one counts the required one", ctx.noticeView(needs, ["vgs-one", "vgs-two"], {}, { id: "acme.needs", commands: ["vgs-one", "vgs-two"], required: ["vgs-one", "vgs-two"] }, ARCH), ["needs", 1, "package"]],
        ["a notice of an optional package alone needs nothing", optionalView, ["can use", 1, "package"]],
        ["a notice counts an outdated optional package, drawn Outdated, and leaves out a missing optional one", mixedView, ["needs", 2, "update"]],
    ];
    for (const [name, view, want] of titleRows) {
        const read = titleReads(ctx.noticeTitle("Owner", view));
        const needed = view.drawn.filter(e => e.update || !e.optional).length;
        check("noticeTitle: " + name, read, want);
        check("noticeTitle counts the entries the view draws as needed: " + name, read[1], needed === 0 ? view.drawn.length : needed);
    }
    check("control: the optional-only notice draws its optional entry", optionalView.drawn.map(e => [e.chip, e.optional]), [["two-git", true]]);
    check("control: the mixed notice draws an outdated optional entry and a missing optional one", mixedView.drawn.map(e => [e.chip, e.update, e.optional]), [["old", true, false], ["pi", true, true], ["vox", false, true]]);
    // Each chip's state reads in the tone its Requirements row draws
    // (requirementBadge): a missing required tool Missing in the danger
    // tone, a missing optional one Optional in the info tone, and an
    // outdated one Outdated in the warning tone, optional or not.
    const badgeOf = e => [e.chip === undefined ? e.name : e.chip, e.badge.text, e.badge.tone];
    check("requirementRows: each row's badge reads its state in its tone", ctx.requirementRows(needs, ["vgs-one", "vgs-two"], {}).map(badgeOf),
        [["vgs-one", "Missing", "danger"], ["vgs-two", "Optional", "info"], ["vgs-bare", "Present", "success"], ["sh", "Present", "success"], ["vgs-nix", "Present", "success"]]);
    check("noticeView: a missing required package's chip reads Missing in the danger tone, a missing optional one Optional in the info tone",
        ctx.noticeView(needs, ["vgs-one", "vgs-two"], {}, { id: "acme.needs", commands: ["vgs-one", "vgs-two"], required: ["vgs-one", "vgs-two"] }, ARCH).drawn.map(badgeOf),
        [["one", "Missing", "danger"], ["two-git", "Optional", "info"]]);
    check("noticeView: an outdated package's chip reads Outdated in the warning tone, optional or not", mixedView.drawn.map(badgeOf),
        [["old", "Outdated", "warning"], ["pi", "Outdated", "warning"], ["vox", "Optional", "info"]]);
    // noticeUnchanged names an optional package the install left missing
    // as optional, so the notice says so rather than reporting a failure.
    check("noticeUnchanged: an install that left an optional package missing names it optional",
        ctx.noticeUnchanged(needs, ["vgs-two"], {}, { id: "acme.needs", commands: ["vgs-two"], required: ["vgs-two"] }, ARCH, { manager: "aur", installs: ["two-git"], updates: [] }),
        unchanged({ kind: "missing", name: "two-git", optional: true }));

    // The core's owner: the core's list, drawn under the name VGS, asked
    // for as a plugin's manifest is.
    const core = ctx.coreOwner([{ name: "gum", bus: null, packages: { pacman: "gum" }, optional: true, purpose: "Dialogs" }, { name: "git", bus: null, packages: { pacman: "git" }, optional: false, purpose: "Plugins" }]);
    check("the core's owner is named core and drawn as VGS", [core.id, core.name, ctx.CORE_OWNER], ["core", "VGS", "core"]);
    const coreRequest = ctx.noticeRequest(core, ["gum"], {}, "chosen", ["gum", "git"]);
    check("noticeRequest: a choice of the core's commands lists its missing ones", [coreRequest.answer, coreRequest.commands, coreRequest.required], ["ok", ["gum"], ["gum"]]);

    // noticeOwnerError: [name, owner, want]. acme.needs is enabled,
    // acme.off known and disabled.
    const owners = { core: core, "acme.needs": needs, "acme.off": Object.assign({}, needs, { id: "acme.off" }) };
    const ownerRows = [
        ["the core is always an owner", "core", ""],
        ["an enabled plugin is an owner", "acme.needs", ""],
        ["a disabled plugin is refused", "acme.off", "refused: owner=acme.off reason=disabled"],
        ["an unknown owner is refused", "acme.gone", "refused: owner=acme.gone reason=unknown"],
        ["an unprintable owner is named quoted", "a b", "refused: owner=\"a b\" reason=unknown"],
        ["an owner that is no string is malformed", 7, "refused: owner=malformed"],
        ["an inherited name is no owner", "toString", "refused: owner=toString reason=unknown"],
    ];
    for (const [name, owner, want] of ownerRows)
        check("noticeOwnerError: " + name, ctx.noticeOwnerError(owner, owners, ["acme.needs"]), want);

    // noticeAdmit: [name, queue, rest, id, request commands and required,
    // trigger, want as [answer, queue as id: commands / required]].
    const n = (id, commands, required) => ({ id, commands, required });
    const shown = q => q.map(e => e.id + ": " + e.commands.join(",") + " / " + e.required.join(","));
    const full = Array.from({ length: 8 }, (_, i) => n("acme.p" + i, ["c"], ["c"]));
    const admitRows = [
        ["a first notice joins the queue", [], {}, "acme.needs", n("", ["a", "b"], ["a"]), "installed", ["ok", ["acme.needs: a,b / a"]]],
        ["a second plugin waits behind the first", [n("acme.x", ["x"], ["x"])], {}, "acme.needs", n("", ["a"], ["a"]), "enabled", ["ok", ["acme.x: x / x", "acme.needs: a / a"]]],
        ["a plugin holding a notice gets the new commands merged", [n("acme.x", ["x"], ["x"]), n("acme.needs", ["a"], ["a"])], {}, "acme.needs", n("", ["b", "a"], ["b"]), "offered", ["ok", ["acme.x: x / x", "acme.needs: a,b / a,b"]]],
        ["a resting plugin's suggestion is refused", [], { "acme.needs": 1500 }, "acme.needs", n("", ["a"], ["a"]), "suggested", ["refused: requirements=acme.needs reason=resting retry-ms=500", []]],
        ["a rest that ended refuses nothing", [], { "acme.needs": 1000 }, "acme.needs", n("", ["a"], ["a"]), "suggested", ["ok", ["acme.needs: a / a"]]],
        ["an offer, a user's press, is never refused for a rest", [], { "acme.needs": 1500 }, "acme.needs", n("", ["a"], ["a"]), "offered", ["ok", ["acme.needs: a / a"]]],
        ["an install is never refused for a rest", [], { "acme.needs": 1500 }, "acme.needs", n("", ["a"], ["a"]), "installed", ["ok", ["acme.needs: a / a"]]],
        ["an enable is never refused for a rest", [], { "acme.needs": 1500 }, "acme.needs", n("", ["a"], ["a"]), "enabled", ["ok", ["acme.needs: a / a"]]],
        ["a request is never refused for a rest", [], { "acme.needs": 1500 }, "acme.needs", n("", ["a"], ["a"]), "requested", ["ok", ["acme.needs: a / a"]]],
        ["a choice is never refused for a rest", [], { "acme.needs": 1500 }, "acme.needs", n("", ["a"], ["a"]), "chosen", ["ok", ["acme.needs: a / a"]]],
        ["another plugin's rest refuses nothing", [], { "acme.other": 1500 }, "acme.needs", n("", ["a"], ["a"]), "suggested", ["ok", ["acme.needs: a / a"]]],
        ["a resting plugin's suggestion merges into its held notice", [n("acme.needs", ["a"], ["a"])], { "acme.needs": 1500 }, "acme.needs", n("", ["b"], ["b"]), "suggested", ["ok", ["acme.needs: a,b / a,b"]]],
        ["a full queue refuses a ninth plugin", full, {}, "acme.needs", n("", ["a"], ["a"]), "installed", ["refused: notices=full limit=8", shown(full)]],
        ["a full queue still merges a held plugin", full, {}, "acme.p3", n("", ["d"], ["d"]), "installed", ["ok", shown(full).map(line => line.startsWith("acme.p3:") ? "acme.p3: c,d / c,d" : line)]],
    ];
    for (const [name, queue, rest, id, request, trigger, want] of admitRows) {
        const before = JSON.stringify(queue);
        const r = ctx.noticeAdmit(queue, rest, id, request, trigger, 1000);
        check("noticeAdmit: " + name, [r.answer, shown(r.queue)], want);
        check("noticeAdmit leaves the queue it was handed alone: " + name, JSON.stringify(queue), before);
    }
    check("noticeAdmit throws on a trigger no rule covers", (() => { try { ctx.noticeAdmit([], {}, "acme.needs", n("", ["a"], ["a"]), "asked", 0); return "answered"; } catch (e) { return e.message; } })(), "notices: trigger \"asked\" is not one of installed, enabled, offered, suggested, requested, chosen");
    check("the queue holds eight plugins and an offer names sixteen commands", [ctx.NOTICE_QUEUE_MAX, ctx.NOTICE_OFFER_MAX], [8, 16]);
    check("a plugin's offers rest ten minutes after Not now", ctx.NOTICE_OFFER_REST_MS, 600000);

    // noticeView: [name, missing, notice, found, want as
    // [satisfied, rows as command (manager/name) optional, the press as
    // [action, args], byHand, the later entries as manager and chip]].
    const all = n("acme.needs", ["vgs-one", "vgs-two", "vgs-bare", "vgs-nix"], ["vgs-one", "vgs-nix"]);
    const rowText = r => r.name + (r.package === null ? "" : " (" + r.package.manager + "/" + r.package.name + ")") + (r.optional ? " optional" : "") + ": " + r.purpose;
    const viewRows = [
        ["the primary's group installs first", allMissing, all, ARCH,
            [false, ["vgs-one (pacman/one): First", "vgs-two (aur/two-git) optional: Second", "vgs-bare optional: No package", "vgs-nix: Nix"], ["install", ["one"]], [], [["aur", "two-git"]]]],
        ["the overlay's group installs once the primary's is done", ["vgs-two", "vgs-nix"], all, ARCH,
            [false, ["vgs-two (aur/two-git) optional: Second", "vgs-nix: Nix"], ["install", ["--manager", "aur", "two-git"]], [], []]],
        ["nix's packages are named for its configuration, with no install", allMissing, all, { primary: NIX, overlays: [], sources: [] },
            [false, ["vgs-one: First", "vgs-two optional: Second", "vgs-bare optional: No package", "vgs-nix (nix/nix-one): Nix"], null, [{ manager: "nix", names: ["nix-one"] }], []]],
        ["no answer from detection lists commands without packages", allMissing, all, null,
            [false, ["vgs-one: First", "vgs-two optional: Second", "vgs-bare optional: No package", "vgs-nix: Nix"], null, [], []]],
        ["the notice is satisfied once no required command is missing", ["vgs-two", "vgs-bare"], all, ARCH,
            [true, ["vgs-two (aur/two-git) optional: Second", "vgs-bare optional: No package"], ["install", ["--manager", "aur", "two-git"]], [], []]],
        ["packages only optional requirements wait for are not offered later, since the notice closes first", allMissing, n("acme.needs", ["vgs-one", "vgs-two", "vgs-bare"], ["vgs-one"]), ARCH,
            [false, ["vgs-one (pacman/one): First", "vgs-two (aur/two-git) optional: Second", "vgs-bare optional: No package"], ["install", ["one"]], [], []]],
        ["a required package of a second manager is offered for a later press, and one no manager provides is not", allMissing, n("acme.needs", ["vgs-one", "vgs-two", "vgs-bare"], ["vgs-one", "vgs-two"]), ARCH,
            [false, ["vgs-one (pacman/one): First", "vgs-two (aur/two-git) optional: Second", "vgs-bare optional: No package"], ["install", ["one"]], [], [["aur", "two-git"]]]],
        ["a command the notice does not list is not drawn", ["vgs-one", "vgs-two"], n("acme.needs", ["vgs-two"], ["vgs-two"]), ARCH,
            [false, ["vgs-two (aur/two-git) optional: Second"], ["install", ["--manager", "aur", "two-git"]], [], []]],
    ];
    for (const [name, missing, notice, found, want] of viewRows) {
        const v = ctx.noticeView(needs, missing, {}, notice, found);
        check("noticeView: " + name, [v.satisfied, v.rows.map(rowText), v.run === null ? null : [v.run.action, v.run.args], v.byHand, laterOf(v)], want);
        check("noticeView lists every entry while no press runs, and offers none for later: " + name, v.run !== null || stepOf(v).length === v.rows.length, true);
    }
    // noticeGroups over noticeView's rows: [name, found, want as chip,
    // packaged, optional and purposes per group]. A group is optional only
    // while every requirement in it is. vgs-a and vgs-b come from one
    // package, and the
    // command `shared`, with no package, carries that package's name.
    const sharing = ctx.validateManifest({
        schemaVersion: 1, id: "acme.sharing", name: "Sharing", version: "1", author: "a", description: "d",
        kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["requirements"],
        requirements: [
            { command: "vgs-a", packages: { pacman: "shared" }, purpose: "A" },
            { command: "vgs-c", purpose: "C" },
            { command: "vgs-b", packages: { pacman: "shared" }, optional: true, purpose: "B" },
            { command: "shared", purpose: "D" },
            { command: "vgs-e", packages: { aur: "other-git" }, purpose: "E" },
        ],
    }, "/p").manifest;
    const sharingMissing = ["vgs-a", "vgs-c", "vgs-b", "shared", "vgs-e"];
    const groupRows = [
        ["requirements one package provides are one group, in first-appearance order", ARCH,
            [["shared", true, false, ["A", "B"]], ["vgs-c", false, false, ["C"]], ["shared", false, false, ["D"]], ["other-git", true, false, ["E"]]]],
        ["without packages each requirement is its own group", null,
            [["vgs-a", false, false, ["A"]], ["vgs-c", false, false, ["C"]], ["vgs-b", false, true, ["B"]], ["shared", false, false, ["D"]], ["vgs-e", false, false, ["E"]]]],
    ];
    for (const [name, found, want] of groupRows) {
        const v = ctx.noticeView(sharing, sharingMissing, {}, n("acme.sharing", sharingMissing, ["vgs-a"]), found);
        check("noticeGroups: " + name, ctx.noticeGroups(v.rows).map(g => [g.chip, g.packaged, g.optional, g.purposes]), want);
    }
    const pkgRow = (name, optional) => ({ name: name, purpose: name, optional: optional, state: "missing", package: { manager: "pacman", name: "shared" } });
    check("noticeGroups: an optional requirement and a required one of one package are a required group",
        ctx.noticeGroups([pkgRow("vgs-b", true), pkgRow("vgs-a", false)]).map(g => [g.chip, g.optional]), [["shared", false]]);
    const coreView = ctx.noticeView(core, ["gum"], {}, n("core", ["gum"], ["gum"]), ARCH);
    check("noticeView: the core's notice installs its package", [coreView.satisfied, coreView.rows.map(rowText), coreView.run.action, coreView.run.args], [false, ["gum (pacman/gum) optional: Dialogs"], "install", ["gum"]]);

    // noticeSettle: [name, queue, missing per plugin, installing id, the
    // ids kept]. acme.gone has no manifest.
    const manifests = { "acme.needs": needs, "acme.other": Object.assign({}, needs, { id: "acme.other" }) };
    const held = [n("acme.needs", ["vgs-one"], ["vgs-one"]), n("acme.other", ["vgs-nix"], ["vgs-nix"])];
    const settleRows = [
        ["notices still missing a required command stay", held, { "acme.needs": ["vgs-one"], "acme.other": ["vgs-nix"] }, "", ["acme.needs", "acme.other"]],
        ["a satisfied notice goes", held, { "acme.needs": [], "acme.other": ["vgs-nix"] }, "", ["acme.other"]],
        ["the installing notice stays satisfied until its run's scan", held, { "acme.needs": [], "acme.other": ["vgs-nix"] }, "acme.needs", ["acme.needs", "acme.other"]],
        ["another plugin's install keeps no satisfied notice", held, { "acme.needs": [], "acme.other": ["vgs-nix"] }, "acme.other", ["acme.other"]],
        ["a plugin with no missing list is satisfied", held, { "acme.other": ["vgs-nix"] }, "", ["acme.other"]],
        ["a notice whose plugin went goes, installing or not", [n("acme.gone", ["vgs-one"], ["vgs-one"])].concat(held), { "acme.gone": ["vgs-one"], "acme.needs": ["vgs-one"], "acme.other": ["vgs-nix"] }, "acme.gone", ["acme.needs", "acme.other"]],
    ];
    for (const [name, queue, missing, installing, want] of settleRows)
        check("noticeSettle: " + name, ctx.noticeSettle(queue, manifests, missing, {}, installing).map(e => e.id), want);
    const coreHeld = [n("core", ["gum"], ["gum"])];
    check("noticeSettle: the core's notice stays while its command is missing", ctx.noticeSettle(coreHeld, { core: core }, { core: ["gum"] }, {}, "").map(e => e.id), ["core"]);
    check("noticeSettle: the core's notice goes once the scan finds its command", ctx.noticeSettle(coreHeld, { core: core }, { core: [] }, {}, "").map(e => e.id), []);

    // noticeDetected: [name, completion, stdout, stderr, want as the
    // managers found or the log line].
    const ok = { code: 0, status: 0 };
    const arch = JSON.stringify(ARCH);
    const detectRows = [
        ["a detection that answered", ok, arch + "\n", "", ARCH],
        ["a system with no primary", ok, JSON.stringify({ primary: null, overlays: [{ id: "flatpak", binary: "flatpak" }], sources: [] }), "", { primary: null, overlays: [{ id: "flatpak", binary: "flatpak" }], sources: [] }],
        ["a detection that never started", null, "", "", "notices: detect=unstarted"],
        ["a detection that failed", { code: 1, status: 0 }, "", "vgshell: refused: os-release=unreadable\nmore", "notices: detect=failed exit=1 status=0 vgshell: refused: os-release=unreadable"],
        ["a detection that crashed", { code: 0, status: 1 }, arch, "", "notices: detect=failed exit=0 status=1 "],
        ["output that does not parse", ok, "primary=pacman", "", "notices: detect=unparseable"],
        ["a manager the table does not know", ok, JSON.stringify({ primary: { id: "brew", binary: "brew" }, overlays: [], sources: [] }), "", "notices: detect=malformed"],
        ["an entry without a binary", ok, JSON.stringify({ primary: { id: "pacman" }, overlays: [], sources: [] }), "", "notices: detect=malformed"],
        ["overlays that are not a list", ok, JSON.stringify({ primary: null, overlays: {}, sources: [] }), "", "notices: detect=malformed"],
        ["no sources", ok, JSON.stringify({ primary: null, overlays: [] }), "", "notices: detect=malformed"],
        ["holders are optional", ok, JSON.stringify(Object.assign({}, ARCH, { holders: { "vgs-old": { path: "/usr/bin/vgs-old", owners: { pacman: "old", aur: null } }, missing: { path: null, owners: {} } } })), "", Object.assign({}, ARCH, { holders: { "vgs-old": { path: "/usr/bin/vgs-old", owners: { pacman: "old", aur: null } }, missing: { path: null, owners: {} } } })],
        ["a holder command must be a command name", ok, JSON.stringify(Object.assign({}, ARCH, { holders: { "/bin/sh": { path: "/bin/sh", owners: { pacman: "bash" } } } })), "", "notices: detect=malformed"],
        ["a holder owner must be a known manager", ok, JSON.stringify(Object.assign({}, ARCH, { holders: { sh: { path: "/bin/sh", owners: { brew: "bash" } } } })), "", "notices: detect=malformed"],
        ["a missing holder has no owners", ok, JSON.stringify(Object.assign({}, ARCH, { holders: { sh: { path: null, owners: { pacman: "bash" } } } })), "", "notices: detect=malformed"],
        ["a list for an answer", ok, "[]", "", "notices: detect=malformed"],
    ];
    for (const [name, completion, stdout, stderr, want] of detectRows) {
        const r = ctx.noticeDetected(completion, stdout, stderr);
        check("noticeDetected: " + name, r.ok ? r.found : r.line, want);
    }

    // consentSlotView: the first-start welcome around the Hyprland question.
    // The key rows are the repository's shipped shell.json's, so a key row
    // it drops fails here too.
    const shipped = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "config", "shell.json"), "utf8"));
    const binder = (id, shortcut, key) => ctx.validateManifest({
        schemaVersion: 1, id, name: "B", version: "1", author: "a", description: "d",
        kinds: ["service"], entryPoints: { service: "S.qml" }, capabilities: ["shortcut"], hyprland: { binds: [{ shortcut, key }] },
    }, "/p").manifest;
    const keyhints = ctx.hyprlandSection({}, binder("vgs.keyhints", "toggle", "SUPER+SLASH"));
    const themes = ctx.hyprlandSection({}, binder("vgs.themes", "themes", "SUPER+SHIFT+T"));
    const keyhintsUnbound = ctx.hyprlandSection({ plugins: [{ id: "vgs.keyhints", keys: { toggle: null } }] }, binder("vgs.keyhints", "toggle", "SUPER+SLASH"));
    const keyhintsMoved = ctx.hyprlandSection({ plugins: [{ id: "vgs.keyhints", keys: { toggle: "SUPER+SHIFT+K" } }] }, binder("vgs.keyhints", "toggle", "SUPER+SLASH"));
    const QUESTION = "Let VGS manage its Hyprland settings?";
    const CONNECT = [{ label: "Connect", role: "accept", answer: "connect" }, { label: "Not now", role: "cancel", answer: "decline" }];
    const CLOSE = [{ label: "Close", role: "cancel", answer: "close" }];
    const LINK = { text: "hyprland.lua", path: "hypr/hyprland.lua" };
    const phase = (name, queued, failure) => ({ phase: name, queued: queued || "", failure: failure || "" });
    const shape = view => view === null ? null : ({
        welcome: view.welcome,
        title: view.title,
        message: view.message === "" ? "" : "present",
        lineCount: view.lines.length,
        link: view.link,
        keys: view.keys,
        keysTitle: view.keysTitle,
        actions: view.actions,
        failure: view.failure,
        busy: view.busy
    });
    const welcome = (lineCount, keys, asking, failure, busy, link) => ({ welcome: true, title: "Welcome to VGS", message: "", lineCount, link: link === undefined ? LINK : link, keys, keysTitle: "Quick commands", actions: asking ? CONNECT : CLOSE, failure: failure || "", busy: busy === true });
    const question = { welcome: false, title: QUESTION, message: "", lineCount: 1, link: LINK, keys: [], keysTitle: "", actions: CONNECT, failure: "", busy: false };
    const keyLine = (shortcut, text) => ({ shortcut, text });
    const keyHintsLine = keyLine("Super+/", "shows every key VGS adds.");
    const themeLine = keyLine("Super+Shift+T", "picks a theme.");
    // [name, consent, welcome state, shipped, sections, want].
    const slotRows = [
        ["an unseen welcome asks with Connect and Not now", phase("asking"), "unseen", shipped, [keyhints, themes], welcome(3, [keyHintsLine, themeLine], true)],
        ["the key-hints row is absent while its shortcut is not bound", phase("asking"), "unseen", shipped, [themes], welcome(3, [themeLine], true)],
        ["the key-hints row is absent while the user unbinds it", phase("asking"), "unseen", shipped, [keyhintsUnbound, themes], welcome(3, [themeLine], true)],
        ["a key row reads the key the user binds", phase("asking"), "unseen", shipped, [keyhintsMoved], welcome(3, [keyLine("Super+Shift+K", "shows every key VGS adds.")], true)],
        ["no enabled plugin binds a key row", phase("asking"), "unseen", shipped, [], welcome(3, [], true)],
        ["a shipped file without welcome keys draws the fixed lines", phase("asking"), "unseen", { version: 1 }, [keyhints, themes], welcome(3, [], true)],
        ["a failed Connect keeps the welcome with the failure", phase("asking", "", "wire=failed status=1"), "unseen", shipped, [themes], welcome(3, [themeLine], true, "wire=failed status=1")],
        ["a queued answer makes the welcome busy", phase("asking", "connect"), "unseen", shipped, [themes], welcome(3, [themeLine], true, "", true)],
        ["an unseen welcome over a wired file offers Close alone", phase("wired"), "unseen", shipped, [themes], welcome(2, [themeLine], false)],
        ["an unseen welcome with no hyprland.lua offers Close alone without a link", phase("settled"), "unseen", shipped, [themes], welcome(2, [themeLine], false, "", false, null)],
        ["an unseen welcome declined this session offers Close alone", phase("declined"), "unseen", shipped, [themes], welcome(2, [themeLine], false)],
        ["the welcome waits for the probe", phase("pending"), "unseen", shipped, [themes], null],
        ["the welcome waits for the decline marker's read", phase("unwired"), "unseen", shipped, [themes], null],
        ["the slot waits for the welcome marker's read", phase("asking"), "reading", shipped, [themes], null],
        ["a seen welcome leaves the plain question", phase("asking"), "seen", shipped, [keyhints, themes], question],
        ["a seen welcome over a wired file draws nothing", phase("wired"), "seen", shipped, [themes], null],
        ["a seen welcome after Not now draws nothing", phase("declined"), "seen", shipped, [themes], null],
    ];
    for (const [name, consent, state, file, sections, want] of slotRows)
        check("consentSlotView: " + name, shape(ctx.consentSlotView(consent, state, file, sections)), want);
    const throws = (fn) => { try { fn(); return "returned"; } catch (e) { return e.message.split(":")[0]; } };
    check("consentSlotView: an unknown welcome state is refused", throws(() => ctx.consentSlotView(phase("asking"), "maybe", shipped, [])), "consentSlotView");
    check("consentSlotView: an unknown consent phase is refused", throws(() => ctx.consentSlotView(phase("later"), "unseen", shipped, [])), "consentSlotView");

    // keyLabel: [key, want].
    const labelRows = [
        ["SUPER+SLASH", "Super+/"],
        ["SUPER+T", "Super+T"],
        ["SUPER+1", "Super+1"],
        ["SUPER+CTRL+SPACE", "Super+Ctrl+Space"],
        ["ALT+SHIFT+RETURN", "Alt+Shift+Return"],
        ["SUPER+BRACKETLEFT", "Super+["],
        ["SUPER+code:108", "Super+code:108"],
    ];
    for (const [key, want] of labelRows) check("keyLabel: " + key, ctx.keyLabel(key), want);

    // welcomeStep: [name, welcome state, event, want as [state, write]].
    const stepRows = [
        ["a marker that exists reads seen", "reading", { type: "read", seen: true }, ["seen", false]],
        ["an absent marker reads unseen", "reading", { type: "read", seen: false }, ["unseen", false]],
        ["Close closes the welcome and writes the marker", "unseen", { type: "answer", answer: "close" }, ["seen", true]],
        ["Not now waits for the decline", "unseen", { type: "answer", answer: "decline" }, ["unseen", false]],
        ["Connect waits for the wiring", "unseen", { type: "answer", answer: "connect" }, ["unseen", false]],
        ["Not now on the plain question writes nothing", "seen", { type: "answer", answer: "decline" }, ["seen", false]],
        ["a Connect that wires closes the welcome and writes the marker", "unseen", { type: "consent", before: phase("asking", "connect"), after: phase("wired") }, ["seen", true]],
        ["a Not now that declines closes the welcome and writes the marker", "unseen", { type: "consent", before: phase("asking", "decline"), after: phase("declined") }, ["seen", true]],
        ["a decline found at start keeps the welcome", "unseen", { type: "consent", before: phase("unwired"), after: phase("declined") }, ["unseen", false]],
        ["a Connect that fails keeps the welcome", "unseen", { type: "consent", before: phase("asking", "connect"), after: phase("asking", "", "wire=failed status=1") }, ["unseen", false]],
        ["a file wired at start keeps the welcome", "unseen", { type: "consent", before: phase("pending"), after: phase("wired") }, ["unseen", false]],
        ["a wiring after the welcome writes nothing", "seen", { type: "consent", before: phase("asking", "connect"), after: phase("wired") }, ["seen", false]],
    ];
    for (const [name, state, event, want] of stepRows) {
        const r = ctx.welcomeStep(state, event);
        check("welcomeStep: " + name, [r.welcome, r.write], want);
    }
    check("welcomeStep: a second read is refused", throws(() => ctx.welcomeStep("seen", { type: "read", seen: false })), "welcomeStep");
    check("welcomeStep: Close on a seen welcome is refused", throws(() => ctx.welcomeStep("seen", { type: "answer", answer: "close" })), "welcomeStep");
}

suite(load(LOGIC), report);

// Each control removes one rule from a copy of the judge and keeps the text
// around it; the suite must fail on every copy. The copy sits at the
// judge's own place in a temporary tree, beside the files it imports.
const CONTROLS = [
    ["installed requires only the needed commands", ": listed.filter(function (row) { return !row.optional; });", ": listed;"],
    ["a request requires its optional commands", "required = trigger === \"requested\" ? listed : ", "required = "],
    ["installed lists only missing commands", "var lacking = rows.filter(function (row) { return row.state !== \"present\"; });", "var lacking = rows;"],
    ["an install or enable trigger lists no outdated command", "listed = trigger === \"requested\" ? lacking : lacking.filter(function (row) { return row.state === \"missing\"; });", "listed = lacking;"],
    ["an unchanged run names a requirement of the manager that ran", "r.package !== null && r.package.manager === ran.manager && (", "r.package !== null && ("],
    ["a package the press updated is judged outdated", "var stillOutdated = judged(ran.updates, \"outdated\");", "var stillOutdated = function () { return false; };"],
    ["a package the press installed is judged missing", "var stillMissing = judged(ran.installs, \"missing\");", "var stillMissing = function () { return false; };"],
    ["a package is judged by the state its own list names", "return r.state === state && names.indexOf(r.package.name) !== -1;", "return names.indexOf(r.package.name) !== -1;"],
    ["only a package the press ran is judged", "return r.state === state && names.indexOf(r.package.name) !== -1;", "return r.state === state;"],
    ["an unchanged run is named by its requirement's state", "var named = { kind: row.state,", "var named = { kind: ran.updates.length === 0 ? \"missing\" : \"outdated\","],
    ["an unchanged run names its package, not its command", "var named = { kind: row.state, name: row.package.name };", "var named = { kind: row.state, name: row.name };"],
    ["an unchanged run names every package it left", "var left = owed.filter(function (row, i) {", "var left = owed.slice(0, 1).filter(function (row, i) {"],
    ["a run that left nothing is no failure", "return left.length === 0 ? null : { kind: \"unchanged\", left: left };", "return { kind: \"unchanged\", left: left };"],
    ["an unchanged run names a package once", "return !owed.slice(0, i).some(", "return true || !owed.slice(0, i).some("],
    ["an unchanged update names the version its command printed", "VERSION_IN_LINE.exec(versions[row.name]).slice(1, 4).join(\".\")", "versions[row.name]"],
    ["one press installs a manager's missing packages beside its updates", ".concat(installs.length === 0 ? [] : [\"--install\"].concat(installs))", ""],
    ["a manager with an update is pressed first", "var order = runs.filter(function (g) { return updatesOf(g).length > 0; }).concat(runs.filter(function (g) { return updatesOf(g).length === 0; }));", "var order = runs;"],
    ["later stops at the last manager that holds a required package", "next.slice(0, unreached ? next.length : reach)", "next"],
    ["later holds every manager while no press reaches a required package", "unreached ? next.length : reach", "reach"],
    ["later holds no entry of the press's own manager", "var next = order.slice(1);", "var next = order;"],
    ["later follows the order of the presses", "reached.reduce(function (held, manager) { return held.concat(entries.filter(function (e) { return e.manager === manager; })); }, [])", "entries.filter(function (e) { return reached.indexOf(e.manager) !== -1; })"],
    ["a view draws its later entries", ".concat(waiting.map(function (e) { return Object.assign({}, e, { later: true }); }))", ""],
    ["a view marks the entries of later presses", "Object.assign({}, e, { later: true })", "Object.assign({}, e, { later: false })"],
    ["the title counts the later entries the view draws", "view.drawn.filter(function (e) { return e.update || !e.optional; })", "view.drawn.filter(function (e) { return (e.update || !e.optional) && !e.later; })"],
    ["the title leaves missing optional entries out", "view.drawn.filter(function (e) { return e.update || !e.optional; })", "view.drawn"],
    ["the title counts an outdated optional entry", "view.drawn.filter(function (e) { return e.update || !e.optional; })", "view.drawn.filter(function (e) { return !e.optional; })"],
    ["a missing package left by an install says whether it is optional", "return r.package.name !== row.package.name || r.optional;", "return false;"],
    ["a missing required tool draws in the danger tone", "{ text: \"Missing\", tone: \"danger\" }", "{ text: \"Missing\", tone: \"warning\" }"],
    ["a missing optional tool draws Optional in the info tone", "optional ? { text: \"Optional\", tone: \"info\" } : ", "false ? { text: \"Optional\", tone: \"info\" } : "],
    ["an outdated tool draws in the warning tone", "{ text: \"Outdated\", tone: \"warning\" }", "{ text: \"Outdated\", tone: \"danger\" }"],
    ["a notice entry reads Outdated for an update", "requirementBadge(g.update ? \"outdated\" : \"missing\", g.optional)", "requirementBadge(\"missing\", g.optional)"],
    ["a group is optional only while each requirement is", "            held.optional = held.optional && row.optional;\n", ""],
    ["a view lists only the packages its press handles", "entries.filter(function (e) { return e.manager === pressed.manager; })", "entries"],
    ["a press updates only a package of its own manager", "e.manager === group.manager && e.chip === name && e.update", "e.chip === name && e.update"],
    ["an offer is a list", "if (!Array.isArray(commands) || commands.length === 0", "if (commands.length === 0"],
    ["an offer is not empty", " || commands.length === 0 || commands.length > NOTICE_OFFER_MAX", " || commands.length > NOTICE_OFFER_MAX"],
    ["an offer names at most sixteen commands", " || commands.length > NOTICE_OFFER_MAX || ", " || "],
    ["an offer names strings", " || !commands.every(function (c) { return typeof c === \"string\"; }))", ")"],
    ["an offer names declared commands", "        if (undeclared.length > 0)\n", "        if (false)\n"],
    ["an offer lists only missing commands", "return row.state !== \"present\" && commands.indexOf(row.name) !== -1;", "return commands.indexOf(row.name) !== -1;"],
    ["an offer of nothing lacking is satisfied", "answer: listed.length === 0 ? \"satisfied\" : \"ok\"", "answer: \"ok\""],
    ["nothing required is satisfied", "answer: required.length === 0 ? \"satisfied\" : \"ok\"", "answer: \"ok\""],
    ["a held plugin's notice is merged", "    if (at !== -1) {\n", "    if (false) {\n"],
    ["a merge keeps the held commands", "var union = function (held, added) { return held.concat(", "var union = function (held, added) { return [].concat(added, "],
    ["a suggestion rests", "if (trigger === \"suggested\" && hasOwn(rest, id) && rest[id] > now)", "if (false)"],
    ["only a suggestion rests", "if (trigger === \"suggested\" && hasOwn(rest, id)", "if (hasOwn(rest, id)"],
    ["a press offer never rests", "if (trigger === \"suggested\" && hasOwn(rest, id)", "if ((trigger === \"suggested\" || trigger === \"offered\") && hasOwn(rest, id)"],
    ["a suggestion lists as an offer", "    case \"offered\":\n    case \"suggested\":\n", "    case \"offered\":\n"],
    ["a rest ends", "hasOwn(rest, id) && rest[id] > now)", "hasOwn(rest, id))"],
    ["the queue has a ceiling", "if (queue.length >= NOTICE_QUEUE_MAX)", "if (false)"],
    ["the queue is not changed in place", "var merged = queue.slice();", "var merged = queue;"],
    ["a view lists only missing commands", "requirementRows(manifest, missing, versions).filter(function (row) { return row.state !== \"present\"; });\n    var rows", "requirementRows(manifest, missing, versions);\n    var rows"],
    ["a view is satisfied only without a required command", "var satisfied = !notice.required.some(", "var satisfied = notice.required.some("],
    ["a view groups the requirements one package provides", "if (held === undefined) out.push(", "if (true) out.push("],
    ["a group keeps a package apart from a requirement of its name", "g.manager === manager && g.chip === chip", "g.chip === chip"],
    ["a view installs only through an installing manager", "var runs = plan.groups.filter(function (g) { return g.installs; });", "var runs = plan.groups;"],
    ["a view ignores holders", "PackageManagers.installGroups(rows, found);", "PackageManagers.installGroups(rows, Object.assign({}, found, { holders: {} }));"],
    ["a settle keeps the installing notice", "        if (n.id === installing)\n            return true;\n", ""],
    ["a settle drops a notice whose owner went", "        if (!hasOwn(owners, n.id))\n            return false;\n", ""],
    ["a settle drops a satisfied notice", "        return !noticeView(owners[n.id]", "        return true || !noticeView(owners[n.id]"],
    ["a choice lists as an offer", "    case \"suggested\":\n    case \"chosen\":\n", "    case \"suggested\":\n"],
    ["an owner is a string", "    if (typeof owner !== \"string\")\n        return \"refused: owner=malformed\";\n", ""],
    ["an owner is known", "    if (!hasOwn(owners, owner))\n        return \"refused: owner=\"", "    if (false)\n        return \"refused: owner=\""],
    ["a plugin owner is enabled", "if (owner !== CORE_OWNER && enabled.indexOf(owner) === -1)", "if (false)"],
    ["the core owner needs no enabling", "if (owner !== CORE_OWNER && enabled.indexOf(owner) === -1)", "if (enabled.indexOf(owner) === -1)"],
    ["a detection that crashed is a failure", "if (completion.status !== 0 || completion.code !== 0)\n        return { ok: false, line: \"notices: detect=failed", "if (completion.code !== 0)\n        return { ok: false, line: \"notices: detect=failed"],
    ["a detected manager is a known one", " && PackageManagers.managerRow(e.id) !== null", ""],
    ["a detection names its sources", " || !Array.isArray(found.sources) || !found.sources.every(entry)", ""],
    ["a detection accepts a malformed holder command", "return PackageManagers.validCommand(command) && holder(holders[command]);", "return holder(holders[command]);"],
    ["a detection accepts a missing holder with owners", "&& (h.path !== null || Object.keys(h.owners).length === 0)\n            && ", "&& "],
    ["a seen welcome leaves the plain question", "    if (welcomeState === \"seen\")\n", "    if (false)\n"],
    ["the welcome waits for the marker's read", "    if (welcomeState === \"reading\") return null;\n", ""],
    ["the welcome waits for the consent answer", "    if (WELCOME_WAITS.indexOf(consent.phase) !== -1) return null;\n", ""],
    ["a key row needs its bind", "return typeof key === \"string\" ? { shortcut: keyLabel(key), text: row.text } : null;", "return { shortcut: keyLabel(typeof key === \"string\" ? key : \"SUPER+SLASH\"), text: row.text };"],
    ["the question carries the welcome file link", "lines: [question.message], link: WELCOME.link, keys: []", "lines: [question.message], link: null, keys: []"],
    ["the welcome carries its file link except settled", "link: consent.phase === \"settled\" ? null : WELCOME.link,", "link: null,"],
    ["a settled consent offers Close alone", "actions: question === null ? [{ label: WELCOME.close, role: \"cancel\", answer: \"close\" }] : actions,", "actions: actions,"],
    ["a key that types a character reads as it", "        if (hasOwn(KEY_GLYPHS, part)) return KEY_GLYPHS[part];\n", ""],
    ["a read records the marker", "return { welcome: event.seen ? \"seen\" : \"unseen\", write: false };", "return { welcome: \"unseen\", write: false };"],
    ["Not now waits for the decline", "        case \"connect\":\n        case \"decline\":\n            return keep;\n", "        case \"connect\":\n            return keep;\n        case \"decline\":\n            return seen;\n"],
    ["a Not now that declines closes the welcome", " || event.after.phase === \"declined\")", ")"],
    ["Close closes the welcome", "            return seen;\n        }\n", "            return keep;\n        }\n"],
    ["a Connect that wires closes the welcome", "(event.after.phase === \"wired\" || ", "("],
    ["only an answer closes the welcome on a consent change", "event.before.phase === \"asking\" && (", "("],
];

const temp = fs.mkdtempSync(path.join(os.tmpdir(), "notice-logic-control-"));
try {
    for (const [source, relative] of IMPORTS) {
        fs.mkdirSync(path.dirname(path.join(temp, relative)), { recursive: true });
        fs.symlinkSync(source, path.join(temp, relative));
    }
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

if (failures > 0) { console.log("test-notice-logic: " + failures + " failing"); process.exit(1); }
console.log("test-notice-logic: ok");
