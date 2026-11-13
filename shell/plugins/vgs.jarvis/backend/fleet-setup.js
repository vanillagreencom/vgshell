#!/usr/bin/env node
// The Jarvis home's package routes, each run from its TUI in the terminal
// the user sees, under the shared lock and the descendant-safe PID lease,
// and the read-only probes beside them. kendex is the one writer of the
// Jarvis package (D126):
//   setup   makes the Home folder a new Jarvis home, on a computer whose
//           Main Jarvis host is empty: the dedicated folder, git init,
//           `kendex add vanillagreencom/kendex --bundle jarvis`, then the
//           package's `jarvis-session init`
//   clone   makes the Home folder a private clone of the main home for a
//           second computer: git clone without a checkout, a refusal of a
//           history that holds the private env file, the checkout,
//           `kendex guard install`, init's state folder, then
//           `jarvis-session main-host --set`, read back with --get
//   repair  refreshes the home's packages through kendex: Repair and the
//           package update alike
//   plan    prints the steps setup or a clone runs, one command a line,
//           for the TUI to show before the user confirms
// Each step but init and the main-host read-back keeps the terminal's input
// and output: git and kendex write there, and git uses the user's SSH
// agent or asks there for an SSH passphrase. The plan the user confirmed
// names kendex add's --yes, which skips kendex's confirmation prompts, and
// its --allow-repo-effects, which says yes to the repository changes the
// package declares, its hooks among them: that one confirmation answers
// both of kendex's questions. The two
// piped steps' reports are read, not shown, and their stderr reaches the
// terminal once each ends.
// Every refusal is one keyed line, `jarvis: fleet-setup=<key> ...`, on
// stderr, and exits 1: arguments exits 2, and credentials-committed 3, so
// the TUI can say that nothing of the main home stayed. Success is read back from the
// home, never taken from an exit.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");
const Home = require("./Home.js");

// The marketplace and bundle that hold the Jarvis package.
const MARKETPLACE = "vanillagreencom/kendex";
const BUNDLE = "jarvis";
// The flags the home's package commands take: kendex writes and leaves its
// files as diffs for the user to commit. A new folder holds no harness
// folder for kendex to find, and kendex then installs nothing ("nothing
// would be installed — no tool is on this machine and this scope names
// none", kendex 1.20.0 in a fresh HOME, 2026-11-08), so the harnesses are
// named: the two whose folders a Jarvis home keeps (home-layout.md).
// --yes alone still asks before the repository changes the packages
// declare, and with no terminal to ask kendex makes none of them;
// --allow-repo-effects is kendex's own yes (kendex 1.20.0, `confirm` in
// crates/cli/src/commands/repo_effects.rs).
const ADD = ["add", MARKETPLACE, "--bundle", BUNDLE, "--harness", "claude,codex", "--yes", "--allow-repo-effects", "--leave"];
// The update a refresh remedy names, written for the selected home: no
// --yes, --discard-edits or global write (D126).
const REFRESH = folder => ["refresh", "--scope", "project", "--project-path", folder, "--leave"];
// The transports a clone may take its source over: git's ext and other
// helpers run commands of the source's choosing (git(1) GIT_ALLOW_PROTOCOL).
const CLONE_PROTOCOLS = "ssh:https:file";
// A clone source: a URL, an scp-like host:path or a local path, as one
// printable word that git cannot read as an option.
const CLONE_SOURCE = /^[^\s\x00-\x1f\x7f-][^\s\x00-\x1f\x7f]{0,1023}$/;
// The private env file kendex makes in a home (home-layout.md): it holds
// credentials and never travels in the clone.
const PRIVATE_ENV = ".env.local";
// The bound of a git probe: a recovery bound, not a measured latency.
const PROBE_MS = 30000;
// A step's bound: kendex fetches the marketplace and git the clone.
const STEP_MS = 600000;

