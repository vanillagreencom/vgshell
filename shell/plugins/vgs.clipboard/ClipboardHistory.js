.pragma library

// Pure decisions for vgs.clipboard: what a line of the capture helper
// records, how a copy joins the history, what a pin, a removal and a clear
// leave, which image files the history still names, the rows the overlay
// draws for a filter and the key chord a paste sends. QML owns the
// processes and the store; scripts/test-clipboard-history.js runs this file
// under node.
//
// An entry is { id, type, pinned, time } with `id` the SHA-256 of the
// copied bytes as 64 hex digits and `time` the copy's Unix time in seconds.
// A text entry adds `text`; an image entry adds `mime`, and its file in the
// store's image directory is named by its id. The history is a list of
// entries, newest first.

// The entries the history keeps.
var LIMIT = 500;
// The rows the overlay draws for one filter.
var ROWS = 50;
// The characters of one text entry the overlay searches and draws. A paste
// puts the whole entry on the clipboard.
var SHOWN = 8192;
// The type a text entry goes back on the clipboard as.
var TEXT_MIME = "text/plain;charset=utf-8";

var ID = /^[0-9a-f]{64}$/;
var MIME = /^image\/[a-z0-9][a-z0-9.+-]*$/;

function hasOwn(object, key) {
    return object !== null && typeof object === "object" && Object.prototype.hasOwnProperty.call(object, key);
}

// The entry `value` states, with `pinned` read as false unless true, or
// null when it is no entry: a text entry holds text that is not only white
// space, and an image entry names an image type.
function entryOf(value) {
    if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
    if (typeof value.id !== "string" || !ID.test(value.id)) return null;
    if (typeof value.time !== "number" || !isFinite(value.time) || value.time < 0) return null;
    var base = { id: value.id, type: value.type, pinned: value.pinned === true, time: Math.floor(value.time) };
    if (value.type === "text") {
        if (typeof value.text !== "string" || value.text.trim() === "") return null;
        base.text = value.text;
        return base;
    }
    if (value.type === "image") {
        if (typeof value.mime !== "string" || !MIME.test(value.mime)) return null;
        base.mime = value.mime;
        return base;
    }
    return null;
}

// The entry one line of the capture helper records, or null for a line
// that states no entry.
function captured(line) {
    var value;
    try { value = JSON.parse(String(line)); } catch (e) { return null; }
    return entryOf(value);
}

// The history a stored file holds: every entry it states, the first of
// each id, held to the limit. Text that is no history gives none.
function parse(text) {
    var doc;
    try { doc = JSON.parse(String(text)); } catch (e) { return []; }
    if (!hasOwn(doc, "entries") || !Array.isArray(doc.entries)) return [];
    var seen = {}, out = [];
    for (var i = 0; i < doc.entries.length; i++) {
        var entry = entryOf(doc.entries[i]);
        if (entry === null || seen[entry.id] === true) continue;
        seen[entry.id] = true;
        out.push(entry);
    }
    return trimmed(out);
}

function serialize(entries) {
    return JSON.stringify({ version: 1, entries: entries }) + "\n";
}

// `entries` held to the limit: the oldest entry that is not pinned goes
// first, so a pin outlives the limit, and a history of pins alone loses its
// oldest.
function trimmed(entries) {
    var out = entries.slice();
    while (out.length > LIMIT) {
        var drop = out.length - 1;
        for (var i = out.length - 1; i >= 0; i--) {
            if (!out[i].pinned) { drop = i; break; }
        }
        out.splice(drop, 1);
    }
    return out;
}

// The history after a copy of `entry`: the copy is first, and an entry of
// the same bytes is that one entry moved there with its pin kept.
function record(entries, entry) {
    var first = { id: entry.id, type: entry.type, pinned: false, time: entry.time };
    if (entry.type === "text") first.text = entry.text;
    else first.mime = entry.mime;
    var rest = [];
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].id === entry.id) first.pinned = entries[i].pinned;
        else rest.push(entries[i]);
    }
    return trimmed([first].concat(rest));
}

function find(entries, id) {
    for (var i = 0; i < entries.length; i++) if (entries[i].id === id) return entries[i];
    return null;
}

function removed(entries, id) {
    return entries.filter(function (entry) { return entry.id !== id; });
}

// The history after Clear all: the pinned entries.
function cleared(entries) {
    return entries.filter(function (entry) { return entry.pinned; });
}

// The history with the pin of entry `id` turned over.
function repinned(entries, id) {
    return entries.map(function (entry) {
        if (entry.id !== id) return entry;
        var next = {};
        for (var key in entry) next[key] = entry[key];
        next.pinned = !entry.pinned;
        return next;
    });
}

// The image files `entries` name, each by its entry's id.
function files(entries) {
    var out = [];
    for (var i = 0; i < entries.length; i++) if (entries[i].type === "image") out.push(entries[i].id);
    return out;
}

// The members of `names` no entry of `entries` names: files the store may
// delete.
function unused(names, entries) {
    var kept = {};
    files(entries).forEach(function (name) { kept[name] = true; });
    return names.filter(function (name, at) { return kept[name] !== true && names.indexOf(name) === at; });
}

// An image entry's line, such as "PNG image".
function imageLabel(mime) {
    return mime.slice("image/".length).split("+")[0].toUpperCase() + " image";
}

// The rows the overlay draws for `query`: the entries that hold the query,
// compared without case, pinned entries first, then newest first, at most
// ROWS. A text row carries the first SHOWN characters as `text`, which the
// query is looked for in, and those on one line as `label`; an image row
// is found by its label and its type. Each row is
// { id, type, pinned, time, label, text, mime }.
function rows(entries, query) {
    var needle = String(query).trim().toLowerCase();
    var out = [];
    for (var pass = 0; pass < 2 && out.length < ROWS; pass++) {
        for (var i = 0; i < entries.length && out.length < ROWS; i++) {
            var entry = entries[i];
            if (entry.pinned !== (pass === 0)) continue;
            var image = entry.type === "image";
            var shown = image ? "" : entry.text.slice(0, SHOWN);
            var label = image ? imageLabel(entry.mime) : shown.replace(/\s+/g, " ").trim();
            var searched = image ? label + " " + entry.mime : shown;
            if (needle !== "" && searched.toLowerCase().indexOf(needle) === -1) continue;
            out.push({
                id: entry.id, type: entry.type, pinned: entry.pinned, time: entry.time, label: label, text: shown,
                mime: image ? entry.mime : ""
            });
        }
    }
    return out;
}

// The words after `wtype` that send the paste key to the focused window:
// Ctrl+Shift+V for a terminal, which reads Ctrl+V as a control character,
// and Ctrl+V for any other application.
function pasteChord(terminal) {
    return terminal ? ["-M", "ctrl", "-M", "shift", "-k", "v", "-m", "shift", "-m", "ctrl"] : ["-M", "ctrl", "-k", "v", "-m", "ctrl"];
}
