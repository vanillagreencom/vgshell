.pragma library
.import "Session.js" as Session

// Shell produces hello, intent, indicator, shown, requirements-scan, tui-state and reply. Voice confirmation
// is daemon-internal. Daemon produces status/state/devices/level/audio-fault,
// request, tasks, task-answer and transcript. A line excludes its LF.
// A transcript is one speaker's caption segment: partial text grows under
// a rising rev; final closes the segment.
var MAX_LINE_BYTES = 256 * 1024;
var TASK_TERMINALS = ["auto", "tmux", "floating"];
// The manifest's cloudVision options; Policy.recipients judges the same set.
var CLOUD_VISION = ["ask", "allow", "never"];
var TRANSCRIPT_CHARS = Session.TRANSCRIPT_CHARS;

// Requests the daemon sends and the service answers, one reply each. `args`
// lists each argument's type, or "argv" for a command; `data` names the
// reply's data shape. `acts` marks a request that changes the desktop,
// which the service refuses while the session is locked.
// Shell.compositor owns each dispatcher's argument rules.
var REQUESTS = {
    "compositor.focusWorkspace": { args: ["text"], data: "none", acts: true },
    "compositor.focusWindow": { args: ["text"], data: "none", acts: true },
    "compositor.moveWindowToWorkspace": { args: ["text", "text"], data: "none", acts: true },
    "compositor.toggleSpecialWorkspace": { args: ["text"], data: "none", acts: true },
    "compositor.closeWindow": { args: ["text"], data: "none", acts: true },
    "compositor.fullscreenWindow": { args: ["text", "text"], data: "none", acts: true },
    "compositor.floatWindow": { args: ["text", "text"], data: "none", acts: true },
    "compositor.moveWindow": { args: ["text", "integer", "integer"], data: "none", acts: true },
    "compositor.resizeWindow": { args: ["text", "integer", "integer"], data: "none", acts: true },
    "compositor.focusMonitor": { args: ["text"], data: "none", acts: true },
    "compositor.moveCursor": { args: ["integer", "integer"], data: "none", acts: true },
    "input.observe": { args: "input-point", data: "input", acts: false },
    "input.keys": { args: "argv", data: "keys", acts: false },
    "compositor.reveal": { args: ["text"], data: "none", acts: true },
    "run.detached": { args: "argv", data: "none", acts: true },
    "desktop.launch": { args: ["text"], data: "entry", acts: true },
    "desktop.list": { args: [], data: "entries", acts: false },
    "tui.run": { args: "task-spec", data: "none", acts: true }
};
// Requests awaiting a reply, the plan's bound. The daemon refuses the next.
var MAX_PENDING_REQUESTS = 16;
var TEXT_MAX = 4096;
var ARGV_MAX = 64;
var ANSWER_MAX = 300;
var FIELD_MAX = 128;
var ENTRIES_MAX = 512;
// Desktop entries stop here, so a list reply stays far below MAX_LINE_BYTES.
var ENTRIES_BYTES = 192 * 1024;

function fail(reason) {
    throw new Error("jarvis: protocol=" + reason);
}

function object(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function keys(value, wanted, name) {
    if (!object(value) || Object.keys(value).sort().join(",") !== wanted.slice().sort().join(","))
        fail("shape-" + name);
}

// Count UTF-8 bytes in QML too, where Buffer and TextEncoder are absent.
function bytes(text) {
    var count = 0;
    for (var i = 0; i < text.length; i++) {
        var code = text.charCodeAt(i);
        if (code < 0x80) count++;
        else if (code < 0x800) count += 2;
        else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length
                 && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) {
            count += 4;
            i++;
        } else count += 3;
    }
    return count;
}

function bounded(line) {
    if (bytes(line) > MAX_LINE_BYTES) fail("line-too-long");
}

// Both streaming endpoints call this before retaining an unfinished line.
function feed(tail, chunk) {
    var parts = (tail + chunk).split("\n");
    for (var i = 0; i < parts.length; i++) bounded(parts[i]);
    return { lines: parts.slice(0, -1), tail: parts[parts.length - 1] };
}

