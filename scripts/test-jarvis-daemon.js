#!/usr/bin/env node
// Synthetic fixture from JarvisProtocol.js, 2026-09-30. All daemon
// cases and controls run in J09's private network/PID world.
"use strict";
const assert = require("node:assert/strict");
const cp = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { once } = require("node:events");
const { freshSuite, shellState } = require("./fixtures/jarvis/prepare.js");
const { runBounded, hungWorldControl } = require("./fixtures/jarvis/bounded.js");
const { REPLY: scriptedReply, instrument, chainedEngine } = require("./fixtures/jarvis/scripted.js");
const { jarvisHome } = require("./fixtures/jarvis/home.js");
const { standins } = require("./fixtures/jarvis/audio.js");
const desktopFixture = require("./fixtures/jarvis/desktop.js");
const { instrument: instrumentDesktop } = require("./fixtures/jarvis/desktop-driver.js");
const tree = path.resolve(__dirname, "..");
// A held release uses Session's own press clock and tap boundary.
const { TAP_MS, TOGGLE_DEBOUNCE_MS } = require("../bin/lib/qml-library.js").load(path.join(tree, "shell/plugins/vgs.jarvis/Session.js"));
// The daemon's held snapshot acknowledges the press on its Session clock.
// Advance only that disposable clock; a parent's write time says nothing
// about when the child's event loop consumed the press.
// Stay inside the held interval: adding exactly TAP_MS can round below it.
function releaseHeld(clock, state, send) {
    assert.equal(state.input.kind, "held", "a held release needs the daemon's press acknowledgment");
    fs.writeFileSync(clock, String(state.input.since + 2 * TAP_MS));
    send();
}
const daemon = path.join(tree, "shell/plugins/vgs.jarvis/backend/jarvisd.js");
const source = fs.readFileSync(daemon, "utf8");
const hello = { v: 1, type: "hello", gen: 0, settings: { home: "", sounds: false, holdToTalk: true, microphone: "", speaker: "", brain: "", model: "", effort: "", fallbacks: [], taskTerminal: "auto", voiceProvider: "local", voiceAccount: "", voice: "", clonedVoice: false, dictation: "",
    cloudVision: "ask", memoryNotes: "ask", privateWindows: "bitwarden", mainHost: "", weeklyOpenaiCap: 25 }, directories: {
    state: "/private/state", data: "/private/data", runtime: "/private/runtime"
}, revision: "a".repeat(64), locked: false,
keys: { talk: "SUPER+code:44", deny: null, stop: "SUPER+CTRL+X", confirm: "SUPER+CTRL+Y", console: "SUPER+ALT+C", "voice-mute": "SUPER+CTRL+M" } };
// The rows of a file another process appends to. Every writer ends a row
// with a newline, so the text after the last one is a row still being
// written: a poll skips it rather than parse half a row.
const lines = file => fs.existsSync(file)
    ? fs.readFileSync(file, "utf8").split("\n").slice(0, -1).filter(Boolean).map(line => JSON.parse(line)) : [];
// The desktop driver polls call.json and parses what it finds, so a call
// appears whole: written under another name, then renamed into place.
const writeCall = (directory, call) => {
    const pending = path.join(directory, ".call.json-" + process.pid);
    fs.writeFileSync(pending, JSON.stringify(call));
    fs.renameSync(pending, path.join(directory, "call.json"));
};
async function homeReply(read, daemon, poll) {
    for (let attempts = 0; ; attempts++) {
        const frames = read().filter(frame => ["start-text", "status"].includes(frame.type));
        const answered = frames.findIndex(frame => frame.type === "status" && frame.daemon === daemon);
        if (answered > 0 && frames[answered - 1].type === "start-text") return frames.slice(answered - 1, answered + 1);
        await poll(attempts);
    }
}
async function homeReplyOrder() {
    const stale = { type: "start-text", size: { kind: "read", layers: [] } };
    const current = { type: "start-text", size: { kind: "read", layers: [{ layer: "home/AGENTS.md", tokens: 2110 }] } };
    const frames = [stale, { type: "status", daemon: "ready" }, { type: "status", daemon: "ready" }];
    const answer = [current, { type: "status", daemon: "locked" }];
    let delivered = 0;
    const own = await homeReply(() => frames, "locked", async () => {
        assert.ok(delivered < answer.length, "the hello reply completes the wait");
        frames.push(answer[delivered++]);
    });
    assert.equal(delivered, answer.length, "extra statuses cannot complete the hello");
    assert.equal(layerTokens(own[0].size, "home/AGENTS.md"), 2110);
    await assert.rejects(() => homeReply(() => [...frames.slice(0, 3), answer[1]], "locked", async () => {
        assert.fail("the hello's own start-text is missing");
    }), assert.AssertionError);
    assert.throws(() => layerTokens(stale.size, "home/AGENTS.md"),
        error => error instanceof assert.AssertionError && error.message.includes("layers=[]"));
}
function layerTokens(size, layer) {
    const entry = size.layers?.find(entry => entry.layer === layer);
    assert.ok(entry !== undefined, layer + " missing; layers=" + JSON.stringify(size.layers?.map(entry => entry.layer) ?? size.kind));
    return entry.tokens;
}

