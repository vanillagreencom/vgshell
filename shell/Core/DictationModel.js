.pragma library

// The `dictation` capability's decisions (D106). shell/Core/Dictation.qml
// drives them over one `voxtype daemon` child, its status follower and one
// serial command runner, and scripts/test-dictation-model.js runs event
// sequences through them. Every event function takes the model and returns
// { model, effects }, a new model and the effects for the owner to run in
// order; start, stop, cancel and restart also return `answer`, `ok` or the
// refusal:
//   { kind: "run", tag, argv }  queue one command behind those queued; its
//                               end comes back as ran
//   { kind: "abort" }           drop the queued commands and end the running
//                               one, with no ran for any of them
//   { kind: "daemon" }          start the daemon child
//   { kind: "term" }            SIGTERM to the daemon child
//   { kind: "kill" }            SIGKILL to the daemon child
//   { kind: "follow" }          start the status follower
//   { kind: "unfollow" }        end the status follower
//   { kind: "timer", ms }       arm the one timer for MS, or stop it at 0
//   { kind: "check" }           arm the start check for CHECK_MS; its end
//                               comes back as checked
//   { kind: "done", result }    hand RESULT to the stop's callback
//   { kind: "forget" }          drop the stop's callback uncalled
//   { kind: "log", line }       one warning line
// One rule ties a command's end and a daemon word to a recording. `status`
// holds only the daemon's own word, from the follower or from one
// `status` read. A start is taken only while no recording is held, no
// record command pends and that word is idle. Serial completion keeps a
// command's result tied to its recording. The state is read after its
// last command, under a start check before any recording word, or on a
// refused busy start with no outstanding command.
// The voxtype 1.1.0 facts each rule rests on are cited at the rule, by file
// of github.com/peteonrails/voxtype at tag v1.1.0, and measured in the
// report on VGS-1200 (2026-10-10, host cachy).

// How long the daemon has to end after SIGTERM before SIGKILL, and how
// long it has to take a cancel before SIGTERM: it reads the cancel file
// each 100 ms while it records or transcribes (src/daemon.rs:3845-3848,
// 4349-4351).
var GRACE_MS = 2000;
// How long the daemon has to say `recording` after a `record start` that
// ended 0 before it is read. It opens the capture before it writes the word,
// and one that cannot open it writes nothing (src/daemon.rs:4169-4203); the
// VGS-1200 reading 4 (host cachy, 2026-10-10) measured 4.5 to 24.1 ms from
// the command's spawn to `recording`, so a read at once can still answer idle.
var CHECK_MS = 1000;
// `record stop --wait` gives up after this many seconds (exit 4).
var STOP_TIMEOUT_S = 60;
// A `text` recording is cancelled this long before voxtype's own cap. At
// the cap voxtype drops the file override and sends the text to its
// configured output, so it is typed (src/daemon.rs:3995-4027).
var CAP_MARGIN_S = 1;
// The live readiness words in `status`. A live daemon with no readable
// state file also prints `stopped` (src/app/status.rs:47-58).
var LIVE = ["idle", "recording", "streaming", "transcribing"];
var MODES = ["type", "text"];
// What each daemon start reads before the child starts, in order: public
// liveness independent of readiness, then the config values the model needs.
// `config get KEY` prints the resolved value bare (src/app/config_get.rs).
var PROBE = "probe";
// The tag of the one-shot read after a recording's last command.
var STATE = "state";
var STATUS_ARGV = ["voxtype", "status", "--format", "json"];
var DIRECTORY = "directory";
var CLEAN = "clean";
var CONFIG_KEYS = ["audio.max_duration_secs", "engine", "output.mode", "output.auto_submit", "text.smart_auto_submit", "audio.feedback.enabled"];
var SETUP_KEYS = ["version", "model", "models", "engines"];
var OUTPUT_MODES = ["type", "clipboard", "paste", "file"];

