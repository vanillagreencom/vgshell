#!/usr/bin/env python3
"""Enforce the no-manual-commands rule of D061 on the text a user reads.

A setup step is automatic or one click. The interface shows no command,
except where VGS cannot run a step on this system and the user must run it
by hand. A plugin README keeps commands behind a "Show command" details
block. This check fails where user-facing text tells the user to run a
command:
  instruction   a clause that opens with an imperative verb of VERBS and
                names a command: inline code whose first word is a command
                head, or, outside Markdown, a command head as the verb's
                object; or a clause whose subject is inline code naming a
                command, followed by a verb of SUBJECT_VERBS, as in
                "`vgshell plugin enable x` brings it back". A clause opens at
                the start of the text, after `.`, `!`, `?`, `:` or `;`,
                after a comma, and after `or` or `then`. A first word that
                is a path names the command its last part does, so
                `bin/vgshell` is `vgshell`. Outside Markdown, a command
                head the verb takes as its other object, after a comma or
                `or`, is one too, as in "Run this again, or vgshell sudo
                revoke, to end it".
  shell-block   a fenced code block of Markdown, untagged or tagged with a
                shell of SHELL_FENCES, whose first command word is a command
                head.
  code-command  a command inside a string literal of shipped QML or
                JavaScript bound to a property of DRAWN, the text a page, a
                notice, a plugin's system notification or a CodeLine draws:
                inline code whose first word is a command head, or a literal
                that opens with a head and an argument, as "vgshell plugin
                enable x" does. A command
                there is copied off a label. A log line is read by
                `instruction` alone. A binding reaches back over the lines its statement
                wraps across, so `text: ready` then `? "..."` on the next
                line is bound to `text`.
  page-reference  prose that names a VGS page, tab or section in plain words
                (PAGE_REFERENCE), as "in Settings > AI model", "under
                Requirements" or "Open Capture settings" does, in a manifest
                string or a string literal. Such words
                are a link that opens the page: the words of LinkText's
                page reference, `[words](page:<plugin id>)`, or of a
                manifest entry's `link`. A TUI line cannot link and names
                the button that opens the page instead. Markdown is not
                read for it.
  page-reference-target  a complete literal page reference whose plugin id
                names no plugin directory under the root's plugins/. A
                target completed by concatenation is not judged. With
                --plugin, the target directories are that plugin's siblings.
  page-reference-field  a complete literal `page:<id>/Settings/<field key>`
                reference whose key names no field of that plugin's
                manifest schema, which its Settings tab would not show.
  file-reference  a known file extension, ~/ path or absolute path in
                manifest prose or drawn/source prose outside a file link.
                PageReference.js reads inline links. File-action labels,
                explicit LinkText links and label/value folder choices
                already have their own route. Call arguments and CodeLine
                samples are data, not prose. Markdown and TUI text cannot
                draw the inline links and are not read for this rule.
A string literal is a quoted one or a template literal, whose `${...}`
parts read as the argument $ARG.
The text read is every Markdown file and every manifest.json of each plugin
directory under the root's plugins/, the user-facing strings of each
manifest (FIELDS, each key the judge admits named there or in EXEMPT), and
every string literal of every `.qml` and `.js` file
under the root, comments blanked through scripts/qml_source.py, and the
text a floating TUI draws: each quoted argument a script hands a drawing
function of bin/lib/tui.sh (TUI_DRAW), read as `instruction`, in every
file of a plugin's tui/ and, beside the root, every file of bin/ that
sources lib/tui.sh. A whole-line `#` comment is not read, and neither is
other output a script prints, which its command line shares. A
`<details>` block of Markdown whose `<summary>` reads "Show command" is not
read.

A command head is a command VGS knows a user could be told to run: a file
name in bin/, a requirement `command` of any plugin manifest under the root
or the repository's shell/ and of config/requirements.json, a binary of every manager in
shell/Core/PackageManagers.js and each of its elevators. The heads are read
from those artifacts, never listed here; fewer than HEADS_FLOOR, or a set
missing a REQUIRED_HEADS member, means an extractor broke, and the run ends
unreadable rather than certifying a tree against too few heads.

Usage: check-user-commands.py [ROOT | --plugin DIR]
ROOT is the repository's shell/ by default. `--plugin DIR` reads one plugin
directory alone, as `vgs-plugin check` passes it. The pass is
`check-user-commands: ok files=<n> strings=<n> heads=<n>`. Each finding is
one line `<rule> <file>:<line> <excerpt>`. Exit 0 when clean, 1 on any
finding, 2 when a file cannot be read or the heads are incomplete, printed
as `check-user-commands: unreadable: <what>: <why>`.
"""
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from qml_source import Unreadable, blank_comments, source_texts

