// The provider table: wire brain drivers and the cloud voices. One row
// per provider names its driver, endpoint, key need, documented retention and
// no-store request fields, each from its vendor's documentation. Contract:
// docs/architecture/jarvis.md § Adapters.
"use strict";
const Net = require("./net.js");

const LOCAL = Object.freeze({ text: "A loopback server: nothing leaves the machine.", source: null });
// The Gemini API's terms, which cover its chat endpoint and its Live API.
const GEMINI_TERMS = Object.freeze({ text: "Paid tier: logged for a limited period to detect abuse, not used to improve products. Unpaid quota: used to improve products, and human reviewers may read it.",
    source: "https://ai.google.dev/gemini-api/terms" });

// key: "required" for a cloud account, "optional" where the server's operator
// may switch authentication on, "none" for a harness program that owns its
// login. noStore: request fields that keep the
// provider from storing the exchange, merged into every request body.
// images: the endpoint documents image content parts with base64 data.
const ROWS = Object.freeze({
    anthropic: { driver: "anthropic-messages", base: "https://api.anthropic.com/v1", key: "required", images: true,
        noStore: null,
        retention: { text: "API inputs and outputs are deleted within 30 days, with policy, legal, agreed-retention and covered-model exceptions. Zero data retention requires an agreement.",
            source: "https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data" } },
    openai: { driver: "openai-chat", base: "https://api.openai.com/v1", key: "required", images: true,
        noStore: { store: false },
        retention: { text: "Abuse monitoring logs are kept up to 30 days; API data is not used for training unless the account opts in.",
            source: "https://developers.openai.com/api/docs/guides/your-data" } },
    // The duplex voice engine. base is its WebSocket endpoint; a key stored for
    // the openai row's origin serves it, since both handshake at that origin.
    // The address pins the model, which session.update cannot change; this is
    // the one place the shell names it. It is the model Talk's session uses:
    // ~/dev/talk/docs/talk-api.md:58. noStore keeps the session out of
    // OpenAI's Traces dashboard.
    "openai-realtime": { driver: "openai-realtime", base: "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1", key: "required", images: false,
        noStore: { tracing: null },
        retention: { text: "Abuse monitoring logs are kept up to 30 days; realtime sessions are not used for training, and OpenAI keeps no conversation state after the session.",
            source: "https://developers.openai.com/api/docs/guides/your-data" } },
    openrouter: { driver: "openai-chat", base: "https://openrouter.ai/api/v1", key: "required", images: true,
        noStore: { provider: { data_collection: "deny" } },
        retention: { text: "OpenRouter stores no prompts or responses unless the account opts in; it stores request metadata. Routing is limited to providers that do not collect user data.",
            source: "https://openrouter.ai/docs/guides/privacy/data-collection" } },
    groq: { driver: "openai-chat", base: "https://api.groq.com/openai/v1", key: "required", images: true,
        noStore: null,
        retention: { text: "Not retained by default; inputs and outputs may be logged up to 30 days to troubleshoot reliability or investigate abuse. Zero data retention is an account setting.",
            source: "https://console.groq.com/docs/your-data" } },
    cerebras: { driver: "openai-chat", base: "https://api.cerebras.ai/v1", key: "required", images: true,
        noStore: null,
        retention: { text: "Cerebras does not retain inputs and outputs of its inference services.",
            source: "https://www.cerebras.ai/privacy-policy" } },
    mistral: { driver: "openai-chat", base: "https://api.mistral.ai/v1", key: "required", images: true,
        noStore: null,
        retention: { text: "Input and output are kept 30 rolling days to monitor abuse unless zero data retention is activated for the account.",
            source: "https://legal.mistral.ai/terms/privacy-policy/" } },
    gemini: { driver: "openai-chat", base: "https://generativelanguage.googleapis.com/v1beta/openai", key: "required", images: true,
        noStore: null, retention: GEMINI_TERMS },
    // The second duplex voice engine, Gemini Live. base is its WebSocket
    // endpoint with no query: the key travels in its header, and a key
    // stored for the gemini row's origin serves it, since both handshake at
    // that origin. model is the one place the shell names its model, which
    // the session's setup message carries: the models page's default Live
    // API model, read 2026-10-12. Google documents no field that keeps a
    // Live session from being stored.
    "gemini-live": { driver: "gemini-live", base: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent",
        key: "required", images: false, model: "gemini-3.8-live", noStore: null, retention: GEMINI_TERMS },
    // The ElevenLabs voice, which speaks the released sentences of a reply:
    // no brain runs on it. model is the one place the shell names its text
    // to speech model, which each request body carries: eleven_flash_v2_5,
    // the model ElevenLabs's models page documents for real-time use, read
    // 2026-10-12. Zero retention (enable_logging=false) is for enterprise
    // accounts only, so no request field keeps the exchange unstored.
    elevenlabs: { driver: "elevenlabs", base: "https://api.elevenlabs.io", key: "required", images: false,
        model: "eleven_flash_v2_5", noStore: null,
        retention: { text: "ElevenLabs keeps request history, and may use it to improve its models unless the account turns that off under Terms and privacy, Data use.",
            source: "https://elevenlabs.io/docs/help-center/legal/is-my-data-used-to-improve-eleven-labs-ai-models" } },
    ollama: { driver: "openai-chat", base: "http://127.0.0.1:11434/v1", key: "optional", images: true,
        noStore: null, retention: LOCAL },
    "llama-server": { driver: "openai-chat", base: "http://127.0.0.1:8080/v1", key: "optional", images: true,
        noStore: null, retention: LOCAL },
    "lm-studio": { driver: "openai-chat", base: "http://127.0.0.1:1234/v1", key: "optional", images: true,
        noStore: null, retention: LOCAL },
    // The Codex harness: the vendor's program owns its login and sockets.
    // base is the release recipient's origin, chatgpt_base_url's host in
    // codex-cli 0.160.0; Jarvis opens no socket to it.
    codex: { driver: "codex-app-server", base: "https://chatgpt.com", key: "none", images: false,
        noStore: null, retention: { text: "Set by the OpenAI account Codex signs in with; Jarvis cannot read its data controls.", source: null } },
    // The Copilot ACP harness: the vendor's program owns its login and
    // sockets. base is the release recipient's origin; Jarvis opens no
    // socket to it.
    copilot: { driver: "copilot-acp", base: "https://api.githubcopilot.com", key: "none", images: false,
        noStore: null, retention: { text: "Set by the GitHub account Copilot signs in with; Copilot keeps each Jarvis conversation in its own session history in the account folder.", source: null } },
    // The Pi harness: the user's own Pi setup owns its providers and their
    // sockets, and Jarvis cannot see which one a turn reaches, so base is a
    // non-loopback origin naming Pi: release always judges Pi as a cloud
    // recipient. Jarvis opens no socket to it.
    pi: { driver: "pi-rpc", base: "https://pi.dev", key: "none", images: false,
        noStore: null, retention: { text: "Set by the providers your own Pi setup uses; Jarvis keeps Pi from saving the conversation.", source: null } },
    // The Claude Code harness: the vendor's program owns its login and
    // sockets. base is the release recipient's origin, the API origin Claude
    // Code's account Verify names; Jarvis opens no socket to it. The program
    // hands an MCP result's image block to its model: in one live turn on
    // 2026-11-03 (VGS-2182), Claude Code 2.1.317 on claude-sonnet-5-5, run
    // with ClaudeCode.js's flags, answered a Mcp.content image of a green
    // triangle on dark blue, with no text naming either, by naming both.
    claude: { driver: "claude-code", base: "https://api.anthropic.com", key: "none", images: true,
        noStore: null, retention: { text: "Set by the Anthropic account Claude Code signs in with; Jarvis cannot read its data controls.", source: null } },
    // A user's own server: no documentation states its image support or
    // retention, so images go to OCR text and the operator owns retention.
    custom: { driver: "openai-chat", base: null, key: "optional", images: false,
        noStore: null, retention: { text: "Set by the server's operator.", source: null } }
});

