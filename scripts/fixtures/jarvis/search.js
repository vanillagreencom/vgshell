// Responses shapes: tools-web-search and responses/methods/create, read
// 2026-11-10. Synthetic content only; never a billed request.
"use strict";
const { assert, fs, path, tree } = require("./policy.js");
const backend = path.join(tree, "shell/plugins/vgs.jarvis/backend");
const Policy = require(path.join(backend, "Policy.js"));
const Audit = require(path.join(backend, "Audit.js"));
const WebSearch = require(path.join(backend, "WebSearch.js"));
const Check = require("../schema-check.js");
const schema = require("../jarvis-search/responses.schema.js");

function response() {
    const value = { status: "completed", service_tier: "default", usage: { input_tokens: 100, output_tokens: 50, input_tokens_details: { cached_tokens: 20 } },
        tool_usage: { web_search: { num_requests: 1 } },
        output: [
            { type: "web_search_call", status: "completed", action: { type: "search", sources: [{ type: "url", url: "https://example.test/news" }] } },
            { type: "message", content: [{ type: "output_text", text: "A sourced answer.", annotations: [
                { type: "url_citation", title: "News", url: "https://example.test/news", start_index: 0, end_index: 16 }
            ] }] }
        ] };
    assert.deepEqual(Check.errors(schema, "Response", value), []);
    return value;
}

function selected(logic, brain = "claude", voice = "local", policy = Policy) {
    const origin = "https://api.openai.com";
    const key = { reference: { provider: "openai", origin }, secrets: { lookup() { assert.fail("selection must not read a key"); } } };
    const recipients = policy.recipients({ conversation: "search-fixture", profile: "standard", cloudVision: "ask",
        brain: { kind: "network", provider: brain, account: "brain", origin: brain === "openai" ? origin : "https://api.anthropic.com" },
        speech: [voice === "local" ? { kind: "local", provider: voice, account: "" }
            : { kind: "network", provider: "openai", origin, account: "voice" }] });
    return logic.keyFor({ recipients, brain: { provider: { id: brain }, key: brain === "openai" ? key : null },
        speech: { id: voice, key: voice === "openai-realtime" ? key : null } });
}

function eligibility(logic = WebSearch, policy = Policy) {
    for (const [brain, voice, offered] of [
        ["claude", "local", false], ["openai", "local", true], ["claude", "openai-realtime", true], ["openai", "openai-realtime", true]
    ]) assert.equal(selected(logic, brain, voice, policy) !== null, offered, brain + "/" + voice);
}

function rig(logic = WebSearch, { cost = 0, status = 200, value = response(), onLookup = () => {}, onTransfer = () => {} } = {}) {
    const state = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "search-"));
    const audit = Audit.create({ state, now: () => Date.UTC(2026, 10, 10, 12) });
    if (cost !== 0) assert.equal(audit.usage({ call: "realtime", model: "gpt-realtime-2.1",
        usage: { input_tokens: 0, output_tokens: cost * 1e6 / 64, input_token_details: {},
            output_token_details: { audio_tokens: cost * 1e6 / 64 } } }).kind, "recorded");
    const requests = [], buffers = [];
    let record, live = true, lookups = 0, cancels = 0, closes = 0;
    const key = { reference: { provider: "openai", origin: "https://api.openai.com" }, secrets: { lookup() {
        lookups++;
        const key = Buffer.from("search-private-key");
        buffers.push(key);
        onLookup();
        return key;
    } } };
    const recipients = Policy.recipients({ conversation: "search", profile: "standard", cloudVision: "ask",
        brain: { kind: "network", provider: "openai", origin: key.reference.origin, account: "fixture" },
        speech: [{ kind: "local", provider: "local", account: "" }] });
    const conversation = () => live ? { key, grants: () => [], release: item => Policy.release(item, recipients),
        transfer: (_item, start) => { onTransfer(); return start(); }, net: { async request(item, options, grants) {
            requests.push({ item, options, grants });
            assert.deepEqual(Check.errors(schema, "Request", JSON.parse(item.content)), []);
            return { kind: "response", response: status === 200 ? new Response(JSON.stringify(value)) : {
                status, body: { cancel: async () => { cancels++; }, getReader() { assert.fail("provider error body read"); } }
            }, close: () => { closes++; } };
        } } } : null;
    const owner = logic.install({ router: { register(id, executor) { assert.equal(id, "web"); record = executor; } },
        conversation, audit, cap: () => 25 });
    return { audit, record, state, requests, buffers, owner,
        call: (labels = ["speech"], authorize = () => ({ kind: "allow" })) => new Promise(resolve => record.start({ id: "web.search", args: { query: "news?" } },
            resolve, authorize, { labels })),
        live: value => { live = value; }, facts: () => ({ lookups, cancels, closes }),
        close() { owner.close(); audit.close(); } };
}

