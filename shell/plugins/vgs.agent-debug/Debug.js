.pragma library
.import qs.Commons 1.0 as Commons

// Agent Debug's decisions, pure so scripts/test-agent-debug.js runs them
// under node: which agents the Settings select offers, the journal follower's
// argv and the reading of its lines, the per-program and per-task limit,
// the muted programs, the options of each notification,
// and the facts Diagnose hands its terminal. The service
// (Service.qml) owns the journal and uid processes and calls these.
//
// A crash is a systemd-coredump journal entry, MESSAGE_ID
// fc2e22bc6ee647b6b90729ab34a250b1 (systemd's catalog,
// https://github.com/systemd/systemd/blob/main/catalog/systemd.catalog.in),
// read through `journalctl -o json`, which writes one JSON object a line,
// each field a string, or an array of numbers for a value that is not
// UTF-8, or an array for a field the entry holds twice
// (https://systemd.io/JOURNAL_EXPORT_FORMATS/#journal-json-format).
// A field that is no string is read as absent.

// The agents Diagnose opens, in the order the select offers them; `value`
// is each one's command and the first argument tui/diagnose.sh takes.
var AGENTS = [
    { value: "claude", label: "Claude Code" },
    { value: "codex", label: "Codex" },
    { value: "copilot", label: "Copilot" },
    { value: "pi", label: "Pi" },
    { value: "opencode", label: "OpenCode" }
];
var COREDUMP_MESSAGE_ID = "fc2e22bc6ee647b6b90729ab34a250b1";
// The fields the follower asks journalctl for: a coredump entry can carry
// the backtrace in MESSAGE and the core itself in COREDUMP, which the line
// then never holds.
var FIELDS = ["COREDUMP_COMM", "COREDUMP_PID", "COREDUMP_EXE", "COREDUMP_SIGNAL_NAME", "COREDUMP_SIGNAL", "COREDUMP_TIMESTAMP"];
// One notification per program or task in this window, and at most
// MAX_KEYS programs and tasks remembered in it: the window's keys come
// from the journal, which other programs write.
var WINDOW_MS = 60000;
var MAX_KEYS = 64;
// The most programs the muted list holds: the core's STATUS_LIST_MAX, the
// longest `rows` value the status record takes (shell/Core/PluginLogic.js).
var MUTED_MAX = 64;
// The longest program name the list holds: the core's STATUS_LABEL_MAX, a
// row label's length. The kernel's own name of a program is at most 15
// bytes (TASK_COMM_LEN).
var NAME_MAX = 60;
// The longest fact one terminal argument carries: shell.tui.run takes 1 to
// 256 characters an argument.
var FACT_MAX = 256;
// The most recent pids of the service's own processes it never notifies
// about: the follower and the uid read.
var OWN_PIDS_MAX = 16;
// The longest package sentence a setup notification's body holds before
// its Diagnose line: "cups, cups-pk-helper and system-config-printer.",
// the longest the design sheets show whole on the card at rest and on
// hover, in both modes (VGS-2260 sheets A9 and A10).
var BODY_PACKAGES_MAX = 47;
// The words of the Crash watch reading, one per state of the follower.
var WATCH = {
    "no-agent": { tone: "info", text: "Off", hint: "Starts when you [choose an agent](page:vgs.agent-debug/Settings/agent)" },
    "no-journal": { tone: "info", text: "Off", hint: "Starts when the system journal tool is installed from the [Setup tab](page:vgs.agent-debug/Setup)" },
    "starting": { tone: "info", text: "Starting" },
    "watching": { tone: "ok", text: "Watching" },
    "stopped": { tone: "warning", text: "Stopped", info: "Agent Debug stopped looking for crashes because it could not read the system journal.\nTurn Agent Debug off and on to try again." }
};

function hasOwn(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
}

// The agents whose command the last scan found: MISSING is the plugin's
// requirement commands it did not find. Each { label, value }.
function offers(missing) {
    return AGENTS.filter(function (a) { return missing.indexOf(a.value) === -1; })
        .map(function (a) { return { label: a.label, value: a.value }; });
}

function choices(missing, targets, saved) {
    var rows = offers(missing);
    (targets || []).forEach(function (target) {
        rows.push({ value: target.key, label: target.label + (target.available ? "" : " (unavailable)") });
    });
    if (isHandoff(saved) && !rows.some(function (row) { return row.value === saved; }))
        rows.push({ value: saved, label: "Saved message target (unavailable)" });
    return rows;
}

function isHandoff(value) { return typeof value === "string" && value.indexOf("handoff:") === 0; }

// The agent Diagnose opens: the `agent` setting while it names an agent
// the select offers, else "", which means no notification shows.
function chosen(agent, missing) {
    return isHandoff(agent) || offers(missing).some(function (a) { return a.value === agent; }) ? agent : "";
}

