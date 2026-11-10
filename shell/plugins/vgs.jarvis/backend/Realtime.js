// The Realtime duplex speech engine: one provider session per conversation.
// It streams the microphone, hands each transcribed user turn to the brain as
// a delegation and has the voice read the brain's released sentences aloud,
// each in an out-of-band response whose context holds only its words. It
// keeps which of those responses the user heard to their end, for the
// brain's account of an interruption.
// The voice has no tools and never answers on its own. Session owns the
// lifetime through the speech port; Audio owns devices and calls captureSink
// and playbackSource. Protocol: OpenAI's Realtime guides and the event types
// of openai-node 7.31.0, read 2026-10-09. The transcription's keywords
// field: the Realtime reference's AudioTranscription.keywords, "Words or
// phrases to guide transcription of the input audio. Supported by
// gpt-transcribe and gpt-live-transcribe", and the speech-to-text guide's
// keyword rule, read 2026-11-02. Contract:
// docs/decisions/D089-jarvis-chained-engine-and-heard-prefix.md.
"use strict";
const { Readable, Writable } = require("node:stream");
const Policy = require("./Policy.js");
const Providers = require("./Providers.js");
const Net = require("./net.js");
const Guidance = require("./Guidance.js");
const Speakable = require("./Speakable.js");
const Child = require("./Child.js");
const VoiceRollover = require("./VoiceRollover.js");
const { sourceLimit, PCM_RATE } = require("./Audio.js");

const FORMAT = Object.freeze({ type: "audio/pcm", rate: PCM_RATE });
// The transcription guide's model for text that arrives while the user
// speaks, which the captions need.
const TRANSCRIBE = "gpt-live-transcribe";
// Recovery bounds and grouping rules, not measured latency budgets.
const START_WAIT_MS = 20000;      // connect, session.created and session.updated
// Realtime conversations guide, read 2026-11-05: maximum session duration.
const SESSION_MS = 60 * 60 * 1000;
const RESPONSE_WAIT_MS = 30000;   // response.create to its response.done
const REPLY_GAP_MS = 500;         // no words waiting for this long ends a playing reply
const PUMP_MS = 100;
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
// The voices of audio.output.voice, as the Settings page offers them. The
// Realtime conversations guide lists these ten and recommends marin and
// cedar, read 2026-10-11; the first stands for the unset setting. Once the
// session has made audio its voice cannot change, so a new voice is a new
// session, as a changed setting ends the conversation.
const VOICES = Object.freeze(["marin", "cedar", "alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse"]
    .map(name => Object.freeze({ label: name[0].toUpperCase() + name.slice(1), value: name })));
// The delegation a preview's words answer: no user request exists.
const PREVIEW = "preview";
// The user's dictation vocabulary, which voxtype answers as `.replacements`
// of `voxtype config schema --json`, the resolved [text.replacements] table
// (voxtype 1.1.1). `voxtype config get` refuses that key. A recovery bound,
// not a measured budget, and an output ceiling above the 73 KiB the command
// printed on cachy, 2026-11-02.
const VOCABULARY_MS = 2000;
const VOCABULARY_BYTES = 1024 * 1024;
// setpriv's exit when the command it runs is not found: util-linux errexec,
// EX_EXEC_ENOENT, seen from setpriv 2.42.4, 2026-11-02.
const NOT_FOUND = 127;

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
// Server session.created/session.updated, RealtimeSessionCreateResponse:
// https://developers.openai.com/api/reference/resources/realtime/server-events
// This is session expiry, never the client_secret credential expiry.
function expiresAt(value) {
    const seconds = plain(value.session) ? value.session.expires_at : undefined;
    if (seconds === undefined) return null;
    if (!Number.isSafeInteger(seconds) || seconds < 0) fail("frame-shape");
    return seconds * 1000;
}

/**
 * The target words of the user's voxtype [text.replacements], once each in
 * the order voxtype lists them: {kind: "words", words}, empty when voxtype is
 * not installed or its table holds no word, or {kind: "unread", cause}.
 * The cause is a key built from Child.run's answer, never its output, which
 * can hold the table's words: the stop reason (timeout, output-limit,
 * cancelled), spawn=<code>, exit=<N>, signal=<S>, json when stdout does not
 * parse (voxtype 1.1.1 prints a WARN line there for a config section it
 * skips) or shape when .replacements is not a table of strings. The
 * speech-to-text guide keeps each keyword on one line with no < or >, and the
 * API rejects the whole request otherwise, so such a word is dropped. The
 * table's own replacements never touch a transcript: its left-hand forms are
 * voxtype's local engine's errors, not the provider's.
 */
