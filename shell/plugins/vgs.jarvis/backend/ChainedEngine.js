// One conversation owner: chained speech or duplex delegation to a cloud voice.
// Session owns identity and deadlines, Audio owns pacing and heard accounting,
// WireBrain owns history and ToolRouter owns actions. This owner connects them
// per conversation and keeps the heard prefix that the next turn reports.
// Contract: docs/decisions/D089-jarvis-chained-engine-and-heard-prefix.md.
"use strict";
const { Readable, Writable } = require("node:stream");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const Policy = require("./Policy.js");
const Providers = require("./Providers.js");
const { PROVIDERS, unlistedChoice } = require("../AccountProviders.js");
const Net = require("./net.js");
const Guidance = require("./Guidance.js");
const Speakable = require("./Speakable.js");
const Tools = require("./Tools.js");
const OpenAIChat = require("./OpenAIChat.js");
const AnthropicMessages = require("./AnthropicMessages.js");
const CodexHarness = require("./CodexHarness.js");
const CopilotHarness = require("./CopilotHarness.js");
const PiHarness = require("./PiHarness.js");
const ClaudeCode = require("./ClaudeCode.js");
const LocalSpeech = require("./LocalSpeech.js");
const { PCM_RATE } = require("./Audio.js");
const Realtime = require("./Realtime.js");
const GeminiLive = require("./GeminiLive.js");
const ElevenLabs = require("./ElevenLabs.js");
const TaskVoice = require("./TaskVoice.js");
const Redact = require("./Redact.js");

// Speech adapter rows in selection order. A row is {select({settings,
// accounts, directories})} answering {kind:"ready", recipients, voices,
// open({net, recipients})} or {kind:"unconfigured", cause, detail?}, voices
// its {label, value} offers, whose value is the speaker its adapter's speak
// takes. A row's transcribe yields
// partials, then {kind: "final", text}; a ready row with `dictation: true`
// takes each utterance's words from the core's dictation recording (D064)
// and ends it with {kind: "ended", speech}, whether its voice activity
// heard speech. The ElevenLabs voice speaks over the ready row, which still
// hears the user (selectSpoken).
const SPEECH = Object.freeze({ local: LocalSpeech.row });
const DRIVERS = Object.freeze({ "openai-chat": OpenAIChat, "anthropic-messages": AnthropicMessages,
    "codex-app-server": CodexHarness, "copilot-acp": CopilotHarness, "pi-rpc": PiHarness, "claude-code": ClaudeCode });
// A tool's id and its model-facing name. A harness shows a brain that name
// behind its own prefix, which ends before the name starts. Speakable keeps
// a sentence of a brain's reply that holds one out of speech.
const TOOL_NAMES = Object.freeze([...Object.keys(Tools.TABLE), ...Tools.wireNames(Object.keys(Tools.TABLE)).keys()]);
// The duplex voices by their Voice provider setting: the provider row, the
// account provider whose stored key serves that row's origin, and the
// adapter. Both adapters keep Realtime.js's contract.
const DUPLEX = Object.freeze({
    realtime: Object.freeze({ id: "openai-realtime", account: "openai", adapter: Realtime }),
    gemini: Object.freeze({ id: "gemini-live", account: "gemini", adapter: GeminiLive })
});
function duplexOf(id) { return Object.values(DUPLEX).find(row => row.id === id) ?? null; }
// The hello carries no language setting; empty selects English.
const LANGUAGE = "";
// Object-mode chunks queued toward Audio, below its playback allowance.
const SPEECH_CHUNKS = 16;
// Released sentence text waiting for synthesis, in UTF-16 code units. One
// response is bounded at its source; this bounds the text Speakable made.
const SENTENCE_TEXT = 8 * 1024 * 1024;
// Capture bytes held for transcription before Audio sees backpressure.
const CAPTURE_BYTES = 16 * 1024;
// Release records name the transfer leaving the machine.
const RELEASE_EFFECT = "external";
// One local working sound for a still-silent turn, without a speech request.
const WORKING_AFTER_MS = 1200;
// Owner ruling VGS-1320: longer than a few seconds gets one spoken progress line per stated step.
const PROGRESS_AFTER_MS = 4000;
// The one sentence a voice preview speaks.
const PREVIEW_LINE = "This is how I sound when I answer you.";

function earcon(kind) {
    const frames = PCM_RATE * (kind === "start" ? 80 : 120) / 1000;
    const pcm = Buffer.alloc(frames * 2);
    const edge = PCM_RATE * 5 / 1000;
    const frequency = kind === "start" ? 880 : 440;
    for (let frame = 0; frame < frames; frame++) {
        const envelope = Math.min(1, frame / edge, (frames - frame - 1) / edge);
        pcm.writeInt16LE(Math.round(3900 * envelope * Math.sin(2 * Math.PI * frequency * frame / PCM_RATE)), frame * 2);
    }
    return pcm;
}

function fail(code) { throw new Error("jarvis: engine=" + code); }
// A dictation request that did not answer "ok", as Session's keyed fault:
// the word the core or the service refused with, or the port's own end.
function dictationFault(result) {
    if (result.kind !== "answer") return "speech=dictation-" + result.kind;
    return "speech=dictation-" + (/^refused: dictation=([a-z-]{1,40})/.exec(result.answer)?.[1] ?? "refused");
}
function unconfigured(cause, detail) { return detail === undefined ? { kind: "unconfigured", cause } : { kind: "unconfigured", cause, detail }; }
// The index in VOICES, a speech row's {label, value} offers, of the voice
// SETTING names. The first offer stands for the unset setting
// (docs/architecture/design-system.md § Settings pages), and so for a voice
// of another provider, which this row cannot speak.
function voiceIndex(voices, setting) {
    const at = voices.findIndex(voice => voice.value === setting);
    return at === -1 ? 0 : at;
}
// Session's fault carries the producer's keyed cause, never other text.
function keyed(error) {
    const message = error?.message ?? "";
    return /^jarvis(?:-[a-z]+)?: [a-z-]+=[^\n]*$/.test(message)
        ? message.replace(/^jarvis: /, "").slice(0, 180) : "engine=unexpected";
}

const WIRE_FAILOVER = new Map([
    ["unauthorized", 401], ["billing", 402], ["forbidden", 403], ["rate-limited", 429],
    ["provider-error", 500], ["unavailable", 503], ["timeout", 504], ["overloaded", 529]
]);
function failoverCause(reason) {
    if (["brain=stream-failed", "brain=stream-truncated", "brain=stream-error", "net=request"].includes(reason)) return true;
    const api = /^brain=harness-api-error status=([0-9]+)$/.exec(reason);
    if (api !== null) return [401, 402, 403, 429].includes(Number(api[1])) || Number(api[1]) >= 500;
    const wire = /^brain=([a-z-]+) status=([0-9]+)$/.exec(reason);
    if (wire !== null && wire[1] === "http") return Number(wire[2]) >= 500;
    if (wire !== null) return WIRE_FAILOVER.get(wire[1]) === Number(wire[2]);
    if (/^brain=harness-model-refused(?: |$)/.test(reason)) return true;
    if (/^brain=(harness-exit|harness-ended|copilot-signed-out|(?:codex|copilot|pi)-exited)(?: |$)/.test(reason)) return true;
    return false;
}
function endedCause(reason) {
    return /^brain=(harness-exit|harness-ended|(?:codex|copilot|pi)-exited)(?: |$)/.test(reason);
}

function providerLabel(provider) {
    return PROVIDERS.find(row => row.id === provider)?.label ?? provider;
}

function brainLabel(entry) {
    const label = entry.model === "" ? entry.label : entry.label + " " + entry.model;
    return label.slice(0, 180);
}

function failoverLine(from, to, resend) {
    const start = from + " is not answering, so I am continuing on " + to + ".";
    return start + (resend ? " It has not heard what we said before." : " It has not heard what we said before. Please say your request again.");
}

// A test run's record of what a brain wrote: one {gen, op, text} line for
// each text event, before Speakable reads it. trace is {marker, file}, the
// daemon's VGS_TEST_RUN and VGS_JARVIS_TRACE. Only the test-run marker with a
// path opens the file, so no session of a user's writes a transcript to disk
// (docs/architecture/jarvis.md § Capture and records). The file is the
// run's own: made 0600, never through a link, and only added to. A run's
// environment is its caller's to set, and a path that is not absolute would
// land in the daemon's working folder, so it is refused.
function tracer(trace) {
    if (trace.marker !== "1" || trace.file === undefined) return null;
    if (typeof trace.file !== "string" || !path.isAbsolute(trace.file)) fail("trace-path");
    const { O_WRONLY, O_APPEND, O_CREAT, O_NOFOLLOW } = fs.constants;
    const failed = (step, error) => fail("trace-" + step + " cause=" + (error.code ?? "unknown"));
    let fd;
    try { fd = fs.openSync(trace.file, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o600); }
    catch (error) { failed("open", error); }
    return {
        write(turn, text) {
            try { fs.writeSync(fd, JSON.stringify({ gen: turn.gen, op: turn.op, text }) + "\n"); }
            catch (error) { failed("write", error); }
        },
        // Teardown can run again after a failure inside it.
        close() {
            if (fd !== null) fs.closeSync(fd);
            fd = null;
        }
    };
}

// One wake point per waiter; notify releases every current waiter.
function signal() {
    let waiters = [];
    return {
        wait: () => new Promise(resolve => waiters.push(resolve)),
        notify() { const current = waiters; waiters = []; for (const resolve of current) resolve(); }
    };
}

/**
 * Choose the conversation plan from snapshot settings. The first ready speech
 * row wins; the brain comes from the saved account through Accounts.choose,
 * the provider table and the key reference. The speech and brain steps are
 * judged apart, so an unconfigured plan carries `cause`, the first failing
 * step's, speech before brain, and `causes`, every failing step's in that
 * order, which the daemon publishes for the setup view. A dictation row
 * holds the plan with the service's dictation cause, settings.dictation,
 * while the core's recording cannot start; its sidecar still loads.
 */
function select(settings, accounts, directories, listed = () => ({ voices: null, known: null, reading: false }), models = () => ({ kind: "none" })) {
    const { list = null, ...speech } = selectSpeech(settings, accounts, directories, listed);
    const dictation = speech.kind === "ready" && speech.dictation === true && settings.dictation !== ""
        ? unconfigured(settings.dictation) : { kind: "ready" };
    const brain = selectBrain(settings, accounts, models);
    const failing = [speech, dictation, brain].filter(step => step.kind !== "ready");
    if (failing.length > 0) return { ...failing[0], speech, causes: failing.map(step => step.cause), list, modelLists: brain.modelLists };
    return { kind: "ready", speech, brain: brain.brain, entries: brain.entries, list, modelLists: brain.modelLists };
}

