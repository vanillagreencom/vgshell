#!/usr/bin/env python3
"""The load reading of scripts/validate's table rows and nested smoke rows,
and the one reader of the relation between smoke rows.

Run from the repository root as `python3 -I -B scripts/row_loads.py --rows
FILE... [--loads FILE...]`, `--smoke ROW...`, `--harness`, `--row-reads
ROW... [--unlisted BASE NAME...]` or `--harness-reach BASE PATH ROW...`. It reads each FILE, a table row's command file,
under the loading boundary table below, and never a file those load in
turn. For each FILE it prints `unread FILE LINE KIND GLOB` for a load site
no `loads:` directive covers, with `-` for a value whose glob it cannot
tell, and `malformed FILE LINE` for a malformed directive. For each FILE
named after --loads as well it prints `load FILE TARGET` for each tracked
file a load operation of FILE names, and `pattern FILE GLOB` for each glob
of its directives. scripts/validate is the caller: table_unread_read reads
the unread facts and table_cover the loads.

--smoke prints each listed ROW's facts, walked as § The smoke rows below
gives: `input ROW PATH`, `pattern ROW GLOB`, `plugin ROW FOLDER`, `reads
ROW NEEDED function|variable|state`, `unread ROW FILE LINE KIND GLOB`,
`malformed ROW FILE LINE` and `unparsed FILE`; smoke_rows_read in
scripts/validate files them. --harness prints the harness's own inputs:
`harness PATH`, `harness-glob GLOB`, `harness-unread FILE LINE KIND GLOB`
and `harness-malformed FILE LINE`. --row-reads prints only the `reads` and
`unparsed` facts, which scripts/qml-smoke.sh closes --rows over; a NAME
after --unlisted, a row rows.list no longer holds, counts as a definer,
read from the tree or else from BASE, and only its readers print.
--harness-reach prints `reach ROW` for each row a function-level change
to the harness file PATH against BASE reaches, or `harness` for every row.

A FILE that is not a regular file git lists under that spelling, or a
reading that cannot finish, prints one `unreadable path=<path> cause=<cause>`
or `failed operation=<operation> ...` fact in place of the reading. -B: the
reading writes no bytecode into the tree it reads.

Each file's facts are kept outside the tree, in vgs-row-loads.json in the
worktree's git directory, and reused while the reader, the file and every
inventory answer its reading asked are unchanged: § The stored reading
below. A store it cannot read or write is no fault and prints nothing.
"""
import ast, bisect, concurrent.futures, ctypes, fnmatch, functools, json, multiprocessing, os, re, shlex, signal, subprocess, sys, tokenize, io, hashlib, tempfile

# The reader's own bytes, part of every stored fact's key. Python compiled
# this module from an earlier read of the file, so an edit between that read
# and this one would key the old code's facts to the new bytes: the store is
# used only when the bytes compile to the code running here. CPython compares
# code objects by their compiled content, nested functions' code included
# (code_richcompare, Objects/codeobject.c); recorded run, CPython 3.14.10: a
# normal run compares equal, and code compiled from bytes whose module or
# method body differs does not. An edit after this read is harmless: the
# facts are keyed to the bytes that compiled them.
with open(__file__, "rb") as _own:
    READER_BYTES = _own.read()
READER_RUNS = compile(READER_BYTES, __file__, "exec") == sys._getframe(0).f_code


class Unreadable(Exception):
    """A file the reading cannot read, with the cause."""

    def __init__(self, path, strerror):
        super().__init__(f"{path}: {strerror}")
        self.path, self.strerror = path, strerror


def inventory():
    """What git tracks or would add, never an ignored file: the paths a
    reading may name, those that are regular files, and their folders."""
    listed = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                            capture_output=True)
    if listed.returncode:
        raise subprocess.CalledProcessError(listed.returncode, "git-ls-files", stderr=listed.stderr.decode(errors="replace"))
    paths = sorted({path for path in listed.stdout.decode("utf-8", "surrogateescape").split("\0") if path})
    present = {path for path in paths if os.path.isfile(path)}
    folders = {""}
    for path in paths:
        folder = os.path.dirname(path)
        while folder and folder not in folders:
            folders.add(folder)
            folder = os.path.dirname(folder)
    return paths, present, folders


def read_bytes(path):
    """PATH's bytes: the one read of a command file, which its key, its
    language and its text all take, so a save while the reading runs
    cannot key one content's facts to another's bytes."""
    try:
        with open(path, "rb") as source:
            return source.read()
    except OSError as exc:
        raise Unreadable(path, exc.strerror or str(exc)) from exc


def decoded(path, data):
    try:
        return data.decode("utf-8-sig")
    except UnicodeError as exc:
        raise Unreadable(path, str(exc)) from exc

# ---------------------------------------------------------------------------
# The supported loading boundary: the direct loads of a command file.
#
# Each operation below resolves to a `load` of a tracked file, or it is
# `unread`: a load site the reading cannot follow, which makes the row
# whose command names the file run on every change (table_unread_read in
# scripts/validate). A `loads: GLOB... -- REASON` comment line (`#`, or
# `//` in JavaScript) directly above a site covers it; a directive whose
# globs use only `*` and hold every path the site can name covers it from
# anywhere in the file. A directive with no glob, no ` -- ` or no reason
# is `malformed`, and its row runs on every change too. A directive stands
# only on a whole comment line of the file's language or of code it embeds:
# a node or quoted python heredoc, or a `bash -c` script. Text that looks
# like a directive in any other string or heredoc is none.
#
#   language  operation                                   resolved  otherwise
#   JS        require(X), import ... from X, import(X)    load      unread
#             (a node built-in is no repository load;
#             a bare name is unread)
#   JS        qml-library.js load/closure, any binding    load      unread
#   JS        a call's argument, or an element of an      load      unread
#             array that is one, such as a spawned
#             command's words or a file read
#   JS        path.join/resolve/dirname, +, templates,    a value   -
#             __dirname, process.cwd(), const/let/var
#   JS        fs readdir/opendir/cp/glob of a folder      -         unread
#   JS        vm, eval, new Function over a file read     load      unread
#   Python    import, from ... import: the file's         load      unread unless
#             folder, scripts/, a literal sys.path                  stdlib or
#             folder                                                THIRD_PARTY
#   Python    importlib, runpy, imp, __import__,          load      unread
#             SourceFileLoader, spec_from_file_location
#   Python    exec/compile of a file read                 load      unread
#   Python    a call's argument, or an element of a       load      unread
#             list or tuple that is one
#   Python    Path / x, os.path.join, __file__, parent,   a value   -
#             f-strings, one binding level
#   Python    os.listdir/scandir/walk, glob, iterdir,     -         unread
#             rglob, shutil.copytree of a folder
#   Bash      source X, . X                               load      unread
#   Bash      a command word, an interpreter's script     load      -
#             and a read or copy command's operands
#             (BASH_READERS)
#   Bash      a path under $repo-style variables,         load      unread
#             BASH_SOURCE, $(dirname ...), $(cd ... &&
#             pwd), or under a copy of the checkout,
#             that a command uses
#   Bash      a python3 or node heredoc                   as Python/JS  unread when
#                                                                       it cannot be
#                                                                       parsed
#   shebang   an extensionless file: bash, sh, node,      as that   unread for
#             python3; no shebang, or another extension,  language  another
#             is data                                               interpreter
#
# A Bash `case` arm's patterns and the operand of `==`, `!=`, `=` or `=~`
# in `[[ ]]` match a string and read no file: they make no load.
#
# A value is a load where a call or a command uses it: a file it names is a
# load, and a folder, a target the tree lacks or a value at a path builder,
# a binding or an existence check loads nothing. A value the reading cannot
# resolve is `unread` at its use only when it is anchored: built from the
# repository root, a file's folder or __dirname, with a known part that
# names a folder the inventory holds. A value with no such part, such as a
# path under a temporary copy, names no repository file; the copy is a load
# where it is made. A literal path word anywhere else, in a comment, a
# message, a data table, a Bash array element or quoted word, or a
# fixture's text, is no load.
#
# The gaps, which review holds: what a file the command files load loads in
# turn; a folder's members a call enumerates; a data file read through a
# computed path no load site names; and a load through an operation this
# table does not name, such as a Bash function that runs its arguments.
# ---------------------------------------------------------------------------

NODE_BUILTINS = set()
# Python packages outside the standard library that no repository file
# provides: the only ones the repository imports.
THIRD_PARTY = {"cups", "dbus", "gi", "numpy", "onnxruntime", "PIL", "sherpa_onnx", "tokenizers", "transformers"}
DIRECTIVE = re.compile(r"^[ \t]*(?:#|//)[ \t]*loads:(.*)$")
GLOB = re.compile(r"[*?\[]")


class P(str):
    """A repository path, relative to its root ("" is the root)."""


class Str(str):
    """A string value that is not yet a path."""


class U:
    """A value the reading cannot resolve; `prefix` is the repository folder
    its known part names when it is anchored, else None, and `glob` the
    repository glob of every path it can name, its known parts kept and each
    unknown part `*`, when the reading can tell. `copied` is the relative
    path a value with no anchor joins to its unknown base, which names the
    repository file of that path when the base is a copy of the checkout or
    the checkout passed in."""

    def __init__(self, prefix=None, glob=None, copied=None):
        self.prefix, self.glob, self.copied = prefix, glob, copied

    def names(self):
        """The glob of what an anchored value can name."""
        if self.glob is not None:
            return self.glob or "*"
        return "*" if not self.prefix else self.prefix + "/*"


def glob_of(text):
    path = norm(text)
    return None if path is None else (path or "*")


def norm(text):
    """A repository path from TEXT relative to the root, or None outside it."""
    if text.startswith("/"):
        return None
    path = os.path.normpath(text or ".")
    if path == ".":
        return P("")
    if path.startswith("../") or path == "..":
        return None
    return P(path)


def known(value):
    """VALUE, or an unresolved value for None: the root, P(""), is a path
    though an empty string is false."""
    return U() if value is None else value


def joined(base, *parts):
    return norm(os.path.join(base or ".", *parts))


def anchored(*values):
    """The first anchored folder among VALUES, a P or a U's prefix."""
    for value in values:
        if isinstance(value, P):
            return value
        if isinstance(value, U) and value.prefix is not None:
            return value.prefix
    return None


def concat(parts):
    """A + chain, a template or an f-string of resolved PARTS."""
    if not parts:
        return Str("")
    first = parts[0]
    if isinstance(first, U):
        if first.prefix is None and len(parts) > 1 and all(isinstance(part, Str) for part in parts[1:]):
            return U(copied=norm("".join(parts[1:]).lstrip("/")))
        if first.prefix is None or first.glob is None:
            return U(first.prefix)
        raw, prefix = first.glob, first.prefix
    else:
        raw = ("." if first == "" else first) if isinstance(first, P) else str(first)
        prefix = None
    if any(isinstance(part, Str) and re.search(r"\s|=", part) for part in parts):
        # Text with a space or a key=value field is a message, not a path.
        return U()
    for part in parts[1:]:
        if isinstance(part, U):
            if not isinstance(first, (P, U)):
                # A relative path with an unknown part: its glob, which a
                # path builder anchors.
                rest = "*".join(str(p) if isinstance(p, Str) else "" for p in parts[parts.index(part) + 1:] if not isinstance(p, P))
                return U(None, raw + "*" + rest) if "/" in raw + rest and not any(isinstance(p, P) for p in parts) else U()
            if prefix is None:
                prefix = norm(raw if raw.endswith("/") else os.path.dirname(raw))
            raw += "*"
        elif isinstance(part, P):
            return U(prefix if prefix is not None else (norm(raw) if isinstance(first, P) else None))
        else:
            raw += part
    if prefix is not None or isinstance(first, U):
        return U(prefix, glob_of(raw))
    return norm(raw) if isinstance(first, P) else Str(raw)


def join_values(values, resolve=False):
    """path.join, path.resolve or os.path.join of resolved VALUES."""
    current = None
    for index, value in enumerate(values):
        if isinstance(value, U):
            if index == 0 and value.prefix is not None:
                prefix, glob = value.prefix, (value.glob if value.glob is not None else value.names())
            elif isinstance(current, P):
                prefix = current
                glob = os.path.join(current or ".", value.glob if value.prefix is None and value.glob else "*")
            elif index == 0 and len(values) > 1 and all(isinstance(rest, Str) and not rest.startswith("/") for rest in values[1:]):
                return U(copied=norm(os.path.join(*values[1:])))
            else:
                return U()
            for rest in values[index + 1:]:
                if isinstance(rest, Str) and not rest.startswith("/"):
                    glob = os.path.join(glob, rest)
                elif isinstance(rest, U):
                    glob = os.path.join(glob, "*")
                else:
                    return U(prefix)
            return U(prefix, glob_of(glob))
        if isinstance(value, P):
            current = value
            continue
        if value.startswith("/"):
            return U()
        if current is None:
            current = joined("", value) if resolve else Str(value)
        elif isinstance(current, P):
            current = joined(current, value)
        else:
            current = Str(os.path.join(current, value))
        if current is None:
            return U()
    if current is None:
        return P("") if resolve else U()
    return Str(os.path.normpath(current)) if isinstance(current, Str) else current


