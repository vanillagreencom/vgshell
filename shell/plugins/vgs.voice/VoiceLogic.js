.pragma library

// The plugin id the `dictation` capability names as a recording's holder.
var HOLDER = "vgs.voice";
var DEFAULT_ENGINE = "parakeet";
var DEFAULT_MODEL = "parakeet-tdt-0.6b-v3";

function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function parseJson(text, fallback) {
    try {
        return JSON.parse(text);
    } catch (e) {
        return fallback;
    }
}

// The dictation Voice shows from STATE, the `dictation` capability's, and
// OWN, whether the last one it showed was its own: { own, phase }. A phase
// shows only while Voice holds the recording, and through the
// transcription after it: `record stop` ends before voxtype has the words,
// so the capability then names no holder, and it takes no other start
// until the daemon reads idle. Another holder's recording reads idle.
function ownDictation(state, own) {
    if (state.holder === HOLDER) return { own: true, phase: state.phase };
    var after = own && state.holder === "" && (state.phase === "unread" || state.phase === "transcribing");
    return { own: after, phase: after ? "transcribing" : "idle" };
}

// The version `voxtype --version` prints, as `voxtype 1.1.0`, or "".
function versionOf(text) {
    var found = /\b(\d+\.\d+(?:\.\d+)?)\b/.exec(String(text));
    return found === null ? "" : found[1];
}

// What Set up's state says of the voxtype the core runs, by the
// capability's `daemon` word, "" for one that needs no line: `starting`
// and `ready`.
var DAEMON_LINES = {
    absent: "Dictation is not running. Select Set up to start it.",
    starting: "",
    ready: "",
    elsewhere: "Another voxtype is already running. Stop the other voxtype so VGS can start its own.",
    failed: "Dictation is not running. Select Set up to start it."
};

// Set up's state from READS, the core's typed setup readings, with
// null while the core reads setup or when that read failed, `present`
// false while voxtype is not found, and DAEMON, the capability's
// `daemon` word: { tone, text, lines, action, engine, model }, or
// { hidden, lines, action, engine, model } without voxtype, which
// setupPublished states as a step the Review action on its own row
// installs. Ready reads the version and the model; otherwise each line
// names one thing that is missing. `action` names the manifest's step
// that applies: `stop` while another voxtype holds the daemon's place,
// whatever else is missing, since the core's setup cannot free it,
// `setup` while another line stands, "" once ready and without voxtype.
function setupState(reads, daemon) {
    if (reads !== null && reads.present === false)
        return { hidden: true, lines: [], action: "", engine: DEFAULT_ENGINE, model: DEFAULT_MODEL };
    if (DAEMON_LINES[daemon] === undefined)
        throw new Error("voice: daemon " + JSON.stringify(daemon) + " is not one of " + Object.keys(DAEMON_LINES).join(", "));
    if (reads === null) {
        var failed = daemon === "failed";
        return { tone: failed ? "warning" : "info", text: failed ? "To do" : "Checking",
            lines: failed ? [DAEMON_LINES.failed] : [], action: failed ? "setup" : "",
            engine: DEFAULT_ENGINE, model: DEFAULT_MODEL };
    }
    var engine = reads.engine || DEFAULT_ENGINE;
    var model = reads.model || DEFAULT_MODEL;
    var lines = [];
    // Set up is offered on every path but `stop`, whose row offers no action.
    if (!reads.compiled) lines.push("The installed dictation tool cannot use this speech engine." + (daemon === "elsewhere" ? "" : " Select Set up to fix it."));
    if (!reads.installed) lines.push("The " + model + " speech model is not installed.");
    if (DAEMON_LINES[daemon] !== "" && (daemon !== "absent" || lines.length === 0)) lines.push(DAEMON_LINES[daemon]);
    if (lines.length > 0) return { tone: "warning", text: "To do", lines: lines, action: daemon === "elsewhere" ? "stop" : "setup", engine: engine, model: model };
    if (daemon === "starting") return { tone: "info", text: "Checking", lines: [], action: "", engine: engine, model: model };
    var version = versionOf(reads.version || "");
    var summary = (version === "" ? "voxtype" : "voxtype " + version) + " \u00b7 " + model;
    return { tone: "ok", text: "Ready", lines: [summary], action: "", engine: engine, model: model };
}

