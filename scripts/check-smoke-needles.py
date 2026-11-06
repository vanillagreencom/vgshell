#!/usr/bin/env python3
"""Refuse smoke edit needles that overlap QML/JavaScript comments.

Usage: check-smoke-needles.py [ROOT]
ROOT defaults to the repository. Read every smoke row with the shared Bash
reader, following local function calls and static variable/array/heredoc
values into edit_tree NAME FILE OLD NEW and plugin_control FILE LABEL OLD NEW.
No shell program is executed. An unresolved reached target or needle refuses
with needle-unreadable, rather than certifying a partial scan. The check does
not judge comments in other languages. Each finding names the row and line.
Exit 0 when clean, 1 on a comment overlap, 2 on an unreadable source/value.
"""
import itertools
import pathlib
import re
import sys

from qml_source import Unreadable as SourceUnreadable, blank_comments, source_texts
from shell_source import ASSIGN, DECLARE, Scan, head

ROOT = pathlib.Path(__file__).resolve().parent.parent
VARIABLE = re.compile(r'\$(?:\{([A-Za-z_][\w]*|[0-9]+|@)(?:\[@\])?\}|([A-Za-z_][\w]*|[0-9]+|@))')
UNKNOWN = None


class Unreadable(Exception):
    pass


def word(raw, lookup):
    """Static Bash word expansion; None is an unresolved value.

    Only literal quoting, escapes, parameters and a cat heredoc substitution
    are admitted. Arbitrary command substitutions never run.
    """
    values = ['']
    i = 0
    quote = None
    while i < len(raw):
        ch = raw[i]
        if ch == "'" and quote is None:
            end = raw.find("'", i + 1)
            if end < 0:
                return UNKNOWN
            chunk = raw[i + 1:end]
            i = end + 1
        elif raw.startswith("$'", i) and quote is None:
            end = i + 2
            chunk = ''
            escapes = {'n': '\n', 'r': '\r', 't': '\t', 'a': '\a', 'b': '\b', 'e': '\x1b', 'f': '\f', 'v': '\v', '\\': '\\', "'": "'", '"': '"'}
            while end < len(raw) and raw[end] != "'":
                if raw[end] == '\\' and end + 1 < len(raw):
                    end += 1
                    chunk += escapes.get(raw[end], '\\' + raw[end])
                else:
                    chunk += raw[end]
                end += 1
            if end == len(raw):
                return UNKNOWN
            i = end + 1
        elif ch == '"':
            quote = None if quote == '"' else '"'
            i += 1
            continue
        elif ch == '\\':
            if i + 1 == len(raw):
                return UNKNOWN
            nxt = raw[i + 1]
            chunk = '' if nxt == '\n' else (nxt if quote is None or nxt in '$`"\\' else '\\' + nxt)
            i += 2
        elif raw.startswith('$(', i):
            match = re.match(r"\$\(\s*cat\s*<<(-?)[ \t]*(['\"]?)(\w+)\2[^\n]*\n", raw[i:])
            if not match:
                return UNKNOWN
            start = i + match.end()
            ending = re.search(r'(?m)^\t*' + re.escape(match[3]) + r'\n?\s*\)', raw[start:])
            if not ending:
                return UNKNOWN
            chunk = raw[start:start + ending.start()]
            if match[1]:
                chunk = '\n'.join(line.lstrip('\t') for line in chunk.split('\n'))
            if not match[2]:
                expanded = word('"' + chunk.replace('"', '\\"') + '"', lookup)
                if expanded is None:
                    return UNKNOWN
                chunk_values = expanded
            else:
                chunk_values = [chunk]
            chunk_values = [value.rstrip('\n') for value in chunk_values]
            values = [a + b for a, b in itertools.product(values, chunk_values)]
            i = start + ending.end()
            continue
        elif ch == '$':
            match = VARIABLE.match(raw, i)
            if not match:
                return UNKNOWN
            resolved = lookup(match[1] or match[2])
            if resolved is None:
                return UNKNOWN
            values = [a + b for a, b in itertools.product(values, resolved)]
            if len(values) > 256:
                return UNKNOWN
            i = match.end()
            continue
        elif ch == '`':
            return UNKNOWN
        else:
            chunk = ch
            i += 1
        values = [value + chunk for value in values]
    return sorted(set(values)) if quote is None else UNKNOWN


