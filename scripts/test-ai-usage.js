#!/usr/bin/env node
// vgs.ai-usage under node: the usage helper, shell/plugins/vgs.ai-usage/
// backend/usage.js, its view, UsageView.js, and the sign-in TUIs. Each
// account lives in a scratch HOME; Claude's endpoint is the stand-in
// scripts/fixtures/ai-usage/endpoint.js on 127.0.0.1, reached only through
// the reader's origin argument, and Codex is the stand-in
// scripts/fixtures/ai-usage/codex, reached by its path or a PATH that holds
// no other codex. The recorded replies beside the stand-ins are written by
// hand. Every control plants one defect in a disposable copy of the plugin
// and requires this suite to fail on it.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const cp = require("node:child_process");
const crypto = require("node:crypto");
const { load } = require("../bin/lib/qml-library.js");
const Endpoint = require("./fixtures/ai-usage/endpoint.js");

const tree = path.resolve(__dirname, "..");
const plugin = path.join(tree, "shell/plugins/vgs.ai-usage");
const fixtures = path.join(tree, "scripts/fixtures/ai-usage");
const Anchored = require(path.join(tree, "bin/lib/anchored.js"));
// A token no other text holds, so finding it anywhere is a leak.
const TOKEN = "sk-ant-oat01-plantedToken-" + crypto.randomBytes(12).toString("hex");
const HOUR = 3600000;
const NOW = Date.parse("2026-10-05T12:00:00Z");

const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "ai-usage-")));
let cases = 0;
// Each copy of the helper this suite loads holds its own exit listener.
process.setMaxListeners(64);
// The stand-in endpoint, closed however the suite ends.
let server = null;
let controls = 0;

function write(file, text) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text);
}
// A Claude Code account folder holding a `.credentials.json` whose token
// expires EXPIRES milliseconds after NOW.
function claudeAccount(directory, expires, now = NOW) {
    write(path.join(directory, ".credentials.json"), JSON.stringify({ claudeAiOauth: {
        accessToken: TOKEN, refreshToken: "planted-refresh-" + TOKEN.slice(-6), expiresAt: now + expires,
        scopes: ["user:inference", "user:profile"], subscriptionType: "max" } }));
    return directory;
}
function codexAccount(directory, mode = "ok") {
    write(path.join(directory, "auth.json"), JSON.stringify({ OPENAI_API_KEY: null, tokens: { access_token: TOKEN } }));
    write(path.join(directory, "stand-in-mode"), mode + "\n");
    return directory;
}
// The bytes and modification time of every credential file under DIR.
function credentials(dir) {
    const out = {};
    for (const entry of fs.readdirSync(dir, { recursive: true }))
        if (/(^|\/)(\.credentials|auth)\.json$/.test(entry)) {
            const file = path.join(dir, entry);
            out[entry] = [fs.readFileSync(file, "utf8"), fs.statSync(file).mtimeMs];
        }
    return out;
}
function calls(directory) {
    const file = path.join(directory, "stand-in-calls");
    return fs.existsSync(file) ? fs.readFileSync(file, "utf8").trim().split("\n").map(line => JSON.parse(line)) : [];
}
// A child run to its end without blocking this process, whose stand-in
// endpoint answers it: { status, stdout, stderr }.
function run(args, env, timeoutMs = 30000) {
    return new Promise((resolve, reject) => {
        const child = cp.spawn(process.execPath, args, { env, stdio: ["ignore", "pipe", "pipe"] });
        let stdout = "", stderr = "";
        child.stdout.on("data", chunk => { stdout += chunk; });
        child.stderr.on("data", chunk => { stderr += chunk; });
        const timer = setTimeout(() => child.kill("SIGKILL"), timeoutMs);
        child.on("error", reject);
        child.on("close", status => { clearTimeout(timer); resolve({ status, stdout, stderr }); });
    });
}
function alive(pid) {
    try { process.kill(pid, 0); return true; } catch (error) { if (error.code === "ESRCH") return false; throw error; }
}

