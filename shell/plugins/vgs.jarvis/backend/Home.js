// The Jarvis home folder: the one folder the user picks, whose AGENTS.md,
// skills, memory and state every brain uses the same way. kendex installs
// and updates the Jarvis package there and the package's init writes its
// starting files (D126); this owner only judges the home and reads its
// text. It writes nothing in the home but Repair's result record, and never
// follows a link at the home or below it, since a link there could hand
// another file to every brain. Home text gives knowledge, never
// permission: the gate stays the only source of that. It also finds the
// two programs of the home VGS starts: the kendex mail tool that writes the
// Jarvis session's mailbox there, and the Jarvis package's session command.
// Contract: docs/decisions/D105-jarvis-home-folder.md and
// docs/decisions/D126-kendex-owns-the-jarvis-package.md.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { createHash } = require("node:crypto");
const Core = require("./Core.js");
const Tools = require("./Tools.js");
const { O_RDONLY, O_WRONLY, O_CREAT, O_EXCL, O_DIRECTORY, O_NOFOLLOW, O_NONBLOCK } = fs.constants;

// The base package: kendex's jarvis skill; the persona is its persona.md.
const PACKAGE = "jarvis";
// kendex renders the package at RENDER/PACKAGE, beside the skills it
// requires. Of that set, help reads the package and the skills its
// SKILL.md declares required (declaration), never another one.
const RENDER = ".agents/skills";
// The files of the package read by name: a render without one is partial.
const RENDER_FILES = Object.freeze(["SKILL.md", "persona.md"]);
// kendex's record of each package it installed, read at any version for its
// entries alone (installed).
const LOCK = ".kendex-lock.json";
// The bound of Repair's result record.
const RECORD_BYTES = 1 << 20;
// The Home step reads the last repair result, never as proof of readiness.
const REPAIR_RECORD = ".vgs-home-repair.json";
// The starting files the package's init writes, by kind: a home without
// one is not set up yet.
const STARTING = Object.freeze([["AGENTS.md", "file"], ["memory/MEMORY.md", "file"], ["state", "directory"]]);
// The one entry of the home the gate leaves a model: Jarvis writes it
// through files.write. Every other path in the folder is the user's, the
// package's and VGS's alone.
const OPEN = "state";
const SETS = Object.freeze(["base", "own"]);
// Entries read from one skill set before the listing answers incomplete.
const SET_ENTRIES = 256;
// A memory search call walks personal notes on demand. These recovery
// ceilings refuse an unexpectedly large tree instead of publishing a partial
// index as complete.
const NOTE_ENTRIES = 10000;
const NOTE_DEPTH = 16;
// The head of a skill file its index line is read from, and that line's
// bound in characters.
const HEAD_BYTES = 4096;
const LINE_CHARS = 160;
// Linux PATH_MAX, the anchored walk's own bound.
const PATH_BYTES = 4096;
// The home list is a short Settings offer list, not a history.
const HOMES = 10;
const OFFER_VALUE_MAX = 200;
const OFFER_LABEL_MAX = 60;
// The program of the home a brain's action starts: lane-mail, which kendex
// installs here with its mailbox skill, writes the Jarvis session's mailbox
// (D105). It runs the mailbox skill's own scripts and the home's kendex
// settings in turn; Jarvis starts no other path of the home.
const MAIL_TOOL = ".agents/skills/mailbox/scripts/lane-mail";
// The home's own repository entry: a folder, or a file for a worktree.
// lane-mail takes the repository its working folder belongs to, so without
// one it would take a repository the home lies inside, and that one's
// settings and .env.local.
const OWN_REPOSITORY = ".git";
// The Jarvis session's mailbox folder, as lane-mail lays it out below its
// root. The Jarvis session makes it when it first reads its mail; Jarvis
// never does.
const MAILBOX = "tmp/lane-mail/overseer";
// The Jarvis package's session command, which kendex installs with the
// package: the one owner of the user's Jarvis session, its record, its
// resume and its hand-over.
const SESSION_COMMAND = ".agents/skills/jarvis/scripts/jarvis-session";
// A YAML block scalar's header: > or |, then an optional chomping mark and
// indent digit in either order. Its text is on the lines below it.
const BLOCK_SCALAR = /^[>|][-+1-9]{0,2}$/;
// A name the package declares, which becomes a path component of the home.
const DECLARED_NAME = /^[a-z0-9][a-z0-9-]*$/;
// The front matter lists of the package's dependencies read.
const DEPENDENCY_LISTS = Object.freeze(["required", "agents"]);
// The top-level front matter line by which an own skill's own file opts it
// in to Jarvis Voice: the value true, nothing else.
const VOICE_KEY = /^jarvis-voice:\s*true\s*$/;

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

