// The daemon owns one synchronous audit writer. The router and network door
// must use before() after their own authorization and before starting work.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const Tools = require("./Tools.js");
const Redact = require("./Redact.js");
const Private = require("./Private.js");
const Usage = require("./Usage.js");

const LINE_BYTES = 4 * 1024;
const STORE_BYTES = 64 * 1024 * 1024;
const DAY_MS = 24 * 60 * 60 * 1000;
const TAIL_BYTES = 64 * 1024;
const owners = new Set();
const effects = ["read", "reversible", "input", "persistent", "exec", "external", "destructive"];
// Why a duplex voice stream failed, as ChainedEngine closes its release
// rows: the provider refused the key, or another fault stopped the stream.
const STREAM_CAUSES = ["key-refused", "voice-stopped"];
// Vision, Screen and the router's rejudge produce these keys. Child failure
// detail can contain screen text or private paths, so only its command and
// fixed end category enter the audit.
const VISION_REASONS = ["outside-turn", "ocr-unavailable", "screenshot-limit", "hyprland-read",
    "monitor-shape", "monitor-absent", "window-absent", "window-shape", "window-hidden", "private-window",
    "window-off-screen", "region-off-screen", "image-empty", "image-size", "mask-failed", "image-bytes",
    "area-cancelled", "area-shape", "screen-changed", "cancelled", "cleanup", "executor-failed",
    "session-locked", "policy-profile", "turn-taint", "policy-changed", "stale-turn"];
const VISION_COMMAND = /^(grim|magick|slurp|tesseract)-(exit=[0-9]{1,3}|signal|cancelled|timeout|output-limit|spawn|input)$/;
// A conversation fault's row keeps the keyed cause's head word, without a
// key reader's `jarvis-keys: ` prefix, and its HTTP status, never the rest of
// its text, which can name a model or a kind; the category is
// ChainedEngine's restartOf word, and the action Session's. faultRecord
// lowercases the head word and maps `_` to `-`, as a harness stop reason
// carries its program's spelling (`copilot-stop-max_tokens`, `pi-stop-toolUse`).
const FAULT_CAUSE = /^[a-z-]+=[a-z0-9-]{1,60}$/;
const FAULT_CATEGORIES = ["connection", "reply-cut", "service", "app-stopped", "account", "model", "setup", "other"];
const FAULT_ACTIONS = ["restarted", "stopped"];

function visionReason(content) {
    if (content === "executor-failed") return content;
    let value;
    try { value = JSON.parse(content); } catch { fail("reason"); }
    if (value === null || typeof value !== "object") fail("reason");
    if (value.command === undefined) return value.reason;
    if (!["grim", "magick", "slurp", "tesseract"].includes(value.command)) fail("reason");
    const end = value.reason !== undefined ? value.reason
        : Number.isInteger(value.code) && value.code >= 0 && value.code <= 255 ? "exit=" + value.code
        : value.code === undefined && typeof value.signal === "string" ? "signal" : null;
    return value.command + "-" + end;
}

function fail(code) {
    const error = new Error("jarvis: audit=" + code);
    error.code = code;
    throw error;
}

function dateOf(name) {
    if (!/^\d{4}-\d{2}-\d{2}\.jsonl$/.test(name)) fail("entry-name");
    const date = name.slice(0, 10);
    const time = Date.parse(date + "T00:00:00.000Z");
    if (!Number.isFinite(time) || new Date(time).toISOString().slice(0, 10) !== date) fail("entry-date");
    return time;
}

function regular(stat) {
    if (!stat.isFile() || stat.nlink !== 1 || stat.uid !== process.getuid()) fail("file-type");
}

function encode(record) {
    const line = Buffer.from(JSON.stringify(record) + "\n");
    if (line.length > LINE_BYTES) fail("line-size");
    return line;
}

