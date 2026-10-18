// The Jarvis home folder: the one folder the user picks, whose AGENTS.md,
// skills, memory and state every brain uses the same way. This owner creates
// the folder's missing entries, keeps the Jarvis package in kendex's own
// layout, a copy of the render VGS ships, in a home kendex did not install it
// in, and reads its text; it never follows a link at the home or below
// it, since a link there could hand another file to every brain. Home text
// gives knowledge, never permission: the gate stays the only source of that.
// It also finds the two programs of the home VGS starts: the kendex mail
// tool that writes the Jarvis session's mailbox there, and the Jarvis
// package's session command.
// Contract: docs/decisions/D105-jarvis-home-folder.md.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { createHash } = require("node:crypto");
const Core = require("./Core.js");
const Tools = require("./Tools.js");
const { O_RDONLY, O_WRONLY, O_CREAT, O_EXCL, O_DIRECTORY, O_NOFOLLOW, O_NONBLOCK, S_IXUSR } = fs.constants;

// The two harness files serve the user's own Claude Code or Codex session
// started in the home; a brain Jarvis starts never runs there. Claude Code's
// key is autoMemoryEnabled (code.claude.com/docs/en/memory) and Codex's are
// features.memories and the memories table
// (developers.openai.com/codex/config-reference).
const LAYOUT = Object.freeze([
    ["AGENTS.md", ""],
    ["skills", null], ["skills/own", null],
    ["memory", null], ["memory/MEMORY.md", ""], ["memory/inbox", null],
    ["state", null],
    [".claude", null], [".claude/settings.json", "{\"autoMemoryEnabled\": false}\n"],
    [".codex", null], [".codex/config.toml", "[features]\nmemories = false\n\n[memories]\ngenerate_memories = false\nuse_memories = false\n"]
]);
// The base package: kendex's jarvis skill; the persona is its persona.md.
const PACKAGE = "jarvis";
// kendex renders the package at RENDER/PACKAGE, beside the skills it
// requires, which are no Jarvis help topic, in a home kendex installed it
// in and in the render VGS ships (Core.homeRender) alike.
const RENDER = ".agents/skills";
// The files of the package read by name: a render without one is partial.
const RENDER_FILES = Object.freeze(["SKILL.md", "persona.md"]);
// kendex's record of each path it wrote, by kind and harness: the render's,
// read in the lock version this reader knows, and a home's own, read at any
// version for its entries alone (installed).
const LOCK = ".kendex-lock.json";
const LOCK_VERSION = 11;
// The kinds of the render VGS copies into a home. A hook needs its
// harness's settings as well, which nothing here writes yet.
const COPIED_KINDS = Object.freeze(["skill", "agent"]);
// VGS's record of the package files it wrote in a home, {files: [path]}, so
// it replaces and removes those files only.
const RECORD = ".vgs-package.json";
const RECORD_BYTES = 1 << 20;
// The Home step reads the last repair result, never as proof of readiness.
const REPAIR_RECORD = ".vgs-home-repair.json";
// VGS's copy of the package before the home took kendex's layout.
const OLD_COPY = "skills/base";
// The CLAUDE.md VGS wrote before: one line importing AGENTS.md, which Claude
// Code reads itself, while a CLAUDE.md turns its nested loading off. The
// open removes a regular file holding exactly this and keeps any other.
const OLD_CLAUDE = Object.freeze(["CLAUDE.md", "@AGENTS.md\n"]);
// The one entry of the home the gate leaves a model: Jarvis writes it
// through files.write. Every other path in the folder, an entry this layout
// does not name among them, is the user's and VGS's alone.
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
// The front matter lists of the package's dependencies read, and the
// arrays of its kendex catalog bundle table read.
const DEPENDENCY_LISTS = Object.freeze(["required", "agents"]);
const BUNDLE_LISTS = Object.freeze(["skills", "agents", "hooks"]);
// A TOML table header line, which ends the table above it.
const TABLE_HEADER = /^\[{1,2}[^\]"]+\]{1,2}\s*(?:#.*)?$/;

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

// Every entry below the held folder FD as [path, bytes, executable], a
// folder's path ending in "/" with no bytes, in no order; executable is the
// owner's execute bit of a file. A link throws home=link and is never
// followed; any entry but a folder or a regular file throws home=kind. A
// file reads whole for a null LIMIT, else as at most LIMIT + 1 bytes.
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
                    out.push([prefix + entry.name + "/", Buffer.alloc(0), false]);
                    entries(held, limit, prefix + entry.name + "/", out);
                } else out.push([prefix + entry.name, limit === null ? fs.readFileSync(held) : bytes(held, limit),
                    (fs.fstatSync(held).mode & S_IXUSR) !== 0]);
            } finally { fs.closeSync(held); }
        }
    } finally { directory.closeSync(); }
    return out;
}

