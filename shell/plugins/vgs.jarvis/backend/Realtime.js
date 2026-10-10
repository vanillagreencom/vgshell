// The Realtime duplex speech engine: one provider session per conversation.
// It streams the microphone, hands each transcribed user turn to the brain as
// a delegation and has the voice read the brain's released sentences aloud.
// It keeps which of those responses the user heard to their end, for the
// brain's account of an interruption.
// The voice has no tools and never answers on its own. Session owns the
// lifetime through the speech port; Audio owns devices and calls captureSink
// and playbackSource. Protocol: OpenAI's Realtime guides and the event types
// of openai-node 7.31.0, read 2026-10-09. Contract:
// docs/decisions/D089-jarvis-chained-engine-and-heard-prefix.md.
"use strict";
const { Readable, Writable } = require("node:stream");
const Policy = require("./Policy.js");
const Providers = require("./Providers.js");
const Net = require("./net.js");
const Guidance = require("./Guidance.js");
const Speakable = require("./Speakable.js");
const { sourceLimit, PCM_RATE } = require("./Audio.js");

const FORMAT = Object.freeze({ type: "audio/pcm", rate: PCM_RATE });
// The transcription guide's model for text that arrives while the user
// speaks, which the captions need.
const TRANSCRIBE = "gpt-live-transcribe";
// Recovery bounds and grouping rules, not measured latency budgets.
const IDLE_MS = 60000;            // plan § 3.5
const START_WAIT_MS = 20000;      // connect, session.created and session.updated
const RESPONSE_WAIT_MS = 30000;   // response.create to its response.done
const REPLY_GAP_MS = 500;         // no words waiting for this long ends a playing reply
const SILENCE_TICK_MS = 100;
const SILENCE_MAX_MS = 1000;      // no catch-up past this after a stalled event loop
const PENDING_BYTES = PCM_RATE * 2 * START_WAIT_MS / 1000;  // queued input, opening words included
const APPEND_BYTES = PCM_RATE * 2;
const SEND_BACKLOG_BYTES = 256 * 1024;
const FRAME_CHARS = 1024 * 1024;
const TURN_CHARS = 65536;         // one user turn's transcript
const QUEUE_CHARS = 65536;        // released words waiting for the voice
// A response's audio cannot be paused. One response carries at most
// SPEECH_CHARS, and the next is asked for once playback has drained the reply
// to REPLY_LOW_BYTES, so the rest of Audio's allowance is one response's room.
const SPEECH_CHARS = 240;
const REPLY_BYTES = sourceLimit(false, false);
const REPLY_LOW_BYTES = PCM_RATE * 2 * 2;
const BASE64 = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

