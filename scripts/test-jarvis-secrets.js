#!/usr/bin/env node
// loads: shell/plugins/vgs.jarvis/* -- the controls read the plugin files they list
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const cp = require("node:child_process");
const { standins, ref } = require("./fixtures/jarvis/keys-world.js");
const tree = path.resolve(__dirname, "..");
const backend = path.join(tree, "shell/plugins/vgs.jarvis/backend");
const source = fs.readFileSync(path.join(backend, "Secrets.js"), "utf8");
const key = "test-key-must-stay-private";

function inside() {
    const api = require(path.join(backend, "Secrets.js"));
    const env = {};
    for (const name of ["PATH", "HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_DATA_HOME",
        "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS"]) env[name] = process.env[name];
    const root = process.env.JARVIS_TEST_ROOT;
    const directory = path.join(env.XDG_STATE_HOME, "vgshell/jarvis");
    const store = new api.Secrets(directory, { ...env, OPENAI_API_KEY: key, VGSHELL_RUNNER_PID: "123" });
    let cases = 0, controls = 0;
    const safe = value => assert.equal(String(value).includes(key), false, "no key in files, logs, argv, env or status");
    const calls = name => fs.existsSync(path.join(env.XDG_STATE_HOME, name))
        ? fs.readFileSync(path.join(env.XDG_STATE_HOME, name), "utf8") : "";
    const mode = value => fs.writeFileSync(path.join(env.XDG_STATE_HOME, "bus-mode"), value);
    function rejects(fn, expected) { assert.throws(fn, expected); cases++; }
    assert.deepEqual(store.references(), []);
    assert.equal(store.revision(), "", "no list has no revision");
    assert.equal(calls("secret-calls"), "");
    store.remember(ref);
    assert.deepEqual(store.references(), [ref]);
    assert.equal(fs.statSync(store.file).mode & 0o777, 0o600);
    for (const value of ["present", "locked", "absent", "failed", "junk"]) {
        mode(value);
        const row = store.rows()[0];
        assert.equal(row.value, ["failed", "junk"].includes(value) ? "unavailable" : value);
        safe(JSON.stringify(row));
        cases++;
    }
    assert.equal(calls("secret-calls"), "", "presence must not call secret-tool");
    const args = JSON.parse(calls("bus-calls").trim().split("\n")[0]);
    assert.deepEqual(args, ["--user", "--auto-start=no", "--allow-interactive-authorization=no",
        "--timeout=5", "--json=short", "call", "org.freedesktop.secrets", "/org/freedesktop/secrets",
        "org.freedesktop.Secret.Service", "SearchItems", "a{ss}", "4",
        "service", "vgs-jarvis", "provider", "fixture", "account", "test", "origin", "https://fixture.invalid"]);
    function normalized(copy) {
        for (const [input, expected] of [[[65, 66], [65, 66]], [[65, 66, 10], [65, 66]],
            [[65, 10, 66, 10], [65, 10, 66]], [[65, 13, 10], [65, 13]]]) {
            const owner = new copy.Secrets(directory, env);
            const bytes = Buffer.from(input);
            owner.run = () => bytes;
            const value = owner.lookup(ref);
            assert.deepEqual([...value], expected);
            assert.equal(value.length, expected.length);
            assert.equal(bytes.every(byte => byte === 0), true);
            value.fill(0);
        }
    }
    normalized(api); cases++;
    const lookedUp = store.lookup(ref);
    assert.equal(lookedUp.toString(), key);
    lookedUp.fill(0);
    const receipt = JSON.parse(calls("secret-calls").trim().split("\n")[0]);
    assert.deepEqual(receipt.argv, ["lookup", "service", "vgs-jarvis", "provider", "fixture",
        "account", "test", "origin", "https://fixture.invalid"]);
    assert.equal(receipt.env.OPENAI_API_KEY, undefined);
    assert.equal(receipt.env.VGSHELL_RUNNER_PID, undefined);
    safe(calls("secret-calls"));
    const external = { ...ref, account: "external", attributes: { application: "other-tool", id: "chosen-item" } };
    store.remember(external);
    assert.deepEqual(store.references()[1], external);
    assert.equal(store.lookup(external).toString(), key);
    // The key reaches secret-tool on stdin alone, never in its argv, and
    // the buffer is zeroed after the write, refused or not.
    for (const [, bytes, expected] of [["empty", Buffer.alloc(0), /store=empty/],
        ["oversize", Buffer.alloc(8193, 65), /store=oversize/], ["not a buffer", key, /store=empty/]])
        rejects(() => store.addKey(ref, bytes, "replace"), expected);
    const oversize = Buffer.alloc(8193, 65);
    rejects(() => store.addKey(ref, oversize, "replace"), /store=oversize/);
    assert.equal(oversize.every(byte => byte === 0), true, "a refused key is zeroed");
    const pasted = Buffer.from(key);
    const beforeStore = calls("secret-calls");
    store.addKey(ref, pasted, "replace");
    assert.equal(pasted.every(byte => byte === 0), true, "a stored key is zeroed");
    const stored = calls("secret-calls").slice(beforeStore.length).trim().split("\n").map(JSON.parse);
    assert.deepEqual(stored.map(call => call.argv), [["store", "--label=Jarvis provider key", "service", "vgs-jarvis",
        "provider", "fixture", "account", "test", "origin", "https://fixture.invalid"]]);
    safe(calls("secret-calls"));
    cases++;
    // A key stored again under its name keeps its reference and gives the
    // list a new revision, which ends the engine's refused-key hold.
    const revision = store.revision();
    assert.equal(store.revision(), revision, "a read keeps the revision");
    const referencesBefore = JSON.stringify(store.references());
    store.addKey(ref, Buffer.from(key), "replace");
    assert.equal(JSON.stringify(store.references()), referencesBefore, "the stored-again key keeps its reference");
    assert.notEqual(store.revision(), revision, "a key stored again gives a new revision");
    cases++;

    const referenceCases = [
        [{ ...ref, key }, /reference=shape/],
        [{ ...ref, provider: "" }, /reference=identity/],
        [{ ...ref, origin: "https://fixture.invalid/path" }, /reference=origin/],
        [{ ...ref, origin: "https://user:password@fixture.invalid" }, /reference=origin/],
        [{ ...ref, attributes: {} }, /reference=attributes/],
        [{ ...ref, attributes: { "--option": "x" } }, /reference=attributes/],
        [{ ...ref, attributes: { id: "x\nsecret" } }, /reference=attributes/]
    ];
    for (const [input, expected] of referenceCases) rejects(() => store.remember(input), expected);
    const clean = fs.readFileSync(store.file);
    const metadataCases = [
        ["junk", /references=json/], [JSON.stringify([ref, ref]), /references=duplicate/],
        [JSON.stringify(Array(33).fill(ref)), /references=limit/],
        [" ".repeat(65537), /references=size/], [JSON.stringify([{ ...ref, key }]), /reference=shape/]
    ];

    // The reference the key editor's save stores (KeyEditor.qml runs
    // keys.js add-key new|replace PROVIDER NAME with the key on stdin): the chosen
    // provider's own origin.
    const added = (id, origin, account = "test") => ({ provider: id, account, origin,
        attributes: { service: "vgs-jarvis", provider: id, account, origin } });
    const openai = added("openai", "https://api.openai.com");
    const plugin = path.dirname(backend);
    // One save as the editor runs it: keys.js add-key in MODE, new for an
    // Add and replace for an Edit, with the key and the field's line feed
    // on stdin, and the store calls it made.
    function save(folder = plugin, id = "openai", account = "test", input = key + "\n", mode = "new") {
        const before = calls("secret-calls");
        const result = cp.spawnSync("node", [path.join(folder, "backend/keys.js"), "add-key", mode, id, account], { env, input, encoding: "utf8" });
        result.storageCalls = calls("secret-calls").slice(before.length).trim().split("\n").filter(Boolean)
            .map(JSON.parse).filter(call => call.argv[0] === "store");
        return result;
    }
    // A stored key: one store call, the keyed result alone on stdout, no key
    // in any output, and the reference bound to the provider's origin.
    function goodSave(result, expected = openai) {
        assert.equal(result.error, undefined);
        assert.deepEqual([result.status, result.stdout, result.stderr], [0, "jarvis-keys: stored=libsecret\n", ""]);
        assert.equal(result.storageCalls.length, 1, "this save stores one key");
        safe(result.stdout + result.stderr);
        assert.deepEqual(store.references().find(item => item.provider === expected.provider && item.account === expected.account), expected);
    }
    function refusedSave(expected, folder = plugin) {
        const before = calls("secret-calls");
        const metadata = fs.readFileSync(store.file);
        const result = save(folder);
        assert.equal(result.error, undefined);
        // A full or oversized list exits 6, which the editor words; any
        // other refusal exits 1 (keys.js EXIT_STATUS).
        assert.equal(result.status, /limit|size/.test(expected.source) ? 6 : 1, result.stdout + result.stderr);
        assert.match(result.stderr, expected);
        assert.equal(calls("secret-calls"), before, "invalid metadata must not call secret-tool");
        assert.deepEqual(fs.readFileSync(store.file), metadata, "refusal must preserve reference metadata");
        safe(result.stdout + result.stderr);
    }
    for (const [data, expected] of metadataCases) {
        fs.writeFileSync(store.file, data);
        rejects(() => store.references(), expected);
        refusedSave(expected);
    }
    fs.writeFileSync(store.file, clean);
    fs.renameSync(store.file, store.file + ".saved");
    fs.symlinkSync(store.file + ".saved", store.file);
    rejects(() => store.references(), /references=read-failed/);
    refusedSave(/references=read-failed/);
    assert.equal(fs.lstatSync(store.file).isSymbolicLink(), true);
    fs.unlinkSync(store.file);
    fs.renameSync(store.file + ".saved", store.file);
    const full = Array.from({ length: 32 }, (_, index) => ({ ...ref, account: String(index) }));
    fs.writeFileSync(store.file, JSON.stringify(full));
    refusedSave(/references=limit/);
    const replacement = { ...full[0], attributes: { id: "replacement" } };
    store.remember(replacement);
    assert.equal(store.references().length, 32, "a full list permits an existing identity update");
    assert.deepEqual(store.references()[0], replacement);
    fs.writeFileSync(store.file, JSON.stringify([...full.slice(1), openai]));
    goodSave(save(plugin, "openai", "test", key + "\n", "replace"));
    assert.equal(store.references().length, 32, "a full list permits replacing an existing identity");
    fs.writeFileSync(store.file, clean);
    cases += 3;
    goodSave(save());
    safe(calls("secret-calls"));
    const snapshot = fs.readFileSync(store.file);
    fs.writeFileSync(path.join(env.XDG_STATE_HOME, "store-fail"), "");
    const failed = save(plugin, "openai", "test", key + "\n", "replace");
    assert.deepEqual([failed.status, failed.stdout, failed.stderr], [1, "", "jarvis-keys: secret-tool=failed\n"]);
    safe(failed.stdout + failed.stderr);
    assert.deepEqual(fs.readFileSync(store.file), snapshot, "failed storage does not change references");
    fs.unlinkSync(path.join(env.XDG_STATE_HOME, "store-fail"));
    // An Add never overwrites a stored key: keys.js refuses a key the list
    // holds before the keyring, exit 8, which the editor words, and an Edit
    // refuses a key Jarvis did not store itself.
    const modes = folder => {
        const listed = fs.readFileSync(store.file);
        try {
            store.remember({ provider: "openai", account: "foreign", origin: "https://api.openai.com", attributes: { application: "other-tool", id: "x" } });
            for (const [label, mode, account, status, reason] of [
                ["an Add of a stored key", "new", "test", 8, "store=exists"],
                ["an Add of another app's key", "new", "foreign", 8, "store=exists"],
                ["an Edit of no stored key", "replace", "nobody", 1, "store=absent"],
                ["an Edit of another app's key", "replace", "foreign", 1, "store=absent"]
            ]) {
                const before = calls("secret-calls");
                const metadata = fs.readFileSync(store.file);
                const result = save(folder, "openai", account, key + "\n", mode);
                assert.deepEqual([result.status, result.stdout, result.stderr], [status, "", "jarvis-keys: " + reason + "\n"], label);
                assert.equal(calls("secret-calls"), before, label + ": no keyring call");
                assert.deepEqual(fs.readFileSync(store.file), metadata, label + ": the list stays");
                cases++;
            }
            goodSave(save(folder, "openai", "test", key + "\n", "replace"));
            cases++;
        } finally { fs.writeFileSync(store.file, listed); }
    };
    modes(plugin);

    // A save binds the key to the chosen provider's own origin; keys.js
    // refuses any other provider before the keyring, as a typed id or a
    // custom origin would bind a key no account can use.
    const { PROVIDERS } = require(path.join(plugin, "AccountProviders.js"));
    const chosen = folder => {
        const listed = fs.readFileSync(store.file);
        try {
            goodSave(save(folder, "anthropic"), added("anthropic", "https://api.anthropic.com"));
            // The ElevenLabs voice's key is bound to ElevenLabs's own origin.
            goodSave(save(folder, "elevenlabs"), added("elevenlabs", "https://api.elevenlabs.io"));
        } finally { fs.writeFileSync(store.file, listed); }
    };
    const unknown = folder => {
        for (const id of ["fixture", "custom", "ollama", "cerebras", ""]) {
            const before = calls("secret-calls");
            const metadata = fs.readFileSync(store.file);
            const result = save(folder, id);
            assert.deepEqual([result.status, result.stderr], [1, "jarvis-keys: provider=unknown\n"], "provider [" + id + "]");
            assert.equal(calls("secret-calls"), before);
            assert.deepEqual(fs.readFileSync(store.file), metadata);
            cases++;
        }
    };
    // The editor's Provider choices are the providers keys.js stores, each
    // with its key page, the one link that opens the browser.
    const offers = folder => {
        const { keyProviderChoices } = require(path.join(folder, "AccountProviders.js"));
        const ids = keyProviderChoices().map(choice => choice.value);
        for (const id of ids) {
            const row = PROVIDERS.find(item => item.id === id);
            assert.ok(row && (row.kind === "speech-key" || row.kind === "key" && row.probe.model !== ""), "offered [" + id + "]");
        }
        for (const id of ["openai", "elevenlabs"]) assert.ok(ids.includes(id), "offered [" + id + "]");
        assert.equal(ids.includes("cerebras"), false, "offered [cerebras]");
        assert.deepEqual(keyProviderChoices().find(choice => choice.value === "openai").link,
            { text: "OpenAI key page", url: "https://platform.openai.com/api-keys" });
        cases++;
    };
    // A save takes the key out of the last Check's record, so a replaced
    // key reads Not checked yet; a removal takes its record too, and a
    // record file the judge refuses reads unreadable, never unchecked.
    const checked = folder => {
        const judge = new (require(path.join(folder, "backend/Secrets.js")).Secrets)(directory, env);
        const listed = fs.readFileSync(store.file);
        try {
            fs.writeFileSync(store.file, JSON.stringify([ref, openai]));
            judge.recordCheck(openai, { kind: "working" }, 1795000000000);
            judge.recordCheck(ref, { kind: "failed", reason: "http-401" }, 1795000000001);
            const held = judge.checks();
            assert.equal(held.kind, "read");
            assert.deepEqual(held.checks.get(judge.identity(openai)), { kind: "working", at: 1795000000000 });
            assert.deepEqual(held.checks.get(judge.identity(ref)), { kind: "failed", reason: "http-401", at: 1795000000001 });
            goodSave(save(folder, "openai", "test", key + "\n", "replace"));
            assert.equal(judge.checks().checks.has(judge.identity(openai)), false, "a replaced key keeps no Check");
            assert.equal(judge.checks().checks.has(judge.identity(ref)), true, "another key keeps its Check");
            mode("present");
            judge.removeKey(ref.provider, ref.account);
            assert.equal(judge.checks().checks.size, 0, "a removed key keeps no Check");
            for (const junk of ["junk", JSON.stringify([{ ...openai, kind: "working" }]), JSON.stringify([{ provider: "openai", account: "test",
                origin: "https://api.openai.com", kind: "working", at: 1, key }])]) {
                fs.writeFileSync(judge.checksFile, junk);
                assert.deepEqual(judge.checks(), { kind: "unreadable" }, "refused record [" + junk.slice(0, 20) + "]");
            }
            fs.rmSync(judge.checksFile);
            assert.deepEqual([judge.checks().kind, judge.checks().checks.size], ["read", 0], "no file has no checks");
            cases += 4;
        } finally {
            fs.writeFileSync(store.file, listed);
            fs.rmSync(judge.checksFile, { force: true });
            mode("present");
        }
    };
    // Remove takes the chosen key out of the keyring and out of Jarvis's
    // key list, by its provider and name alone. The fake keyring holds one
    // item, which busctl answers for: secret-tool clear takes it out. A key
    // the keyring already lost only leaves the list, and an item another
    // program stored is only forgotten.
    const removal = folder => {
        const listed = fs.readFileSync(store.file);
        const stored = [ref, external, openai];
        const run = (...args) => cp.spawnSync("node", [path.join(folder, "backend/keys.js"), ...args], { env, encoding: "utf8" });
        const keyring = before => calls("secret-calls").slice(before.length).trim().split("\n").filter(Boolean)
            .map(line => JSON.parse(line).argv);
        const clear = ["clear", "service", "vgs-jarvis", "provider", "openai", "account", "test", "origin", "https://api.openai.com"];
        try {
            for (const [label, bus, target, answer, argv, after] of [
                ["a stored key", "present", openai, "libsecret", [clear], "absent"],
                ["a key the keyring lost", "absent", openai, "libsecret", [], "absent"],
                ["another program's item", "present", external, "reference", [], "present"]
            ]) {
                fs.writeFileSync(store.file, JSON.stringify(stored));
                mode(bus);
                const before = calls("secret-calls");
                const result = run("remove-key", target.provider, target.account);
                assert.deepEqual([result.status, result.stdout, result.stderr], [0, "jarvis-keys: removed=" + answer + "\n", ""], label);
                assert.deepEqual(keyring(before), argv, label + ": keyring calls");
                assert.equal(store.presence(target).value, after, label + ": keyring");
                assert.deepEqual(store.references(), stored.filter(item => item !== target), label + ": key list");
                cases++;
            }
            fs.writeFileSync(store.file, JSON.stringify(stored));
            mode("present");
            let before = calls("secret-calls");
            const absent = run("remove-key", "openai", "nobody");
            assert.deepEqual([absent.status, absent.stdout, absent.stderr], [1, "", "jarvis-keys: key=unknown\n"]);
            assert.deepEqual([keyring(before), store.references()], [[], stored], "an unknown key changes nothing");
            cases++;
            // A locked keyring keeps its item whatever clear exits with:
            // the removal fails, the key stays listed and no line says
            // removed.
            mode("locked");
            before = calls("secret-calls");
            const locked = run("remove-key", "openai", "test");
            assert.deepEqual([locked.status, locked.stdout, locked.stderr], [1, "", "jarvis-keys: key=locked\n"]);
            assert.deepEqual([keyring(before), store.presence(openai).value, store.references()], [[clear], "locked", stored], "a locked key stays");
            cases++;
        } finally {
            fs.writeFileSync(store.file, listed);
            mode("present");
        }
    };
    // The editor words these refusals by keys.js's exit status
    // (AccountStatus.saveFailure); any other refusal exits 1.
    const statuses = folder => {
        const before = calls("secret-calls");
        try {
            for (const [label, list, input, account, status, reason] of [
                ["an empty field", clean, "\n", "test", 3, "store=empty"],
                ["a paste too long", clean, "A".repeat(8193), "test", 4, "store=oversize"],
                ["a name too long", clean, key, "n".repeat(81), 5, "reference=identity"],
                ["a full list", JSON.stringify(full), key, "new", 6, "references=limit"],
                ["a list too large", " ".repeat(65537), key, "new", 6, "references=size"],
                ["an unreadable list", "junk", key, "new", 1, "references=json"]
            ]) {
                fs.writeFileSync(store.file, list);
                const result = save(folder, "openai", account, input);
                assert.deepEqual([result.status, result.stderr], [status, "jarvis-keys: " + reason + "\n"], label);
                cases++;
            }
        } finally { fs.writeFileSync(store.file, clean); }
        assert.equal(calls("secret-calls"), before, "a refusal stores nothing");
    };
    statuses(plugin);
    // The editor's save starts keys.js before the key arrives on its pipe,
    // so keys.js may wait on it. That wait blocks in the kernel: the
    // process's utime + stime (/proc/PID/stat, clock ticks) across 0.6 s of
    // the wait stays under 0.2 s. This probe on Node v26.11.1, 2026-10-20:
    // 0.00 s blocking, 0.60 s for a read loop that retries EAGAIN.
    const waited = folder => {
        const result = cp.spawnSync("python3", ["-c", `
import os, subprocess, sys, time
child = subprocess.Popen(["node", sys.argv[1], "add-key", "new", "openai", "waited"], stdin=subprocess.PIPE,
                         stdout=subprocess.DEVNULL, stderr=sys.stderr)
def cpu():
    fields = open(f"/proc/{child.pid}/stat").read().rsplit(")", 1)[1].split()
    return (int(fields[11]) + int(fields[12])) / os.sysconf("SC_CLK_TCK")
time.sleep(0.6)  # past node's start, into the read
before = cpu()
time.sleep(0.6)
spent = cpu() - before
child.communicate((sys.argv[2] + "\\n").encode(), timeout=10)
print(f"{spent:.2f} {child.returncode}")
`, path.join(folder, "backend/keys.js"), key], { env, encoding: "utf8", timeout: 20000 });
        fs.writeFileSync(store.file, clean);
        assert.equal(result.status, 0, result.stderr);
        const [spent, status] = result.stdout.trim().split(" ").map(Number);
        assert.equal(status, 0, "the key is stored once it arrives: " + result.stderr);
        assert.ok(spent < 0.2, "the wait for the key takes no CPU: " + spent + " s");
        cases++;
    };
    waited(plugin);
    chosen(plugin);
    unknown(plugin);
    offers(plugin);
    checked(plugin);
    removal(plugin);

    // Removing each stand-in must break its own behavioral assertion.
    for (const name of ["secret-tool", "busctl"]) {
        const file = path.join(env.PATH.split(":")[0], name);
        fs.renameSync(file, file + ".off");
        try {
            if (name === "busctl") {
                mode("present");
                assert.equal(store.rows()[0].value, "unavailable");
            } else assert.notEqual(save().status, 0, name + " cannot fall back to the host");
        } finally { fs.renameSync(file + ".off", file); }
        cases++;
    }
    function mutate(name, needle, replacement, check) {
        assert.equal(source.split(needle).length - 1, 1, name + " mutation match");
        const file = path.join(root, name + ".js");
        fs.writeFileSync(file, source.replace(needle, replacement));
        assert.notEqual(fs.readFileSync(file, "utf8"), source);
        const copy = require(file);
        assert.throws(() => check(copy), assert.AssertionError, name + " must fail its assertion");
        controls++;
    }
    mutate("revision", 'return stat.ino + ":" + stat.mtimeNs;', 'return "fixed";', copy => {
        const copied = new copy.Secrets(directory, env);
        const before = copied.revision();
        copied.remember(ref);
        assert.notEqual(copied.revision(), before);
    });
    mutate("shape", "fail(\"reference=shape\");", "void 0;",
        copy => assert.throws(() => copy.reference({ ...ref, key }), /reference=shape/));
    mutate("identity", 'fail("reference=identity");', "void 0;",
        copy => assert.throws(() => copy.reference({ ...ref, account: "" }), /reference=identity/));
    mutate("origin", 'fail("reference=origin");\n    const attrs', 'void 0;\n    const attrs',
        copy => assert.throws(() => copy.reference({ ...ref, origin: "https://fixture.invalid/path" }), /reference=origin/));
    mutate("attributes", 'fail("reference=attributes");\n    return', 'void 0;\n    return',
        copy => assert.throws(() => copy.reference({ ...ref, attributes: { "--option": "x" } }), /reference=attributes/));
    mutate("attribute-count", 'fail("reference=attributes");\n    for', 'void 0;\n    for',
        copy => assert.throws(() => copy.reference({ ...ref, attributes: {} }), /reference=attributes/));
    for (const [name, needle, replacement, data, reason] of [
        ["size", "if (!stat.isFile() || stat.size > MAX_BYTES) fail(\"references=size\");", "void 0;", " ".repeat(65537), /references=size/],
        ["count", 'if (!Array.isArray(values) || values.length > MAX_REFERENCES) fail("references=limit");', "void 0;", JSON.stringify(Array(33).fill(ref)), /references=limit/],
        ["duplicates", 'fail("references=duplicate");', "void 0;", JSON.stringify([ref, ref]), /references=duplicate/],
        ["remember-limit", 'if (refs.length > MAX_REFERENCES) fail("references=limit");',
            'if (false) fail("references=limit");', null, /references=limit/]
    ]) {
        mutate(name, needle, replacement, copy => {
            if (data !== null) {
                fs.writeFileSync(store.file, data);
                try { assert.throws(() => new copy.Secrets(directory, env).references(), reason); }
                finally { fs.writeFileSync(store.file, clean); }
            } else {
                fs.writeFileSync(store.file, JSON.stringify(Array.from({ length: 32 }, (_, index) =>
                    ({ ...ref, account: String(index) }))));
                try { assert.throws(() => new copy.Secrets(directory, env).remember(ref), reason); }
                finally { fs.writeFileSync(store.file, clean); }
            }
        });
    }
    mutate("env", "this.env = childEnvironment(env);", "this.env = env;",
        copy => safe(JSON.stringify(new copy.Secrets(directory, { ...env, OPENAI_API_KEY: key }).env)));
    mutate("presence", '"SearchItems", "a{ss}"', '"GetSecrets", "a{ss}"',
        copy => assert.equal(new copy.Secrets(directory, env).rows()[0].value, "present"));
    mutate("key-final-lf", 'key.at(-1) === 10 ? 1 : 0', 'false ? 1 : 0', normalized);
    mutate("key-buffer-zero", 'const value = Buffer.from(key.subarray(0, size));\n        key.fill(0);',
        'const value = Buffer.from(key.subarray(0, size));', normalized);
    mutate("lookup", '["lookup", ...this.attributes(ref)]', '["search", ...this.attributes(ref)]',
        copy => assert.doesNotThrow(() => new copy.Secrets(directory, env).lookup(ref)));
    mutate("error-output", 'fail(command + "=" + cause);',
        'fail(result.stderr.toString());',
        copy => {
            fs.writeFileSync(path.join(env.XDG_STATE_HOME, "store-fail"), "");
            try { new copy.Secrets(directory, env).run("secret-tool", ["unknown"]); }
            catch (error) { safe(error.message); }
            finally { fs.unlinkSync(path.join(env.XDG_STATE_HOME, "store-fail")); }
        });
    // The actual CLI path, not a reimplementation, sees these mutations.
    const mutant = path.join(root, "cli-copy");
    fs.mkdirSync(path.join(mutant, "backend"), { recursive: true });
    for (const file of ["backend/keys.js", "backend/Secrets.js", "AccountProviders.js"])
        fs.copyFileSync(path.join(plugin, file), path.join(mutant, file));
    for (const [name, file, needle, replacement, check] of [
        ["store-output", "backend/Secrets.js", 'output.fill(0);\n            this.remember(own);', 'process.stdout.write(output);\n            output.fill(0);\n            this.remember(own);', folder => goodSave(save(folder))],
        ["store-call", "backend/keys.js", "store.addKey(ref, pastedKey(), mode);", "void ref;", folder => goodSave(save(folder))],
        ["replaced-check", "backend/Secrets.js", "this.recordCheck(own, null, 0);", "void 0;", checked],
        ["removal-leaves-keyring-item", "backend/Secrets.js", 'this.run("secret-tool", ["clear", ...this.attributes(ref)]).fill(0);', "void 0;", removal],
        ["removal-trusts-clear", "backend/Secrets.js", 'if (left !== "absent") fail("key=" + left);', "void left;", removal],
        ["removal-leaves-reference", "backend/Secrets.js", "refs.filter(item => item !== ref)", "refs", removal],
        ["removal-clears-absent", "backend/Secrets.js", 'if (own && this.presence(ref).value !== "absent")', "if (own)", removal],
        ["removal-clears-foreign", "backend/Secrets.js", "return sorted(ref.attributes) === sorted(ownReference(ref.provider, ref.account, ref.origin).attributes);", "return true;", folder => { removal(folder); modes(folder); }],
        ["add-overwrites", "backend/Secrets.js", 'if (mode === "new" && held !== undefined) fail("store=exists");', "", modes],
        ["replace-takes-any", "backend/Secrets.js", 'if (mode === "replace" && (held === undefined || !this.isOwn(held))) fail("store=absent");', "", modes],
        ["exists-unworded", "backend/keys.js", '"store=exists": 8', '"store=exists-unworded": 8', modes],
        ["removal-cli", "backend/keys.js", "store.removeKey(process.argv[3], process.argv[4])", "true", removal],
        ["stdin-stream", "backend/keys.js", "if (tty.isatty(0))", "if (process.stdin.isTTY)", waited],
        ["empty-status", "backend/keys.js", '"store=empty": 3,', "", statuses],
        ["name-status", "backend/keys.js", '"reference=identity": 5,', "", statuses],
        ["unknown-provider", "backend/keys.js", 'if (row === undefined) throw new Error("jarvis-keys: provider=unknown");', "", unknown],
        ["provider-origin", "backend/keys.js", "ownReference(row.id, account, row.origin)", 'ownReference(row.id, account, "https://api.openai.com")', chosen],
        ["model-providers", "AccountProviders.js", 'return row.kind === "key" && modelProvider(row);', 'return row.kind === "key";', folder => { unknown(folder); offers(folder); }],
        ["speech-key-stored", "AccountProviders.js", 'return modelKeyProvider(row) || row.kind === "speech-key";', "return modelKeyProvider(row);", chosen]
    ]) {
        const original = fs.readFileSync(path.join(plugin, file), "utf8");
        assert.equal(original.split(needle).length - 1, 1, name + " matches");
        const changed = original.replace(needle, replacement);
        assert.notEqual(changed, original, name + " changes its file");
        fs.writeFileSync(path.join(mutant, file), changed);
        try { assert.throws(() => check(mutant), assert.AssertionError, name + " must turn red"); }
        finally { fs.writeFileSync(path.join(mutant, file), original); }
        controls++;
    }
    // The EAGAIN retry this replaced spins while the editor's save waits.
    {
        const original = fs.readFileSync(path.join(plugin, "backend/keys.js"), "utf8");
        const spinning = original.replace("if (tty.isatty(0))", "if (process.stdin.isTTY)")
            .replace("catch {\n            chunk.fill(0);", "catch (error) {\n            if (error.code === \"EAGAIN\") continue;\n            chunk.fill(0);");
        assert.equal(spinning.includes("EAGAIN") && spinning.includes("process.stdin.isTTY"), true, "spin mutation matches");
        fs.writeFileSync(path.join(mutant, "backend/keys.js"), spinning);
        try { assert.throws(() => waited(mutant), /takes no CPU/, "an EAGAIN retry must turn red"); }
        finally { fs.writeFileSync(path.join(mutant, "backend/keys.js"), original); }
        controls++;
    }
    function walk(folder) {
        for (const item of fs.readdirSync(folder, { withFileTypes: true })) {
            const file = path.join(folder, item.name);
            if (item.isDirectory()) walk(file);
            else if (item.isFile()) safe(fs.readFileSync(file));
        }
    }
    // Fixture source and mutants contain the sentinel by design. The actual
    // state, account HOME, runtime and cache output directories must not.
    for (const folder of [env.XDG_STATE_HOME, env.HOME, env.XDG_RUNTIME_DIR]) walk(folder);
    console.log("test-jarvis-secrets: ok cases=" + cases + " controls=" + controls);
}

if (process.argv[2] === "--inside") inside();
else {
    fs.mkdirSync(os.tmpdir(), { recursive: true });
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "jk-"));
    try {
        standins(path.join(root, "standins"));
        const result = cp.spawnSync("/bin/bash", [path.join(tree, "scripts/lib/jarvis-env.sh"),
            path.join(root, "standins"), "--", "node", __filename, "--inside"], {
            env: { PATH: "/usr/bin:/bin", HOME: root }, encoding: "utf8", timeout: 60000 });
        process.stdout.write(result.stdout || "");
        process.stderr.write(result.stderr || "");
        if (result.error) throw result.error;
        process.exitCode = result.status ?? 1;
    } finally { fs.rmSync(root, { recursive: true, force: true }); }
}
