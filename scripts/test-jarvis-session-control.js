#!/usr/bin/env node
// backend/session-control.js, run as the shell runs it, against a stand-in
// for the Jarvis package's `jarvis-session`
// (scripts/fixtures/jarvis/session-package.py) in a scratch home of the
// J09 world: the stand-in records each call and answers what the case
// wrote, and starts nothing. No package, vendor program, account, tmux
// server or live session. A control runs a private copy of the plugin with
// one planted defect.
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
    // shell restarted from a tmux pane would hand it.
    function helper(directory, args) {
        const result = cp.spawnSync(process.execPath, [path.join(directory, "backend/session-control.js"), "--tree", tree, ...args], {
            env: { ...process.env, XDG_SESSION_ID: "7", TMUX: "/scratch/other,1,0", TMUX_PANE: "%9", VGSHELL_RUNNER_PID: "1" },
            encoding: "utf8", timeout: 30000 });
        assert.equal(result.status, 0, "the helper answers: " + result.stderr);
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
        assert.deepEqual([result.kind, result.state, result.names], ["answer", "running", { home: "~/Jarvis", account: "Claude Code, ~/.claude" }]);
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
        for (const [setting, target, block] of [[local, "~/Jarvis", "not-app"], [claude, "~/Bare", "package"], [claude, "~/Absent", "no-home"]]) {
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
            ["package", ["status", "~/Bare"]], ["package", ["build", claude, "~/Bare", "resume", "on"]],
            ["no-account", ["build", "", "~/Jarvis", "resume", "on"]], ["no-account", ["start", "cli:" + "0".repeat(32), "~/Jarvis", "resume"]],
            ["not-app", ["start", local, "~/Jarvis", "resume"]]
        ];
        for (const [block, args] of rows) {
            assert.deepEqual(helper(directory, args), { kind: "blocked", block }, block + " " + args[0]);
            assert.equal(calls(folder).some(call => call.argv[0] === "start"), false, block + " starts nothing");
            cases++;
        }
    }
    // A command file that is no package: a link on the way, no execute bit,
    // or a status outside the contract.
    function noPackage(directory) {
        const file = path.join(scripts(other), "jarvis-session");
        answers(other, { status: { exit: 0, object: { state: "stopped", reason: "never-started", v: 2 } } });
        assert.deepEqual(helper(directory, ["status", "~/Other"]), { kind: "blocked", block: "package" }, "another format version");
        answers(other, { status: said("stopped", "never-started") });
        fs.chmodSync(file, 0o644);
        assert.deepEqual(helper(directory, ["status", "~/Other"]), { kind: "blocked", block: "package" }, "no execute bit");
        fs.chmodSync(file, 0o755);
        const linked = path.join(home, "Linked");
        fs.mkdirSync(path.join(linked, ".agents/skills"), { recursive: true });
        fs.symlinkSync(path.join(other, ".agents/skills/jarvis"), path.join(linked, ".agents/skills/jarvis"));
        assert.deepEqual(helper(directory, ["status", "~/Linked"]), { kind: "blocked", block: "package" }, "a link on the way");
        assert.deepEqual(calls(other), [], "a refused command file is not run");
        fs.rmSync(linked, { recursive: true });
        cases++;
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

    // A running session's model and start time, and the record saved before
    // a machine restart, pass on as the package gives them; a field it
    // does not give, or gives as null, stays absent.
    const record = { unlock: "1password", steps: [
        { kind: "delegate", name: "jarvis", outcome: "resumed", cause: null },
        { kind: "overseer", name: "vgshell", outcome: "failed", cause: "The app asked for a sign-in." },
        { kind: "lane", name: "VGS-1", outcome: "pending", cause: null }] };
    function fields(directory) {
        const since = "2026-10-17T11:02:00-07:00";
        answers(folder, { status: said("running", "existing", { home: folder, harness: "claude", account, model: "claude-fable-5-1", since, restart: record }) });
        const given = helper(directory, ["status", "~/Jarvis"]);
        assert.deepEqual([given.model, given.since, given.restart], ["claude-fable-5-1", since, record], "the fields pass on");
        for (const more of [{}, { model: null, since: null, restart: null }]) {
            answers(folder, { status: said("running", "existing", more) });
            const none = helper(directory, ["status", "~/Jarvis"]);
            assert.deepEqual(["model", "since", "restart"].filter(field => Object.hasOwn(none, field)), [], "absent or null stays absent");
        }
        cases++;
    }
    // A field outside the contract makes the whole answer outside it.
    function fieldsOutside(directory) {
        const step = more => ({ restart: { unlock: null, steps: [{ kind: "lane", name: "VGS-1", outcome: "pending", cause: null, ...more }] } });
        const rows = [
            ["model-empty", { model: "" }], ["model-long", { model: "m".repeat(101) }], ["model-control", { model: "a\u0007" }],
            ["since-not-iso", { since: "11:02" }], ["since-no-zone", { since: "2026-10-17T11:02:00" }], ["since-number", { since: 1 }],
            ["unlock", { restart: { unlock: "keyring", steps: [] } }], ["steps-missing", { restart: { unlock: null } }],
            ["steps-many", { restart: { unlock: null, steps: Array(33).fill({ kind: "lane", name: "x", outcome: "pending", cause: null }) } }],
            ["step-kind", step({ kind: "task" })], ["step-name", step({ name: "" })], ["step-outcome", step({ outcome: "done" })],
            ["step-cause-control", step({ cause: "a\nb" })], ["step-cause-number", step({ cause: 1 })], ["unlock-number", { restart: { unlock: 1, steps: [] } }]
        ];
        for (const [name, more] of rows) {
            answers(folder, { status: said("running", "existing", more) });
            assert.deepEqual(helper(directory, ["status", "~/Jarvis"]), { kind: "blocked", block: "package" }, name);
            cases++;
        }
        answers(folder, { status: said("running", "existing", { model: "m".repeat(100), since: "2026-10-17T18:02:00.5Z" }) });
        assert.equal(helper(directory, ["status", "~/Jarvis"]).kind, "answer", "the longest model and a UTC time are inside");
        // A nested field the package does not give is null, as a top-level
        // one is: a record with no `unlock`, a step with no `cause`.
        answers(folder, { status: said("stopped", "ended", { restart: { steps: [{ kind: "lane", name: "x", outcome: "pending" }] } }) });
        assert.deepEqual(helper(directory, ["status", "~/Jarvis"]).restart, { unlock: null, steps: [{ kind: "lane", name: "x", outcome: "pending", cause: null }] },
            "an absent unlock and cause read as null");
        cases++;
    }
    // The Resume: one `resume --origin manual` in the home, then a status
    // read; it names no account.
    function resume(directory) {
        answers(folder, { resume: said("starting", "resuming"), status: said("starting", "resuming", { restart: record }) });
        const result = helper(directory, ["resume", "~/Jarvis"]);
        assert.deepEqual([result.state, result.reason, result.restart], ["starting", "resuming", record]);
        assert.deepEqual(calls(folder).map(call => call.argv), [["resume", "--origin", "manual", "--home", folder], status(folder)]);
        cases++;
    }
    // Do not resume: one `dismiss` in the home, whose answer, the session
    // without its record, is the session; a package that refuses the verb,
    // as one without `dismiss` does, is a failed call.
    function dismiss(directory) {
        answers(folder, { dismiss: said("stopped", "ended"), status: said("stopped", "ended", { restart: record }) });
        const result = helper(directory, ["dismiss", "~/Jarvis"]);
        assert.deepEqual([result.kind, result.state, result.reason, Object.hasOwn(result, "restart")], ["answer", "stopped", "ended", false]);
        assert.deepEqual(calls(folder).map(call => call.argv), [["dismiss", "--home", folder]]);
        // The package's refusals, exit 1 with its contract object, and an
        // unknown verb, exit 2: each keeps the record.
        for (const [label, refusal] of [
            ["an unknown verb", undefined],
            ["a record it cannot read", { exit: 1, object: { state: "blocked", reason: "record-unreadable" } }],
            ["a failed state", { exit: 1, object: { state: "failed", reason: "launch-failed", restart: record } }],
            ["an answer that keeps the record", { exit: 1, object: { state: "stopped", reason: "ended", restart: record } }]]) {
            answers(folder, { status: said("stopped", "ended", { restart: record }), ...(refusal === undefined ? {} : { dismiss: refusal }) });
            assert.deepEqual(helper(directory, ["dismiss", "~/Jarvis"]), { kind: "failed" }, label + ": a dismiss not done");
        }
        cases++;
    }
    // At boot with Resume the last session, a record saved before a machine
    // restart is resumed instead of a start; with Start a new session, or
    // with no record, the boot starts as before.
    function bootResume(directory) {
        const stopped = more => said("stopped", "ended", more);
        answers(folder, { status: stopped({ restart: record }), resume: said("starting", "resuming"), start: said("starting", "launching") });
        helper(directory, ["build", claude, "~/Jarvis", "resume", "on"]);
        assert.deepEqual(calls(folder).map(call => call.argv), [status(folder), ["resume", "--origin", "boot", "--home", folder], status(folder)], "a record resumes");
        answers(folder, { status: stopped({ restart: record }), resume: said("starting", "resuming"), start: said("starting", "launching") });
        helper(directory, ["build", claude, "~/Jarvis", "new", "on"]);
        assert.deepEqual(calls(folder).map(call => call.argv), [status(folder), startWords("new", "boot"), status(folder)], "a new session starts");
        answers(folder, { status: stopped({ restart: record }), resume: said("starting", "resuming") });
        helper(directory, ["build", claude, "~/Jarvis", "resume", "off"]);
        assert.deepEqual(calls(folder).map(call => call.argv), [status(folder)], "with the boot setting off a build only reads");
        // A shell restart while the resume runs, or after it, resumes nothing
        // again: the boot start, which the package handles once a boot.
        for (const live of [said("starting", "resuming", { restart: record }), said("running", "restart-resumed", { restart: record })]) {
            answers(folder, { status: live, resume: said("starting", "resuming"), start: said("starting", "launching") });
            helper(directory, ["build", claude, "~/Jarvis", "resume", "on"]);
            assert.deepEqual(calls(folder).map(call => call.argv), [status(folder), startWords("resume", "boot"), status(folder)], live.object.reason + ": no second resume");
        }
        cases++;
    }

    const checks = { boot, bootOff, enable, manual, off, change, changeRefused, blocks, noPackage, outside, fields, fieldsOutside, resume, dismiss, bootResume };
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
    control("check-before-stop", C, 'if (probe.kind === "blocked") return { ...answer(before), unapplied: probe.block };', "", changeRefused);
    control("stop-old-home", C, 'if (await run(from, ["stop"]) === null) return failed;', "", change);
    control("live-only", C, "if (!live) return", "if (false) return", changeRefused);
    control("bound-ends-run", C, "                child.stdout.destroy();\n                end(null);", "", stalled, quick);
    control("old-home-unread", C, 'const before = from.kind === "blocked" ? from : await run(from, ["status"]);',
        'const before = from.kind === "blocked" ? from : await read(from);', changeRefused);
    control("same-selection", C, "if (at.folder === from.folder && before.harness === who.harness && before.account === who.directory) return answer(before);", "", changeRefused);
    control("detail-length", C, " || value.detail.length > DETAIL_MAX", "", outside);
    control("printable", C, "value[field] !== null && UNPRINTABLE.test(value[field])", "false", outside);
    control("contract-pair", C, "|| !STATES[value.state].includes(value.reason)", "", outside);
    control("exit-status", C, "signal === null && (code === 0 || code === 1) ? accepted(out) : null", "accepted(out)", outside);
    control("one-line", C, "if (!/^[^\\n]+\\n$/.test(text)) return null;", "text = text.split(\"\\n\")[0];", outside);
    control("version", C, "|| value.v !== 1", "", noPackage);
    control("home-folder", S, "folder === null || !fs.statSync(folder, { throwIfNoEntry: false })?.isDirectory()", "folder === null", blocks);
    control("fields-pass-on", C, '...Object.fromEntries(["model", "since", "restart"]', '...Object.fromEntries([]', fields);
    control("model-checked", C, "if (model !== null && !named(model)) return null;", "", fieldsOutside);
    control("nested-absent-refused", C, 'const cause = given(step, "cause");', "const cause = step.cause;", fieldsOutside);
    control("since-checked", C, "ISO.test(since)", "true", fieldsOutside);
    control("step-checked", C, "|| !OUTCOMES.includes(step.outcome)", "", fieldsOutside);
    control("resume-origin", C, 'launch(at, ["resume", "--origin", "manual"])', 'launch(at, ["resume", "--origin", "boot"])', resume);
    control("dismiss-refusal", C, '["blocked", "failed"].includes(dismissed.state) || ', "", dismiss);
    control("dismiss-kept-record", C, " || dismissed.restart !== null) return failed;", ") return failed;", dismiss);
    control("dismiss-verb", C, 'const dismissed = await run(at, ["dismiss"]);', 'const dismissed = await run(at, ["status"]);', dismiss);
    control("boot-resume", C, 'if (origin === "boot" && mode === "resume" && now.restart !== null && !LIVE.includes(now.state)) return launch(at, ["resume", "--origin", "boot"]);', "", bootResume);
    control("boot-resume-mode", C, 'origin === "boot" && mode === "resume" && now.restart !== null', 'origin === "boot" && now.restart !== null', bootResume);
    control("boot-resume-live", C, "now.restart !== null && !LIVE.includes(now.state)", "now.restart !== null", bootResume);
    control("not-app", C, 'resolved.source.kind === "cli" ? { harness: resolved.provider, directory: resolved.source.directory } : blocked("not-app")',
        "{ harness: resolved.provider, directory: String(resolved.source.directory) }", blocks);
    // No control plants a file without its execute bit as a package: the
    // start of such a file fails too, so the block reads the same.
    console.log("test-jarvis-session-control: ok cases=" + cases + " controls=" + controls);
}

function main() {
    if (process.argv[2] === "--inside") return inside();
    const parent = require("node:os").tmpdir();
    const root = fs.realpathSync(fs.mkdtempSync(path.join(parent, "js-")));
    try {
        const standins = path.join(root, "standins");
        fs.mkdirSync(standins);
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
