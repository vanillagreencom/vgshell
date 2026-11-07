#!/usr/bin/env node
// Agent Debug's decisions, shell/plugins/vgs.agent-debug/Debug.js, under
// node: the agents the select offers, the follower's argv and the reading
// of its journal lines, the per-program and per-task limit, the restart
// bound, the muted list and its bounds, each notification's words and
// core notify options, the facts Diagnose hands its
// terminal, and which failed tasks are new. Every value the service
// publishes is judged by the core's status writer against the plugin's
// manifest. Every expected value is written out by hand.
//
// The controls at the end edit a copy of Debug.js, one rule at a time, and
// require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const root = path.join(__dirname, "..");
const dir = path.join(root, "shell", "plugins", "vgs.agent-debug");
const modules = { "qs.Commons 1.0": { SettingValues: load(path.join(root, "shell", "Commons", "SettingValues.js")) } };
const core = load(path.join(root, "shell", "Core", "PluginLogic.js"));
const loaded = core.validateManifest(JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf8")), dir);
assert.equal(loaded.ok, true, "the manifest validates: " + (loaded.error || ""));
const manifest = loaded.manifest;
// Debug.js runs in its own context, whose arrays and objects are not this
// one's; values are compared as JSON.
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message === undefined ? JSON.stringify(want) : message);

// One follower line as journalctl -o json writes it, with FIELDS over a
// crash of ad-crasher.
const line = fields => JSON.stringify(Object.assign({
    __CURSOR: "s=1;i=2", __REALTIME_TIMESTAMP: "1793742000000000",
    COREDUMP_COMM: "ad-crasher", COREDUMP_PID: "4242", COREDUMP_EXE: "/usr/bin/ad-crasher", COREDUMP_SIGNAL_NAME: "SIGSEGV",
    COREDUMP_SIGNAL: "11", COREDUMP_TIMESTAMP: "1793742000123456"
}, fields));
const CRASH = { kind: "crash", program: "ad-crasher", pid: "4242", signal: "SIGSEGV", time: 1793742000123, binary: "/usr/bin/ad-crasher" };
const skip = reason => ({ kind: "skip", reason: reason });
const name = n => "p".repeat(n);

// [name, line, own pids, answer]
const LINES = [
    ["a crash of the user's program", line({}), [], CRASH],
    ["the service's own process", line({}), ["17", "4242"], skip("own")],
    ["another pid with an own process's name", line({ COREDUMP_COMM: "tail", COREDUMP_PID: "4243" }), ["4242"], Object.assign({}, CRASH, { program: "tail", pid: "4243" })],
    ["a name that is not UTF-8", line({ COREDUMP_COMM: [255, 254] }), [], skip("program")],
    ["an empty name", line({ COREDUMP_COMM: "" }), [], skip("program")],
    ["a pid that is no number", line({ COREDUMP_PID: "42a" }), [], skip("pid")],
    ["a field the entry holds twice", line({ COREDUMP_PID: ["1", "2"] }), [], skip("pid")],
    ["a signal number alone", line({ COREDUMP_SIGNAL_NAME: undefined }), [], Object.assign({}, CRASH, { signal: "signal 11" })],
    ["no signal", line({ COREDUMP_SIGNAL_NAME: undefined, COREDUMP_SIGNAL: undefined }), [], Object.assign({}, CRASH, { signal: "-" })],
    ["no time", line({ COREDUMP_TIMESTAMP: undefined }), [], Object.assign({}, CRASH, { time: null })],
    ["no binary", line({ COREDUMP_EXE: undefined }), [], Object.assign({}, CRASH, { binary: "-" })],
    ["a line that is no JSON", "{\"COREDUMP_PID\":", [], skip("json")],
    ["a JSON list", "[1]", [], skip("json")]
];

// [name, packages, action, body]
const TASK_BODIES = [
    ["the longest sentence the card shows whole", ["cups", "cups-pk-helper", "system-config-printer"], "install",
        "cups, cups-pk-helper and system-config-printer. Diagnose with Claude Code"],
    ["one character past it", ["cups", "cups-pk-helper", "system-config-printerx"], "install", "Diagnose with Claude Code"],
    ["one package", ["gum"], "update", "gum. Diagnose with Claude Code"],
    ["no package", [], "install", "Diagnose with Claude Code"]
];

