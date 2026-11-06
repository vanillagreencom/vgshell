"""The shared Bash source reader for validation selection and smoke edits."""
import pathlib
import re

NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
ASSIGN = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)(\[[^\]]*\])?\+?=")
HEREDOC = re.compile(r"<<(-?)\s*(['\"]?)\\?([A-Za-z_][A-Za-z0-9_]*)\2")
SOURCE = re.compile(r'^\s*(?:source|\.)\s+"\$repo/([^"]+)"', re.M)
DECLARE = {"local", "declare", "typeset", "export", "readonly"}
RESET = {"if", "then", "elif", "else", "do", "while", "until", "!", "{", "time"}
TAKES = {"read": set("dinNptu"), "mapfile": set("dnOsuCc"), "readarray": set("dnOsuCc")}


def head(words):
    """The index of a command's first word that is not an assignment."""
    at = 0
    while at < len(words) - 1 and ASSIGN.match(words[at][0]):
        at += 1
    return at


class Scan:
    """One bash file's functions, the names it assigns or declares, the
    variables it expands, its commands as word lists, the rows it runs
    through smoke_row, and its runners: FUNCTION -> N for each function
    whose body runs "$@" as a command after one `shift N`. Quotes, heredocs,
    comments, arithmetic and { } bodies are read as bash reads them; broken
    is set when a quote, heredoc or substitution runs to the end."""

    def __init__(self, text):
        self.t, self.n, self.broken = text, len(text), False
        self.funcs, self.sets, self.reads, self.rows = set(), set(), set(), set()
        self.sources = set()
        self.commands, self.runners, self.heredocs = [], {}, []
        self.arrays = []
        self.depth, self.defining, self.bodies = 0, None, []
        self.words, self.spans, self.open_spans = [], [], []
        self.code(0, None)
        self.broken |= bool(self.heredocs)
        # The existing name reader need not partition every brace. Function
        # attribution is stricter, without changing that reader's verdict.
        self.partition_broken = bool(self.open_spans) or self.depth != 0

    def dollar(self, i):
        t, j = self.t, i + 1
        if j >= self.n:
            return j
        if t[j] == "(":
            return self.arith(j + 2) if t.startswith("((", j) else self.code(j + 1, ")")
        if t[j] == "'":
            return self.single(j + 1, ansi=True)
        if t[j] == "{":
            j += 1
            if j < self.n and t[j] in "#!":
                j += 1
        m = NAME.match(t, j)
        if not m:
            return j + 1 if j < self.n and t[j] in "?$#@!*-0123456789" else j
        self.reads.add(m.group())
        return m.end()

    def single(self, i, ansi=False):
        t = self.t
        while i < self.n and t[i] != "'":
            i += 2 if ansi and t[i] == "\\" else 1
        self.broken |= i >= self.n
        return i + 1

    def arith(self, i):
        t, depth = self.t, 0
        while i < self.n:
            c = t[i]
            if c == "$":
                i = self.dollar(i)
                continue
            if c == "(":
                depth += 1
            elif c == ")":
                if depth == 0 and t.startswith("))", i):
                    return i + 2
                depth -= 1
            m = NAME.match(t, i)
            if m and not (t[i - 1].isalnum() or t[i - 1] in "_#"):
                if re.match(r"\s*(\+\+|--|[-+*/%&|^]?=(?!=))", t[m.end():]):
                    self.sets.add(m.group())
                self.reads.add(m.group())
                i = m.end()
                continue
            i += 1
        self.broken = True
        return i

    def expand(self, i, end, quote):
        """The expansions up to END, or to the closing QUOTE when set."""
        t = self.t
        while i < end:
            c = t[i]
            if c == "\\":
                i += 2
            elif quote and c == quote:
                return i + 1
            elif c == "$":
                i = self.dollar(i)
            else:
                i += 1
        self.broken |= bool(quote)
        return i

    def take_heredocs(self, i):
        t = self.t
        while self.heredocs:
            delim, quoted, strip = self.heredocs[0]
            start = i
            while i < self.n:
                end = t.find("\n", i)
                end = self.n if end < 0 else end
                line = t[i:end]
                i = end + 1
                if (line.lstrip("\t") if strip else line) == delim:
                    self.words.append((start, end - len(line), t[start:end - len(line)]))
                    if not quoted:
                        self.expand(start, end - len(line), None)
                    self.heredocs.pop(0)
                    break
            else:
                return i
        return i

    def code(self, i, close, values=False):
        t = self.t
        words = []  # per word: (its unquoted literal text, that text when the word is all literal, its source text)
        cur = None
        case = 0

        def end_word():
            nonlocal cur, case
            if cur is not None:
                words.append((cur[0], cur[0] if cur[1] else None, t[cur[2]:i], cur[2], i))
                self.words.append((cur[2], i, t[cur[2]:i]))
                cur = None
                if not values:
                    case += self.word(words)

        def end_command():
            end_word()
            if words and not values:
                self.command(words)
            words.clear()

        def part(literal):
            nonlocal cur
            cur = cur or ["", True, i]
            if literal is None:
                cur[1] = False
            elif cur[1]:
                cur[0] += literal

        while i < self.n:
            c = t[i]
            if c == "\n":
                end_command()
                i = self.take_heredocs(i + 1)
            elif c in " \t":
                end_word()
                i += 1
            elif c == "#" and cur is None:
                j = t.find("\n", i)
                i = self.n if j < 0 else j
            elif c == "\\":
                if not t.startswith("\n", i + 1):
                    part(t[i + 1:i + 2])
                i += 2
            elif c == "'":
                part(None)
                i = self.single(i + 1)
            elif c == '"':
                part(None)
                i = self.expand(i + 1, self.n, '"')
            elif c == "$":
                part(None)
                i = self.dollar(i)
            elif t.startswith("<<", i) and not t.startswith("<<<", i):
                end_word()
                m = HEREDOC.match(t, i)
                if m:
                    self.heredocs.append((m.group(3), bool(m.group(2)), bool(m.group(1))))
                i = m.end() if m else i + 2
            elif c in "<>" and t.startswith("(", i + 1):
                end_word()
                i = self.code(i + 2, ")")
            elif c == "(":
                if cur is not None and cur[1] and cur[0] and t.startswith(")", i + 1):
                    self.funcs.add(cur[0])
                    self.defining = (cur[0], cur[2])
                    cur = None
                    words.clear()
                    i += 2
                elif cur is not None and cur[1] and cur[0].endswith("="):
                    name, start = cur[0][:-1], cur[2]
                    end_word()  # name=( WORDS ): the words are values
                    first = len(self.words)
                    i = self.code(i + 1, ")", values=True)
                    self.arrays.append((name, start, list(self.words[first:])))
                elif cur is None and t.startswith("((", i):
                    i = self.arith(i + 2)
                else:
                    end_command()
                    i = self.code(i + 1, ")")
            elif c == ")":
                end_command()
                i += 1
                if close == ")" and not case:
                    return i
            elif c in ";|&":
                end_command()
                i += 1
            elif c in "<>":
                end_word()
                i += 1
            else:
                part(c)
                i += 1
        end_command()
        self.broken |= close is not None
        return i

    def word(self, words):
        """Read the word that just ended; return the change in case depth."""
        prefix, whole = words[-1][:2]
        pos, at = len(words) - 1, head(words)
        if pos == at:
            if whole != "{":
                self.defining = None
            m = ASSIGN.match(prefix)
            if m:
                self.sets.add(m.group(1))
            elif whole == "{":
                self.depth += 1
                if self.defining:
                    name, start = self.defining
                    self.bodies.append((name, self.depth, []))
                    self.open_spans.append((name, start, self.depth))
                    self.defining = None
                words.clear()
            elif whole == "}":
                if self.open_spans and self.open_spans[-1][2] == self.depth:
                    name, start, _ = self.open_spans.pop()
                    self.spans.append((name, start, words[-1][4]))
                if self.bodies and self.bodies[-1][1] == self.depth:
                    name, _, shifts = self.bodies.pop()
                    if shifts and shifts[-1] == "runs" and len(shifts) <= 2 and None not in shifts:
                        self.runners[name] = shifts[0] if len(shifts) == 2 else 0
                self.depth -= 1
            elif whole in RESET:
                words.clear()
            return {"case": 1, "esac": -1}.get(whole, 0)
        cmd, args = words[at][1], [w[1] for w in words[at + 1:]]
        prev = args[-2] if len(args) > 1 else None
        if cmd == "smoke_row" and len(args) == 1 and whole:
            self.rows.add(whole)
        elif cmd == "function" and len(args) == 1 and whole:
            self.funcs.add(whole)
        elif cmd in DECLARE:
            m = NAME.match(prefix)
            if m and not prefix.startswith("-"):
                self.sets.add(m.group())
        elif cmd in ("for", "select") and len(args) == 1 and whole:
            self.sets.add(whole)
        elif cmd == "printf" and prev == "-v" and whole:
            self.sets.add(whole)
        elif cmd == "getopts" and len(args) == 2 and whole:
            self.sets.add(whole)
        elif cmd in TAKES and whole and NAME.fullmatch(whole):
            if not (prev and prev.startswith("-") and prev[-1] in TAKES[cmd]):
                self.sets.add(whole)
        return 0

    def command(self, words):
        """Keep a command's words, and note in the innermost open function
        body each shift and the "$@" it runs: a body runs its arguments when
        it holds at most one literal shift and then runs "$@"."""
        self.commands.append(list(words))
        source = SOURCE.match(" ".join(word[2] for word in words[head(words):]))
        if source and re.fullmatch(r"scripts/smoke/rows/[a-z0-9-]+\.sh", source[1]):
            self.sources.add(pathlib.Path(source[1]).stem)
        if not self.bodies or self.bodies[-1][2][-1:] == ["runs"]:
            return
        at, shifts = head(words), self.bodies[-1][2]
        if words[at][1] == "shift":
            count = words[at + 1][1] if at + 1 < len(words) else "1"
            shifts.append(int(count) if count and count.isdigit() else None)
        elif words[at][2] == '"$@"':
            shifts.append("runs")
