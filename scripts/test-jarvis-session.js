#!/usr/bin/env node
// Pure Session contracts. All time is injected; no process, socket or audio
// device exists here. Callbacks use the identity of the production owner.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { load } = require("../bin/lib/qml-library.js");
const file = path.resolve(__dirname, "../shell/plugins/vgs.jarvis/Session.js");
const Session = load(file);
const copy = value => JSON.parse(JSON.stringify(value));
const event = (type, at = 10, extra = {}) => ({ type, at, ...(type === "indicator" ? { bar: "gone" } : {}), ...extra });
const snapshot = (extra = {}) => ({ type: "snapshot", at: 0, locked: false, configured: true,
    engine: "chained", settings: {}, ...extra });
const callback = (type, owner, at = 20, extra = {}) => event(type, at, {
    gen: owner.gen, op: owner.op, ...extra });
const step = (logic, state, input) => copy(logic.reduce(state,
    input.type === "indicator" ? { gen: state.gen, ...input } : input));
const kinds = result => result.effects.map(effect => effect.kind);
const has = (result, kind) => kinds(result).includes(kind);
const LOST = 'device-lost target="fixture.mic" from=default microphones=0[]';
function ready(logic, settings = {}, engine = "chained") {
    let s = step(logic, logic.initial(), snapshot({ settings, engine })).state;
    return step(logic, s, event("indicator", 1, { shown: true })).state;
}
function listening(logic, holdToTalk = true, engine = "chained", settings = {}) {
    let s = ready(logic, { ...settings, holdToTalk }, engine);
    s = step(logic, s, event("talk-down")).state;
    if (s.playback.kind === "feedback") s = step(logic, s, callback("played", s.playback, 11)).state;
    return step(logic, s, callback("capture-opened", s.capture, 20)).state;
}
function thinking(logic, holdToTalk = true) {
    let s = listening(logic, holdToTalk);
    s = step(logic, s, callback("final", s.turn, 30, { text: "test" })).state;
    return step(logic, s, callback("capture-closed", s.capture, 31)).state;
}
function speaking(logic, holdToTalk = true) {
    const s = thinking(logic, holdToTalk);
    return step(logic, s, callback("play", s.turn, 40, { interruptible: true })).state;
}
function between(logic) {
    const s = thinking(logic);
    return step(logic, s, callback("brain-done", s.turn, 40)).state;
}
function acting(logic, cancellable = true) {
    const s = thinking(logic);
    return step(logic, s, callback("tool", s.turn, 40, {
        tool: "fixture", id: "tool", timeoutMs: 100, cancellable })).state;
}
function held(logic, physical = true, purpose = "action") {
    const s = thinking(logic);
    return step(logic, s, callback("approval", s.turn, 40, { id: "held", digest: "a".repeat(64), purpose,
        physical, text: "Fixture", tool: "fixture", timeoutMs: 100, cancellable: true })).state;
}
function confirm(logic, s, at, extra = {}) {
    return step(logic, s, callback("confirm", s.approval, at, {
        id: s.approval.id, digest: s.approval.digest, source: "key", ...extra }));
}
function duplexListening(logic, holdToTalk = true) { return listening(logic, holdToTalk, "duplex"); }
function echoListening(logic) {
    const s = duplexListening(logic, false);
    return step(logic, s, snapshot({ at: 21, engine: "duplex", settings: s.settings, echoCancel: true })).state;
}
function duplexReleased(logic) {
    let s = duplexListening(logic);
    s = step(logic, s, event("talk-up", 610)).state;
    return step(logic, s, callback("capture-closed", s.capture, 611, { speech: true })).state;
}
function duplexSpeaking(logic) {
    const s = duplexReleased(logic);
    return step(logic, s, callback("speak", s.speech, 612)).state;
}
function duplexThinking(logic) {
    const s = duplexReleased(logic);
    return step(logic, s, callback("delegation", s.speech, 612, { id: "request", text: "context" })).state;
}
function startCue(logic, engine = "chained", holdToTalk = false) {
    return step(logic, ready(logic, { sounds: true, holdToTalk }, engine), event("talk-down"));
}
function lineReply(logic) {
    let s = thinking(logic);
    s = step(logic, s, callback("feedback", s.turn, 40, { cue: "line" })).state;
    return step(logic, s, callback("play", s.turn, 41, { interruptible: true })).state;
}
function pendingReply(logic) {
    let s = thinking(logic);
    s = step(logic, s, snapshot({ at: 35, settings: { ...s.settings, sounds: true } })).state;
    s = step(logic, s, callback("feedback", s.turn, 40)).state;
    s = step(logic, s, snapshot({ at: 41, settings: { ...s.settings, sounds: false } })).state;
    return step(logic, s, callback("play", s.turn, 42, { interruptible: true })).state;
}

