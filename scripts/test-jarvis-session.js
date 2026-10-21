#!/usr/bin/env node
// Pure Session contract from the Jarvis plan §3.4, synthetic, 2026-09-30.
// No process, socket, network or audio exists in this suite. Strict assertions
// are Node's shared assertion library, as in the other pure JS suites.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");
const file = path.resolve(__dirname, "../shell/plugins/vgs.jarvis/Session.js");
const Session = load(file);
const copy = value => JSON.parse(JSON.stringify(value));
const events = ["snapshot", "indicator", "talk-down", "talk-up", "toggle", "mute", "unmute", "mute-toggle", "stop",
    "cancel", "interrupt", "capture-opened", "capture-closed", "capture-failed", "playback-failed", "partial", "final", "say", "collect-failed", "brain-done",
    "brain-failed", "brain-ended", "cancelled", "play", "played", "flushed", "tool", "tool-done", "approval",
    "shown", "confirm", "approval-cancel", "deadline", "lease-ended", "speak", "speech-due", "transcript", "speech-idle", "speech-failed", "feedback", "delegation", "relay", "wake", "voice-check", "voice-checked", "voice-check-failed",
    "preview"];
assert.deepEqual(copy(Session.EVENTS), events, "every supported event enters the pair matrix");
const snapshot = extra => ({ type: "snapshot", at: 0, locked: false, engine: "chained", configured: true,
    settings: {}, ...extra });
const event = (type, at = 10, extra = {}) => ({ type, at, ...extra });
// The Talk release that ends a hold pressed at DOWN: TAP_MS later, so it is
// no tap. AFTER moves it later still.
const holdUp = (down = 10, after = 0) => event("talk-up", down + Session.TAP_MS + after);
const callback = (type, owner, at = 20, extra = {}) => event(type, at, {
    gen: owner.gen, op: owner.op, ...(owner.kind === "held" ? { id: owner.id, digest: owner.digest } : {}), ...extra });
const step = (logic, s, e) => copy(logic.reduce(s, e));
const ready = logic => step(logic, step(logic, logic.initial(), snapshot()).state,
    event("indicator", 1, { shown: true })).state;