function directory(value) {
    return typeof value === "string" && value.length > 1 && value[0] === "/" && !/[\x00-\x1f\x7f]/.test(value);
}

function text(value) {
    return typeof value === "string" && value.length >= 1 && value.length <= TEXT_MAX && value.indexOf("\u0000") === -1;
}

function printable(value, min, max) {
    return typeof value === "string" && value.length >= min && value.length <= max && !/[\x00-\x1f\x7f]/.test(value);
}

function argv(value) {
    return Array.isArray(value) && value.length >= 1 && value.length <= ARGV_MAX && value.every(text);
}

function requestArgs(kind, args) {
    var rule = REQUESTS[kind].args;
    if (rule === "input-point") return Array.isArray(args) && (args.length === 0 || args.length === 2 && args.every(Number.isSafeInteger));
    if (rule === "task-spec")
        return Array.isArray(args) && args.length === 1 && directory(args[0]);
    if (rule === "argv") return argv(args);
    if (!Array.isArray(args) || args.length !== rule.length) return false;
    for (var i = 0; i < rule.length; i++)
        if (rule[i] === "text" ? !text(args[i]) : !Number.isSafeInteger(args[i])) return false;
    return true;
}

// The wire form of one desktop entry the service read, or null when an
// entry cannot cross: hidden or unnamed by a printable id. A launch reply
// adds `terminal`, since a terminal entry's window carries the terminal's
// class; a list reply omits it.
function desktopEntry(entry, withTerminal) {
    if (entry === null || typeof entry !== "object" || entry.noDisplay === true) return null;
    if (!printable(entry.id, 1, FIELD_MAX)) return null;
    var value = { id: entry.id, name: String(entry.name || "").replace(/[\x00-\x1f\x7f]/g, " ").slice(0, FIELD_MAX),
        startupClass: String(entry.startupClass || "").replace(/[\x00-\x1f\x7f]/g, " ").slice(0, FIELD_MAX) };
    if (withTerminal) value.terminal = entry.terminal === true;
    return value;
}

// The list reply's data from every entry the service read: sorted by id,
// bounded by ENTRIES_MAX and ENTRIES_BYTES; `complete` says none was cut.
function desktopEntries(entries) {
    var values = entries.map(function (entry) { return desktopEntry(entry, false); })
        .filter(function (entry) { return entry !== null; })
        .sort(function (a, b) { return a.id < b.id ? -1 : a.id > b.id ? 1 : 0; });
    var kept = [];
    var size = 0;
    for (var i = 0; i < values.length && kept.length < ENTRIES_MAX; i++) {
        size += bytes(JSON.stringify(values[i])) + 1;
        if (size > ENTRIES_BYTES) break;
        kept.push(values[i]);
    }
    return { entries: kept, complete: kept.length === values.length };
}

// The service's answer to KIND before any capability runs: a keyed refusal
// for a request that changes the desktop while the session is locked, else
// "". Policy judged the lock when the action started; a lock observed since
// stops the requests that remain.
function lockedRefusal(kind, locked) {
    return locked !== false && REQUESTS[kind].acts ? "refused: locked" : "";
}

// A shell call's answer as the reply carries it: one printable line.
function answer(value) {
    var line = String(value).replace(/[\x00-\x1f\x7f]/g, " ").slice(0, ANSWER_MAX);
    return line === "" ? "refused: answer=empty" : line;
}

function entryShape(value, withTerminal) {
    keys(value, withTerminal ? ["id", "name", "startupClass", "terminal"] : ["id", "name", "startupClass"], "entry");
    if (!printable(value.id, 1, FIELD_MAX) || !printable(value.name, 0, FIELD_MAX)
            || !printable(value.startupClass, 0, FIELD_MAX)) fail("entry");
    if (withTerminal && typeof value.terminal !== "boolean") fail("entry");
}

