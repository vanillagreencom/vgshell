// The Pi RPC judge builds every record Jarvis writes to `pi --mode rpc` and
// narrows every line Pi writes back. No other file parses this protocol. The
// interface is Pi 1.1.0's documented RPC mode (rpc.md, rpc-commands.md,
// json.md and rpc-extension-ui.md under https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/); the
// pinned excerpt is scripts/fixtures/jarvis-pi/rpc.schema.json and the
// recording scripts/fixtures/jarvis-pi/recorded.ndjson. A failed command's
// error text and every message body but a text delta are left unread: they
// can carry provider text or a credential.
"use strict";

// One JSON record per LF-terminated line (https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/rpc.md, "Framing"). A tool result
// can carry a whole file, so the ceiling is the wire brains' total stream
// bound.
const LINE_BYTES = 8 * 1024 * 1024;
// The bridge's server name in .pi/mcp.json. Pi names its tools
// mcp__<server>__<tool> (https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/mcp.md, "Configuration rules").
const SERVER = "vgs_jarvis";
const TOOL_PREFIX = "mcp__" + SERVER + "__";
// pi-ai's StopReason. Only stop completes a turn.
const STOPS = Object.freeze(["stop", "length", "toolUse", "error", "aborted"]);
// The dialog methods block until answered (rpc-extension-ui.md).
const DIALOGS = Object.freeze(["select", "confirm", "input", "editor"]);
// A model menu offers at most this many of one Pi setup's models.
const MODELS = 16;
// A reference's bounds keep a model choice, the reference, within a choices
// value's 200 characters.
const PROVIDER_CHARS = 40;
const ID_CHARS = 120;
// Pi's thinking levels, which the Jarvis page calls effort
// (https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/rpc-commands.md, "set_thinking_level").
const LEVELS = Object.freeze(["off", "minimal", "low", "medium", "high", "xhigh", "max"]);

