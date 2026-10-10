// The Jarvis home folder: the one folder the user picks, whose AGENTS.md,
// skills, memory and state every brain uses the same way. This owner creates
// the folder's missing entries, keeps skills/base a copy of the base package
// VGS ships, and reads its text; it never follows a link at the home or below
// it, since a link there could hand another file to every brain. Home text
// gives knowledge, never permission: the gate stays the only source of that.
// It also appends a request to the master session's mailbox in the folder,
// the one write a brain's call makes there outside state/.
// Contract: docs/decisions/D105-jarvis-home-folder.md.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawnSync } = require("node:child_process");
const Core = require("./Core.js");
const Tools = require("./Tools.js");
const { O_RDONLY, O_WRONLY, O_RDWR, O_APPEND, O_CREAT, O_EXCL, O_DIRECTORY, O_NOFOLLOW, O_NONBLOCK } = fs.constants;

// The two harness files serve the user's own Claude Code or Codex session
// started in the home; a brain Jarvis starts never runs there. Claude Code's
// key is autoMemoryEnabled (code.claude.com/docs/en/memory) and Codex's are
// features.memories and the memories table
// (developers.openai.com/codex/config-reference).
const LAYOUT = Object.freeze([
    ["AGENTS.md", ""], ["CLAUDE.md", "@AGENTS.md\n"],
    ["skills", null], ["skills/base", null], ["skills/own", null],
    ["memory", null], ["memory/MEMORY.md", ""], ["memory/inbox", null],
    ["state", null],
    [".claude", null], [".claude/settings.json", "{\"autoMemoryEnabled\": false}\n"],
    [".codex", null], [".codex/config.toml", "[features]\nmemories = false\n\n[memories]\ngenerate_memories = false\nuse_memories = false\n"]
]);
// skills/base holds this one folder, a copy of the shipped base package
// (Core.basePackage); the persona is its persona.md.
const PACKAGE = "jarvis";
// The one entry of the home the gate leaves a model: Jarvis writes it
// through files.write. Every other path in the folder, an entry this layout
// does not name among them, is the user's and VGS's alone.
const OPEN = "state";
const SETS = Object.freeze(["base", "own"]);
// Entries read from one skill set before the listing answers incomplete.
const SET_ENTRIES = 256;
// The head of a skill file its index line is read from, and that line's
// bound in characters.
const HEAD_BYTES = 4096;
const LINE_CHARS = 160;
// Linux PATH_MAX, the anchored walk's own bound.
const PATH_BYTES = 4096;
// The master session's mailbox, as lane-mail lays one out below its root
// (.agents/skills/orch/scripts/lane-mail): the session that runs the owner's
// fleet reads this file with `lane-mail inbox --item overseer`.
const MAILBOX = "tmp/lane-mail/overseer";
const MAILBOX_FILE = "to-lane.jsonl";
// Seconds the append waits for the mailbox lock. lane-mail holds it for one
// read, append or rewrite of the file, so the wait only bounds a holder that
// hung; the daemon answers nothing else while it waits.
const LOCK_SECONDS = 1;
// A YAML block scalar's header: > or |, then an optional chomping mark and
// indent digit in either order. Its text is on the lines below it.
const BLOCK_SCALAR = /^[>|][-+1-9]{0,2}$/;

function fail(code) { throw new Error("jarvis: home=" + code); }

/**
 * The home folder a setting names, or null for the empty setting. `~` is
 * the user's home directory. The folder lies strictly inside that directory,
 * where the file tools reach state/. Throws jarvis: home=path.
 */
function resolve(setting, userHome) {
    if (typeof setting !== "string" || typeof userHome !== "string" || !path.isAbsolute(userHome)) fail("path");
    if (setting === "") return null;
    const base = path.resolve(userHome);
    const named = setting === "~" ? base : setting.startsWith("~/") ? path.join(base, setting.slice(2)) : setting;
    if (!path.isAbsolute(named) || /[\x00-\x1f\x7f]/.test(named)) fail("path");
    const file = path.resolve(named);
    if (!file.startsWith(base === "/" ? "/" : base + "/") || Buffer.byteLength(file) > PATH_BYTES) fail("path");
    return file;
}

/**
 * HOME as the gate guards it (Denied.js jarvisHome): every path in root is
 * refused but the entry named open and what lies below it.
 */
function guard(home) { return { root: home, open: OPEN }; }

