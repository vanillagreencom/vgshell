#!/usr/bin/env node
// Real Audio and reducer ports, synthetic PCM. J09 owns all processes.
"use strict";
const { assert, fs, path, cp, tree, world, hungWorld, until, unlocked, copyBackend } = require("./fixtures/jarvis/audio.js");
const { Readable, Writable, PassThrough } = require("node:stream");
const { load } = require("../bin/lib/qml-library.js");
const Session = load(path.join(tree, "shell/plugins/vgs.jarvis/Session.js"));
const { SessionRunner, unavailable } = require("../shell/plugins/vgs.jarvis/backend/session-runner.js");
const file = path.join(tree, "shell/plugins/vgs.jarvis/backend/Audio.js");
const { Audio } = require(file);
const EchoCancel = require("../shell/plugins/vgs.jarvis/backend/EchoCancel.js");
require("../shell/plugins/vgs.jarvis/backend/Core.js").use(tree);

function echoGraph() {
    const targets = { microphone: "physical.mic", speaker: "physical.speaker" }, group = EchoCancel.group(targets);
    const node = (id, name, media, props = {}) => ({ id, type: "PipeWire:Interface:Node",
        info: { props: { "node.name": name, "media.class": media, ...props } } });
    return { targets, graph: [
        node(10, targets.microphone, "Audio/Source", { "device.id": 8 }),
        node(11, targets.speaker, "Audio/Sink", { "device.id": 8 }),
        ...Object.entries(EchoCancel.NAMES).map(([role, name], i) => node(20 + i, name,
            { capture: "Stream/Input/Audio", source: "Audio/Source", sink: "Audio/Sink", playback: "Stream/Output/Audio" }[role],
            { "node.group": group, "node.link-group": group, "node.virtual": true,
                ...(role === "capture" ? { "target.object": targets.microphone }
                    : role === "playback" ? { "target.object": targets.speaker } : {}) })),
        { id: 30, type: "PipeWire:Interface:Module", info: { name: "libpipewire-module-echo-cancel",
            args: "{\n" + EchoCancel.argumentsText(targets) + "\n}" } },
        { id: 31, type: "PipeWire:Interface:Link", info: { "output-node-id": 10, "input-node-id": 20, state: "paused" } },
        { id: 32, type: "PipeWire:Interface:Link", info: { "output-node-id": 23, "input-node-id": 11, state: "active" } },
        { id: 4, type: "PipeWire:Interface:Metadata", props: { "metadata.name": "default" }, metadata: [
            { subject: 0, key: "default.audio.source", type: "Spa:String:JSON", value: { name: targets.microphone } },
            { subject: 0, key: "default.audio.sink", type: "Spa:String:JSON", value: { name: targets.speaker } }
        ] }
    ] };
}

async function echoRoutes(Implementation = Audio) {
    const fixture = echoGraph(), w = setup(Implementation);
    try {
        w.audio.echoFile = { state: "installed", path: "/fixture/pipewire.conf.d/60-jarvis-echo-cancel.conf", reason: "", targets: fixture.targets };
        w.audio.snapshot(fixture.graph, "full");
        w.dispatch("snapshot", { locked: false, configured: true, engine: "duplex", echoCancel: true,
            settings: { microphone: "", speaker: "" } });
        assert.equal(w.audio.echoRoute.state, "active", "connected native graph matches the owned plan");
        assert.equal(w.audio.echoActive(), true);
        const judgeGraph = w.audio.echoGraph;
        let judgments = 0;
        w.audio.echoGraph = function (...args) { judgments++; return judgeGraph.apply(this, args); };
        for (const type of ["snapshot", "deadline", "indicator"]) {
            const before = judgments;
            w.dispatch(type, type === "snapshot" ? { locked: false, configured: true, engine: "duplex",
                echoCancel: true, settings: { microphone: "", speaker: "" } }
                : type === "indicator" ? { gen: w.runner.state.gen, shown: true, bar: "gone" } : {});
            assert.equal(judgments, before, type + " with unchanged physical selections reuses the graph judgment");
            assert.equal(w.audio.state, w.runner.state, "Audio still observes the current Session");
        }
        assert.equal(w.audio.device("microphones", "microphone", w.runner.state.settings, "duplex"), "jarvis_ec_source");
        assert.equal((await w.audio.selected("speakers", "speaker")).target, "jarvis_ec_sink");
        for (const engine of ["dictation", "chained"]) {
            assert.equal(w.audio.echoActive(engine), false, engine + " keeps half duplex");
            assert.equal(w.audio.device("microphones", "microphone", w.runner.state.settings, engine), fixture.targets.microphone);
        }
        assert.deepEqual(w.audio.setupTargets(w.runner.state.settings), fixture.targets,
            "setup reuses the physical selection while live audio chooses the EC pair");
        for (const row of [
            { name: "unrelated module", id: 30, change: item => { item.info.args = "library.name=aec/libspa-aec-webrtc"; } },
            { name: "wrong module", id: 30, change: item => { item.info.name = "libpipewire-module-loopback"; } },
            { name: "wrong group", id: 21, change: item => { item.info.props["node.group"] = "other-ec"; } },
            { name: "wrong physical target", id: 20, change: item => { item.info.props["target.object"] = "other.mic"; } },
            { name: "failed link", id: 31, change: item => { item.info.state = "error"; } },
            { name: "wrong link", id: 32, change: item => { item.info["input-node-id"] = 10; } },
            { name: "missing module", id: 30, remove: true },
            { name: "missing source", id: 21, remove: true }
        ]) {
            const graph = structuredClone(fixture.graph);
            if (row.remove) graph.splice(graph.findIndex(item => item.id === row.id), 1);
            else row.change(graph.find(item => item.id === row.id));
            w.audio.snapshot(graph, "full");
            assert.equal(w.audio.echoRoute.state, "pending", row.name);
            assert.equal(w.audio.echoActive(), false, row.name + " grants no overlap");
            assert.equal(w.audio.device("microphones", "microphone", w.runner.state.settings, "duplex"), fixture.targets.microphone,
                row.name + " changes the check source with the actual route");
        }
        w.audio.snapshot(fixture.graph, "full");
        w.audio.snapshot([{ id: 13, type: "PipeWire:Interface:Node", info: { props: {
            "node.name": "physical.usb", "media.class": "Audio/Source", "device.id": 9 } } }]);
        w.dispatch("snapshot", { locked: false, configured: true, engine: "duplex", echoCancel: true,
            settings: { microphone: "physical.usb", speaker: "" } });
        assert.equal(w.audio.echoRoute.reason, "targets-changed", "a new physical setting needs explicit setup again");
        assert.equal(w.audio.echoActive(), false);
        w.dispatch("snapshot", { locked: false, configured: true, engine: "duplex", echoCancel: false,
            settings: { microphone: "", speaker: "" } });
        w.audio.snapshot(fixture.graph, "full");
        const crowded = Array.from({ length: 32 }, (_, i) => ({ id: 100 + i, type: "PipeWire:Interface:Node",
            info: { props: { "node.name": "a.mic." + i, "media.class": "Audio/Source", "device.id": i + 100 } } }));
        w.audio.snapshot([...fixture.graph, ...crowded], "full");
        assert.equal(w.audio.echoActive(), false, "raw pair presence outside bounded target offers grants no overlap");
        w.audio.snapshot(fixture.graph, "full");
        w.audio.capture = { target: fixture.targets.microphone };
        assert.equal(w.audio.echoActive(), false, "an existing physical recorder cannot inherit full duplex");
        w.audio.capture = null;
        const child = {};
        w.audio.children.set(child, { kind: "playback", target: fixture.targets.speaker, stopping: true });
        assert.equal(w.audio.echoActive(), false, "retiring physical audio waits for its actual exit");
        w.audio.children.delete(child);
        assert.equal(w.audio.echoActive(), true);
        w.audio.snapshot([{ id: 31, info: null }]);
        assert.equal(w.audio.echoActive(), false, "monitor removal revokes route admission");
        w.audio.snapshot(fixture.graph, "full");
        const overlap = { ids: new Set([31]), defaults: false };
        w.audio.snapshot([{ id: 31, info: { state: "error" }, type: "PipeWire:Interface:Link" }]);
        w.audio.snapshot(fixture.graph, "full", overlap);
        assert.equal(w.audio.echoActive(), false, "an older full read cannot revive a failed monitor link");
    } finally { w.audio.capture = null; w.audio.children.clear(); w.runner.close(); await w.audio.close("test-end"); }
}