async function vocabulary(clock, signal) {
    // PATH finds setpriv and voxtype; voxtype finds its config from HOME or
    // XDG_CONFIG_HOME. No other daemon variable, and so no key, reaches it.
    const env = { LC_ALL: "C.UTF-8" };
    for (const name of ["PATH", "HOME", "XDG_CONFIG_HOME"]) if (process.env[name] !== undefined) env[name] = process.env[name];
    const result = await Child.run("setpriv", ["--pdeathsig", "KILL", "--", "voxtype", "config", "schema", "--json"],
        { env, limit: VOCABULARY_BYTES, deadline: VOCABULARY_MS, group: true, signal, clock });
    const unread = cause => ({ kind: "unread", cause });
    if (result.kind === "stopped") return unread(result.reason);
    // Child.run's error is the spawn error's code, or its message when it has none.
    if (result.kind === "error") return unread(result.reason + "=" + token(result.error));
    if (result.code === NOT_FOUND) return { kind: "words", words: [] };
    if (result.code === null) return unread("signal=" + result.signal);
    if (result.code !== 0) return unread("exit=" + result.code);
    let table;
    try { table = JSON.parse(result.stdout).replacements; } catch { return unread("json"); }
    if (!plain(table) || !Object.values(table).every(word => typeof word === "string")) return unread("shape");
    return { kind: "words", words: [...new Set(Object.values(table))].filter(word => word.trim() !== "" && !/[<>\r\n]/.test(word)) };
}

/**
 * The one narrowing door for a server message. Returns a tagged event or
 * throws a keyed error. An error event's message text is never read.
 */
