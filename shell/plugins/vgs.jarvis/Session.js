.pragma library

// The daemon owns this value. Time enters only through event.at (monotonic
// milliseconds). Adapter callbacks carry the gen/op returned in their effect.
// Cleanup acknowledgments and a running tool's outcome retain their original
// identity across stop; content callbacks do not. A duplex engine owns one
// speech session per conversation; its callbacks carry the session's gen/op.
// A dictation engine is the chained engine whose final words come from the
// core's dictation recording (D064), whose tones are the recording's cue.
var SESSION_SETTINGS = ["mode", "voiceProvider", "voice", "clonedVoice", "language", "brain", "model", "effort", "fallbacks", "customBaseUrl", "home", "policy", "cloudVision", "account", "voiceAccount"];
// A thinking turn's bound on a stalled brain: a running tool call holds it
// past the call's own limit and a finished one starts a fresh interval, so a
// brain that keeps working outlives one interval.
var RESPONSE_TIMEOUT_MS = 60000;
var COLLECTION_TIMEOUT_MS = 60000;
var VOICE_CHECK_MS = 3000;
var PLAYBACK_TIMEOUT_MS = 300000;
var APPROVAL_TIMEOUT_MS = 60000;
var APPROVAL_DRAW_MS = 700;
var VOICE_QUIET_MS = 1000;
// How long a wake-word request, or a spoken follow-up window, waits for its
// first words. The captions model decodes in 560 ms chunks (artifacts.json,
// nemotron), so speech shows as a partial within about a second; the rest is
// the pause a speaker takes after the start tone. Keeping the window short
// also keeps the time a television or another person can reach the AI model
// without a wake word short. A design choice, not a measurement.
var WAKE_SILENCE_MS = 6000;
// How long a tapped request listens after its last words, or after the tap
// while none came: the end of speech that sends it. About 6 s, chosen, not
// measured, so a speaker can pause mid-request without it being sent.
var TAP_SILENCE_MS = 6000;
// A Talk press released sooner than this is a tap: the microphone stays open
// until the next press or the end of speech. Hyprland's default
// input:repeat_delay, 600 ms, is the bound the core's tap tracker uses for a
// tap (HyprlandLayer.tapTrackerLines), so a key held longer than a repeat
// would start counts as a hold here too.
var TAP_MS = 600;
var TRANSCRIPT_CHARS = 4096;
var EVENTS = [
    "snapshot", "indicator", "talk-down", "talk-up", "toggle", "mute", "unmute", "mute-toggle",
    "stop", "cancel", "interrupt", "capture-opened", "capture-closed", "capture-failed", "playback-failed", "partial",
    "final", "say", "collect-failed", "brain-done", "brain-failed", "brain-ended", "cancelled", "play", "played",
    "flushed", "tool", "tool-done", "approval", "shown", "confirm", "approval-cancel", "deadline", "lease-ended",
    "speak", "speech-due", "transcript", "speech-idle", "speech-failed", "feedback", "delegation", "relay", "wake", "voice-check", "voice-checked", "voice-check-failed",
    "preview"
];

function initial() {
    return {
        gen: 0, nextOp: 1, stale: 0, settings: {},
        gate: { kind: "down", reason: "starting" },
        mute: { kind: "off" }, capture: { kind: "closed" },
        turn: { kind: "none" }, brain: { kind: "closed" }, playback: { kind: "idle" },
        action: { kind: "none" }, approval: { kind: "none" }, fault: { kind: "none" },
        conversation: { kind: "ended" }, input: { kind: "released" }, followUp: { kind: "none" },
        indicator: { kind: "gone" }, duplex: { kind: "half" }, toggleAt: null,
        engine: { kind: "chained" }, speech: { kind: "closed" }, check: { kind: "unavailable" }, checkSource: null
    };
}

// One phase judge for the wire and the shell. Closing/flushing do not claim
// listening/speaking; mute completion waits for capture's close acknowledgment.
function phaseOf(s) {
    if (s.check.kind === "recording" && s.capture.kind === "open") return "listening";
    if (s.gate.kind === "down") return "down";
    if (s.fault.kind !== "none") return "error";
    if (s.approval.kind === "held") return "confirming";
    if (s.action.kind === "running") return "acting";
    // A duplex reply speaks from the moment its words go to the voice, as a
    // chained reply does from its play, before the voice's first audio, and
    // as one held behind a spoken line does.
    if (s.playback.kind === "playing" || s.playback.kind === "feedback" && s.playback.reply.kind === "waiting"
            || s.speech.kind === "open" && s.speech.reply.kind === "due") return "speaking";
    if (s.turn.kind === "thinking" || s.turn.kind === "cancelling") return "thinking";
    if (s.capture.kind === "open" && s.capture.mode !== "armed") return "listening";
    if (s.capture.kind === "open") return "armed";
    return "idle";
}