function verify(d) {
    // The select offers each agent whose command the scan found, in order.
    same(d.offers([]), [{ label: "Claude Code", value: "claude" }, { label: "Codex", value: "codex" }, { label: "Copilot", value: "copilot" },
        { label: "Pi", value: "pi" }, { label: "OpenCode", value: "opencode" }]);
    same(d.offers(["claude", "copilot", "pi", "journalctl"]), [{ label: "Codex", value: "codex" }, { label: "OpenCode", value: "opencode" }]);
    for (const agent of d.AGENTS.map(a => a.value)) {
        const declared = manifest.requirements.filter(r => r.name === agent && r.bus === null);
        assert.equal(declared.length === 1 && declared[0].optional === true, true, agent + " is one optional requirement of the manifest");
    }
    // No agent, a missing one or an unknown one is no choice.
    same([d.chosen("codex", []), d.chosen("", []), d.chosen("codex", ["codex"]), d.chosen("vim", []), d.chosen(undefined, [])], ["codex", "", "", "", ""]);
    same([d.uidOf("1000\n"), d.uidOf("0"), d.uidOf(""), d.uidOf("-1"), d.uidOf("10 00")], ["1000", "0", "", "", ""]);

    same(d.followerArgv("1000"), ["journalctl", "-f", "-n", "0", "-o", "json",
        "--output-fields=COREDUMP_COMM,COREDUMP_PID,COREDUMP_EXE,COREDUMP_SIGNAL_NAME,COREDUMP_SIGNAL,COREDUMP_TIMESTAMP",
        "MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1", "COREDUMP_UID=1000"]);
    for (const [label, text, own, want] of LINES) same(d.crash(text, own), want, label);
    same(d.ownAdded(["1"], 2), ["1", "2"]);
    same(d.ownAdded(["1"], null), ["1"]);
    const sixteen = Array.from({ length: 16 }, (_, i) => String(i));
    same(d.ownAdded(sixteen, 99), sixteen.slice(1).concat(["99"]), "the oldest of 16 own pids goes");

    // At most one notice per key a minute, and at most 64 keys in it.
    const first = d.admit({}, "crash:a", 1000);
    same([first.admit, first.seen], [true, { "crash:a": 1000 }]);
    const again = d.admit(first.seen, "crash:a", 60999);
    same([again.admit, again.reason], [false, "window"]);
    const later = d.admit(first.seen, "crash:a", 61000);
    same([later.admit, later.seen], [true, { "crash:a": 61000 }]);
    same(d.admit(first.seen, "crash:b", 2000).admit, true, "another key is its own");
    const full = {};
    for (let i = 0; i < 64; i++) full["crash:" + i] = 1000;
    const refused = d.admit(full, "crash:new", 2000);
    same([refused.admit, refused.reason, Object.keys(refused.seen).length], [false, "full", 64]);
    same(d.admit(full, "crash:new", 61000).seen, { "crash:new": 61000 }, "an expired key leaves the window");

    same([d.fact("a\nb\u0007"), d.fact(""), d.fact("x".repeat(256)).length, d.fact("x".repeat(257)), d.fact("\u{1F600}".repeat(256)).length],
        ["a?b?", "-", 256, "-", 512]);

    // The muted list keeps names a status row takes, once, at most 64.
    same(d.mutedList(["firefox", "firefox", "", "a\nb", name(60), name(61), 7, "Web Content"]), ["firefox", name(60), "Web Content"]);
    same(d.mutedList("firefox"), []);
    same(d.mute([], "Web Content"), { answer: "ok", list: ["Web Content"] });
    same(d.mute(["a"], "a"), { answer: "ok", list: ["a"] });
    same(d.mute([], "a\u2028b").answer, "refused: program=malformed");
    const many = Array.from({ length: 64 }, (_, i) => "p" + i);
    same(d.mute(many, "one-more").answer, "refused: muted=full limit=64");
    same(d.mutedList(many.concat(["p64"])).length, 64);
    same(d.unmute(["a", "b"], "a"), { answer: "ok", list: ["b"] });
    same(d.unmute(["a"], "b"), { answer: "refused: program=unmuted", list: ["a"] });
    same(d.mutedRows(["firefox"]), [{ id: "firefox", label: "firefox", actions: ["unmute"] }]);

    // The words and the core notify options.
    const crash = d.crashNotice("firefox", "Claude Code");
    same(crash, { title: "firefox crashed", body: "Diagnose with Claude Code", urgency: "critical", tone: "danger", mute: true });
    same(d.options(crash), { title: "firefox crashed", message: "Diagnose with Claude Code", urgency: "critical", tone: "danger", icon: "bug", actions: [{ id: "diagnose", label: "Diagnose" }, { id: "mute", label: "Mute" }] });
    for (const [label, packages, action, body] of TASK_BODIES)
        same(d.taskNotice({ action: action, packages: packages }, "Claude Code").body, body, label);
    const task = d.taskNotice({ action: "install", packages: ["gum"] }, "Codex");
    same(task, { title: "Could not install tools", body: "gum. Diagnose with Codex", urgency: "normal", tone: "warning", mute: false });
    same(d.taskNotice({ action: "update", packages: ["gum"] }, "Codex").title, "Could not update tools");
    same(d.options(task), { title: "Could not install tools", message: "gum. Diagnose with Codex", urgency: "normal", tone: "warning", icon: "bug", actions: [{ id: "diagnose", label: "Diagnose" }] });

    // The facts, each one terminal argument, the time in local time with
    // its offset.
    same([d.timeText(1793742000123, -480), d.timeText(1793742000123, 330), d.timeText(1793742000123, 0), d.timeText(1793742000123, -570)],
        ["2026-11-03T13:40:00-08:00", "2026-11-04T03:10:00+05:30", "2026-11-03T21:40:00+00:00", "2026-11-03T12:10:00-09:30"]);
    same(d.crashArgs("claude", Object.assign({}, CRASH, { program: "ad x;$(id)", binary: "/tmp/ad bin" }), 1793742000123, -480),
        ["claude", "crash", "ad x;$(id)", "4242", "SIGSEGV", "2026-11-03T13:40:00-08:00", "/tmp/ad bin"]);
    same(d.crashArgs("codex", Object.assign({}, CRASH, { binary: "/" + "b".repeat(256) }), 1793742060000, 0),
        ["codex", "crash", "ad-crasher", "4242", "SIGSEGV", "2026-11-03T21:41:00+00:00", "-"]);
    const failure = { action: "install", manager: "pacman", packages: ["cups", "gum"], lines: ["token=secret-value"], run: "k3q9x2", key: "core/requirements-install",
        path: "/run/user/1000/vgshell/tui/core@requirements-install@k3q9x2.ended.json" };
    same(d.taskArgs("pi", "vgs.printers", failure, 1793742000000, -480), ["pi", "task", "vgs.printers", "install", "pacman", "cups, gum", "2026-11-03T13:40:00-08:00",
        "/run/user/1000/vgshell/tui/core@requirements-install@k3q9x2.ended.json"]);
    same(d.taskArgs("pi", "acme.x", Object.assign({}, failure, { path: null, manager: "", packages: Array(60).fill("package") }), 0, 0).slice(4),
        ["-", "-", "1970-01-01T00:00:00+00:00", "-"]);
    // A failed sync job handed as text: [case, text, accepted].
    const SYNC = { kind: "sync", unit: "notes.service", name: "Notes", engine: "rsync", from: "/home/u/notes/", to: "/mnt/a/", error: "rsync error: error in file IO (code 11)", at: 1793742000123 };
    for (const [label, text, accepted] of [
        ["the shape Local Sync writes", JSON.stringify(SYNC), true],
        ["not JSON", "rsync failed", false],
        ["another kind", JSON.stringify(Object.assign({}, SYNC, { kind: "crash" })), false],
        ["a key too many", JSON.stringify(Object.assign({}, SYNC, { command: "rm -rf ~" })), false],
        ["a key missing", JSON.stringify(Object.assign({}, SYNC, { error: undefined })), false],
        ["a fact that is not text", JSON.stringify(Object.assign({}, SYNC, { from: ["/a"] })), false],
        ["no time", JSON.stringify(Object.assign({}, SYNC, { at: "now" })), false]
    ])
        assert.equal(d.syncFacts(text) !== null, accepted, "sync facts: " + label);
    same(d.syncArgs("claude", Object.assign({}, SYNC, { error: "line\nnext" }), SYNC.at, -480),
        ["claude", "sync", "notes.service", "Notes", "rsync", "/home/u/notes/", "/mnt/a/", "line?next", "2026-11-03T13:40:00-08:00"]);
    // Diagnose reads the failure the core holds at the press while it is
    // still the run the notification told, so a record path the core
    // listed after the first read reaches the prompt.
    const firstRead = Object.assign({}, failure, { path: null });
    same([d.pressedFailure({ "vgs.printers": failure }, "vgs.printers", "vgs.printers:k3q9x2", firstRead).path,
        d.pressedFailure({ "vgs.printers": Object.assign({}, failure, { run: "later" }) }, "vgs.printers", "vgs.printers:k3q9x2", firstRead).path,
        d.pressedFailure({}, "vgs.printers", "vgs.printers:k3q9x2", firstRead).path,
        d.pressedFailure(null, "vgs.printers", "vgs.printers:k3q9x2", firstRead).path],
        [failure.path, null, null, null]);

    // A failed task is told once, never on the first read and never the
    // service's own.
    const failures = { "acme.needs": Object.assign({}, failure, { run: "r1" }), "vgs.agent-debug": Object.assign({}, failure, { run: "r2" }) };
    same(d.failuresStep(null, failures, "vgs.agent-debug"), { seen: ["acme.needs:r1", "vgs.agent-debug:r2"], fresh: [] });
    const step = d.failuresStep([], failures, "vgs.agent-debug");
    same(step.fresh.map(f => f.id), ["acme.needs"]);
    same(d.failuresStep(step.seen, failures, "vgs.agent-debug").fresh, []);
    same(d.failuresStep(step.seen, { "acme.needs": Object.assign({}, failure, { run: "r3" }) }, "vgs.agent-debug"),
        { seen: ["acme.needs:r3"], fresh: [{ id: "acme.needs", failure: Object.assign({}, failure, { run: "r3" }) }] });
    same(d.failuresStep([], { "acme.x": Object.assign({}, failure, { run: null }) }, "self").seen, ["acme.x:unstarted"]);

    // Every value the service publishes, the largest included, is one the
    // core's status writer takes for this manifest.
    const fits = (key, value) => assert.equal(core.statusWrite(manifest, {}, key, value).ok, true, key + " " + JSON.stringify(value));
    for (const state of Object.keys(d.WATCH)) fits("watch", d.WATCH[state]);
    fits("agents", d.offers([]));
    const target = { key: "handoff:acme.receiver/compose", label: "Fixture receiver", available: true };
    same(d.chosen(target.key, []), target.key);
    same(d.label(target.key, [target]), "Fixture receiver");
    const unavailable = Object.assign({}, target, { available: false });
    const rows = d.choices(["claude", "codex", "copilot", "pi", "opencode"], [unavailable], target.key);
    same(rows.map(row => row.value), [target.key], "the unavailable saved choice remains, with no silent terminal choice");
    same(d.chosen(target.key, ["claude", "codex"]), target.key);
    fits("agents", rows);
    same(d.choices([], [], target.key).slice(-1).map(row => row.value), [target.key], "a removed target remains selected");
    const action = { key: "handoff:acme.jobs/new", label: "Fixture action", kind: "action", available: true };
    same(d.choices(["claude", "codex", "copilot", "pi", "opencode"], [target, action], "").map(row => row.value), [target.key], "an action receiver is no agent");
    fits("muted", d.mutedRows(Array.from({ length: d.MUTED_MAX }, (_, i) => name(d.NAME_MAX - 2) + String(i).padStart(2, "0"))));
    fits("muted", d.mutedRows(["Web Content", ".kitty-wrapped"]));
}

