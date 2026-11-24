#!/usr/bin/env python3
"""Controls for scripts/row_loads.py, the reading of a table row's command
files that scripts/validate's unread rule and coverage check read.

Each case of CASES plants files in a scratch repository holding the reader,
runs the reader there over every file git lists, and asserts facts it must
print (`+`) and facts it must not (`-`), as `kind loader target` with `*`
for a field the case leaves open. CASES hold, for each operation of the
loading boundary table they name, a resolved load, an unread site or both,
and the rules that keep a literal path word, a comment, a match pattern, a
redirect target, quoted text, an array element and text that only looks
like a directive from being a load or a directive; the table's other entries are review's. MUTANTS run
the cases they name against a disposable copy of the reader with one rule
removed, and each must fail there: a copy whose rule is not found once or
whose reading fails is a failed control, not a kill. REAL holds loads the
reader must print for the checkout itself.

STORE_CASES hold the reuse of stored facts: each reads a file, changes one
input of its facts, and reads again against the store the first reading
left, which must print the fact the change makes, as a reading with the
store deleted does. In a case that marks it, the change comes first and
the first reading runs code compiled from the reader as it was before it, so
the code that runs is not the code of the bytes on disk. STORED, the
fidelity row, proves a reading prints every fact field of a hit's stored
entry, so the cases' changes are what void a hit, and that a store of
another shape or an entry missing a field reads as none. Two key parts
stay unproved: no case can change the Python that runs the reader, and
none changes node's built-in list.

Prints `test-row-loads: ok` or a `FAIL` line per finding, and exits 1 on
any. Arguments name the CASES, MUTANTS, STORE_CASES or STORED to run,
alone.
"""
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
READER = "scripts/row_loads.py"
# node on PATH may be a version-manager shim that reads the caller's own
# configuration, so the reader reaches node through the binary it resolves.
NODE = subprocess.run(["node", "-e", "process.stdout.write(process.execPath)"], capture_output=True, text=True).stdout
ENV = {"PATH": os.path.dirname(NODE) + ":" + os.environ.get("PATH", "/usr/bin:/bin"), "HOME": "/nonexistent", "LC_ALL": "C",
       "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"}

