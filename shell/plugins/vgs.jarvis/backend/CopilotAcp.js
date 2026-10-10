// The Copilot ACP v1 judge builds every message Jarvis writes to
// `copilot --acp --stdio` and narrows every line Copilot writes back. No
// other file parses this protocol. The pinned schema excerpt is
// scripts/fixtures/jarvis-copilot/acp.schema.json, and the recording is the
// offline Copilot 1.0.91 handshake with no account and one signed-in
// session/new answer.
"use strict";

// One JSON-RPC message per line. A tool call's diff can carry a whole file,
// so the ceiling is the wire brains' total stream bound.
const LINE_BYTES = 8 * 1024 * 1024;
const VERSION = 1;
const CLIENT = Object.freeze({ name: "vgs-jarvis", title: "VGS Jarvis", version: "1" });
// The bridge's server name in session/new. Jarvis passes no other server.
const SERVER = "vgs_jarvis";
// session/prompt stop reasons. Only end_turn completes a turn.
const STOPS = Object.freeze(["end_turn", "max_tokens", "max_turn_requests", "refusal", "cancelled"]);
const KINDS = Object.freeze(["read", "edit", "delete", "move", "search", "execute", "think", "fetch", "switch_mode", "other"]);
const STATUSES = Object.freeze(["pending", "in_progress", "completed", "failed"]);
const OPTIONS = Object.freeze(["allow_once", "allow_always", "reject_once", "reject_always"]);