verify(load(path.join(dir, "Debug.js"), modules));

// Each control removes one rule from a copy of Debug.js and keeps the text
// around it. The suite must fail on every copy.
const CONTROLS = [
    ["the service's own pids notify", "if (own.indexOf(pid) !== -1) return", "if (false) return"],
    ["a byte-array field is read", 'return typeof value === "string" ? value : null;', "return value === undefined ? null : value;"],
    ["no window", "if (hasOwn(kept, key)) return", "if (false) return"],
    ["no key ceiling", "if (Object.keys(kept).length >= MAX_KEYS) return", "if (false) return"],
    ["the window never ends", "if (now - seen[k] < WINDOW_MS) kept[k] = seen[k];", "kept[k] = seen[k];"],
    ["a fact keeps control characters", 'replace(/[\\u0000-\\u001f\\u007f-\\u009f]/g, "?")', 'replace(/$^/g, "?")'],
    ["a fact past 256 characters", "Array.from(clean).length > FACT_MAX", "false"],
    ["no muted ceiling", "if (list.length >= MUTED_MAX) return", "if (false) return"],
    ["a malformed name is muted", "if (!nameFits(name)) return", "if (false) return"],
    ["a setup notice offers Mute", "urgency: \"normal\",\n        tone: \"warning\",\n        mute: false", "urgency: \"normal\",\n        tone: \"warning\",\n        mute: true"],
    ["no body bound", "sentence.length <= BODY_PACKAGES_MAX", "true"],
    ["the prompt's time is UTC", "new Date(ms + offset * 60000)", "new Date(ms)"],
    ["a sync fact takes another key", "if (keys.length !== SYNC_KEYS.length || ", "if ("],
    ["an action receiver is offered as an agent", "if (target.kind === \"action\") return;", ""],
    ["the offset's sign is lost", '(offset < 0 ? "-" : "+")', '"+"'],
    ["Diagnose reads the first record path", "failureKey(plugin, failures[plugin]) === key) return failures[plugin];", "failureKey(plugin, failures[plugin]) === key) return seen;"],
    ["the first read tells every failure", "if (seen !== null && seen.indexOf(key) === -1 && id !== self)", "if ((seen === null || seen.indexOf(key) === -1) && id !== self)"],
    ["the service's own failure is told", " && id !== self) fresh.push", ") fresh.push"],
    ["a missing agent is chosen", "return isHandoff(agent) || offers(missing).some(function (a) { return a.value === agent; }) ? agent : \"\";", "return isHandoff(agent) || AGENTS.some(function (a) { return a.value === agent; }) ? agent : \"\";"]
];

