#!/usr/bin/env node
// The automations engine, shell/plugins/vgs.automations/bin/automations,
// end to end: the store verbs, sync against a stand-in systemctl and a
// stand-in crontab, the runner (success, a non-zero exit, a timeout that
// ends the command's process group, a failed start, the transcript cap, the
// records it writes before and after the command), the notifications it
// sends through a stand-in notify-send and the failure streak that keeps
// one notice open across runs on the notification server a stand-in
// busctl names, run-now through a stand-in
// systemd-run, the scheduled trigger's guard, history with a running and a
// vanished run, clear and pruning with the plugin's historyDays setting, the
// cron startup line that catches up a missed occurrence, a
// timed-out run that waits for a descendant ignoring SIGTERM, and output
// with no line break, which reaches the transcript in pieces. The snippet
// keeps each candidate line cut to what a snippet shows; that bounds the
// runner's memory alone and changes no snippet, so no case reddens without
// it, and the snippet rows hold what a snippet shows.
//
// Every case runs in its own scratch home with a PATH of stand-ins and an
// allow-list of host tools, and an XDG_RUNTIME_DIR of its own with no
// session bus: no case can reach the user's systemd manager, crontab,
// notification server or ~/.config/systemd. The command under test runs in
// the user's login shell, as the runner runs it, so every command here is
// valid in sh, bash, zsh and fish.
//
// The controls at the end edit a copy of the engine, one rule at a time,
// and require the case that rule serves to fail on the copy.
"use strict";
const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");
const modules = { "qs.Commons 1.0": { Duration: load(path.join(__dirname, "..", "shell", "Commons", "Duration.js")) } };

// The cases and the engine read local time in one zone.
process.env.TZ = "UTC";
const repo = path.join(__dirname, "..");
const pluginDir = path.join(repo, "shell", "plugins", "vgs.automations");
const Logic = load(path.join(pluginDir, "AutomationsLogic.js"), modules);
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "test-automations-engine-"));
// The host tools a case may run: the engine's own, the ones vgshell plugin
// settings needs, and the ones the commands under test use. systemctl,
// systemd-run, loginctl, crontab, notify-send and busctl are stand-ins alone.
const TOOLS = ["bash", "sh", "env", "flock", "sleep", "yes", "head", "cat", "python3", "systemd-analyze", "dirname", "readlink", "basename", "mkdir", "rm", "mv", "cp", "ls", "id", "date", "sed", "grep", "tr", "mktemp", "true", "false", "realpath", "stat", "sort", "uname", "wc", "cut", "awk", "touch", "chmod", "ln", "find", "tail", "tee", "kill", "setsid", "printf", "test"];
const FORBIDDEN = ["systemctl", "systemd-run", "loginctl", "crontab", "notify-send", "busctl"];

// ------------------------------------------------------------ the world

function which(command) {
    for (const dir of String(process.env.PATH || "").split(path.delimiter)) {
        const candidate = path.join(dir, command);
        try {
            fs.accessSync(candidate, fs.constants.X_OK);
            if (fs.statSync(candidate).isFile()) return fs.realpathSync(candidate);
        } catch (_e) {
            // Keep looking.
        }
    }
    return null;
}

function write(file, text, mode) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text, { mode: mode || 0o644 });
}

// The stand-ins: each appends its argv, one JSON list a line, to
// $STUB/<name>.calls. systemctl answers show-environment with
// $STUB/systemd (up or down); systemd-run runs the argv after `--`;
// notify-send prints the id it replaces, as a notification server keeps
// it, else the next one; busctl answers the session bus's id from
// $STUB/bus and the owner of org.freedesktop.Notifications from
// $STUB/owner, refusing as busctl does when the file is empty, and
// NetworkManager's Connectivity on the system bus from $STUB/nm, absent while the
// file is empty, ended by SIGTERM when it reads `kill` and hung past any
// bound when it reads `hang`, as a system bus slow to answer just after a
// resume leaves it; its wait for StateChanged reads the State, then appends
// its --timeout word to $STUB/nm-waits and returns when $STUB/nm changes,
// as the signal would, or after its timeout with no output; crontab
// keeps the table in $STUB/crontab; loginctl answers $STUB/linger.
const STUBS = {
    systemctl: `#!/usr/bin/env bash
printf '%s\\n' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@")" >>"$STUB/systemctl.calls"
if [[ \${2:-} == show-environment ]]; then [[ $(<"$STUB/systemd") == up ]] || exit 1; fi
exit 0
`,
    "systemd-run": `#!/usr/bin/env bash
printf '%s\\n' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@")" >>"$STUB/systemd-run.calls"
while [[ $# -gt 0 && $1 != -- ]]; do
  case "$1" in --setenv=*) export "\${1#--setenv=}" ;; esac
  shift
done
shift
"$@" >>"$STUB/systemd-run.out" 2>&1 || true
`,
    "notify-send": `#!/usr/bin/env bash
printf '%s\\n' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@")" >>"$STUB/notify-send.calls"
n=$(( $(wc -l <"$STUB/notify-send.calls") + 40 ))
for a in "$@"; do case "$a" in --replace-id=*) n=\${a#--replace-id=} ;; esac; done
printf '%s\\n' "$n"
`,
    busctl: `#!/usr/bin/env bash
nm="org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.NetworkManager"
case "$*" in
  "--system --json=short get-property $nm Connectivity")
    printf read\\n >>"$STUB/nm-reads"
    v=$(<"$STUB/nm")
    [[ $v == kill ]] && kill -TERM $$
    # exec, so the runner's bound kills the process holding the pipes.
    [[ $v == hang ]] && exec sleep 30
    [[ -n $v ]] || { echo "Failed to get property State on interface org.freedesktop.NetworkManager: The name org.freedesktop.NetworkManager was not provided by any .service files" >&2; exit 1; }
    printf '{"type":"u","data":%s}\\n' "$v"; exit 0 ;;
  "--system --json=short wait --timeout="*" org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.DBus.Properties PropertiesChanged")
    was=$(<"$STUB/nm")
    printf '%s\\n' "$4" >>"$STUB/nm-waits"
    if [[ -f $STUB/nm-wait-failure ]]; then cat "$STUB/nm-wait-failure" >&2; exit 23; fi
    for ((i = 0; i < \${4#--timeout=} * 20; i++)); do
      v=$(<"$STUB/nm")
      [[ $v == "$was" ]] || { printf '{"type":"u","data":[%s]}\\n' "$v"; exit 0; }
      sleep 0.05
    done
    exit 0 ;;
  "--user --json=short call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetId") v=$(<"$STUB/bus") ;;
  "--user --json=short call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner s org.freedesktop.Notifications") v=$(<"$STUB/owner") ;;
  *) echo "busctl stand-in: unexpected $*" >&2; exit 2 ;;
esac
[[ -n $v ]] || { echo "Call failed: Could not get owner of name 'org.freedesktop.Notifications': no such name" >&2; exit 1; }
printf '{"type":"s","data":["%s"]}\\n' "$v"
`,
    crontab: `#!/usr/bin/env bash
printf '%s\\n' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@")" >>"$STUB/crontab.calls"
case "$1" in
  -l) if [[ -f $STUB/crontab ]]; then cat "$STUB/crontab"; else echo "no crontab for $(id -un)" >&2; exit 1; fi ;;
  -) cat >"$STUB/crontab" ;;
  *) exit 2 ;;
esac
`,
    loginctl: `#!/usr/bin/env bash
printf '%s\\n' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@")" >>"$STUB/loginctl.calls"
cat "$STUB/linger"
`
};

// The session bus every world starts on.
const BUS = "4b1d2c3e4f5a6b7c8d9e0f1a2b3c4d5e";

let worlds = 0;
// A fresh home, stand-ins and PATH. `stubs` names the stand-ins present;
// systemd `up` or `down`.
function world(options) {
    const opts = Object.assign({ systemd: "up", stubs: FORBIDDEN, linger: "no", timezone: "UTC" }, options || {});
    const root = path.join(scratch, "w" + (worlds += 1));
    const stub = path.join(root, "stub");
    const bin = path.join(root, "bin");
    const tools = path.join(root, "tools");
    fs.mkdirSync(stub, { recursive: true });
    fs.mkdirSync(tools, { recursive: true });
    fs.mkdirSync(path.join(root, "home"), { recursive: true });
    fs.mkdirSync(path.join(root, "run"), { recursive: true, mode: 0o700 });
    for (const name of opts.stubs) write(path.join(bin, name), STUBS[name], 0o755);
    fs.mkdirSync(bin, { recursive: true });
    for (const tool of TOOLS) {
        const real = which(tool);
        if (real !== null) fs.symlinkSync(real, path.join(tools, tool));
    }
    fs.symlinkSync(process.execPath, path.join(tools, "node"));
    write(path.join(stub, "systemd"), opts.systemd + "\n");
    write(path.join(stub, "linger"), opts.linger + "\n");
    write(path.join(stub, "bus"), BUS + "\n");
    write(path.join(stub, "owner"), ":1.7\n");
    write(path.join(stub, "nm"), "");
    const env = { HOME: path.join(root, "home"), PATH: bin + ":" + tools, XDG_RUNTIME_DIR: path.join(root, "run"), STUB: stub, LANG: "C.UTF-8", TZ: opts.timezone };
    if (opts.nowMs !== undefined) {
        const clock = path.join(root, "fixed-date.js");
        const state = path.join(root, "clock.json");
        write(state, JSON.stringify({ now: opts.nowMs, mono: 0 }));
        write(clock, "const fs = require('fs'); const read = () => JSON.parse(fs.readFileSync(" + JSON.stringify(state) + ", 'utf8')); const RealDate = Date; global.Date = class FixedDate extends RealDate { constructor(...args) { super(...(args.length === 0 ? [read().now] : args)); } static now() { return read().now; } }; process.hrtime.bigint = () => BigInt(read().mono) * 1000000n;\n");
        env.NODE_OPTIONS = "--require=" + clock;
    }
    const home = path.join(root, "home");
    return {
        root, stub, home,
        runs: path.join(home, ".local", "state", "vgshell", "automations", "runs"),
        units: path.join(home, ".config", "systemd", "user"),
        store: path.join(home, ".config", "vgshell", "automations", "automations.json"),
        env: env
    };
}

function cli(w, engine, args, options) {
    const out = childProcess.spawnSync(engine, ["--tree", repo].concat(args), Object.assign({ encoding: "utf8", env: w.env, cwd: w.home, timeout: 60000 }, options || {}));
    return { status: out.status, stdout: out.stdout, stderr: out.stderr, first: (out.stderr || "").split("\n")[0] };
}

function calls(w, name) {
    const file = path.join(w.stub, name + ".calls");
    return fs.existsSync(file) ? fs.readFileSync(file, "utf8").trim().split("\n").filter(Boolean).map(JSON.parse) : [];
}

