#!/usr/bin/env node
// Read-only probes and the shared automatic/manual installer. The worker
// runs under the shared lock and the existing descendant-safe PID lease.
"use strict";
const path = require("node:path");
const cp = require("node:child_process");
const Home = require("./Home.js");

function environment(source) {
    const env = { PATH: source.PATH || "/usr/bin:/bin", LANG: "C.UTF-8", HOME: source.HOME };
    for (const key of ["XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR", "TERM"])
        if (source[key]) env[key] = source[key];
    return env;
}

// Retain the existing TUI lock identity. The locked worker consumes the
// automatic record before namespace setup, so a refused namespace consumes it.
async function install(tree, folder, automatic, source, signal) {
    return locked(tree, folder, automatic ? "automatic-worker" : "manual-worker", source, signal);
}

function locked(tree, folder, verb, source, signal, terminal = false) {
    const env = environment(source);
    const runtime = env.XDG_RUNTIME_DIR || "/run/user/" + process.getuid();
    return leased(terminal ? "host" : "exec", [process.execPath, __filename, "--tree", tree, verb, folder], {
        env, cwd: folder, signal, terminal,
        prefix: ["flock", "--no-fork", "-n", "-E", "75", path.join(runtime, "vgs-tui-jarvis-fleet-setup.lock")]
    });
}

function leased(mode, command, { env, cwd, signal, terminal = false, deadline = 300000, prefix = [] }) {
    const argv = ["python3", "-I", path.join(__dirname, "audio-child.py"), mode, String(process.pid), ...command];
    if (mode !== "host") argv.unshift("setpriv", "--pdeathsig", "KILL", "--");
    argv.unshift(...prefix);
    return require("./Child.js").run(argv[0], argv.slice(1), {
        // A terminal worker keeps its controlling terminal. The host lease
        // keeps the repair lock until its descendants have ended.
        env, cwd, limit: 1 << 20, deadline, group: mode === "exec" && !terminal, terminal, signal, extra: 2,
        shutdown: mode === "host" ? child => child.stdio[3].end() : undefined,
        attach(child) {
            child.stdio[3].on("error", error => { if (error.code !== "EPIPE") child.kill("SIGKILL"); });
            child.stdio[3].write("S");
            child.stdio[4].resume();
        }
    });
}

function fail(key) { throw new Error("jarvis: fleet-setup=" + key); }

async function worker(tree, folder, automatic, repair = false) {
    if (!repair && Home.mailTool(folder) !== null) return 0;
    if (automatic) {
        if (Home.mailCutover(folder) !== "eligible") return 0;
        if (!Home.consumeMailCutover(folder)) return 0;
    }
    const controller = new AbortController();
    const cancel = () => controller.abort();
    process.once("SIGTERM", cancel);
    process.once("SIGINT", cancel);
    try {
        if (repair) {
            Home.repairResult(folder, { kind: "running" });
            return await repairPackage(tree, folder, controller.signal);
        }
        const result = await leased("outer", [process.execPath, __filename, "--tree", tree, "install-worker", folder], {
            env: environment(process.env), cwd: folder, signal: controller.signal
        });
        if (result.stdout) process.stdout.write(result.stdout);
        if (result.stderr) process.stderr.write(result.stderr);
        if (result.kind !== "exited") fail(result.reason);
        if (result.code !== 0) fail("install-failed");
        return 0;
    } finally {
        process.removeListener("SIGTERM", cancel);
        process.removeListener("SIGINT", cancel);
    }
}

async function repairPackage(tree, folder, signal) {
    const owner = Home.packageOwner(folder);
    const file = owner === "kendex" ? "kendex" : path.join(tree, "bin/vgshell");
    const args = owner === "kendex" ? ["refresh", "--scope", "project", "--project-path", folder, "--leave"] : ["self", "repair"];
    const result = await leased(owner === "kendex" ? "outer" : "exec", [file, ...args], {
        cwd: folder, env: environment(process.env), terminal: true, signal
    });
    if (result.kind !== "exited") {
        Home.repairResult(folder, { kind: "failed", cause: result.reason });
        fail(result.reason);
    }
    if (result.code !== 0) {
        const code = Number.isInteger(result.code) ? result.code : 1;
        Home.repairResult(folder, { kind: "failed", cause: owner === "kendex" ? "refresh-failed" : "install-failed", code });
        return code;
    }
    // Curl repair publishes a new tree and restarts the shell. Its new
    // daemon judges the Home against that tree; this worker holds the old.
    try { if (owner === "kendex") Home.layout(folder); }
    catch (error) {
        if (!/^jarvis: home=[a-z-]+$/.test(error.message)) throw error;
        Home.repairResult(folder, { kind: "failed", cause: error.message.slice(8) });
        process.stderr.write(error.message + "\n");
        return 1;
    }
    Home.repairResult(folder, { kind: "complete" });
    return 0;
}

