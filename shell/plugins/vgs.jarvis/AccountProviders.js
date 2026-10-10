// Shared by the account judge and its environment-presence reader.
// Login tokens belong to the vendor program, never to the key picker. A cli
// row's id names its harness in shell/Commons/AccountDirectories.js, the
// core's account rule, which holds its folder, variable and marker. A key
// row's keyPage is the vendor's page that creates an API key, which Add key
// names beside a provider it offers.
var PROVIDERS = [
    { id: "claude", label: "Claude Code", kind: "cli", origin: "https://api.anthropic.com", command: ["claude", "auth", "status"], signIn: ["claude", "auth", "login"] },
    { id: "codex", label: "Codex", kind: "cli", command: ["codex", "login", "status"], signIn: ["codex", "login"] },
    // Copilot documents no status command; Verify proves the account answers.
    // Sign in runs `copilot login`, the sign-in GitHub documents for Copilot CLI.
    { id: "copilot", label: "GitHub Copilot", kind: "cli", command: null, signIn: ["copilot", "login"] },
    // Pi's sign-in check needs a provider name; its own model list proves a setup.
    { id: "pi", label: "Pi", kind: "cli", command: null },
    { id: "openai", label: "OpenAI", kind: "key", variable: "OPENAI_API_KEY", origin: "https://api.openai.com", keyPage: "https://platform.openai.com/api-keys",
        probe: { driver: "chat", path: "/v1/chat/completions", model: "gpt-4.1-nano", limit: "max_completion_tokens", header: "authorization", prefix: "Bearer " } },
    { id: "anthropic", label: "Anthropic", kind: "key", variable: "ANTHROPIC_API_KEY", origin: "https://api.anthropic.com", keyPage: "https://console.anthropic.com/settings/keys",
        probe: { driver: "messages", path: "/v1/messages", model: "claude-haiku-4-5", header: "x-api-key", prefix: "" } },
    { id: "openrouter", label: "OpenRouter", kind: "key", variable: "OPENROUTER_API_KEY", origin: "https://openrouter.ai", keyPage: "https://openrouter.ai/keys",
        probe: { driver: "chat", path: "/api/v1/chat/completions", model: "openai/gpt-4.1-nano", limit: "max_tokens", header: "authorization", prefix: "Bearer " } },
    { id: "groq", label: "Groq", kind: "key", variable: "GROQ_API_KEY", origin: "https://api.groq.com", keyPage: "https://console.groq.com/keys",
        probe: { driver: "chat", path: "/openai/v1/chat/completions", model: "llama-3.1-8b-instant", limit: "max_tokens", header: "authorization", prefix: "Bearer " } },
    { id: "cerebras", label: "Cerebras", kind: "key", variable: "CEREBRAS_API_KEY", origin: "https://api.cerebras.ai",
        probe: { driver: "chat", path: "/v1/chat/completions", model: "", limit: "max_completion_tokens", header: "authorization", prefix: "Bearer " } },
    { id: "mistral", label: "Mistral", kind: "key", variable: "MISTRAL_API_KEY", origin: "https://api.mistral.ai", keyPage: "https://console.mistral.ai/api-keys",
        probe: { driver: "chat", path: "/v1/chat/completions", model: "mistral-small-latest", limit: "max_tokens", header: "authorization", prefix: "Bearer " } },
    { id: "gemini", label: "Gemini", kind: "key", variable: "GEMINI_API_KEY", origin: "https://generativelanguage.googleapis.com", keyPage: "https://aistudio.google.com/apikey",
        probe: { driver: "chat", path: "/v1beta/openai/chat/completions", model: "gemini-2.5-flash-lite", limit: "max_tokens", header: "authorization", prefix: "Bearer " } },
    { id: "elevenlabs", label: "ElevenLabs", kind: "speech-key", variable: "ELEVENLABS_API_KEY", origin: "https://api.elevenlabs.io" },
    { id: "ollama", label: "Ollama", kind: "local", port: 11434, origin: "http://127.0.0.1:11434",
        probe: { driver: "ollama", path: "/api/generate", model: "" } },
    { id: "llama-server", label: "llama-server", kind: "local", port: 8080, origin: "http://127.0.0.1:8080",
        probe: { driver: "llama", path: "/completion", model: "" } },
    { id: "lm-studio", label: "LM Studio", kind: "local", port: 1234, origin: "http://127.0.0.1:1234",
        probe: { driver: "chat", path: "/v1/chat/completions", model: "", limit: "max_tokens" } }
];

