#!/usr/bin/env node
// vgs.local-sync's pure decisions, shell/plugins/vgs.local-sync/
// SyncLogic.js: which systemd user units are sync jobs and which folders
// they copy, which job an engine process belongs to, what a job's journal
// says about its last copy, its state, and what the bar item shows. The
// fixtures are the shapes the reads print on cachy (systemd 262, rsync
// 3.5.1, 2026-11-06): `systemctl --user show --timestamp=unix` blocks, the
// owner's scribd-brain-backup wrapper, systemd's GetUnitProcesses answer as
// `busctl --json=short` prints it and `journalctl -o json` entries. A
// card is held by its state, tone and actions, never its words; the bar by
// its state and dot. Controls edit a copy of the logic, one rule each, and
// require this suite to fail on it.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.local-sync", "SyncLogic.js");
const HOME = "/home/user";
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), JSON.parse(JSON.stringify(want)), message || "");
const CG = "/user.slice/user-1000.slice/user@1000.service/app.slice/";

function exec(argv) {
    return "{ path=" + argv[0] + " ; argv[]=" + argv.join(" ") + " ; ignore_errors=no ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }";
}

function block(fields) {
    return Object.keys(fields).map(key => key + "=" + fields[key]).join("\n");
}

function unit(id, argv, extra) {
    return Object.assign({
        Id: id, Description: id, LoadState: "loaded", ActiveState: "inactive", SubState: "dead", Result: "success",
        Type: "oneshot", ExecStart: exec(argv), TriggeredBy: "", UnitFileState: "static",
        ExecMainStatus: "0", ExecMainStartTimestamp: "", ExecMainExitTimestamp: ""
    }, extra || {});
}

// Lines of the owner's wrapper: comments, assignments, its rsync call and
// the log lines that name rsync.
const WRAPPER = [
    "# Continuously mirror the scribd-brain corpus to an off-drive backup.",
    "# and, after a short debounce, runs an rsync exact-mirror (--delete) into DEST",
    "SRC=\"/run/media/user/Tertiary/scribd-brain\"",
    "DEST=\"$HOME/dev/scribd-brain-backup\"",
    "DEBOUNCE=\"${SCRIBD_BACKUP_DEBOUNCE:-2}\"",
    "EVENTS=(-e modify -e create -e delete -e move -e attrib -e close_write)",
    "  # rc 24 (\"source files vanished\") is expected on a live-changing tree.",
    "  rsync -a --delete --exclude='.Trash-*/' \"$SRC/\" \"$DEST/\"",
    "[ \"$rc\" -eq 0 ] || log \"initial rsync exited $rc\"",
    "  [ \"$rc\" -eq 0 ] || log \"rsync exited $rc\"",
    "log() { printf '%s scribd-brain-backup: %s\\n' \"$(date '+%H:%M:%S')\" \"$*\"; }",
    "while [ -d \"$SRC\" ]; do"
];

function entry(unitName, at, message, comm) {
    return JSON.stringify({ __REALTIME_TIMESTAMP: String(at * 1000), MESSAGE: message, _COMM: comm || "bash", PRIORITY: "6", _SYSTEMD_USER_UNIT: unitName });
}

