"""The QML and JavaScript source lines a static check reads.

`check-plugin-boundary.py`, `check-design-tokens.py` and
`check-pointer-cursor.py` walk the same files the way the shell lists them,
through `bin/vgshell-scan`, and read code only: line comments, block comments
and trailing comments are blanked before matching, with line numbers kept. String literals stay, so a name inside a string handed
to `Qt.createQmlObject` is still a finding.

A directory or file the walk cannot read raises `Unreadable`, and the caller
ends its run: an incomplete traversal never certifies a tree.
"""
import os
import runpy

SCAN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin", "vgshell-scan")
scan_sources = runpy.run_path(SCAN)["source_files"]

# A `/` after one of these characters, after one of these keywords, or at the
# start of the text, opens a regular expression literal rather than dividing.
REGEX_AFTER = set("(,=:[!&|?{};~+-*%<>^")
REGEX_AFTER_WORDS = {"return", "typeof", "case", "in", "of", "delete", "void", "throw", "new", "else", "do", "yield", "await", "instanceof"}


class Unreadable(Exception):
    """A directory or file the walk could not read; the run ends with exit 2."""

    def __init__(self, path, strerror):
        super().__init__(f"{path}: {strerror}")
        self.path = path
        self.strerror = strerror


def blank_comments(text, literals=True, *, comments=None):
    """Blank comments without changing offsets; optionally collect their spans.

    Literal contents stay intact. Template interpolation is code and can hold
    comments, nested strings and templates. With literals false the complete
    literal, including interpolation, is masked for the brace readers.
    """
    out = list(text)
    n = len(text)

    def hide(start, end):
        for at in range(start, end):
            if text[at] != "\n":
                out[at] = " "

    def literal(i, close):
        start = i
        i += 1
        in_class = False
        while i < n:
            ch = text[i]
            if ch == "\n" and close != "`":
                break
            if ch == "\\":
                i += 2
                continue
            if close == "`" and text.startswith("${", i):
                i = code(i + 2, interpolation=True)
                continue
            if close == "/" and ch == "[":
                in_class = True
            elif close == "/" and ch == "]":
                in_class = False
            elif ch == close and not in_class:
                i += 1
                break
            i += 1
        if not literals:
            hide(start + 1, max(start + 1, i - (i <= n and text[i - 1:i] == close)))
        return i

    def code(i, interpolation=False):
        last = ""
        word = ""
        word_gap = False
        depth = 0
        controls = []
        while i < n:
            c = text[i]
            nxt = text[i + 1:i + 2]
            # Quickshell executes these line-leading directives. They are
            # code even though their introducer resembles a JS comment.
            if text.startswith("//@ pragma ", i) and not text[text.rfind("\n", 0, i) + 1:i].strip():
                i += 2
                continue
            if c == "/" and nxt in ("/", "*"):
                start = i
                if nxt == "/":
                    end = text.find("\n", i)
                    i = n if end < 0 else end
                else:
                    end = text.find("*/", i + 2)
                    i = n if end < 0 else end + 2
                hide(start, i)
                if comments is not None:
                    comments.append((start, i))
                continue
            if c in "\"'`" or (c == "/" and (not last or last in REGEX_AFTER or word in REGEX_AFTER_WORDS)):
                i = literal(i, c)
                last, word = c, ""
                continue
            if c == "(":
                controls.append(word in {"if", "while", "for", "with", "switch", "catch"})
            elif c == ")":
                control = controls.pop() if controls else False
                if control:
                    last, word = ";", ""
                    i += 1
                    continue
            if c == "{":
                depth += 1
            elif c == "}":
                if interpolation and depth == 0:
                    return i + 1
                depth -= 1
            if not c.isspace():
                word = ("" if word_gap else word) + c if (c.isalnum() or c in "_$") else ""
                word_gap = False
                last = c
            else:
                word_gap = True
            i += 1
        return i

    code(0)
    return "".join(out)


def source_texts(root):
    """Yield (path, text) for every `.qml` and `.js` file under `root`, as
    written, comments included."""
    try:
        for relative, _executable, data in scan_sources(root):
            if not relative.endswith((".qml", ".js")):
                continue
            path = os.path.join(root, relative)
            try:
                yield path, data.decode("utf-8-sig")
            except UnicodeError as exc:
                raise Unreadable(path, str(exc)) from exc
    except OSError as exc:
        raise Unreadable(exc.filename, exc.strerror) from exc


def source_lines(root):
    """Yield (path, line number, code) for every non-blank code line of every
    `.qml` and `.js` file under `root`, comments blanked."""
    for path, text in source_texts(root):
        for number, line in enumerate(blank_comments(text).split("\n"), 1):
            if line.strip():
                yield path, number, line
