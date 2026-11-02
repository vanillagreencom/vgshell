#!/usr/bin/env node
// The package CLI through the production child owner; no provider or desktop.
"use strict";
const assert = require("node:assert/strict"), fs = require("node:fs"), os = require("node:os"), path = require("node:path"), cp = require("node:child_process");
const { load, closure } = require("../bin/lib/qml-library.js");
const tree = path.resolve(__dirname, "..");
require("../shell/plugins/vgs.jarvis/backend/Core.js").use(tree);
const Protocol = load(path.join(tree, "shell/plugins/vgs.jarvis/JarvisProtocol.js"));
const OwnerAsks = require("../shell/plugins/vgs.jarvis/backend/OwnerAsks.js");
const Child = require("../shell/plugins/vgs.jarvis/backend/Child.js");
const vm = require("node:vm");
const fixture = path.join(__dirname, "fixtures/jarvis/owner-asks.js");
const root = fs.mkdtempSync(path.join(os.tmpdir(), "owner-asks-"));
const environment = { PATH: "/usr/bin:/bin", HOME: root, LANG: "C.UTF-8" };
function control(...args) {
    const result = cp.spawnSync(process.execPath, [fixture, ...args], { env: environment, encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    return result.stdout.trim() === "" ? null : JSON.parse(result.stdout);
}
function home(name, count) {
    const folder = path.join(root, name), command = path.join(folder, ".agents/skills/jarvis/scripts/jarvis-session");
    control("--seed", folder, String(count));
    fs.mkdirSync(path.dirname(command), { recursive: true });
    fs.copyFileSync(fixture, command); fs.chmodSync(command, 0o700);
    return folder;
}
function clock() {
    let serial = 0;
    const timers = new Map();
    return { timers, now: () => Date.now(), set(fn) { timers.set(++serial, fn); return serial; }, clear(id) { timers.delete(id); } };
}
function client(extra = {}) {
    const snapshots = [], answers = [], logs = [], time = clock();
    const owner = OwnerAsks.create({ Protocol, environment, publish: s => snapshots.push(s), answer: s => answers.push(s), log: s => logs.push(s), clock: time, ...extra });
    return { owner, snapshots, answers, logs, time, current: () => snapshots[snapshots.length - 1] };
}
(async () => {
    const folder = home("first", 7), c = client();
    await c.owner.setHome(folder);
    assert.equal(c.current().kind, "ready");
    assert.equal(c.current().active.length, 3);
    assert.equal(c.current().activeCount, 7, "canonical count exceeds the visible page");
    const publications = c.snapshots.length;
    await c.owner.refresh(false);
    assert.equal(c.snapshots.length, publications, "an unchanged periodic read retains published controls and unread count");
    await c.owner.page("active", c.current().activeNextCursor, c.current().revision);
    assert.equal(c.current().active[0].id, "ask-3");
    assert.equal(c.current().active.length, 3, "paging replaces rather than accumulates rows");
    assert.equal(c.current().activeCount, 7);
    await c.owner.page("active", c.current().activeNextCursor, c.current().revision);
    assert.equal(c.current().active.length, 1);
    assert.equal(c.current().activeNextCursor, null);
    await c.owner.page("active", null, c.current().revision);
    assert.equal(c.current().active[0].id, "jarvis-briefing");
    const request = (action, id, text = "") => ({ action, id, requestId: "request-" + action,
        expectedRevision: c.current().active.concat(c.current().snoozed).find(row => row.id === id).revision,
        text, until: action === "later" ? new Date(Date.now() + 86400000).toISOString() : null });
    const reply = request("reply", "jarvis-briefing", "Keep this in the original thread.\nOwner answer.");
    await c.owner.act(reply);
    assert.equal(c.answers[c.answers.length - 1].kind, "accepted");
    const calls = fs.readFileSync(path.join(folder, ".owner-asks-fixture-calls.jsonl"), "utf8").trim().split("\n").map(JSON.parse);
    const call = calls.find(call => call.argv[1] === "reply");
    assert.equal(call.input.text, reply.text);
    assert.equal(call.argv.includes(reply.text), false, "owner text travels only through stdin");
    await c.owner.act(request("done", "tracker-design", "The design was checked."));
    assert.equal(c.current().active.find(row => row.id === "tracker-design").state, "checking");
    assert.equal(c.current().activeCount, 7, "Done does not close an unverified ask");
    control("--verify", folder, "tracker-design");
    await c.owner.refresh();
    assert.equal(c.current().activeCount, 6);
    assert.equal(c.current().active.some(row => row.id === "tracker-design"), false);
    await c.owner.act(request("later", "fleet-update"));
    assert.equal(c.current().activeCount, 5);
    assert.equal(c.current().snoozedCount, 1);
    assert.equal(c.current().snoozed[0].id, "fleet-update");
    assert.equal(c.current().snoozed[0].state, "snoozed");
    for (const mode of ["unavailable", "malformed"]) {
        control("--mode", folder, mode); await c.owner.refresh();
        assert.equal(c.current().kind, "unavailable", "unread source never becomes empty success");
        assert.equal(Object.hasOwn(c.current(), "activeCount"), false);
    }
    control("--mode", folder, "ready"); await c.owner.refresh();
    const accepted = c.current();
    const envelope = { v: 1, gen: 0, revision: "a".repeat(64) };
    for (const [direction, frame] of [
        ["shell", { type: "intent", intent: "owner-asks-refresh" }],
        ["shell", { type: "intent", intent: "owner-asks-page", view: "active", cursor: null, expectedRevision: accepted.revision }],
        ["shell", { type: "intent", intent: "owner-ask-action", request: reply }],
        ["daemon", { type: "owner-asks", snapshot: accepted }],
        ["daemon", { type: "owner-ask-answer", result: { v: 1, requestId: reply.requestId, kind: "unknown", state: null, cause: "The action was not confirmed." } }],
        ["daemon", { type: "owner-ask-answer", result: { v: 1, requestId: reply.requestId, kind: "not-sent", state: null, cause: "The session is locked." } }]
    ]) {
        const line = JSON.stringify({ ...envelope, ...frame });
        Protocol.accept(line, direction);
        assert.throws(() => Protocol.accept(line, direction === "shell" ? "daemon" : "shell"), "the other endpoint cannot produce this message");
        assert.throws(() => Protocol.accept(JSON.stringify({ ...envelope, ...frame, extra: true }), direction), "wire shape stays exact");
    }
    assert.throws(() => Protocol.ownerAskAnswer({ v: 1, requestId: "public", kind: "unknown", state: null, cause: "Not confirmed." }, "done"),
        "unknown is local transport state, never a fabricated public package acknowledgement");
    for (const mutate of [
        value => { value.active.push({ ...value.active[0] }); },
        value => { value.activeNextCursor = value.activeCursor = "same"; },
        value => { value.active[0].link.url = "file:///private"; },
        value => { value.active[0].actions.done = { allowed: false, reason: "" }; }
    ]) {
        const value = JSON.parse(JSON.stringify(accepted)); mutate(value);
        assert.throws(() => Protocol.ownerAsksSnapshot(value));
    }
    function doneChecks(judge) {
        assert.throws(() => judge.ownerAskAnswer({ v: 1, requestId: "done", kind: "accepted", state: "closed", cause: "" }, "done"));
    }
    doneChecks(Protocol);
    const protocolFile = path.join(tree, "shell/plugins/vgs.jarvis/JarvisProtocol.js");
    const mutationRoot = path.join(root, "control");
    fs.mkdirSync(mutationRoot);
    for (const file of closure(protocolFile)) fs.copyFileSync(file, path.join(mutationRoot, path.basename(file)));
    const source = fs.readFileSync(protocolFile, "utf8"), needle = 'action === "done" && value.state !== "checking"';
    assert.equal(source.split(needle).length, 2);
    fs.writeFileSync(path.join(mutationRoot, "JarvisProtocol.js"), source.replace(needle, 'false && ' + needle));
    assert.throws(() => doneChecks(load(path.join(mutationRoot, "JarvisProtocol.js"))), assert.AssertionError,
        "control: dropping the Done/checking invariant must fail this assertion");
    await c.owner.close();
    assert.equal(c.time.timers.size, 0);

    const backlog = client();
    await backlog.owner.setHome(home("large-backlog", 70));
    assert.equal(backlog.current().activeCount, 70, "a legitimate backlog above64 is still browsable");
    assert.equal(backlog.current().active.length, 3);
    await backlog.owner.page("active", backlog.current().activeNextCursor, backlog.current().revision);
    assert.equal(backlog.current().active[0].id, "ask-3");
    assert.equal(backlog.current().activeCount, 70);
    await backlog.owner.close();

    // The package has acted before either losing its acknowledgement or
    // reaching the child's deadline. Only a judged package receipt can
    // prove acceptance/refusal; rereading checking does not forge a receipt.
    for (const mode of ["receipt-malformed", "receipt-timeout"]) {
        const uncertainHome = home(mode, 3);
        const uncertain = client({ run(file, argv, options) {
            if (argv[5] === "list" || mode !== "receipt-timeout") return Child.run(file, argv, options);
            let deadline;
            return Child.run(file, argv, { ...options,
                clock: { set(fn, ms) { assert.equal(ms, 15000); deadline = fn; return 1; }, clear() {} },
                attach(child) { child.stderr.on("data", bytes => { if (bytes.toString().includes("fixture: receipt-written")) deadline(); }); }
            });
        } });
        await uncertain.owner.setHome(uncertainHome);
        control("--mode", uncertainHome, mode);
        const request = { action: "done", id: "tracker-design", requestId: "uncertain-" + mode,
            expectedRevision: "1", text: "", until: null };
        await uncertain.owner.act(request);
        assert.equal(control("--state", uncertainHome).rows.find(row => row.id === request.id).state, "checking", "fixture really acted");
        assert.equal(uncertain.answers.at(-1).kind, "unknown", mode);
        assert.equal(uncertain.answers.at(-1).requestId, request.requestId);
        assert.equal(uncertain.answers.some(value => value.kind === "refused"), false);
        await uncertain.owner.close();
    }

    // Use the actual core judge, not a second byte-limit implementation.
    // Ask pages arrive first. A later conversation at its existing bound
    // must publish while the optional page becomes explicitly unavailable.
    const PageReference = load(path.join(tree, "shell/Commons/PageReference.js"));
    const core = load(path.join(tree, "shell/Core/PluginLogic.js"), { "qs.Commons 1.0": { PageReference } });
    const publicationFile = path.join(tree, "shell/plugins/vgs.jarvis/StatusPublication.js");
    const publication = load(publicationFile);
    const manifest = JSON.parse(fs.readFileSync(path.join(tree, "shell/plugins/vgs.jarvis/manifest.json"), "utf8"));
    const Conversation = load(path.join(tree, "shell/plugins/vgs.jarvis/Conversation.js"));
    let fullConversation = Conversation.start();
    for (let gen = 0; gen < 64; gen++) fullConversation = Conversation.update(fullConversation,
        { gen, role: "assistant", text: "語".repeat(4000), stage: "final", at: gen, session: "one" });
    assert.ok(Buffer.byteLength(JSON.stringify(fullConversation)) > 23000);
    const bulky = JSON.parse(JSON.stringify(accepted));
    bulky.active = []; bulky.snoozed = [];
    for (const view of ["active", "snoozed"]) {
        for (let index = 0; index < 16; index++) bulky[view].push({ ...accepted.active[0], id: view + index,
            what: "W".repeat(200), state: view === "active" ? "open" : "snoozed",
            snoozedUntil: view === "active" ? null : new Date(Date.now() + 86400000).toISOString() });
        bulky[view + "Count"] = 16; bulky[view + "Cursor"] = null; bulky[view + "NextCursor"] = null;
    }
    Protocol.ownerAsksSnapshot(bulky);
    function quotaContract(policy) {
        const status = { values: {}, set(key, value) {
            const result = core.statusWrite(manifest, this.values, key, value);
            if (result.ok) this.values = result.values;
            return result.ok ? "ok" : result.error;
        } };
        assert.equal(policy.write(status, "ownerAsks", bulky), "ok");
        // Transcript plus a full published audit window are independently
        // valid data statuses. They put the combined publication over quota.
        assert.equal(policy.write(status, "transcript", { text: "語".repeat(4096) }), "ok");
        const failures = Array.from({ length: 20 }, () => ({ time: new Date().toISOString(), tool: "語".repeat(128),
            effect: "destructive", decision: "refuse", outcome: "cancelled", refusal: "identity", cause: null }));
        Protocol.accept(JSON.stringify({ v: 1, type: "audit-failures", gen: 0, revision: "a".repeat(64), rows: failures }), "daemon");
        assert.equal(policy.write(status, "auditFailures", failures), "ok");
        assert.notEqual(status.values.ownerAsks, null, "asks are retained before conversation growth");
        assert.equal(policy.write(status, "conversation", fullConversation), "ok");
        assert.equal(status.values.ownerAsks, null, "quota pressure explicitly removes optional asks");
        assert.equal(JSON.stringify(status.values.conversation), JSON.stringify(fullConversation));
        assert.equal(policy.write(status, "noSuchStatus", []), "refused: status=noSuchStatus reason=undeclared");
        assert.equal(policy.write(status, "conversation", "x".repeat(70000)), "refused: status=conversation reason=size", "unrelated oversize still refuses");
        assert.equal(policy.write(status, "ownerAsks", bulky), "ok");
        assert.equal(status.values.ownerAsks, null, "incoming pages also yield to retained conversation");
    }
    quotaContract(publication);
    const quotaSource = fs.readFileSync(publicationFile, "utf8"), quotaNeedle = 'if (values.ownerAsks !== undefined && values.ownerAsks !== null)';
    assert.equal(quotaSource.split(quotaNeedle).length, 2);
    fs.writeFileSync(path.join(mutationRoot, "StatusPublication.js"), quotaSource.replace(quotaNeedle, "if (false)"));
    assert.throws(() => quotaContract(load(path.join(mutationRoot, "StatusPublication.js"))), assert.AssertionError,
        "control: retaining asks over conversation growth must fail");

    // Execute the shipped Service callback: a dead daemon must not leave
    // ready rows/counts that still invite a reply against its old source.
    const serviceFile = path.join(tree, "shell/plugins/vgs.jarvis/Service.qml");
    const serviceSource = fs.readFileSync(serviceFile, "utf8");
    function serviceEndContract(source) {
        const methods = ["ended", "publishOwnerAsks"].map(name => {
            const match = source.match(new RegExp("^    function " + name + "\\([^\\n]*\\) \\{\\n[\\s\\S]*?^    \\}", "m"));
            assert.ok(match, "shipped callback " + name); return match[0];
        }).join("\n");
        const status = { values: { ownerAsks: accepted }, isOk: core.statusReplyOk, set(key, value) {
            const next = core.statusWrite(manifest, this.values, key, value);
            if (next.ok) this.values = next.values;
            return next.ok ? "ok" : next.error;
        } };
        const timer = { stop() {} };
        const root = { shell: { status }, helloDeadline: timer, stopDeadline: timer, startWait: timer,
            lifetime: { kind: "ready", pendingMute: "none" }, outputTail: "", errorTail: "", cause: "jarvis: daemon=ended",
            retries: 0, cancelDictation() {}, shellStatus() {}, publishDaemon() {}, publishSetup() {}, notice() {} };
        vm.runInNewContext("(function() { with(root) { " + methods + "\nended({status:0,code:78}); } })()", {
            root, StatusPublication: publication, Gate: { startStatus() {}, stoppedNotice() {} }, console: { warn() {} }
        });
        assert.equal(status.values.ownerAsks.kind, "unavailable");
        assert.equal(Object.hasOwn(status.values.ownerAsks, "activeCount"), false, "a dead source publishes no canonical count");
    }
    serviceEndContract(serviceSource);
    const endNeedle = 'if (!publishOwnerAsks({ type: "owner-asks", snapshot: { kind: "unavailable",';
    assert.equal(serviceSource.split(endNeedle).length, 2);
    assert.throws(() => serviceEndContract(serviceSource.replace(endNeedle, 'if (false && !publishOwnerAsks({ type: "owner-asks", snapshot: { kind: "unavailable",')),
        assert.AssertionError, "control: retaining ended daemon asks must fail");

    // A held real-owner child callback from the old home cannot publish
    // into the selected home, even when cancellation races its completion.
    const held = [], stale = client({ run: (file, argv, options) => new Promise(resolve => held.push({ argv, options, resolve })) });
    const first = stale.owner.setHome(folder);
    const other = home("other", 3);
    const second = stale.owner.setHome(other);
    assert.equal(held[0].options.signal.aborted, true);
    const page = { v: 1, homeId: "late", revision: "late", observedAt: new Date().toISOString(), activeCount: 0, snoozedCount: 0, rows: [], nextCursor: null, complete: true };
    held[0].resolve({ kind: "exited", code: 0, stdout: JSON.stringify(page), stderr: "" });
    await first;
    assert.equal(stale.snapshots.some(snapshot => snapshot.homeId === "late"), false);
    const closing = stale.owner.close();
    assert.equal(held[1].options.signal.aborted, true);
    held[1].resolve({ kind: "stopped", reason: "cancelled", stdout: "", stderr: "" });
    await second; await closing;
    assert.equal(stale.time.timers.size, 0);
    console.log("test-jarvis-owner-asks: ok");
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => fs.rmSync(root, { recursive: true, force: true }));