function label(agent, targets) {
    if (isHandoff(agent)) {
        var target = (targets || []).find(function (row) { return row.key === agent; });
        return target === undefined ? "your saved message target" : target.label;
    }
    for (var i = 0; i < AGENTS.length; i++)
        if (AGENTS[i].value === agent) return AGENTS[i].label;
    throw new Error("agent-debug: agent=" + JSON.stringify(agent) + " unknown");
}

// The uid `id -u` printed in TEXT, or "" when TEXT is no uid.
function uidOf(text) {
    var uid = String(text).trim();
    return /^(0|[1-9][0-9]*)$/.test(uid) ? uid : "";
}

// The follower: new coredump entries of UID's programs, from now on, one
// JSON object a line; journalctl applies the COREDUMP_UID match.
function followerArgv(uid) {
    return ["journalctl", "-f", "-n", "0", "-o", "json", "--output-fields=" + FIELDS.join(","),
        "MESSAGE_ID=" + COREDUMP_MESSAGE_ID, "COREDUMP_UID=" + uid];
}

function field(entry, name) {
    var value = entry[name];
    return typeof value === "string" ? value : null;
}

// LINE, one follower line, read with OWN the pids of the service's own
// processes: { kind: "crash", program, pid, signal, time, binary }, or
// { kind: "skip", reason } for a line that names no crash to notify:
// `json` for no JSON object, `pid` for no process id, `own` for the
// service's own process and `program` for no program name. `time` is the crash's time in ms since
// the epoch, or null when the entry holds none; `signal` the signal's name,
// `signal <n>` for a number alone, or "-"; `binary` the program's file, or
// "-".
function crash(line, own) {
    var entry;
    try {
        entry = JSON.parse(line);
    } catch (e) {
        return { kind: "skip", reason: "json" };
    }
    if (entry === null || typeof entry !== "object" || Array.isArray(entry)) return { kind: "skip", reason: "json" };
    var pid = field(entry, "COREDUMP_PID");
    if (pid === null || !/^[1-9][0-9]*$/.test(pid)) return { kind: "skip", reason: "pid" };
    if (own.indexOf(pid) !== -1) return { kind: "skip", reason: "own" };
    var program = field(entry, "COREDUMP_COMM");
    if (program === null || program === "") return { kind: "skip", reason: "program" };
    var name = field(entry, "COREDUMP_SIGNAL_NAME");
    var number = field(entry, "COREDUMP_SIGNAL");
    var stamp = field(entry, "COREDUMP_TIMESTAMP");
    var binary = field(entry, "COREDUMP_EXE");
    return {
        kind: "crash",
        program: program,
        pid: pid,
        signal: name !== null && /^SIG[A-Z0-9+-]+$/.test(name) ? name : number !== null && /^[0-9]+$/.test(number) ? "signal " + number : "-",
        time: stamp !== null && /^[0-9]{1,17}$/.test(stamp) ? Math.floor(Number(stamp) / 1000) : null,
        binary: binary === null || binary === "" ? "-" : binary
    };
}

// OWN with PID, a started process's id, added, keeping the last
// OWN_PIDS_MAX.
function ownAdded(own, pid) {
    if (pid === null || pid === undefined) return own;
    return own.concat([String(pid)]).slice(-OWN_PIDS_MAX);
}

// Whether KEY may notify at NOW, with SEEN the time of each key's last
// notice: { admit, seen, reason }, `seen` the window's keys with KEY's
// time when admitted, `reason` `window` for a key inside the window and
// `full` past MAX_KEYS.
function admit(seen, key, now) {
    var kept = {};
    Object.keys(seen).forEach(function (k) { if (now - seen[k] < WINDOW_MS) kept[k] = seen[k]; });
    if (hasOwn(kept, key)) return { admit: false, seen: kept, reason: "window" };
    if (Object.keys(kept).length >= MAX_KEYS) return { admit: false, seen: kept, reason: "full" };
    kept[key] = now;
    return { admit: true, seen: kept, reason: "" };
}

// TEXT as one terminal argument: each control character as `?`, and "-"
// for an empty text or one past FACT_MAX characters.
function fact(text) {
    var clean = String(text).replace(/[\u0000-\u001f\u007f-\u009f]/g, "?");
    return clean === "" || Array.from(clean).length > FACT_MAX ? "-" : clean;
}

// Whether NAME is a program name the muted list holds: a printable line of
// 1 to NAME_MAX characters, as a status row's label.
function nameFits(name) {
    return typeof name === "string" && name.length > 0 && name.length <= NAME_MAX && !Commons.SettingValues.CONTROL_OR_SEPARATOR.test(name);
}

// The `muted` setting as the service keeps it: each name nameFits admits,
// once, at most MUTED_MAX. A hand-edited file can hold anything of the
// default's type.
function mutedList(value) {
    if (!Array.isArray(value)) return [];
    var out = [];
    value.forEach(function (name) { if (nameFits(name) && out.indexOf(name) === -1 && out.length < MUTED_MAX) out.push(name); });
    return out;
}

