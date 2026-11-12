#!/usr/bin/env node
// What the Agent Warden widget and flyout show,
// shell/plugins/vgs.agent-warden/ViewLogic.js, under node: the icon, tone,
// count and tooltip of every state, the flyout's sentence, rows, meter,
// buttons and check time, the words for a press's reply, and the reading
// of `vsys --once --summary` with the rows the flyout draws from it. The
// details come from vsys's status fixtures through WardenLogic.derive and
// WardenLogic.withCauses, as the service publishes them, and every
// expected value is written out by hand. An item of a kind the plugin
// does not know, with an action it does not know, draws by its level,
// words and actions. No text the view draws for a fixture or a summary
// names a scope unit or a process id of it.
//
// The controls at the end edit a copy of the view one rule at a time and
// require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { load } = require("../bin/lib/qml-library.js");
const modules = { "qs.Commons 1.0": { Duration: load(path.join(__dirname, "..", "shell", "Commons", "Duration.js")) } };

const dir = path.join(__dirname, "..", "shell", "plugins", "vgs.agent-warden");
const fixtures = path.join(__dirname, "smoke", "fixtures", "agent-warden");
const Lucide = load(path.join(__dirname, "..", "shell", "Ui", "icons", "Lucide.js"), modules);
const Tokens = load(path.join(__dirname, "..", "shell", "Commons", "Tokens.js"), modules);
const PluginLogic = load(path.join(__dirname, "..", "shell", "Core", "PluginLogic.js"));
const manifest = JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf8"));
// The view runs in its own context, whose arrays and objects are not this
// one's; values are compared as JSON.
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message === undefined ? JSON.stringify(want) : message);
const fixture = name => JSON.parse(fs.readFileSync(path.join(fixtures, "status-" + name + ".json"), "utf8"));
const edited = (name, edit) => { const doc = fixture(name); edit(doc); return doc; };
const GIB = 1073741824;
const SCOPE = "agent-warden-100-200.scope";

const summary = verdict => JSON.stringify({ schema: "vsys.summary.v2", time: 1, verdict: verdict, meters: [{ id: "cpu", value: null, max: 100, level: "warn" }], errors: [] });
// A `warn` or `danger` cause as vsys writes one, over FIELDS.
const cause = (level, title, fields) => Object.assign({ cause: "memory-high", level: level, subject: null, title: title, processes: [], open: [] }, fields);
const NODE_BASH = [{ pid: 48213, name: "node" }, { pid: 48377, name: "bash" }];
// vsys's memory warning, as it words it (VSY-279): a count, no names.
const HIGH = "1 group is near the memory threshold";
const READONLY = "1 mount is read-only: /home";
// The causes of one summary warning, as readSummary reads it.
const MEMORY = [{ level: "warn", title: HIGH, names: ["node", "bash"], open: [] }];
// Its row.
const MEMORY_ROW = { key: "summary:0", tone: "warning", icon: "shield-alert", title: HIGH + ".", text: "The main programs are node and bash.", actions: [{ label: "Open vsys", args: [] }] };

// The detail the service publishes for DOC, a status document, at SECONDS
// after its time, with CAUSES, a summary's: { doc, detail, now }.
function detailOf(view, doc, seconds, causes) {
    const logic = view.WardenLogic;
    const now = (doc.time + seconds) * 1000;
    const read = logic.readStatus(JSON.stringify(doc));
    assert.equal(read.kind, "read", "the status reads: " + JSON.stringify(read));
    return { doc: doc, detail: logic.withCauses(logic.derive(read, now), causes), now: now };
}

// Every text the view draws for DETAIL at NOW, both vsys answers.
function texts(view, detail, now) {
    const out = [view.tooltip(detail, now), view.widget(detail, now, true).count, view.checked(detail, now), view.summaryClear(detail)];
    for (const missing of [false, true]) {
        out.push(view.sentence(detail, missing));
        const button = view.setup(detail, missing);
        if (button !== null) out.push(button.label);
        const link = view.link(missing, button);
        if (link !== null) out.push(link.label);
    }
    for (const row of view.rows(detail)) out.push(row.title, row.text, ...row.actions.map(a => a.label));
    const meter = view.meter(detail.memory);
    if (meter !== null) out.push(meter.text);
    return out;
}

// Each scope unit and process id fixture DOC carries.
function secrets(doc) {
    const found = [];
    const visit = value => {
        if (Array.isArray(value)) value.forEach(visit);
        else if (value !== null && typeof value === "object")
            for (const [key, inner] of Object.entries(value)) {
                if (key === "scope" && typeof inner === "string") found.push(inner);
                else if (key === "pid" && typeof inner === "number") found.push(String(inner));
                else visit(inner);
            }
    };
    visit(doc);
    return found;
}

