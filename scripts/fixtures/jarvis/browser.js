"use strict";
const { assert, fs, path, tree } = require("./policy.js");
const cp = require("node:child_process");
const { once } = require("node:events");
function standins(directory) {
    fs.copyFileSync(path.join(tree, "scripts/fixtures/jarvis/browser.py"), path.join(directory, "agent-browser"));
    fs.chmodSync(path.join(directory, "agent-browser"), 0o700);
    // Setup terminal fixtures use the real TUI script with a neutral library.
    fs.copyFileSync(path.join(tree, "scripts/fixtures/jarvis/browser-gum.py"), path.join(directory, "gum"));
    fs.chmodSync(path.join(directory, "gum"), 0o700);
}
function mode(value) {
    fs.rmSync(path.join(process.env.JARVIS_TEST_ROOT, "browser-open-completed"), { force: true });
    fs.rmSync(path.join(process.env.JARVIS_TEST_ROOT, "browser-launch-completed"), { force: true });
    fs.rmSync(path.join(process.env.JARVIS_TEST_ROOT, "browser-version-release"), { force: true });
    update(value);
    fs.writeFileSync(path.join(process.env.JARVIS_TEST_ROOT, "browser-calls.jsonl"), "");
}
function update(value) {
    fs.writeFileSync(path.join(process.env.JARVIS_TEST_ROOT, "browser-mode.json"), JSON.stringify(value));
}
function calls() {
    return fs.readFileSync(path.join(process.env.JARVIS_TEST_ROOT, "browser-calls.jsonl"), "utf8").trim().split("\n").filter(Boolean).map(JSON.parse);
}

function daemonStandins(directory) {
    standins(directory);
    require("./audio.js").standins(directory);
    require("./desktop.js").standins(directory);
}

