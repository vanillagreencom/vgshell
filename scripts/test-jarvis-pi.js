#!/usr/bin/env node
// The Pi harness end to end in J09: the real Session reducer, SessionRunner,
// ToolRouter, Policy, Denied, Audit, ToolBridge with the real mcp-shim,
// Accounts and PiHarness, against fixtures/jarvis-pi/pi-stub.js as the
// `pi` program. The stub speaks the RPC subset of Pi 1.1.0 recorded in
// fixtures/jarvis-pi/recorded.ndjson; its header says how. No real Pi,
// account, network or paid request is used. Mutants edit disposable plugin
// copies; each must turn a case red.
"use strict";
const { assert, fs, path, tree, world, seed } = require("./fixtures/jarvis/policy.js");
const Check = require("./fixtures/schema-check.js");
const excerpt = require("./fixtures/jarvis-pi/rpc.schema.json");
const { load } = require("../bin/lib/qml-library.js");
const Fixture = require("./fixtures/jarvis/engine.js");
const cp = require("node:child_process");
const plugin = path.join(tree, "shell/plugins/vgs.jarvis");
// A key planted in the user's own Pi setup and in the daemon's environment.
const PLANTED = "pi-planted-credential-7f3a91";
const LOCKDOWN = ["--mode", "rpc", "--no-session", "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-themes",
    "--no-context-files", "--offline"];

