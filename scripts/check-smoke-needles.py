#!/usr/bin/env python3
"""Refuse smoke edit needles that overlap QML/JavaScript comments.

Usage: check-smoke-needles.py [--unresolved-inputs] [ROOT]
ROOT defaults to the repository. Read every smoke row with the shared Bash
reader, following local function calls and static variable/array/heredoc
values into edit_tree NAME FILE OLD NEW and plugin_control FILE LABEL OLD NEW.
Read literal count/replace needles in shared harness/tree and row inline
Python too. No shell or Python program is executed. An unresolved Bash edit
refuses with needle-unreadable. Unsupported inline Python retains its input
reach: --unresolved-inputs prints target/producer TAB path records consumed
by validate's existing selection. Only shell/ QML/JS receives the selection
grant; the check does not judge comments in other languages. Each finding
names the producer and line.
Exit 0 when clean, 1 on a comment overlap, 2 on an unreadable source/value.
"""
import ast
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
        for words in commands:
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
                # sa_copy's guard is part of the loop body, between its edit
                # and shift. Certify the whole supported body before reading
                # every group; a partial last group is not coverage.
                before = self.text[:words[at][3]]
                loop = re.search(r'while\s+\(\(\s*\$#\s*>=\s*(\d+)\s*\)\)\s*;\s*do\s*$', before)
                if not loop and re.search(r'while[^\n]*;\s*do\s*$', before):
                    raise Unreadable(f'{self.path}:{line}: shifted-edit-loop')
                if loop:
                    step = int(loop[1])
                    tail = self.text[words[-1][4]:]
                    body = re.match(r'\s*(?:\|\|\s*return\s+1\s*)?[;\n]\s*shift\s+(\d+)\s*[;\n]\s*done\b', tail)
                    if not step or not body or int(body[1]) != step or len(params) % step:
                        raise Unreadable(f'{self.path}:{line}: shifted-edit-loop')
                    for offset in range(step, len(params), step):
                        shifted = [value for token in words[at + 1:] for value in self.expand(token[2], scope, params[offset:], bound)]
                        yield line, shifted[1 if command == 'edit_tree' else 0], shifted[2]
            else:
                yield from self.edits(command, arguments, (*stack, scope))

    def python_programs(self):
        """Inline Python only, from the same Bash command/word reading."""
        for words in self.scan.commands:
            at = head(words)
            if words[at][1] != 'python3':
                continue
            # These executors receive the already-enumerated Bash edit
            # operands. Reading their positional parameters again would
            # discard the call-site resolution above.
            if self.scope(words[at][3]) in ('edit_tree', 'plugin_control'):
                continue
            line = self.text.count('\n', 0, words[at][3]) + 1
            args = words[at + 1:]
            if args and args[0][1] == '-c' and len(args) > 1:
                programs = word(args[1][2], lambda name: self.lookup(name, self.scope(words[at][3]), (), set()))
                if programs:
                    for program in programs:
                        yield line, program, args[2:]
                continue
            end = self.text.find('\n', words[-1][4])
            header = self.text[words[-1][4]:end]
            heredoc = re.search(r"<<(-?)\s*(['\"]?)(\w+)\2", header)
            if heredoc:
                ending = re.search(r'(?m)^\t*' + re.escape(heredoc[3]) + r'$', self.text[end + 1:])
                if not ending:
                    raise Unreadable(f'{self.path}:{line}: python-heredoc')
                program = self.text[end + 1:end + 1 + ending.start()]
                if heredoc[1]:
                    program = '\n'.join(part.lstrip('\t') for part in program.split('\n'))
                if not heredoc[2] and re.search(r'[$`]', program):
                    program = None
                yield line, program, args[1:] if args and args[0][1] == '-' else args

    def suffixes(self, args):
        def lookup(name, seen=()):
            if name in seen:
                return ['\0']
            bindings = self.bindings.get((None, name), [])
            result = []
            for raw, _ in bindings:
                result.extend(word(raw, lambda other: lookup(other, (*seen, name))) or ['\0'])
            return result or ['\0']
        result = []
        for token in args:
            values = word(token[2], lookup) or ['\0']
            names = {value.rsplit('/', 1)[-1] for value in values}
            result.append(values[0] if len(values) == 1 else '\0/' + next(iter(names)) if len(names) == 1 else '\0')
        return result


