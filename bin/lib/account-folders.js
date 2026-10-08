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
 *
 * followLinks: false, the default, is the anchored walk for the readers of
 * sign-ins, which never leaves a folder through a link. true follows links
 * as a path lookup does, for the theme apply, which writes where a harness
 * itself reads: a dotfile manager's linked `~/.claude` is then a folder.
 */
function accountFolders({ home, config, data, env, followLinks = false }) {
    const open = followLinks ? openFollowed : openAnchored;
    // The walk judges each parent; a default folder joined below one would
    // read as normal whatever the parent held.
    for (const parent of [home, config, data]) {
        const opened = open(parent);
        if (opened.kind === "directory") opened.close();
        if (opened.kind === "not-absolute") throw new Error("account-folders: directory=absolute-normal-path-required");
    }
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
        const fallback = path.join(home, row.home);
        // A linked default or home is followed only with followLinks.
        const opened = open(fallback);
        if (opened.kind === "directory") opened.close();
        if (opened.kind === "directory" || opened.kind === "absent") add(row, fallback, "default", "default");
        else partial ||= "parent-unreadable";
    }
    for (const parent of [...new Set([home, config, data])]) {
        // A linked parent is followed only with followLinks.
        const opened = open(parent);
        if (opened.kind === "absent") continue;
        if (opened.kind !== "directory") { partial ||= "parent-unreadable"; continue; }
        let stream;
        try {
            stream = fs.opendirSync(opened.path);
            let read = 0;
            for (let entry; (entry = stream.readSync()) !== null;) {
                if (++read > MAX_PARENT_ENTRIES) { partial ||= "entry-limit"; break; }
                if (!(entry.isDirectory() || (followLinks && entry.isSymbolicLink() && open(path.join(parent, entry.name)).kind === "directory"))) continue;
                const row = Rule.accountDirectory(entry.name, 1);
                if (row) add(row, path.join(parent, entry.name), Rule.label(entry.name, row), "folder");
            }
        } catch (error) {
            if (typeof error.code !== "string") throw error;
            partial ||= "parent-unreadable";
        } finally {
            if (stream) stream.closeSync();
            opened.close();
        }
    }
    return { folders, partial };
}

// A folder opened without following a link: { kind: "directory", path,
// close } reads it through the held descriptor, else Anchored's kind.
function openAnchored(dir) {
    const opened = Anchored.directory(dir);
    if (opened.kind !== "directory") return { kind: opened.kind };
    return { kind: "directory", path: "/proc/self/fd/" + opened.fd, close: () => fs.closeSync(opened.fd) };
}

// A folder looked up through links, with the same answers.
function openFollowed(dir) {
    if (typeof dir !== "string" || !path.isAbsolute(dir) || path.normalize(dir) !== dir) return { kind: "not-absolute" };
    let stat;
    try {
        stat = fs.statSync(dir);
    } catch (error) {
        if (typeof error.code !== "string") throw error;
        return error.code === "ENOENT" ? { kind: "absent" } : { kind: "unreadable", code: error.code };
    }
    return stat.isDirectory() ? { kind: "directory", path: dir, close: () => {} } : { kind: "not-directory" };
}

module.exports = { accountFolders };
