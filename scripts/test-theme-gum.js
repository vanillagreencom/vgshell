#!/usr/bin/env node
// The shipped gum target, themes/targets/gum, against the one reader of the
// file it writes: bin/vgshell-tui present, which parses gum.env and never
// sources it. The target renders under the shipped vgs package and the
// catalog's flexoki-light, a light package; present must export every line
// of each render and warn nothing. The expected colours are pinned literals
// written from each package's theme.json; flexoki-light's success, warning
// and danger are mixes its theme.json states, resolved once under node with
// ThemeLogic.accept. With no gum.env, as before any theme apply, present
// must export the vgs colours from `vgshell-theme-judge default-file gum`,
// pinned by the same vgs literals.
//
// With no gum.env and a judge that fails, or one that prints a line the
// rule rejects, present warns with its keyed line, exports no colour and
// still runs the command with its exit code; those judges are stand-ins in
// copies of the tree.
//
// The controls: a copy of the template whose last value is a `$(...)`
// command must fail the check, with nothing run; a copy of the presenter
// without its no-gum.env branch must fail the absent row. The judge's verb
// must refuse a target with two files, planted in a copy of the themes
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

// A copy of FILE under DIR with NEEDLE, which occurs once, replaced.
const mutant = (file, dir, needle, replacement) => {
    const text = fs.readFileSync(file, "utf8");
    assert.equal(text.split(needle).length, 2, `control: ${needle} occurs once in ${file}`);
    const copy = path.join(dir, path.basename(file));
    fs.writeFileSync(copy, text.replace(needle, replacement), { mode: 0o755 });
    assert.notEqual(fs.readFileSync(copy, "utf8"), text);
    return copy;
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

    // No gum.env: the vgs colours, from the judge's render of the target.
    const [, , vgsLines] = EXPECTED[0];
    const absent = seen => {
        for (const line of vgsLines) assert.ok(seen.has(line), `no gum.env: present did not export ${line}`);
    };
    absent(presented(path.join(root, "absent"), null));

    // A tree whose bin/ holds the mutant presenter and a copy of the judge,
    // whose themes/ links the shipped vgs package and gum target beside a
    // planted target with two files; bin/lib and shell/ are links.
    const tree = path.join(root, "tree");
    fs.mkdirSync(path.join(tree, "bin"), { recursive: true });
    fs.mkdirSync(path.join(tree, "themes", "targets", "two"), { recursive: true });
    fs.symlinkSync(path.join(repo, "bin", "lib"), path.join(tree, "bin", "lib"));
    fs.symlinkSync(path.join(repo, "shell"), path.join(tree, "shell"));
    fs.symlinkSync(path.join(repo, "themes", "vgs"), path.join(tree, "themes", "vgs"));
    fs.symlinkSync(targetDir, path.join(tree, "themes", "targets", "gum"));
    fs.copyFileSync(judge, path.join(tree, "bin", "vgshell-theme-judge"));
    const two = path.join(tree, "themes", "targets", "two");
    const twoTarget = JSON.parse(fs.readFileSync(path.join(targetDir, "target.json"), "utf8"));
    twoTarget.files = [{ template: "gum.env", destination: "two.a" }, { template: "gum.env", destination: "two.b" }];
    fs.writeFileSync(path.join(two, "target.json"), JSON.stringify(twoTarget));
    fs.copyFileSync(path.join(targetDir, "gum.env"), path.join(two, "gum.env"));

    // Control: present without its no-gum.env branch fails the absent row.
    const unthemed = mutant(presenter, path.join(tree, "bin"),
        `  text="$(node "$root/bin/vgshell-theme-judge" default-file gum 2>/dev/null)" || status=$?`, "  return 0");
    assert.throws(() => absent(presented(path.join(root, "unthemed"), null, unthemed)), /no gum\.env: present did not export/,
        "control: present without its no-gum.env branch passed the absent row");

    // A judge that fails, or prints a line the rule rejects: the keyed
    // warning, no colour, and the command's own exit code. Each tree holds a
    // copy of the presenter, bin/lib linked, and a stand-in judge.
    const judgeRows = [
        ["failing", "process.exit(3);\n", "vgshell-tui: gum-env=default-unavailable exit=3"],
        ["rejected", "process.stdout.write(\"FOREGROUND=#000000\\nPATH=#000000\\n\");\n", "vgshell-tui: gum-env=rejected line=2 default=gum"]
    ];
    for (const [name, judgeText, warning] of judgeRows) {
        const bin = path.join(root, "judge-" + name, "bin");
        fs.mkdirSync(bin, { recursive: true });
        fs.symlinkSync(path.join(repo, "bin", "lib"), path.join(bin, "lib"));
        fs.copyFileSync(presenter, path.join(bin, "vgshell-tui"));
        fs.chmodSync(path.join(bin, "vgshell-tui"), 0o755);
        fs.writeFileSync(path.join(bin, "vgshell-theme-judge"), judgeText);
        const run = present(path.join(root, "judge-" + name), null, path.join(bin, "vgshell-tui"), ["sh", "-c", "env; exit 7"]);
        assert.equal(run.status, 7, `${name} judge: present did not keep the command's exit code: ${run.stderr}`);
        assert.equal(run.stderr.split("\n")[0], warning, `${name} judge: present's warning`);
        const exported = run.stdout.split("\n").filter(line => /^(GUM_|FOREGROUND=|BACKGROUND=|BORDER_FOREGROUND=|VGS_TUI_(ACCENT|SUCCESS|WARNING|DANGER)=)/.test(line));
        assert.deepEqual(exported, [], `${name} judge: present exported a colour`);
    }

    // The verb refuses a target with other than one file, and prints nothing.
    const verb = target => spawnSync(process.execPath, [path.join(tree, "bin", "vgshell-theme-judge"), "default-file", target],
        { encoding: "utf8", env: { PATH: childPath, HOME: root } });
    const one = verb("gum");
    assert.equal(one.status, 0, one.stderr);
    assert.equal(one.stdout, rendered(defaults, template), "default-file gum is the gum target's vgs render");
    const refused = verb("two");
    assert.equal(refused.status, 1, refused.stderr);
    assert.equal(refused.stdout, "");
    assert.equal(refused.stderr.split("\n")[0], "vgshell: refused: default-file=two reason=files count=2");

    // Control: a `$(...)` value fails the check and runs nothing.
    const planted = path.join(root, "planted");
    const bad = rendered(defaults, template + `GUM_SPIN_TITLE_FOREGROUND=$(touch ${planted})\n`);
    assert.throws(() => presented(path.join(root, "control"), bad), new RegExp(`gum-env=rejected line=${template.split("\n").length} `),
        "control: the check passed a gum.env line holding $(...)");
    assert.equal(fs.existsSync(planted), false, "control: present ran the planted line");

    console.log(`test-theme-gum: ok packages=${EXPECTED.length} lines=${lines} controls=2`);
} finally {
    fs.rmSync(root, { recursive: true, force: true });
}
