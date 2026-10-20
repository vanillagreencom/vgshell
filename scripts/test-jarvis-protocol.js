#!/usr/bin/env node
// Synthetic cases from JarvisProtocol.js, 2026-09-30. No provider wire.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");
const { freshSuite } = require("./fixtures/jarvis/prepare.js");
const file = path.join(__dirname, "../shell/plugins/vgs.jarvis/JarvisProtocol.js");
const Protocol = load(file);
const hello = { v: 1, type: "hello", gen: 0, settings: { home: "", sounds: false, mode: "hold", microphone: "", speaker: "", brain: "", model: "", effort: "", fallbacks: [], taskTerminal: "auto", voiceProvider: "local", voiceAccount: "", voice: "", clonedVoice: false, dictation: "",
    cloudVision: "ask", privateWindows: "bitwarden, incognito" }, directories: {
    state: "/private/state", data: "/private/data", runtime: "/private/runtime"
}, revision: "a".repeat(64), locked: false,
keys: { talk: "SUPER+code:108", mute: "SUPER+SHIFT+code:108", stop: "SUPER+ALT+PERIOD", confirm: "SUPER+ALT+Y", console: "SUPER+ALT+C" } };
const intent = { v: 1, type: "intent", gen: 0, revision: hello.revision, intent: "talk-down" };
const id = "11111111-1111-4111-8111-111111111111";
const confirm = { ...intent, intent: "confirm", id, digest: "a".repeat(64), source: "key" };
const cancel = { ...intent, intent: "cancel", id };
const shown = { v: 1, type: "shown", gen: 0, revision: hello.revision, id };
const indicator = { v: 1, type: "indicator", gen: 0, revision: hello.revision, shown: true };
const status = { v: 1, type: "status", gen: 0, revision: hello.revision, daemon: "ready", causes: [], cautions: [] };
const shellStatus = { v: 1, type: "shell-status", gen: 0, revision: hello.revision, availability: { kind: "available" } };
const memory = { v: 1, type: "memory", gen: 0, revision: hello.revision, cause: "memory=sqlite" };
const memoryEntry = { id, target: "facts/new.md", kind: "propose", title: "New memory", labels: ["home", "web"], text: "Remember this.", hash: "b".repeat(64), problem: "" };
const memoryInbox = { v: 1, type: "memory-inbox", gen: 0, revision: hello.revision, entries: [memoryEntry] };
const memoryConfirm = { ...intent, intent: "memory-confirm", id, hash: memoryEntry.hash };
const memoryDiscard = { ...intent, intent: "memory-discard", id, hash: memoryEntry.hash };
const state = { v: 1, type: "state", gen: 0, revision: hello.revision, seq: 1,
    state: JSON.parse(JSON.stringify(Protocol.Session.initial())), phase: "down", brain: "Claude Code Fable" };
const manifest = JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8"));
// The hello's settings are the manifest's and `sounds`, which the service
// reads from the manifest's one sound event, `feedback`, but `localTier`:
// the Local voice choice is a download request the service keeps
// (LocalTier.qml), and the daemon loads the tier setup left ready. The
// service also keeps the two Start Jarvis at boot settings
// (SessionStart.qml): the daemon reads no session.
const kept = ["localTier", "startAtBoot", "bootSession"];
assert.deepEqual(Object.keys(manifest.settings).filter(key => !kept.includes(key)).concat(["sounds", "dictation"]).sort(), Object.keys(hello.settings).sort());
assert.deepEqual([Object.keys(manifest.sounds), manifest.sounds.feedback.own !== undefined], [["feedback"], true]);
assert.deepEqual([manifest.settings.cloudVision, manifest.schema.cloudVision.options.map(option => option.value)], ["ask", ["ask", "allow", "never"]]);
assert.equal(typeof manifest.settings.privateWindows, "string");
assert.deepEqual(manifest.schema.mode.options.map(option => option.value), ["hold", "toggle", "always"]);
assert.deepEqual(manifest.schema.taskTerminal.options.map(option => option.value), ["auto", "tmux", "floating"]);
assert.deepEqual(manifest.tui.task, { script: "tui/task.sh", title: "Jarvis coding task", presentation: "plain", requires: ["python3", "node"] });
assert.deepEqual(manifest.status.tasks.type, "count");
assert.equal(manifest.hyprland.binds.every(bind => typeof bind.info === "string" && bind.info !== ""), true);
assert.deepEqual(manifest.hyprland.binds.map(({ info, ...bind }) => bind), [
    { shortcut: "talk", key: "SUPER+code:108", hold: true },
    { shortcut: "mute", key: "SUPER+SHIFT+code:108" },
    { shortcut: "stop", key: "SUPER+ALT+PERIOD" },
    { shortcut: "confirm", key: "SUPER+ALT+Y" },
    { shortcut: "console", key: "SUPER+ALT+C" }
]);
assert.equal(manifest.capabilities.includes("shortcut") && manifest.capabilities.includes("surfaces"), true);
assert.equal(manifest.requirements.some(row => row.command === "pw-cli"), false);
const devices = { v: 1, type: "devices", gen: 0, revision: hello.revision,
    microphones: [{ label: "Microphone", value: "fixture.mic" }], speakers: [] };
const homes = { v: 1, type: "homes", gen: 0, revision: hello.revision,
    homes: [{ id: "h012345abcdef", label: "~/Jarvis", value: "~/Jarvis" }], current: "~/Jarvis" };
const voices = { v: 1, type: "voices", gen: 0, revision: hello.revision, voices: [{ label: "Heart, American English, female", value: "af_heart" }] };
const personality = { v: 1, type: "personality", gen: 0, revision: hello.revision, personality: { kind: "section", lines: ["Calm."], more: false } };
// The start text's estimate: two home layers of the five, as an empty home
// sends them.
const startText = { v: 1, type: "start-text", gen: 0, revision: hello.revision,
    size: { kind: "read", tokens: 1430, layers: [{ layer: "home/skills", tokens: 20 }, { layer: "home/state", tokens: 60 }] } };
const startLayers = layers => changed(startText, { size: { ...startText.size, layers } });
const level = { v: 1, type: "level", gen: 0, revision: hello.revision, level: { capture: 0.5, playback: 0 } };
const audioFault = { v: 1, type: "audio-fault", gen: 0, revision: hello.revision, reason: "discovery-exit" };
const request = { v: 1, type: "request", gen: 0, revision: hello.revision, id: 1, kind: "compositor.moveWindow", args: ["0xa1", -10, 20] };
const reply = { v: 1, type: "reply", gen: 0, revision: hello.revision, id: 1, kind: "compositor.moveWindow", answer: "ok", data: null };
const entry = { id: "org.example.App", name: "Example", startupClass: "example" };
const listReply = { ...reply, kind: "desktop.list", data: { entries: [entry], complete: true } };
const entryReply = { ...reply, kind: "desktop.launch", data: { ...entry, terminal: false } };
// The local voice's final words, as the service hands back voxtype's text.
const stopReply = { ...reply, kind: "dictation.stop", data: { text: "Open the browser." } };
assert.equal(manifest.capabilities.includes("compositor") && manifest.capabilities.includes("run"), true);
const taskStop = { ...intent, intent: "task-stop", task: "0f7c6a2e-5d1b-4c3a-9e8f-1a2b3c4d5e6f" };
const taskOpen = { ...taskStop, intent: "task-open" };
const taskOpened = { v: 1, type: "task-open", gen: 0, revision: hello.revision, task: taskStop.task, answer: "tmux" };
const taskRow = { id: taskStop.task, goal: "Goal", agent: "fixture", state: "working", failure: null, createdAt: 0, endedAt: null };
const taskList = { v: 1, type: "task-list", gen: 0, revision: hello.revision, rows: [taskRow] };
const auditRow = { time: "2026-09-30T12:00:00.000Z", tool: "files.write", effect: "persistent", decision: "allow", outcome: "failed", refusal: null, cause: null };
const auditFailures = { ...taskList, type: "audit-failures", rows: [auditRow] };
const say = { ...intent, intent: "say", text: "typed message" };
const requirementsScan = { v: 1, type: "requirements-scan", gen: 0, revision: hello.revision, scan: 1 };
const tuiState = { v: 1, type: "tui-state", gen: 0, revision: hello.revision, name: "task", running: true };
const taskReply = { ...reply, kind: "tui.run", answer: "refused: tui=task reason=busy" };
const taskRequest = { v: 1, type: "request", gen: 0, revision: hello.revision, id: 1, kind: "tui.run",
    args: ["/run/user/1000/vgshell/jarvis/tasks/" + taskStop.task + ".json"] };