const table = [
    ["hidden-admission", logic => {
        for (const engine of ["chained", "dictation", "duplex"]) {
            let s = step(logic, ready(logic, {}, engine), event("hidden", 2)).state;
            const demand = step(logic, s, event("talk-down", 10));
            s = demand.state;
            assert.equal(logic.captureWanted(s), true, "badge demand exists before capture admission");
            assert.equal(has(demand, "capture-open"), false, "an orb alone never admits hidden capture");
            for (const bar of ["gone", "present"]) {
                const refused = step(logic, s, event("indicator", 11, { shown: true, bar }));
                assert.equal(has(refused, "capture-open"), false, bar + ": a listening badge is required");
                assert.equal(refused.state.capture.kind, "closed");
            }
            const admitted = step(logic, s, event("indicator", 12, { shown: false, bar: "listening" }));
            assert.equal(has(admitted, "capture-open"), true, engine + ": badge admits without orb");
            for (const opened of [false, true]) {
                let active = admitted.state;
                if (opened) active = step(logic, active, callback("capture-opened", active.capture, 13)).state;
                const lost = step(logic, active, event("indicator", 14, { shown: true, bar: "gone" }));
                assert.equal(lost.state.capture.kind, "closing", "loss retires opening and open recorders");
                assert.equal(lost.effects.find(e => e.kind === "capture-close").target, active.capture.op);
                assert.deepEqual(lost.state.history, active.history);
                assert.deepEqual(lost.state.conversation, active.conversation);
                assert.equal(lost.state.gen, active.gen);
                const returned = step(logic, lost.state, event("indicator", 15, { shown: false, bar: "listening" }));
                assert.equal(has(returned, "capture-open"), false, "a returned badge cannot bypass retirement");
                const stale = step(logic, returned.state, callback("capture-closed", { ...lost.state.capture, op: active.capture.op }, 16));
                assert.equal(stale.state.capture.kind, "closing");
                const closed = step(logic, stale.state, callback("capture-closed", lost.state.capture, 17));
                assert.equal(has(closed, "capture-open"), true, "only the matching close admits replacement");
            }
            const locked = step(logic, admitted.state, snapshot({ at: 20, settings: admitted.state.settings, engine, locked: true }));
            assert.equal(locked.state.capture.kind, "closing");
            assert.equal(locked.state.visibility.kind, "hidden");
            const oldFrame = step(logic, s, event("indicator", 12, { shown: false, bar: "listening", gen: s.gen - 1 }));
            assert.equal(has(oldFrame, "capture-open"), false, "old generation badge grants nothing");
            assert.equal(oldFrame.state.barIndicator.kind, "gone");
            const next = step(logic, admitted.state, event("new-conversation", 30));
            const cleaned = step(logic, next.state, callback("capture-closed", next.state.capture, 31));
            assert.equal(has(cleaned, "capture-open"), false, "new generation waits for its own badge frame");
        }
    }],
    ["hidden-choice", logic => {
        const base = ready(logic);
        assert.equal(logic.hideRefusal(base), "indicator");
        assert.equal(step(logic, base, event("hide", 2)).state.visibility.kind, "shown");
        let s = step(logic, base, event("indicator", 2, { shown: true, bar: "present" })).state;
        const hidden = step(logic, s, event("hide", 3));
        assert.equal(hidden.state.visibility.kind, "hidden");
        assert.deepEqual(hidden.effects.map(e => [e.kind, e.hidden]), [["hidden-store", true]]);
        assert.deepEqual({ ...hidden.state, visibility: s.visibility, nextOp: s.nextOp }, s, "Hide changes only its held choice");
        assert.deepEqual(step(logic, hidden.state, event("hide", 4)).effects, [], "repeated Hide stores nothing");
        const shown = step(logic, hidden.state, event("show", 5));
        assert.equal(shown.state.visibility.kind, "shown");
        assert.deepEqual(shown.effects.map(e => [e.kind, e.hidden]), [["hidden-store", false]]);
        assert.deepEqual(step(logic, shown.state, event("show", 6)).effects, []);
        const restored = step(logic, logic.initial(), event("hidden", 0));
        assert.equal(restored.state.visibility.kind, "hidden");
        assert.deepEqual(restored.effects, [], "restore never writes the record or opens capture");
        for (const type of ["talk-down", "stop", "new-conversation", "voice-mute-toggle", "lease-ended"]) {
            const result = step(logic, hidden.state, event(type, 20));
            assert.equal(result.state.visibility.kind, "hidden", type + ": independent held choice");
            assert.equal(has(result, "hidden-store"), false);
        }
        for (const seed of [speaking(logic), held(logic)]) {
            s = step(logic, seed, event("indicator", 50, { shown: true, bar: "present" })).state;
            const result = step(logic, s, event("hide", 51));
            assert.deepEqual(result.state.playback, s.playback, "hiding leaves speech and its cue ownership");
            assert.deepEqual(result.state.approval, s.approval, "hiding never dismisses a held ask");
            assert.deepEqual(result.state.quiet, s.quiet, "hiding does not refresh quiet lifetime");
        }
    }],
    ["hidden-cues", logic => {
        for (const engine of ["chained", "dictation", "duplex"]) {
            let s = step(logic, ready(logic, { sounds: true }, engine), event("hidden", 2)).state;
            s = step(logic, s, event("voice-mute", 3)).state;
            const opened = step(logic, s, event("talk-down", 10));
            assert.equal(opened.state.playback.cue, "start", engine + ": hidden still plays its start cue");
            assert.equal(has(opened, "capture-open"), false);
            s = step(logic, opened.state, callback("played", opened.state.playback, 11)).state;
            assert.equal(s.capture.kind, "closed", "a cue is no capture indicator");
            s = step(logic, s, event("indicator", 12, { shown: false, bar: "listening" })).state;
            s = step(logic, s, callback("capture-opened", s.capture, 13)).state;
            const quiet = copy(s.quiet), history = copy(s.history);
            const shown = step(logic, s, event("show", 14));
            assert.deepEqual(shown.state.quiet, quiet);
            assert.deepEqual(shown.state.history, history);
            assert.equal(has(shown, "playback-start"), false, "Show plays no cue");
            const closing = step(logic, s, event("talk-down", 400));
            assert.equal(closing.state.visibility.kind, "hidden");
            assert.equal(closing.state.voiceMute.kind, "on");
            const closed = step(logic, closing.state, callback("capture-closed", closing.state.capture, 401));
            assert.equal(closed.state.playback.cue, "stop", engine + ": hidden keeps normal closing cue");
            assert.equal(has(closed, "playback-start"), true);
        }
    }],
    ["history-resume", logic => {
        for (const engine of ["chained", "dictation", "duplex"]) {
            const s = listening(logic, false, engine);
            const closed = step(logic, s, event("toggle", 400));
            assert.deepEqual(closed.state.history, s.history, engine + ": ordinary close retains context identity");
            let next = step(logic, closed.state, callback("capture-closed", closed.state.capture, 401)).state;
            next = step(logic, next, event("talk-down", 700)).state;
            assert.deepEqual(next.history, s.history, engine + ": Talk resumes the same history across live generations");
            assert.ok(next.gen > s.gen);
            assert.equal(next.conversation.kind, "active");
            const quiet = listening(logic, false, engine);
            assert.deepEqual(step(logic, quiet, callback("deadline", quiet.quiet, quiet.quiet.deadline)).state.history, quiet.history);
            for (const boundary of [event("lease-ended", 710), snapshot({ at: 710, engine, settings: { ...next.settings, model: "changed" } })]) {
                const reset = step(logic, next, boundary).state;
                assert.deepEqual(reset.history, { kind: "current", epoch: next.history.epoch + 1 });
            }
        }
    }],
    ["new-conversation", logic => {
        const rows = [
            [ready(logic), false, "released"],
            [listening(logic, false), true, "conversation"],
            [listening(logic, false, "chained", { sounds: true }), true, "conversation"],
            [listening(logic, true), true, "held"],
            [between(logic), true, "released"],
            [speaking(logic), true, "released"],
            [acting(logic), true, "released"],
            [held(logic), true, "released"],
            [duplexListening(logic, false), true, "conversation"],
            [duplexReleased(logic), true, "released"],
            [duplexSpeaking(logic), true, "released"]
        ];
        for (const [s, open, input] of rows) {
            const reset = step(logic, s, event("new-conversation", 1000));
            assert.deepEqual(reset.state.history, { kind: "reset", epoch: s.history.epoch + 1, reason: "requested" });
            assert.equal(reset.state.gen, s.gen + 1);
            assert.equal(reset.state.conversation.kind, open ? "active" : "ended");
            assert.equal(reset.state.input.kind, input);
            assert.equal(reset.state.cue.kind, "none");
            assert.equal(reset.state.fault.kind, "none");
            assert.equal(reset.state.approval.kind, "none");
            assert.equal(reset.effects.filter(e => e.kind === "brain-reset").length, 1);
            assert.equal(has(reset, "capture-open"), false, "old resources close before a reset opens capture");
            assert.equal(has(reset, "playback-start"), false, "reset adds no conversation cue");
            if (s.speech.kind === "open") {
                assert.equal(reset.effects.find(e => e.kind === "speech-close").target, s.speech.op);
                const late = step(logic, reset.state, callback("transcript", s.speech, 1001,
                    { role: "assistant", text: "old", stage: "final", rev: 1 }));
                assert.equal(has(late, "transcript"), false, "old speech cannot repopulate fresh history");
            }
            if (s.turn.kind === "thinking") {
                assert.equal(reset.effects.find(e => e.kind === "brain-cancel").target, s.turn.op);
                assert.equal(reset.effects.find(e => e.kind === "brain-close").target, s.brain.op);
                const late = step(logic, reset.state, callback("brain-done", s.turn, 1001));
                assert.equal(late.state.stale, reset.state.stale + 1);
            }
            if (s.action.kind === "running") assert.equal(has(reset, "tool-cancel"), true);
        }
        const s = listening(logic, false);
        const reset = step(logic, s, event("new-conversation", 1000));
        const cleaned = step(logic, reset.state, callback("capture-closed", reset.state.capture, 1001));
        assert.equal(cleaned.state.capture.kind, "opening", "automatic capture resumes only after old recorder acknowledgment");
        assert.equal(cleaned.effects.find(e => e.kind === "capture-open").gen, reset.state.gen);
    }],
    ["turn-limit-reset", logic => {
        const s = thinking(logic);
        const text = "Keep this attempted message";
        for (const extra of [{}, { gen: s.turn.gen + 1 }, { op: s.turn.op + 1 }]) {
            const result = step(logic, s, callback("conversation-reset", s.turn, 40, { reason: "turn-limit", text, ...extra }));
            const live = Object.keys(extra).length === 0;
            assert.equal(result.state.history.epoch, s.history.epoch + (live ? 1 : 0));
            assert.deepEqual(result.state.turn, s.turn, "the attempted thinking operation survives");
            assert.equal(result.state.gen, s.gen);
            assert.equal(result.state.conversation.kind, "active");
            assert.equal(result.state.fault.kind, "none");
            assert.equal(result.state.cue.kind, "none");
            assert.equal(has(result, "brain-close"), false);
            assert.equal(has(result, "speech-close"), false);
            assert.equal(has(result, "playback-start"), false);
            const transcript = result.effects.find(e => e.kind === "transcript");
            if (live) {
                assert.equal(result.state.history.reason, "turn-limit");
                assert.deepEqual([transcript.role, transcript.text, transcript.stage], ["user", text, "final"]);
            } else assert.equal(transcript, undefined);
        }
    }],
    ["default-talk", logic => {
        for (const settings of [{}, { holdToTalk: false }]) {
            const s = ready(logic, settings);
            const pressed = step(logic, s, event("talk-down", 100));
            assert.deepEqual([pressed.state.input.kind, pressed.state.conversation.kind, pressed.state.capture.kind],
                ["conversation", "active", "opening"]);
            const released = step(logic, pressed.state, event("talk-up", 101));
            assert.deepEqual(released, { state: pressed.state, effects: [] }, "default release leaves listening demand");
            assert.deepEqual(step(logic, released.state, event("talk-down", 349)), released, "repeat inside debounce is inert");
            const closed = step(logic, released.state, event("talk-down", 350));
            assert.equal(closed.state.conversation.kind, "ended", "next press closes");
            assert.equal(closed.state.gen, pressed.state.gen + 1);
            assert.equal(closed.state.capture.kind, "closing");
        }
        for (const s of [thinking(logic, false), speaking(logic, false)]) {
            const closed = step(logic, s, event("talk-down", 400));
            assert.equal(closed.state.conversation.kind, "ended", "default Talk closes during reply or work");
            assert.equal(has(closed, "brain-cancel"), true);
            assert.equal(has(closed, "capture-open"), false);
            if (s.playback.kind === "playing") assert.equal(has(closed, "playback-flush"), true);
        }
    }],
    ["default-turns", logic => {
        for (const engine of ["chained", "dictation", "duplex"]) {
            let s = listening(logic, false, engine);
            const gen = s.gen;
            if (engine === "duplex") s = step(logic, s, callback("speak", s.speech, 30)).state;
            else s = step(logic, s, callback("final", s.turn, 30, { text: "first" })).state;
            s = step(logic, s, callback("capture-closed", s.capture, 31)).state;
            if (engine !== "duplex") {
                s = step(logic, s, callback("play", s.turn, 40, { interruptible: true })).state;
                if (s.capture.kind === "closing") s = step(logic, s, callback("capture-closed", s.capture, 41)).state;
                s = step(logic, s, callback("brain-done", s.turn, 42)).state;
            }
            s = step(logic, s, callback("played", s.playback, 43)).state;
            assert.deepEqual([s.conversation.kind, s.input.kind, s.capture.kind, s.gen],
                ["active", "conversation", "opening", gen], engine + ": reply completion listens again");
        }
    }],
    ["hold-release", logic => {
        for (const engine of ["chained", "dictation", "duplex"]) {
            const s = listening(logic, true, engine);
            assert.deepEqual(s.input, { kind: "held", since: 10, heard: false }, "new hold has no native nonempty result");
            assert.deepEqual(step(logic, s, event("talk-down", 21)), { state: s, effects: [] }, "held repeat is inert");
            const released = step(logic, s, event("talk-up", 610));
            assert.deepEqual([released.state.input.kind, released.state.capture.kind, released.state.conversation.kind, released.state.gen],
                ["released", "closing", "active", s.gen], engine + ": long release closes only microphone");
            assert.equal(logic.indicatorWanted(released.state), true, "open conversation retains orb");
            assert.equal(has(released, "speech-close"), false);
            assert.deepEqual(step(logic, released.state, event("talk-up", 611)), { state: released.state, effects: [] });
            let closed = step(logic, released.state, callback("capture-closed", released.state.capture, 612, { speech: true })).state;
            closed = engine === "duplex" ? step(logic, closed, callback("speak", closed.speech, 613)).state
                : step(logic, closed, callback("final", closed.turn, 613, { text: "held words" })).state;
            if (engine !== "duplex") closed = step(logic, closed, callback("play", closed.turn, 614, { interruptible: true })).state;
            assert.equal(closed.playback.kind, "playing", "reply proceeds after release");
            closed = step(logic, closed, callback("played", closed.playback, 615)).state;
            assert.equal(closed.capture.kind, "closed", "checked release keeps microphone closed after reply");
            assert.equal(closed.conversation.kind, "active");
        }
        const idle = ready(logic, { holdToTalk: true });
        assert.deepEqual(step(logic, idle, event("talk-up")), { state: idle, effects: [] }, "release alone grants no hold");
    }],
    ["hold-interrupt", logic => {
        for (const s of [speaking(logic), duplexSpeaking(logic)]) {
            const r = step(logic, s, event("talk-down", 700));
            assert.deepEqual([r.state.conversation.kind, r.state.input.kind, r.state.gen], ["active", "held", s.gen]);
            assert.equal(has(r, "playback-flush"), true);
            assert.equal(has(r, "capture-open"), false, "capture waits for flush and cancel acknowledgments");
            let next = step(logic, r.state, callback("flushed", r.state.playback, 701)).state;
            if (next.turn.kind === "cancelling") next = step(logic, next, callback("cancelled", next.turn, 702)).state;
            assert.equal(next.capture.kind, "opening");
            if (s.engine.kind === "duplex") assert.equal(r.effects.find(e => e.kind === "speech-flush").target, s.speech.op);
        }
    }],
    ["silent-tap-local", logic => {
        for (const engine of ["chained", "dictation"]) for (const text of ["", "spoken words"]) {
            const s = listening(logic, true, engine);
            const tapped = step(logic, s, event("talk-up", 100));
            assert.deepEqual([tapped.state.input.kind, tapped.state.capture.kind], ["closing-tap", "closing"]);
            const closed = step(logic, tapped.state, callback("capture-closed", tapped.state.capture, 101)).state;
            const result = step(logic, closed, callback("final", s.turn, 102, { text }));
            assert.equal(result.state.conversation.kind, text === "" ? "ended" : "active");
            assert.equal(has(result, "brain-send"), text !== "");
            assert.equal(result.state.fault.kind, "none");
        }
        const cue = startCue(logic, "chained", true).state;
        const early = step(logic, cue, event("talk-up", 11));
        assert.equal(early.state.conversation.kind, "ended", "tap before capture admission closes");
        assert.equal(has(early, "capture-open"), false);
        const flushed = step(logic, early.state, callback("flushed", early.state.playback, 12));
        assert.equal(has(flushed, "capture-open"), false, "late opening sound cannot reopen ended tap");
    }],
    ["silent-tap-cloud", logic => {
        for (const speech of [false, true]) for (const empty of [false, true]) {
            const s = duplexListening(logic);
            let r = step(logic, s, event("talk-up", 100));
            assert.equal(r.state.input.source, s.capture.op, "tap names admitted capture");
            r = step(logic, r.state, callback("capture-closed", r.state.capture, 101, { speech }));
            if (!speech) {
                assert.deepEqual([r.state.conversation.kind, r.state.fault.kind], ["ended", "none"], "no committed audio closes normally");
                continue;
            }
            assert.deepEqual([r.state.input.kind, r.state.conversation.kind], ["closing-tap", "active"]);
            const old = step(logic, r.state, callback("speech-input-ended", s.speech, 102, { capture: s.capture.op + 100, empty: true }));
            assert.equal(old.state.input.kind, "closing-tap", "another capture cannot decide this tap");
            assert.equal(old.state.stale, r.state.stale + 1);
            const delayed = step(logic, r.state, callback("speech-idle", s.speech, 60000));
            assert.equal(delayed.state.conversation.kind, "active", "missing captions and provider idle are no empty result");
            const result = step(logic, delayed.state, callback("speech-input-ended", s.speech, 60001, { capture: s.capture.op, empty }));
            assert.equal(result.state.conversation.kind, empty ? "ended" : "active");
            assert.equal(result.state.input.kind, "released");
            assert.equal(result.state.fault.kind, "none");
        }
    }],
    // Realtime/Gemini report inputEnded once for the original capture op.
    // empty:false is an actual nonempty native transcript, not PCM admission
    // or a caption guess (Realtime/GeminiLive inputResult/reportInput).
    ["cloud-native-result-order", logic => {
        for (const capturePhase of ["opening", "open"]) for (const order of ["before-release", "after-release"]) {
            let s = startCue(logic, "duplex", true).state;
            s = step(logic, s, callback("played", s.playback, 11)).state;
            if (capturePhase === "open") s = step(logic, s, callback("capture-opened", s.capture, 20)).state;
            const capture = copy(s.capture), speech = copy(s.speech), gen = s.gen;
            assert.deepEqual(s.input, { kind: "held", since: 10, heard: false });
            for (const extra of [{ capture: capture.op + 100 }, { gen: speech.gen + 1 }, { op: speech.op + 100 }]) {
                const old = step(logic, s, callback("speech-input-ended", speech, 25, { capture: capture.op, empty: false, ...extra }));
                assert.equal(old.state.input.heard, false, "another capture or speech owner cannot mark this hold heard");
                assert.equal(old.state.quiet.deadline, s.quiet.deadline);
                assert.equal(old.state.stale, s.stale + 1);
            }
            if (order === "before-release") {
                const heard = step(logic, s, callback("speech-input-ended", speech, 30, { capture: capture.op, empty: false }));
                assert.deepEqual(heard.state.input, { kind: "held", since: 10, heard: true });
                assert.equal(logic.validate(heard.state), true);
                assert.equal(heard.state.quiet.deadline, 30 + 30 * 60 * 1000);
                // A native adapter may delegate in the same event that
                // reports its final transcript, before physical key release.
                const delegated = step(logic, heard.state, callback("delegation", speech, 31, { id: "native-request", text: "spoken request" }));
                assert.equal(delegated.effects.find(e => e.kind === "brain-send").text, "spoken request");
                s = delegated.state;
            }
            const released = step(logic, s, event("talk-up", 100));
            assert.equal(released.state.input.kind, order === "before-release" ? "released" : "closing-tap",
                order + ": a short spoken hold keeps the conversation");
            assert.deepEqual([released.state.conversation.kind, released.state.capture.kind, released.state.gen, released.state.cue.kind],
                ["active", "closing", gen, "none"]);
            assert.equal(released.state.playback.kind, "idle", "short spoken release has no closing tone");
            s = step(logic, released.state, callback("capture-closed", released.state.capture, 101, { speech: true })).state;
            if (order === "after-release") {
                const heard = step(logic, s, callback("speech-input-ended", speech, 102, { capture: capture.op, empty: false }));
                assert.equal(heard.state.input.kind, "released");
                const delegated = step(logic, heard.state, callback("delegation", speech, 103, { id: "native-request", text: "spoken request" }));
                assert.equal(delegated.effects.find(e => e.kind === "brain-send").text, "spoken request");
                s = delegated.state;
            }
            assert.deepEqual([s.conversation.kind, s.capture.kind, s.turn.kind, s.speech.op, s.gen, s.cue.kind],
                ["active", "closed", "thinking", speech.op, gen, "none"], order + ": the native request retains its live conversation");
        }
    }],
    ["tap-failure", logic => {
        for (const engine of ["chained", "dictation", "duplex"]) {
            const s = listening(logic, true, engine);
            const tapped = step(logic, s, event("talk-up", 100)).state;
            const failed = step(logic, tapped, callback("capture-failed", tapped.capture, 101, { reason: "capture=failed" }));
            assert.deepEqual([failed.state.conversation.kind, failed.state.fault.reason], ["ended", "capture=failed"]);
            assert.equal(failed.state.fault.kind, "error", "a real capture failure is not silence");
        }
    }],
    ["stop-retains-conversation", logic => {
        for (const holdToTalk of [false, true]) {
            const before = speaking(logic, holdToTalk);
            const r = step(logic, before, event("stop", 700));
            assert.deepEqual([r.state.gen, r.state.conversation.kind, r.state.cue.kind], [before.gen, "active", "none"]);
            assert.equal(r.state.conversation.purpose, "conversation", "Stop retains the actual conversation purpose");
            assert.equal(has(r, "brain-cancel"), true);
            assert.equal(has(r, "playback-flush"), true);
            assert.equal(has(r, "brain-close"), false, "Stop preserves conversation owner");
            assert.equal(has(r, "speech-close"), false);
            let s = step(logic, r.state, callback("flushed", r.state.playback, 701)).state;
            s = step(logic, s, callback("cancelled", s.turn, 702)).state;
            assert.deepEqual(s.brain, before.brain, "acknowledged cancellation preserves brain history");
            assert.equal(s.capture.kind, holdToTalk ? "closed" : "opening");
            assert.equal(logic.indicatorWanted(s), true);
        }
        const s = duplexSpeaking(logic);
        const r = step(logic, s, event("stop", 700));
        assert.equal(r.effects.find(e => e.kind === "speech-flush").target, s.speech.op);
        assert.deepEqual(r.state.speech, { ...s.speech, reply: { kind: "none" } });
    }],
    ["quiet-close", logic => {
        assert.equal(logic.CONVERSATION_QUIET_MS, 30 * 60 * 1000);
        for (const engine of ["chained", "dictation", "duplex"]) {
            let s = listening(logic, false, engine, { sounds: true });
            const bound = s.quiet.deadline;
            const early = step(logic, s, callback("deadline", s.quiet, bound - 1));
            assert.equal(early.state.conversation.kind, "active");
            const r = step(logic, s, callback("deadline", s.quiet, bound));
            assert.deepEqual([r.state.conversation.kind, r.state.fault.kind, r.state.quiet.kind], ["ended", "none", "none"]);
            assert.equal(has(r, "capture-close"), true);
            assert.equal(has(r, "playback-start"), false, "quiet close awaits capture acknowledgment");
            const closed = step(logic, r.state, callback("capture-closed", r.state.capture, bound + 1));
            assert.equal(closed.state.playback.cue, "stop", "quiet close has normal closing cue");
            assert.equal(has(closed, "playback-start"), true);
            s = step(logic, closed.state, callback("played", closed.state.playback, bound + 2)).state;
            const repeated = step(logic, s, callback("deadline", r.state.quiet, bound + 3));
            assert.equal(has(repeated, "playback-start"), false, "one close has one cue");
            assert.equal(repeated.state.fault.kind, "none");
        }
    }],
    ["quiet-activity", logic => {
        const listeningState = listening(logic, false);
        for (const [type, text, resets] of [["partial", "heard", true], ["partial", "", false]]) {
            const r = step(logic, listeningState, callback(type, listeningState.turn, 1000, { text }));
            assert.equal(r.state.quiet.deadline, resets ? 1000 + 30 * 60 * 1000 : listeningState.quiet.deadline);
        }
        const cloud = duplexListening(logic, false);
        const rows = [
            [cloud, callback("transcript", cloud.speech, 1000, { role: "user", text: "heard", stage: "partial", rev: 1 }), true],
            [cloud, callback("input-silent", cloud.capture, 1000, { device: "fixture.mic" }), false],
            [cloud, snapshot({ at: 1000, engine: "duplex", settings: cloud.settings }), false],
            [cloud, callback("speech-idle", cloud.speech, 1000), false]
        ];
        for (const [s, e, resets] of rows) {
            const r = step(logic, s, e);
            assert.equal(r.state.quiet.deadline, resets ? 1000 + 30 * 60 * 1000 : s.quiet.deadline, e.type);
        }
        for (const s of [thinking(logic), acting(logic), held(logic), speaking(logic)]) {
            const kept = copy(s);
            // Isolate quiet expiry while each independent owner is still live.
            kept.quiet.deadline = 50;
            const r = step(logic, kept, callback("deadline", kept.quiet, 50));
            assert.equal(r.state.conversation.kind, "active", "work in flight is not quiet");
            assert.equal(r.state.quiet.deadline, 50 + 30 * 60 * 1000);
        }
        const said = step(logic, between(logic), event("say", 1000, { text: "typed" }));
        assert.equal(said.state.quiet.deadline, 1000 + 30 * 60 * 1000);
        const completed = thinking(logic);
        assert.equal(step(logic, completed, callback("brain-done", completed.turn, 1000)).state.quiet.deadline, 1000 + 30 * 60 * 1000,
            "a reply without playback finishes real work");
        const playedState = speaking(logic);
        assert.equal(step(logic, playedState, callback("played", playedState.playback, 1000)).state.quiet.deadline, 1000 + 30 * 60 * 1000);
        const tool = acting(logic);
        assert.equal(step(logic, tool, callback("tool-done", tool.action, 1000, { outcome: "completed" })).state.quiet.deadline, 1000 + 30 * 60 * 1000);
    }],
    ["digital-silence", logic => {
        const s = duplexListening(logic, false);
        const quiet = step(logic, s, callback("input-silent", s.capture, 30, { device: "fixture.mic" }));
        assert.deepEqual(quiet.state.sound, { kind: "silent", device: "fixture.mic" });
        assert.deepEqual([quiet.state.fault.kind, quiet.state.conversation.kind, quiet.state.capture.kind, quiet.state.quiet.deadline],
            ["none", "active", "open", s.quiet.deadline]);
        const loud = step(logic, quiet.state, callback("input-sound", s.capture, 31, { device: "fixture.mic" }));
        assert.deepEqual(loud.state.sound, { kind: "none" });
        const old = step(logic, quiet.state, callback("input-sound", { ...s.capture, op: s.capture.op + 1 }, 32, { device: "other" }));
        assert.deepEqual(old.state.sound, quiet.state.sound, "old capture cannot clear current observation");
        const ended = step(logic, quiet.state, event("toggle", 400));
        assert.deepEqual(ended.state.sound, { kind: "none" });
    }],
    ["collection-delay", logic => {
        let s = listening(logic);
        s = step(logic, s, event("talk-up", 610)).state;
        s = step(logic, s, callback("capture-closed", s.capture, 611)).state;
        assert.equal(s.turn.deadline, null, "closed capture has no guessed transcription deadline");
        const bound = 60000;
        const delayed = step(logic, s, callback("deadline", s.turn, bound));
        assert.deepEqual([delayed.state.turn.kind, delayed.state.turn.deadline, delayed.state.fault.kind, delayed.state.conversation.kind],
            ["collecting", null, "none", "active"], "recognizer delay neither invents empty input nor faults");
        const final = step(logic, delayed.state, callback("final", s.turn, bound + 1, { text: "late words" }));
        assert.equal(final.effects.find(e => e.kind === "brain-send").text, "late words");
    }],
    ["indicator-admission", logic => {
        for (const engine of ["chained", "dictation", "duplex"]) {
            const s = step(logic, logic.initial(), snapshot({ engine })).state;
            const demand = step(logic, s, event("talk-down"));
            assert.equal(logic.indicatorWanted(s), false);
            assert.equal(logic.indicatorWanted(demand.state), true);
            assert.equal(has(demand, "capture-open"), false);
            const shown = step(logic, demand.state, event("indicator", 11, { shown: true }));
            assert.equal(has(shown, "capture-open"), true);
            assert.equal(has(shown, "collect"), engine !== "duplex");
            const gone = step(logic, shown.state, event("indicator", 12, { shown: false }));
            assert.equal(gone.state.capture.kind, "closing");
            const ended = step(logic, gone.state, event("toggle", 400)).state;
            const closed = step(logic, ended, callback("capture-closed", ended.capture, 401));
            assert.equal(logic.indicatorWanted(closed.state), false);
        }
        for (const locked of [null, true, false]) {
            const s = step(logic, logic.initial(), snapshot({ locked, configured: false })).state;
            assert.equal(has(step(logic, s, event("talk-down")), "capture-open"), false);
        }
    }],
    ["half-duplex", logic => {
        let s = thinking(logic, false);
        s = step(logic, s, callback("capture-opened", s.capture, 32)).state;
        const reply = step(logic, s, callback("play", s.turn, 40, { interruptible: true }));
        assert.deepEqual([reply.state.capture.kind, reply.state.playback.admission.kind], ["closing", "waiting"]);
        assert.equal(has(reply, "playback-start"), false);
        const closed = step(logic, reply.state, callback("capture-closed", reply.state.capture, 41));
        assert.equal(has(closed, "playback-start"), true);
        assert.equal(closed.state.capture.kind, "closed");
        assert.equal(step(logic, closed.state, callback("played", closed.state.playback, 42)).state.capture.kind, "opening");
        s = duplexListening(logic);
        const waiting = step(logic, s, callback("speak", s.speech, 30));
        assert.deepEqual([waiting.state.speech.reply.kind, waiting.state.playback.kind], ["waiting", "idle"]);
        const released = step(logic, waiting.state, event("talk-up", 610));
        assert.equal(has(released, "playback-start"), false);
        assert.equal(has(step(logic, released.state, callback("capture-closed", released.state.capture, 611)), "playback-start"), true);
    }],
    ["echo-route-admission", logic => {
        for (const engine of ["chained", "dictation", "duplex"]) for (const echoCancel of [false, true]) {
            let s = listening(logic, false, engine);
            s = step(logic, s, snapshot({ at: 21, engine, settings: s.settings, echoCancel })).state;
            if (engine !== "duplex") {
                s = step(logic, s, callback("final", s.turn, 22, { text: "request" })).state;
                s = step(logic, s, callback("capture-closed", s.capture, 23)).state;
                s = step(logic, s, callback("capture-opened", s.capture, 24)).state;
            }
            const reply = step(logic, s, callback(engine === "duplex" ? "speak" : "play",
                engine === "duplex" ? s.speech : s.turn, 30, { interruptible: true }));
            const full = engine === "duplex" && echoCancel;
            assert.equal(reply.state.duplex.kind, full ? "full" : "half");
            assert.equal(reply.state.capture.kind, full ? "open" : "closing");
            assert.equal(has(reply, "playback-start"), full, engine + ": overlap requires judged cloud route");
            if (full) {
                assert.equal(reply.state.capture.op, s.capture.op, "reply retains the admitted recorder");
                assert.equal(logic.phaseOf(reply.state), "speaking");
            }
        }
    }],
    ["echo-route-loss", logic => {
        const s = echoListening(logic);
        const playing = step(logic, s, callback("speak", s.speech, 30)).state;
        for (const boundary of [snapshot({ at: 31, engine: "duplex", settings: s.settings, echoCancel: false }),
            snapshot({ at: 31, engine: "duplex", settings: s.settings, echoCancel: true, locked: true }),
            event("indicator", 31, { shown: false })]) {
            const lost = step(logic, playing, boundary);
            assert.equal(lost.state.capture.kind, "closing");
            assert.equal(has(lost, "capture-open"), false);
            const staleAck = step(logic, lost.state, callback("capture-closed", { ...lost.state.capture, op: s.capture.op }, 32));
            assert.equal(staleAck.state.capture.kind, "closing", "old recorder callback cannot release a newer close");
            const closed = step(logic, staleAck.state, callback("capture-closed", lost.state.capture, 33));
            assert.equal(closed.state.capture.kind, "closed");
        }
        let waiting = step(logic, playing, event("stop", 31)).state;
        const speech = waiting.speech;
        waiting = step(logic, waiting, callback("speak", speech, 32)).state;
        assert.equal(waiting.playback.kind, "flushing");
        const flushed = step(logic, waiting, callback("flushed", waiting.playback, 33));
        assert.equal(has(flushed, "playback-start"), false, "capture teardown still holds admission");
        const released = step(logic, flushed.state, callback("capture-closed", flushed.state.capture, 34));
        assert.equal(has(released, "playback-start"), true, "new output waits for both owned cleanup acknowledgments");
    }],
    ["echo-route-indicator", logic => {
        let s = step(logic, logic.initial(), snapshot({ engine: "duplex", echoCancel: true })).state;
        const requested = step(logic, s, event("talk-down"));
        assert.equal(has(requested, "capture-open"), false);
        const shown = step(logic, requested.state, event("indicator", 11, { shown: true }));
        assert.equal(has(shown, "capture-open"), true);
        s = step(logic, logic.initial(), snapshot({ engine: "duplex", echoCancel: true, settings: { sounds: true } })).state;
        s = step(logic, s, event("indicator", 1, { shown: true })).state;
        const cue = step(logic, s, event("talk-down", 10));
        assert.equal(cue.state.playback.kind, "feedback");
        assert.equal(cue.state.capture.kind, "closed", "conversation cues remain exclusive under EC");
        assert.equal(has(step(logic, cue.state, callback("played", cue.state.playback, 11)), "capture-open"), true);
    }],
    ["approval-identity", logic => {
        const h = held(logic);
        const s = step(logic, h, callback("shown", h.approval, 50, { id: h.approval.id })).state;
        for (const [extra, at, reason] of [
            [{ id: "other" }, 750, "identity"], [{ digest: "b".repeat(64) }, 750, "identity"],
            [{ gen: s.gen + 1 }, 750, "identity"], [{ source: "model" }, 750, "source"],
            [{}, 749, "early"], [{ source: "voice", beganAt: 1050, idleAt: 0 }, 1750, "voice-physical"]
        ]) {
            const r = confirm(logic, s, at, extra);
            assert.equal(r.effects.find(e => e.kind === "confirm-refused")?.reason, reason);
            assert.equal(has(r, "tool-start"), false);
            assert.equal(r.state.approval.kind, "held");
        }
        const accepted = confirm(logic, s, 750);
        assert.equal(accepted.state.action.kind, "running");
        assert.equal(accepted.effects.find(e => e.kind === "tool-start").confirmed, "key");
        assert.equal(has(step(logic, accepted.state, callback("confirm", s.approval, 751, { id: s.approval.id,
            digest: s.approval.digest, source: "key" })), "tool-start"), false, "confirmation is single use");
        assert.equal(step(logic, h, callback("shown", h.approval, 50, { id: "wrong" })).state.approval.shownAt, null);
        assert.equal(step(logic, h, callback("approval-cancel", h.approval, 50, { id: "wrong" })).state.approval.kind, "held");
        assert.equal(step(logic, h, callback("approval-cancel", h.approval, 50, { id: h.approval.id })).state.approval.kind, "none");
    }],
    ["approval-timing", logic => {
        let s = held(logic, false);
        s = step(logic, s, callback("shown", s.approval, 2500, { id: s.approval.id })).state;
        for (const extra of [{}, { beganAt: 2000, idleAt: 0 }, { beganAt: 3000, idleAt: 2001 }, { beganAt: 4500, idleAt: 0 }])
            assert.equal(confirm(logic, s, 4000, { source: "voice", ...extra }).effects.find(e => e.kind === "confirm-refused").reason, "voice-timing");
        assert.equal(confirm(logic, s, 4000, { source: "voice", beganAt: 3000, idleAt: 0 }).state.action.kind, "running");
        const expired = confirm(logic, s, s.approval.deadline);
        assert.equal(expired.effects.find(e => e.kind === "confirm-refused").reason, "expired");
        assert.equal(expired.state.fault.kind, "none");
        for (const purpose of ["action", "release"]) {
            const h = held(logic, false, purpose);
            const drawn = step(logic, h, callback("shown", h.approval, 50, { id: h.approval.id })).state;
            const r = confirm(logic, drawn, 750);
            assert.equal(has(r, purpose === "release" ? "release-confirmed" : "tool-start"), true);
            assert.equal(has(r, purpose === "release" ? "tool-start" : "release-confirmed"), false);
        }
    }],
    ["approval-answer-lifetime", logic => {
        for (const ending of ["confirm", "approval-cancel", "deadline", "stop"]) {
            const h = held(logic, false);
            let s = step(logic, h, event("talk-down", 50)).state;
            s = step(logic, s, callback("capture-opened", s.capture, 51)).state;
            s = step(logic, s, callback("shown", s.approval, 52, { id: h.approval.id })).state;
            const at = ending === "deadline" ? s.approval.deadline : 752;
            const r = ending === "confirm" ? confirm(logic, s, at) : ending === "stop" ? step(logic, s, event("stop", at))
                : step(logic, s, callback(ending, s.approval, at, { id: h.approval.id }));
            assert.equal(r.state.approval.kind, "none", ending);
            assert.equal(r.state.capture.kind, "closing", ending + " closes held answer recording");
            assert.equal(r.state.input.kind, "released");
        }
    }],
    ["approval-default-resume", logic => {
        for (const decision of ["confirm", "approval-cancel", "deadline"]) {
            let s = thinking(logic, false);
            s = step(logic, s, callback("approval", s.turn, 40, { id: "held", digest: "a".repeat(64), physical: false,
                text: "Fixture", tool: "fixture", timeoutMs: 100, cancellable: true })).state;
            s = step(logic, s, event("talk-down", 50)).state;
            s = step(logic, s, callback("capture-closed", s.capture, 51)).state;
            s = step(logic, s, callback("capture-opened", s.capture, 52)).state;
            s = step(logic, s, callback("shown", s.approval, 53, { id: s.approval.id })).state;
            const at = decision === "deadline" ? s.approval.deadline : 753;
            const r = decision === "confirm" ? confirm(logic, s, at)
                : step(logic, s, callback(decision, s.approval, at, { id: s.approval.id }));
            assert.equal(r.state.input.kind, "conversation", decision + ": default Talk keeps listening demand");
            assert.equal(r.state.capture.kind, "closing", decision + ": old answer capture closes");
            const next = step(logic, r.state, callback("capture-closed", r.state.capture, at + 1));
            assert.equal(next.state.capture.kind, "opening", decision + ": default resumes after acknowledgment");
            assert.equal(next.state.conversation.kind, "active");
        }
    }],
    ["tool-lifetime", logic => {
        for (const cancellable of [false, true]) for (const outcome of ["completed", "failed", "unknown"]) {
            const s = acting(logic, cancellable);
            assert.equal(has(step(logic, s, event("interrupt", 50)), "tool-cancel"), false);
            const stopped = step(logic, s, event("stop", 50));
            assert.equal(has(stopped, "tool-cancel"), cancellable);
            assert.equal(has(step(logic, stopped.state, event("stop", 51)), "tool-cancel"), false, "cancel requested once");
            const r = step(logic, stopped.state, callback("tool-done", s.action, 52, { outcome }));
            const result = r.effects.find(e => e.kind === "tool-outcome");
            assert.deepEqual([result.outcome, result.source, result.target, result.gen], [outcome, s.action.op, s.action.brain, s.action.gen]);
            assert.equal(r.state.action.kind, "none");
            assert.equal(r.state.gen, s.gen);
        }
        for (const s of [acting(logic), held(logic)])
            assert.equal(has(step(logic, s, callback("tool", s.turn, 50, { tool: "second", timeoutMs: 100, cancellable: true })), "tool-start"), false);
    }],
    ["tool-deadline", logic => {
        const s = acting(logic);
        assert.equal(has(step(logic, s, callback("deadline", s.action, 139)), "tool-outcome"), false);
        const expired = step(logic, s, callback("deadline", s.action, 140));
        assert.deepEqual([expired.state.action.kind, expired.state.action.limit.kind], ["running", "expired"]);
        assert.equal(expired.effects.find(e => e.kind === "tool-outcome").outcome, "unknown");
        assert.equal(has(step(logic, expired.state, callback("deadline", s.action, 141)), "tool-outcome"), false);
        const long = step(logic, thinking(logic), callback("tool", thinking(logic).turn, 40, { tool: "fixture", timeoutMs: 120000, cancellable: true })).state;
        assert.equal(long.turn.deadline, 180040);
        const done = step(logic, long, callback("tool-done", long.action, 50000, { outcome: "completed" })).state;
        assert.equal(done.turn.deadline, 110000);
        assert.equal(step(logic, done, callback("deadline", done.turn, 110000)).state.fault.reason, "thinking-timeout");
    }],
    ["brain-lifetime", logic => {
        const first = thinking(logic);
        let s = step(logic, first, callback("brain-done", first.turn, 40)).state;
        assert.deepEqual(s.brain, first.brain);
        s = step(logic, s, event("talk-down", 50)).state;
        s = step(logic, s, callback("capture-opened", s.capture, 51)).state;
        const next = step(logic, s, callback("final", s.turn, 52, { text: "next" }));
        assert.notEqual(next.state.turn.op, first.turn.op);
        assert.equal(next.effects.find(e => e.kind === "brain-send").owner, first.brain.op);
        for (const e of [event("toggle", 400), event("lease-ended", 400), snapshot({ at: 400, settings: { ...first.settings, model: "changed" } })]) {
            const completed = step(logic, first, callback("brain-done", first.turn, 40)).state;
            const closed = step(logic, completed, e);
            assert.equal(closed.effects.find(effect => effect.kind === "brain-close").target, first.brain.op);
            assert.equal(has(step(logic, closed.state, e), "brain-close"), false);
        }
    }],
    ["cancel-and-lease", logic => {
        const s = thinking(logic);
        const cancelled = step(logic, s, event("cancel", 100));
        assert.equal(cancelled.state.turn.deadline, 2100);
        const ack = step(logic, cancelled.state, callback("cancelled", cancelled.state.turn, 200));
        assert.deepEqual(ack.state.brain, s.brain, "live cancellation retains brain");
        const timeout = step(logic, cancelled.state, callback("deadline", cancelled.state.turn, 2100));
        assert.equal(timeout.state.brain.kind, "closed");
        const lease = step(logic, s, event("lease-ended", 100));
        assert.deepEqual([lease.state.conversation.kind, lease.state.turn.kind, lease.state.brain.kind], ["ended", "none", "closed"]);
        assert.equal(has(lease, "brain-cancel"), true);
        const cloud = duplexListening(logic);
        assert.equal(step(logic, cloud, event("lease-ended", 100)).effects.find(e => e.kind === "speech-close").mode, "abort");
    }],
    ["stale-callbacks", logic => {
        const s = listening(logic);
        for (const extra of [{ op: s.turn.op + 1 }, { gen: s.turn.gen + 1 }]) {
            const r = step(logic, s, callback("partial", s.turn, 21, { text: "old", ...extra }));
            assert.deepEqual([r.state.turn.partial, r.state.stale, r.effects], ["", s.stale + 1, []]);
        }
        for (const before of [thinking(logic), speaking(logic), duplexListening(logic)]) {
            const r = step(logic, before, event("toggle", 400));
            const callbacks = before.engine.kind === "duplex" ? ["speak", "speech-due", "transcript", "speech-idle", "speech-failed", "delegation", "speech-input-ended"]
                : ["brain-done", "brain-failed", "play", "transcript"];
            for (const type of callbacks) {
                const late = step(logic, r.state, callback(type, before.engine.kind === "duplex" ? before.speech : before.turn, 401,
                    { text: "late", role: "assistant", stage: "partial", rev: 1, due: true, empty: true, capture: 1, reason: "failed", id: "old" }));
                assert.equal(late.state.stale, r.state.stale + 1, type);
                assert.equal(has(late, "capture-open") || has(late, "playback-start") || has(late, "brain-send"), false, type);
            }
        }
        const h = listening(logic);
        let r = step(logic, h, event("talk-up", 610)).state;
        r = step(logic, r, callback("capture-closed", r.capture, 611)).state;
        r = step(logic, r, event("talk-down", 612)).state;
        const late = step(logic, r, callback("final", h.turn, 613, { text: "old recording" }));
        assert.equal(has(late, "brain-send"), false);
        assert.deepEqual(late.state.capture, r.capture);
    }],
    ["faults-and-recovery", logic => {
        const s = thinking(logic);
        const late = step(logic, s, callback("brain-done", s.turn, s.turn.deadline));
        assert.deepEqual([late.state.turn.kind, late.state.fault.reason, late.state.stale], ["cancelling", "thinking-timeout", s.stale + 1]);
        const failed = step(logic, s, callback("brain-failed", s.turn, 40, { reason: "brain=failed" })).state;
        assert.equal(failed.fault.reason, "brain=failed");
        const recovered = step(logic, failed, event("talk-down", 400));
        assert.deepEqual([recovered.state.fault.kind, recovered.state.conversation.kind, recovered.state.capture.kind], ["none", "active", "opening"]);
        assert.ok(recovered.state.gen > failed.gen);
        const cloud = duplexListening(logic);
        const error = step(logic, cloud, callback("speech-failed", cloud.speech, 40, { reason: "live=failed" }));
        assert.deepEqual([error.state.fault.reason, error.state.speech.kind, error.state.conversation.kind], ["live=failed", "closed", "ended"]);
        const playing = speaking(logic);
        const failedPlayback = step(logic, playing, callback("playback-failed", playing.playback, 50, { reason: "playback=failed" }));
        assert.deepEqual([failedPlayback.state.fault.reason, failedPlayback.state.playback.kind], ["playback=failed", "flushing"]);
        const done = step(logic, playing, callback("brain-done", playing.turn, 100)).state;
        assert.equal(done.playback.deadline, 300100);
        assert.equal(step(logic, done, callback("deadline", done.playback, 300100)).state.fault.reason, "playback-timeout");
    }],
    ["collect-failed", logic => {
        let s = listening(logic);
        s = step(logic, s, event("talk-up", 610)).state;
        s = step(logic, s, callback("capture-closed", s.capture, 611)).state;
        const failed = step(logic, s, callback("collect-failed", s.turn, 612, { reason: "speech=failed" }));
        assert.deepEqual([failed.state.turn.kind, failed.state.conversation.kind, failed.state.fault.reason], ["none", "ended", "speech=failed"]);
        const late = step(logic, failed.state, callback("collect-failed", s.turn, 613, { reason: "late" }));
        assert.equal(late.state.stale, failed.state.stale + 1);
        assert.equal(late.state.fault.reason, "speech=failed");
    }],
    ["phase-priority", logic => {
        for (const [s, expected] of [[ready(logic), "idle"], [listening(logic), "listening"], [thinking(logic), "thinking"],
            [speaking(logic), "speaking"], [held(logic), "confirming"], [acting(logic), "acting"], [logic.initial(), "down"]])
            assert.equal(logic.phaseOf(s), expected);
        const s = speaking(logic);
        const failed = step(logic, s, callback("playback-failed", s.playback, 50, { reason: "failed" })).state;
        assert.equal(logic.phaseOf(failed), "error");
    }],
    ["fault-stop", logic => {
        for (const holdToTalk of [false, true]) for (const attempts of [1, 4]) {
            let s = listening(logic, holdToTalk);
            for (let n = 0; n < attempts; n++) {
                s = step(logic, s, callback("capture-failed", s.capture, 50 + n * 2, { reason: LOST })).state;
                if (n + 1 < attempts) s = step(logic, s, callback("capture-closed", s.capture, 51 + n * 2)).state;
            }
            assert.equal(s.fault.kind, attempts === 1 ? "retrying" : "error");
            const old = s.capture;
            s = step(logic, s, event("stop", 100)).state;
            s = step(logic, s, callback("capture-closed", s.capture, 101)).state;
            for (const e of [event("cancel", 102), event("indicator", 103, { shown: false }),
                snapshot({ at: 104, settings: s.settings }), callback("capture-failed", old, 105, { reason: LOST })]) {
                const r = step(logic, s, e);
                assert.equal(r.state.input.kind, "stopped", "teardown preserves the pause");
                assert.equal(has(r, "capture-open"), false);
                s = r.state;
            }
            assert.equal(s.fault.kind, "none");
            assert.equal(s.capture.kind, "closed");
            assert.equal(step(logic, s, event("talk-down", 500)).state.conversation.kind, "active");
        }
    }],
    ["device-retries", logic => {
        let s = listening(logic);
        for (let n = 0; n < 4; n++) {
            const r = step(logic, s, callback("capture-failed", s.capture, 50 + n * 2, { reason: LOST }));
            assert.equal(r.state.fault.kind, n < 3 ? "retrying" : "error");
            assert.equal(r.state.fault.retry, Math.min(n + 1, 3));
            s = step(logic, r.state, callback("capture-closed", r.state.capture, 51 + n * 2)).state;
            assert.equal(s.capture.kind, n < 3 ? "opening" : "closed");
        }
        const selected = step(logic, s, snapshot({ at: 100, settings: { ...s.settings, microphone: "replacement" } }));
        assert.deepEqual([selected.state.fault.kind, selected.state.capture.kind, selected.state.gen], ["none", "opening", s.gen]);
    }],
    ["voice-check", logic => {
        let s = step(logic, logic.initial(), snapshot({ configured: false, checkReady: true, checkSource: "mic-a" })).state;
        assert.equal(logic.canCheck(s), true);
        s = step(logic, s, event("voice-check", 10)).state;
        assert.equal(logic.indicatorWanted(s), true);
        assert.equal(s.capture.kind, "closed");
        s = step(logic, s, event("indicator", 11, { shown: true })).state;
        s = step(logic, s, callback("capture-opened", s.capture, 20)).state;
        assert.equal(s.check.deadline, 3020);
        assert.equal(s.turn.kind, "none", "check opens no brain turn");
        const finishing = step(logic, s, callback("deadline", s.check, 3020)).state;
        for (const result of ["ready", "silent", "not-heard"]) {
            const checked = step(logic, finishing, callback("voice-checked", finishing.check, 3021, { result })).state;
            assert.deepEqual(checked.check, { kind: "done", result, device: "mic-a" });
            const cloud = step(logic, checked, snapshot({ at: 3022, configured: false, checkReady: false, checkSource: "mic-a" })).state;
            assert.deepEqual(cloud.check, { kind: "kept", result, device: "mic-a" });
            const echo = step(logic, checked, snapshot({ at: 3022, engine: "duplex", echoCancel: true,
                configured: false, checkReady: false, checkSource: "jarvis_ec_source" })).state;
            assert.equal(echo.check.kind, "unavailable", "the old physical check cannot claim the EC source was checked");
            assert.equal(echo.checkSource, "jarvis_ec_source");
            const moved = step(logic, checked, snapshot({ at: 3022, configured: false, checkReady: true, checkSource: "mic-b" })).state;
            assert.equal(moved.check.kind, "again");
        }
        for (const e of [event("stop", 30), event("cancel", 30), event("interrupt", 30), event("lease-ended", 30),
            event("indicator", 30, { shown: false }), snapshot({ at: 30, locked: true, checkReady: true })]) {
            const r = step(logic, s, e);
            assert.equal(r.state.capture.kind, "closing");
            assert.equal(["waiting", "recording", "finishing"].includes(r.state.check.kind), false);
        }
        const moved = step(logic, s, snapshot({ at: 30, configured: false, checkReady: true, checkSource: "mic-b" })).state;
        assert.equal(moved.check.kind, "again");
        const failed = step(logic, finishing, callback("voice-check-failed", finishing.check, 3021, { reason: "speech=failed" })).state;
        assert.deepEqual(failed.check, { kind: "failed", reason: "speech=failed", device: "mic-a" });
        assert.equal(failed.fault.kind, "none");
        assert.equal(logic.canCheck(failed), true);
        for (const owner of [step(logic, logic.initial(), snapshot({ configured: false, checkReady: true, checkSource: "mic-a" })).state,
            finishing]) {
            const waiting = owner.check.kind === "ready" ? step(logic, owner, event("voice-check", 10)).state : owner;
            const timed = step(logic, waiting, callback("deadline", waiting.check, waiting.check.deadline));
            assert.deepEqual(timed.state.check, { kind: "failed", reason: "check-timeout", device: "mic-a" });
            assert.equal(timed.state.fault.kind, "none");
        }
    }],
    ["text-and-captions", logic => {
        const s = listening(logic);
        const partial = step(logic, s, callback("partial", s.turn, 21, { text: "draft" }));
        assert.equal(has(partial, "brain-send"), false);
        const final = step(logic, partial.state, callback("final", s.turn, 22, { text: "final words" }));
        const caption = final.effects.find(e => e.kind === "transcript");
        assert.deepEqual([caption.role, caption.stage, caption.text, caption.rev], ["user", "final", "final words", s.turn.op]);
        assert.ok(kinds(final).indexOf("transcript") < kinds(final).indexOf("brain-send"));
        const turn = thinking(logic);
        const words = { role: "assistant", text: "Reply", stage: "partial", rev: 1 };
        const captioned = step(logic, turn, callback("transcript", turn.turn, 40, words));
        assert.equal(captioned.effects.find(e => e.kind === "transcript").text, "Reply");
        assert.equal(has(step(logic, turn, callback("transcript", turn.turn, 40, { ...words, role: "user" })), "transcript"), false);
        const finished = step(logic, turn, callback("brain-done", turn.turn, 41)).state;
        assert.equal(has(step(logic, finished, callback("transcript", turn.turn, 42, words)), "transcript"), false);
        const typed = step(logic, ready(logic), event("say", 20, { text: "typed words" }));
        assert.equal(typed.state.conversation.kind, "active");
        assert.equal(typed.effects.find(e => e.kind === "brain-send").text, "typed words");
        assert.equal(typed.state.capture.kind, "closed");
        for (const [text, expected] of [["line\nfeed", "line feed"], ["x".repeat(4097), "x".repeat(4096)]])
            assert.equal(step(logic, s, callback("final", s.turn, 22, { text })).effects.find(e => e.kind === "transcript").text, expected);
        assert.equal(has(step(logic, s, callback("final", s.turn, 22, { text: "" })), "transcript"), false);
        for (const [state, reason] of [[logic.initial(), "down"], [ready(logic, {}, "duplex"), "duplex"], [held(logic), "held"],
            [speaking(logic), "speaking"], [thinking(logic), "busy"], [acting(logic), "busy"]]) {
            assert.equal(logic.sayRefusal(state), reason);
            assert.equal(has(step(logic, state, event("say", 50, { text: "typed" })), "brain-send"), false);
        }
    }],
    ["preview-and-relay", logic => {
        for (const s of [ready(logic), between(logic)]) {
            const preview = step(logic, s, event("preview", 50, { voice: "VoiceA" }));
            assert.equal(preview.effects.find(e => e.kind === "brain-send").preview, true);
            assert.equal(has(preview, "transcript") || has(preview, "capture-open"), false);
            assert.deepEqual(preview.state.conversation, { kind: "active", purpose: s.conversation.kind === "ended" ? "preview" : "conversation" });
        }
        const cloud = step(logic, ready(logic, {}, "duplex"), event("preview", 50, { voice: "marin" }));
        assert.equal(cloud.effects.find(e => e.kind === "speech-open").voice, "marin");
        assert.equal(has(cloud, "capture-open"), false);
        const s = between(logic);
        const ask = { task: "t1", prompt: "p1", kind: "question" };
        const relay = step(logic, s, event("relay", 50, { text: "Question", ask }));
        assert.deepEqual(relay.effects.find(e => e.kind === "brain-send").relay, { text: "Question", ask });
        assert.equal(relay.effects.find(e => e.kind === "brain-send").owner, s.brain.op);
        assert.equal(has(relay, "transcript"), false);
        for (const busy of [listening(logic), thinking(logic), speaking(logic), held(logic), acting(logic)]) {
            assert.equal(logic.previewRefusal(busy), "busy");
            assert.equal(has(step(logic, busy, event("preview", 50, { voice: "VoiceA" })), "brain-send"), false);
            assert.equal(logic.relayRefusal(busy), "busy");
        }
    }],
    ["preview-native-completion", logic => {
        let r = step(logic, ready(logic, { sounds: true }, "duplex"), event("preview", 50, { voice: "marin" }));
        assert.deepEqual(r.state.conversation, { kind: "active", purpose: "preview" });
        assert.equal(has(r, "capture-open") || has(r, "playback-start"), false);
        const speech = copy(r.state.speech);
        r = step(logic, r.state, callback("speak", speech, 51));
        assert.equal(r.state.playback.kind, "playing");
        r = step(logic, r.state, callback("played", r.state.playback, 52));
        assert.equal(r.state.conversation.purpose, "preview", "native played precedes its own preview idle report");
        r = step(logic, r.state, callback("speech-idle", speech, 53));
        assert.deepEqual([r.state.conversation.kind, r.state.speech.kind, r.state.capture.kind, r.state.cue.kind, r.state.playback.kind],
            ["ended", "closed", "closed", "none", "idle"], "native preview completes without capture or conversation cue");
        assert.equal(r.effects.find(e => e.kind === "speech-close")?.target, speech.op);
        assert.equal(has(r, "capture-open") || has(r, "playback-start"), false);
        const late = step(logic, r.state, callback("speech-idle", speech, 54));
        assert.equal(late.state.stale, r.state.stale + 1);
        assert.equal(has(late, "capture-open") || has(late, "playback-start"), false);
    }],
    ["preview-chained-completion", logic => {
        for (const engine of ["chained", "dictation"]) for (const order of ["brain-first", "played-first"]) {
            let s = ready(logic, { sounds: true }, engine);
            s = step(logic, s, event("preview", 50, { voice: "VoiceA" })).state;
            assert.equal(s.conversation.purpose, "preview");
            const brain = copy(s.turn);
            s = step(logic, s, callback("play", brain, 51, { interruptible: true })).state;
            const playback = copy(s.playback);
            const first = order === "brain-first" ? callback("brain-done", brain, 52) : callback("played", playback, 52);
            const second = order === "brain-first" ? callback("played", playback, 53) : callback("brain-done", brain, 53);
            s = step(logic, s, first).state;
            assert.equal(s.conversation.kind, "active", "temporary preview waits for turn and playback completion");
            const done = step(logic, s, second);
            assert.deepEqual([done.state.conversation.kind, done.state.brain.kind, done.state.capture.kind, done.state.cue.kind, done.state.playback.kind],
                ["ended", "closed", "closed", "none", "idle"]);
            assert.equal(has(done, "capture-open") || has(done, "playback-start"), false);
        }
        let s = between(logic);
        const original = copy(s.conversation), gen = s.gen;
        s = step(logic, s, event("preview", 50, { voice: "VoiceA" })).state;
        s = step(logic, s, callback("play", s.turn, 51, { interruptible: true })).state;
        s = step(logic, s, callback("brain-done", s.turn, 52)).state;
        const done = step(logic, s, callback("played", s.playback, 53));
        assert.deepEqual(done.state.conversation, original, "preview inside real chained conversation keeps that conversation");
        assert.equal(done.state.gen, gen);
        assert.equal(done.state.brain.kind, "acquired");
    }],
    ["preview-stop", logic => {
        for (const engine of ["chained", "dictation", "duplex"]) for (const playing of [false, true]) {
            let s = step(logic, ready(logic, { sounds: true }, engine), event("preview", 50, { voice: "VoiceA" })).state;
            const oldSpeech = copy(s.speech);
            if (playing) s = engine === "duplex" ? step(logic, s, callback("speak", s.speech, 51)).state
                : step(logic, s, callback("play", s.turn, 51, { interruptible: true })).state;
            const stopped = step(logic, s, event("stop", 52));
            assert.deepEqual([stopped.state.conversation.kind, stopped.state.capture.kind, stopped.state.speech.kind, stopped.state.cue.kind],
                ["ended", "closed", "closed", "none"], "Stop closes only the temporary preview lifetime");
            assert.equal(has(stopped, "capture-open") || has(stopped, "playback-start"), false);
            let after = stopped.state;
            if (after.playback.kind === "flushing") after = step(logic, after, callback("flushed", after.playback, 53)).state;
            if (after.turn.kind === "cancelling") after = step(logic, after, callback("cancelled", after.turn, 54)).state;
            const settled = step(logic, after, event("indicator", 55, { shown: true }));
            assert.deepEqual([settled.state.conversation.kind, settled.state.capture.kind, settled.state.cue.kind, settled.state.playback.kind],
                ["ended", "closed", "none", "idle"], "preview cleanup leaves no orphan cue or microphone");
            assert.equal(has(settled, "capture-open") || has(settled, "playback-start"), false);
            if (engine === "duplex") assert.equal(step(logic, settled.state, callback("speech-idle", oldSpeech, 56)).state.stale, settled.state.stale + 1);
        }
    }],
    ["preview-talk-promotion", logic => {
        for (const holdToTalk of [false, true]) {
            let s = step(logic, ready(logic, { sounds: true, holdToTalk }, "duplex"), event("preview", 50, { voice: "marin" })).state;
            const oldSpeech = copy(s.speech), gen = s.gen;
            s = step(logic, s, callback("speak", oldSpeech, 51)).state;
            const promoted = step(logic, s, event("talk-down", 100));
            assert.deepEqual(promoted.state.conversation, { kind: "active", purpose: "conversation" });
            assert.equal(promoted.state.gen, gen);
            assert.equal(promoted.effects.find(e => e.kind === "speech-close")?.target, oldSpeech.op);
            assert.equal(promoted.state.cue.cue, "start");
            assert.equal(has(promoted, "capture-open"), false, "promotion waits for old preview playback cleanup");
            s = step(logic, promoted.state, callback("flushed", promoted.state.playback, 101)).state;
            assert.equal(s.playback.cue, "start");
            const admitted = step(logic, s, callback("played", s.playback, 102));
            s = admitted.state;
            assert.equal(has(admitted, "capture-open"), true);
            assert.equal(s.speech.kind, "open");
            assert.notEqual(s.speech.op, oldSpeech.op, "real conversation takes its own speech owner");
            const stale = step(logic, s, callback("speech-idle", oldSpeech, 103));
            assert.deepEqual(stale.state.conversation, { kind: "active", purpose: "conversation" });
            assert.equal(stale.state.stale, s.stale + 1);
            assert.equal(has(stale, "speech-close") || has(stale, "playback-start"), false);
        }
    }],
    ["preview-typed-promotion", logic => {
        let s = step(logic, ready(logic, { sounds: true }), event("preview", 50, { voice: "VoiceA" })).state;
        s = step(logic, s, callback("play", s.turn, 51, { interruptible: true })).state;
        s = step(logic, s, callback("brain-done", s.turn, 52)).state;
        const gen = s.gen;
        assert.equal(logic.sayRefusal(s), null);
        const promoted = step(logic, s, event("say", 100, { text: "typed request" }));
        assert.deepEqual(promoted.state.conversation, { kind: "active", purpose: "conversation" });
        assert.equal(promoted.state.gen, gen);
        assert.equal(promoted.effects.find(e => e.kind === "brain-send")?.text, "typed request");
        assert.equal(promoted.state.playback.kind, "flushing");
        assert.equal(promoted.state.cue.cue, "start");
        s = step(logic, promoted.state, callback("flushed", promoted.state.playback, 101)).state;
        assert.equal(s.playback.cue, "start");
        s = step(logic, s, callback("played", s.playback, 102)).state;
        assert.deepEqual([s.conversation.purpose, s.turn.kind, s.capture.kind, s.cue.kind], ["conversation", "thinking", "closed", "none"]);
    }],
    ["voice-mute-and-cues", logic => {
        const s = speaking(logic);
        const muted = step(logic, s, event("voice-mute-toggle", 41));
        assert.deepEqual(muted.state.voiceMute, { kind: "on" });
        assert.deepEqual(muted.effects.map(e => [e.kind, e.muted]), [["voice-mute-store", true]]);
        assert.deepEqual({ ...muted.state, voiceMute: s.voiceMute, nextOp: s.nextOp }, s);
        assert.deepEqual(step(logic, logic.initial(), event("voice-mute", 1)).effects, []);
        for (const engine of ["chained", "dictation", "duplex"]) for (const sounds of [true, false]) {
            let s = ready(logic, { sounds, holdToTalk: false }, engine);
            s = step(logic, s, event("voice-mute", 2)).state;
            const started = step(logic, s, event("talk-down", 10));
            s = started.state;
            if (sounds) {
                assert.equal(s.playback.cue, "start");
                assert.equal(has(started, "capture-open"), false);
                s = step(logic, s, callback("played", s.playback, 11)).state;
            } else assert.equal(s.playback.kind, "idle");
            s = step(logic, s, callback("capture-opened", s.capture, 12)).state;
            const closing = step(logic, s, event("talk-down", 400));
            assert.equal(closing.state.conversation.kind, "ended");
            assert.equal(has(closing, "playback-start"), false);
            const closed = step(logic, closing.state, callback("capture-closed", closing.state.capture, 401));
            assert.equal(closed.state.voiceMute.kind, "on");
            assert.equal(closed.state.playback.kind, sounds ? "feedback" : "idle");
            if (sounds) {
                assert.equal(closed.state.playback.cue, "stop");
                const failed = step(logic, closed.state, callback("playback-failed", closed.state.playback, 402, { reason: "playback=failed" }));
                assert.deepEqual([failed.state.conversation.kind, failed.state.fault.kind, failed.state.playback.kind], ["ended", "none", "idle"]);
            }
        }
    }],
    ["cue-cleanup", logic => {
        const started = startCue(logic).state;
        const ending = step(logic, started, event("talk-down", 400));
        assert.equal(ending.state.playback.kind, "flushing");
        assert.equal(ending.state.cue.cue, "stop");
        const late = step(logic, ending.state, callback("played", started.playback, 401));
        assert.equal(has(late, "capture-open") || has(late, "playback-start"), false);
        const flushed = step(logic, ending.state, callback("flushed", ending.state.playback, 402));
        assert.equal(flushed.state.playback.cue, "stop");
        assert.equal(has(flushed, "playback-start"), true);
        const stopped = step(logic, started, event("stop", 11));
        assert.equal(stopped.state.cue.kind, "none", "Stop emits no conversation closing sound");
        const noCue = step(logic, stopped.state, callback("flushed", stopped.state.playback, 12));
        assert.equal(has(noCue, "playback-start"), false);
    }],
    ["feedback-reply-ownership", logic => {
        let working = thinking(logic);
        working = step(logic, working, snapshot({ at: 35, settings: { ...working.settings, sounds: true } })).state;
        working = step(logic, working, callback("feedback", working.turn, 40)).state;
        const speech = step(logic, working, callback("play", working.turn, 41, { interruptible: true }));
        assert.equal(speech.state.playback.op, working.playback.op, "working tone hands its player to reply");
        assert.equal(has(speech, "playback-start"), false);
        const line = lineReply(logic);
        assert.equal(line.playback.reply.kind, "waiting");
        assert.equal(logic.phaseOf(line), "speaking");
        const reply = step(logic, line, callback("played", line.playback, 43));
        assert.equal(reply.state.playback.kind, "playing");
        assert.equal(reply.state.playback.source, line.turn.op);
        for (const done of [false, true]) {
            let s = pendingReply(logic);
            assert.equal(s.playback.reply.kind, "waiting");
            if (done) s = step(logic, s, callback("brain-done", s.turn, 43)).state;
            const r = step(logic, s, callback("flushed", s.playback, 44));
            assert.equal(r.state.playback.kind, "playing");
            assert.equal(r.state.playback.deadline, done ? 300043 : null);
            for (const type of ["stop", "cancel", "interrupt", "lease-ended"]) {
                const cancelled = step(logic, s, event(type, 44)).state;
                const ack = step(logic, cancelled, callback("flushed", cancelled.playback, 45));
                assert.equal(has(ack, "playback-start"), false, type + " drops pending speech");
            }
        }
    }],
    ["duplex-owner", logic => {
        const s = duplexListening(logic);
        const first = step(logic, s, callback("delegation", s.speech, 30, { id: "old", text: "first" }));
        const next = step(logic, first.state, callback("delegation", s.speech, 31, { id: "new", text: "second" }));
        assert.equal(next.effects.find(e => e.kind === "brain-send").owner, first.state.brain.op);
        assert.equal(has(next, "brain-cancel"), true);
        assert.equal(next.state.speech.op, s.speech.op);
        assert.equal(step(logic, next.state, callback("brain-done", first.state.turn, 32)).state.stale, next.state.stale + 1);
        const due = step(logic, duplexThinking(logic), callback("speech-due", duplexThinking(logic).speech, 620, { due: true })).state;
        assert.equal(logic.phaseOf(due), "speaking");
        const stopped = step(logic, due, event("stop", 621));
        assert.equal(stopped.state.speech.reply.kind, "none");
        assert.equal(stopped.state.conversation.kind, "active");
        assert.equal(stopped.state.speech.kind, "open");
        assert.equal(step(logic, due, callback("speech-idle", due.speech, 622)).state.speech.reply.kind, "due", "provider idle cannot invent reply completion");
    }],
    ["retired-inputs", logic => {
        for (const type of ["mute", "unmute", "mute-toggle", "wake"])
            assert.throws(() => logic.reduce(logic.initial(), event(type)), /session=event/);
        for (const key of ["mute", "followUp"]) {
            const s = copy(logic.initial());
            s[key] = { kind: "off" };
            assert.equal(logic.validate(s), false, key + " has no live state reader");
        }
        for (const kind of ["armed", "woken", "follow-up", "tapped"]) {
            const s = copy(logic.initial()); s.input = { kind };
            assert.equal(logic.validate(s), false);
        }
        assert.equal(logic.sayRefusal(ready(logic)), null, "typed input has no microphone privacy gate");
    }],
    ["invalid-inputs", logic => {
        for (const at of [-1, NaN, Infinity]) assert.throws(() => logic.reduce(logic.initial(), event("stop", at)), /session=clock/);
        const s = thinking(logic);
        for (const timeoutMs of [0, -1, Infinity, null, "120"])
            assert.throws(() => logic.reduce(s, callback("tool", s.turn, 40, { tool: "fixture", timeoutMs, cancellable: true })), /session=tool-deadline/);
        assert.throws(() => logic.reduce(acting(logic), callback("tool-done", acting(logic).action, 50, { outcome: "finished" })), /session=tool-outcome/);
        assert.throws(() => logic.reduce(ready(logic), snapshot({ engine: undefined })), /session=engine/);
    }]
];

