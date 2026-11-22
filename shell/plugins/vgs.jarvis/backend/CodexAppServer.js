// The Codex harness's one app-server judge: it builds every message Jarvis
// writes to `codex app-server` and narrows every line the program writes back.
// No other file parses this protocol.
// Contract: docs/architecture/jarvis.md § Adapters.
"use strict";

// One JSON-RPC message per line. A thread or turn reply can carry a whole
// patch, so the ceiling is the wire brains' total stream bound.
const LINE_BYTES = 8 * 1024 * 1024;
const CLIENT = Object.freeze({ name: "vgs-jarvis", title: "VGS Jarvis", version: "1" });
// The bridge's server name in the thread's configuration. A user's own server
// of that name refuses the thread rather than merge with it.
const SERVER = "vgs_jarvis";
// Feature switches that give the model a built-in tool, run a program the
// gate cannot see or pick an access program VGS has not reviewed
// (cli_daybreak, api_key_cyber_access_programs), each judged against its
// description in codex-rs/features/src/lib.rs at rust-v0.171.0.
// multi_agent_v2 is off by default there, and a user's config.toml can
// switch on its sub-agent routing. Codex 0.169.0 with these off, web search
// disabled, the user-input tool off and catalog()'s catalog offered the
// model apply_patch alone, besides MCP access.
const FEATURES_OFF = Object.freeze(["shell_tool", "unified_exec", "view_image", "image_generation", "browser_use",
    "browser_use_external", "computer_use", "multi_agent", "multi_agent_v2", "apps", "plugins", "memories", "goals",
    "tool_suggest", "skill_search", "sleep_tool", "in_app_browser", "hooks", "code_mode_host", "remote_plugin",
    "workspace_dependencies", "skill_mcp_dependency_install", "shell_snapshot", "cli_daybreak",
    "api_key_cyber_access_programs"]);
// Every feature codex-cli 0.171.0 reports enabled on a thread started with
// FEATURES_OFF, each judged against its description in
// codex-rs/features/src/lib.rs at rust-v0.171.0. tui_workspace acts only in
// the TUI's side conversations. incremental_tools_legacy and its _gcp
// sibling change how tool declarations are sent, never which tools.
// worktrees and realtime_conversation read enabled whatever the thread sets
// and act only when the app asks for them. tool_search_always_defer_mcp_tools
// is Stage::Removed and reads enabled: MCP tools are always deferred when
// tool_search is available, which threadStart's bridge entry opts out of.
// Any other enabled feature may be a new tool, so the thread is refused.
const FEATURES_ENABLED = Object.freeze(["api_key_model_discovery", "auth_elicitation", "bedrock_setup_wizard",
    "browser_annotation_api", "browser_use_full_cdp_access", "code_mode_host_grpc", "code_mode_host_output_truncation",
    "code_mode_interrupt", "collaboration_modes", "compaction_image_budget", "content_item_kinds", "daemon_auto_start",
    "deferred_tool_world_state", "enable_request_compression", "fast_mode", "guardian_approval",
    "guardian_include_additional_context", "guardian_reuse_parent_compaction", "in_app_chat", "in_app_dictation",
    "in_app_local_automation", "in_app_updates", "in_app_voice", "incremental_tools", "incremental_tools_legacy",
    "incremental_tools_legacy_gcp", "instant_interrupt", "item_ids", "mcp_oauth_refresh_coordination", "mentions_v2",
    "plugin_sharing", "prediction_preserve_parent_tools", "realtime_conversation", "reasoning_effort_override",
    "resize_all_images", "retain_client_tool_outputs", "sqlite", "steer", "system_proxy_fallback",
    "terminal_resize_reflow", "tool_call_mcp_elicitation", "tool_search_always_defer_mcp_tools", "tui_app_server",
    "tui_workspace", "ultrafast_mode", "unbounded_connection_retries", "unified_exec", "unified_exec_tty",
    "unified_image_budget", "untrusted_as_tool_output", "worktrees", "write_stdin_approval"]);