const tasks = { v: 1, type: "tasks", gen: 0, revision: hello.revision, count: 2 };
const taskAnswer = { v: 1, type: "task-answer", gen: 0, revision: hello.revision, task: taskStop.task, answer: "stop-incomplete" };
const taskRespond = { ...intent, intent: "task-respond", task: taskStop.task, prompt: id, answer: { v: 1, kind: "allow" } };
const taskResponse = { ...taskAnswer, type: "task-response", prompt: id, answer: "answered" };
const promptRecord = { v: 1, id, task: taskStop.task, kind: "permission", tool: "Bash", text: "Bash {}", at: 1000, deadline: 601000 };
const taskPrompts = { ...tasks, type: "task-prompts", prompts: [promptRecord] };
delete taskPrompts.count;
const transcript = { v: 1, type: "transcript", gen: 0, revision: hello.revision, role: "user", text: " the time?", stage: "partial", rev: 1 };
const changed = (message, extra) => JSON.stringify({ ...message, ...extra });
const inputReply = { ...reply, kind: "input.observe", data: { ok: true, target: { kind: "application", id: "fixture", window: "0xa1" }, cursor: { x: 1, y: 2 } } };
const keysReply = { ...reply, kind: "input.keys", data: { ok: true, keys: [{ modifiers: ["SUPER"], keycode: 38, keysym: "a", codepoint: 97 }], translation: [{ modifiers: ["SUPER"], keycode: 38, keysym: "a", codepoint: 97 }], effective: [] } };
const inputReady = { ...status, type: "input-ready", commands: ["wtype", "wlrctl"] };
delete inputReady.daemon;
delete inputReady.causes;
delete inputReady.cautions;
const cases = [
    ["task-list-direction", JSON.stringify(taskList), "shell", "direction-task-list"],
    ["task-list-count", changed(taskList, { rows: Array(17).fill(taskRow) }), "daemon", "task-list"],
    ["task-list-goal", changed(taskList, { rows: [{ ...taskRow, goal: "g".repeat(201) }] }), "daemon", "task-row"],
    ["task-list-agent", changed(taskList, { rows: [{ ...taskRow, agent: "a".repeat(129) }] }), "daemon", "task-row"],
    ["task-list-state", changed(taskList, { rows: [{ ...taskRow, state: "complete" }] }), "daemon", "task-row"],
    ["task-list-failure", changed(taskList, { rows: [{ ...taskRow, failure: "f".repeat(129) }] }), "daemon", "task-row"],
    ["task-list-zero", changed(taskList, { rows: [{ ...taskRow, failure: 0 }] }), "daemon", "task-row"],
    ["task-list-created", changed(taskList, { rows: [{ ...taskRow, createdAt: -1 }] }), "daemon", "task-row"],
    ["task-list-ended", changed(taskList, { rows: [{ ...taskRow, endedAt: -1 }] }), "daemon", "task-row"],
    ["audit-direction", JSON.stringify(auditFailures), "shell", "direction-audit-failures"],
    ["audit-count", changed(auditFailures, { rows: Array(21).fill(auditRow) }), "daemon", "audit-failures"],
    ["audit-args", changed(auditFailures, { rows: [{ ...auditRow, args: {} }] }), "daemon", "shape-audit-row"],
    ["audit-time", changed(auditFailures, { rows: [{ ...auditRow, time: auditRow.time + "x" }] }), "daemon", "audit-row"],
    ["audit-tool", changed(auditFailures, { rows: [{ ...auditRow, tool: "t".repeat(129) }] }), "daemon", "audit-row"],
    ["audit-effect", changed(auditFailures, { rows: [{ ...auditRow, effect: "other" }] }), "daemon", "audit-row"],
    ["audit-decision", changed(auditFailures, { rows: [{ ...auditRow, decision: "other" }] }), "daemon", "audit-row"],
    ["audit-outcome", changed(auditFailures, { rows: [{ ...auditRow, decision: "refuse", outcome: "other" }] }), "daemon", "audit-row"],
    ["audit-completed", changed(auditFailures, { rows: [{ ...auditRow, outcome: "completed" }] }), "daemon", "audit-row"],
    ["audit-refusal", changed(auditFailures, { rows: [{ ...auditRow, refusal: "other" }] }), "daemon", "audit-row"],
    ["audit-cause", changed(auditFailures, { rows: [{ ...auditRow, cause: "live=unheard" }] }), "daemon", "audit-row"],
    ["task-open-id", changed(taskOpen, { task: "a".repeat(65) }), "shell", "task-id"],
    ["task-open-direction", JSON.stringify(taskOpened), "shell", "direction-task-open"],
    ["task-open-answer-id", changed(taskOpened, { task: "a".repeat(65) }), "daemon", "open-task-id"],
    ["task-open-answer", changed(taskOpened, { answer: "a".repeat(41) }), "daemon", "task-open"],
    ["task-respond-direction", JSON.stringify(taskRespond), "daemon", "direction-intent"],
    ["task-respond-id", changed(taskRespond, { prompt: "bad" }), "shell", "task-prompt-id"],
    ["task-respond-shape", changed(taskRespond, { answer: { v: 1, kind: "allow", extra: true } }), "shell", "shape-task-response"],
    ["task-respond-kind", changed(taskRespond, { answer: { v: 1, kind: "finish" } }), "shell", "task-response"],
    ["task-respond-empty", changed(taskRespond, { answer: { v: 1, kind: "reply", text: " " } }), "shell", "task-response"],
    ["task-response-direction", JSON.stringify(taskResponse), "shell", "direction-task-response"],
    ["task-prompts-direction", JSON.stringify(taskPrompts), "shell", "direction-task-prompts"],
    ["task-prompts-shape", changed(taskPrompts, { prompts: [{ ...promptRecord, extra: 1 }] }), "daemon", "shape-task-prompt"],
    ["task-prompts-kind", changed(taskPrompts, { prompts: [{ ...promptRecord, kind: "finished", tool: null }] }), "daemon", "task-prompt"],
    ["transcript-direction", JSON.stringify(transcript), "shell", "direction-transcript"],
    ["transcript-shape", changed(transcript, { partial: true }), "daemon", "shape-transcript"],
    ["transcript-role", changed(transcript, { role: "system" }), "daemon", "transcript-role"],
    ["transcript-stage", changed(transcript, { stage: "done" }), "daemon", "transcript-stage"],
    ["transcript-empty", changed(transcript, { text: "" }), "daemon", "transcript-text"],
    ["transcript-long", changed(transcript, { text: "a".repeat(4097) }), "daemon", "transcript-text"],
    ["transcript-control", changed(transcript, { text: "a\nb" }), "daemon", "transcript-text"],
    ["transcript-rev", changed(transcript, { rev: 0 }), "daemon", "transcript-rev"],
    ["indicator-direction", JSON.stringify(indicator), "daemon", "direction-indicator"],
    ["indicator-shape", changed(indicator, { extra: true }), "shell", "shape-indicator"],
    ["indicator-shown", changed(indicator, { shown: 1 }), "shell", "indicator"],
    ["input-point", changed(request, { kind: "input.observe", args: [1] }), "daemon", "request-args"],
    ["input-target", changed(inputReply, { data: { ...inputReply.data, target: { kind: "unknown", id: "fixture" } } }), "shell", "input-reply"],
    ["input-key", changed(keysReply, { data: { ...keysReply.data, keys: [{ modifiers: ["SUPER"], keycode: 0, keysym: "a", codepoint: 97 }] } }), "shell", "input-reply"],
    ...[null, -1, 0.5, 0x110000, 0xd800, 0xdfff].map(codepoint =>
        ["input-codepoint-" + codepoint, changed(keysReply, { data: { ...keysReply.data,
            keys: [{ ...keysReply.data.keys[0], codepoint }] } }), "shell", "input-reply"]),
    ["input-ready-direction", JSON.stringify(inputReady), "shell", "direction-input-ready"],
    ["input-ready-command", changed(inputReady, { commands: ["sudo"] }), "daemon", "input-commands"],
    ["requirements-direction", JSON.stringify(requirementsScan), "daemon", "direction-requirements-scan"],
    ["requirements-shape", changed(requirementsScan, { extra: true }), "shell", "shape-requirements-scan"],
    ["requirements-scan", changed(requirementsScan, { scan: -1 }), "shell", "requirements-scan"],
    ["requirements-fraction", changed(requirementsScan, { scan: 0.5 }), "shell", "requirements-scan"],
    ["requirements-overflow", changed(requirementsScan, { scan: Number.MAX_SAFE_INTEGER + 1 }), "shell", "requirements-scan"],
    ["shell-status-direction", JSON.stringify(shellStatus), "shell", "direction-shell-status"],
    ["shell-status-shape", changed(shellStatus, { extra: true }), "daemon", "shape-shell-status"],
    ["shell-availability", changed(shellStatus, { availability: { kind: "ready" } }), "daemon", "shell-availability"],
    ["shell-availability-shape", changed(shellStatus, { availability: { kind: "available", reason: "extra" } }), "daemon", "shape-shell-availability"],
    ["shell-reason", changed(shellStatus, { availability: { kind: "unavailable", reason: "" } }), "daemon", "shell-reason"],
    ["memory-direction", JSON.stringify(memory), "shell", "direction-memory"],
    ["memory-shape", changed(memory, { extra: true }), "daemon", "shape-memory"],
    ["memory-cause", changed(memory, { cause: "sqlite" }), "daemon", "memory-cause"],
    ["memory-inbox-direction", JSON.stringify(memoryInbox), "shell", "direction-memory-inbox"],
    ["memory-inbox-shape", changed(memoryInbox, { extra: true }), "daemon", "shape-memory-inbox"],
    ["memory-inbox-list", changed(memoryInbox, { entries: {} }), "daemon", "memory-inbox"],
    ["memory-inbox-bound", changed(memoryInbox, { entries: Array(65).fill(memoryEntry) }), "daemon", "memory-inbox"],
    ["memory-entry-shape", changed(memoryInbox, { entries: [{ ...memoryEntry, extra: true }] }), "daemon", "shape-memory-entry"],
    ["memory-entry-id", changed(memoryInbox, { entries: [{ ...memoryEntry, id: "bad" }] }), "daemon", "memory-entry"],
    ["memory-entry-target", changed(memoryInbox, { entries: [{ ...memoryEntry, target: "inbox/pending.md" }] }), "daemon", "memory-entry"],
    ["memory-entry-kind", changed(memoryInbox, { entries: [{ ...memoryEntry, kind: "edit" }] }), "daemon", "memory-entry"],
    ["memory-entry-labels", changed(memoryInbox, { entries: [{ ...memoryEntry, labels: ["home", "home"] }] }), "daemon", "memory-entry"],
    ["memory-entry-text", changed(memoryInbox, { entries: [{ ...memoryEntry, text: "x".repeat(16 * 1024 + 1) }] }), "daemon", "memory-entry"],
    ["memory-entry-hash", changed(memoryInbox, { entries: [{ ...memoryEntry, hash: "B".repeat(64) }] }), "daemon", "memory-entry"],
    ["memory-entry-problem", changed(memoryInbox, { entries: [{ ...memoryEntry, problem: "other" }] }), "daemon", "memory-entry"],
    ["memory-inbox-byte-bound", changed(memoryInbox, { entries: Array(9).fill({ ...memoryEntry, text: "x".repeat(16 * 1024) }) }), "daemon", "memory-inbox"],
    ["audio-fault-direction", JSON.stringify(audioFault), "shell", "direction-audio-fault"],
    ["audio-fault", changed(audioFault, { reason: "" }), "daemon", "audio-fault"],
    ["device-setting", changed(hello, { settings: { ...hello.settings, microphone: 1 } }), "shell", "device-setting"],
    ["devices-direction", JSON.stringify(devices), "shell", "direction-devices"],
    ["choices", changed(devices, { microphones: {} }), "daemon", "choices"],
    ["choice", changed(devices, { microphones: [{ label: "Microphone", value: "" }] }), "daemon", "choice"],
    ["choice-duplicate", changed(devices, { microphones: devices.microphones.concat(devices.microphones) }), "daemon", "choice-duplicate"],
    ["homes-direction", JSON.stringify(homes), "shell", "direction-homes"],
    ["homes-current", changed(homes, { current: 7 }), "daemon", "home-current"],
    ["voice-setting", changed(hello, { settings: { ...hello.settings, voice: "af_heart\n" } }), "shell", "voice-setting"],
    ["voices-direction", JSON.stringify(voices), "shell", "direction-voices"],
    ["voices-bound", changed(voices, { voices: Array.from({ length: 65 }, (_, n) => ({ label: "V" + n, value: "v" + n })) }), "daemon", "voices"],
    ["voices-label", changed(voices, { voices: [{ label: "", value: "af_heart" }] }), "daemon", "voice"],
    ["voices-duplicate", changed(voices, { voices: voices.voices.concat(voices.voices) }), "daemon", "voice-duplicate"],
    ["personality-direction", JSON.stringify(personality), "shell", "direction-personality"],
    ["personality-kind", changed(personality, { personality: { kind: "granted" } }), "daemon", "personality-kind"],
    // An AGENTS.md of any size shows its section: no kind says it is too long.
    ["personality-too-large", changed(personality, { personality: { kind: "too-large" } }), "daemon", "personality-kind"],
    ["personality-lines", changed(personality, { personality: { kind: "section", lines: Array(25).fill("Calm."), more: true } }), "daemon", "personality-lines"],
    ["personality-control", changed(personality, { personality: { kind: "section", lines: ["Calm.\nBrief."], more: false } }), "daemon", "personality-lines"],
    // The status judge refuses these too: a line separator and a C1 control.
    ["personality-separator", changed(personality, { personality: { kind: "section", lines: ["Calm.\u2028Brief."], more: false } }), "daemon", "personality-lines"],
    ["personality-c1", changed(personality, { personality: { kind: "section", lines: ["Calm.\u0085"], more: false } }), "daemon", "personality-lines"],
    ["personality-empty-lines", changed(personality, { personality: { kind: "section", lines: [], more: false } }), "daemon", "personality-lines"],
    ["personality-empty-line", changed(personality, { personality: { kind: "section", lines: [""], more: false } }), "daemon", "personality-lines"],
    ["personality-more", changed(personality, { personality: { kind: "section", lines: ["Calm."], more: "yes" } }), "daemon", "personality-lines"],
    ["start-text-direction", JSON.stringify(startText), "shell", "direction-start-text"],
    ["start-text-shape", changed(startText, { bytes: 5720 }), "daemon", "shape-start-text"],
    ["start-text-size-shape", changed(startText, { size: { ...startText.size, bytes: 5720 } }), "daemon", "shape-start-text"],
    ["start-text-unreadable-shape", changed(startText, { size: { kind: "unreadable", tokens: 0 } }), "daemon", "shape-start-text"],
    ["start-text-kind", changed(startText, { size: { kind: "none" } }), "daemon", "start-text-kind"],
    ["start-text-size", changed(startText, { size: null }), "daemon", "start-text"],
    ["start-text-total", changed(startText, { size: { ...startText.size, tokens: -10 } }), "daemon", "start-text-tokens"],
    ["start-text-fraction", changed(startText, { size: { ...startText.size, tokens: 1.5 } }), "daemon", "start-text-tokens"],
    ["start-text-layers", changed(startText, { size: { ...startText.size, layers: {} } }), "daemon", "start-text-tokens"],
    ["start-text-layer-name", startLayers([{ layer: "home/other", tokens: 20 }]), "daemon", "start-text-tokens"],
    ["start-text-layer-order", startLayers([{ layer: "home/state", tokens: 60 }, { layer: "home/skills", tokens: 20 }]), "daemon", "start-text-tokens"],
    ["start-text-layer-twice", startLayers([{ layer: "home/state", tokens: 60 }, { layer: "home/state", tokens: 60 }]), "daemon", "start-text-tokens"],
    ["start-text-layer-tokens", startLayers([{ layer: "home/state", tokens: -1 }]), "daemon", "start-text-tokens"],
    ["start-text-layer-shape", startLayers([{ layer: "home/state", tokens: 60, bytes: 240 }]), "daemon", "start-text-tokens"],
    ["voices-separator", changed(voices, { voices: [{ label: "Heart\u2029", value: "af_heart" }] }), "daemon", "voice"],
    ["homes-current-path", changed(homes, { current: "/user/One" }), "daemon", "home-current"],
    ["homes-id", changed(homes, { homes: [{ ...homes.homes[0], id: "../../outside" }] }), "daemon", "home-id"],
    ["homes-id-duplicate", changed(homes, { homes: [homes.homes[0], { ...homes.homes[0], value: "~/Other" }] }), "daemon", "home-id-duplicate"],
    ["homes-bound", changed(homes, { homes: Array(11).fill(homes.homes[0]) }), "daemon", "home-choices"],
    ["homes-duplicate", changed(homes, { homes: homes.homes.concat(homes.homes) }), "daemon", "home-duplicate"],
    ["level-direction", JSON.stringify(level), "shell", "direction-level"],
    ["level-bound", changed(level, { level: { capture: 1.01, playback: 0 } }), "daemon", "level"],
    ["playback-level-bound", changed(level, { level: { capture: 0, playback: -0.01 } }), "daemon", "level"],
    ["json", "{", "shell", "json"],
    ["object", "[]", "shell", "object"],
    ["version", changed(hello, { v: 2 }), "shell", "version"],
    ["generation", changed(hello, { gen: -1 }), "shell", "generation"],
    ["generation-fraction", changed(hello, { gen: 0.5 }), "shell", "generation"],
    ["generation-overflow", changed(hello, { gen: 9007199254740992 }), "shell", "generation"],
    ["direction", JSON.stringify(hello), "other", "direction"],
    ["hello-direction", JSON.stringify(hello), "daemon", "direction-hello"],
    ["status-direction", JSON.stringify(status), "shell", "direction-status"],
    ["type", changed(hello, { type: "unknown" }), "shell", "type"],
    ["hello-shape", changed(hello, { surprise: true }), "shell", "shape-hello"],
    ["status-shape", changed(status, { surprise: true }), "daemon", "shape-status"],
    ["settings", changed(hello, { settings: {} }), "shell", "shape-settings"],
    ...[false, true].map(echoCancel => ["echo-setting-" + echoCancel,
        changed(hello, { settings: { ...hello.settings, echoCancel } }), "shell", "shape-settings"]),
    ["mode", changed(hello, { settings: { ...hello.settings, mode: "continuous" } }), "shell", "mode"],
    ["extra-setting", changed(hello, { settings: { ...hello.settings, extra: "" } }), "shell", "shape-settings"],
    ["missing-brain", changed(hello, { settings: { ...hello.settings, brain: undefined } }), "shell", "shape-settings"],
    ["brain-setting", changed(hello, { settings: { ...hello.settings, brain: 1 } }), "shell", "shape-settings"],
    ["keys", changed(hello, { keys: { talk: "SUPER+A" } }), "shell", "shape-keys"],
    ["key-type", changed(hello, { keys: { ...hello.keys, talk: false } }), "shell", "key-talk"],
    ["key-empty", changed(hello, { keys: { ...hello.keys, talk: "" } }), "shell", "key-talk"],
    ["intent-direction", JSON.stringify(intent), "daemon", "direction-intent"],
    ["intent-shape", changed(intent, { extra: true }), "shell", "shape-intent"],
    ["intent-name", changed(intent, { intent: "approve" }), "shell", "intent"],
    ["say-shape", changed(say, { extra: true }), "shell", "shape-say"],
    ["say-empty", changed(say, { text: "" }), "shell", "say-text"],
    ["say-blank", changed(say, { text: "   " }), "shell", "say-text"],
    ["say-long", changed(say, { text: "a".repeat(4097) }), "shell", "say-text"],
    ["say-control", changed(say, { text: "a\nb" }), "shell", "say-text"],
    ["confirm-shape", changed(confirm, { extra: true }), "shell", "shape-confirm"],
    ["confirm-id", changed(confirm, { id: "made-up" }), "shell", "approval-id"],
    ["confirm-digest", changed(confirm, { digest: "A".repeat(64) }), "shell", "approval-digest"],
    ["confirm-voice", changed(confirm, { source: "voice" }), "shell", "approval-source"],
    ["confirm-model", changed(confirm, { source: "model" }), "shell", "approval-source"],
    ["cancel-shape", changed(cancel, { digest: confirm.digest }), "shell", "shape-cancel"],
    ["memory-confirm-shape", changed(memoryConfirm, { extra: true }), "shell", "shape-memory-intent"],
    ["memory-confirm-id", changed(memoryConfirm, { id: "bad" }), "shell", "memory-intent"],
    ["memory-confirm-hash", changed(memoryConfirm, { hash: "B".repeat(64) }), "shell", "memory-intent"],
    ["shown-direction", JSON.stringify(shown), "daemon", "direction-shown"],
    ["shown-shape", changed(shown, { source: "button" }), "shell", "shape-shown"],
    ["shown-id", changed(shown, { id: "" }), "shell", "approval-id"],
    ["directories-shape", changed(hello, { directories: {} }), "shell", "shape-directories"],
    ["directory", changed(hello, { directories: { ...hello.directories, data: "relative" } }), "shell", "directory-data"],
    ["directory-control", changed(hello, { directories: { ...hello.directories, data: "/path\n" } }), "shell", "directory-data"],
    ["lock", changed(hello, { locked: null }), "shell", "lock"],
    ["revision", changed(hello, { revision: "" }), "shell", "revision"],
    ["daemon", changed(status, { daemon: "listening" }), "daemon", "daemon"],
    // ChainedEngine select: one keyed cause per failing step, speech first.
    ["status-causes-missing", changed(status, { causes: undefined }), "daemon", "shape-status"],
    ["status-causes-list", changed(status, { causes: {} }), "daemon", "causes"],
    ["status-causes-order", changed(status, { causes: ["brain=unselected", "speech=local-not-set-up"] }), "daemon", "causes"],
    ["status-causes-twice", changed(status, { causes: ["brain=unselected", "brain=account-unavailable"] }), "daemon", "causes"],
    ["status-causes-step", changed(status, { causes: ["voice=local-not-set-up"] }), "daemon", "causes"],
    ["status-causes-home-order", changed(status, { causes: ["speech=local-not-set-up", "home=link"] }), "daemon", "causes"],
    ["status-causes-home-twice", changed(status, { causes: ["home=link", "guidance=home-skills-too-large"] }), "daemon", "causes"],
    ["status-causes-key", changed(status, { causes: ["speech=Not set up"] }), "daemon", "causes"],
    ["status-causes-text", changed(status, { causes: [7] }), "daemon", "causes"],
    // Guidance.compose's overBudget: the home texts over their budget, in
    // layer order, each once, none of them a step's cause.
    ["status-cautions-missing", changed(status, { cautions: undefined }), "daemon", "shape-status"],
    ["status-cautions-list", changed(status, { cautions: {} }), "daemon", "cautions"],
    ["status-cautions-order", changed(status, { cautions: ["guidance=memory-over-budget", "guidance=agents-over-budget"] }), "daemon", "cautions"],
    ["status-cautions-twice", changed(status, { cautions: ["guidance=agents-over-budget", "guidance=agents-over-budget"] }), "daemon", "cautions"],
    ["status-cautions-cause", changed(status, { cautions: ["guidance=home-skills-too-large"] }), "daemon", "cautions"],
    ["state-direction", JSON.stringify(state), "shell", "direction-state"],
    ["state-shape", changed(state, { extra: 1 }), "daemon", "shape-state"],
    ["state-seq", changed(state, { seq: 0 }), "daemon", "sequence"],
    ["state-regions", changed(state, { state: {} }), "daemon", "state"],
    ["state-gen", changed(state, { gen: 1 }), "daemon", "state-generation"],
    ["state-phase", changed(state, { phase: "listening" }), "daemon", "phase"],
    ["state-brain", changed(state, { brain: "bad\nbrain" }), "daemon", "brain"],
    ["request-direction", JSON.stringify(request), "shell", "direction-request"],
    ["request-shape", changed(request, { extra: 1 }), "daemon", "shape-request"],
    ["request-id", changed(request, { id: 0 }), "daemon", "request-id"],
    ["request-id-fraction", changed(request, { id: 1.5 }), "daemon", "request-id"],
    ["request-kind", changed(request, { kind: "compositor.sendKeys" }), "daemon", "request-kind"],
    ["request-tui-invalid", changed(request, { kind: "tui.run" }), "daemon", "request-args"],
    ["request-kind-proto", changed(request, { kind: "__proto__" }), "daemon", "request-kind"],
    ["request-count", changed(request, { args: ["0xa1", 1] }), "daemon", "request-args"],
    ["request-type", changed(request, { args: ["0xa1", "1", 2] }), "daemon", "request-args"],
    ["request-integer", changed(request, { args: ["0xa1", 1.5, 2] }), "daemon", "request-args"],
    ["request-text-empty", changed(request, { kind: "compositor.focusWindow", args: [""] }), "daemon", "request-args"],
    ["request-text-nul", changed(request, { kind: "desktop.launch", args: ["a\u0000b"] }), "daemon", "request-args"],
    ["request-text-size", changed(request, { kind: "desktop.launch", args: ["x".repeat(4097)] }), "daemon", "request-args"],
    ["request-argv-empty", changed(request, { kind: "run.detached", args: [] }), "daemon", "request-args"],
    ["request-argv-size", changed(request, { kind: "run.detached", args: Array(65).fill("a") }), "daemon", "request-args"],
    ["request-argv-word", changed(request, { kind: "run.detached", args: ["gio", ""] }), "daemon", "request-args"],
    ["request-args-object", changed(request, { kind: "desktop.list", args: {} }), "daemon", "request-args"],
    ["reply-direction", JSON.stringify(reply), "daemon", "direction-reply"],
    ["reply-shape", changed(reply, { extra: 1 }), "shell", "shape-reply"],
    ["reply-id", changed(reply, { id: -1 }), "shell", "request-id"],
    ["reply-kind", changed(reply, { kind: "launch" }), "shell", "request-kind"],
    ["reply-answer-empty", changed(reply, { answer: "" }), "shell", "reply-answer"],
    ["reply-answer-line", changed(reply, { answer: "refused:\nsecond" }), "shell", "reply-answer"],
    ["reply-answer-size", changed(reply, { answer: "x".repeat(301) }), "shell", "reply-answer"],
    ["reply-data-none", changed(reply, { data: {} }), "shell", "reply-data"],
    ["reply-data-refused", changed(entryReply, { answer: "refused: desktop=unknown" }), "shell", "reply-data"],
    ["reply-entries-shape", changed(listReply, { data: { entries: [] } }), "shell", "shape-entries"],
    ["reply-entries-list", changed(listReply, { data: { entries: {}, complete: true } }), "shell", "reply-data"],
    ["reply-entries-size", changed(listReply, { data: { entries: Array(513).fill(entry), complete: false } }), "shell", "reply-data"],
    ["reply-entry-shape", changed(listReply, { data: { entries: [{ ...entry, terminal: false }], complete: true } }), "shell", "shape-entry"],
    ["reply-launch-command", changed(entryReply, { data: { ...entryReply.data, command: ["example"] } }), "shell", "shape-entry"],
    ["request-kind-entry", changed(request, { kind: "desktop.entry", args: ["org.example.App"] }), "daemon", "request-kind"],
    ["reply-entry-id", changed(listReply, { data: { entries: [{ ...entry, id: "" }], complete: true } }), "shell", "entry"],
    ["reply-entry-name", changed(listReply, { data: { entries: [{ ...entry, name: "a\nb" }], complete: true } }), "shell", "entry"],
    ["reply-entry-duplicate", changed(listReply, { data: { entries: [entry, entry], complete: true } }), "shell", "entry-duplicate"],
    ["reply-entry-terminal", changed(entryReply, { data: { ...entryReply.data, terminal: "no" } }), "shell", "entry"],
    ["dictation-text-long", changed(stopReply, { data: { text: "a".repeat(4097) } }), "shell", "dictation-text"],
    ["dictation-text-extra", changed(stopReply, { data: { text: "words", status: "ok" } }), "shell", "shape-dictation-text"],
    ["dictation-text-nul", changed(stopReply, { data: { text: "a\u0000b" } }), "shell", "dictation-text"],
    ["dictation-start-args", changed(request, { kind: "dictation.start", args: ["text"] }), "daemon", "request-args"],
    ["dictation-start-data", changed(reply, { kind: "dictation.start", data: { text: "words" } }), "shell", "reply-data"],
    ["task-terminal", changed(hello, { settings: { ...hello.settings, taskTerminal: "kitty" } }), "shell", "task-terminal"],
    ["sounds-type", changed(hello, { settings: { ...hello.settings, sounds: "true" } }), "shell", "sounds"],
    ["dictation-setting-type", changed(hello, { settings: { ...hello.settings, dictation: [""] } }), "shell", "dictation-setting"],
    ["dictation-setting-step", changed(hello, { settings: { ...hello.settings, dictation: "brain=dictation-device" } }), "shell", "dictation-setting"],
    ["cloud-vision", changed(hello, { settings: { ...hello.settings, cloudVision: "sometimes" } }), "shell", "cloud-vision"],
    ["voice-provider", changed(hello, { settings: { ...hello.settings, voiceProvider: "other" } }), "shell", "voice-settings"],
    ["live-account-type", changed(hello, { settings: { ...hello.settings, voiceAccount: true } }), "shell", "voice-settings"],
    ["live-account-control", changed(hello, { settings: { ...hello.settings, voiceAccount: "key\n" } }), "shell", "voice-settings"],
    ["live-account-size", changed(hello, { settings: { ...hello.settings, voiceAccount: "x".repeat(201) } }), "shell", "voice-settings"],
    ["home-type", changed(hello, { settings: { ...hello.settings, home: 7 } }), "shell", "home-setting"],
    ["home-control", changed(hello, { settings: { ...hello.settings, home: "~/Jarvis\n" } }), "shell", "home-setting"],
    ["home-size", changed(hello, { settings: { ...hello.settings, home: "x".repeat(4097) } }), "shell", "home-setting"],
    ["model-type", changed(hello, { settings: { ...hello.settings, model: 7 } }), "shell", "shape-settings"],
    ["effort-type", changed(hello, { settings: { ...hello.settings, effort: true } }), "shell", "shape-settings"],
    ["fallbacks-type", changed(hello, { settings: { ...hello.settings, fallbacks: {} } }), "shell", "fallbacks"],
    ["fallbacks-shape", changed(hello, { settings: { ...hello.settings, fallbacks: [{ name: "one", brain: "b" }] } }), "shell", "shape-fallback"],
    ["fallbacks-model-type", changed(hello, { settings: { ...hello.settings, fallbacks: [{ name: "one", brain: "b", model: 7 }] } }), "shell", "fallbacks"],
    ["missing-cloud-vision", changed(hello, { settings: { ...hello.settings, cloudVision: undefined } }), "shell", "shape-settings"],
    ["private-windows-type", changed(hello, { settings: { ...hello.settings, privateWindows: ["bitwarden"] } }), "shell", "private-windows"],
    ["private-windows-control", changed(hello, { settings: { ...hello.settings, privateWindows: "bitwarden\nvault" } }), "shell", "private-windows"],
    ["private-windows-size", changed(hello, { settings: { ...hello.settings, privateWindows: "a".repeat(1025) } }), "shell", "private-windows"],
    ["missing-task-terminal", changed(hello, { settings: { ...hello.settings, taskTerminal: undefined } }), "shell", "shape-settings"],
    ["cloned-voice-type", changed(hello, { settings: { ...hello.settings, clonedVoice: "on" } }), "shell", "cloned-voice"],
    ["task-stop-shape", changed(taskStop, { task: undefined }), "shell", "shape-task-stop"],
    ["task-stop-id", changed(taskStop, { task: "../home" }), "shell", "task-id"],
    ["tui-state-direction", JSON.stringify(tuiState), "daemon", "direction-tui-state"],
    ["tui-state-shape", changed(tuiState, { code: 0 }), "shell", "shape-tui-state"],
    ["tui-state-name", changed(tuiState, { name: "accounts" }), "shell", "tui-name"],
    ["tui-state-running", changed(tuiState, { running: "yes" }), "shell", "tui-running"],
    ["task-request-name", changed(taskRequest, { name: "accounts" }), "daemon", "shape-request"],
    ["task-request-args", changed(taskRequest, { args: [taskRequest.args[0], "--other"] }), "daemon", "request-args"],
    ["task-request-spec", changed(taskRequest, { args: ["tasks/one.json"] }), "daemon", "request-args"],
    ["tasks-direction", JSON.stringify(tasks), "shell", "direction-tasks"],
    ["tasks-shape", changed(tasks, { live: 1 }), "daemon", "shape-tasks"],
    ["task-count", changed(tasks, { count: -1 }), "daemon", "task-count"],
    ["task-count-fraction", changed(tasks, { count: 0.5 }), "daemon", "task-count"],
    ["task-answer-direction", JSON.stringify(taskAnswer), "shell", "direction-task-answer"],
    ["task-answer-shape", changed(taskAnswer, { reason: "" }), "daemon", "shape-task-answer"],
    ["task-answer-task", changed(taskAnswer, { task: "" }), "daemon", "answer-task-id"],
    ["task-answer-value", changed(taskAnswer, { answer: "Stopped!" }), "daemon", "task-answer"]
];
function rejected(logic, row) {
    assert.throws(() => logic.accept(row[1], row[2]), { message: "jarvis: protocol=" + row[3] }, row[0]);
}
for (const row of cases) rejected(Protocol, row);
assert.throws(() => Protocol.accept(null, "shell"), { message: "jarvis: protocol=line-not-string" });
for (const locked of [false, true]) {
    const message = { ...hello, locked };
    assert.equal(JSON.stringify(Protocol.accept(JSON.stringify(message), "shell")), JSON.stringify(message));
}
for (const brain of ["", "cli:saved-unavailable-id"])
    assert.equal(Protocol.accept(changed(hello, { settings: { ...hello.settings, brain } }), "shell").settings.brain, brain);