// The `setup` entry's value from STATE, setupState's. Without voxtype the
// step waits on the one install action, PluginLogic.STATUS_TOOLS_ACTION,
// which the page offers as Review on the step's row. While another voxtype
// holds the daemon's place the step offers no action: its hint points at
// Stop the other voxtype beside its fact on Details. Otherwise the step
// offers Set up while setupState names it.
function setupPublished(state) {
    if (state.hidden) return { tone: "warning", text: "Not installed", hint: "Install the dictation tool to use Voice", action: "tools" };
    var value = { tone: state.tone, text: state.text };
    if (state.lines !== undefined && state.lines.length > 0) value.lines = state.lines;
    value.action = state.action === "setup";
    if (state.action === "stop") value.hint = "Choose Stop the other voxtype under [Other dictation service](page:vgs.voice/Details)";
    return value;
}

// The on-screen display's level from one voxtype-audio-bridge frame, as the
// owner's plasma design reads it: the louder of the peak and RMS_WEIGHT times
// the RMS, times LEVEL_GAIN, raised to LEVEL_GAMMA. The gamma under 1 lifts
// quiet speech without moving silence, and ordinary speech reaches 1.
var RMS_WEIGHT = 1.7;
var LEVEL_GAIN = 6.0;
var LEVEL_GAMMA = 0.62;

function amplitude(value) {
    return typeof value === "number" && isFinite(value) && value >= 0;
}

// One stdout line of voxtype-audio-bridge: a frame with `peak` and `rms`, or
// a `connected` or `disconnected` status line.
function parseFrame(line) {
    var frame = parseJson(line, null);
    if (!isObject(frame)) return { ok: false, reason: "json" };
    if (frame.status === "connected" || frame.status === "disconnected") return { ok: true, kind: frame.status };
    if (!amplitude(frame.peak) || !amplitude(frame.rms)) return { ok: false, reason: "frame" };
    return { ok: true, kind: "frame", peak: frame.peak, rms: frame.rms };
}

function frameLevel(peak, rms) {
    return Math.min(1, Math.pow(Math.max(peak, rms * RMS_WEIGHT) * LEVEL_GAIN, LEVEL_GAMMA));
}

// The Model row: the engine and the model of the daemon the core runs,
// from STATE, the capability's, and SETUP's, the configured ones, while no
// daemon has named its own.
function modelData(state, setup) {
    return { engine: state.engine !== "" ? state.engine : setup.engine, model: state.model !== "" ? state.model : setup.model };
}

// The screens whose end with code 0 has the core start its daemon again:
// Configure and Choose model change voxtype's config, which a daemon reads
// when it starts, and Stop the other voxtype frees the place the core's
// daemon takes, which the core reads only when it starts one.
var RESTART_TUIS = ["configure", "model", "stop-other"];

// Whether RUN, one entry of shell.tui.state, holds a run that ended with
// code 0 since SEEN, the endedAt this instance read last. SEEN is
// undefined before the instance's first read, so a run that ended before
// the instance started restarts nothing.
function runFinished(seen, run) {
    return seen !== undefined && run.endedAt !== null && run.endedAt !== seen && run.code === 0;
}

// Dictation sounds are voxtype's own tones. Their one holder is voxtype's
// config, `audio.feedback.enabled`, which a hand edit and voxtype's own
// Configure screen also write, so the service reads the value there and
// states it to the Sounds page (the manifest's held sound event). The
// page's choice runs FEEDBACK_STAGES, one command each: read the value and
// stop when it already is the choice, so nothing is written and nothing
// restarts; read what the config file is; write through voxtype's own
// `config set`; have the core start its voxtype daemon again, which reads
// the config; read the value back.
var FEEDBACK_KEY = "audio.feedback.enabled";
var FEEDBACK_ON = "own";
var FEEDBACK_OFF = "";
var FEEDBACK_STAGES = ["read", "kind", "write", "restart", "verify"];