function fail(code) { throw new Error("jarvis: brain=copilot-" + code); }
function plain(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function string(value) { return typeof value === "string"; }
function absent(value) { return value === undefined || value === null; }
function validId(id) { return string(id) || Number.isSafeInteger(id); }

function request(id, method, params) { return { jsonrpc: "2.0", id, method, params }; }

/**
 * The handshake's first request. Jarvis offers the agent no file system and
 * no terminal, so an agent that honours its capabilities calls neither.
 */
function initialize(id) {
    return request(id, "initialize", { protocolVersion: VERSION,
        clientCapabilities: { fs: { readTextFile: false, writeTextFile: false }, terminal: false }, clientInfo: { ...CLIENT } });
}

/**
 * The conversation's session, with no MCP server. Copilot 1.0.91 advertises
 * mcpCapabilities {http, sse} and drops a stdio server sent here, logging
 * `Rejecting non-http/sse MCP server "vgs_jarvis" from client`; the bridge
 * reaches it through CopilotHarness's private config file instead.
 * @param {{cwd: string}} value
 */
function sessionNew(id, { cwd }) {
    return request(id, "session/new", { cwd, mcpServers: [] });
}

/** One user turn: each string is one text block, in order. */
function prompt(id, sessionId, texts) {
    return request(id, "session/prompt", { sessionId, prompt: texts.map(text => ({ type: "text", text })) });
}

/** The notification that cancels the session's running prompt. */
function cancel(sessionId) { return { jsonrpc: "2.0", method: "session/cancel", params: { sessionId } }; }

/**
 * The answer to a narrowed agent request. A permission request is answered
 * with its one-time allow or reject option; without the option chosen, or
 * when its turn was cancelled, the outcome is cancelled. An unsupported
 * method answers a JSON-RPC error.
 * @param {"allow"|"reject"|"cancelled"} choice
 */
function answer(id, value, choice) {
    switch (value.kind) {
    case "permission": {
        let option;
        switch (choice) {
        case "allow": option = value.allow; break;
        case "reject": option = value.reject; break;
        case "cancelled": option = null; break;
        default: return fail("answer");
        }
        return { jsonrpc: "2.0", id, result: { outcome: option === null ? { outcome: "cancelled" }
            : { outcome: "selected", optionId: option } } };
    }
    case "unsupported": return { jsonrpc: "2.0", id, error: { code: -32601, message: "Method not found" } };
    default: return fail("request-kind");
    }
}

/**
 * The agent's initialize result, judged against the program row: protocol
 * version 1, the row's agent name, and a version at or above the floor the
 * row's lockdown was established on. Returns the version.
 */
function agent(result, row) {
    if (!plain(result) || result.protocolVersion !== VERSION) fail("protocol");
    const info = result.agentInfo;
    if (!plain(info) || info.name !== row.agent || !string(info.version)) fail("agent");
    const version = /^(\d+)\.(\d+)\.(\d+)(?:[-+][0-9A-Za-z.+-]*)?$/.exec(info.version);
    if (version === null) fail("agent-version");
    const floor = row.floor.split(".").map(Number);
    for (let i = 0; i < 3; i++) {
        const part = Number(version[i + 1]);
        if (part > floor[i]) break;
        if (part < floor[i]) fail("agent-version");
    }
    return info.version;
}

function sessionId(result) {
    if (!plain(result) || !string(result.sessionId) || result.sessionId === "") fail("session");
    return result.sessionId;
}

/**
 * A session/new result's models, for Harness.offers: the options of its
 * model selector, the entry of configOptions whose category is "model"
 * (ACP 1.7.0 SessionConfigOption). value is the id --model takes, and own
 * marks the selector's current value. The selector names no effort level,
 * so a model offers none. Copilot 1.0.91 answered a flat selector with
 * "auto" three times and current (a run on 2026-10-09, the recording's
 * signed-in flow).
 */
function models(result) {
    const selector = plain(result) && Array.isArray(result.configOptions)
        ? result.configOptions.find(option => plain(option) && option.category === "model") : undefined;
    if (selector === undefined || !string(selector.currentValue) || !Array.isArray(selector.options)) fail("model-list");
    return selector.options.map(entry => {
        if (!plain(entry) || !string(entry.value) || !string(entry.name)) fail("model-list");
        return { value: entry.value, label: entry.name, efforts: [], effort: "", own: entry.value === selector.currentValue };
    });
}

function stopReason(result) {
    if (!plain(result) || !STOPS.includes(result.stopReason)) fail("stop-reason");
    return result.stopReason;
}

function locations(value) {
    if (absent(value)) return [];
    if (!Array.isArray(value) || !value.every(entry => plain(entry) && string(entry.path))) fail("message");
    return value.map(entry => entry.path);
}

// The diffs a tool call carries. Other content passes unread.
function diffs(value) {
    if (absent(value)) return [];
    if (!Array.isArray(value) || !value.every(plain)) fail("message");
    return value.filter(entry => entry.type === "diff").map(entry => {
        if (!string(entry.path) || !string(entry.newText) || !(absent(entry.oldText) || string(entry.oldText))) fail("message");
        return { path: entry.path, newText: entry.newText };
    });
}

/**
 * One tool call as the agent reports it. A new call names its title; in an
 * update or a permission request every field but the id is optional.
 */
function toolCall(value, partial) {
    if (!plain(value) || !string(value.toolCallId) || value.toolCallId === "") fail("tool-call");
    if (partial ? !(absent(value.title) || string(value.title)) : !string(value.title)) fail("tool-call");
    if (!absent(value.kind) && !KINDS.includes(value.kind)) fail("tool-kind");
    if (!absent(value.status) && !STATUSES.includes(value.status)) fail("tool-status");
    return { id: value.toolCallId, title: value.title ?? null, kind: value.kind ?? null, status: value.status ?? null,
        locations: locations(value.locations), diffs: diffs(value.content), rawInput: value.rawInput ?? null };
}

function update(params) {
    if (!plain(params) || !string(params.sessionId) || !plain(params.update) || !string(params.update.sessionUpdate)) fail("message");
    const u = params.update;
    const sessionId = params.sessionId;
    switch (u.sessionUpdate) {
    case "agent_message_chunk":
        if (!plain(u.content) || !string(u.content.type)) fail("message");
        if (u.content.type !== "text") return { kind: "content", sessionId, type: u.content.type };
        if (!string(u.content.text)) fail("message");
        return { kind: "text", sessionId, text: u.content.text };
    case "tool_call": return { kind: "tool-call", sessionId, call: toolCall(u, false) };
    case "tool_call_update": return { kind: "tool-update", sessionId, call: toolCall(u, true) };
    default: return { kind: "other", sessionId, update: u.sessionUpdate };
    }
}

function options(value) {
    if (!Array.isArray(value) || value.length === 0) fail("message");
    let allow = null, reject = null;
    for (const option of value) {
        if (!plain(option) || !string(option.optionId) || !string(option.name) || !OPTIONS.includes(option.kind)) fail("message");
        // Never a standing grant: each request is one decision.
        if (option.kind === "allow_once" && allow === null) allow = option.optionId;
        if (option.kind === "reject_once" && reject === null) reject = option.optionId;
    }
    return { allow, reject };
}

function agentRequest(method, params) {
    switch (method) {
    case "session/request_permission":
        if (!plain(params) || !string(params.sessionId)) fail("message");
        return { kind: "permission", sessionId: params.sessionId, call: toolCall(params.toolCall, true), ...options(params.options) };
    default: return { kind: "unsupported", method };
    }
}

/**
 * Narrow one line the agent wrote: a response, a failure, a notification or
 * a request. An unreadable line throws a keyed error.
 */
function accept(line) {
    if (Buffer.byteLength(line) + 1 > LINE_BYTES) fail("line-size");
    let message;
    try { message = JSON.parse(line); } catch { fail("json"); }
    if (!plain(message) || message.jsonrpc !== "2.0") fail("message");
    const hasId = Object.hasOwn(message, "id");
    if (hasId && !validId(message.id)) fail("message");
    if (string(message.method)) {
        if (hasId) return { kind: "request", id: message.id, request: agentRequest(message.method, message.params) };
        if (message.method === "session/update") return { kind: "notification", event: update(message.params) };
        return { kind: "notification", event: { kind: "other", method: message.method } };
    }
    if (!hasId) fail("message");
    if (Object.hasOwn(message, "result")) return { kind: "response", id: message.id, result: message.result };
    if (plain(message.error) && Number.isSafeInteger(message.error.code) && string(message.error.message))
        return { kind: "failure", id: message.id, code: message.error.code };
    return fail("message");
}

// A command as its tool call's raw input states it: a string, or argv.
function commandText(rawInput) {
    if (!plain(rawInput)) return null;
    const value = rawInput.command;
    if (string(value) && value !== "") return value;
    if (Array.isArray(value) && value.length !== 0 && value.every(string)) return value.join(" ");
    return null;
}

/**
 * The gate's typed call for a permission request, from its tool call and the
 * call the agent announced under that id. Edits, deletions and moves list
 * every path the call names; a command needs its text. A call that names
 * neither carries no arguments, which the router refuses, and any other
 * kind has no row.
 */
function proposal(value, announced, cwd) {
    const call = value.call;
    const kind = call.kind ?? announced?.kind ?? null;
    const named = [...call.diffs, ...(call.diffs.length === 0 ? announced?.diffs ?? [] : [])];
    const paths = [...new Set([...call.locations, ...(announced?.locations ?? []), ...named.map(d => d.path)])];
    const diff = named.map(d => d.path + "\n" + d.newText + (d.newText.endsWith("\n") ? "" : "\n")).join("");
    const files = (write, move, remove) => ({ tool: "harness.files",
        arguments: paths.length === 0 ? {} : { write, move, remove, diff } });
    switch (kind) {
    case "edit": return files(paths, [], []);
    case "delete": return files([], [], paths);
    // Which path is the source is the agent's word, so each is judged in both roles.
    case "move": return files(paths, paths, []);
    case "execute": {
        const text = commandText(call.rawInput) ?? commandText(announced?.rawInput);
        const input = plain(call.rawInput) ? call.rawInput : announced?.rawInput;
        const where = plain(input) && string(input.cwd) ? input.cwd : cwd;
        return { tool: "harness.command", arguments: text === null ? {} : { command: text, cwd: where } };
    }
    default: return { tool: "harness.permissions", arguments: {} };
    }
}

/**
 * Whether a narrowed call is one of the bridge's: Copilot 1.0.91 titles an MCP
 * call `<server>-<tool>`, as in `vgs_jarvis-files_list`, and its rawInput is
 * the call's arguments. tools are the bridge's MCP tools ({name, inputSchema});
 * a title naming none of them, or an argument the tool does not declare, is
 * not the bridge's.
 */
function bridged(call, tools) {
    const tool = tools.find(entry => call.title === SERVER + "-" + entry.name);
    if (tool === undefined) return false;
    const declared = Object.keys(tool.inputSchema.properties ?? {});
    return absent(call.rawInput) || (plain(call.rawInput) && Object.keys(call.rawInput).every(key => declared.includes(key)));
}

module.exports = { LINE_BYTES, SERVER, initialize, sessionNew, prompt, cancel, answer, agent, sessionId, models, stopReason,
    accept, proposal, bridged };
