#!/usr/bin/env node
// Real files and audit admission callbacks inside J09. No real executor runs.
"use strict";
const { assert, fs, path, tree, world, mutant, fsFault } = require("./fixtures/jarvis/policy.js");
const file = path.join(tree, "shell/plugins/vgs.jarvis/backend/Audit.js");
const Audit = require(file);
const Desktop = require(path.join(tree, "shell/plugins/vgs.jarvis/backend/Desktop.js"));
const RedactFile = path.join(tree, "shell/plugins/vgs.jarvis/backend/Redact.js");
const PrivateFile = path.join(tree, "shell/plugins/vgs.jarvis/backend/Private.js");

world(() => {
    const Usage = require(path.join(tree, "shell/plugins/vgs.jarvis/backend/Usage.js"));
    const UsageCli = require(path.join(tree, "shell/plugins/vgs.jarvis/backend/usage.js"));
    const usageFile = path.join(tree, "shell/plugins/vgs.jarvis/backend/Usage.js");
    const realtimeUsage = { input_tokens: 132, output_tokens: 121,
        input_token_details: { text_tokens: 119, audio_tokens: 13, image_tokens: 0, cached_tokens: 64,
            cached_tokens_details: { text_tokens: 64, audio_tokens: 0, image_tokens: 0 } },
        output_token_details: { text_tokens: 30, audio_tokens: 91 } };
    function prices(logic) {
        for (const [event, cost, counts] of [
            [{ call: "realtime", model: "gpt-realtime-2.1", usage: realtimeUsage }, 0.0072056, { inputAudio: 13, cachedText: 64 }],
            [{ call: "transcription", model: "gpt-live-transcribe", usage: { type: "duration", seconds: 60 } }, 0.017, { seconds: 60 }],
            [{ call: "search", model: "gpt-4.1-mini", tier: "default", searches: 1, usage: { input_tokens: 100, output_tokens: 50, input_tokens_details: { cached_tokens: 20 } } }, 0.013314, { input: 100, searchContent: 8000 }],
            [{ call: "search", model: "gpt-4.1-mini", tier: "priority", searches: 1, usage: { input_tokens: 100, output_tokens: 50, input_tokens_details: { cached_tokens: 20 } } }, null, { input: 100 }],
            [{ call: "realtime", model: "gpt-realtime-2.1" }, null, null],
            [{ call: "search", model: "unknown", usage: { input_tokens: 1, output_tokens: 1 } }, null, { input: 1 }],
            [{ call: "transcription", model: "gpt-live-transcribe", usage: { type: "tokens", input_tokens: 13, output_tokens: 9, input_token_details: { audio_tokens: 13 } } }, null, { inputAudio: 13 }],
            [{ call: "realtime", model: "gpt-realtime-2.1", usage: { ...realtimeUsage, input_token_details: { ...realtimeUsage.input_token_details, cached_tokens: 1 } } }, null, { input: 132 }]
        ]) {
            const row = logic.record(event);
            assert.equal(row.pricing, cost === null ? "unpriced" : "priced");
            if (cost === null) assert.equal(row.costUsd, null, "unknown never becomes a zero price");
            else assert.ok(Math.abs(row.costUsd - cost) < 1e-12, JSON.stringify(row));
            if (counts === null) assert.equal(row.tokens, null);
            else for (const [key, count] of Object.entries(counts)) assert.equal(row.tokens[key], count, key);
        }
    }
    prices(Usage);
    mutant(usageFile, "cached-price", "(input - cached) * rates[0]", "input * rates[0]", prices);
    mutant(usageFile, "standard-tier", 'row.tier !== "default"', "false", prices);
    console.log("control=usage-cached-price detected");
    console.log("control=usage-standard-tier detected");
    const usageState = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "usage-window-"));
    const until = Date.UTC(2026, 10, 10, 12), since = until - 7 * 86400000;
    let wall = since - 1;
    const usageWriter = Audit.create({ state: usageState, now: () => wall });
    const eventUsage = { call: "transcription", model: "gpt-live-transcribe", usage: { type: "duration", seconds: 60,
        transcript: "PRIVATE transcript", key: "PRIVATE key" } };
    try {
        for (const time of [since - 1, since, until]) {
            wall = time;
            assert.equal(usageWriter.usage(eventUsage).kind, "recorded");
        }
        assert.equal(usageWriter.usage({ call: "search", model: "gpt-4.1-mini" }).kind, "recorded");
        const report = UsageCli.main(["--state", usageState], {}, until);
        assert.equal(report.rows.length, 3, "the seven-day boundary includes its exact start, never earlier rows");
        assert.deepEqual([report.total.calls, report.total.priced, report.total.unpriced, report.total.costUsd],
            [3, 2, 1, 0.034]);
        assert.deepEqual([report.byCall.transcription.calls, report.byTool.voice.tokens.seconds], [2, 120]);
        assert.equal(JSON.stringify(report).includes("PRIVATE"), false, "usage holds no provider content");
        for (const file of fs.readdirSync(path.join(usageState, "audit"))) {
            const log = path.join(usageState, "audit", file);
            assert.equal(fs.statSync(log).mode & 0o777, 0o600);
            assert.equal(fs.readFileSync(log, "utf8").includes("PRIVATE"), false);
        }
        const latest = path.join(usageState, "audit/2026-11-10.jsonl");
        fs.appendFileSync(latest, '{"kind":"usage"');
        assert.throws(() => Audit.readUsage({ state: usageState, now: until }), /audit=usage-read/, "a partial file is unread, not zero spend");
    } finally { usageWriter.close(); }
    function missingUsage(logic) {
        const state = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "usage-missing-"));
        const writer = logic.create({ state, now: () => until });
        try {
            assert.equal(writer.usage(eventUsage).kind, "recorded");
            fsFault("writeSync", () => { const error = new Error("planted ledger failure"); error.code = "EIO"; throw error; }, () => {
                assert.equal(writer.usage(eventUsage).kind, "refuse");
            });
            assert.equal(writer.usage(eventUsage).kind, "recorded", "the filesystem recovers");
            const window = writer.usageWindow();
            assert.equal(window.complete, false, "a recovered append cannot reconstruct missing usage");
            assert.equal(window.total.calls, 2, "only actually recorded calls are reported");
        } finally { writer.close(); }
    }
    missingUsage(Audit);
    mutant(file, "usage-missing-latch", "usageIncomplete = true", "usageIncomplete = false", missingUsage);
    console.log("control=usage-missing-latch detected");
    const base = process.env.XDG_STATE_HOME;
    const today = Date.parse("2026-09-30T12:00:00.000Z");
    let serial = 0;
    function state() { return path.join(base, "audit-" + ++serial); }
    function currentState() {
        const root = state();
        fs.mkdirSync(path.join(root, "audit"), { recursive: true, mode: 0o700 });
        fs.writeFileSync(path.join(root, "audit-cause-version.json"), '{"version":1}\n', { mode: 0o600 });
        return root;
    }
    const event = { kind: "action", gen: 2, op: 3, tool: "files.write",
        args: { path: "/synthetic", text: "planted-arbitrary-credential" },
        effect: "persistent", decision: "allow", confirmed: "none", outcome: "pending" };
    function records(root, date = "2026-09-30") {
        const content = fs.readFileSync(path.join(root, "audit", date + ".jsonl"), "utf8");
        assert.equal(content.endsWith("\n"), true);
        const lines = content.trimEnd().split("\n");
        for (const line of lines) assert.ok(Buffer.byteLength(line + "\n") <= 4096, "line including LF bounded");
        return lines.map(line => JSON.parse(line));
    }
    function withWriter(logic, options, check) {
        const writer = logic.create({ state: state(), now: () => today, ...options });
        try { check(writer); } finally { writer.close(); }
    }
    function checkFailures(logic) {
        const root = currentState();
        const folder = path.join(root, "audit");
        fs.mkdirSync(folder, { recursive: true, mode: 0o700 });
        const saved = (op, changes = {}) => ({ ...event, time: "2026-09-30T12:00:00.000Z", op,
            args: { text: "[redacted]", path: "[redacted]" }, outcome: "failed", ...changes });
        fs.writeFileSync(path.join(folder, "2026-09-29.jsonl"), JSON.stringify(saved(1)) + "\n", { mode: 0o600 });
        const content = JSON.stringify(saved(2)) + "\n" + Array.from({ length: 1000 }, (_, n) =>
            JSON.stringify(saved(n + 3, { decision: "allow", outcome: "completed" })) + "\n").join("")
            + Array.from({ length: 24 }, (_, n) => JSON.stringify(saved(2000 + n, {
                time: "2026-09-30T12:00:" + String(n).padStart(2, "0") + ".000Z" })) + "\n").join("")
            + JSON.stringify(saved(3000, { outcome: "completed" })) + "\n";
        const latest = path.join(folder, "2026-09-30.jsonl");
        fs.writeFileSync(latest, content, { mode: 0o600 });
        let writer;
        const reads = [];
        fsFault("readSync", (original, fd, buffer, offset, length, position) => {
            reads.push({ length, position, file: fs.readlinkSync("/proc/self/fd/" + fd) });
            return original(fd, buffer, offset, length, position);
        }, () => { writer = logic.create({ state: root, now: () => today }); });
        try {
            assert.deepEqual(reads.filter(read => read.file.endsWith(".jsonl")).map(({ length, position }) => ({ length, position })),
                [{ length: 65536, position: Buffer.byteLength(content) - 65536 }],
                "seed requests only the bounded tail of the oversized daily file");
            const rows = writer.failures();
            assert.equal(rows.length, 20);
            assert.equal(rows[0].time, "2026-09-30T12:00:04.000Z");
            assert.deepEqual(rows[0], { time: rows[0].time, tool: "files.write", effect: "persistent",
                decision: "allow", outcome: "failed", refusal: null, cause: null });
            rows[0].tool = "edited";
            assert.equal(writer.failures()[0].tool, "files.write");
        } finally { writer.close(); }
        const changes = [];
        withWriter(logic, { state: root, changed: rows => changes.push(rows) }, writer => {
            assert.equal(writer.record({ ...event, outcome: "completed" }).kind, "recorded");
            assert.equal(changes.length, 0);
            for (const change of [{ outcome: "failed" }, { outcome: "unknown" }, { decision: "refuse" },
                { kind: "release", decision: "withhold", refusal: "expired" },
                { kind: "release", decision: "send", outcome: "failed", cause: "voice-stopped" }]) {
                assert.equal(writer.record({ ...event, ...change }).kind, "recorded");
                const rows = writer.failures();
                assert.equal(rows.length, 20);
                assert.deepEqual(rows.at(-1), { time: "2026-09-30T12:00:00.000Z", tool: change.kind === "release" ? "release" : "files.write",
                    effect: "persistent", decision: change.decision ?? "allow", outcome: change.outcome ?? "pending", refusal: change.refusal ?? null,
                    cause: change.cause ?? null });
                assert.deepEqual(changes.at(-1), rows);
            }
        });
    }
    checkFailures(Audit);
    mutant(file, "failure seed whole file", "const buffer = Buffer.alloc(Math.min(stat.size, TAIL_BYTES));",
        "const buffer = Buffer.alloc(stat.size);", checkFailures);
    mutant(file, "failure list args", ": { time: record.time, tool: record.tool", ": { ...record, time: record.time, tool: record.tool", checkFailures);
    mutant(file, "failure list bound", ".slice(-20)", ".slice(-21)", checkFailures);
    mutant(file, "failure callback", '&& retain(value)) changed(failures());', '&& retain(value)) void failures();', checkFailures);
    function checkOrder(logic) {
        const root = state();
        withWriter(logic, { state: root }, writer => {
            let starts = 0;
            const answer = writer.before(event, () => {
                starts++;
                assert.deepEqual(records(root), [{
                    time: "2026-09-30T12:00:00.000Z", kind: "action", gen: 2, op: 3,
                    tool: "files.write", args: { path: "[redacted]", text: "[redacted]" },
                    effect: "persistent", decision: "allow", confirmed: "none", outcome: "pending"
                }], "decision persisted before callback");
                return "executor-result-private";
            });
            assert.equal(answer.kind, "started");
            assert.equal(answer.value, "executor-result-private");
            assert.equal(starts, 1);
        });
    }
    function checkRefusal(logic) {
        const root = state();
        fs.writeFileSync(root, "stand-in for an unwritable state directory");
        withWriter(logic, { state: root }, writer => {
            let starts = 0;
            const result = writer.before(event, () => { starts++; });
            assert.equal(starts, 0, "failed write refuses the action");
            assert.deepEqual(result, { kind: "refuse", reason: "audit-write", cause: "directory-type" });
            for (const kind of ["stop", "teardown"]) {
                const shutdown = writer.cleanup(kind, () => { starts++; });
                assert.equal(shutdown.kind, "started");
                assert.equal(shutdown.audit.kind, "refuse");
            }
            assert.equal(starts, 2, "all privacy shutdown paths remain available");
        });
    }
    function checkPrivacy(logic) {
        const root = state();
        withWriter(logic, { state: root }, writer => {
            const written = writer.record(event);
            assert.equal(written.kind, "recorded");
            assert.equal(written.time, records(root)[0].time, "the result names the row it wrote by its time");
            assert.equal(writer.record({ ...event, tool: "memory.propose",
                args: { id: "facts/private.md", text: "planted-memory-note-text" },
                effect: "reversible" }).kind, "recorded");
            const content = fs.readFileSync(path.join(root, "audit", "2026-09-30.jsonl"), "utf8");
            assert.equal(content.includes("planted-arbitrary-credential"), false, "planted key absent on disk");
            assert.equal(content.includes("planted-memory-note-text"), false, "memory note text absent on disk");
        });
    }
    function checkModes(logic) {
        const root = state();
        fs.mkdirSync(path.join(root, "audit"), { recursive: true, mode: 0o755 });
        const log = path.join(root, "audit", "2026-09-30.jsonl");
        fs.writeFileSync(log, "", { mode: 0o644 });
        fs.chmodSync(log, 0o644);
        fs.chmodSync(root, 0o755);
        fs.chmodSync(path.dirname(log), 0o755);
        withWriter(logic, { state: root }, writer => {
            assert.equal(writer.record(event).kind, "recorded");
            assert.equal(fs.statSync(log).mode & 0o777, 0o600, "owner-only existing file");
            for (const dir of [root, path.dirname(log)])
                assert.equal(fs.statSync(dir).mode & 0o777, 0o700, "owner-only directory");
        });
    }
    function old(root, date, bytes = 0) {
        fs.mkdirSync(path.join(root, "audit"), { recursive: true });
        const file = path.join(root, "audit", date + ".jsonl");
        // Sparse data exercises the actual store bound without a large buffer.
        const fd = fs.openSync(file, "w", 0o600);
        try { fs.ftruncateSync(fd, bytes); } finally { fs.closeSync(fd); }
        return file;
    }
    function checkAge(logic) {
        const root = state();
        const expired = old(root, "2026-08-31");
        const retained = old(root, "2026-09-01");
        withWriter(logic, { state: root }, writer => {
            assert.equal(writer.record(event).kind, "recorded");
            assert.equal(fs.existsSync(expired), false, "default 30 days removes cutoff date");
            assert.equal(fs.existsSync(retained), true, "day inside retention survives");
            assert.deepEqual(records(root)[0].args, { date: "2026-08-31", bytes: 0, reason: "age" });
            assert.equal(records(root)[0].outcome, "completed");
        });
    }
    function checkSize(logic) {
        const root = state();
        const oldest = old(root, "2026-09-01", 64 * 1024 * 1024 - 4096);
        const newer = old(root, "2026-09-02");
        withWriter(logic, { state: root }, writer => {
            fsFault("unlinkSync", (original, victim) => {
                assert.equal(victim, oldest, "oldest file removed first");
                return original(victim);
            }, () => assert.equal(writer.record(event).kind, "recorded"));
            assert.equal(fs.existsSync(oldest), false, "actual 64 MiB ceiling removes oldest first");
            assert.equal(fs.existsSync(newer), true);
            assert.deepEqual(records(root)[0].args, { date: "2026-09-01", bytes: 64 * 1024 * 1024 - 4096, reason: "size" });
            const bytes = fs.readdirSync(path.join(root, "audit"))
                .reduce((sum, name) => sum + fs.statSync(path.join(root, "audit", name)).size, 0);
            assert.ok(bytes <= 64 * 1024 * 1024);
        });
    }
    checkOrder(Audit); checkRefusal(Audit); checkPrivacy(Audit); checkModes(Audit); checkAge(Audit); checkSize(Audit);

    const root = state();
    let at = today;
    withWriter(Audit, { state: root, now: () => at }, writer => {
        assert.throws(() => Audit.create({ state: root }), { code: "writer-owned" });
        for (const decision of ["allow", "confirm", "refuse"])
            assert.equal(writer.record({ ...event, decision, confirmed: decision === "confirm" ? "physical" : "none" }).kind, "recorded");
        for (const decision of ["send", "ask", "withhold"]) {
            const release = { ...event, kind: "release", tool: "release", decision, effect: "external",
                args: { labels: ["file"], recipients: [{ origin: "https://user:private@example.test", key: "planted" }], audio: Buffer.from("private") } };
            assert.equal(writer.record(release).kind, "recorded");
        }
        for (const outcome of ["completed", "failed", "unknown", "cancelled"])
            assert.equal(writer.record({ ...event, outcome }).kind, "recorded");
        for (const entry of records(root).filter(row => row.kind === "release"))
            assert.deepEqual(entry.args, { labels: "[redacted]", recipients: "[redacted]" });
        at += 24 * 60 * 60 * 1000;
        assert.equal(writer.record({ ...event, tool: "secret-key-as-tool-name", args: { password: "secret" } }).kind, "recorded");
        assert.equal(records(root, "2026-10-01")[0].tool, "unknown");
        writer.close();
        assert.deepEqual(writer.record(event), { kind: "refuse", reason: "audit-write", cause: "writer-closed" });
    });
    withWriter(Audit, { state: root }, writer => assert.equal(writer.record(event).kind, "recorded"));
    for (const auditDays of [0, 366, 1.5, "30", null])
        assert.throws(() => Audit.create({ state: state(), auditDays }), { code: "audit-days" });
    for (const auditDays of [1, 365])
        withWriter(Audit, { auditDays }, writer => assert.equal(writer.record(event).kind, "recorded"));
    for (const [field, value, cause] of [
        ["kind", "unknown", "decision"], ["gen", -1, "identity"], ["op", 0, "identity"],
        ["effect", "unknown", "effect"], ["decision", "unknown", "decision"],
        ["confirmed", "model", "confirmation"], ["outcome", "private body", "outcome"]
    ]) withWriter(Audit, {}, writer => assert.deepEqual(writer.record({ ...event, [field]: value }),
        { kind: "refuse", reason: "audit-write", cause }));

    // Links, hard links, incomplete writes and unexpected entries refuse
    // rather than writing elsewhere or deleting files the audit does not own.
    function checkUnsafe(logic, setup, cause) {
        const root = state();
        const target = path.join(base, "untouched-" + ++serial);
        fs.writeFileSync(target, "private scratch content");
        setup(root, target);
        withWriter(logic, { state: root }, writer => {
            let starts = 0;
            const result = writer.before(event, () => starts++);
            assert.equal(starts, 0);
            assert.equal(result.cause, cause);
            assert.equal(fs.readFileSync(target, "utf8"), "private scratch content");
        });
    }
    const hazards = [
        ["state link", (root, target) => fs.symlinkSync(path.dirname(target), root), "directory-type"],
        ["audit link", (root, target) => { fs.mkdirSync(root); fs.symlinkSync(path.dirname(target), path.join(root, "audit")); }, "directory-type"],
        ["daily link", (root, target) => { old(root, "2026-09-29"); fs.symlinkSync(target, path.join(root, "audit", "2026-09-30.jsonl")); }, "file-type"],
        ["hard link", (root, target) => { old(root, "2026-09-29"); fs.linkSync(target, path.join(root, "audit", "2026-09-30.jsonl")); }, "file-type"],
        ["incomplete", root => { const log = old(root, "2026-09-30"); fs.writeFileSync(log, '{"partial":'); }, "partial-line"],
        ["unknown entry", root => { fs.mkdirSync(path.join(root, "audit"), { recursive: true }); fs.writeFileSync(path.join(root, "audit", "other"), ""); }, "entry-name"]
    ];
    for (const [, setup, cause] of hazards) checkUnsafe(Audit, setup, cause);

    function checkPartialAppend(logic) {
        const root = currentState();
        withWriter(logic, { state: root }, writer => {
            assert.equal(writer.record(event).kind, "recorded");
            const file = path.join(root, "audit", "2026-09-30.jsonl");
            fs.appendFileSync(file, '{"partial":');
            const before = fs.readFileSync(file);
            let starts = 0;
            assert.equal(writer.before(event, () => starts++).cause, "partial-line");
            assert.equal(starts, 0, "an incomplete append refuses the action");
            assert.deepEqual(fs.readFileSync(file), before, "refusal appends no bytes");
        });
    }
    checkPartialAppend(Audit);

    function checkFault(logic, method, replacement, cause) {
        const root = currentState();
        withWriter(logic, { state: root }, writer => {
            let starts = 0;
            fsFault(method, replacement, () => {
                const result = writer.before(event, () => starts++);
                assert.equal(starts, 0, method + " failure must refuse callback");
                assert.equal(result.cause, cause);
            });
        });
    }
    const ioError = code => () => { const error = new Error("private error body"); error.code = code; throw error; };
    checkFault(Audit, "writeSync", ioError("ENOSPC"), "ENOSPC");
    checkFault(Audit, "fsyncSync", ioError("EIO"), "EIO");
    checkFault(Audit, "fchmodSync", ioError("EPERM"), "EPERM");
    function checkShort(logic) {
        const root = currentState();
        withWriter(logic, { state: root }, writer => {
            let starts = 0;
            fsFault("writeSync", (original, fd, buffer) => original(fd, buffer, 0, 2), () => {
                const result = writer.before(event, () => starts++);
                assert.equal(starts, 0);
                assert.equal(result.cause, "short-write");
            });
            assert.equal(fs.statSync(path.join(root, "audit", "2026-09-30.jsonl")).size, 0, "partial append rolled back");
            assert.equal(writer.record(event).kind, "recorded", "retry after short write produces valid JSON");
            assert.equal(records(root).length, 1);
        });
    }
    checkShort(Audit);
    function checkSingle(logic) {
        const root = state();
        withWriter(logic, { state: root }, () => {
            let extra;
            try { assert.throws(() => { extra = logic.create({ state: root }); }, { code: "writer-owned" }); }
            finally { if (extra) extra.close(); }
        });
    }
    function checkClosed(logic) {
        withWriter(logic, {}, writer => {
            writer.close();
            assert.equal(writer.before(event, () => assert.fail("closed owner started action")).cause, "writer-closed");
        });
    }
    function checkPruneLog(logic) {
        const root = state();
        old(root, "2026-08-31");
        withWriter(logic, { state: root }, writer => {
            assert.equal(writer.record(event).kind, "recorded");
            assert.deepEqual(records(root).map(row => row.kind), ["prune", "action"]);
        });
    }
    function checkField(logic, field, value, cause) {
        withWriter(logic, {}, writer => assert.deepEqual(writer.record({ ...event, [field]: value }),
            { kind: "refuse", reason: "audit-write", cause }));
    }
    function checkDays(logic, days) {
        let writer;
        try { assert.throws(() => { writer = logic.create({ state: state(), auditDays: days }); }, { code: "audit-days" }); }
        finally { if (writer) writer.close(); }
    }
    function checkClock(logic) {
        withWriter(logic, { now: () => -1 }, writer => assert.equal(writer.record(event).cause, "clock-value"));
    }
    function checkUnknownTool(logic) {
        const root = state();
        withWriter(logic, { state: root }, writer => {
            assert.equal(writer.record({ ...event, tool: "planted-key-as-tool" }).kind, "recorded");
            assert.equal(records(root)[0].tool, "unknown");
        });
    }
    // An action the local matcher proposed says so; no other proposer or
    // record kind carries the field.
    function checkProposer(logic) {
        const root = state();
        withWriter(logic, { state: root }, writer => {
            assert.equal(writer.record({ ...event, proposer: "matcher" }).kind, "recorded");
            assert.equal(writer.record(event).kind, "recorded");
            assert.deepEqual(records(root).map(record => record.proposer), ["matcher", undefined]);
            for (const value of [{ ...event, proposer: "brain" }, { ...event, proposer: "" },
                { ...event, kind: "release", tool: "release", decision: "send", proposer: "matcher" }])
                assert.deepEqual(writer.record(value), { kind: "refuse", reason: "audit-write", cause: "proposer" });
            assert.equal(records(root).length, 2, "a refused record writes nothing");
        });
    }
    // A failed voice stream's closing release row keeps one of the stream
    // causes, never the fault's own text; no other record carries one.
    function checkCause(logic) {
        const root = state();
        const stream = { ...event, kind: "release", effect: "external", decision: "send", outcome: "failed" };
        withWriter(logic, { state: root }, writer => {
            for (const cause of ["key-refused", "voice-stopped"])
                assert.equal(writer.record({ ...stream, cause }).kind, "recorded", cause);
            assert.equal(writer.record(stream).kind, "recorded");
            assert.deepEqual(records(root).map(record => record.cause), ["key-refused", "voice-stopped", undefined]);
            for (const [name, value] of [["retired silence", { ...stream, cause: "input-silent" }],
                ["retired unheard", { ...stream, cause: "unheard" }],
                ["fault text", { ...stream, cause: "live=key-refused" }],
                ["caller text", { ...stream, cause: "planted-arbitrary-credential" }],
                ["completed stream", { ...stream, outcome: "completed", cause: "key-refused" }],
                ["action", { ...event, outcome: "failed", cause: "voice-stopped" }]])
                assert.deepEqual(writer.record(value), { kind: "refuse", reason: "audit-write", cause: "cause" }, name);
            assert.equal(records(root).length, 3, "a refused cause writes nothing");
        });
    }
    // A conversation fault's row: the keyed cause's head word and status,
    // the engine's category and Session's action, never the cause's other
    // text. The Problems list keeps it, and the next writer seeds it back.
    function checkFaultRow(logic) {
        const root = currentState();
        const time = "2026-09-30T12:00:00.000Z";
        const fault = { kind: "fault-record", gen: 4, op: 9, reason: "brain=provider-error status=503", category: "service", action: "restarted" };
        const kept = [
            ["brain=provider-error status=503", "service", "restarted", { cause: "brain=provider-error", status: 503 }],
            ["brain=harness-model-refused model=planted-arbitrary-credential", "model", "stopped", { cause: "brain=harness-model-refused" }],
            ["brain=harness-api-error status=0", "other", "stopped", { cause: "brain=harness-api-error" }],
            ["net=request", "connection", "restarted", { cause: "net=request" }],
            ["jarvis-keys: secret-tool=locked", "setup", "stopped", { cause: "secret-tool=locked" }],
            ["home=absent", "other", "stopped", { cause: "home=absent" }],
            // Harness stop reasons keep their program's spelling (CopilotAcp.STOPS, PiRpc.STOPS).
            ["brain=copilot-stop-max_tokens", "other", "stopped", { cause: "brain=copilot-stop-max-tokens" }],
            ["brain=copilot-stop-max_turn_requests", "other", "stopped", { cause: "brain=copilot-stop-max-turn-requests" }],
            ["brain=pi-stop-toolUse", "other", "stopped", { cause: "brain=pi-stop-tooluse" }]];
        const listed = kept.map(([, category, action, row]) => ({ time, kind: "fault", status: null, ...row, category, action }));
        const changes = [];
        withWriter(logic, { state: root, changed: rows => changes.push(rows) }, writer => {
            for (const [reason, category, action] of kept)
                assert.equal(writer.fault({ ...fault, reason, category, action }).kind, "recorded", reason);
            assert.deepEqual(records(root), kept.map(([, category, action, row]) => ({ time, kind: "fault", gen: 4, ...row, category, action })));
            for (const [name, value, cause] of [
                ["free text head", { ...fault, reason: "brain=Provider: said no" }, "fault-cause"],
                ["unkeyed text", { ...fault, reason: "the provider said no" }, "fault-cause"],
                ["second prefix", { ...fault, reason: "jarvis-keys: jarvis-accounts: store=locked" }, "fault-cause"],
                ["long head", { ...fault, reason: "brain=" + "a".repeat(61) }, "fault-cause"],
                ["category", { ...fault, category: "transient" }, "fault-category"],
                ["action", { ...fault, action: "retried" }, "fault-action"],
                ["identity", { ...fault, gen: -1 }, "identity"],
                ["reason", { ...fault, reason: 7 }, "event-shape"]])
                assert.deepEqual(writer.fault(value), { kind: "refuse", reason: "audit-write", cause }, name);
            assert.equal(records(root).length, kept.length, "a refused fault writes nothing");
            assert.deepEqual(writer.failures(), listed, "the Problems list keeps every fault");
            assert.deepEqual(changes.at(-1), listed, "each kept fault publishes the list");
        });
        withWriter(logic, { state: root }, writer => {
            let seeded;
            assert.doesNotThrow(() => { seeded = writer.failures(); }, "the stored faults pass the seed's judge");
            assert.deepEqual(seeded, listed, "the next writer seeds the stored faults");
        });
    }
    function legacyStore() {
        const root = state();
        fs.mkdirSync(path.join(root, "audit"), { recursive: true, mode: 0o700 });
        const rows = ["unheard", "input-silent"].map((cause, index) => ({
            time: "2026-09-" + (29 + index) + "T12:00:00.000Z", kind: "release", gen: 2, op: index + 1,
            tool: "release", args: { labels: "[redacted]", recipients: "[redacted]" }, effect: "external",
            decision: "send", confirmed: "none", outcome: "failed", cause
        }));
        for (let index = 0; index < rows.length; index++)
            fs.writeFileSync(path.join(root, "audit", "2026-09-" + (29 + index) + ".jsonl"), JSON.stringify(rows[index]) + "\n", { mode: 0o600 });
        return { root, rows };
    }
    function checkCauseMigration(logic) {
        const { root, rows } = legacyStore();
        withWriter(logic, { state: root }, writer => {
            assert.doesNotThrow(() => writer.failures(), "converted records pass the current judge");
            assert.equal(writer.failures().at(-1).cause, null);
        });
        for (let index = 0; index < rows.length; index++) {
            const { cause, ...current } = rows[index];
            assert.deepEqual(records(root, "2026-09-" + (29 + index)), [current], "every old daily file converts, including the unread older day");
        }
        const file = path.join(root, "audit", "2026-09-29.jsonl");
        const before = fs.statSync(file).ino;
        withWriter(logic, { state: root }, writer => assert.doesNotThrow(() => writer.failures()));
        assert.equal(fs.statSync(file).ino, before, "a current marker prevents repeated daily rewrites");
        assert.deepEqual(JSON.parse(fs.readFileSync(path.join(root, "audit-cause-version.json"), "utf8")), { version: 1 });
    }
    function checkMigrationAtomic(logic) {
        const { root } = legacyStore();
        const daily = fs.readdirSync(path.join(root, "audit")).map(name => path.join(root, "audit", name));
        const before = daily.map(file => fs.readFileSync(file));
        fsFault("renameSync", (original, source, target) => {
            if (target.endsWith(".jsonl")) { const error = new Error("fixture rename failure"); error.code = "EIO"; throw error; }
            return original(source, target);
        }, () => withWriter(logic, { state: root }, writer => {
            assert.throws(() => writer.failures(), error => error.code === "EIO");
        }));
        for (const [index, file] of daily.entries())
            assert.deepEqual(fs.readFileSync(file), before[index], "a failed atomic replacement preserves each old daily file");
        assert.equal(fs.existsSync(path.join(root, "audit-cause-version.json")), false, "failed conversion publishes no current marker");
        withWriter(logic, { state: root }, writer => assert.doesNotThrow(() => writer.failures(), "the next owner retries the retained conversion"));
        assert.equal(records(root, "2026-09-29")[0].cause, undefined);
    }
    function checkFormatRefusal(logic) {
        for (const [value, cause] of [["broken", "format-json"], ['{"version":2}', "format-version"]]) {
            const root = state();
            fs.mkdirSync(root, { recursive: true, mode: 0o700 });
            fs.writeFileSync(path.join(root, "audit-cause-version.json"), value, { mode: 0o600 });
            withWriter(logic, { state: root }, writer => {
                assert.throws(() => writer.failures(), error => error.code === cause);
                assert.deepEqual(writer.record(event), { kind: "refuse", reason: "audit-write", cause });
                let cleaned = false;
                writer.cleanup("teardown", () => { cleaned = true; });
                assert.equal(cleaned, true, "format refusal never delays privacy teardown");
            });
            assert.equal(fs.existsSync(path.join(root, "audit")), false, "refused format creates no daily store");
            assert.equal(fs.readFileSync(path.join(root, "audit-cause-version.json"), "utf8"), value);
        }
    }
    checkCauseMigration(Audit);
    checkMigrationAtomic(Audit);
    checkFormatRefusal(Audit);
    mutant(file, "retired audit cause conversion", "if (convert) migrate(file);", "if (false) migrate(file);", checkCauseMigration);
    mutant(file, "atomic audit conversion", "fs.renameSync(candidate, file);",
        "fs.writeFileSync(file, fs.readFileSync(candidate)); fs.renameSync(candidate, file);", checkMigrationAtomic);
    mutant(file, "refused audit format", "if (seedError !== null) throw seedError;\n        Private.directory(state);",
        "Private.directory(state);", checkFormatRefusal);
    // A vision capture's facts: numbers and a digest, never image bytes.
    const capture = { box: [0, 0, 320, 200], scale: 1.25, width: 400, height: 250, bytes: 1024, sha256: "0a".repeat(32), masks: 2 };
    const vision = { ...event, tool: "vision.screen", args: {}, effect: "read", outcome: "completed", capture };
    // Only the vision result's fixed diagnostic key survives. Its free text,
    // private command detail and arbitrary supplied keys cannot enter a row.
    function checkVisionReason(logic) {
        const root = state();
        const failed = { ...event, tool: "vision.screen", args: {}, effect: "read", outcome: "failed" };
        const call = { id: "vision.screen", args: {} };
        withWriter(logic, { state: root }, writer => {
            for (const [failure, reason] of [
                [JSON.stringify({ kind: "failed", reason: "hyprland-read", detail: "PRIVATE-SCREEN-TEXT" }), "hyprland-read"],
                [Desktop.failure(call, "grim", { kind: "stopped", reason: "timeout" }).content, "grim-timeout"],
                [Desktop.failure(call, "grim", { kind: "exited", code: 1, stderr: "PRIVATE-SCREEN-TEXT" }).content, "grim-exit=1"],
                ...["grim", "magick", "slurp", "tesseract"].map(command =>
                    [Desktop.failure(call, command, { kind: "exited", code: null, signal: "SIGTERM" }).content, command + "-signal"]),
                [Desktop.failure(call, "grim", { kind: "error", reason: "spawn", error: "PRIVATE-SCREEN-TEXT" }).content, "grim-spawn"]
            ]) {
                assert.equal(writer.record({ ...failed, failure }).kind, "recorded");
                assert.equal(records(root).at(-1).reason, reason);
            }
            for (const [name, change] of [
                ["unknown reason", { failure: '{"kind":"failed","reason":"PRIVATE-SCREEN-TEXT"}' }],
                ["unknown command", { failure: '{"kind":"failed","command":"PRIVATE-SCREEN-TEXT","code":1}' }],
                ["unstructured result", { failure: "PRIVATE-SCREEN-TEXT" }],
                ["empty result", { failure: "{}" }],
                ["completed result", { outcome: "completed", failure: '{"reason":"image-size"}' }],
                ["other executor", { tool: "files.read", failure: '{"reason":"image-size"}' }],
                ["unjudged stored reason", { reason: "PRIVATE-SCREEN-TEXT" }]
            ]) assert.deepEqual(writer.record({ ...failed, ...change }), { kind: "refuse", reason: "audit-write", cause: "reason" }, name);
            const stored = fs.readFileSync(path.join(root, "audit", "2026-09-30.jsonl"), "utf8");
            for (const privateText of ["PRIVATE-SCREEN-TEXT", "SIGTERM"])
                assert.equal(stored.includes(privateText), false);
        });
        withWriter(logic, { state: root }, writer => assert.doesNotThrow(() => writer.failures(), "stored vision reasons pass the same judge"));
    }
    checkVisionReason(Audit);
    function checkCapture(logic) {
        const root = state();
        withWriter(logic, { state: root }, writer => {
            assert.equal(writer.record(vision).kind, "recorded");
            assert.deepEqual(records(root)[0].capture, capture);
            for (const [name, value] of [
                ["extra key", { ...vision, capture: { ...capture, image: "iVBORw0KGgo" } }],
                ["other tool", { ...vision, tool: "files.read" }],
                ["release", { ...vision, kind: "release", decision: "send" }],
                ["digest", { ...vision, capture: { ...capture, sha256: "0A".repeat(32) } }],
                ["box length", { ...vision, capture: { ...capture, box: [0, 0, 320] } }],
                ["box value", { ...vision, capture: { ...capture, box: ["0", 0, 320, 200] } }],
                ["box size", { ...vision, capture: { ...capture, box: [0, 0, 0, 200] } }],
                ["scale", { ...vision, capture: { ...capture, scale: 0 } }],
                ["image size", { ...vision, capture: { ...capture, width: 0 } }],
                ["counts", { ...vision, capture: { ...capture, masks: -1 } }]
            ]) assert.deepEqual(writer.record(value), { kind: "refuse", reason: "audit-write", cause: "capture" }, name);
            assert.equal(records(root).length, 1, "a refused capture writes nothing");
        });
    }
    function checkUnlinkFailure(logic) {
        const root = state();
        old(root, "2026-08-31");
        withWriter(logic, { state: root }, writer => {
            let starts = 0;
            fsFault("unlinkSync", ioError("EACCES"), () => {
                assert.equal(writer.before(event, () => starts++).cause, "EACCES");
                assert.equal(starts, 0);
            });
        });
    }
    checkUnlinkFailure(Audit); checkClock(Audit); checkUnknownTool(Audit); checkCapture(Audit); checkProposer(Audit); checkCause(Audit); checkFaultRow(Audit);
    for (const invalid of ["relative", "/", base + "/x/../y", null])
        assert.throws(() => Audit.create({ state: invalid }), { code: "state-path" });
    withWriter(Audit, { now: () => NaN }, writer => assert.equal(writer.record(event).kind, "refuse"));
    const invalidDate = (root) => { old(root, "2026-02-30"); };
    checkUnsafe(Audit, invalidDate, "entry-date");
    const controls = [
        ["write refusal", 'if (audit.kind === "refuse") return audit;', 'if (audit.kind === "refuse") start();', checkRefusal],
        ["write syscall", "const written = fs.writeSync(fd, line, 0, line.length);", "const written = line.length;",
            logic => checkFault(logic, "writeSync", ioError("ENOSPC"), "ENOSPC")],
        ["file flush", "            fs.fsyncSync(fd);\n        } finally", "            /* omitted file flush */\n        } finally",
            logic => {
                // Directory flushes cannot stand in for the file flush.
                checkFault(logic, "fsyncSync", (original, fd) => {
                    if (fs.fstatSync(fd).isFile()) ioError("EIO")();
                    return original(fd);
                }, "EIO");
            }],
        ["short write refusal", 'if (written !== line.length) {', 'if (false && written !== line.length) {', checkShort],
        ["short write rollback", "fs.ftruncateSync(fd, stat.size);", "/* omitted rollback */", checkShort],
        ["file permissions", "fs.fchmodSync(fd, 0o600);", "/* omitted private file mode */", checkModes],
        ["retention age", "date <= today - auditDays * DAY_MS", "false && date <= today - auditDays * DAY_MS", checkAge],
        ["retention size", "inventory.total + line.length + LINE_BYTES > STORE_BYTES", "false && inventory.total + line.length + LINE_BYTES > STORE_BYTES", checkSize],
        ["oldest first", "date < oldest.date", "date > oldest.date", checkSize],
        ["removal record", "append(stamp.file, encode({ time: stamp.time, kind: \"prune\"", "false && append(stamp.file, encode({ time: stamp.time, kind: \"prune\"", checkPruneLog],
        ["one writer", 'if (owners.has(state)) fail("writer-owned");', 'if (false && owners.has(state)) fail("writer-owned");', checkSingle],
        ["closed owner", 'if (lifetime !== "open") fail("writer-closed");', 'if (false && lifetime !== "open") fail("writer-closed");', checkClosed],
        ["partial line", 'tail[0] !== 10', 'false && tail[0] !== 10', checkPartialAppend],
        ["file links", 'if (!stat.isFile() || stat.nlink !== 1 || stat.uid !== process.getuid()) fail("file-type");',
            'if (!stat.isFile() || stat.uid !== process.getuid()) fail("file-type");',
            logic => checkUnsafe(logic, hazards[3][1], "file-type")],
        ["removal failure", "fs.unlinkSync(victim.file);", "/* removal omitted */",
            logic => {
                // Reject the first wrong operation before a pruning loop can
                // repeat. The filesystem stand-in is private to this case.
                const root = state();
                old(root, "2026-08-31");
                withWriter(logic, { state: root }, writer => {
                    let removals = 0;
                    fsFault("unlinkSync", () => { removals++; ioError("EACCES")(); }, () => {
                        fsFault("writeSync", (original, ...args) => {
                            assert.equal(removals, 1, "failed removal must prevent a following write");
                            return original(...args);
                        }, () => assert.equal(writer.record(event).cause, "EACCES"));
                    });
                });
            }],
        ["auditDays floor", "auditDays < 1", "false && auditDays < 1", logic => checkDays(logic, 0)],
        ["auditDays ceiling", "auditDays > 365", "false && auditDays > 365", logic => checkDays(logic, 366)],
        ["auditDays integer", "!Number.isInteger(auditDays)", "false && !Number.isInteger(auditDays)", logic => checkDays(logic, 1.5)],
        ["clock value", "ms < 0", "false && ms < 0", checkClock],
        ["identity", "if (!Number.isSafeInteger(gen) || gen < 0 || !Number.isSafeInteger(op) || op < 1)",
            "if (false && (!Number.isSafeInteger(gen) || gen < 0 || !Number.isSafeInteger(op) || op < 1))",
            logic => checkField(logic, "op", 0, "identity")],
        ["decision enum", "!decisions.includes(decision)", "false && !decisions.includes(decision)",
            logic => checkField(logic, "decision", "planted-key", "decision")],
        ["effect enum", 'if (effect !== null && !effects.includes(effect))', 'if (false && effect !== null && !effects.includes(effect))',
            logic => checkField(logic, "effect", "planted-key", "effect")],
        ["confirmation enum", 'if (!["none", "physical", "voice"].includes(confirmed))', 'if (false && !["none", "physical", "voice"].includes(confirmed))',
            logic => checkField(logic, "confirmed", "planted-key", "confirmation")],
        ["outcome enum", 'if (!["pending", "completed", "failed", "unknown", "cancelled"].includes(outcome))', 'if (false && !["pending", "completed", "failed", "unknown", "cancelled"].includes(outcome))',
            logic => checkField(logic, "outcome", "planted-key", "outcome")],
        ["tool identity", 'Object.hasOwn(Tools.TABLE, tool) ? tool : "unknown"', 'tool', checkUnknownTool],
        ["proposer kept", '...(event.proposer === undefined ? {} : { proposer: event.proposer }),', "", checkProposer],
        ["proposer judged", 'if (event.proposer !== undefined && (kind !== "action" || event.proposer !== "matcher")) fail("proposer");', "", checkProposer],
        ["cause kept", "...(event.cause === undefined ? {} : { cause: event.cause }),", "", checkCause],
        ["cause judged", 'if (event.cause !== undefined && (kind !== "release" || outcome !== "failed" || !STREAM_CAUSES.includes(event.cause))) fail("cause");', "", checkCause],
        ["cause scope", 'kind !== "release" || outcome !== "failed" || !STREAM_CAUSES', "!STREAM_CAUSES", checkCause],
        ["cause listed", "cause: record.cause ?? null }", "cause: null }", checkFailures],
        ["fault head word", '.split(" ", 1)[0]', "", checkFaultRow],
        ["fault head spelling", '.toLowerCase().replace(/_/g, "-")', "", checkFaultRow],
        ["fault key prefix", '.replace(/^jarvis-[a-z]+: /, "")', "", checkFaultRow],
        ["fault any area", "const FAULT_CAUSE = /^[a-z-]+=[a-z0-9-]{1,60}$/;", "const FAULT_CAUSE = /^(?:brain|net)=[a-z0-9-]{1,60}$/;", checkFaultRow],
        ["fault cause judged", 'if (typeof cause !== "string" || !FAULT_CAUSE.test(cause)) fail("fault-cause");', "", checkFaultRow],
        ["fault status kept", "...(status === null ? {} : { status: Number(status[1]) })", "...{}", checkFaultRow],
        ["fault category judged", 'if (!FAULT_CATEGORIES.includes(category)) fail("fault-category");', "", checkFaultRow],
        ["fault action judged", 'if (!FAULT_ACTIONS.includes(action)) fail("fault-action");', "", checkFaultRow],
        ["fault retained", 'return record.kind === "fault" || ["refuse"', 'return ["refuse"', checkFaultRow],
        ["fault stored judge", 'return record.kind === "fault" ? faultRow(record) : eventRecord(record, record.time);',
            "return eventRecord(record, record.time);", checkFaultRow],
        ["fault status listed", "status: record.status ?? null,", "status: null,", checkFaultRow],
        ["vision signal producer shape", 'value.code === undefined && typeof value.signal === "string"',
            'value.code === null && typeof value.signal === "string"', checkVisionReason],
        ["capture keys", 'Object.keys(capture).sort().join(",") !== "box,bytes,height,masks,scale,sha256,width"', "false", checkCapture],
        ["capture scope", 'if (kind !== "action" || !Object.hasOwn(Tools.TABLE, tool) || Tools.TABLE[tool].executor !== "vision"', "if (false", checkCapture],
        ["capture digest", "!/^[0-9a-f]{64}$/.test(capture.sha256)", "false", checkCapture],
        ["capture box", "!capture.box.every(whole)", "false", checkCapture],
        ["capture box size", "capture.box[2] < 1 || capture.box[3] < 1", "false", checkCapture],
        ["capture scale", "capture.scale <= 0", "false", checkCapture],
        ["capture size", "![capture.width, capture.height].every(value => whole(value) && value > 0)", "false", checkCapture],
        ["capture counts", "![capture.bytes, capture.masks].every(value => whole(value) && value >= 0)", "false", checkCapture],
        ["invalid stored date", 'new Date(time).toISOString().slice(0, 10) !== date', 'false && new Date(time).toISOString().slice(0, 10) !== date',
            logic => checkUnsafe(logic, invalidDate, "entry-date")]
    ];
    for (const [name, needle, replacement, check] of controls)
        mutant(file, name, needle, replacement, check);
    // The private directory owner is shared; these controls reach it through the writer.
    mutant(PrivateFile, "directory permissions", "fs.chmodSync(target, 0o700);", "/* omitted private directory mode */", checkModes, "Audit.js");
    mutant(PrivateFile, "state links", 'if (!fs.lstatSync(current).isDirectory()) fail("directory-type");',
        'if (!fs.statSync(current).isDirectory()) fail("directory-type");',
        logic => checkUnsafe(logic, hazards[0][1], "directory-type"), "Audit.js");
    // Start before record, but retain both calls and the record's matched text.
    mutant(file, "decision before action", "const audit = record(event);",
        "start(); const audit = record(event);", logic => {
            const root = state();
            withWriter(logic, { state: root }, writer => {
                const persisted = [];
                writer.before(event, () => { persisted.push(fs.existsSync(path.join(root, "audit", "2026-09-30.jsonl"))); });
                assert.deepEqual(persisted, [true], "one action saw a persisted decision");
            });
        });
    mutant(file, "disk redaction", "args: Redact.argumentsFor(kind, tool, event.args)", "args: event.args", checkPrivacy);
    mutant(RedactFile, "redaction reaches writer", 'result[field] = "[redacted]";', "result[field] = args[field];", checkPrivacy, "Audit.js");
    // The fixed metadata and argument envelope fit the line bound by design.
    // Plant an enlarged emitted envelope to prove the assertion detects it.
    mutant(file, "bounded emitted line", "const line = Buffer.from(JSON.stringify(record) + \"\\n\");\n    if (line.length > LINE_BYTES)",
        "const line = Buffer.from(JSON.stringify({ ...record, padding: 'x'.repeat(4096) }) + \"\\n\");\n    if (false && line.length > LINE_BYTES)",
        checkOrder);
    for (const kind of ["stop", "teardown"])
        mutant(file, "privacy shutdown " + kind, 'return { kind: "started", audit, value: start() };\n        },\n        close()',
            'if (kind === "' + kind + '" && audit.kind === "refuse") return audit;\n            return { kind: "started", audit, value: start() };\n        },\n        close()', checkRefusal);
    console.log("jarvis-audit: acceptance=passed controls=" + (controls.length + 15)
        + " planted-keys=absent failed-write=refused");
});
