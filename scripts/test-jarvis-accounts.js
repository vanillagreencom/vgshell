#!/usr/bin/env node
"use strict";
const { assert, fs, path, cp, tree, environment, world, mutant } = require("./fixtures/jarvis/accounts-world.js");
const plugin = path.join(tree, "shell/plugins/vgs.jarvis");
const privateValue = "fixture-secret-private";

world(async () => {
    const env = environment();
    const directory = path.join(env.XDG_STATE_HOME, "vgshell/jarvis");
    const { Accounts } = require(path.join(plugin, "backend/Accounts.js"));
    const { Secrets, ownReference } = require(path.join(plugin, "backend/Secrets.js"));
    const { PROVIDERS, keyPresence, helperFailure, feedDiagnostic, probeFailure } = require(path.join(plugin, "AccountProviders.js"));
    const mode = (name, value) => fs.writeFileSync(path.join(env.XDG_STATE_HOME, name + "-mode"), value);
    const calls = name => fs.existsSync(path.join(env.XDG_STATE_HOME, name))
        ? fs.readFileSync(path.join(env.XDG_STATE_HOME, name), "utf8").trim().split("\n").filter(Boolean).map(JSON.parse) : [];
    const safe = value => assert.equal(JSON.stringify(value).includes(privateValue), false, "no secret in metadata, status or diagnosis");
    const markerReads = [];
    const markerChecks = [];
    let markerOrder = null;
    const originalStat = fs.lstatSync;
    fs.lstatSync = function (file, ...args) {
        if (typeof file === "string" && [".credentials.json", "auth.json"].includes(path.basename(file))) {
            markerChecks.push(file);
            if (markerOrder !== null) {
                const count = calls("cli-calls").length;
                assert.ok(count > markerOrder.value, "each marker check follows its candidate's vendor account command");
                markerOrder.value = count;
            }
        }
        return originalStat.call(fs, file, ...args);
    };
    for (const method of ["readFileSync", "openSync", "createReadStream"]) {
        const original = fs[method];
        fs[method] = function (file, ...args) {
            if (typeof file === "string" && [".credentials.json", "auth.json"].includes(path.basename(file)))
                markerReads.push([method, file]);
            return original.call(fs, file, ...args);
        };
    }
    const seed = (root, name, marker) => {
        const folder = path.join(root, name);
        fs.mkdirSync(folder, { recursive: true });
        if (marker) fs.writeFileSync(path.join(folder, marker), privateValue, { mode: 0o000 });
        return folder;
    };
    const defaultClaude = seed(env.HOME, ".claude", ".credentials.json");
    const nestedClaude = seed(env.XDG_CONFIG_HOME, ".claude-team", ".credentials.json");
    const unicodeClaude = seed(env.XDG_CONFIG_HOME, ".claude-équipe", ".credentials.json");
    const nestedCodex = seed(env.XDG_DATA_HOME, ".codex-business", "auth.json");
    // Folder names and the labels the documented rule gives them.
    const named = [[".5claude", "5"], [".claude-work", "work"], [".2codex", "2"]]
        .map(([name, label]) => [seed(env.HOME, name, name.includes("codex") ? "auth.json" : ".credentials.json"), label]);
    const hand = seed(env.HOME, "hand-added", ".credentials.json");
    const explicit = seed(env.HOME, "explicit", "auth.json");
    // An account folder one level down, and names the rule leaves out.
    seed(env.HOME, "projects/.claude", ".credentials.json");
    for (const name of [".claudia", ".abcdefghiclaude", "claude"]) seed(env.HOME, name, ".credentials.json");
    const linked = seed(process.env.JARVIS_TEST_ROOT, "link-target", ".credentials.json");
    fs.symlinkSync(linked, path.join(env.HOME, ".claude-link"));
    fs.symlinkSync(linked, path.join(env.XDG_DATA_HOME, "link-parent"));
    const store = new Accounts(directory, { ...env, CODEX_HOME: explicit,
        OPENAI_API_KEY: privateValue, VGSHELL_RUNNER_PID: "123" });
    store.add({ provider: "claude", directory: hand, label: "hand" });
    assert.equal(fs.statSync(store.file).mode & 0o777, 0o600);
    let cases = 0, controls = 0;
    const diagnosticCases = [
        ["jarvis-accounts: directory=link\n", "jarvis-accounts: directory=link"],
        ["jarvis-accounts: added=json\n", "jarvis-accounts: added=json"],
        ["jarvis-keys: busctl=missing\n", "jarvis-keys: busctl=missing"],
        ["jarvis-accounts: discovery=" + privateValue, ""],
        ["jarvis-accounts: added=json\n" + privateValue, ""],
        ["node: " + privateValue, ""],
        ["constructor: name=object", ""],
        ["jarvis-accounts: constructor=object", ""]
    ];
    for (const [input, expected] of diagnosticCases) {
        assert.equal(helperFailure(input), expected);
        cases++;
    }
    const collected = text => feedDiagnostic({ kind: "collected", text: "" }, text);
    const completionCases = [
        [{ kind: "starting" }, "", "jarvis-accounts: process=start-failed"],
        [{ kind: "crashed" }, privateValue, "jarvis-accounts: process=crashed"],
        [{ kind: "exited", code: 0 }, privateValue, "jarvis-accounts: output=invalid"],
        [{ kind: "exited", code: 1 }, "jarvis-accounts: added=json\n", "jarvis-accounts: added=json"],
        [{ kind: "exited", code: 1 }, privateValue, "jarvis-accounts: process=failed"]
    ];
    for (const [completion, text, expected] of completionCases) {
        const value = probeFailure(completion, collected(text));
        assert.equal(value, expected);
        safe(value);
        cases++;
    }
    let bounded = collected("x".repeat(256));
    assert.equal(bounded.kind, "collected");
    bounded = feedDiagnostic(bounded, "x");
    assert.deepEqual(bounded, { kind: "oversize" });
    assert.equal(probeFailure({ kind: "exited", code: 1 }, bounded), "jarvis-accounts: diagnostic=oversize");
    await mutant("AccountProviders.js", "safe-diagnostic-key",
        'if (!Array.isArray(codes) || codes.indexOf(match[3]) === -1) return "";',
        'if (false) return "";', folder => {
            const api = require(path.join(folder, "AccountProviders.js"));
            assert.equal(api.helperFailure("jarvis-accounts: discovery=" + privateValue), "");
        });
    controls++;
    await mutant("AccountProviders.js", "bounded-diagnostic", "if (text.length > MAX_DIAGNOSTIC_CHARS)",
        "if (false)", folder => {
            const api = require(path.join(folder, "AccountProviders.js"));
            assert.deepEqual(api.feedDiagnostic({ kind: "collected", text: "" }, "x".repeat(257)), { kind: "oversize" });
        });
    controls++;
    await mutant("AccountProviders.js", "preserved-diagnostic-cause",
        'return helperFailure(diagnostic.text) || "jarvis-accounts: process=failed";',
        'return "jarvis-accounts: process=failed";', folder => {
            const api = require(path.join(folder, "AccountProviders.js"));
            assert.equal(api.probeFailure({ kind: "exited", code: 1 }, collected("jarvis-accounts: added=json\n")),
                "jarvis-accounts: added=json");
        });
    controls++;

    function discovery(judge) {
        const before = markerReads.length;
        markerOrder = { value: calls("cli-calls").length };
        let rows;
        try { rows = judge.discover(); } finally { markerOrder = null; }
        assert.equal(markerReads.length, before, "no marker content API is called, even if mode 000 can be bypassed");
        assert.ok(rows.some(item => item.source.directory === nestedClaude && item.label === "team"), "config home Claude");
        assert.ok(rows.some(item => item.source.directory === unicodeClaude && item.label === "équipe"), "Unicode directory");
        assert.ok(rows.some(item => item.source.directory === nestedCodex && item.label === "business"), "data home Codex");
        for (const [folder, label] of named)
            assert.ok(rows.some(item => item.source.directory === folder && item.label === label), "named folder " + folder);
        assert.ok(rows.some(item => item.source.directory === hand && item.label === "hand"), "manual directory");
        assert.ok(rows.some(item => item.source.directory === explicit), "explicit directory");
        assert.ok(rows.some(item => item.source.directory === defaultClaude), "mode 000 marker");
        assert.equal(rows.find(item => item.source.directory === defaultClaude).marker, "present");
        assert.equal(rows.some(item => item.source.directory?.startsWith(path.join(env.HOME, "projects"))), false, "no descent");
        assert.equal(rows.some(item => /\/(\.claudia|\.abcdefghiclaude|claude)$/.test(item.source.directory ?? "")), false,
            "a name outside the rule");
        assert.equal(rows.some(item => item.source.directory?.includes("link")), false, "links excluded");
        assert.equal(rows.find(item => item.source.directory === nestedClaude).state.kind, "signed-in");
        assert.equal(rows.find(item => item.source.directory === nestedClaude).identity.kind, "match", "a folder name names no identity");
        assert.ok(rows.some(item => item.source.kind === "variable" && item.provider === "openai"));
        assert.ok(rows.some(item => item.source.kind === "local" && item.provider === "ollama"));
        assert.equal(rows.some(item => item.state.kind === "verified"), false, "discovery is never verification");
        safe(judge.status());
        return rows;
    }
    let rows = discovery(store);
    for (const call of [...calls("cli-calls"), ...calls("port-calls")]) {
        assert.equal(call.env.OPENAI_API_KEY, undefined);
        assert.equal(call.env.VGSHELL_RUNNER_PID, undefined);
        assert.ok(["auth,status", "login,status", "-H,-ltn"].includes(call.args.join(",")));
        safe(call);
    }
    assert.equal(calls("secret-calls").length, 0);
    cases++;

    for (const [name, value, expected] of [
        ["claude", "found", "found"], ["claude", "failed", "unavailable"], ["claude", "junk", "unavailable"],
        ["codex", "api", "signed-in"], ["codex", "found", "found"], ["codex", "failed", "unavailable"], ["codex", "junk", "unavailable"]
    ]) {
        mode(name, value);
        const item = store.discover().find(row => row.provider === name && row.source.directory);
        assert.equal(item.state.kind, expected);
        safe(store.status());
        mode(name, "signed-in");
        cases++;
    }

    const references = new Secrets(directory, env);
    for (const [selected, reason, needle, replacement] of [
        ["too-many", /items=limit-or-duplicate/, "paths.length > MAX_REFERENCES", "false"],
        ["duplicate", /items=limit-or-duplicate/, "new Set(paths).size !== paths.length", "false"],
        ["property-type", /items=reply/, "reply.type !== type", "false"],
        ["property-extra", /items=reply/, "reply.data.length !== 1", "false"],
        ["property-object", /items=reply/, "reply.type !== type || !Array.isArray(reply.data)", "reply.type !== type || false"],
        ["empty-label", /items=label/, 'fail("items=label");', "void 0;"]
    ]) {
        mode("bus", selected);
        const assertion = Store => assert.throws(() => new Store(directory, env).items(), reason);
        assertion(Secrets);
        await mutant("backend/Secrets.js", "items-" + selected, needle, replacement, folder =>
            assertion(require(path.join(folder, "backend/Secrets.js")).Secrets));
        controls++;
        cases++;
    }
    mode("bus", "unicode-label");
    assert.ok(references.items().some(item => item.label === "Other tool API clé"));
    mode("bus", "present");
    for (const value of ["present", "locked", "absent", "failed", "junk"]) {
        mode("bus", value);
        const ref = { provider: "openai", account: "other", origin: "https://api.openai.com",
            attributes: { application: "other-tool", id: "api-key" } };
        references.remember(ref);
        const item = store.discover().find(row => row.source.kind === "keyring");
        assert.equal(item.state.kind, value === "present" ? "found" : value === "locked" ? "locked" : "unavailable");
        assert.equal(store.status().brains.some(row => row.value === item.id), value === "present");
        safe(store.status());
        cases++;
    }
    mode("bus", "present");
    const items = store.keyItems();
    assert.deepEqual(items.map(item => item.label), ["Other tool API key"]);
    store.remember(items[0].path, "anthropic", "chosen label");
    assert.deepEqual(references.references()[1].attributes, { application: "other-tool", id: "api-key" });
    const unicodeRef = { provider: "custom-tool", account: "clé", origin: "https://custom.invalid",
        attributes: { application: "other-tool", user: "développeur" } };
    references.remember(unicodeRef);
    assert.deepEqual(references.references()[2], unicodeRef);
    const ownedAlias = ownReference("anthropic", "Claude Code", "https://api.anthropic.com");
    references.remember(ownedAlias);
    assert.equal(store.discover().find(item => item.source.reference?.account === "Claude Code").state.kind, "found");
    const stableReference = Judge => {
        const original = references.references().find(ref => ref.account === "other");
        const before = new Judge(directory, env).discover().find(item => item.source.reference?.account === "other").id;
        try {
            references.remember({ ...original, attributes: Object.fromEntries(Object.entries(original.attributes).reverse()) });
            const after = new Judge(directory, env).discover().find(item => item.source.reference?.account === "other").id;
            assert.equal(after, before, "dictionary order is not account identity");
        } finally { references.remember(original); }
    };
    stableReference(Accounts);
    await mutant("backend/Accounts.js", "stable-reference-id",
        'Object.fromEntries(Object.entries(value).sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0))',
        "value", folder => stableReference(require(path.join(folder, "backend/Accounts.js")).Accounts));
    controls++;
    cases++;
    const unknown = store.discover().find(item => item.provider === "custom-tool");
    assert.deepEqual(unknown.state, { kind: "unavailable", reason: "provider-unsupported" });
    assert.equal(store.status().brains.some(choice => choice.value === unknown.id), false);
    let unknownRequests = 0;
    await assert.rejects(() => store.verify(unknown.id, "user", async () => {
        unknownRequests++; return { kind: "inference", text: "OK" };
    }), /verify=provider-unsupported/);
    assert.equal(unknownRequests, 0);
    await mutant("backend/Accounts.js", "unknown-provider-verify",
        'fail("verify=provider-unsupported");',
        'void 0;', async folder => {
            const judge = new (require(path.join(folder, "backend/Accounts.js")).Accounts)(directory, env);
            const item = judge.discover().find(row => row.provider === "custom-tool");
            await assert.rejects(() => judge.verify(item.id, "user", async () => ({ kind: "inference", text: "OK" })),
                /verify=provider-unsupported/);
        });
    controls++;
    cases++;
    references.remember(ownReference("elevenlabs", "voice", "https://api.elevenlabs.io"));
    // The daemon resolves a saved choice without discovery's vendor commands.
    const resolution = Judge => {
        const judge = new Judge(directory, env);
        const found = store.discover();
        const before = [calls("cli-calls").length, calls("port-calls").length, calls("secret-calls").length];
        const keyring = found.find(item => item.source.reference?.account === "chosen label");
        assert.deepEqual(judge.resolve(keyring.id), { id: keyring.id, provider: "anthropic", label: "chosen label",
            source: keyring.source, model: "claude-haiku-4-5" });
        const local = store.account(PROVIDERS.find(row => row.id === "ollama"), "local", { kind: "found" },
            { kind: "local", origin: "http://127.0.0.1:11434" });
        assert.deepEqual(judge.resolve(local.id), { id: local.id, provider: "ollama", label: "local",
            source: local.source, model: "" });
        const speech = found.find(item => item.provider === "elevenlabs");
        assert.ok(speech, "a speech-only key reference exists");
        // A Claude Code folder's program is the brain, with its own default model.
        const claude = found.find(item => item.source.kind === "cli" && item.provider === "claude");
        assert.deepEqual(judge.resolve(claude.id), { id: claude.id, provider: "claude", label: claude.label,
            source: { kind: "cli", directory: claude.source.directory }, model: "" });
        for (const other of [unknown.id, speech.id, "", "keyring:0"]) {
            let value;
            assert.doesNotThrow(() => { value = judge.resolve(other); }, "resolution judges every saved reference");
            assert.equal(value, null, "a speech-only, unsupported or unknown id selects nothing");
        }
        assert.deepEqual([calls("cli-calls").length, calls("port-calls").length, calls("secret-calls").length], before,
            "resolution runs no vendor command, port read or key lookup");
    };
    resolution(Accounts);
    await mutant("backend/Accounts.js", "resolve-unsupported", 'if ((source.kind === "keyring" && !keyProvider(row)) || !brainRow(row)) return null;', "",
        folder => resolution(require(path.join(folder, "backend/Accounts.js")).Accounts));
    controls++;
    cases++;
    safe(fs.readFileSync(references.file, "utf8"));
    assert.throws(() => store.remember("/org/freedesktop/secrets/collection/test/cli", "openai", "login"), /reference=item-unavailable/);
    assert.throws(() => store.remember(items[0].path, "claude", "login"), /reference=provider/);
    assert.equal(calls("secret-calls").length, 0, "picker never looks up a secret");
    for (const call of calls("bus-calls")) {
        assert.equal(call.args.some(arg => /GetSecret|Unlock|search/.test(arg)), false);
        safe(call);
    }
    cases++;

    rows = store.discover();
    const chosen = rows.find(row => row.source.directory === nestedClaude).id;
    let inferenceCalls = 0;
    const request = async account => { inferenceCalls++; assert.equal(account.id, chosen); return { kind: "inference", text: "OK" }; };
    assert.equal(inferenceCalls, 0);
    await assert.rejects(() => store.verify(chosen, "automatic", request), /explicit-user-required/);
    assert.equal(inferenceCalls, 0);
    // The Claude route starts the harness; this stand-in answers only auth status.
    assert.deepEqual(await store.verify(chosen, "user"), { kind: "unavailable", reason: "harness-exit" });
    assert.ok(calls("cli-calls").some(call => call.args[0] === "-p" && call.env.CLAUDE_CONFIG_DIR === nestedClaude));
    assert.equal(inferenceCalls, 0);
    assert.deepEqual(await store.verify(chosen, "user", request), { kind: "verified" });
    assert.equal(inferenceCalls, 1);
    assert.equal(store.accounts.find(row => row.id === chosen).state.kind, "verified");
    store.discover();
    assert.equal(store.accounts.find(row => row.id === chosen).state.kind, "signed-in", "no cached verification");
    for (const response of [{ kind: "models", text: "OK" }, { kind: "inference", text: "" }, { kind: "signed-in", text: "OK" }])
        assert.equal((await store.verify(chosen, "user", async () => response)).kind, "unavailable");
    let finish;
    const held = store.verify(chosen, "user", () => new Promise(resolve => { finish = resolve; }));
    await assert.rejects(() => store.verify(chosen, "user", request), /verify=busy/);
    store.discover();
    finish({ kind: "inference", text: "OK" });
    assert.deepEqual(await held, { kind: "superseded" });
    assert.equal(store.accounts.find(row => row.id === chosen).state.kind, "signed-in");
    mode("bus", "locked");
    const lockedId = store.discover().find(row => row.source.kind === "keyring").id;
    await assert.rejects(() => store.verify(lockedId, "user", request), /verify=keyring-locked/);
    mode("bus", "present");
    cases++;

    const metadata = fs.readFileSync(store.file);
    const additions = Array.from({ length: 33 }, (_, index) => ({
        provider: "claude", directory: seed(process.env.JARVIS_TEST_ROOT, "added-" + index), label: String(index)
    }));
    for (const [data, expected, needle, replacement] of [
        ["[]".padEnd(65537, " "), /added=size/, "stat.size > MAX_BYTES", "false"],
        [JSON.stringify(additions), /added=limit/, "values.length > MAX_ROWS", "false"],
        [JSON.stringify([additions[0], additions[0]]), /added=duplicate/, 'fail("added=duplicate");', "void 0;"],
        [JSON.stringify([{ ...additions[0], token: privateValue }]), /added=shape/,
            'Object.keys(value).sort().join(",") !== "directory,label,provider"', "false"]
    ]) {
        fs.writeFileSync(store.file, data);
        const assertion = Judge => assert.throws(() => new Judge(directory, env).added(), expected);
        assertion(Accounts);
        await mutant("backend/Accounts.js", "metadata-" + expected.source, needle, replacement, folder =>
            assertion(require(path.join(folder, "backend/Accounts.js")).Accounts));
        fs.writeFileSync(store.file, metadata);
        controls++;
        cases++;
    }
    fs.writeFileSync(store.file, JSON.stringify(additions.slice(0, 32)));
    const addLimit = Judge => assert.throws(() => new Judge(directory, env).add(additions[32]), /added=limit/);
    addLimit(Accounts);
    await mutant("backend/Accounts.js", "added-write-limit", "entries.length > MAX_ROWS", "false", folder =>
        addLimit(require(path.join(folder, "backend/Accounts.js")).Accounts));
    fs.writeFileSync(store.file, metadata);
    controls++;
    for (const [data, expected] of [["junk", /added=json/], ["[]".padEnd(65537, " "), /added=size/],
        [JSON.stringify(Array(33).fill({ provider: "claude", directory: hand, label: "hand" })), /added=limit/],
        [JSON.stringify([{ provider: "claude", directory: hand, label: "hand", token: privateValue }]), /added=shape/]]) {
        fs.writeFileSync(store.file, data);
        assert.throws(() => store.discover(), expected);
        fs.writeFileSync(store.file, metadata);
        cases++;
    }
    assert.throws(() => store.add({ provider: "claude", directory: path.join(env.HOME, ".claude-link"), label: "link" }), /directory=link/);
    assert.throws(() => new Accounts(directory, { ...env, CLAUDE_CONFIG_DIR: path.join(env.HOME, ".claude-link") }).discover(), /directory=link/);
    // The core walk refuses a root that is no absolute normal path; the
    // judge names it by its own key.
    for (const root of ["relative/claude", path.join(env.HOME, "x") + "/../.claude"])
        assert.throws(() => new Accounts(directory, { ...env, CLAUDE_CONFIG_DIR: root }).discover(), /directory=absolute-normal-path-required/);
    fs.renameSync(store.file, store.file + ".saved");
    fs.symlinkSync(store.file + ".saved", store.file);
    assert.throws(() => store.discover(), /added=read-failed/);
    fs.unlinkSync(store.file);
    fs.renameSync(store.file + ".saved", store.file);
    cases++;

    const late = path.join(env.HOME, "late-account");
    const lateLink = Judge => {
        mode("claude", "late-link");
        const before = markerChecks.length;
        try {
            const judge = new Judge(directory, { ...env, CLAUDE_CONFIG_DIR: late });
            const item = judge.discover().find(row => row.source.directory === late);
            assert.equal(item.marker, "absent", "an absent directory has no held marker parent");
            assert.equal(markerChecks.slice(before).some(file => file.startsWith(late + "/")), false,
                "a new link cannot become a marker's parent");
        } finally {
            mode("claude", "signed-in");
            if (fs.existsSync(late)) fs.unlinkSync(late);
        }
    };
    lateLink(Accounts);
    await mutant("backend/Accounts.js", "late-marker-link", 'if (opened.kind === "directory") {\n                const markerPath',
        'if (opened.kind !== "directory") fs.lstatSync(path.join(candidate.directory, harness(row.id).marker));\n            if (opened.kind === "directory") {\n                const markerPath',
        folder => lateLink(require(path.join(folder, "backend/Accounts.js")).Accounts));
    controls++;
    cases++;
    // A home of its own: only its direct entries are read, whatever their number.
    const worldOf = name => {
        const root = path.join(process.env.JARVIS_TEST_ROOT, name);
        const own = { ...env, HOME: path.join(root, "home"), XDG_CONFIG_HOME: path.join(root, "config"),
            XDG_DATA_HOME: path.join(root, "data") };
        for (const folder of [own.HOME, own.XDG_CONFIG_HOME, own.XDG_DATA_HOME]) fs.mkdirSync(folder, { recursive: true });
        return { state: path.join(root, "state"), env: own };
    };
    const judgeIn = folder => require(path.join(folder, "backend/Accounts.js")).Accounts;
    // The core search the copy reads, and the folders it found by name.
    const foldersIn = folder => require(path.join(folder, "backend/Core.js")).folders().accountFolders;
    const byName = found => found.folders.filter(item => item.source === "folder");
    const crowded = worldOf("crowded");
    const crowdedFolders = [seed(crowded.env.HOME, ".4claude"), seed(crowded.env.HOME, ".codex-work")];
    for (let i = 0; i < 4998; i++) fs.writeFileSync(path.join(crowded.env.HOME, String(i)), "");
    const crowdedSearch = folder => {
        const judge = new (judgeIn(folder))(crowded.state, crowded.env);
        const found = judge.discover();
        for (const directory of crowdedFolders) assert.ok(found.some(item => item.source.directory === directory), directory);
        assert.equal(judge.status().search.partial, "", "a home of 5000 entries is read whole");
    };
    crowdedSearch(plugin);
    await mutant("bin/lib/account-folders.js", "parent-entry-bound", "const MAX_PARENT_ENTRIES = 10000;",
        "const MAX_PARENT_ENTRIES = 200;", crowdedSearch);
    controls++;
    cases++;
    // A home past the bound: the folders among the names read before it,
    // as fs.opendirSync hands them out, plus every other parent's.
    const full = worldOf("full");
    const fullConfig = seed(full.env.XDG_CONFIG_HOME, ".claude-config");
    for (let i = 0; i < 12; i++) seed(full.env.HOME, ".claude-" + i);
    for (let i = 0; i <= 10000; i++) fs.writeFileSync(path.join(full.env.HOME, String(i)), "");
    const readFirst = [];
    const listing = fs.opendirSync(full.env.HOME);
    try {
        for (let entry; readFirst.length < 10000 && (entry = listing.readSync()) !== null;)
            readFirst.push(entry);
    } finally { listing.closeSync(); }
    const expectedHome = readFirst.filter(entry => entry.isDirectory() && /^\.claude-[0-9]+$/.test(entry.name))
        .map(entry => path.join(full.env.HOME, entry.name)).sort();
    assert.ok(expectedHome.length > 0, "the names read before the bound hold an account folder");
    const boundReached = folder => {
        const accountFolders = foldersIn(folder);
        let found;
        assert.doesNotThrow(() => { found = accountFolders({ home: full.env.HOME, config: full.env.XDG_CONFIG_HOME, data: full.env.XDG_DATA_HOME, env: {} }); });
        assert.equal(found.partial, "entry-limit");
        assert.deepEqual(byName(found).filter(item => path.dirname(item.directory) === full.env.HOME).map(item => item.directory).sort(),
            expectedHome, "the home folders read before the bound");
        assert.ok(found.folders.some(item => item.directory === fullConfig), "the next parent is still read");
        const judge = new (judgeIn(folder))(full.state, full.env);
        assert.doesNotThrow(() => judge.discover());
        assert.equal(judge.status().search.partial, "entry-limit");
    };
    boundReached(plugin);
    for (const [name, replacement] of [
        ["entry-bound-throws", 'if (++read > MAX_PARENT_ENTRIES) throw new Error("jarvis-accounts: discovery=entry-limit");'],
        ["entry-bound-unmarked", "if (++read > MAX_PARENT_ENTRIES) break;"],
        ["entry-bound-drops", 'if (++read > MAX_PARENT_ENTRIES) { partial ||= "entry-limit"; folders.length = 0; break; }'],
        ["entry-bound-stops", 'if (++read > MAX_PARENT_ENTRIES) { partial ||= "entry-limit"; return { folders, partial }; }']
    ]) {
        await mutant("bin/lib/account-folders.js", name, 'if (++read > MAX_PARENT_ENTRIES) { partial ||= "entry-limit"; break; }',
            replacement, boundReached);
        controls++;
    }
    cases++;
    // Exactly the bound is a whole search.
    const exact = worldOf("exact");
    const exactFolder = seed(exact.env.HOME, ".claude-exact");
    for (let i = 0; i < 9999; i++) fs.writeFileSync(path.join(exact.env.HOME, String(i)), "");
    assert.equal(fs.readdirSync(exact.env.HOME).length, 10000);
    const exactBound = folder => {
        const found = foldersIn(folder)(
            { home: exact.env.HOME, config: exact.env.XDG_CONFIG_HOME, data: exact.env.XDG_DATA_HOME, env: {} });
        assert.deepEqual([found.partial, byName(found).map(item => item.directory)], ["", [exactFolder]]);
    };
    exactBound(plugin);
    await mutant("bin/lib/account-folders.js", "entry-bound-off-by-one", "if (++read > MAX_PARENT_ENTRIES)", "if (++read >= MAX_PARENT_ENTRIES)", exactBound);
    controls++;
    cases++;
    // A linked parent is never followed and one that is no directory is not
    // read: the search is partial and keeps the other parents' folders. A
    // mode-000 folder is readable inside J09's user namespace, so the kinds
    // read here are a link and a file.
    for (const kind of ["link", "file"]) {
        const odd = worldOf("parent-" + kind);
        const oddHome = seed(odd.env.HOME, ".claude-home");
        const target = seed(process.env.JARVIS_TEST_ROOT, "parent-target-" + kind);
        seed(target, ".claude-behind");
        fs.rmSync(odd.env.XDG_CONFIG_HOME, { recursive: true });
        if (kind === "link") fs.symlinkSync(target, odd.env.XDG_CONFIG_HOME);
        else fs.writeFileSync(odd.env.XDG_CONFIG_HOME, "");
        const oddParent = folder => {
            let found;
            assert.doesNotThrow(() => { found = foldersIn(folder)(
                { home: odd.env.HOME, config: odd.env.XDG_CONFIG_HOME, data: odd.env.XDG_DATA_HOME, env: {} }); });
            assert.deepEqual([found.partial, byName(found).map(item => item.directory)], ["parent-unreadable", [oddHome]]);
            const judge = new (judgeIn(folder))(odd.state, odd.env);
            assert.doesNotThrow(() => judge.discover());
            assert.equal(judge.status().search.partial, "parent-unreadable");
        };
        oddParent(plugin);
        await mutant("bin/lib/account-folders.js", "parent-" + kind + "-throws",
            'if (opened.kind !== "directory") { partial ||= "parent-unreadable"; continue; }',
            'if (opened.kind !== "directory") throw new Error("jarvis-accounts: directory=" + opened.kind);', oddParent);
        controls++;
        cases++;
    }
    // A linked home leaves its default folders out, partial, and throws nothing.
    const linkedHome = worldOf("linked-home");
    const homeTarget = seed(process.env.JARVIS_TEST_ROOT, "linked-home-target");
    seed(homeTarget, ".claude");
    fs.rmSync(linkedHome.env.HOME, { recursive: true });
    fs.symlinkSync(homeTarget, linkedHome.env.HOME);
    const linkedDefault = folder => {
        const judge = new (judgeIn(folder))(linkedHome.state, linkedHome.env);
        let found;
        assert.doesNotThrow(() => { found = judge.discover(); });
        assert.equal(found.some(item => item.source.kind === "cli"), false, "nothing behind the link");
        assert.equal(judge.status().search.partial, "parent-unreadable");
    };
    linkedDefault(plugin);
    await mutant("bin/lib/account-folders.js", "default-under-link", 'else partial ||= "parent-unreadable";', "else add(row, fallback, \"default\", \"default\");", linkedDefault);
    controls++;
    cases++;
    // Only a label that is an email names an identity to compare.
    const labelled = worldOf("email-label");
    const emailFolder = seed(labelled.env.HOME, "by-hand");
    new Accounts(labelled.state, labelled.env).add({ provider: "claude", directory: emailFolder, label: "other@example.invalid" });
    seed(labelled.env.HOME, ".claude-team");
    const identities = folder => {
        const found = new (judgeIn(folder))(labelled.state, labelled.env).discover();
        assert.deepEqual([found.find(item => item.source.directory === emailFolder).identity.kind,
            found.find(item => item.label === "team").identity.kind], ["mismatch", "match"]);
    };
    identities(plugin);
    await mutant("backend/Accounts.js", "identity-any-label", 'email && label.includes("@") && email !== label',
        'email && label !== "default" && email !== label', identities);
    controls++;
    await mutant("backend/Accounts.js", "identity-never", 'email && label.includes("@") && email !== label', "false", identities);
    controls++;
    cases++;
    const many = worldOf("many");
    for (let i = 0; i < 33; i++) seed(many.env.HOME, ".claude-" + i);
    const accountBound = folder => {
        const before = calls("cli-calls").length;
        const judge = new (judgeIn(folder))(many.state, many.env);
        let found;
        assert.doesNotThrow(() => { found = judge.discover(); });
        assert.equal(judge.status().search.partial, "account-limit");
        assert.ok(found.length <= 32);
        assert.ok(calls("cli-calls").length - before <= 32, "at most the shown count of vendor commands");
    };
    accountBound(plugin);
    for (const [name, needle, replacement] of [
        ["candidate-bound-throws", 'if (candidates.length > MAX_ROWS) this.partial ||= "account-limit";',
            'if (candidates.length > MAX_ROWS) fail("discovery=account-limit");'],
        ["candidate-bound-probes", "candidates.slice(0, MAX_ROWS).map(", "candidates.map("]
    ]) {
        await mutant("backend/Accounts.js", name, needle, replacement, accountBound);
        controls++;
    }
    cases++;
    const referenceBytes = fs.readFileSync(references.file);
    fs.writeFileSync(references.file, JSON.stringify(Array.from({ length: 32 }, (_, index) => ({
        provider: "openai", account: String(index), origin: "https://api.openai.com", attributes: { id: String(index) }
    }))));
    const finalBound = Judge => {
        const judge = new Judge(directory, env);
        let found;
        assert.doesNotThrow(() => { found = judge.discover(); });
        assert.equal(found.length, 32);
        assert.deepEqual([judge.status().search.found, judge.status().search.partial], [32, "account-limit"]);
    };
    finalBound(Accounts);
    await mutant("backend/Accounts.js", "status-bound", "this.accounts = result.slice(0, MAX_ROWS);", "this.accounts = result;",
        folder => finalBound(judgeIn(folder)));
    controls++;
    fs.writeFileSync(references.file, referenceBytes);
    cases++;

    for (const [name, needle, replacement, check] of [
        ["marker-open", "const stat = fs.lstatSync(markerPath);", "const stat = (fs.readFileSync(markerPath), fs.lstatSync(markerPath));",
            Judge => discovery(new Judge(directory, { ...env, CODEX_HOME: explicit, OPENAI_API_KEY: privateValue }))],
        ["marker-first", "const result = this.run(row.command[0], row.command.slice(1), { [harness(row.id).variable]: candidate.directory });",
            "fs.lstatSync(path.join(candidate.directory, harness(row.id).marker));\n        const result = this.run(row.command[0], row.command.slice(1), { [harness(row.id).variable]: candidate.directory });",
            Judge => discovery(new Judge(directory, { ...env, CODEX_HOME: explicit, OPENAI_API_KEY: privateValue }))],

        ["manual", "for (const item of this.added())", "for (const item of [])",
            Judge => discovery(new Judge(directory, { ...env, CODEX_HOME: explicit, OPENAI_API_KEY: privateValue }))],
        ["explicit-user", 'if (initiation !== "user")', "if (false)",
            async Judge => { const judge = new Judge(directory, env); const id = judge.discover()[0].id;
                await assert.rejects(() => judge.verify(id, "automatic", async () => ({ kind: "inference", text: "OK" })), /explicit-user-required/); }],
        ["inference-proof", 'answer.kind !== "inference"', "false",
            async Judge => { const judge = new Judge(directory, env); const id = judge.discover()[0].id;
                assert.equal((await judge.verify(id, "user", async () => ({ kind: "models", text: "OK" }))).kind, "unavailable"); }],
        ["stale-verify", "this.epoch !== epoch", "false",
            async Judge => { const judge = new Judge(directory, env); const id = judge.discover()[0].id; let done;
                const pending = judge.verify(id, "user", () => new Promise(resolve => { done = resolve; }));
                judge.discover(); done({ kind: "inference", text: "OK" }); assert.deepEqual(await pending, { kind: "superseded" }); }],
        ["vendor-token", "return /(claude[ -]?code|codex|copilot|oauth|refresh[ _-]?token|access[ _-]?token)/.test(text);", "return false;",
            Judge => assert.deepEqual(new Judge(directory, env).keyItems().map(item => item.label), ["Other tool API key"])],
        ["login-is-not-inference", 'return { kind: "signed-in", email, plan };', 'return { kind: "verified", email, plan };',
            Judge => discovery(new Judge(directory, { ...env, CODEX_HOME: explicit, OPENAI_API_KEY: privateValue }))],
        ["child-environment", "this.env = childEnvironment(env);", "this.env = env;",
            Judge => { const before = calls("cli-calls").length;
                new Judge(directory, { ...env, OPENAI_API_KEY: privateValue }).discover();
                for (const call of calls("cli-calls").slice(before)) assert.equal(call.env.OPENAI_API_KEY, undefined); }]
    ]) {
        await mutant("backend/Accounts.js", name, needle, replacement, folder => check(require(path.join(folder, "backend/Accounts.js")).Accounts));
        controls++;
    }
    await mutant("backend/Secrets.js", "metadata-only", '"get-property",', '"call",', folder =>
        assert.doesNotThrow(() => new (require(path.join(folder, "backend/Secrets.js")).Secrets)(directory, env).items()));
    controls++;

    // Discovery finds its candidates through the shared name rule and the
    // shared anchored walk, each with its own control in its own file.
    const sharedRule = folder => discovery(new (judgeIn(folder))(directory, { ...env, CODEX_HOME: explicit, OPENAI_API_KEY: privateValue }));
    for (const [relative, name, needle, replacement] of [
        ["shell/Commons/AccountDirectories.js", "name-rule", 'if (new RegExp("^\\\\.[a-z0-9]{0,8}" + row.folder).test(name)) return row;', "if (false) return row;"],
        ["shell/Commons/AccountDirectories.js", "name-tag", '"^\\\\.[a-z0-9]{0,8}" + row.folder', '"^\\\\." + row.folder'],
        ["bin/lib/account-folders.js", "no-descent", "for (const parent of [...new Set([home, config, data])])",
            'for (const parent of [...new Set([home, config, data, path.join(home, "projects")])])']
    ]) {
        await mutant(relative, name, needle, replacement, sharedRule);
        controls++;
    }
    const linkedRoot = folder => assert.throws(() => new (judgeIn(folder))(directory,
        { ...env, CLAUDE_CONFIG_DIR: path.join(env.HOME, ".claude-link") }).discover(), /directory=link/);
    linkedRoot(plugin);
    await mutant("bin/lib/anchored.js", "no-follow", 'if (stat.isSymbolicLink()) return { kind: "link" };',
        'if (stat.isSymbolicLink()) return { kind: "absent" };', linkedRoot);
    controls++;

    // The service passes exactly the harnesses' root variables.
    const variables = folder => assert.deepEqual({ ...require(path.join(folder, "backend/Core.js")).accounts().accountVariables(name => "value-" + name) },
        { CLAUDE_CONFIG_DIR: "value-CLAUDE_CONFIG_DIR", CODEX_HOME: "value-CODEX_HOME", COPILOT_HOME: "value-COPILOT_HOME" });
    variables(plugin);
    cases++;
    await mutant("shell/Commons/AccountDirectories.js", "account-variables",
        "result[HARNESSES[i].variable] = read(HARNESSES[i].variable);", "void read;", variables);
    controls++;

    // The roots entry: explicit roots, then hand-added ones, and never a
    // scanned candidate.
    const explicitClaude = path.join(env.HOME, "explicit-claude");
    const rootsOf = folder => {
        const { accountRoots } = require(path.join(folder, "backend/Accounts.js"));
        assert.deepEqual(accountRoots(directory, { ...env, CODEX_HOME: explicit, CLAUDE_CONFIG_DIR: explicitClaude }),
            [explicitClaude, explicit, hand]);
        assert.deepEqual(accountRoots(directory, env), [hand]);
    };
    rootsOf(plugin);
    cases++;
    for (const [name, needle, replacement] of [
        ["roots-explicit", 'if (env[row.variable]) result[row.id] = env[row.variable];', ''],
        ["roots-added", 'addedRows(path.join(stateDirectory, "accounts.json"))', '[]']
    ]) {
        await mutant("backend/Accounts.js", name, needle, replacement, rootsOf);
        controls++;
    }

    // A missing stand-in cannot reach a host executable.
    for (const [command, assertion] of [
        ["claude", judge => {
            assert.equal(judge.discover().find(row => row.provider === "claude").state.kind, "unavailable");
            assert.throws(() => discovery(judge), assert.AssertionError);
        }],
        ["ss", judge => {
            assert.equal(judge.discover().find(row => row.provider === "ollama").state.kind, "unavailable");
            assert.throws(() => discovery(judge), assert.AssertionError);
        }],
        ["busctl", judge => {
            assert.throws(() => judge.keyItems(), /busctl=missing/);
            assert.throws(() => assert.doesNotThrow(() => judge.keyItems()), assert.AssertionError);
        }]
    ]) {
        const file = path.join(process.env.JARVIS_TEST_ROOT, "standins", command);
        fs.renameSync(file, file + ".removed");
        try { assertion(new Accounts(directory, env)); }
        finally { fs.renameSync(file + ".removed", file); }
        cases++;
    }
    mode("ports", "junk");
    assert.throws(() => store.discover(), /ports=reply/);
    mode("ports", "present");

    function cli(folder, args) {
        return cp.spawnSync("node", [path.join(folder, "backend/accounts.js"), "--tree", tree, ...args], {
            env, encoding: "utf8", timeout: 15000 });
    }
    const goodCli = folder => {
        const result = cli(folder, ["list"]);
        assert.equal(result.status, 0, result.stdout + result.stderr);
        assert.ok(JSON.parse(result.stdout).some(item => item.source.directory === hand));
        safe(result.stdout + result.stderr);
    };
    goodCli(plugin);
    const normalizedError = folder => {
        const result = cli(folder, ["presence", privateValue]);
        assert.equal(result.status, 1);
        assert.equal(result.stderr, "jarvis-accounts: operation=failed\n");
        safe(result.stdout + result.stderr);
    };
    normalizedError(plugin);
    await mutant("backend/accounts.js", "safe-cli-error",
        'const reason = helperFailure(error.message) || "jarvis-accounts: operation=failed";',
        "const reason = error.message;", normalizedError);
    controls++;
    const automatic = cli(plugin, ["verify", chosen]);
    assert.equal(automatic.status, 1);
    await mutant("backend/accounts.js", "cli-discovery", "value = judge.discover();", "value = [];",
        folder => goodCli(folder));
    controls++;
    assert.equal(calls("secret-calls").length, 0);
    safe(fs.readFileSync(store.file, "utf8"));
    assert.deepEqual(keyPresence(() => ""), keyPresence(() => undefined));

    // The page's words: each outcome's tone and whether Accounts or Add key
    // is offered. A search, whole or partial, offers Accounts; every
    // failure key the helper can name, read from the helper's own table,
    // and every cause the reader names itself is a failed check that does
    // not. The words carry no diagnostic key.
    const plain = value => {
        const text = typeof value === "string" ? value : value.text;
        assert.equal(/=|jarvis-/.test(text) || text === "", false, "user words: " + text);
    };
    const failed = reason => ({ kind: "failed", reason });
    const pageWords = folder => {
        const Words = require(path.join(folder, "AccountStatus.js"));
        const { FAILURE_KEYS } = require(path.join(folder, "AccountProviders.js"));
        const reasons = Object.entries(FAILURE_KEYS).flatMap(([owner, fields]) => Object.entries(fields)
            .flatMap(([field, codes]) => codes.map(code => owner + ": " + field + "=" + code)));
        assert.ok(["jarvis-accounts: added=json", "jarvis-accounts: directory=link", "jarvis-keys: busctl=missing"]
            .every(reason => reasons.includes(reason)), "the helper's table holds its known failures");
        const searchCases = [
            [{ kind: "found", found: 3, partial: "" }, "ok", true],
            [{ kind: "found", found: 1, partial: "" }, "ok", true],
            [{ kind: "found", found: 0, partial: "" }, "info", true],
            [{ kind: "found", found: 2, partial: "entry-limit" }, "warning", true],
            [{ kind: "found", found: 2, partial: "parent-unreadable" }, "warning", true],
            [{ kind: "found", found: 32, partial: "account-limit" }, "warning", true],
            ...reasons.map(reason => [failed(reason), "danger", false]),
            ...["process=start-failed", "process=crashed", "output=invalid", "diagnostic=oversize", "process=failed"]
                .map(reason => [failed("jarvis-accounts: " + reason), "danger", false]),
            [failed(""), "danger", false]
        ];
        for (const [outcome, tone, action] of searchCases) {
            const value = Words.searchValue(outcome);
            assert.deepEqual([value.tone, value.action], [tone, action], JSON.stringify(outcome));
            plain(value);
        }
        const keyRow = value => ({ label: "fixture / test", value });
        for (const [outcome, tone] of [
            [{ kind: "listed", rows: [keyRow("present"), keyRow("present")] }, "ok"],
            [{ kind: "listed", rows: [] }, "info"],
            [{ kind: "listed", rows: [keyRow("present"), keyRow("locked")] }, "warning"],
            [{ kind: "listed", rows: [keyRow("unavailable")] }, "warning"],
            [{ kind: "failed" }, "warning"]
        ]) {
            const value = Words.keysValue(outcome);
            assert.deepEqual([value.tone, value.action], [tone, true], JSON.stringify(outcome));
            plain(value);
        }
        for (const value of ["present", "absent", "locked"]) assert.equal(Words.keyHint(keyRow(value)), "", value);
        plain(Words.keyHint({ label: "fixture / test", value: "unavailable", hint: "jarvis-keys: busctl=failed" }));
        const hints = [];
        for (const state of ["signed-in", "found", "verifying", "verified", "locked", "unavailable"])
            for (const source of ["cli", "variable", "keyring", "local"])
                for (const mismatch of [false, true]) {
                    const hint = Words.accountHint({ state, source, plan: "pro", email: "team@example.invalid", mismatch });
                    plain(hint);
                    assert.ok(hint.length <= 200);
                    hints.push([state, source, mismatch, hint]);
                }
        const hintOf = (state, source) => hints.find(row => row[0] === state && row[1] === source && !row[2])[3];
        assert.notEqual(hintOf("signed-in", "cli"), hintOf("found", "cli"), "signed in and found read apart");
        assert.notEqual(hintOf("found", "cli"), hintOf("unavailable", "cli"), "found and unavailable read apart");
        for (const [state, source] of [["found", "cli"], ["locked", "keyring"]])
            assert.notEqual(Words.accountHint({ state, source, plan: "", email: "", mismatch: true }),
                Words.accountHint({ state, source, plan: "", email: "", mismatch: false }), "a mismatch is named");
    };
    pageWords(plugin);
    for (const account of store.status().accounts) plain(require(path.join(plugin, "AccountStatus.js")).accountHint(account));
    cases++;
    await mutant("AccountStatus.js", "saved-list-offers-accounts",
        'return { tone: "danger", text: "Could not read your saved accounts", action: false };',
        'return { tone: "danger", text: "Could not read your saved accounts", action: true };', pageWords);
    controls++;
    await mutant("AccountStatus.js", "partial-reads-complete", 'if (outcome.partial === "entry-limit")', "if (false)", pageWords);
    controls++;
    console.log("test-jarvis-accounts: ok cases=" + cases + " controls=" + controls);
});