function echoInstallation() {
    const root = fs.mkdtempSync(path.join(process.env.HOME, "echo-setup-")), targets = echoGraph().targets;
    const environment = { HOME: root }, file = EchoCancel.location(environment);
    try {
        assert.equal(EchoCancel.read(environment).state, "absent");
        const installed = cp.spawnSync(process.execPath, [path.join(tree, "shell/plugins/vgs.jarvis/backend/echo-cancel-setup.js"), "install", tree], {
            env: { HOME: root, PATH: process.env.PATH }, input: JSON.stringify(targets), encoding: "utf8", timeout: 10000
        });
        assert.equal(installed.error, undefined);
        assert.equal(installed.status, 0, installed.stderr);
        const before = fs.statSync(file);
        assert.equal(EchoCancel.read(environment).state, "installed");
        const content = fs.readFileSync(file, "utf8");
        for (const clause of ["name = libpipewire-module-echo-cancel", "library.name = aec/libspa-aec-webrtc",
            "webrtc.noise_suppression = false", "webrtc.gain_control = false", "webrtc.high_pass_filter = true",
            'target.object = "physical.mic"', 'target.object = "physical.speaker"',
            "node.name = jarvis_ec_source", "node.name = jarvis_ec_sink"])
            assert.equal(content.includes(clause), true, "PipeWire consumes the native configuration: " + clause);
        assert.equal(EchoCancel.install(environment, targets).changed, false);
        const after = fs.statSync(file);
        assert.equal(after.ino, before.ino, "unchanged setup keeps the existing file");
        assert.equal(after.mtimeMs, before.mtimeMs, "unchanged setup needs no restart");
        const rename = fs.renameSync;
        try {
            fs.renameSync = () => { throw Object.assign(new Error("fixture replacement failed"), { code: "EIO" }); };
            assert.throws(() => EchoCancel.install(environment, { ...targets, microphone: "physical.usb" }), { code: "EIO" });
            assert.equal(fs.readFileSync(file, "utf8"), content, "a failed replacement preserves the complete installed file");
            assert.deepEqual(fs.readdirSync(path.dirname(file)), [path.basename(file)]);
        } finally { fs.renameSync = rename; }
        const link = fs.linkSync;
        fs.unlinkSync(file);
        try {
            fs.linkSync = () => { throw Object.assign(new Error("fixture publication failed"), { code: "EIO" }); };
            assert.throws(() => EchoCancel.install(environment, targets), { code: "EIO" });
            assert.equal(fs.existsSync(file), false, "a failed publication exposes no partial configuration");
            assert.deepEqual(fs.readdirSync(path.dirname(file)), [], "the owned temporary file is removed");
        } finally { fs.linkSync = link; }
        for (const row of [
            { name: "foreign", prepare: () => fs.writeFileSync(file, "# User configuration\n"), read: () => fs.readFileSync(file, "utf8") },
            { name: "edited owned", prepare: () => fs.writeFileSync(file, EchoCancel.render(targets) + "# User edit\n"), read: () => fs.readFileSync(file, "utf8") },
            { name: "linked", prepare: () => fs.symlinkSync(path.join(root, "keep"), file), read: () => fs.readlinkSync(file) }
        ]) {
            fs.writeFileSync(path.join(root, "keep"), "keep\n");
            row.prepare();
            const unchanged = row.read();
            assert.equal(EchoCancel.read(environment).state, "foreign", row.name);
            assert.throws(() => EchoCancel.install(environment, targets), { message: /^echo-cancel-/ }, row.name);
            assert.equal(row.read(), unchanged, row.name + " remains unchanged");
            assert.equal(fs.readFileSync(path.join(root, "keep"), "utf8"), "keep\n");
            fs.unlinkSync(file);
        }
        const linkedRoot = path.join(root, "linked-config");
        fs.symlinkSync(path.dirname(path.dirname(file)), linkedRoot);
        assert.equal(EchoCancel.read({ HOME: root, XDG_CONFIG_HOME: linkedRoot }).state, "foreign");
        assert.throws(() => EchoCancel.install({ HOME: root, XDG_CONFIG_HOME: linkedRoot }, targets), { message: /^echo-cancel-config-/ });
    } finally { fs.rmSync(root, { recursive: true, force: true }); }
}

function setup(Implementation = Audio, sink = null, source = null, clock = null, spoken = true) {
    const levels = [], offers = [], faults = [];
    let frames = 0, at = 0;
    const audio = new Implementation({
        session: Session, environment: { PATH: process.env.PATH, HOME: process.env.HOME,
            XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR, VGSHELL_RUNNER_PID: "secret-runner",
            OPENAI_API_KEY: "fixture-key", ANTHROPIC_API_KEY: "fixture-key" },
        clock: clock || { now: () => at, set: (fn, ms) => setTimeout(fn, ms), clear: timer => clearTimeout(timer) },
        offers: value => offers.push(value),
        level: (gen, value) => levels.push({ gen, value, at }),
        fault: value => faults.push(value),
        captureSink: e => typeof sink === "function" ? sink(e)
            : sink || new Writable({ write(frame, encoding, done) { frames++; at += 10; done(); } }),
        playbackSource: () => ({ readable: source || new PassThrough(), spoken })
    });
    const ports = unavailable();
    ports.transcript = () => {}; // Captions are outside this audio lifetime surface.
    ports.capture = { ...ports.capture, ...audio.capturePort,
        collect: () => {} }; // Speech is outside this audio lifetime surface.
    ports.playback = audio.playbackPort;
    ports.voiceMute = { store: () => {} }; // Its record is the daemon's.
    ports.brain.send = () => {}; // No speech/brain implementation enters this audio fixture.
    // Session's clock, which release() moves past a tap.
    let skew = 0;
    // Each fault the runner publishes, once per change: Service.qml logs one
    // `jarvis: fault=` line for each.
    const published = [];
    const runner = new SessionRunner(Session, ports, {
        now: () => performance.now() + skew, set: (fn, ms) => setTimeout(fn, ms), clear: timer => clearTimeout(timer)
    }, s => {
        audio.observe(s);
        if (s.fault.kind !== "none" && JSON.stringify(s.fault) !== JSON.stringify(published.at(-1)))
            published.push({ ...s.fault });
        if (s.gate.kind === "down") void audio.teardown("gate", ["capture", "playback"]);
    });
    const dispatch = (type, values = {}) => runner.dispatch({ type, ...values });
    dispatch("snapshot", { locked: false, engine: "chained", configured: true,
        settings: { microphone: "", speaker: "", holdToTalk: true } });
    dispatch("indicator", { gen: runner.state.gen, shown: true, bar: "gone" });
    // A Talk release that ends a hold: past Session's tap bound, so it
    // closes the capture.
    const release = () => { skew += Session.TAP_MS; dispatch("talk-up"); };
    // A later Talk press in toggle mode: past Session's 250 ms debounce
    // (Session.js::bounced), so it toggles however soon the fixture reaches it.
    const press = () => { skew += 250; dispatch("talk-down"); };
    return { audio, runner, dispatch, release, press, levels, offers, faults, published, frames: () => frames, tick: ms => { at += ms; } };
}

async function capture(w) {
    w.dispatch("talk-down");
    await until(() => w.runner.state.capture.kind === "open", "capture opens from real PCM");
    await until(() => fs.readdirSync(process.env.HOME).some(name => name.endsWith(".lock")) && !unlocked(),
        "fixture descendant actually holds its lock");
}

