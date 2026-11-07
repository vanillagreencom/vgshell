.pragma library

// vgs.local-sync's pure decisions, run under node by
// scripts/test-local-sync-logic.js: which systemd user units are sync
// jobs, what their wrapper scripts copy, which job an engine process
// belongs to, what the job's journal says about its last copy, and the
// words the bar item, the flyout cards and Details show for a job. The
// service (Service.qml) runs the reads; this file only judges their text.
// Local Sync keeps no state of its own: each answer comes from systemd,
// the job's own files and the journal.

// The copy engines a job runs. A job runs one of them directly, as its
// unit's command, or through a script its command names.
var ENGINES = ["rsync", "unison"];

// The unit properties the service reads with `systemctl --user show
// --timestamp=unix`, which prints a timestamp as `@<seconds>` (systemctl(1),
// --timestamp=).
var SHOW_PROPERTIES = ["Id", "Description", "LoadState", "ActiveState", "SubState", "Result", "Type",
    "ExecStart", "TriggeredBy", "FragmentPath", "UnitFileState", "ExecMainStatus",
    "ExecMainStartTimestamp", "ExecMainExitTimestamp"];

// The lines of a script that matter to the reader: lines that name an
// engine, simple assignments and a unison profile's `root =` and `repeat =`
// lines.
var SCRIPT_LINE = /(rsync|unison)|^\s*((export|readonly|local|declare)\s+)?[A-Za-z_][A-Za-z0-9_]*=|^\s*(root|repeat)\s*=/;

// The most of a script the service reads: `head --bytes`, so a program a
// unit names, which is no script, costs no more than this.
var SCRIPT_BYTES = 65536;

// Folders that hold the system's own programs, never a user's script; a
// command there is not read. /usr/local holds the user's own.
var SYSTEM_DIRS = /^\/(usr\/(?!local\/)|bin\/|sbin\/|lib|nix\/store\/)/;

// A unit the Automations engine writes for an automation
// (vgs.automations AutomationsLogic.unitName), and the transient unit its
// Run now starts for one, `vgs-automation-<id>-now-<ms>.service`
// (vgs.automations bin/automations runNowVerb). An id may itself end in
// `-now-<digits>`, so only the store tells the two apart (automationOf).
var AUTOMATION_UNIT = /^vgs-automation-([A-Za-z0-9][A-Za-z0-9_-]*)\.service$/;
var RUN_NOW = /^(.+)-now-\d+$/;

// How long after an error line the job's own lines still belong to that
// failure: the PROBLEMS lines that name it, and the lines a script writes
// as it ends the failed copy. A job line later than this is a later try.
var FAILURE_WINDOW = 60000;

// The rsync exit status its manual calls a warning, not an error: "Partial
// transfer due to vanished source files" (rsync(1), EXIT VALUES).
var RSYNC_WARNINGS = [24];

// How the journal words a failed copy, and what the card says about it.
// Each pattern is a line rsync 3.5.1 printed for that failure on this
// host (cachy, 2026-11-06): a missing source folder and a destination
// whose parent is missing.
var PROBLEMS = [
    { key: "from", pattern: /^rsync: \[sender\] change_dir ".*" failed: No such file or directory/,
      text: "Cannot reach the From folder.", next: "Connect the drive that holds the From folder." },
    { key: "to", pattern: /^rsync: \[Receiver\] mkdir ".*" failed: No such file or directory/,
      text: "Cannot reach the To folder.", next: "Connect the drive that holds the To folder." }
];

// The PROBLEMS entry of KEY, or null.
function problemOf(key) {
    var found = PROBLEMS.filter(function (problem) { return problem.key === key; });
    return found.length === 0 ? null : found[0];
}

function hasOwn(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
}

function baseName(path) {
    var text = String(path);
    return text.slice(text.lastIndexOf("/") + 1);
}

function engineOf(word) {
    var name = baseName(word);
    return ENGINES.indexOf(name) === -1 ? "" : name;
}

// `systemctl --user list-unit-files --type=service --no-legend --plain`:
// the first column of each line, without templates, which run nothing
// until an instance of them exists.
function unitFileNames(text) {
    var out = [];
    String(text || "").split("\n").forEach(function (line) {
        var name = line.trim().split(/\s+/)[0];
        if (name !== undefined && /\.service$/.test(name) && !/@\.service$/.test(name) && out.indexOf(name) === -1) out.push(name);
    });
    return out;
}

// `systemctl show`'s blocks, one a unit, each `Key=value` line split at its
// first `=`; a unit listed twice keeps its first block.
function parseShow(text) {
    var out = [];
    var seen = {};
    String(text || "").split(/\n\s*\n/).forEach(function (block) {
        var record = {};
        block.split("\n").forEach(function (line) {
            var at = line.indexOf("=");
            if (at > 0) record[line.slice(0, at)] = line.slice(at + 1);
        });
        if (typeof record.Id !== "string" || record.Id === "" || hasOwn(seen, record.Id)) return;
        seen[record.Id] = true;
        out.push(record);
    });
    return out;
}

