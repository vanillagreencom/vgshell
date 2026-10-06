.pragma library

// The Browser theming row of the plugin's Settings page, pure so
// scripts/test-themes-setup.js runs it under node: what `vgshell theme setup
// --json` says of the chromium target's one-time setup, the writer
// `vgshell theme browser-policy install` puts on PATH
// (docs/architecture/theme-targets.md).

// The shipped target whose setup the row reports.
var TARGET = "chromium";
// The states `vgshell theme setup` reports a setup in.
var STATES = ["not-detected", "absent", "done"];
var STATUS_LIST_MAX = 32;
var LABEL_MAX = 60;
var HINT_MAX = 200;

// The `browserTheming` status value, a `state`, for TEXT, the setup
// report's stdout, and CODE, its exit code, null for a report that did not
// start: Installed once the writer is on
// PATH; Not installed with the manifest's Install browser theming action
// offered while a Chromium-family browser is and the writer is not; No
// browser found while none is; not shipped for a tree whose targets hold
// no chromium setup, as the smoke's sandbox tree ships none. A report that
// failed or does not parse reads as unknown, in the danger tone, and
// offers nothing.
function browserTheming(text, code) {
    var unknown = function (why) {
        console.warn("themes: setup=" + why);
        return { tone: "danger", text: "Browser theme setup could not be checked. Open Plugins to check Themes." };
    };
    if (code === null) return unknown("did not start");
    if (code !== 0) return unknown("exited " + code);
    var report;
    try {
        report = JSON.parse(text);
    } catch (e) {
        return unknown("printed no report");
    }
    var rows = report !== null && typeof report === "object" && Array.isArray(report.setups) ? report.setups : null;
    if (rows === null) return unknown("printed no report");
    var row = null;
    for (var i = 0; i < rows.length; i++)
        if (rows[i] !== null && typeof rows[i] === "object" && rows[i].name === TARGET) row = rows[i];
    if (row === null) return { tone: "info", text: "This version of VGS does not support browser themes" };
    switch (row.state) {
    case "done": return { tone: "ok", text: "Browser theme support is installed" };
    case "absent": return { tone: "warning", text: "Browser themes are not installed", action: true };
    case "not-detected": return { tone: "info", text: "No Chromium-family browser found" };
    }
    return unknown("named the state " + JSON.stringify(row.state) + ", not one of " + STATES.join(", "));
}

function truncated(text, max) {
    var chars = Array.from(String(text));
    return chars.length <= max ? chars.join("") : chars.slice(0, max - 1).join("") + "…";
}

function displayFile(file, home) {
    return typeof home === "string" && home !== "" && file.indexOf(home + "/") === 0 ? "~" + file.slice(home.length) : file;
}

function wiring(text, code) {
    var unknown = function (why) {
        console.warn("themes: wiring=" + why);
        return null;
    };
    if (code === null) return unknown("did not start");
    if (code !== 0) return unknown("exited " + String(code));
    var report;
    try {
        report = JSON.parse(text);
    } catch (e) {
        return unknown("printed no report");
    }
    var rows = report !== null && typeof report === "object" && Array.isArray(report.wiring) ? report.wiring : null;
    if (rows === null) return unknown("printed no report");
    var home = report.home;
    var items = [];
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i];
        if (row === null || typeof row !== "object" || typeof row.app !== "string" || typeof row.file !== "string") return unknown("printed a malformed row");
        if (row.state !== "wired" && row.state !== "unreadable") return unknown("named the state " + JSON.stringify(row.state));
        if (row.line !== null && typeof row.line !== "string") return unknown("printed a malformed line");
        var file = displayFile(row.file, home);
        var hint = row.line === null ? file : file + ": " + row.line;
        items.push({ label: truncated(row.app, LABEL_MAX), value: row.state === "wired" ? "present" : "unavailable", hint: truncated(hint, HINT_MAX), sort: row.app + "\n" + row.file });
    }
    items.sort(function (a, b) { return a.sort < b.sort ? -1 : a.sort > b.sort ? 1 : 0; });
    if (items.length > STATUS_LIST_MAX) {
        var hidden = items.length - (STATUS_LIST_MAX - 1);
        items = items.slice(0, STATUS_LIST_MAX - 1);
        items.push({ label: "More files", value: "present", hint: hidden + " more files are not listed" });
    }
    return items.map(function (item) { return { label: item.label, value: item.value, hint: item.hint }; });
}
