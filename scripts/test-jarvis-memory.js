#!/usr/bin/env node
// Jarvis memory search index: Memory.js owns the disposable SQLite FTS5 index,
// reads notes only through Home.js, and returns Policy labels from note
// sources. The scratch world is under JARVIS_TEST_ROOT.
"use strict";
const { assert, fs, path, tree, world, seed, mutant } = require("./fixtures/jarvis/policy.js");
const { load } = require("../bin/lib/qml-library.js");
const backend = path.join(tree, "shell/plugins/vgs.jarvis/backend");
const memoryFile = path.join(backend, "Memory.js");
const homeFile = path.join(backend, "Home.js");

world(() => {
    const Memory = require(memoryFile);
    const Tools = require(path.join(backend, "Tools.js"));
    const Home = require(path.join(backend, "Home.js"));
    const Router = require(path.join(backend, "ToolRouter.js"));
    const Audit = require(path.join(backend, "Audit.js"));
    const Denied = require(path.join(backend, "Denied.js"));
    const Policy = require(path.join(backend, "Policy.js"));
    const Session = load(path.join(tree, "shell/plugins/vgs.jarvis/Session.js"));
    const { SessionRunner, unavailable } = require(path.join(backend, "session-runner.js"));
    const fixtures = seed();
    let serial = 0;

    function attach(logic, folder, state, options = {}) {
        const router = { record: null, register(id, executor) { assert.equal(id, "memory"); this.record = executor; } };
        const logs = [];
        const installed = logic.install({ router, directory: path.join(state, "memory"), home: () => folder,
            log: line => logs.push(line), ...options });
        assert.equal(installed.kind, "installed");
        const call = (id, args) => {
            let answer;
            router.record.start({ id, args }, value => { answer = value; });
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
        return { installed, search, read, logs };
    }

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

    function routerWorld() {
        let transcript, at = 0;
        const audit = Audit.create({ state: path.join(process.env.JARVIS_TEST_ROOT, "audit-" + ++serial), now: () => Date.UTC(2026, 9, 1) });
        const ports = { ...unavailable(), mute: { store() {} }, transcript() {},
            capture: { open: (e, done) => done(), close: (e, done) => done(), collect: (e, done) => { transcript = done; } },
            brain: { send() {}, cancel: (e, done) => done(), close() {}, outcome: value => results.push(value) } };
        const runner = new SessionRunner(Session, ports, { now: () => at, set: fn => ({ fn }), clear() {} }, () => {});
        const results = [];
        const router = Router.create({ session: Session, state: () => runner.state, dispatch: e => runner.dispatch(e),
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
        Memory.install({ router, directory: path.join(m.state, "router-memory"), home: () => offeredHome, log() {} });
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
    console.log("test-jarvis-memory: ok controls=" + controls);
});