// The voices the daemon runs: the local one, the two duplex cloud voices and
// ElevenLabs, which speaks over the local one.
function voiceProviders(logic) {
    for (const voiceProvider of ["local", "realtime", "gemini", "elevenlabs"]) {
        let accepted;
        assert.doesNotThrow(() => { accepted = logic.accept(changed(hello, { settings: { ...hello.settings, voiceProvider } }), "shell"); }, voiceProvider);
        assert.equal(accepted.settings.voiceProvider, voiceProvider);
    }
}
voiceProviders(Protocol);
for (const daemon of ["ready", "locked"])
    assert.equal(Protocol.accept(changed(status, { daemon }), "daemon").daemon, daemon);
for (const causes of [[], ["speech=local-not-set-up"], ["brain=unselected"], ["speech=local-not-ready", "brain=account-unavailable"],
    ["home=link", "speech=local-not-set-up", "brain=unselected"], ["guidance=home-skills-too-large", "brain=unselected"]])
    assert.equal(JSON.stringify(Protocol.accept(changed(status, { causes }), "daemon").causes), JSON.stringify(causes));
for (const cautions of [["guidance=agents-over-budget"], ["guidance=persona-over-budget", "guidance=agents-over-budget",
    "guidance=skills-over-budget", "guidance=memory-over-budget", "guidance=start-over-budget"]])
    assert.equal(JSON.stringify(Protocol.accept(changed(status, { cautions, causes: ["brain=unselected"] }), "daemon").cautions), JSON.stringify(cautions));