function verify(L) {
    const records = L.parseShow([
        block(unit("scribd-brain-backup.service", [HOME + "/.local/bin/scribd-brain-backup-sync"], { Type: "simple", ActiveState: "active", SubState: "running", TriggeredBy: "scribd-brain-backup.path" })),
        block(unit("scribd-brain-sync.service", ["/usr/bin/unison", "scribd-brain"], { TriggeredBy: "scribd-brain-sync.timer", ExecMainStartTimestamp: "@1794013200", ExecMainExitTimestamp: "@1794013200" })),
        block(unit("notes.service", ["/usr/bin/env", "LANG=C", "/usr/bin/rsync", "-a", "/home/user/notes/", "/mnt/archive/notes/"], { Result: "exit-code", ExecMainStatus: "23" })),
        block(unit("inline.service", ["/usr/bin/bash", "-c", "rsync -a ~/a/ /b/"])),
        // A command whose arguments are a log file that names rsync: only
        // the script a command runs is read, never its arguments.
        block(unit("watch.service", ["/usr/bin/sh", "-c", "exec \"$@\"", "sh", "/var/log/rsync.log"], { Type: "simple" })),
        block(unit("runner.service", ["/usr/bin/bash", HOME + "/bin/run.sh", "/var/log/rsync.log"])),
        block(unit("dbus-broker.service", ["/usr/bin/dbus-broker-launch", "--scope", "user"])),
        block(unit("gone.service", ["/usr/bin/rsync", "/a/", "/b/"], { LoadState: "not-found" })),
        block(unit("vgs-automation-backup.service", ["/usr/bin/flock", "-n", "/lock", "/usr/bin/node", "/engine", "run", "--scheduled", "backup"])),
        block(unit("vgs-automation-other.service", ["/usr/bin/flock", "-n", "/lock", "/usr/bin/node", "/engine", "run", "--scheduled", "other"])),
        // A unit listed again, as `show '*.service' <files>` prints a loaded
        // installed unit twice.
        block(unit("notes.service", ["/usr/bin/true"]))
    ].join("\n\n"));
    assert.equal(records.filter(r => r.Id === "notes.service").length, 1, "a unit listed twice is read once");
    assert.equal(records.find(r => r.Id === "notes.service").ExecStart.indexOf("rsync") !== -1, true, "the first block of a unit stands");

    const files = L.scriptFiles(records, HOME);
    for (const wanted of [HOME + "/.local/bin/scribd-brain-backup-sync", HOME + "/.unison/scribd-brain.prf", HOME + "/bin/run.sh"])
        assert.ok(files.indexOf(wanted) !== -1, "reads " + wanted);
    for (const unwanted of ["/var/log/rsync.log", "/usr/bin/rsync", "/usr/bin/flock", "/engine", "/usr/bin/dbus-broker-launch"])
        assert.equal(files.indexOf(unwanted), -1, "does not read " + unwanted);

    const scripts = {
        [HOME + "/.local/bin/scribd-brain-backup-sync"]: L.scriptLines(WRAPPER.join("\n")),
        [HOME + "/.unison/scribd-brain.prf"]: L.scriptLines("# Unison preferences\nroot = /home/user/dev/scribd-brain\nroot = ssh://user@host//home/user/dev/scribd-brain\nbatch = true\n"),
        "/var/log/rsync.log": ["rsync -a /x/ /y/"]
    };
    assert.equal(scripts[HOME + "/.local/bin/scribd-brain-backup-sync"].indexOf("while [ -d \"$SRC\" ]; do"), -1, "a line that names no engine and sets nothing is not read");
    const store = L.readStore(JSON.stringify({ version: 2, automations: [
        { id: "backup", name: "Photos backup", command: "rsync -a --delete /home/user/Pictures/ /mnt/photos/" },
        { id: "other", name: "Pull repos", command: "git -C ~/dev pull" }
    ] }));
    assert.equal(store.ok, true);
    const automations = store.automations;
    // A store this reader does not know lists no automation, and says so
    // while an automation's unit exists: [case, text].
    for (const [name, text] of [["absent", null], ["not JSON", "not json"], ["another version", JSON.stringify({ version: 3, automations: [] })]]) {
        const read = L.readStore(text);
        assert.equal(read.ok, false, "store: " + name);
        assert.equal(Object.keys(read.automations).length, 0, "store lists nothing: " + name);
        assert.notEqual(L.storeProblem(read, records), "", "store problem: " + name);
    }
    assert.equal(L.storeProblem(L.readStore(null), records.filter(r => L.automationId(r.Id) === "")), "", "no automation unit, no problem");

    const jobs = L.jobs(records, scripts, automations, HOME, ["unison"]);
    const byUnit = {};
    for (const job of jobs) byUnit[job.unit] = job;
    same(Object.keys(byUnit).sort(), ["inline.service", "notes.service", "scribd-brain-backup.service", "scribd-brain-sync.service", "vgs-automation-backup.service"], "the sync jobs");

    // [unit, engine, via, continuous, from, to, available, automation]
    for (const [name, engine, via, continuous, from, to, available, automation] of [
        ["scribd-brain-backup.service", "rsync", "script", true, "/run/media/user/Tertiary/scribd-brain/", HOME + "/dev/scribd-brain-backup/", true, ""],
        ["scribd-brain-sync.service", "unison", "direct", false, "/home/user/dev/scribd-brain", "ssh://user@host//home/user/dev/scribd-brain", false, ""],
        ["notes.service", "rsync", "direct", false, "/home/user/notes/", "/mnt/archive/notes/", true, ""],
        ["inline.service", "rsync", "script", false, HOME + "/a/", "/b/", true, ""],
        ["vgs-automation-backup.service", "rsync", "automation", false, "/home/user/Pictures/", "/mnt/photos/", true, "backup"]
    ]) {
        const job = byUnit[name];
        same([job.engine, job.via, job.continuous, job.from, job.to, job.available, job.automation],
            [engine, via, continuous, from, to, available, automation], "job " + name);
    }
    assert.equal(byUnit["vgs-automation-backup.service"].name, "Photos backup", "an automation keeps its own name");

    // A value from a command, or a variable no line sets, is not read.
    same(L.scriptJob(["SRC=$(pick)", "rsync -a \"$SRC/\" /b/"], HOME, {}), { engine: "rsync", from: "", to: "/b/" });
    same(L.scriptJob(["rsync -a \"$UNSET/\" \"${DEST:-/fallback}\""], HOME, {}), { engine: "rsync", from: "", to: "/fallback" });
    assert.equal(L.scriptJob(["echo \"rsync -a /x/ /y/\"", "log rsync started"], HOME, {}), null, "an engine named inside another command's words runs nothing");
    assert.equal(L.scriptJob(["nice -n 10 rsync -a /x/ /y/ && echo done"], HOME, {}).to, "/y/", "a command prefix leads to the engine, and its arguments end at the next command");

    // Whether an engine runs in a unit: [case, GetUnitProcesses answer, running].
    const procs = list => JSON.stringify({ type: "a(sus)", data: [list.map((command, i) => [CG + "scribd-brain-backup.service", 2000 + i, command])] });
    for (const [name, text, running] of [
        ["the watching wrapper", procs(["bash /home/user/.local/bin/scribd-brain-backup-sync", "inotifywait -r -q -e modify /run/media/user/Tertiary/scribd-brain"]), false],
        ["its rsync child", procs(["bash /home/user/.local/bin/scribd-brain-backup-sync", "rsync -a --delete /a/ /b/"]), true],
        ["an engine by its path", procs(["/usr/bin/unison scribd-brain"]), true],
        ["an engine named in an argument", procs(["tail -f /var/log/rsync"]), false],
        ["no process", procs([]), false],
        ["not the answer", "Call failed: Unit x.service not loaded.", null]
    ])
        assert.equal(L.engineRunning(text), running, "engine running: " + name);

    // The journal: [case, entries, failed, problem].
    const backup = byUnit["scribd-brain-backup.service"];
    for (const [name, lines, failed, problem] of [
        ["a start line", [entry(backup.unit, 1000, "13:01:51 scribd-brain-backup: change detected -> syncing")], false, ""],
        ["a vanished file is a warning", [entry(backup.unit, 1000, "rsync warning: some files vanished before they could be transferred (code 24) at main.c(1338) [sender=3.5.1]", "rsync"),
            entry(backup.unit, 1001, "13:01:52 scribd-brain-backup: rsync exited 24")], false, ""],
        ["a missing source", [entry(backup.unit, 1000, "rsync: [sender] change_dir \"/run/media/user/Tertiary/scribd-brain\" failed: No such file or directory (2)", "rsync"),
            entry(backup.unit, 1001, "rsync error: some files/attrs were not transferred (see previous errors) (code 23) at main.c(1412) [sender=3.5.1]", "rsync"),
            entry(backup.unit, 1002, "13:01:52 scribd-brain-backup: rsync exited 23")], true, "from"],
        ["a missing destination", [entry(backup.unit, 1000, "rsync: [Receiver] mkdir \"/nonexistent/dst\" failed: No such file or directory (2)", "rsync"),
            entry(backup.unit, 1001, "rsync error: error in file IO (code 11) at main.c(821) [Receiver=3.5.1]", "rsync")], true, "to"],
        ["a script's report of a failed exit", [entry(backup.unit, 1000, "13:01:52 scribd-brain-backup: initial rsync exited 12")], true, ""],
        ["another unit's error", [entry("notes.service", 1000, "rsync error: error in file IO (code 11)", "rsync")], false, ""]
    ]) {
        const facts = L.journalFacts(lines.map(L.journalEntry), backup);
        assert.equal(facts.failedAt > 0, failed, "journal failed: " + name);
        assert.equal(facts.problem, problem, "journal problem: " + name);
        same(JSON.parse(JSON.stringify(facts)), facts, "facts are plain JSON: " + name);
    }

    // States: [case, job changes, facts, copying, clean end, state, tone, actions].
    const none = { tried: 0, failedAt: 0, error: "", problem: "" };
    const notes = byUnit["notes.service"];
    for (const [name, changes, facts, copying, clean, state, tone, actions] of [
        ["a watching wrapper", {}, none, false, 0, "watching", "neutral", []],
        ["a wrapper's copy", {}, none, true, 0, "copying", "info", []],
        ["a wrapper's failed copy", {}, { tried: 2000, failedAt: 2000, error: "rsync exited 12", problem: "" }, false, 0, "failed", "danger", ["log", "agent"]],
        ["a wrapper's unreachable folder", {}, { tried: 2000, failedAt: 2000, error: "x", problem: "to" }, false, 0, "attention", "danger", ["log"]],
        ["a clean copy after the error", {}, { tried: 2000, failedAt: 2000, error: "x", problem: "" }, false, 3000, "watching", "neutral", []],
        ["a failed unit", { active: "failed" }, none, false, 0, "failed", "danger", ["log", "agent"]],
        ["a missing engine", { available: false }, none, false, 0, "unavailable", "neutral", ["setup"]],
        ["a stopped unit", { active: "inactive", triggers: [] }, none, false, 0, "stopped", "neutral", []],
        ["a timer's unit", { active: "inactive" }, none, false, 0, "waiting", "neutral", []]
    ]) {
        const job = Object.assign({}, backup, changes);
        const card = L.card(job, facts, copying, clean, 10000, ms => String(ms));
        same([card.state, card.tone, card.actions], [state, tone, actions], "card: " + name);
    }
    const oneshot = L.card(notes, none, false, 0, 10000, ms => String(ms));
    same([oneshot.state, oneshot.actions], ["failed", ["log", "agent"]], "a one-shot unit's failed result");
    const active = L.card(Object.assign({}, notes, { result: "success", active: "activating" }), none, false, 0, 10000, ms => String(ms));
    assert.equal(active.state, "starting", "an active one-shot with no engine running is not copying");

    // The bar: [case, card states, state, failed].
    for (const [name, states, state, failed] of [
        ["no jobs", [], "idle", false],
        ["watching only", ["watching", "waiting"], "idle", false],
        ["a copy", ["copying", "watching"], "syncing", false],
        ["a failure", ["failed", "watching"], "failed", true],
        ["a copy beside a failure", ["copying", "attention"], "syncing", true]
    ]) {
        const view = L.bar(states.map((s, i) => ({ state: s, stateText: s, name: "job " + i })));
        same([view.state, view.failed], [state, failed], "bar: " + name);
    }

    same(L.removeUnits(backup), ["scribd-brain-backup.path", "scribd-brain-backup.service"], "Remove turns off the triggers before the unit");

    // A manager line about a job, or a reload, reads the jobs again.
    for (const [name, about, message, matters] of [
        ["a job's start", "scribd-brain-sync.service", "Starting Two-way scribd-brain sync…", true],
        ["another unit", "app-foo.scope", "Started app-foo.scope.", false],
        ["a reload", "", "Reloading requested from client PID 1 ('systemctl')…", true]
    ])
        assert.equal(L.managerLineMatters({ about: about, message: message }, jobs), matters, "manager line: " + name);
}

