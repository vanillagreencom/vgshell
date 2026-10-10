// The Copilot harness brain starts one `copilot --acp --stdio` program per
// conversation with COPILOT_HOME set to the selected account directory. Jarvis
// hands it released text only. Copilot sees only the bridge tools, denied tool
// kinds and the runtime tripwire. Permission requests pass HarnessGate before
// Copilot proceeds. CopilotAcp is the protocol judge. Residuals: Copilot can
// still load account MCP server, plugin and extension configuration, with those
// tools hidden by the allow-list; Copilot also keeps each ACP session in its
// own history under the account directory because ACP v1 has no delete
// method and Copilot documents no no-session switch.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const Copilot = require("./CopilotAcp.js");
const Harness = require("./HarnessProgram.js");
const Policy = require("./Policy.js");
const Private = require("./Private.js");

// Copilot 1.0.91 documents ACP over stdio. GitHub's page
// https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/allowing-tools
// says --available-tools disables every other tool and wins over
// --excluded-tools. A recorded 1.0.91 ACP turn (VGS-1242) with the bridge and
// a second server loaded from --additional-mcp-config offered only
// vgs_jarvis-help under vgs_jarvis/* and listed the other server's tool as
// disabled. A wrong filter form hides the bridge and fails closed.
const COPILOT = Object.freeze({ command: "copilot", variable: "COPILOT_HOME", agent: "Copilot", floor: "1.0.60",
    args: Object.freeze(["--acp", "--stdio", "--no-auto-update", "--no-custom-instructions", "--no-ask-user",
        "--disable-builtin-mcps", "--disallow-temp-dir",
        "--available-tools", Copilot.SERVER + "/*",
        "--deny-tool", "shell", "write", "read", "url", "memory",
        "--allow-tool", Copilot.SERVER])
});
// The levels --reasoning-effort takes, as Copilot 1.0.91's --help lists its
// possible values. ACP's model list names none, so each listed model offers
// them all.
const EFFORTS = Object.freeze(["none", "minimal", "low", "medium", "high", "xhigh", "max"]);
// The plan's context bound in user turns, as the wire brains keep it.
const TURNS = 40;
// A program that never finishes its handshake is ended; the account's own
// configuration loads and the bridge's server starts inside this bound.
const HANDSHAKE_MS = 30000;
// One Verify turn: a bound on a stalled provider, not a latency budget.
const PROBE_MS = 60000;
const PROBE_INSTRUCTIONS = "Answer in one word.";
// Tool kinds that name a built-in operation on the machine or the network.
// A call of one of them that runs must have asked the gate first. Copilot
// 1.0.91 also gives a bridge call with a path argument kind "read" (recorded
// for vgs_jarvis-files_list); a call CopilotAcp.bridged matches to a tool the
// bridge serves reaches the router's gate instead. A server other than the
// bridge asks.
const BUILTIN = Object.freeze(["read", "edit", "delete", "move", "search", "execute", "fetch", "switch_mode"]);
const RAN = Object.freeze(["in_progress", "completed", "failed"]);

function fail(code) { throw new Error("jarvis: brain=copilot-" + code); }

// The program under the shared harness shape, with its account directory
// and an empty providers file so no custom provider replaces Copilot's own.
// model and effort are each "" for the program's own; a judged value cannot
// read as a flag.
function program({ program: p, directory, env, cwd, model, effort, config }, listener) {
    if (!Harness.isModel(model)) fail("model");
    if (!Harness.isEffort(effort)) fail("effort");
    return Harness.program({ name: "copilot", argv: [p.command, ...p.args,
        ...(config === null ? [] : ["--additional-mcp-config", "@" + config]), ...(model === "" ? [] : ["--model", model]),
        ...(effort === "" ? [] : ["--reasoning-effort", effort])],
        env, extra: { [p.variable]: directory, COPILOT_PROVIDERS_CONFIG: path.join(cwd, "no-providers", "providers.json") },
        cwd, accept: Copilot.accept, lineBytes: Copilot.LINE_BYTES,
        // ACP's auth_required: the program is not signed in, and Jarvis never signs it in.
        refused: (call, value) => new Error(value.code === -32000 ? "jarvis: brain=copilot-signed-out"
            : "jarvis: brain=copilot-refused method=" + call.method + " code=" + value.code) }, listener);
}

/**
 * One session on one program, its agent judged before the first turn.
 * hooks: {event(event), request(id, request, session)} for the owner's turn
 * and permission handling, and ended(error). The session keeps session/new's
 * result as `created`, which carries the program's model list.
 */
