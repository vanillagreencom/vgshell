// The one owner of the Jarvis package's satellite contract: the
// fleet.forward executor, the hand-off of Main Jarvis host to the package's
// main-host setting, and the read of the main's reachability. Every call is
// the home's session command by argv (SessionCommand.place); the package
// owns the SSH connection, the outbox, retries and the answer.
"use strict";
const fs = require("node:fs");
const crypto = require("node:crypto");
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
const SESSION_PREFIX = "vgs-voice:";

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
        : { kind: "unavailable", host: hostOf(value), cause: cause === "setter-absent" ? "package-old" : "package-unread" };
}

/**
 * The reading `status --main` ANSWER gives for VALUE, the Main Jarvis host
 * setting: main only when both name this computer; {kind:"satellite", host,
 * reachable, cause} while the package names VALUE's main; else
 * {kind:"unavailable", host, cause}, "setting-unhanded" when the package
 * names this computer or another main, naming the package's host while
 * VALUE is empty; "package-unread" for any other answer.
 */
function reading(answer, value, acceptReach) {
    const host = hostOf(value);
    if (answer === null || typeof answer !== "object" || answer.v !== 1) return { kind: "unavailable", host, cause: "package-unread" };
    if (value === "") {
        if (answer.role === "main") return { kind: "main" };
        if (answer.role === "satellite") {
            const held = { kind: "unavailable", host: answer.main, cause: "setting-unhanded" };
            // The package's stored host bypasses the VGS setting's admission.
            // Use publication's wire judge before returning that new input.
            if (answer.main !== "" && acceptReach(held)) return held;
        }
        return { kind: "unavailable", host, cause: "package-unread" };
    }
    if (answer.role === "satellite" && answer.cause === "setting-invalid") return refused("setting-invalid", value);
    if (answer.role === "main" || answer.role === "satellite" && answer.main !== host)
        return { kind: "unavailable", host, cause: "setting-unhanded" };
    if (answer.role !== "satellite" || ![true, false, null].includes(answer.reachable))
        return { kind: "unavailable", host, cause: "package-unread" };
    return { kind: "satellite", host, reachable: answer.reachable,
        cause: answer.reachable === false ? "main-unreachable" : "" };
}

/**
 * create({home, homeBlock, mainHost, environment, publish, acceptReach, log}) builds the owner.
 * home() answers the ready home folder or null; homeBlock() answers, while
 * home() is null, "not-set-up" for a chosen folder Setup has yet to set up
 * (D126), else null for no folder; mainHost() the Main Jarvis
 * host setting; environment is the daemon's; publish(reach) receives each
 * reading; acceptReach is the wire's main-reach judge. runtime is the
 * daemon's private runtime directory; fatal ends it if a lease cannot retire.
 */
