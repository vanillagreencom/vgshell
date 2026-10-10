#!/usr/bin/env node
// Jarvis memory search index: Memory.js owns the disposable SQLite FTS5 index,
// reads notes only through Home.js, and returns Policy labels from note
// sources. The scratch world is under JARVIS_TEST_ROOT.
"use strict";
const crypto = require("node:crypto");
const { assert, fs, path, tree, world, seed, mutant } = require("./fixtures/jarvis/policy.js");
const { load } = require("../bin/lib/qml-library.js");
const backend = path.join(tree, "shell/plugins/vgs.jarvis/backend");
const memoryFile = path.join(backend, "Memory.js");
const homeFile = path.join(backend, "Home.js");
const routerFile = path.join(backend, "ToolRouter.js");

world(() => {
    const Memory = require(memoryFile);
    const Tools = require(path.join(backend, "Tools.js"));
    const Home = require(path.join(backend, "Home.js"));
    const Router = require(path.join(backend, "ToolRouter.js"));
    const Audit = require(path.join(backend, "Audit.js"));
    const Denied = require(path.join(backend, "Denied.js"));
    const Policy = require(path.join(backend, "Policy.js"));
    const Session = load(path.join(tree, "shell/plugins/vgs.jarvis/Session.js"));
    const Protocol = load(path.join(tree, "shell/plugins/vgs.jarvis/JarvisProtocol.js"));
    const { SessionRunner, unavailable } = require(path.join(backend, "session-runner.js"));
    const fixtures = seed();
    let serial = 0;

    function attach(logic, folder, state, options = {}) {
        const router = { record: null, register(id, executor) { assert.equal(id, "memory"); this.record = executor; } };
        const logs = [];
        const installed = logic.install({ router, directory: path.join(state, "memory"), home: () => folder,
            log: line => logs.push(line), ...options });
        assert.equal(installed.kind, "installed");
        const call = (id, args, origin) => {
            let answer;
            router.record.start({ id, args }, value => { answer = value; }, undefined, origin);
            return answer;
        };
        const search = args => {
            const answer = call("memory.search", args);
            assert.equal(answer.outcome, "completed", JSON.stringify(answer));
            return { answer, body: JSON.parse(answer.content) };
        };
        const read = ids => {
            const answer = call("memory.read", { ids });
            return { answer, body: answer.content.startsWith("{") ? JSON.parse(answer.content) : null };
        };
        const writeCall = (id, args, origin = { labels: ["home"], tainted: false }) => call(id, args, origin);
        return { installed, search, read, writeCall, logs };
    }
    const sha = text => crypto.createHash("sha256").update(text).digest("hex");
    const receipts = state => {
        const folder = path.join(state, "memory-receipts");
        return fs.existsSync(folder) ? fs.readdirSync(folder).map(name => JSON.parse(fs.readFileSync(path.join(folder, name), "utf8"))) : [];
    };

    function make(logic = Memory) {
        const root = path.join(process.env.JARVIS_TEST_ROOT, "memory-" + ++serial);
        const folder = path.join(root, "home");
        const state = path.join(root, "state");
        fs.mkdirSync(root, { recursive: true });
        Home.layout(folder);
        fs.mkdirSync(state, { recursive: true });
        const write = (id, text) => {
            fs.mkdirSync(path.dirname(path.join(folder, "memory", id)), { recursive: true });
            fs.writeFileSync(path.join(folder, "memory", id), text);
        };
        return { root, folder, state, write, db: path.join(state, "memory/memory.sqlite"), ...attach(logic, folder, state) };
    }

    function populate(w) {
        w.write("facts/title.md", "---\ntitle: Alpha launch\naliases: [rocket, crew]\ndate: 2026-10-01\nsources: [web]\n---\n# Alpha launch\nThe launch note links [[facts/body.md|body]] and [[Inbox secret]].\n");
        w.write("facts/body.md", "---\ntitle: Body note\ndate: 2026-10-02\n---\n# Body note\nThe body mentions alpha once and links [[Alpha launch#heading]].\n");
        w.write("facts/old.md", "---\ntitle: Old note\ndate: 2025-01-01\n---\n# Old note\nalpha old body only.\n");
        w.write("facts/empty.md", " \n");
        w.write("inbox/pending.md", "---\ntitle: Inbox secret\nsources: [web]\n---\n# Inbox secret\nneedle-inbox alpha [[facts/title.md]]\n");
    }

    const w = make();
    populate(w);
    let found = w.search({ query: "alpha" });
    assert.deepEqual(found.body.results.map(row => row.id).slice(0, 2), ["facts/title.md", "facts/body.md"], "title rank beats body rank");
    assert.deepEqual(found.answer.labels, ["home", "web"]);
    assert.deepEqual(found.body.results.find(row => row.id === "facts/title.md").sources, ["home", "web"]);
    w.write("facts/crlf.md", "---\r\ntitle: CRLF note\r\nsources: [web]\r\n---\r\n# CRLF\r\ncrlf-token\r\n");
    w.write("facts/quoted.md", "---\ntitle: Quoted source\nsources: [\"web\"]\n---\n# Quoted\nquoted-token\n");
    assert.deepEqual(w.search({ query: "crlf-token" }).body.results[0].sources, ["home", "web"]);
    assert.deepEqual(w.search({ query: "quoted-token" }).body.results[0].sources, ["home", "web"]);
    assert.equal(found.body.results.some(row => row.id === "inbox/pending.md"), false, "inbox is not searched");
    assert.deepEqual(w.search({ query: "alpha", title: "body" }).body.results.map(row => row.id), ["facts/body.md"]);
    assert.deepEqual(w.search({ query: "alpha", alias: "rocket" }).body.results.map(row => row.id), ["facts/title.md"]);
    assert.deepEqual(w.search({ query: "alpha", since: "2026-01-01", until: "2026-12-31" }).body.results.map(row => row.id),
        ["facts/title.md", "facts/body.md"]);
    assert.deepEqual(w.search({ query: "alpha", since: "2027-01-01" }).body.results, []);
    assert.deepEqual(w.search({ query: "needle-inbox" }).body.results, [], "inbox text is absent from the index");
    assert.deepEqual(w.read(["facts/title.md"]).body.notes[0].links, ["facts/body.md"]);
    assert.equal(typeof w.read(["facts/title.md"]).body.notes[0].hash, "string", "read carries the current hash");
    assert.deepEqual(w.read(["facts/body.md"]).body.notes[0].backlinks, ["facts/title.md"]);
    assert.equal(w.read(["inbox/pending.md"]).answer.outcome, "failed", "inbox is not read");
    const mixed = w.read(["facts/title.md", "facts/empty.md", "facts/missing.md"]);
    assert.equal(mixed.answer.outcome, "completed");
    assert.deepEqual(mixed.body.notes.map(note => note.error || note.id), ["facts/title.md", "empty", "absent"]);
    assert.deepEqual(mixed.answer.labels, ["home", "web"]);
    assert.equal(Tools.refine({ id: "memory.read", args: { ids: ["a.md", "b.md", "c.md", "d.md", "e.md", "f.md"] } }).reason, "argument-shape");
    assert.equal(fs.existsSync(path.join(w.folder, "memory.sqlite")), false, "the index is not under the home");
    assert.equal(fs.existsSync(w.db), true, "the index is private state");
    const beforeDelete = w.search({ query: "alpha" }).body.results.map(row => [row.id, row.snippet]);
    w.installed.close();
    fs.rmSync(w.db, { force: true });
    const rebuilt = make();
    fs.cpSync(path.join(w.folder, "memory"), path.join(rebuilt.folder, "memory"), { recursive: true, force: true });
    assert.deepEqual(rebuilt.search({ query: "alpha" }).body.results.map(row => [row.id, row.snippet]), beforeDelete, "delete and restart rebuilds the same results");
    fs.writeFileSync(path.join(rebuilt.folder, "memory/facts/body.md"), "# Body note\nfresh-live term\n");
    assert.deepEqual(rebuilt.search({ query: "fresh-live" }).body.results.map(row => row.id), ["facts/body.md"], "a live edit is found next search");
    rebuilt.installed.close();
    const downFile = path.join(rebuilt.folder, "memory/facts/body.md");
    const downStat = fs.statSync(downFile);
    fs.writeFileSync(downFile, "# Body note\nfresh-down term\n");
    fs.truncateSync(downFile, downStat.size);
    fs.utimesSync(downFile, downStat.atime, downStat.mtime);
    Object.assign(rebuilt, attach(Memory, rebuilt.folder, rebuilt.state));
    assert.deepEqual(rebuilt.search({ query: "fresh-down" }).body.results.map(row => row.id), ["facts/body.md"], "a down edit is reconciled on start");
    const unavailableHome = { value: null };
    const late = attach(Memory, rebuilt.folder, path.join(rebuilt.root, "late"), { home: () => unavailableHome.value });
    assert.equal(late.installed.kind, "installed");
    unavailableHome.value = rebuilt.folder;
    late.installed.reconcileStart();
    assert.deepEqual(late.search({ query: "fresh-down" }).body.results.map(row => row.id), ["facts/body.md"], "start reconcile runs after a home appears");

    const writes = make();
    let proposed = writes.writeCall("memory.propose", { id: "facts/proposed.md", text: "# Proposed\nclean-proposed\n" });
    assert.equal(proposed.outcome, "completed");
    assert.deepEqual(JSON.parse(proposed.content), { status: "written", id: "facts/proposed.md", kind: "propose" });
    assert.deepEqual(writes.writeCall("memory.propose", { id: "MEMORY.md", text: "bootstrap" }).content, "memory-propose:bootstrap");
    assert.equal(writes.search({ query: "clean-proposed" }).body.results[0].id, "facts/proposed.md");
    writes.installed.close();
    Object.assign(writes, attach(Memory, writes.folder, writes.state));
    assert.equal(writes.search({ query: "clean-proposed" }).body.results[0].id, "facts/proposed.md", "proposed note survives restart");
    const readProposed = writes.read(["facts/proposed.md"]).body.notes[0];
    assert.equal(readProposed.hash, sha(readProposed.text));
    writes.write("facts/crlf-replace.md", "# CRLF\r\nold\r\n");
    const crlf = writes.read(["facts/crlf-replace.md"]).body.notes[0];
    assert.equal(crlf.hash, sha("# CRLF\r\nold\r\n"));
    const crlfAnswer = writes.writeCall("memory.replace", { id: "facts/crlf-replace.md", text: "# CRLF\r\nnew-crlf-token\r\n", hash: crlf.hash });
    assert.equal(crlfAnswer.outcome, "completed");
    assert.equal(writes.search({ query: "new-crlf-token" }).body.results[0].id, "facts/crlf-replace.md");
    const replaced = writes.writeCall("memory.replace", { id: "facts/proposed.md", text: "# Proposed\nreplacement-token\n", hash: readProposed.hash });
    assert.equal(replaced.outcome, "completed");
    assert.equal(writes.search({ query: "replacement-token" }).body.results[0].id, "facts/proposed.md");
    const beforeConflict = writes.read(["facts/proposed.md"]).body.notes[0];
    fs.writeFileSync(path.join(writes.folder, "memory/facts/proposed.md"), "# Proposed\nuser bytes\n");
    const conflict = writes.writeCall("memory.replace", { id: "facts/proposed.md", text: "# Proposed\nlost bytes\n", hash: beforeConflict.hash });
    assert.deepEqual([conflict.outcome, conflict.content], ["failed", "memory-replace:conflict"]);
    assert.equal(fs.readFileSync(path.join(writes.folder, "memory/facts/proposed.md"), "utf8"), "# Proposed\nuser bytes\n");
    assert.equal(writes.read(["facts/proposed.md"]).body.notes[0].edited, true, "receipt no longer vouches for hand-edited bytes");

    const tainted = make();
    const pending = tainted.writeCall("memory.propose", { id: "facts/web.md", text: "# Web\nweb-pending-token\n" },
        { labels: ["home", "web"], tainted: true });
    assert.equal(pending.outcome, "completed");
    assert.deepEqual(Object.keys(JSON.parse(pending.content)).sort(), ["id", "kind", "status"]);
    assert.deepEqual(tainted.search({ query: "web-pending-token" }).body.results, [], "pending text is not searched");
    assert.equal(tainted.read(["facts/web.md"]).answer.outcome, "failed", "pending target is not read");
    const waiting = tainted.installed.pending();
    assert.equal(waiting.length, 1);
    assert.deepEqual([waiting[0].target, waiting[0].kind, waiting[0].labels], ["facts/web.md", "propose", ["home", "web"]]);
    assert.throws(() => tainted.installed.confirm(waiting[0].id, "0".repeat(64)), { message: "jarvis: memory=hash" });
    assert.equal(tainted.installed.pending().length, 1, "hash mismatch keeps the inbox entry");
    const waitingAfterHash = tainted.installed.pending()[0];
    assert.deepEqual(tainted.installed.confirm(waitingAfterHash.id, waitingAfterHash.hash), { kind: "confirmed", target: "facts/web.md" });
    assert.equal(receipts(tainted.state).some(row => row.inbox === waiting[0].id), false, "confirm removes inbox receipt");
    assert.equal(tainted.search({ query: "web-pending-token" }).body.results[0].id, "facts/web.md");
    assert.deepEqual(tainted.read(["facts/web.md"]).body.notes[0].sources, ["home", "web"], "confirmed note keeps host origin label");
    const duplicatePending = tainted.writeCall("memory.propose", { id: "facts/web.md", text: "duplicate" },
        { labels: ["home", "web"], tainted: true });
    assert.deepEqual([duplicatePending.outcome, duplicatePending.content], ["failed", "memory-propose:exists"]);
    const stalePending = tainted.writeCall("memory.replace", { id: "facts/web.md", text: "stale", hash: "0".repeat(64) },
        { labels: ["home", "web"], tainted: true });
    assert.deepEqual([stalePending.outcome, stalePending.content], ["failed", "memory-replace:conflict"]);
    const confirmedNote = tainted.read(["facts/web.md"]).body.notes[0];
    tainted.writeCall("memory.replace", { id: "facts/web.md", text: "# Web\nconfirmed-replace-token\n", hash: confirmedNote.hash },
        { labels: ["home", "web"], tainted: true });
    const replaceWait = tainted.installed.pending()[0];
    fs.writeFileSync(path.join(tainted.folder, "memory/facts/web.md"), "# Web\nuser conflict\n");
    assert.throws(() => tainted.installed.confirm(replaceWait.id, replaceWait.hash), { message: "jarvis: memory=conflict" });
    assert.equal(tainted.installed.pending()[0].problem, "conflict");
    assert.equal(fs.readFileSync(path.join(tainted.folder, "memory/facts/web.md"), "utf8"), "# Web\nuser conflict\n");

    const discarded = make();
    discarded.writeCall("memory.propose", { id: "facts/no.md", text: "discard-token" }, { labels: ["home", "web"], tainted: true });
    const waitingDiscard = discarded.installed.pending()[0];
    assert.deepEqual(discarded.installed.discard(waitingDiscard.id, waitingDiscard.hash), { kind: "discarded", target: "facts/no.md" });
    assert.equal(receipts(discarded.state).some(row => row.inbox === waitingDiscard.id), false, "discard removes inbox receipt");
    assert.deepEqual(discarded.search({ query: "discard-token" }).body.results, []);

    const inboxBound = make();
    const longTitle = "L".repeat(200);
    inboxBound.writeCall("memory.propose", { id: "facts/long-title.md", text: "# " + longTitle + "\nlong-title-token\n" },
        { labels: ["home", "web"], tainted: true });
    fs.writeFileSync(path.join(inboxBound.folder, "memory/inbox/bad.json"), "{not json");
    for (let n = 0; n < 70; n++)
        inboxBound.writeCall("memory.propose", { id: "many/note-" + n + ".md", text: "# Note " + n + "\n" + "x".repeat(200) },
            { labels: ["home", "web"], tainted: true });
    const inboxEntries = inboxBound.installed.pending();
    assert.equal(inboxEntries.length, 64, "wire inbox is capped by count");
    assert.ok(inboxEntries.some(entry => entry.target === "facts/long-title.md" && entry.title.length <= 128));
    assert.doesNotThrow(() => Protocol.accept(JSON.stringify({ v: 1, type: "memory-inbox", gen: 1,
        revision: "a".repeat(64), entries: inboxEntries }), "daemon"));

    const inherited = make();
    inherited.write("facts/labelled.md", "---\nsources: [web]\n---\n# Labelled\noriginal-label\n");
    const labelled = inherited.read(["facts/labelled.md"]).body.notes[0];
    inherited.writeCall("memory.replace", { id: "facts/labelled.md", text: "# Labelled\nclean-replace\n", hash: labelled.hash });
    assert.deepEqual(inherited.read(["facts/labelled.md"]).body.notes[0].sources, ["home", "web"], "replace keeps existing source labels");

    const symlinkRoot = path.join(process.env.JARVIS_TEST_ROOT, "memory-link-root-" + ++serial);
    const realParent = path.join(symlinkRoot, "real");
    const linkParent = path.join(symlinkRoot, "link");
    fs.mkdirSync(realParent, { recursive: true });
    fs.symlinkSync(realParent, linkParent);
    const linkedHome = path.join(linkParent, "home");
    Home.layout(linkedHome);
    const linkedState = path.join(symlinkRoot, "state");
    fs.mkdirSync(linkedState);
    const linked = attach(Memory, linkedHome, linkedState);
    assert.equal(linked.writeCall("memory.propose", { id: "facts/symlink-parent.md", text: "symlink-parent-token" }).outcome, "completed");
    assert.equal(linked.search({ query: "symlink-parent-token" }).body.results[0].id, "facts/symlink-parent.md");

    const guarded = make();
    const outside = path.join(guarded.root, "outside.md");
    fs.writeFileSync(outside, "outside-safe\n");
    fs.symlinkSync(outside, path.join(guarded.folder, "memory/link.md"));
    const refusedLink = guarded.writeCall("memory.propose", { id: "link.md", text: "outside changed\n" });
    assert.deepEqual([refusedLink.outcome, refusedLink.content], ["failed", "memory-propose:link"]);
    assert.equal(fs.readFileSync(outside, "utf8"), "outside-safe\n");
    const secret = guarded.writeCall("memory.propose", { id: "facts/secret.md", text: "token sk-ant-synthetic-secret-token-value" });
    assert.deepEqual([secret.outcome, secret.content], ["failed", "memory-propose:secret"]);
    assert.deepEqual(guarded.writeCall("memory.propose", { id: "sk-ant-synthetic-secret-token-value.md", text: "title" }).content,
        "memory-propose:secret");
    assert.equal(fs.existsSync(path.join(guarded.folder, "memory/facts/secret.md")), false);

    for (const loader of [() => { throw new Error("missing"); }, () => ({ DatabaseSync: class {
        exec(sql) { if (String(sql).includes("fts5")) throw new Error("no fts"); }
        close() {}
    } })]) {
        const refused = Memory.install({ router: { register() { throw new Error("registered"); } },
            directory: path.join(process.env.JARVIS_TEST_ROOT, "sqlite-" + ++serial), home: () => w.folder, sqlite: loader, log() {} });
        assert.deepEqual(refused, { kind: "refused", cause: "memory=sqlite" });
    }
    const bad = make();
    bad.write("facts/good.md", "# Good\nhealthy-token\n");
    bad.write("latin1.md", Buffer.from([0x63, 0x61, 0x66, 0xe9, 0x0a]));
    const good = bad.search({ query: "healthy-token" });
    assert.deepEqual(good.body.results.map(row => row.id), ["facts/good.md"], "one bad note does not stop the index");
    assert.equal(bad.logs.some(line => /^jarvis: memory=note-text id=latin1\.md$/.test(line)), true, "bad note is logged by id");

    function routerWorld(RouterImpl = Router) {
        let transcript, at = 0;
        const audit = Audit.create({ state: path.join(process.env.JARVIS_TEST_ROOT, "audit-" + ++serial), now: () => Date.UTC(2026, 9, 1) });
        const ports = { ...unavailable(), mute: { store() {} }, transcript() {},
            capture: { open: (e, done) => done(), close: (e, done) => done(), collect: (e, done) => { transcript = done; } },
            brain: { send() {}, cancel: (e, done) => done(), close() {}, outcome: value => results.push(value) } };
        const runner = new SessionRunner(Session, ports, { now: () => at, set: fn => ({ fn }), clear() {} }, () => {});
        const results = [];
        const router = RouterImpl.create({ session: Session, state: () => runner.state, dispatch: e => runner.dispatch(e),
            audit, context: () => ({ profile: "standard", locked: false, denied: Denied.create(fixtures.roots) }),
            result: value => results.push(value) });
        Object.assign(ports, router.ports);
        router.register("files", { commands: [], timeoutMs: 1000, cancellable: false,
            start(call, done) { done({ outcome: "completed", content: "wrote" }); } });
        runner.dispatch({ type: "snapshot", locked: false, engine: "chained", configured: true, settings: {} });
        runner.dispatch({ type: "indicator", shown: true });
        runner.dispatch({ type: "talk-down" }); transcript("final", "fixture user");
        const turn = () => ({ gen: runner.state.gen, op: runner.state.turn.op });
        const m = make();
        m.write("facts/web.md", "---\ntitle: Web memory\nsources: [web]\n---\n# Web memory\nweb-taint\n");
        let offeredHome = null;
        const memoryInstall = Memory.install({ router, directory: path.join(m.state, "router-memory"), home: () => offeredHome, log() {} });
        assert.equal(router.offer().some(row => row.id.startsWith("memory.")), false, "no home means no memory row");
        offeredHome = m.folder;
        assert.equal(router.offer().some(row => row.id === "memory.read"), true, "a chosen home offers memory read");
        offeredHome = null;
        assert.equal(router.route({ kind: "tool-call", id: "lost", tool: "memory.read", arguments: { ids: ["facts/web.md"] } }, turn()).reason,
            "executor-unavailable", "a home lost after offer is refused before reading");
        offeredHome = m.folder;
        router.route({ kind: "tool-call", id: "mem", tool: "memory.read", arguments: { ids: ["facts/web.md"] } }, turn());
        const item = results.at(-1).results[0].item;
        assert.deepEqual(item.labels, ["home", "web"], "the router keeps recorded labels");
        assert.equal(router.route({ kind: "tool-call", id: "write", tool: "files.write",
            arguments: { path: path.join(fixtures.project, "new"), text: "x" } }, turn()).kind, "held", "web-labelled memory taints the turn");
        assert.equal(item.content.includes("web-taint"), true);
        runner.dispatch({ type: "cancel" });
        runner.dispatch({ type: "talk-down" }); transcript("final", "fixture user");
        router.route({ kind: "tool-call", id: "remember", tool: "memory.propose",
            arguments: { id: "facts/routed.md", text: "# Routed\nrouter-origin-token\n" } }, turn());
        assert.deepEqual(memoryInstall.pending().map(row => [row.target, row.labels]),
            [["facts/routed.md", ["home", "web"]]], "router passes host origin labels to memory writes");
        assert.deepEqual(m.search({ query: "router-origin-token" }).body.results, [], "tainted router write is quarantined");
        router.register("windows", { commands: ["hyprctl"], timeoutMs: 1000, cancellable: false,
            start(call, done) { done({ outcome: "completed", content: "bad labels", labels: ["web"] }); } });
        runner.dispatch({ type: "cancel" });
        runner.dispatch({ type: "talk-down" }); transcript("final", "fixture user");
        assert.throws(() => router.route({ kind: "tool-call", id: "bad", tool: "windows.list", arguments: {} }, turn()),
            { message: "jarvis: router=labels" });
        audit.close();
    }
    routerWorld();

    let controls = 0;
    const checkInbox = logic => {
        const x = make(logic); populate(x);
        assert.deepEqual(x.search({ query: "needle-inbox" }).body.results, []);
        assert.equal(x.read(["inbox/pending.md"]).answer.outcome, "failed");
    };
    mutant(homeFile, "memory-inbox-skip", [
        ['if (prefix === "" && entry.name === "inbox") continue;', ""],
        ['    if (!Tools.memoryNote(entry)) fail("absent");\n', ""],
        ["if (!stat.isFile() || !entry.name.endsWith(\".md\") || !Tools.memoryNote(id)) continue;", "if (!stat.isFile() || !entry.name.endsWith(\".md\")) continue;"]
    ], null, checkInbox, "Memory.js");
    controls++;
    mutant(memoryFile, "memory-hash-compare", "prior !== undefined && prior.hash === read.hash", "prior !== undefined", logic => {
        const x = make(logic); x.write("facts/a.md", "# A\noldterm\n"); assert.deepEqual(x.search({ query: "oldterm" }).body.results.map(row => row.id), ["facts/a.md"]);
        const file = path.join(x.folder, "memory/facts/a.md");
        const stat = fs.statSync(file);
        x.installed.close(); x.write("facts/a.md", "# A\nnewterm\n"); fs.truncateSync(file, stat.size); fs.utimesSync(file, stat.atime, stat.mtime); Object.assign(x, attach(logic, x.folder, x.state));
        assert.deepEqual(x.search({ query: "newterm" }).body.results.map(row => row.id), ["facts/a.md"]);
    });
    controls++;
    mutant(memoryFile, "memory-stat-reconcile", "const database = reconcileFor(\"memory-search:\", done);",
        "const database = open();", logic => {
            const x = make(logic); x.write("facts/a.md", "# A\noldterm\n"); assert.deepEqual(x.search({ query: "oldterm" }).body.results.map(row => row.id), ["facts/a.md"]);
            x.write("facts/a.md", "# A\nnewterm\n");
            assert.deepEqual(x.search({ query: "newterm" }).body.results.map(row => row.id), ["facts/a.md"]);
        });
    controls++;
    mutant(memoryFile, "memory-offer-home", "available: () => home() !== null", "available: () => true", logic => {
        const folder = path.join(process.env.JARVIS_TEST_ROOT, "offer-" + ++serial);
        const state = path.join(process.env.JARVIS_TEST_ROOT, "offer-state-" + serial);
        fs.mkdirSync(folder, { recursive: true }); fs.mkdirSync(state, { recursive: true });
        let transcript;
        const audit = Audit.create({ state: path.join(state, "audit"), now: () => Date.UTC(2026, 9, 1) });
        const ports = { ...unavailable(), mute: { store() {} }, transcript() {},
            capture: { open: (e, done) => done(), close: (e, done) => done(), collect: (e, done) => { transcript = done; } },
            brain: { send() {}, cancel: (e, done) => done(), close() {}, outcome() {} } };
        const runner = new SessionRunner(Session, ports, { now: () => 0, set: fn => ({ fn }), clear() {} }, () => {});
        const router = Router.create({ session: Session, state: () => runner.state, dispatch: e => runner.dispatch(e),
            audit, context: () => ({ profile: "standard", locked: false, denied: Denied.create(fixtures.roots) }), result() {} });
        Object.assign(ports, router.ports);
        logic.install({ router, directory: path.join(state, "memory"), home: () => null, log() {} });
        runner.dispatch({ type: "snapshot", locked: false, engine: "chained", configured: true, settings: {} });
        runner.dispatch({ type: "indicator", shown: true });
        runner.dispatch({ type: "talk-down" }); transcript("final", "fixture");
        assert.equal(router.offer().some(row => row.id.startsWith("memory.")), false);
        audit.close();
    });
    controls++;
    mutant(memoryFile, "memory-quarantine-taint", "if (origin?.tainted === true) {", "if (false && origin?.tainted === true) {", logic => {
        const x = make(logic);
        x.writeCall("memory.propose", { id: "facts/web.md", text: "# Web\nweb-pending-token\n" },
            { labels: ["home", "web"], tainted: true });
        assert.deepEqual(x.search({ query: "web-pending-token" }).body.results, [], "tainted proposal must wait outside the index");
    });
    controls++;
    mutant(memoryFile, "memory-replace-conflict", [
        ["if (hashText(current) !== expectedHash) throw new Error(\"jarvis: memory=conflict\");",
            "if (false) throw new Error(\"jarvis: memory=conflict\");"],
        ["if (hashText(current) !== expectedHash) {\n                throw new Error(\"jarvis: memory=conflict\");\n            }",
            "if (false) {\n                throw new Error(\"jarvis: memory=conflict\");\n            }"]
    ], null, logic => {
            const x = make(logic);
            x.writeCall("memory.propose", { id: "facts/a.md", text: "# A\nold\n" });
            const note = x.read(["facts/a.md"]).body.notes[0];
            fs.writeFileSync(path.join(x.folder, "memory/facts/a.md"), "# A\nuser\n");
            const answer = x.writeCall("memory.replace", { id: "facts/a.md", text: "# A\nmodel\n", hash: note.hash });
            assert.deepEqual([answer.outcome, answer.content], ["failed", "memory-replace:conflict"]);
        });
    controls++;
    mutant(memoryFile, "memory-secret-refusal", [
        ['if (Redact.secret(id) || Redact.secret(text)) {\n            throw new Error("jarvis: memory=secret");\n        }', 'if (false) {\n            throw new Error("jarvis: memory=secret");\n        }'],
        ['if (Redact.secret(id) || Redact.secret(text)) throw new Error("jarvis: memory=secret");', 'if (false) throw new Error("jarvis: memory=secret");']
    ], null, logic => {
        const x = make(logic);
        const answer = x.writeCall("memory.propose", { id: "facts/secret.md", text: "token sk-ant-synthetic-secret-token-value" });
        assert.deepEqual([answer.outcome, answer.content], ["failed", "memory-propose:secret"]);
    });
    controls++;
    mutant(memoryFile, "memory-symlink-target", [
        ['function atomicWrite(parent, name, text, { replace }) {\n        if (entryKind(parent, name) === "link") throw new Error("jarvis: memory=link");',
            'function atomicWrite(parent, name, text, { replace }) {\n        if (false && entryKind(parent, name) === "link") throw new Error("jarvis: memory=link");'],
        ['const currentKind = withParent(id, true, (parent, name) => entryKind(parent, name));\n        if (!replace && currentKind !== "absent") throw new Error(currentKind === "link" ? "jarvis: memory=link" : "jarvis: memory=exists");\n        let writeLabels = labels;',
            'const currentKind = withParent(id, true, (parent, name) => entryKind(parent, name));\n        if (!replace && currentKind !== "absent" && currentKind !== "link") throw new Error(currentKind === "link" ? "jarvis: memory=link" : "jarvis: memory=exists");\n        let writeLabels = labels;'],
        ['if (!replace && currentKind !== "absent") throw new Error(currentKind === "link" ? "jarvis: memory=link" : "jarvis: memory=exists");',
            'if (!replace && currentKind !== "absent" && currentKind !== "link") throw new Error(currentKind === "link" ? "jarvis: memory=link" : "jarvis: memory=exists");']
    ], null, logic => {
        const x = make(logic);
        const outside = path.join(x.root, "outside.md");
        fs.writeFileSync(outside, "safe\n");
        fs.symlinkSync(outside, path.join(x.folder, "memory/link.md"));
        const answer = x.writeCall("memory.propose", { id: "link.md", text: "changed\n" });
        assert.deepEqual([answer.outcome, answer.content], ["failed", "memory-propose:link"]);
        assert.equal(fs.readFileSync(outside, "utf8"), "safe\n");
    });
    controls++;
    mutant(memoryFile, "memory-edited-receipt", "return record !== null && record.note === id && record.approvedHash !== hashText(text);",
        "return false;", logic => {
            const x = make(logic);
            x.writeCall("memory.propose", { id: "facts/a.md", text: "# A\nold\n" });
            fs.writeFileSync(path.join(x.folder, "memory/facts/a.md"), "# A\nuser\n");
            assert.equal(x.read(["facts/a.md"]).body.notes[0].edited, true);
        });
    controls++;
    mutant(memoryFile, "memory-crlf-raw-hash", "const currentHash = hashText(text);", "const currentHash = hashText(parsed.text);", logic => {
        const x = make(logic);
        x.write("facts/crlf.md", "# CRLF\r\nold\r\n");
        const note = x.read(["facts/crlf.md"]).body.notes[0];
        assert.equal(note.hash, sha("# CRLF\r\nold\r\n"));
    });
    controls++;
    mutant(memoryFile, "memory-remove-inbox-receipt",
        'removeInbox(id);\n        removeReceipt("inbox/" + id);\n        publishInbox();\n        return { kind: "confirmed", target: record.target };',
        'removeInbox(id);\n        void id;\n        publishInbox();\n        return { kind: "confirmed", target: record.target };', logic => {
        const x = make(logic);
        x.writeCall("memory.propose", { id: "facts/a.md", text: "a" }, { labels: ["home", "web"], tainted: true });
        const row = x.installed.pending()[0];
        x.installed.confirm(row.id, row.hash);
        assert.equal(receipts(x.state).some(receipt => receipt.inbox === row.id), false);
    });
    controls++;
    mutant(memoryFile, "memory-replace-keeps-labels", "writeLabels = uniqueLabels([...parseNote(id, current).labels, ...labels]);",
        "writeLabels = labels;", logic => {
            const x = make(logic);
            x.write("facts/a.md", "---\nsources: [web]\n---\n# A\nold\n");
            const note = x.read(["facts/a.md"]).body.notes[0];
            x.writeCall("memory.replace", { id: "facts/a.md", text: "# A\nnew\n", hash: note.hash });
            assert.deepEqual(x.read(["facts/a.md"]).body.notes[0].sources, ["home", "web"]);
        });
    controls++;
    mutant(memoryFile, "memory-bootstrap-target", [
        ['if (id === "MEMORY.md") throw new Error("jarvis: memory=bootstrap");', 'if (false) throw new Error("jarvis: memory=bootstrap");'],
        ['if (id === "MEMORY.md") {\n            throw new Error("jarvis: memory=bootstrap");\n        }',
            'if (false) {\n            throw new Error("jarvis: memory=bootstrap");\n        }']
    ], null, logic => {
        const x = make(logic);
        assert.equal(x.writeCall("memory.propose", { id: "MEMORY.md", text: "bootstrap" }).content, "memory-propose:bootstrap");
    });
    controls++;
    mutant(memoryFile, "memory-pending-count-bound", "kept.length === 64", "false", logic => {
        const x = make(logic);
        for (let n = 0; n < 70; n++)
            x.writeCall("memory.propose", { id: "many/note-" + n + ".md", text: "x" }, { labels: ["home", "web"], tainted: true });
        assert.equal(x.installed.pending().length, 64);
    });
    controls++;
    mutant(memoryFile, "memory-pending-result-hidden", 'done({ outcome: "completed", content: JSON.stringify({ status: "pending", id: args.id, kind }) });',
        'done({ outcome: "completed", content: JSON.stringify({ status: "pending", id: args.id, kind, inbox: "leaked" }) });',
        logic => {
            const x = make(logic);
            const answer = x.writeCall("memory.propose", { id: "facts/a.md", text: "x" }, { labels: ["home", "web"], tainted: true });
            assert.deepEqual(Object.keys(JSON.parse(answer.content)).sort(), ["id", "kind", "status"]);
        });
    controls++;
    mutant(memoryFile, "memory-secret-id-refusal", [
        ['if (Redact.secret(id) || Redact.secret(text)) {\n            throw new Error("jarvis: memory=secret");\n        }',
            'if (Redact.secret(text)) {\n            throw new Error("jarvis: memory=secret");\n        }'],
        ['if (Redact.secret(id) || Redact.secret(text)) throw new Error("jarvis: memory=secret");',
            'if (Redact.secret(text)) throw new Error("jarvis: memory=secret");']
    ], null, logic => {
        const x = make(logic);
        assert.equal(x.writeCall("memory.propose", { id: "sk-ant-synthetic-secret-token-value.md", text: "title" }).content,
            "memory-propose:secret");
    });
    controls++;
    mutant(routerFile, "memory-origin-labels",
        "conversationLabels.add(label);",
        "void label;", routerWorld);
    controls++;
    console.log("test-jarvis-memory: ok controls=" + controls);
});