// LIST with NAME muted: { answer, list }, `answer` `ok`,
// `refused: program=malformed` or `refused: muted=full limit=<n>`.
function mute(list, name) {
    if (!nameFits(name)) return { answer: "refused: program=malformed", list: list };
    if (list.indexOf(name) !== -1) return { answer: "ok", list: list };
    if (list.length >= MUTED_MAX) return { answer: "refused: muted=full limit=" + MUTED_MAX, list: list };
    return { answer: "ok", list: list.concat([name]) };
}

// LIST without NAME: { answer, list }, `answer` `ok`, or
// `refused: program=unmuted` for a name the list does not hold.
function unmute(list, name) {
    if (list.indexOf(name) === -1) return { answer: "refused: program=unmuted", list: list };
    return { answer: "ok", list: list.filter(function (n) { return n !== name; }) };
}

// The Muted programs rows the Settings page draws, each with Unmute.
function mutedRows(list) {
    return list.map(function (name) { return { id: name, label: name, actions: ["unmute"] }; });
}

// A list of names as a sentence reads it: "a", "a and b", "a, b and c".
function listed(names) {
    if (names.length <= 1) return names.join("");
    return names.slice(0, -1).join(", ") + " and " + names[names.length - 1];
}

// The notification for a crash of PROGRAM, with AGENT the label of the
// agent Diagnose opens.
function crashNotice(program, agent) {
    return { title: fact(program) + " crashed", body: "Diagnose with " + agent, urgency: "critical", tone: "danger", mute: true };
}

// The notification for FAILURE, a doctor.installFailures entry. The title
// names no plugin, since the doctor capability lends no plugin name.
function taskNotice(failure, agent) {
    var sentence = listed(failure.packages) + ".";
    var diagnose = "Diagnose with " + agent;
    return {
        title: failure.action === "update" ? "Could not update tools" : "Could not install tools",
        body: failure.packages.length > 0 && sentence.length <= BODY_PACKAGES_MAX ? sentence + " " + diagnose : diagnose,
        urgency: "normal",
        tone: "warning",
        mute: false
    };
}

function options(notice) {
    var actions = [{ id: "diagnose", label: "Diagnose" }];
    if (notice.mute) actions.push({ id: "mute", label: "Mute" });
    return { title: notice.title, message: notice.body, urgency: notice.urgency, icon: "bug", tone: notice.tone, actions: actions };
}

// MS since the epoch as the prompt writes a time: local time with its
// OFFSET in minutes east of UTC, as 2026-11-03T13:40:00-08:00, the form
// the approved sheet shows. journalctl --since reads it: systemd-analyze
// timestamp "2026-11-03T13:40:00-08:00" read it as 21:40:00 UTC (systemd
// on the VGS-2260 lane host, 2026-11-03).
function timeText(ms, offset) {
    var local = new Date(ms + offset * 60000).toISOString().slice(0, 19);
    var size = Math.abs(offset);
    var pad = function (n) { return (n < 10 ? "0" : "") + n; };
    return local + (offset < 0 ? "-" : "+") + pad(Math.floor(size / 60)) + ":" + pad(size % 60);
}

// tui/diagnose.sh's arguments for CRASH, crash()'s, opened in AGENT, at AT,
// its time in ms, OFFSET minutes east of UTC.
function crashArgs(agent, entry, at, offset) {
    return [agent, "crash", fact(entry.program), entry.pid, fact(entry.signal), timeText(at, offset), fact(entry.binary)];
}

// tui/diagnose.sh's arguments for FAILURE, a doctor.installFailures entry
// of plugin PLUGIN the service read at AT, opened in AGENT. The record is
// the run's ended record, never its lines.
function taskArgs(agent, plugin, failure, at, offset) {
    return [agent, "task", fact(plugin), fact(failure.action), fact(failure.manager || ""), fact(failure.packages.join(", ")), timeText(at, offset),
        fact(failure.path === null ? "" : failure.path)];
}

// The failure Diagnose describes: FAILURES' entry for PLUGIN while it is
// still the run KEY names, so its record path is the one the core holds at
// the press, else SEEN, the entry the service read first.
function pressedFailure(failures, plugin, key, seen) {
    if (failures !== null && hasOwn(failures, plugin) && failureKey(plugin, failures[plugin]) === key) return failures[plugin];
    return seen;
}

// The key one failure is told once by: its plugin and its run, `unstarted`
// for a launch that never started.
function failureKey(id, failure) {
    return id + ":" + (failure.run === null ? "unstarted" : String(failure.run));
}

// The failures FAILURES holds that SEEN, the keys of the last step, or
// null before the first, does not: { seen, fresh }, `fresh` each new
// { id, failure } but SELF's own. The first step tells none: the failures
// the core kept from before the service started were shown then.
function failuresStep(seen, failures, self) {
    var keys = [];
    var fresh = [];
    Object.keys(failures).sort().forEach(function (id) {
        var key = failureKey(id, failures[id]);
        keys.push(key);
        if (seen !== null && seen.indexOf(key) === -1 && id !== self) fresh.push({ id: id, failure: failures[id] });
    });
    return { seen: keys, fresh: fresh };
}