function environment(source, extra = []) {
    const env = { PATH: source.PATH || "/usr/bin:/bin", LANG: "C.UTF-8", HOME: source.HOME };
    for (const key of ["XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR", "TERM", ...extra])
        if (source[key]) env[key] = source[key];
    return env;
}

function locked(tree, folder, verb, args, source, signal) {
    // The clone hands the user's SSH agent to git clone.
    const env = environment(source, verb === "clone-worker" ? ["SSH_AUTH_SOCK"] : []);
    const runtime = env.XDG_RUNTIME_DIR || "/run/user/" + process.getuid();
    return leased("host", [process.execPath, __filename, "--tree", tree, verb, folder, ...args], {
        env, cwd: path.dirname(folder), signal, terminal: true,
        prefix: ["flock", "--no-fork", "-n", "-E", "75", path.join(runtime, "vgs-tui-jarvis-fleet-setup.lock")]
    });
}

function leased(mode, command, { env, cwd, signal, terminal = false, output, deadline = STEP_MS, prefix = [] }) {
    const argv = ["python3", "-I", path.join(__dirname, "audio-child.py"), mode, String(process.pid), ...command];
    if (mode !== "host") argv.unshift("setpriv", "--pdeathsig", "KILL", "--");
    argv.unshift(...prefix);
    return require("./Child.js").run(argv[0], argv.slice(1), {
        // A terminal worker keeps its controlling terminal. The host lease
        // keeps the lock until its descendants have ended.
        env, cwd, limit: 1 << 20, deadline, group: mode === "exec" && !terminal, terminal, output, signal, extra: 2,
        shutdown: mode === "host" ? child => child.stdio[3].end() : undefined,
        attach(child) {
            child.stdio[3].on("error", error => { if (error.code !== "EPIPE") child.kill("SIGKILL"); });
            child.stdio[3].write("S");
            child.stdio[4].resume();
        }
    });
}

function fail(key) { throw new Error("jarvis: fleet-setup=" + key); }

// One step in the terminal: COMMAND under the lease, in CWD, with the
// terminal's input and output. Refuses KEY on any end but exit 0.
async function step(command, { cwd, env, signal, key }) {
    const result = await leased("outer", command, { cwd, env, signal, terminal: true });
    if (result.kind !== "exited") fail(key + " cause=" + result.reason);
    if (result.code !== 0) fail(key + " cause=exit=" + result.code);
}

// The top folder of the git work tree DIRECTORY lies in, or null outside
// every work tree, as git gives it: links resolved. git exits 128 with this
// message for a folder no work tree holds (setup.c die_not_a_repository);
// any other failure refuses.
function workTree(directory) {
    const result = git(["-C", directory, "rev-parse", "--show-toplevel"]);
    if (result.status === 128 && /^fatal: not a git repository/m.test(result.stderr)) return null;
    if (result.status !== 0) fail("git-unreadable cause=exit=" + result.status);
    return path.resolve(result.stdout.trim());
}

// One git probe that changes nothing, bounded, its failure to start refused.
function git(args) {
    const result = cp.spawnSync("git", ["-c", "safe.directory=*", ...args], {
        env: { ...environment(process.env), LC_ALL: "C" }, encoding: "utf8", maxBuffer: 1 << 16, timeout: PROBE_MS
    });
    if (result.error) fail("git-unreadable cause=" + (result.error.code || "spawn"));
    return result;
}

// FOLDER with every link resolved, as git names a work tree: its own real
// path once it exists, else its nearest existing folder's with the names
// below it, so a home reached through a link compares with git's answer.
function real(folder) {
    let at = folder;
    const below = [];
    while (!fs.existsSync(at)) {
        below.unshift(path.basename(at));
        at = path.dirname(at);
    }
    return path.join(fs.realpathSync(at), ...below);
}

