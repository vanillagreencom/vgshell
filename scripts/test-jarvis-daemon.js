#!/usr/bin/env node
// Synthetic fixture from JarvisProtocol.js, 2026-09-30. All daemon
// cases and controls run in J09's private network/PID world.
"use strict";
const assert = require("node:assert/strict");
const cp = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const { once } = require("node:events");
const { freshSuite, shellState } = require("./fixtures/jarvis/prepare.js");
const { runBounded, hungWorldControl } = require("./fixtures/jarvis/bounded.js");
const { instrument, chainedEngine } = require("./fixtures/jarvis/scripted.js");
const { standins } = require("./fixtures/jarvis/audio.js");
const desktopFixture = require("./fixtures/jarvis/desktop.js");
const { instrument: instrumentDesktop } = require("./fixtures/jarvis/desktop-driver.js");
const tree = path.resolve(__dirname, "..");
const daemon = path.join(tree, "shell/plugins/vgs.jarvis/backend/jarvisd.js");
const source = fs.readFileSync(daemon, "utf8");
const hello = { v: 1, type: "hello", gen: 0, settings: { home: "", sounds: false, mode: "hold", microphone: "", speaker: "", brain: "", model: "", effort: "", fallbacks: [], taskTerminal: "auto", voiceProvider: "local", voiceAccount: "", voice: "", clonedVoice: false, dictation: "",
    cloudVision: "ask", privateWindows: "bitwarden" }, directories: {
    state: "/private/state", data: "/private/data", runtime: "/private/runtime"
}, revision: "a".repeat(64), locked: false,
keys: { talk: "SUPER+code:108", mute: "SUPER+SHIFT+code:108", stop: "SUPER+ALT+PERIOD", confirm: "SUPER+ALT+Y", console: "SUPER+ALT+C" } };
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

