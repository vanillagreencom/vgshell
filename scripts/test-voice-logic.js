#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const repo = path.join(__dirname, "..");
const file = path.join(repo, "shell", "plugins", "vgs.voice", "VoiceLogic.js");
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message);

const readsReady = {
  engine: '{"value":"parakeet"}',
  model: '{"value":"parakeet-tdt-0.6b-v3"}',
  models: '{"models":[{"name":"parakeet-tdt-0.6b-v3","installed":true,"size":"600 MB"}]}',
  engines: '{"engines":[{"name":"parakeet","available":true}]}',
  unit: 'enabled\n'
};
const readsMissing = {
  engine: '{"value":"parakeet"}',
  model: '{"value":"parakeet-tdt-0.6b-v3"}',
  models: '{"models":[{"name":"parakeet-tdt-0.6b-v3","installed":false,"size":"600 MB"}]}',
  engines: '{"engines":[{"name":"parakeet","available":false}]}',
  unit: 'disabled\n'
};

function verify(logic) {
  same(logic.parseStatus('{"alt":"recording","engine":"parakeet","model":"voice-model"}'),
    { ok: true, state: "recording", rawState: "recording", unknown: false, engine: "parakeet", model: "voice-model" },
    "recording status parses");
  same(logic.parseStatus('{'), { ok: false, reason: "json" }, "malformed status is refused");
  same(logic.parseStatus('{"state":"paused"}'),
    { ok: true, state: "idle", rawState: "paused", unknown: true, engine: "", model: "" },
    "unknown status falls back to idle and reports the raw state");

  same(logic.setupState(readsReady),
    { tone: "ok", text: "Ready", action: false, engine: "parakeet", model: "parakeet-tdt-0.6b-v3", reasons: [] },
    "ready setup state");
  same(logic.setupState(readsMissing),
    { tone: "warning", text: "Set up needed", lines: [
      "The active build cannot use parakeet.",
      "The speech model is missing.",
      "The service is not enabled."
    ], action: true, engine: "parakeet", model: "parakeet-tdt-0.6b-v3", reasons: [
      "The active build cannot use parakeet.",
      "The speech model is missing.",
      "The service is not enabled."
    ] },
    "missing setup state lists every setup reason");
  assert.equal(logic.modelInstalled(readsReady.models, "parakeet-tdt-0.6b-v3"), true, "installed model is found");
  assert.equal(logic.modelInstalled(readsMissing.models, "parakeet-tdt-0.6b-v3"), false, "missing model is detected");
  assert.equal(logic.engineAvailable(readsReady.engines, "parakeet"), true, "engine is found");
  assert.equal(logic.engineAvailable(readsMissing.engines, "parakeet"), false, "unavailable engine is detected");
  assert.equal(logic.unitEnabled("enabled\n"), true, "enabled unit is accepted");
  assert.equal(logic.unitEnabled("disabled\n"), false, "disabled unit is detected");
  same(logic.modelData({ engine: "", model: "" }, logic.setupState(readsReady)),
    { engine: "parakeet", model: "parakeet-tdt-0.6b-v3" }, "model data falls back to setup");
}

verify(load(file));

const controls = [
  ["malformed lines accepted", "if (!isObject(data)) return { ok: false, reason: \"json\" };", "if (false) return { ok: false, reason: \"json\" };"] ,
  ["unknown state kept", "var state = STATES.indexOf(raw) === -1 ? \"idle\" : raw;", "var state = raw;"],
  ["model presence ignored", "if (name === wanted && affirmative(row, [\"installed\", \"downloaded\", \"present\", \"ready\", \"status\"])) return true;", "if (name === wanted) return true;"],
  ["engine availability ignored", "if (name === wanted && row.available !== false && row.enabled !== false && row.present !== false) return true;", "if (name === wanted) return true;"],
  ["unit disabled accepted", "return value === \"enabled\" || value === \"static\";", "return true;"],
  ["setup never offers action", "return { tone: \"warning\", text: \"Set up needed\", lines: lines, action: true, engine: engine, model: model, reasons: lines };", "return { tone: \"warning\", text: \"Set up needed\", lines: lines, action: false, engine: engine, model: model, reasons: lines };"]
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
