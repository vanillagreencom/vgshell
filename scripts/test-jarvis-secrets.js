#!/usr/bin/env node
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
        rejects(() => store.addKey(ref, bytes), expected);
    const oversize = Buffer.alloc(8193, 65);
    rejects(() => store.addKey(ref, oversize), /store=oversize/);
    assert.equal(oversize.every(byte => byte === 0), true, "a refused key is zeroed");
    const pasted = Buffer.from(key);
    const beforeStore = calls("secret-calls");
    store.addKey(ref, pasted);
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
    store.addKey(ref, Buffer.from(key));
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

    // Add key's gum: choose answers with the provider in gum-provider, as
    // gum 2.0.2 prints an option's value under --label-delimiter, and fails
    // on a provider it was not offered; it keeps the lines it was offered in
    // gum-choose. input answers the key's name.
    fs.writeFileSync(path.join(env.PATH.split(":")[0], "gum"), `#!/usr/bin/env node
const fs = require("node:fs"), path = require("node:path");
const state = process.env.XDG_STATE_HOME, args = process.argv.slice(2);
fs.appendFileSync(path.join(state, "gum-calls"), JSON.stringify(args) + "\\n");
if (args[0] === "input" && args.includes("--password")) {
    // gum's masked box: it asks and reads on the terminal with echo off and
    // prints the value with a line feed.
    const box = require("node:child_process").spawnSync("python3", ["-c",
        "import getpass, sys; sys.stdout.write(getpass.getpass('Password: ') + '\\\\n')"], { stdio: "inherit" });
    process.exit(box.status ?? 1);
}
if (args[0] === "input") { console.log("test"); process.exit(0); }
if (args[0] !== "choose") process.exit(0);
const delimiter = args.find(arg => arg.startsWith("--label-delimiter="))?.slice("--label-delimiter=".length);
const wanted = fs.readFileSync(path.join(state, "gum-provider"), "utf8").trim();
const offered = fs.readFileSync(0, "utf8");
fs.writeFileSync(path.join(state, "gum-choose"), offered);
const values = offered.replace(/\\n$/, "").split("\\n")
    .map(line => delimiter ? line.slice(line.indexOf(delimiter) + delimiter.length) : line);
if (!values.includes(wanted)) process.exit(9);
console.log(wanted);
`, { mode: 0o700 });
    // The world's PATH holds no stty, which vgs_tui_columns reads the
    // terminal's width with.
    const stty = ["/usr/bin/stty", "/bin/stty"].find(file => fs.existsSync(file));
    assert.ok(stty, "stty");
    fs.symlinkSync(stty, path.join(env.PATH.split(":")[0], "stty"));
    const provider = id => fs.writeFileSync(path.join(env.XDG_STATE_HOME, "gum-provider"), id);
    provider("openai");
    // The reference Add key stores: the chosen provider's own origin.
    const added = (id, origin, account = "test") => ({ provider: id, account, origin,
        attributes: { service: "vgs-jarvis", provider: id, account, origin } });
    const openai = added("openai", "https://api.openai.com");
    const log = path.join(env.XDG_STATE_HOME, "vgshell/jarvis/setup.log");
    const logged = () => fs.existsSync(log) ? fs.readFileSync(log, "utf8") : "";
    function tui(folder = path.dirname(backend), script = path.join(tree, "shell/plugins/vgs.jarvis/tui/add-key.sh"),
        extra = []) {
        fs.rmSync(log, { force: true });
        fs.rmSync(path.join(env.XDG_STATE_HOME, "gum-calls"), { force: true });
        const before = calls("secret-calls");
        const result = cp.spawnSync("python3", [path.join(tree, "scripts/fixtures/jarvis/key-tui.py"),
            script, path.join(tree, "bin/lib/tui.sh"), folder, ...extra], { env, encoding: "utf8", timeout: 15000 });
        result.storageCalls = calls("secret-calls").slice(before.length).trim().split("\n").filter(Boolean)
            .map(JSON.parse).filter(call => call.argv[0] === "store");
        return result;
    }
    // Keyed lines go to the log; the screen holds none.
    function goodTui(result, expected = openai) {
        assert.equal(result.error, undefined);
        assert.equal(result.status, 0, result.stdout + result.stderr);
        assert.equal(result.storageCalls.length, 1, "this invocation stores one key");
        assert.match(result.stdout, /Password: /);
        assert.match(logged(), /jarvis-keys: stored=libsecret/);
        assert.doesNotMatch(result.stdout, /jarvis-keys:/);
        safe(result.stdout + result.stderr + logged());
        assert.deepEqual(store.references().find(item => item.provider === expected.provider && item.account === "test"), expected);
    }
    function refusedTui(expected, folder = path.dirname(backend)) {
        const before = calls("secret-calls");
        const metadata = fs.readFileSync(store.file);
        const result = tui(folder, undefined, ["--expect-metadata-refusal"]);
        assert.equal(result.error, undefined);
        assert.equal(result.status, 1, result.stdout + result.stderr);
        assert.match(logged(), expected);
        assert.doesNotMatch(result.stdout, /jarvis-keys:/);
        assert.doesNotMatch(result.stdout, /Password: /, "metadata must fail before prompting for a key");
        assert.equal(calls("secret-calls"), before, "invalid metadata must not call secret-tool");
        assert.deepEqual(fs.readFileSync(store.file), metadata, "refusal must preserve reference metadata");
        safe(result.stdout + result.stderr);
    }
    for (const [data, expected] of metadataCases) {
        fs.writeFileSync(store.file, data);
        rejects(() => store.references(), expected);
        refusedTui(expected);
    }
    fs.writeFileSync(store.file, clean);
    fs.renameSync(store.file, store.file + ".saved");
    fs.symlinkSync(store.file + ".saved", store.file);
    rejects(() => store.references(), /references=read-failed/);
    refusedTui(/references=read-failed/);
    assert.equal(fs.lstatSync(store.file).isSymbolicLink(), true);
    fs.unlinkSync(store.file);
    fs.renameSync(store.file + ".saved", store.file);
    const full = Array.from({ length: 32 }, (_, index) => ({ ...ref, account: String(index) }));
    fs.writeFileSync(store.file, JSON.stringify(full));
    refusedTui(/references=limit/);
    const replacement = { ...full[0], attributes: { id: "replacement" } };
    store.remember(replacement);
    assert.equal(store.references().length, 32, "a full list permits an existing identity update");
    assert.deepEqual(store.references()[0], replacement);
    fs.writeFileSync(store.file, JSON.stringify([...full.slice(1), openai]));
    goodTui(tui());
    assert.equal(store.references().length, 32, "a full list permits storing an existing identity");
    fs.writeFileSync(store.file, clean);
    cases += 3;
    goodTui(tui());
    safe(calls("secret-calls"));
    const snapshot = fs.readFileSync(store.file);
    fs.writeFileSync(path.join(env.XDG_STATE_HOME, "store-fail"), "");
    const failed = tui();
    assert.equal(failed.status, 1);
    assert.match(logged(), /jarvis-keys: secret-tool=failed/);
    assert.doesNotMatch(failed.stdout, /jarvis-keys:/);
    safe(failed.stdout + failed.stderr + logged());
    assert.deepEqual(fs.readFileSync(store.file), snapshot, "failed storage does not change references");
    fs.unlinkSync(path.join(env.XDG_STATE_HOME, "store-fail"));

    // Add key offers the provider table's key providers and no other, and
    // binds the key to the chosen provider's own origin: the key's name is
    // the one typed answer. keys.js refuses any other provider before the
    // keyring, as a typed id or a custom origin would bind a key no account
    // can use.
    const plugin = path.dirname(backend);
    const { PROVIDERS } = require(path.join(plugin, "AccountProviders.js"));
    const offered = folder => {
        const result = cp.spawnSync("node", [path.join(folder, "backend/keys.js"), "providers", "80"], { env, encoding: "utf8" });
        assert.equal(result.status, 0, result.stderr);
        return result.stdout.trimEnd().split("\n").map(line => line.split("\t")[1]);
    };
    // Every offered row is an API key with a model the engine can use, or
    // the speech key a voice speaks with: openai and the ElevenLabs key are
    // offered, and Cerebras, whose row names no model, is not.
    const keyProviders = folder => {
        const ids = offered(folder);
        for (const id of ids) {
            const row = PROVIDERS.find(item => item.id === id);
            assert.ok(row && (row.kind === "speech-key" || row.kind === "key" && row.probe.model !== ""), "offered [" + id + "]");
        }
        for (const id of ["openai", "elevenlabs"]) assert.ok(ids.includes(id), "offered [" + id + "]");
        assert.equal(ids.includes("cerebras"), false, "offered [cerebras]");
    };
    const chosen = folder => {
        provider("anthropic");
        try {
            goodTui(tui(folder), added("anthropic", "https://api.anthropic.com"));
            const gum = calls("gum-calls").trim().split("\n").map(JSON.parse);
            const inputs = gum.filter(args => args[0] === "input");
            assert.deepEqual(inputs.map(args => args.includes("--password")), [false, true],
                "the key's name is typed, then the key in the masked box");
            // The ElevenLabs voice's key is bound to ElevenLabs's own origin.
            provider("elevenlabs");
            goodTui(tui(folder), added("elevenlabs", "https://api.elevenlabs.io"));
        } finally { provider("openai"); }
    };
    const unknown = folder => {
        for (const id of ["fixture", "custom", "ollama", "cerebras", ""]) {
            const before = calls("secret-calls");
            const metadata = fs.readFileSync(store.file);
            const result = cp.spawnSync("node", [path.join(folder, "backend/keys.js"), "add-key", id, "test"], { env, encoding: "utf8" });
            assert.deepEqual([result.status, result.stderr], [1, "jarvis-keys: provider=unknown\n"], "provider [" + id + "]");
            assert.equal(calls("secret-calls"), before);
            assert.deepEqual(fs.readFileSync(store.file), metadata);
            cases++;
        }
    };
    // The choices fit the terminal: each label within its width after
    // gum's two-column cursor.
    const fitted = (folder, script) => {
        goodTui(tui(folder, script, ["--columns", "40"]));
        const labels = fs.readFileSync(path.join(env.XDG_STATE_HOME, "gum-choose"), "utf8").trimEnd().split("\n")
            .map(line => line.split("\t")[0]);
        assert.ok(labels.length > 0);
        for (const label of labels) assert.ok(Array.from(label).length <= 38, "fits 40 columns: " + label);
    };
    const widthRefused = folder => {
        const result = cp.spawnSync("node", [path.join(folder, "backend/keys.js"), "providers", "0"], { env, encoding: "utf8" });
        assert.deepEqual([result.status, result.stderr], [1, "jarvis-keys: arguments=width\n"]);
    };
    // Remove key takes the chosen key out of the keyring and out of
    // Jarvis's key list, by its provider and name alone. The fake keyring
    // holds one item, which busctl answers for: secret-tool clear takes it
    // out. A key the keyring already lost only leaves the list, and an
    // item another program stored is only forgotten.
    const removal = (folder, script = path.join(plugin, "tui/remove-key.sh")) => {
        const listed = fs.readFileSync(store.file);
        const stored = [ref, external, openai];
        const run = (...args) => cp.spawnSync("node", [path.join(folder, "backend/keys.js"), ...args], { env, encoding: "utf8" });
        const keyring = before => calls("secret-calls").slice(before.length).trim().split("\n").filter(Boolean)
            .map(line => JSON.parse(line).argv);
        const clear = ["clear", "service", "vgs-jarvis", "provider", "openai", "account", "test", "origin", "https://api.openai.com"];
        const gone = (target, label) => {
            assert.deepEqual(store.references(), stored.filter(item => item !== target), label + ": key list");
            assert.equal(run("stored", "80").stdout.includes(target.provider + "\t" + target.account + "\n"), false, label + ": choices");
        };
        try {
            for (const [label, bus, target, answer, argv, after] of [
                ["a stored key", "present", openai, "libsecret", [clear], "absent"],
                ["a key the keyring lost", "absent", openai, "libsecret", [], "absent"],
                ["another program's item", "present", external, "reference", [], "present"]
            ]) {
                fs.writeFileSync(store.file, JSON.stringify(stored));
                mode(bus);
                assert.ok(run("stored", "80").stdout.includes(target.provider + "\t" + target.account + "\n"), label + ": offered");
                const before = calls("secret-calls");
                const result = run("remove-key", target.provider, target.account);
                assert.deepEqual([result.status, result.stdout, result.stderr], [0, "jarvis-keys: removed=" + answer + "\n", ""], label);
                assert.deepEqual(keyring(before), argv, label + ": keyring calls");
                assert.equal(store.presence(target).value, after, label + ": keyring");
                gone(target, label);
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
            // removed, on the verb and on the screen.
            mode("locked");
            before = calls("secret-calls");
            const locked = run("remove-key", "openai", "test");
            assert.deepEqual([locked.status, locked.stdout, locked.stderr], [1, "", "jarvis-keys: key=locked\n"]);
            assert.deepEqual([keyring(before), store.presence(openai).value, store.references()], [[clear], "locked", stored], "a locked key stays");
            provider("openai\ttest");
            const refused = tui(folder, script, ["--no-key"]);
            assert.equal(refused.status, 1, refused.stdout + refused.stderr);
            assert.match(logged(), /jarvis-keys: key=locked/);
            assert.doesNotMatch(logged(), /removed=/);
            assert.deepEqual(store.references(), stored, "the screen keeps a locked key");
            safe(refused.stdout + refused.stderr + logged());
            cases++;
            mode("present");
            // The screen asks once, naming the key, before the verb runs.
            provider("openai\ttest");
            before = calls("secret-calls");
            const result = tui(folder, script, ["--no-key"]);
            assert.equal(result.status, 0, result.stdout + result.stderr);
            const asked = calls("gum-calls").trim().split("\n").map(JSON.parse).filter(args => args[0] === "confirm");
            assert.equal(asked.length, 1, "one question");
            assert.ok(asked[0].at(-1).includes("openai / test"), "the question names the key");
            assert.match(logged(), /jarvis-keys: removed=libsecret/);
            assert.doesNotMatch(result.stdout, /jarvis-keys:/);
            safe(result.stdout + result.stderr + logged());
            assert.deepEqual(keyring(before), [clear], "the screen's keyring calls");
            assert.equal(store.presence(openai).value, "absent", "the screen's keyring");
            gone(openai, "the screen");
            cases++;
        } finally {
            fs.writeFileSync(store.file, listed);
            mode("present");
            provider("openai");
        }
    };
    // The add-voice-key window adds the key of the cloud voice chosen, under
    // the next free name, and refuses a voice that takes no key.
    const voiceKey = (...args) => cp.spawnSync("node", [path.join(plugin, "backend/keys.js"), "voice-key", ...args], { env, encoding: "utf8" });
    const listed = fs.readFileSync(store.file);
    for (const [voice, id, product] of [["realtime", "openai", "OpenAI Realtime"], ["gemini", "gemini", "Gemini Live"],
        ["elevenlabs", "elevenlabs", "ElevenLabs"]]) {
        const fields = () => voiceKey(voice).stdout.trimEnd().split("\t");
        assert.deepEqual([fields()[0], fields()[2], fields()[5]], [id, product, "key 1"], voice);
        const row = PROVIDERS.find(item => item.id === id);
        store.remember(added(id, row.origin, "key 1"));
        assert.equal(fields()[5], "key 2", voice + ": the next name");
        cases++;
    }
    fs.writeFileSync(store.file, listed);
    for (const voice of ["local", "auto", ""])
        assert.deepEqual([voiceKey(voice).status, voiceKey(voice).stderr], [7, "jarvis-keys: arguments=voice\n"], "voice [" + voice + "]");
    // The add-key window words these refusals by keys.js's exit status
    // (tui/add-key.sh); any other refusal exits 1.
    const statuses = folder => {
        const run = (input, ...args) => cp.spawnSync("node", [path.join(folder, "backend/keys.js"), ...args],
            { env, input, encoding: "utf8" });
        const before = calls("secret-calls");
        try {
            for (const [label, list, input, args, status, reason] of [
                ["an empty box", clean, "\n", ["add-key", "openai", "test"], 3, "store=empty"],
                ["a paste too long", clean, "A".repeat(8193), ["add-key", "openai", "test"], 4, "store=oversize"],
                ["a name too long", clean, "", ["add-check", "openai", "n".repeat(81)], 5, "reference=identity"],
                ["a full list", JSON.stringify(full), "", ["add-check", "openai", "new"], 6, "references=limit"],
                ["a list too large", " ".repeat(65537), "", ["add-check", "openai", "new"], 6, "references=size"],
                ["an unreadable list", "junk", "", ["add-check", "openai", "new"], 1, "references=json"]
            ]) {
                fs.writeFileSync(store.file, list);
                const result = run(input, ...args);
                assert.deepEqual([result.status, result.stderr], [status, "jarvis-keys: " + reason + "\n"], label);
                cases++;
            }
        } finally { fs.writeFileSync(store.file, clean); }
        assert.equal(calls("secret-calls"), before, "a refusal stores nothing");
        // Enter on an empty box leaves the window as Escape does.
        const result = tui(folder, path.join(folder, "tui/add-key.sh"), ["--empty-key"]);
        assert.equal(result.status, 130, result.stdout + result.stderr);
        assert.equal(calls("secret-calls"), before, "an empty box stores nothing");
        cases++;
    };
    statuses(plugin);
    // The window starts keys.js with the box, so keys.js waits on the pipe
    // while the user fetches the key. That wait blocks in the kernel: the
    // process's utime + stime (/proc/PID/stat, clock ticks) across 0.6 s of
    // the wait stays under 0.2 s. This probe on Node v26.11.1, 2026-10-20:
    // 0.00 s blocking, 0.60 s for a read loop that retries EAGAIN.
    const waited = folder => {
        const result = cp.spawnSync("python3", ["-c", `
import os, subprocess, sys, time
child = subprocess.Popen(["node", sys.argv[1], "add-key", "openai", "waited"], stdin=subprocess.PIPE,
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
    keyProviders(plugin);
    chosen(plugin);
    unknown(plugin);
    fitted(plugin);
    widthRefused(plugin);
    removal(plugin);
    cases += 2;

    // Removing each stand-in must break its own behavioral assertion.
    for (const name of ["secret-tool", "busctl", "gum"]) {
        const file = path.join(env.PATH.split(":")[0], name);
        fs.renameSync(file, file + ".off");
        try {
            if (name === "busctl") {
                mode("present");
                assert.equal(store.rows()[0].value, "unavailable");
            } else assert.notEqual(tui().status, 0, name + " cannot fall back to the host");
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
        ["size", "stat.size > MAX_BYTES", "false", " ".repeat(65537), /references=size/],
        ["count", "values.length > MAX_REFERENCES", "false", JSON.stringify(Array(33).fill(ref)), /references=limit/],
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
    // The actual TUI/CLI path, not a reimplementation, sees this mutation.
    const mutant = path.join(root, "tui-copy");
    fs.mkdirSync(path.join(mutant, "backend"), { recursive: true });
    fs.copyFileSync(path.join(backend, "keys.js"), path.join(mutant, "backend/keys.js"));
    fs.copyFileSync(path.join(plugin, "AccountProviders.js"), path.join(mutant, "AccountProviders.js"));
    fs.mkdirSync(path.join(mutant, "tui"));
    fs.copyFileSync(path.join(plugin, "tui/add-key.sh"), path.join(mutant, "tui/add-key.sh"));
    const precheck = "checkAdd(ref) { this.#referenceUpdate(ownReference(ref.provider, ref.account, ref.origin)); }";
    assert.equal(source.split(precheck).length - 1, 1);
    const unchecked = source.replace(precheck, "checkAdd(ref) { void ref; }");
    assert.notEqual(unchecked, source);
    fs.writeFileSync(path.join(mutant, "backend/Secrets.js"), unchecked);
    for (const [data, expected] of [...metadataCases, [JSON.stringify(full), /references=limit/]]) {
        fs.writeFileSync(store.file, data);
        assert.throws(() => refusedTui(expected, mutant), assert.AssertionError,
            "removing the early judge must break refusal before key entry");
    }
    fs.writeFileSync(store.file, clean);
    controls++;
    const needle = 'output.fill(0);\n            this.remember(own);';
    assert.equal(source.split(needle).length - 1, 1);
    fs.writeFileSync(path.join(mutant, "backend/Secrets.js"),
        source.replace(needle, 'process.stdout.write(output);\n' + needle));
    assert.throws(() => goodTui(tui(mutant)), assert.AssertionError);
    controls++;
    fs.writeFileSync(path.join(mutant, "backend/Secrets.js"), source);
    const cliSource = fs.readFileSync(path.join(backend, "keys.js"), "utf8");
    const cliNeedle = "store.addKey(ref, pastedKey());";
    assert.equal(cliSource.split(cliNeedle).length - 1, 1);
    fs.writeFileSync(path.join(mutant, "backend/keys.js"), cliSource.replace(cliNeedle, "void ref;"));
    assert.throws(() => goodTui(tui(mutant)), assert.AssertionError, "CLI must call storage");
    controls++;
    fs.writeFileSync(path.join(mutant, "backend/keys.js"), cliSource);
    const scriptSource = fs.readFileSync(path.join(tree, "shell/plugins/vgs.jarvis/tui/add-key.sh"), "utf8");
    const scriptNeedle = 'add-key "$provider" "$account"';
    assert.equal(scriptSource.split(scriptNeedle).length - 1, 1);
    const scriptCopy = path.join(root, "wrong-metadata.sh");
    fs.writeFileSync(scriptCopy, scriptSource.replace(scriptNeedle, 'add-key "$account" "$provider"'));
    assert.throws(() => goodTui(tui(path.dirname(backend), scriptCopy)), assert.AssertionError,
        "TUI must pass complete metadata, not a key");
    controls++;
    const widthNeedle = 'keys providers "$(vgs_tui_columns)"';
    assert.equal(scriptSource.split(widthNeedle).length - 1, 1);
    const wideCopy = path.join(root, "unfitted-choices.sh");
    fs.writeFileSync(wideCopy, scriptSource.replace(widthNeedle, "keys providers 1000"));
    assert.throws(() => fitted(path.dirname(backend), wideCopy), assert.AssertionError, "choices must fit the terminal");
    controls++;
    const removeSource = fs.readFileSync(path.join(plugin, "tui/remove-key.sh"), "utf8");
    const confirmNeedle = 'vgs_tui_confirm "Remove the key $provider / $account?" || { vgs_tui_cancelled "The key stays."; exit 130; }';
    assert.equal(removeSource.split(confirmNeedle).length - 1, 1);
    const unaskedCopy = path.join(root, "unasked-removal.sh");
    fs.writeFileSync(unaskedCopy, removeSource.replace(confirmNeedle, ""));
    assert.throws(() => removal(plugin, unaskedCopy), assert.AssertionError, "removal must ask first");
    controls++;
    for (const [name, file, needle, replacement, check] of [
        ["removal-leaves-keyring-item", "backend/Secrets.js", 'this.run("secret-tool", ["clear", ...this.attributes(ref)]).fill(0);', "void 0;", removal],
        ["removal-trusts-clear", "backend/Secrets.js", 'if (left !== "absent") fail("key=" + left);', "void left;", removal],
        ["removal-leaves-reference", "backend/Secrets.js", "refs.filter(item => item !== ref)", "refs", removal],
        ["removal-clears-absent", "backend/Secrets.js", 'if (own && this.presence(ref).value !== "absent")', "if (own)", removal],
        ["removal-clears-foreign", "backend/Secrets.js", "const own = sorted(ref.attributes) === sorted(ownReference(provider, account, ref.origin).attributes);", "const own = true;", removal],
        ["removal-cli", "backend/keys.js", "store.removeKey(process.argv[3], process.argv[4])", "true", removal],
        ["stdin-stream", "backend/keys.js", "if (tty.isatty(0))", "if (process.stdin.isTTY)", waited],
        ["empty-status", "backend/keys.js", '"store=empty": 3,', "", statuses],
        ["name-status", "backend/keys.js", '"reference=identity": 5,', "", statuses],
        ["empty-box-window", "tui/add-key.sh", "3) printf 'No key was saved.\\n'; exit 130 ;;", "", statuses],
        ["unknown-provider", "backend/keys.js", 'if (row === undefined) throw new Error("jarvis-keys: provider=unknown");', "", unknown],
        ["provider-origin", "backend/keys.js", "ownReference(row.id, account, row.origin)", 'ownReference(row.id, account, "https://api.openai.com")', chosen],
        ["model-providers", "AccountProviders.js", 'return row.kind === "key" && modelProvider(row);', 'return row.kind === "key";', unknown],
        ["speech-key-stored", "AccountProviders.js", 'return modelKeyProvider(row) || row.kind === "speech-key";', "return modelKeyProvider(row);", chosen]
    ]) {
        const original = fs.readFileSync(path.join(plugin, file), "utf8");
        assert.equal(original.split(needle).length - 1, 1, name + " matches");
        fs.writeFileSync(path.join(mutant, file), original.replace(needle, replacement));
        try { assert.throws(() => check(mutant), assert.AssertionError, name + " must turn red"); }
        finally { fs.writeFileSync(path.join(mutant, file), original); }
        controls++;
    }
    // The EAGAIN retry this replaced spins while the window waits.
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