# name: ({path: text}, [expectations])
CASES = {
    "js require literal": ({
        "scripts/a.js": 'const b = require("./lib/b.js");\n',
        "scripts/lib/b.js": "module.exports = 1;\n",
    }, ["+load scripts/a.js scripts/lib/b.js", "-unread scripts/a.js * *"]),
    "js require computed under the root": ({
        "scripts/a.js": 'const path = require("path");\nrequire(path.join(__dirname, "..", "shell", process.env.X || "y") + ".js");\n',
        "shell/y.js": "",
    }, ["+unread scripts/a.js 2 require"]),
    "js require builtin and bare name": ({
        "scripts/a.js": 'require("node:fs");\nrequire("path");\nrequire("left-pad");\n',
    }, ["+unread scripts/a.js 3 require", "-unread scripts/a.js 1 *", "-unread scripts/a.js 2 *"]),
    "js require under a temporary copy": ({
        "scripts/a.js": 'const os = require("os"), path = require("path");\nconst tmp = os.tmpdir();\nrequire(path.join(tmp, "x.js"));\n',
    }, ["-unread scripts/a.js * *"]),
    "js esm import": ({
        "scripts/a.mjs": 'import { b } from "./b.mjs";\nimport("./" + name);\n',
        "scripts/b.mjs": "export const b = 1;\n",
    }, ["+load scripts/a.mjs scripts/b.mjs", "+unread scripts/a.mjs 2 import"]),
    "qml library under another binding": ({
        "scripts/a.js": 'const { load: loadLibrary } = require("../bin/lib/qml-library.js");\nconst path = require("path");\n'
                        'loadLibrary(path.join(__dirname, "..", "shell", "Commons", "X.js"));\n'
                        'loadLibrary(path.join(__dirname, "..", "shell", "Commons", process.argv[2]));\n',
        "shell/Commons/X.js": ".pragma library\n",
    }, ["+load scripts/a.js shell/Commons/X.js", "+unread scripts/a.js 4 qml-library"]),
    "js path binding": ({
        "scripts/a.js": 'const path = require("path"), fs = require("fs");\nconst file = path.join(__dirname, "..", "config", "c.json");\nfs.readFileSync(file);\n',
        "config/c.json": "{}\n",
    }, ["+load scripts/a.js config/c.json"]),
    "js enumerated folder": ({
        "scripts/a.js": 'const fs = require("fs"), path = require("path");\nfs.readdirSync(path.join(__dirname, "..", "themes"));\n'
                        'fs.readdirSync(path.join(__dirname, "..", "themes", process.argv[2]));\n',
        "themes/t/theme.json": "{}\n",
    }, ["-load scripts/a.js themes/t/theme.json", "+unread scripts/a.js 3 enumerate"]),
    "js vm over a file read": ({
        "scripts/a.js": 'const vm = require("vm"), fs = require("fs"), path = require("path");\n'
                        'vm.runInNewContext("1 + 1");\n'
                        'vm.runInNewContext(fs.readFileSync(path.join(__dirname, "..", "shell", process.argv[2]), "utf8"));\n',
        "shell/x.js": "",
    }, ["+unread scripts/a.js 3 vm", "-unread scripts/a.js 2 *"]),
    "js a repository root value": ({
        "scripts/a.js": 'const path = require("path");\nconst repo = path.join(__dirname, "..");\nconsole.log(repo);\n',
        "shell/x.js": "",
    }, ["-unread scripts/a.js * *", "-load scripts/a.js shell/x.js"]),
    "a spawned command's words": ({
        "scripts/a.js": 'const { spawnSync } = require("child_process");\nspawnSync("node", ["scripts/x.js", "--flag"]);\n',
        "scripts/b.py": 'import subprocess\nsubprocess.run(["python3", "scripts/y.py"], check=True)\n',
        "scripts/x.js": "", "scripts/y.py": "",
    }, ["+load scripts/a.js scripts/x.js", "+load scripts/b.py scripts/y.py"]),
    "a layout under an unknown base": ({
        "scripts/a.js": 'const path = require("path");\nconst tree = process.argv[2];\n'
                        'require(path.join(tree, "shell/Commons/X.js"));\nrequire(path.join(tree, "AGENTS.md"));\n',
        "scripts/b.py": 'import sys\nfrom pathlib import Path\nrepo = Path(sys.argv[1])\n(repo / "shell/Commons/X.js").read_text()\n',
        "shell/Commons/X.js": "", "AGENTS.md": "",
    }, ["+load scripts/a.js shell/Commons/X.js", "-load scripts/a.js AGENTS.md", "+load scripts/b.py shell/Commons/X.js"]),
    "a literal path word is no load": ({
        "scripts/a.js": '// shell/k.qml holds the view\nconst CASES = ["shell/k.qml"];\nconsole.log("see shell/k.qml");\n',
        "scripts/b.py": '"""shell/k.qml holds the view."""\nCASES = {"view": "shell/k.qml"}\n',
        "scripts/c.sh": 'row "a view" "node shell/k.qml"\necho shell/k.qml\nprintf \'%s\\n\' scripts/x.js >"$out"\n',
        "shell/k.qml": "Item {}\n", "scripts/x.js": "",
    }, ["-load scripts/a.js shell/k.qml", "-load scripts/b.py shell/k.qml", "-load scripts/c.sh shell/k.qml",
        "-load scripts/c.sh scripts/x.js"]),
    "python imports": ({
        "scripts/a.py": 'import os\nimport numpy\nimport helper\nimport nowhere\nimport sys\nsys.path.insert(0, "bin/lib")\nimport wire\n',
        "scripts/helper.py": "",
        "bin/lib/wire.py": "",
    }, ["+load scripts/a.py scripts/helper.py", "+load scripts/a.py bin/lib/wire.py", "+unread scripts/a.py 4 import",
        "-unread scripts/a.py 1 *", "-unread scripts/a.py 2 *"]),
    "python loaders": ({
        "scripts/a.py": 'from importlib.machinery import SourceFileLoader\nfrom pathlib import Path\nimport sys\n'
                        'ROOT = Path(__file__).resolve().parent.parent\n'
                        'SourceFileLoader("x", str(ROOT / "bin" / "x")).load_module()\n'
                        'SourceFileLoader("y", str(ROOT / "bin" / sys.argv[1])).load_module()\n',
        "bin/x": "#!/usr/bin/env python3\n",
    }, ["+load scripts/a.py bin/x", "+unread scripts/a.py 6 importlib"]),
    "python paths": ({
        "scripts/a.py": 'import os, sys\nfrom pathlib import Path\nROOT = Path(__file__).parent.parent\n'
                        '(ROOT / "shell" / "x.qml").read_text()\nopen(os.path.join(ROOT, "shell", sys.argv[1])).read()\n',
        "shell/x.qml": "Item {}\n",
    }, ["+load scripts/a.py shell/x.qml", "+unread scripts/a.py 5 path"]),
    "bash source": ({
        "scripts/a.sh": 'repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"\nsource "$repo/scripts/lib.sh"\nsource "$1"\n',
        "scripts/lib.sh": "",
    }, ["+load scripts/a.sh scripts/lib.sh", "+unread scripts/a.sh 3 source"]),
    "bash computed path under the root": ({
        "scripts/a.sh": 'repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"\nnode "$repo/scripts/x.js"\nbash "$repo/scripts/$1.sh"\n',
        "scripts/x.js": "",
    }, ["+load scripts/a.sh scripts/x.js", "+unread scripts/a.sh 3 path scripts/*.sh"]),
    "bash commands run and read their operands": ({
        "scripts/a.sh": 'node scripts/x.js --flag\nif timeout 5 bash scripts/y.sh; then cat config/c.json; fi\nscripts/z.sh <config/d.json\n',
        "scripts/x.js": "", "scripts/y.sh": "", "scripts/z.sh": "", "config/c.json": "{}\n", "config/d.json": "{}\n",
    }, ["+load scripts/a.sh scripts/x.js", "+load scripts/a.sh scripts/y.sh", "+load scripts/a.sh config/c.json",
        "+load scripts/a.sh scripts/z.sh", "+load scripts/a.sh config/d.json"]),
    "an array element is data": ({
        "scripts/a.sh": 'cases=(\n  scripts/x.js\n  "sound-file|shell/s.wav|logic"\n)\necho\n',
        "scripts/x.js": "", "shell/s.wav": "",
    }, ["-load scripts/a.sh scripts/x.js", "-load scripts/a.sh shell/s.wav"]),
    "quoted text is data": ({
        "scripts/a.sh": 'echo "a|scripts/x.js|b"\nx="node scripts/y.js"\nout="$(cd "$d" && node scripts/z.js)"\n',
        "scripts/x.js": "", "scripts/y.js": "", "scripts/z.js": "",
    }, ["-load scripts/a.sh scripts/x.js", "-load scripts/a.sh scripts/y.js", "+load scripts/a.sh scripts/z.js"]),
    "a comment beside a load": ({
        "scripts/a.sh": 'cat scripts/lib.sh  # cat scripts/other.sh holds the rest\n',
        "scripts/b.js": 'require("./lib.js"); // require("./other.js") holds the rest\n',
        "scripts/lib.sh": "", "scripts/lib.js": "", "scripts/other.sh": "", "scripts/other.js": "",
    }, ["+load scripts/a.sh scripts/lib.sh", "+load scripts/b.js scripts/lib.js",
        "-load scripts/a.sh scripts/other.sh", "-load scripts/b.js scripts/other.js"]),
    "a qml file is data": ({
        "shell/A.qml": 'import QtQuick\nItem { Loader { source: "B.qml" } }\n',
        "shell/B.qml": "Item {}\n",
    }, ["-unread shell/A.qml * *", "-load shell/A.qml *"]),
    "shebang languages": ({
        "bin/n": '#!/usr/bin/env node\nrequire("./lib/m.js");\n',
        "bin/lib/m.js": "",
        "bin/r": "#!/usr/bin/make -f\nall:\n",
        "bin/data": "plain\n",
    }, ["+load bin/n bin/lib/m.js", "+unread bin/r 1 interpreter", "-unread bin/data * *"]),
    "directives": ({
        "scripts/a.js": '// loads: shell/Commons/*.js -- the library is chosen by LIB\nconst path = require("path");\n'
                        'require(path.join(__dirname, "..", "shell", "Commons", process.env.LIB) + ".js");\n'
                        '// loads: shell/Ui/x.js -- the site below\n'
                        'require(path.join(__dirname, "..", "shell", "Ui", process.env.Y));\n',
        "scripts/b.sh": "# loads: shell/*\necho\n",
        "shell/Commons/Foo.js": "", "shell/Ui/x.js": "",
    }, ["+pattern scripts/a.js shell/Commons/*.js", "+pattern scripts/a.js shell/Ui/x.js", "-load scripts/a.js shell/Commons/Foo.js",
        "-unread scripts/a.js * *", "+malformed scripts/b.sh 1", "-pattern scripts/b.sh *"]),
    "a directive stands only on a comment line": ({
        "scripts/a.js": 'const fixture = `\n// loads: shell/* -- fixture text\n`;\n',
        "scripts/b.sh": "x='\n# loads: shell/* -- fixture text\n'\n"
                        "bash -c '\n# loads: scripts/k.sh -- the script sources it\nsource \"$1\"\n' _ scripts/k.sh\n",
        "scripts/k.sh": "",
    }, ["-pattern scripts/a.js *", "-pattern scripts/b.sh shell/*", "+pattern scripts/b.sh scripts/k.sh", "-unread scripts/b.sh * *"]),
    "a match pattern is no edge": ({
        "scripts/a.sh": 'case "$p" in\n  bin/b|docs/d.md) ;;\nesac\nif [[ $p == bin/* &&\n  $q != themes/t ]]; then cat shell/k.qml; fi\n',
        "shell/k.qml": "Item {}\n",
        "docs/d.md": "", "bin/b": "", "themes/t": "",
    }, ["+load scripts/a.sh shell/k.qml", "-load scripts/a.sh bin/b", "-load scripts/a.sh docs/d.md", "-load scripts/a.sh themes/t"]),
    "a checkout copy's redirect target": ({
        "scripts/a.sh": 'printf x >"$d/shell/w.qml"\ncat "$d/shell/r.qml"\n',
        "shell/w.qml": "Item {}\n", "shell/r.qml": "Item {}\n",
    }, ["+load scripts/a.sh shell/r.qml", "-load scripts/a.sh shell/w.qml"]),
    "an absent target is no load": ({
        "scripts/a.js": 'const fs = require("fs");\nfs.readFileSync("shell/Gone.js");\n',
        "shell/Here.js": "",
    }, ["-load scripts/a.js *"]),
}

