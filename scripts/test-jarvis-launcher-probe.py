#!/usr/bin/env python3
"""Run the Jarvis rows' launcher probe against a launcher that exits mid-read.

The probe is the Python text of `jarvis_descendants` in
scripts/smoke/rows/jarvis.sh. The kernel answers a /proc/<pid>/stat read of a
process that exits between the open and the read with ESRCH, which Python
raises as ProcessLookupError. A stand-in reader raises it for the stat path.
The probe must read that launcher as ended and name the cause. The same
stand-in against the probe with its ProcessLookupError catch removed must die
with the traceback, which is what the nested jarvis-keys control read.
"""
from pathlib import Path
import subprocess
import sys
import unittest

REPO = Path(__file__).resolve().parents[1]
ROW = REPO / "scripts/smoke/rows/jarvis.sh"
CATCH = "except (FileNotFoundError, ProcessLookupError):"
# A pid above the kernel's pid_max (2**22), so no /proc entry can exist.
LAUNCHER = 2**22 + 1
# The stand-in reader runs ahead of the probe in the same interpreter.
STANDIN = """
import errno, pathlib, sys
read_text = pathlib.Path.read_text
def standin(self, *args, **kwargs):
    if self.name == "stat":
        raise {error}(errno.ESRCH, "No such process")
    return read_text(self, *args, **kwargs)
pathlib.Path.read_text = standin
sys.argv = ["probe", "{launcher}", "5000"]
"""


def probe_source():
    text = ROW.read_text()
    start = text.index("jarvis_descendants() {")
    start = text.index("<<'PY'\n", start) + len("<<'PY'\n")
    return text[start:text.index("\nPY\n", start) + 1]


def run(source, error):
    program = STANDIN.format(error=error, launcher=LAUNCHER) + source
    return subprocess.run([sys.executable, "-I", "-c", program], capture_output=True, text=True, timeout=30)


class LauncherProbe(unittest.TestCase):
    def test_launcher_exiting_mid_read_is_ended(self):
        source = probe_source()
        for error in ("ProcessLookupError", "FileNotFoundError"):
            with self.subTest(error=error):
                done = run(source, error)
                self.assertEqual(done.returncode, 1, done.stderr)
                self.assertIn(f"jarvis-row: daemon-wait=launcher-ended daemon-count=0 launcher={LAUNCHER}", done.stderr)
                self.assertNotIn("Traceback", done.stderr)

    def test_without_the_catch_the_probe_dies_with_a_traceback(self):
        source = probe_source()
        self.assertIn(CATCH, source)
        done = run(source.replace(CATCH, "except FileNotFoundError:"), "ProcessLookupError")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("ProcessLookupError", done.stderr)
        self.assertNotIn("daemon-wait=launcher-ended", done.stderr)


if __name__ == "__main__":
    unittest.main()