// A `@<seconds>` timestamp as epoch milliseconds, 0 when the unit has none.
function showTime(value) {
    var match = /^@(\d+)$/.exec(String(value || "").trim());
    return match === null ? 0 : Number(match[1]) * 1000;
}

// The commands of an ExecStart= value, each `{ path=… ; argv[]=… ; … }`:
// the argv words. systemctl joins argv with single spaces, so a word that
// held a space reads as two; such a path is not read.
function execCommands(value) {
    var out = [];
    var re = /argv\[\]=(.*?) ; ignore_errors=/g;
    var match;
    while ((match = re.exec(String(value || ""))) !== null) {
        var words = match[1].split(" ").filter(function (w) { return w !== ""; });
        if (words.length > 0) out.push(words);
    }
    return out;
}

// LINE as shell words and operators: quotes removed from the words, `;`,
// `&`, `|`, `(`, `)`, `{` and `}` as words of their own, a comment
// dropped. `quoted` marks a word that held a quote, so `"$SRC/"` keeps its
// expansion while a quoted engine name stays a plain word.
function shellWords(line) {
    var words = [];
    var word = null;
    var quote = "";
    var text = String(line);
    function push() {
        if (word !== null) words.push(word);
        word = null;
    }
    for (var i = 0; i < text.length; i++) {
        var c = text.charAt(i);
        if (quote !== "") {
            if (c === quote) quote = "";
            else if (c === "\\" && quote === "\"" && i + 1 < text.length) word.text += text.charAt(++i);
            else word.text += c;
            continue;
        }
        if (c === "'" || c === "\"") {
            if (word === null) word = { text: "", quoted: true };
            word.quoted = true;
            quote = c;
        } else if (c === "\\" && i + 1 < text.length) {
            if (word === null) word = { text: "", quoted: false };
            word.text += text.charAt(++i);
        } else if (/\s/.test(c)) {
            push();
        } else if (c === "#" && word === null) {
            break;
        } else if (";&|(){}".indexOf(c) !== -1) {
            push();
            words.push({ text: c, quoted: false, operator: true });
        } else {
            if (word === null) word = { text: "", quoted: false };
            word.text += c;
        }
    }
    push();
    return words;
}

// Words after which the next word is a command.
var COMMAND_STARTS = ["then", "do", "else", "elif", "!", "exec", "command", "nohup", "time", "nice", "ionice", "env"];

// The engine LINE runs, with its arguments up to the end of that command:
// { engine, args } or null. An engine name counts only where a command
// starts, so a log line that names rsync in its message runs nothing.
function engineCall(line) {
    var words = shellWords(line);
    var start = true;
    for (var i = 0; i < words.length; i++) {
        var w = words[i];
        if (w.operator) { start = true; continue; }
        if (!start) continue;
        if (!w.quoted && /^[A-Za-z_][A-Za-z0-9_]*=/.test(w.text)) continue;
        if (!w.quoted && (COMMAND_STARTS.indexOf(w.text) !== -1 || /^-/.test(w.text) || /^\d+$/.test(w.text))) continue;
        var engine = w.quoted ? "" : engineOf(w.text);
        if (engine !== "") {
            var args = [];
            for (var j = i + 1; j < words.length && !words[j].operator; j++) args.push(words[j].text);
            return { engine: engine, args: args };
        }
        start = false;
    }
    return null;
}

// The value of a simple assignment LINE, `NAME=value`, or null: a value
// that runs a command, `$(…)` or a backquote, is not one the reader knows.
function assignment(line) {
    var words = shellWords(line).filter(function (w) {
        return !(!w.quoted && ["export", "readonly", "local", "declare"].indexOf(w.text) !== -1);
    });
    if (words.length !== 1 || words[0].operator) return null;
    var match = /^([A-Za-z_][A-Za-z0-9_]*)=([\s\S]*)$/.exec(words[0].text);
    if (match === null || /\$\(|`/.test(match[2])) return null;
    return { name: match[1], value: match[2] };
}

// TEXT with `~`, `$NAME`, `${NAME}` and `${NAME:-default}` expanded from
// VARS; null when it names a variable VARS does not hold or runs a command.
function expand(text, vars) {
    if (/\$\(|`/.test(text)) return null;
    var unknown = false;
    var out = String(text).replace(/^~(?=\/|$)/, function () {
        if (!hasOwn(vars, "HOME")) { unknown = true; return ""; }
        return vars.HOME;
    }).replace(/\$\{([A-Za-z_][A-Za-z0-9_]*)(:-([^}]*))?\}|\$([A-Za-z_][A-Za-z0-9_]*)/g, function (all, braced, hasDefault, fallback, bare) {
        var name = braced || bare;
        if (hasOwn(vars, name)) return vars[name];
        if (hasDefault !== undefined) return fallback;
        unknown = true;
        return "";
    });
    return unknown ? null : out;
}

