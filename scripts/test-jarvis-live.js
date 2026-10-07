#!/usr/bin/env node
// The GPT-Live duplex engine against schema-pinned scripts that a loopback
// WebSocket server replays inside the J09 world, through the real Session
// reducer and runner. In-memory capture and playback ports follow Audio's
// sink and source contract. A manual clock drives silence, reply ends, idle
// close and finalization. Excerpt and scripts: scripts/fixtures/jarvis-live/.
// The key is the keys-world stand-in's fixture value; no network or account.
"use strict";
const { assert, fs, path, tree, world, mutant } = require("./fixtures/jarvis/policy.js");
const { standins } = require("./fixtures/jarvis/keys-world.js");
const Ws = require("./fixtures/jarvis/websocket.js");
const Check = require("./fixtures/schema-check.js");
const excerpt = require("./fixtures/jarvis-live/gpt-live.schema.json");
const fixtures = require("./fixtures/jarvis-live/gpt-live-scripts.json");
const { load } = require("../bin/lib/qml-library.js");
const http = require("node:http");
const cp = require("node:child_process");
const { once } = require("node:events");
const BrainFixture = require("./fixtures/jarvis/engine.js");
const { standins: audioStandins } = require("./fixtures/jarvis/audio.js");
const backend = path.join(tree, "shell/plugins/vgs.jarvis/backend");
const file = path.join(backend, "GptLive.js");
const Protocol = load(path.join(tree, "shell/plugins/vgs.jarvis/JarvisProtocol.js"));
const KEY = "test-key-must-stay-private";
const PRIVATE = "fixture-private-provider-text";
// The bounds docs/decisions/D089-jarvis-chained-engine-and-heard-prefix.md, in the units the engine reads.
const BACKLOG = 256 * 1024;
const FRAME = 1024 * 1024;
const OPENING = 24000 * 2 * 20;
const APPEND = "session.input_audio.append";
const CLIENT = { "session.start": "LiveSessionStartEvent", [APPEND]: "LiveInputAudioAppendEvent",
    "session.close": "LiveSessionCloseParam", "session.commentary.append": "LiveCommentaryAppendEvent" };
const SERVER = { "session.started": "LiveSessionStarted", "session.output_audio.delta": "LiveOutputAudioDelta",
    "session.input_transcript.delta": "LiveInputTranscriptDelta", "session.output_transcript.delta": "LiveOutputTranscriptDelta",
    "session.usage.updated": "LiveSessionUsageUpdated", info: "LiveInfoEvent", "session.closed": "LiveSessionClosed",
    error: "LiveErrorEvent", "session.delegation.created": "LiveDelegationCreated" };
function pinned(name, value, label) {
    assert.equal(typeof name, "string", label + " names a pinned event: " + value.type);
    assert.deepEqual(Check.errors(excerpt, name, value), [], label + " matches the pinned " + name);
}
for (const [name, events] of Object.entries(fixtures.scripts)) for (const event of events) pinned(SERVER[event.type], event, name);
// Off-schema frames a fault row needs, built from a pinned event.
const off = (name, change) => JSON.stringify(change(structuredClone(fixtures.scripts[name][0])));
const turn = () => new Promise(resolve => setImmediate(resolve));
async function until(check, label) {
    // Loopback delivery and stream events, not a latency measurement. Each
    // control's red result waits for this bound, so it stays short.
    const deadline = Date.now() + 2000;
    while (!check()) {
        assert.ok(Date.now() < deadline, label);
        await new Promise(resolve => setTimeout(resolve, 2));
    }
}
function manual() {
    let now = 0, next = 1;
    const timers = new Map();
    return { now: () => now, set(fn, ms) { timers.set(next, { at: now + Math.max(0, ms), fn }); return next++; },
        clear(id) { timers.delete(id); },
        advance(ms) {
            const end = now + ms;
            for (;;) {
                let due = null;
                for (const [id, timer] of timers) if (timer.at <= end && (due === null || timer.at < due[1].at)) due = [id, timer];
                if (due === null) break;
                timers.delete(due[0]);
                now = Math.max(now, due[1].at);
                due[1].fn();
            }
            now = end;
        },
        // A stalled event loop: time passes and no timer runs until the next advance.
        stall(ms) { now += ms; } };
}
// Paced silence leaves once a tick. Yielding between simulated seconds lets
// the socket drain as real time would; one burst would read as a backlog.
async function elapse(w, ms) {
    for (let left = ms; left > 0; left -= 1000) {
        w.clock.advance(Math.min(1000, left));
        await new Promise(resolve => setTimeout(resolve, 0));
    }
}
const bytes = (w, value) => w.played.reduce((sum, { chunk }) => sum + chunk.filter(byte => byte === value).length, 0);
// Byte comparison with a short message: a diff of large buffers stalls assert.
function same(event, expected, label) {
    const actual = Buffer.from(event.audio, "base64");
    assert.ok(actual.equals(expected), label + ": " + actual.length + " bytes");
}
const appended = conn => Buffer.concat(conn.events.filter(event => event.type === APPEND).map(event => Buffer.from(event.audio, "base64")));

