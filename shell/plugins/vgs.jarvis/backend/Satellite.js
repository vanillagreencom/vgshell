// The one owner of the Jarvis package's satellite contract: the
// fleet.forward executor, the hand-off of Main Jarvis host to the package's
// main-host setting, and the read of the main's reachability. Every call is
// the home's session command by argv (SessionCommand.place); the package
// owns the SSH connection, the outbox, retries and the answer.
"use strict";
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const Child = require("./Child.js");
const Redact = require("./Redact.js");
const SessionCommand = require("./SessionCommand.js");

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
// Beside a session call's own variables (SessionCommand.callEnvironment):
// the agent the forward's SSH call signs with.
const SSH_ENVIRONMENT = ["SSH_AUTH_SOCK"];
// A refused call's first stderr line, by its verb: a forward that queued no
// entry and sent nothing (forward.py main), or a main-host setting the
// setter stored nothing of (session.py main_host).
const REFUSED = /^jarvis-session: (forward|main-host)=refused cause=([a-z0-9-]{1,60})/;
// The package's argparse refusal of a verb or flag it lacks (session.py
// Arguments.error): an installed package older than the call.
const ARGUMENTS = /^jarvis-session: arguments=invalid/;
// The lines the main reads as a request's caller and its provenance: a
// first line `voice-request: caller=...` (the package's agent-reach.md
// § Main and satellites) and the `forwarded-request:` line forward.py
// appends. Text holding either line could claim the owner.
const CLAIM = /^(voice-request|forwarded-request):/;
// Python's str.splitlines boundaries, where a line the main reads can start.
const LINES = /\r\n|[\n\r\v\f\x1c-\x1e\x85\u2028\u2029]/;
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

/** The cause of VERB's refusal in a call's STDERR, or undefined. */
function refusal(verb, stderr) {
    const match = REFUSED.exec(stderr.split("\n")[0]);
    return match !== null && match[1] === verb ? match[2] : undefined;
}

/** Whether TEXT holds a line, trimmed and case-folded, that opens as CLAIM does. */
function claims(text) {
    return text.split(LINES).some(line => CLAIM.test(line.trim().toLowerCase()));
}

/**
 * The reading for VALUE, the Main Jarvis host setting, when its setter
 * refused it with CAUSE (session.py main_host): a value the package's role
 * rule judges no host reads as an unparsed setting; a setting it could not
 * read or store, or a setter that did not answer, as a package that did
 * not answer as expected.
 */
function refused(cause, value) {
    return cause === "setting-invalid" ? { kind: "satellite", host: hostOf(value), reachable: null, cause }
        : { kind: "unavailable", host: hostOf(value), cause: "package-unread" };
}

/**
 * The reading `status --main` ANSWER gives for VALUE, the Main Jarvis host
 * setting, each with the host VALUE names: {kind:"satellite", host,
 * reachable, cause} while the package names that main; else
 * {kind:"unavailable", host, cause}, "package-old" for a package that
 * answered role main or another main, which a package without the setter
 * leaves, "package-unread" for any other answer.
 */
function reading(answer, value) {
    const host = hostOf(value);
    if (answer === null || typeof answer !== "object" || answer.v !== 1) return { kind: "unavailable", host, cause: "package-unread" };
    if (answer.role === "satellite" && answer.cause === "setting-invalid") return refused("setting-invalid", value);
    if (answer.role === "main" || answer.role === "satellite" && answer.main !== host)
        return { kind: "unavailable", host, cause: "package-old" };
    if (answer.role !== "satellite" || ![true, false, null].includes(answer.reachable))
        return { kind: "unavailable", host, cause: "package-unread" };
    return { kind: "satellite", host, reachable: answer.reachable,
        cause: answer.reachable === false ? "main-unreachable" : "" };
}

/**
 * create({home, mainHost, environment, publish, log}) builds the owner.
 * home() answers the ready home folder or null; mainHost() the Main Jarvis
 * host setting; environment is the daemon's; publish(reach) receives each
 * reading.
 */