// Demand precedes capture admission. Waiting for capture here would wait
// forever for the indicator that must be presented before capture opens.
function indicatorWanted(s) {
    if (["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1) return true;
    if (s.capture.kind !== "closed") return true;
    var phase = phaseOf(s);
    if (phase !== "idle" && phase !== "down") return true;
    return canEngage(s) && (s.input.kind === "armed"
        || s.conversation.kind !== "ended" && s.input.kind !== "released");
}

function operation(s) { return s.nextOp++; }

function effect(s, effects, kind, values) {
    var e = { kind: kind, gen: s.gen, op: operation(s) };
    for (var key of Object.keys(values || {})) e[key] = values[key];
    effects.push(e);
    return e;
}

function closeCapture(s, effects) {
    if (s.capture.kind !== "open" && s.capture.kind !== "opening") return;
    var e = effect(s, effects, "capture-close", { target: s.capture.op });
    s.capture = { kind: "closing", gen: e.gen, op: e.op };
}

function cancelTurn(s, effects, at) {
    if (s.playback.kind === "flushing") s.playback.reply = { kind: "none" };
    if (s.turn.kind === "thinking") {
        var old = s.turn;
        s.turn = { kind: "cancelling", gen: old.gen, op: old.op, deadline: at + 2000 };
        effect(s, effects, "brain-cancel", { gen: old.gen, target: old.op });
    } else if (s.turn.kind === "collecting") s.turn = { kind: "none" };
}

// The engine finalizes a closed session on its own; a later callback from it
// is stale. Lease loss aborts instead of waiting for the provider.
function closeSpeech(s, effects, mode) {
    if (s.speech.kind !== "open") return;
    effect(s, effects, "speech-close", { gen: s.speech.gen, target: s.speech.op, mode: mode });
    s.speech = { kind: "closed" };
}

function closeBrain(s, effects) {
    if (s.brain.kind === "closed") return;
    effect(s, effects, "brain-close", { gen: s.brain.gen, target: s.brain.op });
    s.brain = { kind: "closed" };
}

function flushPlayback(s, effects) {
    if (s.playback.kind === "flushing") s.playback.reply = { kind: "none" };
    if (["playing", "feedback"].indexOf(s.playback.kind) === -1) return;
    var old = s.playback;
    var e = effect(s, effects, "playback-flush", { gen: old.gen, target: old.op });
    s.playback = { kind: "flushing", gen: e.gen, op: e.op, reply: { kind: "none" } };
}

function dropApproval(s, effects, reason, at) {
    if (s.approval.kind !== "held") return;
    effect(s, effects, "approval-ended", { gen: s.approval.gen, target: s.approval.op,
        id: s.approval.id, purpose: s.approval.purpose, reason: reason });
    s.approval = { kind: "none" };
    if (s.turn.kind === "thinking") s.turn.deadline = at + RESPONSE_TIMEOUT_MS;
}

// The running action has its own limit; its turn's interval ends no sooner
// than a full interval after that limit.
function holdThinking(s) {
    if (s.turn.kind === "thinking" && s.turn.op === s.action.brain)
        s.turn.deadline = Math.max(s.turn.deadline, s.action.limit.deadline + RESPONSE_TIMEOUT_MS);
}

function requestToolCancel(s, effects) {
    if (s.action.kind !== "running" || s.action.cancellation.kind !== "available") return;
    effect(s, effects, "tool-cancel", { gen: s.action.gen, target: s.action.op, tool: s.action.tool });
    s.action.cancellation = { kind: "requested" };
}

function end(s, effects, at, reason, stopTool) {
    if (["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1) s.check = { kind: "ready" };
    if (s.conversation.kind !== "ended") {
        s.gen++;
        s.conversation = { kind: "ended" };
    }
    // A dismissed fault stays paused through teardown until Talk starts again.
    if (s.input.kind !== "stopped") s.input = { kind: "released" };
    closeCapture(s, effects);
    cancelTurn(s, effects, at);
    if (s.turn.kind === "none") closeBrain(s, effects);
    flushPlayback(s, effects);
    closeSpeech(s, effects, reason === "lease" ? "abort" : "graceful");
    dropApproval(s, effects, reason, at);
    if (stopTool) requestToolCancel(s, effects);
}

function canEngage(s) {
    return s.gate.kind === "up" && s.mute.kind === "off" && s.fault.kind !== "error";
}

function canCheck(s) {
    return s !== null && ["ready", "again", "done", "failed"].indexOf(s.check.kind) !== -1 && s.fault.kind === "none" && s.mute.kind === "off"
        && (s.gate.kind === "up" || s.gate.reason === "unconfigured")
        && s.turn.kind === "none" && s.playback.kind === "idle" && s.action.kind !== "running" && s.approval.kind !== "held";
}

function canCapture(s) {
    var checking = s.input.kind === "check" && (s.gate.kind === "up" || s.gate.reason === "unconfigured")
        && s.fault.kind === "none" && s.mute.kind === "off" && ["waiting", "recording"].indexOf(s.check.kind) !== -1;
    return (canEngage(s) || checking) && s.indicator.kind === "shown"
        && s.playback.kind === "idle" && s.turn.kind !== "cancelling" && s.input.kind !== "released"
        && (s.conversation.kind !== "ended" || s.input.kind === "armed" || checking);
}

// Always mode listens for the wake word only while Jarvis is otherwise
// idle: no turn, sound, action or held request, and never for a duplex
// engine, whose capture streams to its provider. A wake capture is the
// local chained engine's alone; it collects no utterance.
function armedWanted(s) {
    return s.settings.mode === "always" && s.engine.kind !== "duplex" && canEngage(s)
        && ["waiting", "recording", "finishing"].indexOf(s.check.kind) === -1
        && s.turn.kind === "none" && s.playback.kind === "idle"
        && s.approval.kind === "none" && s.action.kind === "none";
}

function closeArmed(s, effects) {
    if ((s.capture.kind === "open" || s.capture.kind === "opening") && s.capture.mode === "armed")
        closeCapture(s, effects);
}

function sayRefusal(s) {
    if (s === null || s.gate.kind !== "up") return "down";
    if (s.mute.kind !== "off") return "muted";
    if (s.engine.kind === "duplex") return "duplex";
    if (s.approval.kind === "held") return "held";
    if (s.playback.kind !== "idle") return "speaking";
    if (s.action.kind === "running" || s.turn.kind === "thinking" || s.turn.kind === "cancelling") return "busy";
    return null;
}

function captionText(value) {
    var text = String(value).replace(/[\x00-\x1f\x7f]/g, " ").slice(-TRANSCRIPT_CHARS);
    return text.trim() === "" ? "" : text;
}

// A coding task's line speaks only into an open chained conversation, and
// only at an idle moment: "busy" waits for the next one, any other refusal
// leaves the line to a desktop notification (TaskVoice.js).
function relayRefusal(s) {
    if (s.gate.kind !== "up") return "down";
    if (s.mute.kind !== "off") return "muted";
    if (s.engine.kind === "duplex") return "duplex";
    if (s.fault.kind !== "none") return "fault";
    if (s.conversation.kind === "ended") return "ended";
    if (s.turn.kind !== "none" || s.playback.kind !== "idle" || s.approval.kind !== "none" || s.action.kind !== "none"
            || s.input.kind !== "released" || s.capture.kind !== "closed") return "busy";
    return null;
}

// Why a voice preview cannot start now, or null. It speaks between turns,
// never over one, and a duplex voice speaks it in a session of its own.
function previewRefusal(s) {
    if (s === null || s.gate.kind !== "up") return "down";
    if (s.mute.kind !== "off") return "muted";
    if (s.turn.kind !== "none" || s.playback.kind !== "idle" || s.approval.kind !== "none" || s.action.kind !== "none"
            || ["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1
            || s.engine.kind === "duplex" && s.conversation.kind !== "ended") return "busy";
    return null;
}

function relayAsk(ask) {
    return ask === null || exact(ask, ["task", "prompt", "kind"]) && typeof ask.task === "string"
        && typeof ask.prompt === "string" && ["permission", "question"].indexOf(ask.kind) !== -1;
}

function userTranscript(s, effects, text, rev) {
    var shown = captionText(text);
    if (shown !== "") effect(s, effects, "transcript", { role: "user", text: shown, stage: "final", rev: rev });
}

function commitUserText(s, effects, text, at, rev, voiceRequest) {
    if (s.conversation.kind === "interrupted") s.conversation = { kind: "active" };
    if (s.conversation.kind === "ended") {
        s.gen += 1;
        s.conversation = { kind: "active" };
    }
    if (voiceRequest === true && s.settings.mode === "always" && s.engine.kind !== "duplex")
        s.followUp = { kind: "asked", gen: s.gen };
    if (s.input.kind === "held" || s.settings.mode === "always") s.input = { kind: "released" };
    closeCapture(s, effects);
    userTranscript(s, effects, text, rev);
    think(s, effects, { text: text }, at);
}

// One thinking turn of the conversation's brain owner. A relay turn holds the
// owner too, so a later user turn keeps the conversation's history.
function think(s, effects, values, at) {
    var brain = effect(s, effects, "brain-send", values);
    if (s.brain.kind === "closed") s.brain = { kind: "acquired", gen: brain.gen, op: brain.op };
    brain.owner = s.brain.op;
    s.turn = { kind: "thinking", gen: brain.gen, op: brain.op, deadline: at + RESPONSE_TIMEOUT_MS };
}

function canPlayback(s) {
    return s.gate.kind === "up" && s.fault.kind !== "error" && ["playing", "feedback"].indexOf(s.playback.kind) !== -1
        && s.capture.kind === "closed";
}

// A duplex reply plays when the conversation is live. Half duplex never runs
// capture and playback together, so a held talk key keeps the microphone.
function canSpeak(s) {
    return canEngage(s) && s.conversation.kind === "active" && s.playback.kind === "idle"
        && s.input.kind !== "held";
}

function reconcile(s, effects, at) {
    // The window opens only as the reply ends. A turn that ends while
    // something else holds Jarvis, such as a tool past its limit, drops it,
    // so it never opens later with no reply just spoken.
    if (s.followUp.kind !== "none" && s.turn.kind === "none" && s.playback.kind === "idle") {
        if (s.followUp.kind === "spoken" && s.followUp.gen === s.gen && s.input.kind === "released"
                && s.action.kind === "none" && s.approval.kind === "none" && canEngage(s)
                && s.conversation.kind === "active" && s.settings.mode === "always" && s.engine.kind !== "duplex")
            s.input = { kind: "follow-up" };
        s.followUp = { kind: "none" };
    }
    if (s.input.kind === "armed" && !armedWanted(s)) s.input = { kind: "released" };
    else if (s.input.kind === "released" && armedWanted(s)) s.input = { kind: "armed" };
    if (s.speech.kind === "open" && s.speech.reply.kind === "waiting" && canSpeak(s)) {
        s.playback = { kind: "playing", gen: s.gen, op: operation(s), source: s.speech.op,
            interruptible: true, admission: { kind: "waiting" }, deadline: at + PLAYBACK_TIMEOUT_MS };
        s.speech.reply = { kind: "none" };
    }
    // The session opens with the conversation's first capture, before it.
    if (s.engine.kind === "duplex" && s.speech.kind === "closed" && canCapture(s)) {
        var speech = effect(s, effects, "speech-open", {});
        s.speech = { kind: "open", gen: speech.gen, op: speech.op, reply: { kind: "none" } };
    }
    if (!canCapture(s)) closeCapture(s, effects);
    else if (s.capture.kind === "closed") {
        var mode = s.input.kind === "held" || s.input.kind === "tapped" ? "hold" : s.input.kind === "woken" ? "conversation" : s.input.kind;
        var e = effect(s, effects, "capture-open", { mode: mode });
        s.capture = { kind: "opening", gen: e.gen, op: e.op, mode: mode };
        if (mode === "check") s.check = { kind: "waiting", gen: e.gen, op: e.op, deadline: at + COLLECTION_TIMEOUT_MS };
    }
    if (s.turn.kind === "collecting" && s.capture.kind === "closing" && s.turn.deadline === null)
        s.turn.deadline = at + COLLECTION_TIMEOUT_MS;
    // The duplex voice model owns turn-taking; no utterance is collected.
    if (s.engine.kind !== "duplex" && canCapture(s) && s.input.kind !== "armed" && s.input.kind !== "check"
            && (s.capture.kind === "opening" || s.capture.kind === "open") && s.turn.kind === "none") {
        var collect = effect(s, effects, "collect", {});
        s.turn = { kind: "collecting", gen: collect.gen, op: collect.op, partial: "", deadline: at + COLLECTION_TIMEOUT_MS };
    }
    if (["playing", "feedback"].indexOf(s.playback.kind) !== -1 && s.playback.admission.kind === "waiting" && canPlayback(s)) {
        effect(s, effects, "playback-start", { gen: s.playback.gen, op: s.playback.op, source: s.playback.source });
        s.playback.admission = { kind: "started" };
    }
    if (s.mute.kind === "muting" && s.capture.kind === "closed") s.mute = { kind: "on" };
}

function start(s, effects, mode, at) {
    if (!canEngage(s)) return;
    if (["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1) end(s, effects, at, "talk", false);
    if (s.conversation.kind === "ended") {
        s.gen++;
        s.conversation = { kind: "active" };
    } else if (s.conversation.kind === "interrupted") s.conversation = { kind: "active" };
    // A wake capture feeds the spotter, not a transcription.
    closeArmed(s, effects);
    s.input = mode === "held" ? { kind: "held", since: at } : { kind: mode };
    // Half duplex: the start sound drains before the microphone opens.
    // A held approval's answer starts capture without another prompt sound,
    // and a dictation recording sounds voxtype's own start tone.
    if (s.settings.sounds === true && s.engine.kind === "chained"
            && s.playback.kind === "idle" && s.approval.kind === "none") {
        var cue = operation(s);
        s.playback = { kind: "feedback", gen: s.gen, op: cue, source: cue, cue: "start",
            admission: { kind: "waiting" }, deadline: at + PLAYBACK_TIMEOUT_MS, reply: { kind: "none" } };
    }
    reconcile(s, effects, at);
}

// A callback must match its owner, not merely the newest allocated number.
// Draining operations remain live only for their cleanup/outcome event.
function live(s, e, region, kinds) {
    var owner = s[region];
    return kinds.indexOf(owner.kind) !== -1 && e.gen === owner.gen && e.op === owner.op;
}

function stale(s) { s.stale++; }

function changedSettings(a, b) {
    for (var key of SESSION_SETTINGS) {
        if (key === "fallbacks") {
            if (JSON.stringify(a[key] ?? []) !== JSON.stringify(b[key] ?? [])) return true;
        } else if (a[key] !== b[key]) return true;
    }
    return false;
}

function canPropose(s) {
    return s.conversation.kind === "active" && s.action.kind === "none" && s.approval.kind === "none";
}

function toolDuration(e) {
    if (!Number.isFinite(e.timeoutMs) || e.timeoutMs <= 0)
        throw new Error("jarvis: session=tool-deadline tool=" + e.tool);
}

function interrupt(s, effects, at) {
    if (s.conversation.kind === "ended") return;
    s.conversation = { kind: "interrupted" };
    cancelTurn(s, effects, at);
    flushPlayback(s, effects);
    // A duplex engine drops its waiting words and the rest of the interrupted
    // reply. The brain's next turn carries the part Audio reports as heard.
    if (s.speech.kind === "open") {
        effect(s, effects, "speech-flush", { gen: s.speech.gen, target: s.speech.op });
        s.speech.reply = { kind: "none" };
    }
    dropApproval(s, effects, "interrupt", at);
}

// A failed turn's fault stays shown until the next Talk press, which ends
// what is left of that conversation so the press starts a new one.
function recover(s, effects, at) {
    if (s.fault.kind !== "error" || s.gate.kind !== "up" || s.mute.kind !== "off") return;
    end(s, effects, at, "recover", false);
    s.fault = { kind: "none" };
}

// A press within 250 ms of the last one is a bounce, not a press: it
// leaves the fault shown.
function bounced(s, at) { return s.toggleAt !== null && at - s.toggleAt < 250; }

function toggle(s, effects, at) {
    if (bounced(s, at)) return;
    recover(s, effects, at);
    if (!canEngage(s)) return;
    s.toggleAt = at;
    if (s.conversation.kind === "ended" || s.input.kind === "released" && s.turn.kind === "none" && s.approval.kind === "none" && s.action.kind === "none") start(s, effects, "conversation", at);
    else end(s, effects, at, "toggle", false);
}

// Always mode's Talk listens now, as Hold's press does: it stops a reply,
// cancels a turn or clears a fault first. A press while a request is being
// heard ends the conversation, as Toggle does, and the word is awaited again.
function listenNow(s, effects, at) {
    if (bounced(s, at)) return;
    if ((s.input.kind === "conversation" || s.input.kind === "woken" || s.input.kind === "follow-up")
            && s.turn.kind === "collecting") {
        s.toggleAt = at;
        end(s, effects, at, "toggle", false);
        return;
    }
    recover(s, effects, at);
    if (!canEngage(s)) return;
    s.toggleAt = at;
    interrupt(s, effects, at);
    start(s, effects, "conversation", at);
}

function expire(s, effects, at) {
    // A tapped request ends at the end of speech, for every engine: the
    // bound the tapped input holds while its microphone is open.
    if (s.input.kind === "tapped" && s.input.deadline !== null && s.capture.kind === "open" && at >= s.input.deadline) {
        s.input = { kind: "released" };
        closeCapture(s, effects);
    }
    if (["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1 && at >= s.check.deadline) {
        if (s.check.kind === "recording") {
            s.input = { kind: "released" };
            closeCapture(s, effects);
            s.check = { kind: "finishing", gen: s.check.gen, op: s.check.op, deadline: at + COLLECTION_TIMEOUT_MS };
        } else {
            end(s, effects, at, "check-timeout", false);
            s.check = { kind: "failed", reason: "check-timeout", device: s.checkSource };
        }
    }
    // A woken request that heard nothing was a false wake: Always mode goes
    // back to waiting for the word, with no fault to clear first.
    if (s.turn.kind === "collecting" && s.turn.deadline !== null && at >= s.turn.deadline) {
        if (s.input.kind === "woken") end(s, effects, at, "wake-silence", false);
        else if (s.input.kind === "follow-up") {
            s.input = { kind: "released" };
            closeCapture(s, effects);
            s.turn = { kind: "none" };
        }
        else {
            s.fault = { kind: "error", reason: "speech=collect-timeout", retry: 0 };
            end(s, effects, at, "collect-timeout", false);
        }
    }
    if (["playing", "feedback"].indexOf(s.playback.kind) !== -1 && s.playback.deadline !== null && at >= s.playback.deadline) {
        s.fault = { kind: "error", reason: "playback-timeout", retry: 0 };
        end(s, effects, at, "playback-timeout", false);
    }
    if (s.turn.kind === "thinking" && s.approval.kind !== "held" && at >= s.turn.deadline) {
        dropApproval(s, effects, "thinking-timeout", at);
        cancelTurn(s, effects, at);
        s.fault = { kind: "error", reason: "thinking-timeout", retry: 0 };
        s.input = { kind: "released" };
        closeCapture(s, effects);
    } else if (s.turn.kind === "cancelling" && at >= s.turn.deadline) {
        closeBrain(s, effects);
        s.turn = { kind: "none" };
    }
    if (s.approval.kind === "held" && at >= s.approval.deadline) {
        dropApproval(s, effects, "timeout", at);
        s.input = { kind: "released" };
        closeCapture(s, effects);
    }
    if (s.action.kind === "running" && s.action.limit.kind === "pending" && at >= s.action.limit.deadline) {
        requestToolCancel(s, effects);
        effect(s, effects, "tool-outcome", { gen: s.action.gen, target: s.action.brain,
            source: s.action.op, tool: s.action.tool, outcome: "unknown" });
        // Expiry does not prove that the tool's external effects have ended.
        s.action.limit = { kind: "expired" };
    }
}

// Return a new state and ordered effects. The input state/event are untouched.
// The router supplies authorized proposals. Session owns confirmation identity
// and timing, not the typed call or the policy decision.
function reduce(state, e) {
    if (EVENTS.indexOf(e.type) === -1) throw new Error("jarvis: session=event type=" + e.type);
    if (!Number.isFinite(e.at) || e.at < 0) throw new Error("jarvis: session=clock");
    var s = JSON.parse(JSON.stringify(state));
    var effects = [];
    var expiredApproval = s.approval.kind === "held" && e.at >= s.approval.deadline
        ? s.approval : null;
    // A late callback cannot outrun a delayed event-loop timer.
    if (e.type !== "deadline") expire(s, effects, e.at);
    switch (e.type) {
    case "snapshot": {
        if (["chained", "dictation", "duplex"].indexOf(e.engine) === -1) throw new Error("jarvis: session=engine");
        var settingsChanged = changedSettings(s.settings, e.settings) || s.engine.kind !== e.engine;
        var devicesChanged = s.settings.microphone !== e.settings.microphone || s.settings.speaker !== e.settings.speaker;
        // A check's result belongs to the source it heard: another source,
        // such as a new default microphone, asks for the check again and
        // says why. An unknown source, before discovery, changes nothing.
        var source = typeof e.checkSource === "string" ? e.checkSource : null;
        if (source !== null && ["done", "failed", "kept"].indexOf(s.check.kind) !== -1 && s.check.device !== source) s.check = { kind: "again" };
        // A check under way heard the source it started on, which Audio may
        // still record: a move to another ends it and asks again.
        else if (source !== null && s.checkSource !== null && source !== s.checkSource
                && ["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1) {
            end(s, effects, e.at, "check-source", false);
            s.check = { kind: "again" };
        }
        s.checkSource = source;
        if (devicesChanged && s.fault.kind === "error" && s.fault.reason === "device-lost")
            s.fault = { kind: "none" };
        if (settingsChanged || devicesChanged && ["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1) {
            var before = s.gen;
            end(s, effects, e.at, "settings", false);
            if (s.gen === before) s.gen++;
            s.fault = { kind: "none" };
        }
        s.settings = JSON.parse(JSON.stringify(e.settings));
        if (s.settings.sounds !== true && s.playback.kind === "feedback" && s.playback.cue !== "line") flushPlayback(s, effects);
        s.engine = { kind: e.engine };
        if (e.locked !== false || !e.configured) {
            if (e.locked !== false || e.checkReady !== true || ["waiting", "recording", "finishing"].indexOf(s.check.kind) === -1) end(s, effects, e.at, "gate", false);
            s.gate = { kind: "down", reason: e.locked === null ? "lock-unknown"
                : e.locked ? "locked" : "unconfigured" };
        } else s.gate = { kind: "up" };
        // A voice that cannot check, a cloud one, keeps a check that ended,
        // so a change of voice provider on the same devices keeps its result.
        if (e.checkReady !== true) {
            if (["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1) end(s, effects, e.at, "voice-unavailable", false);
            s.check = s.check.kind === "done" || s.check.kind === "kept" ? { kind: "kept", result: s.check.result, device: s.check.device } : { kind: "unavailable" };
        } else if (s.check.kind === "unavailable") s.check = { kind: "ready" };
        else if (s.check.kind === "kept") s.check = { kind: "done", result: s.check.result, device: s.check.device };
        break;
    }
    case "indicator":
        s.indicator = { kind: e.shown ? "shown" : "gone" };
        if (!e.shown && s.input.kind === "check" && s.capture.kind !== "closed") end(s, effects, e.at, "indicator", false);
        break;
    case "voice-check":
        if (!canCheck(s)) break;
        end(s, effects, e.at, "voice-check", false);
        s.check = { kind: "waiting", gen: s.gen, op: operation(s), deadline: e.at + COLLECTION_TIMEOUT_MS };
        s.input = { kind: "check" };
        break;
    case "voice-checked":
        if (!live(s, e, "check", ["finishing"])) { stale(s); break; }
        if (["ready", "silent", "not-heard"].indexOf(e.result) === -1) throw new Error("jarvis: session=check-result");
        s.check = { kind: "done", result: e.result, device: s.checkSource };
        break;
    case "voice-check-failed":
        if (!live(s, e, "check", ["waiting", "recording", "finishing"])) { stale(s); break; }
        end(s, effects, e.at, "check-failed", false);
        s.check = { kind: "failed", reason: e.reason, device: s.checkSource };
        break;
    case "talk-down":
        if (s.approval.kind === "held") {
            if (s.input.kind !== "held") {
                // Toggle can reopen capture before the brain proposes a hold.
                // Its transcript owns no answer identity. Talk replaces it,
                // then capture-closed admits an answer bound to this hold.
                closeCapture(s, effects);
                start(s, effects, "held", e.at);
            }
            break;
        }
        if (s.settings.mode === "toggle") { toggle(s, effects, e.at); break; }
        if (s.settings.mode === "always") { listenNow(s, effects, e.at); break; }
        if (s.input.kind === "held") break;
        // The press after a tap sends the words, as a release does.
        if (s.input.kind === "tapped") {
            s.input = { kind: "released" };
            closeCapture(s, effects);
            break;
        }
        recover(s, effects, e.at);
        interrupt(s, effects, e.at);
        start(s, effects, "held", e.at);
        break;
    case "talk-up":
        if (s.settings.mode === "toggle" && s.approval.kind !== "held") break;
        if (s.input.kind !== "held") break;
        // A tap keeps the microphone open for the request, or has it open
        // once the start sound and the bubble allow (canCapture), as a tap
        // usually ends before them; a held answer to a request on screen
        // ends with its hold, and a capture that failed leaves nothing to
        // keep open.
        if (s.approval.kind !== "held" && (s.capture.kind === "opening" || s.capture.kind === "open" || (s.capture.kind === "closed" && s.fault.kind === "none"))
                && e.at - s.input.since < TAP_MS) {
            s.input = { kind: "tapped", deadline: s.capture.kind === "open" ? e.at + TAP_SILENCE_MS : null };
            break;
        }
        s.input = { kind: "released" };
        closeCapture(s, effects);
        break;
    case "toggle":
        toggle(s, effects, e.at);
        break;
    case "mute-toggle":
        if (s.mute.kind === "on") {
            s.mute = { kind: "off" };
            effect(s, effects, "mute-store", { muted: false });
        } else if (s.mute.kind === "off") {
            end(s, effects, e.at, "mute", false);
            s.mute = { kind: "muting" };
            effect(s, effects, "mute-store", { muted: true });
        }
        break;
    case "mute":
        end(s, effects, e.at, "mute", false);
        if (s.mute.kind === "off") s.mute = { kind: "muting" };
        break;
    case "unmute":
        // An in-flight close must finish before a new capture can open.
        if (s.mute.kind === "on") s.mute = { kind: "off" };
        break;
    case "stop":
        var faulted = s.fault.kind !== "none" || s.input.kind === "stopped";
        end(s, effects, e.at, "stop", true);
        s.fault = { kind: "none" };
        // A fault's Stop dismisses its retry as well as the conversation.
        // Always mode waits for Talk instead of reopening the lost device.
        if (faulted) s.input = { kind: "stopped" };
        break;
    case "lease-ended":
        end(s, effects, e.at, "lease", true);
        // EOF is teardown, not an interactive cancellation. No adapter may
        // retain the daemon while waiting for an acknowledgment.
        closeBrain(s, effects);
        if (s.turn.kind === "cancelling") s.turn = { kind: "none" };
        break;
    case "cancel":
        if (["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1) end(s, effects, e.at, "cancel", false);
        if (s.input.kind !== "stopped") s.input = { kind: "released" };
        closeCapture(s, effects);
        cancelTurn(s, effects, e.at);
        dropApproval(s, effects, "cancel", e.at);
        break;
    case "interrupt":
        if (["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1) end(s, effects, e.at, "interrupt", false);
        interrupt(s, effects, e.at);
        break;
    case "capture-opened":
        if (!live(s, e, "capture", ["opening"])) { stale(s); break; }
        s.capture.kind = "open";
        if (s.capture.mode === "check") s.check = { kind: "recording", gen: e.gen, op: e.op, deadline: e.at + VOICE_CHECK_MS };
        if (s.turn.kind === "collecting") s.turn.deadline = s.input.kind === "woken" || s.input.kind === "follow-up" ? e.at + WAKE_SILENCE_MS : null;
        if (s.input.kind === "tapped") s.input.deadline = e.at + TAP_SILENCE_MS;
        if (s.fault.kind === "retrying") s.fault = { kind: "none" };
        break;
    case "capture-failed": {
        if (!live(s, e, "capture", ["opening", "open"])) { stale(s); break; }
        var retry = s.fault.kind === "retrying" ? s.fault.retry : 0;
        s.fault = e.reason === "device-lost" && retry < 3
            ? { kind: "retrying", reason: e.reason, retry: retry + 1 }
            : { kind: "error", reason: e.reason, retry: retry };
        closeCapture(s, effects);
        if (s.input.kind === "check") end(s, effects, e.at, "capture-failed", false);
        // A failed capture ends a tap: the next press recovers and listens.
        if (s.input.kind === "tapped") s.input = { kind: "released" };
        if (s.turn.kind === "collecting") s.turn = { kind: "none" };
        break;
    }
    // The wake word opens a conversation as a Talk press does, with its
    // start sound, through a fresh capture that collects the utterance.
    case "wake":
        if (!live(s, e, "capture", ["open"]) || s.capture.mode !== "armed") { stale(s); break; }
        start(s, effects, "woken", e.at);
        break;
    case "capture-closed":
        if (!live(s, e, "capture", ["closing"])) { stale(s); break; }
        s.capture = { kind: "closed" };
        if (s.turn.kind === "collecting") s.turn.deadline = e.at + COLLECTION_TIMEOUT_MS;
        break;
    case "partial":
        if (!live(s, e, "turn", ["collecting"])) { stale(s); break; }
        s.turn.partial = e.text;
        // A tapped request ends once its words stop: each partial moves the
        // silence bound.
        if (s.input.kind === "tapped" && s.capture.kind === "open") s.input.deadline = e.at + TAP_SILENCE_MS;
        // Words were heard: the request is collected as a Talk-started one.
        if (s.input.kind === "woken" || s.input.kind === "follow-up") {
            s.input = { kind: "conversation" };
            if (s.capture.kind === "open") s.turn.deadline = null;
        }
        break;
    case "delegation":
    case "final":
        if (e.type === "delegation") {
            if (s.engine.kind !== "duplex" || !live(s, e, "speech", ["open"]) || !canEngage(s)) { stale(s); break; }
            cancelTurn(s, effects, e.at);
            dropApproval(s, effects, "replaced", e.at);
            // A new request drops the words the voice held for the old one.
            if (s.speech.reply.kind === "due") s.speech.reply = { kind: "none" };
            if (s.conversation.kind === "interrupted") s.conversation = { kind: "active" };
            // A tap is one request: the voice's end of speech hands it to
            // the brain, and the microphone stays closed after the reply.
            if (s.input.kind === "tapped") {
                s.input = { kind: "released" };
                closeCapture(s, effects);
            }
            think(s, effects, { text: e.text, delegation: e.id }, e.at);
        } else {
            if (!live(s, e, "turn", ["collecting"])) { stale(s); break; }
            commitUserText(s, effects, e.text, e.at, e.op, true);
        }
        break;
    case "say":
        if (sayRefusal(s) !== null) break;
        if (["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1) end(s, effects, e.at, "say", false);
        recover(s, effects, e.at);
        commitUserText(s, effects, e.text, e.at, 1, false);
        break;
    // A preview speaks the engine's fixed sentence as a turn of its own; a
    // duplex voice opens its session for it with no capture.
    case "preview":
        if (previewRefusal(s) !== null) break;
        recover(s, effects, e.at);
        // A new conversation takes a new gen; one between turns keeps its own.
        if (s.conversation.kind === "ended") s.gen += 1;
        if (s.conversation.kind !== "active") s.conversation = { kind: "active" };
        // A preview names one offer of the Voice list; the engine plays the
        // chosen voice for a voice its provider does not offer.
        var preview = { preview: true, voice: e.voice };
        if (s.engine.kind === "duplex") {
            var opened = effect(s, effects, "speech-open", preview);
            s.speech = { kind: "open", gen: opened.gen, op: opened.op, reply: { kind: "none" } };
        } else think(s, effects, preview, e.at);
        break;
    // A task line the daemon wrote speaks as a turn of its own: no user
    // words, and the engine never hands it to the brain.
    case "relay":
        if (typeof e.text !== "string" || e.text.trim() === "" || !relayAsk(e.ask))
            throw new Error("jarvis: session=relay");
        if (relayRefusal(s) !== null) { stale(s); break; }
        s.conversation = { kind: "active" };
        think(s, effects, { relay: { text: e.text, ask: e.ask } }, e.at);
        break;
    // A transcription that fails after its capture closed still owns the turn.
    case "collect-failed":
        if (!live(s, e, "turn", ["collecting"])) { stale(s); break; }
        s.turn = { kind: "none" };
        s.fault = { kind: "error", reason: e.reason, retry: 0 };
        end(s, effects, e.at, "collect-failed", false);
        break;
    // The brain ends the conversation without a fault: the next one may start.
    case "brain-ended":
        if (!live(s, e, "turn", ["thinking"])) { stale(s); break; }
        s.turn = { kind: "none" };
        end(s, effects, e.at, e.reason, false);
        break;
    case "brain-done":
    case "brain-failed":
        if (!live(s, e, "turn", ["thinking"])) { stale(s); break; }
        s.turn = { kind: "none" };
        if (e.type === "brain-done" && ["playing", "feedback"].indexOf(s.playback.kind) !== -1)
            s.playback.deadline = e.at + PLAYBACK_TIMEOUT_MS;
        if (e.type === "brain-done" && (s.playback.kind === "flushing" || s.playback.kind === "feedback")
                && s.playback.reply.kind === "waiting")
            s.playback.reply.deadline = e.at + PLAYBACK_TIMEOUT_MS;
        if (e.type === "brain-failed") {
            s.fault = { kind: "error", reason: e.reason, retry: 0 };
            end(s, effects, e.at, "brain-failed", false);
        }
        break;
    case "cancelled":
        if (!live(s, e, "turn", ["cancelling"])) { stale(s); break; }
        // An acknowledged cancel leaves the adapter idle. A live conversation
        // keeps it, so the next turn keeps the brain's history.
        if (s.conversation.kind === "ended") closeBrain(s, effects);
        s.turn = { kind: "none" };
        break;
    case "play":
        if (!live(s, e, "turn", ["thinking"])) { stale(s); break; }
        if (s.playback.kind === "feedback" && s.playback.cue === "line" && s.playback.source === e.op) {
            s.playback.reply = { kind: "waiting", gen: e.gen, source: e.op, interruptible: e.interruptible, deadline: null };
            break;
        }
        if (s.playback.kind === "feedback" && s.playback.cue === "working" && s.playback.source === e.op) {
            s.playback = { kind: "playing", gen: s.playback.gen, op: s.playback.op, source: e.op,
                interruptible: e.interruptible, admission: s.playback.admission, deadline: s.playback.deadline };
            break;
        }
        // Audio closes asynchronously. The reply keeps its one admission
        // request until the old player's matching flush acknowledgment.
        if (s.playback.kind === "flushing" && s.conversation.kind === "active") {
            s.playback.reply = { kind: "waiting", gen: e.gen, source: e.op,
                interruptible: e.interruptible, deadline: null };
            break;
        }
        if (s.playback.kind !== "idle" || s.conversation.kind === "interrupted") break;
        s.playback = { kind: "playing", gen: s.gen, op: operation(s), source: e.op,
            interruptible: e.interruptible, admission: { kind: "waiting" }, deadline: null };
        break;
    case "played":
        if (!live(s, e, "playback", ["playing", "feedback"])) { stale(s); break; }
        if (s.playback.kind === "playing" && s.followUp.kind === "asked" && s.followUp.gen === s.gen)
            s.followUp = { kind: "spoken", gen: s.gen };
        var lineReply = s.playback.kind === "feedback" ? s.playback.reply : { kind: "none" };
        s.playback = lineReply.kind === "waiting" && lineReply.gen === s.gen && s.conversation.kind === "active" && canEngage(s)
            ? { kind: "playing", gen: lineReply.gen, op: operation(s), source: lineReply.source,
                interruptible: lineReply.interruptible, admission: { kind: "waiting" }, deadline: lineReply.deadline }
            : { kind: "idle" };
        break;
    case "flushed":
        if (!live(s, e, "playback", ["flushing"])) { stale(s); break; }
        var reply = s.playback.reply;
        s.playback = reply.kind === "waiting" && reply.gen === s.gen && s.conversation.kind === "active" && canEngage(s)
            ? { kind: "playing", gen: reply.gen, op: operation(s), source: reply.source,
                interruptible: reply.interruptible, admission: { kind: "waiting" }, deadline: reply.deadline }
            : { kind: "idle" };
        break;
    case "playback-failed":
        if (!live(s, e, "playback", ["playing", "feedback"])) { stale(s); break; }
        s.fault = { kind: "error", reason: e.reason, retry: 0 };
        end(s, effects, e.at, "playback-failed", false);
        break;
    case "feedback":
        if (!live(s, e, "turn", ["thinking"])) { stale(s); break; }
        var cue = e.cue === "line" ? "line" : "working";
        if ((cue !== "line" && s.settings.sounds !== true) || !canEngage(s)
                || s.conversation.kind !== "active" || s.approval.kind !== "none") break;
        if (s.playback.kind === "feedback" && s.playback.source === e.op
                && ["working", "line"].indexOf(s.playback.cue) !== -1) break;
        if (s.playback.kind !== "idle") break;
        s.playback = { kind: "feedback", gen: s.gen, op: operation(s), source: e.op, cue: cue,
            admission: { kind: "waiting" }, deadline: null, reply: { kind: "none" } };
        break;
    case "tool":
        if (!live(s, e, "turn", ["thinking"])) { stale(s); break; }
        if (!canPropose(s)) break;
        toolDuration(e);
        var tool = effect(s, effects, "tool-start", { tool: e.tool, id: e.id });
        s.action = { kind: "running", gen: tool.gen, op: tool.op, tool: e.tool,
            brain: e.op, limit: { kind: "pending", deadline: e.at + e.timeoutMs },
            cancellation: { kind: e.cancellable ? "available" : "unavailable" } };
        holdThinking(s);
        break;
    case "tool-done":
        if (!live(s, e, "action", ["running"])) { stale(s); break; }
        if (["completed", "failed", "unknown"].indexOf(e.outcome) === -1)
            throw new Error("jarvis: session=tool-outcome");
        effect(s, effects, "tool-outcome", { gen: s.action.gen, target: s.action.brain,
            source: s.action.op, tool: s.action.tool, outcome: e.outcome });
        if (s.turn.kind === "thinking" && s.turn.op === s.action.brain) s.turn.deadline = e.at + RESPONSE_TIMEOUT_MS;
        s.action = { kind: "none" };
        break;
    case "approval":
        if (!live(s, e, "turn", ["thinking"])) { stale(s); break; }
        if (!canPropose(s)) break;
        toolDuration(e);
        var purpose = e.purpose === "release" ? "release" : "action";
        if (s.playback.kind === "feedback" && (s.playback.cue === "working"
                || s.playback.cue === "line" && s.playback.reply.kind === "none")) flushPlayback(s, effects);
        var hold = effect(s, effects, "approval-show", { id: e.id, digest: e.digest, purpose: purpose });
        s.approval = { kind: "held", purpose: purpose, gen: hold.gen, op: hold.op, id: e.id, digest: e.digest,
            deadline: e.at + APPROVAL_TIMEOUT_MS, shownAt: null, physical: e.physical,
            text: e.text, tool: e.tool, timeoutMs: e.timeoutMs, cancellable: e.cancellable,
            brain: e.op };
        // The held request has its own full interval. The scheduler selects
        // that interval, then thinking gets a fresh interval after a decision.
        s.turn.deadline = s.approval.deadline + RESPONSE_TIMEOUT_MS;
        break;
    case "shown":
        if (!live(s, e, "approval", ["held"])) { stale(s); break; }
        if (e.id !== s.approval.id) { stale(s); break; }
        if (s.approval.shownAt === null) s.approval.shownAt = e.at;
        break;
    case "confirm": {
        var approval = s.approval;
        var reason = approval.kind !== "held" ? (expiredApproval !== null ? "expired" : "no-hold")
            : e.gen !== approval.gen || e.id !== approval.id || e.digest !== approval.digest ? "identity"
            : ["key", "button", "voice"].indexOf(e.source) === -1 ? "source"
            : approval.shownAt === null || e.at - approval.shownAt < APPROVAL_DRAW_MS ? "early"
            : e.source === "voice" && approval.physical ? "voice-physical"
            : e.source === "voice" && (!Number.isFinite(e.beganAt) || !Number.isFinite(e.idleAt)
                || e.beganAt < approval.shownAt || e.beganAt > e.at
                || e.idleAt < 0 || e.beganAt - e.idleAt < VOICE_QUIET_MS
                || s.playback.kind !== "idle") ? "voice-timing" : null;
        if (reason !== null) {
            effect(s, effects, "confirm-refused", { reason: reason, id: e.id,
                gen: approval.kind === "held" ? approval.gen : s.gen,
                target: approval.kind === "held" ? approval.brain : null,
                purpose: approval.kind === "held" ? approval.purpose : "action" });
            break;
        }
        s.approval = { kind: "none" };
        if (s.turn.kind === "thinking") s.turn.deadline = e.at + RESPONSE_TIMEOUT_MS;
        s.input = { kind: "released" };
        closeCapture(s, effects);
        if (approval.purpose === "release") {
            effect(s, effects, "release-confirmed", { id: approval.id, target: approval.brain, confirmed: e.source });
            break;
        }
        var accepted = effect(s, effects, "tool-start", { tool: approval.tool,
            id: approval.id, confirmed: e.source });
        s.action = { kind: "running", gen: accepted.gen, op: accepted.op, tool: approval.tool,
            brain: approval.brain, limit: { kind: "pending", deadline: e.at + approval.timeoutMs },
            cancellation: { kind: approval.cancellable ? "available" : "unavailable" } };
        holdThinking(s);
        break;
    }
    case "approval-cancel":
        if (e.id !== s.approval.id || e.gen !== s.approval.gen) { stale(s); break; }
        dropApproval(s, effects, "cancel", e.at);
        s.input = { kind: "released" };
        closeCapture(s, effects);
        break;
    case "speak":
        if (!live(s, e, "speech", ["open"])) { stale(s); break; }
        // New output after an interruption answers new input.
        if (s.conversation.kind === "interrupted") s.conversation = { kind: "active" };
        s.speech.reply = { kind: "waiting" };
        break;
    // The voice holds words no reply carries yet, or has dropped them. A
    // waiting reply's own audio already holds the speaker.
    case "speech-due":
        if (typeof e.due !== "boolean") throw new Error("jarvis: session=speech-due");
        if (!live(s, e, "speech", ["open"])) { stale(s); break; }
        if (e.due && s.speech.reply.kind === "none") s.speech.reply = { kind: "due" };
        else if (!e.due && s.speech.reply.kind === "due") s.speech.reply = { kind: "none" };
        break;
    case "transcript":
        // The duplex session captions both speakers; a chained thinking turn
        // captions only the words it released for speech.
        if (!live(s, e, "speech", ["open"]) && !(e.role === "assistant" && live(s, e, "turn", ["thinking"]))) {
            stale(s);
            break;
        }
        effect(s, effects, "transcript", { role: e.role, text: e.text, stage: e.stage, rev: e.rev });
        // The voice's captions of the user's words move a tap's end of
        // speech, as a chained engine's partials do.
        if (e.role === "user" && s.input.kind === "tapped" && s.capture.kind === "open") s.input.deadline = e.at + TAP_SILENCE_MS;
        break;
    case "speech-idle":
        if (!live(s, e, "speech", ["open"])) { stale(s); break; }
        // A turn in flight ends by its own deadline, with its own fault or
        // reason: thinking, a held approval, or an action inside its limit.
        // The engine's idle wait runs again.
        if (s.turn.kind === "thinking" || s.approval.kind === "held"
                || s.action.kind === "running" && s.action.limit.kind === "pending") break;
        end(s, effects, e.at, "idle", false);
        break;
    case "speech-failed":
        if (!live(s, e, "speech", ["open"])) { stale(s); break; }
        // A failed engine has already released its session.
        s.speech = { kind: "closed" };
        s.fault = { kind: "error", reason: e.reason, retry: 0 };
        end(s, effects, e.at, "speech-failed", false);
        break;
    case "deadline":
        if (live(s, e, "turn", ["collecting", "thinking", "cancelling"])
                || live(s, e, "check", ["waiting", "recording", "finishing"])
                || live(s, e, "playback", ["playing", "feedback"])
                || live(s, e, "approval", ["held"]) || live(s, e, "action", ["running"])
                || s.input.kind === "tapped" && live(s, e, "capture", ["open"]))
            expire(s, effects, e.at);
        else stale(s);
        break;
    }
    reconcile(s, effects, e.at);
    return { state: s, effects: effects };
}

// The state wire contains this exact record. This table is its sole region
// shape definition; both endpoints use it through JarvisProtocol.
var REGIONS = {
    gate: { down: "reason", up: "" }, mute: { off: "", muting: "", on: "" },
    capture: { closed: "", opening: "gen op mode", open: "gen op mode", closing: "gen op" },
    turn: { none: "", collecting: "gen op partial deadline", thinking: "gen op deadline", cancelling: "gen op deadline" },
    brain: { closed: "", acquired: "gen op" },
    playback: { idle: "", playing: "gen op source interruptible admission deadline",
        feedback: "gen op source cue admission deadline reply", flushing: "gen op reply" },
    action: { none: "", running: "gen op tool brain limit cancellation" },
    approval: { none: "", held: "purpose gen op id digest deadline shownAt physical text tool timeoutMs cancellable brain" },
    fault: { none: "", error: "reason retry", retrying: "reason retry" }, conversation: { ended: "", active: "", interrupted: "" },
    input: { released: "", stopped: "", held: "since", tapped: "deadline", conversation: "", "follow-up": "", armed: "", woken: "", check: "" },
    followUp: { none: "", asked: "gen", spoken: "gen" },
    indicator: { gone: "", shown: "" }, duplex: { half: "" },
    engine: { chained: "", dictation: "", duplex: "" }, speech: { closed: "", open: "gen op reply" },
    check: { unavailable: "", kept: "result device", ready: "", again: "", waiting: "gen op deadline", recording: "gen op deadline", finishing: "gen op deadline", done: "result device", failed: "reason device" }
};

function exact(value, names) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
        && Object.keys(value).sort().join(",") === names.slice().sort().join(",");
}

function validate(s) {
    if (!exact(s, Object.keys(REGIONS).concat(["gen", "nextOp", "stale", "settings", "toggleAt", "checkSource"]))) return false;
    if (s.checkSource !== null && typeof s.checkSource !== "string") return false;
    for (var name of ["gen", "nextOp", "stale"])
        if (!Number.isSafeInteger(s[name]) || s[name] < (name === "nextOp" ? 1 : 0)) return false;
    if (s.settings === null || typeof s.settings !== "object" || Array.isArray(s.settings)) return false;
    if (s.toggleAt !== null && (!Number.isFinite(s.toggleAt) || s.toggleAt < 0)) return false;
    for (var region of Object.keys(REGIONS)) {
        var r = s[region];
        if (r === null || !Object.prototype.hasOwnProperty.call(REGIONS[region], r.kind)) return false;
        var fields = REGIONS[region][r.kind] === "" ? [] : REGIONS[region][r.kind].split(" ");
        if (!exact(r, ["kind"].concat(fields))) return false;
        for (var f of fields) {
            if (["gen", "op", "brain", "source", "retry"].indexOf(f) !== -1) {
                if (!Number.isSafeInteger(r[f]) || r[f] < (["op", "brain", "source"].indexOf(f) !== -1 ? 1 : 0)) return false;
            } else if (f === "device") {
                if (r[f] !== null && typeof r[f] !== "string") return false;
            } else if (f === "since") {
                if (!Number.isFinite(r[f]) || r[f] < 0) return false;
            } else if (f === "deadline" || f === "shownAt") {
                if (f === "deadline" && r[f] === null && (region === "playback" || r.kind === "collecting" || r.kind === "tapped")) continue;
                if (!(f === "shownAt" && r[f] === null) && (!Number.isFinite(r[f]) || r[f] < 0)) return false;
            } else if (f === "timeoutMs") {
                if (!Number.isFinite(r[f]) || r[f] <= 0) return false;
            } else if (["interruptible", "physical", "cancellable"].indexOf(f) !== -1) {
                if (typeof r[f] !== "boolean") return false;
            } else if (f === "cancellation") {
                if (!exact(r[f], ["kind"]) || ["available", "unavailable", "requested"].indexOf(r[f].kind) === -1) return false;
            } else if (f === "admission") {
                if (!exact(r[f], ["kind"]) || ["waiting", "started"].indexOf(r[f].kind) === -1) return false;
            } else if (f === "reply") {
                if (region === "playback" && r[f] && r[f].kind === "waiting") {
                    if (!exact(r[f], ["kind", "gen", "source", "interruptible", "deadline"])
                            || !Number.isSafeInteger(r[f].gen) || r[f].gen < 0
                            || !Number.isSafeInteger(r[f].source) || r[f].source < 1
                            || typeof r[f].interruptible !== "boolean"
                            || (r[f].deadline !== null && (!Number.isFinite(r[f].deadline) || r[f].deadline < 0))) return false;
                    continue;
                }
                if (!exact(r[f], ["kind"]) || ["none", "waiting", "due"].indexOf(r[f].kind) === -1) return false;
                if (region === "playback" && r[f].kind !== "none") return false;
            } else if (f === "limit") {
                if (r[f] === null || typeof r[f] !== "object") return false;
                if (!exact(r[f], r[f].kind === "pending" ? ["kind", "deadline"] : ["kind"])) return false;
                if (["pending", "expired"].indexOf(r[f].kind) === -1) return false;
                if (r[f].kind === "pending" && (!Number.isFinite(r[f].deadline) || r[f].deadline < 0)) return false;
            } else if (typeof r[f] !== "string") return false;
        }
        if (region === "approval" && r.kind === "held" && ["action", "release"].indexOf(r.purpose) === -1) return false;
        if (region === "capture" && fields.indexOf("mode") !== -1
                && ["hold", "conversation", "follow-up", "armed", "check"].indexOf(r.mode) === -1) return false;
        if (region === "check" && (r.kind === "done" || r.kind === "kept") && ["ready", "silent", "not-heard"].indexOf(r.result) === -1) return false;
        if (region === "playback" && r.kind === "feedback" && ["start", "working", "line"].indexOf(r.cue) === -1) return false;
        if (region === "gate" && r.kind === "down"
                && ["starting", "unconfigured", "node", "lock-unknown", "locked"].indexOf(r.reason) === -1) return false;
    }
    return true;
}