REPO = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

VERBS = ("run", "type", "paste", "execute", "enter", "use", "call", r"install\s+with")
# What inline code does as the subject of a clause that tells the reader
# to run it, as in "`x` brings it back". A verb that as often says what a
# command does on its own, such as "starts" in "`vgshell run` starts the shell
# again", is not one.
SUBJECT_VERBS = ("brings", "fixes", "installs", "enables", "restores", "repairs", "sets", "turns", "adds", "connects", "stores")
SHELL_FENCES = ("", "bash", "sh", "shell", "console", "zsh", "fish")
# Prose that names a page of VGS: the Settings window by a path or as a
# place, a tab or standard section of a plugin's page, a page or tab by
# its name, or a plugin's settings to open.
PAGE_REFERENCE = re.compile(r"\bSettings >|\b(?:in|from) (?:Settings|Plugins)\b|\b[Uu]nder (?:Setup|Details|Requirements|Keys)\b"
                            r"|\bthe (?:[A-Z][\w-]* )+(?:page|tab)\b|\bOpen (?:[A-Z][\w-]* )+settings\b")
# The words of the page reference LinkText draws as a link. In a string
# literal its target may come from the next literal a concatenation adds.
PAGE_LINK = re.compile(r"\[[^\[\]\n]+\]\(page:")
# Only complete literal targets can be judged. An empty id opens the
# plugin list; a template argument or unfinished concatenation is unknown.
PAGE_TARGET = re.compile(PAGE_LINK.pattern + r"([^\s()/$]+)(?:/Settings/([^\s()/$]+)|/[^\s()/$]+)?\)")
# Extensions of the configuration and instruction files VGS cites. The
# path branch also catches extensionless folders and files.
FILE_NAME = re.compile(r"(?<![\w./~:$])(?:~?/[^\s<>\[\]`\"']+|[\w.-]+\.(?:lua|conf|config|ghostty|json|jsonc|md|txt|toml|ini|yaml|yml|qml|js|sh|service|desktop|hook))(?!\w|\.[A-Za-z0-9])", re.I)
URL = re.compile(r"\b[A-Za-z][A-Za-z0-9+.-]*://[^\s<>]+")
HEADS_FLOOR = 20
# Members the head extractors must yield: the core's own command and an
# elevator. A set without them came from a broken extractor.
REQUIRED_HEADS = ("vgshell", "sudo")

