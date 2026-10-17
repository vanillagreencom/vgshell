#!/usr/bin/env node
// The tmux target's truecolor lines, themes/targets/tmux/tmux.conf,
// sourced into private tmux servers. The include renders through the
// renderer under the shipped vgs package and each server sources it, as the
// user's tmux.conf does:
//
// - CLAUDE_CODE_TMUX_TRUECOLOR: a pane opened after the include loads holds
//   CLAUDE_CODE_TMUX_TRUECOLOR=1, the variable Claude Code reads before it
//   drops to 256 colours under TMUX.
// - PROMPT_TOOLKIT_COLOR_DEPTH: a new pane holds DEPTH_24_BIT, the override
//   prompt_toolkit reads for Hermes' classic CLI.
// - RGB: a client attached with TERM=xterm-256color and no COLORTERM, whose
//   terminfo has no RGB flag, shows RGB in #{client_termfeatures}.
//
// The client attaches through util-linux script, a pty that answers no
// terminal query. A client attached from a tmux pane is no control: the outer
// tmux answers XTVERSION, the client reads its terminal type as tmux and turns
// RGB on with or without the line (tmux 3.8, run by hand on 2026-10-17).
//
// The controls: the template with each line disabled, rendered and sourced the
// same way, must show no variable and no RGB.
//
// Each server runs on its own socket under a scratch TMUX_TMPDIR and HOME,
// with -f /dev/null, and is killed before the scratch root is removed. A
// server daemonizes out of this process group, so a signal to the group never
// reaches it: its one waiting pane exits when this process ends, however it
// ends, and SIGINT, SIGTERM or SIGHUP kills every server and removes the root
// before exiting 128+signo. With no tmux or script on PATH the test exits 77,
// not measured.
"use strict";
const assert = require("node:assert/strict");
const { spawn, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");
const render = require("../bin/lib/theme-render.js");

const repo = path.join(__dirname, "..");
const logic = load(path.join(repo, "shell", "Commons", "ThemeLogic.js"));
const TOKENS = load(path.join(repo, "shell", "Commons", "Tokens.js")).TOKENS;
const targetDir = path.join(repo, "themes", "targets", "tmux");
const VARIABLES = [
    ["CLAUDE_CODE_TMUX_TRUECOLOR", "1"],
    ["PROMPT_TOOLKIT_COLOR_DEPTH", "DEPTH_24_BIT"]
];
const RGB_LINE = 'set -ag terminal-overrides ",*:RGB"';
// A spawnSync deadline: a tmux client that never returns fails the test.
const DEADLINE_MS = 10000;

for (const [tool, flag] of [["tmux", "-V"], ["script", "--version"]]) {
    const probe = spawnSync(tool, [flag], { encoding: "utf8", env: { PATH: process.env.PATH } });
    if (probe.error && probe.error.code === "ENOENT") {
        console.log(`test-theme-tmux: status=not-measured reason=no-${tool}`);
        process.exit(77);
    }
    assert.equal(probe.status, 0, `${tool} ${flag}: ${probe.stderr}`);
}

const pkg = logic.acceptPackage(TOKENS, {
    directoryName: "vgs",
    themeJson: fs.readFileSync(path.join(repo, "themes", "vgs", "theme.json"), "utf8"),
    terminalJson: fs.readFileSync(path.join(repo, "themes", "vgs", "terminal.json"), "utf8"),
    shipped: true
});
assert.equal(pkg.ok, true, pkg.ok ? "" : logic.refusalLine(pkg));
const judged = render.acceptTarget(logic, "tmux", fs.readFileSync(path.join(targetDir, render.TARGET_FILE), "utf8"));
assert.equal(judged.ok, true, judged.ok ? "" : render.refusalLine("tmux", judged));
assert.deepEqual(judged.target.files.map(f => f.template), ["tmux.conf"]);
const template = fs.readFileSync(path.join(targetDir, "tmux.conf"), "utf8");

const rendered = text => {
    const result = render.renderTarget(logic, TOKENS, judged.target, new Map([["tmux.conf", text]]),
        { values: pkg.values, slots: render.terminalSource(pkg, pkg).terminal, curated: new Map(), installed: false });
    assert.equal(result.ok, true, result.ok ? "" : render.refusalLine("tmux", result));
    return result.files[0].bytes.toString("utf8");
};
// Comment out LINE, retaining its text while disabling its behaviour.
const disabled = line => {
    assert.equal(template.split(line + "\n").length, 2, line);
    const text = template.replace(line + "\n", "# " + line + "\n");
    assert.notEqual(text, template);
    return text;
};

// A socket path holds at most 107 bytes, and an agent or row TMPDIR can be
// long, so the root, the socket directory and each socket name are short.
const root = fs.mkdtempSync(path.join(os.tmpdir(), "vt-"));
const env = {
    PATH: process.env.PATH,
    HOME: path.join(root, "home"),
    TMUX_TMPDIR: path.join(root, "t"),
    TERM: "xterm-256color",
    LANG: "C.UTF-8",
    SHELL: "/bin/sh",
    VGS_TEST_RUN: "1"
};
const sockets = [];
const children = [];

// Kills every server and signals every script child; repeatable, since a
// signal can land while the normal stop runs.
const stopServers = () => {
    for (const socket of sockets)
        spawnSync("tmux", ["-L", socket, "kill-server"], { env, timeout: DEADLINE_MS });
    for (const { child } of children) {
        if (child.exitCode === null && child.signalCode === null) {
            child.stdin.end();
            child.kill("SIGTERM");
        }
    }
};
const removeRoot = () => fs.rmSync(root, { recursive: true, force: true });
for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
    process.once(signal, () => {
        stopServers();
        removeRoot();
        process.exit(128 + os.constants.signals[signal]);
    });
}

