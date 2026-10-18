#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { load } = require("../bin/lib/qml-library.js");

const repo = path.join(__dirname, "..");
const file = path.join(repo, "shell", "plugins", "vgs.voice", "VoiceLogic.js");
const serviceSource = fs.readFileSync(path.join(path.dirname(file), "Service.qml"), "utf8");
const dictationSource = fs.readFileSync(path.join(repo, "shell", "Core", "Dictation.qml"), "utf8");
const dictationModelFile = path.join(repo, "shell", "Core", "DictationModel.js");
const widgetSource = fs.readFileSync(path.join(path.dirname(file), "Widget.qml"), "utf8");
const pluginLogic = load(path.join(repo, "shell", "Core", "PluginLogic.js"));
const pageReference = load(path.join(repo, "shell", "Commons", "PageReference.js"));
const steps = load(path.join(repo, "shell", "plugins", "vgs.settings", "Steps.js"));
const voiceJudged = pluginLogic.validateManifest(JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8")), path.dirname(file));
assert.ok(voiceJudged.ok, `the Voice manifest is accepted: ${voiceJudged.error}`);
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message);

// Typed setup readings published by the core, after its single probe chain.
const readsReady = { engine: "parakeet", model: "parakeet-tdt-0.6b-v3", version: "voxtype 1.1.0\n", compiled: true, installed: true };
const readsMissing = Object.assign({}, readsReady, { compiled: false, installed: false });
// The `dictation` capability's state (DictationModel.state).
const lent = (daemon, phase, holder) => ({ daemon: daemon, phase: phase, holder: holder, engine: "", model: "", device: "" });

// The shared Voice handlers run against the real DictationModel. Only
// process output and deferred scheduling are fixtures; no program starts.
function verifyRecovery(logic, source, model = load(dictationModelFile), ownerSource = dictationSource) {
  const names = ["start", "stop", "toggle", "applyDictation", "publishDictation", "refreshSetup", "publishSetup"];
  const functions = names.map(name => {
    const found = source.match(new RegExp("^    function " + name + "\\([^)]*\\) \\{\\n[\\s\\S]*?^    \\}", "m"));
    assert.ok(found, "the service declares " + name);
    return found[0];
  }).join("\n");
  const ownerRun = ownerSource.match(/^    function run\(effect\) \{\n[\s\S]*?^    \}/m);
  assert.ok(ownerRun, "the owner declares its effect runner");
  for (const ending of ["idle", "transcribing", "recording", "failed", "stopped", "", "other-holder", "normal-result", "late-before-next", "late-after-next"]) {
    const pages = [], effects = [], deliveries = [], deferred = [];
    const owner = { model: Object.assign(model.initial("/fixture/dictation", "/fixture/state"), {
      holders: ["vgs.voice", "acme.dictation"], daemon: "ready", child: "running", maxSecs: 210, setup: readsReady
    }), waiting: null, Qt: { callLater: fn => deferred.push(fn) } };
    owner.root = owner;
    vm.runInNewContext(ownerRun[0], owner);
    const world = { VoiceLogic: logic, voxtypePresent: true, ownDictation: false, dictation: "idle", recoveryRequested: false,
      setupValue: logic.setupState(readsReady, "ready"), publish: () => {}, publishModel: () => {},
      console: { warn: () => {}, error: value => assert.fail(value) }, shell: {
        dictation: { start: mode => event("start", "vgs.voice", mode).answer, stop: () => event("stop", "vgs.voice").answer },
        surfaces: { openPage: (page, tab) => pages.push([page, tab]) }
      } };
    Object.defineProperty(world, "dictationState", { get: () => model.state(owner.model) });
    Object.defineProperty(world, "daemon", { get: () => world.dictationState.daemon });
    world.root = world;
    vm.runInNewContext(functions, world);
    function event(name, ...args) {
      const step = model[name](owner.model, ...args);
      owner.model = step.model;
      effects.push(...step.effects);
      for (const effect of step.effects) if (["done", "forget"].includes(effect.kind)) owner.run(effect);
      world.applyDictation();
      return step;
    }
    const status = alt => event("status", JSON.stringify({ alt }));
    assert.equal(world.toggle(), "ok", ending + ": idle toggle starts");
    event("ran", "start", 0, "");
    status("recording");
    assert.equal(world.dictation, "recording", ending + ": own recording shows");
    assert.equal(world.toggle(), "ok", ending + ": recording toggle stops");
    if (ending.indexOf("late-") === 0 || ending === "normal-result") owner.waiting = result => deliveries.push(result);
    event("ran", "stop", 0, "");
    event("ran", "state", 0, JSON.stringify({ alt: "transcribing" }));
    assert.equal(world.dictation, "transcribing", ending + ": normal stop keeps the display");
    if (ending === "normal-result") {
      status("idle");
      assert.equal(event("start", "acme.dictation", "text").answer, "ok");
      deferred.splice(0).forEach(fn => fn());
      same(deliveries, [{ kind: "typed" }], "normal stop completion still reaches its callback after another holder starts");
      continue;
    }
    effects.length = 0;
    if (ending === "other-holder") {
      status("idle");
      assert.equal(event("start", "acme.dictation", "text").answer, "ok");
      event("ran", "start", 0, "");
      status("recording");
      effects.length = 0;
      assert.equal(world.toggle(), "refused: dictation=busy holder=acme.dictation");
      same(effects, [], "another holder is untouched by Voice recovery");
      assert.equal(world.dictationState.holder, "acme.dictation");
      assert.equal(world.dictation, "idle", "another holder has no Voice display");
      continue;
    }
    assert.equal(world.toggle(), "refused: dictation=engine-busy state=transcribing");
    assert.ok(effects.some(e => e.kind === "run" && e.tag === "state"), ending + ": refused toggle reads fresh engine state");
    assert.equal(effects.some(e => e.tag === "start" || e.tag === "cancel"), false, ending + ": recovery press records and cancels nothing");
    event("ran", "state", ending === "failed" ? 1 : 0, JSON.stringify({ alt: ending.indexOf("late-") === 0 ? "idle" : ending }));
    if (ending === "idle" || ending.indexOf("late-") === 0) {
      assert.equal(world.dictation, "idle", ending + ": stale display hides");
      assert.equal(world.ownDictation, false);
      assert.equal(world.dictationState.holder, "", ending + ": recovery retains no recording intent");
      if (ending === "late-before-next") {
        deferred.splice(0).forEach(fn => fn());
        same(deliveries, [], "recovery discards a deferred cancelled result");
      }
      assert.equal(world.toggle(), "ok", ending + ": next press starts");
      event("ran", "start", 0, "");
      status("recording");
      assert.equal(world.dictation, "recording");
      deferred.splice(0).forEach(fn => fn());
      same(deliveries, [], "old delivery cannot reach a new recording");
    } else if (["failed", "stopped", ""].includes(ending)) {
      assert.equal(world.dictation, "idle", "failure hides stale display");
      same(pages, [["vgs.voice", "Setup"]], "failed recovery opens its actionable correction");
      assert.equal(world.setupValue.action, "setup");
    } else {
      assert.equal(world.dictationState.holder, "", ending + ": progressing engine starts no recording");
      assert.equal(world.dictationState.phase, ending);
      assert.equal(world.dictation, ending === "transcribing" ? "transcribing" : "idle");
      same(pages, [], ending + ": progress opens no correction");
    }
  }
}