async function inside() {
    const Protocol = require(path.join(tree, "bin/lib/qml-library.js")).load(path.join(tree, "shell/plugins/vgs.jarvis/JarvisProtocol.js"));
    process.chdir(process.env.JARVIS_TEST_ROOT);
    hello.directories = {
        state: path.join(process.env.JARVIS_TEST_ROOT, "state/vgshell/jarvis"),
        data: path.join(process.env.JARVIS_TEST_ROOT, "data/vgshell/jarvis"),
        runtime: process.env.XDG_RUNTIME_DIR
    };
    let controls = 0;
    let cases = 0;
    await homeReplyOrder();
    cases++;
    async function run(file, chunks, code, reason = null, expected = [], observations = null) {
        const child = cp.spawn("node", [file, "--tree", tree], { env: {
            PATH: process.env.PATH, HOME: process.env.HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
            XDG_DATA_HOME: process.env.XDG_DATA_HOME
        }, stdio: ["pipe", "pipe", "pipe"] });
        let out = "", err = "";
        child.stdout.on("data", data => { out += data; });
        child.stderr.on("data", data => { err += data; });
        child.stdin.on("error", error => { if (error.code !== "EPIPE") throw error; });
        const closed = once(child, "close");
        // A real bound detects a daemon that retained a lease after EOF.
        const timeout = setTimeout(() => child.kill("SIGKILL"), 3000);
        try {
            for (const chunk of chunks) child.stdin.write(chunk);
            child.stdin.end();
            const [actual, signal] = await closed;
            assert.equal(signal, null, "stdin EOF must end the daemon");
            assert.equal(actual, code, err);
            if (reason instanceof RegExp) assert.match(err.trim(), reason);
            else if (reason !== null) assert.equal(err.trim(), reason);
            else assert.equal(err, "");
            const frames = out.trim() === "" ? [] : out.trim().split("\n").map(line => JSON.parse(line));
            const shell = frames.filter(frame => frame.type === "shell-status");
            assert.deepEqual(shell, expected.length || (typeof reason === "string" && /^jarvis: (voice-mute=|hidden=|state=retired-mute-)/.test(reason)) ? [{ v: 1, type: "shell-status", gen: hello.gen,
                revision: hello.revision, availability: { kind: "checking" } }] : []);
            const keepMemory = expected.some(frame => frame.type === "memory");
            const keepMemoryInbox = expected.some(frame => frame.type === "memory-inbox");
            const keepHomes = expected.some(frame => frame.type === "homes");
            // The Voice offers, the instructions row, the home's drift and the
            // start text's size each judgement sends.
            const shownTypes = ["voices", "instructions", "home-drift", "start-text"];
            const keepShown = expected.some(frame => shownTypes.includes(frame.type));
            const publicFrames = frames.filter(frame => ["task-list", "audit-failures"].includes(frame.type));
            for (const frame of frames.filter(frame => frame.type === "owner-asks")) {
                Protocol.accept(JSON.stringify(frame), "daemon");
                assert.notEqual(frame.snapshot.kind, "ready", "this legacy Home has no asks source; startup must never fabricate an empty inbox");
            }
            // Validate independent readings without pinning their device availability.
            for (const frame of frames.filter(frame => ["main-reach", "echo-cancel"].includes(frame.type)))
                Protocol.accept(JSON.stringify(frame), "daemon");
            if (observations !== null) assert.deepEqual(publicFrames, observations, "startup publishes both bounded lists");
            for (const frame of publicFrames) {
                assert.deepEqual(Object.keys(frame).sort(), ["gen", "revision", "rows", "type", "v"]);
                assert.equal(frame.revision, hello.revision);
                assert.ok(Array.isArray(frame.rows));
                assert.ok(frame.rows.length <= (frame.type === "task-list" ? 16 : 20));
                for (const row of frame.rows) assert.deepEqual(Object.keys(row).sort(), frame.type === "task-list"
                    ? ["agent", "createdAt", "endedAt", "failure", "goal", "id", "state"]
                    : ["cause", "decision", "effect", "outcome", "refusal", "time", "tool"]);
            }
            assert.deepEqual(frames.filter(frame => frame.type !== "shell-status"
                && frame.type !== "task-list" && frame.type !== "audit-failures" && frame.type !== "owner-asks" && frame.type !== "main-reach" && frame.type !== "echo-cancel"
                && (keepMemory || frame.type !== "memory") && (keepMemoryInbox || frame.type !== "memory-inbox")
                && (keepHomes || frame.type !== "homes")
                && (keepShown || !shownTypes.includes(frame.type))), expected);
            cases++;
            return frames;
        } finally { clearTimeout(timeout); if (child.exitCode === null) child.kill("SIGKILL"); }
    }
    // Without local setup or a saved AI model the engine names both steps.
    const reply = (locked, gen) => ({ v: 1, type: "status", gen, revision: hello.revision, daemon: locked ? "locked" : "ready",
        causes: ["speech=local-not-set-up", "brain=unselected"], cautions: [] });
    function states(locks) {
        let seq = 0;
        const lines = [];
        for (const locked of locks) {
            lines.push(reply(locked, seq === 0 ? 0 : 1));
            lines.push({ v: 1, type: "state", gen: 1, revision: hello.revision,
                seq: ++seq, state: {
                    gen: 1, nextOp: 1, stale: 0, stops: 0, settings: hello.settings,
                    gate: { kind: "down", reason: locked ? "locked" : "unconfigured" },
                    voiceMute: { kind: "off" }, capture: { kind: "closed" }, turn: { kind: "none" }, brain: { kind: "closed" },
                    playback: { kind: "idle" }, action: { kind: "none" }, approval: { kind: "none" }, fault: { kind: "none" },
                    conversation: { kind: "ended" }, history: { kind: "current", epoch: 1 },
                    input: { kind: "released" }, quiet: { kind: "none" }, sound: { kind: "none" }, cue: { kind: "none" },
                    indicator: { kind: "gone" }, barIndicator: { kind: "gone" }, visibility: { kind: "shown" },
                    duplex: { kind: "half" }, toggleAt: null,
                    engine: { kind: "chained" }, speech: { kind: "closed" }, check: { kind: "unavailable" }, checkSource: null,
                    restart: { kind: "none" }
                }, phase: "down", brain: "" });
        }
        return lines;
    }
    const startup = file => run(file, [JSON.stringify({ ...hello, directories: { ...hello.directories,
        state: fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "startup-lists-")) } }) + "\n"],
        0, null, states([false]), [
            { v: 1, type: "audit-failures", gen: 0, revision: hello.revision, rows: [] },
            { v: 1, type: "task-list", gen: 1, revision: hello.revision, rows: [] }
        ]);
    await startup(daemon);
    const auditRows = () => {
        const directory = path.join(hello.directories.state, "audit");
        return fs.existsSync(directory) ? fs.readdirSync(directory).filter(name => name.endsWith(".jsonl"))
            .flatMap(name => fs.readFileSync(path.join(directory, name), "utf8").trim().split("\n").map(JSON.parse)) : [];
    };
    const confirmation = { v: 1, type: "intent", gen: 1, revision: hello.revision, intent: "confirm",
        id: "11111111-1111-4111-8111-111111111111", digest: "a".repeat(64), source: "key" };
    function refusalFrames() {
        const frames = states([false]);
        const refused = structuredClone(frames.find(frame => frame.type === "state"));
        refused.seq = 2;
        refused.state.nextOp = 2;
        return [...frames, refused];
    }
    const noHold = async file => {
        const before = auditRows().filter(row => row.kind === "action").length;
        const frames = await run(file, [JSON.stringify(hello) + "\n", JSON.stringify(confirmation) + "\n"], 0, null, refusalFrames());
        const actions = auditRows().filter(row => row.kind === "action");
        assert.equal(actions.length, before + 1, "a real daemon audits a confirmation with no live hold");
        assert.equal(actions.at(-1).decision, "refuse");
        assert.equal(actions.at(-1).outcome, "cancelled");
        const published = frames.filter(frame => frame.type === "audit-failures");
        assert.equal(published.length, 2, "the new refused confirmation publishes after the startup audit list");
        const action = actions.at(-1);
        assert.deepEqual(published.at(-1).rows.at(-1), { time: action.time, tool: action.tool, effect: action.effect,
            decision: "refuse", outcome: "cancelled", refusal: null, cause: null });
    };
    await noHold(daemon);
    const brokenState = path.join(process.env.JARVIS_TEST_ROOT, "broken-audit-state");
    fs.mkdirSync(brokenState);
    fs.writeFileSync(path.join(brokenState, "audit"), "blocked");
    const auditFailure = file => run(file, [JSON.stringify({ ...hello,
        directories: { ...hello.directories, state: brokenState } }) + "\n", JSON.stringify(confirmation) + "\n"],
        74, "jarvis: audit=read cause=directory-type");
    await auditFailure(daemon);
    await run(daemon, [JSON.stringify(hello).slice(0, 20), JSON.stringify(hello).slice(20) + "\n",
        JSON.stringify({ ...hello, locked: true }) + "\n"], 0, null, states([false, true]));
    await run(daemon, [], 0);
    await run(daemon, ["{}\n"], 65, "jarvis: protocol=version");
    await run(daemon, [JSON.stringify(hello)], 65, "jarvis: protocol=unterminated-line");
    await run(daemon, ["a".repeat(262145)], 65, "jarvis: protocol=line-too-long");
    await run(daemon, [JSON.stringify({ ...hello, type: "unknown" }) + "\n"], 65, "jarvis: protocol=type");
    const intent = name => ({ v: 1, type: "intent", gen: 0, revision: hello.revision, intent: name });
    const indicator = (shown, bar = "gone", gen = 0) => ({ v: 1, type: "indicator", gen, revision: hello.revision, shown, bar });
    await run(daemon, [JSON.stringify(indicator(true)) + "\n"], 65, "jarvis: protocol=indicator-identity");
    await run(daemon, [JSON.stringify(hello) + "\n",
        JSON.stringify({ ...indicator(true), revision: "b".repeat(64) }) + "\n"],
        65, "jarvis: protocol=indicator-identity", states([false]));
    await run(daemon, [JSON.stringify(intent("talk-down")) + "\n"], 65, "jarvis: protocol=identity");
    await run(daemon, [JSON.stringify(hello) + "\n",
        JSON.stringify({ ...intent("stop"), revision: "b".repeat(64) }) + "\n"],
        65, "jarvis: protocol=identity", states([false]));
    for (const name of ["hide", "show"])
        await run(daemon, [JSON.stringify(hello) + "\n",
            JSON.stringify({ ...intent(name), revision: "b".repeat(64) }) + "\n"],
            65, "jarvis: protocol=identity", states([false]));
    for (const changed of [{ revision: "b".repeat(64) },
        { directories: { ...hello.directories, state: path.join(process.env.JARVIS_TEST_ROOT, "other") } }])
        await run(daemon, [JSON.stringify(hello) + "\n", JSON.stringify({ ...hello, ...changed }) + "\n"],
            65, "jarvis: protocol=identity", states([false]));
    // The request wire's reply side: a reply answers only a request this
    // daemon sent, and only after hello.
    const answer = { v: 1, type: "reply", gen: 0, revision: hello.revision, id: 1, kind: "run.detached", answer: "ok", data: null };
    await run(daemon, [JSON.stringify(answer) + "\n"], 65, "jarvis: protocol=identity");
    const unknownReply = file => run(file, [JSON.stringify(hello) + "\n", JSON.stringify(answer) + "\n"],
        65, "jarvis: protocol=reply-unknown", states([false]));
    await unknownReply(daemon);
    // The Hyprland probe after hello reaches hyprctl with this session's
    // signature and runtime directory and nothing else of the daemon's.
    const desk = desktopFixture.desktopWorld(process.env.XDG_RUNTIME_DIR, []);
    async function probe(file) {
        desk.reset();
        const child = cp.spawn("node", [file, "--tree", tree], { env: {
            PATH: process.env.PATH, HOME: process.env.HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
            HYPRLAND_INSTANCE_SIGNATURE: "fixture-signature"
        }, stdio: ["pipe", "ignore", "pipe"] });
        let err = "";
        child.stderr.on("data", data => { err += data; });
        const closed = once(child, "close");
        const timeout = setTimeout(() => child.kill("SIGKILL"), 5000);
        try {
            child.stdin.write(JSON.stringify(hello) + "\n");
            for (let wait = 0; desk.hyprctlCalls().length === 0; wait++) {
                assert.ok(wait < 300, "the daemon probes Hyprland after hello");
                await new Promise(resolve => setTimeout(resolve, 10)); // Polls the stand-in's log.
            }
            child.stdin.end();
            assert.deepEqual(await closed, [0, null], err);
            assert.deepEqual(desk.hyprctlCalls().map(call => [call.argv, call.env]), [[["--batch", "j/clients;j/activewindow;j/monitors"],
                ["HYPRLAND_INSTANCE_SIGNATURE", "LANG", "PATH", "XDG_RUNTIME_DIR"]]]);
            cases++;
        } finally { clearTimeout(timeout); if (child.exitCode === null) child.kill("SIGKILL"); }
    }
    await probe(daemon);

    const root = path.join(process.env.JARVIS_TEST_ROOT, "daemon-copies");
    fs.mkdirSync(root);
    const protocol = fs.readFileSync(path.join(tree, "shell/plugins/vgs.jarvis/JarvisProtocol.js"));
    const floorDir = path.join(root, "floor");
    fs.mkdirSync(path.join(floorDir, "backend"), { recursive: true });
    fs.writeFileSync(path.join(floorDir, "JarvisProtocol.js"), protocol);
    for (const name of ["Tasks.js", "task-event", "TaskRelay.js", "claude-hook"])
        fs.copyFileSync(path.join(path.dirname(daemon), name), path.join(floorDir, "backend", name));
    const floorFile = path.join(floorDir, "backend/jarvisd.js");
    const floorNeedle = 'if (Number(process.versions.node.split(".")[0]) < 22)';
    assert.equal(source.split(floorNeedle).length - 1, 1);
    fs.writeFileSync(floorFile, source.replace(floorNeedle,
        'Object.defineProperty(process.versions, "node", { value: "21.0.0" });\n' + floorNeedle));
    await run(floorFile, [], 78, "jarvis: node=21.0.0 need=22");
    async function control(name, needle, replacement, check, failure = assert.AssertionError) {
        assert.equal(source.split(needle).length - 1, 1, name + " mutation match");
        const copy = daemonCopy(name);
        fs.writeFileSync(copy, source.replace(needle, replacement));
        await assert.rejects(() => check(copy), failure, name + " must turn red");
        controls++;
    }
    await control("audit-startup-list", "auditFailures(audit.failures());", "void audit;", startup);
    await control("task-startup-list", 'write({ v: 1, type: "task-list", gen: runner.state.gen,',
        'void ({ v: 1, type: "task-list", gen: runner.state.gen,', startup);
    // The home folder each hello names, on one daemon: it writes nothing in
    // a folder (D126); a folder it refuses, one Setup has not set up among
    // them, leads the status causes with its own keyed cause, and a text
    // over its budget is one of the status cautions, never a cause. No hello
    // follows an edit inside the folder, so a request made while the folder
    // holds the engine judges it again; any other request sends no status.
    async function homeStatus(file) {
        const base = fs.realpathSync(process.env.HOME);
        const missing = path.join(base, "home-missing"), chosen = path.join(base, "home-chosen");
        const linked = path.join(base, "home-linked");
        for (const folder of [missing, chosen, linked]) fs.rmSync(folder, { recursive: true, force: true });
        // Every run of this case, its controls' among them, starts with the
        // daily drift reading due: no reading time is recorded (Drift.js).
        fs.rmSync(path.join(hello.directories.state, "home-drift.json"), { force: true });
        fs.mkdirSync(chosen);
        jarvisHome(linked, tree);
        fs.rmSync(path.join(linked, "state"), { recursive: true });
        fs.symlinkSync(base, path.join(linked, "state"));
        const child = cp.spawn("node", [file, "--tree", tree], { env: {
            PATH: process.env.PATH, HOME: process.env.HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
            XDG_DATA_HOME: process.env.XDG_DATA_HOME
        }, stdio: ["pipe", "pipe", "pipe"] });
        let out = "", err = "";
        child.stdout.on("data", data => { out += data; });
        child.stderr.on("data", data => { err += data; });
        const closed = once(child, "close");
        const frames = () => out.split("\n").slice(0, -1).map(line => JSON.parse(line));
        const statuses = () => frames().filter(frame => frame.type === "status").map(frame => frame.causes);
        const cautions = () => frames().filter(frame => frame.type === "status").map(frame => frame.cautions);
        // The instructions row each judgement of the folder sends: the home's
        // whole AGENTS.md.
        const shown = () => frames().filter(frame => frame.type === "instructions").map(frame => frame.instructions);
        const instructions = () => shown().at(-1);
        // The start text's size each judgement sends: the home layers it
        // names, or unreadable.
        const sizes = () => frames().filter(frame => frame.type === "start-text").map(frame => frame.size);
        const sizeLayers = () => {
            const size = sizes().at(-1);
            assert.ok(size !== undefined, "a judgement sends the start text's size");
            return size.kind === "read" ? size.layers.map(entry => entry.layer) : size.kind;
        };
        // The Voice offers, sent when they change: with no local setup the
        // local provider offers none, however many hellos follow.
        const offered = () => frames().filter(frame => frame.type === "voices").map(frame => frame.voices);
        const send = message => child.stdin.write(JSON.stringify(message) + "\n");
        const named = setting => ({ ...hello, settings: { ...hello.settings, home: setting } });
        const others = reply(false, 0).causes;
        const seen = [];
        let locked = false;
        // A request can publish extra statuses before the following hello.
        // Revision is fixed for a daemon; alternate the mutable lock flag so
        // only this hello can send its status, preceded by its start-text.
        const step = async (lines, want) => {
            const at = frames().length;
            for (const line of lines) {
                if (line.type === "hello") { locked = !locked; send({ ...line, locked }); }
                else send(line);
            }
            seen.push(...want);
            await homeReply(() => frames().slice(at), locked ? "locked" : "ready", async wait => {
                assert.ok(wait < 500 && child.exitCode === null, "the daemon answers the hello: " + err);
                await new Promise(resolve => setTimeout(resolve, 10)); // Polls the daemon's output.
            });
            assert.deepEqual(statuses(), seen);
        };
        // The satellite reading's cause names Setup for a chosen folder
        // Setup has yet to set up, and no-home only while no folder is chosen.
        const reachCause = async want => {
            for (let wait = 0; frames().filter(frame => frame.type === "main-reach").at(-1)?.reach.cause !== want; wait++) {
                assert.ok(wait < 300 && child.exitCode === null, "main-reach names " + want + ": " + JSON.stringify(frames().filter(frame => frame.type === "main-reach").at(-1)));
                await new Promise(resolve => setTimeout(resolve, 10)); // Polls the daemon's output.
            }
        };
        try {
            await step([hello], [others]);
            await reachCause("no-home");
            assert.deepEqual(instructions(), { kind: "none" }, "no home, no instructions");
            assert.deepEqual(sizeLayers(), [], "no home, no home layer in the start text");
            assert.ok(sizes().at(-1).tokens > 0, "the shipped guidance alone has a size");
            assert.deepEqual(offered(), [[]], "a provider whose voices cannot be read offers none");
            await step([named("~/home-missing")], [["home=missing", ...others]]);
            await reachCause("not-set-up");
            assert.equal(fs.existsSync(missing), false, "a judgement makes no folder");
            assert.deepEqual(instructions(), { kind: "unreadable" }, "a refused folder shows no instructions");
            await step([named("~/home-chosen")], [["home=not-set-up", ...others]]);
            await reachCause("not-set-up");
            assert.deepEqual(fs.readdirSync(chosen), [], "and writes nothing in a folder Setup has not set up");
            // A request while that folder holds the engine judges it again,
            // and a home Setup has set up meanwhile takes it. The daemon
            // reads the home it takes, so the folder stays in place.
            jarvisHome(chosen, tree);
            await step([{ ...intent("say"), text: "fixture request" }, named("~/home-chosen")], [others, others]);
            assert.deepEqual(instructions(), { kind: "text", lines: [fs.readFileSync(path.join(chosen, "AGENTS.md"), "utf8").trim()], more: false },
                "the instructions are the home's whole AGENTS.md");
            const bare = sizes().at(-1);
            fs.writeFileSync(path.join(chosen, "AGENTS.md"), "## Notes\nCalm.\n" + "x".repeat(8193) + "\n");
            await step([named("~/home-chosen")], [others]);
            assert.deepEqual(cautions().at(-1), ["guidance=agents-over-budget"], "an AGENTS.md over its budget is a caution of a ready folder");
            // The Setup page shows the file's lines up to the protocol's
            // bound (JarvisProtocol.js INSTRUCTIONS_LINES and _CHARS).
            const Protocol = require(path.join(tree, "bin/lib/qml-library.js")).load(path.join(tree, "shell/plugins/vgs.jarvis/JarvisProtocol.js"));
            assert.deepEqual(instructions(), { kind: "text", more: true,
                lines: ["## Notes", "Calm."].concat(Array(Protocol.INSTRUCTIONS_LINES - 2).fill("x".repeat(Protocol.INSTRUCTIONS_CHARS))) },
                "and shows every line from its first, each heading a line, up to the bound");
            // The layer is 8,283 bytes with its heading: about 2,110 tokens at
            // the recorded ratio. The upper bounds fail a size sent in bytes.
            const agentsTokens = layerTokens(sizes().at(-1), "home/AGENTS.md");
            assert.ok(agentsTokens > 2000 && agentsTokens < 2300, "an AGENTS.md over its budget is counted whole, in tokens: " + agentsTokens);
            const grown = sizes().at(-1).tokens - bare.tokens;
            assert.ok(grown > 2000 && grown < 2300, "and the whole start text grows with it, in tokens: " + grown);
            fs.writeFileSync(path.join(chosen, "AGENTS.md"), "# Short again\n\nCalm\u2028and brief.\n");
            await step([intent("talk-down"), named("~/home-chosen")], [others]);
            assert.deepEqual(cautions().at(-1), [], "a text back within its budget is no caution");
            await step([named("~/home-linked")], [["home=link", ...others]]);
            assert.deepEqual(shown().slice(-2), [{ kind: "text", lines: ["# Short again", "Calm and brief."], more: false }, { kind: "unreadable" }],
                "each judgement reads the file again, a pasted line separator as a space, and a refused folder shows none");
            assert.equal(sizeLayers(), "unreadable", "a refused folder has no size");
            assert.equal(fs.lstatSync(path.join(linked, "state")).isSymbolicLink(), true, "a refused folder keeps its link");
            await step([{ ...intent("say"), text: "fixture request" }, named("/etc/vgs-jarvis-home")], [["home=link", ...others], ["home=path", ...others]]);
            child.stdin.end();
            assert.deepEqual(await closed, [0, null], err);
        } finally { if (child.exitCode === null) child.kill("SIGKILL"); }
        assert.deepEqual(statuses(), seen, "one status a hello, and one for each request made over a folder that held the engine");
        assert.deepEqual(offered(), [[]], "unchanged offers are not sent again");
        assert.equal(err, "jarvis: home=missing\njarvis: home=not-set-up\njarvis: home=link\njarvis: home=link\njarvis: home=path\n");
        assert.equal(fs.existsSync("/etc/vgs-jarvis-home"), false);
        // A ready home's package drift is read once, and with no kendex on
        // the world's PATH it reads as missing, never current (Drift.js); a
        // refused folder, the chosen one before Setup set it up among them,
        // is never read.
        assert.deepEqual(frames().filter(frame => frame.type === "home-drift" && frame.home !== "").map(frame => [frame.home, frame.drift.kind]),
            [["~/home-chosen", "none"], ["~/home-chosen", "kendex-missing"]], "only the ready home's drift is read, once, and kendex's absence is shown");
        cases++;
    }
    const fleet = require("./fixtures/jarvis/fleet.js");
    await fleet.verify(daemon, tree);
    {
        // The home routes keep their order, never convert a project and read
        // success back: a copy without each guard turns its own case red.
        for (const [name, only, needle, replacement] of [
            ["fleet-outside-projects", "setup-refusals", "    outsideProjects(folder);\n    fs.mkdirSync(folder, { recursive: true });", "    fs.mkdirSync(folder, { recursive: true });"],
            ["fleet-read-back", "setup-step-fails", "    await initialize(folder, env, signal);\n    readBack(folder);\n    return 0;\n}\n\n// Whether the history",
                "    await initialize(folder, env, signal);\n    return 0;\n}\n\n// Whether the history"],
            ["fleet-repo-effects", "setup", '"--yes", "--allow-repo-effects", "--leave"', '"--yes", "--leave"'],
            ["fleet-main-host-set", "setup-main-host", '    if (main !== "") fail("main-host-set main=" + JSON.stringify(main));\n', ""],
            ["fleet-linked-home", "setup-linked", "    const own = real(folder);\n", "    const own = path.resolve(folder);\n"],
            ["fleet-clone-history", "clone-history", '            if (credentialsInHistory(folder)) fail("credentials-committed");\n', ""],
            ["fleet-clone-history-all", "clone-history", '"log", "--all", "--full-history", "-1"', '"log", "--full-history", "-1"'],
            ["fleet-clone-history-full", "clone-history", '"log", "--all", "--full-history", "-1"', '"log", "--all", "-1"'],
            ["fleet-clone-removed", "clone-history", "            removeClone(folder, found === null);\n            throw error;\n", "            throw error;\n"],
            ["fleet-clone-retry", "clone-retry", "            removeClone(folder, found === null);\n            throw error;\n", "            throw error;\n"],
            ["fleet-clone-hangup", "clone-hangup", 'const CANCEL_SIGNALS = ["SIGTERM", "SIGINT", "SIGHUP"];', 'const CANCEL_SIGNALS = ["SIGTERM", "SIGINT"];'],
            ["fleet-clone-agent", "clone", 'environment(source, verb === "clone-worker" ? ["SSH_AUTH_SOCK"] : [])', "environment(source)"],
            ["fleet-clone-resume", "clone-resume", "        if (workTree(folder) !== real(folder) || !installedIn(folder)", "        if (true || workTree(folder) !== real(folder) || !installedIn(folder)"],
            ["fleet-clone-resume-history", "clone-resume", " || credentialsInHistory(folder))\n", ")\n"],
            ["fleet-clone-resume-tracked", "clone-resume", " || credentialsTracked(folder)", ""],
            ["fleet-main-host-read-back", "clone-read-back", '    if (report.JARVIS_MAIN_HOST !== main) fail("main-host-unset cause=read-back");\n', ""],
            ["fleet-main-host-read", "clone-read-back", '    if (stored.code !== 0) fail("main-host-read cause=exit=" + stored.code);\n', ""]]) {
            const copy = daemonCopy(name);
            const module = path.join(path.dirname(copy), "fleet-setup.js");
            const original = fs.readFileSync(module, "utf8");
            assert.equal(original.split(needle).length - 1, 1, name + " mutation match");
            fs.writeFileSync(module, original.replace(needle, replacement));
            await assert.rejects(() => fleet.verify(copy, tree, only), assert.AssertionError, name + " must turn red");
            controls++;
            console.log("control=" + name + " detected");
        }
    }
    await homeStatus(daemon);
    await control("home-writes-nothing", "            Home.judge(folder);\n", "            require(\"node:fs\").mkdirSync(folder, { recursive: true }); Home.judge(folder);\n", homeStatus);
    await control("voices-write", 'write({ v: 1, type: "voices", gen: runner.state.gen, revision: context.revision, voices });', "void voices;", homeStatus);
    await control("voices-change-only", "if (signature === publishedVoices) return;", "", homeStatus);
    await control("instructions-whole", 'try { instructions = Protocol.instructionsText(Home.read(homeFolder.state.path, "AGENTS.md", null).text); }',
        'try { instructions = Protocol.instructionsText(Home.read(homeFolder.state.path, "AGENTS.md", null).text.split("\\n")[0]); }', homeStatus);
    await control("reach-not-set-up", "? homeFolder.state.path : null, homeBlock,\n", "? homeFolder.state.path : null,\n", homeStatus);
    await control("drift-selected", "        if (drift !== null) drift.select(homeFolder.state.kind === \"ready\" ? homeFolder.state.path : null);\n", "", homeStatus);
    await control("start-text-each-judgement", "        publishStartText();\n        configured(", "        configured(", homeStatus);
    await control("start-text-total-tokens", "tokens: Guidance.tokens(read.start),", "tokens: read.start,", homeStatus);
    await control("start-text-layer-tokens", "tokens: Guidance.tokens(layer.bytes) }", "tokens: layer.bytes }", homeStatus);
    await control("home-refusal", 'return { path: folder, state: { kind: "refused", cause } };', 'return { path: folder, state: { kind: "none" } };', homeStatus);
    await control("home-engine", "directories: context.directories, home: () => homeFolder.state, rejudge: judgeSetup });", "directories: context.directories, rejudge: judgeSetup });", homeStatus);
    await control("home-each-hello", "                judgeSetup();\n", "                if (first) judgeSetup(); else configured(engine.configure(context.settings));\n", homeStatus);
    await control("home-rejudged", " && (engine.homeHeld() || engine.voicesHeld() || engine.modelsHeld())) judgeSetup();", " && (engine.homeHeld() || engine.voicesHeld() || engine.modelsHeld())) void judgeSetup;", homeStatus);
    await control("home-rejudged-held", ' && (engine.homeHeld() || engine.voicesHeld() || engine.modelsHeld())) judgeSetup();', ') judgeSetup();', homeStatus,
        error => error instanceof assert.AssertionError && error.operator === "deepStrictEqual"
            && error.actual?.length === error.expected?.length + 1);
    console.log("test-jarvis-daemon: control=home-rejudged-held killed reason=extra-status");
    // Homes offered to Settings are daemon state records, never files below
    // a Jarvis home: startup publishes the saved list, an accepted home joins
    // homes.json and the homes message. A refused folder clears current
    // without changing the remembered list.
    async function homesRecord(file) {
        const base = fs.realpathSync(process.env.HOME);
        const prior = path.join(base, "homes/prior/Jarvis");
        const accepted = path.join(base, "homes/accepted/Jarvis");
        const refused = path.join(base, "homes/refused/Jarvis");
        for (const folder of [prior, accepted, refused]) fs.rmSync(folder, { recursive: true, force: true });
        jarvisHome(accepted, tree);
        jarvisHome(refused, tree);
        fs.rmSync(path.join(refused, "state"), { recursive: true });
        fs.symlinkSync(base, path.join(refused, "state"));
        fs.mkdirSync(hello.directories.state, { recursive: true });
        const record = path.join(hello.directories.state, "homes.json");
        fs.writeFileSync(record, JSON.stringify({ homes: [prior] }) + "\n", { mode: 0o600 });
        const child = cp.spawn("node", [file, "--tree", tree], { env: {
            PATH: process.env.PATH, HOME: process.env.HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
            XDG_DATA_HOME: process.env.XDG_DATA_HOME
        }, stdio: ["pipe", "pipe", "pipe"] });
        let out = "", err = "";
        child.stdout.on("data", data => { out += data; });
        child.stderr.on("data", data => { err += data; });
        const closed = once(child, "close");
        const messages = () => out.split("\n").slice(0, -1).map(line => JSON.parse(line));
        const homes = () => messages().filter(frame => frame.type === "homes").map(frame => frame.homes.map(row => row.value));
        const named = setting => ({ ...hello, settings: { ...hello.settings, home: setting } });
        const wait = async predicate => {
            for (let attempts = 0; attempts < 500; attempts++) {
                if (predicate()) return;
                assert.equal(child.exitCode, null, "daemon exited: " + err);
                await new Promise(resolve => setTimeout(resolve, 10));
            }
            assert.fail("homes record timeout: " + out + err);
        };
        try {
            child.stdin.write(JSON.stringify(named("~/homes/accepted/Jarvis")) + "\n");
            await wait(() => homes().some(list => list[0] === "~/homes/accepted/Jarvis"));
            assert.deepEqual(homes().slice(0, 2), [["~/homes/prior/Jarvis"], ["~/homes/accepted/Jarvis", "~/homes/prior/Jarvis"]]);
            assert.deepEqual(JSON.parse(fs.readFileSync(record, "utf8")), { homes: [accepted, prior] });
            for (const folder of [accepted, prior]) {
                const relative = path.relative(folder, record);
                assert.equal(relative.startsWith("..") || path.isAbsolute(relative), true, "homes.json stays outside " + folder);
            }
            const count = homes().length;
            const recordBefore = fs.statSync(record, { bigint: true });
            child.stdin.write(JSON.stringify(named("~/homes/refused/Jarvis")) + "\n");
            await wait(() => messages().some(frame => frame.type === "status" && frame.causes[0] === "home=link"));
            assert.deepEqual(JSON.parse(fs.readFileSync(record, "utf8")), { homes: [accepted, prior] });
            const recordAfter = fs.statSync(record, { bigint: true });
            assert.deepEqual([recordAfter.ino, recordAfter.mtimeNs], [recordBefore.ino, recordBefore.mtimeNs],
                "a refused home does not rewrite the remembered homes");
            assert.equal(homes().length, count + 1, "a refused home publishes the cleared current home");
            assert.equal(messages().filter(frame => frame.type === "homes").at(-1).current, "");
            assert.equal(homes().flat().includes("~/homes/refused/Jarvis"), false);
            child.stdin.end();
            assert.deepEqual(await closed, [0, null], err);
        } finally { if (child.exitCode === null) child.kill("SIGKILL"); }
        assert.equal(err, "jarvis: home=link\n");
        cases++;
    }
    await homesRecord(daemon);
    await control("homes-record-store", "        storeHomes(homes);\n", "", homesRecord);
    await control("homes-record-wire", "        rememberHome();\n        publishHomes();\n", "        rememberHome();\n", homesRecord);
    await control("homes-record-ready-only", 'if (homeFolder.state.kind !== "ready" || homes[0] === homeFolder.state.path) return;',
        'if (false) return;', homesRecord);
    await control("homes-record-state-dir", "        const directory = context.directories.state;\n",
        "        const directory = homeFolder.state.path;\n", homesRecord);
    // Homes are a Settings offer cache. A long offerable home must not crash
    // the wire, malformed cache records fall back to an empty list, bad
    // entries are dropped, and a write failure leaves the daemon running with
    // its in-memory offers.
    async function homesCacheRecovery(file) {
        const base = fs.realpathSync(process.env.HOME);
        const valid = path.join(base, "homes/valid/Jarvis");
        const outside = path.join(path.dirname(base), "outside-home/Jarvis");
        const long = path.join(base, "homes", "long-" + "a".repeat(60), "Jarvis");
        const longValue = "~/" + path.relative(base, long).split(path.sep).join("/");
        const longLabel = "…" + longValue.slice(-59);
        assert.equal(longValue.length > 60 && longValue.length <= 200, true, "long home fixture fits the value wire");
        fs.rmSync(path.join(base, "homes"), { recursive: true, force: true });
        fs.rmSync(path.dirname(outside), { recursive: true, force: true });
        jarvisHome(long, tree);
        const named = (setting, state) => ({ ...hello, settings: { ...hello.settings, home: setting },
            directories: { ...hello.directories, state } });
        const start = state => {
            const child = cp.spawn("node", [file, "--tree", tree], { env: {
                PATH: process.env.PATH, HOME: process.env.HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
                XDG_DATA_HOME: process.env.XDG_DATA_HOME
            }, stdio: ["pipe", "pipe", "pipe"] });
            let out = "", err = "";
            child.stdout.on("data", data => { out += data; });
            child.stderr.on("data", data => { err += data; });
            const messages = () => out.split("\n").slice(0, -1).filter(Boolean).map(line => JSON.parse(line));
            const wait = async predicate => {
                for (let attempts = 0; attempts < 500; attempts++) {
                    if (predicate(messages())) return;
                    assert.equal(child.exitCode, null, "daemon exited: " + err);
                    await new Promise(resolve => setTimeout(resolve, 10));
                }
                assert.fail("homes cache timeout: " + out + err);
            };
            const close = async wantErr => {
                child.stdin.end();
                assert.deepEqual(await once(child, "close"), [0, null], err);
                assert.equal(err, wantErr);
            };
            return { child, messages, wait, close };
        };

        const longState = path.join(hello.directories.state, "homes-long");
        fs.mkdirSync(longState, { recursive: true });
        const longRun = start(longState);
        try {
            longRun.child.stdin.write(JSON.stringify(named(longValue, longState)) + "\n");
            await longRun.wait(messages => messages.some(frame => frame.type === "homes"
                && frame.homes.some(row => row.label === longLabel && row.value === longValue)));
            assert.deepEqual(JSON.parse(fs.readFileSync(path.join(longState, "homes.json"), "utf8")), { homes: [long] });
            assert.equal(longRun.child.exitCode, null, "the long home keeps the daemon running");
            await longRun.close("");
        } finally { if (longRun.child.exitCode === null) longRun.child.kill("SIGKILL"); }

        const outsideState = path.join(hello.directories.state, "homes-outside");
        fs.mkdirSync(outsideState, { recursive: true });
        fs.writeFileSync(path.join(outsideState, "homes.json"), JSON.stringify({ homes: [outside, valid] }) + "\n", { mode: 0o600 });
        const outsideRun = start(outsideState);
        try {
            outsideRun.child.stdin.write(JSON.stringify(named("", outsideState)) + "\n");
            await outsideRun.wait(messages => messages.some(frame => frame.type === "homes"
                && JSON.stringify(frame.homes.map(row => row.value)) === JSON.stringify(["~/homes/valid/Jarvis"])));
            await outsideRun.close("");
        } finally { if (outsideRun.child.exitCode === null) outsideRun.child.kill("SIGKILL"); }

        const corruptState = path.join(hello.directories.state, "homes-corrupt");
        fs.mkdirSync(corruptState, { recursive: true });
        fs.writeFileSync(path.join(corruptState, "homes.json"), "", { mode: 0o600 });
        const corruptRun = start(corruptState);
        try {
            corruptRun.child.stdin.write(JSON.stringify(named("", corruptState)) + "\n");
            await corruptRun.wait(messages => messages.some(frame => frame.type === "homes" && frame.homes.length === 0));
            await corruptRun.close("jarvis: homes=record-json\n");
        } finally { if (corruptRun.child.exitCode === null) corruptRun.child.kill("SIGKILL"); }

        const writeState = path.join(hello.directories.state, "homes-write");
        fs.mkdirSync(writeState, { recursive: true, mode: 0o700 });
        const writeRun = start(writeState);
        try {
            writeRun.child.stdin.write(JSON.stringify(named("", writeState)) + "\n");
            await writeRun.wait(messages => messages.some(frame => frame.type === "homes"));
            fs.writeFileSync(path.join(writeState, ".homes.json-" + writeRun.child.pid), "held\n");
            writeRun.child.stdin.write(JSON.stringify(named(longValue, writeState)) + "\n");
            await writeRun.wait(messages => messages.some(frame => frame.type === "homes"
                && frame.homes.some(row => row.value === longValue)));
            assert.equal(writeRun.child.exitCode, null, "a homes write failure keeps the daemon running");
            await writeRun.close("jarvis: homes=write-failed\n");
        } finally {
            if (writeRun.child.exitCode === null) writeRun.child.kill("SIGKILL");
        }
        cases++;
    }
    await homesCacheRecovery(daemon);
    await control("homes-cache-read-catches", "                process.stderr.write(error.message + \"\\n\");\n                return [];\n",
        "                throw error;\n", homesCacheRecovery);
    await control("homes-cache-write-keeps-running", "            if (reason !== null) process.stderr.write(error.message + \"\\n\");\n            else throw error;\n",
        "            throw error;\n", homesCacheRecovery);
    await control("reply-wire", "requests.reply(message);", "void message;", unknownReply);
    await control("hyprctl-environment", 'const environment = { PATH: process.env.PATH || "/usr/bin:/bin", LANG: "C.UTF-8" };',
        'const environment = { ...process.env, LANG: "C.UTF-8" };', probe);
    await control("lease", 'if (tail !== "") refuse(65, "jarvis: protocol=unterminated-line");',
        'if (tail !== "") refuse(65, "jarvis: protocol=unterminated-line");\n        setInterval(() => {}, 1000);',
        file => run(file, [], 0));
    await control("confirmation-audit", "Object.assign(runner.ports, router.ports);",
        "Object.assign(runner.ports, router.ports, { approval: { ...router.ports.approval, refused() {} } });", noHold);
    await control("audit-update-list", "changed: auditFailures", "changed: () => {}", noHold);
    await control("confirmation-audit-cause", 'error.message.startsWith("jarvis: audit=")', "false", auditFailure);
    await control("hello", 'if (!process.stdout.write(wire + "\\n")) process.stdin.pause();',
        'if (false && !process.stdout.write(wire + "\\n")) process.stdin.pause();',
        file => run(file, [JSON.stringify(hello) + "\n"], 0, null, states([false])));
    await control("session-forward", 'runner.dispatch({ type: "snapshot", locked: context.locked,',
        'runner.dispatch({ type: "snapshot", locked: false,',
        file => run(file, [JSON.stringify({ ...hello, locked: true }) + "\n"], 0, null, states([true])));
    await control("state-publish", 'if (!ending && context !== null) write({ v: 1, type: "state"',
        'if (false && !ending && context !== null) write({ v: 1, type: "state"',
        file => run(file, [JSON.stringify(hello) + "\n"], 0, null, states([false])));
    await control("intent-identity", 'if (context === null || message.revision !== context.revision)\n            throw new Error("jarvis: protocol=identity");',
        'if (false) throw new Error("jarvis: protocol=identity");',
        file => run(file, [JSON.stringify(hello) + "\n",
            JSON.stringify({ ...intent("stop"), revision: "b".repeat(64) }) + "\n"],
            65, "jarvis: protocol=identity", states([false])));
    await control("indicator-identity", 'if (context === null || message.revision !== context.revision)\n                        throw new Error("jarvis: protocol=indicator-identity");',
        'if (false) throw new Error("jarvis: protocol=indicator-identity");',
        file => run(file, [JSON.stringify(hello) + "\n",
            JSON.stringify({ ...indicator(true), revision: "b".repeat(64) }) + "\n"],
            65, "jarvis: protocol=indicator-identity", states([false])));
    await control("snapshot-identity", 'if (context !== null && (message.revision !== context.revision',
        'if (false && context !== null && (message.revision !== context.revision',
        file => run(file, [JSON.stringify(hello) + "\n",
            JSON.stringify({ ...hello, directories: { ...hello.directories,
                state: path.join(process.env.JARVIS_TEST_ROOT, "other") } }) + "\n"],
            65, "jarvis: protocol=identity", states([false])));
    await control("node-floor", floorNeedle, 'Object.defineProperty(process.versions, "node", { value: "21.0.0" });\nif (false)',
        file => run(file, [], 78, "jarvis: node=21.0.0 need=22"));
    const Tasks = require(path.join(path.dirname(daemon), "Tasks.js"));
    const taskStore = new Tasks.Store(hello.directories.state);
    const engine = Tasks.publish(hello.directories.data, path.dirname(daemon));
    const taskGoal = { goal: "Restart fixture", cwd: process.env.HOME, agent: "fixture", account: "" };
    for (let n = 0; n <= 50; n++) taskStore.create("retention-" + n, taskGoal, engine);
    for (let n = 0; n <= 50; n++)
        fs.writeFileSync(path.join(taskStore.root, "retention-" + n, "events/0001.json"),
            JSON.stringify({ v: 1, seq: 1, at: n, kind: "exited", data: { code: 0 } }), { mode: 0o600 });
    await run(daemon, [JSON.stringify(hello) + "\n"], 0, null, states([false]));
    assert.equal(taskStore.list().length, 50);
    assert.equal(fs.existsSync(path.join(taskStore.root, "retention-0")), false);
    taskStore.create("retention-extra", taskGoal, engine);
    fs.writeFileSync(path.join(taskStore.root, "retention-extra/events/0001.json"),
        '{"v":1,"seq":1,"at":0,"kind":"lost","data":{"seq":0}}', { mode: 0o600 });
    const recoveryGuard = "if (first) {\n                    taskEvent = Tasks.publish";
    const skipRecovery = "if (false) {\n                    taskEvent = Tasks.publish";
    await control("startup-retention", recoveryGuard, skipRecovery, async file => {
        await run(file, [JSON.stringify(hello) + "\n"], 0, null, states([false]));
        assert.equal(taskStore.list().length, 50);
    });
    fs.rmSync(path.join(taskStore.root, "retention-extra"), { recursive: true });
    const taskFolder = path.join(hello.directories.state, "tasks", "broken");
    fs.mkdirSync(path.join(taskFolder, "events"), { recursive: true });
    fs.writeFileSync(path.join(taskFolder, "task.json"), "{");
    const badRecord = async file => run(file, [JSON.stringify(hello) + "\n"], 74,
        /jarvis: tasks=parse:.*path=.*broken\/task.json/, []);
    // A parse failure withholds ready and names the record, not the wire.
    await badRecord(daemon);
    await control("task-read", recoveryGuard, skipRecovery,
        badRecord);
    fs.rmSync(taskFolder, { recursive: true });

    function daemonCopy(name) {
        const directory = path.join(root, name);
        fs.cpSync(path.join(tree, "shell/plugins/vgs.jarvis/backend"), path.join(directory, "backend"), { recursive: true });
        for (const relative of ["JarvisProtocol.js", "Session.js", "AccountProviders.js", "manifest.json"])
            fs.copyFileSync(path.join(tree, "shell/plugins/vgs.jarvis", relative), path.join(directory, relative));
        fs.cpSync(path.join(path.dirname(daemon), "skills/computer"), path.join(directory, "backend/skills/computer"), { recursive: true });
        return path.join(directory, "backend/jarvisd.js");
    }
    function holdClock(file, fixed = false) {
        if (file === daemon) return null;
        const clock = path.join(path.dirname(file), "held-clock");
        const before = fs.readFileSync(file, "utf8");
        if (!before.includes("const fixtureHeldClock = ")) {
            const needle = "const runner = new SessionRunner(Session, ports, {\n        now: () => performance.now(),";
            assert.equal(before.split(needle).length - 1, 1, "the disposable daemon exposes its existing Session clock");
            const read = 'Number(fs.readFileSync(fixtureHeldClock, "utf8"))';
            fs.writeFileSync(file, before.replace(needle, "const fixtureHeldClock = " + JSON.stringify(clock) + ";\n    "
                + "const runner = new SessionRunner(Session, ports, {\n        now: () => "
                + (fixed ? read : "Math.max(performance.now(), " + read + ")") + ","));
        } else if (fixed) {
            const read = 'Number(fs.readFileSync(fixtureHeldClock, "utf8"))';
            const elapsed = "Math.max(performance.now(), " + read + ")";
            if (before.includes(elapsed)) {
                assert.equal(before.split(elapsed).length - 1, 1, "one disposable elapsed Session clock");
                fs.writeFileSync(file, before.replace(elapsed, read));
            }
        }
        fs.writeFileSync(clock, "0");
        return clock;
    }
    async function conversation(file, check, holdToTalk = true, expectedCode = 0, expectedError = "", beforeState = null,
        sounds = hello.settings.sounds, settings = {}, fixedClock = false) {
        const clock = holdClock(file, fixedClock);
        const child = cp.spawn("node", [file, "--tree", tree], { env: {
            PATH: process.env.PATH, HOME: process.env.HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
            XDG_DATA_HOME: process.env.XDG_DATA_HOME
        }, stdio: ["pipe", "pipe", "pipe"] });
        const messages = [];
        let tail = "", err = "";
        child.stdout.on("data", data => {
            const lines = (tail + data).split("\n");
            tail = lines.pop();
            messages.push(...lines.map(line => JSON.parse(line)));
        });
        child.stderr.on("data", data => { err += data; });
        child.stdin.on("error", error => { if (error.code !== "EPIPE") throw error; });
        const closed = once(child, "close");
        const timeout = setTimeout(() => child.kill("SIGKILL"), 5000);
        const sent = [];
        const send = message => { sent.push(message); return child.stdin.write(JSON.stringify(message) + "\n"); };
        const last = () => messages.filter(m => m.type === "state").at(-1);
        const wait = async predicate => {
            // The real child crosses an event loop and a pipe. Bound the read
            // rather than treating a missing frame as a successful idle state.
            for (let attempts = 0; attempts < 300; attempts++) {
                const state = last();
                if (state && predicate(state)) return state;
                if (child.exitCode !== null) break;
                await new Promise(resolve => setTimeout(resolve, 5));
            }
            assert.fail("daemon state timeout: " + JSON.stringify(last()) + " stderr=" + err);
        };
        try {
            send({ ...hello, settings: { ...hello.settings, holdToTalk, sounds, ...settings } });
            if (beforeState !== null) await beforeState({ messages });
            await wait(m => m.state.gate.kind !== "down" || m.state.gate.reason === "unconfigured");
            const talk = name => send({ ...intent(name), gen: last().state.gen });
            const holdUp = async (release = releaseHeld) => {
                const held = await wait(message => message.state.input.kind === "held");
                release(clock, held.state, () => talk("talk-up"));
            };
            const closeTalk = async gates => {
                assert.equal(fixedClock, true, "short silent Talk closes use the injected Session clock");
                const silent = path.join(gates, "silent-capture");
                // Held input is published before playback cleanup can acquire
                // capture. Own its empty result before either intent can race.
                fs.writeFileSync(silent, "");
                // A final can release the daemon's input before its frame
                // reaches this reader. A new press and its acknowledgment
                // make the closing release belong to the current hold.
                const before = last().seq;
                talk("talk-down");
                const held = await wait(message => message.seq > before && message.state.input.kind === "held");
                fs.writeFileSync(clock, String(held.state.input.since + TAP_MS - 1));
                talk("talk-up");
                const released = await wait(message => message.state.input.kind !== "held");
                if (released.state.conversation.kind === "ended")
                    fs.rmSync(silent, { force: true });
            };
            await check({ send: talk, holdUp, closeTalk, raw: send, reply: send,
                indicator: (shown, bar = "gone", gen = last().state.gen) => send(indicator(shown, bar, gen)),
                wait, last, messages, sent, pid: child.pid,
                pressClock: at => fs.writeFileSync(clock, String(at)) });
            child.stdin.end();
            const [code, signal] = await closed;
            assert.equal(signal, null, "EOF releases the real child");
            assert.equal(code, expectedCode, err);
            assert.equal(err.trim(), expectedError);
            cases++;
        } finally {
            clearTimeout(timeout);
            if (child.exitCode === null) { child.kill("SIGKILL"); await closed; }
        }
    }
    async function shellRescan(file) {
        const state = path.join(path.dirname(file), "shell-state.json");
        const evidence = path.join(path.dirname(file), "shell-evidence.json");
        const missing = { kind: "unavailable", reason: "bwrap-missing" };
        const put = value => { fs.writeFileSync(state + ".next", JSON.stringify(value)); fs.renameSync(state + ".next", state); };
        put(missing);
        shellState(path.join(path.dirname(file), "Sandbox.js"), file, state, evidence);
        await conversation(file, async w => {
            // Pipe delivery crosses the child loop; poll only our synthetic
            // evidence file, with a bound that fails on a missing publication.
            async function read(want) {
                for (let attempts = 0; attempts < 300; attempts++) {
                    if (fs.existsSync(evidence)) {
                        const value = JSON.parse(fs.readFileSync(evidence, "utf8"));
                        if (value.availability.kind === want) return value;
                    }
                    await new Promise(resolve => setTimeout(resolve, 5));
                }
                assert.fail("shell rescan publication missing: " + want);
            }
            assert.deepEqual((await read("unavailable")).availability, missing);
            put({ kind: "available" });
            w.raw({ v: 1, type: "requirements-scan", gen: w.last().gen, revision: hello.revision, scan: 1 });
            const ready = await read("available");
            assert.equal(ready.pid, w.pid, "rescan retains daemon lease");
            assert.deepEqual(ready.offers.filter(id => id.startsWith("shell.")), ["shell.argv", "shell.line"]);
            put(missing);
            const seq = w.last().seq;
            w.raw({ v: 1, type: "requirements-scan", gen: w.last().gen, revision: hello.revision, scan: 1 });
            w.raw({ v: 1, type: "requirements-scan", gen: w.last().gen, revision: hello.revision, scan: 0 });
            w.raw(hello);
            await w.wait(m => m.seq > seq);
            assert.equal(JSON.parse(fs.readFileSync(evidence, "utf8")).availability.kind, "available",
                "duplicate and old scan counters cannot replace readiness");
            w.raw({ v: 1, type: "requirements-scan", gen: w.last().gen, revision: hello.revision, scan: 2 });
            const lost = await read("unavailable");
            assert.equal(lost.pid, w.pid);
            assert.deepEqual(lost.offers.filter(id => id.startsWith("shell.")), []);
        });
    }
    await shellRescan(daemonCopy("shell-rescan"));
    const shellControl = daemonCopy("shell-rescan-control");
    const shellControlSource = fs.readFileSync(shellControl, "utf8");
    const refresh = "void shell.refresh();";
    assert.equal(shellControlSource.split(refresh).length - 1, 1);
    fs.writeFileSync(shellControl, shellControlSource.replace(refresh, "void shell;"));
    await assert.rejects(() => shellRescan(shellControl), assert.AssertionError);
    controls++;
    console.log("test-jarvis-daemon: control=shell-rescan-delivery detected");
    const scanControl = daemonCopy("shell-rescan-monotonic-control");
    const scanSource = fs.readFileSync(scanControl, "utf8");
    const newer = "message.scan > requirementsScan";
    assert.equal(scanSource.split(newer).length - 1, 1);
    fs.writeFileSync(scanControl, scanSource.replace(newer, "true"));
    await assert.rejects(() => shellRescan(scanControl), assert.AssertionError);
    controls++;
    console.log("test-jarvis-daemon: control=shell-rescan-monotonic detected");

    async function taskWire(file) {
        const gates = path.join(path.dirname(file), "task-wire-gates");
        fs.mkdirSync(gates);
        const fixture = cp.spawnSync("node", [path.join(tree, "scripts/fixtures/jarvis/prepare.js"),
            "--task-requests", file, gates], { env: { PATH: process.env.PATH, HOME: process.env.HOME },
            encoding: "utf8", timeout: 3000 });
        assert.equal(fixture.status, 0, fixture.stdout + fixture.stderr);
        await conversation(file, async w => {
            for (const [n, answer] of [[1, "ok"], [2, "refused: tui=task reason=busy"]]) {
                fs.writeFileSync(path.join(gates, "request-" + n), "");
                let request;
                // The fixture crosses the daemon's pipe; poll its actual
                // output, not a simulated request-owner result.
                for (let attempts = 0; attempts < 300; attempts++) {
                    request = w.messages.find(message => message.type === "request" && message.id === n);
                    if (request !== undefined) break;
                    await new Promise(resolve => setTimeout(resolve, 5));
                }
                assert.deepEqual(request, { v: 1, type: "request", gen: w.last().gen,
                    revision: hello.revision, id: n, kind: "tui.run", args: [path.join(gates, "spec-" + n + ".json")] });
                w.raw({ v: 1, type: "reply", gen: request.gen, revision: request.revision,
                    id: request.id, kind: request.kind, answer, data: null });
                const replies = path.join(gates, "replies.jsonl");
                for (let attempts = 0; attempts < 300; attempts++) {
                    if (fs.existsSync(replies) && fs.readFileSync(replies, "utf8").trim().split("\n").length === n) break;
                    await new Promise(resolve => setTimeout(resolve, 5));
                }
                assert.equal(JSON.parse(fs.readFileSync(replies, "utf8").trim().split("\n").at(-1)).answer,
                    answer, "the task display receives the shared owner's reply");
            }
        });
    }
    await taskWire(daemonCopy("task-wire"));
    await control("task-request-owner", 'requests.send("tui.run", args, 20000, result => {',
        'requests.send("desktop.list", [], 20000, result => {', taskWire);
    // No harness brain exists, so startup opens no tool bridge session.
    const noBridge = file => conversation(file, async () => {
        assert.equal(fs.existsSync(path.join(hello.directories.runtime, "tools.sock")), false, "startup creates no tools.sock");
    });
    await noBridge(daemon);
    await control("no-bridge-session", "// Executor owners register only after their real probes.",
        'void bridge.open({ gen: 0, recipients: require("./Policy.js").recipients({ conversation: "planted",'
        + ' profile: "standard", cloudVision: "ask", brain: { kind: "local", provider: "planted", account: "" },'
        + ' speech: [{ kind: "local", provider: "planted", account: "" }] }) });', noBridge);
    // A retired privacy record is removed as an entry, without reading its
    // bytes or restoring state. Voice mute has an independent lifetime.
    const retiredMuteFile = path.join(hello.directories.state, "mute.json");
    const retainedVoiceMuteFile = path.join(hello.directories.state, "voice-mute.json");
    const retiredTarget = path.join(root, "retired-mute-target.json");
    const retireCheck = async file => {
        for (const entry of ["muted", "corrupt", "linked", "absent"]) {
            fs.writeFileSync(retainedVoiceMuteFile, '{"muted":true}\n', { mode: 0o600 });
            const before = fs.statSync(retainedVoiceMuteFile, { bigint: true });
            if (entry === "muted") fs.writeFileSync(retiredMuteFile, '{"muted":true}');
            else if (entry === "corrupt") fs.writeFileSync(retiredMuteFile, Buffer.from([0xff, 0x7b]));
            else if (entry === "linked") {
                fs.writeFileSync(retiredTarget, "untouched target\n");
                fs.symlinkSync(retiredTarget, retiredMuteFile);
            }
            try {
                await conversation(file, async w => {
                    assert.equal(fs.existsSync(retiredMuteFile), false, "hello removes the retired " + entry + " entry");
                    assert.equal(w.last().state.voiceMute.kind, "on", "the independent voice mute still restores");
                    assert.equal(Object.hasOwn(w.last().state, "mute"), false);
                    if (entry === "linked") assert.equal(fs.readFileSync(retiredTarget, "utf8"), "untouched target\n");
                    const after = fs.statSync(retainedVoiceMuteFile, { bigint: true });
                    assert.deepEqual([after.ino, after.mtimeNs], [before.ino, before.mtimeNs], "retirement never rewrites voice mute");
                    w.raw(hello);
                    await w.wait(m => m.seq > 2);
                    assert.equal(fs.existsSync(retiredMuteFile), false, "a later hello needs no retired record");
                });
            } finally {
                fs.rmSync(retiredMuteFile, { force: true });
                fs.rmSync(retainedVoiceMuteFile, { force: true });
            }
        }
    };
    await retireCheck(daemon);
    await control("retired-mute-removal", "if (first) retireMute();", "if (false) retireMute();", retireCheck);
    fs.mkdirSync(retiredMuteFile);
    await run(daemon, [JSON.stringify(hello) + "\n"], 78, "jarvis: state=retired-mute-remove-failed");
    fs.rmdirSync(retiredMuteFile);
    // Voice mute keeps its own record: the intent stores it, talk and stop
    // keep it, the next daemon restores it, and a malformed record is
    // refused before it can grant voice state.
    const voiceMuteFile = path.join(hello.directories.state, "voice-mute.json");
    const storedVoiceMute = () => fs.existsSync(voiceMuteFile) ? JSON.parse(fs.readFileSync(voiceMuteFile, "utf8")) : null;
    const voiceMuteCheck = async file => {
        try { await voiceMuteRestart(file); } finally { fs.rmSync(voiceMuteFile, { force: true }); }
    };
    const voiceMuteRestart = async file => {
        await conversation(file, async w => {
            assert.equal(w.last().state.voiceMute.kind, "off");
            w.send("voice-mute");
            await w.wait(m => m.state.voiceMute.kind === "on");
            assert.deepEqual(storedVoiceMute(), { muted: true });
            assert.equal(fs.statSync(voiceMuteFile).mode & 0o777, 0o600);
            for (const name of ["talk-down", "talk-up", "stop"]) w.send(name);
            await w.wait(m => m.seq >= 5);
            assert.equal(w.last().state.voiceMute.kind, "on");
        });
        await conversation(file, async w => {
            assert.equal(w.last().state.voiceMute.kind, "on", "the next daemon restores voice mute");
            w.send("voice-mute");
            await w.wait(m => m.state.voiceMute.kind === "off");
            assert.deepEqual(storedVoiceMute(), { muted: false });
        });
    };
    await voiceMuteCheck(daemon);
    await control("voice-mute-store", 'fs.renameSync(file, path.join(directory, name));',
        'void directory;', voiceMuteCheck);
    await control("voice-mute-restore", 'if (first && readVoiceMute()) runner.dispatch({ type: "voice-mute" });',
        'if (false && first && readVoiceMute()) runner.dispatch({ type: "voice-mute" });', voiceMuteCheck);
    await control("voice-mute-intent", 'message.intent === "voice-mute" ? { type: "voice-mute-toggle" }', 'message.intent === "voice-mute" ? { type: "voice-mute" }', voiceMuteCheck);
    for (const [bytes, reason] of [["{", "record-json"], ['{"muted":"yes"}', "record-shape"],
        ['{"muted":true,"extra":0}', "record-shape"], [" ".repeat(65), "record-size"]]) {
        fs.writeFileSync(voiceMuteFile, bytes);
        await run(daemon, [JSON.stringify(hello) + "\n"], 78, "jarvis: voice-mute=" + reason);
    }
    fs.unlinkSync(voiceMuteFile);
    fs.mkdirSync(voiceMuteFile);
    await run(daemon, [JSON.stringify(hello) + "\n"], 78, "jarvis: voice-mute=record-not-file");
    fs.rmdirSync(voiceMuteFile);
    await conversation(daemon, async w => {
        fs.mkdirSync(voiceMuteFile);
        w.send("voice-mute");
    }, true, 78, "jarvis: voice-mute=write-failed");
    fs.rmdirSync(voiceMuteFile);
    await control("voice-mute-size", 'if (size > limit) throw new Error("jarvis: " + area + "=record-size");', 'void size;',
        async file => {
            fs.writeFileSync(voiceMuteFile, '{"muted":false}' + " ".repeat(51));
            await run(file, [JSON.stringify(hello) + "\n"], 78, "jarvis: voice-mute=record-size");
        });
    await control("voice-mute-shape", 'throw new Error("jarvis: " + area + "=record-shape");', ';',
        async file => {
            fs.writeFileSync(voiceMuteFile, '{"muted":false,"extra":0}');
            await run(file, [JSON.stringify(hello) + "\n"], 78, "jarvis: voice-mute=record-shape");
        });
    fs.unlinkSync(voiceMuteFile);
    const linkedVoiceRecord = path.join(root, "linked-voice-mute.json");
    fs.writeFileSync(linkedVoiceRecord, '{"muted":false}');
    fs.symlinkSync(linkedVoiceRecord, voiceMuteFile);
    await run(daemon, [JSON.stringify(hello) + "\n"], 78, "jarvis: voice-mute=read-failed");
    await control("voice-mute-link", 'fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK',
        'fs.constants.O_RDONLY | fs.constants.O_NONBLOCK',
        file => run(file, [JSON.stringify(hello) + "\n"], 78, "jarvis: voice-mute=read-failed"));
    fs.unlinkSync(voiceMuteFile);

    const hiddenFile = path.join(hello.directories.state, "hidden.json");
    const hiddenCheck = async file => {
        try {
            await conversation(file, async w => {
                assert.equal(w.last().state.visibility.kind, "shown", "an absent record means shown");
                assert.equal(fs.existsSync(hiddenFile), false, "absence creates no default record");
                let seq = w.last().seq;
                w.send("hide");
                await w.wait(m => m.seq > seq);
                assert.equal(w.last().state.visibility.kind, "shown", "Hide needs a presented widget");
                assert.equal(fs.existsSync(hiddenFile), false, "a refused Hide stores nothing");
                w.indicator(false, "present");
                await w.wait(m => m.state.barIndicator.kind === "present");
                w.send("hide");
                await w.wait(m => m.state.visibility.kind === "hidden");
                assert.equal(fs.existsSync(hiddenFile), true, "admitted Hide stores its choice before publication");
                assert.equal(fs.readFileSync(hiddenFile, "utf8"), '{"hidden":true}\n');
                assert.equal(fs.statSync(hiddenFile).mode & 0o777, 0o600);
                const before = fs.statSync(hiddenFile, { bigint: true });
                seq = w.last().seq;
                w.send("hide");
                w.send("voice-mute");
                for (const name of ["talk-down", "talk-up", "stop", "new-conversation"]) w.send(name);
                await w.wait(m => m.seq >= seq + 6);
                assert.equal(w.last().state.visibility.kind, "hidden");
                assert.equal(w.last().state.voiceMute.kind, "on", "voice mute is independent");
                const after = fs.statSync(hiddenFile, { bigint: true });
                assert.deepEqual([after.ino, after.mtimeNs], [before.ino, before.mtimeNs],
                    "idempotent Hide, voice mute, Talk, Stop and New conversation never rewrite the choice");
            });
            const before = fs.statSync(hiddenFile, { bigint: true });
            await conversation(file, async w => {
                assert.equal(w.last().state.visibility.kind, "hidden", "a new daemon restores the choice");
                assert.equal(w.last().state.voiceMute.kind, "on");
                assert.equal(w.last().state.capture.kind, "closed", "restore grants no capture");
                const restored = w.messages.findIndex(m => m.type === "state" && m.state.visibility.kind === "hidden");
                const ready = w.messages.findIndex(m => m.type === "status");
                assert.ok(restored >= 0 && restored < ready, "restore precedes readiness");
                assert.equal(w.messages[restored].state.gate.reason, "starting");
                const after = fs.statSync(hiddenFile, { bigint: true });
                assert.deepEqual([after.ino, after.mtimeNs], [before.ino, before.mtimeNs], "restore writes nothing");
                w.send("show");
                await w.wait(m => m.state.visibility.kind === "shown");
                assert.equal(fs.readFileSync(hiddenFile, "utf8"), '{"hidden":false}\n');
                assert.equal(w.last().state.barIndicator.kind, "gone", "Show needs no widget");
                const shown = fs.statSync(hiddenFile, { bigint: true });
                let seq = w.last().seq;
                w.send("show");
                await w.wait(m => m.seq > seq);
                const unchanged = fs.statSync(hiddenFile, { bigint: true });
                assert.deepEqual([unchanged.ino, unchanged.mtimeNs], [shown.ino, shown.mtimeNs], "idempotent Show writes nothing");
                fs.writeFileSync(hiddenFile, '{"hidden":true}\n');
                seq = w.last().seq;
                w.raw(hello);
                await w.wait(m => m.seq > seq);
                assert.equal(w.last().state.visibility.kind, "shown", "only the first hello restores the record");
                fs.writeFileSync(hiddenFile, '{"hidden":false}'.padEnd(64));
                w.send("voice-mute");
                await w.wait(m => m.state.voiceMute.kind === "off");
            });
            const storedFalse = fs.statSync(hiddenFile, { bigint: true });
            await conversation(file, async w => {
                assert.equal(w.last().state.visibility.kind, "shown", "a saved false at the read bound stays shown");
                assert.equal(w.last().state.voiceMute.kind, "off");
                assert.equal(w.messages.filter(m => m.type === "state")[0].state.gate.reason, "unconfigured",
                    "false needs no private restore event");
                const after = fs.statSync(hiddenFile, { bigint: true });
                assert.deepEqual([after.ino, after.mtimeNs], [storedFalse.ino, storedFalse.mtimeNs]);
            });
        } finally {
            fs.rmSync(hiddenFile, { force: true });
            fs.rmSync(voiceMuteFile, { force: true });
        }
    };
    await hiddenCheck(daemon);
    for (const [name, needle, replacement] of [
        ["hidden-store", 'storeRecord("hidden", "hidden.json", { hidden });', 'void hidden;'],
        ["hidden-restore", 'if (first && readHidden()) runner.dispatch({ type: "hidden" });',
            'if (false && first && readHidden()) runner.dispatch({ type: "hidden" });'],
        ["hidden-first-hello", 'if (first && readHidden()) runner.dispatch({ type: "hidden" });',
            'if (readHidden()) runner.dispatch({ type: "hidden" });'],
        ...["hide", "show"].map(name => ["hidden-" + name + "-intent", ': { type: message.intent });',
            ': { type: message.intent === "' + name + '" ? "stop" : message.intent });'])
    ]) await control(name, needle, replacement, hiddenCheck);

    // Hidden is a private exact boolean record, not settings or a mute record.
    const hiddenRefusal = async (file, bytes, reason) => {
        try {
            fs.writeFileSync(hiddenFile, bytes);
            await run(file, [JSON.stringify(hello) + "\n"], 78, "jarvis: hidden=" + reason);
        } finally { fs.rmSync(hiddenFile, { force: true }); }
    };
    for (const [bytes, reason] of [
        ["{", "record-json"], ["null", "record-shape"], ["[]", "record-shape"], ["{}", "record-shape"],
        ['{"muted":true}', "record-shape"], ['{"hidden":null}', "record-shape"],
        ['{"hidden":0}', "record-shape"], ['{"hidden":"false"}', "record-shape"],
        ['{"hidden":false,"extra":0}', "record-shape"], ['{"hidden":false}'.padEnd(65), "record-size"]
    ]) await hiddenRefusal(daemon, bytes, reason);
    fs.mkdirSync(hiddenFile);
    try { await run(daemon, [JSON.stringify(hello) + "\n"], 78, "jarvis: hidden=record-not-file"); }
    finally { fs.rmdirSync(hiddenFile); }
    const linkedHiddenRecord = path.join(root, "linked-hidden.json");
    fs.writeFileSync(linkedHiddenRecord, '{"hidden":true}\n');
    fs.symlinkSync(linkedHiddenRecord, hiddenFile);
    try {
        await run(daemon, [JSON.stringify(hello) + "\n"], 78, "jarvis: hidden=read-failed");
        assert.equal(fs.readFileSync(linkedHiddenRecord, "utf8"), '{"hidden":true}\n');
    } finally { fs.unlinkSync(hiddenFile); }
    await control("hidden-shape", 'throw new Error("jarvis: hidden=record-shape");', ';',
        file => hiddenRefusal(file, '{"hidden":false,"extra":0}', "record-shape"));
    await control("hidden-size", 'if (size > limit) throw new Error("jarvis: " + area + "=record-size");', 'void size;',
        file => hiddenRefusal(file, '{"hidden":false}'.padEnd(65), "record-size"));

    const scripted = daemonCopy("scripted");
    const gates = path.join(root, "gates");
    instrument(scripted, gates);
    const heldDaemon = daemonCopy("held-delivery");
    instrument(heldDaemon, path.join(root, "held-delivery-gates"));
    // This table freezes only Session's clock, so even a paused test process
    // cannot turn the early-release control into an accidental real hold.
    holdClock(heldDaemon, true);
    // Simulate the daemon consuming the press after delivery advances its
    // clock, without delaying the test or enlarging Session's tap threshold.
    const heldDelivery = (at, release = releaseHeld) => conversation(heldDaemon, async w => {
        w.pressClock(at);
        w.send("talk-down");
        const held = await w.wait(message => message.phase === "listening" && message.state.input.kind === "held");
        assert.ok(held.state.input.since >= at, "the daemon records the delivered press on its own clock");
        await w.holdUp(release);
        await w.wait(message => message.phase === "thinking" && message.state.input.kind === "released");
        w.send("stop");
        await w.wait(message => message.state.conversation.kind === "active" && message.phase === "idle");
    });
    const deliveries = [{ name: "immediate", at: 0 }, { name: "delayed", at: 4 * TAP_MS }];
    for (const delivery of deliveries) {
        await heldDelivery(delivery.at);
        console.log("test-jarvis-daemon: held-delivery=" + delivery.name + " passed");
    }
    async function desktopDriver(file, directory, mappedIndicator = false) {
        await conversation(file, async w => {
            writeCall(directory, { id: "fixture-help", tool: "help", arguments: { topic: "input" } });
            if (mappedIndicator) {
                const waiting = await w.wait(message => message.state.input.kind === "held");
                assert.equal(waiting.state.capture.kind, "closed", "the driver waits for the mapped indicator");
                const results = path.join(directory, "results.jsonl");
                assert.equal(fs.existsSync(results), false, "the driver retains demand instead of reporting no-turn");
                w.indicator(true);
            }
            const results = path.join(directory, "results.jsonl");
            await w.wait(() => fs.existsSync(results) && fs.readFileSync(results, "utf8").includes('"outcome"'));
            // A help read answers within its route, so its outcome row can
            // come before the route row.
            const result = fs.readFileSync(results, "utf8").trim().split("\n").map(JSON.parse).find(row => row.outcome !== undefined);
            assert.deepEqual([result.id, result.outcome, typeof result.content === "string" && result.content !== ""], ["fixture-help", "completed", true]);
        });
    }
    const desktopDriverFile = daemonCopy("desktop-driver");
    instrument(desktopDriverFile, path.join(root, "desktop-driver-gates"));
    const driverRoot = path.join(root, "desktop-driver-results");
    const driver = cp.spawnSync(process.execPath, [path.join(tree, "scripts/fixtures/jarvis/desktop-driver.js"),
        desktopDriverFile, driverRoot], { env: { PATH: process.env.PATH, HOME: process.env.HOME }, encoding: "utf8" });
    assert.equal(driver.status, 0, driver.stderr);
    await desktopDriver(desktopDriverFile, driverRoot);
    const mappedDriverFile = daemonCopy("desktop-driver-mapped");
    instrument(mappedDriverFile, path.join(root, "desktop-driver-mapped-gates"), "chained", true);
    const mappedDriverRoot = path.join(root, "desktop-driver-mapped-results");
    const mappedDriver = cp.spawnSync(process.execPath,
        [path.join(tree, "scripts/fixtures/jarvis/desktop-driver.js"), mappedDriverFile, mappedDriverRoot],
        { env: { PATH: process.env.PATH, HOME: process.env.HOME }, encoding: "utf8" });
    assert.equal(mappedDriver.status, 0, mappedDriver.stderr);
    await desktopDriver(mappedDriverFile, mappedDriverRoot, true);
    const mappedDriverFixture = path.join(path.dirname(mappedDriverFile), "desktop-driver-fixture.js");
    const mappedDriverSource = fs.readFileSync(mappedDriverFixture, "utf8");
    const captureWait = 'if (turnRequest === "held" && runner.state.capture.kind === "open" && runner.state.input.kind === "held"\n'
        + '                        && runner.clock.now() - runner.state.input.since >= runner.session.TAP_MS) {';
    assert.equal(mappedDriverSource.split(captureWait).length - 1, 1);
    const earlyRelease = mappedDriverSource.replace(captureWait, 'if (turnRequest === "held") {');
    assert.notEqual(earlyRelease, mappedDriverSource);
    fs.writeFileSync(mappedDriverFixture, earlyRelease);
    fs.rmSync(path.join(mappedDriverRoot, "results.jsonl"));
    await assert.rejects(() => desktopDriver(mappedDriverFile, mappedDriverRoot, true), assert.AssertionError,
        "a driver that releases demand before presentation must fail the mapped-indicator assertion");
    controls++;
    const driverSource = fs.readFileSync(desktopDriverFile, "utf8");
    const driverCall = '                    require("./desktop-driver-fixture.js").drive('
        + JSON.stringify(driverRoot) + ', runner, router);\n';
    assert.equal(driverSource.split(driverCall).length - 1, 1);
    const driverStart = "                    executors = Executors.register(";
    assert.equal(driverSource.split(driverStart).length - 1, 1);
    const earlyDriver = driverSource.replace(driverCall, "").replace(driverStart, driverCall + driverStart);
    assert.notEqual(earlyDriver, driverSource);
    fs.writeFileSync(desktopDriverFile, earlyDriver);
    fs.rmSync(path.join(driverRoot, "results.jsonl"));
    await assert.rejects(() => desktopDriver(desktopDriverFile, driverRoot), assert.AssertionError,
        "an engine port replacement must not discard the driver's result sink");
    controls++;
    // The shipped daemon judges a Codex file change's paths through Denied: a
    // protected root refuses and a workspace path reaches its proposal. A
    // snapshot that cannot be built refuses as path-context with one keyed line.
    const deniedResults = path.join(root, "denied-results");
    const deniedCheck = async (file, expected, error = "") => {
        fs.mkdirSync(deniedResults, { recursive: true });
        fs.rmSync(path.join(deniedResults, "results.jsonl"), { force: true });
        const routed = id => lines(path.join(deniedResults, "results.jsonl"))
            .find(row => row.id === id && row.route !== undefined);
        await conversation(file, async w => {
            for (const [id, target] of [["protected", path.join(process.env.HOME, ".ssh/id_fixture")],
                ["workspace", path.join(process.env.HOME, "project/new")]]) {
                writeCall(deniedResults, { id, kind: "approval",
                    tool: "harness.files", arguments: { write: [target], move: [], remove: [], diff: "+fixture\n" } });
                await w.wait(() => routed(id) !== undefined);
            }
            assert.deepEqual(["protected", "workspace"].map(routed), expected);
        }, true, 0, error);
    };
    const deniedDaemon = daemonCopy("denied-driver");
    instrument(deniedDaemon, path.join(root, "denied-gates"));
    instrumentDesktop(deniedDaemon, deniedResults);
    await deniedCheck(deniedDaemon, [{ id: "protected", route: "refuse", reason: "protected-path" },
        { id: "workspace", route: "proposed" }]);
    const unbuilt = [{ id: "protected", route: "refuse", reason: "path-context" },
        { id: "workspace", route: "refuse", reason: "path-context" }];
    // A dangling linked configuration root fails Denied's root resolution;
    // each of the two judgements logs its keyed line.
    const configRoot = path.join(process.env.HOME, ".config");
    assert.equal(fs.existsSync(configRoot), false, "the scratch home has no configuration root");
    const unbuiltCheck = async file => {
        fs.symlinkSync(path.join(process.env.HOME, "absent-config"), configRoot);
        try {
            await deniedCheck(file, unbuilt, Array(2).fill("jarvis: denied=unavailable cause=ENOENT").join("\n"));
        } finally { fs.rmSync(configRoot); }
    };
    await unbuiltCheck(deniedDaemon);
    for (const [name, needle, replacement, check] of [
        ["denied-wired", "get denied() { return deniedOrNull(); } }),", "denied: null }),", file => deniedCheck(file,
            [{ id: "protected", route: "refuse", reason: "protected-path" }, { id: "workspace", route: "proposed" }])],
        ["denied-refuses", "            return null;\n        }\n    }\n\n    // hyprctl",
            "            throw error;\n        }\n    }\n\n    // hyprctl", unbuiltCheck]
    ]) {
        const file = daemonCopy("denied-" + name);
        const before = fs.readFileSync(file, "utf8");
        assert.equal(before.split(needle).length - 1, 1, name + " match");
        fs.writeFileSync(file, before.replace(needle, replacement));
        instrument(file, path.join(root, "denied-gates"));
        instrumentDesktop(file, deniedResults);
        await assert.rejects(() => check(file), assert.AssertionError, name + " must turn red");
        controls++;
        console.log("test-jarvis-daemon: control=" + name + " detected");
    }
    const count = kind => fs.readFileSync(path.join(gates, "effects.jsonl"), "utf8").trim().split("\n")
        .filter(line => JSON.parse(line).kind === kind).length;
    const gate = name => fs.writeFileSync(path.join(gates, name), "");
    // The physical-key row swaps the daemon for its Node-floor control, then
    // restores the scripted daemon. Its ready engine must stay paired with
    // that daemon until final teardown removes the scripted helper.
    async function scriptedLifecycle(name, restoreOnlyEngine = false) {
        const file = daemonCopy(name);
        const engineFile = path.join(path.dirname(file), "ChainedEngine.js");
        const originalEngine = fs.readFileSync(engineFile);
        const lifecycleGates = path.join(path.dirname(file), "lifecycle-gates");
        instrument(file, lifecycleGates);
        const scriptedDaemon = fs.readFileSync(file);
        const effects = kind => {
            const log = path.join(lifecycleGates, "effects.jsonl");
            return fs.existsSync(log) ? fs.readFileSync(log, "utf8").trim().split("\n").map(JSON.parse)
                .filter(row => row.kind === kind).length : 0;
        };
        const firstTalk = () => conversation(file, async w => {
            assert.equal(w.last().state.gate.kind, "up", "scripted first Talk requires its ready engine");
            const cues = effects("feedback-start"), opens = effects("capture-open");
            w.send("talk-down");
            await w.wait(m => m.phase === "listening");
            assert.equal(effects("feedback-start"), cues + 1, "first Talk completes the scripted start cue");
            assert.equal(effects("capture-open"), opens + 1, "first Talk opens one capture after its cue");
            await w.holdUp();
            await w.wait(m => m.phase === "thinking");
            assert.equal(effects("playback-start"), 0, "the basic fixture keeps its assistant reply gated");
            await w.closeTalk(lifecycleGates);
            await w.wait(m => m.state.conversation.kind === "ended" && m.state.playback.kind === "idle");
        }, true, 0, "", null, true, {}, true);
        await firstTalk();
        fs.writeFileSync(file, source);
        const floor = cp.spawnSync(process.execPath, [path.join(tree, "scripts/fixtures/jarvis/prepare.js"),
            "--floor-daemon", file], { env: { PATH: process.env.PATH, HOME: process.env.HOME }, encoding: "utf8" });
        assert.equal(floor.status, 0, floor.stderr);
        await run(file, [], 78, "jarvis: node=21.0.0 need=22");
        fs.writeFileSync(file, scriptedDaemon);
        if (restoreOnlyEngine) fs.writeFileSync(engineFile, originalEngine);
        await firstTalk();
        fs.writeFileSync(file, source);
        fs.writeFileSync(engineFile, originalEngine);
        fs.unlinkSync(path.join(path.dirname(file), "scripted-fixture.js"));
        await run(file, [JSON.stringify(hello) + "\n"], 0, null, states([false]));
    }
    await scriptedLifecycle("scripted-feedback-lifecycle");
    await assert.rejects(() => scriptedLifecycle("scripted-feedback-restore-control", true),
        error => error instanceof assert.AssertionError
            && error.message.startsWith("scripted first Talk requires its ready engine")
            && error.actual === "down" && error.expected === "up",
        "restoring only the product engine must fail first-Talk readiness");
    controls++;
    console.log("test-jarvis-daemon: control=scripted-feedback-engine-pair detected");
    const mapped = daemonCopy("mapped-indicator");
    instrument(mapped, gates, "chained", true);
    const mappedCheck = async file => {
        const outputGate = path.join(path.dirname(file), "mapped-output");
        const seen = path.join(path.dirname(file), "mapped-seen.jsonl");
        const prepared = cp.spawnSync(process.execPath, [path.join(tree, "scripts/fixtures/jarvis/prepare.js"),
            "--gate-daemon", file, outputGate, seen], { env: { PATH: process.env.PATH, HOME: process.env.HOME }, encoding: "utf8" });
        assert.equal(prepared.status, 0, prepared.stderr);
        fs.writeFileSync(outputGate, "");
        const effectsAt = lines(path.join(gates, "effects.jsonl")).length;
        try { await conversation(file, async w => {
            assert.equal(w.last().state.indicator.kind, "gone");
            w.send("talk-down");
            const waiting = await w.wait(m => m.state.input.kind === "held");
            assert.equal(waiting.state.capture.kind, "closed", "no screen keeps capture closed");
            w.indicator(true);
            await w.wait(m => m.phase === "listening");
            fs.writeFileSync(path.join(gates, "hold-final"), "");
            w.indicator(false);
            const gone = await w.wait(m => m.state.indicator.kind === "gone" && m.state.capture.kind === "closed");
            assert.equal(gone.state.capture.kind, "closed", "indicator loss releases capture");
            assert.equal(gone.state.input.kind, "held");
            fs.unlinkSync(outputGate);
            gate("final");
            await w.wait(() => lines(seen).some(m => m.type === "state" && m.seq > gone.seq
                && m.state.input.kind === "released" && m.phase === "thinking"));
            const released = lines(seen).filter(m => m.type === "state").at(-1);
            assert.equal(w.last().state.input.kind, "held", "the delivered frame still predates the final");
            assert.ok(w.last().seq < released.seq, "the daemon's released frame is still behind the output gate");
            const closing = w.closeTalk(gates);
            await w.wait(() => lines(seen).some(m => m.type === "state" && m.seq > released.seq));
            fs.writeFileSync(outputGate, "");
            try {
                await closing;
                await w.wait(m => m.state.conversation.kind === "ended");
            } finally {
                const states = lines(seen).filter(m => m.type === "state" && m.seq >= gone.seq).map(m => ({ seq: m.seq, gen: m.gen,
                    phase: m.phase, input: m.state.input.kind, capture: m.state.capture.kind,
                    conversation: m.state.conversation.kind, indicator: m.state.indicator.kind }));
                console.log("test-jarvis-daemon: mapped-close=" + JSON.stringify({ scenario: path.basename(path.dirname(file)),
                    delivered: { seq: gone.seq, gen: gone.gen }, states,
                    finals: lines(path.join(gates, "effects.jsonl")).slice(effectsAt).filter(e => e.kind === "capture-final")
                        .map(e => ({ gen: e.gen, close: e.op, capture: e.target })),
                    intents: w.sent.filter(m => m.type === "intent").map(m => ({ intent: m.intent, gen: m.gen })) }));
            }
            assert.equal(fs.existsSync(path.join(gates, "silent-capture")), false,
                "a no-capture close leaves no empty result for the next utterance");
        }, true, 0, "", null, hello.settings.sounds, {}, true);
        } finally {
            fs.rmSync(path.join(gates, "hold-final"), { force: true });
            fs.rmSync(path.join(gates, "silent-capture"), { force: true });
        }
    };
    await mappedCheck(mapped);
    for (const [name, needle, replacement] of [
        ["indicator-delivery", 'runner.dispatch({ type: "indicator", gen: message.gen, shown: message.shown, bar: message.bar });', 'void message.shown;'],
        ["indicator-loss", 'shown: message.shown', 'shown: true'],
        ["silent-talk-close", ': { type: message.intent });',
            ': { type: message.intent === "talk-up" ? "stop" : message.intent });']
    ]) {
        const copy = daemonCopy(name);
        instrument(copy, gates, "chained", true);
        const before = fs.readFileSync(copy, "utf8");
        assert.equal(before.split(needle).length - 1, 1);
        fs.writeFileSync(copy, before.replace(needle, replacement));
        await assert.rejects(() => mappedCheck(copy), assert.AssertionError, name + " must turn red");
        controls++;
    }

    const hiddenMapped = daemonCopy("hidden-indicator");
    const hiddenGates = path.join(root, "hidden-indicator-gates");
    instrument(hiddenMapped, hiddenGates, "chained", true);
    const hiddenIndicatorCheck = async file => {
        try {
            await conversation(file, async w => {
                w.indicator(false, "present");
                await w.wait(m => m.state.barIndicator.kind === "present");
                w.send("hide");
                await w.wait(m => m.state.visibility.kind === "hidden");
                w.send("talk-down");
                const waiting = await w.wait(m => m.state.input.kind === "held");
                assert.equal(waiting.state.capture.kind, "closed", "a previous generation's widget grants no capture");
                const gen = waiting.state.gen;
                let seq = waiting.seq;
                w.indicator(false, "listening", gen - 1);
                await w.wait(m => m.seq > seq);
                assert.equal(w.last().state.barIndicator.kind, "gone", "the wire retains the observed generation");
                assert.equal(w.last().state.capture.kind, "closed", "a stale listening badge cannot open capture");
                w.indicator(false, "present");
                await w.wait(m => m.state.barIndicator.kind === "present");
                assert.equal(w.last().state.capture.kind, "closed", "a widget without a listening badge grants no capture");
                w.indicator(false, "listening");
                await w.wait(m => m.state.capture.kind === "open");
                assert.deepEqual(w.last().state.barIndicator, { kind: "listening", gen });
                fs.writeFileSync(path.join(hiddenGates, "silent-capture"), "");
                w.indicator(false, "gone", gen - 1);
                await w.wait(m => m.state.capture.kind === "closed");
                await w.wait(m => m.state.turn.kind === "none");
                assert.equal(w.last().state.barIndicator.kind, "gone", "loss withdraws across generations");
                w.send("show");
                await w.wait(m => m.state.visibility.kind === "shown");
                assert.equal(w.last().state.capture.kind, "closed", "shown mode waits for the orb");
                w.indicator(true);
                await w.wait(m => m.state.capture.kind === "open");
                seq = w.last().seq;
                await w.closeTalk(hiddenGates);
                await w.wait(m => m.seq > seq && m.state.conversation.kind === "ended" && m.state.capture.kind === "closed");
            }, true, 0, "", null, hello.settings.sounds, {}, true);
        } finally { fs.rmSync(hiddenFile, { force: true }); }
    };
    await hiddenIndicatorCheck(hiddenMapped);
    for (const [name, needle, replacement] of [
        ["hidden-indicator-gen", 'gen: message.gen, shown: message.shown, bar: message.bar',
            'shown: message.shown, bar: message.bar'],
        ["hidden-indicator-stale", 'gen: message.gen, shown: message.shown, bar: message.bar',
            'gen: runner.state.gen, shown: message.shown, bar: message.bar'],
        ["hidden-indicator-bar", 'bar: message.bar', 'bar: "gone"']
    ]) {
        const copy = daemonCopy(name);
        instrument(copy, hiddenGates, "chained", true);
        const before = fs.readFileSync(copy, "utf8");
        assert.equal(before.split(needle).length - 1, 1, name + " mutation match");
        fs.writeFileSync(copy, before.replace(needle, replacement));
        await assert.rejects(() => hiddenIndicatorCheck(copy), assert.AssertionError, name + " must turn red");
        controls++;
    }

    // Both menu intents use the same ordinary daemon route. A failed
    // durable choice ends that lease without publishing the new choice,
    // even while its capture needs privacy teardown.
    const hiddenFailureCheck = async file => {
        for (const action of ["hide", "show"]) {
            let messages, from, capture;
            const effects = lines(path.join(hiddenGates, "effects.jsonl")).length;
            try {
                await conversation(file, async w => {
                    if (action === "show") {
                        w.indicator(false, "present");
                        await w.wait(m => m.state.barIndicator.kind === "present");
                        w.send("hide");
                        await w.wait(m => m.state.visibility.kind === "hidden");
                    } else w.indicator(true);
                    w.send("talk-down");
                    await w.wait(m => m.state.input.kind === "held");
                    w.indicator(action === "hide", action === "hide" ? "present" : "listening");
                    const open = await w.wait(m => m.state.capture.kind === "open"
                        && m.state.barIndicator.gen === m.state.gen);
                    capture = { gen: open.state.capture.gen, op: open.state.capture.op };
                    assert.equal(open.state.visibility.kind, action === "hide" ? "shown" : "hidden");
                    if (fs.existsSync(hiddenFile)) fs.unlinkSync(hiddenFile);
                    fs.mkdirSync(hiddenFile);
                    messages = w.messages;
                    from = messages.length;
                    w.send(action);
                }, true, 78, "jarvis: hidden=write-failed");
                assert.equal(messages.slice(from).some(m => m.type === "state"
                    && m.state.visibility.kind === (action === "hide" ? "hidden" : "shown")), false,
                    "failed " + action + " and fatal teardown publish no changed choice");
                assert.ok(lines(path.join(hiddenGates, "effects.jsonl")).slice(effects)
                    .some(e => e.kind === "capture-close" && e.gen === capture.gen && e.target === capture.op),
                    "failed " + action + " still closes its acquired capture");
                assert.deepEqual(fs.readdirSync(hello.directories.state).filter(name => name.startsWith(".hidden.json-")), [],
                    "failed rename cleans up the owned temporary record");
            } finally {
                if (fs.existsSync(hiddenFile) && fs.lstatSync(hiddenFile).isDirectory()) fs.rmdirSync(hiddenFile);
                else fs.rmSync(hiddenFile, { force: true });
            }
        }
    };
    await hiddenFailureCheck(hiddenMapped);
    for (const [name, needle, replacement] of [
        ["hidden-permanent-failure", '(voice-mute=|hidden=|state=retired-mute-)', '(voice-mute=|state=retired-mute-)'],
        ["hidden-fatal-publication", 'if (!ending && context !== null) write({ v: 1, type: "state"',
            'if (context !== null) write({ v: 1, type: "state"']
    ]) {
        const copy = daemonCopy(name);
        instrument(copy, hiddenGates, "chained", true);
        const before = fs.readFileSync(copy, "utf8");
        assert.equal(before.split(needle).length - 1, 1, name + " mutation match");
        fs.writeFileSync(copy, before.replace(needle, replacement));
        await assert.rejects(() => hiddenFailureCheck(copy), assert.AssertionError, name + " must turn red");
        controls++;
    }

    // The runner publishes the thinking frame before it hands the turn to the
    // brain port, so the brain-send row lands after that frame: the case
    // waits for the row its say adds, within the conversation's read bound.
    const typedSay = (file, effectsRoot) => conversation(file, async w => {
        const sends = () => lines(path.join(effectsRoot, "effects.jsonl")).filter(row => row.kind === "brain-send");
        const before = sends().length;
        w.raw({ v: 1, type: "intent", gen: 0, revision: hello.revision, intent: "say", text: "typed daemon words" });
        await w.wait(m => m.phase === "thinking" && w.messages.some(row => row.type === "transcript" && row.role === "user"));
        assert.deepEqual(w.messages.filter(m => m.type === "transcript").map(m => [m.role, m.stage, m.text]),
            [["user", "final", "typed daemon words"]]);
        await w.wait(() => sends().length > before);
        assert.deepEqual(sends().slice(before).map(row => row.text), ["typed daemon words"]);
    });
    await typedSay(scripted, gates);
    await control("say-text-dispatch", 'message.intent === "say" ? { type: "say", text: message.text }',
        'message.intent === "say" ? { type: "say", text: "wrong" }', async file => {
            const sayGates = path.join(root, "say-text-dispatch-gates");
            instrument(file, sayGates);
            await typedSay(file, sayGates);
        });
    {
        // The user's words stay right and only the brain hears others.
        const file = daemonCopy("say-brain-text");
        const runnerFile = path.join(path.dirname(file), "session-runner.js");
        const needle = 'case "brain-send": this.ports.brain.send(e, ';
        const before = fs.readFileSync(runnerFile, "utf8");
        assert.equal(before.split(needle).length - 1, 1, "say-brain-text mutation match");
        fs.writeFileSync(runnerFile, before.replace(needle, 'case "brain-send": this.ports.brain.send({ ...e, text: "wrong" }, '));
        const sayGates = path.join(root, "say-brain-text-gates");
        instrument(file, sayGates);
        await assert.rejects(() => typedSay(file, sayGates), assert.AssertionError, "say-brain-text must turn red");
        controls++;
    }
    // Stop's settled frame: the flush acknowledgement publishes the idle
    // playback after the flushing frame, so a reader waits for it.
    const stopSettled = m => m.state.conversation.kind === "active" && m.phase === "idle"
        && m.state.playback.kind === "idle";
    const stopGates = ["brain", "played", "late-brain", "late-played", "hold-flush", "flush"];
    const activeStop = async (file, phase, settled = stopSettled) => conversation(file, async w => {
        w.send("talk-down");
        const listening = await w.wait(m => m.phase === "listening");
        await w.holdUp();
        await w.wait(m => m.phase === "thinking");
        if (phase === "speaking") {
            const starts = count("playback-start");
            gate("brain");
            await w.wait(m => m.phase === "speaking" && count("playback-start") === starts + 1);
        }
        const effect = phase === "thinking" ? "brain-cancel" : "playback-flush";
        const before = count(effect);
        const playback = count("playback-start");
        // A speaking Stop holds its flush acknowledgement until the reader
        // has seen the flushing frame, so that frame is always read first.
        const hold = phase === "speaking";
        if (hold) gate("hold-flush");
        let released = false;
        w.send("stop");
        const ended = await w.wait(m => {
            if (hold && !released && m.state.playback.kind === "flushing") { released = true; gate("flush"); }
            return settled(m);
        });
        fs.rmSync(path.join(gates, "hold-flush"), { force: true });
        assert.equal(released, hold, "a speaking Stop publishes its flushing frame first");
        // The daemon publishes a state before it consumes that state's
        // effects, so the effect record can trail the frame read above.
        for (let attempts = 0; attempts < 200 && count(effect) === before; attempts++)
            await new Promise(resolve => setTimeout(resolve, 5));
        assert.equal(count(effect), before + 1, "active Stop delivers " + effect);
        assert.equal(ended.state.capture.kind, "closed");
        assert.equal(ended.state.playback.kind, "idle");
        assert.equal(ended.state.brain.kind, "acquired", "Stop keeps the conversation adapter");
        assert.equal(ended.state.gen, listening.gen, "Stop keeps the conversation identity");
        assert.equal(ended.state.turn.kind, "none");
        gate(phase === "thinking" ? "late-brain" : "late-played");
        const late = await w.wait(m => m.state.stale > ended.state.stale);
        assert.equal(late.phase, "idle", "late callback cannot restart the stopped turn");
        assert.equal(late.state.conversation.kind, "active");
        assert.equal(late.state.capture.kind, "closed");
        assert.equal(late.state.playback.kind, "idle");
        assert.equal(count("playback-start"), playback);
    });
    for (const phase of ["thinking", "speaking"]) await activeStop(scripted, phase);
    // An active conversation frame can still carry a held playback flush.
    await assert.rejects(() => activeStop(scripted, "speaking", m => m.state.conversation.kind === "active" && m.phase === "idle"),
        { name: "AssertionError", message: /'flushing' !== 'idle'/ }, "a Stop read before its flush settles must turn red");
    for (const name of stopGates)
        fs.rmSync(path.join(gates, name), { force: true });
    controls++;
    console.log("test-jarvis-daemon: control=stop-settled detected");
    const stopControl = daemonCopy("stop-routing");
    instrument(stopControl, gates);
    const dispatch = 'runner.dispatch(message.intent === "voice-mute" ? { type: "voice-mute-toggle" }';
    const stopSource = fs.readFileSync(stopControl, "utf8");
    assert.equal(stopSource.split(dispatch).length - 1, 1);
    const misrouted = stopSource.replace(dispatch, 'if (message.intent === "stop") message.intent = "talk-up";\n                    ' + dispatch);
    assert.notEqual(misrouted, stopSource);
    fs.writeFileSync(stopControl, misrouted);
    for (const phase of ["thinking", "speaking"]) {
        await assert.rejects(() => activeStop(stopControl, phase), assert.AssertionError,
            "Stop-to-talk-up must fail the same " + phase + " assertion");
        for (const name of stopGates)
            fs.rmSync(path.join(gates, name), { force: true });
        controls++;
        console.log("test-jarvis-daemon: control=stop-to-talk-up phase=" + phase + " killed");
    }
    const initialOpens = count("capture-open");
    await conversation(scripted, async w => {
        w.send("talk-down");
        const listening = await w.wait(m => m.phase === "listening");
        assert.equal(count("capture-open"), initialOpens + 1);
        w.send("talk-down");
        await w.wait(m => m.seq > listening.seq);
        assert.equal(count("capture-open"), initialOpens + 1, "repeat opens no second scripted capture");
        await w.holdUp();
        await w.wait(m => m.phase === "thinking");
        gate("brain");
        await w.wait(m => m.phase === "speaking");
        gate("played");
        await w.wait(m => m.phase === "idle" && m.state.playback.kind === "idle");
        w.send("talk-down");
        await w.wait(m => m.phase === "listening");
        gate("hold-close");
        await w.closeTalk(gates);
        await w.wait(m => m.state.input.kind === "closing-tap" && m.state.capture.kind === "closing");
        assert.equal(w.last().state.conversation.kind, "active", "an empty tap waits for the recorder's final");
        gate("close");
        await w.wait(m => m.state.conversation.kind === "ended" && m.state.capture.kind === "closed");
        assert.equal(count("capture-open"), initialOpens + 2);
        fs.unlinkSync(path.join(gates, "hold-close"));
    }, true, 0, "", null, hello.settings.sounds, {}, true);
    await conversation(scripted, async w => {
        w.send("talk-down");
        await w.wait(m => m.phase === "listening");
        const before = w.last().seq;
        w.send("talk-up");
        await w.wait(m => m.seq > before);
        assert.equal(w.last().state.input.kind, "conversation", "release does not commit toggle");
        w.pressClock(w.last().state.toggleAt + TOGGLE_DEBOUNCE_MS);
        w.send("talk-down");
        await w.wait(m => m.state.conversation.kind === "ended" && m.state.capture.kind === "closed");
        assert.equal(w.last().state.capture.kind, "closed");
    }, false);
    // The duplex wire: a caption from the live speech session reaches stdout as
    // a judged transcript line; one from a closed session is counted stale.
    const duplexGates = path.join(root, "duplex-gates");
    const captions = file => conversation(file, async w => {
        w.send("talk-down");
        const open = await w.wait(m => m.state.speech.kind === "open" && m.phase === "listening");
        fs.writeFileSync(path.join(duplexGates, "transcript"), "");
        await w.wait(() => w.messages.some(m => m.type === "transcript"));
        assert.deepEqual(w.messages.filter(m => m.type === "transcript"), [{ v: 1, type: "transcript", gen: open.gen,
            revision: hello.revision, role: "user", text: "scripted words", stage: "partial", rev: 1 }]);
        await w.closeTalk(duplexGates);
        const ended = await w.wait(m => m.state.speech.kind === "closed");
        fs.writeFileSync(path.join(duplexGates, "transcript"), "");
        await w.wait(m => m.state.stale > ended.state.stale);
        assert.equal(w.messages.filter(m => m.type === "transcript").length, 1, "a closed session's caption stays off the wire");
    }, true, 0, "", null, hello.settings.sounds, {}, true);
    const duplex = daemonCopy("duplex");
    instrument(duplex, duplexGates, "duplex");
    await captions(duplex);
    const silent = daemonCopy("duplex-silent");
    const wireNeedle = 'if (!ending && context !== null) write({ v: 1, type: "transcript",';
    const silentSource = fs.readFileSync(silent, "utf8");
    assert.equal(silentSource.split(wireNeedle).length - 1, 1, "transcript wire mutation match");
    fs.writeFileSync(silent, silentSource.replace(wireNeedle, 'if (false) write({ v: 1, type: "transcript",'));
    instrument(silent, duplexGates, "duplex");
    await assert.rejects(() => captions(silent), assert.AssertionError, "a dropped transcript port must turn red");
    controls++;
    console.log("test-jarvis-daemon: control=transcript-wire killed");
    // The bubble row's world: the scripted ports hand each turn to the real
    // engine under the fixture's chained plan, and the reply gate releases
    // the scripted driver's words. They reach the wire only as the engine's
    // captions of the sentence it released.
    const chainedGates = path.join(root, "chained-gates");
    const replyWords = file => conversation(file, async w => {
        w.send("talk-down");
        const listening = await w.wait(m => m.phase === "listening");
        await w.holdUp();
        const thinking = await w.wait(m => m.phase === "thinking");
        fs.writeFileSync(path.join(chainedGates, "reply"), "");
        await w.wait(m => m.phase === "speaking" && m.state.turn.kind === "none");
        assert.deepEqual(w.messages.filter(m => m.type === "transcript").map(m => [m.gen, m.role, m.stage, m.rev, m.text]),
            [[thinking.gen, "user", "final", listening.state.turn.op, "scripted utterance"],
                [thinking.gen, "assistant", "partial", 1, "On it."],
                [thinking.gen, "assistant", "partial", 2, "On it. " + scriptedReply],
                [thinking.gen, "assistant", "final", 3, "On it. " + scriptedReply]],
            "the bubble fixture's words come from the chained engine");
        await w.closeTalk(chainedGates);
        await w.wait(m => m.state.conversation.kind === "ended" && m.state.brain.kind === "closed");
        assert.equal(w.messages.filter(m => m.type === "transcript" && m.role === "user" && m.stage === "final").length, 1,
            "short cleanup supplies no second utterance to the retained brain");
        assert.equal(fs.existsSync(path.join(chainedGates, "silent-capture")), false,
            "short cleanup releases its empty-result fixture");
    }, true, 0, "", null, hello.settings.sounds, {}, true);
    for (const [name, plant] of [["chained-scripted", null], ["chained-scripted-silent", "        caption(c, turn, sentence);\n"]]) {
        const file = daemonCopy(name);
        instrument(file, chainedGates);
        const engineFile = path.join(path.dirname(file), "ChainedEngine.js");
        chainedEngine(engineFile);
        if (plant === null) { await replyWords(file); continue; }
        const source = fs.readFileSync(engineFile, "utf8");
        assert.equal(source.split(plant).length - 1, 1, "caption producer mutation match");
        fs.writeFileSync(engineFile, source.replace(plant, ""));
        await assert.rejects(() => replyWords(file), error => error instanceof assert.AssertionError
            && error.message.startsWith("the bubble fixture's words come from the chained engine"),
        "a dropped producer must turn the bubble fixture's words red");
        controls++;
        console.log("test-jarvis-daemon: control=bubble-chained-caption killed");
    }
    // The user removes the package from a home while the service runs, and
    // no hello follows: the first request after it judges the home once,
    // holds the engine on the home Setup has to set up again, and restores
    // nothing: kendex is the package's one writer (D126).
    const renderGates = path.join(root, "render-gates");
    const renderHome = path.join(fs.realpathSync(process.env.HOME), "home-render");
    const renderRemoved = file => conversation(file, async w => {
        fs.rmSync(renderHome, { recursive: true, force: true });
        jarvisHome(renderHome, tree);
        w.raw({ ...hello, settings: { ...hello.settings, home: "~/home-render" } });
        await w.wait(m => m.state.settings.home === "~/home-render" && m.state.gate.kind === "up");
        const judged = w.messages.filter(m => m.type === "status").length;
        fs.rmSync(path.join(renderHome, ".agents"), { recursive: true });
        w.send("talk-down");
        await w.wait(m => m.phase === "listening");
        await w.holdUp();
        const down = await w.wait(m => m.state.gate.kind === "down" || m.state.fault.kind !== "none");
        assert.deepEqual([down.state.gate, down.state.fault], [{ kind: "down", reason: "unconfigured" }, { kind: "none" }],
            "the request after the package is removed holds the engine");
        await w.wait(m => m.state.conversation.kind === "ended" && m.state.brain.kind === "closed");
        const statuses = w.messages.filter(m => m.type === "status");
        assert.equal(statuses.length, judged + 1, "the request judges the home once");
        assert.equal(statuses.at(-1).causes[0], "home=not-set-up", "the home waits for Setup");
        assert.equal(fs.existsSync(path.join(renderHome, ".agents")), false, "VGS restores no package file");
    }, true, 0, "jarvis: home=not-set-up", null, hello.settings.sounds, {}, true);
    for (const [name, needle, replacement] of [["render-removed", null, null],
        ["render-removed-unjudged", 'if (error.message !== "jarvis: home=absent") throw error; }\n        rejudge();\n',
            'if (error.message !== "jarvis: home=absent") throw error; }\n']]) {
        fs.rmSync(renderGates, { recursive: true, force: true });
        const file = daemonCopy(name);
        instrument(file, renderGates);
        const engineFile = path.join(path.dirname(file), "ChainedEngine.js");
        chainedEngine(engineFile);
        if (needle === null) { await renderRemoved(file); continue; }
        const engineSource = fs.readFileSync(engineFile, "utf8");
        assert.equal(engineSource.split(needle).length - 1, 1, name + " mutation match");
        fs.writeFileSync(engineFile, engineSource.replace(needle, replacement));
        await assert.rejects(() => renderRemoved(file), error => error instanceof assert.AssertionError, name + " must turn red");
        controls++;
        console.log("test-jarvis-daemon: control=" + name + " killed");
    }

    // The shipped executor seam inside the real daemon. A disposable copy
    // changes only its brain port, which routes one media.play to the
    // playerctl stand-in and records the routing and the result.
    const desktop = path.join(process.env.JARVIS_TEST_ROOT, "desktop");
    fs.mkdirSync(desktop, { recursive: true });
    const answers = path.join(root, "desktop-answers.jsonl");
    const brainPort = "Object.assign(runner.ports, { capture: scripted.capture, brain: scripted.brain, playback: scripted.playback });";
    const routingBrain = brainPort + "\nObject.assign(runner.ports.brain, {\n"
        + "    send: e => fs.appendFileSync(" + JSON.stringify(answers) + ", JSON.stringify({ routed: router.route("
        + '{ kind: "tool-call", id: "fixture-media", tool: "media.play", arguments: {} }, { gen: e.gen, op: e.op }) }) + "\\n"),\n'
        + "    outcome: value => fs.appendFileSync(" + JSON.stringify(answers) + ', JSON.stringify(value) + "\\n") });';
    function desktopDaemon(name, edits = [], routerEdits = []) {
        const file = daemonCopy(name);
        instrument(file, gates);
        const routerFile = path.join(path.dirname(file), "ToolRouter.js");
        let router = fs.readFileSync(routerFile, "utf8");
        for (const [needle, value] of routerEdits) {
            assert.equal(router.split(needle).length - 1, 1, name + " router edit match");
            router = router.replace(needle, value);
        }
        fs.writeFileSync(routerFile, router);
        let changed = fs.readFileSync(file, "utf8");
        for (const [needle, value] of [[brainPort, routingBrain], ...edits]) {
            assert.equal(changed.split(needle).length - 1, 1, name + " desktop instrumentation match");
            changed = changed.replace(needle, value);
        }
        fs.writeFileSync(file, changed);
        return file;
    }
    const alive = pid => {
        try { process.kill(pid, 0); return true; }
        catch (error) { if (error.code === "ESRCH") return false; throw error; }
    };
    // Bounded reads of files the daemon and the stand-in write.
    async function desktopUntil(predicate, what) {
        for (let attempts = 0; attempts < 400; attempts++) {
            if (predicate()) return;
            await new Promise(resolve => setTimeout(resolve, 5));
        }
        assert.fail("desktop daemon: " + what);
    }
    async function gatedHello(file, dropMarker = false) {
        const gate = path.join(path.dirname(file), "hello-gate");
        const seen = path.join(path.dirname(file), "hello-seen");
        const prepared = cp.spawnSync("node", [path.join(tree, "scripts/fixtures/jarvis/prepare.js"),
            "--gate-daemon", file, gate, seen], { env: { PATH: process.env.PATH, HOME: process.env.HOME },
            encoding: "utf8", timeout: 3000 });
        assert.equal(prepared.status, 0, prepared.stdout + prepared.stderr);
        if (dropMarker) {
            const original = fs.readFileSync(file, "utf8");
            const needle = 'fixtureFs.appendFileSync(fixtureSeen, wire + "\\n");';
            assert.equal(original.split(needle).length - 1, 1);
            const changed = original.replace(needle, 'fixtureFs.writeFileSync(fixtureSeen, ""); if (false) ' + needle);
            assert.notEqual(changed, original);
            fs.writeFileSync(file, changed);
        }
        // Each new child must consume hello while its response gate is shut.
        for (const start of ["startup", "restart"]) {
            fs.rmSync(gate, { force: true });
            fs.rmSync(seen, { force: true });
            await conversation(file, async () => {}, true, 0, "", async ({ messages }) => {
                await desktopUntil(() => fs.existsSync(seen)
                    && (dropMarker || lines(seen).some(message => message.type === "status" && message.daemon === "ready")),
                start + " hello marker is absent");
                assert.ok(lines(seen).some(message => message.type === "status" && message.daemon === "ready"),
                    start + " consumes hello before opening the reply gate");
                assert.deepEqual(messages, [], "the closed gate delivers no response");
                fs.writeFileSync(gate, "");
            });
        }
    }
    const gated = daemonCopy("gated-hello");
    instrument(gated, path.join(path.dirname(gated), "scripted-gates"));
    await gatedHello(gated);
    const missingMarker = daemonCopy("gated-hello-marker-control");
    instrument(missingMarker, path.join(path.dirname(missingMarker), "scripted-gates"));
    // Keep hello consumption and queued replies; leave the marker empty.
    await assert.rejects(() => gatedHello(missingMarker, true),
        error => error instanceof assert.AssertionError && error.message.includes("startup consumes hello before opening the reply gate"));
    controls++;
    console.log("test-jarvis-daemon: control=gated-hello-marker killed");
    const desktopTurn = (file, modes) => {
        let held = null;
        return conversation(file, async w => {
            fs.writeFileSync(path.join(desktop, "modes.json"), JSON.stringify(modes));
            fs.writeFileSync(path.join(desktop, "calls.jsonl"), "");
            fs.rmSync(path.join(desktop, "playerctl.held"), { force: true });
            fs.rmSync(answers, { force: true });
            w.send("talk-down");
            await w.wait(m => m.phase === "listening");
            await w.holdUp();
            // The routed call can move the phase on to acting at once.
            await w.wait(m => m.state.turn.kind === "thinking");
            if (modes.playerctl?.hold) {
                await desktopUntil(() => fs.existsSync(path.join(desktop, "playerctl.held")), "the held stand-in never started");
                held = JSON.parse(fs.readFileSync(path.join(desktop, "playerctl.held"), "utf8")).pid;
            } else await desktopUntil(() => lines(answers).length === 2, "no tool result reached the brain port");
        }).then(() => held);
    };
    const routed = async file => {
        await desktopTurn(file, {});
        const written = lines(answers);
        const route = written.find(line => line.routed !== undefined);
        const result = written.find(line => line.kind === "tool-results");
        assert.equal(route?.routed.kind, "proposed", JSON.stringify(written));
        assert.equal(result.outcome, "completed");
        assert.deepEqual(result.results[0].item, { content: '{"kind":"done"}', labels: ["desktop"] });
        const [call, ...rest] = lines(path.join(desktop, "calls.jsonl"));
        assert.deepEqual(rest, []);
        assert.deepEqual([call.name, ...call.argv], ["playerctl", "play"]);
        assert.equal(call.deathsig, 9);
    };
    await routed(desktopDaemon("desktop"));
    const register = "executors = Executors.register(router, { find: commandFile, environment: process.env, clock,\n"
        + "                        desktop: { Dispatch, Launch, request: requests.send, clock,\n"
        + '                            environment: hyprctlEnvironment(), commands: ["gio"].filter(onPath) },\n'
        + "                        // The engine exists before the first turn that could route a capture.\n"
        + '                        web: { conversation: () => engine?.release.search() ?? null, audit,\n'
        + '                            cap: () => context.settings.weeklyOpenaiCap },\n'
        + '                        vision: { directory: path.join(context.directories.runtime, "vision"), state: () => runner.state,\n'
        + '                            route: () => engine.images() ? "image" : "text",\n'
        + "                            privateWindows: () => context.settings.privateWindows } });";
    await assert.rejects(() => routed(desktopDaemon("desktop-unregistered", [[register, "void Executors;"]])),
        assert.AssertionError, "a daemon that registers no executor must fail the routed call");
    controls++;
    console.log("test-jarvis-daemon: control=desktop-register killed");
    const released = async file => {
        const pid = await desktopTurn(file, { playerctl: { hold: true } });
        assert.equal(alive(pid), false, "the daemon's end releases its running command");
    };
    await released(desktopDaemon("desktop-held"));
    // Session's lease end cancels the running tool through the router.
    await assert.rejects(() => released(desktopDaemon("desktop-uncancelled", [],
        [["cancel() { if (pending !== null) pending.executor.cancel(pending.call); },", "cancel() {},"]])),
    assert.AssertionError, "a daemon whose router drops the cancel must keep its command running");
    controls++;
    console.log("test-jarvis-daemon: control=desktop-cancel killed");
    const seamDriverRoot = path.join(root, "desktop-seam-driver");
    const driverDaemon = daemonCopy("desktop-seam-driver");
    instrument(driverDaemon, gates);
    instrumentDesktop(driverDaemon, seamDriverRoot);
    const seamDriver = async write => {
        for (const [tool, arguments_, kind, content] of [
            ["windows.focus", { window: "0xa1" }, "compositor.focusWindow", /Read back: window 0xa1 has the focus/]
        ]) {
            desk.reset();
            fs.rmSync(path.join(seamDriverRoot, "results.jsonl"), { force: true });
            await conversation(driverDaemon, async w => {
                await write(seamDriverRoot, { id: "driver-" + tool, tool, arguments: arguments_ }, w);
                await desktopUntil(() => w.messages.some(message => message.type === "request"), "the driver sent no desktop request");
                const request = w.messages.find(message => message.type === "request");
                assert.equal(request.kind, kind);
                w.reply(desk.serve(Protocol, request));
                await desktopUntil(() => lines(path.join(seamDriverRoot, "results.jsonl")).some(result => result.outcome !== undefined),
                    "the driver received no desktop result");
                const result = lines(path.join(seamDriverRoot, "results.jsonl")).find(value => value.outcome !== undefined);
                assert.equal(result.outcome, "completed");
                assert.match(result.content, content);
            });
        }
    };
    await seamDriver(writeCall);
    // A call written in place, in two parts, is read half written: the
    // driver's parse throws and the daemon ends before any request.
    const writeInParts = async (directory, call, w) => {
        const file = path.join(directory, "call.json");
        const text = JSON.stringify(call);
        fs.writeFileSync(file, text.slice(0, text.length >> 1));
        for (let attempts = 0; attempts < 400 && alive(w.pid); attempts++) await new Promise(resolve => setTimeout(resolve, 5));
        fs.appendFileSync(file, text.slice(text.length >> 1));
    };
    await assert.rejects(() => seamDriver(writeInParts),
        error => error instanceof assert.AssertionError && error.message.includes("the driver sent no desktop request"),
        "a call.json the driver can see half written must fail the desktop-driver case");
    fs.rmSync(path.join(seamDriverRoot, "call.json"), { force: true });
    controls++;
    console.log("test-jarvis-daemon: control=desktop-driver-partial-call killed");
    async function blockedReader(file) {
        fs.writeFileSync(path.join(process.env.HOME, "audio-flood"), "");
        const child = cp.spawn("node", [file, "--tree", tree], {
            env: { PATH: process.env.PATH, HOME: process.env.HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR },
            stdio: ["pipe", "pipe", "pipe"]
        });
        let err = "";
        child.stderr.on("data", data => { err += data; });
        child.stdin.on("error", error => { if (error.code !== "EPIPE") throw error; });
        const exited = once(child, "exit");
        const timeout = setTimeout(() => child.kill("SIGKILL"), 5000);
        try {
            child.stdin.write(JSON.stringify(hello) + "\n");
            // Deliberately leave stdout unread. Discovery must not grow its
            // outgoing queue without a bound while the lease remains open.
            const [code, signal] = await exited;
            assert.equal(signal, null, "blocked stdout must fault without waiting for EOF: " + err);
            assert.equal(code, 74);
            assert.equal(err.trim(), "jarvis: stdout=overflow");
        } finally {
            clearTimeout(timeout);
            child.stdout.destroy();
            child.stdin.destroy();
            if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
            fs.unlinkSync(path.join(process.env.HOME, "audio-flood"));
        }
    }
    await blockedReader(daemon);
    await control("outgoing-bound",
        'if (process.stdout.writableLength + Buffer.byteLength(wire + "\\n") > Protocol.MAX_LINE_BYTES)',
        'if (false && process.stdout.writableLength + Buffer.byteLength(wire + "\\n") > Protocol.MAX_LINE_BYTES)',
        blockedReader);

    // Task control end to end: a record and a real task-run.py group made
    // here, no profile row. Startup observation writes lost for a group that
    // is gone; a task-stop intent stops a live group and answers stopped.
    const taskEnv = { PATH: process.env.PATH, HOME: process.env.HOME, LANG: "C.UTF-8" };
    const producer = (id, kind, data) => {
        const result = cp.spawnSync("node", [engine, "--state", hello.directories.state, id, kind],
            { env: taskEnv, input: JSON.stringify(data), encoding: "utf8", timeout: 10000 });
        assert.equal(result.status, 0, result.stderr);
    };
    let taskCount = 0;
    async function taskGroup() {
        const id = "control-" + (++taskCount);
        producer(id, "create", { goal: "Daemon fixture", cwd: process.env.HOME, agent: "fixture", account: "" });
        const spec = path.join(root, id + ".json");
        fs.writeFileSync(spec, JSON.stringify({ v: 1, id, state: hello.directories.state, engine,
            cwd: process.env.HOME, argv: ["sleep", "30"], env: taskEnv }), { mode: 0o600 });
        // A terminal runs the launcher in a session of its own.
        const launcher = cp.spawn("python3", [path.join(path.dirname(daemon), "task-run.py"), "--spec", spec],
            { env: taskEnv, stdio: "ignore", detached: true });
        const closed = once(launcher, "close");
        for (let attempts = 0; taskStore.read(id).process.kind !== "alive"; attempts++) {
            assert.ok(attempts < 500, "task-run records started");
            await new Promise(resolve => setTimeout(resolve, 10)); // Bounded: exec and the producer's lock.
        }
        return { id, pgid: taskStore.read(id).identity.pgid, closed, launcher };
    }
    const until = async (label, predicate) => {
        for (let attempts = 0; !predicate(); attempts++) {
            assert.ok(attempts < 400, label);
            await new Promise(resolve => setTimeout(resolve, 10)); // Bounded: the daemon's own child writes.
        }
    };
    const Relay = require(path.join(path.dirname(daemon), "TaskRelay.js"));
    async function lockedTaskAnswer(file) {
        const task = await taskGroup();
        const directory = path.join(hello.directories.runtime, "prompts");
        const prompt = Relay.ask(directory, task.id, { kind: "permission", tool: "Bash", text: "Bash {}" }, Date.now(), 600000);
        const answerFile = path.join(directory, task.id + "." + prompt.id + ".answer.json");
        try {
            await conversation(file, async w => {
                await until("the daemon publishes the held permission", () => w.messages.some(message =>
                    message.type === "task-prompts" && message.prompts.some(item => item.id === prompt.id)));
                w.raw({ ...hello, locked: true });
                await w.wait(message => message.state.gate.reason === "locked");
                w.raw({ v: 1, type: "intent", gen: w.last().gen, revision: hello.revision,
                    intent: "task-respond", task: task.id, prompt: prompt.id, answer: { v: 1, kind: "allow" } });
                await until("locked task response", () => w.messages.some(message => message.type === "task-response"));
                assert.deepEqual(w.messages.filter(message => message.type === "task-response")
                    .map(message => [message.task, message.prompt, message.answer]), [[task.id, prompt.id, "session-locked"]]);
                assert.equal(fs.existsSync(answerFile), false, "a locked answer leaves no answer file");
                assert.ok(Relay.pending(directory, Date.now()).some(item => item.id === prompt.id));
            });
            assert.doesNotThrow(() => process.kill(-task.pgid, 0), "daemon teardown preserves the live task");
            assert.ok(Relay.pending(directory, Date.now()).some(item => item.id === prompt.id));
            assert.equal(fs.existsSync(answerFile), false);
        } finally {
            if (task.launcher.exitCode === null) {
                try { process.kill(-task.pgid, "SIGKILL"); } catch (error) { if (error.code !== "ESRCH") throw error; }
            }
            await task.closed;
            Relay.withdrawTask(directory, task.id);
        }
    }
    await lockedTaskAnswer(daemon);
    await control("locked-task-answer", 'const answer = context.locked ? "session-locked"',
        'const answer = false && context.locked ? "session-locked"', lockedTaskAnswer);
    async function goneGroup() {
        const id = "control-" + (++taskCount);
        const gone = cp.spawn("true", [], { detached: true, stdio: "ignore" });
        const stat = fs.readFileSync("/proc/" + gone.pid + "/stat", "utf8").split(") ")[1].split(" ");
        await once(gone, "exit");
        producer(id, "create", { goal: "Daemon fixture", cwd: process.env.HOME, agent: "fixture", account: "" });
        producer(id, "started", { pid: gone.pid, pgid: Number(stat[2]), sid: Number(stat[3]), startTime: stat[19] });
        return id;
    }
    const startupLost = async file => {
        const id = await goneGroup();
        const observed = path.join(path.dirname(file), "startup-observed");
        const original = fs.readFileSync(file, "utf8");
        const calls = original.match(/if \(first\) void (tasks\.observe\(\)|Promise\.resolve\(\));/g);
        assert.equal(calls?.length, 1);
        const changed = original.replace(calls[0], calls[0].slice(0, -1)
            + '.then(() => require("node:fs").writeFileSync(' + JSON.stringify(observed) + ', ""));');
        assert.notEqual(changed, original);
        fs.writeFileSync(file, changed);
        await conversation(file, async () => {
            await until("startup observation completes", () => fs.existsSync(observed));
            assert.equal(taskStore.read(id).process.kind, "lost", "startup observation writes lost");
        });
    };
    await startupLost(daemonCopy("startup-observation"));
    await control("startup-observation", "if (first) void tasks.observe();", "if (first) void Promise.resolve();", startupLost);
    const stopIntent = async file => {
        const task = await taskGroup();
        try {
            await conversation(file, async w => {
                await until("the live task is counted", () => w.messages.some(m => m.type === "tasks" && m.count === 1));
                await until("the task list includes the live task", () => w.messages.some(message => message.type === "task-list"
                    && message.rows.some(row => row.id === task.id && row.state === "working")));
                w.raw({ v: 1, type: "intent", gen: 1, revision: hello.revision, intent: "task-stop", task: task.id });
                await until("task-answer", () => w.messages.some(m => m.type === "task-answer"));
                assert.deepEqual(w.messages.filter(m => m.type === "task-answer").map(m => [m.task, m.answer]), [[task.id, "stopped"]]);
                assert.throws(() => process.kill(-task.pgid, 0), { code: "ESRCH" });
                assert.equal(taskStore.read(task.id).state, "stopped");
                await until("the count returns to zero", () => w.messages.filter(m => m.type === "tasks").at(-1).count === 0);
                await until("the task list publishes the stopped task", () => w.messages.filter(message => message.type === "task-list")
                    .at(-1)?.rows.some(row => row.id === task.id && row.state === "stopped"));
            });
            await task.closed;
        } finally { if (task.launcher.exitCode === null) process.kill(-task.pgid, "SIGKILL"); }
    };
    await stopIntent(daemon);
    await control("task-stop-intent", "void tasks.stop(task).then(answer => {", "void Promise.resolve(\"stopped\").then(answer => {", stopIntent);
    await control("task-update-list", "signature !== publishedTasks", "publishedTasks === null", stopIntent);
    // With no conversation open, a held prompt and a task's end reach the
    // user as notifications the daemon runs itself: the notify-send
    // stand-in records the argv, the parent-death signal and an environment
    // holding only what the command reads.
    const voiceNotify = async file => {
        fs.writeFileSync(path.join(desktop, "modes.json"), "{}");
        fs.writeFileSync(path.join(desktop, "calls.jsonl"), "");
        const notified = () => lines(path.join(desktop, "calls.jsonl")).filter(call => call.name === "notify-send");
        const task = await taskGroup();
        const directory = path.join(hello.directories.runtime, "prompts");
        Relay.ask(directory, task.id, { kind: "permission", tool: "Bash", text: "Run the tests" }, Date.now(), 600000);
        try {
            await conversation(file, async w => {
                await until("the held prompt is notified", () => notified().length === 1);
                assert.equal(w.last().state.conversation.kind, "ended");
                w.raw({ v: 1, type: "intent", gen: 1, revision: hello.revision, intent: "task-stop", task: task.id });
                await until("the stopped task is notified", () => notified().length === 2);
            });
            await task.closed;
            const calls = notified();
            assert.deepEqual(calls.map(call => call.argv), [
                ["--app-name=Jarvis", "--", "Coding task", "The coding agent asks to use Bash: Run the tests. Talk to Jarvis to answer."],
                ["--app-name=Jarvis", "--", "Coding task", "The coding task was stopped."]]);
            for (const call of calls) {
                assert.deepEqual(Object.keys(call.env).sort(), ["LC_ALL", "PATH", "XDG_RUNTIME_DIR"], "only what notify-send reads");
                assert.equal(call.deathsig, 9);
            }
        } finally {
            if (task.launcher.exitCode === null) {
                try { process.kill(-task.pgid, "SIGKILL"); } catch (error) { if (error.code !== "ESRCH") throw error; }
            }
            await task.closed;
            Relay.withdrawTask(directory, task.id);
        }
    };
    await voiceNotify(daemon);
    await control("voice-prompts", "                            voice.prompts(prompts);\n", "", voiceNotify);
    await control("voice-views", "                            voice.observe(views);\n", "", voiceNotify);
    // Without local setup the installed daemon stays unconfigured. A
    // disposable copy adds the scripted row and indicator, then drives
    // phases with the selected model the local fixture catalog offers.
    const Engine = require("./fixtures/jarvis/engine.js");
    // said is the scripted utterance; recipients, when given, the speech row's.
    // extra plants one defect each in the copy's engine.
    function engineCopy(name, said = "What time is it?", recipients = null, extra = []) {
        const file = daemonCopy(name);
        const directory = path.dirname(path.dirname(file));
        const utterances = "[fixture.utterance(" + JSON.stringify(said) + ")]";
        for (const [relative, needle, replacement] of [...extra.map(([needle, replacement]) =>
            ["backend/ChainedEngine.js", needle, replacement]),
            ["backend/ChainedEngine.js", "const SPEECH = Object.freeze({ local: LocalSpeech.row });",
                "const SPEECH = Object.freeze({ scripted: (fixture => (fixture.reset({ utterances: " + utterances
                + (recipients === null ? "" : ", recipients: " + JSON.stringify(recipients)) + " }), fixture.row))(require("
                + JSON.stringify(require.resolve("./fixtures/jarvis/engine.js")) + ")) });"],
            ["backend/jarvisd.js", 'runner.dispatch({ type: "snapshot", locked: context.locked,',
                'if (runner.state.indicator.kind !== "shown") runner.dispatch({ type: "indicator", gen: runner.state.gen, shown: true, bar: "gone" });\n                runner.dispatch({ type: "snapshot", locked: context.locked,']]) {
            const target = path.join(directory, relative);
            const original = fs.readFileSync(target, "utf8");
            assert.equal(original.split(needle).length - 1, 1, name + " engine instrumentation");
            fs.writeFileSync(target, original.replace(needle, replacement));
        }
        return file;
    }
    require(path.join(tree, "shell/plugins/vgs.jarvis/backend/Core.js")).use(tree);
    const { Accounts } = require(path.join(tree, "shell/plugins/vgs.jarvis/backend/Accounts.js"));
    const { PROVIDERS } = require(path.join(tree, "shell/plugins/vgs.jarvis/AccountProviders.js"));
    // The real daemon's composition must carry the engine's model notice to
    // stdout. Adapter and consumer tests alone cannot prove that connection.
    async function modelFallback(file) {
        const standins = path.join(process.env.JARVIS_TEST_ROOT, "standins");
        const command = path.join(standins, "claude");
        const account = path.join(process.env.HOME, ".claude-model-notice");
        fs.mkdirSync(account);
        fs.copyFileSync(path.join(tree, "scripts/fixtures/jarvis-claude/claude"), command);
        fs.chmodSync(command, 0o700);
        const saved = "claude-opus-5.5";
        const refused = [{ raw: JSON.stringify({ type: "assistant", parent_tool_use_id: null, error: "model_not_found",
            message: { id: "refused", role: "assistant", content: [] } }) }, { result: "api-error" }];
        fs.writeFileSync(path.join(account, "script.json"), JSON.stringify({ tree,
            turns: [[{ text: "Answered." }, { result: "success" }]], modelTurns: { [saved]: [refused] } }));
        try {
            const chosen = new Accounts(hello.directories.state, process.env).discover()
                .find(row => row.source.kind === "cli" && row.source.directory === account);
            assert.equal(chosen?.state.kind, "signed-in", "scratch Claude account is discovered through its stand-in");
            await conversation(file, async w => {
                w.send("talk-down");
                await w.wait(m => m.phase === "listening");
                await w.holdUp();
                await w.wait(m => m.phase === "idle" && m.state.turn.kind === "none"
                    && w.messages.some(frame => frame.type === "transcript" && frame.role === "assistant"
                        && frame.stage === "final" && frame.text.endsWith(" Answered.")));
                assert.equal(w.last().state.settings.model, saved, "the daemon retains the exact saved choice");
                const notices = w.messages.filter(frame => frame.type === "model-fallback");
                assert.deepEqual(notices, [{ v: 1, type: "model-fallback", gen: w.last().gen,
                    revision: hello.revision, saved, used: "claude-fable-5-1" }], "the engine publishes one fallback notice on the daemon wire");
                const Protocol = require("../bin/lib/qml-library.js").load(path.join(tree, "shell/plugins/vgs.jarvis/JarvisProtocol.js"));
                assert.deepEqual(JSON.parse(JSON.stringify(Protocol.accept(JSON.stringify(notices[0]), "daemon"))), notices[0]);
            }, true, 0, "", null, false, { brain: chosen.id, model: saved });
        } finally {
            fs.rmSync(command);
            fs.rmSync(account, { recursive: true });
        }
    }
    const noticeDaemon = engineCopy("model-fallback-wire");
    await modelFallback(noticeDaemon);
    const wrongFactory = engineCopy("model-fallback-wrong-factory");
    const noticeWriter = '                        modelUsed: choice => write({ v: 1, type: "model-fallback", gen: runner.state.gen, revision: context.revision, ...choice }),\n';
    const wrongSource = fs.readFileSync(wrongFactory, "utf8");
    const memoryNotify = '                        notify: entries => writeMemoryInbox(entries) });';
    assert.equal(wrongSource.split(noticeWriter).length - 1, 1);
    assert.equal(wrongSource.split(memoryNotify).length - 1, 1);
    const misplaced = wrongSource.replace(noticeWriter, "").replace(memoryNotify, noticeWriter + memoryNotify);
    assert.notEqual(misplaced, wrongSource);
    fs.writeFileSync(wrongFactory, misplaced);
    await assert.rejects(() => modelFallback(wrongFactory), error => error instanceof assert.AssertionError
        && error.message.startsWith("the engine publishes one fallback notice on the daemon wire"), "a writer on Memory.install must lose the wire notice");
    controls++;
    console.log("test-jarvis-daemon: control=model-fallback-wrong-factory detected");
    const ollama = PROVIDERS.find(row => row.id === "ollama");
    const brainId = new Accounts(hello.directories.state, { HOME: process.env.HOME })
        .account(ollama, "local", { kind: "found" }, { kind: "local", origin: ollama.origin }).id;
    const loopback = Engine.brain(11434);
    await loopback.ready;
    // The daemon carries cloudVision to Policy and privateWindows to the
    // vision executor. A network speech row makes the recipient set
    // non-offline, so the loopback brain receives screen content only as
    // cloudVision allows. grim and magick are vision-tool.py, which draws the
    // stand-in hyprctl's windows and runs the host's ImageMagick.
    const VisionWorld = require("./fixtures/jarvis/vision.js");
    const hostMagick = ["/usr/bin/magick", "/bin/magick"].find(file => fs.existsSync(file));
    let notMeasured = false;
    const SCREEN_SPEECH = [{ kind: "network", provider: "scripted-voice", account: "fixture", origin: "http://192.0.2.1:9" }];
    const SECRET = [200, 40, 40], VAULT = [40, 40, 200];
    function screenCopy(name, edits = []) {
        const file = engineCopy(name, "Look at my screen.", SCREEN_SPEECH);
        const registered = path.join(path.dirname(file), "vision-registered");
        for (const [target, needle, replacement] of [[path.join(path.dirname(file), "ToolRouter.js"), "function register(id, executor) {",
            "function register(id, executor) {\n        if (id === \"vision\") require(\"node:fs\").writeFileSync(" + JSON.stringify(registered) + ", \"\");"],
        ...edits.map(([needle, replacement]) => [file, needle, replacement])]) {
            const original = fs.readFileSync(target, "utf8");
            assert.equal(original.split(needle).length - 1, 1, name + " screen instrumentation");
            fs.writeFileSync(target, original.replace(needle, replacement));
        }
        return { file, registered };
    }
    async function screenConversation({ file, registered }, settings) {
        const clock = holdClock(file);
        const screen = VisionWorld.world(process.env.XDG_RUNTIME_DIR, process.env.JARVIS_TEST_ROOT);
        screen.set({ monitors: [VisionWorld.monitor(0, "FIX-1", { width: 320, height: 200, scale: 1 })],
            outputs: [{ name: "FIX-1", box: [0, 0, 320, 200] }],
            clients: [VisionWorld.client("0xa1", { class: "Fixture-Secret", initialClass: "Fixture-Secret", at: [20, 30], size: [100, 50] }),
                VisionWorld.client("0xc3", { class: "Bitwarden", initialClass: "Bitwarden", title: "Vault", initialTitle: "Vault",
                    at: [150, 40], size: [100, 80] })],
            colors: { "0xa1": SECRET, "0xc3": VAULT } });
        const child = cp.spawn("node", [file, "--tree", tree], { env: {
            PATH: process.env.PATH, HOME: process.env.HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR
        }, stdio: ["pipe", "pipe", "pipe"] });
        const states = [];
        let tail = "", err = "";
        child.stdout.on("data", data => {
            const lines = (tail + data).split("\n");
            tail = lines.pop();
            for (const message of lines.map(line => JSON.parse(line))) if (message.type === "state") states.push(message);
        });
        child.stderr.on("data", data => { err += data; });
        child.stdin.on("error", error => { if (error.code !== "EPIPE") throw error; });
        const closed = once(child, "close");
        const send = message => child.stdin.write(JSON.stringify(message) + "\n");
        // Bounded polls of the daemon's own messages and files, not latencies.
        const wait = async (predicate, label) => {
            for (let attempts = 0; attempts < 1000 && child.exitCode === null; attempts++) {
                if (predicate(states.at(-1))) return;
                await new Promise(resolve => setTimeout(resolve, 5));
            }
            assert.fail((typeof label === "function" ? label() : label) + ": " + JSON.stringify(states.at(-1)?.state) + " stderr=" + err);
        };
        try {
            const before = loopback.requests.length;
            // A control's unconsumed reply never answers this conversation.
            loopback.replies.splice(0);
            loopback.replies.push(Engine.calls({ id: "call_screen", name: "vision_screen", arguments: {} }), Engine.text("I see it."));
            send({ ...hello, settings: { ...hello.settings, brain: brainId, model: "fixture-model", ...settings } });
            await wait(m => m?.state.gate.kind === "up", "the engine raises the gate");
            await wait(() => fs.existsSync(registered), "vision registers after the Hyprland probe");
            send(intent("talk-down"));
            await wait(m => m.phase === "listening", "listening");
            releaseHeld(clock, states.at(-1).state, () => send(intent("talk-up")));
            await wait(m => loopback.requests.length === before + 2 && m.phase === "idle" && m.state.turn.kind === "none",
                () => "the screen result reaches the brain, requests=" + (loopback.requests.length - before) + " last="
                + JSON.stringify(loopback.requests.at(-1)?.body.messages.slice(1)).slice(0, 600));
            child.stdin.end();
            const [code] = await closed;
            assert.equal(code, 0, err);
            cases++;
            return { body: loopback.requests.at(-1).body, magick: screen.calls().filter(call => call.name === "magick") };
        } finally { if (child.exitCode === null) { child.kill("SIGKILL"); await closed; } }
    }
    // The user message right after the tool message holds the image or its marker.
    const pictured = body => body.messages[body.messages.findLastIndex(message => message.role === "tool") + 1].content;
    async function screenNever(copy) {
        const { body, magick } = await screenConversation(copy, { cloudVision: "never", privateWindows: "fixture-secret" });
        assert.equal(body.messages.find(message => message.role === "tool").content, "[withheld: screen content]");
        assert.deepEqual(pictured(body), [{ type: "text", text: "Image from tool call call_screen:" },
            { type: "text", text: "[withheld: screen content]" }], "never withholds the image from a non-offline set");
        assert.equal(JSON.stringify(body).includes("data:image/png"), false);
        assert.equal(magick.length, 1, "the setting's pattern is painted");
        assert.deepEqual(magick[0].argv.slice(1, -1), ["+antialias", "-fill", "black", "-draw", "rectangle 20,30 119,79"],
            "only the setting's window is painted, not the shipped list's");
    }
    async function screenSettings() {
        const standins = path.join(process.env.JARVIS_TEST_ROOT, "standins");
        for (const name of ["grim", "magick"]) {
            fs.copyFileSync(path.join(tree, "scripts/fixtures/jarvis/vision-tool.py"), path.join(standins, name));
            fs.chmodSync(path.join(standins, name), 0o700);
        }
        try {
            await screenNever(screenCopy("screen-never"));
            const { body } = await screenConversation(screenCopy("screen-allow"), { cloudVision: "allow", privateWindows: "fixture-secret" });
            const part = pictured(body).at(-1);
            assert.equal(part.type, "image_url", "allow sends the image");
            const image = VisionWorld.decode(Buffer.from(part.image_url.url.slice("data:image/png;base64,".length), "base64"));
            assert.deepEqual([image.pixel(20, 30), image.pixel(119, 79)], [[0, 0, 0, 255], [0, 0, 0, 255]], "the setting's window is painted");
            assert.deepEqual(image.pixel(160, 50), [...VAULT, 255], "a window the setting does not name is not");
            for (const [name, needle, replacement] of [
                ["cloud-vision-setting", "cloudVision: context.settings.cloudVision })", "cloudVision: \"allow\" })"],
                ["private-windows-setting", "privateWindows: () => context.settings.privateWindows }", "privateWindows: () => \"\" }"]]) {
                await assert.rejects(() => screenNever(screenCopy("screen-" + name, [[needle, replacement]])), assert.AssertionError, name);
                controls++;
                console.log("test-jarvis-daemon: control=" + name + " killed");
            }
        } finally { for (const name of ["grim", "magick"]) fs.rmSync(path.join(standins, name), { force: true }); }
    }
    async function engineConversation(file, said = "What time is it?", caption = said, identicalHello = false, pressAt = null) {
        const clock = holdClock(file, pressAt !== null);
        if (pressAt !== null) fs.writeFileSync(clock, String(pressAt));
        const child = cp.spawn("node", [file, "--tree", tree], { env: {
            PATH: process.env.PATH, HOME: process.env.HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR
        }, stdio: ["pipe", "pipe", "pipe"] });
        const states = [], captions = [], statuses = [], statusStates = [];
        let tail = "", err = "";
        child.stdout.on("data", data => {
            const lines = (tail + data).split("\n");
            tail = lines.pop();
            for (const message of lines.map(line => JSON.parse(line))) {
                if (message.type === "status") { statuses.push(message); statusStates.push(states.length); }
                if (message.type === "state") states.push(message);
                if (message.type === "transcript") captions.push(message);
            }
        });
        child.stderr.on("data", data => { err += data; });
        child.stdin.on("error", error => { if (error.code !== "EPIPE") throw error; });
        const closed = once(child, "close");
        const send = message => child.stdin.write(JSON.stringify(message) + "\n");
        let releaseReply = () => {};
        const heldReply = identicalHello ? new Promise(resolve => { releaseReply = resolve; }) : null;
        // Real capture, a loopback request and paced playback cross pipes.
        const wait = async (predicate, label) => {
            for (let attempts = 0; attempts < 1000 && child.exitCode === null; attempts++) {
                if (states.length && predicate(states.at(-1))) return;
                await new Promise(resolve => setTimeout(resolve, 5));
            }
            assert.fail(label + ": " + JSON.stringify(states.at(-1)?.state) + " stderr=" + err);
        };
        try {
            const before = loopback.requests.length;
            const reply = Engine.text("It is noon. ", "The sun is high.");
            if (identicalHello) reply.splice(1, 0, { wait: heldReply });
            loopback.replies.push(reply);
            const snapshot = { ...hello, settings: { ...hello.settings, brain: brainId, model: "fixture-model" } };
            send(snapshot);
            await wait(m => m.state.gate.kind === "up", "the selected catalog model admits the engine");
            assert.equal(states.at(-1).state.gate.kind, "up", "the engine raises the gate: " + JSON.stringify(states.at(-1).state.gate));
            assert.deepEqual(statuses.at(-1).causes, [], "a ready engine publishes no setup cause");
            send(intent("talk-down"));
            await wait(m => m.phase === "listening", "listening");
            const collectionOp = states.at(-1).state.turn.op;
            releaseHeld(clock, states.at(-1).state, () => send(intent("talk-up")));
            if (identicalHello) {
                await wait(m => m.phase === "thinking" && loopback.requests.length === before + 1,
                    "the real local turn is active before the unchanged hello");
                const conversation = structuredClone(states.at(-1).state.conversation);
                const generation = states.at(-1).state.gen;
                const statusAt = statuses.length, catalogs = loopback.catalogs.length;
                send(snapshot);
                // configured publishes status before its snapshot. Read that
                // snapshot, not an earlier playback or fixture indicator frame.
                await wait(() => statuses.length > statusAt && states.length > statusStates[statusAt], "the unchanged hello answers");
                const answer = states[statusStates[statusAt]].state;
                assert.deepEqual(answer.conversation, conversation, "an unchanged hello keeps the active local conversation");
                assert.equal(answer.gen, generation, "an unchanged hello keeps its generation");
                assert.equal(answer.gate.kind, "up");
                assert.equal(loopback.catalogs.length, catalogs, "an admitted unchanged selection needs no new catalog operation");
                releaseReply();
            }
            await wait(m => m.phase === "idle" && m.state.conversation.kind !== "ended" && m.state.turn.kind === "none"
                && states.some(state => state.phase === "speaking"), "speech completes");
            const phases = states.map(state => state.phase).filter((phase, index, all) => phase !== all[index - 1]);
            const order = ["listening", "thinking", "speaking", "idle"].map(phase => phases.lastIndexOf(phase));
            assert.deepEqual(order.slice().sort((a, b) => a - b), order, "phases advance in order: " + phases.join(","));
            assert.equal(loopback.requests.length, before + 1);
            assert.deepEqual(loopback.requests.at(-1).body.messages.filter(message => message.role === "user")
                .map(message => message.content), [said], "the original final reaches the loopback brain");
            const gen = states.at(-1).state.gen;
            const userCaption = captions.find(message => message.role === "user");
            assert.equal(userCaption?.text, caption, "the user final caption keeps the sanitized tail");
            assert.equal(JSON.stringify(Protocol.accept(JSON.stringify(userCaption), "daemon")), JSON.stringify(userCaption),
                "the user final is accepted by the shell transcript judge");
            // The acknowledgement opens the reply's caption; its words come
            // from the transcript, so the row names it by its place.
            const ack = captions[1]?.text ?? "";
            assert.ok(ack !== "" && !ack.includes("noon"), "the acknowledgement is captioned first");
            assert.deepEqual(captions.map(m => [m.gen, m.role, m.stage, m.rev, m.text]), [
                [gen, "user", "final", collectionOp, caption],
                [gen, "assistant", "partial", 1, ack],
                [gen, "assistant", "partial", 2, ack + " It is noon."],
                [gen, "assistant", "partial", 3, ack + " It is noon. The sun is high."],
                [gen, "assistant", "final", 4, ack + " It is noon. The sun is high."]], "the chained reply's words reach the wire in order, final last");
            if (identicalHello) {
                loopback.replies.push(Engine.text("The follow-up is complete."));
                send({ ...intent("say"), text: "Follow up." });
                await wait(() => loopback.requests.length === before + 2 && loopback.requests.at(-1).body !== null,
                    "the next request keeps the earlier conversation history");
                const history = loopback.requests.at(-1).body.messages;
                assert.deepEqual(history.filter(message => message.role === "user").map(message => message.content), [said, "Follow up."]);
                assert.ok(history.some(message => message.role === "assistant" && message.content?.includes("It is noon.")));
                await wait(m => m.phase === "idle" && m.state.turn.kind === "none", "the follow-up completes");
            }
            child.stdin.end();
            const [code] = await closed;
            assert.equal(code, 0, err);
            cases++;
        } finally { releaseReply(); if (child.exitCode === null) { child.kill("SIGKILL"); await closed; } }
    }
    try {
        // Speech.transcribe joins recognizer text without the shell caption's
        // character or length rules. The brain keeps that original final.
        const tail = "x".repeat(Protocol.TRANSCRIPT_CHARS);
        const finals = [
            ["ordinary-integer", "What time is it?", "What time is it?", 1024],
            ["ordinary-fractional", "What time is it?", "What time is it?", 1023.9999999999997],
            ["multiline-integer", "What time\nis it?\tPlease tell me.\u0000", "What time is it? Please tell me. ", 1024],
            ["multiline-fractional", "What time\nis it?\tPlease tell me.\u0000", "What time is it? Please tell me. ", 1023.9999999999997],
            ["oversized", "Dropped prefix. " + tail, tail, null]
        ];
        for (const [name, said, caption, pressAt] of finals) {
            await engineConversation(engineCopy("engine-" + name, said), said, caption, false, pressAt);
            console.log("test-jarvis-daemon: caption=" + name + " passed");
        }
        await engineConversation(engineCopy("engine-identical-hello"), "What time is it?", "What time is it?", true);
        await assert.rejects(() => engineConversation(engineCopy("engine-clears-identical-hello", "What time is it?", null,
            [["if (identity !== modelsFor || modelsHeld()) cancelModels();",
                "if (identity !== modelsFor || modelsHeld() || conversation !== null) cancelModels();"]]),
            "What time is it?", "What time is it?", true),
        error => error instanceof assert.AssertionError && error.operator === "deepStrictEqual"
            && error.actual?.kind === "ended" && error.expected?.kind === "active",
        "an unnecessary invalidation must fail the active conversation assertion");
        controls++;
        console.log("test-jarvis-daemon: control=identical-hello-conversation killed");
        await assert.rejects(() => engineConversation(engineCopy("engine-no-caption", "What time is it?", null,
            [["        caption(c, turn, sentence);\n", ""]])),
        error => error instanceof assert.AssertionError && error.message.startsWith("the chained reply's words reach the wire"),
        "a dropped caption producer must turn the caption assertion red");
        controls++;
        console.log("test-jarvis-daemon: control=chained-caption killed");
        await assert.rejects(() => engineConversation(engineCopy("engine-catalog-audit", "What time is it?", null,
            [["account.readOffers(id, read.stop.signal, audit)", "account.readOffers(id, read.stop.signal)"]])),
        error => error instanceof assert.AssertionError && error.message.includes("audit=writer-owned"),
        "a second catalog audit writer must fail the real daemon's admission");
        controls++;
        console.log("test-jarvis-daemon: control=catalog-shared-audit killed");
        const unconfigured = engineCopy("engine-stock-speech");
        const stockEngine = path.join(path.dirname(unconfigured), "ChainedEngine.js");
        fs.copyFileSync(path.join(tree, "shell/plugins/vgs.jarvis/backend/ChainedEngine.js"), stockEngine);
        await assert.rejects(() => engineConversation(unconfigured), assert.AssertionError,
            "the stock speech table keeps the daemon unconfigured");
        controls++;
        if (hostMagick === undefined) {
            console.log("test-jarvis-daemon: screen=not-measured missing=magick");
            notMeasured = true;
        } else await screenSettings();
        assert.deepEqual(loopback.faults, []);
    } finally { await loopback.close(); }
    console.log("test-jarvis-daemon: ok cases=" + cases + " controls=" + controls);
    // A row that could not run is not a pass.
    if (notMeasured) process.exitCode = 77;
}

