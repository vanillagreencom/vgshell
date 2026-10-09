#!/usr/bin/env node
// The chained engine through the real Session, runner, Audio, router, audit,
// release gate and wire brain, with scripted speech adapters and a loopback
// brain inside the J09 world. Every request body is read at the server.
"use strict";
const { assert, fs, path, cp, tree, world, until: wait } = require("./fixtures/jarvis/audio.js");
const { once } = require("node:events");
const { clock, turn } = require("./fixtures/jarvis/playback.js");
const Fixture = require("./fixtures/jarvis/engine.js");
const vm = require("node:vm");
const { load } = require("../bin/lib/qml-library.js");
const { utterance, text, calls, control } = Fixture;
// The ollama row's default port: free inside the private network namespace.
const PORT = 11434;
// Bounds a missing observation, not a latency: each rig runs real capture and
// player children, which a loaded host can delay.
const OBSERVE_MS = 15000;
const until = (check, message) => wait(check, message, OBSERVE_MS);
const INTERRUPTED = "[interrupted] The user heard none of your last reply.";
// A synthetic screen image the vision stand-in answers with.
const PNG = Buffer.from("89504e470d0a1a0a0000000d49484452", "hex");
const heardOnly = prefix => "[interrupted] The user heard only this part of your last reply: \"" + prefix + "\"";
// A reply that opens its stream, then waits for the case's gate.
const pause = held => [{ delta: { role: "assistant", content: "" }, finish_reason: null }, { wait: held.wait }];
function gate() {
    let open;
    const wait = new Promise(resolve => { open = resolve; });
    return { wait, open };
}

function rig(kit, server, options = {}) {
    const backend = name => require(path.join(kit.folder, "backend", name));
    const Session = load(path.join(kit.folder, "Session.js"));
    const Protocol = load(path.join(kit.folder, "JarvisProtocol.js"));
    const { SessionRunner, unavailable } = backend("session-runner.js");
    const { Audio } = backend("Audio.js");
    const Audit = backend("Audit.js");
    const Router = backend("ToolRouter.js");
    const Denied = backend("Denied.js");
    const audioClock = clock();
    // Session deadlines run on an injected clock that only the case advances.
    let at = 0;
    const timers = new Map();
    const runnerClock = { now: () => at, set: (fn, ms) => { const key = {}; timers.set(key, { fn, at: at + ms }); return key; },
        clear: key => timers.delete(key) };
    const advanceRunner = ms => {
        at += ms;
        for (const [key, timer] of [...timers]) if (timer.at <= at) { timers.delete(key); timer.fn(); }
    };
    const state = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "state-"));
    const workspace = options.actionApproval ? fs.mkdtempSync(path.join(process.env.HOME, "workspace-")) : null;
    const audit = Audit.create({ state, now: () => Date.UTC(2026, 9, 1) });
    const faults = [], executions = [], held = [], partials = [], captions = [];
    const audio = new Audio({ session: Session, environment: { PATH: process.env.PATH, HOME: process.env.HOME,
        XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR }, clock: audioClock, offers: () => {}, level: () => {},
    fault: reason => faults.push(reason), captureSink: null, playbackSource: null });
    const writes = [];
    const spawn = audio.spawn.bind(audio);
    audio.spawn = async (...args) => {
        const owner = await spawn(...args);
        if (args[0] === "playback") {
            const write = owner.child.stdin.write.bind(owner.child.stdin);
            owner.child.stdin.write = (pcm, ...rest) => {
                writes.push({ at: performance.now(), source: audio.playback.e.source, pcm: Buffer.from(pcm) });
                return write(pcm, ...rest);
            };
        }
        return owner;
    };
    const ports = { ...unavailable(), mute: { store() {} } };
    ports.capture = { ...ports.capture, ...audio.capturePort };
    ports.transcript = e => captions.push([e.gen, e.role, e.stage, e.rev, e.text]);
    let engine = null;
    let voice = null;
    const runner = new SessionRunner(Session, ports, runnerClock, s => {
        audio.observe(s);
        if (engine !== null) engine.observe(s);
        if (voice !== null) voice.session(s);
        if (s.gate.kind === "down") void audio.teardown("gate", ["capture", "playback"]);
        if (s.turn.kind === "collecting" && s.turn.partial !== "" && partials.at(-1) !== s.turn.partial)
            partials.push(s.turn.partial);
    });
    const router = Router.create({ session: Session, state: () => runner.state, dispatch: e => runner.dispatch(e), audit,
        context: () => ({ profile: "standard", locked: false, denied: options.actionApproval ? Denied.create({
            home: process.env.HOME, config: process.env.XDG_CONFIG_HOME, data: process.env.XDG_DATA_HOME,
            state: process.env.XDG_STATE_HOME, runtime: process.env.XDG_RUNTIME_DIR, install: kit.folder, accountRoots: []
        }) : null }),
        result: value => runner.ports.brain.outcome(value) });
    Object.assign(ports, router.ports);
    // The callback stands in for a command-ready executor; it never starts hyprctl.
    router.register("compositor", { commands: ["hyprctl"], timeoutMs: 30000, cancellable: false, start(call, done) {
        executions.push(call);
        if (options.holdTools) held.push(done);
        else done({ outcome: "completed", content: "focused " + call.args.window });
    } });
    router.register("clipboard", { commands: ["wl-paste"], timeoutMs: 30000, cancellable: false, start(call, done) {
        executions.push(call);
        done({ outcome: "completed", content: "clipboard words" });
    } });
    router.register("vision", { commands: ["grim"], timeoutMs: 30000, cancellable: false, start(call, done) {
        executions.push(call);
        done({ outcome: "completed", content: "screen text", image: { type: "image/png", bytes: PNG } });
    } });
    // The action approval case uses an inert executor, with no process.
    if (options.actionApproval) router.register("sandbox", { commands: ["bwrap"], timeoutMs: 30000,
        cancellable: false, start(call, done) {
            executions.push(call);
            done({ outcome: "completed", content: "fixture result" });
        } });
    // Accounts.choose has its own suite; this stand-in names a loopback row.
    const accounts = () => ({ secrets: null, choose: id => ({ kind: "accepted", account: { id, provider: "ollama", label: "local",
        source: { kind: "local", origin: "http://127.0.0.1:" + PORT }, model: "fixture-model" } }) });
    const configured = answer => runner.dispatch({ type: "snapshot", locked: false, engine: "chained",
        configured: answer.kind === "ready" || answer.kind === "loading", settings: runner.state.settings });
    const tasks = options.tasks ? taskWorld(kit, runner, Session, faults) : null;
    voice = tasks?.voice ?? null;
    engine = kit.Engine.create({ session: Session, state: () => runner.state, audit, router, accounts,
        policy: () => ({ profile: "standard", cloudVision: "ask" }), fault: reason => faults.push(reason),
        captionLimit: options.captionLimit ?? Protocol.TRANSCRIPT_CHARS, dispatch: e => runner.dispatch(e), clock: runnerClock,
        directories: options.directories, configured, tasks: tasks?.port ?? null });
    ports.release = engine.release;
    const actionApproval = ports.approval;
    const daemonSource = fs.readFileSync(path.join(kit.folder, "backend/jarvisd.js"), "utf8");
    const wiring = [...daemonSource.matchAll(/runner\.ports\.approval = (\{\n[\s\S]*?\n                    \});/g)];
    assert.equal(wiring.length, 1, "one shipped daemon approval wiring");
    ports.approval = vm.runInNewContext("(" + wiring[0][1] + ")", { engine, actionApproval });
    ports.brain = engine.brain;
    ports.capture.collect = engine.collect;
    ports.playback = engine.playback(audio.playbackPort);
    audio.captureSink = engine.captureSink;
    audio.playbackSource = engine.playbackSource;
    const configure = settings => {
        const answer = engine.configure(settings);
        runner.dispatch({ type: "snapshot", locked: false, engine: "chained",
            configured: answer.kind === "ready" || answer.kind === "loading", settings });
        return answer;
    };
    const configuration = configure({ mode: options.mode ?? "hold", sounds: options.sounds === true,
        microphone: "", speaker: "", brain: "fixture-account" });
    assert.equal(configuration.kind, options.directories ? "loading" : "ready");
    runner.dispatch({ type: "indicator", shown: true });
    const rows = () => {
        const file = path.join(state, "audit/2026-10-01.jsonl");
        return fs.existsSync(file) ? fs.readFileSync(file, "utf8").trim().split("\n").map(line => JSON.parse(line)) : [];
    };
    return { runner, audio, audioClock, engine, audit, faults, executions, held, partials, captions, rows, configure,
        state, workspace, server, advanceRunner, writes, timers, tasks,
        s: () => runner.state,
        async close() {
            tasks?.close();
            runner.close();
            engine.close();
            audit.close();
            await audio.close("test-end");
        } };
}

// Coding-task records and held prompts through the real producer, relay,
// TaskRunner and TaskVoice, wired to the engine by the shipped daemon's
// tasks port. Each task is alive as a sleeping group this world started, so
// observation keeps it without a launch. Notifications are recorded, not run.
function taskWorld(kit, runner, Session, faults) {
    const backend = path.join(kit.folder, "backend");
    const Tasks = require(path.join(backend, "Tasks.js"));
    const Relay = require(path.join(backend, "TaskRelay.js"));
    const TaskRunner = require(path.join(backend, "TaskRunner.js"));
    const TaskVoice = require(path.join(backend, "TaskVoice.js"));
    const root = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "tasks-"));
    const directories = { state: path.join(root, "state"), runtime: path.join(root, "run") };
    const producer = Tasks.publish(path.join(root, "data"), backend);
    const env = { PATH: process.env.PATH, LANG: "C.UTF-8" };
    const notes = [], logs = [];
    const voice = TaskVoice.create({ session: Session, state: () => runner.state, dispatch: e => runner.dispatch(e),
        notify: (title, body) => { notes.push([title, body]); return Promise.resolve({ kind: "exited", code: 0 }); },
        log: line => logs.push(line) });
    const tasks = TaskRunner.create({ directories, engine: producer, backend, settings: () => ({ taskTerminal: "floating" }),
        display: { run: () => Promise.resolve("refused") }, count() {}, failed: error => faults.push(error.message),
        changed: views => voice.observe(views), promptsChanged: list => voice.prompts(list),
        environment: env, lookup: () => false, clock: { now: Date.now, set: () => ({}), clear() {} } });
    const daemon = fs.readFileSync(path.join(backend, "jarvisd.js"), "utf8");
    const wiring = [...daemon.matchAll(/tasks: (\{ held: [\s\S]*?withheld\(gen, text, ask\) \}),\n/g)];
    assert.equal(wiring.length, 1, "one shipped daemon tasks port");
    const port = vm.runInNewContext("(" + wiring[0][1] + ")", { tasks, voice, answerTask: (...args) => tasks.answer(...args) });
    const event = (id, kind, data = {}) => {
        const result = cp.spawnSync(process.execPath, [producer, "--state", directories.state, id, kind],
            { env, input: JSON.stringify(data), encoding: "utf8", timeout: 10000 });
        assert.equal(result.status, 0, result.stderr);
    };
    const prompts = path.join(directories.runtime, "prompts");
    const groups = [];
    return { voice, port, notes, logs, prompts, Relay, TaskVoice,
        task(id) {
            const group = cp.spawn("sleep", ["600"], { detached: true, stdio: "ignore" });
            groups.push(group);
            const stat = fs.readFileSync("/proc/" + group.pid + "/stat", "utf8").split(") ")[1].split(" ");
            event(id, "create", { goal: "Fixture goal", cwd: process.env.HOME, agent: "fixture", account: "" });
            event(id, "started", { pid: group.pid, pgid: Number(stat[2]), sid: Number(stat[3]), startTime: stat[19] });
        },
        event,
        ask: (id, detail) => Relay.ask(prompts, id, detail, Date.now(), 600000),
        observe: () => tasks.observe(),
        close() {
            voice.close();
            tasks.close();
            for (const group of groups) group.kill("SIGKILL");
        }
    };
}

// One utterance through real capture: down, partials, up, final.
async function say(w, script, { waitPartial = true } = {}) {
    control.utterances.push(script);
    const before = w.server.requests.length;
    w.runner.dispatch({ type: "talk-down" });
    if (w.s().playback.kind === "feedback") await playOut(w);
    // An early final leaves collection; the case's own assertions judge it.
    const collecting = () => w.s().turn.kind === "collecting";
    await until(() => w.s().capture.kind === "open" || (w.s().turn.kind !== "none" && !collecting()),
        "capture opens from real fixture PCM");
    if (waitPartial && script.partials.length)
        await until(() => w.partials.at(-1) === script.partials.at(-1) || !collecting(), "partials reach Session");
    w.runner.dispatch({ type: "talk-up" });
    return before;
}
// Waits for an observation or for a state from which it can no longer come,
// then asserts the observation: a defect turns red once it settles, and the
// observation bound is left for a slow host.
async function settled(observed, over, message) {
    let seen = false;
    await until(() => (seen = observed()) || over(), message);
    assert.ok(seen, message);
}
async function requested(w, count, label, over = () => false) {
    await settled(() => w.server.requests.length >= count && w.server.requests[count - 1].body !== null, over, label);
    return w.server.requests[count - 1].body;
}
async function feeding(w, frames) {
    await until(() => w.audio.playback !== null && w.audio.playback.kind === "feeding"
        && w.audio.playback.received >= frames, "playback receives synthesized PCM");
}
// Advance the injected playback clock one node period at a time.
async function advance(w, periods) {
    for (let i = 0; i < periods; i++) {
        w.audioClock.advance(20);
        await turn();
    }
}
// Each poll advances the injected playback clock one node period. Child pipes
// and the stand-in player's exit cross real I/O, so the poll is short.
async function playOut(w) {
    await wait(() => {
        if (w.s().playback.kind === "idle") return true;
        w.audioClock.advance(20);
        return false;
    }, "playback completes", OBSERVE_MS, 1);
}
const user = body => body.messages.filter(message => message.role === "user").map(message => message.content);
const assistantCaptions = w => w.captions.filter(row => row[1] === "assistant");