// An eager private browser stays owned until the real daemon ends its lease.
// The sync double prevents conversation end from hiding missing daemon teardown.
async function daemonLease(ending, removeClose = false) {
    mode({});
    require("./desktop.js").desktopWorld(process.env.XDG_RUNTIME_DIR, []);
    const plugin = path.join(tree, "shell/plugins/vgs.jarvis");
    const marker = path.join(process.env.XDG_DATA_HOME, "vgshell/jarvis/browser-ready.json");
    fs.mkdirSync(path.dirname(marker), { recursive: true });
    fs.writeFileSync(marker, JSON.stringify({ version: "0.38.1" }));
    const folder = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "browser-daemon-"));
    require("./audio.js").copyBackend(path.join(folder, "backend"));
    for (const file of ["JarvisProtocol.js", "Session.js", "AccountProviders.js"])
        fs.copyFileSync(path.join(plugin, file), path.join(folder, file));
    const browserFile = path.join(folder, "backend/Browser.js");
    const original = fs.readFileSync(browserFile, "utf8");
    const eager = '    return Object.freeze({\n        sync(state) {';
    assert.equal(original.split(eager).length - 1, 1, "eager browser instrumentation match");
    const changed = original.replace(eager,
        '    owner().record.start({ id: "browser", args: { command: "read", args: {} } }, () => {});\n' +
        '    return Object.freeze({\n        sync(state) { return;');
    assert.notEqual(changed, original);
    fs.writeFileSync(browserFile, changed);
    const file = path.join(folder, "backend/jarvisd.js");
    const source = fs.readFileSync(file, "utf8");
    const close = "try { browser.close(); }";
    assert.equal(source.split(close).length - 1, 1, "daemon teardown mutation match");
    if (removeClose) {
        const mutant = source.replace(close, "try { void browser; }");
        assert.notEqual(mutant, source);
        fs.writeFileSync(file, mutant);
    }
    const hello = { v: 1, type: "hello", gen: 0,
        settings: { home: "", sounds: false, mode: "hold", microphone: "", speaker: "", brain: "", model: "", effort: "", taskTerminal: "auto", voiceProvider: "local", voiceAccount: "", cloudVision: "ask", privateWindows: "" },
        directories: {
            state: path.join(process.env.JARVIS_TEST_ROOT, "state/vgshell/jarvis"),
            data: path.join(process.env.JARVIS_TEST_ROOT, "data/vgshell/jarvis"),
            runtime: path.join(process.env.JARVIS_TEST_ROOT, "run/vgshell/jarvis")
        }, revision: "a".repeat(64), locked: false,
        keys: { talk: "SUPER+code:108", mute: "SUPER+SHIFT+code:108", stop: "SUPER+ALT+PERIOD", confirm: "SUPER+ALT+Y", console: "SUPER+ALT+C" } };
    const child = cp.spawn("node", [file, "--tree", tree], { env: {
        PATH: process.env.PATH, HOME: process.env.HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
        XDG_DATA_HOME: process.env.XDG_DATA_HOME
    }, stdio: ["pipe", ending === "signal" ? "ignore" : "pipe", "pipe"] });
    let out = "", err = "";
    if (child.stdout !== null) child.stdout.on("data", data => { out += data; });
    child.stderr.on("data", data => { err += data; });
    child.stdin.on("error", error => { if (error.code !== "EPIPE") throw error; });
    const closed = once(child, "close");
    // The existing child bounds detect retained leases and stalled signal cleanup.
    const timeout = setTimeout(() => child.kill("SIGKILL"), ending === "signal" ? 5000 : 3000);
    try {
        child.stdin.write(JSON.stringify(hello) + "\n");
        if (ending === "signal") {
            for (let n = 0; !calls().some(row => row.args.includes("--session")); n++) {
                assert.ok(n < 400, "the daemon reaches its vendor session");
                // Poll the synthetic vendor's log before signalling the exact daemon PID.
                await new Promise(resolve => setTimeout(resolve, 10));
            }
            child.kill("SIGTERM");
            assert.deepEqual(await closed, [0, null], "SIGTERM cleans up before exit: " + err);
        } else {
            assert.equal(ending, "eof");
            child.stdin.end();
            const [actual, signal] = await closed;
            assert.equal(signal, null, "stdin EOF must end the daemon");
            assert.equal(actual, 0, err);
            assert.equal(err, "");
            assert.deepEqual(out.trim() === "" ? [] : out.trim().split("\n").map(JSON.parse), [
                { v: 1, type: "shell-status", gen: 0, revision: hello.revision, availability: { kind: "checking" } },
                { v: 1, type: "status", gen: 0, revision: hello.revision, daemon: "ready",
                    causes: ["speech=local-not-set-up", "brain=unselected"] },
                { v: 1, type: "state", gen: 1, revision: hello.revision, seq: 1, state: {
                    gen: 1, nextOp: 1, stale: 0, settings: hello.settings,
                    gate: { kind: "down", reason: "unconfigured" },
                    mute: { kind: "off" }, capture: { kind: "closed" }, turn: { kind: "none" }, brain: { kind: "closed" },
                    playback: { kind: "idle" }, action: { kind: "none" }, approval: { kind: "none" }, fault: { kind: "none" },
                    conversation: { kind: "ended" }, input: { kind: "released" }, indicator: { kind: "gone" },
                    duplex: { kind: "half" }, toggleAt: null,
                    engine: { kind: "chained" }, speech: { kind: "closed" }
                }, phase: "down" },
                { v: 1, type: "memory-inbox", gen: 1, revision: hello.revision, entries: [] }
            ]);
        }
        const session = calls().find(row => row.args.includes("--session"));
        assert.ok(session, "the fixture starts a private vendor session");
        assert.equal(calls().filter(row => row.args.at(-1) === "close").length, 1,
            "daemon " + ending + " closes the owned vendor session");
        assert.equal(fs.existsSync(session.env.XDG_RUNTIME_DIR), false, "daemon " + ending + " clears vendor data");
    } finally {
        clearTimeout(timeout);
        if (child.exitCode === null && child.signalCode === null) { child.kill("SIGKILL"); await closed; }
        fs.rmSync(marker, { force: true });
        fs.rmSync(folder, { recursive: true, force: true });
    }
}