// Hold the home folder itself open. The folders above it are the user's own
// path and resolve as the system gives them; the home is never a link.
function hold(home, create) {
    let file;
    try {
        if (create) fs.mkdirSync(path.dirname(home), { recursive: true });
        file = path.join(fs.realpathSync.native(path.dirname(home)), path.basename(home));
        if (create) {
            try { fs.mkdirSync(file); }
            catch (error) { if (error.code !== "EEXIST") throw error; }
        }
    } catch (error) { fail(create ? "unwritable" : "unreadable"); }
    const opened = Core.anchored().directory(file);
    switch (opened.kind) {
    case "directory": return opened.fd;
    case "link": return fail("link");
    case "not-directory": return fail("kind");
    default: return fail(create ? "unwritable" : "unreadable");
    }
}

// The kind of an entry in a held folder, read without following it.
function kindOf(parent, name) {
    let stat;
    try { stat = fs.lstatSync(Core.anchored().child(parent, name)); }
    catch (error) {
        if (error.code === "ENOENT") return "absent";
        throw error;
    }
    return stat.isSymbolicLink() ? "link" : stat.isDirectory() ? "directory" : stat.isFile() ? "file" : "other";
}

// A file appears under its name whole or not at all, and link(2) never
// replaces an entry made meanwhile.
function createFile(parent, name, content) {
    const child = Core.anchored().child;
    const scratch = child(parent, "." + name + "." + process.pid + ".new");
    const fd = fs.openSync(scratch, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644);
    try {
        try { fs.writeFileSync(fd, content); } finally { fs.closeSync(fd); }
        fs.linkSync(scratch, child(parent, name));
    } finally { fs.unlinkSync(scratch); }
}

// Every entry below the held folder FD as [path, bytes], a folder's path
// ending in "/" with no bytes, in no order. A link throws home=link and is
// never followed; any entry but a folder or a regular file throws home=kind.
// A file reads whole for a null LIMIT, else as at most LIMIT + 1 bytes.
function entries(fd, limit, prefix = "", out = []) {
    const child = Core.anchored().child;
    const directory = fs.opendirSync("/proc/self/fd/" + fd);
    try {
        for (let entry = directory.readSync(); entry !== null; entry = directory.readSync()) {
            const kind = kindOf(fd, entry.name);
            if (kind !== "directory" && kind !== "file") fail(kind === "link" ? "link" : "kind");
            const directoryKind = kind === "directory";
            const held = fs.openSync(child(fd, entry.name), (directoryKind ? O_RDONLY | O_DIRECTORY : O_RDONLY | O_NONBLOCK) | O_NOFOLLOW);
            try {
                if (directoryKind) {
                    out.push([prefix + entry.name + "/", Buffer.alloc(0)]);
                    entries(held, limit, prefix + entry.name + "/", out);
                } else out.push([prefix + entry.name, limit === null ? fs.readFileSync(held) : bytes(held, limit)]);
            } finally { fs.closeSync(held); }
        }
    } finally { directory.closeSync(); }
    return out;
}

// Make skills/base, held as FD, hold exactly the shipped package: unchanged
// when it already does, else a fresh copy swapped in for PACKAGE by one
// rename and every other entry removed. A shipped package that cannot be
// read throws home=package.
function base(fd) {
    let shipped;
    try {
        const root = fs.openSync(Core.basePackage(), O_RDONLY | O_DIRECTORY);
        try { shipped = entries(root, null, PACKAGE + "/", [[PACKAGE + "/", Buffer.alloc(0)]]); }
        finally { fs.closeSync(root); }
    } catch { fail("package"); }
    const order = list => list.sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0);
    order(shipped);
    // A home file past the largest shipped one differs whatever it holds.
    const found = order(entries(fd, Math.max(...shipped.map(([, content]) => content.length))));
    if (found.length === shipped.length && found.every(([name, content], index) =>
        name === shipped[index][0] && content.equals(shipped[index][1]))) return;
    const child = Core.anchored().child;
    const fresh = "." + PACKAGE + "." + process.pid + ".new";
    const old = "." + PACKAGE + "." + process.pid + ".old";
    for (const name of [fresh, old]) fs.rmSync(child(fd, name), { recursive: true, force: true });
    for (const [name, content] of shipped) {
        const at = child(fd, fresh + name.slice(PACKAGE.length));
        if (name.endsWith("/")) fs.mkdirSync(at);
        else {
            const file = fs.openSync(at, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644);
            try { fs.writeFileSync(file, content); } finally { fs.closeSync(file); }
        }
    }
    if (kindOf(fd, PACKAGE) !== "absent") fs.renameSync(child(fd, PACKAGE), child(fd, old));
    fs.renameSync(child(fd, fresh), child(fd, PACKAGE));
    for (const name of fs.readdirSync("/proc/self/fd/" + fd))
        if (name !== PACKAGE) fs.rmSync(child(fd, name), { recursive: true, force: true });
}

