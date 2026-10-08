#!/usr/bin/env node
// The shipped gum target, themes/targets/gum, against the one reader of the
// file it writes: bin/vgshell-tui present, which parses gum.env and never
// sources it. The target renders under the shipped vgs package and the
// catalog's flexoki-light, a light package; present must export every line
// of each render and warn nothing. The expected colours are pinned literals
// written from each package's theme.json; flexoki-light's success, warning
// and danger are mixes its theme.json states, resolved once under node with
// ThemeLogic.accept. With no gum.env, as before any theme apply, present
// must export `vgshell-theme-judge gum-default`'s environment: every
// background key of the template and the three base colours present and
// empty, so gum keeps the terminal's own, the selection foregrounds the
// pinned vgs accent with their styles bold and no other style bold, and a
// header foreground empty.
//
// With no gum.env and a judge that fails, or one that prints a line the
// rule rejects, present warns with its keyed line, exports no colour and
// still runs the command with its exit code; those judges are stand-ins in
// copies of the tree.
//
// The controls: a copy of the template whose last value is a `$(...)`
// command must fail the check, with nothing run; a copy of the presenter
// without its no-gum.env branch, a stand-in judge that hands back the full
// vgs render, and one that hands back the no-theme environment without its
// bold lines, must each fail the absent row. The judge's verb must
// refuse a gum target with two files, planted in a copy of the themes
// directory beside a copy of the judge.
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
const judge = path.join(repo, "bin", "vgshell-theme-judge");

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

// node first on PATH: a version-manager shim there may read the
// developer's own configuration, and present runs node for the judge.
const childPath = path.dirname(process.execPath) + path.delimiter + process.env.PATH;

// Runs present, BIN, on TEXT as the state directory's gum.env, or with
// none for null, and answers the run of ARGV. The child gets its own HOME,
// state and runtime directories, never the developer's.
const present = (root, text, bin, argv) => {
    const state = path.join(root, "state");
    fs.mkdirSync(path.join(state, "vgshell", "theme"), { recursive: true });
    if (text !== null) fs.writeFileSync(path.join(state, "vgshell", "theme", "gum.env"), text);
    const run = spawnSync(bin, ["present", "--presentation", "plain", "--", ...argv], {
        encoding: "utf8",
        env: { PATH: childPath, HOME: root, XDG_STATE_HOME: state, XDG_RUNTIME_DIR: root }
    });
    assert.equal(run.error, undefined, String(run.error));
    return run;
};

// present, BIN by default, running `env`: what the command saw. Throws
// unless present exported every line of TEXT whole and printed nothing on
// stderr.
const presented = (root, text, bin = presenter) => {
    const run = present(root, text, bin, ["env"]);
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.stderr, "", `present warned: ${run.stderr}`);
    const seen = new Set(run.stdout.split("\n"));
    if (text === null) return seen;
    const lines = text.split("\n");
    assert.equal(lines.pop(), "", "gum.env ends in a newline");
    for (const line of lines) assert.ok(seen.has(line), `present did not export ${line}`);
    return seen;
};