def python_needles(program, arguments=()):
    """Read literal count/replace operands, never execute Python.

    The current producers use assignments and literal tuple tables. Anything
    outside those forms stays unresolved and retains its producer's input
    reach. Paths are literal source suffixes, not evaluated filesystem calls.
    """
    if program is None:
        return [], True
    try:
        tree = ast.parse(program)
    except SyntaxError:
        return [], True
    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)]
    if not any(node.func.attr == 'replace' for node in calls) or not any(node.func.attr == 'count' for node in calls):
        return [], False
    values = {}
    paths = set()
    path_names = {}
    needles = []
    unresolved = False
    argument_names = {}
    reads = []
    unknown_read = False

    def argument_index(node):
        if isinstance(node, ast.Name):
            return argument_names.get(node.id)
        if isinstance(node, ast.Call) and len(node.args) == 1 and (isinstance(node.func, ast.Name) and node.func.id == 'Path' or isinstance(node.func, ast.Attribute) and node.func.attr == 'Path'):
            return argument_index(node.args[0])
        if isinstance(node, ast.Subscript) and ast.unparse(node.value) == 'sys.argv' and isinstance(node.slice, ast.Constant) and isinstance(node.slice.value, int):
            return node.slice.value
        return None


    def literal(node):
        if isinstance(node, ast.Name):
            return values.get(node.id)
        if isinstance(node, (ast.Tuple, ast.List)):
            result = [literal(item) for item in node.elts]
            return result if all(item is not None for item in result) else None
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            left, right = literal(node.left), literal(node.right)
            return left + right if isinstance(left, str) and isinstance(right, str) else None
        try:
            return ast.literal_eval(node)
        except (ValueError, TypeError):
            return None

    def source_paths(node):
        value = literal(node)
        if isinstance(value, str) and value.endswith(('.qml', '.js')) and '\n' not in value:
            return {value.lstrip('/')}
        if isinstance(node, ast.Name) and path_names.get(node.id):
            return path_names[node.id]
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
            return source_paths(node.right)
        if isinstance(node, ast.Call) and len(node.args) == 1 and (isinstance(node.func, ast.Name) and node.func.id == 'Path' or isinstance(node.func, ast.Attribute) and node.func.attr == 'Path'):
            return source_paths(node.args[0])
        index = argument_index(node)
        if index is not None and 0 < index <= len(arguments):
            value = arguments[index - 1]
            suffix = value.rsplit('\0', 1)[-1]
            if value.endswith(('.qml', '.js')) and '\n' not in value and ('\0' not in value or suffix.startswith('/')):
                return {suffix.lstrip('/')}
        return None

    def forget_stores(statement):
        for node in ast.walk(statement):
            if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Store):
                values[node.id] = None
                argument_names[node.id] = None
                path_names[node.id] = None

    def statements(body):
        nonlocal unresolved, unknown_read
        for statement in body:
            if isinstance(statement, ast.For):
                if not any(isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == 'count' for node in ast.walk(statement)):
                    forget_stores(statement)
                    continue
                table = literal(statement.iter)
                names = [statement.target.id] if isinstance(statement.target, ast.Name) else [item.id for item in statement.target.elts] if isinstance(statement.target, (ast.Tuple, ast.List)) and all(isinstance(item, ast.Name) for item in statement.target.elts) else []
                if isinstance(table, list) and names:
                    for row in table:
                        parts = [row] if len(names) == 1 else row
                        if not isinstance(parts, (list, tuple)) or len(parts) != len(names):
                            unresolved = True
                            continue
                        values.update(zip(names, parts))
                        statements(statement.body)
                else:
                    unresolved = True
                    forget_stores(statement)
                continue
            if isinstance(statement, ast.Assign):
                value = literal(statement.value)
                assigned_paths = source_paths(statement.value)
                for target in statement.targets:
                    if not isinstance(target, ast.Name):
                        forget_stores(target)
                    if isinstance(target, ast.Name):
                        values[target.id] = value
                        argument_names[target.id] = argument_index(statement.value)
                        path_names[target.id] = assigned_paths
                    elif isinstance(target, (ast.Tuple, ast.List)) and isinstance(statement.value, ast.Subscript) and ast.unparse(statement.value.value) == 'sys.argv' and isinstance(statement.value.slice, ast.Slice) and isinstance(statement.value.slice.lower, ast.Constant) and isinstance(statement.value.slice.lower.value, int):
                        for index, name in enumerate(target.elts, statement.value.slice.lower.value):
                            if isinstance(name, ast.Name):
                                values[name.id] = None
                                argument_names[name.id] = index
                    elif isinstance(target, (ast.Tuple, ast.List)) and isinstance(statement.value, (ast.Tuple, ast.List)) and len(target.elts) == len(statement.value.elts):
                        for name, expression in zip(target.elts, statement.value.elts):
                            if isinstance(name, ast.Name):
                                values[name.id] = None
                                argument_names[name.id] = argument_index(expression)
                                path_names[name.id] = source_paths(expression)
            else:
                forget_stores(statement)
            for node in ast.walk(statement):
                if isinstance(node, ast.Call):
                    source = None
                    if isinstance(node.func, ast.Attribute) and node.func.attr == 'read_text':
                        source = node.func.value
                    elif isinstance(node.func, ast.Name) and node.func.id == 'open' and node.args and (len(node.args) == 1 or isinstance(node.args[1], ast.Constant) and node.args[1].value == 'r'):
                        source = node.args[0]
                    if source is not None:
                        reads.append(argument_index(source))
                        found = source_paths(source)
                        if found:
                            paths.update(found)
                        else:
                            unknown_read = True
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == 'count' and len(node.args) == 1:
                    needle = literal(node.args[0])
                    if isinstance(needle, str) and needle:
                        needles.append(needle)
                    else:
                        unresolved = True
    statements(tree.body)
    # A supplied filename with no source suffix (for example the generated
    # terminal script) cannot be a shell QML/JS dependency. Unknown roots or
    # computed filenames retain the producer's existing input reach.
    filenames = [arguments[index - 1] if index is not None and 0 < index <= len(arguments) else '\0' for index in reads]
    non_source = not paths and filenames and all(value.rsplit('/', 1)[-1] and '\0' not in value.rsplit('/', 1)[-1] and '\n' not in value and not value.endswith(('.qml', '.js')) for value in filenames)
    return [(paths, needle) for needle in needles], False if non_source else unresolved or unknown_read or bool(needles and not paths)