// The words of an engine call's ARGS that are not options. unison's
// `-repeat` takes the next word as its value (unison manual, Preferences:
// `repeat`), which is no root or profile.
function plainWords(call) {
    var out = [];
    for (var i = 0; i < call.args.length; i++) {
        var word = call.args[i];
        if (call.engine === "unison" && word === "-repeat") i++;
        else if (word !== "" && word.charAt(0) !== "-") out.push(word);
    }
    return out;
}

// The profile a unison call names, { roots, repeat } from PROFILES, or
// null: its one plain word, when it names no second root.
function profileOf(call, profiles) {
    var plain = plainWords(call);
    return call.engine === "unison" && plain.length === 1 && hasOwn(profiles, plain[0]) ? profiles[plain[0]] : null;
}

// Whether an engine call stays running between its copies, so an engine
// process in its unit is no copy: unison's `repeat` preference, on its
// command line or in the profile it reads, makes it synchronize again and
// again, by a time or by watching the files (unison manual, Preferences:
// `repeat`; "When synchronizing continuously (time interval repeat or
// with filesystem monitoring)"), and rsync's `--daemon` serves clients
// until it is stopped (rsync(1), --daemon).
function resident(call, profiles) {
    if (call.engine === "rsync") return call.args.indexOf("--daemon") !== -1;
    if (call.args.some(function (word) { return word === "-repeat" || word.indexOf("-repeat=") === 0; })) return true;
    var profile = profileOf(call, profiles);
    return profile !== null && profile.repeat;
}

