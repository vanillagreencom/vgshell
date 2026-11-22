#!/usr/bin/env python3
"""Real compiler controls for check-voiceorb-shader.py: a shader for each
rule set of its table, judged under its own rules, passes clean and refuses
a stale pack, a texture and the loop its rules refuse; the pack contract's
rows, the judge's coverage of the shipped packs, its reading of a loop
bound, its reading of an included file and its reading of the orb styles
are proved once."""
import importlib.util
import json
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
SHADERS = checker.shaders()
MANIFEST = json.loads((checker.JARVIS / "manifest.json").read_text())


def once(text, old, new):
    """TEXT with its one OLD replaced by NEW."""
    assert text.count(old) == 1, old
    return text.replace(old, new)


# Per shader: an edit that changes its compiled shader, and a loop its
# rules refuse: any loop in an analytic shader, a uniform-bound loop
# elsewhere. Every rule set of the table has a shader here; Glass bead also
# holds the orb rule set over a source that includes the orb head, and the
# launcher's edge light stands for the two edge lights.
EDITS = {
    "voiceorb": (("max(ring, arcs)", "min(ring, arcs)"),
                 ("float ring =", "for (int i = 0; i < 5; ++i) { radius += pixel; }\n    float ring ="), "loop"),
    "radial-backdrop": (("vec3 rgb = ink * a;", "vec3 rgb = ink;"),
                        ("float m = min(", "for (int i = 0; i < 4; ++i) { p += 0.0; }\n    float m = min("), "loop"),
    "glass-lens": (("vec3(light);", "vec3(light) * 0.9;"),
                   ("float depth =", "for (int i = 0; i < 4; ++i) { p += 0.0; }\n    float depth ="), "loop"),
    "launcher-edge-light": (("glow * 0.22 * light;", "glow * 0.2 * light;"),
                            ("float light =", "for (int i = 0; i < 4; ++i) { p += 0.0; }\n    float light ="), "loop"),
    "plasma": (("clamp(a, 0.0, 1.0)) * qt_Opacity;", "clamp(a, 0.0, 0.9)) * qt_Opacity;"),
               ("for (int i = 0; i < 16; i++)", "for (int i = 0; i < int(uAmp * 8.0); i++)"), "loop-bound"),
    "jarvis-glass-bead": (("discA += (1.0 - discA) * shadow(uv, Re);", "discA += (1.0 - discA) * shadow(uv, Re) * 0.9;"),
                          ("for (int q = 0; q < 4; q++)", "for (int q = 0; q < int(uField.w * 8.0); q++)"), "loop-bound"),
}
# The file every orb style includes, and a style that includes it.
HEAD = "orb.glsl"
INCLUDER = "jarvis-blades"


def copy_heads(shipped, folder):
    """Copy the files SHIPPED's folder holds for inclusion into FOLDER, where
    qsb and the judge resolve a copy's includes."""
    for included in shipped.parent.glob("*.glsl"):
        shutil.copyfile(included, Path(folder) / included.name)


def checkout(folder, script_text, manifest):
    """FOLDER as a checkout holding SCRIPT_TEXT as the judge and MANIFEST as
    the Jarvis manifest, from which the judge's table reads its orb styles.
    Returns the judge's path."""
    script = Path(folder) / "scripts" / SCRIPT.name
    script.parent.mkdir(parents=True)
    script.write_text(script_text)
    jarvis = Path(folder) / "shell/plugins/vgs.jarvis"
    (jarvis / "shaders").mkdir(parents=True)
    (jarvis / "manifest.json").write_text(json.dumps(manifest))
    return script


def git(*args, folder):
    subprocess.run(["git", "-C", str(folder), *args], env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"},
                   capture_output=True, check=True)


