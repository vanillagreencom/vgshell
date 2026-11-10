.pragma library
.import "Session.js" as Session

// Shell produces hello, intent, indicator, shown, requirements-scan, tui-state, echo-cancel-refresh and reply. Voice confirmation
// is daemon-internal. Daemon produces status/state/devices/echo-cancel/homes/voices/instructions/home-drift/start-text/level/audio-fault,
// request, tasks, task-answer, model-fallback, voice-renewal and transcript. A line excludes its LF.
// A transcript is one speaker's caption segment: partial text grows under
// a rising rev; final closes the segment.
var MAX_LINE_BYTES = 256 * 1024;
var TASK_TERMINALS = ["auto", "tmux", "floating"];
// The manifest's cloudVision options; Policy.recipients judges the same set.
var CLOUD_VISION = ["ask", "allow", "never"];
var MEMORY_NOTES = ["ask", "save"];
var TRANSCRIPT_CHARS = Session.TRANSCRIPT_CHARS;
// The Voice setting's offers, and the lines of the home's instructions as a
// Settings state carries them: PluginLogic's STATUS_LIST_MAX, STATUS_LABEL_MAX
// and STATUS_TEXT_MAX bound each.
var VOICES_MAX = 64;
var INSTRUCTIONS_LINES = 24;
var INSTRUCTIONS_CHARS = 200;
// The readings of a home's package drift (backend/Drift.js KINDS): only
// "behind" offers the update.
var HOME_DRIFT = ["none", "checking", "current", "behind", "drift", "pending", "unknown", "kendex-missing", "malformed", "timeout", "failed"];
// What the status judge refuses in a line: SettingValues.CONTROL_OR_SEPARATOR,
// which PluginLogic.isPrintableLine reads. A plugin's published snapshot
// cannot import a core file, so this is a copy, and
// scripts/test-jarvis-protocol.js holds it equal to the judge's.
var STATUS_UNPRINTABLE = /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/;

// Requests the daemon sends and the service answers, one reply each. `args`
// lists each argument's type, or "argv" for a command; `data` names the
// reply's data shape. `acts` marks a request that changes the desktop,
// which the service refuses while the session is locked.
// Shell.compositor owns each dispatcher's argument rules.
var REQUESTS = {
    "compositor.focusWorkspace": { args: ["text"], data: "none", acts: true },
    "compositor.focusWindow": { args: ["text"], data: "none", acts: true },
    "compositor.moveWindowToWorkspace": { args: ["text", "text"], data: "none", acts: true },
    "compositor.toggleSpecialWorkspace": { args: ["text"], data: "none", acts: true },
    "compositor.closeWindow": { args: ["text"], data: "none", acts: true },
    "compositor.fullscreenWindow": { args: ["text", "text"], data: "none", acts: true },
    "compositor.floatWindow": { args: ["text", "text"], data: "none", acts: true },
    "compositor.moveWindow": { args: ["text", "integer", "integer"], data: "none", acts: true },
    "compositor.resizeWindow": { args: ["text", "integer", "integer"], data: "none", acts: true },
    "compositor.focusMonitor": { args: ["text"], data: "none", acts: true },
    "compositor.moveCursor": { args: ["integer", "integer"], data: "none", acts: true },
    "input.observe": { args: "input-point", data: "input", acts: false },
    "input.keys": { args: "argv", data: "keys", acts: false },
    "compositor.reveal": { args: ["text"], data: "none", acts: true },
    "run.detached": { args: "argv", data: "none", acts: true },
    "desktop.launch": { args: ["text"], data: "entry", acts: true },
    "desktop.list": { args: [], data: "entries", acts: false },
    "tui.run": { args: "task-spec", data: "none", acts: true },
    // The core's dictation recording the local voice takes its final words
    // from (D064). Session admitted the capture that asks for each, so the
    // lock rule for desktop changes does not apply.
    "dictation.start": { args: [], data: "none", acts: false },
    "dictation.stop": { args: [], data: "text", acts: false },
    "dictation.cancel": { args: [], data: "none", acts: false }
};
// Requests awaiting a reply, the plan's bound. The daemon refuses the next.
var MAX_PENDING_REQUESTS = 16;
var TEXT_MAX = 4096;
var ARGV_MAX = 64;
var ANSWER_MAX = 300;
var FIELD_MAX = 128;
var ENTRIES_MAX = 512;
var MEMORY_INBOX_MAX = 64;
var MEMORY_INBOX_BYTES = 128 * 1024;
var MEMORY_TEXT_MAX = 16 * 1024;
var MEMORY_LABELS = ["speech", "desktop", "home", "clipboard", "file", "screen", "web", "command", "agent"];
// Desktop entries stop here, so a list reply stays far below MAX_LINE_BYTES.
var ENTRIES_BYTES = 192 * 1024;
// The package publishes a page, not a complete backlog. Counts remain
// canonical while the console replaces its bounded visible page.
var OWNER_ASK_ROWS = 32;
var OWNER_ASK_BYTES = 16 * 1024;

function instant(value) {
    return typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?(Z|[+-]\d{2}:\d{2})$/.test(value)
        && Number.isFinite(Date.parse(value));
}

function ownerAskRows(rows, view) {
    if (!Array.isArray(rows) || rows.length > OWNER_ASK_ROWS) fail("owner-ask-rows");
    var ids = Object.create(null);
    for (var row of rows) {
        var fields = ["id", "revision", "kind", "what", "askedBy", "askedAt", "link", "threadRef", "state", "snoozedUntil", "actions"];
        if (object(row) && row.statusText !== undefined) fields.push("statusText");
        keys(row, fields, "owner-ask-row");
        if (!printable(row.id, 1, 128) || Object.prototype.hasOwnProperty.call(ids, row.id)
                || !printable(row.revision, 1, 128) || !printable(row.what, 1, 200)
                || ["jarvis-ask", "tracker-item", "fleet-approval"].indexOf(row.kind) === -1
                || !instant(row.askedAt) || !printable(row.threadRef, 1, 200)
                || ["open", "checking", "snoozed"].indexOf(row.state) === -1
                || (view === "snoozed") !== (row.state === "snoozed")
                || (row.state === "snoozed" ? !instant(row.snoozedUntil) : row.snoozedUntil !== null)
                || row.statusText !== undefined && !printable(row.statusText, 0, 200)) fail("owner-ask-row");
        ids[row.id] = true;
        keys(row.askedBy, ["id", "name"], "owner-ask-sender");
        if (!printable(row.askedBy.id, 1, 128) || !printable(row.askedBy.name, 1, 100)) fail("owner-ask-sender");
        keys(row.link, ["label", "url"], "owner-ask-link");
        if (!printable(row.link.label, 1, 100) || !printable(row.link.url, 1, 2048)
                || !/^https?:\/\/[^\s]+$/.test(row.link.url)) fail("owner-ask-link");
        keys(row.actions, ["reply", "done", "later"], "owner-ask-actions");
        for (var action of ["reply", "done", "later"]) {
            var offer = row.actions[action];
            keys(offer, ["allowed", "reason"], "owner-ask-offer");
            if (typeof offer.allowed !== "boolean" || !printable(offer.reason, offer.allowed ? 0 : 1, 200)
                    || offer.allowed && offer.reason !== "") fail("owner-ask-offer");
        }
    }
    return rows;
}