function listening(logic, toggle = false) {
    let s = ready(logic);
    s = step(logic, s, event(toggle ? "toggle" : "talk-down")).state;
    return step(logic, s, callback("capture-opened", s.capture)).state;
}
function thinking(logic, toggle = false) {
    let s = listening(logic, toggle);
    s = step(logic, s, callback("final", s.turn, 30, { text: "test" })).state;
    return step(logic, s, callback("capture-closed", s.capture, 31)).state;
}
function speaking(logic) {
    let s = thinking(logic);
    return step(logic, s, callback("play", s.turn, 40, { interruptible: true })).state;
}
// A hold conversation between turns: open, idle, the microphone closed.
function between(logic) {
    const s = thinking(logic);
    return step(logic, s, callback("brain-done", s.turn, 40)).state;
}
function acting(logic, cancellable = true) {
    let s = thinking(logic);
    return step(logic, s, callback("tool", s.turn, 40, { tool: "fixture", timeoutMs: 100, cancellable })).state;
}
function held(logic, physical = true) {
    let s = thinking(logic);
    return step(logic, s, callback("approval", s.turn, 40, { id: "held", digest: "a".repeat(64),
        physical, text: "Delete the fixture", tool: "fixture", timeoutMs: 100, cancellable: true })).state;
}
const kinds = result => result.effects.map(e => e.kind);
function confirmation(logic, s, at, extra = {}) {
    return step(logic, s, callback("confirm", s.approval, at, { source: "key", ...extra }));
}
// A duplex engine: talk opens the speech session; the voice model speaks.
const duplexReady = logic => step(logic, ready(logic), snapshot({ engine: "duplex" })).state;
function duplexListening(logic) {
    let s = duplexReady(logic);
    s = step(logic, s, event("talk-down")).state;
    return step(logic, s, callback("capture-opened", s.capture)).state;
}
function duplexSpeaking(logic) {
    let s = step(logic, duplexListening(logic), holdUp()).state;
    s = step(logic, s, callback("capture-closed", s.capture, 31)).state;
    return step(logic, s, callback("speak", s.speech, 32)).state;
}
// Talk released, the user's request is the brain's turn.
function duplexThinking(logic) {
    let s = step(logic, duplexListening(logic), holdUp()).state;
    s = step(logic, s, callback("capture-closed", s.capture, 31)).state;
    return step(logic, s, callback("delegation", s.speech, 32, { id: "request", text: "context" })).state;
}
// The gap: the turn ended and the voice holds its words, no audio yet.
function duplexDue(logic) {
    let s = duplexThinking(logic);
    s = step(logic, s, callback("speech-due", s.speech, 40, { due: true })).state;
    return step(logic, s, callback("brain-done", s.turn, 41)).state;
}
// Always mode: the wake capture opens once the indicator shows.
const always = { mode: "always" };
function alwaysArmed(logic) {
    let s = step(logic, logic.initial(), snapshot({ settings: always })).state;
    s = step(logic, s, event("indicator", 1, { shown: true })).state;
    return step(logic, s, callback("capture-opened", s.capture, 2)).state;
}
function alwaysListening(logic) {
    let s = alwaysArmed(logic);
    s = step(logic, s, callback("wake", s.capture, 10)).state;
    s = step(logic, s, callback("capture-closed", s.capture, 11)).state;
    return step(logic, s, callback("capture-opened", s.capture, 12)).state;
}
function alwaysThinking(logic) {
    let s = alwaysListening(logic);
    s = step(logic, s, callback("final", s.turn, 30, { text: "test" })).state;
    return step(logic, s, callback("capture-closed", s.capture, 31)).state;
}
function alwaysFollowUp(logic, order = "brain-then-played") {
    let s = alwaysThinking(logic);
    s = step(logic, s, callback("play", s.turn, 40, { interruptible: true })).state;
    if (order === "played-then-brain") {
        s = step(logic, s, callback("played", s.playback, 42)).state;
        return step(logic, s, callback("brain-done", s.turn, 43)).state;
    }
    s = step(logic, s, callback("brain-done", s.turn, 41)).state;
    return step(logic, s, callback("played", s.playback, 43)).state;
}
const table = [
    ["voice-check-lifetime", logic => {
        let s = step(logic, logic.initial(), snapshot({ configured: false, checkReady: true, checkSource: "mic-a" })).state;
        assert.equal(logic.canCheck(s), true);
        for (const blocked of [{ ...s, gate: { kind: "down", reason: "locked" } }, { ...s, mute: { kind: "on" } },
            { ...s, turn: thinking(logic).turn }, { ...s, action: acting(logic).action }, { ...s, approval: held(logic).approval }]) {
            assert.equal(logic.canCheck(blocked), false);
            assert.equal(step(logic, blocked, event("voice-check", 1)).state.check.kind, "ready");
        }
        const waiting = step(logic, s, event("voice-check", 10));
        assert.equal(logic.indicatorWanted(waiting.state), true);
        assert.deepEqual(kinds(waiting), [], "microphone waits for the indicator");
        s = step(logic, waiting.state, event("indicator", 11, { shown: true })).state;
        assert.deepEqual([s.capture.kind, s.capture.mode, s.turn.kind, s.brain.kind], ["opening", "check", "none", "closed"]);
        s = step(logic, s, callback("capture-opened", s.capture, 20)).state;
        assert.equal(logic.validate(s), true);
        assert.equal(s.check.deadline, 3020);
        assert.equal(logic.canCapture(s), true, "local setup needs no brain or home");
        const early = step(logic, s, callback("voice-checked", s.check, 21, { result: "ready" })).state;
        assert.equal(early.check.kind, "recording", "an early wake cannot close the three-second sample");
        const closing = step(logic, s, callback("deadline", s.check, 3020));
        assert.deepEqual(kinds(closing), ["capture-close"]);
        assert.equal(closing.state.check.kind, "finishing");
        for (const result of ["ready", "silent", "not-heard"]) {
            const checked = step(logic, closing.state, callback("voice-checked", s.check, 3021, { result })).state;
            assert.deepEqual(checked.check, { kind: "done", result, device: "mic-a" }, "a result names the source it heard");
            const at = (state, extra, time) => step(logic, state, snapshot({ at: time, configured: false, checkReady: true, ...extra })).state;
            const changed = at(checked, { checkSource: "mic-b" }, 3022);
            assert.equal(changed.check.kind, "again", "a result belongs to the checked microphone, and its reset says so");
            assert.deepEqual(at(checked, { checkSource: "mic-a" }, 3022).check, checked.check, "the same source keeps the result");
            assert.deepEqual(at(checked, {}, 3022).check, checked.check, "an unknown source keeps the result");
            // A cloud voice cannot check; it keeps the result for the same
            // source, so Local, then a cloud voice, then Local keeps it.
            const cloud = at(checked, { checkReady: false, checkSource: "mic-a" }, 3023);
            assert.deepEqual(cloud.check, { kind: "kept", result, device: "mic-a" }, "a cloud voice keeps the result");
            assert.deepEqual(at(cloud, { checkSource: "mic-a" }, 3024).check, checked.check, "back on Local the result stands");
            // Under a cloud voice no check can run, so a kept result of
            // another source is dropped; Local then asks for a check.
            const moved = at(cloud, { checkReady: false, checkSource: "mic-b" }, 3024);
            assert.deepEqual([moved.check.kind, at(moved, { checkSource: "mic-b" }, 3025).check.kind], ["unavailable", "ready"],
                "a kept result goes with its source");
        }
        for (const trigger of [event("mute", 30), event("stop", 30), event("lease-ended", 30),
            event("indicator", 30, { shown: false }), event("cancel", 30), event("interrupt", 30),
            snapshot({ at: 30, configured: false, checkReady: true, settings: { ...s.settings, microphone: "other" } }), snapshot({ at: 30, configured: false, checkReady: true, locked: true }),
            snapshot({ at: 30, checkReady: false })]) {
            const stopped = step(logic, s, trigger).state;
            assert.equal(stopped.capture.kind, "closing", trigger.type);
            assert.equal(logic.canCapture(stopped), false, trigger.type);
            assert.equal(stopped.input.kind, "released", trigger.type);
            assert.equal(["waiting", "recording", "finishing"].includes(stopped.check.kind), false, trigger.type);
            assert.notEqual(step(logic, stopped, callback("voice-checked", s.check, 31, { result: "ready" })).state.check.kind, "done");
        }
    }],
    // A source that moves while a check runs, such as a new default
    // microphone with the old one still connected, ends the check and asks
    // again: the result the old source's recording brings is not the new
    // source's.
    ["voice-check-source-moves", logic => {
        let waiting = step(logic, logic.initial(), snapshot({ configured: false, checkReady: true, checkSource: "mic-a" })).state;
        waiting = step(logic, waiting, event("voice-check", 1)).state;
        let recording = step(logic, waiting, event("indicator", 2, { shown: true })).state;
        recording = step(logic, recording, callback("capture-opened", recording.capture, 3)).state;
        const finishing = step(logic, recording, callback("deadline", recording.check, recording.check.deadline)).state;
        for (const [label, owner] of [["waiting", waiting], ["recording", recording], ["finishing", finishing]]) {
            const at = owner.check.deadline - 1;
            const moved = step(logic, owner, snapshot({ at, configured: false, checkReady: true, checkSource: "mic-b" })).state;
            assert.deepEqual([moved.check.kind, moved.checkSource, moved.input.kind], ["again", "mic-b", "released"], label + ": the check asks again");
            assert.equal(["opening", "open"].includes(moved.capture.kind), false, label + ": the old recording ends");
            const late = step(logic, moved, callback("voice-checked", owner.check, at + 1, { result: "ready" })).state;
            assert.equal(late.check.kind, "again", label + ": the old source's result does not land");
            const same = step(logic, owner, snapshot({ at, configured: false, checkReady: true, checkSource: "mic-a" })).state;
            assert.equal(same.check.kind, owner.check.kind, label + ": the same source keeps the check");
        }
    }],
    ["voice-check-failures", logic => {
        let waiting = step(logic, logic.initial(), snapshot({ configured: false, checkReady: true, checkSource: "mic-a" })).state;
        waiting = step(logic, waiting, event("voice-check", 1)).state;
        let recording = step(logic, waiting, event("indicator", 2, { shown: true })).state;
        recording = step(logic, recording, callback("capture-opened", recording.capture, 3)).state;
        const finishing = step(logic, recording, callback("deadline", recording.check, recording.check.deadline)).state;
        for (const [owner, type, reason] of [
            [waiting, "deadline", "check-timeout"], [finishing, "deadline", "check-timeout"],
            [recording, "voice-check-failed", "speech=local-wake-failed"],
            [finishing, "voice-check-failed", "speech=local-wake-failed"]]) {
            const at = type === "deadline" ? owner.check.deadline : owner.check.deadline - 1;
            const failed = step(logic, owner, callback(type, owner.check, at, { reason })).state;
            assert.deepEqual(failed.check, { kind: "failed", reason, device: "mic-a" }, "check failure keeps its cause");
            assert.equal(logic.validate(failed), true);
            assert.equal(failed.input.kind, "released");
            assert.equal(logic.canCapture(failed), false);
            assert.equal(failed.fault.kind, "none", "check failure does not break normal conversation");
            assert.equal(logic.canCheck(failed), true, "check can be repeated");
            const again = step(logic, failed, callback("capture-closed", failed.capture, at + 1)).state;
            const repeated = step(logic, again, event("voice-check", at + 2)).state;
            assert.equal(repeated.check.kind, "waiting");
            assert.notEqual(repeated.check.op, owner.check.op);
            const stale = step(logic, repeated, callback("voice-check-failed", owner.check, at + 3, { reason })).state;
            assert.equal(stale.check.kind, "waiting", "old failure cannot replace a repeated check");
            const changed = step(logic, failed, snapshot({ at: at + 1, configured: false, checkReady: true, checkSource: "mic-b" })).state;
            assert.equal(changed.check.kind, "again", "failure belongs to the checked microphone");
        }
        for (const owner of [waiting, recording, finishing]) for (const type of ["stop", "mute", "lease-ended"]) {
            const stopped = step(logic, owner, event(type, owner.check.deadline - 2)).state;
            const stale = step(logic, stopped, callback("voice-check-failed", owner.check, owner.check.deadline - 1,
                { reason: "speech=local-wake-failed" })).state;
            assert.notEqual(stale.check.kind, "failed", "cancelled check ignores detector failure");
            assert.equal(logic.canCapture(stale), false);
        }
    }],
    ["always-arms", logic => {
        const configured = step(logic, logic.initial(), snapshot({ settings: always })).state;
        assert.deepEqual([configured.input.kind, configured.capture.kind, configured.conversation.kind], ["armed", "closed", "ended"]);
        assert.equal(logic.indicatorWanted(configured), true, "a wake capture asks for its indicator first");
        const shown = step(logic, configured, event("indicator", 1, { shown: true }));
        assert.deepEqual(kinds(shown), ["capture-open"], "the wake capture collects no utterance");
        assert.equal(shown.effects[0].mode, "armed");
        assert.equal(shown.state.gen, configured.gen, "listening for the word starts no conversation");
        const s = alwaysArmed(logic);
        assert.equal(logic.phaseOf(s), "armed");
        assert.equal(logic.validate(s), true);
        for (const mode of ["hold", "toggle"])
            assert.equal(step(logic, ready(logic), snapshot({ settings: { mode } })).state.input.kind, "released", mode + " never arms");
    }],
    ["always-wake", logic => {
        const shown = logic => step(logic, step(logic, logic.initial(), snapshot({ settings: always })).state,
            event("indicator", 1, { shown: true })).state;
        const s = alwaysArmed(logic);
        const woke = step(logic, s, callback("wake", s.capture, 10));
        assert.deepEqual([woke.state.capture.kind, woke.state.input.kind, woke.state.conversation.kind],
            ["closing", "woken", "active"]);
        assert.equal(woke.state.gen, s.gen + 1);
        assert.equal(woke.effects.find(e => e.kind === "capture-close").target, s.capture.op);
        const reopened = step(logic, woke.state, callback("capture-closed", woke.state.capture, 11));
        assert.deepEqual(kinds(reopened), ["capture-open", "collect"]);
        assert.equal(reopened.effects[0].mode, "conversation");
        const sounds = step(logic, s, snapshot({ at: 5, settings: { ...always, sounds: true } })).state;
        const cued = step(logic, step(logic, sounds, event("indicator", 6, { shown: true })).state, event("indicator", 6, { shown: true })).state;
        const opened = step(logic, cued, callback("capture-opened", cued.capture, 7)).state;
        assert.equal(step(logic, opened, callback("wake", opened.capture, 8)).state.playback.cue, "start", "the word is answered by the start sound");
        for (const [label, before, owner] of [["old capture", woke.state, s.capture],
            ["listening capture", alwaysListening(logic), alwaysListening(logic).capture],
            ["opening capture", shown(logic), shown(logic).capture]]) {
            const late = step(logic, before, callback("wake", owner, 20));
            assert.deepEqual([late.state.stale, late.effects], [before.stale + 1, []], label + " wake is dropped and counted");
        }
    }],
    ["always-one-utterance", logic => {
        const s = alwaysListening(logic);
        const final = step(logic, s, callback("final", s.turn, 30, { text: "test" }));
        assert.deepEqual([final.state.input.kind, final.state.turn.kind, final.state.capture.kind], ["released", "thinking", "closing"]);
        const closed = step(logic, final.state, callback("capture-closed", final.state.capture, 31));
        assert.deepEqual([kinds(closed), closed.state.input.kind], [[], "released"], "no capture while the turn thinks");
        const speaking = step(logic, closed.state, callback("play", closed.state.turn, 40, { interruptible: true })).state;
        const done = step(logic, speaking, callback("brain-done", speaking.turn, 41)).state;
        assert.equal(done.input.kind, "released", "no capture while Jarvis speaks");
        const rearmed = step(logic, done, callback("played", done.playback, 42));
        assert.deepEqual(kinds(rearmed), ["capture-open", "collect"]);
        assert.deepEqual([rearmed.effects[0].mode, rearmed.state.input.kind, rearmed.state.conversation.kind, rearmed.state.gen],
            ["follow-up", "follow-up", "active", s.gen], "the short follow-up window opens in the same conversation");
    }],
    ["always-follow-up-orders", logic => {
        for (const order of ["brain-then-played", "played-then-brain"]) {
            const opened = alwaysFollowUp(logic, order);
            assert.deepEqual([opened.capture.kind, opened.capture.mode, opened.input.kind, opened.conversation.kind],
                ["opening", "follow-up", "follow-up", "active"], order + " opens the follow-up window");
            assert.equal(opened.turn.kind, "collecting", order + " collects the next words");
            const live = step(logic, opened, callback("capture-opened", opened.capture, 44)).state;
            assert.equal(live.turn.deadline, 6044, order + " uses the wake silence bound");
            assert.equal(logic.phaseOf(live), "listening");
        }
    }],
    ["always-follow-up-final", logic => {
        let s = alwaysFollowUp(logic);
        s = step(logic, s, callback("capture-opened", s.capture, 44)).state;
        const heard = step(logic, s, callback("partial", s.turn, 45, { text: "and germany" })).state;
        assert.deepEqual([heard.input.kind, heard.turn.deadline, heard.gen], ["conversation", null, s.gen],
            "words inside the window become a normal request in the same conversation");
        const sent = step(logic, heard, callback("final", heard.turn, 46, { text: "and germany" }));
        const brain = sent.effects.find(e => e.kind === "brain-send");
        assert.deepEqual([brain.text, brain.gen, brain.owner], ["and germany", s.gen, s.brain.op]);
        assert.equal(sent.state.followUp.kind, "asked", "follow-up turns can chain another window");
    }],
    ["always-follow-up-silence", logic => {
        let s = alwaysFollowUp(logic);
        s = step(logic, s, callback("capture-opened", s.capture, 44)).state;
        const quiet = step(logic, s, callback("deadline", s.turn, s.turn.deadline));
        assert.deepEqual([kinds(quiet), quiet.state.fault.kind, quiet.state.conversation.kind, quiet.state.input.kind, quiet.state.turn.kind],
            [["capture-close"], "none", "active", "armed", "none"], "silence closes the window and keeps the conversation");
        const rearmed = step(logic, quiet.state, callback("capture-closed", quiet.state.capture, s.turn.deadline + 1));
        assert.deepEqual([kinds(rearmed), rearmed.effects[0].mode], [["capture-open"], "armed"], "the wake capture re-arms");
        const late = step(logic, rearmed.state, callback("final", s.turn, s.turn.deadline + 2, { text: "too late" }));
        assert.equal(late.effects.some(e => e.kind === "brain-send"), false);
        assert.equal(late.state.stale, rearmed.state.stale + 1);
    }],
    ["always-follow-up-refusals", logic => {
        const thinking = alwaysThinking(logic);
        const noReply = step(logic, thinking, callback("brain-done", thinking.turn, 40));
        assert.equal(noReply.state.followUp.kind, "none", "no spoken reply opens no window");
        assert.equal(kinds(noReply).includes("capture-open"), true, "the wake word re-arms instead");
        let failed = alwaysThinking(logic);
        failed = step(logic, failed, callback("play", failed.turn, 40, { interruptible: true })).state;
        const brainFailed = step(logic, failed, callback("brain-failed", failed.turn, 41, { reason: "fixture" })).state;
        assert.equal(brainFailed.playback.kind, "flushing");
        const playedAfterFailure = step(logic, brainFailed, callback("played", failed.playback, 42));
        assert.equal(playedAfterFailure.effects.some(e => e.kind === "capture-open"), false, "a failed turn opens no window");
        const flushedAfterFailure = step(logic, brainFailed, callback("flushed", brainFailed.playback, 42));
        assert.deepEqual([flushedAfterFailure.state.followUp.kind, flushedAfterFailure.state.input.kind,
            flushedAfterFailure.effects.some(e => e.kind === "capture-open")], ["none", "released", false],
            "a failed turn drops the pending window once its reply is flushed");
        let typed = step(logic, alwaysArmed(logic), event("say", 20, { text: "typed" })).state;
        typed = step(logic, typed, callback("capture-closed", typed.capture, 21)).state;
        typed = step(logic, typed, callback("play", typed.turn, 22, { interruptible: true })).state;
        typed = step(logic, typed, callback("brain-done", typed.turn, 23)).state;
        const afterTyped = step(logic, typed, callback("played", typed.playback, 24));
        assert.equal(afterTyped.effects.find(e => e.kind === "capture-open")?.mode, "armed", "Console messages return to the wake word");
        assert.equal(afterTyped.state.followUp.kind, "none", "Console messages do not arm follow-up memory");
        let relay = between(logic);
        relay.settings = { mode: "always" };
        relay.input = { kind: "released" };
        relay = step(logic, relay, event("relay", 50, { text: "line", ask: null })).state;
        relay = step(logic, relay, callback("play", relay.turn, 51, { interruptible: true })).state;
        relay = step(logic, relay, callback("brain-done", relay.turn, 52)).state;
        const relayPlayed = step(logic, relay, callback("played", relay.playback, 53));
        assert.equal(relayPlayed.effects.some(e => e.kind === "capture-open" && e.mode === "follow-up"), false,
            "a spoken relay line opens no window");
    }],
    ["always-follow-up-overrun", logic => {
        let s = alwaysThinking(logic);
        s = step(logic, s, callback("tool", s.turn, 40, { tool: "fixture", id: "t1", timeoutMs: 1000, cancellable: false })).state;
        assert.equal(s.action.kind, "running");
        s = step(logic, s, callback("deadline", s.action, 1041)).state;
        s = step(logic, s, callback("play", s.turn, 1042, { interruptible: true })).state;
        s = step(logic, s, callback("played", s.playback, 1043)).state;
        s = step(logic, s, callback("brain-done", s.turn, 1044)).state;
        assert.deepEqual([s.action.kind, s.followUp.kind], ["running", "none"], "a reply that ends while a tool holds Jarvis drops the window");
        const later = step(logic, s, callback("tool-done", s.action, 300000, { outcome: "completed" }));
        assert.equal(later.effects.some(e => e.kind === "capture-open" && e.mode === "follow-up"), false,
            "the window does not open when the tool ends minutes later");
        assert.notEqual(later.state.input.kind, "follow-up");
    }],
    ["always-follow-up-closes", logic => {
        let s = alwaysFollowUp(logic);
        s = step(logic, s, callback("capture-opened", s.capture, 44)).state;
        for (const [name, trigger] of [["mute", event("mute", 45)], ["stop", event("stop", 45)]]) {
            const closed = step(logic, s, trigger);
            assert.equal(kinds(closed).includes("capture-close"), true, name + " closes the follow-up capture");
            assert.equal(closed.state.followUp.kind, "none");
            assert.notEqual(closed.state.input.kind, "follow-up");
        }
        for (const [name, trigger] of [["mute", event("mute", 43)], ["stop", event("stop", 43)]]) {
            let spoken = alwaysThinking(logic);
            spoken = step(logic, spoken, callback("play", spoken.turn, 40, { interruptible: true })).state;
            spoken = step(logic, spoken, callback("played", spoken.playback, 42)).state;
            assert.equal(spoken.followUp.kind, "spoken");
            const ended = step(logic, spoken, trigger).state;
            assert.equal(ended.turn.kind, "cancelling");
            const after = step(logic, ended, callback("cancelled", ended.turn, 44)).state;
            assert.equal(after.turn.kind, "none", name + " ends the turn");
            assert.notEqual(after.input.kind, "follow-up", name + " before brain-done opens no window afterwards");
            assert.equal(after.followUp.kind, "none", name + " drops the pending window");
        }
        const press = step(logic, s, event("talk-down", 500));
        assert.deepEqual([press.state.conversation.kind, press.state.input.kind, press.state.turn.kind],
            ["ended", "armed", "none"], "Talk closes the follow-up window as it closes a woken request");
    }],
    ["always-disarms", logic => {
        const s = alwaysArmed(logic);
        for (const [label, e] of [["mute", event("mute", 20)], ["stop", event("stop", 20)],
            ["lock", snapshot({ at: 20, locked: true, settings: always })], ["hold", snapshot({ at: 20, settings: { mode: "hold" } })],
            ["duplex", snapshot({ at: 20, engine: "duplex", settings: always })]]) {
            const r = step(logic, s, e);
            assert.equal(r.state.capture.kind, "closing", label);
            if (label === "stop") assert.equal(r.state.input.kind, "armed", "stop ends nothing Always mode waits for");
            else assert.equal(r.state.input.kind, "released", label);
            const closed = step(logic, r.state, callback("capture-closed", r.state.capture, 21));
            assert.deepEqual(kinds(closed).filter(k => k === "capture-open").length, label === "stop" ? 1 : 0, label);
        }
        const failed = step(logic, s, callback("capture-failed", s.capture, 20, { reason: "provider-disconnected" })).state;
        assert.deepEqual([failed.fault.kind, failed.input.kind], ["error", "released"], "a fault stops listening for the word");
        const gone = step(logic, s, event("indicator", 20, { shown: false })).state;
        assert.deepEqual([gone.capture.kind, gone.input.kind], ["closing", "armed"], "no indicator, no capture");
        const typed = step(logic, s, event("say", 20, { text: "typed" })).state;
        assert.deepEqual([typed.input.kind, typed.turn.kind, typed.capture.kind], ["released", "thinking", "closing"]);
        const muting = step(logic, s, event("mute", 20)).state;
        const muted = step(logic, muting, callback("capture-closed", muting.capture, 21)).state;
        assert.equal(muted.mute.kind, "on");
        assert.equal(step(logic, muted, event("unmute", 22)).state.input.kind, "armed", "unmute listens for the word again");
    }],
    ["always-talk", logic => {
        const s = alwaysArmed(logic);
        const pressed = step(logic, s, event("talk-down", 300));
        assert.deepEqual([pressed.state.input.kind, pressed.state.capture.kind, pressed.state.conversation.kind],
            ["conversation", "closing", "active"], "Talk listens now");
        assert.deepEqual(step(logic, pressed.state, event("talk-up", 301)).state.input, pressed.state.input, "release changes nothing");
        const armedHeard = step(logic, pressed.state, callback("capture-closed", pressed.state.capture, 302));
        assert.deepEqual([kinds(armedHeard), armedHeard.effects[0].mode], [["capture-open", "collect"], "conversation"],
            "a press while armed listens for a request");
        const heard = step(logic, armedHeard.state, callback("capture-opened", armedHeard.state.capture, 303)).state;
        const bounced = step(logic, heard, event("talk-down", 400));
        assert.deepEqual([bounced.effects, bounced.state.turn.kind], [[], "collecting"], "a press within 250 ms is no press");
        const talkEnded = step(logic, heard, event("talk-down", 600)).state;
        assert.deepEqual([talkEnded.conversation.kind, talkEnded.input.kind], ["ended", "armed"], "a press while listening after Talk ends it");
        const listening = alwaysListening(logic);
        const again = step(logic, listening, event("talk-down", 400));
        assert.deepEqual([again.state.conversation.kind, again.state.input.kind, again.state.turn.kind], ["ended", "armed", "none"],
            "a press while listening ends it");
        const rearmed = step(logic, again.state, callback("capture-closed", again.state.capture, 401));
        assert.deepEqual([kinds(rearmed), rearmed.effects[0].mode], [["capture-open"], "armed"], "the word is awaited again");
        // A press while Jarvis speaks stops the reply, then listens.
        let reply = alwaysThinking(logic);
        reply = step(logic, reply, callback("play", reply.turn, 40, { interruptible: true })).state;
        reply = step(logic, reply, callback("brain-done", reply.turn, 41)).state;
        const stopped = step(logic, reply, event("talk-down", 500));
        assert.deepEqual([kinds(stopped), stopped.state.input.kind], [["playback-flush"], "conversation"], "a press while speaking stops the reply");
        const afterReply = step(logic, stopped.state, callback("flushed", stopped.state.playback, 501));
        assert.deepEqual([kinds(afterReply), afterReply.state.gen], [["capture-open", "collect"], reply.gen], "then listens in the same conversation");
        // A press while Jarvis thinks cancels the turn, then listens.
        const busy = alwaysThinking(logic);
        const cancelling = step(logic, busy, event("talk-down", 500));
        assert.deepEqual([kinds(cancelling), cancelling.state.turn.kind, cancelling.state.input.kind],
            [["brain-cancel"], "cancelling", "conversation"], "a press while thinking cancels the turn");
        const afterCancel = step(logic, cancelling.state, callback("cancelled", cancelling.state.turn, 501));
        assert.deepEqual(kinds(afterCancel), ["capture-open", "collect"], "then listens");
        // A press on a shown fault clears it and listens.
        const faulted = step(logic, listening, callback("capture-failed", listening.capture, 40, { reason: "provider-disconnected" })).state;
        const cleared = step(logic, faulted, event("talk-down", 500));
        assert.deepEqual([cleared.state.fault.kind, cleared.state.input.kind], ["none", "conversation"], "a press on a fault listens");
        // After a turn the conversation stays open while the word is awaited.
        let t = alwaysThinking(logic);
        t = step(logic, t, callback("brain-done", t.turn, 40)).state;
        t = step(logic, t, callback("capture-opened", t.capture, 41)).state;
        assert.deepEqual([t.input.kind, t.conversation.kind], ["armed", "active"]);
        const followUp = step(logic, t, event("talk-down", 500)).state;
        assert.deepEqual([followUp.input.kind, followUp.gen], ["conversation", t.gen], "Talk continues the conversation");
    }],
    ["always-false-wake", logic => {
        const s = alwaysListening(logic);
        assert.equal(s.input.kind, "woken");
        assert.ok(Number.isFinite(s.turn.deadline) && s.turn.deadline > 12 && s.turn.deadline - 12 < 60000,
            "a woken request waits a short bound for words");
        const early = step(logic, s, callback("deadline", s.turn, s.turn.deadline - 1));
        assert.deepEqual([early.effects, early.state.turn.kind], [[], "collecting"], "the bound has not passed");
        const quiet = step(logic, s, callback("deadline", s.turn, s.turn.deadline));
        assert.deepEqual([kinds(quiet), quiet.state.fault.kind, quiet.state.conversation.kind, quiet.state.input.kind, quiet.state.turn.kind],
            [["capture-close"], "none", "ended", "armed", "none"], "silence after the word returns quietly to armed");
        const rearmed = step(logic, quiet.state, callback("capture-closed", quiet.state.capture, s.turn.deadline + 1));
        assert.deepEqual([kinds(rearmed), rearmed.effects[0].mode], [["capture-open"], "armed"], "the wake capture re-arms");
        // Words before the bound: the request is collected as today.
        const spoken = step(logic, s, callback("partial", s.turn, 20, { text: "what time" })).state;
        assert.deepEqual([spoken.input.kind, spoken.turn.deadline], ["conversation", null], "words lift the bound");
        const kept = step(logic, spoken, callback("deadline", spoken.turn, s.turn.deadline));
        assert.equal(kept.state.turn.kind, "collecting", "a heard request outlives the bound");
        const sent = step(logic, kept.state, callback("final", kept.state.turn, s.turn.deadline + 1, { text: "what time is it" }));
        assert.deepEqual([sent.state.turn.kind, sent.effects.find(e => e.kind === "brain-send").text], ["thinking", "what time is it"]);
        // A Talk-started request keeps no such bound.
        let talk = step(logic, alwaysArmed(logic), event("talk-down", 300)).state;
        talk = step(logic, talk, callback("capture-closed", talk.capture, 301)).state;
        talk = step(logic, talk, callback("capture-opened", talk.capture, 302)).state;
        assert.deepEqual([talk.input.kind, talk.turn.kind, talk.turn.deadline], ["conversation", "collecting", null], "Talk waits for words as before");
    }],
    ["final-caption", logic => {
        let s = listening(logic);
        const draft = step(logic, s, callback("partial", s.turn, 21, { text: "draft words" }));
        assert.equal(kinds(draft).includes("brain-send"), false);
        s = draft.state;
        const r = step(logic, s, callback("final", s.turn, 22, { text: "final words" }));
        const caption = r.effects.find(e => e.kind === "transcript");
        assert.ok(caption, "the final reaches the caption consumer");
        assert.deepEqual([caption.role, caption.stage, caption.text, caption.rev], ["user", "final", "final words", s.turn.op]);
        assert.equal(r.effects.find(e => e.kind === "brain-send").text, "final words");
        assert.ok(kinds(r).indexOf("transcript") < kinds(r).indexOf("brain-send"));
        const late = step(logic, r.state, callback("final", s.turn, 23, { text: "late" }));
        assert.equal(kinds(late).includes("transcript"), false);
        assert.equal(kinds(step(logic, s, callback("final", s.turn, 23, { text: "" }))).includes("transcript"), false,
            "silence sends no invalid empty caption");
    }],
    ["say-idle", logic => {
        const s = ready(logic);
        const r = step(logic, s, event("say", 20, { text: "typed words" }));
        assert.equal(r.state.conversation.kind, "active");
        assert.equal(r.state.gen, s.gen + 1);
        assert.equal(r.state.turn.kind, "thinking");
        assert.equal(r.state.input.kind, "released");
        const transcript = r.effects.find(e => e.kind === "transcript");
        assert.ok(transcript);
        assert.deepEqual([transcript.gen, transcript.role, transcript.text, transcript.rev], [r.state.gen, "user", "typed words", 1]);
        const brain = r.effects.find(e => e.kind === "brain-send");
        assert.deepEqual([brain.gen, brain.text], [r.state.gen, "typed words"]);
    }],
    ["say-refusals", logic => {
        const unchanged = (label, s, key) => {
            assert.equal(logic.sayRefusal(s), key, label);
            assert.deepEqual(step(logic, s, event("say", 20, { text: "typed" })), { state: copy(s), effects: [] }, label);
        };
        unchanged("down", logic.initial(), "down");
        unchanged("muted", step(logic, ready(logic), event("mute", 10)).state, "muted");
        unchanged("duplex", duplexReady(logic), "duplex");
        unchanged("held", held(logic), "held");
        unchanged("speaking", speaking(logic), "speaking");
        unchanged("busy-turn", thinking(logic), "busy");
        unchanged("busy-action", acting(logic), "busy");
        unchanged("busy-cancel", step(logic, thinking(logic), event("cancel", 50)).state, "busy");
    }],
    // A local preview is a turn of its own with no user words: the engine
    // speaks its fixed sentence, Session admits the playback as a reply's.
    ["preview-local", logic => {
        for (const [label, s] of [["idle", ready(logic)], ["between turns", between(logic)], ["always armed", alwaysArmed(logic)]]) {
            assert.equal(logic.previewRefusal(s), null, label);
            let r = step(logic, s, event("preview", 50, { voice: "VoiceA" }));
            const send = r.effects.find(e => e.kind === "brain-send");
            assert.ok(send, label + ": the engine is asked for the sentence");
            assert.deepEqual([send.preview, send.voice, send.text, r.state.turn.kind, r.state.turn.op, r.state.conversation.kind],
                [true, "VoiceA", undefined, "thinking", send.op, "active"], label);
            assert.equal(r.state.gen, s.conversation.kind === "ended" ? s.gen + 1 : s.gen, label + ": a new conversation takes a new gen");
            assert.equal(kinds(r).includes("transcript"), false, label + ": a preview is no user turn");
            assert.equal(r.state.capture.kind === "open" || r.state.capture.kind === "opening", false, label + ": no microphone opens");
            r = step(logic, r.state, callback("play", r.state.turn, 51, { interruptible: true }));
            assert.deepEqual([r.state.playback.kind, r.state.playback.source], ["playing", send.op], label + ": the sentence plays");
        }
    }],
    ["preview-refusals", logic => {
        const unchanged = (label, s, key) => {
            assert.equal(logic.previewRefusal(s), key, label);
            assert.deepEqual(step(logic, s, event("preview", 20, { voice: "VoiceA" })), { state: copy(s), effects: [] }, label);
        };
        unchanged("down", logic.initial(), "down");
        unchanged("muted", step(logic, ready(logic), event("mute", 10)).state, "muted");
        unchanged("listening", listening(logic), "busy");
        unchanged("thinking", thinking(logic), "busy");
        unchanged("speaking", speaking(logic), "busy");
        unchanged("held", held(logic), "busy");
        unchanged("acting", acting(logic), "busy");
        unchanged("follow-up window", alwaysFollowUp(logic), "busy");
        unchanged("duplex conversation", duplexListening(logic), "busy");
        let checking = step(logic, logic.initial(), snapshot({ checkReady: true })).state;
        checking = step(logic, step(logic, checking, event("indicator", 1, { shown: true })).state, event("voice-check", 20)).state;
        assert.equal(checking.check.kind, "waiting");
        unchanged("microphone check", checking, "busy");
        // Each clause alone: a reply still playing after its turn, and a held
        // request or a running action with no turn in flight.
        const reply = speaking(logic);
        const playing = step(logic, reply, callback("brain-done", reply.turn, 41)).state;
        assert.deepEqual([playing.turn.kind, playing.playback.kind], ["none", "playing"]);
        unchanged("playing after its turn", playing, "busy");
        const idle = between(logic);
        for (const [label, s] of [["held alone", { ...idle, approval: held(logic).approval }], ["acting alone", { ...idle, action: acting(logic).action }]])
            assert.equal(logic.previewRefusal(s), "busy", label);
    }],
    // A preview after a failed turn clears the fault as Talk does, then speaks.
    ["preview-recovers", logic => {
        const s = thinking(logic);
        const failed = step(logic, s, callback("brain-failed", s.turn, 40, { reason: "brain=fixture" })).state;
        assert.equal(failed.fault.kind, "error");
        assert.equal(logic.previewRefusal(failed), null);
        const r = step(logic, failed, event("preview", 50, { voice: "VoiceA" }));
        assert.deepEqual([r.state.fault.kind, r.state.turn.kind, kinds(r).includes("brain-send")], ["none", "thinking", true]);
    }],
    // A duplex preview opens the voice's session alone, with no capture;
    // the voice's idle report after the sentence ends the conversation.
    ["preview-duplex", logic => {
        const s = duplexReady(logic);
        let r = step(logic, s, event("preview", 50, { voice: "marin" }));
        const open = r.effects.find(e => e.kind === "speech-open");
        assert.ok(open, "the voice's session opens");
        assert.equal(open.voice, "marin", "the preview names its voice");
        assert.deepEqual([open.preview, r.state.speech.op, r.state.conversation.kind, r.state.gen, r.state.turn.kind],
            [true, open.op, "active", s.gen + 1, "none"]);
        assert.equal(kinds(r).includes("capture-open"), false, "no microphone opens");
        r = step(logic, r.state, callback("speak", r.state.speech, 51));
        assert.equal(r.effects.find(e => e.kind === "playback-start").source, open.op, "the voice's sentence plays");
        r = step(logic, r.state, callback("played", r.state.playback, 52));
        r = step(logic, r.state, callback("speech-idle", r.state.speech, 53));
        assert.deepEqual([r.state.conversation.kind, r.effects.find(e => e.kind === "speech-close").target], ["ended", open.op]);
    }],
    ["relay-idle", logic => {
        const s = between(logic);
        assert.equal(logic.relayRefusal(s), null);
        const ask = { task: "t1", prompt: "p1", kind: "question" };
        const r = step(logic, s, event("relay", 50, { text: "The coding agent asks: Which branch?", ask }));
        assert.deepEqual(kinds(r), ["brain-send"], "a relay line is no user turn: no user caption");
        const send = r.effects[0];
        assert.deepEqual([send.text, send.relay], [undefined, { text: "The coding agent asks: Which branch?", ask }]);
        assert.equal(send.owner, s.brain.op, "the relay turn keeps the conversation's brain owner");
        assert.deepEqual([r.state.turn.kind, r.state.turn.op, r.state.gen, r.state.conversation.kind], ["thinking", send.op, s.gen, "active"]);
        assert.deepEqual(r.state.brain, s.brain, "the relay turn keeps the conversation's brain owner");
        assert.equal(r.state.stale, s.stale);
        const line = step(logic, s, event("relay", 50, { text: "The coding task was stopped.", ask: null }));
        assert.equal(line.effects[0].relay.ask, null);
    }],
    ["relay-refusals", logic => {
        const refused = (label, s, key) => {
            assert.equal(logic.relayRefusal(s), key, label);
            const r = step(logic, s, event("relay", 300, { text: "line", ask: null }));
            assert.deepEqual(kinds(r).filter(kind => kind === "brain-send"), [], label);
            assert.equal(r.state.stale, s.stale + 1, label + " is counted stale");
            assert.equal(r.state.turn.kind, s.turn.kind, label);
        };
        refused("down", logic.initial(), "down");
        refused("ended", ready(logic), "ended");
        refused("muted", step(logic, between(logic), event("mute", 50)).state, "muted");
        refused("duplex", step(logic, between(logic), snapshot({ at: 50, engine: "duplex" })).state, "duplex");
        let failedTurn = thinking(logic);
        failedTurn = step(logic, failedTurn, callback("brain-failed", failedTurn.turn, 40, { reason: "fixture" })).state;
        refused("fault", failedTurn, "fault");
        refused("listening", listening(logic), "busy");
        refused("thinking", thinking(logic), "busy");
        refused("speaking", speaking(logic), "busy");
        refused("acting", acting(logic), "busy");
        refused("held", held(logic), "busy");
        refused("toggle-conversation", step(logic, ready(logic), event("toggle", 50)).state, "busy");
        // Talk held while the indicator is away: no capture, but the user is speaking up.
        const hidden = step(logic, between(logic), event("indicator", 50, { shown: false })).state;
        const pressed = step(logic, hidden, event("talk-down", 51)).state;
        assert.deepEqual([pressed.input.kind, pressed.capture.kind, pressed.turn.kind], ["held", "closed", "none"]);
        refused("talk-held", pressed, "busy");
        assert.throws(() => logic.reduce(between(logic), event("relay", 50, { text: "line" })), /session=relay/);
        assert.throws(() => logic.reduce(between(logic), event("relay", 50, { text: " ", ask: null })), /session=relay/);
        assert.throws(() => logic.reduce(between(logic), event("relay", 50, { text: "line",
            ask: { task: "t1", prompt: "p1", kind: "idle" } })), /session=relay/);
    }],
    ["say-refuses-action-only", logic => {
        const running = acting(logic, false);
        const stopped = step(logic, running, event("stop", 50)).state;
        const idleTurn = step(logic, stopped, callback("cancelled", stopped.turn, 51)).state;
        assert.deepEqual([idleTurn.turn.kind, idleTurn.action.kind], ["none", "running"]);
        assert.equal(logic.sayRefusal(idleTurn), "busy");
        assert.deepEqual(step(logic, idleTurn, event("say", 52, { text: "typed" })), { state: copy(idleTurn), effects: [] });
    }],
    ["say-recovers", logic => {
        let s = thinking(logic);
        s = step(logic, s, callback("brain-failed", s.turn, 40, { reason: "fixture" })).state;
        const r = step(logic, s, event("say", 50, { text: "after fault" }));
        assert.equal(r.state.fault.kind, "none");
        assert.equal(r.state.turn.kind, "thinking");
        assert.equal(r.effects.find(e => e.kind === "brain-send").text, "after fault");
    }],
    ["say-refuses-speaking", logic => {
        const s = step(logic, speaking(logic), callback("brain-done", speaking(logic).turn, 40)).state;
        assert.equal(logic.sayRefusal(s), "speaking");
        assert.deepEqual(step(logic, s, event("say", 50, { text: "barge in" })), { state: copy(s), effects: [] });
    }],
    ["say-replaces-collection", logic => {
        const s = listening(logic, true);
        const r = step(logic, s, event("say", 30, { text: "typed instead" }));
        assert.equal(r.state.input.kind, "conversation");
        assert.equal(r.state.capture.kind, "closing");
        assert.equal(r.state.turn.kind, "thinking");
        assert.ok(kinds(r).includes("capture-close"));
        assert.equal(r.effects.find(e => e.kind === "brain-send").text, "typed instead");
    }],
    ["toggle-after-say-listens", logic => {
        let s = step(logic, ready(logic), snapshot({ settings: { mode: "toggle" } })).state;
        const said = step(logic, s, event("say", 20, { text: "typed" }));
        const brain = said.state.turn;
        s = step(logic, said.state, callback("brain-done", brain, 30)).state;
        const talk = step(logic, s, event("talk-down", 300));
        assert.equal(talk.state.conversation.kind, "active");
        assert.equal(talk.state.capture.kind, "opening");
        assert.deepEqual(talk.effects.map(e => e.kind), ["capture-open", "collect"]);
        assert.equal(talk.effects.some(e => e.kind === "brain-close"), false);
    }],
    ["user-transcript-sanitized", logic => {
        let s = listening(logic);
        let r = step(logic, s, callback("final", s.turn, 30, { text: "line\nfeed" }));
        assert.equal(r.effects.find(e => e.kind === "transcript").text, "line feed");
        s = ready(logic);
        r = step(logic, s, event("say", 20, { text: "   " }));
        assert.equal(r.effects.some(e => e.kind === "transcript"), false);
        r = step(logic, s, event("say", 21, { text: "x".repeat(logic.TRANSCRIPT_CHARS + 1) }));
        assert.equal(r.effects.find(e => e.kind === "transcript").text.length, logic.TRANSCRIPT_CHARS);
    }],
    ["collection-deadline", logic => {
        let s = listening(logic);
        assert.equal(s.turn.deadline, null);
        s = step(logic, s, event("talk-up", 100000)).state;
        assert.equal(s.turn.deadline, 160000);
        s = step(logic, s, callback("capture-closed", s.capture, 100001)).state;
        assert.equal(s.turn.deadline, 160001);
        assert.equal(step(logic, s, callback("deadline", s.turn, 160000)).state.turn.kind, "collecting");
        const expired = step(logic, s, callback("deadline", s.turn, 160001));
        assert.equal(expired.state.turn.kind, "none");
        assert.equal(expired.state.fault.kind, "error");
        assert.equal(expired.state.fault.reason, "speech=collect-timeout");
        assert.equal(expired.state.conversation.kind, "ended");
        assert.equal(step(logic, expired.state, callback("final", s.turn, 160002, { text: "fixture" })).state.stale,
            expired.state.stale + 1);
        assert.equal(logic.validate(expired.state), true);
    }],
    ["playback-deadline", logic => {
        const playing = speaking(logic);
        assert.equal(playing.playback.deadline, null);
        const s = step(logic, playing, callback("brain-done", playing.turn, 100)).state;
        assert.equal(s.playback.deadline, 300100);
        assert.equal(logic.validate(s), true);
        assert.equal(step(logic, s, callback("deadline", s.playback, 300099)).state.playback.kind, "playing");
        const expired = step(logic, s, callback("deadline", s.playback, 300100));
        assert.equal(expired.state.fault.reason, "playback-timeout");
        assert.equal(expired.state.playback.kind, "flushing");
        assert.equal(expired.state.conversation.kind, "ended");
        assert.equal(kinds(expired).includes("playback-flush"), true);
        assert.equal(kinds(expired).includes("brain-close"), true);
        assert.equal(step(logic, expired.state, callback("played", s.playback, 300101)).state.stale, expired.state.stale + 1);
    }],
    ["confirmation", logic => {
        const heldState = held(logic);
        const s = step(logic, heldState, callback("shown", heldState.approval, 50)).state;
        const accepted = confirmation(logic, s, 750);
        assert.equal(accepted.state.approval.kind, "none");
        assert.equal(accepted.state.action.kind, "running");
        assert.equal(accepted.state.action.brain, s.approval.brain);
        assert.equal(accepted.state.action.limit.deadline, 850);
        assert.equal(accepted.effects.find(e => e.kind === "tool-start").confirmed, "key");
        const replay = step(logic, accepted.state, callback("confirm", s.approval, 751, { source: "key" }));
        assert.equal(replay.effects.find(e => e.kind === "confirm-refused")?.reason, "no-hold");
        assert.equal(kinds(replay).includes("tool-start"), false);
        for (const source of ["button", "voice"]) {
            const h = held(logic, false);
            const shown = step(logic, h, callback("shown", h.approval, 50)).state;
            assert.equal(confirmation(logic, shown, 1750, { source, beganAt: 1050, idleAt: 0 }).state.action.kind, "running");
        }
    }],
    ...[
        ["confirm-id", { id: "synthetic" }, "identity"],
        ["confirm-digest", { digest: "b".repeat(64) }, "identity"],
        ["confirm-generation", { gen: 999 }, "identity"],
        ["confirm-source", { source: "model" }, "source"],
        ["confirm-physical", { source: "voice", beganAt: 1050, idleAt: 0 }, "voice-physical"]
    ].map(([name, extra, reason]) => [name, logic => {
        const h = held(logic);
        const s = step(logic, h, callback("shown", h.approval, 50)).state;
        const r = confirmation(logic, s, extra.source === "voice" ? 1750 : 750, extra);
        assert.equal(r.effects.find(e => e.kind === "confirm-refused")?.reason, reason);
        assert.equal(r.state.action.kind, "none");
        assert.equal(r.state.approval.kind, "held");
    }]),
    ["confirm-draw", logic => {
        const h = held(logic);
        const s = step(logic, h, callback("shown", h.approval, 50)).state;
        for (const [seed, at] of [[h, 750], [s, 749]]) {
            const r = confirmation(logic, seed, at);
            assert.equal(r.effects.find(e => e.kind === "confirm-refused")?.reason, "early");
            assert.equal(r.state.action.kind, "none");
        }
    }],
    ["confirm-expired", logic => {
        const h = held(logic);
        // Extend the independent thinking owner so this row reaches approval expiry.
        h.turn.deadline = 70000;
        const s = step(logic, h, callback("shown", h.approval, 50)).state;
        const r = confirmation(logic, s, 60040);
        assert.equal(r.effects.find(e => e.kind === "confirm-refused")?.reason, "expired");
        assert.equal(r.state.action.kind, "none");
    }],
    ["confirm-replaced", logic => {
        const h = held(logic);
        const stopped = step(logic, h, event("interrupt", 50)).state;
        const r = step(logic, stopped, callback("confirm", h.approval, 750, { source: "key" }));
        assert.equal(r.effects.find(e => e.kind === "confirm-refused")?.reason, "no-hold");
        assert.equal(r.state.action.kind, "none");
    }],
    ["shown-id", logic => {
        const h = held(logic);
        const r = step(logic, h, callback("shown", h.approval, 50, { id: "other" }));
        assert.equal(r.state.approval.shownAt, null);
    }],
    ["cancel-id", logic => {
        const h = held(logic);
        const r = step(logic, h, callback("approval-cancel", h.approval, 50, { id: "other" }));
        assert.equal(r.state.approval.kind, "held");
        assert.equal(step(logic, h, callback("approval-cancel", h.approval, 50)).state.approval.kind, "none");
    }],
    ["key-mode", logic => {
        let s = step(logic, ready(logic), snapshot({ settings: { mode: "toggle" } })).state;
        s = step(logic, s, event("talk-down", 100)).state;
        assert.equal(s.input.kind, "conversation");
        assert.deepEqual(step(logic, s, event("talk-up", 101)), { state: s, effects: [] });
        assert.deepEqual(step(logic, s, event("talk-down", 349)), { state: s, effects: [] });
        const closed = step(logic, s, event("talk-down", 350));
        assert.equal(closed.state.conversation.kind, "ended");
        assert.equal(closed.state.capture.kind, "closing");
    }],
    ["mute-key", logic => {
        const active = listening(logic);
        const muted = step(logic, active, event("mute-toggle", 30));
        assert.equal(muted.state.mute.kind, "muting");
        assert.equal(muted.state.capture.kind, "closing");
        assert.deepEqual(muted.effects.filter(e => e.kind === "mute-store").map(e => e.muted), [true]);
        assert.deepEqual(step(logic, muted.state, event("mute-toggle", 31)), { state: muted.state, effects: [] });
        let s = step(logic, muted.state, callback("capture-closed", muted.state.capture, 32)).state;
        assert.equal(s.mute.kind, "on");
        for (const type of ["talk-down", "talk-up", "toggle", "stop"]) {
            const result = step(logic, s, event(type, 400));
            assert.equal(result.state.mute.kind, "on");
            assert.deepEqual(result.effects, []);
            assert.equal(result.state.capture.kind, "closed");
        }
        const unmuted = step(logic, s, event("mute-toggle", 401));
        assert.equal(unmuted.state.mute.kind, "off");
        assert.equal(unmuted.state.input.kind, "released");
        assert.deepEqual(unmuted.effects.map(e => [e.kind, e.muted]), [["mute-store", false]]);
        s = step(logic, active, snapshot({ at: 30, settings: { mode: "toggle" } })).state;
        assert.equal(s.conversation.kind, "ended", "mode change ends capture demand");
    }],
    ["device-choice-recovery", logic => {
        let s = listening(logic);
        for (let attempt = 0; attempt <= 3; attempt++) {
            s = step(logic, s, callback("capture-failed", s.capture, 50 + attempt, { reason: "device-lost" })).state;
            s = step(logic, s, callback("capture-closed", s.capture, 60 + attempt)).state;
        }
        assert.equal(s.capture.kind, "closed");
        const changed = step(logic, s, snapshot({ at: 70, settings: { microphone: "replacement", speaker: "" } }));
        assert.equal(changed.state.fault.kind, "none");
        assert.equal(changed.state.capture.kind, "opening");
        assert.equal(changed.state.gen, s.gen, "a device selection does not replace the conversation");
        assert.equal(changed.state.settings.microphone, "replacement");
        const provider = { ...s, fault: { kind: "error", reason: "provider-disconnected", retry: 0 } };
        assert.equal(step(logic, provider, snapshot({ at: 70, settings: { microphone: "replacement", speaker: "" } })).state.fault.reason,
            "provider-disconnected", "a device choice cannot clear another owner's fault");
    }],
    ["device-retries", logic => {
        let s = listening(logic);
        for (let attempt = 0; attempt <= 3; attempt++) {
            s = step(logic, s, callback("capture-failed", s.capture, 50 + attempt, { reason: "device-lost" })).state;
            assert.equal(s.capture.kind, "closing");
            assert.equal(s.fault.kind, attempt < 3 ? "retrying" : "error");
            assert.equal(s.fault.retry, Math.min(attempt + 1, 3));
            s = step(logic, s, callback("capture-closed", s.capture, 60 + attempt)).state;
            assert.equal(s.capture.kind, attempt < 3 ? "opening" : "closed");
        }
        assert.equal(logic.phaseOf(s), "error");
    }],
    ["capture-fault", logic => {
        const before = listening(logic);
        const s = step(logic, before, callback("capture-failed", before.capture, 50, { reason: "provider-disconnected" })).state;
        assert.equal(s.fault.reason, "provider-disconnected");
        assert.equal(s.fault.retry, 0);
        assert.equal(s.capture.kind, "closing");
        assert.equal(s.turn.kind, "none");
    }],
    ["playback-fault", logic => {
        const before = speaking(logic);
        const s = step(logic, before, callback("playback-failed", before.playback, 50, { reason: "device-lost" })).state;
        assert.equal(s.fault.reason, "device-lost");
        assert.equal(s.playback.kind, "flushing");
        assert.equal(s.conversation.kind, "ended");
    }],
    ["unknown-event", logic => assert.throws(() => logic.reduce(logic.initial(), event("unknown")),
        { message: "jarvis: session=event type=unknown" })],
    ["event-clock", logic => {
        for (const at of [-1, NaN, Infinity])
            assert.throws(() => logic.reduce(logic.initial(), event("stop", at)), { message: "jarvis: session=clock" });
    }],
    ["invalid-tool-deadline", logic => {
        const s = thinking(logic);
        for (const timeoutMs of [0, -1, Infinity, null, "120"])
            assert.throws(() => logic.reduce(s, callback("tool", s.turn, 40, { tool: "fixture", cancellable: true, timeoutMs })),
                { message: "jarvis: session=tool-deadline tool=fixture" });
    }],
    ["invalid-outcome", logic => {
        const s = acting(logic);
        assert.throws(() => logic.reduce(s, callback("tool-done", s.action, 50, { outcome: "finished" })),
            { message: "jarvis: session=tool-outcome" });
    }],
    ["startup", logic => {
        const s = copy(logic.initial());
        assert.equal(logic.phaseOf(s), "down");
        assert.equal(s.gen, 0);
        assert.equal(s.nextOp, 1);
        assert.equal(s.stale, 0);
        assert.deepEqual(s.capture, { kind: "closed" });
        assert.deepEqual(s.indicator, { kind: "gone" });
    }],
    // Tap or hold (Talk mode hold): a press released within TAP_MS is a tap,
    // which keeps listening until a second press or the end of speech,
    // TAP_SILENCE_MS after the last words; a longer press ends at release.
    ["tap", logic => {
        const tap = 10 + logic.TAP_MS - 1;
        const tapped = () => step(logic, listening(logic), event("talk-up", tap)).state;
        let s = tapped();
        assert.deepEqual([s.input, s.capture.kind], [{ kind: "tapped", deadline: tap + logic.TAP_SILENCE_MS }, "open"],
            "tap: a short press keeps listening until the end of speech");
        assert.equal(logic.phaseOf(s), "listening", "tap: Jarvis listens");
        // A second press sends the words; its release changes nothing.
        const second = step(logic, s, event("talk-down", tap + 100));
        assert.deepEqual([second.state.input, second.state.capture.kind], [{ kind: "released" }, "closing"], "second tap: the press sends the words");
        assert.deepEqual(step(logic, second.state, event("talk-up", tap + 150)).effects, [], "second tap: its release changes nothing");
        // Each partial moves the end of speech; silence after it sends.
        s = step(logic, tapped(), callback("partial", tapped().turn, tap + 1000, { text: "turn on the" })).state;
        assert.equal(s.input.deadline, tap + 1000 + logic.TAP_SILENCE_MS, "end of speech: words move the bound");
        assert.deepEqual(step(logic, s, callback("deadline", s.capture, s.input.deadline - 1)).state.input, s.input,
            "end of speech: words heard within the bound keep listening");
        const ended = step(logic, s, callback("deadline", s.capture, s.input.deadline));
        assert.deepEqual([ended.state.input, ended.state.capture.kind, ended.state.turn.kind, ended.state.fault.kind], [{ kind: "released" }, "closing", "collecting", "none"],
            "end of speech: silence sends the words, no fault");
        // A press released at TAP_MS is a hold, which ends at release.
        const held = step(logic, listening(logic), holdUp()).state;
        assert.deepEqual([held.input, held.capture.kind], [{ kind: "released" }, "closing"], "hold: the release sends the words");
        // A tap before the microphone opened listens from its opening.
        let early = step(logic, ready(logic), event("talk-down")).state;
        early = step(logic, early, event("talk-up", tap)).state;
        early = step(logic, early, callback("capture-opened", early.capture, tap + 20)).state;
        assert.deepEqual(early.input, { kind: "tapped", deadline: tap + 20 + logic.TAP_SILENCE_MS }, "tap before open: the bound starts at the opening");
        // A tap during the start sound, before the microphone opens, keeps
        // the request: the microphone opens once the sound ends.
        let cue = startFeedback(logic).state;
        cue = step(logic, cue, event("talk-up", 11)).state;
        assert.deepEqual(cue.input, { kind: "tapped", deadline: null }, "tap during the start sound: the request stays");
        assert.equal(step(logic, cue, callback("played", cue.playback, 12)).state.capture.kind, "opening",
            "tap during the start sound: the microphone opens after it");
        // A capture that failed leaves no tap: the next press starts afresh.
        let failed = step(logic, listening(logic), callback("capture-failed", listening(logic).capture, 20, { reason: "provider-disconnected" })).state;
        failed = step(logic, failed, callback("capture-closed", failed.capture, 21)).state;
        failed = step(logic, failed, event("talk-up", tap)).state;
        assert.notEqual(failed.input.kind, "tapped", "failed capture: a short release is no tap");
        // A capture that fails after a tap ends it: the next press recovers
        // and listens at once.
        let lost = tapped();
        lost = step(logic, lost, callback("capture-failed", lost.capture, tap + 50, { reason: "provider-disconnected" })).state;
        lost = step(logic, lost, callback("capture-closed", lost.capture, tap + 51)).state;
        const again = step(logic, lost, event("talk-down", tap + 100));
        assert.deepEqual([again.state.fault.kind, again.state.input.kind, again.state.capture.kind, kinds(again).includes("capture-open")],
            ["none", "held", "opening", true], "tap then failed capture: the next press listens");
    }],
    // A tap on a cloud voice is one request. Each adapter's events for one
    // spoken request, as it emits them: Realtime captions the user's words
    // as they come and delegates the item at its transcript; Gemini Live
    // captions the turn and delegates it at its end, before the caption's
    // final.
    ["duplex-tap", logic => {
        const tap = 10 + logic.TAP_MS - 1;
        for (const [adapter, request] of [
            ["realtime", [["transcript", { role: "user", text: "turn on", stage: "partial", rev: 1 }],
                ["transcript", { role: "user", text: "turn on the light", stage: "final", rev: 2 }],
                ["delegation", { id: "item", text: "turn on the light" }]]],
            ["gemini", [["transcript", { role: "user", text: "turn on the light", stage: "partial", rev: 1 }],
                ["delegation", { id: "turn-1", text: "turn on the light" }],
                ["transcript", { role: "user", text: "turn on the light", stage: "final", rev: 2 }]]]
        ]) {
            const label = adapter + ": ";
            const tapped = step(logic, duplexListening(logic), event("talk-up", tap)).state;
            assert.deepEqual([tapped.input, tapped.capture.kind], [{ kind: "tapped", deadline: tap + logic.TAP_SILENCE_MS }, "open"],
                label + "a short tap keeps listening");
            // Silence: no words end the request at the bound, no fault, and
            // nothing reopens the microphone.
            const silent = step(logic, tapped, callback("deadline", tapped.capture, tapped.input.deadline)).state;
            assert.deepEqual([silent.input.kind, silent.capture.kind, silent.fault.kind], ["released", "closing", "none"],
                label + "silence ends the tap");
            assert.equal(step(logic, silent, callback("capture-closed", silent.capture, tapped.input.deadline + 1)).effects
                .some(e => e.kind === "capture-open"), false, label + "silence: the microphone stays closed");
            // Words move the bound; the voice's end of speech hands the
            // request to the brain and closes the microphone; after the
            // reply plays, nothing reopens it.
            let s = tapped, at = tap, opened = [];
            const run = (type, owner, extra) => {
                const r = step(logic, s, callback(type, owner, ++at, extra));
                opened = opened.concat(r.effects.filter(e => e.kind === "capture-open"));
                s = r.state;
            };
            run(...[request[0][0], s.speech, request[0][1]]);
            assert.equal(s.input.deadline, at + logic.TAP_SILENCE_MS, label + "words move the end of speech");
            for (const [type, extra] of request.slice(1)) run(type, s.speech, extra);
            assert.deepEqual([s.input.kind, s.capture.kind, s.turn.kind], ["released", "closing", "thinking"],
                label + "the request goes to the brain and the microphone closes");
            run("capture-closed", s.capture);
            run("speak", s.speech);
            assert.equal(s.playback.kind, "playing", label + "the reply plays");
            run("played", s.playback);
            run("brain-done", s.turn);
            assert.deepEqual([s.playback.kind, s.turn.kind, s.capture.kind, opened], ["idle", "none", "closed", []],
                label + "after the reply the microphone stays closed");
        }
    }],
    ["hold-edges", logic => {
        let s = listening(logic);
        s = step(logic, s, callback("partial", s.turn, 20, { text: "keep this partial" })).state;
        assert.equal(logic.phaseOf(s), "listening");
        const duplicate = step(logic, s, event("talk-down", 21));
        assert.deepEqual(duplicate, { state: s, effects: [] });
        s = step(logic, s, holdUp()).state;
        const twice = step(logic, s, holdUp(10, 1));
        assert.deepEqual(twice, { state: s, effects: [] });
        assert.deepEqual(step(logic, ready(logic), event("talk-up")).effects, []);
        const conversation = listening(logic, true);
        assert.deepEqual(step(logic, conversation, event("talk-up")), { state: conversation, effects: [] });
    }],
    ["hold-replacement", logic => {
        let s = listening(logic);
        const old = copy(s.turn);
        s = step(logic, s, holdUp()).state;
        s = step(logic, s, callback("capture-closed", s.capture, 22)).state;
        s = step(logic, s, event("talk-down", 23)).state;
        s = step(logic, s, callback("capture-opened", s.capture, 24)).state;
        const before = copy(s);
        const late = step(logic, s, callback("final", old, 25, { text: "old transcript" }));
        assert.deepEqual(late.effects, [], "the old final cannot send or close the new hold");
        assert.deepEqual(late.state.capture, before.capture);
        assert.deepEqual(late.state.input, { kind: "held", since: 23 });
        assert.deepEqual(late.state.turn, before.turn);
        assert.equal(late.state.stale, before.stale + 1);
        assert.notEqual(before.turn.op, old.op);
        const fresh = step(logic, late.state, callback("final", before.turn, 26, { text: "new transcript" }));
        assert.equal(fresh.effects.find(e => e.kind === "brain-send").text, "new transcript");
    }],
    ["hold-approval", logic => {
        const s = held(logic);
        const speaking = step(logic, s, event("talk-down", 50));
        assert.deepEqual(speaking.state.approval, s.approval, "Talk records an answer to the existing hold");
        assert.equal(speaking.state.turn.kind, "thinking");
        assert.equal(speaking.state.input.kind, "held");
        const repeated = step(logic, speaking.state, event("talk-down", 51));
        assert.deepEqual(repeated, { state: speaking.state, effects: [] });
        const interrupted = step(logic, s, event("interrupt", 50));
        assert.equal(interrupted.state.approval.kind, "none");
        assert.equal(interrupted.state.turn.kind, "cancelling");
        assert.equal(interrupted.effects.find(e => e.kind === "approval-ended").reason, "interrupt");
    }],
    ["toggle-debounce", logic => {
        const s = step(logic, ready(logic), event("toggle", 100)).state;
        assert.deepEqual(step(logic, s, event("toggle", 349)), { state: s, effects: [] });
        const end = step(logic, s, event("toggle", 350)).state;
        assert.equal(end.conversation.kind, "ended");
        assert.equal(end.gen, s.gen + 1);
    }],
    ["start-generation", logic => {
        const s = ready(logic);
        assert.equal(step(logic, s, event("talk-down")).state.gen, s.gen + 1);
    }],
    ["end-generation", logic => {
        const s = listening(logic);
        const end = step(logic, s, event("stop"));
        assert.equal(end.state.gen, s.gen + 1);
        assert.equal(end.state.conversation.kind, "ended");
        assert.equal(step(logic, end.state, event("stop")).state.gen, end.state.gen);
    }],
    ["stale-op", logic => {
        const s = listening(logic);
        const r = step(logic, s, callback("partial", s.turn, 22, { op: s.turn.op + 1, text: "late" }));
        assert.equal(r.state.turn.partial, "");
        assert.equal(r.state.stale, s.stale + 1);
        assert.deepEqual(r.effects, []);
    }],
    ["stale-gen", logic => {
        const s = step(logic, listening(logic), event("stop")).state;
        const r = step(logic, s, callback("capture-closed", s.capture, 22, { gen: s.capture.gen + 1 }));
        assert.equal(r.state.capture.kind, "closing");
        assert.equal(r.state.stale, s.stale + 1);
    }],
    ["stale-kind", logic => {
        const s = step(logic, thinking(logic), event("cancel", 50)).state;
        const r = step(logic, s, callback("brain-done", s.turn, 51));
        assert.equal(r.state.turn.kind, "cancelling");
        assert.equal(r.state.stale, s.stale + 1);
    }],
    ["mute-gate", logic => {
        const s = step(logic, ready(logic), event("mute")).state;
        assert.equal(s.mute.kind, "on");
        const r = step(logic, s, event("talk-down", 21));
        assert.equal(r.state.capture.kind, "closed", "muted must not listen");
        assert.equal(logic.phaseOf(r.state), "idle");
        assert.deepEqual(r.effects, []);
    }],
    ["gate", logic => {
        for (const locked of [null, true, false]) {
            const s = step(logic, logic.initial(), snapshot({ locked, configured: false })).state;
            const r = step(logic, s, event("talk-down"));
            assert.equal(r.state.conversation.kind, "ended");
            assert.deepEqual(r.effects, []);
        }
    }],
    ["fault-gate", logic => {
        // A capture failure while the key is held leaves the conversation live:
        // only the fault keeps the closed capture from reopening.
        let s = listening(logic);
        s = step(logic, s, callback("capture-failed", s.capture, 20, { reason: "provider-disconnected" })).state;
        const reopened = step(logic, s, callback("capture-closed", s.capture, 21));
        assert.equal(logic.phaseOf(reopened.state), "error");
        assert.equal(kinds(reopened).includes("capture-open"), false, "a fault holds capture while the key is down");
        s = thinking(logic);
        s = step(logic, s, callback("brain-failed", s.turn, 50, { reason: "fixture-failure" })).state;
        const kept = (before, e, name) => {
            const r = step(logic, before, e);
            assert.deepEqual(r.state.fault, before.fault, name + " keeps the fault");
            assert.equal(logic.phaseOf(r.state), "error", name + " keeps the error phase");
            assert.equal(kinds(r).includes("capture-open"), false, name + " opens no capture");
            return r.state;
        };
        for (const e of [event("indicator", 51, { shown: false }), event("indicator", 52, { shown: true }),
            event("stop", 53), event("cancel", 54), event("interrupt", 55), event("talk-up", 56),
            event("mute-toggle", 57), event("mute-toggle", 58), event("mute", 59), event("unmute", 60)])
            s = kept(s, e, e.type);
        assert.equal(s.mute.kind, "off", "the mute round trips end unmuted");
        const muted = step(logic, s, event("mute-toggle", 61)).state;
        assert.equal(muted.mute.kind, "on");
        kept(muted, event("talk-down", 62), "a muted press");
        kept(muted, event("toggle", 63), "a muted toggle");
        const locked = step(logic, s, snapshot({ at: 64, locked: true })).state;
        const lockedPress = step(logic, locked, event("talk-down", 65)).state;
        assert.deepEqual(lockedPress.fault, locked.fault, "a press while the gate is down keeps the fault");
        kept(lockedPress, snapshot({ at: 66 }), "a press while the gate is down");
        // A press inside the toggle debounce is not a press.
        s = step(logic, ready(logic), snapshot({ at: 2, settings: { mode: "toggle" } })).state;
        s = step(logic, s, event("toggle", 10)).state;
        s = step(logic, s, callback("capture-opened", s.capture, 11)).state;
        s = step(logic, s, callback("capture-failed", s.capture, 20, { reason: "provider-disconnected" })).state;
        s = step(logic, s, callback("capture-closed", s.capture, 21)).state;
        assert.equal(s.fault.kind, "error");
        kept(s, event("toggle", 100), "a debounced toggle");
        assert.equal(step(logic, s, event("toggle", 260)).state.fault.kind, "none", "a press after the debounce recovers");
    }],
    ["fault-recovery", logic => {
        const toggleReady = () => step(logic, ready(logic), snapshot({ at: 2, settings: { mode: "toggle" } })).state;
        const opened = (s, press) => {
            s = step(logic, s, event(press, 10)).state;
            return step(logic, s, callback("capture-opened", s.capture, 11)).state;
        };
        const asked = s => {
            s = step(logic, s, callback("final", s.turn, 12, { text: "test" })).state;
            return step(logic, s, callback("capture-closed", s.capture, 13)).state;
        };
        // Each producer of an error fault, ended conversation or still live.
        const failures = {
            "brain-failed": s => step(logic, asked(s), callback("brain-failed", asked(s).turn, 50,
                { reason: "fixture" })).state,
            "thinking-timeout": s => step(logic, asked(s), callback("deadline", asked(s).turn, 60012)).state,
            "collect-failed": s => {
                s = step(logic, s, callback("collect-failed", s.turn, 20, { reason: "fixture" })).state;
                return step(logic, s, callback("capture-closed", s.capture, 21)).state;
            },
            "capture-failed": s => {
                s = step(logic, s, callback("capture-failed", s.capture, 20, { reason: "provider-disconnected" })).state;
                s = step(logic, s, callback("capture-closed", s.capture, 21)).state;
                return step(logic, s, event("talk-up", 22)).state;
            }
        };
        const paths = [["hold", () => ready(logic), "talk-down", "talk-down"], ["toggle", toggleReady, "toggle", "toggle"],
            ["toggle-key", toggleReady, "toggle", "talk-down"]];
        for (const [mode, base, starter, press] of paths) for (const [name, fail] of Object.entries(failures)) {
            const label = mode + " " + name;
            let s = fail(opened(base(), starter));
            // A toggle conversation reopens capture while it thinks; the failure closes it.
            if (s.capture.kind === "closing") s = step(logic, s, callback("capture-closed", s.capture, 60500)).state;
            assert.equal(s.fault.kind, "error", label + " sets an error fault");
            const timedOut = name === "thinking-timeout";
            assert.equal(s.conversation.kind, timedOut || name === "capture-failed" ? "active" : "ended", label);
            const r = step(logic, s, event(press, 61000));
            assert.deepEqual(r.state.fault, { kind: "none" }, label + " press clears the fault");
            assert.equal(r.state.conversation.kind, "active", label + " press starts a conversation");
            assert.ok(r.state.gen > s.gen, label + " press starts a new conversation");
            let started = r;
            if (timedOut) {
                assert.equal(r.state.turn.kind, "cancelling", label + " cancel still drains");
                assert.equal(kinds(r).includes("capture-open"), false, label + " capture waits for the cancel");
                started = step(logic, r.state, callback("cancelled", r.state.turn, 61001));
            }
            const capture = started.effects.find(e => e.kind === "capture-open");
            assert.ok(capture, label + " press opens capture");
            assert.equal(capture.gen, r.state.gen, label + " capture belongs to the new conversation");
        }
        // With no fault a press keeps its ordinary meaning in a live conversation.
        const live = thinking(logic);
        const held = step(logic, live, event("talk-down", 50)).state;
        assert.deepEqual([held.gen, held.conversation.kind], [live.gen, "active"],
            "a healthy hold press interrupts and keeps its conversation");
        const talking = opened(toggleReady(), "toggle");
        const ended = step(logic, talking, event("toggle", 500));
        assert.equal(ended.state.conversation.kind, "ended", "a healthy toggle press ends its conversation");
        assert.equal(kinds(ended).includes("capture-open"), false, "a healthy toggle press starts no conversation");
    }],
    ["indicator-gate", logic => {
        const s = step(logic, logic.initial(), snapshot()).state;
        const r = step(logic, s, event("talk-down"));
        assert.equal(r.state.capture.kind, "closed");
        assert.equal(r.state.input.kind, "held");
        assert.equal(logic.indicatorWanted(s), false, "ready idle maps no indicator");
        assert.equal(logic.indicatorWanted(r.state), true, "demand maps before capture admission");
        const opening = step(logic, r.state, event("indicator", 11, { shown: true }));
        assert.equal(opening.state.capture.kind, "opening");
        const lost = step(logic, opening.state, event("indicator", 12, { shown: false }));
        assert.equal(lost.state.capture.kind, "closing");
        assert.equal(logic.indicatorWanted(lost.state), true, "capture drain retains the visual request");
        const ended = step(logic, lost.state, event("stop", 13));
        const closed = step(logic, ended.state, callback("capture-closed", ended.state.capture, 14));
        assert.equal(logic.indicatorWanted(closed.state), false);
    }],
    ["mute-ack", logic => {
        const s = listening(logic);
        const r = step(logic, s, event("mute"));
        assert.equal(r.state.mute.kind, "muting");
        assert.equal(r.state.capture.kind, "closing");
        assert.deepEqual(kinds(r), ["capture-close"]);
        assert.equal(step(logic, r.state, event("unmute")).state.mute.kind, "muting");
        const ack = step(logic, r.state, callback("capture-closed", r.state.capture));
        assert.equal(ack.state.mute.kind, "on");
        assert.equal(step(logic, ack.state, event("unmute")).state.mute.kind, "off");
    }],
    ["collect-failed", logic => {
        let s = listening(logic);
        s = step(logic, s, event("talk-up", 30)).state;
        s = step(logic, s, callback("capture-closed", s.capture, 31)).state;
        assert.equal(s.turn.kind, "collecting", "a hold release leaves the utterance to its final");
        const r = step(logic, s, callback("collect-failed", s.turn, 32, { reason: "speech=failed" }));
        assert.equal(r.state.turn.kind, "none");
        assert.deepEqual(r.state.fault, { kind: "error", reason: "speech=failed", retry: 0 });
        const stale = step(logic, r.state, callback("collect-failed", s.turn, 33, { reason: "late" }));
        assert.equal(stale.state.stale, r.state.stale + 1, "a retired collection's failure is stale");
    }],
    ["brain-ended", logic => {
        const s = thinking(logic);
        const r = step(logic, s, callback("brain-ended", s.turn, 40, { reason: "brain=context-limit" }));
        assert.equal(r.state.turn.kind, "none");
        assert.equal(r.state.fault.kind, "none", "a clean end leaves no fault");
        assert.equal(r.state.conversation.kind, "ended");
        assert.deepEqual(kinds(r), ["brain-close"]);
        const next = step(logic, r.state, event("talk-down", 41));
        assert.equal(next.state.capture.kind, "opening", "the next conversation starts");
    }],
    ["cancel-ack", logic => {
        const s = thinking(logic);
        const r = step(logic, s, event("cancel", 100));
        assert.equal(r.state.turn.kind, "cancelling");
        assert.equal(r.state.turn.deadline, 2100);
        assert.deepEqual(kinds(r), ["brain-cancel"]);
        const ack = step(logic, r.state, callback("cancelled", r.state.turn, 200));
        assert.equal(ack.state.turn.kind, "none");
        assert.deepEqual(kinds(ack), [], "a live conversation keeps its acknowledged adapter");
        assert.deepEqual(ack.state.brain, s.brain);
        const stopped = step(logic, thinking(logic), event("stop", 100)).state;
        const closed = step(logic, stopped, callback("cancelled", stopped.turn, 200));
        assert.deepEqual(kinds(closed), ["brain-close"], "an ended conversation closes its adapter");
        assert.equal(closed.state.brain.kind, "closed");
    }],
    ["cancel-timeout", logic => {
        let s = step(logic, thinking(logic), event("cancel", 100)).state;
        assert.equal(step(logic, s, callback("deadline", s.turn, 2099)).state.turn.kind, "cancelling");
        const r = step(logic, s, callback("deadline", s.turn, 2100));
        assert.equal(r.state.turn.kind, "none");
        assert.deepEqual(kinds(r), ["brain-close"]);
    }],
    ["lease-close", logic => {
        const s = thinking(logic);
        const r = step(logic, s, event("lease-ended", 100));
        assert.equal(r.state.conversation.kind, "ended");
        assert.equal(r.state.turn.kind, "none");
        assert.deepEqual(kinds(r), ["brain-cancel", "brain-close"]);
        assert.equal(r.effects[1].target, s.turn.op);
    }],
    ["completed-brain-owner", logic => {
        const thinkingState = thinking(logic);
        const owner = copy(thinkingState.brain);
        const completed = step(logic, thinkingState, callback("brain-done", thinkingState.turn, 40)).state;
        assert.equal(completed.turn.kind, "none");
        assert.deepEqual(completed.brain, owner, "response completion is not adapter teardown");
        for (const endEvent of [event("stop", 50), event("lease-ended", 50),
            snapshot({ at: 50, settings: { model: "new" } })]) {
            const r = step(logic, completed, endEvent);
            assert.equal(r.state.brain.kind, "closed");
            const closes = r.effects.filter(e => e.kind === "brain-close");
            assert.equal(closes.length, 1);
            assert.equal(closes[0].gen, owner.gen);
            assert.equal(closes[0].target, owner.op);
            assert.equal(kinds(step(logic, r.state, endEvent)).includes("brain-close"), false);
        }
    }],
    ["reused-brain-owner", logic => {
        let s = thinking(logic);
        const owner = copy(s.brain);
        s = step(logic, s, callback("brain-done", s.turn, 40)).state;
        s = step(logic, s, event("talk-down", 50)).state;
        s = step(logic, s, callback("capture-opened", s.capture, 51)).state;
        const sent = step(logic, s, callback("final", s.turn, 52, { text: "next turn" }));
        assert.notEqual(sent.state.turn.op, owner.op);
        assert.equal(sent.effects.find(e => e.kind === "brain-send").owner, owner.op, "next chained turn retains the conversation's brain owner");
        assert.deepEqual(sent.state.brain, owner);
        s = step(logic, sent.state, callback("brain-done", sent.state.turn, 53)).state;
        const closed = step(logic, s, event("lease-ended", 54));
        assert.equal(closed.effects.find(e => e.kind === "brain-close").target, owner.op);
    }],
    ["thinking-timeout", logic => {
        const s = thinking(logic);
        assert.equal(s.turn.deadline, 60030);
        assert.equal(step(logic, s, callback("deadline", s.turn, 60029)).state.turn.kind, "thinking");
        const r = step(logic, s, callback("deadline", s.turn, 60030));
        assert.equal(r.state.turn.kind, "cancelling");
        assert.equal(r.state.fault.reason, "thinking-timeout");
        assert.equal(r.state.turn.deadline, 62030);
        assert.deepEqual(kinds(r), ["brain-cancel"]);
    }],
    // A running tool call holds its turn's interval past the call's own limit,
    // and a finished one starts a fresh interval for the turn that made it.
    ["thinking-tool-renewal", logic => {
        const long = { tool: "fixture", timeoutMs: 120000, cancellable: true };
        let s = thinking(logic);
        s = step(logic, s, callback("tool", s.turn, 40, long)).state;
        assert.equal(s.turn.deadline, 180040);
        assert.equal(step(logic, s, callback("deadline", s.turn, 100000)).state.turn.kind, "thinking", "a long call outlives one interval");
        const done = step(logic, s, callback("tool-done", s.action, 50000, { outcome: "completed" })).state;
        assert.equal(done.turn.deadline, 110000);
        assert.equal(step(logic, done, callback("deadline", done.turn, 109999)).state.turn.kind, "thinking");
        assert.equal(step(logic, done, callback("deadline", done.turn, 110000)).state.fault.reason, "thinking-timeout");
        // A confirmed call holds the interval the same way.
        let h = thinking(logic);
        h = step(logic, h, callback("approval", h.turn, 40, { id: "long", digest: "a".repeat(64), physical: true,
            text: "Run the fixture", ...long })).state;
        h = step(logic, h, callback("shown", h.approval, 50)).state;
        assert.equal(confirmation(logic, h, 750).state.turn.deadline, 180750);
        // An expired call's late end still renews; a later turn keeps its own interval.
        const expired = acting(logic);
        assert.equal(step(logic, expired, callback("tool-done", expired.action, 50000, { outcome: "completed" })).state.turn.deadline, 110000);
        const later = copy(expired);
        later.turn = { ...later.turn, op: later.nextOp++ };
        assert.equal(step(logic, later, callback("tool-done", later.action, 50000, { outcome: "completed" })).state.turn.deadline,
            later.turn.deadline);
    }],
    ["thinking-approval-expiry", logic => {
        let s = thinking(logic);
        s = step(logic, s, callback("approval", s.turn, 10030, { id: "late-hold", digest: "a".repeat(64),
            physical: true, text: "Delete the fixture", tool: "fixture", timeoutMs: 100, cancellable: true })).state;
        const approval = copy(s.approval);
        s = step(logic, s, callback("shown", approval, 10031)).state;
        assert.equal(s.turn.deadline, 130030);
        assert.equal(s.approval.deadline, 70030);
        const oldDeadline = step(logic, s, callback("deadline", s.turn, 60030));
        assert.deepEqual(oldDeadline, { state: s, effects: [] }, "the earlier thinking deadline cannot retire a hold");
        const confirmed = step(logic, s, callback("confirm", approval, 60030, { source: "key" }));
        assert.equal(confirmed.state.action.kind, "running");
        assert.equal(confirmed.state.turn.deadline, 120130, "a full interval after the confirmed call's limit");
        const expired = step(logic, s, callback("deadline", s.turn, 70030));
        assert.equal(expired.state.approval.kind, "none");
        assert.equal(expired.state.turn.kind, "thinking");
        assert.equal(expired.state.turn.deadline, 130030);
        assert.equal(expired.state.fault.kind, "none");
        assert.equal(expired.effects.find(e => e.kind === "approval-ended").reason, "timeout");
    }],
    ["voice-timing", logic => {
        const h = held(logic, false);
        const s = step(logic, h, callback("shown", h.approval, 2500)).state;
        for (const extra of [{}, {beganAt: 2000, idleAt: 0}, {beganAt: 3000, idleAt: 2001},
            {beganAt: 4500, idleAt: 0}]) {
            assert.equal(confirmation(logic, s, 4000, {source: "voice", ...extra}).effects
                .find(e => e.kind === "confirm-refused")?.reason, "voice-timing");
        }
        const playing = copy(s); playing.playback = duplexSpeaking(logic).playback;
        assert.equal(confirmation(logic, playing, 4000, {source: "voice", beganAt: 3000, idleAt: 0}).state.action.kind, "none");
    }],
    ["approval-end-reasons", logic => {
        for (const [reason, ending] of [
            ["stop", event("stop", 50)], ["mute", event("mute-toggle", 50)],
            ["toggle", event("toggle", 350)], ["lease", event("lease-ended", 50)],
            ["settings", snapshot({ at: 50, settings: { model: "new" } })],
            ["gate", snapshot({ at: 50, locked: true })]
        ]) {
            const r = step(logic, held(logic), ending);
            assert.equal(r.effects.find(e => e.kind === "approval-ended")?.reason, reason);
            assert.equal(r.state.approval.kind, "none");
        }
    }],
    ["late-callback", logic => {
        const s = thinking(logic);
        const r = step(logic, s, callback("brain-done", s.turn, s.turn.deadline));
        assert.equal(r.state.turn.kind, "cancelling");
        assert.equal(r.state.stale, s.stale + 1);
        assert.deepEqual(kinds(r), ["brain-cancel"]);
    }],
    ["approval-timeout", logic => {
        const h = held(logic);
        const s = step(logic, h, callback("brain-done", h.turn, 41)).state;
        assert.equal(s.approval.deadline, 60040);
        assert.equal(step(logic, s, callback("deadline", s.approval, 60039)).state.approval.kind, "held");
        const shown = step(logic, s, callback("shown", s.approval, 200)).state;
        assert.equal(shown.approval.shownAt, 200);
        assert.equal(step(logic, shown, callback("shown", shown.approval, 201)).state.approval.shownAt, 200);
        const r = step(logic, s, callback("deadline", s.approval, 60040));
        assert.equal(r.state.approval.kind, "none");
        assert.equal(r.effects.find(e => e.kind === "approval-ended").reason, "timeout");
    }],
    ["approval-end-capture", logic => {
        function openHeld(id = "held", at = 40) {
            let s = thinking(logic, true);
            assert.equal(s.input.kind, "conversation");
            assert.equal(s.capture.kind, "opening");
            s = step(logic, s, callback("capture-opened", s.capture, 32)).state;
            assert.equal(s.capture.kind, "open");
            const r = step(logic, s, callback("approval", s.turn, at, { id, digest: "a".repeat(64),
                physical: false, text: "Delete the fixture", tool: "fixture", timeoutMs: 100, cancellable: true }));
            assert.deepEqual(kinds(r), ["approval-show"]);
            assert.equal(r.state.capture.kind, "open");
            return r.state;
        }
        function assertSecondHoldOpensNoCapture(state, at) {
            const r = step(logic, state, callback("approval", state.turn, at, { id: "again", digest: "b".repeat(64),
                physical: false, text: "Delete the fixture again", tool: "fixture", timeoutMs: 100, cancellable: true }));
            assert.equal(kinds(r).includes("approval-show"), true);
            assert.equal(kinds(r).includes("capture-open"), false);
            assert.equal(r.state.turn.kind, "thinking");
        }
        let s = openHeld();
        const timedOut = step(logic, s, callback("deadline", s.approval, 60040));
        assert.equal(kinds(timedOut).includes("capture-close"), true, "timeout closes the answer capture");
        assert.equal(timedOut.state.input.kind, "released");
        assert.equal(timedOut.state.approval.kind, "none");
        assert.equal(timedOut.effects.find(e => e.kind === "approval-ended")?.reason, "timeout");
        s = step(logic, timedOut.state, callback("capture-closed", timedOut.state.capture, 60041)).state;
        assertSecondHoldOpensNoCapture(s, 60042);

        s = openHeld();
        const cancelled = step(logic, s, callback("approval-cancel", s.approval, 50));
        assert.equal(kinds(cancelled).includes("capture-close"), true, "cancel closes the answer capture");
        assert.equal(cancelled.state.input.kind, "released");
        assert.equal(cancelled.state.approval.kind, "none");
        assert.equal(cancelled.effects.find(e => e.kind === "approval-ended")?.reason, "cancel");
        s = step(logic, cancelled.state, callback("capture-closed", cancelled.state.capture, 51)).state;
        assertSecondHoldOpensNoCapture(s, 52);
    }],
    ["interrupt", logic => {
        const s = speaking(logic);
        const r = step(logic, s, event("interrupt", 50));
        assert.equal(r.state.playback.kind, "flushing");
        assert.equal(r.state.turn.kind, "cancelling");
        assert.equal(r.state.conversation.kind, "interrupted");
        assert.deepEqual(kinds(r), ["brain-cancel", "playback-flush"]);
        const ack = step(logic, r.state, callback("flushed", r.state.playback, 51));
        assert.equal(ack.state.playback.kind, "idle");
        assert.equal(step(logic, r.state, callback("played", s.playback, 52)).state.stale, s.stale + 1);
    }],
    ["hold-interrupt", logic => {
        const s = speaking(logic);
        const r = step(logic, s, event("talk-down", 50));
        assert.equal(r.state.turn.kind, "cancelling");
        assert.equal(r.state.playback.kind, "flushing");
        assert.equal(r.state.input.kind, "held");
        assert.equal(r.state.capture.kind, "closed");
    }],
    ["cancel-capture-gate", logic => {
        const s = step(logic, thinking(logic), event("talk-down", 50)).state;
        assert.equal(s.turn.kind, "cancelling");
        assert.equal(s.capture.kind, "closed");
        const r = step(logic, s, callback("cancelled", s.turn, 51));
        assert.equal(r.state.capture.kind, "opening");
    }],
    ["tool-cancel", logic => {
        for (const cancellable of [false, true]) {
            const s = acting(logic, cancellable);
            assert.equal(kinds(step(logic, s, event("interrupt", 50))).includes("tool-cancel"), false);
            const stopped = step(logic, s, event("stop", 50));
            assert.equal(kinds(stopped).includes("tool-cancel"), cancellable);
            assert.equal(kinds(step(logic, stopped.state, event("stop", 51))).includes("tool-cancel"), false);
        }
    }],
    ["tool-outcome", logic => {
        for (const outcome of ["completed", "failed", "unknown"]) {
            const s = acting(logic);
            const stopped = step(logic, s, event("stop", 50)).state;
            const r = step(logic, stopped, callback("tool-done", s.action, 51, { outcome }));
            assert.equal(r.state.action.kind, "none");
            assert.equal(r.state.gen, stopped.gen);
            assert.deepEqual(kinds(r), ["tool-outcome"]);
            assert.equal(r.effects[0].outcome, outcome);
            assert.equal(r.effects[0].target, s.action.brain);
            assert.equal(r.effects[0].source, s.action.op);
            assert.equal(r.effects[0].gen, s.action.gen);
        }
    }],
    ["tool-serial", logic => {
        const s = acting(logic);
        assert.deepEqual(step(logic, s, callback("tool", s.turn, 50, { tool: "second", cancellable: true, timeoutMs: 20 })).effects, []);
    }],
    ["tool-held", logic => {
        const s = held(logic);
        assert.deepEqual(step(logic, s, callback("tool", s.turn, 50, { tool: "held", cancellable: true, timeoutMs: 20 })).effects, []);
    }],
    ["tool-interrupted", logic => {
        let s = acting(logic);
        const brain = s.turn;
        s = step(logic, s, event("interrupt", 50)).state;
        s = step(logic, s, callback("cancelled", s.turn, 51)).state;
        s = step(logic, s, callback("tool-done", s.action, 52, { outcome: "completed" })).state;
        assert.equal(kinds(step(logic, s, callback("tool", brain, 53, { tool: "late", timeoutMs: 20, cancellable: true }))).includes("tool-start"), false);
        // A legal overlapping collecting region does not reactivate an
        // interrupted conversation until its own final transcript arrives.
        s.turn = { kind: "thinking", gen: s.gen, op: s.nextOp++, deadline: 100 };
        assert.equal(kinds(step(logic, s, callback("tool", s.turn, 53, { tool: "late", timeoutMs: 20, cancellable: true }))).includes("tool-start"), false);
    }],
    ["tool-deadline", logic => {
        for (const cancellable of [false, true]) {
            const s = acting(logic, cancellable);
            assert.equal(s.action.limit.deadline, 140);
            assert.deepEqual(step(logic, s, callback("deadline", s.action, 139)).effects, []);
            const expired = step(logic, s, callback("deadline", s.action, 140));
            assert.equal(expired.state.action.kind, "running");
            assert.equal(expired.state.action.limit.kind, "expired");
            assert.equal(expired.effects.find(e => e.kind === "tool-outcome").outcome, "unknown");
            assert.equal(kinds(expired).includes("tool-cancel"), cancellable);
            assert.deepEqual(step(logic, expired.state, callback("deadline", s.action, 141)).effects, []);
            assert.equal(step(logic, expired.state, callback("tool-done", s.action, 142, { outcome: "completed" })).state.action.kind, "none");
        }
    }],
    ["half-duplex", logic => {
        let s = thinking(logic, true);
        s = step(logic, s, callback("capture-opened", s.capture, 32)).state;
        const r = step(logic, s, callback("play", s.turn, 40, { interruptible: true }));
        assert.equal(r.state.capture.kind, "closing");
        assert.equal(r.state.playback.admission.kind, "waiting");
        assert.equal(logic.canPlayback(r.state), false, "Audio cannot start before capture closes");
        assert.deepEqual(kinds(r), ["capture-close"], "close before any playback start");
        const ack = step(logic, r.state, callback("capture-closed", r.state.capture, 41));
        assert.deepEqual(kinds(ack), ["playback-start"]);
        assert.equal(ack.state.capture.kind, "closed");
        assert.equal(ack.state.playback.admission.kind, "started");
        assert.equal(logic.canPlayback(ack.state), true);
        const done = step(logic, ack.state, callback("played", ack.state.playback, 42));
        assert.equal(done.state.capture.kind, "opening");
    }],
    ["echo-unavailable", logic => {
        const s = ready(logic);
        assert.equal(s.duplex.kind, "half");
        s.duplex = { kind: "echo" };
        assert.equal(logic.validate(s), false, "the wire cannot claim unsupported echo cancellation");
    }],
    ["phase-priority", logic => {
        let s = held(logic);
        s.capture = { kind: "open", mode: "armed", gen: s.gen, op: s.nextOp++ };
        s.action = acting(logic).action;
        s.playback = speaking(logic).playback;
        assert.equal(logic.phaseOf(s), "confirming");
        s.approval = { kind: "none" };
        assert.equal(logic.phaseOf(s), "acting");
        s.action = { kind: "none" };
        assert.equal(logic.phaseOf(s), "speaking");
        s.playback = { kind: "idle" };
        assert.equal(logic.phaseOf(s), "thinking");
        s.turn = { kind: "none" };
        assert.equal(logic.phaseOf(s), "armed");
        s.capture.mode = "follow-up";
        assert.equal(logic.phaseOf(s), "listening");
        s.fault = { kind: "error", reason: "fixture", retry: 0 };
        assert.equal(logic.phaseOf(s), "error");
        s.gate = { kind: "down", reason: "node" };
        assert.equal(logic.phaseOf(s), "down");
    }]
];
for (const key of ["voiceProvider", "voice", "clonedVoice", "language", "brain", "model", "effort", "fallbacks", "customBaseUrl", "home", "policy", "cloudVision", "account", "voiceAccount"])
    table.push(["settings-" + key, logic => {
        const s = held(logic);
        const r = step(logic, s, snapshot({ at: 50, settings: { [key]: "changed" } }));
        assert.equal(r.state.gen, s.gen + 1);
        assert.equal(r.state.conversation.kind, "ended");
        assert.equal(r.state.approval.kind, "none");
        assert.equal(r.state.turn.kind, "cancelling");
        const ended = r.effects.find(e => e.kind === "approval-ended");
        assert.equal(ended.gen, s.approval.gen);
        assert.equal(ended.target, s.approval.op);
        const idle = step(logic, ready(logic), snapshot({ settings: { [key]: "changed" } })).state;
        assert.equal(idle.gen, 1, "an idle session-setting change also invalidates identity");
        assert.equal(step(logic, idle, snapshot({ settings: { [key]: "changed" } })).state.gen, 1);
    }]);
