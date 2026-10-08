#!/usr/bin/env node
// Stand-in `pi` built from the Pi 1.1.0 RPC excerpt (rpc.schema.json) and
// the sanitized recording beside it. The recording ran
// @earendil-works/pi-coding-agent 1.1.0 (tarball SHA-256
// 09cd8a0a43dbb1d81a67346b09400b439ce71d818caba4e963ea958846a1aed4) through
// PiHarness.models, PiHarness.probe and one PiHarness conversation (a turn
// with one bridge tool call, then a cancelled turn), with a scratch
// PI_CODING_AGENT_DIR whose models.json named one loopback stand-in model
// server, whose mcp.json named a user-level MCP server and whose extensions
// folder held an extension, so no account, network or paid request was
// used. Besides Pi's lines it holds each run's argv, the tools each model
// request offered, whether the user-level server's environment held the
// bridge token and whether the extension loaded. Scratch paths read
// /scratch and system prompts are cut.
// It speaks the RPC subset Jarvis uses on stdio and replays a scenario the
// test writes to $XDG_STATE_HOME/pi-scenario.json:
//   { crash: "handshake", hang: "handshake", refuse: command type (answered
//     success false), models: [model], state: {get_state data},
//     reply: "text" (any prompt), turns: [[step, ...], ...], leak: true }
// A step is {text} (one text_delta), {tool: {name, durationMs?, hold?}} (a
// tool's execution events; hold never ends the tool), {mcp: {tool, arguments}} (a tools/call through the
// server cwd/.pi/mcp.json names, with its environment, tools/list first,
// then its execution events), {dialog: method} (waits for the answer), {notice: text}, {abort:
// true} (waits for abort), {stop: reason} (the reply's message_end and the
// settled run), {exit: code} or {raw: bytes}. With leak, the key in
// $PI_CODING_AGENT_DIR/auth.json goes into every field Jarvis must leave
// unread: stderr, each model's extra fields, a refusal's error, a notice, a
// reply's errorMessage and a tool's result. Every line is appended to
// $XDG_STATE_HOME/pi-log as {direction, message}, with the count of Jarvis's
// audit lines when a prompt arrives; argv, environment, cwd and the files
// Jarvis wrote to pi-calls.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");
const state = process.env.XDG_STATE_HOME;
const args = process.argv.slice(2);
const DEATHSIG = "FIXTURE_PI_DEATHSIG";
if (process.env[DEATHSIG] === undefined)
    process.execve("/usr/bin/env", ["env", "python3", "-I", "-c", [
        "import ctypes, os, sys",
        "value = ctypes.c_int(-1)",
        "if ctypes.CDLL(None, use_errno=True).prctl(2, ctypes.byref(value), 0, 0, 0) != 0: sys.exit(9)",
        "os.environ['" + DEATHSIG + "'] = str(value.value)",
        "os.execv(sys.argv[1], sys.argv[1:])"].join("\n"), process.execPath, __filename, ...args]);
const deathsig = Number(process.env[DEATHSIG]);
delete process.env[DEATHSIG];
const read = file => fs.existsSync(file) ? fs.readFileSync(file, "utf8") : null;
const prompt = args.includes("--system-prompt") ? args[args.indexOf("--system-prompt") + 1] : null;
fs.appendFileSync(path.join(state, "pi-calls"), JSON.stringify({ args, env: process.env, cwd: process.cwd(), pid: process.pid,
    parent: process.ppid, deathsig, instructions: prompt === null ? null : read(prompt),
    mcp: read(path.join(process.cwd(), ".pi/mcp.json")),
    mcpMode: fs.existsSync(path.join(process.cwd(), ".pi/mcp.json")) ? fs.statSync(path.join(process.cwd(), ".pi/mcp.json")).mode & 0o777 : null }) + "\n");
if (args[0] !== "--mode" || args[1] !== "rpc") process.exit(9);
const scenario = JSON.parse(fs.readFileSync(path.join(state, "pi-scenario.json"), "utf8"));
const recorded = fs.readFileSync(path.join(state, "pi-recorded.ndjson"), "utf8").trim().split("\n").map(line => JSON.parse(line));
const log = (direction, message) => fs.appendFileSync(path.join(state, "pi-log"), JSON.stringify({ direction, message }) + "\n");
const keepalive = () => setInterval(() => {}, 1000);
const auth = read(path.join(process.env.PI_CODING_AGENT_DIR ?? "", "auth.json"));
const key = scenario.leak && auth !== null ? JSON.parse(auth).stub.key : null;
if (key !== null) process.stderr.write("pi: using key " + key + "\n");
const answers = new Map();
let prompts = 0, uiId = 0, aborted = null, abortSeen = false;
const recordedModel = recorded.find(row => row.direction === "out" && row.line.command === "get_available_models").line.data.models[0];

function auditLines() {
    const directory = path.join(state, "vgshell/jarvis/audit");
    if (!fs.existsSync(directory)) return 0;
    return fs.readdirSync(directory).reduce((count, name) =>
        count + fs.readFileSync(path.join(directory, name), "utf8").split("\n").filter(Boolean).length, 0);
}
function write(message) {
    log("out", message);
    process.stdout.write(JSON.stringify(message) + "\n");
}
const respond = (message, data) => write({ id: message.id, type: "response", command: message.type, success: true,
    ...(data === undefined ? {} : { data }) });