verify(load(file));

const controls = [
    ["an engine counts anywhere in a line", "        if (!start) continue;\n", ""],
    ["rsync's vanished-file warning is an error", "var RSYNC_WARNINGS = [24];", "var RSYNC_WARNINGS = [];"],
    ["any process word names an engine", "engineOf(proc[2].split(\" \")[0]) !== \"\"", "proc[2].split(\" \").some(function (w) { return engineOf(w) !== \"\"; })"],
    ["a system program is read as a script", "if (script !== null && script.file !== undefined && !SYSTEM_DIRS.test(script.file)) add(script.file);", "if (script !== null && script.file !== undefined) add(script.file);"],
    ["a command's arguments are read as scripts", "if (argv[i].charAt(0) !== \"-\") return argv[i].charAt(0) === \"/\" ? { file: argv[i] } : null;", "if (argv[i].charAt(0) !== \"-\") continue;"],
    ["an active one-shot copies", "return job.continuous ? \"watching\" : \"starting\";", "return job.continuous ? \"watching\" : \"copying\";"],
    ["a clean copy does not clear an error", "var lastGood = Math.max(seen || 0,", "var lastGood = Math.max(0,"],
    ["any store version is read", " || doc.version !== STORE_VERSION || ", " || "]
];

const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "test-local-sync-logic-"));
try {
    const source = fs.readFileSync(file, "utf8");
    for (const [label, needle, replacement] of controls) {
        assert.equal(source.split(needle).length - 1, 1, "control pattern occurs once: " + label);
        const dir = fs.mkdtempSync(path.join(scratch, "control-"));
        const mutant = path.join(dir, "SyncLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, replacement));
        assert.notEqual(fs.readFileSync(mutant, "utf8"), source);
        let red = false;
        try { verify(load(mutant)); } catch (e) { red = e instanceof assert.AssertionError; }
        assert.equal(red, true, "control fails without rule: " + label);
    }
} finally {
    fs.rmSync(scratch, { recursive: true, force: true });
}

console.log("test-local-sync-logic: ok");