// The two folders an engine call copies between, { from, to }, each ""
// when not readable. rsync copies `SRC... DEST`, so the last two words
// that are not options are the last source and the destination (rsync(1),
// SYNOPSIS); unison syncs two roots, given as its first two words or by
// a profile (unison manual, Profiles). PROFILES maps a profile name to its
// { roots, repeat }.
function folders(call, vars, profiles) {
    var plain = plainWords(call);
    var profile = profileOf(call, profiles);
    var pair;
    if (call.engine === "rsync") {
        pair = plain.length >= 2 ? plain.slice(-2) : [];
    } else if (plain.length >= 2) {
        pair = plain.slice(0, 2);
    } else if (profile !== null) {
        pair = profile.roots;
    } else {
        pair = [];
    }
    function read(word) {
        if (word === undefined) return "";
        var value = expand(word, vars);
        return value === null || value === "" || (value.charAt(0) !== "/" && !/^[a-z]+:\/\//.test(value)) ? "" : value;
    }
    return { from: read(pair[0]), to: read(pair[1]) };
}

// What a script's LINES copy: { engine, from, to, resident }, or null when
// no line runs an engine. Assignments before the engine's line set the variables
// it reads; HOME seeds them.
function scriptJob(lines, home, profiles) {
    var vars = { HOME: home };
    for (var i = 0; i < lines.length; i++) {
        var set = assignment(lines[i]);
        if (set !== null) {
            var value = expand(set.value, vars);
            if (value !== null) vars[set.name] = value;
            else delete vars[set.name];
            continue;
        }
        var call = engineCall(lines[i]);
        if (call !== null) {
            var pair = folders(call, vars, profiles || {});
            return { engine: call.engine, from: pair.from, to: pair.to, resident: resident(call, profiles || {}) };
        }
    }
    return null;
}

// A unison profile's LINES as { roots, repeat }: its `root = <path>`
// lines, and whether a `repeat = <value>` line makes it run continuously
// (unison manual, Profiles and Preferences: `repeat`).
function profileRead(lines) {
    var out = { roots: [], repeat: false };
    lines.forEach(function (line) {
        var match = /^\s*root\s*=\s*(.+?)\s*$/.exec(line);
        if (match !== null) out.roots.push(match[1]);
        if (/^\s*repeat\s*=\s*\S/.test(line)) out.repeat = true;
    });
    return out;
}

// The shells a unit's command can name before its script.
var SHELLS = ["sh", "bash", "dash", "zsh", "ksh"];

// What ARGV, one command of a unit, runs: { engine } when it is an engine,
// { text } for a shell's `-c` script, { file } for a script it names, or
// null. `env` and its assignments lead to the command after them; a shell
// runs its first word that is not an option; any other command is itself
// the file, which the reader skips when it is not text. The words after a
// script are its arguments, never read.
function commandScript(argv) {
    var at = 0;
    if (baseName(argv[0]) === "env") {
        at = 1;
        while (at < argv.length && (argv[at].charAt(0) === "-" || /^[A-Za-z_][A-Za-z0-9_]*=/.test(argv[at]))) at++;
    }
    if (at >= argv.length) return null;
    if (engineOf(argv[at]) !== "") return { engine: engineOf(argv[at]), args: argv.slice(at + 1) };
    if (SHELLS.indexOf(baseName(argv[at])) === -1) return argv[at].charAt(0) === "/" ? { file: argv[at] } : null;
    for (var i = at + 1; i < argv.length; i++) {
        // systemctl joins the words with spaces, so the script and the
        // words after it read as one text.
        if (argv[i] === "-c") return i + 1 < argv.length ? { text: argv.slice(i + 1).join(" ") } : null;
        if (argv[i].charAt(0) !== "-") return argv[i].charAt(0) === "/" ? { file: argv[i] } : null;
    }
    return null;
}

// The files the service reads for RECORDS' commands: each script a
// command names (commandScript), and each unison profile a direct unison
// command names, under HOME's `.unison` (unison manual, Profiles), for
// every unit but an automation's.
function scriptFiles(records, home) {
    var out = [];
    function add(path) {
        if (out.indexOf(path) === -1) out.push(path);
    }
    records.forEach(function (record) {
        // An automation's command is in the Automations store, not a file.
        if (automationId(record.Id) !== "") return;
        execCommands(record.ExecStart).forEach(function (argv) {
            var script = commandScript(argv);
            if (script !== null && script.file !== undefined && !SYSTEM_DIRS.test(script.file)) add(script.file);
            if (script !== null && script.engine === "unison") {
                plainWords(script).forEach(function (word) {
                    if (/^[A-Za-z0-9_.-]+$/.test(word)) add(home + "/.unison/" + word + ".prf");
                });
            }
        });
    });
    return out;
}

// The lines of a script's TEXT the reader reads (SCRIPT_LINE), in order.
function scriptLines(text) {
    return String(text || "").split("\n").filter(function (line) { return SCRIPT_LINE.test(line); });
}

// The automation id an Automations unit's name holds, or "": for a Run
// now unit, the id with its `-now-<ms>` (automationOf parts them).
function automationId(unit) {
    var match = AUTOMATION_UNIT.exec(String(unit));
    return match === null ? "" : match[1];
}

// Which automation of AUTOMATIONS, the store's, an Automations UNIT runs:
// { id, run }, `run` true for a Run now unit of that automation; null for
// no Automations unit. An id the store holds is that automation's own
// unit, even when it ends in `-now-<digits>`.
function automationOf(unit, automations) {
    var id = automationId(unit);
    if (id === "") return null;
    if (hasOwn(automations || {}, id)) return { id: id, run: false };
    var run = RUN_NOW.exec(id);
    if (run !== null && hasOwn(automations || {}, run[1])) return { id: run[1], run: true };
    return { id: id, run: false };
}

// Whether UNIT is a Run now unit of JOB, an automation's job: its id's
// `-now-<ms>` unit, and none of the units JOB.notRuns names, the store's
// own automations whose ids look like one.
function isRunOf(unit, job) {
    if (job.automation === "" || job.notRuns.indexOf(unit) !== -1) return false;
    var run = RUN_NOW.exec(automationId(unit));
    return run !== null && run[1] === job.automation;
}

// Whether UNIT's lines and processes are JOB's: its own unit, or a Run now
// unit of it.
function ownsUnit(job, unit) {
    return unit === job.unit || isRunOf(unit, job);
}

// A unit name as words: `scribd-brain-backup.service` reads "Scribd brain
// backup".
function unitTitle(unit) {
    var words = String(unit).replace(/\.service$/, "").replace(/[-_.]+/g, " ").trim();
    return words === "" ? String(unit) : words.charAt(0).toUpperCase() + words.slice(1);
}

// Every sync job among RECORDS, the `systemctl show` blocks: a unit whose
// command runs an engine, directly or through a script SCRIPTS holds the
// lines of, or an automation of AUTOMATIONS (the Automations store's
// `automations`, keyed by id) whose command runs one. MISSING lists the
// engines this computer lacks. A Run now unit is no job of its own: its
// automation's job lists it in `runs` while systemd holds it, and
// `runPattern` names every one for the journal read.
function jobs(records, scripts, automations, home, missing) {
    var profiles = {};
    Object.keys(scripts).forEach(function (file) {
        var match = /\/\.unison\/([^/]+)\.prf$/.exec(file);
        if (match !== null) profiles[match[1]] = profileRead(scripts[file]);
    });
    var out = [];
    records.forEach(function (record) {
        if (record.LoadState !== "loaded") return;
        var found = null;
        var via = "";
        var name = "";
        var owner = automationOf(record.Id, automations);
        var id = owner === null ? "" : owner.id;
        if (owner !== null) {
            var automation = hasOwn(automations || {}, id) && !owner.run ? automations[id] : null;
            if (automation === null) return;
            found = scriptJob([automation.command], home, profiles);
            via = "automation";
            name = automation.name;
        } else {
            var commands = execCommands(record.ExecStart);
            for (var c = 0; c < commands.length && found === null; c++) {
                var script = commandScript(commands[c]);
                if (script === null) continue;
                if (script.engine !== undefined) {
                    var pair = folders(script, { HOME: home }, profiles);
                    found = { engine: script.engine, from: pair.from, to: pair.to, resident: resident(script, profiles) };
                    via = "direct";
                } else if (script.text !== undefined) {
                    found = scriptJob([script.text], home, profiles);
                    via = "script";
                } else if (hasOwn(scripts, script.file)) {
                    found = scriptJob(scripts[script.file], home, profiles);
                    via = "script";
                }
            }
        }
        if (found === null) return;
        out.push({
            unit: record.Id,
            name: name !== "" ? name : unitTitle(record.Id),
            description: record.Description || "",
            automation: id,
            engine: found.engine,
            available: (missing || []).indexOf(found.engine) === -1,
            from: found.from,
            to: found.to,
            via: via,
            // A script that runs as a service, or an engine that stays
            // running between copies: its unit's end is no copy's end.
            continuous: record.Type !== "oneshot" && (via === "script" || found.resident),
            // An engine process that stays running is no copy, so the copy
            // check leaves this job out.
            resident: found.resident,
            active: record.ActiveState || "",
            sub: record.SubState || "",
            result: record.Result || "",
            triggers: String(record.TriggeredBy || "").split(" ").filter(function (t) { return t !== ""; }),
            fileState: record.UnitFileState || "",
            mainStatus: Number(record.ExecMainStatus || 0),
            startedAt: showTime(record.ExecMainStartTimestamp),
            exitedAt: showTime(record.ExecMainExitTimestamp),
            runs: id === "" ? [] : records.filter(function (other) {
                var of = other.LoadState === "loaded" ? automationOf(other.Id, automations) : null;
                return of !== null && of.run && of.id === id;
            }).map(function (other) { return other.Id; }),
            runPattern: id === "" ? "" : "vgs-automation-" + id + "-now-*.service",
            notRuns: id === "" ? [] : Object.keys(automations || {}).filter(function (other) {
                var run = RUN_NOW.exec(other);
                return run !== null && run[1] === id;
            }).map(function (other) { return "vgs-automation-" + other + ".service"; })
        });
    });
    out.sort(function (a, b) { return a.name.localeCompare(b.name) || a.unit.localeCompare(b.unit); });
    return out;
}

// The Automations store's version this reader knows. The store's format
// belongs to vgs.automations: bin/automations names the file and
// AutomationsLogic.js (STORE_VERSION, parseStore, unitName) judges it.
// Automations documents `automations list --json` as the reading of its
// jobs, but that program lives in vgs.automations' own tree, which no
// plugin may name as a requirement (D035 names commands, never another
// plugin), and it would start Automations' engine for every store change;
// the file is read only. scripts/test-local-sync-logic.js loads
// AutomationsLogic.js, so a change to the format fails Local Sync's test.
var STORE_VERSION = 2;

// The Automations store's TEXT, read only: { ok: true, automations: { id:
// { name, command } } } for a store of STORE_VERSION, { ok: false } for any
// other version, an absent file (null TEXT) or text that does not parse.
// No field is guessed: an automation without a text id, name and command
// is left out.
function readStore(text) {
    if (text === null || text === undefined) return { ok: false, automations: {} };
    var doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return { ok: false, automations: {} };
    }
    if (doc === null || typeof doc !== "object" || doc.version !== STORE_VERSION || !Array.isArray(doc.automations)) return { ok: false, automations: {} };
    var out = {};
    doc.automations.forEach(function (a) {
        if (a !== null && typeof a === "object" && typeof a.id === "string" && typeof a.command === "string" && typeof a.name === "string")
            out[a.id] = { name: a.name, command: a.command };
    });
    return { ok: true, automations: out };
}

