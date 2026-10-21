#!/usr/bin/env node
// The chained engine through the real Session, runner, Audio, router, audit,
// release gate and wire brain, with scripted speech adapters and a loopback
// brain inside the J09 world. Every request body is read at the server.
"use strict";
const { assert, fs, path, cp, tree, world, until: wait } = require("./fixtures/jarvis/audio.js");
const { once } = require("node:events");
const http = require("node:http");
const net = require("node:net");
const { clock, turn } = require("./fixtures/jarvis/playback.js");
const Fixture = require("./fixtures/jarvis/engine.js");
const Frames = require("./fixtures/jarvis-brain/openai-chat-frames.js");
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
const withoutAcks = rows => rows.filter(sentence => !["On it.", "Let me check."].includes(sentence));
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

// One expression of the shipped daemon's wiring, evaluated in the rig's scope.
function shipped(source, pattern, scope, what) {
    const found = [...source.matchAll(pattern)];
    assert.equal(found.length, 1, "one shipped daemon " + what);
    return vm.runInContext("(" + found[0][1] + ")", scope);
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
    const daemonSource = fs.readFileSync(path.join(kit.folder, "backend/jarvisd.js"), "utf8");
    // A harness program's tool bridge takes the shipped daemon's result
    // route and bridge wiring, so its answers reach the engine as in jarvisd.
    const daemon = options.bridge ? vm.createContext({ runner, audit, router: null, engine: null, gate: null, bridge: null,
        context: { directories: { runtime: fs.mkdtempSync(path.join(process.env.XDG_RUNTIME_DIR, "b-")) } } }) : null;
    const result = daemon === null ? value => runner.ports.brain.outcome(value)
        : shipped(daemonSource, /result: (value => gate\.deliver\(value\)[^\n]*?),\n/g, daemon, "result route");
    const router = Router.create({ session: Session, state: () => runner.state, dispatch: e => runner.dispatch(e), audit,
        context: () => ({ profile: "standard", locked: false, denied: options.actionApproval ? Denied.create({
            home: process.env.HOME, config: process.env.XDG_CONFIG_HOME, data: process.env.XDG_DATA_HOME,
            state: options.deniedState ?? process.env.XDG_STATE_HOME, runtime: process.env.XDG_RUNTIME_DIR, install: kit.folder, accountRoots: [], jarvisHome: null
        }) : null }),
        result, routed: turn => engine?.brain.routed(turn) });
    Object.assign(ports, router.ports);
    if (daemon !== null) {
        daemon.router = router;
        daemon.bridge = backend("ToolBridge.js").create(shipped(daemonSource,
            /bridge = ToolBridge\.create\((\{[\s\S]*?\})\);\n/g, daemon, "bridge"));
        daemon.gate = backend("HarnessGate.js").create({ router, state: () => runner.state });
    }
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
    router.register("harness", { commands: [], timeoutMs: 30000, cancellable: false, start(call, done) {
        executions.push(call);
        done({ outcome: "completed", content: "harness acted" });
    } });
    // The files executor stands in for a command-ready one; it touches nothing.
    if (options.filesExecutor) router.register("files", { commands: [], timeoutMs: 30000, cancellable: false, start(call, done) {
        executions.push(call);
        done({ outcome: "completed", content: "fixture deleted" });
    } });
    // The guidance stand-in hands no request anywhere: fleet.request ends
    // with the case's result.
    if (options.fleet) router.register("guidance", { commands: [], timeoutMs: 30000, cancellable: false, fleet: () => true,
        start(call, done) {
            executions.push(call);
            done(options.fleet);
        } });
    // The action approval case uses an inert executor, with no process.
    if (options.actionApproval) router.register("sandbox", { commands: ["bwrap"], timeoutMs: 30000,
        cancellable: false, start(call, done) {
            executions.push(call);
            done({ outcome: "completed", content: "fixture result" });
        } });
    // Accounts.choose has its own suite; this stand-in names a loopback row.
    const accounts = () => options.accounts ?? ({ secrets: null, choose: id => ({ kind: "accepted", account: { id, provider: "ollama", label: "local",
        source: { kind: "local", origin: "http://127.0.0.1:" + PORT }, model: "fixture-model" } }) });
    const configured = answer => runner.dispatch({ type: "snapshot", locked: false, engine: engine.engine(),
        configured: answer.kind === "ready" || answer.kind === "loading", settings: runner.state.settings });
    const dictation = Fixture.dictation(backend("ShellRequests.js"), Protocol, runnerClock);
    const tasks = options.tasks ? taskWorld(kit, runner, Session, faults) : null;
    voice = tasks?.voice ?? null;
    engine = kit.Engine.create({ session: Session, state: () => runner.state, audit, router, accounts,
        policy: () => ({ profile: "standard", cloudVision: "ask" }), fault: reason => faults.push(reason),
        captionLimit: options.captionLimit ?? Protocol.TRANSCRIPT_CHARS, dispatch: e => runner.dispatch(e), clock: runnerClock,
        directories: options.directories, configured, tasks: tasks?.port ?? null, request: dictation.send,
        ...(options.home === undefined ? {} : { home: options.home }),
        ...(options.log === undefined ? {} : { log: options.log }),
        ...(options.trace === undefined ? {} : { trace: options.trace }),
        ...(options.rejudge === undefined ? {} : { rejudge: options.rejudge }) });
    if (daemon !== null) daemon.engine = engine;
    ports.release = engine.release;
    const actionApproval = ports.approval;
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
        runner.dispatch({ type: "snapshot", locked: false, engine: engine.engine(),
            configured: answer.kind === "ready" || answer.kind === "loading", settings });
        return answer;
    };
    const configuration = configure({ mode: options.mode ?? "hold", sounds: options.sounds === true,
        microphone: "", speaker: "", brain: "fixture-account", fallbacks: options.fallbacks ?? [], dictation: options.dictation ?? "",
        ...options.settings });
    if (options.later !== true) assert.equal(configuration.kind, options.directories ? "loading" : "ready");
    runner.dispatch({ type: "indicator", shown: true });
    const rows = () => {
        const file = path.join(state, "audit/2026-10-01.jsonl");
        return fs.existsSync(file) ? fs.readFileSync(file, "utf8").trim().split("\n").map(line => JSON.parse(line)) : [];
    };
    return { Session, runnerNow: runnerClock.now, runner, router, audio, audioClock, engine, audit, faults, executions, held, partials, captions, rows, configure,
        state, workspace, server, advanceRunner, writes, timers, tasks, dictation, bridge: daemon?.bridge,
        s: () => runner.state,
        async close() {
            daemon?.bridge.close();
            daemon?.gate.close();
            tasks?.close();
            runner.close();
            engine.close();
            dictation.close();
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

// A Talk release after a hold: Session reads a release sooner than its
// TAP_MS as a tap, which keeps the microphone open, so the injected
// runner clock first passes that bound.
function release(w) {
    w.advanceRunner(w.Session.TAP_MS);
    w.runner.dispatch({ type: "talk-up" });
}

// One utterance through real capture: down, partials, up, final.
async function say(w, script, { waitPartial = true, over = () => false } = {}) {
    control.utterances.push(script);
    const before = w.server.requests.length;
    w.runner.dispatch({ type: "talk-down" });
    if (w.s().playback.kind === "feedback") await playOut(w);
    // An early final leaves collection; the case's own assertions judge it.
    const collecting = () => w.s().turn.kind === "collecting";
    await settled(() => w.s().capture.kind === "open" || (w.s().turn.kind !== "none" && !collecting()), over,
        "capture opens from real fixture PCM");
    if (waitPartial && script.partials.length)
        await settled(() => w.partials.at(-1) === script.partials.at(-1) || !collecting(), over, "partials reach Session");
    release(w);
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
// A harness program's side of the tool bridge: the shim's hello, then MCP
// through initialize and its notification, on the session's socket.
async function harnessProgram(launch) {
    const socket = net.createConnection({ path: launch.env.VGS_JARVIS_TOOLS_SOCKET });
    socket.setEncoding("utf8");
    socket.on("error", () => {});
    const lines = [];
    let tail = "";
    socket.on("data", chunk => {
        tail += chunk;
        for (let end; (end = tail.indexOf("\n")) >= 0; tail = tail.slice(end + 1)) lines.push(JSON.parse(tail.slice(0, end)));
    });
    const next = async what => {
        await until(() => lines.length !== 0, what);
        return lines.shift();
    };
    const send = message => socket.write(JSON.stringify(message) + "\n");
    send({ v: 1, type: "hello", token: launch.env.VGS_JARVIS_TOOLS_TOKEN });
    assert.deepEqual(await next("the bridge admits the program"), { v: 1, type: "ready" });
    send({ jsonrpc: "2.0", id: 0, method: "initialize",
        params: { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "fixture-harness", version: "0" } } });
    assert.equal((await next("the bridge answers initialize")).id, 0);
    send({ jsonrpc: "2.0", method: "notifications/initialized" });
    return { next, send, close: () => socket.destroy() };
}
async function requested(w, count, label, over = () => false) {
    await settled(() => w.server.requests.length >= count && w.server.requests[count - 1].body !== null, over, label);
    return w.server.requests[count - 1].body;
}
function quietTurn(w) {
    const s = w.s();
    return s.turn.kind === "none" && s.playback.kind === "idle" && s.approval.kind === "none"
        && s.action.kind === "none" && s.capture.kind === "closed";
}

function statusBrain(port, behavior) {
    const requests = [];
    const queue = Array.isArray(behavior) ? behavior.slice() : [behavior];
    const server = http.createServer((request, response) => {
        requests.push(request.url);
        request.resume();
        const behavior = queue.length > 1 ? queue.shift() : queue[0];
        const send = async () => {
            if (behavior.wait !== undefined) await behavior.wait;
            return true;
        };
        if (behavior.kind === "status") {
            void send().then(() => {
                response.writeHead(behavior.status, { "content-type": "application/json" });
                response.end("{}");
            });
        } else if (behavior.kind === "frames") {
            void send().then(() => {
                response.writeHead(200, { "content-type": "text/event-stream" });
                for (const frame of behavior.frames) response.write(Frames.encode(frame, "failover"));
                response.end();
            });
        } else if (behavior.kind === "stream-failed") {
            response.writeHead(200, { "content-type": "text/event-stream" });
            response.write("data: ");
            response.destroy();
        } else if (behavior.kind === "refusal") {
            response.writeHead(200, { "content-type": "text/event-stream" });
            response.write('data: {"choices":[{"index":0,"delta":{"refusal":"No."},"finish_reason":null}]}\n\n');
            response.write("data: [DONE]\n\n");
            response.end();
        } else if (behavior.kind === "content-filter") {
            response.writeHead(200, { "content-type": "text/event-stream" });
            response.write('data: {"choices":[{"index":0,"delta":{},"finish_reason":"content_filter"}]}\n\n');
            response.write("data: [DONE]\n\n");
            response.end();
        } else throw new Error("statusBrain behavior");
    });
    return { requests, ready: new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(port, "127.0.0.1", resolve);
    }), close: () => new Promise(resolve => server.close(resolve)) };
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
// A brain turn's acknowledgement plays first and Session holds the reply
// behind it: play the line out until the reply's own playback starts.
async function replyPlays(w, label) {
    await wait(() => {
        if (w.s().playback.kind === "playing") return true;
        w.audioClock.advance(20);
        return false;
    }, label, OBSERVE_MS, 1);
}
// Each poll advances the injected playback clock one node period. Child pipes
// and the stand-in player's exit cross real I/O, so the poll is short.
async function playOut(w, over = () => false) {
    let idle = false;
    await wait(() => {
        if ((idle = w.s().playback.kind === "idle") || over()) return true;
        w.audioClock.advance(20);
        return false;
    }, "playback completes", OBSERVE_MS, 1);
    assert.ok(idle, "playback completes");
}
const user = body => body.messages.filter(message => message.role === "user").map(message => message.content);
const assistantCaptions = w => w.captions.filter(row => row[1] === "assistant");

// The shipped daemon's stdout as ROWS. Its dictation requests are answered
// as Service.qml answers them, with TEXT as the recording's words.
function readDaemon(child, rows, send, text) {
    let tail = "";
    child.stdout.on("data", data => {
        tail += data;
        const lines = tail.split("\n");
        tail = lines.pop();
        for (const row of lines.filter(Boolean).map(JSON.parse)) {
            rows.push(row);
            if (row.type !== "request") continue;
            assert.equal(row.kind.startsWith("dictation."), true, "the daemon asks the service only for its recording");
            send({ type: "reply", gen: row.gen, revision: row.revision, id: row.id, kind: row.kind, answer: "ok",
                data: row.kind === "dictation.stop" ? { text } : null });
        }
    });
}

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
    const scripts = { start: scenario, utterances: Array.from({ length: 6 }, () => ({ speech: true })),
        speech: Array.from({ length: 20 }, () => ({ rate: 16000, samples: 4800 })) };
    fs.writeFileSync(path.join(local, "scenario.json"), JSON.stringify(scripts));
    if (scenario === "held")
        assert.equal(cp.spawnSync("python3", ["-I", "-c", "import os,sys;os.mkfifo(sys.argv[1])", path.join(local, "ready-gate")]).status, 0);
    fs.writeFileSync(path.join(state, "local-ready.json"), JSON.stringify({ tier: "small", data: fs.realpathSync(local) }));
    const logs = () => fs.existsSync(path.join(local, "log.jsonl")) ? fs.readFileSync(path.join(local, "log.jsonl"), "utf8")
        .trim().split("\n").filter(Boolean).map(JSON.parse) : [];
    const starts = () => logs().filter(row => row.start).map(row => row.start);
    const alive = pid => { try { process.kill(pid, 0); return true; } catch (error) { if (error.code === "ESRCH") return false; throw error; } };
    const w = rig(kit, server, { directories: { state, data: root, runtime: root } });
    // The local row's words come from the core's recording.
    w.dictation.text = "Fixture request.";
    try {
        assert.equal(w.s().gate.kind, "up");
        await until(() => starts().length === 1, "sidecar starts before any conversation");
        if (scenario === "held") {
            w.runner.dispatch({ type: "snapshot", locked: null, engine: w.engine.engine(), configured: true, settings: w.s().settings });
            w.runner.dispatch({ type: "talk-down" });
            assert.equal(w.s().gate.reason, "lock-unknown");
            assert.equal(w.s().capture.kind, "closed");
            assert.equal(w.s().conversation.kind, "ended");
            w.runner.dispatch({ type: "snapshot", locked: false, engine: w.engine.engine(), configured: true, settings: w.s().settings });
            w.runner.dispatch({ type: "talk-down" });
            await until(() => w.s().capture.kind === "open", "bounded loading capture opens");
            release(w);
            await until(() => w.s().capture.kind === "closed", "bounded loading capture releases");
            assert.equal(w.s().turn.kind, "collecting");
            const before = server.requests.length;
            w.advanceRunner(60000);
            await settled(() => w.s().fault.kind === "error",
                () => w.s().fault.kind === "none",
                "existing loading deadline is visible");
            assert.equal(["speech=collect-timeout", "speech=local-ready-timeout"].includes(w.s().fault.reason), true);
            assert.equal(w.s().conversation.kind, "ended");
            assert.equal(w.s().capture.kind, "closed");
            await until(() => !alive(starts()[0].pid), "deadline reaps the failed starting child");
            assert.equal(w.configure(w.s().settings).cause, "speech=local-ready-timeout", "ready timeout becomes a setup refusal");
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
        assert.deepEqual(w.engine.voices().map(voice => voice.value), ["ljspeech"], "the ready small tier offers its Piper voice");
        const pid = starts()[0].pid;
        for (const ending of [firstEnding, "brain-failed", "stop"]) {
            const before = await say(w, utterance("Fixture request."),
                { over: () => starts().length === 1 && !alive(pid) && w.s().gate.kind === "down" });
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
        await requested(w, before + 1, "request after sidecar fault",
            () => w.s().fault.kind === "error");
        assert.equal(starts().length, 2);
        assert.notEqual(starts()[1].pid, pid);
        // The cloned voice setting ends the conversation and replaces the
        // sidecar with one handed the recording; an unchanged one keeps it.
        const gen = w.s().gen;
        w.configure({ ...w.s().settings, clonedVoice: true });
        assert.deepEqual([w.s().conversation.kind, w.s().gen > gen], ["ended", true], "the setting ends the conversation");
        await turn();
        await until(() => starts().length === 3, "the setting restarts the sidecar");
        assert.deepEqual(starts()[2].argv.slice(-2), ["--reference", path.join(state, "voice-reference.wav")]);
        await turn();
        await until(() => !alive(starts()[1].pid), "the replaced sidecar ends");
        w.configure(w.s().settings);
        assert.equal(starts().length, 3, "an unchanged setting keeps the sidecar");
        // A clone setup that publishes under an open conversation replaces
        // the sidecar only once that conversation ends.
        await until(() => w.s().conversation.kind === "ended" && w.configure(w.s().settings).kind === "ready", "the cloned sidecar is ready");
        const asked = await say(w, utterance("Fixture request."));
        await requested(w, asked + 1, "request beside the cloned sidecar");
        const marker = path.join(state, "clone-ready.json");
        fs.writeFileSync(marker + ".new", "{}");
        fs.renameSync(marker + ".new", marker);
        // A replacement would answer loading at once; the open one keeps its ready sidecar.
        assert.deepEqual([w.configure(w.s().settings).kind, w.s().conversation.kind], ["ready", "active"], "the open conversation keeps its sidecar");
        await turn();
        assert.equal(starts().length, 3, "no sidecar starts under the open conversation");
        w.runner.dispatch({ type: "stop" });
        await until(() => starts().length === 4, "the conversation's end replaces the sidecar");
        assert.deepEqual(starts()[3].argv.slice(-2), ["--reference", path.join(state, "voice-reference.wav")]);
        w.configure({ ...w.s().settings, clonedVoice: false });
        await until(() => starts().length === 5, "turning it off restarts the sidecar");
        assert.equal(starts()[4].argv.includes("--reference"), false);
        fs.rmSync(marker);
        w.runner.dispatch({ type: "stop" });
        // A tier whose marker is gone offers no voices, and the setting stays.
        fs.rmSync(path.join(state, "local-ready.json"));
        w.configure({ ...w.s().settings, voice: "ljspeech" });
        assert.deepEqual([w.engine.voices(), w.s().settings.voice], [[], "ljspeech"]);
    } finally {
        await w.close();
        // A control can leave a replaced sidecar running; its handle would
        // keep this world alive past its bound.
        await turn();
        try { await until(() => starts().every(row => !alive(row.pid)), "daemon teardown releases speech child"); }
        finally {
            for (const row of starts()) if (alive(row.pid)) process.kill(row.pid, "SIGKILL");
            server.closeAll();
        }
    }
}

// A local voice setup run over a live local conversation with the stand-in
// sidecar (ChainedEngine localSetup): its start ends the conversation and
// answers only once the sidecar is reaped, a judge during the run starts
// none, and its end starts the sidecar on the publication the run left.
async function localSetupRun(server, edits = []) {
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
    const root = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "local-setup-"));
    const local = path.join(root, "local"), state = path.join(root, "state");
    fs.mkdirSync(path.join(local, "venv/bin"), { recursive: true });
    fs.mkdirSync(state);
    fs.copyFileSync(path.join(__dirname, "fixtures/jarvis-local-speech/standin.py"), path.join(local, "venv/bin/python"));
    fs.chmodSync(path.join(local, "venv/bin/python"), 0o700);
    fs.writeFileSync(path.join(local, "scenario.json"), JSON.stringify({ start: "ready",
        utterances: Array.from({ length: 2 }, () => ({ speech: true })), speech: [] }));
    const marker = path.join(state, "local-ready.json");
    fs.writeFileSync(marker, JSON.stringify({ tier: "small", data: fs.realpathSync(local) }));
    const logs = () => fs.existsSync(path.join(local, "log.jsonl")) ? fs.readFileSync(path.join(local, "log.jsonl"), "utf8")
        .trim().split("\n").filter(Boolean).map(JSON.parse) : [];
    const starts = () => logs().filter(row => row.start).map(row => row.start);
    const alive = pid => { try { process.kill(pid, 0); return true; } catch (error) { if (error.code === "ESRCH") return false; throw error; } };
    const w = rig(kit, server, { directories: { state, data: root, runtime: root }, rejudge: () => w.configure(w.s().settings) });
    w.dictation.text = "Fixture request.";
    try {
        await until(() => starts().length === 1, "sidecar starts before any conversation");
        const first = starts()[0].pid;
        // Whether setup-local could take the lock alone now.
        const lockFree = () => cp.spawnSync("python3", ["-I", "-c", "import fcntl,sys\nfcntl.flock(open(sys.argv[1], 'a'), fcntl.LOCK_EX | fcntl.LOCK_NB)",
            path.join(state, "local-setup.lock")]).status === 0;
        assert.equal(lockFree(), false, "the sidecar holds the setup lock");
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().conversation.kind === "active" && w.s().capture.kind === "open", "a live local conversation");
        const answer = w.engine.localSetup(true).then(() => alive(first));
        assert.deepEqual([w.s().gate.kind, w.s().conversation.kind], ["down", "ended"], "the start ends the live conversation");
        assert.equal(w.engine.localSetup(true) instanceof Promise, true);
        assert.equal(await answer, false, "the answer follows the sidecar's exit");
        assert.equal(lockFree(), true, "the answer follows the lock's release");
        assert.deepEqual(w.configure(w.s().settings).causes, ["speech=local-setting-up"]);
        w.runner.dispatch({ type: "talk-down" });
        assert.equal(w.s().conversation.kind, "ended", "Talk waits for the setup");
        // setup-local publishes the replacement with rename.
        const replacement = path.join(state, ".local-ready-replaced");
        fs.writeFileSync(replacement, JSON.stringify({ tier: "medium", data: fs.realpathSync(local) }));
        fs.renameSync(replacement, marker);
        assert.deepEqual(w.configure(w.s().settings).causes, ["speech=local-setting-up"]);
        w.engine.localSetup(false);
        assert.equal(w.s().gate.kind, "up", "the end judges again");
        // A sidecar a judge started during the run was spawned before the
        // end's, so it has logged its start once the end's one is ready.
        await until(() => w.engine.checkReady(), "the end starts the sidecar on the new publication");
        assert.equal(starts().length, 2, "no sidecar starts while the setup runs");
    } finally {
        await w.close();
        await turn();
        try { await until(() => starts().every(row => !alive(row.pid)), "daemon teardown releases speech child"); }
        finally {
            for (const row of starts()) if (alive(row.pid)) process.kill(row.pid, "SIGKILL");
            server.closeAll();
        }
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
    fs.writeFileSync(path.join(local, "scenario.json"), JSON.stringify({ start: "held", utterances: [{ speech: true }],
        checks: [ending === "check-ready" ? { afterFrames: 1 } : {}] }));
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
    let childDone = false;
    closed.then(() => { childDone = true; });
    const rows = [], logs = () => fs.existsSync(path.join(local, "log.jsonl"))
        ? fs.readFileSync(path.join(local, "log.jsonl"), "utf8").trim().split("\n").filter(Boolean).map(JSON.parse) : [];
    const starts = () => logs().filter(row => row.start);
    const states = () => rows.filter(row => row.type === "state");
    const s = () => states().at(-1)?.state;
    const status = () => rows.filter(row => row.type === "status").at(-1);
    let error = "";
    readDaemon(child, rows, fields => send(fields), "Captured once.");
    child.stderr.on("data", data => { error += data; });
    child.stdin.on("error", e => { if (e.code !== "EPIPE") throw e; });
    const send = fields => child.stdin.write(JSON.stringify({ v: 1, gen: s()?.gen ?? 0, revision: "a".repeat(64), ...fields }) + "\n");
    const hello = (locked = false) => send({ type: "hello", locked,
        settings: { home: "", sounds: false, mode: "hold", microphone: "", speaker: "", brain: ending === "brain" || ending.startsWith("check-") ? "" : "fixture-account", model: "", effort: "", fallbacks: [], taskTerminal: "auto", voiceProvider: "local", voiceAccount: "", voice: "", clonedVoice: false, dictation: "", cloudVision: "ask", privateWindows: "bitwarden" },
        keys: { talk: null, mute: null, stop: null, confirm: null, console: null }, directories: { state, data: root, runtime: process.env.XDG_RUNTIME_DIR } });
    const intent = name => send({ type: "intent", intent: name });
    const before = server.requests.length;
    let tryPassed = false;
    try {
        hello(ending === "locked");
        await settled(() => status() && s(), () => childDone, "shipped daemon publishes admission: " + error);
        if (ending.startsWith("check-")) {
            await until(() => starts().length === 1, "the setup check has one local speech owner");
            fs.writeFileSync(path.join(local, "ready-gate"), "R");
            await until(() => s().check.kind === "ready", "local voice can be checked without a brain");
            assert.equal(s().gate.kind, "down");
            if (ending === "check-silent") fs.writeFileSync(path.join(process.env.HOME, "capture-silent"), "");
            intent("voice-check");
            await until(() => s().check.kind === "waiting", "the check waits for the indicator");
            assert.equal(s().capture.kind, "closed");
            send({ type: "indicator", shown: true });
            await until(() => s().check.kind === "recording", "selected stand-in microphone opens");
            await until(() => s().check.kind === "done", "the microphone check finishes", OBSERVE_MS);
            assert.equal(s().check.result, ending.slice(6));
            await until(() => s().capture.kind === "closed", "the check's owned recorder exits");
            assert.deepEqual([s().conversation.kind, s().turn.kind, s().brain.kind, server.requests.length],
                ["ended", "none", "closed", before]);
            assert.equal(starts().length, 1);
            assert.equal(logs().some(row => row.listen), false, "check audio never reaches transcription");
            tryPassed = true;
            return;
        }
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
            if (ending === "missing") assert.equal(starts().length, 0);
            tryPassed = true;
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
            tryPassed = true;
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
        // The shipped daemon's runner reads the real clock: a release sooner
        // than Session's TAP_MS would be a tap, which keeps capturing.
        await new Promise(resolve => setTimeout(resolve, load(path.join(kit.folder, "Session.js")).TAP_MS));
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
            tryPassed = true;
            return;
        }
        if (ending === "lease") {
            child.stdin.end();
            const [code, signal] = await closed;
            assert.equal(code, 0, error);
            assert.equal(signal, null);
            assert.equal(server.requests.length, before, "lease ends without replaying the held utterance");
            tryPassed = true;
            return;
        }
        if (ending === "stop") intent("stop");
        else if (ending === "mute") intent("mute");
        else if (ending === "lock") hello(true);
        if (ending !== "ready") await settled(() => s().conversation.kind === "ended",
            () => childDone, "loading cancellation ends its utterance");
        fs.writeFileSync(path.join(local, "ready-gate"), "R");
        await settled(() => status().causes.length === 0,
            () => starts().length > 1, "actual ready clears loading status");
        if (ending === "ready") {
            const body = await requested({ server }, before + 1, "one held utterance reaches the real wire brain",
                () => starts().length > 1);
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
            await settled(() => logs().some(row => row.abort),
                () => server.requests.length > before,
                "cancelled loading utterance abort reaches the same child");
            assert.equal(s().conversation.kind, "ended");
            assert.equal(s().turn.kind, "none");
            assert.equal(server.requests.length, before, "ready does not replay cancelled Talk");
        }
        assert.equal(starts().length, 1, "loading Talk starts no second child");
        tryPassed = true;
    } finally {
        child.stdin.end();
        if (!tryPassed && !childDone) child.kill("SIGKILL");
        const timer = setTimeout(() => child.kill("SIGKILL"), OBSERVE_MS);
        try {
            const [code, signal] = await closed;
            if (tryPassed) {
                assert.equal(signal, null);
                assert.equal(code, 0, error);
            }
        }
        finally {
            clearTimeout(timer); server.closeAll();
            for (const file of ["no-devices", "capture-silent"]) fs.rmSync(path.join(process.env.HOME, file), { force: true });
        }
    }
}