// Both the package reader and the two wire endpoints use these judges.
function ownerAsksPage(page, view, cursor) {
    keys(page, ["v", "homeId", "revision", "observedAt", "activeCount", "snoozedCount", "rows", "nextCursor", "complete"], "owner-asks-page");
    if (page.v !== 1 || !printable(page.homeId, 1, 128) || !printable(page.revision, 1, 128)
            || !instant(page.observedAt) || !Number.isSafeInteger(page.activeCount) || page.activeCount < 0
            || !Number.isSafeInteger(page.snoozedCount) || page.snoozedCount < 0
            || !(page.nextCursor === null || printable(page.nextCursor, 1, 200))
            || typeof page.complete !== "boolean" || page.complete !== (page.nextCursor === null)
            || page.nextCursor !== null && page.nextCursor === cursor
            || bytes(JSON.stringify(page)) > OWNER_ASK_BYTES) fail("owner-asks-page");
    ownerAskRows(page.rows, view);
    var count = view === "active" ? page.activeCount : page.snoozedCount;
    if (page.rows.length > count || !page.complete && page.rows.length === 0
            || cursor === null && page.complete && count !== page.rows.length) fail("owner-asks-count");
    return page;
}

function ownerAskAction(value) {
    keys(value, ["action", "id", "requestId", "expectedRevision", "text", "until"], "owner-ask-action");
    if (["reply", "done", "later"].indexOf(value.action) === -1 || !printable(value.id, 1, 128)
            || !printable(value.requestId, 1, 128) || !printable(value.expectedRevision, 1, 128)
            || typeof value.text !== "string" || value.text.length > 4096
            || /[\x00-\x09\x0b-\x1f\x7f]/.test(value.text)
            || value.action === "reply" && value.text.trim() === ""
            || (value.action === "later" ? !instant(value.until) || value.text !== "" : value.until !== null)) fail("owner-ask-action");
    return value;
}

function ownerAskAnswer(value, action, internal) {
    keys(value, ["v", "requestId", "kind", "state", "cause"], "owner-ask-answer");
    if (value.v !== 1 || !printable(value.requestId, 1, 128) || (internal ? ["accepted", "refused", "unknown", "not-sent"] : ["accepted", "refused"]).indexOf(value.kind) === -1
            || [null, "open", "checking", "snoozed", "closed"].indexOf(value.state) === -1
            || !printable(value.cause, value.kind === "accepted" ? 0 : 1, 200)
            || ["unknown", "not-sent"].indexOf(value.kind) !== -1 && value.state !== null
            || value.kind === "accepted" && (value.cause !== "" || value.state === null
                || action === "done" && value.state !== "checking" || action === "later" && value.state !== "snoozed"
                || action === "reply" && value.state === "closed")) fail("owner-ask-answer");
    return value;
}

function ownerAsksSnapshot(value) {
    if (!object(value)) fail("owner-asks-snapshot");
    if (value.kind === "reading") keys(value, ["kind"], "owner-asks-reading");
    else if (value.kind === "unavailable") {
        keys(value, ["kind", "cause"], "owner-asks-unavailable");
        if (!printable(value.cause, 1, 200)) fail("owner-asks-unavailable");
    } else if (value.kind === "ready") {
        keys(value, ["kind", "homeId", "revision", "observedAt", "activeCount", "snoozedCount", "active", "snoozed",
            "activeCursor", "activeNextCursor", "snoozedCursor", "snoozedNextCursor"], "owner-asks-ready");
        for (var view of ["active", "snoozed"]) {
            if (!(value[view + "Cursor"] === null || printable(value[view + "Cursor"], 1, 200))) fail("owner-asks-cursor");
            ownerAsksPage({ v: 1, homeId: value.homeId, revision: value.revision, observedAt: value.observedAt,
                activeCount: value.activeCount, snoozedCount: value.snoozedCount, rows: value[view],
                nextCursor: value[view + "NextCursor"], complete: value[view + "NextCursor"] === null }, view, value[view + "Cursor"]);
        }
        if (bytes(JSON.stringify(value)) > 2 * OWNER_ASK_BYTES
                || value.active.some(function (active) { return value.snoozed.some(function (snoozed) { return active.id === snoozed.id; }); }))
            fail("owner-asks-snapshot");
    } else fail("owner-asks-kind");
    return value;
}

function fail(reason) {
    throw new Error("jarvis: protocol=" + reason);
}

function object(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function keys(value, wanted, name) {
    if (!object(value) || Object.keys(value).sort().join(",") !== wanted.slice().sort().join(","))
        fail("shape-" + name);
}

// Count UTF-8 bytes in QML too, where Buffer and TextEncoder are absent.
function bytes(text) {
    var count = 0;
    for (var i = 0; i < text.length; i++) {
        var code = text.charCodeAt(i);
        if (code < 0x80) count++;
        else if (code < 0x800) count += 2;
        else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length
                 && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) {
            count += 4;
            i++;
        } else count += 3;
    }
    return count;
}

function bounded(line) {
    if (bytes(line) > MAX_LINE_BYTES) fail("line-too-long");
}

// Both streaming endpoints call this before retaining an unfinished line.
function feed(tail, chunk) {
    var parts = (tail + chunk).split("\n");
    for (var i = 0; i < parts.length; i++) bounded(parts[i]);
    return { lines: parts.slice(0, -1), tail: parts[parts.length - 1] };
}

function directory(value) {
    return typeof value === "string" && value.length > 1 && value[0] === "/" && !/[\x00-\x1f\x7f]/.test(value);
}

// A selected home as the daemon names it on the wire, homes.current and
// home-drift.home alike, which the service compares: "" for none, or a ~/
// path within the bound Home.resolve admits.
function homeIdentity(value) {
    return typeof value === "string" && (value === "" || /^~\/[^\x00-\x1f\x7f]{1,4096}$/.test(value));
}

function text(value) {
    return typeof value === "string" && value.length >= 1 && value.length <= TEXT_MAX && value.indexOf("\u0000") === -1;
}

function printable(value, min, max) {
    return typeof value === "string" && value.length >= min && value.length <= max && !/[\x00-\x1f\x7f]/.test(value);
}

function argv(value) {
    return Array.isArray(value) && value.length >= 1 && value.length <= ARGV_MAX && value.every(text);
}