// The daemon's runtime directory under the session's XDG_RUNTIME_DIR, empty
// without one. The service hands it to the daemon in hello and the account
// helper to Verify's harness handoff, so both place Codex in one directory.
function runtimeDirectory(base) {
    return base ? base + "/vgshell/jarvis" : "";
}

// Only booleans cross into the helper. No key value enters its environment.
function keyProvider(row) {
    return row.kind === "key" || row.kind === "speech-key";
}

function keyPresence(read) {
    var result = {};
    for (var i = 0; i < PROVIDERS.length; i++) {
        var row = PROVIDERS[i];
        if (keyProvider(row))
            result[row.variable] = Boolean(read(row.variable));
    }
    return result;
}

// The one rule for a row whose account the conversation engine can run as
// its AI model: a sign-in program, whose model modelChoice picks, or a row
// whose probe names the model the account judge hands the engine. The
// account judge refuses any other as model-required (Accounts.js accepted).
function modelProvider(row) {
    return row.kind === "cli" || (row.probe !== undefined && row.probe.model !== "");
}

// An API-key row the engine can use as its AI model; a speech-only key is
// no AI model, so Add key and Use keyring item offer no other key row.
function modelKeyProvider(row) {
    return row.kind === "key" && modelProvider(row);
}

// The models Jarvis prefers, first to last, each at PREFERRED_EFFORT (owner,
// 2026-10-09): the first one the selected sign-in offers is its default. A
// sign-in that offers none runs its program's own default model and effort.
var PREFERRED_MODELS = ["claude-fable-5-1", "claude-opus-5-5"];
var PREFERRED_EFFORT = "high";
// The effort choice that hands the program no effort, where a model takes
// levels and its program names no default among them, as Claude Code's
// list does for a model Jarvis does not prefer. No program's level has this
// name: Claude Code 2.1.289 lists low to max and Codex 0.160.0 low to ultra.
var OWN_EFFORT = "default";
var EFFORT_LABELS = { xhigh: "Extra high" };

// Whether VALUE, a model as its program lists it, is the model ID. Claude
// Code 2.1.289 appends the context size, "claude-opus-5-5[1m]"; Copilot
// 1.0.91 writes a version with a dot, "claude-opus-5.5".
function namesModel(value, id) {
    return value.replace(/\[[^\]]*\]$/, "").replace(/\./g, "-") === id;
}

// The preferred model OFFERS holds, or null: the first of PREFERRED_MODELS
// that an offer names.
function preferredOffer(offers) {
    for (var i = 0; i < PREFERRED_MODELS.length; i++) {
        var found = offers.filter(function (offer) { return namesModel(offer.value, PREFERRED_MODELS[i]); })[0];
        if (found !== undefined) return found;
    }
    return null;
}

// A level as the page reads it: the program's own by name, else its word.
function effortLabel(level) {
    return level === OWN_EFFORT ? "Model default"
        : Object.prototype.hasOwnProperty.call(EFFORT_LABELS, level) ? EFFORT_LABELS[level]
        : level.charAt(0).toUpperCase() + level.slice(1);
}

