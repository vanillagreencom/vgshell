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
    // Execute the shipped QML publication callback. Process timing and drawing
    // remain the nested smoke's contract; these cases judge its write decision.
    const publicationSource = fs.readFileSync(path.join(plugin, "Accounts.qml"), "utf8");
    const publicationCases = [
        { name: "sole", choices: ["key-a"], writes: ["key-a"] },
        { name: "zero", choices: [], writes: [] },
        { name: "multiple", choices: ["key-a", "key-b"], writes: [] },
        { name: "explicit", choices: ["key-a"], selected: "key-b", writes: [] },
        { name: "failed", choices: ["key-a"], code: 1, writes: [] },
        { name: "invalid", choices: ["key-a"], invalid: true, writes: [] },
        { name: "stale", choices: ["key-a"], pending: true, writes: [] },
        { name: "refused", choices: ["key-a"], refuseWrite: true, writes: ["key-a"] },
        ...["accounts", "brains", "voiceAccounts", "accountSearch"].map(key =>
            ({ name: "status-" + key, choices: ["key-a"], refuseStatus: key, writes: [] }))
    ];
    function publication(source, row) {
        const vm = require("node:vm");
        const matches = [...source.matchAll(/^    function publish\(\) \{\n[\s\S]*?^    \}/gm)];
        assert.equal(matches.length, 1);
        const writes = [], reports = new Map(), warnings = [];
        let refreshed = 0;
        const initial = row.selected ?? "";
        const root = { pending: row.pending ?? false, completion: { kind: "exited", code: row.code ?? 0 },
            diagnostic: { kind: "collected", text: "" },
            output: row.invalid ? "broken" : JSON.stringify({ accounts: [], brains: [],
                voiceAccounts: row.choices.map(value => ({ value, label: "Fixture " + value })),
                search: { found: row.choices.length, partial: "" } }),
            refreshed: () => refreshed++, shell: { settings: { voiceAccount: initial },
                status: { set: (key, value) => {
                    if (row.refuseStatus === key && !reports.has(key)) { reports.set(key, null); return "refused"; }
                    reports.set(key, value); return "ok";
                } },
                configure: { set: (key, value) => {
                    assert.equal(key, "voiceAccount"); writes.push(value);
                    if (row.refuseWrite) return "refused";
                    root.shell.settings.voiceAccount = value; return "ok";
                } } } };
        const context = vm.createContext({ root, Providers: { probeFailure },
            Gate: require("../bin/lib/qml-library.js").load(path.join(plugin, "SetupGate.js")),
            Words: require(path.join(plugin, "AccountStatus.js")), console: { warn: value => warnings.push(value) } });
        vm.runInContext("(function() { with(root) { return (" + matches[0][0] + ").call(root); } })()", context);
        assert.deepEqual(writes, row.writes);
        assert.equal(root.shell.settings.voiceAccount, row.refuseWrite || row.writes.length === 0 ? initial : "key-a");
        assert.equal(refreshed, 1);
        const failed = row.code === 1 || row.invalid || row.refuseStatus;
        assert.equal(reports.get("accountSearch").tone, failed ? "danger" : row.choices.length ? "ok" : "info");
        assert.deepEqual(Array.from(reports.get("voiceAccounts"), item => item.value), failed ? [] : row.choices);
        assert.equal(warnings.length, failed || row.refuseWrite ? 1 : 0);
    }
    for (const row of publicationCases) { publication(publicationSource, row); cases++; }
    const selectionControls = [
        ["sole", 'shell.configure.set("voiceAccount", value.voiceAccounts[0].value)', 'shell.configure.set("voiceAccount", "key-b")'],
        ["zero", "value.voiceAccounts.length === 1", "value.voiceAccounts.length <= 1"],
        ["multiple", "value.voiceAccounts.length === 1", "value.voiceAccounts.length > 0"],
        ["explicit", 'shell.settings.voiceAccount === ""', "true"],
        ["failed", 'if (code !== 0) throw new Error("probe");', "void code;"],
        ["invalid", "JSON.parse(output)", 'JSON.parse(output === "broken" ? JSON.stringify({accounts: [], brains: [], voiceAccounts: [{value: "key-a", label: "Fixture"}], search: {found: 1, partial: ""}}) : output)'],
        ["stale", "!pending && shell.settings.voiceAccount", "true && shell.settings.voiceAccount"],
        ["stale", 'const code = completion.kind === "exited" ? completion.code : -1;', 'if (pending) return; const code = completion.kind === "exited" ? completion.code : -1;'],
        ["refused", 'console.warn("jarvis-accounts: voice-selection=refused");', "void 0;"]
    ];
    for (const key of ["accounts", "brains", "voiceAccounts", "accountSearch"]) {
        const argument = { accounts: "accounts", brains: "value.brains", voiceAccounts: "value.voiceAccounts", accountSearch: "search" }[key];
        selectionControls.push(["status-" + key, 'shell.status.set("' + key + '", ' + argument + ') !== "ok"',
            '(shell.status.set("' + key + '", ' + argument + '), false)']);
    }
    for (const [name, needle, replacement] of selectionControls) {
        assert.equal(publicationSource.split(needle).length - 1, 1);
        assert.throws(() => publication(publicationSource.replace(needle, replacement),
            publicationCases.find(row => row.name === name)), assert.AssertionError, name);
        controls++;
    }
    const manifest = JSON.parse(fs.readFileSync(path.join(plugin, "manifest.json"), "utf8"));
    const configured = value => assert.equal(value.capabilities.includes("configure"), true);
    configured(manifest);
    assert.throws(() => configured({ ...manifest, capabilities: manifest.capabilities.filter(value => value !== "configure") }),
        assert.AssertionError);
    cases++; controls++;
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
        assert.equal(store.status().voiceAccounts.some(row => row.value === item.id), value === "present");
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
    const voiceOffers = Judge => {
        const judge = new Judge(directory, { ...env, OPENAI_API_KEY: privateValue });
        const rows = judge.discover();
        const wanted = rows.find(item => item.source.reference?.account === "other");
        const environmentAccount = rows.find(item => item.provider === "openai" && item.source.kind === "variable");
        assert.ok(environmentAccount, "the fixture discovers an environment account");
        const choices = judge.status().voiceAccounts;
        assert.equal(choices.some(choice => choice.value === environmentAccount.id), false);
        assert.deepEqual(choices.map(choice => choice.value), [wanted.id]);
        safe(choices);
    };
    voiceOffers(Accounts);
    for (const [name, needle, replacement] of [
        ["live-provider-offer", 'offered.filter(item => item.provider === "openai")', "offered"],
        ["live-resolved-account-offer", 'if (resolved === null) return { kind: "refused", cause: "account-unavailable" };',
            'if (resolved === null) return { kind: "accepted", account: null };']
    ]) {
        await mutant("backend/Accounts.js", name, needle,
            replacement, folder => voiceOffers(require(path.join(folder, "backend/Accounts.js")).Accounts));
        controls++;
        cases++;
    }
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
        // A speech-only key is found, with no model, and the engine refuses it.
        const speech = found.find(item => item.provider === "elevenlabs");
        assert.ok(speech, "a speech-only key reference exists");
        assert.deepEqual(judge.resolve(speech.id), { id: speech.id, provider: "elevenlabs", label: speech.label,
            source: speech.source, model: "" });
        assert.deepEqual(judge.choose(speech.id), { kind: "refused", cause: "model-required" }, "a speech-only key");
        // A Claude Code folder's program is the brain, with its own default model.
        const claude = found.find(item => item.source.kind === "cli" && item.provider === "claude");
        assert.deepEqual(judge.resolve(claude.id), { id: claude.id, provider: "claude", label: claude.label,
            source: { kind: "cli", directory: claude.source.directory }, model: "" });
        for (const other of [unknown.id, "", "keyring:0"]) {
            let value;
            assert.doesNotThrow(() => { value = judge.resolve(other); }, "resolution judges every saved reference");
            assert.equal(value, null, "an unsupported or unknown id selects nothing");
        }
        assert.deepEqual([calls("cli-calls").length, calls("port-calls").length, calls("secret-calls").length], before,
            "resolution runs no vendor command, port read or key lookup");
    };
    resolution(Accounts);
    await mutant("backend/Accounts.js", "resolve-unsupported", 'if (source.kind === "keyring" && !keyProvider(row)) return null;', "",
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
    // An absent folder is never probed, so the check creates nothing: in
    // late-link mode the stand-in, as Claude Code makes the folder its
    // status command names, puts a link where CLAUDE_CONFIG_DIR names none.
    // The folder is neither listed, offered nor chosen.
    const late = path.join(env.HOME, "late-account");
    const present = file => {
        try { fs.lstatSync(file); return true; }
        catch (error) { if (error.code === "ENOENT") return false; throw error; }
    };
    const absentFolder = Judge => {
        const lateEnv = { ...env, CLAUDE_CONFIG_DIR: late };
        fs.mkdirSync(late);
        let id;
        try { id = new Judge(directory, lateEnv).discover().find(row => row.source.directory === late).id; }
        finally { fs.rmdirSync(late); }
        mode("claude", "late-link");
        const before = calls("cli-calls").length;
        try {
            const judge = new Judge(directory, lateEnv);
            const rows = judge.discover();
            assert.equal(calls("cli-calls").slice(before).some(call => call.env.CLAUDE_CONFIG_DIR === late), false,
                "discovery runs no vendor command for an absent folder");
            assert.equal(present(late), false, "discovery creates no folder");
            assert.equal(rows.some(row => row.id === id), false, "an absent folder is not listed");
            assert.equal(judge.status().brains.some(choice => choice.value === id), false, "an absent folder is not offered");
            const count = calls("cli-calls").length;
            assert.deepEqual(judge.choose(id), { kind: "refused", cause: "account-unavailable" }, "an absent folder is not chosen");
            assert.equal(calls("cli-calls").slice(count).some(call => call.env.CLAUDE_CONFIG_DIR === late), false,
                "the engine's choice runs no vendor command for an absent folder");
            assert.equal(present(late), false, "the engine's choice creates no folder");
        } finally {
            mode("claude", "signed-in");
            if (present(late)) fs.unlinkSync(late);
        }
    };
    absentFolder(Accounts);
    await mutant("backend/Accounts.js", "absent-folder-probed", 'if (opened.kind === "absent") return null;',
        'if (opened.kind === "absent") { if (row.command !== null) this.run(row.command[0], row.command.slice(1), { [harness(row.id).variable]: candidate.directory }); return null; }',
        folder => absentFolder(judgeIn(folder)));
    controls++;
    cases++;
    // A folder removed after discovery is refused by Verify before the
    // vendor program starts, which would create the folder it names.
    const goneFolder = async Judge => {
        const gone = seed(env.HOME, ".claude-gone", ".credentials.json");
        let id;
        const judge = new Judge(directory, env);
        try { id = judge.discover().find(row => row.source.directory === gone).id; }
        finally { fs.rmSync(gone, { recursive: true }); }
        const before = calls("cli-calls").length;
        try {
            assert.deepEqual(await judge.verify(id, "user"), { kind: "unavailable", reason: "account-directory" }, "Verify refuses a removed folder");
            assert.equal(calls("cli-calls").slice(before).some(call => call.env.CLAUDE_CONFIG_DIR === gone), false,
                "Verify runs no vendor program for a removed folder");
            assert.equal(present(gone), false, "Verify creates no folder");
        } finally { fs.rmSync(gone, { recursive: true, force: true }); }
    };
    await goneFolder(Accounts);
    await mutant("backend/Accounts.js", "verify-absent-folder",
        'if (directory(account.source.directory).kind !== "directory") fail("verify=account-directory");', "",
        folder => goneFolder(judgeIn(folder)));
    controls++;
    cases++;
    // The engine's status check, inside every hello, stops a stalled vendor
    // command at its own bound, under the shell's 5000 ms first-hello
    // deadline, and reads it unavailable, which the engine still takes,
    // never signed out: the stand-in answers signed out only after 4000 ms.
    const stalledStatus = Judge => {
        const judge = new Judge(directory, env);
        const id = judge.discover().find(row => row.source.directory === nestedClaude).id;
        mode("claude", "slow");
        try {
            const before = calls("cli-calls").length;
            const started = Date.now();
            const answer = judge.choose(id);
            const elapsed = Date.now() - started;
            assert.equal(calls("cli-calls").slice(before).some(call => call.env.CLAUDE_CONFIG_DIR === nestedClaude), true,
                "the status command ran");
            assert.ok(elapsed < 3000, "choose() stops a stalled status command at its own bound: " + elapsed + " ms");
            assert.equal(answer.kind, "accepted", "a stalled status command is not signed out");
        } finally { mode("claude", "signed-in"); }
    };
    stalledStatus(Accounts);
    for (const [name, needle, replacement] of [
        ["choose-command-bound", "label: resolved.label }, CHOOSE_STATUS_MS);", "label: resolved.label });"],
        ["run-ignores-bound", "timeout, maxBuffer", "timeout: COMMAND_MS, maxBuffer"]]) {
        await mutant("backend/Accounts.js", name, needle, replacement, folder => stalledStatus(judgeIn(folder)));
        controls++;
    }
    cases++;
    // A signed-out folder, the vendor's own not logged in answer, is listed
    // signed-out, with Sign in for a provider that has one, and is neither
    // offered nor chosen; signed in, it is offered and chosen. A Copilot
    // folder, which no status command checks, stays offered.
    const copilotWorld = worldOf("copilot");
    const copilotFolder = seed(copilotWorld.env.HOME, ".copilot");
    const signedOutRule = Judge => {
        for (const [name, folder] of [["claude", nestedClaude], ["codex", nestedCodex]]) {
            for (const state of ["found", "signed-in"]) {
                const out = state === "found";
                const label = name + " " + state + ": ";
                mode(name, state);
                try {
                    const judge = new Judge(directory, env);
                    const rows = judge.discover();
                    const status = judge.status();
                    const at = rows.findIndex(row => row.source.directory === folder);
                    assert.ok(at >= 0, label + "fixture folder");
                    assert.deepEqual([rows[at].state.kind, status.accounts[at].state, status.accounts[at].value, status.accounts[at].signIn],
                        [state, state, out ? "signed-out" : "present", out], label + "listed");
                    assert.equal(status.brains.some(choice => choice.value === rows[at].id), !out, label + "offered");
                    assert.deepEqual(judge.choose(rows[at].id), out ? { kind: "refused", cause: "signed-out" }
                        : { kind: "accepted", account: { id: rows[at].id, provider: name, label: rows[at].label, source: rows[at].source, model: "" } },
                    label + "chosen");
                } finally { mode(name, "signed-in"); }
            }
        }
        const judge = new Judge(copilotWorld.state, copilotWorld.env);
        const rows = judge.discover();
        const status = judge.status();
        const at = rows.findIndex(row => row.source.directory === copilotFolder);
        assert.ok(at >= 0, "copilot fixture folder");
        assert.deepEqual([status.accounts[at].state, status.accounts[at].value, status.accounts[at].signIn], ["unchecked", "present", false], "copilot: listed");
        assert.equal(status.brains.some(choice => choice.value === rows[at].id), true, "copilot: offered");
        assert.equal(judge.choose(rows[at].id).kind, "accepted", "copilot: chosen");
    };
    signedOutRule(Accounts);
    for (const [name, needle, replacement] of [
        ["signed-out-accepted", 'if (signedOut(resolved.source, state)) return { kind: "refused", cause: "signed-out" };', ""],
        ["signed-out-choice-unchecked", "accepted(resolved, account.state.kind);", "accepted(resolved, null);"],
        ["signed-out-reads-present", 'value = out ? "signed-out" : "present";', 'value = "present";'],
        ["signed-out-reads-absent", 'value = out ? "signed-out" : "present";', 'value = out ? "absent" : "present";'],
        ["signed-out-no-sign-in", "signIn: out && Array.isArray(row.signIn) };", "signIn: false };"],
        ["copilot-signed-out", 'return source.kind === "cli" && state === "found";', 'return source.kind === "cli" && ["found", "unchecked"].includes(state);']]) {
        await mutant("backend/Accounts.js", name, needle, replacement, folder => signedOutRule(judgeIn(folder)));
        controls++;
    }
    cases++;
    // The AI model list offers only the accounts Accounts.choose takes: no
    // key read from a variable, no local server or Cerebras key without a
    // model, and every subscription a harness runs.
    references.remember(ownReference("cerebras", "fast", "https://api.cerebras.ai"));
    const modelList = Judge => {
        const judge = new Judge(directory, { ...env, CODEX_HOME: explicit, OPENAI_API_KEY: privateValue });
        const found = judge.discover();
        const offered = new Set(judge.status().brains.map(choice => choice.value));
        const one = test => { const item = found.find(test); assert.ok(item, "fixture account"); return item; };
        const variable = one(row => row.source.kind === "variable" && row.provider === "openai");
        const ollama = one(row => row.provider === "ollama");
        const cerebras = one(row => row.provider === "cerebras");
        const key = one(row => row.source.reference?.account === "chosen label");
        const claude = one(row => row.source.directory === nestedClaude);
        const codex = one(row => row.source.directory === nestedCodex);
        assert.deepEqual(judge.choose(variable.id), { kind: "refused", cause: "account-unavailable" }, "a variable key");
        assert.deepEqual(judge.choose(ollama.id), { kind: "refused", cause: "model-required" }, "a local server");
        assert.deepEqual(judge.choose(cerebras.id), { kind: "refused", cause: "model-required" }, "Cerebras");
        assert.deepEqual(judge.choose(key.id), { kind: "accepted", account: { id: key.id, provider: "anthropic",
            label: "chosen label", source: key.source, model: "claude-haiku-4-5" } }, "a stored key");
        for (const item of [claude, codex])
            assert.deepEqual(judge.choose(item.id), { kind: "accepted", account: { id: item.id, provider: item.provider,
                label: item.label, source: item.source, model: "" } }, item.provider);
        for (const item of [variable, ollama, cerebras, ...found.filter(row => row.source.kind === "local")])
            assert.equal(offered.has(item.id), false, "not offered: " + item.provider + " " + item.source.kind);
        for (const item of [key, claude, codex]) assert.equal(offered.has(item.id), true, "offered: " + item.provider);
    };
    modelList(Accounts);
    for (const [file, name, needle, replacement] of [
        ["backend/Accounts.js", "model-rule", 'if (!modelProvider(provider(resolved.provider))) return', "if (false) return"],
        ["AccountProviders.js", "subscription-model", 'return row.kind === "cli" || (', "return ("],
        ["AccountProviders.js", "probe-model", '(row.probe !== undefined && row.probe.model !== "")', "row.probe !== undefined"],
        ["backend/Accounts.js", "list-accepted", '\n            && accepted(resolve(item.id), item.state.kind).kind === "accepted");', ");"]]) {
        await mutant(file, name, needle, replacement, folder => modelList(judgeIn(folder)));
        controls++;
    }
    cases++;
    // Labels: one account of a harness reads as its provider's name, more
    // read as their sign-in emails, and one with no email names no folder;
    // grouped by provider, a provider's emails in order. The words around
    // them are the label's own.
    const labelWorld = (name, folders) => {
        const own = worldOf(name);
        const directories = folders.map(([folder, email]) => {
            const made = seed(own.env.HOME, folder);
            if (email !== null) fs.writeFileSync(path.join(made, "fixture-email"), email);
            return made;
        });
        return { own, directories };
    };
    const providerLabel = id => PROVIDERS.find(row => row.id === id).label;
    // WANT: [provider id, its email, "alone" for a provider's one account or
    // null for none, folder name] for each offered account.
    const checkLabels = (judge, found, want, name) => {
        const got = judge.status().brains.map(choice => {
            const item = found.find(account => account.id === choice.value);
            return { label: choice.label, provider: item.provider, folder: path.basename(item.source.directory), name: item.label };
        });
        assert.deepEqual(got.map(row => row.provider + " " + row.folder).sort(),
            want.map(([provider, , folder]) => provider + " " + folder).sort(), name + ": the accounts offered");
        for (const row of got) {
            const [, email] = want.find(([provider, , folder]) => provider === row.provider && folder === row.folder);
            const first = providerLabel(row.provider);
            assert.ok(row.label.startsWith(first), name + ": " + row.label + " names its provider first");
            if (email === "alone") assert.equal(row.label, first, name + ": a provider's one account");
            else if (email === null)
                assert.equal(row.label, first + " / " + row.name,
                    name + ": " + row.label + " falls back to the folder label");
            else assert.ok(row.label.includes(email), name + ": " + row.label + " names " + email);
        }
        const groups = got.map(row => providerLabel(row.provider));
        assert.deepEqual(groups, [...groups].sort(), name + ": grouped by provider");
        for (const provider of new Set(got.map(row => row.provider))) {
            const emails = got.filter(row => row.provider === provider)
                .map(row => want.find(([id, , folder]) => id === provider && folder === row.folder)[1])
                .filter(email => email !== null && email !== "alone");
            assert.deepEqual(emails, [...emails].sort(), name + ": " + provider + " in email order");
        }
    };
    const several = labelWorld("labels", [[".claude", "bob@example.invalid"], [".claude-a", "zed@example.invalid"],
        [".claude-b", "amy@example.invalid"], [".claude-q", ""], [".2codex", null], [".codex", null]]);
    const single = labelWorld("single", [[".claude", "bob@example.invalid"], [".codex", null]]);
    const labels = Judge => {
        for (const [world, want, name] of [
            [several, [["claude", null, ".claude-q"], ["claude", "amy@example.invalid", ".claude-b"],
                ["claude", "bob@example.invalid", ".claude"], ["claude", "zed@example.invalid", ".claude-a"],
                ["codex", null, ".2codex"], ["codex", null, ".codex"]], "several"],
            [single, [["claude", "alone", ".claude"], ["codex", "alone", ".codex"]], "single"]]) {
            const judge = new Judge(world.own.state, world.own.env);
            checkLabels(judge, judge.discover(), want, name);
        }
    };
    labels(Accounts);
    for (const [name, needle, replacement] of [
        ["label-email", 'item.email ? row.label + " / " + item.email', 'item.email ? row.label + " / " + item.label'],
        ["label-single", ".length === 1;", ".length === 0;"],
        ["label-no-email", ": row.label + \" / \" + item.label;", ": row.label;"],
        ["label-order", ".sort((left, right) => order(left.label, right.label) || order(left.value, right.value)).slice(0, MAX_ROWS);",
            ".slice(0, MAX_ROWS);"]]) {
        await mutant("backend/Accounts.js", name, needle, replacement, folder => labels(judgeIn(folder)));
        controls++;
    }
    cases++;
    // A signed-in Codex account's email comes from its own program's
    // account/read, as AI Usage reads it: one bounded program per account,
    // CODEX_HOME its folder. Any failed or late read names no email. Only
    // the silent program's row times the bound; the others keep the
    // production bound, far above a loaded host's start.
    const codexWorld = labelWorld("codex-emails", [[".codex", "amy@example.invalid"], [".2codex", "zed@example.invalid"]]);
    const codexFolders = [".codex", ".2codex"].map(name => path.join(codexWorld.own.env.HOME, name));
    const noEmail = [["codex", null, ".codex"], ["codex", null, ".2codex"]];
    const codexEmails = async Judge => {
        for (const [appMode, want] of [
            ["chatgpt", [["codex", "amy@example.invalid", ".codex"], ["codex", "zed@example.invalid", ".2codex"]]],
            ["api", noEmail], ["exit", noEmail], ["silent", noEmail]]) {
            mode("codex-app", appMode);
            const judge = new Judge(codexWorld.own.state, codexWorld.own.env);
            const found = judge.discover();
            const before = calls("app-calls").length;
            const started = Date.now();
            await judge.readEmails(appMode === "silent" ? { deadlineMs: 300 } : {});
            // The bound, not the silent program's own exit at 3000 ms, ends its read.
            if (appMode === "silent") assert.ok(Date.now() - started < 1500, "silent: the read ends at its bound");
            checkLabels(judge, found, want, appMode);
            const reads = calls("app-calls").slice(before);
            assert.deepEqual(reads.map(call => call.env.CODEX_HOME).sort(), [...codexFolders].sort(), appMode + ": one program per account");
            for (const call of reads) assert.equal(call.env.VGSHELL_RUNNER_PID, undefined);
        }
        mode("codex-app", "chatgpt");
    };
    await codexEmails(Accounts);
    for (const [file, name, needle, replacement] of [
        ["backend/Accounts.js", "email-kept", "            item.email = email;\n", ""],
        ["bin/lib/codex-account.js", "refresh-token", "{ refreshToken: false }", "{ refreshToken: true }"],
        ["backend/Accounts.js", "email-deadline", "deadlineMs: deadlineMs ?? EMAIL_MS,", "deadlineMs: 60000,"]]) {
        await mutant(file, name, needle, replacement, folder => codexEmails(judgeIn(folder)));
        mode("codex-app", "chatgpt");
        controls++;
    }
    cases++;
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
        ["marker-first", "const result = this.run(row.command[0], row.command.slice(1), { [harness(row.id).variable]: candidate.directory }, timeout);",
            "fs.lstatSync(path.join(candidate.directory, harness(row.id).marker));\n        const result = this.run(row.command[0], row.command.slice(1), { [harness(row.id).variable]: candidate.directory }, timeout);",
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
        { CLAUDE_CONFIG_DIR: "value-CLAUDE_CONFIG_DIR", CODEX_HOME: "value-CODEX_HOME", COPILOT_HOME: "value-COPILOT_HOME",
            PI_CODING_AGENT_DIR: "value-PI_CODING_AGENT_DIR" });
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
        for (const state of ["signed-in", "found", "unchecked", "verifying", "verified", "locked", "unavailable"])
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
        assert.notEqual(hintOf("unchecked", "cli"), hintOf("found", "cli"), "unchecked and found read apart");
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