// Refuse a FOLDER that lies inside another project's work tree: kendex
// add there installs into that project
// (.agents/skills/jarvis/references/home-layout.md § Initialize), and
// Setup never converts a project. FOLDER may not exist yet; its real path
// is the one compared and named.
function outsideProjects(folder) {
    const own = real(folder);
    let at = own;
    while (!fs.existsSync(at)) at = path.dirname(at);
    const top = workTree(at);
    if (top !== null && top !== own) fail("inside-project work-tree=" + JSON.stringify(top));
    const above = top === own ? workTree(path.dirname(own)) : null;
    if (above !== null) fail("inside-project work-tree=" + JSON.stringify(above));
}

// The top-level entries of FOLDER, or null where it is not there.
function contents(folder) {
    try { return fs.readdirSync(folder); }
    catch (error) {
        if (error.code === "ENOENT") return null;
        if (error.code === "ENOTDIR") fail("home-kind");
        fail("home-unreadable cause=" + error.code);
    }
}

// Whether kendex installed the Jarvis package in FOLDER, read without
// refusing a folder whose lock cannot be read: that is no home either.
function installedIn(folder) {
    try { return Home.packageInstalled(folder); }
    catch (error) {
        if (!/^jarvis: home=/.test(error.message)) throw error;
        return false;
    }
}

// The home's own session command, found as Jarvis finds it, or a refusal.
function sessionCommand(folder) {
    const found = Home.sessionCommand(folder);
    if (found.kind !== "found") fail("session-command cause=" + found.kind);
    return found.path;
}

// Each step a verb runs, as argv, for the step itself and for the plan the
// TUI shows: one source for both. SESSION is the session command, absolute
// when it runs and relative to the home in the plan.
const STEPS = {
    gitInit: folder => ["git", "-C", folder, "init"],
    add: () => ["kendex", ...ADD],
    init: (session, folder) => [session, "init", "--home", folder],
    clone: (source, folder) => ["git", "clone", "--no-checkout", "--", source, folder],
    checkout: folder => ["git", "-C", folder, "reset", "--hard", "--quiet", "HEAD"],
    guard: () => ["kendex", "guard", "install"],
    mainHost: (session, main, folder) => [session, "main-host", "--set", main, "--home", folder]
};

// Refuse a clone from SOURCE for a computer that forwards to MAIN unless
// both can be taken.
function cloneArguments(source, main) {
    if (!CLONE_SOURCE.test(source)) fail("clone-source");
    if (typeof main !== "string" || main === "" || /[\x00-\x1f\x7f]/.test(main)) fail("main-host-unset");
}

// The steps the TUI shows before the user confirms: `new`, or `clone`
// with its SOURCE and MAIN.
function plan(folder, [mode, source, main]) {
    const session = Home.SESSION_COMMAND;
    if (mode === "new" && source === undefined) return [STEPS.gitInit(folder), STEPS.add(), STEPS.init(session, folder)];
    if (mode !== "clone" || main === undefined) return fail("arguments");
    cloneArguments(source, main);
    return [STEPS.clone(source, folder), STEPS.checkout(folder), STEPS.guard(), STEPS.init(session, folder),
        STEPS.mainHost(session, main, folder)];
}

// Run the package's init in FOLDER with its output piped: its JSON report
// is read, not shown, and its stderr, a refusal's own line among it,
// reaches the terminal once init ends.
async function initialize(folder, env, signal) {
    const result = await leased("outer", STEPS.init(sessionCommand(folder), folder),
        { cwd: folder, env, signal, terminal: true, output: "pipe" });
    if (result.stderr) process.stderr.write(result.stderr);
    if (result.kind !== "exited") fail("init cause=" + result.reason);
    if (result.code !== 0) fail("init-refused cause=exit=" + result.code);
    let report = null;
    try { report = JSON.parse(result.stdout); } catch {}
    // .agents/skills/jarvis/references/home-layout.md § Initialize: v, home, created, kept
    // and settings.
    if (report === null || typeof report !== "object" || report.v !== 1
            || !Array.isArray(report.created) || !Array.isArray(report.kept)) fail("init-unaccepted");
}

