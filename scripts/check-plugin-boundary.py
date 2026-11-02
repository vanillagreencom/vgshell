#!/usr/bin/env python3
"""Enforce the plugin boundary docs/architecture/overview.md § Rules states.

Plugin rules, one per QML or JS file under a plugin directory:
  import-module      a module import starts with QtQuick, QtQml, Qt.labs., qs.Commons,
                     qs.Ui or Quickshell, never Quickshell.Wayland or QtQuick.Window
  import-path        a quoted import stays inside the plugin directory
  surface-type       no window or layer-shell type is instantiated
  core-type          no object the core lends through a capability is instantiated
                     (IpcHandler, GlobalShortcut, NotificationServer, PolkitAgent) and
                     Hyprland.dispatch is never called
  theme-input        no write to Theme's input: `appearanceInput`, the user's
                     Appearance values, which Config alone binds; a plugin
                     writes them through capability `appearance`
  status-reply       a `shell.status.set` reply is judged by `shell.status.isOk`
                     before any comparison with a string literal, so a retired
                     instance's refusal is never read as a failure. The rule
                     covers `(const|let) NAME = (root.)?shell.status.set(` and a
                     `status.set(...)` call compared with a literal directly.
                     A binding's span runs to the next `const`, `let` or `var`
                     binding of NAME in the file, or its end; a literal
                     comparison of NAME in the span is a finding unless
                     `status.isOk(NAME)` comes before it in the span. A reply
                     that leaves its binding, returned, put in an array or
                     passed to a function, is outside the rule; review holds it.
Core rules, one per QML or JS file under shell/ outside shell/plugins/:
  core-plugin-name   no first-party plugin id literal (the `vgs.` prefix alone is fine)
  core-plugin-import no import of a plugin directory

Every rule reads code only, through `scripts/qml_source.py`: comments are
blanked before matching, with line numbers kept, and string literals stay, so a
window type inside a string handed to Qt.createQmlObject is still a finding.
`status-reply` reads the same code with string contents blanked too, so a
parenthesis or a name inside a string is not code.

Usage: check-plugin-boundary.py [--shell DIR] [PLUGIN_DIR...]
With no plugin directories, every plugin under DIR/plugins is checked, listed
the way the shell lists them: by bin/vgshell-scan, so a directory with no
manifest.json is not a plugin and a file or directory the scan cannot read ends
the run, named by the path that failed.

Every finding is one line: `<rule> <file>:<line> <detail>`. Exit 0 when clean,
1 on any finding, 2 when any directory or source file cannot be read, printed as
`check-plugin-boundary: unreadable: <path>: <strerror>`. An incomplete traversal
never certifies a tree: the first read failure ends the run before any verdict.
"""
import argparse
import json
import os
import re
import subprocess
import sys

# A check writes nothing into the tree it reads, so the shared module leaves
# no bytecode cache beside it.
sys.dont_write_bytecode = True
from qml_source import SCAN, Unreadable, blank_comments, source_lines, source_texts

# The scan runs under this environment and nothing inherited beyond it.
SCAN_ENV = {"PATH": os.environ.get("PATH", ""), "LC_ALL": "C"}

ALLOWED_PREFIXES = ("QtQuick", "QtQml", "Qt.labs.", "Quickshell", "qs.Commons", "qs.Ui")
REFUSED_MODULES = ("Quickshell.Wayland", "QtQuick.Window")
SURFACE_TYPES = ("PanelWindow", "FloatingWindow", "PopupWindow", "WlSessionLock", "WlSessionLockSurface", "WlrLayershell", "Window", "ApplicationWindow")
LENT_TYPES = ("IpcHandler", "GlobalShortcut", "NotificationServer", "PolkitAgent")
# A QML file imports with `import`, a JS file with `.import`.
MODULE_IMPORT = re.compile(r"^\s*\.?import\s+([A-Za-z][\w.]*)")
PATH_IMPORT = re.compile(r"^\s*\.?import\s+\"([^\"]+)\"")
SURFACE = re.compile(r"\b(" + "|".join(SURFACE_TYPES) + r")\s*\{")
LENT = re.compile(r"\b(" + "|".join(LENT_TYPES) + r")\s*\{|\b(Hyprland\.dispatch)\s*\(")
THEME_INPUT = re.compile(r"\bappearanceInput\b")
PLUGIN_ID_LITERAL = re.compile(r"[\"'`]vgs\.[a-z]")
PLUGIN_DIR_IMPORT = re.compile(r"^\s*\.?import\s+\"[^\"]*plugins/")
REPLY_BINDING = re.compile(r"\b(?:const|let)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:root\.)?shell\.status\.set\(")
STATUS_SET = re.compile(r"\bstatus\.set\(")
# With string contents blanked a literal is its two quotes and spaces.
LITERAL = r"(?:\"[ ]*\"|'[ ]*')"
EQUALITY = r"(?:===|!==|==|!=)"
LITERAL_AFTER = re.compile(r"\s*" + EQUALITY + r"\s*" + LITERAL)
LITERAL_BEFORE = re.compile(LITERAL + r"\s*" + EQUALITY + r"\s*$")
RECEIVER = re.compile(r"[\w$.]*$")