async function open({ program: p, directory, env, runtime, model, effort, bridge }, hooks) {
    Private.directory(runtime);
    const cwd = fs.mkdtempSync(path.join(runtime, "copilot-"));
    // Copilot drops a stdio server sent in session/new (CopilotAcp.sessionNew),
    // so the bridge goes in a config file.
    const config = bridge === null ? null : path.join(cwd, "mcp.json");
    try { if (config !== null) Private.mcpConfig(config, Copilot.SERVER, bridge); }
    catch (error) { fs.rmSync(cwd, { recursive: true, force: true }); throw error; }
    let session = null;
    const child = program({ program: p, directory, env, cwd, model, effort, config }, value => {
        if (value.kind === "notification") hooks.event(value.event);
        // Before the session exists a request is answered on the bare program.
        else if (value.kind === "request") hooks.request(value.id, value.request, session ?? { program: child, id: null, cwd });
        // A handshake failure rejects its pending call instead.
        else if (session !== null) hooks.ended(value.error);
    });
    const timer = setTimeout(() => child.close(), HANDSHAKE_MS);
    try {
        Copilot.agent(await child.call(id => Copilot.initialize(id)), p);
        const created = await child.call(n => Copilot.sessionNew(n, { cwd }));
        session = { program: child, id: Copilot.sessionId(created), cwd, created };
        return session;
    } catch (error) {
        await child.close();
        fs.rmSync(cwd, { recursive: true, force: true });
        throw error;
    } finally { clearTimeout(timer); }
}

async function shut(session) {
    await session.program.close();
    fs.rmSync(session.cwd, { recursive: true, force: true });
}

/**
 * The conversation's brain, behind the plan's interface: start, send as a
 * stream of text and done, cancel with an acknowledgement, and close. options
 * carries the engine's {provider, model, effort, recipients} and the harness
 * facts: account (the agent's account directory), gen, and {bridge, gate,
 * env, runtime}. A harness turn yields no tool-call event: the program's
 * tool calls reach the router itself.
 */