// Why the jobs Automations runs are not listed, "" when they are or when
// RECORDS hold no automation's unit: STORE, readStore's answer, could not
// be read.
function storeProblem(store, records) {
    if (store.ok || !records.some(function (record) { return automationId(record.Id) !== ""; })) return "";
    return "Local Sync could not read the Automations jobs, so it does not show them.";
}

// Whether an engine runs in a unit, from systemd's GetUnitProcesses
// answer as `busctl --json=short` prints it: `{"type":"a(sus)","data":
// [[[cgroup, pid, command line], …]]}`, every process of the unit's
// control group and those below it (org.freedesktop.systemd1(5),
// GetUnitProcesses; busctl on cachy, systemd 262, 2026-11-06). A process
// is an engine when its command line's first word is one. null when TEXT
// is not that answer.
function engineRunning(text) {
    var doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (doc === null || typeof doc !== "object" || doc.type !== "a(sus)" || !Array.isArray(doc.data) || !Array.isArray(doc.data[0])) return null;
    return doc.data[0].some(function (proc) {
        return Array.isArray(proc) && typeof proc[2] === "string" && engineOf(proc[2].split(" ")[0]) !== "";
    });
}

// One `journalctl -o json` line as { at, message, comm, priority, unit },
// or null.
function journalEntry(line) {
    var doc;
    try {
        doc = JSON.parse(line);
    } catch (e) {
        return null;
    }
    if (doc === null || typeof doc !== "object") return null;
    var message = Array.isArray(doc.MESSAGE) ? "" : String(doc.MESSAGE || "");
    return {
        at: Math.floor(Number(doc.__REALTIME_TIMESTAMP || 0) / 1000),
        message: message,
        comm: String(doc._COMM || ""),
        priority: Number(doc.PRIORITY === undefined ? 6 : doc.PRIORITY),
        unit: String(doc._SYSTEMD_USER_UNIT || ""),
        about: String(doc.USER_UNIT || "")
    };
}