// Execute the shipped handlers and publishers. Only capability effects
// are replaced, so every user entry must reach the shared correction.
function verifyStartCorrection(source, manifest) {
  const logic = load(file);
  const functions = ["start", "stop", "toggle", "refreshSetup", "publishSetup"].map(name => {
    const found = source.match(new RegExp("^    function " + name + "\\(\\) \\{\\n[\\s\\S]*?^    \\}", "m"));
    assert.ok(found, "the service declares " + name);
    return found[0];
  }).join("\n");
  const registration = source.match(/    onShellChanged: \{\n([\s\S]*?)^    \}/m);
  const widgetToggle = widgetSource.match(/^    function toggle\(\) \{\n[\s\S]*?^    \}/m);
  assert.ok(registration && widgetToggle, "the service and widget entry points exist");
  assert.ok(manifest.capabilities.includes("surfaces"), "the service receives the page route");
  for (const [label, daemon, reads, answer, tab, action, tone = "warning"] of [
    ["failed daemon", "failed", readsReady, "refused: dictation=daemon-failed", "Setup", "setup"],
    ["failed setup read", "failed", null, "refused: dictation=daemon-failed", "Setup", "setup"],
    ["missing model", "absent", readsMissing, "refused: dictation=daemon-absent", "Setup", "setup"],
    ["absent daemon", "absent", readsReady, "refused: dictation=daemon-absent", "Setup", "setup"],
    ["foreign daemon", "elsewhere", readsReady, "refused: dictation=daemon-elsewhere", "Details", "stop"],
    ["foreign daemon before setup", "elsewhere", readsMissing, "refused: dictation=daemon-elsewhere", "Details", "stop"],
    ["ready daemon", "ready", readsReady, "ok", "", ""],
    ["another holder", "ready", readsReady, "refused: dictation=busy holder=acme.dictation", "", ""],
    ["transcribing", "ready", readsReady, "refused: dictation=engine-busy state=transcribing", "", ""],
    ["starting daemon", "starting", null, "refused: dictation=daemon-starting", "Setup", "", "info"],
    ["starting daemon after setup read", "starting", readsReady, "refused: dictation=daemon-starting", "Setup", "", "info"]
  ]) {
    const pages = [], starts = [], stops = [], warnings = [], handlers = {}, values = {};
    const world = { VoiceLogic: logic, registeredWith: null, voxtypePresent: true,
      daemon, dictationState: Object.assign(lent(daemon, "idle", label === "another holder" ? "acme.dictation" : ""), { setup: reads }),
      setupValue: logic.setupState(readsReady, "ready"),
      Qt: { callLater: () => {} }, osdLayer: {}, readFeedback: () => {}, chooseFeedback: () => {},
      console: { warn: value => warnings.push(value), error: value => assert.fail(value) },
      publishModel: () => {},
      publish: (key, value) => {
        assert.equal(pluginLogic.statusValueFits("state", value), true, label + ": status accepts the current result");
        values[key] = value;
      },
      shell: {
        dictation: { start: mode => { starts.push(mode); return answer; }, stop: () => { stops.push(true); return "ok"; } },
        surfaces: { openPage: (page, target) => { pages.push([page, target]); return "ok"; } },
        shortcut: { register: (name, description, press, release) => { handlers[name] = { press, release }; } },
        ipc: { handle: (name, handler) => { handlers[name + "-ipc"] = { press: handler }; } },
        layers: { show: () => {} }, sounds: { hold: () => "ok" }
      }
    };
    world.root = world;
    vm.runInNewContext(functions + "\n(function () {\n" + registration[1] + "\n})();", world);
    const widget = { shell: { ipc: { call: () => handlers["toggle-ipc"].press() } } };
    vm.runInNewContext(widgetToggle[0], widget);
    for (const [entry, invoke] of [["toggle", handlers.toggle.press], ["tap", handlers.tap.press], ["hold", handlers.talk.press], ["microphone", widget.toggle]]) {
      pages.length = starts.length = stops.length = warnings.length = 0;
      assert.equal(invoke(), answer, label + ": " + entry + " retains the capability answer");
      same(starts, ["type"], label + ": " + entry + " asks for one typed recording");
      same(stops, [], label + ": " + entry + " stops no recording");
      same(pages, tab === "" ? [] : [["vgs.voice", tab]], label + ": " + entry + " opens the correction for this cause");
      if (answer !== "ok") assert.ok(warnings.some(value => value.endsWith(answer)), label + ": the diagnostic cause remains in the log");
      if (tab !== "") {
        same([world.setupValue.tone, world.setupValue.action], [tone, action], label + ": current typed setup replaces stale Ready");
        if (daemon === "starting") same(world.setupValue.lines, [], label + ": pending setup invents no failure cause");
        const request = pluginLogic.statusActionRequest(manifest, "vgs.voice", true, values, action === "stop" ? "otherService" : "setup");
        same(request, action === "stop" ? { ok: true, kind: "tui", name: "stop-other" }
          : action === "setup" ? { ok: true, kind: "core", name: "dictation-setup" }
          : { ok: false, answer: "refused: action=setup reason=not-offered" }, label + ": the current setup controls the existing action");
      }
    }
    if (label === "ready daemon") {
      world.dictationState.holder = "vgs.voice";
      starts.length = 0;
      assert.equal(handlers.toggle.press(), "ok", "toggle stops Voice's own recording");
      same(starts, [], "an own-recording toggle starts nothing");
      same(stops, [true], "an own-recording toggle stops once");
      assert.equal(handlers.talk.release(), "ok", "hold release retains its stop route");
    }
  }
}

