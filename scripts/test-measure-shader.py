#!/usr/bin/env python3
"""Exercise the real log reader and ceiling judge with Qt-format records.

Log fields come from Qt 6.11.2 QSGRenderThread::syncAndRender and
QRhiVulkan::create. The costly shader is proved separately on the real GPU.
Controls remove each sample, percentile, pass and ceiling rule from a
disposable reader, without removing the matched error text. The runner's
held-scene loop and its argument refusals run with the sandbox stubbed,
and their controls plant one defect per rule in a copy.
"""
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
READER = ROOT / "shader/readings.py"
RUNNER = ROOT / "measure-shader.sh"
BASH = shutil.which("bash")
JARVIS = ROOT.parent / "shell/plugins/vgs.jarvis"
# The manifest a runner copy reads, unless a test plants another.
JARVIS_MANIFEST = json.loads((JARVIS / "manifest.json").read_text())
spec = importlib.util.spec_from_file_location("readings", READER)
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)
spec = importlib.util.spec_from_file_location("shader_judge", ROOT / "check-voiceorb-shader.py")
judge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(judge)
# The runner draws one orb scene per orb style the shader judge reads, and
# one in the reduced look of the default style.
ORB_DEFAULT, ORB_STYLES = judge.orb_styles()
SCENES = ("voiceorb", "plasma", *(f"jarvis-orb-{style}" for style in ORB_STYLES), "jarvis-orb-reduced",
          "radial-backdrop", "glass-lens")


def orb_words(shader):
    """The orb style and reduced flag the runner hands SHADER's scene."""
    if shader == "jarvis-orb-reduced":
        return ORB_DEFAULT, 1
    return shader.removeprefix("jarvis-orb-") if shader.startswith("jarvis-orb-") else "", 0

DEVICE = "Physical device 0: 'Test GPU' 1.2.3 (api 1.3.0 vendor 0x1 device 0x2 type 2)\nDEBUG qt.rhi.general:     using this physical device"
HEADER = DEVICE + "\nCreating QRhi with backend Vulkan for window 0x1234 (wflags 0x1)\nSwap interval is 0, attempting to disable vsync when presenting.\n"
CPU = "DEBUG qt.scenegraph.time.renderloop: [window 0x1234][render thread 0xabcd] syncAndRender: frame rendered in 2ms, sync=1, render=1, swap=0\n"
GPU = "DEBUG qt.scenegraph.time.renderloop: [window 0x1234][render thread 0xabcd] syncAndRender: last retrieved GPU frame time was %.4f ms\n"
STATE = {"complete": True, "window": "ProxiedWindow(0x1234)", "scale": 1, "presentation": [16] * 720}
BASELINE = {"backend": "Vulkan", "device": "Test GPU", "gpu_null_spread_ms": 0, "ceilings": {
    "cpu_sync_ms": 2, "cpu_render_ms": 2, "gpu_cost_ms": 0.2, "presentation_ms": 32}}


def log(gpu=0.2):
    return HEADER + (CPU + GPU % gpu) * 720


def stream_log(sync, render, gpu):
    """A log whose CPU and GPU records carry one value per frame."""
    return HEADER + "".join(
        CPU.replace("sync=1, render=1", f"sync={s}, render={r}") + GPU % g
        for s, r, g in zip(sync, render, gpu, strict=True))


STEADY_CLOCK = "clock_sm=2580/2601.5/2632 clock_mem=13801/13801 pstates=P1 clock_samples=4"


def fixture(root):
    for scale in (1, 2):
        for mode, gpu in (("off", 0.1), ("null", 0.1), ("on", 0.2), ("costly", 1.0)):
            stem = root / f"scale-{scale}-{mode}"
            stem.with_suffix(".log").write_text(log(gpu))
            stem.with_suffix(".json").write_text(json.dumps(dict(STATE, scale=scale)))
            stem.with_suffix(".cpu").write_text("0.5\n")
            stem.with_suffix(".gpu").write_text("2\n")
            stem.with_suffix(".gpu-peak").write_text("4\n")
            stem.with_suffix(".gpu-foreign").write_text("1\n")
            stem.with_suffix(".gpu-clock").write_text(STEADY_CLOCK + "\n")
            stem.with_suffix(".load").write_text(
                "quiet cpu=0.5 gpu_foreign=1 gpu=2 gpu_peak=4 clock_sm=2580/2601.5/2632 clock=steady retaken=false\n")