const tmux = (socket, ...args) => {
    const run = spawnSync("tmux", ["-L", socket, "-f", "/dev/null", ...args], { encoding: "utf8", env, timeout: DEADLINE_MS });
    assert.equal(run.error, undefined, `tmux ${args[0]}: ${run.error}`);
    assert.equal(run.status, 0, `tmux ${args[0]}: ${run.stderr}`);
    return run.stdout;
};

// A server on its own socket, NAME, holding one session whose pane waits
// until this process ends, that has sourced TEXT rendered. The session's end
// ends the server, and with it any client attached.
const server = (name, text) => {
    const include = path.join(root, `${name}.conf`);
    fs.writeFileSync(include, rendered(text));
    sockets.push(name);
    tmux(name, "new-session", "-d", "-s", "t", "-x", "80", "-y", "24",
        `exec tail --pid=${process.pid} -f /dev/null`);
    tmux(name, "source-file", include);
    return name;
};

// What a pane opened after TEXT loads holds as the variable.
const paneVariable = (name, text, variable) => {
    const socket = server(name, text);
    const out = path.join(root, `${name}.out`);
    tmux(socket, "new-window", "-d",
        `printf '%s' "\${${variable}-unset}" > '${out}'; tmux wait-for -S read`);
    tmux(socket, "wait-for", "read");
    return fs.readFileSync(out, "utf8");
};

// The features of a client attached through a pty with no COLORTERM, to a
// server that sourced TEXT.
const clientFeatures = (name, text) => {
    const socket = server(name, text);
    tmux(socket, "set-hook", "-g", "client-attached", "wait-for -S attached");
    const child = spawn("script", ["-q", "-e", "-c", `exec tmux -L ${socket} attach-session -t t`, "/dev/null"],
        { env, stdio: ["pipe", "ignore", "ignore"] });
    children.push({ child, exited: new Promise(resolve => child.once("exit", resolve)) });
    tmux(socket, "wait-for", "attached");
    const lines = tmux(socket, "list-clients", "-F", "#{client_termname} #{client_termfeatures}").trim().split("\n");
    assert.equal(lines.length, 1, lines.join("\n"));
    const [termname, features] = lines[0].split(" ");
    assert.equal(termname, "xterm-256color");
    return features.split(",");
};

const stop = async () => {
    stopServers();
    await Promise.all(children.map(({ exited }) => exited));
    removeRoot();
};

(async () => {
    try {
        fs.mkdirSync(env.HOME);
        fs.mkdirSync(env.TMUX_TMPDIR);
        for (const [index, [variable, value]] of VARIABLES.entries()) {
            const line = `set-environment -g ${variable} ${value}`;
            assert.equal(paneVariable(`v${index}1`, template, variable), value, variable);
            assert.equal(paneVariable(`v${index}0`, disabled(line), variable), "unset", variable);
            console.log(`test-theme-tmux: pane-variable=${variable} value=${value} control=unset`);
        }

        assert.ok(clientFeatures("r1", template).includes("RGB"));
        const control = clientFeatures("r0", disabled(RGB_LINE));
        assert.ok(!control.includes("RGB"), control.join(","));
        console.log("test-theme-tmux: client-rgb=on control=off");
    } finally {
        await stop();
    }
})().catch(error => {
    console.error(error);
    process.exit(1);
});
