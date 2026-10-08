#!/usr/bin/env node
// vgs.ai-usage under node: the usage helper, shell/plugins/vgs.ai-usage/
// backend/usage.js, its view, UsageView.js, and the sign-in TUIs. Each
// account lives in a scratch HOME; Claude and Copilot endpoints are the stand-in
// scripts/fixtures/ai-usage/endpoint.js on 127.0.0.1, reached only through
// the reader's origin argument, Copilot's keyring is the stand-in secret-tool
// fixture, and Codex is the stand-in
// scripts/fixtures/ai-usage/codex, reached by its path or a PATH that holds
// no other codex. The recorded replies beside the stand-ins are written by
// hand. Every control plants one defect in a disposable copy of the plugin
// and requires this suite to fail on it.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");
const crypto = require("node:crypto");
const { load } = require("../bin/lib/qml-library.js");
const modules = { "qs.Commons 1.0": { Duration: load(path.join(__dirname, "..", "shell", "Commons", "Duration.js")) } };
const Endpoint = require("./fixtures/ai-usage/endpoint.js");

const tree = path.resolve(__dirname, "..");
const plugin = path.join(tree, "shell/plugins/vgs.ai-usage");
const fixtures = path.join(tree, "scripts/fixtures/ai-usage");
const Anchored = require(path.join(tree, "bin/lib/anchored.js"));
// A token no other text holds, so finding it anywhere is a leak.
const TOKEN = "sk-ant-oat01-plantedToken-" + crypto.randomBytes(12).toString("hex");
const HOUR = 3600000;
const NOW = Date.parse("2026-10-05T12:00:00Z");