// Exercise Audio's real capture feed with a held recorder close. No child or
// device runs; the fake boundary supplies only raw PCM and its exit receipt.
async function cloudInput(Implementation = Audio) {
    const writes = [], ends = [], readings = [], failures = [];
    let finish;
    const closed = new Promise(resolve => { finish = resolve; });
    const stdout = new PassThrough(), lease = new PassThrough();
    const child = { stdout, stdin: new PassThrough(), stdio: [null, null, null, lease] };
    const owner = { child, kind: "capture", stopping: false, closed };
    const feed = new Writable({ write(pcm, encoding, done) { writes.push(Buffer.from(pcm)); done(); } });
    feed.endInput = () => { ends.push(writes.length); return true; };
    const audio = new Implementation({ session: { canCapture: () => true }, environment: {},
        clock: { now: () => 0, set: () => ({}), clear() {} }, offers() {}, level() {}, fault: value => failures.push(value),
        captureSink: () => feed, playbackSource: null, input: value => readings.push(value) });
    audio.observe({ engine: { kind: "duplex" }, settings: {} });
    audio.discover = async () => {};
    audio.selected = async () => ({ target: "fixture.mic", from: "default" });
    audio.spawn = async () => { audio.children.set(child, owner); return owner; };
    void closed.then(() => audio.children.delete(child));
    const pcm = value => {
        const bytes = Buffer.alloc(960);
        for (let at = 0; at < bytes.length; at += 2) bytes.writeInt16LE(value, at);
        return bytes;
    };
    const send = (value, count) => { for (let i = 0; i < count; i++) stdout.emit("data", pcm(value)); };
    try {
        await audio.openCapture({ gen: 3, op: 7, mode: "conversation" }, () => {}, reason => failures.push(reason));
        send(0, 110);
        assert.deepEqual(writes, [], "digital silence never leaves for the cloud");
        assert.deepEqual(readings, [{ type: "input-silent", gen: 3, op: 7, device: "fixture.mic" }],
            "one nonblocking hint belongs to the microphone capture");
        send(128, 20);
        assert.deepEqual(writes, [], "quiet background frames stay on this computer");
        send(8192, 1);
        send(0, 30);
        assert.equal(ends.length, 1, "the captured hangover ends one native input");
        assert.ok(ends[0] >= 6 && ends[0] <= 26, "a short actual hangover follows the speech frame");
        assert.deepEqual(writes[0], pcm(8192), "the real speech frame is forwarded");
        assert.ok(writes.slice(1).every(bytes => bytes.equals(pcm(0))), "hangover contains only actual captured frames");
        assert.equal(readings.filter(value => value.type === "input-sound").length, 1, "sound clears the hint once");
        send(8192, 1);
        let result = null;
        const ending = audio.capturePort.close({ gen: 3, op: 8, target: 7 }, value => { result = value; }, error => { throw error; });
        assert.equal(owner.stopping, true, "microphone shutdown starts before native-end acknowledgement");
        assert.equal(ends.length, 2, "recorder close finishes the active native input");
        assert.equal(result, null, "capture-close waits for the held recorder exit");
        finish();
        await ending;
        assert.deepEqual(result, { speech: true }, "the close reports queued audio, not recognition");
        assert.equal(feed.destroyed, true);
        assert.deepEqual(failures, []);
    } finally { finish(); await audio.close("test-end"); }
}

async function trigger(Implementation, type) {
    const w = setup(Implementation);
    try {
        await capture(w);
        if (type === "indicator") w.dispatch("indicator", { gen: w.runner.state.gen, shown: false, bar: "gone" });
        else if (type === "provider") w.audio.failCapture("provider-disconnected", "");
        else if (type === "lease") w.runner.close();
        else w.dispatch("snapshot", { locked: type === "unknown" ? null : true, engine: "chained", configured: true,
            settings: w.runner.state.settings });
        await until(() => w.runner.state.capture.kind === "closed", type + " acknowledgment");
        assert.equal([...w.audio.children.values()].filter(owner => owner.kind !== "discovery").length, 0,
            type + " leaves no audio process");
        assert.equal(unlocked(), true, type + " leaves no detached descendant");
        if (type === "provider") assert.equal(w.runner.state.fault.reason, "provider-disconnected");
    } finally { w.runner.close(); await w.audio.close("test-end"); }
}

