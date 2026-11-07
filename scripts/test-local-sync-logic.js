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
// its state and dot. The Automations store is built with vgs.automations'
// own AutomationsLogic.js, so a change to its format fails here. Controls
// edit a copy of the logic, one rule each, and require this suite to fail
// on it.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.local-sync", "SyncLogic.js");
const Automations = load(path.join(__dirname, "..", "shell", "plugins", "vgs.automations", "AutomationsLogic.js"),
    { "qs.Commons 1.0": { Duration: load(path.join(__dirname, "..", "shell", "Commons", "Duration.js")) } });
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

// A user manager line ABOUT a unit, as journalctl -o json prints it.
function managerEntry(about, at, message) {
    return JSON.stringify({ __REALTIME_TIMESTAMP: String(at * 1000), MESSAGE: message, _COMM: "systemd", PRIORITY: "6", _SYSTEMD_USER_UNIT: "init.scope", USER_UNIT: about });
}

// The Automations store as bin/automations writes it, through
// AutomationsLogic's own add and serialize.
function automationsStore(definitions) {
    let store = Automations.emptyStore();
    for (const definition of definitions) {
        const added = Automations.addAutomation(store, Object.assign({ schedule: { frequency: "daily", interval: 1, times: ["09:00"], start: "2026-01-01", end: { type: "never" } } }, definition));
        assert.equal(added.ok, true, "the fixture automation is one Automations accepts: " + JSON.stringify(added.error));
        store = added.store;
    }
    return Automations.serializeStore(store);
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
        // Run now of backup, a transient unit while it runs, and an
        // automation whose own id looks like a Run now of it.
        block(unit("vgs-automation-backup-now-1794044488532.service", ["/usr/bin/node", "/engine", "run", "--manual", "backup"], { Type: "simple", ActiveState: "active" })),
        block(unit("vgs-automation-backup-now-2.service", ["/usr/bin/flock", "-n", "/lock", "/usr/bin/node", "/engine", "run", "--scheduled", "backup-now-2"])),
        // An engine that stays running: unison watching by its command
        // line, by its profile, and an rsync daemon.
        block(unit("mirror-watch.service", ["/usr/bin/unison", "mirror", "-repeat", "watch"], { Type: "simple", ActiveState: "active" })),
        block(unit("mirror-profile.service", ["/usr/bin/unison", "repeating"], { Type: "simple", ActiveState: "active" })),
        block(unit("rsyncd.service", ["/usr/bin/rsync", "--daemon", "--no-detach"], { Type: "simple", ActiveState: "active" })),
        // A unit listed again, as `show '*.service' <files>` prints a loaded
        // installed unit twice.
        block(unit("notes.service", ["/usr/bin/true"]))
    ].join("\n\n"));
    assert.equal(records.filter(r => r.Id === "notes.service").length, 1, "a unit listed twice is read once");
    assert.equal(records.find(r => r.Id === "notes.service").ExecStart.indexOf("rsync") !== -1, true, "the first block of a unit stands");

    const files = L.scriptFiles(records, HOME);
    for (const wanted of [HOME + "/.local/bin/scribd-brain-backup-sync", HOME + "/.unison/scribd-brain.prf", HOME + "/bin/run.sh"])
        assert.ok(files.indexOf(wanted) !== -1, "reads " + wanted);
    for (const unwanted of ["/var/log/rsync.log", "/usr/bin/rsync", "/usr/bin/flock", "/engine", "/usr/bin/dbus-broker-launch", HOME + "/.unison/watch.prf"])
        assert.equal(files.indexOf(unwanted), -1, "does not read " + unwanted);

    const scripts = {
        [HOME + "/.local/bin/scribd-brain-backup-sync"]: L.scriptLines(WRAPPER.join("\n")),
        [HOME + "/.unison/scribd-brain.prf"]: L.scriptLines("# Unison preferences\nroot = /home/user/dev/scribd-brain\nroot = ssh://user@host//home/user/dev/scribd-brain\nbatch = true\n"),
        [HOME + "/.unison/mirror.prf"]: L.scriptLines("root = /home/user/m\nroot = /mnt/m\n"),
        [HOME + "/.unison/repeating.prf"]: L.scriptLines("root = /home/user/r\nroot = /mnt/r\nrepeat = watch\n"),
        "/var/log/rsync.log": ["rsync -a /x/ /y/"]
    };
    assert.equal(scripts[HOME + "/.local/bin/scribd-brain-backup-sync"].indexOf("while [ -d \"$SRC\" ]; do"), -1, "a line that names no engine and sets nothing is not read");
    // The store Automations writes, read by this reader: its version and
    // its unit names are Automations' own.
    assert.equal(L.STORE_VERSION, Automations.STORE_VERSION, "the store version is Automations'");
    for (const id of ["backup", "backup-now-2"])
        assert.equal(L.automationId(Automations.unitName(id, "service")), id, "an automation's unit names its id: " + id);
    const store = L.readStore(automationsStore([
        { id: "backup", name: "Photos backup", command: "rsync -a --delete /home/user/Pictures/ /mnt/photos/" },
        { id: "other", name: "Pull repos", command: "git -C ~/dev pull" },
        { id: "backup-now-2", name: "Backup now 2", command: "rsync -a /home/user/x/ /mnt/x/" }
    ]));
    assert.equal(store.ok, true, "the store Automations writes reads");
    const automations = store.automations;
    same(L.automationOf("vgs-automation-backup-now-1794044488532.service", automations), { id: "backup", run: true }, "a Run now unit is its automation's");
    same(L.automationOf("vgs-automation-backup-now-2.service", automations), { id: "backup-now-2", run: false }, "a stored id is its own automation");
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
    same(Object.keys(byUnit).sort(), ["inline.service", "mirror-profile.service", "mirror-watch.service", "notes.service", "rsyncd.service", "scribd-brain-backup.service",
        "scribd-brain-sync.service", "vgs-automation-backup-now-2.service", "vgs-automation-backup.service"], "the sync jobs, a Run now unit none of its own");

    // [unit, engine, via, continuous, resident, from, to, available, automation]
    for (const [name, engine, via, continuous, stays, from, to, available, automation] of [
        ["scribd-brain-backup.service", "rsync", "script", true, false, "/run/media/user/Tertiary/scribd-brain/", HOME + "/dev/scribd-brain-backup/", true, ""],
        ["scribd-brain-sync.service", "unison", "direct", false, false, "/home/user/dev/scribd-brain", "ssh://user@host//home/user/dev/scribd-brain", false, ""],
        ["notes.service", "rsync", "direct", false, false, "/home/user/notes/", "/mnt/archive/notes/", true, ""],
        ["inline.service", "rsync", "script", false, false, HOME + "/a/", "/b/", true, ""],
        ["vgs-automation-backup.service", "rsync", "automation", false, false, "/home/user/Pictures/", "/mnt/photos/", true, "backup"],
        ["mirror-watch.service", "unison", "direct", true, true, "/home/user/m", "/mnt/m", false, ""],
        ["mirror-profile.service", "unison", "direct", true, true, "/home/user/r", "/mnt/r", false, ""],
        ["rsyncd.service", "rsync", "direct", true, true, "", "", true, ""]
    ]) {
        const job = byUnit[name];
        same([job.engine, job.via, job.continuous, job.resident, job.from, job.to, job.available, job.automation],
            [engine, via, continuous, stays, from, to, available, automation], "job " + name);
    }
    assert.equal(byUnit["vgs-automation-backup.service"].name, "Photos backup", "an automation keeps its own name");
    same(byUnit["vgs-automation-backup.service"].runs, ["vgs-automation-backup-now-1794044488532.service"], "a Run now unit is listed with its automation's job");
    same(byUnit["vgs-automation-backup-now-2.service"].runs, [], "an automation whose id looks like a Run now has its own runs");

    // The copy check asks about every job's units but an engine that
    // stays running, each answer counted for its job.
    const checked = L.checkUnits(jobs);
    same(checked.filter(c => c.job === "vgs-automation-backup.service").map(c => c.unit),
        ["vgs-automation-backup.service", "vgs-automation-backup-now-1794044488532.service"], "the copy check asks about a job's Run now unit");
    for (const name of ["mirror-watch.service", "mirror-profile.service", "rsyncd.service"])
        assert.equal(checked.some(c => c.job === name), false, "the copy check leaves out an engine that stays running: " + name);
    same(L.journalUnits(byUnit["vgs-automation-backup.service"]), ["-u", "vgs-automation-backup.service", "-u", "vgs-automation-backup-now-*.service"], "the journal read names the Run now units");
    same(L.journalUnits(byUnit["notes.service"]), ["-u", "notes.service"]);

    // A value from a command, or a variable no line sets, is not read.
    same(L.scriptJob(["SRC=$(pick)", "rsync -a \"$SRC/\" /b/"], HOME, {}), { engine: "rsync", from: "", to: "/b/", resident: false });
    same(L.scriptJob(["rsync -a \"$UNSET/\" \"${DEST:-/fallback}\""], HOME, {}), { engine: "rsync", from: "", to: "/fallback", resident: false });
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

    // An automation's journal: [case, entries, failedAt, finishedAt]. A Run
    // now unit's lines are the job's; another automation's are not, even
    // when its id looks like a Run now; the manager's clean end of a run
    // is its finish.
    const auto = byUnit["vgs-automation-backup.service"];
    const run = "vgs-automation-backup-now-1794044488532.service";
    for (const [name, lines, failedAt, finishedAt] of [
        ["a Run now's error", [entry(run, 5000, "rsync error: error in file IO (code 11)", "rsync")], 5000, 0],
        ["a look-alike automation's error", [entry("vgs-automation-backup-now-2.service", 5000, "rsync error: error in file IO (code 11)", "rsync")], 0, 0],
        ["a one-shot's clean finish", [managerEntry(auto.unit, 6000, "Finished vgs-automation-backup.service - Photos backup.")], 0, 6000],
        ["a Run now's clean end", [managerEntry(run, 7000, "Deactivated successfully.")], 0, 7000],
        ["a failed run's manager line", [managerEntry(auto.unit, 8000, "Failed with result 'exit-code'.")], 0, 0]
    ]) {
        const facts = L.journalFacts(lines.map(L.journalEntry), auto);
        same([facts.failedAt, facts.finishedAt], [failedAt, finishedAt], "automation journal: " + name);
    }
    for (const [name, about, matters] of [["its Run now", run, true], ["a look-alike automation", "vgs-automation-backup-now-2.service", false]])
        assert.equal(L.managerLineMatters({ about: about, message: "Started x." }, [auto]), matters, "manager line about " + name);

    // States: [case, job changes, facts, copying, clean end, state, tone,
    // actions, the moment the card words, the Errors row's tone and whether
    // it shows the error line]. The moment is "good" for the last clean end,
    // "tried" for the last try, "" for none, read from the moment the card
    // hands its `when`.
    const none = { tried: 0, failedAt: 0, error: "", problem: "", finishedAt: 0 };
    const fail = (at, extra) => Object.assign({ tried: at, failedAt: at, error: "rsync exited 12", problem: "", finishedAt: 0 }, extra || {});
    const notes = byUnit["notes.service"];
    for (const [name, changes, facts, copying, clean, state, tone, actions, moment, errorTone, showsError] of [
        ["a watching wrapper", {}, none, false, 0, "watching", "neutral", [], "", "neutral", false],
        ["a wrapper's copy", {}, none, true, 0, "copying", "info", [], "", "neutral", false],
        ["a wrapper's try", {}, Object.assign({}, none, { tried: 2000 }), false, 0, "watching", "neutral", [], "tried", "neutral", false],
        ["a wrapper's failed copy", {}, fail(2000), false, 0, "failed", "danger", ["log", "agent"], "tried", "danger", true],
        ["a wrapper's unreachable folder", {}, fail(2000, { problem: "to" }), false, 0, "attention", "danger", ["log"], "tried", "danger", true],
        ["a clean copy after the error", {}, fail(2000), false, 3000, "watching", "neutral", [], "good", "neutral", false],
        ["the failure's own later lines", {}, fail(2000, { tried: 2000 + 30000 }), false, 0, "failed", "danger", ["log", "agent"], "tried", "danger", true],
        ["a later try with no error", {}, fail(2000, { tried: 2000 + 61000 }), false, 0, "watching", "neutral", [], "tried", "neutral", false],
        ["a failed unit", { active: "failed" }, none, false, 0, "failed", "danger", ["log", "agent"], "", "neutral", false],
        ["a missing engine", { available: false }, none, false, 0, "unavailable", "neutral", ["setup"], "", "neutral", false],
        ["a stopped unit", { active: "inactive", triggers: [] }, none, false, 0, "stopped", "neutral", [], "", "neutral", false],
        ["a timer's unit", { active: "inactive" }, none, false, 0, "waiting", "neutral", [], "", "neutral", false],
        ["an engine that stays running", { via: "direct", resident: true }, none, false, 0, "watching", "neutral", [], "", "neutral", false]
    ]) {
        const job = Object.assign({}, backup, changes);
        const worded = [];
        const when = ms => { worded.push(ms); return "@" + ms; };
        const card = L.card(job, facts, copying, clean, 10000, when);
        const wanted = moment === "good" ? clean : moment === "tried" ? facts.tried : null;
        same([card.state, card.tone, card.actions, worded.length === 0 ? null : worded[0]], [state, tone, actions, wanted], "card: " + name);
        const errors = L.details(job, facts, copying, clean, 10000, when).rows.find(row => row.label === "Errors");
        same([errors.tone, errors.value === facts.error], [errorTone, showsError], "Errors row: " + name);
    }
    // A one-shot's clean run, from systemd's result or the manager's
    // finish line, is its last sync; a continuous job's unit exit is none.
    const oneshotGood = Object.assign({}, notes, { result: "success", mainStatus: 0, exitedAt: 4000, startedAt: 3500 });
    for (const [name, job, facts, good] of [
        ["systemd's result", oneshotGood, fail(3000, { tried: 3000 }), 4000],
        ["the manager's finish line", Object.assign({}, oneshotGood, { exitedAt: 0 }), fail(3000, { tried: 3000, finishedAt: 5000 }), 5000],
        ["a continuous job's unit exit", Object.assign({}, oneshotGood, { continuous: true }), Object.assign({}, none, { finishedAt: 5000 }), 0]
    ])
        same([L.card(job, facts, false, 0, 10000, ms => "@" + ms).good, L.jobState(job, facts, false, 0) === "failed"], [good, good === 0 && facts.failedAt > 0], "last sync: " + name);
    const oneshot = L.card(notes, none, false, 0, 10000, ms => String(ms));
    same([oneshot.state, oneshot.actions], ["failed", ["log", "agent"]], "a one-shot unit's failed result");
    const active = L.card(Object.assign({}, notes, { result: "success", active: "activating" }), none, false, 0, 10000, ms => String(ms));
    assert.equal(active.state, "starting", "an active one-shot with no engine running is not copying");

    // The bar: [case, card states, state, failed].
    for (const [name, states, state, failed] of [
        ["no jobs", [], "idle", false],
        ["watching only", ["watching", "waiting"], "idle", false],
        ["an engine that stays running", [L.card(byUnit["rsyncd.service"], none, false, 0, 10000, String).state], "idle", false],
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
    ["a clean copy does not clear an error", "good: Math.max(seen || 0, unitGood),", "good: Math.max(0, unitGood),"],
    ["a later try does not clear an error", " && facts.tried <= facts.failedAt + FAILURE_WINDOW;", ";"],
    ["an engine that stays running copies", "        if (job.resident) return;\n", ""],
    ["unison's repeat is ignored", "    if (call.args.some(function (word) { return word === \"-repeat\" || word.indexOf(\"-repeat=\") === 0; })) return true;\n", ""],
    ["a Run now unit is a job of its own", "if (hasOwn(automations || {}, id)) return { id: id, run: false };", "return { id: id, run: false };"],
    ["the manager's clean end is ignored", "if (ownsUnit(job, entry.about) && MANAGER_CLEAN.test(entry.message) && entry.at > facts.finishedAt) facts.finishedAt = entry.at;", ""],
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