# name: ((rule text in the reader, its replacement in a disposable copy),
# cases that must fail there)
MUTANTS = {
    "an unresolved require is no site": (("            self.reading.use(self.path, value, line, kind)", "            pass"),
                                         ["js require computed under the root"]),
    "an unresolved source is no site": (('                    reading.site(path, number, "source", U(P(""), glob_of(re.sub(r"\\x01([^\\x02]*)\\x02", r"\\1", re.sub(r"\\$\\{?\\w+\\}?", "*", word))) if "\\x01" in word else None))',
                                         "                    pass"), ["bash source"]),
    "a comment's path is an edge": (("            return line[:i]", "            pass"), ["a comment beside a load"]),
    "a line directive covers nothing": (("        if line - 1 in self.directives.get(loader, ()):\n            return\n",
                                         "        if line - 1 in self.directives.get(loader, ()):\n            pass\n"), ["directives"]),
    "a redirect target is a copy's read": ((' and not re.search(r"[0-9&]?>[>|]?\\s*$", plain[:copied.start()])', ''),
                                          ["a checkout copy's redirect target"]),
    "match patterns are words": (("line, state = bash_unmatched(bash_code(lines[at]), state)", "line = bash_code(lines[at])"),
                                 ["a match pattern is no edge"]),
    "array lines are commands": (("            words = [] if at in arrays else bash_command_paths(", "            words = bash_command_paths("),
                                 ["an array element is data"]),
    "quotes are no words": (("            quote, quoted = ch, True", "            pass"), ["quoted text is data"]),
    "any line is a comment line": (("match = DIRECTIVE.match(line) if number in comments else None", "match = DIRECTIVE.match(line)"),
                                   ["a directive stands only on a comment line"]),
}