function def(extra) {
    return Object.assign({ name: "Job", command: "echo done", schedule: { frequency: "daily", interval: 1, times: ["09:00"], start: "2026-01-01", end: { type: "never" } } }, extra);
}

function add(w, engine, extra) {
    const out = cli(w, engine, ["add", "--definition", JSON.stringify(def(extra))]);
    assert.equal(out.status, 0, "add: " + out.stderr);
    return out.stdout.trim().split("\n").pop().replace(/^added=/, "");
}

function runFiles(w) {
    return fs.existsSync(w.runs) ? fs.readdirSync(w.runs).sort() : [];
}

function ended(w, id) {
    const names = runFiles(w).filter(n => n.startsWith(id + "@") && n.endsWith(".ended.json"));
    assert.equal(names.length, 1, "one ended record for " + id + ": " + runFiles(w).join(" "));
    return JSON.parse(fs.readFileSync(path.join(w.runs, names[0]), "utf8"));
}

function manual(w, engine, id) {
    return cli(w, engine, ["run", "--manual", id]);
}

// ------------------------------------------------------------ the cases

const CASES = {
    "sync with nothing runs nothing"(engine) {
        const w = world();
        const out = cli(w, engine, ["sync"]);
        assert.equal(out.stdout, "sync=idle changed=0\n");
        for (const name of FORBIDDEN) same(calls(w, name), [], "no " + name + " call");
        assert.equal(fs.existsSync(w.units), false);
    },

    "add writes the units, reloads and enables the timer"(engine) {
        const w = world();
        const id = add(w, engine, { name: "Back up", schedule: { frequency: "weekly", interval: 2, weekdays: ["mon", "thu"], times: ["08:30", "17:00"], start: "2026-01-05", end: { type: "never" } }, catchUp: true });
        assert.equal(id, "back-up");
        same(calls(w, "systemctl"), [["--user", "show-environment"], ["--user", "daemon-reload"], ["--user", "enable", "--now", "vgs-automation-back-up.timer"]]);
        const timer = fs.readFileSync(path.join(w.units, "vgs-automation-back-up.timer"), "utf8");
        assert.match(timer, /\nOnCalendar=Mon,Thu \*-\*-\* 08:30:00\nOnCalendar=Mon,Thu \*-\*-\* 17:00:00\n/);
        assert.match(timer, /\nPersistent=true\n/);
        const service = fs.readFileSync(path.join(w.units, "vgs-automation-back-up.service"), "utf8");
        const exec = /\nExecStart=(.*)\n/.exec(service)[1];
        assert.match(exec, /^"[^"]*\/flock" "-n" "-E" "75" "-o" "[^"]*\/locks\/back-up\.lock" "[^"]*node[^"]*" "[^"]*\/engine\/[0-9a-f]{16}\/bin\/automations" "--tree" "[^"]*" "run" "--scheduled" "back-up"$/);
        const engineCopy = /"([^"]*\/engine\/[0-9a-f]{16})\/bin\/automations"/.exec(exec)[1];
        assert.equal(fs.readFileSync(path.join(engineCopy, "AutomationsLogic.js"), "utf8"), fs.readFileSync(path.join(pluginDir, "AutomationsLogic.js"), "utf8"), "the units run a copy of the judge");
        assert.ok(JSON.parse(fs.readFileSync(path.join(w.home, ".local", "state", "vgshell", "automations", "guard", "back-up.json"), "utf8")).handledThrough > Date.now() - 60000, "add marks the past handled");
        const multi = cli(w, engine, ["add", "--definition", JSON.stringify(def({ name: "Multi", command: "a=1\necho $a" }))]);
        assert.equal(multi.status, 0);
        const refused = cli(w, engine, ["add", "--definition", JSON.stringify(def({ command: "a\u0000b" }))]);
        assert.equal(refused.status, 1);
        assert.equal(refused.first, "automations: refused: definition=definition.command:-want=command-of-1..4096-without-control-characters-except-newline-and-tab");
        assert.equal(JSON.parse(fs.readFileSync(w.store, "utf8")).automations.length, 2, "a refused add leaves the store");
        assert.equal(cli(w, engine, ["add", "--definition", "{"]).first, "automations: refused: definition=not-json");
    },

    "edit, disable, enable and remove follow the store"(engine) {
        const w = world();
        const id = add(w, engine, {});
        fs.rmSync(path.join(w.stub, "systemctl.calls"));
        assert.equal(cli(w, engine, ["edit", id, "--definition", JSON.stringify({ schedule: { frequency: "yearly", interval: 1, yearly: { month: 3, day: 15 }, times: ["07:00"], start: "2026-01-01", end: { type: "never" } } })]).status, 0);
        assert.match(fs.readFileSync(path.join(w.units, "vgs-automation-job.timer"), "utf8"), /\nOnCalendar=\*-03-15 07:00:00\n/);
        same(calls(w, "systemctl").slice(1), [["--user", "daemon-reload"], ["--user", "enable", "--now", "vgs-automation-job.timer"], ["--user", "restart", "vgs-automation-job.timer"]], "a changed timer restarts");
        fs.rmSync(path.join(w.stub, "systemctl.calls"));
        assert.equal(cli(w, engine, ["disable", id]).stdout.trim().split("\n").pop(), "disabled=job");
        same(calls(w, "systemctl").slice(1), [["--user", "disable", "--now", "vgs-automation-job.timer"], ["--user", "daemon-reload"]]);
        same(fs.readdirSync(w.units), []);
        assert.equal(cli(w, engine, ["enable", id]).status, 0);
        same(fs.readdirSync(w.units).sort(), ["vgs-automation-job.service", "vgs-automation-job.timer"]);
        assert.equal(manual(w, engine, id).status, 0);
        assert.equal(cli(w, engine, ["remove", id]).stdout.trim().split("\n").pop(), "removed=job");
        same(fs.readdirSync(w.units), []);
        same(runFiles(w), [], "remove drops the automation's runs");
        same(JSON.parse(fs.readFileSync(w.store, "utf8")).automations, []);
        assert.equal(cli(w, engine, ["remove", id]).first, "automations: refused: id=unknown value=job");
    },

    "a run that succeeds writes both records and its transcript"(engine) {
        const w = world();
        const id = add(w, engine, { command: "echo one; echo two >&2; cat " + JSON.stringify(w.runs) + "/job@$VGS_AUTOMATION_RUN.started.json" });
        const out = manual(w, engine, id);
        assert.equal(out.status, 0, out.stderr);
        const rec = ended(w, id);
        same([rec.outcome, rec.exitCode, rec.signal, rec.trigger, rec.slot, rec.truncated, rec.snippet], ["succeeded", 0, null, "manual", null, false, ""]);
        assert.equal(Logic.recordError(rec, "ended"), "");
        const files = runFiles(w);
        same(files.map(n => n.replace(/@\d+-\d+/, "@R")), ["job@R.ended.json", "job@R.log", "job@R.started.json"], "no temporary file is left");
        const transcript = fs.readFileSync(rec.transcript, "utf8");
        assert.match(transcript, /^# vgs\.automations run \d+-\d+\n# automation: job \(Job\)\n# command: echo one/);
        assert.match(transcript, /\n\d\d:\d\d:\d\d\.\d{3} out \| one\n/);
        assert.match(transcript, /\n\d\d:\d\d:\d\d\.\d{3} err \| two\n/);
        assert.match(transcript, /\n\d\d:\d\d:\d\d\.\d{3} out \| \{"version":1,"automation":"job"/, "the started record is on disk before the command runs");
        assert.match(transcript, /\n# outcome: succeeded exit=0\n# duration: \d+s\n$/);
        same(calls(w, "notify-send"), [], "a success sends nothing without notifyEveryRun");
    },

    "a failing run sends the error notification whatever the toggle"(engine) {
        const w = world();
        const id = add(w, engine, { name: "Nightly <sync>", command: "echo fine; echo 'disk full' >&2; exit 3" });
        assert.equal(manual(w, engine, id).status, 1);
        const rec = ended(w, id);
        same([rec.outcome, rec.exitCode, rec.snippet], ["failed", 3, "disk full"]);
        same(calls(w, "notify-send"), [["--app-name=Automations", "--urgency=critical", "--print-id", "--hint=string:x-vgs-avatar:calendar-clock", "--hint=string:x-vgs-icon:circle-x", "--hint=string:x-vgs-tone:danger", "--hint=string:x-vgs-click:open", "--hint=string:x-vgs-open:" + rec.transcript, "--", "Nightly <sync> failed", "The automation failed. Open Automations to read its output."]]);
    },

    "notifyEveryRun sends the start, then replaces it with the finish"(engine) {
        const w = world();
        const id = add(w, engine, { notifyEveryRun: true });
        assert.equal(manual(w, engine, id).status, 0);
        const rec = ended(w, id);
        same(calls(w, "notify-send"), [
            ["--app-name=Automations", "--urgency=low", "--print-id", "--hint=string:x-vgs-avatar:calendar-clock", "--hint=string:x-vgs-icon:play", "--hint=string:x-vgs-tone:warning", "--hint=string:x-vgs-click:none", "--", "Job started", "The automation is running."],
            ["--app-name=Automations", "--urgency=low", "--print-id", "--hint=string:x-vgs-avatar:calendar-clock", "--hint=string:x-vgs-icon:circle-check", "--hint=string:x-vgs-tone:success", "--hint=string:x-vgs-click:open", "--hint=string:x-vgs-open:" + rec.transcript, "--replace-id=41", "--", "Job finished", "Finished in 0s"]
        ]);
    },

    "repeated failures replace one notice and a success recovers it"(engine) {
        const w = world();
        const flag = path.join(w.root, "fail");
        const streakFile = id => path.join(w.home, ".local", "state", "vgshell", "automations", "streak", id + ".json");
        const sends = () => calls(w, "notify-send").map(c => [c.filter(a => /^--(urgency|replace-id)=/.test(a)), c.slice(-2)[0], c.slice(-1)[0].split("\n")[0]]);
        write(flag, "");
        const quiet = add(w, engine, { name: "Pull", command: "test ! -e " + JSON.stringify(flag) });
        for (let k = 0; k < 3; k++) assert.equal(manual(w, engine, quiet).status, 1);
        const firstStart = Math.min(...runFiles(w).filter(n => n.endsWith(".ended.json")).map(n => JSON.parse(fs.readFileSync(path.join(w.runs, n), "utf8")).startedAt));
        same(JSON.parse(fs.readFileSync(streakFile(quiet), "utf8")), { notice: { id: 41, server: BUS + " :1.7" }, failures: 3, since: firstStart }, "the open failure notice is kept per automation");
        fs.rmSync(flag);
        assert.equal(manual(w, engine, quiet).status, 0);
        assert.equal(fs.existsSync(streakFile(quiet)), false, "a success closes the streak");
        const failure = "The automation failed. Open Automations to read its output.";
        const quietSends = sends();
        same(quietSends.map(([flags, summary]) => [flags, summary]), [
            [["--urgency=critical"], "Pull failed"],
            [["--urgency=critical", "--replace-id=41"], "Pull failed"],
            [["--urgency=critical", "--replace-id=41"], "Pull failed"],
            [["--urgency=low", "--replace-id=41"], "Pull recovered"]
        ]);
        same([quietSends[0][2], quietSends[1][2].replace(/since .*/, "since"), quietSends[2][2].replace(/since .*/, "since")], [failure, "Failed 2 times since", "Failed 3 times since"]);
        // With notifyEveryRun the start takes the open notice's place, so a
        // run still shows one notice.
        fs.rmSync(path.join(w.stub, "notify-send.calls"));
        write(flag, "");
        const loud = add(w, engine, { name: "Loud", command: "test ! -e " + JSON.stringify(flag), notifyEveryRun: true });
        assert.equal(manual(w, engine, loud).status, 1);
        fs.rmSync(flag);
        assert.equal(manual(w, engine, loud).status, 0);
        same(sends().map(([flags, summary]) => [flags, summary]), [
            [["--urgency=low"], "Loud started"],
            [["--urgency=critical", "--replace-id=41"], "Loud failed"],
            [["--urgency=low", "--replace-id=41"], "Loud started"],
            [["--urgency=low", "--replace-id=41"], "Loud recovered"]
        ]);
        write(flag, "");
        assert.equal(manual(w, engine, loud).status, 1);
        assert.equal(fs.existsSync(streakFile(loud)), true);
        assert.equal(cli(w, engine, ["remove", loud]).status, 0);
        assert.equal(fs.existsSync(streakFile(loud)), false, "remove drops the streak");
    },

    "a notice from another notification server is never replaced"(engine) {
        const w = world();
        const owner = path.join(w.stub, "owner");
        const streakFile = id => path.join(w.home, ".local", "state", "vgshell", "automations", "streak", id + ".json");
        const replaced = () => calls(w, "notify-send").map(c => c.filter(a => a.startsWith("--replace-id=")));
        const notice = id => JSON.parse(fs.readFileSync(streakFile(id), "utf8")).notice;
        const failing = add(w, engine, { name: "Pull", command: "false" });
        assert.equal(manual(w, engine, failing).status, 1);
        same(notice(failing), { id: 41, server: BUS + " :1.7" });
        // A restarted shell owns the name under a new unique name on the
        // same bus, and hands out ids from 1 again.
        write(owner, ":1.9\n");
        assert.equal(manual(w, engine, failing).status, 1);
        same(notice(failing), { id: 42, server: BUS + " :1.9" }, "the notice is the new server's");
        // A fresh bus, after a new login or a reboot, can give the shell
        // the unique name the old bus gave it.
        write(path.join(w.stub, "bus"), "0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f\n");
        assert.equal(manual(w, engine, failing).status, 1);
        // No server owns the name: nothing to check the notice against.
        write(owner, "");
        assert.equal(manual(w, engine, failing).status, 1);
        same(notice(failing), null, "a notice from an unknown server is none");
        assert.equal(JSON.parse(fs.readFileSync(streakFile(failing), "utf8")).failures, 4);
        same(replaced(), [[], [], [], []], "no failure replaced a notice of another server");
        // The shell restarts while a run is live: the end does not replace
        // the start.
        fs.rmSync(path.join(w.stub, "notify-send.calls"));
        write(owner, ":1.7\n");
        const loud = add(w, engine, { name: "Loud", command: "echo :1.11 > " + JSON.stringify(owner), notifyEveryRun: true });
        assert.equal(manual(w, engine, loud).status, 0);
        same(replaced(), [[], []], "the end replaced nothing of the new server");
    },

    "a timeout ends the command's whole process group"(engine) {
        const w = world();
        const pidFile = path.join(w.root, "grandchild.pid");
        // The background child holds the output pipe, so a run whose timeout
        // misses it cannot end before its sleep does. A sleep as long as the
        // bound keeps that run past the bound whatever the host's load; the
        // bound leaves a run that ends at its 1 s timeout room to finish on
        // a loaded host.
        const bound = 15;
        const id = add(w, engine, { command: "sh -c 'sleep " + bound + " & echo $! > " + pidFile + "; wait'", timeoutSeconds: 1 });
        const started = Date.now();
        assert.equal(manual(w, engine, id).status, 1);
        assert.ok(Date.now() - started < bound * 1000, "the timeout ended the run");
        const rec = ended(w, id);
        same([rec.outcome, rec.reason], ["timeout", "timeout=1s"]);
        const pid = Number(fs.readFileSync(pidFile, "utf8"));
        let alive = true;
        try {
            process.kill(pid, 0);
        } catch (_e) {
            alive = false;
        }
        if (alive) process.kill(pid, "SIGKILL");
        assert.equal(alive, false, "the command's background child was ended too");
        assert.match(calls(w, "notify-send")[0].slice(-1)[0], /^Timed out after 1s/);
    },

    "a missing working directory is a failed start"(engine) {
        const w = world();
        const id = add(w, engine, { workingDirectory: path.join(w.root, "gone") });
        assert.equal(manual(w, engine, id).status, 1);
        const rec = ended(w, id);
        same([rec.outcome, rec.exitCode, rec.reason], ["failed-start", null, "directory=ENOENT path=" + path.join(w.root, "gone")]);
        assert.equal(calls(w, "notify-send")[0].slice(-1)[0], "The work folder is unavailable. Choose another folder in Automations.");
    },

    "a refused store is a failed start the user is told of"(engine) {
        const w = world();
        const id = add(w, engine, {});
        fs.writeFileSync(w.store, "{ broken");
        assert.equal(cli(w, engine, ["list"]).first, "automations: refused: store=store:-not-json");
        assert.equal(manual(w, engine, id).status, 1);
        same([ended(w, id).outcome, ended(w, id).reason], ["failed-start", "store=store:-not-json"]);
        assert.equal(calls(w, "notify-send")[0].slice(-2)[0], "job failed");
    },

    "the transcript stops at its cap and the run goes on"(engine) {
        const w = world();
        const id = add(w, engine, { command: "yes line | head -n 70000; echo last" });
        assert.equal(manual(w, engine, id).status, 0);
        const rec = ended(w, id);
        assert.equal(rec.truncated, true);
        const text = fs.readFileSync(rec.transcript, "utf8");
        assert.ok(Buffer.byteLength(text) < Logic.TRANSCRIPT_MAX_BYTES + 4096, "the transcript holds the cap and its header and footer");
        assert.match(text, /\n# transcript cut at \d+ bytes; later output is not kept\n/);
        assert.doesNotMatch(text, / out \| last\n/, "output past the cap is dropped");
        assert.match(text, /\n# outcome: succeeded exit=0\n/, "the footer is written past the cap");
    },

    "output with no line break reaches the transcript in pieces"(engine) {
        const w = world();
        // 20000 characters, one line break, then a short line, under the
        // cap, in one write(2) to the pipe, so the runner reads the long
        // line whole with its break and must split it itself.
        const long = add(w, engine, { name: "Long", command: "python3 -c 'import os; os.write(1, b\"y\" * 20000 + b\"\\nafter\\n\")'" });
        assert.equal(manual(w, engine, long).status, 0);
        const rec = ended(w, long);
        const text = fs.readFileSync(rec.transcript, "utf8");
        const pieces = text.split("\n").filter(line => / out \| y+$/.test(line)).map(line => line.length - line.indexOf("| ") - 2);
        same([rec.truncated, pieces], [false, [Logic.TRANSCRIPT_LINE_MAX, Logic.TRANSCRIPT_LINE_MAX, 20000 - 2 * Logic.TRANSCRIPT_LINE_MAX]], "a long line arrives as pieces of the line ceiling");
        assert.match(text, / out \| after\n/, "the line after the long one follows it");
        // 3 MB with no line break at all: the runner holds one piece at a
        // time, so the transcript fills to its cap with pieces while the
        // pipe drains. A runner that kept the line whole would write none of
        // it, since the one line passes the cap.
        const flat = add(w, engine, { name: "Flat", command: "head -c 3000000 /dev/zero | tr '\\0' x" });
        assert.equal(manual(w, engine, flat).status, 0);
        const cut = ended(w, flat);
        const flatText = fs.readFileSync(cut.transcript, "utf8");
        assert.equal(cut.truncated, true);
        assert.match(flatText, new RegExp(" out \\| x{" + Logic.TRANSCRIPT_LINE_MAX + "}\\n"), "the first pieces are in the transcript");
        assert.ok(Buffer.byteLength(flatText) < Logic.TRANSCRIPT_MAX_BYTES + 4096, "the transcript holds the cap");
        assert.match(flatText, /\n# transcript cut at \d+ bytes; later output is not kept\n[^]*\n# outcome: succeeded exit=0\n/, "the marker and the footer follow the pieces");
    },

    "a timed-out run ends after a descendant that ignores SIGTERM"(engine) {
        const w = world();
        const pidFile = path.join(w.root, "stubborn.pid");
        const script = path.join(w.root, "stubborn.sh");
        // The descendant ignores SIGTERM and lets go of the output pipes, so
        // the shell's end closes them while it lives on.
        write(script, "#!/bin/sh\nsh -c 'trap \"\" TERM; exec </dev/null >/dev/null 2>&1; echo $$ >\"$1\"; exec sleep 60' sh \"$1\" &\nexec sleep 60\n", 0o755);
        const id = add(w, engine, { command: "sh " + script + " " + pidFile, timeoutSeconds: 1 });
        const started = Date.now();
        assert.equal(manual(w, engine, id).status, 1);
        const took = Date.now() - started;
        const pid = Number(fs.readFileSync(pidFile, "utf8"));
        let alive = true;
        try {
            process.kill(pid, 0);
        } catch (_e) {
            alive = false;
        }
        if (alive) process.kill(pid, "SIGKILL");
        assert.equal(alive, false, "the SIGTERM-proof descendant was killed before the run ended");
        assert.ok(took >= Logic.KILL_GRACE_MS, "the run waited for the SIGKILL: " + took + " ms");
        same([ended(w, id).outcome, ended(w, id).reason], ["timeout", "timeout=1s"]);
    },

    "a scheduled trigger runs only what the guard allows"(engine) {
        const w = world();
        const now = new Date();
        const pad = n => String(n).padStart(2, "0");
        const today = now.getFullYear() + "-" + pad(now.getMonth() + 1) + "-" + pad(now.getDate());
        const id = add(w, engine, { schedule: { frequency: "daily", interval: 1, times: [pad(now.getHours()) + ":" + pad(now.getMinutes())], start: today, end: { type: "never" } } });
        const skipped = cli(w, engine, ["run", "--scheduled", id]);
        same([skipped.status, skipped.first], [0, "automations: skipped=job reason=handled"], "add marked the occurrence due now handled");
        same(runFiles(w), []);
        write(path.join(w.home, ".local", "state", "vgshell", "automations", "guard", "job.json"), JSON.stringify({ handledThrough: 0 }));
        assert.equal(cli(w, engine, ["run", "--scheduled", id]).status, 0);
        const rec = ended(w, id);
        same([rec.trigger, typeof rec.slot], ["scheduled", "number"]);
        assert.equal(cli(w, engine, ["run", "--scheduled", id]).first, "automations: skipped=job reason=handled", "one occurrence runs once");
        assert.equal(JSON.parse(fs.readFileSync(path.join(w.home, ".local", "state", "vgshell", "automations", "guard", "job.json"), "utf8")).handledThrough, rec.slot);
        assert.equal(cli(w, engine, ["disable", id]).status, 0);
        assert.equal(cli(w, engine, ["run", "--scheduled", id]).first, "automations: skipped=job reason=paused");
    },

    "network requirements admit FULL alone and local commands bypass NM"(engine) {
        const table = [
            ["0", "unavailable", "connectivity", 0, null, null],
            ["1", "grace", "connectivity", 0, null, null],
            ["2", "grace", "connectivity", 0, null, null],
            ["3", "grace", "connectivity", 0, null, null],
            ["99", "unavailable", "invalid-reply", 0, null, null],
            ["", "unavailable", "exit", 1, null, null],
            ["kill", "unavailable", "signal", null, "SIGTERM", null],
            ["hang", "unavailable", "timeout", null, "SIGTERM", 5000],
            [null, "unavailable", "missing-command", null, null, null]
        ];
        for (const [value, diagnostic, category, exit, signal, timeoutMs] of table) {
            const { w, id, due } = networkWorld(engine, { value: value });
            const runner = startRunner(w, engine, id, "scheduled");
            try {
                waitFor(() => {
                    same(runFiles(w).filter(n => n.endsWith(".started.json")), [], "a non-FULL prerequisite never starts a command");
                    return listed(w, engine, id).pending?.diagnostic === diagnostic;
                }, "the pending diagnostic " + value);
                // nm-reads is an acknowledgement that the production read
                // reached the stub; missing busctl has no such child.
                if (value !== null) waitFor(() => fs.existsSync(path.join(w.stub, "nm-reads")), "the connectivity read");
                waitFor(() => networkLogs(runner).some(out => out.operation === "get-property"), "the structured connectivity result");
                const cause = networkLogs(runner).find(out => out.operation === "get-property");
                same([cause.id, cause.command, cause.category, cause.exit, cause.signal, cause.timeoutMs], [id, "busctl", category, exit, signal, timeoutMs]);
                if (category === "connectivity") same(cause.connectivity, Number(value));
                if (category === "invalid-reply" || category === "exit") assert.ok(cause.detail.length > 0 && cause.detail.length <= 512);

                same([runFiles(w).filter(n => n.includes("@")), calls(w, "notify-send")], [[], []], "non-FULL " + value + " starts and notifies nothing");
                same([listed(w, engine, id).state, listed(w, engine, id).pending.dueAt], ["waiting", due]);
                assert.equal(cli(w, engine, ["cancel", id]).stdout, "cancelled=" + id + "\n");
                same([ended(w, id).outcome, ended(w, id).reason, ended(w, id).durationMs, ended(w, id).exitCode], ["skipped", "cancelled-before-start", 0, null]);
                same(calls(w, "notify-send"), [], "cancellation stays quiet");
            } finally { stopRunner(runner); }
            const local = world();
            write(path.join(local.stub, "nm"), "hang");
            const localId = add(local, engine, { requiresNetwork: false });
            assert.equal(manual(local, engine, localId).status, 0);
            assert.equal(fs.existsSync(path.join(local.stub, "nm-reads")), false, "local work reads no NM property");
        }
        for (const trigger of ["scheduled", "manual"]) {
            const { w, id } = networkWorld(engine, { value: "4" });
            const out = cli(w, engine, ["run", "--" + trigger, id]);
            assert.equal(out.status, 0, out.stderr);
            same([ended(w, id).trigger, ended(w, id).outcome], [trigger, "succeeded"]);
            assert.equal(listed(w, engine, id).pending, null);
        }
    },

    "network wait failure transitions retain causes and suppress identical retries"(engine) {
        const { w, id } = networkWorld(engine);
        // A refused busctl wait is a supported older/unavailable bus path.
        // Its arbitrarily long stderr must remain bounded in the journal.
        write(path.join(w.stub, "nm-wait-failure"), "x".repeat(8192) + "\n");
        const runner = startRunner(w, engine, id, "manual");
        try {
            waitFor(() => waits(w) >= 1, "the actual failed signal-wait operation");
            waitFor(() => networkLogs(runner).some(out => out.operation === "wait"), "the wait operation's structured cause");
            waitFor(() => waits(w) >= 3, "two completed retry/backoff iterations", 20000);
            const logs = networkLogs(runner);
            const failures = logs.filter(out => out.operation === "wait");
            same(failures.length, 1, "identical wait failures emit one transition");
            const cause = failures[0];
            same([cause.id, cause.command, cause.category, cause.exit, cause.signal, cause.timeoutMs, cause.detail.length], [id, "busctl", "exit", 23, null, null, 512]);
            same(logs.filter(out => out.operation === "get-property").map(out => out.connectivity), [1], "unchanged reads do not alternate into repeated wait errors");
            same([runFiles(w).filter(n => n.includes("@")), calls(w, "notify-send")], [[], []]);
            write(path.join(w.stub, "nm"), "4");
            waitFor(() => runFiles(w).some(n => n.endsWith(".ended.json")), "FULL admission after failed signal waits");
            same(ended(w, id).outcome, "succeeded");
            same(networkLogs(runner).filter(out => out.operation === "get-property").map(out => out.connectivity), [1, 4], "the changed read logs recovery");
        } finally { stopRunner(runner); }
    },

    "scheduled finalization never moves handled time backward"(engine) {
        // The scheduler's Date.now can move backward after time correction.
        // Every scheduled finalizer consumes the same persisted high water.
        for (const [requiresNetwork, action] of [[false, "trigger"], [true, "trigger"], [true, "cancel"], [true, "edit"], [true, "disable"]]) {
            const w = world({ nowMs: NETWORK_DUE });
            write(path.join(w.stub, "nm"), "4");
            const events = path.join(w.root, "commands");
            const id = add(w, engine, { requiresNetwork, command: "echo once >> " + JSON.stringify(events), schedule: { frequency: "minutely", interval: 1, start: "2026-10-30", end: { type: "never" }, zone: "utc" } });
            const guard = path.join(w.home, ".local/state/vgshell/automations/guard", id + ".json");
            write(guard, JSON.stringify({ handledThrough: 0 }));
            const fire = () => { const out = cli(w, engine, ["run", "--scheduled", id]); assert.equal(out.status, 0, out.stderr); };
            const handled = () => JSON.parse(fs.readFileSync(guard, "utf8")).handledThrough;
            const commands = () => fs.readFileSync(events, "utf8").trim().split("\n").length;
            fire();
            same([handled(), commands()], [NETWORK_DUE, 1]);
            let runner = null;
            try {
                if (action !== "trigger") {
                    clockAt(w, NETWORK_DUE + 60000, 1);
                    write(path.join(w.stub, "nm"), "1");
                    runner = startRunner(w, engine, id, "scheduled");
                    waitFor(() => waits(w) >= 1, "the future slot's retained wait before clock correction");
                }
                clockAt(w, NETWORK_DUE - 4 * 60000, 2);
                if (action === "trigger") fire();
                else {
                    const args = action === "edit" ? ["edit", id, "--definition", JSON.stringify({ name: "Edited" })] : [action, id];
                    assert.equal(cli(w, engine, args).status, 0);
                }
                same([handled(), commands()], [NETWORK_DUE, 1], "the " + action + " finalizer preserves newer handled time, network=" + requiresNetwork);
                if (action === "trigger") {
                    for (const offset of [-3, 0]) { clockAt(w, NETWORK_DUE + offset * 60000, 3); fire(); }
                    same([handled(), commands()], [NETWORK_DUE, 1], "no occurrence before the clock correction repeats");
                    clockAt(w, NETWORK_DUE + 60000, 4); fire();
                    same([handled(), commands()], [NETWORK_DUE + 60000, 2], "a strictly newer slot still runs");
                }
            } finally { if (runner !== null) stopRunner(runner); }
        }
    },

    "reconnect admits once after grace without spending wall-clock grace"(engine) {
        const { w, id, due } = networkWorld(engine);
        const runner = startRunner(w, engine, id, "scheduled");
        try {
            waitFor(() => waits(w) >= 1, "the PropertiesChanged wait");
            same([listed(w, engine, id).pending.diagnostic, runFiles(w).filter(n => n.includes("@"))], ["grace", []]);
            // A forward wall step inside the ten-minute rule cannot spend
            // active grace, whose monotonic source is separately injected.
            clockAt(w, due + 6 * 60000, 1);
            write(path.join(w.stub, "nm"), "2");
            waitFor(() => waits(w) >= 2, "the next property wait after the wall step");
            same(listed(w, engine, id).pending.diagnostic, "grace");
            clockAt(w, due + 6 * 60000, 60001);
            write(path.join(w.stub, "nm"), "3");
            waitFor(() => listed(w, engine, id).pending?.diagnostic === "offline", "active grace expiry");
            same(runFiles(w).filter(n => n.includes("@")), [], "grace expiry grants no offline admission");
            const admittedAt = due + 6 * 60000;
            write(path.join(w.stub, "nm"), "4");
            waitFor(() => runFiles(w).some(n => n.endsWith(".ended.json")), "the reconnect run");
            same([ended(w, id).outcome, ended(w, id).startedAt, ended(w, id).slot], ["succeeded", admittedAt, due]);
            waitFor(() => !runnerAlive(runner), "the reconnect owner releases its lock");
            assert.equal(cli(w, engine, ["run", "--scheduled", id]).status, 0);
            same(runFiles(w).filter(n => n.endsWith(".ended.json")).length, 1, "one retained wait runs once");
        } finally { stopRunner(runner); }
    },

    "offline lateness skips neutrally or catches up the latest once"(engine) {
        for (const [catchUp, latest, outcome] of [[false, false, "skipped"], [true, false, "succeeded"], [true, true, "succeeded"]]) {
            const { w, id, due } = networkWorld(engine, { catchUp: catchUp, minutely: latest });
            const runner = startRunner(w, engine, id, "scheduled");
            try {
                waitFor(() => waits(w) >= 1, "the retained offline attempt");
                const original = listed(w, engine, id).pending.dueAt;
                clockAt(w, due + 2 * 60 * 60000, 60001);
                write(path.join(w.stub, "nm"), "2");
                if (!catchUp) {
                    waitFor(() => runFiles(w).some(n => n.endsWith(".ended.json")), "the ordinary late skip while still offline");
                    same([ended(w, id).reason, ended(w, id).exitCode, ended(w, id).signal, ended(w, id).durationMs], ["network-offline-late", null, null, 0]);
                    same(runFiles(w).filter(n => n.endsWith(".started.json")), [], "a skip starts no command");
                    same(calls(w, "notify-send"), [], "a skip sends no notice even with notifyEveryRun");
                } else {
                    waitFor(() => listed(w, engine, id).pending?.diagnostic === "offline", "offline after active grace");
                    same(listed(w, engine, id).pending.dueAt, original, "the original due time survives later slots");
                    write(path.join(w.stub, "nm"), "4");
                    waitFor(() => runFiles(w).some(n => n.endsWith(".ended.json")), "the latest catch-up command");
                }
                same([ended(w, id).outcome, ended(w, id).slot], [outcome, latest ? due + 2 * 60 * 60000 : due]);
                assert.equal(Logic.recordError(ended(w, id), "ended"), "");
                waitFor(() => !runnerAlive(runner), "the finalized attempt releases its lock");
                assert.equal(cli(w, engine, ["run", "--scheduled", id]).status, 0);
                same(runFiles(w).filter(n => n.endsWith(".ended.json")).length, 1);
            } finally { stopRunner(runner); }
        }
    },

    "edit disable remove and explicit Cancel invalidate only waiting attempts"(engine) {
        for (const action of ["edit", "disable", "remove", "cancel"]) {
            const { w, id } = networkWorld(engine);
            const runner = startRunner(w, installedEngine(w, id), id, "scheduled");
            try {
                waitFor(() => waits(w) >= 1, "the cancellable wait");
                const args = action === "edit" ? ["edit", id, "--definition", JSON.stringify({ command: "echo edited", requiresNetwork: false })] : [action, id];
                const out = cli(w, engine, args);
                assert.equal(out.status, 0, out.stderr);
                if (action !== "remove") same([ended(w, id).outcome, ended(w, id).reason], ["skipped", "cancelled-before-start"]);
                write(path.join(w.stub, "nm"), "4");
                waitFor(() => !runnerAlive(runner), "the cancelled owner exit");
                same(runFiles(w).filter(n => n.endsWith(".started.json")), [], "no old captured command starts after " + action);
                same(calls(w, "notify-send"), []);
                if (action === "remove") {
                    same(runFiles(w), [], "remove leaves no resurrected record or marker");
                    assert.equal(fs.existsSync(path.join(w.home, ".local/state/vgshell/automations/guard", id + ".json")), false);
                    const reused = add(w, engine, { name: "Pull", requiresNetwork: true });
                    same(reused, id);
                    same(listed(w, engine, id).pending, null, "reusing an id inherits no wait");
                }
            } finally { stopRunner(runner); }
        }
    },

    "manual run-now remains visible with NM unavailable and Cancel ends it"(engine) {
        const { w, id, due } = networkWorld(engine, { value: "", systemd: "down" });
        assert.equal(cli(w, engine, ["run-now", id]).status, 0);
        waitFor(() => listed(w, engine, id).pending?.diagnostic === "unavailable", "the visible manual unavailable attempt");
        same([listed(w, engine, id).state, listed(w, engine, id).pending.trigger, listed(w, engine, id).pending.dueAt], ["waiting", "manual", due + 5 * 60000]);
        clockAt(w, due + 2 * 86400000, 60001);
        same(runFiles(w).filter(n => n.includes("@")), [], "manual work has no schedule expiry");
        const marker = JSON.parse(fs.readFileSync(path.join(w.runs, id + ".pending.json"), "utf8"));
        assert.equal(cli(w, engine, ["cancel", id]).stdout, "cancelled=" + id + "\n");
        same([ended(w, id).trigger, ended(w, id).reason], ["manual", "cancelled-before-start"]);
        write(path.join(w.stub, "nm"), "4");
        waitFor(() => !identityAlive(marker.owner), "the cancelled detached manual owner exit");
        same(runFiles(w).filter(n => n.endsWith(".started.json")), []);
        same(calls(w, "notify-send"), []);
    },

    "dead owner markers are invisible and retired by the next runner"(engine) {
        const { w, id } = networkWorld(engine);
        plant(w, id, NETWORK_DUE - 1000, true);
        const runner = startRunner(w, engine, id, "scheduled");
        waitFor(() => waits(w) >= 1, "the first owner's wait");
        same(listed(w, engine, id).state, "waiting", "a crashed started record cannot borrow the waiter lock and hide its wait");
        const token = listed(w, engine, id).pending.token;
        stopRunner(runner);
        same(listed(w, engine, id).pending, null, "a crashed owner's marker is not a live wait");
        const replacement = startRunner(w, engine, id, "scheduled");
        try {
            waitFor(() => listed(w, engine, id).pending?.token !== token && listed(w, engine, id).pending !== null, "the replacement's token");
            write(path.join(w.stub, "nm"), "4");
            waitFor(() => runFiles(w).some(n => n.endsWith(".ended.json")), "the replacement's command");
            same(ended(w, id).outcome, "succeeded");
        } finally { stopRunner(replacement); }
    },

    "an admitted command survives Cancel and a saved edit"(engine) {
        const { w, id } = networkWorld(engine, { value: "4" });
        const started = path.join(w.root, "command-started");
        const release = path.join(w.root, "command-release");
        const script = path.join(w.root, "admitted.sh");
        write(script, '#!/bin/sh\n: >"$1"\nwhile test ! -e "$2"; do sleep 0.05; done\n', 0o755);
        const command = "sh " + JSON.stringify(script) + " " + JSON.stringify(started) + " " + JSON.stringify(release);
        assert.equal(cli(w, engine, ["edit", id, "--definition", JSON.stringify({ command })]).status, 0);
        const runner = startRunner(w, installedEngine(w, id), id, "manual");
        try {
            waitFor(() => fs.existsSync(started), "the admitted command's acknowledgement");
            same([listed(w, engine, id).state, listed(w, engine, id).pending], ["running", null]);
            assert.equal(cli(w, engine, ["cancel", id]).stdout, "cancelled=none\n");
            assert.equal(cli(w, engine, ["edit", id, "--definition", JSON.stringify({ command: "false", requiresNetwork: false })]).status, 0);
            same(runFiles(w).filter(n => n.endsWith(".ended.json")), [], "edit does not cancel the admitted command");
            write(release, "");
            waitFor(() => runFiles(w).some(n => n.endsWith(".ended.json")), "the admitted command's ordinary end");
            same([ended(w, id).outcome, ended(w, id).command], ["succeeded", command]);
        } finally { stopRunner(runner); }
    },

    "a late network skip preserves a real failure streak"(engine) {
        const { w, id, due } = networkWorld(engine, { value: "4" });
        assert.equal(cli(w, engine, ["edit", id, "--definition", JSON.stringify({ command: "exit 7" })]).status, 0);
        assert.equal(manual(w, engine, id).status, 1);
        const streakFile = path.join(w.home, ".local/state/vgshell/automations/streak", id + ".json");
        const before = fs.readFileSync(streakFile, "utf8");
        const sends = calls(w, "notify-send").length;
        assert.equal(cli(w, engine, ["clear", id]).status, 0);
        assert.equal(cli(w, engine, ["edit", id, "--definition", JSON.stringify({ command: "true" })]).status, 0);
        write(path.join(w.stub, "nm"), "1");
        const runner = startRunner(w, engine, id, "scheduled");
        try {
            waitFor(() => waits(w) >= 1, "the wait following a real failure");
            clockAt(w, due + 600001, 60001);
            write(path.join(w.stub, "nm"), "2");
            waitFor(() => runFiles(w).some(n => n.endsWith(".ended.json")), "the late skip following the failure");
            same([ended(w, id).outcome, calls(w, "notify-send").length, fs.readFileSync(streakFile, "utf8")], ["skipped", sends, before]);
        } finally { stopRunner(runner); }
    },

    "first-read conversion and a concurrent edit share the store lock"(engine) {
        const w = world();
        const id = add(w, engine, {});
        const old = JSON.parse(fs.readFileSync(w.store, "utf8"));
        old.version = 1;
        for (const automation of old.automations) delete automation.requiresNetwork;
        write(w.store, JSON.stringify(old));
        const lock = path.join(w.home, ".local/state/vgshell/automations/locks/store.lock");
        const release = holdLock(w, lock);
        let held = true;
        const barrier = path.join(w.root, "flock-arrivals");
        fs.mkdirSync(barrier);
        // Both real engine entries acknowledge their arrival at flock
        // before the fixture releases the store lock. The real flock still
        // orders every transaction; this wrapper changes no lock result.
        write(path.join(w.root, "bin/flock"), "#!/bin/sh\nfor word do case \"$word\" in */store.lock) touch " + JSON.stringify(barrier) + "/$$ ;; esac; done\nexec " + JSON.stringify(path.join(w.root, "tools/flock")) + " \"$@\"\n", 0o755);
        const children = [];
        try {
            for (const args of [["list", "--json"], ["edit", id, "--definition", JSON.stringify({ command: "echo concurrent" })]]) {
                const file = path.join(w.root, "concurrent-" + children.length + ".out");
                const fd = fs.openSync(file, "w");
                const child = childProcess.spawn(engine, ["--tree", repo].concat(args), { env: w.env, cwd: w.home, detached: true, stdio: ["ignore", fd, fd] });
                fs.closeSync(fd);
                runners.add(child);
                children.push({ child, file });
            }
            waitFor(() => fs.readdirSync(barrier).length >= 2, "both first-read callers reaching the store lock");
            same(JSON.parse(fs.readFileSync(w.store, "utf8")).version, 1, "conversion cannot write past the held lock");
            release();
            held = false;
            for (const { child, file } of children) {
                waitFor(() => !runnerAlive(child), "the concurrent reader/editor to finish");
                assert.doesNotMatch(fs.readFileSync(file, "utf8"), /automations: refused:/);
            }
            const current = JSON.parse(fs.readFileSync(w.store, "utf8"));
            same([current.version, current.automations[0].requiresNetwork, current.automations[0].command], [2, false, "echo concurrent"]);
        } finally {
            if (held) release();
            for (const { child } of children) stopRunner(child);
        }
    },

    "v1 store conversion precedes list and engine-copy reads"(engine) {
        for (const verb of ["list", "run"]) {
            const w = world();
            const id = add(w, engine, { command: "echo converted", catchUp: true });
            const service = fs.readFileSync(path.join(w.units, "vgs-automation-" + id + ".service"), "utf8");
            const copy = /"([^"\n]*\/engine\/[0-9a-f]{16}\/bin\/automations)"/.exec(service)[1];
            const current = JSON.parse(fs.readFileSync(w.store, "utf8"));
            const old = JSON.parse(JSON.stringify(current));
            old.version = 1;
            for (const automation of old.automations) delete automation.requiresNetwork;
            write(w.store, JSON.stringify(old));
            const out = cli(w, verb === "run" ? copy : engine, verb === "run" ? ["run", "--manual", id] : ["list", "--json"]);
            assert.equal(out.status, 0, out.stderr);
            same(JSON.parse(fs.readFileSync(w.store, "utf8")), current, "conversion preserves every old value and adds the false default");
            const stamp = fs.statSync(w.store).mtimeMs;
            assert.equal(cli(w, engine, ["list", "--json"]).status, 0);
            same(fs.statSync(w.store).mtimeMs, stamp, "the current store is not converted again");
        }
    },

    "an every-10-minutes automation runs its latest slot once per trigger"(engine) {
        const w = world();
        const TEN = 10 * 60 * 1000;
        // The two triggers below must fall in one slot: a run takes well
        // under the 15 s kept clear of the next boundary.
        const toBoundary = TEN - Date.now() % TEN;
        if (toBoundary < 15000) childProcess.spawnSync("sleep", [String((toBoundary + 100) / 1000)]);
        const today = new Date().toISOString().slice(0, 10);
        const schedule = { frequency: "minutely", interval: 10, start: today, end: { type: "never" } };
        for (const catchUp of [false, true]) {
            const id = add(w, engine, { name: "Ten " + catchUp, schedule: schedule, catchUp: catchUp });
            const timer = fs.readFileSync(path.join(w.units, "vgs-automation-" + id + ".timer"), "utf8");
            same(timer.split("\n").filter(line => /^(OnCalendar|Persistent)=/.test(line)), ["OnCalendar=*-*-* *:00/10:00", "Persistent=" + catchUp], "the timer of " + id);
            // The last slot handled 25 minutes back: two slots went by.
            const handled = Date.now() - 25 * 60 * 1000;
            write(path.join(w.home, ".local", "state", "vgshell", "automations", "guard", id + ".json"), JSON.stringify({ handledThrough: handled }));
            assert.equal(cli(w, engine, ["run", "--scheduled", id]).status, 0);
            const rec = ended(w, id);
            same([rec.trigger, rec.outcome, rec.slot % TEN, rec.slot > handled, rec.startedAt - rec.slot < TEN], ["scheduled", "succeeded", 0, true, true], "the latest slot ran, catch-up " + catchUp);
            assert.equal(cli(w, engine, ["run", "--scheduled", id]).first, "automations: skipped=" + id + " reason=handled", "a second trigger in the slot runs nothing, catch-up " + catchUp);
            same(runFiles(w).filter(n => n.startsWith(id + "@") && n.endsWith(".ended.json")).length, 1, "one run, never one per missed slot");
        }
        const cron = world({ systemd: "down" });
        const id = add(cron, engine, { name: "Ten cron", schedule: schedule });
        const lines = fs.readFileSync(path.join(cron.stub, "crontab"), "utf8").split("\n").filter(line => line.endsWith("'run' '--scheduled' '" + id + "'"));
        same(lines.map(line => line.split(" env ")[0]), ["*/10 * * * *"], "one crontab line every 10 minutes");
    },

    "run-now goes through systemd-run and refuses a busy automation"(engine) {
        const w = world();
        const id = add(w, engine, {});
        const out = cli(w, engine, ["run-now", id]);
        assert.equal(out.stdout, "started=job\n", out.stderr);
        const call = calls(w, "systemd-run")[0];
        same(call.slice(0, 3), ["--user", "--collect", "--quiet"]);
        assert.match(call[3], /^--unit=vgs-automation-job-now-\d+$/);
        same(call.slice(4, 7).map(a => a.replace(/=.*/, "")), ["--setenv", "--setenv", "--setenv"]);
        same(call.slice(7, 13).map(a => a.replace(/^.*\//, "")), ["--", "flock", "-n", "-E", "75", "-o"]);
        same(call.slice(-3), ["run", "--manual", "job"]);
        same(ended(w, id).trigger, "manual");
        const lock = path.join(w.home, ".local", "state", "vgshell", "automations", "locks", "job.lock");
        const release = holdLock(w, lock);
        try {
            const busy = cli(w, engine, ["run-now", id]);
            same([busy.status, busy.first], [1, "automations: refused: run=busy id=job"]);
        } finally {
            release();
        }
        assert.equal(calls(w, "systemd-run").length, 1, "a busy automation starts nothing");
    },

    "history names a running and a vanished run"(engine) {
        const w = world();
        const id = add(w, engine, { command: "sleep 5" });
        const lock = path.join(w.home, ".local", "state", "vgshell", "automations", "locks", "job.lock");
        const runner = childProcess.spawn("flock", ["-n", "-E", "75", "-o", lock, engine, "--tree", repo, "run", "--manual", id], { stdio: "ignore", env: w.env, detached: true });
        try {
            // flock takes the lock before the runner starts, so the lock is
            // held once the started record is there.
            waitFor(() => runFiles(w).some(n => n.endsWith(".started.json")), "the started record");
            same(JSON.parse(cli(w, engine, ["history", "--json"]).stdout).rows[0].outcome, "running");
            // The run's lock goes with its whole group, the runner and
            // flock alike, as a killed service's cgroup does.
            process.kill(-runner.pid, "SIGKILL");
            waitFor(() => JSON.parse(cli(w, engine, ["history", "--json"]).stdout).rows[0].outcome === "vanished", "the vanished run");
        } finally {
            try { process.kill(-runner.pid, "SIGKILL"); } catch (_e) { /* gone */ }
        }
        const text = cli(w, engine, ["history", id]).stdout;
        assert.match(text, /^job\t\d+-\d+\tvanished\t\/.*\.log\n$/);
    },

    "clear keeps a running run and prune keeps the retention"(engine) {
        const w = world();
        const DAY = 24 * 60 * 60 * 1000;
        for (const [id, age] of [["a", 31], ["a", 2], ["b", 40], ["b", 0]]) plant(w, id, Date.now() - age * DAY - 1000);
        assert.equal(cli(w, engine, ["prune", "--days", "30"]).stdout, "pruned=2\n");
        same(runFiles(w).map(n => n.replace(/@\d+-\d+/, "@R")), ["a@R.ended.json", "a@R.log", "b@R.ended.json", "b@R.log"]);
        // The plugin's historyDays setting, read through vgshell plugin settings.
        write(path.join(w.home, ".config", "vgshell", "shell.json"), JSON.stringify({ version: 1, plugins: [{ id: "vgs.automations", historyDays: 1 }] }));
        const pruned = cli(w, engine, ["prune"]);
        assert.equal(pruned.stdout, "pruned=1\n", pruned.stderr);
        same(runFiles(w).map(n => n.slice(0, 2)), ["b@", "b@"]);
        plant(w, "b", Date.now() - 5000, true);
        const lock = path.join(w.home, ".local", "state", "vgshell", "automations", "locks", "b.lock");
        const release = holdLock(w, lock);
        try {
            assert.ok(JSON.parse(cli(w, engine, ["history", "--json"]).stdout).rows.some(r => r.outcome === "running"), "the held lock is a running run");
            assert.equal(cli(w, engine, ["clear", "b"]).stdout, "cleared=1\n");
            same(JSON.parse(cli(w, engine, ["history", "--json"]).stdout).rows.map(r => r.outcome), ["running"]);
        } finally {
            release();
        }
        waitFor(() => JSON.parse(cli(w, engine, ["history", "--json"]).stdout).rows.every(r => r.outcome === "vanished"), "the released lock");
        assert.equal(cli(w, engine, ["clear", "--all"]).stdout, "cleared=1\n");
        same(runFiles(w), []);
    },

    "without a systemd user manager sync keeps a crontab block"(engine) {
        const w = world({ systemd: "down" });
        const id = add(w, engine, { schedule: { frequency: "monthly", interval: 1, monthly: { by: "weekday", week: 2, weekday: "tue" }, times: ["09:00"], start: "2026-01-01", end: { type: "never" } } });
        same(calls(w, "systemctl"), [["--user", "show-environment"]], "no unit is written");
        same(calls(w, "crontab"), [["-l"], ["-"]], "a user without a table gets one");
        const block = fs.readFileSync(path.join(w.stub, "crontab"), "utf8");
        write(path.join(w.stub, "crontab"), "MAILTO=me\n5 * * * * mine\n" + block);
        const table = fs.readFileSync(path.join(w.stub, "crontab"), "utf8").split("\n");
        same(table.slice(0, 3), ["MAILTO=me", "5 * * * * mine", Logic.CRON_BEGIN]);
        assert.match(table[3], /^0 9 \* \* 2 env 'XDG_CONFIG_HOME=[^']*' 'XDG_STATE_HOME=[^']*' 'XDG_DATA_HOME=[^']*' '[^']*\/flock' '-n' '-E' '75' '-o' '[^']*\/job\.lock' '[^']*' '[^']*\/bin\/automations' '--tree' '[^']*' 'run' '--scheduled' 'job'$/);
        same(table.slice(4), [Logic.CRON_END, ""]);
        const listed = JSON.parse(cli(w, engine, ["list", "--json"]).stdout);
        same([listed.scheduler, listed.linger, listed.automations[0].summary], ["cron", "no", "Monthly on the second Tuesday at 09:00"]);
        assert.equal(cli(w, engine, ["remove", id]).status, 0);
        assert.equal(fs.readFileSync(path.join(w.stub, "crontab"), "utf8"), "MAILTO=me\n5 * * * * mine\n", "remove drops the block alone");
    },

    "under cron a catch-up automation runs a missed occurrence at startup"(engine) {
        const w = world({ systemd: "down" });
        // A daily time two hours back: the machine was off when it came.
        const missed = new Date(Date.now() - 2 * 60 * 60 * 1000);
        const time = String(missed.getUTCHours()).padStart(2, "0") + ":" + String(missed.getUTCMinutes()).padStart(2, "0");
        const schedule = { frequency: "daily", interval: 1, times: [time], start: "2026-01-01", end: { type: "never" } };
        const late = add(w, engine, { name: "Late", schedule: schedule, catchUp: true });
        const strict = add(w, engine, { name: "Strict", schedule: schedule, catchUp: false });
        const startup = fs.readFileSync(path.join(w.stub, "crontab"), "utf8").split("\n").filter(line => line.startsWith("@reboot "));
        assert.equal(startup.length, 1, "one startup line, for the automation that catches up: " + startup.join(" | "));
        assert.match(startup[0], /^@reboot env '[^']*' '[^']*' '[^']*' '[^']*\/flock' '-n' '-E' '75' '-o' '[^']*\/late\.lock' .* 'run' '--scheduled' 'late'$/, "the startup line runs the locked scheduled trigger");
        // Nothing was handled since before the missed occurrence.
        for (const id of [late, strict]) write(path.join(w.home, ".local", "state", "vgshell", "automations", "guard", id + ".json"), JSON.stringify({ handledThrough: 0 }));
        const boot = childProcess.spawnSync("sh", ["-c", startup[0].slice("@reboot ".length)], { encoding: "utf8", env: w.env, cwd: w.home, timeout: 60000 });
        assert.equal(boot.status, 0, "the startup line runs: " + boot.stderr);
        const rec = ended(w, late);
        same([rec.trigger, rec.outcome, rec.slot === null ? null : new Date(rec.slot).getUTCHours() * 60 + new Date(rec.slot).getUTCMinutes()], ["scheduled", "succeeded", missed.getUTCHours() * 60 + missed.getUTCMinutes()], "the startup trigger ran the missed occurrence");
        // Without catch-up the same trigger, as the next calendar line would
        // make it, finds the occurrence late and runs nothing.
        same([cli(w, engine, ["run", "--scheduled", strict]).first, runFiles(w).filter(n => n.startsWith(strict + "@"))], ["automations: skipped=strict reason=late", []]);
    },

    "with neither scheduler sync refuses"(engine) {
        const w = world({ systemd: "down", stubs: ["systemctl", "notify-send", "loginctl"] });
        const out = cli(w, engine, ["add", "--definition", JSON.stringify(def({}))]);
        same([out.status, out.first], [1, "automations: refused: scheduler=none"]);
    },

    "preview prints the judge's answer"(engine) {
        const w = world();
        const s = { frequency: "weekly", interval: 2, weekdays: ["mon"], times: ["09:00"], start: "2026-01-05", end: { type: "count", count: 3 } };
        const out = cli(w, engine, ["preview", "--schedule", JSON.stringify(s), "--count", "5", "--after", String(Date.parse("2026-01-01T00:00:00Z"))]);
        same(JSON.parse(out.stdout), { summary: Logic.summaryText(s), calendar: ["Mon *-*-* 09:00:00"], cron: ["0 9 * * 1"], occurrences: Logic.nextOccurrences(s, Date.parse("2026-01-01T00:00:00Z"), 5) });
        assert.equal(cli(w, engine, ["preview", "--schedule", JSON.stringify(Object.assign({}, s, { interval: 0 }))]).first, "automations: refused: schedule=schedule.interval:-want=1..99");
        same(JSON.parse(cli(world({ linger: "yes" }), engine, ["list", "--json"]).stdout).linger, "yes");
    },

    "cron scopes mixed local and UTC schedules across the November clock change"(engine) {
        const slot = Date.parse("2026-11-01T00:00:00Z");
        const w = world({ systemd: "down", timezone: "America/Los_Angeles", nowMs: slot });
        const schedule = { frequency: "monthly", interval: 1, monthly: { by: "date", day: 1 }, times: ["00:00"], start: "2026-11-01", end: { type: "never" }, zone: "utc" };
        const id = add(w, engine, { name: "UTC month end", schedule: schedule });
        const preview = cli(w, engine, ["preview", "--schedule", JSON.stringify(schedule), "--count", "3", "--after", String(Date.parse("2026-10-31T00:00:00Z"))]);
        same(JSON.parse(preview.stdout).occurrences, [slot, Date.parse("2026-12-01T00:00:00Z"), Date.parse("2027-01-01T00:00:00Z")], "CLI preview keeps the UTC month edge across Pacific month ends");
        const localSchedule = { frequency: "monthly", interval: 1, monthly: { by: "date", day: 1 }, times: ["00:00"], start: "2026-11-01", end: { type: "never" } };
        add(w, engine, { name: "Local month start", schedule: localSchedule });
        const managedTable = fs.readFileSync(path.join(w.stub, "crontab"), "utf8");
        write(path.join(w.stub, "crontab"), "MAILTO=me\n" + managedTable + "5 * * * * user-after\n");
        const table = fs.readFileSync(path.join(w.stub, "crontab"), "utf8").split("\n");
        const begin = table.indexOf(Logic.CRON_BEGIN);
        const end = table.indexOf(Logic.CRON_END);
        assert.ok(begin >= 0 && end > begin, "sync keeps one managed block");
        same(table.slice(0, begin), ["MAILTO=me"]);
        const managed = table.slice(begin + 1, end);
        const localLine = managed.findIndex(line => line.startsWith("0 0 1 * * ") && line.endsWith("'local-month-start'"));
        const utcZone = managed.indexOf("CRON_TZ=UTC");
        const utcLine = managed.findIndex(line => line.startsWith("0 0 1 * * ") && line.endsWith("'utc-month-end'"));
        const restoredZone = managed.indexOf("CRON_TZ=");
        assert.ok(localLine >= 0 && localLine < utcZone && utcZone < utcLine && utcLine < restoredZone, "local timing precedes UTC, then the daemon timezone is restored inside VGS markers");
        same(table.slice(end + 1), ["5 * * * * user-after", ""], "the user's later entry stays after the managed block");
        write(path.join(w.home, ".local", "state", "vgshell", "automations", "guard", id + ".json"), JSON.stringify({ handledThrough: Date.parse("2026-10-01T00:00:00Z") }));
        const run = cli(w, engine, ["run", "--scheduled", id]);
        assert.equal(run.status, 0, run.stderr);
        const rec = ended(w, id);
        same([rec.trigger, rec.outcome, rec.slot], ["scheduled", "succeeded", slot], "the scheduled trigger records the UTC occurrence at Pacific month end");
    }
};

// Node's assert refuses an explicit undefined message, so a missing
// message is left out rather than passed.
function same(got, want, message) {
    const args = [JSON.parse(JSON.stringify(got)), JSON.parse(JSON.stringify(want))];
    if (message !== undefined) args.push(message);
    assert.deepEqual(...args);
}

// Polls CHECK every 50 ms for at most 10 s: a process the case started
// takes its lock or writes its record on its own clock.
function waitFor(check, what, boundMs = 10000) {
    const until = Date.now() + boundMs;
    while (Date.now() < until) {
        if (check()) return;
        childProcess.spawnSync("sleep", ["0.05"]);
    }
    assert.fail("timed out waiting for " + what);
}

// Holds LOCK from a process group of its own and returns once it is held,
// with the function that lets it go. flock's child holds the lock too, so
// the release ends the whole group.
function holdLock(w, lock) {
    const held = path.join(w.root, path.basename(lock) + ".held");
    const holder = childProcess.spawn("flock", [lock, "sh", "-c", ": >\"$1\"; exec sleep 10", "sh", held], { stdio: "ignore", env: w.env, detached: true });
    const release = () => {
        try {
            process.kill(-holder.pid, "SIGKILL");
        } catch (e) {
            if (e.code !== "ESRCH") throw e;
        }
    };
    try {
        waitFor(() => fs.existsSync(held), "the held lock");
    } catch (e) {
        release();
        throw e;
    }
    return release;
}

// An ended run of automation ID that started at MS, with its transcript;
// with `open`, only its started record.
function plant(w, id, ms, open) {
    const run = ms + "-" + (worlds * 100 + runFiles(w).length);
    const transcript = path.join(w.runs, Logic.runFile(id, run, "log"));
    const rec = { version: 1, automation: id, run: run, name: id, command: "true", directory: w.home, trigger: "manual", slot: null, startedAt: ms, transcript: transcript };
    write(transcript, "# planted\n");
    if (open) return write(path.join(w.runs, Logic.runFile(id, run, "started")), JSON.stringify(rec));
    write(path.join(w.runs, Logic.runFile(id, run, "ended")), JSON.stringify(Object.assign(rec, { endedAt: ms + 1, durationMs: 1, outcome: "succeeded", exitCode: 0, signal: null, reason: "", transcriptBytes: 10, truncated: false, snippet: "" })));
}

const NETWORK_DUE = Date.parse("2026-10-30T09:00:00Z");
function networkWorld(engine, options) {
    const opts = Object.assign({ value: "1", catchUp: false, minutely: false }, options);
    const w = world({ nowMs: NETWORK_DUE + 5 * 60000, systemd: opts.systemd || "up", stubs: opts.value === null ? FORBIDDEN.filter(name => name !== "busctl") : FORBIDDEN });
    const id = add(w, engine, { name: "Pull", requiresNetwork: true, catchUp: opts.catchUp,
        schedule: opts.minutely ? { frequency: "minutely", interval: 10, start: "2026-10-30", end: { type: "never" }, zone: "utc" }
            : { frequency: "daily", interval: 1, times: ["09:00"], start: "2026-10-30", end: { type: "never" }, zone: "utc" } });
    write(path.join(w.home, ".local/state/vgshell/automations/guard", id + ".json"), JSON.stringify({ handledThrough: 0 }));
    write(path.join(w.stub, "nm"), opts.value === null ? "" : opts.value);
    return { w, id, due: NETWORK_DUE };
}

function installedEngine(w, id) {
    const service = fs.readFileSync(path.join(w.units, "vgs-automation-" + id + ".service"), "utf8");
    return /"([^"\n]*\/engine\/[0-9a-f]{16}\/bin\/automations)"/.exec(service)[1];
}

function clockAt(w, now, mono) {
    const file = path.join(w.root, "clock.json");
    write(file + ".new", JSON.stringify({ now, mono }));
    fs.renameSync(file + ".new", file);
}

function listed(w, engine, id) {
    const out = cli(w, engine, ["list", "--json"]);
    assert.equal(out.status, 0, out.stderr);
    return JSON.parse(out.stdout).automations.find(row => row.id === id);
}

const runners = new Set();
function startRunner(w, engine, id, trigger) {
    const logFile = path.join(w.root, "runner-" + runners.size + ".log");
    const log = fs.openSync(logFile, "w");
    const lock = path.join(w.home, ".local/state/vgshell/automations/locks", id + ".lock");
    const child = childProcess.spawn("flock", ["-n", "-E", "75", "-o", lock, engine, "--tree", repo, "run", "--" + trigger, id], { env: w.env, cwd: w.home, stdio: ["ignore", log, log], detached: true });
    fs.closeSync(log);
    runners.add(child);
    child.logFile = logFile;
    return child;
}

// The runner journal's stable machine line keeps operation causes apart
// from the UI's plain pending diagnostic and command notifications.
function networkLogs(child) {
    return fs.readFileSync(child.logFile, "utf8").split("\n").slice(0, -1)
        .filter(line => line.startsWith("automations: network="))
        .map(line => JSON.parse(line.slice("automations: network=".length)));
}

function identityAlive(owner) {
    try {
        const fields = fs.readFileSync("/proc/" + owner.pid + "/stat", "utf8").split(") ").pop().split(" ");
        return fields[0] !== "Z" && fields[19] === owner.startTime;
    } catch (e) { if (e.code === "ENOENT") return false; throw e; }
}
function runnerAlive(child) {
    try { return !/[)] [ZX] /.test(fs.readFileSync("/proc/" + child.pid + "/stat", "utf8")); }
    catch (e) { if (e.code === "ENOENT") return false; throw e; }
}
function stopRunner(child) {
    if (!runners.has(child)) return;
    if (runnerAlive(child)) {
        try { process.kill(-child.pid, "SIGKILL"); }
        catch (e) { if (e.code !== "ESRCH") throw e; }
        waitFor(() => !runnerAlive(child), "the owned runner group to end");
    }
    runners.delete(child);
}

// How many PropertiesChanged waits the busctl stand-in began.
function waits(w) {
    const file = path.join(w.stub, "nm-waits");
    return fs.existsSync(file) ? fs.readFileSync(file, "utf8").split("\n").filter(Boolean).length : 0;
}

// ------------------------------------------------------------ the controls

// [label, the case, text in bin/automations, its replacement].
const CONTROLS = [
    ["FULL admission cannot be bypassed", "network requirements admit FULL alone and local commands bypass NM", "if (!admission.admit) {", "if (false && !admission.admit) {"],
    ["sync starts nothing with nothing to schedule", "sync with nothing runs nothing", "if (store.automations.length === 0 && ownedUnits().length === 0 && !fs.existsSync(engineRoot)) {", "if (false) {"],
    ["sync reloads after a unit change", "add writes the units, reloads and enables the timer", "if (removed.length + changed.length > 0) systemctl([\"daemon-reload\"]);", ""],
    ["the units run a copy of the engine", "add writes the units, reloads and enables the timer", "if (fs.existsSync(path.join(dir, \"bin\", \"automations\"))) return dir;", "return PLUGIN_DIR;"],
    ["add marks the past handled", "a scheduled trigger runs only what the guard allows", "    markHandled(judged.automation.id, Date.now());\n", "\n"],
    ["a changed active timer restarts", "edit, disable, enable and remove follow the store", "if (restarted.length > 0) systemctl([\"restart\"].concat(restarted));", ""],
    ["a disabled timer is stopped", "edit, disable, enable and remove follow the store", "if (timersGone.length > 0) systemctl([\"disable\", \"--now\"].concat(timersGone));", ""],
    ["the started record comes before the command", "a run that succeeds writes both records and its transcript", "writeAtomic(path.join(runsDir, Logic.runFile(id, runId, \"started\")), JSON.stringify(started) + \"\\n\", 0o600);", ""],
    ["a record lands by rename", "a run that succeeds writes both records and its transcript", "    fs.renameSync(temp, file);\n}", "}"],
    ["an error notifies", "a failing run sends the error notification whatever the toggle", "notify(Logic.notificationFor(\"end\", automation, ended, streak), shown, env)", "null"],
    ["the finish replaces the start", "notifyEveryRun sends the start, then replaces it with the finish", "ended, streak), shown, env)", "ended, streak), null, env)"],
    ["the start replaces the open failure notice", "repeated failures replace one notice and a success recovers it", "streak === null ? null : streak.notice, env);", "null, env);"],
    ["a notice is replaced on its own server alone", "a notice from another notification server is never replaced", "Logic.notifySendArgs(n, Logic.replaceIdFor(notice, server))", "Logic.notifySendArgs(n, notice === null ? null : notice.id)"],
    ["the server names the name's owner", "a notice from another notification server is never replaced", "ask(\"GetNameOwner\", [\"s\", \"org.freedesktop.Notifications\"])", "JSON.stringify({ type: \"s\", data: [\":1.7\"] })"],
    ["the server names the bus", "a notice from another notification server is never replaced", "Logic.notificationServer(ask(\"GetId\", [])", "Logic.notificationServer(JSON.stringify({ type: \"s\", data: [\"b\"] })"],
    ["a notice keeps its server", "repeated failures replace one notice and a success recovers it", "{ id: id, server: server }", "{ id: id, server: \"s\" }"],
    ["the end reads the streak", "repeated failures replace one notice and a success recovers it", "Logic.notificationFor(\"end\", automation, ended, streak)", "Logic.notificationFor(\"end\", automation, ended, null)"],
    ["the runner keeps the streak", "repeated failures replace one notice and a success recovers it", "else writeAtomic(streakFile(id), JSON.stringify(streak) + \"\\n\", 0o600);", "else return;"],
    ["the runner closes the streak", "repeated failures replace one notice and a success recovers it", "if (streak === null) fs.rmSync(streakFile(id), { force: true });\n    else", "if (streak === null) return;\n    else"],
    ["remove drops the streak", "repeated failures replace one notice and a success recovers it", "    fs.rmSync(streakFile(id), { force: true });\n    process.stdout.write(\"removed=\"", "    process.stdout.write(\"removed=\""],
    ["the timeout signals the group", "a timeout ends the command's whole process group", "process.kill(-child.pid, sig);", "process.kill(child.pid, sig);"],
    ["the timeout fires", "a timeout ends the command's whole process group", "timedOut = true;\n        signalGroup(\"SIGTERM\");", "timedOut = true;"],
    ["a timed-out run waits for its group", "a timed-out run ends after a descendant that ignores SIGTERM", "if (!timedOut) return finish(ending);", "return finish(ending);"],
    ["a long line ending in a break is split too", "output with no line break reaches the transcript in pieces", "        for (let at = 0; at < line.length; at += Logic.TRANSCRIPT_LINE_MAX) onLine(line.slice(at, at + Logic.TRANSCRIPT_LINE_MAX));\n        if (line === \"\") onLine(line);", "        onLine(line);"],
    ["a long line is split into pieces", "output with no line break reaches the transcript in pieces", "        while (pending.length > Logic.TRANSCRIPT_LINE_MAX) {", "        while (false) {"],
    ["a missing directory fails the start", "a missing working directory is a failed start", "return finish({ started: false, timedOut: false, exitCode: null, signal: null, reason: \"directory=\" + e.code + \" path=\" + directory });", "directory; // unchecked"],
    ["the transcript keeps its cap", "the transcript stops at its cap and the run goes on", "if (body + bytes > Logic.TRANSCRIPT_MAX_BYTES) {", "if (false) {"],
    ["the footer follows the cap", "the transcript stops at its cap and the run goes on", "put(footer.map(line => \"# \" + line + \"\\n\").join(\"\"));", ""],
    ["run-now goes through systemd-run", "run-now goes through systemd-run and refuses a busy automation", "if (scheduler() === \"systemd\") {\n        const unit", "if (false) {\n        const unit"],
    ["run-now refuses a busy automation", "run-now goes through systemd-run and refuses a busy automation", "if (lockHeld(id)) refuse(\"run=busy id=\" + id, \"a run of it is live\");", ""],
    ["a held lock is a running run", "history names a running and a vanished run", "if (out.status === 75) return true;", "if (out.status === 75) return false;"],
    ["prune keeps the retention", "clear keeps a running run and prune keeps the retention", "return removeRuns(Logic.prunable(judged.rows, Date.now(), days), judged.groups);", "return removeRuns(judged.rows.map(row => row.automation + \"@\" + row.run), judged.groups);"],
    ["prune reads historyDays", "clear keeps a running run and prune keeps the retention", "return { ok: true, days: Logic.retentionDays(JSON.parse(out.stdout).historyDays) };", "return { ok: true, days: 30 };"],
    ["clear keeps a running run", "clear keeps a running run and prune keeps the retention", "judged.rows.filter(row => row.outcome !== \"running\")", "judged.rows"],
    ["cron is the fallback", "without a systemd user manager sync keeps a crontab block", "changed = writeCrontab(requireCommand(\"crontab\"), Logic.cronLines(", "changed = writeCrontab(requireCommand(\"crontab\"), [] || Logic.cronLines("],
    ["cron lines run the scheduled trigger", "under cron a catch-up automation runs a missed occurrence at startup", "Logic.cronLines(store.automations, a => runnerArgv(engine, a.id, \"scheduled\"), runnerEnvironment)", "Logic.cronLines(store.automations, a => runnerArgv(engine, a.id, \"manual\"), runnerEnvironment)"],
    ["a crontab without a table reads empty", "without a systemd user manager sync keeps a crontab block", "if (out.status === 1 && /^no crontab for /.test(firstLine(out.stderr))) return \"\";", ""],
    ["no scheduler refuses", "with neither scheduler sync refuses", "if (chosen === \"none\") refuse(\"scheduler=none\", \"neither a systemd user manager nor crontab answered\");", ""]
];


let passed = 0;
try {
    const engine = path.join(pluginDir, "bin", "automations");
    const selected = process.argv.slice(2);
    for (const name of selected) assert.ok(Object.hasOwn(CASES, name), "unknown engine case: " + name);
    for (const [name, check] of Object.entries(CASES)) {
        if (selected.length && !selected.includes(name)) continue;
        check(engine);
        passed += 1;
    }
    const source = fs.readFileSync(engine, "utf8");
    let controls = 0;
    CONTROLS.forEach(([label, name, needle, replacement], i) => {
        if (selected.length && !selected.includes(name)) return;
        assert.ok(Object.prototype.hasOwnProperty.call(CASES, name), `control "${label}": no case "${name}"`);
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const copy = path.join(scratch, "control-" + i, "vgs.automations");
        fs.cpSync(pluginDir, copy, { recursive: true });
        fs.writeFileSync(path.join(copy, "bin", "automations"), source.replace(needle, () => replacement), { mode: 0o755 });
        let failed = false;
        try {
            CASES[name](path.join(copy, "bin", "automations"));
        } catch (e) {
            if (label === "FULL admission cannot be bypassed" && !(e instanceof assert.AssertionError)) throw e;
            failed = true;
        }
        assert.ok(failed, `control "${label}": case "${name}" passed on an engine without that rule`);
        controls += 1;
        if (label === "FULL admission cannot be bypassed") console.log("control: FULL admission bypass rejected by non-FULL command-start assertion");
    });
    console.log(`test-automations-engine: ok cases=${passed} controls=${controls}`);
} finally {
    for (const runner of runners) stopRunner(runner);
    fs.rmSync(scratch, { recursive: true, force: true });
}