assert.equal(JSON.stringify(Protocol.accept(JSON.stringify(state), "daemon")), JSON.stringify(state));
for (const reason of ["check-timeout", "speech=local-wake-failed"]) {
    const failed = { ...state, state: { ...state.state, check: { kind: "failed", reason } } };
    assert.deepEqual(JSON.parse(JSON.stringify(Protocol.accept(JSON.stringify(failed), "daemon"))), failed,
        "a microphone check failure carries its cause over the wire");
}
// A duplex reply whose words wait at the voice for their first audio.
const dueState = (() => {
    const Session = Protocol.Session;
    let s = Session.initial();
    for (const e of [{ type: "snapshot", locked: false, engine: "duplex", configured: true, settings: {} },
        { type: "indicator", shown: true }, { type: "talk-down" }])
        s = Session.reduce(s, { at: 1, ...e }).state;
    s = Session.reduce(s, { type: "speech-due", at: 2, gen: s.speech.gen, op: s.speech.op, due: true }).state;
    assert.equal(s.speech.reply.kind, "due");
    return { ...state, gen: s.gen, state: JSON.parse(JSON.stringify(s)), phase: Session.phaseOf(s) };
})();
assert.equal(JSON.stringify(Protocol.accept(JSON.stringify(dueState), "daemon")), JSON.stringify(dueState), "a due reply is a wire state");
rejected(Protocol, ["state-speech-reply", JSON.stringify({ ...dueState, state: { ...dueState.state, speech: { ...dueState.state.speech, reply: { kind: "coming" } } } }),
    "daemon", "state"]);