def planted(path, text):
    """A change that writes TEXT at PATH under the scratch root."""
    return lambda root: plant(root, path, text)


def reader_without(old):
    """A change that removes OLD, found once, from the scratch's reader."""
    def change(root):
        with open(os.path.join(root, READER)) as handle:
            text = handle.read()
        if text.count(old) != 1:
            return f"rule not found once: {old!r}"
        plant(root, READER, text.replace(old, "", 1))
    return change


# name: ({path: text}, the file read, the change before the second
# reading, the fact the second reading must print and the first must not,
# whether the change comes first and the first reading runs the code of the
# reader before it)
STORE_CASES = {
    "a folder the tree gains": ({
        "scripts/a.js": 'const path = require("path");\nrequire(path.join(__dirname, "..", "themes", process.argv[2]));\n',
    }, "scripts/a.js", planted("themes/t.json", "{}\n"), "+unread scripts/a.js 2 require", False),
    "a file the tree gains": ({
        "scripts/a.js": 'const fs = require("fs");\nfs.readFileSync("scripts/b.js");\n',
    }, "scripts/a.js", planted("scripts/b.js", ""), "+load scripts/a.js scripts/b.js", False),
    "a command file's edit": ({
        "scripts/a.js": 'const path = require("path");\n',
    }, "scripts/a.js", planted("scripts/a.js", 'const path = require("path");\n'
                                               'require(path.join(__dirname, "..", "scripts", process.argv[2]));\n'),
        "+unread scripts/a.js 2 require", False),
    # A reader whose rule drops a package from THIRD_PARTY reads the import
    # as unread; a hit on the first reader's facts would skip that row.
    "another reader": ({
        "scripts/a.py": "import numpy\n",
    }, "scripts/a.py", reader_without('"numpy", '), "+unread scripts/a.py 1 import", False),
    # The reader edited after Python compiled it and before it read its own
    # bytes: the old code's facts keyed to the new reader would skip the row.
    "code compiled from the reader before an edit": ({
        "scripts/a.py": "import numpy\n",
    }, "scripts/a.py", reader_without('"numpy", '), "+unread scripts/a.py 1 import", True),
}

