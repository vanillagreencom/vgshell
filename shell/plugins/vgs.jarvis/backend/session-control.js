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
//                                    while BOOT is "on" `start --origin
//                                    boot`; MODE "resume" with ACCOUNT
//                                    empty uses the record's harness and
//                                    account;
//                                    else a status read
//   start ACCOUNT HOME MODE          `start --origin manual`
//   change OLD ACCOUNT HOME MODE     a changed account or home: while a
//                                    session lives in OLD, checks the new
//                                    selection, stops the old session and
//                                    starts the new one; else a status read
//   stop HOME [app-off]              `stop`, with the app's Off recorded
// Each verb prints one JSON line and exits 0:
//   { kind: "answer", state, reason, detail, names: { home, account } }
//     the package's answer, names those of the recorded session or null:
//     `home` as ~/path, `account` as the Jarvis page labels it, its
//     provider and sign-in email (Accounts.js accountLabel), read now;
//     `model` and `since` are added as the package gives them
//     (accepted); `unapplied`, a block, is added when the selection failed
//     its check and the session that lives stays as it is
//   { kind: "blocked", block }  "no-account", "not-app", "no-home",
//     "package", "not-set-up", "home-link", "home-kind" or
//     "home-unreadable" (SessionCommand.place): no call can be made; or
//     "unread": the command's status ran outside its contract
//   { kind: "failed" }  the command ran outside its contract
// A run outside the contract, an exit other than 0 or 1, a signal, the
// time-out, a command that would not start, no line or more than one, or
// an answer outside the table, writes one keyed line to stderr,
// `jarvis: session-<verb>=timeout|exit=N|signal|spawn|unaccepted`, VERB
// the command's: SessionStart.qml logs its first. An account whose label
// cannot be read writes `jarvis: session-account=<reason>` and reads by
// its provider alone. Arguments it cannot read exit 2 with a keyed line.
"use strict";
const cp = require("node:child_process");
const path = require("node:path");

// The contract's closed table: each state with its reasons.
const STATES = Object.freeze({
    running: ["resumed", "new-no-record", "new-history-gone", "new-selection-changed", "new-requested", "existing"],
    starting: ["launching", "resuming"],
    "handing-over": ["succession"],
    stopping: ["stop-requested"],
    stopped: ["never-started", "stopped", "ended"],
    off: ["app-off"],
    blocked: ["app-off", "name-conflict", "record-unreadable", "sign-in-required", "selection-conflict", "tmux-missing", "app-missing", "trust-required"],
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
// A model draws as one line with its label in a status line or the bar's
// tooltip (PluginLogic STATUS_TEXT_MAX).
const NAME_MAX = 100;
// `since` names an instant: a time with no offset or Z could be any zone's.
// A value outside these forms puts the whole answer outside the contract,
// as any other field does: the package then is not one VGS was written for.
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?(Z|[+-]\d{2}:\d{2})$/;

const line = (text, max) => typeof text === "string" && text.length <= max && !UNPRINTABLE.test(text);
const named = text => line(text, NAME_MAX) && text !== "";

// OBJECT's FIELD, null where the package does not give it: an optional
// field may be absent or null alike.
const given = (object, field) => object[field] === undefined ? null : object[field];

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
    return { ...value, model, since };
}

async function main() {
    const [flag, tree, verb, ...args] = process.argv.slice(2);
    const shapes = { status: 1, build: 4, start: 3, change: 4, stop: [1, 2] };
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
    const { Accounts, accountLabel } = require("./Accounts.js");
    const SessionCommand = require("./SessionCommand.js");
    const user = process.env.HOME;
    const environment = SessionCommand.environment(process.env);

    const blocked = block => ({ kind: "blocked", block });
    const short = value => value === user || value.startsWith(user + "/") ? "~" + value.slice(user.length) : value;
    const state = path.join(process.env.XDG_STATE_HOME || path.join(user, ".local/state"), "vgshell/jarvis");
    // The recorded session's account by its label. The label is a name to
    // show, so an account it cannot read still shows the session.
    async function label(harness, directory) {
        try { return await new Accounts(state, process.env).label(harness, directory); }
        catch (error) {
            const key = /^jarvis-accounts: ([a-z=-]+)/.exec(error.message);
            if (key === null) throw error;
            process.stderr.write("jarvis: session-account=" + key[1] + "\n");
            return accountLabel({ provider: harness, source: { kind: "cli" }, email: "" });
        }
    }
    // The optional fields are passed on only as the package gives them.
    const answer = async value => ({ kind: "answer", state: value.state, reason: value.reason, detail: value.detail,
        names: value.home === null || value.harness === null || value.account === null ? null
            : { home: short(value.home), account: await label(value.harness, value.account) },
        ...Object.fromEntries(["model", "since"].filter(field => value[field] !== null).map(field => [field, value[field]])) });

    // The home folder a setting names with its session command, or a block.
    const place = setting => SessionCommand.place(setting, user);
    // The app account a setting names, or a block.
    function account(setting) {
        const resolved = setting === "" ? null : new Accounts(state, process.env).resolve(setting);
        if (resolved === null) return blocked("no-account");
        return resolved.source.kind === "cli" ? { harness: resolved.provider, directory: resolved.source.directory } : blocked("not-app");
    }
    // One run of the command by argument list in its home: the contract's
    // object for exit 0 or 1, else null, whose cause goes to stderr as its
    // keyed line. The bound ends the run itself: a program the command
    // started can hold its output open past
    // the command's own end, and `close` waits for that.
    function run(at, words) {
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
            const outside = cause => {
                if (!ended) process.stderr.write("jarvis: session-" + words[0] + "=" + cause + "\n");
                end(null);
            };
            const timer = setTimeout(() => {
                child.kill("SIGKILL");
                child.stdout.destroy();
                outside("timeout");
            }, COMMAND_MS);
            child.stdout.setEncoding("utf8");
            child.stdout.on("data", text => { if (out.length <= OUTPUT_BYTES) out += text; });
            child.on("error", () => outside("spawn"));
            child.on("close", (code, signal) => {
                const value = signal === null && (code === 0 || code === 1) ? accepted(out) : null;
                if (value !== null) end(value);
                else outside(signal !== null ? "signal" : code !== 0 && code !== 1 ? "exit=" + code : "unaccepted");
            });
        });
    }
    const failed = { kind: "failed" };
    // The session as the command reads it now; a status outside the
    // contract reads `unread`.
    const read = async at => await run(at, ["status"]) ?? blocked("unread");
    // A `start`, WORDS, then the session as it is after it. A
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
        if (probe.kind === "blocked") return { ...await answer(before), unapplied: probe.block };
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
    // An explicit selection wins over history; the package's start judges
    // whether that selection can resume. With no selection, boot resume
    // uses the record's app and account (jarvis-session start --help).
    const who = origin === "boot" && mode === "resume" && setting === ""
            && now.harness !== null && now.harness !== "" && now.account !== null && now.account !== ""
        ? { harness: now.harness, directory: now.account } : account(setting);
    if (who.kind !== "blocked") return start(at, who, mode, origin);
    // A session that lives, one started by hand among them, stays shown.
    return LIVE.includes(now.state) ? { ...await answer(now), unapplied: who.block } : who;
}

main().then(value => {
    if (typeof value === "number") { process.exitCode = value; return; }
    process.stdout.write(JSON.stringify(value) + "\n");
}, error => {
    process.stderr.write(error.message.split("\n")[0] + "\n");
    process.exitCode = 1;
});
