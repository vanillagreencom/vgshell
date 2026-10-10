// The Pi harness brain: one `pi --mode rpc --no-session` per conversation,
// started with PI_CODING_AGENT_DIR set to the user's own Pi folder, so Pi
// reaches its providers with its own setup and Jarvis never reads a
// credential. Jarvis hands it released text only. Pi's only tools are the
// bridge's, named in a private working folder's .pi/mcp.json, and a tool
// of any other name that starts ends the conversation. PiRpc is the protocol
// judge. Residual: Pi still starts the MCP servers the user configured in
// that folder, with Pi's environment; their tools are not declared to the
// model, the tripwire refuses them, and the bridge's token is not in that
// environment.
// Contract: docs/architecture/jarvis.md § Adapters.
"use strict";
const cp = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const Pi = require("./PiRpc.js");
const Harness = require("./HarnessProgram.js");
const Policy = require("./Policy.js");
const Private = require("./Private.js");
const { childEnvironment } = require("./Secrets.js");

// The Pi release PiRpc's records were written to: Pi 1.0.2 settles a run
// with no `aborted` field. Pi's RPC mode names no version, so its
// `--version` line is the reader.
const FLOOR = "1.1.0";
// One version read: a bound on a stalled program, not a latency budget.
const VERSION_MS = 10000;

// Pi 1.1.0's CLI (https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/cli.md): no discovered or configured extension,
// skill, prompt template, theme or context file, no saved session and no
// automatic network activity. A turn adds back only the built-in MCP
// support for the bridge.
const LOCKDOWN = Object.freeze(["--mode", "rpc", "--no-session", "--no-extensions", "--no-skills", "--no-prompt-templates",
    "--no-themes", "--no-context-files", "--offline"]);
// A turn trusts only its own working folder's .pi/mcp.json, and `--tools`
// starting with mcp__ filters MCP tools too, so the bridge's are the only
// tools declared (https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/mcp.md, "Control tool exposure").
const TURN = Object.freeze(["--extension", "builtin:mcp", "--approve", "--tools", Pi.TOOL_PREFIX + "*"]);
const BARE = Object.freeze(["--no-approve", "--no-tools", "--no-mcp"]);
// The plan's context bound in user turns, as the wire brains keep it.
const TURNS = 40;
// A program that never answers its first command is ended; the user's own
// configuration loads inside this bound.
const HANDSHAKE_MS = 30000;
// One Verify turn: a bound on a stalled provider, not a latency budget.
const PROBE_MS = 60000;
// One model read: a bound on a stalled program, not a latency budget.
const MODELS_MS = 10000;
const PROBE_INSTRUCTIONS = "Answer in one word.";

function fail(code) { throw new Error("jarvis: brain=pi-" + code); }

/**
 * The installed Pi's version, refused as pi-update below FLOOR. Synchronous:
 * the engine's account choice reads it inside its one blocking judgement.
 * Setpriv exits 127 when it finds no pi to run.
 */
function version(env) {
    const result = cp.spawnSync("setpriv", ["--pdeathsig", "KILL", "--", "pi", "--version"], { env: childEnvironment(env),
        stdio: ["ignore", "pipe", "ignore"], encoding: "utf8", timeout: VERSION_MS, maxBuffer: 1024 });
    if (result.error) fail("version cause=" + (result.error.code ?? "unknown"));
    if (result.status !== 0) fail("exited code=" + result.status + " signal=" + result.signal);
    const found = /^(\d+)\.(\d+)\.(\d+)(?:[-+][0-9A-Za-z.+-]*)?\s*$/.exec(result.stdout);
    if (found === null) fail("version-shape");
    const floor = FLOOR.split(".").map(Number);
    for (let i = 0; i < 3; i++) {
        const part = Number(found[i + 1]);
        if (part > floor[i]) break;
        if (part < floor[i]) fail("update need=" + FLOOR);
    }
    return found[0].trim();
}

/**
 * One Pi program in a fresh private folder under runtime, its system prompt
 * replaced by instructions and, with bridge, the bridge as its one MCP
 * server. The bridge's variables travel only in that folder's 0600
 * mcp.json, never in Pi's environment: Pi starts the user's own MCP servers
 * with its environment (seen in a Pi 1.1.0 run), and the token would reach
 * them. model, a "provider/id" reference or "", is set before the first
 * turn. hooks: {event(event), request(id, request, session)},
 * and ended(error).
 */