// Run the shipped publisher against the states the core publishes during
// initial setup and restart. A stale Ready value must be replaced even
// while no completed setup reading exists.
function verifyRefreshSetup(logic, source) {
  const found = source.match(/^    function refreshSetup\(\) \{\n[\s\S]*?^    \}/m);
  const publisher = source.match(/^    function publishSetup\(\) \{\n[\s\S]*?^    \}/m);
  assert.ok(found, "the service declares the setup refresh");
  assert.ok(publisher, "the service declares the setup publisher");
  const ready = logic.setupState(readsReady, "ready");
  for (const [label, initial, states] of [
    ["cold read failure", { tone: "info", action: "" }, [["starting", null, "info", ""], ["failed", null, "warning", "setup"]]],
    ["restart read failure", ready, [["starting", null, "info", ""], ["failed", null, "warning", "setup"]]],
    ["restart completes", ready, [["starting", null, "info", ""], ["starting", readsReady, "info", ""], ["ready", readsReady, "ok", ""]]]
  ]) {
    const published = [];
    const world = { VoiceLogic: logic, voxtypePresent: true, dictationState: null, daemon: "", setupValue: initial };
    world.publish = (key, value) => {
      assert.ok(["setup", "otherService"].includes(key), label + ": only the declared setup and service statuses are published");
      assert.equal(pluginLogic.statusValueFits("state", value), true, label + ": the real status judge accepts the published value");
      if (key === "setup") published.push(value);
      else same(value, { tone: "ok", text: "No other service to stop", action: false }, label + ": pending and ready setup offer no Settings stop action");
    };
    world.publishModel = () => {};
    vm.runInNewContext(found[0] + "\n" + publisher[0], world);
    for (const [daemon, setup, tone, action] of states) {
      world.daemon = daemon;
      world.dictationState = { daemon, setup };
      const before = published.length;
      world.refreshSetup();
      assert.equal(published.length, before + 1, label + ": the new core state is published");
      same([world.setupValue.tone, world.setupValue.action], [tone, action], label + ": current setup replaces the prior value");
      const value = published[published.length - 1];
      same([value.tone, value.text, value.action], [tone, world.setupValue.text, action === "setup"], label + ": the current setup reaches the status record");
      if (world.setupValue.lines.length === 0) assert.equal(Object.hasOwn(value, "lines"), false, label + ": pending setup omits empty lines");
      else same(value.lines, Array.from(world.setupValue.lines), label + ": the status keeps the setup detail lines");
    }
  }
}