function replyData(message) {
    var shape = REQUESTS[message.kind].data;
    if (shape === "none" || message.answer !== "ok") {
        if (message.data !== null) fail("reply-data");
        return;
    }
    if (shape === "entry") {
        entryShape(message.data, true);
        return;
    }
    if (shape === "input" || shape === "keys") {
        if (!object(message.data) || message.data.ok !== true) fail("input-reply");
        if (shape === "input") {
            keys(message.data, ["ok", "target", "cursor"], "input");
            var target = message.data.target;
            if (!object(target) || ["application", "terminal", "vgs", "lock", "polkit"].indexOf(target.kind) === -1
                    || !printable(target.id, 1, TEXT_MAX) || !object(message.data.cursor)
                    || !Number.isFinite(message.data.cursor.x) || !Number.isFinite(message.data.cursor.y)) fail("input-reply");
        } else {
            keys(message.data, ["ok", "keys", "translation", "effective"], "resolved-keys");
            if (!Array.isArray(message.data.keys) || message.data.keys.length < 1 || message.data.keys.length > ARGV_MAX
                    || !Array.isArray(message.data.effective) || !Array.isArray(message.data.translation)
                    || message.data.translation.length !== message.data.keys.length) fail("input-reply");
            for (var key of message.data.keys.concat(message.data.translation)) {
                keys(key, ["modifiers", "keycode", "keysym", "codepoint"], "resolved-key");
                if (!Array.isArray(key.modifiers) || !key.modifiers.every(text) || !Number.isSafeInteger(key.keycode)
                        || key.keycode < 8 || !text(key.keysym) || !Number.isSafeInteger(key.codepoint)
                        || key.codepoint < 0 || key.codepoint > 0x10ffff
                        || key.codepoint >= 0xd800 && key.codepoint <= 0xdfff) fail("input-reply");
            }
            if (!message.data.effective.every(text)) fail("input-reply");
        }
        return;
    }
    keys(message.data, ["entries", "complete"], "entries");
    if (!Array.isArray(message.data.entries) || message.data.entries.length > ENTRIES_MAX
            || typeof message.data.complete !== "boolean") fail("reply-data");
    var seen = {};
    for (var entry of message.data.entries) {
        entryShape(entry, false);
        if (Object.prototype.hasOwnProperty.call(seen, entry.id)) fail("entry-duplicate");
        Object.defineProperty(seen, entry.id, { value: true });
    }
}

// Tasks.js's task id rule, judged again on the wire before any record read.
function taskId(value) {
    return typeof value === "string" && /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/.test(value);
}

function approvalId(value) {
    return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value);
}

// The engine's failing setup steps (ChainedEngine select): at most one keyed
// cause per step, the home folder, then speech, then brain; none while the
// engine is ready. The home step's cause is the folder's own, `home=`, or
// its text's, `guidance=`.
var SETUP_STEPS = ["home", "speech", "brain"];
var SETUP_CAUSE_STEPS = { home: "home", guidance: "home", speech: "speech", brain: "brain" };
function setupCauses(value) {
    if (!Array.isArray(value)) return false;
    var last = -1;
    for (var i = 0; i < value.length; i++) {
        var match = typeof value[i] === "string" ? /^([a-z]+)=[a-z0-9-]{1,60}$/.exec(value[i]) : null;
        var step = match === null || !Object.prototype.hasOwnProperty.call(SETUP_CAUSE_STEPS, match[1]) ? -1
            : SETUP_STEPS.indexOf(SETUP_CAUSE_STEPS[match[1]]);
        if (step <= last) return false;
        last = step;
    }
    return true;
}

