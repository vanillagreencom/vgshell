.pragma library

// The one rule for when a plugin page shows a setup step (D061), pure so
// scripts/test-settings-steps.js runs it under node: a step's button shows
// only while its value offers it: a `presence` while `absent` and a `state`
// while it carries `action: true` or names one of its entry's actions, so a
// failing state its writer gives no action shows none. The core decides when
// a step applies (PluginLogic.statusActionOffered, SECRET_ACCESS,
// requirementRows); this file decides what the page then draws.

// What the line of ENTRY, one row of PluginLogic.statusRows, draws of its
// step: { offered }, whether the action's button shows.
function statusStep(entry) {
    var offered = entry.action !== null && entry.action.offered;
    return { offered: offered };
}

// Whether the Requirements section's install step applies to REQUIREMENT,
// one row of PluginLogic.requirementRows: while its requirement is missing.
function requirementApplies(requirement) {
    return requirement.state === "missing";
}

// The words a `presence` value reads as on the page.
var PRESENCE_WORDS = { present: "Present", absent: "Absent", locked: "Locked", unavailable: "Unavailable", unsafe: "Unsafe" };

// What a page draws of ENTRY, one row of PluginLogic.statusRows, or null
// for a row whose entry left the manager row: { label, hint, info,
// offered, tone, text, lines, muted, items }, `offered` its step's
// (statusStep), `tone` "" for a value drawn as text, `lines` a state's
// further lines and `items` a presence list's items with the `key` each
// keeps across writes (itemsKeyed). TIME_TEXT spells a `time` value for
// people. An entry the plugin has not published reads "Not reported".
function statusView(entry, timeText) {
    if (entry === null) return { label: "", hint: "", info: "", offered: false, tone: "", text: "", lines: [], muted: true, items: [] };
    var out = { label: entry.label, hint: entry.hint, info: entry.info, offered: statusStep(entry).offered, tone: "", text: "Not reported", lines: [], muted: true, items: [] };
    if (entry.report !== "reported") return out;
    out.muted = false;
    out.tone = entry.tone;
    switch (entry.type) {
    case "presence": out.text = PRESENCE_WORDS[entry.value]; return out;
    case "presenceList":
        out.items = itemsKeyed(entry.value);
        out.text = entry.value.length === 0 ? "None detected" : "";
        out.muted = true;
        return out;
    case "state":
        out.text = entry.value.text;
        if (entry.value.lines !== undefined) out.lines = entry.value.lines;
        return out;
    case "text": out.text = entry.value; return out;
    case "count": out.text = String(entry.value); return out;
    case "time": out.text = timeText(entry.value); return out;
    }
    console.error("Steps: no rule for status type " + JSON.stringify(entry.type));
    out.text = "";
    return out;
}

// ITEMS, a presence list's, each with the `key` a line keeps across
// writes, so a status write elsewhere, which hands the page new objects,
// keeps each line's delegate, an open Connect field and what it holds with
// it: its secret's account, else its label, with its count among earlier
// equal names after a second one.
function itemsKeyed(items) {
    var seen = Object.create(null);
    return items.map(function (item) {
        var name = item.secret !== "" ? "secret " + item.secret : "label " + item.label;
        seen[name] = (seen[name] || 0) + 1;
        return Object.assign({ key: seen[name] === 1 ? name : name + " " + seen[name] }, item);
    });
}

// The status group a page draws at the top of its Setup section, with the
// setup buttons under it, so the state a setup step changes reads beside
// the step.
var SETUP_GROUP = "Setup";

// The entries of STATUS, a manager row's status rows, in SETUP_GROUP.
function setupEntries(status) {
    return status.filter(function (entry) { return entry.group === SETUP_GROUP; });
}

// The Setup section's buttons for TUIS, a manager row's listed TUIs
// (PluginLogic.listedTuiRows), and STATUS, its status rows, in drawn order:
// first each TUI an offered action opens (a row's action names a TUI only
// while it is offered), in status order, as that step, primary, with the
// action's label; then every other TUI in manifest order, secondary, with
// its entry's label. A secondary button whose TUI lacks a requirement takes
// no press and reads the core's reason, the TUI's `withheld`: its press
// would only raise the notice the step installs from. Each { key, name,
// label, icon, primary, enabled, reason }, `key` naming the button as
// drawn, so a change of label, prominence or state draws it anew.
function setupButtons(tuis, status) {
    var out = [];
    function has(name) { return out.some(function (button) { return button.name === name; }); }
    function add(tui, label, primary) {
        var enabled = primary || tui.withheld === "";
        out.push({ key: tui.name + " " + label + " " + primary + " " + enabled, name: tui.name, label: label, icon: tui.icon, primary: primary, enabled: enabled, reason: enabled ? "" : tui.withheld });
    }
    status.forEach(function (entry) {
        if (entry.action === null || entry.action.tui === "") return;
        var tui = tuis.filter(function (t) { return t.name === entry.action.tui; })[0];
        if (tui !== undefined && !has(tui.name)) add(tui, entry.action.label, true);
    });
    tuis.forEach(function (tui) { if (!has(tui.name)) add(tui, tui.label, false); });
    return out;
}
