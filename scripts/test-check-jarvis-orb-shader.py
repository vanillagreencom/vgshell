#!/usr/bin/env python3
"""Real compiler controls for each rule check-jarvis-orb-shader.py hands the
shared pack judge: the orb pack is fresh, the source samples no texture,
and the source may loop only to a constant bound. The judge's own reading
of a bound is proved by scripts/test-check-plasma-shader.py."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "check-jarvis-orb-shader.py"
JUDGE = HERE / "check-voiceorb-shader.py"
spec = importlib.util.spec_from_file_location("jarvis_orb_check", SCRIPT)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
TOOL = checker.judge.qsb_tool()
if TOOL is None:
    print("test-jarvis-orb-shader: status=not-measured missing=qsb")
    raise SystemExit(77)


def once(text, old, new):
    """TEXT with its one OLD replaced by NEW."""
    assert text.count(old) == 1, old
    return text.replace(old, new)


class JarvisOrbShaderControls(unittest.TestCase):
    def run_check(self, source, script=SCRIPT, write=False):
        cmd = [sys.executable, str(script), "--source", str(source)]
        if write:
            cmd.append("--write")
        return subprocess.run(cmd, env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "QSB": TOOL},
                              capture_output=True, text=True, check=False)

    def judge(self, name, text, script=SCRIPT):
        """Check a disposable copy of the shipped source and pack, with the
        source replaced by TEXT and the defect NAME planted."""
        with tempfile.TemporaryDirectory() as scratch:
            source = Path(scratch) / "particleorb.frag"
            source.write_text(checker.SOURCE.read_text() if text is None else text)
            pack = source.with_suffix(".frag.qsb")
            shutil.copyfile(checker.SOURCE.with_suffix(".frag.qsb"), pack)
            if name == "pack-changed":
                pack.write_bytes(b"invalid pack")
            return self.run_check(source, script)

    def rows(self):
        original = checker.SOURCE.read_text()
        needle = "fragColor = vec4(min(col, vec3(a)), a) * qt_Opacity;"
        return (
            ("clean", None, 0, "jarvis-orb-shader: ok"),
            ("source-changed", once(original, needle, needle.replace("vec3(a)), a)", "vec3(a)), a * 0.9)")), 1, "jarvis-orb-shader: stale"),
            ("pack-changed", None, 1, "jarvis-orb-shader: stale"),
            ("texture", original + "\nlayout(binding=1) uniform sampler2D source;\n", 1, "jarvis-orb-shader: refused rule=texture"),
            ("uniform-bound", once(original, "for (int q = 0; q < 4; q++)", "for (int q = 0; q < int(uField.w * 8.0); q++)"),
             1, "jarvis-orb-shader: refused rule=loop-bound"),
        )

    def test_rules(self):
        # The shipped orb loops: the clean row reaches the loop rule.
        self.assertRegex(checker.SOURCE.read_text(), r"\bfor \(int ")
        for name, text, status, key in self.rows():
            with self.subTest(name=name):
                result = self.judge(name, text)
                self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                self.assertTrue(result.stdout.startswith(key), result.stdout)

    def test_rule_controls(self):
        # Each plant changes the rules or the pack read this script hands
        # the judge; the row it names must turn red.
        rows = {row[0]: row for row in self.rows()}
        plants = (
            ("loop refused", 'RULES = ("loop-bound", "texture")', 'RULES = ("loop", "texture")', "clean"),
            ("texture allowed", 'RULES = ("loop-bound", "texture")', 'RULES = ("loop-bound",)', "texture"),
            ("loop bound unchecked", 'RULES = ("loop-bound", "texture")', 'RULES = ("texture",)', "uniform-bound"),
            ("shipped pack unread", "judge.check(args.source, args.write, RULES", "judge.check(args.source, True, RULES", "pack-changed"),
        )
        with tempfile.TemporaryDirectory() as scratch:
            for name, old, new, row in plants:
                with self.subTest(name=name):
                    text = SCRIPT.read_text()
                    script = Path(scratch) / SCRIPT.name
                    script.write_text(once(text, old, new))
                    shutil.copyfile(JUDGE, Path(scratch) / JUDGE.name)
                    _, source, status, key = rows[row]
                    result = self.judge(row, source, script)
                    self.assertFalse(result.returncode == status and result.stdout.startswith(key),
                                     result.stdout + result.stderr)

    def test_write_refreshes_a_stale_pack(self):
        with tempfile.TemporaryDirectory() as scratch:
            source = Path(scratch) / "particleorb.frag"
            source.write_text(checker.SOURCE.read_text())
            source.with_suffix(".frag.qsb").write_bytes(b"invalid pack")
            self.assertEqual(self.run_check(source).returncode, 1)
            self.assertEqual(self.run_check(source, write=True).returncode, 0)
            self.assertEqual(self.run_check(source).returncode, 0)


if __name__ == "__main__":
    unittest.main()