def module_allowed(name):
    for refused in REFUSED_MODULES:
        if name == refused or name.startswith(refused + "."):
            return False
    for allowed in ALLOWED_PREFIXES:
        if allowed.endswith("."):
            if name.startswith(allowed):
                return True
        elif name == allowed or name.startswith(allowed + "."):
            return True
    return False


def check_plugin(plugin_dir, findings):
    real_root = os.path.realpath(plugin_dir)
    for path, number, line in source_lines(plugin_dir):
        m = MODULE_IMPORT.match(line)
        if m and not module_allowed(m.group(1)):
            findings.append(f"import-module {path}:{number} {m.group(1)}")
        m = PATH_IMPORT.match(line)
        if m:
            target = os.path.realpath(os.path.join(os.path.dirname(path), m.group(1)))
            if not target.startswith(real_root + os.sep) and target != real_root:
                findings.append(f"import-path {path}:{number} {m.group(1)}")
        m = SURFACE.search(line)
        if m:
            findings.append(f"surface-type {path}:{number} {m.group(1)}")
        m = LENT.search(line)
        if m:
            findings.append(f"core-type {path}:{number} {m.group(1) or m.group(2)}")
        if THEME_INPUT.search(line):
            findings.append(f"theme-input {path}:{number} appearanceInput")
    for path, text in source_texts(plugin_dir):
        check_status_replies(path, text, findings)


def line_of(code, offset):
    return code.count("\n", 0, offset) + 1


def closing_paren(code, start):
    """Return the offset of the `)` that closes the `(` at `start`, or -1."""
    depth = 0
    for i in range(start, len(code)):
        if code[i] == "(":
            depth += 1
        elif code[i] == ")":
            depth -= 1
            if depth == 0:
                return i
    return -1


def check_status_replies(path, text, findings):
    code = blank_comments(text, literals=False)
    for m in STATUS_SET.finditer(code):
        close = closing_paren(code, m.end() - 1)
        receiver = m.start() - len(RECEIVER.search(code, 0, m.start()).group(0))
        line_start = code.rfind("\n", 0, receiver) + 1
        if (close != -1 and LITERAL_AFTER.match(code, close + 1)) or LITERAL_BEFORE.search(code, line_start, receiver):
            findings.append(f"status-reply {path}:{line_of(code, m.start())} status.set compared with a literal")
    for b in REPLY_BINDING.finditer(code):
        start, name = b.start(), b.group(1)
        rebound = re.compile(r"\b(?:const|let|var)\s+" + re.escape(name) + r"(?![\w$])").search(code, b.end())
        end = rebound.start() if rebound else len(code)
        word = r"(?<![\w$.])" + re.escape(name) + r"(?![\w$])"
        compare = re.compile(word + r"\s*" + EQUALITY + r"\s*" + LITERAL + "|" + LITERAL + r"\s*" + EQUALITY + r"\s*" + word)
        judged = re.compile(r"\bstatus\.isOk\(\s*" + re.escape(name) + r"\s*\)")
        first_judge = judged.search(code, start, end)
        for c in compare.finditer(code, start, end):
            if first_judge is None or first_judge.start() > c.start():
                findings.append(f"status-reply {path}:{line_of(code, c.start())} {name} compared with a literal before status.isOk({name})")


def check_core(shell_dir, findings):
    plugins_root = os.path.join(shell_dir, "plugins")
    for path, number, line in source_lines(shell_dir):
        if path.startswith(plugins_root + os.sep):
            continue
        if PLUGIN_ID_LITERAL.search(line):
            findings.append(f"core-plugin-name {path}:{number} {line.strip()}")
        if PLUGIN_DIR_IMPORT.match(line):
            findings.append(f"core-plugin-import {path}:{number} {line.strip()}")


def plugin_directories(base):
    scan = subprocess.run([SCAN, "--require-base", base], capture_output=True, text=True, check=False, env=SCAN_ENV)
    if scan.returncode != 0:
        raise Unreadable(base, f"vgshell-scan exited {scan.returncode}")
    entries = json.loads(scan.stdout)
    for entry in entries:
        if "error" in entry:
            raise Unreadable(entry["path"], entry["error"])
    return sorted(entry["dir"] for entry in entries)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--shell", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell"))
    parser.add_argument("plugin_dirs", nargs="*")
    args = parser.parse_args(argv[1:])
    shell_dir = os.path.abspath(args.shell)
    findings = []
    try:
        plugin_dirs = args.plugin_dirs or plugin_directories(os.path.join(shell_dir, "plugins"))
        for plugin_dir in plugin_dirs:
            check_plugin(plugin_dir, findings)
        check_core(shell_dir, findings)
    except Unreadable as exc:
        print(f"check-plugin-boundary: unreadable: {exc.path}: {exc.strerror}")
        return 2
    for line in findings:
        print(line)
    if findings:
        print(f"check-plugin-boundary: findings={len(findings)}")
        return 1
    print(f"check-plugin-boundary: ok plugins={len(plugin_dirs)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
