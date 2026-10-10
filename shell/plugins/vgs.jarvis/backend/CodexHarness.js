// The Codex harness brain: one `codex app-server` per conversation, started
// with the account's CODEX_HOME so the vendor's program owns its login and its
// sockets. Jarvis hands it released text alone; the program's tools are its
// MCP access to the tool bridge and the actions whose approval requests pass
// HarnessGate. CodexAppServer is the protocol judge.
// Contract: docs/architecture/jarvis.md § Adapters.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const Codex = require("./CodexAppServer.js");
const Harness = require("./HarnessProgram.js");
const Policy = require("./Policy.js");
const Private = require("./Private.js");

// The plan's context bound in user turns, as the wire brains keep it. Past it
// the brain refuses with the wire brains' key, which the engine ends cleanly on.
const TURNS = 40;
// A program that never finishes its handshake is ended; the account's own
// configuration loads and its MCP servers start inside this bound.
const HANDSHAKE_MS = 30000;
// One Verify turn: a bound on a stalled provider, not a latency budget.
const PROBE_MS = 60000;
const PROBE_INSTRUCTIONS = "Answer in one word.";

function fail(code) { throw new Error("jarvis: brain=codex-" + code); }

// The program under the shared harness shape, with its account directory.
function program({ directory, env, cwd }, listener) {
    return Harness.program({ name: "codex", argv: ["codex", "app-server", "--listen", "stdio://"], env,
        extra: { CODEX_HOME: directory }, cwd, accept: Codex.accept, lineBytes: Codex.LINE_BYTES,
        refused: (call, value) => new Error("jarvis: brain=codex-refused method=" + call.method + " code=" + value.code) }, listener);
}

async function shut(session) {
    await session.program.close();
    fs.rmSync(session.cwd, { recursive: true, force: true });
}

/**
 * The program in a new private folder under runtime, initialized, as
 * started {program, cwd}: where a thread and a model list read both begin.
 * listener(value, started) receives what the program sends. use(started)
 * runs under the bound: a program that outlives ms is closed, and when the
 * start or use fails the program ends and its folder goes.
 */
async function start({ directory, env, runtime }, listener, ms, use) {
    Private.directory(runtime);
    const cwd = fs.mkdtempSync(path.join(runtime, "codex-"));
    const started = { program: program({ directory, env, cwd }, value => listener(value, started)), cwd };
    const timer = setTimeout(() => started.program.close(), ms);
    try {
        await started.program.call(id => Codex.initialize(id));
        started.program.write(Codex.initialized());
        return await use(started);
    } catch (error) {
        await shut(started);
        throw error;
    } finally { clearTimeout(timer); }
}

/**
 * One thread on one program, locked down and verified before its first turn.
 * hooks: {event(event), request(id, request, session)} for the owner's
 * turn and approval handling, and ended(error).
 */
function open({ directory, env, runtime, model, effort, instructions, bridge }, hooks) {
    let session = null;
    return start({ directory, env, runtime }, (value, started) => {
        if (value.kind === "notification") hooks.event(value.event);
        // Before the thread exists a request is answered on the bare program.
        else if (value.kind === "request") hooks.request(value.id, value.request, session ?? { program: started.program, thread: null });
        // A handshake failure rejects its pending call instead.
        else if (session !== null) hooks.ended(value.error);
    }, HANDSHAKE_MS, async ({ program: p, cwd }) => {
        const foreign = Codex.servers(await p.call(id => Codex.configRead(id, cwd)));
        const thread = Codex.thread(await p.call(id => Codex.threadStart(id, { cwd, model, effort, instructions, foreign, bridge })));
        Codex.features(await p.call(id => Codex.featureList(id, thread)));
        session = { program: p, thread, cwd };
        return session;
    });
}

/**
 * The conversation's brain, behind the plan's interface: start, send as a
 * stream of text and done, cancel with an acknowledgement, and close. options
 * carries the engine's {model, effort, recipients} and the harness facts: account (a
 * Codex directory), gen, and {bridge, gate, env, runtime}. A harness turn
 * yields no tool-call event: the program's tool calls reach the router itself.
 */
