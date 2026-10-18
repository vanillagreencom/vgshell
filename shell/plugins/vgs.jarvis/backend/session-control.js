#!/usr/bin/env node
// session-control.js --tree ABSOLUTE_VGS_TREE VERB ARGS..., the one caller
// of the Jarvis package's session command, `jarvis-session` in the home
// folder (Home.sessionCommand). The package owns the user's Jarvis session:
// its record, its tmux session, resume and hand-over. This file starts no
// program but that command, and reads no answer but its contract's.
// ACCOUNT is the plugin's `brain` setting, HOME its `home` setting, MODE
// "resume" or "new".
//   status HOME                      reads the session; starts nothing
//   build ACCOUNT HOME MODE BOOT     the service's build: `start --origin
//                                    app-on` after the app's Off, else
//                                    while BOOT is "on" `resume --origin
//                                    boot` when MODE is "resume", no
//                                    session lives and the package holds a
//                                    record saved before a machine
//                                    restart, else `start --origin boot`;
//                                    else a status read
//   start ACCOUNT HOME MODE          `start --origin manual`
//   resume HOME                      `resume --origin manual`: the record
//                                    saved before a machine restart
//   dismiss HOME                     `dismiss`: the package drops that
//                                    record and answers the session as
//                                    `status` does; a refusal (exit 1),
//                                    an answer that keeps the record or
//                                    no answer is `failed`
//   change OLD ACCOUNT HOME MODE     a changed account or home: while a
//                                    session lives in OLD, checks the new
//                                    selection, stops the old session and
//                                    starts the new one; else a status read
//   stop HOME [app-off]              `stop`, with the app's Off recorded
// The package's `prepare` before a machine restart is power-wait.js's call.
// Each verb prints one JSON line and exits 0:
//   { kind: "answer", state, reason, detail, names: { home, account } }
//     the package's answer, names those of the recorded session or null;
//     `model`, `since` and `restart` are added as the package gives them
//     (accepted); `unapplied`, a block, is added when the selection failed
//     its check and the session that lives stays as it is
//   { kind: "blocked", block }  "no-account", "not-app", "no-home" or
//     "package": no call can be made
//   { kind: "failed" }  the command ran outside its contract
// Arguments it cannot read exit 2 with a keyed line.
"use strict";
const cp = require("node:child_process");
const path = require("node:path");

// The contract's closed table: each state with its reasons.
const STATES = Object.freeze({
    running: ["resumed", "restart-resumed", "new-no-record", "new-history-gone", "new-selection-changed", "new-requested", "existing"],
    starting: ["launching", "resuming"],
    "handing-over": ["succession"],
    stopping: ["stop-requested"],
    stopped: ["never-started", "stopped", "ended"],
    off: ["app-off"],
    blocked: ["app-off", "name-conflict", "record-unreadable", "sign-in-required", "selection-conflict", "tmux-missing", "app-missing"],
    failed: ["launch-failed", "handover-failed"]
});
const LIVE = ["running", "starting", "handing-over"];
// One command run: a bound on a stalled command, not a latency budget.
const COMMAND_MS = 60000;
const OUTPUT_BYTES = 16384;
// The contract's `detail`: empty, or one printable line the Settings page
// can draw as a row's hint (PluginLogic STATUS_HINT_MAX). The names it
// draws, `home`, `harness` and `account`, are printable too.
// What that page draws as one line (SettingValues.CONTROL_OR_SEPARATOR).
const UNPRINTABLE = /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/;
const DETAIL_MAX = 200;
// The optional fields of a running session and of the record saved before
// a machine restart. A model or a step's name draws as one line with its
// label in a status line or the bar's tooltip (PluginLogic
// STATUS_TEXT_MAX); a step's cause is a line as `detail` is.
const NAME_MAX = 100;
const STEPS_MAX = 32;
// `since` names an instant: a time with no offset or Z could be any zone's.
// A value outside these forms puts the whole answer outside the contract,
// as any other field does: the package then is not one VGS was written for.
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?(Z|[+-]\d{2}:\d{2})$/;
const UNLOCKS = [null, "1password"];
const STEP_KINDS = ["delegate", "overseer", "lane"];
const OUTCOMES = ["pending", "resumed", "failed"];

const line = (text, max) => typeof text === "string" && text.length <= max && !UNPRINTABLE.test(text);
const named = text => line(text, NAME_MAX) && text !== "";

// OBJECT's FIELD, null where the package does not give it: an optional
// field may be absent or null alike, at any depth.
const given = (object, field) => object[field] === undefined ? null : object[field];

/**
 * RECORD, the `restart` field of an answer, as the plain record VGS
 * passes on, or undefined when it is outside the contract: `unlock` null
 * or "1password", and each step its kind, name, outcome and cause, the
 * cause null or a line. An absent `unlock` or `cause` is null.
 */
