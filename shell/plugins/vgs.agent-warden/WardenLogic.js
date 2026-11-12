.pragma library

// The Agent Warden plugin's decisions, pure so scripts/test-agent-warden-logic.js
// runs them under node: whether a warden status file can be read, the
// consumer state it means at a moment, and the plugin status the service
// publishes from that state.
//
// The warden, which vsys ships, writes $XDG_RUNTIME_DIR/agent-warden/status.json
// every tick, numbers and ids only, null for a reading it could not take,
// and from schema 1.3 its `items`: what needs saying, each with its level,
// its words and the vsys arguments that act on it. The contract is
// https://github.com/vanillagreencom/vsys/blob/main/docs/architecture/warden.md.
// The warden judges every state; this file reads its `items` and judges
// none of its own. A minor version adds fields an older reader ignores, so
// this file checks only the fields it reads. A 1.x document before 1.3
// has no `items` and reads as needing a newer vsys. A major version it
// does not know is refused whole.

// The status schema major this plugin reads, and the first minor of it
// that carries `items`.
var SUPPORTED_MAJOR = 1;
var ITEMS_MINOR = 3;
// A status whose `time` is further than this from now, either way, is
// stale: three missed ticks of the warden's default 30 s interval. The far
// side covers a clock set back after the warden wrote.
var STALE_AFTER_MS = 90000;
// The warden's default check interval, which the service's summary runs
// keep while no fresh status sets their pace.
var TICK_MS = 30000;
var GIB = 1073741824;

// The consumer states `derive` answers, in the order the widget ranks them.
// calm, info, warn and danger are a fresh status's: no item, info items
// only, a warn item and no danger item, a danger item.
var STATES = ["calm", "info", "warn", "danger", "not-checking", "not-set-up"];
// Why a status is not checking: too old, unreadable, a major version this
// plugin does not read, or a 1.x status from before `items`.
var NOT_CHECKING_REASONS = ["stale", "unreadable", "schema", "old-vsys"];
// The item levels the contract fixes, most serious first.
var LEVELS = ["danger", "warn", "info"];

function isObject(v) {
    return v !== null && typeof v === "object" && !Array.isArray(v);
}

function isCount(v) {
    return typeof v === "number" && Number.isInteger(v) && v >= 0;
}

function countOrNull(v) {
    return v === null || isCount(v);
}

// A cgroup limit: bytes or tasks, `max` for unlimited, or null unread.
function isLimit(v) {
    return v === "max" || countOrNull(v);
}

function stringOrNull(v) {
    return v === null || typeof v === "string";
}

// The first field of a list whose rows fail `check`, "" when every row
// passes, or the field itself when it is not a list (or null where
// `nullable`).
function listError(doc, key, nullable, check) {
    var list = doc[key];
    if (list === null && nullable) return "";
    if (!Array.isArray(list)) return key;
    for (var i = 0; i < list.length; i++) {
        var at = key + "[" + i + "]";
        if (!isObject(list[i])) return at;
        var field = check(list[i]);
        if (field !== "") return at + "." + field;
    }
    return "";
}

function firstFailing(row, checks) {
    for (var i = 0; i < checks.length; i++)
        if (!checks[i][1](row[checks[i][0]])) return checks[i][0];
    return "";
}

function laneError(lane) {
    if (!isObject(lane.label)) return "label";
    if (!stringOrNull(lane.label.tool)) return "label.tool";
    return firstFailing(lane, [["scope", function (v) { return typeof v === "string"; }]]);
}

function nonEmpty(v) {
    return typeof v === "string" && v !== "";
}

// An action's `args` stay unread here: ViewLogic.openValid judges them
// where they are handed to the vsys TUI.
function actionError(action) {
    return firstFailing(action, [["id", nonEmpty], ["label", nonEmpty]]);
}

function itemError(item) {
    var field = firstFailing(item, [
        ["kind", nonEmpty], ["key", nonEmpty],
        ["level", function (v) { return LEVELS.indexOf(v) !== -1; }],
        ["title", nonEmpty], ["detail", stringOrNull]
    ]);
    if (field !== "") return field;
    return listError(item, "actions", false, actionError);
}

function sliceError(slice) {
    if (slice === null) return "";
    if (!isObject(slice)) return "slice";
    var field = firstFailing(slice, [["memory", countOrNull], ["high", isLimit], ["max", isLimit]]);
    return field === "" ? "" : "slice." + field;
}

// The field of a same-major status document that does not have the type
// the contract gives it, or "" when every field this file reads has.
function shapeError(doc) {
    if (typeof doc.time !== "number" || !isFinite(doc.time)) return "time";
    var checks = [
        function () { return sliceError(doc.slice); },
        function () { return listError(doc, "lanes", true, laneError); },
        function () {
            return listError(doc, "orphans", true, function (o) {
                return firstFailing(o, [["scope", function (v) { return typeof v === "string"; }]]);
            });
        },
        function () { return listError(doc, "items", false, itemError); }
    ];
    for (var i = 0; i < checks.length; i++) {
        var field = checks[i]();
        if (field !== "") return field;
    }
    return "";
}