async function execution(logic = WebSearch) {
    for (const [cost, expected, sent] of [[0, "completed", 1], [25, "failed", 0]]) {
        const w = rig(logic, { cost });
        try {
            assert.equal(w.record.available(), true);
            const result = await w.call();
            assert.equal(result.outcome, expected);
            assert.equal(w.requests.length, sent, "the cap refuses before the network");
            assert.equal(w.facts().lookups, sent, "the cap refuses before key lookup");
            if (sent) {
                const request = w.requests[0];
                assert.deepEqual(JSON.parse(request.item.content), { model: "gpt-4.1-mini", service_tier: "default", input: "news?",
                    tools: [{ type: "web_search" }], tool_choice: "required", max_tool_calls: 1, parallel_tool_calls: false,
                    max_output_tokens: 2048, include: ["web_search_call.action.sources"], store: false });
                assert.deepEqual(request.item.labels, ["speech"]);
                assert.equal(request.options.url, "https://api.openai.com/v1/responses");
                assert.equal(request.options.key.value, "search-private-key");
                assert.deepEqual(JSON.parse(result.content), { outcome: "completed", answer: "A sourced answer.",
                    citations: [{ title: "News", url: "https://example.test/news" }] });
                assert.equal(w.buffers.every(buffer => buffer.every(byte => byte === 0)), true);
                const report = w.audit.usageWindow();
                assert.equal(report.byTool["web.search"].calls, 1);
                assert.ok(Math.abs(report.total.costUsd - 0.013314) < 1e-12);
            }
            w.live(false);
            assert.equal(w.record.available(), false);
        } finally { w.close(); }
    }
    // Billable tool requests are not the number of output action items.
    for (const [billed, expected] of [[0, 0.000114], [2, 0.026514], [null, null]]) {
        const value = response();
        if (billed === null) delete value.tool_usage;
        else value.tool_usage.web_search.num_requests = billed;
        assert.deepEqual(Check.errors(schema, "Response", value), []);
        const w = rig(logic, { value });
        try {
            assert.equal((await w.call()).outcome, "completed");
            const row = w.audit.usageWindow().rows[0];
            assert.equal(row.searches, billed);
            assert.equal(row.pricing, billed === null ? "unpriced" : "priced");
            if (expected === null) {
                assert.equal(row.costUsd, null);
                assert.equal(Object.hasOwn(row.tokens, "searchContent"), false);
            } else assert.ok(Math.abs(row.costUsd - expected) < 1e-12);
        } finally { w.close(); }
    }
    const priority = response();
    priority.service_tier = "priority";
    const otherTier = rig(logic, { value: priority });
    try {
        assert.equal((await otherTier.call()).outcome, "completed");
        const row = otherTier.audit.usageWindow().rows[0];
        assert.equal(row.tier, "priority");
        assert.equal(row.pricing, "unpriced", "a different actual tier cannot use standard prices");
        assert.equal(row.costUsd, null);
    } finally { otherTier.close(); }
    for (const boundary of ["key", "audit", "queued-lease"]) {
        let allowed = true;
        const revoke = () => { allowed = false; };
        const hooks = boundary === "key" ? { onLookup: revoke } : boundary === "audit" ? { onTransfer: revoke }
            : { onLookup: () => { setImmediate(revoke); } };
        const stale = rig(logic, hooks);
        try {
            const answer = await stale.call(["speech"], () => ({ kind: allowed ? "allow" : "refuse" }));
            assert.equal(answer.outcome, "failed", boundary);
            assert.equal(stale.facts().lookups, 1, boundary);
            assert.equal(stale.requests.length, 0, boundary + " cannot outlive the authority to send");
            assert.equal(stale.buffers.every(buffer => buffer.every(byte => byte === 0)), true, boundary);
        } finally { stale.close(); }
    }
    const unread = rig(logic);
    try {
        fs.mkdirSync(path.join(unread.state, "audit"), { recursive: true, mode: 0o700 });
        fs.writeFileSync(path.join(unread.state, "audit/2026-11-09.jsonl"), '{"kind":"usage"', { mode: 0o600 });
        assert.equal((await unread.call()).outcome, "failed");
        assert.equal(unread.facts().lookups, 0);
        assert.equal(unread.requests.length, 0, "an unread day is not zero spend");
    } finally { unread.close(); }
    for (const status of [401, 429, 503]) {
        const w = rig(logic, { status });
        try {
            const answer = await w.call();
            assert.equal(answer.outcome, "failed");
            assert.equal(w.facts().cancels, 1, "failed body cancelled unread");
            assert.equal(w.facts().closes, 1);
            assert.equal(w.audit.usageWindow().total.unpriced, 1);
            assert.equal(w.buffers.every(buffer => buffer.every(byte => byte === 0)), true);
        } finally { w.close(); }
    }
    const w = rig(logic);
    try {
        const answer = await w.call(["speech", "file"]);
        assert.equal(answer.outcome, "failed", "ungranted file query is refused at the last send boundary");
        assert.equal(w.requests.length, 0);
        assert.equal(w.facts().lookups, 0);
    } finally { w.close(); }
}

