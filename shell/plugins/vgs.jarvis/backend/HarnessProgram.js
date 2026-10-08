// The one harness brain shape, shared by the Codex, Copilot and Pi brains:
// the vendor program as a JSON-line child, the release of a turn's items and
// one turn's stream of text and done. Each brain keeps its protocol judge,
// its lockdown and its handshake.
// Contract: docs/architecture/jarvis.md § Adapters.
"use strict";
const cp = require("node:child_process");
const Policy = require("./Policy.js");
const { childEnvironment } = require("./Secrets.js");

// After its stdin closes the program has this long to exit before KILL.
const CLOSE_MS = 2000;

/**
 * Start the program and own its JSON-line connection. name keys every
 * failure, `jarvis: brain=<name>-...`; argv follows setpriv's `--`; env is
 * the daemon environment, scrubbed by childEnvironment, and extra the
 * variables the brain adds. accept(line) narrows one line to {kind:
 * "response", id, result}, {kind: "failure", id, ...}, {kind:
 * "notification", event} or {kind: "request", id, request}; refused(call,
 * value) is a failure's error. listener receives each notification and
 * request, and once {kind: "ended", error}. Every child, including
 * setpriv's exec of the program, ends with the daemon.
 */
function program({ name, argv, env, extra, cwd, accept, lineBytes, refused }, listener) {
    const fail = code => { throw new Error("jarvis: brain=" + name + "-" + code); };
    const child = cp.spawn("setpriv", ["--pdeathsig", "KILL", "--", ...argv], {
        cwd, env: { ...childEnvironment(env), ...extra }, stdio: ["pipe", "pipe", "pipe"] });
    const calls = new Map();
    let next = 1;
    let tail = "";
    let ended = null;
    const exited = new Promise(resolve => child.once("close", resolve));

    function end(error) {
        if (ended !== null) return;
        ended = error;
        for (const call of calls.values()) call.reject(error);
        calls.clear();
        if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
        listener({ kind: "ended", error });
    }
    child.on("error", error => end(new Error("jarvis: brain=" + name + "-start cause=" + (error.code ?? "unknown"))));
    child.on("close", (code, signal) => end(new Error("jarvis: brain=" + name + "-exited code=" + code + " signal=" + signal)));
    child.stdin.on("error", () => {});
    // The program's log can hold conversation text or a credential; it is read and dropped.
    child.stderr.resume();
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", chunk => {
        if (ended !== null) return;
        tail += chunk;
        try {
            let index;
            while (ended === null && (index = tail.indexOf("\n")) >= 0) {
                const line = tail.slice(0, index);
                tail = tail.slice(index + 1);
                receive(accept(line));
            }
            if (Buffer.byteLength(tail) >= lineBytes) fail("line-size");
        } catch (error) { end(error); }
    });

    function receive(value) {
        switch (value.kind) {
        case "response": case "failure": {
            const call = calls.get(value.id);
            if (call === undefined) fail("response-id");
            calls.delete(value.id);
            if (value.kind === "response") call.resolve(value.result);
            else call.reject(refused(call, value));
            return;
        }
        case "notification": case "request": listener(value); return;
        default: fail("message-kind");
        }
    }
    function write(message) {
        if (ended === null) child.stdin.write(JSON.stringify(message) + "\n");
    }
    return {
        /** Send build(n), a message that carries its own id, and resolve with the program's result. */
        call(build) {
            if (ended !== null) return Promise.reject(ended);
            const message = build(next++);
            return new Promise((resolve, reject) => {
                calls.set(message.id, { method: message.method ?? message.type, resolve, reject });
                write(message);
            });
        },
        write,
        /** End the program with error; the turn it serves fails with it. */
        abort(error) { end(error); },
        /** Close stdin, the program's lease; KILL it if it outlives CLOSE_MS. */
        close() {
            if (ended === null) child.stdin.end();
            const timer = setTimeout(() => end(new Error("jarvis: brain=" + name + "-closed")), CLOSE_MS);
            return exited.then(() => clearTimeout(timer));
        }
    };
}