// DIR is the 0700 directory the `text` transcripts are written in.
// STATE_PATH is voxtype's documented state_file=auto path, which a killed
// daemon leaves behind because only a graceful shutdown removes it
// (docs/CONFIGURATION.md, src/daemon.rs:4606).
function initial(dir, statePath, outputReady, inputReady) {
    return {
        dir: dir, statePath: statePath, holders: [], daemon: "absent", step: "", child: "none", timer: "none",
        recording: null, late: false, delivery: 0, reconciling: false, files: 0, pending: 0, status: "idle", config: {}, setup: null, elsewhere: false, maxSecs: 0, engine: "", model: "", device: "", typeFlags: [], outputReady: outputReady, inputReady: inputReady
    };
}

function clone(s) { return JSON.parse(JSON.stringify(s)); }

// What a holder may know of the daemon's state: its own word, or `unread`
// from the end of a recording until its last command ended and the daemon
// was read again.
function phase(s) { return s.pending > 0 && s.recording === null ? "unread" : s.status; }

// The capability's bindable `state`.
function state(s) {
    return {
        daemon: s.daemon,
        phase: s.daemon === "ready" ? phase(s) : "idle",
        holder: s.recording === null ? "" : s.recording.holder,
        engine: s.engine, model: s.model, device: s.device,
        setup: s.setup === null ? null : Object.freeze(Object.assign({}, s.setup))
    };
}

// The lending record: no transcript and no path. A child that still takes
// its last cancel is one being stopped.
function record(s) {
    return {
        daemon: s.daemon, child: s.child === "draining" ? "stopping" : s.child, holders: s.holders.slice(),
        holder: s.recording === null ? "" : s.recording.holder,
        mode: s.recording === null ? "" : s.recording.mode
    };
}

function steps(s) {
    var out = [{ tag: PROBE, argv: ["voxtype", "info", "variants", "--json"] }];
    for (var i = 0; i < CONFIG_KEYS.length; i++)
        out.push({ tag: CONFIG_KEYS[i], argv: ["voxtype", "config", "get", CONFIG_KEYS[i]] });
    out.push({ tag: "version", argv: ["voxtype", "--version"] });
    out.push({ tag: "model", argv: ["voxtype", "config", "get", s.engine + ".model"] });
    out.push({ tag: "models", argv: ["voxtype", "info", "models", "--json"] });
    out.push({ tag: "engines", argv: ["voxtype", "info", "engines", "--json"] });
    out.push({ tag: DIRECTORY, argv: ["install", "-d", "-m", "700", "--", s.dir] });
    out.push({ tag: CLEAN, argv: ["rm", "-f", "--", s.statePath] });
    return out;
}

function run(effects, tag, argv) { effects.push({ kind: "run", tag: tag, argv: argv }); }

// Queues a record command or the state read: `pending` counts those whose
// end has not come back.
function command(s, effects, tag, argv) {
    s.pending += 1;
    run(effects, tag, argv);
}

function abort(s, effects) {
    s.pending = 0;
    s.reconciling = false;
    s.delivery += 1;
    effects.push({ kind: "abort" });
}

function setTimer(s, effects, name, ms) {
    s.timer = name;
    effects.push({ kind: "timer", ms: ms });
}

function step(s, effects, tag) {
    var all = steps(s);
    for (var i = 0; i < all.length; i++) {
        if (all[i].tag !== tag) continue;
        s.step = tag;
        run(effects, tag, all[i].argv);
        return;
    }
    throw new Error("dictation: step " + JSON.stringify(tag) + " is not a start step");
}

// Starts the daemon for the holders: at once, or from the exit of a child
// that is still ending.
function begin(s, effects) {
    s.daemon = "starting";
    s.config = {};
    s.setup = null;
    s.elsewhere = false;
    s.typeFlags = [];
    if (s.child !== "none") s.step = "exit";
    else step(s, effects, PROBE);
}