class Bindings:
    """Each name's values by where each binding ends. A use reads the
    nearest binding before it: block and function scopes approximated by
    text order, which follows a name rebound in each function or block
    without merging its values. A use before every binding is a parameter
    or another scope's name, which the reading cannot resolve."""

    def __init__(self):
        self.names = {}

    def bind(self, name, position, value):
        positions, values = self.names.setdefault(name, ([], []))
        at = bisect.bisect_right(positions, position)
        positions.insert(at, position)
        values.insert(at, value)

    def get(self, name, position):
        if name not in self.names:
            return U()
        positions, values = self.names[name]
        at = bisect.bisect_left(positions, position) - 1
        return values[at] if at >= 0 else U()

    def items(self):
        for name, (_, values) in self.names.items():
            for value in values:
                yield name, value

    def values(self):
        return [value for _, value in self.items()]


class Asked:
    """An inventory set a reading may only ask membership of, recording each
    value it asks and the answer: what a stored reading's reuse checks. Any
    other use, such as iterating or sizing it, raises and fails the reading,
    so no reader path can depend on the inventory past this record."""

    def __init__(self, members):
        self.members, self.answers = members, {}

    def __contains__(self, value):
        if value is not None and not isinstance(value, str):
            # The store holds each question as JSON, a string or null.
            raise RuntimeError(f"inventory question of a {type(value).__name__}")
        answer = self.answers[value] = value in self.members
        return answer


class Reading:
    """The facts of one reading of command files."""

    def __init__(self, present, folders):
        self.present, self.folders = present, folders
        self.loads, self.patterns, self.unread, self.malformed, self.directives, self.declared = {}, {}, {}, {}, {}, {}
        self.inproc, self.missing = {}, {}

    def edge(self, loader, target, inproc=False):
        """A load of TARGET when it is a tracked file, in the loader's own
        process when INPROC: a source, an import or a require. A folder
        loads nothing. A target the tree lacks is `missing`: the smoke
        reading keeps it as a literal input, so the change that removed a
        file a row still names reaches the row."""
        if target is None or target == loader:
            return
        if target not in self.present:
            if target and target not in self.folders and not GLOB.search(target) and not any(ch.isspace() for ch in target):
                self.missing.setdefault(loader, set()).add(target)
            return
        if any(ch.isspace() for ch in target):
            # A fact is space-delimited; no tracked path holds a space today.
            raise RuntimeError(f"load target holds a space: {target!r}")
        self.loads.setdefault(loader, set()).add(target)
        if inproc:
            self.inproc.setdefault(loader, set()).add(target)

    def use(self, loader, value, line, kind="path", inproc=False):
        """VALUE used at a call or a command: a load of the file it names,
        or a site when it is anchored and unresolved."""
        if isinstance(value, Str):
            value = norm(value) if "/" in value else None
        if isinstance(value, P):
            self.edge(loader, value, inproc)
        elif isinstance(value, U):
            # One name under an unknown base is any folder's file, such as
            # a fixture home's AGENTS.md; a layout names the checkout's.
            if value.copied is not None and "/" in value.copied and value.copied in self.present:
                self.edge(loader, value.copied, inproc)
            else:
                self.site(loader, line, kind, value)

    def site(self, loader, line, kind, value=None):
        """A load site the reading cannot follow, unless VALUE is a value
        whose known part names no folder the inventory holds."""
        if isinstance(value, U) and (value.prefix is None or value.prefix not in self.folders):
            return
        if callable(line):
            line = line()
        if line - 1 in self.directives.get(loader, ()):
            return
        # A directive of the file whose pattern holds every path the value
        # can name covers it: its known parts match the pattern's.
        names = value.names() if isinstance(value, U) else None
        if names is not None and any(fnmatch.fnmatchcase(names, glob) or fnmatch.fnmatchcase(names + "/*", glob)
                                     for glob in self.declared.get(loader, ())):
            return
        self.unread.setdefault(loader, set()).add((line, kind, names or "-"))

    def read_directives(self, loader, text, comments):
        """The `loads:` directives on COMMENTS, the numbers of the lines of
        TEXT that are whole comments in its language."""
        lines = set()
        if "loads:" in text:
            for number, line in enumerate(text.split("\n"), 1):
                match = DIRECTIVE.match(line) if number in comments else None
                if not match:
                    continue
                globs, separator, reason = match.group(1).partition(" -- ")
                globs = globs.split()
                if not separator or not reason.strip() or not globs:
                    self.malformed.setdefault(loader, set()).add(number)
                    continue
                lines.add(number)
                for glob in globs:
                    self.patterns.setdefault(loader, set()).add(glob)
                    if not re.search(r"[?\[]", glob):
                        self.declared.setdefault(loader, []).append(glob)
        self.directives[loader] = lines



# --- JavaScript ----------------------------------------------------------------

# Comments, strings, templates and regular expression literals, read by one
# scan so that each is skipped whole: qml_source.blank_comments reads the
# same shapes character by character, too slowly for every file of the tree.
JS_TOKEN = re.compile(r"//[^\n]*|/\*[\s\S]*?(?:\*/|\Z)|\"(?:\\.|[^\"\\\n])*\"?|'(?:\\.|[^'\\\n])*'?|`(?:\\[\s\S]|[^`\\])*`?|/")
JS_REGEX = re.compile(r"/(?:\\.|\[(?:\\.|[^\]\\\n])*\]|[^/\\\n\[])+/[a-z]*")
REGEX_AFTER = set("(,=:[!&|?{};~+-*%<>^")
REGEX_AFTER_WORDS = {"return", "typeof", "case", "in", "of", "delete", "void", "throw", "new", "else", "do", "yield", "await", "instanceof"}


def before(text, at, width=40):
    """The code just before AT, trailing whitespace stripped: a bounded
    look-behind, since a slice from the start costs the whole file."""
    return text[max(0, at - width):at].rstrip()


def blank(text):
    """TEXT with every character but a line break made a space."""
    return " " * len(text) if "\n" not in text else re.sub(r"[^\n]", " ", text)


def js_mask(text):
    """TEXT with comments blanked (`code`), and with literal contents blanked
    as well (`shape`), offsets and line breaks kept."""
    code, shape = [], []
    at = done = 0
    while True:
        match = JS_TOKEN.search(text, at)
        if not match:
            break
        token, lo = match.group(0), match.start()
        if token == "/":
            prior = before(text, lo)
            word = re.search(r"[\w$]+$", prior)
            if not prior or prior[-1] in REGEX_AFTER or (word and word.group(0) in REGEX_AFTER_WORDS):
                literal = JS_REGEX.match(text, lo)
                if literal:
                    hi = literal.end()
                    code.append(text[done:hi])
                    shape.append(text[done:lo + 1] + blank(text[lo + 1:hi - 1]) + text[hi - 1:hi])
                    at = done = hi
                    continue
            at = lo + 1
            continue
        hi = match.end()
        head = text[done:lo]
        if token.startswith(("//", "/*")):
            code.append(head + blank(token))
            shape.append(head + blank(token))
        else:
            code.append(text[done:hi])
            shape.append(head + token[:1] + blank(token[1:-1]) + token[-1:] if len(token) > 1 else head + token)
        at = done = hi
    code.append(text[done:])
    shape.append(text[done:])
    return "".join(code), "".join(shape)


JS_CALL = re.compile(r"(?<![\w$])((?:[A-Za-z_$][\w$]*)(?:\s*\??\.\s*[A-Za-z_$][\w$]*)*)\s*\(")
JS_NOT_CALLS = {"if", "for", "while", "switch", "catch", "function", "return", "typeof", "with", "await",
                "yield", "do", "else", "case", "throw", "delete", "void", "in", "of", "super", "constructor"}
JS_BUILDERS = {"path.join", "path.resolve", "path.dirname", "path.normalize", "path.relative", "path.basename",
               "path.extname", "path.parse", "path.isAbsolute", "require.resolve", "String", "JSON.stringify",
               "fileURLToPath", "pathToFileURL", "Number", "Boolean", "Array.isArray", "Object.keys"}
# Calls whose first argument is a place to write or a path to test, never
# code or data the row reads.
JS_BASE_ONLY = {"existsSync", "statSync", "lstatSync", "accessSync", "realpathSync", "mkdirSync", "mkdtempSync",
                "rmSync", "rmdirSync", "unlinkSync", "writeFileSync", "appendFileSync", "chmodSync", "chdir",
                "mkdir", "rm", "writeFile", "appendFile", "access", "stat", "lstat", "startsWith", "endsWith",
                "includes", "indexOf", "relative", "equal", "strictEqual", "notEqual", "ok", "match", "push",
                "has", "add", "set", "get", "log", "error", "warn", "info", "replace", "replaceAll", "split", "join",
                "symlinkSync", "renameSync", "copyFileSync", "cpSync", "utimesSync", "openSync", "createWriteStream"}
JS_ENUMERATE = {"readdirSync", "readdir", "opendirSync", "opendir", "cpSync", "cp", "globSync", "glob"}
JS_COPY_SOURCE = {"copyFileSync", "copyFile", "cpSync", "cp", "symlinkSync"}
JS_EVAL = {"vm.runInThisContext": "vm", "vm.runInNewContext": "vm", "vm.runInContext": "vm",
           "vm.compileFunction": "vm", "vm.Script": "vm", "vm.SourceTextModule": "vm", "eval": "eval",
           "Function": "eval", "Module._load": "module", "Module._compile": "module", "module._compile": "module",
           "createRequire": "module", "module.createRequire": "module"}
JS_BINDING = re.compile(r"\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*")
JS_DESTRUCTURE = re.compile(r"\b(?:const|let|var)\s*\{([^{}]*)\}\s*=\s*")
JS_ESM = re.compile(r"^[ \t]*(?:import|export)\b[^;'\"`]*?\bfrom\s*([\"'])([^\"'\n]+)\1|^[ \t]*import\s*([\"'])([^\"'\n]+)\3", re.M)
JS_VALUE_START = re.compile(r"(?<![\w$.])(?:__dirname|__filename|path\s*\.\s*(?:join|resolve))\b")
JS_REQUIRE_AT = re.compile(r"require\s*\(")
QML_LIBRARY = "bin/lib/qml-library.js"