// Success read from the home itself: the package judged as Jarvis judges
// it, the mail tool and the session command.
function readBack(folder) {
    try { Home.judge(folder); }
    catch (error) {
        if (!/^jarvis: home=[a-z-]+$/.test(error.message)) throw error;
        fail("still-missing cause=" + error.message.slice(8));
    }
    if (Home.mailTool(folder) === null) fail("still-missing cause=mail-tool");
    sessionCommand(folder);
}

/**
 * Make FOLDER a new Jarvis home (D126): the dedicated folder outside every
 * project, its own Git repository, the Jarvis bundle through kendex, then
 * the package's init. A computer whose Main Jarvis host, MAIN, names
 * another computer takes the clone instead, so its memory stays the main
 * home's. An existing folder qualifies only while it is empty, holds Git's
 * entry alone, or is a home kendex installed the Jarvis package in, which
 * the same steps complete; any other folder is never converted.
 */
async function setupHome(folder, main, signal) {
    if (main !== "") fail("main-host-set main=" + JSON.stringify(main));
    const env = environment(process.env);
    const found = contents(folder);
    if (found !== null && found.length > 0 && !(found.length === 1 && found[0] === ".git") && !installedIn(folder))
        fail("occupied entry=" + JSON.stringify(found.sort()[0]));
    outsideProjects(folder);
    fs.mkdirSync(folder, { recursive: true });
    if (workTree(folder) !== real(folder)) await step(STEPS.gitInit(folder), { cwd: folder, env, signal, key: "git-init-failed" });
    await step(STEPS.add(), { cwd: folder, env, signal, key: "install-failed" });
    await initialize(folder, env, signal);
    readBack(folder);
    return 0;
}

// Whether the history of the repository at FOLDER, every ref of it, holds
// the private env file: a commit that ever added, changed or removed it.
// --full-history walks each parent of a merge: by default git log follows
// only a parent the merge leaves the file unchanged from, which skips a
// merged branch that added and then removed it (git-log(1) § History
// Simplification).
function credentialsInHistory(folder) {
    const result = git(["-C", folder, "log", "--all", "--full-history", "-1", "--format=%H", "--", PRIVATE_ENV]);
    if (result.status !== 0) fail("git-unreadable cause=exit=" + result.status);
    return result.stdout.trim() !== "";
}

// Whether FOLDER's index tracks the private env file.
function credentialsTracked(folder) {
    const result = git(["-C", folder, "ls-files", "-z", "--", PRIVATE_ENV]);
    if (result.status !== 0) fail("git-unreadable cause=exit=" + result.status);
    return result.stdout !== "";
}

// Remove what this run's clone wrote at FOLDER: the folder itself where the
// run made it, else every entry the clone put in the folder it found empty.
function removeClone(folder, made) {
    if (made) { fs.rmSync(folder, { recursive: true, force: true }); return; }
    for (const name of fs.readdirSync(folder)) fs.rmSync(path.join(folder, name), { recursive: true, force: true });
}

/**
 * Make FOLDER a private clone of the main home at SOURCE for a second
 * computer that forwards to MAIN (D126): git clone with no checkout, a
 * refusal while any commit of the clone's history holds the private env
 * file, before a file of it is checked out, then the checkout, the clone's
 * commit guards through kendex, the state folder init makes and the
 * package's main-host setting, read back. Any end before the checkout
 * holds the package removes what the clone wrote.
 * The clone holds no second memory: the main's daemon alone writes a note,
 * and the clone gets it when it pulls the main home.
 * FOLDER is absent or empty, or a clone an earlier run left: its own work
 * tree with the package installed and the private env file neither tracked
 * nor in its history, which the steps after the checkout complete.
 */
