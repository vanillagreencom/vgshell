#!/usr/bin/env python3
"""Real compiler controls for check-voiceorb-shader.py: each shader of its
table, judged under its own rules, passes clean and refuses a stale pack, a
texture and the loop its rules refuse; the pack contract's rows and the
judge's reading of a loop bound are proved once."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zlib

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "check-voiceorb-shader.py"
spec = importlib.util.spec_from_file_location("shader_check", SCRIPT)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
TOOL = checker.qsb_tool()
if TOOL is None:
    print("test-voiceorb-shader: status=not-measured missing=qsb")
    raise SystemExit(77)
TEXTURE = "\nlayout(binding=1) uniform sampler2D source;\n"


def once(text, old, new):
    """TEXT with its one OLD replaced by NEW."""
    assert text.count(old) == 1, old
    return text.replace(old, new)


# Per shader: an edit that changes its compiled shader, and a loop its
# rules refuse: any loop in VoiceOrb, a uniform-bound loop elsewhere.
EDITS = {
    "voiceorb": (("max(ring, arcs)", "min(ring, arcs)"),
                 ("float ring =", "for (int i = 0; i < 5; ++i) { radius += pixel; }\n    float ring ="), "loop"),
    "plasma": (("clamp(a, 0.0, 1.0)) * qt_Opacity;", "clamp(a, 0.0, 0.9)) * qt_Opacity;"),
               ("for (int i = 0; i < 16; i++)", "for (int i = 0; i < int(uAmp * 8.0); i++)"), "loop-bound"),
    "jarvis-orb": (("vec3(a)), a) * qt_Opacity;", "vec3(a)), a * 0.9) * qt_Opacity;"),
                   ("for (int q = 0; q < 4; q++)", "for (int q = 0; q < int(uField.w * 8.0); q++)"), "loop-bound"),
}


def rows(name):
    """The table rows of shader NAME: name, source text or None for the
    shipped one, exit and the output's start."""
    original = checker.SHADERS[name][0].read_text()
    changed, loop, rule = EDITS[name]
    label = name + "-shader"
    return (
        ("clean", None, 0, f"{label}: ok"),
        ("source-changed", once(original, *changed), 1, f"{label}: stale"),
        ("pack-changed", None, 1, f"{label}: stale"),
        ("texture", original + TEXTURE, 1, f"{label}: refused rule=texture"),
        ("loop", once(original, *loop), 1, f"{label}: refused rule={rule}"),
    )