// The real local row and sidecar wire with the interpreter stand-in. Session
// and Audio still own conversation admission and faults in this rig.
async function daemonSpeech(server, edits = [], scenario = "ready", firstEnding = "stop") {
    Fixture.reset();
    server.replies.length = 0;
    const kit = Fixture.copy(process.env.JARVIS_TEST_ROOT, edits);
    const engineFile = path.join(kit.folder, "backend/ChainedEngine.js");
    const source = fs.readFileSync(engineFile, "utf8");
    const needle = 'const SPEECH = Object.freeze({ scripted: require(' + JSON.stringify(require.resolve("./fixtures/jarvis/engine.js")) + ').row });';
    assert.equal(source.split(needle).length - 1, 1);
    fs.writeFileSync(engineFile, source.replace(needle, "const SPEECH = Object.freeze({ local: LocalSpeech.row });"));
    fs.copyFileSync(path.join(tree, "shell/plugins/vgs.jarvis/artifacts.json"), path.join(kit.folder, "artifacts.json"));
    delete require.cache[engineFile];
    kit.Engine = require(engineFile);
    const root = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "daemon-speech-"));
    const local = path.join(root, "local"), state = path.join(root, "state");
    fs.mkdirSync(path.join(local, "venv/bin"), { recursive: true });
    fs.mkdirSync(state);
    fs.copyFileSync(path.join(__dirname, "fixtures/jarvis-local-speech/standin.py"), path.join(local, "venv/bin/python"));
    fs.chmodSync(path.join(local, "venv/bin/python"), 0o700);
    const scripts = { start: scenario, utterances: Array.from({ length: 6 }, () => ({ final: "Fixture request." })) };
    fs.writeFileSync(path.join(local, "scenario.json"), JSON.stringify(scripts));
    if (scenario === "held")
        assert.equal(cp.spawnSync("python3", ["-I", "-c", "import os,sys;os.mkfifo(sys.argv[1])", path.join(local, "ready-gate")]).status, 0);
    fs.writeFileSync(path.join(state, "local-ready.json"), JSON.stringify({ tier: "small", data: fs.realpathSync(local) }));
    const logs = () => fs.existsSync(path.join(local, "log.jsonl")) ? fs.readFileSync(path.join(local, "log.jsonl"), "utf8")
        .trim().split("\n").filter(Boolean).map(JSON.parse) : [];
    const starts = () => logs().filter(row => row.start).map(row => row.start);
    const alive = pid => { try { process.kill(pid, 0); return true; } catch (error) { if (error.code === "ESRCH") return false; throw error; } };
    const w = rig(kit, server, { directories: { state, data: root, runtime: root } });
    try {
        assert.equal(w.s().gate.kind, "up");
        await until(() => starts().length === 1, "sidecar starts before any conversation");
        if (scenario === "held") {
            w.runner.dispatch({ type: "snapshot", locked: null, engine: "chained", configured: true, settings: w.s().settings });
            w.runner.dispatch({ type: "talk-down" });
            assert.equal(w.s().gate.reason, "lock-unknown");
            assert.equal(w.s().capture.kind, "closed");
            assert.equal(w.s().conversation.kind, "ended");
            w.runner.dispatch({ type: "snapshot", locked: false, engine: "chained", configured: true, settings: w.s().settings });
            w.runner.dispatch({ type: "talk-down" });
            await until(() => w.s().capture.kind === "open", "bounded loading capture opens");
            w.runner.dispatch({ type: "talk-up" });
            await until(() => w.s().capture.kind === "closed", "bounded loading capture releases");
            assert.equal(w.s().turn.kind, "collecting");
            const before = server.requests.length;
            w.advanceRunner(60000);
            await until(() => w.s().fault.kind === "error", "existing loading deadline is visible");
            assert.equal(w.s().fault.reason, "speech=collect-timeout");
            assert.equal(w.s().conversation.kind, "ended");
            assert.equal(w.s().capture.kind, "closed");
            await until(() => !alive(starts()[0].pid), "deadline reaps the failed starting child");
            assert.equal(w.configure(w.s().settings).kind, "ready", "deadline does not become a setup refusal");
            assert.equal(starts().length, 1, "deadline does not automatically restart");
            assert.equal(server.requests.length, before, "deadline does not replay an utterance");
            return;
        }
        if (["not-ready", "memory-refused", "memory-unavailable"].includes(scenario)) {
            const expected = { "not-ready": "speech=local-runtime-not-ready",
                "memory-refused": "speech=local-memory-insufficient", "memory-unavailable": "speech=local-memory-unavailable" }[scenario];
            await until(() => !alive(starts()[0].pid), "admission refusal closes child");
            assert.equal(w.configure(w.s().settings).cause, expected);
            assert.equal(starts().length, 1);
            fs.writeFileSync(path.join(local, "scenario.json"), JSON.stringify({ ...scripts, start: "ready" }));
            assert.equal(w.configure(w.s().settings).cause, expected);
            assert.equal(w.s().gate.kind, "down");
            assert.equal(starts().length, 1, "ordinary hello does not retry an unpublished runtime");
            // setup-local publishes with rename after its inference probe.
            // Republish identical marker bytes: the publication is new.
            const marker = path.join(state, "local-ready.json"), replacement = path.join(state, ".local-ready-repaired");
            fs.copyFileSync(marker, replacement);
            fs.renameSync(replacement, marker);
            assert.equal(w.configure(w.s().settings).cause, "speech=local-loading");
            await until(() => w.configure(w.s().settings).kind === "ready", "completed setup publication restores model readiness");
            assert.equal(w.configure(w.s().settings).kind, "ready");
            assert.equal(starts().length, 2);
            return;
        }
        await until(() => w.configure(w.s().settings).kind === "ready", "model ready ends the loading cause");
        const pid = starts()[0].pid;
        for (const ending of [firstEnding, "brain-failed", "stop"]) {
            const before = await say(w, utterance("Fixture request."));
            const body = await requested(w, before + 1, "first request in conversation");
            assert.deepEqual(user(body), ["Fixture request."]);
            assert.equal(starts().length, 1, "conversation starts no new sidecar");
            if (ending === "brain-failed")
                w.runner.dispatch({ type: "brain-failed", gen: w.s().gen, op: w.s().turn.op, reason: "brain=fixture-failed" });
            else w.runner.dispatch({ type: "stop" });
            await until(() => w.s().conversation.kind === "ended", "conversation ends");
            await until(() => w.s().brain.kind === "closed" && w.s().capture.kind === "closed", "conversation children acknowledge closure");
            assert.equal(alive(pid), true, "conversation end retains healthy sidecar");
            assert.equal(starts().length, 1);
        }
        // A faulted child is reaped. Recovery loads on the next permitted
        // request; a healthy conversation fault above never paid that load.
        process.kill(pid, "SIGKILL");
        await until(() => !alive(pid), "daemon reaps faulted child");
        assert.equal(w.configure(w.s().settings).kind, "ready");
        assert.equal(starts().length, 1, "hello does not restart a failed child");
        const before = await say(w, utterance("Fixture request."));
        await requested(w, before + 1, "request after sidecar fault");
        assert.equal(starts().length, 2);
        assert.notEqual(starts()[1].pid, pid);
        w.runner.dispatch({ type: "stop" });
    } finally {
        await w.close();
        await until(() => starts().every(row => !alive(row.pid)), "daemon teardown releases speech child");
        server.closeAll();
    }
}

// Run the shipped daemon, Session, Audio and local adapter. Only Accounts'
// separately tested selection boundary is replaced by the loopback account.
// The FIFO holds the child before its real ready frame and input read loop.
async function loadingTalk(server, ending = "ready", edits = []) {
    server.replies.length = 0;
    const kit = Fixture.copy(process.env.JARVIS_TEST_ROOT);
    const engineFile = path.join(kit.folder, "backend/ChainedEngine.js");
    const speechNeedle = 'const SPEECH = Object.freeze({ scripted: require(' + JSON.stringify(require.resolve("./fixtures/jarvis/engine.js")) + ').row });';
    let source = fs.readFileSync(engineFile, "utf8");
    assert.equal(source.split(speechNeedle).length, 2);
    fs.writeFileSync(engineFile, source.replace(speechNeedle, "const SPEECH = Object.freeze({ local: LocalSpeech.row });"));
    fs.copyFileSync(path.join(tree, "shell/plugins/vgs.jarvis/artifacts.json"), path.join(kit.folder, "artifacts.json"));
    for (const [file, needle, replacement] of edits) {
        const name = path.join(kit.folder, file), original = fs.readFileSync(name, "utf8");
        assert.equal(original.split(needle).length, 2, "one loading control match");
        fs.writeFileSync(name, original.replace(needle, replacement));
    }
    const root = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "loading-"));
    const local = path.join(root, "local"), state = path.join(root, "state");
    fs.mkdirSync(path.join(local, "venv/bin"), { recursive: true });
    fs.mkdirSync(state);
    fs.copyFileSync(path.join(__dirname, "fixtures/jarvis-local-speech/standin.py"), path.join(local, "venv/bin/python"));
    fs.chmodSync(path.join(local, "venv/bin/python"), 0o700);
    fs.writeFileSync(path.join(local, "scenario.json"), JSON.stringify({ start: "held", utterances: [{ final: "Captured once." }] }));
    assert.equal(cp.spawnSync("python3", ["-I", "-c", "import os,sys;os.mkfifo(sys.argv[1])", path.join(local, "ready-gate")]).status, 0);
    if (ending !== "missing") fs.writeFileSync(path.join(state, "local-ready.json"), JSON.stringify({ tier: "small", data: fs.realpathSync(local) }));
    if (ending === "muted") fs.writeFileSync(path.join(state, "mute.json"), JSON.stringify({ muted: true }));
    if (ending === "device") fs.writeFileSync(path.join(process.env.HOME, "no-devices"), "");
    const preload = path.join(root, "accounts.js");
    fs.writeFileSync(preload, 'require(' + JSON.stringify(path.join(kit.folder, "backend/Core.js")) + ').use(' + JSON.stringify(tree) + ');\n' +
        'require(' + JSON.stringify(path.join(kit.folder, "backend/Accounts.js")) + ').Accounts.prototype.choose = id => ({ kind: "accepted", account: { id, provider: "ollama", label: "local", source: { kind: "local", origin: "http://127.0.0.1:11434" }, model: "fixture-model" } });');
    const child = cp.spawn("node", ["--require", preload, path.join(kit.folder, "backend/jarvisd.js"), "--tree", tree], {
        env: { PATH: process.env.PATH, HOME: process.env.HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR }, stdio: ["pipe", "pipe", "pipe"] });
    const closed = once(child, "close");
    const rows = [], logs = () => fs.existsSync(path.join(local, "log.jsonl"))
        ? fs.readFileSync(path.join(local, "log.jsonl"), "utf8").trim().split("\n").filter(Boolean).map(JSON.parse) : [];
    const starts = () => logs().filter(row => row.start);
    const states = () => rows.filter(row => row.type === "state");
    const s = () => states().at(-1)?.state;
    const status = () => rows.filter(row => row.type === "status").at(-1);
    let tail = "", error = "";
    child.stdout.on("data", data => { tail += data; const lines = tail.split("\n"); tail = lines.pop(); rows.push(...lines.filter(Boolean).map(JSON.parse)); });
    child.stderr.on("data", data => { error += data; });
    child.stdin.on("error", e => { if (e.code !== "EPIPE") throw e; });
    const send = fields => child.stdin.write(JSON.stringify({ v: 1, gen: s()?.gen ?? 0, revision: "a".repeat(64), ...fields }) + "\n");
    const hello = (locked = false) => send({ type: "hello", locked,
        settings: { sounds: false, mode: "hold", microphone: "", speaker: "", brain: ending === "brain" ? "" : "fixture-account", taskTerminal: "auto", voiceProvider: "local", voiceAccount: "", cloudVision: "ask", privateWindows: "bitwarden" },
        keys: { talk: null, mute: null, stop: null, confirm: null, console: null }, directories: { state, data: root, runtime: process.env.XDG_RUNTIME_DIR } });
    const intent = name => send({ type: "intent", intent: name });
    const before = server.requests.length;
    try {
        hello(ending === "locked");
        await until(() => status() && s(), "shipped daemon publishes admission: " + error);
        if (["missing", "brain", "locked", "muted"].includes(ending)) {
            if (ending === "muted") assert.equal(s().mute.kind, "on");
            else assert.equal(s().gate.kind, "down");
            send({ type: "indicator", shown: true });
            intent("talk-down");
            // The hello is an ordered wire barrier after the refused intent.
            const count = rows.filter(row => row.type === "status").length;
            hello(ending === "locked");
            await until(() => rows.filter(row => row.type === "status").length > count, "refused Talk settles");
            assert.equal(s().capture.kind, "closed");
            assert.equal(s().conversation.kind, "ended");
            assert.equal(server.requests.length, before);
            if (["missing", "brain"].includes(ending)) assert.equal(starts().length, 0);
            return;
        }
        assert.equal(s().gate.kind, "up", "healthy loading admits Talk");
        assert.deepEqual(status().causes, ["speech=local-loading"]);
        await until(() => starts().length === 1, "one daemon-owned child starts");
        intent("talk-down");
        await until(() => s().conversation.kind === "active", "Talk starts one conversation");
        send({ type: "indicator", shown: false });
        await until(() => s().indicator.kind === "gone" && s().input.kind === "held", "unmapped indicator settles");
        assert.equal(s().capture.kind, "closed", "capture waits for the presented indicator");
        send({ type: "indicator", shown: true });
        if (ending === "device") {
            await until(() => s().fault.kind !== "none" && s().capture.kind === "closed",
                "loading capture refuses a missing device and settles its capture");
            assert.equal(s().fault.reason, "device-lost");
            assert.equal(s().capture.kind, "closed");
            assert.equal(server.requests.length, before);
            return;
        }
        await until(() => s().capture.kind === "open", "real Audio captures before model ready");
        assert.equal(logs().some(row => row.ready), false);
        const identity = { gen: s().gen, op: s().turn.op };
        assert.equal(s().turn.kind, "collecting");
        assert.deepEqual(status().causes, ["speech=local-loading"]);
        // At least one PCM period reaches the existing sink before release.
        await until(() => fs.existsSync(path.join(process.env.HOME, "audio-argv")) &&
            fs.readFileSync(path.join(process.env.HOME, "audio-argv"), "utf8").includes('"command": "pw-record"'), "fixture recorder starts");
        intent("talk-up");
        await until(() => s().capture.kind === "closed", "release closes the same capture before ready");
        assert.equal(s().input.kind, "released");
        assert.equal(s().turn.kind, "collecting");
        assert.deepEqual({ gen: s().gen, op: s().turn.op }, identity);
        assert.equal(server.requests.length, before, "no transcription or brain turn before real ready");
        if (ending === "fault") {
            process.kill(starts()[0].start.pid, "SIGKILL");
            await until(() => s().fault.kind === "error", "own-child fault is visible during loading");
            assert.match(s().fault.reason, /^speech=local-exit/);
            assert.equal(s().capture.kind, "closed");
            hello();
            await until(() => status().causes.length === 0, "own-child fault is unloaded, not setup refusal");
            assert.equal(starts().length, 1, "hello does not automatically retry the child");
            assert.equal(server.requests.length, before);
            intent("talk-down");
            await until(() => starts().length === 2 && s().capture.kind === "open", "next permitted request reloads the reaped loading child");
            assert.deepEqual(status().causes, ["speech=local-loading"], "replacement loading is published by its daemon owner");
            assert.equal(s().fault.kind, "none");
            assert.equal(s().turn.kind, "collecting");
            assert.equal(server.requests.length, before, "faulted utterance is not replayed during recovery");
            return;
        }
        if (ending === "lease") {
            child.stdin.end();
            const [code, signal] = await closed;
            assert.equal(code, 0, error);
            assert.equal(signal, null);
            assert.equal(server.requests.length, before, "lease ends without replaying the held utterance");
            return;
        }
        if (ending === "stop") intent("stop");
        else if (ending === "mute") intent("mute");
        else if (ending === "lock") hello(true);
        if (ending !== "ready") await until(() => s().conversation.kind === "ended", "loading cancellation ends its utterance");
        fs.writeFileSync(path.join(local, "ready-gate"), "R");
        await until(() => status().causes.length === 0, "actual ready clears loading status");
        if (ending === "ready") {
            const body = await requested({ server }, before + 1, "one held utterance reaches the real wire brain");
            assert.deepEqual(user(body), ["Captured once."]);
            const readyIndex = rows.findIndex(row => row.type === "status" && row.causes.length === 0);
            const readyState = rows.slice(readyIndex + 1).find(row => row.type === "state").state;
            assert.equal(readyState.turn.kind, "collecting");
            assert.deepEqual({ gen: readyState.gen, op: readyState.turn.op }, identity, "ready snapshot preserves collecting identity before final starts its brain operation");
            assert.equal(server.requests.length, before + 1);
            const ends = logs().filter(row => row.end);
            assert.equal(ends.length, 1);
            assert.ok(ends[0].samples > 0, "queued utterance contains actual fixture PCM");
        } else {
            await until(() => logs().some(row => row.abort), "cancelled loading utterance abort reaches the same child");
            assert.equal(s().conversation.kind, "ended");
            assert.equal(s().turn.kind, "none");
            assert.equal(server.requests.length, before, "ready does not replay cancelled Talk");
        }
        assert.equal(starts().length, 1, "loading Talk starts no second child");
    } finally {
        child.stdin.end();
        const timer = setTimeout(() => child.kill("SIGKILL"), OBSERVE_MS);
        try { const [code, signal] = await closed; assert.equal(signal, null); assert.equal(code, 0, error); }
        finally { clearTimeout(timer); server.closeAll(); fs.rmSync(path.join(process.env.HOME, "no-devices"), { force: true }); }
    }
}

