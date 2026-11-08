#!/usr/bin/env node
// Real browser/guidance owners and action judge in J09. Main request
// answers use lane-mail's public envelope (lane-mail lm_envelope/lm_objects),
// an injected child port and clock; no session, notification or cloud call.
"use strict";
const { assert, fs, path, tree, world, mutant, pluginCopy } = require("./fixtures/jarvis/policy.js");
const { daemonStandins, daemonLease, daemonStartup, mode, update, calls } = require("./fixtures/jarvis/browser.js");
const cp = require("node:child_process");
const backend = path.join(tree, "shell/plugins/vgs.jarvis/backend");
const file = path.join(backend, "Browser.js");
world(async () => {
    const Browser = require(file);
    const Tools = require(path.join(backend, "Tools.js"));
    const Policy = require(path.join(backend, "Policy.js"));
    const environment = { ...process.env, OPENAI_API_KEY: "fixture-secret", AGENT_BROWSER_CDP: "host-browser",
        AGENT_BROWSER_PROFILE: "/fixture/profile", AGENT_BROWSER_CONFIG: "/fixture/config", VGSHELL_RUNNER_PID: "fixture" };
    const marker = path.join(environment.XDG_DATA_HOME, "vgshell/jarvis/browser-ready.json");
    const call = (command, args = {}) => ({ id: "browser", args: { command, args } });
    const run = (owner, command, args = {}) => new Promise(resolve => owner.record.start(call(command, args), resolve));
    async function check(implementation, name, fixture, command, args, outcome, reason, changed) {
        mode(fixture);
        const owner = implementation.create({ environment });
        try {
            if (["click", "fill", "submit"].includes(command)) {
                const observation = owner.record.observe(call(command, args));
                if (changed !== undefined) {
                    assert.deepEqual(observation, { target: { kind: "site", id: "https://first.test", password: false, submit: false },
                        ref: args.ref, type: "text" }, name + " observes the ordinary control before approval");
                    update(changed);
                }
            }
            const answer = await run(owner, command, args);
            assert.equal(answer.outcome, outcome, name + ": " + answer.content);
            assert.match(answer.content, reason, name);
            if (changed !== undefined)
                assert.equal(calls().some(row => row.args.includes("click") || row.args.includes("fill")), false,
                    name + " changed target starts no input command");
            return answer;
        } finally { owner.close(); }
    }
    const cases = [
        ["open", {}, "open", { url: "https://first.test/" }, "completed", /fixture-nonce.*fixture page/],
        ["read", {}, "read", {}, "completed", /fixture-nonce.*fixture page/],
        ["click", {}, "click", { ref: "@e2" }, "completed", /fixture page/],
        ["fill", {}, "fill", { ref: "@e1", text: "literal value" }, "completed", /fixture page/],
        ["submit", { type: "submit" }, "submit", { ref: "@e3" }, "completed", /fixture page/],
        ["password", { type: "password" }, "fill", { ref: "@e1", text: "private" }, "failed", /browser=password/],
        ["reference", {}, "click", { ref: "@e999" }, "failed", /browser=reference/],
        ["site-race", { attributeSite: "https://second.test/" }, "click", { ref: "@e2" }, "failed", /browser=target-changed/],
        ["changed-click", {}, "click", { ref: "@e1" }, "failed", /browser=target-changed/, { type: "submit" }],
        ["changed-fill", {}, "fill", { ref: "@e1", text: "literal value" }, "failed", /browser=target-changed/, { type: "submit" }],
        ["redirect", { redirect: "file:///fixture/secret" }, "open", { url: "https://first.test/" }, "failed", /browser=page-url/],
        ["reply-json", { malformed: true }, "read", {}, "failed", /browser=reply-json/],
        ["command-failed", { fail: true }, "read", {}, "failed", /browser=command-failed/]
    ];
    for (const row of cases) await check(Browser, ...row);
    // A command refused after a good launch leaves a browser that close still ends.
    await check(Browser, ...cases.find(row => row[0] === "command-failed"));
    assert.equal(calls().filter(row => row.args.at(-1) === "close").length, 1, "command-failed closes once");
    const forbidden = ["--cdp", "--auto-connect", "--profile", "--executable-path", "--allow-file-access", "--init-script",
        "--extension", "--args", "--config", "--session", "--action-policy", "--state", "--restore"];
    for (const flag of forbidden) {
        mode({});
        for (const request of [call(flag), call("open", { url: "https://first.test/", [flag]: "fixture" }),
            call("click", { ref: flag }), call("fill", { ref: "@e1", text: flag })]) {
            const before = calls().length;
            const owner = Browser.create({ environment });
            const probes = calls().length;
            const answer = await new Promise(resolve => owner.record.start(request, resolve));
            owner.close();
            assert.equal(answer.outcome, "failed", JSON.stringify(request));
            assert.equal(calls().length, probes, "refusal starts no vendor action");
            assert.equal(probes, before + 1, "only the version probe ran");
        }
    }
    for (const command of ["eval", "upload", "download", "state load", "cookies set", "network", "auth"]) {
        assert.equal(Tools.refine(call(command)).kind, "refuse");
    }
    for (const url of ["file:///fixture/secret", "FILE:///fixture/secret", "javascript:alert(1)"])
        assert.equal(Tools.refine(call("open", { url })).kind, "refuse");

    async function confinement(implementation, category) {
        mode({});
        const owner = implementation.create({ environment });
        try {
            await run(owner, "read");
            const row = calls().find(row => row.args.includes("snapshot"));
            assert.equal(row.env.HOME, path.join(row.env.XDG_RUNTIME_DIR, "home"));
            assert.equal(fs.readlinkSync(path.join(row.env.HOME, ".agent-browser/browsers")),
                path.join(environment.XDG_DATA_HOME, "vgshell/jarvis/browser-home/.agent-browser/browsers"));
            assert.ok(row.env.XDG_RUNTIME_DIR.startsWith(path.join(environment.XDG_RUNTIME_DIR, "vgshell/jarvis/browser-")));
            assert.equal(row.env.AGENT_BROWSER_CDP, undefined);
            assert.equal(row.env.AGENT_BROWSER_PROFILE, undefined);
            assert.equal(row.env.OPENAI_API_KEY, undefined);
            assert.equal(row.env.VGSHELL_RUNNER_PID, undefined);
            assert.notEqual(row.env.AGENT_BROWSER_CONFIG, environment.AGENT_BROWSER_CONFIG);
            const session = row.args[row.args.indexOf("--session") + 1];
            assert.match(session, /^jarvis-[0-9a-f]{8}$/);
            assert.equal(row.env.AGENT_BROWSER_NAMESPACE, undefined);
            assert.ok(row.args.includes("--content-boundaries"));
            assert.equal(row.args[row.args.indexOf("--max-output") + 1], "16384");
            assert.equal(row.policy.default, "deny");
            for (const denied of category ? [category] : ["eval", "upload", "download", "state", "network"])
                assert.ok(row.policy.deny.includes(denied));
            assert.deepEqual(row.policy.allow, ["launch", "navigate", "snapshot", "url", "getattribute", "click", "fill", "close"]);
            const second = implementation.create({ environment });
            try {
                await run(second, "read");
                const next = calls().filter(row => row.args.includes("snapshot")).at(-1);
                assert.notEqual(next.args[next.args.indexOf("--session") + 1], session);
            } finally { second.close(); }
        } finally { owner.close(); }
    }
    await confinement(Browser);
    async function bounded(implementation) {
        const answer = await check(implementation, "bounded", { text: "x".repeat(25000) }, "read", {}, "completed", /result clipped/);
        assert.ok(Buffer.byteLength(answer.content) <= 16384);
    }
    await bounded(Browser);
    function readiness(implementation, fixture, expected) {
        mode(fixture);
        assert.equal(implementation.status(environment).tone, expected);
    }
    readiness(Browser, { version: "0.37.9" }, "warning");
    mode({});
    function verification(implementation) {
        mode({});
        const verified = implementation.create({ environment });
        try {
            assert.doesNotThrow(() => verified.verify(), "the vendor policy permits verification and close");
            assert.equal(implementation.status(environment).tone, "ok");
        } finally { verified.close(); }
    }
    verification(Browser);
    assert.deepEqual(calls().filter(row => row.args.includes("--json")).map(row => row.args.slice(row.args.indexOf("--json") + 1)),
        [["get", "url"], ["open", "about:blank"], ["get", "url"], ["close"]]);
    readiness(Browser, { version: "0.38.2" }, "warning");
    mode({ verifyUrl: "https://wrong.test/" });
    const failed = Browser.create({ environment });
    assert.throws(() => failed.verify(), /verify-url/); failed.close();
    assert.equal(fs.existsSync(marker), false);
    mode({});
    const skill = Browser.create({ environment });
    assert.match(skill.guidance(), /fixture installed core guide/);
    assert.equal(skill.guidance(), skill.guidance());
    assert.equal(calls().filter(row => row.args[0] === "skills").length, 1, "one cache per version-owned session");
    skill.close();
    function versionCache(implementation) {
        mode({ version: "0.38.2" });
        const first = implementation.create({ environment });
        first.guidance(); first.close();
        const next = implementation.create({ environment });
        next.guidance(); next.close();
        assert.equal(calls().filter(row => row.args[0] === "skills").length, 1,
            "the daemon reuses one version guide across private sessions");
        update({ version: "0.38.3" });
        const updated = implementation.create({ environment });
        updated.guidance(); updated.close();
        assert.equal(calls().filter(row => row.args[0] === "skills").length, 2,
            "a new installed version reloads its core guide");
    }
    versionCache(Browser);
    mode({});
    const stopped = Browser.create({ environment }); stopped.close();
    assert.equal((await run(stopped, "read")).outcome, "failed");
    // Remove the sole driver stand-in. There is no real-browser PATH fallback.
    const executable = path.join(environment.JARVIS_TEST_ROOT, "standins/agent-browser");
    const saved = fs.readFileSync(executable); fs.rmSync(executable);
    try { assert.equal(Browser.status(environment).tone, "warning"); }
    finally { fs.writeFileSync(executable, saved, { mode: 0o700 }); }

    function decision(implementation, command, fixture, grants, taint, profile = "standard") {
        mode(fixture);
        const owner = implementation.create({ environment });
        const request = call(command, { ref: command === "fill" ? "@e1" : "@e3", ...(command === "fill" ? { text: "fixture" } : {}) });
        try { return Policy.decide(request, { locked: false, profile, grants, taint,
            input: owner.record.observe(request) }); } finally { owner.close(); }
    }
    const clean = { kind: "clean" };
    assert.deepEqual(decision(Browser, "fill", {}, [], clean), { kind: "confirm", effect: "input", physical: false, scope: "site:https://first.test" });
    assert.equal(decision(Browser, "fill", {}, ["site:https://first.test"], clean).kind, "allow");
    assert.equal(decision(Browser, "fill", { site: "https://second.test/" }, ["site:https://first.test"], clean).kind, "confirm");
    assert.equal(decision(Browser, "fill", {}, ["site:https://first.test"], Policy.observe(clean, "web")).kind, "confirm");
    assert.equal(decision(Browser, "fill", { type: "password" }, [], clean, "trusted").reason, "password-target");
    const submit = implementation => assert.equal(decision(implementation, "click", { type: "submit" }, ["site:https://first.test"], clean, "trusted").effect, "external");
    submit(Browser);
    const remote = Policy.recipients({ conversation: "browser", profile: "standard", cloudVision: "ask",
        brain: { kind: "network", provider: "fixture", account: "fixture", origin: "https://provider.test" }, speech: [{ kind: "local", provider: "local", account: "" }] });
    assert.equal(Policy.release(Policy.item("fixture page", ["web"]), remote).kind, "ask");

    async function cancellation(implementation) {
        mode({ delayMs: 1000 });
        const owner = implementation.create({ environment });
        const result = run(owner, "open", { url: "https://first.test/" });
        // Wait for the synthetic child to record that it reached open.
        for (let n = 0; !calls().some(row => row.args.includes("open")); n++) {
            assert.ok(n < 500, "the fixture reaches its pending command");
            await new Promise(resolve => setTimeout(resolve, 10));
        }
        const directory = calls().find(row => row.args.includes("open")).env.XDG_RUNTIME_DIR;
        owner.record.cancel();
        assert.equal((await result).outcome, "failed", "cancel ends the actual CLI child");
        assert.equal(fs.existsSync(path.join(process.env.JARVIS_TEST_ROOT, "browser-open-completed")), false, "cancel precedes natural child completion");
        assert.ok(calls().some(row => row.args.at(-1) === "close"), "cancel closes the vendor session");
        assert.equal(fs.existsSync(directory), false, "cancel releases owned session files");
        owner.close();
    }
    await cancellation(Browser);
    async function until(predicate) {
        for (let n = 0; n < 500; n++) {
            if (predicate()) return;
            await new Promise(resolve => setTimeout(resolve, 10));
        }
        assert.fail("probe settlement absent");
    }
    async function lifecycle(implementation, edge) {
        mode({});
        fs.mkdirSync(path.dirname(marker), { recursive: true });
        fs.writeFileSync(marker, JSON.stringify({ version: "0.38.1" }));
        const records = {};
        const lease = implementation.install({ environment, router: { register: (id, record) => { records[id] = record; } } });
        assert.ok(lease);
        lease.sync({ gen: 1, conversation: { kind: "started" } });
        await until(() => records.browser !== undefined);
        await new Promise(resolve => records.browser.start(call("read"), resolve));
        const first = calls().find(row => row.args.includes("snapshot"));
        if (edge === "generation") lease.sync({ gen: 2, conversation: { kind: "started" } });
        else if (edge === "end") lease.sync({ gen: 1, conversation: { kind: "ended" } });
        else lease.close();
        assert.equal(fs.existsSync(first.env.XDG_RUNTIME_DIR), false, edge + " releases session files");
        assert.equal(calls().filter(row => row.args.at(-1) === "close").length, 1, edge + " closes vendor session");
        if (edge !== "lease") {
            lease.sync({ gen: 2, conversation: { kind: "started" } });
            await new Promise(resolve => records.browser.start(call("read"), resolve));
            const second = calls().filter(row => row.args.includes("snapshot")).at(-1);
            const name = row => row.args[row.args.indexOf("--session") + 1];
            assert.notEqual(name(first), name(second));
        }
        lease.close();
    }
    for (const edge of ["generation", "end", "lease"]) await lifecycle(Browser, edge);

    async function setupAfterStart(implementation) {
        mode({}); fs.rmSync(marker, { force: true });
        const records = {};
        const registrations = [];
        const lease = implementation.install({ environment, router: { register(id, record) {
            registrations.push(id); records[id] = record;
        } } });
        assert.equal(records.browser, undefined, "unverified browser is not offered");
        const guidance = records.guidance;
        assert.deepEqual(guidance.topics(), ["input", "shell", "vision"], "the shipped file help is available before browser setup");
        let answer;
        guidance.start({ id: "help", args: { topic: "input" } }, value => { answer = value; });
        assert.deepEqual(answer, { outcome: "completed",
            content: fs.readFileSync(path.join(backend, "skills/computer/input.md"), "utf8").trim() });
        await until(() => calls().some(row => row.args[0] === "--version") &&
            !fs.existsSync(calls().find(row => row.args[0] === "--version").env.HOME));
        lease.sync({ gen: 1, conversation: { kind: "ended" } });
        fs.writeFileSync(marker, JSON.stringify({ version: "0.38.1" }));
        lease.sync({ gen: 2, conversation: { kind: "started" } });
        await until(() => records.browser !== undefined);
        assert.equal(typeof records.browser?.start, "function", "setup becomes available to the next conversation");
        assert.equal(records.guidance, guidance, "browser setup retains the shared help owner");
        assert.deepEqual(registrations, ["guidance", "browser"], "each executor registers once");
        assert.deepEqual(guidance.topics(), ["input", "shell", "vision", "browser"], "ready browser help joins the file help");
        fs.rmSync(marker, { force: true });
        let target;
        assert.doesNotThrow(() => { target = records.browser.observe(call("fill", { ref: "@e1", text: "fixture" })); },
            "stale readiness cannot throw through the action judge");
        assert.equal(target, undefined, "stale readiness produces an unavailable input target");
        assert.throws(() => records.browser.start(call("read"), () => {}), /unverified/,
            "a removed or stale verification cannot start a new session");
        lease.close();
    }
    await setupAfterStart(Browser);

    // ComputerHelp is Browser.install's shared guidance owner. Its request
    // reader has one clock and one child port, independent of conversations.
    const Help = require(path.join(backend, "ComputerHelp.js"));
    const TaskVoice = require(path.join(backend, "TaskVoice.js"));
    const { load } = require("../bin/lib/qml-library.js");
    const Session = load(path.join(tree, "shell/plugins/vgs.jarvis/Session.js"));
    const flush = () => new Promise(resolve => setImmediate(resolve));
    function mailWorld(implementation) {
        const folder = fs.mkdtempSync(path.join(process.env.HOME, "request-home-"));
        const tool = path.join(folder, ".agents/skills/mailbox/scripts/lane-mail");
        fs.mkdirSync(path.dirname(tool), { recursive: true });
        fs.mkdirSync(path.join(folder, ".git"));
        fs.writeFileSync(tool, "#!/bin/sh\nexit 1\n", { mode: 0o700 });
        const timers = new Map(), over = [], sent = [], delivered = [], logs = [], runs = [];
        let next = 0, duplicate = false, corrupt = false, hold = false, chosen = folder, main = true, onSend = () => {};
        const clock = { now: () => 0, set: (fn, ms) => { timers.set(fn, ms); return fn; }, clear: fn => timers.delete(fn) };
        const exited = stdout => ({ kind: "exited", code: 0, stdout, stderr: "" });
        const owner = implementation.create(undefined, null, () => chosen,
            { PATH: process.env.PATH, HOME: process.env.HOME, OPENAI_API_KEY: "not-in-child" }, () => main,
            { answer: item => delivered.push(item), log: line => logs.push(line), clock,
                async run(file, argv, options) {
                    assert.equal(file, "setpriv");
                    assert.deepEqual(argv.slice(0, 4), ["--pdeathsig", "KILL", "--", tool]);
                    assert.deepEqual(options.env, { LC_ALL: "C.UTF-8", GIT_CEILING_DIRECTORIES: path.dirname(folder),
                        PATH: process.env.PATH, HOME: process.env.HOME });
                    assert.equal(options.group, true);
                    assert.equal(options.cwd, folder);
                    assert.ok(argv.includes("--root") && !argv.includes("--mark-read"));
                    runs.push({ argv, options });
                    const box = argv[argv.indexOf("--box") + 1];
                    if (argv[4] === "send") {
                        assert.ok(fs.readFileSync(argv[argv.indexOf("--file") + 1], "utf8").startsWith("Request"));
                        if (duplicate) return { kind: "exited", code: 1, stdout: "", stderr: "lane-mail: duplicate id=" + sent.at(-1) + "\n" };
                        const id = "request-" + ++next;
                        sent.push(id);
                        onSend(id);
                        return exited("lane-mail: sent item=overseer id=" + id + " bytes=7 monitor=unread\n");
                    }
                    assert.equal(argv[4], "events");
                    if (box === "to-lane") return exited("count=" + sent.length + " first=" + (sent[0] ?? "") + "\n"
                        + sent.map(id => JSON.stringify({ id })).join("\n") + "\n");
                    assert.equal(box, "to-overseer");
                    const after = Number(argv[argv.indexOf("--after") + 1]);
                    if (hold && after !== Number.MAX_SAFE_INTEGER)
                        return new Promise(resolve => options.signal.addEventListener("abort",
                            () => resolve({ kind: "stopped", reason: "cancelled", stdout: "", stderr: "" }), { once: true }));
                    const rows = over.map((row, i) => ({ ...row, box, line: i + 1, count: over.length }))
                        .filter(row => row.line > after);
                    return exited("count=" + over.length + " first=" + (over[0]?.id ?? "") + "\n"
                        + rows.map(row => JSON.stringify(row)).join("\n") + (rows.length ? "\n" : "")
                        + (corrupt ? "not-json\n" : ""));
                } });
        return { owner, timers, over, delivered, logs, runs, sent,
            request: () => new Promise(resolve => owner.start({ id: "fleet.request", args: { text: "Request " + next } }, resolve)),
            notice(ref, text, extra = {}) {
                over.push({ id: "notice-" + (over.length + 1), kind: "notice", at: "2026-11-06T19:30:00Z",
                    from: "overseer", to: "owner", ref, text, ...extra });
            },
            duplicate() { duplicate = true; }, corrupt(value) { corrupt = value; }, hold() { hold = true; },
            onSend(fn) { onSend = fn; },
            change(edge) { if (edge === "home") chosen = null; else main = false; owner.sync(); },
            async tick() {
                assert.equal(timers.size, 1, "only unanswered requests keep a reader timer");
                const fn = timers.keys().next().value;
                timers.delete(fn);
                fn();
                await flush();
            } };
    }
    async function mainSnapshot(implementation) {
        const h = mailWorld(implementation);
        try {
            assert.equal(h.timers.size, 0, "no reader before a request");
            // A fast Jarvis session can answer before the send's receipt.
            h.onSend(id => {
                h.notice("someone-else", "Unrelated answer.");
                h.notice(id, "Still working.", { progress: true });
                h.notice(id, "The requested change is ready.");
                h.notice(id, "A repeated final answer.");
            });
            assert.equal((await h.request()).outcome, "completed");
            h.onSend(id => h.notice(id, "The second request is ready."));
            assert.equal((await h.request()).outcome, "completed");
            await h.tick();
            assert.deepEqual(h.delivered, [
                { content: "The requested change is ready.", labels: ["agent"] },
                { content: "The second request is ready.", labels: ["agent"] }
            ],
                "one final owner answer per request, not progress or another request");
            assert.equal(h.timers.size, 0, "answered requests stop reading");
            h.duplicate();
            assert.equal((await h.request()).outcome, "completed");
            assert.equal(h.delivered.length, 2, "a duplicate send receipt does not reopen an answered request");
            assert.equal(h.timers.size, 0);
        } finally { h.owner.close(); }
    }
    await mainSnapshot(Help);

    async function readerLifetime() {
        for (const edge of ["close", "home", "main"]) {
            const h = mailWorld(Help);
            await h.request();
            h.hold();
            await h.tick();
            const child = h.runs.at(-1);
            if (edge === "close") h.owner.close(); else h.change(edge);
            await flush();
            assert.equal(child.options.signal.aborted, true, edge + " ends the pending reader child");
            assert.equal(h.timers.size, 0, edge + " ends its timer");
            assert.deepEqual(h.delivered, [], edge + " delivers no late answer");
            h.owner.close();
        }
        const h = mailWorld(Help);
        try {
            await h.request();
            h.notice(h.sent[0], "Read after recovery.");
            h.corrupt(true);
            await h.tick();
            assert.equal(h.delivered.length, 0, "an incomplete snapshot releases nothing");
            assert.equal(h.logs.length, 1, "the failed read is reported");
            h.corrupt(false);
            await h.tick();
            assert.deepEqual(h.delivered, [{ content: "Read after recovery.", labels: ["agent"] }],
                "a failed read spends no cursor");
            assert.equal(h.timers.size, 0);
        } finally { h.owner.close(); }
    }
    await readerLifetime();

    function idleState() {
        const s = Session.initial();
        s.gen = 1; s.gate = { kind: "up" }; s.conversation = { kind: "active" };
        return s;
    }
    async function answerChannels() {
        const body = "The change is ready. The private answer is complete.";
        const notice = ["Jarvis Voice", "Jarvis answered your request"];
        for (const channel of ["idle", "busy", "closed", "changed", "withheld"]) {
            const s = idleState(), spoken = [], notes = [], deferred = [];
            if (channel === "closed") s.conversation = { kind: "ended" };
            if (["busy", "changed"].includes(channel)) s.turn = { kind: "thinking" };
            const voice = TaskVoice.create({ session: Session, state: () => s, dispatch: e => spoken.push(e),
                notify: (title, text) => { notes.push([title, text]); return Promise.resolve({ kind: "exited", code: 0 }); },
                log() {}, defer: fn => deferred.push(fn) });
            try {
                voice.answer(Policy.item(body, ["agent", "file"]));
                if (channel === "busy") {
                    assert.equal(deferred.length, 0, "another turn keeps the answer queued");
                    s.turn = { kind: "none" }; voice.session();
                }
                if (channel === "changed") {
                    s.gen++; s.turn = { kind: "none" }; voice.session();
                }
                for (const fn of deferred.splice(0)) fn();
                if (channel === "withheld") {
                    const event = spoken[0];
                    voice.withheld(s.gen, event.text, null);
                    voice.withheld(s.gen, event.text, null);
                }
                await flush();
                assert.deepEqual(notes, ["closed", "changed", "withheld"].includes(channel) ? [notice] : [], channel);
                if (!["closed", "changed"].includes(channel)) {
                    assert.equal(spoken.length, 1, channel + " dispatches one relay");
                    assert.equal(spoken[0].text, "Jarvis answered: " + body, "the short answer is the spoken result");
                    assert.deepEqual(spoken[0].labels, ["file", "agent"], "a summary keeps every contributing label");
                } else assert.equal(spoken.length, 0, channel + " never opens a conversation");
            } finally { voice.close(); }
        }
        const s = idleState(), events = [];
        const voice = TaskVoice.create({ session: Session, state: () => s, dispatch: e => events.push(e),
            notify() { assert.fail("a speakable summary does not notify"); }, log() {} });
        try {
            voice.answer(Policy.item("The repair is complete. " + "More detail follows. ".repeat(100) + "UNSPOKEN_TAIL", ["agent"]));
            await flush();
            assert.equal(events.length, 1);
            assert.ok(events[0].text.startsWith("Jarvis's answer, in brief: The repair is complete."));
            assert.ok(events[0].text.length <= 850 && !events[0].text.includes("UNSPOKEN_TAIL"), "long answers take an opening summary");
            assert.deepEqual(events[0].labels, ["agent"]);
        } finally { voice.close(); }
    }
    await answerChannels();

    // Prompt ownership outlives its playback. A main answer must not make
    // the next words look like a follow-up while a task still consumes them.
    async function answerWaitsForPrompt() {
        for (const ending of ["answered", "closed"]) {
            const s = idleState(), spoken = [], notes = [], deferred = [];
            const prompt = { task: "task-1", id: "prompt-1", kind: "permission", tool: "Bash", text: "Run the task command." };
            const voice = TaskVoice.create({ session: Session, state: () => s, dispatch: e => spoken.push(e),
                notify: (title, text) => { notes.push([title, text]); return Promise.resolve({ kind: "exited", code: 0 }); },
                log() {}, defer: fn => deferred.push(fn) });
            try {
                voice.prompts([prompt]);
                deferred.shift()();
                assert.equal(spoken[0].ask.prompt, prompt.id, "the task prompt was spoken and owns the next words");
                assert.equal(Session.relayRefusal(s), null, "Session alone considers the pause idle");
                voice.answer(Policy.item("The main request is complete.", ["agent"]));
                voice.session();
                assert.equal(deferred.length, 0, "a held prompt prevents scheduling an independent answer");
                assert.equal(spoken.length, 1, "no main answer speaks while the task owns the next utterance");
                if (ending === "answered") {
                    voice.prompts([]);
                    assert.equal(deferred.length, 1, "removing the answered prompt resumes the queued answer");
                    deferred.shift()();
                    assert.equal(spoken.length, 2);
                    assert.equal(spoken[1].ask, null);
                    assert.equal(spoken[1].text, "Jarvis answered: The main request is complete.");
                } else {
                    s.conversation = { kind: "ended" };
                    voice.session();
                    assert.equal(spoken.length, 1, "closing the conversation does not speak the queued answer");
                }
                await flush();
                assert.deepEqual(notes, ending === "closed"
                    ? [["Jarvis Voice", "Jarvis answered your request"]] : []);
            } finally { voice.close(); }
        }
    }
    await answerWaitsForPrompt();

    // Execute the labelled relay through Session and the real engine release
    // gate. This hold-only speech port consumes text but synthesizes no audio.
    // A remote recipient must ask before the port sees the answer.
    async function answerRelease() {
        const root = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "answer-release-"));
        const speechFile = path.join(root, "speech.js");
        fs.writeFileSync(speechFile, `"use strict";
module.exports = { spoken: [], select() {
    return { kind: "ready", recipients: [{ kind: "network", provider: "scripted-voice", account: "fixture",
        origin: "http://192.0.2.1:9" }], voices: [{ value: "fixture" }], open: () => ({
        close() {}, async *speak(items) { for await (const item of items) module.exports.spoken.push(item.content); }
    }) };
} };
`);
        try {
            await pluginCopy(path.join(backend, "ChainedEngine.js"), [
                ["const SPEECH = Object.freeze({ local: LocalSpeech.row });",
                    "const SPEECH = Object.freeze({ scripted: require(" + JSON.stringify(speechFile) + ") });"]
            ], async folder => {
                const Engine = require(path.join(folder, "backend/ChainedEngine.js"));
                const Voice = require(path.join(folder, "backend/TaskVoice.js"));
                const Audit = require(path.join(folder, "backend/Audit.js"));
                const audit = Audit.create({ state: path.join(root, "state"), now: () => Date.UTC(2026, 10, 6) });
                let s = idleState(), engine;
                const notes = [], faults = [];
                const dispatch = event => {
                    const reduced = Session.reduce(s, { ...event, at: 0 });
                    s = reduced.state;
                    for (const e of reduced.effects) if (e.kind === "brain-send") engine.brain.send(e, () => {});
                };
                const voice = Voice.create({ session: Session, state: () => s, dispatch,
                    notify: (title, text) => { notes.push([title, text]); return Promise.resolve({ kind: "exited", code: 0 }); }, log() {} });
                engine = Engine.create({ session: Session, state: () => s, dispatch, audit, router: {},
                    accounts: () => ({ choose: id => ({ kind: "accepted", account: { id, provider: "ollama", label: "local",
                        source: { kind: "local", origin: "http://127.0.0.1:11434" }, model: "fixture-model" } }) }),
                    policy: () => ({ profile: "standard", cloudVision: "ask" }), fault: value => faults.push(value), captionLimit: 8192,
                    tasks: { withheld: (...args) => voice.withheld(...args) } });
                try {
                    const configured = engine.configure({ mode: "hold", sounds: false, brain: "fixture", fallbacks: [], microphone: "", speaker: "" });
                    assert.equal(configured.kind, "ready");
                    voice.answer(Policy.item("Private cloud answer.", ["agent"]));
                    await flush();
                    assert.equal(s.approval.kind, "held", "agent text reaches Policy.release, not the desktop exemption");
                    assert.equal(s.approval.purpose, "release");
                    assert.deepEqual(require(speechFile).spoken, [], "no cloud speech before release");
                    engine.release.ended(s.approval);
                    await flush();
                    assert.deepEqual(notes, [["Jarvis Voice", "Jarvis answered your request"]], "a refused release exposes no answer on the card");
                    assert.deepEqual(require(speechFile).spoken, []);
                    assert.deepEqual(faults, []);
                } finally { engine.close(); voice.close(); audit.close(); }
            });
        } finally { fs.rmSync(root, { recursive: true, force: true }); }
    }
    await answerRelease();
    await mutant(path.join(backend, "ComputerHelp.js"), "request-answer-once", 'item.kind = "answered";',
        'if (false) item.kind = "answered";', mainSnapshot);
    console.log("case=main-request-answers passed control=request-answer-once detected");

    await daemonStartup(file);
    let controls = 0;
    for (const ending of ["eof", "signal"]) {
        await daemonLease(ending);
        await assert.rejects(() => daemonLease(ending, true), assert.AssertionError,
            "removing daemon teardown must fail its " + ending + " browser lifetime assertion");
        controls++;
    }
    async function control(name, needle, replacement, check) {
        await mutant(file, name, needle, replacement, (implementation, folder) => {
            fs.cpSync(path.join(backend, "skills"), path.join(folder, "skills"), { recursive: true });
            return check(implementation);
        });
        controls++;
    }
    const one = name => implementation => check(implementation, ...cases.find(row => row[0] === name));
    await mutant(file, "startup-sync-probe", '                request = versionRequest(environment);',
        '                version(environment); request = versionRequest(environment);',
        (_module, folder) => daemonStartup(path.join(folder, "Browser.js")));
    controls++;
    await control("setup-after-start", 'if (changed && !ended) prepare();', 'void changed;', setupAfterStart);
    await control("browser-topic-readiness", 'guidance.enableBrowser();', ';', setupAfterStart);
    await control("live-verification", 'if (status(environment).tone !== "ok") throw new Error("jarvis: browser=unverified");',
        'if (false) throw new Error("jarvis: browser=unverified");', setupAfterStart);
    await control("unverified-observation", 'try { return owner().record.observe(call); } catch { return undefined; }',
        'return owner().record.observe(call);', setupAfterStart);
    await control("guidance-version-cache", 'guidanceCache === null || guidanceCache.version !== installed',
        'guidanceCache === null', versionCache);
    await control("guidance-session-cache", 'if (guidanceCache === null || guidanceCache.version !== installed) {',
        'if (true) {', versionCache);
    await control("private-home", "HOME: privateHome, LANG:", "HOME: environment.HOME, LANG:", confinement);
    await control("private-session", 'const session = "jarvis-" + crypto.randomBytes(4).toString("hex");',
        'const session = "jarvis-00000000";', confinement);
    await control("short-session", 'crypto.randomBytes(4).toString("hex")', "crypto.randomUUID()", confinement);
    await control("no-namespace", "AGENT_BROWSER_CONFIG: configFile };",
        "AGENT_BROWSER_CONFIG: configFile, AGENT_BROWSER_NAMESPACE: session };", confinement);
    await control("neutral-config", "AGENT_BROWSER_CONFIG: configFile", "AGENT_BROWSER_CONFIG: environment.AGENT_BROWSER_CONFIG", confinement);
    await control("scrub-env", "const env = { PATH:", "const env = { ...environment, PATH:", confinement);
    await control("boundaries", '"--content-boundaries", "--max-output"', '"--debug", "--max-output"', confinement);
    await control("max-output", 'String(OUTPUT_BYTES), "--json"', '"999999", "--json"', confinement);
    await control("policy-url", '"url", "getattribute"', '"get", "getattribute"', verification);
    await control("policy-attribute", '"getattribute", "click"', '"get", "click"', one("fill"));
    await control("policy-close", '"fill", "close"', '"fill"', verification);
    await control("policy-launch", 'allow: ["launch", "navigate",', 'allow: ["navigate",', verification);
    for (const category of ["eval", "upload", "download", "state", "network"])
        await control("deny-" + category, '"' + category + '"', '"fixture-' + category + '"', implementation => confinement(implementation, category));
    await control("output-bound", "bytes.length <= OUTPUT_BYTES", "true", bounded);
    await control("password", "if (fresh.target.password) throw", "if (false) throw", one("password"));
    await control("reference", "if (!ref || typeof ref.role !== \"string\") throw", "if (false) throw", one("reference"));
    await control("page-url", 'if (refined.kind !== "call") throw new Error("jarvis: browser=page-url");',
        'if (false) throw new Error("jarvis: browser=page-url");', one("redirect"));
    await control("target-race", "site !== page(before) ||", "false ||", one("site-race"));
    await control("observed-target", "JSON.stringify(fresh) !== JSON.stringify(observation)", "false", one("changed-click"));
    await control("submit", 'type === "submit" || type === "image"', 'type === "fixture-submit" || type === "image"', implementation => {
        // textbox role isolates explicit type from the button default rule.
        mode({ type: "submit" }); const owner = implementation.create({ environment });
        try { assert.equal(owner.record.observe(call("click", { ref: "@e1" })).target.submit, true); } finally { owner.close(); }
    });
    await control("version-floor", "found[1] < floor[1]", "false", implementation => {
        mode({ version: "0.37.9" }); assert.throws(() => implementation.create({ environment }), /version-floor/);
    });
    await control("verified-version", "marker.version !== installed", "false", implementation => {
        fs.mkdirSync(path.dirname(marker), { recursive: true }); fs.writeFileSync(marker, JSON.stringify({ version: "0.38.1" }));
        readiness(implementation, { version: "0.38.2" }, "warning");
    });
    await control("verification", 'answer.data.url !== "about:blank"', "false", implementation => {
        mode({ verifyUrl: "https://wrong.test/" }); const owner = implementation.create({ environment });
        try { assert.throws(() => owner.verify(), /verify-url/); } finally { owner.close(); }
    });
    function failedClose(implementation) {
        mode({ closeFail: true });
        const owner = implementation.create({ environment });
        assert.throws(() => owner.verify(), /close-failed/);
        assert.equal(fs.existsSync(marker), false, "failed close cannot leave ready");
    }
    failedClose(Browser);
    // A vendor that answers the launch as failed opened no session: close sends it nothing.
    const refusals = [
        [{ socketRefused: true }, "command-failed", /^Session name 'jarvis-[0-9a-f]{8}' is too long\./],
        [{ launchFailed: true }, "command-failed", /^Failed to launch Chrome/],
        [{ missing: true }, "missing", /^Chrome not found\./]
    ];
    function refusedLaunch(implementation) {
        for (const [fixture, key, said] of refusals) {
            mode(fixture); fs.rmSync(marker, { force: true });
            const vendor = [];
            const owner = implementation.create({ environment, log: text => vendor.push(text) });
            assert.throws(() => owner.verify(), error => error.message === "jarvis: browser=" + key, key);
            assert.doesNotThrow(() => owner.close());
            const rows = calls().filter(row => row.args.includes("--json"));
            assert.deepEqual(rows.map(row => row.args.slice(row.args.indexOf("--json") + 1)), [["get", "url"]], key + " sends no close");
            assert.equal(fs.existsSync(rows[0].env.XDG_RUNTIME_DIR), false, key + " releases session files");
            assert.equal(fs.existsSync(marker), false);
            assert.equal(vendor.length, 1, key + " logs one vendor text");
            assert.match(vendor[0], said);
        }
    }
    refusedLaunch(Browser);
    // The sink gets a character-boundary prefix within 2048 bytes; é straddles the cut.
    const long = "x".repeat(2047) + "\u00e9 vendor tail";
    function clipped(implementation) {
        mode({ fail: true, failText: long });
        const vendor = [];
        const owner = implementation.create({ environment, log: text => vendor.push(text) });
        try { assert.throws(() => owner.verify(), /browser=command-failed/); } finally { owner.close(); }
        assert.equal(vendor.length, 1);
        assert.ok(Buffer.byteLength(vendor[0]) <= 2048 && Buffer.byteLength(vendor[0]) >= 2044, "clip keeps the bound");
        assert.ok(long.startsWith(vendor[0]), "clip keeps a prefix");
        assert.equal(vendor[0].includes("\ufffd"), false, "clip splits no character");
    }
    clipped(Browser);
    // jarvisd makes its owner with no sink: Service.qml takes any daemon stderr line as fatal.
    // A child runs the real module so no stub stands between it and stderr.
    function quiet(module) {
        for (const fixture of [{ fail: true }, { socketRefused: true }, { malformed: true }]) {
            mode(fixture);
            const child = cp.spawnSync(process.execPath, ["-e", `
                const owner = require(process.argv[1]).create({ environment: process.env });
                owner.record.start({ id: "browser", args: { command: "read", args: {} } }, answer => {
                    owner.close(); process.stdout.write(answer.outcome); });`, module],
                { env: process.env, encoding: "utf8", timeout: 20000 });
            assert.equal(child.status, 0, child.stderr);
            assert.equal(child.stdout, "failed", JSON.stringify(fixture) + " reaches a vendor failure");
            assert.equal(child.stderr, "", JSON.stringify(fixture) + " daemon owner writes no vendor text");
        }
    }
    quiet(file);
    // A launch with no vendor answer may have left a browser: close still runs once.
    const silences = [[{ malformed: true }, undefined, "reply-json"], [{ launchDelayMs: 6000 }, 1500, "command cause=ETIMEDOUT"]];
    function silentLaunch(implementation) {
        for (const [fixture, commandMs, key] of silences) {
            mode(fixture);
            const vendor = [];
            const owner = implementation.create({ environment, commandMs, log: text => vendor.push(text) });
            assert.throws(() => owner.verify(), error => error.message === "jarvis: browser=" + key, key);
            owner.close();
            assert.equal(calls().filter(row => row.args.at(-1) === "close").length, 1, JSON.stringify(fixture) + " closes once");
            // Vendor stdout can carry page content; only its size may reach the log.
            assert.equal(vendor.some(text => text.includes("not json")), false, "no vendor stdout in the log");
        }
    }
    silentLaunch(Browser);
    // The first open's launch runs as a killable child; a cancel during it still ends the vendor session.
    async function cancelLaunch(implementation) {
        mode({ launchDelayMs: 5000 });
        const owner = implementation.create({ environment });
        const result = run(owner, "open", { url: "https://first.test/" });
        for (let n = 0; !calls().some(row => row.args.at(-1) === "url"); n++) {
            assert.ok(n < 500, "the fixture reaches its pending launch");
            await new Promise(resolve => setTimeout(resolve, 10));
        }
        owner.record.cancel();
        assert.equal((await result).outcome, "failed");
        assert.equal(fs.existsSync(path.join(process.env.JARVIS_TEST_ROOT, "browser-launch-completed")), false, "cancel kills the launch child");
        assert.equal(calls().filter(row => row.args.at(-1) === "close").length, 1, "an in-flight launch is closed once");
        assert.equal(calls().some(row => row.args.includes("open")), false, "a cancelled launch starts no command");
    }
    await cancelLaunch(Browser);
    await control("vendor-log", "log(clip(answer.text));", "void clip(answer.text);", refusedLaunch);
    await control("vendor-clip", "bytes.length <= VENDOR_LOG_BYTES ? text", "true ? text", clipped);
    await mutant(file, "daemon-sink", "log = null }", "log = vendorLine }", (implementation, folder) => quiet(path.join(folder, "Browser.js")));
    controls++;
    await control("unknown-before-spawn", 'state = { kind: "unknown" };\n        return true;', "return true;", cancelLaunch);
    await control("refused-close", 'if (state.kind !== "none") {', "if (true) {", refusedLaunch);
    await control("silent-launch", 'answer.kind === "refused" ? "none" : "unknown"', 'answer.kind === "refused" ? "none" : "none"', silentLaunch);
    await control("verified-close", 'try { decode(result); } catch { throw new Error("jarvis: browser=close-failed"); }',
        'void result;', failedClose);
    await mutant(path.join(backend, "Policy.js"), "submit-effect", 'if (input.target.submit === true) effect = "external";',
        'if (false && input.target.submit === true) effect = "external";', implementation => {
            const request = call("click", { ref: "@e1" });
            assert.equal(implementation.decide(request, { locked: false, profile: "trusted", taint: clean, grants: [],
                input: { target: { kind: "site", id: "https://first.test", password: false, submit: true } } }).effect, "external");
        }); controls++;
    await mutant(path.join(backend, "Tools.js"), "fill-flag", 'pattern: "^(?!-)[^\\\\u0000]*$"', 'pattern: "^[^\\\\u0000]*$"', implementation => {
        assert.equal(implementation.refine(call("fill", { ref: "@e1", text: "--cdp" })).kind, "refuse");
    }); controls++;
    await control("cancel-child", 'if (active !== null) active.kill("SIGKILL");', 'if (false && active !== null) active.kill("SIGKILL");', cancellation);
    await control("generation-close", 'if (generation !== state.gen || state.conversation.kind === "ended") clear();',
        'if (state.conversation.kind === "ended") clear();', implementation => lifecycle(implementation, "generation"));
    await control("conversation-close", 'if (generation !== state.gen || state.conversation.kind === "ended") clear();',
        'if (generation !== state.gen) clear();', implementation => lifecycle(implementation, "end"));
    await control("lease-close", 'close() { closed = true; guidance.close(); if (probe !== null) probe.kill("SIGKILL"); clear(); }', 'close() { closed = true; guidance.close(); if (probe !== null) probe.kill("SIGKILL"); }', implementation => lifecycle(implementation, "lease"));
    console.log("test-jarvis-browser: ok cases=" + (cases.length + 6 + refusals.length + silences.length) + " controls=" + controls);
}, daemonStandins);