function fail(code) { throw new Error("jarvis: live=" + code); }
function plain(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function identity(value) {
    if (typeof value !== "string" || value === "" || value.length > 512) fail("frame-shape");
    return value;
}
// Provider codes and types are reported; provider message text is not.
function token(value) { return typeof value === "string" && /^[A-Za-z0-9_.-]{1,64}$/.test(value) ? value : "unrecognized"; }
function reasonOf(error) { return String(error.message).replace(/^jarvis: /, "").slice(0, 160); }
function clean(text) { return text.replace(/[\x00-\x1f\x7f]/g, " "); }

/**
 * The one narrowing door for a server message. Returns a tagged event or
 * throws a keyed error. An error event's message text is never read.
 */
function eventOf(data) {
    if (typeof data !== "string") fail("frame-binary");
    if (data.length > FRAME_CHARS) fail("frame-size");
    let value;
    try { value = JSON.parse(data); } catch { fail("frame-json"); }
    if (!plain(value) || typeof value.type !== "string") fail("frame-shape");
    switch (value.type) {
    case "session.created":
        return { kind: "created" };
    case "session.updated": {
        const audio = plain(value.session) ? value.session.audio : undefined;
        if (!plain(audio)) fail("frame-shape");
        for (const side of [audio.input, audio.output])
            if (!plain(side) || !plain(side.format) || side.format.type !== FORMAT.type || side.format.rate !== FORMAT.rate)
                fail("format");
        return { kind: "started" };
    }
    case "input_audio_buffer.speech_started":
        return { kind: "activity" };
    case "conversation.item.input_audio_transcription.delta":
        if (value.delta !== undefined && typeof value.delta !== "string") fail("frame-shape");
        return { kind: "hearing", item: identity(value.item_id), text: value.delta ?? "" };
    case "conversation.item.input_audio_transcription.completed":
        if (typeof value.transcript !== "string") fail("frame-shape");
        if (value.transcript.length > TURN_CHARS) fail("turn-size");
        return { kind: "heard", item: identity(value.item_id), text: value.transcript };
    case "conversation.item.input_audio_transcription.failed":
        return fail("transcription code=" + token(plain(value.error) ? value.error.code : undefined));
    case "response.created":
        return { kind: "speaking", id: identity(plain(value.response) ? value.response.id : undefined) };
    case "response.output_audio.delta": {
        if (typeof value.delta !== "string" || !BASE64.test(value.delta)) fail("output-audio");
        const pcm = Buffer.from(value.delta, "base64");
        if (pcm.length % 2 !== 0) fail("output-audio");
        return { kind: "audio", id: identity(value.response_id), pcm };
    }
    case "response.output_audio_transcript.delta":
        if (typeof value.delta !== "string") fail("frame-shape");
        return { kind: "said", id: identity(value.response_id), text: value.delta };
    case "response.done": {
        const response = plain(value.response) ? value.response : {};
        const id = identity(response.id);
        if (response.status !== "completed") {
            // The provider's cause: a failed response's error, an incomplete one's reason.
            const details = plain(response.status_details) ? response.status_details : {};
            fail("response status=" + token(response.status)
                + (plain(details.error) ? " type=" + token(details.error.type) + " code=" + token(details.error.code) : "")
                + (details.reason === undefined ? "" : " reason=" + token(details.reason)));
        }
        return { kind: "spoken", id };
    }
    case "error": {
        const error = plain(value.error) ? value.error : {};
        return fail("server-error type=" + token(error.type) + " code=" + token(error.code));
    }
    // Documented events this session causes and does not read.
    case "conversation.created": case "conversation.item.created": case "conversation.item.added":
    case "conversation.item.done": case "input_audio_buffer.speech_stopped": case "input_audio_buffer.committed":
    case "response.output_item.added": case "response.output_item.done": case "response.content_part.added":
    case "response.content_part.done": case "response.output_audio.done": case "response.output_audio_transcript.done":
    case "rate_limits.updated":
        return { kind: "ignored" };
    // Everything else answers a request this session never makes: a function
    // call, a text reply, a truncation or a cancel.
    default:
        return fail("event type=" + token(value.type));
    }
}

/**
 * create({provider, clock, conversation, captionLimit, log}) returns
 * {port, captureSink, playbackSource, played, commentary, heard}. provider is the Providers.select
 * "openai-realtime" row. conversation(e) answers {net, key, language, transfer, grants} for a
 * speech-open effect: the session's net owner, null or {secrets, reference},
 * the speech language, audited transfer and current release grants. captionLimit
 * is the wire's transcript bound. log receives keyed diagnostic lines. One
 * session at a time is live.
 */
function create({ provider, clock, conversation, captionLimit, log }) {
    Providers.assertRow(provider);
    if (provider.driver !== "openai-realtime") fail("driver");
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
        session.speech = { queue: [], chars: 0, active: null };
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
    function append(session, pcm) {
        try { send(session, { type: "input_audio_buffer.append", audio: pcm.toString("base64") }); }
        catch (error) { failed(session, reasonOf(error)); return false; }
        return true;
    }
    // Every input frame enters here, in order. Input waits for
    // session.updated, and new input waits behind queued input. Returns
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
    // The provider commits a turn when its voice activity detection hears the
    // speech end. While no microphone feeds it, silence gives it that end.
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
            // Words and their audio hold the session: a response's end and a
            // reply's close each restart this wait.
            if (session.playing !== null || session.next !== null || !quiet(session)) return;
            session.events.idle();
            // Session leaves a turn in flight to its own deadline and keeps
            // this session open; the wait then runs again.
            activity(session);
        }, IDLE_MS);
    }
    function quiet(session) { return session.speech.active === null && session.speech.queue.length === 0; }
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
    // One response at a time: out-of-band responses can run in parallel, and
    // their audio would mix. Returns false once the session has failed.
    function speak(session) {
        const speech = session.speech;
        const waiting = [session.playing, session.next].reduce((sum, reply) => sum + (reply === null ? 0 : reply.stream.readableLength), 0);
        if (session.state.kind !== "running" || speech.active !== null || speech.queue.length === 0 || waiting > REPLY_LOW_BYTES)
            return true;
        const words = speech.queue.shift();
        speech.chars -= words.text.length;
        speech.active = { id: null, discarded: false, said: false, text: words.text, request: session.delegation, reply: null };
        clear(session, "gap");
        // A response that never ends would hold every later word.
        session.timers.words = clock.set(() => failed(session, "live=response-timeout"), RESPONSE_WAIT_MS);
        // conversation "none" keeps the response out of the provider's
        // conversation, so no assistant item exists there to truncate.
        try {
            send(session, { type: "response.create", response: { conversation: "none", output_modalities: ["audio"],
                instructions: session.reader + "\n\n" + JSON.stringify(words.text) } }, [words.item]);
        } catch (error) { failed(session, reasonOf(error)); return false; }
        return true;
    }
    // The response the provider reports must be the one this session asked for.
    function asked(session, id, created) {
        const active = session.speech.active;
        if (active === null || (created ? active.id !== null : active.id !== id)) fail("event-order");
        return active;
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
        // A response cannot be paused: a full queue faults, never drops speech.
        if (!reply.stream.push(pcm)) failed(session, "live=output-overflow");
    }
    function emit(session, role, text, stage) {
        session.rev++;
        session.events.transcript({ role, text, stage, rev: session.rev });
    }
    // One open caption per speaker: a user turn's, or the reply's words so
    // far. A caption at the wire's bound closes and the rest starts the next.
    function caption(session, role, source, delta) {
        let text = clean(delta);
        let segment = session.segments[role];
        // Another user item's partial text takes the open caption over. The
        // item it leaves gets its caption from its completed transcript.
        if (segment !== null && segment.source !== source) segment = session.segments[role] = null;
        if (segment === null && text.trim() === "") return;
        while (text !== "") {
            if (segment !== null && segment.text.length === captionLimit) {
                conclude(session, role);
                segment = null;
            }
            if (segment === null) segment = session.segments[role] = { source, text: "" };
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
    function receive(session, data) {
        if (session.state.kind === "ended") return;
        let event;
        try { event = eventOf(data); } catch (error) { failed(session, reasonOf(error)); return; }
        const kind = session.state.kind;
        try {
            if (kind !== "running" && !["created", "started", "ignored"].includes(event.kind)) fail("event-order");
            switch (event.kind) {
            case "created":
                if (kind !== "connecting") fail("event-order");
                session.state = { kind: "starting" };
                send(session, session.update);
                break;
            case "started":
                if (kind !== "starting") fail("event-order");
                clear(session, "start");
                session.state = { kind: "running" };
                session.inputAt = clock.now();
                if (!pump(session)) return;
                silence(session);
                activity(session);
                break;
            case "activity": activity(session); break;
            case "hearing":
                activity(session);
                conclude(session, "assistant");
                caption(session, "user", event.item, event.text);
                break;
            case "heard":
                activity(session);
                conclude(session, "assistant");
                // The open caption closes on its own item's transcript. An item
                // with none open gets its caption whole, and another item's stays open.
                if (session.segments.user !== null && session.segments.user.source === event.item) conclude(session, "user");
                else for (let text = clean(event.text); text.trim() !== ""; text = text.slice(captionLimit))
                    emit(session, "user", text.slice(0, captionLimit), "final");
                if (event.text.trim() === "") break;
                // Words still waiting answer the request this one replaces.
                session.speech.queue = [];
                session.speech.chars = 0;
                // A playing reply with no words left to wait for ends after its gap.
                settle(session);
                // Heard responses are kept for the request in hand only.
                session.said = [];
                session.delegation = event.item;
                session.events.delegation({ id: event.item, text: clean(event.text) });
                break;
            case "speaking": asked(session, event.id, true).id = event.id; break;
            case "audio": {
                const active = asked(session, event.id, false);
                if (!active.discarded) output(session, active, event.pcm);
                break;
            }
            case "said": {
                const active = asked(session, event.id, false);
                if (active.discarded) break;
                caption(session, "assistant", null, (active.said || session.segments.assistant === null ? "" : " ") + event.text);
                active.said = true;
                break;
            }
            case "spoken": {
                const active = asked(session, event.id, false);
                // A whole response marks where its audio ends in the reply that carries it.
                if (!active.discarded && active.reply !== null)
                    active.reply.marks.push({ request: active.request, end: active.reply.bytes, text: active.text });
                session.speech.active = null;
                clear(session, "words");
                activity(session);
                if (speak(session)) settle(session);
                break;
            }
            case "ignored": break;
            default: throw new Error("jarvis: live=event-kind");
            }
        } catch (error) { failed(session, reasonOf(error)); }
    }
    function connect(session, { net, key, language, transfer, grants }) {
        session.transfer = transfer;
        session.grants = grants;
        session.language = language;
        if (key === null) fail("no-key");
        Net.assertKeyTarget(provider.base, key.reference.origin);
        session.reader = Guidance.compose("duplex", "duplex", language).instructions;
        // No tools, and create_response false: the voice has no function to
        // call and never answers a turn on its own.
        session.update = { type: "session.update", session: { type: "realtime", output_modalities: ["audio"], tools: [],
            audio: { input: { format: FORMAT, transcription: { model: TRANSCRIBE },
                turn_detection: { type: "semantic_vad", create_response: false, interrupt_response: false } },
                output: { format: FORMAT } }, ...provider.noStore } };
        const secret = key.secrets.lookup(key.reference);
        let answer;
        try {
            const item = Policy.item(provider.base, ["speech"]);
            answer = transfer(item, () => net.websocket(item, { url: provider.base,
                key: { origin: key.reference.origin, header: "authorization", prefix: "Bearer ", value: secret.toString("utf8") } }));
        } finally { secret.fill(0); }
        if (answer.kind !== "channel") fail("release-" + answer.kind);
        session.channel = answer;
        answer.events.addEventListener("message", event => receive(session, event.data));
        // WHATWG WebSocket fires close after every error, a refused redirect
        // included; close owns the outcome.
        answer.events.addEventListener("close", event => failed(session, "live=disconnected code=" + event.code));
    }

    const port = {
        open(e, events) {
            if (live !== null) throw new Error("jarvis: live=session-live");
            const session = { op: e.op, events, state: { kind: "connecting" }, channel: null, update: null, reader: "",
                timers: { start: null, silence: null, idle: null, gap: null, words: null },
                pending: [], pendingBytes: 0, inputAt: clock.now(), capture: null, playing: null, next: null,
                speech: { queue: [], chars: 0, active: null }, delegation: null, said: [], taken: null,
                segments: { user: null, assistant: null }, rev: 0, language: "" };
            live = session;
            session.timers.start = clock.set(() => failed(session, "live=start-timeout"), START_WAIT_MS);
            try { connect(session, conversation(e)); } catch (error) { failed(session, reasonOf(error)); }
        },
        // The session has no close event: closing the socket ends it.
        close(e) {
            if (live !== null && live.op === e.target) release(live);
        },
        // Lease loss: no socket or timer may hold the daemon.
        release() {
            if (live !== null) release(live);
        },
        // Drop the words not yet asked for, then the rest of the interrupted
        // response, by its identity. No response.cancel leaves: a cancel that
        // meets a finished response is answered with an error event.
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

    function commentary(id, item) {
        const session = live;
        if (session === null || session.state.kind !== "running" || session.delegation !== id) return false;
        // Speakable sentences enter here; each response keeps its sentence's source labels.
        let text = item.content;
        while (text !== "") {
            let prefix = [...text].slice(0, SPEECH_CHARS).join("");
            if (prefix.length < text.length && prefix.lastIndexOf(" ") > 0) prefix = prefix.slice(0, prefix.lastIndexOf(" ") + 1);
            text = text.slice(prefix.length);
            if (session.speech.chars + prefix.length > QUEUE_CHARS) fail("speech-queue");
            session.speech.chars += prefix.length;
            session.speech.queue.push({ text: prefix, item });
        }
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
                input(session, pcm);
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
    // response in it. The reply's stream closes earlier, once Audio has read it.
    function played(source) {
        const session = live;
        if (session === null || session.op !== source || session.taken === null) return;
        session.said.push(...session.taken.marks);
        session.taken = null;
    }

    /**
     * What the user heard of one request's reply, read before the flush of
     * an interruption drops it: null when the session answers another
     * request. pending says words or audio are still unplayed. text(report)
     * joins the responses heard to their end: those of every reply Audio
     * played out, and those that end within the frames Audio's flush report
     * credits to the reply at the speaker, none of them without a report.
     */
    function heard(id) {
        const session = live;
        if (session === null || session.delegation !== id) return null;
        const { said, taken, op } = session;
        return Object.freeze({
            pending: !quiet(session) || session.next !== null || taken !== null,
            text(report) {
                const bytes = report !== null && report.source === op ? report.heardFrames * 2 : 0;
                return [...said, ...(taken === null ? [] : taken.marks.filter(mark => mark.end <= bytes))]
                    .filter(mark => mark.request === id)
                    .reduce((all, mark) => all + (all === "" || all.endsWith(" ") ? "" : " ") + mark.text, "").trimEnd();
            }
        });
    }

    return Object.freeze({ port: Object.freeze(port), captureSink, playbackSource, played, commentary, heard });
}

module.exports = { create };