// Ends the child and everything that reads it. The commands queued for it
// go first, so a `record stop --wait` does not wait out a dead daemon.
function endChild(s, effects) {
    abort(s, effects);
    if (s.timer === "audio") setTimer(s, effects, "none", 0);
    if (s.child !== "running" && s.child !== "draining") return;
    s.child = "stopping";
    effects.push({ kind: "unfollow" }, { kind: "term" });
    setTimer(s, effects, "grace", GRACE_MS);
}

// The recording is over without a transcript: its file and voxtype's
// completion sidecar beside it (`P.done`, src/app/record.rs) are removed,
// and a stop that waits is answered with REASON.
function drop(s, effects, reason) {
    var r = s.recording;
    if (r === null) return;
    s.recording = null;
    s.delivery += 1;
    if (s.timer === "cap") setTimer(s, effects, "none", 0);
    if (r.phase === "stopping") effects.push(reason === "" ? { kind: "forget" } : { kind: "done", result: { kind: "failed", reason: reason } });
    if (r.mode === "text") run(effects, "remove", ["rm", "-f", "--", r.path, r.path + ".done"]);
}

// `record cancel` discards the audio and the file override with it
// (src/daemon.rs:3848-3881), so no later recording writes this one's file.
function cancelRecording(s, effects, reason) {
    command(s, effects, "cancel", ["voxtype", "record", "cancel"]);
    drop(s, effects, reason);
}

// The daemon is no longer wanted. SIGTERM leaves the file override of a
// live `text` recording in voxtype's runtime directory (the shutdown at
// src/daemon.rs:4602 removes the profile override alone), and the next
// daemon's `type` recording would write to that file. So such a recording
// is cancelled first, ahead of every queued command, and the child ends
// once the daemon reads idle or the grace is over.
function end(s, effects, reason) {
    var r = s.recording;
    if (s.child === "running" && r !== null && r.mode === "text") {
        abort(s, effects);
        cancelRecording(s, effects, reason);
        s.child = "draining";
        setTimer(s, effects, "drain", GRACE_MS);
        return;
    }
    endChild(s, effects);
    drop(s, effects, reason);
}

function drained(s, effects) {
    if (s.child === "draining" && s.pending === 0 && s.status === "idle") endChild(s, effects);
}

function fail(s, effects, reason) {
    if (s.daemon === "failed") return;
    effects.push({ kind: "log", line: "dictation: daemon=failed reason=" + reason });
    end(s, effects, "daemon-" + reason);
    s.daemon = s.holders.length === 0 ? "absent" : "failed";
    s.step = "";
}

function lease(s, id) {
    if (s.holders.indexOf(id) !== -1) throw new Error("dictation: lease by " + id + " which holds one");
    var t = clone(s), effects = [];
    t.holders.push(id);
    if (t.holders.length === 1) begin(t, effects);
    return { model: t, effects: effects };
}

function release(s, id) {
    if (s.holders.indexOf(id) === -1) throw new Error("dictation: release by " + id + " which holds none");
    var t = clone(s), effects = [];
    t.holders = t.holders.filter(function(h) { return h !== id; });
    if (t.holders.length === 0) {
        end(t, effects, "");
        t.daemon = "absent";
        t.step = "";
    } else if (t.recording !== null && t.recording.holder === id) {
        cancelRecording(t, effects, "");
    }
    return { model: t, effects: effects };
}

function refusal(s, id, verb) {
    if (s.holders.indexOf(id) === -1) throw new Error("dictation: " + verb + " by " + id + " which holds no lease");
    if (verb === "start") return "";
    if (s.recording === null) return "refused: dictation=idle";
    if (s.recording.holder !== id) return "refused: dictation=not-holder holder=" + s.recording.holder;
    if (s.recording.phase === "stopping") return "refused: dictation=stopping";
    return "";
}

