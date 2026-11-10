// OpenAI usage is data in the existing audit, never another store. Unknown
// models or incomplete provider counts stay unpriced, not free.
"use strict";

// USD, standard service tier. Source, read 2026-11-10:
// https://developers.openai.com/api/docs/pricing
// Token rates are per million. Non-preview web_search adds its call fee
// and, for gpt-4.1-mini, a fixed 8,000 search-content input tokens per search.
const PRICES = Object.freeze({
    "gpt-realtime-2.1": { text: [4, 0.4, 24], audio: [32, 0.4, 64], image: [5, 0.5, 0] },
    "gpt-live-transcribe": { minute: 0.017 },
    "gpt-4.1-mini": { text: [0.4, 0.1, 1.6], search: 0.01, searchTokens: 8000 }
});
const TOKEN_FIELDS = Object.freeze(["input", "output", "cached", "inputText", "inputAudio", "inputImage",
    "cachedText", "cachedAudio", "cachedImage", "outputText", "outputAudio", "searchContent"]);
const CALLS = Object.freeze({ realtime: "voice", transcription: "voice", search: "web.search", chat: "brain", verify: "account.verify" });
// "default" is standard pricing. Responses/Chat may report a different
// actual mode from the requested one; do not price it with standard rates.
// https://developers.openai.com/api/reference/resources/responses/methods/create
// service_tier, read 2026-11-10.
const TIERS = Object.freeze(["auto", "default", "flex", "scale", "priority", "fast", "ultrafast", "unknown"]);
const whole = value => Number.isSafeInteger(value) && value >= 0;
const plain = value => value !== null && typeof value === "object" && !Array.isArray(value);

function counts(call, usage, searches) {
    if (!plain(usage)) return null;
    if (call === "transcription" && usage.type === "duration")
        return typeof usage.seconds === "number" && Number.isFinite(usage.seconds) && usage.seconds >= 0
            ? { seconds: usage.seconds } : null;
    const chat = call === "chat" || call === "verify";
    const input = chat ? usage.prompt_tokens : usage.input_tokens;
    const output = chat ? usage.completion_tokens : usage.output_tokens;
    if (!whole(input) || !whole(output)) return null;
    if (call === "realtime") {
        const detail = usage.input_token_details, out = usage.output_token_details;
        if (!plain(detail) || !plain(out)) return { input, output };
        const cached = detail.cached_tokens_details ?? {};
        const result = { input, output, cached: detail.cached_tokens ?? 0,
            inputText: detail.text_tokens ?? 0, inputAudio: detail.audio_tokens ?? 0, inputImage: detail.image_tokens ?? 0,
            cachedText: cached.text_tokens ?? 0, cachedAudio: cached.audio_tokens ?? 0, cachedImage: cached.image_tokens ?? 0,
            outputText: out.text_tokens ?? 0, outputAudio: out.audio_tokens ?? 0 };
        if (!Object.values(result).every(whole) || result.inputText + result.inputAudio + result.inputImage !== input
                || result.outputText + result.outputAudio !== output
                || result.cachedText + result.cachedAudio + result.cachedImage !== result.cached
                || ["Text", "Audio", "Image"].some(kind => result["cached" + kind] > result["input" + kind])) return { input, output };
        return result;
    }
    if (call === "transcription") {
        const detail = usage.input_token_details ?? {};
        return { input, output,
            ...(whole(detail.text_tokens) ? { inputText: detail.text_tokens } : {}),
            ...(whole(detail.audio_tokens) ? { inputAudio: detail.audio_tokens } : {}) };
    }
    const detail = (chat ? usage.prompt_tokens_details : usage.input_tokens_details) ?? {};
    const cached = detail.cached_tokens ?? 0;
    if (!whole(cached) || cached > input) return { input, output };
    return { input, output, cached, inputText: input, outputText: output, cachedText: cached,
        ...(call === "search" && whole(searches) ? { searchContent: searches * PRICES["gpt-4.1-mini"].searchTokens } : {}) };
}

