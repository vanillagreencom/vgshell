// The one owner of the Jarvis package's satellite contract: the
// fleet.forward executor, the hand-off of Main Jarvis host to the package's
// main-host setting, and the read of the main's reachability. Every call is
// the home's session command by argv (Home.sessionCommand); the package owns
// the SSH connection, the outbox, retries and the answer.
"use strict";
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const Child = require("./Child.js");
const Home = require("./Home.js");
const Redact = require("./Redact.js");

// Above the package's 45 s budget for one forward run (forward.py
// DRAIN_SECONDS), so the package records why before this bound ends it.
const FORWARD_MS = 50000;
// A recovery bound for a hung local read or write; the status read starts
// no SSH call (the package's workflows/session.md).
const LOCAL_MS = 5000;
const OUTPUT_BYTES = 16 * 1024;
// The package's watch loop drains the outbox every FORWARD_EVERY_SECS (60,
// watch.py), so the reading changes no more often.
const READ_EVERY_MS = 60000;
// What the package reads beside its argv: its tools, the home, the state
// directory its outbox is under (the watch loop's own), the agent the SSH
// call signs with, and the locale.
const ENVIRONMENT = ["PATH", "HOME", "XDG_STATE_HOME", "SSH_AUTH_SOCK", "LANG"];
// A refused forward's first stderr line (session.py, forward.py main): no
// entry was queued and nothing was sent.
const REFUSED = /^jarvis-session: forward=refused cause=([a-z0-9-]{1,60})/;
// The package's argparse refusal of a verb or flag it lacks (session.py
// Arguments.error): an installed package older than the satellite contract.
const ARGUMENTS = /^jarvis-session: arguments=invalid/;
const CLOCK = { set: (fn, ms) => setTimeout(fn, ms), clear: timer => clearTimeout(timer) };

/**
 * The host part of a Main Jarvis host value, as the package's role names
 * it: DEST of DEST:/abs/home (watch.py role), or the bare host.
 */
function hostOf(value) {
    const colon = value.indexOf(":");
    return colon === -1 ? value : value.slice(0, colon);
}

/**
 * The package's setting for VALUE in the home FOLDER: "" for this machine,
 * a value holding ":/" unchanged, and a bare host as HOST:FOLDER, the main
 * home at the same path. The package judges the result.
 */
function settingOf(value, folder) {
    return value === "" || value.includes(":/") ? value : value + ":" + folder;
}

/**
 * The reading `status --main` answers, as the Now line shows it, for
 * VALUE, the Main Jarvis host setting: {kind:"satellite", host, reachable,
 * cause} while the package names the main the setting names, else
 * {kind:"unavailable", cause:"package"}. A package that answered role
 * main, or another main, has not taken the setting.
 */
function reading(answer, value) {
    if (answer === null || typeof answer !== "object" || answer.v !== 1) return { kind: "unavailable", cause: "package" };
    if (answer.role === "satellite" && answer.cause === "setting-invalid")
        return { kind: "satellite", host: "", reachable: null, cause: "setting-invalid" };
    if (answer.role !== "satellite" || answer.main !== hostOf(value) || ![true, false, null].includes(answer.reachable))
        return { kind: "unavailable", cause: "package" };
    return { kind: "satellite", host: answer.main, reachable: answer.reachable,
        cause: answer.reachable === false ? "main-unreachable" : "" };
}

/**
 * create({home, mainHost, environment, publish, log}) builds the owner.
 * home() answers the ready home folder or null; mainHost() the Main Jarvis
 * host setting; environment is the daemon's; publish(reach) receives each
 * reading.
 */