world(async () => {
    const Session = load(path.join(plugin, "Session.js"));
    const fixtures = seed();
    const state = process.env.XDG_STATE_HOME;
    fs.copyFileSync(path.join(tree, "scripts/fixtures/jarvis-pi/recorded.ndjson"), path.join(state, "pi-recorded.ndjson"));
    const account = path.join(process.env.HOME, ".pi/agent");
    fs.mkdirSync(account, { recursive: true });
    fs.writeFileSync(path.join(account, "auth.json"), JSON.stringify({ stub: { type: "api_key", key: PLANTED } }));
    const env = { PATH: process.env.PATH, HOME: process.env.HOME, XDG_CONFIG_HOME: process.env.XDG_CONFIG_HOME,
        XDG_STATE_HOME: state, XDG_DATA_HOME: process.env.XDG_DATA_HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
        ANTHROPIC_API_KEY: PLANTED, OPENAI_API_KEY: PLANTED, VGSH_RUNNER_PID: "1" };
    const owners = [];
    let serial = 0, cases = 0;

    async function until(predicate, what, ms = 5000) {
        // Children answer across pipes; poll in real time with a bound.
        for (const end = Date.now() + ms; Date.now() < end;) {
            if (predicate()) return;
            await new Promise(resolve => setTimeout(resolve, 5));
        }
        assert.fail(what + " never held");
    }
    const read = name => fs.existsSync(path.join(state, name))
        ? fs.readFileSync(path.join(state, name), "utf8").trim().split("\n").filter(Boolean).map(line => JSON.parse(line)) : [];
    function scenario(value) {
        for (const name of ["pi-log", "pi-calls"]) fs.rmSync(path.join(state, name), { force: true });
        fs.writeFileSync(path.join(state, "pi-scenario.json"), JSON.stringify(value));
    }
    const program = () => read("pi-calls").at(-1);
    const alive = pid => { try { process.kill(pid, 0); return true; } catch { return false; } };
    const livePrograms = () => read("pi-calls").filter(call => Number.isSafeInteger(call.pid) && alive(call.pid));
    function killLivePrograms() { for (const call of livePrograms()) try { process.kill(call.pid, "SIGKILL"); } catch {} }
    async function noProgramOrDir(runtime, label) {
        await until(() => livePrograms().length === 0, label + " leaves no program");
        await until(() => !fs.existsSync(runtime) || fs.readdirSync(runtime).every(name => !name.startsWith("pi-")), label + " removes its directory");
    }
    const received = type => read("pi-log").filter(row => row.direction === "in" && row.message.type === type).map(row => row.message);
    // Every record Jarvis wrote is a command of the pinned excerpt.
    function validWrites() {
        for (const { direction, message } of read("pi-log")) {
            if (direction === "in") assert.deepEqual(Check.errors(excerpt, "Command", message), [], message.type);
            if (direction === "out" && message.type === "response") assert.deepEqual(Check.errors(excerpt, "Response", message), [], "stub response");
        }
    }
    const chunk = text => ({ text });

    /** One daemon-side world loaded from a plugin folder. */
    function make(folder = plugin, options = {}) {
        const need = name => require(path.join(folder, "backend", name));
        const Router = need("ToolRouter.js"), Bridge = need("ToolBridge.js"), Audit = need("Audit.js");
        need("Core.js").use(tree);
        const Policy = need("Policy.js"), Denied = need("Denied.js"), Harness = need("PiHarness.js"), Providers = need("Providers.js");
        const { SessionRunner, unavailable } = need("session-runner.js");
        const root = path.join(process.env.JARVIS_TEST_ROOT, "a" + ++serial);
        fs.mkdirSync(root);
        let transcript;
        const starts = [];
        const audit = Audit.create({ state: path.join(root, "state"), now: () => Date.UTC(2026, 9, 8) });
        const ports = { ...unavailable(), mute: { store() {} }, transcript() {},
            capture: { open: (e, done) => done(), close: (e, done) => done(), collect: (e, done) => { transcript = done; } },
            brain: { send() {}, cancel: (e, done) => done(), close() {} } };
        const runner = new SessionRunner(Session, ports, { now: () => 0, set: () => ({}), clear() {} }, () => {});
        let bridge = null;
        const router = Router.create({ session: Session, state: () => runner.state, dispatch: e => runner.dispatch(e),
            context: () => ({ profile: "standard", locked: false, denied: Denied.create(fixtures.roots) }),
            audit, result: value => bridge.deliver(value) });
        Object.assign(ports, router.ports);
        router.register("windows", { commands: ["hyprctl"], timeoutMs: 1000, cancellable: false,
            start: (call, done) => starts.push({ call, done }) });
        const runtime = path.join(process.env.JARVIS_TEST_ROOT, "r" + serial.toString(36));
        bridge = Bridge.create({ router, state: () => runner.state, audit, directory: runtime,
            release: { prepare: () => Promise.resolve([]) } });
        runner.dispatch({ type: "snapshot", locked: false, engine: "chained", configured: true, settings: {} });
        runner.dispatch({ type: "indicator", shown: true });
        runner.dispatch({ type: "talk-down" });
        transcript("final", "fixture user");
        const recipients = Policy.recipients({ conversation: "pi-" + serial, profile: "standard", cloudVision: "ask",
            brain: { kind: "network", provider: "pi", account: "fixture", origin: "https://pi.dev" },
            speech: [{ kind: "local", provider: "fixture-speech", account: "" }] });
        const create = (value = bridge) => Harness.create({ provider: Providers.select("pi"), model: options.model ?? "",
            recipients, account: { kind: "cli", directory: account }, gen: runner.state.gen,
            harness: { bridge: value, env, runtime: () => runtime } });
        const brain = create();
        brain.start({ instructions: "Be brief.", tools: [] });
        owners.push(() => { brain.close(); bridge.close(); audit.close(); });
        return { Policy, Harness, runner, router, bridge, brain, starts, runtime, recipients, audit, root, create,
            say: (text, labels = ["speech"]) => brain.send({ kind: "user", items: [Policy.item(text, labels)] }) };
    }
    // A turn crosses the stub's pipes; a lost answer fails its case.
    async function drain(reply) {
        const events = [];
        let timer;
        const limit = new Promise((resolve, reject) => {
            timer = setTimeout(() => reject(new assert.AssertionError({ message: "turn timeout" })), 8000);
        });
        const consume = (async () => { for await (const event of reply.events) events.push(event); })();
        // A turn's own failure is the behaviour under test: its keyed message is
        // compared, and an unexpected one fails the case as an assertion.
        try { await Promise.race([consume, limit]); }
        catch (error) { throw error instanceof assert.AssertionError ? error : new assert.AssertionError({ message: error.message }); }
        finally { clearTimeout(timer); }
        return events;
    }
    function copied(folder, edits) {
        const copy = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "copy-"));
        fs.mkdirSync(path.join(copy, "backend"));
        for (const name of fs.readdirSync(plugin).filter(name => name.endsWith(".js")))
            fs.copyFileSync(path.join(folder, name), path.join(copy, name));
        for (const name of fs.readdirSync(path.join(folder, "backend")).filter(name => name.endsWith(".js") || name === "mcp-shim"))
            fs.copyFileSync(path.join(folder, "backend", name), path.join(copy, "backend", name));
        fs.cpSync(path.join(folder, "backend/skills"), path.join(copy, "backend/skills"), { recursive: true });
        for (const [relative, changes] of Object.entries(edits)) {
            const file = path.join(copy, relative);
            let source = fs.readFileSync(file, "utf8");
            for (const [needle, replacement] of changes) {
                assert.equal(source.split(needle).length - 1, 1, relative + " match: " + needle);
                source = source.replace(needle, replacement);
            }
            fs.writeFileSync(file, source);
        }
        return copy;
    }
    const shortBounds = folder => copied(folder, { "backend/PiHarness.js": [
        ["const HANDSHAKE_MS = 30000;", "const HANDSHAKE_MS = 300;"],
        ["const PROBE_MS = 60000;", "const PROBE_MS = 300;"],
        ["const MODELS_MS = 10000;", "const MODELS_MS = 300;"]
    ], "backend/HarnessProgram.js": [["const CLOSE_MS = 2000;", "const CLOSE_MS = 50;"]] });
    const accounts = (folder, runtime) => {
        require(path.join(folder, "backend/Core.js")).use(tree);
        const { Accounts } = require(path.join(folder, "backend/Accounts.js"));
        const directory = path.join(state, "vgshell/jarvis");
        return { judge: new Accounts(directory, env, undefined, runtime), directory };
    };
    // Every file under a directory, as text, for a planted-key scan.
    const filesUnder = directory => !fs.existsSync(directory) ? [] : fs.readdirSync(directory, { recursive: true })
        .map(name => path.join(directory, name)).filter(file => fs.lstatSync(file).isFile()).map(file => fs.readFileSync(file, "utf8"));

    const CASES = {
        // The lockdown argv, the scrubbed environment, the bridge as the one
        // MCP server, compaction off before the first prompt and streamed text.
        async turn(folder) {
            scenario({ turns: [[chunk("Hel"), chunk("lo."), { stop: "stop" }], [chunk("Again."), { stop: "stop" }]] });
            const w = make(folder);
            assert.deepEqual(await drain(w.say("hi")), [{ kind: "text", text: "Hel" }, { kind: "text", text: "lo." }, { kind: "done", reason: "stop" }]);
            const call = program();
            assert.deepEqual(call.args.slice(0, LOCKDOWN.length), LOCKDOWN);
            assert.deepEqual(call.args.slice(LOCKDOWN.length, -2), ["--extension", "builtin:mcp", "--approve", "--tools", "mcp__vgs_jarvis__*"],
                "only the built-in MCP support and the bridge's tools");
            assert.equal(call.args.at(-2), "--system-prompt");
            assert.equal(call.instructions, "Be brief.", "the instructions replace Pi's system prompt");
            assert.equal(call.deathsig, 9, "setpriv keeps the program tied to the daemon");
            assert.equal(call.env.PI_CODING_AGENT_DIR, account, "the user's own Pi folder");
            for (const name of ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "VGSH_RUNNER_PID"])
                assert.equal(Object.hasOwn(call.env, name), false, name + " stays out of the program's environment");
            assert.equal(path.dirname(call.cwd), w.runtime, "a private working directory");
            const server = JSON.parse(call.mcp).mcpServers;
            assert.deepEqual(Object.keys(server), ["vgs_jarvis"]);
            assert.equal(server.vgs_jarvis.exposure, "direct");
            assert.deepEqual(server.vgs_jarvis.env, { VGS_JARVIS_TOOLS_SOCKET: "${VGS_JARVIS_TOOLS_SOCKET}",
                VGS_JARVIS_TOOLS_TOKEN: "${VGS_JARVIS_TOOLS_TOKEN}" }, "mcp.json names the bridge's variables, never their values");
            assert.match(call.env.VGS_JARVIS_TOOLS_TOKEN, /^[0-9a-f]{64}$/);
            assert.equal(JSON.stringify(call.args).includes(call.env.VGS_JARVIS_TOOLS_TOKEN), false, "the token stays out of argv");
            assert.deepEqual(await drain(w.say("more")), [{ kind: "text", text: "Again." }, { kind: "done", reason: "stop" }]);
            const commands = read("pi-log").filter(row => row.direction === "in").map(row => row.message.type);
            assert.deepEqual(commands, ["set_auto_compaction", "prompt", "prompt"]);
            assert.equal(received("set_auto_compaction")[0].enabled, false);
            assert.deepEqual(received("prompt").map(m => m.message), ["hi", "more"]);
            assert.equal(read("pi-calls").length, 1, "one program per conversation");
            validWrites();
        },
        // A model chosen in the menu is set before the first prompt.
        async model(folder) {
            scenario({ turns: [[{ stop: "stop" }]] });
            const w = make(folder, { model: "openrouter/openai/gpt-5" });
            await drain(w.say("hi"));
            assert.deepEqual(received("set_model").map(m => [m.provider, m.modelId]), [["openrouter", "openai/gpt-5"]]);
            const types = read("pi-log").filter(row => row.direction === "in").map(row => row.message.type);
            assert.ok(types.indexOf("set_model") < types.indexOf("prompt"));
            assert.throws(() => make(folder, { model: "no-slash" }), { message: "jarvis: brain=pi-model" });
            validWrites();
        },
        // Only released content reaches the program; a file needs a grant.
        async release(folder) {
            scenario({ turns: [[{ stop: "stop" }]] });
            const w = make(folder);
            const reply = w.brain.send({ kind: "user", items: [w.Policy.item("spoken", ["speech"]), w.Policy.item("secret notes", ["file"])] });
            assert.deepEqual([[...reply.release.labels], [...reply.release.needed]], [["speech"], ["file"]]);
            await drain(reply);
            const text = received("prompt")[0].message;
            assert.ok(text.includes("spoken"));
            assert.equal(text.includes("secret notes"), false);
            const empty = make(folder);
            await assert.rejects(drain(empty.say("only a file", ["file"])), { message: "jarvis: brain=pi-release-empty" });
        },
        // The bridge's tool calls run through the real shim and router.
        async bridge(folder) {
            scenario({ turns: [[{ mcp: { tool: "windows_list", arguments: {} } }, chunk("Listed."), { stop: "stop" }]] });
            const w = make(folder);
            const done = drain(w.say("list windows"));
            // An assertion below may leave this turn unread; its own failure is not the finding.
            done.catch(() => {});
            await until(() => w.starts.length === 1, "the bridge call reaches the windows executor");
            assert.equal(w.starts[0].call.id, "windows.list");
            w.starts[0].done({ outcome: "completed", content: "[]" });
            assert.deepEqual(await done, [{ kind: "text", text: "Listed." }, { kind: "done", reason: "stop" }]);
            const [mcp] = read("pi-log").filter(row => row.direction === "mcp").map(row => row.message);
            assert.ok(mcp.tools.includes("windows_list"));
            assert.equal(mcp.tools.some(name => name.startsWith("harness_")), false, "no harness row is offered");
            assert.deepEqual(mcp.result.result, { content: [{ type: "text", text: "[]" }], isError: false });
        },
        // A tool other than the bridge's that ran ends the conversation; a
        // name the model made up, which did not run, does not.
        async builtin(folder) {
            scenario({ turns: [[{ tool: { name: "made_up" } }, chunk("Fine."), { stop: "stop" }]] });
            const ok = make(folder);
            assert.deepEqual(await drain(ok.say("x")), [{ kind: "text", text: "Fine." }, { kind: "done", reason: "stop" }]);
            for (const owner of owners.splice(0)) owner();
            scenario({ turns: [[chunk("Running."), { tool: { name: "bash", durationMs: 3 } }, { stop: "stop" }]] });
            const w = make(folder);
            await assert.rejects(drain(w.say("run")), { message: "jarvis: brain=pi-builtin" });
            await until(() => livePrograms().length === 0, "the tripwire leaves no program");
            assert.throws(() => w.say("again"), { message: "jarvis: brain=pi-builtin" }, "the conversation is over");
        },
        // Only a reply that stopped completes a turn.
        async stops(folder) {
            for (const stop of ["error", "length"]) {
                scenario({ turns: [[chunk("Part"), { stop }]] });
                const w = make(folder);
                await assert.rejects(drain(w.say("x")), { message: "jarvis: brain=pi-stop-" + stop });
                for (const owner of owners.splice(0)) owner();
            }
        },
        // cancel sends abort and resolves on Pi's settled run; the next turn runs.
        async cancel(folder) {
            scenario({ turns: [[chunk("a"), { abort: true }], [chunk("b"), { stop: "stop" }]] });
            const w = make(folder);
            const iterator = w.say("long").events[Symbol.asyncIterator]();
            assert.deepEqual((await iterator.next()).value, { kind: "text", text: "a" });
            const rest = iterator.next();
            // An assertion below may leave this read pending; its own failure is not the finding.
            rest.catch(() => {});
            let timer;
            await Promise.race([w.brain.cancel(), new Promise((resolve, reject) => {
                timer = setTimeout(() => reject(new assert.AssertionError({ message: "cancel never acknowledged" })), 5000);
            })]).finally(() => clearTimeout(timer));
            assert.equal(received("abort").length, 1);
            await assert.rejects(rest, { message: "jarvis: brain=cancelled" });
            assert.deepEqual(await drain(w.say("next")), [{ kind: "text", text: "b" }, { kind: "done", reason: "stop" }]);
            validWrites();
        },
        // A dialog no one can answer is answered cancelled; a notice is not.
        async dialog(folder) {
            scenario({ turns: [[{ notice: "fyi" }, { dialog: "confirm" }, chunk("ok"), { stop: "stop" }]] });
            const w = make(folder);
            assert.deepEqual(await drain(w.say("x")), [{ kind: "text", text: "ok" }, { kind: "done", reason: "stop" }]);
            assert.deepEqual(received("extension_ui_response").map(m => [m.id, m.cancelled]), [["ui-1", true]]);
            validWrites();
        },
        // A program that exits mid-turn or during its handshake fails the turn with its exit.
        async exit(folder) {
            scenario({ turns: [[chunk("a"), { exit: 3 }]] });
            const w = make(folder);
            await assert.rejects(drain(w.say("x")), { message: "jarvis: brain=pi-exited code=3 signal=null" });
            assert.throws(() => w.say("again"), { message: "jarvis: brain=pi-exited code=3 signal=null" });
            for (const owner of owners.splice(0)) owner();
            scenario({ crash: "handshake", turns: [[{ stop: "stop" }]] });
            const h = make(folder);
            await assert.rejects(drain(h.say("x")), { message: "jarvis: brain=pi-exited code=3 signal=null" });
            assert.deepEqual(received("prompt"), [], "a failed handshake sends no prompt");
            await noProgramOrDir(h.runtime, "failed handshake");
        },
        // A refused command fails with its command alone.
        async refused(folder) {
            scenario({ refuse: "prompt", turns: [[{ stop: "stop" }]] });
            const w = make(folder);
            await assert.rejects(drain(w.say("x")), { message: "jarvis: brain=pi-refused command=prompt" });
        },
        async handshakeHang(folder) {
            scenario({ hang: "handshake", turns: [[{ stop: "stop" }]] });
            const w = make(shortBounds(folder));
            try {
                await assert.rejects(drain(w.say("x")), { message: /^jarvis: brain=pi-(closed|exited code=null signal=SIGKILL)$/ });
                assert.deepEqual(received("prompt"), []);
                await noProgramOrDir(w.runtime, "hung handshake");
            } finally { killLivePrograms(); }
        },
        async lineSize(folder) {
            scenario({ turns: [[{ raw: 8 * 1024 * 1024 }]] });
            const w = make(folder);
            await assert.rejects(drain(w.say("x")), { message: "jarvis: brain=pi-line-size" });
            await until(() => livePrograms().length === 0, "oversize line leaves no program");
        },
        // close ends the program, the bridge session and the private directory.
        async close(folder) {
            scenario({ turns: [[{ stop: "stop" }]] });
            const w = make(folder);
            await drain(w.say("x"));
            const socket = path.join(w.runtime, "tools.sock");
            assert.ok(fs.existsSync(socket));
            w.brain.close();
            await until(() => !fs.existsSync(socket), "the bridge session closes");
            await noProgramOrDir(w.runtime, "close");
            assert.throws(() => w.say("again"), { message: "jarvis: brain=pi-closed" });
        },
        // The plan's context bound in user turns: past it the chained engine
        // ends the conversation cleanly, as it does a wire brain's.
        async limit(folder) {
            scenario({ turns: Array.from({ length: 41 }, () => [{ stop: "stop" }]) });
            const { folder: engineFolder, Engine } = Fixture.copy(process.env.JARVIS_TEST_ROOT, [], folder);
            const w = make(engineFolder);
            const engine = Engine.create({ session: Session, state: () => w.runner.state, audit: w.audit, router: w.router,
                accounts: () => ({ secrets: null, choose: id => ({ kind: "accepted", account: { id, provider: "pi", label: "default",
                    source: { kind: "cli", directory: account }, model: "" } }) }),
                policy: () => ({ profile: "standard", cloudVision: "ask" }), fault: reason => assert.fail("fault " + reason),
                captionLimit: 4096, dispatch: e => w.runner.dispatch(e), clock: { now: () => 0, set: () => ({}), clear() {} },
                harness: { bridge: w.bridge, gate: null, env, runtime: () => w.runtime } });
            owners.unshift(() => engine.close());
            let plan;
            assert.doesNotThrow(() => { plan = engine.configure({ brain: "pi-fixture" }); }, "the engine has the Pi driver");
            assert.deepEqual(plan, { kind: "ready" });
            const { gen, turn: { op } } = w.runner.state;
            const send = text => new Promise(resolve => engine.brain.send({ gen, op, owner: 1, text },
                (verdict, detail) => resolve([verdict, detail])));
            for (let turn = 0; turn < 40; turn++) assert.deepEqual(await send("turn " + turn), ["brain-done", undefined]);
            assert.deepEqual(await send("one more"), ["brain-ended", { reason: "brain=context-limit" }]);
            assert.equal(received("prompt").length, 40);
        },
        // Verify: no tools, no MCP, one prompt after the release record.
        async probe(folder) {
            const Harness = require(path.join(folder, "backend/PiHarness.js"));
            const runtime = path.join(process.env.JARVIS_TEST_ROOT, "probe");
            const probe = () => Harness.probe({ directory: account, env, runtime, model: "", text: "Reply OK." });
            scenario({ reply: "OK" });
            assert.equal(await probe(), "OK");
            const call = program();
            assert.deepEqual(call.args.slice(LOCKDOWN.length, -2), ["--no-approve", "--no-tools", "--no-mcp"], "a probe has no tools");
            assert.equal(call.mcp, null);
            assert.deepEqual(fs.readdirSync(runtime), []);
            scenario({ reply: " " });
            await assert.rejects(probe(), { message: "jarvis: brain=pi-no-reply" });
            scenario({ turns: [[chunk("No."), { stop: "error" }]] });
            await assert.rejects(probe(), { message: "jarvis: brain=pi-stop-error" });
            const short = require(path.join(shortBounds(folder), "backend/PiHarness.js"));
            scenario({ turns: [[chunk("slow"), { abort: true }]] });
            await assert.rejects(short.probe({ directory: account, env, runtime, model: "", text: "x" }), { message: "jarvis: brain=pi-probe-deadline" });
            await noProgramOrDir(runtime, "hung probe");
            validWrites();
        },
        // The menu's models: the selected first, each narrowed to its names,
        // one a choice cannot carry left out, at most sixteen; no prompt.
        async models(folder) {
            const Harness = require(path.join(folder, "backend/PiHarness.js"));
            const runtime = path.join(process.env.JARVIS_TEST_ROOT, "models");
            const listed = [{ provider: "a", id: "one", name: "One", baseUrl: "https://example.invalid" },
                { provider: "b", id: "two" }, { provider: "c", id: "x".repeat(121) },
                ...Array.from({ length: 20 }, (_, i) => ({ provider: "d", id: "m" + i }))];
            scenario({ models: listed, state: { model: { provider: "b", id: "two" } } });
            const menu = await Harness.models({ directory: account, env, runtime });
            assert.deepEqual(menu.slice(0, 3), [{ provider: "b", id: "two" }, { provider: "a", id: "one" }, { provider: "d", id: "m0" }]);
            assert.equal(menu.length, 16);
            assert.deepEqual(received("prompt"), []);
            assert.deepEqual(program().args.slice(LOCKDOWN.length, -2), ["--no-approve", "--no-tools", "--no-mcp"]);
            const short = require(path.join(shortBounds(folder), "backend/PiHarness.js"));
            scenario({ hang: "handshake" });
            await assert.rejects(short.models({ directory: account, env, runtime }), { message: /^jarvis: brain=pi-(closed|exited code=null signal=SIGKILL)$/ });
            killLivePrograms();
            validWrites();
        },
        // Discovery finds ~/.pi/agent, the model read signs it in and the
        // menu offers "Pi / provider/id", which resolves to its model.
        // Verify writes the release record before the one prompt.
        async accounts(folder) {
            const runtime = path.join(process.env.JARVIS_TEST_ROOT, "accounts-runtime");
            const { judge, directory } = accounts(folder, runtime);
            fs.rmSync(path.join(directory, "audit"), { recursive: true, force: true });
            scenario({ reply: "OK" });
            const found = judge.discover();
            const pi = found.find(item => item.provider === "pi");
            assert.ok(pi, "discovery finds the Pi folder");
            assert.deepEqual([pi.source, pi.state, pi.marker], [{ kind: "cli", directory: account }, { kind: "unchecked" }, "present"]);
            assert.deepEqual(read("pi-calls"), [], "discovery starts no Pi program");
            assert.deepEqual(judge.status().brains.filter(choice => choice.value.startsWith(pi.id)), [], "no model is offered before the read");
            await judge.readModels();
            assert.deepEqual(pi.state, { kind: "signed-in" });
            const choices = judge.status().brains.filter(choice => choice.value.startsWith(pi.id));
            assert.deepEqual(choices, [{ value: pi.id + "/stub/stub-1", label: "Pi / stub/stub-1" }]);
            assert.deepEqual(judge.resolve(choices[0].value), { id: pi.id, provider: "pi", label: "default",
                source: { kind: "cli", directory: account }, model: "stub/stub-1" });
            assert.equal(judge.resolve(pi.id + "/no-slash"), null, "a reference Pi cannot name resolves to nothing");
            assert.deepEqual(judge.choose(choices[0].value).kind, "accepted");
            assert.deepEqual(await judge.verify(pi.id, "user"), { kind: "verified" });
            assert.deepEqual(read("pi-log").filter(row => row.direction === "audit").map(row => row.message.lines), [1],
                "the release record precedes the program's prompt");
            assert.deepEqual(received("prompt").map(m => m.message), ["Reply OK."]);
            assert.equal(read("pi-calls").some(call => call.args[0] === "auth"), false, "no Pi credential command runs");
            // A setup that lists no model is found, and offers none.
            scenario({ models: [] });
            judge.discover();
            await judge.readModels();
            const empty = judge.accounts.find(item => item.provider === "pi");
            assert.deepEqual(empty.state, { kind: "found" });
            assert.deepEqual(judge.status().brains.filter(choice => choice.value.startsWith(pi.id)), []);
        },
        // Without Pi installed the menu offers it no model.
        async absent(folder) {
            const runtime = path.join(process.env.JARVIS_TEST_ROOT, "absent-runtime");
            require(path.join(folder, "backend/Core.js")).use(tree);
            const { Accounts } = require(path.join(folder, "backend/Accounts.js"));
            const bare = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "bin-"));
            for (const tool of ["setpriv", "node", "python3", "env"])
                fs.symlinkSync(cp.execFileSync("/usr/bin/env", ["bash", "-c", "command -v " + tool], { encoding: "utf8" }).trim(), path.join(bare, tool));
            const judge = new Accounts(path.join(state, "vgshell/jarvis"), { ...env, PATH: bare }, undefined, runtime);
            judge.discover();
            await judge.readModels();
            const pi = judge.accounts.find(item => item.provider === "pi");
            assert.deepEqual(pi.state, { kind: "unavailable", reason: "command-missing" });
            assert.deepEqual(judge.status().brains.filter(choice => choice.value.startsWith(pi.id)), []);
        },
        // No credential crosses from Pi into Jarvis: the key planted in Pi's
        // own setup and the daemon's environment, which the stand-in puts in
        // every field Jarvis must leave unread, appears in no event, error,
        // status, audit record, state file or helper output.
        async credential(folder) {
            const runtime = path.join(process.env.JARVIS_TEST_ROOT, "credential-runtime");
            scenario({ leak: true, turns: [[{ notice: "n" }, chunk("Hi."), { tool: { name: "made_up" } }, { stop: "stop" }],
                [chunk("x"), { stop: "error" }]] });
            const w = make(folder);
            const seen = [];
            seen.push(...await drain(w.say("hi")));
            await w.say("again").events.next().then(value => seen.push(value), error => seen.push(error.message));
            assert.ok(read("pi-log").some(row => JSON.stringify(row).includes(PLANTED)), "the stand-in offered the key");
            for (const owner of owners.splice(0)) owner();
            scenario({ leak: true, refuse: "set_model", reply: "OK" });
            const Harness = require(path.join(folder, "backend/PiHarness.js"));
            await Harness.probe({ directory: account, env, runtime, model: "a/b", text: "x" }).catch(error => seen.push(error.message));
            scenario({ leak: true, reply: "OK" });
            seen.push(await Harness.models({ directory: account, env, runtime }));
            const { judge, directory } = accounts(folder, runtime);
            judge.discover();
            await judge.readModels();
            seen.push(judge.status(), judge.accounts);
            seen.push(await judge.verify(judge.accounts.find(item => item.provider === "pi").id, "user"));
            const helper = cp.spawnSync("node", [path.join(folder, "backend/accounts.js"), "--tree", tree, "presence",
                JSON.stringify(Object.fromEntries(require(path.join(folder, "AccountProviders.js")).PROVIDERS
                    .filter(row => row.variable).map(row => [row.variable, false])))],
            { env: { ...env, XDG_RUNTIME_DIR: path.dirname(path.dirname(runtime)) }, encoding: "utf8", timeout: 20000 });
            assert.equal(helper.status, 0, helper.stderr);
            assert.ok(JSON.parse(helper.stdout).brains.some(choice => choice.label === "Pi / stub/stub-1"), "the helper read the leaking Pi");
            seen.push(helper.stdout, helper.stderr);
            const text = JSON.stringify(seen);
            assert.equal(text.includes(PLANTED), false, "Jarvis never receives the key");
            for (const content of [...filesUnder(directory), ...filesUnder(w.root), ...filesUnder(runtime)])
                assert.equal(content.includes(PLANTED), false, "Jarvis never writes the key");
            for (const call of read("pi-calls"))
                for (const name of ["ANTHROPIC_API_KEY", "OPENAI_API_KEY"]) assert.equal(Object.hasOwn(call.env, name), false, name);
        }
    };

    async function variant(relative, edits, check) {
        const folder = copied(plugin, { [relative]: edits });
        await assert.rejects(check(folder), assert.AssertionError, relative + " variant must turn red: " + edits[0][0]);
        killLivePrograms();
        for (const owner of owners.splice(0)) owner();
    }

    try {
        for (const [name, check] of Object.entries(CASES)) {
            await check(plugin);
            for (const owner of owners.splice(0)) owner();
            cases++;
            console.log("case=" + name + " passed");
        }
        let controls = 0;
        const H = "backend/PiHarness.js", R = "backend/PiRpc.js", A = "backend/Accounts.js";
        for (const [name, relative, edits, row] of [
            ["tools-allowlist", H, [['"--tools", Pi.TOOL_PREFIX + "*"', '"--tools", "*"']], "turn"],
            ["extensions-off", H, [['"--no-extensions", ', ""]], "turn"],
            ["context-files", H, [['"--no-context-files", ', ""]], "turn"],
            ["account-folder", H, [["PI_CODING_AGENT_DIR: directory", "PI_CODING_AGENT_DIR: env.HOME"]], "turn"],
            ["token-file", H, [['[name, "${" + name + "}"]', "[name, bridge.env[name]]"]], "turn"],
            ["system-prompt", H, [["fs.writeFileSync(prompt, instructions,", 'fs.writeFileSync(prompt, "",']], "turn"],
            ["no-compaction", H, [["await p.call(id => Pi.noCompaction(id));", ""]], "turn"],
            ["set-model", H, [['if (model !== "") await p.call(id => Pi.setModel(id, Pi.model(model)));', ""]], "model"],
            ["model-shape", H, [['if (model !== "") Pi.model(model);', ""]], "model"],
            ["release-empty", H, [['if (labels.length === 0) fail("release-empty");', ""]], "release"],
            ["bridge-launch", H, [["instructions,\n                bridge: launch }", "instructions,\n                bridge: null }"]], "bridge"],
            ["tripwire", H, [["if (e.bridge) break;", "break;"]], "builtin"],
            ["tripwire-ends", H, [["session.program.abort(error);", ""]], "builtin"],
            ["ran-only", R, [["if (message.durationMs === undefined) return { kind: \"other\" };", ""]], "builtin"],
            ["stop-complete", H, [['current.stop === "stop" ? { kind: "complete" }', 'current.stop !== null ? { kind: "complete" }']], "stops"],
            ["abort-sent", H, [["session.program.call(id => Pi.abort(id)).catch(() => {});", ""]], "cancel"],
            ["dialog-cancel", H, [['case "dialog": current.program.write(Pi.cancelDialog(id)); return;', 'case "dialog": return;']], "dialog"],
            ["refusal-command", H, [['refused: call => new Error("jarvis: brain=pi-refused command=" + call.method)',
                'refused: () => new Error("jarvis: brain=pi-refused")']], "refused"],
            ["handshake-timer", H, [["timer = setTimeout(() => p.close(), HANDSHAKE_MS);", "timer = null;"]], "handshakeHang"],
            ["directory-removal", H, [["    await session.program.close();\n    fs.rmSync(session.cwd, { recursive: true, force: true });",
                "    await session.program.close();"]], "close"],
            ["bridge-close", H, [["launch?.close();", ""]], "close"],
            ["context-limit", H, [['if (turns >= TURNS) throw new Error("jarvis: brain=context-limit");', ""]], "limit"],
            ["probe-bare", H, [['const BARE = Object.freeze(["--no-approve", "--no-tools", "--no-mcp"]);', "const BARE = TURN;"]], "probe"],
            ["probe-reply", H, [['if (run.reply.trim() === "") fail("no-reply");', ""]], "probe"],
            ["probe-stop", H, [['if (run.aborted || run.stop !== "stop")', "if (run.aborted)"]], "probe"],
            ["probe-timer", H, [['timer = setTimeout(() => reject(new Error("jarvis: brain=pi-" + key + "-deadline")), deadline);', ""]], "probe"],
            ["menu-selected", R, [["const ordered = selected === null ? all", "const ordered = true ? all"]], "models"],
            ["menu-bound", R, [[".slice(0, MODELS));", "));"]], "models"],
            ["menu-fits", R, [["ordered.filter((m, i) => fits(m) && ", "ordered.filter((m, i) => "]], "models"],
            ["menu-narrow", R, [["return Object.freeze({ provider: value.provider, id: value.id });", "return Object.freeze({ ...value });"]], "credential"],
            ["refusal-unread", "backend/HarnessProgram.js", [["else call.reject(refused(call, value));", "else call.reject(new Error(JSON.stringify(value)));"]], "credential"],
            ["failure-narrow", R, [[": { kind: \"failure\", id: message.id, command: message.command };", ": { kind: \"failure\", id: message.id, command: message.command, error: message.error };"]], "credential"],
            ["stderr-dropped", "backend/HarnessProgram.js", [["child.stderr.resume();", "child.stderr.on(\"data\", chunk => process.stderr.write(chunk));"]], "credential"],
            ["environment-scrub", "backend/HarnessProgram.js", [["env: { ...childEnvironment(env), ...extra }", "env: { ...env, ...extra }"]], "credential"],
            ["models-state", A, [['item.state = { kind: item.models.length === 0 ? "found" : "signed-in" };', ""]], "accounts"],
            ["models-read", "backend/accounts.js", [["await Promise.all([judge.readEmails(), judge.readModels()]);\n        value = judge.status();",
                "await judge.readEmails();\n        value = judge.status();"]], "credential"],
            ["choice-model", A, [['const model = candidate.provider === "pi" && id.startsWith(account + "/") ? piModel(id.slice(account.length + 1)) : "";',
                'const model = "";']], "accounts"],
            ["choice-label", A, [['" / " + PiRpc.reference(model)).slice(0, 60)', ').slice(0, 60)']], "accounts"],
            ["handoff-route", A, [['case "pi":', 'case "pi-removed":']], "accounts"],
            ["handoff-audit", A, [["release.start(() => PiHarness.probe(", "(send => send())(() => PiHarness.probe("]], "accounts"],
            ["command-missing", A, [['? "command-missing" : key[1]', ': key[1]']], "absent"],
            ["harness-reason", A, [["(?:harness|codex|copilot|pi)-", "(?:harness|codex|copilot)-"]], "absent"],
            ["account-row", "AccountProviders.js", [['{ id: "pi", label: "Pi", kind: "cli", command: null },', ""]], "accounts"],
            ["engine-driver", "backend/ChainedEngine.js", [['"pi-rpc": PiHarness, ', ""]], "limit"]
        ]) {
            await variant(relative, edits, folder => CASES[row](folder));
            controls++;
            console.log("control=" + name + " detected");
        }
        console.log("test-jarvis-pi: ok cases=" + cases + " controls=" + controls);
    } finally { killLivePrograms(); for (const owner of owners.splice(0)) owner(); }
}, standins => {
    fs.copyFileSync(path.join(tree, "scripts/fixtures/jarvis-pi/pi-stub.js"), path.join(standins, "pi"));
    fs.chmodSync(path.join(standins, "pi"), 0o700);
}, 900000);