function start(s, id, mode) {
    var t = clone(s), effects = [], answer = refusal(t, id, "start");
    if (MODES.indexOf(mode) === -1) answer = "refused: dictation=mode value=" + JSON.stringify(mode);
    else if (t.recording !== null) answer = "refused: dictation=busy holder=" + t.recording.holder;
    else if (t.daemon === "failed") {
        // A refused start keeps no recording intent. A hold released while
        // setup runs must not become a recording after readiness arrives.
        var recovery = restart(t);
        return { model: recovery.model, effects: recovery.effects, answer: "refused: dictation=daemon-" + recovery.model.daemon };
    }
    else if (t.daemon !== "ready") answer = "refused: dictation=daemon-" + t.daemon;
    else if (!t.inputReady) answer = "refused: dictation=audio-unavailable";
    // A start the daemon gets while it transcribes starts nothing, and
    // one queued behind an earlier recording's commands would run among
    // them.
    else if (phase(t) !== "idle") {
        answer = "refused: dictation=engine-busy state=" + phase(t);
        // The follower can print an unread state and then stay silent.
        // Reuse an outstanding read, or read fresh on this press. Only
        // idle retires the old attempt; no recording intent is retained.
        t.reconciling = true;
        if (t.pending === 0) command(t, effects, STATE, STATUS_ARGV);
    }
    if (answer !== "") return { model: t, effects: effects, answer: answer };
    var argv = ["voxtype", "record", "start"];
    t.recording = { holder: id, mode: mode, phase: "starting", path: "" };
    t.late = false;
    if (mode === "text") {
        t.files += 1;
        t.recording.path = t.dir + "/" + t.files + ".txt";
        argv.push("--file=" + t.recording.path, "--no-auto-submit", "--no-smart-auto-submit", "--no-osd");
        setTimer(t, effects, "cap", (t.maxSecs - CAP_MARGIN_S) * 1000);
    } else if (mode === "type") {
        argv = argv.concat(t.typeFlags);
    }
    command(t, effects, "start", argv);
    return { model: t, effects: effects, answer: "ok" };
}

function stop(s, id) {
    var t = clone(s), effects = [], answer = refusal(t, id, "stop");
    if (answer !== "") return { model: t, effects: effects, answer: answer };
    t.recording.phase = "stopping";
    if (t.timer === "cap") setTimer(t, effects, "none", 0);
    command(t, effects, "stop", t.recording.mode === "text"
        ? ["voxtype", "record", "stop", "--wait", "--json", "--timeout", String(STOP_TIMEOUT_S)]
        : ["voxtype", "record", "stop"]);
    return { model: t, effects: effects, answer: "ok" };
}

function cancel(s, id) {
    var t = clone(s), effects = [], answer = refusal(t, id, "cancel");
    if (answer !== "") return { model: t, effects: effects, answer: answer };
    cancelRecording(t, effects, "");
    return { model: t, effects: effects, answer: "ok" };
}

// Reads the daemon again from nothing: the probe, the config and a new
// child, after the end of the one that runs. A child that still takes its
// last cancel ends on its own.
function restart(s) {
    var t = clone(s), effects = [], answer = "";
    if (t.recording !== null) answer = "refused: dictation=busy holder=" + t.recording.holder;
    else if (t.holders.length === 0) answer = "refused: dictation=no-holder";
    if (answer !== "") return { model: t, effects: effects, answer: answer };
    if (t.child !== "draining") endChild(t, effects);
    begin(t, effects);
    return { model: t, effects: effects, answer: "ok" };
}

// What `record stop --wait --json` answered: one JSON object with `status`
// and `text`, exit 0 for `ok`, 3 for `empty`, 4 for `timeout` and 1 with
// no JSON for any other end (src/app/record.rs:243-250, 352-360).
function transcript(code, out) {
    var data = null;
    try {
        data = JSON.parse(out);
    } catch (e) {
        data = null;
    }
    if (data === null || typeof data !== "object" || typeof data.status !== "string" || typeof data.text !== "string")
        return { kind: "failed", reason: "stop code=" + (code === null ? "none" : code) };
    if (data.status === "empty" || (data.status === "ok" && data.text.trim() === "")) return { kind: "empty" };
    if (data.status === "ok") return { kind: "text", text: data.text };
    return { kind: "failed", reason: "stop status=" + data.status.slice(0, 40) };
}

