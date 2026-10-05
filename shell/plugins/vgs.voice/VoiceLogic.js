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

function setupState(reads) {
    var engine = configValue(reads.engine || "", DEFAULT_ENGINE);
    var model = configValue(reads.model || "", DEFAULT_MODEL);
    var installed = modelInstalled(reads.models || "", engine, model);
    var available = engineAvailable(reads.engines || "", engine);
    var unit = unitEnabled(reads.unit || "");
    var lines = [];
    if (!available) lines.push("The active build cannot use " + engine + ".");
    if (!installed) lines.push("The speech model is missing.");
    if (!unit) lines.push("The service is not enabled.");
    if (lines.length === 0) return { tone: "ok", text: "Ready", action: false, engine: engine, model: model, reasons: [] };
    return { tone: "warning", text: "Set up needed", lines: lines, action: true, engine: engine, model: model, reasons: lines };
}

function modelData(status, setup) {
    var engine = setup && setup.engine ? setup.engine : DEFAULT_ENGINE;
    var model = setup && setup.model ? setup.model : status && status.model ? status.model : DEFAULT_MODEL;
    return { engine: engine, model: model };
}