def js_close(shape, at):
    """The offset after the bracket that closes SHAPE[at], or None."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    stack = []
    for i in range(at, len(shape)):
        ch = shape[i]
        if ch in pairs:
            stack.append(pairs[ch])
        elif ch in ")]}":
            if not stack or stack.pop() != ch:
                return None
            if not stack:
                return i + 1
    return None


def js_split(shape, lo, hi, separator):
    """Top-level SEPARATOR offsets of SHAPE[lo:hi]."""
    cuts, depth, i = [], 0, lo
    while i < hi:
        ch = shape[i]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif depth == 0 and shape.startswith(separator, i):
            cuts.append(i)
            i += len(separator)
            continue
        i += 1
    return cuts


def js_operators(shape, lo, hi):
    """The top-level offsets of ||, ??, ? and + in SHAPE[lo:hi], one pass."""
    found = {"||": [], "??": [], "?": [], "+": []}
    depth, i = 0, lo
    while i < hi:
        ch = shape[i]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif depth == 0 and ch in "|?+":
            pair = shape[i:i + 2]
            if pair in ("||", "??"):
                found[pair].append(i)
                i += 2
                continue
            if ch == "?" and pair != "?.":
                found["?"].append(i)
            elif ch == "+" and pair != "++" and shape[i - 1:i] != "+" and pair != "+=":
                found["+"].append(i)
        i += 1
    return found


def js_expression_end(shape, lo):
    """The end of the expression at LO: a top-level , ; ) ] } or line end."""
    depth = 0
    for i in range(lo, len(shape)):
        ch = shape[i]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                return i
            depth -= 1
        elif depth == 0 and ch in ",;\n":
            return i
    return len(shape)


def js_unquote(literal):
    return re.sub(r"\\(.)", r"\1", literal[1:-1])


class JsFile:
    def __init__(self, reading, path, text, offset=0, here=None, masked=None):
        self.reading, self.path, self.offset = reading, path, offset
        self.code, self.shape = masked or js_mask(text)
        self.here = os.path.dirname(path) if here is None else here
        self.env, self.qml_names, self.qml_spaces = Bindings(), set(), set()
        self.lines = self.naming = self.closes = None

    def line(self, at):
        if self.lines is None:
            self.lines = [m.start() for m in re.finditer("\n", self.code)]
        return self.offset + bisect.bisect_left(self.lines, at) + 1

    def value(self, lo, hi):
        code, shape = self.code, self.shape
        while lo < hi and code[lo].isspace():
            lo += 1
        while hi > lo and code[hi - 1].isspace():
            hi -= 1
        if lo >= hi:
            return U()
        if shape[lo] == "(" and js_close(shape, lo) == hi:
            return self.value(lo + 1, hi - 1)
        operators = js_operators(shape, lo, hi)
        for alternative in ("||", "??"):
            cuts = operators[alternative]
            if cuts:
                parts = [self.value(a, b) for a, b in zip([lo] + [c + 2 for c in cuts], cuts + [hi])]
                return U(anchored(*parts))
        if operators["?"]:
            return U()
        cuts = operators["+"]
        if cuts:
            return concat([self.value(a, b) for a, b in zip([lo] + [c + 1 for c in cuts], cuts + [hi])])
        text = code[lo:hi]
        if text[0] in "\"'" and text[-1] == text[0] and len(text) >= 2:
            return Str(js_unquote(text))
        if text[0] == "`" and text[-1] == "`" and len(text) >= 2:
            if "${" not in text:
                return Str(text[1:-1])
            parts, at = [], 1
            for match in re.finditer(r"\$\{([^{}`]*)\}", text):
                parts.append(Str(text[at:match.start()]))
                inner = lo + match.start(1)
                parts.append(self.value(inner, inner + len(match.group(1))))
                at = match.end()
            parts.append(Str(text[at:-1]))
            return concat([p for p in parts if not (isinstance(p, Str) and not p)])
        if text == "__dirname":
            return P(self.here)
        if text == "__filename":
            return P(self.path)
        if re.fullmatch(r"process\s*\.\s*cwd\s*\(\s*\)", text):
            return P("")
        if re.fullmatch(r"[A-Za-z_$][\w$]*", text):
            return self.env.get(text, lo)
        call = re.compile(r"(?:path|nodePath)\s*\.\s*(join|resolve|dirname|normalize)\s*\(").match(code, lo)
        if call and js_close(shape, call.end() - 1) == hi:
            values = [self.value(a, b) for a, b in self.args(call.end() - 1)]
            name = call.group(1)
            if name == "dirname":
                v = values[0] if values else U()
                if isinstance(v, (P, Str)):
                    return type(v)(os.path.dirname(v))
                if v.glob is not None:
                    parent, prefix = os.path.dirname(v.glob), v.prefix
                    if prefix is not None and len(parent) < len(prefix):
                        prefix = P(parent)
                    return U(prefix, parent or None)
                return U(v.prefix and P(os.path.dirname(v.prefix)))
            return join_values(values, resolve=name == "resolve")
        resolve = re.compile(r"require\s*\.\s*resolve\s*\(").match(code, lo)
        if resolve and js_close(shape, resolve.end() - 1) == hi:
            args = self.args(resolve.end() - 1)
            target = self.module(args[0]) if args else U()
            return target if isinstance(target, (P, U)) else U()
        return U()

    def may_name(self, lo, hi):
        """Whether CODE[lo:hi] can name a repository path: a path builder,
        a literal with a slash, or a binding that holds a path."""
        if self.naming is None:
            names = [re.escape(n) for n, v in self.env.items()
                     if isinstance(v, P) or (isinstance(v, Str) and "/" in v) or (isinstance(v, U) and v.prefix is not None)]
            self.naming = re.compile(r"__dirname|__filename|process\s*\.\s*cwd|\bpath\s*\.|require|[\"'`][^\"'`\n]*/" +
                                     (r"|(?<![\w$.])(?:" + "|".join(names) + r")(?![\w$])" if names else ""))
        return self.naming.search(self.code, lo, hi) is not None

    def close(self, open_at):
        """The offset after the bracket that closes SHAPE[open_at]: one
        pass over the file pairs every bracket."""
        if self.closes is None:
            self.closes, stack = {}, []
            for bracket in re.finditer(r"[(){}\[\]]", self.shape):
                if bracket.group(0) in "([{":
                    stack.append(bracket.start())
                elif stack:
                    self.closes[stack.pop()] = bracket.start() + 1
        return self.closes.get(open_at)

    def elements(self, lo, hi):
        """The element spans of CODE[lo:hi] when it is an array literal."""
        while lo < hi and self.code[lo].isspace():
            lo += 1
        while hi > lo and self.code[hi - 1].isspace():
            hi -= 1
        if lo >= hi or self.shape[lo] != "[" or self.close(lo) != hi:
            return []
        inner_lo, inner_hi = lo + 1, hi - 1
        if not self.code[inner_lo:inner_hi].strip():
            return []
        cuts = js_split(self.shape, inner_lo, inner_hi, ",")
        return [(a, b) for a, b in zip([inner_lo] + [c + 1 for c in cuts], cuts + [inner_hi])]

    def args(self, open_at):
        close = self.close(open_at)
        if close is None:
            return []
        lo, hi = open_at + 1, close - 1
        if not self.code[lo:hi].strip():
            return []
        cuts = js_split(self.shape, lo, hi, ",")
        return [(a, b) for a, b in zip([lo] + [c + 1 for c in cuts], cuts + [hi])]

    def module(self, span):
        """A require or import argument: the file it loads, `builtin`, or
        an unresolved value."""
        value = self.value(*span) if isinstance(span, tuple) else span
        if isinstance(value, U) and value.prefix is None and value.glob and value.glob.startswith(("./", "../")):
            # A specifier relative to this file, with an unknown part.
            return U(P(self.here), glob_of(os.path.join(self.here or ".", value.glob)))
        if isinstance(value, Str):
            if value.startswith("node:") or value.split("/")[0] in NODE_BUILTINS:
                return "builtin"
            if not value.startswith(("./", "../")):
                return U(P(""))
            value = joined(self.here, value)
            if value is None:
                return U()
        if isinstance(value, P):
            for candidate in (value, value + ".js", value + ".json", value + "/index.js"):
                if candidate in self.reading.present:
                    return P(candidate)
        return value

    def bind(self):
        handled = set()
        for match in JS_BINDING.finditer(self.shape):
            lo = match.end()
            hi = js_expression_end(self.shape, lo)
            handled.add(lo)
            value, name = self.value(lo, hi), match.group(1)
            self.env.bind(name, hi, value)
            required = JS_REQUIRE_AT.match(self.code, lo)
            if required and self.close(required.end() - 1) == hi:
                args = self.args(required.end() - 1)
                if args and self.module(args[0]) == QML_LIBRARY:
                    self.qml_spaces.add(name)
        for match in JS_DESTRUCTURE.finditer(self.shape):
            required = JS_REQUIRE_AT.match(self.code, match.end())
            if not required:
                continue
            args = self.args(required.end() - 1)
            if not args or self.module(args[0]) != QML_LIBRARY:
                continue
            for entry in match.group(1).split(","):
                key, _, alias = entry.partition(":")
                if key.strip() in ("load", "closure"):
                    self.qml_names.add((alias or key).strip())
        return handled

    def load(self, kind, value, line):
        if value != "builtin":
            # A require, an import or a qml-library load evaluates the file
            # in this process; any other use runs or reads it.
            self.reading.use(self.path, value, line, kind, inproc=kind in ("require", "import", "qml-library"))

    def scan(self):
        reading, path, code, shape = self.reading, self.path, self.code, self.shape
        handled = self.bind()
        # A binding of a path the reading resolves to a file names that
        # file for a use the text order of Bindings cannot attribute.
        for value in self.env.values():
            reading.use(path, value if isinstance(value, P) else None, 0)
        for match in JS_CALL.finditer(shape):
            callee = match.group(1)
            if not callee.isidentifier():
                callee = re.sub(r"\s+|\?", "", callee)
            if callee in JS_NOT_CALLS or callee in JS_BUILDERS:
                continue
            last = callee.rsplit(".", 1)[-1]
            open_at = match.end() - 1
            special = (callee in ("require", "import") or callee in self.qml_names or callee in JS_EVAL or callee == "Function"
                       or callee.rsplit(".", 1)[0] in self.qml_spaces or last in JS_ENUMERATE or last in JS_COPY_SOURCE)
            if not special:
                close = self.close(open_at)
                if close is None or not self.may_name(open_at, close):
                    continue
            prior = before(shape, match.start())
            if re.search(r"\b(?:function|class)$", prior):
                continue
            line = functools.partial(self.line, match.start())
            if code[match.start()] != shape[match.start()]:
                # A require( inside a string, a generated program: its
                # argument must be a literal.
                if callee == "require":
                    literal = re.match(r"\s*(\"(?:\\.|[^\"\\\n])*\"|'(?:\\.|[^'\\\n])*')\s*\)", code[open_at + 1:])
                    self.load("require", self.module(Str(js_unquote(literal.group(1)))) if literal else U(P("")), line)
                continue
            args = self.args(open_at)
            for lo, _ in args:
                handled.add(lo)
            if callee == "require" or callee == "import":
                self.load(callee, self.module(args[0]) if args else U(P("")), line)
                continue
            if callee in self.qml_names or (callee.rsplit(".", 1)[0] in self.qml_spaces and last in ("load", "closure")):
                value = self.value(*args[0]) if args else U(P(""))
                if isinstance(value, Str):
                    value = norm(value)
                self.load("qml-library", value if value is not None else U(), line)
                continue
            if callee in JS_EVAL or (callee == "Function" and prior.endswith("new")):
                for lo, hi in args:
                    for read in re.finditer(r"readFile(?:Sync)?\s*\(", shape[lo:hi]):
                        inner = self.args(lo + read.end() - 1)
                        value = self.value(*inner[0]) if inner else U(P(""))
                        reading.use(path, value, line, JS_EVAL.get(callee, "eval"), inproc=True)
                continue
            values = [self.value(lo, hi) if self.may_name(lo, hi) else U() for lo, hi in args]
            if last in JS_ENUMERATE and values and (callee.startswith(("fs.", "fsp.", "promises.")) or callee == last):
                reading.use(path, values[0], line, "enumerate")
                if last in JS_COPY_SOURCE:
                    continue
            if last in JS_COPY_SOURCE and values:
                reading.use(path, values[0], line, "path")
                continue
            for index, value in enumerate(values):
                if index == 0 and last in JS_BASE_ONLY:
                    continue
                reading.use(path, value, line)
                # An array argument's elements are used too: a spawned
                # command's words, or the files a call reads.
                for element in self.elements(*args[index]):
                    if self.may_name(*element):
                        reading.use(path, self.value(*element), line)
        for match in JS_ESM.finditer(code):
            self.load("import", self.module(Str(match.group(2) or match.group(4))), self.line(match.start()))
        for space in self.qml_spaces:
            for use in re.finditer(r"(?<![\w$.])" + re.escape(space) + r"\b", shape):
                rest = shape[use.end():use.end() + 40]
                if not re.match(r"\s*\.\s*(?:load|closure)\s*\(|\s*=[^=]", rest):
                    reading.site(path, self.line(use.start()), "qml-library", U(P("")))
        for match in re.finditer(r"require\s*\([^()]*\)\s*\.\s*(?:load|closure)\s*\(", shape):
            args = self.args(match.end() - 1)
            value = self.value(*args[0]) if args else U(P(""))
            self.load("qml-library", norm(value) if isinstance(value, Str) else value, self.line(match.start()))
        for match in JS_VALUE_START.finditer(shape):
            if match.start() in handled or code[match.start()] != shape[match.start()]:
                continue
            if before(shape, match.start())[-1:] not in ("[", ",", ":"):
                continue
            # A value nested in an array or object literal is a use.
            lo = match.start()
            reading.use(path, self.value(lo, js_expression_end(shape, lo)), self.line(lo))


# --- Python ---------------------------------------------------------------------

PY_LOADERS = {
    "import_module": "importlib", "__import__": "importlib", "run_module": "runpy", "run_path": "runpy",
    "load_source": "imp", "load_module": "imp", "spec_from_file_location": "importlib",
    "SourceFileLoader": "importlib",
}
PY_LOADING_MODULES = {"importlib", "runpy", "imp", "util", "machinery"}
# importlib calls over a spec or a loader another call made: the path or
# name is read where that call is.
PY_SPEC_ONLY = {"module_from_spec", "spec_from_loader", "exec_module", "invalidate_caches", "reload"}
PY_ENUMERATE = {"listdir", "scandir", "walk", "glob", "iglob", "iterdir", "rglob", "copytree"}
PY_BUILDERS = {"join", "dirname", "abspath", "realpath", "normpath", "expanduser", "basename", "relpath", "Path",
               "PurePath", "PosixPath", "joinpath", "resolve", "absolute", "str", "fspath", "with_suffix", "with_name",
               "with_stem", "exists", "is_file", "is_dir", "isfile", "isdir", "lexists", "mkdir", "makedirs",
               "rmtree", "unlink", "chdir", "startswith", "endswith", "relative_to", "is_relative_to", "write_text",
               "write_bytes", "touch", "chmod", "symlink_to", "rename", "replace", "samefile", "stat", "lstat",
               "commonpath", "isabs", "split", "splitext", "access", "remove", "mkdtemp", "TemporaryDirectory", "print",
               "append", "add", "format", "get", "setdefault", "len", "sorted", "set", "list", "tuple", "assertEqual",
               "assertTrue", "assertIn", "assertFalse", "assertNotIn", "fail"}
PY_READS = {"read_text", "read_bytes", "open", "iterdir", "glob", "rglob"}


def py_callee(node):
    func = node.func
    if isinstance(func, ast.Name):
        return "", func.id
    if isinstance(func, ast.Attribute):
        owner = func.value
        if isinstance(owner, ast.Name):
            return owner.id, func.attr
        if isinstance(owner, ast.Attribute):
            return owner.attr, func.attr
        return "?", func.attr
    return "?", ""


class PyFile:
    def __init__(self, reading, path, text, offset=0, here=None):
        self.reading, self.path, self.text, self.offset = reading, path, text, offset
        self.here = os.path.dirname(path) if here is None else here
        self.env, self.roots = Bindings(), [self.here, "scripts"]

    def value(self, node):
        if isinstance(node, ast.Constant):
            return Str(node.value) if isinstance(node.value, str) else U()
        if isinstance(node, ast.Name):
            return P(self.path) if node.id == "__file__" else self.env.get(node.id, (node.lineno, node.col_offset))
        if isinstance(node, ast.Attribute) and node.attr == "parent":
            v = self.value(node.value)
            return P(os.path.dirname(v)) if isinstance(v, P) else U(v.prefix if isinstance(v, U) else None)
        if isinstance(node, ast.Subscript) and isinstance(node.value, ast.Attribute) and node.value.attr == "parents":
            v, index = self.value(node.value.value), node.slice
            if isinstance(v, P) and isinstance(index, ast.Constant) and isinstance(index.value, int):
                for _ in range(index.value + 1):
                    v = P(os.path.dirname(v))
                return v
            return U(anchored(v))
        if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Div, ast.Add)):
            left, right = self.value(node.left), self.value(node.right)
            if isinstance(node.op, ast.Div):
                if isinstance(left, Str):
                    left = norm(left)
                if isinstance(left, P) and isinstance(right, Str) and not right.startswith("/"):
                    return known(joined(left, right))
                return join_values([known(left), right])
            return concat([left, right])
        if isinstance(node, ast.JoinedStr):
            parts = []
            for piece in node.values:
                if isinstance(piece, ast.Constant):
                    parts.append(Str(piece.value))
                elif isinstance(piece, ast.FormattedValue):
                    parts.append(self.value(piece.value))
            return concat(parts)
        if isinstance(node, ast.Call):
            owner, name = py_callee(node)
            args = [self.value(a) for a in node.args]
            receiver = self.value(node.func.value) if isinstance(node.func, ast.Attribute) and owner not in ("path", "os") else None
            if name in ("Path", "PurePath", "PosixPath") and owner in ("", "pathlib"):
                if not args:
                    return P("")
                first = norm(args[0]) if isinstance(args[0], Str) else args[0]
                return join_values([first if first is not None else U()] + list(args[1:]))
            if name in ("cwd", "getcwd"):
                return P("")
            if name in ("resolve", "absolute", "expanduser") and receiver is not None:
                return receiver
            if name == "joinpath" and receiver is not None:
                return join_values([receiver] + args)
            if owner == "path" and name in ("dirname", "abspath", "realpath", "normpath", "expanduser") and args:
                v = args[0]
                if name == "dirname":
                    return type(v)(os.path.dirname(v)) if isinstance(v, (P, Str)) else U(v.prefix)
                return known(norm(v)) if isinstance(v, Str) and name in ("abspath", "realpath") else v
            if owner == "path" and name == "join" and args:
                return join_values(args)
            if name in ("str", "fspath") and len(args) == 1:
                return args[0]
            if name == "with_name" and isinstance(receiver, P) and args and isinstance(args[0], Str):
                return known(joined(os.path.dirname(receiver), args[0]))
            if name in ("with_suffix", "with_name", "with_stem") and receiver is not None:
                return U(P(os.path.dirname(receiver)) if isinstance(receiver, P) else anchored(receiver))
        if isinstance(node, (ast.IfExp, ast.BoolOp)):
            values = [self.value(n) for n in ([node.body, node.orelse] if isinstance(node, ast.IfExp) else node.values)]
            anchor = anchored(*values)
            paths = [v for v in values if isinstance(v, P)]
            return U(anchor, paths[0] if len(paths) == 1 and paths[0] == anchor else None)
        return U()

    def module(self, name, level=0):
        """The repository file module NAME loads, `outside` for one the
        repository does not provide, or None when it cannot be read."""
        parts = [part for part in name.split(".") if part]
        if level:
            base = self.here
            for _ in range(level - 1):
                base = os.path.dirname(base)
            roots = [base]
        else:
            roots = self.roots
        for root in roots:
            stem = joined(root, *parts) if parts else P(root)
            if stem is None:
                continue
            for candidate in (stem + ".py", stem + "/__init__.py"):
                if candidate in self.reading.present:
                    return P(candidate)
            if parts and stem in self.reading.folders:
                return P(stem)
        if not level and parts and (parts[0] in sys.stdlib_module_names or parts[0] in THIRD_PARTY):
            return "outside"
        return None

    def line(self, node):
        return self.offset + getattr(node, "lineno", 1)

    def imported(self, node, name, level, quiet=False):
        target = self.module(name, level)
        if isinstance(target, P):
            self.reading.edge(self.path, target, inproc=True)
        elif target is None and not quiet:
            self.reading.site(self.path, self.line(node), "import")
        return target

    def scan(self):
        reading, path = self.reading, self.path
        try:
            tree = ast.parse(self.text)
        except (SyntaxError, ValueError) as exc:
            reading.site(path, self.offset + (getattr(exc, "lineno", None) or 1), "syntax")
            return
        parents = {}
        for parent in ast.walk(tree):
            for child in ast.iter_child_nodes(parent):
                parents[child] = parent
        nodes = sorted((n for n in parents if hasattr(n, "lineno")), key=lambda n: (n.lineno, n.col_offset))
        for node in nodes:
            if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
                name, value = node.targets[0].id, self.value(node.value)
                self.env.bind(name, (node.end_lineno, node.end_col_offset), value)
            elif isinstance(node, ast.Call):
                owner, name = py_callee(node)
                if owner == "path" and name in ("insert", "append") and node.args:
                    folder = self.value(node.args[-1])
                    folder = norm(folder) if isinstance(folder, Str) else folder
                    if isinstance(folder, P) and folder not in self.roots:
                        self.roots.append(folder)
        for node in nodes:
            if isinstance(node, ast.Import):
                for alias in node.names:
                    self.imported(node, alias.name, 0)
            elif isinstance(node, ast.ImportFrom):
                target = self.imported(node, node.module or "", node.level)
                if isinstance(target, P) and target in reading.folders:
                    for alias in node.names:
                        self.imported(node, (node.module or "") + "." + alias.name, node.level, quiet=True)
            elif isinstance(node, ast.Call):
                if not isinstance(parents.get(node), ast.Raise):
                    self.call(node)
            elif isinstance(node, (ast.BinOp, ast.JoinedStr)):
                # A path nested in a list, dict or tuple, or stored into
                # one, is a use, through str() or os.fspath() as well.
                holder = parents.get(node)
                while isinstance(holder, ast.Call) and py_callee(holder)[1] in ("str", "fspath") and len(holder.args) == 1:
                    holder = parents.get(holder)
                stored = isinstance(holder, ast.Assign) and not isinstance(holder.targets[0], ast.Name)
                if stored or not isinstance(holder, (ast.BinOp, ast.JoinedStr, ast.Call, ast.Assign, ast.keyword, ast.FormattedValue)):
                    reading.use(path, self.value(node), self.line(node))
        # A binding of a path the reading resolves to a file names that
        # file for a use the text order of Bindings cannot attribute.
        for value in self.env.values():
            reading.use(path, value if isinstance(value, P) else None, 0)

    def call(self, node):
        reading, path = self.reading, self.path
        owner, name = py_callee(node)
        line = self.line(node)
        if name in PY_LOADERS and owner in ("", *PY_LOADING_MODULES):
            kind = PY_LOADERS[name]
            if name in ("import_module", "__import__", "run_module"):
                argument = self.value(node.args[0]) if node.args else U()
                target = self.module(argument) if isinstance(argument, Str) else None
                if isinstance(target, P):
                    reading.edge(path, target, inproc=True)
                elif target is None:
                    reading.site(path, line, kind)
                return
            argument = node.args[-1] if node.args else None
            for keyword in node.keywords:
                if keyword.arg in ("location", "path"):
                    argument = keyword.value
            value = self.value(argument) if argument is not None else U(P(""))
            value = norm(value) if isinstance(value, Str) else value
            reading.use(path, value if value is not None else U(), line, kind, inproc=True)
            return
        if owner in PY_LOADING_MODULES and name not in PY_SPEC_ONLY:
            reading.site(path, line, owner)
            return
        if name in ("exec", "compile") and owner == "":
            for inner in ast.walk(node):
                if isinstance(inner, ast.Call) and py_callee(inner)[1] in ("open", "read_text", "read_bytes"):
                    target = self.value(inner.args[0]) if py_callee(inner)[1] == "open" and inner.args else (
                        self.value(inner.func.value) if isinstance(inner.func, ast.Attribute) else U())
                    reading.use(path, norm(target) if isinstance(target, Str) else target, line, "exec", inproc=True)
            return
        receiver = self.value(node.func.value) if isinstance(node.func, ast.Attribute) and owner not in ("os", "path", "shutil", "glob", "subprocess", "json", "re", "sys") else None
        if name in PY_ENUMERATE:
            if name in ("glob", "iglob") and owner in ("glob", "") and node.args:
                pattern = self.value(node.args[0])
                if not (isinstance(pattern, (Str, P)) and GLOB.search(pattern)):
                    reading.use(path, pattern, line, "enumerate")
                return
            folder = receiver if receiver is not None else (self.value(node.args[0]) if node.args else U())
            reading.use(path, folder, line, "enumerate")
            return
        if receiver is not None and name in PY_READS:
            reading.use(path, receiver, line)
        if name in PY_BUILDERS:
            return
        if name == "open" and len(node.args) > 1:
            mode = self.value(node.args[1])
            if isinstance(mode, Str) and set(mode) & set("wax"):
                return
        for argument in node.args:
            reading.use(path, self.value(argument), line)
            # A list or tuple argument's elements are used too: a spawned
            # command's words, or the files a call reads.
            if isinstance(argument, (ast.List, ast.Tuple)):
                for element in argument.elts:
                    reading.use(path, self.value(element), line)
        for keyword in node.keywords:
            value = self.value(keyword.value)
            if isinstance(value, P):
                reading.edge(path, value)


# --- Bash ----------------------------------------------------------------------

MARK = "\x01{}\x02"
BASH_ASSIGN = re.compile(r"^[ \t]*(?:(?:local|readonly|export|declare(?:[ \t]+-\w+)*)[ \t]+)?([A-Za-z_]\w*)=(.*)$")
# Commands that only write, test or move to a place: their path words
# load nothing.
BASH_BASE_ONLY = re.compile(r"^\s*(?:(?:if|elif|while|until|!|then|do|&&|\|\|)\s+)*(?:mkdir|rm|rmdir|touch|chmod|chown|cd|pushd|mktemp|ln|mv|echo|printf|test|trap|export|local|readonly|declare|unset|wait|kill|\[\[?)(?=\s|$)")


def bash_code(line):
    """LINE without its comment: a `#` that starts a word outside quotes
    (bash(1), COMMENTS). A path a comment names is no load."""
    quote = None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = None
            elif ch == "\\" and quote == '"':
                continue
        elif ch in "'\"":
            quote = ch
        elif ch == "#" and (i == 0 or line[i - 1] in " \t;|&("):
            return line[:i]
    return line


# A `case` arm's patterns and the right side of `==`, `!=`, `=` or `=~`
# inside `[[ ]]` match a string; they read no file (bash(1), Compound
# Commands), so they are blanked before any path reading.
BASH_CASE_OPEN = re.compile(r"(?<![\w$-])case\s+\S.*?\s+in(?=\s|$)")
BASH_CASE_ARM = re.compile(r"(?:^|(?<=;;)|(?<=;&)|(?<=;;&))[ \t]*\(?((?:[^\s()|;]|\\.)+(?:[ \t]*\|[ \t]*(?:[^\s()|;]|\\.)+)*)\)")
BASH_TEST = re.compile(r"\[\[(?:(?!\]\]).)*\]\]")
BASH_TEST_MATCH = re.compile(r"(\s(?:==|!=|=~|=)[ \t]+)((?:[^\s\\]|\\.)+)")


def bash_unmatched(line, state):
    """LINE with its case patterns and [[ ]] match operands blanked, and
    the state after it: whether a case and a [[ ]] that spans lines are
    open. STATE is the state before it, (False, False) at the start."""
    in_case, in_test = state
    blank = lambda m, group: m.group(0)[:m.start(group) - m.start()] + " " * len(m.group(group)) + m.group(0)[m.end(group) - m.start():]
    opened = BASH_CASE_OPEN.search(line)
    if in_case or opened:
        start = opened.end() if opened else 0
        head, tail = line[:start], line[start:]
        tail = BASH_CASE_ARM.sub(lambda m: blank(m, 1), tail)
        line = head + tail
        in_case = not re.search(r"(?<![\w$-])esac(?![\w-])", line[start:]) if opened else not re.search(r"(?<![\w$-])esac(?![\w-])", line)
    operands = lambda text: BASH_TEST_MATCH.sub(lambda m: m.group(1) + " " * len(m.group(2)), " " + text)[1:]
    if in_test:
        end = line.find("]]")
        head, line = (line, "") if end < 0 else (line[:end], line[end:])
        head = operands(head)
        in_test = end < 0
    else:
        head = ""
    line = BASH_TEST.sub(lambda t: operands(t.group(0)[:-2]) + "]]", line)
    opened = line.rfind("[[")
    if opened >= 0 and "]]" not in line[opened:]:
        line = line[:opened] + operands(line[opened:])
        in_test = True
    return head + line, (in_case, in_test)


def bash_words(text):
    """TEXT's shell words, quotes, $( ) and ${ } kept inside a word."""
    words, word, quote, depth = [], "", None, 0
    for i, ch in enumerate(text):
        if quote:
            word += ch
            if ch == quote:
                quote = None
            continue
        if ch in "'\"":
            quote = ch
        elif text.startswith(("$(", "${"), i):
            depth += 1
        elif ch in ")}" and depth:
            depth -= 1
        elif ch in " \t" and not depth:
            if word:
                words.append(word)
            word = ""
            continue
        elif ch in ";|&" and not depth:
            break
        word += ch
    if word:
        words.append(word)
    return words