// What each problem of a feedback run tells the user on the event's row,
// whose page reference the Sounds pane opens; the key is the log's.
var FEEDBACK_PROBLEMS = {
    "": "",
    "missing": "Voice records speech with voxtype. Install it on the [Voice page](page:vgs.voice/Setup).",
    "unread": "VGS could not read the voxtype settings.",
    "no-config": "Voice is not set up. Use Set up on the [Voice page](page:vgs.voice/Setup).",
    "link": "Your voxtype config is a link to another file, so VGS did not change it. Use Configure on the [Voice page](page:vgs.voice/Settings).",
    "write": "VGS could not change the voxtype settings.",
    "restart": "The change is saved. It applies when voxtype starts again.",
    "mismatch": "voxtype did not keep the change."
};

// The value in the stdout of `voxtype config get audio.feedback.enabled
// --json`, which voxtype 1.1.0 prints as { "file_value", "key", "value" }
// with `value` the one in effect (host cachy, 2026-10-09): FEEDBACK_ON,
// FEEDBACK_OFF, or null for anything else.
function feedbackValue(text) {
    var data = parseJson(text, null);
    if (!isObject(data) || typeof data.value !== "boolean") return null;
    return data.value ? FEEDBACK_ON : FEEDBACK_OFF;
}

// What the config file is, from the stdout of `stat --format=%f`, the raw
// mode in hex: `file`, `link` for a symbolic link, else `none`. voxtype's
// `config set` replaces a symbolic link with a regular file and leaves the
// file it pointed at as it was (voxtype 1.1.0 in a scratch home, host
// cachy, 2026-10-09), so a link is refused, as Configure warns of one.
function fileKind(text) {
    var type = parseInt(String(text).trim(), 16) & 0xf000;
    return type === 0x8000 ? "file" : type === 0xa000 ? "link" : "none";
}

// The command of STAGE of a feedback run that wants WANTED, with the
// config file at CONFIG_FILE, or null for `restart`, which runs none: the
// service asks the `dictation` capability.
function feedbackCommand(stage, wanted, configFile) {
    switch (stage) {
    case "read":
    case "verify": return ["voxtype", "config", "get", FEEDBACK_KEY, "--json"];
    case "kind": return ["stat", "--format=%f", "--", configFile];
    case "write": return ["voxtype", "config", "set", FEEDBACK_KEY, wanted === FEEDBACK_ON ? "true" : "false"];
    case "restart": return null;
    }
    throw new Error("voice: feedback stage " + JSON.stringify(stage) + " is not one of " + FEEDBACK_STAGES.join(", "));
}

// A feedback run that starts: WANTED is FEEDBACK_ON or FEEDBACK_OFF, the
// page's choice, or null for a read alone.
function feedbackRun(wanted) {
    return { stage: "read", wanted: wanted, value: null, problem: "" };
}

// RUN after its stage ended with exit CODE and stdout OUT: { stage,
// wanted, value, problem }, `stage` the next one or `done`, `value` the
// last one read and `problem` a key of FEEDBACK_PROBLEMS. The restart
// stage's CODE is 0 when the capability took the restart; when it refused,
// the write stands and the run says the change waits for voxtype's next
// start.
function feedbackNext(run, code, out) {
    var next = { stage: "done", wanted: run.wanted, value: run.value, problem: run.problem };
    switch (run.stage) {
    case "read":
        next.value = code === 0 ? feedbackValue(out) : null;
        if (next.value === null) next.problem = "unread";
        else if (run.wanted !== null && next.value !== run.wanted) next.stage = "kind";
        return next;
    case "kind":
        var kind = code === 0 ? fileKind(out) : "none";
        if (kind === "file") next.stage = "write";
        else next.problem = kind === "link" ? "link" : "no-config";
        return next;
    case "write":
        if (code !== 0) next.problem = "write";
        else next.stage = "restart";
        return next;
    case "restart":
        if (code !== 0) next.problem = "restart";
        next.stage = "verify";
        return next;
    case "verify":
        next.value = code === 0 ? feedbackValue(out) : null;
        if (next.value === null) next.problem = "unread";
        else if (next.value !== run.wanted) next.problem = "mismatch";
        return next;
    }
    throw new Error("voice: feedback stage " + JSON.stringify(run.stage) + " is not one of " + FEEDBACK_STAGES.join(", "));
}