// The names of NAME, a relative path of plain names, or null for any other
// value: an empty or absolute path, ".", "..", a NUL or one past PATH_BYTES.
function plainParts(name) {
    if (typeof name !== "string" || name === "" || Buffer.byteLength(name) > PATH_BYTES) return null;
    const parts = name.split("/");
    return parts.every(part => part !== "" && part !== "." && part !== ".." && !part.includes("\0")) ? parts : null;
}

// Hold each folder PARTS names below the held folder FD in turn, making a
// missing one where MAKE, and answer what ACT answers on the descriptors,
// FD first, or on null where a folder is absent and MAKE is false. A link
// throws home=link and any other entry home=kind. The descriptors close
// when ACT returns.
function along(fd, parts, make, act) {
    const child = Core.anchored().child;
    const chain = [fd];
    try {
        for (const part of parts) {
            const at = chain[chain.length - 1];
            const kind = kindOf(at, part);
            if (kind === "link") fail("link");
            if (kind === "absent") {
                if (!make) return act(null);
                fs.mkdirSync(child(at, part));
            } else if (kind !== "directory") fail("kind");
            chain.push(fs.openSync(child(at, part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW));
        }
        return act(chain);
    } finally { for (const held of chain.slice(1)) fs.closeSync(held); }
}

// The package files of the render VGS ships as [path, bytes, executable],
// sorted by path: every file below each path its lock names for an entry of
// COPIED_KINDS. A render that cannot be read, a lock of another version, a
// path that is no plain path, a link, or a render without a skill or an
// agent its package declares, throws home=package: the render is partial.
function rendered() {
    const child = Core.anchored().child;
    let root;
    try { root = fs.openSync(Core.homeRender(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW); }
    catch { return fail("package"); }
    try {
        const held = fs.openSync(child(root, LOCK), O_RDONLY | O_NONBLOCK | O_NOFOLLOW);
        let lock;
        try { lock = JSON.parse(bytes(held, null).toString("utf8")); } finally { fs.closeSync(held); }
        if (lock?.version !== LOCK_VERSION || typeof lock.entries !== "object" || lock.entries === null) fail("package");
        const found = new Map();
        const names = Object.fromEntries(COPIED_KINDS.map(kind => [kind, new Set()]));
        for (const entry of Object.values(lock.entries)) {
            if (!COPIED_KINDS.includes(entry?.kind)) continue;
            names[entry.kind].add(entry.name);
            if (!Array.isArray(entry.emitted?.paths)) fail("package");
            for (const at of entry.emitted.paths) {
                const parts = plainParts(at);
                if (parts === null) fail("package");
                along(root, parts.slice(0, -1), false, chain => {
                    if (chain === null) fail("package");
                    const parent = chain[chain.length - 1];
                    const kind = kindOf(parent, parts[parts.length - 1]);
                    if (kind !== "directory" && kind !== "file") fail("package");
                    const opened = fs.openSync(child(parent, parts[parts.length - 1]),
                        (kind === "directory" ? O_RDONLY | O_DIRECTORY : O_RDONLY | O_NONBLOCK) | O_NOFOLLOW);
                    try {
                        if (kind === "file") found.set(at, [fs.readFileSync(opened), (fs.fstatSync(opened).mode & S_IXUSR) !== 0]);
                        else for (const [inner, content, executable] of entries(opened, null))
                            if (!inner.endsWith("/")) found.set(at + "/" + inner, [content, executable]);
                    } finally { fs.closeSync(opened); }
                });
            }
        }
        if (!RENDER_FILES.every(name => found.has(RENDER + "/" + PACKAGE + "/" + name))) fail("package");
        const skill = found.get(RENDER + "/" + PACKAGE + "/SKILL.md");
        const declared = declaration(skill[0].toString("utf8"), null);
        if (![PACKAGE, ...declared.skills].every(name => names.skill.has(name)) || !declared.agents.every(name => names.agent.has(name)))
            fail("package");
        return [...found].map(([name, [content, executable]]) => [name, content, executable])
            .sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0);
    } catch { return fail("package"); }
    finally { fs.closeSync(root); }
}

// The paths VGS's record in the home held as FD names, or null where the
// home holds no record. A record in a link's place throws home=link, one of
// another kind home=kind, and one that is no list of plain paths home=record.
function recorded(fd) {
    const kind = kindOf(fd, RECORD);
    if (kind === "absent") return null;
    if (kind === "link") fail("link");
    if (kind !== "file") fail("kind");
    const held = fs.openSync(Core.anchored().child(fd, RECORD), O_RDONLY | O_NONBLOCK | O_NOFOLLOW);
    let content;
    try { content = bytes(held, RECORD_BYTES); } finally { fs.closeSync(held); }
    let files = null;
    try { files = JSON.parse(content.toString("utf8"))?.files; } catch {}
    if (content.length > RECORD_BYTES || !Array.isArray(files) || !files.every(name => plainParts(name) !== null)) fail("record");
    return files;
}

// Write FILE in the held folder FD whole, under a scratch name it then
// renames over FILE, with the owner's execute bit where EXECUTABLE.
function replace(fd, file, content, executable) {
    const child = Core.anchored().child;
    const scratch = "." + file + "." + process.pid + ".new";
    fs.rmSync(child(fd, scratch), { force: true });
    const mode = executable ? 0o755 : 0o644;
    const held = fs.openSync(child(fd, scratch), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode);
    try {
        try {
            fs.writeFileSync(held, content);
            // The process umask can clear bits the open asked for.
            fs.fchmodSync(held, mode);
        } finally { fs.closeSync(held); }
        fs.renameSync(child(fd, scratch), child(fd, file));
    } catch (error) {
        fs.rmSync(child(fd, scratch), { force: true });
        throw error;
    }
}

// What the home held as FD holds at NAME, a plain path, beside a file of
// CONTENT and the EXECUTABLE bit: "absent", "same" or "differs". A link on
// the way or in its place throws home=link, and an entry of another kind
// home=kind.
function compare(fd, name, content, executable) {
    const parts = name.split("/");
    return along(fd, parts.slice(0, -1), false, chain => {
        if (chain === null) return "absent";
        const parent = chain[chain.length - 1];
        const kind = kindOf(parent, parts[parts.length - 1]);
        if (kind === "absent") return "absent";
        if (kind === "link") fail("link");
        if (kind !== "file") fail("kind");
        const held = fs.openSync(Core.anchored().child(parent, parts[parts.length - 1]), O_RDONLY | O_NONBLOCK | O_NOFOLLOW);
        try {
            const same = bytes(held, content.length).equals(content) && ((fs.fstatSync(held).mode & S_IXUSR) !== 0) === executable;
            return same ? "same" : "differs";
        } finally { fs.closeSync(held); }
    });
}

// Remove NAME, a file of VGS's record, from the home held as FD, and each
// folder above it that this leaves empty, below the home's own entries. A
// link in its place goes, never followed; a folder throws home=kind.
function drop(fd, name) {
    const child = Core.anchored().child;
    const parts = name.split("/");
    along(fd, parts.slice(0, -1), false, chain => {
        if (chain === null) return;
        const kind = kindOf(chain[chain.length - 1], parts[parts.length - 1]);
        if (kind === "directory") fail("kind");
        if (kind !== "absent") fs.unlinkSync(child(chain[chain.length - 1], parts[parts.length - 1]));
        for (let depth = chain.length - 1; depth > 1; depth--) {
            try { fs.rmdirSync(child(chain[depth - 1], parts[depth - 1])); }
            catch (error) {
                if (error.code === "ENOTEMPTY" || error.code === "EEXIST") return;
                throw error;
            }
        }
    });
}

// Whether NAME, a plain path, is one of PATHS or lies below one.
function under(name, paths) {
    return paths.some(at => name === at || name.startsWith(at + "/"));
}

// Make the home held as FD, whose record named BEFORE (null for none), hold
// the render's package files but at a path below CLAIMED, kendex's, and
// none of BEFORE's the render dropped. A file VGS did not write that differs
// from the render's stays the user's, unrecorded; one already equal joins
// the record. A path kendex took leaves the record and keeps its file. The
// record names every file before it is written, so a write cut short leaves
// no file of VGS's out of it, and the next open finishes the work.
function sync(fd, before, claimed) {
    const kept = before === null ? [] : before;
    const found = rendered().filter(([name]) => !under(name, claimed))
        .map(file => [file, compare(fd, ...file)])
        .filter(([[name], state]) => state !== "differs" || kept.includes(name));
    const names = found.map(([[name]]) => name);
    const stale = found.filter(([, state]) => state !== "same").map(([file]) => file);
    const same = kept.length === names.length && [...kept].sort().every((name, index) => name === names[index]);
    if (before !== null && same && stale.length === 0) return;
    record(fd, [...new Set([...kept, ...names])]);
    for (const [name, content, executable] of stale) {
        const parts = name.split("/");
        along(fd, parts.slice(0, -1), true, chain => replace(chain[chain.length - 1], parts[parts.length - 1], content, executable));
    }
    for (const name of kept) if (!names.includes(name) && !under(name, claimed)) drop(fd, name);
    record(fd, names);
}

// Write VGS's record in the home held as FD: FILES, sorted.
function record(fd, files) {
    replace(fd, RECORD, JSON.stringify({ files: [...files].sort() }) + "\n", false);
}

// kendex's own record of what it installed in the home held as FD, its
// lock, read for the entries' kinds, names and paths alone, whatever lock
// version kendex wrote: {jarvis, paths}, whether it installed the package's
// skill and every path it wrote, or null where the home holds no lock. A
// lock in a link's place throws home=link, one of another kind home=kind,
// and one VGS cannot read home=kendex-lock: VGS could not tell which files
// are kendex's.
function installed(fd) {
    const kind = kindOf(fd, LOCK);
    if (kind === "absent") return null;
    if (kind === "link") fail("link");
    if (kind !== "file") fail("kind");
    const held = fs.openSync(Core.anchored().child(fd, LOCK), O_RDONLY | O_NONBLOCK | O_NOFOLLOW);
    let entries = null;
    try { entries = JSON.parse(bytes(held, null).toString("utf8"))?.entries; }
    catch {}
    finally { fs.closeSync(held); }
    if (entries === null || typeof entries !== "object") fail("kendex-lock");
    const rows = Object.values(entries);
    return {
        jarvis: rows.some(row => row?.kind === "skill" && row.name === PACKAGE),
        paths: rows.flatMap(row => Array.isArray(row?.emitted?.paths) ? row.emitted.paths.filter(at => plainParts(at) !== null) : [])
    };
}

// Repair reads ownership without laying out a refused Home or consulting
// the shipped render, which may itself be the missing package input.
function packageOwner(home) {
    const fd = hold(home, false);
    try { return installed(fd)?.jarvis ? "kendex" : "vgs"; }
    finally { fs.closeSync(fd); }
}

function repairResult(home, result) {
    const fd = hold(home, false);
    try {
        if (result !== undefined) {
            replace(fd, REPAIR_RECORD, JSON.stringify(result) + "\n", false);
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
 * Create the entries of LAYOUT the home lacks, and the home itself. Where
 * kendex's lock in the home names the package's skill, kendex is the
 * package's one writer there: VGS writes no package file and drops its own
 * record. Elsewhere make the home hold the package files of the render VGS
 * ships, at their paths in it, but those at a path kendex's lock names and
 * a file VGS did not write that differs, and none of those VGS wrote that
 * the render dropped (sync). The open removes skills/base, VGS's copy of
 * the package before this layout, and the CLAUDE.md VGS wrote before, byte
 * for byte. Any other entry already there is kept byte for byte. A link at
 * the home, at a layout path or on the way to a package file VGS writes
 * throws jarvis: home=link and is never followed; an entry of the other kind
 * throws home=kind, a render that cannot be read or is partial home=package,
 * a record VGS cannot read home=record, a kendex lock it cannot read
 * home=kendex-lock, a package skill that source refuses as it says, and a
 * failed write home=unwritable.
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
        // Whatever entry stands there goes; a link goes, never followed.
        fs.rmSync(Core.anchored().child(held.get("skills"), path.basename(OLD_COPY)), { recursive: true, force: true });
        const [claude, shim] = OLD_CLAUDE;
        if (kindOf(held.get("."), claude) === "file" && compare(held.get("."), claude, Buffer.from(shim), false) === "same")
            fs.unlinkSync(Core.anchored().child(held.get("."), claude));
        const before = recorded(held.get("."));
        const kendex = installed(held.get("."));
        if (kendex?.jarvis) {
            if (before !== null) fs.unlinkSync(Core.anchored().child(held.get("."), RECORD));
        } else sync(held.get("."), before, kendex === null ? [] : kendex.paths);
        source(held.get("."));
    } catch (error) {
        if (/^jarvis: home=/.test(error.message)) throw error;
        fail("unwritable");
    } finally { for (const fd of held.values()) fs.closeSync(fd); }
}

/**
 * Remove the package files VGS wrote in the home, but those at a path
 * kendex's lock there names, and VGS's record, so that kendex can install
 * its packages over them: kendex treats a file it did not write as the
 * user's. The next layout writes again what kendex did not take. Throws
 * jarvis: home=unreadable for a home that is not there, home=link or
 * home=kind for an entry on the way, home=record or home=kendex-lock for a
 * record or lock it cannot read, and home=unwritable for a failed removal.
 */
function release(home) {
    const fd = hold(home, false);
    try {
        const before = recorded(fd);
        if (before === null) return;
        const kendex = installed(fd);
        for (const name of before) if (!under(name, kendex === null ? [] : kendex.paths)) drop(fd, name);
        fs.unlinkSync(Core.anchored().child(fd, RECORD));
    } catch (error) {
        if (/^jarvis: home=/.test(error.message)) throw error;
        fail("unwritable");
    } finally { fs.closeSync(fd); }
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
        const found = entries(at, 0).map(([name]) => name);
        if (!RENDER_FILES.every(name => found.includes(name))) fail("package");
        return RENDER;
    } catch (error) {
        if (/^jarvis: home=/.test(error.message)) throw error;
        return fail("unreadable");
    } finally { if (at !== fd) fs.closeSync(at); }
}

/**
 * The set of the home the base package is read from, ".agents/skills",
 * once source has judged it, on each open of the home: the layout, a skill
 * index or a skill read. Throws as source does.
 */
function baseSet(home) {
    const fd = hold(home, false);
    try { return source(fd); } finally { fs.closeSync(fd); }
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

function directory(home, entry) {
    const child = Core.anchored().child;
    let fd = hold(home, false);
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
// empty. A list is a one-line flow list or block items on the lines below
// its key; any other value of those keys throws home=declaration.
function dependencies(text) {
    const lines = text.split("\n");
    const end = lines.findIndex((line, index) => index > 0 && line.trim() === "---");
    if (lines[0].trim() !== "---" || end === -1) fail("declaration");
    const found = Object.fromEntries(DEPENDENCY_LISTS.map(key => [key, []]));
    let inside = false;
    let keyIndent = null;
    let open = null;
    for (const line of lines.slice(1, end)) {
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

// The BUNDLE_LISTS arrays of the [bundles.<PACKAGE>] table of CATALOG, the
// kendex catalog's kendex.toml text, as {skills, agents, hooks}: each list
// empty where the catalog has no such table or the table no such key. An
// array may span lines; any other value of those keys throws home=declaration.
function bundle(catalog) {
    const found = Object.fromEntries(BUNDLE_LISTS.map(key => [key, []]));
    const lines = catalog.split("\n");
    const start = lines.findIndex(line => line.trim() === "[bundles." + PACKAGE + "]");
    if (start === -1) return found;
    const rest = lines.slice(start + 1);
    const end = rest.findIndex(line => TABLE_HEADER.test(line.trim()));
    // A comment never holds a name; the table's other values are not read.
    const table = rest.slice(0, end === -1 ? rest.length : end).map(line => line.replace(/\s#.*$|^#.*$/, "")).join("\n");
    for (const key of BUNDLE_LISTS) {
        const assigned = table.match(new RegExp("^\\s*" + key + "\\s*=", "gm")) ?? [];
        const arrays = [...table.matchAll(new RegExp("^\\s*" + key + "\\s*=\\s*\\[([^\\]]*)\\]", "gm"))];
        if (assigned.length > 1 || arrays.length !== assigned.length) fail("declaration");
        for (const [, items] of arrays) {
            const entries = items.split(",").map(item => item.trim()).filter(item => item !== "");
            if (entries.some(item => !/^"[^"]*"$/.test(item))) fail("declaration");
            found[key].push(...declaredNames(entries));
        }
    }
    return found;
}

/**
 * What the base package declares beside its own files, read from kendex's
 * own manifests at the shipped revision, never from a list kept in VGS:
 * SKILL, the package's SKILL.md text, names skills in its front matter's
 * dependencies.required and agents in dependencies.agents; CATALOG, the
 * kendex catalog's kendex.toml text, or null where none ships, adds the
 * skills, agents and hooks of its [bundles.<PACKAGE>] table.
 * {skills, agents, hooks}, each sorted, once, and without PACKAGE. Throws
 * jarvis: home=declaration for a list in another form or a name that is no
 * plain name.
 */
function declaration(skill, catalog) {
    const front = dependencies(skill);
    const bundled = catalog === null ? bundle("") : bundle(catalog);
    const set = (...lists) => [...new Set(lists.flat())].filter(name => name !== PACKAGE).sort();
    return { skills: set(front.required, bundled.skills), agents: set(front.agents, bundled.agents), hooks: set(bundled.hooks) };
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
 * A skill is `<name>.md` or `<name>/SKILL.md` directly in the base set
 * (baseSet, holding the package alone) or
 * skills/own, a regular file under a name Tools.homeTopic admits; a folder
 * skill's `references/<reference>.md` is a skill of its own under
 * "<set>/<name>/<reference>", and its `workflows/<workflow>.md` one under
 * "<set>/<name>/workflows/<workflow>". Any other entry, a link among them, is no
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
    const base = baseSet(home);
    for (const set of SETS) {
        const folder = set === "base" ? base : "skills/" + set;
        let listed = listing(home, folder);
        if (folder === RENDER) listed = { entries: listed.entries.filter(entry => entry.name === PACKAGE), complete: listed.complete };
        flat(folder, set + "/", listed);
        for (const entry of listed.entries) {
            const topic = set + "/" + entry.name;
            if (Tools.homeTopic(topic) === null) continue;
            // An entry that is no folder, a folder without SKILL.md, or one with a
            // link in its place, is no skill.
            const skill = indexed(home, topic, folder + "/" + entry.name + "/SKILL.md", true);
            if (skill === null) continue;
            found.push(skill);
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
                flat(inner, prefix, inside);
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
 * not hold.
 */
function skill(home, topic) {
    const named = Tools.homeTopic(topic);
    if (named === null) fail("absent");
    const set = named.set === "base" ? baseSet(home) : "skills/" + named.set;
    if (set === RENDER && named.name !== PACKAGE) fail("absent");
    const base = set + "/" + named.name;
    const whole = file => read(home, file, null).text;
    if (named.file !== null) return whole(base + "/" + named.folder + "/" + named.file + ".md");
    // The render's set holds the package's folder alone, never a flat file.
    if (set !== RENDER) {
        try { return whole(base + ".md"); }
        catch (error) { if (error.message !== "jarvis: home=absent") throw error; }
    }
    return whole(base + "/SKILL.md");
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

// Only absence permits cutover. A refused canonical entry must never turn
// an executable refusal into permission to install over the home.
function mailCutover(home) {
    if (mailTool(home) !== null) return "ready";
    const fd = hold(home, false);
    try {
        const entry = name => along(fd, name.split("/").slice(0, -1), false, chain =>
            chain === null ? "absent" : kindOf(chain[chain.length - 1], path.basename(name)));
        if (!["absent", "file", "directory"].includes(kindOf(fd, OWN_REPOSITORY))) return "refused";
        if (entry(MAIL_TOOL) !== "absent") return "refused";
        const old = MAIL_TOOL.replace("/mailbox/", "/orch/");
        return entry(old) === "file" ? "eligible" : "ineligible";
    } finally { fs.closeSync(fd); }
}

// The consumed record is outside model-writable state and outside the package
// release record. A partial record consumes the attempt too, by refusing it.
function consumeMailCutover(home) {
    const fd = hold(home, false);
    const name = ".vgs-mailbox-cutover.json";
    try {
        const kind = kindOf(fd, name);
        if (kind !== "absent") {
            if (kind !== "file") fail("cutover-record");
            const record = fs.openSync(Core.anchored().child(fd, name), O_RDONLY | O_NONBLOCK | O_NOFOLLOW);
            try {
                const content = bytes(record, 128);
                if (content.toString("utf8") !== '{"consumed":true}\n') fail("cutover-record");
            } finally { fs.closeSync(record); }
            return false;
        }
        const record = fs.openSync(Core.anchored().child(fd, name), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600);
        try {
            fs.writeFileSync(record, '{"consumed":true}\n');
            fs.fsyncSync(record);
        } finally { fs.closeSync(record); }
        fs.fsyncSync(fd);
        return true;
    } catch (error) {
        if (/^jarvis: home=/.test(error.message)) throw error;
        fail("cutover-record");
    } finally {
        try { fs.closeSync(fd); } catch { fail("cutover-record"); }
    }
}

/**
 * The absolute path of the home's Jarvis session command, SESSION_COMMAND
 * reached through no link and a regular file with its owner's execute bit;
 * else null, as while the home cannot be read. The shell runs it by this
 * path, never a brain: it starts and stops the user's own Jarvis session
 * (D105).
 */
function sessionCommand(home) {
    return held(home, SESSION_COMMAND, O_RDONLY | O_NONBLOCK, fd => {
        const found = fs.fstatSync(fd);
        const runs = found.isFile() && (found.mode & fs.constants.S_IXUSR) !== 0;
        return runs ? path.join(home, SESSION_COMMAND) : null;
    });
}

/** Whether the home holds the Jarvis session's mailbox folder, no link on the way. */
function mailbox(home) {
    return held(home, MAILBOX, O_RDONLY | O_DIRECTORY, () => true) === true;
}

module.exports = { PACKAGE, resolve, relativeHome, remembered, remember, offers, layout, release, packageOwner, repairResult, guard, baseSet, read, declaration, skills, skill, note, notes, mailTool, mailCutover, consumeMailCutover, mailbox, sessionCommand, directory };