// Always mode through the shipped daemon, Session, Audio and local adapter
// with the stand-in sidecar: the wake capture reaches only the sidecar and
// no brain, the word opens one utterance, the reply plays, and the next
// wake capture follows in the same conversation. "refused" selects the Realtime voice
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
        utterances: [{ turnEnd: true }], speech: [{ rate: 16000, samples: 4800 }, { rate: 16000, samples: 4800 }] }));
    if (ending !== "unset") fs.writeFileSync(path.join(state, "local-ready.json"), JSON.stringify({ tier: "small", data: fs.realpathSync(local) }));
    const preload = path.join(root, "accounts.js");
    fs.writeFileSync(preload, 'require(' + JSON.stringify(path.join(kit.folder, "backend/Core.js")) + ').use(' + JSON.stringify(tree) + ');\n' +
        'require(' + JSON.stringify(path.join(kit.folder, "backend/Accounts.js")) + ').Accounts.prototype.choose = id => ({ kind: "accepted", account: { id, provider: "ollama", label: "local", source: { kind: "local", origin: "http://127.0.0.1:11434" }, model: "fixture-model" } });');
    const child = cp.spawn("node", ["--require", preload, path.join(kit.folder, "backend/jarvisd.js"), "--tree", tree], {
        env: { PATH: process.env.PATH, HOME: process.env.HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR }, stdio: ["pipe", "pipe", "pipe"] });
    const closed = once(child, "close");
    let childDone = false;
    closed.then(() => { childDone = true; });
    const rows = [], logs = () => fs.existsSync(path.join(local, "log.jsonl"))
        ? fs.readFileSync(path.join(local, "log.jsonl"), "utf8").trim().split("\n").filter(Boolean).map(JSON.parse) : [];
    const states = () => rows.filter(row => row.type === "state");
    const s = () => states().at(-1)?.state;
    const status = () => rows.filter(row => row.type === "status").at(-1);
    let error = "";
    readDaemon(child, rows, fields => send(fields), "Woken request.");
    child.stderr.on("data", data => { error += data; });
    child.stdin.on("error", e => { if (e.code !== "EPIPE") throw e; });
    const send = fields => child.stdin.write(JSON.stringify({ v: 1, gen: s()?.gen ?? 0, revision: "a".repeat(64), ...fields }) + "\n");
    const hello = () => send({ type: "hello", locked: false,
        settings: { home: "", sounds: false, mode: "always", microphone: "", speaker: "", brain: "fixture-account", model: "", effort: "", fallbacks: [], taskTerminal: "auto",
            voiceProvider: ending === "refused" ? "realtime" : "local", voiceAccount: "", voice: "", clonedVoice: false, dictation: "", cloudVision: "ask", privateWindows: "bitwarden" },
        keys: { talk: null, mute: null, stop: null, confirm: null, console: null }, directories: { state, data: root, runtime: process.env.XDG_RUNTIME_DIR } });
    hello();
    const before = server.requests.length;
    try {
        await settled(() => status() && s(), () => childDone, "shipped daemon publishes admission: " + error);
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
        await until(() => s().conversation.kind === "active",
            "the word starts a conversation: " + JSON.stringify(logs().slice(-3)));
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

    const failoverAccounts = (primary = "llama-server") => ({ secrets: null, choose(id) {
        if (id === "refused") return { kind: "refused", cause: "signed-out" };
        if (id === "fixture-account") return { kind: "accepted", account: { id, provider: primary, label: "primary",
            source: { kind: "local", origin: "http://127.0.0.1:8080" }, model: "primary-model" } };
        return { kind: "accepted", account: { id, provider: "ollama", label: "backup",
            source: { kind: "local", origin: "http://127.0.0.1:" + PORT }, model: "backup-model" } };
    } });

    for (const [name, behavior] of [
        ["wire-401", { kind: "status", status: 401 }],
        ["wire-402", { kind: "status", status: 402 }],
        ["wire-403", { kind: "status", status: 403 }],
        ["wire-429", { kind: "status", status: 429 }],
        ["wire-500", { kind: "status", status: 500 }],
        ["wire-503", { kind: "status", status: 503 }],
        ["wire-504", { kind: "status", status: 504 }],
        ["wire-529", { kind: "status", status: 529 }]
    ]) await run("failover-" + name, async w => {
        const primary = statusBrain(8080, behavior);
        await primary.ready;
        try {
            const before = await say(w, utterance("Try the backup."));
            server.replies.push(text("Backup answered."));
            const body = await requested(w, before + 1, "backup receives the refused request after " + name);
            assert.deepEqual(user(body), ["Try the backup."]);
            await until(() => w.s().turn.kind === "none", "backup answer finishes");
            await playOut(w);
            await until(() => control.spoken.length >= 2, "failover line and backup answer are spoken");
            const line = control.spoken.find(sentence => sentence.includes("not answering"));
            assert.equal(line, "llama-server primary-model is not answering, so I am continuing on Ollama backup-model. It has not heard what we said before.");
            assert.equal(primary.requests.length, 1, "primary was opened once");
            assert.equal(w.s().fault.kind, "none");
        } finally { await primary.close(); }
    }, { accounts: failoverAccounts(), fallbacks: [{ name: "backup", brain: "backup", model: "backup-model" }] });

    for (const [name, behavior] of [
        ["model-refusal", { kind: "refusal" }],
        ["content-filter", { kind: "content-filter" }]
    ]) await run("failover-control-" + name, async w => {
        const primary = statusBrain(8080, behavior);
        await primary.ready;
        try {
            const before = await say(w, utterance("Do not switch."));
            await until(() => w.s().fault.kind === "error", "non-failover refusal ends the turn");
            assert.equal(server.requests.length, before, "backup was not opened");
        } finally { await primary.close(); }
    }, { accounts: failoverAccounts(), fallbacks: [{ name: "backup", brain: "backup", model: "backup-model" }] });

    await run("failover-skips-refused-entry", async w => {
        const primary = statusBrain(8080, [{ kind: "status", status: 403 }, { kind: "status", status: 403 }]);
        await primary.ready;
        try {
            const before = await say(w, utterance("Skip bad backup."));
            server.replies.push(text("Usable backup."));
            const body = await requested(w, before + 1, "usable backup receives request");
            assert.deepEqual(user(body), ["Skip bad backup."]);
            await until(() => w.s().turn.kind === "none", "usable backup answer finishes");
            await playOut(w);
            const line = control.spoken.find(sentence => sentence.includes("not answering"));
            assert.equal(line, "llama-server primary-model is not answering, so I am continuing on Ollama backup-model. It has not heard what we said before.");
        } finally { await primary.close(); }
    }, { accounts: failoverAccounts(), fallbacks: [
        { name: "refused", brain: "refused", model: "nope" },
        { name: "backup", brain: "backup", model: "backup-model" }
    ] });

    await run("failover-list-used-up", async w => {
        const primary = statusBrain(8080, { kind: "status", status: 403 });
        await primary.ready;
        try {
            await say(w, utterance("No backup."));
            await until(() => w.s().fault.kind === "error", "last failover cause ends the turn");
            assert.equal(w.s().fault.reason, "brain=forbidden status=403");
        } finally { await primary.close(); }
    }, { accounts: failoverAccounts(), fallbacks: [] });

    await run("failover-stays-on-backup", async w => {
        const primary = statusBrain(8080, { kind: "status", status: 403 });
        await primary.ready;
        try {
            let before = await say(w, utterance("First."));
            server.replies.push(text("Backup first."));
            await requested(w, before + 1, "first backup request");
            await until(() => w.s().turn.kind === "none", "first turn ends");
            await playOut(w);
            before = await say(w, utterance("Second."));
            server.replies.push(text("Backup second."));
            const body = await requested(w, before + 1, "second turn stays on backup");
            assert.deepEqual(user(body).slice(-1), ["Second."]);
            await until(() => w.s().turn.kind === "none", "second turn ends");
            await playOut(w);
            assert.equal(primary.requests.length, 1, "primary is not retried in the same conversation");
            w.runner.dispatch({ type: "stop" });
            await until(() => w.s().conversation.kind === "ended", "conversation ends");
            before = await say(w, utterance("New."));
            server.replies.push(text("Backup new."));
            await requested(w, before + 1, "new conversation starts at primary then backs up");
            assert.equal(primary.requests.length, 2);
        } finally { await primary.close(); }
    }, { accounts: failoverAccounts(), fallbacks: [{ name: "backup", brain: "backup", model: "backup-model" }] });

    await run("failover-after-tool-asks-repeat", async w => {
        const held = gate();
        const primary = statusBrain(8080, { kind: "status", status: 403, wait: held.wait });
        await primary.ready;
        const first = await say(w, utterance("Use the tool."));
        try {
            await until(() => primary.requests.length === 1, "primary request starts");
            const routed = w.router.route({ kind: "tool-call", id: "wire-call", tool: "windows.focus", arguments: { window: "0x1f" } },
                { gen: w.s().gen, op: w.s().turn.op });
            assert.notEqual(routed.kind, "refuse", "tool route is accepted");
            held.open();
            await until(() => w.s().turn.kind === "none", "tool failover line ends the turn");
            await playOut(w);
            await until(() => control.spoken.length >= 1, "repeat line is spoken");
            const line = control.spoken.find(sentence => sentence.includes("Please say"));
            assert.equal(line, "llama-server primary-model is not answering, so I am continuing on Ollama backup-model. It has not heard what we said before. Please say your request again.");
            assert.equal(server.requests.length, first, "request is not resent after a tool ran");
        } finally { await primary.close(); }
    }, { accounts: failoverAccounts(), fallbacks: [{ name: "backup", brain: "backup", model: "backup-model" }] });

    for (const [name, request, options] of [
        ["failover-after-bridge-call-asks-repeat", { kind: "tool-call", id: "bridge-call", tool: "windows.focus", arguments: { window: "0x1f" } }, {}],
        ["failover-after-harness-approval-asks-repeat", { kind: "approval", id: "harness-approval", tool: "harness.files",
            arguments: { write: [path.join(process.env.HOME, "workspace-file")], move: [], remove: [], diff: "fixture" } }, { actionApproval: true }]
    ]) await run(name, async w => {
        const held = gate();
        const primary = statusBrain(8080, { kind: "status", status: 429, wait: held.wait });
        await primary.ready;
        try {
            const before = await say(w, utterance("Run once."));
            await until(() => primary.requests.length === 1, "primary request starts");
            const routed = w.router.route(request, { gen: w.s().gen, op: w.s().turn.op });
            assert.notEqual(routed.kind, "refuse", "action route is accepted: " + JSON.stringify(routed));
            held.open();
            await until(() => w.s().turn.kind === "none", "failover repeat line ends the turn");
            await playOut(w);
            const line = control.spoken.find(sentence => sentence.includes("Please say"));
            assert.equal(line, "llama-server primary-model is not answering, so I am continuing on Ollama backup-model. It has not heard what we said before. Please say your request again.");
            assert.equal(server.requests.length, before, "backup does not receive a request after a routed action");
        } finally { await primary.close(); }
    }, { accounts: failoverAccounts(), fallbacks: [{ name: "backup", brain: "backup", model: "backup-model" }], ...options });

    await run("feedback-start", async w => {
        w.runner.dispatch({ type: "talk-down" });
        const owner = w.s().playback;
        assert.equal(owner.kind, "feedback");
        await until(() => w.writes.length !== 0, "the start sound reaches the stand-in player");
        assert.equal(w.s().capture.kind, "closed", "no microphone overlaps the start sound");
        assert.equal(control.frames, 0);
        assert.equal(w.writes.some(write => write.pcm.some(byte => byte !== 0)), true, "the start sound is audible PCM");
        release(w);
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
            w.advanceRunner(1);
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
        await until(() => control.spoken.length !== 0, "the acknowledgement reaches speech");
        assert.ok(control.spoken.includes("Let me check."), "the acknowledgement speaks before the working cue");
        await until(() => w.s().capture.kind === "closed", "capture closes before the acknowledgement playback drains");
        await playOut(w);
        const startWrites = w.writes.length;
        w.advanceRunner(1199);
        assert.equal(w.s().playback.kind, "idle", "working feedback waits for its interval after the acknowledgement");
        w.advanceRunner(1200);
        assert.equal(w.s().playback.cue, "working");
        await until(() => w.writes.length > startWrites, "working PCM reaches the stand-in player");
        assert.equal(w.writes.slice(startWrites).some(write => write.pcm.some(byte => byte !== 0)), true);
        w.advanceRunner(1200);
        await advance(w, 6);
        assert.equal(w.audio.playback.received, 2880, "only one working cue enters the stream");
        server.replies.push(text("Yes I am here."));
        await until(() => w.s().turn.kind === "none", "the brain finishes independently of playback");
        await playOut(w);
        assert.equal(w.audio.lastPlayback.writtenFrames, 2880 + 4 * Fixture.WORD_FRAMES);
        assert.equal(w.audio.lastPlayback.heardText, "Yes I am", "only aligned assistant words enter heard accounting");
        assert.deepEqual(control.spoken, ["Let me check.", "Yes I am here."]);
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

    for (const [kind, reply] of [["text", held => text("A sentence for speech. ", { wait: held.wait })],
        ["tool", () => calls({ id: "focus", name: "windows_focus", arguments: { window: "0x1f" } })]]) {
        await run("feedback-suppressed-" + kind, async w => {
            const first = await say(w, utterance("Hello."));
            await requested(w, first + 1, "the request reaches the server");
            const held = gate();
            // The injected clock advances only after the real stream adapter
            // has consumed the released sentence or the tool event.
            server.replies.push(reply(held));
            await settled(() => ![...w.timers.values()].some(timer => timer.at === w.runnerNow() + 1200),
                () => kind === "tool" ? w.executions.length > 0 : withoutAcks(control.spoken).length > 0,
                "substantive provider output retires the feedback timer");
            w.advanceRunner(1200);
            assert.notEqual(w.s().playback.cue, "working", "substantive " + kind + " suppresses the working cue");
            held.open();
            w.runner.dispatch({ type: "stop" });
        }, { sounds: true, holdTools: kind === "tool" });
    }

    // Text that stays silent, as a brain writes before a tool call, is no
    // speech: the working sound still covers the wait. The trace shows the
    // engine has read the text, since it is written before Speakable reads.
    const silenced = path.join(fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "silenced-")), "brain.jsonl");
    await run("feedback-silenced-text", async w => {
        const first = await say(w, utterance("Hello."));
        await requested(w, first + 1, "the request reaches the server");
        const held = gate();
        server.replies.push(text('<tool_call>{"name": "windows_focus"}</tool_call> Calling `mcp__vgs-jarvis__windows_focus` now. ', { wait: held.wait }));
        await until(() => fs.readFileSync(silenced, "utf8").includes("Calling"), "the engine reads the silenced text");
        assert.ok([...w.timers.values()].some(timer => timer.at === w.runnerNow() + 1200), "silenced text leaves the working sound due");
        w.advanceRunner(1200);
        assert.deepEqual([w.s().playback.kind, w.s().playback.cue], ["feedback", "line"], "the acknowledgement line covers the wait");
        assert.deepEqual(control.spoken, ["On it."], "and none of the silenced text is spoken");
        held.open();
        w.runner.dispatch({ type: "stop" });
    }, { sounds: true, trace: { marker: "1", file: silenced } });

    await run("feedback-disable-working", async w => {
        const first = await say(w, utterance("Hello."));
        await requested(w, first + 1, "the request starts");
        await until(() => control.spoken.length !== 0, "the acknowledgement reaches speech");
        await playOut(w);
        w.advanceRunner(1200);
        await until(() => w.s().playback.cue === "working" && w.audio.playback?.kind === "feeding", "the working cue starts");
        w.configure({ ...w.s().settings, sounds: false });
        await until(() => w.s().playback.kind === "idle", "disabling feedback flushes the working cue");
        server.replies.push(text("Hello there."));
        await until(() => w.s().turn.kind === "none", "the live reply still completes");
        await playOut(w);
        assert.deepEqual(control.spoken, ["On it.", "Hello there."]);
        assert.equal(w.audio.lastPlayback.heardText, "Hello");
        assert.deepEqual(w.faults, []);
        assert.equal(w.s().fault.kind, "none");
    }, { sounds: true });

    await run("feedback-delayed-flush", async w => {
        const first = await say(w, utterance("Hello."));
        await requested(w, first + 1, "the request starts");
        await until(() => control.spoken.length !== 0, "the acknowledgement speaks");
        await playOut(w);
        w.advanceRunner(1200);
        await until(() => w.s().playback.cue === "working" && w.audio.playback?.received === 2880, "the working cue enters Audio");
        const flush = w.runner.ports.playback.flush;
        let acknowledge = null;
        w.runner.ports.playback.flush = (e, done) => flush(e, report => { acknowledge = () => done(report); });
        w.configure({ ...w.s().settings, sounds: false });
        await until(() => acknowledge !== null, "Audio closes the old player before its held acknowledgment");
        assert.equal(w.audio.playback, null);
        const writes = w.writes.length;
        server.replies.push(text("Hello there."));
        await until(() => w.s().turn.kind === "none", "the brain finishes before flush acknowledgment");
        assert.deepEqual(control.spoken, ["On it.", "Hello there."]);
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
        await until(() => control.spoken.length !== 0, "the acknowledgement speaks");
        await playOut(w);
        w.advanceRunner(1200);
        await until(() => w.s().playback.cue === "working" && w.audio.playback?.received === 2880, "working feedback enters Audio");
        const oldSource = w.audio.playbackFeed;
        server.replies.push(calls(purpose === "action"
            ? { id: "call_action", name: "shell_argv", arguments: { argv: ["true"], cwd: w.workspace, network: false } }
            : { id: "call_release", name: "clipboard_read", arguments: {} }));
        await until(() => w.s().approval.kind === "held", "approval follows the working cue");
        const h = w.s().approval;
        assert.equal(h.purpose, purpose);
        assert.equal(h.physical, false);
        w.runner.dispatch({ type: "shown", gen: h.gen, op: h.op, id: h.id });
        await settled(() => w.s().playback.kind === "idle",
            () => w.s().approval.kind === "held" && w.s().playback.kind === "feedback" && w.s().playback.cue === "working",
            "the approval releases cue playback");
        assert.equal(w.audio.playback, null, "Audio released the old player");
        assert.equal(oldSource.destroyed, true, "the cue-only speech stream is released");
        w.advanceRunner(1100);
        control.utterances.push(utterance("Yes."));
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "Talk admits the voice answer after flush");
        assert.equal(w.s().turn.kind, "thinking");
        release(w);
        await requested(w, first + 2, "voice approval continues the same brain turn");
        const writes = w.writes.length;
        server.replies.push(text("Done."));
        await until(() => w.s().turn.kind === "none", "the approved reply completes");
        await playOut(w);
        assert.deepEqual(control.spoken, ["Let me check.", "Done."]);
        assert.ok(w.writes.slice(writes).some(write => write.pcm.includes(0x11)), "later speech acquires a fresh player");
        assert.equal(w.s().approval.kind, "none");
        assert.deepEqual(w.faults, []);
        await say(w, utterance("Another turn."));
        const body = await requested(w, first + 3, "the next request follows the completed approved reply");
        assert.equal(user(body).at(-1), "Another turn.", "approval line teardown adds no interrupted speech context");
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

    await run("spoken-lines", async w => {
        const firstHold = gate(), secondHold = gate();
        const first = await say(w, utterance("Check the Fidelity pages for my balance."));
        server.replies.push(text("<step>Reading the Fidelity pages</step>", { wait: firstHold.wait },
            "<step>Searching records</step>", { wait: secondHold.wait }, "The balance is ready."));
        await requested(w, first + 1, "the long request reaches the brain");
        await settled(() => control.spoken.includes("Checking the Fidelity pages."),
            () => w.s().turn.kind === "thinking" && w.s().playback.kind === "idle",
            "the acknowledgement speaks");
        assert.deepEqual([w.s().playback.kind, w.s().playback.cue], ["feedback", "line"],
            "a spoken line closes capture without changing the thinking phase first");
        assert.equal(w.s().turn.kind, "thinking");
        await playOut(w);
        w.advanceRunner(3999);
        assert.equal(control.spoken.includes("Reading the Fidelity pages"), false, "a short request has no progress line");
        w.advanceRunner(1);
        await settled(() => control.spoken.includes("Reading the Fidelity pages"),
            () => w.s().turn.kind === "thinking" && w.s().playback.kind === "idle",
            "the threshold speaks the latest step");
        await playOut(w);
        firstHold.open();
        await until(() => control.spoken.includes("Searching records"), "a later step after the threshold speaks at once");
        secondHold.open();
        await until(() => w.s().turn.kind === "none", "the long reply completes");
        await playOut(w);
        assert.deepEqual(control.spoken.filter(line => line === "Reading the Fidelity pages").length, 1, "a progress line is not repeated");
        const releases = w.rows().filter(row => row.kind === "release" && row.decision === "send");
        assert.ok(releases.length >= 3, "acknowledgement and progress lines pass the release path");
    });

    await run("progress-short-request", async w => {
        const stepGate = gate(), answerGate = gate();
        const first = await say(w, utterance("Check the short status."));
        server.replies.push(text({ wait: stepGate.wait }, "<step>Reading short status</step>", { wait: answerGate.wait }, "Done."));
        await requested(w, first + 1, "the short request reaches the brain");
        await until(() => control.spoken.length !== 0, "the acknowledgement speaks");
        await playOut(w);
        w.advanceRunner(1000);
        stepGate.open();
        await turn();
        w.advanceRunner(1999);
        answerGate.open();
        await until(() => w.s().turn.kind === "none", "the short request completes before the progress threshold");
        await playOut(w);
        assert.equal(control.spoken.includes("Reading short status"), false, "a short request has no progress line");
    });

    await run("progress-repeat", async w => {
        const stepA = gate(), repeatA = gate(), stepB = gate(), answer = gate();
        const first = await say(w, utterance("Check the repeated status."));
        server.replies.push(text({ wait: stepA.wait }, "<step>Reading repeated status</step>",
            { wait: repeatA.wait }, "<step>Reading repeated status</step>",
            { wait: stepB.wait }, "<step>Searching later status</step>",
            { wait: answer.wait }, "Done."));
        await requested(w, first + 1, "the repeated request reaches the brain");
        await until(() => control.spoken.length !== 0, "the acknowledgement speaks");
        await playOut(w);
        w.advanceRunner(1000);
        stepA.open();
        await turn();
        w.advanceRunner(3000);
        await until(() => control.spoken.includes("Reading repeated status"), "the first progress line speaks");
        await playOut(w);
        repeatA.open();
        await turn();
        await playOut(w);
        assert.equal(control.spoken.filter(line => line === "Reading repeated status").length, 1,
            "a repeated stated step does not speak twice");
        stepB.open();
        await until(() => control.spoken.includes("Searching later status"), "the changed step speaks once");
        answer.open();
        await until(() => w.s().turn.kind === "none", "the repeated request completes");
        assert.equal(control.spoken.filter(line => line === "Reading repeated status").length, 1);
        assert.equal(control.spoken.filter(line => line === "Searching later status").length, 1);
    });

    // A step change while a line plays neither cuts it nor piles up: the
    // newest step waits alone and plays once the line has played.
    await run("progress-one-waits", async w => {
        const steps = gate(), answer = gate();
        const first = await say(w, utterance("Check the stacked status."));
        server.replies.push(text("<step>Reading stacked status</step>", { wait: steps.wait },
            "<step>Comparing stacked rows</step> <step>Counting stacked totals</step>",
            { wait: answer.wait }, "Done."));
        await requested(w, first + 1, "the stacked request reaches the brain");
        await until(() => control.spoken.length !== 0, "the acknowledgement speaks");
        await playOut(w);
        w.advanceRunner(4000);
        await until(() => control.spoken.includes("Reading stacked status"), "the first progress line speaks");
        steps.open();
        await turn();
        await turn();
        assert.deepEqual(w.s().playback.cue, "line", "the playing line is not cut");
        assert.equal(control.spoken.includes("Comparing stacked rows"), false, "a replaced step never waits");
        assert.equal(control.spoken.includes("Counting stacked totals"), false, "the newest step waits for the line");
        await playOut(w);
        await settled(() => control.spoken.includes("Counting stacked totals"),
            () => w.s().turn.kind === "thinking" && w.s().playback.kind === "idle",
            "the one waiting line plays next");
        answer.open();
        await until(() => w.s().turn.kind === "none", "the stacked request completes");
        await playOut(w);
        assert.deepEqual(control.spoken, ["Checking the stacked status.", "Reading stacked status", "Counting stacked totals", "Done."]);
        assert.deepEqual(w.faults, []);
    });

    // A line Session refused while an approval was held leaves no stream:
    // a later step still speaks once the hold is answered.
    await run("progress-after-refused-line", async w => {
        const first = await say(w, utterance("Read my clipboard."));
        server.replies.push([...text("<step>Reading the clipboard</step>").slice(0, 2),
            ...calls({ id: "call_1", name: "clipboard_read", arguments: {} }).slice(1)]);
        await until(() => w.s().approval.kind === "held", "clipboard release is held");
        const h = w.s().approval;
        w.runner.dispatch({ type: "shown", gen: h.gen, op: h.op, id: h.id });
        w.advanceRunner(4000);
        await turn();
        assert.equal(control.spoken.includes("Reading the clipboard"), false, "no line plays over a held approval");
        w.runner.dispatch({ type: "confirm", gen: h.gen, id: h.id, digest: h.digest, source: "button" });
        const held = gate();
        server.replies.push(text("<step>Comparing the clipboard</step>", { wait: held.wait }, "Done."));
        await requested(w, first + 2, "the granted result reaches the brain");
        await until(() => control.spoken.includes("Comparing the clipboard"), "a later step speaks after the hold");
        held.open();
        await until(() => w.s().turn.kind === "none", "the turn completes");
        assert.deepEqual(w.faults, []);
    }, { fixture: { recipients: [{ kind: "network", provider: "scripted-voice", account: "fixture", origin: "http://192.0.2.1:9" }] } });

    // Talk while a reply waits behind a line: the line is cut and the reply
    // was heard not at all, which the brain's next request says.
    await run("line-held-reply-interrupt", async w => {
        const first = await say(w, utterance("Hello."));
        await requested(w, first + 1, "the request starts");
        await until(() => control.spoken.includes("On it."), "the acknowledgement speaks");
        await feeding(w, 2 * Fixture.WORD_FRAMES);
        await advance(w, 6);
        server.replies.push(text("Hello there."));
        await until(() => w.s().turn.kind === "none" && w.s().playback.reply?.kind === "waiting", "the reply waits behind the line");
        control.utterances.push(utterance("Enough."));
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "Talk cuts the line and opens capture");
        release(w);
        server.replies.push(text(""));
        const body = await requested(w, first + 2, "the request after the interruption");
        assert.deepEqual(user(body), ["Hello.", INTERRUPTED + "\n\nEnough."], "the held reply was heard not at all");
        assert.deepEqual(w.faults, []);
    });

    await run("spoken-lines-secret", async w => {
        const held = gate();
        const first = await say(w, utterance("Check sk-abcdefghijklmnopqrstu."));
        server.replies.push(text({ wait: held.wait }, "<step>Reading sk-abcdefghijklmnopqrstu</step>", "Done."));
        await requested(w, first + 1, "the secret request reaches the brain");
        await until(() => control.spoken.length !== 0, "the acknowledgement speaks");
        await playOut(w);
        w.advanceRunner(4000);
        held.open();
        await until(() => w.s().turn.kind === "none", "the secret-line turn completes");
        assert.equal(control.spoken.includes("Reading sk-abcdefghijklmnopqrstu"), false, "a secret progress line is dropped");
        assert.equal(control.spoken.includes("On it."), true, "a secret transcript uses the acknowledgement fallback");
    });

    await run("feedback-interrupt-working", async w => {
        const first = await say(w, utterance("Hello."));
        await requested(w, first + 1, "the first request starts");
        w.advanceRunner(1200);
        await until(() => control.spoken.includes("On it."), "the acknowledgement line enters Audio");
        control.utterances.push(utterance("Enough."));
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "interruption flushes cue playback before capture");
        release(w);
        server.replies.push(text(""));
        const body = await requested(w, first + 2, "the interrupted cue's next request");
        assert.deepEqual(user(body), ["Hello.", INTERRUPTED + "\n\nEnough."], "no cue becomes assistant heard context");
        assert.deepEqual(control.spoken, ["On it.", "On it."]);
        assert.deepEqual(w.faults, []);
    }, { sounds: true });

    // The home folder's text follows the shipped guidance in the brain's
    // instructions and is read again at each conversation's first turn. A
    // text that outgrew its budget since the setup answer reaches the brain
    // whole and fails no turn; a skill set that outgrew its entry bound fails
    // that turn with its cause, and no request leaves without the whole
    // persona.
    const homeFolder = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "home-"));
    for (const set of [".agents/skills/jarvis", "skills/own", "memory"]) fs.mkdirSync(path.join(homeFolder, set), { recursive: true });
    fs.writeFileSync(path.join(homeFolder, "memory/MEMORY.md"), "");
    fs.writeFileSync(path.join(homeFolder, ".agents/skills/jarvis/SKILL.md"), "# Jarvis\n");
    fs.writeFileSync(path.join(homeFolder, ".agents/skills/jarvis/persona.md"), "# Persona\n");
    fs.writeFileSync(path.join(homeFolder, "skills/own/alpha.md"), "# Alpha skill\n");
    fs.writeFileSync(path.join(homeFolder, "AGENTS.md"), "HOME-MARKER-ONE\n");
    await run("home-text", async w => {
        // One whole exchange, then the conversation's end: the system text its first request carried.
        const exchange = async words => {
            const before = await say(w, utterance(words));
            const body = await requested(w, before + 1, words + ": the request reaches the server");
            server.replies.push(text("Ok."));
            await until(() => w.s().turn.kind === "none", words + ": the reply completes");
            await playOut(w);
            w.runner.dispatch({ type: "stop" });
            await until(() => w.s().conversation.kind === "ended" && w.s().playback.kind === "idle", words + ": the conversation ends");
            assert.equal(body.messages[0].role, "system");
            return body.messages[0].content;
        };
        const first = await exchange("Hello.");
        assert.deepEqual(["HOME-MARKER-ONE", "- own/alpha: Alpha skill"].map(line => first.includes(line)), [true, true]);
        fs.writeFileSync(path.join(homeFolder, "AGENTS.md"), "HOME-MARKER-TWO\n");
        const next = await exchange("Again.");
        assert.deepEqual([next.includes("HOME-MARKER-ONE"), next.includes("HOME-MARKER-TWO")], [false, true], "the last edit is the one a brain gets");
        fs.writeFileSync(path.join(homeFolder, "AGENTS.md"), "x".repeat(8193));
        fs.writeFileSync(path.join(homeFolder, "memory/MEMORY.md"), "m".repeat(4097));
        const over = await exchange("Once more.");
        assert.deepEqual([over.includes("x".repeat(8193)), over.includes("m".repeat(4097))], [true, true], "texts over their budget reach the brain whole");
        assert.equal(w.s().fault.kind, "none", "a text over its budget fails no turn");
        for (let index = 0; index < 257; index++) fs.writeFileSync(path.join(homeFolder, "skills/own/s" + index + ".md"), "# S\n");
        const fourth = await say(w, utterance("And again."));
        await settled(() => w.s().fault.kind !== "none", () => w.server.requests.length > fourth, "the overfull skill set fails the turn");
        assert.equal(w.s().fault.reason, "guidance=home-skills-too-large");
        assert.equal(w.server.requests.length, fourth, "no request leaves without the whole persona");
    }, { home: () => ({ kind: "ready", path: homeFolder }) });

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
        await until(() => w.s().turn.kind === "none", "the reply reaches speech");
        await playOut(w);
        assert.deepEqual(withoutAcks(control.spoken), ["It is noon.", "Anything else?"], "only Speakable sentences reach speech");
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
        assert.deepEqual(assistantCaptions(w), [[gen, "assistant", "partial", 1, "Let me check."],
            [gen, "assistant", "partial", 2, "Let me check. It is noon."],
            [gen, "assistant", "partial", 3, "Let me check. It is noon. Anything else?"],
            [gen, "assistant", "final", 4, "Let me check. It is noon. Anything else?"],
            [gen, "assistant", "partial", 5, "On it."], [gen, "assistant", "final", 6, "On it."]],
        "each released sentence grows the reply's caption, acknowledgements included, final at its end");
        const releases = w.rows().filter(row => row.kind === "release");
        assert.ok(releases.length >= 5 && releases.every(row => row.decision === "send" && row.outcome === "pending"
            && row.effect === "external"), "each utterance, request and sentence is audited before transfer");
        assert.deepEqual([...control.labels], ["speech"], "frames and sentences reach the adapter as labelled items");
    });

    // A test run's trace holds the brain's text as it wrote it, each text
    // event under its turn, while only its sentences reach speech: the one
    // that names a tool does not. Without the marker no file is made.
    for (const marker of ["1", undefined]) {
        const file = path.join(fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "brain-trace-")), "brain.jsonl");
        await run("brain-trace", async w => {
            const first = await say(w, utterance("Read my notes."));
            await requested(w, first + 1, "first request");
            const reply = ["Calling `mcp__vgs-jarvis__files_read` now. ", "Your notes say **noon**."];
            server.replies.push(text(...reply));
            await until(() => w.s().turn.kind === "none", "the reply completes");
            await playOut(w);
            assert.deepEqual(control.spoken.slice(-1), ["Your notes say noon."], "a sentence that names a tool is not spoken");
            assert.equal(control.spoken.some(sentence => sentence.includes("Calling") || sentence.includes("mcp")), false,
                "the tool status line is not spoken");
            if (marker !== "1") {
                assert.equal(fs.existsSync(file), false, "without the test-run marker the path is ignored");
                return;
            }
            const rows = fs.readFileSync(file, "utf8").split("\n").filter(Boolean).map(line => JSON.parse(line));
            assert.equal(rows.map(row => row.text).join(""), reply.join(""), "the trace holds the text as the brain wrote it");
            assert.deepEqual([...new Set(rows.map(row => row.gen))], [w.s().gen], "under the conversation's generation");
            assert.equal(new Set(rows.map(row => row.op)).size, 1, "and one turn");
        }, { trace: { marker, file } });
    }

    // Barge-in during speech, after the reply completed: the next request
    // carries exactly the heard prefix, read at the loopback server.
    await run("barge-in", async w => {
        const first = await say(w, utterance("What time is it?"));
        await requested(w, first + 1, "first request");
        await until(() => control.spoken.length !== 0, "the acknowledgement speaks");
        await playOut(w);
        server.replies.push(text("Hello there. ", "The time is noon."));
        await until(() => w.s().turn.kind === "none", "the reply completes before the interruption");
        await feeding(w, 2 * Fixture.WORD_FRAMES);
        await advance(w, 6);
        assert.equal(w.audio.playback.written, 1440 + 6 * 480, "the paced writer reached the planned count");
        control.utterances.push(utterance("Stop there."));
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "capture reopens after the flush");
        assert.equal(w.audio.lastPlayback.heardText, "Hello", "Audio's lower bound covers one word");
        release(w);
        server.replies.push(text("Stopped."));
        const body = await requested(w, first + 2, "the request after barge-in");
        assert.deepEqual(body.messages.slice(1).map(message => [message.role, message.content]), [
            ["user", "What time is it?"], ["assistant", "Hello there. The time is noon."],
            ["user", heardOnly("Hello") + "\n\nStop there."]], "the brain is told exactly the heard prefix");
        assert.deepEqual(withoutAcks(control.spoken).slice(0, 2), ["Hello there.", "The time is noon."]);
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
        await until(() => control.spoken.length !== 0, "the acknowledgement speaks");
        await playOut(w);
        const held = gate();
        server.replies.push(text("First part. ", { wait: held.wait }, "Second part."));
        await feeding(w, 2 * Fixture.WORD_FRAMES);
        await advance(w, 6);
        control.utterances.push(utterance("Enough."));
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "capture reopens after cancel and flush");
        await server.requests[first].closed;
        held.open();
        release(w);
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
        assert.equal(w.audio.lastPlayback === null || w.audio.lastPlayback.heardText === "", true,
            "no reply audio played before the interruption");
        held.open();
        release(w);
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
        await replyPlays(w, "the final reply speaks");
        await playOut(w);
        assert.deepEqual(control.spoken.slice(-1), ["Focused it."]);
        assert.deepEqual(assistantCaptions(w).map(row => row.slice(2)), [["partial", 1, "On it."],
            ["partial", 2, "On it. Focused it."], ["final", 3, "On it. Focused it."]],
        "a tool round's acknowledgement and reply are captioned once, at their end");
        assert.deepEqual(w.faults, []);
    });

    // A request handed to the Jarvis session's mailbox: a completed one is
    // Jarvis's fixed line, captioned and spoken once whatever the brain
    // says after it; any other result leaves the words to the brain.
    const ASKING = "Asking Jarvis's session.";
    const FLEET_ROW = { outcome: "completed", content: "Completed: the request is in the Jarvis session's mailbox as row 1792200000001." };
    for (const [name, result, reply, spoken] of [
        ["completed-echo", FLEET_ROW,
            "Asking Jarvis's session. It reads its mail next.", [ASKING, "It reads its mail next."]],
        ["completed-silent", { outcome: "completed", content: "Completed: the request is in the Jarvis session's mailbox as row 1792200000002." },
            "", [ASKING]],
        ["failed", { outcome: "failed", content: "fleet-request:mail-tool-absent" },
            "The mail tool is missing.", ["The mail tool is missing."]],
        ["unknown", { outcome: "unknown", content: "Unknown: lane-mail ended without a receipt." },
            "I could not confirm the request.", ["I could not confirm the request."]]
    ]) await run("fleet-request-" + name, async w => {
        const first = await say(w, utterance("Ask my fleet to update the docs."));
        server.replies.push(calls({ id: "call_fleet", name: "fleet_request", arguments: { text: "Update the docs." } }), text(reply));
        await until(() => w.s().approval.kind === "held", "the request for the Jarvis session waits for the user");
        const h = w.s().approval;
        w.runner.dispatch({ type: "shown", gen: h.gen, op: h.op, id: h.id });
        w.advanceRunner(1000);
        w.runner.dispatch({ type: "confirm", gen: h.gen, id: h.id, digest: h.digest, source: "button" });
        const body = await requested(w, first + 2, "the result reaches the brain");
        assert.deepEqual(w.executions.map(call => [call.id, call.args]), [["fleet.request", { text: "Update the docs." }]]);
        assert.equal(body.messages.find(message => message.role === "tool").content, result.content, "the row id stays in the result");
        await until(() => w.s().turn.kind === "none", "the turn completes");
        await playOut(w);
        assert.deepEqual(withoutAcks(control.spoken), spoken);
        const said = withoutAcks(assistantCaptions(w).filter(row => row[2] === "final").at(-1)[4].split(/(?<=\.) /u));
        assert.deepEqual(said, spoken, "the transcript shows what was spoken");
        assert.deepEqual(w.faults, []);
    }, { fleet: result });

    // The same request from a harness program, answered through the tool
    // bridge while the brain's reply streams: Jarvis's fixed line, said once,
    // though the brain says nothing after it.
    await run("fleet-request-bridged", async w => {
        const first = await say(w, utterance("Ask my fleet to update the docs."));
        const streaming = gate();
        server.replies.push([...pause(streaming), ...text("").slice(1)]);
        await requested(w, first + 1, "the brain's reply streams");
        const launch = await w.bridge.open({ gen: w.s().gen, recipients: control.opened.at(-1).recipients });
        const program = await harnessProgram(launch);
        try {
            program.send({ jsonrpc: "2.0", id: 1, method: "tools/call",
                params: { name: "fleet_request", arguments: { text: "Update the docs." } } });
            await until(() => w.s().approval.kind === "held", "the request for the Jarvis session waits for the user");
            const h = w.s().approval;
            w.runner.dispatch({ type: "shown", gen: h.gen, op: h.op, id: h.id });
            w.advanceRunner(1000);
            w.runner.dispatch({ type: "confirm", gen: h.gen, id: h.id, digest: h.digest, source: "button" });
            const answer = await program.next("the program receives the result");
            assert.deepEqual([answer.id, answer.result.content[0].text], [1, FLEET_ROW.content], "the row id stays in the result");
            assert.deepEqual(w.executions.map(call => [call.id, call.args]), [["fleet.request", { text: "Update the docs." }]]);
            streaming.open();
            await until(() => w.s().turn.kind === "none", "the turn completes");
            await playOut(w);
            assert.deepEqual(withoutAcks(control.spoken), [ASKING]);
            const said = withoutAcks(assistantCaptions(w).filter(row => row[2] === "final").at(-1)[4].split(/(?<=\.) /u));
            assert.deepEqual(said, [ASKING], "the transcript shows what was spoken");
            assert.deepEqual(w.faults, []);
        } finally {
            program.close();
            launch.close();
        }
    }, { fleet: FLEET_ROW, bridge: true });

    // A short command takes the local fast path: one call through the real
    // router and audit, no brain request, a fixed spoken line, and an
    // account of it in the brain's next request.
    const FAST_ACCOUNT = "[done without you] The user said \"Please go to workspace three.\". Jarvis ran workspaces.focus "
        + "{\"workspace\":3} with no model call, which ended completed: focused undefined";
    await run("fast-path", async w => {
        const first = await say(w, utterance("Please go to workspace three."));
        await settled(() => w.s().playback.kind === "playing",
            () => w.server.requests.length > first, "the fast path's line speaks");
        await playOut(w);
        await until(() => w.s().turn.kind === "none", "the fast turn ends");
        assert.equal(w.server.requests.length, first, "no brain request: no model call");
        assert.deepEqual(w.executions.map(call => [call.id, call.args]), [["workspaces.focus", { workspace: 3 }]]);
        assert.deepEqual(withoutAcks(control.spoken), ["Done."]);
        assert.deepEqual(assistantCaptions(w).map(row => row.slice(2)), [["partial", 1, "Done."], ["final", 2, "Done."]]);
        assert.deepEqual(w.rows().filter(row => row.kind === "action").map(row => [row.tool, row.decision, row.outcome, row.proposer]),
            [["workspaces.focus", "allow", "pending", "matcher"], ["workspaces.focus", "allow", "completed", "matcher"]],
            "Policy allowed the call and the audit names the matcher before and after it ran");
        const second = await say(w, utterance("Thanks."));
        server.replies.push(text("You are welcome."));
        const body = await requested(w, second + 1, "the next words reach the brain");
        assert.deepEqual(user(body), [FAST_ACCOUNT + "\n\nThanks."], "the brain hears what was done without it, once");
        await replyPlays(w, "the brain's reply speaks");
        await playOut(w);
        assert.deepEqual(w.faults, []);
    });

    // Words the matcher does not name reach the brain unchanged.
    await run("fast-path-unmatched", async w => {
        const first = await say(w, utterance("Bow to workspace three."));
        const body = await requested(w, first + 1, "the misheard words reach the brain");
        assert.deepEqual(user(body), ["Bow to workspace three."]);
        assert.deepEqual(w.executions, []);
        server.replies.push(text("Which workspace?"));
        await replyPlays(w, "the brain's reply speaks");
        await playOut(w);
    });

    // The fast path's line was never the brain's reply: cutting it off
    // adds no heard prefix.
    await run("fast-path-barge-in", async w => {
        const first = await say(w, utterance("Please go to workspace three."));
        await until(() => w.s().turn.kind === "none" && w.s().playback.kind !== "idle", "the fast path's line plays");
        control.utterances.push(utterance("Stop there."));
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "capture reopens after the flush");
        release(w);
        server.replies.push(text("Stopped."));
        const body = await requested(w, first + 1, "the request after the barge-in");
        assert.deepEqual(user(body), [FAST_ACCOUNT + "\n\nStop there."]);
        await replyPlays(w, "the brain's reply speaks");
        await playOut(w);
    });

    // A fast call that did not act hands the same words to the brain, with
    // its account: the rig has no media executor, so the router refuses.
    await run("fast-path-refused", async w => {
        const first = await say(w, utterance("Please mute the sound."));
        const body = await requested(w, first + 1, "the brain gets the words the fast call could not serve",
            () => w.s().turn.kind === "none" && w.server.requests.length === first);
        const said = user(body);
        assert.equal(said.length, 1);
        assert.ok(said[0].startsWith("[done without you] The user said \"Please mute the sound.\". Jarvis ran media.mute "
            + "{\"muted\":true} with no model call, which ended cancelled: "), said[0]);
        assert.ok(said[0].endsWith("\n\nPlease mute the sound."), said[0]);
        assert.deepEqual(w.rows().filter(row => row.kind === "action").map(row => [row.tool, row.decision, row.outcome, row.proposer]),
            [["media.mute", "refuse", "cancelled", "matcher"]]);
        server.replies.push(text("I cannot reach the sound here."));
        await replyPlays(w, "the brain's reply speaks");
        await playOut(w);
        assert.deepEqual(control.spoken.slice(-1), ["I cannot reach the sound here."], "no fast line before the brain's");
    });

    // A fast call still running when the user speaks again reports its real
    // outcome to the brain's next request.
    await run("fast-path-interrupted", async w => {
        const first = await say(w, utterance("Please go to workspace three."));
        await until(() => w.held.length === 1, "the stand-in executor holds the fast call");
        control.utterances.push(utterance("Wait."));
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "capture reopens while the call runs");
        w.held[0]({ outcome: "completed", content: "workspace shown late" });
        await turn();
        release(w);
        server.replies.push(text("Waiting."));
        const body = await requested(w, first + 1, "the request after the interruption");
        assert.deepEqual(user(body), [FAST_ACCOUNT.replace("focused undefined", "workspace shown late") + "\n\nWait."],
            "the real outcome reaches the next request as the fast call's, with no heard prefix");
        await replyPlays(w, "the brain's reply speaks");
        await playOut(w);
        assert.deepEqual(w.faults, []);
    }, { holdTools: true });

    // A segment closes at the wire's bound; a failed reply closes its words.
    await run("caption-segments", async w => {
        const first = await say(w, utterance("What time is it?"));
        await requested(w, first + 1, "first request");
        server.replies.push(text("It is noon. ", "Anything else?"));
        await until(() => w.s().turn.kind === "none", "the reply completes");
        const second = await say(w, utterance("And tomorrow?"));
        await requested(w, second + 1, "second request");
        server.replies.push(text("Bye, now. Go. More").slice(0, 2));
        await until(() => w.s().fault.kind === "error", "the cut reply fails");
        // The acknowledgement opens each reply's caption, so it shares the
        // reply's segments.
        assert.deepEqual(assistantCaptions(w).map(row => row.slice(2)), [
            ["partial", 1, "Let me check"], ["final", 2, "Let me check"], ["partial", 3, "."], ["partial", 4, ". It is noon"],
            ["final", 5, ". It is noon"], ["partial", 6, "."], ["partial", 7, ". Anything e"], ["final", 8, ". Anything e"],
            ["partial", 9, "lse?"], ["final", 10, "lse?"], ["partial", 11, "Let me check"], ["final", 12, "Let me check"],
            ["partial", 13, "."], ["partial", 14, ". Bye, now."], ["final", 15, ". Bye, now."], ["partial", 16, "Go."],
            ["final", 17, "Go."]], "segments split at the bound");
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
        release(w);
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
        await replyPlays(w, "the final reply speaks");
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
        await playOut(w);
        await until(() => control.utterances.length === 2, "capture reopens while the brain thinks");
        thinkingCapture.open();
        await replyPlays(w, "the first reply speaks");
        await playOut(w);
        // The final reaches a bound collection in the same tick, so a turn
        // still collecting after every final was delivered never sends it.
        const next = await requested(w, before + 2, "the second toggle turn",
            () => control.finals === 3 && w.s().turn.kind === "collecting");
        assert.equal(user(next).at(-1), "Second turn.");
        assert.ok(control.detections.length > 0 && control.detections.every(value => value === true),
            "toggle sends local turn-detection admission to each utterance");
    }, { mode: "toggle" });

    await run("follow-up-close-aborts", async w => {
        const before = await say(w, utterance("First turn.", [], null, { afterFrames: 3 }));
        server.replies.push(text("Reply."));
        await requested(w, before + 1, "the first Always request reaches the brain");
        await replyPlays(w, "the reply starts");
        control.utterances.push(utterance("inside window", [], null, { afterFrames: 100000 }));
        await playOut(w);
        await until(() => w.s().capture.kind === "open" && w.s().capture.mode === "follow-up", "the follow-up window opens");
        w.advanceRunner(6000);
        await until(() => w.s().capture.kind === "closed", "the silent follow-up window closes");
        await settled(() => control.aborted === 1, () => control.finals > 1 || w.faults.length > 0,
            "the closed follow-up utterance is aborted");
        assert.equal(server.requests.length, before + 1, "a closed window sends no follow-up request");
        assert.deepEqual(w.faults, [], "a closed window raises no transcription fault");
    }, { mode: "always", fixture: { wake: true } });

    // A transcription that fails after its capture closed ends its turn.
    await run("transcribe-failure", async w => {
        control.utterances.push(utterance("lost", [], null, { failAfterClose: true }));
        const before = server.requests.length;
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "capture opens");
        release(w);
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
        await until(() => control.spoken.length !== 0, "the acknowledgement speaks");
        await playOut(w);
        server.replies.push(text("One. ", "Two. ", "Three."));
        // The last sentence is released only at the reply's end and reaches
        // speech a tick later; nothing advances the playback clock, so a turn
        // still open then waits on speech.
        await settled(() => w.s().turn.kind === "none",
            () => withoutAcks(control.spoken).length === 3 || w.audio.playbackFeed?.readableLength > 0 && w.s().turn.kind === "thinking",
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
        assert.deepEqual(w.configure({ mode: "hold", microphone: "", speaker: "", brain: "other-account" }), { kind: "ready", cautions: [] });
        await assert.rejects(old.net.request({ content: "x", labels: ["speech"] }, { url: "http://127.0.0.1:" + PORT + "/v1" }),
            { message: "jarvis: net=closed" }, "the old transport closes at the change");
        const second = await say(w, utterance("What did I say?"));
        server.replies.push(text(""));
        const body = await requested(w, second + 1, "the request after the change");
        assert.deepEqual(user(body), ["What did I say?"], "old context does not cross the change");
        assert.equal(control.opened[1].recipients.brain.account, "other-account");
    });

    // A preview speaks one fixed sentence in the chosen voice with no brain
    // request, and a changed voice ends the conversation, as a changed
    // provider does: a Realtime voice cannot change once it has spoken.
    await run("voice-preview", async w => {
        const before = w.server.requests.length;
        w.runner.dispatch({ type: "preview", voice: "fixture" });
        await settled(() => control.spoken.length === 1,
            () => w.s().turn.kind === "none" && w.s().playback.kind === "idle",
            "the preview speaks");
        await playOut(w);
        assert.deepEqual([control.speakers, w.server.requests.length], [["fixture"], before], "the first voice, no brain request");
        const first = await say(w, utterance("Remember blue."));
        server.replies.push(text(""));
        await requested(w, first + 1, "first request");
        await until(() => w.s().turn.kind === "none", "the first turn completes");
        const old = control.opened[0];
        const gen = w.s().gen;
        w.configure({ ...w.s().settings, voice: "other" });
        await assert.rejects(old.net.request({ content: "x", labels: ["speech"] }, { url: "http://127.0.0.1:" + PORT + "/v1" }),
            { message: "jarvis: net=closed" }, "the voice change closes the conversation's transport");
        assert.deepEqual([w.s().conversation.kind, w.s().gen > gen], ["ended", true]);
        // The ended turn's acknowledgement is flushed first; a preview waits for a quiet speaker.
        await until(() => w.s().playback.kind === "idle", "the ended conversation's playback is flushed");
        w.runner.dispatch({ type: "preview", voice: "other" });
        await until(() => control.spoken.filter(line => line === control.spoken[0]).length === 2, "the preview speaks again");
        await playOut(w);
        assert.deepEqual([control.speakers.at(-1), control.spoken.at(-1)], ["other", control.spoken[0]], "the same sentence in the new voice");
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

    // The cloned voice's recording sits in Jarvis's private state, which the
    // file judge protects: a brain turn that names it is refused before any
    // executor, and no byte of it enters an item Policy.release sends. The
    // state root is the default one inside the home (setup-local roots), so
    // only that protection, not the home bound, withholds it.
    const defaultState = path.join(process.env.HOME, ".local/state");
    await run("cloned-voice-reference-withheld", async w => {
        const reference = path.join(defaultState, "vgshell/jarvis/voice-reference.wav");
        fs.mkdirSync(path.dirname(reference), { recursive: true });
        fs.writeFileSync(reference, "RIFF fixture recording", { mode: 0o600 });
        try {
            const first = await say(w, utterance("Read my voice recording."));
            server.replies.push(calls({ id: "call_reference", name: "files_read", arguments: { path: reference } }), text(""));
            const body = await requested(w, first + 2, "the tool-results request");
            assert.equal(JSON.stringify(server.requests).includes("fixture recording"), false, "no byte of the recording leaves");
            assert.deepEqual(w.executions, [], "no executor reads it");
            assert.equal(body.messages.some(message => message.role === "tool"), true, "the brain reads the refusal");
            assert.ok(w.rows().some(row => row.kind === "action" && row.tool === "files.read" && row.decision === "refuse"),
                "the refusal is audited");
        } finally { fs.rmSync(reference); }
    }, { actionApproval: true, filesExecutor: true, deniedState: defaultState });

    // A progress line is the brain's text: it carries the turn's labels to
    // the voice, as a reply sentence does, whether the threshold timer or a
    // later step speaks it.
    for (const path of ["timer", "late"]) await run("progress-line-labels-" + path, async w => {
        const first = await say(w, utterance("Read my clipboard."));
        server.replies.push(calls({ id: "call_1", name: "clipboard_read", arguments: {} }));
        await until(() => w.s().approval.kind === "held", "clipboard release is held before transfer");
        const h = w.s().approval;
        w.runner.dispatch({ type: "shown", gen: h.gen, op: h.op, id: h.id });
        w.advanceRunner(1000);
        w.runner.dispatch({ type: "confirm", gen: h.gen, id: h.id, digest: h.digest, source: "button" });
        const held = gate();
        if (path === "late") w.advanceRunner(3000);
        server.replies.push(text("<step>Reading the clipboard words</step>", { wait: held.wait }, "Done."));
        await requested(w, first + 2, "the granted result reaches the brain");
        if (path === "timer") {
            await turn();
            w.advanceRunner(3000);
        }
        await until(() => control.spoken.includes("Reading the clipboard words"), "the step speaks");
        assert.ok(control.labels.has("clipboard"), "the line keeps the turn's clipboard label");
        held.open();
        await until(() => w.s().turn.kind === "none", "the turn completes");
        assert.deepEqual(w.faults, []);
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
        await until(() => w.s().playback.kind === "idle", "the acknowledgement line is flushed before voice confirmation");
        w.advanceRunner(1100);
        control.utterances.push(utterance("Yes."));
        const finals = control.finals;
        w.runner.dispatch({type: "talk-down"});
        await until(() => w.s().capture.kind === "open", "answer capture opens without a new brain turn");
        assert.equal(w.s().approval.id, h.id);
        assert.equal(w.s().turn.kind, "thinking");
        release(w);
        const body = await requested(w, first + 2, "final voice answer releases the result",
            () => w.s().approval.kind === "held" && w.s().capture.kind === "closed" && control.finals > finals);
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
        // Half duplex: the acknowledgement plays out before capture opens.
        await playOut(w);
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
        release(w);
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
                await until(() => w.s().turn.kind === "none", "prior reply is released");
                await replyPlays(w, "prior reply plays");
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
            release(w);
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
    await run("audit-refusal-line", async w => {
        const block = () => {
            fs.renameSync(path.join(w.state, "audit"), path.join(w.state, "audit-saved"));
            fs.writeFileSync(path.join(w.state, "audit"), "not a directory\n");
        };
        control.utterances.push(utterance("Hello."));
        const before = server.requests.length;
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "capture opens");
        block();
        release(w);
        await settled(() => w.s().fault.kind === "error",
            () => server.requests.length > before || w.s().turn.kind === "thinking",
            "the acknowledgement audit failure ends the turn");
        assert.equal(w.s().fault.reason, "engine=audit-write");
        assert.equal(server.requests.length, before, "no request left without its audit record");
        fs.rmSync(path.join(w.state, "audit"));
        fs.renameSync(path.join(w.state, "audit-saved"), path.join(w.state, "audit"));
        assert.deepEqual(w.configure({ mode: "hold", microphone: "", speaker: "", brain: "other-account" }), { kind: "ready", cautions: [] });
        await say(w, utterance("Again."));
        server.replies.push(text(""));
        assert.deepEqual(user(await requested(w, before + 1, "the next turn")), ["Again."],
            "the failed line leaves no stuck turn");
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
        assert.deepEqual(withoutAcks(control.spoken), [], "no text reaches speech without its audit record");
        assert.deepEqual(assistantCaptions(w).filter(row => !["On it.", "Let me check."].includes(row[4])), [],
            "no reply text is captioned without its release");
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
        await until(() => control.spoken.length !== 0, "the acknowledgement speaks");
        await playOut(w);
        const sentences = Array.from({ length: 40 }, (_, index) => "Item number " + (index + 1) + ".");
        server.replies.push(text(...sentences.map(sentence => sentence + " ")));
        // Nothing advances the playback clock: the source fills to its mark.
        await until(() => w.audio.playbackFeed !== null
            && w.audio.playbackFeed.readableLength >= w.audio.playbackFeed.readableHighWaterMark, "the source fills");
        await until(() => w.s().turn.kind === "none", "the brain is read to its end");
        // Audio holds one chunk and the adapter one sentence beyond the mark.
        const bound = w.audio.playbackFeed.readableHighWaterMark + 2;
        const listed = () => control.spoken.filter(sentence => sentence.startsWith("Item number "));
        assert.ok(listed().length <= bound, "a stalled player pauses synthesis: " + listed().length);
        await playOut(w);
        assert.equal(listed().length, 40);
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

    // A dictation row: the core records each utterance once Session admitted
    // its capture, and the words its stop hands back are the user's turn.
    // The row's own final only says whether it heard speech.
    const dictating = { fixture: { dictation: true } };
    await run("dictation-hold-turn", async w => {
        w.dictation.text = "Open the voxtype browser.";
        w.runner.dispatch({ type: "indicator", shown: false });
        control.utterances.push(utterance("Open the sidecar browser."));
        w.runner.dispatch({ type: "talk-down" });
        await turn();
        assert.deepEqual(w.dictation.calls, [], "no recording before the indicator is presented");
        const before = server.requests.length;
        w.runner.dispatch({ type: "indicator", shown: true });
        await until(() => w.s().capture.kind === "open", "the presented indicator opens the capture");
        assert.deepEqual(w.dictation.calls, ["dictation.start"]);
        release(w);
        const body = await requested(w, before + 1, "the recording's words reach the brain",
            () => w.dictation.calls.includes("dictation.stop") && quietTurn(w));
        assert.deepEqual(user(body), ["Open the voxtype browser."], "the recording's words are the user's turn");
        assert.deepEqual(w.dictation.calls, ["dictation.start", "dictation.stop"]);
        server.replies.push(text(""));
        await until(() => w.s().turn.kind === "none", "the turn completes");
    }, dictating);

    // voxtype's tones, set in Voice, are the recording's cue: with Jarvis's
    // sounds on, Talk opens the capture with no sound of Jarvis's own.
    await run("dictation-no-cue", async w => {
        control.utterances.push(utterance("Hello."));
        w.runner.dispatch({ type: "talk-down" });
        assert.equal(w.s().playback.kind, "idle", "no start sound is queued");
        await until(() => w.s().capture.kind === "open", "the capture opens at once");
        assert.deepEqual(w.writes, [], "Jarvis played nothing before the recording");
        w.runner.dispatch({ type: "stop" });
        await until(() => w.s().capture.kind === "closed", "stop ends the capture");
    }, { ...dictating, sounds: true });

    // Each end that drops the utterance cancels its recording: no stop, and
    // no words reach the brain.
    for (const trigger of ["mute", "stop", "lock", "daemon-end"]) await run("dictation-cancel-" + trigger, async w => {
        w.dictation.text = "Words that never leave.";
        control.utterances.push(utterance("Words that never leave.", ["Words"]));
        const before = server.requests.length;
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.partials.at(-1) === "Words", "the utterance is heard");
        await until(() => w.dictation.calls.length === 1, "the recording starts");
        // Its answer comes on a later turn, as a reply line does.
        await new Promise(resolve => setImmediate(resolve));
        if (trigger === "mute") w.runner.dispatch({ type: "mute-toggle" });
        else if (trigger === "stop") w.runner.dispatch({ type: "stop" });
        else if (trigger === "lock") w.runner.dispatch({ type: "snapshot", configured: true, locked: true,
            engine: w.engine.engine(), settings: w.s().settings });
        let daemonEnded = false;
        if (trigger === "daemon-end") { w.engine.close(); daemonEnded = true; }
        await settled(() => w.dictation.calls.includes("dictation.cancel"),
            () => daemonEnded && w.dictation.calls.length === 1 || w.s().capture.kind === "closed" && w.s().turn.kind === "none",
            trigger + " cancels the recording");
        release(w);
        await turn();
        assert.deepEqual(w.dictation.calls, ["dictation.start", "dictation.cancel"], trigger + ": never stopped");
        assert.equal(server.requests.length, before, trigger + ": no words reach the brain");
    }, dictating);

    // An end asked for while the start is unanswered runs once it answers:
    // a dropped utterance's recording is cancelled, never stopped, and a Hold
    // released then is stopped and its words are the turn.
    for (const trigger of ["stop", "mute", "lock"]) await run("dictation-pending-" + trigger, async w => {
        w.dictation.hold = true;
        w.dictation.text = "Words that never leave.";
        control.utterances.push(utterance("Words that never leave.", ["Words"]));
        const before = server.requests.length;
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.dictation.calls.length === 1 && w.partials.at(-1) === "Words", "the start waits for its answer");
        if (trigger === "stop") w.runner.dispatch({ type: "stop" });
        else if (trigger === "mute") w.runner.dispatch({ type: "mute-toggle" });
        else w.runner.dispatch({ type: "snapshot", configured: true, locked: true, engine: w.engine.engine(), settings: w.s().settings });
        await until(() => w.s().conversation.kind === "ended", trigger + " ends the conversation");
        w.dictation.release();
        await turn();
        await settled(() => w.dictation.calls.includes("dictation.cancel"),
            () => w.dictation.held.length === 0 && w.dictation.calls.length === 1 && w.s().conversation.kind === "ended",
            trigger + " cancels the recording once the start answers");
        release(w);
        await turn();
        assert.deepEqual(w.dictation.calls, ["dictation.start", "dictation.cancel"], trigger + ": never stopped");
        assert.equal(server.requests.length, before, trigger + ": no words reach the brain");
    }, dictating);
    await run("dictation-pending-release", async w => {
        w.dictation.hold = true;
        w.dictation.text = "Released early.";
        control.utterances.push(utterance("Released early."));
        const before = server.requests.length;
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.dictation.calls.length === 1 && w.s().capture.kind === "open", "the start waits for its answer");
        release(w);
        await until(() => control.finals === 1, "the row's end comes before the start answers");
        assert.deepEqual(w.dictation.calls, ["dictation.start"]);
        w.dictation.release();
        await turn();
        const body = await requested(w, before + 1, "the released Hold's words reach the brain",
            () => w.dictation.held.length === 0 && w.dictation.calls.length === 1 && w.s().capture.kind === "closed");
        assert.deepEqual(user(body), ["Released early."]);
        assert.deepEqual(w.dictation.calls, ["dictation.start", "dictation.stop"]);
        server.replies.push(text(""));
        await until(() => w.s().turn.kind === "none", "the turn completes");
    }, dictating);

    // A stop the core refuses fails the turn with its keyed cause.
    await run("dictation-stop-refused", async w => {
        w.dictation.stop = "refused: dictation=failed reason=stop code=1";
        const before = await say(w, utterance("Lost words."));
        await settled(() => w.s().fault.kind === "error",
            () => w.dictation.calls.includes("dictation.stop") && quietTurn(w),
            "the refused stop is the turn's fault");
        assert.equal(w.s().fault.reason, "speech=dictation-failed");
        assert.deepEqual(w.dictation.calls, ["dictation.start", "dictation.stop"]);
        assert.equal(server.requests.length, before, "no words reach the brain");
    }, dictating);

    // Toggle reopens the capture while Jarvis thinks; no turn takes it, so it
    // records nothing, and the next turn's capture records again.
    await run("dictation-toggle-second-turn", async w => {
        control.utterances.push(utterance("First turn.", [], null, { afterFrames: 3 }),
            utterance("unbound while thinking", [], null, { afterFrames: 1 }),
            utterance("Second turn.", [], null, { afterFrames: 3 }),
            utterance("never ends", [], null, { afterFrames: 100000 }));
        w.dictation.text = "First turn.";
        const before = server.requests.length;
        const thinkingCapture = gate();
        server.replies.push([...pause(thinkingCapture), ...text("One.").slice(1)], text("Two."));
        w.runner.dispatch({ type: "talk-down" });
        assert.deepEqual(user(await requested(w, before + 1, "the first toggle turn")), ["First turn."]);
        await playOut(w);
        await until(() => control.utterances.length === 2 && control.finals === 2, "the capture reopened while the brain thinks ends");
        await turn();
        assert.deepEqual(w.dictation.calls, ["dictation.start", "dictation.stop"], "the capture no turn takes records nothing");
        w.dictation.text = "Second turn.";
        thinkingCapture.open();
        await replyPlays(w, "the first reply speaks");
        await playOut(w);
        const next = await requested(w, before + 2, "the second toggle turn",
            () => control.finals === 3 && w.s().turn.kind === "collecting");
        assert.equal(user(next).at(-1), "Second turn.");
        assert.deepEqual(w.dictation.calls, ["dictation.start", "dictation.stop", "dictation.start", "dictation.stop"]);
    }, { ...dictating, mode: "toggle" });

    // No speech in the utterance: voxtype would still write words for the
    // silence, so the recording is cancelled, never stopped.
    await run("dictation-silent", async w => {
        w.dictation.text = "Yeah.";
        const before = await say(w, utterance(""));
        await turn();
        await settled(() => w.dictation.calls.includes("dictation.cancel"),
            () => w.dictation.calls.length === 1 && w.s().capture.kind === "closed"
                || w.dictation.calls.includes("dictation.stop") || control.finals > 0 && w.dictation.calls.length === 1 || quietTurn(w),
            "the silent recording is cancelled");
        await until(() => w.s().turn.kind === "none" && w.s().capture.kind === "closed", "the empty turn settles");
        assert.deepEqual(w.dictation.calls, ["dictation.start", "dictation.cancel"]);
        assert.equal(server.requests.length, before, "the silence's words never reach the brain");
    }, dictating);

    // A start the core or the service refuses fails the collection with its
    // keyed cause; nothing is stopped and no words reach the brain.
    await run("dictation-start-refused", async w => {
        w.dictation.start = "refused: dictation=busy holder=vgs.voice";
        control.utterances.push(utterance("Words for nobody.", ["Words"]));
        const before = server.requests.length;
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().fault.kind === "error", "the refusal is the turn's fault");
        assert.equal(w.s().fault.reason, "speech=dictation-busy");
        await until(() => w.s().capture.kind === "closed", "the refused utterance's capture closes");
        release(w);
        await turn();
        assert.deepEqual(w.dictation.calls, ["dictation.start"], "a refused recording is never stopped");
        assert.equal(server.requests.length, before);
    }, dictating);

    // The service's dictation cause holds the local voice: no capture opens
    // and nothing is recorded.
    await run("dictation-cause-holds", async w => {
        assert.deepEqual(w.configure({ ...w.s().settings, dictation: "speech=dictation-device" }),
            { kind: "unconfigured", cause: "speech=dictation-device", causes: ["speech=dictation-device"], cautions: [] });
        assert.equal(w.s().gate.kind, "down");
        control.utterances.push(utterance("Hello."));
        w.runner.dispatch({ type: "talk-down" });
        await turn();
        assert.deepEqual([w.s().capture.kind, w.dictation.calls], ["closed", []], "no capture and no recording");
        assert.equal(w.configure({ ...w.s().settings, dictation: "" }).kind, "ready", "a hello without the cause frees it");
    }, dictating);

    // The confirm phrase is judged on the recording's words, and a voice
    // confirmation never passes a physical hold: a voxtype replacement that
    // turns another word into "yes" confirms nothing.
    await run("dictation-physical-hold", async w => {
        const target = path.join(w.workspace, "fixture.txt");
        fs.writeFileSync(target, "fixture");
        w.dictation.text = "Delete the fixture.";
        const first = await say(w, utterance("Delete the fixture."));
        server.replies.push(calls({ id: "call_delete", name: "files_delete", arguments: { path: target } }), text(""));
        await until(() => w.s().approval.kind === "held", "the delete is held");
        const h = w.s().approval;
        assert.equal(h.physical, true, "a destructive action holds for a physical confirmation");
        w.runner.dispatch({ type: "shown", gen: h.gen, op: h.op, id: h.id });
        await until(() => w.s().playback.kind === "idle", "the acknowledgement is flushed");
        w.advanceRunner(1100);
        w.dictation.text = "Yes.";
        control.utterances.push(utterance("Maybe."));
        const calls0 = w.dictation.calls.length;
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "the answer capture opens");
        w.advanceRunner(1100);
        release(w);
        await until(() => w.dictation.calls.slice(calls0).join(",") === "dictation.start,dictation.stop", "the answer is recorded");
        await until(() => w.s().capture.kind === "closed", "the answer capture closes");
        await turn();
        await turn();
        assert.equal(w.s().approval.kind, "held", "the voice answer leaves the hold");
        assert.equal(w.s().approval.id, h.id);
        assert.deepEqual(w.executions, [], "nothing was deleted");
        assert.equal(server.requests.length, first + 1, "no brain turn follows the refused answer");
    }, { ...dictating, actionApproval: true, filesExecutor: true });

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
    async function opened(w, playbackOver = () => false) {
        const first = await say(w, utterance("Hello."));
        await requested(w, first + 1, "the opening turn reaches the brain");
        server.replies.push(text("Hi."));
        await until(() => w.s().turn.kind === "none" && control.spoken.includes("Hi."), "the opening reply completes");
        const spokenBefore = control.spoken.length;
        await playOut(w, () => playbackOver(spokenBefore));
        return spokenBefore;
    }
    // Waits until speech holds every sentence of line after the first from,
    // then plays it out and answers the spoken text.
    async function spoken(w, from, line, over = () => false, playOver = () => false) {
        await settled(() => control.spoken.slice(from).join(" ") === line,
            () => {
                const said = control.spoken.slice(from).join(" ");
                return over() || said.length > line.length || said !== "" && !line.startsWith(said)
                    || quietTurn(w) && said !== line;
            }, "Jarvis speaks: " + line);
        await playOut(w, playOver);
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
        await turn();
        await settled(() => t.notes.length === 1,
            () => control.spoken.length > 0 || quietTurn(w), "the held prompt is notified");
        assert.deepEqual(t.notes, [["Coding task", QUESTION_CARD]], "with no conversation the prompt is a notification");
        assert.deepEqual([control.spoken, w.s().conversation.kind], [[], "ended"], "nothing is spoken with no conversation");
        const asked = await opened(w,
            from => control.spoken.slice(from).join(" ").startsWith(QUESTION + " "));
        await spoken(w, asked, QUESTION, undefined, () => control.spoken.slice(asked).join(" ") !== QUESTION);
        assert.ok(control.labels.has("agent"), "the agent's text reaches speech labelled as agent output");
        const requests = server.requests.length;
        // Another idle state publication asks nothing new.
        w.runner.dispatch({ type: "indicator", shown: true });
        await new Promise(resolve => setImmediate(resolve));
        assert.equal(control.spoken.length, asked + 2, "a prompt is asked once per conversation");
        const said = control.spoken.length;
        await say(w, utterance("Use main."));
        await spoken(w, said, SENT, () => server.requests.length > requests
            || t.Relay.answerTo(t.prompts, question) !== null && quietTurn(w) || quietTurn(w));
        assert.equal(server.requests.length, requests, "the answer never reaches the brain");
        assert.deepEqual(t.Relay.answerTo(t.prompts, question), { v: 1, kind: "reply", text: "Use main." });
        assert.deepEqual(w.captions.filter(row => row[1] === "user").map(row => row[4]), ["Hello.", "Use main."],
            "the user's answer shows as their words");
        assert.ok(w.captions.some(row => row[1] === "assistant" && row[4].includes("Which branch should I use?")),
            "the asked prompt is captioned as Jarvis's words");
        t.event("t1", "turn-ended");
        let from = control.spoken.length;
        await t.observe();
        await spoken(w, from, WAITING,
            () => control.spoken.slice(from).some(sentence => sentence.includes("Which branch")));
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

    // A permission prompt as the shipped hook writes it, backend/claude-hook:
    // the tool's name, a space and its input as JSON. Jarvis speaks the
    // command the user is asked to allow, and the words that say how to
    // answer, also where TaskRelay cut a long input short.
    await run("task-permission-command", async w => {
        const t = w.tasks;
        await t.observe();
        await opened(w);
        t.task("t5");
        const hook = input => "Bash " + JSON.stringify(input);
        const first = t.ask("t5", { kind: "permission", tool: "Bash", text: hook({ command: "rm -rf build", description: "Remove the build folder" }) });
        let from = control.spoken.length;
        await t.observe();
        await spoken(w, from, 'The coding agent asks to use Bash: Bash "command":"rm -rf build","description":"Remove the build folder". Say allow or deny.');
        from = control.spoken.length;
        await say(w, utterance("Deny."));
        await spoken(w, from, SENT);
        assert.deepEqual(t.Relay.answerTo(t.prompts, first), { v: 1, kind: "deny" });
        // One word a sentence, so the line plays out in a few seconds.
        const word = "remove" + "-build".repeat(10);
        const long = hook({ command: (word + ". ").repeat(80) });
        assert.ok(Buffer.byteLength(long) > 4096, "the input passes TaskRelay's bound");
        const cut = t.ask("t5", { kind: "permission", tool: "Bash", text: long });
        from = control.spoken.length;
        await t.observe();
        const said = () => control.spoken.slice(from);
        let cutDone = false;
        await wait(() => {
            cutDone = said().some(sentence => sentence.endsWith("Say allow or deny."));
            const spoken = said().join(" ");
            if (cutDone || w.s().fault.kind !== "none" || quietTurn(w) && spoken !== "")
                return true;
            w.audioClock.advance(20);
            return false;
        }, "the cut prompt is spoken to its end", OBSERVE_MS, 1);
        assert.ok(cutDone, "the cut prompt is spoken to its end");
        assert.ok(said().at(-1).endsWith("Say allow or deny."), "the cut prompt still says how to answer");
        assert.ok(said()[0].startsWith('The coding agent asks to use Bash: Bash "command":"' + word), "the cut prompt names the tool and starts its command");
        assert.ok(said().filter(sentence => sentence === word + ".").length >= 50, "the command's words are spoken");
        await playOut(w);
        from = control.spoken.length;
        await say(w, utterance("Allow."));
        await spoken(w, from, SENT);
        assert.deepEqual(t.Relay.answerTo(t.prompts, cut), { v: 1, kind: "allow" });
        assert.deepEqual(w.faults, []);
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
        const body = await requested(w, next + 1, "the interrupting words reach the brain",
            () => t.Relay.answerTo(t.prompts, question) !== null || quietTurn(w));
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
        await settled(() => w.s().conversation.kind === "ended" && t.notes.length > 0,
            () => w.s().conversation.kind === "ended" && w.s().playback.kind === "idle" && t.notes.length === 0,
            "the cut-off prompt is notified");
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
            await settled(() => w.s().fault.kind === "error" && t.notes.length > 0,
                () => w.s().fault.kind === "error" && t.notes.length === 0,
                "the failed line is notified");
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
            const spokenBefore = control.spoken.length;
            const next = await say(w, utterance(said));
            const body = await requested(w, next + 1, "the words reach the brain: " + said,
                () => control.spoken.slice(spokenBefore).includes(PERMISSION)
                    || control.spoken.slice(spokenBefore).includes("Say allow or deny.")
                    || t.Relay.answerTo(t.prompts, permission) !== null || control.spoken.includes(SENT) || quietTurn(w));
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
        await settled(() => w.s().approval.kind === "held",
            () => control.spoken.some(sentence => sentence.includes("Which branch")) || t.notes.length > 0,
            "agent text asks for release first");
        assert.equal(w.s().approval.purpose, "release");
        const h = w.s().approval;
        w.runner.dispatch({ type: "approval-cancel", gen: h.gen, id: h.id });
        await settled(() => t.notes.length === 1 && w.s().turn.kind === "none",
            () => w.s().turn.kind === "none" && w.s().approval.kind === "none" && t.notes.length === 0,
            "the withheld prompt is notified");
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
            ["relay-reply-rules", "                const speakable = Speakable.create(LANGUAGE);\n                for (const sentence of [...speakable.push(text)",
                "                const speakable = Speakable.create(LANGUAGE, { tools: [] });\n                for (const sentence of [...speakable.push(text)",
                "task-permission-command"],
            ["relay-retry-captures", "if (prompt !== null && answer === null && c.retried === c.relay) {",
                "if (false) {", "task-permission-release"],
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
        assert.deepEqual(configure(settings, choose, ready), { kind: "unconfigured", cause: causes[0], causes, cautions: [] }, causes.join(" "));
    assert.deepEqual(configure({}, () => { throw new Error("jarvis-keys: references=json"); }, true),
        { kind: "unconfigured", cause: "brain=accounts-unreadable", detail: "jarvis-keys: references=json", causes: ["brain=accounts-unreadable"], cautions: [] },
        "a reader's keyed failure keeps its cause");
    assert.deepEqual(configure({ fallbacks: [{ name: "backup", brain: "b", model: "backup-model" }] },
        id => id === "a" ? { kind: "refused", cause: "signed-out" } : { kind: "accepted", account: { ...resolved, id, model: "" } }, true),
    { kind: "ready", cautions: [] }, "a refused primary is skipped when a backup is usable");
    Fixture.reset();
    assert.throws(() => Engine.create({ accounts: () => ({ choose: () => { throw new TypeError("defect"); } }), captionLimit: 1 })
        .configure({ brain: "a" }), TypeError, "a defect is not a configuration cause");
    assert.deepEqual(configure({}, accepted(resolved), true), { kind: "ready", cautions: [] });
    // Always mode needs a row that spots the word on this computer.
    const always = ["speech=always-local-voice"];
    for (const [settings, wake, causes] of [
        [{ mode: "always" }, false, always],
        [{ mode: "always", voiceProvider: "realtime" }, true, always],
        [{ mode: "always", voiceProvider: "gemini" }, true, always],
        [{ mode: "always", brain: "" }, false, [...always, "brain=unselected"]]])
        assert.deepEqual(configure(settings, accepted(resolved), true, wake), { kind: "unconfigured", cause: causes[0], causes, cautions: [] }, JSON.stringify(settings));
    assert.deepEqual(configure({ mode: "always" }, accepted(resolved), false, true), { kind: "unconfigured", cause: "speech=fixture-off",
        causes: ["speech=fixture-off"], cautions: [] }, "a row not set up keeps its own cause and Settings path");
    assert.deepEqual(configure({ mode: "always" }, accepted(resolved), true, true), { kind: "ready", cautions: [] });
    assert.deepEqual(configure({ mode: "toggle" }, accepted(resolved), true), { kind: "ready", cautions: [] });
    // The home folder's step leads the two: a folder the daemon refused, or
    // whose text Guidance cannot read, holds the engine with its cause
    // first; no home, or a home that reads, adds none. A text over its
    // budget holds nothing: each answer names it among its cautions.
    const homes = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "homes-"));
    const homeAt = (name, agents, memory = "", skills = 0) => {
        for (const set of [".agents/skills/jarvis", "skills/own", "memory"]) fs.mkdirSync(path.join(homes, name, set), { recursive: true });
        fs.writeFileSync(path.join(homes, name, "memory/MEMORY.md"), memory);
        for (let index = 0; index < skills; index++) fs.writeFileSync(path.join(homes, name, "skills/own/s" + index + ".md"), "# S\n");
        fs.writeFileSync(path.join(homes, name, ".agents/skills/jarvis/SKILL.md"), "# Jarvis\n");
        fs.writeFileSync(path.join(homes, name, ".agents/skills/jarvis/persona.md"), "# Persona\n");
        fs.writeFileSync(path.join(homes, name, "AGENTS.md"), agents);
        return { kind: "ready", path: path.join(homes, name) };
    };
    const withHome = (home, settings, ready) => {
        Fixture.reset({ ready });
        return Engine.create({ accounts: () => ({ secrets: null, choose: accepted(resolved) }), captionLimit: 1, home: () => home })
            .configure({ brain: "a", ...settings });
    };
    for (const home of [{ kind: "none" }, homeAt("whole", "persona")]) assert.deepEqual(withHome(home, {}, true), { kind: "ready", cautions: [] }, home.kind);
    for (const [name, home, cautions] of [
        ["AGENTS.md", homeAt("large", "x".repeat(8193)), ["guidance=agents-over-budget"]],
        ["MEMORY.md", homeAt("memory-large", "persona", "m".repeat(4097)), ["guidance=memory-over-budget"]]]) {
        assert.deepEqual(withHome(home, {}, true), { kind: "ready", cautions }, name + " over its budget leaves the engine ready");
        assert.deepEqual(withHome(home, { brain: "" }, false), { kind: "unconfigured", cause: "speech=fixture-off",
            causes: ["speech=fixture-off", "brain=unselected"], cautions }, name + " over its budget beside the other steps' causes");
    }
    for (const [home, cause] of [[{ kind: "refused", cause: "home=link" }, "home=link"], [homeAt("many", "persona", "", 257), "guidance=home-skills-too-large"]]) {
        assert.deepEqual(withHome(home, {}, true), { kind: "unconfigured", cause, causes: [cause], cautions: [] }, cause);
        assert.deepEqual(withHome(home, { brain: "" }, false), { kind: "unconfigured", cause, causes: [cause, "speech=fixture-off", "brain=unselected"], cautions: [] },
            cause + " leads every other step's cause");
    }
    assert.throws(() => withHome({ kind: "other" }, {}, true), { message: "jarvis: engine=home-state" });
    // A subscription's program chooses its own model; its account names its directory.
    for (const [provider, directory] of [["codex", "/home/fixture/.codex"], ["claude", "/home/fixture/.claude"]])
        assert.deepEqual(configure({}, accepted({ id: "c", provider, label: "default",
            source: { kind: "cli", directory }, model: "" }), true), { kind: "ready", cautions: [] }, provider);
}