BASH_HEREDOC = re.compile(r"<<(-?)[ \t]*(['\"]?)([A-Za-z_]\w*)\2")


def bash_layout(lines):
    """The indexes of LINES that are Bash code, and each heredoc body as
    (first, end, language, quoted): its language is that of the python3 or
    node command it feeds, named as a word, a `$node...` variable or the
    tag, else None."""
    code, bodies, i = [], [], 0
    while i < len(lines):
        line = lines[i]
        code.append(i)
        here_doc = BASH_HEREDOC.search(line) if "<<<" not in line and not line.lstrip().startswith("#") else None
        if here_doc:
            tag, j = here_doc.group(3), i + 1
            while j < len(lines) and (lines[j].lstrip("\t") if here_doc.group(1) else lines[j]) != tag:
                j += 1
            if re.search(r"\bpython3?\b", line) or re.match(r"PY", tag):
                language = "python"
            elif re.search(r"\bnode\b|\$\{?node\w*", line) or re.match(r"(?:JS|NODE)", tag):
                language = "js"
            else:
                language = None
            bodies.append((i + 1, j, language, bool(here_doc.group(2))))
            i = j + 1
            continue
        i += 1
    return code, bodies


# Commands whose operands are files they read or copy; an interpreter's
# first operand is the script it runs. A path word elsewhere in a command,
# such as a function's argument or a message, is no load.
BASH_READERS = {"cat", "cp", "cmp", "diff", "install", "rsync", "tar", "head", "tail", "grep", "sed", "awk", "jq",
                "wc", "sha256sum", "md5sum", "sort", "comm", "stat", "readlink", "realpath", "xxd", "od"}