function configured(s) {
    var secs = Number(s.config["audio.max_duration_secs"]);
    if (!Number.isInteger(secs) || secs <= CAP_MARGIN_S) return "config max_duration_secs=" + JSON.stringify(s.config["audio.max_duration_secs"]);
    var mode = s.config["output.mode"];
    if (OUTPUT_MODES.indexOf(mode) === -1) return "config output.mode=" + JSON.stringify(mode);
    var autoSubmit = s.config["output.auto_submit"];
    if (autoSubmit !== "true" && autoSubmit !== "false") return "config output.auto_submit=" + JSON.stringify(autoSubmit);
    var smartAutoSubmit = s.config["text.smart_auto_submit"];
    if (smartAutoSubmit !== "true" && smartAutoSubmit !== "false") return "config text.smart_auto_submit=" + JSON.stringify(smartAutoSubmit);
    if (["true", "false"].indexOf(s.config["audio.feedback.enabled"]) === -1) return "config audio.feedback.enabled=unread";
    s.maxSecs = secs;
    // The daemon's --audio-device default override routes capture to
    // PipeWire's selected source, including with an existing raw ALSA name.
    s.device = "default";
    s.engine = s.config.engine;
    // `record start` writes these per-recording override files before it
    // signals the daemon (src/app/record.rs:36-68). A killed recording can
    // leave the prior files; voxtype clears them only at output, cancel,
    // cap and reset (src/daemon.rs:2623, 2754).
    s.typeFlags = [
        autoSubmit === "true" ? "--auto-submit" : "--no-auto-submit",
        smartAutoSubmit === "true" ? "--smart-auto-submit" : "--no-smart-auto-submit",
        "--" + mode
    ];
    return "";
}

function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function parseJson(text, fallback) {
    try { return JSON.parse(text); } catch (e) { return fallback; }
}

function modelRows(modelsText, engine) {
    var data = parseJson(modelsText, null);
    if (!isObject(data) || !isObject(data.engines) || !isObject(data.engines[engine]) || !Array.isArray(data.engines[engine].models)) return [];
    return data.engines[engine].models;
}

function modelInstalled(modelsText, engine, wanted) {
    var models = modelRows(modelsText, engine);
    for (var i = 0; i < models.length; i++) {
        var row = models[i];
        if (isObject(row) && row.name === wanted && row.installed === true) return true;
    }
    return false;
}

function engineAvailable(enginesText, wanted) {
    var engines = parseJson(enginesText, null);
    if (!Array.isArray(engines)) return false;
    for (var i = 0; i < engines.length; i++) {
        var row = engines[i];
        if (isObject(row) && row.name === wanted) return row.compiled === true;
    }
    return false;
}

// `info variants --json` serializes Inventory.daemon_pid: Option<i32>,
// from read_pid_if_alive, independently of the readiness file (voxtype
// v1.1.0, src/setup/binary.rs:541-555, 839-845; src/daemon_status.rs:27-58).
// Explicit null is upstream's no-observed-live-PID result, which also
// folds unreadable locks into absence. Missing or invalid public output
// is unreadable here. This PID never grants authority to signal a process.
function ownershipOf(text) {
    var data = parseJson(text, null);
    if (!isObject(data)) return "unread";
    if (data.daemon_pid === null) return "absent";
    if (!Number.isInteger(data.daemon_pid) || data.daemon_pid <= 1 || data.daemon_pid > 2147483647) return "unread";
    return "elsewhere";
}