// A home folder's own keyed cause, or null for any other failure.
function homeCause(error) {
    return /^jarvis: (home=[a-z-]{1,60}|guidance=home-[a-z-]{1,50})$/.exec(error?.message ?? "")?.[1] ?? null;
}

/**
 * The plan with the home folder's step judged before its own, as {plan,
 * cautions}. home is the daemon's judgement of the folder the user chose. A
 * folder the daemon refused, or whose text Guidance cannot read, holds the
 * engine with its cause first: Jarvis never answers without the persona the
 * user chose. cautions are the causes of the home texts over their budget,
 * in the largest consumer's guidance, the local brain's: each loads whole and
 * holds nothing (Guidance homeLayers).
 */
function heldByHome(plan, home) {
    let cause = null;
    let cautions = [];
    switch (home.kind) {
    case "none": break;
    case "refused": cause = home.cause; break;
    case "ready":
        try { cautions = Guidance.compose("chained", "local", LANGUAGE, home.path).overBudget; }
        catch (error) {
            cause = homeCause(error);
            if (cause === null) throw error;
        }
        break;
    default: fail("home-state");
    }
    if (cause === null) return { plan, cautions };
    return { plan: { ...unconfigured(cause), speech: plan.speech, causes: [cause, ...(plan.kind === "ready" ? [] : plan.causes)], list: plan.list, modelLists: plan.modelLists },
        cautions };
}

// Always mode listens for the wake word on this computer, so it needs a row
// that spots it locally; any other voice would stream the room to a provider.
function selectSpeech(settings, accounts, directories, listed) {
    const speech = selectVoice(settings, accounts, directories, listed);
    if (settings.mode === "always" && (Object.hasOwn(DUPLEX, settings.voiceProvider) || speech.kind === "ready" && speech.wake !== true))
        return unconfigured("speech=always-local-voice");
    return speech;
}

// The stored key a cloud voice uses: the Voice key setting's account, a
// keyring key of the provider ACCOUNT names, which may travel to PROVIDER's
// origin. {kind: "ready", key, recipient}, or the cloud voices' shared
// cause.
function voiceKey(settings, accounts, account, provider) {
    if (!settings.voiceAccount) return unconfigured("speech=live-account-unselected");
    let judge, resolved;
    try { judge = accounts(); resolved = judge.resolve(settings.voiceAccount); }
    catch (error) {
        if (!/^jarvis-(?:accounts|keys): /.test(error?.message ?? "")) throw error;
        return unconfigured("speech=live-account-unreadable");
    }
    if (resolved === null || resolved.provider !== account || resolved.source.kind !== "keyring")
        return unconfigured("speech=live-key-required");
    const reference = resolved.source.reference;
    Net.assertKeyTarget(provider.base, reference.origin);
    return { kind: "ready", key: { secrets: judge.secrets, reference },
        recipient: { kind: "network", provider: resolved.provider, account: resolved.id, origin: Net.endpoint(provider.base).origin } };
}

function selectVoice(settings, accounts, directories, listed) {
    if (Object.hasOwn(DUPLEX, settings.voiceProvider)) {
        const duplex = DUPLEX[settings.voiceProvider];
        const provider = Providers.select(duplex.id);
        const key = voiceKey(settings, accounts, duplex.account, provider);
        if (key.kind !== "ready") return key;
        const voices = duplex.adapter.VOICES;
        return { kind: "ready", id: duplex.id, provider, key: key.key,
            voices, voice: voices[voiceIndex(voices, settings.voice)].value, recipients: [key.recipient] };
    }
    if (settings.voiceProvider === "elevenlabs") return selectSpoken(settings, accounts, directories, listed);
    return selectHearing(settings, accounts, directories);
}

/**
 * The ElevenLabs voice: the ready speech row hears the user, wake word and
 * turn detection included, and ElevenLabs speaks with the stored key. Its
 * recipients are that row's and ElevenLabs's. LISTED(reference) answers the
 * key's voice list as {voices, known, reading}: voices the offers of the
 * last read, null before one answered and [] after a failed one; known the
 * ids a read of this key listed in this daemon's life, null before any; and
 * whether a read is in flight. The speaker is one of the offers, else the
 * Voice setting while a read listed it, so another provider's voice name
 * never becomes a request path. With neither, the step waits for a read
 * still to answer, or holds with the failed read's cause, which a Talk
 * reads again (voicesHeld). `list` asks the engine to read the voices for
 * this key, whatever the rest of the step answers.
 */
function selectSpoken(settings, accounts, directories, listed) {
    const provider = Providers.select("elevenlabs");
    const key = voiceKey(settings, accounts, "elevenlabs", provider);
    if (key.kind !== "ready") return key;
    const list = { provider, key: key.key, recipient: key.recipient };
    const hearing = selectHearing(settings, accounts, directories);
    if (hearing.kind !== "ready") return { ...hearing, list };
    const read = listed(key.key.reference);
    const voices = read.voices ?? [];
    const speaker = voices.length !== 0 ? voices[voiceIndex(voices, settings.voice)].value
        : read.known?.has(settings.voice) ? settings.voice : null;
    if (speaker === null)
        return { ...unconfigured(read.voices === null || read.reading ? "speech=elevenlabs-voices-reading" : "speech=elevenlabs-voice"), list };
    return { ...hearing, id: "elevenlabs", voices, speaker, recipients: [...hearing.recipients, key.recipient],
        spoken: { provider, key: key.key }, list };
}

function selectHearing(settings, accounts, directories) {
    let speech = unconfigured("speech=no-adapter");
    for (const [id, row] of Object.entries(SPEECH)) {
        const answer = row.select({ settings, accounts, directories });
        if (answer.kind === "ready") return { ...answer, id, speaker: answer.voices[voiceIndex(answer.voices, settings.voice)].value };
        if (answer.kind !== "unconfigured") fail("speech-row");
        if (speech.cause === "speech=no-adapter") speech = answer;
    }
    return speech;
}

function selectedBrain(settings, accounts, id, model, primary, models, modelLists) {
    if (id === "") return primary ? unconfigured("brain=unselected") : null;
    let judge, choice;
    try {
        judge = accounts();
        choice = judge.choose(id, model ?? settings.model ?? "", models(id));
        if (choice.list !== undefined) modelLists.push({ judge, id: choice.list });
    } catch (error) {
        // Only the account and key readers' keyed failures are a cause here.
        if (!/^jarvis-(?:accounts|keys): /.test(error?.message ?? "")) throw error;
        return primary ? unconfigured("brain=accounts-unreadable", error.message) : null;
    }
    if (choice.kind === "refused") return primary ? unconfigured("brain=" + choice.cause) : null;
    if (choice.kind !== "accepted") fail("brain-choice");
    const account = choice.account;
    const provider = Providers.select(account.provider);
    if (!Object.hasOwn(DRIVERS, provider.driver)) fail("driver");
    const target = Net.endpoint(provider.base);
    // A key without a model list and a local server name their own model.
    // An Anthropic key and every sign-in program run the saved model and
    // effort, each "" for a program's own, and with no model saved the
    // choice unlistedChoice makes for the provider of the account resolved
    // here: a hello sent before the account reader's first answer could not
    // name it. On a hello that made the choice it changes nothing.
    const chosen = account.model !== "" ? { model: account.model, effort: "" }
        : model !== undefined ? unlistedChoice({ ...settings, model, effort: "" }, account.provider)
        : unlistedChoice(settings, account.provider);
    return { provider, model: chosen.model, effort: chosen.effort, id,
        label: providerLabel(account.provider),
        account: account.source,
        key: account.source.kind === "keyring" ? { secrets: judge.secrets, reference: account.source.reference } : null,
        recipient: { kind: "network", provider: provider.id, account: account.id, origin: target.origin },
        guidance: Guidance.compose("chained", target.loopback ? "local" : "text", LANGUAGE) };
}

function selectBrain(settings, accounts, models) {
    const modelLists = [];
    const first = selectedBrain(settings, accounts, settings.brain, undefined, true, models, modelLists);
    const entries = first.kind === "unconfigured" ? [] : [first];
    if (Array.isArray(settings.fallbacks)) {
        for (const fallback of settings.fallbacks) {
            if (fallback === null || typeof fallback !== "object") continue;
            const entry = selectedBrain(settings, accounts, fallback.brain, fallback.model, false, models, modelLists);
            if (entry !== null) entries.push(entry);
        }
    }
    if (entries.length === 0) return { ...first, modelLists };
    return { kind: "ready", brain: entries[0], entries, modelLists };
}

/**
 * create({session, state, audit, router, accounts, policy, fault, captionLimit,
 * harness, directories}) owns the daemon's conversations. session is
 * the Session judge and state returns its current record; audit is the daemon's
 * writer; directories are the hello's state, data and runtime roots; router supplies
 * offer, route, observe and interrupted; accounts returns an Accounts judge;
 * policy returns {profile, cloudVision}; fault reports a speech failure that
 * no capture or turn remains to carry. captionLimit is the wire's transcript
 * bound. harness is {bridge, gate, env, runtime} for a harness brain: the
 * tool bridge, the HarnessGate, the environment its program is started from
 * and a function answering the runtime directory. tasks is the coding-task
 * port a relay turn needs: held() lists the held prompts, answer(task,
 * prompt, value) answers one, and interrupted(gen, ask), released(gen, ask)
 * and withheld(gen, text, ask) report back to TaskVoice. home answers the
 * daemon's judgement of the user's home folder: {kind: "none"}, {kind:
 * "ready", path} or {kind: "refused", cause}; rejudge has the daemon judge
 * the folder and the setup again. trace is {marker, file}, the daemon's
 * test-run marker and trace path, which tracer judges. request is the
 * daemon's shell request port, ShellRequests' send, which a dictation row's
 * utterances record through.
 */