// The vgs accent, from themes/vgs/theme.json, and the selection
// foregrounds that take it with no theme applied.
const VGS_ACCENT = "#ff5a36";
const SELECTION = ["GUM_CHOOSE_CURSOR_FOREGROUND", "GUM_CONFIRM_SELECTED_FOREGROUND", "GUM_INPUT_PROMPT_FOREGROUND"];
// The selection styles drawn bold with no theme applied: each a style gum
// 2.0.2 reads, since gum refuses a <stem>_BOLD value it cannot parse
// (`--cursor.bold: bool value must be ...`), checked on 2026-10-07.
const BOLD_STEMS = ["GUM_CONFIRM_PROMPT", "GUM_CONFIRM_SELECTED", "GUM_INPUT_PROMPT", "GUM_CHOOSE_CURSOR",
    "GUM_CHOOSE_SELECTED", "GUM_FILTER_PROMPT", "GUM_FILTER_MATCH", "GUM_FILTER_INDICATOR", "GUM_FILTER_SELECTED_PREFIX",
    "GUM_TABLE_SELECTED", "GUM_SPIN_SPINNER", "GUM_FILE_SELECTED", "GUM_PAGER_MATCH", "GUM_PAGER_MATCH_HIGH", "GUM_LOG_LEVEL"];

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

    // No gum.env: the judge's no-theme environment, as present exports it.
    const templateKeys = template.split("\n").filter(line => line !== "").map(line => line.slice(0, line.indexOf("=")));
    const emptied = [...templateKeys.filter(key => key.endsWith("BACKGROUND")), "FOREGROUND", "BORDER_FOREGROUND"];
    const absent = bin => {
        const run = present(path.join(root, "absent-" + path.basename(path.dirname(path.dirname(bin)))), null, bin, ["env"]);
        assert.equal(run.status, 0, run.stderr);
        assert.equal(run.stderr, "", `present warned: ${run.stderr}`);
        const env = new Map(run.stdout.split("\n").filter(line => line.includes("=")).map(line => [line.slice(0, line.indexOf("=")), line.slice(line.indexOf("=") + 1)]));
        for (const key of emptied) assert.equal(env.get(key), "", `no gum.env: ${key} is ${env.get(key)}, not empty`);
        for (const key of SELECTION) assert.equal(env.get(key), VGS_ACCENT, `no gum.env: ${key} is ${env.get(key)}, not the accent`);
        assert.equal(env.get("GUM_CHOOSE_HEADER_FOREGROUND"), "", "no gum.env: the choose header has a colour");
        const bolds = [...env].filter(([key]) => key.endsWith("_BOLD")).map(([key, value]) => key + "=" + value).sort();
        assert.deepEqual(bolds, BOLD_STEMS.map(stem => stem + "_BOLD=true").sort(), "no gum.env: the bold keys");
    };
    absent(presenter);

    // A tree of BIN's copies: the presenter, given by its text, bin/lib
    // linked, and a judge, a copy or a stand-in's text.
    const presenterTree = (name, presenterText, judgeText) => {
        const bin = path.join(root, name, "bin");
        fs.mkdirSync(bin, { recursive: true });
        fs.symlinkSync(path.join(repo, "bin", "lib"), path.join(bin, "lib"));
        fs.writeFileSync(path.join(bin, "vgshell-tui"), presenterText, { mode: 0o755 });
        fs.writeFileSync(path.join(bin, "vgshell-theme-judge"), judgeText);
        return path.join(bin, "vgshell-tui");
    };
    const presenterText = fs.readFileSync(presenter, "utf8");

    // Control: present without its no-gum.env branch fails the absent row.
    const needle = `  text="$(node "$root/bin/vgshell-theme-judge" gum-default 2>/dev/null)" || status=$?`;
    assert.equal(presenterText.split(needle).length, 2, "control: the no-gum.env branch occurs once");
    const unthemed = presenterTree("unthemed", presenterText.replace(needle, "  return 0"), "process.exit(9);\n");
    assert.throws(() => absent(unthemed), /no gum\.env: \S+ is undefined, not empty/,
        "control: present without its no-gum.env branch passed the absent row");

    // Control: a judge that hands back the full vgs render fails the absent
    // row at its backgrounds.
    const full = presenterTree("full", presenterText, `process.stdout.write(${JSON.stringify(rendered(defaults, template))});\n`);
    assert.throws(() => absent(full), /no gum\.env: \S*BACKGROUND is #[0-9a-f]{6}, not empty/,
        "control: the full vgs render passed the absent row");

    // Control: a judge whose environment has no bold line fails the absent
    // row at its bold keys.
    const judged = spawnSync(process.execPath, [judge, "gum-default"], { encoding: "utf8", env: { PATH: childPath, HOME: root } });
    assert.equal(judged.status, 0, judged.stderr);
    const unbold = judged.stdout.split("\n").filter(line => !/^[^=]*_BOLD=/.test(line)).join("\n");
    assert.notEqual(unbold, judged.stdout);
    const plain = presenterTree("unbold", presenterText, `process.stdout.write(${JSON.stringify(unbold)});\n`);
    assert.throws(() => absent(plain), /no gum\.env: the bold keys/, "control: a no-theme environment without bold passed the absent row");

    // A judge that fails, or prints a line the rule rejects: the keyed
    // warning, no colour, and the command's own exit code. Each tree holds a
    // copy of the presenter, bin/lib linked, and a stand-in judge.
    const judgeRows = [
        ["failing", "process.exit(3);\n", "vgshell-tui: gum-env=default-unavailable exit=3"],
        ["rejected", "process.stdout.write(\"FOREGROUND=#000000\\nPATH=#000000\\n\");\n", "vgshell-tui: gum-env=rejected line=2 default=gum"]
    ];
    for (const [name, judgeText, warning] of judgeRows) {
        const run = present(path.join(root, "judge-" + name), null, presenterTree("judge-" + name, presenterText, judgeText), ["sh", "-c", "env; exit 7"]);
        assert.equal(run.status, 7, `${name} judge: present did not keep the command's exit code: ${run.stderr}`);
        assert.equal(run.stderr.split("\n")[0], warning, `${name} judge: present's warning`);
        const exported = run.stdout.split("\n").filter(line => /^(GUM_|FOREGROUND=|BACKGROUND=|BORDER_FOREGROUND=|VGS_TUI_(ACCENT|SUCCESS|WARNING|DANGER)=)/.test(line));
        assert.deepEqual(exported, [], `${name} judge: present exported a colour`);
    }

    // The verb refuses a gum target with other than one file, and prints
    // nothing: a tree whose copy of the judge reads a planted gum target
    // beside the shipped vgs package; bin/lib and shell/ are links.
    const tree = path.join(root, "two");
    const planted2 = path.join(tree, "themes", "targets", "gum");
    fs.mkdirSync(path.join(tree, "bin"), { recursive: true });
    fs.mkdirSync(planted2, { recursive: true });
    fs.symlinkSync(path.join(repo, "bin", "lib"), path.join(tree, "bin", "lib"));
    fs.symlinkSync(path.join(repo, "shell"), path.join(tree, "shell"));
    fs.symlinkSync(path.join(repo, "themes", "vgs"), path.join(tree, "themes", "vgs"));
    fs.copyFileSync(judge, path.join(tree, "bin", "vgshell-theme-judge"));
    const twoTarget = JSON.parse(fs.readFileSync(path.join(targetDir, "target.json"), "utf8"));
    twoTarget.files = [{ template: "gum.env", destination: "gum.a" }, { template: "gum.env", destination: "gum.b" }];
    fs.writeFileSync(path.join(planted2, "target.json"), JSON.stringify(twoTarget));
    fs.copyFileSync(path.join(targetDir, "gum.env"), path.join(planted2, "gum.env"));
    const refused = spawnSync(process.execPath, [path.join(tree, "bin", "vgshell-theme-judge"), "gum-default"],
        { encoding: "utf8", env: { PATH: childPath, HOME: root } });
    assert.equal(refused.status, 1, refused.stderr);
    assert.equal(refused.stdout, "");
    assert.equal(refused.stderr.split("\n")[0], "vgshell: refused: gum-default reason=files count=2");

    // Control: a `$(...)` value fails the check and runs nothing.
    const planted = path.join(root, "planted");
    const bad = rendered(defaults, template + `GUM_SPIN_TITLE_FOREGROUND=$(touch ${planted})\n`);
    assert.throws(() => presented(path.join(root, "control"), bad), new RegExp(`gum-env=rejected line=${template.split("\n").length} `),
        "control: the check passed a gum.env line holding $(...)");
    assert.equal(fs.existsSync(planted), false, "control: present ran the planted line");

    console.log(`test-theme-gum: ok packages=${EXPECTED.length} lines=${lines} controls=4`);
} finally {
    fs.rmSync(root, { recursive: true, force: true });
}