function fail(code) { throw new Error("jarvis: brain=pi-" + code); }
function plain(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function string(value) { return typeof value === "string"; }
function printable(value, max) {
    return string(value) && value.length > 0 && value.length <= max && !/[\x00-\x1f\x7f]/.test(value);
}

// Jarvis's command ids are strings, as Pi's responses repeat them.
function command(id, type, fields = {}) { return { id: "j" + id, type, ...fields }; }

/** One user prompt: Pi rejects one sent while it streams, so Jarvis sends one per turn. */
function prompt(id, message) { return command(id, "prompt", { message }); }
function abort(id) { return command(id, "abort"); }
function models(id) { return command(id, "get_available_models"); }
function state(id) { return command(id, "get_state"); }
/** Jarvis never lets Pi summarise its history: the context bound refuses instead. */
function noCompaction(id) { return command(id, "set_auto_compaction", { enabled: false }); }
function setModel(id, model) { return command(id, "set_model", { provider: model.provider, modelId: model.id }); }
function thinkingLevels(id) { return command(id, "get_available_thinking_levels"); }
function setThinkingLevel(id, value) { return command(id, "set_thinking_level", { level: value }); }
/** Every dialog an extension opens is answered cancelled: no one is at Pi's side. */
function cancelDialog(id) { return { type: "extension_ui_response", id, cancelled: true }; }

/**
 * A model reference as a choice carries it, "provider/id": the provider
 * names no slash, the id may. Returns {provider, id}; anything else refuses.
 */
function model(reference) {
    if (!string(reference)) fail("model");
    const at = reference.indexOf("/");
    const value = { provider: reference.slice(0, Math.max(at, 0)), id: reference.slice(at + 1) };
    if (at < 0 || !fits(value)) fail("model");
    return value;
}
function fits(value) {
    return printable(value.provider, PROVIDER_CHARS) && printable(value.id, ID_CHARS);
}
function reference(value) { return value.provider + "/" + value.id; }

/**
 * An effort level as a setting carries it: one of LEVELS, returned; anything
 * else refuses. Pi answers success for a word it does not know and keeps
 * its level (seen in a Pi 1.1.0 run), so the refusal is here.
 */
function level(value) {
    if (!LEVELS.includes(value)) fail("effort");
    return value;
}

/**
 * The effort levels of a get_available_thinking_levels result, the selected
 * model's. Pi answers ["off"] for a model without reasoning support
 * (rpc-commands.md), which takes no effort. A level LEVELS does not name,
 * as a later Pi may list, is left out, not refused: level() would refuse it
 * as a choice.
 */
function levels(result) {
    if (!plain(result) || !Array.isArray(result.levels)) fail("level-list");
    const known = result.levels.filter(value => LEVELS.includes(value));
    return known.length === 1 && known[0] === "off" ? [] : known;
}

function modelOf(value) {
    if (!plain(value) || !string(value.provider) || value.provider.includes("/") || !string(value.id)) fail("model-list");
    return Object.freeze({ provider: value.provider, id: value.id });
}

/**
 * The menu's models from get_available_models and get_state results: the
 * selected model first, then Pi's order, MODELS at most, each narrowed to
 * {provider, id}. No other model field is kept: a configured endpoint's
 * fields are the user's own setup.
 */
function menu(listed, current) {
    if (!plain(listed) || !Array.isArray(listed.models) || !plain(current)) fail("model-list");
    const all = listed.models.map(modelOf);
    const selected = current.model === undefined ? null : modelOf(current.model);
    const ordered = selected === null ? all
        : [...all.filter(m => reference(m) === reference(selected)), ...all.filter(m => reference(m) !== reference(selected))];
    // A model whose names a choice cannot carry is left out, not refused.
    return Object.freeze(ordered.filter((m, i) => fits(m) && ordered.findIndex(o => reference(o) === reference(m)) === i)
        .slice(0, MODELS));
}

/** A prompt's response: only a run Pi started answers the turn. */
function started(result) {
    if (!plain(result) || result.disposition !== "started") fail("prompt-disposition");
}

function update(value) {
    if (!plain(value) || !string(value.type)) fail("message");
    if (value.type !== "text_delta") return { kind: "other" };
    if (!string(value.delta)) fail("message");
    return { kind: "text", text: value.delta };
}

function event(message) {
    switch (message.type) {
    case "message_update": return update(message.assistantMessageEvent);
    case "message_end": {
        if (!plain(message.message) || !string(message.message.role)) fail("message");
        if (message.message.role !== "assistant") return { kind: "other" };
        if (!STOPS.includes(message.message.stopReason)) fail("stop-reason");
        return { kind: "reply-end", stop: message.message.stopReason };
    }
    // Judged as a tool starts, before it can act, whether or not it then
    // runs (https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/json.md,
    // "Tool execution events").
    case "tool_execution_start":
        if (!string(message.toolCallId) || !string(message.toolName)) fail("message");
        return { kind: "tool", bridge: message.toolName.startsWith(TOOL_PREFIX) };
    case "agent_settled":
        if (typeof message.aborted !== "boolean") fail("message");
        return { kind: "settled", aborted: message.aborted };
    default: return { kind: "other" };
    }
}

/**
 * Narrow one line Pi wrote: a response, a failure, a notification or a
 * request. A failure keeps only its command. An unreadable line throws a
 * keyed error.
 */
function accept(line) {
    if (Buffer.byteLength(line) + 1 > LINE_BYTES) fail("line-size");
    let message;
    try { message = JSON.parse(line.endsWith("\r") ? line.slice(0, -1) : line); } catch { fail("json"); }
    if (!plain(message) || !string(message.type)) fail("message");
    switch (message.type) {
    case "response":
        // A response without an id answers a line Pi could not parse; Jarvis writes none.
        if (!string(message.id) || !string(message.command) || typeof message.success !== "boolean") fail("message");
        return message.success ? { kind: "response", id: message.id, result: message.data ?? null }
            : { kind: "failure", id: message.id, command: message.command };
    case "extension_ui_request":
        if (!string(message.id) || !string(message.method)) fail("message");
        return { kind: "request", id: message.id, request: { kind: DIALOGS.includes(message.method) ? "dialog" : "notice" } };
    default: return { kind: "notification", event: event(message) };
    }
}

module.exports = { LINE_BYTES, SERVER, TOOL_PREFIX, prompt, abort, models, state, noCompaction, setModel, thinkingLevels,
    setThinkingLevel, cancelDialog, model, reference, level, levels, menu, started, accept };
