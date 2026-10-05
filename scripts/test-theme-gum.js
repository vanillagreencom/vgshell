#!/usr/bin/env node
// The shipped gum target, themes/targets/gum, against the one reader of the
// file it writes: bin/vgshell-tui present, which parses gum.env and never
// sources it. The target renders under the shipped vgs package and the
// catalog's flexoki-light, a light package; present must export every line
// of each render and warn nothing. The expected colours are pinned literals
// written from each package's theme.json; flexoki-light's success, warning
// and danger are mixes its theme.json states, resolved once under node with
// ThemeLogic.accept.
//
// The control renders a copy of the template whose last value is a `$(...)`
// command and requires the same check to fail on it, with nothing run.
"use strict";
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");
const render = require("../bin/lib/theme-render.js");

const repo = path.join(__dirname, "..");
const logic = load(path.join(repo, "shell", "Commons", "ThemeLogic.js"));
const TOKENS = load(path.join(repo, "shell", "Commons", "Tokens.js")).TOKENS;
const targetDir = path.join(repo, "themes", "targets", "gum");
const presenter = path.join(repo, "bin", "vgshell-tui");

// The package in DIR, a directory under themes/, judged as shipped when
// SHIPPED holds and as the installed package a catalog entry becomes
// otherwise.
const themePackage = (dir, shipped) => {
    const pkg = logic.acceptPackage(TOKENS, {
        directoryName: path.basename(dir),
        themeJson: fs.readFileSync(path.join(repo, "themes", dir, "theme.json"), "utf8"),
        terminalJson: fs.readFileSync(path.join(repo, "themes", dir, "terminal.json"), "utf8"),
        shipped
    });
    assert.equal(pkg.ok, true, pkg.ok ? "" : logic.refusalLine(pkg));
    return pkg;
};
const defaults = themePackage("vgs", true);

const judged = render.acceptTarget(logic, "gum", fs.readFileSync(path.join(targetDir, "target.json"), "utf8"));
assert.equal(judged.ok, true, judged.ok ? "" : render.refusalLine("gum", judged));
const target = judged.target;
assert.deepEqual(target.files.map(f => f.destination), ["gum.env"]);
const template = fs.readFileSync(path.join(targetDir, "gum.env"), "utf8");

const rendered = (pkg, text) => {
    const result = render.renderTarget(logic, TOKENS, target, new Map([["gum.env", text]]),
        { values: pkg.values, slots: render.terminalSource(pkg, defaults).terminal, curated: new Map(), installed: false });
    assert.equal(result.ok, true, result.ok ? "" : render.refusalLine("gum", result));
    return result.files[0].bytes.toString("utf8");
};

// Runs present on TEXT as the state directory's gum.env and returns what the
// command it ran saw. Throws unless present exported every line of TEXT
// whole and printed nothing on stderr. The child gets its own HOME, state
// and runtime directories, never the developer's.
const presented = (root, text) => {
    const state = path.join(root, "state");
    fs.mkdirSync(path.join(state, "vgshell", "theme"), { recursive: true });
    fs.writeFileSync(path.join(state, "vgshell", "theme", "gum.env"), text);
    const run = spawnSync(presenter, ["present", "--presentation", "plain", "--", "env"], {
        encoding: "utf8",
        env: { PATH: process.env.PATH, HOME: root, XDG_STATE_HOME: state, XDG_RUNTIME_DIR: root }
    });
    assert.equal(run.error, undefined, String(run.error));
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.stderr, "", `present warned: ${run.stderr}`);
    const seen = new Set(run.stdout.split("\n"));
    const lines = text.split("\n");
    assert.equal(lines.pop(), "", "gum.env ends in a newline");
    for (const line of lines) assert.ok(seen.has(line), `present did not export ${line}`);
    return seen;
};

// Hand-written from themes/<dir>/theme.json: a line each for the base
// colours, and the library's four.
const EXPECTED = [
    ["vgs", true, ["FOREGROUND=#d7d7d9", "BACKGROUND=#000000", "GUM_CHOOSE_CURSOR_FOREGROUND=#ff5a36",
        "VGS_TUI_ACCENT=#ff5a36", "VGS_TUI_SUCCESS=#b4c96f", "VGS_TUI_WARNING=#ffb000", "VGS_TUI_DANGER=#f43f5e"]],
    ["catalog/flexoki-light", false, ["FOREGROUND=#100f0f", "BACKGROUND=#fffcf0", "GUM_CHOOSE_CURSOR_FOREGROUND=#205ea6",
        "VGS_TUI_ACCENT=#205ea6", "VGS_TUI_SUCCESS=#616f29", "VGS_TUI_WARNING=#83660d", "VGS_TUI_DANGER=#b64339"]]
];

const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "theme-gum-")));
try {
    let lines = 0;
    for (const [dir, shipped, expected] of EXPECTED) {
        const name = path.basename(dir);
        const text = rendered(themePackage(dir, shipped), template);
        const seen = presented(path.join(root, name), text);
        for (const line of expected) assert.ok(seen.has(line), `${name}: present did not export ${line}`);
        lines = text.split("\n").length - 1;
    }

    // Control: a `$(...)` value fails the check and runs nothing.
    const planted = path.join(root, "planted");
    const bad = rendered(defaults, template + `GUM_SPIN_TITLE_FOREGROUND=$(touch ${planted})\n`);
    assert.throws(() => presented(path.join(root, "control"), bad), new RegExp(`gum-env=rejected line=${template.split("\n").length} `),
        "control: the check passed a gum.env line holding $(...)");
    assert.equal(fs.existsSync(planted), false, "control: present ran the planted line");

    console.log(`test-theme-gum: ok packages=${EXPECTED.length} lines=${lines} controls=1`);
} finally {
    fs.rmSync(root, { recursive: true, force: true });
}
