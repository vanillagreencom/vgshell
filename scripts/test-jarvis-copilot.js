#!/usr/bin/env node
// The Copilot ACP harness end to end in J09: the real Session reducer,
// SessionRunner, ToolRouter, Policy, Denied, Audit, ToolBridge with the real
// mcp-shim, HarnessGate and CopilotHarness, against
// fixtures/jarvis-copilot/copilot-stub.js as the Copilot program. The stub
// answers with the sanitized Copilot 1.0.91 handshake, recorded from the
// GitHub Copilot CLI 1.0.91 binary whose SHA-256 is
// 5ba1d69542af6fd91702d4dbf4845f41c0a29efa3e9bc56fcc308347ff70ff3e. The
// recording command was `env -i PATH=/usr/bin:/bin HOME=<scratch>
// COPILOT_HOME=<scratch> unshare -rn copilot --acp --stdio`, followed by
// initialize and session/new on stdin. No vendor program, login, account or
// network is used. Mutants edit disposable plugin copies.
"use strict";
const { assert, fs, path, tree, world, seed } = require("./fixtures/jarvis/policy.js");
const Check = require("./fixtures/schema-check.js");
const excerpt = require("./fixtures/jarvis-copilot/acp.schema.json");
const { load } = require("../bin/lib/qml-library.js");
const Fixture = require("./fixtures/jarvis/engine.js");
const cp = require("node:child_process");
const plugin = path.join(tree, "shell/plugins/vgs.jarvis");
const PARAMS = { "initialize": "InitializeRequest", "session/new": "NewSessionRequest", "session/prompt": "PromptRequest",
    "session/cancel": "CancelNotification" };
const AVAILABLE = ["vgs_jarvis/*"];
const DENIED = ["shell", "write", "read", "url", "memory"];
const BUILTIN_KINDS = ["read", "edit", "delete", "move", "search", "execute", "fetch", "switch_mode"];