// One start step ended with CODE and OUT.
function stepped(s, effects, tag, code, out) {
    var text = out.trim();
    if (code !== 0) {
        fail(s, effects, tag + " code=" + (code === null ? "none" : code));
        return;
    }
    if (tag === PROBE) {
        var ownership = ownershipOf(text);
        if (ownership === "unread") {
            fail(s, effects, "probe liveness=unread");
        } else {
            // begin waits for our Process to exit before this probe. A
            // live PID here belongs elsewhere, including during model load.
            s.elsewhere = ownership === "elsewhere";
            step(s, effects, CONFIG_KEYS[0]);
        }
        return;
    }
    if (tag === DIRECTORY) {
        // voxtype writes its pid before it loads its model, and
        // `status --follow` can read the old state while that pid lives
        // (src/daemon_status.rs:160, src/app/status.rs). The new daemon's
        // first own word comes only after the model load (src/daemon.rs:3329).
        step(s, effects, CLEAN);
        return;
    }
    if (tag === CLEAN) {
        s.step = "audio";
        if (audioAvailable(s)) launch(s, effects);
        // This reuses the shutdown grace as a chosen startup failure
        // deadline, not a measured PipeWire startup latency budget.
        else setTimer(s, effects, "audio", GRACE_MS);
        return;
    }
    s.config[tag] = text;
    if (SETUP_KEYS.indexOf(tag) !== -1) {
        var nextSetup = SETUP_KEYS[SETUP_KEYS.indexOf(tag) + 1];
        if (nextSetup !== undefined) step(s, effects, nextSetup);
        else {
            s.setup = {
                engine: s.engine, model: s.config.model, version: s.config.version,
                compiled: engineAvailable(s.config.engines, s.engine),
                installed: modelInstalled(s.config.models, s.engine, s.config.model)
            };
            // The daemon itself notifies on an unavailable engine. Keep it
            // absent until its existing setup readings permit the start.
            if (s.elsewhere || !s.setup.compiled || !s.setup.installed) {
                s.daemon = s.elsewhere ? "elsewhere" : "absent";
                s.step = "";
            } else step(s, effects, DIRECTORY);
        }
        return;
    }
    var next = CONFIG_KEYS[CONFIG_KEYS.indexOf(tag) + 1];
    if (next !== undefined) step(s, effects, next);
    else {
        var problem = configured(s);
        if (problem === "") step(s, effects, SETUP_KEYS[0]);
        else fail(s, effects, problem);
    }
}

function audioAvailable(s) {
    return s.inputReady && (s.config["audio.feedback.enabled"] === "false" || s.outputReady);
}

function launch(s, effects) {
    if (s.timer === "audio") setTimer(s, effects, "none", 0);
    s.step = "child";
    s.child = "running";
    effects.push({ kind: "daemon" }, { kind: "follow" });
}

// Pipewire's initial sync and default-node property changes feed this
// event. A ready daemon keeps running across transient default changes.
function audio(s, outputReady, inputReady) {
    var t = clone(s), effects = [];
    t.outputReady = outputReady;
    t.inputReady = inputReady;
    if (t.daemon === "starting" && t.step === "audio" && audioAvailable(t)) launch(t, effects);
    return { model: t, effects: effects };
}

// The last record command of an ended recording ended: the daemon is read
// once. `voxtype status --follow` prints a state only when it differs from
// the last one it printed (src/app/status.rs:107-119), so a daemon that
// never left idle, or one whose lines are still on their way, is not
// known from the follower alone.
function settle(s, effects) {
    if (s.pending === 0 && s.recording === null) command(s, effects, STATE, STATUS_ARGV);
}