function requestArgs(kind, args) {
    var rule = REQUESTS[kind].args;
    if (rule === "input-point") return Array.isArray(args) && (args.length === 0 || args.length === 2 && args.every(Number.isSafeInteger));
    if (rule === "task-spec")
        return Array.isArray(args) && args.length === 1 && directory(args[0]);
    if (rule === "argv") return argv(args);
    if (!Array.isArray(args) || args.length !== rule.length) return false;
    for (var i = 0; i < rule.length; i++)
        if (rule[i] === "text" ? !text(args[i]) : !Number.isSafeInteger(args[i])) return false;
    return true;
}

// The wire form of one desktop entry the service read, or null when an
// entry cannot cross: hidden or unnamed by a printable id. A launch reply
// adds `terminal`, since a terminal entry's window carries the terminal's
// class; a list reply omits it.
function desktopEntry(entry, withTerminal) {
    if (entry === null || typeof entry !== "object" || entry.noDisplay === true) return null;
    if (!printable(entry.id, 1, FIELD_MAX)) return null;
    var value = { id: entry.id, name: String(entry.name || "").replace(/[\x00-\x1f\x7f]/g, " ").slice(0, FIELD_MAX),
        startupClass: String(entry.startupClass || "").replace(/[\x00-\x1f\x7f]/g, " ").slice(0, FIELD_MAX) };
    if (withTerminal) value.terminal = entry.terminal === true;
    return value;
}

// The list reply's data from every entry the service read: sorted by id,
// bounded by ENTRIES_MAX and ENTRIES_BYTES; `complete` says none was cut.
function desktopEntries(entries) {
    var values = entries.map(function (entry) { return desktopEntry(entry, false); })
        .filter(function (entry) { return entry !== null; })
        .sort(function (a, b) { return a.id < b.id ? -1 : a.id > b.id ? 1 : 0; });
    var kept = [];
    var size = 0;
    for (var i = 0; i < values.length && kept.length < ENTRIES_MAX; i++) {
        size += bytes(JSON.stringify(values[i])) + 1;
        if (size > ENTRIES_BYTES) break;
        kept.push(values[i]);
    }
    return { entries: kept, complete: kept.length === values.length };
}

// The service's answer to KIND before any capability runs: a keyed refusal
// for a request that changes the desktop while the session is locked, else
// "". Policy judged the lock when the action started; a lock observed since
// stops the requests that remain.
function lockedRefusal(kind, locked) {
    return locked !== false && REQUESTS[kind].acts ? "refused: locked" : "";
}

// A shell call's answer as the reply carries it: one printable line.
function answer(value) {
    var line = String(value).replace(/[\x00-\x1f\x7f]/g, " ").slice(0, ANSWER_MAX);
    return line === "" ? "refused: answer=empty" : line;
}

function entryShape(value, withTerminal) {
    keys(value, withTerminal ? ["id", "name", "startupClass", "terminal"] : ["id", "name", "startupClass"], "entry");
    if (!printable(value.id, 1, FIELD_MAX) || !printable(value.name, 0, FIELD_MAX)
            || !printable(value.startupClass, 0, FIELD_MAX)) fail("entry");
    if (withTerminal && typeof value.terminal !== "boolean") fail("entry");
}

function replyData(message) {
    var shape = REQUESTS[message.kind].data;
    if (shape === "none" || message.answer !== "ok") {
        if (message.data !== null) fail("reply-data");
        return;
    }
    if (shape === "entry") {
        entryShape(message.data, true);
        return;
    }
    // The words voxtype wrote, "" for a recording it heard nothing in.
    if (shape === "text") {
        keys(message.data, ["text"], "dictation-text");
        if (typeof message.data.text !== "string" || message.data.text.length > TEXT_MAX
                || message.data.text.indexOf("\u0000") !== -1) fail("dictation-text");
        return;
    }
    if (shape === "input" || shape === "keys") {
        if (!object(message.data) || message.data.ok !== true) fail("input-reply");
        if (shape === "input") {
            keys(message.data, ["ok", "target", "cursor"], "input");
            var target = message.data.target;
            if (!object(target) || ["application", "terminal", "vgs", "lock", "polkit"].indexOf(target.kind) === -1
                    || !printable(target.id, 1, TEXT_MAX) || !object(message.data.cursor)
                    || !Number.isFinite(message.data.cursor.x) || !Number.isFinite(message.data.cursor.y)) fail("input-reply");
        } else {
            keys(message.data, ["ok", "keys", "translation", "effective"], "resolved-keys");
            if (!Array.isArray(message.data.keys) || message.data.keys.length < 1 || message.data.keys.length > ARGV_MAX
                    || !Array.isArray(message.data.effective) || !Array.isArray(message.data.translation)
                    || message.data.translation.length !== message.data.keys.length) fail("input-reply");
            for (var key of message.data.keys.concat(message.data.translation)) {
                keys(key, ["modifiers", "keycode", "keysym", "codepoint"], "resolved-key");
                if (!Array.isArray(key.modifiers) || !key.modifiers.every(text) || !Number.isSafeInteger(key.keycode)
                        || key.keycode < 8 || !text(key.keysym) || !Number.isSafeInteger(key.codepoint)
                        || key.codepoint < 0 || key.codepoint > 0x10ffff
                        || key.codepoint >= 0xd800 && key.codepoint <= 0xdfff) fail("input-reply");
            }
            if (!message.data.effective.every(text)) fail("input-reply");
        }
        return;
    }
    keys(message.data, ["entries", "complete"], "entries");
    if (!Array.isArray(message.data.entries) || message.data.entries.length > ENTRIES_MAX
            || typeof message.data.complete !== "boolean") fail("reply-data");
    var seen = {};
    for (var entry of message.data.entries) {
        entryShape(entry, false);
        if (Object.prototype.hasOwnProperty.call(seen, entry.id)) fail("entry-duplicate");
        Object.defineProperty(seen, entry.id, { value: true });
    }
}

// Tasks.js's task id rule, judged again on the wire before any record read.
function taskId(value) {
    return typeof value === "string" && /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/.test(value);
}

function approvalId(value) {
    return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value);
}

function hash(value) {
    return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
}

function memoryInboxId(value) {
    return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value);
}

function memoryTarget(value) {
    return typeof value === "string" && /^(?!inbox\/)(?=[^\u0000-\u001f\u007f]{1,255}$)(?:[^./][^/]*\/)*[^./][^/]*\.md$/.test(value);
}

function memoryText(value) {
    return typeof value === "string" && bytes(value) <= MEMORY_TEXT_MAX && value.indexOf("\u0000") === -1;
}

function memoryLabels(value) {
    return Array.isArray(value) && value.length >= 1 && value.length <= MEMORY_LABELS.length
        && value.every(function (label) { return MEMORY_LABELS.indexOf(label) !== -1; })
        && value.filter(function (label, index) { return value.indexOf(label) === index; }).length === value.length;
}