function create({ model, effort, recipients, account, gen, harness }) {
    Policy.assertRecipients(recipients);
    if (!account || account.kind !== "cli" || typeof account.directory !== "string") fail("account");
    if (!harness) fail("unwired");
    const { bridge, gate, env, runtime } = harness;
    let instructions = null;
    let opening = null;
    let launch = null;
    let session = null;
    let turns = 0;
    let active = null;
    let closed = false;
    let ended = null;

    function usable() {
        if (closed) fail("closed");
        if (active !== null) fail("busy");
        if (ended !== null) throw ended;
    }

    function start(value) {
        usable();
        if (typeof value.instructions !== "string") fail("instructions");
        instructions = value.instructions;
    }

    // One program per conversation, with the bridge session of its generation.
    function ensure() {
        if (opening === null) opening = (async () => {
            launch = await bridge.open({ gen, recipients });
            // A close during the open found no launch to end.
            if (closed) { launch.close(); fail("closed"); }
            const opened = await open({ directory: account.directory, env, runtime: runtime(), model, effort,
                instructions, bridge: launch }, { event, request, ended: error => { ended ??= error; active?.fault(error); } });
            if (closed) { await shut(opened); fail("closed"); }
            session = opened;
            return opened;
        })();
        return opening;
    }

    // The turn's announced items: an approval request names one by id.
    function event(e) {
        const turn = active;
        if (turn === null || session === null || e.threadId !== session.thread) return;
        if (e.kind === "turn-started" && turn.id === null) turn.id = e.turnId;
        if (e.turnId !== turn.id) return;
        switch (e.kind) {
        case "delta": {
            const prior = turn.text.get(e.itemId) ?? { value: "", completed: false };
            if (!prior.completed && e.delta !== "") {
                prior.value += e.delta;
                turn.text.set(e.itemId, prior);
                turn.push({ kind: "text", text: e.delta });
            }
            break;
        }
        case "item-started": turn.items.set(e.item.id, e.item); break;
        case "item-completed": {
            if (e.item.kind === "message") {
                const prior = turn.text.get(e.item.id) ?? { value: "", completed: false };
                if (!prior.completed) {
                    if (!e.item.text.startsWith(prior.value)) {
                        const error = new Error("jarvis: brain=codex-message-text");
                        error.code = "message-text";
                        turn.fault(error);
                        return;
                    }
                    const remainder = e.item.text.slice(prior.value.length);
                    turn.text.set(e.item.id, { value: e.item.text, completed: true });
                    if (remainder !== "") turn.push({ kind: "text", text: remainder });
                }
            }
            turn.items.set(e.item.id, e.item);
            const waiter = turn.waiters.get(e.item.id);
            if (waiter !== undefined) { turn.waiters.delete(e.item.id); waiter(e.item); }
            break;
        }
        case "error": break;
        case "turn-completed": turn.complete(e.status); break;
        case "turn-started": case "other": break;
        default: fail("event-kind");
        }
    }

    function request(id, value, current) {
        const respond = admitted => current.program.write(Codex.answer(id, value, admitted));
        const turn = active;
        switch (value.kind) {
        case "elicitation":
            // The bridge routes the call that follows; any other server's is declined.
            respond(value.toolCall && value.server === Codex.SERVER && value.threadId === current.thread);
            return;
        case "unsupported": respond(false); return;
        case "file-change": case "command": case "permissions": {
            if (turn === null || value.threadId !== current.thread || value.turnId !== turn.id) { respond(false); return; }
            let answered = false;
            const once = admitted => { if (!answered) { answered = true; respond(admitted); } };
            gate.ask(gen, Codex.proposal(value, turn.items.get(value.itemId) ?? null), {
                decline: () => once(false),
                accept: () => {
                    once(true);
                    return new Promise(resolve => turn.waiters.set(value.itemId, item => resolve({
                        outcome: item.status === "completed" ? "completed"
                            : ["failed", "declined"].includes(item.status) ? "failed" : "unknown",
                        content: JSON.stringify({ kind: "harness", status: item.status }) })));
                }
            });
            return;
        }
        default: fail("request-kind");
        }
    }

    function send(turn, grants = []) {
        usable();
        if (instructions === null) fail("not-started");
        const { text, labels, release } = Harness.release(turn, recipients, grants, fail);
        if (turns >= TURNS) throw new Error("jarvis: brain=context-limit");

        // requested: turn/start is written, so only the program's completion
        // acknowledges a cancel.
        const current = { id: null, requested: false, items: new Map(), waiters: new Map(), text: new Map() };
        const { handle, events } = Harness.stream({ run, detach: () => { if (active === current) active = null; },
            interrupt() {
                if (current.id !== null && session !== null)
                    session.program.call(id => Codex.turnInterrupt(id, session.thread, current.id)).catch(() => {});
                return current.requested;
            },
            settled() {
                for (const waiter of current.waiters.values()) waiter({ status: "unknown" });
                current.waiters.clear();
            } });
        Object.assign(current, { push: handle.push, fault: handle.fault, cancel: handle.cancel,
            complete(status) {
                handle.finish(status === "completed" ? { kind: "complete" } : status === "interrupted" ? { kind: "cancelled" }
                    : { kind: "failed", error: new Error("jarvis: brain=codex-turn-" + status) });
            } });

        async function run() {
            try {
                if (labels.length === 0) fail("release-empty");
                const opened = await ensure();
                if (handle.state() !== "streaming") return;
                turns++;
                current.requested = true;
                const id = Codex.turnId(await opened.program.call(n => Codex.turnStart(n, opened.thread, text)));
                if (current.id === null) current.id = id;
                else if (current.id !== id) fail("turn-id");
                if (handle.state() === "cancelling") opened.program.call(n => Codex.turnInterrupt(n, opened.thread, id)).catch(() => {});
            } catch (error) { current.fault(error); }
        }
        active = current;
        return Object.freeze({ release, events });
    }

    return Object.freeze({ start, send,
        /** A harness turn is never answered by tool results. */
        record() { fail("record"); },
        cancel() { return active === null ? Promise.resolve() : active.cancel(); },
        close() {
            if (closed) return;
            closed = true;
            active?.cancel();
            launch?.close();
            if (session !== null) void shut(session);
            session = null;
        } });
}