async function cloneHome(folder, source, main, signal) {
    cloneArguments(source, main);
    const env = environment(process.env, ["SSH_AUTH_SOCK"]);
    const found = contents(folder);
    if (found !== null && found.length > 0) {
        if (workTree(folder) !== real(folder) || !installedIn(folder) || credentialsTracked(folder) || credentialsInHistory(folder))
            fail("occupied entry=" + JSON.stringify(found.sort()[0]));
        outsideProjects(folder);
    } else {
        outsideProjects(folder);
        fs.mkdirSync(path.dirname(folder), { recursive: true });
        // Until its checkout holds the package, the clone is nothing a
        // later run resumes: every end before then, a refusal, a failed
        // step or a cancellation, removes what the clone wrote, so a retry
        // finds the folder as it was.
        try {
            await step(STEPS.clone(source, folder), {
                cwd: path.dirname(folder), env: { ...env, GIT_ALLOW_PROTOCOL: CLONE_PROTOCOLS }, signal, key: "clone-failed"
            });
            if (credentialsInHistory(folder)) fail("credentials-committed");
            await step(STEPS.checkout(folder), { cwd: folder, env, signal, key: "checkout-failed" });
            if (!installedIn(folder)) fail("clone-not-home");
        } catch (error) {
            removeClone(folder, found === null);
            throw error;
        }
    }
    await step(STEPS.guard(), { cwd: folder, env, signal, key: "guard-failed" });
    await initialize(folder, env, signal);
    const session = sessionCommand(folder);
    await step(STEPS.mainHost(session, main, folder), { cwd: folder, env, signal, key: "main-host-failed" });
    // The package's own reader of the setting it stored (main-host --get,
    // skills/jarvis/scripts/lib/session.py main_host, kendex 6c00d3e19).
    const stored = await leased("outer", [session, "main-host", "--get", "--home", folder],
        { cwd: folder, env, signal, terminal: true, output: "pipe" });
    if (stored.stderr) process.stderr.write(stored.stderr);
    if (stored.kind !== "exited") fail("main-host-read cause=" + stored.reason);
    if (stored.code !== 0) fail("main-host-read cause=exit=" + stored.code);
    let report = null;
    try { report = JSON.parse(stored.stdout); } catch {}
    if (report === null || typeof report !== "object" || typeof report.JARVIS_MAIN_HOST !== "string") fail("main-host-read cause=unparseable");
    // A read that succeeded and holds another value: the setting was not kept.
    if (report.JARVIS_MAIN_HOST !== main) fail("main-host-unset cause=read-back");
    readBack(folder);
    return 0;
}

async function repairPackage(folder, signal) {
    if (!Home.packageInstalled(folder)) {
        Home.repairResult(folder, { kind: "failed", cause: "not-set-up" });
        fail("not-set-up");
    }
    const result = await leased("outer", ["kendex", ...REFRESH(folder)], {
        cwd: folder, env: environment(process.env), terminal: true, signal
    });
    if (result.kind !== "exited") {
        Home.repairResult(folder, { kind: "failed", cause: result.reason });
        fail(result.reason);
    }
    if (result.code !== 0) {
        const code = Number.isInteger(result.code) ? result.code : 1;
        Home.repairResult(folder, { kind: "failed", cause: "refresh-failed", code });
        return code;
    }
    try { Home.judge(folder); }
    catch (error) {
        if (!/^jarvis: home=[a-z-]+$/.test(error.message)) throw error;
        Home.repairResult(folder, { kind: "failed", cause: error.message.slice(8) });
        process.stderr.write(error.message + "\n");
        return 1;
    }
    Home.repairResult(folder, { kind: "complete" });
    return 0;
}

// The signals that end a verb in the terminal: SIGTERM from the lease,
// SIGINT from Ctrl+C, and SIGHUP, which the terminal sends the TUI's whole
// process group when its window closes. Node dies on each without a
// listener, before a step's cleanup runs
// (https://nodejs.org/api/process.html#signal-events).
const CANCEL_SIGNALS = ["SIGTERM", "SIGINT", "SIGHUP"];

