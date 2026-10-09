#!/usr/bin/env node
// Synthetic Claude Code task cases from AgentProfiles.js, claude-hook and
// TaskRelay.js v1, 2026-10-02, and what TaskVoice.js says about them, from
// the Jarvis plan § 7 Voice and § 4.4, 2026-10-08. The stand-in claude,
// scripts/fixtures/jarvis-claude/claude-task.js, runs the hooks --settings
// wires as the Claude Code hooks reference describes; TaskRunner, task-run.py
// and the task engine copy are real. Everything runs inside the J09 world.
// No vendor program, login, terminal, network or live session. Every signal
// targets a group this suite recorded, never a name.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");
const { once } = require("node:events");
const { seedTaskEvents } = require("./fixtures/jarvis/prepare.js");
const { load: loadQml } = require("../bin/lib/qml-library.js");
const tree = path.resolve(__dirname, "..");
const backend = path.join(tree, "shell/plugins/vgs.jarvis/backend");
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
// The files a control copies: the engine copy's four and their consumers.
const ENGINE = ["Tasks.js", "task-event", "TaskRelay.js", "claude-hook"];
const SOURCES = ENGINE.concat(["TaskRunner.js", "AgentProfiles.js", "task-run.py", "TaskVoice.js"]);
const EVENTS = ["Notification", "PermissionRequest", "SessionEnd", "Stop", "StopFailure", "UserPromptSubmit"];
// Hook timeouts in seconds: a held event's is the 600 s window plus 60.
const TIMEOUTS = { UserPromptSubmit: 30, Notification: 30, PermissionRequest: 660, Stop: 660, StopFailure: 30, SessionEnd: 10 };
// J09 maps the test user to root. Remove its DAC bypass across every exec
// for the unwritable-project actor, including the hooks and flock children.
// setpriv(1): https://github.com/util-linux/util-linux/blob/master/sys-utils/setpriv.1.adoc
const FILE_PERMISSIONS = ["--bounding-set=-dac_override,-dac_read_search",
    "--inh-caps=-dac_override,-dac_read_search", "--ambient-caps=-dac_override,-dac_read_search"];