async function open({ directory, env, runtime, model, instructions, bridge }, hooks) {
    Private.directory(runtime);
    const cwd = fs.mkdtempSync(path.join(runtime, "pi-"));
    let session = null;
    let p = null, timer;
    try {
        const prompt = path.join(cwd, "instructions.md");
        fs.writeFileSync(prompt, instructions, { flag: "wx", mode: 0o600 });
        if (bridge !== null) {
            fs.mkdirSync(path.join(cwd, ".pi"), { mode: 0o700 });
            const server = { command: bridge.command, args: [...bridge.args], exposure: "direct", env: { ...bridge.env } };
            fs.writeFileSync(path.join(cwd, ".pi", "mcp.json"), JSON.stringify({ mcpServers: { [Pi.SERVER]: server } }),
                { flag: "wx", mode: 0o600 });
        }
        p = Harness.program({ name: "pi", argv: ["pi", ...LOCKDOWN, ...(bridge === null ? BARE : TURN), "--system-prompt", prompt],
            env, extra: { PI_CODING_AGENT_DIR: directory }, cwd,
            accept: Pi.accept, lineBytes: Pi.LINE_BYTES,
            refused: call => new Error("jarvis: brain=pi-refused command=" + call.method) }, value => {
            if (value.kind === "notification") hooks.event(value.event);
            else if (value.kind === "request") hooks.request(value.id, value.request, session ?? { program: p, cwd });
            // A handshake failure rejects its pending call instead.
            else if (session !== null) hooks.ended(value.error);
        });
        timer = setTimeout(() => p.close(), HANDSHAKE_MS);
        await p.call(id => Pi.noCompaction(id));
        if (model !== "") await p.call(id => Pi.setModel(id, Pi.model(model)));
        session = { program: p, cwd };
        return session;
    } catch (error) {
        await p?.close();
        fs.rmSync(cwd, { recursive: true, force: true });
        throw error;
    } finally { clearTimeout(timer); }
}

async function shut(session) {
    await session.program.close();
    fs.rmSync(session.cwd, { recursive: true, force: true });
}

// No one sits at Pi's side to answer an extension's dialog.
function request(id, value, current) {
    switch (value.kind) {
    case "dialog": current.program.write(Pi.cancelDialog(id)); return;
    case "notice": return;
    default: fail("request-kind");
    }
}

/**
 * The conversation's brain, behind the plan's interface: start, send as a
 * stream of text and done, cancel with an acknowledgement, and close. options
 * carries the engine's {provider, model, recipients} and the harness facts:
 * account (the Pi folder), gen, and {bridge, env, runtime}. A harness turn
 * yields no tool-call event: Pi's tool calls reach the router through the
 * bridge itself.
 */