// A disposable copy of the plugin with FILE's NEEDLE, which must match once,
// replaced; CHECK gets the copy's folder and must fail an assertion.
async function control(name, file, needle, replacement, check) {
    const folder = fs.mkdtempSync(path.join(root, "control-"));
    fs.cpSync(plugin, folder, { recursive: true });
    const target = path.join(folder, file);
    const source = fs.readFileSync(target, "utf8");
    assert.equal(source.split(needle).length - 1, 1, name + " match");
    const changed = source.replace(needle, replacement);
    assert.notEqual(changed, source);
    fs.writeFileSync(target, changed);
    await assert.rejects(async () => check(folder), assert.AssertionError, name + " must turn red");
    controls++;
}
// The same for FILE, a core file outside the plugin: CHECK gets the copy's path.
async function fileControl(name, file, needle, replacement, check) {
    const folder = fs.mkdtempSync(path.join(root, "control-"));
    const source = fs.readFileSync(file, "utf8");
    assert.equal(source.split(needle).length - 1, 1, name + " match");
    const changed = source.replace(needle, replacement);
    assert.notEqual(changed, source);
    const copy = path.join(folder, path.basename(file));
    fs.writeFileSync(copy, changed);
    await assert.rejects(async () => check(copy), assert.AssertionError, name + " must turn red");
    controls++;
}
// PROMISE, failing an assertion when it has not settled after MS.
function bounded(promise, ms, what) {
    let timer;
    const late = new Promise((resolve, reject) => {
        timer = setTimeout(() => reject(new assert.AssertionError({ message: what + " outlived " + ms + " ms" })), ms);
    });
    return Promise.race([promise, late]).finally(() => clearTimeout(timer));
}
// Whether every process PIDS names has ended, polled for up to 5 s.
async function ended(pids) {
    for (const deadline = Date.now() + 5000; Date.now() < deadline;) {
        if (!pids.some(alive)) return true;
        await new Promise(resolve => setTimeout(resolve, 50));
    }
    return !pids.some(alive);
}
const usageIn = folder => require(path.join(folder, "backend/usage.js"));
const viewIn = folder => load(path.join(folder, "UsageView.js"));