const CALM_METER = { value: 38 / 64, text: "Agents use 38 GB and slow down at 64 GB." };
// The rows of the fixtures' items.
const NEAR_ROW = {
    key: "near-limit:" + SCOPE, tone: "warning", icon: "shield-alert", title: "claude in vsy-52 is near its memory and task limits.",
    text: "Memory: 50 of 64 GB; past it the system slows this agent. Tasks: 6200 of 8192 tasks; past it the agent cannot start processes.",
    actions: [{ label: "Show in vsys", args: ["--lane", SCOPE] }, { label: "Stop", args: ["--lane", SCOPE, "--stop"] }]
};
const FULL_ROW = { key: "memory-full", tone: "danger", icon: "shield-x", title: "Agents are close to their memory limit.", text: "73 of 80 GB in use. The warden holds back 1 agent until memory frees.", actions: [{ label: "Show in vsys", args: [] }] };
const LEFTOVER_ROW = { key: "leftover", tone: "info", icon: "shield", title: "Leftover work from 5 finished agents is still running.", text: "5 processes. The warden stops it if it gets busy.", actions: [{ label: "Show in vsys", args: [] }] };
const REAPED_ROW = { key: "reaped", tone: "info", icon: "shield", title: "The warden stopped leftover work from 1 finished agent.", text: "42 processes had become busy.", actions: [] };
// The warden's slowdown item, in vsys's words
// (https://github.com/vanillagreencom/vsys/blob/main/warden/agent-warden, status_items).
const SLOWDOWN = { kind: "slowdown", key: "slowdown", level: "warn", title: "Agents use more memory than the slowdown point.", detail: "73 of 64 GB. The system slows every agent until use falls.", actions: [{ id: "show", label: "Show in vsys", args: [] }] };
// An item of a kind the plugin has no rule for, with an action it has no
// rule for.
const UNKNOWN = { kind: "gpu-hot", key: "gpu-hot:card0", level: "warn", title: "The graphics card is too hot for agents.", detail: null, actions: [{ id: "cool", label: "Cool it down", args: ["--cool", "card0"] }] };