// One read of status.json as a tagged value:
//   { kind: "read", doc }            a document this plugin reads
//   { kind: "schema", schema }       a major version it does not read
//   { kind: "old-vsys", schema }     a 1.x document from before `items`
//   { kind: "unreadable", cause }    not JSON, or a field of the wrong type;
//                                    `cause` is `json` or `field=<path>`
function readStatus(text) {
    var doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return { kind: "unreadable", cause: "json" };
    }
    if (!isObject(doc)) return { kind: "unreadable", cause: "field=root" };
    var version = typeof doc.schema === "string" ? /^(\d+)\.(\d+)$/.exec(doc.schema) : null;
    if (version === null) return { kind: "unreadable", cause: "field=schema" };
    if (Number(version[1]) !== SUPPORTED_MAJOR) return { kind: "schema", schema: doc.schema };
    if (Number(version[2]) < ITEMS_MINOR) return { kind: "old-vsys", schema: doc.schema };
    var field = shapeError(doc);
    if (field !== "") return { kind: "unreadable", cause: "field=" + field };
    return { kind: "read", doc: doc };
}

function numberOrNull(limit) {
    return typeof limit === "number" ? limit : null;
}

function orphanScopes(doc) {
    return doc.orphans === null ? [] : doc.orphans.map(function (o) { return o.scope; });
}

// The lanes that are running agents: a lane is a scope under agents.slice;
// one whose agent the warden could not identify, or that is leftover work
// from a finished agent, is not one.
function agentLanes(doc) {
    var orphans = orphanScopes(doc);
    return doc.lanes.filter(function (lane) {
        return lane.label.tool !== null && orphans.indexOf(lane.scope) === -1;
    });
}

// The agent group's memory for the flyout's meter, bytes, or null when the
// slice or its use is unknown.
function meterOf(slice) {
    if (slice === null || slice.memory === null) return null;
    return { used: slice.memory, high: numberOrNull(slice.high), max: numberOrNull(slice.max) };
}

// The items of DOC as the plugin keeps them: the fields the contract
// names, in vsys's order, which is level order.
function readItems(doc) {
    return doc.items.map(function (item) {
        return {
            kind: item.kind, key: item.key, level: item.level, title: item.title, detail: item.detail,
            actions: item.actions.map(function (a) { return { id: a.id, label: a.label, args: a.args }; })
        };
    });
}

// The fresh state ITEMS mean: the most serious level among them, calm for
// none.
function stateOf(items) {
    var has = function (level) { return items.some(function (i) { return i.level === level; }); };
    return has("danger") ? "danger" : has("warn") ? "warn" : has("info") ? "info" : "calm";
}

function blank(state, reason) {
    return { state: state, reason: reason, checkedAt: null, agents: null, items: [], memory: null };
}

// The consumer state of FILE, the status read, at NOW milliseconds since
// the epoch, or null while a read is pending. The answer is the `detail`
// the service publishes:
//   { state, reason, checkedAt, agents, items, memory }
// `state` is one of STATES; `reason` one of NOT_CHECKING_REASONS for
// not-checking, else null; `checkedAt` the status's time in milliseconds;
// `agents` the running agents as of that time, null when the warden could
// not list them; `items` readItems'; `memory` meterOf's. A stale status
// keeps its time and agent count and drops its items and meter.
function derive(file, now) {
    switch (file.kind) {
    case "pending": return null;
    case "absent": return blank("not-set-up", null);
    case "unreadable": return blank("not-checking", "unreadable");
    case "schema": return blank("not-checking", "schema");
    case "old-vsys": return blank("not-checking", "old-vsys");
    case "read": break;
    default: throw new Error("agent-warden: file kind=" + JSON.stringify(file.kind) + " unknown");
    }
    var doc = file.doc;
    var checkedAt = Math.round(doc.time * 1000);
    var agents = doc.lanes === null ? null : agentLanes(doc).length;
    if (Math.abs(now - checkedAt) > STALE_AFTER_MS) {
        var stale = blank("not-checking", "stale");
        stale.checkedAt = checkedAt;
        stale.agents = agents;
        return stale;
    }
    var items = readItems(doc);
    return { state: stateOf(items), reason: null, checkedAt: checkedAt, agents: agents, items: items, memory: meterOf(doc.slice) };
}