for (const name of ["talk-down", "talk-up", "mute", "stop", "voice-check", "preview"])
    assert.equal(Protocol.accept(changed(intent, { intent: name }), "shell").intent, name);
assert.equal(JSON.stringify(Protocol.accept(JSON.stringify(say), "shell")), JSON.stringify(say));
for (const shown of [personality, { ...personality, personality: { kind: "none" } }, { ...personality, personality: { kind: "missing" } }, voices, { ...voices, voices: [] },
    startText, { ...startText, size: { kind: "unreadable" } }, { ...startText, size: { kind: "read", tokens: 1350, layers: [] } },
    { ...startText, size: { kind: "read", tokens: 9000, layers: ["home/persona", "home/AGENTS.md", "home/skills", "home/MEMORY.md", "home/state"].map(layer => ({ layer, tokens: 100 })) } }])
    assert.equal(JSON.stringify(Protocol.accept(JSON.stringify(shown), "daemon")), JSON.stringify(shown));
// The section's text as the wire carries it: blank lines dropped, a long
// line cut at a space into pieces of 200, tabs as spaces, 24 pieces at most.
{
    const long = Array(60).fill("word").join(" ");
    const section = Protocol.personalitySection("Calm\tand brief.\n\n" + long + " " + long + "\n" + Array(30).fill("Line.").join("\n"));
    assert.deepEqual([section.lines[0], section.lines.length, section.more], ["Calm and brief.", 24, true]);
    assert.ok(section.lines.slice(1, 3).every(line => line.length <= 200 && !line.startsWith(" ") && !line.endsWith(" ")), "a long line splits at a space");
    assert.equal(section.lines.slice(1).join(" ").startsWith(long + " " + long), true, "no word is lost at a cut");
    assert.equal(Protocol.accept(changed(personality, { personality: section }), "daemon").personality.lines.length, 24);
    assert.equal(JSON.stringify(Protocol.personalitySection("Brief.")), JSON.stringify({ kind: "section", lines: ["Brief."], more: false }));
    // What the status judge refuses becomes a space, so a pasted line
    // separator never reaches Settings.
    assert.equal(JSON.stringify(Protocol.personalitySection("Calm.\u2028Brief.\u0085")), JSON.stringify({ kind: "section", lines: ["Calm. Brief."], more: false }));
    // The copy of the status judge's rule is the judge's own.
    const SettingValues = load(path.join(__dirname, "../shell/Commons/SettingValues.js"));
    assert.equal(Protocol.STATUS_UNPRINTABLE.source, SettingValues.CONTROL_OR_SEPARATOR.source, "the wire refuses what the status judge refuses");
}
for (const [message, direction] of [
    [taskOpen, "shell"], [{ ...taskOpen, task: "a".repeat(64) }, "shell"],
    [taskOpened, "daemon"], [{ ...taskOpened, task: "a".repeat(64), answer: "a".repeat(40) }, "daemon"],
    [{ ...taskList, rows: [] }, "daemon"], [{ ...auditFailures, rows: [] }, "daemon"],
    [{ ...taskList, rows: Array(16).fill({ ...taskRow, id: "a".repeat(64), goal: "g".repeat(200), agent: "a".repeat(128),
        failure: "f".repeat(128), createdAt: Number.MAX_SAFE_INTEGER, endedAt: Number.MAX_SAFE_INTEGER }) }, "daemon"],
    [{ ...auditFailures, rows: Array(20).fill({ ...auditRow, tool: "t".repeat(128) }) }, "daemon"],
    [{ ...auditFailures, rows: ["input-silent", "unheard", "voice-stopped"].map(cause => ({ ...auditRow, tool: "release", decision: "send", cause })) }, "daemon"]
]) assert.equal(JSON.stringify(Protocol.accept(JSON.stringify(message), direction)), JSON.stringify(message));
for (const failure of [null, 1, -1, Number.MAX_SAFE_INTEGER, "lost", "reported-failed"])
    assert.equal(Protocol.accept(changed(taskList, { rows: [{ ...taskRow, failure }] }), "daemon").rows[0].failure, failure);
for (const message of [confirm, { ...confirm, source: "button" }, cancel, memoryConfirm, memoryDiscard, shown])
    assert.equal(JSON.stringify(Protocol.accept(JSON.stringify(message), "shell")), JSON.stringify(message));
for (const shown of [false, true])
    assert.equal(Protocol.accept(changed(indicator, { shown }), "shell").shown, shown);
assert.equal(Protocol.accept(changed(hello, { settings: { ...hello.settings, mode: "toggle" },
    keys: { talk: null, mute: null, stop: null, confirm: null, console: null } }), "shell").settings.mode, "toggle");
assert.equal(Protocol.accept(changed(hello, { settings: { ...hello.settings, mode: "always" },
    keys: { talk: null, mute: null, stop: null, confirm: null, console: null } }), "shell").settings.mode, "always");
for (const message of [devices, homes, level, audioFault, memory, memoryInbox, { ...memoryInbox, entries: [{ ...memoryEntry, kind: "replace" }] },
    { ...memoryInbox, entries: [{ ...memoryEntry, problem: "write" }] },
    taskRequest, tasks, taskAnswer, taskPrompts, taskResponse, { ...tasks, count: 0 },
    transcript, { ...transcript, role: "assistant", stage: "final", text: "a".repeat(4096), rev: 2 },
    shellStatus, { ...shellStatus, availability: { kind: "checking" } },
    { ...shellStatus, availability: { kind: "unavailable", reason: "bwrap-missing" } }])
    assert.equal(JSON.stringify(Protocol.accept(JSON.stringify(message), "daemon")), JSON.stringify(message));
for (const message of [taskRespond, { ...taskRespond, answer: { v: 1, kind: "reply", text: "main" } }, requirementsScan, { ...requirementsScan, scan: 0 }, { ...requirementsScan, scan: Number.MAX_SAFE_INTEGER }, taskStop, tuiState, { ...tuiState, running: false }, taskReply, { ...taskReply, answer: "ok" },
    { ...taskReply, answer: "x".repeat(300) }])
    assert.equal(JSON.stringify(Protocol.accept(JSON.stringify(message), "shell")), JSON.stringify(message));
for (const cloudVision of ["ask", "allow", "never"])
    assert.equal(Protocol.accept(changed(hello, { settings: { ...hello.settings, cloudVision } }), "shell").settings.cloudVision, cloudVision);
for (const privateWindows of ["", "a".repeat(1024), manifest.settings.privateWindows])
    assert.equal(Protocol.accept(changed(hello, { settings: { ...hello.settings, privateWindows } }), "shell").settings.privateWindows, privateWindows);
for (const dictation of ["", "speech=dictation-device", "speech=dictation-starting"])
    assert.equal(Protocol.accept(changed(hello, { settings: { ...hello.settings, dictation } }), "shell").settings.dictation, dictation);
for (const taskTerminal of ["auto", "tmux", "floating"])
    assert.equal(Protocol.accept(changed(hello, { settings: { ...hello.settings, taskTerminal } }), "shell").settings.taskTerminal, taskTerminal);
assert.equal(Protocol.MAX_PENDING_REQUESTS, 16);
assert.equal(Protocol.MEMORY_INBOX_BYTES, 128 * 1024);
assert.equal(Protocol.memoryInboxEntries([{ ...memoryEntry, problem: "other" }, memoryEntry]).length, 1);
assert.equal(Protocol.memoryInboxEntries(Array(9).fill({ ...memoryEntry, text: "x".repeat(16 * 1024) })).length, 7);
assert.equal(Protocol.accept(JSON.stringify(inputReady), "daemon").commands.length, 2);
for (const value of [0, 1])
    assert.equal(Protocol.accept(changed(level, { level: { capture: value, playback: value } }), "daemon").level.capture, value);
assert.equal(Protocol.accept(changed(hello, { settings: { ...hello.settings, microphone: "missing.mic" } }), "shell").settings.microphone, "missing.mic");
for (const message of [request, { ...request, kind: "run.detached", args: ["gio", "open", "/path with space"] },
    { ...request, kind: "desktop.launch", args: ["Line\nnext"] }, { ...request, kind: "desktop.list", args: [] },
    { ...request, kind: "compositor.fullscreenWindow", args: ["fullscreen", "set"] }, { ...request, id: Number.MAX_SAFE_INTEGER }])
    assert.equal(JSON.stringify(Protocol.accept(JSON.stringify(message), "daemon")), JSON.stringify(message));
for (const kind of Object.keys(Protocol.REQUESTS)) {
    const rule = Protocol.REQUESTS[kind].args;
    const args = rule === "argv" ? ["program"] : rule === "task-spec" ? ["/private/task.json"] : rule === "input-point" ? [1, 2]
        : rule.map(type => type === "text" ? "value" : 1);
    assert.equal(Protocol.accept(changed(request, { kind, args }), "daemon").kind, kind);
}
for (const message of [inputReply, keysReply, reply, listReply, entryReply, { ...reply, answer: "refused: dispatcher=moveWindow argument=1" },
    { ...entryReply, answer: "refused: desktop=unknown", data: null }, { ...listReply, data: { entries: [], complete: false } },
    stopReply, { ...stopReply, data: { text: "" } }, { ...stopReply, data: { text: "a".repeat(4096) } },
    { ...stopReply, answer: "refused: dictation=failed reason=stop code=1", data: null },
    { ...reply, kind: "dictation.start" }, { ...reply, kind: "dictation.start", answer: "refused: dictation=busy holder=vgs.voice" },
    { ...reply, kind: "dictation.cancel" }])
    assert.equal(JSON.stringify(Protocol.accept(JSON.stringify(message), "shell")), JSON.stringify(message));
// The service's builders produce what the judge accepts, from Quickshell's
// DesktopEntry fields as Service.qml copies them.
const shellEntry = (id, values = {}) => ({ id, name: "Name " + id, startupClass: "", noDisplay: false, terminal: false, ...values });
const built = Protocol.desktopEntries([shellEntry("zeta"), shellEntry("alpha", { name: "Tab\tname", startupClass: "Alpha" }),
    shellEntry("hidden", { noDisplay: true }), shellEntry("bad\nid"), shellEntry("x".repeat(129))]);
assert.equal(JSON.stringify(built), JSON.stringify({ entries: [{ id: "alpha", name: "Tab name", startupClass: "Alpha" },
    { id: "zeta", name: "Name zeta", startupClass: "" }], complete: true }));