function create({ home, mainHost, environment, publish, log, clock = CLOCK, run = Child.run }) {
    let last = null;
    let controller = null;
    let timer = null;
    let inFlight = Promise.resolve();
    let setting = Promise.resolve();
    let closed = false;

    function childEnvironment() {
        const env = { LANG: "C.UTF-8" };
        for (const name of ENVIRONMENT) if (environment[name] !== undefined) env[name] = environment[name];
        return env;
    }

    // The home's session command, or null for a home without it.
    function command(folder) {
        const found = Home.sessionCommand(folder);
        return found.kind === "found" ? found.path : null;
    }

    function session(file, folder, args, deadline, signal) {
        return run("setpriv", ["--pdeathsig", "KILL", "--", file, ...args, "--home", folder],
            { env: childEnvironment(), cwd: folder, limit: OUTPUT_BYTES, deadline, group: true, signal });
    }

    async function read(signal) {
        const value = mainHost();
        if (value === "") return { kind: "main" };
        const folder = home();
        if (folder === null) return { kind: "unavailable", cause: "home" };
        const file = command(folder);
        if (file === null) return { kind: "unavailable", cause: "package" };
        const result = await session(file, folder, ["status", "--main"], LOCAL_MS, signal);
        if (result.kind === "stopped" && result.reason === "cancelled") return null;
        if (result.kind !== "exited" || result.code !== 0) {
            const old = result.kind === "exited" && ARGUMENTS.test(result.stderr);
            if (!old) log("jarvis: satellite=status cause=" + (result.kind === "exited" ? "exit-" + result.code : result.reason));
            return { kind: "unavailable", cause: "package" };
        }
        let answer = null;
        try { answer = JSON.parse(result.stdout.trim()); }
        catch { log("jarvis: satellite=status cause=unparsed"); }
        return reading(answer, value);
    }

    function show(reach) {
        if (JSON.stringify(reach) === JSON.stringify(last)) return;
        last = reach;
        publish(reach);
    }

    // Read again now, ending a read under way, then every READ_EVERY_MS
    // while the setting names a main. Each hello that changes the setting or
    // the home, each choice and each forward reads again.
    function refresh() {
        if (closed) return;
        if (timer !== null) clock.clear(timer);
        timer = null;
        if (controller !== null) controller.abort();
        const own = controller = new AbortController();
        inFlight = read(own.signal).then(reach => {
            if (closed || own !== controller) return;
            controller = null;
            if (reach !== null) show(reach);
            if (mainHost() !== "") timer = clock.set(() => { timer = null; refresh(); }, READ_EVERY_MS);
        }, error => {
            if (closed || own !== controller) return;
            controller = null;
            log("jarvis: satellite=status cause=" + (error.code || "unexpected"));
            show({ kind: "unavailable", cause: "package" });
        });
    }

    // Hand the user's choice of VALUE to the package's main-host setting of
    // the home FOLDER, one choice at a time in the order chosen, then read.
    function choose(value, folder) {
        setting = setting.then(async () => {
            if (closed) return;
            const file = folder === null ? null : command(folder);
            if (file !== null) {
                const result = await session(file, folder, ["main-host", "--set=" + settingOf(value, folder)], LOCAL_MS);
                if (result.kind !== "exited" || result.code !== 0)
                    log("jarvis: satellite=main-host cause=" + (result.kind !== "exited" ? result.reason
                        : ARGUMENTS.test(result.stderr) ? "package-old" : "exit-" + result.code));
            }
            refresh();
        }).catch(error => log("jarvis: satellite=main-host cause=" + (error.code || "unexpected")));
        return setting;
    }

    const failed = cause => ({ outcome: "failed", content: "fleet-forward:" + cause });

    async function forward(call, confirmed) {
        // external: the router holds it for the user's confirmation.
        if (confirmed === undefined || !["voice", "physical"].includes(confirmed.method)) return failed("unconfirmed");
        if (Redact.secret(call.args.text)) return failed("secret");
        const folder = home();
        if (folder === null) return failed("home-unchosen");
        const file = command(folder);
        if (file === null) return failed("package-absent");
        // The request as the user made it, spoken or typed: no VGS path knows
        // who spoke, so the record names no caller.
        const record = { v: 1, request: { ref: confirmed.ref, at: confirmed.at, text: call.args.text },
            confirmation: { ref: confirmed.ref, at: confirmed.at, method: confirmed.method } };
        const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "vgs-jarvis-forward-"));
        let result;
        try {
            const recordFile = path.join(scratch, "record.json");
            fs.writeFileSync(recordFile, JSON.stringify(record), { mode: 0o600, flag: "wx" });
            result = await session(file, folder, ["forward", "--record", recordFile], FORWARD_MS);
        } finally { fs.rmSync(scratch, { recursive: true, force: true }); }
        if (result.kind === "error") return failed("spawn");
        if (result.kind !== "exited")
            return { outcome: "unknown", content: "Unknown: the forward ended before the Jarvis package answered, so the request may be in this computer's outbox or not." };
        if (result.code === 0)
            return { outcome: "completed", content: "Completed: the request reached your main Jarvis. Its answer comes in your Slack channel." };
        if (result.code === 75) {
            let cause = "";
            try { cause = JSON.parse(result.stdout.trim()).cause ?? ""; } catch { cause = ""; }
            return { outcome: "completed", content: "Completed: the request waits in this computer's outbox for your main Jarvis"
                + (cause === "" ? "" : " (" + cause + ")") + ". The Jarvis package sends it again every minute." };
        }
        const first = result.stderr.split("\n")[0];
        if (result.code === 2 && ARGUMENTS.test(first)) return failed("package-old");
        const refused = result.code === 2 ? REFUSED.exec(first)?.[1] : undefined;
        if (refused !== undefined) return failed(refused);
        return { outcome: "unknown", content: "Unknown: the Jarvis package ended with exit " + result.code + ", so the request may be in this computer's outbox or not." };
    }

    return {
        executor: { commands: [], timeoutMs: FORWARD_MS + 1000, cancellable: false,
            // Read at offer, route and start: a satellite whose package
            // reads the main this setting names.
            available: () => mainHost() !== "" && last !== null && last.kind === "satellite" && last.cause !== "setting-invalid",
            start(call, done, authorize, origin, confirmed) {
                forward(call, confirmed).then(answer => { done(answer); refresh(); },
                    error => done(failed(error.code || "unexpected")));
            } },
        refresh, choose,
        close() {
            closed = true;
            if (timer !== null) clock.clear(timer);
            timer = null;
            if (controller !== null) controller.abort();
            return Promise.allSettled([inFlight, setting]);
        }
    };
}

module.exports = { create, reading, settingOf, READ_EVERY_MS };