BASH_INTERPRETERS = {"bash", "sh", "node", "python3", "python"}
# Words that lead a command without being it: keywords, and commands that
# run the rest of their words, with the options and argument they take.
BASH_LEADERS = {"if", "elif", "then", "else", "do", "while", "until", "!", "{", "time", "command", "exec", "nohup",
                "setsid", "env", "nice", "timeout", "taskset"}
BASH_LEADER_ARGUMENT = {"timeout", "taskset"}
BASH_ASSIGNMENT = re.compile(r"[A-Za-z_]\w*(?:\[[^]]*\])?\+?=")


def bash_commands(code):
    """The simple commands of CODE, a line of Bash code with its quotes, as
    lists of (word, quoted): a word with its quotes removed and whether any
    part of it was quoted. Quoted text is part of one word and holds no
    command separator; a `$( )` opens a command of its own, inside double
    quotes too, and leaves a `$` in the word around it (bash(1), QUOTING
    and Command Substitution)."""
    done, current, stack = [], [], []
    word, quoted, quote, i = "", False, None, 0

    def end_word():
        nonlocal word, quoted
        if word or quoted:
            current.append((word, quoted))
        word, quoted = "", False

    while i < len(code):
        ch = code[i]
        if quote == "'":
            if ch == "'":
                quote = None
            else:
                word += ch
        elif code.startswith("$(", i):
            stack.append((current, word, quoted, quote))
            current, word, quoted, quote = [], "", False, None
            i += 2
            continue
        elif ch == ")" and quote is None and stack:
            end_word()
            done.append(current)
            current, word, quoted, quote = stack.pop()
            word += "$"
        elif quote == '"':
            if ch == '"':
                quote = None
            elif ch == "\\":
                i += 1
                word += code[i:i + 1]
            else:
                word += ch
        elif ch in "'\"":
            quote, quoted = ch, True
        elif ch == "\\":
            i += 1
            word += code[i:i + 1]
        elif ch in " \t":
            end_word()
        elif ch in ";&|()`":
            end_word()
            done.append(current)
            current = []
        else:
            word += ch
        i += 1
    end_word()
    done.append(current)
    return [command for command in done if command]


def bash_command_paths(code):
    """The path words of CODE, a line of Bash code with its quotes, that its
    commands run or read: each unquoted command word with a slash, an
    interpreter's script, a reader's operands (BASH_READERS) and a `<`
    redirect's source. A `>` redirect's target is written, not read, and a
    quoted command word, such as an element of a quoted list, is data."""
    found = []
    for command in bash_commands(code):
        kept, i = [], 0
        while i < len(command):
            word, quoted = command[i]
            if not quoted and re.fullmatch(r"[0-9&]?>>?|<", word):
                if word == "<" and i + 1 < len(command):
                    found.append(command[i + 1][0])
                i += 2
                continue
            if not quoted and re.match(r"[0-9&]?>", word):
                i += 1
                continue
            if not quoted and word.startswith("<") and not word.startswith("<<"):
                found.append(word[1:])
                i += 1
                continue
            kept.append((word, quoted))
            i += 1
        while kept and (BASH_ASSIGNMENT.match(kept[0][0]) or (not kept[0][1] and kept[0][0] in BASH_LEADERS)):
            head = kept.pop(0)[0]
            if head in BASH_LEADERS:
                while kept and kept[0][0].startswith("-"):
                    kept.pop(0)
                if head in BASH_LEADER_ARGUMENT and kept:
                    kept.pop(0)
        if not kept or kept[0][1]:
            continue
        name, operands = kept[0][0], [word for word, _ in kept[1:] if not word.startswith("-")]
        if "/" in name:
            found.append(name)
        elif name in BASH_INTERPRETERS and operands:
            found.append(operands[0])
        elif name in BASH_READERS:
            found.extend(operands)
    return [word.rstrip("/") for word in found if "/" in word and not re.search(r"[$`*?\[]", word)]


def bash_array_lines(lines, code):
    """The indexes among CODE, lines of LINES, that continue a multi-line
    `NAME=(` array assignment, through the line that closes it: its
    elements are data, never a command."""
    found, depth, quote = set(), 0, None
    for at in code:
        line = lines[at]
        start = 0
        if depth == 0:
            opened = re.match(r"^[ \t]*(?:(?:local|readonly|declare(?:[ \t]+-\w+)*)[ \t]+)?[A-Za-z_]\w*\+?=\(", line)
            if not opened:
                continue
            depth, start = 1, opened.end()
        else:
            found.add(at)
        i = start
        while i < len(line) and depth:
            ch = line[i]
            if quote == "'":
                quote = None if ch == "'" else quote
            elif quote == '"':
                if ch == "\\":
                    i += 1
                elif ch == '"':
                    quote = None
            elif ch == "\\":
                i += 1
            elif ch in "'\"":
                quote = ch
            elif ch == "#" and (i == 0 or line[i - 1] in " \t("):
                break
            elif ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            i += 1
    return found


BASH_COPIED = re.compile(r"\$\{?[A-Za-z_]\w*\}?/((?:[\w.@+-]+/)*[\w.@+-]+)")


def mark(path):
    return MARK.format("." if path == "" else path)


class BashFile:
    def __init__(self, reading, path, text):
        self.reading, self.path, self.text = reading, path, text
        self.here = os.path.dirname(path)
        self.env = Bindings()
        self.naming = None
        self.at = 0

    def variable(self, name, original):
        value = self.env.get(name, self.at)
        if isinstance(value, P):
            return mark(value)
        if isinstance(value, U) and value.prefix is not None:
            return mark(value.prefix) + "/$" + name
        return original

    def subst(self, text, line):
        """TEXT with each path idiom and each variable that holds a path,
        as bound before LINE, marked as \x01path\x02."""
        self.at = line
        if "$" not in text:
            return text
        if self.naming is None:
            names = [re.escape(n) for n, v in self.env.items() if isinstance(v, P) or (isinstance(v, U) and v.prefix is not None)]
            self.naming = re.compile(r"BASH_SOURCE|\$0\b|git rev-parse" + (r"|\$\{?(?:" + "|".join(names) + r")\b" if names else ""))
        if not self.naming.search(text):
            return text
        own = mark(self.path)

        def marked(match, step):
            target = norm(match.group(1) + match.group(2))
            return match.group(0) if target is None else mark(step(target))
        for _ in range(12):
            before = text
            text = re.sub(r"\$\{BASH_SOURCE(?:\[0\])?\}|\$BASH_SOURCE\b|\$0\b", own, text)
            text = re.sub(r"\$\((?:readlink|realpath)(?:[ \t]+-[\w-]+)*(?:[ \t]+--)?[ \t]+\"?\x01([^\x02]*)\x02([^\"\s)]*)\"?[ \t]*\)",
                          lambda m: marked(m, lambda t: t), text)
            text = re.sub(r"\$\(dirname(?:[ \t]+--)?[ \t]+\"?\x01([^\x02]*)\x02([^\"\s)]*)\"?[ \t]*\)",
                          lambda m: marked(m, os.path.dirname), text)
            text = re.sub(r"\$\(cd(?:[ \t]+(?:--|-P))*[ \t]+\"?\x01([^\x02]*)\x02([^\"\s)]*)\"?[ \t]*&&[ \t]*pwd(?:[ \t]+-P)?[ \t]*\)",
                          lambda m: marked(m, lambda t: t), text)
            text = text.replace("$(git rev-parse --show-toplevel)", mark(""))
            # ${NAME:-DEFAULT} reads its default where NAME holds no path:
            # the value in the repository's own use.
            text = re.sub(r"\$\{([A-Za-z_]\w*):?-([^{}]*)\}", lambda m: m.group(0) if isinstance(self.env.get(m.group(1), self.at), P) else m.group(2), text)
            # ${NAME%/*} is dirname of NAME's value.
            text = re.sub(r"\$\{([A-Za-z_]\w*)%/\*\}", lambda m: mark(os.path.dirname(self.env.get(m.group(1), self.at)))
                          if isinstance(self.env.get(m.group(1), self.at), P) else m.group(0), text)

            text = re.sub(r"\$\{([A-Za-z_]\w*)\}|\$([A-Za-z_]\w*)\b", lambda m: self.variable(m.group(1) or m.group(2), m.group(0)), text)
            if text == before:
                break
        return text

    def assigned(self, raw, at):
        """The value an assignment's right side RAW binds at line AT."""
        value = self.subst(raw, at).replace('"', "").replace("'", "").strip()
        value = re.split(r"\s+(?:\|\||&&)|;", value)[0].strip()
        # ${N:-DEFAULT}: the default is the value in the repository's own
        # use of the file.
        default = re.fullmatch(r"\$\{[A-Za-z_0-9]+:?-(.*)\}", value)
        if default:
            value = default.group(1)
        whole = re.fullmatch(r"\x01([^\x02]*)\x02([^\s;|&<>()$`]*)", value)
        partial = re.match(r"\x01([^\x02]*)\x02([^\s;|&<>()`]*)", value)
        copied = re.fullmatch(r"\$\{?[A-Za-z_]\w*\}?/([\w.@+/-]+)", value)
        if whole:
            return known(norm(whole.group(1) + whole.group(2)))
        if copied and (("/" in copied.group(1).rstrip("/") and copied.group(1).rstrip("/") in self.reading.folders)
                       or copied.group(1) in self.reading.present):
            # A copy of the checkout keeps its layout.
            return P(copied.group(1).rstrip("/"))
        if partial:
            lead = partial.group(2).split("$", 1)[0]
            return U(norm(partial.group(1) + (lead if lead.endswith("/") or not lead else os.path.dirname(lead))))
        return U()

    def scan(self):
        reading, path = self.reading, self.path
        lines = self.text.split("\n")
        code, bodies = bash_layout(lines)
        arrays = bash_array_lines(lines, code)
        assigned = set()
        for at in code:
            line = lines[at]
            assign = BASH_ASSIGN.match(line) if not line.lstrip().startswith("#") else None
            if not assign:
                continue
            assigned.add(at)
            declaration = re.match(r"[ \t]*(?:local|readonly|export|declare(?:[ \t]+-\w+)*)[ \t]+", line)
            words = bash_words(line[declaration.end():]) if declaration else [line.strip()]
            for word in words:
                name, equals, raw = word.partition("=")
                if equals and re.fullmatch(r"[A-Za-z_]\w*", name):
                    self.env.bind(name, at + 0.5, self.assigned(raw, at))
                    self.naming = None
        state = (False, False)
        for at in code:
            line, state = bash_unmatched(bash_code(lines[at]), state)
            number = at + 1
            if not line.strip():
                continue
            substituted = self.subst(line, at)
            expanded = substituted.replace('"', "").replace("'", "")
            use = at not in assigned and not BASH_BASE_ONLY.match(expanded)
            for match in re.finditer(r"\x01([^\x02]*)\x02((?:[\w./@+*?-]|\$\{[^{}]*\}|\$[A-Za-z_0-9@#*]\w*)*)", expanded):
                base, suffix = match.group(1), match.group(2)
                redirected = re.search(r"[0-9&]?>>?\s*$|\w=$", expanded[:match.start()])
                if "$" in suffix:
                    lead = suffix[:suffix.index("$")]
                    prefix = norm(base + (lead if lead.endswith("/") or not lead else os.path.dirname(lead)))
                    if use and not redirected:
                        reading.site(path, number, "path", U(prefix, glob_of(base + re.sub(r"\$\{[^{}]*\}|\$[A-Za-z_0-9#@*]\w*", "*", suffix))))
                    continue
                target = norm(base + suffix.rstrip("/"))
                if target is not None and not redirected:
                    reading.edge(path, target)
            plain = re.sub(r"\x01[^\x02]*\x02\S*", " ", expanded)
            # A copy of the checkout keeps its layout: a path under a base
            # the reading cannot resolve names the repository file it copies.
            for copied in BASH_COPIED.finditer(plain):
                # A redirect writes its target and reads nothing. A path
                # under a folder of the checkout below its root, a file it
                # lacks, is the layout's too: a missing target.
                target = norm(copied.group(1))
                if target and (target in reading.present or ("/" in target and os.path.dirname(target) in reading.folders)) and not re.search(r"[0-9&]?>[>|]?\s*$", plain[:copied.start()]):
                    reading.edge(path, P(target))
            source = re.match(r"^[ \t]*(?:source[ \t]+(?!=)(\S+)|\.[ \t]+(\S*[/$]\S*|\S+\.(?:sh|bash)))", expanded)
            if source:
                word = source.group(1) or source.group(2)
                marked = re.fullmatch(r"\x01([^\x02]*)\x02([^$`]*)", word)
                target = norm(marked.group(1) + marked.group(2)) if marked else None
                copied = re.fullmatch(r"\$\{?[A-Za-z_]\w*\}?/([\w.@+/-]+)", word)
                if copied and copied.group(1) in reading.present:
                    target = P(copied.group(1))
                layout = re.fullmatch(r"\$\{?[A-Za-z_]\w*\}?/((?:[\w.@+-]+/)+)(.+)", word)
                if target is None and not re.search(r"[$`\x01]", word):
                    for base in (self.here, ""):
                        candidate = joined(base, word)
                        if candidate in reading.present:
                            target = candidate
                            break
                if target is not None:
                    reading.edge(path, target, inproc=True)
                elif layout and "/" in layout.group(1).rstrip("/") and layout.group(1).rstrip("/") in reading.folders and re.search(r"[$`]", layout.group(2)):
                    # A computed name under a folder of a copy of the
                    # checkout: any file that folder holds.
                    folder = P(layout.group(1).rstrip("/"))
                    reading.site(path, number, "source", U(folder, glob_of(folder + "/" + re.sub(r"\$\{?\w+\}?|`[^`]*`", "*", layout.group(2)))))
                elif word.startswith("/") and not re.search(r"[$`\x01]", word):
                    # An absolute path, such as /dev/stdin, names no
                    # repository file.
                    pass
                elif re.fullmatch(r"\$\{?[A-Za-z_0-9@*#]\w*\}?|\$\(.*\)|`.*`", word) or "\x01" in word or not word.startswith("$"):
                    # A whole computed word, an anchored path or a word
                    # that names no repository file; a path under an
                    # unbound variable names none, as a copy's layout
                    # did not resolve it above.
                    reading.site(path, number, "source", U(P(""), glob_of(re.sub(r"\x01([^\x02]*)\x02", r"\1", re.sub(r"\$\{?\w+\}?", "*", word))) if "\x01" in word else None))
            # A marked path is read above; the quotes stay for the words.
            words = [] if at in arrays else bash_command_paths(re.sub(r"\x01[^\x02]*\x02[^\s\"';|&()]*", " ", substituted))
            for word in words:
                for base in ("", self.here):
                    candidate = joined(base, word)
                    if candidate in reading.present:
                        reading.edge(path, candidate)
                        break
        for start, end, language, quoted in bodies:
            body = "\n".join(lines[start:end])
            if language == "python" and quoted:
                PyFile(reading, path, body, offset=start, here=self.here).scan()
            elif language == "js":
                JsFile(reading, path, body, offset=start, here=self.here).scan()
            elif language == "python" and re.search(r"^\s*(?:import|from)\s", body, re.M):
                reading.site(path, start, "python-heredoc")