function restartOf(record) {
    if (record === null || typeof record !== "object" || Array.isArray(record) || !UNLOCKS.includes(given(record, "unlock"))
            || !Array.isArray(record.steps) || record.steps.length > STEPS_MAX) return undefined;
    const steps = [];
    for (const step of record.steps) {
        if (step === null || typeof step !== "object" || Array.isArray(step) || !STEP_KINDS.includes(step.kind) || !named(step.name)
                || !OUTCOMES.includes(step.outcome)) return undefined;
        const cause = given(step, "cause");
        if (cause !== null && !line(cause, DETAIL_MAX)) return undefined;
        steps.push({ kind: step.kind, name: step.name, outcome: step.outcome, cause });
    }
    return { unlock: given(record, "unlock"), steps };
}

/** The contract's one object from a run's stdout, or null for anything else. */
function accepted(text) {
    if (!/^[^\n]+\n$/.test(text)) return null;
    let value;
    try { value = JSON.parse(text); } catch { return null; }
    const optional = field => value[field] === null || typeof value[field] === "string";
    if (value === null || typeof value !== "object" || Array.isArray(value) || value.v !== 1
            || !Object.hasOwn(STATES, value.state) || !STATES[value.state].includes(value.reason)
            || !["home", "harness", "account"].every(optional) || typeof value.detail !== "string" || value.detail.length > DETAIL_MAX
            || ["home", "harness", "account", "detail"].some(field => value[field] !== null && UNPRINTABLE.test(value[field]))) return null;
    const model = given(value, "model");
    const since = given(value, "since");
    if (model !== null && !named(model)) return null;
    if (since !== null && !(typeof since === "string" && ISO.test(since) && Number.isFinite(Date.parse(since)))) return null;
    const restart = given(value, "restart") === null ? null : restartOf(value.restart);
    if (restart === undefined) return null;
    return { ...value, model, since, restart };
}

