// One hosted lookup under an OpenAI key already in the frozen conversation.
// The engine owns release/grants and net owns every socket; this executor
// owns only its cancellable request, never a provider connection or key cache.
"use strict";
const Net = require("./net.js");
const Policy = require("./Policy.js");
const { setImmediate } = require("node:timers/promises");

// Owner decision on VGS-2445: one search model, no fallback. The selected
// brain proposes the call even when its own model is not an OpenAI model.
const MODEL = "gpt-4.1-mini";
const URL = "https://api.openai.com/v1/responses";
const RESPONSE_BYTES = 1024 * 1024;
const TIMEOUT_MS = 60000;
const plain = value => value !== null && typeof value === "object" && !Array.isArray(value);
function fail(key) { throw new Error("jarvis: search=" + key); }

async function requireAuthority(check, signal) {
    // SessionRunner defers events during an effect drain. Node's immediate
    // runs after I/O callbacks, so queued lease/lock changes and deadlines
    // are reduced before a key lookup or delivery can start.
    // https://nodejs.org/docs/latest-v22.x/api/timers.html, read 2026-11-10.
    await setImmediate(undefined, { signal });
    if (check().kind !== "allow") fail("stale-action");
}

/** Only selected keyring accounts, never another remembered OpenAI key. */
function keyFor({ recipients, brain, speech }) {
    Policy.assertRecipients(recipients);
    for (const [chosen, selected] of [
        [speech?.id === "openai-realtime" ? speech : null, recipients.speech],
        [brain?.provider.id === "openai" ? brain : null, [recipients.brain]]
    ]) {
        const key = chosen?.key;
        if (key !== undefined && key !== null && key.reference.provider === "openai"
                && key.reference.origin === "https://api.openai.com"
                && selected.some(row => row.kind === "network" && row.provider === "openai"
                    && row.origin === key.reference.origin))
            return key;
    }
    return null;
}

// Responses API, read 2026-11-10:
// https://developers.openai.com/api/docs/guides/tools-web-search
// https://developers.openai.com/api/reference/resources/responses/methods/create
// One built-in call is the server-enforced maximum, not a prompt convention.
function request(query) {
    return { model: MODEL, service_tier: "default", input: query, tools: [{ type: "web_search" }], tool_choice: "required",
        max_tool_calls: 1, parallel_tool_calls: false, max_output_tokens: 2048,
        include: ["web_search_call.action.sources"], store: false };
}

function result(value) {
    if (!plain(value) || value.status !== "completed" || !Array.isArray(value.output)) fail("response-shape");
    const text = [], citations = [];
    for (const message of value.output.filter(row => row.type === "message")) {
        if (!Array.isArray(message.content)) fail("response-shape");
        for (const part of message.content) {
            if (part.type !== "output_text") continue;
            if (typeof part.text !== "string" || !Array.isArray(part.annotations)) fail("response-shape");
            text.push(part.text);
            for (const citation of part.annotations.filter(row => row.type === "url_citation")) {
                if (typeof citation.title !== "string" || typeof citation.url !== "string") fail("citation-shape");
                // Citation URLs are untrusted result data, not transport
                // targets. In particular a source's #fragment must survive.
                // The view that makes a link actionable owns its URL judge.
                citations.push({ title: citation.title, url: citation.url });
            }
        }
    }
    if (text.length === 0 || !value.output.some(row => row.type === "web_search_call" && row.status === "completed")) fail("response-shape");
    return JSON.stringify({ outcome: "completed", answer: text.join("\n"), citations });
}

