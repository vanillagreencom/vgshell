#!/usr/bin/env node
// Controls for scripts/check-theme-contrast.js. Each row builds a themes
// directory below the repository tmp/ tree and asserts the check reports the
// producer-facing line that a theme author acts on.
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const repo = path.join(__dirname, "..");
const CHECK = path.join(repo, "scripts", "check-theme-contrast.js");
const NODE = process.execPath;
const DEFAULT_PALETTE = {
    background: "#000000",
    foreground: "#d7d7d9",
    accent: "#ff5a36",
    success: "#b4c96f",
    warning: "#ffb000",
    danger: "#f43f5e",
    info: "#74a7f7"
};

function rmTree(dir) {
    fs.rmSync(dir, { recursive: true, force: true });
}

function env(root) {
    const tmp = path.join(root, "tmp");
    fs.mkdirSync(tmp, { recursive: true });
    return { PATH: process.env.PATH || "", HOME: path.join(root, "home"), TMPDIR: tmp, LC_ALL: "C" };
}

function run(root, themesDir) {
    return spawnSync(NODE, [CHECK, themesDir], { encoding: "utf8", env: env(path.join(path.dirname(root), path.basename(root) + "-env")) });
}

function writeTheme(dir, name, tokens) {
    const packageDir = path.join(dir, name);
    fs.mkdirSync(packageDir, { recursive: true });
    fs.writeFileSync(path.join(packageDir, "theme.json"), JSON.stringify({ schemaVersion: 1, name, tokens }, null, 2) + "\n");
}

function writeCatalogTheme(dir, name, tokens) {
    writeTheme(path.join(dir, "catalog"), name, tokens);
    fs.writeFileSync(path.join(dir, "catalog", "index.json"), JSON.stringify({
        schemaVersion: 1,
        entries: [{
            name,
            mode: "dark",
            palette: DEFAULT_PALETTE,
            imagery: null
        }]
    }, null, 2) + "\n");
}

// Sixteen readable terminal slots on the default black background, with
// OVERRIDES on top.
function writeTerminal(dir, name, overrides) {
    const slots = {};
    for (let i = 0; i < 16; i++) slots[`color${i}`] = "#d7d7d9";
    fs.writeFileSync(path.join(dir, name, "terminal.json"), JSON.stringify({ schemaVersion: 1, slots: Object.assign(slots, overrides) }, null, 2) + "\n");
}

// Each terminal slot set to the background's own colour: the slot's line
// when the check judges it as text, null when the slot also fills or dims.
const TERMINAL_SLOT_ROWS = [
    ["color0", null],
    ["color1", "terminal.color1"],
    ["color2", "terminal.color2"],
    ["color3", "terminal.color3"],
    ["color4", "terminal.color4"],
    ["color5", "terminal.color5"],
    ["color6", "terminal.color6"],
    ["color7", null],
    ["color8", null],
    ["color9", "terminal.color9"],
    ["color10", "terminal.color10"],
    ["color11", "terminal.color11"],
    ["color12", "terminal.color12"],
    ["color13", "terminal.color13"],
    ["color14", "terminal.color14"],
    ["color15", null]
];

// The check and every file it loads, copied to COPY, where a control
// plants its defect.
function copyCheck(copy) {
    for (const file of ["scripts/check-theme-contrast.js", "bin/lib/qml-library.js", "shell/Commons/ThemeLogic.js",
        "shell/Commons/Tokens.js", "shell/Commons/Glass.js", "shell/plugins/vgs.notifications/Appearance.js"]) {
        fs.mkdirSync(path.dirname(path.join(copy, file)), { recursive: true });
        fs.copyFileSync(path.join(repo, file), path.join(copy, file));
    }
}

// Replace each [needle, replacement] in FILE, each needle found once.
function plant(file, edits) {
    let source = fs.readFileSync(file, "utf8");
    for (const [needle, replacement] of edits) {
        assert.equal(source.split(needle).length, 2, `the planted text ${JSON.stringify(needle)} matches once`);
        source = source.replace(needle, () => replacement);
    }
    fs.writeFileSync(file, source);
}

function assertStatus(proc, status) {
    assert.equal(proc.status, status, proc.stdout + proc.stderr);
}

fs.mkdirSync(path.join(repo, "tmp"), { recursive: true });
const root = fs.mkdtempSync(path.join(repo, "tmp", "test-check-theme-contrast-"));
let failures = 0;
function row(name, fn) {
    try {
        fn(path.join(root, name.replace(/[^A-Za-z0-9_.-]/g, "-")));
        console.log(`  ok    ${name}`);
    } catch (e) {
        failures += 1;
        console.error(`  FAIL  ${name}`);
        console.error(String(e.stack || e).split("\n").map(line => `        ${line}`).join("\n"));
    }
}