class ShaderControls(unittest.TestCase):
    def run_check(self, name, source, tool=TOOL, script=SCRIPT, write=False):
        cmd = [sys.executable, str(script), "--shader", name, "--source", str(source)]
        if write:
            cmd.append("--write")
        return subprocess.run(cmd, env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "QSB": tool},
                              capture_output=True, text=True, check=False)

    def judge(self, name, row, text, script=SCRIPT, tool=TOOL):
        """Check a disposable copy of shader NAME's shipped source and pack,
        with the source replaced by TEXT and the defect ROW planted."""
        shipped = checker.SHADERS[name][0]
        with tempfile.TemporaryDirectory() as scratch:
            source = Path(scratch) / shipped.name
            source.write_text(shipped.read_text() if text is None else text)
            pack = source.with_suffix(".frag.qsb")
            shutil.copyfile(shipped.with_suffix(".frag.qsb"), pack)
            if row == "pack-changed":
                pack.write_bytes(b"invalid pack")
            if row in ("pack-recompressed", "pack-other-shader", "pack-length-wrong"):
                held = zlib.decompress(pack.read_bytes()[4:])
                if row == "pack-other-shader":
                    held = held[:-1] + bytes([held[-1] ^ 1])
                prefix = len(held) + (1 if row == "pack-length-wrong" else 0)
                pack.write_bytes(prefix.to_bytes(4, "big") + zlib.compress(held, 1))
            if row == "missing-pack":
                pack.unlink()
            if row == "missing-source":
                source.unlink()
            return self.run_check(name, source, tool, script)

    def assert_row(self, result, status, key):
        self.assertEqual(result.returncode, status, result.stdout + result.stderr)
        self.assertTrue(result.stdout.startswith(key), result.stdout)

    def test_every_shader_keeps_its_rules(self):
        self.assertEqual(set(EDITS), set(checker.SHADERS), "every shader of the table has its rows")
        for name in checker.SHADERS:
            for row, text, status, key in rows(name):
                with self.subTest(shader=name, row=row):
                    self.assert_row(self.judge(name, row, text), status, key)

    def test_the_pack_contract(self):
        original = checker.SHADERS["voiceorb"][0].read_text()
        for row, text, status, key in (
            ("invalid", "not glsl;", 1, "voiceorb-shader: compile-failed"),
            ("pack-recompressed", None, 0, "voiceorb-shader: ok"),
            ("pack-other-shader", None, 1, "voiceorb-shader: stale"),
            ("pack-length-wrong", None, 1, "voiceorb-shader: stale"),
            ("missing-pack", None, 1, "voiceorb-shader: unreadable"),
            ("missing-source", None, 1, "voiceorb-shader: unreadable"),
            ("missing-tool", original, 77, "voiceorb-shader: status=not-measured missing=qsb"),
        ):
            with self.subTest(row=row):
                self.assert_row(self.judge("voiceorb", row, text, tool="/absent/qsb" if row == "missing-tool" else TOOL), status, key)

    def test_the_judge_reads_a_loop_bound(self):
        # Plasma holds a constant-bound raymarch, so these rows reach the
        # bound's reading, not the plain loop rule.
        original = checker.SHADERS["plasma"][0].read_text()
        bound = {
            "uniform-bound": once(original, *EDITS["plasma"][1]),
            "variable-bound": once(original, "const int STEPS = 34;", "int STEPS = int(uAmp * 34.0);"),
            "while": once(original, "float pclock = t + uSwirl * 0.6;", "float pclock = t + uSwirl * 0.6;\n    while (pclock < uAmp) pclock += 0.1;"),
        }
        for row, text in bound.items():
            with self.subTest(row=row):
                self.assert_row(self.judge("plasma", row, text), 1, "plasma-shader: refused rule=loop-bound")

    def test_rule_controls(self):
        # Each plant changes one shader's rules in the table, the judge's
        # pack read or its bound reading; the row it names must turn red.
        source = SCRIPT.read_text()
        plants = []
        for name, (_, rules) in checker.SHADERS.items():
            line = next(line for line in source.splitlines() if line.startswith(f'    "{name}": ('))
            listed = repr(rules).replace("'", '"')
            self.assertEqual(line.count(listed), 1, line)
            loop = rules[0]
            plants.append((f"{name} allows a texture", line, line.replace(listed, f'("{loop}",)'), name, "texture"))
            plants.append((f"{name} allows its loop", line, line.replace(listed, '("texture",)'), name, "loop"))
            if loop == "loop-bound":
                plants.append((f"{name} refuses a bounded loop", line, line.replace(listed, '("loop", "texture")'), name, "clean"))
        plants += [
            ("the shipped pack unread", "check(args.source or default, args.write,", "check(args.source or default, True,", "voiceorb", "pack-changed"),
            ("the pack never compared", "elif (held := shader(compiled.read_bytes())) is None or held != shader(fresh):", "elif False:", "voiceorb", "pack-changed"),
            ("any bound taken", "if bound is None or not (bound[1].isdigit() or bound[1] in constants):", "if False:", "plasma", "loop"),
            ("a variable bound taken", "bound[1] in constants", "bound[1].isidentifier()", "plasma", "variable-bound"),
            ("while taken", 'if re.search(r"\\b(?:while|do)\\b", code):', "if False:", "plasma", "while"),
        ]
        variable = once(checker.SHADERS["plasma"][0].read_text(), "const int STEPS = 34;", "int STEPS = int(uAmp * 34.0);")
        whiled = once(checker.SHADERS["plasma"][0].read_text(), "float pclock = t + uSwirl * 0.6;", "float pclock = t + uSwirl * 0.6;\n    while (pclock < uAmp) pclock += 0.1;")
        with tempfile.TemporaryDirectory() as scratch:
            script = Path(scratch) / SCRIPT.name
            for label, old, new, name, row in plants:
                with self.subTest(plant=label):
                    script.write_text(once(source, old, new))
                    if row == "variable-bound":
                        text, status, key = variable, 1, "plasma-shader: refused rule=loop-bound"
                    elif row == "while":
                        text, status, key = whiled, 1, "plasma-shader: refused rule=loop-bound"
                    else:
                        _, text, status, key = next(r for r in rows(name) if r[0] == row)
                    result = self.judge(name, row, text, script)
                    self.assertFalse(result.returncode == status and result.stdout.startswith(key),
                                     label + ": " + result.stdout + result.stderr)

    def test_write_refreshes_a_stale_pack(self):
        name = "jarvis-orb"
        shipped = checker.SHADERS[name][0]
        with tempfile.TemporaryDirectory() as scratch:
            source = Path(scratch) / shipped.name
            source.write_text(once(shipped.read_text(), *EDITS[name][0]))
            shutil.copyfile(shipped.with_suffix(".frag.qsb"), source.with_suffix(".frag.qsb"))
            self.assertEqual(self.run_check(name, source).returncode, 1)
            self.assertEqual(self.run_check(name, source, write=True).returncode, 0)
            self.assertEqual(self.run_check(name, source).returncode, 0)

    def test_the_table_is_judged_whole(self):
        # With no --shader, as scripts/validate runs it, the judge checks
        # every entry of its table.
        result = subprocess.run([sys.executable, str(SCRIPT)], env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "QSB": TOOL},
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([line.split(":")[0] for line in result.stdout.splitlines()],
                         [name + "-shader" for name in checker.SHADERS])


if __name__ == "__main__":
    unittest.main()