// Fixture states: [label, doc, seconds after its time, summary causes,
// widget, sentence with vsys installed, rows, meter, summary line].
const STATES = [
    ["calm", fixture("calm"), 12, [], { icon: "shield-check", tone: "neutral", count: "1", countLevel: "neutral", tooltip: "1 agent running within its limits" },
        "1 agent is running within its limits.", [], CALM_METER, "vsys found no problems on this computer."],
    ["information only, the owner's case", fixture("leftover-idle"), 0, [], { icon: "shield-check", tone: "neutral", count: "1", countLevel: "neutral", tooltip: "1 agent running within its limits" },
        "1 agent is running within its limits.", [LEFTOVER_ROW], CALM_METER, "vsys found no problems on this computer."],
    ["information without an action", fixture("reaped"), 0, [], { icon: "shield-check", tone: "neutral", count: "1", countLevel: "neutral", tooltip: "1 agent running within its limits" },
        "1 agent is running within its limits.", [REAPED_ROW], CALM_METER, "vsys found no problems on this computer."],
    ["a warning with its actions", fixture("near-limit"), 0, [], { icon: "shield-alert", tone: "warning", count: "1", countLevel: "warning", tooltip: "claude in vsy-52 is near its memory and task limits" },
        "1 warning needs your attention.", [NEAR_ROW], CALM_METER, "vsys found no problems on this computer."],
    ["a calm warden under a summary warning", fixture("calm"), 0, MEMORY, { icon: "shield-alert", tone: "warning", count: "1", countLevel: "warning", tooltip: HIGH },
        "1 warning needs your attention.", [MEMORY_ROW], CALM_METER, ""],
    ["a warning and a summary warning", fixture("near-limit"), 0, MEMORY, { icon: "shield-alert", tone: "warning", count: "2", countLevel: "warning", tooltip: "claude in vsy-52 is near its memory and task limits" },
        "2 warnings need your attention.", [NEAR_ROW, MEMORY_ROW], CALM_METER, ""],
    ["a problem and a summary warning", fixture("holding-off"), 0, MEMORY, { icon: "shield-x", tone: "danger", count: "2", countLevel: "danger", tooltip: "Agents are close to their memory limit" },
        "1 problem and 1 warning need your attention.", [FULL_ROW, MEMORY_ROW], { value: 1, text: "Agents use 73 GB and are slowed down above 64 GB." }, ""],
    // vsys's memory warning and the warden's slowdown both draw, as vsys
    // sends them.
    ["the summary's memory warning beside the warden's slowdown", edited("holding-off", d => { d.items = [SLOWDOWN]; }), 0, MEMORY,
        { icon: "shield-alert", tone: "warning", count: "2", countLevel: "warning", tooltip: "Agents use more memory than the slowdown point" }, "2 warnings need your attention.",
        [{ key: "slowdown", tone: "warning", icon: "shield-alert", title: SLOWDOWN.title, text: SLOWDOWN.detail, actions: [{ label: "Show in vsys", args: [] }] }, MEMORY_ROW],
        { value: 1, text: "Agents use 73 GB and are slowed down above 64 GB." }, ""],
    // A summary problem outranks the warden's warning in the list.
    ["a summary problem over a warning", fixture("near-limit"), 0, [{ level: "danger", title: READONLY, names: [], open: ["--view", "storage"] }],
        { icon: "shield-x", tone: "danger", count: "2", countLevel: "danger", tooltip: READONLY }, "1 problem and 1 warning need your attention.",
        [{ key: "summary:0", tone: "danger", icon: "shield-x", title: READONLY + ".", text: "", actions: [{ label: "Show in vsys", args: ["--view", "storage"] }] }, NEAR_ROW], CALM_METER, ""],
    ["an item the plugin has no rule for", edited("calm", d => { d.schema = "1.9"; d.items = [UNKNOWN]; }), 0, [],
        { icon: "shield-alert", tone: "warning", count: "1", countLevel: "warning", tooltip: "The graphics card is too hot for agents" }, "1 warning needs your attention.",
        [{ key: "gpu-hot:card0", tone: "warning", icon: "shield-alert", title: UNKNOWN.title, text: "", actions: [{ label: "Cool it down", args: ["--cool", "card0"] }] }], CALM_METER, "vsys found no problems on this computer."],
    ["an action vsys's TUI cannot take is not offered", edited("leftover-idle", d => { d.items[0].actions = [{ id: "show", label: "Show in vsys", args: ["--lane", "a\nb"] }, { id: "odd", label: "Odd", args: "--lane" }]; }), 0, [],
        { icon: "shield-check", tone: "neutral", count: "1", countLevel: "neutral", tooltip: "1 agent running within its limits" },
        "1 agent is running within its limits.", [Object.assign({}, LEFTOVER_ROW, { actions: [] })], CALM_METER, "vsys found no problems on this computer."],
    ["a stale status keeps the summary's rows and counts nothing", fixture("calm"), 200, MEMORY, { icon: "shield-off", tone: "neutral", count: "", countLevel: "neutral", tooltip: "Agent Warden hasn't checked in 3m" },
        "Agent Warden has stopped checking.", [MEMORY_ROW], null, ""]
];

// A detail built by hand, over a calm one's fields.
const T = 1700000000000;
const hand = fields => Object.assign({ state: "calm", reason: null, checkedAt: T, agents: 0, items: [], memory: null, causes: null }, fields);

// States without a fixture: [label, detail, widget, sentence with vsys
// installed, sentence without it].
const HAND = [
    ["pending", null, { icon: "shield", tone: "neutral", count: "", countLevel: "neutral", tooltip: "Agent Warden is starting" }, null, null],
    ["calm with no agent", hand({}), { icon: "shield-check", tone: "neutral", count: "", countLevel: "neutral", tooltip: "No agents running" },
        "No agents are running.", "No agents are running."],
    ["calm with unlisted lanes", hand({ agents: null }), { icon: "shield-check", tone: "neutral", count: "", countLevel: "neutral", tooltip: "Agents are within their limits" },
        "Agents are within their limits.", "Agents are within their limits."],
    ["calm with many agents", hand({ agents: 1234 }), { icon: "shield-check", tone: "neutral", count: "1234", countLevel: "neutral", tooltip: "1,234 agents running within their limits" },
        "1,234 agents are running within their limits.", "1,234 agents are running within their limits."],
    // The warden's status cannot be read: the crossed shield and the
    // heading agree it is not checking, and the summary's row still draws.
    ["unreadable", hand({ state: "not-checking", reason: "unreadable", checkedAt: null, agents: null, causes: MEMORY }),
        { icon: "shield-off", tone: "neutral", count: "", countLevel: "neutral", tooltip: "Agent Warden's status can't be read" }, "Agent Warden's status can't be read.", "Agent Warden's status can't be read."],
    ["schema", hand({ state: "not-checking", reason: "schema", checkedAt: null, agents: null }),
        { icon: "shield-off", tone: "neutral", count: "", countLevel: "neutral", tooltip: "Agent Warden's status needs a newer VGS" },
        "Update VGS to read Agent Warden status.", "Update VGS to read Agent Warden status."],
    ["a vsys from before items", hand({ state: "not-checking", reason: "old-vsys", checkedAt: null, agents: null }),
        { icon: "shield-off", tone: "neutral", count: "", countLevel: "neutral", tooltip: "Agent Warden needs a newer vsys" },
        "Agent Warden needs a newer vsys.", "Agent Warden needs a newer vsys."],
    ["not set up", hand({ state: "not-set-up", checkedAt: null, agents: null }), { icon: "shield-question-mark", tone: "neutral", count: "", countLevel: "neutral", tooltip: "Agent Warden isn't set up" },
        "Agent Warden isn't set up.", "Install vsys to set up Agent Warden."]
];