function create({ home, mainHost, environment, publish, log, clock = CLOCK, run = Child.run, place = SessionCommand.place }) {
    let last = null;
    let controller = null;
    let timer = null;
    let inFlight = Promise.resolve();
    let setting = Promise.resolve();
    // While a choice runs its setter, no read starts: the choice reads after.
    let choosing = false;
    // The setting the last choice's setter refused, {setting, cause}, or
    // null: the package kept its previous value, so its status names that
    // one, and the reading names the refusal until the next choice.
    let rejected = null;
    let closed = false;

    // The ready home's session command, {folder, command}, or {kind:
    // "blocked", block} (SessionCommand.place).
    function locate() {
        const folder = home();
        if (folder === null) return { kind: "blocked", block: "no-home" };
        try { return place(folder, environment.HOME); }
        catch (error) {
            log("jarvis: satellite=place cause=" + (error.code || "unexpected"));
            return { kind: "blocked", block: "home-unreadable" };
        }
    }

    function session(location, args, deadline, signal) {
        return run("setpriv", ["--pdeathsig", "KILL", "--", location.command, ...args, "--home", location.folder],
            { env: SessionCommand.callEnvironment(environment, SSH_ENVIRONMENT), cwd: location.folder,
                limit: OUTPUT_BYTES, deadline, group: true, signal });
    }

    async function read(signal) {
        const value = mainHost();
        if (value === "") return { kind: "main" };
        const location = locate();
        if (location.kind === "blocked") return { kind: "unavailable", host: hostOf(value), cause: location.block };
        if (rejected !== null && rejected.setting === settingOf(value, location.folder)) return refused(rejected.cause, value);
        const result = await session(location, ["status", "--main"], LOCAL_MS, signal);
        if (result.kind === "stopped" && result.reason === "cancelled") return null;
        if (result.kind !== "exited" || result.code !== 0) {
            // A package older than the satellite contract refuses the verb
            // on every read, which the reading names; any other failure of
            // a session program that is there is logged.
            if (result.kind === "exited" && ARGUMENTS.test(result.stderr)) return { kind: "unavailable", host: hostOf(value), cause: "package-old" };
            log("jarvis: satellite=status cause=" + (result.kind === "exited" ? "exit-" + result.code : result.reason));
            return { kind: "unavailable", host: hostOf(value), cause: "package-unread" };
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

    function stopRead() {
        if (timer !== null) clock.clear(timer);
        timer = null;
        if (controller !== null) controller.abort();
        controller = null;
    }

    // Read again now, ending a read under way, then every READ_EVERY_MS
    // while the setting names a main. Each hello that changes the setting or
    // the home, each choice and each forward reads again.
    function refresh() {
        if (closed || choosing) return;
        stopRead();
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
            show({ kind: "unavailable", host: hostOf(mainHost()), cause: "package-unread" });
        });
    }

    // Hand Main Jarvis host, as the setting reads now, to the package of the
    // ready home, one choice at a time in the order chosen, then read once.
    // FIELD is the setting the user chose, "mainHost" or "home". Only a
    // choice of Main Jarvis host clears the package's main: a Home choice
    // while the field is empty hands nothing, since that home's package
    // may name a main set by hand in its private env file (the package's
    // README), which VGS never reads.
    function choose(field) {
        setting = setting.then(async () => {
            if (closed) return;
            choosing = true;
            try {
                stopRead();
                if (field === "home" && mainHost() === "") return;
                rejected = null;
                const location = locate();
                if (location.kind === "blocked") {
                    // A home without the package holds no setting to clear,
                    // so only a named main is a hand-off lost.
                    if (mainHost() !== "") log("jarvis: satellite=main-host cause=" + location.block);
                    return;
                }
                const chosen = settingOf(mainHost(), location.folder);
                const result = await session(location, ["main-host", "--set=" + chosen], LOCAL_MS);
                if (result.kind === "exited" && result.code === 0) return;
                // A setter that is absent stores nothing and says so; the
                // status read then names the package as older than the
                // contract.
                if (result.kind === "exited" && ARGUMENTS.test(result.stderr)) {
                    log("jarvis: satellite=main-host cause=setter-absent");
                    return;
                }
                const named = result.kind === "exited" && result.code === 2 ? refusal("main-host", result.stderr) : undefined;
                const cause = named !== undefined ? named : result.kind !== "exited" ? result.reason : "exit-" + result.code;
                log("jarvis: satellite=main-host cause=" + cause);
                rejected = { setting: chosen, cause };
            } finally {
                choosing = false;
                refresh();
            }
        }).catch(error => log("jarvis: satellite=main-host cause=" + (error.code || "unexpected")));
        return setting;
    }

    const failed = cause => ({ outcome: "failed", content: "fleet-forward:" + cause });

    // The cause the package names for a queued forward, or "".
    function queuedCause(stdout) {
        let cause = "";
        try { cause = JSON.parse(stdout.trim()).cause; } catch { return ""; }
        return typeof cause === "string" && /^[a-z0-9-]{1,60}$/.test(cause) ? cause : "";
    }

    // CONFIRMED is the router's {ref, at, method} for the start the owner
    // confirmed (ToolRouter register).
    async function forward(call, confirmed) {
        if (Redact.secret(call.args.text)) return failed("secret");
        if (claims(call.args.text)) return failed("caller-claim");
        const location = locate();
        if (location.kind === "blocked") return failed(location.block);
        // The request as the user made it, spoken or typed: no VGS path knows
        // who spoke, so the record names no caller.
        const record = { v: 1, request: { ref: confirmed.ref, at: confirmed.at, text: call.args.text },
            confirmation: { ref: confirmed.ref, at: confirmed.at, method: confirmed.method } };
        const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "vgs-jarvis-forward-"));
        let result;
        try {
            const recordFile = path.join(scratch, "record.json");
            fs.writeFileSync(recordFile, JSON.stringify(record), { mode: 0o600, flag: "wx" });
            result = await session(location, ["forward", "--record", recordFile], FORWARD_MS);
        } finally { fs.rmSync(scratch, { recursive: true, force: true }); }
        if (result.kind === "error") return failed("spawn");
        if (result.kind !== "exited")
            return { outcome: "unknown", content: "Unknown: the forward ended before the Jarvis package answered, so the request may be in this computer's outbox or not." };
        if (result.code === 0)
            return { outcome: "completed", content: "Completed: the request reached your main Jarvis. Its answer comes in your Slack channel." };
        if (result.code === 75) {
            // A queued entry stays queued whatever its cause, and the
            // package's watch loop sends every queued entry again on each
            // pass (forward.py record, send, drain), so the answer states
            // only that. The cause may be this computer's own, such as an
            // ssh that could not start (forward.py host), so it blames no one.
            const cause = queuedCause(result.stdout);
            return { outcome: "completed", content: "Completed: the request is queued in this computer's outbox and not delivered yet"
                + (cause === "" ? "" : "; the Jarvis package's last attempt ended with " + cause)
                + ". The Jarvis package keeps sending it while its Jarvis session runs." };
        }
        if (result.code === 2 && ARGUMENTS.test(result.stderr.split("\n")[0])) return failed("package-old");
        const named = result.code === 2 ? refusal("forward", result.stderr) : undefined;
        if (named !== undefined) return failed(named);
        return { outcome: "unknown", content: "Unknown: the Jarvis package ended with exit " + result.code + ", so the request may be in this computer's outbox or not." };
    }

    // A satellite whose package reads the main this setting names.
    const forwarding = () => mainHost() !== "" && last !== null && last.kind === "satellite" && last.cause !== "setting-invalid";

    return {
        executor: { commands: [], timeoutMs: FORWARD_MS + 1000, cancellable: false,
            // Read at offer, route and start.
            available: forwarding,
            start(call, done, authorize, origin, confirmed) {
                forward(call, confirmed).then(answer => { done(answer); refresh(); },
                    error => done(failed(error.code || "unexpected")));
            } },
        refresh, choose,
        close() {
            closed = true;
            stopRead();
            return Promise.allSettled([inFlight, setting]);
        }
    };
}

module.exports = { create, reading, settingOf, READ_EVERY_MS };