# The manifest keys a user reads, each a path whose `*` is any key of a
# table or index of a list.
FIELDS = (
    ("name",), ("description",), ("author",),
    ("schema", "*", "label"), ("schema", "*", "description"), ("schema", "*", "placeholder"), ("schema", "*", "info"), ("schema", "*", "tooltip"), ("schema", "*", "link", "text"), ("schema", "*", "group"), ("schema", "*", "options", "*", "label"), ("schema", "*", "presets", "*", "label"),
    ("schema", "*", "items", "*", "label"), ("schema", "*", "items", "*", "description"), ("schema", "*", "items", "*", "tooltip"), ("schema", "*", "items", "*", "placeholder"), ("schema", "*", "items", "*", "group"),
    ("schema", "*", "items", "*", "options", "*", "label"), ("schema", "*", "items", "*", "presets", "*", "label"),
    ("status", "*", "label"), ("status", "*", "group"), ("status", "*", "hint"), ("status", "*", "info"), ("status", "*", "link", "text"), ("status", "*", "action", "label"), ("status", "*", "actions", "*", "label"), ("status", "*", "aside", "label"), ("status", "*", "rowActions", "*", "label"),
    ("requirements", "*", "purpose"), ("requirements", "*", "dbus", "label"),
    ("pane", "group"),
    ("tui", "*", "title"), ("tui", "*", "entry", "label"), ("tui", "*", "entry", "group"),
    ("menu", "*", "label"), ("menu", "*", "description"), ("menu", "*", "toggle", "label"),
    ("hyprland", "binds", "*", "info"),
    ("sounds", "*", "label"), ("sounds", "*", "description"), ("sounds", "*", "own"),
    ("setupGuide", "title"), ("setupGuide", "text"), ("setupGuide", "link"),
    ("secrets", "label"),
)
# The keys the judge admits that the check does not read, and why: an
# identifier, a path or a value no one reads as prose.
EXEMPT = (
    ("schemaVersion",), ("id",), ("version",), ("license",), ("icon",), ("kinds",), ("entryPoints",),
    ("capabilities",), ("capabilityKinds",), ("systemSteps",), ("settings",), ("defaultSection",), ("pane", "order"), ("appearance",), ("alwaysOn",), ("formerIds",), ("idleStages",),
    ("schema", "*", "type"), ("schema", "*", "optionsFrom"), ("schema", "*", "link", "url"), ("schema", "*", "defaults"), ("schema", "*", "presets", "*", "value"), ("schema", "*", "separator"), ("schema", "*", "allowCustom"), ("schema", "*", "hideEmpty"), ("schema", "*", "shownWhen"), ("schema", "*", "format"), ("schema", "*", "unit"), ("schema", "*", "min"), ("schema", "*", "max"), ("schema", "*", "step"),
    ("status", "*", "setup"), ("status", "*", "setting"), ("status", "*", "step"),
    ("status", "*", "type"), ("status", "*", "hidden"), ("status", "*", "link", "url"),
    ("status", "*", "action", "tui"), ("status", "*", "action", "system"), ("status", "*", "action", "undo"), ("status", "*", "action", "tone"), ("status", "*", "action", "icon"), ("status", "*", "action", "dictation"), ("status", "*", "action", "file"),
    ("status", "*", "actions", "*", "tui"), ("status", "*", "actions", "*", "system"), ("status", "*", "actions", "*", "undo"), ("status", "*", "actions", "*", "tone"), ("status", "*", "actions", "*", "icon"), ("status", "*", "actions", "*", "dictation"), ("status", "*", "actions", "*", "file"),
    ("status", "*", "aside", "tui"), ("status", "*", "aside", "system"), ("status", "*", "aside", "undo"), ("status", "*", "aside", "tone"), ("status", "*", "aside", "icon"), ("status", "*", "aside", "dictation"), ("status", "*", "aside", "file"),
    ("status", "*", "rowActions", "*", "tui"), ("status", "*", "rowActions", "*", "system"), ("status", "*", "rowActions", "*", "undo"), ("status", "*", "rowActions", "*", "tone"), ("status", "*", "rowActions", "*", "icon"), ("status", "*", "rowActions", "*", "dictation"), ("status", "*", "rowActions", "*", "file"),
    ("status", "*", "settings"), ("status", "*", "icon"), ("status", "*", "plain"),
    ("setupGuide", "readme"),
    ("requirements", "*", "command"), ("requirements", "*", "dbus", "bus"), ("requirements", "*", "dbus", "name"), ("requirements", "*", "packages"), ("requirements", "*", "optional"), ("requirements", "*", "floor"), ("requirements", "*", "install"),
    ("tui", "*", "script"), ("tui", "*", "size"), ("tui", "*", "presentation"), ("tui", "*", "requires"), ("tui", "*", "entry", "icon"), ("tui", "*", "entry", "settings"),
    ("menu", "*", "icon"), ("menu", "*", "aliases"), ("menu", "*", "shortcut"), ("menu", "*", "tui"), ("menu", "*", "tuiGroup"), ("menu", "*", "provider"), ("menu", "*", "toggle", "setting"), ("menu", "*", "toggle", "icon"),
    ("secrets", "service"),
    ("sounds", "*", "default"), ("sounds", "*", "held"),
    ("hyprland", "binds", "*", "shortcut"), ("hyprland", "binds", "*", "key"), ("hyprland", "binds", "*", "hold"), ("hyprland", "binds", "*", "tap"), ("hyprland", "appearance"),
    ("hyprland", "layerRules", "*", "namespace"), ("hyprland", "layerRules", "*", "blur"), ("hyprland", "layerRules", "*", "ignoreAlpha"),
    ("hyprland", "options"), ("hyprland", "pads"), ("hyprland", "monitors"),
)