// Buttons: [label, detail, vsys missing, setup button, footer link].
const OPEN = { label: "Open vsys", action: "open" };
const GET = { label: "Install vsys", action: "get-vsys" };
const BUTTONS = [
    ["a checking warden offers only the link", hand({ agents: 1 }), false, null, OPEN],
    ["a checking warden without vsys links to it", hand({ agents: 1 }), true, null, GET],
    ["not set up offers Set up", hand({ state: "not-set-up" }), false, { label: "Set up", action: "setup" }, OPEN],
    ["not set up without vsys offers vsys once", hand({ state: "not-set-up" }), true, GET, null],
    ["a stale warden offers Start checks", hand({ state: "not-checking", reason: "stale" }), false, { label: "Start checks", action: "start" }, OPEN],
    ["an unreadable status offers no setup", hand({ state: "not-checking", reason: "unreadable" }), false, null, OPEN],
    ["a problem offers no setup", hand({ state: "danger" }), false, null, OPEN]
];

// Meters: [label, memory, meter].
const METERS = [
    ["unknown", null, null],
    ["no limit at all", { used: GIB, high: null, max: null }, null],
    ["a hard limit alone", { used: 20 * GIB, high: null, max: 80 * GIB }, { value: 0.25, text: "Agents use 20 GB of their 80 GB limit." }],
    ["past a hard limit alone", { used: 90 * GIB, high: null, max: 80 * GIB }, { value: 1, text: "Agents use 90 GB, past their 80 GB limit." }]
];

// Times: [label, seconds back, words].
const SINCE = [["a fraction", 1.9, "1s"], ["now", 0, "0s"], ["a moment ahead", -30, "0s"], ["seconds", 59, "59s"], ["minutes", 60, "1m"], ["hours", 7200, "2h"], ["days", 86400 * 3, "3d"]];

// Replies: [label, reply, words].
const REPLIES = [
    ["a hand-off", "ok", ""],
    ["a live run of the TUI", "refused: tui=vsys reason=busy", ""],
    ["a live run of vsys at another cause", "refused: tui=vsys reason=busy-other", "vsys is already open in another window. Close it, then try again."],
    ["missing launcher", "refused: tui=setup reason=launcher-missing", "The setup window could not open. VGS is missing its terminal launcher, xdg-terminal-exec. Reinstall VGS to restore it."],
    ["failed launcher", "refused: tui=setup reason=launcher-failed", "VGS could not open this action. Try again."],
    ["vsys already found", "satisfied", "vsys is already installed."],
    ["a full queue", "refused: notices=full limit=8", "Too many install requests are waiting. Try again later."],
    ["anything else, as it came", "refused: argv=empty", "VGS could not open this action. Try again."]
];

