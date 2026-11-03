#!/usr/bin/env node
// The provider table against its vendors' documentation. No request is made.
"use strict";
const { assert, fs, path, backend, world, control } = require("./fixtures/jarvis-voice/assertions.js");
const Providers = require(path.join(backend, "Providers.js"));
const Net = require(path.join(backend, "net.js"));

// Pinned independently of the table: base URL, key need, image input and
// no-store fields per documented provider. Rows the table adds beyond these
// are not detected here; the brain suite reaches each of these rows.
const documented = {
    openai: ["https://api.openai.com/v1", "required", true, { store: false }],
    openrouter: ["https://openrouter.ai/api/v1", "required", true, { provider: { data_collection: "deny" } }],
    groq: ["https://api.groq.com/openai/v1", "required", true, null],
    cerebras: ["https://api.cerebras.ai/v1", "required", true, null],
    mistral: ["https://api.mistral.ai/v1", "required", true, null],
    gemini: ["https://generativelanguage.googleapis.com/v1beta/openai", "required", true, null],
    ollama: ["http://127.0.0.1:11434/v1", "optional", true, null],
    "llama-server": ["http://127.0.0.1:8080/v1", "optional", true, null],
    "lm-studio": ["http://127.0.0.1:1234/v1", "optional", true, null]
};
function pinned(logic) {
    for (const [id, [base, key, images, noStore]] of Object.entries(documented)) {
        const row = logic.select(id);
        assert.deepEqual([row.id, row.driver, row.base, row.key, row.images, row.noStore], [id, "openai-chat", base, key, images, noStore], id);
        assert.equal(typeof row.retention.text, "string", id);
        if (base.startsWith("https:")) assert.match(row.retention.source, /^https:\/\//, id + " cites its retention source");
        else assert.equal(row.retention.source, null, id + " is a loopback server");
        assert.ok(Object.isFrozen(row) && Object.isFrozen(row.retention), id + " is frozen");
        if (row.noStore !== null) assert.ok(Object.isFrozen(row.noStore), id + " no-store fields are frozen");
        logic.assertRow(row);
    }
    const row = logic.select("anthropic", "http://127.0.0.1:9000/v1");
    assert.deepEqual([row.id, row.driver, row.base, row.key, row.images, row.noStore],
        ["anthropic", "anthropic-messages", "https://api.anthropic.com/v1", "required", true, null]);
    assert.equal(row.retention.source, "https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data");
    assert.ok(Object.isFrozen(row) && Object.isFrozen(row.retention));
    // The address pins the model: session.update cannot change it.
    const live = logic.select("openai-realtime", "http://127.0.0.1:9000/v1");
    assert.deepEqual([live.id, live.driver, live.base, live.key, live.images, live.noStore],
        ["openai-realtime", "openai-realtime", "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1", "required", false, { tracing: null }]);
    assert.equal(live.retention.source, "https://developers.openai.com/api/docs/guides/your-data");
    assert.ok(Object.isFrozen(live) && Object.isFrozen(live.noStore));
    // The Gemini Live address carries no query: the key travels in its
    // header, and the setup message names the model this row pins.
    const gemini = logic.select("gemini-live", "http://127.0.0.1:9000/v1");
    assert.deepEqual([gemini.id, gemini.driver, gemini.base, gemini.key, gemini.images, gemini.noStore, gemini.model],
        ["gemini-live", "gemini-live", "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent",
            "required", false, null, "gemini-3.8-live"]);
    assert.equal(gemini.retention.source, "https://ai.google.dev/gemini-api/terms");
    assert.ok(Object.isFrozen(gemini) && Object.isFrozen(gemini.retention));
    // The ElevenLabs voice's row: the HTTPS origin its key travels to, and
    // the text to speech model each request body names.
    const eleven = logic.select("elevenlabs", "http://127.0.0.1:9000/v1");
    assert.deepEqual([eleven.id, eleven.driver, eleven.base, eleven.key, eleven.images, eleven.noStore, eleven.model],
        ["elevenlabs", "elevenlabs", "https://api.elevenlabs.io", "required", false, null, "eleven_flash_v2_5"]);
    assert.match(eleven.retention.source, /^https:\/\/elevenlabs\.io\/docs\//, "elevenlabs cites its retention source");
    assert.ok(Object.isFrozen(eleven) && Object.isFrozen(eleven.retention));
    // The harness rows: the program owns its login; base names the release recipient.
    const codex = logic.select("codex");
    assert.deepEqual([codex.id, codex.driver, codex.base, codex.key, codex.images, codex.noStore, codex.retention.source],
        ["codex", "codex-app-server", "https://chatgpt.com", "none", false, null, null]);
    const claude = logic.select("claude");
    assert.deepEqual([claude.id, claude.driver, claude.base, claude.key, claude.images, claude.noStore, claude.retention.source],
        ["claude", "claude-code", "https://api.anthropic.com", "none", true, null, null]);
}
pinned(Providers);

// The chained engine joins an account declaration to its brain row by id.
// Every key and local declaration has a row at the declared origin, and every
// row but custom, whose base is a setting, has a declaration.
const { PROVIDERS } = require(path.join(backend, "../AccountProviders.js"));
function joined(logic) {
    const declared = PROVIDERS.filter(row => row.kind === "key" || row.kind === "local");
    assert.ok(declared.length >= 10, "the declaration filter found the key and local rows");
    for (const row of declared) {
        let selected;
        assert.doesNotThrow(() => { selected = logic.select(row.id); }, row.id + " has a brain row");
        assert.equal(new URL(selected.base).origin, row.origin, row.id + " shares its declared origin");
    }
    for (const id of [...Object.keys(documented), "anthropic"])
        assert.ok(declared.some(row => row.id === id), id + " has an account declaration");
    // A harness declaration's origin is the one its Verify releases to, so
    // the engine's recipient for the same program must name it too.
    const harnesses = PROVIDERS.filter(row => row.kind === "cli" && row.origin !== undefined);
    assert.ok(harnesses.some(row => row.id === "claude"), "the Claude Code declaration names its origin");
    for (const row of harnesses)
        assert.equal(new URL(logic.select(row.id).base).origin, row.origin, row.id + " shares its declared origin");
    // A key added as Gemini serves the Gemini Live voice: the door lets it
    // travel to the voice's handshake origin.
    // The ElevenLabs speech key serves the voice's row at its declared origin.
    const speechKey = PROVIDERS.find(row => row.kind === "speech-key" && row.id === "elevenlabs");
    assert.ok(speechKey, "the ElevenLabs key has an account declaration");
    assert.doesNotThrow(() => Net.assertKeyTarget(logic.select("elevenlabs").base, speechKey.origin), "an ElevenLabs key serves its voice");
    const google = declared.find(row => row.id === "gemini");
    assert.doesNotThrow(() => Net.assertKeyTarget(logic.select("gemini-live").base, google.origin), "a Gemini key serves the Gemini Live voice");
}
joined(Providers);

// [customBaseUrl, resolved base or keyed refusal]. Only the custom row reads it.
const custom = [
    ["http://localhost:9000/v1/", "http://127.0.0.1:9000/v1"],
    ["https://llm.example.test/api", "https://llm.example.test/api"],
    ["https://LLM.example.test:443/", "https://llm.example.test"],
    ["http://192.0.2.1:8000/v1", "http://192.0.2.1:8000/v1"],
    ["", "custom-base"],
    [undefined, "custom-base"],
    ["ws://127.0.0.1:9000/v1", "custom-base"],
    ["http://127.0.0.1:9000/v1?key=1", "custom-base"],
    ["http://127.0.0.1:9000/v1?", "custom-base"],
    ["http://user:pass@127.0.0.1:9000/v1", "custom-base"],
    ["http://127.0.0.1:9000/v1#x", "custom-base"],
    ["file:///tmp/server", "custom-base"],
    ["not a URL", "custom-base"]
];
function resolves(logic, [value, expected]) {
    if (expected.includes("/")) {
        const row = logic.select("custom", value);
        assert.deepEqual([row.base, row.key, row.images, row.noStore, row.retention.source], [expected, "optional", false, null, null], value);
    } else assert.throws(() => logic.select("custom", value), { message: "jarvis: provider=" + expected }, String(value));
}
for (const row of custom) resolves(Providers, row);
assert.equal(Providers.select("openai", "http://127.0.0.1:9000/v1").base, "https://api.openai.com/v1", "only custom reads the setting");
for (const id of ["", "OpenAI", "xai", "constructor", "__proto__", 7])
    assert.throws(() => Providers.select(id), { message: "jarvis: provider=unknown" }, String(id));
assert.throws(() => Providers.assertRow({ ...Providers.select("openai") }), { message: "jarvis: provider=row" });
assert.throws(() => Providers.select("openai").noStore.store = true, TypeError);

let controls = 0;
// Every call through a network door is named here. Inference carries its
// provider row's noStore fields under its own test: the wire
// brain in test-jarvis-brain-openai.js (no-store), the voice engine in
// test-jarvis-live.js (no-trace) and the key check in
// test-jarvis-account-verify.js (verify-no-store). Door holders are the
// local catalog in test-jarvis-accounts.js sends a bodyless GET. Door holders
// are the names Net.create's result is assigned to; a door passed on under another
// name is not found.
// The Gemini Live and ElevenLabs rows document no such field, so their
// requests, ElevenLabs's sentences and voice list both, carry none.
const NO_STORE_SITES = ["Accounts.js:request", "Accounts.js:request", "ElevenLabs.js:request", "ElevenLabs.js:request", "GeminiLive.js:websocket", "Realtime.js:websocket", "WireBrain.js:request"];
function doorSites(sources) {
    const holders = new Set(sources.flatMap(([, text]) => [...text.matchAll(/\b(\w+) = Net\.create\(/g)].map(match => match[1])));
    assert.ok(holders.has("door") && holders.has("net"), "door holders are discovered");
    return sources.flatMap(([name, text]) => [...text.matchAll(/\b(\w+)\.(request|websocket)\(/g)]
        .filter(match => holders.has(match[1])).map(match => name + ":" + match[2])).sort();
}

// noStore reaches every provider request: each call site below is the one
// place its body is built, and each one's own test holds the merge.
const sources = fs.readdirSync(backend).filter(name => name.endsWith(".js") && name !== "net.js")
    .map(name => [name, fs.readFileSync(path.join(backend, name), "utf8")]);
assert.deepEqual(doorSites(sources), NO_STORE_SITES, "every provider request site is named with its no-store test");
assert.notDeepEqual(doorSites([...sources, ["Planted.js", "await net.request(item, options, grants);"]]), NO_STORE_SITES,
    "an unnamed door call turns the inventory red");

world("providers", root => {
    const mutants = [
        ["anthropic-driver", 'driver: "anthropic-messages"', 'driver: "openai-chat"', pinned],
        ["anthropic-base", '"https://api.anthropic.com/v1"', '"https://api.anthropic.com"', pinned],
        ["base", '"https://api.groq.com/openai/v1"', '"https://api.groq.com/v1"', pinned],
        ["no-store", "images: true,\n        noStore: { store: false }", "images: true,\n        noStore: null", pinned],
        ["live-no-store", "images: false,\n        noStore: { tracing: null }", "images: false,\n        noStore: null", pinned],
        ["live-base", '"wss://api.openai.com/v1/realtime?model=', '"wss://api.openai.com/v1/live?model=', pinned],
        ["live-model", '/v1/realtime?model=', '/v1/realtime?version=', pinned],
        ["live-model-id", "?model=gpt-realtime-2.1", "?model=gpt-realtime-mini", pinned],
        ["gemini-live-model", 'model: "gemini-3.8-live"', 'model: "gemini-3.8-flash-live"', pinned],
        ["gemini-live-query", "GenerativeService.BidiGenerateContent\",", "GenerativeService.BidiGenerateContent?alt=ws\",", pinned],
        ["gemini-live-origin", '"wss://generativelanguage.googleapis.com/ws/', '"wss://live.generativelanguage.googleapis.com/ws/', joined],
        ["elevenlabs-model", 'model: "eleven_flash_v2_5"', 'model: "eleven_multilingual_v2"', pinned],
        ["elevenlabs-origin", 'base: "https://api.elevenlabs.io"', 'base: "https://elevenlabs.io"', joined],
        ["codex-key", 'base: "https://chatgpt.com", key: "none"', 'base: "https://chatgpt.com", key: "optional"', pinned],
        ["claude-key", 'base: "https://api.anthropic.com", key: "none"', 'base: "https://api.anthropic.com", key: "optional"', pinned],
        ["claude-origin", 'base: "https://api.anthropic.com", key: "none"', 'base: "https://claude.ai", key: "none"', joined],
        ["freeze", "Object.freeze(value);", "", logic => {
            const row = logic.select("openai");
            assert.throws(() => { row.noStore.store = true; }, TypeError);
        }],
        ["custom-query", ' || url.search !== ""', "", logic => resolves(logic, custom[7])],
        ["custom-websocket", "target.websocket || ", "", logic => resolves(logic, custom[6])],
        ["custom-bare-query", ' || url.href.endsWith("?")', "", logic => resolves(logic, custom[8])],
        ["custom-slash", '.replace(/\\/$/, "")', "", logic => resolves(logic, custom[0])],
        ["unknown", "!Object.hasOwn(ROWS, id)", "!(id in ROWS)",
            logic => assert.throws(() => logic.select("constructor"), { message: "jarvis: provider=unknown" })],
        ["account-join", '"lm-studio": { driver', '"lmstudio": { driver', joined],
        ["registered", 'if (!rows.has(value)) fail("row");', "",
            logic => assert.throws(() => logic.assertRow({ ...logic.select("openai") }), { message: "jarvis: provider=row" })]
    ];
    for (const [name, needle, replacement, check] of mutants) {
        control(root, name, "Providers.js", needle, replacement, check);
        controls++;
    }
});
console.log("test-jarvis-providers: ok rows=" + Object.keys(documented).length + " custom=" + custom.length + " controls=" + controls);