async function inside() {
    process.chdir(process.env.JARVIS_TEST_ROOT);
    hello.directories = {
        state: path.join(process.env.JARVIS_TEST_ROOT, "state/vgshell/jarvis"),
        data: path.join(process.env.JARVIS_TEST_ROOT, "data/vgshell/jarvis"),
        runtime: path.join(process.env.JARVIS_TEST_ROOT, "run/vgshell/jarvis")
    };
    let controls = 0;
    let cases = 0;
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
            assert.deepEqual(shell, expected.length || (typeof reason === "string" && reason.startsWith("jarvis: mute=")) ? [{ v: 1, type: "shell-status", gen: hello.gen,
                revision: hello.revision, availability: { kind: "checking" } }] : []);
            const keepMemory = expected.some(frame => frame.type === "memory");
            const keepMemoryInbox = expected.some(frame => frame.type === "memory-inbox");
            const keepHomes = expected.some(frame => frame.type === "homes");
            // The Voice offers, the Personality row and the start text's size
            // each judgement sends.
            const shownTypes = ["voices", "personality", "start-text"];
            const keepShown = expected.some(frame => shownTypes.includes(frame.type));
            const publicFrames = frames.filter(frame => ["task-list", "audit-failures"].includes(frame.type));
            if (observations !== null) assert.deepEqual(publicFrames, observations, "startup publishes both bounded lists");
            for (const frame of publicFrames) {
                assert.deepEqual(Object.keys(frame).sort(), ["gen", "revision", "rows", "type", "v"]);
                assert.equal(frame.revision, hello.revision);
                assert.ok(Array.isArray(frame.rows));
                assert.ok(frame.rows.length <= (frame.type === "task-list" ? 16 : 20));
                for (const row of frame.rows) assert.deepEqual(Object.keys(row).sort(), frame.type === "task-list"
                    ? ["agent", "createdAt", "endedAt", "failure", "goal", "id", "state"]
                    : ["decision", "effect", "outcome", "refusal", "time", "tool"]);
            }
            assert.deepEqual(frames.filter(frame => frame.type !== "shell-status"
                && frame.type !== "task-list" && frame.type !== "audit-failures"
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
                    gen: 1, nextOp: 1, stale: 0, settings: hello.settings,
                    gate: { kind: "down", reason: locked ? "locked" : "unconfigured" },
                    mute: { kind: "off" }, capture: { kind: "closed" }, turn: { kind: "none" }, brain: { kind: "closed" },
                    playback: { kind: "idle" }, action: { kind: "none" }, approval: { kind: "none" }, fault: { kind: "none" },
                    conversation: { kind: "ended" }, input: { kind: "released" }, followUp: { kind: "none" },
                    indicator: { kind: "gone" },
                    duplex: { kind: "half" }, toggleAt: null,
                    engine: { kind: "chained" }, speech: { kind: "closed" }, check: { kind: "unavailable" }
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
            decision: "refuse", outcome: "cancelled", refusal: null });
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
    const indicator = shown => ({ v: 1, type: "indicator", gen: 0, revision: hello.revision, shown });
    await run(daemon, [JSON.stringify(indicator(true)) + "\n"], 65, "jarvis: protocol=indicator-identity");
    await run(daemon, [JSON.stringify(hello) + "\n",
        JSON.stringify({ ...indicator(true), revision: "b".repeat(64) }) + "\n"],
        65, "jarvis: protocol=indicator-identity", states([false]));
    await run(daemon, [JSON.stringify(intent("talk-down")) + "\n"], 65, "jarvis: protocol=identity");
    await run(daemon, [JSON.stringify(hello) + "\n",
        JSON.stringify({ ...intent("stop"), revision: "b".repeat(64) }) + "\n"],
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
    async function control(name, needle, replacement, check) {
        assert.equal(source.split(needle).length - 1, 1, name + " mutation match");
        const copy = daemonCopy(name);
        fs.writeFileSync(copy, source.replace(needle, replacement));
        await assert.rejects(() => check(copy), assert.AssertionError, name + " must turn red");
        controls++;
    }
    await control("audit-startup-list", "auditFailures(audit.failures());", "void audit;", startup);
    await control("task-startup-list", 'write({ v: 1, type: "task-list", gen: runner.state.gen,',
        'void ({ v: 1, type: "task-list", gen: runner.state.gen,', startup);
    // The home folder each hello names, on one daemon: it makes what a new
    // folder lacks, a folder it refuses leads the status causes with its own
    // keyed cause, and a text over its budget is one of the status cautions,
    // never a cause. No hello follows an edit inside the folder, so a
    // request made while the folder holds the engine judges it again; any
    // other request sends no status.
    async function homeStatus(file) {
        const base = fs.realpathSync(process.env.HOME);
        const made = path.join(base, "home-made"), linked = path.join(base, "home-linked");
        for (const folder of [made, linked]) fs.rmSync(folder, { recursive: true, force: true });
        fs.mkdirSync(linked);
        fs.symlinkSync(base, path.join(linked, "skills"));
        const child = cp.spawn("node", [file, "--tree", tree], { env: {
            PATH: process.env.PATH, HOME: process.env.HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
            XDG_DATA_HOME: process.env.XDG_DATA_HOME
        }, stdio: ["pipe", "pipe", "pipe"] });
        let out = "", err = "";
        child.stdout.on("data", data => { out += data; });
        child.stderr.on("data", data => { err += data; });
        const closed = once(child, "close");
        const statuses = () => out.split("\n").slice(0, -1).map(line => JSON.parse(line)).filter(frame => frame.type === "status").map(frame => frame.causes);
        const cautions = () => out.split("\n").slice(0, -1).map(line => JSON.parse(line)).filter(frame => frame.type === "status").map(frame => frame.cautions);
        // The Personality row each judgement of the folder sends.
        const shown = () => out.split("\n").slice(0, -1).map(line => JSON.parse(line)).filter(frame => frame.type === "personality").map(frame => frame.personality);
        const personality = () => shown().at(-1);
        // The start text's size each judgement sends: the home layers it
        // names, or unreadable.
        const sizes = () => out.split("\n").slice(0, -1).map(line => JSON.parse(line)).filter(frame => frame.type === "start-text").map(frame => frame.size);
        const sizeLayers = () => {
            const size = sizes().at(-1);
            assert.ok(size !== undefined, "a judgement sends the start text's size");
            return size.kind === "read" ? size.layers.map(entry => entry.layer) : size.kind;
        };
        // The Voice offers, sent when they change: with no local setup the
        // local provider offers none, however many hellos follow.
        const offered = () => out.split("\n").slice(0, -1).map(line => JSON.parse(line)).filter(frame => frame.type === "voices").map(frame => frame.voices);
        const send = message => child.stdin.write(JSON.stringify(message) + "\n");
        const named = setting => ({ ...hello, settings: { ...hello.settings, home: setting } });
        const others = reply(false, 0).causes;
        const seen = [];
        // Send LINES, the last a hello, and read every status so far once
        // that hello is answered: WANT is what the lines add. The home cause
        // of the hello's own answer also ends the wait, so a daemon that
        // sent fewer statuses is read at once. The bound detects a daemon
        // that never answers and is no latency budget.
        const step = async (lines, want) => {
            for (const line of lines) send(line);
            seen.push(...want);
            const last = want.at(-1);
            const met = list => list.length >= seen.length || (last.length > others.length && list.some(causes => causes[0] === last[0]));
            for (let wait = 0; !met(statuses()); wait++) {
                assert.ok(wait < 500 && child.exitCode === null, "the daemon answers the hello: " + err);
                await new Promise(resolve => setTimeout(resolve, 10)); // Polls the daemon's output.
            }
            assert.deepEqual(statuses(), seen);
        };
        try {
            await step([hello], [others]);
            assert.deepEqual(personality(), { kind: "none" }, "no home, no Personality section");
            assert.deepEqual(sizeLayers(), [], "no home, no home layer in the start text");
            assert.ok(sizes().at(-1).tokens > 0, "the shipped guidance alone has a size");
            assert.deepEqual(offered(), [[]], "a provider whose voices cannot be read offers none");
            await step([intent("talk-down"), named("~/home-made")], [others]);
            assert.deepEqual(personality(), { kind: "missing" }, "a new AGENTS.md has no Personality section");
            const bare = sizes().at(-1);
            assert.deepEqual(["AGENTS.md", "skills/own", "memory/MEMORY.md", "memory/inbox", "state",
                ".claude/settings.json", ".codex/config.toml", ".agents/skills/jarvis/SKILL.md", ".agents/skills/jarvis/persona.md"].filter(name => !fs.existsSync(path.join(made, name))), [], "the second hello makes the layout");
            fs.writeFileSync(path.join(made, "AGENTS.md"), "x".repeat(8193) + "\n## Personality\nCalm.\n");
            await step([named("~/home-made")], [others]);
            assert.deepEqual([cautions().at(-1), personality()], [["guidance=agents-over-budget"], { kind: "section", lines: ["Calm."], more: false }],
                "an AGENTS.md over its budget is a caution of a ready folder, and shows its section");
            // 8,193 bytes and more at the recorded ratio: over 2,000 tokens.
            assert.ok(sizes().at(-1).layers.find(entry => entry.layer === "home/AGENTS.md").tokens > 2000, "an AGENTS.md over its budget is counted whole");
            assert.ok(sizes().at(-1).tokens > bare.tokens + 2000, "and the whole start text grows with it");
            fs.writeFileSync(path.join(made, "AGENTS.md"), "# Short again\n\n## Personality\nCalm\u2028and brief.\n");
            await step([intent("talk-down"), named("~/home-made")], [others]);
            assert.deepEqual(cautions().at(-1), [], "a text back within its budget is no caution");
            await step([named("~/home-linked")], [["home=link", ...others]]);
            assert.deepEqual(shown().slice(-2), [{ kind: "section", lines: ["Calm and brief."], more: false }, { kind: "unreadable" }],
                "each judgement reads the section again, a pasted line separator as a space, and a refused folder shows none");
            assert.equal(sizeLayers(), "unreadable", "a refused folder has no size");
            fs.rmSync(path.join(linked, "skills"));
            await step([{ ...intent("say"), text: "fixture request" }, named("/etc/vgs-jarvis-home")], [others, ["home=path", ...others]]);
            child.stdin.end();
            assert.deepEqual(await closed, [0, null], err);
        } finally { if (child.exitCode === null) child.kill("SIGKILL"); }
        assert.deepEqual(statuses(), seen, "one status a hello, and one for each request made over a folder that held the engine");
        assert.deepEqual(offered(), [[]], "unchanged offers are not sent again");
        assert.equal(err, "jarvis: home=link\njarvis: home=path\n");
        assert.equal(fs.existsSync(path.join(linked, "skills/own")), true, "the repaired folder got its layout");
        assert.equal(fs.existsSync("/etc/vgs-jarvis-home"), false);
        cases++;
    }
    const fleet = require("./fixtures/jarvis/fleet.js");
    await fleet.verify(daemon, tree, hello);
    {
        const copy = daemonCopy("fleet-release");
        const module = path.join(path.dirname(copy), "fleet-setup.js");
        const source = fs.readFileSync(module, "utf8");
        const needle = "    try { Home.release(folder); }";
        assert.equal(source.split(needle).length, 2);
        fs.writeFileSync(module, source.replace(needle, "    try { void Home; }"));
        await assert.rejects(() => fleet.verify(copy, tree, hello), assert.AssertionError);
        controls++;
        console.log("control=fleet-installer-release detected");
    }
    await control("fleet-first-hello", "                if (first) startFleetCutover();", "                startFleetCutover();", file => fleet.verify(file, tree, hello));
    await control("fleet-selected-home", "            if (Home.resolve(context.settings.home, process.env.HOME) !== target) return;", "", file => fleet.verify(file, tree, hello));
    await homeStatus(daemon);
    await control("home-layout", "            Home.layout(folder);\n", "", homeStatus);
    await control("voices-write", 'write({ v: 1, type: "voices", gen: runner.state.gen, revision: context.revision, voices });', "void voices;", homeStatus);
    await control("voices-change-only", "if (signature === publishedVoices) return;", "", homeStatus);
    await control("personality-section", 'personality = section.kind === "section" ? Protocol.personalitySection(section.text) : section;',
        "void section;", homeStatus);
    await control("start-text-each-judgement", "        publishStartText();\n        configured(", "        configured(", homeStatus);
    await control("home-refusal", 'return { path: folder, state: { kind: "refused", cause } };', 'return { path: folder, state: { kind: "none" } };', homeStatus);
    await control("home-engine", "directories: context.directories, home: () => homeFolder.state, rejudge: judgeSetup });", "directories: context.directories, rejudge: judgeSetup });", homeStatus);
    await control("home-each-hello", "                judgeSetup();\n", "                if (first) judgeSetup(); else configured(engine.configure(context.settings));\n", homeStatus);
    await control("home-rejudged", " && (engine.homeHeld() || engine.voicesHeld() || engine.modelsHeld())) judgeSetup();", " && (engine.homeHeld() || engine.voicesHeld() || engine.modelsHeld())) void judgeSetup;", homeStatus);
    await control("home-rejudged-held", ' && (engine.homeHeld() || engine.voicesHeld() || engine.modelsHeld())) judgeSetup();', ') judgeSetup();', homeStatus);
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
        fs.mkdirSync(path.join(refused, "skills"), { recursive: true });
        fs.rmSync(path.join(refused, "skills"), { recursive: true });
        fs.symlinkSync(base, path.join(refused, "skills"));
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
    async function conversation(file, check, mode = "hold", expectedCode = 0, expectedError = "", beforeState = null,
        sounds = hello.settings.sounds) {
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
        const send = message => child.stdin.write(JSON.stringify(message) + "\n");
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
            send({ ...hello, settings: { ...hello.settings, mode, sounds } });
            if (beforeState !== null) await beforeState({ messages });
            await wait(m => m.state.gate.kind !== "down" || m.state.gate.reason === "unconfigured");
            await check({ send: name => send(intent(name)), raw: send, reply: send,
                indicator: shown => send(indicator(shown)), wait, last, messages, pid: child.pid });
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
    const muteFile = path.join(hello.directories.state, "mute.json");
    const muteCheck = async file => {
        await conversation(file, async w => {
            w.send("mute");
            await w.wait(m => m.state.mute.kind === "on");
            assert.deepEqual(JSON.parse(fs.readFileSync(muteFile, "utf8")), { muted: true });
            assert.equal(fs.statSync(muteFile).mode & 0o777, 0o600);
            for (const name of ["talk-down", "talk-up", "stop"]) w.send(name);
            await w.wait(m => m.seq >= 5);
            assert.equal(w.last().state.mute.kind, "on");
            assert.equal(w.last().state.capture.kind, "closed");
        });
    };
    await muteCheck(daemon);
    // No harness brain exists, so startup opens no tool bridge session.
    const noBridge = file => conversation(file, async () => {
        assert.equal(fs.existsSync(path.join(hello.directories.runtime, "tools.sock")), false, "startup creates no tools.sock");
    });
    await noBridge(daemon);
    await control("no-bridge-session", "// Executor owners register only after their real probes.",
        'void bridge.open({ gen: 0, recipients: require("./Policy.js").recipients({ conversation: "planted",'
        + ' profile: "standard", cloudVision: "ask", brain: { kind: "local", provider: "planted", account: "" },'
        + ' speech: [{ kind: "local", provider: "planted", account: "" }] }) });', noBridge);
    const restoreCheck = file => conversation(file, async w => {
        assert.equal(w.last().state.mute.kind, "on");
        await w.wait(m => m.state.mute.kind === "on" && w.messages.some(message =>
            message.type === "devices" && message.microphones.some(item => item.value === "fixture.mic")));
        w.send("talk-down"); w.send("talk-up"); w.send("stop");
        await w.wait(m => m.seq >= 5);
        assert.equal(w.last().state.capture.kind, "closed");
        w.send("mute");
        await w.wait(m => m.state.mute.kind === "off");
        assert.deepEqual(JSON.parse(fs.readFileSync(muteFile, "utf8")), { muted: false });
    });
    await restoreCheck(daemon);
    fs.writeFileSync(muteFile, JSON.stringify({ muted: true }));
    await control("muted-device-offers", "if (first) void audio.discover()", "if (seq === 1) void audio.discover()", restoreCheck);
    fs.writeFileSync(muteFile, JSON.stringify({ muted: true }));
    await control("mute-restore", 'if (first && readMute()) runner.dispatch({ type: "mute" });',
        'if (false && first && readMute()) runner.dispatch({ type: "mute" });', restoreCheck);
    fs.writeFileSync(muteFile, JSON.stringify({ muted: false }));
    await control("mute-store", 'fs.renameSync(file, path.join(directory, name));',
        'void directory;', muteCheck);
    await control("intent-consumer", 'runner.dispatch(message.intent === "mute" ? { type: "mute-toggle" }\n                                : message.intent === "say" ? { type: "say", text: message.text }\n                                : { type: message.intent });',
        'void message.intent;', muteCheck);
    for (const [bytes, reason] of [["{", "record-json"], ['{"muted":"yes"}', "record-shape"],
        ['{"muted":true,"extra":0}', "record-shape"], [" ".repeat(65), "record-size"]]) {
        fs.writeFileSync(muteFile, bytes);
        await run(daemon, [JSON.stringify(hello) + "\n"], 78, "jarvis: mute=" + reason);
    }
    fs.unlinkSync(muteFile);
    fs.mkdirSync(muteFile);
    await run(daemon, [JSON.stringify(hello) + "\n"], 78, "jarvis: mute=record-not-file");
    fs.rmdirSync(muteFile);
    await conversation(daemon, async w => {
        fs.mkdirSync(muteFile);
        w.send("mute");
    }, "hold", 78, "jarvis: mute=write-failed");
    fs.rmdirSync(muteFile);
    await control("mute-size", 'if (size > limit) throw new Error("jarvis: " + area + "=record-size");', 'void size;',
        async file => {
            fs.writeFileSync(muteFile, '{"muted":false}' + " ".repeat(51));
            await run(file, [JSON.stringify(hello) + "\n"], 78, "jarvis: mute=record-size");
        });
    await control("mute-shape", 'throw new Error("jarvis: mute=record-shape");', ';',
        async file => {
            fs.writeFileSync(muteFile, '{"muted":false,"extra":0}');
            await run(file, [JSON.stringify(hello) + "\n"], 78, "jarvis: mute=record-shape");
        });
    fs.unlinkSync(muteFile);
    const linkedRecord = path.join(root, "linked-mute.json");
    fs.writeFileSync(linkedRecord, '{"muted":false}');
    fs.symlinkSync(linkedRecord, muteFile);
    await run(daemon, [JSON.stringify(hello) + "\n"], 78, "jarvis: mute=read-failed");
    await control("mute-link", 'fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK',
        'fs.constants.O_RDONLY | fs.constants.O_NONBLOCK',
        file => run(file, [JSON.stringify(hello) + "\n"], 78, "jarvis: mute=read-failed"));
    fs.unlinkSync(muteFile);

    const scripted = daemonCopy("scripted");
    const gates = path.join(root, "gates");
    instrument(scripted, gates);
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
    const captureWait = 'if (turnRequest === "held" && runner.state.capture.kind === "open")';
    assert.equal(mappedDriverSource.split(captureWait).length - 1, 1);
    const earlyRelease = mappedDriverSource.replace(captureWait, 'if (turnRequest === "held")');
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
        }, "hold", 0, error);
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
            w.send("talk-up");
            await w.wait(m => m.phase === "thinking");
            assert.equal(effects("playback-start"), 0, "the basic fixture keeps its assistant reply gated");
            w.send("stop");
            await w.wait(m => m.state.conversation.kind === "ended" && m.state.playback.kind === "idle");
        }, "hold", 0, "", null, true);
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
    const mappedCheck = async file => conversation(file, async w => {
        assert.equal(w.last().state.indicator.kind, "gone");
        w.send("talk-down");
        const waiting = await w.wait(m => m.state.input.kind === "held");
        assert.equal(waiting.state.capture.kind, "closed", "no screen keeps capture closed");
        w.indicator(true);
        await w.wait(m => m.phase === "listening");
        w.indicator(false);
        const gone = await w.wait(m => m.state.indicator.kind === "gone" && m.state.capture.kind === "closed");
        assert.equal(gone.state.capture.kind, "closed", "indicator loss releases capture");
        w.send("stop");
        await w.wait(m => m.state.conversation.kind === "ended");
    });
    await mappedCheck(mapped);
    for (const [name, needle, replacement] of [
        ["indicator-delivery", 'runner.dispatch({ type: "indicator", shown: message.shown });', 'void message.shown;'],
        ["indicator-loss", 'shown: message.shown', 'shown: true']
    ]) {
        const copy = daemonCopy(name);
        instrument(copy, gates, "chained", true);
        const before = fs.readFileSync(copy, "utf8");
        assert.equal(before.split(needle).length - 1, 1);
        fs.writeFileSync(copy, before.replace(needle, replacement));
        await assert.rejects(() => mappedCheck(copy), assert.AssertionError, name + " must turn red");
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
    const stopSettled = m => m.state.conversation.kind === "ended" && m.phase === "idle"
        && m.state.playback.kind === "idle";
    const stopGates = ["brain", "played", "late-brain", "late-played", "hold-flush", "flush"];
    const activeStop = async (file, phase, settled = stopSettled) => conversation(file, async w => {
        w.send("talk-down");
        await w.wait(m => m.phase === "listening");
        w.send("talk-up");
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
        assert.equal(ended.state.brain.kind, "closed");
        assert.equal(ended.state.turn.kind, "none");
        gate(phase === "thinking" ? "late-brain" : "late-played");
        const late = await w.wait(m => m.state.stale > ended.state.stale);
        assert.equal(late.phase, "idle", "late callback cannot restart the stopped turn");
        assert.equal(late.state.conversation.kind, "ended");
        assert.equal(late.state.capture.kind, "closed");
        assert.equal(late.state.playback.kind, "idle");
        assert.equal(count("playback-start"), playback);
    });
    for (const phase of ["thinking", "speaking"]) await activeStop(scripted, phase);
    // The first ended frame alone reads the held flushing frame.
    await assert.rejects(() => activeStop(scripted, "speaking", m => m.state.conversation.kind === "ended" && m.phase === "idle"),
        { name: "AssertionError", message: /'flushing' !== 'idle'/ }, "a Stop read before its flush settles must turn red");
    for (const name of stopGates)
        fs.rmSync(path.join(gates, name), { force: true });
    controls++;
    console.log("test-jarvis-daemon: control=stop-settled detected");
    const stopControl = daemonCopy("stop-routing");
    instrument(stopControl, gates);
    const dispatch = 'runner.dispatch(message.intent === "mute" ? { type: "mute-toggle" }\n                                : message.intent === "say" ? { type: "say", text: message.text }\n                                : { type: message.intent });';
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
        w.send("talk-up");
        await w.wait(m => m.phase === "thinking");
        gate("brain");
        await w.wait(m => m.phase === "speaking");
        gate("played");
        await w.wait(m => m.phase === "idle" && m.state.playback.kind === "idle");
        w.send("talk-down");
        await w.wait(m => m.phase === "listening");
        gate("hold-close");
        w.send("mute");
        await w.wait(m => m.state.mute.kind === "muting");
        w.send("talk-down"); w.send("talk-up"); w.send("stop");
        gate("close");
        await w.wait(m => m.state.mute.kind === "on");
        assert.equal(w.last().state.capture.kind, "closed");
        assert.equal(count("capture-open"), initialOpens + 2);
        fs.unlinkSync(path.join(gates, "hold-close"));
    });
    await conversation(scripted, async w => {
        assert.equal(w.last().state.mute.kind, "on");
        const opens = count("capture-open");
        w.send("talk-down"); w.send("talk-up"); w.send("stop");
        await w.wait(m => m.seq >= 6);
        assert.equal(count("capture-open"), opens, "restart preserves privacy before every key");
        w.send("mute");
        await w.wait(m => m.state.mute.kind === "off");
    });
    await conversation(scripted, async w => {
        w.send("talk-down");
        await w.wait(m => m.phase === "listening");
        const before = w.last().seq;
        w.send("talk-up");
        await w.wait(m => m.seq > before);
        assert.equal(w.last().state.input.kind, "conversation", "release does not commit toggle");
        await new Promise(resolve => setTimeout(resolve, 250)); // Reach the reducer's next permitted toggle edge.
        w.send("talk-down");
        await w.wait(m => m.state.conversation.kind === "ended" && m.state.capture.kind === "closed");
        assert.equal(w.last().state.capture.kind, "closed");
    }, "toggle");
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
        w.send("stop");
        const ended = await w.wait(m => m.state.speech.kind === "closed");
        fs.writeFileSync(path.join(duplexGates, "transcript"), "");
        await w.wait(m => m.state.stale > ended.state.stale);
        assert.equal(w.messages.filter(m => m.type === "transcript").length, 1, "a closed session's caption stays off the wire");
    });
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
    const scriptedReply = Array(24).fill("scripted reply").join(" ");
    const replyWords = file => conversation(file, async w => {
        w.send("talk-down");
        const listening = await w.wait(m => m.phase === "listening");
        w.send("talk-up");
        const thinking = await w.wait(m => m.phase === "thinking");
        fs.writeFileSync(path.join(chainedGates, "reply"), "");
        await w.wait(m => m.phase === "speaking" && m.state.turn.kind === "none");
        assert.deepEqual(w.messages.filter(m => m.type === "transcript").map(m => [m.gen, m.role, m.stage, m.rev, m.text]),
            [[thinking.gen, "user", "final", listening.state.turn.op, "scripted utterance"],
                [thinking.gen, "assistant", "partial", 1, "On it."],
                [thinking.gen, "assistant", "partial", 2, "On it. " + scriptedReply],
                [thinking.gen, "assistant", "final", 3, "On it. " + scriptedReply]],
            "the bubble fixture's words come from the chained engine");
        w.send("stop");
        await w.wait(m => m.state.conversation.kind === "ended" && m.state.brain.kind === "closed");
    });
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
    // no hello follows: the first request after it judges the home once. A
    // home VGS laid out gets the render VGS ships again, at its own paths,
    // and the request gets the scripted reply. A home kendex installed the
    // package in, as its lock names the package's skill, is kendex's to
    // restore: VGS writes nothing there and the request fails on the
    // home's absent package.
    const renderGates = path.join(root, "render-gates");
    const renderHome = path.join(fs.realpathSync(process.env.HOME), "home-render");
    const shipped = path.join(tree, "packaging/jarvis-home");
    // The render's harness folders, read from the render itself.
    const HARNESS = [".agents", ".claude/skills", ".claude/agents", ".codex/agents"];
    const tracked = folder => fs.readdirSync(folder, { recursive: true }).sort()
        .map(name => [name, fs.statSync(path.join(folder, name)).isFile() ? fs.readFileSync(path.join(folder, name), "utf8") : null]);
    const vgsFiles = () => [".vgs-package.json", ...HARNESS].filter(name => fs.existsSync(path.join(renderHome, name)));
    const renderRemoved = (file, owner) => conversation(file, async w => {
        fs.rmSync(renderHome, { recursive: true, force: true });
        fs.mkdirSync(renderHome);
        if (owner === "kendex") {
            fs.cpSync(path.join(shipped, ".agents/skills/jarvis"), path.join(renderHome, ".agents/skills/jarvis"), { recursive: true });
            fs.writeFileSync(path.join(renderHome, ".kendex-lock.json"), JSON.stringify({ version: 11, entries: { "skill:jarvis:codex":
                { kind: "skill", name: "jarvis", harness: "codex", emitted: { kind: "skill", name: "jarvis", paths: [".agents/skills/jarvis"] } } } }) + "\n");
        }
        w.raw({ ...hello, settings: { ...hello.settings, home: "~/home-render" } });
        await w.wait(m => m.state.settings.home === "~/home-render" && m.state.gate.kind === "up");
        if (owner === "kendex") assert.deepEqual(vgsFiles(), [".agents"], "the hello reads kendex's render and writes none of VGS's copy");
        else for (const folder of HARNESS)
            assert.deepEqual(tracked(path.join(renderHome, folder)), tracked(path.join(shipped, folder)), folder + ": the hello lays the render out");
        const judged = w.messages.filter(m => m.type === "status").length;
        fs.rmSync(path.join(renderHome, ".agents"), { recursive: true });
        w.send("talk-down");
        await w.wait(m => m.phase === "listening");
        w.send("talk-up");
        if (owner === "kendex") {
            const down = await w.wait(m => m.state.gate.kind === "down" || m.state.fault.kind !== "none");
            assert.deepEqual([down.state.gate, down.state.fault], [{ kind: "down", reason: "unconfigured" }, { kind: "none" }],
                "the request after kendex's render is removed holds the engine");
            await w.wait(m => m.state.conversation.kind === "ended" && m.state.brain.kind === "closed");
            const statuses = w.messages.filter(m => m.type === "status");
            assert.equal(statuses.length, judged + 1, "the request judges the home once");
            assert.equal(statuses.at(-1).causes[0], "home=absent", "the home is refused for its absent package");
            assert.deepEqual(vgsFiles(), [], "VGS writes nothing in kendex's home");
            return;
        }
        await w.wait(m => m.phase === "thinking" || m.state.fault.kind !== "none");
        fs.writeFileSync(path.join(renderGates, "reply"), "");
        const ended = await w.wait(m => m.state.fault.kind !== "none" || m.phase === "speaking" && m.state.turn.kind === "none");
        assert.deepEqual(ended.state.fault, { kind: "none" }, "the first request after the removal gets an answer");
        assert.ok(w.messages.some(m => m.type === "transcript" && m.role === "assistant" && m.stage === "final"
            && m.text.endsWith(scriptedReply)), "the answer is the brain's reply");
        assert.equal(w.messages.filter(m => m.type === "status").length, judged + 1, "the request judges the home once");
        for (const folder of HARNESS)
            assert.deepEqual(tracked(path.join(renderHome, folder)), tracked(path.join(shipped, folder)), folder + " holds the shipped render");
        w.send("stop");
        await w.wait(m => m.state.conversation.kind === "ended" && m.state.brain.kind === "closed");
    }, "hold", 0, owner === "kendex" ? "jarvis: home=absent" : "");
    for (const [name, needle, replacement, owner = "vgs"] of [["render-removed", null, null], ["render-removed-kendex", null, null, "kendex"],
        ["render-removed-unjudged", "        rejudge();\n", ""]]) {
        fs.rmSync(renderGates, { recursive: true, force: true });
        const file = daemonCopy(name);
        instrument(file, renderGates);
        const engineFile = path.join(path.dirname(file), "ChainedEngine.js");
        chainedEngine(engineFile);
        if (needle === null) { await renderRemoved(file, owner); continue; }
        const engineSource = fs.readFileSync(engineFile, "utf8");
        assert.equal(engineSource.split(needle).length - 1, 1, name + " mutation match");
        fs.writeFileSync(engineFile, engineSource.replace(needle, replacement));
        await assert.rejects(() => renderRemoved(file, owner), error => error instanceof assert.AssertionError
            && error.message.startsWith("the first request after the removal gets an answer"), name + " must turn red");
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
    const keyRow = fs.readFileSync(path.join(tree, "scripts/smoke/rows/jarvis-keys.sh"), "utf8");
    const retryStart = 'expect "repeated physical Mute during retry stays one request"';
    const helloRead = 'expect_poll "the restarted daemon consumes hello" seen jarvis_seen_hello';
    const startupRead = 'expect_poll "the retry starts its next daemon with Mute pending" '
        + '\'{"kind":"starting","pendingMute":"waiting"}\' jarvis_key_pending';
    for (const needle of [retryStart, helloRead, startupRead]) assert.equal(keyRow.split(needle).length - 1, 1);
    const retryReads = keyRow.slice(keyRow.indexOf(retryStart), keyRow.indexOf(helloRead) + helloRead.length);
    const harness = fs.readFileSync(path.join(tree, "scripts/smoke/harness.sh"), "utf8");
    const pollers = harness.match(/^expect_poll\(\) \{[\s\S]*?^\}/gm);
    assert.equal(pollers?.length, 1);
    const pollBound = harness.match(/^smoke_poll_bound_ms=[0-9]+$/gm);
    assert.equal(pollBound?.length, 1);
    const pollTries = harness.match(/^smoke_poll_tries\(\) \{[\s\S]*?^\}/gm);
    assert.equal(pollTries?.length, 1);
    const onePending = keyRow.match(/^jarvis_key_one_pending\(\) \{[\s\S]*?^\}/gm);
    assert.equal(onePending?.length, 1);
    const retryClock = path.join(root, "retry-clock");
    function retryOrdering(reads, helloTick) {
        fs.writeFileSync(retryClock, "0");
        // One tick is the real poller's 0.2 s sleep. The service starts
        // after the fixture's 4.5 s retry; hello follows that child start.
        const fixture = `
set -euo pipefail
failures=0
clock=${JSON.stringify(retryClock)}
sandbox=${JSON.stringify(root)}
hello_tick=${helloTick}
ok() { :; }
fail() { failures=$((failures + 1)); printf '%s\\n' "$1"; }
reader_stderr() { [[ ! -s $2 ]]; }
seq() {
    local value
    for ((value=$1; value<=$2; value++)); do printf '%s\\n' "$value"; done
}
expect() {
    local label="$1" want="$2" got
    shift 2
    got="$("$@")"
    [[ $got == "$want" ]] || fail "$label: got $got want $want"
}
sleep() {
    [[ $1 == 0.2 ]]
    local tick
    tick="$(<"$clock")"
    printf '%s' "$((tick + 1))" >"$clock"
}
jarvis_key_pending() {
    local tick
    tick="$(<"$clock")"
    if ((tick < 23)); then printf '%s\\n' '{"kind":"retry","pendingMute":"waiting"}'
    else printf '%s\\n' '{"kind":"starting","pendingMute":"waiting"}'; fi
}
${onePending[0]}
jarvis_seen_hello() {
    local tick
    tick="$(<"$clock")"
    if ((tick >= hello_tick)); then echo seen; else echo pending; fi
}
${pollBound[0]}
${pollTries[0]}
${pollers[0]}
${reads}
exit "$failures"
`;
        const result = cp.spawnSync("bash", ["-c", fixture], { env: { PATH: process.env.PATH, HOME: process.env.HOME },
            encoding: "utf8", timeout: 3000 });
        assert.equal(result.error, undefined);
        return result;
    }
    for (const helloTick of [24, 28]) {
        const actual = retryOrdering(retryReads, helloTick);
        assert.equal(actual.status, 0, actual.stdout + actual.stderr);
        cases++;
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
            await conversation(file, async () => {}, "hold", 0, "", async ({ messages }) => {
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
            w.send("talk-up");
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
    const Protocol = require(path.join(tree, "bin/lib/qml-library.js")).load(path.join(tree, "shell/plugins/vgs.jarvis/JarvisProtocol.js"));
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
                'if (runner.state.indicator.kind !== "shown") runner.dispatch({ type: "indicator", shown: true });\n                runner.dispatch({ type: "snapshot", locked: context.locked,']]) {
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
            send(intent("talk-up"));
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
    async function engineConversation(file, said = "What time is it?", caption = said, identicalHello = false) {
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
            send(intent("talk-up"));
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
            ["ordinary", "What time is it?", "What time is it?"],
            ["multiline", "What time\nis it?\tPlease tell me.\u0000", "What time is it? Please tell me. "],
            ["oversized", "Dropped prefix. " + tail, tail]
        ];
        for (const [name, said, caption] of finals) {
            await engineConversation(engineCopy("engine-" + name, said), said, caption);
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
    const parent = path.join(tree, "tmp");
    fs.mkdirSync(parent, { recursive: true });
    const root = fs.mkdtempSync(path.join(parent, "jd-"));
    try {
        // The export copies this tree's suite inputs and a read outside them
        // fails there, so its run is the one run of every case and control;
        // freshSuite fails with that run's output when a case fails.
        const launcher = path.join(tree, "scripts/lib/jarvis-env.sh");
        const env = { PATH: "/usr/bin:/bin", HOME: root, JARVIS_TEST_SCRATCH_ROOT: path.join(tree, "tmp") };
        if (process.argv[2] !== "--fresh") {
            // Here, not in the export's run, so the row prints the control's line.
            fs.mkdirSync(path.join(root, "hung"));
            hungWorldControl(launcher, path.join(root, "hung"), env);
            freshSuite(tree, "daemon", root);
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