// The effort levels the page offers for OFFER, the unset one first: the
// preferred effort for a preferred model that takes it, else the level its
// program names as its own, else OWN_EFFORT. A model that takes no level
// offers none, so the page shows no effort field.
function effortOffers(offer, preferred) {
    if (offer.efforts.length === 0) return [];
    var first = preferred && offer.efforts.indexOf(PREFERRED_EFFORT) !== -1 ? PREFERRED_EFFORT
        : offer.efforts.indexOf(offer.effort) !== -1 ? offer.effort : OWN_EFFORT;
    return [first].concat(offer.efforts.filter(function (level) { return level !== first; })).map(function (level) {
        return { label: effortLabel(level), value: level };
    });
}

// What the Jarvis page offers as model and effort for SETTINGS, the
// plugin's, and the model and effort it saves. LISTED is the page's read of
// the chosen sign-in's own list, { kind, offers }: "read" with offers, each
// { value, label, efforts, effort }, its program's own default first;
// "failed" for a read its program did not answer; else no read, as while
// the page is closed. With no list `models` and `efforts` hold the saved
// choice alone, the model marked while its list could not be read, and
// `model` and `effort` are the saved ones. With a list they are the page's
// choices, each led by what its unset setting runs
// (docs/architecture/design-system.md § Settings pages), and `model` and
// `effort` are what the page saves: the saved choice while the sign-in
// offers it, else that first choice, and "" for the program's own.
function modelChoice(settings, listed) {
    if (listed.kind !== "read")
        return { model: settings.model, effort: settings.effort,
            models: settings.model === "" ? [] : [{ label: settings.model + (listed.kind === "failed" ? " (list not read)" : ""), value: settings.model }],
            efforts: settings.effort === "" ? [] : [{ label: effortLabel(settings.effort), value: settings.effort }] };
    var offers = listed.offers;
    if (offers.length === 0) return { model: "", effort: "", models: [], efforts: [] };
    var preferred = preferredOffer(offers);
    var ordered = preferred === null ? offers
        : [preferred].concat(offers.filter(function (offer) { return offer !== preferred; }));
    var chosen = ordered.filter(function (offer) { return offer.value === settings.model; })[0] || ordered[0];
    var efforts = effortOffers(chosen, PREFERRED_MODELS.some(function (id) { return namesModel(chosen.value, id); }));
    var effort = efforts.some(function (level) { return level.value === settings.effort; }) ? settings.effort
        : efforts.length === 0 ? "" : efforts[0].value;
    return { model: chosen.value, effort: effort === OWN_EFFORT ? "" : effort,
        models: ordered.map(function (offer) { return { label: offer.label, value: offer.value }; }), efforts: efforts };
}

// The setup terminal's choice lines, LABEL<TAB>VALUE for
// `gum choose --label-delimiter=$'\t'`, which prints VALUE alone: an id goes
// back to its judge and never reaches the screen. Each label fits a terminal
// width columns wide, cut with an ellipsis, after gum's two-column "> "
// cursor. Labels come from judges that refuse control characters, so none
// holds a tab. Width counts code points, so a wide character can overflow.
var MIN_WIDTH = 20;
var MAX_WIDTH = 1000;
var CHOICE_CURSOR = 2;

// The terminal width argument of the setup helpers, or null when it is no
// integer from MIN_WIDTH to MAX_WIDTH.
function parseWidth(text) {
    if (typeof text !== "string" || !/^[0-9]{1,4}$/.test(text)) return null;
    var value = Number(text);
    return value >= MIN_WIDTH && value <= MAX_WIDTH ? value : null;
}

function fitText(text, width) {
    var points = Array.from(text);
    return points.length <= width ? text : points.slice(0, width - 1).join("") + "\u2026";
}

function choiceLine(label, value, width) {
    return fitText(label, width - CHOICE_CURSOR) + "\t" + value;
}

