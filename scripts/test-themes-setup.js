#!/usr/bin/env node
// The Browser theming row of vgs.themes, shell/plugins/vgs.themes/SetupLogic.js,
// under node: each state `vgshell theme setup --json` reports for the chromium
// target reads as its row, only a missing writer offers the Install browser
// theming action, a tree that ships no chromium setup reads as not
// shipped, and a report that failed or does not parse reads as unknown and
// offers nothing. The value each row answers
// fits the plugin's own manifest, through the core's status judge. Every
// expected value is written out by hand.
//
// The controls at the end edit a copy of the logic, one rule at a time,
// and require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { spawnSync } = require("node:child_process");
const { load } = require("../bin/lib/qml-library.js");

const dir = path.join(__dirname, "..", "shell", "plugins", "vgs.themes");
const file = path.join(dir, "SetupLogic.js");
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message);
const report = state => JSON.stringify({ setups: [{ name: "chromium", app: "Chromium, Google Chrome, Microsoft Edge and Brave", setup: "vgshell-browser-policy", state }] }) + "\n";
const wiringReport = rows => JSON.stringify({ home: "/home/alice", setups: [], wiring: rows }) + "\n";

// [label, stdout, exit code, the value]. The Setup tone rule
// (design-system.md, Steps.js stepOpen): browser theming is optional, so
// its open step reads info, and a report the user cannot mend reads info.
const ROWS = [
    ["the writer installed", report("done"), 0, { tone: "ok", text: "Browser theme support is installed" }],
    ["a browser without the writer", report("absent"), 0, { tone: "info", text: "Browser themes are not installed", action: true }],
    ["no browser", report("not-detected"), 0, { tone: "info", text: "No Chromium-family browser found" }],
    ["a failed report", report("done"), 1, { tone: "info", text: "Browser theme setup could not be checked. Open Plugins to check Themes." }],
    ["a report that did not start", report("done"), null, { tone: "info", text: "Browser theme setup could not be checked. Open Plugins to check Themes." }],
    ["a report killed by a signal, whose code is no exit code", "", -1, { tone: "info", text: "Browser theme setup could not be checked. Open Plugins to check Themes." }],
    ["no JSON", "setup=chromium\n", 0, { tone: "info", text: "Browser theme setup could not be checked. Open Plugins to check Themes." }],
    ["no setups list", "{}\n", 0, { tone: "info", text: "Browser theme setup could not be checked. Open Plugins to check Themes." }],
    ["no chromium row", JSON.stringify({ setups: [{ name: "other", app: "Other", setup: "other-writer", state: "done" }] }), 0, { tone: "info", text: "This version of VGS does not support browser themes" }],
    ["another target's row after chromium's", JSON.stringify({ setups: [{ name: "chromium", app: "C", setup: "vgshell-browser-policy", state: "done" }, { name: "other", app: "Other", setup: "other-writer", state: "absent" }] }), 0, { tone: "ok", text: "Browser theme support is installed" }],
    ["an unknown state", report("maybe"), 0, { tone: "info", text: "Browser theme setup could not be checked. Open Plugins to check Themes." }]
];

function verify(logic) {
    for (const [label, text, code, want] of ROWS) same(logic.browserTheming(text, code), want, label);
}

verify(load(file));

const WIRING_ROWS = [
    ["wired rows map to presence items", wiringReport([
        { name: "kitty", app: "kitty", file: "/home/alice/.config/kitty/kitty.conf", line: "include /home/alice/.local/state/vgshell/theme/kitty.conf", state: "wired" },
        { name: "btop", app: "btop", file: "/home/alice/.config/btop/themes/vgs.theme", line: null, state: "wired" }
    ]), 0, [
        { label: "btop", value: "present", hint: "~/.config/btop/themes/vgs.theme" },
        { label: "kitty", value: "present", hint: "~/.config/kitty/kitty.conf: include /home/alice/.local/state/vgshell/theme/kitty.conf" }
    ]],
    ["an unreadable row is unavailable", wiringReport([
        { name: "foot", app: "foot", file: "/home/alice/.config/foot/foot.ini", line: null, state: "unreadable" }
    ]), 0, [
        { label: "foot", value: "unavailable", hint: "~/.config/foot/foot.ini" }
    ]],
    ["a failed report publishes nothing", wiringReport([]), 1, null],
    ["an unparseable report publishes nothing", "setup=chromium\n", 0, null]
];

{
    const rows = [];
    for (let i = 0; i < 35; i++)
        rows.push({ name: `app${i}`, app: `App ${String(i).padStart(2, "0")}`, file: `/home/alice/.config/app${i}/theme.conf`, line: "x".repeat(220), state: "wired" });
    const got = load(file).wiring(wiringReport(rows), 0);
    assert.equal(got.length, 32, "the wiring list is capped");
    same(got[31], { label: "More files", value: "present", hint: "4 more files are not listed" }, "the cap ends with a summary item");
    assert.ok(got.every(item => item.label.length <= 60 && item.hint.length <= 200), "items fit the manifest limits");
}

function verifyWiring(logic) {
    for (const [label, text, code, want] of WIRING_ROWS) same(logic.wiring(text, code), want, label);
}

verifyWiring(load(file));