// The model catalog's entry keys: the 42 that `codex debug models --bundled`
// prints on codex-cli 0.169.0 and the six optional ModelInfo fields it
// omits, which an account's catalog can carry, each judged against ModelInfo
// in codex-rs/protocol/src/openai_models.rs at rust-v0.169.0. An unknown key
// may be a new tool, so the catalog is refused. CATALOG_TOOLS are the keys
// that give the model a tool VGS has not reviewed: the code-mode runner
// (`exec`, `wait`), the sub-agent tools (`collaboration.*`) and the
// experimental `clock`, `sleep` and `send_user_message_async`. catalog()
// writes these values over Codex's. The rest pass as Codex wrote them:
// naming, reasoning, speed tiers, context and prompt text give no tool;
// shell_type, apply_patch_tool_type, web_search_tool_type and
// use_responses_lite shape a tool the thread switches off or the gate
// judges; supports_search_tool would defer MCP tools behind tool_search, and
// threadStart's bridge entry omits the deferred surface; node_repl_*,
// model_specialty, guardian and
// auto_review_model_override steer only the automatic reviewer, its model
// and prefix rules, and thread() keeps the reviewer at the user;
// auto_compact_token_limit and supports_reasoning_summary_parameter set the
// compaction point and a request parameter.
const CATALOG_TOOLS = Object.freeze({ tool_mode: null, multi_agent_version: null, experimental_supported_tools: [] });
// Keys catalog() leaves out, which Codex reads as unset: web_search_provider
// picks a search route, standalone or a search MCP server, and
// available_access_programs names OpenAI access programs, as the
// switched-off cli_daybreak and api_key_cyber_access_programs features do.
// VGS has reviewed neither.
const CATALOG_OMITTED = Object.freeze(["available_access_programs", "web_search_provider"]);
const CATALOG_KEYS = Object.freeze([...Object.keys(CATALOG_TOOLS), ...CATALOG_OMITTED, "additional_speed_tiers",
    "apply_patch_tool_type", "auto_compact_token_limit", "auto_review_model_override", "availability_nux",
    "base_instructions", "comp_hash", "context_window", "default_reasoning_level", "guardian",
    "default_reasoning_summary", "default_service_tier", "default_verbosity", "description", "display_name",
    "effective_context_window_percent", "include_apps_usage_instructions", "include_plugin_usage_instructions",
    "include_skills_usage_instructions", "input_modalities", "max_context_window", "model_messages", "model_specialty",
    "multi_agent_reasoning_effort", "node_repl_auto_review_required", "node_repl_disabled", "priority",
    "service_tiers", "shell_type", "slug", "support_verbosity", "supported_in_api", "supported_reasoning_levels",
    "supports_experimental_context", "supports_image_detail_original", "supports_reasoning_effort_updates",
    "supports_reasoning_summary_parameter", "supports_search_tool", "truncation_policy", "upgrade", "use_responses_lite", "visibility",
    "web_search_tool_type"]);
const FEATURE_PAGE = 500;
// One page of the model list; the page's choices hold fewer.
const MODEL_PAGE = 100;
const NAME = /^[A-Za-z0-9_-]{1,64}$/;
// What codex-cli 0.160.0 writes to stderr before an early exit, each with the
// word its fault names. Its log holds no other word the fault may carry.
const EXITS = Object.freeze([
    // `Error: CODEX_HOME points to "<path>", but that path does not exist` (exit 1, a run on 2026-10-13;
    // codex-cli 0.169.0's `debug models` writes the same line, a run on 2026-11-16).
    [/^Error: CODEX_HOME points to .*, but that path does not exist$/m, "home-missing"]
]);

