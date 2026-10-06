#!/usr/bin/env node
// usage.js --tree ABSOLUTE_VGS_TREE
// Reads the plan limits of every Claude Code, Codex and Copilot account the
// core's account discovery finds, and optionally Vercel AI Gateway credits
// from the keyring, through each provider's own sign-in or secret, and
// prints one JSON line on stdout: { accounts: [{ id, provider, label, email,
// state, windows: [{ name, usedPercent, resetsAt }], credits, details }],
// partial, gatewayKey }. email is the account's email address, or the login
// where the provider gives no email (Copilot), else "".
// state is ok, expired, signed-out, no-plan for a sign-in that has no plan
// limits, or failed; a window the tool does not report is left out, never
// read as 0. Diagnostics are lines of `ai-usage: <key>=<value>` pairs on
// stderr. No token or reply body reaches either stream; of what the tools
// report, only an account's email, windows and credit totals do.
// Nothing here writes or refreshes a credential file.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");
const crypto = require("node:crypto");
const { O_RDONLY, O_NOFOLLOW, O_NONBLOCK, O_NOCTTY } = fs.constants;

// The usage endpoint Claude Code itself reads, with its OAuth beta header.
const ORIGIN = "https://api.anthropic.com";
const USAGE_PATH = "/api/oauth/usage";
const OAUTH_BETA = "oauth-2025-04-20";
const COPILOT_ORIGIN = "https://api.github.com";
const COPILOT_PATH = "/copilot_internal/user";
const GATEWAY_ORIGIN = "https://ai-gateway.vercel.sh";
const GATEWAY_PATH = "/v1/credits";
const GATEWAY_ACCOUNT = "ai-gateway";
// Bounds on a stalled endpoint or program, not latency budgets.
const REQUEST_MS = 15000;
const CODEX_MS = 20000;
const SECRET_TOOL_MS = 5000;
// The largest credential file and reply read; a larger one is refused.
const MAX_BYTES = 64 * 1024;
const MAX_LINE_BYTES = 1024 * 1024;
// The largest Claude Code profile (.claude.json) read for the account's
// email. Claude Code keeps per-project history in it, so it grows with use:
// 147,884 bytes on the owner's ~/.nclaude/.claude.json (stat, 2026-10-06). A
// larger one leaves the email unread.
const PROFILE_MAX_BYTES = 4 * 1024 * 1024;
// The accounts read in one run; past it the run is partial.
const MAX_ACCOUNTS = 32;
const CLIENT = Object.freeze({ name: "vgs_ai_usage", title: "VGS AI usage", version: "1" });