fs.mkdirSync(path.join(tree, "tmp"), { recursive: true });
const root = fs.realpathSync(fs.mkdtempSync(path.join(tree, "tmp/ai-usage-")));
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
function copilotAccount(directory, config = {}) {
    write(path.join(directory, "config.json"), "// Copilot CLI config\n" + JSON.stringify({ lastLoggedInUser: {
        host: "https://github.com", login: "octo-user" }, ...config }, null, 2));
    return directory;
}
// The bytes and modification time of every credential file under DIR.
function credentials(dir) {
    const out = {};
    for (const entry of fs.readdirSync(dir, { recursive: true }))
        if (/(^|\/)(\.credentials|auth|config)\.json$/.test(entry)) {
            const file = path.join(dir, entry);
            out[entry] = [fs.readFileSync(file, "utf8"), fs.statSync(file).mtimeMs];
        }
    return out;
}
function calls(directory) {
    const file = path.join(directory, "stand-in-calls");
    return fs.existsSync(file) ? fs.readFileSync(file, "utf8").trim().split("\n").map(line => JSON.parse(line)) : [];
}
function secretCalls(directory) {
    const file = path.join(directory, "secret-tool-calls");
    return fs.existsSync(file) ? fs.readFileSync(file, "utf8").trim().split("\n").filter(Boolean).map(line => JSON.parse(line)) : [];
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
const viewIn = folder => load(path.join(folder, "UsageView.js"), modules);

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
    fs.symlinkSync(path.join(fixtures, "secret-tool"), path.join(standins, "secret-tool"));
    for (const name of ["claude", "gum"]) {
        write(path.join(standins, name), '#!/bin/sh\nprintf "%s\\n" "$*" >>"$HOME/' + name + '-calls"\n');
        fs.chmodSync(path.join(standins, name), 0o755);
    }
    const PATH = standins + ":/usr/bin:/bin";
    for (const name of ["codex", "claude", "gum", "secret-tool"]) {
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
    await control("default-origin", "backend/usage.js",
        'async function read(tree, env, { origin = ORIGIN, copilotOrigin = COPILOT_ORIGIN, gatewayOrigin = GATEWAY_ORIGIN, secretTool = "secret-tool", gateway = false } = {}) {',
        'async function read(tree, env, { origin = "http://127.0.0.1:9", copilotOrigin = COPILOT_ORIGIN, gatewayOrigin = GATEWAY_ORIGIN, secretTool = "secret-tool", gateway = false } = {}) {', shipped);

    // The recorded replies, parsed. A window the reply leaves out or holds
    // as null is absent, never a 0 % window; a reply of another shape is null.
    const claudeReply = JSON.parse(fs.readFileSync(path.join(fixtures, "claude-usage.json"), "utf8"));
    const codexReply = JSON.parse(fs.readFileSync(path.join(fixtures, "codex-rate-limits.json"), "utf8"));
    const recorded = folder => {
        const { claudeWindows, claudeDetails, codexWindows } = usageIn(folder);
        assert.deepEqual(claudeWindows(claudeReply), [
            { name: "five_hour", usedPercent: 42, resetsAt: Date.parse("2026-10-05T18:00:00.461Z") },
            { name: "seven_day", usedPercent: 83, resetsAt: Date.parse("2026-10-09T08:00:00.461Z") },
            { name: "seven_day_fable", usedPercent: 12, resetsAt: null }]);
        assert.deepEqual(claudeWindows(JSON.parse(fs.readFileSync(path.join(fixtures, "claude-usage-missing.json"), "utf8"))),
            [{ name: "seven_day", usedPercent: 83, resetsAt: Date.parse("2026-10-09T08:00:00.461Z") },
                { name: "seven_day_fable", usedPercent: 12, resetsAt: null }]);
        const malformedScoped = structuredClone(claudeReply);
        malformedScoped.limits[2].percent = "12";
        assert.equal(claudeWindows(malformedScoped), null, "a malformed scoped percent fails the reply");
        const malformedScopedReset = structuredClone(claudeReply);
        malformedScopedReset.limits[2].resets_at = "soon";
        assert.equal(claudeWindows(malformedScopedReset), null, "a malformed scoped reset fails the reply");
        for (const body of ["text", [], null, { five_hour: { utilization: "42", resets_at: null } }, { seven_day: 7 },
            { five_hour: { utilization: 4, resets_at: "soon" } }])
            assert.equal(claudeWindows(body), null, JSON.stringify(body));
        assert.deepEqual(claudeDetails(null), {}, "a null reply has no extra usage details");
        assert.deepEqual(claudeDetails(claudeReply), { claudeExtra: { used: 123.45, limit: 500, currency: "USD", utilization: 24.69 } });
        assert.deepEqual(codexWindows(codexReply), { details: { codexCredits: { balance: "12345" } }, windows: [
            { name: "five_hour", usedPercent: 27, resetsAt: 1791223200000 },
            { name: "seven_day", usedPercent: 64, resetsAt: 1791561600000 }] });
        assert.deepEqual(codexWindows({ rateLimits: { primary: { usedPercent: 5, windowDurationMins: 60, resetsAt: null }, secondary: null, credits: { hasCredits: true, unlimited: true, balance: null } } }),
            { details: { codexCredits: { unlimited: true } }, windows: [{ name: "minutes_60", usedPercent: 5, resetsAt: null }] });
        for (const body of [{}, { rateLimits: 3 }, { rateLimits: { primary: { usedPercent: "5" } } }, { rateLimits: { primary: [] } }])
            assert.equal(codexWindows(body), null, JSON.stringify(body));
    };
    recorded(plugin);
    cases++;
    await control("old-seven-day-scan", "backend/usage.js", "    for (const name of [\"five_hour\", \"seven_day\"]) {",
        "    const names = Object.keys(body).filter(name => /^seven_day_[a-z0-9_]+$/.test(name)).sort();\n    for (const name of [\"five_hour\", \"seven_day\", ...names]) {", recorded);
    await control("limits-parse-removed", "backend/usage.js", "for (const entry of Array.isArray(body.limits) ? body.limits : [])",
        "for (const entry of [])", recorded);
    await control("null-window-zero", "backend/usage.js", "        if (window !== undefined) windows.push(window);",
        "        if (window !== undefined) windows.push(window); else windows.push({ name, usedPercent: 0, resetsAt: null });", recorded);
    await control("shape-accepted", "backend/usage.js", "        const resetsAt = resetTime(entry.resets_at);\n        if (usedPercent === undefined || resetsAt === undefined) return null;",
        "        const resetsAt = resetTime(entry.resets_at);\n        if (usedPercent === undefined) continue;", recorded);
    await control("claude-details-null-unguarded", "backend/usage.js", "    if (!plain(body)) return {};",
        "    if (!plain(body)) return null;", recorded);

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
    const second = path.join(home, ".claude-second");
    write(path.join(second, ".credentials.json"), JSON.stringify({ claudeAiOauth: {
        accessToken: TOKEN + "-second", expiresAt: NOW + HOUR, scopes: ["user:inference"] } }));
    const before = credentials(home);
    const tokenHash = crypto.createHash("sha256").update(TOKEN).digest("hex");
    const claudeCases = async folder => {
        const { readClaude } = usageIn(folder);
        const readOf = (directory, word, deadlineMs) => { mode(word); return readClaude(Anchored, directory, { origin, now: NOW, deadlineMs }); };
        const sent = requests().length;
        assert.deepEqual(await readOf(fresh, "ok"), { state: "ok", email: "", windows: [
            { name: "five_hour", usedPercent: 42, resetsAt: Date.parse("2026-10-05T18:00:00.461Z") },
            { name: "seven_day", usedPercent: 83, resetsAt: Date.parse("2026-10-09T08:00:00.461Z") },
            { name: "seven_day_fable", usedPercent: 12, resetsAt: null }],
            details: { claudeExtra: { used: 123.45, limit: 500, currency: "USD", utilization: 24.69 } } });
        assert.deepEqual(requests().slice(sent), [{ method: "GET", path: "/api/oauth/usage", beta: "oauth-2025-04-20",
            token: tokenHash, authHash: null, userAgent: null }]);
        assert.deepEqual((await readOf(fresh, "missing")).windows.map(row => row.name), ["seven_day", "seven_day_fable"], "a missing window is absent");
        const quiet = requests().length;
        assert.deepEqual(await readOf(expired, "ok"), { state: "expired", email: "" }, "an expired token reads expired");
        assert.equal(requests().length, quiet, "an expired token sends no request");
        assert.deepEqual(await readOf(fresh, "refused"), { state: "expired", email: "" }, "a refused token reads expired");
        assert.deepEqual(await readOf(fresh, "malformed"), { state: "failed", reason: "reply-json", email: "" }, "a malformed body fails");
        assert.deepEqual(await readOf(fresh, "null"), { state: "failed", reason: "reply-shape", email: "" }, "a null body fails one account, not the whole run");
        assert.deepEqual(await readOf(fresh, "error"), { state: "failed", reason: "http-500", email: "" });
        assert.deepEqual(await readOf(fresh, "throttled"), { state: "limited", email: "" }, "a 429 reads limited, no failure");
        // The stand-in's limited mode: each token's first read is served,
        // its next one inside the window turned away, another token's served.
        mode("limited");
        const again = directory => readClaude(Anchored, directory, { origin, now: NOW });
        assert.equal((await again(fresh)).state, "ok", "limited mode serves a token's first read");
        assert.deepEqual(await again(fresh), { state: "limited", email: "" }, "limited mode turns away the token's next read");
        assert.equal((await again(second)).state, "ok", "limited mode serves another token's first read");
        assert.deepEqual(await readOf(unsigned, "ok"), { state: "signed-out" });
        assert.deepEqual(await readOf(path.join(home, ".claude-absent"), "ok"), { state: "signed-out" });
        assert.deepEqual(await readOf(linked, "ok"), { state: "failed", reason: "credentials-link" }, "a linked credential file is not followed");
        assert.deepEqual(await readOf(fresh + "/../.claude", "ok"), { state: "failed", reason: "directory-not-absolute" });
        assert.deepEqual(await bounded(readOf(fresh, "hang", 500), 5000, "a read of a silent endpoint"),
            { state: "failed", reason: "deadline", email: "" }, "a silent endpoint ends at the deadline");
        assert.deepEqual(credentials(home), before, "no credential file changed");
    };
    await claudeCases(plugin);
    cases++;
    await control("expired-sends", "backend/usage.js", '    if (oauth.expiresAt <= now) return { state: "expired", email };\n', "", claudeCases);
    await control("malformed-zero", "backend/usage.js",
        'try { body = JSON.parse(reply.body); } catch { return lost("reply-json"); }\n    const windows = claudeWindows(body);',
        "try { body = JSON.parse(reply.body); } catch { body = { five_hour: { utilization: 0, resets_at: null } }; }\n    const windows = claudeWindows(body);",
        claudeCases);
    await control("link-followed", "backend/usage.js", "fs.openSync(Anchored.child(fd, file), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_NOCTTY)",
        "fs.openSync(Anchored.child(fd, file), O_RDONLY | O_NONBLOCK | O_NOCTTY)", claudeCases);
    await control("credentials-touched", "backend/usage.js",
        "    try { file = readHeld(Anchored, opened.fd, \".credentials.json\"); }\n    finally { fs.closeSync(opened.fd); }\n    if (file.kind === \"absent\") return { state: \"signed-out\" };",
        "    try { file = readHeld(Anchored, opened.fd, \".credentials.json\"); }\n    finally { fs.closeSync(opened.fd); }\n    if (file.kind === \"file\") fs.utimesSync(path.join(directory, \".credentials.json\"), new Date(), new Date());\n    if (file.kind === \"absent\") return { state: \"signed-out\" };",
        claudeCases);
    await control("request-deadline", "backend/usage.js", "request.destroy(); finish({ error: \"deadline\" });", "void request;", claudeCases);
    await control("throttle-failed", "backend/usage.js", '    if (reply.status === 429) return { state: "limited", email };',
        '    if (reply.status === 429) return lost("http-429");', claudeCases);
    fs.unlinkSync(path.join(linked, ".credentials.json"));

    // The account's email, from the `.claude.json` Claude Code reads for it:
    // HOME's for the default folder, the folder's own for any other. The
    // profiles are padded past the credential ceiling, as a real one is. An
    // absent or linked profile leaves the email empty and the read ok. No
    // account carries a plan.
    const emailHome = path.join(root, "email-home");
    const profile = (directory, email) => write(path.join(directory, ".claude.json"), JSON.stringify({
        oauthAccount: { emailAddress: email, accountUuid: "planted" }, projects: { padding: "x".repeat(150 * 1024) } }));
    claudeAccount(path.join(emailHome, ".claude"), HOUR, Date.now());
    profile(emailHome, "home@example.invalid");
    profile(path.join(emailHome, ".claude"), "inside-default@example.invalid");
    claudeAccount(path.join(emailHome, ".nclaude"), HOUR, Date.now());
    profile(path.join(emailHome, ".nclaude"), "n@example.invalid");
    claudeAccount(path.join(emailHome, ".2claude"), HOUR, Date.now());
    claudeAccount(path.join(emailHome, ".3claude"), HOUR, Date.now());
    fs.symlinkSync(path.join(emailHome, ".nclaude/.claude.json"), path.join(emailHome, ".3claude/.claude.json"));
    const emails = async folder => {
        mode("ok");
        const result = await usageIn(folder).read(tree, { PATH, HOME: emailHome, LANG: "C.UTF-8" }, { origin });
        assert.deepEqual(result.accounts.map(row => [row.label, row.state, row.email]).sort(), [
            ["2", "ok", ""], ["3", "ok", ""], ["default", "ok", "home@example.invalid"], ["n", "ok", "n@example.invalid"]]);
        for (const row of result.accounts) assert.equal("plan" in row, false, row.label + " carries no plan");
        mode("error");
        const failing = await usageIn(folder).read(tree, { PATH, HOME: emailHome, LANG: "C.UTF-8" }, { origin });
        assert.deepEqual(failing.accounts.map(row => [row.label, row.state, row.email]).sort(), [
            ["2", "failed", ""], ["3", "failed", ""], ["default", "failed", "home@example.invalid"], ["n", "failed", "n@example.invalid"]],
        "a failed read keeps the email");
    };
    await emails(plugin);
    cases++;
    await control("default-profile-in-folder", "backend/usage.js", 'profile: folder.source === "default" ? home : folder.directory',
        "profile: folder.directory", emails);
    await control("profile-email-dropped", "backend/usage.js",
        'return plain(account) && printable(account.emailAddress, 120) ? account.emailAddress : "";', 'return "";', emails);
    await control("profile-credential-ceiling", "backend/usage.js",
        'readHeld(Anchored, opened.fd, ".claude.json", PROFILE_MAX_BYTES)', 'readHeld(Anchored, opened.fd, ".claude.json")', emails);
    await control("profile-link-followed", "backend/usage.js", "fs.openSync(Anchored.child(fd, file), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_NOCTTY)",
        "fs.openSync(Anchored.child(fd, file), O_RDONLY | O_NONBLOCK | O_NOCTTY)", emails);
    await control("claude-failure-unnamed", "backend/usage.js",
        '    if (reply.status !== 200) return lost("http-" + reply.status);\n    let body;\n    try { body = JSON.parse(reply.body); } catch { return lost("reply-json"); }\n    const windows',
        '    if (reply.status !== 200) return failed("http-" + reply.status);\n    let body;\n    try { body = JSON.parse(reply.body); } catch { return lost("reply-json"); }\n    const windows', emails);
    await control("plan-published", "backend/usage.js", 'email: result.email || "",\n            state: result.state,',
        'email: result.email || "", plan: "max",\n            state: result.state,', emails);

    // Codex through the stand-in program: its answers, nothing run for a
    // folder with no auth.json, and the program dead after every read,
    // the deadline's included.
    const codexHome = path.join(root, "codex-home");
    const signed = codexAccount(path.join(codexHome, ".codex"));
    const noAuth = path.join(codexHome, ".codex-empty");
    fs.mkdirSync(noAuth, { recursive: true });
    // CODEX_FILE is the core's Codex account reader, or a disposable copy.
    const codexCases = async (folder, codexFile = path.join(tree, "bin/lib/codex-account.js")) => {
        const { readCodex } = usageIn(folder);
        const Codex = require(codexFile);
        const env = { PATH, HOME: codexHome };
        const readOf = (word, options = {}) => {
            write(path.join(signed, "stand-in-mode"), word + "\n");
            return readCodex(Anchored, Codex, signed, { command: codex, env, ...options });
        };
        const started = calls(signed).length;
        assert.deepEqual(await readOf("ok"), { state: "ok", email: "person@example.invalid", windows: [
            { name: "five_hour", usedPercent: 27, resetsAt: 1791223200000 },
            { name: "seven_day", usedPercent: 64, resetsAt: 1791561600000 }], details: { codexCredits: { balance: "12345" } } });
        const run = calls(signed).slice(started);
        assert.deepEqual(run.map(call => [call.args, call.codexHome]), [[["app-server"], signed]]);
        assert.deepEqual(await readOf("signed-out"), { state: "signed-out" });
        assert.deepEqual(await readOf("error"), { state: "failed", reason: "codex-error", email: "person@example.invalid" },
            "a rate-limit failure keeps the email account/read gave");
        const methods = path.join(signed, "stand-in-methods");
        fs.rmSync(methods, { force: true });
        assert.deepEqual(await readOf("api-key"), { state: "no-plan" }, "an API-key sign-in has no plan limits");
        assert.deepEqual(fs.readFileSync(methods, "utf8").trim().split("\n"), ["initialize", "initialized", "account/read"],
            "an API-key sign-in asks for no limits");
        assert.deepEqual(await readOf("hang", { deadlineMs: 1500 }), { state: "failed", reason: "codex-deadline", email: "person@example.invalid" });
        assert.equal(await ended(calls(signed).slice(started).map(call => call.pid)), true, "every program ended");
        assert.deepEqual(await readCodex(Anchored, Codex, noAuth, { command: codex, env }), { state: "signed-out" });
        assert.equal(calls(noAuth).length, 0, "nothing runs for a folder with no sign-in");
    };
    await codexCases(plugin);
    cases++;
    await fileControl("deadline-kept", path.join(tree, "bin/lib/codex-account.js"), '            child.stdin.destroy();\n            child.kill("SIGKILL");\n',
        '            child.stdin.destroy();\n', copy => codexCases(plugin, copy));
    await control("codex-failure-unnamed", "backend/usage.js",
        'return error.account !== null && error.account.kind === "chatgpt" ? { ...value, email: error.account.email } : value;', "return value;", codexCases);
    await control("api-key-limits", "backend/usage.js", '            if (account.kind !== "chatgpt") return { state: "no-plan" };\n', "", codexCases);
    for (const call of calls(signed)) if (alive(call.pid)) process.kill(call.pid, "SIGKILL");

    // Copilot through a fixture config, the stand-in keyring and the
    // stand-in endpoint. It reads current config keys only, then the keyring
    // in Copilot CLI's order, uses search with a user-agent, and never
    // changes config bytes.
    const copilotHome = path.join(root, "copilot-home");
    const copilotDir = copilotAccount(path.join(copilotHome, ".copilot"), { copilotTokens: TOKEN });
    const objectDir = copilotAccount(path.join(copilotHome, ".1copilot"), { copilotTokens: { "https://github.com:octo-user": TOKEN } });
    const keyringDir = copilotAccount(path.join(copilotHome, ".2copilot"));
    const plainDir = copilotAccount(path.join(copilotHome, ".3copilot"));
    const lockedDir = copilotAccount(path.join(copilotHome, ".4copilot"));
    const missingDir = copilotAccount(path.join(copilotHome, ".5copilot"));
    const foreignDir = copilotAccount(path.join(copilotHome, ".6copilot"), { lastLoggedInUser: { host: "https://github.example", login: "octo-user" } });
    const signedOutDir = copilotAccount(path.join(copilotHome, ".7copilot"), { lastLoggedInUser: { host: "https://github.com", login: "" } });
    const copilotBefore = credentials(copilotHome);
    const secretTool = path.join(standins, "secret-tool");
    const copilotEnv = { PATH, HOME: copilotHome, DBUS_SESSION_BUS_ADDRESS: "unix:path=/no-bus", XDG_RUNTIME_DIR: root };
    const tokenHash2 = crypto.createHash("sha256").update(TOKEN).digest("hex");
    const copilotCases = async folder => {
        const { copilotCredits, readCopilot } = usageIn(folder);
        const enterprise = { state: "ok", email: "octo-user", windows: [
            { name: "credits", usedPercent: 4.5225, resetsAt: Date.parse("2026-11-01T00:00:00.000Z") }],
            credits: { unit: "credits", used: 45225, granted: 1000000, monthUsed: 362327 },
            details: { copilotRenewsAt: Date.parse("2026-11-01T00:00:00.000Z"), copilotMonthUsed: 362327 } };
        mode("copilot");
        assert.deepEqual(copilotCredits({ copilot_plan: "enterprise" }), { state: "ok", windows: [], credits: null });
        assert.deepEqual(copilotCredits({ copilot_plan: "enterprise", quota_snapshots: { premium_interactions: {
            unlimited: true, token_based_billing: false } } }),
        { state: "ok", windows: [], credits: { unit: "requests", unlimited: true }, details: {} });
        assert.deepEqual(copilotCredits({ quota_snapshots: { premium_interactions: { entitlement: 0, token_based_billing: true } } }),
            { state: "ok", windows: [], credits: { unit: "credits", granted: 0 }, details: {} });
        assert.equal(copilotCredits({ quota_snapshots: { premium_interactions: { entitlement: -1, remaining: 0 } } }), null);
        assert.deepEqual(await readCopilot(Anchored, copilotDir, { origin, secretTool, env: copilotEnv }), enterprise);
        assert.deepEqual(await readCopilot(Anchored, objectDir, { origin, secretTool, env: copilotEnv }), enterprise);
        let last = requests().filter(row => row.path === "/copilot_internal/user").slice(-1)[0];
        assert.deepEqual([last.authHash, last.userAgent], [tokenHash2, "vgs-ai-usage"]);
        fs.writeFileSync(path.join(copilotHome, "secret-tool-mode"), "ok\n");
        fs.writeFileSync(path.join(copilotHome, "secret-tool-map.json"), JSON.stringify({ "https://github.com:octo-user:github": TOKEN }) + "\n");
        assert.deepEqual(await readCopilot(Anchored, keyringDir, { origin, secretTool, env: copilotEnv }), enterprise);
        assert.deepEqual(secretCalls(copilotHome).slice(-1)[0], ["search", "service", "copilot-cli", "username", "https://github.com:octo-user:github"]);
        fs.writeFileSync(path.join(copilotHome, "secret-tool-calls"), "");
        fs.writeFileSync(path.join(copilotHome, "secret-tool-map.json"), JSON.stringify({ "https://github.com:octo-user": TOKEN }) + "\n");
        assert.deepEqual(await readCopilot(Anchored, plainDir, { origin, secretTool, env: copilotEnv }), enterprise);
        assert.deepEqual(secretCalls(copilotHome), [
            ["search", "service", "copilot-cli", "username", "https://github.com:octo-user:github"],
            ["search", "service", "copilot-cli", "username", "https://github.com:octo-user"]]);
        fs.writeFileSync(path.join(copilotHome, "secret-tool-mode"), "locked\n");
        assert.deepEqual(await readCopilot(Anchored, lockedDir, { origin, secretTool, env: copilotEnv }), { state: "failed", reason: "keyring-locked", email: "octo-user" });
        fs.writeFileSync(path.join(copilotHome, "secret-tool-mode"), "missing\n");
        assert.deepEqual(await readCopilot(Anchored, missingDir, { origin, secretTool, env: copilotEnv }), { state: "failed", reason: "token-missing", email: "octo-user" });
        assert.deepEqual(await readCopilot(Anchored, missingDir, { origin, secretTool: path.join(standins, "absent-secret-tool"), env: copilotEnv }),
            { state: "failed", reason: "keyring-missing", email: "octo-user" });
        assert.deepEqual(await readCopilot(Anchored, foreignDir, { origin, secretTool, env: copilotEnv }), { state: "failed", reason: "copilot-host", email: "octo-user" });
        assert.deepEqual(await readCopilot(Anchored, signedOutDir, { origin, secretTool, env: copilotEnv }), { state: "signed-out" });
        mode("copilot-refused");
        assert.deepEqual(await readCopilot(Anchored, copilotDir, { origin, secretTool, env: copilotEnv }), { state: "expired", email: "octo-user" },
            "an expired sign-in keeps its login");
        mode("copilot-zero");
        assert.deepEqual((await readCopilot(Anchored, copilotDir, { origin, secretTool, env: copilotEnv })).credits,
            { unit: "credits", granted: 0 });
        mode("copilot-unlimited");
        assert.deepEqual((await readCopilot(Anchored, copilotDir, { origin, secretTool, env: copilotEnv })).credits,
            { unit: "credits", unlimited: true });
        mode("copilot-malformed");
        assert.deepEqual(await readCopilot(Anchored, copilotDir, { origin, secretTool, env: copilotEnv }), { state: "failed", reason: "reply-json", email: "octo-user" });
        assert.deepEqual(credentials(copilotHome), copilotBefore, "no Copilot config file changed");
    };
    await copilotCases(plugin);
    cases++;
    await control("copilot-credits-used", "backend/usage.js", "const used = entitlement - Math.max(remaining, 0);",
        "const used = snap.credits_used;", copilotCases);
    await control("copilot-expired-unnamed", "backend/usage.js", 'if (reply.status === 401) return { state: "expired", email };',
        'if (reply.status === 401) return { state: "expired" };', copilotCases);
    await control("copilot-failure-unnamed", "backend/usage.js", "const lost = reason => ({ ...failed(reason), email });\n    if (user.host",
        "const lost = failed;\n    if (user.host", copilotCases);
    await control("copilot-user-agent", "backend/usage.js", 'authorization: "token " + token.token, accept: "application/json", "user-agent": "vgs-ai-usage"',
        'authorization: "token " + token.token, accept: "application/json"', copilotCases);
    await control("secret-tool-search", "backend/usage.js", 'const result = await secretSearch(secretTool, ["service", "copilot-cli", "username", username], env);',
        'const result = await secretSearch(secretTool, ["service", "copilot-cli", "account", username], env);', copilotCases);
    await control("keyring-missing-unnamed", "backend/usage.js",
        '            if (status === 127) return finish({ kind: "failed", reason: "keyring-missing" });\n', "", copilotCases);

    // A reader killed while the keyring holds its answer takes secret-tool
    // with it: the search outlives no reader.
    const holdHome = path.join(root, "hold-home");
    const holdDir = copilotAccount(path.join(holdHome, ".copilot"));
    write(path.join(holdHome, "secret-tool-mode"), "hold\n");
    const held = [];
    const holdCase = async folder => {
        const pidFile = path.join(holdHome, "secret-tool-pid");
        fs.rmSync(pidFile, { force: true });
        const reader = cp.spawn(process.execPath, ["-e", `
const { readCopilot } = require(process.argv[1]);
readCopilot(require(process.argv[2]), process.argv[3], { origin: process.argv[4], secretTool: process.argv[5], env: process.env });`,
            path.join(folder, "backend/usage.js"), path.join(tree, "bin/lib/anchored.js"), holdDir, origin, secretTool],
        { env: { PATH, HOME: holdHome, LANG: "C.UTF-8" }, stdio: "ignore" });
        const exited = new Promise(resolve => reader.on("exit", resolve));
        try {
            const deadline = Date.now() + 5000;
            while (!(fs.existsSync(pidFile) && fs.readFileSync(pidFile, "utf8").endsWith("\n"))) {
                // A setup failure, not the red a control expects.
                if (Date.now() >= deadline) throw new Error("the stand-in secret-tool did not hold within 5 s");
                await new Promise(resolve => setTimeout(resolve, 20));
            }
            const pid = Number(fs.readFileSync(pidFile, "utf8"));
            held.push(pid);
            assert.equal(alive(pid), true, "the stand-in holds");
            reader.kill("SIGKILL");
            await exited;
            assert.equal(await ended([pid]), true, "secret-tool ends with its reader");
            held.splice(held.indexOf(pid), 1);
        } finally {
            reader.kill("SIGKILL");
        }
    };
    try {
        await holdCase(plugin);
        cases++;
        await control("secret-tool-outlives-reader", "backend/usage.js",
            'cp.spawn("setpriv", ["--pdeathsig", "KILL", "--", secretTool, "search"].concat(attrs), {',
            'cp.spawn(secretTool, ["search"].concat(attrs), {', holdCase);
    } finally {
        for (const pid of held) if (alive(pid)) process.kill(pid, "SIGKILL");
    }

    // AI Gateway is an owner-only extra. With its flag off, the helper does
    // not read the key and sends no Gateway request. With it on, it reads one
    // libsecret account, keeps the key out of output, and maps the credits
    // reply into a Gateway account and full-view details.
    const gatewayHome = path.join(root, "gateway-home");
    fs.mkdirSync(gatewayHome, { recursive: true });
    claudeAccount(path.join(gatewayHome, ".claude"), -HOUR, Date.now());
    const gatewayToken = "vga_" + TOKEN;
    const gatewayEnv = { PATH, HOME: gatewayHome, LANG: "C.UTF-8" };
    const gatewayCases = async folder => {
        const usage = usageIn(folder);
        fs.rmSync(path.join(gatewayHome, "secret-tool-calls"), { force: true });
        fs.writeFileSync(path.join(gatewayHome, "secret-tool-mode"), "ok\n");
        fs.writeFileSync(path.join(gatewayHome, "secret-tool-map.json"), JSON.stringify({ "vgs-ai-usage:ai-gateway": gatewayToken }) + "\n");
        mode("gateway-string");
        const beforeRequests = requests().length;
        const off = await usage.read(tree, gatewayEnv, { origin, gatewayOrigin: origin, secretTool, gateway: false });
        assert.equal(off.gatewayKey, null);
        assert.equal(secretCalls(gatewayHome).length, 0, "the extra-off read does not ask the keyring");
        assert.equal(requests().slice(beforeRequests).some(row => row.path === "/v1/credits"), false, "the extra-off read sends no Gateway request");
        const on = await usage.read(tree, gatewayEnv, { origin, gatewayOrigin: origin, secretTool, gateway: true });
        const gatewayAccount = on.accounts.find(row => row.provider === "gateway");
        assert.equal(on.gatewayKey, "present");
        assert.deepEqual(secretCalls(gatewayHome).slice(-1)[0], ["search", "service", "vgs-ai-usage", "account", "ai-gateway"]);
        assert.deepEqual(gatewayAccount.state, "ok");
        assert.deepEqual(gatewayAccount.details, { gateway: { balance: 10.5, totalUsed: 5.25 } });
        assert.deepEqual(gatewayAccount.windows.map(row => [row.name, row.usedPercent, row.resetsAt]), [["credits", 100 * 5.25 / 15.75, null]]);
        const lastGateway = requests().filter(row => row.path === "/v1/credits").slice(-1)[0];
        assert.deepEqual([lastGateway.token, lastGateway.userAgent], [crypto.createHash("sha256").update(gatewayToken).digest("hex"), "vgs-ai-usage"]);
        mode("gateway-malformed");
        assert.deepEqual((await usage.read(tree, gatewayEnv, { origin, gatewayOrigin: origin, secretTool, gateway: true })).accounts
            .filter(row => row.provider === "gateway").map(row => [row.state, row.windows]), [["failed", []]]);
        fs.writeFileSync(path.join(gatewayHome, "secret-tool-mode"), "missing\n");
        const missing = await usage.read(tree, gatewayEnv, { origin, gatewayOrigin: origin, secretTool, gateway: true });
        assert.equal(missing.gatewayKey, "absent");
        assert.equal(missing.accounts.some(row => row.provider === "gateway"), false);
        fs.writeFileSync(path.join(gatewayHome, "secret-tool-mode"), "locked\n");
        assert.equal((await usage.read(tree, gatewayEnv, { origin, gatewayOrigin: origin, secretTool, gateway: true })).gatewayKey, "locked");
        const child = await run([path.join(folder, "backend/usage.js"), "--tree", tree, "--gateway"], gatewayEnv);
        assert.equal(child.status, 0, child.stderr);
        assert.equal((child.stdout + child.stderr).includes(gatewayToken), false, "the Gateway key reaches no output");
    };
    await gatewayCases(plugin);
    cases++;
    await control("gateway-flag-ignored", "backend/usage.js", 'if (gateway) {', 'if (true) {', gatewayCases);
    await control("gateway-balance-string", "backend/usage.js", 'const balance = numberValue(body.balance);', 'const balance = typeof body.balance === "number" ? body.balance : undefined;', gatewayCases);
    await control("gateway-secret-service", "backend/usage.js", '["service", "vgs-ai-usage", "account", GATEWAY_ACCOUNT]', '["service", "copilot-cli", "account", GATEWAY_ACCOUNT]', gatewayCases);

    // Discovery includes Copilot homes and the account limit now covers the
    // owner's mix of Claude, Codex and Copilot directories without a partial
    // result. The GitHub Copilot extension folder is not a Copilot CLI home.
    const discoverHome = path.join(root, "discover-home");
    fs.mkdirSync(discoverHome, { recursive: true });
    for (const name of [".copilot", ".1copilot", ".github-copilot-cli"]) fs.mkdirSync(path.join(discoverHome, name));
    const discoverCases = async folder => {
        const { accountFolders } = require(path.join(tree, "bin/lib/account-folders.js"));
        const found = accountFolders({ home: discoverHome, config: path.join(discoverHome, ".config"),
            data: path.join(discoverHome, ".local/share"), env: {} });
        assert.ok(found.folders.some(row => row.provider === "copilot" && row.directory === path.join(discoverHome, ".copilot")));
        assert.ok(found.folders.some(row => row.provider === "copilot" && row.directory === path.join(discoverHome, ".1copilot")));
        assert.equal(found.folders.some(row => row.directory === path.join(discoverHome, ".github-copilot-cli")), false);
        assert.equal(viewIn(folder).NAMES.copilot, "Copilot");
    };
    await discoverCases(plugin);
    cases++;
    const limitHome = path.join(root, "limit-home");
    fs.mkdirSync(limitHome, { recursive: true });
    for (let i = 0; i < 15; i++) fs.mkdirSync(path.join(limitHome, "." + i + "claude"));
    for (let i = 0; i < 3; i++) fs.mkdirSync(path.join(limitHome, "." + i + "codex"));
    for (let i = 0; i < 2; i++) fs.mkdirSync(path.join(limitHome, "." + i + "copilot"));
    const limitCases = async folder => {
        const result = await usageIn(folder).read(tree, { PATH, HOME: limitHome, LANG: "C.UTF-8" }, { origin, copilotOrigin: origin, secretTool });
        assert.deepEqual([result.partial, result.accounts.length], ["", 20]);
        assert.deepEqual(result.accounts.map(row => row.state).filter(state => state !== "signed-out"), []);
    };
    await limitCases(plugin);
    cases++;
    const failedCopilot = async folder => {
        const failedHome = path.join(root, "failed-copilot");
        fs.rmSync(failedHome, { recursive: true, force: true });
        copilotAccount(path.join(failedHome, ".copilot"), { copilotTokens: TOKEN });
        mode("error");
        const result = await usageIn(folder).read(tree, { PATH, HOME: failedHome, LANG: "C.UTF-8" },
            { origin, copilotOrigin: origin, secretTool });
        assert.deepEqual(result.accounts.map(row => [row.provider, row.state, row.windows]), [["copilot", "failed", []]]);
    };
    await failedCopilot(plugin);
    cases++;
    await control("failed-copilot-zero", "backend/usage.js", "state: result.state, windows: result.windows || [], credits: result.credits || null",
        "state: result.state, windows: result.windows || [{ name: \"credits\", usedPercent: 0, resetsAt: null }], credits: result.credits || null",
        failedCopilot);

    // The whole read in a child, as the service runs it, over a HOME of
    // three accounts: the published status and every byte the child
    // printed hold no token, whatever the endpoint answers.
    const world = path.join(root, "world");
    claudeAccount(path.join(world, ".claude"), HOUR, Date.now());
    claudeAccount(path.join(world, ".config/.claude-work"), -HOUR, Date.now());
    codexAccount(path.join(world, ".codex"));
    copilotAccount(path.join(world, ".copilot"), { copilotTokens: TOKEN });
    const worldBefore = credentials(world);
    const env = { PATH, HOME: world, LANG: "C.UTF-8" };
    const driver = (folder, word) => {
        mode(word);
        return run(["-e", `
const usage = require(process.argv[1]);
usage.read(process.argv[2], process.env, { origin: process.argv[3], copilotOrigin: process.argv[3], secretTool: process.argv[4] }).then(r => process.stdout.write(JSON.stringify(r) + "\\n"));`,
            path.join(folder, "backend/usage.js"), tree, origin, secretTool], env);
    };
    const helperLines = [];
    const leaks = async folder => {
        const View = viewIn(plugin);
        for (const word of ["ok", "error", "malformed", "throttled"]) {
            const result = await driver(folder, word);
            if (folder === plugin) helperLines.push(...result.stderr.split("\n").filter(Boolean));
            assert.equal(result.status, 0, result.stderr);
            const reading = JSON.parse(result.stdout);
            const usage = View.merge(null, reading, NOW);
            const status = JSON.stringify([usage, View.signIn(usage, "claude"), View.signIn(usage, "codex"), View.signIn(usage, "copilot")]);
            for (const [where, text] of [["stdout", result.stdout], ["stderr", result.stderr], ["status", status]])
                assert.equal(text.includes(TOKEN), false, "the token reaches " + where + " for " + word);
            const states = Object.fromEntries(reading.accounts.map(row => [row.provider + "/" + row.label, row.state]));
            assert.deepEqual(states, { "claude/default": word === "ok" ? "ok" : word === "throttled" ? "limited" : "failed", "claude/work": "expired",
                "codex/default": "ok", "copilot/default": "failed" }, result.stderr);
        }
        assert.deepEqual(credentials(world), worldBefore, "no credential file changed");
    };
    await leaks(plugin);
    cases++;
    await control("token-in-log", "backend/usage.js",
        '    if (reply.status === 429) return { state: "limited", email };\n    if (reply.status !== 200) return lost("http-" + reply.status);',
        '    if (reply.status === 429) return { state: "limited", email };\n    if (reply.status !== 200) return lost("http-" + reply.status + "-" + oauth.accessToken);',
        leaks);
    await control("copilot-token-in-log", "backend/usage.js",
        '    if (reply.status === 401) return { state: "expired", email };\n    if (reply.status !== 200) return lost("http-" + reply.status);',
        '    if (reply.status === 401) return { state: "expired", email };\n    if (reply.status !== 200) return lost("http-" + reply.status + "-" + token.token);',
        leaks);

    // The shipped entry point under the same HOME, with no unexpired Claude
    // token, so it sends no request: one line of every account.
    const shippedRun = () => {
        const old = path.join(world, ".claude/.credentials.json");
        const copilotConfig = path.join(world, ".copilot/config.json");
        const saved = fs.readFileSync(old);
        const savedCopilot = fs.readFileSync(copilotConfig);
        claudeAccount(path.join(world, ".claude"), -HOUR, Date.now());
        write(copilotConfig, JSON.stringify({ lastLoggedInUser: { host: "https://github.com", login: "" } }));
        try {
            const result = cp.spawnSync(process.execPath, [path.join(plugin, "backend/usage.js"), "--tree", tree], { env, encoding: "utf8", timeout: 30000 });
            assert.equal(result.status, 0, result.stderr);
            const line = JSON.parse(result.stdout);
            assert.deepEqual([line.partial, line.accounts.map(row => [row.provider, row.label, row.state])],
                ["", [["claude", "default", "expired"], ["codex", "default", "ok"], ["copilot", "default", "signed-out"], ["claude", "work", "expired"]]]);
            assert.equal(result.stdout.includes(TOKEN) || result.stderr.includes(TOKEN), false);
            const refused = cp.spawnSync(process.execPath, [path.join(plugin, "backend/usage.js")], { env, encoding: "utf8" });
            assert.deepEqual([refused.status, refused.stdout, refused.stderr], [2, "", "ai-usage: arguments=expected-tree\n"]);
            helperLines.push(refused.stderr.trim());
        } finally {
            fs.writeFileSync(old, saved);
            fs.writeFileSync(copilotConfig, savedCopilot);
        }
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
        assert.ok(lines.some(line => /^ai-usage: account=claude-[0-9a-f]+ limited=http-429$/.test(line)), "a limited account prints its line");
        const View = viewIn(plugin);
        for (const line of lines) assert.equal(View.keyed(line), true, line);
        for (const line of ["node:internal/main", TOKEN, "ai-usage: read=" + TOKEN]) assert.equal(View.keyed(line), false, line);
    };
    logged(plugin);
    cases++;
    await control("read-line-unkeyed", "backend/usage.js", 'process.stderr.write("ai-usage: read=failed" + (key === null ? "" : " " + key[1]) + "\\n");',
        'process.stderr.write("ai-usage: read=" + (key === null ? "failed" : key[1]) + "\\n");', logged);

    // The view: the merge that keeps a failed read's last figures stale,
    // the widget's bar settings, warning tone and hidden state, the sign-in
    // rows and the panel's cards: provider titles, account lines, notes,
    // limits and reset times, and grouped whole credits.
    const reading = (state, windows) => ({ accounts: [
        { id: "claude-a", provider: "claude", label: "default", email: "", state, windows },
        { id: "codex-b", provider: "codex", label: "work", email: "person@example.invalid", state: "ok",
            windows: [{ name: "five_hour", usedPercent: 79, resetsAt: NOW + 61 * 60000 }] }], partial: "" });
    const views = folder => {
        const View = viewIn(folder);
        const plainOf = value => JSON.parse(JSON.stringify(value));
        const shown = (usage, settings, now = NOW) => { const w = View.widget(usage, settings, now); return [w.shown, w.percent, w.tone]; };
        const first = View.merge(null, reading("ok", [{ name: "seven_day", usedPercent: 80, resetsAt: NOW + 26 * HOUR }]), NOW);
        assert.deepEqual(shown(first), [true, 80, "warning"]);
        const failedRead = View.merge(first, reading("failed", []), NOW + 1);
        assert.deepEqual(plainOf(failedRead.accounts[0]), { id: "claude-a", provider: "claude", label: "default", email: "",
            state: "stale", windows: [{ name: "seven_day", usedPercent: 80, resetsAt: NOW + 26 * HOUR }], credits: null, details: {}, readAt: NOW },
        "a failed read keeps its last figures and when they were read");
        assert.equal(failedRead.readAt, NOW + 1);
        const failedRun = View.merge(first, null, NOW + 2);
        assert.deepEqual(plainOf(failedRun.accounts.map(row => [row.state, row.windows.length, row.readAt])), [["stale", 1, NOW], ["stale", 1, NOW]],
            "a failed run keeps each account's read time");
        assert.equal(failedRun.readAt, NOW + 2, "a failed check still completed");
        assert.equal(View.merge(null, null, NOW + 2).readAt, NOW + 2, "a failed first check still completed");

        // A limited read, the endpoint turning away a frequent read, keeps
        // the last figures with the time they were read, reads limited and
        // draws a plain note; once a kept window has reset, the figures read
        // as old. With none, the account reads limited with no figures.
        assert.deepEqual(plainOf(first.accounts.map(row => row.readAt)), [NOW, NOW], "an ok read sets its read time");
        const limitedRead = View.merge(first, reading("limited", []), NOW + 5 * 60000);
        const keptClaude = { id: "claude-a", provider: "claude", label: "default", email: "",
            state: "limited", windows: [{ name: "seven_day", usedPercent: 80, resetsAt: NOW + 26 * HOUR }], credits: null, details: {}, readAt: NOW };
        assert.deepEqual(plainOf(limitedRead.accounts[0]), keptClaude, "a limited read keeps the last figures, marked limited");
        assert.equal(limitedRead.readAt, NOW + 5 * 60000, "a limited run still answered");
        const limitedAgain = View.merge(limitedRead, reading("limited", []), NOW + 20 * 60000);
        assert.deepEqual(plainOf(limitedAgain.accounts[0]), keptClaude, "a second limited read keeps the first figures and their time");
        assert.deepEqual(plainOf(View.merge(limitedRead, null, NOW + 6 * 60000).accounts.map(row => [row.state, row.readAt])),
            [["limited", NOW], ["stale", NOW + 5 * 60000]], "a failed run leaves a limited account as it was");
        assert.deepEqual(plainOf((({ state, readAt, windows }) => [state, readAt, windows.length])(
            View.merge(limitedRead, reading("failed", []), NOW + 6 * 60000).accounts[0])), ["stale", NOW, 1],
        "a failed read after a limited one turns the kept figures stale");
        const card = (usage, now) => { const r = View.panel(usage, now)[0]; return [r.state, r.note, r.noteTone, r.windows.length]; };
        assert.deepEqual(card(limitedRead, NOW + 5 * 60000), ["limited", View.LIMITED_NOTE, "normal", 1], "kept figures draw a plain note");
        assert.deepEqual(card(limitedRead, NOW + 26 * HOUR), ["limited", View.STALE_NOTE, "warning", 1],
            "kept figures past a window's reset draw the stale warning");
        assert.deepEqual(card(limitedRead, NOW + 26 * HOUR - 1), ["limited", View.LIMITED_NOTE, "normal", 1], "a reset not yet passed is no warning");
        assert.deepEqual(shown(limitedRead, null, NOW + 5 * 60000), [true, 80, "warning"], "the bar counts the kept share");
        const tip = (usage, now) => View.widget(usage, null, now).tooltip;
        const okTip = tip(first, NOW + 5 * 60000);
        const staleTip = tip(failedRead, NOW + 5 * 60000);
        const limitedTip = tip(limitedRead, NOW + 5 * 60000);
        assert.deepEqual([limitedTip === okTip, limitedTip === staleTip, staleTip === okTip], [false, false, false],
            "kept figures name their own tooltip");
        assert.equal(tip(limitedRead, NOW + 26 * HOUR), tip(failedRead, NOW + 26 * HOUR), "kept figures past a reset take the stale tooltip");
        const limitedFirst = View.merge(null, reading("limited", []), NOW);
        assert.deepEqual(plainOf([limitedFirst.accounts[0].state, limitedFirst.accounts[0].windows, limitedFirst.accounts[0].readAt]),
            ["limited", [], null], "a limited first read holds no figures");
        const limitedEmpty = View.panel(limitedFirst, NOW)[0];
        assert.deepEqual([limitedEmpty.note, limitedEmpty.noteTone], [View.LIMITED_NOTE, "normal"],
            "a limited account with no figures draws a plain note");
        assert.deepEqual(shown(limitedFirst), [true, 79, "normal"], "a limited account adds no share");
        assert.equal(tip(limitedFirst, NOW), tip(View.merge(null, reading("signed-out", []), NOW), NOW), "a limited account with no figures adds nothing to the tooltip");
        const limitedIdle = View.merge(View.merge(null, reading("ok", [{ name: "five_hour", usedPercent: 0, resetsAt: null }]), NOW),
            reading("limited", []), NOW + 1);
        assert.deepEqual(card(limitedIdle, NOW + 1), ["limited", View.LIMITED_NOTE, "normal", 0], "kept figures with no use draw no limits");
        const refusedRead = View.panel(View.merge(first, reading("expired", []), NOW + 1), NOW + 1)[0];
        assert.deepEqual([refusedRead.state, refusedRead.note, refusedRead.noteTone], ["expired", View.EXPIRED.claude, "warning"],
            "a refused token still reads expired");
        const erroredRead = View.panel(failedRead, NOW + 1)[0];
        assert.deepEqual([erroredRead.state, erroredRead.note, erroredRead.noteTone], ["stale", View.STALE_NOTE, "warning"],
            "a server error still reads stale");
        // One age represents the completed helper batch, including a
        // partial batch whose kept figures have an earlier read time.
        const age = (readAt, ms) => View.checkedText(readAt, readAt === null ? NOW : readAt + ms);
        assert.equal(age(null, 0), "");
        assert.notEqual(age(NOW, 0), "");
        assert.equal(age(NOW, 59000), age(NOW, 0));
        assert.notEqual(age(NOW, 60000), age(NOW, 59000));
        assert.notEqual(age(NOW, 4 * 60000), age(NOW, 2 * HOUR));
        assert.equal(age(NOW, 2 * HOUR), age(NOW, 2 * HOUR + 59000));
        const tenOn = NOW + 10 * 60000;
        const limitedTen = View.merge(first, reading("limited", []), tenOn);
        assert.notEqual(View.checkedText(limitedTen.readAt, tenOn), View.checkedText(limitedTen.accounts[0].readAt, tenOn));
        assert.equal(limitedTen.accounts[0].readAt, NOW);
        assert.equal(View.checkedText(limitedTen.readAt, tenOn), age(NOW, 0));
        assert.equal(View.panel(limitedTen, tenOn)[0].note, View.LIMITED_NOTE);
        assert.equal(View.panel(View.merge(first, reading("failed", []), tenOn), tenOn)[0].note, View.STALE_NOTE);
        const never = View.merge(null, reading("failed", []), NOW);
        assert.deepEqual(plainOf(never.accounts[0].windows), [], "a failed first read holds no window");
        assert.deepEqual(shown(View.merge(null, { accounts: [never.accounts[0]], partial: "" }, NOW)), [true, null, "normal"],
            "a failed read shows no share");
        const below = View.merge(null, reading("ok", [{ name: "five_hour", usedPercent: 12, resetsAt: null }]), NOW);
        assert.deepEqual(shown(below), [true, 79, "normal"], "the highest share across accounts");
        const only = state => View.merge(null, { accounts: [{ id: "c", provider: "codex", label: "x", email: "", state,
            windows: [] }], partial: "" }, NOW);
        for (const usage of [null, { accounts: [], readAt: NOW }, only("signed-out")])
            assert.equal(View.widget(usage, null, NOW).shown, false, "no sign-in hides the widget");
        assert.equal(View.widget(only("no-plan"), null, NOW).shown, true, "an API sign-in can open its card");

        // The bar settings over three accounts: peaks 80 and 20, and one
        // with no window, which no figure counts as 0. The defaults draw
        // what the bar drew before the settings: the most used, in the
        // warning tone.
        const bar = View.merge(null, { accounts: [
            { id: "a", provider: "claude", label: "a", email: "", state: "ok", windows: [
                { name: "five_hour", usedPercent: 10, resetsAt: NOW + HOUR }, { name: "seven_day", usedPercent: 80, resetsAt: NOW + 26 * HOUR }] },
            { id: "b", provider: "codex", label: "b", email: "", state: "ok", windows: [{ name: "five_hour", usedPercent: 20, resetsAt: NOW + HOUR }] },
            { id: "c", provider: "claude", label: "c", email: "", state: "ok", windows: [] }], partial: "" }, NOW);
        const barOf = settings => { const w = View.widget(bar, settings, NOW); return [w.used, w.percent, w.text, w.tone]; };
        for (const [settings, want] of [
            [null, [80, 80, "80%", "warning"]],
            [{}, [80, 80, "80%", "warning"]],
            [{ barNumber: "most-used", barShows: "used", colourByUsage: true }, [80, 80, "80%", "warning"]],
            [{ barNumber: "average" }, [50, 50, "50%", "normal"]],
            [{ barNumber: "most-left" }, [20, 20, "20%", "normal"]],
            [{ barShows: "left" }, [80, 20, "20%", "warning"]],
            [{ barNumber: "most-left", barShows: "left" }, [20, 80, "80%", "normal"]],
            [{ colourByUsage: false }, [80, 80, "80%", "normal"]]])
            assert.deepEqual(barOf(settings), want, JSON.stringify(settings));
        assert.notEqual(View.widget(bar, { barShows: "left" }, NOW).tooltip, View.widget(bar, {}, NOW).tooltip, "the tooltip names the share shown");

        const row = (usage, provider) => { const r = View.signIn(usage, provider); return [r.tone, r.action === true]; };
        assert.deepEqual(row(null, "claude"), ["info", true], "no sign-in offers Sign in");
        assert.deepEqual(row(first, "claude"), ["ok", false]);
        assert.deepEqual(row(only("no-plan"), "codex"), ["info", false], "an API-key sign-in is no failure and offers nothing");
        assert.deepEqual(row(View.merge(first, reading("failed", []), NOW), "claude"), ["ok", false], "stale figures stay signed in");
        assert.deepEqual(row(View.merge(null, reading("failed", []), NOW), "claude"), ["danger", false]);
        assert.deepEqual(row(View.merge(null, reading("limited", []), NOW), "claude"), ["ok", false], "a limited account stays signed in");
        assert.equal(View.signIn(View.merge(null, reading("expired", []), NOW), "claude").text, View.EXPIRED.claude);

        // A card's title is the provider's name alone, never the folder's
        // label; its account line is the email the helper read.
        assert.deepEqual(plainOf(View.panel(first, NOW).map(r => [r.id, r.title, r.label, r.email, r.state,
            r.windows.map(w => [w.name, w.percent, w.tone, w.resetIn])])), [
            ["claude-a", View.NAMES.claude, "default", "", "ok", [["seven_day", 80, "danger", { kind: "in", days: 1, hours: 2, minutes: 0 }]]],
            ["codex-b", View.NAMES.codex, "work", "person@example.invalid", "ok", [["five_hour", 79, "warning", { kind: "in", days: 0, hours: 1, minutes: 1 }]]]]);
        for (const r of View.panel(first, NOW)) assert.equal("plan" in r, false, r.id + " carries no plan");
        // The reset reads as the time left alone.
        for (const [resetAt, text] of [[null, ""], [NOW, "now"], [NOW + 59000, "1m"], [NOW + 61 * 60000, "1h 1m"], [NOW + 4 * 24 * HOUR, "4d 0h"]])
            assert.equal(View.resetText(resetAt, NOW), text);

        // An account whose every window reads 0 % has had no use: a note in
        // the normal tone and no limit rows. A window with no use and no
        // reset time beside one in use reads not started.
        const fresh = View.merge(null, { accounts: [
            { id: "claude-n", provider: "claude", label: "n", email: "n@example.invalid", state: "ok", windows: [
                { name: "five_hour", usedPercent: 0, resetsAt: null }, { name: "seven_day", usedPercent: 0, resetsAt: NOW + 26 * HOUR },
                { name: "seven_day_fable", usedPercent: 0, resetsAt: NOW + 26 * HOUR }] },
            { id: "claude-m", provider: "claude", label: "m", email: "", state: "ok", windows: [
                { name: "five_hour", usedPercent: 0, resetsAt: null }, { name: "seven_day", usedPercent: 40, resetsAt: NOW + 26 * HOUR }] }],
        partial: "" }, NOW);
        const [idle, half] = View.panel(fresh, NOW);
        assert.deepEqual(plainOf([idle.windows, idle.noteTone, idle.note !== ""]), [[], "normal", true], "an unused account shows no limits");
        assert.deepEqual(plainOf(half.windows.map(w => [w.name, w.started, w.percent, w.reset, w.text === "0%"])),
            [["five_hour", false, 0, "", false], ["seven_day", true, 40, "1d 2h", false]]);
        assert.equal(half.windows[1].text, "40%");
        assert.deepEqual([half.note, half.noteTone], ["", "normal"]);
        assert.deepEqual(shown(fresh), [true, 40, "normal"], "the bar keeps the used account's share");
        const pool = View.panel(View.merge(null, { accounts: [{ id: "copilot-p", provider: "copilot", label: "default", email: "octo-user",
            state: "ok", credits: { unit: "requests", used: 0, granted: 300, monthUsed: 0 }, details: {},
            windows: [{ name: "credits", usedPercent: 0, resetsAt: Date.parse("2026-11-01T00:00:00Z") }] }], partial: "" }, NOW), NOW)[0];
        assert.deepEqual(plainOf([pool.note, pool.windows.map(w => [w.name, w.text, w.started])]), ["", [["credits", "0 of 300", true]]],
            "a credit pool at 0 used keeps its allowance");

        // The account line is only the reported email or login.
        const nameless = View.merge(null, { accounts: [
            { id: "claude-n", provider: "claude", label: "n", email: "", state: "expired", windows: [] },
            { id: "claude-d", provider: "claude", label: "default", email: "", state: "expired", windows: [] },
            { id: "copilot-w", provider: "copilot", label: "work", email: "octo-user", state: "failed", windows: [] },
            { id: "gateway-x", provider: "gateway", label: "AI Gateway", email: "", state: "failed", windows: [] }], partial: "" }, NOW);
        assert.deepEqual(View.panel(nameless, NOW).map(r => [r.id, r.account]),
            [["claude-n", ""], ["claude-d", ""], ["copilot-w", "octo-user"], ["gateway-x", ""]]);

        const copilot = View.merge(null, { accounts: [{ id: "copilot-a", provider: "copilot", label: "work", email: "octo-user",
            state: "ok", credits: { unit: "credits", used: 45225, granted: 1000000, monthUsed: 362327 },
            details: { copilotMonthUsed: 362327, copilotRenewsAt: Date.parse("2026-11-01T00:00:00Z") },
            windows: [{ name: "credits", usedPercent: 4.5225, resetsAt: Date.parse("2026-11-01T00:00:00Z") }] },
        { id: "copilot-b", provider: "copilot", label: "zero", email: "zero-user", state: "ok",
            credits: { unit: "requests", granted: 0 }, details: {}, windows: [] },
        { id: "claude-enterprise", provider: "claude", label: "enterprise", email: "", state: "ok",
            credits: null, details: {}, windows: [] },
        { id: "codex-c", provider: "codex", label: "c", email: "c@example.invalid", state: "ok", credits: null,
            details: { codexCredits: { balance: "59295.2328000000" } }, windows: [{ name: "five_hour", usedPercent: 3, resetsAt: NOW + HOUR }] },
        { id: "gateway-a", provider: "gateway", label: "AI Gateway", email: "", state: "ok", credits: null,
            details: { gateway: { balance: 10.5, totalUsed: 5.25 } }, windows: [{ name: "credits", usedPercent: 33.3333333333, resetsAt: null }] }], partial: "" }, NOW);
        assert.deepEqual(plainOf(View.panel(copilot, NOW).map(r => [r.id, r.title, r.email, r.detail, r.note,
            r.windows.map(w => [w.label, w.text, w.percent, w.started]), r.details.map(d => [d.label, d.value])])), [
            ["claude-enterprise", "Claude Code", "", "", "This plan reports no usage limits.", [], []],
            ["codex-c", "Codex", "c@example.invalid", "", "", [["5-hour limit", "3%", 3, true]], [["Codex credits", "59,295 available"]]],
            ["copilot-a", "Copilot", "octo-user", "", "", [["AI credits", "45.2k of 1M", 4.5225, true]], [["Month credits used", "362k"], ["Renews", "2026-11-01"]]],
            ["copilot-b", "Copilot", "zero-user", "No premium request pool", "", [], []],
            ["gateway-a", "AI Gateway", "", "", "", [["AI Gateway credits", "33%", 33.3333333333, true]], [["Balance left", "$10.50"], ["Total used", "$5.25"]]]]);
        assert.deepEqual(["0", "999", "1,000", "59,295", "1,234,568", ""].map((want, i) =>
            [View.wholeNumber([0, "999.4", 999.5, "59295.2328000000", 1234567.8, "credits"][i]), want]).filter(r => r[0] !== r[1]), []);
        assert.deepEqual(shown(copilot, { showCopilot: false }), [true, 33.3333333333, "normal"], "provider filters remove Copilot from the widget");
        assert.deepEqual(View.panel(copilot, NOW, { showCopilot: false }).map(r => r.provider), ["claude", "codex", "gateway"]);
        assert.deepEqual(View.panel(copilot, NOW, { hidden: [{ account: "" }] }).map(r => r.id), ["claude-enterprise", "codex-c", "copilot-b", "gateway-a"], "empty hidden account means the first offer");
        assert.deepEqual(View.accountChoices(copilot).map(r => r.value), ["copilot-a", "copilot-b", "claude-enterprise", "codex-c", "gateway-a"]);
        assert.equal(View.panel(copilot, NOW, { aiGateway: false }).some(r => r.provider === "gateway"), false);
        assert.equal(View.panel(copilot, NOW, { aiGateway: true }).some(r => r.provider === "gateway"), true);
        assert.deepEqual(plainOf(View.gatewayKey("present")), [{ label: "AI Gateway", value: "present", secret: "ai-gateway" }]);
        const failedCreditless = View.merge(copilot, { accounts: [{ id: "copilot-b", provider: "copilot", label: "zero",
            email: "", state: "failed", windows: [], credits: null }], partial: "" }, NOW + 1);
        assert.deepEqual(plainOf(failedCreditless.accounts[0]), { id: "copilot-b", provider: "copilot", label: "zero",
            email: "zero-user", state: "stale", windows: [], credits: { unit: "requests", granted: 0 }, details: {}, readAt: NOW },
        "a failed read keeps credit data that has no meter");
        const expiredCard = View.panel(View.merge(null, { accounts: [{ id: "copilot-expired", provider: "copilot", label: "default",
            email: "", state: "expired", windows: [], credits: null }], partial: "" }, NOW), NOW)[0];
        assert.deepEqual([expiredCard.note, expiredCard.noteTone], [View.EXPIRED.copilot, "warning"]);
        assert.deepEqual(["950", "1.04k", "45.2k", "362k", "1M"].map(function (want, i) {
            return [View.compact([950, 1043, 45225, 362327, 1000000][i]), want];
        }).every(function (row) { return row[0] === row[1]; }), true);
        assert.deepEqual(plainOf([View.resetIn(null, NOW), View.resetIn(NOW - 1, NOW), View.resetIn(NOW + 59000, NOW),
            View.resetIn(NOW + (3 * 1440 + 6 * 60 + 30) * 60000, NOW)]),
            [{ kind: "none" }, { kind: "now" }, { kind: "in", days: 0, hours: 0, minutes: 1 }, { kind: "in", days: 3, hours: 6, minutes: 30 }]);
        assert.deepEqual(plainOf(["five_hour", "seven_day", "seven_day_fable", "minutes_120", "primary"].map(View.limitOf)),
            [{ minutes: 300, model: "" }, { minutes: 10080, model: "" }, { minutes: 10080, model: "fable" }, { minutes: 120, model: "" },
                { minutes: null, model: "" }]);
    };
    const cardChanges = folder => {
        const View = viewIn(folder);
        const usage = View.merge(null, { accounts: [
            { id: "copilot-z", provider: "copilot", label: "work", email: "z@example.invalid", state: "ok", windows: [
                { name: "credits", usedPercent: 10, resetsAt: NOW + HOUR }] },
            { id: "codex-b", provider: "codex", label: "default", email: "B@example.invalid", state: "ok", windows: [
                { name: "five_hour", usedPercent: 20, resetsAt: NOW + HOUR }, { name: "seven_day", usedPercent: 90, resetsAt: NOW + HOUR }] },
            { id: "claude-a", provider: "claude", label: "work", email: "a@example.invalid", state: "limited", windows: [
                { name: "five_hour", usedPercent: 50, resetsAt: NOW + HOUR }] },
            { id: "codex-api", provider: "codex", label: "api", email: "", state: "no-plan", windows: [] },
            { id: "gateway-api", provider: "gateway", label: "AI Gateway", email: "", state: "ok", windows: [
                { name: "credits", usedPercent: 30, resetsAt: null }] }
        ] }, NOW);
        for (const [sort, ids] of [
            ["provider", ["claude-a", "codex-b", "codex-api", "copilot-z", "gateway-api"]],
            ["email", ["codex-api", "gateway-api", "claude-a", "codex-b", "copilot-z"]],
            ["most-left", ["copilot-z", "gateway-api", "claude-a", "codex-b", "codex-api"]]
        ]) assert.deepEqual(View.panel(usage, NOW, { sort }).map(r => r.id), ids, sort);
        assert.deepEqual(usage.accounts.map(r => r.id), ["copilot-z", "codex-b", "claude-a", "codex-api", "gateway-api"], "sorting leaves published order unchanged");
        assert.deepEqual(View.panel({ accounts: [] }, NOW, { sort: "most-left" }), []);
        for (const [used, tone] of [[0, "success"], [49.99, "success"], [50, "warning"], [79.99, "warning"], [80, "danger"], [100, "danger"], [120, "danger"]]) {
            const window = View.windowRow({ provider: "claude" }, { name: "five_hour", usedPercent: used, resetsAt: NOW + HOUR }, NOW);
            assert.equal(window.tone, tone, "used=" + used);
        }
        const cards = View.panel(usage, NOW, { sort: "provider" });
        assert.deepEqual(cards.map(r => [r.id, r.api]), [["claude-a", false], ["codex-b", false], ["codex-api", true], ["copilot-z", false], ["gateway-api", true]]);
        assert.equal(cards.find(r => r.id === "codex-api").note, View.NO_PLAN);
        assert.equal(cards.find(r => r.id === "codex-api").account, "", "an API key without an email has no account line");
        for (const provider of new Set(cards.map(card => card.provider))) {
            const source = View.logo(provider, "#ffabcdef");
            assert.ok(source.startsWith("data:image/svg+xml,"));
            assert.ok(decodeURIComponent(source).includes('fill="#abcdef"'));
            assert.ok(decodeURIComponent(source).includes('fill-opacity="1"'));
            assert.ok(decodeURIComponent(View.logo(provider, "#80123456")).includes('fill="#123456" fill-opacity="' + 128 / 255 + '"'));
            assert.ok(decodeURIComponent(source).includes('<path '));
        }
        assert.equal(View.logo("unknown", "#ffabcdef"), "");
    };
    cardChanges(plugin);
    cases++;
    await control("codex-mark-removed", "UsageView.js", '    "codex": ', '    "absent-codex": ', cardChanges);
    await control("provider-sort-ignored", "UsageView.js", "return a.provider.localeCompare(b.provider);", "return 0;", cardChanges);
    await control("email-sort-ignored", "UsageView.js", 'if (mode === "email") {', 'if (false) {', cardChanges);
    await control("room-sort-ignored", "UsageView.js", 'if (mode === "most-left") {', 'if (false) {', cardChanges);
    await control("room-lowest-limit", "UsageView.js", 'return row.windows.length === 0 ? Infinity : Math.max.apply', 'return row.windows.length === 0 ? Infinity : Math.min.apply', cardChanges);
    await control("medium-boundary", "UsageView.js", "percent >= MEDIUM_PERCENT", "percent > MEDIUM_PERCENT", cardChanges);
    await control("almost-out-boundary", "UsageView.js", "percent >= WARNING_PERCENT", "percent > WARNING_PERCENT", cardChanges);
    await control("api-chip-absent", "UsageView.js", 'api: row.state === "no-plan" || row.provider === "gateway"', 'api: false', cardChanges);
    await control("logo-absent", "UsageView.js", 'var mark = MARKS[provider];', 'var mark = undefined;', cardChanges);
    await control("logo-qt-color", "UsageView.js", 'var rgb = "#" + color.slice(3);', 'var rgb = color;', cardChanges);
    views(plugin);
    cases++;
    await control("stale-dropped", "UsageView.js", 'if ((row.state === "failed" || row.state === "limited") && last !== null && hasFigures(last))',
        "if (false)", views);
    await control("limited-dropped", "UsageView.js", 'if ((row.state === "failed" || row.state === "limited") && last !== null && hasFigures(last))',
        'if (row.state === "failed" && last !== null && hasFigures(last))', views);
    await control("limited-stale", "UsageView.js", 'state: row.state === "limited" ? "limited" : "stale",', 'state: "stale",', views);
    await control("limited-ok", "UsageView.js", 'state: row.state === "limited" ? "limited" : "stale",', 'state: row.state === "limited" ? "ok" : "stale",', views);
    await control("limited-run-stale", "UsageView.js", 'if (row.state === "ok") copy.state = "stale";',
        'if (row.state === "ok" || row.state === "limited") copy.state = "stale";', views);
    await control("limited-past-reset-ignored", "UsageView.js",
        ': row.state === "stale" || (row.state === "limited" && pastReset(row, now)) ? STALE_NOTE', ': row.state === "stale" ? STALE_NOTE', views);
    await control("reset-boundary", "UsageView.js", "item.resetsAt <= now; });", "item.resetsAt < now; });", views);
    await control("limited-tip-dropped", "UsageView.js", '    else if (limited) tooltip += ". " + LIMITED_TIP;\n', "", views);
    await control("limited-tip-past-reset", "UsageView.js",
        'if (row.state === "stale" || (row.state === "limited" && pastReset(row, now))) stale = true;', 'if (row.state === "stale") stale = true;', views);
    await control("limited-unused-ignored", "UsageView.js", 'return (row.state === "ok" || row.state === "limited") && row.windows.length > 0',
        'return row.state === "ok" && row.windows.length > 0', views);
    await control("kept-read-time-dropped", "UsageView.js", "                readAt: last.readAt });", "                readAt: now });", views);
    await control("read-time-unset", "UsageView.js", 'return accountCopy(row, { readAt: row.state === "ok" ? now : null });',
        "return accountCopy(row, { readAt: null });", views);
    await control("run-read-time-dropped", "UsageView.js", "var copy = accountCopy(row, { readAt: row.readAt });", "var copy = accountCopy(row);", views);
    await control("failed-check-time-kept", "UsageView.js", "}), readAt: now, gatewayKey: previous.gatewayKey", "}), readAt: previous.readAt, gatewayKey: previous.gatewayKey", views);
    await control("first-failed-check-time-absent", "UsageView.js", "return { accounts: [], readAt: now, gatewayKey: null };", "return { accounts: [], readAt: null, gatewayKey: null };", views);
    await control("limited-warned", "UsageView.js", 'noteTone: warning !== "" ? "warning" : "normal"',
        'noteTone: warning !== "" || row.state === "limited" ? "warning" : "normal"', views);
    await control("limited-signed-out", "UsageView.js", 'return row.state === "ok" || row.state === "stale" || row.state === "limited"; }))',
        'return row.state === "ok" || row.state === "stale"; }))', views);
    await control("checked-minute-floor", "UsageView.js", 'return seconds < 60 ? "Last checked just now"', 'return seconds < 1 ? "Last checked just now"', views);
    await control("plan-kept", "UsageView.js", 'email: row.email || "",\n        state: row.state,', 'email: row.email || "", plan: row.plan || "",\n        state: row.state,', views);
    await control("warning-boundary", "UsageView.js", 'used >= WARNING_PERCENT ? "warning"', 'used > WARNING_PERCENT ? "warning"', views);
    await control("lowest-share", "UsageView.js", "    return Math.max.apply(null, peaks);", "    return Math.min.apply(null, peaks);", views);
    await control("average-ignored", "UsageView.js",
        "    if (mode === \"average\") return Math.round(peaks.reduce(function (sum, peak) { return sum + peak; }, 0) / peaks.length);\n", "", views);
    await control("most-left-ignored", "UsageView.js", '    if (mode === "most-left") return Math.min.apply(null, peaks);\n', "", views);
    await control("windowless-counted", "UsageView.js",
        "        if (row.windows.length > 0)\n            peaks.push(Math.max.apply(null, row.windows.map(function (item) { return item.usedPercent; })));",
        "        peaks.push(Math.max.apply(null, [0].concat(row.windows.map(function (item) { return item.usedPercent; }))));", views);
    await control("left-ignored", "UsageView.js", "var percent = used === null ? null : left ? Math.max(0, 100 - used) : used;", "var percent = used;", views);
    await control("colour-ignored", "UsageView.js", "given.colourByUsage !== false && ", "", views);
    await control("always-shown", "UsageView.js", "shown: accounts.length > 0", "shown: true", views);
    await control("api-account-hidden", "UsageView.js", 'return row.state !== "signed-out";', 'return row.state !== "signed-out" && row.state !== "no-plan";', views);
    await control("gateway-switch-ignored", "UsageView.js", 'if (provider === "gateway") return settings.aiGateway !== false;', 'if (provider === "gateway") return true;', views);
    await control("provider-filter-ignored", "UsageView.js", 'if (provider === "copilot") return settings.showCopilot !== false;', 'if (provider === "copilot") return true;', views);
    await control("hidden-first-ignored", "UsageView.js", 'if (id === "") id = first;', 'if (id === "") id = "";', views);
    await control("details-dropped", "UsageView.js", 'if (d.gateway !== undefined) {', 'if (false) {', views);
    await control("reset-rounded-down", "UsageView.js", "var minutes = Math.ceil((resetsAt - now) / 60000);", "var minutes = Math.floor((resetsAt - now) / 60000);", views);
    await control("reset-prefixed", "UsageView.js", "    return Commons.Duration.format(seconds, seconds < 3600 ? 1 : 2);",
        '    return "Resets in " + Commons.Duration.format(seconds, seconds < 3600 ? 1 : 2);', views);
    await control("no-reset-drawn", "UsageView.js", 'if (left.kind === "none") return "";', 'if (left.kind === "none") return "No reset time";', views);
    await control("title-labelled", "UsageView.js", "title: NAMES[row.provider] || row.provider,",
        'title: (NAMES[row.provider] || row.provider) + (row.label === "default" ? "" : " · " + row.label),', views);
    await control("unused-limits-drawn", "UsageView.js", "windows: idle ? [] : row.windows.map(", "windows: row.windows.map(", views);
    await control("not-started-percent", "UsageView.js", 'return item.name === "credits" || item.usedPercent > 0 || ', "return true || ", views);
    await control("pool-unused", "UsageView.js", 'return item.name !== "credits" && item.usedPercent === 0;', "return item.usedPercent === 0;", views);
    await control("account-folder-fallback", "UsageView.js", "    return row.email;", "    return row.email || row.label;", views);
    await control("credits-raw", "UsageView.js", '    return (whole < 0 ? "-" : "") + grouped(String(Math.abs(whole)));', "    return String(n);", views);

    // The sign-in TUIs run each tool's own login, through the presentation
    // library, with the stand-ins on PATH.
    const signIns = folder => {
        for (const [script, tool, argv] of [["sign-in-claude.sh", "claude", "auth login"], ["sign-in-codex.sh", "codex", "login"], ["gateway-key.sh", "xdg-open", "https://vercel.com/dashboard"]]) {
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
    await control("gateway-opener-skipped", "tui/gateway-key.sh", "\nxdg-open https://vercel.com/dashboard\n", "\ntrue\n", signIns);
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
