.pragma library

// The daemon owns this value. Time enters only through event.at (monotonic
// milliseconds). Adapter callbacks carry the gen/op returned in their effect.
// Cleanup acknowledgments and a running tool's outcome retain their original
// identity across stop; content callbacks do not. A duplex engine owns one
// speech session per conversation; its callbacks carry the session's gen/op.
// A dictation engine is the chained engine whose final words come from the
// core's dictation recording (D064).
var SESSION_SETTINGS = ["holdToTalk", "voiceProvider", "voice", "clonedVoice", "language", "brain", "model", "effort", "fallbacks", "customBaseUrl", "home", "policy", "cloudVision", "account", "voiceAccount"];
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
var CONVERSATION_QUIET_MS = 30 * 60 * 1000;
var TOGGLE_DEBOUNCE_MS = 250;
// A shorter press is a close request only if its capture heard no speech.
// The boundary follows HyprlandLayer's hold/tap repeat-delay convention.
var TAP_MS = 600;
var TRANSCRIPT_CHARS = 4096;
// The engine's cause categories (ChainedEngine's cause table), which a
// brain-failed event names and the restart region keeps for the shell's
// plain words (WidgetView.FAULT_WORDS).
var FAULT_CATEGORIES = ["connection", "reply-cut", "service", "app-stopped", "account", "model", "setup", "other"];
var EVENTS = [
    "snapshot", "indicator", "hide", "show", "hidden", "talk-down", "talk-up", "toggle", "voice-mute", "voice-mute-toggle",
    "stop", "cancel", "interrupt", "capture-opened", "capture-closed", "capture-failed", "playback-failed", "partial",
    "final", "say", "collect-failed", "brain-done", "brain-failed", "cancelled", "play", "played",
    "flushed", "tool", "tool-done", "approval", "shown", "confirm", "approval-cancel", "deadline", "lease-ended",
    "speak", "speech-due", "transcript", "speech-idle", "speech-failed", "feedback", "delegation", "relay", "voice-check", "voice-checked", "voice-check-failed", "input-silent", "input-sound",
    "preview", "speech-input-ended", "new-conversation", "conversation-reset"
];

function initial() {
    return {
        gen: 0, nextOp: 1, stale: 0, settings: {},
        gate: { kind: "down", reason: "starting" },
        voiceMute: { kind: "off" }, capture: { kind: "closed" },
        turn: { kind: "none" }, brain: { kind: "closed" }, playback: { kind: "idle" },
        action: { kind: "none" }, approval: { kind: "none" }, fault: { kind: "none" }, cue: { kind: "none" },
        conversation: { kind: "ended" }, history: { kind: "current", epoch: 0 },
        input: { kind: "released" }, quiet: { kind: "none" }, sound: { kind: "none" },
        indicator: { kind: "gone" }, barIndicator: { kind: "gone" }, visibility: { kind: "shown" },
        duplex: { kind: "half" }, toggleAt: null,
        engine: { kind: "chained" }, speech: { kind: "closed" }, check: { kind: "unavailable" }, checkSource: null,
        restart: { kind: "none" }
    };
}

// One phase judge for the wire and the shell. Closing/flushing do not claim
// listening/speaking.
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
    if (s.capture.kind === "open") return "listening";
    return "idle";
}