// Summaries: [label, text, readSummary answer, the rows of a calm status
// under it]. Each warning or problem is a row of its own.
const SUMMARIES = [
    ["nothing wrong", summary([]), { kind: "read", causes: [] }, []],
    ["a skipped scratch scan", summary([{ cause: "scratch", level: null, subject: null }]), { kind: "read", causes: [] }, []],
    ["a cause at ok carries no card", summary([{ cause: "disk", level: "ok", subject: null }]), { kind: "read", causes: [] }, []],
    ["one warning, its programs by name and its place in vsys", summary([cause("warn", HIGH, { subject: "/agents.slice/agent-confine-48213-1.scope", processes: NODE_BASH, open: ["--lane", "claude-vgs"] })]),
        { kind: "read", causes: [{ level: "warn", title: HIGH, names: ["node", "bash"], open: ["--lane", "claude-vgs"] }] },
        [Object.assign({}, MEMORY_ROW, { actions: [{ label: "Show in vsys", args: ["--lane", "claude-vgs"] }] })]],
    ["a warning without programs", summary([cause("warn", HIGH)]), { kind: "read", causes: [{ level: "warn", title: HIGH, names: [], open: [] }] },
        [Object.assign({}, MEMORY_ROW, { text: "" })]],
    ["a program named twice is named once", summary([cause("warn", HIGH, { processes: [{ pid: 30001, name: "node" }, { pid: 30002, name: "node" }, { pid: 30003, name: "" }] })]),
        { kind: "read", causes: [{ level: "warn", title: HIGH, names: ["node"], open: [] }] }, [Object.assign({}, MEMORY_ROW, { text: "The main program is node." })]],
    ["as many programs as the row names", summary([cause("warn", HIGH, { processes: ["node", "bash", "cargo"].map((name, i) => ({ pid: 100 + i, name: name })) })]),
        { kind: "read", causes: [{ level: "warn", title: HIGH, names: ["node", "bash", "cargo"], open: [] }] },
        [Object.assign({}, MEMORY_ROW, { text: "The main programs are node, bash and cargo." })]],
    ["more programs than the row names", summary([cause("warn", HIGH, { processes: ["node", "bash", "cargo", "rustc", "ld"].map((name, i) => ({ pid: 100 + i, name: name })) })]),
        { kind: "read", causes: [{ level: "warn", title: HIGH, names: ["node", "bash", "cargo", "rustc", "ld"], open: [] }] },
        [Object.assign({}, MEMORY_ROW, { text: "The main programs are node, bash, cargo and 2 others." })]],
    ["a title that ends a sentence keeps its own stop", summary([cause("warn", "Disk is full.")]), { kind: "read", causes: [{ level: "warn", title: "Disk is full.", names: [], open: [] }] },
        [Object.assign({}, MEMORY_ROW, { title: "Disk is full.", text: "" })]],
    ["two warnings are two rows", summary([cause("warn", HIGH, { processes: NODE_BASH }), cause("warn", READONLY, { cause: "brand-new" })]),
        { kind: "read", causes: [{ level: "warn", title: HIGH, names: ["node", "bash"], open: [] }, { level: "warn", title: READONLY, names: [], open: [] }] },
        [MEMORY_ROW, { key: "summary:1", tone: "warning", icon: "shield-alert", title: READONLY + ".", text: "", actions: [{ label: "Open vsys", args: [] }] }]],
    ["a later problem comes first", summary([cause("warn", HIGH, { open: ["--lane", "a"] }), { cause: "scratch", level: null, subject: null }, cause("danger", READONLY, { cause: "read-only", open: ["--view", "storage"] })]),
        { kind: "read", causes: [{ level: "warn", title: HIGH, names: [], open: ["--lane", "a"] }, { level: "danger", title: READONLY, names: [], open: ["--view", "storage"] }] },
        [{ key: "summary:1", tone: "danger", icon: "shield-x", title: READONLY + ".", text: "", actions: [{ label: "Show in vsys", args: ["--view", "storage"] }] },
            { key: "summary:0", tone: "warning", icon: "shield-alert", title: HIGH + ".", text: "", actions: [{ label: "Show in vsys", args: ["--lane", "a"] }] }]],
    ["markup in a title is text", summary([cause("warn", "<b>claude</b> & <i>vgs</i>", { processes: [{ pid: 7, name: "<u>sh</u>" }] })]),
        { kind: "read", causes: [{ level: "warn", title: "<b>claude</b> & <i>vgs</i>", names: ["<u>sh</u>"], open: [] }] },
        [Object.assign({}, MEMORY_ROW, { title: "<b>claude</b> & <i>vgs</i>.", text: "The main program is <u>sh</u>." })]]
];
// The cause of a summary readSummary refuses, at verdict[1] after one that
// reads: [label, cause, the refused field].
const REFUSED = [
    ["a missing title", { cause: "disk", level: "warn", subject: null, processes: [], open: [] }, "title"],
    ["a title that is no string", cause("danger", 3), "title"],
    ["an empty title", cause("warn", ""), "title"],
    ["missing processes", { cause: "disk", level: "warn", subject: null, title: HIGH, open: [] }, "processes"],
    ["processes that are no list", cause("warn", HIGH, { processes: { pid: 1, name: "node" } }), "processes"],
    ["a process with no name", cause("warn", HIGH, { processes: [{ pid: 1 }] }), "processes"],
    ["a process that is a name alone", cause("warn", HIGH, { processes: ["node"] }), "processes"],
    ["a missing open", { cause: "disk", level: "danger", subject: null, title: HIGH, processes: [] }, "open"],
    ["an open that is no list", cause("warn", HIGH, { open: "--lane a" }), "open"],
    ["an open of seventeen arguments", cause("warn", HIGH, { open: Array(17).fill("a") }), "open"],
    ["an empty argument", cause("warn", HIGH, { open: ["--lane", ""] }), "open"],
    ["an argument of 257 characters", cause("warn", HIGH, { open: ["a".repeat(257)] }), "open"],
    ["an argument with a newline", cause("warn", HIGH, { open: ["--lane", "a\nb"] }), "open"],
    ["an argument with a C1 control character", cause("warn", HIGH, { open: ["a\u0085b"] }), "open"],
    ["an argument that is a number", cause("warn", HIGH, { open: ["--lane", 3] }), "open"]
];
// Summaries readSummary refuses: [label, text, answer].
const UNREAD = [
    ["not JSON", "{", { kind: "unreadable", cause: "json" }],
    ["a list", "[]", { kind: "unreadable", cause: "field=root" }],
    ["the previous schema", JSON.stringify({ schema: "vsys.summary.v1", verdict: [] }), { kind: "unreadable", cause: "schema=\"vsys.summary.v1\"" }],
    ["another schema", JSON.stringify({ schema: "vsys.summary.v3", verdict: [] }), { kind: "unreadable", cause: "schema=\"vsys.summary.v3\"" }],
    ["no verdict", JSON.stringify({ schema: "vsys.summary.v2" }), { kind: "unreadable", cause: "field=verdict" }],
    ["a cause that is no object", JSON.stringify({ schema: "vsys.summary.v2", verdict: ["disk"] }), { kind: "unreadable", cause: "field=verdict[0]" }],
    ["an unknown level", JSON.stringify({ schema: "vsys.summary.v2", verdict: [{ cause: "disk", level: "fatal", subject: null }] }), { kind: "unreadable", cause: "field=verdict[0].level" }]
].concat(REFUSED.map(([label, refused, field]) => [label, summary([cause("warn", HIGH), refused]), { kind: "unreadable", cause: "field=verdict[1]." + field }]));
// The arguments an `open` may hold at the edges the core admits.
const ADMITTED_OPEN = [Array(16).fill("a"), ["a".repeat(256)], ["\u{1F600}".repeat(256)], ["$(touch x)", "a b"]];