table.push(["next-setting", logic => {
    const s = held(logic);
    assert.equal(step(logic, s, snapshot({ settings: { microphone: "next" } })).state.gen, s.gen);
}]);
table.push(["duplex-delegation", logic => {
    const s = duplexListening(logic);
    const first = step(logic, s, callback("delegation", s.speech, 30, { id: "old", text: "context" }));
    assert.equal(first.state.turn.kind, "thinking");
    assert.equal(first.state.capture.kind, "open", "delegation does not change the voice model's capture");
    assert.equal(first.effects.find(e => e.kind === "brain-send").delegation, "old");
    const replacement = step(logic, first.state, callback("delegation", first.state.speech, 31, { id: "new", text: "new context" }));
    assert.ok(replacement.effects.some(e => e.kind === "brain-cancel" && e.target === first.state.turn.op));
    assert.ok(replacement.state.turn.op > first.state.turn.op);
    assert.equal(replacement.effects.find(e => e.kind === "brain-send").owner, first.state.brain.op, "replacement delegation retains the conversation's brain owner");
    assert.deepEqual(replacement.state.brain, first.state.brain, "replacement retains the conversation's brain owner");
    const late = step(logic, replacement.state, callback("brain-done", first.state.turn, 32));
    assert.equal(late.state.turn.op, replacement.state.turn.op);
    assert.equal(late.state.stale, replacement.state.stale + 1);
    const ended = step(logic, replacement.state, event("stop", 33)).state;
    const stale = step(logic, ended, callback("delegation", first.state.speech, 34, { id: "old", text: "old context" }));
    assert.equal(stale.effects.some(e => e.kind === "brain-send"), false);
    assert.equal(stale.state.stale, ended.stale + 1);
    const reopened = step(logic, step(logic, s, event("stop", 35)).state, event("talk-down", 36)).state;
    assert.deepEqual([reopened.speech.kind, reopened.speech.op !== s.speech.op], ["open", true]);
    const old = step(logic, reopened, callback("delegation", s.speech, 37, { id: "old", text: "old context" }));
    assert.deepEqual([old.state.stale, old.effects.some(e => e.kind === "brain-send")], [reopened.stale + 1, false],
        "an old session's request is stale while a new session is open");
}], ["duplex-open", logic => {
    const chained = step(logic, ready(logic), event("talk-down"));
    assert.equal(kinds(chained).includes("speech-open"), false, "a chained engine opens no speech session");
    const r = step(logic, duplexReady(logic), event("talk-down"));
    assert.deepEqual(kinds(r), ["speech-open", "capture-open"], "the session opens before capture; no utterance is collected");
    assert.deepEqual([r.state.speech.op, r.state.turn.kind], [r.effects[0].op, "none"]);
    const s = step(logic, r.state, callback("capture-opened", r.state.capture, 11)).state;
    assert.equal(logic.phaseOf(s), "listening");
}], ["duplex-hold-reply", logic => {
    let s = step(logic, duplexListening(logic), callback("speak", duplexListening(logic).speech, 30)).state;
    assert.deepEqual([s.speech.reply.kind, s.capture.kind, s.playback.kind], ["waiting", "open", "idle"],
        "a reply waits while talk is held: half duplex never runs both");
    const released = step(logic, s, holdUp(10, 1));
    assert.equal(released.state.playback.kind, "playing");
    assert.equal(released.state.playback.source, s.speech.op);
    assert.equal(released.state.capture.kind, "closing");
    const started = step(logic, released.state, callback("capture-closed", released.state.capture, 32));
    assert.deepEqual(kinds(started), ["playback-start"]);
}], ["duplex-interrupt", logic => {
    const s = duplexSpeaking(logic);
    const r = step(logic, s, event("talk-down", 40));
    const flush = r.effects.find(e => e.kind === "speech-flush") ?? {};
    assert.deepEqual([flush.gen, flush.target], [s.speech.gen, s.speech.op], "interrupt flushes the engine's reply");
    assert.ok(kinds(r).includes("playback-flush"));
    const queued = step(logic, duplexListening(logic), callback("speak", duplexListening(logic).speech, 30)).state;
    const dropped = step(logic, queued, event("interrupt", 31));
    assert.equal(dropped.state.speech.reply.kind, "none", "an interruption drops a queued reply");
    assert.ok(kinds(dropped).includes("speech-flush"));
}], ["duplex-speak-resumes", logic => {
    const s = step(logic, duplexSpeaking(logic), event("interrupt", 40)).state;
    assert.equal(s.conversation.kind, "interrupted");
    const r = step(logic, s, callback("speak", s.speech, 41)).state;
    assert.equal(r.conversation.kind, "active", "new output answers new input");
    assert.equal(r.speech.reply.kind, "waiting");
}], ["duplex-close", logic => {
    const s = duplexListening(logic);
    const stopped = step(logic, s, event("stop", 40));
    const close = stopped.effects.find(e => e.kind === "speech-close") ?? {};
    assert.deepEqual([close.target, close.mode, stopped.state.speech.kind], [s.speech.op, "graceful", "closed"]);
    assert.equal((step(logic, s, event("lease-ended", 40)).effects.find(e => e.kind === "speech-close") ?? {}).mode, "abort");
}], ["duplex-idle", logic => {
    const s = duplexListening(logic);
    const r = step(logic, s, callback("speech-idle", s.speech, 40));
    assert.deepEqual([r.state.conversation.kind, r.state.speech.kind, r.state.capture.kind], ["ended", "closed", "closing"]);
    assert.ok(r.state.gen > s.gen);
    assert.equal((r.effects.find(e => e.kind === "speech-close") ?? {}).mode, "graceful");
}], ["duplex-idle-in-flight", logic => {
    // The engine's idle report changes nothing while a turn is in flight.
    const listening = duplexListening(logic);
    const thinking = step(logic, listening, callback("delegation", listening.speech, 30, { id: "request", text: "context" })).state;
    const proposal = { id: "held", digest: "a".repeat(64), physical: true, text: "Delete the fixture", tool: "fixture",
        timeoutMs: 100, cancellable: true };
    // A held approval and a running action can each outlive their turn.
    let held = step(logic, thinking, callback("approval", thinking.turn, 40, proposal)).state;
    held = step(logic, held, callback("brain-done", held.turn, 41)).state;
    let acting = step(logic, thinking, callback("tool", thinking.turn, 40, proposal)).state;
    acting = step(logic, acting, callback("brain-done", acting.turn, 41)).state;
    for (const [name, s, flight] of [["a thinking turn", thinking, ["thinking", "none", "none"]],
        ["a held approval", held, ["none", "held", "none"]], ["a running action", acting, ["none", "none", "running"]]]) {
        assert.deepEqual([s.turn.kind, s.approval.kind, s.action.kind], flight, name + " alone is in flight");
        const r = step(logic, s, callback("speech-idle", s.speech, 50));
        assert.deepEqual([r.state.conversation.kind, r.state.speech.kind, r.state.gen, r.effects], ["active", "open", s.gen, []],
            name + " keeps the conversation past the engine's idle wait");
    }
    const expired = step(logic, acting, callback("deadline", acting.action, acting.action.limit.deadline)).state;
    assert.deepEqual([expired.action.kind, expired.action.limit.kind], ["running", "expired"]);
    const r = step(logic, expired, callback("speech-idle", expired.speech, 200));
    assert.deepEqual([r.state.conversation.kind, r.state.speech.kind], ["ended", "closed"],
        "an action past its limit no longer holds the conversation");
}], ["duplex-failed", logic => {
    const s = duplexListening(logic);
    const r = step(logic, s, callback("speech-failed", s.speech, 40, { reason: "live=fixture" }));
    assert.deepEqual(r.state.fault, { kind: "error", reason: "live=fixture", retry: 0 });
    assert.deepEqual([r.state.speech.kind, r.state.conversation.kind, kinds(r).includes("speech-close")], ["closed", "ended", false]);
    assert.equal(logic.phaseOf(r.state), "error");
}], ["duplex-stale", logic => {
    const s = duplexListening(logic);
    const stopped = step(logic, s, event("stop", 40)).state;
    for (const type of ["speak", "speech-due", "transcript", "speech-idle", "speech-failed"]) {
        const r = step(logic, stopped, callback(type, s.speech, 41, { role: "user", text: "late", stage: "partial", rev: 1, reason: "late", due: true }));
        assert.deepEqual([r.state.stale, r.effects], [stopped.stale + 1, []], type + " from a closed session is dropped and counted");
    }
}], ["duplex-transcript", logic => {
    const s = duplexListening(logic);
    const r = step(logic, s, callback("transcript", s.speech, 40, { role: "assistant", text: "Hi", stage: "final", rev: 3 }));
    assert.deepEqual(r.effects.map(e => [e.kind, e.gen, e.role, e.text, e.stage, e.rev]), [["transcript", s.gen, "assistant", "Hi", "final", 3]]);
}], ["chained-transcript", logic => {
    const s = thinking(logic);
    const caption = { role: "assistant", text: "Hi", stage: "partial", rev: 1 };
    const r = step(logic, s, callback("transcript", s.turn, 40, caption));
    assert.deepEqual([r.state.stale, r.effects.map(e => [e.kind, e.gen, e.role, e.text, e.stage, e.rev])],
        [s.stale, [["transcript", s.gen, "assistant", "Hi", "partial", 1]]], "the thinking turn's caption reaches the wire");
    const rows = [
        ["a user caption from the turn", s, s.turn, { ...caption, role: "user" }],
        ["an ended turn's caption", step(logic, s, callback("brain-done", s.turn, 41)).state, s.turn, caption],
        ["a cancelling turn's caption", step(logic, s, event("interrupt", 41)).state, s.turn, caption]
    ];
    for (const [label, before, owner, values] of rows) {
        const late = step(logic, before, callback("transcript", owner, 42, values));
        assert.deepEqual([late.state.stale, late.effects], [before.stale + 1, []], label + " is dropped and counted");
    }
}], ["duplex-reply-due", logic => {
    const thinking = duplexThinking(logic);
    assert.equal(logic.phaseOf(thinking), "thinking");
    const due = step(logic, thinking, callback("speech-due", thinking.speech, 40, { due: true }));
    assert.deepEqual([due.state.speech.reply.kind, due.effects], ["due", []]);
    assert.equal(logic.validate(due.state), true, "a due reply is a wire state");
    assert.equal(logic.phaseOf(due.state), "speaking", "the reply speaks once its words go to the voice");
    const done = step(logic, due.state, callback("brain-done", due.state.turn, 41)).state;
    assert.deepEqual([done.turn.kind, done.playback.kind, logic.phaseOf(done)], ["none", "idle", "speaking"],
        "the finished turn's reply still speaks before its first audio");
    assert.equal(logic.phaseOf(step(logic, thinking, callback("brain-done", thinking.turn, 41)).state), "idle",
        "the same turn with no due reply rests");
    const spoken = step(logic, done, callback("speak", done.speech, 42));
    assert.deepEqual([spoken.state.speech.reply.kind, spoken.state.playback.kind, spoken.state.playback.source],
        ["none", "playing", done.speech.op]);
    assert.ok(kinds(spoken).includes("playback-start"));
    assert.equal(logic.phaseOf(spoken.state), "speaking");
}], ["duplex-due-waiting", logic => {
    const s = step(logic, duplexListening(logic), callback("speak", duplexListening(logic).speech, 30)).state;
    for (const due of [true, false]) {
        const r = step(logic, s, callback("speech-due", s.speech, 31, { due }));
        assert.deepEqual([r.state.speech.reply.kind, r.effects], ["waiting", []], "a waiting reply holds its own audio: due " + due);
    }
}], ["duplex-due-replaced", logic => {
    const s = duplexDue(logic);
    const r = step(logic, s, callback("delegation", s.speech, 50, { id: "next", text: "new context" })).state;
    assert.deepEqual([r.speech.reply.kind, r.turn.kind], ["none", "thinking"], "a new request drops the old request's words");
    assert.equal(logic.phaseOf(step(logic, r, callback("brain-done", r.turn, 51)).state), "idle");
}], ["duplex-due-stop", logic => {
    const s = duplexDue(logic);
    const r = step(logic, s, event("stop", 50));
    const close = r.effects.find(e => e.kind === "speech-close") ?? {};
    assert.deepEqual([close.target, r.state.speech.kind, r.state.conversation.kind], [s.speech.op, "closed", "ended"],
        "stop in the gap ends the reply before any audio");
    assert.equal(kinds(r).includes("playback-start"), false);
    assert.notEqual(logic.phaseOf(r.state), "speaking");
    const late = step(logic, r.state, callback("speak", s.speech, 51));
    assert.deepEqual([late.state.playback.kind, late.state.stale, late.effects], ["idle", r.state.stale + 1, []], "the voice's late audio never plays");
}], ["duplex-due-talk", logic => {
    for (const trigger of [event("talk-down", 50), event("interrupt", 50)]) {
        const s = duplexDue(logic);
        const r = step(logic, s, trigger);
        const flush = r.effects.find(e => e.kind === "speech-flush") ?? {};
        assert.deepEqual([flush.target, r.state.speech.reply.kind], [s.speech.op, "none"], trigger.type + " drops the due words");
        assert.notEqual(logic.phaseOf(r.state), "speaking", trigger.type);
    }
}], ["duplex-due-idle", logic => {
    const s = duplexDue(logic);
    const r = step(logic, s, callback("speech-idle", s.speech, 60050)).state;
    assert.deepEqual([r.conversation.kind, r.speech.kind, logic.phaseOf(r)], ["ended", "closed", "idle"],
        "words whose audio never comes end with the engine's idle wait");
}], ["duplex-due-stale", logic => {
    const s = duplexThinking(logic);
    const r = step(logic, s, callback("speech-due", { gen: s.speech.gen, op: s.speech.op + 1000 }, 40, { due: true }));
    assert.deepEqual([r.state.stale, r.effects, r.state.speech.reply.kind], [s.stale + 1, [], "none"], "another session's due words are stale");
}], ["duplex-due-dropped", logic => {
    const s = duplexDue(logic);
    const r = step(logic, s, callback("speech-due", s.speech, 50, { due: false }));
    assert.deepEqual([r.state.speech.reply.kind, r.state.speech.kind, r.effects], ["none", "open", []],
        "words the voice dropped leave no reply due");
    assert.equal(logic.phaseOf(r.state), "idle");
}], ["duplex-due-shape", logic => {
    const s = duplexThinking(logic);
    for (const due of [undefined, "yes", 1])
        assert.throws(() => logic.reduce(s, callback("speech-due", s.speech, 40, { due })), { message: "jarvis: session=speech-due" }, String(due));
}], ["chained-play-speaks", logic => {
    const s = thinking(logic);
    const played = step(logic, s, callback("play", s.turn, 40, { interruptible: true })).state;
    const done = step(logic, played, callback("brain-done", played.turn, 41)).state;
    assert.deepEqual([logic.phaseOf(played), logic.phaseOf(done), done.speech.kind], ["speaking", "speaking", "closed"],
        "a chained reply speaks from its play, before and after its turn ends");
    assert.equal(step(logic, s, callback("speech-due", s.turn, 40, { due: true })).state.stale, s.stale + 1, "a chained engine has no due reply");
}], ["duplex-engine", logic => {
    const s = duplexListening(logic);
    const r = step(logic, s, snapshot({ at: 40 }));
    assert.deepEqual([r.state.engine.kind, r.state.conversation.kind, r.state.speech.kind], ["chained", "ended", "closed"],
        "an engine change ends the conversation");
    assert.throws(() => logic.reduce(s, { ...snapshot(), engine: undefined }), { message: "jarvis: session=engine" });
}]);
function startFeedback(logic) {
    const s = step(logic, ready(logic), snapshot({ settings: { sounds: true } })).state;
    return step(logic, s, event("talk-down", 10));
}
function workingFeedback(logic) {
    let s = thinking(logic);
    s = step(logic, s, snapshot({ at: 35, settings: { sounds: true } })).state;
    return step(logic, s, callback("feedback", s.turn, 40)).state;
}
function lineFeedback(logic) {
    let s = thinking(logic);
    return step(logic, s, callback("feedback", s.turn, 40, { cue: "line" })).state;
}
function lineReply(logic) {
    const s = lineFeedback(logic);
    return step(logic, s, callback("play", s.turn, 41, { interruptible: true })).state;
}
function pendingFeedbackReply(logic) {
    const s = workingFeedback(logic);
    const flushing = step(logic, s, snapshot({ at: 41, settings: { sounds: false } })).state;
    return step(logic, flushing, callback("play", s.turn, 42, { interruptible: true })).state;
}
// A dictation engine records each utterance through the core: its capture's
// sink sends dictation.start (ChainedEngine captureSink), so capture-open is
// the one effect that can start a recording, and only once the indicator
// is presented. voxtype's tones are the recording's cue: Jarvis plays none.
table.push(["dictation-start-admission", logic => {
    for (const mode of ["hold", "toggle", "always"]) {
        let s = step(logic, logic.initial(), snapshot({ engine: "dictation", settings: { mode, sounds: true } })).state;
        assert.equal(logic.validate(s), true);
        if (mode === "always") {
            assert.deepEqual(kinds(step(logic, s, event("talk-down", 1))), [], "always: no capture before the indicator");
            s = step(logic, s, event("indicator", 2, { shown: true })).state;
            s = step(logic, s, callback("capture-opened", s.capture, 3)).state;
            s = step(logic, s, callback("wake", s.capture, 4)).state;
            s = step(logic, s, event("indicator", 5, { shown: false })).state;
            s = step(logic, s, callback("capture-closed", s.capture, 6)).state;
        }
        const asked = step(logic, s, event(mode === "toggle" ? "toggle" : "talk-down", 10));
        assert.equal(kinds(asked).includes("capture-open"), false, mode + ": the intent alone starts no recording");
        const shown = step(logic, asked.state, event("indicator", 11, { shown: true }));
        assert.deepEqual(kinds(shown), ["capture-open", "collect"], mode + ": the presented indicator admits the recording");
        assert.equal(shown.state.playback.kind, "idle", mode + ": no start sound of Jarvis's own");
    }
}], ["dictation-no-cue", logic => {
    for (const [engine, cued] of [["dictation", false], ["chained", true]]) {
        const s = step(logic, ready(logic), snapshot({ engine, settings: { sounds: true } })).state;
        const pressed = step(logic, s, event("talk-down", 10));
        assert.equal(pressed.state.playback.kind === "feedback" && pressed.state.playback.cue === "start", cued, engine + ": the start sound");
        assert.equal(kinds(pressed).includes("capture-open"), !cued, engine + ": the capture opens at once");
        let armed = step(logic, step(logic, logic.initial(), snapshot({ engine, settings: { mode: "always", sounds: true } })).state,
            event("indicator", 1, { shown: true })).state;
        armed = step(logic, armed, callback("capture-opened", armed.capture, 2)).state;
        assert.equal(logic.phaseOf(armed), "armed", engine + ": Always mode listens for the word");
        const woke = step(logic, armed, callback("wake", armed.capture, 3)).state;
        assert.equal(woke.playback.kind === "feedback", cued, engine + ": the word is answered by the start sound");
    }
}]);
table.push(["feedback-start", logic => {
    const started = startFeedback(logic);
    const s = started.state;
    assert.equal(logic.validate(s), true);
    assert.equal(s.playback.kind, "feedback");
    assert.equal(s.playback.cue, "start");
    assert.equal(logic.phaseOf(s), "idle", "a cue is not assistant speech");
    assert.equal(logic.indicatorWanted(s), true);
    assert.deepEqual(kinds(started), ["playback-start"], "only playback starts before capture");
    assert.equal(logic.canCapture(s), false);
    const played = step(logic, s, callback("played", s.playback, 11));
    assert.deepEqual(kinds(played), ["capture-open", "collect"]);
    // A hold released before the start sound ends opens no microphone.
    const released = step(logic, s, holdUp()).state;
    assert.equal(step(logic, released, callback("played", s.playback, 10 + logic.TAP_MS + 1)).state.capture.kind, "closed");
    for (const value of [false, undefined]) {
        const silent = step(logic, ready(logic), snapshot({ settings: { sounds: value } })).state;
        assert.deepEqual(kinds(step(logic, silent, event("talk-down"))), ["capture-open", "collect"]);
    }
    for (const trigger of [event("mute", 11), event("stop", 11), event("lease-ended", 11),
        snapshot({ at: 11, locked: true, settings: { sounds: true } }),
        snapshot({ at: 11, settings: { sounds: true, brain: "changed" } })]) {
        const stopped = step(logic, s, trigger);
        assert.equal(stopped.state.playback.kind, "flushing", trigger.type);
        assert.ok(kinds(stopped).includes("playback-flush"));
        const late = step(logic, stopped.state, callback("played", s.playback, 12));
        assert.equal(late.state.capture.kind, "closed", "a retired sound never opens capture");
        assert.equal(late.state.stale, stopped.state.stale + 1);
    }
    const disabled = step(logic, s, snapshot({ at: 11, settings: { sounds: false } }));
    assert.equal(disabled.state.playback.kind, "flushing");
    const approval = { ...held(logic), settings: { sounds: true } };
    assert.equal(step(logic, approval, event("talk-down", 50)).state.playback.kind, "idle", "approval answers skip the start cue");
    const busy = { ...speaking(logic), settings: { sounds: true } };
    assert.equal(step(logic, busy, event("talk-down", 50)).state.playback.kind, "flushing", "interrupt cannot replace an unfinished flush with a cue");
    const duplex = step(logic, ready(logic), snapshot({ engine: "duplex", settings: { sounds: true } })).state;
    assert.equal(step(logic, duplex, event("talk-down")).state.playback.kind, "idle");
}], ["feedback-working", logic => {
    let s = thinking(logic);
    s = step(logic, s, snapshot({ at: 35, settings: { sounds: true } })).state;
    const working = step(logic, s, callback("feedback", s.turn, 40));
    assert.equal(working.state.playback.kind, "feedback");
    assert.equal(working.state.playback.cue, "working");
    assert.equal(logic.phaseOf(working.state), "thinking");
    assert.equal(logic.validate(working.state), true);
    const speaking = step(logic, working.state, callback("play", s.turn, 41, { interruptible: true }));
    assert.equal(speaking.state.playback.kind, "playing");
    assert.equal(speaking.state.playback.op, working.state.playback.op, "speech reuses the cue's player");
    assert.equal(kinds(speaking).includes("playback-start"), false);
    for (const [label, state, owner] of [
        ["sounds off", { ...s, settings: { sounds: false } }, s.turn],
        ["busy player", speaking.state, s.turn],
        ["held approval", { ...held(logic), settings: { sounds: true } }, held(logic).turn],
        ["stale operation", s, { ...s.turn, op: s.turn.op + 1 }],
        ["ended turn", step(logic, s, callback("brain-done", s.turn, 41)).state, s.turn]
    ]) assert.equal(kinds(step(logic, state, callback("feedback", owner, 42))).includes("playback-start"), false, label);
}], ["feedback-line", logic => {
    let s = thinking(logic);
    const line = step(logic, s, callback("feedback", s.turn, 40, { cue: "line" }));
    assert.deepEqual([line.state.playback.kind, line.state.playback.cue, logic.phaseOf(line.state), logic.canCapture(line.state)],
        ["feedback", "line", "thinking", false], "a spoken feedback line keeps the thinking phase but closes capture");
    assert.equal(logic.validate(line.state), true);
    const disabled = step(logic, line.state, snapshot({ at: 41, settings: { sounds: false } }));
    assert.equal(disabled.state.playback.kind, "feedback", "sound settings do not flush speech lines");
    const waiting = step(logic, disabled.state, callback("play", s.turn, 42, { interruptible: true }));
    assert.deepEqual([waiting.state.playback.kind, waiting.state.playback.reply.kind, waiting.effects],
        ["feedback", "waiting", []], "reply waits for a line player");
    assert.equal(logic.phaseOf(waiting.state), "speaking", "a reply held behind a line already shows speaking");
    const admitted = step(logic, waiting.state, callback("played", waiting.state.playback, 43));
    assert.deepEqual([admitted.state.playback.kind, admitted.state.playback.source, admitted.state.playback.admission.kind],
        ["playing", s.turn.op, "started"], "line completion starts the waiting reply");
    s = lineFeedback(logic);
    const repeated = step(logic, s, callback("feedback", s.turn, 41, { cue: "line" }));
    assert.deepEqual([repeated.state.playback, repeated.effects], [s.playback, []], "another waiting line uses the same stream");
    const held = step(logic, s, callback("approval", s.turn, 41, { purpose: "release", id: "held", digest: "a".repeat(64),
        physical: false, text: "Fixture", tool: "fixture", timeoutMs: 1000, cancellable: false }));
    assert.equal(held.state.playback.kind, "flushing", "approval flushes a spoken line");
    assert.equal(kinds(held).includes("playback-flush"), true);
    s = lineReply(logic);
    const dropped = step(logic, s, event("talk-down", 42));
    assert.equal(dropped.state.playback.kind, "flushing", "Talk drops a reply waiting behind a line");
    assert.equal(dropped.state.playback.reply.kind, "none");
    const stale = step(logic, thinking(logic), callback("feedback", { ...s.turn, op: s.turn.op + 100 }, 42, { cue: "line" }));
    assert.equal(stale.state.playback.kind, "idle", "stale line callbacks are ignored");
}], ["feedback-approval", logic => {
    for (const purpose of ["action", "release"]) {
        const s = workingFeedback(logic);
        const held = step(logic, s, callback("approval", s.turn, 41, { purpose, id: "held", digest: "a".repeat(64),
            physical: false, text: "Fixture", tool: "fixture", timeoutMs: 1000, cancellable: false }));
        assert.equal(held.state.playback.kind, "flushing");
        assert.equal(kinds(held).includes("playback-flush"), true);
        const talk = step(logic, held.state, event("talk-down", 42)).state;
        assert.equal(talk.capture.kind, "closed");
        const flushed = step(logic, talk, callback("flushed", talk.playback, 43));
        assert.equal(flushed.state.capture.kind, "opening");
        assert.equal(flushed.state.approval.purpose, purpose);
        assert.equal(flushed.state.turn.op, s.turn.op, "approval keeps the brain turn");
    }
}], ["feedback-pending-reply", logic => {
    for (const done of [false, true]) {
        let s = pendingFeedbackReply(logic);
        assert.equal(s.playback.reply.kind, "waiting");
        const source = s.playback.reply.source;
        assert.equal(logic.validate(s), true);
        const stale = step(logic, s, callback("flushed", { ...s.playback, op: s.playback.op + 1 }, 43));
        assert.equal(stale.state.playback.reply.source, source, "a stale flush keeps the reply waiting");
        if (done) s = step(logic, s, callback("brain-done", s.turn, 43)).state;
        const admitted = step(logic, s, callback("flushed", s.playback, 44));
        assert.equal(admitted.state.playback.kind, "playing");
        assert.equal(admitted.state.playback.source, source);
        assert.equal(admitted.state.playback.deadline, done ? 300043 : null);
        assert.deepEqual(kinds(admitted), ["playback-start"]);
        assert.equal(logic.validate(admitted.state), true);
    }
}], ["feedback-pending-cancel", logic => {
    for (const done of [false, true]) for (const trigger of [event("stop", 44), event("cancel", 44), event("interrupt", 44),
        event("lease-ended", 44), event("mute", 44), snapshot({ at: 44, locked: true, settings: { sounds: false } }),
        snapshot({ at: 44, settings: { sounds: false, brain: "changed" } })]) {
        let s = pendingFeedbackReply(logic);
        if (done) s = step(logic, s, callback("brain-done", s.turn, 43)).state;
        const cancelled = step(logic, s, trigger).state;
        assert.equal(cancelled.playback.reply.kind, "none", trigger.type + " retires pending speech");
        const flushed = step(logic, cancelled, callback("flushed", cancelled.playback, 45));
        assert.equal(kinds(flushed).includes("playback-start"), false, "cleanup cannot replay cancelled speech");
    }
}]);
for (const [name, check] of table) { check(Session); }

