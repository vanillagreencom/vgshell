.pragma library

var STATES = ["idle", "recording", "transcribing", "stopped"];
var DEFAULT_ENGINE = "parakeet";
var DEFAULT_MODEL = "parakeet-tdt-0.6b-v3";

function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function asString(value) {
    return typeof value === "string" ? value : "";
}

function parseJson(text, fallback) {
    try {
        return JSON.parse(text);
    } catch (e) {
        return fallback;
    }
}

function configValue(text, fallback) {
    var value = parseJson(text, undefined);
    if (value === undefined) return fallback;
    if (isObject(value) && value.value !== undefined) return String(value.value);
    if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") return String(value);
    return fallback;
}

function stateOf(raw) {
    if (raw === "streaming") return "recording";
    return STATES.indexOf(raw) === -1 ? "idle" : raw;
}

function parseStatus(line) {
    var data = parseJson(line, null);
    if (!isObject(data)) return { ok: false, reason: "json" };
    var raw = asString(data.state) || asString(data.alt) || asString(data.class) || asString(data.status) || "idle";
    var state = stateOf(raw);
    var model = asString(data.model);
    var backend = asString(data.backend);
    var device = asString(data.device);
    return { ok: true, state: state, rawState: raw, unknown: state === "idle" && raw !== "idle", backend: backend, device: device, model: model };
}

function modelRows(modelsText, engine) {
    var data = parseJson(modelsText, null);
    if (!isObject(data) || !isObject(data.engines) || !isObject(data.engines[engine]) || !Array.isArray(data.engines[engine].models)) return [];
    return data.engines[engine].models;
}

function modelInstalled(modelsText, engine, wanted) {
    var models = modelRows(modelsText, engine);
    for (var i = 0; i < models.length; i++) {
        var row = models[i];
        if (isObject(row) && row.name === wanted && row.installed === true) return true;
    }
    return false;
}

function engineAvailable(enginesText, wanted) {
    var engines = parseJson(enginesText, null);
    if (!Array.isArray(engines)) return false;
    for (var i = 0; i < engines.length; i++) {
        var row = engines[i];
        if (isObject(row) && row.name === wanted) return row.compiled === true;
    }
    return false;
}

function unitEnabled(text) {
    var value = configValue(text, text).trim();
    return value === "enabled" || value === "static";
}

// `systemctl --user is-active voxtype` answers `active` while the daemon runs.
function unitActive(text) {
    return String(text).trim() === "active";
}

// The version `voxtype --version` prints, as `voxtype 1.1.0`, or "".
function versionOf(text) {
    var found = /\b(\d+\.\d+(?:\.\d+)?)\b/.exec(String(text));
    return found === null ? "" : found[1];
}

// The stages the service reads Set up's state in, each one command's
// stdout under its name (Service.probeCommand), and the two of them that
// systemctl answers.
var PROBE_STAGES = ["version", "engine", "model", "models", "engines", "unit", "active"];
var SERVICE_STAGES = ["unit", "active"];

// Set up's state from READS, the service's probe stdout by stage, with
// `present` false while voxtype is not found: { tone, text, lines, action,
// engine, model }. Ready reads the version and the model, then that the
// service runs; otherwise each line names one thing that is missing, and
// the action, Set up, is offered.
function setupState(reads) {
    if (reads.present === false)
        return { tone: "warning", text: "Set up needed", lines: ["voxtype is not installed."], action: true, engine: DEFAULT_ENGINE, model: DEFAULT_MODEL };
    var engine = configValue(reads.engine || "", DEFAULT_ENGINE);
    var model = configValue(reads.model || "", DEFAULT_MODEL);
    var lines = [];
    if (!engineAvailable(reads.engines || "", engine)) lines.push("The active build cannot use " + engine + ".");
    if (!modelInstalled(reads.models || "", engine, model)) lines.push("The speech model is missing.");
    if (!unitEnabled(reads.unit || "")) lines.push("The Voice service is not enabled.");
    if (!unitActive(reads.active || "")) lines.push("The Voice service is not running.");
    if (lines.length > 0) return { tone: "warning", text: "Set up needed", lines: lines, action: true, engine: engine, model: model };
    var version = versionOf(reads.version || "");
    var summary = (version === "" ? "voxtype" : "voxtype " + version) + " \u00b7 " + model;
    return { tone: "ok", text: "Ready", lines: [summary, "The Voice service is running."], action: false, engine: engine, model: model };
}

// The on-screen display's level from one voxtype-audio-bridge frame, as the
// owner's plasma design reads it: the louder of the peak and RMS_WEIGHT times
// the RMS, times LEVEL_GAIN, raised to LEVEL_GAMMA. The gamma under 1 lifts
// quiet speech without moving silence, and ordinary speech reaches 1.
var RMS_WEIGHT = 1.7;
var LEVEL_GAIN = 6.0;
var LEVEL_GAMMA = 0.62;

function amplitude(value) {
    return typeof value === "number" && isFinite(value) && value >= 0;
}

// One stdout line of voxtype-audio-bridge: a frame with `peak` and `rms`, or
// a `connected` or `disconnected` status line.
function parseFrame(line) {
    var frame = parseJson(line, null);
    if (!isObject(frame)) return { ok: false, reason: "json" };
    if (frame.status === "connected" || frame.status === "disconnected") return { ok: true, kind: frame.status };
    if (!amplitude(frame.peak) || !amplitude(frame.rms)) return { ok: false, reason: "frame" };
    return { ok: true, kind: "frame", peak: frame.peak, rms: frame.rms };
}

function frameLevel(peak, rms) {
    return Math.min(1, Math.pow(Math.max(peak, rms * RMS_WEIGHT) * LEVEL_GAIN, LEVEL_GAMMA));
}

function modelData(status, setup) {
    var engine = setup && setup.engine ? setup.engine : DEFAULT_ENGINE;
    var model = setup && setup.model ? setup.model : status && status.model ? status.model : DEFAULT_MODEL;
    return { engine: engine, model: model };
}

// The key a person dictates with, from KEYS, shell.shortcut.keys: the hold
// key first, then the toggle key, then the tap key, as { kind, key }, kind
// `hold`, `toggle`, `tap`, or `none` with key null when none is bound.
function readyKey(keys) {
    if (typeof keys.talk === "string") return { kind: "hold", key: keys.talk };
    if (typeof keys.toggle === "string") return { kind: "toggle", key: keys.toggle };
    if (typeof keys.tap === "string") return { kind: "tap", key: keys.tap };
    return { kind: "none", key: null };
}

// The message of the toast a finished Set up shows: readyKey's key, spelled
// for people by SPELL.
function readyMessage(keys, spell) {
    var ready = readyKey(keys);
    if (ready.kind === "hold") return "Hold " + spell(ready.key) + " to dictate.";
    if (ready.kind === "toggle") return "Press " + spell(ready.key) + " to start or stop dictation.";
    if (ready.kind === "tap") return "Tap " + spell(ready.key) + " to start or stop dictation.";
    return "Set a key in Voice settings to dictate.";
}

// Whether SETUP, the `setup` entry of shell.tui.state, holds a run that
// ended with code 0 since SEEN, the endedAt this instance read last. SEEN
// is undefined before the instance's first read, so a run that ended before
// the instance started shows nothing.
function setupFinished(seen, setup) {
    return seen !== undefined && setup.endedAt !== null && setup.endedAt !== seen && setup.code === 0;
}
