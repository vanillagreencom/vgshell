// The core files the Jarvis backend reads through backend/Core.js. The
// checkout's own backend reads this checkout's tree once this file loads; a
// test's disposable backend copy names its tree with useTree: the checkout's,
// or a scratch tree from scratchTree that holds the core files with one
// planted edit.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const tree = path.resolve(__dirname, "../../..");
// What backend/Core.js loads, by its path in the tree.
const FILES = Object.freeze(["bin/lib/qml-library.js", "bin/lib/anchored.js", "bin/lib/account-folders.js",
    "shell/Commons/AccountDirectories.js"]);

/** Name ROOT, the checkout's tree by default, for the backend in BACKEND. */
function useTree(backend, root = tree) {
    require(path.join(backend, "Core.js")).use(root);
}

/**
 * A tree under PARENT holding the core files, each file CHANGES names, by
 * its path in the tree, holding the text given there in place of the
 * checkout's. Returns the tree's root.
 */
function scratchTree(parent, changes) {
    for (const name of Object.keys(changes)) assert.ok(FILES.includes(name), "core file " + name);
    const root = fs.mkdtempSync(path.join(parent, "core-"));
    for (const name of FILES) {
        fs.mkdirSync(path.join(root, path.dirname(name)), { recursive: true });
        fs.writeFileSync(path.join(root, name), changes[name] ?? fs.readFileSync(path.join(tree, name), "utf8"));
    }
    return root;
}

useTree(path.join(tree, "shell/plugins/vgs.jarvis/backend"));

module.exports = { FILES, useTree, scratchTree };