# Runs the reader file ARGV[2] as Python would, but with the code compiled
# from ARGV[1].
COMPILED_FROM = ("import sys\nsource, path = sys.argv[1:3]\nsys.argv = [path] + sys.argv[3:]\n"
                 "with open(source, 'rb') as handle:\n    code = compile(handle.read(), path, 'exec')\n"
                 "exec(code, {'__name__': '__main__', '__file__': path})\n")

STORED = "a stored entry is what a hit prints"
# Every fact kind, for the fidelity row.
STORED_FILES = {
    "scripts/a.js": '// loads: shell/*.js -- the view is chosen by X\n// loads:\nconst path = require("path");\n'
                    'require("./b.js");\nrequire(path.join(__dirname, "..", "scripts", process.argv[2]));\n',
    "scripts/b.js": "",
}

# Real loads the reading must keep, of command files.
REAL = [
    "load scripts/test-network-share.py shell/plugins/vgs.network/bin/share-qr",
    "load scripts/test-displays-brightness.py shell/plugins/vgs.displays/helper/brightness.py",
    "load scripts/test-themes-setup.js bin/lib/theme-render.js",
    "load scripts/test-vgshell-scan.py bin/vgshell-scan",
    "load scripts/test-duration.js shell/Commons/Duration.js",
    "load scripts/test-duration.js bin/lib/qml-library.js",
]


# A reading takes seconds; one past this deadline is a hang, which the
# case fails rather than waits on.
DEADLINE = 300