/** Real reducer/router release ordering, with the engine's release port fake. */
async function releaseCase(logic, policy, accepted) {
    const { load } = require(path.join(tree, "bin/lib/qml-library.js"));
    const Session = load(path.join(tree, "shell/plugins/vgs.jarvis/Session.js"));
    const { SessionRunner, unavailable } = require(path.join(backend, "session-runner.js"));
    const state = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "search-release-"));
    const audit = Audit.create({ state });
    const ports = { ...unavailable(), transcript() {}, brain: { send() {}, outcome() {}, cancel: (_e, done) => done(), close() {} } };
    const runner = new SessionRunner(Session, ports, { now: () => 0, set: () => ({}), clear() {} }, () => {});
    const recipients = policy.recipients({ conversation: "release-search", profile: "standard", cloudVision: "ask",
        brain: { kind: "network", provider: "openai", account: "fixture", origin: "https://api.openai.com" },
        speech: [{ kind: "local", provider: "local", account: "" }] });
    let held, finish, sends = 0, delivered;
    const router = logic.create({ session: Session, state: () => runner.state, dispatch: event => runner.dispatch(event),
        context: () => ({ profile: "standard", locked: false }), audit, result(value) { delivered = value; },
        release: item => {
            held = policy.release(item, recipients);
            return held.kind === "send" ? true : new Promise(resolve => { finish = resolve; });
        } });
    Object.assign(ports, router.ports);
    router.register("web", { commands: [], timeoutMs: 1000, cancellable: true, cancel() {},
        start(_call, done) { sends++; done({ outcome: "completed", content: "completed" }); } });
    router.register("compositor", { commands: ["hyprctl"], timeoutMs: 1000, cancellable: true, cancel() {},
        start() { assert.fail("web-tainted changes must ask"); } });
    try {
        runner.dispatch({ type: "snapshot", locked: false, engine: "chained", configured: true, settings: { holdToTalk: true } });
        runner.dispatch({ type: "say", text: "news?" });
        const turn = runner.state.turn;
        assert.equal(turn.kind, "thinking");
        router.observe(turn, ["speech", "file"]);
        const waiting = router.route({ kind: "tool-call", id: "search-1", tool: "web.search", arguments: { query: "file-derived question" } }, turn);
        await Promise.resolve();
        await Promise.resolve();
        assert.equal(held.kind, "ask", "a file-derived query needs release");
        assert.deepEqual(held.needed, ["file"]);
        assert.equal(sends, 0, "release is judged before the action can send");
        assert.equal(runner.state.action.kind, "none", "release can hold Session's approval slot");
        finish(accepted);
        const answer = await waiting;
        if (!accepted) {
            assert.equal(answer.reason, "release-withheld");
            assert.equal(sends, 0);
        } else {
            assert.equal(answer.kind, "proposed");
            assert.equal(sends, 1, "the admitted query runs once");
            assert.deepEqual(delivered.results[0].item.labels, ["web"], "the result taints the turn");
            assert.equal(router.route({ kind: "tool-call", id: "after-web", tool: "windows.close", arguments: { window: "0x1" } }, turn).kind,
                "held", "a change after search needs action approval");
        }
    } finally { audit.close(); }
}

async function release(logic, policy = Policy) {
    for (const accepted of [false, true]) await releaseCase(logic, policy, accepted);
}

module.exports = { response, eligibility, execution, rig, release };