function create({ home, homeBlock = () => null, mainHost, environment, runtime, publish, acceptReach, log,
    fatal = error => { throw error; }, clock = CLOCK, run = Child.run, place = SessionCommand.place }) {
    let last = null;
    let controller = null;
    let timer = null;
    let inFlight = Promise.resolve();
    let setting = Promise.resolve();
    let started = false;
    // While a choice runs its setter, no read starts: the choice reads after.
    let choosing = false;
    // The setting the last choice's setter refused, {folder, setting, cause}, or
    // null: the package kept its previous value, so its status names that
    // one, and the reading names the refusal until the next choice.
    let rejected = null;
    let closed = false;
    let voiceSession = null;
    let binding = null;
    let lease = null;
    let owner = null;

    function retireLease() {
        const held = lease;
        lease = null;
        if (held === null) return;
        try {
            const parent = fs.lstatSync(held.folder, { throwIfNoEntry: false });
            if (parent === undefined) return;
            if (held.parent !== null && (parent.dev !== held.parent.dev || parent.ino !== held.parent.ino))
                throw new Error("ownership");
            if (held.file !== null) {
                const found = fs.lstatSync(held.file.path, { throwIfNoEntry: false });
                if (found !== undefined) {
                    if (found.dev !== held.file.dev || found.ino !== held.file.ino) throw new Error("ownership");
                    fs.unlinkSync(held.file.path);
                }
            }
            fs.rmdirSync(held.folder);
        } catch (error) {
            closed = true;
            stopRead();
            fatal(new Error("jarvis: satellite=lease-retire cause=" + (error.code || "ownership")));
        }
    }

    // The binding object is the router's revocation token: a new one, even
    // for the same generation (a main setting change or Stop), ends its grant.
    function currentSession() {
        if (closed || voiceSession === null) return null;
        const folder = home();
        const main = folder === null || mainHost() === "" ? null : settingOf(mainHost(), folder);
        if (binding !== null && (binding.home !== folder || binding.main !== main)) stopForwarding();
        if (closed || folder === null || main === null) return null;
        if (binding === null) binding = Object.freeze({ id: voiceSession.id, name: voiceSession.name, home: folder, main });
        return binding;
    }

    function stopForwarding() {
        retireLease();
        binding = null;
    }

    function sync(state) {
        if (closed) return;
        if (state.conversation.kind === "ended" || state.conversation.purpose === "preview"
                || voiceSession !== null && voiceSession.gen !== state.gen) {
            stopForwarding();
            voiceSession = null;
        }
        if (closed || state.conversation.kind === "ended" || state.conversation.purpose === "preview") return;
        if (voiceSession === null) {
            const uuid = crypto.randomUUID();
            voiceSession = { gen: state.gen, id: SESSION_PREFIX + uuid, name: "Jarvis Voice " + uuid, stops: state.stops };
        } else if (voiceSession.stops !== state.stops) {
            voiceSession.stops = state.stops;
            stopForwarding();
        }
        currentSession();
    }

    // liveLease's own refusals carry their cause as the code forward logs.
    const leaseRefusal = cause => Object.assign(new Error(cause), { code: cause });

    function liveLease(selected, confirmation) {
        if (lease !== null && lease.confirmation === confirmation.ref) return lease.file.path;
        retireLease();
        // Linux proc_pid_stat(5): field 2 can contain spaces and ')'; after
        // its last ')' field 22 is index 19. boot_id is constant per boot
        // (docs.kernel.org/admin-guide/sysctl/kernel.html#random).
        if (owner === null) {
            const stat = fs.readFileSync("/proc/self/stat", "utf8");
            const start = stat.slice(stat.lastIndexOf(")") + 2).trim().split(/\s+/)[19];
            const boot = fs.readFileSync("/proc/sys/kernel/random/boot_id", "utf8").trim();
            if (!/^[0-9]+$/.test(start) || !/^[0-9a-f-]{36}$/.test(boot)) throw leaseRefusal("owner-unread");
            owner = { pid: process.pid, start, boot };
        }
        const folder = path.join(runtime, "forward-sessions");
        fs.mkdirSync(folder, { recursive: true, mode: 0o700 });
        const directory = fs.lstatSync(folder);
        if (!directory.isDirectory() || directory.uid !== process.getuid() || (directory.mode & 0o077) !== 0)
            throw leaseRefusal("lease-directory");
        // The filename binds the session; a fresh parent binds the grant so
        // reconfirmation cannot revive stopped queued records (D134).
        const grantFolder = path.join(folder, crypto.randomUUID());
        const file = path.join(grantFolder, selected.id.slice(SESSION_PREFIX.length) + ".json");
        fs.mkdirSync(grantFolder, { mode: 0o700 });
        lease = { folder: grantFolder, parent: null, file: null, confirmation: confirmation.ref };
        let fd = null;
        try {
            lease.parent = fs.lstatSync(grantFolder);
            fd = fs.openSync(file, "wx", 0o600);
            const found = fs.fstatSync(fd);
            lease.file = { path: file, dev: found.dev, ino: found.ino };
            // REVISIT(D134): Kendex's forward/drain checks this lease once
            // before each send attempt; unlink is Stop/end, owner is crash identity.
            fs.writeFileSync(fd, JSON.stringify({ v: 1, id: selected.id, main: selected.main, owner }));
        } catch (error) { retireLease(); throw error; }
        finally { if (fd !== null) fs.closeSync(fd); }
        return file;
    }

    // The ready home's session command, {folder, command}, or {kind:
    // "blocked", block} (SessionCommand.place).
    function locate() {
        const folder = home();
        if (folder === null) return { kind: "blocked", block: homeBlock() ?? "no-home" };
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
        const location = locate();
        if (location.kind !== "blocked" && rejected !== null && rejected.folder === location.folder
            && rejected.setting === settingOf(value, location.folder)) return refused(rejected.cause, value);
        if (location.kind === "blocked") return { kind: "unavailable", host: hostOf(value), cause: location.block };
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
        return reading(answer, value, acceptReach);
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

    // Hand a named host once at startup, then read again now, ending a read
    // under way, and every READ_EVERY_MS while the setting names a main.
    // Each changed hello, choice and forward reads again.
    function refresh() {
        if (closed || choosing) return;
        if (!started) {
            started = true;
            // main-host --set judges before writing (KEN-4874, session.py
            // main_host). Replaying a named host recovers its refusal after
            // restart. Never replay an empty field: the package may hold a
            // main set by hand. A missing setter is attempted only once.
            if (mainHost() !== "") { choose("startup"); return; }
        }
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
    // FIELD is "startup" or the setting the user chose, "mainHost" or
    // "home". Keep that origin through the queue: a changed hello can clear
    // the field before the startup operation runs. Only a
    // choice of Main Jarvis host clears the package's main: a Home choice
    // while the field is empty hands nothing, since that home's package
    // may name a main set by hand in its private env file (the package's
    // README), which VGS never reads.
    function choose(field) {
        started = true;
        setting = setting.then(async () => {
            if (closed) return;
            choosing = true;
            try {
                stopRead();
                if (field !== "mainHost" && mainHost() === "") return;
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
                // A setter that is absent stores nothing and identifies an
                // older package even if its status names a different main.
                if (result.kind === "exited" && ARGUMENTS.test(result.stderr)) {
                    log("jarvis: satellite=main-host cause=setter-absent");
                    rejected = { folder: location.folder, setting: chosen, cause: "setter-absent" };
                    return;
                }
                const named = result.kind === "exited" && result.code === 2 ? refusal("main-host", result.stderr) : undefined;
                const cause = named !== undefined ? named : result.kind !== "exited" ? result.reason : "exit-" + result.code;
                log("jarvis: satellite=main-host cause=" + cause);
                rejected = { folder: location.folder, setting: chosen, cause };
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

    // The router supplies the request's own row, the accepted consent and
    // the exact trusted live-session binding, never model metadata.
    async function forward(call, confirmed, authorize) {
        if (Redact.secret(call.args.text)) return failed("secret");
        if (claims(call.args.text)) return failed("caller-claim");
        const location = locate();
        if (location.kind === "blocked") return failed(location.block);
        // The router owns the binding's currency; nothing awaits between
        // this answer and the spawn, and a refused binding publishes no lease.
        const authority = authorize();
        if (authority.kind !== "allow") return failed(authority.reason);
        const record = { v: 1, request: { ...confirmed.request, text: call.args.text }, confirmation: confirmed.confirmation };
        if (confirmed.confirmation.scope === "session") {
            try {
                record.session = { id: confirmed.session.id, name: confirmed.session.name, main: confirmed.session.main,
                    lease: liveLease(confirmed.session, confirmed.confirmation) };
            }
            catch (error) {
                log("jarvis: satellite=lease-create cause=" + (error.code || "unavailable"));
                return failed("lease-unavailable");
            }
        }
        // The request as the user made it, spoken or typed: no VGS path knows
        // who spoke, so the record names no caller.
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
            return { outcome: "completed", content: "Completed: the request reached Jarvis main." };
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
                forward(call, confirmed, authorize).then(answer => { done(answer); refresh(); },
                    error => done(failed(error.code || "unexpected")));
            } },
        stopExecutor: { commands: [], timeoutMs: LOCAL_MS, cancellable: false,
            available: () => !closed && voiceSession !== null && mainHost() !== "",
            start(_call, done) {
                stopForwarding();
                done({ outcome: "completed", content: "Completed: forwarding from this conversation stopped." });
            } },
        refresh, choose, sync, session: currentSession,
        close() {
            if (closed) return Promise.allSettled([inFlight, setting]);
            closed = true;
            stopForwarding();
            voiceSession = null;
            stopRead();
            return Promise.allSettled([inFlight, setting]);
        }
    };
}

module.exports = { create, reading, settingOf, READ_EVERY_MS };