// RUN given a signal that any of CANCEL_SIGNALS aborts, so each ends
// through the steps' cancellation.
async function cancellable(run) {
    const controller = new AbortController();
    const cancel = () => controller.abort();
    for (const name of CANCEL_SIGNALS) process.once(name, cancel);
    try { return await run(controller.signal); }
    finally { for (const name of CANCEL_SIGNALS) process.removeListener(name, cancel); }
}

// The worker's verb, under the lock in the terminal.
async function worker(verb, folder, rest) {
    return cancellable(async signal => {
        if (verb === "setup-worker") return await setupHome(folder, rest[0], signal);
        if (verb === "clone-worker") return await cloneHome(folder, rest[0], rest[1], signal);
        Home.repairResult(folder, { kind: "running" });
        return await repairPackage(folder, signal);
    });
}

// The numbers of arguments after the setting each verb may take: plan
// takes new, or clone with its source and main; setup and its worker take
// the Main Jarvis host setting.
const VERBS = { status: [0], folder: [0], tool: [0], ready: [0], plan: [1, 3], setup: [1], clone: [2], "repair-status": [0], repair: [0],
    "setup-worker": [1], "clone-worker": [2], "repair-worker": [0] };

async function main() {
    const [flag, tree, verb, setting, ...rest] = process.argv.slice(2);
    if (flag !== "--tree" || !path.isAbsolute(tree || "") || !Object.hasOwn(VERBS, verb)
            || typeof setting !== "string" || !VERBS[verb].includes(rest.length)) fail("arguments");
    require("./Core.js").use(tree);
    let folder = null;
    try { folder = Home.resolve(setting, process.env.HOME); }
    catch (error) { if (!/^jarvis: home=/.test(error.message)) throw error; }
    if (verb.endsWith("-worker")) {
        if (folder === null) fail("home-unchosen");
        return worker(verb, folder, rest);
    }
    if (verb === "repair-status") {
        if (folder === null) fail("home-unchosen");
        const kind = Home.packageInstalled(folder) ? "home" : "setup";
        process.stdout.write(JSON.stringify({ kind, folder, lastRepair: Home.repairResult(folder) }) + "\n");
        return 0;
    }
    if (verb === "setup" || verb === "clone" || verb === "repair") {
        if (folder === null) fail("home-unchosen");
        return cancellable(async signal => {
            // The lock's working folder is the home's parent: the home
            // itself may not exist before setup or a clone.
            if (verb !== "repair") fs.mkdirSync(path.dirname(folder), { recursive: true });
            const result = await locked(tree, folder, verb + "-worker", rest, process.env, signal);
            if (result.kind !== "exited") fail(result.reason);
            if (result.code === 75) fail("busy");
            return result.code;
        });
    }
    if (verb === "plan") {
        if (folder === null) fail("home-unchosen");
        process.stdout.write(plan(folder, rest).map(argv => argv.join(" ") + "\n").join(""));
        return 0;
    }
    if (verb === "ready") {
        if (folder === null) fail("home-unchosen");
        readBack(folder);
        return 0;
    }
    const tool = folder === null ? null : Home.mailTool(folder);
    if (verb === "status") {
        const { load } = require(path.join(tree, "bin/lib/qml-library.js"));
        const PageReference = load(path.join(tree, "shell/Commons/PageReference.js"));
        const Gate = load(path.join(__dirname, "../SetupGate.js"), { "qs.Commons 1.0": { PageReference } });
        process.stdout.write(JSON.stringify(Gate.fleetStep(folder, tool)) + "\n");
        return 0;
    }
    const found = verb === "folder" ? folder : tool;
    if (found === null) fail(folder === null ? "home-unchosen" : "tool-absent");
    process.stdout.write(found + "\n");
    return 0;
}

if (require.main === module) main().then(code => { process.exitCode = code; }).catch(error => {
    process.stderr.write(error.message + "\n");
    process.exitCode = error.message === "jarvis: fleet-setup=arguments" ? 2
        : error.message === "jarvis: fleet-setup=credentials-committed" ? 3 : 1;
});
module.exports = { setupHome, cloneHome };