function verify(logic) {
  verifyRefreshSetup(logic, serviceSource);
  // ownDictation: [name, the capability's state, whether the last shown
  // was Voice's own, { own, phase }].
  const ownRows = [
    ["Voice's own recording shows", lent("ready", "recording", "vgs.voice"), false, { own: true, phase: "recording" }],
    ["Voice's own recording shows its transcribing", lent("ready", "transcribing", "vgs.voice"), true, { own: true, phase: "transcribing" }],
    ["Voice's start the daemon has not taken yet reads idle, its own", lent("ready", "idle", "vgs.voice"), false, { own: true, phase: "idle" }],
    ["another holder's recording reads idle", lent("ready", "recording", "acme.dictation"), false, { own: false, phase: "idle" }],
    ["another holder's recording ends Voice's own", lent("ready", "recording", "acme.dictation"), true, { own: false, phase: "idle" }],
    ["the daemon unread after Voice's stop shows transcribing", lent("ready", "unread", ""), true, { own: true, phase: "transcribing" }],
    ["the transcription after Voice's stop shows", lent("ready", "transcribing", ""), true, { own: true, phase: "transcribing" }],
    ["the transcription after another holder's stop reads idle", lent("ready", "transcribing", ""), false, { own: false, phase: "idle" }],
    ["the daemon unread after another holder's stop reads idle", lent("ready", "unread", ""), false, { own: false, phase: "idle" }],
    ["an idle daemon ends Voice's own", lent("ready", "idle", ""), true, { own: false, phase: "idle" }],
    ["a recording nobody holds reads idle", lent("ready", "recording", ""), true, { own: false, phase: "idle" }],
    ["a daemon that is not ready reads idle", lent("failed", "idle", ""), true, { own: false, phase: "idle" }],
  ];
  for (const [name, state, own, want] of ownRows) same(logic.ownDictation(state, own), want, `ownDictation: ${name}`);

  // setupState: [name, reads, the capability's daemon word, tone, action,
  // line count, a fragment the first line holds or null]. Ready's line
  // carries the version and the model; each missing thing is one line.
  const stateRows = [
    ["a pending setup read is not ready", null, "starting", "info", "", 0, null],
    ["a failed setup read offers recovery", null, "failed", "warning", "setup", 1, null],
    ["ready reads the version and the model", readsReady, "ready", "ok", "", 1, "1.1.0"],
    ["ready names the configured model", readsReady, "ready", "ok", "", 1, "parakeet-tdt-0.6b-v3"],
    ["completed setup stays pending until the child is ready", readsReady, "starting", "info", "", 0, null],
    ["real missing prerequisites keep their warning while starting", readsMissing, "starting", "warning", "setup", 2, null],
    ["every missing thing is a line", readsMissing, "failed", "warning", "setup", 3, null],
    ["no daemon is not ready", readsReady, "absent", "warning", "setup", 1, null],
    ["a daemon the shell did not start offers to stop it", readsReady, "elsewhere", "warning", "stop", 1, null],
    ["a daemon the shell did not start offers to stop it before the setup", readsMissing, "elsewhere", "warning", "stop", 3, null],
    ["a daemon that failed is not ready", readsReady, "failed", "warning", "setup", 1, null],
    ["a missing model is not ready", Object.assign({}, readsReady, { installed: false }), "ready", "warning", "setup", 1, null],
    ["no version still reads ready", Object.assign({}, readsReady, { version: "" }), "ready", "ok", "", 1, "parakeet-tdt-0.6b-v3"],
  ];
  for (const [name, reads, daemon, tone, action, count, fragment] of stateRows) {
    const state = logic.setupState(reads, daemon);
    same([state.tone, state.action, state.lines.length], [tone, action, count], `setupState: ${name}`);
    if (fragment !== null) assert.ok(state.lines[0].includes(fragment), `setupState: ${name}: the first line holds ${fragment}`);
  }
  for (const missing of [{ compiled: false }, { installed: false }, { compiled: false, installed: false }]) {
    const state = logic.setupState(Object.assign({}, readsReady, missing), "absent");
    same([state.tone, state.action], ["warning", "setup"], "an absent daemon keeps setup offered for each missing prerequisite");
  }
  // The stop path's row offers no Set up, so its engine line drops the
  // instruction the Set up paths' line ends with.
  {
    const offered = logic.setupState(Object.assign({}, readsReady, { compiled: false }), "absent").lines[0];
    const stopped = logic.setupState(Object.assign({}, readsReady, { compiled: false }), "elsewhere").lines[0];
    assert.ok(stopped !== offered && offered.startsWith(stopped), "setupState: the stop path's engine line names no action its row lacks");
  }
  // Without voxtype the reading offers no setup action of its own.
  for (const daemon of ["failed", ""])
    same(logic.setupState({ present: false }, daemon), { hidden: true, lines: [], action: "", engine: "parakeet", model: "parakeet-tdt-0.6b-v3" }, `setupState: voxtype not found, daemon ${JSON.stringify(daemon)}, hides the entry`);
  // The published step without voxtype, for each daemon word: To do, with
  // a hint, offering Review, the one install action, on its own row while
  // voxtype is missing. The real status judge admits it for the shipped
  // manifest's step.
  const voxtypeMissing = pluginLogic.requirementRows(voiceJudged.manifest, ["voxtype", "voxtype-audio-bridge"], {});
  for (const daemon of Object.keys(logic.DAEMON_LINES)) {
    const label = `setupPublished: voxtype not found, daemon ${daemon}`;
    const value = logic.setupPublished(logic.setupState({ present: false }, daemon));
    same([value.tone, value.action, typeof value.hint, Object.hasOwn(value, "available")], ["warning", pluginLogic.STATUS_TOOLS_ACTION, "string", false], label + ": a To do step that names the install action");
    assert.equal(pluginLogic.hintFits(value.hint), true, label + ": the hint keeps the copy rule");
    assert.equal(pluginLogic.statusWrite(voiceJudged.manifest, {}, "setup", value).ok, true, label + ": the status judge admits the value");
    const row = pluginLogic.statusRows(voiceJudged.manifest, { setup: value }).find(entry => entry.key === "setup");
    assert.equal(steps.stepReading(row), "todo", label + ": the step reads To do");
    same((steps.stepButton(row, voxtypeMissing) || {}).kind, "tools", label + ": the step's row offers Review");
  }
  // Another voxtype in the daemon's place: the step offers no action of
  // its own, and its hint opens Details, where Stop the other voxtype is.
  const stop = logic.setupPublished(logic.setupState(readsMissing, "elsewhere"));
  same([Object.keys(stop), stop.tone, stop.action], [["tone", "text", "lines", "action", "hint"], "warning", false], "setupPublished: another voxtype offers no Setup action");
  const stopTarget = pageReference.parse(stop.hint);
  same([stopTarget.page, stopTarget.tab], ["vgs.voice", "Details"], "setupPublished: another voxtype's hint opens Details");
  for (const [name, reads, daemon, action] of [["a missing model offers Set up", readsMissing, "ready", true], ["ready offers nothing", readsReady, "ready", false]]) {
    const value = logic.setupPublished(logic.setupState(reads, daemon));
    same([value.action, Object.hasOwn(value, "hint")], [action, false], `setupPublished: ${name}`);
    assert.equal(pluginLogic.statusWrite(voiceJudged.manifest, {}, "setup", value).ok, true, `setupPublished: ${name}: the status judge admits the value`);
  }
  // Absent and failed ask for the same Set up; another voxtype has its own line.
  const daemonLines = ["absent", "elsewhere", "failed"].map(daemon => logic.setupState(readsReady, daemon).lines[0]);
  same([daemonLines[0] === daemonLines[2], daemonLines[1] !== daemonLines[0]], [true, true], "absent and failed read one line, elsewhere its own");
  assert.throws(() => logic.setupState(readsReady, "paused"), "a daemon word the capability does not have is refused");
  assert.equal(logic.versionOf("voxtype 1.1.0\n"), "1.1.0", "the version is read from --version");
  assert.equal(logic.versionOf("voxtype\n"), "", "no version reads empty");
  const configured = logic.setupState(Object.assign({}, readsReady, { engine: "whisper", model: "configured" }), "starting");
  same(logic.modelData(lent("starting", "idle", ""), configured), { engine: "whisper", model: "configured" }, "the Model row reads the configured engine and model before a daemon names its own");
  same(logic.modelData(Object.assign(lent("ready", "idle", ""), { engine: "whisper", model: "base.en" }), configured), { engine: "whisper", model: "base.en" }, "the Model row reads the running daemon's engine and model");

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

  // runFinished: [name, the endedAt seen last, the screen's state, want].
  const ended = (endedAt, code) => ({ running: false, code: code, endedAt: endedAt });
  const finishedRows = [
    ["a run ended before the first read restarts nothing", undefined, ended("t1", 0), false],
    ["the first run ending with code 0 restarts", null, ended("t1", 0), true],
    ["a new run ending with code 0 restarts", "t1", ended("t2", 0), true],
    ["the end already seen restarts nothing again", "t2", ended("t2", 0), false],
    ["a failed run restarts nothing", "t1", ended("t2", 1), false],
    ["a run that never ended restarts nothing", null, { running: true, code: null, endedAt: null }, false],
  ];
  for (const [name, seen, run, want] of finishedRows) assert.equal(logic.runFinished(seen, run), want, `runFinished: ${name}`);

  // Dictation sounds. feedbackValue: [name, the stdout of `voxtype config
  // get audio.feedback.enabled --json`, the value]; the first two are what
  // voxtype 1.1.0 printed in a scratch home on host cachy on 2026-10-09.
  const feedbackOn = '{\n  "file_value": true,\n  "key": "audio.feedback.enabled",\n  "value": true\n}\n';
  const feedbackOff = '{\n  "file_value": null,\n  "key": "audio.feedback.enabled",\n  "value": false\n}\n';
  const feedbackValueRows = [
    ["tones on in the file", feedbackOn, "own"],
    ["no config file and the default in effect", feedbackOff, ""],
    ["no output", "", null],
    ["a value that is no boolean", '{"value":"true"}', null],
    ["an answer that is no object", "true", null],
  ];
  for (const [name, out, want] of feedbackValueRows) assert.equal(logic.feedbackValue(out), want, `feedbackValue: ${name}`);

  // fileKind: [name, the stdout of `stat --format=%f`, the kind]; the three
  // modes are what stat printed for a file, a symbolic link and a
  // directory on host cachy on 2026-10-09.
  const kindRows = [
    ["a regular file", "81a4\n", "file"],
    ["a symbolic link", "a1ff\n", "link"],
    ["a directory", "41ed\n", "none"],
    ["no output, as for a missing file", "", "none"],
    ["text that is no mode", "regular file\n", "none"],
  ];
  for (const [name, out, want] of kindRows) assert.equal(logic.fileKind(out), want, `fileKind: ${name}`);

  // feedbackCommand: each stage's argv, which voxtype and stat read; the
  // restart stage runs none, the service asks the capability.
  const get = ["voxtype", "config", "get", "audio.feedback.enabled", "--json"];
  const commandRows = [
    ["read", "", get],
    ["verify", "", get],
    ["kind", "", ["stat", "--format=%f", "--", "/h/.config/voxtype/config.toml"]],
    ["write", "", ["voxtype", "config", "set", "audio.feedback.enabled", "false"]],
    ["write", "own", ["voxtype", "config", "set", "audio.feedback.enabled", "true"]],
    ["restart", "", null],
  ];
  for (const [stage, wanted, want] of commandRows) same(logic.feedbackCommand(stage, wanted, "/h/.config/voxtype/config.toml"), want, `feedbackCommand: ${stage} for ${JSON.stringify(wanted)}`);
  for (const stage of logic.FEEDBACK_STAGES) assert.doesNotThrow(() => logic.feedbackCommand(stage, "", "/c"), `feedbackCommand: stage ${stage} is known`);
  assert.throws(() => logic.feedbackCommand("done", "", "/c"), "a stage outside the list has no command");
  same(logic.feedbackRun(""), { stage: "read", wanted: "", value: null, problem: "" }, "a run starts by reading");

  // feedbackNext: [name, the run, the exit code and stdout of its stage,
  // the run after].
  const at = (stage, wanted, value, problem) => ({ stage: stage, wanted: wanted, value: value, problem: problem });
  const nextRows = [
    ["a read alone states the value and ends", at("read", null, null, ""), 0, feedbackOn, at("done", null, "own", "")],
    ["a read alone that fails ends unread", at("read", null, null, ""), 1, "", at("done", null, null, "unread")],
    ["a choice the config already holds writes nothing and restarts nothing", at("read", "", null, ""), 0, feedbackOff, at("done", "", "", "")],
    ["a choice the config does not hold goes on to the file", at("read", "", null, ""), 0, feedbackOn, at("kind", "", "own", "")],
    ["a choice over a value that cannot be read writes nothing", at("read", "", null, ""), 1, "", at("done", "", null, "unread")],
    ["a regular config file is written", at("kind", "", "own", ""), 0, "81a4\n", at("write", "", "own", "")],
    ["a symbolic link is left as it is", at("kind", "", "own", ""), 0, "a1ff\n", at("done", "", "own", "link")],
    ["a missing config file is not written", at("kind", "own", "", ""), 1, "", at("done", "own", "", "no-config")],
    ["a write has the daemon started again", at("write", "", "own", ""), 0, "", at("restart", "", "own", "")],
    ["a failed write restarts nothing", at("write", "", "own", ""), 1, "", at("done", "", "own", "write")],
    ["a restart is followed by the read back", at("restart", "", "own", ""), 0, "", at("verify", "", "own", "")],
    ["a refused restart is named and the value is read back", at("restart", "", "own", ""), 1, "", at("verify", "", "own", "restart")],
    ["the read back states the value", at("verify", "", "own", ""), 0, feedbackOff, at("done", "", "", "")],
    ["the read back keeps a failed restart", at("verify", "", "own", "restart"), 0, feedbackOff, at("done", "", "", "restart")],
    ["a read back of another value is a mismatch", at("verify", "", "own", ""), 0, feedbackOn, at("done", "", "own", "mismatch")],
    ["a read back that fails is unread", at("verify", "", "own", ""), 1, "", at("done", "", null, "unread")],
  ];
  const problems = new Set(["missing"]);
  for (const [name, run, code, out, want] of nextRows) {
    same(logic.feedbackNext(run, code, out), want, `feedbackNext: ${name}`);
    problems.add(want.problem);
  }
  assert.throws(() => logic.feedbackNext(at("done", "", "", ""), 0, ""), "a run that ended has no next stage");
  // Every problem a run ends with, and voxtype missing, has its line.
  for (const problem of problems) assert.equal(typeof logic.FEEDBACK_PROBLEMS[problem], "string", `FEEDBACK_PROBLEMS has ${JSON.stringify(problem)}`);
  same(Object.keys(logic.FEEDBACK_PROBLEMS).sort(), [...problems].sort(), "FEEDBACK_PROBLEMS holds no line a run cannot end with");
  same(Object.keys(logic.FEEDBACK_PROBLEMS).filter(problem => (logic.FEEDBACK_PROBLEMS[problem] === "") !== (problem === "")), [], "each problem but none has a line");
  // The lines that send the user to the Voice page link to the tab that
  // holds the step: Setup holds Install all missing and Set up, Settings
  // holds Configure.
  const target = problem => { const found = pageReference.parse(logic.FEEDBACK_PROBLEMS[problem]); return [found.page, found.tab]; };
  same(target("missing"), ["vgs.voice", "Setup"], "voxtype missing links to the Setup tab");
  same(target("no-config"), ["vgs.voice", "Setup"], "no config links to the Setup tab");
  same(target("link"), ["vgs.voice", "Settings"], "a linked config links to the Settings tab");
}

