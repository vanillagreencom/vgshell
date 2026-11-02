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
const PageReference = load(path.join(tree, "shell/Commons/PageReference.js"));
const core = load(path.join(tree, "shell/Core/PluginLogic.js"), { "qs.Commons 1.0": { PageReference } });
const publicationFile = path.join(tree, "shell/plugins/vgs.jarvis/StatusPublication.js");
const publication = load(publicationFile);
const manifest = JSON.parse(fs.readFileSync(path.join(tree, "shell/plugins/vgs.jarvis/manifest.json"), "utf8"));
const Conversation = load(path.join(tree, "shell/plugins/vgs.jarvis/Conversation.js"));
const serviceFile = path.join(tree, "shell/plugins/vgs.jarvis/Service.qml");
const serviceSource = fs.readFileSync(serviceFile, "utf8");
const plain = value => JSON.parse(JSON.stringify(value));
function statusWith(values = {}) {
    const status = { values: {}, isOk: core.statusReplyOk, set(key, value) {
        const result = core.statusWrite(manifest, this.values, key, value);
        if (result.ok) this.values = result.values;
        return result.ok ? "ok" : result.error;
    } };
    for (const [key, value] of Object.entries(values)) assert.equal(status.set(key, value), "ok");
    return status;
}
function service(source = serviceSource, values = {}, policy = publication) {
    const names = ["ownerAskOperation", "setOwnerAskOperation", "unconfirmOwnerAsk", "ownerAsksIntent", "publishOwnerAsks", "start", "ended", "broken"];
    const methods = names.map(name => {
        const match = source.match(new RegExp("^    function " + name + "\\([^\\n]*\\) \\{\\n[\\s\\S]*?^    \\}", "m"));
        assert.ok(match, "shipped Service method " + name); return match[0];
    }).join("\n");
    const sent = [], work = [], warnings = [], status = statusWith(values);
    // The Qt Timer surface the copied methods call: start, stop and restart.
    const timer = { start() {}, stop() {}, restart() {} };
    const root = { shell: { status, settings: { home: "" }, manifest: { ...manifest, __revision: "a".repeat(64) } },
        selectedHome: "", lifetime: { kind: "ready", pendingMute: "none" }, cause: "", locked: false,
        child: { running: true }, childSerial: 1, retries: 0, outputTail: "", errorTail: "",
        helloDeadline: timer, stopDeadline: timer, startWait: timer, retry: { ...timer },
        cancelDictation() {}, shellStatus() { return true; }, publishDaemon() {}, publishSetup() { return true; },
        publishInput() { return true; }, publishHomes() { return true; }, publish() { return true; },
        notice() {}, resolveHomePath() {},
        send(fields) { sent.push({ fields, operation: plain(status.values.ownerAskAnswer) }); }
    };
    Object.assign(root, vm.runInNewContext("(function() { with(root) { " + methods + "\nreturn {" + names.join(",") + "}; } })()", {
        root, Protocol, StatusPublication: policy, Conversation, Gate: { startStatus() {}, stoppedNotice() {}, RETRYING_START: "retry" },
        console: { warn: message => warnings.push(message) }
    }));
    function callback(name) {
        const match = source.match(new RegExp("^    " + name + ": \\{\\n([\\s\\S]*?)^    \\}", "m"));
        assert.ok(match, "shipped Service callback " + name);
        return vm.runInNewContext("(function() { with(root) { " + match[1] + " } })", { root });
    }
    return { root, status, sent, work, warnings, homeChanged: callback("onSelectedHomeChanged"), destroyed: callback("Component.onDestruction"),
        admit: request => root.ownerAsksIntent("owner-ask-action", JSON.stringify(request)),
        answer(result) {
            const message = Protocol.accept(JSON.stringify({ v: 1, type: "owner-ask-answer", gen: 0, revision: "a".repeat(64), result }), "daemon");
            return root.publishOwnerAsks(message);
        } };
}
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
    return { timers, set(fn) { timers.set(++serial, fn); return serial; }, clear(id) { timers.delete(id); } };
}
function client(extra = {}) {
    const snapshots = [], answers = [], logs = [], time = clock();
    const owner = OwnerAsks.create({ Protocol, environment, log: s => logs.push(s), clock: time, ...extra,
        publish: s => { snapshots.push(s); if (extra.publish) extra.publish(s); },
        answer: s => { answers.push(s); if (extra.answer) extra.answer(s); } });
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
    async function uncertainContract(source, mode, action) {
        const uncertainHome = home(mode + "-" + action + "-" + (source === serviceSource ? "real" : "control"), 3);
        const h = service(source);
        h.root.shell.settings.home = uncertainHome;
        h.root.selectedHome = uncertainHome;
        function connect() {
            return client({ publish: snapshot => h.root.publishOwnerAsks({ type: "owner-asks", snapshot }), answer: result => h.answer(result),
                run(file, argv, options) {
                    if (argv[5] === "list" || mode !== "receipt-timeout") return Child.run(file, argv, options);
                    let deadline;
                    return Child.run(file, argv, { ...options,
                        clock: { set(fn, ms) { assert.equal(ms, 15000); deadline = fn; return 1; }, clear() {} },
                        attach(child) {
                            let progress = "";
                            child.stderr.on("data", bytes => { progress += bytes.toString(); if (progress.includes("fixture: receipt-written")) deadline(); });
                        }
                    });
                } });
        }
        let uncertain = connect();
        h.root.send = fields => {
            h.sent.push({ fields, operation: plain(h.status.values.ownerAskAnswer) });
            h.work.push(uncertain.owner.act(fields.request));
        };
        try {
            await uncertain.owner.setHome(uncertainHome);
            control("--mode", uncertainHome, mode);
            const request = { action, id: "tracker-design", requestId: "uncertain-" + mode + "-" + action,
                expectedRevision: "1", text: action === "reply" ? "One owner reply." : "",
                until: action === "later" ? new Date(Date.now() + 86400000).toISOString() : null };
            const original = { ...request };
            assert.equal(h.admit(request), "ok");
            assert.equal(h.sent[0].operation.kind, "first-pending", "recovery is published before forwarding");
            assert.equal(h.admit(original), "refused: owner-ask=pending");
            if (action === "later") request.until = new Date(Date.now() + 172800000).toISOString();
            else request.text = "Changed caller object.";
            await h.work.at(-1);
            assert.equal(control("--state", uncertainHome).rows.find(row => row.id === request.id).revision, "2", "fixture really acted");
            assert.equal(h.status.values.ownerAskAnswer.kind, "unknown", mode);
            assert.deepEqual(plain(h.status.values.ownerAskAnswer.request), original, "the caller cannot mutate canonical recovery");
            assert.equal(h.admit(request), "refused: owner-ask=unconfirmed");
            assert.equal(h.admit({ ...original, requestId: "new-identity", expectedRevision: "2" }), "refused: owner-ask=unconfirmed");
            control("--mode", uncertainHome, "unavailable");
            await uncertain.owner.refresh();
            assert.equal(h.status.values.ownerAsks.kind, "unavailable");
            // Recreate the actual backend owner while the existing Service and
            // core status survive. The public package keeps its receipt on disk.
            await uncertain.owner.close();
            h.root.child.running = false;
            h.root.ended({ status: 0, code: 1 });
            assert.equal(h.status.values.ownerAskAnswer.kind, "unknown");
            const childSerial = h.root.childSerial;
            h.root.start();
            assert.equal(h.root.childSerial, childSerial + 1);
            assert.notEqual(h.status.values.ownerAskAnswer, null, "start cannot erase a possibly applied action");
            assert.deepEqual(plain(h.status.values.ownerAskAnswer.request), original, "start cannot erase a possibly applied action");
            assert.equal(h.sent.length, 1, "restart never replays an action");
            uncertain = connect();
            await uncertain.owner.setHome(uncertainHome);
            h.root.lifetime = { kind: "ready", pendingMute: "none" };
            h.root.cause = "";
            assert.equal(h.status.values.ownerAsks.kind, "unavailable");
            control("--mode", uncertainHome, "ready");
            assert.equal(h.admit(original), "ok");
            assert.equal(h.sent.at(-1).operation.kind, "retry-pending");
            await h.work.at(-1);
            assert.equal(h.status.values.ownerAskAnswer.kind, "answered");
            assert.equal(h.status.values.ownerAskAnswer.result.kind, "accepted", "the restarted child reaches the package idempotency lookup");
            const state = control("--state", uncertainHome);
            assert.equal(state.rows.find(row => row.id === original.id).revision, "2", "retry does not apply the action twice");
            assert.deepEqual(Object.keys(state.receipts), [original.requestId]);
            const actions = fs.readFileSync(path.join(uncertainHome, ".owner-asks-fixture-calls.jsonl"), "utf8").trim().split("\n")
                .map(JSON.parse).filter(call => call.argv[1] !== "list");
            assert.equal(actions.length, 2, "only the original and deliberate identical retry reach the public command");
            assert.deepEqual(actions[1].input, actions[0].input);
            assert.equal(h.admit({ ...original, requestId: "new-stale-request" }), "ok");
            await h.work.at(-1);
            assert.equal(h.status.values.ownerAskAnswer.result.kind, "refused", "the package alone judges a new stale revision");
            if (mode === "receipt-malformed" && action === "reply") {
                control("--mode", uncertainHome, mode);
                const next = { ...original, requestId: "next-reply", expectedRevision: "2" };
                assert.equal(h.admit(next), "ok");
                await h.work.at(-1);
                assert.equal(h.status.values.ownerAskAnswer.kind, "unknown");
                const other = home("uncertain-home-change", 3);
                h.root.shell.settings.home = other;
                h.root.selectedHome = other;
                h.homeChanged();
                assert.equal(h.status.values.ownerAskAnswer, null, "Home change releases recovery ownership");
                h.answer({ v: 1, requestId: next.requestId, kind: "accepted", state: "open", cause: "" });
                assert.equal(h.status.values.ownerAskAnswer, null, "an old receipt cannot populate an empty Home owner");
                await uncertain.owner.setHome(other);
            }
        } finally {
            await uncertain.owner.close();
            h.destroyed();
            assert.equal(h.status.values.ownerAskAnswer, null, "actual Service teardown clears its action");
        }
    }
    for (const mode of ["receipt-malformed", "receipt-timeout"])
        for (const action of ["reply", "done", "later"]) await uncertainContract(serviceSource, mode, action);
    const serviceControl = path.join(mutationRoot, "Service.qml");
    const clearNeedle = 'const asks = StatusPublication.write(shell.status, "ownerAsks", { kind: "reading" });';
    assert.equal(serviceSource.split(clearNeedle).length - 1, 1);
    fs.writeFileSync(serviceControl, serviceSource.replace(clearNeedle,
        'setOwnerAskOperation(null);\n        ' + clearNeedle));
    await assert.rejects(() => uncertainContract(fs.readFileSync(serviceControl, "utf8"), "receipt-malformed", "reply"), assert.AssertionError,
        "control: clearing recovery on a child restart must fail the package regression");

    // Use the actual core judge, not a second byte-limit implementation.
    // Ask pages arrive first. A later conversation at its existing bound
    // must publish while the optional page becomes explicitly unavailable.
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
        const status = statusWith();
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

    const retainedRequest = { action: "reply", id: "tracker-design", requestId: "canonical-recovery", expectedRevision: "1", text: "One reply.", until: null };
    const operation = kind => ({ kind, home: "", request: retainedRequest, result: null });
    const receipt = kind => ({ v: 1, requestId: retainedRequest.requestId, kind,
        state: kind === "accepted" ? "open" : null, cause: kind === "accepted" ? "" : "The action was not confirmed." });
    for (const [phase, incoming, expected] of [
        ["first-pending", "accepted", "answered"], ["first-pending", "refused", "answered"],
        ["first-pending", "unknown", "unknown"], ["first-pending", "not-sent", "answered"],
        ["retry-pending", "accepted", "answered"], ["retry-pending", "refused", "answered"],
        ["retry-pending", "unknown", "unknown"], ["retry-pending", "not-sent", "unknown"]
    ]) {
        const h = service(serviceSource, { ownerAskAnswer: operation(phase) });
        assert.equal(h.answer(receipt(incoming)), true);
        assert.equal(h.status.values.ownerAskAnswer.kind, expected, phase + "/" + incoming);
        assert.deepEqual(plain(h.status.values.ownerAskAnswer.request), retainedRequest);
        if (expected === "answered") assert.equal(h.status.values.ownerAskAnswer.result.kind, incoming);
        else assert.equal(h.status.values.ownerAskAnswer.result, null);
    }
    // A valid memory-inbox publication can use more than the entire status
    // quota. Find the boundary with its real Protocol and core judges.
    function fillStatus(status) {
        function entries(length) {
            return Array.from({ length: 4 }, (_, i) => ({ id: "00000000-0000-4000-8000-" + String(i).padStart(12, "0"),
                target: "note-" + i + ".md", kind: "propose", title: "Memory note", labels: ["file"],
                text: "x".repeat(Math.max(0, Math.min(Protocol.MEMORY_TEXT_MAX, length - i * Protocol.MEMORY_TEXT_MAX))), hash: "a".repeat(64), problem: "" }));
        }
        let low = 0, high = 4 * Protocol.MEMORY_TEXT_MAX;
        while (low < high) {
            const middle = Math.ceil((low + high) / 2), value = entries(middle);
            Protocol.accept(JSON.stringify({ v: 1, type: "memory-inbox", gen: 0, revision: "a".repeat(64), entries: value }), "daemon");
            const result = publication.write(status, "memoryInbox", value);
            if (result === "ok") low = middle;
            else { assert.equal(result, "refused: status=memoryInbox reason=size"); high = middle - 1; }
        }
        assert.equal(publication.write(status, "memoryInbox", entries(low)), "ok");
    }
    const full = service(serviceSource, { ownerAsks: null });
    fillStatus(full.status);
    assert.equal(full.admit(retainedRequest), "refused: status=ownerAskAnswer reason=size");
    assert.equal(full.sent.length, 0, "no action runs without a retained recovery reservation");
    assert.equal(full.status.values.ownerAskAnswer, undefined);
    function receiptQuotaContract(policy, incoming, phase) {
        const h = service(serviceSource, { ownerAsks: bulky, ownerAskAnswer: operation(phase) }, policy);
        fillStatus(h.status);
        assert.equal(h.status.values.ownerAsks, null, "optional page eviction cannot evict the operation");
        const before = plain(h.status.values.ownerAskAnswer);
        assert.equal(h.answer(receipt(incoming)), true);
        const expected = incoming === "not-sent" && phase === "first-pending" ? "not-sent" : "unknown";
        assert.equal(h.status.values.ownerAskAnswer.kind, expected, "a refused receipt publication cannot count as retained");
        assert.deepEqual(plain(h.status.values.ownerAskAnswer.request), retainedRequest);
        assert.equal(h.status.values.ownerAskAnswer.result, null);
        assert.ok(Buffer.byteLength(JSON.stringify(h.status.values.ownerAskAnswer)) < Buffer.byteLength(JSON.stringify(before)));
        h.answer(receipt("accepted"));
        assert.equal(h.status.values.ownerAskAnswer.kind, expected, "late answers cannot settle a non-pending operation");
        if (expected === "unknown") {
            // Other legitimate statuses can consume the room released by the
            // shorter tag. A retry must reserve again before it can run.
            fillStatus(h.status);
            assert.equal(h.admit(retainedRequest), "refused: status=ownerAskAnswer reason=size");
            assert.equal(h.sent.length, 0);
            assert.equal(h.status.values.ownerAskAnswer.kind, "unknown");
            assert.equal(publication.write(h.status, "memoryInbox", []), "ok");
            assert.equal(h.admit(retainedRequest), "ok");
            assert.deepEqual(plain(h.sent[0].fields.request), retainedRequest);
        } else {
            assert.equal(publication.write(h.status, "memoryInbox", []), "ok");
            assert.equal(h.admit({ ...retainedRequest, requestId: "after-not-sent" }), "ok", "known not-sent releases the action identity");
        }
    }
    for (const phase of ["first-pending", "retry-pending"])
        for (const incoming of ["accepted", "refused", "unknown", "not-sent"]) receiptQuotaContract(publication, incoming, phase);
    const receiptQuotaNeedle = "    return reply;\n}";
    assert.equal(quotaSource.split(receiptQuotaNeedle).length - 1, 1);
    fs.writeFileSync(path.join(mutationRoot, "StatusPublication.js"), quotaSource.replace(receiptQuotaNeedle,
        '    if (key === "ownerAskAnswer" && reply === "refused: status=" + key + " reason=size") return set("ownerAsks", null);\n' + receiptQuotaNeedle));
    assert.throws(() => receiptQuotaContract(load(path.join(mutationRoot, "StatusPublication.js")), "accepted", "first-pending"), assert.AssertionError,
        "control: reporting an optional page clear as a retained receipt must fail");

    const identities = service(serviceSource, { ownerAskAnswer: operation("unknown") });
    for (const change of [
        { action: "done" }, { id: "another-ask" }, { requestId: "another-request" },
        { expectedRevision: "2" }, { text: "Changed reply." }
    ]) assert.equal(identities.admit({ ...retainedRequest, ...change }), "refused: owner-ask=unconfirmed");
    const laterRequest = { ...retainedRequest, action: "later", text: "", until: new Date(Date.now() + 86400000).toISOString() };
    const laterIdentity = service(serviceSource, { ownerAskAnswer: { ...operation("unknown"), request: laterRequest } });
    assert.equal(laterIdentity.admit({ ...laterRequest, until: new Date(Date.now() + 172800000).toISOString() }), "refused: owner-ask=unconfirmed");
    assert.equal(identities.sent.length + laterIdentity.sent.length, 0, "each changed primitive refuses before forwarding");
    identities.root.locked = true;
    assert.equal(identities.admit(retainedRequest), "refused: owner-ask=locked");
    identities.root.locked = false;
    for (const [key, value] of [["lifetime", { kind: "starting" }], ["cause", "jarvis: daemon=ended"], ["child", { running: false }]]) {
        const previous = identities.root[key]; identities.root[key] = value;
        assert.equal(identities.admit(retainedRequest), "refused: jarvis=not-ready");
        identities.root[key] = previous;
    }
    assert.equal(identities.root.ownerAsksIntent("owner-ask-action", "broken"), "refused: owner-ask=json");
    assert.match(identities.admit({ ...retainedRequest, extra: true }), /^refused: jarvis: protocol=/);
    assert.equal(identities.status.values.ownerAskAnswer.kind, "unknown");
    const transport = service(serviceSource, { ownerAskAnswer: operation("retry-pending") });
    transport.root.broken("jarvis: protocol=broken");
    assert.equal(transport.status.values.ownerAskAnswer.kind, "unknown", "a broken wire preserves possible application");
    const wrongReceipt = service(serviceSource, { ownerAskAnswer: operation("first-pending") });
    wrongReceipt.answer({ ...receipt("accepted"), requestId: "another-request" });
    assert.equal(wrongReceipt.status.values.ownerAskAnswer.kind, "first-pending");

    for (const kind of ["stale", "disallowed", "past-later"]) {
        const target = home("package-refuses-" + kind, 3), canonical = client();
        if (kind === "disallowed") {
            const stateFile = path.join(target, ".owner-asks-fixture.json"), state = JSON.parse(fs.readFileSync(stateFile, "utf8"));
            state.rows.find(row => row.id === retainedRequest.id).actions.done = { allowed: false, reason: "This ask is waiting for another answer." };
            fs.writeFileSync(stateFile, JSON.stringify(state));
        }
        try {
            await canonical.owner.setHome(target);
            const request = { ...retainedRequest, requestId: "package-" + kind,
                action: kind === "disallowed" ? "done" : kind === "past-later" ? "later" : "reply",
                text: kind === "stale" ? retainedRequest.text : "", expectedRevision: kind === "stale" ? "old" : "1",
                until: kind === "past-later" ? new Date(Date.now() - 1000).toISOString() : null };
            await canonical.owner.act(request);
            assert.equal(canonical.answers.at(-1).kind, "refused", "the public package judges " + kind);
            assert.equal(control("--state", target).revision, 1, "refusal has no effect");
            const calls = fs.readFileSync(path.join(target, ".owner-asks-fixture-calls.jsonl"), "utf8").trim().split("\n").map(JSON.parse);
            assert.equal(calls.filter(call => call.argv[1] !== "list").length, 1, "backend page state does not replace the package judge");
        } finally { await canonical.owner.close(); }
    }

    // Execute the shipped Service callback: a dead daemon must not leave
    // ready rows/counts that still invite a reply against its old source.
    function serviceEndContract(source) {
        const h = service(source, { ownerAsks: accepted });
        h.root.ended({ status: 0, code: 78 });
        assert.equal(h.status.values.ownerAsks.kind, "unavailable");
        assert.equal(Object.hasOwn(h.status.values.ownerAsks, "activeCount"), false, "a dead source publishes no canonical count");
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
