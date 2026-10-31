#!/usr/bin/env python3
"""The repository's absence assertions and a disposable missing-ttfx control."""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHECK = ROOT / "scripts/check-smoke-hidden.py"
ENV = {"PATH": os.environ.get("PATH", ""), "LC_ALL": "C"}


def run(root):
    return subprocess.run([sys.executable, str(CHECK), str(root)], env=ENV, capture_output=True, text=True, timeout=30)


result = run(ROOT)
assert result.returncode == 0, result.stdout + result.stderr
commands = {line.split()[1].removeprefix("command=") for line in result.stdout.splitlines()}
assert {"claude", "codex", "vgshell-browser-policy", "ttfx", "tesseract"} <= commands, result.stdout
assert "rclone" not in commands, result.stdout  # A present-command assertion is not an absence control.
print("ok repository absence assertions covered; presence assertions excluded")

with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    shutil.copytree(ROOT / "scripts/smoke/rows", root / "scripts/smoke/rows")
    runner = root / "scripts/qml-smoke.sh"
    source = (ROOT / "scripts/qml-smoke.sh").read_text()
    old = " codex ttfx)"
    assert source.count(old) == 1
    mutant = source.replace(old, " codex)")
    assert mutant != source
    runner.write_text(mutant)
    result = run(root)
    assert result.returncode == 1, result.stdout + result.stderr
    missing = [line.split()[1] for line in result.stdout.splitlines() if "hidden=false" in line]
    assert missing == ["command=ttfx"], result.stdout
    print("ok must-fail control: unhidden ttfx rejected with assertion intact")
    for state in ("missing-array", "missing-rows", "no-assertions"):
        runner.write_text("" if state == "missing-array" else source)
        if state == "missing-rows":
            shutil.rmtree(root / "scripts/smoke/rows")
        elif state == "no-assertions":
            (root / "scripts/smoke/rows").mkdir()
            (root / "scripts/smoke/rows/empty.sh").write_text("# none shell_resolves ttfx\n")
        result = run(root)
        assert result.returncode == 2, result.stdout + result.stderr
        print(f"ok incomplete discovery refused: {state}")