# A clause's rest runs to its sentence's end: a `.`, `!`, `?` or `;` that
# ends a word, never one inside inline code or a dotted name.
CLAUSE = re.compile(r"(?:^|[.!?:;]\s+|,\s*|\b(?:or|then)\s+)(" + "|".join(VERBS) + r")\b((?:`[^`\n]*`|[.!?;](?=[^\s`])|[^.!?;`\n])*)", re.I | re.M)
SUBJECT = re.compile(r"(?:^|[.!?:;]\s+|,\s*|\b(?:or|then)\s+)`([^`\n]+)`\s+(" + "|".join(SUBJECT_VERBS) + r")\b", re.I | re.M)
INLINE_CODE = re.compile(r"`([^`\n]+)`")
# The verb's other objects: what follows a comma, `, or` or `or`.
ALTERNATIVE = re.compile(r"(?:,\s*(?:or\s+)?|\bor\s+)([^\s,]+)")
# The functions of bin/lib/tui.sh that draw their arguments, and a shell
# script's quoted words.
TUI_DRAW = re.compile(r"\bvgs_tui_(?:header|step|success|warn|error|confirm|failed|refuse)\b([^\n]*)")
SH_STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"|\'[^\'\n]*\'')
SH_COMMENT = re.compile(r"(?m)^[ \t]*#.*$")
# In a string literal, code may run past its end into the next literal a
# concatenation adds, as `"`vgshell plugin enable " + id + "`"` does.
LITERAL_CODE = re.compile(r"`([^`\n]+)(?:`|$)")
FENCE = re.compile(r"^([ \t]*)(```+|~~~+)[ \t]*([A-Za-z0-9_+-]*)[^\n]*\n(.*?)^\1\2[ \t]*$", re.M | re.S)
DETAILS = re.compile(r"<details>\s*<summary>\s*Show command\s*</summary>.*?</details>", re.S | re.I)
# The properties whose text a component draws: a Label's and a Button's
# text, a Field's hint, info and error, a TextField's placeholder, a
# notice's title and message and those of shell.notify.send, a row's label
# and description.
DRAWN = ("text", "hint", "info", "error", "description", "placeholderText", "title", "message", "label", "secondary", "body", "summary")
DRAWN_BEFORE = re.compile(r"\b(?:" + "|".join(DRAWN) + r")\s*:")
STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\'')
# A quoted literal or a template literal, the quoted ones first, so a
# backtick inside a quoted literal opens no template.
LITERAL = re.compile(STRING.pattern + r"|`(?:[^`\\]|\\.)*`", re.S)
TEMPLATE_PART = re.compile(r"\$\{[^{}]*\}")
WORD = re.compile(r"[A-Za-z0-9./~][A-Za-z0-9._+/~-]*")
# A line that carries its statement on from the one before: it opens with
# an operator, or the line before ends with one.
CONTINUES = re.compile(r"[ \t]*(?:[?:+.)]|&&|\|\|)")
CONTINUED = re.compile(r"(?:[?:+(,=]|&&|\|\|)\s*$")


def unreadable(what, why):
    print(f"check-user-commands: unreadable: {what}: {why}")
    sys.exit(2)


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except (OSError, UnicodeError) as exc:
        unreadable(path, getattr(exc, "strerror", None) or str(exc))


def plugin_dirs(base):
    try:
        names = sorted(os.listdir(base))
    except OSError as exc:
        unreadable(base, exc.strerror)
    return [os.path.join(base, n) for n in names if os.path.isdir(os.path.join(base, n))]


def manager_heads():
    script = ("const m = require(process.argv[1]).load(process.argv[2]);"
              "process.stdout.write(JSON.stringify(m.MANAGERS.reduce((a, r) => a.concat(r.binaries), []).concat(m.ELEVATORS)));")
    try:
        out = subprocess.run(["node", "-e", script, os.path.join(REPO, "bin", "lib", "qml-library.js"),
                              os.path.join(REPO, "shell", "Core", "PackageManagers.js")],
                             capture_output=True, text=True, check=True, env={"PATH": os.environ.get("PATH", "/usr/bin:/bin")})
        heads = json.loads(out.stdout)
    except (OSError, subprocess.CalledProcessError, ValueError) as exc:
        unreadable("shell/Core/PackageManagers.js", "the managers' binaries did not load: " + str(exc).splitlines()[0])
    if not isinstance(heads, list) or not all(isinstance(h, str) for h in heads):
        unreadable("shell/Core/PackageManagers.js", "the managers' binaries are no list of names")
    return heads