function packageInstall(folder) {
    const run = (file, args, key) => {
        const result = cp.spawnSync(file, args, { cwd: folder, env: environment(process.env), stdio: "inherit" });
        if (result.error || result.status !== 0) fail(key);
    };
    const repository = cp.spawnSync("git", ["-C", folder, "rev-parse", "--show-toplevel"], {
        env: environment(process.env), encoding: "utf8", maxBuffer: 8192
    });
    if (repository.error || repository.status !== 0 || path.resolve(repository.stdout.trim()) !== folder)
        run("git", ["-C", folder, "init"], "git-init-failed");
    try { Home.release(folder); }
    catch (error) { fail("release-failed " + error.message); }
    run("kendex", ["add", "vanillagreencom/kendex", "--skill", "orch", "--yes", "--leave"], "install-failed");
    if (Home.mailTool(folder) === null) fail("still-missing");
    return 0;
}

async function main() {
    const [flag, tree, verb, setting, ...rest] = process.argv.slice(2);
    if (flag !== "--tree" || !path.isAbsolute(tree || "")
            || !["status", "folder", "tool", "manual", "repair-status", "repair", "automatic-worker", "manual-worker", "install-worker", "repair-worker"].includes(verb)
            || typeof setting !== "string" || rest.length > 0) fail("arguments");
    require("./Core.js").use(tree);
    let folder = null;
    try { folder = Home.resolve(setting, process.env.HOME); }
    catch (error) { if (!/^jarvis: home=/.test(error.message)) throw error; }
    if (verb.endsWith("-worker")) {
        if (folder === null) fail("home-unchosen");
        return verb === "install-worker" ? packageInstall(folder) : worker(tree, folder, verb === "automatic-worker", verb === "repair-worker");
    }
    if (verb === "repair-status") {
        if (folder === null) fail("home-unchosen");
        const kind = Home.packageOwner(folder) === "kendex" ? "home" : "install";
        const status = { kind, folder, lastRepair: Home.repairResult(folder) };
        if (kind === "install") {
            const plan = await leased("outer", [path.join(tree, "bin/vgshell"), "self", "repair", "--plan"], {
                env: environment(process.env), cwd: folder, deadline: 10000
            });
            if (plan.kind !== "exited" || plan.code !== 0) fail("install-plan-unreadable");
            status.installPlan = JSON.parse(plan.stdout);
        }
        process.stdout.write(JSON.stringify(status) + "\n");
        return 0;
    }
    if (verb === "manual" || verb === "repair") {
        if (folder === null) fail("home-unchosen");
        const controller = new AbortController();
        const cancel = () => controller.abort();
        process.once("SIGTERM", cancel);
        process.once("SIGINT", cancel);
        try {
            const result = await (verb === "repair"
                ? locked(tree, folder, "repair-worker", process.env, controller.signal, true)
                : install(tree, folder, false, process.env, controller.signal));
            if (result.stdout) process.stdout.write(result.stdout);
            if (result.stderr) process.stderr.write(result.stderr);
            if (result.kind !== "exited") fail(result.reason);
            if (result.code === 75) fail("busy");
            if (verb === "repair") return result.code;
            if (result.code !== 0) fail("install-failed");
            return 0;
        } finally {
            process.removeListener("SIGTERM", cancel);
            process.removeListener("SIGINT", cancel);
        }
    }
    const tool = folder === null ? null : Home.mailTool(folder);
    if (verb === "status") {
        const { load } = require(path.join(tree, "bin/lib/qml-library.js"));
        const Gate = load(path.join(__dirname, "../SetupGate.js"));
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
    process.exitCode = error.message === "jarvis: fleet-setup=arguments" ? 2 : 1;
});
module.exports = { install };