// Wire shape rules exercise the shared state judge without copying its table.
const shapes = [
    ["record", s => { s.extra = 1; }],
    ["counter", s => { s.stale = 0.5; }],
    ["settings", s => { s.settings = []; }],
    ["toggle-time", s => { s.toggleAt = -1; }],
    ["region-tag", s => { s.capture = { kind: "unknown" }; }],
    ["region-fields", s => { s.capture.extra = 1; }],
    ["owner-counter", s => { s.turn.op = -1; }, thinking],
    ["owner-time", s => { s.turn.deadline = -1; }, thinking],
    ["owner-string", s => { s.turn.partial = 1; }, listening],
    ["owner-bool", s => { s.playback.interruptible = "yes"; }, speaking],
    ["cancel-tag", s => { s.action.cancellation = { kind: "unknown" }; }, acting],
    ["admission-tag", s => { s.playback.admission = { kind: "unknown" }; }, speaking],
    ["limit-tag", s => { s.action.limit = { kind: "unknown" }; }, acting],
    ["limit-time", s => { s.action.limit.deadline = -1; }, acting],
    ["capture-mode", s => { s.capture.mode = "unknown"; }, listening],
    ["gate-reason", s => { s.gate.reason = "unknown"; }, logic => copy(logic.initial())],
    ["speech-reply-tag", s => { s.speech.reply = { kind: "unknown" }; }, duplexListening],
    ["engine-tag", s => { s.engine = { kind: "unknown" }; }],
    ["follow-up-gen", s => { s.followUp.gen = -1; }, logic => ({ ...copy(logic.initial()), followUp: { kind: "asked", gen: 1 } })],
    ["feedback-cue", s => { s.playback.cue = "unknown"; }, logic => startFeedback(logic).state],
    ...[
        ["shape", r => { r.extra = true; }], ["gen", r => { r.gen = -1; }],
        ["source", r => { r.source = 0; }], ["interruptible", r => { r.interruptible = "yes"; }],
        ["deadline", r => { r.deadline = -1; }], ["tag", r => { r.kind = "unknown"; }]
    ].map(([name, mutate]) => ["pending-reply-" + name, s => mutate(s.playback.reply), pendingFeedbackReply]),
    ["pending-reply-null", s => { s.playback.reply = null; }, pendingFeedbackReply],
    ["pending-reply-missing", s => { s.playback.reply = { kind: "waiting" }; }, pendingFeedbackReply]
];
for (const [name, mutate, seed = logic => copy(logic.initial())] of shapes) {
    const check = logic => {
        const s = seed(logic);
        assert.equal(logic.validate(s), true, name + " positive");
        mutate(s);
        assert.equal(logic.validate(s), false, name + " negative");
    };
    check(Session);
    table.push(["wire-" + name, check]);
}