async function inside() {
    let controls = 0;
    async function firstPlayback(Implementation = Audio) {
        const source = Readable.from([Buffer.alloc(480)]);
        const w = setup(Implementation, null, source);
        try {
            w.dispatch("snapshot", { configured: true, locked: false, engine: "chained", settings: { sounds: true } });
            w.dispatch("talk-down");
            await until(() => w.runner.state.playback.kind === "idle" || w.runner.state.fault.kind === "error",
                "the first sound finishes without prior capture");
            assert.equal(w.runner.state.fault.kind, "none", "playback discovers the selected speaker before capture");
            assert.ok(w.offers.some(offers => offers.speakers.some(item => item.value === "fixture.speaker")));
            await until(() => w.runner.state.capture.kind === "open", "capture starts after feedback drains");
        } finally { w.runner.close(); await w.audio.close("test-end"); }
    }
    await cloudInput();
    await echoRoutes();
    echoInstallation();
    await firstPlayback();
    async function desktopDefaults(Implementation = Audio) {
        const w = setup(Implementation);
        const metadata = entries => ({ id: 4, type: "PipeWire:Interface:Metadata",
            props: { "metadata.name": "default" }, metadata: entries });
        const entry = (key, name) => ({ subject: 0, key, type: "Spa:String:JSON", value: { name } });
        const groups = [
            { group: "microphones", setting: "microphone", media: "Audio/Source", key: "default.audio.source" },
            { group: "speakers", setting: "speaker", media: "Audio/Sink", key: "default.audio.sink" }
        ];
        try {
            const nodes = groups.flatMap((row, i) => ["a.first", "z.default"].map((name, j) => ({
                id: 10 + i * 2 + j, type: "PipeWire:Interface:Node",
                info: { props: { "media.class": row.media, "node.name": name + "." + row.setting } }
            })));
            w.audio.snapshot([...nodes, metadata(groups.map(row => entry(row.key, "z.default." + row.setting)))]);
            for (const row of groups) {
                assert.equal(w.audio.devices[row.group][0].value, "a.first." + row.setting);
                assert.equal((await w.audio.selected(row.group, row.setting)).target, "z.default." + row.setting);
                assert.equal(w.runner.state.settings[row.setting], "");
            }
            // Configured defaults and other metadata stores are not the active desktop choice.
            w.audio.snapshot([...nodes, metadata([...groups.map(row => entry(row.key, "z.default." + row.setting)),
                entry("default.configured.audio.source", "a.first.microphone")]),
                { ...metadata([entry("default.audio.source", "a.first.microphone")]), id: 5,
                    props: { "metadata.name": "other" } }], "full");
            assert.equal((await w.audio.selected("microphones", "microphone")).target, "z.default.microphone");
            w.audio.snapshot([metadata([entry("default.audio.source", "a.first.microphone")])]);
            assert.equal((await w.audio.selected("microphones", "microphone")).target, "a.first.microphone");
            w.dispatch("snapshot", { locked: false, engine: "chained", configured: true,
                settings: { microphone: "z.default.microphone", speaker: "a.first.speaker" } });
            for (const row of groups)
                assert.deepEqual(await w.audio.selected(row.group, row.setting),
                    { target: w.runner.state.settings[row.setting], from: "setting" });
            w.dispatch("snapshot", { locked: false, engine: "chained", configured: true,
                settings: { microphone: "", speaker: "" } });
            w.audio.snapshot([{ id: 4, info: null }]);
            for (const row of groups)
                await assert.rejects(w.audio.selected(row.group, row.setting), { message: /^device-lost target=null from=default / });
            w.audio.snapshot([metadata(groups.map(row => entry(row.key, "z.default." + row.setting)))]);
            w.audio.snapshot(nodes, "full");
            for (const row of groups)
                await assert.rejects(w.audio.selected(row.group, row.setting), { message: /^device-lost / });
        } finally { w.runner.close(); await w.audio.close("test-end"); }
    }
    await desktopDefaults();
    const store = entries => [{ id: 4, type: "PipeWire:Interface:Metadata",
        props: { "metadata.name": "default" }, metadata: entries }];
    const microphone = w => w.audio.selected("microphones", "microphone").then(choice => choice.target, error => error.message);
    // The cachy loss, recorded in the nested sandbox: a stream's target entry,
    // the stream's removal, then the store's empty delta. pw-dump prints that
    // removal of the entry as `metadata: []`; the default stays named.
    async function emptyDelta(Implementation = Audio) {
        const w = setup(Implementation);
        try {
            await capture(w);
            w.audio.snapshot(store([{ subject: 62, key: "target.object", type: null, value: "\"fixture.mic\"" }]));
            w.audio.snapshot([{ id: 62, info: null }]);
            w.audio.snapshot(store([]));
            assert.equal(w.runner.state.capture.kind, "open", "an open capture stays open");
            assert.equal(await microphone(w), "fixture.mic");
            w.release();
            await until(() => w.runner.state.capture.kind === "closed", "the capture closes");
            w.audio.snapshot(store([]));
            await capture(w);
            assert.equal(w.runner.state.fault.kind, "none");
        } finally { w.runner.close(); await w.audio.close("test-end"); }
    }
    await emptyDelta();
    // A delta that hid the default's own removal, a new default, and a
    // store delta during the read, which is newer than the read may be.
    async function defaultRemoval(Implementation = Audio) {
        const w = setup(Implementation);
        const usb = { id: 93, type: "PipeWire:Interface:Node",
            info: { props: { "media.class": "Audio/Source", "node.name": "fixture.usb" } } };
        const named = name => store([{ subject: 0, key: "default.audio.source", type: "Spa:String:JSON", value: { name } }]);
        try {
            await w.audio.discover();
            fs.writeFileSync(path.join(process.env.HOME, "no-default-source"), "");
            w.audio.snapshot(store([]));
            const offered = w.offers.length;
            await assert.rejects(w.audio.selected("microphones", "microphone"),
                { message: 'device-lost target=null from=default microphones=1["fixture.mic"]' });
            // jarvisd re-reads its check source on each offer.
            assert.equal(w.offers.length, offered + 1, "a read that moves the default microphone re-sends the offers");
            w.audio.snapshot([usb, ...named("fixture.usb")]);
            assert.equal(await microphone(w), "fixture.usb", "Jarvis follows the default the store names");
            fs.rmSync(path.join(process.env.HOME, "no-default-source"));
            w.audio.snapshot(store([]));
            const read = microphone(w);
            w.audio.snapshot(named("fixture.usb"));
            assert.deepEqual([await read, w.audio.defaults.microphones], ["fixture.usb", "fixture.usb"],
                "a read naming fixture.mic never replaces a newer delta");
            // No store at all: pw-dump prints nothing, and no default is named.
            fs.writeFileSync(path.join(process.env.HOME, "no-objects"), "");
            w.audio.snapshot(store([]));
            assert.equal(await microphone(w), 'device-lost target=null from=default microphones=2["fixture.mic","fixture.usb"]');
        } finally {
            w.runner.close();
            await w.audio.close("test-end");
            for (const name of ["no-default-source", "no-objects"])
                fs.rmSync(path.join(process.env.HOME, name), { force: true });
        }
    }
    await defaultRemoval();
    for (const type of ["locked", "unknown", "indicator", "provider", "lease"])
        await trigger(Audio, type);
    const retired = setup();
    retired.runner.close();
    await retired.audio.close("lease");
    await assert.rejects(retired.audio.discover(), { message: "audio-start-refused" });
    assert.equal(retired.audio.children.size, 0);
    const w = setup();
    try {
        await capture(w);
        await until(() => w.frames() >= 15, "level samples");
        assert.ok(w.levels.length > 0);
        assert.deepEqual(w.levels[0].value, { capture: 0.5, playback: 0 });
        for (let i = 1; i < w.levels.length; i++)
            assert.ok(w.levels[i].at - w.levels[i - 1].at >= 1000 / 30);
        const argv = fs.readFileSync(path.join(process.env.HOME, "audio-argv"), "utf8").trim().split("\n").map(JSON.parse);
        assert.ok(argv.some(row => row.command === "pw-record" && row.argv.includes("fixture.mic")));
        const record = argv.find(row => row.command === "pw-record");
        assert.deepEqual(JSON.parse(record.argv[record.argv.indexOf("--properties") + 1]),
            { "node.dont-fallback": true, "node.dont-reconnect": true });
        for (const row of argv) {
            assert.equal(row.env.VGSHELL_RUNNER_PID, undefined);
            assert.equal(row.env.OPENAI_API_KEY, undefined);
            assert.equal(row.env.ANTHROPIC_API_KEY, undefined);
        }
        assert.deepEqual(w.offers.at(-1), {
            microphones: [{ label: "Fixture microphone", value: "fixture.mic" }],
            speakers: [{ label: "Fixture speaker", value: "fixture.speaker" }]
        });
    } finally { w.runner.close(); await w.audio.close("test-end"); }

    for (const [name, setting, reason] of [["no-devices", "", "device-lost target=null from=default microphones=0[]"],
        ["unavailable-id", "missing.mic", 'device-lost target="missing.mic" from=setting microphones=1["fixture.mic"]']]) {
        const w = setup();
        if (name === "no-devices") fs.writeFileSync(path.join(process.env.HOME, name), "");
        w.dispatch("snapshot", { locked: false, engine: "chained", configured: true,
            settings: { microphone: setting, speaker: "" } });
        w.dispatch("talk-down");
        await until(() => w.runner.state.fault.kind === "error" && w.runner.state.capture.kind === "closed",
            "three device retries end");
        assert.equal(w.runner.state.fault.retry, 3);
        assert.equal(w.runner.state.fault.reason, reason, "the fault names the target and what the read held");
        assert.equal(w.runner.state.settings.microphone, setting, "never rewrite unavailable configured id");
        w.runner.close();
        await w.audio.close("test-end");
        if (name === "no-devices") fs.unlinkSync(path.join(process.env.HOME, name));
    }
    const failed = setup();
    fs.writeFileSync(path.join(process.env.HOME, "capture-exits"), "");
    failed.dispatch("talk-down");
    await until(() => failed.runner.state.fault.kind === "error" && failed.runner.state.capture.kind === "closed",
        "exiting capture gives its actual cause");
    assert.equal(failed.runner.state.fault.retry, 0);
    assert.equal(failed.runner.state.fault.reason, "capture-exit-1");
    failed.runner.close();
    await failed.audio.close("test-end");
    fs.unlinkSync(path.join(process.env.HOME, "capture-exits"));

    async function startupFailure(Implementation = Audio) {
        const w = setup(Implementation, () => {
            const sink = new Writable({ write(frame, encoding, done) { done(); } });
            queueMicrotask(() => sink.destroy(new Error("synthetic provider disconnect")));
            return sink;
        });
        try {
            w.dispatch("talk-down");
            await until(() => w.runner.state.fault.kind === "error" && w.runner.state.capture.kind === "closed",
                "provider loss during startup ends the capture set");
            assert.equal(w.runner.state.fault.reason, "provider-disconnected");
            assert.equal([...w.audio.children.values()].filter(owner => owner.kind !== "discovery").length, 0);
        } finally { w.runner.close(); await w.audio.close("test-end"); }
    }
    await startupFailure();

    async function retiredSink(Implementation = Audio) {
        const sinks = [];
        const w = setup(Implementation, () => {
            const sink = new Writable({ write(frame, encoding, done) { done(); } });
            sinks.push(sink);
            return sink;
        });
        try {
            await capture(w);
            w.release();
            await until(() => w.runner.state.capture.kind === "closed", "first capture exits");
            await capture(w);
            const before = w.runner.state.capture.op;
            sinks[0].emit("error", new Error("late retired provider callback"));
            await w.audio.release;
            assert.equal(w.runner.state.capture.kind, "open");
            assert.equal(w.runner.state.capture.op, before);
            assert.equal(w.runner.state.fault.kind, "none");
        } finally { w.runner.close(); await w.audio.close("test-end"); }
    }
    await retiredSink();

    fs.writeFileSync(path.join(process.env.HOME, "lost-before-monitor-trigger"), "");
    const earlyLoss = setup();
    try {
        earlyLoss.dispatch("talk-down");
        await until(() => earlyLoss.runner.state.fault.kind === "error" && earlyLoss.runner.state.capture.kind === "closed",
            "a stream exit before monitor removal still gets three device retries");
        // The stream exit names the target it held; the retries' selections
        // find no default after the full read.
        assert.deepEqual(earlyLoss.published[0],
            { kind: "retrying", reason: 'device-lost target="fixture.mic" from=default microphones=0[]', retry: 1 });
        assert.equal(earlyLoss.runner.state.fault.reason, "device-lost target=null from=default microphones=0[]");
        assert.equal(earlyLoss.runner.state.fault.retry, 3);
    } finally {
        earlyLoss.runner.close();
        await earlyLoss.audio.close("test-end");
        for (const name of ["lost-before-monitor-trigger", "lost-before-monitor"])
            fs.rmSync(path.join(process.env.HOME, name), { force: true });
    }

    async function playback(Implementation = Audio) {
        const source = new PassThrough();
        const w = setup(Implementation, null, source);
        try {
            await capture(w);
            w.dispatch("final", { gen: w.runner.state.turn.gen, op: w.runner.state.turn.op, text: "fixture" });
            await until(() => w.runner.state.capture.kind === "closed", "capture ends before playback");
            w.dispatch("play", { gen: w.runner.state.turn.gen, op: w.runner.state.turn.op, interruptible: true });
            w.tick(40);
            const frame = Buffer.alloc(480);
            for (let i = 0; i < frame.length; i += 2) frame.writeInt16LE(8192, i);
            source.write(frame);
            await until(() => [...w.audio.children.values()].some(owner => owner.kind === "playback"),
                "real playback child starts");
            await until(() => !unlocked(), "playback descendant holds a lock");
            await until(() => w.levels.some(row => row.value.playback === 0.25), "playback RMS is published");
            assert.deepEqual(w.levels.at(-1).value, { capture: 0, playback: 0.25 });
            for (let i = 1; i < w.levels.length; i++)
                assert.ok(w.levels[i].at - w.levels[i - 1].at >= 1000 / 30, "combined channel rate");
            w.dispatch("interrupt");
            await until(() => w.runner.state.playback.kind === "idle", "interrupt waits for playback exit");
            assert.equal(unlocked(), true, "interrupt kills detached playback descendants");
            assert.equal(source.destroyed, true, "interrupt ends the provider audio feed");
            const calls = fs.readFileSync(path.join(process.env.HOME, "audio-argv"), "utf8").trim().split("\n").map(JSON.parse);
            assert.ok(calls.some(row => row.command === "pw-cat" && row.argv.includes("fixture.speaker")
                && row.argv.includes("20ms") && row.argv.includes("24000")));
            const cat = calls.filter(row => row.command === "pw-cat").at(-1);
            assert.deepEqual(JSON.parse(cat.argv[cat.argv.indexOf("--properties") + 1]),
                { "node.dont-fallback": true, "node.dont-reconnect": true });
        } finally { w.runner.close(); await w.audio.close("test-end"); }
    }
    await playback();

    async function halfDuplex(Implementation = Audio, operation = "complete") {
        const source = new PassThrough();
        const w = setup(Implementation, null, source);
        try {
            w.dispatch("snapshot", { configured: true, locked: false, engine: "chained",
                settings: { ...w.runner.state.settings, holdToTalk: false } });
            w.dispatch("talk-down");
            await until(() => w.runner.state.capture.kind === "open", "conversation capture opens");
            w.dispatch("final", { gen: w.runner.state.turn.gen, op: w.runner.state.turn.op, text: "fixture" });
            await until(() => w.runner.state.capture.kind === "open", "conversation capture reopens after final");
            const sink = w.audio.feed;
            w.dispatch("play", { gen: w.runner.state.turn.gen, op: w.runner.state.turn.op, interruptible: true });
            source.write(Buffer.alloc(480));
            await until(() => w.audio.playback !== null && w.audio.playback.kind === "feeding",
                "playback starts after recorder exit");
            w.dispatch("brain-done", { gen: w.runner.state.turn.gen, op: w.runner.state.turn.op });
            assert.equal(w.runner.state.duplex.kind, "half");
            assert.equal(w.runner.state.capture.kind, "closed");
            assert.equal(w.audio.capture, null, "half duplex has no recorder owner during playback");
            assert.equal(sink.closed, true, "speech receives no microphone feed during playback");
            assert.equal([...w.audio.children.values()].some(owner => owner.kind === "capture"), false);
            const playback = w.runner.state.playback;
            const resumes = ["complete", "interrupt", "stop"].includes(operation);
            if (operation === "complete") source.end();
            else if (operation === "interrupt") w.dispatch("interrupt");
            else if (operation === "talk") w.press();
            else if (operation === "release") {
                w.press();
                w.release();
            }
            else if (operation === "indicator") w.dispatch("indicator", { gen: w.runner.state.gen, shown: false, bar: "gone" });
            else if (operation === "provider") source.destroy(new Error("synthetic provider disconnect"));
            else if (operation === "device") w.audio.snapshot([{ id: 12, info: null }]);
            else if (operation === "lease") w.runner.close();
            else if (operation === "stop") w.dispatch(operation);
            else if (operation === "locked" || operation === "unknown") {
                w.dispatch("snapshot", { locked: operation === "unknown" ? null : true, engine: "chained", configured: true,
                    settings: w.runner.state.settings });
            } else {
                throw new Error("half-duplex fixture operation: " + operation);
            }
            // Indicator loss blocks capture, not playback. Let its real player
            // finish so the same admission check reaches the resume boundary.
            if (operation === "indicator") source.end();
            await until(() => w.runner.state.playback.kind === "idle", operation + " playback ends");
            if (operation === "device")
                assert.equal(w.runner.state.fault.reason, 'device-lost target="fixture.speaker" from=default speakers=0[]');
            assert.equal(source.destroyed, true, "playback release ends the provider source");
            if (resumes) {
                await until(() => w.runner.state.capture.kind === "open", operation + " resumes permitted demand");
                assert.notEqual(w.audio.feed, sink, "resume acquires a new speech feed");
                assert.equal(w.runner.state.input.kind, "conversation");
            } else {
                assert.equal(w.runner.state.capture.kind, "closed", operation + " cannot revive capture");
                assert.equal(w.audio.capture, null);
                assert.equal(unlocked(), true, operation + " releases detached audio children");
            }
            w.dispatch("played", { gen: playback.gen, op: playback.op });
            assert.equal(w.runner.state.playback.kind, "idle", "late player completion cannot restart playback");
            const calls = fs.readFileSync(path.join(process.env.HOME, "audio-argv"), "utf8").trim().split("\n").map(JSON.parse);
            assert.equal(calls.some(row => row.command === "pw-cli"), false, "half duplex loads no module");
        } finally { w.runner.close(); await w.audio.close("test-end"); }
    }
    for (const operation of ["complete", "interrupt", "talk", "release", "stop", "locked", "unknown",
        "indicator", "provider", "device", "lease"]) await halfDuplex(Audio, operation);

    // Voice mute sends the speaker silence of the length of Jarvis's spoken
    // words through the one paced write, for a chained voice's sentences and
    // a duplex voice's bytes alike: the written count and the acknowledgement
    // are a heard reply's, and the level still reads the voice. A source the
    // engine hands as not spoken, a start sound or a preview, and a packet
    // the engine marks a tone inside a spoken source, the working sound, stay
    // audible. Any unmarked packet of a spoken source is silenced, whatever
    // its shape.
    async function voiceMute(Implementation = Audio) {
        const voice = Buffer.alloc(480), tone = Buffer.alloc(480);
        for (let i = 0; i < voice.length; i += 2) { voice.writeInt16LE(8192, i); tone.writeInt16LE(4096, i); }
        const silence = Buffer.alloc(voice.length);
        const words = { pcm: voice, sentence: { text: "fixture", frames: voice.length / 2 } };
        const bytesOf = packets => {
            const source = new Readable({ read() {} });
            for (const packet of packets) source.push(packet);
            source.push(null);
            return source;
        };
        // name, source, spoken, voice muted, the bytes the speaker gets
        const rows = [
            ["chained reply heard", () => Readable.from([words]), true, false, [voice]],
            ["chained reply muted", () => Readable.from([words]), true, true, [silence]],
            ["duplex reply muted", () => bytesOf([voice]), true, true, [silence]],
            ["working sound and reply muted", () => Readable.from([{ pcm: tone, tone: true }, words]), true, true, [tone, silence]],
            ["unmarked bare packet muted", () => Readable.from([voice]), true, true, [silence]],
            ["unmarked pcm packet muted", () => Readable.from([{ pcm: voice }]), true, true, [silence]],
            ["start sound muted", () => Readable.from([tone]), false, true, [tone]],
            ["chained preview muted", () => Readable.from([words]), false, true, [voice]],
            ["duplex preview muted", () => bytesOf([voice]), false, true, [voice]]
        ];
        const record = path.join(process.env.HOME, "playback-record");
        const bytes = path.join(process.env.HOME, "playback-bytes");
        fs.writeFileSync(record, "");
        try {
            for (const [name, source, spoken, muted, expected] of rows) {
                fs.rmSync(bytes, { force: true });
                const w = setup(Implementation, null, source(), null, spoken);
                try {
                    await capture(w);
                    w.dispatch("final", { gen: w.runner.state.turn.gen, op: w.runner.state.turn.op, text: "fixture" });
                    await until(() => w.runner.state.capture.kind === "closed", name + " capture ends before playback");
                    if (muted) w.dispatch("voice-mute-toggle");
                    w.tick(40);
                    w.dispatch("play", { gen: w.runner.state.turn.gen, op: w.runner.state.turn.op, interruptible: true });
                    await until(() => w.runner.state.playback.kind === "idle", name + " playback is acknowledged");
                    assert.deepEqual(fs.readFileSync(bytes), Buffer.concat(expected), name + " speaker bytes");
                    assert.equal(w.audio.lastPlayback.writtenFrames, Buffer.concat(expected).length / 2, name + " written count");
                    if (expected[0] !== tone) assert.ok(w.levels.some(row => row.value.playback === 0.25), name + " level reads the voice");
                } finally { w.runner.close(); await w.audio.close("test-end"); }
            }
        } finally { fs.rmSync(record, { force: true }); fs.rmSync(bytes, { force: true }); }
    }
    await voiceMute();

    async function playbackExit(Implementation = Audio) {
        fs.writeFileSync(path.join(process.env.HOME, "playback-exits"), "");
        const source = new PassThrough();
        const w = setup(Implementation, null, source);
        try {
            await capture(w);
            w.dispatch("final", { gen: w.runner.state.turn.gen, op: w.runner.state.turn.op, text: "fixture" });
            await until(() => w.runner.state.capture.kind === "closed", "capture closes before speech");
            w.dispatch("play", { gen: w.runner.state.turn.gen, op: w.runner.state.turn.op, interruptible: true });
            source.write(Buffer.alloc(480));
            try {
                await until(() => w.runner.state.fault.kind === "error" && w.runner.state.playback.kind === "idle",
                    "an exited player ends a provider feed that stays open");
            } catch (error) {
                assert.fail(error.message + " state=" + JSON.stringify(w.runner.state) + " children=" +
                    JSON.stringify([...w.audio.children.values()].map(owner => ({ kind: owner.kind, exit: owner.exit }))) +
                    " feed=" + JSON.stringify({ closed: source.closed, destroyed: source.destroyed }) +
                    " faults=" + JSON.stringify(w.faults));
            }
            assert.equal(w.runner.state.fault.reason, "playback-exit-1");
            assert.equal(source.destroyed, true);
            assert.equal(unlocked(), true);
        } finally {
            w.runner.close();
            await w.audio.close("test-end");
            fs.unlinkSync(path.join(process.env.HOME, "playback-exits"));
        }
    }
    await playbackExit();

    async function overflow(Implementation = Audio) {
        const sink = new Writable({ highWaterMark: 1048576, write() {} });
        const w = setup(Implementation, sink);
        try {
            await capture(w);
            await until(() => w.runner.state.fault.kind === "error", "bounded capture buffer faults");
            assert.equal(w.runner.state.fault.reason, "capture-overflow");
            await until(() => w.runner.state.capture.kind === "closed", "overflow waits for exits");
            assert.equal(unlocked(), true);
        } finally { w.runner.close(); await w.audio.close("test-end"); }
    }
    await overflow();

    async function discoveryOverflow(Implementation = Audio) {
        fs.writeFileSync(path.join(process.env.HOME, "huge-devices"), "");
        const w = setup(Implementation);
        try {
            await assert.rejects(w.audio.discover(), { message: "discovery-overflow" });
            assert.deepEqual(w.offers.at(-1), { microphones: [], speakers: [] });
        } finally {
            w.runner.close();
            await w.audio.close("test-end");
            fs.unlinkSync(path.join(process.env.HOME, "huge-devices"));
        }
    }
    await discoveryOverflow();

    async function cacheBound(Implementation = Audio) {
        fs.writeFileSync(path.join(process.env.HOME, "extra-properties"), "");
        const w = setup(Implementation);
        try {
            await w.audio.discover();
            assert.ok(w.audio.nodes.size > 0, "the monitor retained real offer nodes");
            for (const node of w.audio.nodes.values())
                assert.ok(Buffer.byteLength(JSON.stringify(node)) <= 1024, "arbitrary properties cannot grow the node cache");
        } finally {
            w.runner.close();
            await w.audio.close("test-end");
            fs.unlinkSync(path.join(process.env.HOME, "extra-properties"));
        }
    }
    await cacheBound();

    function monitorCalls() {
        return fs.readFileSync(path.join(process.env.HOME, "audio-argv"), "utf8").trim().split("\n")
            .map(JSON.parse).filter(row => row.command === "pw-dump" && row.argv.includes("--monitor")).length;
    }
    async function discoveryRecovery(Implementation = Audio, trigger = "monitor-exits") {
        const w = setup(Implementation);
        const marker = path.join(process.env.HOME, trigger);
        try {
            await w.audio.discover();
            const calls = monitorCalls();
            fs.writeFileSync(marker, "");
            await until(() => w.faults.length > 0 && w.offers.some(value => value.microphones.length === 0),
                "unexpected monitor failure removes untrusted offers");
            await until(() => w.offers.at(-1).microphones.length === 1, "discovery restores offers after teardown");
            await w.audio.discover();
            assert.equal(monitorCalls(), calls + 1, "one replacement monitor");
            assert.equal(w.audio.discovery.kind, "monitoring");
            assert.equal(w.faults.some(value => value.startsWith(trigger === "monitor-exits"
                ? "discovery-exit" : "discovery-framing")), true);
        } finally {
            w.runner.close();
            await w.audio.close("test-end");
            fs.rmSync(marker, { force: true });
        }
    }
    for (const trigger of ["monitor-exits", "monitor-malformed"]) await discoveryRecovery(Audio, trigger);

    async function discoveryBound(Implementation = Audio) {
        const w = setup(Implementation);
        const marker = path.join(process.env.HOME, "monitor-crashes");
        try {
            await w.audio.discover();
            const calls = monitorCalls();
            fs.writeFileSync(marker, "");
            await until(() => w.faults.some(value => value.startsWith("discovery-recovery-exhausted:")),
                "automatic monitor recovery stops at its lifetime bound");
            assert.equal(monitorCalls(), calls + 3);
            assert.equal(w.audio.discovery.kind, "failed");
            await assert.rejects(w.audio.discover(), /discovery-recovery-exhausted:/);
            assert.deepEqual(w.offers.at(-1), { microphones: [], speakers: [] });
            assert.equal(w.audio.children.size, 0);
        } finally {
            w.runner.close();
            await w.audio.close("test-end");
            fs.rmSync(marker, { force: true });
        }
    }
    await discoveryBound();

    async function discoveryClose(Implementation = Audio) {
        const timers = new Map();
        const clock = { now: () => 0, set: (fn, ms) => { const timer = {}; timers.set(timer, { fn, ms }); return timer; },
            clear: timer => timers.delete(timer) };
        const w = setup(Implementation, null, null, clock);
        const marker = path.join(process.env.HOME, "monitor-exits");
        try {
            await w.audio.discover();
            const calls = monitorCalls();
            fs.writeFileSync(marker, "");
            await until(() => w.audio.discovery.kind === "waiting", "monitor recovery timer is armed");
            assert.equal(timers.size, 1);
            const scheduled = [...timers.values()][0];
            w.runner.close();
            await w.audio.close("lease");
            assert.equal(timers.size, 0, "close cancels the reconnect timer");
            scheduled.fn();
            assert.equal(monitorCalls(), calls);
            assert.equal(w.audio.children.size, 0);
        } finally {
            await w.audio.close("test-end");
            fs.rmSync(marker, { force: true });
        }
    }
    await discoveryClose();

    // A failed child start or one-shot read stops only its own child: the
    // monitor keeps the list and keeps reporting. A row's fail returns the
    // reason its caller reports. A start fails with no setpriv on the child's
    // PATH, where Node looks a command up:
    // https://nodejs.org/api/child_process.html#child_processspawncommand-args-options
    const reported = w => until(() => w.published.some(fault => fault.kind === "error"), "the failure is published")
        .then(() => w.published.find(fault => fault.kind === "error").reason);
    const read = w => w.audio.refreshDevices().then(() => "read", error => error.message);
    const talk = w => { w.dispatch("talk-down"); return reported(w); };
    const oneShotRows = [
        { name: "read-overflow", markers: ["huge-read"], fail: read, reason: "discovery-overflow" },
        { name: "read-start", start: "fails", fail: read, reason: "audio-child: spawn-ENOENT" },
        { name: "exit-read", markers: ["huge-read", "capture-exits"], fail: talk, reason: "device-probe: discovery-overflow" },
        { name: "capture-start", start: "fails", fail: talk, reason: "audio-start: audio-child: spawn-ENOENT" },
        { name: "playback-start", start: "fails", sounds: true, fail: talk, reason: "audio-child: spawn-ENOENT" }
    ];
    async function oneShotFailure(Implementation = Audio, rows = oneShotRows) {
        for (const row of rows) {
            const w = setup(Implementation);
            const markers = [...(row.markers || []), "remove-device"].map(name => path.join(process.env.HOME, name));
            const PATH = w.audio.environment.PATH;
            try {
                if (row.sounds) w.dispatch("snapshot", { locked: false, engine: "chained", configured: true,
                    settings: { microphone: "", speaker: "", sounds: true } });
                await w.audio.discover();
                const calls = monitorCalls(), offered = w.offers.length;
                for (const marker of markers.slice(0, -1)) fs.writeFileSync(marker, "");
                if (row.start === "fails") w.audio.environment.PATH = path.join(process.env.HOME, "no-commands");
                assert.equal(await row.fail(w), row.reason, row.name);
                w.audio.environment.PATH = PATH;
                assert.deepEqual(w.audio.devices.microphones.map(item => item.value), ["fixture.mic"],
                    row.name + " keeps the monitor's list");
                fs.writeFileSync(markers.at(-1), "");
                await until(() => w.offers.at(-1).microphones.length === 0, row.name + ": the monitor still reports");
                // A retired monitor offers an empty list; the monitor's
                // removal keeps the speaker.
                assert.ok(w.offers.slice(offered).every(offer => offer.speakers.length === 1),
                    row.name + " never empties the list");
                assert.equal(monitorCalls(), calls, row.name + " keeps the first monitor");
            } finally {
                w.audio.environment.PATH = PATH;
                w.runner.close();
                await w.audio.close("test-end");
                for (const marker of markers) fs.rmSync(marker, { force: true });
            }
        }
    }
    await oneShotFailure();

    // A monitor delta during a full read: what the delta named keeps the
    // monitor's state, and the read stands for the rest. The fixture's
    // monitor prints DELTA before the read prints. A row's drive returns what
    // its caller sees: the list and default a read leaves, or the reason a
    // capture exit reports.
    const mic = (id, name) => ({ id, type: "PipeWire:Interface:Node",
        info: { props: { "media.class": "Audio/Source", "node.name": name } } });
    const held = w => w.audio.refreshDevices()
        .then(() => [w.audio.devices.microphones.map(item => item.value), w.audio.defaults.microphones]);
    const exits = async w => {
        await capture(w);
        fs.writeFileSync(path.join(process.env.HOME, "capture-ends"), "");
        await until(() => w.published.length !== 0, "the exit is published");
        return w.published[0];
    };
    const overlapRows = [
        { name: "recreated", markers: ["no-devices"], delta: [{ id: 91, info: null }, mic(92, "fixture.mic")],
            drive: held, seen: [["fixture.mic"], null] },
        { name: "default-moved", markers: [], delta: [mic(93, "fixture.usb"), ...store([{ subject: 0,
            key: "default.audio.source", type: "Spa:String:JSON", value: { name: "fixture.usb" } }])],
            drive: held, seen: [["fixture.mic", "fixture.usb"], "fixture.usb"] },
        // The exiting pw-record's own stream node goes before the monitor
        // reports the microphone's removal, which the read already shows.
        // Session retries only a device-lost exit.
        { name: "recorder-exit", markers: ["no-devices"], delta: [{ id: 77, info: null }], drive: exits,
            seen: { kind: "retrying", reason: 'device-lost target="fixture.mic" from=default microphones=0[]', retry: 1 } }
    ];
    async function readOverlap(Implementation = Audio, rows = overlapRows) {
        for (const row of rows) {
            const w = setup(Implementation);
            const markers = [...row.markers, "read-delta", "capture-ends"].map(name => path.join(process.env.HOME, name));
            try {
                await w.audio.discover();
                for (const marker of markers.slice(0, -2)) fs.writeFileSync(marker, "");
                fs.writeFileSync(markers.at(-2), JSON.stringify(row.delta));
                assert.deepEqual(await row.drive(w), row.seen, row.name);
            } finally {
                w.runner.close();
                await w.audio.close("test-end");
                for (const marker of [...markers, path.join(process.env.HOME, "monitor-delta")])
                    fs.rmSync(marker, { force: true });
            }
        }
    }
    await readOverlap();

    const lost = setup();
    try {
        await capture(lost);
        fs.writeFileSync(path.join(process.env.HOME, "remove-device"), "");
        await until(() => lost.runner.state.fault.kind === "error" && lost.runner.state.capture.kind === "closed",
            "discovery removal closes capture and bounds retries");
        // The monitor's removal writes the first fault, the retries the rest.
        assert.deepEqual(lost.published.map(fault => fault.reason),
            Array(4).fill('device-lost target="fixture.mic" from=default microphones=0[]'));
        assert.equal(lost.runner.state.fault.retry, 3);
        assert.deepEqual(lost.offers.at(-1).microphones, []);
        assert.equal(unlocked(), true);
    } finally { lost.runner.close(); await lost.audio.close("test-end"); }

    const source = fs.readFileSync(file, "utf8");
    async function control(name, needle, replacement, check) {
        assert.equal(source.split(needle).length - 1, 1, name + " match");
        const folder = path.join(process.env.JARVIS_TEST_ROOT, name);
        copyBackend(folder);
        const changed = source.replace(needle, replacement);
        assert.notEqual(changed, source);
        fs.writeFileSync(path.join(folder, "Audio.js"), changed);
        await assert.rejects(() => check(require(path.join(folder, "Audio.js")).Audio), assert.AssertionError);
        controls++;
    }
    await control("cloud-level-gate", 'gate: this.state.engine.kind === "duplex" ?',
        'gate: false ?', cloudInput);
    await control("echo-physical-links", 'if (!linked(microphone[0].id, nodes.capture.id) || !linked(nodes.playback.id, speaker[0].id)) return "links-missing";',
        'if (false && (!linked(microphone[0].id, nodes.capture.id) || !linked(nodes.playback.id, speaker[0].id))) return "links-missing";', echoRoutes);
    await control("echo-semantic-selection", 'if (settings?.microphone !== state.settings.microphone || settings?.speaker !== state.settings.speaker)',
        'if (settings !== state.settings)', echoRoutes);
    await control("silent-hint", "capture.frames >= SILENT_FRAMES", "false", cloudInput);
    await control("native-close-result", "speech: capture.gate.committed", "speech: false", cloudInput);
    await control("desktop-default", 'if (!before.unsettled.includes(group)) return before[group];',
        'if (!before.unsettled.includes(group)) return this.devices[group][0] && this.devices[group][0].value;', desktopDefaults);
    // The base rule: an empty delta read as a cleared store.
    await control("empty-delta", "const prior = node.id === this.defaults.id ? this.defaults : noDefaults(node.id);",
        "const prior = node.id === this.defaults.id && node.metadata.length !== 0 ? this.defaults : noDefaults(node.id);", emptyDelta);
    await control("unsettled-default", '["microphones", "speakers"].filter(group => !(group in named))', "[]", defaultRemoval);
    await control("read-order", "if (this.defaults !== before) return", "if (false) return", defaultRemoval);
    await control("first-playback-discovery", 'await this.discover();\n            if (this.playback !== playback) return;',
        'if (this.playback !== playback) return;', firstPlayback);
    await control("early-capture-ack", "return this.release;", "return Promise.resolve();", async impl => {
        let released;
        const sink = new Writable({ write(frame, encoding, done) { done(); },
            destroy(error, done) { released = () => done(error); } });
        const w = setup(impl, sink);
        try {
            await capture(w);
            w.release();
            await until(() => released !== undefined, "feed close requested");
            await new Promise(resolve => setImmediate(resolve));
            assert.equal(w.runner.state.capture.kind, "closing", "capture acknowledgement waits for feed and process exits");
        } finally {
            if (released) released();
            w.runner.close();
            await w.audio.close("test-end");
        }
    });
    await control("level-rate", "at - this.lastLevel >= 1000 / 30", "at - this.lastLevel >= 0", async impl => {
        const w = setup(impl);
        try {
            await capture(w);
            await until(() => w.levels.length >= 3, "mutant levels");
            assert.ok(w.levels[1].at - w.levels[0].at >= 1000 / 30);
        } finally { w.runner.close(); await w.audio.close("test-end"); }
    });
    await control("env-scrub", "this.environment = {};", "this.environment = { ...environment };", async impl => {
        const w = setup(impl);
        try {
            await capture(w);
            const lines = fs.readFileSync(path.join(process.env.HOME, "audio-argv"), "utf8").trim().split("\n").map(JSON.parse);
            assert.equal(lines.at(-1).env.OPENAI_API_KEY, undefined);
        } finally { w.runner.close(); await w.audio.close("test-end"); }
    });
    await control("capture-bound", "pcm.length > BUFFER_BYTES || feed.writableLength + pcm.length > BUFFER_BYTES",
        "false && (pcm.length > BUFFER_BYTES || feed.writableLength + pcm.length > BUFFER_BYTES)", overflow);
    await control("discovery-bound", "const DISCOVERY_BYTES = 1024 * 1024;",
        "const DISCOVERY_BYTES = 2 * 1024 * 1024;", discoveryOverflow);
    await control("playback-release", 'if (this.playbackFeed !== null)',
        'if (false && this.playbackFeed !== null)', playback);
    await control("playback-level", 'this.reportLevel(playback.e.gen, "playback", pcm);',
        'if (false) this.reportLevel(playback.e.gen, "playback", pcm);', playback);
    await control("voice-mute-silence", 'const out = spoken && this.state.voiceMute.kind === "on" ? Buffer.alloc(bytes) : pcm;',
        'const out = pcm;', voiceMute);
    await control("voice-mute-spoken", "const out = spoken && this.state.voiceMute.kind",
        "const out = this.state.voiceMute.kind", voiceMute);
    await control("voice-mute-tone", "spoken && !tone", "spoken", voiceMute);
    await control("voice-mute-unmarked", "const tone = !Buffer.isBuffer(packet) && packet.tone === true;",
        "const tone = Buffer.isBuffer(packet) || packet.tone === true;", voiceMute);
    await control("voice-mute-level", 'this.reportLevel(playback.e.gen, "playback", pcm);',
        'this.reportLevel(playback.e.gen, "playback", out);', voiceMute);
    await control("node-cache-bound", 'this.nodes.set(node.id, { group, label: label.slice(0, 60), value });',
        'this.nodes.set(node.id, { ...props, group, label: label.slice(0, 60), value });', cacheBound);
    await control("closed-owner", 'this.lifetime.kind === "closed" || (kind !== "discovery"',
        'false || (kind !== "discovery"', async impl => {
        const w = setup(impl);
        w.runner.close();
        await w.audio.close("lease");
        try { await assert.rejects(w.audio.spawn("discovery", "pw-dump"), { message: "audio-start-refused" }); }
        finally { await w.audio.close("test-end"); }
    });
    await control("startup-provider", 'if (this.capture === capture) this.failCapture("provider-disconnected", error.message);',
        'if (false && this.capture === capture) this.failCapture("provider-disconnected", error.message);', startupFailure);
    await control("retired-provider", 'if (this.capture === capture) this.failCapture("provider-disconnected", error.message);',
        'if (true || this.capture === capture) this.failCapture("provider-disconnected", error.message);', retiredSink);
    await control("player-exit", 'this.failPlayback("playback-exit-" + (owner.exit.signal || owner.exit.code));',
        'if (false) this.failPlayback("playback-exit-" + (owner.exit.signal || owner.exit.code));', playbackExit);
    await control("device-fallback", '"node.dont-fallback": true', '"node.dont-fallback": false', playback);
    await control("device-reconnect", '"node.dont-reconnect": true', '"node.dont-reconnect": false', playback);
    await control("half-capture-release", 'this.teardown("capture-close", ["capture"])',
        '(false ? this.teardown("capture-close", ["capture"]) : Promise.resolve())', halfDuplex);
    await control("discovery-retired", 'this.discovery = waiting;',
        'if (false) this.discovery = waiting;', discoveryRecovery);
    await control("discovery-recovery-bound", "if (discovery.retries === 3)", "if (discovery.retries === 4)", discoveryBound);
    await control("discovery-close", 'if (this.discovery.kind === "waiting") this.clock.clear(this.discovery.timer);',
        'if (false && this.discovery.kind === "waiting") this.clock.clear(this.discovery.timer);', discoveryClose);
    await control("closed-discovery", 'if (this.lifetime.kind === "closed") return Promise.reject(new Error("audio-start-refused"));',
        'if (false) return Promise.reject(new Error("audio-start-refused"));', async impl => {
            const w = setup(impl);
            try {
                await w.audio.discover();
                w.runner.close();
                await w.audio.close("lease");
                await assert.rejects(w.audio.discover(), { message: "audio-start-refused" });
            } finally { await w.audio.close("test-end"); }
        });
    await control("one-shot-stop", "void this.stop(owner);",
        'void this.teardown("discovery-overflow", ["discovery"]);', impl => oneShotFailure(impl, oneShotRows.slice(0, 1)));
    await control("start-stop", "catch (error) { await this.stop(owner); throw error; }",
        'catch (error) { await this.teardown("start-failed", [kind]); throw error; }',
        impl => oneShotFailure(impl, oneShotRows.slice(1, 2)));
    await control("exit-read-list", 'this.fault("device-probe: " + error.message);',
        'this.nodes.clear(); this.devices = { microphones: [], speakers: [] }; this.fault("device-probe: " + error.message);',
        impl => oneShotFailure(impl, oneShotRows.slice(2, 3)));
    await control("overlap-nodes", "for (const id of overlap.ids)", "for (const id of [])",
        impl => readOverlap(impl, overlapRows.slice(0, 1)));
    await control("overlap-defaults", "if (overlap.defaults) this.defaults = held.defaults;",
        "if (false) this.defaults = held.defaults;", impl => readOverlap(impl, overlapRows.slice(1, 2)));
    await control("default-offer", "if (read.microphones !== before.microphones) this.offers(this.devices);",
        "if (false) this.offers(this.devices);", defaultRemoval);
    await control("empty-read", 'text.trim() === "" ? [] : JSON.parse(text)', "JSON.parse(text)", defaultRemoval);
    console.log("test-jarvis-audio: ok triggers=5 controls=" + controls);
}

if (process.argv[2] !== "--inside") hungWorld();
world(inside).catch(error => { console.error(error); process.exitCode = 1; });
