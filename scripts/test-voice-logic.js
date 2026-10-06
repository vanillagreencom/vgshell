#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const repo = path.join(__dirname, "..");
const file = path.join(repo, "shell", "plugins", "vgs.voice", "VoiceLogic.js");
// Keys spelled as the shell's KeyCaps spells them, the helper the service
// passes.
const keyNav = load(path.join(repo, "shell", "Ui", "foundation", "KeyNavLogic.js"));
const spell = key => keyNav.keyCaps(key).join("+");
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message);

const modelsReady = '{"engines":{"parakeet":{"models":[{"name":"parakeet-tdt-0.6b-v3","installed":true,"downloadable":true,"download_arg":"parakeet-tdt-0.6b-v3"}],"default":"parakeet-tdt-0.6b-v3"}},"verified":true}';
const modelsMissing = '{"engines":{"parakeet":{"models":[{"name":"parakeet-tdt-0.6b-v3","installed":false,"downloadable":true,"download_arg":"parakeet-tdt-0.6b-v3"}],"default":"parakeet-tdt-0.6b-v3"}},"verified":true}';
const enginesReady = '[{"name":"whisper","compiled":true,"active":false},{"name":"parakeet","compiled":true,"active":true}]';
const enginesMissing = '[{"name":"whisper","compiled":true,"active":true},{"name":"parakeet","compiled":false,"active":false}]';
const readsReady = { engine: '{"value":"parakeet"}', model: '{"value":"parakeet-tdt-0.6b-v3"}', models: modelsReady, engines: enginesReady, unit: 'enabled\n' };
const readsMissing = { engine: '{"value":"parakeet"}', model: '{"value":"parakeet-tdt-0.6b-v3"}', models: modelsMissing, engines: enginesMissing, unit: 'disabled\n' };