async function main() {
    if (process.argv[2] === "--inside") return inside();
    const parent = os.tmpdir();
    fs.mkdirSync(parent, { recursive: true });
    const root = fs.mkdtempSync(path.join(parent, "jd-"));
    try {
        // The export copies this tree's suite inputs and a read outside them
        // fails there, so its run is the one run of every case and control;
        // freshSuite fails with that run's output when a case fails.
        const launcher = path.join(tree, "scripts/lib/jarvis-env.sh");
        const env = { PATH: "/usr/bin:/bin", HOME: root, JARVIS_TEST_SCRATCH_ROOT: os.tmpdir() };
        if (process.argv[2] !== "--fresh") {
            // Here, not in the export's run, so the row prints the control's line.
            fs.mkdirSync(path.join(root, "hung"));
            hungWorldControl(launcher, path.join(root, "hung"), env);
            freshSuite(tree, "daemon", root);
            console.log("test-jarvis-daemon: mapped-indicator-close passed");
            return;
        }
        standins(path.join(root, "standins"));
        desktopFixture.standins(path.join(root, "standins"));
        for (const name of ["playerctl", "notify-send"]) {
            fs.copyFileSync(path.join(tree, "scripts/fixtures/jarvis/desktop-tool.py"), path.join(root, "standins", name));
            fs.chmodSync(path.join(root, "standins", name), 0o700);
        }
        const result = runBounded("/bin/bash", [launcher, path.join(root, "standins"), "--", "node", __filename, "--inside"], { env });
        if (result.error) throw result.error;
        assert.equal(result.signal, null);
        process.exitCode = result.status;
    } finally { fs.rmSync(root, { recursive: true, force: true }); }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
