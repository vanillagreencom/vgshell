// Load one of the shell's `.pragma library` JavaScript files under node, so a
// script makes its decision through the shell's own judge instead of a copy.
// Every offline reader of shell/Core/PluginLogic.js and shell/Core/Dispatch.js
// goes through here: bin/lib/check-manifests.js, bin/vgshell-plugin-judge,
// scripts/test-plugin-logic.js and scripts/test-dispatch.js.
//
// The pragma is what marks a file as a library Quickshell shares between QML
// files; a file without it is not one the shell loads that way, so loading it
// here would judge with code the shell never runs. A library may import
// another library as the shell does, with `.import "<path>" as <Name>` lines
// straight after the pragma, the path relative to the importing file; the
// imported file is loaded by the same rule and bound as <Name>. Module
// imports require explicit bindings from the caller, keyed by module name
// and version, for example "qs.Commons 1.0". An unresolved import is refused.
// Each refusal is one keyed line
// on stderr and exit 2:
//   qml-library: refused: pragma=missing path=<file>
//   qml-library: refused: unreadable path=<file> error=<code>
//   qml-library: refused: import=<line> path=<file>
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const PRAGMA = ".pragma library\n";
const IMPORT = /^\.import\s+"([^"]+)"\s+as\s+([A-Za-z_][A-Za-z0-9_]*)\s*$/;

function refuse(first) {
    process.stderr.write("qml-library: refused: " + first + "\n");
    process.exit(2);
}

// The library's top-level functions and variables as properties of one
// object, evaluated in a fresh context with no access to this process. Each
// imported library is bound on it under its qualifier before the body runs.
function load(file, modules = {}) {
    let source;
    try {
        source = fs.readFileSync(file, "utf8");
    } catch (e) {
        refuse("unreadable path=" + file + " error=" + e.code);
    }
    if (!source.startsWith(PRAGMA)) refuse("pragma=missing path=" + file);
    const library = {};
    // Import lines become blank lines, so the body keeps its line numbers.
    const lines = source.slice(PRAGMA.length).split("\n");
    let header = true;
    for (let i = 0; i < lines.length; i++) {
        if (!lines[i].startsWith(".import")) {
            header = false;
            continue;
        }
        const m = IMPORT.exec(lines[i]);
        const moduleImport = /^\.import\s+([A-Za-z_][A-Za-z0-9_.]*\s+[0-9]+\.[0-9]+)\s+as\s+([A-Za-z_][A-Za-z0-9_]*)\s*$/.exec(lines[i]);
        if (!header || (m === null && (moduleImport === null || !Object.prototype.hasOwnProperty.call(modules, moduleImport[1]))))
            refuse("import=" + JSON.stringify(lines[i]) + " path=" + file);
        if (m !== null) library[m[2]] = load(path.resolve(path.dirname(file), m[1]), modules);
        else library[moduleImport[2]] = modules[moduleImport[1]];
        lines[i] = "";
    }
    vm.runInNewContext(lines.join("\n"), library, { filename: file });
    return library;
}

module.exports = { load };