// The brain plan's model and effort: the saved pair, else the choice
// AccountProviders.unlistedChoice makes for the provider of the account the
// daemon resolved, which a hello sent before the account reader's first
// answer could not make. The copy's engine also answers its plan.
const PLAN = ["        homeHeld: () => homeHeld,", "        homeHeld: () => homeHeld,\n        plan: () => plan,"];
function brainPlan(Engine) {
    const accepted = (provider, source) => () => ({ kind: "accepted", account: { id: "a", provider, label: "fixture", source, model: "" } });
    const key = accepted("anthropic", { kind: "keyring", reference: { provider: "anthropic", account: "fixture", origin: "https://api.anthropic.com" } });
    const claude = accepted("claude", { kind: "cli", directory: "/home/fixture/.claude" });
    const codex = accepted("codex", { kind: "cli", directory: "/home/fixture/.codex" });
    for (const [label, choose, saved, want] of [
        ["an Anthropic key and nothing saved", key, {}, ["claude-opus-5-5", "high"]],
        ["an Anthropic key and an effort saved alone", key, { effort: "max" }, ["claude-opus-5-5", "max"]],
        ["an Anthropic key and a saved model", key, { model: "claude-haiku-4-5" }, ["claude-haiku-4-5", ""]],
        ["Claude Code and nothing saved", claude, {}, ["claude-fable-5-1", "high"]],
        ["Claude Code and a saved model and effort", claude, { model: "claude-opus-5-5", effort: "max" }, ["claude-opus-5-5", "max"]],
        ["Codex and nothing saved", codex, {}, ["", ""]]]) {
        Fixture.reset({ ready: true });
        const engine = Engine.create({ accounts: () => ({ secrets: null, choose }), captionLimit: 1 });
        assert.deepEqual(engine.configure({ brain: "a", model: "", effort: "", ...saved }), { kind: "ready", cautions: [] }, label);
        assert.deepEqual([engine.plan().brain.model, engine.plan().brain.effort], want, label);
    }
}

