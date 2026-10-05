#!/usr/bin/env python3
"""Real compiler controls for each rule check-plasma-shader.py hands the
shared pack judge: the plasma pack is fresh, the source samples no texture,
and the source may loop only to a constant bound, where VoiceOrb's rules
refuse every loop."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "check-plasma-shader.py"
JUDGE = HERE / "check-voiceorb-shader.py"
spec = importlib.util.spec_from_file_location("plasma_check", SCRIPT)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
TOOL = checker.judge.qsb_tool()
if TOOL is None:
    print("test-plasma-shader: status=not-measured missing=qsb")
    raise SystemExit(77)


def once(text, old, new):
    """TEXT with its one OLD replaced by NEW."""
    assert text.count(old) == 1, old
    return text.replace(old, new)


class PlasmaShaderControls(unittest.TestCase):
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
            source = Path(scratch) / "plasma.frag"
            source.write_text(checker.SOURCE.read_text() if text is None else text)
            pack = source.with_suffix(".frag.qsb")
            shutil.copyfile(checker.SOURCE.with_suffix(".frag.qsb"), pack)
            if name == "pack-changed":
                pack.write_bytes(b"invalid pack")
            return self.run_check(source, script)

    def rows(self):
        original = checker.SOURCE.read_text()
        needle = "fragColor = vec4(outc, clamp(a, 0.0, 1.0)) * qt_Opacity;"
        self.assertEqual(original.count(needle), 1)
        return (
            ("clean", None, 0, "plasma-shader: ok"),
            ("source-changed", original.replace(needle, needle.replace("clamp(a, 0.0, 1.0)", "clamp(a, 0.0, 0.9)")), 1, "plasma-shader: stale"),
            ("pack-changed", None, 1, "plasma-shader: stale"),
            ("texture", original + "\nlayout(binding=1) uniform sampler2D source;\n", 1, "plasma-shader: refused rule=texture"),
            ("uniform-bound", once(original, "for (int i = 0; i < 16; i++)", "for (int i = 0; i < int(uAmp * 8.0); i++)"),
             1, "plasma-shader: refused rule=loop-bound"),
            ("variable-bound", once(original, "const int STEPS = 34;", "int STEPS = int(uAmp * 34.0);"),
             1, "plasma-shader: refused rule=loop-bound"),
            ("while", once(original, "float pclock = t + uSwirl * 0.6;",
                           "float pclock = t + uSwirl * 0.6;\n    while (pclock < uAmp) pclock += 0.1;"),
             1, "plasma-shader: refused rule=loop-bound"),
        )

    def test_rules(self):
        # The shipped raymarch loops: the clean row reaches the loop rule.
        self.assertRegex(checker.SOURCE.read_text(), r"\bfor \(int ")
        for name, text, status, key in self.rows():
            with self.subTest(name=name):
                result = self.judge(name, text)
                self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                self.assertTrue(result.stdout.startswith(key), result.stdout)

    def test_rule_controls(self):
        # Each plant changes one rule, in the rules handed to the judge or in
        # the judge's loop-bound reading; the row it names must turn red.
        rows = {row[0]: row for row in self.rows()}
        plants = (
            ("loop refused", SCRIPT, 'RULES = ("loop-bound", "texture")', 'RULES = ("loop", "texture")', "clean"),
            ("texture allowed", SCRIPT, 'RULES = ("loop-bound", "texture")', 'RULES = ("loop-bound",)', "texture"),
            ("loop bound unchecked", SCRIPT, 'RULES = ("loop-bound", "texture")', 'RULES = ("texture",)', "uniform-bound"),
            ("shipped pack unread", SCRIPT, "judge.check(args.source, args.write, RULES", "judge.check(args.source, True, RULES", "pack-changed"),
            ("any bound taken", JUDGE, "if bound is None or not (bound[1].isdigit() or bound[1] in constants):", "if False:", "uniform-bound"),
            ("a variable bound taken", JUDGE, "bound[1] in constants", "bound[1].isidentifier()", "variable-bound"),
            ("while taken", JUDGE, 'if re.search(r"\\b(?:while|do)\\b", code):', "if False:", "while"),
        )
        with tempfile.TemporaryDirectory() as scratch:
            for name, target, old, new, row in plants:
                with self.subTest(name=name):
                    text = target.read_text()
                    self.assertEqual(text.count(old), 1)
                    changed = text.replace(old, new)
                    self.assertNotEqual(changed, text)
                    script = Path(scratch) / "check-plasma-shader.py"
                    shutil.copyfile(SCRIPT, script)
                    shutil.copyfile(JUDGE, Path(scratch) / "check-voiceorb-shader.py")
                    (Path(scratch) / target.name).write_text(changed)
                    _, source, status, key = rows[row]
                    result = self.judge(row, source, script)
                    self.assertFalse(result.returncode == status and result.stdout.startswith(key),
                                     result.stdout + result.stderr)

    def test_write_refreshes_a_stale_pack(self):
        with tempfile.TemporaryDirectory() as scratch:
            source = Path(scratch) / "plasma.frag"
            source.write_text(checker.SOURCE.read_text())
            source.with_suffix(".frag.qsb").write_bytes(b"invalid pack")
            self.assertEqual(self.run_check(source).returncode, 1)
            self.assertEqual(self.run_check(source, write=True).returncode, 0)
            self.assertEqual(self.run_check(source).returncode, 0)


if __name__ == "__main__":
    unittest.main()