function memoryEntry(value) {
    keys(value, ["id", "target", "kind", "title", "labels", "text", "hash", "problem"], "memory-entry");
    if (!memoryInboxId(value.id) || !memoryTarget(value.target) || ["propose", "replace"].indexOf(value.kind) === -1
            || !printable(value.title, 1, FIELD_MAX) || !memoryLabels(value.labels) || !memoryText(value.text)
            || !hash(value.hash) || !/^(|exists|conflict|link|secret|hash|bootstrap|write)$/.test(value.problem)) fail("memory-entry");
}

function memoryEntryAccepted(value) {
    try {
        memoryEntry(value);
        return true;
    } catch (error) { return false; }
}

function memoryInboxEntries(values) {
    if (!Array.isArray(values)) return [];
    var kept = [];
    var size = 0;
    for (var entry of values) {
        if (!memoryEntryAccepted(entry)) continue;
        var next = bytes(JSON.stringify(entry)) + 1;
        if (kept.length === MEMORY_INBOX_MAX || size + next > MEMORY_INBOX_BYTES) break;
        kept.push(entry);
        size += next;
    }
    return kept;
}

// The engine's failing setup steps (ChainedEngine select): at most one keyed
// cause per step, the home folder, then speech, then brain; none while the
// engine is ready. The home step's cause is the folder's own, `home=`, or
// its text's, `guidance=`.
var SETUP_STEPS = ["home", "speech", "brain"];
var SETUP_CAUSE_STEPS = { home: "home", guidance: "home", speech: "speech", brain: "brain" };
function setupCauses(value) {
    if (!Array.isArray(value)) return false;
    var last = -1;
    for (var i = 0; i < value.length; i++) {
        var match = typeof value[i] === "string" ? /^([a-z]+)=[a-z0-9-]{1,60}$/.exec(value[i]) : null;
        var step = match === null || !Object.prototype.hasOwnProperty.call(SETUP_CAUSE_STEPS, match[1]) ? -1
            : SETUP_STEPS.indexOf(SETUP_CAUSE_STEPS[match[1]]);
        if (step <= last) return false;
        last = step;
    }
    return true;
}
// The home texts over their size budget (Guidance.compose's overBudget):
// cautions, which hold no step, in this order, each at most once.
var SETUP_CAUTIONS = ["guidance=persona-over-budget", "guidance=agents-over-budget", "guidance=skills-over-budget",
    "guidance=memory-over-budget", "guidance=start-over-budget"];
function setupCautions(cautions) {
    if (!Array.isArray(cautions)) return false;
    var last = -1;
    for (var i = 0; i < cautions.length; i++) {
        var at = SETUP_CAUTIONS.indexOf(cautions[i]);
        if (at <= last) return false;
        last = at;
    }
    return true;
}

// The home layers Guidance.compose adds after the shipped ones, in its order;
// the `start-text` message's layers name each at most once, in this order,
// with its estimated tokens.
var HOME_LAYERS = ["home/persona", "home/AGENTS.md", "home/skills", "home/MEMORY.md", "home/state"];
function homeLayerTokens(layers) {
    if (!Array.isArray(layers)) return false;
    var last = -1;
    for (var i = 0; i < layers.length; i++) {
        if (!object(layers[i]) || Object.keys(layers[i]).sort().join(",") !== "layer,tokens") return false;
        var at = HOME_LAYERS.indexOf(layers[i].layer);
        if (at <= last || !Number.isSafeInteger(layers[i].tokens) || layers[i].tokens < 0) return false;
        last = at;
    }
    return true;
}

// Whether VALUE is a line a status value may carry, of 1 to MAX characters.
function statusLine(value, max) {
    return typeof value === "string" && value.length >= 1 && value.length <= max && !STATUS_UNPRINTABLE.test(value);
}

// The Main Jarvis host setting: "" for this computer, else the main's host
// with an optional ":/path" to its home, which the Jarvis package judges;
// the wire holds it to one line of at most 512 characters.
function mainHostSetting(value) {
    return typeof value === "string" && /^[^\x00-\x1f\x7f]{0,512}$/.test(value);
}

// What stops a forward before the main is read (Satellite.js): a block of
// the home's session command (SessionCommand.place), a package older than
// the satellite contract, which lacks its verbs, or one that did not answer
// as expected or names a different main than the setting.
var MAIN_REACH_UNAVAILABLE = ["no-home", "package", "not-set-up", "home-link", "home-kind", "home-unreadable", "package-old", "package-unread", "setting-unhanded"];

// The `main-reach` message's reading of the main Jarvis (Satellite.js),
// with the host Main Jarvis host names, or the package's held main while
// that setting is empty:
// this computer is the main; a satellite whose package names that main,
// whether the package last reached it (null before its first call) and the
// cause the Now line names; or the forward route unavailable and why.
function mainReach(value) {
    if (!object(value)) return false;
    if (value.kind === "main") return Object.keys(value).length === 1;
    if (!mainHostSetting(value.host)) return false;
    if (value.kind === "unavailable")
        return Object.keys(value).sort().join(",") === "cause,host,kind" && MAIN_REACH_UNAVAILABLE.indexOf(value.cause) !== -1;
    return value.kind === "satellite" && Object.keys(value).sort().join(",") === "cause,host,kind,reachable"
        && [true, false, null].indexOf(value.reachable) !== -1 && ["", "main-unreachable", "setting-invalid"].indexOf(value.cause) !== -1;
}

// The `instructions` message's text for TEXT, the whole home AGENTS.md: each
// non-blank line with what the status judge refuses as spaces, cut at a space into
// pieces of at most INSTRUCTIONS_CHARS, the first INSTRUCTIONS_LINES of them;
// `more` says pieces were left out. A text with no such line is "empty".
function instructionsText(text) {
    var pieces = [];
    for (var line of String(text).split("\n")) {
        var rest = line.replace(new RegExp(STATUS_UNPRINTABLE.source, "g"), " ").trim();
        while (rest !== "") {
            var piece = rest.slice(0, INSTRUCTIONS_CHARS);
            if (piece.length < rest.length && piece.lastIndexOf(" ") > 0) piece = piece.slice(0, piece.lastIndexOf(" "));
            pieces.push(piece);
            rest = rest.slice(piece.length).trim();
        }
    }
    if (pieces.length === 0) return { kind: "empty" };
    return { kind: "text", lines: pieces.slice(0, INSTRUCTIONS_LINES), more: pieces.length > INSTRUCTIONS_LINES };
}