/**
 * Create the entries of LAYOUT the home lacks, and the home itself, and make
 * skills/base hold exactly the shipped base package. Any other entry already
 * there is kept byte for byte. A link at the home, at any layout path or
 * inside skills/base throws jarvis: home=link and is never followed; an
 * entry of the other kind throws home=kind, a shipped package that cannot
 * be read home=package, and a failed write home=unwritable.
 */
function layout(home) {
    const held = new Map([[".", hold(home, true)]]);
    try {
        for (const [entry, content] of LAYOUT) {
            const parent = held.get(path.dirname(entry));
            const name = path.basename(entry);
            const kind = kindOf(parent, name);
            if (kind === "link") fail("link");
            if (content === null) {
                if (kind === "absent") fs.mkdirSync(Core.anchored().child(parent, name));
                else if (kind !== "directory") fail("kind");
                held.set(entry, fs.openSync(Core.anchored().child(parent, name), O_RDONLY | O_DIRECTORY | O_NOFOLLOW));
            } else if (kind === "absent") createFile(parent, name, content);
            else if (kind !== "file") fail("kind");
        }
        base(held.get("skills/base"));
    } catch (error) {
        if (/^jarvis: home=/.test(error.message)) throw error;
        fail("unwritable");
    } finally { for (const fd of held.values()) fs.closeSync(fd); }
}

// Open ENTRY, a relative path of plain names, below the held home, each
// component without following a link, and hand its descriptor to act.
function within(home, entry, flags, act) {
    const child = Core.anchored().child;
    let fd = hold(home, false);
    try {
        const parts = entry.split("/");
        for (const [index, part] of parts.entries()) {
            const last = index === parts.length - 1;
            let next;
            try {
                // The kind names the refusal; O_NOFOLLOW is what holds it.
                const kind = kindOf(fd, part);
                if (kind === "absent" || kind === "link") fail(kind);
                if (kind !== "directory" && (!last || flags & O_DIRECTORY)) fail("kind");
                next = fs.openSync(child(fd, part), (last ? flags : O_RDONLY | O_DIRECTORY) | O_NOFOLLOW);
            } catch (error) {
                if (/^jarvis: home=/.test(error.message)) throw error;
                return fail("unreadable");
            }
            fs.closeSync(fd);
            fd = next;
        }
        return act(fd);
    } finally { fs.closeSync(fd); }
}

// At most limit + 1 bytes of a regular file, or all of it where limit is null.
function bytes(fd, limit) {
    if (!fs.fstatSync(fd).isFile()) fail("kind");
    if (limit === null) return fs.readFileSync(fd);
    const buffer = Buffer.alloc(limit + 1);
    let size = 0;
    while (size < buffer.length) {
        const count = fs.readSync(fd, buffer, size, buffer.length - size, null);
        if (count === 0) break;
        size += count;
    }
    return buffer.subarray(0, size);
}

/**
 * Read ENTRY of the home as UTF-8 text of at most LIMIT bytes, or of any
 * size where LIMIT is null: {kind: "text", text}, or {kind: "too-large"};
 * never a cut text. Throws jarvis: home=absent, link, kind, unreadable or
 * text.
 */
function read(home, entry, limit) {
    // O_NONBLOCK: a FIFO in the file's place answers at once, as not a file.
    return within(home, entry, O_RDONLY | O_NONBLOCK, fd => {
        const content = bytes(fd, limit);
        if (limit !== null && content.length > limit) return { kind: "too-large" };
        try { return { kind: "text", text: new TextDecoder("utf-8", { fatal: true }).decode(content) }; }
        catch { return fail("text"); }
    });
}

