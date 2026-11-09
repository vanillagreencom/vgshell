#!/usr/bin/env node
// backend/session-control.js, run as the shell runs it, against a stand-in
// for the Jarvis package's `jarvis-session`
// (scripts/fixtures/jarvis/session-package.py) in a scratch home of the
// J09 world: the stand-in records each call and answers what the case
// wrote, and starts nothing. No package, vendor program, account, tmux
// server or live session; a `claude` stand-in answers `auth status` for
// ~/.claude alone. A control runs a private copy of the plugin with one
// planted defect. `node test-jarvis-session-control.js CHECK` runs that
// one check and no control, as against another tree's plugin copied here.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");
const crypto = require("node:crypto");
const tree = path.resolve(__dirname, "..");
const plugin = path.join(tree, "shell/plugins/vgs.jarvis");
const standIn = path.join(tree, "scripts/fixtures/jarvis/session-package.py");

function inside() {
    const root = process.env.JARVIS_TEST_ROOT;
    const home = process.env.HOME;
    const folder = path.join(home, "Jarvis");
    const other = path.join(home, "Other");
    const bare = path.join(home, "Bare");
    const account = path.join(home, ".claude");
    const scripts = at => path.join(at, ".agents/skills/jarvis/scripts");
    for (const directory of [scripts(folder), scripts(other), bare, account]) fs.mkdirSync(directory, { recursive: true });
    for (const at of [folder, other]) {
        fs.copyFileSync(standIn, path.join(scripts(at), "jarvis-session"));
        fs.chmodSync(path.join(scripts(at), "jarvis-session"), 0o755);
    }
    // An account's id as the Jarvis page saves it (Accounts.js identity).
    const claude = "cli:" + crypto.createHash("sha256").update(JSON.stringify(["claude", account])).digest("hex").slice(0, 32);
    require(path.join(plugin, "backend/Core.js")).use(tree);
    const { Accounts } = require(path.join(plugin, "backend/Accounts.js"));
    const judge = new Accounts(path.join(process.env.XDG_STATE_HOME, "vgshell/jarvis"), process.env);
    const local = judge.localRows().map(({ row, label, source }) => judge.account(row, label, { kind: "found" }, source).id)[0];
    assert.equal(typeof local, "string");
    let cases = 0, controls = 0;

    // The stand-in's answers in a home, and the calls it took since.
    function answers(at, value) {
        fs.writeFileSync(path.join(scripts(at), "answers.json"), JSON.stringify(value));
        fs.rmSync(path.join(scripts(at), "calls.log"), { force: true });
    }
    const calls = at => fs.existsSync(path.join(scripts(at), "calls.log"))
        ? fs.readFileSync(path.join(scripts(at), "calls.log"), "utf8").split("\n").filter(Boolean).map(line => JSON.parse(line)) : [];
    const said = (state, reason, more = {}) => ({ exit: 0, object: { state, reason, ...more } });
    // One helper run from DIRECTORY, a plugin tree, with the variables a
    // shell restarted from a tmux pane would hand it; `errors` keeps its
    // stderr.
    let errors = "";
    function helper(directory, args) {
        const result = cp.spawnSync(process.execPath, [path.join(directory, "backend/session-control.js"), "--tree", tree, ...args], {
            env: { ...process.env, XDG_SESSION_ID: "7", TMUX: "/scratch/other,1,0", TMUX_PANE: "%9", VGSHELL_RUNNER_PID: "1" },
            encoding: "utf8", timeout: 30000 });
        assert.equal(result.status, 0, "the helper answers: " + result.stderr);
        errors = result.stderr;
        return JSON.parse(result.stdout);
    }
    const startWords = (mode, origin, at = folder) =>
        ["start", "--harness", "claude", "--account", account, "--mode", mode, "--origin", origin, "--home", at];
    const status = at => ["status", "--home", at];

    // The build with the boot setting on: one `start --origin boot` a
    // build, in the home, with the user's session and none of the shell's
    // own marks. A second build, a shell restart, asks the package again
    // and makes no other call: the package's receipt decides, not VGS.
    function boot(directory) {
        answers(folder, { status: said("stopped", "never-started"), start: said("running", "existing", { home: folder, harness: "claude", account }) });
        for (const round of [1, 2]) {
            const result = helper(directory, ["build", claude, "~/Jarvis", "resume", "on"]);
            assert.equal(result.kind, "answer", "round " + round);
            assert.deepEqual(calls(folder).map(call => call.argv), Array(round).fill([status(folder), startWords("resume", "boot"), status(folder)]).flat(),
                "round " + round + ": one boot start a build and no other call");
        }
        for (const call of calls(folder))
            assert.deepEqual([call.cwd, call.session, call.leaked], [folder, "7", []], "the command's folder and environment");
        cases++;
    }
    // With the setting off a build reads the session and starts nothing,
    // and shows a session started by hand as it is.
    function bootOff(directory) {
        answers(folder, { status: said("running", "existing", { home: folder, harness: "claude", account }) });
        const result = helper(directory, ["build", claude, "~/Jarvis", "resume", "off"]);
        assert.deepEqual([result.kind, result.state, result.names], ["answer", "running", { home: "~/Jarvis", account: "Claude Code, beijuan@vanillagreen.com" }]);
        assert.deepEqual(calls(folder).map(call => call.argv), [status(folder)], "a build with the setting off only reads");
        cases++;
    }
    // After the app's Off, a build is the user's Enable, whatever the boot setting.
    function enable(directory) {
        for (const setting of ["on", "off"]) {
            answers(folder, { status: said("off", "app-off"), start: said("starting", "launching") });
            helper(directory, ["build", claude, "~/Jarvis", "new", setting]);
            assert.deepEqual(calls(folder).map(call => call.argv), [status(folder), startWords("new", "app-on"), status(folder)], "boot " + setting);
        }
        cases++;
    }
    function manual(directory) {
        answers(folder, { status: said("stopped", "ended"), start: said("running", "new-requested") });
        helper(directory, ["start", claude, folder, "new"]);
        assert.deepEqual(calls(folder).map(call => call.argv), [status(folder), startWords("new", "manual"), status(folder)]);
        cases++;
    }
    // The user's Off records the app's Off; a plain stop does not.
    function off(directory) {
        answers(folder, { stop: said("stopping", "stop-requested") });
        assert.equal(helper(directory, ["stop", "~/Jarvis", "app-off"]).state, "stopping");
        helper(directory, ["stop", "~/Jarvis"]);
        assert.deepEqual(calls(folder).map(call => call.argv), [["stop", "--origin", "app-off", "--home", folder], ["stop", "--home", folder]]);
        cases++;
    }
    // A changed home while a session lives: the new selection is checked,
    // then the old home's session stops and the new one starts.
    function change(directory) {
        answers(folder, { status: said("running", "resumed", { home: folder, harness: "claude", account }), stop: said("stopping", "stop-requested") });
        answers(other, { status: said("stopped", "never-started"), start: said("starting", "launching") });
        assert.equal(helper(directory, ["change", "~/Jarvis", claude, "~/Other", "resume"]).state, "stopped");
        assert.deepEqual(calls(folder).map(call => call.argv), [status(folder), ["stop", "--home", folder]]);
        assert.deepEqual(calls(other).map(call => call.argv), [status(other), startWords("resume", "manual", other), status(other)]);
        cases++;
    }
    // A new selection that fails its check keeps the old session, says so
    // and stops nothing.
    function changeRefused(directory) {
        for (const [setting, target, block] of [[local, "~/Jarvis", "not-app"], [claude, "~/Bare", "vgs-package"], [claude, "~/Absent", "no-home"]]) {
            answers(folder, { status: said("running", "resumed", { home: folder, harness: "claude", account }), stop: said("stopping", "stop-requested") });
            const result = helper(directory, ["change", "~/Jarvis", setting, target, "resume"]);
            assert.deepEqual([result.kind, result.state, result.unapplied], ["answer", "running", block], block);
            assert.equal(calls(folder).some(call => call.argv[0] === "stop" || call.argv[0] === "start"), false, block + ": the old session stays");
            cases++;
        }
        // An old home whose command does not answer may hold a live
        // session: the change fails and touches neither home.
        answers(folder, { status: { exit: 3, object: { state: "running", reason: "resumed" } }, stop: said("stopping", "stop-requested") });
        answers(other, { status: said("stopped", "never-started"), start: said("starting", "launching") });
        assert.deepEqual(helper(directory, ["change", "~/Jarvis", claude, "~/Other", "resume"]), { kind: "failed" });
        assert.deepEqual([calls(folder).map(call => call.argv), calls(other)], [[status(folder)], []], "an unread old home is left as it is");
        cases++;
        // The selection the session already runs on replaces nothing.
        answers(folder, { status: said("running", "resumed", { home: folder, harness: "claude", account }), stop: said("stopping", "stop-requested"),
            start: said("running", "existing") });
        assert.equal(helper(directory, ["change", "~/Jarvis", claude, "~/Jarvis", "resume"]).state, "running");
        assert.deepEqual(calls(folder).map(call => call.argv), [status(folder), status(folder)], "the same selection stops and starts nothing");
        cases++;
        // With no live session a change only reads the new selection.
        answers(folder, { status: said("stopped", "stopped"), stop: said("stopped", "stopped") });
        answers(other, { status: said("stopped", "never-started"), start: said("starting", "launching") });
        helper(directory, ["change", "~/Jarvis", claude, "~/Other", "resume"]);
        assert.deepEqual([calls(folder).map(call => call.argv), calls(other).map(call => call.argv)], [[status(folder)], [status(other)]]);
        cases++;
    }
    // What no call can use, and the block that names it.
    function blocks(directory) {
        answers(folder, { status: said("stopped", "never-started"), start: said("starting", "launching") });
        const rows = [
            ["no-home", ["build", claude, "", "resume", "on"]], ["no-home", ["status", "~/Absent"]], ["no-home", ["status", "/outside"]],
            ["vgs-package", ["status", "~/Bare"]], ["vgs-package", ["build", claude, "~/Bare", "resume", "on"]],
            ["no-account", ["build", "", "~/Jarvis", "resume", "on"]], ["no-account", ["start", "cli:" + "0".repeat(32), "~/Jarvis", "resume"]],
            ["not-app", ["start", local, "~/Jarvis", "resume"]]
        ];
        for (const [block, args] of rows) {
            assert.deepEqual(helper(directory, args), { kind: "blocked", block }, block + " " + args[0]);
            assert.equal(calls(folder).some(call => call.argv[0] === "start"), false, block + " starts nothing");
            cases++;
        }
    }
    // Each cause the session row names, as the helper reads it: a status
    // outside the contract reads `unread` with its keyed stderr line, the
    // package's trust question is its own answer with its line unchanged,
    // and a way to the command Jarvis cannot follow, or a command missing
    // from a home Kendex installed or from one VGS made, is its own block,
    // with no run of the command. Every row is read before any is judged,
    // so a run against another tree prints each row it reads. No row reads
    // home-unreadable: the world's user namespace opens a mode 000 folder.
    function causes(directory) {
        const file = path.join(scripts(other), "jarvis-session");
        const trust = "Do you trust the files in this folder?";
        const homes = path.join(home, "causes");
        const at = name => path.join(homes, name);
        fs.rmSync(homes, { recursive: true, force: true });
        // A link on the way to the command.
        fs.mkdirSync(path.join(at("Linked"), ".agents/skills"), { recursive: true });
        fs.symlinkSync(path.join(other, ".agents/skills/jarvis"), path.join(at("Linked"), ".agents/skills/jarvis"));
        // A file where a folder on the way should be.
        fs.mkdirSync(path.join(at("Kind"), ".agents/skills"), { recursive: true });
        fs.writeFileSync(path.join(at("Kind"), ".agents/skills/jarvis"), "");
        // A home Kendex installed, its command with no execute bit.
        fs.mkdirSync(scripts(at("Kendex")), { recursive: true });
        fs.writeFileSync(path.join(at("Kendex"), ".kendex-lock.json"), JSON.stringify({ entries: { jarvis: { kind: "skill", name: "jarvis" } } }));
        fs.copyFileSync(standIn, path.join(scripts(at("Kendex")), "jarvis-session"));
        fs.chmodSync(path.join(scripts(at("Kendex")), "jarvis-session"), 0o644);
        // A home VGS laid out from its render, which ships no command.
        fs.mkdirSync(at("Made"));
        require(path.join(plugin, "backend/Home.js")).layout(at("Made"));
        const statusRows = [
            ["exit-2", { exit: 2, object: { state: "stopped", reason: "never-started" } }, { kind: "blocked", block: "unread" }, "jarvis: session-status=exit=2"],
            ["no-line", { exit: 0, raw: "" }, { kind: "blocked", block: "unread" }, "jarvis: session-status=unaccepted"],
            ["two-lines", { exit: 0, raw: "a\nb\n" }, { kind: "blocked", block: "unread" }, "jarvis: session-status=unaccepted"],
            ["format-version", { exit: 0, object: { state: "stopped", reason: "never-started", v: 2 } }, { kind: "blocked", block: "unread" }, "jarvis: session-status=unaccepted"],
            ["trust-required", { exit: 1, object: { state: "blocked", reason: "trust-required", detail: trust } },
                { kind: "answer", state: "blocked", reason: "trust-required", detail: trust, names: null }, ""]
        ];
        const read = [], expected = [], ran = [];
        for (const [name, entry, reads, line] of statusRows) {
            answers(other, { status: entry });
            read.push([name, helper(directory, ["status", "~/Other"]), errors.split("\n")[0]]);
            expected.push([name, reads, line]);
            ran.push(...calls(other).map(call => call.argv));
        }
        answers(other, { status: said("stopped", "never-started") });
        fs.chmodSync(file, 0o644);
        const homeRows = [["link", "~/causes/Linked", "home-link"], ["kind", "~/causes/Kind", "home-kind"],
            ["kendex-no-execute", "~/causes/Kendex", "package"], ["vgs-no-execute", "~/Other", "vgs-package"], ["vgs-made", "~/causes/Made", "vgs-package"]];
        for (const [name, setting, block] of homeRows) {
            read.push([name, helper(directory, ["status", setting]), errors.split("\n")[0]]);
            expected.push([name, { kind: "blocked", block }, ""]);
        }
        fs.chmodSync(file, 0o755);
        for (const [name, reads, line] of read)
            console.log("test-jarvis-session-control: cause=" + name + " reads=" + JSON.stringify(reads) + " stderr=" + JSON.stringify(line));
        assert.deepEqual(read, expected, "each cause reads its own row");
        assert.deepEqual([ran, calls(other)], [statusRows.map(() => status(other)), []], "one status run a row, and a refused command file is not run");
        fs.rmSync(homes, { recursive: true });
        cases += read.length;
    }
    // The recorded session's account reads by its provider and sign-in
    // email, read now, and by its provider alone while that email is
    // unknown: never by its folder's name, `.1copilot` among them.
    function names(directory) {
        const copilot = path.join(home, ".1copilot");
        fs.mkdirSync(copilot, { recursive: true });
        const rows = [
            ["signed-in", "claude", account, "Claude Code, beijuan@vanillagreen.com"],
            ["signed-out", "claude", path.join(home, ".claude-work"), "Claude Code"],
            ["no-email", "copilot", copilot, "GitHub Copilot"],
            ["unlisted", "other-app", account, "other-app"]
        ];
        for (const [name, harness, directoryOf, label] of rows) {
            answers(folder, { status: said("running", "existing", { home: folder, harness, account: directoryOf }) });
            assert.deepEqual(helper(directory, ["status", "~/Jarvis"]).names, { home: "~/Jarvis", account: label }, name);
            cases++;
        }
        fs.rmSync(copilot, { recursive: true });
    }
    // A start outside the contract is a failure, never a state: a pair the
    // table does not hold, another exit status, two lines, no object.
    function outside(directory) {
        const good = said("stopped", "never-started");
        const rows = [
            ["unknown-pair", { exit: 0, object: { state: "running", reason: "launching" } }],
            ["exit", { exit: 3, object: { state: "running", reason: "resumed" } }],
            ["two-lines", { exit: 0, raw: '{"v":1}\n{"v":1}\n' }],
            ["no-object", { exit: 0, raw: "" }],
            ["no-newline", { exit: 0, raw: '{"v":1,"state":"running","reason":"resumed","home":null,"harness":null,"account":null,"detail":""}' }]
        ];
        for (const [name, start] of rows) {
            answers(folder, { status: good, start });
            assert.deepEqual(helper(directory, ["start", claude, "~/Jarvis", "resume"]), { kind: "failed" }, name);
            cases++;
        }
        // A line the Settings page cannot draw as a hint, or a name with a
        // control character, is outside the contract too.
        const launch = more => ({ exit: 1, object: { state: "failed", reason: "launch-failed", detail: "The app ended.", ...more } });
        for (const [name, more, kind] of [["detail-fits", { detail: "x".repeat(200) }, "answer"], ["detail-long", { detail: "x".repeat(201) }, "failed"],
            ["detail-tab", { detail: "The app\tended." }, "failed"], ["detail-line-separator", { detail: "The app\u2028ended." }, "failed"],
            ["home-control", { home: folder + "\u0007" }, "failed"]]) {
            answers(folder, { status: good, start: launch(more) });
            assert.equal(helper(directory, ["start", claude, "~/Jarvis", "resume"]).kind, kind, name);
            cases++;
        }
        // A refusal's own object is the answer, with its line for the user.
        answers(folder, { status: good, start: { exit: 1, object: { state: "blocked", reason: "sign-in-required", detail: "Sign in to the app." } } });
        const refused = helper(directory, ["start", claude, "~/Jarvis", "resume"]);
        assert.deepEqual([refused.state, refused.reason, refused.detail], ["blocked", "sign-in-required", "Sign in to the app."]);
        cases++;
    }

    // A running session's model and start time pass on as the package
    // gives them; a field it does not give, or gives as null, stays absent.
    function fields(directory) {
        const since = "2026-10-17T11:02:00-07:00";
        answers(folder, { status: said("running", "existing", { home: folder, harness: "claude", account, model: "claude-fable-5-1", since }) });
        const given = helper(directory, ["status", "~/Jarvis"]);
        assert.deepEqual([given.model, given.since], ["claude-fable-5-1", since], "the fields pass on");
        for (const more of [{}, { model: null, since: null }]) {
            answers(folder, { status: said("running", "existing", more) });
            const none = helper(directory, ["status", "~/Jarvis"]);
            assert.deepEqual(["model", "since"].filter(field => Object.hasOwn(none, field)), [], "absent or null stays absent");
        }
        cases++;
    }
    // A field outside the contract makes the whole answer outside it.
    function fieldsOutside(directory) {
        const rows = [
            ["model-empty", { model: "" }], ["model-long", { model: "m".repeat(101) }], ["model-control", { model: "a\u0007" }],
            ["since-not-iso", { since: "11:02" }], ["since-no-zone", { since: "2026-10-17T11:02:00" }], ["since-number", { since: 1 }]
        ];
        for (const [name, more] of rows) {
            answers(folder, { status: said("running", "existing", more) });
            assert.deepEqual(helper(directory, ["status", "~/Jarvis"]), { kind: "blocked", block: "unread" }, name);
            cases++;
        }
        answers(folder, { status: said("running", "existing", { model: "m".repeat(100), since: "2026-10-17T18:02:00.5Z" }) });
        assert.equal(helper(directory, ["status", "~/Jarvis"]).kind, "answer", "the longest model and a UTC time are inside");
        cases++;
    }
    // The package's status names the recorded selection.
    // Empty Account resumes that selection at boot; an explicit
    // Account wins, even when it is invalid. The package owns resume/new.
    function bootResume(directory) {
        const prior = path.join(home, ".codex-prior");
        const history = { home: folder, harness: "codex", account: prior };
        const recordedStart = ["start", "--harness", "codex", "--account", prior, "--mode", "resume", "--origin", "boot", "--home", folder];
        for (const [name, setting, mode, bootSetting, more, words, block] of [
            ["empty Account uses history", "", "resume", "on", history, recordedStart],
            ["selected Account replaces history", claude, "resume", "on", history, startWords("resume", "boot")],
            ["unresolved Account stays blocked", "cli:" + "0".repeat(32), "resume", "on", history, null, "no-account"],
            ["non-app Account stays blocked", local, "resume", "on", history, null, "not-app"],
            ["empty Account without history", "", "resume", "on", {}, null, "no-account"],
            ["empty Account with no recorded account", "", "resume", "on", { ...history, account: null }, null, "no-account"],
            ["new mode requires selection", "", "new", "on", history, null, "no-account"],
            ["selected new mode", claude, "new", "on", history, startWords("new", "boot")],
            ["boot off only reads", "", "resume", "off", history, null]
        ]) {
            answers(folder, { status: said("stopped", "ended", more), start: said("starting", "launching") });
            const result = helper(directory, ["build", setting, "~/Jarvis", mode, bootSetting]);
            assert.deepEqual(calls(folder).map(call => call.argv), words === null ? [status(folder)] : [status(folder), words, status(folder)], name + ": argv");
            assert.deepEqual(block === undefined ? result.kind : result, block === undefined ? "answer" : { kind: "blocked", block }, name + ": result");
        }
        cases++;
    }

    const checks = { boot, bootOff, enable, manual, off, change, changeRefused, blocks, causes, names, outside, fields, fieldsOutside, bootResume };
    const only = process.argv[3];
    if (only !== undefined) {
        assert.ok(Object.hasOwn(checks, only), "no check " + only);
        checks[only](plugin);
        console.log("test-jarvis-session-control: ok check=" + only + " cases=" + cases);
        return;
    }
    for (const check of Object.values(checks)) check(plugin);

    // A copy of the plugin tree FROM with one text of FILE replaced.
    function planted(name, file, needle, replacement, from = plugin) {
        const source = fs.readFileSync(path.join(from, file), "utf8");
        assert.equal(source.split(needle).length - 1, 1, name + " match");
        const copy = path.join(root, name);
        fs.cpSync(from, copy, { recursive: true });
        fs.writeFileSync(path.join(copy, file), source.replace(needle, () => replacement));
        return copy;
    }
    // The stall bound, on a copy whose bound is short: a command that
    // waits on a child holding its output open ends as a failure at the
    // bound, not when that child lets go. Real time, for the timer's wiring.
    const quick = planted("quick-bound", "backend/session-control.js", "const COMMAND_MS = 60000;", "const COMMAND_MS = 400;");
    function stalled(directory) {
        answers(folder, { stop: { ...said("stopping", "stop-requested"), hold: 5 } });
        const from = Date.now();
        assert.deepEqual(helper(directory, ["stop", "~/Jarvis"]), { kind: "failed" });
        assert.ok(Date.now() - from < 3000, "the bound ends the run while a child holds the output: ms=" + (Date.now() - from));
        cases++;
    }
    stalled(quick);
    // A status the bound ends reads `unread`, its keyed line naming the time-out.
    function statusStalled(directory) {
        answers(folder, { status: { ...said("stopped", "never-started"), hold: 5 } });
        assert.deepEqual([helper(directory, ["status", "~/Jarvis"]), errors.split("\n")[0]],
            [{ kind: "blocked", block: "unread" }, "jarvis: session-status=timeout"]);
        cases++;
    }
    statusStalled(quick);

    function control(name, file, needle, replacement, check, from = plugin) {
        const copy = planted("control-" + name, file, needle, replacement, from);
        assert.throws(() => check(copy), error => {
            assert.ok(error instanceof assert.AssertionError, name + " must turn red, not crash: " + error.stack);
            console.log("test-jarvis-session-control: control=" + name + " killed by=" + JSON.stringify(error.message.split("\n")[0]));
            return true;
        });
        controls++;
    }
    const C = "backend/session-control.js";
    const S = "backend/SessionCommand.js";
    control("duplicate-start", C, 'if (started.state === "blocked" || started.state === "failed") return answer(started);',
        'if (started.state === "blocked" || started.state === "failed") return answer(started);\n        await run(at, words);', boot);
    control("boot-setting", C, 'boot === "on" ? "boot" : null', '"boot"', bootOff);
    control("app-on", C, 'now.state === "off" ? "app-on" : ', "", enable);
    control("origin-manual", C, 'verb === "start" ? "manual" : ', "", manual);
    control("mode", C, '"--mode", mode, "--origin", origin]);', '"--mode", "resume", "--origin", origin]);', manual);
    control("environment", S, "const { TMUX, TMUX_PANE, VGSHELL_RUNNER_PID, ...kept } = from;", "const kept = from;", boot);
    control("app-off", C, 'args.length === 2 ? ["--origin", "app-off"] : []', "[]", off);
    control("check-before-stop", C, 'if (probe.kind === "blocked") return { ...await answer(before), unapplied: probe.block };', "", changeRefused);
    control("stop-old-home", C, 'if (await run(from, ["stop"]) === null) return failed;', "", change);
    control("live-only", C, "if (!live) return", "if (false) return", changeRefused);
    control("bound-ends-run", C, "                child.stdout.destroy();\n                outside(\"timeout\");", "", stalled, quick);
    control("old-home-unread", C, 'const before = from.kind === "blocked" ? from : await run(from, ["status"]);',
        'const before = from.kind === "blocked" ? from : await read(from);', changeRefused);
    control("same-selection", C, "if (at.folder === from.folder && before.harness === who.harness && before.account === who.directory) return answer(before);", "", changeRefused);
    control("detail-length", C, " || value.detail.length > DETAIL_MAX", "", outside);
    control("printable", C, "value[field] !== null && UNPRINTABLE.test(value[field])", "false", outside);
    control("contract-pair", C, "|| !STATES[value.state].includes(value.reason)", "", outside);
    control("exit-status", C, "signal === null && (code === 0 || code === 1) ? accepted(out) : null", "accepted(out)", outside);
    control("one-line", C, "if (!/^[^\\n]+\\n$/.test(text)) return null;", "text = text.split(\"\\n\")[0];", outside);
    control("version", C, "|| value.v !== 1", "", causes);
    control("unread-block", C, '?? blocked("unread")', '?? blocked("package")', causes);
    control("keyed-line", C, 'process.stderr.write("jarvis: session-" + words[0] + "=" + cause + "\\n");', "", causes);
    control("trust-state", C, '"app-missing", "trust-required"]', '"app-missing"]', causes);
    control("home-blocks", S, 'if (command.kind !== "absent") return { kind: "blocked", block: BLOCKS[command.kind] };', "", causes);
    control("package-owner", S, 'owner === "kendex" ? "package" : "vgs-package"', '"package"', causes);
    control("account-label", C, "account: await label(value.harness, value.account)", "account: value.account", names);
    control("home-folder", S, "folder === null || !fs.statSync(folder, { throwIfNoEntry: false })?.isDirectory()", "folder === null", blocks);
    control("fields-pass-on", C, '...Object.fromEntries(["model", "since"]', '...Object.fromEntries([]', fields);
    control("model-checked", C, "if (model !== null && !named(model)) return null;", "", fieldsOutside);
    control("since-checked", C, "ISO.test(since)", "true", fieldsOutside);
    control("boot-record-account", C, 'origin === "boot" && mode === "resume" && setting === ""', 'false', bootResume);
    control("not-app", C, 'resolved.source.kind === "cli" ? { harness: resolved.provider, directory: resolved.source.directory } : blocked("not-app")',
        "{ harness: resolved.provider, directory: String(resolved.source.directory) }", blocks);
    // No control plants a file without its execute bit as a package: the
    // start of such a file fails too, so the block reads the same.
    console.log("test-jarvis-session-control: ok cases=" + cases + " controls=" + controls);
}