function verify(view) {
    // Every state and level has a look, every icon is shipped, every state
    // tone is `neutral` or a Theme.color role, every level tone is a
    // Callout state, every level's notice tone is a notify tone or none,
    // the info level's none, and the TUIs the flyout opens are declared.
    same(Object.keys(view.STATE_LOOKS).sort(), JSON.parse(JSON.stringify(view.WardenLogic.STATES)).sort(), "every state has a look");
    for (const look of Object.values(view.STATE_LOOKS).concat([view.PENDING_LOOK])) {
        assert.ok(Object.prototype.hasOwnProperty.call(Lucide.ICONS, look.icon), "icon " + look.icon + " is shipped");
        assert.ok(look.tone === "neutral" || Object.prototype.hasOwnProperty.call(Tokens.TOKENS.color, look.tone), "tone " + look.tone + " is neutral or a colour role");
    }
    same(Object.keys(view.LEVEL_LOOKS).sort(), JSON.parse(JSON.stringify(view.WardenLogic.LEVELS)).sort(), "every level has a look");
    for (const look of Object.values(view.LEVEL_LOOKS)) {
        assert.ok(Object.prototype.hasOwnProperty.call(Lucide.ICONS, look.icon), "icon " + look.icon + " is shipped");
        assert.ok(Object.prototype.hasOwnProperty.call(Tokens.TOKENS.callout.tone, look.tone), "tone " + look.tone + " is a Callout state");
        assert.ok(look.notice === "" || PluginLogic.NOTIFY_TONES.indexOf(look.notice) !== -1, "notice tone " + look.notice + " is a notify tone or none");
    }
    // A calm notice draws its shield in the card's own ink, as the
    // flyout's info row is grey.
    assert.equal(view.LEVEL_LOOKS.info.notice, "", "an info notice names no tone");
    same(Object.keys(manifest.tui).sort(), ["setup", "vsys"], "the flyout's TUIs are declared");
    same(view.START_ARGV, ["systemctl", "--user", "start", "agent-warden.timer"]);
    assert.ok(manifest.requirements.some(r => r.command === view.START_ARGV[0]), "the command Start checks runs is declared");

    for (const [label, doc, seconds, causes, widget, sentence, rows, meter, line] of STATES) {
        const { detail, now } = detailOf(view, doc, seconds, causes);
        same(view.widget(detail, now, true), widget, label + ": widget");
        same(view.widget(detail, now, false).count, "", label + ": no count when it is off");
        assert.equal(view.sentence(detail, false), sentence, label + ": sentence");
        same(view.rows(detail), rows, label + ": rows");
        same(view.meter(detail.memory), meter, label + ": meter");
        assert.equal(view.summaryClear(detail), line, label + ": the summary line");
        assert.equal(view.checked(detail, now), "Checked " + view.ago(doc.time * 1000, now), label + ": check time");
        const drawn = texts(view, detail, now).join("\n");
        for (const secret of secrets(doc)) assert.ok(!drawn.includes(secret), label + ": the view names " + secret);
    }
    assert.equal(view.checked(detailOf(view, fixture("calm"), 12, []).detail, (fixture("calm").time + 12) * 1000), "Checked 12s ago");

    for (const [label, detail, widget, installed, missing] of HAND) {
        same(view.widget(detail, T, true), widget, label + ": widget");
        if (detail === null) continue;
        assert.equal(view.sentence(detail, false), installed, label + ": sentence with vsys");
        assert.equal(view.sentence(detail, true), missing, label + ": sentence without vsys");
        same(view.rows(detail), detail.causes === null ? [] : [MEMORY_ROW], label + ": rows");
    }
    assert.equal(view.checked(hand({ checkedAt: null }), T), "", "no check time before a status told one");
    assert.equal(view.summaryClear(hand({})), "", "no summary line before a summary was read");
    assert.throws(() => view.rows(hand({ items: [Object.assign({}, UNKNOWN, { level: "fatal" })] })), /item level="fatal" unknown/);

    // Idle: nothing needs attention with no agent running, and nothing else.
    assert.equal(view.idle(hand({ agents: 0 })), true);
    assert.equal(view.idle(hand({ state: "info", agents: 0 })), true, "information needs no attention");
    assert.equal(view.idle(hand({ agents: 1 })), false);
    assert.equal(view.idle(hand({ agents: null })), false, "unlisted lanes are not idle");
    assert.equal(view.idle(hand({ state: "warn", agents: 0 })), false);
    assert.equal(view.idle(hand({ state: "not-set-up", agents: null })), false);
    assert.equal(view.idle(null), false);

    for (const [label, detail, missing, button, link] of BUTTONS) {
        const got = view.setup(detail, missing);
        same(got, button, label + ": setup");
        same(view.link(missing, got), link, label + ": link");
    }

    for (const [label, memory, meter] of METERS) same(view.meter(memory), meter, "meter: " + label);
    for (const [label, back, words] of SINCE) assert.equal(view.ago(T - back * 1000, T), words + " ago", "since: " + label);
    for (const [label, reply, words] of REPLIES) {
        assert.equal(view.refusal(reply), words, "reply: " + label);
        assert.equal(view.handedOff(reply), words === "", "hand-off: " + label);
    }
    for (const [label, text, read, rows] of SUMMARIES) {
        const got = view.readSummary(text);
        same(got, read, "summary: " + label);
        const detail = hand({ agents: 1, causes: JSON.parse(JSON.stringify(got.causes)) });
        const drawn = view.rows(detail);
        same(drawn, rows, "summary rows: " + label);
        assert.equal(view.summaryClear(detail), rows.length === 0 ? "vsys found no problems on this computer." : "", "summary line: " + label);
        // A row names no process id and no subject of its summary.
        const words = drawn.map(row => row.title + "\n" + row.text).join("\n");
        for (const c of JSON.parse(text).verdict) {
            for (const p of c.processes || []) assert.ok(!words.includes(String(p.pid)), label + ": a row names process id " + p.pid);
            if (c.subject !== null) assert.ok(!words.includes(c.subject.split("/").pop()), label + ": a row names " + c.subject);
        }
    }
    for (const [label, text, answer] of UNREAD) same(view.readSummary(text), answer, "summary refused: " + label);
    for (const open of ADMITTED_OPEN)
        same(view.readSummary(summary([cause("warn", HIGH, { open: open })])).causes[0].open, open, "an open the core admits is read: " + JSON.stringify(open).slice(0, 40));
}