// A skill's index line: the one-line `description` of a leading front
// matter block, as a harness skill file carries, else the first line of
// text, its heading marks dropped. A block scalar description is not read.
function indexLine(text) {
    let lines = text.split("\n");
    if (lines[0].trim() === "---") {
        const end = lines.findIndex((line, index) => index > 0 && line.trim() === "---");
        const front = lines.slice(1, end === -1 ? lines.length : end);
        const described = front.map(line => /^description:\s*(.*)$/.exec(line)).find(match => match !== null);
        const value = described ? described[1].trim().replace(/^(["'])(.*)\1$/, "$2") : "";
        if (value !== "" && !BLOCK_SCALAR.test(value)) return value.slice(0, LINE_CHARS);
        lines = end === -1 ? [] : lines.slice(end + 1);
    }
    const first = lines.find(line => line.trim() !== "") ?? "";
    return first.trim().replace(/^#+\s*/, "").replace(/[\x00-\x1f\x7f]/g, " ").slice(0, LINE_CHARS);
}

// The entries of FOLDER, a path of plain names in the home, at most
// SET_ENTRIES of them: {entries, complete}.
function listing(home, folder) {
    return within(home, folder, O_RDONLY | O_DIRECTORY, fd => {
        // The descriptor's own /proc path: the folder held, not a name looked up again.
        const directory = fs.opendirSync("/proc/self/fd/" + fd);
        try {
            const entries = [];
            for (let entry = directory.readSync(); entry !== null; entry = directory.readSync()) {
                if (entries.length === SET_ENTRIES) return { entries, complete: false };
                entries.push(entry);
            }
            return { entries, complete: true };
        } finally { directory.closeSync(); }
    });
}

// The index entry of FILE under TOPIC, or, where OPTIONAL, null for a file
// that is absent, a link or no regular file.
function indexed(home, topic, file, optional) {
    let head;
    try { head = within(home, file, O_RDONLY | O_NONBLOCK, fd => bytes(fd, HEAD_BYTES - 1)); }
    catch (error) {
        if (optional && /^jarvis: home=(?:absent|link|kind)$/.test(error.message)) return null;
        throw error;
    }
    return { topic, file, line: indexLine(new TextDecoder("utf-8").decode(head)) };
}

/**
 * The home's skills in topic order: {skills: [{topic, file, line}], complete}.
 * A skill is `<name>.md` or `<name>/SKILL.md` directly in skills/base or
 * skills/own, a regular file under a name Tools.homeTopic admits; a folder
 * skill's `references/<reference>.md` is a skill of its own under
 * "<set>/<name>/<reference>". Any other entry, a link among them, is no
 * skill. topic is "<set>/<name>", file its path in the home and line its
 * index line. complete is false once a folder holds more than SET_ENTRIES
 * entries.
 */
function skills(home) {
    const found = [];
    let complete = true;
    // Each regular `<name>.md` file of FOLDER, under PREFIX + name.
    function flat(folder, prefix, listed) {
        complete &&= listed.complete;
        for (const entry of listed.entries) {
            const topic = prefix + entry.name.slice(0, -3);
            if (entry.isFile() && entry.name.endsWith(".md") && Tools.homeTopic(topic) !== null)
                found.push(indexed(home, topic, folder + "/" + entry.name, false));
        }
    }
    for (const set of SETS) {
        const folder = "skills/" + set;
        const listed = listing(home, folder);
        flat(folder, set + "/", listed);
        for (const entry of listed.entries) {
            const topic = set + "/" + entry.name;
            if (Tools.homeTopic(topic) === null) continue;
            // An entry that is no folder, a folder without SKILL.md, or one with a
            // link in its place, is no skill.
            const skill = indexed(home, topic, folder + "/" + entry.name + "/SKILL.md", true);
            if (skill === null) continue;
            found.push(skill);
            const references = folder + "/" + entry.name + "/references";
            let inside;
            try { inside = listing(home, references); }
            catch (error) {
                if (/^jarvis: home=(?:absent|link|kind)$/.test(error.message)) continue;
                throw error;
            }
            flat(references, topic + "/", inside);
        }
    }
    found.sort((left, right) => left.topic < right.topic ? -1 : left.topic > right.topic ? 1 : 0);
    return { skills: found, complete };
}

/**
 * The whole text of the skill TOPIC names. A skill is read on demand, so no
 * size bound applies; the bounds are on what every brain gets at its start.
 * Throws as read() does, and jarvis: home=absent for a topic the home does
 * not hold.
 */
function skill(home, topic) {
    const named = Tools.homeTopic(topic);
    if (named === null) fail("absent");
    const base = "skills/" + named.set + "/" + named.name;
    const whole = file => read(home, file, null).text;
    if (named.reference !== null) return whole(base + "/references/" + named.reference + ".md");
    try { return whole(base + ".md"); }
    catch (error) {
        if (error.message !== "jarvis: home=absent") throw error;
        return whole(base + "/SKILL.md");
    }
}

/**
 * The whole text of the memory note PATH names below memory/. A note is read
 * on demand, as a skill is, so no size bound applies. Throws as read() does,
 * and jarvis: home=absent for a path Tools.memoryNote refuses, a note under
 * memory/inbox/ among them.
 */
function note(home, entry) {
    if (!Tools.memoryNote(entry)) fail("absent");
    return read(home, "memory/" + entry, null).text;
}

/** Whether the home holds the master session's mailbox folder, no link on the way. */
function mailbox(home) {
    try { return within(home, MAILBOX, O_RDONLY | O_DIRECTORY, () => true); }
    catch (error) {
        if (/^jarvis: home=/.test(error.message)) return false;
        throw error;
    }
}

// Take lane-mail's lock on the mailbox file held as FD: flock on the file
// itself, which each of its readers and writers takes
// (lane-mail's lib/mailbox-append.sh). flock(1) locks the descriptor it
// inherits as its descriptor 3, and the lock belongs to the open file
// description, so this process holds it until FD closes (flock(2)).
// Child.run hands a child pipes alone, never a descriptor, so this start is
// its own; flock(1) ends itself once LOCK_SECONDS pass.
function lock(fd) {
    const taken = spawnSync("flock", ["-w", String(LOCK_SECONDS), "-E", "75", "3"],
        { stdio: ["ignore", "ignore", "ignore", fd], env: { PATH: process.env.PATH ?? "" } });
    if (taken.status === 75) fail("busy");
    if (taken.status !== 0) fail("lock");
}

/**
 * Hand TEXT to the master session: append it to the mailbox as one lane-mail
 * directive from the owner, stamped NOW, an unpaired surrogate in it
 * replaced by U+FFFD. Jarvis writes the row itself, in
 * the record form lane-mail documents, because lane-mail's own `send` cannot
 * serve: VGS ships no copy of it, and the copy in the home is home text,
 * which Jarvis never runs (D105). The append holds lane-mail's lock, closes
 * a line a killed writer left without its newline, as lane-mail's append
 * does, and ends the row on one. The mailbox folder is the master's: Jarvis
 * makes none, and makes the file where it is absent, as lane-mail's append
 * does. Returns {kind: "handed", id} once the row reads back as the file's
 * last line, and {kind: "unread", id} for a write that failed part way or
 * reads back otherwise. Throws jarvis: home=absent, link or kind for the
 * mailbox, home=busy while another holder keeps the lock past LOCK_SECONDS,
 * home=lock where flock cannot run, and home=unwritable; none of them wrote
 * a row.
 */
function hand(home, text, now = Date.now()) {
    const seconds = Math.floor(now / 1000);
    // lane-mail's id form, <epoch>-<pid>-<random>, and its `at`, UTC to the second.
    const id = seconds + "-" + process.pid + "-" + crypto.randomInt(32768);
    // JSON.stringify writes an unpaired surrogate as a \ud escape, which jq,
    // lane-mail's parser, refuses: the reader would count the row and never
    // hand it over.
    const row = Buffer.from(JSON.stringify({ id, kind: "directive",
        at: new Date(seconds * 1000).toISOString().replace(".000Z", "Z"), from: "owner", text: text.toWellFormed() }) + "\n");
    return within(home, MAILBOX, O_RDONLY | O_DIRECTORY, folder => {
        const kind = kindOf(folder, MAILBOX_FILE);
        if (kind === "link") fail(kind);
        if (kind !== "file" && kind !== "absent") fail("kind");
        let fd;
        try { fd = fs.openSync(Core.anchored().child(folder, MAILBOX_FILE), O_RDWR | O_APPEND | O_CREAT | O_NOFOLLOW, 0o644); }
        catch { return fail("unwritable"); }
        try {
            lock(fd);
            try {
                const size = fs.fstatSync(fd).size;
                const last = Buffer.alloc(1);
                const open = size > 0 && fs.readSync(fd, last, 0, 1, size - 1) === 1 && last[0] !== 0x0a;
                // O_APPEND puts every byte at the file's end, where the lock lets no other in.
                fs.writeFileSync(fd, open ? Buffer.concat([Buffer.from("\n"), row]) : row);
                const seen = Buffer.alloc(row.length);
                fs.readSync(fd, seen, 0, row.length, fs.fstatSync(fd).size - row.length);
                return seen.equals(row) ? { kind: "handed", id } : { kind: "unread", id };
            } catch { return { kind: "unread", id }; }
        } finally { fs.closeSync(fd); }
    });
}

module.exports = { PACKAGE, resolve, layout, guard, read, skills, skill, note, mailbox, hand };