def command_heads(root, manifests):
    heads = set(manager_heads())
    try:
        heads.update(n for n in os.listdir(os.path.join(REPO, "bin")) if os.path.isfile(os.path.join(REPO, "bin", n)))
    except OSError as exc:
        unreadable(os.path.join(REPO, "bin"), exc.strerror)
    core = os.path.join(REPO, "config", "requirements.json")
    shipped = []
    for d in plugin_dirs(os.path.join(REPO, "shell", "plugins")):
        path = os.path.join(d, "manifest.json")
        if os.path.exists(path):
            try:
                shipped.append((path, json.loads(read(path))))
            except ValueError as exc:
                unreadable(path, "not JSON: " + str(exc))
    for source, doc in [(core, json.loads(read(core)))] + shipped + manifests:
        reqs = doc if source == core else doc.get("requirements", [])
        for req in reqs if isinstance(reqs, list) else []:
            if isinstance(req, dict) and isinstance(req.get("command"), str):
                heads.add(req["command"])
    if len(heads) < HEADS_FLOOR or any(h not in heads for h in REQUIRED_HEADS):
        unreadable("command heads", f"found {len(heads)}, want at least {HEADS_FLOOR} holding {', '.join(REQUIRED_HEADS)}: an extractor is broken")
    return heads


def first_word(code):
    text = code.strip()
    if text.startswith("$ "):
        text = text[2:].lstrip()
    match = WORD.match(text)
    return os.path.basename(match.group(0).rstrip("/")) if match else ""


def line_of(text, index):
    return text.count("\n", 0, index) + 1


def statement_start(code, index):
    """Where the statement holding INDEX of CODE starts: the start of its
    line, moved back over each line it wraps from."""
    start = code.rfind("\n", 0, index) + 1
    while start > 0:
        before = code.rfind("\n", 0, start - 1) + 1
        if not (CONTINUES.match(code, start) or CONTINUED.search(code[before:start - 1])):
            break
        start = before
    return start


def enclosing_type(code, index):
    """The QML type whose `{` block holds INDEX of CODE, or ""."""
    depth = 0
    for at in range(index - 1, -1, -1):
        if code[at] == "}":
            depth += 1
        elif code[at] == "{":
            if depth == 0:
                match = re.search(r"([A-Z][A-Za-z0-9_]*)\s*$", code[:at])
                return match.group(1) if match else ""
            depth -= 1
    return ""


def opens_with_command(value, heads, copied):
    """Whether VALUE reads as a command line: a head, then an argument. A
    CodeLine's text (COPIED) is one whatever its words; drawn prose that
    opens with a command's name, as "vsys sees nothing wrong." does, is
    one only when it ends with no sentence stop and one of its arguments
    reads as a flag, a path, a dotted name, an assignment or a template
    literal's `${...}`, read as $ARG."""
    text = value.strip()
    if text.startswith("$ "):
        text = text[2:].lstrip()
    parts = text.split()
    if len(parts) < 2 or first_word(parts[0]) not in heads or parts[0] != WORD.match(parts[0]).group(0):
        return False
    return copied or (not text.endswith((".", "!", "?")) and any(re.search(r"^-|[./=:$]", word) for word in parts[1:]))


def blank(text, pattern):
    """TEXT with every match of PATTERN replaced by spaces, newlines kept."""
    return pattern.sub(lambda m: re.sub(r"[^\n]", " ", m.group(0)), text)


def instructions(text, heads, bare):
    """(index, excerpt) of each clause of TEXT that tells the reader to run
    a command: inline code naming a head, or with BARE a head as the verb's
    first word."""
    out = []
    for match in CLAUSE.finditer(text):
        rest = match.group(2)
        named = any(first_word(code) in heads for code in INLINE_CODE.findall(rest))
        if not named and bare:
            named = first_word(rest.lstrip("`\"' ")) in heads
        if not named and bare:
            named = any(first_word(word) in heads for word in ALTERNATIVE.findall(rest))
        if named:
            out.append((match.start(1), (match.group(1) + match.group(2)).strip()[:120]))
    for match in SUBJECT.finditer(text):
        if first_word(match.group(1)) in heads:
            out.append((match.start(), match.group(0).strip(" ,.;:!?")[:120]))
    return sorted(out)


def page_references(text, linked=""):
    """TEXT's excerpt, in a list, when it holds a plain page reference
    outside the words of a page reference and outside LINKED, the words
    its manifest entry's `link` draws as a link; else no excerpt."""
    plain = blank(text, PAGE_LINK)
    if linked:
        plain = plain.replace(linked, " " * len(linked))
    return [text.strip()[:120]] if PAGE_REFERENCE.search(plain) else []


