.pragma library
.import qs.Commons 1.0 as Commons
.import "WardenLogic.js" as WardenLogic

// What the Agent Warden widget and flyout show, pure so
// scripts/test-agent-warden-view.js runs it under node: the words, icons and
// tones of the `detail` the service publishes (WardenLogic.derive's answer
// with WardenLogic.withCauses' summary causes), the rows of its items and
// causes, the button each state offers, and the reading of
// `vsys --once --summary`. Every word the user reads is here, save the
// warden's item titles, details and action labels and a summary cause's
// title and program names, which vsys writes and the flyout draws as plain
// text. vsys names no process id or scope unit in them, and a summary row
// draws no process id or subject.

// The icon and tone of each state WardenLogic.STATES names. A tone names
// the Theme.color state role the widget draws in; `neutral` is textMuted.
var STATE_LOOKS = {
    "calm": { icon: "shield-check", tone: "neutral" },
    "info": { icon: "shield-check", tone: "neutral" },
    "warn": { icon: "shield-alert", tone: "warning" },
    "danger": { icon: "shield-x", tone: "danger" },
    "not-checking": { icon: "shield-off", tone: "neutral" },
    "not-set-up": { icon: "shield-question-mark", tone: "neutral" }
};
// The look before the service has derived a state.
var PENDING_LOOK = { icon: "shield", tone: "neutral" };
// The look of each item level WardenLogic.LEVELS names, the shield's icon
// family: the Callout tone and icon a flyout row draws, and the icon,
// notify tone, urgency and transient hint of its notice. A Callout draws
// `info` in neutral shades, but a notification card draws its info tone
// in a hue, so an info notice names no tone and the card draws its shield
// in its own ink, the calm grey.
var LEVEL_LOOKS = {
    "danger": { icon: "shield-x", tone: "danger", notice: "danger", urgency: "critical", transient: false },
    "warn": { icon: "shield-alert", tone: "warning", notice: "warning", urgency: "normal", transient: false },
    "info": { icon: "shield", tone: "info", notice: "", urgency: "low", transient: true }
};
// The argv `start` hands shell.run.detached: the timer an explicit
// `vsys warden install` enables
// (https://github.com/vanillagreencom/vsys/blob/main/docs/architecture/warden.md#the-approach).
var START_ARGV = ["systemctl", "--user", "start", "agent-warden.timer"];
// The summary contract `vsys --once --summary` prints: ids and raw numbers,
// and on each `warn` or `danger` cause the Home card's `title`, the
// `processes` it names as {pid, name} and the vsys arguments `open` that
// open vsys at it
// (https://github.com/vanillagreencom/vsys/blob/main/docs/architecture/verdict.md#rules).
var SUMMARY_SCHEMA = "vsys.summary.v2";
var SUMMARY_LEVELS = ["ok", "warn", "danger"];
// A summary row names at most this many programs of its cause.
var MAX_PROGRAMS = 3;
// The arguments shell.tui.run takes after a script, as the core judges
// them (shell/Core/PluginLogic.js tuiArgsValid, which judges them again at
// the press): at most OPEN_ARGS_MAX strings, each 1 to OPEN_ARG_MAX
// characters with no control character. scripts/test-agent-warden-logic.js
// holds this copy to the core's answers.
var OPEN_ARGS_MAX = 16;
var OPEN_ARG_MAX = 256;
var OPEN_CONTROL = /[\u0000-\u001f\u007f-\u009f]/;

// N with the noun for one or for many: "1 agent", "3 agents".
function plural(n, one, many) {
    return grouped(n) + " " + (n === 1 ? one : many);
}