world(async () => {
    const childEnv = {};
    for (const name of ["PATH", "HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_DATA_HOME", "XDG_RUNTIME_DIR"])
        childEnv[name] = process.env[name];
    const lookups = () => {
        const calls = path.join(process.env.XDG_STATE_HOME, "secret-calls");
        return fs.existsSync(calls) ? fs.readFileSync(calls, "utf8").trim().split("\n")
            .filter(line => JSON.parse(line).argv[0] === "lookup").length : 0;
    };
    function listen() {
        const conns = [];
        const instance = http.createServer((request, response) => { response.writeHead(404); response.end(); });
        instance.on("upgrade", (request, socket) => {
            const conn = { url: request.url, rig: new URL(request.url, "http://rig").searchParams.get("rig"), taken: false,
                headers: request.headers, events: [], cursor: 0, socket, ended: false,
                play(name) { for (const event of fixtures.scripts[name]) this.raw(JSON.stringify(event)); },
                send(event) { pinned(SERVER[event.type], event, "raw"); this.raw(JSON.stringify(event)); },
                raw(data, opcode = 1) { socket.write(Ws.frame(opcode, data)); },
                count: type => conn.events.filter(event => event.type === type).length,
                async event(type) {
                    await until(() => conn.events.slice(conn.cursor).some(event => event.type === type), "client sends " + type);
                    const index = conn.events.findIndex((event, at) => at >= conn.cursor && event.type === type);
                    conn.cursor = index + 1;
                    return conn.events[index];
                } };
            conns.push(conn);
            Ws.accept(request, socket);
            socket.on("data", Ws.decoder(({ opcode, payload }) => {
                if (opcode === 8) { socket.end(Ws.frame(8, payload)); return; }
                assert.equal(opcode, 1, "client events are text frames");
                const value = JSON.parse(payload.toString());
                pinned(CLIENT[value.type], value, "client");
                conn.events.push(value);
            }));
            socket.on("close", () => { conn.ended = true; });
            // A fixture socket reset after the engine closes is not evidence.
            socket.on("error", () => {});
        });
        return new Promise((resolve, reject) => {
            instance.once("error", reject);
            instance.listen(0, "127.0.0.1", () => resolve({ instance, conns,
                origin: "http://127.0.0.1:" + instance.address().port,
                // A rig's own connection: a red control's late one never stands in.
                async accept(w) {
                    const next = () => conns.find(conn => conn.rig === String(w.id) && !conn.taken);
                    await until(() => next() !== undefined, "the engine connects");
                    const conn = next();
                    conn.taken = true;
                    return conn;
                } }));
        });
    }
    const main = await listen();
    const other = await listen();
    const nets = [];
    let conversations = 0;

    // A disposable backend whose provider row points at the loopback server.
    function kitFrom(folder, edits = []) {
        const table = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "live-kit-"));
        for (const sibling of fs.readdirSync(folder).filter(name => name.endsWith(".js")))
            fs.copyFileSync(path.join(folder, sibling), path.join(table, sibling));
        fs.cpSync(path.join(backend, "skills"), path.join(table, "skills"), { recursive: true });
        for (const [name, needle, replacement] of [["Providers.js", '"wss://api.openai.com/v1/live/sessions"',
            JSON.stringify(main.origin.replace("http:", "ws:") + "/v1/live/sessions")], ...edits]) {
            const source = fs.readFileSync(path.join(table, name), "utf8");
            assert.equal(source.split(needle).length - 1, 1, name + " kit substitution");
            fs.writeFileSync(path.join(table, name), source.replace(needle, replacement));
        }
        const load = name => require(path.join(table, name));
        return { folder: table, Live: load("GptLive.js"), Policy: load("Policy.js"), Net: load("net.js"), Providers: load("Providers.js"),
            Secrets: load("Secrets.js"), Runner: load("session-runner.js") };
    }

    function rig(kit, { key = "own", mode = "hold", synchronousClose = false } = {}) {
        const clock = manual();
        const w = { id: ++conversations, clock, played: [], flushes: 0, transcripts: [], logs: [], collected: [], sink: null,
            source: null, handed: [], backlog: null, delegations: [] };
        const store = new kit.Secrets.Secrets(path.join(childEnv.XDG_STATE_HOME, "vgshell/jarvis"), childEnv);
        const reference = kit.Secrets.ownReference("openai", "fixture", key === "elsewhere" ? other.origin : main.origin);
        const secrets = { lookup: value => { const secret = store.lookup(value); w.handed.push(secret); return secret; } };
        const recipients = kit.Policy.recipients({ conversation: "live-" + w.id, profile: "standard", cloudVision: "ask",
            brain: { kind: "local", provider: "fixture-brain", account: "" },
            speech: [{ kind: "network", provider: "openai-live", account: "fixture", origin: main.origin }] });
        w.net = kit.Net.create(recipients);
        nets.push(w.net);
        // The rig's query names its connection on the server. The send-backlog
        // bound reads the channel's unsent bytes; a staged w.backlog stands in
        // for the kernel's buffering, which differs by host.
        const net = { websocket(value, options) {
            const channel = w.net.websocket(value, { ...options, url: options.url + "?rig=" + w.id });
            if (channel.kind !== "channel") return channel;
            let closing = false;
            return { kind: channel.kind, events: channel.events, send: channel.send, close() {
                if (synchronousClose && !closing) {
                    closing = true;
                    channel.events.dispatchEvent(Object.assign(new Event("close"), { code: 1006, wasClean: false }));
                }
                channel.close();
            },
                get readyState() { return channel.readyState; },
                get bufferedAmount() { return w.backlog === null ? channel.bufferedAmount : w.backlog; } };
        } };
        const engine = kit.Live.create({ provider: kit.Providers.select("openai-live"), clock,
            captionLimit: Protocol.TRANSCRIPT_CHARS, log: line => w.logs.push(line),
            conversation: () => ({ net, key: key === null ? null : { secrets, reference }, language: "",
                transfer: (item, start) => start(), grants: () => [] }) });
        w.engine = engine;
        const ports = kit.Runner.unavailable();
        ports.capture = {
            // Audio refuses capture without a sink, as here.
            open: (e, done, failed) => {
                w.sink = engine.captureSink(e);
                if (w.sink === null) failed("audio-start: speech-unavailable"); else done();
            },
            close: (e, done) => { if (w.sink !== null) w.sink.destroy(); w.sink = null; done(); },
            collect: e => w.collected.push(e)
        };
        ports.playback = {
            start: (e, done, failed) => {
                const source = engine.playbackSource(e.source);
                if (source === null) { failed("playback-source-unavailable"); return; }
                w.source = source;
                source.on("data", chunk => w.played.push({ chunk, flush: w.flushes }));
                source.on("end", () => { if (w.source === source) { w.source = null; done(); } });
            },
            flush: (e, done) => { w.flushes++; if (w.source !== null) w.source.destroy(); w.source = null; done(); }
        };
        // The daemon's wire mapping, judged by the shared protocol.
        ports.transcript = e => {
            Protocol.accept(JSON.stringify({ v: 1, type: "transcript", gen: e.gen, revision: "a".repeat(64),
                role: e.role, text: e.text, stage: e.stage, rev: e.rev }), "daemon");
            w.transcripts.push({ role: e.role, text: e.text, stage: e.stage, rev: e.rev });
        };
        ports.mute = { store: () => {} };
        ports.speech = engine.port;
        ports.brain = { ...ports.brain, send: (e, done) => { w.delegations.push(e); done("brain-done"); } };
        w.runner = new kit.Runner.SessionRunner(Protocol.Session, ports, clock, (state, phase) => { w.state = state; w.phase = phase; });
        w.dispatch = (type, values = {}) => w.runner.dispatch({ type, ...values });
        w.dispatch("snapshot", { locked: false, engine: "duplex", configured: true, settings: { mode } });
        w.dispatch("indicator", { shown: true });
        return w;
    }
    // Talk opens the session and holds it before session.started.
    async function starting(kit, options) {
        const w = rig(kit, options);
        w.dispatch("talk-down");
        const conn = await main.accept(w);
        await conn.event("session.start");
        return { w, conn };
    }
    // Release leaves the started session running on paced silence.
    async function running(kit, options) {
        const { w, conn } = await starting(kit, options);
        conn.play("started");
        w.sink.write(Buffer.alloc(960, 5));
        await conn.event(APPEND);
        w.dispatch("talk-up");
        await turn();
        w.clock.advance(100);
        await conn.event(APPEND);
        return { w, conn };
    }
    // Session state comes from the QML library realm; compare its JSON.
    const fault = (w, reason) => assert.deepEqual(JSON.parse(JSON.stringify(w.state.fault)), { kind: "error", reason, retry: 0 });
    function quiet(w, conn) {
        const all = JSON.stringify([w.state, w.logs, w.transcripts, conn === undefined ? [] : conn.events]);
        assert.equal(all.includes(KEY), false, "no key in state, log, transcript or frame");
        assert.equal(all.includes(PRIVATE), false, "no provider message text");
    }

    async function roundTrip(kit) {
        const w = rig(kit);
        const looked = lookups();
        w.dispatch("talk-down");
        assert.equal(lookups(), looked + 1, "the key is looked up when the session first needs it");
        assert.ok(w.handed.length === 1 && w.handed[0].every(byte => byte === 0), "the looked-up key is zeroed after the handshake");
        const conn = await main.accept(w);
        assert.equal(conn.url, "/v1/live/sessions?rig=" + w.id);
        assert.equal(conn.headers.authorization, "Bearer " + KEY);
        const start = await conn.event("session.start");
        assert.equal(start.session.model, "gpt-live-1");
        assert.deepEqual(start.session.audio, { format: { type: "audio/pcm", rate: 24000 } });
        assert.deepEqual(start.session.delegation, { type: "client" });
        assert.equal(start.session.store, false);
        assert.match(start.session.instructions, /You are Jarvis/);
        w.sink.write(Buffer.alloc(4800, 5));
        await turn();
        assert.equal(conn.count(APPEND), 0, "no audio before session.started");
        conn.play("started");
        same(await conn.event(APPEND), Buffer.alloc(4800, 5),
            "opening words wait for session.started, then leave once");
        w.sink.write(Buffer.alloc(960, 6));
        same(await conn.event(APPEND), Buffer.alloc(960, 6), "a microphone frame leaves");
        w.clock.advance(1000);
        await turn();
        assert.equal(conn.count(APPEND), 2, "no silence while capture feeds the session");
        w.dispatch("talk-up");
        await turn();
        w.clock.advance(100);
        same(await conn.event(APPEND), Buffer.alloc(4800),
            "released talk leaves the session on paced silence");
        w.clock.stall(2500);
        w.clock.advance(0);
        same(await conn.event(APPEND), Buffer.alloc(48000),
            "after a stalled loop at most 1 s of silence leaves, with no catch-up");
        conn.play("reply-old");
        await until(() => bytes(w, 0x11) === 1440, "the reply reaches playback");
        assert.equal(w.phase, "speaking");
        w.clock.advance(400);
        conn.send(fixtures.scripts["late-old"][0]);
        await until(() => bytes(w, 0x11) === 1920, "a later delta joins the playing reply");
        w.clock.advance(499);
        await turn();
        assert.equal(w.state.playback.kind, "playing", "each delta restarts the reply's gap");
        w.clock.advance(1);
        await until(() => w.state.playback.kind === "idle", "the reply ends after its gap");
        assert.equal(w.phase, "idle");
        assert.deepEqual(w.collected, [], "the duplex engine collects no utterance");
        assert.equal(w.state.fault.kind, "none");
        quiet(w, conn);
        return { w, conn };
    }

    // Idle is 60 s with no caption, no output audio and no new capture while
    // no reply is queued or playing. Output audio counts through its reply.
    async function idle(kit) {
        const { w, conn } = await roundTrip(kit);
        const closes = () => conn.count("session.close");
        await elapse(w, 59000);
        conn.play("speech-after");
        await until(() => w.transcripts.length === 1, "a caption arrives");
        await elapse(w, 59000);
        assert.equal(closes(), 0, "a caption restarts the idle wait");
        conn.play("reply-new");
        await until(() => bytes(w, 0x22) === 1440, "a late reply plays");
        w.clock.advance(500);
        await until(() => w.state.playback.kind === "idle", "the late reply ends");
        await elapse(w, 1000);
        assert.equal(closes(), 0, "a reply's end restarts the idle wait");
        w.dispatch("talk-down");
        conn.play("speech-after");
        conn.play("reply-old");
        await until(() => w.state.speech.reply.kind === "waiting", "a reply waits behind the held key");
        await elapse(w, 61000);
        assert.equal(closes(), 0, "a queued reply holds the session");
        const old = bytes(w, 0x11);
        w.dispatch("talk-up");
        await until(() => bytes(w, 0x11) === old + 1440, "the queued reply plays");
        w.clock.advance(500);
        await until(() => w.state.playback.kind === "idle", "the queued reply ends");
        await elapse(w, 59999);
        assert.equal(closes(), 0, "no close before 60 s idle");
        assert.equal(w.state.speech.kind, "open");
        w.clock.advance(1);
        await conn.event("session.close");
        assert.equal(w.state.speech.kind, "closed");
        assert.equal(w.state.conversation.kind, "ended", "idle close ends the conversation");
        assert.equal(w.state.fault.kind, "none");
        conn.play("closed");
        await until(() => conn.ended, "the engine releases the socket after session.closed");
        assert.deepEqual(w.logs, []);
    }

    async function unconfirmed(kit) {
        const { w, conn } = await running(kit);
        w.dispatch("stop");
        await conn.event("session.close");
        const closedAt = conn.events.length;
        await elapse(w, 14999);
        assert.equal(conn.ended, false, "the engine waits for session.closed");
        assert.deepEqual(conn.events.slice(closedAt).map(event => event.type), [], "input stops at session.close");
        w.clock.advance(1);
        await until(() => conn.ended, "the bounded wait releases the socket");
        assert.deepEqual(w.logs, ["jarvis: live=close-unconfirmed cause=timeout"]);
        const lease = await running(kit);
        lease.w.runner.close();
        await until(() => lease.conn.ended, "lease loss aborts at once");
        assert.equal(lease.conn.count("session.close"), 0);
        assert.deepEqual(lease.w.logs, ["jarvis: live=close-unconfirmed cause=lease"]);
        const closing = await running(kit);
        closing.w.dispatch("stop");
        await closing.conn.event("session.close");
        closing.w.runner.close();
        await until(() => closing.conn.ended, "lease loss releases a closing session at once");
        assert.deepEqual(closing.w.logs, ["jarvis: live=close-unconfirmed cause=lease"]);
    }

    async function finalizing(kit) {
        const w = rig(kit, { mode: "toggle" });
        const conns = [];
        for (let index = 0; index < 5; index++) {
            w.clock.advance(300);
            w.dispatch("talk-down");
            const conn = await main.accept(w);
            await conn.event("session.start");
            conn.play("started");
            w.sink.write(Buffer.alloc(960));
            await conn.event(APPEND);
            w.clock.advance(300);
            w.dispatch("talk-down");
            await conn.event("session.close");
            conns.push(conn);
        }
        await until(() => conns[0].ended, "past four finalizing sessions the oldest is released");
        assert.deepEqual(conns.map(conn => conn.ended), [true, false, false, false, false]);
        assert.deepEqual(w.logs, ["jarvis: live=close-unconfirmed cause=finalizing-limit"]);
    }

    async function captions(kit) {
        const { w, conn } = await running(kit);
        conn.play("captions");
        conn.send({ type: "session.output_transcript.delta", event_id: "evt_long", delta: "x\u0007".repeat(2500), start_ms: 5000, end_ms: 9000 });
        await until(() => w.transcripts.length === 9, "captions reach the wire");
        const long = "x ".repeat(2500);
        assert.deepEqual(w.transcripts, [
            { role: "user", text: "What is", stage: "partial", rev: 1 },
            { role: "user", text: "What is the time?", stage: "partial", rev: 2 },
            { role: "assistant", text: "It is noon.", stage: "partial", rev: 3 },
            { role: "user", text: "What is the time?", stage: "final", rev: 4 },
            { role: "user", text: "Thanks.", stage: "partial", rev: 5 },
            { role: "assistant", text: "It is noon.", stage: "final", rev: 6 },
            { role: "assistant", text: long.slice(0, 4096), stage: "partial", rev: 7 },
            { role: "assistant", text: long.slice(0, 4096), stage: "final", rev: 8 },
            { role: "assistant", text: long.slice(4096), stage: "partial", rev: 9 }
        ]);
        conn.play("usage");
        conn.play("speech-before");
        await until(() => w.transcripts.length === 10, "usage and info pass without a fault");
        assert.equal(w.state.fault.kind, "none");
        quiet(w, conn);
    }

    // An interrupted reply already playing: its later audio never plays, and
    // only user speech after the interruption point reopens output.
    async function interruptPlaying(kit) {
        const { w, conn } = await running(kit);
        conn.play("reply-old");
        await until(() => bytes(w, 0x11) === 1440, "the old reply plays");
        w.dispatch("talk-down");
        assert.equal(w.flushes, 1);
        assert.equal(w.state.playback.kind, "idle");
        conn.play("late-old");
        conn.play("speech-before");
        conn.play("late-old");
        conn.play("speech-after");
        await until(() => w.transcripts.some(item => item.text.startsWith("Stop")), "the new utterance arrives");
        assert.ok(w.transcripts.some(item => item.role === "assistant"), "the interrupted reply's caption arrives");
        assert.equal(w.played.filter(item => item.flush === 1).length, 0, "no audio of the interrupted reply after the flush");
        assert.equal(w.state.speech.reply.kind, "none");
        conn.play("reply-new");
        w.dispatch("talk-up");
        await until(() => bytes(w, 0x22) === 1440, "the reply to the new utterance plays");
        assert.equal(w.played.filter(item => item.flush === 1).reduce((sum, item) => sum + item.chunk.filter(b => b === 0x11).length, 0), 0);
    }

    // A reply still queued behind a held talk key is dropped whole.
    async function interruptQueued(kit) {
        const { w, conn } = await running(kit);
        w.dispatch("talk-down");
        conn.play("speech-after");
        conn.play("reply-old");
        await until(() => w.state.speech.reply.kind === "waiting", "the reply waits behind the held key");
        assert.equal(w.state.capture.kind, "open", "half duplex: a reply never cuts off held talk");
        w.dispatch("interrupt");
        assert.equal(w.state.speech.reply.kind, "none");
        w.dispatch("talk-up");
        await turn();
        assert.equal(w.state.playback.kind, "idle", "the interruption cleared the queue");
        conn.play("speech-after");
        conn.play("reply-new");
        await until(() => bytes(w, 0x22) === 1440, "the next reply plays");
        assert.equal(bytes(w, 0x11), 0, "no queued audio of the interrupted reply plays");
    }

    // Each fault row: [name, stage, act, reason]. A caption after the act
    // reaches the wire only when the act did not fault, so a red row is quick.
    const rows = [
        ["error", running, conn => conn.play("error"), "live=server-error code=unknown_parameter"],
        ["delegation-shape", running, conn => conn.raw(off("delegation", event => ({ ...event, delegation: { ...event.delegation, target: "responses" } }))), "live=delegation-shape"],
        ["delegation-id", running, conn => conn.raw(off("delegation", event => ({ ...event, delegation: { ...event.delegation, id: "" } }))), "live=delegation-shape"],
        ["delegation-id-type", running, conn => conn.raw(off("delegation", event => ({ ...event, delegation: { ...event.delegation, id: 0 } }))), "live=delegation-shape"],
        ["delegation-id-size", running, conn => conn.raw(off("delegation", event => ({ ...event, delegation: { ...event.delegation, id: "x".repeat(513) } }))), "live=delegation-shape"],
        ["delegation-offset", running, conn => conn.raw(off("delegation", event => ({ ...event, offset_ms: -1 }))), "live=delegation-shape"],
        ["delegation-kind", running, conn => conn.raw(off("delegation", event => ({ ...event, delegation: { ...event.delegation, type: "tool" } }))), "live=delegation-shape"],
        ["expired", running, conn => conn.play("expired"), "live=closed reason=expired"],
        ["closed-reason", running, conn => conn.raw(off("expired", event => ({ ...event, reason: "hung_up" }))), "live=frame-shape"],
        ["json", running, conn => conn.raw("{"), "live=frame-json"],
        ["binary", running, conn => conn.raw(Buffer.from([1, 2]), 2), "live=frame-binary"],
        ["frame-size", running, conn => conn.raw("x".repeat(FRAME + 1)), "live=frame-size"],
        ["shape", running, conn => conn.raw("[1]"), "live=frame-shape"],
        ["caption-shape", running, conn => conn.send({ type: "session.input_transcript.delta", event_id: "e", delta: "late",
            start_ms: 20, end_ms: 10 }), "live=frame-shape"],
        ["usage-shape", running, conn => conn.raw(off("usage", event => ({ ...event, usage: {} }))), "live=frame-shape"],
        ["odd-audio", running, conn => conn.send({ type: "session.output_audio.delta", delta: "AAAA" }), "live=output-audio"],
        // Lenient base64 decodes this to four bytes; only the strict pattern refuses it.
        ["not-base64", running, conn => conn.send({ type: "session.output_audio.delta", delta: "AAAAAA=A" }), "live=output-audio"],
        ["unrequested", running, conn => conn.raw(JSON.stringify({ type: "response.event", event_id: "e", event: {} })),
            "live=event type=response.event"],
        ["started-twice", running, conn => conn.play("started"), "live=event-order"],
        ["input-frame", running, (conn, w) => { w.dispatch("talk-down"); w.sink.write(Buffer.alloc(3)); }, "live=input-frame"],
        ["reset", running, conn => conn.socket.destroy(), "live=disconnected code=1006"],
        ["format", starting, conn => conn.raw(off("started", event => {
            event.session.audio.format.rate = 16000;
            return event;
        })), "live=format"],
        ["started-shape", starting, conn => conn.raw(off("started", event => ({ ...event, session: { ...event.session, id: "" } }))),
            "live=frame-shape"],
        ["early-audio", starting, conn => conn.send(fixtures.scripts["reply-old"][0]), "live=event-order"],
        ["early-caption", starting, conn => conn.play("speech-before"), "live=event-order"]
    ];
    async function failures(kit, only = null) {
        const selected = rows.filter(([name]) => only === null || name === only);
        assert.ok(selected.length > 0, "fault row " + only);
        for (const [name, stage, act, reason] of selected) {
            const { w, conn } = await stage(kit);
            act(conn, w);
            if (stage === starting) conn.play("started");
            conn.play("speech-before");
            await until(() => w.state.fault.kind === "error" || w.transcripts.length > 0, name + " is judged");
            fault(w, reason);
            assert.equal(w.state.speech.kind, "closed", name + " releases the session");
            assert.equal(w.state.conversation.kind, "ended", name + " ends the conversation: no silent provider switch");
            await until(() => conn.ended, name + " closes the socket");
            quiet(w, conn);
        }
    }

    async function startTimeout(kit) {
        const { w, conn } = await starting(kit);
        await elapse(w, 19999);
        assert.equal(w.state.fault.kind, "none");
        w.clock.advance(1);
        fault(w, "live=start-timeout");
        await until(() => conn.ended, "start timeout closes the socket");
    }

    async function keys(kit) {
        const looked = lookups();
        const elsewhere = rig(kit, { key: "elsewhere" });
        elsewhere.dispatch("talk-down");
        fault(elsewhere, "net=key-origin");
        assert.equal(lookups(), looked, "a key bound to another origin is refused before any lookup");
        const missing = rig(kit, { key: null });
        missing.dispatch("talk-down");
        fault(missing, "live=no-key");
        await turn();
        const own = [elsewhere.id, missing.id].map(String);
        assert.equal([...main.conns, ...other.conns].filter(conn => own.includes(conn.rig)).length, 0, "no connection without a usable key");
    }

    async function release(kit) {
        const { w, conn } = await starting(kit);
        conn.play("started");
        w.sink.write(Buffer.alloc(960, 5));
        await until(() => w.state.fault.kind === "error", "a withheld frame faults");
        fault(w, "live=release-withhold");
        await until(() => conn.ended, "the withheld session closes");
        assert.equal(conn.count(APPEND), 0, "a withheld frame writes nothing");
    }

    async function releaseConnect(kit) {
        const w = rig(kit);
        w.dispatch("talk-down");
        fault(w, "live=release-withhold");
        await turn();
        assert.equal(main.conns.filter(conn => conn.rig === String(w.id)).length, 0, "a withheld connection opens no socket");
    }

    // The full opening fits; it leaves after session.started in order, ahead
    // of later words, without meeting the send backlog.
    async function opening(kit) {
        const { w: early } = await starting(kit);
        for (let sent = 0; sent < OPENING; sent += 48000) early.sink.write(Buffer.alloc(48000));
        assert.equal(early.state.fault.kind, "none", "20 s of opening words fit");
        early.sink.write(Buffer.alloc(2));
        fault(early, "live=input-overflow");
        const { w, conn } = await starting(kit);
        const words = Buffer.concat(Array.from({ length: 20 }, (_, index) => Buffer.alloc(48000, index + 1)));
        for (let offset = 0; offset < words.length; offset += 48000) w.sink.write(words.subarray(offset, offset + 48000));
        conn.play("started");
        await conn.event(APPEND);
        assert.equal(w.state.fault.kind, "none", "the opening leaves behind the socket's backpressure");
        w.sink.write(Buffer.alloc(960, 0x7f));
        const all = Buffer.concat([words, Buffer.alloc(960, 0x7f)]);
        const deadline = Date.now() + 2000;
        while (appended(conn).length < all.length && w.state.fault.kind === "none") {
            assert.ok(Date.now() < deadline, "the opening drains");
            w.clock.advance(100);
            await new Promise(resolve => setTimeout(resolve, 2));
        }
        assert.equal(w.state.fault.kind, "none", "the full opening never meets the send backlog");
        assert.ok(appended(conn).equals(all), "every opening byte leaves once, in order, before later words");
    }

    async function releaseLifetime(kit) {
        const { w, conn } = await starting(kit, { synchronousClose: true });
        w.sink.write(Buffer.alloc(OPENING + 2));
        fault(w, "live=input-overflow");
        assert.equal(w.state.speech.kind, "closed", "released speech closes once");
        await until(() => conn.ended, "overflow closes its transport");
        w.clock.advance(20000);
        fault(w, "live=input-overflow");
        assert.equal(w.state.conversation.kind, "ended", "released callbacks cannot restore the session");
    }

    async function replyQueue(kit) {
        const { w, conn } = await running(kit);
        w.dispatch("talk-down");
        conn.play("speech-after");
        const chunk = { type: "session.output_audio.delta", delta: Buffer.alloc(65536).toString("base64") };
        for (let index = 0; index < 19; index++) conn.send(chunk);
        conn.send({ type: "session.output_transcript.delta", event_id: "mark", delta: "mark", start_ms: 1, end_ms: 2 });
        await until(() => w.transcripts.length === 2, "19 queued chunks arrive");
        assert.equal(w.state.fault.kind, "none", "a queue under the playback allowance is kept");
        for (let index = 0; index < 2; index++) conn.send(chunk);
        await until(() => w.state.fault.kind === "error", "past the allowance the reply faults");
        fault(w, "live=output-overflow");
    }

    async function backlog(kit) {
        const { w, conn } = await running(kit);
        const count = conn.count(APPEND);
        w.backlog = BACKLOG;
        w.clock.advance(100);
        await until(() => conn.count(APPEND) === count + 1, "a frame leaves with the socket at the bound");
        assert.equal(w.state.fault.kind, "none", "a backlog at the bound is kept");
        w.backlog = BACKLOG + 1;
        w.clock.advance(100);
        fault(w, "live=send-backlog");
    }

    async function frameBound(kit) {
        const { w, conn } = await running(kit);
        const frame = JSON.stringify({ type: "info", event_id: "e", code: "c", message: "" });
        conn.raw(frame.replace('"message":""', '"message":"' + "m".repeat(FRAME - frame.length) + '"'));
        conn.play("speech-before");
        await until(() => w.transcripts.length === 1 || w.state.fault.kind === "error", "a frame at the bound is judged");
        assert.equal(w.state.fault.kind, "none", "a 1 MiB frame is kept");
    }

    async function delegation(kit) {
        const { w, conn } = await running(kit);
        conn.play("captions");
        conn.send({ type: "session.input_transcript.delta", event_id: "straddling", delta: "Across the boundary.", start_ms: 3500, end_ms: 3700 });
        conn.play("delegation");
        await until(() => w.delegations.length === 1 || w.state.fault.kind === "error", "delegation reaches the brain");
        assert.equal(w.delegations.length, 1);
        const task = w.delegations[0];
        assert.equal(task.delegation, "del_fixture");
        assert.ok(task.text.includes("What is") && task.text.includes("It is noon."));
        assert.equal(task.text.includes("Thanks."), false, "context after the delegation offset does not enter the request");
        assert.equal(task.text.includes("Across the boundary."), false, "a delta that ends after delegation is excluded");
        const item = kit.Policy.item("The result is ready. ".repeat(30), ["speech"]);
        assert.equal(w.engine.commentary(task.delegation, item), true);
        await until(() => conn.events.some(event => event.type === "session.commentary.append"), "commentary leaves");
        const sent = conn.events.filter(event => event.type === "session.commentary.append");
        assert.equal(sent.map(event => event.content).join(""), item.content);
        assert.ok(sent.every(event => Buffer.byteLength(event.content) <= 400 && event.delegation_id === task.delegation));
        assert.equal(w.engine.commentary("stale", item), false);
        w.dispatch("interrupt");
        assert.equal(w.engine.commentary(task.delegation, item), false);
        conn.play("speech-after");
        conn.play("delegation");
        await until(() => w.delegations.length === 2, "a new delegation uses new identity");
        w.dispatch("stop");
        assert.equal(w.engine.commentary(task.delegation, item), false, "an ended conversation sends no commentary");
    }

    async function violations(kit) {
        const { w, conn } = await running(kit);
        conn.send({ type: "session.output_transcript.delta", event_id: "format_1", delta: "Visit https://example.com.", start_ms: 0, end_ms: 100 });
        conn.send({ type: "session.output_transcript.delta", event_id: "format_2", delta: "Use **bold**.", start_ms: 2000, end_ms: 2100 });
        conn.play("speech-before");
        await until(() => w.transcripts.some(item => item.text === "earlier"), "the transcript windows arrive");
        let counts = w.logs.filter(line => line.startsWith("jarvis: live=violations counts="))
            .map(line => JSON.parse(line.split("counts=")[1]));
        assert.equal(counts.length, 1, "the closed window is counted once");
        assert.equal(counts[0].url, 1);
        w.dispatch("stop");
        counts = w.logs.filter(line => line.startsWith("jarvis: live=violations counts="))
            .map(line => JSON.parse(line.split("counts=")[1]));
        assert.equal(counts.length, 2, "teardown counts the final non-overlapping window");
        assert.equal(counts[1].markdown, 4);
        assert.equal(w.logs.some(line => line.includes("example.com") || line.includes("bold")), false);
    }

    async function contextBound(kit) {
        const { w, conn } = await running(kit);
        conn.send({ type: "session.input_transcript.delta", event_id: "bound", delta: "x".repeat(65536), start_ms: 0, end_ms: 100 });
        await until(() => w.transcripts.length >= 16 || w.state.fault.kind === "error", "context at its limit arrives");
        assert.equal(w.state.fault.kind, "none");
        conn.play("speech-before");
        await until(() => w.state.fault.kind === "error", "overflow ends the session");
        fault(w, "live=context-limit");
    }

    // The real daemon selects Accounts, the configured brain, Session,
    // ToolRouter, Policy, Files, Audit and the duplex speech owner. Only the
    // provider address, local fixture model and clock are instrumented in its disposable tree.
    async function daemonDelegation(kit, only = "action") {
        const root = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "delegation-daemon-"));
        const plugin = path.join(root, "plugin");
        fs.cpSync(path.join(tree, "shell/plugins/vgs.jarvis"), plugin, { recursive: true });
        for (const file of fs.readdirSync(kit.folder).filter(name => name.endsWith(".js")))
            fs.copyFileSync(path.join(kit.folder, file), path.join(plugin, "backend", file));
        const accountsFile = path.join(plugin, "AccountProviders.js");
        const accountSource = fs.readFileSync(accountsFile, "utf8");
        const modelNeedle = 'probe: { driver: "ollama", path: "/api/generate", model: "" }';
        assert.equal(accountSource.split(modelNeedle).length - 1, 1, "the local fixture names its scripted model");
        fs.writeFileSync(accountsFile, accountSource.replace(modelNeedle,
            'probe: { driver: "ollama", path: "/api/generate", model: "fixture-model" }'));
        const runnerFile = path.join(plugin, "backend/jarvisd.js");
        const offset = path.join(root, "clock");
        fs.writeFileSync(offset, "0");
        let source = fs.readFileSync(runnerFile, "utf8");
        assert.equal(source.split("performance.now()").length - 1, 3, "the daemon clocks share the injected offset");
        source = source.replaceAll("performance.now()", 'performance.now() + Number(fs.readFileSync(' + JSON.stringify(offset) + ', "utf8"))');
        fs.writeFileSync(runnerFile, source);
        if (only === "release") {
            const engineFile = path.join(plugin, "backend/ChainedEngine.js");
            const engineSource = fs.readFileSync(engineFile, "utf8");
            const needle = "speech: plan.speech.recipients";
            assert.equal(engineSource.split(needle).length - 1, 1);
            fs.writeFileSync(engineFile, engineSource.replace(needle,
                needle + '.concat(plan.speech.recipients.map(recipient => ({...recipient,origin:"https://example.invalid"})))'));
        }
        const directories = Object.fromEntries(["state", "data", "runtime"].map(name => [name, path.join(root, name)]));
        for (const folder of Object.values(directories)) fs.mkdirSync(folder, { mode: 0o700 });
        fs.writeFileSync(path.join(directories.state, "keys.json"), JSON.stringify([kit.Secrets.ownReference("openai", "fixture", main.origin)]));
        require(path.join(plugin, "backend/Core.js")).use(tree);
        const { Accounts } = require(path.join(plugin, "backend/Accounts.js"));
        const { PROVIDERS } = require(path.join(plugin, "AccountProviders.js"));
        const accounts = new Accounts(directories.state, childEnv);
        const live = accounts.account(PROVIDERS.find(row => row.id === "openai"), "fixture", { kind: "found" },
            { kind: "keyring", reference: kit.Secrets.ownReference("openai", "fixture", main.origin) }).id;
        const local = PROVIDERS.find(row => row.id === "ollama");
        const brain = accounts.account(local, "local", { kind: "found" }, { kind: "local", origin: local.origin }).id;
        const victim = path.join(process.env.HOME, "delegated-file-" + path.basename(root));
        fs.writeFileSync(victim, "fixture", { mode: 0o600 });
        const server = BrainFixture.brain(11434);
        await server.ready;
        const child = cp.spawn("node", [runnerFile, "--tree", tree], { env: childEnv, stdio: ["pipe", "pipe", "pipe"] });
        const closed = once(child, "close");
        const deadline = setTimeout(() => child.kill("SIGKILL"), 15000);
        const messages = [];
        let tail = "", stderr = "";
        child.stdout.on("data", data => {
            const lines = (tail + data).split("\n"); tail = lines.pop();
            for (const line of lines) messages.push(Protocol.accept(line, "daemon"));
        });
        child.stderr.on("data", data => { stderr += data; });
        child.stdin.on("error", error => { if (error.code !== "EPIPE") throw error; });
        const last = () => messages.filter(value => value.type === "state").at(-1)?.state;
        const revision = "a".repeat(64);
        const send = value => child.stdin.write(JSON.stringify({ v: 1, gen: last()?.gen ?? 0, revision, ...value }) + "\n");
        const wait = async (check, label) => {
            try { await until(() => check() || child.exitCode !== null, label); }
            catch { assert.fail(label + ": " + JSON.stringify(messages.filter(value => value.type === "status")) + " state=" + JSON.stringify(last()) + " stderr=" + stderr); }
            assert.ok(check(), label + ": " + stderr);
        };
        const rows = () => fs.readdirSync(path.join(directories.state, "audit"))
            .flatMap(file => fs.readFileSync(path.join(directories.state, "audit", file), "utf8").trim().split("\n").map(JSON.parse));
        let releaseReply;
        const heldReply = new Promise(resolve => { releaseReply = resolve; });
        try {
            send({ type: "hello", settings: { mode: "hold", microphone: "", speaker: "", brain, taskTerminal: "auto",
                cloudVision: "ask", privateWindows: "", voiceProvider: "gpt-live", voiceAccount: live }, directories, locked: false,
                keys: { talk: "SUPER+code:108", mute: "SUPER+SHIFT+code:108", stop: "SUPER+ALT+PERIOD", confirm: "SUPER+ALT+Y" } });
            await wait(() => last()?.gate.kind === "up", "configured GPT-Live raises the daemon gate");
            assert.equal(last().engine.kind, "duplex");
            send({ type: "indicator", shown: true });
            send({ type: "intent", intent: "talk-down" });
            await wait(() => main.conns.some(conn => conn.rig === null && !conn.taken), "the actual daemon connects its voice");
            const conn = main.conns.find(conn => conn.rig === null && !conn.taken); conn.taken = true;
            await conn.event("session.start");
            conn.play("started");
            await wait(() => last()?.capture.kind === "open", "synthetic capture opens behind the indicator");
            send({ type: "intent", intent: "talk-up" });
            if (only === "action") server.replies.push(BrainFixture.calls({ id: "delete_call", name: "files_delete", arguments: { path: victim } }),
                BrainFixture.text("**Completed.** Visit https://example.com."));
            else if (only === "release") server.replies.push(BrainFixture.calls({ id: "read_call", name: "files_read", arguments: { path: victim } }),
                BrainFixture.text("The private result was withheld."));
            else if (only === "stale") server.replies.push([{ wait: heldReply },
                ...BrainFixture.calls({ id: "stale_delete", name: "files_delete", arguments: { path: victim } })]);
            else {
                server.replies.push(BrainFixture.text({ wait: heldReply }, "Late reply."));
                if (only === "replacement") server.replies.push(BrainFixture.text("Current reply."));
            }
            conn.play("captions"); conn.play("delegation");
            await wait(() => server.requests[0]?.body !== null && server.requests.length > 0, "the configured brain receives the delegation");
            const first = server.requests[0].body;
            assert.ok(first.messages.some(value => value.role === "user" && value.content.includes("What is")));
            assert.equal(first.model, "fixture-model");
            assert.ok(Array.isArray(first.tools) && first.tools.some(value => value.function.name === "files_delete"), "the configured router offers its tools");
            assert.equal(JSON.stringify(first).includes("Thanks."), false);
            if (only === "action") {
                await wait(() => last()?.approval.kind === "held", "the router holds the destructive call");
                assert.equal(fs.existsSync(victim), true, "Policy blocks deletion before approval");
                const approval = last().approval;
                assert.equal(approval.physical, true);
                send({ type: "shown", id: approval.id });
                await wait(() => last().approval.shownAt !== null, "the action is drawn");
                fs.writeFileSync(offset, "1000");
                send({ type: "intent", intent: "confirm", id: approval.id, digest: approval.digest, source: "key" });
                await wait(() => conn.count("session.commentary.append") > 0 || last()?.fault.kind === "error", "the approved result returns through commentary");
                assert.ok(conn.count("session.commentary.append") > 0, JSON.stringify(last()?.fault));
                assert.equal(fs.existsSync(victim), false);
                assert.equal(server.requests.length, 2);
                assert.ok(server.requests[1].body.messages.some(value => value.role === "tool" && value.tool_call_id === "delete_call"));
                const commentary = conn.events.filter(value => value.type === "session.commentary.append");
                assert.ok(commentary.every(value => value.delegation_id === "del_fixture" && !value.content.includes("https://") && !value.content.includes("**")));
                assert.ok(rows().some(row => row.kind === "action" && row.effect === "destructive" && row.confirmed === "physical"));
                assert.ok(rows().some(row => row.kind === "release" && row.decision === "send" && row.op === last().speech.op
                    && row.outcome === "pending" && row.args.labels === "[redacted]"),
                    "outbound commentary has a prior audit for its live operation");
            } else if (only === "release") {
                await wait(() => last()?.approval.kind === "held", "the whole recipient set asks for file release");
                assert.equal(last().approval.purpose, "release");
                assert.ok(last().approval.text.includes(PROVIDERS.find(row => row.id === "openai").label),
                    "release names the selected account provider");
                assert.equal(last().approval.text.includes("openai-live"), false, "release shows no adapter id");
                assert.equal(server.requests.length, 1, "no tool result reaches the brain while release is held");
                send({ type: "intent", intent: "cancel", id: last().approval.id });
                await wait(() => conn.count("session.commentary.append") > 0, "the refused release completes with a withheld result");
                assert.equal(server.requests.length, 2);
                const tool = server.requests[1].body.messages.find(value => value.role === "tool");
                assert.equal(tool.tool_call_id, "read_call");
                assert.equal(tool.content.includes("fixture"), false, "the private file does not leave for the brain");
                assert.ok(rows().some(row => row.kind === "release" && row.decision === "ask"));
                assert.ok(rows().some(row => row.kind === "release" && row.decision === "withhold"));
            } else {
                let requestClosed = false;
                server.requests[0].closed.then(() => { requestClosed = true; });
                if (only === "replacement") {
                    const event = structuredClone(fixtures.scripts.delegation[0]);
                    event.delegation.id = "del_current";
                    conn.send(event);
                } else send({ type: "intent", intent: only === "interrupt" ? "talk-down" : "stop" });
                await wait(() => requestClosed, "cancel closes the old brain request");
                releaseReply();
                if (only === "replacement") {
                    await wait(() => conn.count("session.commentary.append") > 0, "the new delegation returns after cancellation");
                    assert.equal(server.requests.length, 2);
                    const commentary = conn.events.filter(value => value.type === "session.commentary.append");
                    assert.ok(commentary.every(value => value.delegation_id === "del_current" && !value.content.includes("Late")));
                } else {
                    if (only === "stale") {
                        await wait(() => last()?.conversation.kind === "ended", "stop ends delegated work");
                        await wait(() => conn.ended, "stop closes the old speech transport");
                    } else await wait(() => last()?.turn.kind === "none", "interrupt ends delegated work");
                    assert.equal(conn.count("session.commentary.append"), 0, "stale brain work never reaches GPT-Live");
                }
                assert.equal(fs.existsSync(victim), true, "stale work starts no file action");
            }
            child.stdin.end();
            const [code, signal] = await closed;
            assert.equal(signal, null);
            assert.equal(code, 0, stderr);
            assert.equal(stderr.includes(KEY), false);
        } finally {
            clearTimeout(deadline); releaseReply();
            if (child.exitCode === null) { child.kill("SIGKILL"); await closed; }
            server.closeAll(); await server.close();
            fs.rmSync(victim, { force: true });
        }
    }

    const cases = { roundTrip, idle, unconfirmed, finalizing, captions, interruptPlaying, interruptQueued,
        failures, startTimeout, keys, opening, releaseLifetime, replyQueue, backlog, frameBound, delegation, violations, contextBound,
        daemonDelegation, daemonStale: kit => daemonDelegation(kit, "stale"), daemonRelease: kit => daemonDelegation(kit, "release"),
        daemonReplacement: kit => daemonDelegation(kit, "replacement"), daemonInterrupt: kit => daemonDelegation(kit, "interrupt") };
    const withheld = ["Policy.js", "const current = item(value.content, value.labels);",
        'const current = item(value.content, value.labels);\n    if (String(current.content).includes("input_audio.append")) return { kind: "withhold", content: "[withheld]", labels: current.labels };'];
    const withheldConnect = ["Policy.js", "const current = item(value.content, value.labels);",
        'const current = item(value.content, value.labels);\n    if (String(current.content).endsWith("/v1/live/sessions")) return { kind: "withhold", content: "[withheld]", labels: current.labels };'];
    let controls = 0;
    async function control(name, needle, replacement, check) {
        await mutant(file, name, needle, replacement, async (_module, folder) => check(folder), "GptLive.js");
        controls++;
        console.log("control=" + name + " detected");
    }
    try {
        for (const check of Object.values(cases)) await check(kitFrom(backend));
        await release(kitFrom(backend, [withheld]));
        await releaseConnect(kitFrom(backend, [withheldConnect]));
        const as = name => folder => cases[name](kitFrom(folder));
        const row = name => folder => failures(kitFrom(folder), name);
        const mutations = [
            ["delegation-dispatch", "session.events.delegation({ id: event.id,", "void ({ id: event.id,", as("delegation")],
            ["delegation-context", "item.end <= event.offset", "true", as("delegation")],
            ["stale-delegation", " || session.delegation !== id", "", as("delegation")],
            ["flush-delegation", "session.delegation = null;\n            session.output", "session.output", as("delegation")],
            ["commentary-bound", "slice(0, COMMENTARY_CHARS)", "slice(0)", as("delegation")],
            ["violation-count", "const counts = Speakable.violations(segment.text, session.language);", 'const counts = Speakable.violations("", session.language);', as("violations")],
            ["context-bound", 'if (session.contextChars > CONTEXT_CHARS) fail("context-limit");', "", as("contextBound")],
            ["flush-queue", "if (session.next !== null) session.next.stream.destroy();\n            session.next = null;\n            // Audio's",
                "// Audio's", as("interruptQueued")],
            ["discard", 'if (session.output.kind === "discarding" || pcm.length === 0) return;', "if (pcm.length === 0) return;", as("interruptPlaying")],
            ["discard-timeline", "&& start >= session.output.from", "", as("interruptPlaying")],
            ["reopen-role", 'role === "user" && session.output.kind === "discarding"', 'session.output.kind === "discarding"', as("interruptPlaying")],
            ["idle-rule", "}, IDLE_MS);", "}, IDLE_MS + 1);", as("idle")],
            ["caption-activity", "function caption(session, role, delta, start, end) {\n        activity(session);",
                "function caption(session, role, delta, start, end) {", as("idle")],
            ["reply-end-activity", 'clear(session, "gap");\n            activity(session);', 'clear(session, "gap");', as("idle")],
            ["idle-guard", "if (session.playing !== null || session.next !== null) return;", "", as("idle")],
            ["close-wait", 'clock.set(() => finalize(session, "timeout"), CLOSE_WAIT_MS)', "null", as("unconfirmed")],
            ["close-input", 'for (const name of ["silence", "idle", "gap"]) clear(session, name);',
                'for (const name of ["idle", "gap"]) clear(session, name);', as("unconfirmed")],
            ["lease-release", 'for (const session of [...sessions.values()]) finalize(session, "lease");', "", as("unconfirmed")],
            ["finalizing", 'if (closing.length > FINALIZING) finalize(closing[0], "finalizing-limit");', "", as("finalizing")],
            ["server-error", 'return fail("server-error code="', 'return { kind: "ignored" }; return fail("server-error code="', row("error")],
            ["delegation-shape", 'value.delegation.target !== "client"', 'false', row("delegation-shape")],
            ["delegation-id", 'value.delegation.id === ""', "false", row("delegation-id")],
            ["delegation-id-type", 'typeof value.delegation.id !== "string"', "false", row("delegation-id-type")],
            ["delegation-id-size", 'value.delegation.id.length > 512', "false", row("delegation-id-size")],
            ["delegation-offset", '!time(value.offset_ms)', "false", row("delegation-offset")],
            ["delegation-kind", 'value.delegation.type !== "delegation"', "false", row("delegation-kind")],
            ["closed-running", 'else fail("closed reason=" + event.reason);', "", row("expired")],
            ["closed-reason", 'if (!CLOSED_REASONS.includes(value.reason)) fail("frame-shape");', "", row("closed-reason")],
            ["frame-json", 'catch { fail("frame-json"); }', 'catch { return { kind: "ignored" }; }', row("json")],
            ["frame-binary", 'if (typeof data !== "string") fail("frame-binary");', "", row("binary")],
            ["frame-size", 'if (data.length > FRAME_CHARS) fail("frame-size");', "", row("frame-size")],
            ["frame-shape", 'if (!plain(value) || typeof value.type !== "string") fail("frame-shape");', "", row("shape")],
            ["caption-shape", " || value.end_ms < value.start_ms", "", row("caption-shape")],
            ["usage-shape", 'if (!plain(value.usage) || !time(value.usage.seconds)) fail("frame-shape");', "", row("usage-shape")],
            ["output-odd", 'if (pcm.length % 2 !== 0) fail("output-audio");', "", row("odd-audio")],
            ["output-base64", " || !BASE64.test(value.delta)", "", row("not-base64")],
            ["unrequested", 'return fail("event type=" + token(value.type));', 'return { kind: "ignored" };', row("unrequested")],
            ["started-order", 'if (session.state.kind !== "starting") fail("event-order");', "", row("started-twice")],
            ["input-frame", 'if (pcm.length % 2 !== 0) { failed(session, "live=input-frame"); return; }', "", row("input-frame")],
            ["disconnected", 'else failed(session, "live=disconnected code=" + event.code);', "", row("reset")],
            ["format", '\n            fail("format");', "\n            void 0;", row("format")],
            ["started-shape", 'if (!plain(session) || typeof session.id !== "string" || session.id === "") fail("frame-shape");', "",
                row("started-shape")],
            ["audio-order", 'output(session, event.pcm);\n                else if (kind !== "closing") fail("event-order");',
                "output(session, event.pcm);", row("early-audio")],
            ["caption-order", 'event.start, event.end);\n                else if (kind !== "closing") fail("event-order");',
                "event.start, event.end);", row("early-caption")],
            ["start-timeout", 'clock.set(() => failed(session, "live=start-timeout"), START_WAIT_MS)', "null", as("startTimeout")],
            ["key-first", "Net.assertKeyTarget(provider.base, key.reference.origin);", "", as("keys")],
            ["key-zero", "} finally { secret.fill(0); }", "} finally { void secret; }", as("roundTrip")],
            ["pending", "session.pending.push(Buffer.from(pcm));", "", as("roundTrip")],
            ["silence", "if (samples > 0 && !input(session, Buffer.alloc(samples * 2))) return;", "", as("roundTrip")],
            ["silence-gate", "if (session.capture === null) {", "if (true) {", as("roundTrip")],
            ["silence-cap", "Math.min(now - session.inputAt, SILENCE_MAX_MS)", "(now - session.inputAt)", as("roundTrip")],
            ["reply-gap", "reply.stream.push(null);", "", as("roundTrip")],
            ["gap-restart", "if (reply === session.playing) gap(session);", "", as("roundTrip")],
            ["segment-gap", "start - segment.end >= SEGMENT_GAP_MS", "false", as("captions")],
            ["segment-limit", 'captionLimit) {\n                conclude(session, role);\n                emit(segment.text, "final");', "captionLimit) {", as("captions")],
            ["release-before-close", 'session.state = { kind: "ended" };\n        if (session.channel !== null) session.channel.close();',
                'if (session.channel !== null) session.channel.close();\n        session.state = { kind: "ended" };', as("releaseLifetime")],
            ["input-overflow", 'if (session.pendingBytes > PENDING_BYTES) { failed(session, "live=input-overflow"); return false; }', "",
                as("opening")],
            ["input-order", "if (!waiting && session.pending.length === 0) return append(session, pcm);",
                "if (!waiting) return append(session, pcm);", as("opening")],
            ["drain", " && session.channel.bufferedAmount === 0) {", ") {", as("opening")],
            ["output-overflow", 'if (!reply.stream.push(pcm)) { failed(session, "live=output-overflow"); return; }', "reply.stream.push(pcm);",
                as("replyQueue")],
            ["backlog", 'if (session.channel.bufferedAmount > SEND_BACKLOG_BYTES) fail("send-backlog");', "", as("backlog")],
            ["release", 'if (answer.kind !== "send") fail("release-" + answer.kind);\n        if (session.channel', "if (session.channel",
                folder => release(kitFrom(folder, [withheld]))],
            ["release-connect", 'if (answer.kind !== "channel") fail("release-" + answer.kind);', 'if (answer.kind !== "channel") return;',
                folder => releaseConnect(kitFrom(folder, [withheldConnect]))]
        ];
        for (const [name, needle, replacement, check] of mutations) await control(name, needle, replacement, check);
        for (const [name, needle, replacement, scenario] of [
            ["daemon-live-selection", 'settings.voiceProvider === "gpt-live"', "false", "action"],
            ["daemon-commentary", "c.live.commentary(turn.delegation, item);", "void item;", "action"],
            ["daemon-router-tools", "tools: router.offer()", "tools: []", "action"],
            ["daemon-router-approval", "router.route(call, { gen: turn.gen, op: turn.op });", "void call;", "action"],
            ["daemon-speakable", "for (const sentence of text.push(event.text))", "for (const sentence of [event.text])", "action"],
            ["daemon-recipient-provider", 'provider: account.provider, account: account.id, origin: Net.endpoint(provider.base).origin',
                'provider: provider.id, account: account.id, origin: Net.endpoint(provider.base).origin', "release"],
            ["daemon-release-request", "if (needed.length === 0) return;", "return;", "release"],
            ["daemon-audit-before-send", 'const result = audit.before(releaseEvent(c, identity, item.labels, "send", "pending"), start);\n        if (result.kind !== "started") fail("audit-write");\n        return result.value;',
                'return start();', "action"]
        ]) {
            const kit = kitFrom(backend, [["ChainedEngine.js", needle, replacement]]);
            // The audit plant must parse, send the real commentary frame, and
            // fail at its missing operation record rather than at setup.
            new (require("node:vm").Script)(fs.readFileSync(path.join(kit.folder, "ChainedEngine.js"), "utf8"));
            const failed = name === "daemon-audit-before-send"
                ? error => error instanceof assert.AssertionError
                    && error.message === "outbound commentary has a prior audit for its live operation"
                : assert.AssertionError;
            await assert.rejects(() => daemonDelegation(kit, scenario), failed, name + " must turn red");
            controls++;
            console.log("control=" + name + " detected");
        }
        console.log("test-jarvis-live: ok cases=" + (Object.keys(cases).length + 2) + " controls=" + controls
            + " connections=" + main.conns.length);
    } finally {
        for (const net of nets) net.close();
        for (const server of [main, other]) {
            for (const conn of server.conns) conn.socket.destroy();
            server.instance.closeAllConnections();
            await new Promise(resolve => server.instance.close(resolve));
        }
    }
}, folder => { standins(folder); audioStandins(folder); }, 180000)?.catch(error => { console.error(error); process.exitCode = 1; });