def link_words(doc, where):
    """The words of the string of DOC at WHERE, a dotted path, that a
    manifest `link` draws as a link, or "": the `link.text` of the entry
    that holds the string, which is that text itself."""
    node = doc
    for key in where.split(".")[:-1]:
        node = node[int(key)] if isinstance(node, list) else node.get(key, {})
    link = node if where.endswith(".link.text") else node.get("link") if isinstance(node, dict) else None
    return link["text"] if isinstance(link, dict) and isinstance(link.get("text"), str) else ""


def file_action_label(doc, where):
    """Whether WHERE labels an action whose existing route opens a file."""
    if not where.endswith(".label"):
        return False
    node = doc
    for key in where.split(".")[:-1]:
        node = node[int(key)] if isinstance(node, list) else node.get(key, {})
    return isinstance(node, dict) and bool(node.get("file"))


def literal_context(masked, code, literal):
    """The enclosing expression's start and end, and its opening delimiter.

    A direct call argument is data (including fileReference and its local
    wrappers). An object member inside a call is still drawn prose.
    """
    depth = 0
    start = literal.start()
    for at in range(start - 1, -1, -1):
        if masked[at] in ")}]":
            depth += 1
        elif masked[at] in "({[":
            if depth == 0:
                end = at + 1
                nested = 1
                while end < len(masked) and nested:
                    if masked[end] in "({[":
                        nested += 1
                    elif masked[end] in ")}]":
                        nested -= 1
                    end += 1
                return at, end, masked[at]
            depth -= 1
    return 0, len(code), ""


def file_prose(code, masked, literal, value):
    """Source prose to judge, or empty for technical data/linked words."""
    start, end, delimiter = literal_context(masked, code, literal)
    if delimiter in ("(", "[") or "CodeLine" == enclosing_type(masked, literal.start()):
        return ""
    prefix = masked[start + (1 if delimiter else 0):literal.start()]
    bindings = list(re.finditer(r"(?:^|[;,\n])\s*(?:readonly\s+)?(?:property\s+\w+\s+)?(\w+)\s*:", prefix))
    binding = bindings[-1] if bindings else None
    if binding is not None and binding.group(1) not in DRAWN:
        return ""
    if binding is None and not re.search(r"\b(?:var|let|const)\s+\w+\s*=\s*$", prefix):
        return ""
    if re.search(r"^\s*(?:[\w.-]+\s*=|[a-z][\w-]*:)", value):
        return ""
    if binding is None and re.search(r"\s", value.strip()) is None:
        return ""
    block = code[start:end]
    if re.search(r"\blink\s*:\s*$", masked[:start]):
        return ""
    # Settings folder offers draw a label for the value they select; these
    # are choices of a folder, rather than citations in explanatory text.
    choice = re.search(r"\bvalue\s*:\s*(" + STRING.pattern + r")", block)
    if choice and choice.group(1)[1:-1] == value:
        return ""
    if enclosing_type(masked, literal.start()) == "LinkText":
        link = re.search(r"\blink\s*:\s*(" + STRING.pattern + r")", block)
        if link:
            words = link.group(1)[1:-1]
            value = value.replace(words, " " * len(words)) if words else value
    return value