function verify(logic) {
  same(logic.parseStatus('{"state":"recording","backend":"ONNX CPU","model":"parakeet-tdt-0.6b-v3","device":"default"}'),
    { ok: true, state: "recording", rawState: "recording", unknown: false, backend: "ONNX CPU", device: "default", model: "parakeet-tdt-0.6b-v3" }, "recording status parses");
  same(logic.parseStatus('{'), { ok: false, reason: "json" }, "malformed status is refused");
  same(logic.parseStatus('{"state":"paused"}'),
    { ok: true, state: "idle", rawState: "paused", unknown: true, backend: "", device: "", model: "" }, "unknown status falls back to idle and reports the raw state");
  same(logic.parseStatus('{"state":"streaming"}').state, "recording", "streaming shows as recording");
  same(logic.parseStatus('{"state":"stopped"}').state, "stopped", "stopped is distinct");

  same(logic.setupState(readsReady), { tone: "ok", text: "Ready", action: false, engine: "parakeet", model: "parakeet-tdt-0.6b-v3", reasons: [] }, "ready setup state");
  same(logic.setupState(readsMissing), { tone: "warning", text: "Set up needed", lines: [
    "The active build cannot use parakeet.", "The speech model is missing.", "The service is not enabled."
  ], action: true, engine: "parakeet", model: "parakeet-tdt-0.6b-v3", reasons: [
    "The active build cannot use parakeet.", "The speech model is missing.", "The service is not enabled."
  ] }, "missing setup state lists every setup reason");
  assert.equal(logic.modelInstalled(modelsReady, "parakeet", "parakeet-tdt-0.6b-v3"), true, "installed model is found");
  assert.equal(logic.modelInstalled(modelsMissing, "parakeet", "parakeet-tdt-0.6b-v3"), false, "missing model is detected");
  assert.equal(logic.engineAvailable(enginesReady, "parakeet"), true, "compiled engine is found");
  assert.equal(logic.engineAvailable(enginesMissing, "parakeet"), false, "uncompiled engine is detected");
  assert.equal(logic.unitEnabled("enabled\n"), true, "enabled unit is accepted");
  assert.equal(logic.unitEnabled("disabled\n"), false, "disabled unit is detected");
  same(logic.modelData({ model: "old" }, logic.setupState(readsReady)), { engine: "parakeet", model: "parakeet-tdt-0.6b-v3" }, "fresh probe wins for model row");

  // Lines in the shape voxtype-audio-bridge prints (voxtype-shared README, AudioBridge).
  same(logic.parseFrame('{"peak":0.421,"rms":0.18,"vad":1,"ts_ms":1234567}'), { ok: true, kind: "frame", peak: 0.421, rms: 0.18 }, "a bridge frame parses");
  same(logic.parseFrame('{"status":"connected"}'), { ok: true, kind: "connected" }, "the connected line parses");
  same(logic.parseFrame('{"status":"disconnected"}'), { ok: true, kind: "disconnected" }, "the disconnected line parses");
  same(logic.parseFrame("bridge: starting"), { ok: false, reason: "json" }, "a log line is refused");
  same(logic.parseFrame('{"peak":"0.4","rms":0.1}'), { ok: false, reason: "frame" }, "a text peak is refused");
  same(logic.parseFrame('{"peak":0.4}'), { ok: false, reason: "frame" }, "a frame without rms is refused");
  same(logic.parseFrame('{"peak":-0.1,"rms":0.1}'), { ok: false, reason: "frame" }, "a negative peak is refused");
  assert.equal(logic.frameLevel(0, 0), 0, "silence draws no level");
  assert.equal(logic.frameLevel(0.5, 0), 1, "a loud peak reaches the full level");
  assert.ok(Math.abs(logic.frameLevel(0.01, 0) - Math.pow(0.06, 0.62)) < 1e-12, "a quiet peak is lifted by the gamma");
  assert.ok(Math.abs(logic.frameLevel(0.01, 0.02) - Math.pow(0.02 * 1.7 * 6, 0.62)) < 1e-12, "a louder weighted RMS sets the level");

  // readyKey: [name, shell.shortcut.keys, { kind, key }].
  const readyRows = [
    ["the hold key comes first", { toggle: "SUPER+CTRL+X", tap: null, talk: "F9" }, { kind: "hold", key: "F9" }],
    ["the toggle key without a hold key", { toggle: "SUPER+CTRL+X", tap: "SUPER+ALT+V", talk: null }, { kind: "toggle", key: "SUPER+CTRL+X" }],
    ["the tap key alone", { toggle: null, tap: "SUPER+ALT+V", talk: null }, { kind: "tap", key: "SUPER+ALT+V" }],
    ["no key bound", { toggle: null, tap: null, talk: null }, { kind: "none", key: null }],
    ["no key declared", {}, { kind: "none", key: null }],
  ];
  for (const [name, keys, want] of readyRows) same(logic.readyKey(keys), want, `readyKey: ${name}`);
  assert.ok(logic.readyMessage({ toggle: "SUPER+CTRL+X", talk: null }, spell).includes("Super+Ctrl+X"), "the message spells the bound key for people");
  assert.ok(!logic.readyMessage({ toggle: null, tap: null, talk: null }, spell).includes("null"), "the message names no key when none is bound");

  // setupFinished: [name, the endedAt seen last, the setup state, want].
  const ended = (endedAt, code) => ({ running: false, code: code, endedAt: endedAt });
  const finishedRows = [
    ["a run ended before the first read shows nothing", undefined, ended("t1", 0), false],
    ["the first run ending with code 0 shows", null, ended("t1", 0), true],
    ["a new run ending with code 0 shows", "t1", ended("t2", 0), true],
    ["the end already seen shows nothing again", "t2", ended("t2", 0), false],
    ["a failed run shows nothing", "t1", ended("t2", 1), false],
    ["a run that never ended shows nothing", null, { running: true, code: null, endedAt: null }, false],
  ];
  for (const [name, seen, setup, want] of finishedRows) assert.equal(logic.setupFinished(seen, setup), want, `setupFinished: ${name}`);
}

verify(load(file));