// Always mode through the shipped daemon, Session, Audio and local adapter
// with the stand-in sidecar: the wake capture reaches only the sidecar and
// no brain, the word opens one utterance, the reply plays, and the next
// wake capture follows in the same conversation. "refused" selects GPT-Live
// and "unset" has no local setup: neither opens any capture.
async function alwaysTalk(server, ending = "ready", edits = []) {
    server.replies.length = 0;
    const kit = Fixture.copy(process.env.JARVIS_TEST_ROOT);
    const engineFile = path.join(kit.folder, "backend/ChainedEngine.js");
    const speechNeedle = 'const SPEECH = Object.freeze({ scripted: require(' + JSON.stringify(require.resolve("./fixtures/jarvis/engine.js")) + ').row });';
    const source = fs.readFileSync(engineFile, "utf8");
    assert.equal(source.split(speechNeedle).length, 2);
    fs.writeFileSync(engineFile, source.replace(speechNeedle, "const SPEECH = Object.freeze({ local: LocalSpeech.row });"));
    fs.copyFileSync(path.join(tree, "shell/plugins/vgs.jarvis/artifacts.json"), path.join(kit.folder, "artifacts.json"));
    for (const [file, needle, replacement] of edits) {
        const name = path.join(kit.folder, file), original = fs.readFileSync(name, "utf8");
        assert.equal(original.split(needle).length, 2, "one always control match");
        fs.writeFileSync(name, original.replace(needle, replacement));
    }
    const root = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "always-"));
    const local = path.join(root, "local"), state = path.join(root, "state");
    fs.mkdirSync(path.join(local, "venv/bin"), { recursive: true });
    fs.mkdirSync(state);
    fs.copyFileSync(path.join(__dirname, "fixtures/jarvis-local-speech/standin.py"), path.join(local, "venv/bin/python"));
    fs.chmodSync(path.join(local, "venv/bin/python"), 0o700);
    fs.writeFileSync(path.join(local, "scenario.json"), JSON.stringify({ start: "ready", wakes: [{ afterFrames: 2 }],
        utterances: [{ earlyFinal: "Woken request." }], speech: [{ rate: 16000, samples: 4800 }] }));
    if (ending !== "unset") fs.writeFileSync(path.join(state, "local-ready.json"), JSON.stringify({ tier: "small", data: fs.realpathSync(local) }));
    const preload = path.join(root, "accounts.js");
    fs.writeFileSync(preload, 'require(' + JSON.stringify(path.join(kit.folder, "backend/Core.js")) + ').use(' + JSON.stringify(tree) + ');\n' +
        'require(' + JSON.stringify(path.join(kit.folder, "backend/Accounts.js")) + ').Accounts.prototype.choose = id => ({ kind: "accepted", account: { id, provider: "ollama", label: "local", source: { kind: "local", origin: "http://127.0.0.1:11434" }, model: "fixture-model" } });');
    const child = cp.spawn("node", ["--require", preload, path.join(kit.folder, "backend/jarvisd.js"), "--tree", tree], {
        env: { PATH: process.env.PATH, HOME: process.env.HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR }, stdio: ["pipe", "pipe", "pipe"] });
    const closed = once(child, "close");
    const rows = [], logs = () => fs.existsSync(path.join(local, "log.jsonl"))
        ? fs.readFileSync(path.join(local, "log.jsonl"), "utf8").trim().split("\n").filter(Boolean).map(JSON.parse) : [];
    const states = () => rows.filter(row => row.type === "state");
    const s = () => states().at(-1)?.state;
    const status = () => rows.filter(row => row.type === "status").at(-1);
    let tail = "", error = "";
    child.stdout.on("data", data => { tail += data; const lines = tail.split("\n"); tail = lines.pop(); rows.push(...lines.filter(Boolean).map(JSON.parse)); });
    child.stderr.on("data", data => { error += data; });
    child.stdin.on("error", e => { if (e.code !== "EPIPE") throw e; });
    const send = fields => child.stdin.write(JSON.stringify({ v: 1, gen: s()?.gen ?? 0, revision: "a".repeat(64), ...fields }) + "\n");
    const hello = () => send({ type: "hello", locked: false,
        settings: { sounds: false, mode: "always", microphone: "", speaker: "", brain: "fixture-account", taskTerminal: "auto",
            voiceProvider: ending === "refused" ? "gpt-live" : "local", voiceAccount: "", cloudVision: "ask", privateWindows: "bitwarden" },
        keys: { talk: null, mute: null, stop: null, confirm: null, console: null }, directories: { state, data: root, runtime: process.env.XDG_RUNTIME_DIR } });
    hello();
    const before = server.requests.length;
    try {
        await until(() => status() && s(), "shipped daemon publishes admission: " + error);
        if (ending !== "ready") {
            assert.deepEqual(status().causes, [ending === "refused" ? "speech=always-local-voice" : "speech=local-not-set-up"]);
            assert.equal(s().gate.kind, "down");
            send({ type: "indicator", shown: true });
            send({ type: "intent", intent: "talk-down" });
            // The hello is an ordered wire barrier after the refused intent.
            const count = rows.filter(row => row.type === "status").length;
            hello();
            await until(() => rows.filter(row => row.type === "status").length > count, "refused Always settles");
            assert.deepEqual([s().indicator.kind, s().input.kind, s().capture.kind, s().conversation.kind], ["shown", "released", "closed", "ended"]);
            assert.equal(logs().length, 0, "no sidecar starts for a refused Always mode");
            assert.equal(server.requests.length, before);
            return;
        }
        assert.deepEqual(status().causes.filter(cause => cause !== "speech=local-loading"), []);
        assert.equal(s().input.kind, "armed");
        assert.equal(s().capture.kind, "closed", "the wake capture waits for its indicator");
        send({ type: "indicator", shown: true });
        await until(() => s().capture.kind === "open" && s().capture.mode === "armed", "the wake capture opens");
        const armedGen = s().gen;
        assert.equal(s().conversation.kind, "ended");
        await until(() => s().conversation.kind === "active", "the word starts a conversation: " + JSON.stringify(logs().slice(-3)));
        const log = logs();
        const wake = log.findIndex(row => row.wake !== undefined), woke = log.findIndex(row => row.woke !== undefined);
        assert.ok(wake !== -1 && woke > wake, "the stand-in spotted the word");
        assert.equal(log.slice(0, woke).some(row => row.listen !== undefined), false, "no utterance before the word");
        assert.equal(server.requests.length, before, "the wake capture reaches no brain");
        assert.equal(s().gen, armedGen + 1);
        server.replies.push(Fixture.text("Done."));
        const body = await requested({ server }, before + 1, "the woken utterance reaches the brain");
        assert.deepEqual(user(body), ["Woken request."]);
        const listen = logs().find(row => row.listen !== undefined);
        assert.equal(listen.detect, true, "the woken utterance ends by turn detection");
        await until(() => logs().some(row => row.speak !== undefined), "the reply is spoken");
        await until(() => logs().filter(row => row.wake !== undefined).length === 2 && s().capture.kind === "open"
            && s().capture.mode === "armed", "the next wake capture follows the reply");
        assert.deepEqual([s().conversation.kind, s().gen], ["active", armedGen + 1], "the conversation stays open for the next word");
        assert.equal(server.requests.length, before + 1);
        assert.equal(logs().filter(row => row.start).length, 1, "one daemon-owned sidecar serves wake and speech");
        send({ type: "intent", intent: "mute" });
        await until(() => s().mute.kind === "on" && s().capture.kind === "closed", "mute ends the wake capture");
        await until(() => logs().filter(row => row.abort !== undefined).length >= 1, "the ended wake capture is aborted");
        assert.equal(s().input.kind, "released");
    } finally {
        child.stdin.end();
        const timer = setTimeout(() => child.kill("SIGKILL"), OBSERVE_MS);
        try { const [code, signal] = await closed; assert.equal(signal, null); assert.equal(code, 0, error); }
        finally { clearTimeout(timer); server.closeAll(); fs.rmSync(path.join(state, "mute.json"), { force: true }); }
    }
}