// The command TAG ended: CODE is its exit code, null for one that did not
// start or ended on a signal, and OUT its stdout.
function ran(s, tag, code, out) {
    var t = clone(s), effects = [], r = t.recording;
    // The stream supervisor reserves 74 for a raw byte/record bound. A
    // flooded command invalidates this daemon, not just that command.
    if (code === 74) {
        fail(t, effects, "stream-overflow role=command");
        return { model: t, effects: effects };
    }
    if ([STATE, "start", "stop", "cancel"].indexOf(tag) !== -1) {
        if (t.pending === 0) throw new Error("dictation: command " + JSON.stringify(tag) + " ended with none pending");
        t.pending -= 1;
    }
    switch (tag) {
    case "start":
        // `record start` exits 0 once it signalled a live daemon
        // (src/app/record.rs:22-26, 188), whether or not a recording
        // then runs.
        if (r !== null && code !== 0) drop(t, effects, "start code=" + (code === null ? "none" : code));
        else if (r !== null && r.phase === "starting") {
            r.phase = "recording";
            effects.push({ kind: "check" });
        }
        settle(t, effects);
        break;
    case "stop":
        if (r !== null && r.phase === "stopping") {
            var result = r.mode === "text" ? transcript(code, out) : code === 0 ? { kind: "typed" } : { kind: "failed", reason: "stop code=" + (code === null ? "none" : code) };
            t.recording = null;
            effects.push({ kind: "done", result: result });
            // A stop that gave up leaves the daemon transcribing with
            // the override in place, to write the file after its
            // removal; a cancel ends that task and the override
            // (src/daemon.rs:4349-4367).
            if (r.mode === "text" && result.kind === "failed") command(t, effects, "cancel", ["voxtype", "record", "cancel"]);
            if (r.mode === "text") run(effects, "remove", ["rm", "-f", "--", r.path, r.path + ".done"]);
        }
        settle(t, effects);
        break;
    case "cancel":
        if (code !== 0) effects.push({ kind: "log", line: "dictation: cancel=failed code=" + (code === null ? "none" : code) });
        settle(t, effects);
        break;
    case "remove":
        if (code !== 0) effects.push({ kind: "log", line: "dictation: remove=failed code=" + (code === null ? "none" : code) });
        break;
    case STATE:
        var read = code === 0 ? phaseOf(statusOf(out.trim())) : null;
        // An alive child with no readable state prints stopped too.
        // Recovery cannot treat that as progress or reset it to idle.
        if (t.reconciling && read === "stopped") read = null;
        if (t.reconciling && read === "idle") t.delivery += 1;
        t.reconciling = false;
        if (read === null) fail(t, effects, "state " + (code === 0 ? "status=unread" : "code=" + (code === null ? "none" : code)));
        // `stopped`: the child's exit reports a daemon that ended. Only
        // checked reads the daemon under a held recording, while the
        // follower's word is idle; a word the follower printed since is
        // newer than the read.
        else if (read !== "stopped" && (r === null || t.status === "idle")) t.status = read;
        // A daemon still idle at the check has not recorded, but may yet:
        // its start handler awaits the media pause and the capture open
        // before it writes `recording` (src/daemon.rs:4083-4203). So the
        // dropped recording is marked, and status cancels a late one.
        if (read === "idle" && r !== null && r.phase === "recording" && t.status === "idle") {
            drop(t, effects, "");
            t.late = true;
        }
        drained(t, effects);
        break;
    default:
        if (t.daemon !== "starting" || t.step !== tag) throw new Error("dictation: command " + JSON.stringify(tag) + " ended at step " + JSON.stringify(t.step));
        stepped(t, effects, tag, code, out);
    }
    return { model: t, effects: effects };
}

// One line of `status --format json`: { word, model }, or null for a line
// that is not the object status prints (src/status_json.rs: `alt` holds the
// state, `model` the model under --extended).
function statusOf(line) {
    var data = null;
    try {
        data = JSON.parse(line);
    } catch (e) {
        return null;
    }
    if (data === null || typeof data !== "object" || typeof data.alt !== "string") return null;
    return { word: data.alt, model: typeof data.model === "string" ? data.model : "" };
}

// What a read of the daemon says of it: `idle`, `recording` (voxtype's
// `streaming` is one), `transcribing` or `stopped`, or null for a read
// that is none of them.
function phaseOf(read) {
    if (read === null || (LIVE.indexOf(read.word) === -1 && read.word !== "stopped")) return null;
    return read.word === "streaming" ? "recording" : read.word;
}