assert.equal(Protocol.accept(changed(listReply, { data: built }), "shell").data.entries.length, 2);
const many = Protocol.desktopEntries(Array.from({ length: 600 }, (_, n) => shellEntry("app" + String(n).padStart(3, "0"))));
assert.equal(many.entries.length, 512);
assert.equal(many.complete, false);
const wide = Protocol.desktopEntries(Array.from({ length: 512 }, (_, n) => shellEntry(String(n).padStart(3, "0") + "é".repeat(120), { name: "語".repeat(128), startupClass: "語".repeat(128) })));
assert.equal(wide.complete, false, "the byte bound cuts before the line limit");
assert.ok(Protocol.bytes(changed(listReply, { data: wide })) < Protocol.MAX_LINE_BYTES);
Protocol.accept(changed(listReply, { data: wide }), "shell");
assert.equal(JSON.stringify(Protocol.desktopEntry(shellEntry("tool", { terminal: true }), true)),
    JSON.stringify({ id: "tool", name: "Name tool", startupClass: "", terminal: true }));
assert.equal(Protocol.desktopEntry(shellEntry("tool"), true).terminal, false);
// The service refuses a desktop change while the session is locked, and
// nothing else. Expected kinds are written by hand.
const acting = ["compositor.focusWorkspace", "compositor.focusWindow", "compositor.moveWindowToWorkspace",
    "compositor.toggleSpecialWorkspace", "compositor.closeWindow", "compositor.fullscreenWindow", "compositor.floatWindow",
    "compositor.moveWindow", "compositor.moveCursor", "compositor.resizeWindow", "compositor.focusMonitor", "compositor.reveal", "run.detached", "desktop.launch", "tui.run"];
function lockedRows(logic) {
    assert.deepEqual(Object.keys(logic.REQUESTS).sort(), [...acting, "desktop.list", "input.observe", "input.keys",
        "dictation.start", "dictation.stop", "dictation.cancel"].sort(), "the request kinds");
    for (const kind of Object.keys(logic.REQUESTS)) {
        assert.equal(logic.lockedRefusal(kind, true), acting.includes(kind) ? "refused: locked" : "", kind + " while locked");
        assert.equal(logic.lockedRefusal(kind, false), "", kind + " while unlocked");
    }
}
lockedRows(Protocol);
assert.equal(Protocol.desktopEntry(shellEntry("hidden", { noDisplay: true }), true), null);
assert.equal(Protocol.answer("refused: a\nb"), "refused: a b");
assert.equal(Protocol.answer(""), "refused: answer=empty");
assert.equal(Protocol.answer("x".repeat(400)).length, 300);
for (const text of ["", "a", "é", "語", "😀", "\ud800"])
    assert.equal(Protocol.bytes(text), Buffer.byteLength(text), text);
const wire = JSON.stringify(status);
assert.equal(Protocol.accept(wire + " ".repeat(262144 - wire.length), "daemon").daemon, "ready");
assert.throws(() => Protocol.accept(wire + " ".repeat(262145 - wire.length), "daemon"),
    { message: "jarvis: protocol=line-too-long" });
assert.equal(Protocol.feed("", "a".repeat(262144)).tail.length, 262144);
assert.throws(() => Protocol.feed("a".repeat(262144), "a"), { message: "jarvis: protocol=line-too-long" });
assert.throws(() => Protocol.feed("", "é".repeat(131073)), { message: "jarvis: protocol=line-too-long" });
assert.equal(JSON.stringify(Protocol.feed("one", "\ntwo\nthree")), '{"lines":["one","two"],"tail":"three"}');