class ShaderReadings(unittest.TestCase):
    def test_resolution_floor_and_boundary(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            fixture(root)
            for scale in (1, 2):
                (root / f"scale-{scale}-on.log").write_text(stream_log([0] * 720, [0] * 720, [0.2] * 720))
                (root / f"scale-{scale}-on.json").write_text(json.dumps(dict(STATE, scale=scale, presentation=[0] * 720)))
            self.assertEqual(reader.calibrate([root])["ceilings"], {
                "cpu_sync_ms": 1, "cpu_render_ms": 1, "gpu_cost_ms": 0.2, "presentation_ms": 1})

    def test_null_spread_floor(self):
        # A second identical scene measures instrument spread, including
        # differences between passes/scales. Below that spread is not a
        # resolved slowdown; an actual costly shader must still fail.
        with tempfile.TemporaryDirectory() as scratch:
            roots = [Path(scratch) / f"run-{index}" for index in (1, 2, 3)]
            for root in roots:
                root.mkdir()
                fixture(root)
            (roots[2] / "scale-2-null.log").write_text(log(0.5))
            baseline = reader.calibrate(roots)
            self.assertAlmostEqual(baseline["gpu_null_spread_ms"], 0.4)
            self.assertAlmostEqual(baseline["calibration_runs"][2]["gpu_null_readings_ms"]["2"], 0.4)
            self.assertAlmostEqual(baseline["ceilings"]["gpu_cost_ms"], 0.4)
            for cost, rejected in ((0.3, False), (0.4, False), (0.4001, True)):
                with self.subTest(cost=cost):
                    (roots[0] / "scale-1-on.log").write_text(log(0.1 + cost))
                    if rejected:
                        with self.assertRaisesRegex(ValueError, "ceiling=exceeded"):
                            reader.check(roots[0], baseline, 2.8)
                    else:
                        reader.check(roots[0], baseline, 2.8)
            # Noise too wide to distinguish the planted shader is no
            # calibration. It cannot write a higher accepted ceiling.
            (roots[2] / "scale-2-null.log").write_text(log(1.0))
            with self.assertRaisesRegex(ValueError, "costly-control=accepted"):
                reader.calibrate(roots)

    def test_gpu_tick_boundary(self):
        ceilings = dict(BASELINE["ceilings"], gpu_cost_ms=0.0026)
        for value, want in ((0.0026000000000000007, []), (0.0027, ["gpu_cost_ms"])):
            with self.subTest(gpu_cost_ms=value):
                self.assertEqual(reader.over_ceiling(dict(ceilings, gpu_cost_ms=value), ceilings), want)

    def test_pressure_verdicts(self):
        # The on scene produces the CPU readings. Off/control pressure
        # cannot excuse a quiet on-scene CPU regression.
        cases = (
            ("loaded CPU", "scale-1-on", "2.9", 3, 0.2, False, 77),
            ("quiet same CPU", "scale-1-on", "2.8", 3, 0.2, False, 1),
            ("off loaded only", "scale-1-off", "9.0", 3, 0.2, False, 1),
            ("CPU pressure unread", "scale-1-on", "unmeasured", 3, 0.2, False, 77),
            ("quiet GPU", "scale-1-on", "0.5", 1, 0.31, False, 1),
            ("loaded GPU", "scale-1-on", "2.9", 3, 0.31, False, 1),
            ("loaded weak control", "scale-1-on", "2.9", 3, 0.2, True, 1),
        )
        for name, stem, pressure, cpu, gpu, weak, status in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as scratch:
                root = Path(scratch)
                fixture(root)
                (root / f"{stem}.cpu").write_text(pressure + "\n")
                (root / "scale-1-on.log").write_text(stream_log([cpu] * 720, [cpu] * 720, [gpu] * 720))
                if weak:
                    (root / "scale-1-costly.log").write_text(log(0.2))
                path = root / "baseline.json"
                path.write_text(json.dumps({"shaders": {"voiceorb": BASELINE}}))
                result = subprocess.run(
                    [sys.executable, str(READER), "--cpu-pressure-limit", "2.8", str(root), "--shader", "voiceorb", "--check", str(path)],
                    env={"PATH": "/usr/bin:/bin", "HOME": scratch, "LC_ALL": "C"},
                    text=True, capture_output=True, check=False)
                self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                # Main batch investigations consume these keyed readings.
                fields = dict(re.findall(r"(\w+)=([^\s]+)", result.stdout))
                if status == 77:
                    self.assertEqual(fields["status"], "not-measured")
                    self.assertEqual(fields["cpu_some_pct"], pressure)
                    self.assertEqual(float(fields["cpu_sync_ms"]), 3)
                    self.assertEqual(float(fields["cpu_render_ms"]), 3)
                if gpu == 0.31:
                    self.assertIn("gpu_cost_ms", fields)
                    self.assertAlmostEqual(float(fields["gpu_cost_ms"]), 0.21)
                    self.assertEqual(float(fields["ceiling_gpu_cost_ms"]), 0.2)

    def test_distinct_readings_and_calibration(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            fixture(root)
            result = reader.calibrate([root])
            self.assertEqual(result["samples"], 600)
            self.assertEqual(result["warmup"], 120)
            self.assertEqual(result["readings"]["1"], {
                "cpu_sync_ms": 1, "cpu_render_ms": 1, "gpu_cost_ms": 0.1, "presentation_ms": 16})
            self.assertEqual(result["ceilings"], {
                "cpu_sync_ms": 2, "cpu_render_ms": 2, "gpu_cost_ms": 0.2, "presentation_ms": 32})
            self.assertEqual(set(result["readings"]), {"1", "2"})
            self.assertAlmostEqual(result["calibration_runs"][0]["costly_control"]["2"]["gpu_cost_ms"], 0.9)
            self.assertEqual(result["calibration_runs"][0]["cpu_some_pct"], 0.5)

    def test_calibration_pressure(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch) / "run-2/voiceorb"
            root.mkdir(parents=True)
            fixture(root)
            marker = root / "scale-2-costly.load"
            marker.write_text("quiet cpu=1.7 gpu_foreign=3 gpu=unmeasured gpu_peak=unmeasured clock_sm=1400/1900/2800 "
                              "clock=steady retaken=true\n")
            run = reader.calibrate([root])["calibration_runs"][0]
            self.assertEqual(run["cpu_some_pct"], 1.7)
            expected = {scale: {mode: {"cpu_some_pct": 0.5, "gpu_foreign_pct": 1, "gpu_pct": 2,
                                       "gpu_peak_pct": 4, "clock_sm": "2580/2601.5/2632", "clock": "steady", "retaken": False}
                                for mode in ("off", "null", "on", "costly")} for scale in ("1", "2")}
            expected["2"]["costly"] = {"cpu_some_pct": 1.7, "gpu_foreign_pct": 3, "gpu_pct": "unmeasured",
                                       "gpu_peak_pct": "unmeasured", "clock_sm": "1400/1900/2800", "clock": "steady",
                                       "retaken": True}
            self.assertEqual(run["scene_loads"], expected)
            marker.unlink()
            with self.assertRaisesRegex(reader.Unmeasured, r"scene-load=missing-or-unreadable .*run-2/voiceorb "
                                        r"scale=2 scene=costly cpu_some_pct=0.5 gpu_foreign_pct=1 gpu_pct=2 gpu_peak_pct=4"):
                reader.calibrate([root])

    def test_sample_and_attribution_rules(self):
        cases = (
            ("zero CPU", HEADER + GPU % 0.2, STATE, "samples=cpu-sync"),
            ("zero GPU", HEADER + CPU * 720, STATE, "samples=gpu"),
            ("zero presentation", log(), dict(STATE, presentation=[]), "samples=presentation"),
            ("incomplete GPU", HEADER + (CPU + GPU % 0.2) * 719, STATE, "samples=cpu-sync"),
            ("other window", log().replace("[window 0x1234]", "[window 0x5678]"), STATE, "samples=cpu-sync"),
            ("wrong scale", log(), dict(STATE, scale=2), "scale=2"),
            ("no vsync proof", log().replace("Swap interval is 0", "Swap interval is 1"), STATE, "swap-interval=unverified"),
            ("incomplete scene", log(), dict(STATE, complete=False), "scene=incomplete"),
            ("no device", log().replace("using this physical device", "not selected"), STATE, "backend=device-unreadable"),
        )
        for name, text, state, error in cases:
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, error):
                reader.scene(text, state, 1)

    def test_software_is_77(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            fixture(root)
            (root / "scale-1-off.log").write_text(log().replace("type 2)", "type 4)"))
            result = subprocess.run(
                [sys.executable, str(READER), "--cpu-pressure-limit", "2.8", str(root), "--shader", "voiceorb", "--calibrate", str(root / "baseline.json")],
                env={"PATH": "/usr/bin:/bin", "HOME": scratch, "LC_ALL": "C"},
                text=True, capture_output=True, check=False)
            self.assertEqual(result.returncode, 77, result.stdout + result.stderr)
            self.assertIn("shader-cost: status=not-measured shader=voiceorb backend=software", result.stdout)
            self.assertFalse((root / "baseline.json").exists())

    def test_costly_control_and_each_ceiling(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            fixture(root)
            result = reader.calibrate([root])
            row = result["readings"]["1"]
            for name in reader.READINGS:
                with self.subTest(name=name):
                    self.assertEqual(reader.over_ceiling(dict(row, **{name: result["ceilings"][name] + 1}), result["ceilings"]), [name])
            self.assertEqual(reader.over_ceiling(result["ceilings"], result["ceilings"]), [])
            self.assertEqual(reader.over_ceiling(dict(row, cpu_sync_ms=1), dict(result["ceilings"], cpu_sync_ms=0)), ["cpu_sync_ms"])
            (root / "scale-2-costly.log").write_text(log(0.2))
            with self.assertRaisesRegex(ValueError, "costly-control=accepted scale=2"):
                reader.calibrate([root])

    def test_check_mode_report_and_cli(self):
        cases = (
            ("within ceiling", 0.2, None),
            ("normal GPU regression", 0.05, "ceiling=exceeded scale=1 readings=gpu_cost_ms"),
            ("accepted costly shader", 1.0, "costly-control=accepted scale=1"),
        )
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            fixture(root)
            for name, ceiling, error in cases:
                with self.subTest(name=name):
                    baseline = dict(BASELINE, ceilings=dict(BASELINE["ceilings"], gpu_cost_ms=ceiling))
                    if error is None:
                        self.assertEqual(reader.check(root, baseline, 2.8)["ceilings"], baseline["ceilings"])
                    else:
                        with self.assertRaisesRegex(ValueError, error):
                            reader.check(root, baseline, 2.8)
                    path = root / "baseline.json"
                    path.write_text(json.dumps({"shaders": {"voiceorb": baseline}}))
                    result = subprocess.run(
                        [sys.executable, str(READER), "--cpu-pressure-limit", "2.8", str(root), "--shader", "voiceorb", "--check", str(path)],
                        env={"PATH": "/usr/bin:/bin", "HOME": scratch, "LC_ALL": "C"},
                        text=True, capture_output=True, check=False)
                    self.assertEqual(result.returncode, 1 if error else 0, result.stdout + result.stderr)
                    if error:
                        self.assertIn("shader-cost: failed shader=voiceorb " + error, result.stdout)
                    else:
                        report = json.loads(result.stdout)
                        self.assertEqual(report["ceilings"], baseline["ceilings"])
                        self.assertEqual(report["scene_loads"]["2"]["costly"]["clock_sm"], "2580/2601.5/2632")

    def test_check_mode_calibration_identity(self):
        # Every scene is a real producer of device identity, including the
        # off and costly scenes. A mismatched baseline backend also skips.
        cases = [(scale, mode, BASELINE) for scale in (1, 2) for mode in ("off", "on", "costly")]
        cases.append((None, None, dict(BASELINE, backend="OpenGL")))
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            for scale, mode, baseline in cases:
                with self.subTest(scale=scale, mode=mode, backend=baseline["backend"]):
                    fixture(root)
                    if scale is not None:
                        path = root / f"scale-{scale}-{mode}.log"
                        path.write_text(path.read_text().replace("'Test GPU'", "'Other GPU'"))
                    with self.assertRaisesRegex(reader.Unmeasured, "calibration=identity-mismatch"):
                        reader.check(root, baseline, 2.8)
                    path = root / "baseline.json"
                    path.write_text(json.dumps({"shaders": {"voiceorb": baseline}}))
                    result = subprocess.run(
                        [sys.executable, str(READER), "--cpu-pressure-limit", "2.8", str(root), "--shader", "voiceorb", "--check", str(path)],
                        env={"PATH": "/usr/bin:/bin", "HOME": scratch, "LC_ALL": "C"},
                        text=True, capture_output=True, check=False)
                    self.assertEqual(result.returncode, 77, result.stdout + result.stderr)
                    self.assertIn("shader-cost: status=not-measured shader=voiceorb calibration=identity-mismatch", result.stdout)

    def test_percentile_ignores_a_spike(self):
        # Nearest rank: the smallest sample with at least 90 percent of
        # the samples at or below it.
        self.assertEqual(reader.percentile(list(range(600, 0, -1))), 540)
        self.assertEqual(reader.percentile(list(range(1, 11))), 9)
        # Rows: the stream one kept sample spikes in, the spike, and the
        # reading without it. A stream read as its highest sample reads
        # the spike.
        rows = (
            ("cpu_sync_ms", 9, 1),
            ("cpu_render_ms", 9, 1),
            ("gpu_cost_ms", 5.0, 0.1),
            ("presentation_ms", 500, 16),
        )
        for name, spike, want in rows:
            with self.subTest(stream=name), tempfile.TemporaryDirectory() as scratch:
                root = Path(scratch)
                fixture(root)
                streams = {"cpu_sync_ms": [1] * 720, "cpu_render_ms": [1] * 720,
                           "gpu_cost_ms": [0.2] * 720, "presentation_ms": [16] * 720}
                streams[name][reader.WARMUP + 300] = spike
                (root / "scale-1-on.log").write_text(stream_log(
                    streams["cpu_sync_ms"], streams["cpu_render_ms"], streams["gpu_cost_ms"]))
                (root / "scale-1-on.json").write_text(json.dumps(dict(STATE, presentation=streams["presentation_ms"])))
                self.assertAlmostEqual(reader.calibrate([root])["readings"]["1"][name], want)
                self.assertEqual(reader.check(root, BASELINE, 2.8)["ceilings"], BASELINE["ceilings"])

    def test_gpu_cost_not_resolved(self):
        # Fewer than a tenth of the on scene's frames cost more than the
        # off scene's: the highest delta is positive, the 90th percentile
        # is zero.
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            fixture(root)
            gpu = [0.1] * 720
            for index in range(reader.WARMUP, reader.WARMUP + 50):
                gpu[index] = 0.5
            (root / "scale-1-on.log").write_text(stream_log([1] * 720, [1] * 720, gpu))
            with self.assertRaisesRegex(ValueError, "gpu-cost=not-resolved reading_ms=0"):
                reader.calibrate([root])

    def test_calibration_over_passes(self):
        with tempfile.TemporaryDirectory() as scratch:
            first, second, weak = (Path(scratch) / name / "plasma" for name in ("run-1", "run-2", "run-3"))
            for root in (first, second, weak):
                root.mkdir(parents=True)
                fixture(root)
            (second / "scale-2-on.log").write_text(log(0.25))
            (weak / "scale-1-costly.log").write_text(log(0.35))
            result = reader.calibrate([first, second])
            self.assertAlmostEqual(result["ceilings"]["gpu_cost_ms"], 0.3)
            self.assertAlmostEqual(result["readings"]["2"]["gpu_cost_ms"], 0.15)
            self.assertAlmostEqual(result["readings"]["1"]["gpu_cost_ms"], 0.1)
            self.assertEqual([run["run"] for run in result["calibration_runs"]],
                             [f"{Path(scratch).name}/run-1/plasma", f"{Path(scratch).name}/run-2/plasma"])
            self.assertAlmostEqual(result["calibration_runs"][0]["readings"]["2"]["gpu_cost_ms"], 0.1)
            with self.assertRaisesRegex(ValueError, f"costly-control=accepted scale=1 .* run={Path(scratch).name}/run-3/plasma$"):
                reader.calibrate([first, second, weak])
            # A later pass is matched to the first pass's device.
            other = Path(scratch) / "run-4" / "plasma"
            other.mkdir(parents=True)
            fixture(other)
            path = other / "scale-2-off.log"
            path.write_text(path.read_text().replace("'Test GPU'", "'Other GPU'"))
            with self.assertRaisesRegex(
                    reader.Unmeasured,
                    r"calibration=identity-mismatch scale=2 scene=off want=\[Vulkan:Test GPU\] got=\[Vulkan:Other GPU\]"):
                reader.calibrate([first, other])

    def test_check_takes_one_directory(self):
        with tempfile.TemporaryDirectory() as scratch:
            first, second = Path(scratch) / "a", Path(scratch) / "b"
            for root in (first, second):
                root.mkdir()
                fixture(root)
            path = Path(scratch) / "baseline.json"
            path.write_text(json.dumps({"shaders": {"voiceorb": BASELINE}}))
            for roots, status in (([first], 0), ([first, second], 2)):
                with self.subTest(directories=len(roots)):
                    result = subprocess.run(
                        [sys.executable, str(READER), "--cpu-pressure-limit", "2.8", *map(str, roots), "--shader", "voiceorb", "--check", str(path)],
                        env={"PATH": "/usr/bin:/bin", "HOME": scratch, "LC_ALL": "C"},
                        text=True, capture_output=True, check=False)
                    self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                    if status:
                        self.assertEqual(result.stdout, "shader-cost: refused directories=2 check=1\n")

    def test_shader_records(self):
        # Each shader is judged against its own record, and calibrating one
        # shader keeps every other shader's record as it was.
        def run(root, path, shader, choice):
            return subprocess.run(
                [sys.executable, str(READER), "--cpu-pressure-limit", "2.8", str(root), "--shader", shader, choice, str(path)],
                env={"PATH": "/usr/bin:/bin", "HOME": str(root), "LC_ALL": "C"},
                text=True, capture_output=True, check=False)
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            fixture(root)
            tight = dict(BASELINE, ceilings=dict(BASELINE["ceilings"], gpu_cost_ms=0.05))
            path = root / "ceilings.json"
            path.write_text(json.dumps({"shaders": {"voiceorb": BASELINE, "plasma": tight}}))
            rows = (
                ("voiceorb", 0, None),
                ("plasma", 1, "shader-cost: failed shader=plasma ceiling=exceeded scale=1 readings=gpu_cost_ms"),
                ("absent", 1, "shader-cost: failed shader=absent baseline=absent"),
            )
            for shader, status, line in rows:
                with self.subTest(check=shader):
                    result = run(root, path, shader, "--check")
                    self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                    if line is not None:
                        self.assertTrue(result.stdout.startswith(line + " ") or result.stdout == line + "\n", result.stdout)
            kept = path.read_text()
            result = run(root, path, "plasma", "--calibrate")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            records = json.loads(path.read_text())["shaders"]
            self.assertEqual(records["voiceorb"], json.loads(kept)["shaders"]["voiceorb"])
            self.assertEqual(records["plasma"]["ceilings"], reader.calibrate([root])["ceilings"])
            path.unlink()
            result = run(root, path, "plasma", "--calibrate")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(list(json.loads(path.read_text())["shaders"]), ["plasma"])

    def test_sample_and_ceiling_mutants_turn_tests_red(self):
        plants = (
            ("resolution floor", "max(RESOLUTION_MS[name], 2 *", "max(0 * RESOLUTION_MS[name], 2 *", "test_resolution_floor_and_boundary"),
            ("null spread ignored", 'max(ceilings["gpu_cost_ms"], null_spread)',
             'max(ceilings["gpu_cost_ms"], 0 * null_spread)', "test_null_spread_floor"),
            ("GPU tick equality", "round(reading[name] / RESOLUTION_MS[name]) > round(ceilings[name] / RESOLUTION_MS[name])",
             "reading[name] > ceilings[name]", "test_gpu_tick_boundary"),
            ("CPU pressure ignored", 'if value == "unmeasured" or value > pressure_limit}',
             'if False and (value == "unmeasured" or value > pressure_limit)}', "test_pressure_verdicts"),
            ("failed readings omitted", 'f"{values} cpu_some_pct=',
             'f"{values[:0]} cpu_some_pct=', "test_pressure_verdicts"),
            ("sample guard", "if len(values) < WARMUP + SAMPLES:", "if False and len(values) < WARMUP + SAMPLES:", "test_sample_and_attribution_rules"),
            ("ceiling guard", "if round(reading[name] / RESOLUTION_MS[name]) > round(ceilings[name] / RESOLUTION_MS[name])", "if round(reading[name] / RESOLUTION_MS[name]) > float('inf') + round(ceilings[name] / RESOLUTION_MS[name])", "test_costly_control_and_each_ceiling"),
            ("baseline rejection", 'raise ValueError(f"ceiling=exceeded',
             'str(f"ceiling=exceeded', "test_check_mode_report_and_cli"),
            ("calibration identity", "if identity is not None and (", "if identity is not None and False and (",
             "test_check_mode_calibration_identity"),
            ("percentile reading", "return ordered[rank - 1]", "return ordered[-1]", "test_percentile_ignores_a_spike"),
            ("CPU sync read as its highest", '"cpu_sync_ms": percentile(on["cpu_sync_ms"])',
             '"cpu_sync_ms": max(on["cpu_sync_ms"])', "test_percentile_ignores_a_spike cpu_sync_ms"),
            ("CPU render read as its highest", '"cpu_render_ms": percentile(on["cpu_render_ms"])',
             '"cpu_render_ms": max(on["cpu_render_ms"])', "test_percentile_ignores_a_spike cpu_render_ms"),
            ("GPU cost read as its highest", "cost = percentile(delta)", "cost = max(delta)",
             "test_percentile_ignores_a_spike gpu_cost_ms"),
            ("presentation read as its highest", '"presentation_ms": percentile(on["presentation_ms"])',
             '"presentation_ms": max(on["presentation_ms"])', "test_percentile_ignores_a_spike presentation_ms"),
            ("unresolved GPU cost accepted", "if cost <= 0 and resolved:", "if cost < -1 and resolved:", "test_gpu_cost_not_resolved"),
            ("passes not matched to the first", "measure(root, runs[0] if runs else None, calibrating=True)", "measure(root, None, calibrating=True)",
             "test_calibration_over_passes"),
            ("calibration over passes", "for root in roots:", "for root in roots[:1]:", "test_calibration_over_passes"),
            ("costly control of every pass", "    for run in runs:\n        prove_control(",
             "    for run in runs[:1]:\n        prove_control(", "test_calibration_over_passes"),
            ("check reads one directory", "if args.check and len(args.directory) != 1:",
             "if args.check and len(args.directory) != len(args.directory):", "test_check_takes_one_directory"),
            ("check reads another shader's record", "check(args.directory[0], records[args.shader], args.cpu_pressure_limit)",
             "check(args.directory[0], records[next(iter(records))], args.cpu_pressure_limit)", "test_shader_records"),
            ("an absent record passes", 'raise ValueError("baseline=absent")', 'records[args.shader] = records["voiceorb"]',
             "test_shader_records"),
            ("calibration drops other records",
             'json.loads(args.calibrate.read_text()) if args.calibrate.exists() else {"shaders": {}}',
             '{"shaders": {}}', "test_shader_records"),
        )
        source = READER.read_text()
        suite = Path(__file__).read_text()
        with tempfile.TemporaryDirectory() as scratch:
            # A checkout the copied suite imports from: its scripts folder,
            # with the shader judge, and the Jarvis manifest the judge reads
            # the orb styles from.
            root = Path(scratch) / "scripts"
            (root / "shader").mkdir(parents=True)
            shutil.copyfile(ROOT / "check-voiceorb-shader.py", root / "check-voiceorb-shader.py")
            (Path(scratch) / "shell/plugins/vgs.jarvis").mkdir(parents=True)
            shutil.copyfile(JARVIS / "manifest.json", Path(scratch) / "shell/plugins/vgs.jarvis/manifest.json")
            for name, old, new, test in plants:
                with self.subTest(name=name):
                    self.assertEqual(source.count(old), 1)
                    changed = source.replace(old, new)
                    self.assertNotEqual(changed, source)
                    (root / "shader/readings.py").write_text(changed)
                    copy = root / "test-measure-shader.py"
                    copy.write_text(suite)
                    test, _, stream = test.partition(" ")
                    # -B: same-length plants written in one second would
                    # otherwise load the previous plant's cached bytecode.
                    result = subprocess.run(
                        [sys.executable, "-B", str(copy), f"ShaderReadings.{test}"],
                        env={"PATH": "/usr/bin:/bin", "HOME": scratch, "LC_ALL": "C"},
                        text=True, capture_output=True, check=False)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertIn("FAILED (", result.stderr)
                    if stream:
                        # A stream plant turns its own row red, no other.
                        failed = re.findall(r"^(?:FAIL|ERROR): .*\(stream='(\w+)'\)$", result.stderr, re.M)
                        self.assertEqual(failed, [stream], result.stderr)


SCENE = ROOT / "shader/measure-scene.sh"
GPU_PROCESSES = ROOT / "shader/gpu-processes.py"


class ShaderRunner(unittest.TestCase):
    def test_pmon_blocks_and_foreign_window(self):
        spec = importlib.util.spec_from_file_location("gpu_processes", GPU_PROCESSES)
        pmon = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(pmon)
        lines = """#Date Time gpu pid type sm mem enc dec jpg ofa command
#YYYYMMDD HH:MM:SS Idx # C/G % % % % % % name
20261118 04:31:36 0 101 C+G 8 - - - - - qs
20261118 04:31:36 0 102 G 4 - - - - - peer
20261118 04:31:36 0 103 C+G - - - - - -
20261118 04:31:37 0 104 G 5 - - - - - gone
#Date Time gpu pid type sm mem enc dec jpg ofa command
20261118 04:31:38 0 - - - - - - - -
"""
        cgroups = {101: "/unit.service/child", 102: "/unit.service-peer.service/worker.scope/subgroup",
                   103: "/unit.service"}
        times = iter((1000, 2000, 3000))
        records = list(pmon.blocks(lines.splitlines(keepends=True), "/unit.service", cgroups.get, lambda: next(times)))
        self.assertEqual(records, [
            {"epoch_ms": 1000, "foreign_sm_pct": 4, "own_sm_pct": 8,
             "processes": [[101, 8, True, "qs", "unit.service"], [102, 4, False, "peer", "worker.scope"],
                           [103, 0, True, "", "unit.service"]]},
            {"epoch_ms": 2000, "foreign_sm_pct": 5, "own_sm_pct": 0,
             "processes": [[104, 5, False, "gone", ""]]},
            {"epoch_ms": 3000, "foreign_sm_pct": 0, "own_sm_pct": 0, "processes": []},
        ])
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "pmon.jsonl"
            self.assertEqual(pmon.window(path, 1000, 2000), ("unmeasured", []))
            path.write_text("".join(json.dumps(row) + "\n" for row in records) + '{"epoch_ms":')
            self.assertEqual(pmon.window(path, 1000, 2000), (5, ["gone", "peer@worker.scope"]))
            self.assertEqual(pmon.window(path, 3000, 3000), (0, []))
            self.assertEqual(pmon.window(path, 3001, 4000), ("unmeasured", []))

    def test_outer_sampler_stops_and_keeps_fence_status(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            nvidia = root / "nvidia-smi"
            nvidia.write_text(f"""#!{sys.executable}
from pathlib import Path
import os
import signal
import sys
home = Path(os.environ["HOME"])
assert sys.argv[1:] == ["pmon", "-s", "u", "-d", "1", "-o", "DT"]
def stop(signum, frame):
    (home / "stopped").touch()
    sys.exit(0)
signal.signal(signal.SIGTERM, stop)
signal.alarm(5)
print("20261118 04:31:38 0 - - - - - - - -", flush=True)
print("#Date Time gpu pid type sm mem enc dec jpg ofa command", flush=True)
while True:
    signal.pause()
""")
            nvidia.chmod(0o755)
            fence = root / "fence"
            fence.write_text(f"""#!{sys.executable}
from pathlib import Path
import sys
import time
assert sys.argv[1:4] == ["--keep", "--", "env"]
name, path = sys.argv[4].split("=", 1)
assert name == "VGS_SHADER_GPU_PROCESSES" and sys.argv[5:] == ["fixture scene", "scene arg"]
deadline = time.monotonic() + 3
while not Path(path).read_text().endswith("\\n"):
    assert time.monotonic() < deadline
    time.sleep(0.01)
sys.exit(42)
""")
            fence.chmod(0o755)
            result = subprocess.run(
                [sys.executable, str(GPU_PROCESSES), "run", str(root / "output"),
                 str(fence), "--keep", "--", "fixture scene", "scene arg"],
                env={"PATH": f"{scratch}:/usr/bin:/bin", "HOME": scratch, "LC_ALL": "C"},
                text=True, capture_output=True, check=False, timeout=10)
            self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
            self.assertTrue((root / "stopped").is_file())
            traces = list((root / "output").glob("gpu-processes-*.jsonl"))
            self.assertEqual(len(traces), 1)
            record = json.loads(traces[0].read_text())
            self.assertEqual(record["foreign_sm_pct"], 0)

    def test_null_uses_identical_off_scene(self):
        source = SCENE.read_text()
        needle = '${scene/null/off}'
        self.assertEqual(source.count(needle), 1)
        script = r"""
source "$1"
cpu_some_us() { echo 0; }
now_ms() { echo 0; }
shell_env=(); bundled_fonts=(); shader=voiceorb; repo="$HOME"
spawn_display() { printf '%s\n' "$@"; return 1; }
measure_scene 1 "$2" "$HOME/scene"
"""
        for mutant, text in ((False, source), (True, source.replace(needle, "${scene}"))):
            for mode in ("off", "null", "on", "costly"):
                with self.subTest(mutant=mutant, mode=mode), tempfile.TemporaryDirectory() as scratch:
                    subject = Path(scratch) / "measure-scene.sh"
                    subject.write_text(text)
                    nvidia = Path(scratch) / "nvidia-smi"
                    nvidia.write_text("#!/bin/sh\nexit 127\n")
                    nvidia.chmod(0o755)
                    result = subprocess.run(
                        [BASH, "-c", script, "_", str(subject), mode],
                        env={"PATH": f"{scratch}:/usr/bin:/bin", "HOME": scratch, "LC_ALL": "C"},
                        text=True, capture_output=True, check=False, timeout=10)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertEqual((Path(scratch) / "scene.gpu").read_text(), "unmeasured\n")
                    self.assertEqual((Path(scratch) / "scene.gpu-peak").read_text(), "unmeasured\n")
                    self.assertEqual((Path(scratch) / "scene.gpu-clock").read_text(), "unmeasured\n")
                    expected = "off" if mode == "null" else mode
                    self.assertEqual(f"VGS_SHADER_MODE={expected}" in result.stdout.splitlines(),
                                     not (mutant and mode == "null"), result.stdout)

    def test_gpu_window_mean_rounds_half_up_and_keeps_peak(self):
        source = SCENE.read_text()
        needle = "mean = (2 * sum(values) + count) // (2 * count)"
        self.assertEqual(source.count(needle), 1)
        mutant = source.replace(needle, "mean = round(sum(values) / count)")
        samples = ("4, 2580, 13801, P1", "2, 2601, 13801, P1", "5, 2602, 13801, P1", "7, 2632, 13801, P1")
        script = r"""
set -euo pipefail
source "$1"
cpu_some_us() { echo 0; }
now_ms() { echo 0; }
shell_env=(); bundled_fonts=(); shader=voiceorb; orb_style=""; orb_reduced=0; repo="$HOME"
spawn_display() {
  # Wait for the stand-in's acknowledgement that all samples were written.
  while [[ ! -f $HOME/gpu-ready ]]; do sleep 0.01; done
  echo 'shader-test: sampler-ready'
  return 1
}
measure_scene 1 on "$HOME/scene"
"""
        for text, rounded in ((source, 5), (mutant, 4)):
            with self.subTest(mean=rounded), tempfile.TemporaryDirectory() as scratch:
                root = Path(scratch)
                subject = root / "measure-scene.sh"
                subject.write_text(text)
                nvidia = root / "nvidia-smi"
                nvidia.write_text(
                    '#!/bin/sh\n'
                    '[ "$*" = "--query-gpu=utilization.gpu,clocks.sm,clocks.mem,pstate --format=csv,noheader,nounits -lms 500" ] || exit 1\n'
                    + 'printf "%s\\n" ' + " ".join(f"'{sample}'" for sample in samples) + '\n: >"$HOME/gpu-ready"\n')
                nvidia.chmod(0o755)
                result = subprocess.run(
                    [BASH, "-c", script, "_", str(subject)],
                    env={"PATH": f"{scratch}:/usr/bin:/bin", "HOME": scratch, "LC_ALL": "C"},
                    text=True, capture_output=True, check=False, timeout=10)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("shader-test: sampler-ready", result.stdout.splitlines(), result.stdout + result.stderr)
                self.assertEqual((root / "scene.gpu-samples").read_text(), "\n".join(samples) + "\n")
                self.assertEqual((root / "scene.gpu").read_text(), f"{rounded}\n")
                self.assertEqual((root / "scene.gpu-peak").read_text(), "7\n")
                self.assertEqual((root / "scene.gpu-clock").read_text(), STEADY_CLOCK + "\n")

    def held_scene(self, text, state):
        """Drive measure_held_scene from TEXT with its sandbox stubbed:
        measure_scene counts each measurement and held_mode_state answers
        STATE after it. Returns the run, how many times the scene was
        measured, and the scratch HOME the scene's log is under."""
        with tempfile.TemporaryDirectory() as scratch:
            subject = Path(scratch) / "measure-scene.sh"
            subject.write_text(text)
            script = """
set -euo pipefail
source "$1"
source "$2"
home="$HOME"; stub_state="$3"; sandbox="$HOME"
mode_hold=(WAYLAND-1 "3510x1866 scale=2")
measure_scene() {
  local n=0
  [[ -f $home/measured ]] && n="$(<"$home/measured")"
  echo $((n + 1)) >"$home/measured"
  scene_cpu_some_pct=1.5 scene_gpu_foreign_pct=2 scene_gpu_pct=4 scene_gpu_peak_pct=7
  scene_gpu_foreign_peers='["peer@worker.scope"]'
  scene_gpu_clock=unmeasured
  scene_start_ms=1795000000000 scene_end_ms=1795000012000
}
held_mode_state() { echo "$stub_state"; }
mode_scale_of() { echo "1755x933 scale=1.5"; }
measure_held_scene 2 on "$HOME/scale-2-on"
"""
            result = subprocess.run(
                [BASH, "-c", script, "_", str(ROOT / "smoke/verdict.sh"), str(subject), state],
                env={"PATH": "/usr/bin:/bin", "HOME": scratch, "LC_ALL": "C"},
                text=True, capture_output=True, check=False)
            measured = Path(scratch) / "measured"
            return result, int(measured.read_text()) if measured.exists() else 0, scratch

    MEASURED = ("shader-cost: scene=on scale=2 samples=600 cpu_some_pct=1.5 gpu_foreign_pct=2 "
                'gpu_foreign_peers=["peer@worker.scope"] gpu_pct=4 gpu_peak_pct=7 '
                "clock=unmeasured start_ms=1795000000000 end_ms=1795000012000 log=%s/scale-2-on.log")

    def held_cases(self):
        """Rows: the state after the measurement, exit status,
        measurements and the last line printed."""
        return (
            ("held", 0, 1, self.MEASURED),
            ("reset", 1, 1, "shader-cost: failed output=reset scene=on scale=2 got=[1755x933 scale=1.5]"),
            ("unreadable", 1, 1, "shader-cost: failed output=unreadable scene=on scale=2 got=[1755x933 scale=1.5]"),
        )

    def assert_held_case(self, text, case):
        state, status, measured, last = case
        result, count, home = self.held_scene(text, state)
        self.assertEqual(result.returncode, status, result.stdout + result.stderr)
        self.assertEqual(count, measured, result.stdout)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[-1], last % home if last == self.MEASURED else last)

    def test_held_scene(self):
        text = SCENE.read_text()
        for case in self.held_cases():
            with self.subTest(state=case[0]):
                self.assert_held_case(text, case)

    def test_held_scene_mutants_turn_red(self):
        # Each plant keeps the matched text's place and removes one rule;
        # the case it names must fail.
        cases = self.held_cases()
        plants = (
            ("a reset is measured", "  if [[ $state != held ]]; then", "  if false; then", cases[1]),
            ("a reset passes", "    return 1\n  fi", "    :\n  fi", cases[1]),
        )
        text = SCENE.read_text()
        for name, old, new, case in plants:
            with self.subTest(name=name):
                self.assertEqual(text.count(old), 1)
                changed = text.replace(old, new)
                self.assertNotEqual(changed, text)
                with self.assertRaises(AssertionError):
                    self.assert_held_case(changed, case)

    def runner_copy(self, root, harness, text, args=(), scene=None, readings=None, manifest=None):
        scripts = root / "scripts"
        (scripts / "smoke").mkdir(parents=True)
        (scripts / "shader").mkdir()
        (root / "home").mkdir()
        env = {"PATH": "/usr/bin:/bin", "HOME": str(root / "home"), "LC_ALL": "C"}
        subprocess.run(["git", "init", "-q", "--template=", str(root)], env=env, check=True)
        for lock in ("vgs-smoke-hold", "vgs-smoke-turn"):
            (root / ".git" / lock).touch()
        (root / "shell/Ui/feedback/shaders").mkdir(parents=True)
        (root / "shell/Ui/foundation/shaders").mkdir(parents=True)
        (root / "shell/plugins/vgs.voice/shaders").mkdir(parents=True)
        (root / "shell/plugins/vgs.jarvis/shaders").mkdir(parents=True)
        script = scripts / "measure-shader.sh"
        script.write_text(text)
        owner = (ROOT / "check-voiceorb-shader.py").read_text()
        declarations = [line for line in owner.splitlines() if line.startswith("OPTIONS = ")]
        self.assertEqual(len(declarations), 1)
        changed = owner.replace(declarations[0], 'OPTIONS = ("--test-owner-option", "--test option with spaces")')
        self.assertNotEqual(changed, owner)
        (scripts / "check-voiceorb-shader.py").write_text(changed)
        shutil.copyfile(ROOT / "shader/Scene.qml", scripts / "shader/Scene.qml")
        if scene is None:
            shutil.copyfile(SCENE, scripts / "shader/measure-scene.sh")
        else:
            (scripts / "shader/measure-scene.sh").write_text(scene)
        if readings is not None:
            (scripts / "shader/readings.py").write_text(readings)
        for shader in ("shell/Ui/feedback/shaders/voiceorb.frag", "shell/Ui/feedback/shaders/radialbackdrop.frag", "shell/Ui/foundation/shaders/glasslens.frag", "shell/plugins/vgs.voice/shaders/plasma.frag"):
            # loads: scripts/check-voiceorb-shader.py scripts/shader/Scene.qml scripts/shader/measure-scene.sh scripts/shader/readings.py shell/Ui/feedback/shaders/radialbackdrop.frag shell/Ui/feedback/shaders/voiceorb.frag shell/Ui/foundation/shaders/glasslens.frag shell/plugins/vgs.jarvis/shaders/* shell/plugins/vgs.voice/shaders/plasma.frag -- the controls copy the files they list
            shutil.copyfile(ROOT.parent / shader, root / shader)
        for source in (*(JARVIS / "shaders").glob("*.frag"), JARVIS / "shaders/orb.glsl"):
            shutil.copyfile(source, root / "shell/plugins/vgs.jarvis/shaders" / source.name)
        (root / "shell/plugins/vgs.jarvis/manifest.json").write_text(json.dumps(JARVIS_MANIFEST if manifest is None else manifest))
        (scripts / "smoke/harness.sh").write_text('''
world_pressure_file="$HOME/pressure"
printf 'some avg10=7.30 avg60=0.00 avg300=0.00 total=0\\n' >"$world_pressure_file"
latency_pressure_limit=7.3
latency_pressure_verdict() { if [[ $2 == 7.3 ]]; then echo within; else echo unmeasured; fi; }
# These providers inject a pressure window; harness.sh owns the PSI math.
# No runner test waits on real time.
now_ms() {
  local stamp=0
  [[ ! -f $HOME/clock ]] || read -r stamp <"$HOME/clock"
  echo "$stamp"
  echo $((stamp + 1000)) >"$HOME/clock"
}
cpu_some_us() { echo 0; }
smoke_hold_begin() { :; }
smoke_hold_end() { :; }
sleep() { :; }
cpu_some_pct() {
  local kind rest
  while read -r kind rest; do
    if [[ $kind == some && $rest =~ avg10=([0-9]+\\.[0-9])[0-9]($|[[:space:]]) ]]; then echo "${BASH_REMATCH[1]}"; return; fi
  done <"$world_pressure_file"
  echo unmeasured
}
''' + f"""write_quiet_clock() {{ printf '%s\\n' '{STEADY_CLOCK}' >"$1.gpu-clock"; }}\n""" + harness)
        # The runner asks the fence before it makes anything; this stand-in
        # answers that no amdgpu node is visible. scripts/test-gpu-fence.sh
        # holds the runner to the call.
        fence = scripts / "smoke/gpu-fence.sh"
        fence.write_text("#!/bin/sh\nexit 0\n")
        fence.chmod(0o755)
        compiler = root / "qsb stand-in"
        compiler.write_text(f"""#!{sys.executable}
import json, os, pathlib, sys
pathlib.Path(os.environ["HOME"], "compiler-args.json").write_text(json.dumps(sys.argv[1:]))
with open(pathlib.Path(os.environ["HOME"], "compiler-calls"), "a") as calls:
    calls.write(json.dumps(sys.argv[1:]) + "\\n")
""")
        compiler.chmod(0o755)
        (root / "world-tmp").mkdir()
        return subprocess.run(
            [BASH, str(script), *args],
            env=dict(env, QSB=str(compiler), TMPDIR=str(root / "world-tmp")),
            text=True, capture_output=True, check=False, timeout=60)

    def test_uses_world_scratch(self):
        harness = """
scratch="$(mktemp -d "$TMPDIR/vgshell-smoke.XXXXXX")"
printf 'shader-test: scratch=%s\\n' "$scratch"
exit 0
"""
        text = RUNNER.read_text()
        old = 'source_repo="$repo"\n'
        self.assertEqual(text.count(old), 1)
        mutant = text.replace(old, old + 'export TMPDIR="$source_repo/undeclared"\n')
        self.assertNotEqual(mutant, text)
        with tempfile.TemporaryDirectory() as scratch:
            for index, (source, status) in enumerate(((text, 0), (mutant, 1))):
                with self.subTest(mutant=index):
                    root = Path(scratch) / str(index)
                    result = self.runner_copy(root, harness, source)
                    self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                    if status == 0:
                        directories = list((root / "world-tmp").glob("vgshell-smoke.*"))
                        self.assertTrue(directories)
                    self.assertFalse((root / "tmp").exists())

    def test_runs_needs_calibration(self):
        # Check mode judges one pass; the refusals come before the harness,
        # whose stand-in says so if it is reached.
        harness = "echo 'shader-test: harness-reached'; exit 0\n"
        cases = (
            (["--runs", "2"], "shader-cost: refused argument=--runs without=--calibrate"),
            (["--calibrate", "out.json", "--runs", "0"], "shader-cost: refused argument=--runs value=0"),
            (["--calibrate", "out.json", "--runs"], "shader-cost: refused argument=--runs value="),
            (["--shader", "other"], "shader-cost: refused argument=--shader value=other"),
            (["--shader"], "shader-cost: refused argument=--shader value="),
        )
        text = RUNNER.read_text()
        old = 'if [[ -n $runs && ${choice[0]} != --calibrate ]]; then'
        self.assertEqual(text.count(old), 1)
        changed = text.replace(old, 'if [[ -n $runs && ${choice[0]} == never ]]; then')
        self.assertNotEqual(changed, text)
        with tempfile.TemporaryDirectory() as scratch:
            for index, (args, line) in enumerate(cases):
                with self.subTest(args=args):
                    result = self.runner_copy(Path(scratch) / str(index), harness, text, args)
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                    self.assertEqual(result.stdout, line + "\n")
            result = self.runner_copy(Path(scratch) / "mutant", harness, changed, cases[0][0])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("shader-test: harness-reached", result.stdout)

    def test_pressure_stops_before_compilation_or_next_scene(self):
        harness = '''
home="$HOME"; sandbox="$HOME/sandbox"; mkdir -p "$sandbox"
failures=0; mode_hold=()
first_name() { echo WAYLAND-1; }
unscaled_mode_of() { echo 1920x1080; }
hidpi_mode_of() { echo 3840x2160; }
hold_mode() { mode_hold=("$2" "$3 scale=$4"); }
release_mode() { mode_hold=(); }
'''
        scene = '''
measure_held_scene() {
  echo measured >>"$home/scenes"
  scene_cpu_some_pct=7.3 scene_gpu_foreign_pct=1 scene_gpu_pct=2 scene_gpu_peak_pct=4
  write_quiet_clock "$3"
  if [[ ${dirty_after:-any} == any || $2 == "${dirty_after:-any}" ]]; then
    printf 'some avg10=7.40 total=0\\n' >"$world_pressure_file"
  fi
}
'''
        text = RUNNER.read_text()
        needle = '  [[ $result == within ]] || {'
        self.assertEqual(text.count(needle), 1)
        mutant = text.replace(needle, '  true || {')
        # Restoring the old avg10 reading makes only the ended-costly
        # regression refuse: the next fresh window itself is quiet.
        window = 'pressure="$(cpu_some_pct "$start_us" "$end_us" "$elapsed_ms")"'
        self.assertEqual(text.count(window), 1)
        historical = text.replace(window, r"""pressure=unmeasured
  while read -r kind rest; do
    if [[ $kind == some && $rest =~ avg10=([0-9]+\.[0-9])[0-9]($|[[:space:]]) ]]; then pressure="${BASH_REMATCH[1]}"; break; fi
  done <"$world_pressure_file"
""")
        with tempfile.TemporaryDirectory() as scratch:
            for name, seed, count in (("loaded", "some avg10=7.40 total=0", 0),
                                      ("unread", "full avg10=0.00 total=0", 0),
                                      ("later", "some avg10=7.30 total=0", 1),
                                      ("ended-costly", "some avg10=7.30 total=0", 3)):
                for index, source in enumerate((text, mutant, historical)):
                    with self.subTest(case=name, mutant=index):
                        root = Path(scratch) / f"{name}-{index}"
                        setup = harness + f"printf '%s\\n' '{seed}' >\"$world_pressure_file\"\n"
                        if name == "ended-costly":
                            setup += 'dirty_after=costly\ncpu_some_pct() { echo 7.3; }\n'
                        result = self.runner_copy(root, setup, source, scene=scene, readings="pass\n")
                        self.assertEqual(set(re.findall(r"window_ms=([0-9]+)", result.stdout)), {"1000"})
                        admitted = index == 1 or (name == "ended-costly" and index == 0)
                        self.assertEqual(result.returncode, 0 if admitted else 77, result.stdout + result.stderr)
                        measured = root / "home/scenes"
                        expected_count = 6 * len(SCENES) if admitted else count
                        self.assertEqual(len(measured.read_text().splitlines()) if measured.exists() else 0,
                                         expected_count)
                        if not admitted:
                            self.assertIn("status=not-measured reason=cpu-pressure", result.stdout)
                            next_scene = "run-1/plasma/scale-1-off" if name == "ended-costly" else "run-1/voiceorb/scale-1-on" if count else "setup"
                            self.assertIn("scene=" + next_scene, result.stdout)
                            self.assertEqual((root / "home/compiler-calls").exists(), expected_count > 0)

    def test_pass_loop(self):
        # The harness, the scene owner and the reader are stand-ins that
        # record what the runner hands them; the runner's own loop runs.
        harness = """
home="$HOME"; sandbox="$HOME/sandbox"
shell_env=(env -i PATH=/usr/bin:/bin HOME="$HOME")
mkdir -p -- "$sandbox"
failures=0; mode_hold=(); latency_pressure_limit=7.3
first_name() { echo WAYLAND-1; }
unscaled_mode_of() { echo 1755x933; }
hidpi_mode_of() { echo 3510x1866; }
hold_mode() { mode_hold=("$2" "$3 scale=$4"); }
release_mode() { mode_hold=(); }
"""
        scene = """
measure_held_scene() {
  printf 'held %s %s %s style=%s reduced=%s\\n' "$1" "$2" "${3#"$logs"/}" "$orb_style" "$orb_reduced" >>"$home/scenes"
  scene_cpu_some_pct=7.3 scene_gpu_foreign_pct=1 scene_gpu_pct=2 scene_gpu_peak_pct=4
  write_quiet_clock "$3"
}
measure_scene() {
  printf 'bare %s %s %s style=%s reduced=%s\\n' "$1" "$2" "${3#"$logs"/}" "$orb_style" "$orb_reduced" >>"$home/scenes"
  scene_cpu_some_pct=7.3 scene_gpu_foreign_pct=1 scene_gpu_pct=2 scene_gpu_peak_pct=4
  write_quiet_clock "$3"
}
"""
        readings = """import json, pathlib, sys
with open(pathlib.Path(__file__).with_name("readings-args"), "a") as calls:
    calls.write(json.dumps(sys.argv[1:]) + "\\n")
"""
        passes = 2
        text = RUNNER.read_text()
        plants = (
            ('measure_held_scene "$scale" "$scene"', 'measure_scene "$scale" "$scene"'),
            ("run <= runs;", "run <= 1;"),
            ('"${passes[@]/%//$shader}"', '"${passes[0]}/$shader"'),
            ('    for shader in "${shaders[@]}"; do\n      orb_scene', '    for shader in "${shaders[@]:0:1}"; do\n      orb_scene'),
            ('"$pass/$shader/scale-$scale-$scene"', '"$pass/scale-$scale-$scene"'),
            ('--shader "$shader" "${choice[@]}"', '--shader voiceorb "${choice[@]}"'),
            ('      orb_scene "$shader"\n      mkdir -p -- "$pass/$shader"', '      mkdir -p -- "$pass/$shader"'),
        )
        sources = [text]
        for old, new in plants:
            self.assertEqual(text.count(old), 1, old)
            sources.append(text.replace(old, new))
            self.assertNotEqual(sources[-1], text)
        with tempfile.TemporaryDirectory() as scratch:
            for chosen in ((), ("plasma",)):
                shaders = chosen or SCENES
                want = [f"held {scale} {mode} run-{run}/{shader}/scale-{scale}-{mode} style=%s reduced=%s" % orb_words(shader)
                        for run in range(1, passes + 1) for scale in (1, 2) for shader in shaders
                        for mode in ("off", "null", "on", "costly")]
                for index, source in enumerate(sources):
                    with self.subTest(shaders=chosen, mutant=index):
                        root = Path(scratch) / f"{len(chosen)}-{index}"
                        args = [*(["--shader", *chosen] if chosen else []), "--calibrate", "out.json", "--runs", str(passes)]
                        result = self.runner_copy(root, harness, source, args, scene, readings)
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        logs = [line.split("=", 1)[1] for line in result.stdout.splitlines()
                                if line.startswith("shader-cost: logs=")]
                        self.assertEqual(len(logs), 1, result.stdout)
                        scenes = (root / "home/scenes").read_text().splitlines()
                        calls = [json.loads(line) for line in (root / "scripts/shader/readings-args").read_text().splitlines()]
                        held = (scenes == want and calls == [
                            [f"{logs[0]}/run-{run}/{shader}" for run in range(1, passes + 1)]
                            + ["--shader", shader, "--calibrate", "out.json", "--cpu-pressure-limit", "7.3"] for shader in shaders])
                        # The fourth plant drops every shader but the first,
                        # and the seventh leaves each scene the orb words the
                        # costly loop set last, which one chosen shader cannot see.
                        self.assertEqual(held, index == 0 or (chosen != () and index in (4, 7)),
                                         f"scenes={scenes} readings={calls}")

    def test_scene_windows_and_retakes(self):
        # The real reader consumes the stand-in scenes. Only the first
        # voiceorb gate is loaded; both plasma on windows have high foreign
        # load. A missing foreign window is also loaded, but every scene's
        # high device-wide mean and peak are evidence only. GlassLens
        # retakes a changing off clock and then an on clock that differs
        # from the final off record.
        harness = r'''
home="$HOME"; sandbox="$HOME/sandbox"; mkdir -p "$sandbox"
failures=0; mode_hold=(); latency_pressure_limit=2.8
first_name() { echo WAYLAND-1; }
unscaled_mode_of() { echo 1920x1080; }
hidpi_mode_of() { echo 3840x2160; }
hold_mode() { mode_hold=("$2" "$3 scale=$4"); }
release_mode() { mode_hold=(); }
window= gate_pressure=0.5
latency_pressure_verdict() {
  case "$2" in 0.5|2.8) echo within ;; unmeasured) echo unread ;; *) echo unmeasured ;; esac
}
cpu_some_pct() { echo "$gate_pressure"; }
smoke_hold_begin() {
  window="$2"
  printf 'begin %s %s\n' "$1" "$window" >>"$home/events"
}
sleep() {
  printf 'gate %s\n' "${window:-setup}" >>"$home/events"
  if [[ $window == run-1/voiceorb/scale-1-off && ! -f $home/gate-once ]]; then
    gate_pressure=unmeasured
    : >"$home/gate-once"
  fi
}
smoke_hold_end() {
  printf 'end %s\n' "$window" >>"$home/events"
  window= gate_pressure=0.5
}
'''
        scene = r'''
measure_held_scene() {
  local label="${3#"$logs"/}"
  printf 'scene %s\n' "$label" >>"$home/events"
  scene_cpu_some_pct=0.5 scene_gpu_foreign_pct=2 scene_gpu_pct=8 scene_gpu_peak_pct=9
  case "${check_case:-calibration}:$label" in
    quiet:*|clock:*|weak:*) ;;
    missing:run-1/plasma/scale-1-off) scene_gpu_foreign_pct=unmeasured ;;
    missing:*) ;;
    *:run-1/plasma/scale-1-on) scene_gpu_foreign_pct=6 ;;
  esac
  if [[ $label == run-1/radial-backdrop/scale-1-off && ! -f $home/missing-once ]]; then
    scene_gpu_foreign_pct=unmeasured
    : >"$home/missing-once"
  fi
  cp "$source_repo/../fixture/scale-$1-$2.log" "$3.log"
  if [[ $label == run-1/plasma/scale-1-on && -n ${check_case:-} && $check_case != within ]]; then
    cp "$source_repo/../fixture/over.log" "$3.log"
  elif [[ $label == run-1/plasma/scale-1-costly && ${check_case:-} == weak ]]; then
    cp "$source_repo/../fixture/weak.log" "$3.log"
  fi
  cp "$source_repo/../fixture/scale-$1-$2.json" "$3.json"
  printf '%s\n' "$scene_cpu_some_pct" >"$3.cpu"
  printf '%s\n' "$scene_gpu_foreign_pct" >"$3.gpu-foreign"
  if [[ $scene_gpu_foreign_pct == 6 ]]; then
    printf '%s\n' '["peer@worker.scope"]' >"$3.gpu-foreign-peers"
  else
    printf '%s\n' '[]' >"$3.gpu-foreign-peers"
  fi
  printf '%s\n' "$scene_gpu_pct" >"$3.gpu"
  printf '%s\n' "$scene_gpu_peak_pct" >"$3.gpu-peak"
  write_quiet_clock "$3"
  case "${check_case:-calibration}:$label" in
    calibration:run-1/glass-lens/scale-1-off)
      if [[ ! -f $home/clock-off-once ]]; then
        printf '%s\n' 'clock_sm=787/2200/2632 clock_mem=810/13801 pstates=P1,P5 clock_samples=4' >"$3.gpu-clock"
        : >"$home/clock-off-once"
      fi ;;
    calibration:run-1/glass-lens/scale-1-on)
      if [[ ! -f $home/clock-on-once ]]; then
        printf '%s\n' 'clock_sm=1790/1800/1810 clock_mem=13801/13801 pstates=P2 clock_samples=4' >"$3.gpu-clock"
        : >"$home/clock-on-once"
      fi ;;
    clock:run-1/plasma/scale-1-on|weak:run-1/plasma/scale-1-on|weak:run-1/plasma/scale-1-costly)
      printf '%s\n' 'clock_sm=1790/1800/1810 clock_mem=13801/13801 pstates=P2 clock_samples=4' >"$3.gpu-clock" ;;
  esac
}
'''
        text = RUNNER.read_text()
        begin = '  smoke_hold_begin shader-cost "$label"'
        gate = '  elif shader_pressure_gate "$label"; then'
        retake = '    [[ $action == retake ]] || return 0'
        foreign_gate = '((scene_gpu_foreign_pct <= shader_gpu_busy_limit))'
        clock_gate = ' && $clock_state == steady'
        for needle in (begin, gate, retake, foreign_gate, clock_gate):
            self.assertEqual(text.count(needle), 1)
        late_hold = text.replace(begin, '  :').replace(gate, gate + '\n  ' + begin)
        no_retake = text.replace(retake, '    [[ $action == none ]] || return 0')
        device_gate = text.replace(foreign_gate, '((scene_gpu_pct <= shader_gpu_busy_limit))')
        voice = "run-1/voiceorb/scale-1-off"
        plasma = "run-1/plasma/scale-1-on"
        plasma_off = "run-1/plasma/scale-1-off"
        plasma_costly = "run-1/plasma/scale-1-costly"
        radial = "run-1/radial-backdrop/scale-1-off"
        glass_off = "run-1/glass-lens/scale-1-off"
        glass_on = "run-1/glass-lens/scale-1-on"
        calibration_retakes = (voice, plasma, radial, glass_off, glass_on)
        with tempfile.TemporaryDirectory() as scratch:
            fixture_root = Path(scratch) / "fixture"
            fixture_root.mkdir()
            fixture(fixture_root)
            (fixture_root / "over.log").write_text(log(0.35))
            (fixture_root / "weak.log").write_text(log(0.25))

            def measure(name, source, check_case=None, status=77, retakes=calibration_retakes):
                root = Path(scratch) / name
                output = root / "ceilings.json"
                calibrate = check_case is None
                args = ["--calibrate", str(output)] if calibrate else ["--shader", "plasma"]
                setup = harness
                if not calibrate:
                    check = json.dumps({"shaders": {"plasma": BASELINE}})
                    setup += f"printf '%s\\n' '{check}' >\"$source_repo/scripts/shader/ceilings.json\"\n"
                    setup += f"check_case={check_case}\n"
                result = self.runner_copy(root, setup, source, args, scene, READER.read_text())
                modes = ("off", "null", "on", "costly") if calibrate else ("off", "on", "costly")
                want = ["gate setup"]
                for scale in (1, 2):
                    for shader in SCENES if calibrate else ("plasma",):
                        for mode in modes:
                            label = f"run-1/{shader}/scale-{scale}-{mode}"
                            want.extend([f"begin shader-cost {label}", f"gate {label}", f"scene {label}", f"end {label}"]
                                        * (2 if label in retakes else 1))
                self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                self.assertEqual((root / "home/events").read_text().splitlines(), want)
                logs = Path(re.search(r"^shader-cost: logs=(.+)$", result.stdout, re.M)[1])
                if not calibrate:
                    self.assertEqual({str(path.relative_to(logs)).removesuffix(".loaded.load")
                                      for path in logs.rglob("*.loaded.load")}, set(retakes))
                    for label in retakes:
                        self.assertTrue((logs / (label + ".load")).read_text().startswith("loaded "))
                    diagnostic = next((line for line in result.stdout.splitlines()
                                       if line.startswith(("shader-cost: failed shader=", "shader-cost: status=not-measured shader="))), "")
                    expected = {
                        "within": "",
                        "loaded": "reason=gpu-load scale=1",
                        "weak": "costly-control=accepted scale=1",
                        "quiet": "ceiling=exceeded scale=1 readings=gpu_cost_ms",
                        "missing": "off_gpu_foreign_pct=unmeasured",
                        "clock": "on_clock=differs on_clock_record=[clock_sm=1790/1800/1810 ",
                    }[check_case]
                    if expected:
                        self.assertIn(expected, diagnostic)
                    else:
                        self.assertEqual(diagnostic, "")
                    if check_case == "loaded":
                        self.assertIn('on_gpu_foreign_pct=6 on_gpu_foreign_peers=["peer@worker.scope"]', diagnostic)
                    if check_case == "clock":
                        self.assertIn(f"off_clock=steady off_clock_record=[{STEADY_CLOCK}]", diagnostic)
                    if check_case == "weak":
                        self.assertTrue((logs / (plasma_costly + ".load")).read_text().endswith("clock=differs\n"))
                    return

                loaded = [dict(word.split("=", 1) for word in line.split()[2:])
                          for line in result.stdout.splitlines() if line.startswith("shader-cost: loaded ")]
                self.assertEqual(loaded, [
                    dict(scene=label, attempt=attempt, cpu_some_pct="0.5", gpu_foreign_pct=foreign, gpu_pct="8", gpu_peak_pct="9",
                         gate_cpu_some_pct=pressure, cpu_limit="2.8", gpu_limit="5", clock=clock,
                         accepted="false", action=action)
                    for label, attempt, foreign, pressure, clock, action in (
                        (voice, "1", "2", "unmeasured", "steady", "retake"),
                        (plasma, "1", "6", "0.5", "steady", "retake"),
                        (plasma, "2", "6", "0.5", "steady", "none"),
                        (radial, "1", "unmeasured", "0.5", "steady", "retake"),
                        (glass_off, "1", "2", "0.5", "changed", "retake"),
                        (glass_on, "1", "2", "0.5", "differs", "retake"),
                    )
                ])
                for label in calibration_retakes:
                    stem = logs / label
                    self.assertEqual({path.name.removeprefix(stem.name + ".loaded.")
                                      for path in stem.parent.glob(stem.name + ".loaded.*")},
                                     {"cpu", "gpu", "gpu-clock", "gpu-foreign", "gpu-foreign-peers", "gpu-peak",
                                      "json", "load", "log"})
                self.assertEqual((logs / (plasma + ".load")).read_text(),
                                 "loaded cpu=0.5 gpu_foreign=6 gpu=8 gpu_peak=9 clock_sm=2580/2601.5/2632 clock=steady\n")
                self.assertIn("scale=1 scene=on cpu_some_pct=0.5 gpu_foreign_pct=6 gpu_pct=8 gpu_peak_pct=9", result.stdout)
                records = json.loads(output.read_text())["shaders"]
                self.assertEqual(set(records), set(SCENES) - {"plasma"})
                for shader, mode, retaken in (("voiceorb", "off", True), ("radial-backdrop", "off", True),
                                              ("glass-lens", "off", True), ("glass-lens", "on", True),
                                              ("glass-lens", "null", False)):
                    self.assertEqual(records[shader]["calibration_runs"][0]["scene_loads"]["1"][mode],
                                     {"cpu_some_pct": 0.5, "gpu_foreign_pct": 2, "gpu_pct": 8,
                                      "gpu_peak_pct": 9, "clock_sm": "2580/2601.5/2632", "clock": "steady",
                                      "retaken": retaken})

            measure("calibration", text)
            for case, status, retakes in (("within", 0, (plasma,)), ("loaded", 77, (plasma,)),
                                          ("clock", 77, (plasma,)), ("weak", 1, (plasma, plasma_costly)), ("quiet", 1, ()),
                                          ("missing", 77, (plasma_off,))):
                with self.subTest(check=case):
                    measure(case, text, case, status, retakes)
            for name, mutant in (("late-hold", late_hold), ("no-retake", no_retake), ("device-gate", device_gate)):
                self.assertNotEqual(mutant, text)
                with self.subTest(mutant=name), self.assertRaises(AssertionError):
                    measure(name, mutant)
            without_clock_gate = text.replace(clock_gate, "")
            self.assertNotEqual(without_clock_gate, text)
            with self.assertRaises(AssertionError):
                measure("without-clock-gate", without_clock_gate, "clock", 77, (plasma,))

    def test_clock_rule(self):
        # Only the P-state and the memory clock judge a window: the SM boost
        # clock ranges inside one P-state and is recorded beside the scene.
        # Every scene reads OFF_CLOCK but the scale-1 on scene, which reads
        # the row's record, and the real reader writes the calibration.
        harness = '''
home="$HOME"; sandbox="$HOME/sandbox"; mkdir -p "$sandbox"
failures=0; mode_hold=(); latency_pressure_limit=2.8
first_name() { echo WAYLAND-1; }
unscaled_mode_of() { echo 1920x1080; }
hidpi_mode_of() { echo 3840x2160; }
hold_mode() { mode_hold=("$2" "$3 scale=$4"); }
release_mode() { mode_hold=(); }
latency_pressure_verdict() { echo within; }
cpu_some_pct() { echo 0.5; }
'''
        scene = r'''
measure_held_scene() {
  scene_cpu_some_pct=0.5 scene_gpu_foreign_pct=1 scene_gpu_pct=8 scene_gpu_peak_pct=9
  cp "$source_repo/../fixture/scale-$1-$2.log" "$3.log"
  cp "$source_repo/../fixture/scale-$1-$2.json" "$3.json"
  printf '%s\n' "$scene_cpu_some_pct" >"$3.cpu"
  printf '%s\n' "$scene_gpu_foreign_pct" >"$3.gpu-foreign"
  printf '%s\n' '[]' >"$3.gpu-foreign-peers"
  printf '%s\n' "$scene_gpu_pct" >"$3.gpu"
  printf '%s\n' "$scene_gpu_peak_pct" >"$3.gpu-peak"
  if [[ $1/$2 == 1/on ]]; then
    printf '%s\n' "$on_clock" >"$3.gpu-clock"
  else
    printf '%s\n' 'clock_sm=1410/2100/2790 clock_mem=14001/14001 pstates=P0 clock_samples=20' >"$3.gpu-clock"
  fi
}
'''
        # Rows: the scale-1 on scene's clock record, its clock state, and
        # the runner's exit.
        rows = (
            ("wide boost", "clock_sm=1400/1900/2800 clock_mem=14001/14001 pstates=P0 clock_samples=20", "steady", 0),
            ("P-state change", "clock_sm=1400/1900/2800 clock_mem=14001/14001 pstates=P0,P2 clock_samples=20", "changed", 77),
            ("memory change", "clock_sm=1400/1900/2800 clock_mem=13801/14001 pstates=P0 clock_samples=20", "changed", 77),
            ("P-state not off's", "clock_sm=1400/1900/2800 clock_mem=14001/14001 pstates=P2 clock_samples=20", "differs", 77),
            ("memory not off's", "clock_sm=1400/1900/2800 clock_mem=13801/13801 pstates=P0 clock_samples=20", "differs", 77),
        )
        text = RUNNER.read_text()
        gate = '  if [[ $states == *,* || $mem != "${BASH_REMATCH[3]}" ]]; then'
        pair = '    if [[ $states != "${BASH_REMATCH[4]}" || $mem != "${BASH_REMATCH[2]}" || $mem != "${BASH_REMATCH[3]}" ]]; then'
        for needle in (gate, pair):
            self.assertEqual(text.count(needle), 1)
        # Each plant drops one gate; the row it names must then fail.
        plants = (
            ("no P-state gate", text.replace(gate, '  if [[ $mem != "${BASH_REMATCH[3]}" ]]; then'), rows[1]),
            ("no memory gate", text.replace(gate, '  if [[ $states == *,* ]]; then'), rows[2]),
            ("no P-state pair", text.replace(pair, '    if [[ $mem != "${BASH_REMATCH[2]}" || $mem != "${BASH_REMATCH[3]}" ]]; then'), rows[3]),
        )
        with tempfile.TemporaryDirectory() as scratch:
            fixture_root = Path(scratch) / "fixture"
            fixture_root.mkdir()
            fixture(fixture_root)

            def assert_row(name, source, row):
                _, record, state, status = row
                root = Path(scratch) / name
                output = root / "ceilings.json"
                setup = harness + f"on_clock='{record}'\n"
                result = self.runner_copy(root, setup, source, ["--shader", "plasma", "--calibrate", str(output)],
                                          scene, READER.read_text())
                self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                logs = Path(re.search(r"^shader-cost: logs=(.+)$", result.stdout, re.M)[1])
                load = (logs / "run-1/plasma/scale-1-on.load").read_text().split()
                self.assertIn("clock_sm=1400/1900/2800", load)
                self.assertIn(f"clock={state}", load)
                if status == 0:
                    loads = json.loads(output.read_text())["shaders"]["plasma"]["calibration_runs"][0]["scene_loads"]
                    self.assertEqual((loads["1"]["on"]["clock_sm"], loads["1"]["off"]["clock_sm"]),
                                     ("1400/1900/2800", "1410/2100/2790"))
                else:
                    self.assertIn("scene-load=loaded", result.stdout)

            for row in rows:
                with self.subTest(row=row[0]):
                    assert_row(row[0].replace(" ", "-").replace("'", ""), text, row)
            for name, source, row in plants:
                self.assertNotEqual(source, text)
                with self.subTest(plant=name), self.assertRaises(AssertionError):
                    assert_row(name.replace(" ", "-"), source, row)

    def test_verdict_over_shaders(self):
        # Every shader is judged, and a failure outranks a shader that
        # could not be measured, whichever comes first.
        harness = """
home="$HOME"; sandbox="$HOME/sandbox"
shell_env=(env -i PATH=/usr/bin:/bin HOME="$HOME")
mkdir -p -- "$sandbox"
failures=0; mode_hold=(); latency_pressure_limit=7.3
first_name() { echo WAYLAND-1; }
unscaled_mode_of() { echo 1755x933; }
hidpi_mode_of() { echo 3510x1866; }
hold_mode() { mode_hold=("$2" "$3 scale=$4"); }
release_mode() { mode_hold=(); }
"""
        scene = ("measure_held_scene() { scene_cpu_some_pct=7.3 scene_gpu_foreign_pct=1 "
                 'scene_gpu_pct=2 scene_gpu_peak_pct=4; write_quiet_clock "$3"; }\n')
        readings = """import os, pathlib, sys
shader = sys.argv[sys.argv.index("--shader") + 1]
with open(pathlib.Path(__file__).with_name("judged"), "a") as judged:
    judged.write(shader + "\\n")
# The run directory, run-<voiceorb exit>-<plasma exit>, names each exit;
# every orb scene passes.
sys.exit(0 if shader.startswith("jarvis-orb") else int(pathlib.Path(os.environ["HOME"]).parent.name.split("-")[1 if shader == "voiceorb" else 2]))
"""
        rows = (("0", "0", 0), ("77", "0", 77), ("0", "77", 77), ("77", "1", 1), ("1", "77", 1), ("2", "1", 2))
        text = RUNNER.read_text()
        old = "( $verdict -eq 0 || $verdict -eq 77 )"
        self.assertEqual(text.count(old), 1)
        last = text.replace(old, "1 -eq 1")
        with tempfile.TemporaryDirectory() as scratch:
            for orb, plasma, status in rows:
                with self.subTest(voiceorb=orb, plasma=plasma):
                    root = Path(scratch) / f"run-{orb}-{plasma}"
                    result = self.runner_copy(root, harness, text, [], scene, readings)
                    self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                    self.assertEqual((root / "scripts/shader/judged").read_text().split(), list(SCENES))
            root = Path(scratch) / "mutant-1-77"
            self.assertEqual(self.runner_copy(root, harness, last, [], scene, readings).returncode, 77)

    def test_compiler_consumes_owner_options(self):
        # Stop before any compositor or QML process. The compiler only
        # records argv; the script still builds its real disposable source.
        harness = """
home="$HOME"; sandbox="$HOME/sandbox"
shell_env=(env -i PATH=/usr/bin:/bin HOME="$HOME")
mkdir -p -- "$sandbox"
first_name() { echo 'shader-test: stop-after-compile' >&2; return 1; }
"""
        text = RUNNER.read_text()
        old = '"${compiler_words[@]}"'
        self.assertEqual(text.count(old), 1)
        plants = ((text, True), (text.replace(old, '"${compiler_words[0]}"'), False))
        with tempfile.TemporaryDirectory() as scratch:
            for index, (source, includes_options) in enumerate(plants):
                with self.subTest(mutant=index):
                    root = Path(scratch) / str(index)
                    result = self.runner_copy(root, harness, source)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertIn("shader-test: stop-after-compile", result.stderr)
                    args = json.loads((root / "home/compiler-args.json").read_text())
                    self.assertEqual("--test-owner-option" in args, includes_options)
                    if includes_options:
                        self.assertEqual(args[:2], ["--test-owner-option", "--test option with spaces"])
                    calls = [json.loads(line) for line in (root / "home/compiler-calls").read_text().splitlines()]
                    self.assertEqual([call[-3:-1] for call in calls], [
                        ["-o", f"{root}/shell/costly-{shader}.frag.qsb"] for shader in SCENES])

    def test_costly_copy_of_each_shader(self):
        # Each costly source is its own shader with the 256-step loop added
        # before its output.
        harness = """
home="$HOME"; sandbox="$HOME/sandbox"
shell_env=(env -i PATH=/usr/bin:/bin HOME="$HOME")
mkdir -p -- "$sandbox"
first_name() { echo 'shader-test: stop-after-compile' >&2; return 1; }
"""
        rows = (("voiceorb", "shell/Ui/feedback/shaders/voiceorb.frag", "cost = angle + phase;"),
                ("plasma", "shell/plugins/vgs.voice/shaders/plasma.frag", "cost = ang + uTime;"),
                *((f"jarvis-orb-{style}", f"shell/plugins/vgs.jarvis/shaders/{style}.frag", "cost = r + uFlow;")
                  for style in ORB_STYLES),
                ("jarvis-orb-reduced", f"shell/plugins/vgs.jarvis/shaders/{ORB_DEFAULT}.frag", "cost = r + uFlow;"),
                ("radial-backdrop", "shell/Ui/feedback/shaders/radialbackdrop.frag", "cost = p.x * 0.01 + uJoin.x;"),
                ("glass-lens", "shell/Ui/foundation/shaders/glasslens.frag", "cost = p.x * 0.01 + uRadius;"))
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            result = self.runner_copy(root, harness, RUNNER.read_text())
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            # qsb resolves each orb style's include beside the source it compiles.
            self.assertEqual((root / "home/sandbox/orb.glsl").read_text(), (JARVIS / "shaders/orb.glsl").read_text())
            for shader, source, seed in rows:
                with self.subTest(shader=shader):
                    costly = (root / f"home/sandbox/costly-{shader}.frag").read_text()
                    # loads: shell/Ui/feedback/shaders/radialbackdrop.frag shell/Ui/foundation/shaders/glasslens.frag shell/plugins/vgs.jarvis/shaders/* shell/plugins/vgs.voice/shaders/plasma.frag -- the case reads the files it lists
                    original = (ROOT.parent / source).read_text()
                    self.assertIn(seed, costly)
                    self.assertIn("for (int i = 0; i < 256; ++i)", costly)
                    self.assertNotIn("for (int i = 0; i < 256; ++i)", original)
                    # Everything before the planted loop is the shader's own source.
                    self.assertTrue(original.startswith(costly[:costly.index("float cost =")].rstrip()))

    def test_orb_scenes_follow_manifest(self):
        # The orb scenes come from the Jarvis manifest's Orb style setting: a
        # planted list and default change which costly copies build and
        # which scene --shader accepts, and an empty list refuses with the
        # judge's key before the harness.
        harness = """
home="$HOME"; sandbox="$HOME/sandbox"
shell_env=(env -i PATH=/usr/bin:/bin HOME="$HOME")
mkdir -p -- "$sandbox"
first_name() { echo 'shader-test: stop-after-compile' >&2; return 1; }
"""

        def planted(styles, default):
            manifest = json.loads(json.dumps(JARVIS_MANIFEST))
            manifest["schema"]["orbStyle"]["options"] = [{"value": style, "label": style} for style in styles]
            manifest["settings"]["orbStyle"] = default
            return manifest

        text = RUNNER.read_text()
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch) / "planted"
            result = self.runner_copy(root, harness, text, manifest=planted(["bubble", "ribbons"], "ribbons"))
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            calls = [json.loads(line) for line in (root / "home/compiler-calls").read_text().splitlines()]
            self.assertEqual([call[-2] for call in calls], [f"{root}/shell/costly-{shader}.frag.qsb" for shader in (
                "voiceorb", "plasma", "jarvis-orb-bubble", "jarvis-orb-ribbons", "jarvis-orb-reduced",
                "radial-backdrop", "glass-lens")])
            reduced = (root / "home/sandbox/costly-jarvis-orb-reduced.frag").read_text()
            self.assertTrue((JARVIS / "shaders/ribbons.frag").read_text().startswith(
                reduced[:reduced.index("float cost =")].rstrip()))
            result = self.runner_copy(Path(scratch) / "unlisted", harness, text, ["--shader", "jarvis-orb-glass-bead"],
                                      manifest=planted(["bubble"], "bubble"))
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertEqual(result.stdout, "shader-cost: refused argument=--shader value=jarvis-orb-glass-bead\n")
            result = self.runner_copy(Path(scratch) / "empty", harness, text, manifest=planted([], "glass-bead"))
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertEqual(result.stdout, "shader-cost: failed orb-styles=invalid reason=no-options\n")
            self.assertFalse((Path(scratch) / "empty/home/compiler-calls").exists())


if __name__ == "__main__":
    unittest.main()