for (const key of ["holdToTalk", "voiceProvider", "voice", "clonedVoice", "language", "brain", "model", "effort", "fallbacks", "customBaseUrl", "home", "policy", "cloudVision", "account", "voiceAccount"])
    table.push(["settings-" + key, logic => {
        const s = held(logic);
        const value = key === "holdToTalk" ? false : key === "fallbacks" ? [{ brain: "changed" }] : "changed";
        const r = step(logic, s, snapshot({ at: 50, settings: { ...s.settings, [key]: value } }));
        assert.deepEqual([r.state.gen, r.state.conversation.kind, r.state.approval.kind], [s.gen + 1, "ended", "none"]);
        assert.equal(r.effects.find(e => e.kind === "approval-ended").target, s.approval.op);
    }]);

const shapeCases = [
    ["extra-state", logic => copy(logic.initial()), s => { s.extra = 1; }],
    ["counter", thinking, s => { s.stale = 0.5; }],
    ["settings", thinking, s => { s.settings = []; }],
    ["owner", thinking, s => { s.turn.op = 0; }],
    ["deadline", thinking, s => { s.turn.deadline = -1; }],
    ["capture-mode", listening, s => { s.capture.mode = "armed"; }],
    ["quiet-deadline", listening, s => { s.quiet.deadline = -1; }],
    ["silent-device", listening, s => { s.sound = { kind: "silent", device: "" }; }],
    ["closing-tap", listening, s => { s.input = { kind: "closing-tap", source: 0 }; }],
    ["held-heard", listening, s => { s.input.heard = "true"; }],
    ["held-missing-heard", listening, s => { delete s.input.heard; }],
    ["conversation-purpose", listening, s => { s.conversation.purpose = "unknown"; }],
    ["conversation-missing-purpose", listening, s => { delete s.conversation.purpose; }],
    ["history-epoch", listening, s => { s.history.epoch = -1; }],
    ["history-reset-reason", listening, s => { s.history = { kind: "reset", epoch: 1, reason: "unknown" }; }],
    ["history-reset-missing-reason", listening, s => { s.history = { kind: "reset", epoch: 1 }; }],
    ["speech-provisional-preview", duplexListening, s => { s.speech.preview = true; }],
    ["playback-admission", speaking, s => { s.playback.admission = { kind: "unknown" }; }],
    ["tool-cancel", acting, s => { s.action.cancellation = { kind: "unknown" }; }],
    ["tool-limit", acting, s => { s.action.limit = { kind: "pending", deadline: -1 }; }],
    ["reply-source", pendingReply, s => { s.playback.reply.source = 0; }],
    ["reply-shape", pendingReply, s => { s.playback.reply.extra = true; }],
    ["echo", listening, s => { s.duplex = { kind: "echo" }; }],
    ["hidden-shape", listening, s => { s.visibility = { kind: "hidden", saved: true }; }],
    ["bar-indicator-shape", listening, s => { s.barIndicator = { kind: "configured" }; }],
    ["bar-indicator-generation", listening, s => { s.barIndicator = { kind: "present", gen: -1 }; }]
];
for (const [name, seed, mutate] of shapeCases) table.push(["wire-" + name, logic => {
    const s = seed(logic);
    assert.equal(logic.validate(s), true, name + " positive");
    mutate(s);
    assert.equal(logic.validate(s), false, name + " negative");
}]);
for (const [name, check] of table) check(Session);

