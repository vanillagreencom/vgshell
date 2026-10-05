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

    // The shipped origin is Claude Code's own endpoint; the copy the smoke
    // row plants, edited as scripts/smoke/fixtures/ai-usage/origin.py edits
    // it, is not.
    const shipped = folder => assert.equal(usageIn(folder).ORIGIN, "https://api.anthropic.com");
    shipped(plugin);
    cases++;
    await control("origin-edited", "backend/usage.js", 'const ORIGIN = "https://api.anthropic.com";',
        'const ORIGIN = "http://127.0.0.1:9";', shipped);

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
        const readOf = (directory, word) => { mode(word); return readClaude(Anchored, directory, { origin, now: NOW }); };
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
        assert.deepEqual(await readOf("hang", { deadlineMs: 1500 }), { state: "failed", reason: "codex-deadline" });
        await new Promise(resolve => setTimeout(resolve, 200));
        assert.deepEqual(calls(signed).slice(started).filter(call => alive(call.pid)).map(call => call.pid), [], "every program ended");
        assert.deepEqual(await readCodex(Anchored, noAuth, { command: codex, env }), { state: "signed-out" });
        assert.equal(calls(noAuth).length, 0, "nothing runs for a folder with no sign-in");
    };
    await codexCases(plugin);
    cases++;
    await control("deadline-kept", "backend/usage.js", '            child.kill("SIGKILL");\n', "", codexCases);
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
    const leaks = async folder => {
        const View = viewIn(plugin);
        for (const word of ["ok", "error", "malformed"]) {
            const result = await driver(folder, word);
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
        } finally { fs.writeFileSync(old, saved); }
    };
    const sentBefore = requests().length;
    shippedRun();
    assert.equal(requests().length, sentBefore, "the shipped run sent nothing to the stand-in");
    cases++;

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
        const first = View.merge(null, reading("ok", [{ name: "seven_day", usedPercent: 80, resetsAt: NOW + 26 * HOUR }]), NOW);
        assert.deepEqual(plainOf(View.widget(first)), { shown: true, percent: 80, tone: "warning", text: "80%",
            tooltip: "Highest plan limit used: 80%" });
        const failedRead = View.merge(first, reading("failed", []), NOW + 1);
        assert.deepEqual(plainOf(failedRead.accounts[0]), { id: "claude-a", provider: "claude", label: "default", email: "", plan: "max",
            state: "stale", windows: [{ name: "seven_day", usedPercent: 80, resetsAt: NOW + 26 * HOUR }] }, "a failed read keeps its last figures");
        assert.equal(failedRead.readAt, NOW + 1);
        const failedRun = View.merge(first, null, NOW + 2);
        assert.deepEqual(plainOf(failedRun.accounts.map(row => [row.state, row.windows.length])), [["stale", 1], ["stale", 1]]);
        assert.equal(failedRun.readAt, NOW);
        const never = View.merge(null, reading("failed", []), NOW);
        assert.deepEqual(plainOf(never.accounts[0].windows), [], "a failed first read holds no window");
        assert.deepEqual(plainOf(View.widget(View.merge(null, { accounts: [never.accounts[0]], partial: "" }, NOW))),
            { shown: true, percent: null, tone: "normal", text: "", tooltip: "No usage figures yet" }, "a failed read shows no share");
        const below = View.merge(null, reading("ok", [{ name: "five_hour", usedPercent: 12, resetsAt: null }]), NOW);
        assert.deepEqual([View.widget(below).percent, View.widget(below).tone], [79, "normal"], "the highest share across accounts");
        for (const usage of [null, { accounts: [], readAt: NOW }, View.merge(null, { accounts: [{ id: "c", provider: "codex", label: "x",
            email: "", plan: "", state: "signed-out", windows: [] }], partial: "" }, NOW)])
            assert.equal(View.widget(usage).shown, false, "no signed-in account hides the widget");
        assert.deepEqual(plainOf(View.signIn(null, "claude")), { tone: "info", text: "Not signed in", action: true });
        assert.deepEqual(plainOf(View.signIn(first, "claude")), { tone: "ok", text: "Signed in" });
        assert.deepEqual(plainOf(View.signIn(View.merge(null, reading("expired", []), NOW), "claude")),
            { tone: "warning", text: "Open Claude Code to refresh the sign-in" });
        assert.deepEqual(plainOf(View.panel(first, NOW)), [
            { id: "claude-a", title: "Claude Code", detail: "Max plan", note: "", windows: [
                { label: "Weekly limit", percent: 80, text: "80%", tone: "warning", reset: "Resets in 1 d 2 h" }] },
            { id: "codex-b", title: "Codex · work", detail: "person@example.invalid · Plus plan", note: "", windows: [
                { label: "5-hour limit", percent: 79, text: "79%", tone: "normal", reset: "Resets in 1 h 1 min" }] }]);
        assert.deepEqual([View.resetText(null, NOW), View.resetText(NOW - 1, NOW), View.resetText(NOW + 59000, NOW)],
            ["No reset time", "Resets now", "Resets in 1 min"]);
        assert.deepEqual(["seven_day_opus", "minutes_1440", "minutes_120", "primary"].map(View.windowLabel),
            ["Weekly Opus limit", "1-day limit", "2-hour limit", "Short limit"]);
    };
    views(plugin);
    cases++;
    await control("stale-dropped", "UsageView.js", 'if (row.state === "failed" && last !== null && last.windows.length > 0)', "if (false)", views);
    await control("warning-boundary", "UsageView.js", "percent !== null && percent >= WARNING_PERCENT", "percent !== null && percent > WARNING_PERCENT", views);
    await control("lowest-share", "UsageView.js", "row.windows[j].usedPercent > percent", "row.windows[j].usedPercent < percent", views);
    await control("always-shown", "UsageView.js", "shown: accounts.length > 0", "shown: true", views);

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
    if (server !== null) server.close();
    fs.rmSync(root, { recursive: true, force: true });
}).catch(error => {
    console.error(error);
    process.exitCode = 1;
});