// Demand precedes capture admission. Waiting for capture here would wait
// forever for the indicator that must be presented before capture opens.
function indicatorWanted(s) {
    if (["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1) return true;
    if (s.capture.kind !== "closed") return true;
    var phase = phaseOf(s);
    if (phase !== "idle" && phase !== "down") return true;
    return canEngage(s) && s.conversation.kind !== "ended";
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
    // Conversation retirement may already have advanced s.gen; cleanup
    // still belongs to the recorder's acquired generation.
    var e = effect(s, effects, "capture-close", { gen: s.capture.gen, target: s.capture.op });
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

// Live generations expire on close. The history identity survives an ordinary
// close so the engine can retain context after voice and grants end.
function resetHistory(s, reason) {
    s.history = reason === null ? { kind: "current", epoch: s.history.epoch + 1 }
        : { kind: "reset", epoch: s.history.epoch + 1, reason: reason };
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

function previewConversation(s) {
    return s.conversation.kind !== "ended" && s.conversation.purpose === "preview";
}

function end(s, effects, at, reason, stopTool) {
    var soundedClose = s.conversation.kind !== "ended" && !previewConversation(s) && s.settings.sounds === true && s.fault.kind === "none"
        && ["lease", "gate", "settings", "voice-unavailable", "brain-failed"].indexOf(reason) === -1;
    s.cue = soundedClose ? { kind: "pending", cue: "stop" } : { kind: "none" };
    s.quiet = { kind: "none" };
    s.sound = { kind: "none" };
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

// The engine's answer whether a failed turn's cause may restart: { kind:
// "restart" | "none", category }.
function restartAnswer(restart) {
    return exact(restart, ["kind", "category"]) && ["restart", "none"].indexOf(restart.kind) !== -1
        && FAULT_CATEGORIES.indexOf(restart.category) !== -1;
}

// A failed turn ends its conversation. A cause the engine may restart, in a
// user conversation that has not used its restart and that Talk could start
// again (canEngage), ends it with no fault instead; an open conversation, one
// that listens between turns, opens again through start(). Every failure
// leaves one record of its cause and what Session did.
function failBrain(s, effects, e) {
    var restarting = e.restart.kind === "restart" && s.restart.kind === "none" && !previewConversation(s) && canEngage(s);
    var open = s.input.kind === "conversation";
    effect(s, effects, "fault-record", { reason: e.reason, category: e.restart.category,
        action: restarting ? "restarted" : "stopped" });
    if (!restarting) {
        s.fault = { kind: "error", reason: e.reason, retry: 0 };
        end(s, effects, e.at, "brain-failed", false);
        return;
    }
    end(s, effects, e.at, "brain-failed", false);
    if (open) start(s, effects, "conversation", e.at);
    s.restart = { kind: "restarted", category: e.restart.category };
}

function canEngage(s) {
    return s.gate.kind === "up" && (s.fault.kind === "none" || s.fault.kind === "retrying");
}

function canCheck(s) {
    return s !== null && ["ready", "again", "done", "failed"].indexOf(s.check.kind) !== -1 && s.fault.kind === "none"
        && (s.gate.kind === "up" || s.gate.reason === "unconfigured")
        && s.turn.kind === "none" && s.playback.kind === "idle" && s.action.kind !== "running" && s.approval.kind !== "held";
}

function captureWanted(s) {
    var checking = s.input.kind === "check" && (s.gate.kind === "up" || s.gate.reason === "unconfigured")
        && s.fault.kind === "none" && ["waiting", "recording"].indexOf(s.check.kind) !== -1;
    return (canEngage(s) || checking)
        && (s.playback.kind === "idle" || overlapping(s) && s.playback.kind === "playing")
        && s.cue.kind === "none" && s.turn.kind !== "cancelling"
        && ["held", "conversation", "check"].indexOf(s.input.kind) !== -1
        && (s.conversation.kind !== "ended" && !previewConversation(s) || checking);
}

function canCapture(s) {
    // Show requests the orb before transferring admission. During that
    // handoff the current generation's presented listening bar still owns it.
    return captureWanted(s) && (s.visibility.kind !== "shown"
        ? barPresented(s) && s.barIndicator.kind === "listening" : s.indicator.kind === "shown");
}

function barPresented(s) {
    return s.barIndicator.kind !== "gone" && s.barIndicator.gen === s.gen;
}

function hideRefusal(s) {
    return s === null ? "not-ready" : !barPresented(s) ? "indicator" : null;
}

// Audio alone judges the connected native EC route. The engine name alone
// cannot admit overlap, and checks and conversation tones stay exclusive.
function overlapping(s) {
    return s.duplex.kind === "full" && s.engine.kind === "duplex" && s.input.kind !== "check";
}

function sayRefusal(s) {
    if (s === null || s.gate.kind !== "up") return "down";
    if (s.engine.kind === "duplex") return "duplex";
    if (previewConversation(s)) return null;
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

// The one automatic restart a user conversation allows. The restarted
// conversation's first user turn spends what is left of it.
function spendRestart(s) {
    if (s.restart.kind === "restarted") s.restart = { kind: "spent" };
}

// A conversation the user starts allows the restart again, unless the
// restart region still holds a restart no user turn has met: then the new
// conversation continues the restarted one and starts spent. That covers the
// conversation after a restart that left no input open, and the one after a
// reopened conversation that ended before a user turn.
function userConversation(s) {
    s.restart = s.restart.kind === "restarted" ? { kind: "spent" } : { kind: "none" };
}

function commitUserText(s, effects, text, at, rev) {
    promotePreview(s, effects, at);
    if (s.conversation.kind === "interrupted") s.conversation = { kind: "active", purpose: s.conversation.purpose };
    if (s.conversation.kind === "ended") {
        s.gen += 1;
        s.conversation = { kind: "active", purpose: "conversation" };
        userConversation(s);
    }
    spendRestart(s);
    if (s.input.kind === "held" || s.input.kind === "closing-tap") s.input = { kind: "released" };
    closeCapture(s, effects);
    userTranscript(s, effects, text, rev);
    think(s, effects, { text: text }, at);
}

function activity(s, at) {
    if (s.conversation.kind === "ended") return;
    s.quiet = { kind: "waiting", gen: s.gen,
        op: s.quiet.kind === "waiting" ? s.quiet.op : operation(s), deadline: at + CONVERSATION_QUIET_MS };
}

function releasedInput(s) {
    return s.conversation.kind !== "ended" && !previewConversation(s) && s.settings.holdToTalk !== true
        ? { kind: "conversation" } : { kind: "released" };
}

function promotePreview(s, effects, at) {
    if (!previewConversation(s)) return;
    if (s.conversation.kind !== "interrupted") interrupt(s, effects, at);
    // The preview's provider session has its own voice/idle behavior. A user
    // conversation takes a fresh speech owner, within this generation.
    closeSpeech(s, effects, "abort");
    s.conversation = { kind: "active", purpose: "conversation" };
    userConversation(s);
    if (s.settings.sounds === true) s.cue = { kind: "pending", cue: "start" };
}

// One thinking turn of the conversation's brain owner. A relay turn holds the
// owner too, so a later user turn keeps the conversation's history.
function think(s, effects, values, at) {
    activity(s, at);
    var brain = effect(s, effects, "brain-send", values);
    if (s.brain.kind === "closed") s.brain = { kind: "acquired", gen: brain.gen, op: brain.op };
    brain.owner = s.brain.op;
    s.turn = { kind: "thinking", gen: brain.gen, op: brain.op, deadline: at + RESPONSE_TIMEOUT_MS };
}

function canPlayback(s) {
    return canEngage(s) && ["playing", "feedback"].indexOf(s.playback.kind) !== -1
        && (s.capture.kind === "closed" || overlapping(s) && s.playback.kind === "playing"
            && ["opening", "open"].indexOf(s.capture.kind) !== -1);
}

// A duplex reply plays when the conversation is live. Half duplex never runs
// capture and playback together, so a held talk key keeps the microphone.
function canSpeak(s) {
    return canEngage(s) && s.conversation.kind === "active" && s.playback.kind === "idle"
        && s.input.kind !== "held";
}

function reconcile(s, effects, at) {
    // Without capture demand there is no indicator ownership to transfer.
    if (s.visibility.kind === "showing" && !captureWanted(s)) s.visibility = { kind: "shown" };
    if (previewConversation(s) && s.engine.kind !== "duplex" && s.turn.kind === "none" && s.playback.kind === "idle")
        end(s, effects, at, "preview", false);
    // Conversation cues wait for capture cleanup and the old player.
    // The stop cue owns only playback; the conversation is already ended.
    if (s.cue.kind === "pending" && s.playback.kind === "idle") {
        var cue = operation(s);
        s.playback = { kind: "feedback", gen: s.gen, op: cue, source: cue, cue: s.cue.cue,
            admission: { kind: "waiting" }, deadline: at + PLAYBACK_TIMEOUT_MS, reply: { kind: "none" } };
        s.cue = { kind: "none" };
    }
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
        var mode = s.input.kind === "held" ? "hold" : s.input.kind;
        var e = effect(s, effects, "capture-open", { mode: mode });
        s.capture = { kind: "opening", gen: e.gen, op: e.op, mode: mode };
        s.sound = { kind: "none" };
        if (mode === "check") s.check = { kind: "waiting", gen: e.gen, op: e.op, deadline: at + COLLECTION_TIMEOUT_MS };
    }
    // The duplex voice model owns turn-taking; no utterance is collected.
    if (s.engine.kind !== "duplex" && canCapture(s) && s.input.kind !== "check"
            && (s.capture.kind === "opening" || s.capture.kind === "open") && s.turn.kind === "none") {
        var collect = effect(s, effects, "collect", {});
        s.turn = { kind: "collecting", gen: collect.gen, op: collect.op, partial: "", deadline: null };
    }
    if (["playing", "feedback"].indexOf(s.playback.kind) !== -1 && s.playback.admission.kind === "waiting" && canPlayback(s)) {
        effect(s, effects, "playback-start", { gen: s.playback.gen, op: s.playback.op, source: s.playback.source });
        s.playback.admission = { kind: "started" };
    }
}

function start(s, effects, mode, at) {
    if (!canEngage(s)) return;
    promotePreview(s, effects, at);
    if (["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1) end(s, effects, at, "talk", false);
    if (s.conversation.kind === "ended") {
        s.gen++;
        s.conversation = { kind: "active", purpose: "conversation" };
        userConversation(s);
        if (s.settings.sounds === true) s.cue = { kind: "pending", cue: "start" };
    } else if (s.conversation.kind === "interrupted") s.conversation = { kind: "active", purpose: s.conversation.purpose };
    s.input = mode === "held" ? { kind: "held", since: at, heard: false } : { kind: mode };
    activity(s, at);
    reconcile(s, effects, at);
}

// A device loss's reason, whose key Audio follows with what was missing
// and what its read held.
function deviceLost(reason) {
    return reason.indexOf("device-lost ") === 0;
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
    s.conversation = { kind: "interrupted", purpose: s.conversation.purpose };
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
    if (s.fault.kind === "none" || s.fault.kind === "retrying" || s.gate.kind !== "up") return;
    end(s, effects, at, "recover", false);
    s.fault = { kind: "none" };
}

// A press within the debounce interval is a bounce, not a press: it
// leaves the fault shown.
function bounced(s, at) { return s.toggleAt !== null && at - s.toggleAt < TOGGLE_DEBOUNCE_MS; }

function toggle(s, effects, at) {
    if (bounced(s, at)) return;
    recover(s, effects, at);
    if (!canEngage(s)) return;
    s.toggleAt = at;
    if (s.conversation.kind === "ended" || previewConversation(s) || s.input.kind === "stopped") start(s, effects, "conversation", at);
    else end(s, effects, at, "toggle", false);
}

function expire(s, effects, at) {
    if (s.quiet.kind === "waiting" && at >= s.quiet.deadline) {
        if (s.turn.kind === "thinking" || s.turn.kind === "cancelling" || s.action.kind === "running"
                || s.approval.kind === "held" || s.playback.kind !== "idle") activity(s, at);
        else end(s, effects, at, "idle", false);
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
    if (["playing", "feedback"].indexOf(s.playback.kind) !== -1 && s.playback.deadline !== null && at >= s.playback.deadline) {
        if (s.playback.kind === "feedback" && s.playback.cue === "stop") flushPlayback(s, effects);
        else {
            s.fault = { kind: "error", reason: "playback-timeout", retry: 0 };
            end(s, effects, at, "playback-timeout", false);
        }
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
        s.input = releasedInput(s);
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
        if (devicesChanged && s.fault.kind === "error" && deviceLost(s.fault.reason))
            s.fault = { kind: "none" };
        if (settingsChanged || devicesChanged && ["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1) {
            var before = s.gen;
            end(s, effects, e.at, "settings", false);
            if (s.gen === before) s.gen++;
            s.fault = { kind: "none" };
            if (settingsChanged) {
                resetHistory(s, null);
                s.restart = { kind: "none" };
            }
        }
        s.settings = JSON.parse(JSON.stringify(e.settings));
        if (s.settings.sounds !== true) s.cue = { kind: "none" };
        if (s.settings.sounds !== true && s.playback.kind === "feedback" && s.playback.cue !== "line") flushPlayback(s, effects);
        s.engine = { kind: e.engine };
        s.duplex = { kind: e.engine === "duplex" && e.echoCancel === true ? "full" : "half" };
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
        if (["gone", "present", "listening"].indexOf(e.bar) === -1) throw new Error("jarvis: session=bar-indicator");
        // A loss always withdraws; a positive frame belongs to the
        // generation whose badge the host actually drew.
        s.barIndicator = e.bar === "gone" || e.gen !== s.gen ? { kind: "gone" } : { kind: e.bar, gen: e.gen };
        if (s.visibility.kind === "showing" && e.shown === true && e.gen === s.gen)
            s.visibility = { kind: "shown" };
        if (!canCapture(s) && s.input.kind === "check" && s.capture.kind !== "closed") end(s, effects, e.at, "indicator", false);
        break;
    case "hide":
        if (hideRefusal(s) !== null || s.visibility.kind === "hidden") break;
        s.visibility = { kind: "hidden" };
        effect(s, effects, "hidden-store", { hidden: true });
        break;
    case "show":
        if (s.visibility.kind !== "hidden") break;
        // Demand survives indicator loss; only admitted bar capture needs
        // transfer. Otherwise request the orb without granting capture.
        s.visibility = { kind: s.indicator.kind === "shown" || !canCapture(s) ? "shown" : "showing" };
        effect(s, effects, "hidden-store", { hidden: false });
        break;
    // The daemon restores its own record. Unlike an interactive Hide it
    // needs no current widget and writes nothing; admission still waits.
    case "hidden":
        s.visibility = { kind: "hidden" };
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
        if (s.settings.holdToTalk !== true) { toggle(s, effects, e.at); break; }
        if (s.input.kind === "held") break;
        recover(s, effects, e.at);
        interrupt(s, effects, e.at);
        start(s, effects, "held", e.at);
        break;
    case "talk-up":
        if (s.settings.holdToTalk !== true && s.approval.kind !== "held") break;
        if (s.input.kind !== "held") break;
        if (s.approval.kind !== "held" && e.at - s.input.since < TAP_MS && !s.input.heard && s.fault.kind === "none") {
            if (["opening", "open"].indexOf(s.capture.kind) === -1) end(s, effects, e.at, "tap", false);
            else {
                s.input = { kind: "closing-tap", source: s.capture.op };
                closeCapture(s, effects);
            }
            break;
        }
        s.input = { kind: "released" };
        closeCapture(s, effects);
        break;
    case "toggle":
        toggle(s, effects, e.at);
        break;
    case "new-conversation": {
        var open = s.conversation.kind !== "ended" && !previewConversation(s);
        var heldInput = s.input.kind === "held";
        var priorGen = s.gen;
        end(s, effects, e.at, "new-conversation", true);
        if (s.gen === priorGen) s.gen++;
        closeBrain(s, effects);
        resetHistory(s, "requested");
        effect(s, effects, "brain-reset", {});
        s.cue = { kind: "none" };
        s.fault = { kind: "none" };
        s.restart = { kind: "none" };
        s.input = { kind: "released" };
        if (open) {
            s.conversation = { kind: "active", purpose: "conversation" };
            s.input = heldInput ? { kind: "held", since: e.at, heard: false } : releasedInput(s);
            activity(s, e.at);
        }
        break;
    }
    case "conversation-reset":
        if (!live(s, e, "turn", ["thinking"])) { stale(s); break; }
        if (e.reason !== "turn-limit" || typeof e.text !== "string" || e.text.trim() === "")
            throw new Error("jarvis: session=conversation-reset");
        resetHistory(s, e.reason);
        userTranscript(s, effects, e.text, 1);
        activity(s, e.at);
        break;
    // Voice mute changes no other region: Audio's paced write reads it and
    // sends silence, so the reply, its playback and its deadline run as when
    // heard. Only these two events change it; talk, stop and a new
    // conversation keep it. voice-mute applies the restored record and
    // stores nothing.
    case "voice-mute-toggle":
        s.voiceMute = { kind: s.voiceMute.kind === "on" ? "off" : "on" };
        effect(s, effects, "voice-mute-store", { muted: s.voiceMute.kind === "on" });
        break;
    case "voice-mute":
        s.voiceMute = { kind: "on" };
        break;
    case "stop":
        if (previewConversation(s)) {
            end(s, effects, e.at, "preview", true);
            break;
        }
        var faulted = s.fault.kind !== "none" || s.input.kind === "stopped";
        if (["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1) s.check = { kind: "ready" };
        interrupt(s, effects, e.at);
        requestToolCancel(s, effects);
        closeCapture(s, effects);
        s.cue = { kind: "none" };
        if (s.conversation.kind !== "ended") s.conversation = { kind: "active", purpose: s.conversation.purpose };
        s.input = releasedInput(s);
        s.fault = { kind: "none" };
        activity(s, e.at);
        if (faulted) s.input = { kind: "stopped" };
        break;
    case "lease-ended":
        end(s, effects, e.at, "lease", true);
        resetHistory(s, null);
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
        if (s.turn.kind === "collecting") s.turn.deadline = null;
        if (s.fault.kind === "retrying") s.fault = { kind: "none" };
        break;
    case "capture-failed": {
        if (!live(s, e, "capture", ["opening", "open", "closing"])) { stale(s); break; }
        var retry = s.fault.kind === "retrying" ? s.fault.retry : 0;
        s.fault = deviceLost(e.reason) && retry < 3
            ? { kind: "retrying", reason: e.reason, retry: retry + 1 }
            : { kind: "error", reason: e.reason, retry: retry };
        if (s.capture.kind === "closing") s.capture = { kind: "closed" };
        else closeCapture(s, effects);
        if (s.input.kind === "check") end(s, effects, e.at, "capture-failed", false);
        if (s.input.kind === "closing-tap") end(s, effects, e.at, "capture-failed", false);
        if (s.turn.kind === "collecting") s.turn = { kind: "none" };
        break;
    }
    case "capture-closed":
        if (!live(s, e, "capture", ["closing"])) { stale(s); break; }
        s.capture = { kind: "closed" };
        if (s.engine.kind === "duplex" && s.input.kind === "closing-tap") {
            if (typeof e.speech !== "boolean") throw new Error("jarvis: session=capture-speech");
            if (!e.speech) end(s, effects, e.at, "tap", false);
        }
        break;
    case "partial":
        if (!live(s, e, "turn", ["collecting"])) { stale(s); break; }
        s.turn.partial = e.text;
        if (String(e.text).trim() !== "") activity(s, e.at);
        break;
    case "delegation":
    case "final":
        if (e.type === "delegation") {
            if (s.engine.kind !== "duplex" || !live(s, e, "speech", ["open"]) || !canEngage(s)) { stale(s); break; }
            cancelTurn(s, effects, e.at);
            dropApproval(s, effects, "replaced", e.at);
            // A new request drops the words the voice held for the old one.
            if (s.speech.reply.kind === "due") s.speech.reply = { kind: "none" };
            if (s.conversation.kind === "interrupted") s.conversation = { kind: "active", purpose: s.conversation.purpose };
            spendRestart(s);
            think(s, effects, { text: e.text, delegation: e.id }, e.at);
        } else {
            if (!live(s, e, "turn", ["collecting"])) { stale(s); break; }
            if (String(e.text).trim() === "") {
                s.turn = { kind: "none" };
                if (s.input.kind === "closing-tap") end(s, effects, e.at, "tap", false);
                break;
            }
            commitUserText(s, effects, e.text, e.at, e.op);
        }
        activity(s, e.at);
        break;
    case "say":
        if (sayRefusal(s) !== null) break;
        if (["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1) end(s, effects, e.at, "say", false);
        recover(s, effects, e.at);
        commitUserText(s, effects, e.text, e.at, 1);
        break;
    // A preview speaks the engine's fixed sentence as a turn of its own; a
    // duplex voice opens its session for it with no capture.
    case "preview":
        if (previewRefusal(s) !== null) break;
        recover(s, effects, e.at);
        // A new conversation takes a new gen; one between turns keeps its own.
        if (s.conversation.kind === "ended") {
            s.gen += 1;
            s.conversation = { kind: "active", purpose: "preview" };
        } else if (s.conversation.kind !== "active") s.conversation = { kind: "active", purpose: s.conversation.purpose };
        activity(s, e.at);
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
        s.conversation = { kind: "active", purpose: s.conversation.purpose };
        think(s, effects, { relay: { text: e.text, ask: e.ask, labels: e.labels } }, e.at);
        break;
    // A transcription that fails after its capture closed still owns the turn.
    case "collect-failed":
        if (!live(s, e, "turn", ["collecting"])) { stale(s); break; }
        s.turn = { kind: "none" };
        s.fault = { kind: "error", reason: e.reason, retry: 0 };
        end(s, effects, e.at, "collect-failed", false);
        break;
    case "brain-done":
    case "brain-failed":
        if (e.type === "brain-failed" && !restartAnswer(e.restart)) throw new Error("jarvis: session=brain-failed");
        if (!live(s, e, "turn", ["thinking"])) { stale(s); break; }
        s.turn = { kind: "none" };
        if (e.type === "brain-done") activity(s, e.at);
        if (e.type === "brain-done" && ["playing", "feedback"].indexOf(s.playback.kind) !== -1)
            s.playback.deadline = e.at + PLAYBACK_TIMEOUT_MS;
        if (e.type === "brain-done" && (s.playback.kind === "flushing" || s.playback.kind === "feedback")
                && s.playback.reply.kind === "waiting")
            s.playback.reply.deadline = e.at + PLAYBACK_TIMEOUT_MS;
        if (e.type === "brain-failed") failBrain(s, effects, e);
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
        var lineReply = s.playback.kind === "feedback" ? s.playback.reply : { kind: "none" };
        s.playback = lineReply.kind === "waiting" && lineReply.gen === s.gen && s.conversation.kind === "active" && canEngage(s)
            ? { kind: "playing", gen: lineReply.gen, op: operation(s), source: lineReply.source,
                interruptible: lineReply.interruptible, admission: { kind: "waiting" }, deadline: lineReply.deadline }
            : { kind: "idle" };
        activity(s, e.at);
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
        // A failed closing tone cannot reopen the closed conversation's UI.
        if (s.playback.kind === "feedback" && s.playback.cue === "stop") {
            s.playback = { kind: "idle" };
            break;
        }
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
        activity(s, e.at);
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
        s.input = releasedInput(s);
        activity(s, e.at);
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
        s.input = releasedInput(s);
        activity(s, e.at);
        closeCapture(s, effects);
        break;
    case "speak":
        if (!live(s, e, "speech", ["open"])) { stale(s); break; }
        // New output after an interruption answers new input.
        if (s.conversation.kind === "interrupted") s.conversation = { kind: "active", purpose: s.conversation.purpose };
        s.speech.reply = { kind: "waiting" };
        activity(s, e.at);
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
        if (String(e.text).trim() !== "") activity(s, e.at);
        break;
    case "input-silent":
    case "input-sound":
        if (!live(s, e, "capture", ["open"])) { stale(s); break; }
        if (typeof e.device !== "string" || e.device === "") throw new Error("jarvis: session=input-device");
        s.sound = e.type === "input-silent" ? { kind: "silent", device: e.device } : { kind: "none" };
        break;
    case "speech-input-ended":
        if (!live(s, e, "speech", ["open"])) { stale(s); break; }
        if (typeof e.empty !== "boolean") throw new Error("jarvis: session=input-ended");
        // A native result can precede release. Keep real words against the
        // same capture, so a short spoken hold is never mistaken for empty.
        if (s.input.kind === "held" && ["opening", "open"].indexOf(s.capture.kind) !== -1 && s.capture.op === e.capture && !e.empty) {
            s.input.heard = true;
            activity(s, e.at);
            break;
        }
        if (s.input.kind !== "closing-tap" || s.input.source !== e.capture) { stale(s); break; }
        if (e.empty) end(s, effects, e.at, "tap", false);
        else { s.input = { kind: "released" }; activity(s, e.at); }
        break;
    case "speech-idle":
        if (!live(s, e, "speech", ["open"])) { stale(s); break; }
        if (previewConversation(s)) {
            end(s, effects, e.at, "preview", false);
            break;
        }
        // Session owns the shared quiet deadline; a provider idle event
        // cannot shorten it or close a still-open conversation.
        break;
    case "speech-failed":
        if (!live(s, e, "speech", ["open"])) { stale(s); break; }
        // A failed engine has already released its session.
        s.speech = { kind: "closed" };
        // Only duplex speech opens this port; a brain's failure has its own
        // event even under duplex. Keep the origin, not a guess from net=.
        s.fault = { kind: "voice-connection", reason: e.reason };
        end(s, effects, e.at, "speech-failed", false);
        break;
    case "deadline":
        if (live(s, e, "turn", ["collecting", "thinking", "cancelling"])
                || live(s, e, "check", ["waiting", "recording", "finishing"])
                || live(s, e, "playback", ["playing", "feedback"])
                || live(s, e, "approval", ["held"]) || live(s, e, "action", ["running"])
                || live(s, e, "quiet", ["waiting"]))
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
    gate: { down: "reason", up: "" }, voiceMute: { off: "", on: "" },
    capture: { closed: "", opening: "gen op mode", open: "gen op mode", closing: "gen op" },
    turn: { none: "", collecting: "gen op partial deadline", thinking: "gen op deadline", cancelling: "gen op deadline" },
    brain: { closed: "", acquired: "gen op" },
    playback: { idle: "", playing: "gen op source interruptible admission deadline",
        feedback: "gen op source cue admission deadline reply", flushing: "gen op reply" },
    action: { none: "", running: "gen op tool brain limit cancellation" }, cue: { none: "", pending: "cue" },
    approval: { none: "", held: "purpose gen op id digest deadline shownAt physical text tool timeoutMs cancellable brain" },
    fault: { none: "", error: "reason retry", retrying: "reason retry", "voice-connection": "reason" }, conversation: { ended: "", active: "purpose", interrupted: "purpose" },
    history: { current: "epoch", reset: "epoch reason" },
    input: { released: "", stopped: "", held: "since heard", conversation: "", check: "", "closing-tap": "source" },
    quiet: { none: "", waiting: "gen op deadline" }, sound: { none: "", silent: "device" },
    indicator: { gone: "", shown: "" }, barIndicator: { gone: "", present: "gen", listening: "gen" },
    visibility: { shown: "", showing: "", hidden: "" }, duplex: { half: "", full: "" },
    engine: { chained: "", dictation: "", duplex: "" }, speech: { closed: "", open: "gen op reply" },
    restart: { none: "", restarted: "category", spent: "" },
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
            if (["gen", "op", "brain", "source", "retry", "epoch"].indexOf(f) !== -1) {
                if (!Number.isSafeInteger(r[f]) || r[f] < (["op", "brain", "source"].indexOf(f) !== -1 ? 1 : 0)) return false;
            } else if (f === "device") {
                if (r[f] !== null && typeof r[f] !== "string") return false;
            } else if (f === "since") {
                if (!Number.isFinite(r[f]) || r[f] < 0) return false;
            } else if (f === "deadline" || f === "shownAt") {
                if (f === "deadline" && r[f] === null && (region === "playback" || r.kind === "collecting")) continue;
                if (!(f === "shownAt" && r[f] === null) && (!Number.isFinite(r[f]) || r[f] < 0)) return false;
            } else if (f === "timeoutMs") {
                if (!Number.isFinite(r[f]) || r[f] <= 0) return false;
            } else if (["interruptible", "physical", "cancellable", "heard"].indexOf(f) !== -1) {
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
        if (region === "conversation" && r.kind !== "ended" && ["conversation", "preview"].indexOf(r.purpose) === -1) return false;
        if (region === "history" && r.kind === "reset" && ["requested", "turn-limit"].indexOf(r.reason) === -1) return false;
        if (region === "capture" && fields.indexOf("mode") !== -1
                && ["hold", "conversation", "check"].indexOf(r.mode) === -1) return false;
        if (region === "sound" && r.kind === "silent" && (typeof r.device !== "string" || r.device === "")) return false;
        if (region === "check" && (r.kind === "done" || r.kind === "kept") && ["ready", "silent", "not-heard"].indexOf(r.result) === -1) return false;
        if (region === "playback" && r.kind === "feedback" && ["start", "stop", "working", "line"].indexOf(r.cue) === -1) return false;
        if (region === "cue" && r.kind === "pending" && ["start", "stop"].indexOf(r.cue) === -1) return false;
        if (region === "restart" && r.kind === "restarted" && FAULT_CATEGORIES.indexOf(r.category) === -1) return false;
        if (region === "gate" && r.kind === "down"
                && ["starting", "unconfigured", "node", "lock-unknown", "locked"].indexOf(r.reason) === -1) return false;
    }
    return true;
}
