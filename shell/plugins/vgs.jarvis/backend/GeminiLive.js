// The Gemini Live duplex speech engine: one provider session per
// conversation, with the contract of Realtime.js. It streams the microphone,
// hands each transcribed user turn to the brain as a delegation and has the
// voice read the brain's released sentences aloud. It keeps which of those
// sentences the user heard to their end, for the brain's account of an
// interruption.
// The voice has no tools and its own answers never play. Session owns the
// lifetime through the speech port; Audio owns devices and calls captureSink
// and playbackSource. Protocol: Google's Live API reference
// (https://ai.google.dev/api/live), its WebSocket and capabilities guides
// and python-genai's live.py, read 2026-10-12. Contract:
// docs/decisions/D089-jarvis-chained-engine-and-heard-prefix.md.
"use strict";
const { Readable, Writable } = require("node:stream");
const Policy = require("./Policy.js");
const Providers = require("./Providers.js");
const Net = require("./net.js");
const Guidance = require("./Guidance.js");
const Speakable = require("./Speakable.js");
const { sourceLimit, peak, SILENT_PEAK, PCM_RATE } = require("./Audio.js");

// The Live API hears 16 kHz PCM and speaks 24 kHz PCM (capabilities guide).
// Audio captures and plays at PCM_RATE, so speech plays as it comes and the
// microphone is resampled by 2/3 on its way out.
const OUTPUT_RATE = 24000;
const INPUT_MIME = "audio/pcm;rate=16000";
if (PCM_RATE !== OUTPUT_RATE) throw new Error("jarvis: live=audio-rate");
// Recovery bounds and grouping rules, not measured latency budgets.
const IDLE_MS = 60000;            // plan § 3.5
const START_WAIT_MS = 20000;      // connect, open and setupComplete
const RESPONSE_WAIT_MS = 30000;   // asked words, or words held for the voice's own turn, to that turn's turnComplete
// The first captured frame of a running session to the voice's first heard
// words: an interim or a final input transcription that holds any. The
// reference sends inputTranscription independently of the other messages,
// with no guaranteed order, so a long request's words can come late; its
// voiceActivity start pauses the bound and its end runs the bound again from
// there. This leaves a user room to start talking.
const UNHEARD_MS = 15000;
const REPLY_GAP_MS = 500;         // no words waiting for this long ends a playing reply
const SILENCE_TICK_MS = 100;
const SILENCE_MAX_MS = 1000;      // no catch-up past this after a stalled event loop
const PENDING_BYTES = PCM_RATE * 2 * START_WAIT_MS / 1000;  // queued input, opening words included
const APPEND_BYTES = PCM_RATE * 2;
const SEND_BACKLOG_BYTES = 256 * 1024;
const FRAME_CHARS = 1024 * 1024;
const TURN_CHARS = 65536;         // one user turn's transcript
const QUEUE_CHARS = 65536;        // released words waiting for the voice
// A model turn's audio cannot be paused. One turn carries at most
// SPEECH_CHARS, and the next is asked for once playback has drained the reply
// to REPLY_LOW_BYTES, so the rest of Audio's allowance is one turn's room.
const SPEECH_CHARS = 240;
const REPLY_BYTES = sourceLimit(false, false);
const REPLY_LOW_BYTES = PCM_RATE * 2 * 2;
const BASE64 = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;
// The prebuilt voices of speechConfig.voiceConfig, as the Settings page
// offers them, in the speech generation guide's order, read 2026-10-12:
// native audio models speak every voice of the text-to-speech models. The
// first stands for the unset setting. A session's voice is fixed at setup,
// so a new voice is a new session, as a changed setting ends the conversation.
const VOICES = Object.freeze(["Zephyr", "Puck", "Charon", "Kore", "Fenrir", "Leda", "Orus", "Aoede", "Callirrhoe", "Autonoe",
    "Enceladus", "Iapetus", "Umbriel", "Algieba", "Despina", "Erinome", "Algenib", "Rasalgethi", "Laomedeia", "Achernar",
    "Alnilam", "Schedar", "Gacrux", "Pulcherrima", "Achird", "Zubenelgenubi", "Vindemiatrix", "Sadachbia", "Sadaltager", "Sulafat"]
    .map(name => Object.freeze({ label: name, value: name })));