function plain(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function printable(value, max) {
    return typeof value === "string" && value.length > 0 && value.length <= max && !/[\x00-\x1f\x7f]/.test(value);
}
function failed(reason) { return { state: "failed", reason }; }

// A percentage the tool reported, or undefined for a value of another shape.
function percent(value) {
    return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : undefined;
}

function numberValue(value) {
    if (typeof value === "boolean" || value === null || value === undefined) return undefined;
    if (typeof value === "number") return Number.isFinite(value) ? value : undefined;
    if (typeof value === "string" && value.trim() !== "") {
        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : undefined;
    }
    return undefined;
}

function resetTime(value) {
    if (value === null || value === undefined) return null;
    const resetsAt = Date.parse(value);
    return Number.isFinite(resetsAt) ? resetsAt : undefined;
}

function slug(value) {
    if (!printable(value, 80)) return "other";
    const text = value.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
    return text || "other";
}

function claudeWindow(name, value) {
    if (value === undefined || value === null) return undefined;
    if (!plain(value)) return null;
    const usedPercent = percent(value.utilization);
    const resetsAt = resetTime(value.resets_at);
    if (usedPercent === undefined || resetsAt === undefined) return null;
    return { name, usedPercent, resetsAt };
}

/**
 * The windows of a Claude usage reply recorded from Claude Code's usage
 * endpoint: five_hour and seven_day as { utilization, resets_at }, followed
 * by each limits[] entry whose kind is weekly_scoped. A scoped model named
 * Fable becomes seven_day_fable. A window the reply leaves out or holds as
 * null is absent. Returns the windows, or null for a reply that is no object
 * or holds a present window of another shape.
 */
function claudeWindows(body) {
    if (!plain(body)) return null;
    const windows = [];
    for (const name of ["five_hour", "seven_day"]) {
        const window = claudeWindow(name, body[name]);
        if (window === null) return null;
        if (window !== undefined) windows.push(window);
    }
    if (body.limits !== undefined && body.limits !== null && !Array.isArray(body.limits)) return null;
    for (const entry of Array.isArray(body.limits) ? body.limits : []) {
        if (!plain(entry) || entry.kind !== "weekly_scoped") continue;
        const usedPercent = percent(entry.percent);
        const resetsAt = resetTime(entry.resets_at);
        if (usedPercent === undefined || resetsAt === undefined) return null;
        const name = "seven_day_" + slug(entry.scope?.model?.display_name);
        windows.push({ name, usedPercent, resetsAt });
    }
    return windows;
}

/**
 * Claude's extra_usage details when the reply enables them. monthly_limit
 * and used_credits are minor currency units, cents as v1 claudebar read
 * them, so display values divide by 100. A reply without extra_usage keeps
 * the details empty; a present extra_usage of another shape fails the reply.
 */
function claudeDetails(body) {
    if (!plain(body)) return {};
    const extra = plain(body.extra_usage) ? body.extra_usage : null;
    if (extra === null || extra.is_enabled !== true) return {};
    const limit = numberValue(extra.monthly_limit);
    const used = numberValue(extra.used_credits);
    if (limit === undefined || used === undefined) return null;
    const out = { claudeExtra: { used: used / 100, limit: limit / 100 } };
    if (printable(extra.currency, 12)) out.claudeExtra.currency = extra.currency;
    const utilization = percent(extra.utilization);
    if (utilization !== undefined) out.claudeExtra.utilization = utilization;
    return out;
}

/**
 * The windows and credit balance of a Codex rate-limit reply,
 * `account/rateLimits/read`'s result: rateLimits.primary and .secondary,
 * each { usedPercent, windowDurationMins, resetsAt } with resetsAt in Unix
 * seconds, named by their length: five_hour, seven_day or minutes_<n>, else
 * primary or secondary; and rateLimits.credits, a CreditsSnapshot. Returns
 * { windows, details }, or null for a reply of another shape. Source:
 * codex-rs/app-server-protocol/src/protocol/v2/account.rs,
 * GetAccountRateLimitsResponse, RateLimitSnapshot, RateLimitWindow and
 * CreditsSnapshot.
 */
function codexWindows(result) {
    if (!plain(result) || !plain(result.rateLimits)) return null;
    const snapshot = result.rateLimits;
    const windows = [];
    for (const slot of ["primary", "secondary"]) {
        const value = snapshot[slot];
        if (value === undefined || value === null) continue;
        if (!plain(value)) return null;
        const usedPercent = percent(value.usedPercent);
        const minutes = value.windowDurationMins;
        const resets = value.resetsAt;
        if (usedPercent === undefined || (minutes !== undefined && minutes !== null && !Number.isSafeInteger(minutes))
            || (resets !== undefined && resets !== null && !Number.isSafeInteger(resets))) return null;
        const name = minutes === 300 ? "five_hour" : minutes === 10080 ? "seven_day"
            : Number.isSafeInteger(minutes) ? "minutes_" + minutes : slot;
        windows.push({ name, usedPercent, resetsAt: Number.isSafeInteger(resets) ? resets * 1000 : null });
    }
    const details = {};
    if (snapshot.credits !== undefined && snapshot.credits !== null) {
        const credits = snapshot.credits;
        if (!plain(credits) || typeof credits.hasCredits !== "boolean" || typeof credits.unlimited !== "boolean"
            || (credits.balance !== null && credits.balance !== undefined && typeof credits.balance !== "string")) return null;
        if (credits.unlimited === true) details.codexCredits = { unlimited: true };
        else if (credits.hasCredits === true) {
            details.codexCredits = {};
            if (credits.balance !== null && credits.balance !== undefined) details.codexCredits.balance = credits.balance;
        }
    }
    return { windows, details };
}

/**
 * The credential file FILE inside the held directory FD, read once without
 * following a link, refused past MAX bytes: { kind: "absent" },
 * { kind: "file", text } or { kind: "refused", reason }.
 */
function readHeld(Anchored, fd, file, max = MAX_BYTES) {
    let handle;
    try {
        handle = fs.openSync(Anchored.child(fd, file), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_NOCTTY);
        const stat = fs.fstatSync(handle);
        if (!stat.isFile()) return { kind: "refused", reason: "credentials-not-file" };
        if (stat.size > max) return { kind: "refused", reason: "credentials-size" };
        return { kind: "file", text: fs.readFileSync(handle, "utf8") };
    } catch (error) {
        if (error.code === "ENOENT") return { kind: "absent" };
        return { kind: "refused", reason: error.code === "ELOOP" ? "credentials-link" : "credentials-unreadable" };
    } finally { if (handle !== undefined) fs.closeSync(handle); }
}

// One GET of URL with HEADERS under the deadline: { status, body } with the
// body cut off past MAX_BYTES, or { error } for a failed or late request.
function get(url, headers, deadlineMs) {
    const transport = require(url.protocol === "https:" ? "node:https" : "node:http");
    return new Promise(resolve => {
        let done = false;
        const finish = value => { if (!done) { done = true; clearTimeout(timer); resolve(value); } };
        const request = transport.request(url, { method: "GET", headers }, response => {
            const chunks = [];
            let size = 0;
            response.on("data", chunk => {
                size += chunk.length;
                if (size > MAX_BYTES) { request.destroy(); finish({ error: "reply-size" }); return; }
                chunks.push(chunk);
            });
            response.on("end", () => finish({ status: response.statusCode, body: Buffer.concat(chunks).toString("utf8") }));
            response.on("error", () => finish({ error: "reply-failed" }));
        });
        const timer = setTimeout(() => { request.destroy(); finish({ error: "deadline" }); }, deadlineMs);
        request.on("error", () => finish({ error: "request-failed" }));
        request.end();
    });
}

/**
 * The email of the Claude Code profile `.claude.json` in PROFILE, its
 * oauthAccount.emailAddress, read without following a link; "" when the
 * file is absent, unreadable, too large or holds no email, since the email
 * only names the account and never fails its read.
 */
function claudeEmail(Anchored, profile) {
    const opened = Anchored.directory(profile);
    if (opened.kind !== "directory") return "";
    let file;
    try { file = readHeld(Anchored, opened.fd, ".claude.json", PROFILE_MAX_BYTES); }
    finally { fs.closeSync(opened.fd); }
    if (file.kind !== "file") return "";
    let account;
    try { account = JSON.parse(file.text).oauthAccount; } catch { return ""; }
    return plain(account) && printable(account.emailAddress, 120) ? account.emailAddress : "";
}

/**
 * The Claude Code account in DIRECTORY: its `.credentials.json`, read
 * without following a link and never written, then one GET of the usage
 * endpoint at ORIGIN with the access token. An expired token sends nothing
 * and reads expired, as does a token the endpoint refuses. PROFILE is the
 * folder whose `.claude.json` Claude Code reads for this account, which
 * names its email.
 */
async function readClaude(Anchored, directory, { origin = ORIGIN, now = Date.now(), deadlineMs = REQUEST_MS, profile = directory } = {}) {
    const opened = Anchored.directory(directory);
    if (opened.kind === "absent") return { state: "signed-out" };
    if (opened.kind !== "directory") return failed("directory-" + opened.kind);
    let file;
    try { file = readHeld(Anchored, opened.fd, ".credentials.json"); }
    finally { fs.closeSync(opened.fd); }
    if (file.kind === "absent") return { state: "signed-out" };
    if (file.kind === "refused") return failed(file.reason);
    let oauth;
    try { oauth = JSON.parse(file.text).claudeAiOauth; } catch { return failed("credentials-json"); }
    if (oauth === undefined) return { state: "signed-out" };
    if (!plain(oauth) || !printable(oauth.accessToken, 8192) || typeof oauth.expiresAt !== "number")
        return failed("credentials-shape");
    const email = claudeEmail(Anchored, profile);
    const lost = reason => ({ ...failed(reason), email });
    if (oauth.expiresAt <= now) return { state: "expired", email };
    const reply = await get(new URL(USAGE_PATH, origin), {
        authorization: "Bearer " + oauth.accessToken, "anthropic-beta": OAUTH_BETA, accept: "application/json"
    }, deadlineMs);
    if (reply.error) return lost(reply.error);
    if (reply.status === 401 || reply.status === 403) return { state: "expired", email };
    if (reply.status !== 200) return lost("http-" + reply.status);
    let body;
    try { body = JSON.parse(reply.body); } catch { return lost("reply-json"); }
    const windows = claudeWindows(body);
    const details = claudeDetails(body);
    if (windows === null || details === null) return lost("reply-shape");
    return { state: "ok", email, windows, details };
}

/**
 * The Codex account in DIRECTORY: nothing runs unless its auth.json is
 * there; then `codex app-server` with CODEX_HOME set to it, asked over
 * JSON-RPC on stdio for `initialize`, the `initialized` notification,
 * `account/read` and `account/rateLimits/read` (codex-rs/app-server/README.md
 * and codex-rs/app-server-protocol/src/protocol/v2/account.rs). The program
 * is killed at the deadline and once both answers are in; setpriv kills it
 * when this process dies first.
 */
async function readCodex(Anchored, directory, { command = "codex", deadlineMs = CODEX_MS, env = process.env } = {}) {
    const opened = Anchored.directory(directory);
    if (opened.kind === "absent") return { state: "signed-out" };
    if (opened.kind !== "directory") return failed("directory-" + opened.kind);
    let marker;
    try {
        const stat = fs.lstatSync(Anchored.child(opened.fd, "auth.json"));
        marker = stat.isFile() ? "present" : "refused";
    } catch (error) { marker = error.code === "ENOENT" ? "absent" : "refused"; }
    finally { fs.closeSync(opened.fd); }
    if (marker === "absent") return { state: "signed-out" };
    if (marker === "refused") return failed("marker");
    const child = cp.spawn("setpriv", ["--pdeathsig", "KILL", "--", command, "app-server"], {
        cwd: env.HOME, stdio: ["pipe", "pipe", "ignore"],
        env: { PATH: env.PATH || "/usr/bin:/bin", HOME: env.HOME, LANG: "C.UTF-8", CODEX_HOME: directory }
    });
    children.add(child);
    return new Promise(resolve => {
        let done = false;
        let account = null;
        let tail = "";
        // A read that fails once account/read named the account keeps its
        // email, so the card still says whose it is.
        const finish = value => {
            if (done) return;
            done = true;
            clearTimeout(timer);
            child.stdin.destroy();
            child.kill("SIGKILL");
            resolve(account !== null && value.state === "failed" ? { ...value, email: account.email } : value);
        };
        const send = message => child.stdin.write(JSON.stringify(message) + "\n");
        const timer = setTimeout(() => finish(failed("codex-deadline")), deadlineMs);
        child.on("error", error => finish(failed(error.code === "ENOENT" ? "setpriv-missing" : "codex-start")));
        child.on("exit", () => { children.delete(child); finish(failed("codex-exited")); });
        child.stdin.on("error", () => finish(failed("codex-exited")));
        const receive = line => {
            let message;
            try { message = JSON.parse(line); } catch { return finish(failed("codex-line")); }
            if (!plain(message) || ![1, 2, 3].includes(message.id) || message.method !== undefined) return;
            if (message.error !== undefined || !plain(message.result)) return finish(failed("codex-error"));
            if (message.id === 1) {
                send({ method: "initialized" });
                send({ id: 2, method: "account/read", params: { refreshToken: false } });
            } else if (message.id === 2) {
                const value = message.result.account;
                if (value === null || value === undefined) return finish({ state: "signed-out" });
                if (!plain(value)) return finish(failed("codex-account"));
                // account is { type: "chatgpt", email, planType } or
                // { type: "apiKey" }. Only a ChatGPT sign-in has plan limits;
                // Codex refuses the rate-limit read for any other
                // (codex-rs/app-server/src/request_processors/account_processor.rs).
                if (value.type !== "chatgpt") return finish({ state: "no-plan" });
                account = { email: printable(value.email, 120) ? value.email : "" };
                send({ id: 3, method: "account/rateLimits/read" });
            } else {
                const read = codexWindows(message.result);
                if (read === null) return finish(failed("codex-shape"));
                finish({ state: "ok", email: account.email, windows: read.windows, details: read.details });
            }
        };
        child.stdout.on("data", chunk => {
            tail += chunk.toString("utf8");
            if (tail.length > MAX_LINE_BYTES) return finish(failed("codex-line-size"));
            let at;
            while (!done && (at = tail.indexOf("\n")) >= 0) {
                const line = tail.slice(0, at);
                tail = tail.slice(at + 1);
                if (line.trim() !== "") receive(line);
            }
        });
        send({ id: 1, method: "initialize", params: { clientInfo: { ...CLIENT } } });
    });
}

function uncommentJson(text) {
    return text.split(/\r?\n/).filter(line => !/^\s*\/\//.test(line)).join("\n");
}

function childEnv(env) {
    const result = { LANG: "C.UTF-8" };
    for (const name of ["PATH", "HOME", "DBUS_SESSION_BUS_ADDRESS", "XDG_RUNTIME_DIR"])
        if (env[name]) result[name] = env[name];
    return result;
}

// setpriv kills secret-tool when this process dies first, as readCodex's
// program; the timer below lives only as long as this process. setpriv
// exits 127 when it cannot find the program and 126 when it cannot run it
// (util-linux 2.42 setpriv, checked by a run).
function secretSearch(secretTool, attrs, env) {
    return new Promise(resolve => {
        const child = cp.spawn("setpriv", ["--pdeathsig", "KILL", "--", secretTool, "search"].concat(attrs), {
            stdio: ["ignore", "pipe", "pipe"], env: childEnv(env), cwd: env.HOME || undefined
        });
        let stdout = "";
        let stderr = "";
        let done = false;
        const finish = value => {
            if (done) return;
            done = true;
            clearTimeout(timer);
            resolve(value);
        };
        const timer = setTimeout(() => {
            child.kill("SIGKILL");
            finish({ kind: "failed", reason: "keyring-failed" });
        }, SECRET_TOOL_MS);
        child.on("error", error => finish({ kind: "failed", reason: error.code === "ENOENT" ? "setpriv-missing" : "keyring-failed" }));
        child.stdout.on("data", chunk => {
            stdout += chunk.toString("utf8");
            if (stdout.length > MAX_BYTES) {
                child.kill("SIGKILL");
                finish({ kind: "failed", reason: "keyring-failed" });
            }
        });
        child.stderr.on("data", chunk => {
            stderr += chunk.toString("utf8");
            if (stderr.length > MAX_BYTES) {
                child.kill("SIGKILL");
                finish({ kind: "failed", reason: "keyring-failed" });
            }
        });
        child.on("close", status => {
            if (done) return;
            if (status === 127) return finish({ kind: "failed", reason: "keyring-missing" });
            if (status !== 0) return finish({ kind: "failed", reason: "keyring-failed" });
            for (const line of stdout.split(/\r?\n/)) {
                if (line.startsWith("secret = ")) {
                    const value = line.slice("secret = ".length);
                    return finish(printable(value, 8192) ? { kind: "found", token: value } : { kind: "failed", reason: "token-missing" });
                }
            }
            if (stdout.split(/\r?\n/).some(line => line.startsWith("label = ")))
                return finish({ kind: "failed", reason: "keyring-locked" });
            finish({ kind: "absent" });
        });
    });
}

async function copilotToken(config, host, login, secretTool, env) {
    const tokens = config.copilotTokens;
    if (printable(tokens, 8192)) return { kind: "found", token: tokens };
    if (plain(tokens) && printable(tokens[host + ":" + login], 8192))
        return { kind: "found", token: tokens[host + ":" + login] };
    for (const username of [host + ":" + login + ":github", host + ":" + login]) {
        const result = await secretSearch(secretTool, ["service", "copilot-cli", "username", username], env);
        if (result.kind !== "absent") return result;
    }
    return { kind: "failed", reason: "token-missing" };
}

function copilotCredits(body) {
    if (!plain(body)) return null;
    const snap = plain(body.quota_snapshots) && plain(body.quota_snapshots.premium_interactions)
        ? body.quota_snapshots.premium_interactions : null;
    if (snap === null) return { state: "ok", windows: [], credits: null };
    const unit = (snap.token_based_billing ?? body.token_based_billing) === true ? "credits" : "requests";
    const resetsAt = resetTime(body.quota_reset_date_utc);
    if (resetsAt === undefined) return null;
    const details = {};
    if (resetsAt !== null) details.copilotRenewsAt = resetsAt;
    if (snap.unlimited === true) return { state: "ok", windows: [], credits: { unit, unlimited: true }, details };
    const entitlement = snap.entitlement;
    const remaining = snap.remaining;
    if (entitlement === 0) return { state: "ok", windows: [], credits: { unit, granted: 0 }, details };
    if (!Number.isFinite(entitlement) || entitlement < 0 || !Number.isFinite(remaining)) return null;
    const used = entitlement - Math.max(remaining, 0);
    const monthUsed = Number.isFinite(snap.credits_used) && snap.credits_used >= 0 ? snap.credits_used : null;
    if (monthUsed !== null) details.copilotMonthUsed = monthUsed;
    return { state: "ok", windows: [{ name: "credits", usedPercent: used * 100 / entitlement, resetsAt }],
        credits: { unit, used, granted: entitlement, monthUsed }, details };
}

async function readCopilot(Anchored, directory, { origin = COPILOT_ORIGIN, secretTool = "secret-tool", env = process.env,
    deadlineMs = REQUEST_MS } = {}) {
    const opened = Anchored.directory(directory);
    if (opened.kind === "absent") return { state: "signed-out" };
    if (opened.kind !== "directory") return failed("directory-" + opened.kind);
    let file;
    try { file = readHeld(Anchored, opened.fd, "config.json"); }
    finally { fs.closeSync(opened.fd); }
    if (file.kind === "absent") return { state: "signed-out" };
    if (file.kind === "refused") return failed(file.reason);
    let config;
    try { config = JSON.parse(uncommentJson(file.text)); } catch { return failed("config-json"); }
    const user = plain(config.lastLoggedInUser) ? config.lastLoggedInUser : null;
    if (user === null || typeof user.login !== "string" || user.login.trim() === "") return { state: "signed-out" };
    const login = user.login;
    // Copilot gives no email: the login names the account, on every read
    // from here on, failed or expired ones too.
    const email = printable(login, 120) ? login : "";
    const lost = reason => ({ ...failed(reason), email });
    if (user.host !== "https://github.com") return lost("copilot-host");
    const token = await copilotToken(config, user.host, login, secretTool, env);
    if (token.kind !== "found") return lost(token.reason);
    const reply = await get(new URL(COPILOT_PATH, origin), {
        authorization: "token " + token.token, accept: "application/json", "user-agent": "vgs-ai-usage"
    }, deadlineMs);
    if (reply.error) return lost(reply.error);
    if (reply.status === 401) return { state: "expired", email };
    if (reply.status !== 200) return lost("http-" + reply.status);
    let body;
    try { body = JSON.parse(reply.body); } catch { return lost("reply-json"); }
    const credits = copilotCredits(body);
    if (credits === null) return lost("reply-shape");
    return { ...credits, email };
}

async function gatewaySecret(secretTool, env) {
    const result = await secretSearch(secretTool, ["service", "vgs-ai-usage", "account", GATEWAY_ACCOUNT], env);
    if (result.kind === "failed" && result.reason === "keyring-locked") return { kind: "locked" };
    if (result.kind === "failed") return { kind: "unavailable", reason: result.reason };
    return result;
}

function gatewayCredits(body) {
    if (!plain(body)) return null;
    const balance = numberValue(body.balance);
    const totalUsed = numberValue(body.total_used);
    if (balance === undefined || totalUsed === undefined || balance < 0 || totalUsed < 0) return null;
    const pool = balance + totalUsed;
    return { balance, totalUsed, usedPercent: pool > 0 ? totalUsed * 100 / pool : 0 };
}

async function readGateway({ origin = GATEWAY_ORIGIN, secretTool = "secret-tool", env = process.env, deadlineMs = REQUEST_MS } = {}) {
    const secret = await gatewaySecret(secretTool, env);
    if (secret.kind !== "found") return { key: secret.kind === "locked" ? "locked" : secret.kind === "absent" ? "absent" : "unavailable", account: null };
    const reply = await get(new URL(GATEWAY_PATH, origin), {
        authorization: "Bearer " + secret.token, accept: "application/json", "user-agent": "vgs-ai-usage"
    }, deadlineMs);
    const id = "gateway-" + crypto.createHash("sha256").update(GATEWAY_ACCOUNT).digest("hex").slice(0, 12);
    const base = { id, provider: "gateway", label: "AI Gateway", email: "", windows: [], credits: null, details: {} };
    if (reply.error) return { key: "present", account: { ...base, state: "failed", reason: reply.error } };
    if (reply.status === 401 || reply.status === 403) return { key: "present", account: { ...base, state: "expired" } };
    if (reply.status !== 200) return { key: "present", account: { ...base, state: "failed", reason: "http-" + reply.status } };
    let body;
    try { body = JSON.parse(reply.body); } catch { return { key: "present", account: { ...base, state: "failed", reason: "reply-json" } }; }
    const credits = gatewayCredits(body);
    if (credits === null) return { key: "present", account: { ...base, state: "failed", reason: "reply-shape" } };
    return { key: "present", account: { ...base, state: "ok",
        windows: [{ name: "credits", usedPercent: credits.usedPercent, resetsAt: null }],
        details: { gateway: { balance: credits.balance, totalUsed: credits.totalUsed } } } };
}

// Every live app-server, killed if this process ends before its read does.
const children = new Set();
process.on("exit", () => { for (const child of children) child.kill("SIGKILL"); });

/**
 * Every account the core's discovery finds under ENV's HOME, XDG config
 * and data homes and explicit roots, read at once, Claude's at ORIGIN. A
 * directory that is absent is no account; one past MAX_ACCOUNTS is not read
 * and the run is partial "account-limit".
 */
async function read(tree, env, { origin = ORIGIN, copilotOrigin = COPILOT_ORIGIN, gatewayOrigin = GATEWAY_ORIGIN, secretTool = "secret-tool", gateway = false } = {}) {
    const Anchored = require(path.join(tree, "bin/lib/anchored.js"));
    const { accountFolders } = require(path.join(tree, "bin/lib/account-folders.js"));
    const home = env.HOME;
    const found = accountFolders({ home, config: env.XDG_CONFIG_HOME || path.join(home, ".config"),
        data: env.XDG_DATA_HOME || path.join(home, ".local/share"), env });
    const folders = found.folders.filter(folder => {
        const opened = Anchored.directory(folder.directory);
        if (opened.kind === "directory") fs.closeSync(opened.fd);
        return opened.kind !== "absent";
    });
    let partial = found.partial;
    if (folders.length > MAX_ACCOUNTS) partial ||= "account-limit";
    const accounts = await Promise.all(folders.slice(0, MAX_ACCOUNTS).map(async folder => {
        // Claude Code reads the default folder's profile from HOME and any
        // other folder's from inside it.
        const result = folder.provider === "claude" ? await readClaude(Anchored, folder.directory,
            { origin, profile: folder.source === "default" ? home : folder.directory })
            : folder.provider === "copilot" ? await readCopilot(Anchored, folder.directory, { origin: copilotOrigin, secretTool, env })
            : await readCodex(Anchored, folder.directory, { env });
        const id = folder.provider + "-" + crypto.createHash("sha256").update(folder.directory).digest("hex").slice(0, 12);
        if (result.state === "failed") process.stderr.write("ai-usage: account=" + id + " failed=" + result.reason + "\n");
        return { id, provider: folder.provider, label: folder.label.slice(0, 60), email: result.email || "",
            state: result.state, windows: result.windows || [], credits: result.credits || null, details: result.details || {} };
    }));
    let gatewayKey = null;
    if (gateway) {
        const gatewayRead = await readGateway({ origin: gatewayOrigin, secretTool, env });
        gatewayKey = gatewayRead.key;
        if (gatewayRead.account !== null) {
            if (gatewayRead.account.state === "failed") process.stderr.write("ai-usage: account=" + gatewayRead.account.id + " failed=" + gatewayRead.account.reason + "\n");
            accounts.push(gatewayRead.account);
        }
    }
    return { accounts, partial, gatewayKey };
}

module.exports = { ORIGIN, COPILOT_ORIGIN, GATEWAY_ORIGIN, claudeWindows, claudeDetails, codexWindows, copilotCredits, gatewayCredits, readClaude, readCodex, readCopilot, readGateway, read };

if (require.main === module) {
    if ((process.argv.length !== 4 && process.argv.length !== 5) || process.argv[2] !== "--tree" || !path.isAbsolute(process.argv[3])
        || (process.argv.length === 5 && process.argv[4] !== "--gateway")) {
        process.stderr.write("ai-usage: arguments=expected-tree\n");
        process.exit(2);
    }
    read(path.resolve(process.argv[3]), process.env, { gateway: process.argv[4] === "--gateway" }).then(result => {
        process.stdout.write(JSON.stringify(result) + "\n");
    }, error => {
        const key = /^account-folders: ([a-z]+=[a-z-]+)$/.exec(error.message);
        process.stderr.write("ai-usage: read=failed" + (key === null ? "" : " " + key[1]) + "\n");
        process.exitCode = 1;
    });
}
