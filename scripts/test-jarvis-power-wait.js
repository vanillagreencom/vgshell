#!/usr/bin/env node
// backend/power-wait.js, run as the shell runs it, against the stand-in for
// the Jarvis package's `jarvis-session`
// (scripts/fixtures/jarvis/session-package.py) and a stand-in `systemctl`
// that records its arguments, in a scratch home of the J09 world
// (scripts/lib/jarvis-env.sh): PATH holds only stand-ins and the world's
// tools, so no real `systemctl` can run. The helper asks the session to
// save once, then asks `systemctl` once whatever the answer: after the
// saved answer, at its bound, and at once without a command or when the
// command cannot start. Its keyed stderr lines name what came of the
// `prepare`, and of a `systemctl` that does not succeed, whose own words
// reach that stderr too. A control runs a private copy of the plugin with
// one planted defect.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");
const tree = path.resolve(__dirname, "..");
const plugin = path.join(tree, "shell/plugins/vgs.jarvis");
const standIn = path.join(tree, "scripts/fixtures/jarvis/session-package.py");
// Well past a prompt run, well under the shipped 60 s bound.
const PROMPT_MS = 5000;

function inside() {
    const root = process.env.JARVIS_TEST_ROOT;
    const home = process.env.HOME;
    const folder = path.join(home, "Jarvis");
    const stuck = path.join(home, "Stuck");
    const bare = path.join(home, "Bare");
    const signalled = path.join(home, "Signalled");
    const scripts = at => path.join(at, ".agents/skills/jarvis/scripts");
    for (const directory of [scripts(folder), scripts(stuck), scripts(signalled), bare]) fs.mkdirSync(directory, { recursive: true });
    fs.copyFileSync(standIn, path.join(scripts(folder), "jarvis-session"));
    fs.chmodSync(path.join(scripts(folder), "jarvis-session"), 0o755);
    // A command whose interpreter is gone: its start fails.
    fs.writeFileSync(path.join(scripts(stuck), "jarvis-session"), "#!/nonexistent/interpreter\n");
    fs.chmodSync(path.join(scripts(stuck), "jarvis-session"), 0o755);
    // A command a signal ends.
    fs.writeFileSync(path.join(scripts(signalled), "jarvis-session"), "#!/bin/sh\nkill -TERM $$\n");
    fs.chmodSync(path.join(scripts(signalled), "jarvis-session"), 0o755);
    const powerLog = path.join(home, "systemctl.log");
    // While this file holds a number, the stand-in systemctl refuses as
    // logind does and exits with it.
    const powerExit = path.join(home, "systemctl.exit");
    let cases = 0, controls = 0;

    function answers(value) {
        fs.writeFileSync(path.join(scripts(folder), "answers.json"), JSON.stringify(value));
        fs.rmSync(path.join(scripts(folder), "calls.log"), { force: true });
        fs.rmSync(powerLog, { force: true });
        fs.rmSync(powerExit, { force: true });
    }
    const calls = () => fs.existsSync(path.join(scripts(folder), "calls.log"))
        ? fs.readFileSync(path.join(scripts(folder), "calls.log"), "utf8").split("\n").filter(Boolean).map(line => JSON.parse(line)) : [];
    const powered = () => fs.existsSync(powerLog) ? fs.readFileSync(powerLog, "utf8").split("\n").filter(Boolean).map(line => JSON.parse(line)) : [];
    const saved = { exit: 0, object: { state: "running", reason: "existing", saved: true } };
    // One helper run from DIRECTORY, a plugin tree, with the variables a
    // shell restarted from a tmux pane would hand it; its exit status and
    // milliseconds and the keyed lines of its stderr, systemctl's own
    // among them. The parent's deadline bounds a helper that never ends.
    function helper(directory, args, deadline = 2 * PROMPT_MS) {
        const from = Date.now();
        const result = cp.spawnSync(process.execPath, [path.join(directory, "backend/power-wait.js"), "--tree", tree, ...args], {
            env: { ...process.env, XDG_SESSION_ID: "7", TMUX: "/scratch/other,1,0", TMUX_PANE: "%9", VGSHELL_RUNNER_PID: "1" },
            encoding: "utf8", timeout: deadline });
        return { status: result.status, ms: Date.now() - from, lines: result.stderr.split("\n").filter(line => /^(jarvis|systemctl): /.test(line)) };
    }
    const prepare = (purpose, at = folder) => ["prepare", "--for", purpose, "--home", at];

    // The saved answer: one `prepare` in the home with the user's session
    // and none of the shell's marks, then one `systemctl` at once.
    function answered(directory) {
        for (const [verb, purpose] of [["reboot", "restart"], ["poweroff", "shutdown"]]) {
            answers({ prepare: saved });
            const run = helper(directory, [verb, "~/Jarvis"]);
            assert.deepEqual(calls().map(call => call.argv), [prepare(purpose)], verb + ": one prepare");
            assert.deepEqual(calls().map(call => [call.cwd, call.session, call.leaked]), [[folder, "7", []]], verb + ": the command's folder and environment");
            assert.deepEqual(powered(), [[verb]], verb + ": one systemctl after the answer");
            assert.ok(run.status === 0 && run.ms < PROMPT_MS, verb + ": at once after the answer: " + JSON.stringify(run));
            assert.deepEqual(run.lines, ["jarvis: power-wait=" + verb + " prepare=answered exit=0"], verb + ": the keyed line");
        }
        cases++;
    }
    // A command that refuses `prepare`, as a package without the verb
    // does, is an answer too.
    function refused(directory) {
        answers({});
        const run = helper(directory, ["reboot", "~/Jarvis"]);
        assert.deepEqual([calls().map(call => call.argv), powered()], [[prepare("restart")], [["reboot"]]]);
        assert.ok(run.ms < PROMPT_MS, "at once after the refusal: " + JSON.stringify(run));
        assert.deepEqual(run.lines, ["jarvis: power-wait=reboot prepare=refused exit=2"], "the keyed line names the refusal");
        cases++;
    }
    // A command that answers outside success, or that a signal ends, is a
    // failure the keyed line names; systemctl still runs.
    function failed(directory) {
        answers({ prepare: { exit: 1, object: { state: "failed", reason: "launch-failed" } } });
        const exited = helper(directory, ["reboot", "~/Jarvis"]);
        assert.deepEqual([powered(), exited.lines], [[["reboot"]], ["jarvis: power-wait=reboot prepare=failed exit=1"]], "an exit of 1");
        answers({});
        const ended = helper(directory, ["reboot", "~/Signalled"]);
        assert.deepEqual([powered(), ended.lines], [[["reboot"]], ["jarvis: power-wait=reboot prepare=failed signal=SIGTERM"]], "a signal");
        cases++;
    }
    // A systemctl that refuses, as logind does under another program's
    // inhibitor lock: its own words and a keyed line reach stderr.
    function powerRefused(directory) {
        answers({ prepare: saved });
        fs.writeFileSync(powerExit, "1");
        const run = helper(directory, ["reboot", "~/Jarvis"]);
        assert.deepEqual([powered(), run.status, run.lines], [[["reboot"]], 1, ["jarvis: power-wait=reboot prepare=answered exit=0",
            "systemctl: refused by an inhibitor lock", "jarvis: power-wait=reboot systemctl=exit-1"]]);
        cases++;
    }
    // No home folder, no command in it, or a command that cannot start:
    // `systemctl` at once.
    function noCommand(directory) {
        for (const at of ["~/Bare", "~/Absent", "", "/outside", "~/Stuck"]) {
            answers({ prepare: saved });
            const run = helper(directory, ["poweroff", at]);
            assert.deepEqual([calls(), powered()], [[], [["poweroff"]]], JSON.stringify(at) + ": no prepare, one systemctl");
            assert.ok(run.ms < PROMPT_MS, JSON.stringify(at) + ": at once: " + JSON.stringify(run));
            cases++;
        }
    }
    // Arguments it cannot read run nothing.
    function badArguments(directory) {
        for (const args of [["restart", "~/Jarvis"], ["reboot"], ["reboot", "~/Jarvis", "more"]]) {
            answers({ prepare: saved });
            assert.deepEqual([helper(directory, args).status, calls(), powered()], [2, [], []], args.join(" "));
            cases++;
        }
    }

    for (const check of [answered, refused, failed, powerRefused, noCommand, badArguments]) check(plugin);

    // A copy of the plugin tree FROM with one text of FILE replaced.
    function planted(name, file, needle, replacement, from = plugin) {
        const source = fs.readFileSync(path.join(from, file), "utf8");
        assert.equal(source.split(needle).length - 1, 1, name + " match");
        const copy = path.join(root, name);
        fs.cpSync(from, copy, { recursive: true });
        fs.writeFileSync(path.join(copy, file), source.replace(needle, () => replacement));
        return copy;
    }
    // The bound, on a copy whose bound is short: a `prepare` that never
    // answers, and whose child holds its output open, still reaches
    // `systemctl` at the bound. Real time, for the timer's wiring; the
    // shipped bound is the same constant.
    const W = "backend/power-wait.js";
    const quick = planted("quick-bound", W, "const PREPARE_MS = 60000;", "const PREPARE_MS = 400;");
    function hung(directory) {
        answers({ prepare: { ...saved, hold: 8 } });
        const run = helper(directory, ["reboot", "~/Jarvis"], 20000);
        assert.deepEqual([calls().map(call => call.argv), powered()], [[prepare("restart")], [["reboot"]]], "one prepare, one systemctl");
        assert.ok(run.ms < 4000, "the bound ends the wait: " + JSON.stringify(run));
        assert.deepEqual(run.lines, ["jarvis: power-wait=reboot prepare=bound"], "the keyed line names the bound");
        cases++;
    }
    hung(quick);

    function control(name, file, needle, replacement, check, from = plugin) {
        const copy = planted("control-" + name, file, needle, replacement, from);
        assert.throws(() => check(copy), error => {
            assert.ok(error instanceof assert.AssertionError, name + " must turn red, not crash: " + error.stack);
            console.log("test-jarvis-power-wait: control=" + name + " killed by=" + JSON.stringify(error.message.split("\n")[0]));
            return true;
        });
        controls++;
    }
    control("no-bound", W, 'prepare.kill("SIGKILL");\n            power("bound");', "", hung, quick);
    control("waits-for-bound", W, '            clearTimeout(bound);\n            power(signal !== null', "            return;\n            (signal !== null", answered);
    control("no-command", W, 'if (at.kind === "blocked") return power(at.block);', 'if (at.kind === "blocked") return;', noCommand);
    control("start-failed", W, '            clearTimeout(bound);\n            power("spawn-failed");', "            return;", noCommand);
    control("outcome-named", W, 'code === 0 ? "answered exit=0" : ', "", answered);
    control("systemctl-silent", W, 'stdio: ["ignore", "ignore", "inherit"]', 'stdio: "ignore"', powerRefused);
    control("systemctl-exit-unnamed", W, '            if (code === 0) return;', "            return;", powerRefused);
    control("purpose", W, 'reboot: "restart"', 'reboot: "shutdown"', answered);
    control("environment", "backend/SessionCommand.js", "const { TMUX, TMUX_PANE, VGSHELL_RUNNER_PID, ...kept } = from;", "const kept = from;", answered);
    console.log("test-jarvis-power-wait: ok cases=" + cases + " controls=" + controls);
}