try {
    row("shipped tree passes", dir => {
        const proc = run(dir, path.join(repo, "themes"));
        assertStatus(proc, 0);
        assert.match(proc.stdout, /ok       vgs/);
        assert.match(proc.stdout, /ok       catalog\//);
    });

    // The notice link as e5d112688 drew it, the theme's accent alone, in a
    // disposable copy of the check and the files it loads, judged on the
    // shipped tree: the default's accent on its dark card over white and
    // a light theme's on its light card over black fall short.
    row("control: a notice link in the accent alone is a shortfall", dir => {
        const copy = path.join(dir, "copy");
        copyCheck(copy);
        const look = path.join(copy, "shell", "plugins", "vgs.notifications", "Appearance.js");
        const source = fs.readFileSync(look, "utf8");
        const link = /link: color\("readable\(.*\)"\),/g;
        assert.equal((source.match(link) || []).length, 1, "the planted link matches once");
        fs.writeFileSync(look, source.replace(link, 'link: color("{palette.accent}"),'));
        const proc = spawnSync(NODE, [path.join(copy, "scripts", "check-theme-contrast.js"), path.join(repo, "themes")],
            { encoding: "utf8", env: env(path.join(dir, "env")) });
        assertStatus(proc, 1);
        assert.match(proc.stdout, /^short    vgs: notifications\.text\.link on notifications\.card\.fill over #ffffff ratio=3\.35 floor=4\.5$/m);
        assert.match(proc.stdout, /^short    catalog\/flexoki-light: notifications\.text\.link on notifications\.card\.fill over #000000 ratio=4\.15 floor=4\.5$/m);
    });

    // The failure line on the scrim alone, as VGS-1611 judged it, in a
    // disposable copy of the check and the files it loads, judged on the
    // shipped tree: a light theme's danger, which reads on its plate,
    // falls short on the scrim over a black wallpaper.
    row("control: a failure line judged on the scrim is a shortfall", dir => {
        const copy = path.join(dir, "copy");
        copyCheck(copy);
        plant(path.join(copy, "shell", "Commons", "ThemeLogic.js"), [
            ['var RAIL_TEXT_ROLES = ["carousel.hint", "carousel.hintActive"];', 'var RAIL_TEXT_ROLES = ["carousel.hint", "carousel.hintActive", "carousel.hintDanger"];'],
            ["    pairs.push([FAILURE_LINE, FAILURE_PLATE, READABILITY_FLOOR]);\n", ""]
        ]);
        const proc = spawnSync(NODE, [path.join(copy, "scripts", "check-theme-contrast.js"), path.join(repo, "themes")],
            { encoding: "utf8", env: env(path.join(dir, "env")) });
        assertStatus(proc, 1);
        assert.match(proc.stdout, /^short    catalog\/catppuccin-latte: carousel\.hintDanger on color\.scrim over #000000 ratio=1\.41 floor=4\.5$/m);
        assert.match(proc.stdout, /^short    catalog\/white: carousel\.hintDanger on color\.scrim over #000000 ratio=3\.65 floor=4\.5$/m);
    });

    // The tooltip's text as it drew before VGS-1628, the theme's text and
    // faint text, in a disposable copy judged on the shipped tree: on the
    // fill its glass draws solid, the faint detail line and one theme's
    // title fall short. The same text judged on the opaque raised surface
    // alone, with the solid glass pair taken out, misses both.
    row("control: tooltip text judged on the solid glass fill is a shortfall the opaque pair misses", dir => {
        const copy = path.join(dir, "copy");
        copyCheck(copy);
        plant(path.join(copy, "shell", "Commons", "Tokens.js"), [
            ['foreground: color("readable({color.text}, {tooltip.glass}, contrast({tooltip.glass}))"),', 'foreground: color("{color.text}"),'],
            ['detail: color("readable({color.textFaint}, {tooltip.glass}, readable({color.textMuted}, {tooltip.glass}, {tooltip.foreground}))")', 'detail: color("{color.textFaint}")']
        ]);
        const judge = () => spawnSync(NODE, [path.join(copy, "scripts", "check-theme-contrast.js"), path.join(repo, "themes")],
            { encoding: "utf8", env: env(path.join(dir, "env")) });
        const drawn = judge();
        assertStatus(drawn, 1);
        assert.match(drawn.stdout, /^short    vgs: tooltip\.detail on glass\.fill solid ratio=4\.20 floor=4\.5$/m);
        assert.match(drawn.stdout, /^short    catalog\/moon-orbit: tooltip\.foreground on glass\.fill solid ratio=3\.96 floor=4\.5$/m);
        plant(path.join(copy, "shell", "Commons", "ThemeLogic.js"), [
            ["        pairs.push([TOOLTIP_TEXT_ROLES[t], GLASS_SOLID, READABILITY_FLOOR]);\n", ""]
        ]);
        const opaque = judge();
        assertStatus(opaque, 0);
        assert.doesNotMatch(opaque.stdout, /tooltip\./);
    });

    row("direct package shortfall exits one", dir => {
        fs.mkdirSync(dir, { recursive: true });
        writeTheme(dir, "faint", { color: { textFaint: "#111111" } });
        const proc = run(dir, dir);
        assertStatus(proc, 1);
        assert.match(proc.stdout, /short    faint: color\.textFaint on color\.background ratio=1\.10 floor=4\.5/);
    });

    row("catalog package shortfall is named with catalog prefix", dir => {
        fs.mkdirSync(dir, { recursive: true });
        writeCatalogTheme(dir, "faint", { color: { textFaint: "#111111" } });
        const proc = run(dir, dir);
        assertStatus(proc, 1);
        assert.match(proc.stdout, /short    catalog\/faint: color\.textFaint on color\.background ratio=1\.10 floor=4\.5/);
    });

    row("accent matching background is a shortfall", dir => {
        fs.mkdirSync(dir, { recursive: true });
        writeTheme(dir, "arcish", { palette: { background: "#0c060d", foreground: "#d7d7d9", accent: "#0c060d" } });
        const proc = run(dir, dir);
        assertStatus(proc, 1);
        assert.match(proc.stdout, /short    arcish: color\.accent on color\.background ratio=1\.00 floor=4\.5/);
    });

    row("translucent text is a shortfall", dir => {
        fs.mkdirSync(dir, { recursive: true });
        writeTheme(dir, "translucent", { color: { textFaint: "alpha({palette.foreground}, 0.5)" } });
        const proc = run(dir, dir);
        assertStatus(proc, 1);
        assert.match(proc.stdout, /short    translucent: color\.textFaint on color\.background ratio=translucent floor=4\.5/);
    });

    row("muted text weaker than faint text breaks the hierarchy", dir => {
        fs.mkdirSync(dir, { recursive: true });
        writeCatalogTheme(dir, "inverted", { color: { textMuted: "#a0a0a0", textFaint: "#d0d0d0" } });
        const proc = run(dir, dir);
        assertStatus(proc, 1);
        assert.match(proc.stdout, /^order    catalog\/inverted: color\.textMuted ratio=8\.\d\d below color\.textFaint ratio=13\.\d\d$/m);
        assert.doesNotMatch(proc.stdout, /^short /m);
    });

    row("a heading weaker than body text breaks the hierarchy", dir => {
        fs.mkdirSync(dir, { recursive: true });
        writeTheme(dir, "flat", { color: { textHeading: "#b0b0b0" } });
        const proc = run(dir, dir);
        assertStatus(proc, 1);
        assert.match(proc.stdout, /^order    flat: color\.textHeading ratio=\d+\.\d\d below color\.text ratio=\d+\.\d\d$/m);
        assert.doesNotMatch(proc.stdout, /^short /m);
    });

    row("equal muted and faint text keeps the hierarchy", dir => {
        fs.mkdirSync(dir, { recursive: true });
        writeTheme(dir, "even", { color: { textMuted: "#d0d0d0", textFaint: "#d0d0d0" } });
        const proc = run(dir, dir);
        assertStatus(proc, 0);
        assert.match(proc.stdout, /^ok       even$/m);
    });

    for (const [slot, text] of TERMINAL_SLOT_ROWS) {
        row(`catalog terminal ${slot} on its background`, dir => {
            fs.mkdirSync(dir, { recursive: true });
            writeCatalogTheme(dir, "term", {});
            writeTerminal(path.join(dir, "catalog"), "term", { [slot]: DEFAULT_PALETTE.background });
            const proc = run(dir, dir);
            if (text === null) {
                assertStatus(proc, 0);
                assert.match(proc.stdout, /^ok       catalog\/term$/m);
            } else {
                assertStatus(proc, 1);
                assert.match(proc.stdout, new RegExp(`^short    catalog/term: ${text.replace(".", "\\.")} on palette\\.background ratio=1\\.00 floor=4\\.5$`, "m"));
            }
        });
    }

    row("a direct package's terminal slot below the floor is a shortfall", dir => {
        fs.mkdirSync(dir, { recursive: true });
        writeTheme(dir, "dim", {});
        writeTerminal(dir, "dim", { color2: "#4c4c4c" });
        const proc = run(dir, dir);
        assertStatus(proc, 1);
        assert.match(proc.stdout, /^short    dim: terminal\.color2 on palette\.background ratio=2\.\d\d floor=4\.5$/m);
    });

    row("a refused terminal.json exits one", dir => {
        fs.mkdirSync(dir, { recursive: true });
        writeTheme(dir, "bad", {});
        writeTerminal(dir, "bad", { color3: "red" });
        const proc = run(dir, dir);
        assertStatus(proc, 1);
        assert.match(proc.stdout, /^refused  bad: .*terminal-colour/m);
    });

    row("refused document exits one", dir => {
        fs.mkdirSync(path.join(dir, "bad"), { recursive: true });
        fs.writeFileSync(path.join(dir, "bad", "theme.json"), JSON.stringify({ schemaVersion: 2, name: "bad", tokens: {} }) + "\n");
        const proc = run(dir, dir);
        assertStatus(proc, 1);
        assert.match(proc.stdout, /refused  bad: theme: refused: document reason=schema-version/);
    });

    row("unreadable themes dir exits two", dir => {
        const proc = run(dir, path.join(dir, "missing"));
        assertStatus(proc, 2);
        assert.match(proc.stderr, /check-theme-contrast: unreadable: path=.*missing error=ENOENT/);
    });
} finally {
    rmTree(root);
}

if (failures > 0) process.exit(1);
console.log("test-check-theme-contrast: ok");