// Whether ENTRY, a line of JOB's own processes, reports a failed copy: an
// error line of the engine, a line at error priority or worse, or a
// script's line that an engine exited with a status that is not success
// or a warning.
function isError(entry, job) {
    if (entry.priority <= 3) return true;
    var text = entry.message;
    if (entry.comm === job.engine) {
        if (/^rsync warning:/.test(text)) return false;
        return /^rsync( error)?:|^Fatal error|\bfailed\b/i.test(text);
    }
    var exit = /\b(rsync|unison)\b.*\bexit(?:ed)?\s+(?:with\s+)?(?:code\s+|status\s+)?(\d+)/i.exec(text);
    if (exit === null) return false;
    var code = Number(exit[2]);
    return code !== 0 && !(exit[1].toLowerCase() === "rsync" && RSYNC_WARNINGS.indexOf(code) !== -1);
}

// The user manager's own line that a unit's run ended clean: a one-shot's
// "Finished <unit> - <description>." and a service's "Deactivated
// successfully." (journalctl --user -o json on cachy, systemd 262,
// 2026-11-06). A failed run's lines read "Failed with result ..." instead.
var MANAGER_CLEAN = /^(Finished\b|Deactivated successfully\.)/;

// What JOB's journal ENTRIES say: { tried, failedAt, error, problem,
// finishedAt }. `tried` is the newest line of the job's own processes,
// which a script writes when it acts; `failedAt` and `error` the newest
// error line and its text; `problem` the key of the PROBLEMS entry the
// job's error lines within FAILURE_WINDOW before that one name, or "";
// `finishedAt` the newest manager line that a run of the job ended clean
// (MANAGER_CLEAN), which `journalctl -u` reads with the unit's own lines
// (journalctl(1), --unit: "additional matches for messages from
// systemd"). A job's Run now units count as the job. The facts are plain
// JSON, so the service publishes them as they are.
function journalFacts(entries, job) {
    var facts = { tried: 0, failedAt: 0, error: "", problem: "", finishedAt: 0 };
    entries.forEach(function (entry) {
        if (entry === null) return;
        if (entry.comm === "systemd") {
            if (ownsUnit(job, entry.about) && MANAGER_CLEAN.test(entry.message) && entry.at > facts.finishedAt) facts.finishedAt = entry.at;
            return;
        }
        if (!ownsUnit(job, entry.unit)) return;
        if (entry.at > facts.tried) facts.tried = entry.at;
        if (!isError(entry, job)) return;
        if (entry.at >= facts.failedAt) {
            facts.failedAt = entry.at;
            facts.error = entry.message;
        }
    });
    if (facts.failedAt > 0) {
        entries.forEach(function (entry) {
            if (entry === null || entry.comm === "systemd" || !ownsUnit(job, entry.unit) || facts.failedAt - entry.at > FAILURE_WINDOW || entry.at > facts.failedAt) return;
            PROBLEMS.forEach(function (problem) {
                if (problem.pattern.test(entry.message)) facts.problem = problem.key;
            });
        });
    }
    return facts;
}

// Whether a manager line ABOUT a unit, or one that reloads the manager,
// can change what JOBS read: the service reads every job again for it. A
// Run now unit of a job is about that job.
function managerLineMatters(entry, jobList) {
    if (entry === null) return false;
    if (/^Reload(ing|ed)\b/.test(entry.message)) return true;
    return entry.about !== "" && jobList.some(function (job) { return ownsUnit(job, entry.about); });
}

// The units the copy check asks about for JOBS: { unit, job } for each
// job's unit and its Run now units, job being the job's own unit. A job
// whose engine stays running is left out (resident).
function checkUnits(jobList) {
    var out = [];
    jobList.forEach(function (job) {
        if (job.resident) return;
        [job.unit].concat(job.runs).forEach(function (unit) { out.push({ unit: unit, job: job.unit }); });
    });
    return out;
}

// The `journalctl` match words for JOB's journal read: its unit, and the
// pattern every Run now unit of it matches (journalctl(1), --unit=PATTERN).
function journalUnits(job) {
    return ["-u", job.unit].concat(job.runPattern === "" ? [] : ["-u", job.runPattern]);
}

