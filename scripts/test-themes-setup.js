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
const { load: loadLibrary } = require("../bin/lib/qml-library.js");
const PageReference = loadLibrary(path.join(__dirname, "../shell/Commons/PageReference.js"));
const load = file => loadLibrary(file, { "qs.Commons 1.0": { PageReference } });
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
    ...["no Oh My Posh init line", "dynamic Oh My Posh init form", "complex Oh My Posh init form"].map(reason => [
        "a disconnected prompt names its cause", wiringReport([{ name: "oh-my-posh", app: "Oh My Posh", file: "/home/alice/.bashrc", line: null, state: "not-wired", reason }]), 0,
        [{ label: "Oh My Posh", value: "absent", hint: "~/.bashrc: not wired: " + reason }]
    ]),
    ...[undefined, null, "", 1].map(reason => ["a disconnected row needs a reason", wiringReport([
        { name: "oh-my-posh", app: "Oh My Posh", file: "/home/alice/.bashrc", line: null, state: "not-wired", reason }
    ]), 0, null]),
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
    assert.ok(got.every(item => item.label.length <= 60 && PageReference.plain(item.hint).length <= 200), "items fit the manifest limits");
}

function verifyWiring(logic) {
    for (const [label, text, code, want] of WIRING_ROWS) {
        const got = logic.wiring(text, code);
        if (got === null) { same(got, want, label); continue; }
        const paths = JSON.parse(text).wiring.slice().sort((a, b) => (a.app + "\n" + a.file).localeCompare(b.app + "\n" + b.file)).map(row => row.file);
        got.forEach((item, index) => {
            const links = PageReference.references(item.hint).links;
            assert.equal(links.length, 1, label + ": file link");
            assert.equal(PageReference.file(links[0].page), paths[index], label + ": source path");
        });
        same(got.map(item => Object.assign({}, item, { hint: PageReference.plain(item.hint) })), want, label);
    }
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
    const kdeColors = '[ColorEffects:Disabled]\nIntensityEffect=2\n[Colors:View]\nBackgroundNormal=#010203\n[Colors:Header][Inactive]\nForegroundNormal=#aabbcc\n';
    const kdeKept = '# owner\r\n[General]\r\nColorScheme=Vgs\r\nfont=Sans\r\n[KDE]\r\nLookAndFeelPackage=owner.desktop\r\nSingleClick=false\r\n[WM]\r\nactiveBackground=#998877\r\n';
    // Settings stay independent of the declarations under test. Managed entry
    // paths come from those declarations, so new shipped entries are covered.
    const configurations = [
        { name: "kcolorscheme", base: config, roots: ["."], settings: "kdeglobals",
            emptySelected: '[General]\nColorScheme=Vgs\n', kept: kdeKept,
            sourceText: '[General]\nName=Vgs\n' + kdeColors + '[WM]\nactiveBackground=#112233\n',
            curatedSource: '[General]\r\nName=Curated\r\n' + kdeColors.replace(/\n/g, '\r\n').slice(0, -2),
            selected: kdeColors.replace(/\n/g, '\r\n') + kdeKept,
            other: '# owner\r\n[Colors:View]\r\nBackgroundNormal=#123456\r\n[ColorEffects:Disabled]\r\nIntensityEffect=2\r\n[Colors:Header][Inactive]\r\nForegroundNormal=#abcdef\r\n[General]\r\nColorScheme=Other\r\nfont=Sans\r\n[KDE]\r\nLookAndFeelPackage=owner.desktop\r\nSingleClick=false\r\n',
            localColors: '[Colors:View]\r\nBackgroundNormal=#123456\r\n[ColorEffects:Disabled]\r\nIntensityEffect=2\r\n[Colors:Header][Inactive]\r\nForegroundNormal=#abcdef\r\n' },
        { name: "bat", base: config, roots: ["bat"], settings: "config", values: true,
            selected: "--theme=vgs\n", other: "--theme=other\n" },
        { name: "btop", base: config, roots: ["btop"], settings: "btop.conf",
            selected: 'color_theme = "vgs"\n# owner\n', other: 'color_theme = "Default"\n# owner\n', missing: '# owner\n' },
        { name: "helix", base: config, roots: ["helix"], settings: "config.toml", selected: 'theme = "vgs"\n# owner\n', other: 'theme = "default"\n# owner\n' },
        { name: "zed", base: config, roots: ["zed"], settings: "settings.json", selected: '{"theme":{"mode":"system","dark":"vgs","light":"vgs"},"owner":true}\n', other: '{"theme":{"mode":"system","dark":"other","light":"vgs"},"owner":true}\n' },
        { name: "obsidian", base: path.join(home, "vaults"), roots: ["one", "two"], settings: ".obsidian/appearance.json", selected: '{"cssTheme":"vgs","owner":true}\n', other: '{"cssTheme":"other","owner":true}\n' },
        { name: "claude", base: home, roots: [".claude", ".claude-work"], settings: "settings.json",
            nested: [".claude", ".claude/work"], explicit: "CLAUDE_CONFIG_DIR",
            selected: '{"theme":"custom:vgs","owner":true}\n', other: '{"theme":"dark","owner":true}\n' },
        { name: "codex", base: home, roots: [".codex", ".codex-work"], settings: "config.toml",
            nested: [".codex", ".codex/work"], explicit: "CODEX_HOME",
            selected: 'owner = true\n[tui]\ntheme = "vgs"\n', other: 'owner = true\n[tui]\ntheme = "other"\n' },
        { name: "hermes", base: home, roots: [".hermes"], settings: "config.yaml",
            selected: 'owner: true\ndisplay:\n  skin: vgs\n', other: 'owner: true\ndisplay:\n  skin: other\n' },
        { name: "omp", base: home, roots: [".omp/agent"], settings: "config.yml",
            selected: 'owner: true\ntheme:\n  dark: vgs\n  light: vgs\n', other: 'owner: true\ntheme:\n  dark: other\n  light: other\n' },
        { name: "opencode", base: config, roots: ["opencode"], settings: "tui.json",
            selected: '{"theme":"vgs","owner":true}\n', other: '{"theme":"other","owner":true}\n' },
        { name: "pi", base: home, roots: [".pi/agent"], settings: "settings.json",
            selected: '{"theme":"vgs","owner":true}\n', other: '{"theme":"other","owner":true}\n' },
        { name: "television", base: config, roots: ["television"], settings: "config.toml", values: true,
            selected: '[ui]\ntheme = "vgs"\n', other: '[ui]\ntheme = "other"\n' },
        { name: "yazi", base: config, roots: ["yazi", "yazi-scratchpad"], settings: "theme.toml", values: true,
            selected: '[flavor]\ndark = "vgs"\nlight = "vgs"\n', other: '[flavor]\ndark = "other"\nlight = "other"\n' },
        ...["qt5ct", "qt6ct"].map(name => ({ name, base: config, roots: [name], settings: name + ".conf",
            emptySelected: '[Appearance]\ncustom_palette=true\ncolor_scheme_path=' + JSON.stringify(path.join(state, "theme", name + ".conf")) + '\n',
            selected: '[Appearance]\ncolor_scheme_path=' + JSON.stringify(path.join(state, "theme", name + ".conf")) + '\ncustom_palette=true\nstyle=Fusion\n',
            other: '[Appearance]\ncolor_scheme_path=other.conf\ncustom_palette=false\nstyle=Fusion\n' })),
        ...["vencord", "vesktop", "equibop"].map(name => ({ name, base: config, roots: [name === "vencord" ? "Vencord" : name], settings: "settings/settings.json",
            emptySelected: '{\n  "enabledThemes": ["vgs.css"]\n}\n',
            selected: '{"enabledThemes":["other.css", "vgs.css"],"owner":true}\n',
            other: '{"enabledThemes":["other.css"],"owner":true}\n' })),
        { name: "zen", base: home, roots: [".zen/p0", ".zen/p1"], settings: "user.js",
            selected: 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);\n',
            other: 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", false);\n' }
    ];
    for (const name of ["bin", "shell/Commons", ...configurations.map(row => "themes/targets/" + row.name)])
        fs.cpSync(path.join(setupRepo, name), path.join(tree, name), { recursive: true });
    fs.mkdirSync(path.join(state, "theme"), { recursive: true });
    const targets = new Map(configurations.map(row => [row.name,
        JSON.parse(fs.readFileSync(path.join(tree, "themes/targets", row.name, "target.json"), "utf8"))]));
    fs.mkdirSync(path.join(config, "obsidian"), { recursive: true });
    fs.writeFileSync(path.join(config, "obsidian/obsidian.json"), JSON.stringify({ vaults: Object.fromEntries(
        configurations.find(row => row.name === "obsidian").roots.map(root => [root, { path: path.join(home, "vaults", root) }])) }));
    function declaredEntries(row, root, index) {
        const target = targets.get(row.name);
        if (render.wiringForm(target.wiring) === "include") return [{ kind: "include", file: path.join(row.base, root, target.wiring.file), line: render.wiringLine(target, path.join(state, "theme")) }];
        const wiringBase = target.wiring.base === "account" || target.wiring.vaults !== undefined ? path.join(row.base, root)
            : { home, config }[target.wiring.base];
        const wiringDir = Array.isArray(target.wiring.dir) ? target.wiring.dir[index] : target.wiring.dir;
        return render.entryItems(target, path.join(state, "theme"), index).map(item => ({ ...item,
            file: path.join(wiringBase, wiringDir, item.name) }));
    }
    for (const row of configurations) {
        for (const [index, root] of [...new Set([...row.roots, ...(row.nested ?? [])])].entries()) {
            for (const item of declaredEntries(row, root, index)) {
                fs.mkdirSync(path.dirname(item.file), { recursive: true });
                if (item.kind === "include") { fs.writeFileSync(item.file, item.line + "\n"); continue; }
                fs.writeFileSync(item.to, item.destination === targets.get(row.name).select.source ? row.sourceText : "managed theme\n");
                if (item.kind === "copy") fs.copyFileSync(item.to, item.file);
                else fs.symlinkSync(item.to, item.file);
            }
        }
    }
    fs.writeFileSync(path.join(home, ".zen/profiles.ini"), '[Profile0]\nPath=p0\nIsRelative=1\n[Profile1]\nPath=p1\nIsRelative=1\n');
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
                        fs.mkdirSync(path.dirname(file), { recursive: true });
                        if (connected[index] === "unreadable") fs.mkdirSync(file);
                        else if (connected[index] === "missing") { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, row.missing ?? ""); }
                        else if (connected[index] !== null) { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, connected[index] ? row.selected : row.other); }
                        const unknownValues = row.values && applied !== "valid";
                        if (unknownValues || connected[index] === true)
                            for (const entry of declaredEntries(row, root, index).filter(item => entryFiles(row, root, index).includes(item.file))) expected.push([entry.file, entry.line ?? null, "wired", null]);
                        if (!unknownValues && connected[index] === true)
                            for (const line of targets.get(row.name).select.values !== undefined ? [null] : render.selectKeys(targets.get(row.name)).map(key =>
                                key.join(".") + " = " + render.selectValue(targets.get(row.name), path.join(state, "theme")))) expected.push([file, line, "wired", null]);
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
    const kde = configurations.find(row => row.name === "kcolorscheme");
    const kdeSettings = path.join(kde.base, kde.settings);
    const kdeSource = path.join(state, "theme", targets.get(kde.name).select.source);
    fs.rmSync(kdeSettings, { recursive: true, force: true });
    fs.writeFileSync(kdeSettings, kde.selected);
    for (const replacement of [undefined, '[Colors:View]\nBackgroundNormal=#ffffff\n']) {
        fs.rmSync(kdeSource);
        if (replacement !== undefined) fs.writeFileSync(kdeSource, replacement);
        assert.deepEqual(readWiring(kde.name), [], "KDE setup needs the actual generated colour groups");
        fs.writeFileSync(kdeSource, kde.sourceText);
    }
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
        ["root.length > nearest.root.length", "selection.connected"],
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
    // Drive the actual apply owner using shipped selectors. Hooks are disabled
    // in this disposable tree so the test cannot contact a running application.
    const native = configurations.filter(row => ["qtct", "json-array", "userjs", "kcolorscheme"].includes(targets.get(row.name).select.format));
    const commands = path.join(scratch, "commands");
    const noCommands = path.join(scratch, "no-commands");
    fs.mkdirSync(commands);
    fs.mkdirSync(noCommands);
    for (const row of configurations.filter(row => !native.includes(row))) fs.rmSync(path.join(tree, "themes/targets", row.name), { recursive: true });
    for (const row of native) {
        const target = targets.get(row.name);
        fs.writeFileSync(path.join(tree, "themes/targets", row.name, "target.json"), JSON.stringify({ ...target, reload: null }));
        for (const command of target.detect) fs.writeFileSync(path.join(commands, command), '#!/bin/sh\nexit 99\n', { mode: 0o755 });
    }
    for (const name of ["shell/Core", "config", "themes/vgs"]) fs.cpSync(path.join(setupRepo, name), path.join(tree, name), { recursive: true });
    const light = JSON.parse(fs.readFileSync(path.join(setupRepo, "themes/catalog/flexoki-light/theme.json"), "utf8"));
    delete light.backgrounds;
    fs.mkdirSync(path.join(tree, "themes/flexoki-light"));
    fs.writeFileSync(path.join(tree, "themes/flexoki-light/theme.json"), JSON.stringify(light));
    fs.copyFileSync(path.join(setupRepo, "themes/catalog/flexoki-light/terminal.json"), path.join(tree, "themes/flexoki-light/terminal.json"));
    fs.mkdirSync(path.join(tree, "themes/flexoki-light/targets"));
    fs.writeFileSync(path.join(tree, "themes/flexoki-light/targets", targets.get(kde.name).select.source), kde.curatedSource);
    function verifyApply(only, absent = false, detected = true, kdeSelected = false) {
        const selectors = [];
        for (const row of native) for (const root of row.roots) {
            const file = path.join(row.base, root, row.settings);
            fs.rmSync(file, { recursive: true, force: true });
            fs.mkdirSync(path.dirname(file), { recursive: true });
            // Mozilla does not create user.js. Cover both an existing file and
            // an absent file in independent profiles, without creating a profile.
            if (!absent && (row.name !== "zen" || root === row.roots[0])) fs.writeFileSync(file,
                row.sourceText !== undefined ? (kdeSelected ? row.kept : row.kept.replace('ColorScheme=Vgs', 'ColorScheme=Other')) + row.localColors : row.other);
            selectors.push({ row, file });
        }
        let stable;
        let generated;
        let previousFiles;
        function homeFiles(dir = home) {
            return fs.readdirSync(dir).sort().flatMap(name => {
                const file = path.join(dir, name);
                const stat = fs.lstatSync(file);
                return stat.isDirectory() ? homeFiles(file) : [[path.relative(home, file),
                    stat.isSymbolicLink() ? { link: fs.readlinkSync(file) } : fs.readFileSync(file).toString("hex")]];
            });
        }
        for (const theme of ["vgs", "flexoki-light", "flexoki-light"]) {
            const result = spawnSync(process.execPath, [judge, "apply", "json", path.join(config, "vgshell"), state, "held", theme], { env: { ...env, PATH: detected ? commands : noCommands }, encoding: "utf8", timeout: 30000 });
            assert.equal(result.status, 0, result.stderr);
            const bytes = [];
            for (const { row, file } of selectors) {
                const text = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : undefined;
                let expected = !detected ? undefined : absent ? row.emptySelected ?? row.selected : row.selected;
                if (detected && row.sourceText !== undefined) {
                    const source = fs.readFileSync(path.join(state, "theme", targets.get(row.name).select.source), "utf8");
                    if (theme === "flexoki-light") assert.equal(source, row.curatedSource, "curated KDE bytes retain their missing final newline");
                    // Compare native groups with the generated artifact. The
                    // curated scheme ends at EOF; the shipped one ends at WM.
                    const groups = source.match(/^\[(?:Colors|ColorEffects):[\s\S]*/m)?.[0].split(/^\[WM\]/m)[0];
                    assert.match(groups ?? "", /^\[Colors:View\]/m);
                    expected = groups.split(/\r?\n/).filter(line => line.trim() !== "" && !/^\s*[#;]/.test(line)).join(absent ? "\n" : "\r\n")
                        + (absent ? "\n" + row.emptySelected : "\r\n" + row.kept);
                }
                if (only === undefined || row.name === only) assert.equal(text, expected, row.name + ": apply selects native theme");
                if (row.sourceText === undefined) bytes.push(text);
            }
            if (stable) assert.deepEqual(bytes, stable, "theme switches and repeated applies keep every user selector byte-identical");
            stable = bytes;
            if (!detected) {
                for (const target of JSON.parse(result.stdout).targets) assert.deepEqual([target.state, target.reason], ["skipped", "not-detected"]);
                continue;
            }
            const palette = fs.readFileSync(path.join(state, "theme/qt5ct.conf"), "utf8");
            if (generated !== undefined && theme === "flexoki-light") assert.notEqual(palette, generated, "generated Qt colours change with the theme");
            generated = theme === "vgs" ? palette : undefined;
            const files = homeFiles();
            if (theme === "flexoki-light" && previousFiles !== undefined) assert.deepEqual(files, previousFiles,
                "repeated apply leaves every file and link in the temporary HOME unchanged");
            previousFiles = theme === "flexoki-light" ? files : undefined;
        }
    }
    verifyApply(undefined, true, false);
    verifyApply(undefined, true);
    verifyApply();
    verifyApply("kcolorscheme", false, true, true);
    for (const row of native) {
        const file = path.join(tree, "themes/targets", row.name, "target.json");
        const original = fs.readFileSync(file, "utf8");
        const mutant = JSON.parse(original);
        delete mutant.select;
        const replacement = JSON.stringify(mutant);
        assert.notEqual(replacement, original);
        fs.writeFileSync(file, replacement);
        assert.throws(() => verifyApply(row.name), { name: "AssertionError", message: new RegExp("^" + row.name + ": apply selects native theme") });
        fs.writeFileSync(file, original);
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
    ["wiring unreadable rows look present", 'value: row.state === "wired" ? "present" : row.state === "not-wired" ? "absent" : "unavailable"', 'value: "present"'],
    ["wiring file link removed", "Commons.PageReference.fileReference(truncated(hint, HINT_MAX), row.file)", "truncated(hint, HINT_MAX)"],
    ["wiring rows are not capped", 'if (items.length > STATUS_LIST_MAX) {', 'if (false) {']
];
const source = fs.readFileSync(file, "utf8");
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "themes-setup-control-"));
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
