// The Jarvis home folder: the one folder the user picks, whose AGENTS.md,
// skills, memory and state every brain uses the same way. This owner creates
// the folder's missing entries and reads its text; it never follows a link
// at the home or below it, since a link there could hand another file to
// every brain. Home text gives knowledge, never permission: the gate stays
// the only source of that.
// Contract: docs/decisions/D105-jarvis-home-folder.md.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const Core = require("./Core.js");
const Tools = require("./Tools.js");
const { O_RDONLY, O_WRONLY, O_CREAT, O_EXCL, O_DIRECTORY, O_NOFOLLOW, O_NONBLOCK } = fs.constants;

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

/**
 * Create the entries of LAYOUT the home lacks, and the home itself. An entry
 * already there is kept byte for byte. A link at the home or at any layout
 * path throws jarvis: home=link and is never followed; an entry of the other
 * kind throws home=kind, and a failed write home=unwritable.
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

// At most limit + 1 bytes of a regular file.
function bytes(fd, limit) {
    if (!fs.fstatSync(fd).isFile()) fail("kind");
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
 * Read ENTRY of the home as UTF-8 text of at most LIMIT bytes:
 * {kind: "text", text}, or {kind: "too-large"}; never a cut text. Throws
 * jarvis: home=absent, link, kind, unreadable or text.
 */
function read(home, entry, limit) {
    // O_NONBLOCK: a FIFO in the file's place answers at once, as not a file.
    return within(home, entry, O_RDONLY | O_NONBLOCK, fd => {
        const content = bytes(fd, limit);
        if (content.length > limit) return { kind: "too-large" };
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

/**
 * The home's skills in topic order: {skills: [{topic, file, line}], complete}.
 * A skill is `<name>.md` or `<name>/SKILL.md` directly in skills/base or
 * skills/own, a regular file under a name Tools.homeTopic admits; any other
 * entry, a link among them, is no skill. topic is "<set>/<name>", file its
 * path in the home and line its index line. complete is false once a set
 * holds more than SET_ENTRIES entries.
 */
function skills(home) {
    const found = [];
    let complete = true;
    for (const set of SETS) {
        const names = within(home, "skills/" + set, O_RDONLY | O_DIRECTORY, fd => {
            // The descriptor's own /proc path: the folder held, not a name looked up again.
            const directory = fs.opendirSync("/proc/self/fd/" + fd);
            try {
                const entries = [];
                for (let entry = directory.readSync(); entry !== null; entry = directory.readSync()) {
                    if (entries.length === SET_ENTRIES) { complete = false; break; }
                    entries.push(entry);
                }
                return entries;
            } finally { directory.closeSync(); }
        });
        for (const entry of names) {
            const flat = entry.isFile() && entry.name.endsWith(".md");
            if (!flat && !entry.isDirectory()) continue;
            const topic = set + "/" + (flat ? entry.name.slice(0, -3) : entry.name);
            if (Tools.homeTopic(topic) === null) continue;
            const file = "skills/" + set + "/" + (flat ? entry.name : entry.name + "/SKILL.md");
            let head;
            try { head = within(home, file, O_RDONLY | O_NONBLOCK, fd => bytes(fd, HEAD_BYTES - 1)); }
            catch (error) {
                // A folder without SKILL.md, or with a link in its place, is no skill.
                if (!flat && /^jarvis: home=(?:absent|link|kind)$/.test(error.message)) continue;
                throw error;
            }
            found.push({ topic, file, line: indexLine(new TextDecoder("utf-8").decode(head)) });
        }
    }
    found.sort((left, right) => left.topic < right.topic ? -1 : left.topic > right.topic ? 1 : 0);
    return { skills: found, complete };
}

/**
 * The body of the skill TOPIC names, as read() answers it. Throws
 * jarvis: home=absent for a topic the home does not hold.
 */
function skill(home, topic, limit) {
    const named = Tools.homeTopic(topic);
    if (named === null) fail("absent");
    const base = "skills/" + named.set + "/" + named.name;
    try { return read(home, base + ".md", limit); }
    catch (error) {
        if (error.message !== "jarvis: home=absent") throw error;
        return read(home, base + "/SKILL.md", limit);
    }
}

module.exports = { resolve, layout, guard, read, skills, skill };
