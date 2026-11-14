.pragma library

// A number's units: the time units, which a value converts between, and
// `%`, `×`, `/s` and `ms` keep the declared scale.
var TIME_UNITS = ["seconds", "minutes", "hours", "days"];
var UNITS = TIME_UNITS.concat(["%", "×", "/s", "ms"]);
var FORMATS = ["datetime"];
var PROBLEM_TEXT = {
    empty: "Enter a date or time format.",
    multiline: "Use one line.",
    "too-long": "Use at most 64 characters.",
    "unclosed-quote": "Close the quoted text.",
    "no-field": "Use at least one date or time field, such as HH, mm or ddd."
};

// The row labels a plugin's Settings page draws itself, beside its schema
// rows: the one source the page and the manifest judge read, so no field
// of a manifest takes one (PluginLogic.pageRowsError).
var PAGE_LABELS = { enabled: "Enabled", showInBar: "Show in bar", showOnBar: "Show on the bar", moreSettings: "More settings" };

var CONTROL_OR_SEPARATOR = /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/;
var DATETIME_FIELD = /[dMyhHmszaAt]/;

function unitStep(unit) {
    switch (unit) {
    case "seconds": return 1;
    case "minutes": return 60;
    case "hours": return 3600;
    case "days": return 86400;
    }
    throw new Error("SettingValues.quantityText: unit " + JSON.stringify(unit) + " is not one of " + TIME_UNITS.join(", "));
}

function quantityText(value, unit) {
    if (UNITS.indexOf(unit) === -1)
        throw new Error("SettingValues.quantityText: unit " + JSON.stringify(unit) + " is not one of " + UNITS.join(", "));
    if (unit === "%") return String(value) + "%";
    if (unit === "×") return String(value) + "×";
    if (unit === "/s" || unit === "ms") return String(value) + " " + unit;
    var base = unitStep(unit);
    var chosen = unit;
    var shown = value;
    if (value !== 0) {
        for (var i = TIME_UNITS.indexOf(unit) + 1; i < TIME_UNITS.length; i++) {
            var factor = unitStep(TIME_UNITS[i]) / base;
            if (value % factor === 0) {
                chosen = TIME_UNITS[i];
                shown = value / factor;
            }
        }
    }
    var singular = chosen.slice(0, -1);
    return String(shown) + " " + (shown === 1 ? singular : chosen);
}

function datetimeFormatProblem(text) {
    if (text === "") return "empty";
    if (CONTROL_OR_SEPARATOR.test(text)) return "multiline";
    if (text.length > 64) return "too-long";
    var quoted = false;
    var hasField = false;
    for (var i = 0; i < text.length; i++) {
        var ch = text.charAt(i);
        if (ch === "'") {
            if (text.charAt(i + 1) === "'") {
                i += 1;
                continue;
            }
            quoted = !quoted;
            continue;
        }
        if (!quoted && DATETIME_FIELD.test(ch))
            hasField = true;
    }
    if (quoted) return "unclosed-quote";
    return hasField ? "" : "no-field";
}

function presetText(entry, preset, formatDate) {
    if (preset.label !== undefined) return preset.label;
    if (entry.format === "datetime") return formatDate(preset.value);
    if (entry.type === "number" && entry.unit !== undefined) return quantityText(preset.value, entry.unit);
    return String(preset.value);
}

// The rows a select of SPEC's presets offers: each { label, value },
// presetText's label, then Custom… as { label, custom: true } when
// ALLOW_CUSTOM holds. A spec a view's model handed on holds its presets as
// a list Array.isArray refuses (a Repeater's modelData), so the list
// methods are called on it.
function presetRows(spec, allowCustom, formatDate) {
    var out = Array.prototype.map.call(spec.presets, function (preset) { return { label: presetText(spec, preset, formatDate), value: preset.value, custom: false }; });
    if (allowCustom) out.push({ label: "Custom…", custom: true });
    return out;
}

// The index of SPEC's first preset that holds VALUE, or -1.
function presetIndex(spec, value) {
    if (spec.presets === undefined) return -1;
    for (var i = 0; i < spec.presets.length; i++)
        if (spec.presets[i].value === value) return i;
    return -1;
}

// A number field's typed text as the value it writes: NaN for a blank
// text, which the setting's judge refuses as no number.
function typedNumber(text) {
    return text.trim() === "" ? NaN : Number(text);
}

// What each stage's editor says beside its time: `label`, its label while
// no plugin owns it, `owner`, the clause that names what its owner does,
// for a field whose owner is off or absent, and,
// for a stage that offers Immediately (PluginLogic.IDLE_STAGE_WITH),
// `immediately`, the hint while the choice holds, and `snapshot`, the
// dialog that explains it.
var IDLE_STAGE_TEXT = {
    dim: { label: "Dim after", owner: "dims the displays" },
    screensaver: { label: "Start after", owner: "starts a screensaver" },
    lock: {
        label: "Lock after",
        owner: "locks the screen",
        immediately: "Locks when the screensaver starts",
        snapshot: "Immediately sets this time to the screensaver's start time. The lock time does not change when you change the screensaver's time later. Choose Immediately again to use the new time."
    },
    displayOff: { label: "Turn displays off after", owner: "turns the displays off" },
    sleep: { label: "Sleep after", owner: "puts the computer to sleep" }
};

// FIELD's schema entry as its idle time editor offers it
// (PluginLogic.idleSettingFields): while FIELD.immediately holds a time,
// "Immediately (<time>)" holds it, after the presets at 0 and in place of
// a preset of the same time, so it is the choice that reads that time. A
// spec with no presets offers none. Nothing stores the choice: it is the
// time it holds.
function idleTimeSpec(field) {
    var spec = field.spec;
    if (field.immediately <= 0 || spec.presets === undefined) return spec;
    var out = {};
    Object.keys(spec).forEach(function (key) { out[key] = spec[key]; });
    var kept = Array.prototype.filter.call(spec.presets, function (preset) { return preset.value !== field.immediately; });
    var never = kept.filter(function (preset) { return preset.value === 0; });
    var times = kept.filter(function (preset) { return preset.value !== 0; });
    var words = spec.unit === undefined ? String(field.immediately) : quantityText(field.immediately, spec.unit);
    out.presets = never.concat([{ value: field.immediately, label: "Immediately (" + words + ")" }], times);
    return out;
}

// The number of UTF-8 bytes that encode `text`. A lone surrogate counts as
// the three bytes of its replacement character.
function utf8Bytes(text) {
    var bytes = 0;
    for (var i = 0; i < text.length; i++) {
        var code = text.charCodeAt(i);
        if (code < 0x80) bytes += 1;
        else if (code < 0x800) bytes += 2;
        else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) {
            bytes += 4;
            i += 1;
        } else bytes += 3;
    }
    return bytes;
}