verify(load(path.join(dir, "ViewLogic.js"), modules));

// Each control removes one rule from a copy of the view and keeps the
// text around it: [label, needle, replacement]. The copy sits beside a
// copy of the logic it imports.
const CONTROLS = [
    ["a missing launcher needs installation repair", "reason=launcher-missing$/", "reason=launcher-missing(?!)$/"],
    ["a busy TUI is a refusal", "reason=busy$/", "reason=nothing$/"],
    ["a busy vsys at another cause reads as generic", "reason=busy-other$/", "reason=busy-other(?!)$/"],
    ["the problem shield draws as a warning", "\"danger\": { icon: \"shield-x\", tone: \"danger\" }", "\"danger\": { icon: \"shield-x\", tone: \"warning\" }"],
    ["information raises the shield", "\"info\": { icon: \"shield-check\", tone: \"neutral\" }", "\"info\": { icon: \"shield-alert\", tone: \"warning\" }"],
    ["the count ignores its setting", "if (!showCount || detail === null)", "if (detail === null)"],
    ["a zero count is drawn", "return n === null || n === 0 ? \"\"", "return n === null ? \"\""],
    ["a calm count takes the accent", "return tone === \"warning\" || tone === \"danger\" ? tone : \"neutral\";", "return tone === \"warning\" || tone === \"danger\" ? tone : \"normal\";"],
    ["the count leaves out the summary's causes", "return detail.items.filter(of).length + causesOf(detail).filter(of).length;", "return detail.items.filter(of).length;"],
    ["the sentence leaves out the problems", "if (problems > 0) counts.push(plural(problems, \"problem\", \"problems\"));", ""],
    ["idle ignores the agents", " && detail.agents === 0", ""],
    ["the link repeats the setup button", "return setupButton !== null && setupButton.action === out.action ? null : out;", "return out;"],
    ["a meter with no limit", "if (limit === null || limit === 0) return null;", ""],
    ["an uncapped meter", "value: Math.min(1, memory.used / limit)", "value: memory.used / limit"],
    ["ages round up", "Math.floor((now - ms) / 1000)", "Math.ceil((now - ms) / 1000)"],
    ["no digit groups", "return String(n).replace(/\\B(?=(\\d{3})+(?!\\d))/g, \",\");", "return String(n);"],
    ["an item's detail is dropped", "text: item.detail === null ? \"\" : item.detail", "text: \"\""],
    ["an item draws its key", "title: item.title,", "title: item.key,"],
    ["an action the vsys TUI refuses is offered", ".filter(function (a) { return openValid(a.args); })", ".filter(function (a) { return true; })"],
    ["the rows ignore the level order", ".sort(function (a, b) { return a.rank - b.rank || a.at - b.at; })", ".sort(function (a, b) { return a.at - b.at; })"],
    ["the clear line stands over causes", "detail.causes !== null && detail.causes.length === 0", "detail.causes !== null"],
    ["any summary schema is read", "if (doc.schema !== SUMMARY_SCHEMA) return", "if (false) return"],
    ["any level is read", "if (cause.level !== null && SUMMARY_LEVELS.indexOf(cause.level) === -1) return", "if (false) return"],
    ["a cause without a title is read", "if (typeof cause.title !== \"string\" || cause.title === \"\") return", "if (false) return"],
    ["a cause without processes is read", "if (!isObject(p) || typeof p.name !== \"string\") return null;", ""],
    ["any open list is read", "if (!Array.isArray(open) || open.length > OPEN_ARGS_MAX) return false;", "if (!Array.isArray(open)) return false;"],
    ["a control character reaches vsys", "&& !OPEN_CONTROL.test(arg)", ""],
    ["a long argument reaches vsys", "Array.from(arg).length <= OPEN_ARG_MAX", "true"],
    ["a row names a program twice", "names.indexOf(p.name) === -1", "true"],
    ["a row names a process id", "names.push(p.name);", "names.push(p.name + \" \" + p.pid);"],
    ["a row names every program", "var names = cause.names.slice(0, MAX_PROGRAMS);", "var names = cause.names.slice();"],
    ["a summary row takes no place in vsys", "args: cause.open.slice() }];", "args: [] }];"],
    ["a summary row with a place reads Open vsys", "cause.open.length === 0 ? \"Open vsys\" : \"Show in vsys\"", "\"Open vsys\""]
];

const sources = { "ViewLogic.js": fs.readFileSync(path.join(dir, "ViewLogic.js"), "utf8"), "WardenLogic.js": fs.readFileSync(path.join(dir, "WardenLogic.js"), "utf8") };
const scratchRoot = os.tmpdir();
fs.mkdirSync(scratchRoot, { recursive: true });
const temp = fs.mkdtempSync(path.join(scratchRoot, "agent-warden-view-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(sources["ViewLogic.js"].split(needle).length, 2, `control "${label}": the text to replace must occur once in ViewLogic.js`);
        for (const [name, text] of Object.entries(sources))
            fs.writeFileSync(path.join(temp, name), name === "ViewLogic.js" ? text.replace(needle, () => replacement) : text);
        let failed = false;
        try {
            verify(load(path.join(temp, "ViewLogic.js"), modules));
        } catch (e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the suite passed on a ViewLogic.js without that rule`);
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
console.log(`test-agent-warden-view: ok states=${STATES.length + HAND.length} buttons=${BUTTONS.length} replies=${REPLIES.length} summaries=${SUMMARIES.length + UNREAD.length} controls=${CONTROLS.length}`);