function eventOf(data, usage = () => {}) {
    if (typeof data !== "string") fail("frame-binary");
    if (data.length > FRAME_CHARS) fail("frame-size");
    let value;
    try { value = JSON.parse(data); } catch { fail("frame-json"); }
    if (!plain(value) || typeof value.type !== "string") fail("frame-shape");
    switch (value.type) {
    case "session.created":
        return { kind: "created", expiresAt: expiresAt(value) };
    case "session.updated": {
        const audio = plain(value.session) ? value.session.audio : undefined;
        if (!plain(audio)) fail("frame-shape");
        for (const side of [audio.input, audio.output])
            if (!plain(side) || !plain(side.format) || side.format.type !== FORMAT.type || side.format.rate !== FORMAT.rate)
                fail("format");
        return { kind: "started", expiresAt: expiresAt(value) };
    }
    case "input_audio_buffer.speech_started":
        return { kind: "activity" };
    case "input_audio_buffer.speech_stopped":
        return { kind: "stopped" };
    case "input_audio_buffer.committed":
        return { kind: "committed", item: identity(value.item_id) };
    // input_audio_buffer.clear succeeds with this server acknowledgement.
    // https://developers.openai.com/api/reference/resources/realtime/server-events
    case "input_audio_buffer.cleared":
        return { kind: "ignored" };
    case "conversation.item.input_audio_transcription.delta":
        if (value.delta !== undefined && typeof value.delta !== "string") fail("frame-shape");
        return { kind: "hearing", item: identity(value.item_id), text: value.delta ?? "" };
    case "conversation.item.input_audio_transcription.completed":
        usage({ call: "transcription", model: TRANSCRIBE, usage: value.usage });
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
        usage({ call: "realtime", usage: response.usage });
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
    case "conversation.item.done":
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
 * "openai-realtime" row. conversation(e) answers {net, key, language, voice, preview, transfer, grants} for a
 * speech-open effect: the session's net owner, null or {secrets, reference},
 * the speech language, a value of VOICES, the sentence a preview speaks or
 * null, audited transfer and current release grants. playbackSource answers
 * Audio's {readable, spoken}, spoken false for a preview. A preview session asks
 * for its sentence once it starts and reports idle once Audio played it, so
 * Session ends the conversation. captionLimit
 * is the wire's transcript bound. log receives keyed diagnostic lines. One
 * session at a time is live.
 * clock.now is monotonic; clock.wallNow converts the server's Unix expiry.
 * events.interrupted({id, text}) hands the engine a cap-cut reply's heard
 * prefix after Audio acknowledges its completed native response marks.
 */
function create({ provider, clock, conversation, captionLimit, log, usage = () => {} }) {
    Providers.assertRow(provider);
    if (provider.driver !== "openai-realtime") fail("driver");
    if (!Number.isSafeInteger(captionLimit) || captionLimit < 1) fail("caption-limit");
    let live = null;

    function clear(session, name) {
        if (session.timers[name] !== null) clock.clear(session.timers[name]);
        session.timers[name] = null;
    }
    function release(session) {
        session.rollover?.close();
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
        session.cut = null;
        session.reading.abort();
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
    function boundary(session) { session.rollover?.boundary(); }
    function repeatNotice(session) {
        if (session.repeatNotice) return;
        session.repeatNotice = true;
        session.events.renewal();
    }
    function reportCut(session) {
        const cut = session.cut;
        if (cut === null) return;
        session.cut = null;
        session.events.interrupted?.({ id: cut.id, text: cut.account.text(null) });
    }
    function renew(session, forced) {
        if (session.state.kind === "ended") return;
        session.rollover.close();
        const old = session.channel;
        session.channel = null;
        session.state = { kind: "connecting" };
        session.renewing = true;
        session.repeatNotice = false;
        if (forced) {
            const interrupted = (session.capture?.inputRecord.bytes ?? 0) !== 0
                || session.pending.length !== 0 || session.commits.length !== 0 || session.inputs.size !== 0;
            for (const capture of [...session.commits, ...session.inputs.values()]) capture.discarded = true;
            session.commits = [];
            session.inputs.clear();
            session.pending = [];
            session.pendingBytes = 0;
            if (interrupted) {
                session.capture?.discardInput();
                session.segments.user = null;
                repeatNotice(session);
            }
            // No timing can identify unplayed words inside a partial native
            // response. Cut that chunk rather than repeat words already heard.
            const active = session.speech.active;
            if (active !== null) {
                session.cut ??= { id: session.delegation, reply: active.reply, account: heard(session.delegation) };
                active.discarded = true;
                if (active.reply?.kind === "open") {
                    active.reply.kind = "ended";
                    active.reply.stream.push(null);
                }
                session.speech.active = null;
                clear(session, "words");
                if (session.speech.queue.length === 0) session.events.due(false);
                if (active.reply === null) reportCut(session);
            }
        }
        old?.close();
        clear(session, "start");
        session.timers.start = clock.set(() => failed(session, "live=start-timeout"), START_WAIT_MS);
        try { connect(session, conversation(session.effect)); } catch (error) { failed(session, reasonOf(error)); }
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
        if (session.state.kind === "running" && session.pending.length === 0 && session.channel.bufferedAmount === 0) return append(session, pcm);
        session.pendingBytes += pcm.length;
        if (session.pendingBytes > PENDING_BYTES) { failed(session, "live=input-overflow"); return false; }
        session.pending.push(Buffer.from(pcm));
        return pump(session);
    }
    // One FIFO holds PCM and native turn boundaries, so an end can never
    // overtake audio still waiting for connection or socket backpressure.
    function pump(session) {
        while (session.state.kind === "running" && session.pending.length > 0 && session.channel.bufferedAmount === 0) {
            const queued = session.pending[0];
            if (!Buffer.isBuffer(queued)) {
                session.pending.shift();
                try {
                    if (queued.clear) send(session, { type: "input_audio_buffer.clear" });
                    else {
                        // Bound native results a connected provider has not
                        // returned; each committed gate segment owns one.
                        if (session.commits.length + session.inputs.size >= 128) fail("input-results-overflow");
                        session.commits.push(queued.capture);
                        send(session, { type: "input_audio_buffer.commit" });
                    }
                } catch (error) { failed(session, reasonOf(error)); return false; }
                continue;
            }
            const pcm = queued.subarray(0, APPEND_BYTES);
            if (pcm.length === queued.length) session.pending.shift();
            else session.pending[0] = queued.subarray(pcm.length);
            session.pendingBytes -= pcm.length;
            if (!append(session, pcm)) return false;
        }
        if (session.pending.length !== 0) progress(session);
        return true;
    }
    // Drain bounded socket backpressure without generating microphone audio.
    // No periodic wake remains once the pending input and speech drain.
    function progress(session) {
        if (session.timers.pump !== null || session.state.kind === "ended") return;
        session.timers.pump = clock.set(() => {
            session.timers.pump = null;
            if (!pump(session) || !speak(session)) return;
            if (session.pending.length !== 0 || session.speech.queue.length !== 0) progress(session);
        }, PUMP_MS);
    }
    function inputResult(session, capture, text) {
        if (capture === undefined || capture === null) return;
        capture.pending--;
        capture.words ||= text.trim() !== "";
        reportInput(session, capture);
    }
    function reportInput(session, capture) {
        if (capture.discarded || capture.reported || !capture.committed
                || !capture.words && (!capture.closed || capture.pending !== 0)) return;
        capture.reported = true;
        session.events.inputEnded({ capture: capture.op, empty: !capture.words });
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
    // One response at a time: out-of-band responses can run in parallel, and
    // their audio would mix. Returns false once the session has failed.
    function speak(session) {
        const speech = session.speech;
        const waiting = [session.playing, session.next].reduce((sum, reply) => sum + (reply === null ? 0 : reply.stream.readableLength), 0);
        if (session.state.kind !== "running" || speech.active !== null || speech.queue.length === 0 || waiting > REPLY_LOW_BYTES)
            return true;
        const words = speech.queue.shift();
        speech.chars -= words.text.length;
        speech.active = { id: null, discarded: false, said: false, text: words.text, request: session.delegation, reply: null,
            line: words.line === true };
        clear(session, "gap");
        // A response that never ends would hold every later word.
        session.timers.words = clock.set(() => failed(session, "live=response-timeout"), RESPONSE_WAIT_MS);
        // conversation "none" keeps the response out of the provider's
        // conversation, so no assistant item exists there to truncate. It
        // still reads that conversation, which holds the user's own audio,
        // unless input gives it a context of its own (openai-node 7.31.0,
        // RealtimeResponseCreateParams.input: "creates a new context for this
        // Response instead of using the default conversation"). So the one
        // user message there carries the words as a JSON string, the one text
        // each request gives the reader, and no user item can reach it.
        try {
            send(session, { type: "response.create", response: { conversation: "none", output_modalities: ["audio"],
                instructions: session.reader, input: [{ type: "message", role: "user",
                    content: [{ type: "input_text", text: JSON.stringify(words.text) }] }] } }, [words.item]);
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
        try {
            event = eventOf(data, event => usage({ model: new URL(provider.base).searchParams.get("model"), ...event }));
        } catch (error) { failed(session, reasonOf(error)); return; }
        const kind = session.state.kind;
        try {
            if (kind !== "running" && !["created", "started", "ignored"].includes(event.kind)) fail("event-order");
            switch (event.kind) {
            case "created": {
                if (kind !== "connecting") fail("event-order");
                session.state = { kind: "starting" };
                const channel = session.channel;
                void session.vocabulary.then(answer => { if (session.channel === channel) configure(session, answer); });
                break;
            }
            case "started":
                if (kind !== "starting") fail("event-order");
                clear(session, "start");
                session.state = { kind: "running" };

                if (!pump(session)) return;

                if (session.preview !== null) {
                    session.delegation = PREVIEW;
                    commentary(PREVIEW, Policy.item(session.preview, ["desktop"]));
                }
                session.renewing = false;
                speak(session);
                break;
            case "activity": break;
            case "stopped": break;
            case "committed": {
                const capture = session.commits.shift();
                if (capture !== undefined) session.inputs.set(event.item, capture);
                break;
            }
            case "hearing":
                if (!session.inputs.has(event.item) || session.inputs.get(event.item).discarded) break;

                conclude(session, "assistant");
                caption(session, "user", event.item, event.text);
                break;
            case "heard": {
                const capture = session.inputs.get(event.item);
                session.inputs.delete(event.item);
                if (capture === undefined) break;
                inputResult(session, capture, event.text);
                if (capture?.discarded || session.state.kind === "ended") break;

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
            }
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
                    active.reply.marks.push({ request: active.request, end: active.reply.bytes, text: active.text, line: active.line });
                session.speech.active = null;
                clear(session, "words");

                boundary(session);
                if (speak(session)) settle(session);
                break;
            }
            case "ignored": break;
            default: throw new Error("jarvis: live=event-kind");
            }
            if (event.expiresAt !== undefined && event.expiresAt !== null)
                session.rollover.arm(clock.now() + event.expiresAt - clock.wallNow());
            boundary(session);
        } catch (error) { failed(session, reasonOf(error)); }
    }
    // The session's configuration, once the provider created it and the
    // vocabulary read answered. The words leave as the user's own desktop
    // text beside the speech frame, and no keywords field leaves without one.
    // No tools, and create_response false: the voice has no function to
    // call and never answers a turn on its own.
    function configure(session, answer) {
        if (session.state.kind !== "starting") return;
        if (answer.kind === "unread") log("jarvis: live=vocabulary-unread cause=" + answer.cause);
        const keywords = answer.kind === "words" ? answer.words : [];
        const transcription = keywords.length === 0 ? { model: TRANSCRIBE } : { model: TRANSCRIBE, keywords };
        const update = { type: "session.update", session: { type: "realtime", output_modalities: ["audio"], tools: [],
            audio: { input: { format: FORMAT, transcription,
                turn_detection: null },
                output: { format: FORMAT, voice: session.voice } }, ...provider.noStore } };
        const items = [Policy.item("", ["speech"])];
        if (keywords.length !== 0) items.push(Policy.item(keywords.join("\n"), ["desktop"]));
        try { send(session, update, items); } catch (error) { failed(session, reasonOf(error)); }
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
        session.voice = voice;
        const secret = key.secrets.lookup(key.reference);
        let answer;
        try {
            const item = Policy.item(provider.base, ["speech"]);
            answer = transfer(item, () => net.websocket(item, { url: provider.base,
                key: { origin: key.reference.origin, header: "authorization", prefix: "Bearer ", value: secret.toString("utf8") } }));
        } finally { secret.fill(0); }
        if (answer.kind !== "channel") fail("release-" + answer.kind);
        session.channel = answer;
        session.rollover = VoiceRollover.create({ clock, connectWait: START_WAIT_MS,
            idle: () => session.state.kind === "running" && session.pending.length === 0 && session.commits.length === 0
                && session.inputs.size === 0 && (session.capture?.inputRecord.bytes ?? 0) === 0 && session.speech.active === null,
            reconnect: forced => renew(session, forced) });
        session.rollover.arm(clock.now() + SESSION_MS);
        answer.events.addEventListener("message", event => { if (session.channel === answer) receive(session, event.data); });
        // WHATWG WebSocket fires close after every error, a refused redirect
        // included; close owns the outcome.
        // A handshake answered 401 or 403 refused the key; its body is never read.
        answer.events.addEventListener("close", event => {
            if (session.channel === answer) failed(session,
                Net.keyRefused(event) ? "live=key-refused" : "live=disconnected code=" + event.code);
        });
        // Read while the handshake runs. Node throws, rather than emits, a
        // spawn errno outside EACCES, EAGAIN, EMFILE, ENFILE and ENOENT
        // (lib/internal/child_process.js, Node 26.12.1).
        session.vocabulary ??= vocabulary(clock, session.reading.signal)
            .catch(error => ({ kind: "unread", cause: "thrown=" + token(error.code) }));
    }

    const port = {
        open(e, events) {
            if (live !== null) throw new Error("jarvis: live=session-live");
            const session = { op: e.op, effect: e, events, state: { kind: "connecting" }, channel: null, voice: null, reader: "",
                rollover: null, renewing: false, repeatNotice: false, cut: null,
                reading: new AbortController(), vocabulary: null,
                timers: { start: null, pump: null, gap: null, words: null, preview: null },
                pending: [], pendingBytes: 0, capture: null, commits: [], inputs: new Map(),
                playing: null, next: null,
                speech: { queue: [], chars: 0, active: null }, delegation: null, said: [], taken: null,
                segments: { user: null, assistant: null }, rev: 0, language: "", preview: null };
            live = session;
            session.timers.start = clock.set(() => failed(session, "live=start-timeout"), START_WAIT_MS);
            try { connect(session, conversation(e)); } catch (error) { failed(session, reasonOf(error)); }
        },
        // The session has no close event: closing the socket ends it.
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
        // response, by its identity. No response.cancel leaves: a cancel that
        // meets a finished response is answered with an error event.
        flush(e) {
            const session = live;
            if (session === null || session.op !== e.target) return;
            for (const capture of session.commits) capture.discarded = true;
            for (const capture of session.inputs.values()) capture.discarded = true;
            if (session.capture !== null) session.capture.inputRecord.discarded = true;
            session.pending = [];
            session.pendingBytes = 0;
            if (session.state.kind === "running") {
                try { send(session, { type: "input_audio_buffer.clear" }); }
                catch (error) { failed(session, reasonOf(error)); return; }
            }
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
            session.cut = null;

        }
    };

    function commentary(id, item, options = {}) {
        const session = live;
        if (session === null || session.state.kind !== "running" && !session.renewing || session.delegation !== id) return false;
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
        // Speakable sentences enter here; each response keeps its sentence's source labels.
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
        if (session.speech.queue.length !== 0) progress(session);
        return true;
    }

    function captureSink(e) {
        const session = live;
        if (session === null) return null;
        const record = () => ({ op: e.op, bytes: 0, committed: false, pending: 0,
            closed: false, words: false, reported: false, discarded: false });
        let capture = record();
        let discarding = false;
        const sink = new Writable({
            write(pcm, encoding, done) {
                if (session.capture !== sink || session.state.kind === "ended") { done(); return; }
                if (pcm.length % 2 !== 0) { done(new Error("jarvis: live=input-frame")); return; }
                if (discarding) { done(); return; }
                capture.bytes += pcm.length;
                input(session, pcm);
                done();
            }
        });
        sink.inputRecord = capture;
        sink.discardInput = () => { capture.discarded = true; discarding = true; };
        // Audio calls this only when its level gate closes. A true answer
        // records a native boundary queued locally, not provider acceptance
        // or recognized words. Native results retain the capture identity.
        sink.endInput = () => {
            if (discarding) {
                discarding = false;
                capture = record();
                sink.inputRecord = capture;
                boundary(session);
                return false;
            }
            if (session.state.kind === "ended" || capture.discarded || capture.bytes === 0) return false;
            const bytes = capture.bytes;
            capture.bytes = 0;
            // Realtime rejects a commit shorter than 100 ms; clear those
            // real captured bytes instead of manufacturing padding.
            // Provider diagnostic: openai/openai-agents-js issue #748.
            if (bytes < PCM_RATE * 2 / 10) {
                session.pending.push({ clear: true });
                pump(session);
                boundary(session);
                return false;
            }
            capture.committed = true;
            capture.pending++;
            session.pending.push({ capture });
            pump(session);
            return true;
        };
        session.capture = sink;
        sink.once("close", () => {
            capture.closed = true;
            reportInput(session, capture);
            if (session.capture === sink) session.capture = null;
            boundary(session);
        });
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

        });
        settle(session);
        // A preview's words are no reply, so voice mute leaves them audible.
        return { readable: reply.stream, spoken: session.preview === null };
    }

    // Audio played the reply it took to its end, so the user heard every
    // response in it. The reply's stream closes earlier, once Audio has read it.
    function played(source) {
        const session = live;
        if (session === null || session.op !== source || session.taken === null) return;
        session.said.push(...session.taken.marks);
        if (session.cut?.reply === session.taken) reportCut(session);
        session.taken = null;
        boundary(session);
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
     * joins the responses heard to their end: those of every reply Audio
     * played out, and those that end within the frames Audio's flush report
     * credits to the reply at the speaker, none of them without a report.
     */
    function heard(id) {
        const session = live;
        if (session === null || session.delegation !== id) return null;
        if (session.cut?.id === id) return { ...session.cut.account, pending: true };
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

    return Object.freeze({ port: Object.freeze(port), captureSink, playbackSource, played, commentary, heard });
}

module.exports = { create, VOICES };