async function cases(kit, server, only = null) {
    const Protocol = load(path.join(kit.folder, "JarvisProtocol.js"));
    const run = async (name, check, options) => {
        if (only !== null && only !== name) return;
        Fixture.reset(options?.fixture);
        server.replies.length = 0;
        const w = rig(kit, server, options);
        try { await check(w); } finally {
            await w.close();
            server.closeAll();
        }
    };

    await run("feedback-start", async w => {
        w.runner.dispatch({ type: "talk-down" });
        const owner = w.s().playback;
        assert.equal(owner.kind, "feedback");
        await until(() => w.writes.length !== 0, "the start sound reaches the stand-in player");
        assert.equal(w.s().capture.kind, "closed", "no microphone overlaps the start sound");
        assert.equal(control.frames, 0);
        assert.equal(w.writes.some(write => write.pcm.some(byte => byte !== 0)), true, "the start sound is audible PCM");
        w.runner.dispatch({ type: "talk-up" });
        await playOut(w);
        assert.equal(w.s().capture.kind, "closed", "an early release opens no microphone");
        assert.equal(w.audio.lastPlayback.writtenFrames, 1920, "the whole start sound is played");
        assert.equal(w.audio.lastPlayback.heardText, "", "a local sound is not assistant words");
        assert.deepEqual(w.captions, []);
        assert.deepEqual(control.spoken, [], "no cue text reaches the speech provider");
        w.runner.dispatch({ type: "played", gen: owner.gen, op: owner.op });
        assert.equal(w.s().capture.kind, "closed", "a repeated completion cannot open capture");
    }, { sounds: true });

    for (const trigger of ["mute", "stop", "lock", "settings"]) {
        await run("feedback-stop-" + trigger, async w => {
            w.runner.dispatch({ type: "talk-down" });
            const owner = w.s().playback;
            await until(() => w.writes.length !== 0, "the start cue begins");
            if (trigger === "lock") w.runner.dispatch({ type: "snapshot", configured: true, locked: true,
                engine: "chained", settings: w.s().settings });
            else if (trigger === "settings") w.configure({ ...w.s().settings, brain: "changed" });
            else w.runner.dispatch({ type: trigger });
            await until(() => w.s().playback.kind === "idle", "cue teardown is acknowledged");
            w.advanceRunner(1200);
            w.runner.dispatch({ type: "played", gen: owner.gen, op: owner.op });
            assert.equal(w.s().capture.kind, "closed");
            assert.equal(w.audio.capture, null);
            assert.equal(control.frames, 0);
            assert.deepEqual(control.spoken, []);
            assert.deepEqual(w.faults, []);
        }, { sounds: true });
    }

    await run("feedback-working", async w => {
        const first = await say(w, utterance("Are you there?"));
        await requested(w, first + 1, "the request starts after the user finishes");
        const startWrites = w.writes.length;
        w.advanceRunner(1199);
        assert.equal(w.s().playback.kind, "idle", "working feedback waits for its interval");
        w.advanceRunner(1);
        assert.equal(w.s().playback.kind, "feedback");
        assert.equal(w.s().playback.cue, "working");
        await until(() => w.writes.length > startWrites, "working PCM reaches the stand-in player");
        assert.equal(w.writes.slice(startWrites).some(write => write.pcm.some(byte => byte !== 0)), true);
        assert.deepEqual(control.spoken, [], "working feedback stays local");
        w.advanceRunner(1200);
        await advance(w, 6);
        assert.equal(w.audio.playback.received, 2880, "only one working cue enters the stream");
        server.replies.push(text("Yes I am here."));
        await until(() => w.s().turn.kind === "none", "the brain finishes independently of playback");
        await playOut(w);
        assert.equal(w.audio.lastPlayback.writtenFrames, 2880 + 4 * Fixture.WORD_FRAMES);
        assert.equal(w.audio.lastPlayback.heardText, "Yes I am", "only aligned assistant words enter heard accounting");
        assert.deepEqual(control.spoken, ["Yes I am here."]);
        assert.deepEqual(w.faults, []);
        if (only === null) {
            const request = server.requests[first];
            const responseWrite = w.writes.find(write => write.at >= request.firstByteAt && write.pcm.every(byte => byte === 0x11));
            assert.ok(responseWrite, "the provider byte is followed by a real player write");
            assert.equal(control.inputEnds.length, 1, "the utterance's capture input iterator ended");
            assert.ok(control.inputEnds[0] <= control.finalTimes[0] && control.finalTimes[0] <= request.receivedAt,
                "input end, final transcript, and request belong to this utterance in order");
            console.log("diagnostic=jarvis-overhead capture-input-end-to-loopback-request-ms=" +
                (request.receivedAt - control.inputEnds[0]).toFixed(3) + " final-transcript-to-loopback-request-ms=" +
                (request.receivedAt - control.finalTimes[0]).toFixed(3) + " provider-byte-emitted-to-player-pipe-write-ms=" +
                (responseWrite.at - request.firstByteAt).toFixed(3));
        }
    }, { sounds: true });

    for (const [kind, reply] of [["text", held => text("Words without a full sentence", { wait: held.wait })],
        ["tool", () => calls({ id: "focus", name: "windows_focus", arguments: { window: "0x1f" } })]]) {
        await run("feedback-suppressed-" + kind, async w => {
            const first = await say(w, utterance("Hello."));
            await requested(w, first + 1, "the request reaches the server");
            const held = gate();
            // The injected clock advances only after the real stream adapter
            // has consumed the substantive text or tool event.
            server.replies.push(reply(held));
            await until(() => ![...w.timers.values()].some(timer => timer.at === 1200),
                "substantive provider output retires the feedback timer");
            w.advanceRunner(1200);
            assert.notEqual(w.s().playback.kind, "feedback", "substantive " + kind + " suppresses the working cue");
            held.open();
            w.runner.dispatch({ type: "stop" });
        }, { sounds: true, holdTools: kind === "tool" });
    }

    await run("feedback-disable-working", async w => {
        const first = await say(w, utterance("Hello."));
        await requested(w, first + 1, "the request starts");
        w.advanceRunner(1200);
        await until(() => w.s().playback.kind === "feedback" && w.audio.playback?.kind === "feeding", "the working cue starts");
        w.configure({ ...w.s().settings, sounds: false });
        await until(() => w.s().playback.kind === "idle", "disabling feedback flushes the working cue");
        server.replies.push(text("Hello there."));
        await until(() => w.s().turn.kind === "none", "the live reply still completes");
        await playOut(w);
        assert.deepEqual(control.spoken, ["Hello there."]);
        assert.equal(w.audio.lastPlayback.heardText, "Hello");
        assert.deepEqual(w.faults, []);
        assert.equal(w.s().fault.kind, "none");
    }, { sounds: true });

    await run("feedback-delayed-flush", async w => {
        const first = await say(w, utterance("Hello."));
        await requested(w, first + 1, "the request starts");
        w.advanceRunner(1200);
        await until(() => w.audio.playback?.received === 2880, "the working cue enters Audio");
        const flush = w.runner.ports.playback.flush;
        let acknowledge = null;
        w.runner.ports.playback.flush = (e, done) => flush(e, report => { acknowledge = () => done(report); });
        w.configure({ ...w.s().settings, sounds: false });
        await until(() => acknowledge !== null, "Audio closes the old player before its held acknowledgment");
        assert.equal(w.audio.playback, null);
        const writes = w.writes.length;
        server.replies.push(text("Hello there."));
        await until(() => w.s().turn.kind === "none", "the brain finishes before flush acknowledgment");
        assert.deepEqual(control.spoken, ["Hello there."]);
        assert.equal(w.writes.length, writes, "reply PCM waits for the old flush");
        assert.equal(w.s().playback.kind, "flushing");
        acknowledge();
        await playOut(w);
        assert.ok(w.writes.slice(writes).some(write => write.pcm.includes(0x11)), "reply PCM reaches the new player");
        assert.equal(w.audio.lastPlayback.heardText, "Hello");
        assert.deepEqual(w.faults, []);
        await say(w, utterance("Another turn."));
        const body = await requested(w, first + 2, "the next request follows the completed delayed reply");
        assert.equal(user(body).at(-1), "Another turn.", "a cue flush adds no interrupted speech context");
        server.replies.push(text(""));
        await until(() => w.s().turn.kind === "none", "the next request completes");
    }, { sounds: true });

    for (const purpose of ["action", "release"]) await run("feedback-voice-" + purpose, async w => {
        const first = await say(w, utterance("Do the fixture."));
        await requested(w, first + 1, "the quiet request starts");
        w.advanceRunner(1200);
        await until(() => w.audio.playback?.received === 2880, "working feedback enters Audio");
        const oldSource = w.audio.playbackFeed;
        server.replies.push(calls(purpose === "action"
            ? { id: "call_action", name: "shell_argv", arguments: { argv: ["true"], cwd: w.workspace, network: false } }
            : { id: "call_release", name: "clipboard_read", arguments: {} }));
        await until(() => w.s().approval.kind === "held", "approval follows the working cue");
        const h = w.s().approval;
        assert.equal(h.purpose, purpose);
        assert.equal(h.physical, false);
        w.runner.dispatch({ type: "shown", gen: h.gen, op: h.op, id: h.id });
        await until(() => w.s().playback.kind === "idle", "the approval releases cue playback");
        assert.equal(w.audio.playback, null, "Audio released the old player");
        assert.equal(oldSource.destroyed, true, "the cue-only speech stream is released");
        w.advanceRunner(1100);
        control.utterances.push(utterance("Yes."));
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "Talk admits the voice answer after flush");
        assert.equal(w.s().turn.kind, "thinking");
        w.runner.dispatch({ type: "talk-up" });
        await requested(w, first + 2, "voice approval continues the same brain turn");
        const writes = w.writes.length;
        server.replies.push(text("Done."));
        await until(() => w.s().turn.kind === "none", "the approved reply completes");
        await playOut(w);
        assert.deepEqual(control.spoken, ["Done."]);
        assert.ok(w.writes.slice(writes).some(write => write.pcm.includes(0x11)), "later speech acquires a fresh player");
        assert.equal(w.s().approval.kind, "none");
        assert.deepEqual(w.faults, []);
        await say(w, utterance("Another turn."));
        const body = await requested(w, first + 3, "the next request follows the completed approved reply");
        assert.equal(user(body).at(-1), "Another turn.", "approval cue teardown adds no interrupted speech context");
        server.replies.push(text(""));
        await until(() => w.s().turn.kind === "none", "the next request completes");
    }, { sounds: true, actionApproval: purpose === "action", fixture: purpose === "release"
        ? { recipients: [{ kind: "network", provider: "scripted-voice", account: "fixture", origin: "http://192.0.2.1:9" }] }
        : undefined });

    await run("feedback-off", async w => {
        const first = await say(w, utterance("Hello."));
        await requested(w, first + 1, "a silent request reaches the brain");
        w.advanceRunner(1200);
        assert.deepEqual(w.writes, [], "sounds off starts no feedback playback");
        server.replies.push(text(""));
        await until(() => w.s().turn.kind === "none", "the silent reply finishes");
    });

    await run("feedback-interrupt-working", async w => {
        const first = await say(w, utterance("Hello."));
        await requested(w, first + 1, "the first request starts");
        w.advanceRunner(1200);
        await until(() => w.audio.playback?.received === 2880, "the working cue enters Audio");
        control.utterances.push(utterance("Enough."));
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "interruption flushes cue playback before capture");
        w.runner.dispatch({ type: "talk-up" });
        server.replies.push(text(""));
        const body = await requested(w, first + 2, "the interrupted cue's next request");
        assert.deepEqual(user(body), ["Hello.", INTERRUPTED + "\n\nEnough."], "no cue becomes assistant heard context");
        assert.deepEqual(control.spoken, []);
        assert.deepEqual(w.faults, []);
    }, { sounds: true });

    // Partials draw; the final alone reaches the brain. Brain text reaches
    // speech only through Speakable, and a played reply adds no context.
    await run("turn-loop", async w => {
        const first = await say(w, utterance("What time is it?", ["what", "what time"]));
        const body = await requested(w, first + 1, "the final transcript reaches the brain");
        assert.deepEqual(w.partials, ["what", "what time"], "partials reach Session in revision order");
        assert.deepEqual(user(body), ["What time is it?"]);
        assert.equal(body.messages[0].role, "system");
        assert.ok(Array.isArray(body.tools), "router offers reach the brain as a tool list");
        assert.ok(body.tools.some(tool => tool.function.name === "windows_focus"), "router offers reach the brain");
        server.replies.push(text("It is **noon**. ", "Anything else?"));
        await until(() => w.s().playback.kind === "playing", "speech starts playback");
        await playOut(w);
        assert.deepEqual(control.spoken, ["It is noon.", "Anything else?"], "only Speakable sentences reach speech");
        assert.equal(w.audio.lastPlayback.writtenFrames, (3 + 2) * Fixture.WORD_FRAMES, "every sentence's PCM played");
        const second = await say(w, utterance("Thanks."));
        server.replies.push(text(""));
        const next = await requested(w, second + 1, "the second turn");
        assert.deepEqual(next.messages.slice(1).map(message => [message.role, message.content]), [
            ["user", "What time is it?"], ["assistant", "It is **noon**. Anything else?"], ["user", "Thanks."]],
        "a fully played reply adds no heard context");
        await until(() => w.s().turn.kind === "none", "the empty reply completes");
        const gen = w.s().gen;
        assert.deepEqual(w.captions.filter(row => row[1] === "user").map(row => [row[2], row[4]]),
            [["final", "What time is it?"], ["final", "Thanks."]], "user finals replace the drafts and reach the shell");
        assert.ok(control.detections.length > 0 && control.detections.every(value => value === false), "hold does not detect a turn end");
        assert.deepEqual(assistantCaptions(w), [[gen, "assistant", "partial", 1, "It is noon."],
            [gen, "assistant", "partial", 2, "It is noon. Anything else?"], [gen, "assistant", "final", 3, "It is noon. Anything else?"]],
        "each released sentence grows the reply's caption, final at its end; an empty reply adds none");
        const releases = w.rows().filter(row => row.kind === "release");
        assert.ok(releases.length >= 5 && releases.every(row => row.decision === "send" && row.outcome === "pending"
            && row.effect === "external"), "each utterance, request and sentence is audited before transfer");
        assert.deepEqual([...control.labels], ["speech"], "frames and sentences reach the adapter as labelled items");
    });

    // Barge-in during speech, after the reply completed: the next request
    // carries exactly the heard prefix, read at the loopback server.
    await run("barge-in", async w => {
        const first = await say(w, utterance("What time is it?"));
        await requested(w, first + 1, "first request");
        server.replies.push(text("Hello there. ", "The time is noon."));
        await until(() => w.s().turn.kind === "none", "the reply completes before the interruption");
        await feeding(w, 2 * Fixture.WORD_FRAMES);
        await advance(w, 6);
        assert.equal(w.audio.playback.written, 1440 + 6 * 480, "the paced writer reached the planned count");
        control.utterances.push(utterance("Stop there."));
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "capture reopens after the flush");
        assert.equal(w.audio.lastPlayback.heardText, "Hello", "Audio's lower bound covers one word");
        w.runner.dispatch({ type: "talk-up" });
        server.replies.push(text("Stopped."));
        const body = await requested(w, first + 2, "the request after barge-in");
        assert.deepEqual(body.messages.slice(1).map(message => [message.role, message.content]), [
            ["user", "What time is it?"], ["assistant", "Hello there. The time is noon."],
            ["user", heardOnly("Hello") + "\n\nStop there."]], "the brain is told exactly the heard prefix");
        assert.deepEqual(control.spoken.slice(0, 2), ["Hello there.", "The time is noon."]);
        await until(() => w.s().turn.kind === "none" && w.s().playback.kind !== "idle", "the answer speaks");
        await playOut(w);
        const third = await say(w, utterance("Next."));
        server.replies.push(text(""));
        const later = await requested(w, third + 1, "the turn after");
        assert.equal(user(later).at(-1), "Next.", "the heard prefix is told once");
    });

    // Barge-in mid-stream: the cancelled turn stays unanswered and its
    // partial reply never enters history; the server sees the stream close.
    await run("barge-in-streaming", async w => {
        const first = await say(w, utterance("Tell me a story."));
        await requested(w, first + 1, "first request");
        const held = gate();
        server.replies.push(text("First part. ", { wait: held.wait }, "Second part."));
        await feeding(w, 2 * Fixture.WORD_FRAMES);
        await advance(w, 6);
        control.utterances.push(utterance("Enough."));
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "capture reopens after cancel and flush");
        await server.requests[first].closed;
        held.open();
        w.runner.dispatch({ type: "talk-up" });
        server.replies.push(text("Fine."));
        const body = await requested(w, first + 2, "the request after barge-in");
        assert.deepEqual(body.messages.slice(1).map(message => [message.role, message.content]), [
            ["user", "Tell me a story."], ["user", heardOnly("First") + "\n\nEnough."]]);
        assert.equal(w.s().brain.kind, "acquired", "the interrupted conversation keeps its brain");
    });

    // Cancel during thinking, before any audio: the heard text is empty.
    await run("cancel-thinking", async w => {
        const first = await say(w, utterance("Open the door."));
        await requested(w, first + 1, "first request");
        const held = gate();
        server.replies.push(pause(held));
        control.utterances.push(utterance("Never mind."));
        w.runner.dispatch({ type: "talk-down" });
        await server.requests[first].closed;
        await until(() => w.s().capture.kind === "open", "capture reopens after the cancel acknowledgement");
        assert.equal(w.audio.lastPlayback, null, "no audio played before the interruption");
        held.open();
        w.runner.dispatch({ type: "talk-up" });
        server.replies.push(text("Okay."));
        const body = await requested(w, first + 2, "the request after cancel");
        assert.deepEqual(user(body), ["Open the door.", INTERRUPTED + "\n\nNever mind."], "the brain is told it heard nothing");
    });

    // A tool call goes through the real router to a stand-in executor and
    // returns as one tool-results turn with the local class's restated rule.
    await run("tool-round", async w => {
        const first = await say(w, utterance("Focus the editor."));
        server.replies.push(calls({ id: "call_1", name: "windows_focus", arguments: { window: "0x1f" } }), text("Focused it."));
        const body = await requested(w, first + 2, "the tool-results request");
        await requested(w, first + 1, "first request");
        assert.deepEqual(w.executions.map(call => [call.id, call.args]), [["windows.focus", { window: "0x1f" }]]);
        const after = require(path.join(kit.folder, "backend/Guidance.js")).compose("chained", "local", "").afterToolResult;
        assert.deepEqual(body.messages.slice(-3).map(message => [message.role, message.content]), [
            ["assistant", null], ["tool", "focused 0x1f"], ["system", after]], "the local class restates its rule after results");
        await until(() => w.s().playback.kind === "playing", "the final reply speaks");
        await playOut(w);
        assert.deepEqual(control.spoken, ["Focused it."]);
        assert.deepEqual(assistantCaptions(w).map(row => row.slice(2)), [["partial", 1, "Focused it."], ["final", 2, "Focused it."]],
            "a tool round's reply is captioned once, at its end");
        assert.deepEqual(w.faults, []);
    });

    // A segment closes at the wire's bound; a failed reply closes its words.
    await run("caption-segments", async w => {
        const first = await say(w, utterance("What time is it?"));
        await requested(w, first + 1, "first request");
        server.replies.push(text("It is noon. ", "Anything else?"));
        await until(() => w.s().turn.kind === "none", "the reply completes");
        const second = await say(w, utterance("And tomorrow?"));
        await requested(w, second + 1, "second request");
        server.replies.push(text("Bye now. More").slice(0, 2));
        await until(() => w.s().fault.kind === "error", "the cut reply fails");
        assert.deepEqual(assistantCaptions(w).map(row => row.slice(2)), [
            ["partial", 1, "It is noon."], ["final", 2, "It is noon."], ["partial", 3, "Anything els"],
            ["final", 4, "Anything els"], ["partial", 5, "e?"], ["final", 6, "e?"],
            ["partial", 7, "Bye now."], ["final", 8, "Bye now."]], "segments split at the bound");
    }, { captionLimit: 12 });

    // An interrupted call that runs on is answered "running" and its real
    // outcome reaches the next user turn, never the turn it interrupted; a
    // call that never started is answered "not-started".
    await run("stale-outcome", async w => {
        const first = await say(w, utterance("Focus the editors."));
        server.replies.push(calls({ id: "call_1", name: "windows_focus", arguments: { window: "0x1f" } },
            { id: "call_2", name: "windows_focus", arguments: { window: "0x2b" } }));
        await until(() => w.held.length === 1, "the stand-in executor holds the first call");
        control.utterances.push(utterance("Wait."));
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "capture reopens while the tool runs");
        const later = gate();
        server.replies.push([...pause(later), ...text("Waiting.").slice(1)]);
        w.runner.dispatch({ type: "talk-up" });
        // A fault ends the conversation: no later request or reply comes.
        const faulted = () => w.s().fault.kind === "error";
        const body = await requested(w, first + 2, "the request after the interruption", faulted);
        assert.deepEqual(body.messages.slice(2).map(message => [message.role, message.content]), [
            ["assistant", null], ["tool", "{\"kind\":\"interrupted\",\"outcome\":\"running\"}"],
            ["tool", "{\"kind\":\"interrupted\",\"outcome\":\"not-started\"}"],
            ["user", INTERRUPTED + "\n\nWait."]], "a running call and an unstarted one get distinct answers");
        w.held[0]({ outcome: "completed", content: "focused late" });
        await turn();
        later.open();
        await settled(() => w.s().turn.kind === "none" && w.s().playback.kind !== "idle", faulted, "the second reply speaks");
        await playOut(w);
        assert.deepEqual(w.faults, []);
        assert.equal(w.s().fault.kind, "none", "the late outcome reached no live turn");
        assert.equal(w.executions.length, 1, "the unrouted call never started");
        const third = await say(w, utterance("Thanks."));
        server.replies.push(text(""));
        const last = await requested(w, third + 1, "the third request");
        assert.equal(user(last).at(-1), "[late result] Your interrupted call windows.focus ended completed: focused late\n\nThanks.",
            "the real outcome reaches the next user turn once");
        await settled(() => w.s().turn.kind === "none", faulted,
            "the third reply completes its turn before the fourth utterance");
        const fourth = await say(w, utterance("Bye."));
        server.replies.push(text(""));
        assert.equal(user(await requested(w, fourth + 1, "the fourth request")).at(-1), "Bye.");
    }, { holdTools: true });

    // A tool result's image reaches the brain beside its text, for a brain
    // whose row takes images; an engine with no ready brain takes none.
    await run("screen-image", async w => {
        assert.equal(w.engine.images(), true, "the ollama row takes images");
        const first = await say(w, utterance("What is on screen?"));
        server.replies.push(calls({ id: "call_1", name: "vision_screen", arguments: {} }), text("A terminal."));
        const body = await requested(w, first + 2, "the tool-results request");
        assert.deepEqual(body.messages.slice(-3, -1), [{ role: "tool", tool_call_id: "call_1", content: "screen text" },
            { role: "user", content: [{ type: "text", text: "Image from tool call call_1:" },
                { type: "image_url", image_url: { url: "data:image/png;base64," + PNG.toString("base64") } }] }]);
        await until(() => w.s().playback.kind === "playing", "the final reply speaks");
        await playOut(w);
        const idle = kit.Engine.create({ session: load(path.join(kit.folder, "Session.js")), state: () => w.s(), audit: null,
            router: null, accounts: () => null, policy: () => null, fault: () => {}, captionLimit: Protocol.TRANSCRIPT_CHARS });
        assert.equal(idle.images(), false, "no ready brain takes no image");
    });

    // History taints later turns: a screen read in one turn makes the next
    // turn's persistent call ask for approval.
    await run("history-taint", async w => {
        const first = await say(w, utterance("What is on screen?"));
        server.replies.push(calls({ id: "call_1", name: "vision_screen", arguments: {} }), text(""));
        await requested(w, first + 2, "the tool-results request");
        await until(() => w.s().turn.kind === "none", "the first turn completes");
        const second = await say(w, utterance("Close it."));
        server.replies.push(calls({ id: "call_2", name: "windows_close", arguments: { window: "0x2a" } }));
        await requested(w, second + 1, "the second request");
        await until(() => w.s().approval.kind === "held" || w.executions.length > 1, "the router judges the call");
        assert.equal(w.s().approval.kind, "held", "earlier screen content still taints the conversation");
        assert.deepEqual(w.executions.map(call => call.id), ["vision.screen"]);
    });

    // Toggle mode: capture reopens while thinking; that utterance is not the
    // next turn's, so the second turn binds its own capture.
    await run("toggle-turns", async w => {
        control.utterances.push(utterance("First turn.", [], null, { afterFrames: 3 }),
            utterance("unbound while thinking", [], null, { afterFrames: 1 }),
            utterance("Second turn.", [], null, { afterFrames: 3 }),
            utterance("never ends", [], null, { afterFrames: 100000 }));
        const before = server.requests.length;
        const thinkingCapture = gate();
        server.replies.push([...pause(thinkingCapture), ...text("One.").slice(1)], text("Two."));
        w.runner.dispatch({ type: "talk-down" });
        const body = await requested(w, before + 1, "the first toggle turn");
        assert.deepEqual(user(body), ["First turn."]);
        await until(() => control.utterances.length === 2, "capture reopens while the brain thinks");
        thinkingCapture.open();
        await until(() => w.s().playback.kind === "playing", "the first reply speaks");
        await playOut(w);
        // The final reaches a bound collection in the same tick, so a turn
        // still collecting after every final was delivered never sends it.
        const next = await requested(w, before + 2, "the second toggle turn",
            () => control.finals === 3 && w.s().turn.kind === "collecting");
        assert.equal(user(next).at(-1), "Second turn.");
        assert.ok(control.detections.length > 0 && control.detections.every(value => value === true),
            "toggle sends local turn-detection admission to each utterance");
    }, { mode: "toggle" });

    // A transcription that fails after its capture closed ends its turn.
    await run("transcribe-failure", async w => {
        control.utterances.push(utterance("lost", [], null, { failAfterClose: true }));
        const before = server.requests.length;
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "capture opens");
        w.runner.dispatch({ type: "talk-up" });
        // A failure the service heard is one the turn no longer can.
        await settled(() => w.s().turn.kind !== "collecting",
            () => w.faults.includes("speech-transcribe: speech=fixture-failed"), "the failure reaches the turn");
        assert.deepEqual({ ...w.s().fault }, { kind: "error", reason: "speech=fixture-failed", retry: 0 });
        assert.equal(server.requests.length, before);
    });

    // The thinking deadline bounds the brain, not speech: a reply that plays
    // longer than it leaves no timeout.
    await run("long-speech", async w => {
        const first = await say(w, utterance("Read a long list."));
        await requested(w, first + 1, "first request");
        server.replies.push(text("One. ", "Two. ", "Three."));
        // The last sentence is released only at the reply's end and reaches
        // speech a tick later; nothing advances the playback clock, so a turn
        // still open then waits on speech.
        await settled(() => w.s().turn.kind === "none", () => control.spoken.length === 3,
            "the brain finishes while speech still waits on playback");
        assert.equal(w.s().playback.kind, "playing");
        w.advanceRunner(120000);
        assert.equal(w.s().fault.kind, "none", "no thinking timeout fires during speech");
        await playOut(w);
    });

    // Conversation end closes brain, transport and speech adapters; the next
    // conversation starts with fresh history and a new recipient set.
    await run("conversation-end", async w => {
        const first = await say(w, utterance("Count to ten."));
        await requested(w, first + 1, "first request");
        const held = gate();
        server.replies.push(pause(held));
        w.runner.dispatch({ type: "stop" });
        await server.requests[first].closed;
        held.open();
        assert.equal(control.closed, 1, "the speech adapter is closed");
        const old = control.opened[0];
        await assert.rejects(old.net.request({ content: "x", labels: ["speech"] }, { url: "http://127.0.0.1:" + PORT + "/v1" }),
            { message: "jarvis: net=closed" }, "the conversation's transport is closed");
        await until(() => w.s().brain.kind === "closed", "Session closes the brain owner");
        const second = await say(w, utterance("Hello again."));
        server.replies.push(text(""));
        const body = await requested(w, second + 1, "the next conversation");
        assert.deepEqual(user(body), ["Hello again."], "a new conversation has fresh history");
        assert.notEqual(control.opened[1].recipients, old.recipients);
    });

    // A session-setting change ends the conversation and drops its context
    // and recipient set before a new one starts.
    await run("settings-change", async w => {
        const first = await say(w, utterance("Remember blue."));
        server.replies.push(text(""));
        await requested(w, first + 1, "first request");
        await until(() => w.s().turn.kind === "none", "the first turn completes");
        const old = control.opened[0];
        assert.deepEqual(w.configure({ mode: "hold", microphone: "", speaker: "", brain: "other-account" }), { kind: "ready" });
        await assert.rejects(old.net.request({ content: "x", labels: ["speech"] }, { url: "http://127.0.0.1:" + PORT + "/v1" }),
            { message: "jarvis: net=closed" }, "the old transport closes at the change");
        const second = await say(w, utterance("What did I say?"));
        server.replies.push(text(""));
        const body = await requested(w, second + 1, "the request after the change");
        assert.deepEqual(user(body), ["What did I say?"], "old context does not cross the change");
        assert.equal(control.opened[1].recipients.brain.account, "other-account");
    });

    // Release markers: a remote speech recipient makes the set non-offline,
    // so a clipboard result travels as its marker and the ask is audited.
    await run("release-markers", async w => {
        const first = await say(w, utterance("Read my clipboard."));
        server.replies.push(calls({ id: "call_1", name: "clipboard_read", arguments: {} }), text(""));
        await until(() => w.s().approval.kind === "held", "clipboard release is held before transfer");
        assert.equal(server.requests.length, first + 1, "the recipient has no tool result before the decision");
        assert.equal(w.s().approval.purpose, "release");
        w.runner.dispatch({type: "approval-cancel", gen: w.s().gen, id: w.s().approval.id});
        const body = await requested(w, first + 2, "the tool-results request");
        assert.equal(body.messages.find(message => message.role === "tool").content, "[withheld: clipboard content]");
        assert.equal(JSON.stringify(body).includes("clipboard words"), false);
        assert.ok(w.rows().some(row => row.kind === "release" && row.decision === "ask"), "the ask decision is audited");
    }, { fixture: { recipients: [{ kind: "network", provider: "scripted-voice", account: "fixture", origin: "http://192.0.2.1:9" }] } });

    await run("release-grants", async w => {
        const first = await say(w, utterance("Read my clipboard."));
        server.replies.push(calls({id: "call_1", name: "clipboard_read", arguments: {}}), text(""));
        await until(() => w.s().approval.kind === "held", "release question arrives");
        const h = w.s().approval;
        w.runner.dispatch({type: "shown", gen: h.gen, op: h.op, id: h.id});
        w.advanceRunner(1000);
        w.runner.dispatch({type: "confirm", gen: h.gen, id: h.id, digest: h.digest, source: "button"});
        const body = await requested(w, first + 2, "granted result reaches brain");
        assert.equal(body.messages.find(m => m.role === "tool").content, "clipboard words");
        await until(() => w.s().turn.kind === "none", "first turn completes");
        const second = await say(w, utterance("Read it again."));
        server.replies.push(calls({id: "call_2", name: "clipboard_read", arguments: {}}), text(""));
        await requested(w, second + 2, "same label reuses conversation grant");
        assert.equal(w.rows().filter(r => r.kind === "release" && r.decision === "ask").length, 1);
        await until(() => w.s().turn.kind === "none", "second turn completes");
        w.runner.dispatch({type: "stop"});
        const third = await say(w, utterance("Read it in a new conversation."));
        server.replies.push(calls({id: "call_3", name: "clipboard_read", arguments: {}}), text(""));
        await until(() => w.s().approval.kind === "held", "new conversation asks again");
        assert.equal(server.requests.length, third + 1);
        w.runner.dispatch({type: "confirm", gen: h.gen, id: h.id, digest: h.digest, source: "key"});
        assert.equal(w.s().approval.kind, "held", "stale grant answer is refused");
    }, {fixture: {recipients: [{kind: "network", provider: "scripted-voice", account: "fixture", origin: "http://192.0.2.1:9"}]}});

    await run("voice-release", async w => {
        const first = await say(w, utterance("Read my clipboard."));
        server.replies.push(calls({id: "call_voice", name: "clipboard_read", arguments: {}}), text(""));
        await until(() => w.s().approval.kind === "held", "the release question is held");
        const h = w.s().approval;
        w.runner.dispatch({type: "shown", gen: h.gen, op: h.op, id: h.id});
        w.advanceRunner(1100);
        control.utterances.push(utterance("Yes."));
        w.runner.dispatch({type: "talk-down"});
        await until(() => w.s().capture.kind === "open", "answer capture opens without a new brain turn");
        assert.equal(w.s().approval.id, h.id);
        assert.equal(w.s().turn.kind, "thinking");
        w.runner.dispatch({type: "talk-up"});
        const body = await requested(w, first + 2, "final voice answer releases the result");
        assert.equal(body.messages.find(m => m.role === "tool").content, "clipboard words");
        assert.deepEqual(user(body), ["Read my clipboard."], "confirmation is not a new user turn");
        assert.ok(w.rows().some(row => row.kind === "release" && row.confirmed === "voice" && row.decision === "send"));
    }, {fixture: {recipients: [{kind: "network", provider: "scripted-voice", account: "fixture", origin: "http://192.0.2.1:9"}]}});

    // LocalSpeech finishes on EOF. Indicator loss can close Toggle capture,
    // then a re-shown indicator opens an unbound capture while the brain waits.
    await run("voice-toggle-reopened", async w => {
        control.utterances.push(utterance("Read my clipboard."), utterance("Yes."), utterance("Yes."));
        const blocked = gate();
        const first = server.requests.length;
        server.replies.push([...pause(blocked), ...calls({ id: "toggle_voice", name: "clipboard_read", arguments: {} }).slice(1)], text(""));
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "toggle capture opens");
        w.runner.dispatch({ type: "indicator", shown: false });
        await requested(w, first + 1, "EOF final starts the thinking turn");
        await until(() => w.s().capture.kind === "closed", "indicator loss closes capture");
        w.runner.dispatch({ type: "indicator", shown: true });
        await until(() => w.s().capture.kind === "open", "indicator re-show opens thinking capture");
        const prior = w.s().capture.op;
        blocked.open();
        await until(() => w.s().approval.kind === "held", "release arrives after the reopened capture");
        const h = w.s().approval;
        w.runner.dispatch({ type: "shown", gen: h.gen, op: h.op, id: h.id });
        w.advanceRunner(1100);
        w.runner.dispatch({ type: "talk-down" });
        await until(() => (w.s().capture.kind === "open" && w.s().capture.op !== prior)
            || w.s().input.kind === "held" && w.s().capture.kind === "open", "Talk admits its answer capture");
        assert.notEqual(w.s().capture.op, prior, "Talk replaces the capture that predates the hold");
        assert.equal(w.s().approval.id, h.id, "earlier audio cannot release the hold");
        assert.equal(server.requests.length, first + 1, "earlier Yes starts no brain turn or transfer");
        w.runner.dispatch({ type: "talk-up" });
        const body = await requested(w, first + 2, "fresh Toggle answer releases the result");
        assert.equal(body.messages.find(m => m.role === "tool").content, "clipboard words");
        assert.deepEqual(user(body), ["Read my clipboard."]);
    }, { mode: "toggle", fixture: { recipients: [{ kind: "network", provider: "scripted-voice", account: "fixture", origin: "http://192.0.2.1:9" }] } });

    for (const order of ["before-display", "after-playback"]) {
        await run("voice-" + order, async w => {
            if (order === "after-playback") {
                const prior = await say(w, utterance("Say ready."));
                server.replies.push(text("Ready."));
                await requested(w, prior + 1, "prior reply starts");
                await until(() => w.s().turn.kind === "none" && w.s().playback.kind === "playing", "prior reply plays");
                w.advanceRunner(2000);
                await playOut(w);
            }
            const first = await say(w, utterance("Read my clipboard."));
            server.replies.push(calls({ id: "timing_voice", name: "clipboard_read", arguments: {} }), text(""));
            await until(() => w.s().approval.kind === "held", "timing question is held");
            const h = w.s().approval;
            if (order === "after-playback") {
                w.runner.dispatch({ type: "shown", gen: h.gen, op: h.op, id: h.id });
                w.advanceRunner(700);
            } else w.advanceRunner(1100);
            const finals = control.finals;
            control.utterances.push(utterance("Yes."));
            w.runner.dispatch({ type: "talk-down" });
            await until(() => w.s().capture.kind === "open", "rejected answer uses real capture");
            if (order === "before-display") {
                w.advanceRunner(100);
                w.runner.dispatch({ type: "shown", gen: h.gen, op: h.op, id: h.id });
            }
            w.advanceRunner(1100); // The final is late enough; its start is not.
            w.runner.dispatch({ type: "talk-up" });
            await until(() => control.finals > finals && w.s().capture.kind === "closed", "the answer final arrives after capture closes");
            await turn();
            assert.equal(w.s().approval.kind, "held", "the real engine refuses an answer with unsafe start timing");
            assert.equal(w.s().approval.id, h.id);
            assert.equal(w.s().turn.kind, "thinking");
            assert.equal(server.requests.length, first + 1, "rejected voice starts no brain turn or content transfer");
            assert.equal(w.rows().filter(row => row.kind === "release" && row.confirmed === "voice").length, 0);
            assert.equal(w.rows().at(-1).refusal, "voice-timing", "the release owner records the timing refusal");
        }, { fixture: { recipients: [{ kind: "network", provider: "scripted-voice", account: "fixture", origin: "http://192.0.2.1:9" }] } });
    }

    await run("release-refusal", async w => {
        const first = await say(w, utterance("Read my clipboard."));
        server.replies.push(calls({ id: "refusal_release", name: "clipboard_read", arguments: {} }), text(""));
        await until(() => w.s().approval.kind === "held", "refusal question is held");
        const h = w.s().approval;
        w.runner.dispatch({ type: "confirm", gen: h.gen, id: h.id, digest: h.digest, source: "button" });
        assert.equal(w.s().approval.id, h.id, "early button keeps its hold");
        assert.equal(server.requests.length, first + 1, "early button releases no content");
        const record = w.rows().at(-1);
        assert.equal(record.kind, "release");
        assert.equal(record.refusal, "early", "Session refusal reaches the conversation audit owner");
        assert.equal(record.outcome, "cancelled");
        assert.deepEqual(record.args, { labels: "[redacted]", recipients: "[redacted]" });
        assert.equal(JSON.stringify(record).includes(h.id), false);
        assert.equal(JSON.stringify(record).includes("clipboard words"), false);
        const before = w.rows().length;
        assert.deepEqual(w.audit.record({ ...record, refusal: "private planted transcript" }),
            { kind: "refuse", reason: "audit-write", cause: "refusal" }, "unknown refusal text never reaches the audit file");
        assert.equal(w.rows().length, before);
    }, { fixture: { recipients: [{ kind: "network", provider: "scripted-voice", account: "fixture", origin: "http://192.0.2.1:9" }] } });

    await run("release-decisions", async w => {
        const blocked = gate();
        const first = await say(w, utterance("Keep thinking.")); server.replies.push(pause(blocked));
        await requested(w, first + 1, "a live turn starts");
        const Policy = require(path.join(kit.folder, "backend/Policy.js"));
        const recipients = control.opened[0].recipients;
        const result = labels => ({gen: w.s().gen, op: w.s().turn.op, results: [{item: Policy.item("private mixed content", labels)}]});
        const answer = w.engine.release.prepare(result(["clipboard", "file"]), recipients);
        await until(() => w.s().approval.kind === "held", "mixed labels share a question");
        w.runner.dispatch({type: "approval-cancel", gen: w.s().gen, id: w.s().approval.id});
        assert.deepEqual(await answer, []);
        let repeated;
        const again = w.engine.release.prepare(result(["clipboard", "file"]), recipients).then(value => { repeated = value; });
        await until(() => repeated !== undefined || w.s().approval.kind === "held", "the repeated label receives its prior decision");
        assert.deepEqual(repeated, []);
        await again;
        assert.equal(w.s().approval.kind, "none", "declined labels do not ask again");
        const changed = w.engine.release.prepare(result(["web"]), recipients);
        await until(() => w.s().approval.kind === "held", "another label asks once");
        w.configure({...w.s().settings, brain: "different-account"});
        assert.equal(await changed, null, "settings cancel the pending prompt and grant context");
        blocked.open();
    }, {fixture: {recipients: [{kind: "network", provider: "scripted-voice", account: "fixture", origin: "http://192.0.2.1:9"}]}});

    // A failed audit write refuses the brain request and the speech text.
    await run("audit-refusal", async w => {
        const block = () => {
            fs.renameSync(path.join(w.state, "audit"), path.join(w.state, "audit-saved"));
            fs.writeFileSync(path.join(w.state, "audit"), "not a directory\n");
        };
        control.utterances.push(utterance("Hello."));
        const before = server.requests.length;
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "capture opens");
        block();
        w.runner.dispatch({ type: "talk-up" });
        // A request that reached the server already left unaudited.
        await settled(() => w.s().fault.kind === "error", () => server.requests.length > before, "the turn fails");
        assert.equal(w.s().fault.reason, "engine=audit-write");
        // The next request to arrive must be a later turn's: none left first.
        fs.rmSync(path.join(w.state, "audit"));
        fs.renameSync(path.join(w.state, "audit-saved"), path.join(w.state, "audit"));
        assert.deepEqual(w.configure({ mode: "hold", microphone: "", speaker: "", brain: "other-account" }), { kind: "ready" });
        await say(w, utterance("Again."));
        server.replies.push(text(""));
        assert.deepEqual(user(await requested(w, before + 1, "the next turn")), ["Again."],
            "no request left without its audit record");
    });
    await run("audit-refusal-speech", async w => {
        const first = await say(w, utterance("Hello."));
        await requested(w, first + 1, "first request");
        const held = gate();
        server.replies.push([...pause(held), ...text("Hi there.").slice(1)]);
        fs.renameSync(path.join(w.state, "audit"), path.join(w.state, "audit-saved"));
        fs.writeFileSync(path.join(w.state, "audit"), "not a directory\n");
        held.open();
        await until(() => w.s().fault.kind === "error", "the turn fails");
        assert.equal(w.s().fault.reason, "engine=audit-write");
        assert.deepEqual(control.spoken, [], "no text reaches speech without its audit record");
        assert.deepEqual(assistantCaptions(w), [], "no assistant text is captioned without its release");
    });

    // The plan's context bound: the fortieth turn is sent, the next fails.
    await run("context-bound", async w => {
        for (let index = 1; index <= 40; index++) {
            const before = await say(w, utterance("turn " + index));
            server.replies.push(text(""));
            await requested(w, before + 1, "turn " + index);
            await until(() => w.s().turn.kind === "none", "turn " + index + " completes");
        }
        const before = await say(w, utterance("one more"));
        await until(() => w.s().conversation.kind === "ended", "the bound ends the conversation");
        assert.equal(w.s().fault.kind, "none", "the bound leaves no fault");
        assert.equal(server.requests.length, before, "no request past the bound");
        const fresh = await say(w, utterance("A new start."));
        server.replies.push(text(""));
        assert.deepEqual(user(await requested(w, fresh + 1, "the next conversation")), ["A new start."]);
    });

    // Playback backpressure pauses the brain stream; no sentence is dropped.
    await run("backpressure", async w => {
        const first = await say(w, utterance("Read a long list."));
        await requested(w, first + 1, "first request");
        const sentences = Array.from({ length: 40 }, (_, index) => "Item number " + (index + 1) + ".");
        server.replies.push(text(...sentences.map(sentence => sentence + " ")));
        // Nothing advances the playback clock: the source fills to its mark.
        await until(() => w.audio.playbackFeed !== null
            && w.audio.playbackFeed.readableLength >= w.audio.playbackFeed.readableHighWaterMark, "the source fills");
        await until(() => w.s().turn.kind === "none", "the brain is read to its end");
        // Audio holds one chunk and the adapter one sentence beyond the mark.
        const bound = w.audio.playbackFeed.readableHighWaterMark + 2;
        assert.ok(control.spoken.length <= bound, "a stalled player pauses synthesis: " + control.spoken.length);
        await playOut(w);
        assert.equal(control.spoken.length, 40);
        assert.deepEqual(w.faults, []);
        assert.equal(w.s().fault.kind, "none");
    });

    // A partial revision that does not increase is an adapter fault.
    await run("partial-revision", async w => {
        control.utterances.push(utterance("x", [], [{ kind: "partial", text: "a", rev: 2 },
            { kind: "partial", text: "b", rev: 1 }, { kind: "final", text: "x" }]));
        const before = server.requests.length;
        w.runner.dispatch({ type: "talk-down" });
        // A later revision reached Session; the held capture then waits for a final.
        await settled(() => w.s().fault.kind === "error", () => w.partials.includes("b"), "the capture fails");
        assert.equal(w.s().fault.reason, "provider-disconnected");
        assert.equal(server.requests.length, before);
    });

    // Mute during capture retires the transcription without a final.
    await run("mute-capture", async w => {
        control.utterances.push(utterance("private words", ["private"]));
        const before = server.requests.length;
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.partials.at(-1) === "private", "transcription runs");
        w.runner.dispatch({ type: "mute-toggle" });
        await until(() => w.s().mute.kind === "on", "mute completes");
        // A delivered final ends the transcription without abandoning it.
        await settled(() => control.aborted === 1, () => control.finals === 1, "the transcription is abandoned");
        assert.equal(server.requests.length, before, "muted words never reach the brain");
    });

    // A coding task's question and the user's answer pass through the
    // relay, never the brain. With no conversation the prompt is a
    // notification; in one, Jarvis asks it at the first idle moment, and
    // a turn end is never called finished.
    const QUESTION = "The coding agent asks: Which branch should I use? Your next words are its answer.";
    const QUESTION_CARD = "The coding agent asks: Which branch should I use? Talk to Jarvis to answer.";
    const WAITING = "The coding agent stopped and is waiting.";
    const SENT = "I sent your answer to the coding agent.";
    // A conversation idle after one brain turn. Answers the count of
    // sentences spoken before the idle moment, when a task line may start.
    async function opened(w) {
        const first = await say(w, utterance("Hello."));
        await requested(w, first + 1, "the opening turn reaches the brain");
        server.replies.push(text("Hi."));
        await until(() => w.s().turn.kind === "none" && control.spoken.includes("Hi."), "the opening reply completes");
        const spokenBefore = control.spoken.length;
        await playOut(w);
        return spokenBefore;
    }
    // Waits until speech holds every sentence of line after the first from,
    // then plays it out and answers the spoken text.
    async function spoken(w, from, line) {
        await settled(() => control.spoken.slice(from).join(" ") === line,
            () => control.spoken.slice(from).join(" ").length > line.length, "Jarvis speaks: " + line);
        await playOut(w);
    }
    await run("task-relay", async w => {
        const t = w.tasks;
        t.task("earlier");
        t.event("earlier", "turn-ended");
        await t.observe();
        assert.deepEqual(t.notes, [], "the first observation only seeds: a restart says nothing old");
        t.task("t1");
        const question = t.ask("t1", { kind: "question", tool: null, text: "Which branch should I use?" });
        await t.observe();
        await until(() => t.notes.length === 1, "the held prompt is notified");
        assert.deepEqual(t.notes, [["Coding task", QUESTION_CARD]], "with no conversation the prompt is a notification");
        assert.deepEqual([control.spoken, w.s().conversation.kind], [[], "ended"], "nothing is spoken with no conversation");
        const asked = await opened(w);
        await spoken(w, asked, QUESTION);
        assert.ok(control.labels.has("agent"), "the agent's text reaches speech labelled as agent output");
        const requests = server.requests.length;
        // Another idle state publication asks nothing new.
        w.runner.dispatch({ type: "indicator", shown: true });
        await new Promise(resolve => setImmediate(resolve));
        assert.equal(control.spoken.length, asked + 2, "a prompt is asked once per conversation");
        const said = control.spoken.length;
        await say(w, utterance("Use main."));
        await spoken(w, said, SENT);
        assert.equal(server.requests.length, requests, "the answer never reaches the brain");
        assert.deepEqual(t.Relay.answerTo(t.prompts, question), { v: 1, kind: "reply", text: "Use main." });
        assert.deepEqual(w.captions.filter(row => row[1] === "user").map(row => row[4]), ["Hello.", "Use main."],
            "the user's answer shows as their words");
        assert.ok(w.captions.some(row => row[1] === "assistant" && row[4].includes("Which branch should I use?")),
            "the asked prompt is captioned as Jarvis's words");
        t.event("t1", "turn-ended");
        let from = control.spoken.length;
        await t.observe();
        await spoken(w, from, WAITING);
        t.event("t1", "outcome", { kind: "reported-ok" });
        from = control.spoken.length;
        await t.observe();
        await spoken(w, from, "The coding agent reports the task done.");
        assert.equal(control.spoken.some(sentence => /finish/i.test(sentence)), false, "no turn is called finished");
        const next = await say(w, utterance("Thanks."));
        server.replies.push(text(""));
        const body = await requested(w, next + 1, "the words after an answer reach the brain");
        assert.deepEqual(user(body), ["Hello.", "Thanks."], "the brain never sees a prompt, an answer or a task line");
        assert.deepEqual(body.messages.slice(1).map(message => [message.role, message.content]),
            [["user", "Hello."], ["assistant", "Hi."], ["user", "Thanks."]], "no task line enters the brain's history");
        assert.deepEqual([t.notes.length, t.logs, w.faults], [1, [], []]);
    }, { tasks: true });

    await run("task-permission", async w => {
        const t = w.tasks;
        await t.observe();
        await opened(w);
        t.task("t2");
        const permission = t.ask("t2", { kind: "permission", tool: "Bash", text: "Run the tests" });
        let from = control.spoken.length;
        await t.observe();
        await spoken(w, from, "The coding agent asks to use Bash: Run the tests. Say allow or deny.");
        const requests = server.requests.length;
        from = control.spoken.length;
        await say(w, utterance("Maybe."));
        await spoken(w, from, "Say allow or deny.");
        assert.equal(t.Relay.answerTo(t.prompts, permission), null, "an unjudged permission answer is not sent");
        from = control.spoken.length;
        await say(w, utterance("Allow."));
        await spoken(w, from, SENT);
        assert.deepEqual(t.Relay.answerTo(t.prompts, permission), { v: 1, kind: "allow" });
        assert.equal(server.requests.length, requests, "no permission answer reaches the brain");
        assert.deepEqual([t.notes, w.faults], [[], []]);
    }, { tasks: true });

    // Talk during the question flushes it: the user's words go to the brain
    // and the prompt is asked again at the next idle moment.
    await run("task-barge-in", async w => {
        const t = w.tasks;
        await t.observe();
        await opened(w);
        t.task("t3");
        const question = t.ask("t3", { kind: "question", tool: null, text: "Which branch should I use?" });
        const from = control.spoken.length;
        await t.observe();
        await until(() => control.spoken.length > from && w.s().playback.kind === "playing", "the question starts to play");
        const next = await say(w, utterance("What time is it?"));
        const body = await requested(w, next + 1, "the interrupting words reach the brain");
        assert.deepEqual(user(body), ["Hello.", "What time is it?"], "an interrupted question takes no answer");
        assert.equal(t.Relay.answerTo(t.prompts, question), null);
        server.replies.push(text("Noon."));
        const again = control.spoken.length;
        await until(() => w.s().turn.kind === "none", "the brain answers");
        await playOut(w);
        await spoken(w, again + 1, QUESTION);
    }, { tasks: true });

    // Two held prompts: the conversation asks one at a time, so the user's
    // words answer the prompt they heard, and the second is asked after it.
    await run("task-two-prompts", async w => {
        const t = w.tasks;
        await t.observe();
        await opened(w);
        t.task("ta");
        t.task("tb");
        const first = t.ask("ta", { kind: "question", tool: null, text: "Which branch should I use?" });
        const second = t.ask("tb", { kind: "question", tool: null, text: "Which test should I run?" });
        let from = control.spoken.length;
        await t.observe();
        await spoken(w, from, QUESTION);
        w.runner.dispatch({ type: "indicator", shown: true });
        await new Promise(resolve => setImmediate(resolve));
        assert.equal(control.spoken.length, from + 2, "the second prompt waits while the first holds the next words");
        from = control.spoken.length;
        await say(w, utterance("Use main."));
        await spoken(w, from, SENT);
        assert.deepEqual([t.Relay.answerTo(t.prompts, first), t.Relay.answerTo(t.prompts, second)],
            [{ v: 1, kind: "reply", text: "Use main." }, null], "the answer reaches the prompt the user heard");
        from = control.spoken.lastIndexOf(SENT) + 1;
        await spoken(w, from, "The coding agent asks: Which test should I run? Your next words are its answer.");
        from = control.spoken.length;
        await say(w, utterance("Run all of them."));
        await spoken(w, from, SENT);
        assert.deepEqual(t.Relay.answerTo(t.prompts, second), { v: 1, kind: "reply", text: "Run all of them." });
        assert.deepEqual([t.notes, w.faults], [[], []]);
    }, { tasks: true });

    // A stop while a prompt is spoken: the conversation ends, and the
    // prompt the user did not hear whole is notified, once.
    await run("task-stop-spoken", async w => {
        const t = w.tasks;
        await t.observe();
        await opened(w);
        t.task("t5");
        t.ask("t5", { kind: "question", tool: null, text: "Which branch should I use?" });
        const from = control.spoken.length;
        await t.observe();
        await until(() => control.spoken.length > from && w.s().playback.kind === "playing", "the question starts to play");
        w.runner.dispatch({ type: "stop" });
        await until(() => w.s().conversation.kind === "ended" && t.notes.length > 0, "the cut-off prompt is notified");
        await new Promise(resolve => setImmediate(resolve));
        assert.deepEqual(t.notes, [["Coding task", QUESTION_CARD]]);
    }, { tasks: true });

    // A task line whose relay turn fails ends the conversation unspoken and
    // reaches the user as a notification.
    await run("task-line-failed", async w => {
        const t = w.tasks;
        await opened(w);
        t.task("t6");
        await t.observe();
        fs.renameSync(path.join(w.state, "audit"), path.join(w.state, "audit-saved"));
        fs.writeFileSync(path.join(w.state, "audit"), "not a directory\n");
        try {
            t.event("t6", "turn-ended");
            await t.observe();
            await until(() => w.s().fault.kind === "error" && t.notes.length > 0, "the failed line is notified");
        } finally {
            fs.rmSync(path.join(w.state, "audit"));
            fs.renameSync(path.join(w.state, "audit-saved"), path.join(w.state, "audit"));
        }
        assert.equal(w.s().fault.reason, "engine=audit-write");
        assert.deepEqual(t.notes, [["Coding task", WAITING]]);
        assert.equal(control.spoken.includes(WAITING), false);
    }, { tasks: true });

    // A permission prompt takes one re-ask. Words that again answer nothing
    // are the user's own turn; the prompt is asked once more at a later idle
    // moment, and then left to the console.
    await run("task-permission-release", async w => {
        const t = w.tasks;
        const PERMISSION = "The coding agent asks to use Bash: Run the tests. Say allow or deny.";
        // One brain turn of the user's own words; answers the brain's request.
        async function own(said, reply) {
            const next = await say(w, utterance(said));
            const body = await requested(w, next + 1, "the words reach the brain: " + said);
            server.replies.push(text(reply));
            await until(() => control.spoken.includes(reply), "the brain's reply is spoken");
            return body;
        }
        await t.observe();
        await opened(w);
        t.task("t7");
        const permission = t.ask("t7", { kind: "permission", tool: "Bash", text: "Run the tests" });
        let from = control.spoken.length;
        await t.observe();
        await spoken(w, from, PERMISSION);
        for (const [unjudged, own1, reply] of [["Maybe.", "What time is it?", "Noon."], ["Later.", "Tell me more.", "Sure."]]) {
            from = control.spoken.length;
            await say(w, utterance(unjudged));
            await spoken(w, from, "Say allow or deny.");
            const body = await own(own1, reply);
            assert.equal(user(body).at(-1), own1, "words that again answer nothing go to the brain");
            assert.equal(user(body).some(item => item.includes(unjudged)), false, "a re-ask's words never reach the brain");
            from = control.spoken.lastIndexOf(reply) + 1;
            await playOut(w);
            if (reply === "Noon.") await spoken(w, from, PERMISSION);
            else {
                w.runner.dispatch({ type: "indicator", shown: true });
                await new Promise(resolve => setImmediate(resolve));
                assert.equal(control.spoken.length, from, "a conversation asks a released prompt twice at most");
            }
        }
        assert.equal(t.Relay.answerTo(t.prompts, permission), null, "no unjudged words answer the permission");
    }, { tasks: true });

    // A release the user declines keeps the agent's text from speech; the
    // prompt goes to a notification and the next words go to the brain.
    await run("task-release-declined", async w => {
        const t = w.tasks;
        await t.observe();
        await opened(w);
        t.task("t4");
        t.ask("t4", { kind: "question", tool: null, text: "Which branch should I use?" });
        await t.observe();
        await until(() => w.s().approval.kind === "held", "agent text asks for release first");
        assert.equal(w.s().approval.purpose, "release");
        const h = w.s().approval;
        w.runner.dispatch({ type: "approval-cancel", gen: h.gen, id: h.id });
        await until(() => t.notes.length === 1 && w.s().turn.kind === "none", "the withheld prompt is notified");
        assert.deepEqual(t.notes, [["Coding task", QUESTION_CARD]]);
        assert.equal(control.spoken.some(sentence => sentence.includes("Which branch")), false, "withheld text is not spoken");
        const next = await say(w, utterance("Never mind."));
        server.replies.push(text(""));
        const body = await requested(w, next + 1, "the next words reach the brain");
        assert.deepEqual(user(body), ["Hello.", "Never mind."]);
    }, { tasks: true, fixture: { recipients: [{ kind: "network", provider: "scripted-voice", account: "fixture", origin: "http://192.0.2.1:9" }] } });
}

