// The core files the Jarvis backend reads: the account rule, the account
// discovery, the anchored walk, the Codex account reader and the base
// package of every Jarvis home. Plugin files
// run from a published snapshot (D014), so no path relative to this file
// reaches the core; each entry point hands use() the VGS tree it is given
// as --tree before it loads Accounts.js, Denied.js or Files.js, and those
// read the core through here when they load.
"use strict";
const path = require("node:path");

let tree = null;
let loaded = null;

/** Name the VGS tree, an absolute path, once per process. */
function use(root) {
    if (typeof root !== "string" || !path.isAbsolute(root)) throw new Error("jarvis: tree=absolute-path-required");
    const resolved = path.resolve(root);
    if (tree !== null && tree !== resolved) throw new Error("jarvis: tree=already-set");
    tree = resolved;
}

function core() {
    if (tree === null) throw new Error("jarvis: tree=unset");
    if (loaded === null) {
        const { load } = require(path.join(tree, "bin/lib/qml-library.js"));
        loaded = Object.freeze({
            accounts: load(path.join(tree, "shell/Commons/AccountDirectories.js")),
            folders: require(path.join(tree, "bin/lib/account-folders.js")),
            anchored: require(path.join(tree, "bin/lib/anchored.js"))
        });
    }
    return loaded;
}

/** shell/Commons/AccountDirectories.js: the harness table and the name rule. */
function accounts() { return core().accounts; }
/** bin/lib/account-folders.js: accountFolders. */
function folders() { return core().folders; }
/** bin/lib/anchored.js: child and directory. */
function anchored() { return core().anchored; }
/** The base package VGS ships for every Jarvis home: the kendex jarvis skill. */
function basePackage() {
    if (tree === null) throw new Error("jarvis: tree=unset");
    return path.join(tree, ".agents/skills/jarvis");
}
/**
 * bin/lib/codex-account.js: account and read, loaded on first use, so only
 * a Codex account read loads it.
 */
function codexAccount() {
    if (tree === null) throw new Error("jarvis: tree=unset");
    return require(path.join(tree, "bin/lib/codex-account.js"));
}

module.exports = { use, accounts, folders, anchored, basePackage, codexAccount };