function fail(code) { throw new Error("jarvis: brain=codex-" + code); }
function plain(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function string(value) { return typeof value === "string"; }
function nullable(value) { return value === undefined || value === null ? null : string(value) ? value : fail("message"); }
function validId(id) { return string(id) || Number.isSafeInteger(id); }

/** @typedef {{command: string, args: readonly string[], env: Readonly<Record<string, string>>}} Launch */

function request(id, method, params) { return { id, method, params }; }

/** The handshake's first request. */
function initialize(id) { return request(id, "initialize", { clientInfo: { ...CLIENT } }); }

/** The notification that ends initialization. */
function initialized() { return { method: "initialized" }; }

/** Read the effective configuration as the thread's working directory sees it. */
function configRead(id, cwd) { return request(id, "config/read", { cwd, includeLayers: false }); }

/**
 * Start the conversation's ephemeral thread. foreign names the user's own MCP
 * servers, each switched off; bridge is the tool bridge's launch contract,
 * or null for a thread with no tools. The bridge token travels only here, on
 * the program's stdin, never in argv. model and effort are each "" for the
 * program's own; effort is the `model_reasoning_effort` configuration key.
 * @param {{cwd: string, model: string, effort: string, instructions: string, foreign: string[], bridge: Launch|null}} value
 */
function threadStart(id, { cwd, model, effort, instructions, foreign, bridge }) {
    if (foreign.includes(SERVER)) fail("mcp-name");
    const servers = Object.fromEntries(foreign.map(name => [name, { enabled: false }]));
    // A model with supports_search_tool, every bundled one at codex-cli
    // 0.171.0, loses an MCP tool's direct exposure while its surfaces still
    // hold "deferred" (codex-rs/core/src/tools/spec_plan.rs at rust-v0.171.0),
    // and a deferred tool is absent from the model's initial tool list.
    // omit_tools_from (codex-rs/config/src/mcp_types.rs) drops that surface,
    // so the bridge's tools stay direct.
    if (bridge !== null) servers[SERVER] = { command: bridge.command, args: [...bridge.args], env: { ...bridge.env },
        omit_tools_from: ["deferred"] };
    const params = { cwd, approvalPolicy: "untrusted", approvalsReviewer: "user", sandbox: "read-only",
        ephemeral: true, baseInstructions: instructions,
        config: { features: Object.fromEntries(FEATURES_OFF.map(name => [name, false])), web_search: "disabled",
            tools: { experimental_request_user_input: { enabled: false } }, mcp_servers: servers } };
    if (model !== "") params.model = model;
    if (effort !== "") params.config.model_reasoning_effort = effort;
    return request(id, "thread/start", params);
}

/** List the models the account's picker offers, in one page. */
function modelList(id) { return request(id, "model/list", { limit: MODEL_PAGE }); }

/** List the started thread's effective features in one page. */
function featureList(id, threadId) { return request(id, "experimentalFeature/list", { threadId, limit: FEATURE_PAGE }); }

/** One user turn of plain text. */
function turnStart(id, threadId, text) {
    return request(id, "turn/start", { threadId, input: [{ type: "text", text, text_elements: [] }] });
}

function turnInterrupt(id, threadId, turnId) { return request(id, "turn/interrupt", { threadId, turnId }); }

/**
 * The answer to a narrowed server request. admitted is the gate's answer;
 * a permissions request is answered with no grant, and an unsupported method
 * with a JSON-RPC error.
 */
function answer(id, value, admitted) {
    switch (value.kind) {
    case "file-change": case "command": return { id, result: { decision: admitted ? "accept" : "decline" } };
    case "permissions":
        if (admitted) fail("permissions-admitted");
        return { id, result: { permissions: {}, scope: "turn" } };
    case "elicitation": return { id, result: admitted ? { action: "accept", content: {} } : { action: "decline", content: null } };
    case "unsupported": return { id, error: { code: -32601, message: "Method not found" } };
    default: return fail("request-kind");
    }
}

/** The user's MCP server names from a config/read result. Values are dropped. */
function servers(result) {
    if (!plain(result) || !plain(result.config)) fail("config");
    const table = result.config.mcp_servers ?? {};
    if (!plain(table)) fail("config");
    const names = Object.keys(table);
    if (!names.every(name => NAME.test(name))) fail("mcp-name");
    return names;
}

/** The started thread's id, after its reply proves the lockdown took effect. */
function thread(result) {
    if (!plain(result) || !plain(result.thread) || !string(result.thread.id) || result.thread.id === "") fail("thread");
    if (result.approvalPolicy !== "untrusted" || result.approvalsReviewer !== "user"
            || !plain(result.sandbox) || result.sandbox.type !== "readOnly" || result.sandbox.networkAccess === true)
        fail("lockdown");
    return result.thread.id;
}

/** Refuse a thread whose enabled features name one this table has not judged. */
function features(result) {
    if (!plain(result) || !Array.isArray(result.data) || result.data.length === 0) fail("features");
    if (result.nextCursor !== undefined && result.nextCursor !== null) fail("feature-page");
    for (const feature of result.data) {
        if (!plain(feature) || !string(feature.name) || typeof feature.enabled !== "boolean") fail("features");
        if (feature.enabled && !FEATURES_ENABLED.includes(feature.name))
            fail("feature name=" + (NAME.test(feature.name) ? feature.name : "invalid"));
    }
}

/**
 * The catalog the program starts with, as JSON text, from the text of
 * `codex debug models`: each entry with CATALOG_TOOLS written over Codex's
 * values and CATALOG_OMITTED left out. Refuses an unreadable catalog, an
 * empty one and an entry key CATALOG_KEYS has not judged, by name.
 */
function catalog(text) {
    let value;
    try { value = JSON.parse(text); } catch { fail("catalog json"); }
    if (!plain(value) || !Object.keys(value).every(key => key === "models") || !Array.isArray(value.models)) fail("catalog shape");
    if (value.models.length === 0) fail("catalog empty");
    const models = value.models.map(entry => {
        if (!plain(entry)) fail("catalog shape");
        for (const key of Object.keys(entry))
            if (!CATALOG_KEYS.includes(key)) fail("catalog name=" + (NAME.test(key) ? key : "invalid"));
        const kept = Object.fromEntries(Object.entries(entry).filter(([key]) => !CATALOG_OMITTED.includes(key)));
        return { ...kept, ...CATALOG_TOOLS };
    });
    return JSON.stringify({ models });
}

/**
 * A model/list result's models, for Harness.offers: value is the name
 * thread/start takes, efforts the model's reasoning efforts, effort the one
 * it names as its default, and own marks the program's default model. Codex
 * 0.160.0 listed seven models, gpt-6.1-sol the default at effort low (a run
 * on 2026-10-09).
 */
function models(result) {
    if (!plain(result) || !Array.isArray(result.data)) fail("model-list");
    return result.data.map(entry => {
        if (!plain(entry) || !string(entry.model) || !string(entry.displayName) || typeof entry.isDefault !== "boolean"
                || !string(entry.defaultReasoningEffort) || !Array.isArray(entry.supportedReasoningEfforts)
                || !entry.supportedReasoningEfforts.every(option => plain(option) && string(option.reasoningEffort)))
            fail("model-list");
        return { value: entry.model, label: entry.displayName, effort: entry.defaultReasoningEffort,
            efforts: entry.supportedReasoningEfforts.map(option => option.reasoningEffort), own: entry.isDefault };
    });
}

function turnId(result) {
    if (!plain(result) || !plain(result.turn) || !string(result.turn.id) || result.turn.id === "") fail("turn");
    return result.turn.id;
}

function item(value) {
    if (!plain(value) || !string(value.type) || !string(value.id)) fail("item");
    switch (value.type) {
    case "agentMessage":
        if (!string(value.text)) fail("item");
        return { kind: "message", id: value.id, text: value.text };
    case "fileChange": {
        if (!Array.isArray(value.changes) || value.changes.length === 0
                || !["inProgress", "completed", "failed", "declined"].includes(value.status)) fail("item");
        const changes = value.changes.map(change => {
            if (!plain(change) || !string(change.path) || !string(change.diff) || !plain(change.kind)
                    || !["add", "delete", "update"].includes(change.kind.type)) fail("item");
            const movePath = change.kind.type === "update" ? nullable(change.kind.move_path) : null;
            return { path: change.path, change: change.kind.type, movePath, diff: change.diff };
        });
        return { kind: "file-change", id: value.id, changes, status: value.status };
    }
    case "commandExecution":
        if (!string(value.command) || !string(value.cwd)
                || !["inProgress", "completed", "failed", "declined"].includes(value.status)) fail("item");
        return { kind: "command", id: value.id, command: value.command, cwd: value.cwd, status: value.status };
    case "mcpToolCall":
        if (!string(value.server) || !string(value.tool) || !["inProgress", "completed", "failed"].includes(value.status))
            fail("item");
        return { kind: "mcp", id: value.id, server: value.server, tool: value.tool, status: value.status };
    default: return { kind: "other", id: value.id, type: value.type };
    }
}

function scope(params) {
    if (!plain(params) || !string(params.threadId) || !string(params.turnId)) fail("message");
    return { threadId: params.threadId, turnId: params.turnId };
}

// CodexErrorInfo forwards HTTP status only on these structured variants.
// Other variants and null carry no status; message/additionalDetails are
// provider text and never become a cause.
// https://github.com/openai/codex/blob/df82e2fe0ab2757fa676927d2ade4deea437df72/codex-rs/app-server-protocol/schema/typescript/v2/CodexErrorInfo.ts
function httpStatus(error) {
    const info = error?.codexErrorInfo;
    if (!plain(info)) return null;
    const detail = info.httpConnectionFailed ?? info.responseStreamConnectionFailed
        ?? info.responseStreamDisconnected ?? info.responseTooManyFailedAttempts;
    const status = detail?.httpStatusCode;
    return Number.isSafeInteger(status) && status >= 100 && status <= 599 ? status : null;
}

function notification(method, params) {
    switch (method) {
    case "turn/started": case "turn/completed": {
        if (!plain(params) || !string(params.threadId) || !plain(params.turn) || !string(params.turn.id)) fail("message");
        if (method === "turn/started") return { kind: "turn-started", threadId: params.threadId, turnId: params.turn.id };
        const status = params.turn.status;
        if (!["completed", "interrupted", "failed"].includes(status)) fail("turn-status");
        const error = params.turn.error;
        if (error !== undefined && error !== null && (!plain(error) || !string(error.message))) fail("message");
        return { kind: "turn-completed", threadId: params.threadId, turnId: params.turn.id, status, httpStatus: httpStatus(error) };
    }
    case "item/started": case "item/completed":
        return { kind: method === "item/started" ? "item-started" : "item-completed", ...scope(params), item: item(params.item) };
    case "item/agentMessage/delta":
        if (!string(params?.delta) || !string(params.itemId)) fail("message");
        return { kind: "delta", ...scope(params), itemId: params.itemId, delta: params.delta };
    case "error":
        if (!plain(params?.error) || !string(params.error.message) || typeof params.willRetry !== "boolean") fail("message");
        return { kind: "error", ...scope(params), willRetry: params.willRetry };
    default: return { kind: "other", method };
    }
}

function serverRequest(method, params) {
    switch (method) {
    case "item/fileChange/requestApproval": case "item/commandExecution/requestApproval":
    case "item/permissions/requestApproval": {
        const where = scope(params);
        if (!string(params.itemId)) fail("message");
        if (method === "item/fileChange/requestApproval") return { kind: "file-change", ...where, itemId: params.itemId };
        if (method === "item/permissions/requestApproval") return { kind: "permissions", ...where, itemId: params.itemId };
        return { kind: "command", ...where, itemId: params.itemId, command: nullable(params.command), cwd: nullable(params.cwd) };
    }
    case "mcpServer/elicitation/request":
        if (!plain(params) || !string(params.threadId) || !string(params.serverName)) fail("message");
        // Codex asks before each MCP tool call; the bridge routes the call itself.
        return { kind: "elicitation", threadId: params.threadId, server: params.serverName,
            toolCall: params.mode === "form" && plain(params._meta) && params._meta.codex_approval_kind === "mcp_tool_call" };
    default: return { kind: "unsupported", method };
    }
}

/**
 * The keyed word for an exit, from the end of the program's stderr and
 * whether it wrote a line, the app server's first protocol line or the
 * catalog read's output: a known Codex failure, `not-started`
 * for a program that ended before its first line, as a launcher in front of
 * Codex that refused does, or null.
 */
function cause(log, spoke) {
    const known = EXITS.find(([pattern]) => pattern.test(log));
    return known !== undefined ? known[1] : spoke ? null : "not-started";
}

/**
 * Narrow one line the program wrote: a response, a failure, a notification
 * or a server request. An unreadable line throws a keyed error.
 */
function accept(line) {
    if (Buffer.byteLength(line) + 1 > LINE_BYTES) fail("line-size");
    let message;
    try { message = JSON.parse(line); } catch { fail("json"); }
    if (!plain(message)) fail("message");
    const hasId = Object.hasOwn(message, "id");
    if (hasId && !validId(message.id)) fail("message");
    if (string(message.method)) {
        const params = message.params;
        return hasId ? { kind: "request", id: message.id, request: serverRequest(message.method, params) }
            : { kind: "notification", event: notification(message.method, params) };
    }
    if (!hasId) fail("message");
    if (Object.hasOwn(message, "result")) return { kind: "response", id: message.id, result: message.result };
    if (plain(message.error) && Number.isSafeInteger(message.error.code) && string(message.error.message))
        return { kind: "failure", id: message.id, code: message.error.code };
    return fail("message");
}

/**
 * The gate's typed call for an approval request, from the item the program
 * announced. A file change lists each path by the role Denied judges it in.
 */
function proposal(value, announced) {
    switch (value.kind) {
    case "file-change": {
        if (announced === null || announced.kind !== "file-change") return { tool: "harness.files", arguments: {} };
        const args = { write: [], move: [], remove: [], diff: "" };
        for (const change of announced.changes) {
            if (change.change === "add") args.write.push(change.path);
            else if (change.change === "delete") args.remove.push(change.path);
            else if (change.movePath === null) args.write.push(change.path);
            else { args.move.push(change.path); args.write.push(change.movePath); }
            args.diff += change.path + "\n" + change.diff + (change.diff.endsWith("\n") ? "" : "\n");
        }
        return { tool: "harness.files", arguments: args };
    }
    case "command":
        return { tool: "harness.command", arguments: { command: value.command ?? announced?.command ?? "",
            cwd: value.cwd ?? announced?.cwd ?? "" } };
    case "permissions": return { tool: "harness.permissions", arguments: {} };
    default: return fail("request-kind");
    }
}

module.exports = { LINE_BYTES, SERVER, FEATURES_OFF, FEATURES_ENABLED, initialize, initialized, configRead,
    threadStart, modelList, featureList, turnStart, turnInterrupt, answer, servers, thread, features, catalog, models, turnId, accept,
    proposal, cause };