async function inside() {
    const root = process.env.JARVIS_TEST_ROOT;
    process.chdir(root);
    const env = { PATH: process.env.PATH, HOME: process.env.HOME, LANG: "C.UTF-8" };
    const Tasks = require(path.join(backend, "Tasks.js"));
    const groups = new Set();
    const launchers = [];
    const runners = new Set();
    let cases = 0, controls = 0, worlds = 0;

    // Real processes cross exec, pipes, the producer's lock and the relay's
    // poll. Bound each wait.
    async function until(label, predicate, ms = 15000) {
        const deadline = Date.now() + ms;
        for (;;) {
            const value = await predicate();
            if (value) return value;
            if (Date.now() > deadline) assert.fail("timeout: " + label);
            await sleep(20);
        }
    }
    const load = dir => ({ dir, Runner: require(path.join(dir, "TaskRunner.js")),
        Profiles: require(path.join(dir, "AgentProfiles.js")), Relay: require(path.join(dir, "TaskRelay.js")),
        Tasks: require(path.join(dir, "Tasks.js")), Voice: require(path.join(dir, "TaskVoice.js")) });
    const kinds = record => record.events.map(event => event.kind === "wait" ? "wait " + event.data.kind
        : event.kind === "turn-failed" ? "turn-failed " + event.data.kind : event.kind);

    // One world: private state and runtime directories with a quote and a
    // space, an engine published from a snapshot of modules.dir that is then
    // removed, an account directory, and a runner whose floating display runs
    // task-run.py in a session of its own.
    function world(modules, readOnly = false, options = {}) {
        const base = path.join(root, "w" + (++worlds));
        const directories = { state: path.join(base, "it's \"state\""), runtime: path.join(base, "run time") };
        const snapshot = path.join(base, "snapshot");
        fs.mkdirSync(snapshot, { recursive: true });
        for (const file of ENGINE) fs.copyFileSync(path.join(modules.dir, file), path.join(snapshot, file));
        const engine = modules.Tasks.publish(path.join(base, "data"), snapshot);
        fs.rmSync(snapshot, { recursive: true });
        const account = path.join(base, "accounts", ".claude-work");
        fs.mkdirSync(account, { recursive: true });
        const prompts = path.join(directories.runtime, "prompts");
        const seen = { launchers: [], faults: [] };
        let runner = null;
        runner = modules.Runner.create({ directories, engine, backend: modules.dir,
            settings: () => ({ taskTerminal: "floating" }),
            display: { run(args) {
                const command = readOnly ? ["setpriv", ...FILE_PERMISSIONS, "--", "python3"] : ["python3"];
                const child = cp.spawn(command[0], [...command.slice(1), path.join(modules.dir, "task-run.py"), "--spec", args[0]],
                    { env, stdio: ["ignore", "pipe", "pipe"], detached: true });
                const entry = { child, stderr: "", closed: once(child, "close") };
                child.stderr.on("data", chunk => { entry.stderr += chunk; });
                child.on("close", () => runner.tuiState(false));
                seen.launchers.push(entry);
                launchers.push(child);
                runner.tuiState(true);
                return Promise.resolve("ok");
            } },
            count() {}, failed: error => seen.faults.push(error.message),
            accounts: (agent, reference) => agent === "claude" && reference === "cli:work" ? account : null,
            environment: { ...env, XDG_RUNTIME_DIR: path.join(base, "xdg"), VGSH_RUNNER_PID: "1", FIXTURE_SECRET: "x" },
            lookup: command => command === "claude",
            clock: { now: Date.now, set: setTimeout, clear: clearTimeout }, ...options });
        runners.add(runner);
        runner.tuiState(false);
        const read = id => new Tasks.Store(directories.state).read(id);
        const log = () => fs.readFileSync(path.join(account, "log.jsonl"), "utf8").trim().split("\n").map(line => JSON.parse(line));
        async function start(script, args = {}) {
            fs.writeFileSync(path.join(account, "script.json"), JSON.stringify(script));
            const answer = await new Promise(resolve => runner.executor(async () => "send").start(Object.freeze({
                id: "task.start", args: { goal: "Fix the build", cwd: path.join(root, "home"), agent: "claude", account: "cli:work", ...args }
            }), resolve));
            const result = JSON.parse(answer.content);
            return { answer, result };
        }
        async function started(script, args = {}) {
            const { answer, result } = await start(script, args);
            assert.equal(answer.outcome, "completed", answer.content);
            const task = await until("started", () => {
                const record = read(result.task);
                return record.process.kind !== "starting" && record;
            });
            if (task.identity !== null) groups.add(task.identity.pgid);
            return result.task;
        }
        // The one prompt the task's hook holds, once it is published.
        const prompt = (id, kind) => until("held " + kind, () => {
            const held = runner.held().filter(item => item.task === id);
            assert.ok(held.length <= 1, "one prompt at a time");
            return held.length === 1 && held[0].kind === kind && held[0];
        });
        function close() {
            runner.close();
            runners.delete(runner);
            assert.deepEqual(seen.faults, [], "the runner reported no fault");
        }
        return { runner, directories, engine, prompts, account, seen, read, log, start, started, prompt, close };
    }

    function hook(engine, args, input) {
        const begun = Date.now();
        const result = cp.spawnSync(process.execPath, [path.join(path.dirname(engine), "claude-hook"), ...args],
            { env, input: typeof input === "string" ? input : JSON.stringify(input), encoding: "utf8", timeout: 20000 });
        assert.equal(result.error, undefined);
        return { ...result, ms: Date.now() - begun };
    }
    function hookAsync(engine, args, input) {
        const child = cp.spawn(process.execPath, [path.join(path.dirname(engine), "claude-hook"), ...args],
            { env, timeout: 20000, killSignal: "SIGKILL" });
        let stdout = "", stderr = "";
        child.stdout.on("data", chunk => { stdout += chunk; });
        child.stderr.on("data", chunk => { stderr += chunk; });
        child.stdin.end(JSON.stringify(input));
        const ended = once(child, "close").then(([status, signal]) => ({ status, signal, stdout, stderr }));
        return { child, ended };
    }
    function create(w, id) {
        const result = cp.spawnSync(process.execPath, [w.engine, "--state", w.directories.state, id, "create"],
            { env, input: JSON.stringify({ goal: "Fix the build", cwd: path.join(root, "home"), agent: "claude", account: "" }),
                encoding: "utf8", timeout: 10000 });
        assert.equal(result.status, 0, result.stderr);
    }
    const hookArgs = (w, id, event, window = "1000") =>
        ["--state", w.directories.state, "--prompts", w.prompts, "--window", window, id, event];
    const input = (event, fields = {}) => ({ session_id: "s", transcript_path: "/t", cwd: root, hook_event_name: event, ...fields });

    // The profile row and the --settings it builds, read independently of
    // the builder: one exec-form command hook per documented event.
    function profile(modules) {
        const { Profiles } = modules;
        assert.equal(Object.hasOwn(Profiles.TABLE, "claude"), true);
        const row = Profiles.TABLE.claude;
        assert.deepEqual([row.program, row.account, row.interrupt], ["claude", { variable: "CLAUDE_CONFIG_DIR" }, { signal: "SIGINT" }]);
        const brief = Profiles.brief({ goal: "-p --dangerously-skip-permissions", engine: "/data/engine/h/task-event",
            state: "/state", id: "t1" });
        const argv = Profiles.command(row, { id: "t1", brief, cwd: "/work", account: "/acct", engine: "/data/engine/h/task-event",
            state: "/st ate", prompts: "/run/prompts", node: "/usr/bin/node" });
        assert.deepEqual([argv.length, argv[0], argv[1], argv[3], argv[4]], [5, "claude", "--settings", "--", brief],
            "the brief follows --, so a goal that starts with - is no flag");
        const settings = JSON.parse(argv[2]);
        assert.deepEqual(Object.keys(settings), ["hooks"]);
        assert.deepEqual(Object.keys(settings.hooks).sort(), EVENTS);
        for (const event of EVENTS) {
            assert.deepEqual(settings.hooks[event], [{ hooks: [{ type: "command", command: "/usr/bin/node",
                timeout: TIMEOUTS[event], args: ["/data/engine/h/claude-hook", "--state", "/st ate", "--prompts", "/run/prompts",
                    "--window", "600000", "t1", event] }] }], event);
        }
        cases += 3;
    }

    // Permission and question relay end to end: the stand-in runs the wired
    // hooks; the user's answers reach them only through runner.answer.
    async function relay(modules, readOnly = false) {
        const w = world(modules, readOnly);
        const project = path.join(w.account, "project");
        fs.mkdirSync(project);
        if (readOnly) {
            fs.chmodSync(project, 0o555);
            const refused = cp.spawnSync("setpriv", [...FILE_PERMISSIONS, "--", process.execPath, "-e",
                'const fs = require("node:fs"), assert = require("node:assert/strict");' +
                'assert.throws(() => fs.writeFileSync(process.argv[1], "probe", { flag: "wx" }), { code: "EACCES" });',
                path.join(project, "write-probe")], { env, encoding: "utf8", timeout: 10000 });
            assert.equal(refused.error, undefined);
            assert.equal(refused.signal, null);
            assert.equal(refused.status, 0, refused.stderr);
        }
        const id = await w.started([
            { hook: "UserPromptSubmit", input: { prompt: "brief" } },
            { hook: "PermissionRequest", input: { tool_name: "Bash", tool_input: { command: "make test" } } },
            { hook: "Stop", input: { stop_hook_active: false, last_assistant_message: "Which branch should I use?" } },
            { report: "reported-ok" },
            { hook: "Stop", input: { stop_hook_active: true, last_assistant_message: "Done." } },
            { hook: "Notification", input: { notification_type: "idle_prompt", message: "waiting" } },
            { hook: "SessionEnd", input: { reason: "other" } }
        ], { cwd: project });
        const asked = await w.prompt(id, "permission");
        assert.deepEqual([asked.tool, asked.text], ["Bash", 'Bash {"command":"make test"}']);
        assert.equal(w.read(id).wait.kind, "permission");
        assert.equal(w.runner.answer(id, asked.id, { v: 1, kind: "reply", text: "yes" }), "answer-invalid");
        assert.equal(w.runner.answer(id, asked.id, { v: 1, kind: "allow" }), "answered");
        const question = await w.prompt(id, "question");
        assert.equal(question.text, "Which branch should I use?");
        assert.deepEqual([w.read(id).turn.kind, w.read(id).wait.kind], ["turn-ended", "question"]);
        assert.equal(w.runner.answer(id, question.id, { v: 1, kind: "reply", text: "main" }), "answered");
        // After the outcome is reported, a turn end holds nothing.
        await until("agent exit", () => {
            assert.deepEqual(w.runner.held(), [], "no prompt is held after the outcome is reported");
            return w.read(id).process.kind === "exited";
        });
        await w.seen.launchers[0].closed;
        const entries = w.log();
        const { settings, env: agentEnv } = entries[0].start;
        assert.equal(agentEnv.CLAUDE_CONFIG_DIR, w.account);
        for (const name of ["VGSH_RUNNER_PID", "FIXTURE_SECRET"]) assert.equal(Object.hasOwn(agentEnv, name), false, name);
        for (const event of EVENTS) {
            const args = settings.hooks[event][0].hooks[0].args;
            assert.equal(args[0], path.join(path.dirname(w.engine), "claude-hook"), "hooks run from the engine copy");
            assert.equal(fs.existsSync(args[0]), true);
        }
        const hooks = entries.slice(1);
        assert.deepEqual(hooks.map(entry => [entry.event, entry.status, entry.signal]),
            ["UserPromptSubmit", "PermissionRequest", "Stop", "Stop", "Notification", "SessionEnd"].map(event => [event, 0, null]),
            JSON.stringify(hooks.map(entry => entry.stderr)));
        assert.deepEqual(hooks.map(entry => entry.stdout === "" ? "" : JSON.parse(entry.stdout)), [
            "",
            { hookSpecificOutput: { hookEventName: "PermissionRequest", decision: { behavior: "allow" } } },
            { decision: "block", reason: "The user answered: main" },
            "", "", ""
        ]);
        const record = w.read(id);
        assert.deepEqual(kinds(record), ["started", "working", "wait none", "wait permission", "wait none", "wait question",
            "turn-ended", "working", "wait none", "outcome", "turn-ended", "wait idle", "wait none", "exited"],
        "a turn end follows its held question, and work resumes before the wait clears");
        assert.deepEqual([record.outcome.kind, record.state], ["reported-ok", "reported-ok"]);
        assert.deepEqual(fs.readdirSync(w.prompts).filter(name => name !== ".relay.lock"), [], "every prompt leaves with its hook");
        assert.deepEqual(fs.readdirSync(project), [], "relay delivery writes no project file");
        if (readOnly) fs.chmodSync(project, 0o755);
        w.close();
        cases++;
    }

    // A denied permission, failed turns and the notification map.
    async function deny(modules) {
        const w = world(modules);
        const id = await w.started([
            { hook: "Notification", input: { notification_type: "permission_prompt", message: "m" } },
            { hook: "PermissionRequest", input: { tool_name: "Edit", tool_input: { file_path: "/x" } } },
            { hook: "StopFailure", input: { error: "rate_limit", last_assistant_message: "API Error" } },
            { hook: "Notification", input: { notification_type: "elicitation_dialog", message: "m" } },
            { hook: "Notification", input: { notification_type: "auth_success", message: "m" } },
            { hook: "StopFailure", input: { error: "a-new-kind" } }
        ]);
        const asked = await w.prompt(id, "permission");
        assert.equal(w.runner.answer(id, asked.id, { v: 1, kind: "deny" }), "answered");
        await until("agent exit", () => w.read(id).process.kind === "exited");
        await w.seen.launchers[0].closed;
        const hooks = w.log().slice(1);
        assert.deepEqual(JSON.parse(hooks[1].stdout), { hookSpecificOutput: { hookEventName: "PermissionRequest",
            decision: { behavior: "deny", message: "The user denied this request." } } });
        assert.deepEqual(hooks.map(entry => entry.status), [0, 0, 0, 0, 0, 0]);
        assert.deepEqual(kinds(w.read(id)), ["started", "wait permission", "wait permission", "wait none",
            "turn-failed rate_limit", "wait question", "turn-failed unknown", "exited"]);
        assert.equal(w.read(id).state, "failed");
        w.close();
        cases++;
    }

    // No answer inside the window: no decision, so the agent asks in its own
    // terminal, the wait stays recorded and a late answer finds no prompt.
    async function expiry(modules) {
        const w = world(modules);
        for (const [event, fields, wait] of [
            ["PermissionRequest", { tool_name: "Bash", tool_input: {} }, "permission"],
            ["Stop", { stop_hook_active: false, last_assistant_message: "Shall I?" }, "question"]
        ]) {
            const id = "expiry-" + event;
            create(w, id);
            const running = hookAsync(w.engine, hookArgs(w, id, event), input(event, fields));
            const held = await w.prompt(id, wait);
            const result = await running.ended;
            assert.deepEqual([result.status, result.stdout], [0, ""], result.stderr);
            assert.equal(w.read(id).wait.kind, wait);
            const late = wait === "permission" ? { v: 1, kind: "allow" } : { v: 1, kind: "reply", text: "x" };
            assert.equal(w.runner.answer(id, held.id, late), "prompt-unknown");
            assert.deepEqual(fs.readdirSync(w.prompts).filter(name => name !== ".relay.lock"), []);
            cases++;
        }
        w.close();
    }

    // A full relay holds nothing; expired prompts a killed hook left are
    // swept, so they never fill it.
    async function full(modules) {
        const w = world(modules);
        create(w, "full");
        const now = Date.now();
        for (let i = 0; i < modules.Relay.MAX_PROMPTS; i++)
            modules.Relay.ask(w.prompts, "other", { kind: "question", tool: null, text: "q" }, now, 600000);
        assert.equal(modules.Relay.ask(w.prompts, "full", { kind: "permission", tool: "Bash", text: "extra" }, now, 600000),
            null, "the full live relay refuses another prompt");
        const refused = hook(w.engine, hookArgs(w, "full", "PermissionRequest"), input("PermissionRequest", { tool_name: "Bash" }));
        assert.deepEqual([refused.status, refused.stdout], [0, ""], refused.stderr);
        assert.equal(w.read("full").wait.kind, "permission");
        for (const name of fs.readdirSync(w.prompts).filter(name => name !== ".relay.lock")) fs.rmSync(path.join(w.prompts, name));
        for (let i = 0; i < modules.Relay.MAX_PROMPTS; i++)
            modules.Relay.ask(w.prompts, "other", { kind: "question", tool: null, text: "q" }, now - 700000, 1000);
        const running = hookAsync(w.engine, hookArgs(w, "full", "PermissionRequest", "5000"), input("PermissionRequest", { tool_name: "Bash" }));
        const held = await w.prompt("full", "permission");
        assert.equal(w.runner.answer("full", held.id, { v: 1, kind: "allow" }), "answered");
        const result = await running.ended;
        assert.equal(JSON.parse(result.stdout).hookSpecificOutput.decision.behavior, "allow", result.stderr);
        assert.deepEqual(fs.readdirSync(w.prompts).filter(name => name !== ".relay.lock"), [], "expired prompts were swept");
        w.close();
        cases += 2;
    }

    // A failing hook gives no decision and exits 1: never 2, which Claude
    // Code reads as a block on Stop and UserPromptSubmit.
    function failures(modules) {
        const w = world(modules);
        create(w, "fails");
        const file = path.join(root, "not-a-directory");
        fs.writeFileSync(file, "");
        const rows = [
            ["record", [...hookArgs(w, "fails", "UserPromptSubmit").slice(0, 1), file, ...hookArgs(w, "fails", "UserPromptSubmit").slice(2)],
                input("UserPromptSubmit"), /^jarvis: claude-hook=record kind=working /],
            ["permission-record", [...hookArgs(w, "fails", "PermissionRequest").slice(0, 1), file,
                ...hookArgs(w, "fails", "PermissionRequest").slice(2)], input("PermissionRequest", { tool_name: "Bash" }),
                /^jarvis: claude-hook=record kind=wait /],
            ["event", hookArgs(w, "fails", "PermissionRequest"), input("Stop"), /^jarvis: claude-hook=input-event event=PermissionRequest$/],
            ["json", hookArgs(w, "fails", "Stop"), "{", /^jarvis: claude-hook=input-json$/],
            ["window", hookArgs(w, "fails", "Stop", "999"), input("Stop"), /^jarvis: claude-hook=arguments$/],
            ["tool", hookArgs(w, "fails", "PermissionRequest"), input("PermissionRequest", { tool_name: "a b" }), /^jarvis: claude-hook=input-tool$/],
            ["unknown-event", hookArgs(w, "fails", "PreToolUse"), input("PreToolUse"), /^jarvis: claude-hook=arguments$/]
        ];
        for (const [name, args, value, stderr] of rows) {
            const result = hook(w.engine, args, value);
            assert.deepEqual([result.status, result.stdout], [1, ""], name);
            assert.match(result.stderr.trim(), stderr, name);
            assert.equal(result.stderr.trim().split("\n").length, 1, name);
            cases++;
        }
        assert.deepEqual(kinds(w.read("fails")), [], "a refused hook records nothing");
        w.close();
    }

    // Past the event ceiling the producer drops the hook's events and marks
    // the task noisy; the relay still holds and answers.
    async function ceiling(modules) {
        const w = world(modules);
        create(w, "capped");
        seedTaskEvents(path.join(w.directories.state, "tasks", "capped", "events"), 2000);
        const running = hookAsync(w.engine, hookArgs(w, "capped", "PermissionRequest", "5000"),
            input("PermissionRequest", { tool_name: "Bash" }));
        const held = await w.prompt("capped", "permission");
        assert.equal(w.runner.answer("capped", held.id, { v: 1, kind: "allow" }), "answered");
        const result = await running.ended;
        assert.equal(result.status, 0, result.stderr);
        assert.equal(JSON.parse(result.stdout).hookSpecificOutput.decision.behavior, "allow");
        assert.deepEqual([w.read("capped").noisy, w.read("capped").dropped], [true, 2]);
        w.close();
        cases++;
    }

    // The answer judge, through the daemon's port.
    function answers(modules) {
        const w = world(modules);
        const { Relay } = modules;
        assert.deepEqual(w.runner.held(), [], "no relay directory yet");
        const now = Date.now();
        const permission = Relay.ask(w.prompts, "t1", { kind: "permission", tool: "Bash", text: "Bash {}" }, now, 600000);
        const question = Relay.ask(w.prompts, "t1", { kind: "question", tool: null, text: "q\u0007?" }, now + 1, 600000);
        assert.equal(question.text, "q ?", "control characters are not kept");
        assert.equal(fs.statSync(w.prompts).mode & 0o777, 0o700);
        for (const name of fs.readdirSync(w.prompts).filter(name => name !== ".relay.lock")) assert.equal(fs.statSync(path.join(w.prompts, name)).mode & 0o777, 0o600);
        assert.deepEqual(w.runner.held().map(item => item.id), [permission.id, question.id]);
        const invalid = [
            [permission, { v: 1, kind: "reply", text: "yes" }], [permission, { v: 2, kind: "allow" }],
            [permission, { v: 1, kind: "allow", extra: 1 }], [permission, null], [permission, "allow"],
            [question, { v: 1, kind: "allow" }], [question, { v: 1, kind: "reply", text: "" }],
            [question, { v: 1, kind: "reply", text: "  " }], [question, { v: 1, kind: "reply", text: "a\u0007" }],
            [question, { v: 1, kind: "reply", text: "x".repeat(Relay.MAX_TEXT + 1) }]
        ];
        for (const [prompt, value] of invalid)
            assert.equal(w.runner.answer("t1", prompt.id, value), "answer-invalid", JSON.stringify(value)?.slice(0, 60));
        assert.equal(w.runner.answer("t2", permission.id, { v: 1, kind: "allow" }), "prompt-unknown");
        assert.equal(w.runner.answer("t1", "../" + permission.id, { v: 1, kind: "allow" }), "prompt-unknown");
        assert.equal(w.runner.answer("t1", permission.id, { v: 1, kind: "allow" }), "answered");
        assert.equal(w.runner.answer("t1", permission.id, { v: 1, kind: "deny" }), "answered-already");
        assert.deepEqual(Relay.answerTo(w.prompts, permission), { v: 1, kind: "allow" });
        assert.deepEqual(w.runner.held().map(item => item.id), [question.id], "an answered prompt is not asked again");
        assert.equal(Relay.answer(w.prompts, "t1", question.id, { v: 1, kind: "reply", text: "x" }, question.deadline), "prompt-expired");
        assert.deepEqual(Relay.pending(w.prompts, question.deadline).map(item => item.id), []);
        w.close();
        cases += invalid.length + 6;
    }

    // An account is a discovered one; anything else is refused before a record.
    async function account(modules) {
        const w = world(modules);
        const { answer, result } = await w.start([], { account: "/home/user/.claude" });
        assert.deepEqual([answer.outcome, result.reason], ["failed", "task-account-unknown"]);
        assert.deepEqual(fs.existsSync(path.join(w.directories.state, "tasks"))
            ? fs.readdirSync(path.join(w.directories.state, "tasks")).filter(name => !name.startsWith(".")) : [], []);
        w.close();
        cases++;
    }

    async function takeover(modules) {
        const w = world(modules);
        create(w, "takeover");
        // Stop must remain held beyond the child deadline, so expiry cannot
        // satisfy the terminal takeover assertion.
        const running = hookAsync(w.engine, hookArgs(w, "takeover", "Stop", "600000"),
            input("Stop", { last_assistant_message: "Which branch?" }));
        try {
            const prompt = await w.prompt("takeover", "question");
            const submitted = hook(w.engine, hookArgs(w, "takeover", "UserPromptSubmit"),
                input("UserPromptSubmit", { prompt: "Answered in terminal" }));
            assert.equal(submitted.status, 0, submitted.stderr);
            assert.equal(modules.Relay.present(w.prompts, prompt), false, "terminal input withdraws the live prompt");
            const ended = await running.ended;
            assert.deepEqual([ended.status, ended.stdout], [0, ""]);
            assert.equal(w.runner.answer("takeover", prompt.id, { v: 1, kind: "reply", text: "late" }), "prompt-unknown");
            assert.deepEqual([w.read("takeover").wait.kind, w.read("takeover").turn.kind], ["none", "working"]);
        } finally {
            if (running.child.exitCode === null && running.child.signalCode === null) running.child.kill("SIGKILL");
            await running.ended;
        }
        w.close();
        cases++;
    }

    async function concurrent(modules) {
        const w = world(modules);
        fs.mkdirSync(w.prompts, { recursive: true });
        const script = `const Relay = require(process.argv[1]);
            const prompt = Relay.ask(process.argv[2], "concurrent", {kind:"question",tool:null,text:"q"}, Date.now(), 600000);
            process.stdout.write(JSON.stringify(prompt));`;
        const jobs = Array.from({ length: modules.Relay.MAX_PROMPTS + 2 }, () => {
            const child = cp.spawn(process.execPath, ["-e", script, path.join(modules.dir, "TaskRelay.js"), w.prompts], { env });
            let out = "";
            child.stdout.on("data", chunk => { out += chunk; });
            return once(child, "close").then(([code]) => { assert.equal(code, 0); return JSON.parse(out); });
        });
        const prompts = (await Promise.all(jobs)).filter(value => value !== null);
        assert.equal(prompts.length, modules.Relay.MAX_PROMPTS);
        assert.equal(w.runner.held().length, modules.Relay.MAX_PROMPTS);
        for (const prompt of prompts) modules.Relay.withdraw(w.prompts, prompt);
        assert.deepEqual(w.runner.held(), []);
        w.close();
        cases++;
    }

    // The plan's wording for a turn end with no outcome (§ 7 Voice).
    const WAITING = "The coding agent stopped and is waiting.";
    const DONE = "The coding agent reports the task done.";
    const QUESTION = "The coding agent asks: Which branch should I use? Your next words are its answer.";
    const Session = loadQml(path.join(backend, "../Session.js"));
    // Session with the gate up and no conversation open.
    const ready = Session.reduce(Session.initial(), { type: "snapshot", at: 0, locked: false, engine: "chained",
        configured: true, settings: {} }).state;

    // What a derived task view says, from synthetic records through the real
    // Tasks.derive. Done is said only for the agent's reported-ok outcome.
    function voiceLines(modules) {
        const { Voice, Tasks: Records } = modules;
        const view = (kinds, noisy = false) => Records.derive(kinds.map(([kind, data = {}], index) =>
            ({ v: 1, seq: index + 1, at: index + 1, kind, data })), noisy);
        const started = ["started", { pid: 2, pgid: 2, sid: 2, startTime: "1" }];
        const ok = ["outcome", { kind: "reported-ok" }], bad = ["outcome", { kind: "reported-failed" }];
        const rows = [
            ["turn-ended", [started, ["turn-ended"]], WAITING],
            ["idle", [started, ["wait", { kind: "idle" }]], WAITING],
            ["question", [started, ["turn-ended"], ["wait", { kind: "question" }]], null],
            ["permission", [started, ["wait", { kind: "permission" }]], null],
            ["working", [started, ["working"]], null],
            ["starting", [], null],
            ["noisy", [started, ["turn-ended"]], null, true],
            ["reported-ok", [started, ok], DONE],
            ["reported-ok-exit", [started, ok, ["turn-ended"], ["exited", { code: 0 }]], DONE],
            ["reported-failed", [started, bad], "The coding agent reports the task failed."],
            ["exited", [started, ["turn-ended"], ["exited", { code: 0 }]], "The coding agent exited without reporting an outcome."],
            ["exit-failed", [started, ["exited", { code: 1 }]], "The coding agent failed without reporting an outcome."],
            ["turn-failed", [started, ["turn-failed", { kind: "rate_limit" }]], "The coding agent failed without reporting an outcome."],
            ["failed-after-ok", [started, ok, ["exited", { code: 1 }]], "The coding agent failed after it reported the task done."],
            ["lost", [started, ["lost", { seq: 1 }]], "The coding agent's process was lost without an outcome."],
            ["lost-after-ok", [started, ok, ["lost", { seq: 2 }]], "The coding agent's process was lost after it reported the task done."],
            ["stopped", [started, ["turn-ended"], ["stopped"]], "The coding task was stopped."]
        ];
        for (const [label, kinds, expected, noisy] of rows) {
            const after = view(kinds, noisy === true);
            const line = Voice.outcomeLine(null, after);
            assert.equal(line, expected, label);
            if (line !== null) {
                assert.doesNotMatch(line, /finish/i, label + ": nothing is called finished");
                assert.equal(/\bdone\b/i.test(line), after.outcome.kind === "reported-ok", label + ": done only for reported-ok");
                assert.equal(Voice.outcomeLine(after, after), null, label + ": an unchanged state says nothing");
            }
            cases++;
        }
        const working = view([started, ["working"]]);
        assert.equal(Voice.outcomeLine(working, view([started, ["turn-ended"]])), WAITING);
        assert.equal(Voice.outcomeLine(view([started, ["turn-ended"]]), view([started, ["wait", { kind: "idle" }]])), null,
            "an idle notice after a turn end repeats nothing");
        assert.equal(Voice.promptLine({ kind: "question", tool: null, text: "Which branch should I use?" }), QUESTION);
        assert.equal(Voice.promptLine({ kind: "permission", tool: "Bash", text: "Run the tests" }),
            "The coding agent asks to use Bash: Run the tests. Say allow or deny.");
        cases += 4;
    }

    // The spoken-answer judge yields only answers the relay's own judge takes.
    function voiceAnswers(modules) {
        const { Voice, Relay } = modules;
        const w = world(modules);
        const now = Date.now();
        const permission = { kind: "permission", tool: "Bash", text: "Run the tests" };
        const rows = [
            [permission, "Allow.", "allow"], [permission, " yes ", "allow"], [permission, "Yes allow!", "allow"],
            [permission, "deny", "deny"], [permission, "No.", "deny"], [permission, "no deny", "deny"],
            [permission, "maybe", null], [permission, "allow it", null], [permission, "", null],
            [{ kind: "question", tool: null, text: "q" }, "Use main.", "Use main."],
            [{ kind: "question", tool: null, text: "q" }, "a\u0007b", "a b"],
            [{ kind: "question", tool: null, text: "q" }, "x".repeat(Relay.MAX_TEXT + 9), "x".repeat(Relay.MAX_TEXT)],
            [{ kind: "question", tool: null, text: "q" }, " \u0007 ", null]
        ];
        for (const [detail, said, expected] of rows) {
            const answer = Voice.answerOf(detail, said);
            assert.deepEqual(answer === null ? null : answer.kind === "reply" ? answer.text : answer.kind, expected, JSON.stringify(said).slice(0, 40));
            if (answer !== null) {
                const prompt = Relay.ask(w.prompts, "voice", detail, now, 600000);
                assert.equal(w.runner.answer("voice", prompt.id, answer), "answered", "the relay takes the judged answer");
                Relay.withdraw(w.prompts, prompt);
            }
            cases++;
        }
        w.close();
    }

    // A real stub agent with no conversation open: its question, its turn end
    // and its reported outcome reach the user as notifications, in order, and
    // nothing is dispatched to a conversation.
    async function voiceTask(modules) {
        const notes = [], dispatched = [];
        let voice = null;
        const w = world(modules, false, { changed: views => voice.observe(views), promptsChanged: list => voice.prompts(list) });
        voice = modules.Voice.create({ session: Session, state: () => ready, dispatch: event => dispatched.push(event),
            notify: (title, body) => { notes.push([title, body]); return Promise.resolve({ kind: "exited", code: 0 }); },
            log: line => assert.fail(line) });
        await w.runner.observe();
        const id = await w.started([
            { hook: "UserPromptSubmit", input: { prompt: "brief" } },
            { hook: "Stop", input: { stop_hook_active: false, last_assistant_message: "Which branch should I use?" } },
            { hook: "Notification", input: { notification_type: "idle_prompt", message: "waiting" } },
            { gate: "resume" },
            { hook: "UserPromptSubmit", input: { prompt: "go on" } },
            { report: "reported-ok" },
            { hook: "Stop", input: { stop_hook_active: false, last_assistant_message: "Done." } },
            { hook: "SessionEnd", input: { reason: "other" } }
        ]);
        const told = text => until("notified: " + text, async () => {
            await w.runner.observe();
            return notes.some(note => note[1] === text);
        });
        await told(QUESTION);
        const question = await w.prompt(id, "question");
        assert.equal(w.runner.answer(id, question.id, { v: 1, kind: "reply", text: "main" }), "answered");
        await told(WAITING);
        fs.writeFileSync(path.join(w.account, "resume"), "");
        await until("agent exit", () => w.read(id).process.kind === "exited");
        await told(DONE);
        await w.seen.launchers[0].closed;
        assert.deepEqual(notes, [["Coding task", QUESTION], ["Coding task", WAITING], ["Coding task", DONE]]);
        assert.deepEqual(dispatched, [], "no conversation is open, so nothing is spoken");
        voice.close();
        w.close();
        cases++;
    }

    const current = load(backend);
    function snapshot(modules) {
        const w = world(modules);
        const Protocol = loadQml(path.join(backend, "../JarvisProtocol.js"));
        const now = Date.now();
        for (const text of ["界".repeat(4096), "😀".repeat(4096), '\\"\n'.repeat(4096)]) {
            for (let i = 0; i < modules.Relay.MAX_PROMPTS; i++)
                modules.Relay.ask(w.prompts, "snapshot", { kind: "question", tool: null, text }, now, 600000);
            const prompts = w.runner.held();
            assert.equal(prompts.length, modules.Relay.MAX_PROMPTS, "the full index reaches the wire judge");
            const wire = JSON.stringify({ v: 1, type: "task-prompts", gen: 0, revision: "a".repeat(64), prompts });
            assert.doesNotThrow(() => Protocol.accept(wire, "daemon"), "a full multibyte index fits the wire");
            for (const prompt of prompts) {
                assert.ok(Buffer.byteLength(JSON.stringify(prompt.text)) <= modules.Relay.MAX_TEXT,
                    "prompt JSON bytes stay within the relay text limit");
                assert.equal(prompt.text.endsWith("…"), true);
                assert.equal(Buffer.from(prompt.text).toString("utf8"), prompt.text, "clipping keeps complete code points");
                modules.Relay.withdraw(w.prompts, prompt);
            }
        }
        w.close();
        cases++;
    }
    try {
        profile(current);
        await relay(current);
        await relay(current, true);
        await deny(current);
        await expiry(current);
        await full(current);
        failures(current);
        await ceiling(current);
        answers(current);
        await account(current);
        await takeover(current);
        await concurrent(current);
        snapshot(current);
        voiceLines(current);
        voiceAnswers(current);
        await voiceTask(current);

        async function control(name, file, needle, replacement, check) {
            const source = fs.readFileSync(path.join(backend, file), "utf8");
            assert.equal(source.split(needle).length - 1, 1, name + " match");
            const changed = source.replace(needle, replacement);
            assert.notEqual(changed, source);
            const copy = path.join(root, "control-" + name);
            fs.mkdirSync(copy);
            for (const entry of SOURCES) fs.copyFileSync(path.join(backend, entry), path.join(copy, entry));
            fs.writeFileSync(path.join(copy, file), changed);
            const before = new Set(runners);
            try {
                await assert.rejects(async () => check(load(copy)), error => {
                    assert.ok(error instanceof assert.AssertionError, name + " must turn red, not crash: " + error.stack);
                    console.log("test-jarvis-claude-task: control=" + name + " killed by=" + JSON.stringify(error.message.split("\n")[0]));
                    return true;
                });
            } finally {
                // Failed controls can retain live prompts. Dispose their polling
                // owners without the positive scenario's no-fault assertion.
                for (const runner of runners) if (!before.has(runner)) {
                    runner.close();
                    runners.delete(runner);
                }
                // A mutant can leave a held hook or a running stand-in: end every
                // group this suite recorded, by its recorded pgid.
                for (const pgid of groups) try { process.kill(-pgid, "SIGKILL"); } catch (error) { if (error.code !== "ESRCH") throw error; }
                for (const child of launchers) if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
            }
            controls++;
        }
        await control("exec-form", "AgentProfiles.js", "hooks: [{ type: \"command\", command: task.node, timeout,\n            args: [hook,",
            "hooks: [{ type: \"command\", command: task.node, timeout,\n            argv: [hook,", profile);
        await control("prompt-after-options", "AgentProfiles.js", 'claudeSettings(task), "--", task.brief]', "claudeSettings(task), task.brief]", profile);
        await control("prompt-submit-silent", "claude-hook", '        record(hook, "wait", { kind: "none" });\n        return null;\n    case "Notification"',
            '        record(hook, "wait", { kind: "none" });\n        return {};\n    case "Notification"', relay);
        await control("permission-held", "claude-hook",
            "    const prompt = Relay.ask(hook.prompts, hook.task, detail, Date.now(), hook.window);",
            '    if (detail.kind === "permission") return { v: 1, kind: "allow" };\n    const prompt = Relay.ask(hook.prompts, hook.task, detail, Date.now(), hook.window);', relay);
        await control("deny", "claude-hook", 'decision: { behavior: "deny", message', 'decision: { behavior: "allow", message', deny);
        await control("stop-outcome", "claude-hook", 'if (task.outcome.kind !== "none") {', "if (false) {", relay);
        await control("stop-working", "claude-hook", '    record(hook, "working");\n    record(hook, "wait", { kind: "none" });\n    return { decision: "block"',
            '    record(hook, "wait", { kind: "none" });\n    return { decision: "block"', relay);
        await control("stop-wait-first", "claude-hook", '    record(hook, "wait", { kind: "question" });\n    record(hook, "turn-ended");',
            '    record(hook, "turn-ended");\n    record(hook, "wait", { kind: "question" });', relay);
        await control("failure-kind", "claude-hook", "FAILURES.includes(value.error) ? value.error : \"unknown\"", '"unknown"', deny);
        await control("notification-map", "claude-hook", 'idle_prompt: "idle"', 'idle_prompt: "question"', relay);
        await control("expiry-silent", "claude-hook", "if (Date.now() >= prompt.deadline) return null;",
            'if (Date.now() >= prompt.deadline) return { v: 1, kind: "deny" };', expiry);
        await control("event-ceiling", "claude-hook", "if (result.status === 75 && dropped(result.stdout)) return;",
            "if (false && dropped(result.stdout)) return;", ceiling);
        await control("exit-code", "claude-hook", "    process.exitCode = 1;\n", "    process.exitCode = 2;\n", failures);
        await control("engine-copy", "Tasks.js", '"TaskRelay.js", "claude-hook"];', '"TaskRelay.js"];', relay);
        await control("answer-once", "TaskRelay.js", "fs.linkSync(temporary, answerFile(directory, task, id));",
            "fs.renameSync(temporary, answerFile(directory, task, id));", answers);
        await control("relay-project-lock", "TaskRelay.js", '["-w", "5", "--", file, process.execPath',
            '["-w", "5", "--", "3", process.execPath', relay);
        await control("relay-read-only-lock", "TaskRelay.js", '["-w", "5", "--", file, process.execPath',
            '["-w", "5", "--", "3", process.execPath', modules => relay(modules, true));
        await control("answer-kind", "TaskRelay.js", 'shape(value, ["v", "kind"]) && value.v === 1 && ["allow", "deny"].includes(value.kind)',
            "value !== null && typeof value === \"object\" && value.v === 1", answers);
        await control("answer-expired", "TaskRelay.js", 'if (prompt.deadline <= now) return "prompt-expired";',
            "if (false) return \"prompt-expired\";", answers);
        await control("pending-answered", "TaskRelay.js", "item.deadline > now && !fs.existsSync(answerFile(directory, item.task, item.id))",
            "item.deadline > now", answers);
        await control("relay-full", "TaskRelay.js", "if (live.length >= MAX_PROMPTS) return null;", "if (false) return null;", full);
        await control("relay-text-bytes", "TaskRelay.js", "    if (Buffer.byteLength(JSON.stringify(flat)) <= MAX_TEXT) return flat;",
            "    return flat.slice(0, MAX_TEXT);", snapshot);
        await control("relay-sweep", "TaskRelay.js", "        if (item.deadline <= now) withdrawLocked(directory, item);\n        else live.push(item);",
            "        live.push(item);", full);
        await control("account", "TaskRunner.js", 'if (value === null) return { reason: "account-unknown" };',
            'if (false) return { reason: "account-unknown" };', account);
        await control("takeover", "claude-hook", '        Relay.withdrawTask(hook.prompts, hook.task);\n        record(hook, "working");\n        record(hook, "wait", { kind: "none" });',
            '        record(hook, "working");\n        record(hook, "wait", { kind: "none" });', takeover);
        await control("turn-ended-finished", "TaskVoice.js", 'const WAITING = "The coding agent stopped and is waiting.";',
            'const WAITING = "The coding agent finished.";', voiceLines);
        await control("exit-called-done", "TaskVoice.js", 'case "exited": return "The coding agent exited without reporting an outcome.";',
            'case "exited": return "The coding agent is done.";', voiceLines);
        await control("permission-maybe", "TaskVoice.js", 'return ALLOW.includes(said) ? { v: 1, kind: "allow" }',
            'return !DENY.includes(said) ? { v: 1, kind: "allow" }', voiceAnswers);
        await control("reply-unbounded", "TaskVoice.js", ".trim().slice(0, MAX_REPLY);", ".trim();", voiceAnswers);
        await control("no-conversation-queued", "TaskVoice.js", 'const open = refusal => refusal === null || refusal === "busy";',
            "const open = () => true;", voiceTask);
        await control("views-unobserved", "TaskRunner.js", "if (changed !== undefined) changed(wrote ? store.list() : views);", "", voiceTask);
        console.log("test-jarvis-claude-task: ok cases=" + cases + " controls=" + controls);
    } finally {
        for (const runner of runners) runner.close();
        runners.clear();
    }
}

