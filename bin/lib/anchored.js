// The one anchored descriptor walk, for account discovery, the account
// readers of Jarvis and AI usage, and Jarvis's file tools, which load it
// from the tree their launcher names. Linux /proc/self/fd/<fd>/<name> paths
// resolve through a held directory's inode, so a component renamed or
// swapped for a link after a judge is refused or stays inside that
// directory; it is never followed elsewhere.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { O_RDONLY, O_DIRECTORY, O_NOFOLLOW } = fs.constants;
// The longest path the walk takes, Linux's PATH_MAX.
const MAX_PATH_BYTES = 4096;

/** The path of `name` inside the directory held open as `fd`. */
function child(fd, name) {
    return "/proc/self/fd/" + fd + "/" + name;
}

/**
 * Open every component of an absolute normal path as a directory from "/",
 * holding each parent while its child opens. The only link followed is our
 * own /proc descriptor. Returns {kind: "directory", fd}, whose fd the caller
 * closes, or one of {kind: "not-absolute"} for a value that is no string,
 * no absolute normal path or longer than MAX_PATH_BYTES, which the walk
 * would otherwise follow out of a folder through `..`, {kind: "absent"},
 * {kind: "unreadable", code}, {kind: "link"}, {kind: "not-directory"} and
 * {kind: "unreadable-or-changed"}.
 */
function directory(file) {
    if (typeof file !== "string" || !path.isAbsolute(file) || path.normalize(file) !== file
        || Buffer.byteLength(file) > MAX_PATH_BYTES) return { kind: "not-absolute" };
    let fd = fs.openSync("/", O_RDONLY | O_DIRECTORY);
    try {
        for (const part of file.split("/").filter(Boolean)) {
            let stat;
            try { stat = fs.lstatSync(child(fd, part)); }
            catch (error) { return error.code === "ENOENT" ? { kind: "absent" } : { kind: "unreadable", code: error.code }; }
            if (stat.isSymbolicLink()) return { kind: "link" };
            if (!stat.isDirectory()) return { kind: "not-directory" };
            let next;
            try { next = fs.openSync(child(fd, part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW); }
            catch { return { kind: "unreadable-or-changed" }; }
            fs.closeSync(fd);
            fd = next;
        }
        const result = { kind: "directory", fd };
        fd = undefined;
        return result;
    } finally { if (fd !== undefined) fs.closeSync(fd); }
}

module.exports = { child, directory };
