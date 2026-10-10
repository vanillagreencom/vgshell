// One conversation owner: chained speech or Realtime duplex delegation.
// Session owns identity and deadlines, Audio owns pacing and heard accounting,
// WireBrain owns history and ToolRouter owns actions. This owner connects them
// per conversation and keeps the heard prefix that the next turn reports.
// Contract: docs/decisions/D089-jarvis-chained-engine-and-heard-prefix.md.
"use strict";
const { Readable, Writable } = require("node:stream");
const crypto = require("node:crypto");
const Policy = require("./Policy.js");
const Providers = require("./Providers.js");
const { PROVIDERS } = require("../AccountProviders.js");
const Net = require("./net.js");
const Guidance = require("./Guidance.js");
const Speakable = require("./Speakable.js");
const OpenAIChat = require("./OpenAIChat.js");
const AnthropicMessages = require("./AnthropicMessages.js");
const CodexHarness = require("./CodexHarness.js");
const CopilotHarness = require("./CopilotHarness.js");
const PiHarness = require("./PiHarness.js");
const ClaudeCode = require("./ClaudeCode.js");
const LocalSpeech = require("./LocalSpeech.js");
const { PCM_RATE } = require("./Audio.js");
const Realtime = require("./Realtime.js");
const TaskVoice = require("./TaskVoice.js");