def rows(name):
    """The table rows of shader NAME: name, source text or None for the
    shipped one, exit and the output's start."""
    original = SHADERS[name][0].read_text()
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

    def judge(self, name, row, text, script=SCRIPT, tool=TOOL, head=None):
        """Check a disposable copy of shader NAME's shipped source and pack,
        beside copies of the files its folder holds for inclusion, with the
        source replaced by TEXT, the included head by HEAD and the defect ROW
        planted."""
        shipped = SHADERS[name][0]
        with tempfile.TemporaryDirectory() as scratch:
            copy_heads(shipped, scratch)
            if head is not None:
                (Path(scratch) / HEAD).write_text(head)
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

    def test_every_rule_set_keeps_its_rules(self):
        self.assertLessEqual(set(EDITS), set(SHADERS))
        self.assertLessEqual({rules for _, rules in SHADERS.values()}, {SHADERS[name][1] for name in EDITS},
                             "every rule set of the table has its rows")
        for name in EDITS:
            for row, text, status, key in rows(name):
                with self.subTest(shader=name, row=row):
                    self.assert_row(self.judge(name, row, text), status, key)

    def test_the_pack_contract(self):
        original = SHADERS["voiceorb"][0].read_text()
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
        original = SHADERS["plasma"][0].read_text()
        bound = {
            "uniform-bound": once(original, *EDITS["plasma"][1]),
            "variable-bound": once(original, "const int STEPS = 34;", "int STEPS = int(uAmp * 34.0);"),
            "while": once(original, "float pclock = t + uSwirl * 0.6;", "float pclock = t + uSwirl * 0.6;\n    while (pclock < uAmp) pclock += 0.1;"),
        }
        for row, text in bound.items():
            with self.subTest(row=row):
                self.assert_row(self.judge("plasma", row, text), 1, "plasma-shader: refused rule=loop-bound")

    def test_the_judge_reads_an_included_file(self):
        # A rule broken in the head the style includes is broken by the
        # style; a head that is missing leaves the style unreadable.
        shipped = SHADERS[INCLUDER][0]
        head = (shipped.parent / HEAD).read_text()
        self.assertEqual(shipped.read_text().count(f'#include "{HEAD}"'), 1)
        for row, planted, status, key in (
            ("texture", head + TEXTURE, 1, f"{INCLUDER}-shader: refused rule=texture"),
            ("loop", head + "\nfloat spin(float x) { while (x > 1.0) x -= 1.0; return x; }\n", 1, f"{INCLUDER}-shader: refused rule=loop-bound"),
        ):
            with self.subTest(row=row):
                self.assert_row(self.judge(INCLUDER, row, None, head=planted), status, key)
        with tempfile.TemporaryDirectory() as scratch:
            source = Path(scratch) / shipped.name
            source.write_text(shipped.read_text())
            shutil.copyfile(shipped.with_suffix(".frag.qsb"), source.with_suffix(".frag.qsb"))
            self.assert_row(self.run_check(INCLUDER, source), 1, f"{INCLUDER}-shader: unreadable")

    def test_rule_controls(self):
        # Each plant changes one rule set in the table, the judge's pack
        # read or its bound reading; the row it names must turn red. The orb
        # rule set is planted in the one line every style's row takes.
        source = SCRIPT.read_text()
        plants = []
        orb = next(name for name in EDITS if name.startswith("jarvis-"))
        for name, rules in (*((name, checker.FIXED[name][1]) for name in EDITS if name in checker.FIXED),
                            (orb, checker.ORB_RULES)):
            prefix = "ORB_RULES = (" if name == orb else f'    "{name}": ('
            line = next(line for line in source.splitlines() if line.startswith(prefix))
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
            ("the included head unread", "expanded(source), flags=re.S)", 'source.read_text(encoding="utf-8"), flags=re.S)', INCLUDER, "head-texture"),
        ]
        variable = once(SHADERS["plasma"][0].read_text(), "const int STEPS = 34;", "int STEPS = int(uAmp * 34.0);")
        whiled = once(SHADERS["plasma"][0].read_text(), "float pclock = t + uSwirl * 0.6;", "float pclock = t + uSwirl * 0.6;\n    while (pclock < uAmp) pclock += 0.1;")
        with tempfile.TemporaryDirectory() as scratch:
            script = checkout(scratch, source, MANIFEST)
            for label, old, new, name, row in plants:
                with self.subTest(plant=label):
                    script.write_text(once(source, old, new))
                    head = None
                    if row == "variable-bound":
                        text, status, key = variable, 1, "plasma-shader: refused rule=loop-bound"
                    elif row == "while":
                        text, status, key = whiled, 1, "plasma-shader: refused rule=loop-bound"
                    elif row == "head-texture":
                        text, status, key = None, 1, f"{name}-shader: refused rule=texture"
                        head = (SHADERS[name][0].parent / HEAD).read_text() + TEXTURE
                    else:
                        _, text, status, key = next(r for r in rows(name) if r[0] == row)
                    result = self.judge(name, row, text, script, head=head)
                    self.assertFalse(result.returncode == status and result.stdout.startswith(key),
                                     label + ": " + result.stdout + result.stderr)

    def test_write_refreshes_a_stale_pack(self):
        name = "jarvis-glass-bead"
        shipped = SHADERS[name][0]
        with tempfile.TemporaryDirectory() as scratch:
            copy_heads(shipped, scratch)
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
                         [name + "-shader" for name in SHADERS])

    def test_every_shipped_pack_has_a_row(self):
        # With no --shader, as scripts/validate and the vgshell-git build
        # run it, the judge refuses before judging anything when git tracks
        # a pack under shell/ that no row names, when a row's pack is not
        # tracked, or when the folder is no checkout git can read. The
        # tracked packs are empty: only their paths are read.
        packs = [source.with_suffix(".frag.qsb").relative_to(checker.ROOT).as_posix() for source, _ in SHADERS.values()]
        extra = "shell/plugins/vgs.probe/shaders/probe.frag.qsb"
        cases = (
            ("pack with no row", packs + [extra], f"shader-judge: failed pack=unjudged path={extra}"),
            ("row with no pack", packs[1:], f"shader-judge: failed pack=untracked path={packs[0]}"),
            ("no checkout", None, "shader-judge: failed packs=unread "),
        )
        for name, tracked, key in cases:
            with self.subTest(case=name), tempfile.TemporaryDirectory() as scratch:
                script = checkout(scratch, SCRIPT.read_text(), MANIFEST)
                if tracked is not None:
                    git("init", "-q", folder=scratch)
                    for path in tracked:
                        (Path(scratch) / path).parent.mkdir(parents=True, exist_ok=True)
                        (Path(scratch) / path).touch()
                    git("add", "--", *tracked, folder=scratch)
                # The ceiling keeps git from reading a checkout that holds
                # the scratch folder.
                result = subprocess.run([sys.executable, str(script)],
                                        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "QSB": TOOL,
                                             "GIT_CEILING_DIRECTORIES": str(Path(scratch).parent)},
                                        capture_output=True, text=True, check=False)
                self.assert_row(result, 1, key)
                self.assertTrue(all(line.startswith("shader-judge: failed ") for line in result.stdout.splitlines()),
                                result.stdout)

    def test_an_orb_style_is_judged_from_the_manifest(self):
        # A style the manifest lists is a row of the table under the orb
        # rules: a planted option's shader with a texture is refused by
        # name. A hand-kept table would refuse the name itself, exit 2.
        shipped = SHADERS["jarvis-glass-bead"][0]
        manifest = json.loads(json.dumps(MANIFEST))
        manifest["schema"]["orbStyle"]["options"].append({"value": "probe", "label": "Probe"})
        with tempfile.TemporaryDirectory() as scratch:
            script = checkout(scratch, SCRIPT.read_text(), manifest)
            shaders = script.parents[1] / "shell/plugins/vgs.jarvis/shaders"
            copy_heads(shipped, shaders)
            (shaders / "probe.frag").write_text(shipped.read_text() + TEXTURE)
            result = subprocess.run([sys.executable, str(script), "--shader", "jarvis-probe"],
                                    env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "QSB": TOOL},
                                    capture_output=True, text=True, check=False)
            self.assert_row(result, 1, "jarvis-probe-shader: refused rule=texture")

    def test_the_orb_styles_refuse_by_key(self):
        # The one reader of the orb styles refuses an unreadable manifest
        # apart from one whose list it cannot use, and the judge fails with
        # that key before it judges anything.
        def planted(change):
            manifest = json.loads(json.dumps(MANIFEST))
            change(manifest)
            return json.dumps(manifest)
        cases = (
            ("missing", None, "orb-styles=unread "),
            ("not json", "{", "orb-styles=unread "),
            ("no setting", planted(lambda m: m["schema"].pop("orbStyle")), "orb-styles=invalid reason=no-setting "),
            ("no options", planted(lambda m: m["schema"]["orbStyle"].update(options=[])), "orb-styles=invalid reason=no-options"),
            ("default not an option", planted(lambda m: m["settings"].update(orbStyle="absent")),
             "orb-styles=invalid reason=default-not-an-option "),
        )
        with tempfile.TemporaryDirectory() as scratch:
            script = checkout(scratch, SCRIPT.read_text(), MANIFEST)
            manifest = script.parents[1] / "shell/plugins/vgs.jarvis/manifest.json"
            for name, text, key in cases:
                with self.subTest(case=name):
                    if text is None:
                        manifest.unlink(missing_ok=True)
                    else:
                        manifest.write_text(text)
                    with self.assertRaises(checker.OrbStylesRefused) as refused:
                        checker.orb_styles(manifest)
                    self.assertTrue(str(refused.exception).startswith(key), refused.exception)
                    result = subprocess.run([sys.executable, str(script)], env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "QSB": TOOL},
                                            capture_output=True, text=True, check=False)
                    self.assert_row(result, 1, "shader-judge: failed " + key)


if __name__ == "__main__":
    unittest.main()