// The published events discover the pair inputs. Required members prevent a
// broken enumeration from silently removing the admission/callback probes.
const events = copy(Session.EVENTS);
for (const required of ["talk-down", "talk-up", "stop", "capture-opened", "capture-closed", "final", "confirm", "deadline", "input-silent", "speech-input-ended"])
    assert.equal(events.includes(required), true, required);
const owners = {
    "capture-opened": "capture", "capture-closed": "capture", "capture-failed": "capture", "input-silent": "capture", "input-sound": "capture",
    partial: "turn", final: "turn", "collect-failed": "turn", "brain-done": "turn", "brain-failed": "turn", "conversation-reset": "turn", cancelled: "turn", play: "turn", feedback: "turn",
    "playback-failed": "playback", played: "playback", flushed: "playback", tool: "turn", "tool-done": "action", approval: "turn", shown: "approval", confirm: "approval", "approval-cancel": "approval",
    speak: "speech", "speech-due": "speech", transcript: "speech", "speech-idle": "speech", "speech-failed": "speech", delegation: "speech", "speech-input-ended": "speech",
    "voice-checked": "check", "voice-check-failed": "check", deadline: "quiet"
};
function fixture(type, s, at) {
    const owner = s[owners[type]] || {};
    return event(type, at, { gen: owner.gen ?? s.gen, op: owner.op ?? 99999,
        locked: false, configured: true, engine: s.engine.kind, echoCancel: s.duplex.kind === "full", settings: s.settings, shown: true, bar: "gone",
        text: "fixture", reason: type === "conversation-reset" ? "turn-limit" : "fixture", outcome: "completed", tool: "fixture", timeoutMs: 100, cancellable: true,
        interruptible: true, id: s.approval.id || "fixture", digest: s.approval.digest || "a".repeat(64), physical: true,
        source: "key", role: "user", stage: "partial", rev: 1, ask: null, due: true,
        result: "ready", device: "fixture.mic", capture: s.input.source || s.capture.op || 1, empty: false, speech: true, voice: "VoiceA" });
}
function invariants(before, e, r) {
    const s = r.state;
    assert.equal(Session.validate(s), true, e.type + " state shape");
    assert.ok(s.gen >= before.gen && s.stale >= before.stale && s.nextOp >= before.nextOp);
    if (!e.type.startsWith("voice-mute")) assert.deepEqual(s.voiceMute, before.voiceMute);
    if (!["hide", "show", "hidden"].includes(e.type)) assert.deepEqual(s.visibility, before.visibility);
    if (["opening", "open"].includes(s.capture.kind)) {
        assert.equal(s.visibility.kind === "hidden" ? s.barIndicator.kind === "listening" : s.indicator.kind === "shown", true);
        if (s.visibility.kind === "hidden") assert.equal(s.barIndicator.gen, s.gen);
        assert.equal(s.playback.kind === "idle" || s.duplex.kind === "full" && s.engine.kind === "duplex"
            && s.playback.kind === "playing" && s.input.kind !== "check", true);
        assert.notEqual(s.fault.kind, "error");
        assert.notEqual(s.turn.kind, "cancelling");
        assert.equal(s.gate.kind === "up" || s.input.kind === "check" && s.gate.reason === "unconfigured", true);
        if (s.engine.kind === "duplex") assert.equal(s.speech.kind, "open");
    }
    for (const effect of r.effects) {
        assert.ok(Number.isSafeInteger(effect.op) && effect.op > 0);
        if (effect.kind === "playback-start") assert.equal(s.capture.kind === "closed"
            || s.duplex.kind === "full" && s.engine.kind === "duplex" && s.playback.kind === "playing"
                && ["opening", "open"].includes(s.capture.kind) && s.input.kind !== "check", true);
        if (effect.kind === "collect") assert.notEqual(s.engine.kind, "duplex");
        if (effect.kind === "speech-open") assert.equal(s.engine.kind, "duplex");
        if (effect.kind === "tool-start") assert.equal(s.conversation.kind, "active");
    }
}
const seeds = [ready(Session), listening(Session), listening(Session, false), thinking(Session), speaking(Session), acting(Session), held(Session),
    between(Session), duplexListening(Session), duplexReleased(Session), duplexThinking(Session), duplexSpeaking(Session), echoListening(Session), pendingReply(Session),
    step(Session, listening(Session), event("talk-up", 100)).state,
    step(Session, acting(Session), event("stop", 50)).state, Session.initial()];