def check_file_references(citations, findings, root, core):
    """Read inline references through their production owner, in one call."""
    if not citations:
        return
    script = ("const fs = require('fs'); const load = require(process.argv[1]).load; const m = load(process.argv[2]);"
              # The consent slot, not its input constants, owns the explicit
              # file link applied by NoticeHost. Read that shipped consumer.
              "const linked = new Map(); if (process.argv[3]) { const p = load(process.argv[3]);"
              "for (const state of p.WELCOME_STATES) for (const phase of p.WELCOME_SHOWS) {"
              "const view = p.consentSlotView({phase, failure: '', busy: false}, state, {}, []);"
              "if (view && view.link && view.link.path) for (const text of view.lines)"
              "linked.set(text, text.split(view.link.text).join(' '.repeat(view.link.text.length))); }}"
              "const texts = JSON.parse(fs.readFileSync(0, 'utf8'));"
              "process.stdout.write(JSON.stringify(texts.map(([text, consent]) => {"
              "if (consent && linked.has(text)) text = linked.get(text);"
              "const r = m.references(text); let plain = r.text;"
              "for (const link of r.links.slice().reverse()) if (m.file(link.page))"
              "plain = plain.slice(0, link.start) + ' '.repeat(link.end - link.start) + plain.slice(link.end);"
              "return plain; })));" )
    try:
        consumer = os.path.join(root, "Core", "PluginLogic.js")
        consumer = consumer if core and os.path.isfile(consumer) else ""
        inputs = [(text, bool(consumer) and os.path.dirname(path) == os.path.join(root, "Core"))
                  for path, _where, text in citations]
        done = subprocess.run(["node", "-e", script, os.path.join(REPO, "bin", "lib", "qml-library.js"),
                               os.path.join(REPO, "shell", "Commons", "PageReference.js"), consumer],
                              input=json.dumps(inputs), capture_output=True,
                              text=True, check=True, env={"PATH": os.environ.get("PATH", "/usr/bin:/bin")})
        plain = json.loads(done.stdout)
        if not isinstance(plain, list) or len(plain) != len(citations) or not all(isinstance(text, str) for text in plain):
            raise ValueError("reference reader returned incomplete text")
    except (OSError, subprocess.CalledProcessError, ValueError) as exc:
        unreadable("shell/Commons/PageReference.js", "file references did not load: " + str(exc).splitlines()[0])
    for (path, where, text), visible in zip(citations, plain):
        if FILE_NAME.search(blank(visible, URL)):
            findings.append(("file-reference", path, where, text.strip()[:120]))


def check_markdown(path, heads, findings):
    text = blank(read(path), DETAILS)
    for fence in FENCE.finditer(text):
        lang = fence.group(3).lower()
        body = [line for line in fence.group(4).splitlines() if line.strip()]
        if lang in SHELL_FENCES and body and first_word(body[0]) in heads:
            findings.append(("shell-block", path, line_of(text, fence.start()), body[0].strip()[:120]))
    prose = blank(text, FENCE)
    for index, excerpt in instructions(prose, heads, False):
        findings.append(("instruction", path, line_of(prose, index), excerpt))


def tui_scripts(root, dirs, core):
    """The files whose drawn text a floating TUI shows: every file of each
    plugin's tui/ in DIRS and, with CORE, every file of bin/ beside ROOT
    that sources lib/tui.sh."""
    out = []
    for d in dirs:
        tui = os.path.join(d, "tui")
        if os.path.isdir(tui):
            try:
                out.extend(os.path.join(tui, n) for n in sorted(os.listdir(tui)) if os.path.isfile(os.path.join(tui, n)))
            except OSError as exc:
                unreadable(tui, exc.strerror)
    bin_dir = os.path.join(os.path.dirname(root), "bin")
    if core and os.path.isdir(bin_dir):
        try:
            names = sorted(os.listdir(bin_dir))
        except OSError as exc:
            unreadable(bin_dir, exc.strerror)
        out.extend(path for path in (os.path.join(bin_dir, n) for n in names) if os.path.isfile(path) and "lib/tui.sh" in read(path))
    return out


def check_tui_script(path, heads, findings):
    """Each quoted argument of a TUI_DRAW call in the script at PATH, read
    as instruction; the count of words read. A terminal line cannot draw
    a page link, so it names the page and the button in words."""
    code = blank(read(path), SH_COMMENT)
    words = 0
    for call in TUI_DRAW.finditer(code):
        for word in SH_STRING.finditer(call.group(1)):
            words += 1
            for _index, excerpt in instructions(word.group(0)[1:-1], heads, True):
                findings.append(("instruction", path, line_of(code, call.start()), excerpt))
    return words


def resolve(node, pattern, where=()):
    """(where, value) of each value of NODE at PATTERN, a FIELDS path."""
    if not pattern:
        yield ".".join(where), node
        return
    head, rest = pattern[0], pattern[1:]
    if head == "*":
        items = node.items() if isinstance(node, dict) else enumerate(node) if isinstance(node, list) else []
        for key, child in items:
            yield from resolve(child, rest, where + (str(key),))
    elif isinstance(node, dict) and head in node:
        yield from resolve(node[head], rest, where + (head,))


def schema_keys(base, plugin):
    """The field keys of plugin PLUGIN's manifest schema under BASE."""
    path = os.path.join(base, plugin, "manifest.json")
    try:
        doc = json.loads(read(path))
    except ValueError as exc:
        unreadable(path, "not JSON: " + str(exc))
    schema = doc.get("schema") if isinstance(doc, dict) else None
    return set(schema) if isinstance(schema, dict) else set()