// Add directory offers the sign-in programs, "cli"; Add key and Use keyring
// item the AI model key providers, "key", Add key with the page that
// creates a key.
function providerChoices(kind, width, pages) {
    var rows = PROVIDERS.filter(function (row) {
        if (kind === "cli") return row.kind === "cli";
        if (kind === "sign-in") return row.kind === "cli" && Array.isArray(row.signIn);
        if (kind === "key") return modelKeyProvider(row);
        throw new Error("jarvis-providers: kind=" + kind);
    });
    return rows.map(function (row) {
        return choiceLine(pages ? row.label + ": get a key at " + row.keyPage.replace(/^https:\/\//, "") : row.label, row.id, width);
    });
}

// The account CLI and its QML reader share this exact safe error protocol.
// Only producer-owned keys can leave stderr; values and native errors cannot.
var FAILURE_KEYS = {
    "jarvis-accounts": {
        directory: ["absolute-normal-path-required", "unreadable", "link", "not-directory", "unreadable-or-changed"],
        added: ["shape", "size", "json", "limit", "duplicate", "read-failed", "directory-absent", "write-failed", "cleanup-failed"],
        "key-presence": ["shape"],
        ports: ["reply"],
        reference: ["provider", "item-unavailable", "vendor-login-or-provider"],
        arguments: ["tree", "presence", "list", "table", "accounts", "providers", "items", "add", "remember", "verb", "width", "sign-in-folders", "sign-in-entry"],
        "sign-in": ["terminal-required", "directory-create-failed", "provider", "search-incomplete", "folder-unavailable", "name-invalid", "name-in-use"],
        verify: ["explicit-user-required", "account-unavailable", "provider-unsupported", "busy", "keyring-locked"],
        state: ["unknown"],
        operation: ["failed"]
    },
    "jarvis-keys": {
        reference: ["shape", "identity", "origin", "attributes"],
        references: ["directory", "size", "read-failed", "json", "limit", "duplicate", "write-failed", "cleanup-failed"],
        busctl: ["missing", "timeout", "failed", "reply"],
        "secret-tool": ["missing", "timeout", "failed", "empty-or-oversize"],
        items: ["limit-or-duplicate", "reply", "label"],
        store: ["terminal-required"]
    }
};
var MAX_DIAGNOSTIC_CHARS = 256;

function feedDiagnostic(state, chunk) {
    if (state.kind === "oversize") return state;
    var text = state.text + chunk;
    if (text.length > MAX_DIAGNOSTIC_CHARS) return { kind: "oversize" };
    return { kind: "collected", text: text };
}

function helperFailure(text) {
    if (typeof text !== "string" || text.length > MAX_DIAGNOSTIC_CHARS) return "";
    var match = /^([a-z-]+): ([a-z-]+)=([a-z0-9-]+)\n?$/.exec(text);
    if (match === null) return "";
    var fields = FAILURE_KEYS[match[1]];
    var codes = fields === undefined ? undefined : fields[match[2]];
    if (!Array.isArray(codes) || codes.indexOf(match[3]) === -1) return "";
    return match[1] + ": " + match[2] + "=" + match[3];
}

function probeFailure(completion, diagnostic) {
    switch (completion.kind) {
    case "starting": return "jarvis-accounts: process=start-failed";
    case "crashed": return "jarvis-accounts: process=crashed";
    case "exited":
        if (completion.code === 0) return "jarvis-accounts: output=invalid";
        if (diagnostic.kind === "oversize") return "jarvis-accounts: diagnostic=oversize";
        return helperFailure(diagnostic.text) || "jarvis-accounts: process=failed";
    default: throw new Error("jarvis-accounts: process=invalid-outcome");
    }
}

if (typeof module !== "undefined") module.exports = { PROVIDERS: PROVIDERS, runtimeDirectory: runtimeDirectory,
    keyPresence: keyPresence, keyProvider: keyProvider, modelProvider: modelProvider, modelKeyProvider: modelKeyProvider, modelChoice: modelChoice, parseWidth: parseWidth, fitText: fitText, choiceLine: choiceLine,
    providerChoices: providerChoices, FAILURE_KEYS: FAILURE_KEYS, feedDiagnostic: feedDiagnostic,
    helperFailure: helperFailure, probeFailure: probeFailure };