// The trace's own rules, at the engine's creation: only the test-run marker
// with an absolute path makes the file, the run's own and never a link's
// target.
function tracePaths(Engine) {
    const folder = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "trace-paths-"));
    const open = trace => Engine.create({ captionLimit: 1, trace });
    for (const marker of [undefined, "", "0", "true"]) {
        open({ marker, file: path.join(folder, "unmarked") }).close();
        assert.equal(fs.existsSync(path.join(folder, "unmarked")), false, "marker " + JSON.stringify(marker) + " writes no file");
    }
    open({ marker: "1" }).close();
    assert.throws(() => open({ marker: "1", file: path.relative(process.cwd(), path.join(folder, "relative")) }),
        { message: "jarvis: engine=trace-path" });
    fs.writeFileSync(path.join(folder, "other"), "kept");
    fs.symlinkSync(path.join(folder, "other"), path.join(folder, "link"));
    assert.throws(() => open({ marker: "1", file: path.join(folder, "link") }), { message: "jarvis: engine=trace-open cause=ELOOP" });
    assert.throws(() => open({ marker: "1", file: path.join(folder, "absent/brain.jsonl") }), { message: "jarvis: engine=trace-open cause=ENOENT" });
    // The mode is the engine's own, whatever the caller's mask allows.
    const mask = process.umask(0);
    try { open({ marker: "1", file: path.join(folder, "made") }).close(); } finally { process.umask(mask); }
    assert.equal(fs.statSync(path.join(folder, "made")).mode & 0o777, 0o600, "the trace is the owner's alone");
}