// JOB's two moments, { good, tried }, from its FACTS and SEEN, the end of
// the last copy this service saw end with no error line: `good` the last
// copy known to end clean, `tried` the last try. A continuous job's unit
// keeps running across its copies, so its unit's exit and the manager's
// line about it tell nothing of a copy.
function times(job, facts, seen) {
    var unitGood = job.continuous ? 0 : Math.max(job.result === "success" ? job.exitedAt : 0, facts.finishedAt || 0);
    return {
        good: Math.max(seen || 0, unitGood),
        tried: Math.max(facts.tried, job.continuous ? 0 : job.startedAt)
    };
}

// Whether JOB's newest error line stands: no copy known to end clean came
// after it, and no try came after the lines of that failure
// (FAILURE_WINDOW). A later try with no error line does not confirm a
// success, so it only clears the failure.
function errorStands(facts, moments) {
    return facts.failedAt > 0 && facts.failedAt > moments.good && facts.tried <= facts.failedAt + FAILURE_WINDOW;
}

// JOB's state, one of: copying, failed, attention, unavailable, watching,
// starting, waiting, stopped. Only an engine process makes it copying: an
// active unit with no engine among its processes is watching or starting.
// FACTS are its journal facts and COPYING whether an engine runs in its
// unit now; SEEN is the end of the last copy this service saw end with no
// error line, 0 for none.
function jobState(job, facts, copying, seen) {
    if (!job.available) return "unavailable";
    if (copying) return "copying";
    var failed = job.active === "failed" || (!job.continuous && job.result !== "" && job.result !== "success")
        || errorStands(facts, times(job, facts, seen));
    if (failed) return problemOf(facts.problem) !== null ? "attention" : "failed";
    if (job.active === "active" || job.active === "activating") return job.continuous ? "watching" : "starting";
    if (job.triggers.length > 0) return "waiting";
    return "stopped";
}

var STATE_TEXT = {
    copying: "Syncing",
    failed: "Copy failed",
    attention: "Needs attention",
    unavailable: "",
    watching: "Watching for changes",
    starting: "Starting",
    waiting: "Waiting for its next start",
    stopped: "Not running"
};

function unavailableText(engine) {
    return engine === "unison" ? "Two-way copy is not available on this computer" : "Copying is not available on this computer";
}

// The sentence that says a continuous job cannot confirm a copy's end.
var NO_END = "This job does not report when a copy ends.";

// The flyout card of JOB: { unit, name, state, stateText, tone, from, to,
// recent, explanation, next, actions, good, tried }. TONE is neutral, info
// or danger; ACTIONS are keys the panel draws as links: `log`, `agent` and
// `setup`; GOOD and TRIED are its moments (times). WHEN words a past
// moment (Timestamp.text with NOW).
function card(job, facts, copying, seen, now, when) {
    var state = jobState(job, facts, copying, seen);
    var moments = times(job, facts, seen);
    var good = moments.good;
    var tried = moments.tried;
    var out = {
        unit: job.unit,
        name: job.name,
        state: state,
        stateText: state === "unavailable" ? unavailableText(job.engine) : STATE_TEXT[state],
        tone: state === "failed" || state === "attention" ? "danger" : state === "copying" ? "info" : "neutral",
        from: job.from,
        to: job.to,
        recent: "",
        explanation: "",
        next: "",
        actions: [],
        good: good,
        tried: tried
    };
    // systemd's timestamps are whole seconds and the journal's finer, so
    // an exit within the second of the last line covers it.
    if (good > 0 && good + 1000 > tried) out.recent = "Last sync: " + when(good, now);
    else if (tried > 0) out.recent = "Last tried: " + when(tried, now);
    else out.recent = "No copies recorded.";
    if (state === "attention") {
        out.explanation = problemOf(facts.problem).text;
        out.next = problemOf(facts.problem).next;
        out.actions = ["log"];
    } else if (state === "failed") {
        out.explanation = "The copy stopped with an error.";
        out.actions = ["log", "agent"];
    } else if (state === "unavailable") {
        out.actions = ["setup"];
    } else if (job.continuous && good === 0 && tried > 0 && state !== "copying") {
        out.explanation = NO_END;
    }
    return out;
}

// The Details rows of JOB: [{ label, value, tone }], in the order the
// Details sheet shows them, and its help line: a continuous job with no
// copy known to end clean says once that its copies' ends are unknown, and
// each row keeps to its own fact.
function details(job, facts, copying, seen, now, when) {
    var c = card(job, facts, copying, seen, now, when);
    var failing = c.state === "failed" || c.state === "attention";
    var how = job.via === "automation" ? "Automations job" : job.continuous ? "runs all the time"
        : job.triggers.length > 0 ? "Started by " + job.triggers.join(", ") : "Runs once when started";
    var rows = [
        { label: "System job", value: job.unit, tone: "neutral" },
        { label: "Description", value: job.description, tone: "neutral" },
        { label: "Engine", value: job.engine + " · " + how, tone: "neutral" },
        { label: "From", value: job.from === "" ? "Not readable from the job" : job.from, tone: "neutral" },
        { label: "To", value: job.to === "" ? "Not readable from the job" : job.to, tone: "neutral" },
        { label: "State", value: c.stateText, tone: c.tone },
        { label: "Last attempt", value: c.tried > 0 ? when(c.tried, now) : "Not recorded", tone: "neutral" },
        { label: "Last sync", value: c.good > 0 ? when(c.good, now) : "Not recorded", tone: "neutral" },
        { label: "Last result", value: failing ? (job.mainStatus > 0 && !job.continuous ? "Failed · Exit code " + job.mainStatus : "Failed") : c.good > 0 ? "Success" : "Not recorded", tone: failing ? "danger" : "neutral" },
        { label: "Errors", value: failing && facts.error !== "" ? facts.error : "No errors recorded", tone: failing && facts.error !== "" ? "danger" : "neutral" }
    ].filter(function (row) { return row.value !== ""; });
    return { rows: rows, help: job.continuous && c.good === 0 ? NO_END : "" };
}