// Return the judged message, or throw a keyed protocol error.
function accept(line, direction) {
    if (typeof line !== "string") fail("line-not-string");
    bounded(line);
    var message;
    try { message = JSON.parse(line); } catch (error) { fail("json"); }
    if (!object(message)) fail("object");
    if (message.v !== 1) fail("version");
    if (typeof message.gen !== "number" || !Number.isSafeInteger(message.gen) || message.gen < 0)
        fail("generation");
    if (direction !== "shell" && direction !== "daemon") fail("direction");
    switch (message.type) {
    case "hello":
        if (direction !== "shell") fail("direction-hello");
        keys(message, ["v", "type", "gen", "settings", "directories", "revision", "locked", "keys"], "hello");
        keys(message.settings, ["holdToTalk", "sounds", "microphone", "speaker", "brain", "model", "effort", "fallbacks", "taskTerminal", "cloudVision", "memoryNotes", "privateWindows", "voiceProvider", "voiceAccount", "voice", "clonedVoice", "home", "dictation", "mainHost", "weeklyOpenaiCap"], "settings");
        if (typeof message.settings.weeklyOpenaiCap !== "number" || !Number.isFinite(message.settings.weeklyOpenaiCap)
                || message.settings.weeklyOpenaiCap < 0 || message.settings.weeklyOpenaiCap > 10000) fail("weekly-openai-cap");
        if (!["local", "realtime", "gemini", "elevenlabs"].includes(message.settings.voiceProvider) || typeof message.settings.voiceAccount !== "string"
                || !/^[^\x00-\x1f\x7f]{0,200}$/.test(message.settings.voiceAccount)) fail("voice-settings");
        if (!printable(message.settings.voice, 0, 200)) fail("voice-setting");
        if (typeof message.settings.sounds !== "boolean") fail("sounds");
        if (typeof message.settings.clonedVoice !== "boolean") fail("cloned-voice");
        // The service's cause while the core's dictation recording cannot
        // start (SetupGate.dictationCause), "" while it can.
        if (typeof message.settings.dictation !== "string"
                || !/^(|speech=dictation-[a-z-]{1,40})$/.test(message.settings.dictation)) fail("dictation-setting");
        if (typeof message.settings.brain !== "string") fail("shape-settings");
        // The service's choice for the selected sign-in, each "" for its
        // program's own. A harness brain judges both before its argv.
        if (typeof message.settings.model !== "string" || typeof message.settings.effort !== "string") fail("shape-settings");
        if (!Array.isArray(message.settings.fallbacks)) fail("fallbacks");
        for (var fallback of message.settings.fallbacks) {
            keys(fallback, ["name", "brain", "model"], "fallback");
            if (typeof fallback.name !== "string" || typeof fallback.brain !== "string" || typeof fallback.model !== "string")
                fail("fallbacks");
        }
        if (typeof message.settings.holdToTalk !== "boolean") fail("hold-to-talk");
        if (TASK_TERMINALS.indexOf(message.settings.taskTerminal) === -1) fail("task-terminal");
        if (CLOUD_VISION.indexOf(message.settings.cloudVision) === -1) fail("cloud-vision");
        if (MEMORY_NOTES.indexOf(message.settings.memoryNotes) === -1) fail("memory-notes");
        if (typeof message.settings.privateWindows !== "string"
                || !/^[^\x00-\x1f\x7f]{0,1024}$/.test(message.settings.privateWindows)) fail("private-windows");
        // Home.js judges the folder the text names; the wire bounds the text.
        if (typeof message.settings.home !== "string"
                || !/^[^\x00-\x1f\x7f]{0,4096}$/.test(message.settings.home)) fail("home-setting");
        // The Jarvis package judges the host it names (Satellite.js).
        if (!mainHostSetting(message.settings.mainHost)) fail("main-host-setting");
        for (var setting of ["microphone", "speaker"])
            if (typeof message.settings[setting] !== "string"
                    || !/^[^\x00-\x1f\x7f]{0,200}$/.test(message.settings[setting])) fail("device-setting");
        keys(message.keys, ["talk", "voice-mute", "stop", "confirm", "deny", "console"], "keys");
        for (var shortcut of Object.keys(message.keys)) {
            var key = message.keys[shortcut];
            // The core shortcut provider owns normalization and conflicts.
            if (key !== null && (typeof key !== "string" || key.length === 0))
                fail("key-" + shortcut);
        }
        keys(message.directories, ["state", "data", "runtime"], "directories");
        for (var name of Object.keys(message.directories))
            if (!directory(message.directories[name])) fail("directory-" + name);
        if (typeof message.locked !== "boolean") fail("lock");
        break;
    case "requirements-scan":
        if (direction !== "shell") fail("direction-requirements-scan");
        keys(message, ["v", "type", "gen", "revision", "scan"], "requirements-scan");
        if (!Number.isSafeInteger(message.scan) || message.scan < 0) fail("requirements-scan");
        break;
    case "intent":
        if (direction !== "shell") fail("direction-intent");
        var fields = ["v", "type", "gen", "revision", "intent"];
        if (message.intent === "confirm") {
            keys(message, fields.concat(["id", "digest", "source"]), "confirm");
            if (!approvalId(message.id)) fail("approval-id");
            if (typeof message.digest !== "string" || !/^[0-9a-f]{64}$/.test(message.digest)) fail("approval-digest");
            if (["key", "button"].indexOf(message.source) === -1) fail("approval-source");
        } else if (message.intent === "cancel") {
            keys(message, fields.concat(["id"]), "cancel");
            if (!approvalId(message.id)) fail("approval-id");
        } else if (message.intent === "memory-confirm" || message.intent === "memory-discard") {
            keys(message, fields.concat(["id", "hash"]), "memory-intent");
            if (!memoryInboxId(message.id) || !hash(message.hash)) fail("memory-intent");
        } else if (message.intent === "task-respond") {
            keys(message, fields.concat(["task", "prompt", "answer"]), "task-respond");
            if (!taskId(message.task) || !approvalId(message.prompt)) fail("task-prompt-id");
            var response = message.answer;
            if (!object(response) || response.v !== 1) fail("task-response");
            if (response.kind === "reply") {
                keys(response, ["v", "kind", "text"], "task-response");
                if (typeof response.text !== "string" || response.text.trim() === "" || response.text.length > 4096
                        || /[\x00-\x09\x0b-\x1f\x7f]/.test(response.text)) fail("task-response");
            } else {
                keys(response, ["v", "kind"], "task-response");
                if (["allow", "deny"].indexOf(response.kind) === -1) fail("task-response");
            }
        } else if (message.intent === "task-stop" || message.intent === "task-open") {
            keys(message, fields.concat(["task"]), message.intent);
            if (!taskId(message.task)) fail("task-id");
        } else if (message.intent === "owner-ask-action") {
            keys(message, fields.concat(["request"]), "owner-ask-intent");
            ownerAskAction(message.request);
        } else if (message.intent === "owner-asks-page") {
            keys(message, fields.concat(["view", "cursor", "expectedRevision"]), "owner-asks-page-intent");
            if (["active", "snoozed"].indexOf(message.view) === -1
                    || !(message.cursor === null || printable(message.cursor, 1, 200))
                    || !printable(message.expectedRevision, 1, 128)) fail("owner-asks-page-intent");
        } else if (message.intent === "say") {
            keys(message, fields.concat(["text"]), "say");
            // Typed messages can contain line feeds. Keep every other wire
            // field's single-line contract; this replacement preserves length.
            if (typeof message.text !== "string" || !printable(message.text.replace(/\n/g, " "), 1, TRANSCRIPT_CHARS) || message.text.trim() === "") fail("say-text");
        } else if (message.intent === "preview") {
            // A preview of one offer of the Voice list, beside its speaker
            // button; the engine plays it only if its voice offers it.
            keys(message, fields.concat(["voice"]), "preview");
            if (!printable(message.voice, 1, 128)) fail("preview-voice");
        } else if (message.intent === "main-host") {
            // The setting the user chose, which decides whether an empty
            // Main Jarvis host is handed on (Satellite.choose).
            keys(message, fields.concat(["chosen"]), "main-host-intent");
            if (["mainHost", "home"].indexOf(message.chosen) === -1) fail("main-host-intent");
        } else {
            keys(message, fields, "intent");
            if (["talk-down", "talk-up", "voice-mute", "hide", "show", "stop", "new-conversation", "voice-check", "owner-asks-refresh", "home-drift"].indexOf(message.intent) === -1) fail("intent");
        }
        break;
    case "shown":
        if (direction !== "shell") fail("direction-shown");
        keys(message, ["v", "type", "gen", "revision", "id"], "shown");
        if (!approvalId(message.id)) fail("approval-id");
        break;
    case "request":
        if (direction !== "daemon") fail("direction-request");
        keys(message, ["v", "type", "gen", "revision", "id", "kind", "args"], "request");
        if (!Number.isSafeInteger(message.id) || message.id < 1) fail("request-id");
        if (typeof message.kind !== "string" || !Object.prototype.hasOwnProperty.call(REQUESTS, message.kind))
            fail("request-kind");
        if (!requestArgs(message.kind, message.args)) fail("request-args");
        break;
    case "reply":
        if (direction !== "shell") fail("direction-reply");
        keys(message, ["v", "type", "gen", "revision", "id", "kind", "answer", "data"], "reply");
        if (!Number.isSafeInteger(message.id) || message.id < 1) fail("request-id");
        if (typeof message.kind !== "string" || !Object.prototype.hasOwnProperty.call(REQUESTS, message.kind))
            fail("request-kind");
        if (!printable(message.answer, 1, ANSWER_MAX)) fail("reply-answer");
        replyData(message);
        break;
    // From the shell, a local voice setup run starts (`running` true) or
    // ended; from the daemon, with no field, the answer to a start once the
    // local speech sidecar has exited, so its shared hold on the setup lock
    // is gone (ChainedEngine localSetup).
    case "local-setup":
        if (direction === "shell") {
            keys(message, ["v", "type", "gen", "revision", "running"], "local-setup");
            if (typeof message.running !== "boolean") fail("local-setup-running");
        } else keys(message, ["v", "type", "gen", "revision"], "local-setup");
        break;
    case "tui-state":
        if (direction !== "shell") fail("direction-tui-state");
        keys(message, ["v", "type", "gen", "revision", "name", "running"], "tui-state");
        if (message.name !== "task") fail("tui-name");
        if (typeof message.running !== "boolean") fail("tui-running");
        break;
    case "tasks":
        if (direction !== "daemon") fail("direction-tasks");
        keys(message, ["v", "type", "gen", "revision", "count"], "tasks");
        if (!Number.isSafeInteger(message.count) || message.count < 0) fail("task-count");
        break;
    case "owner-asks":
        if (direction !== "daemon") fail("direction-owner-asks");
        keys(message, ["v", "type", "gen", "revision", "snapshot"], "owner-asks");
        ownerAsksSnapshot(message.snapshot);
        break;
    case "owner-ask-answer":
        if (direction !== "daemon") fail("direction-owner-ask-answer");
        keys(message, ["v", "type", "gen", "revision", "result"], "owner-ask-answer");
        ownerAskAnswer(message.result, null, true);
        break;
    case "main-reach":
        if (direction !== "daemon") fail("direction-main-reach");
        keys(message, ["v", "type", "gen", "revision", "reach"], "main-reach");
        if (!mainReach(message.reach)) fail("main-reach");
        break;
    case "task-list":
        if (direction !== "daemon") fail("direction-task-list");
        keys(message, ["v", "type", "gen", "revision", "rows"], "task-list");
        if (!Array.isArray(message.rows) || message.rows.length > 16) fail("task-list");
        for (var row of message.rows) {
            keys(row, ["id", "goal", "agent", "state", "failure", "createdAt", "endedAt"], "task-row");
            if (!taskId(row.id) || !printable(row.goal, 1, 200) || !printable(row.agent, 1, FIELD_MAX)
                    || ["noisy", "stopped", "lost", "failed", "reported-failed", "reported-ok", "exited", "starting", "waiting", "working"].indexOf(row.state) === -1
                    || !(row.failure === null || printable(row.failure, 1, FIELD_MAX) || Number.isSafeInteger(row.failure) && row.failure !== 0)
                    || !Number.isSafeInteger(row.createdAt) || row.createdAt < 0
                    || !(row.endedAt === null || Number.isSafeInteger(row.endedAt) && row.endedAt >= 0)) fail("task-row");
        }
        break;
    case "audit-failures":
        if (direction !== "daemon") fail("direction-audit-failures");
        keys(message, ["v", "type", "gen", "revision", "rows"], "audit-failures");
        if (!Array.isArray(message.rows) || message.rows.length > 20) fail("audit-failures");
        for (var row of message.rows) {
            // A conversation fault's row: Audit's head word, status and words.
            if (object(row) && row.kind === "fault") {
                keys(row, ["time", "kind", "cause", "status", "category", "action"], "audit-fault");
                if (typeof row.time !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(row.time)
                        || typeof row.cause !== "string" || !/^[a-z-]+=[a-z0-9-]{1,60}$/.test(row.cause)
                        || !(row.status === null || Number.isSafeInteger(row.status) && row.status >= 100 && row.status <= 599)
                        || ["connection", "reply-cut", "service", "app-stopped", "account", "model", "setup", "other"].indexOf(row.category) === -1
                        || ["restarted", "stopped"].indexOf(row.action) === -1) fail("audit-fault");
                continue;
            }
            keys(row, ["time", "tool", "effect", "decision", "outcome", "refusal", "cause"], "audit-row");
            if (typeof row.time !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(row.time)
                    || !printable(row.tool, 1, FIELD_MAX)
                    || !(row.effect === null || ["read", "reversible", "input", "persistent", "exec", "external", "destructive"].indexOf(row.effect) !== -1)
                    || ["allow", "confirm", "refuse", "send", "ask", "withhold"].indexOf(row.decision) === -1
                    || ["pending", "completed", "failed", "unknown", "cancelled"].indexOf(row.outcome) === -1
                    || (["refuse", "withhold"].indexOf(row.decision) === -1 && ["failed", "unknown"].indexOf(row.outcome) === -1)
                    || !(row.refusal === null || ["expired", "no-hold", "identity", "source", "early", "voice-physical", "voice-timing"].indexOf(row.refusal) !== -1)
                    || !(row.cause === null || ["key-refused", "voice-stopped"].indexOf(row.cause) !== -1)) fail("audit-row");
        }
        break;
    case "input-ready":
        if (direction !== "daemon") fail("direction-input-ready");
        keys(message, ["v", "type", "gen", "revision", "commands"], "input-ready");
        if (!Array.isArray(message.commands) || !message.commands.every(command => ["wtype", "wlrctl", "ydotool"].indexOf(command) !== -1)) fail("input-commands");
        break;
    case "shell-status":
        if (direction !== "daemon") fail("direction-shell-status");
        keys(message, ["v", "type", "gen", "revision", "availability"], "shell-status");
        var availability = message.availability;
        if (!object(availability) || ["checking", "available", "unavailable"].indexOf(availability.kind) === -1)
            fail("shell-availability");
        keys(availability, availability.kind === "unavailable" ? ["kind", "reason"] : ["kind"], "shell-availability");
        if (availability.kind === "unavailable" && !printable(availability.reason, 1, FIELD_MAX))
            fail("shell-reason");
        break;
    case "memory":
        if (direction !== "daemon") fail("direction-memory");
        keys(message, ["v", "type", "gen", "revision", "cause"], "memory");
        if (message.cause !== "memory=sqlite") fail("memory-cause");
        break;
    case "memory-inbox":
        if (direction !== "daemon") fail("direction-memory-inbox");
        keys(message, ["v", "type", "gen", "revision", "entries"], "memory-inbox");
        if (!Array.isArray(message.entries) || message.entries.length > MEMORY_INBOX_MAX
                || bytes(JSON.stringify(message.entries)) > MEMORY_INBOX_BYTES) fail("memory-inbox");
        for (var entry of message.entries) memoryEntry(entry);
        break;
    case "task-prompts":
        if (direction !== "daemon") fail("direction-task-prompts");
        keys(message, ["v", "type", "gen", "revision", "prompts"], "task-prompts");
        if (!Array.isArray(message.prompts) || message.prompts.length > 32) fail("task-prompts");
        for (var prompt of message.prompts) {
            keys(prompt, ["v", "id", "task", "kind", "tool", "text", "at", "deadline"], "task-prompt");
            if (prompt.v !== 1 || !taskId(prompt.task) || !approvalId(prompt.id)
                    || ["permission", "question"].indexOf(prompt.kind) === -1
                    || (prompt.kind === "permission" ? typeof prompt.tool !== "string"
                        || !/^[A-Za-z0-9_.:-]{1,128}$/.test(prompt.tool) : prompt.tool !== null)
                    || typeof prompt.text !== "string" || prompt.text.length > 4096
                    || /[\x00-\x09\x0b-\x1f\x7f]/.test(prompt.text)
                    || !Number.isSafeInteger(prompt.at) || !Number.isSafeInteger(prompt.deadline)
                    || prompt.deadline <= prompt.at) fail("task-prompt");
        }
        break;
    case "task-response":
        if (direction !== "daemon") fail("direction-task-response");
        keys(message, ["v", "type", "gen", "revision", "task", "prompt", "answer"], "task-response");
        if (!taskId(message.task) || !approvalId(message.prompt)) fail("task-prompt-id");
        if (typeof message.answer !== "string" || !/^[a-z][a-z-]{0,39}$/.test(message.answer)) fail("task-response");
        break;
    case "task-answer":
        if (direction !== "daemon") fail("direction-task-answer");
        keys(message, ["v", "type", "gen", "revision", "task", "answer"], "task-answer");
        if (!taskId(message.task)) fail("answer-task-id");
        if (typeof message.answer !== "string" || !/^[a-z][a-z-]{0,39}$/.test(message.answer)) fail("task-answer");
        break;
    case "task-open":
        if (direction !== "daemon") fail("direction-task-open");
        keys(message, ["v", "type", "gen", "revision", "task", "answer"], "task-open");
        if (!taskId(message.task)) fail("open-task-id");
        if (typeof message.answer !== "string" || !/^[a-z][a-z-]{0,39}$/.test(message.answer)) fail("task-open");
        break;
    case "indicator":
        if (direction !== "shell") fail("direction-indicator");
        keys(message, ["v", "type", "gen", "revision", "shown", "bar"], "indicator");
        if (typeof message.shown !== "boolean") fail("indicator");
        if (["gone", "present", "listening"].indexOf(message.bar) === -1) fail("bar-indicator");
        break;
    case "model-fallback":
        if (direction !== "daemon") fail("direction-model-fallback");
        keys(message, ["v", "type", "gen", "revision", "saved", "used"], "model-fallback");
        if (typeof message.saved !== "string" || message.saved === "" || typeof message.used !== "string") fail("model-fallback");
        break;
    case "status":
        if (direction !== "daemon") fail("direction-status");
        keys(message, ["v", "type", "gen", "revision", "daemon", "causes", "cautions"], "status");
        if (message.daemon !== "ready" && message.daemon !== "locked") fail("daemon");
        if (!setupCauses(message.causes)) fail("causes");
        if (!setupCautions(message.cautions)) fail("cautions");
        break;
    case "state":
        if (direction !== "daemon") fail("direction-state");
        keys(message, ["v", "type", "gen", "revision", "seq", "state", "phase", "brain"], "state");
        if (!Number.isSafeInteger(message.seq) || message.seq < 1) fail("sequence");
        if (!Session.validate(message.state)) fail("state");
        if (message.state.gen !== message.gen) fail("state-generation");
        if (message.phase !== Session.phaseOf(message.state)) fail("phase");
        if (typeof message.brain !== "string" || /[\x00-\x1f\x7f]/.test(message.brain) || message.brain.length > 180) fail("brain");
        break;
    case "devices":
        if (direction !== "daemon") fail("direction-devices");
        keys(message, ["v", "type", "gen", "revision", "microphones", "speakers"], "devices");
        for (var group of ["microphones", "speakers"]) {
            var values = message[group];
            if (!Array.isArray(values) || values.length > 32) fail("choices");
            var seen = {};
            for (var choice of values) {
                keys(choice, ["label", "value"], "choice");
                if (typeof choice.label !== "string" || !/^[^\x00-\x1f\x7f]{1,60}$/.test(choice.label)
                        || typeof choice.value !== "string" || !/^[^\x00-\x1f\x7f]{1,200}$/.test(choice.value))
                    fail("choice");
                if (Object.prototype.hasOwnProperty.call(seen, choice.value)) fail("choice-duplicate");
                Object.defineProperty(seen, choice.value, { value: true });
            }
        }
        break;
    case "echo-cancel":
        if (direction !== "daemon") fail("direction-echo-cancel");
        keys(message, ["v", "type", "gen", "revision", "state", "path", "reason"], "echo-cancel");
        if (["absent", "foreign", "unavailable", "pending", "active"].indexOf(message.state) === -1
                || !(message.path === "" && message.state === "unavailable"
                    || directory(message.path) && message.path.length <= 4096)
                || typeof message.reason !== "string"
                || (message.state === "active" ? message.reason !== "" : !/^[a-z][a-z-]{0,59}$/.test(message.reason)))
            fail("echo-cancel");
        break;
    case "echo-cancel-refresh":
        if (direction !== "shell") fail("direction-echo-cancel-refresh");
        keys(message, ["v", "type", "gen", "revision"], "echo-cancel-refresh");
        break;
    case "homes":
        if (direction !== "daemon") fail("direction-homes");
        keys(message, ["v", "type", "gen", "revision", "homes", "current"], "homes");
        if (!homeIdentity(message.current)) fail("home-current");
        var values = message.homes;
        if (!Array.isArray(values) || values.length > 10) fail("home-choices");
        var seen = {};
        for (var choice of values) {
            keys(choice, ["id", "label", "value"], "home-choice");
            // Home.js uses a stable path hash, a subset of MENU_ID_PATTERN.
            if (typeof choice.id !== "string" || !/^h[0-9a-f]{12}$/.test(choice.id)) fail("home-id");
            // Mirrors PluginLogic status choice caps: STATUS_LABEL_MAX and STATUS_TEXT_MAX.
            if (typeof choice.label !== "string" || !/^[^\x00-\x1f\x7f]{1,60}$/.test(choice.label)
                    || typeof choice.value !== "string" || !/^~\/[^\x00-\x1f\x7f]{1,200}$/.test(choice.value))
                fail("home-choice");
            if (Object.prototype.hasOwnProperty.call(seen, choice.value)) fail("home-duplicate");
            Object.defineProperty(seen, choice.value, { value: true });
            if (Object.prototype.hasOwnProperty.call(seen, choice.id)) fail("home-id-duplicate");
            Object.defineProperty(seen, choice.id, { value: true });
        }
        break;
    case "voices":
        if (direction !== "daemon") fail("direction-voices");
        keys(message, ["v", "type", "gen", "revision", "voices"], "voices");
        if (!Array.isArray(message.voices) || message.voices.length > VOICES_MAX) fail("voices");
        var voiced = {};
        for (var voice of message.voices) {
            keys(voice, ["label", "value"], "voice");
            if (!statusLine(voice.label, 60) || !statusLine(voice.value, 200)) fail("voice");
            if (Object.prototype.hasOwnProperty.call(voiced, voice.value)) fail("voice-duplicate");
            Object.defineProperty(voiced, voice.value, { value: true });
        }
        break;
    case "instructions":
        if (direction !== "daemon") fail("direction-instructions");
        keys(message, ["v", "type", "gen", "revision", "instructions"], "instructions");
        var shown = message.instructions;
        if (!object(shown)) fail("instructions");
        if (shown.kind === "text") {
            keys(shown, ["kind", "lines", "more"], "instructions");
            if (!Array.isArray(shown.lines) || shown.lines.length < 1 || shown.lines.length > INSTRUCTIONS_LINES
                    || !shown.lines.every(line => statusLine(line, INSTRUCTIONS_CHARS)) || typeof shown.more !== "boolean")
                fail("instructions-lines");
        } else {
            keys(shown, ["kind"], "instructions");
            if (["none", "empty", "unreadable"].indexOf(shown.kind) === -1) fail("instructions-kind");
        }
        break;
    case "home-drift":
        // The package drift reading of HOME, the selected home as ~/path,
        // or "" for none, which the service binds to its own home setting.
        if (direction !== "daemon") fail("direction-home-drift");
        keys(message, ["v", "type", "gen", "revision", "home", "drift"], "home-drift");
        if (!homeIdentity(message.home)) fail("home-drift-home");
        keys(message.drift, ["kind"], "home-drift");
        if (HOME_DRIFT.indexOf(message.drift.kind) === -1) fail("home-drift-kind");
        break;
    case "start-text":
        if (direction !== "daemon") fail("direction-start-text");
        keys(message, ["v", "type", "gen", "revision", "size"], "start-text");
        var size = message.size;
        if (!object(size)) fail("start-text");
        if (size.kind === "read") {
            keys(size, ["kind", "tokens", "layers"], "start-text");
            if (!Number.isSafeInteger(size.tokens) || size.tokens < 0 || !homeLayerTokens(size.layers)) fail("start-text-tokens");
        } else {
            keys(size, ["kind"], "start-text");
            if (size.kind !== "unreadable") fail("start-text-kind");
        }
        break;
    case "level":
        if (direction !== "daemon") fail("direction-level");
        keys(message, ["v", "type", "gen", "revision", "level"], "level");
        keys(message.level, ["capture", "playback"], "levels");
        for (var channel of ["capture", "playback"])
            if (!Number.isFinite(message.level[channel]) || message.level[channel] < 0 || message.level[channel] > 1) fail("level");
        break;
    case "audio-fault":
        if (direction !== "daemon") fail("direction-audio-fault");
        keys(message, ["v", "type", "gen", "revision", "reason"], "audio-fault");
        if (typeof message.reason !== "string" || !/^[^\x00-\x1f\x7f]{1,180}$/.test(message.reason))
            fail("audio-fault");
        break;
    case "voice-renewal":
        if (direction !== "daemon") fail("direction-voice-renewal");
        keys(message, ["v", "type", "gen", "revision"], "voice-renewal");
        break;
    case "transcript":
        if (direction !== "daemon") fail("direction-transcript");
        keys(message, ["v", "type", "gen", "revision", "role", "text", "stage", "rev"], "transcript");
        if (message.role !== "user" && message.role !== "assistant") fail("transcript-role");
        if (message.stage !== "partial" && message.stage !== "final") fail("transcript-stage");
        if (typeof message.text !== "string" || message.text.length === 0 || message.text.length > TRANSCRIPT_CHARS
                || /[\x00-\x1f\x7f]/.test(message.text)) fail("transcript-text");
        if (!Number.isSafeInteger(message.rev) || message.rev < 1) fail("transcript-rev");
        break;
    default:
        fail("type");
    }
    if (typeof message.revision !== "string" || !/^[0-9a-f]{64}$/.test(message.revision)) fail("revision");
    return message;
}
