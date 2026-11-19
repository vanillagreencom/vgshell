#!/usr/bin/env python3
"""Refuse a call to a JavaScript function the shell's engine lacks.

QML and the JavaScript the QML engine loads run on Qt's own engine, which
lacks functions every other runtime has. A call to one throws a TypeError
or ReferenceError, and the binding or reader it feeds silently yields
nothing: VGS-2594's smoke Probe.qml flatMap and VGS-2620's Callout.qml
trimEnd. One rule:
  engine-missing  a line of code names a function of MISSING: `.<name>(`
                  for a prototype method, the qualified `<Owner>.<name>`
                  for a static one, the bare name for a global.
The rule reads every `.qml` file and every `.js` file the QML engine
loads: one a qmldir lists, one a `.qml` file imports with `import "x.js"`
or a loaded `.js` file with `.import "x.js"`, resolved beside the importer.
A `.js` file only node runs, a test or the Jarvis backend, is not read;
node has these functions. An import that names no file in the tree is a
path a test runner assembles at run time and is not followed. Code is read
with comments blanked through scripts/qml_source.py; string contents stay.

Usage: check-js-engine.py [DIR...]
With no directory, the repository's shell/ and scripts/. Every finding is
one line: `engine-missing <file>:<line> name=<name> use="<hint>"`. The pass
is `check-js-engine: ok files=<n> js=<n>`, `js` counting the loaded `.js`
files read. Exit 0 when clean, 1 on any finding, 2 when a directory or
file cannot be read, printed as `check-js-engine: unreadable: <path>:
<strerror>`. A tree holding no QML file is unreadable too: an empty walk
certifies nothing.
"""
import os
import re
import sys

# A check writes nothing into the tree it reads, so the shared module leaves
# no bytecode cache beside it.
sys.dont_write_bytecode = True
from qml_source import Unreadable, blank_comments, scan_sources

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_ROOTS = (os.path.join(REPO, "shell"), os.path.join(REPO, "scripts"))

# Each name read `typeof` undefined, and its call threw, under qmltestrunner
# of qt6-declarative 6.12.0, the libQt6Qml.so.6 vgshell-quickshell 0.3.2
# links, in the shell's QV4 mode through scripts/qml-unit.sh on 2026-11-18.
# The full reading, present functions included, is on VGS-2637.
PROTOTYPE = {
    "flat": "reduce((all, x) => all.concat(x), [])",
    "flatMap": "map(f), then reduce((all, x) => all.concat(x), [])",
    "at": "xs[xs.length - 1] or s.charAt(i)",
    "findLast": "a loop from the end",
    "findLastIndex": "a loop from the end",
    "toSorted": "slice().sort(f)",
    "toReversed": "slice().reverse()",
    "toSpliced": "slice(), then splice() on the copy",
    "with": "slice(), then assign the index on the copy",
    "trimStart": 'replace(/^\\s+/, "")',
    "trimLeft": 'replace(/^\\s+/, "")',
    "trimEnd": 'replace(/\\s+$/, "")',
    "trimRight": 'replace(/\\s+$/, "")',
    "matchAll": "a /g RegExp and an exec() loop",
    "replaceAll": "split(a).join(b) or replace(/.../g, b)",
    "isWellFormed": "a /[\\uD800-\\uDFFF]/ test",
    "toWellFormed": "replace() over lone surrogates",
    "union": "a loop over has() into a new Set",
    "intersection": "filter() over has() into a new Set",
}
STATIC = {
    "Object.fromEntries": "reduce((o, [k, v]) => (o[k] = v, o), {})",
    "Object.hasOwn": "Object.prototype.hasOwnProperty.call(o, k)",
    "Object.groupBy": "reduce() into an object",
    "Map.groupBy": "reduce() into a Map",
    "Promise.allSettled": "Promise.all over then(v => ..., e => ...) per promise",
    "Promise.any": "a counter of rejections over then()",
    "Array.fromAsync": "an await loop that pushes",
}
GLOBAL = {
    "structuredClone": "JSON.parse(JSON.stringify(v)) for plain data",
    "globalThis": "the global by its own name",
    "queueMicrotask": "Qt.callLater(f)",
    "BigInt": "Number",
    "WeakRef": "a plain reference",
}
MISSING = {**PROTOTYPE, **STATIC, **GLOBAL}
CALL = re.compile(
    r"\.(" + "|".join(PROTOTYPE) + r")\s*\("
    r"|\b(" + "|".join(re.escape(name) for name in STATIC) + r")\b"
    r"|(?<![\w$.])(" + "|".join(GLOBAL) + r")\b")
QML_IMPORT = re.compile(r'^\s*import\s+"([^"]+\.js)"', re.M)
JS_IMPORT = re.compile(r'^\s*\.import\s+"([^"]+\.js)"', re.M)
QMLDIR_JS = re.compile(r"^\s*\w+\s+[\d.]+\s+(\S+\.js)\s*$", re.M)


def read_tree(root, texts, qmldirs):
    try:
        for relative, _executable, data in scan_sources(root):
            name = os.path.basename(relative)
            if not (name == "qmldir" or name.endswith((".qml", ".js"))):
                continue
            path = os.path.normpath(os.path.join(root, relative))
            try:
                text = data.decode("utf-8-sig")
            except UnicodeError as exc:
                raise Unreadable(path, str(exc)) from exc
            if name == "qmldir":
                qmldirs[path] = text
            else:
                texts[path] = blank_comments(text)
    except OSError as exc:
        raise Unreadable(exc.filename, exc.strerror) from exc


def loaded(texts, qmldirs):
    """The `.qml` files and the `.js` files the QML engine loads among them."""
    found = {path for path in texts if path.endswith(".qml")}
    for path, text in qmldirs.items():
        found.update(os.path.normpath(os.path.join(os.path.dirname(path), js)) for js in QMLDIR_JS.findall(text))
    pending = list(found)
    while pending:
        path = pending.pop()
        if path not in texts:
            continue
        imports = QML_IMPORT if path.endswith(".qml") else JS_IMPORT
        for js in imports.findall(texts[path]):
            target = os.path.normpath(os.path.join(os.path.dirname(path), js))
            if target not in found:
                found.add(target)
                pending.append(target)
    return sorted(found & texts.keys())


def main(argv):
    roots = [os.path.abspath(root) for root in argv[1:]] or list(DEFAULT_ROOTS)
    texts, qmldirs = {}, {}
    try:
        for root in roots:
            read_tree(root, texts, qmldirs)
        files = loaded(texts, qmldirs)
        if not any(path.endswith(".qml") for path in files):
            raise Unreadable(" ".join(roots), "no QML file found")
    except Unreadable as exc:
        print(f"check-js-engine: unreadable: {exc.path}: {exc.strerror}")
        return 2
    findings = []
    for path in files:
        for number, line in enumerate(texts[path].split("\n"), 1):
            for match in CALL.finditer(line):
                name = match.group(match.lastindex)
                findings.append(f'engine-missing {path}:{number} name={name} use="{MISSING[name]}"')
    for line in findings:
        print(line)
    if findings:
        print(f"check-js-engine: findings={len(findings)}")
        return 1
    print(f"check-js-engine: ok files={len(files)} js={sum(path.endswith('.js') for path in files)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