const rows = new WeakSet();

function fail(code) { throw new Error("jarvis: provider=" + code); }

function deepFreeze(value) {
    if (value !== null && typeof value === "object") {
        for (const child of Object.values(value)) deepFreeze(child);
        Object.freeze(value);
    }
    return value;
}

/**
 * select(id, customBaseUrl) returns a frozen row with its resolved base, for
 * drivers to accept through assertRow. customBaseUrl is the brain settings'
 * customBaseUrl and is read only for the custom row: an HTTP or HTTPS URL
 * without a query, normalized by net.endpoint and stripped of a final slash.
 */
function select(id, customBaseUrl = "") {
    if (typeof id !== "string" || !Object.hasOwn(ROWS, id)) fail("unknown");
    const row = ROWS[id];
    let base = row.base;
    if (base === null) {
        let target;
        try { target = Net.endpoint(customBaseUrl); } catch { fail("custom-base"); }
        const url = new URL(target.url);
        // A bare "?" leaves search empty but still starts a query.
        if (target.websocket || url.search !== "" || url.href.endsWith("?")) fail("custom-base");
        base = url.href.replace(/\/$/, "");
    }
    const result = deepFreeze(structuredClone({ id, ...row, base }));
    rows.add(result);
    return result;
}

function assertRow(value) {
    if (!rows.has(value)) fail("row");
}

module.exports = { select, assertRow };