// N with a comma between each group of three digits: 6,200.
function grouped(n) {
    return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

// A list of names as a sentence reads it: "a", "a and b", "a, b and c".
function listed(names) {
    if (names.length <= 1) return names.join("");
    return names.slice(0, -1).join(", ") + " and " + names[names.length - 1];
}

// BYTES as the plugin writes a memory figure: WardenLogic.gib's number.
function gb(bytes) {
    return String(WardenLogic.gib(bytes));
}

function ago(ms, now) {
    return Commons.Duration.format(Math.max(0, Math.floor((now - ms) / 1000)), 1) + " ago";
}

function levelLook(level) {
    var look = LEVEL_LOOKS[level];
    if (look === undefined) throw new Error("agent-warden: item level=" + JSON.stringify(level) + " unknown");
    return look;
}

// The actions of ITEM the vsys TUI takes, in vsys's order, each
// { label, args }: an action whose `args` openValid refuses is not offered.
function actionsOf(item) {
    return item.actions.filter(function (a) { return openValid(a.args); })
        .map(function (a) { return { label: a.label, args: a.args.slice() }; });
}

// One item of `detail.items` as the flyout's Callout draws it:
// { key, tone, icon, title, text, actions }, ACTIONS actionsOf's, each a
// link under the text.
function calloutRow(item) {
    var look = levelLook(item.level);
    return { key: item.key, tone: look.tone, icon: look.icon, title: item.title, text: item.detail === null ? "" : item.detail, actions: actionsOf(item) };
}

// The summary causes of DETAIL, none before a summary was read.
function causesOf(detail) {
    return detail.causes === null ? [] : detail.causes;
}

// The flyout's rows for DETAIL: every item and every summary cause, in
// level order, danger first, each list keeping vsys's order within a
// level and the warden's items before the summary's causes. Each draws as
// vsys sends it; two that tell of one thing, such as the summary's memory
// warning and the warden's slowdown, both draw.
function rows(detail) {
    var causes = causesOf(detail);
    var all = detail.items.map(calloutRow).concat(summaryRows(causes));
    var levels = detail.items.map(function (i) { return i.level; }).concat(causes.map(function (c) { return c.level; }));
    return all.map(function (row, i) { return { row: row, rank: WardenLogic.LEVELS.indexOf(levels[i]), at: i }; })
        .sort(function (a, b) { return a.rank - b.rank || a.at - b.at; })
        .map(function (r) { return r.row; });
}

// How many items and summary causes of DETAIL are at LEVEL.
function atLevel(detail, level) {
    var of = function (x) { return x.level === level; };
    return detail.items.filter(of).length + causesOf(detail).filter(of).length;
}

// "within its limits" or "within their limits" for N agents.
function running(n) {
    return plural(n, "agent", "agents") + (n === 1 ? " is running within its limits" : " are running within their limits");
}

// The flyout's one status sentence for DETAIL: while the warden is read,
// it counts every warning and problem the flyout lists, the warden's items
// and the summary's causes, as the shield's badge does.
// VSYS_MISSING is whether the last scan did not find vsys, which ships the
// warden.
function sentence(detail, vsysMissing) {
    switch (detail.state) {
    case "calm":
    case "info":
        if (detail.agents === null) return "Agents are within their limits.";
        return detail.agents === 0 ? "No agents are running." : running(detail.agents) + ".";
    case "warn":
    case "danger":
        var problems = atLevel(detail, "danger");
        var warnings = atLevel(detail, "warn");
        var counts = [];
        if (problems > 0) counts.push(plural(problems, "problem", "problems"));
        if (warnings > 0) counts.push(plural(warnings, "warning", "warnings"));
        return listed(counts) + (problems + warnings === 1 ? " needs" : " need") + " your attention.";
    case "not-checking":
        switch (detail.reason) {
        case "stale": return "Agent Warden has stopped checking.";
        case "unreadable": return "Agent Warden's status can't be read.";
        case "schema": return "Update VGS to read Agent Warden status.";
        case "old-vsys": return "Agent Warden needs a newer vsys.";
        }
        throw new Error("agent-warden: reason=" + JSON.stringify(detail.reason) + " unknown");
    case "not-set-up":
        return vsysMissing ? "Install vsys to set up Agent Warden." : "Agent Warden isn't set up.";
    }
    throw new Error("agent-warden: state=" + JSON.stringify(detail.state) + " unknown");
}

// The widget's tooltip for DETAIL at NOW; DETAIL null before the service
// derived a state.
function tooltip(detail, now) {
    if (detail === null) return "Agent Warden is starting";
    switch (detail.state) {
    case "calm":
    case "info":
        if (detail.agents === null) return "Agents are within their limits";
        return detail.agents === 0 ? "No agents running" : plural(detail.agents, "agent", "agents") + " running within " + (detail.agents === 1 ? "its" : "their") + " limits";
    case "warn":
    case "danger":
        return rows(detail)[0].title.replace(/[.]$/, "");
    case "not-checking":
        switch (detail.reason) {
        case "stale": return "Agent Warden hasn't checked in " + Commons.Duration.format(Math.max(0, Math.floor((now - detail.checkedAt) / 1000)), 1);
        case "unreadable": return "Agent Warden's status can't be read";
        case "schema": return "Agent Warden's status needs a newer VGS";
        case "old-vsys": return "Agent Warden needs a newer vsys";
        }
        throw new Error("agent-warden: reason=" + JSON.stringify(detail.reason) + " unknown");
    case "not-set-up": return "Agent Warden isn't set up";
    }
    throw new Error("agent-warden: state=" + JSON.stringify(detail.state) + " unknown");
}

// The count on the shield's corner badge: the running agents while
// nothing needs attention, the warn and danger items and causes while
// something does, and none otherwise, as whole digits, which BarItem caps; "" for none,
// for zero, or when SHOW_COUNT is off.
function count(detail, showCount) {
    if (!showCount || detail === null) return "";
    var n;
    switch (detail.state) {
    case "calm":
    case "info":
        n = detail.agents;
        break;
    case "warn":
    case "danger":
        n = atLevel(detail, "warn") + atLevel(detail, "danger");
        break;
    default:
        n = null;
    }
    return n === null || n === 0 ? "" : String(n);
}

// The badge level of a widget TONE: a warning or danger shield gets a
// badge of its own level; every other shield counts running agents, a
// quantity at rest, in the badge's neutral level, which no theme's accent
// can make read as a warning or problem count.
function countLevel(tone) {
    return tone === "warning" || tone === "danger" ? tone : "neutral";
}

// What the bar widget draws for DETAIL at NOW: { icon, tone, count,
// countLevel, tooltip }.
function widget(detail, now, showCount) {
    var look = detail === null ? PENDING_LOOK : STATE_LOOKS[detail.state];
    if (look === undefined) throw new Error("agent-warden: state=" + JSON.stringify(detail.state) + " unknown");
    return { icon: look.icon, tone: look.tone, count: count(detail, showCount), countLevel: countLevel(look.tone), tooltip: tooltip(detail, now) };
}

// Whether the widget is idle, which `hideWhenIdle` hides: nothing needs
// attention and no agent runs.
function idle(detail) {
    return detail !== null && (detail.state === "calm" || detail.state === "info") && detail.agents === 0;
}

// The one setup button the flyout offers in place of its items for DETAIL,
// { label, action }, or null for a state that needs none: the step
// WardenLogic.setupStep names. An action is `setup`, the setup TUI; `start`,
// START_ARGV; or `get-vsys`, vsys offered through the core's notice; `link`
// adds `open`, the vsys TUI.
function setup(detail, vsysMissing) {
    var step = WardenLogic.setupStep(detail, vsysMissing);
    switch (step) {
    case null: return null;
    case "get-vsys": return { label: "Install vsys", action: "get-vsys" };
    case "setup": return { label: "Set up", action: "setup" };
    case "start": return { label: "Start checks", action: "start" };
    }
    throw new Error("agent-warden: setup step " + JSON.stringify(step) + " unknown");
}

// The flyout's footer link: Open vsys, or Get vsys while the last scan did
// not find it; null when SETUP, setup's answer, already offers the same.
function link(vsysMissing, setupButton) {
    var out = vsysMissing ? { label: "Install vsys", action: "get-vsys" } : { label: "Open vsys", action: "open" };
    return setupButton !== null && setupButton.action === out.action ? null : out;
}

// The footer's time, or "" before a status told one.
function checked(detail, now) {
    return detail.checkedAt === null ? "" : "Checked " + ago(detail.checkedAt, now);
}

// The agent group's memory meter for MEMORY, detail.memory, or null when it
// is unknown or has no limit to measure against: { value, text }, VALUE the
// share of the slowdown point, or of the hard limit without one, at most 1.
function meter(memory) {
    if (memory === null) return null;
    var limit = memory.high !== null ? memory.high : memory.max;
    if (limit === null || limit === 0) return null;
    var used = "Agents use " + gb(memory.used) + " GB";
    var text;
    if (memory.high !== null)
        text = used + (memory.used >= limit ? " and are slowed down above " : " and slow down at ") + gb(limit) + " GB.";
    else
        text = used + (memory.used >= limit ? ", past their " : " of their ") + gb(limit) + " GB limit.";
    return { value: Math.min(1, memory.used / limit), text: text };
}

// The words for a capability's REPLY to a press, "" for one that handed
// off: `ok`, and a TUI's `busy`, whose live window the core focuses.
// A reply this plugin cannot cause, such as an undeclared TUI, is shown
// as it came.
var REFUSALS = [
    [/^ok$/, function () { return ""; }],
    [/^refused: tui=[a-z0-9-]+ reason=busy$/, function () { return ""; }],
    [/^refused: tui=vsys reason=busy-other$/, function () { return "vsys is already open in another window. Close it, then try again."; }],
    [/^refused: tui=[a-z0-9-]+ reason=launcher-missing$/, function () { return "The setup window could not open. VGS is missing its terminal launcher, xdg-terminal-exec. Reinstall VGS to restore it."; }],
    [/^satisfied$/, function () { return "vsys is already installed."; }],
    [/^refused: notices=full limit=\d+$/, function () { return "Too many install requests are waiting. Try again later."; }]
];

function refusal(reply) {
    for (var i = 0; i < REFUSALS.length; i++) {
        var m = REFUSALS[i][0].exec(reply);
        if (m !== null) return REFUSALS[i][1](m);
    }
    return "VGS could not open this action. Try again.";
}

// Whether a press's REPLY handed off, so the flyout closes.
function handedOff(reply) {
    return refusal(reply) === "";
}

function isObject(v) {
    return v !== null && typeof v === "object" && !Array.isArray(v);
}

// Whether OPEN may follow the vsys TUI's script: a list shell.tui.run
// takes, OPEN_ARGS_MAX and OPEN_ARG_MAX above.
function openValid(open) {
    if (!Array.isArray(open) || open.length > OPEN_ARGS_MAX) return false;
    return open.every(function (arg) {
        return typeof arg === "string" && arg.length > 0 && Array.from(arg).length <= OPEN_ARG_MAX && !OPEN_CONTROL.test(arg);
    });
}

// The program names of a cause's PROCESSES, each once in first order, or
// null when the list is not one of {pid, name}. A process id is not kept.
function programNames(processes) {
    if (!Array.isArray(processes)) return null;
    var names = [];
    for (var i = 0; i < processes.length; i++) {
        var p = processes[i];
        if (!isObject(p) || typeof p.name !== "string") return null;
        if (p.name !== "" && names.indexOf(p.name) === -1) names.push(p.name);
    }
    return names;
}

// One `vsys --once --summary` output as a tagged value:
//   { kind: "read", causes }       each `warn` or `danger` cause in verdict
//                                  order, { level, title, names, open }
//   { kind: "unreadable", cause }  `json`, `schema=<value>` or
//                                  `field=<path>`
// A cause at `ok` or with no level, a cause id, a subject or a meter is
// not read; a subject and a process id are never shown. A `warn` or
// `danger` cause without a title, a process list or an `open` the vsys
// TUI takes refuses the whole summary.
function readSummary(text) {
    var doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return { kind: "unreadable", cause: "json" };
    }
    if (!isObject(doc)) return { kind: "unreadable", cause: "field=root" };
    if (doc.schema !== SUMMARY_SCHEMA) return { kind: "unreadable", cause: "schema=" + JSON.stringify(doc.schema) };
    if (!Array.isArray(doc.verdict)) return { kind: "unreadable", cause: "field=verdict" };
    var causes = [];
    for (var i = 0; i < doc.verdict.length; i++) {
        var cause = doc.verdict[i];
        var at = "field=verdict[" + i + "]";
        if (!isObject(cause) || typeof cause.cause !== "string") return { kind: "unreadable", cause: at };
        if (cause.level !== null && SUMMARY_LEVELS.indexOf(cause.level) === -1) return { kind: "unreadable", cause: at + ".level" };
        if (cause.level !== "warn" && cause.level !== "danger") continue;
        if (typeof cause.title !== "string" || cause.title === "") return { kind: "unreadable", cause: at + ".title" };
        var names = programNames(cause.processes);
        if (names === null) return { kind: "unreadable", cause: at + ".processes" };
        if (!openValid(cause.open)) return { kind: "unreadable", cause: at + ".open" };
        causes.push({ level: cause.level, title: cause.title, names: names, open: cause.open.slice() });
    }
    return { kind: "read", causes: causes };
}

