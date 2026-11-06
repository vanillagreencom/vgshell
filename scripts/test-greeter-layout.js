#!/usr/bin/env node
// The greeter's data handoff: production copy/read/render operations on a
// private directory. Independent expected Lua pins the rotated two-output
// layout; hostile identifiers never become code; failed copies retain the
// prior file. A disposable renderer mutant must fail that same contract.
"use strict";
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const repo = path.resolve(__dirname, "..");
const file = path.join(repo, "bin/lib/greeter-layout.js");
const helper = require(file);
const root = fs.mkdtempSync(path.join(os.tmpdir(), "greeter-layout-"));
const saved = {
    outputs: {
        "DP-2": { mode: { width: 5120, height: 2880, refresh: 60 }, position: { x: 0, y: 0 }, transform: 1, scale: 2 },
        "DP-1": { mode: { width: 6016, height: 3384, refresh: 60 }, position: { x: 1440, y: 620 }, transform: 0, scale: 2 }
    },
    primaryOutput: "DP-1"
};
const expected = [
    'hl.monitor({ output = "DP-1", mode = "6016x3384@60", position = "1440x620", scale = 2, transform = 0 })',
    'hl.monitor({ output = "DP-2", mode = "5120x2880@60", position = "0x0", scale = 2, transform = 1 })'
];

function rendering(subject) {
    assert.equal(subject.judge(JSON.stringify(saved)).lines.join("\n"), expected.join("\n"));
}

try {
    const directory = path.join(root, "vgshell");
    fs.mkdirSync(directory);
    const output = path.join(directory, "displays.json");
    assert.deepEqual(helper.read(directory).data, { outputs: {}, primaryOutput: "" });
    const oldMask = process.umask(0o077);
    try { assert.equal(helper.copy(JSON.stringify(saved), directory), "copied"); }
    finally { process.umask(oldMask); }
    const first = fs.statSync(output);
    assert.equal(first.mode & 0o777, 0o644, "the greeter can read a copy made under a private umask");
    assert.deepEqual(helper.read(directory).data, saved);
    assert.equal(helper.copy(JSON.stringify(saved), directory), "unchanged");
    assert.equal(fs.statSync(output).ino, first.ino, "unchanged bytes retain the published file");

    const invalid = [
        ["JSON", "not JSON", /layout=json/],
        ["shape", JSON.stringify({ ...saved, command: "os.execute('false')" }), /layout=shape/],
        ["identifier", JSON.stringify({ ...saved, outputs: { ['DP-2"); os.execute("false")']: {} } }), /layout=rules/],
        ["rotation", JSON.stringify({ ...saved, outputs: { "DP-2": { transform: 8 } } }), /layout=rules/],
        ["primary", JSON.stringify({ ...saved, primaryOutput: 'DP-1"; os.execute("false")' }), /layout=primary/]
    ];
    for (const [name, text, error] of invalid) {
        assert.throws(() => helper.copy(text, directory), error, name);
        assert.deepEqual(helper.read(directory).data, saved, name + " leaves the prior layout");
        assert.equal(fs.statSync(output).ino, first.ino);
    }
    for (const mode of [0o775, 0o777]) {
        fs.chmodSync(directory, mode);
        assert.throws(() => helper.copy(JSON.stringify(saved), directory), /destination=ownership/);
    }
    fs.chmodSync(directory, 0o755);
    fs.renameSync(output, path.join(root, "retained"));
    fs.symlinkSync(path.join(root, "retained"), output);
    assert.throws(() => helper.copy(JSON.stringify(saved), directory), { code: "ELOOP" });
    assert.throws(() => helper.read(directory), { code: "ELOOP" });
    fs.unlinkSync(output);
    fs.symlinkSync(directory, path.join(root, "link"));
    assert.throws(() => helper.copy(JSON.stringify(saved), path.join(root, "link")));
    fs.writeFileSync(output, "{bad");
    assert.throws(() => helper.read(directory), /layout=json/, "bad data is not an absent layout");
    fs.chmodSync(output, 0o666);
    assert.throws(() => helper.copy(JSON.stringify(saved), directory), /destination=ownership/);
    fs.chmodSync(output, 0o644);
    helper.copy(JSON.stringify({ outputs: {}, primaryOutput: "" }), directory);
    assert.deepEqual(helper.read(directory).data, { outputs: {}, primaryOutput: "" }, "clear persists the empty layout");

    const controlRoot = path.join(root, "control");
    fs.mkdirSync(path.join(controlRoot, "bin/lib"), { recursive: true });
    fs.mkdirSync(path.join(controlRoot, "shell/Core"), { recursive: true });
    for (const relative of ["bin/lib/qml-library.js", "bin/lib/judge-files.js", "shell/Core/MonitorLogic.js"])
        fs.copyFileSync(path.join(repo, relative), path.join(controlRoot, relative));
    const source = fs.readFileSync(file, "utf8");
    const directoryDeclaration = 'const DIRECTORY = "/var/lib/vgshell/greeter/theme/vgshell";';
    assert.equal(source.split(directoryDeclaration).length, 2);
    const fixtureFile = path.join(controlRoot, "bin/lib/greeter-layout.js");
    fs.writeFileSync(fixtureFile, source.replace(directoryDeclaration, "const DIRECTORY = " + JSON.stringify(directory) + ";"));
    const launcher = path.join(controlRoot, "bin/vgshell-greeter-layout");
    fs.copyFileSync(path.join(repo, "bin/vgshell-greeter-layout"), launcher);
    const preload = path.join(root, "untrusted-preload.js");
    fs.writeFileSync(preload, 'throw new Error("untrusted Node preload ran");\n');
    const clear = { outputs: {}, primaryOutput: "" };
    const cliRows = [
        ["read", undefined, JSON.stringify(clear) + "\n"],
        ["render", undefined, "\n"],
        ["copy", JSON.stringify(saved), "layout=copied\n"],
        ["render", undefined, expected.join("\n") + "\n"],
        ["read", undefined, JSON.stringify(saved) + "\n"],
        ["copy", JSON.stringify(saved), "layout=unchanged\n", path.join(root, "unused-read-home")]
    ];
    for (const [operation, input, stdout, configHome] of cliRows) {
        const result = spawnSync("/usr/bin/bash", [launcher, operation], {
            encoding: "utf8", input, timeout: 10000,
            env: { PATH: path.dirname(process.execPath) + ":/usr/bin:/bin", VGS_TEST_RUN: "1", XDG_CONFIG_HOME: configHome || root,
                NODE_OPTIONS: "--require " + preload, NODE_PATH: root }
        });
        assert.equal(result.status, 0, operation + ": " + result.stderr);
        assert.equal(result.stdout, stdout, operation);
    }
    const before = "const result = monitors.rulesLines(data.outputs);";
    assert.equal(source.split(before).length, 2);
    const mutant = path.join(controlRoot, "bin/lib/greeter-layout.js");
    fs.writeFileSync(mutant, source.replace(before, "const result = { ok: true, lines: [] };"));
    assert.throws(() => rendering(require(mutant)), assert.AssertionError, "control: missing monitor rules fail the layout assertion");
    console.log("greeter-layout: copy, data refusal, CLI environment, read and monitor rendering pass; renderer control rejected");
} finally { fs.rmSync(root, { recursive: true, force: true }); }
