#!/usr/bin/env python3
"""Enforce the smoke reader rule docs/architecture/validation-smoke.md
states.

A smoke row reads the shell through the probe or the compositor and parses
the answer with an inline Python program. The probe answers a state word,
such as `absent` or `ipc-failed`, in place of JSON, and an empty reply can
still come from a failed command. A raw JSON reader raises on these states,
and a poll that retries past the failed read leaves the traceback in the
log behind a passing check. `py_reply` in scripts/smoke/harness.sh answers
the word itself and parses only JSON, so a
program in a row that parses JSON from its stdin is `py_reply`'s program:
  inline-reader   the read's command is python3, not py_reply.
  unowned-reader  the read is not inside the literal that opens py_reply's
                  program, `py_reply '...'` or `py_reply "$VAR"'...'`, or
                  no command precedes it.
  raw-qs-list     the row runs `qs list` itself, not `qs_list`. qs answers
                  that no instance runs in plain text, which `qs_list` in
                  scripts/smoke/harness.sh reads as the word `none`.
  harness-function the row defines a function the harness or a file it
                  sources defines, replacing it for every later row.
                  Definitions inside subshells or command substitutions
                  cannot replace the sourcing shell's function.
  unreachable-leaves the row declares state it leaves on a `# leaves:`
                  line in its leading comment block, and it is no core row,
                  `smoke_core` in scripts/validate, and no later row in
                  rows.list beside DIR names its file,
                  `scripts/smoke/rows/<row>.sh`, as a word of its
                  `# inputs:` line, the word scripts/validate follows. A scoped run that holds the row and not that reader
                  would carry the state into rows that do not read it.
A read is `json.load(sys.stdin` or `json.loads(sys.stdin`, or any
`sys.stdin` in a program literal that also parses JSON with `json.load`,
`json.loads` or `raw_decode`. Its command is the nearest `py_reply` or
`python3` word before it, and a program literal holds no single quote, so
the read sits in the command's program exactly when the text between the
two is the program's opening. A `sys.stdin` outside a literal, such as in
a heredoc, is a read only in the direct form. A `sys.stdin` on a line whose
text before it is a `#` comment is no read. A run of `qs list` is the words
`qs list` apart from such a comment; the text `qs lists` is none.

Usage: check-smoke-readers.py [DIR]
DIR defaults to the repository's scripts/smoke/rows. Every finding is one
line: `<rule> <file>:<line> <detail>`. The pass is
`check-smoke-readers: ok files=<n> readers=<n>`. Exit 0 when clean, 1 on any
finding, 2 when the directory or a file cannot be read, printed as
`check-smoke-readers: unreadable: <path>: <strerror>`. A directory holding
no row is unreadable too: an empty walk certifies nothing, and so is a
scripts/validate without one `smoke_core=(...)` line once a row declares.
"""
import os
import re
import sys

ROWS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "smoke", "rows")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HARNESS = os.path.join(REPO, "scripts", "smoke", "harness.sh")
VALIDATE = os.path.join(REPO, "scripts", "validate")
CORE = re.compile(r"(?m)^smoke_core=\(([^)\n]*)\)$")
FUNCTION = re.compile(r"(?<![\w=])(?:function\s+)?([A-Za-z_][\w.-]*)\s*\(\s*\)\s*[{(]|\bfunction\s+([A-Za-z_][\w.-]*)\s*[{(]")
SOURCE = re.compile(r"(?m)^[ \t]*(source|\.)[ \t]+(?:\"([^\"\n]+)\"|'([^'\n]+)'|([^\s;]+))")
HEREDOC = re.compile(r"<<(-?)[ \t]*(['\"]?)\\?([A-Za-z_][A-Za-z0-9_]*)\2")
CASE_WORD = re.compile(r"(case|esac)\b")
STDIN = re.compile(r"\bsys\.stdin\b")
DIRECT = re.compile(r"json\.loads?\(\s*$")
PARSES_JSON = re.compile(r"\bjson\.loads?\(|\braw_decode\(")
COMMAND = re.compile(r"\b(py_reply|python3)\b")
QS_LIST = re.compile(r"\bqs[ \t]+list\b")
# The text between a command and a stdin use inside the literal that opens
# its program: python3's `-c`, an optional quoted variable the literal
# extends, then the literal's opening quote and no closing one.
PROGRAM_OPENING = {
    "py_reply": re.compile(r"[ \t]+(?:\"\$[A-Za-z_][A-Za-z0-9_]*\")?'([^']*)"),
    "python3": re.compile(r"[ \t]+-c[ \t]+(?:\"\$[A-Za-z_][A-Za-z0-9_]*\")?'([^']*)"),
}


