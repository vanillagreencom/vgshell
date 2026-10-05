// The one account discovery: where the AI command-line harnesses keep their
// sign-ins, by the rule in shell/Commons/AccountDirectories.js. Jarvis and
// AI usage load it from the tree their launcher names. Only the direct
// entries of HOME and the XDG config and data homes are read; no folder
// below them is entered.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const Anchored = require("./anchored.js");
const Rule = require("./qml-library.js").load(path.join(__dirname, "../../shell/Commons/AccountDirectories.js"));

// A bound on a parent that can hold any number of entries, not a time
// budget: a parent past it is reported partial with the folders read.
const MAX_PARENT_ENTRIES = 10000;

function absoluteNormal(value) {
    return typeof value === "string" && path.isAbsolute(value) && path.normalize(value) === value;
}

/**
 * Every account folder, in this order: each harness's explicit root from
 * its variable in env, then its default folder in home, then the account
 * folders directly inside home, config and data, each parent read once.
 * Returns { folders: [{ provider, directory, label, source }], partial },
 * source "explicit", "default" or "folder", one row per provider and
 * directory, the first found. An explicit root is the user's own name for a
 * folder and is not opened here: the caller opens it anchored. A default
 * folder that is absent is listed; one that is linked, no directory or
 * unreadable, or lies under such a home, is left out. partial is
 * "entry-limit" when a parent held more than MAX_PARENT_ENTRIES names and
 * "parent-unreadable" when a default folder was left out or a parent is
 * linked, no directory or unreadable, whichever came first, else "". A
 * partial search keeps the folders it read. An absent parent holds none; a
 * home, config or data that is no absolute normal path throws
 * account-folders: directory=absolute-normal-path-required.
 */
function accountFolders({ home, config, data, env }) {
    for (const parent of [home, config, data])
        if (!absoluteNormal(parent)) throw new Error("account-folders: directory=absolute-normal-path-required");
    const folders = [];
    const seen = new Set();
    let partial = "";
    const add = (row, directory, label, source) => {
        const key = row.id + "\0" + directory;
        if (seen.has(key)) return;
        seen.add(key);
        folders.push({ provider: row.id, directory, label, source });
    };
    for (const row of Rule.HARNESSES) {
        const explicit = env[row.variable];
        if (typeof explicit === "string" && explicit !== "") add(row, explicit, path.basename(explicit), "explicit");
        const fallback = path.join(home, "." + row.folder);
        // A linked default or home is never followed.
        const opened = Anchored.directory(fallback);
        if (opened.kind === "directory") fs.closeSync(opened.fd);
        if (opened.kind === "directory" || opened.kind === "absent") add(row, fallback, "default", "default");
        else partial ||= "parent-unreadable";
    }
    for (const parent of [...new Set([home, config, data])]) {
        // A linked parent is never followed.
        const opened = Anchored.directory(parent);
        if (opened.kind === "absent") continue;
        if (opened.kind !== "directory") { partial ||= "parent-unreadable"; continue; }
        let stream;
        try {
            stream = fs.opendirSync("/proc/self/fd/" + opened.fd);
            let read = 0;
            for (let entry; (entry = stream.readSync()) !== null;) {
                if (++read > MAX_PARENT_ENTRIES) { partial ||= "entry-limit"; break; }
                if (entry.isSymbolicLink() || !entry.isDirectory()) continue;
                const row = Rule.accountDirectory(entry.name, 1);
                if (row) add(row, path.join(parent, entry.name), Rule.label(entry.name, row), "folder");
            }
        } catch (error) {
            if (typeof error.code !== "string") throw error;
            partial ||= "parent-unreadable";
        } finally {
            if (stream) stream.closeSync();
            fs.closeSync(opened.fd);
        }
    }
    return { folders, partial };
}

module.exports = { accountFolders };