verify(load(file));

const controls = [
  ["complete setup reports success before child readiness", '    if (daemon === "starting") return { tone: "info", text: "Checking", lines: [], action: "", engine: engine, model: model };\n', ""],
  ["voxtype missing names the page in plain words", "Install it on the [Voice page](page:vgs.voice/Setup).", "Install it on the Voice Settings page."],
  ["a linked config links to the Details tab", "Use Configure on the [Voice page](page:vgs.voice/Settings).", "Use Configure on the [Voice page](page:vgs.voice/Details)."],
  ["the phase is read whatever the holder", "if (state.holder === HOLDER) return { own: true, phase: state.phase };", "if (state.holder !== \"\") return { own: true, phase: state.phase };"],
  ["Voice's own recording reads idle", "if (state.holder === HOLDER) return { own: true, phase: state.phase };", ""],
  ["the transcription after any stop shows", "var after = own && state.holder === \"\"", "var after = state.holder === \"\""],
  ["a recording nobody holds shows after Voice's own", " && (state.phase === \"unread\" || state.phase === \"transcribing\");", ";"],
  ["the transcription after Voice's stop reads idle", "phase: after ? \"transcribing\" : \"idle\"", "phase: \"idle\""],
  ["model presence ignored", "if (!reads.installed)", "if (false)"],
  ["engine compiled ignored", "if (!reads.compiled)", "if (false)"],
  ["setup never offers action", "if (lines.length > 0) return { tone: \"warning\", text: \"To do\", lines: lines, action: daemon === \"elsewhere\" ? \"stop\" : \"setup\",", "if (lines.length > 0) return { tone: \"warning\", text: \"To do\", lines: lines, action: \"\","],
  ["a daemon that is not ready reads ready", "    if (DAEMON_LINES[daemon] !== \"\" && (daemon !== \"absent\" || lines.length === 0)) lines.push(", "    if (false) lines.push("],
  ["a daemon the shell did not start reads as one that failed", "    elsewhere: \"Another voxtype is already running. Stop the other voxtype so VGS can start its own.\",", "    elsewhere: \"Dictation is not running. Select Set up to start it.\","],
  ["a daemon the shell did not start offers Set up", "action: daemon === \"elsewhere\" ? \"stop\" : \"setup\",", "action: \"setup\","],
  ["any line offers Stop the other voxtype", "action: daemon === \"elsewhere\" ? \"stop\" : \"setup\",", "action: \"stop\","],
  ["an unknown daemon word reads ready", "    if (DAEMON_LINES[daemon] === undefined)\n", "    if (false)\n"],
  ["voxtype absent offers Set up", "return { hidden: true, lines: [], action: \"\",", "return { hidden: true, lines: [], action: \"setup\","],
  ["voxtype absent offers no install action", ", action: \"tools\" };", ", action: false };"],
  ["voxtype absent reads Done", "if (state.hidden) return { tone: \"warning\",", "if (state.hidden) return { tone: \"ok\","],
  ["another voxtype loses its hint", "if (state.action === \"stop\") value.hint", "if (false) value.hint"],
  ["pending setup publishes empty lines", "if (state.lines !== undefined && state.lines.length > 0) value.lines = state.lines;", "value.lines = state.lines;"],
  ["voxtype absent draws its own line", "return { hidden: true, lines: [], action: \"\",", "return { tone: \"warning\", text: \"To do\", lines: [\"voxtype is not installed.\"], action: \"\","],
  ["the version is not read", "return found === null ? \"\" : found[1];", "return \"\";"],
  ["bridge frame shape ignored", "if (!amplitude(frame.peak) || !amplitude(frame.rms)) return { ok: false, reason: \"frame\" };", ""],
  ["bridge status lines read as frames", "if (frame.status === \"connected\" || frame.status === \"disconnected\") return { ok: true, kind: frame.status };", ""],
  ["level not lifted", "Math.pow(Math.max(peak, rms * RMS_WEIGHT) * LEVEL_GAIN, LEVEL_GAMMA)", "Math.max(peak, rms * RMS_WEIGHT) * LEVEL_GAIN"],
  ["level ignores rms", "Math.max(peak, rms * RMS_WEIGHT)", "peak"],
  ["a past run's end at startup restarts", "return seen !== undefined && ", "return "],
  ["a failed run restarts", " && run.code === 0;", ";"],
  ["a seen end restarts again", " && run.endedAt !== seen", ""],
  ["a read alone goes on to a write", "else if (run.wanted !== null && next.value !== run.wanted) next.stage = \"kind\";", "else if (next.value !== run.wanted) next.stage = \"kind\";"],
  ["a choice the config holds is written again", "else if (run.wanted !== null && next.value !== run.wanted) next.stage = \"kind\";", "else if (run.wanted !== null) next.stage = \"kind\";"],
  ["a value that cannot be read is written over", "if (next.value === null) next.problem = \"unread\";\n        else if (run.wanted !== null", "if (run.wanted === null && next.value === null) next.problem = \"unread\";\n        else if (run.wanted !== null"],
  ["a symbolic link is written through", "if (kind === \"file\") next.stage = \"write\";", "if (kind !== \"none\") next.stage = \"write\";"],
  ["a missing config file is written", "if (kind === \"file\") next.stage = \"write\";", "if (kind !== \"link\") next.stage = \"write\";"],
  ["a link reads as a missing file", "else next.problem = kind === \"link\" ? \"link\" : \"no-config\";", "else next.problem = \"no-config\";"],
  ["a link's mode reads as a file's", "return type === 0x8000 ? \"file\" : type === 0xa000 ? \"link\" : \"none\";", "return type === 0x8000 || type === 0xa000 ? \"file\" : \"none\";"],
  ["a failed write restarts the daemon", "if (code !== 0) next.problem = \"write\";\n        else next.stage = \"restart\";", "next.stage = \"restart\";"],
  ["a write restarts nothing", "        else next.stage = \"restart\";", "        else next.stage = \"verify\";"],
  ["a refused restart is silent", "if (code !== 0) next.problem = \"restart\";\n        next.stage = \"verify\";", "next.stage = \"verify\";"],
  ["a mismatch is silent", "else if (next.value !== run.wanted) next.problem = \"mismatch\";", ""],
  ["a read back that fails is silent", "if (next.value === null) next.problem = \"unread\";\n        else if (next.value !== run.wanted)", "if (false) next.problem = \"unread\";\n        else if (next.value !== run.wanted)"],
  ["the value in effect is not read", "return data.value ? FEEDBACK_ON : FEEDBACK_OFF;", "return FEEDBACK_ON;"],
  ["a value that is no boolean is read", "if (!isObject(data) || typeof data.value !== \"boolean\") return null;", "if (!isObject(data)) return null;"],
  ["off is written as on", "wanted === FEEDBACK_ON ? \"true\" : \"false\"", "\"true\""],
  ["the restart stage runs a command", "    case \"restart\": return null;", "    case \"restart\": return [\"voxtype\", \"daemon\"];"],
  ["the configured model wins over the running daemon's", "model: state.model !== \"\" ? state.model : setup.model };", "model: setup.model };"],
  ["the Model row is empty before a daemon runs", "model: state.model !== \"\" ? state.model : setup.model };", "model: state.model };"]
];
const source = fs.readFileSync(file, "utf8");
const temp = fs.mkdtempSync(path.join(require("node:os").tmpdir(), "voice-logic-control-"));
try {
  for (const [label, needle, replacement] of controls) {
    assert.equal(source.split(needle).length, 2, `control ${label}: replacement text occurs once`);
    const mutant = path.join(temp, "VoiceLogic.js");
    fs.writeFileSync(mutant, source.replace(needle, replacement));
    let failed = false;
    try { verify(load(mutant)); } catch (e) { failed = true; }
    assert.ok(failed, `control ${label}: suite passed without the rule`);
  }
  const needle = "        setupValue = VoiceLogic.setupState(dictationState.setup, daemon);";
  assert.equal(serviceSource.split(needle).length, 2, "the null-setup control text occurs once");
  const copy = path.join(temp, "Service.qml");
  fs.writeFileSync(copy, serviceSource.replace(needle, "        if (dictationState.setup === null) return;\n" + needle));
  assert.throws(() => verifyRefreshSetup(load(file), fs.readFileSync(copy, "utf8")), assert.AssertionError,
    "control: retaining old setup while readings are null must fail publication");
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
// The requirement logic over the shipped manifest: Configure, Choose model
// and Stop the other voxtype run voxtype, so a press without it raises the
// requirement notice in place of the script, which then opens the screen
// once it is found. Only Stop the other voxtype needs systemctl: the core
// runs voxtype, and no user unit does.
const publishSetupSource = serviceSource.match(/^    function publishSetup\(\) \{[\s\S]*?^    \}/m);
assert.ok(publishSetupSource, "the service declares its status publication");
function publishedSetup(state) {
  const values = {};
  const publish = vm.runInNewContext("(" + publishSetupSource[0] + ")", {
    VoiceLogic: logic,
    setupValue: state,
    publish: (key, value) => { values[key] = value; },
    publishModel: () => {}
  });
  publish();
  return values;
}
const manifestFile = path.join(repo, "shell", "plugins", "vgs.voice", "manifest.json");
const logic = load(file);
// The screens that run voxtype.
const VOXTYPE_TUIS = ["configure", "model"];
function verifyRequirements(raw) {
  const judged = pluginLogic.validateManifest(raw, path.dirname(manifestFile));
  assert.ok(judged.ok, `the Voice manifest is accepted: ${judged.error}`);
  const missing = ["voxtype", "voxtype-audio-bridge"];
  const runner = { launcher: "present", busy: [], run: "r1" };
  same(Object.keys(judged.manifest.tui).sort(), Array.from(logic.RESTART_TUIS).sort(), "the screens Voice ships are the three whose end restarts the daemon");
  same(Array.from(logic.RESTART_TUIS).sort(), ["configure", "model", "stop-other"], "Configure, Choose model and Stop the other voxtype restart the daemon");
  for (const name of VOXTYPE_TUIS) {
    same(pluginLogic.tuiMissingRequirements(judged.manifest, name, missing), ["voxtype"], `${name} without voxtype asks for it before its script`);
    same(pluginLogic.tuiMissingRequirements(judged.manifest, name, ["systemctl"]), [], `${name} without systemctl runs its script`);
    same(pluginLogic.tuiMissingRequirements(judged.manifest, name, ["wtype", "wl-copy"]), [], `${name} without the typing tools runs its script`);
    same(pluginLogic.tuiMissingRequirements(judged.manifest, name, []), [], `${name} with voxtype present runs its script`);
    same(pluginLogic.tuiRunFor(judged.manifest, true, "/src", runner, name, missing).kind, "install", `the ${name} press raises the requirement notice`);
  }
  // The required step offers the core's dictation setup while needed.
  // Tools supplies missing voxtype; the ready step offers no action.
  const act = (reads, daemon, key = "setup") => {
    const state = logic.setupState(reads, daemon);
    const values = publishedSetup(state);
    return pluginLogic.statusActionRequest(judged.manifest, "vgs.voice", true, values, key);
  };
  same(act({ present: false }, "failed"), { ok: false, answer: "refused: action=setup reason=not-offered" }, "without voxtype the setup entry offers no step");
  same(act(readsMissing, "ready"), { ok: true, kind: "core", name: "dictation-setup" }, "Set up opens the core's dictation setup");
  same(act(readsReady, "ready").ok, false, "a ready Voice offers no step");
  same(act(readsReady, "elsewhere", "otherService"), { ok: true, kind: "tui", name: "stop-other" }, "another voxtype running opens Stop the other voxtype");
  same(pluginLogic.tuiMissingRequirements(judged.manifest, "stop-other", missing), ["voxtype"], "Stop the other voxtype without voxtype asks for it before its script");
  same(pluginLogic.tuiMissingRequirements(judged.manifest, "stop-other", ["systemctl"]), ["systemctl"], "Stop the other voxtype without systemctl asks for it before its script");
  // Missing voxtype leaves the required step pending beside Tools.
  // The rows use the values the service publishes without voxtype.
  const absent = logic.setupState({ present: false }, "failed");
  const published = publishedSetup(absent);
  same(pluginLogic.requirementRows(judged.manifest, missing, {}).filter(row => row.name === "voxtype").map(row => row.state), ["missing"], "voxtype is one requirement, missing");
  same(pluginLogic.statusRows(judged.manifest, published).map(row => row.key), ["setup", "otherService"], "the page has no duplicate dictation-tool presence row");
  same(pluginLogic.statusRows(judged.manifest, published).filter(row => row.setup).map(row => [row.key, row.tone, row.action.offered]), [["setup", "warning", false]], "without voxtype the required step stays visible and pending");
}
const shipped = JSON.parse(fs.readFileSync(manifestFile, "utf8"));
verifyRequirements(shipped);
const judgedVoice = pluginLogic.validateManifest(shipped, path.dirname(manifestFile));
assert.ok(judgedVoice.ok, "the Voice manifest supplies the correction route");
verifyStartCorrection(serviceSource, judgedVoice.manifest);
verifyRecovery(load(file), serviceSource);
const recoveryControls = [
  ["service", "failed recovery opens its correction", '            if (dictationState.daemon === "failed") shell.surfaces.openPage(VoiceLogic.HOLDER, "Setup");', '            if (false) shell.surfaces.openPage(VoiceLogic.HOLDER, "Setup");'],
  ["service", "recovery remembers the refused start", '        recoveryRequested = answer.indexOf("refused: dictation=engine-busy state=") === 0;', '        recoveryRequested = false;'],
  ["owner", "cancelled result cannot be delivered after recovery or a new start", 'if (root.model.delivery === delivery) done(effect.result);', 'if (true) done(effect.result);'],
  ["model", "idle recovery retires delayed results", '        if (t.reconciling && read === "idle") t.delivery += 1;', '        if (false) t.delivery += 1;'],
  ["model", "normal completion survives the next holder's start", '    t.recording = { holder: id, mode: mode, phase: "starting", path: "" };', '    t.delivery += 1;\n    t.recording = { holder: id, mode: mode, phase: "starting", path: "" };'],
  ["model", "an absent state cannot leave recovery waiting forever", '        if (t.reconciling && read === "stopped") read = null;', '        if (false) read = null;'],
  ["model", "stale start reads fresh engine status", '        if (t.pending === 0) command(t, effects, STATE, STATUS_ARGV);', '        if (false) command(t, effects, STATE, STATUS_ARGV);'],
  ["model", "another holder is untouched by recovery", '    else if (t.recording !== null) answer = "refused: dictation=busy holder=" + t.recording.holder;', '    else if (false) answer = "refused: dictation=busy holder=" + t.recording.holder;'],
  ["logic", "recovered idle hides the old transcription display", '(state.phase === "unread" || state.phase === "transcribing")', '(state.phase === "idle" || state.phase === "unread" || state.phase === "transcribing")'],
  ["logic", "progressing transcription remains visible", '(state.phase === "unread" || state.phase === "transcribing")', '(state.phase === "unread")'],
  ["logic", "another holder has no Voice display", 'if (state.holder === HOLDER)', 'if (state.holder !== "")']
];
const recoveryTemp = fs.mkdtempSync(path.join(require("node:os").tmpdir(), "voice-recovery-control-"));
try {
  const sources = { service: serviceSource, owner: dictationSource, model: fs.readFileSync(dictationModelFile, "utf8"), logic: fs.readFileSync(file, "utf8") };
  for (const [target, label, needle, replacement] of recoveryControls) {
    assert.equal(sources[target].split(needle).length, 2, label + ": mutation matches once");
    const changed = sources[target].replace(needle, replacement);
    assert.notEqual(changed, sources[target]);
    const copy = path.join(recoveryTemp, target + ".js");
    fs.writeFileSync(copy, changed);
    const logic = target === "logic" ? load(copy) : load(file);
    const model = target === "model" ? load(copy) : load(dictationModelFile);
    assert.throws(() => verifyRecovery(logic, target === "service" ? changed : serviceSource, model, target === "owner" ? changed : dictationSource), assert.AssertionError, "control: " + label);
  }
} finally {
  fs.rmSync(recoveryTemp, { recursive: true, force: true });
}
const startControls = [
  ["the pending correction is not opened", ' || answer === "refused: dictation=daemon-starting"', ""],
  ["the correction is not opened", "            shell.surfaces.openPage(", "            if (false) shell.surfaces.openPage("],
  ["the correction uses stale Ready", "            refreshSetup();\n            shell.surfaces.openPage(", "            if (false) refreshSetup();\n            shell.surfaces.openPage("],
  ["the foreign daemon opens Setup", 'setupValue.action === "stop" ? "Details" : "Setup"', 'setupValue.action === "stop" ? "Setup" : "Setup"']
];
const startTemp = fs.mkdtempSync(path.join(require("node:os").tmpdir(), "voice-start-control-"));
try {
  for (const [label, needle, replacement] of startControls) {
    assert.equal(serviceSource.split(needle).length, 2, label + ": the mutation matches once");
    const copy = path.join(startTemp, "Service.qml");
    const changed = serviceSource.replace(needle, replacement);
    assert.notEqual(changed, serviceSource, label + ": the source changes");
    fs.writeFileSync(copy, changed);
    assert.throws(() => verifyStartCorrection(fs.readFileSync(copy, "utf8"), judgedVoice.manifest), assert.AssertionError, "control: " + label);
  }
} finally {
  fs.rmSync(startTemp, { recursive: true, force: true });
}
for (const name of VOXTYPE_TUIS) {
  const unrequired = JSON.parse(JSON.stringify(shipped));
  assert.deepEqual(unrequired.tui[name].requires, ["voxtype"], `control unrequired ${name}: the shipped screen requires voxtype`);
  delete unrequired.tui[name].requires;
  assert.throws(() => verifyRequirements(unrequired), `control unrequired ${name}: a manifest copy whose ${name} does not require voxtype passed`);
}
const manifestControls = [
  ["a manifest copy whose Configure needs systemctl", raw => { raw.tui.configure.requires.push("systemctl"); }],
  ["a manifest copy whose elsewhere step is Set up", raw => { raw.status.otherService.action = { label: "Stop the other voxtype", dictation: "setup" }; }],
  ["a manifest copy that keeps its own Set up screen", raw => { raw.tui.setup = JSON.parse(JSON.stringify(raw.tui.model)); raw.status.setup.action = { label: "Set up", tui: "setup" }; }],
  ["a manifest copy whose Details states voxtype's presence", raw => { raw.status = Object.assign({ voxtype: { type: "state", label: "voxtype" } }, raw.status); }],
];
for (const [label, edit] of manifestControls) {
  const copy = JSON.parse(JSON.stringify(shipped));
  edit(copy);
  assert.throws(() => verifyRequirements(copy), `control: ${label} passed`);
}

// The dictation sounds event over the shipped manifest: the core takes each
// value and each problem line the service states for it, and stores no
// choice for it, so voxtype's config is the value's one holder.
function verifyFeedback(raw) {
  const manifest = pluginLogic.validateManifest(raw, path.dirname(manifestFile)).manifest;
  for (const value of [logic.FEEDBACK_ON, logic.FEEDBACK_OFF, null]) {
    for (const problem of Object.keys(logic.FEEDBACK_PROBLEMS))
      assert.equal(pluginLogic.soundReport(manifest, "feedback", value, logic.FEEDBACK_PROBLEMS[problem]).ok, true, `the core takes ${JSON.stringify(value)} with the ${JSON.stringify(problem)} line`);
  }
  for (const value of [logic.FEEDBACK_ON, logic.FEEDBACK_OFF])
    same(pluginLogic.soundEdit({ version: 1 }, {}, manifest, "vgs.voice", "feedback", value), { ok: true, held: true }, `the choice ${JSON.stringify(value)} goes to Voice and writes no user file`);
  same(pluginLogic.soundChoices({ sounds: { "vgs.voice": { feedback: "" } } }, manifest), {}, "the core lends Voice no stored choice");
}
verifyFeedback(shipped);
const stored = JSON.parse(JSON.stringify(shipped));
delete stored.sounds.feedback.held;
stored.sounds.feedback.default = "own";
assert.throws(() => verifyFeedback(stored), "control stored: a manifest copy whose dictation event the core stores passed");

console.log(`test-voice-logic: ok controls=${controls.length + startControls.length + recoveryControls.length + VOXTYPE_TUIS.length + 1 + manifestControls.length + 1}`);