// One line the follower printed.
function status(s, line) {
    var t = clone(s), effects = [], read = statusOf(line), word = phaseOf(read);
    if (t.child !== "running" && t.child !== "draining") return { model: t, effects: effects };
    if (word === null) {
        effects.push({ kind: "log", line: "dictation: status=unread line=" + JSON.stringify(line.slice(0, 80)) });
        return { model: t, effects: effects };
    }
    // The follower prints `stopped` until the daemon holds its lock, and
    // the child's exit reports a daemon that ended.
    if (word === "stopped") return { model: t, effects: effects };
    t.status = word;
    t.model = read.model;
    if (t.daemon === "starting" && t.step === "child") {
        t.daemon = "ready";
        t.step = "";
    }
    // The daemon went idle under a recording it was signalled for and no
    // stop of this owner ended: its own cap, or a caller outside the
    // shell. A line that comes before the recording's `record start`
    // ended is of an earlier recording, and a stop that waits takes the
    // transcript the daemon wrote before it went idle.
    if (t.status === "idle" && t.recording !== null && t.recording.phase === "recording") drop(t, effects, "");
    // The recording the start check dropped began after all: nothing holds
    // it, and at voxtype's own cap it would be typed. The cancel file it
    // reads while it records was written after its start had removed the
    // stale one (src/daemon.rs:1136-1148).
    if (t.status === "recording" && t.recording === null && t.late) {
        t.late = false;
        effects.push({ kind: "log", line: "dictation: recording=cancelled reason=late-start" });
        command(t, effects, "cancel", ["voxtype", "record", "cancel"]);
    }
    drained(t, effects);
    return { model: t, effects: effects };
}

// The daemon child ended; CODE is null for one that did not start.
function exited(s, code, complaint) {
    if (s.child === "none") throw new Error("dictation: exit with no child");
    var t = clone(s), effects = [], was = t.child;
    t.child = "none";
    t.status = "idle";
    t.late = false;
    if (t.timer === "grace" || t.timer === "drain") setTimer(t, effects, "none", 0);
    if (was !== "stopping") effects.push({ kind: "unfollow" });
    if (was === "running") {
        var daemonReason = code === 74 ? "stream-overflow role=daemon" : "ended code=" + (code === null ? "none" : code);
        if (complaint) daemonReason += " stderr=" + JSON.stringify(complaint);
        fail(t, effects, daemonReason);
        return { model: t, effects: effects };
    }
    if (was === "draining") abort(t, effects);
    if (t.daemon === "starting" && t.step === "exit") step(t, effects, PROBE);
    return { model: t, effects: effects };
}

// The start check ended: a recording the daemon has not said `recording`
// for is read once, as the follower prints nothing for a daemon that never
// left idle. A later start re-arms the check, so it ends CHECK_MS after the
// last start command.
function checked(s) {
    var t = clone(s), effects = [], r = t.recording;
    if (r !== null && r.phase === "recording" && t.status === "idle") command(t, effects, STATE, STATUS_ARGV);
    return { model: t, effects: effects };
}

// The follower ended on its own while the child runs: nothing reads the
// daemon any more.
function unfollowed(s, code, complaint) {
    var t = clone(s), effects = [];
    if (t.child === "running") fail(t, effects, (code === 74 ? "stream-overflow role=follower" : "follower-ended") + (complaint ? " stderr=" + JSON.stringify(complaint) : ""));
    return { model: t, effects: effects };
}

function deadline(s) {
    var t = clone(s), effects = [], timer = t.timer;
    t.timer = "none";
    if (timer === "audio" && t.daemon === "starting" && t.step === "audio") {
        fail(t, effects, "audio-unavailable");
    } else if (timer === "cap" && t.recording !== null) {
        effects.push({ kind: "log", line: "dictation: recording=cancelled reason=cap holder=" + t.recording.holder });
        cancelRecording(t, effects, "");
    } else if (timer === "grace" && t.child === "stopping") {
        effects.push({ kind: "kill" });
    } else if (timer === "drain" && t.child === "draining") {
        effects.push({ kind: "log", line: "dictation: cancel=unread state=" + t.status });
        endChild(t, effects);
    } else {
        throw new Error("dictation: timer " + timer + " fired with nothing to end");
    }
    return { model: t, effects: effects };
}