// The Live API answers every user turn it hears and has no setting that
// stops it, so the voice is told to keep quiet; what it says anyway never plays.
const UNASKED = "You hear the user only so that their words can be written down. Never answer them and never speak on your own. Speak only when a request gives you a text.";
// The delegation a preview's words answer: no user request exists.
const PREVIEW = "preview";
// The fields of serverContent this session reads or knowingly leaves (the
// reference's BidiGenerateContentServerContent, read 2026-10-12).
// groundingMetadata and urlContextMetadata answer tools it never offers.
const CONTENT_FIELDS = new Set(["modelTurn", "turnComplete", "interrupted", "generationComplete", "inputTranscription",
    "interimInputTranscription", "outputTranscription", "waitingForInput", "interactionStatus"]);
// The server message's members beside its one kind: usageMetadata, which the
// session leaves, and voiceActivity, which it reads.
const BESIDE = new Set(["usageMetadata", "voiceActivity"]);
// voiceActivity's types (the reference's VoiceActivity.Type): the start and
// end of the user's speech; TYPE_UNSPECIFIED, the default, says neither.
const VOICE_ACTIVITY = Object.freeze({ ACTIVITY_START: "start", ACTIVITY_END: "end", TYPE_UNSPECIFIED: null });

function fail(code) { throw new Error("jarvis: live=" + code); }
function plain(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function flag(value) {
    if (value !== undefined && typeof value !== "boolean") fail("frame-shape");
    return value === true;
}
// A transcription's {text, finished}. The reference documents text and its
// language and offsets; python-genai's Transcription adds finished, which
// may close the user's turn early. text may be absent on its last message.
function transcription(value) {
    if (value === undefined) return { text: "", finished: false };
    if (!plain(value) || value.text !== undefined && typeof value.text !== "string") fail("frame-shape");
    return { text: value.text ?? "", finished: flag(value.finished) };
}
// Provider names are reported; provider message text is not. Every name
// reported is a member name, so a string.
function token(value) { return /^[A-Za-z0-9_.-]{1,64}$/.test(value) ? value : "unrecognized"; }
function reasonOf(error) { return String(error.message).replace(/^jarvis: /, "").slice(0, 160); }
function clean(text) { return text.replace(/[\x00-\x1f\x7f]/g, " "); }

// One audio part of a model turn: 16-bit PCM at Audio's rate.
function audioOf(part) {
    const data = plain(part.inlineData) ? part.inlineData : null;
    if (data === null || typeof data.mimeType !== "string" || typeof data.data !== "string") fail("frame-shape");
    const [type, ...parameters] = data.mimeType.split(";").map(word => word.trim());
    const rate = parameters.find(word => word.startsWith("rate="));
    if (type !== "audio/pcm" || rate !== undefined && rate !== "rate=" + OUTPUT_RATE) fail("format");
    if (!BASE64.test(data.data)) fail("output-audio");
    const pcm = Buffer.from(data.data, "base64");
    if (pcm.length % 2 !== 0) fail("output-audio");
    return pcm;
}

// A message's voiceActivity: "start", "end" or null.
function voiceActivityOf(value) {
    if (value === undefined) return null;
    if (!plain(value) || value.type !== undefined && typeof value.type !== "string") fail("frame-shape");
    const type = value.type ?? "TYPE_UNSPECIFIED";
    if (!Object.hasOwn(VOICE_ACTIVITY, type)) fail("voice-activity type=" + token(type));
    return VOICE_ACTIVITY[type];
}

/**
 * The one narrowing door for a server message's text. Returns a tagged
 * event, with the message's voice activity, or throws a keyed error. A
 * message names one kind beside optional usageMetadata and voiceActivity.
 */
function eventOf(data) {
    if (data.length > FRAME_CHARS) fail("frame-size");
    let value;
    try { value = JSON.parse(data); } catch { fail("frame-json"); }
    if (!plain(value)) fail("frame-shape");
    const kinds = Object.keys(value).filter(key => !BESIDE.has(key));
    if (kinds.length > 1) fail("frame-shape");
    return { ...kindOf(value, kinds[0]), voice: voiceActivityOf(value.voiceActivity) };
}

// A message's one kind, or none, as a tagged event.
function kindOf(value, kind) {
    switch (kind) {
    case undefined:
        return { kind: "ignored" };
    case "setupComplete":
        if (!plain(value.setupComplete)) fail("frame-shape");
        return { kind: "started" };
    case "serverContent": {
        const content = value.serverContent;
        if (!plain(content)) fail("frame-shape");
        for (const field of Object.keys(content)) if (!CONTENT_FIELDS.has(field)) fail("content field=" + token(field));
        const audio = [];
        // Any part of a model turn, spoken or not, shows that turn has started.
        let model = content.outputTranscription !== undefined;
        if (content.modelTurn !== undefined) {
            model = true;
            const turn = content.modelTurn;
            if (!plain(turn) || turn.parts !== undefined && !Array.isArray(turn.parts)) fail("frame-shape");
            for (const part of turn.parts ?? []) {
                if (!plain(part)) fail("frame-shape");
                if (part.inlineData !== undefined) audio.push(audioOf(part));
                // A native audio model may send its thinking as a text part;
                // the voice speaks only audio. Any other part, such as a
                // function call, answers a request this session never makes.
                else if (typeof part.text !== "string") fail("part");
            }
        }
        flag(content.waitingForInput);
        flag(content.generationComplete);
        if (content.interactionStatus !== undefined && typeof content.interactionStatus !== "string") fail("frame-shape");
        const interim = transcription(content.interimInputTranscription);
        const heard = transcription(content.inputTranscription);
        const said = transcription(content.outputTranscription);
        return { kind: "content", interim: interim.text, heard: heard.text, finished: heard.finished, model, audio, said: said.text,
            interrupted: flag(content.interrupted), complete: flag(content.turnComplete) };
    }
    // The session ends at the server's notice: no resumption is set up.
    case "goAway":
        return fail("go-away");
    case "sessionResumptionUpdate":
        return { kind: "ignored" };
    // Everything else answers a request this session never makes: a tool
    // call or its cancellation.
    default:
        return fail("message type=" + token(kind));
    }
}

/**
 * create({provider, clock, conversation, captionLimit, log}) returns
 * {port, captureSink, playbackSource, played, commentary, heard}. provider is the Providers.select
 * "gemini-live" row. conversation(e) answers {net, key, language, voice, preview, transfer, grants} for a
 * speech-open effect: the session's net owner, null or {secrets, reference},
 * the speech language, a value of VOICES, the sentence a preview speaks or
 * null, audited transfer and current release grants. A preview session asks
 * for its sentence once it starts and reports idle once Audio played it, so
 * Session ends the conversation. captionLimit is the wire's transcript
 * bound. log receives keyed diagnostic lines. One session at a time is live.
 */
function create({ provider, clock, conversation, captionLimit, log }) {
    Providers.assertRow(provider);
    if (provider.driver !== "gemini-live") fail("driver");
    if (!Number.isSafeInteger(captionLimit) || captionLimit < 1) fail("caption-limit");
    let live = null;

    function clear(session, name) {
        if (session.timers[name] !== null) clock.clear(session.timers[name]);
        session.timers[name] = null;
    }
    function release(session) {
        if (session.segments.assistant !== null) tally(session, session.segments.assistant.text);
        session.segments = { user: null, assistant: null };
        for (const name of Object.keys(session.timers)) clear(session, name);
        if (session.next !== null) session.next.stream.destroy();
        session.next = null;
        session.playing = null;
        session.capture = null;
        session.pending = [];
        session.carry = Buffer.alloc(0);
        session.inbox = [];
        session.speech = { queue: [], chars: 0, active: null };
        session.hold = false;
        session.turn = null;
        session.delegation = null;
        session.said = [];
        session.taken = null;
        // Closing a connecting channel can emit close synchronously. The
        // released session must refuse that callback before it closes.
        session.state = { kind: "ended" };
        if (session.channel !== null) session.channel.close();
        if (live === session) live = null;
    }
    function failed(session, reason) {
        if (session.state.kind === "ended") return;
        release(session);
        session.events.failed(reason);
    }
    function send(session, value, items = [Policy.item("", ["speech"])]) {
        const frame = Policy.summary(JSON.stringify(value), items);
        const answer = session.transfer(frame, () => session.channel.send(frame, session.grants()));
        if (answer.kind !== "send") fail("release-" + answer.kind);
        if (session.channel.bufferedAmount > SEND_BACKLOG_BYTES) fail("send-backlog");
    }
    // Audio's 24 kHz frames leave at 16 kHz: of each three samples, the
    // first and the mean of the other two, the samples at 0 and 1.5 on the
    // input's time line. No low-pass filter runs first: speech carries little
    // above 8 kHz, which folds back into the band. The samples short of three
    // wait for the next frame.
    function append(session, pcm) {
        const all = session.carry.length === 0 ? pcm : Buffer.concat([session.carry, pcm]);
        const groups = Math.floor(all.length / 6);
        session.carry = Buffer.from(all.subarray(groups * 6));
        if (groups === 0) return true;
        const out = Buffer.alloc(groups * 4);
        for (let group = 0; group < groups; group++) {
            out.writeInt16LE(all.readInt16LE(group * 6), group * 4);
            out.writeInt16LE((all.readInt16LE(group * 6 + 2) + all.readInt16LE(group * 6 + 4)) >> 1, group * 4 + 2);
        }
        try { send(session, { realtimeInput: { audio: { data: out.toString("base64"), mimeType: INPUT_MIME } } }); }
        catch (error) { failed(session, reasonOf(error)); return false; }
        return true;
    }
    // Every input frame enters here, in order. Input waits for
    // setupComplete, and new input waits behind queued input. Returns
    // false once the session has failed.
    function input(session, pcm) {
        if (session.state.kind === "running" && session.pending.length === 0) return append(session, pcm);
        session.pendingBytes += pcm.length;
        if (session.pendingBytes > PENDING_BYTES) { failed(session, "live=input-overflow"); return false; }
        session.pending.push(Buffer.from(pcm));
        return pump(session);
    }
    // Queued input leaves one APPEND_BYTES chunk at a time, each once the
    // socket has written everything before it, so a long opening never meets
    // the send backlog. New input and silence ticks drain it.
    function pump(session) {
        while (session.state.kind === "running" && session.pending.length > 0 && session.channel.bufferedAmount === 0) {
            const queued = Buffer.concat(session.pending);
            const pcm = queued.subarray(0, APPEND_BYTES);
            session.pending = queued.length > pcm.length ? [queued.subarray(pcm.length)] : [];
            session.pendingBytes = queued.length - pcm.length;
            if (!append(session, pcm)) return false;
        }
        return true;
    }
    // The provider ends a user turn when its voice activity detection hears
    // the speech end. While no microphone feeds it, silence gives it that end.
    function silence(session) {
        session.timers.silence = clock.set(() => {
            session.timers.silence = null;
            if (!pump(session) || !speak(session)) return;
            if (session.capture === null) {
                const now = clock.now();
                const samples = Math.floor(Math.min(now - session.inputAt, SILENCE_MAX_MS) * PCM_RATE / 1000);
                session.inputAt = now;
                if (samples > 0 && !input(session, Buffer.alloc(samples * 2))) return;
            }
            silence(session);
        }, SILENCE_TICK_MS);
    }
    function activity(session) {
        if (session.state.kind !== "running") return;
        clear(session, "idle");
        session.timers.idle = clock.set(() => {
            session.timers.idle = null;
            // Words and their audio hold the session: a turn's end and a
            // reply's close each restart this wait.
            if (session.playing !== null || session.next !== null || !quiet(session)) return;
            session.events.idle();
            // Session leaves a turn in flight to its own deadline and keeps
            // this session open; the wait then runs again.
            activity(session);
        }, IDLE_MS);
    }
    // Captured audio the voice never answers ends the conversation at
    // UNHEARD_MS with the cause its frames' peak names, rather than at the
    // idle wait with no cause. The user's voice activity pauses the watch and
    // its end runs it again; the first heard words end it for the session's
    // life: a quiet answered conversation ends at idle.
    function watch(session) {
        if (session.answered || session.talking || !session.captured || session.state.kind !== "running" || session.timers.unheard !== null) return;
        session.timers.unheard = clock.set(() => {
            session.timers.unheard = null;
            failed(session, session.peak <= SILENT_PEAK ? "live=input-silent" : "live=unheard");
        }, UNHEARD_MS);
    }
    function answered(session) {
        session.answered = true;
        clear(session, "unheard");
    }
    function talking(session, value) {
        session.talking = value;
        if (value) clear(session, "unheard");
        else watch(session);
    }
    function quiet(session) { return session.speech.active === null && session.speech.queue.length === 0; }
    function replyPending(session) {
        return session.speech.active !== null && !session.speech.active.line
            || session.speech.queue.some(words => !words.line)
            || [session.playing, session.next, session.taken].some(reply => reply !== null && reply.marks.some(mark => !mark.line));
    }
    // A playing reply ends once no words have waited for REPLY_GAP_MS.
    function settle(session) {
        clear(session, "gap");
        const reply = session.playing;
        if (reply === null || reply.kind !== "open") return;
        session.timers.gap = clock.set(() => {
            session.timers.gap = null;
            if (session.playing !== reply || reply.kind !== "open" || !quiet(session)) return;
            reply.kind = "ended";
            reply.stream.push(null);
        }, REPLY_GAP_MS);
    }
    // One model turn at a time, and none under the hold: the provider names
    // no turn, so the order of turns is their identity, and a request sent
    // while the voice's own turn runs would take that turn's audio or end as
    // its own. Returns false once the session has failed.
    function speak(session) {
        const speech = session.speech;
        const waiting = [session.playing, session.next].reduce((sum, reply) => sum + (reply === null ? 0 : reply.stream.readableLength), 0);
        if (session.state.kind !== "running" || speech.active !== null || speech.queue.length === 0 || waiting > REPLY_LOW_BYTES)
            return true;
        // A voice's own turn that never ends would hold these words for ever.
        if (session.hold) {
            if (session.timers.hold === null) session.timers.hold = clock.set(() => failed(session, "live=response-timeout"), RESPONSE_WAIT_MS);
            return true;
        }
        const words = speech.queue.shift();
        speech.chars -= words.text.length;
        speech.active = { discarded: false, said: false, text: words.text, request: session.delegation, reply: null,
            line: words.line === true };
        clear(session, "gap");
        // A model turn that never ends would hold every later word.
        session.timers.words = clock.set(() => failed(session, "live=response-timeout"), RESPONSE_WAIT_MS);
        try {
            send(session, { clientContent: { turns: [{ role: "user", parts: [{ text: session.reader + "\n\n" + JSON.stringify(words.text) }] }],
                turnComplete: true } }, [words.item]);
        } catch (error) { failed(session, reasonOf(error)); return false; }
        return true;
    }
    function output(session, active, pcm) {
        if (pcm.length === 0) return;
        let reply = session.playing !== null && session.playing.kind === "open" ? session.playing : session.next;
        if (reply === null) {
            reply = { kind: "open", stream: new Readable({ highWaterMark: REPLY_BYTES, read() {} }), bytes: 0, marks: [] };
            session.next = reply;
            session.events.speak();
        }
        active.reply = reply;
        reply.bytes += pcm.length;
        // A model turn cannot be paused: a full queue faults, never drops speech.
        if (!reply.stream.push(pcm)) failed(session, "live=output-overflow");
    }
    function emit(session, role, text, stage) {
        session.rev++;
        session.events.transcript({ role, text, stage, rev: session.rev });
    }
    // One open caption per speaker: the user turn's, which closes with the
    // turn, or the reply's words so far. A caption at the wire's bound
    // closes and the rest starts the next.
    function caption(session, role, delta) {
        let text = clean(delta);
        let segment = session.segments[role];
        if (segment === null && text.trim() === "") return;
        while (text !== "") {
            if (segment !== null && segment.text.length === captionLimit) {
                conclude(session, role);
                segment = null;
            }
            if (segment === null) segment = session.segments[role] = { text: "" };
            const room = captionLimit - segment.text.length;
            segment.text += text.slice(0, room);
            text = text.slice(room);
            emit(session, role, segment.text, "partial");
        }
    }
    function conclude(session, role) {
        const segment = session.segments[role];
        if (segment === null) return;
        session.segments[role] = null;
        emit(session, role, segment.text, "final");
        if (role === "assistant") tally(session, segment.text);
    }
    // The voice is asked to speak each sentence exactly; this counts where its
    // transcript shows it did not. The log carries only violation kinds and counts.
    function tally(session, text) {
        try {
            const counts = Speakable.violations(text, session.language);
            if (Object.values(counts).some(count => count !== 0))
                log("jarvis: live=violations counts=" + JSON.stringify(counts));
        } catch {
            // Privacy teardown must finish even when a transcript exceeds a sanitizer bound.
            log("jarvis: live=violation-overflow");
        }
    }
    // The user's words of the turn in hand. The provider names no user turn:
    // the turn runs from its first words to the voice's own turnComplete.
    // Words that come after the turn went to the brain belong to it: they
    // finish its caption and never make a request of their own. The Live API
    // answers each user turn with a model turn of the voice's own and has no
    // setting that stops it, so the first words set the hold, as does the
    // first part of a model turn while no words are asked for: no words leave
    // (speak) until a turnComplete arrives while none are asked for, that
    // turn's end.
    function hearing(session, text) {
        activity(session);
        conclude(session, "assistant");
        if (session.turn === null) {
            session.turn = { id: "turn-" + ++session.turns, text: "", delegated: false };
            session.hold = true;
        }
        const turn = session.turn;
        if (turn.text.length + text.length > TURN_CHARS) fail("turn-size");
        turn.text += text;
        caption(session, "user", text);
        if (text.trim() !== "") answered(session);
    }
    // The user's words go to the brain once.
    function delegate(session) {
        const turn = session.turn;
        if (turn === null || turn.delegated) return;
        turn.delegated = true;
        if (turn.text.trim() === "") return;
        // Words still waiting answer the request this one replaces. A
        // playing reply left with none to wait for ends after its gap, which
        // the voice's own turn's end starts.
        session.speech.queue = [];
        session.speech.chars = 0;
        // Heard sentences are kept for the request in hand only.
        session.said = [];
        session.delegation = turn.id;
        session.events.delegation({ id: turn.id, text: clean(turn.text) });
    }
    // One serverContent message, its fields in the order they happen: the
    // user's words, the model turn's parts, then its end. A model turn while
    // no words are asked for is the voice's own: its parts are dropped. Its
    // turnComplete ends the user's turn and lifts the hold. generationComplete
    // ends nothing: the turn is over only at its turnComplete. A delegation
    // can end the session, as a brain that fails at once does.
    function content(session, event) {
        const active = session.speech.active;
        // Interim words show the user was heard; the final ones carry the turn.
        if (event.interim.trim() !== "") {
            activity(session);
            answered(session);
        }
        if (event.heard !== "") hearing(session, event.heard);
        if (event.finished) {
            delegate(session);
            if (session.state.kind === "ended") return;
        }
        if (event.model) {
            if (active === null) session.hold = true;
            else if (!active.discarded) {
                for (const pcm of event.audio) {
                    output(session, active, pcm);
                    if (session.state.kind === "ended") return;
                }
                if (event.said !== "") {
                    caption(session, "assistant", (active.said || session.segments.assistant === null ? "" : " ") + event.said);
                    active.said = true;
                }
            }
        }
        // With NO_INTERRUPTION the user's speech never cuts a model turn,
        // and only a client message does (reference, interrupted). The hold
        // keeps the one request from leaving while a turn runs that it knows
        // of, so a cut while words are asked for is a turn it could not see:
        // whatever came since is not those words' audio.
        if (event.interrupted && active !== null) active.discarded = true;
        if (!event.complete) return;
        if (active === null) {
            delegate(session);
            if (session.state.kind === "ended") return;
            if (session.turn !== null) conclude(session, "user");
            session.turn = null;
            session.hold = false;
            clear(session, "hold");
        } else {
            // Whole words mark where their audio ends in the reply that carries them.
            if (!active.discarded && active.reply !== null)
                active.reply.marks.push({ request: active.request, end: active.reply.bytes, text: active.text, line: active.line });
            session.speech.active = null;
            clear(session, "words");
        }
        activity(session);
        if (speak(session)) settle(session);
    }
    function receive(session, data) {
        if (session.state.kind === "ended") return;
        let event;
        try { event = eventOf(data); } catch (error) { failed(session, reasonOf(error)); return; }
        const kind = session.state.kind;
        try {
            if (kind !== "running" && !["started", "ignored"].includes(event.kind)) fail("event-order");
            switch (event.kind) {
            case "started":
                if (kind !== "starting") fail("event-order");
                clear(session, "start");
                session.state = { kind: "running" };
                session.inputAt = clock.now();
                if (!pump(session)) return;
                silence(session);
                activity(session);
                watch(session);
                if (session.preview !== null) {
                    session.delegation = PREVIEW;
                    commentary(PREVIEW, Policy.item(session.preview, ["desktop"]));
                }
                break;
            case "content": content(session, event); break;
            case "ignored": break;
            default: throw new Error("jarvis: live=event-kind");
            }
            // After the kind, so words in the same message end the watch first.
            if (event.voice !== null && session.state.kind === "running") {
                if (event.voice === "start") activity(session);
                talking(session, event.voice === "start");
            }
        } catch (error) { failed(session, reasonOf(error)); }
    }
    // Messages are read in the order they came. A JSON message may come as a
    // binary frame, which Node's WebSocket hands over as a Blob read only
    // asynchronously, so later messages wait behind it.
    function inbound(session, data) {
        if (session.state.kind === "ended") return;
        session.inbox.push(data);
        if (!session.reading) drain(session);
    }
    function drain(session) {
        while (session.inbox.length > 0 && session.state.kind !== "ended") {
            const data = session.inbox.shift();
            if (typeof data === "string") { receive(session, data); continue; }
            if (!(data instanceof Blob)) { failed(session, "live=frame-binary"); return; }
            if (data.size > FRAME_CHARS) { failed(session, "live=frame-size"); return; }
            session.reading = true;
            data.arrayBuffer().then(bytes => {
                session.reading = false;
                if (session.state.kind === "ended") return;
                let text;
                try { text = new TextDecoder("utf-8", { fatal: true }).decode(bytes); }
                catch { failed(session, "live=frame-binary"); return; }
                receive(session, text);
                drain(session);
            }, () => { session.reading = false; failed(session, "live=frame-binary"); });
            return;
        }
    }
    function opened(session) {
        if (session.state.kind !== "connecting") return;
        session.state = { kind: "starting" };
        try { send(session, session.setup); } catch (error) { failed(session, reasonOf(error)); }
    }
    function connect(session, { net, key, language, voice, preview, transfer, grants }) {
        session.transfer = transfer;
        session.grants = grants;
        session.language = language;
        session.preview = preview;
        if (key === null) fail("no-key");
        if (!VOICES.some(row => row.value === voice)) fail("voice");
        Net.assertKeyTarget(provider.base, key.reference.origin);
        session.reader = Guidance.compose("duplex", "duplex", language).instructions;
        // No tools: the voice has no function to call. NO_INTERRUPTION keeps
        // the server's voice activity detection from cutting a reply; Session's
        // flush owns interruption. Both transcripts are on for the captions
        // and the delegation.
        session.setup = { setup: { model: "models/" + provider.model,
            generationConfig: { responseModalities: ["AUDIO"], speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: voice } } } },
            systemInstruction: { parts: [{ text: session.reader + "\n\n" + UNASKED }] },
            inputAudioTranscription: {}, outputAudioTranscription: {},
            realtimeInputConfig: { activityHandling: "NO_INTERRUPTION" } } };
        const secret = key.secrets.lookup(key.reference);
        let answer;
        try {
            const item = Policy.item(provider.base, ["speech"]);
            answer = transfer(item, () => net.websocket(item, { url: provider.base,
                key: { origin: key.reference.origin, header: "x-goog-api-key", prefix: "", value: secret.toString("utf8") } }));
        } finally { secret.fill(0); }
        if (answer.kind !== "channel") fail("release-" + answer.kind);
        session.channel = answer;
        // The Live API waits for setup as the socket's first message.
        answer.events.addEventListener("open", () => opened(session));
        answer.events.addEventListener("message", event => inbound(session, event.data));
        // WHATWG WebSocket fires close after every error, a refused redirect
        // included; close owns the outcome. Google's close reason is not read,
        // nor the body of a handshake answered 401 or 403, which refused the key.
        answer.events.addEventListener("close", event => failed(session,
            Net.keyRefused(event) ? "live=key-refused" : "live=disconnected code=" + event.code));
    }

    const port = {
        open(e, events) {
            if (live !== null) throw new Error("jarvis: live=session-live");
            const session = { op: e.op, events, state: { kind: "connecting" }, channel: null, setup: null, reader: "",
                timers: { start: null, silence: null, idle: null, gap: null, words: null, hold: null, preview: null, unheard: null },
                pending: [], pendingBytes: 0, carry: Buffer.alloc(0), inbox: [], reading: false, inputAt: clock.now(), capture: null,
                captured: false, peak: 0, answered: false, talking: false,
                playing: null, next: null, speech: { queue: [], chars: 0, active: null }, hold: false, turn: null, turns: 0,
                delegation: null, said: [], taken: null, segments: { user: null, assistant: null }, rev: 0, language: "", preview: null };
            live = session;
            session.timers.start = clock.set(() => failed(session, "live=start-timeout"), START_WAIT_MS);
            try { connect(session, conversation(e)); } catch (error) { failed(session, reasonOf(error)); }
        },
        // The session has no close message: closing the socket ends it.
        close(e) {
            if (live !== null && live.op === e.target) release(live);
        },
        // Lease loss, or a brain failover that opens the session again under
        // the same identity: no socket or timer may hold the daemon. The
        // released session's words are gone, so its due reply is too.
        release() {
            const session = live;
            if (session === null) return;
            release(session);
            session.events.due(false);
        },
        // Drop the words not yet asked for, then the rest of the interrupted
        // model turn, which runs on to its turnComplete unheard.
        flush(e) {
            const session = live;
            if (session === null || session.op !== e.target) return;
            session.delegation = null;
            conclude(session, "assistant");
            session.speech.queue = [];
            session.speech.chars = 0;
            if (session.speech.active !== null) session.speech.active.discarded = true;
            clear(session, "gap");
            if (session.next !== null) session.next.stream.destroy();
            session.next = null;
            // Audio's flush releases the reply it holds.
            session.playing = null;
            session.taken = null;
            activity(session);
        }
    };

    function commentary(id, item, options = {}) {
        const session = live;
        if (session === null || session.state.kind !== "running" || session.delegation !== id) return false;
        const isLine = options.line === true;
        if (isLine) {
            const waiting = session.speech.queue.findIndex(words => words.line === true);
            if (waiting !== -1) {
                session.speech.chars -= session.speech.queue[waiting].text.length;
                session.speech.queue.splice(waiting, 1);
            }
        } else {
            session.speech.chars -= session.speech.queue.filter(words => words.line === true)
                .reduce((sum, words) => sum + words.text.length, 0);
            session.speech.queue = session.speech.queue.filter(words => !words.line);
        }
        // Speakable sentences enter here; each model turn keeps its sentence's source labels.
        let text = item.content;
        while (text !== "") {
            let prefix = [...text].slice(0, SPEECH_CHARS).join("");
            if (prefix.length < text.length && prefix.lastIndexOf(" ") > 0) prefix = prefix.slice(0, prefix.lastIndexOf(" ") + 1);
            text = text.slice(prefix.length);
            if (session.speech.chars + prefix.length > QUEUE_CHARS) fail("speech-queue");
            session.speech.chars += prefix.length;
            session.speech.queue.push({ text: prefix, item, line: isLine });
        }
        // The first audio of these words raises speak; until then the session
        // shows the reply as due. A waiting or open reply carries them.
        if (session.next === null && !(session.playing !== null && session.playing.kind === "open")) session.events.due(true);
        speak(session);
        return true;
    }

    function captureSink() {
        const session = live;
        if (session === null) return null;
        const sink = new Writable({
            write(pcm, encoding, done) {
                done();
                // Frames in flight after the session ended; Session closes capture.
                if (session.capture !== sink || session.state.kind === "ended") return;
                if (pcm.length % 2 !== 0) { failed(session, "live=input-frame"); return; }
                session.inputAt = clock.now();
                // Only the loudest sample is kept, for the cause; no audio is.
                if (!session.answered) {
                    session.captured = true;
                    session.peak = Math.max(session.peak, peak(pcm));
                }
                if (input(session, pcm)) watch(session);
            }
        });
        session.capture = sink;
        sink.once("close", () => {
            if (session.capture !== sink) return;
            session.capture = null;
            session.inputAt = clock.now();
        });
        activity(session);
        return sink;
    }

    function playbackSource(source) {
        const session = live;
        if (session === null || session.op !== source || session.next === null) return null;
        const reply = session.next;
        session.next = null;
        session.playing = reply;
        session.taken = reply;
        reply.stream.once("close", () => {
            if (session.playing !== reply) return;
            session.playing = null;
            clear(session, "gap");
            activity(session);
        });
        settle(session);
        return reply.stream;
    }

    // Audio played the reply it took to its end, so the user heard every
    // sentence in it. The reply's stream closes earlier, once Audio has read it.
    function played(source) {
        const session = live;
        if (session === null || session.op !== source || session.taken === null) return;
        session.said.push(...session.taken.marks);
        session.taken = null;
        // Session hears Audio's played after this call; the idle report that
        // ends a preview's conversation waits for it, on a timer of its own
        // that the reply's close, which restarts the idle wait, leaves.
        if (session.preview !== null && session.delegation === PREVIEW && session.next === null && quiet(session))
            session.timers.preview = clock.set(() => { session.timers.preview = null; session.events.idle(); }, 0);
    }

    /**
     * What the user heard of one request's reply, read before the flush of
     * an interruption drops it: null when the session answers another
     * request. pending says words or audio are still unplayed. text(report)
     * joins the sentences heard to their end: those of every reply Audio
     * played out, and those that end within the frames Audio's flush report
     * credits to the reply at the speaker, none of them without a report.
     */
    function heardOf(id) {
        const session = live;
        if (session === null || session.delegation !== id) return null;
        const { said, taken, op } = session;
        return Object.freeze({
            pending: replyPending(session),
            text(report) {
                const bytes = report !== null && report.source === op ? report.heardFrames * 2 : 0;
                return [...said, ...(taken === null ? [] : taken.marks.filter(mark => mark.end <= bytes))]
                    .filter(mark => mark.request === id)
                    .filter(mark => !mark.line)
                    .reduce((all, mark) => all + (all === "" || all.endsWith(" ") ? "" : " ") + mark.text, "").trimEnd();
            }
        });
    }

    return Object.freeze({ port: Object.freeze(port), captureSink, playbackSource, played, commentary, heard: heardOf });
}

module.exports = { create, VOICES };