// Every ordered event pair runs from each representative lifetime, including
// a drained old generation. Assertions are invariants, not a second reducer.
const seeds = [ready(Session), listening(Session), thinking(Session), speaking(Session), acting(Session),
    held(Session), step(Session, acting(Session), event("stop", 50)).state,
    step(Session, listening(Session), event("mute", 50)).state, copy(Session.initial()),
    step(Session, ready(Session), event("mute", 50)).state,
    step(Session, ready(Session), event("talk-down", 50)).state,
    step(Session, thinking(Session), event("cancel", 50)).state,
    step(Session, thinking(Session, true), callback("play", thinking(Session, true).turn, 40, { interruptible: true })).state,
    step(Session, acting(Session), callback("deadline", acting(Session).action, 140)).state,
    duplexReady(Session), duplexListening(Session), duplexSpeaking(Session), duplexDue(Session), between(Session), alwaysArmed(Session), alwaysThinking(Session)];
const pairEvents = events.map(type => ({ type, extra: {} })).concat([
    { type: "snapshot", extra: { locked: true } },
    { type: "snapshot", extra: { locked: null } },
    { type: "snapshot", extra: { configured: false } },
    { type: "snapshot", extra: { settings: { brain: "new-account" } } },
    { type: "snapshot", extra: { engine: "duplex" } },
    { type: "speech-due", extra: { due: false } }
]);
function fixtureEvent(type, s, at) {
    const regions = {
        "capture-opened": "capture", "capture-closed": "capture", "capture-failed": "capture",
        "playback-failed": "playback", partial: "turn", final: "turn", "collect-failed": "turn",
        "brain-done": "turn", "brain-failed": "turn", "brain-ended": "turn", cancelled: "turn", play: "turn",
        played: "playback", flushed: "playback", tool: "turn", "tool-done": "action",
        approval: "turn", shown: "approval", confirm: "approval", "approval-cancel": "approval", deadline: "turn",
        speak: "speech", "speech-due": "speech", transcript: "speech", "speech-idle": "speech", "speech-failed": "speech", feedback: "turn", delegation: "speech",
        wake: "capture"
    };
    const owner = s[regions[type]] || {};
    return { ...snapshot(), type, at, shown: true, text: "fixture", reason: "fixture", outcome: "completed",
        tool: "fixture", timeoutMs: 100, cancellable: true, interruptible: true, id: "fixture", digest: "a".repeat(64),
        physical: true, source: "key", role: "user", stage: "partial", rev: 1, ask: null, due: true,
        ...(s.approval.kind === "held" && ["shown", "confirm", "approval-cancel"].includes(type)
            ? { id: s.approval.id, digest: s.approval.digest } : {}),
        gen: owner.gen === undefined ? s.gen : owner.gen, op: owner.op === undefined ? 99999 : owner.op };
}
function invariants(before, e, r) {
    const s = r.state;
    assert.equal(Session.validate(s), true, e.type + " state shape");
    assert.ok(s.gen >= before.gen);
    assert.ok(s.stale >= before.stale);
    assert.ok(s.nextOp >= before.nextOp);
    if (s.capture.kind === "open" || s.capture.kind === "opening") {
        assert.equal(s.gate.kind, "up");
        assert.equal(s.mute.kind, "off");
        assert.equal(s.indicator.kind, "shown");
        assert.notEqual(s.fault.kind, "error");
        assert.notEqual(s.turn.kind, "cancelling");
        assert.equal(s.playback.kind, "idle");
        if (s.engine.kind === "duplex") assert.equal(s.speech.kind, "open", "duplex capture has a speech session");
    }
    if (s.input.kind === "armed") {
        assert.deepEqual([s.settings.mode, s.engine.kind, s.turn.kind, s.playback.kind, s.action.kind, s.approval.kind],
            ["always", "chained", "none", "idle", "none", "none"], "only an idle Always mode listens for the word");
        assert.equal(Session.canEngage(s), true, "only an engaged Always mode listens for the word");
    }
    for (const effect of r.effects) {
        assert.ok(Number.isSafeInteger(effect.op) && effect.op > 0);
        if (effect.kind === "tool-start") {
            assert.equal(s.conversation.kind, "active");
            assert.equal(s.approval.kind, "none");
        }
        if (effect.kind === "playback-start") assert.equal(s.capture.kind, "closed");
        if (effect.kind === "tool-cancel") assert.notEqual(before.action.cancellation.kind, "unavailable");
        if (effect.kind === "collect") assert.equal(s.engine.kind, "chained");
        if (effect.kind === "collect") assert.notEqual(s.input.kind, "armed", "a wake capture collects nothing");
        if (effect.kind === "speech-open") assert.equal(s.engine.kind, "duplex");
    }
}
const createdCallbacks = [
    { effect: "capture-open", type: "capture-failed", check: (s, r) => {
        assert.equal(r.state.capture.kind, "closing");
        assert.equal(r.state.fault.reason, "fixture");
    } },
    { effect: "playback-start", type: "playback-failed", check: (s, r) => {
        assert.equal(r.state.playback.kind, "flushing");
        assert.equal(r.state.fault.reason, "fixture");
    } },
    { effect: "capture-open", type: "capture-opened", check: (s, r, e) => {
        assert.equal(r.state.capture.kind, "open");
        assert.equal(r.state.capture.op, e.op);
    } },
    { effect: "capture-close", type: "capture-closed", check: (s, r) => {
        assert.ok(["closed", "opening"].includes(r.state.capture.kind));
        assert.notEqual(r.state.capture.op, s.capture.op);
    } },
    { effect: "collect", type: "partial", check: (s, r) => {
        assert.equal(r.state.turn.kind, "collecting");
        assert.equal(r.state.turn.partial, "fixture");
    } },
    { effect: "collect", type: "final", check: (s, r) => {
        assert.equal(r.state.turn.kind, "thinking");
        assert.equal(r.effects.find(e => e.kind === "brain-send").text, "fixture");
    } },
    { effect: "collect", type: "collect-failed", check: (s, r) => {
        assert.equal(r.state.turn.kind, "none");
        assert.equal(r.state.fault.reason, "fixture");
        assert.equal(r.state.conversation.kind, "ended");
    } },
    { effect: "brain-send", type: "brain-ended", check: (s, r) => {
        assert.equal(r.state.turn.kind, "none");
        assert.equal(r.state.fault.kind, "none");
        assert.equal(r.state.conversation.kind, "ended");
        assert.equal(r.state.brain.kind, "closed");
    } },
    { effect: "brain-send", type: "brain-done", check: (s, r) => {
        assert.ok(["none", "collecting"].includes(r.state.turn.kind));
        assert.deepEqual(r.state.brain, s.brain);
        assert.equal(kinds(r).includes("brain-close"), false);
    } },
    { effect: "brain-send", type: "brain-failed", check: (s, r) => {
        assert.equal(r.state.fault.reason, "fixture");
        assert.equal(r.state.brain.kind, "closed");
        assert.equal(r.effects.find(e => e.kind === "brain-close").target, s.brain.op);
    } },
    { effect: "brain-send", type: "play", check: (s, r, e) => {
        if (s.playback.kind !== "idle" || s.conversation.kind === "interrupted")
            assert.deepEqual(r.state.playback, s.playback, "an existing reply keeps its owner");
        else {
            assert.equal(r.state.playback.kind, "playing");
            assert.equal(r.state.playback.source, e.op);
        }
    } },
    { effect: "brain-send", type: "tool", check: (s, r) => {
        if (s.action.kind === "none" && s.approval.kind === "none") {
            assert.equal(r.state.action.kind, "running");
            assert.equal(r.effects.find(e => e.kind === "tool-start").tool, "fixture");
        } else assert.equal(kinds(r).includes("tool-start"), false);
    } },
    { effect: "brain-send", type: "approval", check: (s, r) => {
        if (s.action.kind === "none" && s.approval.kind === "none") {
            assert.equal(r.state.approval.kind, "held");
            assert.equal(r.effects.find(e => e.kind === "approval-show").id, "fixture");
        } else assert.equal(kinds(r).includes("approval-show"), false);
    } },
    { effect: "brain-send", type: "deadline", deadline: "turn", check: (s, r) => {
        assert.equal(r.state.turn.kind, "cancelling");
        assert.equal(r.state.fault.reason, "thinking-timeout");
        assert.equal(r.effects.find(e => e.kind === "brain-cancel").target, s.turn.op);
    } },
    { effect: "brain-cancel", type: "cancelled", target: true, check: (s, r) => {
        assert.ok(["none", "collecting"].includes(r.state.turn.kind));
        if (s.conversation.kind === "ended") {
            assert.equal(r.state.brain.kind, "closed");
            assert.equal(r.effects.find(e => e.kind === "brain-close").target, s.brain.op);
        } else {
            assert.deepEqual(r.state.brain, s.brain);
            assert.equal(kinds(r).includes("brain-close"), false);
        }
    } },
    { effect: "brain-cancel", type: "deadline", target: true, deadline: "turn", check: (s, r) => {
        assert.ok(["none", "collecting"].includes(r.state.turn.kind));
        assert.equal(r.state.brain.kind, "closed");
        assert.equal(r.effects.find(e => e.kind === "brain-close").target, s.brain.op);
    } },
    { effect: "speech-open", type: "speak", check: (s, r, e) => assert.ok(r.state.speech.reply.kind === "waiting"
        || (r.state.playback.kind === "playing" && r.state.playback.source === e.op)) },
    { effect: "speech-open", type: "speech-due", check: (s, r) => assert.equal(r.state.speech.reply.kind, "due") },
    { effect: "speech-open", type: "transcript", check: (s, r) => assert.equal(r.effects.find(e => e.kind === "transcript").text, "fixture") },
    { effect: "speech-open", type: "delegation", check: (s, r) => {
        assert.equal(r.state.turn.kind, "thinking");
        assert.equal(r.effects.find(e => e.kind === "brain-send").delegation, "fixture");
    } },
    { effect: "brain-send", type: "transcript", extra: { role: "assistant" },
        check: (s, r) => assert.equal(r.effects.find(e => e.kind === "transcript").role, "assistant") },
    { effect: "speech-open", type: "speech-idle", check: (s, r, e) => {
        assert.equal(r.state.conversation.kind, "ended");
        assert.equal(r.effects.find(e => e.kind === "speech-close").target, e.op);
    } },
    { effect: "speech-open", type: "speech-failed", check: (s, r) => {
        assert.equal(r.state.fault.reason, "fixture");
        assert.equal(r.state.speech.kind, "closed");
    } },
    { effect: "playback-start", type: "played", check: (s, r) => assert.equal(r.state.playback.kind, "idle") },
    { effect: "playback-flush", type: "flushed", check: (s, r) => assert.equal(r.state.playback.kind, "idle") },
    { effect: "tool-start", type: "tool-done", check: (s, r, e) => {
        assert.equal(r.state.action.kind, "none");
        const outcome = r.effects.find(e => e.kind === "tool-outcome");
        assert.equal(outcome.outcome, "completed");
        assert.equal(outcome.source, e.op);
        assert.equal(outcome.target, s.action.brain);
    } },
    { effect: "tool-start", type: "deadline", deadline: "action", check: (s, r, e) => {
        assert.equal(r.state.action.limit.kind, "expired");
        assert.equal(r.effects.find(e => e.kind === "tool-outcome").outcome, "unknown");
        assert.equal(r.effects.find(e => e.kind === "tool-cancel").target, e.op);
    } },
    { effect: "approval-show", type: "shown", check: (s, r) => {
        assert.equal(r.state.approval.kind, "held");
        assert.equal(r.state.approval.shownAt, 201);
    } },
    { effect: "approval-show", type: "deadline", deadline: "approval", check: (s, r, e) => {
        assert.equal(r.state.approval.kind, "none");
        const ended = r.effects.find(e => e.kind === "approval-ended");
        assert.equal(ended.reason, s.turn.kind === "thinking" && s.turn.deadline <= s.approval.deadline
            ? "thinking-timeout" : "timeout");
        assert.equal(ended.target, e.op);
    } }
];

