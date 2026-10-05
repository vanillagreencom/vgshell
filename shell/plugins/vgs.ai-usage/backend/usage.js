#!/usr/bin/env node
// usage.js --tree ABSOLUTE_VGS_TREE
// Reads the plan limits of every Claude Code and Codex account the core's
// account discovery finds, through each tool's own sign-in, and prints one
// JSON line on stdout: { accounts: [{ id, provider, label, email, plan,
// state, windows: [{ name, usedPercent, resetsAt }] }], partial }. state is
// ok, expired, signed-out, no-plan for a sign-in that has no plan limits,
// or failed; a window the tool does not report is left out, never read as
// 0. Diagnostics are lines of `ai-usage: <key>=<value>` pairs on stderr. No token or reply body reaches either stream; of what
// the tools report, only an account's email, plan and windows do. Nothing
// here writes or refreshes a credential file.
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
// Bounds on a stalled endpoint or program, not latency budgets.
const REQUEST_MS = 15000;
const CODEX_MS = 20000;
// The largest credential file and reply read; a larger one is refused.
const MAX_BYTES = 64 * 1024;
const MAX_LINE_BYTES = 1024 * 1024;
// The accounts read in one run; past it the run is partial.
const MAX_ACCOUNTS = 16;
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

/**
 * The windows of a Claude usage reply: five_hour, seven_day and each
 * model's seven_day_<model>, in that order, each { utilization, resets_at }
 * with resets_at an ISO time or null. A window the reply leaves out or
 * holds as null is absent. Returns the windows, or null for a reply that is
 * no object or holds a window of another shape.
 */
function claudeWindows(body) {
    if (!plain(body)) return null;
    const names = Object.keys(body).filter(name => /^seven_day_[a-z0-9_]+$/.test(name)).sort();
    const windows = [];
    for (const name of ["five_hour", "seven_day", ...names]) {
        const value = body[name];
        if (value === undefined || value === null) continue;
        if (!plain(value)) return null;
        const usedPercent = percent(value.utilization);
        const resetsAt = value.resets_at === null || value.resets_at === undefined ? null : Date.parse(value.resets_at);
        if (usedPercent === undefined || (resetsAt !== null && !Number.isFinite(resetsAt))) return null;
        windows.push({ name, usedPercent, resetsAt });
    }
    return windows;
}

/**
 * The windows of a Codex rate-limit reply, `account/rateLimits/read`'s
 * result: rateLimits.primary and .secondary, each { usedPercent,
 * windowDurationMins, resetsAt } with resetsAt in Unix seconds, named by
 * their length: five_hour, seven_day or minutes_<n>, else primary or
 * secondary. Returns { windows, plan }, or null for a reply of another
 * shape. Source: codex-rs/app-server-protocol/src/protocol/v2/account.rs,
 * GetAccountRateLimitsResponse, RateLimitSnapshot and RateLimitWindow.
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
    return { windows, plan: printable(snapshot.planType, 40) ? snapshot.planType : "" };
}

/**
 * The credential file FILE inside the held directory FD, read once without
 * following a link: { kind: "absent" }, { kind: "file", text } or
 * { kind: "refused", reason }.
 */
function readHeld(Anchored, fd, file) {
    let handle;
    try {
        handle = fs.openSync(Anchored.child(fd, file), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_NOCTTY);
        const stat = fs.fstatSync(handle);
        if (!stat.isFile()) return { kind: "refused", reason: "credentials-not-file" };
        if (stat.size > MAX_BYTES) return { kind: "refused", reason: "credentials-size" };
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
 * The Claude Code account in DIRECTORY: its `.credentials.json`, read
 * without following a link and never written, then one GET of the usage
 * endpoint at ORIGIN with the access token. An expired token sends nothing
 * and reads expired, as does a token the endpoint refuses.
 */
async function readClaude(Anchored, directory, { origin = ORIGIN, now = Date.now(), deadlineMs = REQUEST_MS } = {}) {
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
    const plan = printable(oauth.subscriptionType, 40) ? oauth.subscriptionType : "";
    if (oauth.expiresAt <= now) return { state: "expired", plan };
    const reply = await get(new URL(USAGE_PATH, origin), {
        authorization: "Bearer " + oauth.accessToken, "anthropic-beta": OAUTH_BETA, accept: "application/json"
    }, deadlineMs);
    if (reply.error) return failed(reply.error);
    if (reply.status === 401 || reply.status === 403) return { state: "expired", plan };
    if (reply.status !== 200) return failed("http-" + reply.status);
    let body;
    try { body = JSON.parse(reply.body); } catch { return failed("reply-json"); }
    const windows = claudeWindows(body);
    if (windows === null) return failed("reply-shape");
    return { state: "ok", plan, windows };
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
        const finish = value => {
            if (done) return;
            done = true;
            clearTimeout(timer);
            child.stdin.destroy();
            child.kill("SIGKILL");
            resolve(value);
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
                account = { email: printable(value.email, 120) ? value.email : "", plan: printable(value.planType, 40) ? value.planType : "" };
                send({ id: 3, method: "account/rateLimits/read" });
            } else {
                const read = codexWindows(message.result);
                if (read === null) return finish(failed("codex-shape"));
                finish({ state: "ok", email: account.email, plan: account.plan || read.plan, windows: read.windows });
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

// Every live app-server, killed if this process ends before its read does.
const children = new Set();
process.on("exit", () => { for (const child of children) child.kill("SIGKILL"); });

/**
 * Every account the core's discovery finds under ENV's HOME, XDG config
 * and data homes and explicit roots, read at once, Claude's at ORIGIN. A
 * directory that is absent is no account; one past MAX_ACCOUNTS is not read
 * and the run is partial "account-limit".
 */
async function read(tree, env, { origin = ORIGIN } = {}) {
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
        const result = folder.provider === "claude" ? await readClaude(Anchored, folder.directory, { origin })
            : await readCodex(Anchored, folder.directory, { env });
        const id = folder.provider + "-" + crypto.createHash("sha256").update(folder.directory).digest("hex").slice(0, 12);
        if (result.state === "failed") process.stderr.write("ai-usage: account=" + id + " failed=" + result.reason + "\n");
        return { id, provider: folder.provider, label: folder.label.slice(0, 60), email: result.email || "",
            plan: result.plan || "", state: result.state, windows: result.windows || [] };
    }));
    return { accounts, partial };
}

module.exports = { ORIGIN, claudeWindows, codexWindows, readClaude, readCodex, read };

if (require.main === module) {
    if (process.argv.length !== 4 || process.argv[2] !== "--tree" || !path.isAbsolute(process.argv[3])) {
        process.stderr.write("ai-usage: arguments=expected-tree\n");
        process.exit(2);
    }
    read(path.resolve(process.argv[3]), process.env).then(result => {
        process.stdout.write(JSON.stringify(result) + "\n");
    }, error => {
        const key = /^account-folders: ([a-z]+=[a-z-]+)$/.exec(error.message);
        process.stderr.write("ai-usage: read=failed" + (key === null ? "" : " " + key[1]) + "\n");
        process.exitCode = 1;
    });
}