/** Project only numeric usage fields; provider text never enters the row. */
function record({ call, model, usage, searches = call === "search" ? null : 0, account = "unknown",
    tier = call === "realtime" || call === "transcription" ? "default" : "unknown" }) {
    if (!Object.hasOwn(CALLS, call)) throw new Error("jarvis: usage=call");
    const name = typeof model === "string" && /^[A-Za-z0-9._-]{1,100}$/.test(model) ? model : "unknown";
    const tokens = counts(call, usage, searches);
    const identity = typeof account === "string" && /^[^\x00-\x1f\x7f]{1,80}$/.test(account) ? account : "unknown";
    const row = { call, tool: CALLS[call], model: name, account: identity, tier: TIERS.includes(tier) ? tier : "unknown",
        tokens, searches: whole(searches) ? searches : null,
        pricing: "unpriced", costUsd: null };
    const price = Object.hasOwn(PRICES, name) ? PRICES[name] : null;
    if (tokens === null || price === null || row.searches === null || row.tier !== "default") return row;
    let cost;
    if (call === "transcription") {
        if (price.minute === undefined || tokens.seconds === undefined) return row;
        cost = tokens.seconds * price.minute / 60;
    } else {
        if (tokens.cached === undefined || tokens.inputText === undefined) return row;
        cost = 0;
        for (const kind of ["Text", "Audio", "Image"]) {
            const input = tokens["input" + kind] ?? 0, cached = tokens["cached" + kind] ?? 0, output = tokens["output" + kind] ?? 0;
            const rates = price[kind.toLowerCase()];
            if (rates === undefined) { if (input + output !== 0) return row; else continue; }
            cost += ((input - cached) * rates[0] + cached * rates[1] + output * rates[2]) / 1e6;
        }
        if (call === "search") {
            if (price.search === undefined) return row;
            cost += searches * price.search + tokens.searchContent * price.text[0] / 1e6;
        }
    }
    return { ...row, pricing: "priced", costUsd: cost };
}

function stored(row) {
    if (!Object.hasOwn(CALLS, row.call) || row.tool !== CALLS[row.call] || typeof row.model !== "string" || typeof row.account !== "string" || !TIERS.includes(row.tier)
            || !["priced", "unpriced"].includes(row.pricing)
            || (row.pricing === "unpriced" ? row.costUsd !== null : typeof row.costUsd !== "number" || !Number.isFinite(row.costUsd) || row.costUsd < 0)
            || (row.searches !== null && !whole(row.searches))
            || (row.tokens !== null && (!plain(row.tokens) || Object.entries(row.tokens).some(([key, value]) =>
                key === "seconds" ? typeof value !== "number" || !Number.isFinite(value) || value < 0 : !TOKEN_FIELDS.includes(key) || !whole(value)))))
        throw new Error("jarvis: usage=stored");
    return { time: row.time, kind: "usage", call: row.call, tool: row.tool, model: row.model, account: row.account, tier: row.tier,
        tokens: row.tokens === null ? null : { ...row.tokens }, searches: row.searches, pricing: row.pricing, costUsd: row.costUsd };
}

/** Report actual recorded rows, never invent a price for an unpriced call. */
function summarize(rows) {
    const group = () => ({ calls: 0, priced: 0, unpriced: 0, costUsd: 0, tokens: {}, searches: 0 });
    const total = group(), byCall = {}, byTool = {}, byAccount = Object.create(null);
    for (const row of rows) {
        for (const result of [total, byCall[row.call] ??= group(), byTool[row.tool] ??= group(), byAccount[row.account] ??= group()]) {
            result.calls++;
            result[row.pricing]++;
            result.costUsd += row.costUsd ?? 0;
            result.searches += row.searches ?? 0;
            for (const [kind, count] of Object.entries(row.tokens ?? {})) result.tokens[kind] = (result.tokens[kind] ?? 0) + count;
        }
    }
    return { total, byCall, byTool, byAccount };
}

module.exports = { record, stored, summarize };