// JOB's journal facts in VALUE, the service's published `jobs` value, or
// the facts of no line while its journal is not read yet.
function factsOf(value, job) {
    return hasOwn(value.facts, job.unit) ? value.facts[job.unit] : journalFacts([], job);
}

// The card of JOB from VALUE, the service's published `jobs` value.
function cardOf(value, job, now, when) {
    return card(job, factsOf(value, job), value.copying.indexOf(job.unit) !== -1, value.cleanEnds[job.unit] || 0, now, when);
}

// Every job's card from VALUE, in its order.
function cards(value, now, when) {
    return value.jobs.map(function (job) { return cardOf(value, job, now, when); });
}

// The Details of JOB from VALUE.
function detailsOf(value, job, now, when) {
    return details(job, factsOf(value, job), value.copying.indexOf(job.unit) !== -1, value.cleanEnds[job.unit] || 0, now, when);
}

// The bar item over CARDS: { state, label, tooltip, lines }. STATE is idle,
// syncing or failed: syncing while any job copies, failed while a job's
// last copy failed, idle otherwise.
function bar(cards) {
    var copying = cards.filter(function (c) { return c.state === "copying"; });
    var failing = cards.filter(function (c) { return c.state === "failed" || c.state === "attention"; });
    var state = copying.length > 0 ? "syncing" : failing.length > 0 ? "failed" : "idle";
    var label = state === "syncing" ? "Local Sync: syncing" : state === "failed" ? "Local Sync: last copy failed" : "Local Sync";
    var lines = copying.map(function (c) { return "Syncing: " + c.name; })
        .concat(failing.map(function (c) { return c.stateText + ": " + c.name; }));
    if (cards.length === 0) lines = ["No sync jobs on this computer"];
    else if (lines.length === 0) lines = [cards.length === 1 ? "1 sync job, not copying" : cards.length + " sync jobs, none copying"];
    return { state: state, failed: failing.length > 0, label: label, tooltip: label, lines: lines };
}

// The fixed handoff receivers Local Sync hands its actions to (D127):
// Agent Debug's Diagnose for Send to agent, and Automations' sync job for
// Add and for Remove of a job Automations runs. Each opens a draft its
// owner shows and starts nothing until the user presses Run, Save or
// Remove there.
var AGENT_TARGET = "handoff:vgs.agent-debug/diagnose";
var AUTOMATIONS_TARGET = "handoff:vgs.automations/sync-job";

// Add's request to Automations: a new sync job's draft with AVAILABLE, the
// engines this computer has (vgs.automations AutomationsLogic.syncJobRequest).
function addRequest(available) {
    return JSON.stringify({ action: "new", available: available });
}

// Remove's request to Automations for JOB, an automation's unit: that
// automation with Automations' own Remove question.
function removeRequest(job) {
    return JSON.stringify({ action: "remove", id: job.automation });
}

// The text Send to agent hands over for JOB with FACTS: the failure's facts
// as one JSON object, the shape Agent Debug's Debug.syncFacts reads. It
// holds the job's own words and its newest error line, never a file's
// content.
function agentFacts(job, facts) {
    return JSON.stringify({
        kind: "sync",
        unit: job.unit,
        name: job.name,
        engine: job.engine,
        from: job.from,
        to: job.to,
        error: facts.error !== "" ? facts.error : job.result !== "" && job.result !== "success" ? "The unit ended with result " + job.result + ", exit status " + job.mainStatus + "." : "",
        at: facts.failedAt > 0 ? facts.failedAt : job.exitedAt
    });
}

// The Remove confirmation for JOB: { title, text, action } when Local Sync
// stops it itself, a unit the user made outside VGS.
function removal(job) {
    return {
        title: "Remove " + job.name + "?",
        text: "This stops the job and turns it off. Your folders and the job's setup file stay.",
        action: "Stop and turn off"
    };
}

// The units Remove stops and turns off for JOB: its triggers first, so a
// timer or a path unit cannot start it again, then the unit.
function removeUnits(job) {
    return job.triggers.concat([job.unit]);
}