// The real engine with only its sidecar boundary replaced. No child,
// device or brain starts; final detector completion follows sink close.
async function checkFailures(file) {
    const actual = require("node:module").createRequire(path.join(tree, "shell/plugins/vgs.jarvis/backend/ChainedEngine.js"));
    for (const closeFirst of [false, true]) {
        let finish;
        const outcome = new Promise(resolve => { finish = resolve; });
        const owner = { status: () => ({ kind: "ready" }), closed: new Promise(() => {}),
            spot: () => ({ outcome }), close() {} };
        const local = { row: { select: () => ({ kind: "ready", lifetime: "daemon", wake: true,
            recipients: [], voices: [{ label: "Fixture", value: "fixture" }], open: () => owner }) } };
        const exported = { exports: {} };
        vm.runInNewContext(fs.readFileSync(file, "utf8"), { module: exported, Buffer, setTimeout, clearTimeout,
            require: name => name === "./LocalSpeech.js" ? local : actual(name) });
        const events = [];
        const engine = exported.exports.create({ captionLimit: 1, dispatch: e => events.push(e) });
        engine.configure({ brain: "" });
        const identity = { mode: "check", gen: 1, op: 2 };
        const sink = engine.captureSink(identity);
        try {
            if (closeFirst) sink.destroy();
            finish({ kind: "failed", error: Object.assign(new Error("jarvis: speech=local-wake-failed"), { code: "wake-failed" }) });
            await outcome;
            assert.deepEqual(JSON.parse(JSON.stringify(events)), [{ type: "voice-check-failed", gen: 1, op: 2,
                reason: "speech=local-wake-failed" }], "check failure reaches Session after capture close");
        } finally { sink.destroy(); engine.close(); }
    }
}


async function runGroupWithServer(name, run) {
    const root = process.env.JARVIS_TEST_ROOT;
    const server = Fixture.brain(PORT);
    await server.ready;
    try {
        const controls = await run(root, server);
        console.log("test-jarvis-engine: ok group=" + name + " requests=" + server.requests.length + " controls=" + controls);
        return { controls, requests: server.requests.length };
    } finally { await server.close(); }
}