class Row:
    def __init__(self, path):
        self.path = path
        self.text = path.read_text()
        self.scan = Scan(self.text)
        if self.scan.broken:
            raise Unreadable(f'{path}: shell-reading')
        self.commands = {}
        self.bindings = {}
        self.arrays = {}
        shifts = {}
        for words in self.scan.commands:
            scope = self.scope(words[0][3])
            self.commands.setdefault(scope, []).append(words)
            at = head(words)
            if words[at][1] == 'shift':
                amount = words[at + 1][1] if len(words) > at + 1 else '1'
                shifts[scope] = shifts.get(scope, 0) + int(amount) if amount and amount.isdigit() and shifts.get(scope, 0) is not None else None
            assignments = words if words[at][1] in DECLARE else words[:at + 1]
            for token in assignments:
                match = ASSIGN.match(token[2])
                if match:
                    rhs = token[2][match.end():]
                    self.bindings.setdefault((scope, match[1]), []).append((rhs, shifts.get(scope, 0)))
        for name, start, tokens in self.scan.arrays:
            self.arrays[(self.scope(start), name)] = [token[2] for token in tokens]
        self.sites = {words[head(words)][3] for words in self.scan.commands if words[head(words)][1] in ('edit_tree', 'plugin_control')}
        self.covered = set()
        self.needed = {'edit_tree', 'plugin_control'}
        while True:
            added = {scope for scope, commands in self.commands.items() if scope and any(words[head(words)][1] in self.needed for words in commands)}
            if added <= self.needed:
                break
            self.needed.update(added)

    def scope(self, offset):
        enclosed = [(end - start, name) for name, start, end in self.scan.spans if start <= offset < end]
        return min(enclosed)[1] if enclosed else None

    def lookup(self, name, scope, params, seen):
        if name.isdigit():
            at = int(name) - 1
            return params[at] if 0 <= at < len(params) else None
        key = (scope, name) if (scope, name) in self.bindings or (scope, name) in self.arrays else (None, name)
        if key in seen:
            return None
        expressions = self.bindings.get(key)
        if expressions is None:
            return None
        found = []
        for raw, shift in expressions:
            if shift is None:
                return None
            value = word(raw, lambda variable: self.lookup(variable, key[0], params[shift:] if variable.isdigit() else params, seen | {key}))
            if value is None:
                return None
            found.extend(value)
        return sorted(set(found))

    def expand(self, raw, scope, params, bound):
        array = re.fullmatch(r'"?\$\{([A-Za-z_]\w*)\[@\]\}"?', raw)
        if array:
            expressions = self.arrays.get((scope, array[1]), self.arrays.get((None, array[1])))
            if expressions is None:
                return [None]
            return [word(value, lambda name: self.lookup(name, scope, params if name.isdigit() else bound, set())) for value in expressions]
        if raw in ('"$@"', '$@'):
            return params
        return [word(raw, lambda name: self.lookup(name, scope, params if name.isdigit() else bound, set()))]

    def edits(self, scope=None, params=(), stack=()):
        if scope in stack:
            raise Unreadable(f'{self.path}: recursive-edit-function={scope}')
        bound = params
        commands = self.commands.get(scope, [])
        for index, words in enumerate(commands):
            at = head(words)
            command = words[at][1]
            if command == 'shift':
                count = words[at + 1][1] if at + 1 < len(words) else '1'
                if not count or not count.isdigit():
                    params = ()
                else:
                    params = params[int(count):]
                continue
            if command not in self.needed:
                continue
            arguments = [value for token in words[at + 1:] for value in self.expand(token[2], scope, params, bound)]
            line = self.text.count('\n', 0, words[at][3]) + 1
            if command in ('edit_tree', 'plugin_control'):
                self.covered.add(words[at][3])
                if len(arguments) < 4:
                    raise Unreadable(f'{self.path}:{line}: edit-arguments')
                yield line, arguments[1 if command == 'edit_tree' else 0], arguments[2]
                # A shifted argument loop, used by sa_copy, applies each group.
                after = commands[index + 1] if index + 1 < len(commands) else []
                if after and after[head(after)][1] == 'shift' and len(after) > 1:
                    step = after[-1][1]
                    before = self.text[:words[at][3]]
                    if step and step.isdigit() and int(step) and re.search(r'while\s+\(\(\s*\$#\s*>=\s*' + step + r'\s*\)\)\s*;\s*do\s*$', before):
                        for offset in range(int(step), len(params), int(step)):
                            shifted = [value for token in words[at + 1:] for value in self.expand(token[2], scope, params[offset:], bound)]
                            if len(params) - offset >= int(step):
                                yield line, shifted[1 if command == 'edit_tree' else 0], shifted[2]
            else:
                yield from self.edits(command, arguments, (*stack, scope))


def main():
    root = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else ROOT
    if len(sys.argv) > 2:
        print('needle-unreadable argument-count')
        return 2
    findings = []
    count = 0
    try:
        rows = sorted((root / 'scripts/smoke/rows').glob('*.sh'))
        if not rows:
            raise Unreadable('no-smoke-rows')
        sources = {}
        for name, text in source_texts(str(root / 'shell')):
            spans = []
            blank_comments(text, comments=spans)
            sources[str(pathlib.Path(name).relative_to(root))] = (text, spans)
        for path in rows:
            row = Row(path)
            for line, targets, needles in row.edits():
                count += 1
                if targets is None:
                    raise Unreadable(f'{path}:{line}: target-unresolved')
                for target in targets:
                    if not target.endswith(('.qml', '.js')):
                        continue
                    if needles is None or not needles or '' in needles:
                        raise Unreadable(f'{path}:{line}: needle-unresolved')
                    target = target if target.startswith('shell/') else 'shell/plugins/vgs.themes/' + target
                    if target not in sources:
                        raise Unreadable(f'{path}:{line}: target-unreadable={target}')
                    text, spans = sources[target]
                    for needle in needles:
                        starts = [match.start() for match in re.finditer(re.escape(needle), text)]
                        if not starts:
                            raise Unreadable(f'{path}:{line}: needle-unmatched target={target} needle={needle!r}')
                        if any(start < b and start + len(needle) > a for start in starts for a, b in spans):
                            findings.append(f'needle-comment {path}:{line} target={target}')
            if row.sites - row.covered:
                missing = sorted(row.text.count('\n', 0, offset) + 1 for offset in row.sites - row.covered)
                raise Unreadable(f'{path}: edit-calls-unresolved lines={missing}')
    except (OSError, UnicodeError, Unreadable, SourceUnreadable) as exc:
        print(f'needle-unreadable {exc}')
        return 2
    for finding in sorted(set(findings)):
        print(finding)
    if findings:
        return 1
    print(f'check-smoke-needles: ok rows={len(rows)} edits={count}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