async function main() {
    const endpointDir = path.join(root, "endpoint");
    fs.mkdirSync(endpointDir);
    const mode = word => fs.writeFileSync(path.join(endpointDir, "mode"), word + "\n");
    const requests = () => {
        const file = path.join(endpointDir, "log");
        return fs.existsSync(file) ? fs.readFileSync(file, "utf8").trim().split("\n").map(line => JSON.parse(line)) : [];
    };
    mode("ok");
    server = Endpoint.start(path.join(endpointDir, "port"), path.join(endpointDir, "mode"), path.join(endpointDir, "log"));
    while (!fs.existsSync(path.join(endpointDir, "port"))) await new Promise(resolve => setTimeout(resolve, 10));
    const origin = "http://127.0.0.1:" + fs.readFileSync(path.join(endpointDir, "port"), "utf8");

    // The stand-ins' directory, and a PATH whose only codex, claude and gum
    // are the stand-ins: the host's own programs live in neither /usr/bin
    // nor /bin, which this suite checks before it runs one.
    const standins = path.join(root, "standins");
    fs.mkdirSync(standins);
    const codex = path.join(standins, "codex");
    fs.symlinkSync(path.join(fixtures, "codex"), codex);
    for (const name of ["claude", "gum"]) {
        write(path.join(standins, name), '#!/bin/sh\nprintf "%s\\n" "$*" >>"$HOME/' + name + '-calls"\n');
        fs.chmodSync(path.join(standins, name), 0o755);
    }
    const PATH = standins + ":/usr/bin:/bin";
    for (const name of ["codex", "claude", "gum"]) {
        const found = cp.spawnSync("sh", ["-c", "command -v " + name], { env: { PATH }, encoding: "utf8" }).stdout.trim();
        assert.equal(found, path.join(standins, name), name + " resolves to its stand-in");
    }

    // The anchored walk refuses a value that is no absolute normal path
    // before it opens anything: through `..` it would leave the folder it
    // was handed, and every caller reads its refusal.
    const walkRoot = path.join(root, "walk");
    fs.mkdirSync(path.join(walkRoot, "inside"), { recursive: true });
    fs.mkdirSync(path.join(walkRoot, "outside"), { recursive: true });
    const escape = path.join(walkRoot, "inside") + "/../outside";
    const walk = file => {
        const { directory } = require(file);
        for (const value of [escape, "walk/outside", "/" + "a".repeat(4096), 7, null])
            assert.deepEqual(directory(value), { kind: "not-absolute" }, String(value).slice(0, 60));
        const opened = directory(path.join(walkRoot, "outside"));
        assert.equal(opened.kind, "directory");
        fs.closeSync(opened.fd);
    };
    walk(path.join(tree, "bin/lib/anchored.js"));
    cases++;
    await fileControl("walk-follows-dotdot", path.join(tree, "bin/lib/anchored.js"),
        "    if (typeof file !== \"string\" || !path.isAbsolute(file) || path.normalize(file) !== file\n",
        "    if (typeof file !== \"string\" || !path.isAbsolute(file)\n",
        file => {
            const { directory } = require(file);
            const opened = directory(escape);
            if (opened.kind === "directory") fs.closeSync(opened.fd);
            assert.deepEqual(opened, { kind: "not-absolute" });
        });

    // The shipped entry point sends Claude's request to Claude Code's own
    // endpoint, its default path included: run with an unexpired planted
    // token, its requests reach no network (scripts/fixtures/ai-usage/
    // no-network.js) and are recorded. The smoke row's copy, whose constant
    // scripts/smoke/fixtures/ai-usage/edit.py edits, and a copy whose read()
    // defaults to another origin both fail.
    const shippedHome = path.join(root, "shipped-home");
    claudeAccount(path.join(shippedHome, ".claude"), HOUR, Date.now());
    const shipped = folder => {
        assert.equal(usageIn(folder).ORIGIN, "https://api.anthropic.com");
        const recorded = path.join(fs.mkdtempSync(path.join(root, "shipped-")), "requests");
        const result = cp.spawnSync(process.execPath, [path.join(folder, "backend/usage.js"), "--tree", tree], { encoding: "utf8", timeout: 30000,
            env: { PATH, HOME: shippedHome, LANG: "C.UTF-8", AI_USAGE_REQUESTS: recorded,
                NODE_OPTIONS: "--require=" + path.join(fixtures, "no-network.js") } });
        assert.equal(result.status, 0, result.stderr);
        assert.deepEqual(fs.readFileSync(recorded, "utf8").trim().split("\n").map(line => JSON.parse(line)),
            [{ url: "https://api.anthropic.com/api/oauth/usage", method: "GET" }]);
        assert.deepEqual(JSON.parse(result.stdout).accounts.map(row => [row.provider, row.state]), [["claude", "failed"]]);
    };
    shipped(plugin);
    cases++;
    await control("origin-edited", "backend/usage.js", 'const ORIGIN = "https://api.anthropic.com";',
        'const ORIGIN = "http://127.0.0.1:9";', shipped);
    await control("default-origin", "backend/usage.js", "async function read(tree, env, { origin = ORIGIN } = {}) {",
        'async function read(tree, env, { origin = "http://127.0.0.1:9" } = {}) {', shipped);

    // The recorded replies, parsed. A window the reply leaves out or holds
    // as null is absent, never a 0 % window; a reply of another shape is null.
    const claudeReply = JSON.parse(fs.readFileSync(path.join(fixtures, "claude-usage.json"), "utf8"));
    const codexReply = JSON.parse(fs.readFileSync(path.join(fixtures, "codex-rate-limits.json"), "utf8"));
    const recorded = folder => {
        const { claudeWindows, codexWindows } = usageIn(folder);
        assert.deepEqual(claudeWindows(claudeReply), [
            { name: "five_hour", usedPercent: 42, resetsAt: Date.parse("2026-10-05T18:00:00.461Z") },
            { name: "seven_day", usedPercent: 83, resetsAt: Date.parse("2026-10-09T08:00:00.461Z") },
            { name: "seven_day_opus", usedPercent: 12, resetsAt: null }]);
        assert.deepEqual(claudeWindows(JSON.parse(fs.readFileSync(path.join(fixtures, "claude-usage-missing.json"), "utf8"))),
            [{ name: "seven_day", usedPercent: 83, resetsAt: Date.parse("2026-10-09T08:00:00.461Z") }]);
        for (const body of ["text", [], null, { five_hour: { utilization: "42", resets_at: null } }, { seven_day: 7 },
            { five_hour: { utilization: 4, resets_at: "soon" } }])
            assert.equal(claudeWindows(body), null, JSON.stringify(body));
        assert.deepEqual(codexWindows(codexReply), { plan: "plus", windows: [
            { name: "five_hour", usedPercent: 27, resetsAt: 1791223200000 },
            { name: "seven_day", usedPercent: 64, resetsAt: 1791561600000 }] });
        assert.deepEqual(codexWindows({ rateLimits: { primary: { usedPercent: 5, windowDurationMins: 60, resetsAt: null }, secondary: null } }),
            { plan: "", windows: [{ name: "minutes_60", usedPercent: 5, resetsAt: null }] });
        for (const body of [{}, { rateLimits: 3 }, { rateLimits: { primary: { usedPercent: "5" } } }, { rateLimits: { primary: [] } }])
            assert.equal(codexWindows(body), null, JSON.stringify(body));
    };
    recorded(plugin);
    cases++;
    await control("missing-window-zero", "backend/usage.js", "        if (value === undefined || value === null) continue;\n        if (!plain(value)) return null;\n        const usedPercent = percent(value.utilization);",
        "        if (value === undefined || value === null) { windows.push({ name, usedPercent: 0, resetsAt: null }); continue; }\n        if (!plain(value)) return null;\n        const usedPercent = percent(value.utilization);", recorded);
    await control("shape-accepted", "backend/usage.js", "if (usedPercent === undefined || (resetsAt !== null && !Number.isFinite(resetsAt))) return null;",
        "if (usedPercent === undefined) continue;", recorded);

    // Claude through the stand-in endpoint. Each case's state and windows;
    // an expired token sends nothing, and no read changes a credential file.
    const home = path.join(root, "claude-home");
    const fresh = claudeAccount(path.join(home, ".claude"), HOUR);
    const expired = claudeAccount(path.join(home, ".claude-old"), -HOUR);
    const unsigned = path.join(home, ".claude-empty");
    fs.mkdirSync(unsigned, { recursive: true });
    const linked = path.join(home, ".claude-linked");
    fs.mkdirSync(linked);
    fs.symlinkSync(path.join(fresh, ".credentials.json"), path.join(linked, ".credentials.json"));
    const before = credentials(home);
    const tokenHash = crypto.createHash("sha256").update(TOKEN).digest("hex");
    const claudeCases = async folder => {
        const { readClaude } = usageIn(folder);
        const readOf = (directory, word, deadlineMs) => { mode(word); return readClaude(Anchored, directory, { origin, now: NOW, deadlineMs }); };
        const sent = requests().length;
        assert.deepEqual(await readOf(fresh, "ok"), { state: "ok", plan: "max", windows: [
            { name: "five_hour", usedPercent: 42, resetsAt: Date.parse("2026-10-05T18:00:00.461Z") },
            { name: "seven_day", usedPercent: 83, resetsAt: Date.parse("2026-10-09T08:00:00.461Z") },
            { name: "seven_day_opus", usedPercent: 12, resetsAt: null }] });
        assert.deepEqual(requests().slice(sent), [{ method: "GET", path: "/api/oauth/usage", beta: "oauth-2025-04-20", token: tokenHash }]);
        assert.deepEqual((await readOf(fresh, "missing")).windows.map(row => row.name), ["seven_day"], "a missing window is absent");
        const quiet = requests().length;
        assert.deepEqual(await readOf(expired, "ok"), { state: "expired", plan: "max" }, "an expired token reads expired");
        assert.equal(requests().length, quiet, "an expired token sends no request");
        assert.deepEqual(await readOf(fresh, "refused"), { state: "expired", plan: "max" }, "a refused token reads expired");
        assert.deepEqual(await readOf(fresh, "malformed"), { state: "failed", reason: "reply-json" }, "a malformed body fails");
        assert.deepEqual(await readOf(fresh, "error"), { state: "failed", reason: "http-500" });
        assert.deepEqual(await readOf(unsigned, "ok"), { state: "signed-out" });
        assert.deepEqual(await readOf(path.join(home, ".claude-absent"), "ok"), { state: "signed-out" });
        assert.deepEqual(await readOf(linked, "ok"), { state: "failed", reason: "credentials-link" }, "a linked credential file is not followed");
        assert.deepEqual(await readOf(fresh + "/../.claude", "ok"), { state: "failed", reason: "directory-not-absolute" });
        assert.deepEqual(await bounded(readOf(fresh, "hang", 500), 5000, "a read of a silent endpoint"),
            { state: "failed", reason: "deadline" }, "a silent endpoint ends at the deadline");
        assert.deepEqual(credentials(home), before, "no credential file changed");
    };
    await claudeCases(plugin);
    cases++;
    await control("expired-sends", "backend/usage.js", '    if (oauth.expiresAt <= now) return { state: "expired", plan };\n', "", claudeCases);
    await control("malformed-zero", "backend/usage.js", 'try { body = JSON.parse(reply.body); } catch { return failed("reply-json"); }',
        "try { body = JSON.parse(reply.body); } catch { body = { five_hour: { utilization: 0, resets_at: null } }; }", claudeCases);
    await control("link-followed", "backend/usage.js", "fs.openSync(Anchored.child(fd, file), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_NOCTTY)",
        "fs.openSync(Anchored.child(fd, file), O_RDONLY | O_NONBLOCK | O_NOCTTY)", claudeCases);
    await control("credentials-touched", "backend/usage.js", "    finally { fs.closeSync(opened.fd); }\n    if (file.kind === \"absent\") return { state: \"signed-out\" };",
        "    finally { fs.closeSync(opened.fd); }\n    if (file.kind === \"file\") fs.utimesSync(path.join(directory, \".credentials.json\"), new Date(), new Date());\n    if (file.kind === \"absent\") return { state: \"signed-out\" };", claudeCases);
    await control("request-deadline", "backend/usage.js", "request.destroy(); finish({ error: \"deadline\" });", "void request;", claudeCases);
    server.closeAllConnections();
    fs.unlinkSync(path.join(linked, ".credentials.json"));

    // Codex through the stand-in program: its answers, nothing run for a
    // folder with no auth.json, and the program dead after every read,
    // the deadline's included.
    const codexHome = path.join(root, "codex-home");
    const signed = codexAccount(path.join(codexHome, ".codex"));
    const noAuth = path.join(codexHome, ".codex-empty");
    fs.mkdirSync(noAuth, { recursive: true });
    const codexCases = async folder => {
        const { readCodex } = usageIn(folder);
        const env = { PATH, HOME: codexHome };
        const readOf = (word, options = {}) => {
            write(path.join(signed, "stand-in-mode"), word + "\n");
            return readCodex(Anchored, signed, { command: codex, env, ...options });
        };
        const started = calls(signed).length;
        assert.deepEqual(await readOf("ok"), { state: "ok", email: "person@example.invalid", plan: "plus", windows: [
            { name: "five_hour", usedPercent: 27, resetsAt: 1791223200000 },
            { name: "seven_day", usedPercent: 64, resetsAt: 1791561600000 }] });
        const run = calls(signed).slice(started);
        assert.deepEqual(run.map(call => [call.args, call.codexHome]), [[["app-server"], signed]]);
        assert.deepEqual(await readOf("signed-out"), { state: "signed-out" });
        assert.deepEqual(await readOf("error"), { state: "failed", reason: "codex-error" });
        const methods = path.join(signed, "stand-in-methods");
        fs.rmSync(methods, { force: true });
        assert.deepEqual(await readOf("api-key"), { state: "no-plan" }, "an API-key sign-in has no plan limits");
        assert.deepEqual(fs.readFileSync(methods, "utf8").trim().split("\n"), ["initialize", "initialized", "account/read"],
            "an API-key sign-in asks for no limits");
        assert.deepEqual(await readOf("hang", { deadlineMs: 1500 }), { state: "failed", reason: "codex-deadline" });
        assert.equal(await ended(calls(signed).slice(started).map(call => call.pid)), true, "every program ended");
        assert.deepEqual(await readCodex(Anchored, noAuth, { command: codex, env }), { state: "signed-out" });
        assert.equal(calls(noAuth).length, 0, "nothing runs for a folder with no sign-in");
    };
    await codexCases(plugin);
    cases++;
    await control("deadline-kept", "backend/usage.js", '            child.kill("SIGKILL");\n', "", codexCases);
    await control("api-key-limits", "backend/usage.js", '                if (value.type !== "chatgpt") return finish({ state: "no-plan" });\n', "", codexCases);
    for (const call of calls(signed)) if (alive(call.pid)) process.kill(call.pid, "SIGKILL");

    // The whole read in a child, as the service runs it, over a HOME of
    // three accounts: the published status and every byte the child
    // printed hold no token, whatever the endpoint answers.
    const world = path.join(root, "world");
    claudeAccount(path.join(world, ".claude"), HOUR, Date.now());
    claudeAccount(path.join(world, ".config/.claude-work"), -HOUR, Date.now());
    codexAccount(path.join(world, ".codex"));
    const worldBefore = credentials(world);
    const env = { PATH, HOME: world, LANG: "C.UTF-8" };
    const driver = (folder, word) => {
        mode(word);
        return run(["-e", `
const usage = require(process.argv[1]);
usage.read(process.argv[2], process.env, { origin: process.argv[3] }).then(r => process.stdout.write(JSON.stringify(r) + "\\n"));`,
            path.join(folder, "backend/usage.js"), tree, origin], env);
    };
    const helperLines = [];
    const leaks = async folder => {
        const View = viewIn(plugin);
        for (const word of ["ok", "error", "malformed"]) {
            const result = await driver(folder, word);
            if (folder === plugin) helperLines.push(...result.stderr.split("\n").filter(Boolean));
            assert.equal(result.status, 0, result.stderr);
            const reading = JSON.parse(result.stdout);
            const usage = View.merge(null, reading, NOW);
            const status = JSON.stringify([usage, View.signIn(usage, "claude"), View.signIn(usage, "codex")]);
            for (const [where, text] of [["stdout", result.stdout], ["stderr", result.stderr], ["status", status]])
                assert.equal(text.includes(TOKEN), false, "the token reaches " + where + " for " + word);
            const states = Object.fromEntries(reading.accounts.map(row => [row.provider + "/" + row.label, row.state]));
            assert.deepEqual(states, { "claude/default": word === "ok" ? "ok" : "failed", "claude/work": "expired", "codex/default": "ok" }, result.stderr);
        }
        assert.deepEqual(credentials(world), worldBefore, "no credential file changed");
    };
    await leaks(plugin);
    cases++;
    await control("token-in-log", "backend/usage.js", 'if (reply.status !== 200) return failed("http-" + reply.status);',
        'if (reply.status !== 200) return failed("http-" + reply.status + "-" + oauth.accessToken);', leaks);

    // The shipped entry point under the same HOME, with no unexpired Claude
    // token, so it sends no request: one line of every account.
    const shippedRun = () => {
        const old = path.join(world, ".claude/.credentials.json");
        const saved = fs.readFileSync(old);
        claudeAccount(path.join(world, ".claude"), -HOUR, Date.now());
        try {
            const result = cp.spawnSync(process.execPath, [path.join(plugin, "backend/usage.js"), "--tree", tree], { env, encoding: "utf8", timeout: 30000 });
            assert.equal(result.status, 0, result.stderr);
            const line = JSON.parse(result.stdout);
            assert.deepEqual([line.partial, line.accounts.map(row => [row.provider, row.label, row.state])],
                ["", [["claude", "default", "expired"], ["codex", "default", "ok"], ["claude", "work", "expired"]]]);
            assert.equal(result.stdout.includes(TOKEN) || result.stderr.includes(TOKEN), false);
            const refused = cp.spawnSync(process.execPath, [path.join(plugin, "backend/usage.js")], { env, encoding: "utf8" });
            assert.deepEqual([refused.status, refused.stdout, refused.stderr], [2, "", "ai-usage: arguments=expected-tree\n"]);
            helperLines.push(refused.stderr.trim());
        } finally { fs.writeFileSync(old, saved); }
    };
    const sentBefore = requests().length;
    shippedRun();
    assert.equal(requests().length, sentBefore, "the shipped run sent nothing to the stand-in");
    cases++;

    // Each keyed line the helper prints passes the service's log rule, a
    // failed discovery's among them; a line of other text does not.
    const relativeHome = folder => cp.spawnSync(process.execPath, [path.join(folder, "backend/usage.js"), "--tree", tree],
        { env: { PATH, HOME: "relative-home", LANG: "C.UTF-8" }, encoding: "utf8", timeout: 30000 });
    const logged = folder => {
        const result = relativeHome(folder);
        assert.equal(result.status, 1, result.stderr);
        const lines = [...helperLines, ...result.stderr.split("\n").filter(Boolean)];
        assert.ok(lines.some(line => line.startsWith("ai-usage: read=")), "a failed discovery prints its line");
        assert.ok(lines.some(line => line.startsWith("ai-usage: account=")), "a failed account prints its line");
        const View = viewIn(plugin);
        for (const line of lines) assert.equal(View.keyed(line), true, line);
        for (const line of ["node:internal/main", TOKEN, "ai-usage: read=" + TOKEN]) assert.equal(View.keyed(line), false, line);
    };
    logged(plugin);
    cases++;
    await control("read-line-unkeyed", "backend/usage.js", 'process.stderr.write("ai-usage: read=failed" + (key === null ? "" : " " + key[1]) + "\\n");',
        'process.stderr.write("ai-usage: read=" + (key === null ? "failed" : key[1]) + "\\n");', logged);

    // The view: the merge that keeps a failed read's last figures stale,
    // the widget's highest share, its warning tone and its hidden state,
    // the sign-in rows and the panel's reset lines.
    const reading = (state, windows) => ({ accounts: [
        { id: "claude-a", provider: "claude", label: "default", email: "", plan: "max", state, windows },
        { id: "codex-b", provider: "codex", label: "work", email: "person@example.invalid", plan: "plus", state: "ok",
            windows: [{ name: "five_hour", usedPercent: 79, resetsAt: NOW + 61 * 60000 }] }], partial: "" });
    const views = folder => {
        const View = viewIn(folder);
        const plainOf = value => JSON.parse(JSON.stringify(value));
        const shown = usage => { const w = View.widget(usage); return [w.shown, w.percent, w.tone]; };
        const first = View.merge(null, reading("ok", [{ name: "seven_day", usedPercent: 80, resetsAt: NOW + 26 * HOUR }]), NOW);
        assert.deepEqual(shown(first), [true, 80, "warning"]);
        const failedRead = View.merge(first, reading("failed", []), NOW + 1);
        assert.deepEqual(plainOf(failedRead.accounts[0]), { id: "claude-a", provider: "claude", label: "default", email: "", plan: "max",
            state: "stale", windows: [{ name: "seven_day", usedPercent: 80, resetsAt: NOW + 26 * HOUR }] }, "a failed read keeps its last figures");
        assert.equal(failedRead.readAt, NOW + 1);
        const failedRun = View.merge(first, null, NOW + 2);
        assert.deepEqual(plainOf(failedRun.accounts.map(row => [row.state, row.windows.length])), [["stale", 1], ["stale", 1]]);
        assert.equal(failedRun.readAt, NOW);
        const never = View.merge(null, reading("failed", []), NOW);
        assert.deepEqual(plainOf(never.accounts[0].windows), [], "a failed first read holds no window");
        assert.deepEqual(shown(View.merge(null, { accounts: [never.accounts[0]], partial: "" }, NOW)), [true, null, "normal"],
            "a failed read shows no share");
        const below = View.merge(null, reading("ok", [{ name: "five_hour", usedPercent: 12, resetsAt: null }]), NOW);
        assert.deepEqual(shown(below), [true, 79, "normal"], "the highest share across accounts");
        const only = state => View.merge(null, { accounts: [{ id: "c", provider: "codex", label: "x", email: "", plan: "", state,
            windows: [] }], partial: "" }, NOW);
        for (const usage of [null, { accounts: [], readAt: NOW }, only("signed-out"), only("no-plan")])
            assert.equal(View.widget(usage).shown, false, "no plan sign-in hides the widget");
        const row = (usage, provider) => { const r = View.signIn(usage, provider); return [r.tone, r.action === true]; };
        assert.deepEqual(row(null, "claude"), ["info", true], "no sign-in offers Sign in");
        assert.deepEqual(row(first, "claude"), ["ok", false]);
        assert.deepEqual(row(only("no-plan"), "codex"), ["info", false], "an API-key sign-in is no failure and offers nothing");
        assert.deepEqual(row(View.merge(first, reading("failed", []), NOW), "claude"), ["ok", false], "stale figures stay signed in");
        assert.deepEqual(row(View.merge(null, reading("failed", []), NOW), "claude"), ["danger", false]);
        assert.equal(View.signIn(View.merge(null, reading("expired", []), NOW), "claude").text, View.EXPIRED);
        assert.deepEqual(plainOf(View.panel(first, NOW).map(r => [r.id, r.provider, r.label, r.email, r.plan, r.state,
            r.windows.map(w => [w.name, w.percent, w.tone, w.resetIn])])), [
            ["claude-a", "claude", "default", "", "max", "ok", [["seven_day", 80, "warning", { kind: "in", days: 1, hours: 2, minutes: 0 }]]],
            ["codex-b", "codex", "work", "person@example.invalid", "plus", "ok", [["five_hour", 79, "normal", { kind: "in", days: 0, hours: 1, minutes: 1 }]]]]);
        assert.deepEqual(plainOf([View.resetIn(null, NOW), View.resetIn(NOW - 1, NOW), View.resetIn(NOW + 59000, NOW),
            View.resetIn(NOW + (3 * 1440 + 6 * 60 + 30) * 60000, NOW)]),
            [{ kind: "none" }, { kind: "now" }, { kind: "in", days: 0, hours: 0, minutes: 1 }, { kind: "in", days: 3, hours: 6, minutes: 30 }]);
        assert.deepEqual(plainOf(["five_hour", "seven_day", "seven_day_opus", "minutes_120", "primary"].map(View.limitOf)),
            [{ minutes: 300, model: "" }, { minutes: 10080, model: "" }, { minutes: 10080, model: "opus" }, { minutes: 120, model: "" },
                { minutes: null, model: "" }]);
    };
    views(plugin);
    cases++;
    await control("stale-dropped", "UsageView.js", 'if (row.state === "failed" && last !== null && last.windows.length > 0)', "if (false)", views);
    await control("warning-boundary", "UsageView.js", "percent !== null && percent >= WARNING_PERCENT", "percent !== null && percent > WARNING_PERCENT", views);
    await control("lowest-share", "UsageView.js", "row.windows[j].usedPercent > percent", "row.windows[j].usedPercent < percent", views);
    await control("always-shown", "UsageView.js", "shown: accounts.length > 0", "shown: true", views);
    await control("no-plan-counted", "UsageView.js", 'return row.state !== "signed-out" && row.state !== "no-plan";', 'return row.state !== "signed-out";', views);
    await control("reset-rounded-down", "UsageView.js", "var minutes = Math.ceil((resetsAt - now) / 60000);", "var minutes = Math.floor((resetsAt - now) / 60000);", views);

    // The sign-in TUIs run each tool's own login, through the presentation
    // library, with the stand-ins on PATH.
    const signIns = folder => {
        for (const [script, tool, argv] of [["sign-in-claude.sh", "claude", "auth login"], ["sign-in-codex.sh", "codex", "login"]]) {
            const tuiHome = fs.mkdtempSync(path.join(root, "tui-"));
            const shim = path.join(tuiHome, "bin");
            write(path.join(shim, tool), '#!/bin/sh\nprintf "%s\\n" "$*" >>"$HOME/' + tool + '-calls"\n');
            fs.chmodSync(path.join(shim, tool), 0o755);
            const result = cp.spawnSync("bash", [path.join(folder, "tui", script)], { encoding: "utf8",
                env: { PATH: shim + ":" + PATH, HOME: tuiHome, VGS_TUI_LIB: path.join(tree, "bin/lib/tui.sh"), LANG: "C.UTF-8" } });
            assert.equal(result.status, 0, result.stderr);
            const record = path.join(tuiHome, tool + "-calls");
            assert.equal(fs.existsSync(record) ? fs.readFileSync(record, "utf8") : "none", argv + "\n", script);
        }
    };
    signIns(plugin);
    cases++;
    await control("sign-in-skipped", "tui/sign-in-claude.sh", "\nclaude auth login\n", "\ntrue\n", signIns);

    console.log("test-ai-usage: ok cases=" + cases + " controls=" + controls);
}

main().finally(() => {
    if (server !== null) { server.closeAllConnections(); server.close(); }
    fs.rmSync(root, { recursive: true, force: true });
}).catch(error => {
    console.error(error);
    process.exitCode = 1;
});