// A vision capture's facts: the layout box it read, the image's size and
// SHA-256, and how many private areas were painted. Numbers and a digest
// only, so no pixel or text of the image can enter the store.
function captureRecord(kind, tool, capture) {
    const whole = value => Number.isSafeInteger(value);
    if (kind !== "action" || !Object.hasOwn(Tools.TABLE, tool) || Tools.TABLE[tool].executor !== "vision"
            || capture === null || typeof capture !== "object"
            || Object.keys(capture).sort().join(",") !== "box,bytes,height,masks,scale,sha256,width"
            || !Array.isArray(capture.box) || capture.box.length !== 4 || !capture.box.every(whole)
            || capture.box[2] < 1 || capture.box[3] < 1 || typeof capture.scale !== "number"
            || !Number.isFinite(capture.scale) || capture.scale <= 0
            || ![capture.width, capture.height].every(value => whole(value) && value > 0)
            || ![capture.bytes, capture.masks].every(value => whole(value) && value >= 0)
            || typeof capture.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(capture.sha256)) fail("capture");
    return { box: capture.box.slice(), scale: capture.scale, width: capture.width, height: capture.height,
        bytes: capture.bytes, sha256: capture.sha256, masks: capture.masks };
}

function eventRecord(event, time) {
    if (event === null || typeof event !== "object") fail("event-shape");
    const { kind, gen, op, tool, effect, decision, confirmed, outcome } = event;
    if (!Number.isSafeInteger(gen) || gen < 0 || !Number.isSafeInteger(op) || op < 1) fail("identity");
    const decisions = kind === "action" ? ["allow", "confirm", "refuse"]
        : kind === "release" ? ["send", "ask", "withhold"] : null;
    if (decisions === null || !decisions.includes(decision)) fail("decision");
    if (effect !== null && !effects.includes(effect)) fail("effect");
    if (!["none", "physical", "voice"].includes(confirmed)) fail("confirmation");
    if (!["pending", "completed", "failed", "unknown", "cancelled"].includes(outcome)) fail("outcome");
    // Session emits these categories. Never retain an id, transcript or caller
    // text as the reason a release confirmation was refused.
    if (event.refusal !== undefined && (kind !== "release" || !["expired", "no-hold", "identity", "source",
        "early", "voice-physical", "voice-timing"].includes(event.refusal))) fail("refusal");
    // A stream's cause is one of these keys, never the fault's own text.
    if (event.cause !== undefined && (kind !== "release" || outcome !== "failed" || !STREAM_CAUSES.includes(event.cause))) fail("cause");
    const reason = event.failure === undefined ? event.reason : visionReason(event.failure);
    if ((event.failure !== undefined || reason !== undefined) && (kind !== "action" || outcome !== "failed"
            || !Object.hasOwn(Tools.TABLE, tool) || Tools.TABLE[tool].executor !== "vision"
            || typeof reason !== "string" || !(VISION_REASONS.includes(reason) || VISION_COMMAND.test(reason)))) fail("reason");
    // An action the local matcher proposed, not a brain (Tools.match).
    if (event.proposer !== undefined && (kind !== "action" || event.proposer !== "matcher")) fail("proposer");
    return { time, kind, gen, op,
        tool: kind === "release" ? "release" : Object.hasOwn(Tools.TABLE, tool) ? tool : "unknown",
        args: Redact.argumentsFor(kind, tool, event.args), effect, decision, confirmed, outcome,
        ...(event.refusal === undefined ? {} : { refusal: event.refusal }),
        ...(event.cause === undefined ? {} : { cause: event.cause }),
        ...(reason === undefined ? {} : { reason }),
        ...(event.proposer === undefined ? {} : { proposer: event.proposer }),
        ...(event.capture === undefined ? {} : { capture: captureRecord(kind, tool, event.capture) }) };
}

function faultRow(row) {
    const { time, gen, cause, status, category, action } = row;
    if (!Number.isSafeInteger(gen) || gen < 0) fail("identity");
    if (typeof cause !== "string" || !FAULT_CAUSE.test(cause)) fail("fault-cause");
    if (status !== undefined && (!Number.isSafeInteger(status) || status < 100 || status > 599)) fail("fault-status");
    if (!FAULT_CATEGORIES.includes(category)) fail("fault-category");
    if (!FAULT_ACTIONS.includes(action)) fail("fault-action");
    return { time, kind: "fault", gen, cause, ...(status === undefined ? {} : { status }), category, action };
}

// Session's fault-record effect: {gen, reason, category, action}, reason the
// engine's keyed cause, which this reduces to its head word and status.
function faultRecord(event, time) {
    if (event === null || typeof event !== "object" || typeof event.reason !== "string") fail("event-shape");
    const status = / status=([1-5][0-9]{2})(?: |$)/.exec(event.reason);
    return faultRow({ time, gen: event.gen, cause: event.reason.replace(/^jarvis-[a-z]+: /, "").split(" ", 1)[0].toLowerCase().replace(/_/g, "-"),
        ...(status === null ? {} : { status: Number(status[1]) }), category: event.category, action: event.action });
}