const parent = path.resolve(__dirname, "../tmp");
fs.mkdirSync(parent, { recursive: true });
const root = fs.mkdtempSync(path.join(parent, "jp-"));
const source = fs.readFileSync(file, "utf8");
let controls = 0;
try {
    if (process.argv[2] !== "--fresh") freshSuite(path.resolve(__dirname, ".."), "protocol", root);
    fs.copyFileSync(path.join(path.dirname(file), "Session.js"), path.join(root, "Session.js"));
    function control(name, needle, replacement, check, matches = 1) {
        assert.equal(source.split(needle).length - 1, matches, name + " mutation match");
        const mutated = source.split(needle).join(replacement);
        assert.notEqual(mutated, source);
        const copy = path.join(root, name + ".js");
        fs.writeFileSync(copy, mutated);
        assert.throws(() => check(load(copy)), assert.AssertionError, name + " must turn red");
        controls++;
    }
    const guards = [
        ["task-list-direction", 'if (direction !== "daemon") fail("direction-task-list");', "", "task-list-direction"],
        ["task-list-count", "message.rows.length > 16", "message.rows.length > 17", "task-list-count"],
        ["task-list-goal", "printable(row.goal, 1, 200)", "printable(row.goal, 1, 201)", "task-list-goal"],
        ["task-list-agent", "printable(row.agent, 1, FIELD_MAX)", "printable(row.agent, 1, FIELD_MAX + 1)", "task-list-agent"],
        ["task-list-state", '].indexOf(row.state) === -1', '].indexOf(row.state) < -1', "task-list-state"],
        ["task-list-failure", "printable(row.failure, 1, FIELD_MAX)", "printable(row.failure, 1, FIELD_MAX + 1)", "task-list-failure"],
        ["task-list-zero", " && row.failure !== 0", "", "task-list-zero"],
        ["task-list-created", "row.createdAt < 0", "row.createdAt < -1", "task-list-created"],
        ["task-list-ended", "row.endedAt >= 0", "row.endedAt >= -1", "task-list-ended"],
        ["audit-direction", 'if (direction !== "daemon") fail("direction-audit-failures");', "", "audit-direction"],
        ["audit-count", "message.rows.length > 20", "message.rows.length > 21", "audit-count"],
        ["audit-args", '["time", "tool", "effect", "decision", "outcome", "refusal", "cause"], "audit-row"', '["time", "tool", "effect", "decision", "outcome", "refusal", "cause", "args"], "audit-row"', "audit-args"],
        ["audit-time", '!/^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$/.test(row.time)', "false", "audit-time"],
        ["audit-tool", "printable(row.tool, 1, FIELD_MAX)", "printable(row.tool, 1, FIELD_MAX + 1)", "audit-tool"],
        ["audit-effect", "].indexOf(row.effect) !== -1", "].indexOf(row.effect) >= -1", "audit-effect"],
        ["audit-decision", "].indexOf(row.decision) === -1\n", "].indexOf(row.decision) < -1\n", "audit-decision"],
        ["audit-outcome", "].indexOf(row.outcome) === -1\n", "].indexOf(row.outcome) < -1\n", "audit-outcome"],
        ["audit-completed", '(["refuse", "withhold"].indexOf(row.decision) === -1 && ["failed", "unknown"].indexOf(row.outcome) === -1)', "false", "audit-completed"],
        ["audit-refusal", "].indexOf(row.refusal) !== -1", "].indexOf(row.refusal) >= -1", "audit-refusal"],
        ["audit-cause", "].indexOf(row.cause) !== -1", "].indexOf(row.cause) >= -1", "audit-cause"],
        ["task-open-direction", 'if (direction !== "daemon") fail("direction-task-open");', "", "task-open-direction"],
        ["task-open-answer-id", 'if (!taskId(message.task)) fail("open-task-id");', "", "task-open-answer-id"],
        ["task-open-answer", 'fail("task-open");', ";", "task-open-answer"],
        ["task-response-direction", 'if (direction !== "daemon") fail("direction-task-response");', 'if (false) fail("direction-task-response");', "task-response-direction"],
        ["task-prompt-kind", '["permission", "question"].indexOf(prompt.kind) === -1', 'false', "task-prompts-kind"],
        ["task-answer-kind", '["allow", "deny"].indexOf(response.kind) === -1', 'false', "task-respond-kind"],
        ["input-symbol-type", '!Number.isSafeInteger(key.codepoint)', 'false', "input-codepoint-0.5"],
        ["input-symbol-floor", ' || key.codepoint < 0', '', "input-codepoint--1"],
        ["input-symbol-ceiling", ' || key.codepoint > 0x10ffff', '', "input-codepoint-1114112"],
        ["input-symbol-scalar", ' || key.codepoint >= 0xd800 && key.codepoint <= 0xdfff', '', "input-codepoint-55296"],
        ["requirements-direction", 'if (direction !== "shell") fail("direction-requirements-scan");', 'if (false) fail("direction-requirements-scan");', "requirements-direction"],
        ["requirements-shape", 'keys(message, ["v", "type", "gen", "revision", "scan"], "requirements-scan");', 'if (false) keys(message, [], "requirements-scan");', "requirements-shape"],
        ["requirements-negative", 'message.scan < 0', 'false', "requirements-scan"],
        ["requirements-integer", '!Number.isSafeInteger(message.scan)', 'false', "requirements-fraction"],
        ["shell-status-direction", 'if (direction !== "daemon") fail("direction-shell-status");',
            'if (false) fail("direction-shell-status");', "shell-status-direction"],
        ["shell-availability", 'fail("shell-availability");', ';', "shell-availability"],
        ["shell-availability-shape", 'keys(availability, availability.kind === "unavailable" ? ["kind", "reason"] : ["kind"], "shell-availability");',
            'if (false) keys(availability, ["kind"], "shell-availability");', "shell-availability-shape"],
        ["shell-reason", 'fail("shell-reason");', ';', "shell-reason"],
        ["memory-direction", 'if (direction !== "daemon") fail("direction-memory");', 'if (false) fail("direction-memory");', "memory-direction"],
        ["memory-shape", 'keys(message, ["v", "type", "gen", "revision", "cause"], "memory");',
            'if (false) keys(message, [], "memory");', "memory-shape"],
        ["memory-cause", 'if (message.cause !== "memory=sqlite") fail("memory-cause");',
            'if (false) fail("memory-cause");', "memory-cause"],
        ["memory-inbox-direction", 'if (direction !== "daemon") fail("direction-memory-inbox");',
            'if (false) fail("direction-memory-inbox");', "memory-inbox-direction"],
        ["memory-inbox-shape", 'keys(message, ["v", "type", "gen", "revision", "entries"], "memory-inbox");',
            'if (false) keys(message, [], "memory-inbox");', "memory-inbox-shape"],
        ["memory-inbox-bound", 'message.entries.length > MEMORY_INBOX_MAX', 'false', "memory-inbox-bound"],
        ["memory-inbox-byte-bound", 'bytes(JSON.stringify(message.entries)) > MEMORY_INBOX_BYTES', 'false', "memory-inbox-byte-bound"],
        ["memory-entry-shape", 'keys(value, ["id", "target", "kind", "title", "labels", "text", "hash", "problem"], "memory-entry");',
            'if (false) keys(value, [], "memory-entry");', "memory-entry-shape"],
        ["memory-entry-target", '!memoryTarget(value.target)', 'false', "memory-entry-target"],
        ["memory-entry-text", '!memoryText(value.text)', 'false', "memory-entry-text"],
        ["memory-entry-labels", '!memoryLabels(value.labels)', 'false', "memory-entry-labels"],
        ["memory-entry-problem", '!/^(|exists|conflict|link|secret|hash|bootstrap|write)$/.test(value.problem)', 'false', "memory-entry-problem"],
        ["memory-intent-shape", 'keys(message, fields.concat(["id", "hash"]), "memory-intent");',
            'if (false) keys(message, [], "memory-intent");', "memory-confirm-shape"],
        ["memory-intent-hash", '!hash(message.hash)', 'false', "memory-confirm-hash"],
        ["approval-id", 'if (!approvalId(message.id)) fail("approval-id");',
            'if (false) fail("approval-id");', "confirm-id", 3],
        ["approval-digest", 'if (typeof message.digest !== "string" || !/^[0-9a-f]{64}$/.test(message.digest)) fail("approval-digest");',
            'if (false) fail("approval-digest");', "confirm-digest"],
        ["approval-source", 'if (["key", "button"].indexOf(message.source) === -1) fail("approval-source");',
            'if (false) fail("approval-source");', "confirm-voice"],
        ["shown-direction", 'if (direction !== "shell") fail("direction-shown");',
            'if (false) fail("direction-shown");', "shown-direction"],
        ["indicator-direction", 'if (direction !== "shell") fail("direction-indicator");',
            'if (false) fail("direction-indicator");', "indicator-direction"],
        ["indicator-shown", 'if (typeof message.shown !== "boolean") fail("indicator");',
            'if (false) fail("indicator");', "indicator-shown"],
        ["indicator-shape", 'keys(message, ["v", "type", "gen", "revision", "shown"], "indicator");',
            'void message;', "indicator-shape"],
        ["mode", 'if (["hold", "toggle", "always"].indexOf(message.settings.mode) === -1) fail("mode");',
            'if (false) fail("mode");', "mode"],
        ["key-type", 'fail("key-" + shortcut);', ';', "key-type"],
        ["intent-direction", 'if (direction !== "shell") fail("direction-intent");',
            'if (false) fail("direction-intent");', "intent-direction"],
        ["intent-name", 'if (["talk-down", "talk-up", "mute", "stop", "voice-check", "preview"].indexOf(message.intent) === -1) fail("intent");',
            'if (false) fail("intent");', "intent-name"],
        ["say-shape", 'keys(message, fields.concat(["text"]), "say");', 'if (false) keys(message, fields.concat(["text"]), "say");', "say-shape"],
        ["say-text", 'if (!printable(message.text, 1, TRANSCRIPT_CHARS) || message.text.trim() === "") fail("say-text");',
            'if (false) fail("say-text");', "say-empty"],
        ["audio-fault-direction", 'if (direction !== "daemon") fail("direction-audio-fault");',
            'if (false) fail("direction-audio-fault");', "audio-fault-direction"],
        ["audio-fault", 'fail("audio-fault");', ';', "audio-fault"],
        ["transcript-direction", 'if (direction !== "daemon") fail("direction-transcript");', 'if (false) fail("direction-transcript");', "transcript-direction"],
        ["transcript-role", 'fail("transcript-role");', ";", "transcript-role"],
        ["transcript-stage", 'fail("transcript-stage");', ";", "transcript-stage"],
        ["transcript-empty", "message.text.length === 0 || ", "", "transcript-empty"],
        ["transcript-long", "message.text.length > TRANSCRIPT_CHARS", "false", "transcript-long"],
        ["transcript-control", "|| /[\\x00-\\x1f\\x7f]/.test(message.text)) fail", ") fail", "transcript-control"],
        ["transcript-rev", 'fail("transcript-rev");', ";", "transcript-rev"],
        ["device-setting", 'fail("device-setting");', ';', "device-setting"],
        ["devices-direction", 'if (direction !== "daemon") fail("direction-devices");', 'if (false) fail("direction-devices");', "devices-direction"],
        ["choices", 'if (!Array.isArray(values) || values.length > 32) fail("choices");',
            'if (false) fail("choices");', "choices"],
        ["choice", 'fail("choice");', ';', "choice"],
        ["choice-duplicate", 'if (Object.prototype.hasOwnProperty.call(seen, choice.value)) fail("choice-duplicate");',
            'if (false) fail("choice-duplicate");', "choice-duplicate"],
        ["homes-direction", 'if (direction !== "daemon") fail("direction-homes");', 'if (false) fail("direction-homes");', "homes-direction"],
        ["voice-setting", 'fail("voice-setting");', ';', "voice-setting"],
        ["voices-direction", 'if (direction !== "daemon") fail("direction-voices");', 'if (false) fail("direction-voices");', "voices-direction"],
        ["voices-bound", 'message.voices.length > VOICES_MAX) fail("voices");', 'false) fail("voices");', "voices-bound"],
        ["voices-label", 'fail("voice");', ';', "voices-label"],
        ["voices-duplicate", 'if (Object.prototype.hasOwnProperty.call(voiced, voice.value)) fail("voice-duplicate");', ';', "voices-duplicate"],
        ["personality-direction", 'if (direction !== "daemon") fail("direction-personality");', ';', "personality-direction"],
        ["personality-kind", 'fail("personality-kind");', ';', "personality-kind"],
        ["personality-lines", 'shown.lines.length > PERSONALITY_LINES', 'false', "personality-lines"],
        ["personality-control", '!shown.lines.every(line => statusLine(line, PERSONALITY_CHARS))', 'false', "personality-control"],
        ["status-separators", "\\u007f-\\u009f\\u2028\\u2029]/;", "\\u007f]/;", "personality-separator"],
        ["status-c1", "\\u007f-\\u009f\\u2028\\u2029]/;", "\\u007f\\u2028\\u2029]/;", "personality-c1"],
        ["personality-empty-lines", "shown.lines.length < 1 || ", "", "personality-empty-lines"],
        ["personality-empty-line", "value.length >= 1 && value.length <= max && !STATUS_UNPRINTABLE", "value.length <= max && !STATUS_UNPRINTABLE", "personality-empty-line"],
        ["personality-more", ' || typeof shown.more !== "boolean")', ")", "personality-more"],
        ["homes-current", 'fail("home-current");', ';', "homes-current"],
        ["homes-id", 'fail("home-id");', ';', "homes-id"],
        ["homes-id-duplicate", 'if (Object.prototype.hasOwnProperty.call(seen, choice.id)) fail("home-id-duplicate");',
            'if (false) fail("home-id-duplicate");', "homes-id-duplicate"],
        ["homes-bound", 'if (!Array.isArray(values) || values.length > 10) fail("home-choices");',
            'if (false) fail("home-choices");', "homes-bound"],
        ["homes-duplicate", 'if (Object.prototype.hasOwnProperty.call(seen, choice.value)) fail("home-duplicate");',
            'if (false) fail("home-duplicate");', "homes-duplicate"],
        ["level-direction", 'if (direction !== "daemon") fail("direction-level");', 'if (false) fail("direction-level");', "level-direction"],
        ["level-bound", 'if (!Number.isFinite(message.level[channel]) || message.level[channel] < 0 || message.level[channel] > 1) fail("level");',
            'if (false) fail("level");', "level-bound"],
        ["object", 'if (!object(message)) fail("object");', 'if (false) fail("object");', "object"],
        ["version", 'if (message.v !== 1) fail("version");', 'if (false) fail("version");', "version"],
        ["generation", 'fail("generation");', ';', "generation"],
        ["direction", 'if (direction !== "shell" && direction !== "daemon") fail("direction");', 'if (false) fail("direction");', "direction"],
        ["hello-direction", 'if (direction !== "shell") fail("direction-hello");', 'if (false) fail("direction-hello");', "hello-direction"],
        ["status-direction", 'if (direction !== "daemon") fail("direction-status");', 'if (false) fail("direction-status");', "status-direction"],
        ["shape", 'fail("shape-" + name);', ';', "hello-shape"],
        ["settings-name", 'keys(message.settings, ["mode", "sounds", "microphone", "speaker", "brain", "model", "effort", "fallbacks", "taskTerminal", "cloudVision", "privateWindows", "voiceProvider", "voiceAccount", "voice", "clonedVoice", "home", "dictation"], "settings");',
            'if (false) keys(message.settings, ["mode", "sounds", "microphone", "speaker", "brain", "model", "effort", "fallbacks", "taskTerminal", "cloudVision", "privateWindows", "voiceProvider", "voiceAccount", "voice", "clonedVoice", "home", "dictation"], "settings");', "extra-setting"],
        ["brain-type", 'typeof message.settings.brain !== "string"', 'false', "brain-setting"],
        ["model-type", 'typeof message.settings.model !== "string" || ', '', "model-type"],
        ["effort-type", ' || typeof message.settings.effort !== "string"', '', "effort-type"],
        ["sounds-type", 'if (typeof message.settings.sounds !== "boolean") fail("sounds");', 'void message;', "sounds-type"],
        ["dictation-setting-type", 'if (typeof message.settings.dictation !== "string"', 'if (false', "dictation-setting-type"],
        ["dictation-setting-step", "/^(|speech=dictation-[a-z-]{1,40})$/", "/^(|[a-z]+=dictation-[a-z-]{1,40})$/", "dictation-setting-step"],
        ["directory", 'if (!directory(message.directories[name])) fail("directory-" + name);', 'if (false) fail("directory-" + name);', "directory"],
        ["lock", 'if (typeof message.locked !== "boolean") fail("lock");', 'if (false) fail("lock");', "lock"],
        ["revision", 'if (typeof message.revision !== "string" || !/^[0-9a-f]{64}$/.test(message.revision)) fail("revision");', 'if (false) fail("revision");', "revision"],
        ["daemon", 'if (message.daemon !== "ready" && message.daemon !== "locked") fail("daemon");', 'if (false) fail("daemon");', "daemon"],
        ["status-causes", 'if (!setupCauses(message.causes)) fail("causes");', 'if (false) fail("causes");', "status-causes-list"],
        ["causes-list", "if (!Array.isArray(value)) return false;", "", "status-causes-list"],
        ["causes-order", "if (step <= last) return false;", "if (step < 0) return false;", "status-causes-order"],
        ["causes-twice", "if (step <= last) return false;", "if (step < last || step < 0) return false;", "status-causes-twice"],
        ["causes-step", "if (step <= last) return false;", "if (step < last) return false;", "status-causes-step"],
        ["causes-key", "/^([a-z]+)=[a-z0-9-]{1,60}$/", "/^([a-z]+)=.{1,60}$/", "status-causes-key"],
        ["causes-home-order", 'var SETUP_STEPS = ["home", "speech", "brain"];', 'var SETUP_STEPS = ["speech", "home", "brain"];', "status-causes-home-order"],
        ["causes-home-text", 'guidance: "home", speech', 'guidance: "speech", speech', "status-causes-home-twice"],
        ["status-cautions", 'if (!setupCautions(message.cautions)) fail("cautions");', 'if (false) fail("cautions");', "status-cautions-list"],
        ["cautions-list", "if (!Array.isArray(cautions)) return false;", "", "status-cautions-list"],
        ["cautions-order", "if (at <= last) return false;", "if (at < 0) return false;", "status-cautions-order"],
        ["cautions-twice", "if (at <= last) return false;", "if (at < last || at < 0) return false;", "status-cautions-twice"],
        ["cautions-known", "if (at <= last) return false;", "if (at < last) return false;", "status-cautions-cause"],
        ["home-type", 'typeof message.settings.home !== "string"', "false", "home-type"],
        ["home-control", "/^[^\\x00-\\x1f\\x7f]{0,4096}$/", "/^[^]{0,4096}$/", "home-control"],
        ["home-size", "/^[^\\x00-\\x1f\\x7f]{0,4096}$/", "/^[^\\x00-\\x1f\\x7f]*$/", "home-size"],
        ["type", 'fail("type");', 'break;', "type"],
        ["state-direction", 'if (direction !== "daemon") fail("direction-state");', 'if (false) fail("direction-state");', "state-direction"],
        ["state-seq", 'if (!Number.isSafeInteger(message.seq) || message.seq < 1) fail("sequence");', 'if (false) fail("sequence");', "state-seq"],
        ["state-regions", 'if (!Session.validate(message.state)) fail("state");', 'if (false) fail("state");', "state-regions"],
        ["state-gen", 'if (message.state.gen !== message.gen) fail("state-generation");', 'if (false) fail("state-generation");', "state-gen"],
        ["state-phase", 'if (message.phase !== Session.phaseOf(message.state)) fail("phase");', 'if (false) fail("phase");', "state-phase"],
        ["request-direction", 'if (direction !== "daemon") fail("direction-request");', 'if (false) fail("direction-request");', "request-direction"],
        ["reply-direction", 'if (direction !== "shell") fail("direction-reply");', 'if (false) fail("direction-reply");', "reply-direction"],
        ["request-id", 'if (!Number.isSafeInteger(message.id) || message.id < 1) fail("request-id");', 'if (false) fail("request-id");', "request-id", 2],
        ["input-ready-direction", 'if (direction !== "daemon") fail("direction-input-ready");', 'if (false) fail("direction-input-ready");', "input-ready-direction"],
        ["input-ready-command", 'fail("input-commands");', ' ;', "input-ready-command"],
        ["request-kind", 'fail("request-kind");', ';', "request-kind", 2],
        ["request-args", 'if (!requestArgs(message.kind, message.args)) fail("request-args");', 'if (false) fail("request-args");', "request-count"],
        ["request-arg-type", 'if (rule[i] === "text" ? !text(args[i]) : !Number.isSafeInteger(args[i])) return false;', ';', "request-integer"],
        ["request-text", 'value.length <= TEXT_MAX && value.indexOf("\\u0000") === -1', 'true', "request-text-size"],
        ["request-argv", 'value.length >= 1 && value.length <= ARGV_MAX && value.every(text)', 'true', "request-argv-size"],
        ["reply-answer", 'if (!printable(message.answer, 1, ANSWER_MAX)) fail("reply-answer");', 'if (false) fail("reply-answer");', "reply-answer-line"],
        ["reply-data", 'if (message.data !== null) fail("reply-data");', ';', "reply-data-refused"],
        ["entries-bound", 'message.data.entries.length > ENTRIES_MAX', 'false', "reply-entries-size"],
        ["entry-fields", 'if (!printable(value.id, 1, FIELD_MAX) || !printable(value.name, 0, FIELD_MAX)', 'if (false', "reply-entry-name"],
        ["entry-terminal", 'if (withTerminal && typeof value.terminal !== "boolean") fail("entry");', ';', "reply-entry-terminal"],
        ["entry-duplicate", 'if (Object.prototype.hasOwnProperty.call(seen, entry.id)) fail("entry-duplicate");', ';', "reply-entry-duplicate"],
        ["task-terminal", 'if (TASK_TERMINALS.indexOf(message.settings.taskTerminal) === -1) fail("task-terminal");',
            'if (false) fail("task-terminal");', "task-terminal"],
        ["cloud-vision", 'if (CLOUD_VISION.indexOf(message.settings.cloudVision) === -1) fail("cloud-vision");',
            'if (false) fail("cloud-vision");', "cloud-vision"],
        ["cloned-voice", 'if (typeof message.settings.clonedVoice !== "boolean") fail("cloned-voice");',
            'if (false) fail("cloned-voice");', "cloned-voice-type"],
        ["voice-provider", '!["local", "realtime", "gemini", "elevenlabs"].includes(message.settings.voiceProvider)', "false", "voice-provider"],
        ["live-account-type", 'typeof message.settings.voiceAccount !== "string"', "false", "live-account-type"],
        ["live-account-control", "/^[^\\x00-\\x1f\\x7f]{0,200}$/", "/^[^]{0,200}$/", "live-account-control", 2],
        ["live-account-size", "/^[^\\x00-\\x1f\\x7f]{0,200}$/", "/^[^\\x00-\\x1f\\x7f]*$/", "live-account-size", 2],
        ["private-windows-type", 'if (typeof message.settings.privateWindows !== "string"\n                || ', 'if (', "private-windows-type"],
        ["private-windows-control", "/^[^\\x00-\\x1f\\x7f]{0,1024}$/", "/^[^]{0,1024}$/", "private-windows-control"],
        ["private-windows-size", "/^[^\\x00-\\x1f\\x7f]{0,1024}$/", "/^[^\\x00-\\x1f\\x7f]*$/", "private-windows-size"],
        ["task-stop-id", 'if (!taskId(message.task)) fail("task-id");', 'if (false) fail("task-id");', "task-stop-id"],
        ["task-id-rule", "/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/.test(value)", "true", "task-stop-id"],
        ["tui-state-direction", 'if (direction !== "shell") fail("direction-tui-state");', 'if (false) fail("direction-tui-state");', "tui-state-direction"],
        ["tui-state-name", 'if (message.name !== "task") fail("tui-name");', 'if (false) fail("tui-name");', "tui-state-name"],
        ["tui-state-running", 'if (typeof message.running !== "boolean") fail("tui-running");', 'if (false) fail("tui-running");', "tui-state-running"],
        ["task-request-count", 'args.length === 1 && directory(args[0])', 'directory(args[0])', "task-request-args"],
        ["task-request-spec", 'args.length === 1 && directory(args[0])', 'args.length === 1', "task-request-spec"],
        ["tasks-direction", 'if (direction !== "daemon") fail("direction-tasks");', 'if (false) fail("direction-tasks");', "tasks-direction"],
        ["task-count", 'if (!Number.isSafeInteger(message.count) || message.count < 0) fail("task-count");', 'if (false) fail("task-count");', "task-count"],
        ["task-answer-direction", 'if (direction !== "daemon") fail("direction-task-answer");', 'if (false) fail("direction-task-answer");', "task-answer-direction"],
        ["task-answer-task", 'if (!taskId(message.task)) fail("answer-task-id");', 'if (false) fail("answer-task-id");', "task-answer-task"],
        ["task-answer-value", 'fail("task-answer");', ';', "task-answer-value"],
        ["dictation-text-max", "message.data.text.length > TEXT_MAX", "message.data.text.length > TEXT_MAX + 1", "dictation-text-long"],
        ["dictation-text-shape", 'keys(message.data, ["text"], "dictation-text");', "", "dictation-text-extra"],
        ["dictation-text-nul", 'message.data.text.indexOf("\\u0000") !== -1) fail("dictation-text");', 'false) fail("dictation-text");', "dictation-text-nul"],
        ["start-text-direction", 'if (direction !== "daemon") fail("direction-start-text");', "", "start-text-direction"],
        ["start-text-shape", 'keys(message, ["v", "type", "gen", "revision", "size"], "start-text");', "", "start-text-shape"],
        ["start-text-size-shape", 'keys(size, ["kind", "tokens", "layers"], "start-text");', "", "start-text-size-shape"],
        ["start-text-kind", 'if (size.kind !== "unreadable") fail("start-text-kind");', "", "start-text-kind"],
        ["start-text-total", "size.tokens < 0 || ", "", "start-text-total"],
        ["start-text-layer-order", "if (at <= last || ", "if (at < last || ", "start-text-layer-twice"],
        ["start-text-layer-name", "if (at <= last || ", "if (", "start-text-layer-name"],
        ["start-text-layer-tokens", " || layers[i].tokens < 0) return false;", ") return false;", "start-text-layer-tokens"],
        ["start-text-layer-shape", '|| Object.keys(layers[i]).sort().join(",") !== "layer,tokens"', "", "start-text-layer-shape"]
    ];
    for (const [name, needle, replacement, example, matches] of guards)
        control(name, needle, replacement, logic => rejected(logic, cases.find(row => row[0] === example)), matches);
    control("voice-provider-gemini", '["local", "realtime", "gemini", "elevenlabs"]', '["local", "realtime", "elevenlabs"]', voiceProviders);
    control("voice-provider-elevenlabs", '["local", "realtime", "gemini", "elevenlabs"]', '["local", "realtime", "gemini"]', voiceProviders);
    control("memory-inbox-filter-bound", "size + next > MEMORY_INBOX_BYTES", "false", logic =>
        assert.equal(logic.memoryInboxEntries(Array(9).fill({ ...memoryEntry, text: "x".repeat(16 * 1024) })).length, 7));
    control("memory-inbox-filter-invalid", "if (!memoryEntryAccepted(entry)) continue;", "", logic =>
        assert.equal(logic.memoryInboxEntries([{ ...memoryEntry, problem: "other" }, memoryEntry]).length, 1));
    control("unsupported-echo", 'keys(message.settings, ["mode", "sounds", "microphone", "speaker", "brain", "model", "effort", "fallbacks", "taskTerminal", "cloudVision", "privateWindows", "voiceProvider", "voiceAccount", "voice", "clonedVoice", "home", "dictation"], "settings");',
        'if (false) keys(message.settings, ["mode", "sounds", "microphone", "speaker", "brain", "model", "effort", "fallbacks", "taskTerminal", "cloudVision", "privateWindows", "voiceProvider", "voiceAccount", "voice", "clonedVoice", "home", "dictation"], "settings");',
        logic => {
            for (const row of cases.filter(row => row[0].startsWith("echo-setting-"))) rejected(logic, row);
        });
    for (const kind of ["compositor.reveal", "run.detached", "desktop.launch", "tui.run"]) {
        const line = source.split("\n").find(row => row.includes('"' + kind + '": {'));
        control("locked-" + kind, line, line.replace("acts: true", "acts: false"), lockedRows);
    }
    control("locked-observed", 'return locked !== false && REQUESTS[kind].acts ? "refused: locked" : "";',
        'return REQUESTS[kind].acts && false ? "refused: locked" : "";', lockedRows);
    control("unlocked-allowed", 'return locked !== false && REQUESTS[kind].acts ? "refused: locked" : "";',
        'return REQUESTS[kind].acts ? "refused: locked" : "";', lockedRows);
    control("entries-hidden", 'entry.noDisplay === true) return null;', 'false) return null;',
        logic => assert.equal(logic.desktopEntries([shellEntry("hidden", { noDisplay: true })]).entries.length, 0));
    control("entries-bytes", 'if (size > ENTRIES_BYTES) break;', ';',
        logic => assert.equal(logic.desktopEntries(Array.from({ length: 512 }, (_, n) => shellEntry(String(n).padStart(3, "0") + "é".repeat(120),
            { name: "語".repeat(128), startupClass: "語".repeat(128) }))).complete, false));
    control("answer-line", 'var line = String(value).replace(/[\\x00-\\x1f\\x7f]/g, " ").slice(0, ANSWER_MAX);', 'var line = String(value);',
        logic => assert.equal(logic.answer("refused: a\nb"), "refused: a b"));
    control("ceiling", 'if (bytes(line) > MAX_LINE_BYTES) fail("line-too-long");', 'if (false) fail("line-too-long");',
        logic => assert.throws(() => logic.feed("", "a".repeat(262145)), { message: "jarvis: protocol=line-too-long" }));
    control("utf8", "count += 4;", "count += 1;",
        logic => assert.equal(logic.bytes("😀"), 4));
    control("framing", 'var parts = (tail + chunk).split("\\n");', 'var parts = chunk.split("\\n");',
        logic => assert.equal(logic.feed("one", "\n").lines[0], "one"));
} finally { fs.rmSync(root, { recursive: true, force: true }); }
console.log("test-jarvis-protocol: ok cases=" + cases.length + " controls=" + controls);