world(async () => {
    const Session = load(path.join(plugin, "Session.js"));
    const fixtures = seed();
    const state = process.env.XDG_STATE_HOME;
    fs.copyFileSync(path.join(tree, "scripts/fixtures/jarvis-copilot/recorded.ndjson"), path.join(state, "copilot-recorded.ndjson"));
    const account = path.join(process.env.HOME, ".copilot");
    const secondAccount = path.join(process.env.HOME, ".1copilot");
    fs.mkdirSync(account);
    fs.mkdirSync(secondAccount);
    const env = { PATH: process.env.PATH, HOME: process.env.HOME, XDG_CONFIG_HOME: process.env.XDG_CONFIG_HOME,
        XDG_STATE_HOME: state, XDG_DATA_HOME: process.env.XDG_DATA_HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
        GH_TOKEN: "fixture-secret-private", COPILOT_GITHUB_TOKEN: "fixture-secret-private", VGSH_RUNNER_PID: "1" };
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
        for (const name of ["copilot-log", "copilot-calls"]) fs.rmSync(path.join(state, name), { force: true });
        fs.writeFileSync(path.join(state, "copilot-scenario.json"), JSON.stringify(value));
    }
    const program = () => read("copilot-calls").at(-1);
    const alive = pid => { try { process.kill(pid, 0); return true; } catch { return false; } };
    const livePrograms = () => read("copilot-calls").filter(call => Number.isSafeInteger(call.pid) && alive(call.pid));
    function killLivePrograms() { for (const call of livePrograms()) try { process.kill(call.pid, "SIGKILL"); } catch {} }
    async function noProgramOrDir(runtime, label) {
        await until(() => livePrograms().length === 0, label + " leaves no program");
        await until(() => fs.readdirSync(runtime).every(name => !name.startsWith("copilot-")), label + " removes its directory");
    }
    const received = method => read("copilot-log").filter(row => row.direction === "in" && row.message.method === method).map(row => row.message);
    // The answers the harness wrote to the stub's requests of this method.
    function answered(method) {
        const log = read("copilot-log");
        const asked = log.filter(row => row.direction === "out" && row.message.method === method).map(row => row.message.id);
        return log.filter(row => row.direction === "in" && row.message.method === undefined && asked.includes(row.message.id))
            .map(row => row.message);
    }
    function validWrites() {
        const log = read("copilot-log");
        for (const { direction, message } of log) {
            if (direction !== "in") continue;
            if (message.method !== undefined) {
                assert.deepEqual(Check.errors(excerpt, message.id === undefined ? "JSONRPCNotification" : "JSONRPCRequest", message), [], message.method);
                assert.deepEqual(Check.errors(excerpt, PARAMS[message.method], message.params), [], message.method);
            } else assert.deepEqual(Check.errors(excerpt, message.error ? "JSONRPCError" : "JSONRPCResponse", message), [], "answer");
        }
        for (const row of log.filter(row => row.direction === "out" && row.message.method === "session/request_permission")) {
            const answer = log.find(entry => entry.direction === "in" && entry.message.method === undefined && entry.message.id === row.message.id);
            if (answer?.message.result) assert.deepEqual(Check.errors(excerpt, "RequestPermissionResponse", answer.message.result), []);
        }
        for (const row of log.filter(row => row.direction === "out")) {
            const message = row.message;
            if (message.method === "session/update") assert.deepEqual(Check.errors(excerpt, "SessionNotification", message.params), [], "stub update");
            if (message.method === "session/request_permission")
                assert.deepEqual(Check.errors(excerpt, "RequestPermissionRequest", message.params), [], "stub request");
        }
    }

    /** One daemon-side world loaded from a plugin folder. */
    function make(folder = plugin, options = {}) {
        const need = name => require(path.join(folder, "backend", name));
        const Router = need("ToolRouter.js"), Bridge = need("ToolBridge.js"), Audit = need("Audit.js"), Gate = need("HarnessGate.js");
        need("Core.js").use(tree);
        const Policy = need("Policy.js"), Denied = need("Denied.js"), Harness = need("CopilotHarness.js"), Providers = need("Providers.js");
        const { SessionRunner, unavailable } = need("session-runner.js");
        const root = path.join(process.env.JARVIS_TEST_ROOT, "a" + ++serial);
        fs.mkdirSync(root);
        let at = 0, transcript;
        const starts = [], harnessRequests = [];
        const audit = Audit.create({ state: path.join(root, "state"), now: () => Date.UTC(2026, 9, 2) });
        const rows = () => { const file = path.join(root, "state/audit/2026-10-02.jsonl");
            return fs.existsSync(file) ? fs.readFileSync(file, "utf8").trim().split("\n").map(line => JSON.parse(line)) : []; };
        const ports = { ...unavailable(), mute: { store() {} }, transcript() {},
            capture: { open: (e, done) => done(), close: (e, done) => done(), collect: (e, done) => { transcript = done; } },
            brain: { send() {}, cancel: (e, done) => done(), close() {} } };
        const runner = new SessionRunner(Session, ports, { now: () => at, set: () => ({}), clear() {} }, () => {});
        let bridge = null, gate = null;
        const router = Router.create({ session: Session, state: () => runner.state, dispatch: e => runner.dispatch(e),
            context: () => ({ profile: options.profile ?? "standard", locked: false, denied: Denied.create(fixtures.roots) }),
            audit, result: value => gate.deliver(value) || bridge.deliver(value) });
        Object.assign(ports, router.ports);
        router.register("windows", { commands: ["hyprctl"], timeoutMs: 1000, cancellable: false,
            start: (call, done) => starts.push({ call, done }) });
        const owner = Gate.create({ router, state: () => runner.state });
        gate = { ...owner, ask(gen, proposal, port) { harnessRequests.push(proposal); return owner.ask(gen, proposal, port); } };
        router.register("harness", gate.executor);
        const runtime = path.join(process.env.JARVIS_TEST_ROOT, "r" + serial.toString(36));
        bridge = Bridge.create({ router, state: () => runner.state, audit, directory: runtime,
            release: { prepare: () => Promise.resolve([]) } });
        runner.dispatch({ type: "snapshot", locked: false, engine: "chained", configured: true, settings: {} });
        runner.dispatch({ type: "indicator", shown: true });
        runner.dispatch({ type: "talk-down" });
        transcript("final", "fixture user");
        const recipients = Policy.recipients({ conversation: "copilot-" + serial, profile: "standard", cloudVision: "ask",
            brain: { kind: "network", provider: "copilot", account: "fixture", origin: "https://api.githubcopilot.com" },
            speech: [{ kind: "local", provider: "fixture-speech", account: "" }] });
        const create = (value = bridge) => Harness.create({ provider: Providers.select("copilot"), model: options.model ?? "",
            recipients, account: { kind: "cli", directory: account }, gen: runner.state.gen,
            harness: { bridge: value, gate, env, runtime: () => runtime } });
        const brain = create();
        brain.start({ instructions: "Be brief.", tools: [] });
        owners.push(() => { brain.close(); bridge.close(); gate.close(); audit.close(); });
        return { Policy, Harness, runner, router, gate, bridge, brain, rows, starts, harnessRequests, runtime, recipients, audit, create,
            time: value => { at = value; },
            show: () => runner.dispatch({ type: "shown", gen: runner.state.gen, op: runner.state.approval.op, id: runner.state.approval.id }),
            confirm: () => runner.dispatch({ type: "confirm", gen: runner.state.gen, id: runner.state.approval.id,
                digest: runner.state.approval.digest, source: "key" }),
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
    const chunk = text => ({ update: { sessionUpdate: "agent_message_chunk", content: { type: "text", text } } });
    const announce = (kind, extra = {}) => ({ update: { sessionUpdate: "tool_call", toolCallId: "call-1", title: "fixture " + kind,
        kind, status: "pending", ...extra } });
    const progress = status => ({ update: { sessionUpdate: "tool_call_update", toolCallId: "call-1", status } });
    const OPTIONS = [{ optionId: "allow-always", name: "Always allow", kind: "allow_always" },
        { optionId: "allow-once", name: "Allow", kind: "allow_once" }, { optionId: "reject-once", name: "Reject", kind: "reject_once" }];
    const permission = (call = {}, extra = {}) => ({ request: "session/request_permission",
        params: { sessionId: "$SESSION", toolCall: { toolCallId: "call-1", ...call }, options: OPTIONS, ...extra } });
    const newFile = path.join(fixtures.project, "new");
    const existing = path.join(fixtures.project, "existing");
    const diff = file => [{ type: "diff", path: file, oldText: null, newText: "fixture\n" }];
    const outcomes = method => answered(method).map(m => m.result?.outcome ?? m.error?.code);
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
    const shortBounds = folder => copied(folder, { "backend/CopilotHarness.js": [
        ["const HANDSHAKE_MS = 30000;", "const HANDSHAKE_MS = 20;"],
        ["const PROBE_MS = 60000;", "const PROBE_MS = 20;"]
    ], "backend/HarnessProgram.js": [
        ["const CLOSE_MS = 2000;", "const CLOSE_MS = 20;"]
    ] });

    const CASES = {
        // The lockdown argv, the scrubbed environment, the bridge as the only
        // configured MCP server in a private file, none in session/new, and
        // the instructions leading the first prompt only.
        async turn(folder) {
            scenario({ turns: [[chunk("Hel"), chunk("lo."), { stop: "end_turn" }], [chunk("Again."), { stop: "end_turn" }]] });
            const w = make(folder);
            assert.deepEqual(await drain(w.say("hi")), [{ kind: "text", text: "Hel" }, { kind: "text", text: "lo." }, { kind: "done", reason: "stop" }]);
            const call = program();
            assert.deepEqual(call.args.slice(call.args.indexOf("--available-tools") + 1, call.args.indexOf("--deny-tool")), AVAILABLE,
                "only the bridge tool namespace is visible");
            assert.equal(call.args.includes("--excluded-tools"), false, "deny lists are not used with the allow-list");
            assert.deepEqual(call.args.slice(call.args.indexOf("--deny-tool") + 1, call.args.indexOf("--allow-tool")), DENIED);
            const configAt = call.args.indexOf("--additional-mcp-config");
            assert.deepEqual(call.args.slice(call.args.indexOf("--allow-tool"), configAt), ["--allow-tool", "vgs_jarvis"], "only the bridge runs unprompted");
            for (const flag of ["--acp", "--stdio", "--no-custom-instructions", "--disable-builtin-mcps", "--disallow-temp-dir", "--no-ask-user", "--no-auto-update"])
                assert.ok(call.args.includes(flag), flag);
            assert.equal(call.args.some(arg => /allow-all|yolo|autopilot/.test(arg)), false, "no standing grant");
            assert.equal(call.args.includes("--enable-memory"), false, "Copilot's own memory is never turned on");
            assert.equal(call.args.slice(0, 4).join(" "), "--acp --stdio --no-auto-update --no-custom-instructions");
            assert.equal(call.deathsig, 9, "setpriv keeps the program tied to the daemon");
            assert.equal(call.env.COPILOT_HOME, account, "the account's own directory");
            assert.equal(call.env.COPILOT_PROVIDERS_CONFIG, path.join(call.cwd, "no-providers/providers.json"));
            assert.equal(fs.existsSync(path.dirname(call.env.COPILOT_PROVIDERS_CONFIG)), false, "BYOK config path fails closed");
            for (const name of ["GH_TOKEN", "COPILOT_GITHUB_TOKEN", "VGSH_RUNNER_PID", "VGS_JARVIS_TOOLS_TOKEN"])
                assert.equal(Object.hasOwn(call.env, name), false, name + " stays out of the program's environment");
            assert.equal(path.dirname(call.cwd), w.runtime, "a private working directory");
            const [open] = received("session/new");
            assert.equal(open.params.cwd, call.cwd);
            assert.deepEqual(open.params.mcpServers, [], "Copilot drops a stdio server sent in session/new");
            assert.deepEqual(Object.keys(call.config.body.mcpServers), ["vgs_jarvis"]);
            const server = call.config.body.mcpServers.vgs_jarvis;
            assert.equal(server.type, "stdio");
            const token = server.env.VGS_JARVIS_TOOLS_TOKEN;
            assert.match(token, /^[0-9a-f]{64}$/);
            assert.equal(JSON.stringify(call.args).includes(token), false, "the token stays out of argv");
            assert.equal(call.config.mode, 0o600, "the config file is private");
            assert.deepEqual(call.args.slice(configAt, configAt + 2), ["--additional-mcp-config", "@" + path.join(call.cwd, "mcp.json")]);
            assert.deepEqual(await drain(w.say("more")), [{ kind: "text", text: "Again." }, { kind: "done", reason: "stop" }]);
            assert.deepEqual(received("session/prompt").map(m => m.params.prompt.map(block => block.text)),
                [["Be brief.", "hi"], ["more"]], "instructions lead the first prompt alone");
            assert.equal(read("copilot-calls").length, 1, "one program per conversation");
            validWrites();
        },
        // A model chosen for the account reaches the program.
        async model(folder) {
            scenario({ turns: [[{ stop: "end_turn" }]] });
            const w = make(folder, { model: "claude-sonnet-5.5" });
            await drain(w.say("hi"));
            assert.deepEqual(program().args.slice(-2), ["--model", "claude-sonnet-5.5"]);
        },
        // Only released content reaches the program; a file needs a grant.
        async release(folder) {
            scenario({ turns: [[{ stop: "end_turn" }]] });
            const w = make(folder);
            const reply = w.brain.send({ kind: "user", items: [w.Policy.item("spoken", ["speech"]), w.Policy.item("secret notes", ["file"])] });
            assert.deepEqual([[...reply.release.labels], [...reply.release.needed]], [["speech"], ["file"]]);
            await drain(reply);
            const promptText = received("session/prompt")[0].params.prompt[1].text;
            assert.ok(promptText.includes("spoken"));
            assert.equal(promptText.includes("secret notes"), false);
            const empty = make(folder);
            await assert.rejects(drain(empty.say("only a file", ["file"])), { message: "jarvis: brain=copilot-release-empty" });
        },
        // An allowed edit: announced pending, asked, audited before the
        // program is told to proceed, then reported done.
        async allowed(folder) {
            scenario({ turns: [[announce("edit", { locations: [{ path: newFile }], content: diff(newFile) }),
                permission({ kind: "edit" }), progress("in_progress"), progress("completed"), chunk("Done."), { stop: "end_turn" }]] });
            const w = make(folder);
            await drain(w.say("make a file"));
            assert.deepEqual(outcomes("session/request_permission"), [{ outcome: "selected", optionId: "allow-once" }]);
            assert.deepEqual(w.rows().filter(row => row.kind === "action").map(row => [row.tool, row.decision, row.outcome]),
                [["harness.files", "allow", "pending"], ["harness.files", "allow", "completed"]]);
            validWrites();
        },
        // An overwrite is held for physical confirmation; the program waits.
        async held(folder) {
            scenario({ turns: [[announce("edit", { locations: [{ path: existing }] }), permission({ kind: "edit" }),
                progress("completed"), { stop: "end_turn" }]] });
            const w = make(folder);
            const done = drain(w.say("edit it"));
            // An assertion below may leave this turn unread; its own failure is not the finding.
            done.catch(() => {});
            await until(() => w.runner.state.approval.kind === "held", "the approval is held");
            assert.equal(w.runner.state.approval.physical, true);
            assert.equal(w.runner.state.approval.tool, "harness.files");
            assert.deepEqual(answered("session/request_permission"), [], "no answer before the user confirms");
            w.show(); w.time(700); w.confirm();
            await done;
            assert.deepEqual(outcomes("session/request_permission"), [{ outcome: "selected", optionId: "allow-once" }]);
            const actionRows = w.rows().filter(row => row.kind === "action");
            assert.deepEqual(actionRows.map(row => [row.decision, row.confirmed, row.outcome]),
                [["confirm", "none", "pending"], ["confirm", "physical", "pending"], ["confirm", "physical", "completed"]]);
            assert.deepEqual(w.harnessRequests.at(-1).arguments.write, [existing]);
            assert.deepEqual(actionRows.at(-1).args, { write: "[redacted]", move: "[redacted]", remove: "[redacted]", diff: "[redacted]" });
        },
        // Refusals: a protected path, the program's own command, a read. A
        // refused call the program then reports failed is no built-in.
        async refused(folder) {
            const blocked = path.join(fixtures.home, ".ssh", "id_fixture");
            scenario({ turns: [[announce("edit", { locations: [{ path: blocked }] }), permission({ kind: "edit" }), progress("failed"),
                permission({ toolCallId: "call-2", kind: "execute", rawInput: { command: "cat ~/.ssh/id_fixture" } }),
                permission({ toolCallId: "call-3", kind: "read", locations: [{ path: existing }] }),
                { update: { sessionUpdate: "tool_call_update", toolCallId: "call-3", kind: "read", status: "failed" } },
                { stop: "end_turn" }]] });
            const w = make(folder);
            assert.deepEqual(await drain(w.say("try")), [{ kind: "done", reason: "stop" }]);
            assert.deepEqual(outcomes("session/request_permission"), [1, 2, 3].map(() => ({ outcome: "selected", optionId: "reject-once" })));
            assert.deepEqual(w.rows().filter(row => row.kind === "action").map(row => [row.tool, row.decision, row.outcome]),
                [["harness.files", "refuse", "cancelled"], ["harness.command", "refuse", "cancelled"], ["unknown", "refuse", "cancelled"]]);
            validWrites();
        },
        // A request outside the live prompt, or one without a one-time allow,
        // never reaches the router.
        async stale(folder) {
            scenario({ turns: [[permission({ kind: "edit", locations: [{ path: newFile }] }, { sessionId: "another-session" }),
                permission({ kind: "edit", locations: [{ path: newFile }] }, { options: OPTIONS.filter(o => o.kind !== "allow_once") }),
                { stop: "end_turn" }]] });
            const w = make(folder);
            await drain(w.say("x"));
            assert.deepEqual(outcomes("session/request_permission"), [1, 2].map(() => ({ outcome: "selected", optionId: "reject-once" })));
            assert.deepEqual(w.rows().filter(row => row.kind === "action"), []);
        },
        // The bridge's own tool calls run through the real shim and router,
        // reported as Copilot 1.0.91 reports a bridge call with a path
        // argument (kind read); a file system or terminal request is refused,
        // as none was offered.
        async bridge(folder) {
            scenario({ turns: [[announce("read", { title: "vgs_jarvis-windows_list", locations: [{ path: existing }] }),
                { mcp: { tool: "windows_list", arguments: {} } }, progress("in_progress"),
                { request: "fs/read_text_file", params: { sessionId: "$SESSION", path: existing } },
                { request: "terminal/create", params: { sessionId: "$SESSION", command: "sh" } },
                progress("completed"), { stop: "end_turn" }]] });
            const w = make(folder);
            const done = drain(w.say("list windows"));
            // An assertion below may leave this turn unread; its own failure is not the finding.
            done.catch(() => {});
            await until(() => w.starts.length === 1, "the bridge call reaches the windows executor");
            assert.equal(w.starts[0].call.id, "windows.list");
            w.starts[0].done({ outcome: "completed", content: "[]" });
            await done;
            const [mcp] = read("copilot-log").filter(row => row.direction === "mcp").map(row => row.message);
            assert.ok(mcp.tools.includes("windows_list"));
            assert.equal(mcp.tools.some(name => name.startsWith("harness_")), false, "no harness row is offered");
            assert.deepEqual(mcp.result.result, { content: [{ type: "text", text: "[]" }], isError: false });
            assert.deepEqual([...outcomes("fs/read_text_file"), ...outcomes("terminal/create")], [-32601, -32601]);
            validWrites();
        },
        // A built-in operation that runs without asking refuses the brain and
        // ends its program for every ACP kind Jarvis classifies as a built-in.
        async builtin(folder) {
            for (const kind of BUILTIN_KINDS) {
                scenario({ turns: [[announce(kind, { locations: [{ path: existing }] }), chunk("Running."),
                    { update: { sessionUpdate: "tool_call_update", toolCallId: "call-1", status: "in_progress" } }, { stop: "end_turn" }]] });
                const w = make(folder);
                await assert.rejects(drain(w.say(kind)), { message: "jarvis: brain=copilot-builtin kind=" + kind });
                await until(() => livePrograms().length === 0, kind + " leaves no program");
                assert.throws(() => w.say("again"), { message: "jarvis: brain=copilot-builtin kind=" + kind }, "the conversation is over");
                assert.deepEqual(w.rows().filter(row => row.kind === "action"), []);
                for (const owner of owners.splice(0)) owner();
            }
        },
        // A built-in call is not the bridge's for a title alone: another
        // server's name, a tool the bridge does not serve, or an argument the
        // bridge tool does not declare still ends the conversation.
        async foreignTitle(folder) {
            for (const [label, kind, extra] of [
                ["another server", "read", { title: "vgs_jarvisx-windows_list" }],
                ["an unserved tool", "execute", { title: "vgs_jarvis-shell", rawInput: {} }],
                ["an undeclared argument", "execute", { title: "vgs_jarvis-windows_list", rawInput: { command: "sh" } }]]) {
                scenario({ turns: [[announce(kind, extra), progress("completed"), { stop: "end_turn" }]] });
                const w = make(folder);
                await assert.rejects(drain(w.say(label)), { message: "jarvis: brain=copilot-builtin kind=" + kind }, label);
                for (const owner of owners.splice(0)) owner();
            }
        },
        // The program's handshake must name the agent at its floor, signed in.
        async handshake(folder) {
            for (const [label, value, message] of [
                ["agent", { agent: { name: "Other" } }, "jarvis: brain=copilot-agent"],
                ["floor", { agent: { version: "1.0.59" } }, "jarvis: brain=copilot-agent-version"],
                ["signed-out", { signedOut: true }, "jarvis: brain=copilot-signed-out"],
                ["crash", { crash: "handshake" }, "jarvis: brain=copilot-exited code=3 signal=null"]
            ]) {
                scenario({ ...value, turns: [[{ stop: "end_turn" }]] });
                const w = make(folder);
                await assert.rejects(drain(w.say("x")), { message }, label);
                assert.deepEqual(received("session/prompt"), [], label + " sends no prompt");
                await until(() => fs.readdirSync(w.runtime).every(name => !name.startsWith("copilot-")), label + " removes its directory");
            }
        },
        async handshakeHang(folder) {
            const copied = shortBounds(folder);
            scenario({ hang: "handshake", turns: [[{ stop: "end_turn" }]] });
            const w = make(copied);
            try {
                await assert.rejects(drain(w.say("x")), { message: "jarvis: brain=copilot-closed" });
                assert.deepEqual(received("session/prompt"), []);
                await noProgramOrDir(w.runtime, "hung handshake");
            } finally { killLivePrograms(); }
        },
        async closeHandshake(folder) {
            const folderCopy = copied(folder, { "backend/CopilotHarness.js": [
                ["const HANDSHAKE_MS = 30000;", "const HANDSHAKE_MS = 1000;"],
                ["const PROBE_MS = 60000;", "const PROBE_MS = 20;"]
            ], "backend/HarnessProgram.js": [
                ["const CLOSE_MS = 2000;", "const CLOSE_MS = 20;"]
            ] });
            scenario({ hang: "handshake", turns: [[{ stop: "end_turn" }]] });
            const w = make(folderCopy);
            const pending = drain(w.say("x"));
            pending.catch(() => {});
            await until(() => program() !== undefined, "the program starts handshaking");
            w.brain.close();
            await assert.rejects(pending, { message: "jarvis: brain=cancelled" });
            await noProgramOrDir(w.runtime, "close during handshake");
        },
        async lineSize(folder) {
            scenario({ turns: [[{ raw: 8 * 1024 * 1024 }]] });
            const w = make(folder);
            await assert.rejects(drain(w.say("x")), { message: "jarvis: brain=copilot-line-size" });
            await until(() => livePrograms().length === 0, "oversize line leaves no program");
        },
        async foreignSession(folder) {
            scenario({ turns: [[{ updateRaw: { sessionId: "foreign", update: { sessionUpdate: "agent_message_chunk", content: { type: "text", text: "wrong" } } } },
                chunk("right"), { stop: "end_turn" }]] });
            const w = make(folder);
            assert.deepEqual(await drain(w.say("x")), [{ kind: "text", text: "right" }, { kind: "done", reason: "stop" }]);
        },
        // cancel answers a held request cancelled, then cancels the prompt
        // and resolves on its stop reason.
        async cancel(folder) {
            scenario({ turns: [[chunk("a"), announce("edit", { locations: [{ path: existing }] }), permission({ kind: "edit" }),
                { cancel: true }, { stop: "cancelled" }]] });
            const w = make(folder);
            const iterator = w.say("long").events[Symbol.asyncIterator]();
            assert.deepEqual((await iterator.next()).value, { kind: "text", text: "a" });
            const rest = iterator.next();
            // An assertion below may leave this read pending; its own failure is not the finding.
            rest.catch(() => {});
            await until(() => w.runner.state.approval.kind === "held", "the approval is held");
            let timer;
            await Promise.race([w.brain.cancel(), new Promise((resolve, reject) => {
                timer = setTimeout(() => reject(new assert.AssertionError({ message: "cancel never acknowledged" })), 5000);
            })]).finally(() => clearTimeout(timer));
            assert.deepEqual(outcomes("session/request_permission"), [{ outcome: "cancelled" }]);
            const log = read("copilot-log").filter(row => row.direction === "in");
            assert.ok(log.findIndex(row => row.message.result?.outcome?.outcome === "cancelled")
                < log.findIndex(row => row.message.method === "session/cancel"), "the request is answered before the cancel");
            await assert.rejects(rest, { message: "jarvis: brain=cancelled" });
            validWrites();
        },
        // close ends the program, the bridge session and the private directory.
        async close(folder) {
            scenario({ turns: [[{ stop: "end_turn" }]] });
            const w = make(folder);
            await drain(w.say("x"));
            const socket = path.join(w.runtime, "tools.sock");
            assert.ok(fs.existsSync(socket));
            w.brain.close();
            await until(() => !fs.existsSync(socket), "the bridge session closes");
            await until(() => fs.readdirSync(w.runtime).every(name => !name.startsWith("copilot-")), "the directory is removed");
            await until(() => !process.getActiveResourcesInfo().includes("ProcessWrap"), "the program exits");
            assert.throws(() => w.say("again"), { message: "jarvis: brain=copilot-closed" });
        },
        // A close while the bridge session is still opening ends that session
        // too, so the next conversation opens its own.
        async opening(folder) {
            scenario({ turns: [[{ stop: "end_turn" }]] });
            const w = make(folder);
            let opened = null;
            const send = value => value.send({ kind: "user", items: [w.Policy.item("x", ["speech"])] });
            const first = w.create({ open: value => (opened = w.bridge.open(value)) });
            first.start({ instructions: "Be brief.", tools: [] });
            const pending = drain(send(first));
            assert.notEqual(opened, null, "the bridge session is opening");
            first.close();
            await assert.rejects(pending, { message: "jarvis: brain=cancelled" });
            // The harness's own continuation of this open runs first.
            await opened;
            const next = w.create();
            owners.unshift(() => next.close());
            next.start({ instructions: "Be brief.", tools: [] });
            await assert.doesNotReject(drain(send(next)), "a later conversation opens its bridge session");
        },
        // The plan's context bound in user turns: past it the chained engine
        // ends the conversation cleanly, as it does a wire brain's.
        async limit(folder) {
            scenario({ turns: Array.from({ length: 41 }, () => [{ stop: "end_turn" }]) });
            // The world loads the engine's own module copies: a recipient set is
            // judged by the Policy module that made it.
            const { folder: copied, Engine } = Fixture.copy(process.env.JARVIS_TEST_ROOT, [], folder);
            const w = make(copied);
            const engine = Engine.create({ session: Session, state: () => w.runner.state, audit: w.audit, router: w.router,
                accounts: () => ({ secrets: null, choose: id => ({ kind: "accepted", account: { id, provider: "copilot", label: "default",
                    source: { kind: "cli", directory: account }, model: "" } }) }),
                policy: () => ({ profile: "standard", cloudVision: "ask" }), fault: reason => assert.fail("fault " + reason),
                captionLimit: 4096, dispatch: e => w.runner.dispatch(e), clock: { now: () => 0, set: () => ({}), clear() {} },
                harness: { bridge: w.bridge, gate: w.gate, env, runtime: () => w.runtime } });
            owners.unshift(() => engine.close());
            let plan;
            assert.doesNotThrow(() => { plan = engine.configure({ brain: "copilot-fixture" }); }, "the engine has the ACP driver");
            assert.deepEqual(plan, { kind: "ready" });
            const { gen, turn: { op } } = w.runner.state;
            const send = text => new Promise(resolve => engine.brain.send({ gen, op, owner: 1, text },
                (verdict, detail) => resolve([verdict, detail])));
            for (let turn = 0; turn < 40; turn++) assert.deepEqual(await send("turn " + turn), ["brain-done", undefined]);
            assert.deepEqual(await send("one more"), ["brain-ended", { reason: "brain=context-limit" }]);
            assert.equal(received("session/prompt").length, 40);
        },
        // Account discovery and Verify on a Copilot directory: no status
        // command runs, then the release record precedes the one probe prompt.
        async verify(folder) {
            require(path.join(folder, "backend/Core.js")).use(tree);
            const { Accounts } = require(path.join(folder, "backend/Accounts.js"));
            const directory = path.join(state, "vgshell/jarvis");
            fs.rmSync(path.join(directory, "audit"), { recursive: true, force: true });
            const runtime = path.join(process.env.JARVIS_TEST_ROOT, "verify-runtime");
            const judge = new Accounts(directory, env, undefined, runtime);
            scenario({ reply: "OK" });
            const found = judge.discover();
            const copilot = found.find(item => item.provider === "copilot");
            assert.ok(copilot, "discovery finds the Copilot directory");
            assert.deepEqual([copilot.source, copilot.state, copilot.marker], [{ kind: "cli", directory: account }, { kind: "unchecked" }, "absent"]);
            assert.deepEqual(read("copilot-calls"), [], "discovery starts no Copilot program");
            assert.deepEqual(judge.resolve(copilot.id), { id: copilot.id, provider: "copilot", label: "default",
                source: { kind: "cli", directory: account }, model: "" });
            const choices = judge.status().brains.filter(choice => found.some(item => item.provider === "copilot" && item.id === choice.value));
            assert.deepEqual(choices.map(choice => choice.label).sort(), ["GitHub Copilot / 1", "GitHub Copilot / default"]);
            const accountRows = judge.status().accounts.filter(row => row.label.startsWith("GitHub Copilot /"));
            assert.deepEqual(accountRows.map(row => [row.state, row.value]).sort(), [["unchecked", "present"], ["unchecked", "present"]]);
            assert.deepEqual(await judge.verify(copilot.id, "user"), { kind: "verified" });
            assert.deepEqual(read("copilot-log").filter(row => row.direction === "audit").map(row => row.message.lines), [1],
                "the release record precedes the program's prompt");
            const promptBlocks = received("session/prompt").map(m => m.params.prompt.map(block => block.text));
            assert.equal(promptBlocks.length, 1);
            assert.equal(promptBlocks[0].length, 2);
            assert.equal(promptBlocks[0][1], "Reply OK.");
            assert.equal(path.dirname(program().cwd), runtime, "the owner's runtime directory");
            const audit = fs.readdirSync(path.join(directory, "audit")).flatMap(name =>
                fs.readFileSync(path.join(directory, "audit", name), "utf8").trim().split("\n").map(line => JSON.parse(line)));
            assert.deepEqual(audit.map(row => [row.kind, row.decision, row.outcome]),
                [["release", "send", "pending"], ["release", "send", "completed"]]);
            // The helper the accounts terminal runs: a signed-out program is its keyed refusal.
            scenario({ signedOut: true });
            const helper = cp.spawnSync("node", [path.join(folder, "backend/accounts.js"), "--tree", tree, "verify", copilot.id, "user"],
                { env, encoding: "utf8", timeout: 30000 });
            assert.deepEqual([helper.status, helper.stdout, helper.stderr],
                [69, JSON.stringify({ kind: "unavailable", reason: "copilot-signed-out" }) + "\n", ""]);
        },
        // Account Verify's handoff: one prompt in a session with no tools.
        async probe(folder) {
            const Harness = require(path.join(folder, "backend/CopilotHarness.js"));
            const runtime = path.join(process.env.JARVIS_TEST_ROOT, "probe");
            const probe = () => Harness.probe({ provider: "copilot", directory: account, env, runtime, model: "", text: "Reply OK." });
            scenario({ reply: "OK" });
            assert.equal(await probe(), "OK");
            assert.deepEqual([program().config, program().args.includes("--additional-mcp-config")], [null, false], "a probe session has no tools");
            assert.deepEqual(fs.readdirSync(runtime), []);
            scenario({ reply: " " });
            await assert.rejects(probe(), { message: "jarvis: brain=copilot-no-reply" });
            scenario({ turns: [[chunk("No."), { stop: "refusal" }]] });
            await assert.rejects(probe(), { message: "jarvis: brain=copilot-stop-refusal" });
            validWrites();
        },
        async probeHang(folder) {
            const probeCopy = copied(folder, { "backend/CopilotHarness.js": [
                ["const HANDSHAKE_MS = 30000;", "const HANDSHAKE_MS = 1000;"],
                ["const PROBE_MS = 60000;", "const PROBE_MS = 20;"]
            ], "backend/HarnessProgram.js": [
                ["const CLOSE_MS = 2000;", "const CLOSE_MS = 200;"]
            ] });
            const Harness = require(path.join(probeCopy, "backend/CopilotHarness.js"));
            const runtime = path.join(process.env.JARVIS_TEST_ROOT, "probe-hang");
            scenario({ reply: "OK", delayPromptMs: 100 });
            await assert.rejects(() => Harness.probe({ provider: "copilot", directory: account, env, runtime, model: "", text: "Reply OK." }),
                { message: "jarvis: brain=copilot-probe-deadline" });
            await noProgramOrDir(runtime, "hung probe");
        },
        async probePermission(folder) {
            const Harness = require(path.join(folder, "backend/CopilotHarness.js"));
            const runtime = path.join(process.env.JARVIS_TEST_ROOT, "probe-permission");
            scenario({ turns: [[permission({ kind: "execute", rawInput: { command: "make" } }), { stop: "end_turn" }]] });
            await assert.rejects(() => Harness.probe({ provider: "copilot", directory: account, env, runtime, model: "", text: "Reply OK." }),
                { message: "jarvis: brain=copilot-no-reply" });
            assert.deepEqual(outcomes("session/request_permission"), [{ outcome: "selected", optionId: "reject-once" }]);
            await noProgramOrDir(runtime, "probe permission");
        }
    };

    async function variant(relative, edits, check) {
        const folder = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "variant-"));
        fs.mkdirSync(path.join(folder, "backend"));
        for (const name of fs.readdirSync(plugin).filter(name => name.endsWith(".js")))
            fs.copyFileSync(path.join(plugin, name), path.join(folder, name));
        for (const name of fs.readdirSync(path.join(plugin, "backend")).filter(name => name.endsWith(".js") || name === "mcp-shim"))
            fs.copyFileSync(path.join(plugin, "backend", name), path.join(folder, "backend", name));
        fs.cpSync(path.join(plugin, "backend/skills"), path.join(folder, "backend/skills"), { recursive: true });
        const target = path.join(folder, relative);
        let source = fs.readFileSync(target, "utf8");
        for (const [needle, replacement] of edits) {
            assert.equal(source.split(needle).length - 1, 1, relative + " match: " + needle);
            source = source.replace(needle, replacement);
        }
        fs.writeFileSync(target, source);
        await assert.rejects(check(folder), assert.AssertionError, relative + " variant must turn red: " + edits[0][0]);
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
        const H = "backend/CopilotHarness.js", S = "backend/HarnessProgram.js";
        for (const [name, relative, edits, row] of [
            ["environment-scrub", S, [["env: { ...childEnvironment(env), ...extra }", "env: { ...env, ...extra }"]], "turn"],
            ["account-home", H, [["[p.variable]: directory", "[p.variable]: env.HOME"]], "turn"],
            ["available-tools", H, [['"--available-tools", Copilot.SERVER + "/*",', ""]], "turn"],
            ["bridge-config", H, [['...(config === null ? [] : ["--additional-mcp-config", "@" + config]), ', ""]], "bridge"],
            // The bridge sent in session/new: Copilot drops it, so no bridge call arrives.
            ["bridge-session-new", H, [['const config = bridge === null ? null : path.join(cwd, "mcp.json");', "const config = null;"],
                ["Copilot.sessionNew(n, { cwd })", "({ ...Copilot.sessionNew(n, { cwd }), params: { cwd, mcpServers: [{ name: Copilot.SERVER, "
                    + "command: bridge.command, args: [...bridge.args], env: Object.entries(bridge.env).map(([name, value]) => ({ name, value })) }] } })"]], "bridge"],
            ["token-argv", H, [['path.join(cwd, "mcp.json");', 'path.join(cwd, "mcp.json#" + bridge.env.VGS_JARVIS_TOOLS_TOKEN);']], "turn"],
            ["server-name", "backend/CopilotAcp.js", [['const SERVER = "vgs_jarvis";', 'const SERVER = "jarvis";']], "turn"],
            ["config-mode", "backend/Private.js", [["{ mode: 0o600, flag: \"wx\" });", "{ mode: 0o600, flag: \"wx\" }); fs.chmodSync(file, 0o644);"]], "turn"],
            ["providers-config", H, [[', COPILOT_PROVIDERS_CONFIG: path.join(cwd, "no-providers", "providers.json")', ""]], "turn"],
            ["parent-death", S, [['"--pdeathsig", "KILL"', '"--pdeathsig", "clear"']], "turn"],
            ["denied-kind", H, [['"--deny-tool", "shell", "write", "read",', '"--deny-tool", "shell", "write",']], "turn"],
            ["native-memory", H, [['"read", "url", "memory",', '"read", "url",']], "turn"],
            ["memory-enabled", H, [['"--no-ask-user",', '"--no-ask-user", "--enable-memory",']], "turn"],
            ["custom-instructions", H, [['"--no-custom-instructions", ', ""]], "turn"],
            ["builtin-mcps", H, [['"--disable-builtin-mcps", ', ""]], "turn"],
            ["model-flag", H, [['...(model === "" ? [] : ["--model", model])', "...[]"]], "model"],
            ["agent-check", H, [["Copilot.agent(await child.call(id => Copilot.initialize(id)), p);", "await child.call(id => Copilot.initialize(id));"]], "handshake"],
            ["signed-out-key", H, [["value.code === -32000 ? ", "false ? "]], "handshake"],
            ["handshake-timer", H, [["const timer = setTimeout(() => child.close(), HANDSHAKE_MS);", "const timer = null;"]], "handshakeHang"],
            ["close-handshake", H, [["active?.cancel();", ""]], "closeHandshake"],
            ["unterminated-line", S, [['if (Buffer.byteLength(tail) >= lineBytes) fail("line-size");', ""]], "lineSize"],
            ["event-session", H, [["e.sessionId !== session.id || ", ""]], "foreignSession"],
            ["bridge-launch", H, [["model,\n                bridge: launch }", "model,\n                bridge: null }"]], "bridge"],
            ["instructions-first", H, [["const texts = turns === 0 ? [instructions, text] : [text];", "const texts = [text];"]], "turn"],
            ["instructions-once", H, [["const texts = turns === 0 ? [instructions, text] : [text];", "const texts = [instructions, text];"]], "turn"],
            ["release", S, [["const decision = Policy.release(item, recipients, grants);",
                "const decision = { kind: \"send\", content: item.content };"]], "release"],
            ["release-empty", H, [['if (labels.length === 0) fail("release-empty");', ""]], "release"],
            ["gate-routing", H, [["gate.ask(gen, Copilot.proposal(", "({ ask: (gen, proposal, port) => port.accept() }).ask(gen, Copilot.proposal("]], "allowed"],
            ["session-binding", H, [[" || value.sessionId !== current.id || value.allow === null)", " || value.allow === null)"]], "stale"],
            ["allow-option", H, [[" || value.allow === null)", ")"]], "stale"],
            ["builtin-tripwire", H, [["if (!BUILTIN.includes(merged.kind) || Copilot.bridged(merged, launch.tools) || turn.asked.has(call.id) || !RAN.includes(merged.status)) return;", "return;"]], "builtin"],
            ["bridge-call", H, [["|| Copilot.bridged(merged, launch.tools) ", ""]], "bridge"],
            ["bridge-title", "backend/CopilotAcp.js", [['call.title === SERVER + "-" + entry.name', "call.title.startsWith(SERVER)"]], "foreignTitle"],
            ["bridge-arguments", "backend/CopilotAcp.js", [["Object.keys(call.rawInput).every(key => declared.includes(key))", "true"]], "foreignTitle"],
            ["builtin-kind", H, [['"execute", ', ""]], "builtin"],
            ["builtin-asked", H, [["turn.asked.has(call.id) || !RAN", "!RAN"]], "refused"],
            ["builtin-pending", H, [[" || !RAN.includes(merged.status)) return;", ") return;"]], "allowed"],
            ["builtin-ends", H, [["session.program.abort(error);", ""]], "builtin"],
            ["cancel-pending", H, [["for (const cancelled of [...current.pending.values()]) cancelled();\n                session.program.write",
                "session.program.write"]], "cancel"],
            ["cancel-notify", H, [["session.program.write(Copilot.cancel(session.id));\n                return true;", "return false;"]], "cancel"],
            ["bridge-close", H, [["launch?.close();", ""]], "close"],
            ["directory-removal", H, [["    await session.program.close();\n    fs.rmSync(session.cwd, { recursive: true, force: true });",
                "    await session.program.close();"]], "close"],
            ["context-limit", H, [['if (turns >= TURNS) throw new Error("jarvis: brain=context-limit");', ""]], "limit"],
            ["opening-close", H, [['if (closed) { launch.close(); fail("closed"); }', 'if (closed) fail("closed");']], "opening"],
            ["probe-reply", H, [['if (reply.trim() === "") fail("no-reply");', ""]], "probe"],
            ["probe-stop", H, [['if (stop !== "end_turn") fail("stop-" + stop);', ""]], "probe"],
            ["probe-tools", H, [["model, bridge: null }, hooks);", "model, bridge: { command: \"x\", args: [], env: {} } }, hooks);"]], "probe"],
            ["probe-timer", H, [['timer = setTimeout(() => reject(new Error("jarvis: brain=copilot-probe-deadline")), PROBE_MS);', ""]], "probeHang"],
            ["probe-permission", H, [['value.kind === "permission" ? "reject" : "cancelled"', '"cancelled"']], "probePermission"],
            ["gate-outcome", H, [['outcome: status === "completed" ? "completed"', 'outcome: status === "unreachable" ? "completed"']], "allowed"],
            ["handoff-route", "backend/Accounts.js", [['case "copilot":', 'case "copilot-removed":']], "verify"],
            ["handoff-audit", "backend/Accounts.js", [["release.start(() => CopilotHarness.probe(", "(send => send())(() => CopilotHarness.probe("]], "verify"],
            ["status-command", "AccountProviders.js", [['{ id: "copilot", label: "GitHub Copilot", kind: "cli", command: null,', '{ id: "copilot", label: "GitHub Copilot", kind: "cli", command: ["copilot", "--version"],']], "verify"],
            ["unchecked-state", "backend/Accounts.js", [['let state = { kind: "unchecked" };', 'let state = { kind: "found" };']], "verify"],
            ["folder-label", "backend/Accounts.js", [[': item.email ? row.label + " / " + item.email : row.label + " / " + item.label;', ': item.email ? row.label + " / " + item.email : row.label + " / same";']], "verify"],
            ["harness-reason", "backend/Accounts.js", [["(?:harness|codex|copilot|pi)-", "(?:harness|codex|pi)-"]], "verify"],
            ["account-row", "AccountProviders.js", [['{ id: "copilot", label: "GitHub Copilot", kind: "cli", command: null,', '{ id: "copilot-removed", label: "GitHub Copilot", kind: "cli", command: null,']], "verify"],
            ["engine-driver", "backend/ChainedEngine.js", [["\"copilot-acp\": CopilotHarness, ", ""]], "limit"]
        ]) {
            await variant(relative, edits, folder => CASES[row](folder));
            controls++;
            console.log("control=" + name + " detected");
        }
        console.log("test-jarvis-copilot: ok cases=" + cases + " controls=" + controls);
    } finally { for (const owner of owners.splice(0)) owner(); }
}, standins => {
    fs.copyFileSync(path.join(tree, "scripts/fixtures/jarvis-copilot/copilot-stub.js"), path.join(standins, "copilot"));
    fs.chmodSync(path.join(standins, "copilot"), 0o700);
}, 900000);
