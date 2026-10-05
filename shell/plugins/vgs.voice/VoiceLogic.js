.pragma library

var STATES = ["idle", "recording", "transcribing"];
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

function statusState(data) {
    var raw = asString(data.state) || asString(data.alt) || asString(data.class) || asString(data.status);
    return STATES.indexOf(raw) === -1 ? "idle" : raw;
}

function parseStatus(line) {
    var data = parseJson(line, null);
    if (!isObject(data)) return { ok: false, reason: "json" };
    var raw = asString(data.state) || asString(data.alt) || asString(data.class) || asString(data.status) || "idle";
    var state = STATES.indexOf(raw) === -1 ? "idle" : raw;
    var engine = asString(data.engine) || asString(data.backend);
    var model = asString(data.model) || asString(data.model_name) || asString(data.variant);
    return { ok: true, state: state, rawState: raw, unknown: state !== raw, engine: engine, model: model };
}

function listOf(value, keys) {
    if (Array.isArray(value)) return value;
    if (!isObject(value)) return [];
    for (var i = 0; i < keys.length; i++) {
        var item = value[keys[i]];
        if (Array.isArray(item)) return item;
    }
    return [];
}

function field(row, names) {
    if (!isObject(row)) return "";
    for (var i = 0; i < names.length; i++) {
        var value = row[names[i]];
        if (value !== undefined && value !== null) return String(value);
    }
    return "";
}

function affirmative(row, names) {
    if (!isObject(row)) return false;
    for (var i = 0; i < names.length; i++) {
        if (row[names[i]] === true) return true;
        if (typeof row[names[i]] === "string") {
            var text = row[names[i]].toLowerCase();
            if (text === "installed" || text === "present" || text === "ready" || text === "downloaded" || text === "available") return true;
        }
    }
    return false;
}

function modelInstalled(modelsText, wanted) {
    var data = parseJson(modelsText, null);
    var models = listOf(data, ["models", "items", "available"]);
    for (var i = 0; i < models.length; i++) {
        var row = models[i];
        var name = field(row, ["name", "id", "model", "model_name"]);
        if (name === wanted && affirmative(row, ["installed", "downloaded", "present", "ready", "status"])) return true;
    }
    return false;
}

function modelSize(modelsText, wanted) {
    var data = parseJson(modelsText, null);
    var models = listOf(data, ["models", "items", "available"]);
    for (var i = 0; i < models.length; i++) {
        var row = models[i];
        var name = field(row, ["name", "id", "model", "model_name"]);
        if (name === wanted) return field(row, ["size", "size_human", "download_size", "download"]);
    }
    return "";
}

function engineAvailable(enginesText, wanted) {
    var data = parseJson(enginesText, null);
    if (Array.isArray(data)) return engineListHas(data, wanted);
    if (!isObject(data)) return false;
    if (Array.isArray(data.features) && data.features.indexOf(wanted) !== -1) return true;
    if (Array.isArray(data.enabled) && data.enabled.indexOf(wanted) !== -1) return true;
    if (typeof data.active === "string" && data.active === wanted) return true;
    var engines = listOf(data, ["engines", "items", "available"]);
    return engineListHas(engines, wanted);
}

function engineListHas(engines, wanted) {
    for (var i = 0; i < engines.length; i++) {
        var row = engines[i];
        if (typeof row === "string" && row === wanted) return true;
        var name = field(row, ["name", "id", "engine"]);
        if (name === wanted && row.available !== false && row.enabled !== false && row.present !== false) return true;
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
    var installed = modelInstalled(reads.models || "", model);
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
    var engine = status && status.engine ? status.engine : setup && setup.engine ? setup.engine : DEFAULT_ENGINE;
    var model = status && status.model ? status.model : setup && setup.model ? setup.model : DEFAULT_MODEL;
    return { engine: engine, model: model };
}