// Speech adapter rows in selection order. A row is {select({settings,
// accounts, directories})} answering {kind:"ready", recipients, open({net,
// recipients})} or {kind:"unconfigured", cause, detail?}. The ElevenLabs row
// adds its own.
const SPEECH = Object.freeze({ local: LocalSpeech.row });
const DRIVERS = Object.freeze({ "openai-chat": OpenAIChat, "anthropic-messages": AnthropicMessages,
    "codex-app-server": CodexHarness, "copilot-acp": CopilotHarness, "pi-rpc": PiHarness, "claude-code": ClaudeCode });
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
function unconfigured(cause, detail) { return detail === undefined ? { kind: "unconfigured", cause } : { kind: "unconfigured", cause, detail }; }
// Session's fault carries the producer's keyed cause, never other text.
function keyed(error) {
    const message = error?.message ?? "";
    return /^jarvis(?:-[a-z]+)?: [a-z-]+=[^\n]*$/.test(message)
        ? message.replace(/^jarvis: /, "").slice(0, 180) : "engine=unexpected";
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
 * order, which the daemon publishes for the setup view.
 */
function select(settings, accounts, directories) {
    const speech = selectSpeech(settings, accounts, directories);
    const brain = selectBrain(settings, accounts);
    const failing = [speech, brain].filter(step => step.kind !== "ready");
    if (failing.length > 0) return { ...failing[0], causes: failing.map(step => step.cause) };
    return { kind: "ready", speech, brain: brain.brain };
}

// A home folder's own keyed cause, or null for any other failure.
function homeCause(error) {
    return /^jarvis: (home=[a-z-]{1,60}|guidance=home-[a-z-]{1,50})$/.exec(error?.message ?? "")?.[1] ?? null;
}

/**
 * The plan with the home folder's step judged before its own. home is the
 * daemon's judgement of the folder the user chose. A folder the daemon
 * refused, or whose text no brain can take whole, holds the engine with its
 * cause first: Jarvis never answers without the persona the user chose.
 */
function heldByHome(plan, home) {
    let cause = null;
    switch (home.kind) {
    case "none": break;
    case "refused": cause = home.cause; break;
    case "ready":
        try { Guidance.compose("chained", "local", LANGUAGE, home.path); }
        catch (error) {
            cause = homeCause(error);
            if (cause === null) throw error;
        }
        break;
    default: fail("home-state");
    }
    if (cause === null) return plan;
    return { ...unconfigured(cause), causes: [cause, ...(plan.kind === "ready" ? [] : plan.causes)] };
}

// Always mode listens for the wake word on this computer, so it needs a row
// that spots it locally; any other voice would stream the room to a provider.
function selectSpeech(settings, accounts, directories) {
    const speech = selectVoice(settings, accounts, directories);
    if (settings.mode === "always" && (settings.voiceProvider === "realtime" || speech.kind === "ready" && speech.wake !== true))
        return unconfigured("speech=always-local-voice");
    return speech;
}

function selectVoice(settings, accounts, directories) {
    if (settings.voiceProvider === "realtime") {
        const provider = Providers.select("openai-realtime");
        if (!settings.voiceAccount) return unconfigured("speech=live-account-unselected");
        let judge, account;
        try { judge = accounts(); account = judge.resolve(settings.voiceAccount); }
        catch (error) {
            if (!/^jarvis-(?:accounts|keys): /.test(error?.message ?? "")) throw error;
            return unconfigured("speech=live-account-unreadable");
        }
        if (account === null || account.provider !== "openai" || account.source.kind !== "keyring")
            return unconfigured("speech=live-key-required");
        const reference = account.source.reference;
        Net.assertKeyTarget(provider.base, reference.origin);
        return { kind: "ready", id: "openai-realtime", provider, key: { secrets: judge.secrets, reference },
            recipients: [{ kind: "network", provider: account.provider, account: account.id, origin: Net.endpoint(provider.base).origin }] };
    }
    let speech = unconfigured("speech=no-adapter");
    for (const [id, row] of Object.entries(SPEECH)) {
        const answer = row.select({ settings, accounts, directories });
        if (answer.kind === "ready") return { ...answer, id };
        if (answer.kind !== "unconfigured") fail("speech-row");
        if (speech.cause === "speech=no-adapter") speech = answer;
    }
    return speech;
}

function selectBrain(settings, accounts) {
    if (settings.brain === "") return unconfigured("brain=unselected");
    let judge, choice;
    try {
        judge = accounts();
        choice = judge.choose(settings.brain);
    } catch (error) {
        // Only the account and key readers' keyed failures are a cause here.
        if (!/^jarvis-(?:accounts|keys): /.test(error?.message ?? "")) throw error;
        return unconfigured("brain=accounts-unreadable", error.message);
    }
    if (choice.kind === "refused") return unconfigured("brain=" + choice.cause);
    if (choice.kind !== "accepted") fail("brain-choice");
    const account = choice.account;
    const provider = Providers.select(account.provider);
    if (!Object.hasOwn(DRIVERS, provider.driver)) fail("driver");
    const target = Net.endpoint(provider.base);
    // A key without a model list, a local server and a Pi choice name their
    // own model. An Anthropic key and every other sign-in program run the
    // model and effort the service chose from its list, each "" for a
    // program's own.
    const own = account.model !== "";
    return { kind: "ready", brain: { provider, model: own ? account.model : settings.model, effort: own ? "" : settings.effort,
        account: account.source,
        key: account.source.kind === "keyring" ? { secrets: judge.secrets, reference: account.source.reference } : null,
        recipient: { kind: "network", provider: provider.id, account: account.id, origin: target.origin },
        guidance: Guidance.compose("chained", target.loopback ? "local" : "text", LANGUAGE) } };
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
 * "ready", path} or {kind: "refused", cause}.
 */
function create({ session, state, audit, router, accounts, policy, fault, captionLimit, harness = null, tasks = null, directories, dispatch, clock, configured = () => {}, log = () => {}, home = () => ({ kind: "none" }) }) {
    if (!Number.isSafeInteger(captionLimit) || captionLimit < 1) fail("caption-limit");
    let plan = unconfigured("engine=starting");
    let conversation = null;
    let retired = null;
    let closed = false;
    let idleAt = null;
    let daemonSpeech = null;
    let speechState = { kind: "new" };
    const homePath = () => { const judged = home(); return judged.kind === "ready" ? judged.path : null; };
    // Whether the home folder's own cause holds the plan.
    let homeHeld = false;

    function configuration() {
        if (plan.kind !== "ready") return plan;
        if (plan.speech.lifetime === "daemon" && speechState.kind === "starting")
            return { kind: "loading", cause: "speech=local-loading", causes: ["speech=local-loading"] };
        if (plan.speech.lifetime === "daemon" && speechState.kind === "refused") {
            const cause = "speech=local-" + speechState.error.code.split(" ")[0];
            return { kind: "unconfigured", cause, causes: [cause] };
        }
        return { kind: "ready" };
    }

    function startSpeech(row) {
        speechState = { kind: "starting" };
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
            speechState = error.kind === "refused"
                ? { kind: "refused", error, publication: row.publication } : { kind: "unloaded" };
            configured(configuration());
        });
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
        const recipients = Policy.recipients({ conversation: "jarvis-" + gen, profile: facts.profile,
            cloudVision: facts.cloudVision, brain: plan.brain.recipient, speech: plan.speech.recipients });
        const net = Net.create(recipients);
        // late holds at most one call: the router runs one action at a time.
        // relay is the held prompt the user's next words answer, or null;
        // retried is that prompt once it was asked again after unjudged words.
        const c = { gen, plan, recipients, net, speech: null, brain: null, guidance: null, owner: null, grants: [], heard: null, relay: null, retried: null,
            decisions: new Set(), releasePending: null, late: new Map(), results: [], turn: null, last: null,
            feedback: null, collection: null, unbound: null, rev: 0, quiet: Promise.resolve(), live: null };
        try {
            if (plan.speech.id === "openai-realtime") {
                c.live = Realtime.create({ provider: plan.speech.provider, clock, captionLimit,
                    log, conversation: e => ({ net, key: plan.speech.key, language: LANGUAGE,
                        grants: () => c.grants, transfer: (item, start) => transfer(c, e, item, start) }) });
                c.speech = { close: () => c.live.port.release() };
            } else {
                if (plan.speech.lifetime === "daemon" && daemonSpeech === null) startSpeech(plan.speech);
                c.speech = plan.speech.lifetime === "daemon" ? daemonSpeech : plan.speech.open({ net, recipients });
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
        if (c.releasePending !== null) {
            c.releasePending.resolve(false);
            c.releasePending = null;
        }
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
        c.net.close();
        retired = { gen: c.gen, closed: quiet };
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

    // Speech to text. The capture sink exists while Audio holds the
    // recorder; one utterance yields partials and one final.
    function transcription(c, e) {
        const approval = state().approval;
        const answer = approval.kind === "held" ? { id: approval.id, digest: approval.digest,
            gen: approval.gen, beganAt: clock.now(), idleAt } : null;
        let output = null;
        // running: transcribing; concluded: final delivered or failed;
        // aborted: abandoned by the conversation or by its replacement.
        const utterance = { state: "running", collection: null, sink: null, abort() {
            if (utterance.state !== "running") return;
            utterance.state = "aborted";
            input.drop();
            void output?.return?.();
        } };
        // Audio's teardown ends the utterance. A conversation that ended
        // with it, as by mute or stop, aborts the utterance in end().
        const input = captured(() => utterance.state === "running");
        const { sink, frames } = input;
        utterance.sink = sink;
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
                    if (event === null || typeof event !== "object" || typeof event.text !== "string") fail("transcript");
                    if (event.kind === "partial") {
                        if (!Number.isSafeInteger(event.rev) || event.rev <= rev) fail("transcript-revision");
                        rev = event.rev;
                        utterance.collection?.done("partial", event.text);
                    } else if (event.kind === "final") {
                        utterance.state = "concluded";
                        if (answer !== null) {
                            const phrase = TaskVoice.phrase(event.text);
                            if (["yes", "confirm", "yes confirm"].includes(phrase))
                                dispatch({ type: "confirm", ...answer, source: "voice" });
                            else if (["no", "cancel", "no cancel"].includes(phrase))
                                dispatch({ type: "approval-cancel", gen: answer.gen, id: answer.id });
                        } else utterance.collection?.done("final", event.text);
                        void output.return?.();
                        return;
                    } else fail("transcript");
                }
            } catch (error) {
                if (utterance.state !== "running") return;
                utterance.state = "concluded";
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

    // The wake word, while Always mode waits: capture reaches only the
    // daemon-owned local sidecar. No conversation exists, so nothing is
    // released or audited; the word dispatches wake for this capture.
    function spotting(e) {
        if (plan.kind !== "ready" || plan.speech.wake !== true) fail("wake-unavailable");
        if (daemonSpeech === null) startSpeech(plan.speech);
        const { sink, frames } = captured(() => true);
        void daemonSpeech.spot(frames).outcome.then(result => {
            if (result.kind === "woke") dispatch({ type: "wake", gen: e.gen, op: e.op });
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
        readable.once("close", () => { ended = true; input.notify(); wanted.notify(); });
        const sentenceInput = { [Symbol.asyncIterator]() { return { async next() {
            for (;;) {
                if (sentences.length !== 0) {
                    const value = sentences.shift();
                    queued -= value.content.length;
                    return { value, done: false };
                }
                if (ended) return { value: undefined, done: true };
                await input.wait();
            }
        }, async return() { ended = true; return { value: undefined, done: true }; } }; } };
        async function pump() {
            const output = c.speech.speak(sentenceInput)[Symbol.asyncIterator]();
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
        return {
            readable, handed: false,
            queue(item) {
                if (queued + item.content.length > SENTENCE_TEXT) fail("speech-queue");
                queued += item.content.length;
                sentences.push(item);
                input.notify();
            },
            end() { ended = true; input.notify(); }
        };
    }

    function say(c, turn, sentence) {
        if (turn.stopped) return;
        const item = Policy.item(sentence, [...turn.labels]);
        if (c.live !== null) {
            c.live.commentary(turn.delegation, item);
            return;
        }
        transfer(c, turn, item, () => {
            if (turn.speech === null) {
                turn.speech = speech(c);
            }
            if (!turn.speaking) {
                turn.speaking = true;
                turn.done("play", { interruptible: true });
            }
            turn.speech.queue(item);
        });
        caption(c, turn, sentence);
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
        quiet(turn);
        turn.speech?.end();
    }
    function quiet(turn) {
        if (turn.feedbackTimer !== null) clock.clear(turn.feedbackTimer);
        turn.feedbackTimer = null;
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
        c.releasePending = { id, labels: needed, identity, resolve };
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
        const grant = { recipients: c.recipients, labels: pending.labels };
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
            const text = Speakable.create(LANGUAGE);
            const calls = [];
            // A request with no released content refuses before it is sent.
            let step = await (reply.release.labels.length === 0 ? events.next()
                : transfer(c, turn, Policy.item("", reply.release.labels), () => events.next()));
            for (; !step.done; step = await events.next()) {
                if (turn.stopped) return;
                const event = step.value;
                switch (event.kind) {
                case "text":
                    if (event.text.trim() !== "") quiet(turn);
                    for (const sentence of text.push(event.text)) say(c, turn, sentence);
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
                    for (const sentence of text.finish()) say(c, turn, sentence);
                    if (turn.stopped) return;
                    if (event.reason === "tool-calls") next(c, turn);
                    else {
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
        } catch (error) { failed(c, turn, error); }
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
    // conversation's recipients goes to TaskVoice instead.
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

    function heard(c, turn, text) {
        c.heard = { turn, labels: [...turn.labels], text };
    }
    // A Realtime reply's heard account for an interruption, or null when the
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
            if (c.brain === null) {
                // The home text is read at each conversation's first turn, so
                // the user's last edit is the one a brain gets. A text that
                // outgrew its bound since the setup answer fails this turn.
                const folder = homePath();
                try { c.guidance = folder === null ? c.plan.brain.guidance : c.plan.brain.guidance.withHome(folder); }
                catch (error) {
                    if (homeCause(error) === null) throw error;
                    done("brain-failed", { reason: keyed(error) });
                    return;
                }
                c.brain = DRIVERS[c.plan.brain.provider.driver].create({ provider: c.plan.brain.provider,
                    model: c.plan.brain.model, effort: c.plan.brain.effort, net: c.net, recipients: c.recipients, key: c.plan.brain.key,
                    account: c.plan.brain.account, gen: c.gen, harness });
                c.brain.start({ instructions: c.guidance.instructions, tools: router.offer() });
                c.owner = e.owner;
            } else if (c.owner !== e.owner) fail("brain-owner");
            if (c.turn !== null) fail("brain-busy");
            const turn = { gen: e.gen, op: e.op, done, labels: new Set(), speech: null, stopped: false, speaking: false, delegation: e.delegation,
                feedbackTimer: null, relay: null,
                phase: "queued", calls: [], answers: new Map(), routing: null, caption: "" };
            if (e.text.trim() === "") {
                done("brain-done");
                return;
            }
            c.turn = turn;
            c.last = turn;
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
            // A queued or relay turn owns no adapter request. Its prior cancellation
            // still blocks the next turn and this cancellation's acknowledgement.
            c.quiet = (turn.phase === "queued" || turn.phase === "relay" ? c.quiet : c.brain.cancel()).then(() => {
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
            c.results.push(lateItem(late.call, value.outcome, item));
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
                const speaking = turn?.speaking === true;
                // A Realtime reply's account is read here: the speech port's
                // flush follows this effect and drops it. Until Audio
                // reports, the reply at the speaker counts as unheard.
                const account = cut(c, turn);
                if (account !== null) heard(c, turn, account.text(null));
                return port.flush(e, report => {
                    if (account !== null && conversation === c && c.last === turn) heard(c, turn, account.text(report));
                    const own = speaking && c.live === null && conversation === c && c.last === turn && (report === null || report.source === turn.op);
                    if (own && turn.relay === null) heard(c, turn, report === null ? "" : report.heardText);
                    else if (own) unheard(c, turn);
                    done(report);
                });
            }
        };
    }

    return Object.freeze({
        /** Select setup admission; healthy loading can accept bounded capture. */
        configure(settings) {
            plan = select(settings, accounts, directories);
            const selected = plan;
            plan = heldByHome(plan, home());
            homeHeld = plan !== selected;
            if (plan.kind === "ready" && plan.speech.lifetime === "daemon") {
                // A completed setup publication can repair an initial
                // refusal. Ordinary hellos leave that runtime unloaded.
                const published = speechState.kind === "refused" && speechState.publication !== plan.speech.publication;
                if (speechState.kind === "new" || published) startSpeech(plan.speech);
            }
            return configuration();
        },
        /**
         * Whether the last configure left the home folder holding the plan.
         * No hello follows an edit inside the folder, so the daemon judges
         * it again at the user's next request.
         */
        homeHeld: () => homeHeld,
        observe(s) {
            if (conversation !== null && (s.gen !== conversation.gen || s.conversation.kind === "ended")) end();
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
            } else if (conversation?.feedback !== null && conversation?.feedback !== undefined) {
                conversation.feedback.readable.destroy();
                conversation.feedback = null;
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
            if (e.mode === "armed") return spotting(e);
            const c = current(e.gen);
            if (c.live !== null) return c.live.captureSink(e);
            const utterance = transcription(c, e);
            const collection = c.collection;
            if (collecting(c, collection) && collection.utterance === null) {
                utterance.collection = collection;
                collection.utterance = utterance;
            } else {
                c.unbound?.abort();
                c.unbound = utterance;
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
            if (adopted !== null) adopted.collection = c.collection;
            c.unbound = null;
        },
        playbackSource(op) {
            if (conversation?.feedback?.source === op) return conversation.feedback.readable;
            if (conversation?.live !== null && conversation?.live !== undefined) return conversation.live.playbackSource(op);
            const turn = conversation?.last;
            if (!turn || turn.op !== op || turn.speech === null || turn.speech.handed) return null;
            turn.speech.handed = true;
            return turn.speech.readable;
        },
        playback, brain,
        engine() { return plan.kind === "ready" && plan.speech.id === "openai-realtime" ? "duplex" : "chained"; },
        speech: {
            open(e, events) { current(e.gen).live.port.open(e, events); },
            close(e) { conversation?.live?.port.close(e); },
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
            daemonSpeech?.close();
        }
    });
}

module.exports = { create };