function create({ provider, model, recipients, account, gen, harness }) {
    Policy.assertRecipients(recipients);
    if (provider?.id !== "pi") fail("provider");
    if (!account || account.kind !== "cli" || typeof account.directory !== "string") fail("account");
    if (!harness) fail("unwired");
    if (model !== "") Pi.model(model);
    const { bridge, env, runtime } = harness;
    let instructions = null;
    let opening = null;
    let launch = null;
    let session = null;
    let turns = 0;
    let active = null;
    // The turn Pi is running: a cancelled turn leaves active at once, but
    // only Pi's settled run acknowledges its cancel.
    let running = null;
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
            const opened = await open({ directory: account.directory, env, runtime: runtime(), model, instructions,
                bridge: launch }, { event, request, ended: error => { ended ??= error; (running ?? active)?.fault(error); } });
            if (closed) { await shut(opened); fail("closed"); }
            session = opened;
            return opened;
        })();
        return opening;
    }

    function event(e) {
        // A tool other than the bridge's is one the lockdown did not remove,
        // whichever turn it starts in.
        if (e.kind === "tool" && !e.bridge && session !== null) {
            const error = new Error("jarvis: brain=pi-builtin");
            ended ??= error;
            session.program.abort(error);
            return;
        }
        const turn = running;
        if (turn === null || session === null) return;
        switch (e.kind) {
        case "text": turn.push({ kind: "text", text: e.text }); break;
        case "reply-end": turn.stop = e.stop; break;
        case "tool": break;
        case "settled": running = null; turn.settled(e.aborted); break;
        case "other": break;
        default: fail("event-kind");
        }
    }

    function send(turn, grants = []) {
        usable();
        if (instructions === null) fail("not-started");
        const { text, labels, release } = Harness.release(turn, recipients, grants, fail);
        if (turns >= TURNS) throw new Error("jarvis: brain=context-limit");

        // requested: the prompt is written, so only Pi's settled run
        // acknowledges a cancel. stop is the last reply's stop reason.
        const current = { requested: false, stop: null };
        const { handle, events } = Harness.stream({ run, settled() {}, detach: () => { if (active === current) active = null; },
            interrupt() {
                if (!current.requested || session === null) return false;
                session.program.call(id => Pi.abort(id)).catch(() => {});
                return true;
            } });
        Object.assign(current, { push: handle.push, fault: handle.fault, cancel: handle.cancel,
            // A cancel is acknowledged whatever the run's end; a run Pi
            // aborted on its own fails as one.
            settled(aborted) {
                handle.finish(!aborted && current.stop === "stop" ? { kind: "complete" }
                    : { kind: "failed", error: new Error("jarvis: brain=pi-stop-" + (aborted ? "aborted" : current.stop ?? "none")) });
            } });

        async function run() {
            try {
                if (labels.length === 0) fail("release-empty");
                const opened = await ensure();
                if (handle.state() !== "streaming") return;
                turns++;
                current.requested = true;
                running = current;
                Pi.started(await opened.program.call(id => Pi.prompt(id, text)));
            } catch (error) {
                // A refused prompt starts no run for Pi to settle.
                if (running === current) running = null;
                current.fault(error);
            }
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
 * One bounded run of a Pi program with no tools: work(session, outcome)
 * sends its commands, outcome resolving with the first settled run's
 * {aborted, stop, reply} and rejecting when the program ends first. Throws
 * a keyed error when the version, the program, the run or the deadline
 * fails. The caller
 * owns release and audit.
 */
async function bare({ directory, env, runtime, model, deadline, key }, work) {
    version(env);
    let session = null;
    let reply = "", stop = null, failed = null, settle;
    const outcome = new Promise((resolve, reject) => { settle = { resolve, reject }; });
    // A work that reads no run leaves outcome unawaited; its end is failed's.
    outcome.catch(() => {});
    const hooks = {
        event(e) {
            if (e.kind === "text") reply += e.text;
            else if (e.kind === "reply-end") stop = e.stop;
            // A program with no tools runs none.
            else if (e.kind === "tool") failed ??= new Error("jarvis: brain=pi-builtin");
            else if (e.kind === "settled") settle.resolve({ aborted: e.aborted, stop, reply });
        },
        request,
        ended(error) { failed ??= error; settle.reject(error); }
    };
    let timer;
    try {
        // The handshake keeps its own bound; the deadline covers the work.
        session = await open({ directory, env, runtime, model, instructions: PROBE_INSTRUCTIONS, bridge: null }, hooks);
        const limit = new Promise((resolve, reject) => {
            timer = setTimeout(() => reject(new Error("jarvis: brain=pi-" + key + "-deadline")), deadline);
        });
        const result = await Promise.race([limit, work(session, outcome)]);
        if (failed !== null) throw failed;
        return result;
    } finally {
        clearTimeout(timer);
        if (session !== null) await shut(session);
    }
}

/**
 * Account Verify's smallest real request: one prompt of text with no tools,
 * through the user's own Pi. Resolves with the reply's text.
 */
async function probe({ directory, env, runtime, model, text }) {
    return bare({ directory, env, runtime, model, deadline: PROBE_MS, key: "probe" }, async (session, outcome) => {
        Pi.started(await session.program.call(id => Pi.prompt(id, text)));
        const run = await outcome;
        if (run.aborted || run.stop !== "stop") fail("stop-" + (run.aborted ? "aborted" : run.stop ?? "none"));
        if (run.reply.trim() === "") fail("no-reply");
        return run.reply;
    });
}

/**
 * The models the user's own Pi offers, from its own list: PiRpc.menu's
 * {provider, id} values, the selected model first. Sends no prompt.
 */
async function models({ directory, env, runtime }) {
    return bare({ directory, env, runtime, model: "", deadline: MODELS_MS, key: "models" }, async session =>
        Pi.menu(await session.program.call(id => Pi.models(id)), await session.program.call(id => Pi.state(id))));
}

module.exports = { version, create, probe, models };