function install({ router, conversation, audit, cap }) {
    let active = null, closed = false;
    const executor = {
        commands: [], timeoutMs: TIMEOUT_MS, cancellable: true,
        available: () => {
            const selected = conversation();
            return !closed && selected !== null && selected.key !== null;
        },
        start(call, done, authorize, origin) {
            const selected = conversation();
            if (closed || active !== null || selected === null || selected.key === null) {
                done({ outcome: "failed", content: "failed: Web search is not available in this conversation." });
                return;
            }
            const operation = { stop: new AbortController() };
            active = operation;
            const finished = () => {
                if (active === operation) active = null;
            };
            void run(selected, call.args.query, origin.labels, authorize, operation).then(content => {
                finished();
                return content;
            }, error => { finished(); throw error; }).then(
                content => done({ outcome: "completed", content }),
                error => done({ outcome: "failed", content: error.message.startsWith("failed:") ? error.message
                    : "failed: Web search could not finish. " + (/^jarvis: (?:search|net)=[a-z-]+$/.test(error.message) ? error.message : "search=request") })
            );
        },
        cancel() { active?.stop.abort(); }
    };
    async function run(selected, query, labels, authorize, operation) {
        const limit = cap();
        let usage;
        try { usage = audit.usageWindow(); } catch { fail("usage-read"); }
        if (!usage.complete) throw new Error("failed: Web search cannot read the full spend record.");
        if (!Number.isFinite(limit) || limit < 0) fail("cap");
        if (usage.total.costUsd >= limit)
            throw new Error("failed: Web search reached the weekly OpenAI spend cap of $" + limit + ". Voice still works.");
        const item = Policy.item(JSON.stringify(request(query)), labels);
        const released = selected.release(item);
        if (released.kind !== "send") fail("release");
        Net.assertKeyTarget(URL, selected.key.reference.origin);
        await requireAuthority(authorize, operation.stop.signal);
        const secret = selected.key.secrets.lookup(selected.key.reference);
        let answer, noted = false;
        const received = value => { noted = true; note({ account: selected.key.reference.account, ...value }); };
        try {
            const waiting = selected.transfer(item, async () => {
                // Both the key helper and the pre-transfer audit can block.
                await requireAuthority(authorize, operation.stop.signal);
                try {
                    // The door builds its headers synchronously. Clear the
                    // Buffer after that construction, not the network wait.
                    return selected.net.request(item, { url: URL,
                        headers: { "content-type": "application/json" }, signal: operation.stop.signal,
                        key: { origin: selected.key.reference.origin, header: "authorization", prefix: "Bearer ", value: secret.toString("utf8") } },
                    selected.grants());
                } finally { secret.fill(0); }
            });
            answer = await waiting;
            if (answer.kind !== "response") fail("release");
            const response = answer.response;
            if (response.status !== 200) {
                await response.body?.cancel();
                // A failed HTTP response has no readable usage. Keep its
                // unknown cost, without opening the provider's error body.
                received({ call: "search", model: MODEL });
                throw new Error("failed: " + (response.status === 429
                    ? "OpenAI refused web search for a rate or spend limit." : "OpenAI refused web search.") + " HTTP " + response.status + ".");
            }
            const reader = response.body.getReader(), chunks = [];
            let size = 0;
            for (;;) {
                const read = await reader.read();
                if (read.done) break;
                size += read.value.byteLength;
                if (size > RESPONSE_BYTES) { await reader.cancel(); fail("response-size"); }
                chunks.push(read.value);
            }
            let value;
            try { value = JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch { fail("response-json"); }
            // Hosted tool usage is separate from base-model usage. The
            // documented count excludes discounted searches and open_page;
            // output actions are not a billing counter. Missing means unknown.
            // https://developers.openai.com/api/reference/resources/responses/methods/create
            // tool_usage, read 2026-11-10.
            received({ call: "search", model: MODEL, tier: value?.service_tier, usage: value?.usage,
                searches: value?.tool_usage?.web_search?.num_requests ?? null });
            return result(value);
        } finally {
            secret.fill(0);
            try {
                if (answer?.kind === "response" && !noted) received({ call: "search", model: MODEL });
            } finally { answer?.close?.(); }
        }
    }
    function note(value) {
        if (audit.usage(value).kind !== "recorded") fail("audit-write");
    }
    router.register("web", executor);
    return { close() { closed = true; active?.stop.abort(); } };
}

module.exports = { install, keyFor };