/**
 * One user turn's items judged by Policy.release against the conversation's
 * recipients and grants. Returns the text handed to the program, each
 * item's released content joined by a blank line, the labels sent and the
 * release record the engine reads. fail(code) throws the brain's keyed error.
 */
function release(turn, recipients, grants, fail) {
    if (turn?.kind !== "user") fail("turn");
    if (!Array.isArray(turn.items) || turn.items.length === 0 || (turn.images ?? []).length !== 0) fail("turn");
    const sent = [], withheld = new Set(), needed = new Set();
    const text = turn.items.map(item => {
        if (!item || typeof item.content !== "string") fail("item-text");
        const decision = Policy.release(item, recipients, grants);
        if (decision.kind === "send") sent.push(item);
        else if (decision.kind === "ask") for (const label of decision.needed) needed.add(label);
        else for (const label of decision.labels) withheld.add(label);
        return decision.content;
    }).join("\n\n");
    const labels = [...new Set(sent.flatMap(item => item.labels))];
    return { text, labels, release: Object.freeze({ withheld: Object.freeze([...withheld]),
        needed: Object.freeze([...needed]), labels: Object.freeze(labels) }) };
}

/**
 * One turn's stream: the brain's handle on it and the engine's async
 * iterator of {kind: "text"} values and one {kind: "done"}. run() starts the
 * program's side on the first next(). interrupt() asks the program to stop a
 * started turn and answers whether the program's own end of the turn will
 * acknowledge the cancel. settled() releases what the turn still holds once
 * it ends. detach() runs when the iterator ends or a cancel is acknowledged.
 * The handle: state(), push(value), finish(outcome) with outcome {kind:
 * "complete"}, {kind: "cancelled"} or {kind: "failed", error}, fault(error),
 * and cancel(), resolved once the cancel is acknowledged.
 */
function stream({ run, interrupt, settled, detach }) {
    const queue = [];
    let wake = () => {};
    let state = { kind: "unstarted" };
    let acknowledged;
    const finished = new Promise(resolve => { acknowledged = resolve; });
    function settle() {
        settled();
        wake();
        acknowledged();
    }
    const handle = {
        state: () => state.kind,
        push(value) { queue.push(value); wake(); },
        finish(outcome) {
            if (state.kind === "streaming") state = outcome;
            settle();
        },
        fault(error) {
            if (state.kind === "streaming" || state.kind === "cancelling") state = { kind: "failed", error };
            settle();
        },
        cancel() {
            switch (state.kind) {
            case "unstarted": state = { kind: "cancelled" }; acknowledged(); break;
            case "streaming":
                state = { kind: "cancelling" };
                if (!interrupt()) acknowledged();
                wake();
                break;
            default: break;
            }
            return finished.then(detach);
        }
    };
    function ended() {
        state = { kind: "ended" };
        detach();
    }
    const events = {
        [Symbol.asyncIterator]() { return this; },
        async next() {
            if (state.kind === "unstarted") {
                state = { kind: "streaming" };
                run();
            }
            for (;;) {
                if (queue.length !== 0 && state.kind !== "cancelled" && state.kind !== "cancelling")
                    return { value: queue.shift(), done: false };
                switch (state.kind) {
                case "streaming": break;
                case "complete":
                    ended();
                    return { value: { kind: "done", reason: "stop" }, done: false };
                case "cancelled": case "cancelling":
                    ended();
                    throw new Error("jarvis: brain=cancelled");
                case "failed": {
                    const error = state.error;
                    ended();
                    throw error;
                }
                case "ended": return { value: undefined, done: true };
                default: throw new Error("jarvis: brain=turn-state");
                }
                await new Promise(resolve => { wake = resolve; });
            }
        },
        async return() {
            await handle.cancel();
            return { value: undefined, done: true };
        }
    };
    return { handle, events };
}

module.exports = { program, release, stream };