let pairs = 0;
for (const seed of seeds) for (const a of events) for (const b of events) {
    let s = copy(seed);
    for (const [index, type] of [a, b].entries()) {
        const e = fixture(type, s, 1000 + index);
        const oldState = copy(s), oldEvent = copy(e);
        const r = step(Session, s, e);
        assert.deepEqual(s, oldState, "state input is immutable");
        assert.deepEqual(e, oldEvent, "event input is immutable");
        invariants(s, e, r);
        s = r.state;
    }
    pairs++;
}
assert.ok(pairs > 0, "event pair discovery completed");

// Each control changes a disposable production copy and runs its owning
// contract. It does not replace the function under test or a dependency.
const parent = os.tmpdir();
fs.mkdirSync(parent, { recursive: true });
const root = fs.mkdtempSync(path.join(parent, "jarvis-session-"));
const source = fs.readFileSync(file, "utf8");
let controls = 0;
try {
    const mutants = [
        ["default-toggle", 'if (s.settings.holdToTalk !== true) { toggle(s, effects, e.at); break; }', 'if (false) { toggle(s, effects, e.at); break; }', "default-talk"],
        ["hold-repeat", 'if (s.input.kind === "held") break;', 'if (false) break;', "hold-release"],
        ["silent-tap-empty", 'if (e.empty) end(s, effects, e.at, "tap", false);', 'if (false) end(s, effects, e.at, "tap", false);', "silent-tap-cloud"],
        ["tap-capture-identity", ' || s.input.source !== e.capture', '', "silent-tap-cloud"],
        ["early-native-short-release", ' && !s.input.heard', '', "cloud-native-result-order"],
        ["preview-native-idle", 'if (previewConversation(s)) {\n            end(s, effects, e.at, "preview", false);', 'if (false) {\n            end(s, effects, e.at, "preview", false);', "preview-native-completion"],
        ["preview-stop-lifetime", 'if (previewConversation(s)) {\n            end(s, effects, e.at, "preview", true);', 'if (false) {\n            end(s, effects, e.at, "preview", true);', "preview-stop"],
        ["preview-no-close-cue", ' && !previewConversation(s) && s.settings.sounds === true', ' && s.settings.sounds === true', "preview-native-completion"],
        ["quiet-close", 'else end(s, effects, at, "idle", false);', 'else void at;', "quiet-close"],
        ["quiet-partial", 'if (String(e.text).trim() !== "") activity(s, e.at);', 'if (false) activity(s, e.at);', "quiet-activity", 2],
        ["observation-fault", 's.sound = e.type === "input-silent" ? { kind: "silent", device: e.device } : { kind: "none" };',
            's.sound = e.type === "input-silent" ? { kind: "silent", device: e.device } : { kind: "none" }; s.fault = { kind: "error", reason: "silent", retry: 0 };', "digital-silence"],
        ["collection-false-deadline", 'if (s.turn.kind === "collecting") s.turn.deadline = null;', 'if (s.turn.kind === "collecting") s.turn.deadline = e.at + COLLECTION_TIMEOUT_MS;', "collection-delay"],
        ["indicator", 's.indicator.kind === "shown"', '(true || s.indicator.kind === "shown")', "indicator-admission"],
        ["hidden-indicator", 'barPresented(s) && s.barIndicator.kind === "listening" :', '(true || barPresented(s) && s.barIndicator.kind === "listening") :', "hidden-admission"],
        ["hidden-generation", ' && s.barIndicator.gen === s.gen', '', "hidden-admission"],
        ["hidden-store", 'effect(s, effects, "hidden-store", { hidden: true });', 'void effects;', "hidden-choice"],
        ["hidden-restore", 'case "hidden":\n        s.visibility = { kind: "hidden" };', 'case "hidden":\n        s.visibility = { kind: "shown" };', "hidden-choice"],
        ["play-before-close", '&& (s.capture.kind === "closed" || overlapping(s)', '&& (true || overlapping(s)', "half-duplex"],
        ["echo-route-required", 'e.engine === "duplex" && e.echoCancel === true', 'e.engine === "duplex"', "echo-route-admission"],
        ["approval-id", 'e.id !== approval.id', '(false && e.id !== approval.id)', "approval-identity"],
        ["approval-draw", 'e.at - approval.shownAt < APPROVAL_DRAW_MS', 'false', "approval-identity"],
        ["stop-tool-cancel", 's.action.cancellation.kind !== "available"', 'false', "tool-lifetime"],
        ["brain-retain", 'if (s.brain.kind === "closed") s.brain =', 'if (true) s.brain =', "brain-lifetime"],
        ["history-reset-epoch", 'epoch: s.history.epoch + 1, reason: reason', 'epoch: s.history.epoch, reason: reason', "new-conversation"],
        ["history-attempted-message", 'userTranscript(s, effects, e.text, 1);', 'void e.text;', "turn-limit-reset"],
        ["stale-op", 'e.op === owner.op', 'true', "stale-callbacks"],
        ["fault-stop", 'if (faulted) s.input = { kind: "stopped" };', 'if (false) s.input = { kind: "stopped" };', "fault-stop"],
        ["phase-priority", 'if (s.approval.kind === "held") return "confirming";', 'if (false) return "confirming";', "phase-priority"],
        ["voice-mute-store", 'effect(s, effects, "voice-mute-store", { muted: s.voiceMute.kind === "on" });', 'void effects;', "voice-mute-and-cues"],
        ["cue-stop", 's.cue = soundedClose ? { kind: "pending", cue: "stop" } : { kind: "none" };', 's.cue = { kind: "none" };', "voice-mute-and-cues"],
        ["pending-reply", 'reply.kind === "waiting" && reply.gen === s.gen', 'false && reply.kind === "waiting" && reply.gen === s.gen', "feedback-reply-ownership"]
    ];
    for (const [name, needle, replacement, row, matches = 1] of mutants) {
        assert.equal(source.split(needle).length - 1, matches, name + " mutation match");
        const changed = source.split(needle).join(replacement);
        assert.notEqual(changed, source);
        const target = path.join(root, name + ".js");
        fs.writeFileSync(target, changed);
        assert.throws(() => table.find(([key]) => key === row)[1](load(target)), assert.AssertionError, name + " must turn its contract red");
        controls++;
    }
} finally { fs.rmSync(root, { recursive: true, force: true }); }
console.log("test-jarvis-session: ok contracts=" + table.length + " pairs=" + pairs + " controls=" + controls);