// The flyout's rows for SUMMARY's causes, readSummary's `read` answer's,
// in vsys's verdict order, each drawn as an item of its level is
// (calloutRow): vsys's title, one sentence that names its main programs,
// and one action: Show in vsys
// when vsys gives the arguments that open it at the cause, else Open vsys,
// which opens vsys's home as the footer's link does.
function summaryRows(causes) {
    return causes.map(function (cause, i) {
        var look = levelLook(cause.level);
        var title = /[.!?]$/.test(cause.title) ? cause.title : cause.title + ".";
        var text = "";
        if (cause.names.length > 0) {
            var names = cause.names.slice(0, MAX_PROGRAMS);
            if (cause.names.length > MAX_PROGRAMS) names.push(plural(cause.names.length - MAX_PROGRAMS, "other", "others"));
            text = (cause.names.length === 1 ? "The main program is " : "The main programs are ") + listed(names) + ".";
        }
        var actions = [{ label: cause.open.length === 0 ? "Open vsys" : "Show in vsys", args: cause.open.slice() }];
        return { key: "summary:" + i, tone: look.tone, icon: look.icon, title: title, text: text, actions: actions };
    });
}

// The flyout's line when DETAIL's summary causes are none, neutral words
// with no level colour; "" while there are causes, which summaryRows
// draws, or before the summary is read.
function summaryClear(detail) {
    return detail.causes !== null && detail.causes.length === 0 ? "vsys found no problems on this computer." : "";
}