class Unreadable(Exception):
    def __init__(self, path, strerror):
        super().__init__(path, strerror)
        self.path = path
        self.strerror = strerror


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def in_comment(text, offset):
    line_start = text.rfind("\n", 0, offset) + 1
    return text[line_start:offset].lstrip().startswith("#")


def read_file(path):
    try:
        with open(path, encoding="utf-8") as source:
            text = source.read()
    except (OSError, UnicodeDecodeError) as exc:
        raise Unreadable(path, getattr(exc, "strerror", None) or str(exc)) from exc
    return text


def shell_code(text):
    """Keep shared shell code, masking literals, heredocs and subshells.

    Rows write stand-in shell programs inside literals and heredocs; their
    functions belong to those programs, not the shell sourcing the row.
    """
    masked = list(text)
    pending = []

    def hide(start, end):
        for at in range(start, end):
            if text[at] != "\n":
                masked[at] = " "

    def code(i, closing=None):
        cases = 0
        while i < len(text):
            start = i
            word = CASE_WORD.match(text, i)
            if word:
                command_start = max(text.rfind(mark, 0, i) for mark in "\n;|&({}") + 1
                if not text[command_start:i].strip():
                    cases += 1 if word.group(1) == "case" else -1
                    if cases < 0:
                        raise ValueError("undecidable case enclosure")
                    i = word.end()
                    continue
            if closing and text[i] == closing and not cases:
                return i + 1
            if text[i] == "\\":
                i = min(i + 2, len(text))
                hide(start, i)
            elif text[i] in "'\"":
                quote = text[i]
                ansi = quote == "'" and i > 0 and text[i - 1] == "$"
                hide(i, i + 1)
                i += 1
                while i < len(text) and text[i] != quote:
                    start = i
                    if quote == '"' and text.startswith("$(", i):
                        i = code(i + 2, ")")
                        hide(start, i)
                        continue
                    i = min(i + (2 if text[i] == "\\" and (quote == '"' or ansi) else 1), len(text))
                    hide(start, i)
                if i >= len(text):
                    raise ValueError("unclosed quote")
                hide(i, i + 1)
                i += 1
            elif text[i] == "#" and (i == 0 or text[i - 1] in " \t\n;|&()"):
                end = text.find("\n", i)
                i = len(text) if end < 0 else end
                hide(start, i)
            elif text.startswith("<<", i) and not text.startswith("<<<", i) and (i == 0 or text[i - 1] != "<"):
                match = HEREDOC.match(text, i)
                if match is None:
                    raise ValueError("unreadable heredoc delimiter")
                pending.append((match.group(3), bool(match.group(1))))
                i = match.end()
                hide(start, i)
            elif text[i] == "\n" and pending:
                i += 1
                while pending:
                    delimiter, strip_tabs = pending.pop(0)
                    start = i
                    while i < len(text):
                        end = text.find("\n", i)
                        end = len(text) if end < 0 else end
                        line = text[i:end]
                        i = min(end + 1, len(text))
                        if (line.lstrip("\t") if strip_tabs else line) == delimiter:
                            break
                    else:
                        raise ValueError("unclosed heredoc")
                    hide(start, i)
            elif text[i] == "(":
                i = code(i + 1, ")")
                hide(start + 1, i - 1)
            elif text[i] == "`":
                i = code(i + 1, "`")
                hide(start, i)
            else:
                i += 1
        if closing or pending or cases:
            raise ValueError("unclosed substitution, case or heredoc")
        return i

    code(0)
    return "".join(masked)


def definitions(path, text):
    try:
        code = shell_code(text)
    except ValueError as exc:
        raise Unreadable(path, str(exc)) from exc
    return code, [(match.group(1) or match.group(2), line_of(text, match.start())) for match in FUNCTION.finditer(code)]


