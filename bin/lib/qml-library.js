// Load one of the shell's `.pragma library` JavaScript files under node, so a
// script makes its decision through the shell's own judge instead of a copy.
// Every offline reader of shell/Core/PluginLogic.js, shell/Core/ConfigLogic.js
// and shell/Core/Dispatch.js goes through here: bin/lib/check-manifests.js,
// bin/vgshell-plugin-judge, bin/vgshell-theme-judge, bin/vgshell-pkg,
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
const MODULE_IMPORT = /^\.import\s+([A-Za-z_][A-Za-z0-9_.]*\s+[0-9]+\.[0-9]+)\s+as\s+([A-Za-z_][A-Za-z0-9_]*)\s*$/;

function refuse(first) {
    process.stderr.write("qml-library: refused: " + first + "\n");
    process.exit(2);
}

// FILE's body, with each import line blanked so the body keeps its line
// numbers, and its imports in order: { name, file } for a path import and
// { name, module } for a bound module import. Only the header is cut into
// lines, to avoid splitting and joining the whole library on every load.
function read(file, modules) {
    let source;
    try {
        source = fs.readFileSync(file, "utf8");
    } catch (e) {
        refuse("unreadable path=" + file + " error=" + e.code);
    }
    if (!source.startsWith(PRAGMA)) refuse("pragma=missing path=" + file);
    const lineAt = at => {
        const end = source.indexOf("\n", at);
        return source.slice(at, end === -1 ? source.length : end);
    };
    const imports = [];
    let at = PRAGMA.length;
    let blank = "";
    while (source.startsWith(".import", at)) {
        const line = lineAt(at);
        const m = IMPORT.exec(line);
        const moduleImport = MODULE_IMPORT.exec(line);
        if (m === null && (moduleImport === null || !Object.prototype.hasOwnProperty.call(modules, moduleImport[1])))
            refuse("import=" + JSON.stringify(line) + " path=" + file);
        if (m !== null) imports.push({ name: m[2], file: path.resolve(path.dirname(file), m[1]) });
        else imports.push({ name: moduleImport[2], module: moduleImport[1] });
        blank += "\n";
        at += line.length + 1;
    }
    const late = source.indexOf("\n.import", at);
    if (late !== -1) refuse("import=" + JSON.stringify(lineAt(late + 1)) + " path=" + file);
    return { body: blank + source.slice(at), imports };
}

// The library's top-level functions and variables as properties of one
// object, evaluated in a fresh context with no access to this process. Each
// imported library is bound on it under its qualifier before the body runs.
function load(file, modules = {}) {
    const { body, imports } = read(file, modules);
    const library = {};
    for (const entry of imports)
        library[entry.name] = entry.file !== undefined ? load(entry.file, modules) : modules[entry.module];
    vm.runInNewContext(body, library, { filename: file });
    return library;
}

// The absolute path of FILE and of every library its path imports reach:
// the files load(FILE, MODULES) reads, refused as load refuses them.
function closure(file, modules = {}, seen = new Set()) {
    const resolved = path.resolve(file);
    if (seen.has(resolved)) return seen;
    seen.add(resolved);
    for (const entry of read(resolved, modules).imports)
        if (entry.file !== undefined) closure(entry.file, modules, seen);
    return seen;
}

module.exports = { load, closure };