def facts(root, reader=READER, rows=None, compiled_from=None):
    """The reading of ROWS under ROOT, every file git lists there by
    default, with the loads of each, running the code compiled from
    COMPILED_FROM when given. The reader runs in a session of its own, so a
    hung reading's workers end with it."""
    if rows is None:
        listed = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root, env=ENV,
                                capture_output=True, text=True, check=True).stdout
        rows = [path for path in listed.split("\0") if path]
    command = ["python3", "-I", "-B", reader]
    if compiled_from is not None:
        command = ["python3", "-I", "-B", "-c", COMPILED_FROM, compiled_from, reader]
    process = subprocess.Popen(command + ["--rows"] + rows + ["--loads"] + rows, cwd=root, env=ENV,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        out, err = process.communicate(timeout=DEADLINE)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        return None, f"reading=hung deadline={DEADLINE}s"
    if process.returncode:
        return None, out + err
    return out.split("\n"), None


def holds(lines, expect):
    want = expect[1:].split()
    for line in lines:
        got = line.split()
        if len(got) >= len(want) and all(w == "*" or w == g for w, g in zip(want, got)):
            return True
    return False


def plant(root, path, text):
    os.makedirs(os.path.join(root, os.path.dirname(path)) or root, exist_ok=True)
    with open(os.path.join(root, path), "w") as handle:
        handle.write(text)
    if text.startswith("#!"):
        os.chmod(os.path.join(root, path), 0o755)


def scratch(files, base):
    root = tempfile.mkdtemp(dir=base)
    os.makedirs(os.path.join(root, "scripts"), exist_ok=True)
    # loads: scripts/row_loads.py -- the scratch copies the reader
    shutil.copy2(os.path.join(REPO, READER), os.path.join(root, READER))
    for path, text in files.items():
        plant(root, path, text)
    subprocess.run(["git", "init", "-q"], cwd=root, env=ENV, check=True)
    return root


def store_of(root):
    """The store the reader keeps for ROOT, as its docstring places it."""
    git_dir = subprocess.run(["git", "rev-parse", "--absolute-git-dir"], cwd=root, env=ENV, capture_output=True, text=True,
                             check=True).stdout.strip()
    return os.path.join(git_dir, "vgs-row-loads.json")


def fresh(root, rows):
    """A reading of ROWS with no store: the answer a stored one must give."""
    if os.path.exists(store_of(root)):
        os.unlink(store_of(root))
    return facts(root, rows=rows)


def store_case_failures(name, base):
    files, row, change, expect, old_code = STORE_CASES[name]
    root = scratch(files, base)
    if old_code:
        old = root + ".reader"
        shutil.copy2(os.path.join(root, READER), old)
        error = change(root)
        if error:
            return [error]
        first, error = facts(root, rows=[row], compiled_from=old)
    else:
        first, error = facts(root, rows=[row])
    if first is None:
        return [f"first reading failed: {error.strip()[-300:]}"]
    if not old_code:
        if not os.path.exists(store_of(root)):
            return ["the first reading left no store"]
        error = change(root)
        if error:
            return [error]
    second, error = facts(root, rows=[row])
    if second is None:
        return [f"second reading failed: {error.strip()[-300:]}"]
    expected, error = fresh(root, [row])
    if expected is None:
        return [f"fresh reading failed: {error.strip()[-300:]}"]
    found = []
    if holds(first, expect):
        found.append(f"the first reading already holds {expect}")
    if not holds(second, expect):
        found.append(f"the second reading misses {expect}")
    if second != expected:
        found.append(f"the second reading differs from a fresh one: {sorted(set(second) ^ set(expected))[:4]}")
    return found


def stored_failures(base):
    """A hit prints every fact field of its entry: entries rewritten in
    place, with no key computed here, show through. A store of another top-level shape,
    and entries missing a field, are read as no store."""
    rows = ["scripts/a.js"]
    root = scratch(STORED_FILES, base)
    cold, error = facts(root, rows=rows)
    if cold is None:
        return [f"cold reading failed: {error.strip()[-300:]}"]
    found = [f"the fixture lacks a {kind} fact" for kind in ("load", "pattern", "unread", "malformed")
             if not holds(cold, f"+{kind} scripts/a.js *")]
    if not os.path.exists(store_of(root)):
        return found + ["the cold reading left no store"]
    with open(store_of(root)) as handle:
        store = json.load(handle)
    for entry in store.values():
        entry.update(loads=["planted/load.js"], patterns=["planted/*"], unread=[[1, "planted", "-"]], malformed=[9])
    with open(store_of(root), "w") as handle:
        json.dump(store, handle)
    warm, error = facts(root, rows=rows)
    if warm is None:
        found.append(f"warm reading failed: {error.strip()[-300:]}")
    else:
        found += [f"a planted fact does not show: {fact}" for fact in
                  ("+load scripts/a.js planted/load.js", "+pattern scripts/a.js planted/*",
                   "+unread scripts/a.js 1 planted -", "+malformed scripts/a.js 9") if not holds(warm, fact)]
    expected, error = fresh(root, rows)
    if expected is None:
        return found + [f"fresh reading failed: {error.strip()[-300:]}"]
    if expected != cold:
        found.append("a fresh reading differs from the cold one")
    damages = (("a store of another shape", lambda store: []),
               ("entries missing a field", lambda store: {key: {field: value for field, value in entry.items() if field != "unread"}
                                                          for key, entry in store.items()}))
    for damage, damaged in damages:
        with open(store_of(root)) as handle:
            store = json.load(handle)
        if not store:
            found.append(f"{damage}: no stored entry to damage")
            continue
        with open(store_of(root), "w") as handle:
            json.dump(damaged(store), handle)
        lines, error = facts(root, rows=rows)
        if lines is None or lines != expected or holds(lines, "+failed *"):
            found.append(f"{damage}: the reading differs from a fresh one: {error or sorted(set(lines) ^ set(expected))[:4]}")
    return found


def case_failures(name, base, mutate=None):
    """The expectations case NAME misses, or with MUTATE, the rule text a
    disposable copy of the reader replaces, why that copy is no control."""
    files, expects = CASES[name]
    root = scratch(files, base)
    if mutate is not None:
        old, new = mutate
        with open(os.path.join(root, READER)) as handle:
            text = handle.read()
        if text.count(old) != 1:
            return None, f"rule not found once: {old!r}"
        with open(os.path.join(root, READER), "w") as handle:
            handle.write(text.replace(old, new, 1))
    lines, error = facts(root)
    if lines is None:
        return None, f"reader failed: {error.strip()[-300:]}"
    return [e for e in expects if holds(lines, e) != e.startswith("+")], None


def main():
    failures = 0
    base = tempfile.mkdtemp(prefix="test-row-loads.", dir=os.environ.get("TMPDIR"))
    only = set(sys.argv[1:])
    unknown = only - set(CASES) - set(MUTANTS) - set(STORE_CASES) - {STORED}
    if unknown:
        print(f"test-row-loads: refused: case={sorted(unknown)[0]}")
        return 2
    try:
        for name in [n for n in CASES if not only or n in only]:
            missed, error = case_failures(name, base)
            for finding in missed if error is None else [error]:
                print(f"FAIL {name}: {finding}")
                failures += 1
        for name, (rule, cases) in [(n, m) for n, m in MUTANTS.items() if not only or n in only]:
            for case in cases:
                missed, error = case_failures(case, base, mutate=rule)
                if error is not None:
                    print(f"FAIL control: {name}: {error}")
                    failures += 1
                elif not missed:
                    print(f"FAIL control: {name}: case {case} passes with the rule removed")
                    failures += 1
        for name in [n for n in STORE_CASES if not only or n in only]:
            for finding in store_case_failures(name, base):
                print(f"FAIL {name}: {finding}")
                failures += 1
        if not only or STORED in only:
            for finding in stored_failures(base):
                print(f"FAIL {STORED}: {finding}")
                failures += 1
        if only:
            return report(failures)
        # A file the reading cannot read ends it with that file's
        # `unreadable` fact, from whichever worker read it: a worker's
        # failure must reach the reading, which must not wait on it.
        root = scratch({"scripts/locked.sh": "echo locked\n", "scripts/open.sh": "echo open\n"}, base)
        os.chmod(os.path.join(root, "scripts", "locked.sh"), 0)
        lines, error = facts(root)
        os.chmod(os.path.join(root, "scripts", "locked.sh"), 0o644)
        if lines is None or "unreadable path=scripts/locked.sh cause='Permission denied'" not in lines:
            print(f"FAIL an unreadable file: {error or 'no unreadable fact'}")
            failures += 1
        # A file git does not list under that spelling, or at all, is no
        # reading of the row that names it.
        root = scratch({"scripts/a.sh": "echo a\n"}, base)
        for request in ("./scripts/a.sh", "scripts/no-such-file.sh"):
            lines, error = facts(root, rows=[request])
            if lines is None or f"unreadable path={request} cause=not-listed" not in lines:
                print(f"FAIL a request outside the inventory: {request}: {error or 'no unreadable fact'}")
                failures += 1
        # A file whose reading raises names that file in its failure.
        root = scratch({"scripts/a.js": 'require("./b c.js");\n', "scripts/b c.js": ""}, base)
        lines, error = facts(root, rows=["scripts/a.js"])
        if lines is None or not any(line.startswith("failed operation=load-reading path=scripts/a.js kind=RuntimeError ")
                                    for line in lines):
            print(f"FAIL a failed reading names its file: {error or 'no failed fact'}")
            failures += 1
        lines, error = facts(REPO, rows=sorted({fact.split()[1] for fact in REAL}))
        if lines is None:
            print(f"FAIL real tree: reader failed: {error.strip()[-300:]}")
            failures += 1
        else:
            for fact in REAL:
                if fact not in lines:
                    print(f"FAIL real tree: missing {fact}")
                    failures += 1
    finally:
        shutil.rmtree(base, ignore_errors=True)
    return report(failures)


def report(failures):
    print("test-row-loads: ok" if not failures else f"test-row-loads: failed={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