// The real Accounts judge and local server catalog during engine configure.
// The LM Studio port is free beside this suite's Ollama inference fixture.
async function localCatalog(kit, root, only) {
    const { Accounts } = require(path.join(kit.folder, "backend/Accounts.js"));
    const env = require("./fixtures/jarvis/accounts-world.js").environment();
    const directory = fs.mkdtempSync(path.join(root, "catalog-"));
    const audit = require(path.join(kit.folder, "backend/Audit.js")).create({ state: directory });
    const judge = new Accounts(directory, env);
    const local = judge.localRows().find(item => item.row.id === "lm-studio");
    const id = judge.account(local.row, local.label, { kind: "found" }, local.source).id;
    let reply, requests = [];
    const server = http.createServer((request, response) => {
        assert.equal(request.method, "GET");
        assert.equal(request.url, "/v1/models");
        const closed = gate();
        response.once("close", closed.open);
        requests.push({ response, closed });
        if (reply.hold) return;
        response.writeHead(reply.status ?? 200, { "content-type": "application/json" });
        response.end(JSON.stringify({ data: reply.data ?? [{ id: "fixture-model" }] }));
    });
    await new Promise(resolve => server.listen(local.row.port, "127.0.0.1", resolve));
    try {
        for (const row of [
            { name: "missing", model: "", cause: "brain=model-required", count: 0 },
            { name: "chosen", model: "fixture-model", kind: "ready" },
            { name: "unknown", model: "absent", cause: "brain=model-unavailable" },
            { name: "empty", model: "fixture-model", data: [], cause: "brain=model-unavailable" },
            { name: "failed", model: "fixture-model", status: 503, cause: "brain=models-unavailable" },
            { name: "recovered", model: "fixture-model", status: 503, cause: "brain=models-unavailable", recover: true },
            { name: "backup", model: "absent", fallbacks: [{ brain: id, model: "fixture-model" }], kind: "ready" },
            { name: "reconfigure", model: "fixture-model", hold: true },
            { name: "account-change", model: "fixture-model", hold: true, accountChange: true },
            { name: "unchanged-pending", model: "fixture-model", hold: true, identical: true },
            { name: "close", model: "fixture-model", hold: true }
        ].filter(row => only === undefined || row.name === only)) {
            Fixture.reset({ ready: true });
            reply = row;
            const observed = [], faults = [];
            const engine = kit.Engine.create({ accounts: () => judge, captionLimit: 1, audit,
                configured: value => observed.push(value), fatal: error => faults.push(error) });
            const count = requests.length;
            try {
                const answer = engine.configure({ brain: id, model: row.model, effort: "", fallbacks: row.fallbacks ?? [] });
                if (row.count === 0) {
                    assert.deepEqual(answer, { kind: "unconfigured", cause: row.cause, causes: [row.cause], cautions: [] });
                    assert.equal(requests.length, count);
                    assert.equal(engine.modelsHeld(), false);
                    continue;
                }
                assert.equal(answer.cause, "brain=models-reading");
                assert.equal(engine.modelsHeld(), false, "a read in flight is not restarted by Talk");
                await until(() => requests.length === count + 1 || faults.length !== 0, "one account catalog read");
                assert.equal(faults.length, 0, "catalog reads use the existing audit writer");
                if (row.hold) {
                    if (row.identical) {
                        assert.equal(engine.configure({ brain: id, model: row.model, effort: "" }).cause, "brain=models-reading");
                        assert.equal(requests.length, count + 1, "an identical hello keeps the same catalog operation");
                    }
                    if (row.name === "close") engine.close();
                    else if (row.accountChange) assert.equal(engine.configure({ brain: "", model: row.model, effort: "" }).cause, "brain=unselected");
                    else assert.equal(engine.configure({ brain: id, model: "", effort: "" }).cause, "brain=model-required");
                    let closed = false;
                    void requests.at(-1).closed.wait.then(() => { closed = true; });
                    await until(() => closed, "close and reconfigure abort the catalog connection");
                    // Complete the aborted request's promise callbacks before
                    // judging publication. This waits on the event queue, not time.
                    await new Promise(resolve => setImmediate(resolve));
                    assert.deepEqual(observed, [], "an obsolete catalog answer cannot publish setup");
                } else {
                    await until(() => observed.length !== 0 || faults.length !== 0, "catalog answers configure");
                    assert.equal(faults.length, 0);
                    if (row.kind === "ready") {
                        assert.deepEqual(observed.at(-1), { kind: "ready", cautions: [] });
                        assert.equal(engine.plan().brain.model, "fixture-model");
                        assert.deepEqual(engine.configure({ brain: id, model: row.model, effort: "", fallbacks: row.fallbacks ?? [] }),
                            { kind: "ready", cautions: [] }, "an identical hello preserves admitted model readiness");
                    } else assert.deepEqual(observed.at(-1), { kind: "unconfigured", cause: row.cause, causes: [row.cause], cautions: [] });
                    assert.equal(requests.length, count + 1, "a primary and backup on one server share their read");
                    assert.equal(engine.modelsHeld(), row.kind !== "ready");
                    if (row.recover) {
                        reply = {};
                        const daemon = fs.readFileSync(path.join(kit.folder, "backend/jarvisd.js"), "utf8");
                        const rule = [...daemon.matchAll(/^ *(if \(\(message\.intent === "talk-down" \|\| message\.intent === "say"\) && [^\n]*judgeSetup\(\);)$/gm)];
                        assert.equal(rule.length, 1);
                        vm.runInNewContext(rule[0][1], { message: { intent: "talk-down" }, engine,
                            judgeSetup: () => engine.configure({ brain: id, model: row.model, effort: "" }) });
                        await until(() => observed.length === 2, "Talk reads the recovered catalog");
                        assert.deepEqual(observed.at(-1), { kind: "ready", cautions: [] });
                        assert.equal(engine.plan().brain.model, "fixture-model");
                        assert.equal(engine.modelsHeld(), false);
                    }
                }
                assert.equal(faults.length, 0);
            } finally { engine.close(); }
        }
    } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); audit.close(); }
}

async function groupSelection(root, server) {
    let controls = 0;
    // Without local setup's marker the stock table's local row is the cause.
    const stock = require(path.join(tree, "shell/plugins/vgs.jarvis/backend/ChainedEngine.js"));
    const bare = fs.mkdtempSync(path.join(root, "stock-"));
    assert.deepEqual(stock.create({ accounts: () => ({ secrets: null, choose: () => ({ kind: "refused", cause: "account-unavailable" }) }),
        captionLimit: 1, directories: { state: bare, data: bare, runtime: bare } }).configure({ brain: "a" }),
    { kind: "unconfigured", cause: "speech=local-not-set-up", causes: ["speech=local-not-set-up", "brain=account-unavailable"], cautions: [] },
    "the stock daemon stays unconfigured and judges the brain too");
    const file = path.join(tree, "shell/plugins/vgs.jarvis/backend/ChainedEngine.js");
    await checkFailures(file);
    const original = fs.readFileSync(file, "utf8");
    const needle = 'result.kind === "failed" && e.mode === "check"';
    assert.equal(original.split(needle).length, 2, "one check failure dispatch rule");
    const mutantRoot = fs.mkdtempSync(path.join(root, "jarvis-check-failure-"));
    try {
        const mutant = path.join(mutantRoot, "closed-check-failure.js");
        fs.writeFileSync(mutant, original.replace(needle, needle + " && !sink.destroyed"));
        await assert.rejects(() => checkFailures(mutant), assert.AssertionError,
            "dropping a closed capture failure turns the check red");
    } finally { fs.rmSync(mutantRoot, { recursive: true, force: true }); }
    console.log("control=closed-check-failure detected");
    controls++;
    // A wait that never observes fails typed; one that settles on another
    // state fails its own assertion, so a control names which it met.
    await assert.rejects(wait(() => false, "unobserved", 20), { operator: "until" });
    await assert.rejects(settled(() => false, () => true, "settled elsewhere"), error => error.operator === "==");
    selection(Fixture.copy(root).Engine);
    await localCatalog(Fixture.copy(root, [PLAN]), root);
    for (const [name, needle, replacement, scenario] of [
        ["local-model-configured", 'judge.choose(id, model ?? settings.model ?? "", models(id))', 'judge.choose(id, "", models(id))', "chosen"],
        ["local-catalog-read", "            readModels(plan.modelLists);", "", "chosen"],
        ["local-catalog-audit", "account.readOffers(id, read.stop.signal, audit)", "account.readOffers(id, read.stop.signal)", "chosen"],
        ["local-catalog-cancel", "        for (const read of modelReads.values()) read.stop.abort();", "", "reconfigure"],
        ["local-catalog-stale", "                if (closed || modelReads.get(id) !== read) return;\n                read.answer = answer;", "                read.answer = answer;", "reconfigure"],
        ["local-catalog-held", 'return plan.kind === "unconfigured" && plan.causes.some(cause => cause === "brain=models-unavailable" || cause === "brain=model-unavailable");',
            'return false;', "recovered"],
        ["local-catalog-unchanged", "if (identity !== modelsFor || modelsHeld()) cancelModels();", "cancelModels();", "chosen"],
        ["local-catalog-close", "            cancelModels();\n            voiceList.net?.close();", "            voiceList.net?.close();", "close"]
    ]) {
        await assert.rejects(() => localCatalog(Fixture.copy(root, [PLAN, [needle, replacement]]), root, scenario),
            assert.AssertionError, name + " must turn red");
        console.log("control=" + name + " detected");
        controls++;
    }
    const catalogRetry = Fixture.copy(root, [PLAN]);
    const daemonFile = path.join(catalogRetry.folder, "backend/jarvisd.js");
    const daemonSource = fs.readFileSync(daemonFile, "utf8");
    const retryNeedle = " || engine.modelsHeld()";
    assert.equal(daemonSource.split(retryNeedle).length - 1, 1);
    fs.writeFileSync(daemonFile, daemonSource.replace(retryNeedle, ""));
    await assert.rejects(() => localCatalog(catalogRetry, root, "recovered"), assert.AssertionError, "local-catalog-talk must turn red");
    console.log("control=local-catalog-talk detected");
    controls++;
    const borrowedAudit = Fixture.copy(root, [PLAN]);
    const accountFile = path.join(borrowedAudit.folder, "backend/Accounts.js");
    const accountSource = fs.readFileSync(accountFile, "utf8");
    const auditClose = "if (ownsAudit) audit.close();";
    assert.equal(accountSource.split(auditClose).length - 1, 1);
    fs.writeFileSync(accountFile, accountSource.replace(auditClose, "audit.close();"));
    await assert.rejects(() => localCatalog(borrowedAudit, root, "recovered"), assert.AssertionError,
        "local-catalog-borrowed-audit must turn red");
    console.log("control=local-catalog-borrowed-audit detected");
    controls++;
    brainPlan(Fixture.copy(root, [PLAN]).Engine);
    assert.throws(() => brainPlan(Fixture.copy(root, [PLAN, ["unlistedChoice(settings, account.provider);",
        "{ model: settings.model, effort: settings.effort };"]]).Engine), assert.AssertionError, "brain-plan-unlisted must turn red");
    console.log("control=brain-plan-unlisted detected");
    controls++;
    for (const [name, needle, replacement = ""] of [
        ["speech-first", "const failing = [speech, dictation, brain]", "const failing = [brain, dictation, speech]"],
        ["home-step", "        plan = held.plan;\n"],
        ["home-cautions", "        cautions = held.cautions;\n"],
        ["ready-cautions", 'return { kind: "ready", cautions };', 'return { kind: "ready" };'],
        ["home-refused", 'case "refused": cause = home.cause; break;', 'case "refused": break;'],
        ["home-text-judged", 'try { cautions = Guidance.compose("chained", "local", LANGUAGE, home.path).overBudget; }', "try { void home.path; }"],
        ["home-first", 'causes: [cause, ...(plan.kind === "ready" ? [] : plan.causes)]', 'causes: [...(plan.kind === "ready" ? [] : plan.causes), cause]'],
        ["home-state", 'default: fail("home-state");', "default: break;"],
        ["every-cause", "causes: failing.map(step => step.cause)", "causes: [failing[0].cause]"],
        ["first-speech-cause", 'if (speech.cause === "speech=no-adapter") speech = answer;'],
        ["accounts-unreadable", 'return primary ? unconfigured("brain=accounts-unreadable", error.message) : null;'],
        ["unselected", 'if (id === "") return primary ? unconfigured("brain=unselected") : null;'],
        ["refused-cause", 'return primary ? unconfigured("brain=" + choice.cause) : null;', 'return primary ? unconfigured("brain=account-unavailable") : null;'],
        ["harness-driver", '"codex-app-server": CodexHarness, '],
        ["claude-driver", ', "claude-code": ClaudeCode });', " });"],
        ["always-any-voice", 'settings.mode === "always" && (', "false && ("],
        ["always-live-voice", 'Object.hasOwn(DUPLEX, settings.voiceProvider) || speech.kind', "speech.kind"],
        ["always-gemini-voice", '    gemini: Object.freeze({ id: "gemini-live", account: "gemini", adapter: GeminiLive })\n', ""],
        ["always-wake-row", ' && speech.wake !== true))', "))"]]) {
        const { Engine } = Fixture.copy(root, [[needle, replacement]]);
        assert.throws(() => selection(Engine), assert.AssertionError, name + " must turn red");
        console.log("control=" + name + " detected");
        controls++;
    }
    tracePaths(Fixture.copy(root).Engine);
    const classifier = Fixture.copy(root).Engine.failoverCause;
    for (const cause of ["brain=stream-failed", "brain=stream-truncated", "brain=stream-error", "net=request", "brain=http status=502", "brain=harness-api-error status=403",
        "brain=harness-api-error status=429", "brain=harness-model-refused model=fable",
        "brain=harness-exit code=1", "brain=codex-exited code=1 signal=null", "brain=copilot-signed-out"])
        assert.equal(classifier(cause), true, cause);
    for (const cause of ["brain=refusal", "brain=finish reason=content-filter",
        "brain=context-limit", "brain=harness-tool name=bad"])
        assert.equal(classifier(cause), false, cause);
    for (const [name, needle, replacement] of [
        ["trace-unmarked", 'if (trace.marker !== "1" || trace.file === undefined) return null;', "if (trace.file === undefined) return null;"],
        ["trace-relative", 'if (typeof trace.file !== "string" || !path.isAbsolute(trace.file)) fail("trace-path");', ""],
        ["trace-link", "O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o600", "O_WRONLY | O_APPEND | O_CREAT, 0o600"],
        ["trace-open-cause", 'catch (error) { failed("open", error); }', "catch (error) { throw error; }"],
        ["trace-mode", "O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o600", "O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o644"]]) {
        const { Engine } = Fixture.copy(root, [[needle, replacement]]);
        assert.throws(() => tracePaths(Engine), assert.AssertionError, name + " must turn red");
        console.log("control=" + name + " detected");
        controls++;
    }
    await cases(Fixture.copy(root), server);
    for (const [name, needle, replacement] of [
        ["home-text-stale", "try { return c.plan.brain.guidance.withHome(folder); }", "try { return c.plan.brain.guidance; }"],
        ["home-text-cut", '            done("brain-failed", { reason: keyed(error) });\n            return false;\n', "            c.guidance = c.plan.brain.guidance;\n"]
    ]) {
        await assert.rejects(() => cases(Fixture.copy(root, [[needle, replacement]]), server, "home-text"), assert.AssertionError,
            name + " must turn home-text red");
        console.log("control=" + name + " detected");
        controls++;
    }
    {
        // The refusal for size Guidance no longer makes: a MEMORY.md over its
        // budget refused whole holds the engine and fails the turn.
        const kit = Fixture.copy(root);
        const file = path.join(kit.folder, "backend/Guidance.js");
        const needle = 'const memory = whole("memory/MEMORY.md", MEMORY_BUDGET, "guidance=memory-over-budget");';
        const source = fs.readFileSync(file, "utf8");
        assert.equal(source.split(needle).length - 1, 1, "home-memory-refusal mutation match");
        fs.writeFileSync(file, source.replace(needle, needle + '\n    if (Buffer.byteLength(memory) > MEMORY_BUDGET) throw new Error("jarvis: guidance=home-memory-too-large");'));
        // The copy's engine loaded Guidance already: load both again.
        const engineFile = path.join(kit.folder, "backend/ChainedEngine.js");
        delete require.cache[file];
        delete require.cache[engineFile];
        kit.Engine = require(engineFile);
        assert.throws(() => selection(kit.Engine), assert.AssertionError, "home-memory-refusal must turn selection red");
        await assert.rejects(() => cases(kit, server, "home-text"), assert.AssertionError, "home-memory-refusal must turn home-text red");
        console.log("control=home-memory-refusal detected");
        controls++;
    }
    assert.deepEqual(server.faults, [], "selection requests matched the pinned schema");
    return controls + await keyRefusedGroup(root);
}

