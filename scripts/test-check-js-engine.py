#!/usr/bin/env python3
"""One planted tree per form check-js-engine.py must find or pass, and the
unreadable trees. Each case writes its files into a throwaway directory,
runs the check on it and asserts each finding's file, line and name, or the
pass, and the exit status."""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CHECK = os.path.join(HERE, "check-js-engine.py")
ENV = {"PATH": os.environ.get("PATH", ""), "LC_ALL": "C"}
QML = "import QtQuick\nItem {}\n"

# rows: name, files, expected findings as (file, line, name).
CASES = [
    ("flatMap in a QML binding", {"Main.qml": 'import QtQuick\nItem {\n    property var all: [[1]].flatMap(x => x)\n}\n'},
     [("Main.qml", 3, "flatMap")]),
    ("trimEnd in a file a QML file imports",
     {"Main.qml": 'import QtQuick\nimport "Logic.js" as Logic\nItem {}\n', "Logic.js": ".pragma library\nfunction tidy(s) { return s.trimEnd(); }\n"},
     [("Logic.js", 2, "trimEnd")]),
    ("a file a loaded file .imports", {"Main.qml": 'import "a/A.js" as A\nItem {}\n', "a/A.js": '.import "B.js" as B\n', "a/B.js": "var o = Object.fromEntries([]);\n"},
     [("a/B.js", 1, "Object.fromEntries")]),
    ("a file a qmldir lists", {"Main.qml": QML, "M/qmldir": "module M\nText 1.0 Text.js\n", "M/Text.js": "function f(s) { return s?.replaceAll('a', 'b'); }\n"},
     [("M/Text.js", 1, "replaceAll")]),
    ("a missing global", {"Main.qml": "Item { property var copy: structuredClone({}) }\n"}, [("Main.qml", 1, "structuredClone")]),
    ("a file only node runs", {"Main.qml": QML, "test.js": "const all = [[1]].flatMap(x => x);\n"}, []),
    ("a name in a comment", {"Main.qml": "Item {\n    // never [].flatMap(f) here\n    /* \" \".trimEnd() */\n}\n"}, []),
    ("an own function of the same name", {"Main.qml": 'import "Logic.js" as Logic\nItem { property bool held: Logic.hasOwn(o, "k") }\n',
                                          "Logic.js": "function hasOwn(o, k) { return Object.prototype.hasOwnProperty.call(o, k); }\n"}, []),
]

failures = 0


def run(args):
    return subprocess.run([sys.executable, CHECK, *args], capture_output=True, text=True, env=ENV, timeout=30)


def check(name, condition, result):
    global failures
    if condition:
        print(f"ok    {name}")
    else:
        failures += 1
        print(f"FAIL  {name}: exit={result.returncode}\n{result.stdout}{result.stderr}")


def found(stdout):
    rows = []
    for line in stdout.splitlines():
        if line.startswith("engine-missing "):
            place, name = line.split()[1:3]
            path, number = place.rsplit(":", 1)
            rows.append((path, int(number), name.removeprefix("name=")))
    return rows


with tempfile.TemporaryDirectory() as tmp:
    for index, (name, files, want) in enumerate(CASES):
        root = os.path.join(tmp, str(index))
        for relative, text in files.items():
            os.makedirs(os.path.dirname(os.path.join(root, relative)), exist_ok=True)
            with open(os.path.join(root, relative), "w") as source:
                source.write(text)
        result = run([root])
        expected = [(os.path.join(root, path), line, call) for path, line, call in want]
        if want:
            check(name, result.returncode == 1 and found(result.stdout) == expected, result)
        else:
            check(name, result.returncode == 0 and result.stdout.startswith("check-js-engine: ok "), result)

    result = run([os.path.join(tmp, "missing")])
    check("a missing directory is unreadable", result.returncode == 2 and result.stdout.startswith("check-js-engine: unreadable: "), result)
    empty = os.path.join(tmp, "empty")
    os.makedirs(os.path.join(empty, "lib"))
    with open(os.path.join(empty, "lib", "a.js"), "w") as source:
        source.write("var x = 1;\n")
    result = run([empty])
    check("a tree with no QML file is unreadable", result.returncode == 2 and result.stdout == f"check-js-engine: unreadable: {empty}: no QML file found\n", result)

if failures:
    print(f"test-check-js-engine: failures={failures}")
    sys.exit(1)
print(f"test-check-js-engine: ok cases={len(CASES) + 2}")