function main() {
    // A failed case can leave held hooks and launchers alive; end at once.
    if (process.argv[2] === "--inside") return inside().catch(error => { console.error(error); process.exit(1); });
    const parent = require("node:os").tmpdir();
    fs.mkdirSync(parent, { recursive: true });
    const root = fs.realpathSync(fs.mkdtempSync(path.join(parent, "jct-")));
    try {
        const standins = path.join(root, "standins");
        fs.mkdirSync(standins);
        fs.copyFileSync(path.join(tree, "scripts/fixtures/jarvis-claude/claude-task.js"), path.join(standins, "claude"));
        fs.chmodSync(path.join(standins, "claude"), 0o755);
        const result = cp.spawnSync("/bin/bash", [path.join(tree, "scripts/lib/jarvis-env.sh"), standins,
            "--", "node", __filename, "--inside"], {
            env: { PATH: "/usr/bin:/bin", HOME: root, JARVIS_TEST_SCRATCH_ROOT: root },
            encoding: "utf8", timeout: 600000
        });
        process.stdout.write(result.stdout || "");
        process.stderr.write(result.stderr || "");
        if (result.error) throw result.error;
        assert.equal(result.signal, null);
        process.exitCode = result.status;
    } finally { fs.rmSync(root, { recursive: true, force: true }); }
}
try { main(); } catch (error) { console.error(error); process.exitCode = 1; }
