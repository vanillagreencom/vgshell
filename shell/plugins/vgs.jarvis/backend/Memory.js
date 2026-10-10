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
const SOURCES = new Set(["speech", "desktop", "home", "clipboard", "file", "screen", "web", "command", "agent"]);

function fail(prefix, code, done) {
    done({ outcome: "failed", content: prefix + code, labels: ["home"] });
}

function json(value) { return JSON.stringify(value); }
function parseJson(value, fallback) {
    try { return JSON.parse(value); } catch { return fallback; }
}
function uniqueLabels(values) { return Policy.labels(values); }
function statKey(row) { return [row.size, row.mtimeNs, row.ctimeNs, row.ino].map(String).join(":"); }

function sourceList(value) {
    if (value === undefined) return [];
    const parsed = listValue(value);
    if (parsed === null) return ["file"];
    return parsed.map(source => SOURCES.has(source) ? source : "file");
}

function listValue(value) {
    const text = String(value).trim();
    if (text === "") return [];
    if (text.startsWith("[") && text.endsWith("]"))
        return text.slice(1, -1).split(",").map(item => item.trim()).filter(Boolean);
    return text.split(",").map(item => item.trim()).filter(Boolean);
}

function parseFrontMatter(text) {
    const meta = {};
    if (!text.startsWith("---\n")) return { meta, body: text };
    const end = text.indexOf("\n---", 4);
    if (end < 0) return { meta, body: text };
    const lines = text.slice(4, end).split("\n");
    for (let i = 0; i < lines.length; i++) {
        const match = /^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$/.exec(lines[i]);
        if (match === null) continue;
        if (match[2] === "" && i + 1 < lines.length && /^\s*-\s+/.test(lines[i + 1])) {
            const list = [];
            while (i + 1 < lines.length && /^\s*-\s+/.test(lines[i + 1]))
                list.push(lines[++i].replace(/^\s*-\s+/, "").trim());
            meta[match[1]] = list;
        } else meta[match[1]] = match[2].trim().replace(/^(["'])(.*)\1$/, "$2");
    }
    return { meta, body: text.slice(end + 4).replace(/^\n/, "") };
}

function parseNote(id, text) {
    const { meta, body } = parseFrontMatter(text);
    const heading = /^#\s+(.+)$/m.exec(body);
    const stem = path.basename(id, ".md");
    const aliases = Array.isArray(meta.aliases) ? meta.aliases : listValue(meta.aliases);
    const title = typeof meta.title === "string" && meta.title !== "" ? meta.title
        : heading === null ? stem : heading[1].trim();
    const date = typeof meta.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(meta.date) ? meta.date : null;
    const recorded = sourceList(meta.sources);
    const labels = uniqueLabels(["home", ...recorded]);
    const rawLinks = [];
    for (const match of text.matchAll(/\[\[([^\]\|\#]+)(?:#[^\]\|]+)?(?:\|[^\]]*)?\]\]/g))
        rawLinks.push(match[1].trim());
    return { id, title, aliases: aliases === null ? [] : aliases, date, labels, rawLinks, text };
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
        try { probe.exec("CREATE VIRTUAL TABLE p USING fts5(x)"); }
        finally { probe.close(); }
    } catch {
        return { kind: "refused", cause: "memory=sqlite" };
    }

    Private.directory(directory);
    const file = path.join(directory, "memory.sqlite");
    let db = null, openedHome = null, closed = false;

    function open() {
        if (db !== null) return db;
        try { db = openOnce(false); }
        catch {
            try { fs.rmSync(file, { force: true }); db = openOnce(true); }
            catch { throw new Error("index"); }
        }
        return db;
    }

    function openOnce(fresh) {
        const database = new DatabaseSync(file);
        try {
            database.exec("PRAGMA journal_mode=WAL");
            const version = database.prepare("PRAGMA user_version").get().user_version;
            if (!fresh && version !== 0 && version !== VERSION) throw new Error("version");
            database.exec([
                "CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)",
                "CREATE TABLE IF NOT EXISTS notes(id TEXT PRIMARY KEY, hash TEXT NOT NULL, stat TEXT NOT NULL, title TEXT NOT NULL, aliases TEXT NOT NULL, date TEXT, labels TEXT NOT NULL, links TEXT NOT NULL)",
                "CREATE VIRTUAL TABLE IF NOT EXISTS body USING fts5(id UNINDEXED, title, aliases, text, tokenize='unicode61 remove_diacritics 2')",
                "PRAGMA user_version = " + VERSION
            ].join(";"));
            return database;
        } catch (error) {
            database.close();
            throw error;
        }
    }

    function clear(database) {
        database.exec("DELETE FROM body; DELETE FROM notes; DELETE FROM meta");
    }

    function reconcile() {
        const folder = home();
        if (folder === null) return;
        const database = open();
        const priorHome = database.prepare("SELECT value FROM meta WHERE key='home'").get()?.value ?? null;
        const rows = Home.notes(folder);
        // A per-call stat walk is enough for a personal notes folder and
        // avoids a watcher lifetime owned beside the daemon's own lease.
        const notes = rows.map(row => {
            const text = Home.note(folder, row.id);
            const hash = crypto.createHash("sha256").update(text).digest("hex");
            return { ...parseNote(row.id, text), hash, stat: statKey(row) };
        });
        resolveLinks(notes);
        database.exec("BEGIN IMMEDIATE");
        try {
            if (priorHome !== folder || openedHome !== folder) {
                clear(database);
                openedHome = folder;
            }
            const seen = new Set(notes.map(note => note.id));
            for (const row of database.prepare("SELECT id FROM notes").all())
                if (!seen.has(row.id)) {
                    database.prepare("DELETE FROM notes WHERE id=?").run(row.id);
                    database.prepare("DELETE FROM body WHERE id=?").run(row.id);
                }
            for (const note of notes) {
                const prior = database.prepare("SELECT hash, stat FROM notes WHERE id=?").get(note.id);
                if (prior?.hash === note.hash && prior?.stat === note.stat) {
                    database.prepare("UPDATE notes SET links=? WHERE id=?").run(json(note.links), note.id);
                    continue;
                }
                database.prepare("DELETE FROM body WHERE id=?").run(note.id);
                database.prepare("INSERT OR REPLACE INTO notes(id,hash,stat,title,aliases,date,labels,links) VALUES(?,?,?,?,?,?,?,?)")
                    .run(note.id, note.hash, note.stat, note.title, json(note.aliases), note.date, json(note.labels), json(note.links));
                database.prepare("INSERT INTO body(id,title,aliases,text) VALUES(?,?,?,?)")
                    .run(note.id, note.title, note.aliases.join(" "), note.text);
            }
            database.prepare("INSERT OR REPLACE INTO meta(key,value) VALUES('home',?)").run(folder);
            database.exec("COMMIT");
        } catch (error) {
            database.exec("ROLLBACK");
            throw error;
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

    function search(args, done) {
        let database;
        try { reconcile(); database = open(); } catch { fail("memory-search:", "index", done); return; }
        const match = matchQuery(args.query);
        if (match === null) { fail("memory-search:", "query-empty", done); return; }
        try {
            const where = ["body MATCH ?"];
            const params = [match];
            if (args.title !== undefined) { where.push("lower(notes.title) LIKE '%' || lower(?) || '%'"); params.push(args.title); }
            if (args.alias !== undefined) { where.push("EXISTS (SELECT 1 FROM json_each(notes.aliases) WHERE lower(value)=lower(?))"); params.push(args.alias); }
            if (args.since !== undefined) { where.push("notes.date IS NOT NULL AND notes.date >= ?"); params.push(args.since); }
            if (args.until !== undefined) { where.push("notes.date IS NOT NULL AND notes.date <= ?"); params.push(args.until); }
            params.push(LIMIT);
            const rows = database.prepare("SELECT notes.id, notes.title, notes.date, notes.labels, snippet(body, 3, '[', ']', '…', 12) AS snippet FROM body JOIN notes ON notes.id=body.id WHERE "
                + where.join(" AND ") + " ORDER BY bm25(body, 0, 10, 5, 1) LIMIT ?").all(...params);
            done({ outcome: "completed", content: JSON.stringify({ results: rows.map(rowObject) }),
                labels: rows.length === 0 ? ["home"] : labelsOf(rows) });
        } catch { fail("memory-search:", "query", done); }
    }

    function read(args, done) {
        let database, readAny = false;
        try { reconcile(); database = open(); } catch { fail("memory-read:", "index", done); return; }
        const notes = [];
        for (const id of args.ids) {
            const row = database.prepare("SELECT * FROM notes WHERE id=?").get(id);
            if (row === undefined) { notes.push({ id, error: "absent" }); continue; }
            let text;
            try { text = Home.note(home(), id); }
            catch { notes.push({ id, error: "absent" }); continue; }
            if (text.trim() === "") { notes.push({ id, error: "empty" }); continue; }
            readAny = true;
            const backlinks = database.prepare("SELECT id FROM notes").all()
                .map(other => other.id).filter(other => parseJson(database.prepare("SELECT links FROM notes WHERE id=?").get(other).links, []).includes(id));
            notes.push({ id, title: row.title, ...(row.date === null ? {} : { date: row.date }),
                sources: parseJson(row.labels, ["home"]), links: parseJson(row.links, []), backlinks, text });
        }
        const rows = args.ids.map(id => database.prepare("SELECT labels FROM notes WHERE id=?").get(id)).filter(Boolean);
        done({ outcome: readAny ? "completed" : "failed", content: readAny ? JSON.stringify({ notes }) : "memory-read:absent",
            labels: rows.length === 0 ? ["home"] : labelsOf(rows) });
    }

    const executor = Object.freeze({ commands: [], timeoutMs: 2000, cancellable: false,
        available: () => home() !== null,
        start(call, done) {
            if (closed) { fail(call.id === "memory.search" ? "memory-search:" : "memory-read:", "closed", done); return; }
            if (call.id === "memory.search") search(call.args, done);
            else if (call.id === "memory.read") read(call.args, done);
            else fail("memory-search:", "tool", done);
        } });
    router.register("memory", executor);
    try { reconcile(); } catch (error) { log("jarvis: memory-search=index"); }
    return { kind: "installed", close() { closed = true; if (db !== null) db.close(); } };
}

module.exports = { install };