// Each task voice rule turns its scenario red: an engine copy with one
// planted defect, or a TaskVoice copy loaded again under its engine.
async function taskControls(root, server) {
    let controls = 0;
    for (const [name, needle, replacement, scenario] of [
            ["relay-answer-to-brain", 'if (c.relay !== null && e.text.trim() !== "") {', "if (false) {", "task-relay"],
            ["relay-heard-whole", "c.relay = turn.relay.ask;", "void turn;", "task-relay"],
            ["relay-held-at-done", '            }\n            turn.phase = "done";\n',
                '            }\n            turn.phase = "done";\n            if (turn.relay.ask !== null) c.relay = turn.relay.ask;\n', "task-barge-in"],
            ["relay-heard-prefix", "if (own && turn.relay === null) heard(", "if (own) heard(", "task-barge-in"],
            ["relay-flush-forgotten", "else if (own) unheard(c, turn);", "", "task-barge-in"],
            ["relay-withheld-silent", "tasks.withheld(c.gen, text, turn.relay.ask ?? turn.relay.about ?? null);", "void text;", "task-release-declined"],
            ...["task-stop-spoken", "task-line-failed"].map(scenario => ["relay-end-forgets-" + scenario,
                "        if (c.last !== null) unheard(c, c.last);\n", "", scenario]),
            ["relay-retry-captures", "if (prompt !== null && answer === null && c.retried === c.relay) {",
                "if (false) {", "task-permission-release"]
    ]) {
        await assert.rejects(() => cases(Fixture.copy(root, [[needle, replacement]]), server, scenario), assert.AssertionError,
            name + " must turn its scenario red");
        console.log("control=" + name + " detected");
        controls++;
    }
    for (const [name, needle, replacement, scenario] of [
        ["permission-maybe", 'return ALLOW.includes(said) ? { v: 1, kind: "allow" }', 'return !DENY.includes(said) ? { v: 1, kind: "allow" }', "task-permission"],
        ["no-conversation-spoken", 'const open = refusal => refusal === null || refusal === "busy";', "const open = () => true;", "task-relay"],
        ["prompt-asked-twice", "        asked.prompts.set(key(prompt), { count: entry(key(prompt)).count + 1, open: true });\n", "", "task-relay"],
        ["cut-off-card-spoken", '                send(promptLine(prompt, "notification"));', '                send(promptLine(prompt, "voice"));', "task-stop-spoken"],
        ["withheld-card-spoken", '            if (prompt !== undefined) send(promptLine(prompt, "notification"));', '            if (prompt !== undefined) send(text);', "task-release-declined"],
        ["two-prompts-at-once", "        if (held.some(prompt => entry(key(prompt)).open)) return null;\n", "", "task-two-prompts"],
        ["released-asked-forever", "        return held.find(prompt => entry(key(prompt)).count < ASKS) ?? null;",
            "        return held.find(() => true) ?? null;", "task-permission-release"]
    ]) {
        const kit = Fixture.copy(root);
        const file = path.join(kit.folder, "backend/TaskVoice.js");
        const source = fs.readFileSync(file, "utf8");
        assert.equal(source.split(needle).length - 1, 1, name + " mutation match");
        fs.writeFileSync(file, source.replace(needle, replacement));
        // The copy's engine loaded TaskVoice already: load both again.
        const engineFile = path.join(kit.folder, "backend/ChainedEngine.js");
        delete require.cache[file];
        delete require.cache[engineFile];
        kit.Engine = require(engineFile);
        await assert.rejects(() => cases(kit, server, scenario), assert.AssertionError, name + " must turn its scenario red");
        console.log("control=" + name + " detected");
        controls++;
    }
    return controls;
}