const assistant = extra => ({ role: "assistant", content: [], api: "openai-completions", provider: "stub", model: "stub-1", ...extra });
function settle(isAborted, stop) {
    write({ type: "message_end", message: assistant({ stopReason: stop, ...(key === null ? {} : { errorMessage: "401 " + key }) }) });
    write({ type: "agent_end", messages: [], willRetry: false });
    write({ type: "agent_settled", aborted: isAborted });
}
async function tool(name, durationMs, result, hold) {
    const toolCallId = "call_" + uiId++;
    write({ type: "tool_execution_start", toolCallId, toolName: name, args: {} });
    if (hold) { keepalive(); await new Promise(() => {}); }
    write({ type: "tool_execution_end", toolCallId, toolName: name, isError: false,
        result: result ?? { content: [{ type: "text", text: key ?? "done" }] }, ...(durationMs === undefined ? {} : { durationMs }) });
}
function dialog(method) {
    const id = "ui-" + uiId++;
    return new Promise(resolve => { answers.set(id, resolve); write({ type: "extension_ui_request", id, method, title: "fixture" }); });
}

// A minimal MCP client of the bridge server .pi/mcp.json names, started as
// Pi starts a server: this program's environment plus the server's env.
async function mcp(call) {
    const server = JSON.parse(fs.readFileSync(path.join(process.cwd(), ".pi/mcp.json"), "utf8")).mcpServers.vgs_jarvis;
    const child = cp.spawn(server.command, server.args, { env: { ...process.env, ...server.env }, stdio: ["pipe", "pipe", "inherit"] });
    let tail = "";
    const waiting = new Map();
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", chunk => {
        tail += chunk;
        let end;
        while ((end = tail.indexOf("\n")) >= 0) {
            const message = JSON.parse(tail.slice(0, end));
            tail = tail.slice(end + 1);
            waiting.get(message.id)?.(message);
        }
    });
    const request = (id, method, params) => new Promise(resolve => {
        waiting.set(id, resolve);
        child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    });
    await request(1, "initialize", { protocolVersion: "2025-11-25", capabilities: { roots: {} }, clientInfo: { name: "pi", version: "1.1.0" } });
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
    const tools = await request(2, "tools/list", {});
    const result = await request(3, "tools/call", { name: call.tool, arguments: call.arguments });
    child.stdin.end();
    log("mcp", { tools: tools.result?.tools?.map(entry => entry.name) ?? null, result });
    await tool("mcp__vgs_jarvis__" + call.tool, 5, result.result);
}

async function turn(steps) {
    write({ type: "agent_start" });
    for (const step of steps) {
        if (step.text !== undefined) write({ type: "message_update", usage: {}, assistantMessageEvent: { type: "text_delta", contentIndex: 0, delta: step.text } });
        else if (step.tool) await tool(step.tool.name, step.tool.durationMs, undefined, step.tool.hold);
        else if (step.mcp) await mcp(step.mcp);
        else if (step.dialog) log("answer", await dialog(step.dialog));
        else if (step.notice) write({ type: "extension_ui_request", id: "ui-" + uiId++, method: "notify", message: key ?? step.notice });
        else if (step.raw) process.stdout.write("x".repeat(step.raw));
        else if (step.exit !== undefined) process.exit(step.exit);
        else if (step.abort) {
            if (!abortSeen) await new Promise(resolve => { aborted = resolve; });
            return;
        } else if (step.stop) { settle(false, step.stop); return; }
    }
}

function models() {
    const list = scenario.models ?? [recordedModel];
    return key === null ? list : list.map(model => ({ ...model, apiKey: key, headers: { authorization: "Bearer " + key } }));
}

function handle(message) {
    if (message.type === "extension_ui_response") { answers.get(message.id)?.(message); answers.delete(message.id); return; }
    if (message.type === scenario.refuse) {
        write({ id: message.id, type: "response", command: message.type, success: false, error: "fixture refused " + (key ?? "") });
        return;
    }
    switch (message.type) {
    case "set_auto_compaction":
        if (scenario.crash === "handshake") process.exit(3);
        if (scenario.hang === "handshake") { keepalive(); return; }
        respond(message);
        return;
    case "set_model": respond(message, { ...recordedModel, provider: message.provider, id: message.modelId }); return;
    case "get_available_models": respond(message, { models: models() }); return;
    case "get_state": respond(message, scenario.state ?? recorded.find(row => row.direction === "out" && row.line.command === "get_state").line.data); return;
    case "prompt": {
        respond(message, { disposition: "started" });
        const steps = scenario.reply !== undefined ? [{ text: scenario.reply }, { stop: "stop" }] : scenario.turns[prompts];
        prompts++;
        void turn(steps);
        return;
    }
    case "abort":
        abortSeen = true;
        settle(true, "aborted");
        respond(message);
        aborted?.();
        return;
    default: write({ id: message.id, type: "response", command: message.type, success: false, error: "fixture: unscripted" });
    }
}

let tail = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => {
    tail += chunk;
    let end;
    while ((end = tail.indexOf("\n")) >= 0) {
        const message = JSON.parse(tail.slice(0, end));
        tail = tail.slice(end + 1);
        log("in", message);
        if (message.type === "prompt") log("audit", { lines: auditLines() });
        handle(message);
    }
});
process.stdin.on("end", () => { if (!scenario.hang) process.exit(0); });