/**
 * Account Verify's smallest real request: one turn of text on a thread with
 * no tools, through the vendor's own program. Resolves with the reply's
 * text; throws a keyed error when the program, the turn or the reply fails.
 * The caller owns release and audit.
 */
async function probe({ directory, env, runtime, model, text }) {
    let session = null;
    let turn = null;
    let reply = "";
    let settle;
    const done = new Promise((resolve, reject) => { settle = { resolve, reject }; });
    // The turn's failure is read at `await done`. After an earlier throw, the
    // program's end during shut() rejects it too, and that throw is the outcome.
    done.catch(() => {});
    const hooks = {
        event(e) {
            if (session === null || e.threadId !== session.thread) return;
            if (e.kind === "turn-started" && turn === null) turn = e.turnId;
            if (e.turnId !== turn) return;
            if (e.kind === "delta") reply += e.delta;
            else if (e.kind === "item-completed" && e.item.kind === "message") reply = e.item.text;
            else if (e.kind === "turn-completed")
                if (e.status === "completed") settle.resolve(); else settle.reject(new Error("jarvis: brain=codex-turn-" + e.status));
        },
        // A probe thread offers no tool, so it admits no request.
        request(id, value, current) { current?.program.write(Codex.answer(id, value, false)); },
        ended(error) { settle.reject(error); }
    };
    const timer = setTimeout(() => settle.reject(new Error("jarvis: brain=codex-probe-deadline")), PROBE_MS);
    try {
        session = await open({ directory, env, runtime, model, effort: "", instructions: PROBE_INSTRUCTIONS, bridge: null }, hooks);
        const id = Codex.turnId(await session.program.call(n => Codex.turnStart(n, session.thread, text)));
        turn ??= id;
        await done;
        if (reply.trim() === "") fail("no-reply");
        return reply;
    } finally {
        clearTimeout(timer);
        if (session !== null) await shut(session);
    }
}

/**
 * The models the account's own program offers, Harness.offers' list, from
 * its model/list answer. No thread starts and no prompt is sent. Past
 * Harness.MODELS_MS the program is ended and the read fails with its exit.
 */
async function models({ directory, env, runtime }) {
    // No thread exists, so a request names none: each is declined.
    const read = await start({ directory, env, runtime }, (value, started) => {
        if (value.kind === "request") started.program.write(Codex.answer(value.id, value.request, false));
    }, Harness.MODELS_MS, async started => ({ started,
        offers: Harness.offers(Codex.models(await started.program.call(id => Codex.modelList(id)))) }));
    await shut(read.started);
    return read.offers;
}

module.exports = { create, probe, models };