const controls = [
  ["malformed lines accepted", "if (!isObject(data)) return { ok: false, reason: \"json\" };", "if (false) return { ok: false, reason: \"json\" };"],
  ["unknown state kept", "return STATES.indexOf(raw) === -1 ? \"idle\" : raw;", "return raw;"],
  ["model presence ignored", "row.name === wanted && row.installed === true", "row.name === wanted"],
  ["engine compiled ignored", "return row.compiled === true;", "return true;"],
  ["unit disabled accepted", "return value === \"enabled\" || value === \"static\";", "return true;"],
  ["setup never offers action", "return { tone: \"warning\", text: \"Set up needed\", lines: lines, action: true, engine: engine, model: model, reasons: lines };", "return { tone: \"warning\", text: \"Set up needed\", lines: lines, action: false, engine: engine, model: model, reasons: lines };"],
  ["streaming not mapped", "if (raw === \"streaming\") return \"recording\";", "if (false) return \"recording\";"],
  ["bridge frame shape ignored", "if (!amplitude(frame.peak) || !amplitude(frame.rms)) return { ok: false, reason: \"frame\" };", ""],
  ["bridge status lines read as frames", "if (frame.status === \"connected\" || frame.status === \"disconnected\") return { ok: true, kind: frame.status };", ""],
  ["level not lifted", "Math.pow(Math.max(peak, rms * RMS_WEIGHT) * LEVEL_GAIN, LEVEL_GAMMA)", "Math.max(peak, rms * RMS_WEIGHT) * LEVEL_GAIN"],
  ["level ignores rms", "Math.max(peak, rms * RMS_WEIGHT)", "peak"],
  ["the toggle key wins over the hold key", "if (typeof keys.talk === \"string\") return { kind: \"hold\", key: keys.talk };\n", ""],
  ["a past run's end at startup shows", "return seen !== undefined && ", "return "],
  ["a failed run shows", " && setup.code === 0;", ";"],
  ["a seen end shows again", " && setup.endedAt !== seen", ""],
  ["stream model wins", "var model = setup && setup.model ? setup.model : status && status.model ? status.model : DEFAULT_MODEL;", "var model = status && status.model ? status.model : setup && setup.model ? setup.model : DEFAULT_MODEL;"]
];
const source = fs.readFileSync(file, "utf8");
const scratchRoot = path.join(repo, "tmp");
fs.mkdirSync(scratchRoot, { recursive: true });
const temp = fs.mkdtempSync(path.join(scratchRoot, "voice-logic-control-"));
try {
  for (const [label, needle, replacement] of controls) {
    assert.equal(source.split(needle).length, 2, `control ${label}: replacement text occurs once`);
    const mutant = path.join(temp, "VoiceLogic.js");
    fs.writeFileSync(mutant, source.replace(needle, replacement));
    let failed = false;
    try { verify(load(mutant)); } catch (e) { failed = true; }
    assert.ok(failed, `control ${label}: suite passed without the rule`);
  }
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
// The requirement logic over the shipped manifest: every Voice screen runs
// voxtype and restarts its service through systemctl, so a press without
// either raises the requirement notice in place of the script, which then
// opens the screen once both are found.
const pluginLogic = load(path.join(repo, "shell", "Core", "PluginLogic.js"));
const manifestFile = path.join(repo, "shell", "plugins", "vgs.voice", "manifest.json");
function verifyRequirements(raw) {
  const judged = pluginLogic.validateManifest(raw, path.dirname(manifestFile));
  assert.ok(judged.ok, `the Voice manifest is accepted: ${judged.error}`);
  const missing = ["voxtype", "voxtype-audio-bridge"];
  const runner = { launcher: "present", busy: [], run: "r1" };
  for (const name of ["setup", "configure", "model"]) {
    same(pluginLogic.tuiMissingRequirements(judged.manifest, name, missing), ["voxtype"], `${name} without voxtype asks for it before its script`);
    same(pluginLogic.tuiMissingRequirements(judged.manifest, name, ["systemctl"]), ["systemctl"], `${name} without systemctl asks for it before its script`);
    same(pluginLogic.tuiMissingRequirements(judged.manifest, name, []), [], `${name} with voxtype present runs its script`);
    same(pluginLogic.tuiRunFor(judged.manifest, true, "/src", runner, name, missing).kind, "install", `the ${name} press raises the requirement notice`);
  }
}
const shipped = JSON.parse(fs.readFileSync(manifestFile, "utf8"));
verifyRequirements(shipped);
for (const name of ["setup", "configure", "model"]) {
  const unrequired = JSON.parse(JSON.stringify(shipped));
  assert.deepEqual(unrequired.tui[name].requires, ["voxtype", "systemctl"], `control unrequired ${name}: the shipped screen requires voxtype and systemctl`);
  delete unrequired.tui[name].requires;
  assert.throws(() => verifyRequirements(unrequired), `control unrequired ${name}: a manifest copy whose ${name} does not require voxtype passed`);
}

console.log(`test-voice-logic: ok controls=${controls.length + 3}`);