const source = fs.readFileSync(path.join(dir, "Debug.js"), "utf8");
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "agent-debug-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        fs.writeFileSync(path.join(temp, "Debug.js"), source.replace(needle, () => replacement));
        let failed = false;
        try {
            verify(load(path.join(temp, "Debug.js"), modules));
        } catch (e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the suite passed on Debug.js without that rule`);
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}

// The prompt text is the product result. The terminal migration consumes the
// same module and supplies its record-owned skill path instead of empty.
const builder = load(path.join(dir, "Diagnose.js"));
assert.equal(builder.prompt(["crash", "ad x;$(id)", "4242", "SIGSEGV", "2026-11-03T13:40:00-08:00", "/usr/bin/ad-crasher"], ""),
    "A program crashed on this computer and I want to know why.\nWhat systemd-coredump recorded:\n- Program: ad x;$(id)\n- Process ID: 4242\n- Binary: /usr/bin/ad-crasher\n- Signal: SIGSEGV\n- Time: 2026-11-03T13:40:00-08:00\nUse the vgs-diagnose skill.\nDiagnose only: change nothing on this computer.");
assert.equal(builder.prompt(["task", "acme.tools", "install", "pacman", "cups, gum", "2026-11-03T13:40:00-08:00", "/run/record.json"], "/skill/SKILL.md"),
    "A VGS setup task failed on this computer and I want to know why.\n- Task: install the tools of the VGS plugin acme.tools\n- Package manager: pacman\n- Packages: cups, gum\n- Time: 2026-11-03T13:40:00-08:00\n- Run record: /run/record.json\nUse the vgs-diagnose skill. If you cannot load skills, read /skill/SKILL.md and follow it.\nDiagnose only: change nothing on this computer.");
console.log(`test-agent-debug: ok lines=${LINES.length} bodies=${TASK_BODIES.length} controls=${CONTROLS.length}`);