function storedEvent(record) {
    if (typeof record.time !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(record.time)) fail("seed-time");
    return record.kind === "fault" ? faultRow(record) : eventRecord(record, record.time);
}

// A row the Problems list shows: every fault, and every refused, withheld,
// failed or unknown action or release.
function problem(record) {
    return record.kind === "fault" || ["refuse", "withhold"].includes(record.decision) || ["failed", "unknown"].includes(record.outcome);
}

/**
 * The audit owner's read-only usage window, shared by admission and the
 * delegate's report command. Open held directories so neither a replaced day
 * nor a linked audit directory can turn a usage read into another file read.
 * A missing store is a new installation; unread or pruned data is not zero.
 */
function readUsage({ state, now = Date.now(), since = now - 7 * DAY_MS, until = now }) {
    if (![since, until].every(Number.isFinite) || since > until || until - since > 7 * DAY_MS) fail("usage-window");
    let parent, directory;
    try {
        parent = fs.openSync(state, fs.constants.O_RDONLY | fs.constants.O_DIRECTORY | fs.constants.O_NOFOLLOW);
        directory = fs.openSync("/proc/self/fd/" + parent + "/audit",
            fs.constants.O_RDONLY | fs.constants.O_DIRECTORY | fs.constants.O_NOFOLLOW);
    } catch (error) {
        if (parent !== undefined) fs.closeSync(parent);
        if (error.code !== "ENOENT") fail("usage-read");
        return { since: new Date(since).toISOString(), until: new Date(until).toISOString(), rows: [],
            ...Usage.summarize([]), complete: true };
    }
    const rows = [];
    let total = 0, complete = true;
    try {
        const base = "/proc/self/fd/" + directory;
        const entries = fs.opendirSync(base);
        try {
            let entry;
            while ((entry = entries.readSync()) !== null) {
                const day = dateOf(entry.name);
                if (day > until || day + DAY_MS <= since) continue;
                const fd = fs.openSync(path.join(base, entry.name), fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
                try {
                    const stat = fs.fstatSync(fd);
                    regular(stat);
                    total += stat.size;
                    if (total > STORE_BYTES) fail("store-size");
                    const buffer = Buffer.alloc(64 * 1024);
                    let tail = "", count;
                    while ((count = fs.readSync(fd, buffer, 0, buffer.length, null)) !== 0) {
                        // Keep bytes across reads for other rows' UTF-8 text.
                        tail += buffer.subarray(0, count).toString("latin1");
                        let end;
                        while ((end = tail.indexOf("\n")) !== -1) {
                            if (end + 1 > LINE_BYTES) fail("line-size");
                            const line = tail.slice(0, end);
                            tail = tail.slice(end + 1);
                            if (line === "") continue;
                            let row;
                            try { row = JSON.parse(Buffer.from(line, "latin1").toString("utf8")); } catch { fail("seed-json"); }
                            const time = Date.parse(row.time);
                            if (!Number.isFinite(time)) fail("seed-time");
                            if (row.kind === "prune" && row.args?.reason === "size"
                                    && Date.parse(row.args.date + "T00:00:00.000Z") + DAY_MS > since) complete = false;
                            if (time < since || time > until || row.kind !== "usage") continue;
                            rows.push(Usage.stored(row));
                        }
                        if (tail.length > LINE_BYTES) fail("line-size");
                    }
                    if (tail.length !== 0) fail("partial-line");
                } finally { fs.closeSync(fd); }
            }
        } finally { entries.closeSync(); }
        rows.sort((a, b) => a.time.localeCompare(b.time));
        return { since: new Date(since).toISOString(), until: new Date(until).toISOString(), rows,
            ...Usage.summarize(rows), complete };
    } catch { fail("usage-read"); }
    finally { fs.closeSync(directory); fs.closeSync(parent); }
}

/**
 * Acquire the daemon's only writer for an absolute Jarvis state directory.
 * auditDays is the manifest owner's setting; now returns wall-clock ms.
 * Creation converts an unversioned store once, then reads the newest daily
 * file's bounded tail. close() ends this owner's lifetime.
 * The VGS instance/child lease supplies process exclusivity, not this API.
 */
function create({ state, auditDays = 30, now = Date.now, changed = () => {} }) {
    if (typeof state !== "string" || !path.isAbsolute(state) || path.normalize(state) !== state
            || state === "/" || /[\x00-\x1f\x7f]/.test(state)) fail("state-path");
    if (!Number.isInteger(auditDays) || auditDays < 1 || auditDays > 365) fail("audit-days");
    if (typeof now !== "function") fail("clock");
    if (typeof changed !== "function") fail("changed");
    if (owners.has(state)) fail("writer-owned");
    owners.add(state);
    const directory = path.join(state, "audit");
    let lifetime = "open";
    let recent = [];
    let seedError = null;
    let migrations = 0;
    let causeCurrent = false;
    let usageIncomplete = false;

    function replace(file, lines, previous = null) {
        const candidate = path.join(state, ".audit-migrate-" + process.pid + "-" + (++migrations));
        let fd, owned = false;
        try {
            fd = fs.openSync(candidate, "wx", 0o600);
            owned = true;
            for (const line of lines) fs.writeFileSync(fd, line);
            fs.fsyncSync(fd);
            fs.closeSync(fd);
            fd = undefined;
            if (previous !== null) {
                const current = fs.lstatSync(file);
                regular(current);
                if (current.dev !== previous.dev || current.ino !== previous.ino || current.size !== previous.size) fail("migration-changed");
            }
            fs.renameSync(candidate, file);
            owned = false;
            for (const folder of new Set([state, path.dirname(file)])) {
                const parent = fs.openSync(folder, fs.constants.O_RDONLY | fs.constants.O_DIRECTORY | fs.constants.O_NOFOLLOW);
                try { fs.fsyncSync(parent); } finally { fs.closeSync(parent); }
            }
        } finally {
            if (fd !== undefined) fs.closeSync(fd);
            if (owned) fs.unlinkSync(candidate);
        }
    }

    // This store's first explicit format marker. Its absence is the old
    // daily-file format; current writers can never emit the retired causes.
    // Publish only after every daily file converted, so a crash retries the
    // idempotent conversion rather than leaving an unread old day behind.
    function converted() {
        let fd;
        try {
            fd = fs.openSync(path.join(state, "audit-cause-version.json"), fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
            regular(fs.fstatSync(fd));
            const buffer = Buffer.alloc(129);
            const count = fs.readSync(fd, buffer, 0, buffer.length, 0);
            if (count > 128) fail("format-size");
            let version;
            try { version = JSON.parse(buffer.subarray(0, count).toString("utf8")); } catch { fail("format-json"); }
            if (version === null || typeof version !== "object" || Array.isArray(version)
                    || Object.keys(version).join(",") !== "version" || version.version !== 1) fail("format-version");
            return true;
        } catch (error) {
            if (error.code === "ENOENT") return false;
            throw error;
        } finally { if (fd !== undefined) fs.closeSync(fd); }
    }

    // D107: the old writer recorded these two silence endings as failures.
    // Keep that historical outcome, removing only its retired cause. This
    // is a read-boundary conversion, never a second current-format reader.
    function migrate(file) {
        const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
        try {
            const stat = fs.fstatSync(fd);
            regular(stat);
            if (stat.size > STORE_BYTES) fail("store-size");
            const bytes = Buffer.alloc(stat.size);
            let offset = 0;
            while (offset < bytes.length) {
                const count = fs.readSync(fd, bytes, offset, bytes.length - offset, offset);
                if (count === 0) fail("migration-read");
                offset += count;
            }
            const text = bytes.toString("utf8");
            if (!text.includes("unheard") && !text.includes("input-silent")) return;
            if (bytes.length !== 0 && bytes[bytes.length - 1] !== 10) fail("partial-line");
            let changed = false;
            const lines = text.split("\n").slice(0, -1).map(line => {
                if (line === "") return "\n";
                let row;
                try { row = JSON.parse(line); } catch { fail("seed-json"); }
                if (row.kind !== "release" || row.outcome !== "failed" || !["unheard", "input-silent"].includes(row.cause)) return line + "\n";
                const { cause, ...current } = row;
                changed = true;
                return encode(storedEvent(current)).toString("utf8");
            });
            if (!changed) return;
            replace(file, lines, stat);
        } finally { fs.closeSync(fd); }
    }

    function retain(record) {
        if (!problem(record)) return false;
        recent = recent.concat([record.kind === "fault"
            ? { time: record.time, kind: "fault", cause: record.cause, status: record.status ?? null, category: record.category, action: record.action }
            : { time: record.time, tool: record.tool, effect: record.effect,
                decision: record.decision, outcome: record.outcome, refusal: record.refusal ?? null, cause: record.cause ?? null }]).slice(-20);
        return true;
    }

    function failures() {
        if (seedError !== null) throw seedError;
        return recent.map(row => ({ ...row }));
    }

    function clock() {
        const ms = now();
        if (!Number.isFinite(ms) || ms < 0) fail("clock-value");
        const time = new Date(ms).toISOString();
        if (time.length !== 24) fail("clock-value");
        return { time, today: Date.parse(time.slice(0, 10) + "T00:00:00.000Z"),
            file: path.join(directory, time.slice(0, 10) + ".jsonl") };
    }

    function scan(today, convert = false) {
        let total = 0, oldest = null, expired = null, newest = null;
        const entries = fs.opendirSync(directory);
        try {
            let entry;
            while ((entry = entries.readSync()) !== null) {
                const date = dateOf(entry.name);
                const file = path.join(directory, entry.name);
                const stat = fs.lstatSync(file);
                regular(stat);
                if (convert) migrate(file);
                total += stat.size;
                if (!Number.isSafeInteger(total)) fail("store-size");
                const row = { file, date, bytes: stat.size };
                if (oldest === null || date < oldest.date) oldest = row;
                if (newest === null || date > newest.date) newest = row;
                if (date <= today - auditDays * DAY_MS && (expired === null || date < expired.date)) expired = row;
            }
        } finally { entries.closeSync(); }
        return { total, oldest, expired, newest };
    }

    function seed() {
        try { fs.lstatSync(state); }
        catch (error) { if (error.code === "ENOENT") return; throw error; }
        Private.directory(state);
        const moved = converted();
        try { fs.lstatSync(directory); }
        catch (error) { if (error.code === "ENOENT") { causeCurrent = moved; return; } throw error; }
        Private.directory(directory);
        const newest = scan(clock().today, !moved).newest;
        if (!moved) replace(path.join(state, "audit-cause-version.json"), ['{"version":1}\n']);
        causeCurrent = true;
        if (newest === null) return;
        const fd = fs.openSync(newest.file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
        try {
            const stat = fs.fstatSync(fd);
            regular(stat);
            const start = Math.max(0, stat.size - TAIL_BYTES);
            const buffer = Buffer.alloc(Math.min(stat.size, TAIL_BYTES));
            const count = fs.readSync(fd, buffer, 0, buffer.length, start);
            let tail = buffer.subarray(0, count);
            if (start > 0) {
                const first = tail.indexOf(10);
                tail = first < 0 ? Buffer.alloc(0) : tail.subarray(first + 1);
            }
            if (tail.length > 0 && tail[tail.length - 1] !== 10) fail("partial-line");
            for (const line of tail.toString("utf8").split("\n").filter(Boolean)) {
                let record;
                try { record = JSON.parse(line); } catch { fail("seed-json"); }
                if (problem(record)) retain(storedEvent(record));
            }
        } finally { fs.closeSync(fd); }
    }
    // Unusable stores still permit cleanup() privacy teardown. The daemon
    // reads failures() at startup and receives the actual read failure.
    try { seed(); } catch (error) {
        seedError = new Error("jarvis: audit=read cause=" + (error.code || "seed-invalid"));
        seedError.code = error.code || "seed-invalid";
    }

    function append(file, line) {
        const fd = fs.openSync(file, fs.constants.O_RDWR | fs.constants.O_CREAT | fs.constants.O_APPEND
            | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK, 0o600);
        try {
            const stat = fs.fstatSync(fd);
            regular(stat);
            fs.fchmodSync(fd, 0o600);
            if (stat.size > 0) {
                const tail = Buffer.alloc(1);
                if (fs.readSync(fd, tail, 0, 1, stat.size - 1) !== 1 || tail[0] !== 10) fail("partial-line");
            }
            const written = fs.writeSync(fd, line, 0, line.length);
            if (written !== line.length) {
                fs.ftruncateSync(fd, stat.size);
                fs.fsyncSync(fd);
                fail("short-write");
            }
            fs.fsyncSync(fd);
        } finally { fs.closeSync(fd); }
    }

    function persist(record, stamp) {
        if (seedError !== null) throw seedError;
        Private.directory(state);
        Private.directory(directory);
        if (!causeCurrent && seedError === null) {
            replace(path.join(state, "audit-cause-version.json"), ['{"version":1}\n']);
            causeCurrent = true;
        }
        const line = encode(record);
        let inventory = scan(stamp.today);
        // Keep only the next oldest candidate, not an unbounded filename list.
        // Reserve one maximum-sized removal record as well as the new event.
        while (inventory.expired !== null || inventory.total + line.length + LINE_BYTES > STORE_BYTES) {
            const victim = inventory.expired || inventory.oldest;
            if (victim === null) fail("store-full");
            fs.unlinkSync(victim.file);
            append(stamp.file, encode({ time: stamp.time, kind: "prune", tool: "audit.prune",
                args: { date: new Date(victim.date).toISOString().slice(0, 10), bytes: victim.bytes,
                    reason: inventory.expired !== null ? "age" : "size" },
                effect: "persistent", decision: "remove", confirmed: "none", outcome: "completed" }));
            inventory = scan(stamp.today);
        }
        append(stamp.file, line);
        // Persist directory entries too, including a new daily file/removal.
        for (const folder of [directory, state]) {
            const fd = fs.openSync(folder, fs.constants.O_RDONLY | fs.constants.O_DIRECTORY | fs.constants.O_NOFOLLOW);
            try { fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
        }
    }

    function attempt(build) {
        try {
            if (lifetime !== "open") fail("writer-closed");
            const stamp = clock();
            persist(build(stamp.time), stamp);
            // The row's time names it: a forward cites the row by it.
            return { kind: "recorded", time: stamp.time };
        } catch (error) {
            // Filesystem messages can contain private paths. Only keyed causes
            // leave this boundary; no caller argument or error body is logged.
            return { kind: "refuse", reason: "audit-write", cause: error.code || "event-invalid" };
        }
    }

    function written(build) {
        let value;
        const result = attempt(time => { value = build(time); return value; });
        if (result.kind === "recorded" && retain(value)) changed(failures());
        return result;
    }
    function record(event) { return written(time => eventRecord(event, time)); }

    return Object.freeze({
        /** Record a decision or later outcome, including refused/held calls. */
        record,
        /** Record one conversation fault: what VGS did about which cause. */
        fault: event => written(time => faultRecord(event, time)),
        /** Usage has no content, only the one price owner's numeric projection. */
        usage(event) {
            const result = written(time => ({ time, kind: "usage", ...Usage.record(event) }));
            // A later successful append cannot reconstruct this lost usage.
            // Keep search held for this writer; voice teardown stays independent.
            if (result.kind !== "recorded") usageIncomplete = true;
            return result;
        },
        usageWindow() {
            const window = readUsage({ state, now: now() });
            return usageIncomplete ? { ...window, complete: false } : window;
        },
        failures,
        /**
         * Persist a pending authorized action/release before invoking start.
         * This is the audit gate only, not a policy or approval judge.
         * start may return a promise; executor results never enter this store.
         * start receives the recorded row's result, {kind:"recorded", time}.
         */
        before(event, start) {
            if (!event || event.outcome !== "pending" || typeof start !== "function") fail("start-shape");
            const audit = record(event);
            if (audit.kind === "refuse") return audit;
            return { kind: "started", audit, value: start(audit) };
        },
        /** Privacy shutdown cannot depend on a writable audit store. */
        cleanup(kind, start) {
            if (!["stop", "teardown"].includes(kind) || typeof start !== "function") fail("cleanup-shape");
            const audit = attempt(time => ({ time, kind: "cleanup", tool: kind, args: {},
                effect: "reversible", decision: "allow", confirmed: "none", outcome: "pending" }));
            return { kind: "started", audit, value: start() };
        },
        close() {
            if (lifetime === "open") { lifetime = "closed"; owners.delete(state); }
        }
    });
}

module.exports = { create, readUsage };