// Discover actual effects, not merely event names. Each matching second
// event uses the identity that the production effect consumer stamps.
function createdPairMatrix(logic) {
    const seen = new Set();
    let count = 0;
    for (const seed of seeds) for (const first of pairEvents) {
        const input = { ...fixtureEvent(first.type, seed, 200), ...first.extra };
        const firstResult = step(logic, seed, input);
        for (const effect of firstResult.effects) {
            // Lease teardown can cancel and close in the same transition.
            // Its acknowledgment is retired, not a new live owner.
            if (effect.kind === "brain-cancel" && firstResult.state.turn.kind !== "cancelling") continue;
            for (const pair of createdCallbacks.filter(row => row.effect === effect.kind)) {
                const before = firstResult.state;
                const second = { ...fixtureEvent(pair.type, before, 201), ...pair.extra };
                second.gen = effect.gen;
                second.op = pair.target ? effect.target : effect.op;
                if (pair.deadline) {
                    const owner = before[pair.deadline];
                    second.at = pair.deadline === "action" ? owner.limit.deadline : owner.deadline;
                }
                const result = step(logic, before, second);
                assert.equal(result.state.stale, before.stale,
                    effect.kind + ":" + pair.type + " must reach a live callback");
                invariants(before, second, result);
                pair.check(before, result, effect);
                seen.add(effect.kind + ":" + pair.type);
                count++;
            }
        }
    }
    // These expected producers/consumers are independent of the discovery
    // table. Omitting one row cannot shrink the coverage claim with it.
    assert.deepEqual([...seen].sort(), [
        "capture-open:capture-opened", "capture-open:capture-failed", "capture-close:capture-closed",
        "collect:partial", "collect:final", "collect:collect-failed", "brain-send:brain-ended",
        "brain-send:brain-done", "brain-send:brain-failed", "brain-send:play", "brain-send:transcript",
        "brain-send:tool", "brain-send:approval", "brain-send:deadline",
        "brain-cancel:cancelled", "brain-cancel:deadline",
        "playback-start:played", "playback-start:playback-failed", "playback-flush:flushed",
        "tool-start:tool-done", "tool-start:deadline",
        "approval-show:shown", "approval-show:deadline",
        "speech-open:speak", "speech-open:speech-due", "speech-open:transcript", "speech-open:speech-idle", "speech-open:speech-failed", "speech-open:delegation"
    ].sort(), "created-owner discovery omitted a producer or deadline owner");
    assert.ok(count >= 18, "created-owner discovery did not complete its required callbacks");
    return count;
}
let pairs = 0;
for (const seed of seeds) for (const a of pairEvents) for (const b of pairEvents) {
    // A,B and B,A appear as distinct rows of this Cartesian product.
    let s = copy(seed);
    const callbacks = [{ ...fixtureEvent(a.type, seed, 100), ...a.extra }, { ...fixtureEvent(b.type, seed, 101), ...b.extra }];
    for (const e of callbacks) {
        const oldState = JSON.stringify(s), oldEvent = JSON.stringify(e);
        const r = step(Session, s, e);
        assert.equal(JSON.stringify(s), oldState, "pure state");
        assert.equal(JSON.stringify(e), oldEvent, "pure event");
        invariants(s, e, r);
        s = r.state;
    }
    pairs++;
}
assert.equal(pairs, 21 * (events.length + 6) ** 2, "matrix discovery floor and exact event set");
const createdPairs = createdPairMatrix(Session);