// Exercise the shipped setup reader against a managed btop link and an
// unrelated selection. No application or reload hook runs in this fixture.
const setupRepo = path.join(__dirname, "..");
const btopScratch = fs.mkdtempSync(path.join(os.tmpdir(), "btop-setup-"));
try {
    const tree = path.join(btopScratch, "tree");
    const home = path.join(btopScratch, "home");
    const config = path.join(home, ".config");
    const state = path.join(home, ".local/state/vgshell");
    for (const name of ["bin", "shell/Commons", "themes/targets/btop"])
        fs.cpSync(path.join(setupRepo, name), path.join(tree, name), { recursive: true });
    fs.mkdirSync(path.join(config, "btop/themes"), { recursive: true });
    fs.mkdirSync(path.join(state, "theme"), { recursive: true });
    fs.writeFileSync(path.join(state, "theme/btop.theme"), "theme[main_bg]=\"#000000\"\n");
    fs.symlinkSync(path.join(state, "theme/btop.theme"), path.join(config, "btop/themes/vgs.theme"));
    const settings = path.join(config, "btop/btop.conf");
    const judge = path.join(tree, "bin/vgshell-theme-judge");
    const env = { HOME: home, PATH: path.dirname(process.execPath), XDG_CONFIG_HOME: config,
        XDG_STATE_HOME: path.join(home, ".local/state"), VGS_TEST_RUN: "1" };
    function readBtopWiring() {
        const result = spawnSync(process.execPath, [judge, "setup", "json", path.join(config, "vgshell"), state], { env, encoding: "utf8", timeout: 10000 });
        assert.equal(result.status, 0, result.stderr);
        return JSON.parse(result.stdout).wiring.filter(row => row.name === "btop" && row.state === "wired");
    }
    for (const selection of ['color_theme = "Default"\n', '# owner\n', null, 'color_theme = "vgs"\n']) {
        if (selection === null) fs.unlinkSync(settings);
        else fs.writeFileSync(settings, selection);
        const rows = readBtopWiring();
        if (selection === 'color_theme = "vgs"\n') {
            assert.ok(rows.some(row => row.file === settings));
            assert.ok(rows.some(row => row.file === path.join(config, "btop/themes/vgs.theme")));
        } else assert.deepEqual(rows, []);
    }
    fs.writeFileSync(settings, 'color_theme = "Default"\n');
    const source = fs.readFileSync(judge, "utf8");
    const needle = 'if (target.select !== undefined && selectionEdits(target, configHome, live)\n                .some(selection => selection.edit(latin1(readIfPresent(selection.file))) !== null)) return [];';
    assert.equal(source.split(needle).length, 2);
    const mutant = source.replace(needle, "");
    assert.notEqual(mutant, source);
    fs.writeFileSync(judge, mutant);
    const mutantRows = readBtopWiring();
    assert.throws(() => assert.deepEqual(mutantRows, []), { name: "AssertionError" });
} finally {
    fs.rmSync(btopScratch, { recursive: true, force: true });
}

// Every value fits the manifest's `browserTheming` entry, whose action the
// core offers only while the value says so.
const pluginLogic = load(path.join(__dirname, "..", "shell", "Core", "PluginLogic.js"));
const judged = pluginLogic.validateManifest(JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf8")), "/x");
assert.equal(judged.ok, true, "the vgs.themes manifest is accepted: " + judged.error);
const logic = load(file);
for (const [label, text, code, want] of ROWS) {
    const value = JSON.parse(JSON.stringify(logic.browserTheming(text, code)));
    assert.equal(pluginLogic.statusWrite(judged.manifest, {}, "browserTheming", value).ok, true, "the core publishes the row of " + label);
    const row = pluginLogic.statusRows(judged.manifest, { browserTheming: value })[0];
    same(row.action, { label: "Install browser theming", icon: "", tone: "", offered: want.action === true, tui: want.action === true ? "browser-policy" : "" }, "the action of " + label);
}
for (const [label, text, code, want] of WIRING_ROWS) {
    if (want === null) continue;
    const value = JSON.parse(JSON.stringify(logic.wiring(text, code)));
    assert.equal(pluginLogic.statusWrite(judged.manifest, {}, "themeWiring", value).ok, true, "the core publishes wiring for " + label);
}

// [label, needle, replacement]: each removes one rule from a copy.
const CONTROLS = [
    ["every state offers the install", 'text: "Browser themes are not installed", action: true }', 'text: "Browser themes are not installed" }'],
    ["the optional install reads info", '"absent": return { tone: "info"', '"absent": return { tone: "warning"'],
    ["an unread report reads info", 'return { tone: "info", text: UNKNOWN_TEXT };', 'return { tone: "danger", text: UNKNOWN_TEXT };'],
    ["a failed report is read", "if (code !== 0) return unknown(\"exited \" + code);", ""],
    ["any target's row is read", "rows[i].name === TARGET", "true"],
    ["an unknown state is installed", 'case "done": return', 'default: return'],
    ["wiring failures publish an empty list", 'if (code !== 0) return unknown("exited " + String(code));', 'if (code !== 0) return [];'],
    ["wiring unreadable rows look present", 'value: row.state === "wired" ? "present" : "unavailable"', 'value: "present"'],
    ["wiring rows are not capped", 'if (items.length > STATUS_LIST_MAX) {', 'if (false) {']
];
const source = fs.readFileSync(file, "utf8");
const scratchRoot = path.join(__dirname, "..", "tmp");
fs.mkdirSync(scratchRoot, { recursive: true });
const temp = fs.mkdtempSync(path.join(scratchRoot, "themes-setup-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const mutant = path.join(temp, "SetupLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, () => replacement));
        let failed = false;
        try {
            verify(load(mutant));
            verifyWiring(load(mutant));
            const rows = [];
            for (let i = 0; i < 35; i++)
                rows.push({ name: `app${i}`, app: `App ${String(i).padStart(2, "0")}`, file: `/home/alice/.config/app${i}/theme.conf`, line: "x".repeat(220), state: "wired" });
            assert.equal(load(mutant).wiring(wiringReport(rows), 0).length, 32);
        } catch (e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the suite passed on a SetupLogic.js without that rule`);
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
console.log(`test-themes-setup: ok rows=${ROWS.length} controls=${CONTROLS.length}`);
