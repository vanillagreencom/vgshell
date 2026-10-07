// The one Codex account reader: one `codex app-server` with CODEX_HOME set
// to an account folder, asked over JSON-RPC on stdio for `initialize`, the
// `initialized` notification and `account/read` without a token refresh
// (codex-rs/app-server/README.md and
// codex-rs/app-server-protocol/src/protocol/v2/account.rs), then what the
// caller asks while the program still runs. AI usage reads the plan limits
// after it; Jarvis reads the email alone. Both load it from the tree their
// launcher names. It never reads auth.json.
"use strict";
const cp = require("node:child_process");

// The largest reply line read; a longer one fails the read.
const MAX_LINE_BYTES = 1024 * 1024;

function plain(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function printable(value, max) {
    return typeof value === "string" && value.length > 0 && value.length <= max && !/[\x00-\x1f\x7f]/.test(value);
}
function fault(reason) {
    const error = new Error("codex-account: read=" + reason);
    error.reason = reason;
    return error;
}

/**
 * The account of an account/read RESULT: { kind: "signed-out" } with no
 * account, { kind: "chatgpt", email } for a ChatGPT sign-in, email its
 * printable address or "", and { kind: "other" } for any other sign-in,
 * an API key among them. An unreadable account fails as codex-account.
 */
function account(result) {
    const value = result.account;
    if (value === null || value === undefined) return { kind: "signed-out" };
    if (!plain(value)) throw fault("codex-account");
    if (value.type !== "chatgpt") return { kind: "other" };
    return { kind: "chatgpt", email: printable(value.email, 120) ? value.email : "" };
}

/**
 * Read the account in DIRECTORY with the program COMMAND, started under
 * setpriv so it dies with this process, in CWD with ENV and CODEX_HOME, and
 * KILLed at DEADLINEMS and once the read ends. CLIENTINFO names the caller
 * in `initialize`. THEN, when given, is called with the account and
 * call(method, params), which resolves a further request's result, and
 * its answer is the read's value. Resolves { account, value }. A failed
 * read throws an Error whose `reason` is setpriv-missing, codex-start,
 * codex-exited, codex-line, codex-line-size, codex-error, codex-account or
 * codex-deadline and whose `account` is the account read before it, or
 * null; an error THEN throws is the read's, as it was thrown. CHILDREN,
 * when given, holds the program while it runs.
 */
function read({ directory, env, cwd, command = "codex", deadlineMs, clientInfo, children = null }, then = null) {
    const child = cp.spawn("setpriv", ["--pdeathsig", "KILL", "--", command, "app-server"], {
        cwd, stdio: ["pipe", "pipe", "ignore"], env: { ...env, CODEX_HOME: directory } });
    if (children !== null) children.add(child);
    return new Promise((resolve, reject) => {
        let done = false;
        let tail = "";
        let next = 1;
        let known = null;
        const pending = new Map();
        const finish = (error, value) => {
            if (done) return;
            done = true;
            clearTimeout(timer);
            child.stdin.destroy();
            child.kill("SIGKILL");
            if (error === null) resolve(value);
            else {
                error.account = known;
                reject(error);
            }
        };
        const timer = setTimeout(() => finish(fault("codex-deadline")), deadlineMs);
        child.on("error", error => finish(fault(error.code === "ENOENT" ? "setpriv-missing" : "codex-start")));
        child.on("exit", () => {
            if (children !== null) children.delete(child);
            finish(fault("codex-exited"));
        });
        child.stdin.on("error", () => finish(fault("codex-exited")));
        const send = message => child.stdin.write(JSON.stringify(message) + "\n");
        const call = (method, params) => new Promise((ok, failed) => {
            if (done) { failed(fault("codex-exited")); return; }
            const id = next++;
            pending.set(id, ok);
            send(params === undefined ? { id, method } : { id, method, params });
        });
        // A notification or a server request names a method; neither is an
        // answer, so it is passed over.
        const receive = line => {
            let message;
            try { message = JSON.parse(line); } catch { return finish(fault("codex-line")); }
            if (!plain(message) || message.method !== undefined || !pending.has(message.id)) return;
            const ok = pending.get(message.id);
            pending.delete(message.id);
            if (message.error !== undefined || !plain(message.result)) return finish(fault("codex-error"));
            ok(message.result);
        };
        child.stdout.on("data", chunk => {
            tail += chunk.toString("utf8");
            if (tail.length > MAX_LINE_BYTES) return finish(fault("codex-line-size"));
            let at;
            while (!done && (at = tail.indexOf("\n")) >= 0) {
                const line = tail.slice(0, at);
                tail = tail.slice(at + 1);
                if (line.trim() !== "") receive(line);
            }
        });
        (async () => {
            await call("initialize", { clientInfo });
            send({ method: "initialized" });
            known = account(await call("account/read", { refreshToken: false }));
            finish(null, { account: known, value: then === null ? undefined : await then(known, call) });
        })().catch(error => finish(error));
    });
}

module.exports = { account, read };