// Selection: the first ready speech row, then the saved brain account as
// Accounts.choose takes it and its provider row. The two steps are judged
// apart: each refusal names its cause, the first failing step's leads, and
// every failing step's cause follows in speech-then-brain order.
function selection(Engine) {
    const resolved = { id: "a", provider: "ollama", label: "local",
        source: { kind: "local", origin: "http://127.0.0.1:" + PORT }, model: "fixture-model" };
    const accepted = account => () => ({ kind: "accepted", account });
    const refused = cause => () => ({ kind: "refused", cause });
    const configure = (settings, choose, ready, wake = false) => {
        Fixture.reset({ ready, wake });
        let answer;
        assert.doesNotThrow(() => {
            answer = Engine.create({ accounts: () => ({ secrets: null, choose }), captionLimit: 1 }).configure({ brain: "a", ...settings });
        }, "selection answers with a cause");
        return answer;
    };
    for (const [settings, choose, ready, causes] of [
        [{}, accepted(resolved), false, ["speech=fixture-off"]],
        [{ brain: "" }, accepted(resolved), false, ["speech=fixture-off", "brain=unselected"]],
        [{}, refused("account-unavailable"), false, ["speech=fixture-off", "brain=account-unavailable"]],
        [{ brain: "" }, accepted(resolved), true, ["brain=unselected"]],
        [{}, refused("account-unavailable"), true, ["brain=account-unavailable"]],
        [{}, refused("model-required"), true, ["brain=model-required"]]])
        assert.deepEqual(configure(settings, choose, ready), { kind: "unconfigured", cause: causes[0], causes }, causes.join(" "));
    assert.deepEqual(configure({}, () => { throw new Error("jarvis-keys: references=json"); }, true),
        { kind: "unconfigured", cause: "brain=accounts-unreadable", detail: "jarvis-keys: references=json", causes: ["brain=accounts-unreadable"] },
        "a reader's keyed failure keeps its cause");
    Fixture.reset();
    assert.throws(() => Engine.create({ accounts: () => ({ choose: () => { throw new TypeError("defect"); } }), captionLimit: 1 })
        .configure({ brain: "a" }), TypeError, "a defect is not a configuration cause");
    assert.deepEqual(configure({}, accepted(resolved), true), { kind: "ready" });
    // Always mode needs a row that spots the word on this computer.
    const always = ["speech=always-local-voice"];
    for (const [settings, wake, causes] of [
        [{ mode: "always" }, false, always],
        [{ mode: "always", voiceProvider: "gpt-live" }, true, always],
        [{ mode: "always", brain: "" }, false, [...always, "brain=unselected"]]])
        assert.deepEqual(configure(settings, accepted(resolved), true, wake), { kind: "unconfigured", cause: causes[0], causes }, JSON.stringify(settings));
    assert.deepEqual(configure({ mode: "always" }, accepted(resolved), false, true), { kind: "unconfigured", cause: "speech=fixture-off",
        causes: ["speech=fixture-off"] }, "a row not set up keeps its own cause and Settings path");
    assert.deepEqual(configure({ mode: "always" }, accepted(resolved), true, true), { kind: "ready" });
    assert.deepEqual(configure({ mode: "toggle" }, accepted(resolved), true), { kind: "ready" });
    // A subscription's program chooses its own model; its account names its directory.
    for (const [provider, directory] of [["codex", "/home/fixture/.codex"], ["claude", "/home/fixture/.claude"]])
        assert.deepEqual(configure({}, accepted({ id: "c", provider, label: "default",
            source: { kind: "cli", directory }, model: "" }), true), { kind: "ready" }, provider);
}