# --- The whole reading -----------------------------------------------------------

def bash_comment_lines(lines, code):
    """The numbers of the lines among CODE, indexes of LINES, that are whole
    Bash comments: a `#` that starts a line outside any quote, a quote that
    spans lines included, and a `$( )` inside double quotes quoting afresh
    (bash(1), QUOTING, Command Substitution and COMMENTS). The single-quoted
    script of a `-c` option is code, with `'\\''` its escaped quote."""
    found, quote, frames = set(), None, []
    for at in code:
        line = lines[at]
        if quote in (None, "-c") and line.lstrip().startswith("#"):
            found.add(at + 1)
            continue
        i = 0
        while i < len(line):
            ch = line[i]
            if quote == "-c":
                if line.startswith("'\\''", i):
                    i += 3
                elif ch == "'":
                    quote = None
            elif quote == "'":
                quote = None if ch == "'" else quote
            elif quote == "$'":
                if ch == "\\":
                    i += 1
                elif ch == "'":
                    quote = None
            elif ch == "\\":
                i += 1
            elif line.startswith("$(", i):
                frames.append([quote, 0])
                quote, i = None, i + 1
            elif quote == '"':
                quote = None if ch == '"' else quote
            elif ch == "(" and frames:
                frames[-1][1] += 1
            elif ch == ")" and frames:
                if frames[-1][1]:
                    frames[-1][1] -= 1
                else:
                    quote = frames.pop()[0]
            elif ch == "#" and (i == 0 or line[i - 1] in " \t;|&("):
                break
            elif ch == "$" and line[i + 1:i + 2] == "'":
                quote, i = "$'", i + 1
            elif ch == "'" and re.search(r"(?:^|\s)-c[ \t]*$", line[:i]):
                quote = "-c"
            elif ch in "'\"":
                quote = ch
            i += 1
    return found


def comment_lines(kind, text):
    """The numbers of the lines of TEXT, in language KIND, that are whole
    comments: where a `loads:` directive may stand."""
    lines = text.split("\n")
    if kind == "js":
        code = js_mask(text)[0].split("\n")
        return {number for number, (raw, masked) in enumerate(zip(lines, code), 1)
                if raw.lstrip().startswith("//") and not masked.strip()}
    if kind == "python":
        found = set()
        try:
            for token in tokenize.generate_tokens(io.StringIO(text).readline):
                if token.type == tokenize.COMMENT and not lines[token.start[0] - 1][:token.start[1]].strip():
                    found.add(token.start[0])
        except (tokenize.TokenError, SyntaxError):
            # A file Python cannot parse is a `syntax` site of its own.
            return set()
        return found
    if kind == "bash":
        code, bodies = bash_layout(lines)
        found = bash_comment_lines(lines, code)
        for start, end, language, quoted in bodies:
            if language == "js" or (language == "python" and quoted):
                found |= {start + number for number in comment_lines(language, "\n".join(lines[start:end]))}
        return found
    return {number for number, line in enumerate(lines, 1) if line.lstrip().startswith("#")}


SHEBANG = "shebang"


def named_language(path):
    """PATH's language by its name, None for data, or SHEBANG for an
    extensionless name, which its first line decides."""
    name = os.path.basename(path)
    if name.endswith((".js", ".mjs", ".cjs")):
        return "js"
    if name.endswith(".py"):
        return "python"
    if name.endswith((".sh", ".bash")):
        return "bash"
    if "." in name:
        # A command word with another extension, a .qml file among them, is
        # data the command reads; the command's own file is the loader.
        return None
    return SHEBANG


def language(path, data):
    kind = named_language(path)
    if kind != SHEBANG:
        return kind
    first = data[:200].partition(b"\n")[0]
    if not first.startswith(b"#!"):
        return None
    words = first[2:].decode("utf-8", "replace").split()
    if words and os.path.basename(words[0]) == "env":
        words = [w for w in words[1:] if not w.startswith("-")]
    interpreter = os.path.basename(words[0]) if words else ""
    return {"bash": "bash", "sh": "bash", "node": "js", "python3": "python", "python": "python"}.get(interpreter, "interpreter")


def node_builtins():
    """The module names node resolves to its own built-ins, as the node on
    PATH reports them: a require of one is no repository load."""
    result = subprocess.run(["node", "-e", 'process.stdout.write(JSON.stringify(require("module").builtinModules))'],
                            text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"node-builtins status={result.returncode} cause={result.stderr.strip()}")
    return json.loads(result.stdout)


class ReadFailed(Exception):
    """A file whose reading raised, with the exception's kind and text."""

    def __init__(self, path, kind, cause):
        super().__init__(f"{path}: {kind}: {cause}")
        self.path, self.kind, self.cause = path, kind, cause


# The inventory, read before the workers fork, which inherit it, and the
# bytes of each file a worker reads: a task carries only its paths.
PRESENT, FOLDERS, DATA = set(), set(), {}


def read_path(reading, path, data):
    kind = language(path, data)
    if kind is None:
        return
    text = decoded(path, data)
    reading.read_directives(path, text, comment_lines(kind, text))
    if kind == "js":
        JsFile(reading, path, text).scan()
    elif kind == "python":
        PyFile(reading, path, text).scan()
    elif kind == "bash":
        BashFile(reading, path, text).scan()
    else:
        # A file run by an interpreter the reading has no reader for may
        # load anything its folder holds.
        folder = P(os.path.dirname(path))
        reading.site(path, 1, "interpreter", U(folder, (folder or "") + "/*"))


def read_files(paths):
    """One worker's reading of PATHS, each file in a reading of its own, so
    its facts and the inventory answers its reading asked are its own: for
    each file, (path, its FACTS, (present answers, folder answers)). Its failure returns as plain data, naming the
    file it was reading: an exception whose arguments do not rebuild it
    cannot cross the pool."""
    files, path = [], None
    try:
        for path in paths:
            reading = Reading(Asked(PRESENT), Asked(FOLDERS))
            read_path(reading, path, DATA[path])
            facts = tuple(getattr(reading, name) for name in FACTS)
            other = set().union(*facts) - {path}
            if other:
                # A stored entry holds the facts of its own file alone.
                raise RuntimeError(f"fact of another loader: {sorted(other)[0]}")
            files.append((path, tuple(found.get(path, set()) for found in facts),
                          (reading.present.answers, reading.folders.answers)))
    except Unreadable as exc:
        return ("unreadable", exc.path, exc.strerror)
    except Exception as exc:
        return ("failed", path, type(exc).__name__, str(exc))
    return ("facts", files)


# --- The stored reading ----------------------------------------------------
#
# read_path's facts of a file follow from the reader (this file's bytes, the
# Python that runs it, node's built-in list), the file's path and bytes, and
# the answers to the inventory questions Asked records; nothing else feeds
# it. So an entry's key is a digest of the reader, the path and the bytes,
# and a hit stands only while each question it recorded answers the same:
# a file added or removed elsewhere voids only the entries whose reading
# asked about it.
# The store holds, for each file, the entry of the last reading that read
# it, and only entries of this reader, which bounds it by the files the
# readings name: a table reading and a smoke reading of other files keep
# each other's entries, and a reading whose every file hit leaves the store
# as it is.
#
# The store is a memo, never evidence. A store that is missing, unreadable
# or of another shape, or an entry missing a field, is a miss, and the file
# is read again. A failed write is ignored and prints nothing, since stdout
# and stderr carry the facts scripts/validate parses. D107 does not govern
# the format: every key carries the reader's digest, so a reader that
# writes another format reads no entry an earlier one wrote. Readings side
# by side: the last write wins, and a lost entry costs one reading of its
# file. The write goes to a temporary file under a fixed prefix beside the
# store, replaced onto it, so a reader never sees half a store; a reading
# killed mid-write, as at validate's deadline, leaves that file behind.

STORE = "vgs-row-loads.json"
ANSWERS = (("present", "not_present"), ("folders", "not_folders"))
# A file's facts, each a set per loader in Reading: its loads, the globs of
# its directives, its unread sites, its malformed directives, the loads it
# makes in its own process and the resolved targets the tree lacks.
FACTS = ("loads", "patterns", "unread", "malformed", "inproc", "missing")


