// The account folders the harnesses document beside each other: Claude Code
// keeps `~/.claude` (CLAUDE_CONFIG_DIR overrides it) and Codex `~/.codex`
// (CODEX_HOME), and a second account is a sibling such as `~/.claude-work`
// or `~/.2codex`. Only the direct entries of HOME and the XDG config and
// data homes are read; no folder below them is entered.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const Anchored = require("./Anchored.js");
const { accountDirectory } = require("../AccountProviders.js");

// A bound on a parent that can hold any number of entries, not a time
// budget: a parent past it is reported partial with the folders read.
const MAX_PARENT_ENTRIES = 10000;

function fail(reason) { throw new Error("jarvis-accounts: " + reason); }

// The folder name less its provider's name and the separators around it:
// a tag before and a suffix after, joined by "-", or "default".
function label(name, row) {
    const at = name.indexOf(row.folder, 1);
    const parts = [name.slice(1, at), name.slice(at + row.folder.length).replace(/^[-_.]+|[-_.]+$/g, "")];
    return parts.filter(Boolean).join("-") || "default";
}

/**
 * The account folders directly inside home, config and data, each parent
 * read once. Returns { folders: [{ provider, directory, label }], partial }
 * with partial "entry-limit" when a parent held more than
 * MAX_PARENT_ENTRIES names, else "". An absent parent holds none; a linked
 * or unreadable one throws its directory= or discovery= key.
 */
function accountFolders({ home, config, data }) {
    const folders = [];
    let partial = "";
    for (const parent of [...new Set([home, config, data])]) {
        if (typeof parent !== "string" || !path.isAbsolute(parent) || path.normalize(parent) !== parent)
            fail("directory=absolute-normal-path-required");
        const opened = Anchored.directory(parent);
        if (opened.kind === "absent") continue;
        if (opened.kind !== "directory") fail("directory=" + opened.kind);
        let stream;
        try {
            stream = fs.opendirSync("/proc/self/fd/" + opened.fd);
            let read = 0;
            for (let entry; (entry = stream.readSync()) !== null;) {
                if (++read > MAX_PARENT_ENTRIES) { partial = "entry-limit"; break; }
                if (entry.isSymbolicLink() || !entry.isDirectory()) continue;
                const row = accountDirectory(entry.name, 1);
                if (row) folders.push({ provider: row.id, directory: path.join(parent, entry.name), label: label(entry.name, row) });
            }
        } catch (error) {
            if (error.message.startsWith("jarvis-accounts:")) throw error;
            fail("discovery=directory-unreadable");
        } finally {
            if (stream) stream.closeSync();
            fs.closeSync(opened.fd);
        }
    }
    return { folders, partial };
}

module.exports = { accountFolders };