def main():
    args = sys.argv[1:]
    dependencies = bool(args and args[0] == '--unresolved-inputs')
    if dependencies:
        args.pop(0)
    root = pathlib.Path(args[0]).resolve() if args else ROOT
    if len(args) > 1:
        print('needle-unreadable argument-count')
        return 2
    findings = []
    count = 0
    unresolved = set()
    try:
        rows = sorted((root / 'scripts/smoke/rows').glob('*.sh'))
        if not rows and not dependencies:
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
        for path in [*rows, *(root / 'scripts/smoke' / name for name in ('harness.sh', 'tree.sh') if (root / 'scripts/smoke' / name).exists())]:
            row = Row(path)
            producer = str(path.relative_to(root))
            for line, program, arguments in row.python_programs():
                edits, unknown = python_needles(program, row.suffixes(arguments))
                if unknown:
                    unresolved.add(('producer', producer))
                for suffixes, needle in edits:
                    targets = {target for target in sources if any(target == suffix or target.endswith('/' + suffix) for suffix in suffixes)}
                    if not targets:
                        if suffixes or unknown:
                            unresolved.add(('producer', producer))
                        continue
                    matched = False
                    for target in targets:
                        text, spans = sources[target]
                        starts = [match.start() for match in re.finditer(re.escape(needle), text)]
                        matched |= bool(starts)
                        if any(start < b and start + len(needle) > a for start in starts for a, b in spans):
                            findings.append(f'needle-comment {path}:{line} target={target}')
                    if not matched or unknown:
                        unresolved.update(('target', target) for target in targets)
    except (OSError, UnicodeError, Unreadable, SourceUnreadable) as exc:
        print(f'needle-unreadable {exc}')
        return 2
    for finding in sorted(set(findings)):
        if not dependencies:
            print(finding)
    if dependencies:
        for kind, path in sorted(unresolved):
            print(f'{kind}\t{path}')
        return 0
    if findings:
        return 1
    print(f'check-smoke-needles: ok rows={len(rows)} edits={count}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
