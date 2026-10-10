// One disposable search index for the user's home memory notes. The index is
// private daemon state, not home data: deleting it only loses a cache.
"use strict";
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const Core = require("./Core.js");
const Home = require("./Home.js");
const Policy = require("./Policy.js");
const Private = require("./Private.js");
const Redact = require("./Redact.js");
const Tools = require("./Tools.js");

const VERSION = 1;
const LIMIT = 8;
const SOURCES = new Set(Policy.SOURCES);
const TEXT_BYTES = 16 * 1024;
const { O_RDONLY, O_WRONLY, O_CREAT, O_EXCL, O_DIRECTORY, O_NOFOLLOW, O_NONBLOCK } = fs.constants;

function json(value) { return JSON.stringify(value); }
function parseJson(value, fallback) {
    try { return JSON.parse(value); } catch { return fallback; }
}
function statKey(row) { return [row.size, row.mtimeNs, row.ctimeNs, row.ino].map(String).join(":"); }
function hashText(text) { return crypto.createHash("sha256").update(text).digest("hex"); }
function homeCause(error) { return /^jarvis: home=([a-z-]+)$/.exec(error.message)?.[1] ?? null; }
function sqliteBroken(error) { return ["SQLITE_CORRUPT", "SQLITE_NOTADB"].includes(error?.code) || /corrupt|not a database/i.test(error?.message ?? ""); }
function sourceItem(value) { return value.trim().replace(/^(\"|')(.*)\1$/, "$2"); }
function uniqueLabels(values) { return Policy.labels(values); }
function clipText(text, limit) {
    const bytes = Buffer.from(text);
    if (bytes.length <= limit) return text;
    return new TextDecoder().decode(bytes.subarray(0, limit), { stream: true });
}
function printable(text, fallback = "") {
    const value = String(text ?? "").replace(/[\x00-\x1f\x7f]/g, " ").trim();
    return value === "" ? fallback : value;
}

function listValue(value) {
    if (Array.isArray(value)) return value.map(item => sourceItem(String(item))).filter(Boolean);
    const text = String(value).trim();
    if (text === "") return [];
    if (text.startsWith("[")) {
        if (!text.endsWith("]")) return null;
        return text.slice(1, -1).split(",").map(sourceItem).filter(Boolean);
    }
    return text.split(",").map(sourceItem).filter(Boolean);
}

function sourceList(value) {
    if (value === undefined) return [];
    const parsed = listValue(value);
    if (parsed === null) return ["file"];
    return parsed.map(source => SOURCES.has(source) ? source : "file");
}

function parseFrontMatter(text) {
    const normalized = text.replace(/\r\n/g, "\n");
    const meta = {};
    if (!normalized.startsWith("---\n")) return { meta, body: normalized };
    const end = normalized.indexOf("\n---", 4);
    if (end < 0) return { meta, body: normalized };
    const lines = normalized.slice(4, end).split("\n");
    for (let i = 0; i < lines.length; i++) {
        const match = /^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$/.exec(lines[i]);
        if (match === null) continue;
        if (match[2] === "" && i + 1 < lines.length && /^\s*-\s+/.test(lines[i + 1])) {
            const list = [];
            while (i + 1 < lines.length && /^\s*-\s+/.test(lines[i + 1]))
                list.push(sourceItem(lines[++i].replace(/^\s*-\s+/, "")));
            meta[match[1]] = list;
        } else meta[match[1]] = match[2].trim().replace(/^(\"|')(.*)\1$/, "$2");
    }

    return { meta, body: normalized.slice(end + 4).replace(/^\n/, "") };
}

function formatSources(labels) {
    const sources = uniqueLabels(["home", ...labels.filter(label => label !== "home")]).filter(label => label !== "home");
    if (sources.length === 0) return "";
    return "sources:\n" + sources.map(label => "  - " + label).join("\n") + "\n";
}

function withSources(text, labels) {
    const normalized = text.replace(/\r\n/g, "\n");
    const sources = formatSources(labels);
    if (sources === "") return normalized;
    if (!normalized.startsWith("---\n")) return "---\n" + sources + "---\n" + normalized;
    const end = normalized.indexOf("\n---", 4);
    if (end < 0) return "---\n" + sources + "---\n" + normalized;
    const lines = normalized.slice(4, end).split("\n");
    const kept = [];
    for (let i = 0; i < lines.length; i++) {
        if (/^sources:\s*/.test(lines[i])) {
            while (i + 1 < lines.length && /^\s*-\s+/.test(lines[i + 1])) i++;
            continue;
        }
        kept.push(lines[i]);
    }
    const meta = kept.filter(line => line.trim() !== "").join("\n");
    return "---\n" + (meta === "" ? "" : meta + "\n") + sources + "---" + normalized.slice(end + 4);
}

function parseNote(id, text) {
    const normalized = text.replace(/\r\n/g, "\n");
    const { meta, body } = parseFrontMatter(normalized);
    const heading = /^#\s+(.+)$/m.exec(body);
    const stem = path.basename(id, ".md");
    const aliases = Array.isArray(meta.aliases) ? meta.aliases : listValue(meta.aliases);
    const title = typeof meta.title === "string" && meta.title !== "" ? meta.title
        : heading === null ? stem : heading[1].trim();
    const date = typeof meta.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(meta.date) ? meta.date : null;
    const recorded = sourceList(meta.sources);
    const labels = uniqueLabels(["home", ...recorded]);
    const rawLinks = [];
    for (const match of normalized.matchAll(/\[\[([^\]\|\#]+)(?:#[^\]\|]+)?(?:\|[^\]]*)?\]\]/g))
        rawLinks.push(match[1].trim());
    return { id, title, aliases: aliases === null ? [] : aliases, date, labels, rawLinks, text: normalized };
}

function resolveLinks(notes) {
    const byId = new Map(notes.map(note => [note.id, note]));
    const title = new Map(), alias = new Map(), stem = new Map();
    function add(map, key, id) {
        const lower = key.toLowerCase();
        map.set(lower, map.has(lower) ? null : id);
    }
    for (const note of notes) {
        add(title, note.title, note.id);
        for (const name of note.aliases) add(alias, name, note.id);
        add(stem, path.basename(note.id, ".md"), note.id);
    }
    for (const note of notes) {
        const links = [];
        for (const raw of note.rawLinks) {
            const direct = byId.has(raw) ? raw : byId.has(raw + ".md") ? raw + ".md"
                : title.get(raw.toLowerCase()) ?? alias.get(raw.toLowerCase()) ?? stem.get(raw.toLowerCase()) ?? null;
            if (direct !== null && direct !== undefined && !links.includes(direct)) links.push(direct);
        }
        note.links = links;
    }
}

function install({ router, directory, home, sqlite = () => require("node:sqlite"), log = () => {}, notify = () => {} }) {
    let DatabaseSync;
    try {
        // node:sqlite is unflagged from Node 22.13. This machine runs
        // /usr/bin/node 26.10.0 from nodejs 26.10.0-3, where DatabaseSync
        // opens and FTS5 works, read 2026-10-09.
        ({ DatabaseSync } = sqlite());
        const probe = new DatabaseSync(":memory:");
        try {
            probe.exec("CREATE VIRTUAL TABLE p USING fts5(x, tokenize='unicode61 remove_diacritics 2')");
            probe.prepare("SELECT value FROM json_each(?)").all("[1]");
        } finally { probe.close(); }
    } catch {
        return { kind: "refused", cause: "memory=sqlite" };
    }

    Private.directory(directory);
    const file = path.join(directory, "memory.sqlite");
    let db = null, closed = false;
    const badNotes = new Map();
    const searchSql = new Map();
    let statements = null;
    const stateRoot = path.dirname(directory);
    const receipts = path.join(stateRoot, "memory-receipts");

    function deleteIndex() {
        for (const suffix of ["", "-wal", "-shm"]) fs.rmSync(file + suffix, { force: true });
    }

    function closeDb() {
        const database = db;
        db = null;
        statements = null;
        searchSql.clear();
        if (database !== null) database.close();
    }

    function withIndexError(action) {
        try { return action(); }
        catch (error) {
            if (sqliteBroken(error)) {
                closeDb();
                deleteIndex();
            }
            throw error;
        }
    }

    function open() {
        if (db !== null) return db;
        try { db = openOnce(false); }
        catch {
            try { closeDb(); deleteIndex(); db = openOnce(true); }
            catch { throw new Error("index"); }
        }
        statements = prepare(db);
        return db;
    }

    function openOnce(fresh) {
        const database = new DatabaseSync(file);
        try {
            database.exec("PRAGMA journal_mode=DELETE");
            const version = database.prepare("PRAGMA user_version").get().user_version;
            if (!fresh && version !== 0 && version !== VERSION) throw new Error("version");
            database.exec([
                "CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)",
                "CREATE TABLE IF NOT EXISTS notes(id TEXT PRIMARY KEY, hash TEXT NOT NULL, stat TEXT NOT NULL, title TEXT NOT NULL, aliases TEXT NOT NULL, date TEXT, labels TEXT NOT NULL, links TEXT NOT NULL, rawLinks TEXT NOT NULL)",
                "CREATE VIRTUAL TABLE IF NOT EXISTS body USING fts5(id UNINDEXED, title, aliases, text, tokenize='unicode61 remove_diacritics 2')",
                "CREATE TABLE IF NOT EXISTS links(source TEXT NOT NULL, target TEXT NOT NULL, PRIMARY KEY(source,target))",
                "CREATE INDEX IF NOT EXISTS links_target ON links(target)",
                "PRAGMA user_version = " + VERSION
            ].join(";"));
            return database;
        } catch (error) {
            database.close();
            throw error;
        }
    }

    function prepare(database) {
        return {
            home: database.prepare("SELECT value FROM meta WHERE key='home'"),
            setHome: database.prepare("INSERT OR REPLACE INTO meta(key,value) VALUES('home',?)"),
            rows: database.prepare("SELECT rowid,id,hash,stat,title,aliases,date,labels,links,rawLinks FROM notes"),
            row: database.prepare("SELECT rowid,id,hash,stat,title,aliases,date,labels,links,rawLinks FROM notes WHERE id=?"),
            deleteNote: database.prepare("DELETE FROM notes WHERE id=?"),
            deleteBody: database.prepare("DELETE FROM body WHERE rowid=?"),
            upsertNote: database.prepare("INSERT OR REPLACE INTO notes(id,hash,stat,title,aliases,date,labels,links,rawLinks) VALUES(?,?,?,?,?,?,?,?,?)"),
            updateStat: database.prepare("UPDATE notes SET stat=? WHERE id=?"),
            updateLinks: database.prepare("UPDATE notes SET links=? WHERE id=?"),
            insertBody: database.prepare("INSERT INTO body(rowid,id,title,aliases,text) VALUES(?,?,?,?,?)"),
            clearBody: database.prepare("DELETE FROM body"),
            clearNotes: database.prepare("DELETE FROM notes"),
            clearMeta: database.prepare("DELETE FROM meta"),
            clearLinks: database.prepare("DELETE FROM links"),
            insertLink: database.prepare("INSERT OR IGNORE INTO links(source,target) VALUES(?,?)"),
            backlinks: database.prepare("SELECT source FROM links WHERE target=? ORDER BY source"),
            labels: database.prepare("SELECT labels FROM notes WHERE id=?")
        };
    }

    function clearAll() {
        statements.clearBody.run();
        statements.clearLinks.run();
        statements.clearNotes.run();
        statements.clearMeta.run();
    }

    function logCause(cause) { log("jarvis: memory=" + cause); }
    function noteFailure(id, cause, stat) {
        const key = cause + ":" + stat;
        if (badNotes.get(id) !== key) {
            badNotes.set(id, key);
            logCause("note-" + cause + " id=" + id);
        }
    }
    function failCall(prefix, cause, done) {
        logCause(cause);
        done({ outcome: "failed", content: prefix + cause, labels: ["home"] });
    }

    function failMemory(prefix, cause, done) {
        logCause(cause);
        done({ outcome: "failed", content: prefix + cause });
    }

    function entryKind(parent, name) {
        let stat;
        try { stat = fs.lstatSync(Core.anchored().child(parent, name)); }
        catch (error) {
            if (error.code === "ENOENT") return "absent";
            throw error;
        }
        return stat.isSymbolicLink() ? "link" : stat.isDirectory() ? "directory" : stat.isFile() ? "file" : "other";
    }

    function openMemory() {
        const folder = home();
        if (folder === null) throw new Error("jarvis: memory=home");
        try { return Home.directory(folder, "memory"); }
        catch (error) {
            const cause = homeCause(error);
            if (cause === "link") throw new Error("jarvis: memory=link");
            if (cause !== null) throw new Error("jarvis: memory=" + cause);
            throw error;
        }
    }

    function withParent(id, create, act) {
        const parts = id.split("/");
        const name = parts.pop();
        let fd = openMemory();
        try {
            for (const part of parts) {
                if (part === "" || part.startsWith(".")) throw new Error("jarvis: memory=path");
                const kind = entryKind(fd, part);
                if (kind === "link") throw new Error("jarvis: memory=link");
                if (kind === "absent") {
                    if (!create) throw new Error("jarvis: memory=absent");
                    fs.mkdirSync(Core.anchored().child(fd, part));
                } else if (kind !== "directory") throw new Error("jarvis: memory=kind");
                const next = fs.openSync(Core.anchored().child(fd, part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
                fs.closeSync(fd);
                fd = next;
            }
            return act(fd, name);
        } finally { fs.closeSync(fd); }
    }

    function readNote(id) {
        return withParent(id, false, (parent, name) => {
            const kind = entryKind(parent, name);
            if (kind === "absent") throw new Error("jarvis: memory=absent");
            if (kind === "link") throw new Error("jarvis: memory=link");
            if (kind !== "file") throw new Error("jarvis: memory=kind");
            const fd = fs.openSync(Core.anchored().child(parent, name), O_RDONLY | O_NONBLOCK | O_NOFOLLOW);
            try { return fs.readFileSync(fd, "utf8"); }
            finally { fs.closeSync(fd); }
        });
    }

    function atomicWrite(parent, name, text, { replace }) {
        if (entryKind(parent, name) === "link") throw new Error("jarvis: memory=link");
        const scratch = "." + name + "." + process.pid + "." + crypto.randomUUID() + ".new";
        const scratchPath = Core.anchored().child(parent, scratch);
        const fd = fs.openSync(scratchPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600);
        try {
            fs.writeFileSync(fd, text);
            fs.fsyncSync(fd);
            const target = Core.anchored().child(parent, name);
            if (replace) fs.renameSync(scratchPath, target);
            else fs.linkSync(scratchPath, target);
            fs.fsyncSync(parent);
        } finally { fs.closeSync(fd); }
        try { fs.unlinkSync(scratchPath); }
        catch (error) { if (error.code !== "ENOENT") throw error; }
    }

    function receiptName(id) {
        return hashText(id) + ".json";
    }

    function writeReceipt(id, record) {
        Private.directory(stateRoot);
        Private.directory(receipts);
        const name = receiptName(id);
        const scratch = path.join(receipts, "." + name + "." + process.pid + "." + crypto.randomUUID());
        const body = JSON.stringify({ v: 1, ...record }, null, 2) + "\n";
        const fd = fs.openSync(scratch, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600);
        let owned = true;
        try {
            fs.writeFileSync(fd, body);
            fs.fsyncSync(fd);
            fs.renameSync(scratch, path.join(receipts, name));
            owned = false;
        } finally { fs.closeSync(fd); }
        if (owned) {
            try { fs.unlinkSync(scratch); }
            catch (error) { if (error.code !== "ENOENT") throw error; }
        }
        const dir = fs.openSync(receipts, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
        try { fs.fsyncSync(dir); } finally { fs.closeSync(dir); }
    }

    function readReceipt(id) {
        try {
            const file = path.join(receipts, receiptName(id));
            const fd = fs.openSync(file, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
            try { return JSON.parse(fs.readFileSync(fd, "utf8")); }
            finally { fs.closeSync(fd); }
        } catch { return null; }
    }

    function removeReceipt(id) {
        try { fs.unlinkSync(path.join(receipts, receiptName(id))); }
        catch (error) { if (error.code !== "ENOENT") throw error; }
    }

    function edited(id, text) {
        const record = readReceipt(id);
        return record !== null && record.note === id && record.approvedHash !== hashText(text);
    }

    function receiptRecord(id, labels, proposedText, writtenText, extra = {}) {
        return { note: id, labels: uniqueLabels(labels), sourceHash: hashText(proposedText),
            time: new Date().toISOString(), approvedHash: hashText(writtenText), ...extra };
    }

    function pendingEntries() {
        try {
            return withParent("inbox/pending.json", true, parent => {
                const entries = [];
                for (const name of fs.readdirSync("/proc/self/fd/" + parent).sort()) {
                    if (!/^[0-9a-f-]{36}\.json$/.test(name)) continue;
                    try {
                        const kind = entryKind(parent, name);
                        if (kind !== "file") continue;
                        const text = fs.readFileSync(Core.anchored().child(parent, name), "utf8");
                        const record = JSON.parse(text);
                        if (record.v !== 1 || record.id !== name.slice(0, -5) || !Tools.memoryNote(record.target)
                                || !["propose", "replace"].includes(record.kind) || typeof record.text !== "string") continue;
                        const labels = Policy.labels(record.labels);
                        const title = clipText(printable(parseNote(record.target, record.text).title, path.basename(record.target, ".md")), 128);
                        entries.push({ id: record.id, target: record.target, kind: record.kind, title, labels,
                            text: clipText(record.text.replace(/\u0000/g, ""), TEXT_BYTES),
                            hash: hashText(text), problem: printable(record.problem, ""), time: record.time ?? "" });
                    } catch { /* one bad inbox file must not hide the others */ }
                }
                return entries.sort((left, right) => left.time < right.time ? -1 : left.time > right.time ? 1 : 0)
                    .map(entry => {
                        const { time: _time, ...wire } = entry;
                        return wire;
                    });
            });
        } catch { return []; }
    }

    function publishInbox() {
        try { notify(pendingEntries()); }
        catch (error) { logCause("inbox-publish"); }
    }

    function inboxRecord(kind, target, text, labels, expectedHash) {
        const id = crypto.randomUUID();
        return { v: 1, id, kind, target, text, labels: uniqueLabels(labels), sourceHash: hashText(text),
            time: new Date().toISOString(), problem: "", ...(expectedHash === undefined ? {} : { expectedHash }) };
    }

    function writeInbox(record) {
        return withParent("inbox/" + record.id + ".json", true, (parent, name) => {
            const body = JSON.stringify(record, null, 2) + "\n";
            atomicWrite(parent, name, body, { replace: false });
            writeReceipt("inbox/" + record.id, { note: record.target, inbox: record.id, kind: record.kind,
                labels: record.labels, sourceHash: record.sourceHash, time: record.time,
                approvedHash: hashText(body), ...(record.expectedHash === undefined ? {} : { expectedHash: record.expectedHash }) });
            return record;
        });
    }

    function removeInbox(id) {
        return withParent("inbox/" + id + ".json", false, (parent, name) => {
            fs.unlinkSync(Core.anchored().child(parent, name));
            fs.fsyncSync(parent);
        });
    }

    function readInbox(id) {
        if (typeof id !== "string" || !/^[0-9a-f-]{36}$/.test(id)) throw new Error("jarvis: memory=inbox-id");
        return withParent("inbox/" + id + ".json", false, (parent, name) => {
            const kind = entryKind(parent, name);
            if (kind === "link") throw new Error("jarvis: memory=link");
            if (kind !== "file") throw new Error("jarvis: memory=absent");
            const text = fs.readFileSync(Core.anchored().child(parent, name), "utf8");
            const record = JSON.parse(text);
            return { text, hash: hashText(text), record };
        });
    }

    function setInboxProblem(id, problem) {
        return withParent("inbox/" + id + ".json", false, (parent, name) => {
            const kind = entryKind(parent, name);
            if (kind !== "file") throw new Error("jarvis: memory=absent");
            const text = fs.readFileSync(Core.anchored().child(parent, name), "utf8");
            const record = JSON.parse(text);
            record.problem = problem;
            atomicWrite(parent, name, JSON.stringify(record, null, 2) + "\n", { replace: true });
        });
    }

    function writeNote(id, text, labels, expectedHash, replace) {
        if (id === "MEMORY.md") throw new Error("jarvis: memory=bootstrap");
        if (Buffer.byteLength(text) > TEXT_BYTES) throw new Error("jarvis: memory=size");
        if (Redact.secret(id) || Redact.secret(text)) {
            throw new Error("jarvis: memory=secret");
        }
        const currentKind = withParent(id, true, (parent, name) => entryKind(parent, name));
        if (!replace && currentKind !== "absent") throw new Error(currentKind === "link" ? "jarvis: memory=link" : "jarvis: memory=exists");
        let writeLabels = labels;
        if (replace) {
            const current = readNote(id);
            if (hashText(current) !== expectedHash) throw new Error("jarvis: memory=conflict");
            writeLabels = uniqueLabels([...parseNote(id, current).labels, ...labels]);
        }
        const written = withSources(text, writeLabels);
        withParent(id, true, (parent, name) => atomicWrite(parent, name, written, { replace }));
        writeReceipt(id, receiptRecord(id, writeLabels, text, written, replace ? { expectedHash } : {}));
        return written;
    }

    function checkWrite(id, text, labels, expectedHash, replace) {
        if (id === "MEMORY.md") {
            throw new Error("jarvis: memory=bootstrap");
        }
        if (Buffer.byteLength(text) > TEXT_BYTES) throw new Error("jarvis: memory=size");
        if (Redact.secret(id) || Redact.secret(text)) throw new Error("jarvis: memory=secret");
        const currentKind = withParent(id, true, (parent, name) => entryKind(parent, name));
        if (!replace && currentKind !== "absent") throw new Error(currentKind === "link" ? "jarvis: memory=link" : "jarvis: memory=exists");
        if (replace) {
            const current = readNote(id);
            if (hashText(current) !== expectedHash) {
                throw new Error("jarvis: memory=conflict");
            }
        }
        return labels;
    }

    function writeOrInbox(kind, args, origin, done) {
        const prefix = kind === "replace" ? "memory-replace:" : "memory-propose:";
        const labels = origin?.labels ?? ["home"];
        try {
            checkWrite(args.id, args.text, labels, args.hash, kind === "replace");
            if (origin?.tainted === true) {
                writeInbox(inboxRecord(kind, args.id, args.text, labels, args.hash));
                publishInbox();
                done({ outcome: "completed", content: JSON.stringify({ status: "pending", id: args.id, kind }) });
                return;
            }
            writeNote(args.id, args.text, labels, args.hash, kind === "replace");
            publishInbox();
            done({ outcome: "completed", content: JSON.stringify({ status: "written", id: args.id, kind }) });
        } catch (error) {
            const cause = /^jarvis: memory=([a-z-]+)$/.exec(error.message)?.[1] ?? "write";
            failMemory(prefix, cause, done);
        }
    }

    function confirm(id, hash) {
        const entry = readInbox(id);
        if (entry.hash !== hash) {
            setInboxProblem(id, "hash");
            throw new Error("jarvis: memory=hash");
        }
        const record = entry.record;
        try { writeNote(record.target, record.text, record.labels, record.expectedHash, record.kind === "replace"); }
        catch (error) {
            const cause = /^jarvis: memory=([a-z-]+)$/.exec(error.message)?.[1] ?? "write";
            const problem = ["exists", "conflict", "link", "secret", "hash", "bootstrap"].includes(cause) ? cause : "write";
            setInboxProblem(id, problem);
            throw error;
        }
        removeInbox(id);
        removeReceipt("inbox/" + id);
        publishInbox();
        return { kind: "confirmed", target: record.target };
    }

    function discard(id, hash) {
        const entry = readInbox(id);
        if (entry.hash !== hash) throw new Error("jarvis: memory=hash");
        removeInbox(id);
        removeReceipt("inbox/" + id);
        publishInbox();
        return { kind: "discarded", target: entry.record.target };
    }

    function loadText(folder, row) {
        try {
            const text = Home.note(folder, row.id);
            badNotes.delete(row.id);
            return { kind: "note", text, hash: hashText(text), parsed: parseNote(row.id, text), stat: statKey(row) };
        } catch (error) {
            const cause = homeCause(error) ?? "unreadable";
            noteFailure(row.id, cause, statKey(row));
            return { kind: "bad", cause, stat: statKey(row) };
        }
    }

    function reconcile(options = {}) {
        const folder = home();
        if (folder === null) return;
        const database = open();
        return withIndexError(() => {
            const priorHome = statements.home.get()?.value ?? null;
            const homeChanged = priorHome !== folder;
            const rows = Home.notes(folder);
            const knownRows = homeChanged ? [] : statements.rows.all();
            const known = new Map(knownRows.map(row => [row.id, row]));
            const listed = new Map(rows.map(row => [row.id, row]));
            const removed = knownRows.filter(row => !listed.has(row.id));
            const loaded = [];
            const statOnly = [];
            let changedLinks = homeChanged || removed.length > 0;
            for (const row of rows) {
                const prior = known.get(row.id);
                const stat = statKey(row);
                if (!homeChanged && prior !== undefined && prior.stat === stat && options.full !== true) continue;
                const read = loadText(folder, row);
                if (read.kind === "bad") { loaded.push({ id: row.id, bad: true }); changedLinks = true; continue; }
                if (!homeChanged && prior !== undefined && prior.hash === read.hash) { statOnly.push({ id: row.id, stat }); continue; }
                loaded.push({ ...read.parsed, hash: read.hash, stat, changed: true });
                changedLinks = true;
            }
            if (!homeChanged && removed.length === 0 && loaded.length === 0 && statOnly.length === 0) return;
            database.exec("BEGIN IMMEDIATE");
            let active = true;
            try {
                if (homeChanged) clearAll();
                for (const row of removed) {
                    statements.deleteBody.run(row.rowid);
                    statements.deleteNote.run(row.id);
                }
                for (const item of loaded) {
                    const prior = known.get(item.id);
                    if (prior !== undefined) statements.deleteBody.run(prior.rowid);
                    statements.deleteNote.run(item.id);
                    if (item.bad) continue;
                    statements.upsertNote.run(item.id, item.hash, item.stat, item.title, json(item.aliases), item.date,
                        json(item.labels), json([]), json(item.rawLinks));
                    const rowid = statements.row.get(item.id).rowid;
                    statements.insertBody.run(rowid, item.id, item.title, item.aliases.join(" "), item.text);
                }
                for (const item of statOnly) statements.updateStat.run(item.stat, item.id);
                if (changedLinks) rewriteLinks();
                statements.setHome.run(folder);
                database.exec("COMMIT");
                active = false;
            } catch (error) {
                if (active && database.isTransaction) database.exec("ROLLBACK");
                throw error;
            }
        });
    }

    function rewriteLinks() {
        const notes = statements.rows.all().map(row => ({ id: row.id, title: row.title,
            aliases: parseJson(row.aliases, []), rawLinks: parseJson(row.rawLinks, []) }));
        resolveLinks(notes);
        statements.clearLinks.run();
        for (const note of notes) {
            statements.updateLinks.run(json(note.links), note.id);
            for (const target of note.links) statements.insertLink.run(note.id, target);
        }
    }

    function reconcileFor(prefix, done, options = {}) {
        try { reconcile(options); return open(); }
        catch (error) {
            if (sqliteBroken(error)) {
                try { reconcile(options); return open(); }
                catch (again) { error = again; }
            }
            const cause = homeCause(error);
            if (cause !== null) failCall(prefix, "home-" + cause, done);
            else failCall(prefix, "index", done);
            return null;
        }
    }

    function matchQuery(query) {
        const tokens = [...query.matchAll(/[\p{L}\p{N}_-]+/gu)].map(match => match[0]);
        if (tokens.length === 0) return null;
        return tokens.map(token => "\"" + token.replaceAll("\"", "\"\"") + "\"").join(" OR ");
    }

    function labelsOf(rows) { return uniqueLabels(rows.flatMap(row => parseJson(row.labels, ["home"]))); }
    function rowObject(row) {
        return { id: row.id, title: row.title, ...(row.date === null ? {} : { date: row.date }),
            sources: parseJson(row.labels, ["home"]), snippet: row.snippet,
            ...(readReceipt(row.id) === null ? {} : { edited: readReceipt(row.id)?.approvedHash !== row.hash }) };
    }

    function searchStatement(args) {
        const mask = (args.title === undefined ? 0 : 1) | (args.alias === undefined ? 0 : 2)
            | (args.since === undefined ? 0 : 4) | (args.until === undefined ? 0 : 8);
        let statement = searchSql.get(mask);
        if (statement !== undefined) return statement;
        const where = ["body MATCH ?"];
        if (args.title !== undefined) where.push("instr(lower(notes.title), lower(?)) > 0");
        if (args.alias !== undefined) where.push("EXISTS (SELECT 1 FROM json_each(notes.aliases) WHERE lower(value)=lower(?))");
        if (args.since !== undefined) where.push("notes.date IS NOT NULL AND notes.date >= ?");
        if (args.until !== undefined) where.push("notes.date IS NOT NULL AND notes.date <= ?");
        statement = open().prepare("SELECT notes.id, notes.title, notes.date, notes.labels, snippet(body, 3, '[', ']', '…', 12) AS snippet FROM body JOIN notes ON notes.rowid=body.rowid WHERE "
            + where.join(" AND ") + " ORDER BY bm25(body, 0, 10, 5, 1) LIMIT ?");
        searchSql.set(mask, statement);
        return statement;
    }

    function search(args, done) {
        const database = reconcileFor("memory-search:", done);
        if (database === null) return;
        const match = matchQuery(args.query);
        if (match === null) { failCall("memory-search:", "query-empty", done); return; }
        let rows;
        const query = () => {
            const params = [match];
            for (const key of ["title", "alias", "since", "until"]) if (args[key] !== undefined) params.push(args[key]);
            params.push(LIMIT);
            return searchStatement(args).all(...params);
        };
        try {
            rows = query();
        } catch (error) {
            if (!sqliteBroken(error)) { failCall("memory-search:", "query", done); return; }
            try { closeDb(); deleteIndex(); reconcile({ full: true }); rows = query(); }
            catch { failCall("memory-search:", "index", done); return; }
        }
        done({ outcome: "completed", content: JSON.stringify({ results: rows.map(rowObject) }),
            labels: rows.length === 0 ? ["home"] : labelsOf(rows) });
    }

    function indexedNotes() {
        return statements.rows.all().map(row => ({ id: row.id, title: row.title,
            aliases: parseJson(row.aliases, []), rawLinks: parseJson(row.rawLinks, []) }));
    }

    function read(args, done, retried = false) {
        const database = reconcileFor("memory-read:", done);
        if (database === null) return;
        let readAny = false;
        const notes = [], labelRows = [];
        try {
            for (const id of args.ids) {
                const row = statements.row.get(id);
                if (row === undefined) { notes.push({ id, error: "absent" }); continue; }
                let text;
                try { text = Home.note(home(), id); }
                catch { notes.push({ id, error: "absent" }); continue; }
                if (text.trim() === "") { notes.push({ id, error: "empty" }); continue; }
                const parsed = parseNote(id, text);
                const currentHash = hashText(text);
                const resolved = indexedNotes().filter(note => note.id !== id).concat([{ id, title: parsed.title, aliases: parsed.aliases, rawLinks: parsed.rawLinks }]);
                resolveLinks(resolved);
                const links = resolved.find(note => note.id === id)?.links ?? [];
                readAny = true;
                labelRows.push({ labels: json(parsed.labels) });
                notes.push({ id, title: parsed.title, ...(parsed.date === null ? {} : { date: parsed.date }),
                    sources: parsed.labels, hash: currentHash, edited: edited(id, text),
                    links, backlinks: statements.backlinks.all(id).map(link => link.source), text: parsed.text });
            }
        } catch (error) {
            if (!sqliteBroken(error) || retried) { failCall("memory-read:", "index", done); return; }
            try { closeDb(); deleteIndex(); reconcile({ full: true }); }
            catch { failCall("memory-read:", "index", done); return; }
            read(args, done, true);
            return;
        }
        done({ outcome: readAny ? "completed" : "failed", content: readAny ? JSON.stringify({ notes }) : "memory-read:absent",
            labels: labelRows.length === 0 ? ["home"] : labelsOf(labelRows) });
    }

    const executor = Object.freeze({ commands: [], timeoutMs: 2000, cancellable: false,
        available: () => home() !== null,
        start(call, done, _authorize, origin) {
            if (closed) {
                const prefix = call.id === "memory.search" ? "memory-search:"
                    : call.id === "memory.read" ? "memory-read:"
                    : call.id === "memory.replace" ? "memory-replace:" : "memory-propose:";
                failCall(prefix, "closed", done); return;
            }
            if (call.id === "memory.search") search(call.args, done);
            else if (call.id === "memory.read") read(call.args, done);
            else if (call.id === "memory.propose") writeOrInbox("propose", call.args, origin, done);
            else if (call.id === "memory.replace") writeOrInbox("replace", call.args, origin, done);
            else failCall("memory-search:", "tool", done);
        } });
    router.register("memory", executor);
    return { kind: "installed",
        reconcileStart() {
            try { reconcile({ full: true }); return true; }
            catch (error) { logCause(homeCause(error) === null ? "index" : "home-" + homeCause(error)); return false; }
        },
        pending: pendingEntries,
        confirm,
        discard,
        close() { closed = true; closeDb(); } };
}

module.exports = { install };