function create({ provider, model, effort, recipients, account, gen, harness }) {
    Policy.assertRecipients(recipients);
    if (provider?.id !== "copilot") fail("provider");
    const p = COPILOT;
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
            const opened = await open({ program: p, directory: account.directory, env, runtime: runtime(), model, effort,
                bridge: launch }, { event, request, ended: error => { ended ??= error; active?.fault(error); } });
            if (closed) { await shut(opened); fail("closed"); }
            session = opened;
            return opened;
        })();
        return opening;
    }

    // A built-in operation the program runs without asking is one the lockdown
    // did not remove: the conversation ends and the brain is refused.
    function reported(turn, call) {
        const announced = turn.calls.get(call.id) ?? null;
        const merged = { ...announced, ...Object.fromEntries(Object.entries(call).filter(([, v]) => v !== null)) };
        turn.calls.set(call.id, merged);
        // An agent announces a call as pending before it asks; it runs once it reports progress.
        if (!BUILTIN.includes(merged.kind) || Copilot.bridged(merged, launch.tools) || turn.asked.has(call.id) || !RAN.includes(merged.status)) return;
        const error = new Error("jarvis: brain=copilot-builtin kind=" + merged.kind);
        ended ??= error;
        session.program.abort(error);
    }

    function event(e) {
        const turn = active;
        if (turn === null || session === null || e.sessionId !== session.id || !turn.requested) return;
        switch (e.kind) {
        case "text": turn.push({ kind: "text", text: e.text }); break;
        // Spoken replies are text; any other content block is not heard.
        case "content": break;
        case "tool-call": case "tool-update": {
            reported(turn, e.call);
            const waiter = turn.waiters.get(e.call.id);
            if (waiter !== undefined && (e.call.status === "completed" || e.call.status === "failed")) {
                turn.waiters.delete(e.call.id);
                waiter(e.call.status);
            }
            break;
        }
        case "other": break;
        default: fail("event-kind");
        }
    }

    function request(id, value, current) {
        const turn = active;
        switch (value.kind) {
        case "unsupported": current.program.write(Copilot.answer(id, value, "cancelled")); return;
        case "permission": {
            if (turn === null || !turn.requested || value.sessionId !== current.id || value.allow === null) {
                current.program.write(Copilot.answer(id, value, "reject"));
                return;
            }
            turn.asked.add(value.call.id);
            let answered = false;
            const once = choice => {
                if (answered) return;
                answered = true;
                turn.pending.delete(id);
                current.program.write(Copilot.answer(id, value, choice));
            };
            // A cancelled turn answers every open request cancelled, as Copilot ACP requires.
            turn.pending.set(id, () => once("cancelled"));
            gate.ask(gen, Copilot.proposal(value, turn.calls.get(value.call.id) ?? null, current.cwd), {
                decline: () => once("reject"),
                accept: () => {
                    once("allow");
                    return new Promise(resolve => turn.waiters.set(value.call.id, status => resolve({
                        outcome: status === "completed" ? "completed" : status === "failed" ? "failed" : "unknown",
                        content: JSON.stringify({ kind: "harness", status }) })));
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

        // requested: session/prompt is written, so only its stop reason
        // acknowledges a cancel. calls holds each reported tool call merged
        // across its updates; asked the ids whose permission request reached the gate.
        const current = { requested: false, calls: new Map(), asked: new Set(), waiters: new Map(), pending: new Map() };
        const { handle, events } = Harness.stream({ run, detach: () => { if (active === current) active = null; },
            interrupt() {
                if (!current.requested || session === null) return false;
                for (const cancelled of [...current.pending.values()]) cancelled();
                session.program.write(Copilot.cancel(session.id));
                return true;
            },
            settled() {
                for (const cancelled of [...current.pending.values()]) cancelled();
                for (const waiter of current.waiters.values()) waiter("unknown");
                current.waiters.clear();
            } });
        Object.assign(current, { push: handle.push, fault: handle.fault, cancel: handle.cancel,
            complete(stop) {
                handle.finish(stop === "end_turn" ? { kind: "complete" } : stop === "cancelled" ? { kind: "cancelled" }
                    : { kind: "failed", error: new Error("jarvis: brain=copilot-stop-" + stop) });
            } });

        async function run() {
            try {
                if (labels.length === 0) fail("release-empty");
                const opened = await ensure();
                if (handle.state() !== "streaming") return;
                // Instructions lead the first prompt: ACP has no system prompt.
                const texts = turns === 0 ? [instructions, text] : [text];
                turns++;
                current.requested = true;
                current.complete(Copilot.stopReason(await opened.program.call(n => Copilot.prompt(n, opened.id, texts))));
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

// A session that offers no tool admits no request.
function refuse(id, value, current) {
    current.program.write(Copilot.answer(id, value, value.kind === "permission" ? "reject" : "cancelled"));
}

/**
 * Account Verify's smallest real request: one prompt of text in a session
 * with no tools, through the vendor's own program. Resolves with the reply's
 * text; throws a keyed error when the program, the turn or the reply fails.
 * The caller owns release and audit.
 */
async function probe({ provider, directory, env, runtime, model, text }) {
    if (provider !== "copilot") fail("provider");
    const p = COPILOT;
    let session = null;
    let reply = "";
    let failed = null;
    const hooks = {
        event(e) { if (session !== null && e.sessionId === session.id && e.kind === "text") reply += e.text; },
        request: refuse,
        ended(error) { failed ??= error; }
    };
    let timer;
    try {
        // The handshake keeps its own bound; the deadline covers the turn.
        session = await open({ program: p, directory, env, runtime, model, effort: "", bridge: null }, hooks);
        const deadline = new Promise((resolve, reject) => {
            timer = setTimeout(() => reject(new Error("jarvis: brain=copilot-probe-deadline")), PROBE_MS);
        });
        const stop = await Promise.race([deadline,
            session.program.call(n => Copilot.prompt(n, session.id, [PROBE_INSTRUCTIONS, text])).then(Copilot.stopReason)]);
        if (failed !== null) throw failed;
        if (stop !== "end_turn") fail("stop-" + stop);
        if (reply.trim() === "") fail("no-reply");
        return reply;
    } finally {
        clearTimeout(timer);
        if (session !== null) await shut(session);
    }
}

/**
 * The models the account's own program offers, Harness.offers' list, from
 * the session/new answer of one session with no tools. No prompt is sent.
 * ACP has no list outside a session, so the read leaves one empty session
 * in the account's history, as a conversation does. The handshake's bound
 * is the read's.
 */
async function models({ directory, env, runtime }) {
    const session = await open({ program: COPILOT, directory, env, runtime, model: "", effort: "", bridge: null },
        { event() {}, request: refuse, ended() {} });
    try { return Harness.offers(Copilot.models(session.created, EFFORTS)); }
    finally { await shut(session); }
}

module.exports = { create, probe, models };