world(async () => {
    const root = process.env.JARVIS_TEST_ROOT;
    // Without local setup's marker the stock table's local row is the cause.
    const stock = require(path.join(tree, "shell/plugins/vgs.jarvis/backend/ChainedEngine.js"));
    const bare = fs.mkdtempSync(path.join(root, "stock-"));
    assert.deepEqual(stock.create({ accounts: () => ({ secrets: null, choose: () => ({ kind: "refused", cause: "account-unavailable" }) }),
        captionLimit: 1, directories: { state: bare, data: bare, runtime: bare } }).configure({ brain: "a" }),
    { kind: "unconfigured", cause: "speech=local-not-set-up", causes: ["speech=local-not-set-up", "brain=account-unavailable"] },
    "the stock daemon stays unconfigured and judges the brain too");
    const server = Fixture.brain(PORT);
    await server.ready;
    let controls = 0;
    try {
        // A wait that never observes fails typed; one that settles on another
        // state fails its own assertion, so a control names which it met.
        await assert.rejects(wait(() => false, "unobserved", 20), { operator: "until" });
        await assert.rejects(settled(() => false, () => true, "settled elsewhere"), error => error.operator === "==");
        selection(Fixture.copy(root).Engine);
        for (const [name, needle, replacement = ""] of [
            ["speech-first", "const failing = [speech, brain]", "const failing = [brain, speech]"],
            ["every-cause", "causes: failing.map(step => step.cause)", "causes: [failing[0].cause]"],
            ["first-speech-cause", 'if (speech.cause === "speech=no-adapter") speech = answer;'],
            ["accounts-unreadable", 'return unconfigured("brain=accounts-unreadable", error.message);'],
            ["unselected", 'if (settings.brain === "") return unconfigured("brain=unselected");'],
            ["refused-cause", 'return unconfigured("brain=" + choice.cause);', 'return unconfigured("brain=account-unavailable");'],
            ["harness-driver", '"codex-app-server": CodexHarness, '],
            ["claude-driver", ', "claude-code": ClaudeCode });', " });"],
            ["always-any-voice", 'settings.mode === "always" && (', "false && ("],
            ["always-live-voice", 'settings.voiceProvider === "gpt-live" || speech.kind', "speech.kind"],
            ["always-wake-row", ' && speech.wake !== true))', "))"]]) {
            const { Engine } = Fixture.copy(root, [[needle, replacement]]);
            assert.throws(() => selection(Engine), assert.AssertionError, name + " must turn red");
            console.log("control=" + name + " detected");
            controls++;
        }
        await cases(Fixture.copy(root), server);
        await daemonSpeech(server);
        await daemonSpeech(server, [], "ready", "brain-failed");
        await daemonSpeech(server, [], "not-ready");
        await daemonSpeech(server, [], "memory-refused");
        await daemonSpeech(server, [], "memory-unavailable");
        await assert.rejects(() => daemonSpeech(server,
            [['error.kind === "refused"', 'false']], "memory-refused"), assert.AssertionError,
            "a startup memory refusal cannot restore readiness");
        console.log("control=memory refusal admitted detected");
        controls++;
        await daemonSpeech(server, [], "held");
        for (const ending of ["ready", "stop", "mute", "lock", "lease", "fault", "locked", "muted", "missing", "brain", "device"])
            await loadingTalk(server, ending);
        for (const ending of ["ready", "refused", "unset"]) await alwaysTalk(server, ending);
        for (const [name, file, needle, replacement] of [
            ["wake sink removed", "backend/ChainedEngine.js", '            if (e.mode === "armed") return spotting(e);\n', ""],
            ["wake not dispatched", "backend/ChainedEngine.js", 'if (result.kind === "woke") dispatch({ type: "wake", gen: e.gen, op: e.op });', "void result;"],
            ["Always refusal removed", "backend/ChainedEngine.js", 'settings.mode === "always" && (settings.voiceProvider', 'false && (settings.voiceProvider']
        ]) {
            await assert.rejects(() => alwaysTalk(server, name === "Always refusal removed" ? "refused" : "ready", [[file, needle, replacement]]),
                assert.AssertionError, name);
            console.log("control=" + name + " detected");
            controls++;
        }
        for (const [name, file, needle, replacement] of [
            ["loading admission removed", "backend/jarvisd.js", ' || configuration.kind === "loading"', ""],
            ["loading ready too early", "backend/ChainedEngine.js", 'return { kind: "loading", cause: "speech=local-loading", causes: ["speech=local-loading"] };', 'return { kind: "ready" };'],
            ["loading ignores presented indicator", "Session.js", 's.indicator.kind === "shown"', "true"],
            ["loading starts a second child", "backend/ChainedEngine.js", 'if (plan.speech.lifetime === "daemon" && daemonSpeech === null) startSpeech(plan.speech);', 'if (plan.speech.lifetime === "daemon") startSpeech(plan.speech);'],
            ["replacement loading unpublished", "backend/ChainedEngine.js", 'daemonSpeech = owner;\n        configured(configuration());', 'daemonSpeech = owner;'],
            ["loading cancellation replays", "backend/ChainedEngine.js", '            if (utterance) utterance.abort();', '            void utterance;']
        ]) {
            const ending = name === "loading cancellation replays" ? "stop" : name === "replacement loading unpublished" ? "fault" : "ready";
            await assert.rejects(() => loadingTalk(server, ending, [[file, needle, replacement]]), assert.AssertionError, name);
            console.log("control=" + name + " detected");
            controls++;
        }
        for (const [name, edits] of [
            ["ready before model load", [['speechState.kind === "new" || published) startSpeech(plan.speech);', 'false) startSpeech(plan.speech);']]],
            ["conversation unloads local speech", [['if (c.plan.speech.lifetime !== "daemon") c.speech.close();', 'c.speech.close();']]],
            ["faulted child kept", [["daemonSpeech = null;\n            // A startup", "// A startup"]]],
            ["admission refusal admitted", [['{ kind: "refused", error, publication: row.publication }', '{ kind: "unloaded" }']]],
            ["ordinary hello retries refusal", [['speechState.publication !== plan.speech.publication', 'true']]],
            ["setup publication ignored", [['speechState.publication !== plan.speech.publication', 'false']]]
        ]) {
            await assert.rejects(() => daemonSpeech(server, edits, ["admission refusal admitted", "ordinary hello retries refusal", "setup publication ignored"].includes(name) ? "not-ready" : "ready"),
                assert.AssertionError, name + " control must fail");
            console.log("control=" + name + " detected");
            controls++;
        }
        await assert.rejects(() => daemonSpeech(server,
            [['if (c.plan.speech.lifetime !== "daemon") c.speech.close();', 'c.speech.close();']], "ready", "brain-failed"),
            assert.AssertionError, "conversation fault unload control must fail");
        console.log("control=conversation fault unloads local speech detected");
        controls++;
        assert.deepEqual(server.faults, [], "every request matched the pinned schema");
        // Each control plants one defect in a disposable engine copy.
        const plants = [
            ["start-earcon-silenced", 'pcm.writeInt16LE(Math.round(3900 * envelope * Math.sin(2 * Math.PI * frequency * frame / PCM_RATE)), frame * 2);',
                'pcm.writeInt16LE(0, frame * 2);', "feedback-start"],
            ["working-earcon-silenced", 'c.turn.speech.readable.push(earcon("working"));',
                'c.turn.speech.readable.push(Buffer.alloc(5760));', "feedback-working"],
            ["feedback-text-suppression", 'if (event.text.trim() !== "") quiet(turn);', 'void event;', "feedback-suppressed-text"],
            ["feedback-tool-suppression", 'case "done":\n                    quiet(turn);',
                'case "done":\n                    void turn;', "feedback-suppressed-tool"],
            ["feedback-disable-stream", 'turn.speech = null;\n            }\n            if (s.playback.kind',
                'void turn.speech;\n            }\n            if (s.playback.kind', "feedback-disable-working"],
            ...["action", "release"].map(purpose => ["feedback-approval-stream-" + purpose,
                's.settings.sounds !== true || s.approval.kind === "held"', 's.settings.sounds !== true',
                "feedback-voice-" + purpose]),
            ["feedback-flush-heard-context", 'const speaking = turn?.speaking === true;',
                'const speaking = true;', "feedback-delayed-flush"],
            ["release-grant", "if (accepted) c.grants.push(grant);", "void grant;", "release-grants"],
            ["release-decline-once", "for (const label of pending.labels) c.decisions.add(label);", "void pending.labels;", "release-decisions"],
            ["voice-confirmation", 'dispatch({ type: "confirm", ...answer, source: "voice" });',
                'dispatch({ type: "confirm", ...answer, source: "model" });', "voice-release"],
            ["voice-final-time", 'dispatch({ type: "confirm", ...answer, source: "voice" });',
                'dispatch({ type: "confirm", ...answer, beganAt: clock.now(), source: "voice" });', "voice-before-display"],
            ["voice-idle-across-playback", 'if (s.playback.kind !== "idle") idleAt = null;',
                'if (false) idleAt = null;', "voice-after-playback"],
            ["release-refusal-record", 'refusal: e.reason });', 'refusal: undefined });', "release-refusal"],
            ["router-offers", "tools: router.offer()", "tools: []", "turn-loop"],
            ["heard-omitted", "if (c.heard !== null) items.push(heardItem(c.heard));", "", "barge-in"],
            ["heard-once", "            c.heard = null;\n", "", "barge-in"],
            ["full-reply-heard", 'heard(c, turn, report === null ? "" : report.heardText);',
                'heard(c, turn, "Hello there. The time is noon.");', "barge-in"],
            ["cancel-heard", '            if (c.live === null && turn.relay === null) heard(c, turn, "");\n', "", "cancel-thinking"],
            ["partial-to-brain", 'utterance.collection?.done("partial", event.text);', 'utterance.collection?.done("final", event.text);', "turn-loop"],
            ["speakable-bypass", "for (const sentence of text.push(event.text)) say(c, turn, sentence);",
                "text.push(event.text); say(c, turn, event.text);", "turn-loop"],
            ["unlabelled-frames", 'return { value: Policy.item(chunk, ["speech"]), done: false };',
                'return { value: Policy.item(chunk, ["desktop"]), done: false };', "turn-loop"],
            ["result-identity", 'if (turn !== null && turn.op === value.op && turn.phase === "routing" && turn.routing?.id === id) {',
                "if (turn !== null) {", "stale-outcome"],
            ["interrupted-answers", "if (routing && c.brain !== null) c.brain.record(", "if (false) c.brain.record(", "stale-outcome"],
            ["not-started", 'return router.interrupted(call, "not-started");', 'return router.interrupted(call, "running");', "stale-outcome"],
            ["late-result", "c.results.push(lateItem(late.call, value.outcome, item));", "void lateItem;", "stale-outcome"],
            ["history-taint", "router.observe(turn, reply.release.labels);", "void reply;", "history-taint"],
            ["toggle-adoption", 'c.unbound !== null && c.unbound.state === "running" ? c.unbound : null',
                "c.unbound", "toggle-turns"],
            ["toggle-detection", 'transcribe(frames, { detect: e.mode !== "hold" })',
                'transcribe(frames, { detect: false })', "toggle-turns"],
            ["collect-failure", "else if (collecting(c, utterance.collection)) utterance.collection.failed(keyed(error));",
                "else if (false) utterance.collection.failed(keyed(error));", "transcribe-failure"],
            ["speech-gates-brain", 'turn.speech?.end();\n                        concluded(c, turn);',
                'turn.speech?.end();\n                        await new Promise(resolve => turn.speech.readable.once("close", resolve));\n                        concluded(c, turn);', "long-speech"],
            ["net-not-closed", "        c.net.close();\n", "", "conversation-end"],
            ["observe-teardown", "if (conversation !== null && (s.gen !== conversation.gen || s.conversation.kind === \"ended\")) end();", "void s;", "settings-change"],
            ["audit-skipped", '"pending"), start);\n        if (result.kind !== "started") fail("audit-write");\n        return result.value;',
                '"pending"), () => {});\n        void result;\n        return start();', "audit-refusal"],
            ["after-tool-rule", "...(after === null ? {} : { instructions: after }),", "", "tool-round"],
            ["image-answer", "turn.answers.set(id, image === undefined ? { item } : { item, image });", "turn.answers.set(id, { item });", "screen-image"],
            ["images-ready", 'return current.kind === "ready" && current.brain.provider.images;', "return true;", "screen-image"],
            ["context-clean-end", 'turn.done(reason === "brain=context-limit" ? "brain-ended" : "brain-failed", { reason });',
                'turn.done("brain-failed", { reason });', "context-bound"],
            ["readable-backpressure", "if (!readable.push(step.value)) await wanted.wait();", "readable.push(step.value);", "backpressure"],
            ["partial-revision", "event.rev <= rev", "false", "partial-revision"],
            ["end-aborts-transcription", "            if (utterance) utterance.abort();", "            void utterance;", "mute-capture"],
            ["caption-dropped", "        caption(c, turn, sentence);\n", "", "turn-loop"],
            ["caption-final", 'concluded(c, turn);\n                        turn.done("brain-done");', 'turn.done("brain-done");', "turn-loop"],
            ["caption-revision", "rev: ++c.rev", "rev: 1", "turn-loop"],
            ["caption-before-release", "        transfer(c, turn, item, () => {\n            if (turn.speech === null) {",
                "        caption(c, turn, sentence);\n        transfer(c, turn, item, () => {\n            if (turn.speech === null) {", "audit-refusal-speech"],
            ["caption-separator", "        if (turn.caption.length + 1 >= captionLimit) concluded(c, turn);\n", "", "caption-segments"],
            ["caption-bound", "const room = captionLimit - turn.caption.length;", "const room = Infinity;", "caption-segments"],
            ["caption-failure-final", "        concluded(c, turn);\n        const reason = keyed(error);", "        const reason = keyed(error);", "caption-segments"]
        ];
        for (const [name, needle, replacement, scenario] of plants) {
            // The copy asserts its match outside the measured run.
            const kit = Fixture.copy(root, [[needle, replacement]]);
            let failure = null;
            try { await cases(kit, server, scenario); }
            catch (error) { failure = error; }
            assert.ok(failure instanceof assert.AssertionError, name + " must turn an assertion red: " + failure);
            console.log("control=" + name + " detected operator=" + failure.operator + ": " + failure.message.split("\n")[0]);
            controls++;
        }
        controls += await taskControls(root, server);
        const toggleKit = Fixture.copy(root);
        const sessionFile = path.join(toggleKit.folder, "Session.js");
        const sessionSource = fs.readFileSync(sessionFile, "utf8");
        const closeNeedle = '                closeCapture(s, effects);\n                start(s, effects, "held", e.at);';
        assert.equal(sessionSource.split(closeNeedle).length, 2, "one held-answer capture control match");
        fs.writeFileSync(sessionFile, sessionSource.replace(closeNeedle, '                start(s, effects, "held", e.at);'));
        await assert.rejects(() => cases(toggleKit, server, "voice-toggle-reopened"), assert.AssertionError,
            "retaining a prior Toggle capture must fail the fresh-answer assertion");
        console.log("control=voice-toggle-reopened detected");
        controls++;
        for (const [name, needle, replacement, scenario] of [
            ["feedback-pending-play", 'if (s.playback.kind === "flushing" && s.conversation.kind === "active") {',
                'if (false && s.playback.kind === "flushing" && s.conversation.kind === "active") {', "feedback-delayed-flush"],
            ...["action", "release"].map(purpose => ["feedback-approval-flush-" + purpose,
                'if (s.playback.kind === "feedback" && s.playback.cue === "working") flushPlayback(s, effects);',
                'if (false) flushPlayback(s, effects);', "feedback-voice-" + purpose])
        ]) {
            const kit = Fixture.copy(root);
            const file = path.join(kit.folder, "Session.js");
            const source = fs.readFileSync(file, "utf8");
            assert.equal(source.split(needle).length - 1, 1, name + " mutation match");
            fs.writeFileSync(file, source.replace(needle, replacement));
            await assert.rejects(() => cases(kit, server, scenario), assert.AssertionError,
                name + " must turn the playback assertion red");
            console.log("control=" + name + " detected");
            controls++;
        }
        const refusalKit = Fixture.copy(root);
        const daemonFile = path.join(refusalKit.folder, "backend/jarvisd.js");
        const daemonSource = fs.readFileSync(daemonFile, "utf8");
        const refusalNeedle = 'e.purpose === "release" ? engine.release.refused(e) : actionApproval.refused(e)';
        assert.equal(daemonSource.split(refusalNeedle).length, 2, "one release refusal wiring control match");
        fs.writeFileSync(daemonFile, daemonSource.replace(refusalNeedle,
            'e.purpose === "release" ? undefined : actionApproval.refused(e)'));
        await assert.rejects(() => cases(refusalKit, server, "release-refusal"), assert.AssertionError,
            "dropping daemon release refusal delivery must fail its audit assertion");
        console.log("control=release-refusal-wiring detected");
        controls++;
        const auditKit = Fixture.copy(root);
        const auditFile = path.join(auditKit.folder, "backend/Audit.js");
        const auditSource = fs.readFileSync(auditFile, "utf8");
        const auditNeedle = 'if (event.refusal !== undefined && (kind !== "release" || ![';
        assert.equal(auditSource.split(auditNeedle).length, 2, "one refusal category control match");
        fs.writeFileSync(auditFile, auditSource.replace(auditNeedle, 'if (false && (kind !== "release" || !['));
        await assert.rejects(() => cases(auditKit, server, "release-refusal"), assert.AssertionError,
            "copying arbitrary refusal text must fail its sanitization assertion");
        console.log("control=release-refusal-category detected");
        controls++;
        console.log("test-jarvis-engine: ok requests=" + server.requests.length + " controls=" + controls);
    } finally { await server.close(); }
// Bounds a hung world: each control reruns a case with real children.
}, 900000).catch(error => { console.error(error); process.exitCode = 1; });