function relativeHome(folder, userHome) {
    if (typeof folder !== "string" || typeof userHome !== "string" || !path.isAbsolute(folder) || !path.isAbsolute(userHome))
        fail("path");
    const base = path.resolve(userHome);
    const file = path.resolve(folder);
    const relative = path.relative(base, file);
    if (relative === "" || relative.startsWith("..") || path.isAbsolute(relative)) fail("path");
    return "~/" + relative.split(path.sep).join("/");
}

function homeOffer(folder, userHome) {
    let value;
    try { value = relativeHome(folder, userHome); } catch { return null; }
    if (value.length > OFFER_VALUE_MAX) return null;
    return { id: "h" + createHash("sha256").update(path.resolve(folder)).digest("hex").slice(0, 12),
        label: value.length <= OFFER_LABEL_MAX ? value : "…" + value.slice(1 - OFFER_LABEL_MAX), value };
}

/** Remembered homes that can cross the Settings choices wire. */
function remembered(list, userHome) {
    if (!Array.isArray(list)) return [];
    const found = [];
    const seen = new Set();
    for (const item of list) {
        if (typeof item !== "string" || !path.isAbsolute(item)) continue;
        const choice = homeOffer(item, userHome);
        if (choice === null || seen.has(choice.value)) continue;
        found.push(item);
        seen.add(choice.value);
        if (found.length === HOMES) break;
    }
    return found;
}

/** Put FOLDER first, once, among at most ten offerable absolute paths. */
function remember(list, folder, userHome = process.env.HOME) {
    const found = remembered(list, userHome);
    const choice = typeof folder === "string" && path.isAbsolute(folder) ? homeOffer(folder, userHome) : null;
    if (choice === null) return found;
    return [folder].concat(found.filter(item => homeOffer(item, userHome).value !== choice.value)).slice(0, HOMES);
}

/** Settings and launcher choices for remembered homes, with stable path ids. */
function offers(list, userHome) {
    return remembered(list, userHome).map(folder => homeOffer(folder, userHome));
}

