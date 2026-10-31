#!/usr/bin/env python3
"""Check literal smoke PATH absence assertions against the runner's hidden names.

VGS-2092: host-installed ttfx broke screensaver's absence control. Read source
without loading the harness or resolving any host command. Usage: [REPO].
Exit 1 for an unhidden assertion, 2 for unreadable or missing source evidence.
"""
import pathlib
import re
import sys

# These are the literal array and one-line expect forms the runner/rows emit.
HIDDEN = re.compile(r"^shell_hidden_commands\+=\(([a-zA-Z0-9_.+ -]+)\)$", re.M)
ABSENT = re.compile(r'''^[ \t]*expect[ \t]+(?:"[^"\n]*"|'[^'\n]*')\s+none\s+shell_resolves\s+(\S+)''', re.M)


def main(root):
    try:
        hidden = HIDDEN.findall((root / "scripts/qml-smoke.sh").read_text())
        rows = sorted((root / "scripts/smoke/rows").glob("*.sh"))
        if len(hidden) != 1 or not rows:
            raise ValueError("missing literal hidden array or smoke rows")
        names = set(hidden[0].split())
        assertions = 0
        status = 0
        for path in rows:
            text = path.read_text()
            for match in ABSENT.finditer(text):
                command = match[1]
                covered = command in names
                line = text.count("\n", 0, match.start()) + 1
                print(f"smoke-hidden: command={command} hidden={str(covered).lower()} path={path.relative_to(root)} line={line}")
                assertions += 1
                if not covered:
                    status = 1
        if not assertions:
            raise ValueError("no PATH absence assertions found")
        return status
    except (OSError, UnicodeError, ValueError) as error:
        print(f"smoke-hidden: unreadable={error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    root = pathlib.Path(sys.argv[1]) if len(sys.argv) == 2 else pathlib.Path(__file__).resolve().parent.parent
    sys.exit(main(root))