async function groupDaemonSpeech(root, server) {
    let controls = 0;
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
    await localSetupRun(server);
    for (const [name, edits] of [
        ["setup answers before the sidecar exits", [["owner.closed.then(() => undefined)", "Promise.resolve()"]]],
        ["setup keeps the conversation", [["            configured(configuration());\n            owner?.close();", "            owner?.close();"]]],
        ["setup run starts a sidecar", [["            speechState = { kind: \"unloaded\" };", "            speechState = { kind: \"new\" };"],
            ["        if (setup !== null) fail(\"local-setting-up\");\n        speechState = { kind: \"starting\" };", "        speechState = { kind: \"starting\" };"]]],
        ["setup end starts nothing", [["                speechState = { kind: \"new\" };\n                rejudge();\n", "                speechState = { kind: \"new\" };\n"]]]
    ]) {
        await assert.rejects(() => localSetupRun(server, edits), assert.AssertionError, name + " control must fail");
        console.log("control=" + name + " detected");
        controls++;
    }
    for (const [name, edits] of [
        ["ready before model load", [['speechState.kind === "new" || published) startSpeech(plan.speech);', 'false) startSpeech(plan.speech);']]],
        ["new arguments keep the sidecar", [['|| speechState.kind === "new" || speechIdentity === plan.speech.identity) return;', '|| true) return;']]],
        ["replaced sidecar kept", [['        daemonSpeech?.close();\n        startSpeech(plan.speech);\n    }', '        startSpeech(plan.speech);\n    }']]],
        ["restart under a conversation", [['if (closed || conversation !== null || plan.speech', 'if (closed || plan.speech']]],
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
    assert.deepEqual(server.faults, [], "daemon-speech requests matched the pinned schema");
    return controls;
}

async function groupDaemonLoading(root, server) {
    let controls = 0;
    for (const ending of ["ready", "stop", "mute", "lock", "lease", "fault", "locked", "muted", "missing", "brain", "device", "check-ready", "check-silent", "check-not-heard"])
        await loadingTalk(server, ending);
    for (const ending of ["ready", "refused", "unset"]) await alwaysTalk(server, ending);
    for (const [name, file, needle, replacement] of [
        ["wake sink removed", "backend/ChainedEngine.js", '            if (e.mode === "armed" || e.mode === "check") return spotting(e);\n', ""],
        ["wake not dispatched", "backend/ChainedEngine.js", 'else if (result.kind === "woke") dispatch({ type: "wake", gen: e.gen, op: e.op });', "else void result;"],
        ["Always refusal removed", "backend/ChainedEngine.js", 'settings.mode === "always" && (settings.voiceProvider', 'false && (settings.voiceProvider']
    ]) {
        await assert.rejects(() => alwaysTalk(server, name === "Always refusal removed" ? "refused" : "ready", [[file, needle, replacement]]),
            assert.AssertionError, name);
        console.log("control=" + name + " detected");
        controls++;
    }
    for (const [name, file, needle, replacement] of [
        ["loading admission removed", "backend/jarvisd.js", ' || configuration.kind === "loading"', ""],
        ["loading ready too early", "backend/ChainedEngine.js", 'return { kind: "loading", cause: "speech=local-loading", causes: ["speech=local-loading"], cautions };', 'return { kind: "ready", cautions };'],
        ["loading ignores presented indicator", "Session.js", 's.indicator.kind === "shown"', "true"],
        ["loading starts a second child", "backend/ChainedEngine.js", 'if (plan.speech.lifetime === "daemon" && daemonSpeech === null) startSpeech(plan.speech);', 'if (plan.speech.lifetime === "daemon") startSpeech(plan.speech);'],
        ["replacement loading unpublished", "backend/ChainedEngine.js", 'daemonSpeech = owner;\n        configured(configuration());', 'daemonSpeech = owner;'],
        ["ready timeout reads ready", "backend/ChainedEngine.js", ' || (speechState.kind === "starting" && error.code === "ready-timeout")', ""],
        ["loading cancellation replays", "backend/ChainedEngine.js", '            if (utterance) utterance.abort();', '            void utterance;']
    ]) {
        const ending = name === "loading cancellation replays" ? "stop" : name === "replacement loading unpublished" ? "fault" : name === "ready timeout reads ready" ? "held" : "ready";
        await assert.rejects(() => loadingTalk(server, ending, [[file, needle, replacement]]), assert.AssertionError, name);
        console.log("control=" + name + " detected");
        controls++;
    }
    assert.deepEqual(server.faults, [], "daemon-loading requests matched the pinned schema");
    return controls;
}

async function groupPlants(root, server) {
    let controls = 0;
    // Each control plants one defect in a disposable engine copy.
    const plants = [
        ["start-earcon-silenced", 'pcm.writeInt16LE(Math.round(3900 * envelope * Math.sin(2 * Math.PI * frequency * frame / PCM_RATE)), frame * 2);',
            'pcm.writeInt16LE(0, frame * 2);', "feedback-start"],
        ["working-earcon-silenced", 'c.turn.speech.readable.push(earcon("working"));',
            'c.turn.speech.readable.push(Buffer.alloc(5760));', "feedback-working"],
        ["feedback-text-suppression", "                        quiet(turn);\n                        say(c, turn, sentence);", "                        say(c, turn, sentence);", "feedback-suppressed-text"],
        ["feedback-tool-suppression", 'case "done":\n                    quiet(turn);',
            'case "done":\n                    void turn;', "feedback-suppressed-tool"],
        ["acknowledgement", 'line(c, turn, Speakable.acknowledgement(e.text), ["speech"]);',
            '', "spoken-lines"],
        ["step-drain", "for (const step of stream.steps()) {",
            "for (const step of []) {", "spoken-lines"],
        ["progress-threshold", "const PROGRESS_AFTER_MS = 4000;", "const PROGRESS_AFTER_MS = 0;", "progress-short-request"],
        ["progress-repeat", 'if (key === "" || turn.lines.has(key)) return false;',
            'if (key === "") return false;', "progress-repeat"],
        ["progress-one-waits", "                turn.waitingLine = { text, labels };\n                return true;",
            "                turn.waitingLine = null;\n                return true;", "progress-one-waits"],
        ["progress-secret", "if (turn.stopped || turn.speaking || turn.replyStarted || Redact.secret(text)) return false;",
            "if (turn.stopped || turn.speaking || turn.replyStarted) return false;", "spoken-lines-secret"],
        ["progress-timer-labels", "if (turn.step !== null) line(c, turn, turn.step, [...turn.labels]);",
            'if (turn.step !== null) line(c, turn, turn.step, ["speech"]);', "progress-line-labels-timer"],
        ["progress-late-labels", "if (turn.progressDue) line(c, turn, step, [...turn.labels]);",
            'if (turn.progressDue) line(c, turn, step, ["speech"]);', "progress-line-labels-late"],
        ["line-feedback", 'turn.done("feedback", { cue: "line" });',
            'turn.done("feedback");', "spoken-lines"],
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
        ["full-reply-heard", 'heard(c, turn, report === null || flushedLine ? "" : withoutLinePrefix(turn, report.heardText));',
            'heard(c, turn, "Hello there. The time is noon.");', "barge-in"],
        ["cancel-heard", '            if (c.live === null && turn.relay === null) heard(c, turn, "");\n', "", "cancel-thinking"],
        ["partial-to-brain", 'utterance.collection?.done("partial", event.text);', 'utterance.collection?.done("final", event.text);', "turn-loop"],
        ["tool-names-spoken", "const text = Speakable.create(LANGUAGE, { tools: TOOL_NAMES });", "const text = Speakable.create(LANGUAGE, { tools: [] });", "brain-trace"],
        ["trace-not-written", "                    brainText?.write(turn, event.text);\n", "", "brain-trace"],
        ["trace-after-speakable", "brainText?.write(turn, event.text);", "for (const sentence of Speakable.create(LANGUAGE).push(event.text)) brainText?.write(turn, sentence);", "brain-trace"],
        ["unlabelled-frames", 'return { value: Policy.item(chunk, ["speech"]), done: false };',
            'return { value: Policy.item(chunk, ["desktop"]), done: false };', "turn-loop"],
        ["result-identity", 'if (turn !== null && turn.op === value.op && turn.phase === "routing" && turn.routing?.id === id) {',
            "if (turn !== null) {", "stale-outcome"],
        ["interrupted-answers", "if (routing && c.brain !== null) c.brain.record(", "if (false) c.brain.record(", "stale-outcome"],
        ["not-started", 'return router.interrupted(call, "not-started");', 'return router.interrupted(call, "running");', "stale-outcome"],
        ["late-result", "c.results.push(lateItem(late.call, value.outcome, item));", "void lateItem;", "stale-outcome"],
        ["fleet-line-absent", '{ "fleet.request": { completed: "Asking Jarvis\'s session." } }', "{}", "fleet-request-completed-silent"],
        ["fleet-line-repeated", "        if (turn.fixed?.has(normalizedLine(sentence))) return;\n", "", "fleet-request-completed-echo"],
        ["fast-match", "? null : Tools.match(e.text);", "? null : null;", "fast-path"],
        ["fast-account", "c.results.push(fastAccount(turn.fast.e.text, call, outcome, item));", "", "fast-path"],
        ["fast-fallthrough", "if (!Object.hasOwn(FAST_LINES, outcome)) {", "if (false) {", "fast-path-refused"],
        ["fast-late-account", "if (late.fast !== undefined) c.results.push(", "if (false) c.results.push(", "fast-path-interrupted"],
        ["fast-proposer", ', proposer: "matcher" };', " };", "fast-path"],
        ["fast-heard", "        if (turn.fast !== undefined) return;\n", "", "fast-path-barge-in"],
        ["fast-late", 'if (turn.phase === "fast" && turn.routing !== null) c.late.set(', "if (false) c.late.set(", "fast-path-interrupted"],
        ["history-taint", "router.observe(turn, reply.release.labels);", "void reply;", "history-taint"],
        ["toggle-adoption", 'c.unbound !== null && c.unbound.state === "running" ? c.unbound : null',
            "c.unbound", "toggle-turns"],
        ["toggle-detection", 'transcribe(frames, { detect: e.mode !== "hold" })',
            'transcribe(frames, { detect: false })', "toggle-turns"],
        ["collect-failure", "else if (collecting(c, utterance.collection)) utterance.collection.failed(keyed(error));",
            "else if (false) utterance.collection.failed(keyed(error));", "transcribe-failure"],
        ["speech-gates-brain", 'if (event.reason === "tool-calls") next(c, turn);\n                    else {\n                        clearProgress(turn);\n                        turn.phase = "done";\n                        c.turn = null;\n                        turn.speech?.end();\n                        concluded(c, turn);',
            'if (event.reason === "tool-calls") next(c, turn);\n                    else {\n                        clearProgress(turn);\n                        turn.phase = "done";\n                        c.turn = null;\n                        turn.speech?.end();\n                        await new Promise(resolve => turn.speech.readable.once("close", resolve));\n                        concluded(c, turn);', "long-speech"],
        ["net-not-closed", "        c.retired.clear();\n        c.net.close();\n        retired = { gen: c.gen, closed: quiet };",
            "        c.retired.clear();\n        retired = { gen: c.gen, closed: quiet };", "conversation-end"],
        ["observe-teardown", "if (conversation !== null && (s.gen !== conversation.gen || s.conversation.kind === \"ended\")) end();", "void s;", "settings-change"],
        ["follow-up-abort", '            if (conversation?.collection !== null && conversation?.collection !== undefined\n                    && !collecting(conversation, conversation.collection)) {\n                conversation.collection.utterance?.abort();\n                conversation.collection = null;\n            }\n',
            "", "follow-up-close-aborts"],
        ["after-tool-rule", "...(after === null ? {} : { instructions: after }),", "", "tool-round"],
        ["image-answer", "turn.answers.set(id, image === undefined ? { item } : { item, image });", "turn.answers.set(id, { item });", "screen-image"],
        ["images-ready", 'return current.kind === "ready" && current.brain.provider.images;', "return true;", "screen-image"],
        ["context-clean-end", 'turn.done(reason === "brain=context-limit" ? "brain-ended" : "brain-failed", { reason });',
            'turn.done("brain-failed", { reason });', "context-bound"],
        ["readable-backpressure", "if (!readable.push(step.value)) await wanted.wait();", "readable.push(step.value);", "backpressure"],
        ["partial-revision", "event.rev <= rev", "false", "partial-revision"],
        ["end-aborts-transcription", "            if (utterance) utterance.abort();", "            void utterance;", "mute-capture"],
        ["caption-revision", "rev: ++c.rev", "rev: 1", "turn-loop"],
        ["caption-before-release", "        transfer(c, turn, item, () => {\n            if (turn.speech === null) {",
            "        caption(c, turn, sentence);\n        transfer(c, turn, item, () => {\n            if (turn.speech === null) {", "audit-refusal-speech"],
        ["audit-skipped", '"pending"), start);\n        if (result.kind !== "started") fail("audit-write");\n        return result.value;',
            '"pending"), () => {});\n        void result;\n        return start();', "audit-refusal-line"],
        ["caption-dropped", "        caption(c, turn, sentence);\n", "", "turn-loop"],
        ["caption-final", 'else {\n                        clearProgress(turn);\n                        turn.phase = "done";\n                        c.turn = null;\n                        turn.speech?.end();\n                        concluded(c, turn);\n                        turn.done("brain-done");',
            'else {\n                        clearProgress(turn);\n                        turn.phase = "done";\n                        c.turn = null;\n                        turn.speech?.end();\n                        turn.done("brain-done");', "turn-loop"],
        ["caption-separator", "        if (turn.caption.length + 1 >= captionLimit) concluded(c, turn);\n", "", "caption-segments"],
        ["caption-bound", "const room = captionLimit - turn.caption.length;", "const room = Infinity;", "caption-segments"],
        ["caption-failure-final", "        concluded(c, turn);\n        const reason = keyed(error);", "        const reason = keyed(error);", "caption-segments"],
        ["speakable-bypass", "for (const sentence of sentences) {\n                        quiet(turn);\n                        say(c, turn, sentence);\n                    }",
            "say(c, turn, event.text);", "turn-loop"],
        ["feedback-silenced-text-cancels", "for (const sentence of sentences) {\n                        quiet(turn);",
            "quiet(turn);\n                    for (const sentence of sentences) {", "feedback-silenced-text"],
        ["feedback-disable-stream", 'turn.speech = null;\n            }\n            if (s.playback.kind',
            'void turn.speech;\n            }\n            if (s.playback.kind', "feedback-disable-working"],
        ...["action", "release"].map(purpose => ["feedback-approval-stream-" + purpose,
            's.settings.sounds !== true || s.approval.kind === "held"', 's.settings.sounds !== true',
            "feedback-voice-" + purpose]),
        ["feedback-flush-heard-context", "const speaking = turn?.speaking === true;",
            "const speaking = c !== null && c !== undefined;", "feedback-delayed-flush"],
        ["line-refused-retry", "if (c.live === null && turn.lineStream !== null) {",
            "if (c.live === null && (turn.lineStream !== null || turn.pendingLine !== null)) {", "progress-after-refused-line"],
        ["line-flush-heard", 'report === null || flushedLine ? "" : withoutLinePrefix', 'report === null ? "" : withoutLinePrefix', "line-held-reply-interrupt"],
        ["preview-speaker", ".speak(sentenceInput, speaker ?? c.plan.speech.speaker)", '.speak(sentenceInput, "fixture")', "voice-preview"],
        ["preview-unspoken", "fixedLine(c, turn, PREVIEW_LINE);", 'turn.done("brain-done");', "voice-preview"],
        ["dictation-reply-dropped", 'settle(ok(result) ? { kind: "text", text: result.data.text }',
            'settle(ok(result) ? { kind: "text", text: "" }', "dictation-hold-turn"],
        ...["mute", "stop", "lock", "daemon-end"].map(trigger => ["dictation-abort-records-on-" + trigger,
            "            record?.cancel();\n        }, begin() { record?.begin(); } };", "        }, begin() { record?.begin(); } };",
            "dictation-cancel-" + trigger]),
        ["dictation-silence-stopped", 'if (!event.speech || answer === null && utterance.collection === null) {',
            'if (answer === null && utterance.collection === null) {', "dictation-silent"],
        ["dictation-voice-as-key", 'dispatch({ type: "confirm", ...answer, source: "voice" });',
            'dispatch({ type: "confirm", ...answer, source: "key" });', "dictation-physical-hold"],
        ["dictation-start-cue", 'return plan.speech?.kind === "ready" && plan.speech.dictation === true ? "dictation" : "chained";',
            'return "chained";', "dictation-no-cue"],
        ["dictation-cause-ignored", 'speech.kind === "ready" && speech.dictation === true && settings.dictation !== ""', "false", "dictation-cause-holds"],
        ...["stop", "mute", "lock", "release"].map(trigger => ["dictation-pending-end-lost-" + trigger,
            "                if (record.end !== null) finish(record.end);\n", "", "dictation-pending-" + trigger]),
        ["dictation-stop-refusal-read-empty", 'settle(ok(result) ? { kind: "text", text: result.data.text } : { kind: "failed", cause: dictationFault(result) });',
            'settle({ kind: "text", text: ok(result) ? result.data.text : "" });', "dictation-stop-refused"],
        ["dictation-unbound-records", "                if (utterance.answers) utterance.begin();", "                utterance.begin();", "dictation-toggle-second-turn"],
        ["dictation-refusal-unheard", "if (collecting(c, utterance.collection)) utterance.collection.failed(result.cause);\n            else if (running", "if (running", "dictation-start-refused"],
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
    // Without the daemon's bridge answer port a harness program's request
    // never reaches the engine's fixed line.
    const bridgeKit = Fixture.copy(root);
    const daemonFile = path.join(bridgeKit.folder, "backend/jarvisd.js");
    const daemonSource = fs.readFileSync(daemonFile, "utf8");
    const answeredNeedle = ",\n                        answered: (value, tool) => engine.brain.bridged(value, tool)";
    assert.equal(daemonSource.split(answeredNeedle).length, 2, "one bridge answer wiring control match");
    fs.writeFileSync(daemonFile, daemonSource.replace(answeredNeedle, ""));
    await assert.rejects(() => cases(bridgeKit, server, "fleet-request-bridged"), error => {
        assert.ok(error instanceof assert.AssertionError, "dropping the daemon's bridge answer port must fail the bridged fixed line: " + error);
        console.log("control=fleet-line-bridged-wiring detected by=" + JSON.stringify(error.message.split("\n").slice(0, 6).join(" ")));
        return true;
    });
    controls++;
    return controls;
}

async function groupTasks(root, server) {
    let controls = 0;
    // The state root's protection is what withholds the recording.
    const deniedKit = Fixture.copy(root);
    const deniedFile = path.join(deniedKit.folder, "backend/Denied.js");
    const deniedSource = fs.readFileSync(deniedFile, "utf8");
    const stateNeedle = 'path.join(data, "vgshell"), path.join(state, "vgshell"),';
    assert.equal(deniedSource.split(stateNeedle).length, 2, "one state root protection match");
    fs.writeFileSync(deniedFile, deniedSource.replace(stateNeedle, 'path.join(data, "vgshell"),'));
    let deniedFailure = null;
    try { await cases(deniedKit, server, "cloned-voice-reference-withheld"); }
    catch (error) { deniedFailure = error; }
    assert.ok(deniedFailure instanceof assert.AssertionError, "state root control must turn an assertion red: " + deniedFailure);
    console.log("control=state root unprotected detected: " + deniedFailure.message.split("\n")[0]);
    controls++;
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
            '                || s.playback.cue === "line" && s.playback.reply.kind === "none")) flushPlayback(s, effects);',
            '                || s.playback.cue === "line" && s.playback.reply.kind === "none")) void effects;',
            "feedback-voice-" + purpose])
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
    return controls;
}

// The ElevenLabs voice: the scripted row hears the user and a loopback
// stand-in of ElevenLabs's two endpoints speaks, which a plugin copy's
// elevenlabs row names. Its routes, query and body follow the reading of
// ElevenLabs's API reference on VGS-1202 (2026-10-12); the PCM and the
// voices are synthetic, and the key is a fixture value.
const ELEVEN_PORT = 9443;
const ELEVEN_ORIGIN = "http://127.0.0.1:" + ELEVEN_PORT;
const ELEVEN_KEY = "test-key-must-stay-private";
// One synthetic sentence: 100 ms of 24 kHz PCM.
const ELEVEN_FRAMES = 2400;
const ELEVEN_SETTINGS = Object.freeze({ voiceProvider: "elevenlabs", voiceAccount: "eleven-key", voice: "VoiceA" });
const PREVIEW = "This is how I sound when I answer you.";
const BASE_NEEDLE = 'base: "https://api.elevenlabs.io",';

// A plugin copy whose elevenlabs row names the stand-in, each backend edit
// [file, needle, replacement] planted once, then the scripted speech table
// and ENGINE's edits.
function elevenKit(root, engine = [], backend = []) {
    const from = fs.mkdtempSync(path.join(root, "elevenlabs-plugin-"));
    const plugin = path.join(tree, "shell/plugins/vgs.jarvis");
    fs.cpSync(path.join(plugin, "backend"), path.join(from, "backend"), { recursive: true });
    for (const name of ["AccountProviders.js", "Session.js", "JarvisProtocol.js", "manifest.json"])
        fs.copyFileSync(path.join(plugin, name), path.join(from, name));
    for (const [file, needle, replacement] of [["Providers.js", BASE_NEEDLE, 'base: "' + ELEVEN_ORIGIN + '",'], ...backend]) {
        const target = path.join(from, "backend", file);
        const source = fs.readFileSync(target, "utf8");
        assert.equal(source.split(needle).length - 1, 1, file + " edit match: " + needle.slice(0, 60));
        fs.writeFileSync(target, source.replace(needle, replacement));
    }
    return Fixture.copy(root, engine, from);
}

// The stand-in: a voice list read answers PAGES in order, the last
// repeating; a sentence answers its plan by text, ELEVEN_FRAMES of PCM by
// default, {frames} of PCM, or {hold} with no answer.
function elevenStandIn() {
    const records = [];
    const speech = new Map();
    const state = { pages: [{ voices: [{ voice_id: "VoiceA", name: "Rachel", category: "premade" }], has_more: false }], served: 0, gate: null };
    const server = http.createServer(async (request, response) => {
        const record = { method: request.method, url: request.url, headers: request.headers, body: "", closed: false };
        request.socket.once("close", () => { record.closed = true; });
        records.push(record);
        const chunks = [];
        for await (const chunk of request) chunks.push(chunk);
        record.body = Buffer.concat(chunks).toString("utf8");
        if (request.method === "GET") {
            const page = state.pages[Math.min(state.served++, state.pages.length - 1)];
            if (page.status !== undefined) {
                response.writeHead(page.status, { "content-type": "application/json", connection: "close" });
                response.end("{}");
                return;
            }
            response.writeHead(200, { "content-type": "application/json" });
            response.end(JSON.stringify(page));
            return;
        }
        record.text = JSON.parse(record.body).text;
        const plan = speech.get(record.text) ?? { frames: ELEVEN_FRAMES };
        if (plan.hold) return;
        // A case's gate holds every sentence until it opens.
        if (state.gate !== null) await state.gate;
        response.writeHead(200, { "content-type": "application/octet-stream" });
        response.end(Buffer.alloc(plan.frames * 2, 0x22), () => { record.answered = true; });
    });
    const ready = new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(ELEVEN_PORT, "127.0.0.1", resolve);
    });
    return { records, speech, state, ready, posts: () => records.filter(record => record.method === "POST"),
        reset() {
            records.length = 0;
            speech.clear();
            state.pages = [{ voices: [{ voice_id: "VoiceA", name: "Rachel", category: "premade" }], has_more: false }];
            state.served = 0;
            state.gate = null;
        },
        close: () => { server.closeAllConnections(); return new Promise(resolve => server.close(resolve)); } };
}

// The engine's accounts: the brain on the loopback model server, and the
// stored ElevenLabs key the Voice key setting names.
const elevenAccounts = Object.freeze({
    secrets: { lookup: () => Buffer.from(ELEVEN_KEY) },
    choose: id => ({ kind: "accepted", account: { id, provider: "ollama", label: "local",
        source: { kind: "local", origin: "http://127.0.0.1:" + PORT }, model: "fixture-model" } }),
    resolve: id => id === "eleven-key" ? { id, provider: "elevenlabs", label: "voice", model: "",
        source: { kind: "keyring", reference: { provider: "elevenlabs", account: "voice", origin: ELEVEN_ORIGIN,
            attributes: { service: "vgs-jarvis" } } } } : null
});

// Selection with the ElevenLabs voice: it needs a stored ElevenLabs key, the
// ready row that hears the user, and a voice the account's list names. While
// the list is read the step loads; a failed read holds it until a Talk reads
// the list again (voicesHeld), and a voice no read listed, as another
// provider's, never becomes a request path. Always mode stays allowed: the
// wake word and the capture stay on this computer, and ElevenLabs gets only
// released reply text (D102). Its recipients are that row's and ElevenLabs's.
async function spokenSelection(Engine, eleven) {
    const keyring = provider => ({ kind: "keyring", reference: { provider, account: "voice", origin: ELEVEN_ORIGIN,
        attributes: { service: "vgs-jarvis" } } });
    const elevenOnly = id => id === "eleven-key" ? { id, provider: "elevenlabs", label: "voice", source: keyring("elevenlabs"), model: "" }
        : id === "openai-key" ? { id, provider: "openai", label: "voice", source: keyring("openai"), model: "" } : null;
    // Each engine's answers: configure's own, then each one a list's answer
    // judges again.
    const engines = [];
    const fatals = [];
    const configure = (settings, { ready = true, wake = true, resolve = elevenOnly, pages = null } = {}) => {
        Fixture.reset({ ready, wake });
        eleven.reset();
        if (pages !== null) eleven.state.pages = pages;
        const answers = [];
        const engine = Engine.create({ accounts: () => ({ secrets: elevenAccounts.secrets, choose: elevenAccounts.choose, resolve }),
            captionLimit: 1, state: () => ({ gen: 0 }), clock: { set: (fn, ms) => setTimeout(fn, ms), clear: timer => clearTimeout(timer) },
            policy: () => ({ profile: "standard", cloudVision: "ask" }), audit: { before: (event, start) => ({ kind: "started", value: start() }) },
            configured: answer => answers.push(answer), fatal: error => fatals.push(error) });
        engines.push(engine);
        answers.push(engine.configure({ brain: "a", mode: "toggle", ...ELEVEN_SETTINGS, ...settings }));
        return { answers, engine };
    };
    const cause = value => [value.kind, value.cause];
    const listedOnce = async answers => {
        await until(() => answers.length === 2, "the list's answer judges the plan again");
        return answers[1];
    };
    try {
        for (const [label, settings, options, want] of [
            ["no key chosen", { voiceAccount: "" }, {}, ["unconfigured", "speech=live-account-unselected"]],
            ["a key of another provider", { voiceAccount: "openai-key" }, {}, ["unconfigured", "speech=live-key-required"]],
            ["a key no longer stored", { voiceAccount: "gone" }, {}, ["unconfigured", "speech=live-key-required"]],
            ["the key reader's keyed failure", {}, { resolve: () => { throw new Error("jarvis-keys: references=json"); } }, ["unconfigured", "speech=live-account-unreadable"]]])
            assert.deepEqual(cause(configure(settings, options).answers[0]), want, label);
        // [label, settings, options, the first answer, the answer once the
        // list answered, the speaker then].
        for (const [label, settings, options, first, listed, speaker] of [
            ["the hearing row not set up", {}, { ready: false }, ["unconfigured", "speech=fixture-off"], ["unconfigured", "speech=fixture-off"], null],
            ["no voice chosen", { voice: "" }, {}, ["unconfigured", "speech=elevenlabs-voices-reading"], ["ready", undefined], "VoiceA"],
            ["a listed voice", {}, {}, ["unconfigured", "speech=elevenlabs-voices-reading"], ["ready", undefined], "VoiceA"],
            ["another provider's voice name", { voice: "Kore" }, {}, ["unconfigured", "speech=elevenlabs-voices-reading"], ["ready", undefined], "VoiceA"],
            ["a failed read with no voice listed before", {}, { pages: [{ status: 500 }] }, ["unconfigured", "speech=elevenlabs-voices-reading"],
                ["unconfigured", "speech=elevenlabs-voice"], null],
            ["Always mode, which listens on this computer", { mode: "always" }, {}, ["unconfigured", "speech=elevenlabs-voices-reading"], ["ready", undefined], "VoiceA"],
            ["Always mode over a row that cannot spot the word", { mode: "always" }, { wake: false }, ["unconfigured", "speech=elevenlabs-voices-reading"],
                ["unconfigured", "speech=always-local-voice"], null]]) {
            const { answers, engine } = configure(settings, options);
            assert.deepEqual(cause(answers[0]), first, label + ": before the list answers");
            assert.deepEqual(cause(await listedOnce(answers)), listed, label + ": once the list answered");
            assert.equal(engine.plan().speech.speaker ?? null, speaker, label + ": the speaker");
            assert.equal(engine.voicesHeld(), listed[1] === "speech=elevenlabs-voice", label + ": held for a Talk to read again");
        }
        const { answers, engine } = configure({});
        await listedOnce(answers);
        assert.deepEqual([engine.plan().speech.id, engine.plan().speech.recipients],
            ["elevenlabs", [{ kind: "local", provider: "scripted-speech", account: "" },
                { kind: "network", provider: "elevenlabs", account: "eleven-key", origin: ELEVEN_ORIGIN }]],
            "the hearing row's recipients and ElevenLabs's");
        assert.equal(engine.engine(), "chained", "the scripted row records no dictation: ElevenLabs keeps the hearing row's engine");
        // A later failed read keeps the voice an earlier read listed.
        eleven.state.pages = [{ status: 500 }];
        eleven.state.served = 0;
        engine.configure({ brain: "a", mode: "toggle", ...ELEVEN_SETTINGS });
        await until(() => answers.length === 3, "the failed read judges the plan again");
        assert.deepEqual([cause(answers[2]), engine.voices(), engine.plan().speech.speaker], [["ready", undefined], [], "VoiceA"],
            "a failed read offers no voices and keeps the voice");
        // A judgement the list's answer makes that throws goes to the
        // daemon's fatal port, as configure's own throw does.
        let reads = 0;
        configure({}, { resolve: id => {
            if (++reads > 1) throw new TypeError("fixture defect");
            return elevenOnly(id);
        } });
        await until(() => fatals.length === 1, "the list's judgement hands its throw over");
        assert.equal(fatals[0].message, "fixture defect");
        // Local stays local whatever key is stored.
        const local = configure({ voiceProvider: "local" }).engine.plan().speech;
        assert.deepEqual([local.id, local.recipients.length], ["scripted", 1], "Local never speaks through ElevenLabs");
    } finally { for (const engine of engines) engine.close(); }
}
// A cloud voice key its provider refuses at the handshake holds Talk with
// speech=live-key-refused until a judge selects another key or none, or the
// key is stored again under its name (a new list revision): the
// shipped adapter fails live=key-refused, the stream's closing release row
// keeps key-refused, and the engine has the daemon judge again. Any other
// refused handshake holds nothing. The handshake stand-in answers on a
// loopback port; no provider is reached.
const REFUSED_VOICES = [
    { setting: "realtime", account: "openai", base: "wss://api.openai.com/v1/realtime", path: "/v1/realtime", status: 401 },
    { setting: "gemini", account: "gemini", base: "wss://generativelanguage.googleapis.com/ws/", path: "/ws/", status: 403 }
];
async function keyRefusedHold(root, handshake, engineEdits = []) {
    const origin = "http://127.0.0.1:" + handshake.address().port;
    const from = fs.mkdtempSync(path.join(root, "key-refused-plugin-"));
    const plugin = path.join(tree, "shell/plugins/vgs.jarvis");
    fs.cpSync(path.join(plugin, "backend"), path.join(from, "backend"), { recursive: true });
    for (const name of ["AccountProviders.js", "Session.js", "JarvisProtocol.js", "manifest.json"])
        fs.copyFileSync(path.join(plugin, name), path.join(from, name));
    const providers = path.join(from, "backend/Providers.js");
    let table = fs.readFileSync(providers, "utf8");
    for (const voice of REFUSED_VOICES) {
        assert.equal(table.split(voice.base).length - 1, 1, "provider base edit match: " + voice.base);
        table = table.replace(voice.base, origin.replace("http:", "ws:") + voice.path);
    }
    fs.writeFileSync(providers, table);
    const { Engine } = Fixture.copy(root, engineEdits, from);
    for (const voice of REFUSED_VOICES) {
        const keyOf = id => ({ id, provider: voice.account, label: id, model: "",
            source: { kind: "keyring", reference: { provider: voice.account, account: id, origin, attributes: { service: "vgs-jarvis" } } } });
        const answers = [], records = [], failures = [];
        let settings = null;
        // Secrets.revision: a new one for each write of the stored list.
        let revision = 1;
        const engine = Engine.create({ captionLimit: 1, state: () => ({ gen: 0 }),
            accounts: () => ({ secrets: { lookup: () => Buffer.from("test-key-must-stay-private"), revision: () => String(revision) }, choose: elevenAccounts.choose,
                resolve: id => ["key 1", "key 2"].includes(id) ? keyOf(id) : null }),
            clock: { now: () => performance.now(), set: (fn, ms) => setTimeout(fn, ms), clear: timer => clearTimeout(timer) },
            policy: () => ({ profile: "standard", cloudVision: "ask" }),
            audit: { before: (event, start) => ({ kind: "started", value: start() }), record: event => { records.push(event); return { kind: "recorded" }; } },
            configured: answer => answers.push(answer), rejudge: () => answers.push(engine.configure(settings)) });
        const judged = key => {
            settings = { brain: "a", mode: "toggle", voiceProvider: voice.setting, voiceAccount: key, voice: "" };
            return engine.configure(settings);
        };
        const cause = answer => [answer.kind, answer.cause, answer.causes?.[0]];
        const talk = async (op, status, label) => {
            handshake.status = status;
            const before = failures.length;
            engine.speech.open({ gen: 0, op }, { failed: reason => failures.push(reason), idle() {}, due() {}, delegation() {} });
            await until(() => failures.length === before + 1, label + ": the refused handshake fails the stream");
            return failures.at(-1);
        };
        try {
            assert.deepEqual(cause(judged("key 1")), ["ready", undefined, undefined], voice.setting + ": key 1 is ready");
            const published = answers.length;
            assert.equal(await talk(1, voice.status, voice.setting), "live=key-refused", voice.setting + ": the adapter's cause");
            assert.deepEqual([records.at(-1).outcome, records.at(-1).cause], ["failed", "key-refused"], voice.setting + ": the stream's closing row");
            assert.equal(answers.length, published + 1, voice.setting + ": the daemon judges again");
            assert.deepEqual(cause(answers.at(-1)), ["unconfigured", "speech=live-key-refused", "speech=live-key-refused"],
                voice.setting + ": the refused key holds Talk");
            assert.deepEqual(cause(judged("key 1")), ["unconfigured", "speech=live-key-refused", "speech=live-key-refused"],
                voice.setting + ": the same key stays held");
            assert.deepEqual(cause(judged("key 2")), ["ready", undefined, undefined], voice.setting + ": another key is ready");
            assert.deepEqual(cause(judged("key 1")), ["ready", undefined, undefined], voice.setting + ": the hold ended with the key change");
            assert.equal(await talk(3, voice.status, voice.setting + " again"), "live=key-refused", voice.setting + ": key 1 refused again");
            assert.deepEqual(cause(judged("key 1")), ["unconfigured", "speech=live-key-refused", "speech=live-key-refused"],
                voice.setting + ": key 1 held again");
            revision += 1;
            assert.deepEqual(cause(judged("key 1")), ["ready", undefined, undefined], voice.setting + ": key 1 stored again under its name is ready");
            const another = await talk(2, 500, voice.setting + " 500");
            assert.deepEqual([another, records.at(-1).cause], ["live=disconnected code=1006", "voice-stopped"], voice.setting + ": another refusal");
            assert.deepEqual(cause(judged("key 1")), ["ready", undefined, undefined], voice.setting + ": another refusal holds nothing");
        } finally { engine.close(); }
    }
}
async function keyRefusedGroup(root) {
    let controls = 0;
    const handshake = http.createServer((request, response) => { response.writeHead(404); response.end(); });
    handshake.status = 401;
    // The refusal's body is provider text, which no cause carries.
    handshake.on("upgrade", (request, socket) => socket.end("HTTP/1.1 " + handshake.status + " Refused\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"));
    await new Promise(resolve => handshake.listen(0, "127.0.0.1", resolve));
    try {
        await keyRefusedHold(root, handshake);
        for (const [name, needle, replacement] of [
            ["key-refused-unheld", "refusedKey = keyIdentity(c.plan.speech.key);", "void c;"],
            ["key-refused-unjudged", "refusedKey = keyIdentity(c.plan.speech.key);\n                        rejudge();",
                "refusedKey = keyIdentity(c.plan.speech.key);"],
            ["key-refused-stored-again", "JSON.stringify([key.reference, key.secrets.revision()])", "JSON.stringify(key.reference)"],
            ["key-refused-kept", 'if (plan.speech?.cause !== "speech=live-key-refused") refusedKey = null;', "void plan;"],
            ["key-refused-stream-cause", ', "live=key-refused": "key-refused" });', " });"],
            ["key-refused-any-fault", 'if (reason === "live=key-refused" && !closed) {', "if (!closed) {"]]) {
            await assert.rejects(() => keyRefusedHold(root, handshake, [[needle, replacement]]), assert.AssertionError, name + " must turn red");
            console.log("control=" + name + " detected");
            controls++;
        }
    } finally {
        handshake.closeAllConnections();
        await new Promise(resolve => handshake.close(resolve));
    }
    return controls;
}