function main() {
    if (process.argv[2] === "--inside") return inside();
    // The caller's JARVIS_TEST_SCRATCH_ROOT holds the scratch root of an
    // evidence run, as jarvis-env.sh takes it.
    const parent = process.env.JARVIS_TEST_SCRATCH_ROOT ?? require("node:os").tmpdir();
    fs.mkdirSync(parent, { recursive: true });
    const root = fs.realpathSync(fs.mkdtempSync(path.join(parent, "js-")));
    try {
        const standins = path.join(root, "standins");
        fs.mkdirSync(standins);
        // Claude Code's `auth status` (Accounts.js login) for ~/.claude
        // alone; any other folder is signed out.
        fs.writeFileSync(path.join(standins, "claude"), [
            "#!/bin/bash",
            '[[ "$*" == "auth status" ]] || exit 2',
            'if [[ $CLAUDE_CONFIG_DIR == "$HOME/.claude" ]]; then echo \'{"loggedIn":true,"email":"beijuan@vanillagreen.com","subscriptionType":"max"}\'; exit 0; fi',
            "echo '{\"loggedIn\":false}'; exit 1", ""].join("\n"), { mode: 0o755 });
        const result = cp.spawnSync("/bin/bash", [path.join(tree, "scripts/lib/jarvis-env.sh"), standins,
            "--", "node", __filename, "--inside", ...process.argv.slice(2)], {
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
