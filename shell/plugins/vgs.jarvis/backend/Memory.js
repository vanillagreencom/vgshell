// One disposable search index for the user's home memory notes. The index is
// private daemon state, not home data: deleting it only loses a cache.
"use strict";
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const Home = require("./Home.js");
const Policy = require("./Policy.js");
const Private = require("./Private.js");

const VERSION = 1;
const LIMIT = 8;
const SOURCES = new Set(Policy.SOURCES);

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

function install({ router, directory, home, sqlite = () => require("node:sqlite"), log = () => {} }) {
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
            sources: parseJson(row.labels, ["home"]), snippet: row.snippet };
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
                const resolved = indexedNotes().filter(note => note.id !== id).concat([{ id, title: parsed.title, aliases: parsed.aliases, rawLinks: parsed.rawLinks }]);
                resolveLinks(resolved);
                const links = resolved.find(note => note.id === id)?.links ?? [];
                readAny = true;
                labelRows.push({ labels: json(parsed.labels) });
                notes.push({ id, title: parsed.title, ...(parsed.date === null ? {} : { date: parsed.date }),
                    sources: parsed.labels, links, backlinks: statements.backlinks.all(id).map(link => link.source), text: parsed.text });
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
        start(call, done) {
            if (closed) { failCall(call.id === "memory.search" ? "memory-search:" : "memory-read:", "closed", done); return; }
            if (call.id === "memory.search") search(call.args, done);
            else if (call.id === "memory.read") read(call.args, done);
            else failCall("memory-search:", "tool", done);
        } });
    router.register("memory", executor);
    return { kind: "installed",
        reconcileStart() {
            try { reconcile({ full: true }); return true; }
            catch (error) { logCause(homeCause(error) === null ? "index" : "home-" + homeCause(error)); return false; }
        },
        close() { closed = true; closeDb(); } };
}

module.exports = { install };