def manifest_strings(doc):
    """(where, text) of every user-facing string of manifest DOC (FIELDS)."""
    return [(where, value) for pattern in FIELDS for where, value in resolve(doc, pattern) if isinstance(value, str)]


def main(argv):
    core = True
    if len(argv) == 3 and argv[1] == "--plugin":
        root = os.path.realpath(argv[2])
        dirs = [root]
        core = False
    elif len(argv) <= 2 and (len(argv) == 1 or not argv[1].startswith("-")):
        root = os.path.realpath(argv[1]) if len(argv) == 2 else os.path.join(REPO, "shell")
        dirs = plugin_dirs(os.path.join(root, "plugins"))
    else:
        print("usage: check-user-commands.py [ROOT | --plugin DIR]")
        return 2
    manifests, markdown = [], []
    for d in dirs:
        path = os.path.join(d, "manifest.json")
        if os.path.exists(path):
            try:
                manifests.append((path, json.loads(read(path))))
            except ValueError as exc:
                unreadable(path, "not JSON: " + str(exc))
        for current, subdirs, files in os.walk(d, onerror=lambda e: unreadable(e.filename, e.strerror)):
            subdirs.sort()
            markdown.extend(os.path.join(current, f) for f in sorted(files) if f.endswith(".md"))
    plugin_base = os.path.join(root, "plugins") if core else os.path.dirname(root)
    targets = {os.path.basename(d) for d in plugin_dirs(plugin_base)}
    heads = command_heads(root, manifests)
    findings = []
    pages = []
    references = []
    citations = []
    strings = 0
    for path in markdown:
        check_markdown(path, heads, findings)
    scripts = tui_scripts(root, dirs, core)
    for path in scripts:
        strings += check_tui_script(path, heads, findings)
    for path, doc in manifests:
        for where, text in manifest_strings(doc):
            strings += 1
            for _index, excerpt in instructions(text, heads, True):
                findings.append(("instruction", path, where, excerpt))
            references.append((path, where, text))
            if not file_action_label(doc, where):
                citations.append((path, where, text))
            for excerpt in page_references(text, link_words(doc, where)):
                pages.append((path, where, excerpt))
    code_files = 0
    try:
        for path, text in source_texts(root):
            code_files += 1
            code = blank_comments(text)
            masked = blank(code, LITERAL)
            for literal in LITERAL.finditer(code):
                strings += 1
                token = literal.group(0)
                value = TEMPLATE_PART.sub("$ARG", token[1:-1]) if token.startswith("`") else token[1:-1]
                line = line_of(code, literal.start())
                for _index, excerpt in instructions(value, heads, True):
                    findings.append(("instruction", path, line, excerpt))
                references.append((path, line, value))
                for excerpt in page_references(value):
                    pages.append((path, line, excerpt))
                start = statement_start(masked, literal.start())
                prose = file_prose(code, masked, literal, value) if FILE_NAME.search(value) else ""
                if FILE_NAME.search(prose):
                    citations.append((path, line, prose))
                if DRAWN_BEFORE.search(masked, start, literal.start()) is None:
                    continue
                inline_named = not token.startswith("`") and any(first_word(inline) in heads for inline in LITERAL_CODE.findall(value))
                if inline_named or opens_with_command(value, heads, enclosing_type(masked, literal.start()) == "CodeLine"):
                    findings.append(("code-command", path, line, value.strip()[:120]))
    except Unreadable as exc:
        unreadable(exc.path, exc.strerror)
    files = len(markdown) + len(manifests) + len(scripts) + code_files
    if files == 0:
        unreadable(root, "no file to read: an empty walk certifies nothing")
    for path, where, text in references:
        for target in PAGE_TARGET.finditer(text):
            if target.group(1) not in targets:
                findings.append(("page-reference-target", path, where, text.strip()[:120]))
            elif target.group(2) is not None and target.group(2) not in schema_keys(plugin_base, target.group(1)):
                findings.append(("page-reference-field", path, where, text.strip()[:120]))
    for path, where, excerpt in pages:
        findings.append(("page-reference", path, where, excerpt))
    check_file_references(citations, findings, root, core)
    for rule, path, where, excerpt in findings:
        print(f"{rule} {os.path.relpath(path, REPO)}:{where} {excerpt}")
    if findings:
        print(f"check-user-commands: findings={len(findings)}")
        return 1
    print(f"check-user-commands: ok files={files} strings={strings} heads={len(heads)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