function main() {
    if (process.argv[2] === "--inside") return inside();
    const parent = require("node:os").tmpdir();
    const root = fs.realpathSync(fs.mkdtempSync(path.join(parent, "jp-")));
    try {
        const standins = path.join(root, "standins");
        fs.mkdirSync(standins);
        // The only `systemctl` the world's PATH reaches: it records its
        // arguments in the world's home and does nothing else.
        fs.writeFileSync(path.join(standins, "systemctl"), "#!/usr/bin/env python3\nimport json, os, sys\n"
            + "with open(os.path.join(os.environ['HOME'], 'systemctl.log'), 'a') as log:\n    log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            + "refusal = os.path.join(os.environ['HOME'], 'systemctl.exit')\n"
            + "if os.path.exists(refusal):\n    sys.stderr.write('systemctl: refused by an inhibitor lock\\n')\n    sys.exit(int(open(refusal).read()))\n");
        fs.chmodSync(path.join(standins, "systemctl"), 0o755);
        const result = cp.spawnSync("/bin/bash", [path.join(tree, "scripts/lib/jarvis-env.sh"), standins,
            "--", "node", __filename, "--inside"], {
            env: { PATH: "/usr/bin:/bin", HOME: root, JARVIS_TEST_SCRATCH_ROOT: root },
            encoding: "utf8", timeout: 300000
        });
        process.stdout.write(result.stdout || "");
        process.stderr.write(result.stderr || "");
        if (result.error) throw result.error;
        assert.equal(result.signal, null);
        process.exitCode = result.status;
    } finally { fs.rmSync(root, { recursive: true, force: true }); }
}
try { main(); } catch (error) { console.error(error); process.exitCode = 1; }
