#!/usr/bin/env python3
"""Exercise the nightly workflow's build decision with a fixed clock."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest


class NightlyCache(unittest.TestCase):
    def test_build_decision(self):
        workflow = Path(__file__).resolve().parents[1] / ".github/workflows/nightly.yml"
        source = workflow.read_text()
        blocks = re.findall(
            r"        id: build-decision\n.*?        run: \|\n((?:          [^\n]*\n|\n)+)",
            source,
            re.DOTALL,
        )
        self.assertEqual(len(blocks), 1)
        script = textwrap.dedent(blocks[0])
        bash = shutil.which("bash")
        self.assertIsNotNone(bash)
        now = 2_000_000_000
        prefix = "Linux-vgs-nightly-package-v1-"
        current = "a" * 64
        other = "b" * 64
        cases = (
            ("no pass", "", "false", False),
            ("recent pass", f"{prefix}{current}-{now - 604799}-1-1", "false", True),
            ("weekly boundary", f"{prefix}{current}-{now - 604800}-1-1", "false", False),
            ("stale pass", f"{prefix}{current}-{now - 604801}-1-1", "false", False),
            ("A through B to A", f"{prefix}{other}-{now - 1}-2-1", "false", False),
            ("forced recent pass", f"{prefix}{current}-{now - 1}-1-1", "true", False),
            ("future pass", f"{prefix}{current}-{now + 1}-1-1", "false", False),
            ("unreadable age", f"{prefix}{current}-unknown-1-1", "false", False),
            ("wrong area", f"Linux-vgs-nightly-nix-v1-{current}-{now}-1-1", "false", False),
        )
        with tempfile.TemporaryDirectory(prefix="nightly-cache-", dir=os.environ["TMPDIR"]) as scratch:
            root = Path(scratch)
            date = root / "date"
            date.write_text(f"#!/bin/sh\nprintf '%s\\n' {now}\n")
            date.chmod(0o755)
            for name, key, force, skip in cases:
                with self.subTest(name=name):
                    output = root / "output"
                    summary = root / "summary"
                    output.write_text("")
                    summary.write_text("")
                    result = subprocess.run(
                        [bash, "-euo", "pipefail", "-c", script],
                        env={
                            "PATH": str(root), "AREA": "package", "INPUT_HASH": current,
                            "CACHE_PREFIX": prefix, "PASS_KEY": key, "FORCE_BUILD": force,
                            "GITHUB_OUTPUT": str(output), "GITHUB_STEP_SUMMARY": str(summary),
                        },
                        capture_output=True, text=True, timeout=5,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(output.read_text(), f"skip={str(skip).lower()}\n")
                    self.assertIn(current, summary.read_text())


if __name__ == "__main__":
    unittest.main()