// DETAIL, derive's answer, with CAUSES, the warn and danger causes of the
// last `vsys --once --summary` (ViewLogic.readSummary's), or null while
// none was read: `causes` holds them, and a fresh state takes the most
// serious level among its items and the causes, so the shield, the
// flyout's heading and its rows count the same things. vsys judges every
// cause; this only ranks the levels it gave. A state that is not fresh
// keeps its own state and still carries the causes.
function withCauses(detail, causes) {
    if (detail === null) return null;
    var out = Object.assign({}, detail, { causes: causes });
    if (causes !== null && ["calm", "info", "warn", "danger"].indexOf(detail.state) !== -1)
        out.state = stateOf(detail.items.concat(causes));
    return out;
}

// The first moment after NOW, in milliseconds since the epoch, at which
// derive's answer for FILE can change while the file does not, or null
// when only a new read can change it. A fresh status turns stale one
// millisecond past STALE_AFTER_MS after its time; a status dated more than
// STALE_AFTER_MS ahead turns fresh once now is that close to its time. A
// status already stale in the past stays so. The service holds one timer
// to this moment and derives again when it fires.
function nextChange(file, now) {
    if (file.kind !== "read") return null;
    var doc = file.doc;
    var checkedAt = Math.round(doc.time * 1000);
    if (now - checkedAt > STALE_AFTER_MS) return null;
    if (checkedAt - now > STALE_AFTER_MS) return checkedAt - STALE_AFTER_MS;
    return checkedAt + STALE_AFTER_MS + 1;
}

// The Settings row for the warden itself, a `state` status value: Running
// while it checks and nothing needs attention, else what is wrong.
function wardenRow(detail) {
    switch (detail.state) {
    case "calm":
    case "info":
        return { tone: "ok", text: "Running" };
    case "warn": return { tone: "warning", text: "Warnings need attention" };
    case "danger": return { tone: "danger", text: "Problems need attention" };
    case "not-checking":
        switch (detail.reason) {
        case "stale": return { tone: "warning", text: "Stopped checking" };
        case "unreadable": return { tone: "danger", text: "Could not read status" };
        case "schema": return { tone: "warning", text: "Update VGS to read this status" };
        case "old-vsys": return { tone: "warning", text: "Needs a newer vsys" };
        }
        throw new Error("agent-warden: reason=" + JSON.stringify(detail.reason) + " unknown");
    case "not-set-up": return { tone: "info", text: "Not set up" };
    }
    throw new Error("agent-warden: state=" + JSON.stringify(detail.state) + " unknown");
}

// The Settings setup step for installing the warden checks. It is open
// only while no warden is set up. With vsys present it offers Set up, the
// setup TUI. With vsys missing it names `action: "tools"`, so the Settings
// page draws Review all missing or outdated tools on the step, the core's
// one install route for vsys, and its hint says vsys comes first.
function setupRow(detail, vsysMissing) {
    switch (detail.state) {
    case "not-set-up":
        var row = { tone: "warning", text: "Not set up" };
        var step = setupStep(detail, vsysMissing);
        if (step === "setup") row.action = true;
        if (step === "get-vsys") {
            row.hint = "Install vsys first. Agent Warden needs it.";
            row.action = "tools";
        }
        return row;
    case "calm":
    case "info":
    case "warn":
    case "danger":
    case "not-checking":
        return { tone: "ok", text: "Done" };
    }
    throw new Error("agent-warden: state=" + JSON.stringify(detail.state) + " unknown");
}

// The one setup step DETAIL calls for, or null for a state that needs
// none: `setup`, the setup TUI, which runs vsys warden install for a warden
// not set up; `start`, the warden timer started again after it
// stopped checking; `get-vsys`, vsys offered through the core's notice,
// first whenever VSYS_MISSING, since every other step needs vsys. The flyout
// and the Settings page offer the same step.
function setupStep(detail, vsysMissing) {
    switch (detail.state) {
    case "not-set-up":
        return vsysMissing ? "get-vsys" : "setup";
    case "not-checking":
        return detail.reason === "stale" ? "start" : null;
    default:
        return null;
    }
}

// The status values the service publishes for DETAIL, derive's answer,
// with MISSING, the plugin's requirement commands the last scan did not
// find: key -> value for each key the manifest declares. `agents` and
// `lastCheck` are left out while no status has told them. The warden row
// stays a reading. The setup row offers Set up while setupStep answers
// `setup`, and Review of the missing tools while it answers `get-vsys`.
// Whether vsys is installed is its requirement's row, never a status
// value.
function published(detail, missing) {
    var vsysMissing = missing.indexOf("vsys") !== -1;
    var setup = setupRow(detail, vsysMissing);
    var out = { warden: wardenRow(detail), setup: setup, detail: detail };
    if (detail.agents !== null) out.agents = detail.agents;
    if (detail.checkedAt !== null) out.lastCheck = detail.checkedAt;
    return out;
}

// BYTES as the number the plugin's copy shows with "GB": gibibytes, one
// decimal below 10 and whole from 10; null for null.
function gib(bytes) {
    if (bytes === null) return null;
    var value = bytes / GIB;
    return value < 10 ? Math.round(value * 10) / 10 : Math.round(value);
}