const parent = path.join(__dirname, "..", "tmp");
fs.mkdirSync(parent, { recursive: true });
const root = fs.mkdtempSync(path.join(parent, "js-"));
const source = fs.readFileSync(file, "utf8");
let controls = 0;
try {
    // Each independent lifetime rule has its own planted defect.
    const mutants = [
        ["check timeout cause", 's.check = { kind: "failed", reason: "check-timeout", device: s.checkSource };', 's.check = { kind: "ready" };', "voice-check-failures"],
        ["check result source", 's.check = { kind: "done", result: e.result, device: s.checkSource };', 's.check = { kind: "done", result: e.result, device: null };', "voice-check-lifetime"],
        ["check source reset", '&& s.check.device !== source) s.check = { kind: "again" };', ') s.check = s.check;', "voice-check-lifetime"],
        ["check source moves", '            end(s, effects, e.at, "check-source", false);\n            s.check = { kind: "again" };\n', "", "voice-check-source-moves", "asks again"],
        ["check kept source", '{ kind: "kept", result: s.check.result, device: s.check.device }', '{ kind: "kept", result: s.check.result, device: null }', "voice-check-lifetime"],
        ["check detector cause", 's.check = { kind: "failed", reason: e.reason, device: s.checkSource };', 's.check = { kind: "ready" };', "voice-check-failures"],
        ["check failure identity", 'if (!live(s, e, "check", ["waiting", "recording", "finishing"]))', 'if (false)', "voice-check-failures"],
        ["check deadline", 'deadline: e.at + VOICE_CHECK_MS', 'deadline: e.at + COLLECTION_TIMEOUT_MS', "voice-check-lifetime"],
        ["check indicator", 'if (!e.shown && s.input.kind === "check" && s.capture.kind !== "closed")', 'if (false)', "voice-check-lifetime"],
        ["check result identity", 'if (!live(s, e, "check", ["finishing"]))', 'if (false)', "voice-check-lifetime"],
        ["check admission", 'if (!canCheck(s)) break;', 'if (false) break;', "voice-check-lifetime"],
        ["collect-limit", 's.turn.kind === "collecting" && s.turn.deadline !== null && at >= s.turn.deadline', 'false && s.turn.kind === "collecting" && s.turn.deadline !== null && at >= s.turn.deadline', "collection-deadline"],
        ["playback-limit", '["playing", "feedback"].indexOf(s.playback.kind) !== -1 && s.playback.deadline !== null && at >= s.playback.deadline', 'false && ["playing", "feedback"].indexOf(s.playback.kind) !== -1 && s.playback.deadline !== null && at >= s.playback.deadline', "playback-deadline"],
        ["feedback-start-sounds", 's.settings.sounds === true && s.engine.kind === "chained"', 'true && s.engine.kind === "chained"', "feedback-start"],
        ["feedback-start-engine", 's.settings.sounds === true && s.engine.kind === "chained"', 's.settings.sounds === true', "feedback-start"],
        ["feedback-start-approval", '&& s.playback.kind === "idle" && s.approval.kind === "none") {', '&& s.playback.kind === "idle") {', "feedback-start"],
        ["feedback-start-busy", '&& s.playback.kind === "idle" && s.approval.kind === "none") {', '&& s.approval.kind === "none") {', "feedback-start"],
        ["feedback-cue-shape", 'if (region === "playback" && r.kind === "feedback" && ["start", "working", "line"].indexOf(r.cue) === -1) return false;', 'void region;', "wire-feedback-cue"],
        ["feedback-disable", 'if (s.settings.sounds !== true && s.playback.kind === "feedback" && s.playback.cue !== "line") flushPlayback(s, effects);', 'void s;', "feedback-start"],
        ["feedback-working-sounds", 'cue !== "line" && s.settings.sounds !== true', 'false', "feedback-working"],
        ["feedback-working-busy", 'if (s.playback.kind !== "idle") break;', 'if (false) break;', "feedback-working"],
        ["feedback-working-held", '|| s.conversation.kind !== "active" || s.approval.kind !== "none") break;', '|| s.conversation.kind !== "active") break;', "feedback-working"],
        ["feedback-line-sounds", 'if ((cue !== "line" && s.settings.sounds !== true) || !canEngage(s)',
            'if ((cue === "line" || s.settings.sounds !== true) || !canEngage(s)', "feedback-line"],
        ["feedback-line-snapshot", 's.settings.sounds !== true && s.playback.kind === "feedback" && s.playback.cue !== "line"',
            's.settings.sounds !== true && s.playback.kind === "feedback"', "feedback-line"],
        ["feedback-line-play", 'if (s.playback.kind === "feedback" && s.playback.cue === "line" && s.playback.source === e.op) {',
            'if (false && s.playback.kind === "feedback" && s.playback.cue === "line" && s.playback.source === e.op) {', "feedback-line"],
        ["feedback-working-play", 'if (s.playback.kind === "feedback" && s.playback.cue === "working" && s.playback.source === e.op) {',
            'if (false && s.playback.kind === "feedback" && s.playback.cue === "working" && s.playback.source === e.op) {', "feedback-working"],
        ["feedback-approval-flush", 'if (s.playback.kind === "feedback" && (s.playback.cue === "working"\n                || s.playback.cue === "line" && s.playback.reply.kind === "none")) flushPlayback(s, effects);',
            'if (false) flushPlayback(s, effects);', "feedback-approval"],
        ["pending-play-admission", 'if (s.playback.kind === "flushing" && s.conversation.kind === "active") {',
            'if (false && s.playback.kind === "flushing" && s.conversation.kind === "active") {', "feedback-pending-reply"],
        ["pending-flush-admission", 'reply.kind === "waiting" && reply.gen === s.gen',
            'false && reply.kind === "waiting" && reply.gen === s.gen', "feedback-pending-reply"],
        ["pending-completion-deadline", 's.playback.reply.deadline = e.at + PLAYBACK_TIMEOUT_MS;',
            's.playback.reply.deadline = null;', "feedback-pending-reply"],
        ["pending-cancel", 'function cancelTurn(s, effects, at) {\n    if (s.playback.kind === "flushing") s.playback.reply = { kind: "none" };',
            'function cancelTurn(s, effects, at) {\n    if (false) s.playback.reply = { kind: "none" };', "feedback-pending-cancel"],
        ["pending-shape", '!exact(r[f], ["kind", "gen", "source", "interruptible", "deadline"])',
            'false', "wire-pending-reply-shape"],
        ["pending-gen", '!Number.isSafeInteger(r[f].gen) || r[f].gen < 0',
            'false', "wire-pending-reply-gen"],
        ["pending-source", '!Number.isSafeInteger(r[f].source) || r[f].source < 1',
            'false', "wire-pending-reply-source"],
        ["pending-interruptible", 'typeof r[f].interruptible !== "boolean"',
            'false', "wire-pending-reply-interruptible"],
        ["pending-deadline", '(r[f].deadline !== null && (!Number.isFinite(r[f].deadline) || r[f].deadline < 0))',
            'false', "wire-pending-reply-deadline"],
        ["confirm-id", "e.id !== approval.id", "(false && e.id !== approval.id)", "confirm-id"],
        ["confirm-digest", "e.digest !== approval.digest", "(false && e.digest !== approval.digest)", "confirm-digest"],
        ["confirm-generation", "e.gen !== approval.gen", "(false && e.gen !== approval.gen)", "confirm-generation"],
        ["confirm-source", '["key", "button", "voice"].indexOf(e.source) === -1',
            'false && ["key", "button", "voice"].indexOf(e.source) === -1', "confirm-source"],
        ["confirm-drawn", ": approval.shownAt === null ||", ": (false && approval.shownAt === null) ||", "confirm-draw"],
        ["confirm-draw-delay", "e.at - approval.shownAt < APPROVAL_DRAW_MS",
            "(false && e.at - approval.shownAt < APPROVAL_DRAW_MS)", "confirm-draw"],
        ["confirm-physical", 'e.source === "voice" && approval.physical',
            'false && e.source === "voice" && approval.physical', "confirm-physical"],
        ["voice-after-draw", "e.beganAt < approval.shownAt", "false", "voice-timing"],
        ["voice-before-final", "e.beganAt > e.at", "false", "voice-timing"],
        ["voice-playback-quiet", "e.beganAt - e.idleAt < VOICE_QUIET_MS", "false", "voice-timing"],
        ["voice-playback-idle", 's.playback.kind !== "idle") ? "voice-timing"', 'false) ? "voice-timing"', "voice-timing"],
        ["confirm-once", 's.approval = { kind: "none" };\n        if (s.turn.kind',
            's.approval = approval;\n        if (s.turn.kind', "confirmation"],
        ["confirm-replaced", 'dropApproval(s, effects, "interrupt", at);',
            'if (false) dropApproval(s, effects, "interrupt", at);', "confirm-replaced"],
        ["shown-id", 'if (e.id !== s.approval.id) { stale(s); break; }',
            'if (false && e.id !== s.approval.id) { stale(s); break; }', "shown-id"],
        ["cancel-id", 'if (e.id !== s.approval.id || e.gen !== s.approval.gen)',
            'if (false && (e.id !== s.approval.id || e.gen !== s.approval.gen))', "cancel-id"],
        ["follow-up-asked", 'voiceRequest === true && s.settings.mode === "always" && s.engine.kind !== "duplex"',
            'false && voiceRequest === true && s.settings.mode === "always" && s.engine.kind !== "duplex"', "always-follow-up-orders"],
        ["follow-up-spoken", 'if (s.playback.kind === "playing" && s.followUp.kind === "asked" && s.followUp.gen === s.gen)\n            s.followUp = { kind: "spoken", gen: s.gen };',
            'if (false)\n            s.followUp = { kind: "spoken", gen: s.gen };', "always-follow-up-orders"],
        ["follow-up-open", '&& s.engine.kind !== "duplex")\n            s.input = { kind: "follow-up" };',
            '&& s.engine.kind !== "duplex")\n            void s;', "always-follow-up-orders"],
        ["follow-up-no-reply", 's.input = { kind: "follow-up" };\n        s.followUp = { kind: "none" };',
            's.input = { kind: "follow-up" };\n        if (s.followUp.kind === "spoken") s.followUp = { kind: "none" };', "always-follow-up-refusals"],
        ["follow-up-overrun", 's.input = { kind: "follow-up" };\n        s.followUp = { kind: "none" };',
            's.input = { kind: "follow-up" };\n        if (s.input.kind === "follow-up") s.followUp = { kind: "none" };', "always-follow-up-overrun"],
        ["follow-up-stop-drops", 's.input = { kind: "follow-up" };\n        s.followUp = { kind: "none" };',
            's.input = { kind: "follow-up" };\n        if (s.input.kind === "follow-up") s.followUp = { kind: "none" };', "always-follow-up-closes"],
        ["follow-up-bound", 's.input.kind === "woken" || s.input.kind === "follow-up" ? e.at + WAKE_SILENCE_MS : null;',
            's.input.kind === "woken" ? e.at + WAKE_SILENCE_MS : null;', "always-follow-up-orders"],
        ["follow-up-partial", 'if (s.input.kind === "woken" || s.input.kind === "follow-up") {',
            'if (s.input.kind === "woken") {', "always-follow-up-final"],
        ["follow-up-silence", 'else if (s.input.kind === "follow-up") {\n            s.input = { kind: "released" };\n            closeCapture(s, effects);\n            s.turn = { kind: "none" };\n        }',
            'else if (false) {\n            s.input = { kind: "released" };\n            closeCapture(s, effects);\n            s.turn = { kind: "none" };\n        }', "always-follow-up-silence"],
        ["follow-up-talk-closes", 's.input.kind === "conversation" || s.input.kind === "woken" || s.input.kind === "follow-up"',
            's.input.kind === "conversation" || s.input.kind === "woken"', "always-follow-up-closes"],
        ["follow-up-console", 'commitUserText(s, effects, e.text, e.at, 1, false);',
            'commitUserText(s, effects, e.text, e.at, 1, true);', "always-follow-up-refusals"],
        ["final-caption", 'commitUserText(s, effects, e.text, e.at, e.op, true);',
            'void e;', "final-caption"],
        ["caption-final-text", 'userTranscript(s, effects, text, rev);',
            'userTranscript(s, effects, s.turn.partial, rev);', "final-caption"],
        ["caption-silence", 'if (shown !== "") effect', 'if (true) effect', "final-caption"],
        ["key-mode", 'if (s.settings.mode === "toggle") { toggle(s, effects, e.at); break; }',
            'if (false) { toggle(s, effects, e.at); break; }', "key-mode"],
        ["mute-key-store", 'effect(s, effects, "mute-store", { muted: true });',
            'void effects;', "mute-key"],
        ["initial", "gen: 0, nextOp: 1, stale: 0, settings: {},",
            "gen: 1, nextOp: 1, stale: 0, settings: {},", "startup"],
        ["stale-op", "e.op === owner.op", "(true || e.op === owner.op)", "stale-op"],
        ["stale-gen", "e.gen === owner.gen", "(true || e.gen === owner.gen)", "stale-gen"],
        ["stale-kind", 'kinds.indexOf(owner.kind) !== -1', '(true || kinds.indexOf(owner.kind) !== -1)', "stale-kind"],
        ["mute", 's.mute.kind === "off" && s.fault', '(true || s.mute.kind === "off") && s.fault', "mute-gate"],
        ["gate", 's.gate.kind === "up" && s.mute', '(true || s.gate.kind === "up") && s.mute', "gate"],
        ["fault", 's.mute.kind === "off" && s.fault.kind !== "error";',
            's.mute.kind === "off" && (true || s.fault.kind !== "error");', "fault-gate"],
        ["recover-hold", 'recover(s, effects, e.at);\n        interrupt(s, effects, e.at);',
            'interrupt(s, effects, e.at);', "fault-recovery"],
        ["recover-toggle", 'return;\n    recover(s, effects, at);\n    if (!canEngage(s)) return;\n    s.toggleAt = at;\n    if (s.conversation',
            'return;\n    if (false) recover(s, effects, at);\n    if (!canEngage(s)) return;\n    s.toggleAt = at;\n    if (s.conversation', "fault-recovery"],
        ["recover-debounce", 'if (bounced(s, at)) return;\n    recover(s, effects, at);',
            'recover(s, effects, at);\n    if (bounced(s, at)) return;', "fault-gate"],
        ["recover-mute", ' || s.mute.kind !== "off") return;', ') return;', "fault-gate"],
        ["recover-gate", 's.fault.kind !== "error" || s.gate.kind !== "up" ||', 's.fault.kind !== "error" ||', "fault-gate"],
        ["recover-fault", 's.fault = { kind: "none" };\n}', '}', "fault-recovery"],
        ["recover-error-only", 'if (s.fault.kind !== "error" || s.gate', 'if (false || s.gate', "fault-recovery"],
        ["recover-end", 'end(s, effects, at, "recover", false);', 'void at;', "fault-recovery"],
        ["device-retry-limit", 'e.reason === "device-lost" && retry < 3',
            'e.reason === "device-lost" && retry < 4', "device-retries"],
        ["device-choice-recovery", 'if (devicesChanged && s.fault.kind === "error" && s.fault.reason === "device-lost")',
            'if (false && devicesChanged && s.fault.kind === "error" && s.fault.reason === "device-lost")', "device-choice-recovery"],
        ["capture-fault", 'reason: e.reason, retry: retry };',
            'reason: "wrong-cause", retry: retry };', "capture-fault"],
        ["playback-fault", 'end(s, effects, e.at, "playback-failed", false);',
            'if (false) end(s, effects, e.at, "playback-failed", false);', "playback-fault"],
        ["indicator", 's.indicator.kind === "shown"', '(true || s.indicator.kind === "shown")', "indicator-gate"],
        ["dictation-intent-start", 's.indicator.kind === "shown"', '(true || s.indicator.kind === "shown")', "dictation-start-admission"],
        ["dictation-cue", 's.settings.sounds === true && s.engine.kind === "chained"', 's.settings.sounds === true && s.engine.kind !== "duplex"', "dictation-no-cue"],
        ["indicator-demand", 'return canEngage(s) && (s.input.kind === "armed"\n        || s.conversation.kind !== "ended" && s.input.kind !== "released");',
            'return false;', "indicator-gate"],
        ["hold", 'if (s.input.kind === "held") break;',
            'if (false && s.input.kind === "held") break;', "hold-edges"],
        ["retire-collect", 'else if (s.turn.kind === "collecting") s.turn = { kind: "none" };',
            'else if (false && s.turn.kind === "collecting") s.turn = { kind: "none" };', "hold-replacement"],
        ["retire-approval", 'dropApproval(s, effects, "interrupt", at);',
            'if (false) dropApproval(s, effects, "interrupt", at);', "hold-approval"],
        ["completed-brain", 'if (s.turn.kind === "none") closeBrain(s, effects);',
            'if (false && s.turn.kind === "none") closeBrain(s, effects);', "completed-brain-owner"],
        ["retain-brain", 'var brain = effect(s, effects, "brain-send", values);\n    if (s.brain.kind === "closed")',
            'var brain = effect(s, effects, "brain-send", values);\n    if (true)', "reused-brain-owner", "next chained turn retains the conversation's brain owner"],
        ["retain-delegation-brain", 'var brain = effect(s, effects, "brain-send", values);\n    if (s.brain.kind === "closed")',
            'var brain = effect(s, effects, "brain-send", values);\n    if (true)', "duplex-delegation", "replacement delegation retains the conversation's brain owner"],
        ["retain-relay-brain", 'var brain = effect(s, effects, "brain-send", values);\n    if (s.brain.kind === "closed")',
            'var brain = effect(s, effects, "brain-send", values);\n    if (true)', "relay-idle", "the relay turn keeps the conversation's brain owner"],
        ["relay-judge", 'if (relayRefusal(s) !== null) { stale(s); break; }', 'if (false) { stale(s); break; }', "relay-refusals"],
        ["relay-busy", '            || s.input.kind !== "released" || s.capture.kind !== "closed") return "busy";',
            '            || s.capture.kind !== "closed") return "busy";', "relay-refusals"],
        ["relay-ended", 'if (s.conversation.kind === "ended") return "ended";', '', "relay-refusals"],
        ["relay-no-caption", 'think(s, effects, { relay: { text: e.text, ask: e.ask } }, e.at);',
            'userTranscript(s, effects, e.text, 1);\n        think(s, effects, { relay: { text: e.text, ask: e.ask } }, e.at);', "relay-idle"],
        ["release", 'if (s.input.kind !== "held") break;', 'if (false && s.input.kind !== "held") break;', "hold-edges"],
        ["toggle", "at - s.toggleAt < 250", "at - s.toggleAt < 249", "toggle-debounce"],
        ["start-gen", 's.gen++;\n        s.conversation = { kind: "active" };', 's.gen += 0;\n        s.conversation = { kind: "active" };', "start-generation"],
        ["end-gen", 's.gen++;\n        s.conversation = { kind: "ended" };', 's.gen += 0;\n        s.conversation = { kind: "ended" };', "end-generation"],
        ["settings", 'a[key] !== b[key]', '(false && a[key] !== b[key])', "settings-model"],
        ["settings-voice-account", '"account", "voiceAccount"]', '"account"]', "settings-voiceAccount"],
        ["settings-voice", '"voiceProvider", "voice", "clonedVoice"', '"voiceProvider", "clonedVoice"', "settings-voice"],
        ["settings-cloned-voice", '"voice", "clonedVoice", "language"', '"voice", "language"', "settings-clonedVoice"],
        ["settings-home", '"customBaseUrl", "home", "policy"', '"customBaseUrl", "policy"', "settings-home"],
        ["settings-effort", '"model", "effort", "fallbacks", "customBaseUrl"', '"model", "fallbacks", "customBaseUrl"', "settings-effort"],
        ["settings-fallbacks", '"effort", "fallbacks", "customBaseUrl"', '"effort", "customBaseUrl"', "settings-fallbacks"],
        ["settings-cloud-vision", '"policy", "cloudVision", "account", "voiceAccount"]', '"policy", "account", "voiceAccount"]', "settings-cloudVision"],
        ["mute-ack", 's.mute.kind === "muting" && s.capture.kind === "closed"', 's.mute.kind === "muting"', "mute-ack"],
        ["cancel-ack", 'live(s, e, "turn", ["cancelling"])', 'live(s, e, "turn", ["none"])', "cancel-ack"],
        ["cancel-ack-retains", 'if (s.conversation.kind === "ended") closeBrain(s, effects);\n        s.turn',
            'closeBrain(s, effects);\n        s.turn', "cancel-ack"],
        ["cancel-ack-ended", 'if (s.conversation.kind === "ended") closeBrain(s, effects);\n        s.turn',
            'if (false) closeBrain(s, effects);\n        s.turn', "cancel-ack"],
        ["cancel-bound", "deadline: at + 2000", "deadline: at + 2001", "cancel-timeout"],
        ["collect-failure", 's.fault = { kind: "error", reason: e.reason, retry: 0 };\n        end(s, effects, e.at, "collect-failed", false);',
            'end(s, effects, e.at, "collect-failed", false);', "collect-failed"],
        ["collect-failure-live", 'if (!live(s, e, "turn", ["collecting"])) { stale(s); break; }\n        s.turn = { kind: "none" };\n        s.fault',
            'if (false) { stale(s); break; }\n        s.turn = { kind: "none" };\n        s.fault', "collect-failed"],
        ["brain-ended-clean", 's.turn = { kind: "none" };\n        end(s, effects, e.at, e.reason, false);',
            's.turn = { kind: "none" };\n        s.fault = { kind: "error", reason: e.reason, retry: 0 };\n        end(s, effects, e.at, e.reason, false);', "brain-ended"],
        ["think-bound", 's.turn.kind === "thinking" && s.approval.kind !== "held" && at >= s.turn.deadline',
            's.turn.kind === "thinking" && s.approval.kind !== "held" && false && at >= s.turn.deadline', "thinking-timeout"],
        ["thinking-tool-renewal", 'if (s.turn.kind === "thinking" && s.turn.op === s.action.brain) s.turn.deadline = e.at + RESPONSE_TIMEOUT_MS;',
            '', "thinking-tool-renewal"],
        ["thinking-tool-owner", ' && s.turn.op === s.action.brain) s.turn.deadline', ') s.turn.deadline', "thinking-tool-renewal"],
        ["thinking-tool-hold", '        holdThinking(s);\n        break;\n    case "tool-done":', '        break;\n    case "tool-done":', "thinking-tool-renewal"],
        ["thinking-confirm-hold", '        holdThinking(s);\n        break;\n    }\n    case "approval-cancel":', '        break;\n    }\n    case "approval-cancel":', "thinking-tool-renewal"],
        ["thinking-approval-expiry", 's.turn.deadline = s.approval.deadline + RESPONSE_TIMEOUT_MS;',
            's.turn.deadline = e.at;', "thinking-approval-expiry"],
        ["approval-end-reasons", 'dropApproval(s, effects, reason, at);',
            'dropApproval(s, effects, "thinking-timeout", at);', "approval-end-reasons"],
        ["approval-bound", 's.approval.kind === "held" && at >= s.approval.deadline',
            's.approval.kind === "held" && false && at >= s.approval.deadline', "approval-timeout"],
        ["approval-timeout-capture-close", 'if (s.approval.kind === "held" && at >= s.approval.deadline) {\n        dropApproval(s, effects, "timeout", at);\n        s.input = { kind: "released" };\n        closeCapture(s, effects);\n    }',
            'if (s.approval.kind === "held" && at >= s.approval.deadline) {\n        dropApproval(s, effects, "timeout", at);\n    }', "approval-end-capture", "timeout closes the answer capture"],
        ["approval-cancel-capture-close", 'dropApproval(s, effects, "cancel", e.at);\n        s.input = { kind: "released" };\n        closeCapture(s, effects);',
            'dropApproval(s, effects, "cancel", e.at);', "approval-end-capture", "cancel closes the answer capture"],
        ["late-callback", 'if (e.type !== "deadline") expire(s, effects, e.at);',
            'if (false && e.type !== "deadline") expire(s, effects, e.at);', "late-callback"],
        ["lease-close", 'if (s.brain.kind === "closed") return;',
            'if (true || s.brain.kind === "closed") return;', "lease-close"],
        ["stale-count", 'function stale(s) { s.stale++; }', 'function stale(s) { if (false) s.stale++; }', "stale-op"],
        ["flush", 'if (["playing", "feedback"].indexOf(s.playback.kind) === -1) return;', 'if (true || ["playing", "feedback"].indexOf(s.playback.kind) === -1) return;', "interrupt"],
        ["cancel-capture", 's.turn.kind !== "cancelling"', '(true || s.turn.kind !== "cancelling")', "cancel-capture-gate"],
        ["tool-cancel", 's.action.kind !== "running" || s.action.cancellation.kind !== "available"',
            's.action.kind !== "running" || (false && s.action.cancellation.kind !== "available")', "tool-cancel"],
        ["outcome", 'outcome: e.outcome', 'outcome: "unknown"', "tool-outcome"],
        ["serial", 's.conversation.kind === "active" && s.action.kind === "none" && s.approval', 's.conversation.kind === "active" && (true || s.action.kind === "none") && s.approval', "tool-serial"],
        ["held", 's.approval.kind === "none";', '(true || s.approval.kind === "none");', "tool-held"],
        ["interrupt-tools", 's.conversation.kind === "active" && s.action', '(true || s.conversation.kind === "active") && s.action', "tool-interrupted"],
        ["tool-bound", "at >= s.action.limit.deadline", "false && at >= s.action.limit.deadline", "tool-deadline"],
        ["half", '"shown"\n        && s.playback.kind === "idle"', '"shown"\n        && (true || s.playback.kind === "idle")', "half-duplex"],
        ["play-after-close", '&& s.capture.kind === "closed";', '&& (true || s.capture.kind === "closed");', "half-duplex"],
        ["echo-state", 'duplex: { half: "" }', 'duplex: { half: "", echo: "" }', "echo-unavailable"],
        ["phase", 'if (s.approval.kind === "held") return "confirming";', 'if (false && s.approval.kind === "held") return "confirming";', "phase-priority"],
        ["speech-open", 'if (s.engine.kind === "duplex" && s.speech.kind === "closed" && canCapture(s)) {', "if (false) {", "duplex-open"],
        ["delegation-cancel", 'cancelTurn(s, effects, e.at);\n            dropApproval(s, effects, "replaced", e.at);',
            'dropApproval(s, effects, "replaced", e.at);', "duplex-delegation"],
        ["delegation-stale", 's.engine.kind !== "duplex" || !live(s, e, "speech", ["open"])', 's.engine.kind !== "duplex" || s.speech.kind !== "open"', "duplex-delegation"],
        ["duplex-collect", 'if (s.engine.kind !== "duplex" && canCapture(s)', "if (canCapture(s)", "duplex-open"],
        ["held-reply", '&& s.input.kind !== "held";', ";", "duplex-hold-reply"],
        ["speech-flush", 'effect(s, effects, "speech-flush", { gen: s.speech.gen, target: s.speech.op });', "", "duplex-interrupt"],
        ["reply-drop", 'target: s.speech.op });\n        s.speech.reply = { kind: "none" };', "target: s.speech.op });", "duplex-interrupt"],
        ["speak-resume", 'if (s.conversation.kind === "interrupted") s.conversation = { kind: "active" };\n        s.speech.reply', "s.speech.reply", "duplex-speak-resumes"],
        ["speech-close", 'closeSpeech(s, effects, reason === "lease" ? "abort" : "graceful");', "", "duplex-close"],
        ["speech-abort", '"abort" : "graceful"', '"graceful" : "graceful"', "duplex-close"],
        ["speech-idle", 'end(s, effects, e.at, "idle", false);', "", "duplex-idle"],
        ["idle-thinking", 'if (s.turn.kind === "thinking" || s.approval.kind === "held"\n', 'if (s.approval.kind === "held"\n',
            "duplex-idle-in-flight", "a thinking turn keeps"],
        ["idle-approval", 'if (s.turn.kind === "thinking" || s.approval.kind === "held"\n', 'if (s.turn.kind === "thinking"\n',
            "duplex-idle-in-flight", "a held approval keeps"],
        ["idle-action", '\n                || s.action.kind === "running" && s.action.limit.kind === "pending") break;', ") break;",
            "duplex-idle-in-flight", "a running action keeps"],
        ["idle-action-limit", ' && s.action.limit.kind === "pending") break;', ") break;",
            "duplex-idle-in-flight", "past its limit"],
        ["speech-fault", 's.fault = { kind: "error", reason: e.reason, retry: 0 };\n        end(s, effects, e.at, "speech-failed", false);',
            'end(s, effects, e.at, "speech-failed", false);', "duplex-failed"],
        ["speech-stale", 'if (!live(s, e, "speech", ["open"])) { stale(s); break; }\n        // New output', "// New output", "duplex-stale"],
        ["transcript-effect", 'effect(s, effects, "transcript", { role: e.role, text: e.text, stage: e.stage, rev: e.rev });', "", "duplex-transcript"],
        ["turn-transcript", '!(e.role === "assistant" && live(s, e, "turn", ["thinking"]))', "true", "chained-transcript"],
        ["turn-transcript-role", 'e.role === "assistant" && live(s, e, "turn", ["thinking"])', 'live(s, e, "turn", ["thinking"])', "chained-transcript"],
        ["turn-transcript-phase", 'e.role === "assistant" && live(s, e, "turn", ["thinking"])',
            'e.role === "assistant" && live(s, e, "turn", ["thinking", "cancelling"])', "chained-transcript"],
        ["engine-change", " || s.engine.kind !== e.engine;", ";", "duplex-engine"],
        ["due-phase", ' || s.speech.kind === "open" && s.speech.reply.kind === "due") return "speaking";', ') return "speaking";', "duplex-reply-due"],
        ["due-set", 'if (e.due && s.speech.reply.kind === "none") s.speech.reply = { kind: "due" };', 'if (false) s.speech.reply = { kind: "due" };', "duplex-reply-due"],
        ["due-keeps-waiting", 'e.due && s.speech.reply.kind === "none"', "e.due", "duplex-due-waiting"],
        ["due-clear", 'else if (!e.due && s.speech.reply.kind === "due") s.speech.reply = { kind: "none" };', "", "duplex-due-dropped"],
        ["due-clear-keeps-waiting", '!e.due && s.speech.reply.kind === "due"', "!e.due", "duplex-due-waiting"],
        ["due-shape", 'if (typeof e.due !== "boolean") throw new Error("jarvis: session=speech-due");\n', "", "duplex-due-shape"],
        ["due-stale", 'throw new Error("jarvis: session=speech-due");\n        if (!live(s, e, "speech", ["open"])) { stale(s); break; }', 'throw new Error("jarvis: session=speech-due");', "duplex-due-stale"],
        ["due-replaced", '// A new request drops the words the voice held for the old one.\n            if (s.speech.reply.kind === "due") s.speech.reply = { kind: "none" };', "", "duplex-due-replaced"],
        ["due-stop", 'closeSpeech(s, effects, reason === "lease" ? "abort" : "graceful");', "", "duplex-due-stop"],
        ["due-talk", 'target: s.speech.op });\n        s.speech.reply = { kind: "none" };', "target: s.speech.op });", "duplex-due-talk"],
        ["due-idle", 'end(s, effects, e.at, "idle", false);', "", "duplex-due-idle"],
        ["chained-speaks", 'if (s.playback.kind === "playing" || s.playback.kind === "feedback"', 'if (s.playback.kind === "feedback"', "chained-play-speaks"],
        ["line-reply-speaks", '|| s.playback.kind === "feedback" && s.playback.reply.kind === "waiting"\n', "\n", "feedback-line"],
        ["engine-required", 'if (["chained", "dictation", "duplex"].indexOf(e.engine) === -1) throw new Error("jarvis: session=engine");', "", "duplex-engine"]
    ];
    mutants.push(
        ["always-arm", 'else if (s.input.kind === "released" && armedWanted(s)) s.input = { kind: "armed" };', "", "always-arms"],
        ["always-disarm", 'if (s.input.kind === "armed" && !armedWanted(s)) s.input = { kind: "released" };', 'if (false) s.input = { kind: "released" };', "always-disarms"],
        ["armed-idle-only", '&& s.turn.kind === "none" && s.playback.kind === "idle"\n', "\n", "always-one-utterance"],
        ["armed-chained", 's.settings.mode === "always" && s.engine.kind !== "duplex" && canEngage(s)', 's.settings.mode === "always" && canEngage(s)', "always-disarms"],
        ["armed-engaged", 's.settings.mode === "always" && s.engine.kind !== "duplex" && canEngage(s)', 's.settings.mode === "always" && s.engine.kind !== "duplex"', "always-disarms"],
        ["armed-no-collect", 'canCapture(s) && s.input.kind !== "armed"', "canCapture(s)", "always-arms"],
        ["armed-ended-capture", '(s.conversation.kind !== "ended" || s.input.kind === "armed" || checking)', '(s.conversation.kind !== "ended" || checking)', "always-arms"],
        ["armed-indicator", 's.input.kind === "armed"\n        || ', "", "always-arms"],
        ["wake-armed-only", ' || s.capture.mode !== "armed") { stale(s); break; }', ") { stale(s); break; }", "always-wake"],
        ["wake-starts", 'start(s, effects, "woken", e.at);\n        break;\n    case "capture-closed":', 'break;\n    case "capture-closed":', "always-wake"],
        ["wake-woken", 'start(s, effects, "woken", e.at);', 'start(s, effects, "conversation", e.at);', "always-false-wake"],
        ["wake-capture-mode", 's.input.kind === "woken" ? "conversation" : s.input.kind;', 's.input.kind;', "always-wake"],
        ["wake-silence-bound", 's.input.kind === "woken" || s.input.kind === "follow-up" ? e.at + WAKE_SILENCE_MS : null;', 'null;', "always-false-wake", "short bound"],
        ["tap-bound", "&& e.at - s.input.since < TAP_MS) {", "&& false) {", "tap", "tap:"],
        ["tap-open-capture", '(s.capture.kind === "opening" || s.capture.kind === "open" || (s.capture.kind === "closed" && s.fault.kind === "none"))\n                && e.at', "e.at", "tap", "failed capture"],
        ["tap-before-open", ' || (s.capture.kind === "closed" && s.fault.kind === "none")', "", "tap", "start sound"],
        ["tap-second-press", '        if (s.input.kind === "tapped") {\n            s.input = { kind: "released" };\n            closeCapture(s, effects);\n            break;\n        }\n', "", "tap", "second tap"],
        ["tap-words-move", '        if (s.input.kind === "tapped" && s.capture.kind === "open") s.input.deadline = e.at + TAP_SILENCE_MS;\n        // Words were heard', "        // Words were heard", "tap", "end of speech"],
        ["tap-silence-ends", '    if (s.input.kind === "tapped" && s.input.deadline !== null && s.capture.kind === "open" && at >= s.input.deadline) {', "    if (false) {", "tap", "end of speech"],
        ["tap-deadline-event", '\n                || s.input.kind === "tapped" && live(s, e, "capture", ["open"]))', ")", "tap", "end of speech"],
        ["tap-opened-bound", '        if (s.input.kind === "tapped") s.input.deadline = e.at + TAP_SILENCE_MS;\n', "", "tap", "tap before open"],
        ["tap-failed-ends", '        if (s.input.kind === "tapped") s.input = { kind: "released" };\n        if (s.turn.kind === "collecting") s.turn = { kind: "none" };', '        if (s.turn.kind === "collecting") s.turn = { kind: "none" };', "tap", "failed capture: the next press"],
        ["duplex-tap-one-request", '            if (s.input.kind === "tapped") {\n                s.input = { kind: "released" };\n                closeCapture(s, effects);\n            }\n            think(', "            think(", "duplex-tap", "the request goes to the brain"],
        ["duplex-tap-words", "        if (e.role === \"user\" && s.input.kind === \"tapped\" && s.capture.kind === \"open\") s.input.deadline = e.at + TAP_SILENCE_MS;\n", "", "duplex-tap", "words move"],
        ["wake-silence-quiet", 'if (s.input.kind === "woken") end(s, effects, at, "wake-silence", false);', 'if (false) end(s, effects, at, "wake-silence", false);', "always-false-wake", "returns quietly"],
        ["wake-heard", 'if (s.input.kind === "woken" || s.input.kind === "follow-up") {\n            s.input = { kind: "conversation" };', 'if (false) {\n            s.input = { kind: "conversation" };', "always-false-wake", "lift the bound"],
        ["wake-heard-open", 'if (s.capture.kind === "open") s.turn.deadline = null;', 'void s;', "always-false-wake", "lift the bound"],
        ["wake-talk-ends", '(s.input.kind === "conversation" || s.input.kind === "woken" || s.input.kind === "follow-up")\n            && s.turn.kind', 's.input.kind === "conversation" && s.turn.kind', "always-talk", "while listening"],
        ["talk-ends", '(s.input.kind === "conversation" || s.input.kind === "woken" || s.input.kind === "follow-up")\n            && s.turn.kind', 's.input.kind === "woken" && s.turn.kind', "always-talk", "after Talk"],
        ["wake-closes-armed", "    closeArmed(s, effects);\n", "", "always-wake"],
        ["always-utterance", ' || s.settings.mode === "always") s.input = { kind: "released" };', ') s.input = { kind: "released" };', "always-one-utterance"],
        ["always-talk-mode", 'if (s.settings.mode === "always") { listenNow(s, effects, e.at); break; }', "", "always-talk", "listens now"],
        ["always-talk-debounce", 'function listenNow(s, effects, at) {\n    if (bounced(s, at)) return;',
            'function listenNow(s, effects, at) {', "always-talk", "250 ms"],
        ["always-talk-ends", 'if ((s.input.kind === "conversation" || s.input.kind === "woken" || s.input.kind === "follow-up")\n            && s.turn.kind === "collecting") {', "if (false) {", "always-talk", "while listening"],
        ["always-talk-interrupts", '    interrupt(s, effects, at);\n    start(s, effects, "conversation", at);', '    start(s, effects, "conversation", at);', "always-talk", "stops the reply"],
        ["always-talk-starts", '    interrupt(s, effects, at);\n    start(s, effects, "conversation", at);', '    interrupt(s, effects, at);', "always-talk", "listens now"],
        ["always-talk-recovers", '    recover(s, effects, at);\n    if (!canEngage(s)) return;\n    s.toggleAt = at;\n    interrupt(',
            '    if (!canEngage(s)) return;\n    s.toggleAt = at;\n    interrupt(', "always-talk", "on a fault"]
    );
    mutants.push(
        ["preview-judge", 'case "preview":\n        if (previewRefusal(s) !== null) break;', 'case "preview":', "preview-refusals"],
        ["preview-turn-busy", 'return "muted";\n    if (s.turn.kind !== "none" || ', 'return "muted";\n    if (', "preview-refusals"],
        ["preview-playback-busy", 'return "muted";\n    if (s.turn.kind !== "none" || s.playback.kind !== "idle" || s.approval.kind !== "none" || s.action.kind !== "none"\n', 'return "muted";\n    if (s.turn.kind !== "none" || s.approval.kind !== "none" || s.action.kind !== "none"\n', "preview-refusals"],
        ["preview-approval-busy", 'return "muted";\n    if (s.turn.kind !== "none" || s.playback.kind !== "idle" || s.approval.kind !== "none" || s.action.kind !== "none"\n', 'return "muted";\n    if (s.turn.kind !== "none" || s.playback.kind !== "idle" || s.action.kind !== "none"\n', "preview-refusals"],
        ["preview-action-busy", 'return "muted";\n    if (s.turn.kind !== "none" || s.playback.kind !== "idle" || s.approval.kind !== "none" || s.action.kind !== "none"\n', 'return "muted";\n    if (s.turn.kind !== "none" || s.playback.kind !== "idle" || s.approval.kind !== "none"\n', "preview-refusals"],
        ["preview-recover", 'recover(s, effects, e.at);\n        // A new conversation takes a new gen', '// A new conversation takes a new gen', "preview-recovers"],
        ["preview-check", '|| ["waiting", "recording", "finishing"].indexOf(s.check.kind) !== -1\n            || s.engine.kind === "duplex"', '|| s.engine.kind === "duplex"', "preview-refusals"],
        ["preview-duplex-busy", ' || s.engine.kind === "duplex" && s.conversation.kind !== "ended") return "busy";', ') return "busy";', "preview-refusals"],
        ["preview-gen", 'if (s.conversation.kind === "ended") s.gen += 1;', '', "preview-local"],
        ["preview-turn", '} else think(s, effects, preview, e.at);', '}', "preview-local"],
        ["preview-duplex-open", 'var opened = effect(s, effects, "speech-open", preview);', 'var opened = effect(s, effects, "speech-open", {});', "preview-duplex"],
        ["say-judge", 'case "say":\n        if (sayRefusal(s) !== null) break;', 'case "say":', "say-refusals"],
        ["say-recover", 'recover(s, effects, e.at);\n        commitUserText(s, effects, e.text, e.at, 1, false);', 'commitUserText(s, effects, e.text, e.at, 1, false);', "say-recovers"],
        ["say-speaking", 'if (s.playback.kind !== "idle") return "speaking";', 'if (false) return "speaking";', "say-refuses-speaking"],
        ["say-action", 's.action.kind === "running" || ', '', "say-refuses-action-only"],
        ["user-transcript", 'userTranscript(s, effects, text, rev);', 'if (false) userTranscript(s, effects, text, rev);', "say-idle"],
        ["caption-control", 'String(value).replace(/[\\x00-\\x1f\\x7f]/g, " ").slice(-TRANSCRIPT_CHARS)', 'String(value).slice(-TRANSCRIPT_CHARS)', "user-transcript-sanitized"],
        ["caption-blank", 'return text.trim() === "" ? "" : text;', 'return text;', "user-transcript-sanitized"],
        ["caption-bound", '.slice(-TRANSCRIPT_CHARS);', ';', "user-transcript-sanitized"],
        ["say-gen", 's.gen += 1;\n        s.conversation = { kind: "active" };', 's.gen += 0;\n        s.conversation = { kind: "active" };', "say-idle"],
        ["unknown-event", 'if (EVENTS.indexOf(e.type) === -1) throw', 'if (false && EVENTS.indexOf(e.type) === -1) throw', "unknown-event"],
        ["event-clock", 'if (!Number.isFinite(e.at) || e.at < 0) throw', 'if (false && (!Number.isFinite(e.at) || e.at < 0)) throw', "event-clock"],
        ["tool-duration", 'if (!Number.isFinite(e.timeoutMs) || e.timeoutMs <= 0)', 'if (false && (!Number.isFinite(e.timeoutMs) || e.timeoutMs <= 0))', "invalid-tool-deadline"],
        ["tool-result", 'if (["completed", "failed", "unknown"].indexOf(e.outcome) === -1)',
            'if (false && ["completed", "failed", "unknown"].indexOf(e.outcome) === -1)', "invalid-outcome"]
    );
    mutants.push(
        ["state-record", 'if (!exact(s, Object.keys(REGIONS).concat(["gen", "nextOp", "stale", "settings", "toggleAt", "checkSource"]))) return false;',
            'if (false && !exact(s, Object.keys(REGIONS).concat(["gen", "nextOp", "stale", "settings", "toggleAt", "checkSource"]))) return false;', "wire-record"],
        ["state-counter", 'if (!Number.isSafeInteger(s[name]) || s[name] < (name === "nextOp" ? 1 : 0)) return false;',
            'if (false && (!Number.isSafeInteger(s[name]) || s[name] < (name === "nextOp" ? 1 : 0))) return false;', "wire-counter"],
        ["state-settings", 'if (s.settings === null || typeof s.settings !== "object" || Array.isArray(s.settings)) return false;',
            'if (false && (s.settings === null || typeof s.settings !== "object" || Array.isArray(s.settings))) return false;', "wire-settings"],
        ["state-toggle", 'if (s.toggleAt !== null && (!Number.isFinite(s.toggleAt) || s.toggleAt < 0)) return false;',
            'if (false && s.toggleAt !== null && (!Number.isFinite(s.toggleAt) || s.toggleAt < 0)) return false;', "wire-toggle-time"],
        ["state-region", 'if (r === null || !Object.prototype.hasOwnProperty.call(REGIONS[region], r.kind)) return false;',
            'if (r === null || !Object.prototype.hasOwnProperty.call(REGIONS[region], r.kind)) { r = { kind: "closed" }; }', "wire-region-tag"],
        ["state-fields", 'if (!exact(r, ["kind"].concat(fields))) return false;',
            'if (false && !exact(r, ["kind"].concat(fields))) return false;', "wire-region-fields"],
        ["state-op", 'if (!Number.isSafeInteger(r[f]) || r[f] < (["op", "brain", "source"].indexOf(f) !== -1 ? 1 : 0)) return false;',
            'if (false && (!Number.isSafeInteger(r[f]) || r[f] < (["op", "brain", "source"].indexOf(f) !== -1 ? 1 : 0))) return false;', "wire-owner-counter"],
        ["state-time", 'if (!(f === "shownAt" && r[f] === null) && (!Number.isFinite(r[f]) || r[f] < 0)) return false;',
            'if (false && !(f === "shownAt" && r[f] === null) && (!Number.isFinite(r[f]) || r[f] < 0)) return false;', "wire-owner-time"],
        ["state-string", 'else if (typeof r[f] !== "string") return false;',
            'else if (false && typeof r[f] !== "string") return false;', "wire-owner-string"],
        ["state-bool", 'if (typeof r[f] !== "boolean") return false;',
            'if (false && typeof r[f] !== "boolean") return false;', "wire-owner-bool"],
        ["state-cancellation", 'if (!exact(r[f], ["kind"]) || ["available", "unavailable", "requested"].indexOf(r[f].kind) === -1) return false;',
            'if (false && (!exact(r[f], ["kind"]) || ["available", "unavailable", "requested"].indexOf(r[f].kind) === -1)) return false;', "wire-cancel-tag"],
        ["state-admission", 'if (!exact(r[f], ["kind"]) || ["waiting", "started"].indexOf(r[f].kind) === -1) return false;',
            'if (false && (!exact(r[f], ["kind"]) || ["waiting", "started"].indexOf(r[f].kind) === -1)) return false;', "wire-admission-tag"],
        ["state-limit", 'if (["pending", "expired"].indexOf(r[f].kind) === -1) return false;',
            'if (false && ["pending", "expired"].indexOf(r[f].kind) === -1) return false;', "wire-limit-tag"],
        ["state-limit-time", 'if (r[f].kind === "pending" && (!Number.isFinite(r[f].deadline) || r[f].deadline < 0)) return false;',
            'if (false && r[f].kind === "pending" && (!Number.isFinite(r[f].deadline) || r[f].deadline < 0)) return false;', "wire-limit-time"],
        ["state-mode", '&& ["hold", "conversation", "follow-up", "armed", "check"].indexOf(r.mode) === -1) return false;',
            '&& false && ["hold", "conversation", "follow-up", "armed"].indexOf(r.mode) === -1) return false;', "wire-capture-mode"],
        ["state-gate", '&& ["starting", "unconfigured", "node", "lock-unknown", "locked"].indexOf(r.reason) === -1) return false;',
            '&& false && ["starting", "unconfigured", "node", "lock-unknown", "locked"].indexOf(r.reason) === -1) return false;', "wire-gate-reason"],
        ["state-reply", 'if (!exact(r[f], ["kind"]) || ["none", "waiting", "due"].indexOf(r[f].kind) === -1) return false;',
            'if (false) return false;', "wire-speech-reply-tag"],
        ["state-reply-due", '["none", "waiting", "due"]', '["none", "waiting"]', "duplex-reply-due"]
    );
    for (const [name, needle, replacement, row, assertion] of mutants) {
        const count = source.split(needle).length - 1;
        // Assert the match before changing only the disposable copy.
        const expected = 1;
        assert.equal(count, expected, name + " mutation match");
        const changed = source.split(needle).join(replacement);
        assert.notEqual(changed, source);
        const mutant = path.join(root, name + ".js");
        fs.writeFileSync(mutant, changed);
        assert.throws(() => table.find(item => item[0] === row)[1](load(mutant)),
            error => error instanceof assert.AssertionError && (assertion === undefined || error.message.includes(assertion)),
            name + " must turn its rule assertion red");
        controls++;
    }
    const matrixSource = createdPairMatrix.toString();
    function matrixControl(name, needle, replacement) {
        assert.equal(matrixSource.split(needle).length - 1, 1, name + " matrix mutation match");
        const changed = matrixSource.replace(needle, replacement);
        assert.notEqual(changed, matrixSource);
        const mutant = path.join(root, name + ".js");
        fs.writeFileSync(mutant, ".pragma library\n" + changed);
        const logic = load(mutant);
        Object.assign(logic, { assert, seeds, pairEvents, createdCallbacks, fixtureEvent, step, invariants });
        assert.throws(() => logic.createdPairMatrix(Session), assert.AssertionError, name + " must turn red");
        controls++;
    }
    for (const kind of ["capture-open", "capture-close", "collect", "brain-send", "brain-cancel",
        "playback-start", "playback-flush", "tool-start", "approval-show", "speech-open"])
        matrixControl("matrix-omit-" + kind, "for (const effect of firstResult.effects) {",
            'for (const effect of firstResult.effects) {\n            if (effect.kind === "' + kind + '") continue;');
    for (const kind of ["brain-send", "brain-cancel", "tool-start", "approval-show"])
        matrixControl("matrix-omit-deadline-" + kind,
            "for (const pair of createdCallbacks.filter(row => row.effect === effect.kind)) {",
            'for (const pair of createdCallbacks.filter(row => row.effect === effect.kind)) {\n' +
            '                if (effect.kind === "' + kind + '" && pair.type === "deadline") continue;');
    matrixControl("matrix-stale-only", "second.op = pair.target ? effect.target : effect.op;",
        "second.op = fixtureEvent(pair.type, seed, 201).op;");
} finally { fs.rmSync(root, { recursive: true, force: true }); }
console.log("test-jarvis-session: ok transitions=" + table.length + " old-owner-pairs=" + pairs +
    " created-owner-pairs=" + createdPairs + " controls=" + controls);