def harness_functions():
    functions = {}
    queue = [HARNESS]
    seen = set()
    while queue:
        path = os.path.abspath(queue.pop(0))
        if path in seen:
            continue
        seen.add(path)
        text = read_file(path)
        code, defined = definitions(path, text)
        for name, line in defined:
            functions.setdefault(name, []).append((path, line))
        for source in SOURCE.finditer(text):
            if code[source.start(1):source.end(1)] != source.group(1):
                continue
            operand = next(value for value in source.groups()[1:] if value is not None)
            # smoke_row sources this separately checked directory at runtime.
            if operand.startswith("$smoke_row_dir/"):
                continue
            operand = re.sub(r"^\$(?:repo\b|\{repo\})", lambda _: REPO, operand)
            if "$" in operand or "`" in operand:
                raise Unreadable(path, f"unresolved source: {operand}")
            queue.append(os.path.join(REPO, operand))
    return functions


def check_file(path, findings, functions):
    text = read_file(path)
    _, defined = definitions(path, text)
    for name, number in defined:
        for owner, line in functions.get(name, []):
            findings.append(f"harness-function {path}:{number} function={name} defined={owner}:{line}")
    readers = 0
    for run in QS_LIST.finditer(text):
        if not in_comment(text, run.start()):
            findings.append(f"raw-qs-list {path}:{line_of(text, run.start())} the row runs qs list itself; read it through qs_list")
    for read in STDIN.finditer(text):
        if in_comment(text, read.start()):
            continue
        line_start = text.rfind("\n", 0, read.start()) + 1
        direct = DIRECT.search(text, line_start, read.start()) is not None
        command = None
        for command in COMMAND.finditer(text, 0, read.start()):
            pass
        opening = command and PROGRAM_OPENING[command.group(1)].fullmatch(text, command.end(), read.start())
        if opening:
            close = text.find("'", read.end())
            program = text[opening.start(1):len(text) if close < 0 else close]
            if not (direct or PARSES_JSON.search(program)):
                continue
        elif not direct:
            continue
        readers += 1
        number = line_of(text, read.start())
        if command is None:
            findings.append(f"unowned-reader {path}:{number} no py_reply before the read")
        elif command.group(1) == "python3":
            findings.append(f"inline-reader {path}:{number} python3 on line {line_of(text, command.start())} parses JSON from stdin; read it through py_reply")
        elif not opening:
            findings.append(f"unowned-reader {path}:{number} the read is outside the program py_reply on line {line_of(text, command.start())} opens")
    return readers


def header(text):
    lines = []
    for line in text.splitlines():
        if not line.startswith("#"):
            break
        lines.append(line)
    return lines


def check_leaves(root, texts, findings):
    declared = {name: number for name, text in texts.items() for number, line in enumerate(header(text), 1) if re.match(r"#[ \t]*leaves:", line)}
    if not declared:
        return
    order = [line.strip() for line in read_file(os.path.join(os.path.dirname(root), "rows.list")).splitlines()]
    order = [row for row in order if row and not row.startswith("#")]
    cores = CORE.findall(read_file(VALIDATE))
    if len(cores) != 1:
        raise Unreadable(VALIDATE, f"smoke_core lines={len(cores)}")
    for name, number in sorted(declared.items()):
        row = name[:-len(".sh")]
        if row in cores[0].split():
            continue
        later = order[order.index(row) + 1:] if row in order else []
        words = [word for reader in later if reader + ".sh" in texts for line in header(texts[reader + ".sh"]) if line.startswith("# inputs:") for word in line.split()[2:]]
        if f"scripts/smoke/rows/{name}" not in words:
            findings.append(f"unreachable-leaves {os.path.join(root, name)}:{number} row={row} is no core row and no later row in rows.list names it")


def main(argv):
    if len(argv) > 2:
        print(f"check-smoke-readers: refused: argument={argv[2]}")
        return 2
    root = os.path.abspath(argv[1] if len(argv) == 2 else ROWS)
    findings = []
    readers = 0
    try:
        try:
            names = sorted(n for n in os.listdir(root) if n.endswith(".sh"))
        except OSError as exc:
            raise Unreadable(root, exc.strerror) from exc
        if not names:
            raise Unreadable(root, "no row found")
        functions = harness_functions()
        for name in names:
            readers += check_file(os.path.join(root, name), findings, functions)
        check_leaves(root, {name: read_file(os.path.join(root, name)) for name in names}, findings)
    except Unreadable as exc:
        print(f"check-smoke-readers: unreadable: {exc.path}: {exc.strerror}")
        return 2
    for line in findings:
        print(line)
    if findings:
        print(f"check-smoke-readers: findings={len(findings)}")
        return 1
    print(f"check-smoke-readers: ok files={len(names)} readers={readers}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
