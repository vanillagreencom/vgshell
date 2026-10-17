#!/usr/bin/env node
// jarvisd --tree ABSOLUTE_VGS_TREE
// Stdin is the service's lease. EOF exits 0; a partial line or a refused
// message exits 65. Task-store or confirmation-audit failure exits 74. Node below 22 or a
// mute record failure exits 78. Stdout carries status/state
// messages and shell requests judged by JarvisProtocol; stderr carries keyed jarvis: failures.
// A reply for a request that awaits none exits 65 like any refused message.
// Startup validates coding-task records and publishes their durable producer,
// then TaskRunner observes them; tasks outlive this process and EOF stops
// only that observation. A task-stop intent answers with task-answer.
// Device discovery is read-only. The conversation owner raises the gate only for a
// ready speech adapter and brain; the local row is ready only after local setup
// published its runtime. EOF closes the audio owner and waits for all child exits.
"use strict";
const path = require("node:path");
const fs = require("node:fs");
const { StringDecoder } = require("node:string_decoder");
const Tasks = require("./Tasks.js");
const cp = require("node:child_process");

function refuse(code, reason) {
    process.stderr.write(reason + "\n");
    process.exitCode = code;
    process.stdin.destroy();
}

if (Number(process.versions.node.split(".")[0]) < 22) {
    refuse(78, "jarvis: node=" + process.versions.node + " need=22");
} else if (process.argv.length !== 4 || process.argv[2] !== "--tree" || !path.isAbsolute(process.argv[3])) {
    refuse(2, "jarvis: arguments=expected-tree");
} else {
    require("./Core.js").use(process.argv[3]);
    const Audit = require("./Audit.js");
    const ToolRouter = require("./ToolRouter.js");
    const ShellRequests = require("./ShellRequests.js");
    const Executors = require("./Executors.js");
    const Input = require("./Input.js");
    const Browser = require("./Browser.js");
    const Memory = require("./Memory.js");
    const Files = require("./Files.js");
    const Shell = require("./Shell.js");
    const TaskRunner = require("./TaskRunner.js");
    const TaskVoice = require("./TaskVoice.js");
    const Desktop = require("./Desktop.js");
    const ToolBridge = require("./ToolBridge.js");
    const HarnessGate = require("./HarnessGate.js");
    const ChainedEngine = require("./ChainedEngine.js");
    const { Accounts, accountRoots } = require("./Accounts.js");
    const Denied = require("./Denied.js");
    const Home = require("./Home.js");
    const FleetSetup = require("./fleet-setup.js");
    const Guidance = require("./Guidance.js");
    const { load } = require(path.join(process.argv[3], "bin/lib/qml-library.js"));
    const { commandFile, onPath } = require(path.join(process.argv[3], "bin/lib/judge-files.js"));
    const Protocol = load(path.join(__dirname, "../JarvisProtocol.js"));
    const Dispatch = load(path.join(process.argv[3], "shell/Core/Dispatch.js"));
    const Launch = load(path.join(process.argv[3], "shell/Commons/DesktopLaunch.js"));
    const Session = Protocol.Session;
    const { SessionRunner, unavailable } = require("./session-runner.js");
    const { Audio } = require("./Audio.js");
    const decoder = new StringDecoder("utf8");
    let tail = "";
    let context = null;
    let ending = false;
    let seq = 0;
    let audit = null;
    let requests = null;
    let engine = null;
    let executors = null;
    let input = null;
    let browser = null;
    let memory = null;
    let memoryReconcileHome = null;
    let memoryReconcileQueued = false;
    let files = null;
    let shell = null;
    let requirementsScan = -1;
    const clock = { now: () => performance.now(), set: (fn, ms) => setTimeout(fn, ms), clear: timer => clearTimeout(timer) };
    let tasks = null;
    let publishedTasks = null;
    let publishedVoices = null;
    let voice = null;
    let bridge = null;
    let gate = null;
    // The user's home folder as it was last judged: path is the folder the
    // setting names, or null, and state what the engine and help read.
    let homeFolder = { path: null, state: { kind: "none" } };
    let homes = [];
    let fleetSetup = Promise.resolve();
    const fleetController = new AbortController();

    function startFleetCutover() {
        if (homeFolder.state.kind !== "ready") return;
        const target = homeFolder.state.path;
        // Only first hello produces an automatic attempt. The lock owner
        // rechecks eligibility before it consumes the durable record.
        try { if (Home.mailCutover(target) !== "eligible") return; }
        catch (error) {
            process.stderr.write("jarvis: fleet-setup=refused " + error.message + "\n");
            return;
        }
        fleetSetup = FleetSetup.install(process.argv[3], target, true, process.env, fleetController.signal).then(result => {
            if (ending) return;
            if (result.kind !== "exited" || result.code !== 0) {
                const key = result.kind === "exited" ? result.code === 75 ? "busy" : "install-failed" : result.reason;
                process.stderr.write("jarvis: fleet-setup=" + key + "\n");
                if (result.stderr) process.stderr.write(result.stderr);
            }
            if (Home.resolve(context.settings.home, process.env.HOME) !== target) return;
            judgeSetup();
        }).catch(error => {
            if (!ending) process.stderr.write("jarvis: fleet-setup=refused " + error.message + "\n");
        });
    }

    // Each judgement names the folder again and creates what it lacks; a
    // refused folder holds the engine with its keyed cause, and the gate
    // guards it while the setting names it.
    function judgeHome(setting) {
        let folder = null;
        try {
            folder = Home.resolve(setting, process.env.HOME);
            if (folder === null) return { path: null, state: { kind: "none" } };
            Home.layout(folder);
            return { path: folder, state: { kind: "ready", path: folder } };
        } catch (error) {
            const cause = /^jarvis: (home=[a-z-]{1,60})$/.exec(error.message)?.[1];
            if (cause === undefined) throw error;
            process.stderr.write("jarvis: " + cause + "\n");
            return { path: folder, state: { kind: "refused", cause } };
        }
    }

    function configured(configuration) {
        if (ending) return;
        // The offers go before the status that answers a hello, so the
        // status's reader holds them.
        publishVoices();
        write({ v: 1, type: "status", gen: runner.state.gen, revision: context.revision,
            daemon: context.locked ? "locked" : "ready",
            causes: configuration.kind === "ready" ? [] : configuration.causes, cautions: configuration.cautions });
        // A selected healthy loading plan can accept bounded capture. The
        // loading cause remains until the same child reports model readiness.
        // Session still owns lock, mute, fault and indicator admission.
        runner.dispatch({ type: "snapshot", locked: context.locked, engine: engine.engine(),
            configured: configuration.kind === "ready" || configuration.kind === "loading", checkReady: engine.checkReady(), settings: context.settings });
    }

    // Judge the home and the engine again; the status carries each failing
    // setup step's cause, and each home text over its budget, for the
    // shell's setup view.
    function judgeSetup() {
        homeFolder = judgeHome(context.settings.home);
        rememberHome();
        publishHomes();
        publishPersonality();
        configured(engine.configure(context.settings));
        scheduleMemoryReconcile();
    }

    function rememberHome() {
        if (homeFolder.state.kind !== "ready" || homes[0] === homeFolder.state.path) return;
        homes = Home.remember(homes, homeFolder.state.path, process.env.HOME);
        storeHomes(homes);
    }

    function scheduleMemoryReconcile() {
        if (memory === null || homeFolder.state.kind !== "ready" || memoryReconcileHome === homeFolder.state.path
                || memoryReconcileQueued) return;
        const target = homeFolder.state.path;
        memoryReconcileQueued = true;
        setImmediate(() => {
            memoryReconcileQueued = false;
            if (ending || memory === null || homeFolder.state.kind !== "ready" || homeFolder.state.path !== target) return;
            if (memory.reconcileStart()) memoryReconcileHome = target;
        });
    }

    function teardown() {
        fleetController.abort();
        if (voice !== null) voice.close();
        // The bridge ends its connections while the router can still drop their results.
        if (bridge !== null) bridge.close();
        if (gate !== null) gate.close();
        if (shell !== null) shell.close();
        runner.close();
        if (engine !== null) engine.close();
        if (executors !== null) executors.close();
        if (input !== null) input.close();
        if (files !== null) files.close();
        if (browser !== null) {
            try { browser.close(); }
            catch (error) { process.stderr.write(error.message + "\n"); process.exitCode = 74; }
        }
        if (memory !== null) {
            try { memory.close(); }
            catch (error) { process.stderr.write(error.message + "\n"); process.exitCode = 74; }
        }
        if (requests !== null) requests.close();
        if (audit !== null) audit.close();
        if (tasks !== null) tasks.close();
    }

    function fatal(error) {
        ending = true;
        teardown();
        void audio.close("protocol");
        refuse(error.message.startsWith("jarvis: tasks=") || error.message.startsWith("jarvis: task=")
            || error.message.startsWith("jarvis: audit=") ? 74
            : error.message.startsWith("jarvis: mute=") ? 78 : 65, error.message);
    }

    // Adapt the shared request result to the task display's text contract.
    function taskTui(args) {
        if (ending || context === null) return Promise.resolve("refused: daemon=ending");
        return new Promise(resolve => {
            requests.send("tui.run", args, 20000, result => {
                switch (result.kind) {
                case "answer": resolve(result.answer); break;
                case "busy": resolve("refused: request=tui.run reason=busy"); break;
                case "timeout": resolve("refused: request=tui.run reason=timeout"); break;
                case "refused": resolve(result.reason); break;
                default: throw new Error("jarvis: requests=result-kind");
                }
            });
        });
    }

    // Typed and spoken answers alike: a locked session answers no prompt.
    function answerTask(task, prompt, value) {
        const answer = context.locked ? "session-locked" : tasks.answer(task, prompt, value);
        return answer;
    }

    // The one producer of the protected path snapshot, rebuilt for every
    // judge from trusted roots: the daemon's XDG roots, the plugin directory
    // it runs from and the account roots, since roots and links can change
    // between calls. A failed build throws; no default stands in.
    function trustedRoots() {
        const home = process.env.HOME;
        if (typeof home !== "string" || home === "") throw new Error("jarvis: paths=home");
        return { home,
            config: process.env.XDG_CONFIG_HOME || path.join(home, ".config"),
            data: process.env.XDG_DATA_HOME || path.join(home, ".local/share"),
            state: process.env.XDG_STATE_HOME || path.join(home, ".local/state"),
            runtime: process.env.XDG_RUNTIME_DIR, install: path.dirname(__dirname),
            jarvisHome: homeFolder.path === null ? null : Home.guard(homeFolder.path),
            accountRoots: accountRoots(context.directories.state, process.env) };
    }

    function denied() { return Denied.create(trustedRoots());
    }

    // Policy refuses every path-bearing call as path-context without it, and
    // the daemon logs the cause as one keyed line.
    function deniedOrNull() {
        try { return denied(); } catch (error) {
            const cause = /^jarvis(?:-[a-z]+)?: ([a-z-]+=[a-z0-9-]+)/.exec(error.message)?.[1] ?? error.code ?? "unknown";
            process.stderr.write("jarvis: denied=unavailable cause=" + cause + "\n");
            return null;
        }
    }

    // hyprctl finds this session's socket from these alone.
    function hyprctlEnvironment() {
        const environment = { PATH: process.env.PATH || "/usr/bin:/bin", LANG: "C.UTF-8" };
        for (const name of ["XDG_RUNTIME_DIR", "HYPRLAND_INSTANCE_SIGNATURE"])
            if (process.env[name] !== undefined) environment[name] = process.env[name];
        return environment;
    }

    function intentIdentity(message) {
        if (context === null || message.revision !== context.revision)
            throw new Error("jarvis: protocol=identity");
    }

    function readRecord(area, name, limit, judge, absent) {
        let fd;
        try {
            fd = fs.openSync(path.join(context.directories.state, name),
                fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
            if (!fs.fstatSync(fd).isFile()) throw new Error("jarvis: " + area + "=record-not-file");
            const bytes = Buffer.alloc(limit + 1);
            const size = fs.readSync(fd, bytes, 0, bytes.length, 0);
            if (size > limit) throw new Error("jarvis: " + area + "=record-size");
            let value;
            try { value = JSON.parse(bytes.subarray(0, size).toString("utf8")); }
            catch { throw new Error("jarvis: " + area + "=record-json"); }
            return judge(value);
        } catch (error) {
            if (error.code === "ENOENT") return absent;
            if (error.message.startsWith("jarvis: " + area + "=")) throw error;
            throw new Error("jarvis: " + area + "=read-failed");
        } finally {
            if (fd !== undefined) {
                try { fs.closeSync(fd); } catch { throw new Error("jarvis: " + area + "=read-close-failed"); }
            }
        }
    }

    function storeRecord(area, name, value) {
        const directory = context.directories.state;
        const file = path.join(directory, "." + name + "-" + process.pid);
        let fd;
        let owned = false;
        try {
            fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
            fd = fs.openSync(file, "wx", 0o600);
            owned = true;
            fs.writeFileSync(fd, JSON.stringify(value) + "\n");
            fs.closeSync(fd);
            fd = undefined;
            fs.renameSync(file, path.join(directory, name));
        } catch (error) {
            if (error.message.startsWith("jarvis: " + area + "=")) throw error;
            throw new Error("jarvis: " + area + "=write-failed");
        } finally {
            if (fd !== undefined) {
                try { fs.closeSync(fd); } catch { throw new Error("jarvis: " + area + "=write-close-failed"); }
            }
            if (owned) {
                try { fs.unlinkSync(file); }
                catch (error) { if (error.code !== "ENOENT") throw new Error("jarvis: " + area + "=cleanup-failed"); }
            }
        }
    }

    function readMute() {
        return readRecord("mute", "mute.json", 64, value => {
            if (value === null || typeof value !== "object" || Array.isArray(value)
                    || Object.keys(value).join(",") !== "muted" || typeof value.muted !== "boolean")
                throw new Error("jarvis: mute=record-shape");
            return value.muted;
        }, false);
    }

    function storeMute(muted) { storeRecord("mute", "mute.json", { muted }); }

    function readHomes() {
        try {
            return readRecord("homes", "homes.json", 40960, value => {
                if (value === null || typeof value !== "object" || Array.isArray(value)
                        || Object.keys(value).join(",") !== "homes" || !Array.isArray(value.homes))
                    throw new Error("jarvis: homes=record-shape");
                // An entry outside this HOME or past the offer bounds is a stale
                // offer, dropped without a fault.
                return Home.remembered(value.homes, process.env.HOME);
            }, []);
        } catch (error) {
            const reason = /^jarvis: homes=([a-z-]+)$/.exec(error.message);
            if (reason !== null) {
                process.stderr.write(error.message + "\n");
                return [];
            }
            throw error;
        }
    }

    function storeHomes(value) {
        try { storeRecord("homes", "homes.json", { homes: value }); }
        catch (error) {
            const reason = /^jarvis: homes=([a-z-]+)$/.exec(error.message);
            if (reason !== null) process.stderr.write(error.message + "\n");
            else throw error;
        }
    }

    function publishHomes() {
        write({ v: 1, type: "homes", gen: runner.state.gen, revision: context.revision,
            homes: Home.offers(homes, process.env.HOME),
            current: homeFolder.state.kind === "ready" ? Home.relativeHome(homeFolder.state.path, process.env.HOME) : "" });
    }

    // The Voice setting's offers, sent when they change: a provider or tier
    // whose voices cannot be read offers none, and the setting stays.
    function publishVoices() {
        const voices = engine.voices().map(voice => ({ label: voice.label, value: voice.value }));
        const signature = JSON.stringify(voices);
        if (signature === publishedVoices) return;
        publishedVoices = signature;
        write({ v: 1, type: "voices", gen: runner.state.gen, revision: context.revision, voices });
    }

    // The home's Personality section as the Settings page shows it, read
    // again at each judgement: a hello follows the page's opening.
    function publishPersonality() {
        let personality = { kind: homeFolder.state.kind === "none" ? "none" : "unreadable" };
        if (homeFolder.state.kind === "ready") {
            try {
                const section = Guidance.personality(homeFolder.state.path);
                personality = section.kind === "section" ? Protocol.personalitySection(section.text) : section;
            } catch (error) {
                if (!/^jarvis: home=[a-z-]{1,60}$/.test(error.message)) throw error;
            }
        }
        write({ v: 1, type: "personality", gen: runner.state.gen, revision: context.revision, personality });
    }

    function fault(reason) {
        if (!ending && context !== null) write({ v: 1, type: "audio-fault", gen: runner.state.gen,
            revision: context.revision, reason: String(reason).replace(/[\x00-\x1f\x7f]/g, " ").slice(0, 180) });
    }

    function write(message) {
        const wire = JSON.stringify(message);
        Protocol.accept(wire, "daemon");
        if (process.stdout.writableLength + Buffer.byteLength(wire + "\n") > Protocol.MAX_LINE_BYTES) {
            ioFailed("stdout", { code: "overflow" });
            return;
        }
        if (!process.stdout.write(wire + "\n")) process.stdin.pause();
    }

    function memoryInboxMessage(entries = null) {
        return { v: 1, type: "memory-inbox", gen: runner.state.gen, revision: context.revision,
            entries: Protocol.memoryInboxEntries(entries === null ? memory.pending() : entries) };
    }

    function writeMemoryInbox(entries = null) {
        if (ending || context === null || memory === null) return;
        try { write(memoryInboxMessage(entries)); }
        catch (error) { process.stderr.write("jarvis: memory=inbox-publish\n"); }
    }
    const audio = new Audio({
        session: Session, environment: process.env, clock: {
            now: () => performance.now(), set: (fn, ms) => setTimeout(fn, ms), clear: timer => clearTimeout(timer)
        },
        offers: devices => {
            if (!ending && context !== null) write({ v: 1, type: "devices", gen: runner.state.gen,
                revision: context.revision, ...devices });
        },
        level: (gen, level) => {
            if (!ending && context !== null) write({ v: 1, type: "level", gen,
                revision: context.revision, level });
        },
        fault, captureSink: null, playbackSource: null
    });
    const ports = unavailable();
    ports.capture = { ...ports.capture, ...audio.capturePort };
    ports.playback = audio.playbackPort;
    ports.mute = { store: storeMute };
    ports.transcript = e => {
        if (!ending && context !== null) write({ v: 1, type: "transcript", gen: e.gen,
            revision: context.revision, role: e.role,
            text: e.text.replace(/[\x00-\x1f\x7f]/g, " ").slice(-Protocol.TRANSCRIPT_CHARS), stage: e.stage, rev: e.rev });
    };
    const runner = new SessionRunner(Session, ports, {
        now: () => performance.now(), set: (fn, ms) => setTimeout(fn, ms), clear: timer => clearTimeout(timer)
    }, (state, phase) => {
        audio.observe(state);
        if (engine !== null) engine.observe(state);
        if (voice !== null) voice.session(state);
        if (state.gate.kind === "down" && !Session.canCapture(state)) void audio.teardown("gate", ["capture", "playback"]);
        if (!ending && context !== null) write({ v: 1, type: "state", gen: state.gen,
            revision: context.revision, seq: ++seq, state, phase, brain: engine === null ? "" : engine.answering() });
    });

    function read(chunk) {
        if (ending) return;
        try {
            const framed = Protocol.feed(tail, chunk);
            tail = framed.tail;
            for (const line of framed.lines) {
                const message = Protocol.accept(line, "shell");
                if (message.type === "intent" && message.intent === "task-open") {
                    intentIdentity(message);
                    void (context.locked ? Promise.resolve("session-locked") : tasks.open(message.task)).then(answer => {
                        if (!ending) write({ v: 1, type: "task-open", gen: runner.state.gen,
                            revision: context.revision, task: message.task, answer });
                    });
                    continue;
                }
                if (message.type === "intent" && message.intent === "task-stop") {
                    intentIdentity(message);
                    const task = message.task;
                    void tasks.stop(task).then(answer => {
                        if (!ending) write({ v: 1, type: "task-answer", gen: runner.state.gen,
                            revision: context.revision, task, answer });
                    });
                    continue;
                }
                if (message.type === "intent" && (message.intent === "memory-confirm" || message.intent === "memory-discard")) {
                    intentIdentity(message);
                    try {
                        if (memory === null) throw new Error("jarvis: memory=unavailable");
                        if (message.intent === "memory-confirm") memory.confirm(message.id, message.hash);
                        else memory.discard(message.id, message.hash);
                    } catch (error) {
                        const cause = /^jarvis: memory=([a-z-]+)$/.exec(error.message)?.[1] ?? "intent";
                        process.stderr.write("jarvis: memory=" + cause + "\n");
                    }
                    writeMemoryInbox();
                    continue;
                }
                if (message.type === "intent" && message.intent === "task-respond") {
                    intentIdentity(message);
                    const answer = answerTask(message.task, message.prompt, message.answer);
                    write({ v: 1, type: "task-response", gen: runner.state.gen,
                        revision: context.revision, task: message.task, prompt: message.prompt, answer });
                    void tasks.observe();
                    continue;
                }
                if (message.type === "requirements-scan") {
                    intentIdentity(message);
                    if (message.scan > requirementsScan) {
                        requirementsScan = message.scan;
                        void shell.refresh();
                    }
                    continue;
                }
                if (message.type === "tui-state") {
                    intentIdentity(message);
                    tasks.tuiState(message.running);
                    continue;
                }
                if (message.type === "reply") {
                    intentIdentity(message);
                    requests.reply(message);
                    continue;
                }
                if (message.type === "indicator") {
                    if (context === null || message.revision !== context.revision)
                        throw new Error("jarvis: protocol=indicator-identity");
                    // Mapping is service lifetime input, not a turn callback.
                    // A gone observation must close capture even across gen.
                    runner.dispatch({ type: "indicator", shown: message.shown });
                    continue;
                }
                if (message.type === "intent") {
                    intentIdentity(message);
                    // Key edges are ordered input, not asynchronous completions.
                    // The observed gen can lag a down followed immediately by up.
                    if (message.intent === "confirm" || message.intent === "cancel") {
                        runner.dispatch({ type: message.intent === "cancel" ? "approval-cancel" : "confirm",
                            gen: message.gen, id: message.id, digest: message.digest, source: message.source });
                    } else {
                        // No hello follows an edit inside the home folder, nor
                        // the network's return after a failed read of the
                        // ElevenLabs voices or a local model catalog. A request made while one holds
                        // the engine judges it again first: a repaired folder
                        // takes the request, and the voices are read again.
                        if ((message.intent === "talk-down" || message.intent === "say") && (engine.homeHeld() || engine.voicesHeld() || engine.modelsHeld())) judgeSetup();
                        const dispatch = () => {
                            runner.dispatch(message.intent === "mute" ? { type: "mute-toggle" }
                                : message.intent === "say" ? { type: "say", text: message.text }
                                : { type: message.intent });
                        };
                        if (["mute", "stop"].includes(message.intent)) audit.cleanup(message.intent, dispatch);
                        else dispatch();
                    }
                    continue;
                }
                if (message.type === "shown") {
                    intentIdentity(message);
                    const hold = runner.state.approval;
                    runner.dispatch({ type: "shown", gen: message.gen, op: hold.op, id: message.id });
                    continue;
                }
                if (context !== null && (message.revision !== context.revision
                        || JSON.stringify(message.directories) !== JSON.stringify(context.directories)))
                    throw new Error("jarvis: protocol=identity");
                const first = context === null;
                let taskEvent = null;
                if (first) {
                    taskEvent = Tasks.publish(message.directories.data, __dirname);
                    // A crash between an exit record and prune can leave an
                    // extra ended task. Recovery uses the same locked writer.
                    const recovered = cp.spawnSync(process.execPath,
                        [taskEvent, "--state", message.directories.state, "--prune"], {
                            env: { PATH: process.env.PATH || "/usr/bin:/bin", LANG: "C.UTF-8" },
                            encoding: "utf8", maxBuffer: 8192
                        });
                    if (recovered.error) throw new Error("jarvis: tasks=recovery:" + recovered.error.code);
                    if (recovered.status !== 0) throw new Error("jarvis: tasks=recovery status="
                        + recovered.status + " signal=" + recovered.signal + " cause=" + recovered.stderr.trim());
                }
                context = message;
                if (first) {
                    homes = readHomes();
                    publishHomes();
                    const auditFailures = rows => {
                        if (!ending) write({ v: 1, type: "audit-failures", gen: runner.state.gen,
                            revision: context.revision, rows });
                    };
                    audit = Audit.create({ state: context.directories.state, changed: auditFailures });
                    auditFailures(audit.failures());
                    fs.mkdirSync(context.directories.runtime, { recursive: true, mode: 0o700 });
                    const profile = () => runner.state.settings.policy ?? "standard";
                    const router = ToolRouter.create({ session: Session, state: () => runner.state,
                        dispatch: event => runner.dispatch(event), audit,
                        context: () => ({ profile: profile(), locked: context.locked, get denied() { return deniedOrNull(); } }),
                        result: value => gate.deliver(value) || bridge.deliver(value) || runner.ports.brain.outcome(value),
                        routed: turn => engine?.brain.routed(turn) });
                    // A harness brain opens the bridge's session for its conversation;
                    // until one is selected no socket exists.
                    bridge = ToolBridge.create({ router, state: () => runner.state, audit,
                        directory: context.directories.runtime, release: { prepare: (value, recipients) => engine.release.prepare(value, recipients) },
                        answered: (value, tool) => engine.brain.bridged(value, tool) });
                    gate = HarnessGate.create({ router, state: () => runner.state });
                    router.register("harness", gate.executor);
                    // Executor owners register only after their real probes.
                    Object.assign(runner.ports, router.ports);
                    shell = Shell.install({ router, roots: trustedRoots, failed: fatal,
                        status: availability => {
                            if (!ending) write({ v: 1, type: "shell-status", gen: runner.state.gen,
                                revision: context.revision, availability });
                        } });
                    requests = ShellRequests.create({ Protocol, clock, write: fields =>
                        write({ v: 1, type: "request", gen: runner.state.gen, revision: context.revision, ...fields }) });
                    executors = Executors.register(router, { find: commandFile, environment: process.env, clock,
                        desktop: { Dispatch, Launch, request: requests.send, clock,
                            environment: hyprctlEnvironment(), commands: ["gio"].filter(onPath) },
                        // The engine exists before the first turn that could route a capture.
                        vision: { directory: path.join(context.directories.runtime, "vision"), state: () => runner.state,
                            route: () => engine.images() ? "image" : "text",
                            privateWindows: () => context.settings.privateWindows } });
                    const environment = hyprctlEnvironment();
                    for (const name of ["WAYLAND_DISPLAY", "YDOTOOL_SOCKET"])
                        if (process.env[name] !== undefined) environment[name] = process.env[name];
                    input = Input.create({ request: requests.send, environment,
                        commands: ["wtype", "wlrctl", "ydotool"].filter(onPath) });
                    void input.ready().then(record => {
                        if (ending) return;
                        router.register("input", record);
                        if (record.commands.length > 0)
                            write({ v: 1, type: "input-ready", gen: runner.state.gen, revision: context.revision, commands: record.commands });
                    });
                    browser = Browser.install({ router, environment: process.env,
                        home: () => homeFolder.state.kind === "ready" ? homeFolder.state.path : null });
                    files = Files.install({ router, denied, clock });
                    memory = Memory.install({ router, directory: path.join(context.directories.state, "memory"),
                        home: () => homeFolder.state.kind === "ready" ? homeFolder.state.path : null,
                        log: line => process.stderr.write(line + "\n"),
                        notify: entries => writeMemoryInbox(entries) });
                    if (memory.kind === "refused") {
                        process.stderr.write("jarvis: " + memory.cause + "\n");
                        write({ v: 1, type: "memory", gen: runner.state.gen, revision: context.revision, cause: memory.cause });
                        memory = null;
                    }
                    const routerSync = runner.ports.tools.sync;
                    runner.ports.tools.sync = state => {
                        routerSync(state);
                        if (browser !== null) browser.sync(state);
                    };
                    // The daemon, not the model, writes every task line and
                    // runs its notification, outside the router and policy.
                    voice = TaskVoice.create({ session: Session, state: () => runner.state,
                        dispatch: event => runner.dispatch(event), log: line => process.stderr.write(line + "\n"),
                        notify: (title, body, signal) => {
                            const file = commandFile("notify-send");
                            return file === null ? null : Desktop.runCommand(file, "notify-send",
                                Desktop.ARGV["notify.notification"]({ title, body }), { environment: process.env, signal, clock });
                        } });
                    // The task executor needs an agent profile and a release port
                    // for the task's recipients. Task handoff orchestration owns
                    // that separate release decision. Until it registers the executor,
                    // TaskRunner only observes and stops recorded tasks.
                    tasks = TaskRunner.create({ directories: context.directories, engine: taskEvent, backend: __dirname,
                        settings: () => context.settings,
                        accounts: (agent, reference) => {
                            const account = new Accounts(context.directories.state, process.env).resolve(reference);
                            return account !== null && account.provider === agent && account.source.kind === "cli"
                                ? account.source.directory : null;
                        },
                        changed: views => {
                            voice.observe(views);
                            const rows = Tasks.rows(views);
                            const signature = JSON.stringify(rows);
                            if (!ending && signature !== publishedTasks) {
                                publishedTasks = signature;
                                write({ v: 1, type: "task-list", gen: runner.state.gen, revision: context.revision, rows });
                            }
                        },
                        promptsChanged: prompts => {
                            voice.prompts(prompts);
                            if (!ending) write({ v: 1, type: "task-prompts", gen: runner.state.gen,
                                revision: context.revision, prompts });
                        },
                        display: { run: taskTui },
                        count: count => {
                            if (!ending) write({ v: 1, type: "tasks", gen: runner.state.gen,
                                revision: context.revision, count });
                        },
                        failed: fatal,
                        clock: { now: Date.now, set: (fn, ms) => setTimeout(fn, ms).unref(), clear: timer => clearTimeout(timer) } });
                    const state = context.directories.state;
                    engine = ChainedEngine.create({ session: Session, state: () => runner.state, audit, router,
                        accounts: () => new Accounts(state, process.env), request: requests.send,
                        policy: () => ({ profile: profile(), cloudVision: context.settings.cloudVision }), fault,
                        captionLimit: Protocol.TRANSCRIPT_CHARS, dispatch: event => runner.dispatch(event), clock, configured, fatal,
                        log: line => process.stderr.write(line + "\n"),
                        harness: { bridge, gate, env: process.env, runtime: () => context.directories.runtime },
                        tasks: { held: () => tasks.held(),
                            answer: (task, prompt, value) => {
                                const answer = answerTask(task, prompt, value);
                                void tasks.observe();
                                return answer;
                            },
                            interrupted: (gen, ask) => voice.interrupted(gen, ask), released: (gen, ask) => voice.released(gen, ask),
                            withheld: (gen, text, ask) => voice.withheld(gen, text, ask) },
                        trace: { marker: process.env.VGS_TEST_RUN, file: process.env.VGS_JARVIS_TRACE },
                        directories: context.directories, home: () => homeFolder.state, rejudge: judgeSetup });
                    const actionApproval = runner.ports.approval;
                    runner.ports.approval = {
                        show: e => { if (e.purpose === "action") actionApproval.show(e); },
                        end: e => e.purpose === "release" ? engine.release.ended(e) : actionApproval.end(e),
                        refused: e => e.purpose === "release" ? engine.release.refused(e) : actionApproval.refused(e)
                    };
                    runner.ports.release = engine.release;
                    runner.ports.brain = engine.brain;
                    runner.ports.speech = engine.speech;
                    runner.ports.capture = { ...runner.ports.capture, collect: engine.collect };
                    runner.ports.playback = engine.playback(audio.playbackPort);
                    audio.captureSink = engine.captureSink;
                    audio.playbackSource = engine.playbackSource;
                }
                if (first && readMute()) runner.dispatch({ type: "mute" });
                judgeSetup();
                if (first) startFleetCutover();
                if (memory !== null) writeMemoryInbox();
                if (first) void audio.discover().catch(error => {
                    if (!ending) audio.fault(error.message);
                });
                if (first) void tasks.observe();
            }
        } catch (error) {
            fatal(error);
        }
    }
    process.stdout.on("drain", () => { if (!ending) process.stdin.resume(); });
    function ioFailed(channel, error) {
        if (ending) return;
        ending = true;
        teardown();
        const released = audio.close(channel);
        refuse(74, "jarvis: " + channel + "=" + error.code);
        // Node's standard output can retain a blocked write after destroy.
        // Audio exits first; a failed pipe cannot keep the daemon alive.
        void Promise.all([released, fleetSetup]).then(() => process.exit(74));
    }
    process.stdout.on("error", error => ioFailed("stdout", error));
    process.stdin.on("error", error => ioFailed("stdin", error));
    process.stdin.on("data", chunk => read(decoder.write(chunk)));
    function terminate() {
        if (ending) return;
        ending = true;
        teardown();
        void Promise.all([audio.close("lease"), fleetSetup]).then(() => process.exit(process.exitCode ?? 0));
    }
    process.once("SIGTERM", terminate);
    process.once("SIGINT", terminate);
    process.stdin.on("end", () => {
        read(decoder.end());
        if (ending) return;
        ending = true;
        teardown();
        void audio.close("lease");
        if (tail !== "") refuse(65, "jarvis: protocol=unterminated-line");
        // No child or handle holds the process alive after lease loss.
    });
}