async function main() {
    const [flag, tree, verb, ...args] = process.argv.slice(2);
    const shapes = { status: 1, build: 4, start: 3, resume: 1, dismiss: 1, change: 4, stop: [1, 2] };
    if (flag !== "--tree" || !path.isAbsolute(tree || "") || !Object.hasOwn(shapes, verb)
            || ![].concat(shapes[verb]).includes(args.length)
            || (verb === "build" && !["on", "off"].includes(args[3]))
            || (["build", "start"].includes(verb) && !["resume", "new"].includes(args[2]))
            || (verb === "change" && !["resume", "new"].includes(args[3]))
            || (verb === "stop" && args.length === 2 && args[1] !== "app-off")) {
        process.stderr.write("jarvis: session-control=arguments\n");
        return 2;
    }
    require("./Core.js").use(tree);
    const { Accounts, provider } = require("./Accounts.js");
    const SessionCommand = require("./SessionCommand.js");
    const user = process.env.HOME;
    const environment = SessionCommand.environment(process.env);

    const blocked = block => ({ kind: "blocked", block });
    const short = value => value === user || value.startsWith(user + "/") ? "~" + value.slice(user.length) : value;
    // The optional fields are passed on only as the package gives them.
    const answer = value => ({ kind: "answer", state: value.state, reason: value.reason, detail: value.detail,
        names: value.home === null || value.harness === null || value.account === null ? null
            : { home: short(value.home), account: provider(value.harness).label + ", " + short(value.account) },
        ...Object.fromEntries(["model", "since", "restart"].filter(field => value[field] !== null).map(field => [field, value[field]])) });

    // The home folder a setting names with its session command, or a block.
    const place = setting => SessionCommand.place(setting, user);
    // The app account a setting names, or a block.
    function account(setting) {
        const state = path.join(process.env.XDG_STATE_HOME || path.join(user, ".local/state"), "vgshell/jarvis");
        const resolved = setting === "" ? null : new Accounts(state, process.env).resolve(setting);
        if (resolved === null) return blocked("no-account");
        return resolved.source.kind === "cli" ? { harness: resolved.provider, directory: resolved.source.directory } : blocked("not-app");
    }
    // One run of the command by argument list in its home: { code, value },
    // the exit status, 0 or 1, and the contract's object, else null. The
    // bound ends the run itself: a program the command started can hold its
    // output open past the command's own end, and `close` waits for that.
    function exited(at, words) {
        return new Promise(resolve => {
            const child = cp.spawn(at.command, words.concat(["--home", at.folder]), { cwd: at.folder, env: environment, stdio: ["ignore", "pipe", "ignore"] });
            let out = "";
            let ended = false;
            const end = value => {
                if (ended) return;
                ended = true;
                clearTimeout(timer);
                resolve(value);
            };
            const timer = setTimeout(() => {
                child.kill("SIGKILL");
                child.stdout.destroy();
                end(null);
            }, COMMAND_MS);
            child.stdout.setEncoding("utf8");
            child.stdout.on("data", text => { if (out.length <= OUTPUT_BYTES) out += text; });
            child.on("error", () => end(null));
            child.on("close", (code, signal) => {
                const value = signal === null && (code === 0 || code === 1) ? accepted(out) : null;
                end(value === null ? null : { code, value });
            });
        });
    }
    // The contract's object of one run, exit 0 and exit 1 alike, else null.
    const run = async (at, words) => (await exited(at, words))?.value ?? null;
    const failed = { kind: "failed" };
    // The session as the command reads it now; a status outside the
    // contract is no package VGS can use.
    const read = async at => await run(at, ["status"]) ?? blocked("package");
    // A `start` or `resume`, WORDS, then the session as it is after it. A
    // refusal's own object is the answer.
    async function launch(at, words) {
        const started = await run(at, words);
        if (started === null) return failed;
        if (started.state === "blocked" || started.state === "failed") return answer(started);
        const after = await run(at, ["status"]);
        return after === null ? failed : answer(after);
    }
    const start = (at, who, mode, origin) => launch(at, ["start", "--harness", who.harness, "--account", who.directory, "--mode", mode, "--origin", origin]);
    const shown = value => value.kind === "blocked" ? value : answer(value);

    if (verb === "stop") {
        const at = place(args[0]);
        if (at.kind === "blocked") return at;
        const stopped = await run(at, ["stop"].concat(args.length === 2 ? ["--origin", "app-off"] : []));
        return stopped === null ? failed : answer(stopped);
    }
    if (verb === "status") {
        const at = place(args[0]);
        return at.kind === "blocked" ? at : shown(await read(at));
    }
    if (verb === "resume") {
        const at = place(args[0]);
        return at.kind === "blocked" ? at : launch(at, ["resume", "--origin", "manual"]);
    }
    if (verb === "dismiss") {
        const at = place(args[0]);
        if (at.kind === "blocked") return at;
        const dismissed = await exited(at, ["dismiss"]);
        // The package refuses with exit 1 and its contract object (session.py
        // main), and an unknown verb exits 2. Exit 0 answers the session as
        // `status` does, a `failed` one from an earlier start included, and
        // carries no record once the record is dropped.
        if (dismissed === null || dismissed.code !== 0 || dismissed.value.restart !== null) return failed;
        return answer(dismissed.value);
    }
    if (verb === "change") {
        const [old, setting, home, mode] = args;
        const from = place(old);
        const before = from.kind === "blocked" ? from : await run(from, ["status"]);
        // A command that does not answer says nothing of its session: the
        // session may live, so it is not passed over as absent.
        if (before === null) return failed;
        const at = place(home);
        const live = before.kind !== "blocked" && LIVE.includes(before.state);
        if (!live) return at.kind === "blocked" ? at : shown(await read(at));
        // The new selection is checked whole before the old session ends.
        const who = account(setting);
        const probe = at.kind === "blocked" ? at : who.kind === "blocked" ? who : await read(at);
        if (probe.kind === "blocked") return { ...answer(before), unapplied: probe.block };
        // The selection the session already runs on, as after a refused
        // selection is taken back, replaces nothing.
        if (at.folder === from.folder && before.harness === who.harness && before.account === who.directory) return answer(before);
        if (await run(from, ["stop"]) === null) return failed;
        return start(at, who, mode, "manual");
    }
    const [setting, home, mode, boot] = args;
    const at = place(home);
    if (at.kind === "blocked") return at;
    const now = await read(at);
    if (now.kind === "blocked") return now;
    // The plugin is built, so an Off the app recorded is over: its user
    // turned Jarvis on again.
    const origin = verb === "start" ? "manual" : now.state === "off" ? "app-on" : boot === "on" ? "boot" : null;
    if (origin === null) return answer(now);
    // The record names the app of each session it resumes, so a resume
    // takes no account. A session that lives, a resume's among them, is not
    // resumed again; the package handles `start --origin boot` once a boot.
    if (origin === "boot" && mode === "resume" && now.restart !== null && !LIVE.includes(now.state)) return launch(at, ["resume", "--origin", "boot"]);
    const who = account(setting);
    if (who.kind !== "blocked") return start(at, who, mode, origin);
    // A session that lives, one started by hand among them, stays shown.
    return LIVE.includes(now.state) ? { ...answer(now), unapplied: who.block } : who;
}

main().then(value => {
    if (typeof value === "number") { process.exitCode = value; return; }
    process.stdout.write(JSON.stringify(value) + "\n");
}, error => {
    process.stderr.write(error.message.split("\n")[0] + "\n");
    process.exitCode = 1;
});
