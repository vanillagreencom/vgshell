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
const render = require("../bin/lib/theme-render.js");

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

// Exercise every shipped entry-plus-selection form through the setup reader.
// No application or reload hook runs in this temporary HOME.
const setupRepo = path.join(__dirname, "..");
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "themes-setup-"));
try {
    const tree = path.join(scratch, "tree");
    const home = path.join(scratch, "home");
    const config = path.join(home, ".config");
    const state = path.join(home, ".local/state/vgshell");
    // Settings stay independent of the declarations under test. Managed entry
    // paths come from those declarations, so new shipped entries are covered.
    const configurations = [
        { name: "bat", base: config, roots: ["bat"], settings: "config", values: true,
            lines: [null],
            selected: "--theme=vgs\n", other: "--theme=other\n" },
        { name: "btop", base: config, roots: ["btop"], settings: "btop.conf",
            lines: ["color_theme = vgs"],
            selected: 'color_theme = "vgs"\n# owner\n', other: 'color_theme = "Default"\n# owner\n', missing: '# owner\n' },
        { name: "claude", base: home, roots: [".claude", ".claude-work"], settings: "settings.json",
            nested: [".claude", ".claude/work"], explicit: "CLAUDE_CONFIG_DIR",
            lines: ["theme = custom:vgs"],
            selected: '{"theme":"custom:vgs","owner":true}\n', other: '{"theme":"dark","owner":true}\n' },
        { name: "codex", base: home, roots: [".codex", ".codex-work"], settings: "config.toml",
            nested: [".codex", ".codex/work"], explicit: "CODEX_HOME",
            lines: ["tui.theme = vgs"],
            selected: 'owner = true\n[tui]\ntheme = "vgs"\n', other: 'owner = true\n[tui]\ntheme = "other"\n' },
        { name: "hermes", base: home, roots: [".hermes"], settings: "config.yaml",
            lines: ["display.skin = vgs"],
            selected: 'owner: true\ndisplay:\n  skin: vgs\n', other: 'owner: true\ndisplay:\n  skin: other\n' },
        { name: "omp", base: home, roots: [".omp/agent"], settings: "config.yml",
            lines: ["theme.dark = vgs", "theme.light = vgs"],
            selected: 'owner: true\ntheme:\n  dark: vgs\n  light: vgs\n', other: 'owner: true\ntheme:\n  dark: other\n  light: other\n' },
        { name: "opencode", base: config, roots: ["opencode"], settings: "tui.json",
            lines: ["theme = vgs"],
            selected: '{"theme":"vgs","owner":true}\n', other: '{"theme":"other","owner":true}\n' },
        { name: "pi", base: home, roots: [".pi/agent"], settings: "settings.json",
            lines: ["theme = vgs"],
            selected: '{"theme":"vgs","owner":true}\n', other: '{"theme":"other","owner":true}\n' },
        { name: "television", base: config, roots: ["television"], settings: "config.toml", values: true,
            lines: [null],
            selected: '[ui]\ntheme = "vgs"\n', other: '[ui]\ntheme = "other"\n' },
        { name: "yazi", base: config, roots: ["yazi", "yazi-scratchpad"], settings: "theme.toml", values: true,
            lines: [null],
            selected: '[flavor]\ndark = "vgs"\nlight = "vgs"\n', other: '[flavor]\ndark = "other"\nlight = "other"\n' }
    ];
    for (const name of ["bin", "shell/Commons", ...configurations.map(row => "themes/targets/" + row.name)])
        fs.cpSync(path.join(setupRepo, name), path.join(tree, name), { recursive: true });
    fs.mkdirSync(path.join(state, "theme"), { recursive: true });
    const targets = new Map(configurations.map(row => [row.name,
        JSON.parse(fs.readFileSync(path.join(tree, "themes/targets", row.name, "target.json"), "utf8"))]));
    function declaredEntries(row, root, index) {
        const target = targets.get(row.name);
        const wiringBase = target.wiring.base === "account" ? path.join(row.base, root) : row.base;
        const wiringDir = Array.isArray(target.wiring.dir) ? target.wiring.dir[index] : target.wiring.dir;
        return render.entryItems(target, path.join(state, "theme"), index).map(item => ({ ...item,
            file: path.join(wiringBase, wiringDir, item.name) }));
    }
    for (const row of configurations) {
        for (const [index, root] of [...new Set([...row.roots, ...(row.nested ?? [])])].entries()) {
            for (const item of declaredEntries(row, root, index)) {
                fs.mkdirSync(path.dirname(item.file), { recursive: true });
                fs.writeFileSync(item.to, "managed theme\n");
                if (item.kind === "copy") fs.copyFileSync(item.to, item.file);
                else fs.symlinkSync(item.to, item.file);
            }
        }
    }
    const judge = path.join(tree, "bin/vgshell-theme-judge");
    const env = { HOME: home, PATH: path.dirname(process.execPath), XDG_CONFIG_HOME: config,
        XDG_STATE_HOME: path.join(home, ".local/state"), VGS_TEST_RUN: "1" };
    function readWiring(name, explicit) {
        const result = spawnSync(process.execPath, [judge, "setup", "json", path.join(config, "vgshell"), state], { env: { ...env, ...explicit }, encoding: "utf8", timeout: 10000 });
        assert.equal(result.status, 0, result.stderr);
        return JSON.parse(result.stdout).wiring.filter(row => row.name === name);
    }
    function verifyConfigurations(applied, entryFiles = (row, root, index) => declaredEntries(row, root, index).map(item => item.file)) {
        for (const name of ["theme.json", "terminal.json"]) fs.rmSync(path.join(state, "theme", name), { force: true });
        if (applied !== "absent") fs.copyFileSync(path.join(setupRepo, "themes/vgs/theme.json"), path.join(state, "theme/theme.json"));
        if (applied === "valid") fs.copyFileSync(path.join(setupRepo, "themes/vgs/terminal.json"), path.join(state, "theme/terminal.json"));
        if (applied === "invalid") fs.writeFileSync(path.join(state, "theme/terminal.json"), "{}\n");
        for (const row of configurations) {
            for (const roots of [row.roots, ...(row.nested ? [row.nested] : [])]) {
                for (const root of new Set([...row.roots, ...(row.nested ?? [])]))
                    fs.rmSync(path.join(row.base, root, row.settings), { recursive: true, force: true });
                const explicit = roots === row.nested ? { [row.explicit]: path.join(row.base, roots[1]) } : {};
                const states = row.roots.length === 1 ? [[true], [false], [null], ["missing"], ["unreadable"]]
                    : [[true, false], [false, true], [true, true], [false, false], [true, null], [null, true], [true, "missing"], ["missing", true], [true, "unreadable"], ["unreadable", true]];
                for (const connected of states) {
                    const expected = [];
                    for (const [index, root] of roots.entries()) {
                        const file = path.join(row.base, root, row.settings);
                        fs.rmSync(file, { recursive: true, force: true });
                        if (connected[index] === "unreadable") fs.mkdirSync(file);
                        else if (connected[index] === "missing") fs.writeFileSync(file, row.missing ?? "");
                        else if (connected[index] !== null) fs.writeFileSync(file, connected[index] ? row.selected : row.other);
                        const unknownValues = row.values && applied !== "valid";
                        if (unknownValues || connected[index] === true)
                            for (const entry of entryFiles(row, root, index)) expected.push([entry, null, "wired", null]);
                        if (!unknownValues && connected[index] === true)
                            for (const line of row.lines) expected.push([file, line, "wired", null]);
                        if (!unknownValues && connected[index] === "unreadable") expected.push([file, null, "unreadable", "EISDIR"]);
                    }
                    const actual = readWiring(row.name, explicit).map(item => [item.file, item.line, item.state, item.error ?? null]);
                    const byFileAndLine = (left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right));
                    assert.deepEqual(actual.sort(byFileAndLine), expected.sort(byFileAndLine), row.name + ": " + roots.join(",") + ": " + applied + ": " + connected.join(","));
                    for (const [index, root] of roots.entries()) {
                        const file = path.join(row.base, root, row.settings);
                        if (typeof connected[index] === "boolean") assert.equal(fs.readFileSync(file, "utf8"), connected[index] ? row.selected : row.other);
                        else if (connected[index] === null) assert.equal(fs.existsSync(file), false);
                        else if (connected[index] === "missing") assert.equal(fs.readFileSync(file, "utf8"), row.missing ?? "");
                        else assert.equal(fs.statSync(file).isDirectory(), true);
                    }
            }
            }
        }
    }
    for (const applied of ["absent", "theme-only", "invalid", "valid"]) verifyConfigurations(applied);
    // An incomplete expected inventory must not hide a declared managed file.
    assert.throws(() => verifyConfigurations("valid", (row, root, index) => row.name === "pi"
        ? [path.join(row.base, root, "themes/vgs.json")]
        : declaredEntries(row, root, index).map(item => item.file)),
    { name: "AssertionError", message: /^pi: \.pi\/agent: valid: true\b/ });
    // Each control retains the selection operation in the disposable judge.
    // The complete behavior table must fail when values or isolation are lost.
    const source = fs.readFileSync(judge, "utf8");
    const controls = [
        ["selectionEdits(target, configHome, live, undefined, undefined, selectionValues).map", "selectionEdits(target, configHome, live, undefined, undefined).map"],
        ["return owner?.connected === true;", "return owner !== undefined;"],
        ["return owner?.connected === true;", "return owner?.connected === true && selections.every(item => item.connected);"],
        ["root.length > path.dirname(nearest.file).length", "selection.connected"],
        ["for (const [index, dir] of dirs.entries()) {", "for (const [index, dir] of dirs.filter(keep).entries()) {",
            { name: "AssertionError", message: /^yazi: yazi,yazi-scratchpad: valid: false,true\b/ }]
    ];
    for (const [needle, replacement, failure] of controls) {
        assert.equal(source.split(needle).length, 2);
        const mutant = source.replace(needle, replacement);
        assert.notEqual(mutant, source);
        fs.writeFileSync(judge, mutant);
        assert.throws(() => verifyConfigurations("valid"), failure ?? { name: "AssertionError" });
        fs.writeFileSync(judge, source);
    }
} finally {
    fs.rmSync(scratch, { recursive: true, force: true });
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