const SPOKEN_CONTROLS = [
    ["elevenlabs-selected", 'if (settings.voiceProvider === "elevenlabs") return selectSpoken(', 'if (false) return selectSpoken('],
    ["elevenlabs-key-provider", 'voiceKey(settings, accounts, "elevenlabs", provider)', 'voiceKey(settings, accounts, "openai", provider)'],
    ["elevenlabs-hearing", "const hearing = selectHearing(settings, accounts, directories);\n    if (hearing.kind !== \"ready\")",
        "const hearing = { kind: \"ready\", recipients: [], voices: [] };\n    if (hearing.kind !== \"ready\")"],
    ["elevenlabs-recipient", "recipients: [...hearing.recipients, key.recipient],", "recipients: hearing.recipients,"],
    ["elevenlabs-reading-as-failed", 'read.voices === null || read.reading ? "speech=elevenlabs-voices-reading" : "speech=elevenlabs-voice"', '"speech=elevenlabs-voice"'],
    ["elevenlabs-unlisted-voice", ": read.known?.has(settings.voice) ? settings.voice : null;", ": settings.voice || null;"],
    ["elevenlabs-failed-read-drops-voice", "known: voices.length !== 0 ? new Set(voices.map(voice => voice.value)) : read.known", "known: voices.length !== 0 ? new Set(voices.map(voice => voice.value)) : null"],
    ["elevenlabs-never-held", 'voicesHeld: () => plan.speech?.kind === "unconfigured" && plan.speech.cause === "speech=elevenlabs-voice",', "voicesHeld: () => false,"],
    ["elevenlabs-list-throw-dropped", "if (lastSettings !== null) configured(judge(lastSettings));\n                } catch (error) { fatal(error); }",
        "if (lastSettings !== null) configured(judge(lastSettings));\n                } catch (error) { void error; }"],
    ["always-elevenlabs-refused", 'settings.mode === "always" && (Object.hasOwn(DUPLEX, settings.voiceProvider) ||',
        'settings.mode === "always" && (Object.hasOwn(DUPLEX, settings.voiceProvider) || settings.voiceProvider === "elevenlabs" ||']
];

async function elevenCases(kit, server, eleven, only = null) {
    const run = async (name, check, options = {}) => {
        if (only !== null && only !== name) return;
        Fixture.reset();
        server.replies.length = 0;
        eleven.reset();
        options.before?.();
        const logs = [];
        // The plan waits for the account's voices, so the rig's first
        // configure answers before it is ready.
        const w = rig(kit, server, { settings: ELEVEN_SETTINGS, accounts: elevenAccounts, log: line => logs.push(line), later: true, ...options });
        w.logs = logs;
        try { await check(w); } finally {
            await w.close();
            server.closeAll();
        }
    };
    const spoken = () => eleven.posts().map(record => record.text);
    const voiced = w => until(() => w.s().gate.kind === "up", "the plan is ready once the voices answered");

    // The account's voices reach the Voice setting through the engine's
    // offers, the user's own first, from keyed GETs that follow the next
    // page's token, each released and audited first. A preview speaks the
    // fixed sentence in the chosen voice through ElevenLabs, with no brain
    // request.
    await run("elevenlabs-voices", async w => {
        await until(() => w.engine.voices().length === 2, "the account's voices are offered");
        await voiced(w);
        assert.deepEqual(w.engine.voices(), [{ label: "My voice (cloned)", value: "Clone1" }, { label: "Rachel", value: "VoiceA" }]);
        const lists = eleven.records.filter(record => record.method === "GET");
        assert.deepEqual(lists.map(record => [record.url, record.headers["xi-api-key"], record.body]), [
            ["/v2/voices?page_size=100", ELEVEN_KEY, ""], ["/v2/voices?page_size=100&next_page_token=next", ELEVEN_KEY, ""]]);
        assert.deepEqual(w.rows().filter(row => row.kind === "release").map(row => [row.decision, row.outcome, row.effect]),
            lists.map(() => ["send", "pending", "external"]), "each page is audited before it leaves");
        const requests = w.server.requests.length;
        w.runner.dispatch({ type: "preview", voice: "VoiceA" });
        await settled(() => spoken().includes(PREVIEW), () => w.s().turn.kind === "none" && w.s().playback.kind === "idle", "the preview speaks");
        await playOut(w);
        const preview = eleven.posts().find(record => record.text === PREVIEW);
        assert.deepEqual([preview.url, preview.headers["xi-api-key"], w.server.requests.length],
            ["/v1/text-to-speech/VoiceA/stream?output_format=pcm_24000", ELEVEN_KEY, requests], "the chosen voice, no brain request");
    }, { before: () => {
        eleven.state.pages = [{ voices: [{ voice_id: "VoiceA", name: "Rachel", category: "premade" }], has_more: true, next_page_token: "next" },
            { voices: [{ voice_id: "Clone1", name: "My voice", category: "cloned" }], has_more: false, next_page_token: null }];
    } });

    // A list that fails later offers no voices and keeps the voice an
    // earlier read listed: the reply still speaks in it.
    await run("elevenlabs-voices-failed", async w => {
        await voiced(w);
        w.configure({ ...w.s().settings });
        await until(() => w.logs.includes("jarvis: speech=elevenlabs-voices-http status=500"), "the failed read is logged keyed");
        assert.deepEqual(w.engine.voices(), [], "a failed list offers none");
        await voiced(w);
        const first = await say(w, utterance("Say hello."));
        await requested(w, first + 1, "the request");
        server.replies.push(text("Hello there."));
        await until(() => spoken().includes("Hello there."), "the reply speaks");
        await playOut(w);
        assert.equal(eleven.posts().find(record => record.text === "Hello there.").url, "/v1/text-to-speech/VoiceA/stream?output_format=pcm_24000");
    }, { before: () => {
        eleven.state.pages = [{ voices: [{ voice_id: "VoiceA", name: "Rachel", category: "premade" }], has_more: false }, { status: 500 }];
    } });

    // A first read that fails holds a user with no chosen voice; no hello
    // follows the network's return, so a Talk, through the shipped daemon's
    // talk-down rule, reads the list again, and the plan speaks the first
    // listed voice.
    await run("elevenlabs-voices-retried", async w => {
        await until(() => w.logs.includes("jarvis: speech=elevenlabs-voices-http status=500"), "the first read fails");
        await until(() => w.engine.voicesHeld(), "the failed read holds the plan");
        assert.equal(w.s().gate.kind, "down", "Jarvis is not ready meanwhile");
        const daemon = fs.readFileSync(path.join(kit.folder, "backend/jarvisd.js"), "utf8");
        const rule = [...daemon.matchAll(/^ *(if \(\(message\.intent === "talk-down" \|\| message\.intent === "say"\) && [^\n]*judgeSetup\(\);)$/gm)];
        assert.equal(rule.length, 1, "one shipped talk-down judgement");
        vm.runInNewContext(rule[0][1], { message: { intent: "talk-down" }, engine: w.engine, judgeSetup: () => w.configure({ ...w.s().settings }) });
        await voiced(w);
        assert.deepEqual(w.engine.voices(), [{ label: "My voice (cloned)", value: "Clone1" }, { label: "Rachel", value: "VoiceA" }]);
        const first = await say(w, utterance("Say hello."));
        await requested(w, first + 1, "the request");
        server.replies.push(text("Hello there."));
        await until(() => spoken().includes("Hello there."), "the reply speaks");
        await playOut(w);
        assert.equal(eleven.posts().find(record => record.text === "Hello there.").url, "/v1/text-to-speech/Clone1/stream?output_format=pcm_24000",
            "the first listed voice");
    }, { settings: { ...ELEVEN_SETTINGS, voice: "" }, before: () => {
        eleven.state.pages = [{ status: 500 }, { voices: [{ voice_id: "Clone1", name: "My voice", category: "cloned" },
            { voice_id: "VoiceA", name: "Rachel", category: "premade" }], has_more: false }];
    } });

    // Barge-in: the brain is told exactly the sentences ElevenLabs played
    // whole, as for the local voices, and the sentence still requested ends
    // at once.
    await run("elevenlabs-barge-in", async w => {
        await voiced(w);
        const first = await say(w, utterance("What time is it?"));
        await requested(w, first + 1, "first request");
        await until(() => spoken().length !== 0, "the acknowledgement speaks through ElevenLabs");
        await playOut(w);
        eleven.speech.set("The time is noon.", { frames: 24000 });
        eleven.speech.set("Goodbye now.", { hold: true });
        server.replies.push(text("Hello there. ", "The time is noon. ", "Goodbye now."));
        await until(() => w.s().turn.kind === "none", "the reply completes before the interruption");
        await until(() => spoken().includes("Goodbye now."), "the last sentence is requested");
        await feeding(w, ELEVEN_FRAMES);
        await advance(w, 8);
        control.utterances.push(utterance("Stop there."));
        w.runner.dispatch({ type: "talk-down" });
        await until(() => w.s().capture.kind === "open", "capture reopens after the flush");
        assert.equal(w.audio.lastPlayback.heardText, "Hello there.", "a sentence counts once it played whole");
        const held = eleven.posts().find(record => record.text === "Goodbye now.");
        await until(() => held.closed, "the barge-in ends the request in flight");
        release(w);
        server.replies.push(text("Stopped."));
        const body = await requested(w, first + 2, "the request after barge-in");
        assert.equal(user(body).at(-1), heardOnly("Hello there.") + "\n\nStop there.", "the brain is told exactly the heard prefix");
    });

    // The conversation's end ends the request in flight.
    await run("elevenlabs-end", async w => {
        await voiced(w);
        const first = await say(w, utterance("Say something."));
        await requested(w, first + 1, "first request");
        await until(() => spoken().length !== 0, "the acknowledgement speaks through ElevenLabs");
        await playOut(w);
        eleven.speech.set("Wait for me.", { hold: true });
        server.replies.push(text("Wait for me."));
        await until(() => spoken().includes("Wait for me."), "the reply is requested");
        w.runner.dispatch({ type: "stop" });
        const held = eleven.posts().find(record => record.text === "Wait for me.");
        await until(() => held.closed, "the end closes the request in flight");
    });

    // A failover while ElevenLabs still streams a sentence: the sentence
    // released under the old set keeps its transport to its last chunk, the
    // conversation stays, and the failover line and the backup's answer
    // speak after it.
    await run("elevenlabs-failover", async w => {
        await voiced(w);
        const primary = statusBrain(8080, { kind: "status", status: 429 });
        await primary.ready;
        try {
            const gate = { open: null };
            eleven.state.gate = new Promise(resolve => { gate.open = resolve; });
            const before = await say(w, utterance("Try the backup."));
            await until(() => spoken().length !== 0, "the acknowledgement is requested");
            const acknowledgement = eleven.posts()[0];
            server.replies.push(text("Backup answered."));
            await requested(w, before + 1, "the backup receives the request while the acknowledgement streams");
            gate.open();
            await until(() => acknowledgement.answered, "the held sentence completes");
            await until(() => w.s().turn.kind === "none", "the backup's answer finishes");
            await playOut(w);
            await until(() => spoken().includes("Backup answered."), "the backup's answer speaks");
            assert.equal(spoken().some(sentence => sentence.includes("is not answering")), true, "the failover line speaks");
            assert.deepEqual([w.s().fault.kind, w.s().conversation.kind], ["none", "active"], "the conversation stays");
        } finally { await primary.close(); }
    }, { accounts: { ...elevenAccounts, choose: id => id === "fixture-account"
        ? { kind: "accepted", account: { id, provider: "llama-server", label: "primary", source: { kind: "local", origin: "http://127.0.0.1:8080" }, model: "primary-model" } }
        : { kind: "accepted", account: { id, provider: "ollama", label: "backup", source: { kind: "local", origin: "http://127.0.0.1:" + PORT }, model: "backup-model" } } },
    fallbacks: [{ name: "backup", brain: "backup", model: "backup-model" }] });
}

const FLUSH_RETURNS = ["void output?.return?.(); });", "});"];
async function groupElevenLabs(root, server) {
    let controls = 0;
    const eleven = elevenStandIn();
    await eleven.ready;
    try {
        await spokenSelection(elevenKit(root, [PLAN]).Engine, eleven);
        for (const [name, needle, replacement] of SPOKEN_CONTROLS) {
            await assert.rejects(() => spokenSelection(elevenKit(root, [PLAN, [needle, replacement]]).Engine, eleven), assert.AssertionError, name + " must turn red");
            console.log("control=" + name + " detected");
            controls++;
        }
        await elevenCases(elevenKit(root), server, eleven);
        // A stop flushes the playback too: the end closes the request in
        // flight on its own, which the end control below takes away.
        await elevenCases(elevenKit(root, [FLUSH_RETURNS]), server, eleven, "elevenlabs-end");
        for (const [name, scenario, engine, backend] of [
            ["elevenlabs-voices-unread", "elevenlabs-voices", [["            if (plan.list !== null && plan.list !== undefined) readVoices(plan.list);\n", ""]], []],
            ["elevenlabs-preview-voice", "elevenlabs-voices", [[".speak(sentenceInput, speaker ?? c.plan.speech.speaker)", '.speak(sentenceInput, "VoiceB")']], []],
            ["elevenlabs-list-unaudited", "elevenlabs-voices", [['const result = audit.before(releaseEvent({ recipients }, identityOf, item.labels, "send", "pending"), start);',
                'const result = { kind: "started", value: start() };']], []],
            ["elevenlabs-failed-list-drops-voice", "elevenlabs-voices-failed", [["known: voices.length !== 0 ? new Set(voices.map(voice => voice.value)) : read.known",
                "known: voices.length !== 0 ? new Set(voices.map(voice => voice.value)) : null"]], []],
            ["elevenlabs-talk-rereads-not", "elevenlabs-voices-retried", [['voicesHeld: () => plan.speech?.kind === "unconfigured" && plan.speech.cause === "speech=elevenlabs-voice",',
                "voicesHeld: () => false,"]], []],
            ["elevenlabs-daemon-talk-rereads-not", "elevenlabs-voices-retried", [], [["jarvisd.js", "(engine.homeHeld() || engine.voicesHeld() || engine.modelsHeld())", "engine.homeHeld()"]]],
            ["elevenlabs-heard-uncredited", "elevenlabs-barge-in", [], [["ElevenLabs.js",
                "yield { pcm: held, sentence: { text: item.content, frames: held.length / 2 } };", "yield { pcm: held };"]]],
            ["elevenlabs-flush-keeps-request", "elevenlabs-barge-in", [FLUSH_RETURNS], []],
            ["elevenlabs-end-keeps-request", "elevenlabs-end", [FLUSH_RETURNS, ["        c.spoken?.close();\n        for (const door of c.retired) door.close();\n        c.retired.clear();\n        c.net.close();\n", ""]], []],
            ["elevenlabs-failover-closes-voice", "elevenlabs-failover", [["        retire(c, c.net);\n", "        c.net.close();\n"]], []]]) {
            await assert.rejects(() => elevenCases(elevenKit(root, engine, backend), server, eleven, scenario), error => {
                assert.ok(error instanceof assert.AssertionError, name + " must turn " + scenario + " red: " + error);
                console.log("control=" + name + " detected by=" + JSON.stringify(error.message.split("\n")[0]));
                return true;
            });
            controls++;
        }
    } finally { await eleven.close(); }
    return controls;
}

const GROUPS = Object.freeze({ selection: groupSelection, "daemon-speech": groupDaemonSpeech, "daemon-loading": groupDaemonLoading, plants: groupPlants, tasks: groupTasks,
    elevenlabs: groupElevenLabs });

async function runGroup(name) {
    await runGroupWithServer(name, GROUPS[name]);
}

function runChild(name) {
    const started = performance.now();
    const child = cp.spawn(process.execPath, [__filename, "--group", name], {
        env: { PATH: process.env.PATH, HOME: process.env.HOME }, stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = "", stderr = "";
    child.stdout.on("data", data => { stdout += data; });
    child.stderr.on("data", data => { stderr += data; });
    return new Promise(resolve => child.on("close", (code, signal) => resolve({ name, code, signal, stdout, stderr,
        secs: ((performance.now() - started) / 1000).toFixed(2) })));
}

async function roster() {
    const results = await Promise.all(Object.keys(GROUPS).map(runChild));
    let controls = 0;
    const failed = [];
    const notMeasured = [];
    for (const result of results) {
        process.stdout.write("test-jarvis-engine: group=" + result.name + " secs=" + result.secs + " exit=" + result.code + "\n");
        if (result.stdout) process.stdout.write(result.stdout);
        if (result.stderr) process.stderr.write(result.stderr);
        const ok = result.stdout.match(new RegExp("test-jarvis-engine: ok group=" + result.name + " requests=\\d+ controls=(\\d+)"));
        if (result.code === 77 && result.signal === null && ok === null) notMeasured.push(result.name);
        else if (result.code !== 0 || result.signal !== null || ok === null) failed.push(result.name);
        else controls += Number(ok[1]);
    }
    if (failed.length !== 0) {
        console.error("test-jarvis-engine: failed groups=" + [...failed, ...notMeasured].join(","));
        process.exitCode = 1;
        return;
    }
    if (notMeasured.length !== 0) {
        console.log("test-jarvis-engine: not-measured groups=" + notMeasured.join(","));
        process.exitCode = 77;
        return;
    }
    console.log("test-jarvis-engine: ok groups=" + results.length + " controls=" + controls);
}

const args = process.argv[2] === "--inside" ? process.argv.slice(3) : process.argv.slice(2);
if (args[0] === "--group") {
    const name = args[1] ?? "";
    if (args.length !== 2 || !Object.hasOwn(GROUPS, name)) {
        console.error("test-jarvis-engine: unknown group=" + name);
        process.exitCode = 1;
    } else world(() => runGroup(name)).catch(error => { console.error(error); process.exitCode = 1; });
} else if (args.length === 0) {
    roster().catch(error => { console.error(error); process.exitCode = 1; });
} else {
    console.error("test-jarvis-engine: unknown arguments " + args.join(" "));
    process.exitCode = 1;
}