function create({ session, state, audit, router, accounts, policy, fault, captionLimit, harness = null, tasks = null, directories, dispatch, clock, configured = () => {}, fatal = error => { throw error; }, log = () => {}, home = () => ({ kind: "none" }), rejudge, trace = {}, request = null }) {
    if (!Number.isSafeInteger(captionLimit) || captionLimit < 1) fail("caption-limit");
    const brainText = tracer(trace);
    let plan = unconfigured("engine=starting");
    let conversation = null;
    let retired = null;
    let closed = false;
    let idleAt = null;
    let daemonSpeech = null;
    let speechState = { kind: "new" };
    // The identity of the row the daemon's sidecar last started from.
    let speechIdentity = null;
    const homePath = () => { const judged = home(); return judged.kind === "ready" ? judged.path : null; };
    // Whether the home folder's own cause holds the plan.
    let homeHeld = false;
    // The causes of the home texts over their budget (heldByHome), which
    // every configuration answer carries.
    let cautions = [];
    // The settings of the last configure, which a voice list's answer
    // judges again.
    let lastSettings = null;
    // The ElevenLabs voices of one key: identity is its reference's JSON,
    // voices null before a read answered and [] after a failed one, known
    // the ids of its last read that listed any, and net the read in
    // flight's owner, or null.
    let voiceList = { identity: null, voices: null, known: null, net: null };
    let listReads = 0;
    // Only the local accounts this selection names. Ordinary hellos keep
    // admitted answers and reads in flight; a new account/model selection,
    // a retry of a refused catalog or close invalidates the operation.
    let modelReads = new Map();
    let modelsFor = null;
    const modelOffers = id => modelReads.get(id)?.answer ?? { kind: "none" };
    function cancelModels() {
        for (const read of modelReads.values()) read.stop.abort();
        modelReads = new Map();
    }
    function modelsHeld() {
        return plan.kind === "unconfigured" && plan.causes.some(cause => cause === "brain=models-unavailable" || cause === "brain=model-unavailable");
    }
    const listed = reference => voiceList.identity === JSON.stringify(reference)
        ? { voices: voiceList.voices, known: voiceList.known, reading: voiceList.net !== null }
        : { voices: null, known: null, reading: false };

    function configuration() {
        const local = plan.speech?.kind === "ready" && plan.speech.lifetime === "daemon";
        const cause = local && speechState.kind === "starting" ? "speech=local-loading"
            : local && speechState.kind === "refused" ? "speech=local-" + speechState.error.code.split(" ")[0] : null;
        if (plan.kind !== "ready") {
            const { speech, list, modelLists, ...answer } = plan;
            // One cause per step: the sidecar's goes before the recording's.
            return cause === null ? { ...answer, cautions }
                : { ...answer, cause, causes: [cause, ...answer.causes.filter(other => !other.startsWith("speech="))], cautions };
        }
        if (local && speechState.kind === "starting")
            return { kind: "loading", cause: "speech=local-loading", causes: ["speech=local-loading"], cautions };
        if (local && speechState.kind === "refused") {
            return { kind: "unconfigured", cause, causes: [cause], cautions };
        }
        return { kind: "ready", cautions };
    }

    function startSpeech(row) {
        speechState = { kind: "starting" };
        speechIdentity = row.identity;
        const owner = row.open({ clock, changed: () => {
            if (!closed && owner.status().kind === "ready") {
                speechState = { kind: "ready" };
                configured(configuration());
            }
        } });
        daemonSpeech = owner;
        configured(configuration());
        void owner.closed.then(({ error }) => {
            if (closed || daemonSpeech !== owner) return;
            daemonSpeech = null;
            // A startup refusal revokes admission. An own-child fault
            // reloads on the next permitted request after the child is reaped.
            speechState = error.kind === "refused" || (speechState.kind === "starting" && error.code === "ready-timeout")
                ? { kind: "refused", error, publication: row.publication } : { kind: "unloaded" };
            configured(configuration());
        });
    }

    // Replace the daemon's sidecar with the plan's row when that row's
    // identity differs: the cloned voice setting changed, or a clone setup
    // or removal published. Never under a conversation, whose pending
    // speech the old sidecar holds; its end or the next one's open does.
    function reargue() {
        if (closed || conversation !== null || plan.speech?.kind !== "ready" || plan.speech.lifetime !== "daemon"
                || speechState.kind === "new" || speechIdentity === plan.speech.identity) return;
        daemonSpeech?.close();
        startSpeech(plan.speech);
    }

    function releaseEvent(c, identity, labels, decision, outcome) {
        return { kind: "release", gen: identity.gen, op: identity.op, tool: "release",
            args: { labels, recipients: c.recipients }, effect: RELEASE_EFFECT, decision, confirmed: "none", outcome };
    }
    // An asked or withheld item travels as its marker; its decision is kept.
    function record(c, identity, labels, decision) {
        if (audit.record(releaseEvent(c, identity, labels, decision, "completed")).kind !== "recorded") fail("audit-write");
    }
    // Every transfer is judged against the whole set, then audited first.
    function transfer(c, identity, item, start) {
        if (Policy.release(item, c.recipients, c.grants).kind !== "send") fail("release-" + item.labels.join("-"));
        const result = audit.before(releaseEvent(c, identity, item.labels, "send", "pending"), start);
        if (result.kind !== "started") fail("audit-write");
        return result.value;
    }

    function open(gen) {
        if (closed) fail("closed");
        if (plan.kind !== "ready") fail("unconfigured");
        const facts = policy();
        const activePlan = { ...plan, brain: plan.entries[0] };
        const recipients = Policy.recipients({ conversation: "jarvis-" + gen, profile: facts.profile,
            cloudVision: facts.cloudVision, brain: activePlan.brain.recipient, speech: activePlan.speech.recipients });
        const net = Net.create(recipients);
        // late holds at most one call: the router runs one action at a time.
        // relay is the held prompt the user's next words answer, or null;
        // retried is that prompt once it was asked again after unjudged words.
        const c = { gen, plan: activePlan, entry: 0, recipients, net, retired: new Set(), speech: null, spoken: null, liveOpen: null, brain: null, guidance: null, owner: null, grants: [], heard: null, relay: null, retried: null, unmatched: null,
            decisions: new Set(), releasePending: null, late: new Map(), results: [], turn: null, last: null,
            feedback: null, collection: null, unbound: null, rev: 0, quiet: Promise.resolve(), live: null };
        try {
            const duplex = duplexOf(plan.speech.id);
            if (duplex !== null) {
                c.live = duplex.adapter.create({ provider: plan.speech.provider, clock, captionLimit,
                    log, conversation: e => ({ net: c.net, key: plan.speech.key, language: LANGUAGE, voice: plan.speech.voice,
                        preview: e.preview === true ? PREVIEW_LINE : null,
                        grants: () => c.grants, transfer: (item, start) => transfer(c, e, item, start) }) });
                c.speech = { close: () => c.live.port.release() };
            } else {
                reargue();
                if (plan.speech.lifetime === "daemon" && daemonSpeech === null) startSpeech(plan.speech);
                c.speech = plan.speech.lifetime === "daemon" ? daemonSpeech : plan.speech.open({ net, recipients });
                // A failover replaces the net owner and the grants, so the
                // voice reads both at each request.
                if (plan.speech.spoken !== undefined) c.spoken = ElevenLabs.create({ provider: plan.speech.spoken.provider,
                    net: () => c.net, key: plan.speech.spoken.key, grants: () => c.grants, clock });
            }
        } catch (error) { net.close(); throw error; }
        return c;
    }
    // observe() ends a conversation before any effect of a newer generation.
    function current(gen) {
        if (gen !== state().gen) fail("stale-conversation");
        if (conversation !== null && conversation.gen !== gen) fail("conversation-generation");
        if (conversation === null) conversation = open(gen);
        else if (conversation.plan.speech.lifetime === "daemon" && daemonSpeech === null) {
            startSpeech(conversation.plan.speech);
            conversation.speech = daemonSpeech;
        }
        return conversation;
    }
    // Drop the context, the recipient set and its transport before another
    // conversation can start. Late cancel acknowledgments wait for closure.
    function end() {
        const c = conversation;
        if (c === null) return;
        conversation = null;
        cancelRelease(c);
        c.grants.length = 0;
        c.decisions.clear();
        // A task line the ending conversation cut off, by stop, lock, a
        // failed turn or a failed playback, goes back to TaskVoice, which
        // tells it the other way.
        if (c.last !== null) unheard(c, c.last);
        if (c.turn !== null) stop(c.turn);
        if (c.last !== null) c.last.speech?.end();
        c.feedback?.readable.destroy();
        for (const utterance of [c.collection?.utterance, c.unbound])
            if (utterance) utterance.abort();
        const brain = c.brain;
        c.brain = null;
        const quiet = brain === null ? Promise.resolve() : brain.cancel();
        brain?.close();
        if (c.plan.speech.lifetime !== "daemon") c.speech.close();
        c.spoken?.close();
        for (const door of c.retired) door.close();
        c.retired.clear();
        c.net.close();
        retired = { gen: c.gen, closed: quiet };
        // After the teardown this observation runs, not inside it.
        queueMicrotask(reargue);
    }
    function cancelRelease(c) {
        if (c.releasePending === null) return;
        c.releasePending.resolve(false);
        c.releasePending = null;
    }
    function collecting(c, collection) {
        return collection !== null && session.live(state(), { gen: c.gen, op: collection.op }, "turn", ["collecting"]);
    }

    // One capture as an adapter reads it: Audio writes the sink, and frames
    // hands each chunk on while running() holds. Each frame reaches the
    // adapter as a speech-labelled item, so a network adapter's own send
    // re-judges what it carries.
    function captured(running) {
        let held = null;
        let finished = false;
        let released = false;
        const wake = signal();
        const sink = new Writable({
            highWaterMark: CAPTURE_BYTES,
            // Frames after the adapter stopped reading have no consumer.
            write(chunk, encoding, done) {
                if (released || !running()) { done(); return; }
                held = { chunk, done };
                wake.notify();
            },
            final(done) { finished = true; wake.notify(); done(); },
            destroy(error, done) {
                finished = true;
                held = null;
                wake.notify();
                done(error);
            }
        });
        const frames = { [Symbol.asyncIterator]() { return { async next() {
            for (;;) {
                if (!running()) return { value: undefined, done: true };
                if (held !== null) {
                    const { chunk, done } = held;
                    held = null;
                    done();
                    return { value: Policy.item(chunk, ["speech"]), done: false };
                }
                if (finished) return { value: undefined, done: true };
                await wake.wait();
            }
        }, async return() {
            released = true;
            held?.done();
            held = null;
            return { value: undefined, done: true };
        } }; } };
        // A stopped reader wakes and ends; its held frame is dropped.
        return { sink, frames, drop() { held = null; wake.notify(); } };
    }

    // One utterance's dictation recording: begin asks the core to record
    // once Session admitted the capture, and stop hands back voxtype's words.
    // finish is "stop" or "cancel"; an end asked for while the start waits
    // runs once it answers. settle receives {kind: "text", text} or {kind:
    // "failed", cause} once, and nothing for a cancelled recording. Session's
    // collection deadline bounds the whole utterance, so it bounds each reply.
    function dictation(settle) {
        if (request === null) fail("dictation-port");
        const record = { phase: "new", end: null };
        const send = (kind, done) => request(kind, [], session.COLLECTION_TIMEOUT_MS, done);
        const ok = result => result.kind === "answer" && result.answer === "ok";
        function finish(how) {
            if (record.phase === "new" || record.phase === "starting") { record.end = how; return; }
            if (record.phase !== "recording") return;
            if (how === "cancel") {
                record.phase = "ended";
                // A recording already gone, as the service cancels at a lock,
                // answers a refusal that leaves nothing to undo.
                send("dictation.cancel", () => {});
                return;
            }
            record.phase = "stopping";
            send("dictation.stop", result => {
                record.phase = "ended";
                settle(ok(result) ? { kind: "text", text: result.data.text } : { kind: "failed", cause: dictationFault(result) });
            });
        }
        function begin() {
            if (record.phase !== "new") return;
            if (record.end === "cancel") {
                record.phase = "ended";
                return;
            }
            record.phase = "starting";
            send("dictation.start", result => {
                if (!ok(result)) {
                    record.phase = "ended";
                    if (record.end !== "cancel") settle({ kind: "failed", cause: dictationFault(result) });
                    return;
                }
                record.phase = "recording";
                if (record.end !== null) finish(record.end);
            });
        }
        return { begin, stop: () => finish("stop"), cancel: () => finish("cancel") };
    }

    // Speech to text. The capture sink exists while Audio holds the
    // recorder; one utterance yields partials and one final.
    function transcription(c, e) {
        const approval = state().approval;
        const answer = approval.kind === "held" ? { id: approval.id, digest: approval.digest,
            gen: approval.gen, beganAt: clock.now(), idleAt } : null;
        let output = null;
        // running: transcribing; ending: the row's final came and the
        // dictation recording's words are awaited; concluded: final delivered
        // or failed; aborted: abandoned by the conversation or by its
        // replacement. begin starts the dictation recording once a turn takes
        // the words: a live collection, or the held request it answers. A
        // capture no turn takes, as Toggle reopens one while Jarvis thinks,
        // records nothing.
        const utterance = { state: "running", collection: null, sink: null, answers: answer !== null, abort() {
            if (utterance.state !== "running" && utterance.state !== "ending") return;
            utterance.state = "aborted";
            input.drop();
            void output?.return?.();
            record?.cancel();
        }, begin() { record?.begin(); } };
        // Audio's teardown ends the utterance. A conversation that ended
        // with it, as by mute or stop, aborts the utterance in end().
        const input = captured(() => utterance.state === "running");
        const { sink, frames } = input;
        utterance.sink = sink;
        // The final words: the answer to a held request by its phrase, else
        // the collection's final.
        function concluded(text) {
            utterance.state = "concluded";
            if (answer !== null) {
                const phrase = TaskVoice.phrase(text);
                if (["yes", "confirm", "yes confirm"].includes(phrase))
                    dispatch({ type: "confirm", ...answer, source: "voice" });
                else if (["no", "cancel", "no cancel"].includes(phrase))
                    dispatch({ type: "approval-cancel", gen: answer.gen, id: answer.id });
            } else utterance.collection?.done("final", text);
        }
        // A dictation request that failed ends the utterance with no words; a
        // live collection's turn carries the cause.
        const record = c.plan.speech.dictation !== true ? null : dictation(result => {
            if (utterance.state !== "running" && utterance.state !== "ending") return;
            if (result.kind === "text") {
                concluded(result.text);
                return;
            }
            const running = utterance.state === "running";
            if (running) {
                input.drop();
                void output?.return?.();
            }
            utterance.state = "concluded";
            // A live collection's turn carries the cause; an unbound capture,
            // as a held request's answer, carries it as run()'s catch does.
            if (collecting(c, utterance.collection)) utterance.collection.failed(result.cause);
            else if (running && !sink.destroyed) sink.destroy(new Error("jarvis: " + result.cause));
        });
        async function run() {
            let rev = 0;
            try {
                transfer(c, e, Policy.item("", ["speech"]), () => {
                    output = c.speech.transcribe(frames, { detect: e.mode !== "hold" })[Symbol.asyncIterator]();
                });
                for (;;) {
                    const step = await output.next();
                    if (utterance.state !== "running") return;
                    if (step.done) fail("transcript-unfinished");
                    const event = step.value;
                    if (event === null || typeof event !== "object") fail("transcript");
                    if (event.kind === "partial" && typeof event.text === "string") {
                        if (!Number.isSafeInteger(event.rev) || event.rev <= rev) fail("transcript-revision");
                        rev = event.rev;
                        utterance.collection?.done("partial", event.text);
                    } else if (event.kind === "final" && record === null && typeof event.text === "string") {
                        void output.return?.();
                        concluded(event.text);
                        return;
                    } else if (event.kind === "ended" && record !== null && typeof event.speech === "boolean") {
                        void output.return?.();
                        // voxtype would still write words for silence, so an
                        // utterance with no speech is not stopped. Neither is
                        // a recording whose words no turn takes.
                        if (!event.speech || answer === null && utterance.collection === null) {
                            record.cancel();
                            concluded("");
                        } else {
                            utterance.state = "ending";
                            record.stop();
                        }
                        return;
                    } else fail("transcript");
                }
            } catch (error) {
                if (utterance.state !== "running") return;
                utterance.state = "concluded";
                record?.cancel();
                // An open capture carries the failure; after it closed, the
                // collection's turn does; unbound, only the service hears it.
                if (!sink.destroyed) sink.destroy(error);
                else if (collecting(c, utterance.collection)) utterance.collection.failed(keyed(error));
                else fault("speech-transcribe: " + keyed(error));
            }
        }
        void run();
        return utterance;
    }

    // Always mode and the setup check share the daemon-owned local spotter.
    // Neither starts a conversation or sends audio to a brain.
    function spotting(e) {
        if (plan.speech?.wake !== true || e.mode !== "check" && plan.kind !== "ready") fail("wake-unavailable");
        if (daemonSpeech === null) startSpeech(plan.speech);
        const { sink, frames } = captured(() => true);
        void daemonSpeech.spot(frames, { check: e.mode === "check" }).outcome.then(result => {
            if (result.kind === "checked") dispatch({ type: "voice-checked", gen: e.gen, op: e.op, result: result.result });
            else if (result.kind === "woke") dispatch({ type: "wake", gen: e.gen, op: e.op });
            // Final detector work completes after Audio closes the sink.
            else if (result.kind === "failed" && e.mode === "check")
                dispatch({ type: "voice-check-failed", gen: e.gen, op: e.op, reason: keyed(result.error) });
            else if (result.kind === "failed" && !sink.destroyed) sink.destroy(result.error);
        });
        return sink;
    }

    // Text to speech for one brain turn: one Readable for Audio, fed by the
    // adapter from released sentences. Synthesis waits on Audio; the brain
    // is read to its end, so its deadline never waits on speech.
    function speech(c) {
        const sentences = [];
        let queued = 0;
        const input = signal(), wanted = signal();
        let ended = false;
        const readable = new Readable({ objectMode: true, highWaterMark: SPEECH_CHUNKS,
            read() { wanted.notify(); } });
        // Audio reports a failed source as a failed playback, including one
        // destroyed before Audio attached its own listener.
        readable.on("error", () => {});
        let output = null;
        // A flush or a stopped turn closes the stream: the request in flight
        // ends now, not when its next audio arrives.
        readable.once("close", () => { ended = true; input.notify(); wanted.notify(); void output?.return?.(); });
        const sentenceInput = { [Symbol.asyncIterator]() { return { async next() {
            for (;;) {
                if (sentences.length !== 0) {
                    const value = sentences.shift();
                    queued -= value.item.content.length;
                    return { value: value.item, done: false };
                }
                if (ended) return { value: undefined, done: true };
                await input.wait();
            }
        }, async return() { ended = true; return { value: undefined, done: true }; } }; } };
        async function pump() {
            output = (c.spoken ?? c.speech).speak(sentenceInput, c.plan.speech.speaker)[Symbol.asyncIterator]();
            try {
                for (;;) {
                    const step = await output.next();
                    if (readable.destroyed) { void output.return?.(); return; }
                    if (step.done) { readable.push(null); return; }
                    if (!readable.push(step.value)) await wanted.wait();
                }
            } catch (error) { readable.destroy(error); }
        }
        void pump();
        // Lines still waiting for synthesis; a reply or a newer line drops them.
        function dropLines() {
            for (let at = sentences.length - 1; at >= 0; at--) {
                if (!sentences[at].line) continue;
                queued -= sentences[at].item.content.length;
                sentences.splice(at, 1);
            }
        }
        return {
            readable, handed: false,
            queue(item) {
                if (queued + item.content.length > SENTENCE_TEXT) fail("speech-queue");
                queued += item.content.length;
                sentences.push({ item, line: false });
                input.notify();
            },
            // A line joins the stream behind what synthesis has taken; a newer
            // line replaces one that still waits, so at most one waits.
            queueLine(items) {
            dropLines();
                for (const item of items) {
                    if (queued + item.content.length > SENTENCE_TEXT) fail("speech-queue");
                    queued += item.content.length;
                    sentences.push({ item, line: true });
                }
                input.notify();
            },
            dropLines,
            end() { ended = true; input.notify(); }
        };
    }

    function say(c, turn, sentence, labels = [...turn.labels]) {
        if (turn.stopped) return;
        // The answer drops every line that has not started; one that plays
        // finishes first, as Session holds the reply behind it.
        turn.pendingLine = null;
        turn.waitingLine = null;
        const item = Policy.item(sentence, labels);
        if (c.live !== null) {
            c.live.commentary(turn.delegation, item);
            return;
        }
        transfer(c, turn, item, () => {
            if (turn.speech === null) {
                turn.speech = speech(c);
            }
            turn.speech.dropLines();
            if (!turn.speaking) {
                turn.speaking = true;
                clearProgress(turn);
                turn.done("play", { interruptible: true });
            }
            turn.speech.queue(item);
        });
        caption(c, turn, sentence);
    }

    function normalizedLine(text) {
        return text.toLowerCase().replace(/[.!?]+$/u, "").replace(/\s+/gu, " ").trim();
    }

    // A line, the acknowledgement or a progress line, is Jarvis's word while
    // the brain works, never its reply: it leaves through the reply's release
    // and audit, is never repeated in a turn, and a secret is never spoken.
    // While the working sound's stream is open the line joins it. Otherwise
    // it plays in a stream of its own, which Session admits as feedback, so
    // the microphone opens again once it has played; a line asked for while
    // one plays waits, replacing an older waiting one.
    function line(c, turn, text, labels) {
        if (turn.stopped || turn.speaking || turn.replyStarted || Redact.secret(text)) return false;
        const key = normalizedLine(text);
        if (key === "" || turn.lines.has(key)) return false;
        try {
            const speakable = Speakable.create(LANGUAGE);
            const sentences = [...speakable.push(text), ...speakable.finish()];
            if (sentences.length === 0) return false;
            // Only a stream Session admitted plays; a line it refused, as
            // while an approval is held, leaves no stream and the next line
            // asks again.
            if (c.live === null && turn.lineStream !== null) {
                turn.waitingLine = { text, labels };
                return true;
            }
            turn.lines.add(key);
            const items = sentences.map(sentence => Policy.item(sentence, labels));
            // A line is no reply the user waits for: one the gate would ask
            // about or withhold is not spoken, and the turn goes on.
            if (items.some(item => Policy.release(item, c.recipients, c.grants).kind !== "send")) return false;
            // A duplex voice captions the words it speaks, as for a reply.
            if (c.live !== null) {
                for (const item of items) c.live.commentary(turn.delegation, item, { line: true });
                return true;
            }
            for (const [at, item] of items.entries()) {
                transfer(c, turn, item, () => {});
                caption(c, turn, sentences[at]);
            }
            const playing = state().playback;
            if (turn.speech !== null && playing.kind === "feedback" && playing.cue === "working" && playing.source === turn.op) {
                turn.linePrefix += (turn.linePrefix === "" ? "" : " ") + sentences.join(" ");
                turn.speech.queueLine(items);
                return true;
            }
            turn.pendingLine = items;
            turn.done("feedback", { cue: "line" });
            return true;
        } catch (error) {
            failed(c, turn, error);
            return false;
        }
    }

    // Session admitted the turn's line: its stream is made once, holds the
    // line alone and ends with it.
    function lineAdmitted(c, turn) {
        const stream = speech(c);
        turn.lineStream = stream;
        stream.queueLine(turn.pendingLine ?? []);
        turn.pendingLine = null;
        stream.end();
    }

    // The words of the working sound's stream that were lines, not the reply.
    function withoutLinePrefix(turn, text) {
        if (text === "" || turn.linePrefix === "") return text;
        if (turn.linePrefix.startsWith(text)) return "";
        return text.startsWith(turn.linePrefix + " ") ? text.slice(turn.linePrefix.length + 1) : text;
    }

    function progress(c, turn) {
        if (clock === undefined) return;
        turn.progressTimer = clock.set(() => {
            turn.progressTimer = null;
            turn.progressDue = true;
            if (conversation !== c || turn.stopped || turn.speaking || !session.live(state(), turn, "turn", ["thinking"])) return;
            if (turn.step !== null) line(c, turn, turn.step, [...turn.labels]);
        }, PROGRESS_AFTER_MS);
    }

    function stated(c, turn, stream) {
        for (const step of stream.steps()) {
            turn.step = step;
            if (turn.progressDue) line(c, turn, step, [...turn.labels]);
        }
    }

    // A failover's old net owner takes no new request: the voice asks c.net
    // at each sentence. A sentence ElevenLabs is still streaming was
    // released under the old set and keeps its transport to its last chunk;
    // the owner closes once it ends, or at end(). A sentence queued before
    // the switch but not yet requested is judged against the new set, where
    // the old grants fail: one with a label only a grant released is not
    // spoken, and the user hears the failover line next.
    function retire(c, door) {
        if (c.spoken === null) {
            door.close();
            return;
        }
        c.retired.add(door);
        void c.spoken.idle(door).then(() => {
            if (c.retired.delete(door)) door.close();
        });
    }

    async function switchBrain(c) {
        const old = c.plan.brain;
        c.entry += 1;
        if (c.entry >= c.plan.entries.length) return null;
        c.plan.brain = c.plan.entries[c.entry];
        cancelRelease(c);
        c.late.clear();
        c.results = [];
        c.heard = null;
        if (c.brain !== null) {
            const brain = c.brain;
            c.brain = null;
            await brain.cancel();
            brain.close();
        }
        cancelRelease(c);
        if (conversation !== c) return null;
        if (c.live !== null && c.liveOpen !== null) c.live.port.release();
        retire(c, c.net);
        c.grants.length = 0;
        c.decisions.clear();
        const facts = policy();
        c.recipients = Policy.recipients({ conversation: "jarvis-" + c.gen + "-" + c.entry, profile: facts.profile,
            cloudVision: facts.cloudVision, brain: c.plan.brain.recipient, speech: c.plan.speech.recipients });
        c.net = Net.create(c.recipients);
        c.guidance = null;
        c.owner = null;
        if (c.live !== null && c.liveOpen !== null) c.live.port.open(c.liveOpen.e, c.liveOpen.events);
        return { from: brainLabel(old), to: brainLabel(c.plan.brain) };
    }

    // Jarvis's words are the sentences released for speech. Each one grows
    // the turn's caption segment under the conversation's rising revision; a
    // segment at the wire's bound closes and the rest starts the next one.
    function caption(c, turn, sentence) {
        let text = sentence.replace(/[\x00-\x1f\x7f]/g, " ");
        // A segment with no room for the separator and one character closes.
        if (turn.caption.length + 1 >= captionLimit) concluded(c, turn);
        if (turn.caption !== "") text = " " + text;
        while (text !== "") {
            if (turn.caption.length === captionLimit) {
                concluded(c, turn);
                text = text.trimStart();
                continue;
            }
            const room = captionLimit - turn.caption.length;
            turn.caption += text.slice(0, room);
            text = text.slice(room);
            captioned(c, turn, "partial");
        }
    }
    function captioned(c, turn, stage) {
        turn.done("transcript", { role: "assistant", text: turn.caption, stage, rev: ++c.rev });
    }
    // A reply's end, or a full segment, closes the open segment.
    function concluded(c, turn) {
        if (turn.caption !== "") captioned(c, turn, "final");
        turn.caption = "";
    }

    function stop(turn) {
        turn.stopped = true;
        turn.pendingLine = null;
        turn.waitingLine = null;
        quiet(turn);
        clearProgress(turn);
        turn.speech?.end();
    }
    function quiet(turn) {
        if (turn.feedbackTimer !== null) clock.clear(turn.feedbackTimer);
        turn.feedbackTimer = null;
    }
    function clearProgress(turn) {
        if (turn.progressTimer !== null && turn.progressTimer !== undefined) clock.clear(turn.progressTimer);
        turn.progressTimer = null;
    }
    function working(c, turn) {
        if (c.live !== null || state().settings.sounds !== true || clock === undefined) return;
        turn.feedbackTimer = clock.set(() => {
            turn.feedbackTimer = null;
            if (conversation !== c || turn.stopped || !session.live(state(), turn, "turn", ["thinking"])) return;
            dispatch({ type: "feedback", gen: turn.gen, op: turn.op });
        }, WORKING_AFTER_MS);
    }
    function failed(c, turn, error) {
        if (turn.stopped) return;
        stop(turn);
        if (c.turn === turn) c.turn = null;
        concluded(c, turn);
        const reason = keyed(error);
        // The history bound ends the conversation cleanly; any other failure
        // is a fault.
        turn.done(reason === "brain=context-limit" ? "brain-ended" : "brain-failed", { reason });
    }

    // The brain's guidance with the home text as it reads now. No hello
    // follows an edit inside the folder, so an entry the layout makes can be
    // gone from a home judged ready, the Jarvis package after kendex's render
    // is removed among them: that miss judges the home once and reads it again.
    function guidanceNow(c) {
        const folder = homePath();
        if (folder === null) return c.plan.brain.guidance;
        try { return c.plan.brain.guidance.withHome(folder); }
        catch (error) { if (error.message !== "jarvis: home=absent") throw error; }
        rejudge();
        const judged = home();
        if (judged.kind !== "ready") throw new Error("jarvis: " + (judged.kind === "refused" ? judged.cause : "home=absent"));
        return c.plan.brain.guidance.withHome(judged.path);
    }

    function openBrain(c, owner, done) {
        try { c.guidance = guidanceNow(c); }
        catch (error) {
            if (homeCause(error) === null) throw error;
            done("brain-failed", { reason: keyed(error) });
            return false;
        }
        // Off the runner's drain, the judgement's snapshot can end the
        // conversation at once, its turn stopped with it.
        if (conversation !== c) return false;
        c.brain = DRIVERS[c.plan.brain.provider.driver].create({ provider: c.plan.brain.provider,
            model: c.plan.brain.model, effort: c.plan.brain.effort, net: c.net, recipients: c.recipients, key: c.plan.brain.key,
            account: c.plan.brain.account, gen: c.gen, harness });
        c.brain.start({ instructions: c.guidance.instructions, tools: router.offer() });
        c.owner = owner;
        return true;
    }

    async function requestRelease(c, identity, labels) {
        const needed = labels.filter(label => !c.decisions.has(label));
        if (needed.length === 0) return;
        if (c.releasePending !== null) fail("release-busy");
        const names = [...new Set([c.recipients.brain, ...c.recipients.speech]
            .filter(recipient => recipient.kind === "network" && !Net.endpoint(recipient.origin).loopback)
            .map(recipient => PROVIDERS.find(row => row.id === recipient.provider)?.label ?? recipient.provider))];
        const sources = { clipboard: "clipboard text", file: "file text", screen: "screen content",
            web: "web page text", command: "command output", agent: "agent output" };
        const text = "Send " + needed.map(label => sources[label]).join(" and ") + " to " + names.join(" and ") + "?";
        const id = crypto.randomUUID();
        const digest = crypto.createHash("sha256").update(JSON.stringify({ labels: needed, recipients: c.recipients })).digest("hex");
        record(c, identity, needed, "ask");
        let resolve;
        const answered = new Promise(done => { resolve = done; });
        c.releasePending = { id, labels: needed, identity, recipients: c.recipients, resolve };
        dispatch({ type: "approval", gen: identity.gen, op: identity.op, purpose: "release", id, digest,
            text, physical: false, tool: "release", timeoutMs: session.RESPONSE_TIMEOUT_MS, cancellable: false });
        // A router outcome can request this while the runner drains effects.
        // Its queued proposal must be reduced before we inspect the hold.
        await Promise.resolve();
        const held = state().approval;
        if (c.releasePending?.id === id && (held.kind !== "held" || held.id !== id)) {
            c.releasePending = null;
            resolve(false);
        }
        await answered;
    }

    function decided(e, accepted) {
        const c = conversation;
        const pending = c?.releasePending;
        if (pending === undefined || pending === null || pending.id !== e.id || c.gen !== e.gen) return;
        if (state().turn.kind !== "thinking" || state().turn.op !== pending.identity.op) {
            c.releasePending = null;
            pending.resolve(false);
            return;
        }
        if (pending.recipients !== c.recipients) {
            c.releasePending = null;
            pending.resolve(false);
            return;
        }
        const grant = { recipients: pending.recipients, labels: pending.labels };
        const result = audit.before({ ...releaseEvent(c, pending.identity, pending.labels,
            accepted ? "send" : "withhold", "pending"), confirmed: accepted ? e.confirmed === "voice" ? "voice" : "physical" : "none" }, () => {
            for (const label of pending.labels) c.decisions.add(label);
            if (accepted) c.grants.push(grant);
        });
        c.releasePending = null;
        pending.resolve(result.kind === "started" && accepted);
    }

    async function respond(c, turn, request) {
        try {
            let reply = c.brain.send(request, c.grants);
            if (reply.release.needed.some(label => !c.decisions.has(label))) {
                // send() only prepares a request. Returning its unstarted stream
                // releases that slot without putting an unsent turn in history.
                await reply.events.return();
                await requestRelease(c, turn, reply.release.needed);
                if (turn.stopped || conversation !== c) return;
                reply = c.brain.send(request, c.grants);
            }
            if (reply.release.needed.length !== 0) record(c, turn, reply.release.needed, "withhold");
            if (reply.release.withheld.length !== 0) record(c, turn, reply.release.withheld, "withhold");
            for (const label of reply.release.labels) turn.labels.add(label);
            // History can carry an earlier turn's untrusted content.
            router.observe(turn, reply.release.labels);
            const events = reply.events[Symbol.asyncIterator]();
            const text = Speakable.create(LANGUAGE, { tools: TOOL_NAMES });
            const calls = [];
            // A request with no released content refuses before it is sent.
            let step = await (reply.release.labels.length === 0 ? events.next()
                : transfer(c, turn, Policy.item("", reply.release.labels), () => events.next()));
            for (; !step.done; step = await events.next()) {
                if (turn.stopped) return;
                const event = step.value;
                switch (event.kind) {
                case "text":
                    brainText?.write(turn, event.text);
                    // Only a sentence for speech ends the wait the working
                    // sound covers: text Speakable keeps silent, as before a
                    // tool call, leaves the sound due.
                    const sentences = text.push(event.text);
                    if (sentences.length !== 0) turn.replyStarted = true;
                    for (const sentence of sentences) {
                        quiet(turn);
                        say(c, turn, sentence);
                    }
                    stated(c, turn, text);
                    break;
                case "tool-call": calls.push(event); break;
                case "done":
                    quiet(turn);
                    // History holds the calls once done is read: an interrupt
                    // from here on must answer them.
                    if (event.reason === "tool-calls") {
                        turn.calls = calls;
                        turn.phase = "routing";
                    }
                    const rest = text.finish();
                    if (rest.length !== 0) turn.replyStarted = true;
                    for (const sentence of rest) say(c, turn, sentence);
                    stated(c, turn, text);
                    if (turn.stopped) return;
                    if (event.reason === "tool-calls") next(c, turn);
                    else {
                        clearProgress(turn);
                        turn.phase = "done";
                        c.turn = null;
                        turn.speech?.end();
                        concluded(c, turn);
                        turn.done("brain-done");
                    }
                    return;
                default: fail("brain-event");
                }
            }
            fail("brain-unfinished");
        } catch (error) {
            const reason = keyed(error);
            if (!turn.stopped && failoverCause(reason) && !(endedCause(reason) && turn.replyStarted) && c.entry + 1 < c.plan.entries.length) {
                const resend = !turn.routed && !turn.speaking && typeof turn.resendText === "string";
                let switched = await switchBrain(c);
                while (switched !== null && !turn.stopped && conversation === c) {
                    try {
                        if (!openBrain(c, turn.owner, turn.done)) return;
                    } catch (openError) {
                        if (c.entry + 1 >= c.plan.entries.length) {
                            failed(c, turn, openError);
                            return;
                        }
                        switched = await switchBrain(c);
                        continue;
                    }
                    turn.labels.add("desktop");
                    quiet(turn);
                    say(c, turn, failoverLine(switched.from, switched.to, resend), ["desktop"]);
                    if (resend) {
                        turn.phase = "streaming";
                        void respond(c, turn, { kind: "user", items: [Policy.item(turn.resendText, ["speech"])] });
                    } else {
                        turn.phase = "done";
                        c.turn = null;
                        turn.speech?.end();
                        concluded(c, turn);
                        turn.done("brain-done");
                    }
                    return;
                }
                return;
            }
            failed(c, turn, error);
        }
    }

    // Route a reply's calls one at a time through the router; their results
    // return through outcome() and answer the reply in one tool-results turn.
    function next(c, turn) {
        if (turn.stopped) return;
        const call = turn.calls.find(value => !turn.answers.has(value.id));
        if (call === undefined) {
            turn.phase = "streaming";
            const after = c.guidance.afterToolResult;
            void respond(c, turn, { kind: "tool-results", ...(after === null ? {} : { instructions: after }),
                results: turn.calls.map(value => ({ id: value.id, ...turn.answers.get(value.id) })) });
            return;
        }
        turn.routing = call;
        router.route(call, { gen: turn.gen, op: turn.op });
    }

    // A relay turn: one fixed task line, never a brain request. relay.ask is
    // the prompt the line asks, or null; relay.about is the prompt an answer
    // turn asks again; relay.line is TaskVoice's own line,
    // null for the engine's reply to an answer; relay.done is set once the
    // line was heard to its end or reported back.
    // A short command Tools.match names: one call the router judges, audits
    // and reads back inside the thinking turn Session opened, with no model
    // call. Jarvis says what became of it, and the brain's next request
    // carries an account of it, as a late result does. A call that did not
    // act (failed, or refused) hands the same words to the brain with that
    // account, so the brain can find another way.
    const FAST_LINES = { completed: "Done.", unknown: "I asked for it, but I could not confirm it." };
    function fastTurn(c, e, done, call) {
        if (c.turn !== null) fail("brain-busy");
        const request = { kind: "tool-call", id: crypto.randomUUID(), tool: call.id, arguments: call.args, proposer: "matcher" };
        const turn = { gen: e.gen, op: e.op, done, labels: new Set(["desktop"]), speech: null, stopped: false, speaking: false,
            delegation: e.delegation, feedbackTimer: null, relay: null, phase: "fast", calls: [request], answers: new Map(),
            routing: request, caption: "", fast: { e } };
        c.turn = turn;
        c.last = turn;
        router.route(request, { gen: turn.gen, op: turn.op });
    }
    function fastAccount(text, call, outcome, item) {
        return Policy.summary("[done without you] The user said " + JSON.stringify(text) + ". Jarvis ran " + call.tool + " "
            + JSON.stringify(call.arguments) + " with no model call, which ended " + outcome + ": " + item.content,
        [Policy.item(text, ["speech"]), item]);
    }
    function fastDone(c, turn, outcome, item) {
        const call = turn.routing;
        turn.routing = null;
        c.results.push(fastAccount(turn.fast.e.text, call, outcome, item));
        if (!Object.hasOwn(FAST_LINES, outcome)) {
            c.turn = null;
            c.unmatched = turn.op;
            brain.send(turn.fast.e, turn.done);
            return;
        }
        fixedLine(c, turn, FAST_LINES[outcome]);
    }
    // Jarvis's own words as the whole turn: spoken, captioned and done.
    function fixedLine(c, turn, text) {
        try {
            const line = Speakable.create(LANGUAGE);
            for (const sentence of [...line.push(text), ...line.finish()]) say(c, turn, sentence);
            if (turn.stopped) return;
            turn.phase = "done";
            c.turn = null;
            turn.speech?.end();
            concluded(c, turn);
            turn.done("brain-done");
        } catch (error) { failed(c, turn, error); }
    }

    function relayTurn(c, e, done, relay) {
        if (c.turn !== null) fail("brain-busy");
        const turn = { gen: e.gen, op: e.op, done, labels: new Set(), speech: null, stopped: false, speaking: false,
            delegation: undefined, feedbackTimer: null, phase: "relay", calls: [], answers: new Map(), routing: null,
            caption: "", relay };
        c.turn = turn;
        c.last = turn;
        return turn;
    }

    // The line leaves through the brain's own path: the release gate,
    // Speakable, captions and playback. A line the gate keeps from the
    // conversation's recipients goes to TaskVoice instead. Speakable reads it
    // as text, not as a brain's reply: a prompt holds the command the user
    // is asked to allow, as JSON, and every word of it is theirs to hear.
    async function relayLine(c, turn, text, labels) {
        try {
            if (tasks === null) fail("tasks-port");
            const item = Policy.item(text, labels);
            let judged = Policy.release(item, c.recipients, c.grants);
            if (judged.kind === "ask") {
                await requestRelease(c, turn, judged.needed);
                if (turn.stopped || conversation !== c) return;
                judged = Policy.release(item, c.recipients, c.grants);
            }
            if (judged.kind === "send") {
                for (const label of item.labels) turn.labels.add(label);
                const speakable = Speakable.create(LANGUAGE);
                for (const sentence of [...speakable.push(text), ...speakable.finish()]) say(c, turn, sentence);
                if (turn.stopped) return;
            } else {
                record(c, turn, judged.kind === "ask" ? judged.needed : judged.labels, "withhold");
                turn.relay.done = true;
                tasks.withheld(c.gen, text, turn.relay.ask ?? turn.relay.about ?? null);
            }
            turn.phase = "done";
            c.turn = null;
            turn.speech?.end();
            concluded(c, turn);
            turn.done("brain-done");
        } catch (error) { failed(c, turn, error); }
    }

    // A relay line that ended before it was heard to its end: a prompt is
    // asked again, TaskVoice's own line is notified. Each line reports once.
    function unheard(c, turn) {
        const relay = turn.relay;
        if (!relay || relay.done) return;
        relay.done = true;
        if (relay.ask !== null) tasks.interrupted(c.gen, relay.ask);
        else if (relay.line !== null) tasks.withheld(c.gen, relay.line, null);
    }

    // The prompt the conversation asked, while its hook still holds it.
    // Answered elsewhere, expired or withdrawn, it no longer takes words.
    function relayPrompt(c) {
        const prompt = tasks.held().find(item => item.task === c.relay.task && item.id === c.relay.prompt) ?? null;
        if (prompt === null) c.relay = null;
        return prompt;
    }

    // The user's words answer the held prompt through the daemon's port,
    // never the brain; Jarvis says what became of them. answer is null for
    // words that answer nothing, which ask the prompt once more.
    function answerTurn(c, e, done, prompt, answer) {
        const turn = relayTurn(c, e, done, { ask: null, line: null, done: false });
        let reply;
        try {
            reply = answer === null ? TaskVoice.retry(prompt)
                : TaskVoice.answered(prompt, tasks.answer(prompt.task, prompt.id, answer));
        } catch (error) { failed(c, turn, error); return; }
        if (answer === null) c.retried = c.relay;
        // A re-ask carries the prompt, so a withheld one is notified as that prompt's card.
        if (reply.labels.includes("agent")) turn.relay.about = c.relay;
        if (!reply.keep) c.relay = null;
        void relayLine(c, turn, reply.text, reply.labels);
    }

    // Only the brain's own reply has a heard prefix to report.
    function heard(c, turn, text) {
        if (turn.fast !== undefined) return;
        c.heard = { turn, labels: [...turn.labels], text };
    }
    // A duplex reply's heard account for an interruption, or null when the
    // interruption cuts nothing: the session answers another request, or the
    // turn ended and all its words played out.
    function cut(c, turn) {
        if (!c || c.live === null || !turn) return null;
        const account = c.live.heard(turn.delegation);
        return account === null || turn.phase === "done" && !account.pending ? null : account;
    }
    function heardItem(value) {
        return Policy.item(value.text === ""
            ? "[interrupted] The user heard none of your last reply."
            : "[interrupted] The user heard only this part of your last reply: \"" + value.text + "\"", value.labels);
    }
    // An interrupted call's real outcome reaches the next user turn, labelled
    // as its result is.
    function lateItem(call, outcome, item) {
        return Policy.summary("[late result] Your interrupted call " + call.tool + " ended " + outcome + ": "
            + item.content, [item]);
    }

    const brain = {
        send(e, done) {
            const c = current(e.gen);
            // A voice preview: one fixed sentence in the chosen voice, never
            // a brain request. As a relay line it leaves the brain no heard
            // prefix, and as a done one no task line to report back.
            if (e.preview === true) {
                const turn = relayTurn(c, e, done, { ask: null, line: null, done: true });
                turn.labels.add("desktop");
                fixedLine(c, turn, PREVIEW_LINE);
                return;
            }
            if (e.relay !== undefined) {
                const turn = relayTurn(c, e, done, { ask: e.relay.ask, line: e.relay.ask === null ? e.relay.text : null, done: false });
                void relayLine(c, turn, e.relay.text, e.relay.ask === null ? ["desktop"] : ["agent"]);
                return;
            }
            if (c.relay !== null && e.text.trim() !== "") {
                let prompt, answer = null;
                try {
                    prompt = relayPrompt(c);
                    if (prompt !== null) answer = TaskVoice.answerOf(prompt, e.text);
                } catch (error) {
                    failed(c, relayTurn(c, e, done, { ask: null, line: null, done: false }), error);
                    return;
                }
                // After one re-ask, words that again answer nothing are the
                // user's own turn; TaskVoice may ask the prompt later.
                if (prompt !== null && answer === null && c.retried === c.relay) {
                    tasks.released(c.gen, c.relay);
                    c.relay = null;
                } else if (prompt !== null) {
                    answerTurn(c, e, done, prompt, answer);
                    return;
                }
            }
            // A fast call that did not act hands its turn back here unmatched.
            const call = c.unmatched === e.op ? null : Tools.match(e.text);
            if (call !== null) {
                fastTurn(c, e, done, call);
                return;
            }
            if (c.brain === null) {
                // The home text is read at each conversation's first turn, so
                // the user's last edit is the one a brain gets. A text that
                // outgrew its bound since the setup answer fails this turn.
                if (!openBrain(c, e.owner, done)) return;
            } else if (c.owner !== e.owner) fail("brain-owner");
            if (c.turn !== null) fail("brain-busy");
            const turn = { gen: e.gen, op: e.op, done, labels: new Set(), speech: null, stopped: false, speaking: false, delegation: e.delegation,
                feedbackTimer: null, relay: null,
                phase: "queued", calls: [], answers: new Map(), routing: null, caption: "", resendText: e.text, owner: e.owner,
                routed: false, replyStarted: false, progressTimer: null, progressDue: false, step: null, lines: new Set(),
                linePrefix: "", lineStream: null, pendingLine: null, waitingLine: null };
            if (e.text.trim() === "") {
                done("brain-done");
                return;
            }
            c.turn = turn;
            c.last = turn;
            line(c, turn, Speakable.acknowledgement(e.text), ["speech"]);
            progress(c, turn);
            working(c, turn);
            const items = [];
            if (c.heard !== null) items.push(heardItem(c.heard));
            c.heard = null;
            items.push(...c.results);
            c.results = [];
            items.push(Policy.item(e.text, ["speech"]));
            // A replaced duplex delegation waits for the prior adapter's cancellation.
            void c.quiet.then(() => {
                if (!turn.stopped && conversation === c) {
                    turn.phase = "streaming";
                    return respond(c, turn, { kind: "user", items });
                }
            });
        },
        cancel(e, done) {
            const c = conversation;
            if (c === null || c.gen !== e.gen) {
                (retired !== null && retired.gen === e.gen ? retired.closed : Promise.resolve()).then(() => done());
                return;
            }
            const turn = c.turn;
            if (turn === null || turn.op !== e.target) { done(); return; }
            c.turn = null;
            stop(turn);
            // A relay turn was never the brain's: it hears no prefix of it.
            if (c.live === null && turn.relay === null) heard(c, turn, "");
            unheard(c, turn);
            const routing = turn.phase === "routing";
            // A fast call that already started reports its real outcome to
            // the brain's next request.
            if (turn.phase === "fast" && turn.routing !== null) c.late.set(turn.routing.id, { call: turn.routing, op: turn.op, fast: turn.fast });
            // A queued or relay turn owns no adapter request. Its prior cancellation
            // still blocks the next turn and this cancellation's acknowledgement.
            c.quiet = (turn.phase === "fast" || turn.phase === "queued" || turn.phase === "relay" || c.brain === null ? c.quiet : c.brain.cancel()).then(() => {
                // Every call in history gets an answer, so the next request is
                // valid. A running call's real outcome follows on a later turn.
                if (routing && c.brain !== null) c.brain.record({ kind: "tool-results", results: turn.calls.map(call => {
                    if (turn.answers.has(call.id)) return { id: call.id, ...turn.answers.get(call.id) };
                    if (turn.routing === call) {
                        c.late.set(call.id, { call, op: turn.op });
                        return router.interrupted(call, "running");
                    }
                    return router.interrupted(call, "not-started");
                }) });
                done();
            });
        },
        routed(e) {
            const c = conversation;
            const turn = c?.turn;
            if (turn !== null && turn !== undefined && turn.gen === e.gen && turn.op === e.op) turn.routed = true;
        },
        close(e) {
            const c = conversation;
            if (c === null || c.owner !== e.target || c.brain === null) return;
            c.brain.close();
            c.brain = null;
            c.owner = null;
        },
        outcome(value) {
            const c = conversation;
            if (c === null || c.gen !== value.gen || value.results.length !== 1) return;
            const { id, item, image } = value.results[0];
            const turn = c.turn;
            if (turn !== null && turn.op === value.op && turn.phase === "fast" && turn.routing?.id === id) {
                fastDone(c, turn, value.outcome, item);
                return;
            }
            if (turn !== null && turn.op === value.op && turn.phase === "routing" && turn.routing?.id === id) {
                // A result's image stays with its text for the tool-results turn.
                turn.answers.set(id, image === undefined ? { item } : { item, image });
                turn.routing = null;
                next(c, turn);
                return;
            }
            const late = c.late.get(id);
            if (late === undefined || late.op !== value.op) return;
            c.late.delete(id);
            if (late.fast !== undefined) c.results.push(fastAccount(late.fast.e.text, late.call, value.outcome, item));
            else c.results.push(lateItem(late.call, value.outcome, item));
        }
    };

    // Audio's flush report carries the heard prefix of this turn's speech.
    // Natural completion drained every sentence, so it changes nothing.
    function playback(port) {
        return {
            start(e, done, failed) {
                const c = conversation;
                const turn = c?.last;
                return port.start(e, (...result) => {
                    // A prompt heard to its end holds the conversation's
                    // next words; a flushed one is asked again later.
                    if (turn?.relay && conversation === c && c.last === turn && turn.op === e.source && turn.phase === "done") {
                        turn.relay.done = true;
                        if (turn.relay.ask !== null) c.relay = turn.relay.ask;
                    }
                    if (conversation === c) c?.live?.played(e.source);
                    done(...result);
                }, failed);
            },
            flush(e, done) {
                // The report belongs to the turn being flushed. Cue-only
                // teardown must not mark its later reply as interrupted.
                const c = conversation;
                const turn = c?.last;
                // While a line's stream exists Session's playback is that
                // line's, handed to Audio or not yet: the flush ends it. Its
                // report is the line's, so a reply held behind it was heard
                // not at all.
                const flushedLine = turn !== undefined && turn !== null && turn.lineStream !== null && turn.lineStream !== undefined;
                if (flushedLine) {
                    if (!turn.lineStream.handed) turn.lineStream.readable.destroy();
                    turn.lineStream = null;
                    turn.waitingLine = null;
                }
                const speaking = turn?.speaking === true;
                // A duplex reply's account is read here: the speech port's
                // flush follows this effect and drops it. Until Audio
                // reports, the reply at the speaker counts as unheard.
                const account = cut(c, turn);
                if (account !== null) heard(c, turn, account.text(null));
                return port.flush(e, report => {
                    if (account !== null && conversation === c && c.last === turn) heard(c, turn, account.text(report));
                    const own = speaking && c.live === null && conversation === c && c.last === turn && (report === null || report.source === turn.op);
                    if (own && turn.relay === null) heard(c, turn, report === null || flushedLine ? "" : withoutLinePrefix(turn, report.heardText));
                    else if (own) unheard(c, turn);
                    done(report);
                });
            }
        };
    }

    function judge(settings) {
        plan = select(settings, accounts, directories, listed, modelOffers);
        const held = heldByHome(plan, home());
        homeHeld = held.plan !== plan;
        plan = held.plan;
        cautions = held.cautions;
        if (plan.speech?.kind === "ready" && plan.speech.lifetime === "daemon") {
            // A completed setup publication can repair an initial
            // refusal. Ordinary hellos leave that runtime unloaded.
            const published = speechState.kind === "refused" && speechState.publication !== plan.speech.publication;
            if (speechState.kind === "new" || published) startSpeech(plan.speech);
            else reargue();
        }
        return configuration();
    }

    // Read the ElevenLabs account's voices for LIST, the plan's key, once a
    // configure names it: each hello reads them again, so a voice made on
    // ElevenLabs's site since shows up, and one read runs per key at a time.
    // The read is its own recipient set, ElevenLabs alone, whose one item is
    // an empty request, released and audited as any transfer. A failed read
    // offers no voices, and the settings stay as the user left them.
    function readVoices(list) {
        const identity = JSON.stringify(list.key.reference);
        if (voiceList.identity === identity && voiceList.net !== null) return;
        voiceList.net?.close();
        const recipients = Policy.recipients({ conversation: "voices-" + (++listReads), profile: policy().profile,
            cloudVision: "never", brain: list.recipient, speech: [{ kind: "local", provider: "voice-list", account: list.recipient.account }] });
        const same = voiceList.identity === identity;
        const read = { identity, voices: same ? voiceList.voices : null, known: same ? voiceList.known : null, net: Net.create(recipients) };
        voiceList = read;
        const identityOf = { gen: state().gen, op: listReads };
        const transfer = (item, start) => {
            if (Policy.release(item, recipients).kind !== "send") fail("release-" + item.labels.join("-"));
            const result = audit.before(releaseEvent({ recipients }, identityOf, item.labels, "send", "pending"), start);
            if (result.kind !== "started") fail("audit-write");
            return result.value;
        };
        void ElevenLabs.voices({ provider: list.provider, net: read.net, key: list.key, transfer, clock })
            .catch(error => {
                // A key reader's cause keeps its own prefix.
                const reason = keyed(error);
                log(/^jarvis-[a-z]+: /.test(reason) ? reason : "jarvis: " + reason);
                return [];
            })
            .then(voices => {
                read.net.close();
                if (closed || voiceList !== read) return;
                // A failed read keeps the ids an earlier read listed, so the
                // chosen voice still speaks.
                voiceList = { identity, voices, known: voices.length !== 0 ? new Set(voices.map(voice => voice.value)) : read.known, net: null };
                // configure's own caller ends the daemon on a judge's
                // throw; this answer comes later, so it hands its own over.
                try {
                    if (lastSettings !== null) configured(judge(lastSettings));
                } catch (error) { fatal(error); }
            });
    }

    function readModels(lists) {
        for (const { judge: account, id } of lists) {
            if (modelReads.has(id)) continue;
            const read = { stop: new AbortController(), answer: { kind: "none" } };
            modelReads.set(id, read);
            account.readOffers(id, read.stop.signal, audit).then(answer => {
                if (closed || modelReads.get(id) !== read) return;
                read.answer = answer;
                try { configured(judge(lastSettings)); } catch (error) { fatal(error); }
            }).catch(error => {
                if (closed || modelReads.get(id) !== read) return;
                fatal(error);
            });
        }
    }

    return Object.freeze({
        /** Select setup admission; healthy loading can accept bounded capture. */
        configure(settings) {
            const identity = JSON.stringify([[settings.brain, settings.model ?? ""],
                ...(Array.isArray(settings.fallbacks) ? settings.fallbacks : []).map(row => [row?.brain, row?.model ?? ""])]);
            if (identity !== modelsFor || modelsHeld()) cancelModels();
            modelsFor = identity;
            lastSettings = settings;
            const answer = judge(settings);
            readModels(plan.modelLists);
            if (plan.list !== null && plan.list !== undefined) readVoices(plan.list);
            return answer;
        },
        /**
         * Whether the last configure left the home folder holding the plan.
         * No hello follows an edit inside the folder, so the daemon judges
         * it again at the user's next request.
         */
        homeHeld: () => homeHeld,
        /**
         * Whether the ElevenLabs voice holds the plan with a failed read of
         * the account's voices. No hello follows the network's return, so
         * the daemon configures again at the user's next request, which
         * reads the list again.
         */
        voicesHeld: () => plan.speech?.kind === "unconfigured" && plan.speech.cause === "speech=elevenlabs-voice",
        // A failed local catalog or a model no longer offered is read again
        // by the daemon's existing Talk judgement, after the server recovers.
        modelsHeld,
        checkReady: () => plan.speech?.wake === true && daemonSpeech?.status().kind === "ready",
        observe(s) {
            if (conversation !== null && (s.gen !== conversation.gen || s.conversation.kind === "ended")) end();
            if (conversation?.collection !== null && conversation?.collection !== undefined
                    && !collecting(conversation, conversation.collection)) {
                conversation.collection.utterance?.abort();
                conversation.collection = null;
            }
            if (s.playback.kind === "feedback") {
                const c = current(s.gen);
                if (s.playback.cue === "start" && c.feedback === null)
                    c.feedback = { source: s.playback.source, readable: Readable.from([earcon("start")],
                        { objectMode: true, highWaterMark: SPEECH_CHUNKS }) };
                if (s.playback.cue === "working" && c.turn !== null && c.turn.op === s.playback.source
                        && c.turn.speech === null) {
                    c.turn.speech = speech(c);
                    c.turn.speech.readable.push(earcon("working"));
                }
                if (s.playback.cue === "line" && c.turn !== null && c.turn.op === s.playback.source
                        && c.turn.lineStream === null) lineAdmitted(c, c.turn);
            } else if (conversation?.feedback !== null && conversation?.feedback !== undefined) {
                conversation.feedback.readable.destroy();
                conversation.feedback = null;
            }
            // A line has played once Session's playback is idle again or
            // plays the reply it held; the waiting line then asks for its own.
            // A flush is the flush port's to settle.
            const lined = conversation?.turn;
            if (lined && lined.lineStream && s.playback.kind !== "flushing"
                    && !(s.playback.kind === "feedback" && s.playback.cue === "line" && s.playback.source === lined.op)) {
                lined.lineStream = null;
                const waiting = lined.waitingLine;
                lined.waitingLine = null;
                if (waiting !== null && session.live(s, lined, "turn", ["thinking"])) line(conversation, lined, waiting.text, waiting.labels);
            }
            const turn = conversation?.turn;
            if (turn && (s.settings.sounds !== true || !session.live(s, turn, "turn", ["thinking"])
                    || s.approval.kind !== "none")) quiet(turn);
            // A cue-only stream cannot wait for sentences while the user
            // answers approval. Later speech gets a new stream after flush.
            if (turn && (s.settings.sounds !== true || s.approval.kind === "held")
                    && !turn.speaking && turn.speech !== null) {
                turn.speech.end();
                turn.speech.readable.destroy();
                turn.speech = null;
            }
            if (s.playback.kind !== "idle") idleAt = null;
            else if (idleAt === null && clock !== undefined) idleAt = clock.now();
        },
        release: {
            confirmed: e => decided(e, true),
            ended: e => decided(e, false),
            refused(e) {
                const c = conversation;
                const pending = c?.releasePending;
                if (pending === undefined || pending === null || c.gen !== e.gen) return;
                const result = audit.record({ ...releaseEvent(c, pending.identity, pending.labels, "withhold", "cancelled"),
                    refusal: e.reason });
                if (result.kind !== "recorded") throw new Error("jarvis: audit=write cause=" + result.cause);
            },
            async prepare(value, recipients) {
                const c = conversation;
                if (c === null || c.recipients !== recipients || c.gen !== value.gen) return null;
                const item = value.results[0].item;
                const judgements = [Policy.release(item, recipients, c.grants)];
                const image = value.results[0].image;
                if (image !== undefined) judgements.push(Policy.release(image.item, recipients, c.grants));
                const needed = [...new Set(judgements.filter(judge => judge.kind === "ask").flatMap(judge => judge.needed))];
                if (needed.length !== 0) await requestRelease(c, value, needed);
                if (conversation !== c || state().turn.kind !== "thinking" || state().turn.op !== value.op) return null;
                return c.grants;
            }
        },
        /** Whether the conversation's brain, or the next one's, takes images. */
        images() {
            const current = conversation !== null ? conversation.plan : plan;
            return current.kind === "ready" && current.brain.provider.images;
        },
        // A live collection adopts the new utterance; otherwise it waits
        // unbound, replacing and abandoning any earlier unbound one.
        captureSink(e) {
            if (e.mode === "armed" || e.mode === "check") return spotting(e);
            const c = current(e.gen);
            if (c.live !== null) return c.live.captureSink(e);
            const utterance = transcription(c, e);
            const collection = c.collection;
            if (collecting(c, collection) && collection.utterance === null) {
                utterance.collection = collection;
                collection.utterance = utterance;
                utterance.begin();
            } else {
                c.unbound?.abort();
                c.unbound = utterance;
                if (utterance.answers) utterance.begin();
            }
            return utterance.sink;
        },
        // Only a running unbound utterance answers a new collection; one that
        // already concluded spoke before the collection existed.
        collect(e, done, failed) {
            const c = current(e.gen);
            const adopted = c.unbound !== null && c.unbound.state === "running" ? c.unbound : null;
            if (adopted === null) c.unbound?.abort();
            c.collection = { op: e.op, done, failed, utterance: adopted };
            if (adopted !== null) {
                adopted.collection = c.collection;
                adopted.begin();
            }
            c.unbound = null;
        },
        playbackSource(op) {
            if (conversation?.feedback?.source === op) return conversation.feedback.readable;
            if (conversation?.live !== null && conversation?.live !== undefined) return conversation.live.playbackSource(op);
            const turn = conversation?.last;
            if (!turn || turn.op !== op) return null;
            if (turn.lineStream && !turn.lineStream.handed) {
                turn.lineStream.handed = true;
                return turn.lineStream.readable;
            }
            if (turn.speech === null || turn.speech.handed) return null;
            turn.speech.handed = true;
            return turn.speech.readable;
        },
        playback, brain,
        // Session's engine word: a dictation row's recording sounds its own
        // tones, so Session plays no start sound for it.
        engine() {
            if (plan.kind === "ready" && duplexOf(plan.speech.id) !== null) return "duplex";
            return plan.speech?.kind === "ready" && plan.speech.dictation === true ? "dictation" : "chained";
        },
        // The selected voice provider's offers for the Voice setting; none
        // while no speech row is ready.
        voices() { return plan.speech?.kind === "ready" ? plan.speech.voices : []; },
        answering() {
            const current = conversation !== null ? conversation.plan.brain : plan.kind === "ready" ? plan.brain : null;
            return current === null ? "" : brainLabel(current);
        },
        speech: {
            open(e, events) {
                const c = current(e.gen);
                // A failover reopens the session for the conversation, which
                // speaks no preview a second time.
                const { preview, ...reopen } = e;
                c.liveOpen = { e: reopen, events };
                c.live.port.open(e, events);
            },
            close(e) {
                if (conversation?.liveOpen?.e?.op === e.target) conversation.liveOpen = null;
                conversation?.live?.port.close(e);
            },
            flush(e) {
                const c = conversation;
                if (c === null || c.live === null) return;
                // With no reply at the speaker no playback flush read the
                // account: the words this interruption drops went unheard.
                const account = c.heard?.turn === c.last ? null : cut(c, c.last);
                c.live.port.flush(e);
                if (account !== null) heard(c, c.last, account.text(null));
            },
            release() { conversation?.live?.port.release(); }
        },
        close() {
            end();
            closed = true;
            cancelModels();
            voiceList.net?.close();
            daemonSpeech?.close();
            brainText?.close();
        }
    });
}

module.exports = { create, failoverCause };