// Return the judged message, or throw a keyed protocol error.
function accept(line, direction) {
    if (typeof line !== "string") fail("line-not-string");
    bounded(line);
    var message;
    try { message = JSON.parse(line); } catch (error) { fail("json"); }
    if (!object(message)) fail("object");
    if (message.v !== 1) fail("version");
    if (typeof message.gen !== "number" || !Number.isSafeInteger(message.gen) || message.gen < 0)
        fail("generation");
    if (direction !== "shell" && direction !== "daemon") fail("direction");
    switch (message.type) {
    case "hello":
        if (direction !== "shell") fail("direction-hello");
        keys(message, ["v", "type", "gen", "settings", "directories", "revision", "locked", "keys"], "hello");
        keys(message.settings, ["mode", "sounds", "microphone", "speaker", "brain", "taskTerminal", "cloudVision", "privateWindows", "voiceProvider", "voiceAccount", "home"], "settings");
        if (!["local", "realtime"].includes(message.settings.voiceProvider) || typeof message.settings.voiceAccount !== "string"
                || !/^[^\x00-\x1f\x7f]{0,200}$/.test(message.settings.voiceAccount)) fail("voice-settings");
        if (typeof message.settings.sounds !== "boolean") fail("sounds");
        if (typeof message.settings.brain !== "string") fail("shape-settings");
        if (["hold", "toggle", "always"].indexOf(message.settings.mode) === -1) fail("mode");
        if (TASK_TERMINALS.indexOf(message.settings.taskTerminal) === -1) fail("task-terminal");
        if (CLOUD_VISION.indexOf(message.settings.cloudVision) === -1) fail("cloud-vision");
        if (typeof message.settings.privateWindows !== "string"
                || !/^[^\x00-\x1f\x7f]{0,1024}$/.test(message.settings.privateWindows)) fail("private-windows");
        // Home.js judges the folder the text names; the wire bounds the text.
        if (typeof message.settings.home !== "string"
                || !/^[^\x00-\x1f\x7f]{0,4096}$/.test(message.settings.home)) fail("home-setting");
        for (var setting of ["microphone", "speaker"])
            if (typeof message.settings[setting] !== "string"
                    || !/^[^\x00-\x1f\x7f]{0,200}$/.test(message.settings[setting])) fail("device-setting");
        keys(message.keys, ["talk", "mute", "stop", "confirm", "console"], "keys");
        for (var shortcut of Object.keys(message.keys)) {
            var key = message.keys[shortcut];
            // The core shortcut provider owns normalization and conflicts.
            if (key !== null && (typeof key !== "string" || key.length === 0))
                fail("key-" + shortcut);
        }
        keys(message.directories, ["state", "data", "runtime"], "directories");
        for (var name of Object.keys(message.directories))
            if (!directory(message.directories[name])) fail("directory-" + name);
        if (typeof message.locked !== "boolean") fail("lock");
        break;
    case "requirements-scan":
        if (direction !== "shell") fail("direction-requirements-scan");
        keys(message, ["v", "type", "gen", "revision", "scan"], "requirements-scan");
        if (!Number.isSafeInteger(message.scan) || message.scan < 0) fail("requirements-scan");
        break;
    case "intent":
        if (direction !== "shell") fail("direction-intent");
        var fields = ["v", "type", "gen", "revision", "intent"];
        if (message.intent === "confirm") {
            keys(message, fields.concat(["id", "digest", "source"]), "confirm");
            if (!approvalId(message.id)) fail("approval-id");
            if (typeof message.digest !== "string" || !/^[0-9a-f]{64}$/.test(message.digest)) fail("approval-digest");
            if (["key", "button"].indexOf(message.source) === -1) fail("approval-source");
        } else if (message.intent === "cancel") {
            keys(message, fields.concat(["id"]), "cancel");
            if (!approvalId(message.id)) fail("approval-id");
        } else if (message.intent === "task-respond") {
            keys(message, fields.concat(["task", "prompt", "answer"]), "task-respond");
            if (!taskId(message.task) || !approvalId(message.prompt)) fail("task-prompt-id");
            var response = message.answer;
            if (!object(response) || response.v !== 1) fail("task-response");
            if (response.kind === "reply") {
                keys(response, ["v", "kind", "text"], "task-response");
                if (typeof response.text !== "string" || response.text.trim() === "" || response.text.length > 4096
                        || /[\x00-\x09\x0b-\x1f\x7f]/.test(response.text)) fail("task-response");
            } else {
                keys(response, ["v", "kind"], "task-response");
                if (["allow", "deny"].indexOf(response.kind) === -1) fail("task-response");
            }
        } else if (message.intent === "task-stop") {
            keys(message, fields.concat(["task"]), "task-stop");
            if (!taskId(message.task)) fail("task-id");
        } else if (message.intent === "say") {
            keys(message, fields.concat(["text"]), "say");
            if (!printable(message.text, 1, TRANSCRIPT_CHARS) || message.text.trim() === "") fail("say-text");
        } else {
            keys(message, fields, "intent");
            if (["talk-down", "talk-up", "mute", "stop"].indexOf(message.intent) === -1) fail("intent");
        }
        break;
    case "shown":
        if (direction !== "shell") fail("direction-shown");
        keys(message, ["v", "type", "gen", "revision", "id"], "shown");
        if (!approvalId(message.id)) fail("approval-id");
        break;
    case "request":
        if (direction !== "daemon") fail("direction-request");
        keys(message, ["v", "type", "gen", "revision", "id", "kind", "args"], "request");
        if (!Number.isSafeInteger(message.id) || message.id < 1) fail("request-id");
        if (typeof message.kind !== "string" || !Object.prototype.hasOwnProperty.call(REQUESTS, message.kind))
            fail("request-kind");
        if (!requestArgs(message.kind, message.args)) fail("request-args");
        break;
    case "reply":
        if (direction !== "shell") fail("direction-reply");
        keys(message, ["v", "type", "gen", "revision", "id", "kind", "answer", "data"], "reply");
        if (!Number.isSafeInteger(message.id) || message.id < 1) fail("request-id");
        if (typeof message.kind !== "string" || !Object.prototype.hasOwnProperty.call(REQUESTS, message.kind))
            fail("request-kind");
        if (!printable(message.answer, 1, ANSWER_MAX)) fail("reply-answer");
        replyData(message);
        break;
    case "tui-state":
        if (direction !== "shell") fail("direction-tui-state");
        keys(message, ["v", "type", "gen", "revision", "name", "running"], "tui-state");
        if (message.name !== "task") fail("tui-name");
        if (typeof message.running !== "boolean") fail("tui-running");
        break;
    case "tasks":
        if (direction !== "daemon") fail("direction-tasks");
        keys(message, ["v", "type", "gen", "revision", "count"], "tasks");
        if (!Number.isSafeInteger(message.count) || message.count < 0) fail("task-count");
        break;
    case "input-ready":
        if (direction !== "daemon") fail("direction-input-ready");
        keys(message, ["v", "type", "gen", "revision", "commands"], "input-ready");
        if (!Array.isArray(message.commands) || !message.commands.every(command => ["wtype", "wlrctl", "ydotool"].indexOf(command) !== -1)) fail("input-commands");
        break;
    case "shell-status":
        if (direction !== "daemon") fail("direction-shell-status");
        keys(message, ["v", "type", "gen", "revision", "availability"], "shell-status");
        var availability = message.availability;
        if (!object(availability) || ["checking", "available", "unavailable"].indexOf(availability.kind) === -1)
            fail("shell-availability");
        keys(availability, availability.kind === "unavailable" ? ["kind", "reason"] : ["kind"], "shell-availability");
        if (availability.kind === "unavailable" && !printable(availability.reason, 1, FIELD_MAX))
            fail("shell-reason");
        break;
    case "task-prompts":
        if (direction !== "daemon") fail("direction-task-prompts");
        keys(message, ["v", "type", "gen", "revision", "prompts"], "task-prompts");
        if (!Array.isArray(message.prompts) || message.prompts.length > 32) fail("task-prompts");
        for (var prompt of message.prompts) {
            keys(prompt, ["v", "id", "task", "kind", "tool", "text", "at", "deadline"], "task-prompt");
            if (prompt.v !== 1 || !taskId(prompt.task) || !approvalId(prompt.id)
                    || ["permission", "question"].indexOf(prompt.kind) === -1
                    || (prompt.kind === "permission" ? typeof prompt.tool !== "string"
                        || !/^[A-Za-z0-9_.:-]{1,128}$/.test(prompt.tool) : prompt.tool !== null)
                    || typeof prompt.text !== "string" || prompt.text.length > 4096
                    || /[\x00-\x09\x0b-\x1f\x7f]/.test(prompt.text)
                    || !Number.isSafeInteger(prompt.at) || !Number.isSafeInteger(prompt.deadline)
                    || prompt.deadline <= prompt.at) fail("task-prompt");
        }
        break;
    case "task-response":
        if (direction !== "daemon") fail("direction-task-response");
        keys(message, ["v", "type", "gen", "revision", "task", "prompt", "answer"], "task-response");
        if (!taskId(message.task) || !approvalId(message.prompt)) fail("task-prompt-id");
        if (typeof message.answer !== "string" || !/^[a-z][a-z-]{0,39}$/.test(message.answer)) fail("task-response");
        break;
    case "task-answer":
        if (direction !== "daemon") fail("direction-task-answer");
        keys(message, ["v", "type", "gen", "revision", "task", "answer"], "task-answer");
        if (!taskId(message.task)) fail("answer-task-id");
        if (typeof message.answer !== "string" || !/^[a-z][a-z-]{0,39}$/.test(message.answer)) fail("task-answer");
        break;
    case "indicator":
        if (direction !== "shell") fail("direction-indicator");
        keys(message, ["v", "type", "gen", "revision", "shown"], "indicator");
        if (typeof message.shown !== "boolean") fail("indicator");
        break;
    case "status":
        if (direction !== "daemon") fail("direction-status");
        keys(message, ["v", "type", "gen", "revision", "daemon", "causes"], "status");
        if (message.daemon !== "ready" && message.daemon !== "locked") fail("daemon");
        if (!setupCauses(message.causes)) fail("causes");
        break;
    case "state":
        if (direction !== "daemon") fail("direction-state");
        keys(message, ["v", "type", "gen", "revision", "seq", "state", "phase"], "state");
        if (!Number.isSafeInteger(message.seq) || message.seq < 1) fail("sequence");
        if (!Session.validate(message.state)) fail("state");
        if (message.state.gen !== message.gen) fail("state-generation");
        if (message.phase !== Session.phaseOf(message.state)) fail("phase");
        break;
    case "devices":
        if (direction !== "daemon") fail("direction-devices");
        keys(message, ["v", "type", "gen", "revision", "microphones", "speakers"], "devices");
        for (var group of ["microphones", "speakers"]) {
            var values = message[group];
            if (!Array.isArray(values) || values.length > 32) fail("choices");
            var seen = {};
            for (var choice of values) {
                keys(choice, ["label", "value"], "choice");
                if (typeof choice.label !== "string" || !/^[^\x00-\x1f\x7f]{1,60}$/.test(choice.label)
                        || typeof choice.value !== "string" || !/^[^\x00-\x1f\x7f]{1,200}$/.test(choice.value))
                    fail("choice");
                if (Object.prototype.hasOwnProperty.call(seen, choice.value)) fail("choice-duplicate");
                Object.defineProperty(seen, choice.value, { value: true });
            }
        }
        break;
    case "level":
        if (direction !== "daemon") fail("direction-level");
        keys(message, ["v", "type", "gen", "revision", "level"], "level");
        keys(message.level, ["capture", "playback"], "levels");
        for (var channel of ["capture", "playback"])
            if (!Number.isFinite(message.level[channel]) || message.level[channel] < 0 || message.level[channel] > 1) fail("level");
        break;
    case "audio-fault":
        if (direction !== "daemon") fail("direction-audio-fault");
        keys(message, ["v", "type", "gen", "revision", "reason"], "audio-fault");
        if (typeof message.reason !== "string" || !/^[^\x00-\x1f\x7f]{1,180}$/.test(message.reason))
            fail("audio-fault");
        break;
    case "transcript":
        if (direction !== "daemon") fail("direction-transcript");
        keys(message, ["v", "type", "gen", "revision", "role", "text", "stage", "rev"], "transcript");
        if (message.role !== "user" && message.role !== "assistant") fail("transcript-role");
        if (message.stage !== "partial" && message.stage !== "final") fail("transcript-stage");
        if (typeof message.text !== "string" || message.text.length === 0 || message.text.length > TRANSCRIPT_CHARS
                || /[\x00-\x1f\x7f]/.test(message.text)) fail("transcript-text");
        if (!Number.isSafeInteger(message.rev) || message.rev < 1) fail("transcript-rev");
        break;
    default:
        fail("type");
    }
    if (typeof message.revision !== "string" || !/^[0-9a-f]{64}$/.test(message.revision)) fail("revision");
    return message;
}