def store_path():
    """The store in the worktree's own git directory, beside validate's
    records, so worktrees on other readers do not replace each other's;
    None when git cannot name that directory."""
    found = subprocess.run(["git", "rev-parse", "--absolute-git-dir"], capture_output=True)
    if found.returncode:
        return None
    return os.path.join(os.fsdecode(found.stdout.rstrip(b"\n")), STORE)


def load_store(path):
    try:
        with open(path, "rb") as source:
            store = json.load(source)
    except (OSError, ValueError):
        return {}
    return store if isinstance(store, dict) else {}


def entry_of(reader, path, facts, answers):
    """The stored form of PATH's FACTS and inventory ANSWERS under READER,
    each question kept as asked, None as null."""
    entry = {"reader": reader, "path": path}
    for name, found in zip(FACTS, facts):
        entry[name] = sorted(list(site) for site in found) if name == "unread" else sorted(found)
    for asked, (yes, no) in zip(answers, ANSWERS):
        entry[yes] = [value for value, answer in asked.items() if answer]
        entry[no] = [value for value, answer in asked.items() if not answer]
    return entry


def stored(entry):
    """The facts and answers ENTRY holds, or None for an entry of any shape
    entry_of does not write, a missing field among them: a missing unread
    field read as none would skip a row the file's reading runs."""
    try:
        facts = tuple({tuple(site) for site in entry[name]} if name == "unread" else set(entry[name]) for name in FACTS)
        answers = tuple({**dict.fromkeys(entry[yes], True), **dict.fromkeys(entry[no], False)} for yes, no in ANSWERS)
        return (facts, answers) if entry_of(entry["reader"], entry["path"], facts, answers) == entry else None
    except (KeyError, TypeError):
        return None


def held(answers):
    present, folders = answers
    return (all((value in PRESENT) == answer for value, answer in present.items())
            and all((value in FOLDERS) == answer for value, answer in folders.items()))


def write_store(path, entries):
    try:
        handle = tempfile.NamedTemporaryFile("w", encoding="ascii", dir=os.path.dirname(path), prefix=STORE + ".",
                                             suffix=".tmp", delete=False)
    except OSError:
        return
    try:
        with handle:
            json.dump(entries, handle, separators=(",", ":"))
        os.replace(handle.name, path)
    except OSError:
        try:
            os.unlink(handle.name)
        except OSError:
            pass


def worker_start(reader):
    """A worker ends with the reader however the reader ends, so a reader
    that is killed leaves no worker behind: PR_SET_PDEATHSIG, prctl(2)."""
    ctypes.CDLL(None, use_errno=True).prctl(1, signal.SIGKILL)
    if os.getppid() != reader:
        os._exit(1)


# The pool's bound: a reading with no stored facts took 3.1 s of CPU on
# one core (`taskset -c 0`, 324 command files, VGS-2749), so four workers
# bring it under a second, and a caller that runs many readings side by
# side, such as scripts/test-validate.sh, starts no more than four workers
# for each.
# The rows that start this pool declare `%weight=4` in scripts/validate.
WORKERS = 4


class Memo:
    """The reading of files across one process: each file's stored facts
    where they hold, and a reading of the rest split across at most WORKERS
    of the cores this process may use (sched_getaffinity, os(3)), in the
    reader alone for one core or one file, and none when every file's facts
    hold. fork: a worker inherits the inventory and the files' bytes, and a
    forkserver or spawn child would run this script's top level again. The
    store is read once and written once, by close, when a file missed."""

    def __init__(self):
        builtins = node_builtins()
        NODE_BUILTINS.update(builtins)
        self.reader = hashlib.sha256(hashlib.sha256(READER_BYTES).digest() + sys.version.encode() + b"\0"
                                     + json.dumps(sorted(builtins)).encode()).hexdigest()
        self.file = store_path() if READER_RUNS else None
        self.store = load_store(self.file) if self.file else {}
        self.entries, self.facts, self.missed = {}, {}, False

    def read(self, paths):
        """Read each of PATHS not yet read into self.facts, path -> FACTS."""
        keys = {}
        for path in paths:
            if path in self.facts or named_language(path) is None:
                continue
            data = read_bytes(path)
            # The reader digest has a fixed length and no path holds a NUL,
            # so no two (path, bytes) pairs share a key's input.
            key = keys[path] = hashlib.sha256(self.reader.encode() + os.fsencode(path) + b"\0" + data).hexdigest()
            hit = stored(self.store.get(key))
            if hit is not None and held(hit[1]):
                self.entries[key], self.facts[path] = self.store[key], hit[0]
            else:
                DATA[path] = data
        misses = [path for path in keys if path not in self.facts]
        workers = min(len(os.sched_getaffinity(0)), WORKERS, len(misses))
        if not misses:
            answers = []
        elif workers <= 1:
            answers = [read_files(misses)]
        else:
            count = min(len(misses), workers * 4)
            # A worker that dies breaks the pool, which then fails every
            # pending result (concurrent.futures, BrokenProcessPool), where
            # a multiprocessing.Pool would wait on it forever.
            pool = concurrent.futures.ProcessPoolExecutor(workers, mp_context=multiprocessing.get_context("fork"),
                                                          initializer=worker_start, initargs=(os.getpid(),))
            try:
                answers = list(pool.map(read_files, [misses[i::count] for i in range(count)]))
            except concurrent.futures.process.BrokenProcessPool as exc:
                raise RuntimeError(f"load-reading worker ended: {exc}") from exc
            finally:
                pool.shutdown(cancel_futures=True)
        for kind, *answer in answers:
            if kind == "unreadable":
                raise Unreadable(*answer)
            if kind == "failed":
                raise ReadFailed(*answer)
            for path, facts, asked in answer[0]:
                self.facts[path] = facts
                self.entries[keys[path]] = entry_of(self.reader, path, facts, asked)
                DATA.pop(path, None)
        self.missed = self.missed or bool(misses)

    def close(self):
        if not (self.file and self.missed):
            return
        read = {entry["path"] for entry in self.entries.values()}
        kept = {key: entry for key, entry in self.store.items()
                if isinstance(entry, dict) and entry.get("reader") == self.reader and entry.get("path") not in read}
        write_store(self.file, {**kept, **self.entries})

    def reading(self):
        """The facts read so far as one Reading."""
        reading = Reading(PRESENT, FOLDERS)
        for path, facts in self.facts.items():
            for name, theirs in zip(FACTS, facts):
                if theirs:
                    getattr(reading, name)[path] = set(theirs)
        return reading


# --- The smoke rows ------------------------------------------------------------
#
# A nested smoke row's inputs are what its file loads under the table above,
# walked by these rules (docs/architecture/validation.md § Selection):
#
#   kind        edge                                          walked onward
#   row file    scripts/smoke/rows/<row>.sh, and a row file   yes
#               it runs through smoke_row that no list names
#   in-process  source, require, import, a qml-library load   yes, transitively
#   direct      any other load a file of the row's own        a target with a
#               in-process closure names                      language: its
#                                                             in-process closure
#   recorded    a load of a file a direct target runs         no
#   plugin      a plugin id word in the row's own files       validate files its
#                                                             manifest and entries
#   directive   each `loads:` glob of a walked file           no
#   missing     a resolved target the tree lacks, a literal   no
#
# The walk stops at the harness, whose in-process closure is the harness's
# own input and never a row's, and at shell/shell.qml, which every started
# shell loads and the core rows cover. Another listed row's file is an
# input and never walked: a row is its own command. An unread site or a
# malformed directive in any walked file leaves the row untraced, so it
# runs on every change. A row file the shell reader cannot read to its end
# is `unparsed`: its relation is unknown.
#
# A row reads another row, and runs only after it, when it calls a function
# or reads a variable only that row defines, or when a `loads:` directive of
# its own files names that row's file alone: state the row leaves.

HARNESS = ("scripts/qml-smoke.sh", "scripts/smoke/row-inputs.sh", "scripts/smoke/harness.sh")
STARTUP = "shell/shell.qml"
ROW_FILE = re.compile(r"scripts/smoke/rows/([a-z0-9-]+)\.sh")
ROW_FILES = "scripts/smoke/rows/*.sh"


def shell_reader():
    """scripts/shell_source.py, which -I keeps off the path."""
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:
        sys.path.insert(0, here)
    import shell_source
    return shell_source


def row_path(row):
    return f"scripts/smoke/rows/{row}.sh"


def text_of(path):
    try:
        with open(path, encoding="utf-8") as source:
            return source.read()
    except (OSError, UnicodeError):
        return None


def state_reads(row, texts):
    """The rows whose file a `loads:` directive of ROW's TEXTS names alone,
    read under the directive grammar Reading.read_directives owns."""
    found = set()
    for text in texts:
        if text is None or "loads:" not in text:
            continue
        reading = Reading(set(), set())
        reading.read_directives(row, text, comment_lines("bash", text))
        for glob in reading.patterns.get(row, ()):
            named = ROW_FILE.fullmatch(glob)
            if named and named.group(1) != row:
                found.add(named.group(1))
    return found


class Rows:
    """The shell reading of the row files and the harness's definitions:
    what scripts/validate, scripts/qml-smoke.sh and
    scripts/check-smoke-readers.py read the row relation from."""

    def __init__(self, listed, extra=None):
        source = shell_reader()
        self.source, self.listed = source, list(listed)
        self.texts, self.side, queue = {}, [], ["scripts/qml-smoke.sh", "scripts/smoke/harness.sh"]
        while queue:
            rel = queue.pop(0)
            if rel not in self.texts:
                self.texts[rel] = text_of(rel)
                self.side.append(rel)
                queue += source.SOURCE.findall(self.texts[rel] or "")
        for path in sorted(pathlib_glob("scripts/smoke/rows", ".sh")):
            self.texts.setdefault(path, text_of(path))
        for path, text in (extra or {}).items():
            self.texts[path] = text

    @functools.cached_property
    def scans(self):
        """Each readable file's shell reading, read on first use: a
        harness reach that cannot attribute its hunks reads no row."""
        scans = {}
        for rel, text in self.texts.items():
            if text is not None:
                scan = self.source.Scan(text)
                if not scan.broken:
                    scans[rel] = scan
        return scans

    def unparsed(self):
        """The files read that the shell reader cannot read to its end; a
        harness file the tree lacks is no reading of a row's."""
        return sorted(rel for rel, text in self.texts.items() if text is not None and rel not in self.scans)

    def parts(self, row):
        """ROW's file and the row files it runs through smoke_row that no
        list names, which count as its own."""
        parts, queue = [], [row_path(row)]
        while queue:
            rel = queue.pop(0)
            if rel not in parts and (rel == row_path(row) or rel in self.texts):
                parts.append(rel)
                if rel in self.scans:
                    queue += [row_path(child) for child in self.scans[rel].rows if child not in self.listed]
        return parts

    def reads(self):
        """(row, needed, kind) for each row a listed row reads."""
        head, runs = self.source.head, {}
        for scan in self.scans.values():
            runs.update(scan.runners)

        def calls(scan):
            """The words SCAN runs as commands: each command's first word
            and, while that word is a runner, the word at its command
            operand, as expect LABEL WANT CMD... runs CMD."""
            found = set()
            for words in scan.commands:
                at = head(words)
                while at < len(words):
                    name = words[at][1]
                    if name:
                        found.add(name)
                    if name not in runs:
                        break
                    at += runs[name] + 1
            return found

        side = {field: set().union(*(getattr(self.scans[rel], field) for rel in self.side if rel in self.scans))
                for field in ("funcs", "sets")}
        owned = {}
        for row in self.listed:
            scans = [self.scans[rel] for rel in self.parts(row) if rel in self.scans]
            sets = set().union(*(s.sets for s in scans))
            # smoke_row sources a row inside its own body, so a name the
            # row declares local there, and each assignment to it, ends
            # when the row returns: no later row reads that binding.
            owned[row] = {"funcs": set().union(*(s.funcs for s in scans)), "sets": sets,
                          "defines": sets - set().union(*(s.locals for s in scans)),
                          "calls": set().union(*(calls(s) for s in scans)), "reads": set().union(*(s.reads for s in scans))}
        found = set()
        for at, row in enumerate(self.listed):
            for kind, used, field, defines in (("function", "calls", "funcs", "funcs"), ("variable", "reads", "sets", "defines")):
                for name in owned[row][used] - owned[row][field] - side[field]:
                    definers = [other for other in self.listed if other != row and name in owned[other][defines]]
                    # The rows run in list order, so the definition in
                    # force when ROW runs is the last one before it: that
                    # row alone gives a scoped run the full run's state. A
                    # name no earlier row defines keeps every definer.
                    earlier = [other for other in definers if self.listed.index(other) < at]
                    for other in earlier[-1:] or definers:
                        found.add((row, other, kind))
            for other in state_reads(row, [self.texts.get(rel) for rel in self.parts(row)]):
                found.add((row, other, "state"))
        return sorted(found)

    def harness_reach(self, base, changed):
        """The rows a change to CHANGED, a harness file, against BASE
        reaches, or None for every row.

        Conservative word reach over the shell reading, not a row map. Both
        hunk sides must fit function bodies. Tokens include quoted strings
        and heredocs, so callbacks and generated helpers count too. A
        top-level use reaches every row; missing evidence never proves an
        empty reach. Git's zero-context ranges:
        https://git-scm.com/docs/diff-format."""
        Scan, NAME = self.source.Scan, self.source.NAME
        try:
            old = subprocess.check_output(["git", "show", f"{base}:{changed}"], text=True)
            new = text_of(changed)
            if new is None:
                return None
            diff = subprocess.check_output(["git", "diff", "--no-ext-diff", "--no-color",
                                            "--no-textconv", "-U0", base, "--", changed], text=True)
        except (OSError, UnicodeError, subprocess.CalledProcessError):
            return None
        before, after = Scan(old), Scan(new)
        if before.broken or after.broken or before.partition_broken or after.partition_broken:
            return None

        def lines(text, scan):
            result = []
            for name, start, end in scan.spans:
                # A line shared with top-level code cannot be attributed to
                # the function alone, even though Git reports one line.
                lo, hi = text.rfind("\n", 0, start) + 1, text.find("\n", end)
                hi = len(text) if hi < 0 else hi
                if text[lo:start].strip() or text[end:hi].strip():
                    continue
                result.append((name, text.count("\n", 0, start) + 1, text.count("\n", 0, end) + 1))
            return result

        spans = (lines(old, before), lines(new, after))
        seeds, hunks = set(), 0
        for line in diff.splitlines():
            if not line.startswith("@@"):
                continue
            match = re.match(r"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", line)
            if not match:
                return None
            hunks += 1
            a, ac, b, bc = match.groups()
            for start, count, ranges in ((int(a), int(ac or 1), spans[0]), (int(b), int(bc or 1), spans[1])):
                # An insertion/deletion also reads the seam on its empty side.
                end = start + count - 1 if count else start + 1
                names = {name for name, lo, hi in ranges if lo <= start and end <= hi}
                if len(names) != 1:
                    return None
                seeds |= names
        if not hunks:
            return None
        # A renamed/removed definition can still have old callers.
        scans, side = dict(self.scans), list(self.side)
        scans[changed] = after
        if changed not in side:
            side.append(changed)
        if any(rel in side and rel not in scans for rel in self.texts):
            return None
        scans[changed + ":before"] = before
        side.append(changed + ":before")

        def words(scan, lo, hi):
            return set().union(*(set(NAME.findall(word)) for start, end, word in scan.words if lo <= start and end <= hi))

        functions, top = {}, {}
        for path, scan in scans.items():
            if scan.partition_broken:
                # An unchanged helper we cannot partition is opaque: any
                # reference to a reached name may be top-level, so it
                # reaches every row. Do not lose that reference with
                # partial spans.
                top[path] = words(scan, 0, scan.n)
                continue
            for name, start, end in scan.spans:
                functions.setdefault(name, set()).update(words(scan, start, end))
            top[path] = set().union(*(set(NAME.findall(word)) for start, end, word in scan.words
                                     if not any(lo <= start and end <= hi for _, lo, hi in scan.spans)))
        reached = set(seeds)
        while True:
            callers = {name for name, used in functions.items() if used & reached}
            if callers <= reached:
                break
            reached |= callers
        if any(top[path] & reached for path in side if path in top):
            return None
        found, traced = set(), False
        for row in self.listed:
            # Unreadable rows always run. All words in a row count,
            # including helpers it invokes later and an unlisted part.
            parts = [scans[rel] for rel in self.parts(row) if rel in scans]
            if any(words(part, 0, part.n) & reached for part in parts):
                traced = True
                found.add(row)
            elif row_path(row) not in scans:
                found.add(row)
        # No named caller is not proof of no caller: a computed dispatch can
        # hide its name. Keep the full-area answer in that case.
        return found if traced else None