// Hold the home folder itself open. The folders above it are the user's own
// path and resolve as the system gives them; the home is never a link. A
// folder that is not there throws home=missing.
function hold(home) {
    let file;
    try { file = path.join(fs.realpathSync.native(path.dirname(home)), path.basename(home)); }
    catch (error) { fail(error.code === "ENOENT" || error.code === "ENOTDIR" ? "missing" : "unreadable"); }
    const opened = Core.anchored().directory(file);
    switch (opened.kind) {
    case "directory": return opened.fd;
    case "absent": return fail("missing");
    case "link": return fail("link");
    case "not-directory": return fail("kind");
    default: return fail("unreadable");
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

// The path of every entry below the held folder FD, a folder's ending in
// "/", in no order. A link throws home=link and is never followed; any
// entry but a folder or a regular file throws home=kind.
function entries(fd, prefix = "", out = []) {
    const child = Core.anchored().child;
    const directory = fs.opendirSync("/proc/self/fd/" + fd);
    try {
        for (let entry = directory.readSync(); entry !== null; entry = directory.readSync()) {
            const kind = kindOf(fd, entry.name);
            if (kind !== "directory" && kind !== "file") fail(kind === "link" ? "link" : "kind");
            if (kind === "file") {
                out.push(prefix + entry.name);
                continue;
            }
            out.push(prefix + entry.name + "/");
            const held = fs.openSync(child(fd, entry.name), O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
            try { entries(held, prefix + entry.name + "/", out); }
            finally { fs.closeSync(held); }
        }
    } finally { directory.closeSync(); }
    return out;
}

// Write FILE in the held folder FD whole, under a scratch name it then
// renames over FILE.
function replace(fd, file, content) {
    const child = Core.anchored().child;
    const scratch = "." + file + "." + process.pid + ".new";
    fs.rmSync(child(fd, scratch), { force: true });
    const held = fs.openSync(child(fd, scratch), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644);
    try {
        try {
            fs.writeFileSync(held, content);
            // The process umask can clear bits the open asked for.
            fs.fchmodSync(held, 0o644);
        } finally { fs.closeSync(held); }
        fs.renameSync(child(fd, scratch), child(fd, file));
    } catch (error) {
        fs.rmSync(child(fd, scratch), { force: true });
        throw error;
    }
}

// Whether kendex's own record of what it installed in the home held as
// FD, its lock, names the package's skill, read for its entries' kinds and
// names alone, whatever lock version kendex wrote; false where the home
// holds no lock. A lock in a link's place throws home=link, one of another
// kind home=kind, and one VGS cannot read home=kendex-lock.
function installed(fd) {
    const kind = kindOf(fd, LOCK);
    if (kind === "absent") return false;
    if (kind === "link") fail("link");
    if (kind !== "file") fail("kind");
    const held = fs.openSync(Core.anchored().child(fd, LOCK), O_RDONLY | O_NONBLOCK | O_NOFOLLOW);
    let rows = null;
    try { rows = JSON.parse(bytes(held, null).toString("utf8"))?.entries; }
    catch {}
    finally { fs.closeSync(held); }
    if (rows === null || typeof rows !== "object") fail("kendex-lock");
    return Object.values(rows).some(row => row?.kind === "skill" && row.name === PACKAGE);
}

/**
 * Whether kendex's lock in the home names the Jarvis package's skill: a
 * home Setup has installed the package in, whose Repair and update refresh
 * it through kendex. Throws as hold and installed do.
 */
function packageInstalled(home) {
    const fd = hold(home);
    try { return installed(fd); }
    finally { fs.closeSync(fd); }
}

function repairResult(home, result) {
    const fd = hold(home);
    try {
        if (result !== undefined) {
            replace(fd, REPAIR_RECORD, JSON.stringify(result) + "\n");
            return result;
        }
        const kind = kindOf(fd, REPAIR_RECORD);
        if (kind === "absent") return null;
        if (kind === "link") fail("link");
        if (kind !== "file") fail("kind");
        const file = fs.openSync(Core.anchored().child(fd, REPAIR_RECORD), O_RDONLY | O_NONBLOCK | O_NOFOLLOW);
        let raw;
        try { raw = bytes(file, RECORD_BYTES); } finally { fs.closeSync(file); }
        if (raw.length > RECORD_BYTES) fail("repair-record");
        let found;
        try { found = JSON.parse(raw.toString("utf8")); } catch { fail("repair-record"); }
        if (!found || !["running", "complete", "failed"].includes(found.kind)
                || (found.cause !== undefined && !/^[a-z][a-z=-]{0,79}$/.test(found.cause))
                || (found.code !== undefined && !Number.isInteger(found.code))) fail("repair-record");
        return found;
    } finally { fs.closeSync(fd); }
}

/**
 * Judge the home a setting names, writing nothing: the folder, the Jarvis
 * package kendex installed there (source) and the starting files the
 * package's init wrote (STARTING). Throws jarvis: home=missing for no
 * folder, home=not-set-up for a folder without the package or a starting
 * file, which Setup installs, home=link or home=kind for an entry Jarvis
 * cannot follow, home=package for a package without a file it reads by
 * name, which Repair restores, and home=unreadable otherwise. Opening a
 * home installs nothing (D126).
 */
function judge(home) {
    const fd = hold(home);
    try {
        try { source(fd); }
        catch (error) {
            if (error.message === "jarvis: home=absent") fail("not-set-up");
            throw error;
        }
    } finally { fs.closeSync(fd); }
    for (const [entry, kind] of STARTING) {
        try {
            within(home, entry, kind === "directory" ? O_RDONLY | O_DIRECTORY : O_RDONLY | O_NONBLOCK, held => {
                if (kind === "file" && !fs.fstatSync(held).isFile()) fail("kind");
            });
        } catch (error) {
            if (error.message === "jarvis: home=absent") fail("not-set-up");
            throw error;
        }
    }
}

// The set of the home held as FD that the base package is read from:
// RENDER, once it holds RENDER/PACKAGE. A home without it throws home=absent,
// which a reader answers by judging the home again; a render reached through
// a link, holding a link or an entry neither a folder nor a regular file, or
// without a file of RENDER_FILES throws home=link, home=kind or home=package.
function source(fd) {
    const child = Core.anchored().child;
    let at = fd;
    try {
        for (const part of [...RENDER.split("/"), PACKAGE]) {
            const kind = kindOf(at, part);
            if (kind === "absent") return fail("absent");
            if (kind === "link") return fail("link");
            if (kind !== "directory") return fail("kind");
            const next = fs.openSync(child(at, part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
            if (at !== fd) fs.closeSync(at);
            at = next;
        }
        const found = entries(at);
        if (!RENDER_FILES.every(name => found.includes(name))) fail("package");
        return RENDER;
    } catch (error) {
        if (/^jarvis: home=/.test(error.message)) throw error;
        return fail("unreadable");
    } finally { if (at !== fd) fs.closeSync(at); }
}

/**
 * The set of the home the base package is read from, ".agents/skills",
 * once source has judged it, on each open of the home: the judgement, a skill
 * index or a skill read. Throws as source does.
 */
function baseSet(home) {
    const fd = hold(home);
    try { return source(fd); } finally { fs.closeSync(fd); }
}

// Open ENTRY, a relative path of plain names, below the held home, each
// component without following a link, and hand its descriptor to act.
function within(home, entry, flags, act) {
    const child = Core.anchored().child;
    let fd = hold(home);
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

function directory(home, entry) {
    const child = Core.anchored().child;
    let fd = hold(home);
    try {
        for (const part of entry.split("/")) {
            let next;
            try {
                const kind = kindOf(fd, part);
                if (kind === "absent") fail(kind);
                if (kind === "link") {
                    fail(kind);
                }
                if (kind !== "directory") fail("kind");
                next = fs.openSync(child(fd, part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
            } catch (error) {
                if (/^jarvis: home=/.test(error.message)) throw error;
                return fail("unreadable");
            }
            fs.closeSync(fd);
            fd = next;
        }
        const result = fd;
        fd = undefined;
        return result;
    } finally { if (fd !== undefined) fs.closeSync(fd); }
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

// The leading front matter block of TEXT, a skill file: {front, body}, the
// lines between its two `---` marks and the lines after it, with body null
// for a block that never closes; null for a file that opens with none.
function frontMatter(text) {
    const lines = text.split("\n");
    if (lines[0].trim() !== "---") return null;
    const end = lines.findIndex((line, index) => index > 0 && line.trim() === "---");
    return end === -1 ? { front: lines.slice(1), body: null } : { front: lines.slice(1, end), body: lines.slice(end + 1) };
}

// Whether TEXT, the head of an own skill's own file, opts the skill in to
// Jarvis Voice: a closed front matter block holding VOICE_KEY at its top
// level.
function voiced(text) {
    const block = frontMatter(text);
    return block !== null && block.body !== null && block.front.some(line => VOICE_KEY.test(line));
}

// A skill's index line: the one-line `description` of a leading front
// matter block, as a harness skill file carries, else the first line of
// text, its heading marks dropped. A block scalar description is not read.
function indexLine(text) {
    let lines = text.split("\n");
    const block = frontMatter(text);
    if (block !== null) {
        const described = block.front.map(line => /^description:\s*(.*)$/.exec(line)).find(match => match !== null);
        const value = described ? described[1].trim().replace(/^(["'])(.*)\1$/, "$2") : "";
        if (value !== "" && !BLOCK_SCALAR.test(value)) return value.slice(0, LINE_CHARS);
        lines = block.body ?? [];
    }
    const first = lines.find(line => line.trim() !== "") ?? "";
    return first.trim().replace(/^#+\s*/, "").replace(/[\x00-\x1f\x7f]/g, " ").slice(0, LINE_CHARS);
}

// ITEMS, the raw entries of one declared list, as plain names.
function declaredNames(items) {
    return items.map(item => {
        const name = item.trim().replace(/^(["'])(.*)\1$/, "$2");
        if (!DECLARED_NAME.test(name)) fail("declaration");
        return name;
    });
}

// The DEPENDENCY_LISTS of the `dependencies` map in the leading front matter
// of TEXT, a skill file, as {required, agents}; a list it leaves out is
// empty, and a skill file with no front matter declares none. A list is a
// one-line flow list or block items on the lines below its key; any other
// value of those keys, or front matter that never closes, throws
// home=declaration.
function dependencies(text) {
    const found = Object.fromEntries(DEPENDENCY_LISTS.map(key => [key, []]));
    const block = frontMatter(text);
    if (block === null) return found;
    if (block.body === null) fail("declaration");
    let inside = false;
    let keyIndent = null;
    let open = null;
    for (const line of block.front) {
        if (line.trim() === "" || line.trimStart().startsWith("#")) continue;
        const indent = line.length - line.trimStart().length;
        if (indent === 0 && !line.startsWith("-")) {
            inside = /^dependencies:\s*$/.test(line);
            keyIndent = null;
            open = null;
            continue;
        }
        if (!inside) continue;
        const key = /^\s*([A-Za-z0-9_-]+):\s*(.*?)\s*$/.exec(line);
        if (key && (keyIndent === null || indent === keyIndent)) {
            keyIndent = indent;
            open = DEPENDENCY_LISTS.includes(key[1]) ? key[1] : null;
            if (open === null) continue;
            const value = key[2];
            if (value === "") continue;
            const flow = /^\[(.*)\]$/.exec(value);
            if (!flow) fail("declaration");
            if (flow[1].trim() !== "") found[open].push(...declaredNames(flow[1].split(",")));
            open = null;
            continue;
        }
        if (open === null) continue;
        const item = /^\s*-\s+(.*?)\s*$/.exec(line);
        if (!item) fail("declaration");
        found[open].push(...declaredNames([item[1]]));
    }
    return found;
}

/**
 * What the base package declares beside its own files, read from its own
 * SKILL.md text, never from a list kept in VGS: the skills its front
 * matter's dependencies.required names and the agents its
 * dependencies.agents names, as {skills, agents}, each sorted, once, and
 * without PACKAGE. Throws jarvis: home=declaration for a list in another
 * form or a name that is no plain name.
 */
function declaration(skill) {
    const front = dependencies(skill);
    const set = list => [...new Set(list)].filter(name => name !== PACKAGE).sort();
    return { skills: set(front.required), agents: set(front.agents) };
}

// The skills of the base set help reads: the package and each skill its
// SKILL.md requires, the guidance its persona routes to (D126).
function baseNames(home, base) {
    return [PACKAGE, ...declaration(read(home, base + "/" + PACKAGE + "/SKILL.md", null).text).skills];
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

// The index entry of FILE under TOPIC, or null where OPTIONAL lets the file
// be absent, a link or no regular file, and where VOICE requires its head to
// opt the skill in to Jarvis Voice (voiced) and it does not.
function indexed(home, topic, file, optional, voice) {
    let head;
    try { head = within(home, file, O_RDONLY | O_NONBLOCK, fd => bytes(fd, HEAD_BYTES - 1)); }
    catch (error) {
        if (optional && /^jarvis: home=(?:absent|link|kind)$/.test(error.message)) return null;
        throw error;
    }
    const text = new TextDecoder("utf-8").decode(head);
    if (voice && !voiced(text)) return null;
    return { topic, file, line: indexLine(text) };
}

/**
 * The home's skills in topic order: {skills: [{topic, file, line}], complete}.
 * A skill is `<name>/SKILL.md` directly in the base set (baseSet, holding
 * the package and the skills it requires, baseNames), or `<name>.md` or
 * `<name>/SKILL.md` directly in skills, which a home may lack, a
 * regular file under a name Tools.homeTopic admits. A folder skill's
 * `references/<reference>.md` is a skill of its own under
 * "<set>/<name>/<reference>", and its `workflows/<workflow>.md` one under
 * "<set>/<name>/workflows/<workflow>", listed for the package and skills;
 * a required skill's are read by topic alone. A skill of skills is listed,
 * with its references and workflows, only while its own file opts it in to
 * Jarvis Voice (voiced); the folders of one that does not stay unread. Any
 * other entry, a link among them, is no skill. topic is "<set>/<name>", file
 * its path in the home and line its index line. complete is false once a
 * folder holds more than SET_ENTRIES entries, counted before any skill is
 * read.
 */
function skills(home) {
    const found = [];
    let complete = true;
    // Each regular `<name>.md` file of FOLDER, under PREFIX + name, where
    // VOICE holds only one that opts in to Jarvis Voice.
    function flat(folder, prefix, listed, voice) {
        complete &&= listed.complete;
        for (const entry of listed.entries) {
            const topic = prefix + entry.name.slice(0, -3);
            if (entry.isFile() && entry.name.endsWith(".md") && Tools.homeTopic(topic) !== null) {
                const skill = indexed(home, topic, folder + "/" + entry.name, false, voice);
                if (skill !== null) found.push(skill);
            }
        }
    }
    const base = baseSet(home);
    const names = baseNames(home, base);
    for (const set of SETS) {
        const folder = set === "base" ? base : "skills";
        let listed;
        try { listed = listing(home, folder); }
        catch (error) {
            // The package's init makes no skills: the user's first skill does.
            if (set === "own" && error.message === "jarvis: home=absent") continue;
            throw error;
        }
        if (folder === RENDER) listed = { entries: listed.entries.filter(entry => names.includes(entry.name)), complete: listed.complete };
        flat(folder, set + "/", listed, set === "own");
        for (const entry of listed.entries) {
            const topic = set + "/" + entry.name;
            if (Tools.homeTopic(topic) === null) continue;
            // An entry that is no folder, a folder without SKILL.md, or one with a
            // link in its place, is no skill.
            const skill = indexed(home, topic, folder + "/" + entry.name + "/SKILL.md", true, set === "own");
            if (skill === null) continue;
            found.push(skill);
            // A required skill's references and workflows stay readable by
            // topic (skill) without a line each in every start text.
            if (folder === RENDER && entry.name !== PACKAGE) continue;
            // A reference keeps the topic "<set>/<name>/<reference>"; a workflow
            // takes "<set>/<name>/workflows/<workflow>", so the two never share one.
            for (const [part, prefix] of [["references", topic + "/"], ["workflows", topic + "/workflows/"]]) {
                const inner = folder + "/" + entry.name + "/" + part;
                let inside;
                try { inside = listing(home, inner); }
                catch (error) {
                    if (/^jarvis: home=(?:absent|link|kind)$/.test(error.message)) continue;
                    throw error;
                }
                flat(inner, prefix, inside, false);
            }
        }
    }
    found.sort((left, right) => left.topic < right.topic ? -1 : left.topic > right.topic ? 1 : 0);
    return { skills: found, complete };
}

/**
 * The whole text of the skill TOPIC names. A skill is read on demand, so no
 * size bound applies; the bounds are on what every brain gets at its start.
 * Throws as read() does, and jarvis: home=absent for a topic the home does
 * not hold, an own skill, reference or workflow whose skill's own file does
 * not opt in to Jarvis Voice among them, as skills leaves it unlisted.
 */
function skill(home, topic) {
    const named = Tools.homeTopic(topic);
    if (named === null) fail("absent");
    const set = named.set === "base" ? baseSet(home) : "skills";
    if (set === RENDER && !baseNames(home, set).includes(named.name)) fail("absent");
    const base = set + "/" + named.name;
    const whole = file => read(home, file, null).text;
    // The whole text of FILE, part of the skill whose own file is SKILL_FILE,
    // which for an own skill must opt in to Jarvis Voice.
    const offered = (skillFile, file = skillFile) => {
        if (set !== RENDER && indexed(home, topic, skillFile, false, true) === null) fail("absent");
        return whole(file);
    };
    if (named.file !== null) return offered(base + "/SKILL.md", base + "/" + named.folder + "/" + named.file + ".md");
    // The render's set holds skill folders alone, never a flat file.
    if (set !== RENDER) {
        try { return offered(base + ".md"); }
        catch (error) { if (error.message !== "jarvis: home=absent") throw error; }
    }
    return offered(base + "/SKILL.md");
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

/**
 * The memory notes the search index may read: Markdown files below memory/,
 * never inbox/, dot entries, links or non-regular files. Each row carries the
 * entry's stat facts, so the index owner can select what Home.note re-opens.
 */
function notes(home) {
    return within(home, "memory", O_RDONLY | O_DIRECTORY, fd => {
        const found = [];
        const child = Core.anchored().child;
        function walk(parent, prefix, depth) {
            if (depth > NOTE_DEPTH) fail("notes-too-many");
            let directory;
            try { directory = fs.opendirSync("/proc/self/fd/" + parent); }
            catch { fail("unreadable"); }
            try {
                for (;;) {
                    let entry;
                    try { entry = directory.readSync(); }
                    catch { fail("unreadable"); }
                    if (entry === null) break;
                    if (entry.name.startsWith(".")) continue;
                    if (prefix === "" && entry.name === "inbox") continue;
                    const id = prefix + entry.name;
                    let stat;
                    try { stat = fs.lstatSync(child(parent, entry.name), { bigint: true }); }
                    catch (error) {
                        if (error.code === "ENOENT") continue;
                        fail("unreadable");
                    }
                    if (stat.isSymbolicLink()) continue;
                    if (stat.isDirectory()) {
                        let held;
                        try { held = fs.openSync(child(parent, entry.name), O_RDONLY | O_DIRECTORY | O_NOFOLLOW); }
                        catch { fail("unreadable"); }
                        try { walk(held, id + "/", depth + 1); }
                        finally { fs.closeSync(held); }
                        continue;
                    }
                    if (!stat.isFile() || !entry.name.endsWith(".md") || !Tools.memoryNote(id)) continue;
                    found.push({ id, size: stat.size, mtimeNs: stat.mtimeNs, ctimeNs: stat.ctimeNs, ino: stat.ino });
                    if (found.length > NOTE_ENTRIES) fail("notes-too-many");
                }
            } finally { directory.closeSync(); }
        }
        walk(fd, "", 0);
        found.sort((left, right) => left.id < right.id ? -1 : left.id > right.id ? 1 : 0);
        return found;
    });
}

// What ACT answers on the held ENTRY of the home, or null while the home
// does not hold it as a walk that follows no link reaches it.
function held(home, entry, flags, act) {
    try { return within(home, entry, flags, act); }
    catch (error) {
        if (/^jarvis: home=/.test(error.message)) return null;
        throw error;
    }
}

/**
 * The absolute path of the home's mail tool, MAIL_TOOL reached through no
 * link and a regular file with its owner's execute bit, in a home that is
 * its own repository (OWN_REPOSITORY, a folder or a file, no link); else
 * null, as while the home cannot be read. The caller runs it by this path:
 * the home's writers are the user, VGS and the Jarvis session (D105), and
 * the gate keeps every model out of the folder.
 */
function mailTool(home) {
    const own = held(home, OWN_REPOSITORY, O_RDONLY | O_NONBLOCK, fd => {
        const stat = fs.fstatSync(fd);
        return stat.isDirectory() || stat.isFile();
    });
    if (own !== true) return null;
    return held(home, MAIL_TOOL, O_RDONLY | O_NONBLOCK, fd => {
        const stat = fs.fstatSync(fd);
        return stat.isFile() && (stat.mode & 0o100) !== 0 ? path.join(home, MAIL_TOOL) : null;
    });
}

/**
 * The home's Jarvis session command, SESSION_COMMAND reached through no
 * link: { kind: "found", path } for a regular file with its owner's execute
 * bit, else { kind } of what stops it: "absent" for no such entry or one
 * that is no program, "link" for a link on the way, "kind" for a part of
 * the way that is no folder, "unreadable" for a part that cannot be opened
 * (within). The shell runs it by this path, never a brain: it starts and
 * stops the user's own Jarvis session (D105).
 */
function sessionCommand(home) {
    try {
        return within(home, SESSION_COMMAND, O_RDONLY | O_NONBLOCK, fd => {
            const found = fs.fstatSync(fd);
            const runs = found.isFile() && (found.mode & fs.constants.S_IXUSR) !== 0;
            return runs ? { kind: "found", path: path.join(home, SESSION_COMMAND) } : { kind: "absent" };
        });
    } catch (error) {
        const code = /^jarvis: home=([a-z-]+)/.exec(error.message);
        if (code === null) throw error;
        return { kind: ["absent", "link", "kind"].includes(code[1]) ? code[1] : "unreadable" };
    }
}

/** Whether the home holds the Jarvis session's mailbox folder, no link on the way. */
function mailbox(home) {
    return held(home, MAILBOX, O_RDONLY | O_DIRECTORY, () => true) === true;
}

module.exports = { PACKAGE, SESSION_COMMAND, resolve, relativeHome, remembered, remember, offers, judge, packageInstalled, repairResult, guard, baseSet, read, declaration, skills, skill, note, notes, mailTool, mailbox, sessionCommand, directory };
