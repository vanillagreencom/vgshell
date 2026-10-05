#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const repo = path.join(__dirname, "..");
const file = path.join(repo, "shell", "plugins", "vgs.voice", "VoiceLogic.js");
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
console.log(`test-voice-logic: ok controls=${controls.length}`);