// The optional probe is held across hello. Only the stand-in helper waits.
async function daemonStartup(browserFile) {
    mode({ versionHold: true });
    require("./desktop.js").desktopWorld(process.env.XDG_RUNTIME_DIR, []);
    const plugin = path.join(tree, "shell/plugins/vgs.jarvis");
    const folder = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "browser-startup-"));
    require("./audio.js").copyBackend(path.join(folder, "backend"));
    for (const file of ["JarvisProtocol.js", "Session.js", "AccountProviders.js"])
        fs.copyFileSync(path.join(plugin, file), path.join(folder, file));
    fs.copyFileSync(browserFile, path.join(folder, "backend/Browser.js"));
    const hello = { v: 1, type: "hello", gen: 0,
        settings: { home: "", sounds: false, mode: "hold", microphone: "", speaker: "", brain: "", model: "", effort: "", taskTerminal: "auto", voiceProvider: "local", voiceAccount: "", cloudVision: "ask", privateWindows: "" },
        directories: {
            state: path.join(process.env.JARVIS_TEST_ROOT, "state/vgshell/jarvis"),
            data: path.join(process.env.JARVIS_TEST_ROOT, "data/vgshell/jarvis"),
            runtime: path.join(process.env.JARVIS_TEST_ROOT, "run/vgshell/jarvis")
        }, revision: "a".repeat(64), locked: false,
        keys: { talk: "SUPER+code:108", mute: "SUPER+SHIFT+code:108", stop: "SUPER+ALT+PERIOD", confirm: "SUPER+ALT+Y", console: "SUPER+ALT+C" } };
    const child = cp.spawn(process.execPath, [path.join(folder, "backend/jarvisd.js"), "--tree", tree],
        { env: { PATH: process.env.PATH, HOME: process.env.HOME, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
            XDG_DATA_HOME: process.env.XDG_DATA_HOME }, stdio: ["pipe", "pipe", "pipe"] });
    let out = "", err = "";
    child.stdout.on("data", data => { out += data; });
    child.stderr.on("data", data => { err += data; });
    const closed = once(child, "close");
    const until = async predicate => {
        for (let n = 0; n < 500; n++) {
            if (predicate()) return;
            await new Promise(resolve => setTimeout(resolve, 10));
        }
        assert.fail("startup event absent");
    };
    try {
        child.stdin.write(JSON.stringify(hello) + "\n");
        await until(() => calls().some(row => row.args[0] === "--version"));
        await until(() => out.split("\n").filter(Boolean).map(JSON.parse).some(row => row.type === "status"));
        const ready = out.split("\n").filter(Boolean).map(JSON.parse).find(row => row.type === "status");
        assert.equal(ready.daemon, "ready");
        assert.equal(fs.existsSync(path.join(process.env.JARVIS_TEST_ROOT, "browser-version-release")), false);
        assert.equal(err.length, 0);
        const probe = calls().find(row => row.args[0] === "--version");
        child.stdin.end();
        let timer;
        try {
            const result = await Promise.race([closed, new Promise(resolve => { timer = setTimeout(() => resolve(null), 3000); })]);
            assert.deepEqual(result, [0, null]);
            await until(() => !fs.existsSync(probe.env.HOME));
        } finally { clearTimeout(timer); }
    } finally {
        fs.writeFileSync(path.join(process.env.JARVIS_TEST_ROOT, "browser-version-release"), "");
        if (child.exitCode === null && child.signalCode === null) { child.kill("SIGKILL"); await closed; }
        fs.rmSync(folder, { recursive: true, force: true });
    }
}

module.exports = { standins, mode, update, calls, daemonStandins, daemonLease, daemonStartup };