def pathlib_glob(folder, suffix):
    try:
        return [os.path.join(folder, name) for name in sorted(os.listdir(folder)) if name.endswith(suffix)]
    except OSError:
        return []


def harness_reading(memo):
    """The harness's own inputs: HARNESS and the files they load in their
    own process, transitively, with the globs of their directives, and the
    sites and malformed directives among them. Each level of the walk is
    one memo.read, so a cold store's misses fan out across its workers."""
    closure, level = [], [path for path in HARNESS if path in PRESENT]
    while level:
        level = [path for path in dict.fromkeys(level) if path not in closure]
        closure += level
        memo.read(level)
        level = [target for path in level for target in sorted(dict(zip(FACTS, memo.facts.get(path, ((),) * len(FACTS))))["inproc"])
                 if target in PRESENT]
    return closure


def smoke_walks(memo, walks, listed, harness, plugins):
    """Each row's facts, ROW -> (inputs, patterns, plugins, unread,
    malformed), its file and the parts WALKS gives it walked as its own.
    The rows walk side by side, one level at a time, and each level of
    every row is one memo.read, so a cold store's misses fan out across its
    workers; each row's walk keeps its own first-in-first-out order."""
    found, queues, seen = {}, {}, {}
    for row, parts in walks.items():
        own = row_path(row)
        queues[row] = [(part, "own") for part in parts if part == own or part in PRESENT]
        seen[row] = {part for part, _ in queues[row]}
        found[row] = (set(), set(), set(), set(), set())
    while any(queues.values()):
        memo.read(sorted({path for queue in queues.values() for path, _ in queue}))
        for row, queue in queues.items():
            inputs, patterns, ids, unread, malformed = found[row]
            following = []
            for path, mode in queue:
                inputs.add(path)
                if named_language(path) is None:
                    continue
                facts = dict(zip(FACTS, memo.facts.get(path, ((),) * len(FACTS))))
                patterns |= facts["patterns"]
                unread |= {(path,) + tuple(site) for site in facts["unread"]}
                malformed |= {(path, number) for number in facts["malformed"]}
                inputs |= facts["missing"]
                if mode == "own" and plugins:
                    ids |= {plugins[word] for word in plugin_words(plugins).findall(text_of(path) or "")}
                for target in sorted(facts["loads"]):
                    if target in harness or target == STARTUP:
                        continue
                    inputs.add(target)
                    other = ROW_FILE.fullmatch(target)
                    if other and other.group(1) in listed:
                        continue
                    follow = mode if target in facts["inproc"] else ("run" if mode == "own" else None)
                    if follow and target not in seen[row]:
                        seen[row].add(target)
                        following.append((target, follow))
            queues[row] = following
    return found


@functools.lru_cache(maxsize=None)
def plugin_words_cached(names):
    return re.compile(r"(?<![\w.-])(" + "|".join(re.escape(name) for name in names) + r")(?![\w-])")


def plugin_words(plugins):
    return plugin_words_cached(tuple(sorted(plugins, key=len, reverse=True)))


def plugin_folders():
    """Each plugin id -> its folder: shell/plugins/<id> and the fixture
    plugins under scripts/smoke/fixtures/plugins/<id> that hold a manifest."""
    found = {}
    for root in ("scripts/smoke/fixtures/plugins", "shell/plugins"):
        for folder in pathlib_glob(root, ""):
            if os.path.join(folder, "manifest.json") in PRESENT:
                found[os.path.basename(folder)] = folder
    return found


def print_harness(memo):
    """Every directive glob of every file of the harness closure is a
    harness input, wherever in its file the directive stands."""
    harness = harness_reading(memo)
    reading = memo.reading()
    for path in harness:
        print("harness", path)
        for glob in sorted(reading.patterns.get(path, ())):
            print("harness-glob", glob)
        for number, kind, names in sorted(reading.unread.get(path, ())):
            # A site that can name only a row file is the walk's row file
            # edge: smoke_row runs each row, and each row's file is that
            # row's own input.
            if names != ROW_FILES:
                print("harness-unread", path, number, kind, names)
        for number in sorted(reading.malformed.get(path, ())):
            print("harness-malformed", path, number)


def print_smoke(memo, rows):
    harness = harness_reading(memo)
    relation = Rows(rows)
    for rel in relation.unparsed():
        print("unparsed", rel)
    # A row that runs another row's functions reads that row's files, so a
    # change to them reaches it as well as the row that defines them.
    defined = {}
    for row, needed, kind in relation.reads():
        print("reads", row, needed, kind)
        if kind != "state":
            defined.setdefault(row, set()).update(relation.parts(needed))
    plugins, listed, side = plugin_folders(), set(rows), set(harness)
    walked = smoke_walks(memo, {row: relation.parts(row) for row in rows}, listed, side, plugins)
    for row in rows:
        inputs, patterns, ids, unread, malformed = walked[row]
        inputs |= {path for path in defined.get(row, ()) if path in PRESENT}
        for path in sorted(inputs):
            print("input", row, path)
        for glob in sorted(patterns):
            print("pattern", row, glob)
        for folder in sorted(ids):
            print("plugin", row, folder)
        for path, number, kind, names in sorted(unread):
            print("unread", row, path, number, kind, names)
        for path, number in sorted(malformed):
            print("malformed", row, path, number)


def print_reading(reading, loads):
    for loader in sorted(loads):
        for target in sorted(reading.loads.get(loader, ())):
            print("load", loader, target)
        for glob in sorted(reading.patterns.get(loader, ())):
            print("pattern", loader, glob)
    for loader in sorted(reading.unread):
        for number, kind, names in sorted(reading.unread[loader]):
            print("unread", loader, number, kind, names)
    for loader in sorted(reading.malformed):
        for number in sorted(reading.malformed[loader]):
            print("malformed", loader, number)


USAGE = """usage: row_loads.py --rows FILE... [--loads FILE...]
       row_loads.py --smoke ROW...
       row_loads.py --harness
       row_loads.py --row-reads ROW... [--unlisted BASE NAME...]
       row_loads.py --harness-reach BASE PATH ROW..."""


def main(arguments):
    mode = arguments[:1]
    if mode == ["--row-reads"]:
        # The row relation alone, which reads no load: scripts/qml-smoke.sh
        # closes --rows over it. A NAME after --unlisted is a row the list
        # no longer holds, read from the tree or else from BASE, whose
        # readers scripts/validate selects.
        rows, unlisted, base = arguments[1:], [], None
        if "--unlisted" in rows:
            at = rows.index("--unlisted")
            rows, base, unlisted = rows[:at], rows[at + 1], rows[at + 2:]
        extra = {}
        for name in unlisted:
            path = row_path(name)
            text = text_of(path)
            if text is None:
                shown = subprocess.run(["git", "show", f"{base}:{path}"], capture_output=True)
                if shown.returncode:
                    print("failed", "operation=git-show", f"path={shlex.quote(path)}", f"status={shown.returncode}")
                    return 0
                text = shown.stdout.decode("utf-8", "replace")
            extra[path] = text
        relation = Rows(rows + unlisted, extra)
        for rel in relation.unparsed():
            print("unparsed", rel)
        for row, needed, kind in relation.reads():
            if row in rows and (not unlisted or needed in unlisted):
                print("reads", row, needed, kind)
        return 0
    if mode == ["--harness-reach"] and len(arguments) >= 3:
        found = Rows(arguments[3:]).harness_reach(arguments[1], arguments[2])
        if found is None:
            print("harness")
        else:
            for row in sorted(found):
                print("reach", row)
        return 0
    if mode not in (["--rows"], ["--smoke"], ["--harness"]):
        print(USAGE, file=sys.stderr)
        return 2
    rows, loads = arguments[1:], []
    if mode == ["--rows"] and "--loads" in rows:
        at = rows.index("--loads")
        rows, loads = rows[:at], rows[at + 1:]
    operation = "git-ls-files"
    try:
        listed, present, folders = inventory()
        PRESENT.update(present)
        FOLDERS.update(folders)
        listed = set(listed)
        # A file git does not list under that spelling would be read as
        # one no table row names, and its row would pass unread.
        for path in (rows + loads) if mode == ["--rows"] else [row_path(row) for row in rows]:
            if path not in listed or path not in present:
                raise Unreadable(path, "not-listed")
        operation = "load-reading"
        memo = Memo()
        if mode != ["--rows"]:
            try:
                print_smoke(memo, rows) if mode == ["--smoke"] else print_harness(memo)
            finally:
                memo.close()
            return 0
        memo.read(sorted(set(rows) | set(loads)))
        memo.close()
        print_reading(memo.reading(), set(loads))
    except subprocess.CalledProcessError as exc:
        print("failed", f"operation={operation}", f"status={exc.returncode}", f"cause={shlex.quote(str(exc.stderr).strip())}")
    except Unreadable as exc:
        print("unreadable", f"path={shlex.quote(exc.path)}", f"cause={shlex.quote(exc.strerror)}")
    except ReadFailed as exc:
        print("failed", f"operation={operation}", f"path={shlex.quote(exc.path)}", f"kind={exc.kind}", f"cause={shlex.quote(exc.cause)}")
    except (OSError, RuntimeError) as exc:
        print("failed", f"operation={operation}", f"kind={type(exc).__name__}", f"cause={shlex.quote(str(exc))}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
