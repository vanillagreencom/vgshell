#!/usr/bin/env python3
"""Exercise the shipped installer in J09, with local download/uv/Python doubles.

Controls keep each rule's matched source text while removing its behavior.
They modify only disposable plugin copies. No real package, model, audio,
account, authentication or desktop service is used.
"""
import fcntl
import hashlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import pty
import re
import select
import shlex
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import termios
import time
import unittest
import wave

REPO = Path(__file__).resolve().parents[1]
PLUGIN = REPO / "shell/plugins/vgs.jarvis"
DOUBLE = REPO / "scripts/fixtures/jarvis-setup/installer.py"


def namespace_entry():
    """Every behavior case runs under the shared private-world owner."""
    if os.environ.get("JARVIS_TEST_ROOT"):
        return
    (REPO / "tmp").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=REPO / "tmp", prefix="setup-standins-") as name:
        child = subprocess.run([str(REPO / "scripts/lib/jarvis-env.sh"), name, "--",
            sys.executable, str(Path(__file__).resolve())],
            env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"}, check=False)
    raise SystemExit(child.returncode)


class Setup(unittest.TestCase):
    def setUp(self):
        (REPO / "tmp").mkdir(exist_ok=True)
        scratch = tempfile.TemporaryDirectory(dir=REPO / "tmp", prefix="jarvis-setup-")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name).resolve()
        self.plugin = self.root / "plugin"
        shutil.copytree(PLUGIN, self.plugin)
        self.home = self.root / "home"
        self.home.mkdir()
        self.state = self.root / "state/vgshell/jarvis"
        self.data = self.root / "data/vgshell/jarvis/local"
        self.data.mkdir(parents=True)
        self.commands = self.root / "commands"
        self.commands.mkdir()
        # Bootstrap names are private doubles created after entering J09. No
        # host nvidia-smi runs: the double answers from gpu_memory and gpu_exit.
        for name in ("uv", "curl", "unshare", "gum", "nvidia-smi", "pw-record"):
            shutil.copyfile(DOUBLE, self.commands / name)
            (self.commands / name).chmod(0o700)
        (self.commands / "gum").write_text("""#!/bin/sh
cmd="$1"
shift
case "$cmd" in
  style)
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done
    [ "$#" -gt 0 ] && shift
    printf '%s\\n' "$@"
    ;;
  confirm)
    exit "${GUM_CONFIRM_EXIT:-0}"
    ;;
  *)
    exit 2
    ;;
esac
""")
        (self.commands / "gum").chmod(0o700)
        self.env = {"PATH": str(self.commands) + ":" + os.environ["PATH"],
                    "HOME": str(self.home), "XDG_STATE_HOME": str(self.root / "state"),
                    "XDG_DATA_HOME": str(self.root / "data"), "LC_ALL": "C",
                    "TMPDIR": str(self.root), "VGS_TEST_RUN": "1"}
        self.config = {"tier": "small"}
        self.spec = json.loads((self.plugin / "artifacts.json").read_text())
        self.downloads = self.data / "downloads"
        self.downloads.mkdir()
        # Membership is read from the producer. Each neutral file has a real
        # hash. Keep all engines, archive/direct and auxiliary shapes.
        for artifact in self.spec["artifacts"]:
            files = {}
            if "baseUrl" in artifact:
                for name in artifact["files"]:
                    payload = ("synthetic " + name).encode()
                    (self.downloads / "clone" / name).parent.mkdir(parents=True, exist_ok=True)
                    (self.downloads / "clone" / name).write_bytes(payload)
                    files[name] = hashlib.sha256(payload).hexdigest()
                artifact.update(baseUrl="https://fixture.invalid/clone/", files=files)
                continue
            if artifact["directory"] == ".":
                payload = b"synthetic direct model"
                name = next(iter(artifact["files"]))
                (self.downloads / name).write_bytes(payload)
                files = {name: hashlib.sha256(payload).hexdigest()}
                filename = name
            else:
                filename = artifact["id"] + ".tar.bz2"
                with tarfile.open(self.downloads / filename, "w:bz2") as bundle:
                    for name in list(artifact["files"]) + [
                            directory + "/data" for directory in artifact.get("auxiliaryDirectories", [])]:
                        payload = ("synthetic " + name).encode()
                        item = tarfile.TarInfo(artifact["directory"] + "/" + name)
                        item.size = len(payload)
                        bundle.addfile(item, io.BytesIO(payload))
                        if name in artifact["files"]:
                            files[name] = hashlib.sha256(payload).hexdigest()
            artifact.update(url="https://fixture.invalid/" + filename, files=files,
                            sha256=hashlib.sha256((self.downloads / filename).read_bytes()).hexdigest())
        (self.plugin / "artifacts.json").write_text(json.dumps(self.spec))
        self.write_config()

    def write_config(self):
        (self.data / "fixture.json").write_text(json.dumps(self.config))

    def run_command(self, *args):
        return subprocess.run([sys.executable, "-I", str(self.plugin / "setup-local"), *args],
                              env=self.env, capture_output=True, text=True, check=False, timeout=30)

    def calls(self):
        path = self.data / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def reset_calls(self):
        (self.data / "calls.jsonl").write_text("")

    def offered(self):
        result = self.run_command("choices")
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def install(self, code=0, tier=True):
        result = self.run_command("install", *([self.config["tier"]] if tier else []))
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result

    def plant_machine(self, gpu, ram_kib, threads):
        """The machine the copy reads: GPU memory in MiB (None for no GPU),
        MemTotal in kB and CPU threads. The double answers nvidia-smi; the
        copy reads a planted /proc/meminfo and thread count in place of the
        host's, through its own meminfo parser."""
        meminfo, count = self.root / "meminfo", self.root / "threads"
        meminfo.write_text(f"MemTotal:       {ram_kib} kB\nMemAvailable:   {ram_kib} kB\n")
        count.write_text(str(threads))
        self.config.update(gpu_memory=[] if gpu is None else [gpu], gpu_exit=9 if gpu is None else 0)
        self.write_config()
        for name, needle, replacement in (
                ("measure-local", 'Path("/proc/meminfo")', f"Path({str(meminfo)!r})"),
                ("setup-local", '"threads": os.cpu_count()', f'"threads": int(Path({str(count)!r}).read_text())')):
            path = self.plugin / name
            text = path.read_text()
            if needle in text:
                self.assertEqual(text.count(needle), 1, needle)
                path.write_text(text.replace(needle, replacement))

    def report(self):
        result = self.run_command("status")
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def ready(self):
        self.assertEqual(self.report(), {"tone": "ok", "text": "Ready: " + self.config["tier"], "action": False})
        self.assertEqual((self.data / "probed").read_text(), self.config["tier"])

    def not_ready(self):
        self.assertNotEqual(self.report()["tone"], "ok")

    def mutant(self, needle, replacement, name="setup-local"):
        path = self.plugin / name
        text = path.read_text()
        self.assertEqual(text.count(needle), 1, needle)
        changed = text.replace(needle, replacement)
        self.assertNotEqual(changed, text)
        path.write_text(changed)

    def test_setup_and_status(self):
        self.assertEqual(self.report(), {"tone": "warning", "text": "Not set up", "action": True})
        self.install()
        self.ready()
        self.assertEqual((self.state / "local-ready.json").stat().st_mode & 0o777, 0o600)
        calls = [json.loads(line) for line in (self.data / "calls.jsonl").read_text().splitlines()]
        self.assertEqual([call[0] for call in calls if call[0] in ("unshare", "python")], ["unshare", "python"])
        # Retry uses the same venv path, not a relocated environment.
        self.install()
        self.ready()

    def plain_lines(self, result):
        return [line for line in result.stdout.splitlines() if line and not line.startswith("jarvis-setup:")]

    # A tier downloads one file per artifact; the window shows each line, so
    # a fresh install and a reusing one each read no line twice.
    def test_install_lines_name_each_file_and_control(self):
        self.config["tier"] = "medium"
        self.write_config()
        self.assertGreaterEqual(len(self.spec["tiers"]["medium"]["artifacts"]), 2, "tier discovery is broken: medium has one artifact")
        def assert_distinct():
            for result in (self.install(), self.install()):
                lines = self.plain_lines(result)
                self.assertEqual(len(lines), len(set(lines)), lines)
        assert_distinct()
        self.mutant('place = f"{value[\'tiers\'][tier][\'name\']}: file {index} of {len(artifacts)}"',
                    'place = value["tiers"][tier]["name"]')
        with self.assertRaises(AssertionError):
            assert_distinct()

    # A size the window states never reads as nothing: a few bytes kept
    # after a failed setup, or the free space of a full disk.
    SIZES = [1, 499_999, 500_000, 685_000_000, 999_499_999, 1_200_000_000]

    def assert_sizes(self, module):
        for count in self.SIZES:
            figure = re.search(r"[0-9]+(\.[0-9]+)?", module.size(count))
            self.assertIsNotNone(figure, count)
            self.assertGreater(float(figure.group()), 0, f"{count} bytes read as {module.size(count)}")

    def test_sizes_never_read_as_nothing_and_control(self):
        self.assert_sizes(self.load_module())
        self.mutant("    if megabytes < 1:\n", "    if False:\n")
        with self.assertRaises(AssertionError):
            self.assert_sizes(self.load_module())

    def test_each_tier_uses_the_manifest(self):
        for tier in self.spec["tiers"]:
            with self.subTest(tier=tier):
                shutil.rmtree(self.data / "models", ignore_errors=True)
                self.reset_calls()
                self.config["tier"] = tier
                self.write_config()
                self.install()
                self.ready()
                calls = [json.loads(line) for line in (self.data / "calls.jsonl").read_text().splitlines()]
                urls = [call[-1] for call in calls if call[0] == "curl"]
                expected = [a["url"] for a in self.spec["artifacts"] if a["id"] in self.spec["tiers"][tier]["artifacts"]]
                self.assertEqual(urls, expected)
                if self.spec["tiers"][tier]["provider"] == "cuda":
                    wheel = self.spec["runtimes"]["sherpa-onnx"]["cudaWheel"]
                    self.assertIn(wheel["url"], (self.data / "requirements-cuda.lock").read_text())
                    self.assertIn(wheel["sha256"], (self.data / "requirements-cuda.lock").read_text())

    def test_hash_and_control(self):
        artifact = next(a for a in self.spec["artifacts"] if a["id"] == "silero")
        path = self.downloads / Path(artifact["url"]).name
        path.write_bytes(b"bad hash")
        result = self.install(1)
        self.assertIn("download=hash-mismatch", result.stderr)
        self.not_ready()
        self.assertFalse((self.state / "local-ready.json").exists())
        self.assertFalse(list((self.data / "models").glob("*.partial")))
        self.mutant("if judge.sha256(partial) != digest:", "if False and judge.sha256(partial) != digest:")
        # The input verifier independently refuses corrupted model bytes.
        result = self.install(1)
        self.assertNotIn("download=hash-mismatch", result.stderr)
        self.assertIn("input=hash-mismatch", result.stderr)

    def test_child_failure_rules_and_controls(self):
        for key, code in (("uv_exit", 6), ("curl_exit", 7), ("probe_exit", 1), ("probe_exit", 77)):
            with self.subTest(key=key, code=code):
                self.install()
                self.ready()
                self.config[key] = code
                self.write_config()
                if key == "curl_exit":
                    artifact = next(a for a in self.spec["artifacts"]
                                    if a["id"] == self.spec["tiers"]["small"]["artifacts"][0])
                    (self.data / "models" / Path(artifact["url"]).name).unlink()
                self.install(code)
                self.not_ready()
                self.assertFalse((self.state / "local-ready.json").exists())
                # Preserve the rule's text while changing its effect.
                self.mutant("    if returncode != 0:", "    if False and returncode != 0:")
                self.install()
                self.ready()
                (self.plugin / "setup-local").write_text((PLUGIN / "setup-local").read_text())
                del self.config[key]
                self.write_config()

    def test_marker_invalidation_control(self):
        self.install()
        self.ready()
        self.config["uv_exit"] = 77
        self.write_config()
        self.install(77)
        self.assertFalse((self.state / "local-ready.json").exists())
        self.config["uv_exit"] = 0
        self.write_config()
        self.install()
        self.mutant("marker.unlink(missing_ok=True)", "False and marker.unlink(missing_ok=True)")
        self.config["uv_exit"] = 77
        self.write_config()
        self.install(77)
        self.assertTrue((self.state / "local-ready.json").exists(), "invalidation control did not reach the marker")

    def test_retired_tier_reads_unavailable_and_control(self):
        # A marker or a Local voice setting saved while the multilingual tiers
        # were declared names a tier the manifest no longer has.
        self.install()
        self.ready()
        marker = self.state / "local-ready.json"
        saved = json.loads(marker.read_text())
        for tier in ("multilingual-cpu", "multilingual-cuda"):
            with self.subTest(tier=tier):
                marker.write_text(json.dumps(dict(saved, tier=tier)))
                report = self.report()
                self.assertEqual([report["tone"], report["action"]], ["warning", True])
                self.assertIsNone(self.offered()["ready"])
                self.reset_calls()
                result = self.run_command("install", tier)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual([call[0] for call in self.calls() if call[0] != "nvidia-smi"], [])
        # A planted migration that reads a retired tier as another.
        self.mutant('tier = saved["tier"]\n',
                    'tier = saved["tier"] = {"multilingual-cuda": "small"}.get(saved["tier"], saved["tier"])\n')
        with self.assertRaises(AssertionError):
            self.not_ready()

    def test_identity_and_controls(self):
        cases = [
            ("requirements-local.lock", "lock"),
            ("venv/installed", "runtime"),
        ]
        for filename, name in cases:
            with self.subTest(name=name):
                self.install()
                path = self.data / filename if filename.startswith("venv/") else self.plugin / filename
                original = path.read_bytes()
                path.write_bytes(original + b"\n# changed\n")
                self.not_ready()
                needle = 'if {key: item for key, item in saved.items() if key != "memory"} != identity(judge, tier, data):'
                self.mutant(needle, 'if False and ' + needle[3:])
                self.ready()
                path.write_bytes(original)
                (self.plugin / "setup-local").write_text((PLUGIN / "setup-local").read_text())

    def test_identity_ignores_display_text_and_pins_selected_artifacts(self):
        self.install()
        self.ready()
        artifact = next(a for a in self.spec["artifacts"]
                        if a["id"] == self.spec["tiers"]["small"]["artifacts"][0])
        original = json.dumps(self.spec)
        self.spec["tiers"]["small"]["name"] = "Tiny"
        self.spec["tiers"]["small"]["description"] = "English, display-only"
        self.spec["tiers"]["small"]["downloadBytes"] += 1
        artifact["description"] = "display-only artifact note"
        (self.plugin / "artifacts.json").write_text(json.dumps(self.spec))
        self.ready()
        artifact["url"] = artifact["url"].replace("https://fixture.invalid/", "https://mirror.invalid/")
        (self.plugin / "artifacts.json").write_text(json.dumps(self.spec))
        self.not_ready()
        (self.plugin / "artifacts.json").write_text(original)
        self.spec = json.loads(original)
        self.ready()
        artifact = next(a for a in self.spec["artifacts"]
                        if a["id"] in self.spec["tiers"]["small"]["artifacts"]
                        and a["directory"] != "." and not a.get("auxiliaryDirectories"))
        archive = self.data / "models" / Path(artifact["url"]).name
        archive_bytes = archive.read_bytes()
        archive.write_bytes(b"identity-only archive hash")
        artifact["sha256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
        (self.plugin / "artifacts.json").write_text(json.dumps(self.spec))
        self.not_ready()
        needle = 'if {key: item for key, item in saved.items() if key != "memory"} != identity(judge, tier, data):'
        self.mutant(needle, 'if False and ' + needle[3:])
        self.ready()
        (self.plugin / "setup-local").write_text((PLUGIN / "setup-local").read_text())
        archive.write_bytes(archive_bytes)
        (self.plugin / "artifacts.json").write_text(original)
        self.spec = json.loads(original)
        self.mutant("hashed_files = [", 'hashed_files = [("artifacts.json", HERE / "artifacts.json"),')
        self.install()
        self.spec["tiers"]["small"]["name"] = "Tiny"
        self.spec["tiers"]["small"]["description"] = "English, display-only"
        artifact = next(a for a in self.spec["artifacts"]
                        if a["id"] == self.spec["tiers"]["small"]["artifacts"][0])
        artifact["description"] = "display-only artifact note"
        (self.plugin / "artifacts.json").write_text(json.dumps(self.spec))
        self.not_ready()
        (self.plugin / "setup-local").write_text((PLUGIN / "setup-local").read_text())
        (self.plugin / "artifacts.json").write_text(original)
        self.spec = json.loads(original)
        self.install()
        artifact = next(a for a in self.spec["artifacts"]
                        if a["id"] == self.spec["tiers"]["small"]["artifacts"][0])
        artifact["url"] = artifact["url"].replace("https://fixture.invalid/", "https://mirror.invalid/")
        (self.plugin / "artifacts.json").write_text(json.dumps(self.spec))
        needle = 'if {key: item for key, item in saved.items() if key != "memory"} != identity(judge, tier, data):'
        self.mutant(needle, 'if False and ' + needle[3:])
        self.ready()
        (self.plugin / "setup-local").write_text((PLUGIN / "setup-local").read_text())

    def auxiliary(self):
        """The small tier's artifact with an auxiliary directory, and that
        directory's installed file."""
        artifact = next(a for a in self.spec["artifacts"]
                        if a["id"] in self.spec["tiers"]["small"]["artifacts"] and a.get("auxiliaryDirectories"))
        return artifact, self.data / "models" / artifact["directory"] / artifact["auxiliaryDirectories"][0] / "data"

    def test_status_binds_installed_model_bytes_and_controls(self):
        artifact, auxiliary = self.auxiliary()
        pinned = self.data / "models" / artifact["directory"] / next(iter(artifact["files"]))
        unbound = ("if not previous:", "if False and not previous:")
        unverified = ('judge.verify_inputs(data / "models", artifacts)',
                      'False and judge.verify_inputs(data / "models", artifacts)')
        for name, path, control in (("auxiliary file changed", auxiliary, unbound),
                                    ("pinned file changed", pinned, unverified),
                                    ("auxiliary file added", auxiliary.with_name("added"), unbound)):
            with self.subTest(case=name):
                self.install()
                self.ready()
                path.write_bytes(b"not the installed bytes")
                self.not_ready()
                # The copy without the rule installs, then reads the same defect ready.
                self.mutant(*control)
                self.install()
                path.write_bytes(b"not the installed bytes")
                self.assertEqual(self.report()["tone"], "ok", "must-fail control stayed green: " + name)
                (self.plugin / "setup-local").write_text((PLUGIN / "setup-local").read_text())

    def test_status_opens_no_archive_and_install_still_checks_it(self):
        self.install()
        artifact, _ = self.auxiliary()
        (self.data / "models" / Path(artifact["url"]).name).write_bytes(b"not an archive")
        self.ready()
        # A copy whose status read runs the archive check cannot read this ready.
        self.mutant('judge.verify_inputs(data / "models", artifacts)', 'judge.verify(value, data / "models", artifacts)')
        self.not_ready()
        (self.plugin / "setup-local").write_text((PLUGIN / "setup-local").read_text())
        self.reset_calls()
        self.install()
        self.ready()
        self.assertEqual([call[-1] for call in self.calls() if call[0] == "curl"], [artifact["url"]])

    def version_1_marker(self, memory):
        """The marker the version 1 setup-local published for the installed
        small tier, built from that format and not by the copy under test."""
        by_id = {artifact["id"]: artifact for artifact in self.spec["artifacts"]}
        inputs = {"provider": "cpu", "cudaWheel": {"python": self.spec["runtimes"]["sherpa-onnx"]["cudaWheel"]["python"]},
                  "artifacts": [{key: by_id[name][key] for key in ("id", "url", "sha256", "directory")}
                                for name in self.spec["tiers"]["small"]["artifacts"]]}
        venv = self.data / "venv"
        files = [(name, self.plugin / name) for name in (
            "requirements-local.lock", "requirements-local-cpu.lock",
            self.spec["fixture"]["audio"], self.spec["fixture"]["transcript"])]
        files += [("venv/" + str(path.relative_to(venv)), path) for path in sorted(venv.rglob("*"))
                  if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc"]
        digest = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode() + b"\0")
        for name, path in files:
            digest.update(name.encode() + b"\0" + hashlib.sha256(path.read_bytes()).hexdigest().encode() + b"\0")
        digest.update(str((venv / "bin/python").resolve()).encode())
        return {"schemaVersion": 1, "tier": "small", "data": str(self.data.resolve()),
                "inputs": digest.hexdigest(), "memory": memory}

    def test_version_1_marker_migrates_in_place_and_controls(self):
        self.install()
        marker = self.state / "local-ready.json"
        current = json.loads(marker.read_text())
        self.assertEqual(current["schemaVersion"], 2)
        old = self.version_1_marker(current["memory"])
        marker.write_text(json.dumps(old))
        self.ready()
        self.assertEqual(json.loads(marker.read_text()), current)
        self.assertEqual(marker.stat().st_mode & 0o777, 0o600)
        self.assertEqual([path.name for path in self.state.glob(".local-ready-*")], [])
        # A second read publishes nothing: a publication replaces the file.
        published = marker.stat().st_ino
        self.ready()
        self.assertEqual(marker.stat().st_ino, published)
        # Not ready, and left as planted: an unknown version, a version 1
        # marker whose tier fails the version 2 judge, and one whose own
        # identity no longer holds.
        artifact, _ = self.auxiliary()
        pinned = self.data / "models" / artifact["directory"] / next(iter(artifact["files"]))
        installed = self.data / "venv/installed"
        for name, planted, path in (("unknown version", dict(current, schemaVersion=3), None),
                                    ("version 2 judge", old, pinned),
                                    ("version 1 identity", old, installed)):
            with self.subTest(case=name):
                marker.write_text(json.dumps(planted))
                original = path.read_bytes() if path else None
                if path:
                    path.write_bytes(original + b"changed")
                self.not_ready()
                self.assertEqual(json.loads(marker.read_text()), planted)
                if path:
                    path.write_bytes(original)
        # The copy that skips the version 1 identity migrates that marker.
        self.mutant('data, previous=True):\n        raise ValueError("marker=stale")',
                    'data, previous=True) and False:\n        raise ValueError("marker=stale")')
        installed.write_bytes(installed.read_bytes() + b"changed")
        self.ready()
        self.assertEqual(json.loads(marker.read_text())["schemaVersion"], 2)

    def test_install_reuses_verified_models_and_redownloads_only_corrupt_model(self):
        self.install()
        self.ready()
        self.reset_calls()
        self.install()
        self.ready()
        self.assertEqual([call[-1] for call in self.calls() if call[0] == "curl"], [])
        small = set(self.spec["tiers"]["small"]["artifacts"])
        medium = set(self.spec["tiers"]["medium"]["artifacts"])
        by_id = {artifact["id"]: artifact for artifact in self.spec["artifacts"]}
        small_only = [by_id[name] for name in self.spec["tiers"]["small"]["artifacts"] if name not in medium]
        old_entries = []
        for old in small_only:
            old_entries.append(self.data / "models" / Path(old["url"]).name)
            if old["directory"] != ".":
                old_entries.append(self.data / "models" / old["directory"])
        self.reset_calls()
        self.config["tier"] = "medium"
        self.write_config()
        self.install()
        self.ready()
        expected = [by_id[name]["url"] for name in self.spec["tiers"]["medium"]["artifacts"] if name not in small]
        self.assertEqual([call[-1] for call in self.calls() if call[0] == "curl"], expected)
        for path in old_entries:
            self.assertFalse(path.exists(), path)
        self.config["tier"] = "small"
        self.write_config()
        self.install()
        self.ready()
        self.reset_calls()
        self.mutant("        if path.name in keep:\n", "        if True or path.name in keep:\n")
        self.config["tier"] = "medium"
        self.write_config()
        self.install()
        self.ready()
        for path in old_entries:
            self.assertTrue(path.exists(), path)
        (self.plugin / "setup-local").write_text((PLUGIN / "setup-local").read_text())
        self.config["tier"] = "small"
        self.write_config()
        self.install()
        self.ready()
        artifact = next(a for a in self.spec["artifacts"]
                        if a["id"] in self.spec["tiers"]["small"]["artifacts"] and a["directory"] != ".")
        corrupt = next(iter(artifact["files"]))
        (self.data / "models" / artifact["directory"] / corrupt).write_text("corrupt model")
        self.reset_calls()
        self.install()
        self.ready()
        self.assertEqual([call[-1] for call in self.calls() if call[0] == "curl"], [artifact["url"]])
        self.reset_calls()
        self.mutant("verified = reuse(judge, value, models, artifacts)",
                    "verified = set() if reuse(judge, value, models, artifacts) is not None else set()")
        self.install()
        expected = [a["url"] for a in self.spec["artifacts"]
                    if a["id"] in self.spec["tiers"]["small"]["artifacts"]]
        self.assertEqual(set(call[-1] for call in self.calls() if call[0] == "curl"), set(expected))

    def test_changed_during_probe_control(self):
        self.config["change_runtime"] = True
        self.write_config()
        result = self.install(1)
        self.assertIn("runtime=changed-during-probe", result.stderr)
        self.not_ready()
        self.mutant("if ready != identity(judge, tier, data):", "if False and ready != identity(judge, tier, data):")
        self.install()
        # The saved pre-probe identity still makes status refuse.
        self.assertTrue((self.state / "local-ready.json").exists())
        self.not_ready()

    def test_memory_publication_and_controls(self):
        self.install()
        marker = self.state / "local-ready.json"
        saved = json.loads(marker.read_text())
        self.assertEqual(saved["memory"], {"ram": 4096, "gpu": None})
        for need in (None, {"ram": 0, "gpu": None}, {"ram": True, "gpu": None}):
            with self.subTest(need=need):
                marker.write_text(json.dumps(dict(saved, memory=need)))
                self.not_ready()
        marker.write_text(json.dumps(dict(saved, memory={"ram": 0, "gpu": None})))
        self.mutant('judge.validate_memory(saved["memory"], value["tiers"][tier]["provider"])',
                    'False and judge.validate_memory(saved["memory"], value["tiers"][tier]["provider"])')
        setup = self.load_module()
        current = setup.identity(setup.measurement(), "small", self.data)
        marker.write_text(json.dumps(dict(current, memory={"ram": 0, "gpu": None})))
        self.ready()
        (self.plugin / "setup-local").write_text((PLUGIN / "setup-local").read_text())
        self.config["probe_record"] = {"scope": "wrong", "provider_requested": "cpu",
            "artifact_ids": self.spec["tiers"]["small"]["artifacts"], "peak_rss_bytes": 4096,
            "gpu_peak_bytes": None}
        self.write_config()
        result = self.install(1)
        self.assertIn("memory-measurement=mismatched", result.stderr)
        self.assertFalse(marker.exists())
        self.assertFalse((self.data / "venv").exists())
        path = self.plugin / "measure-local"
        source = path.read_text()
        needle = 'if (record.get("scope") != scope or record.get("provider_requested") != provider'
        self.assertEqual(source.count(needle), 1)
        path.write_text(source.replace(needle, 'if False and (record.get("scope") != scope or record.get("provider_requested") != provider'))
        self.install()
        self.ready()

    def test_serialization_and_control(self):
        self.install()
        self.ready()
        marker = (self.state / "local-ready.json").read_bytes()
        # A copy with a one-second bound keeps the busy case short.
        self.mutant("LOCK_WAIT = 30\n", "LOCK_WAIT = 1\n")
        with (self.state / "local-setup.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.install(1)
            self.assertIn("setup=busy", result.stderr)
            self.assertEqual(self.report(), {"tone": "info", "text": "Setting up", "action": False})
            self.assertEqual((self.state / "local-ready.json").read_bytes(), marker)
            self.mutant("fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)",
                        "False and fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)")
            self.install()

    def test_install_waits_for_a_status_reader_and_control(self):
        # A status read holds the lock shared while it verifies; install
        # waits for it rather than ending busy. The child must still be
        # waiting a second after it starts: a run that ends busy exits at
        # once, well inside that second.
        def held_install():
            with (self.state / "local-setup.lock").open("a") as lock:
                fcntl.flock(lock, fcntl.LOCK_SH | fcntl.LOCK_NB)
                child = subprocess.Popen([sys.executable, "-I", str(self.plugin / "setup-local"), "install", "small"],
                                         env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                deadline = time.monotonic() + 1
                while time.monotonic() < deadline and child.poll() is None:
                    time.sleep(0.05)
                waited = child.poll() is None
            out, err = child.communicate(timeout=60)
            return waited, child.returncode, err
        self.state.mkdir(parents=True, exist_ok=True)
        waited, code, err = held_install()
        self.assertEqual([waited, code], [True, 0], err)
        self.ready()
        self.mutant("                if time.monotonic() >= deadline:", "                if True or time.monotonic() >= deadline:")
        waited, code, err = held_install()
        self.assertEqual([waited, code], [False, 1], err)
        self.assertIn("setup=busy", err)

    def test_archive_path_control(self):
        archive = self.root / "unsafe.tar"
        with tarfile.open(archive, "w") as bundle:
            item = tarfile.TarInfo("../escaped")
            item.size = 1
            bundle.addfile(item, io.BytesIO(b"x"))
        # The extractor itself, not a second implementation.
        module = self.load_module()
        with self.assertRaisesRegex(ValueError, "archive=unsafe-member"):
            module.extract(archive, self.root / "models")
        self.mutant('if path.is_absolute() or ".." in path.parts or not (member.isdir() or member.isfile()):',
                    'if False and (path.is_absolute() or ".." in path.parts or not (member.isdir() or member.isfile())):')
        module = self.load_module()
        # Python's data filter remains a separate dependency guard.
        with self.assertRaises(tarfile.OutsideDestinationError):
            module.extract(archive, self.root / "models")

    def test_status_lock_control(self):
        self.install()
        self.ready()
        with (self.state / "local-setup.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(self.report(), {"tone": "info", "text": "Setting up", "action": False})
        self.mutant("fcntl.flock(lock, fcntl.LOCK_SH | fcntl.LOCK_NB)",
                    "False and fcntl.flock(lock, fcntl.LOCK_SH | fcntl.LOCK_NB)")
        self.install()
        with (self.state / "local-setup.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.ready()

    def load_module(self):
        loader = importlib.machinery.SourceFileLoader("setup_case", str(self.plugin / "setup-local"))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        return module

    def test_probe_delegation_and_control(self):
        module = self.load_module()
        calls = []
        class Judge:
            def run(self, value, artifacts, models, provider, seconds, scope):
                calls.append((artifacts, models, provider, seconds, scope))
        module.probe(Judge(), self.spec, "large", self.data)
        artifacts = [a for a in self.spec["artifacts"] if a["id"] in self.spec["tiers"]["large"]["artifacts"]]
        self.assertEqual(calls, [(artifacts, self.data / "models", "cuda", None, "large")])
        self.mutant('judge.run(value, artifacts, data / "models", provider, None, tier)',
                    'False and judge.run(value, artifacts, data / "models", provider, None, tier)')
        calls.clear()
        self.load_module().probe(Judge(), self.spec, "large", self.data)
        self.assertEqual(calls, [], "probe control must break delegation")

    def test_installed_probe_keeps_selected_roots(self):
        self.config["entry_probe"] = str(REPO / "scripts/fixtures/jarvis-setup/installed-probe.py")
        self.write_config()
        data_alias, state_alias = self.root / "data-alias", self.root / "state-alias"
        (self.root / "state").mkdir(exist_ok=True)
        data_alias.symlink_to(self.root / "data", target_is_directory=True)
        state_alias.symlink_to(self.root / "state", target_is_directory=True)
        # These sentinel values are never credentials or live endpoints.
        self.env.update(API_KEY="must-not-forward", DBUS_SESSION_BUS_ADDRESS="must-not-forward",
                        PULSE_SERVER="must-not-forward")
        original = (PLUGIN / "setup-local").read_text()
        layouts = [
            ("root-alias", data_alias, state_alias),
            ("inner-vgs", self.root / "data", self.root / "state"),
        ]
        for name, data_root, state_root in layouts:
            with self.subTest(layout=name):
                if name == "inner-vgs":
                    # Move the large plugin data without changing its XDG root.
                    for kind in ("data", "state"):
                        path = self.root / kind / "vgshell"
                        target = self.root / ("stored-" + kind)
                        path.rename(target)
                        path.symlink_to(target, target_is_directory=True)
                (self.plugin / "setup-local").write_text(original)
                self.env.update(XDG_DATA_HOME=str(data_root), XDG_STATE_HOME=str(state_root))
                expected = {"models": str(self.data / "models"), "data": str(self.data),
                            "state": str(self.state), "provider": "cpu",
                            "artifacts": self.spec["tiers"]["small"]["artifacts"]}
                (self.data / "probe-expected.json").write_text(json.dumps(expected))
                self.install()
                self.ready()
                observed = json.loads((self.data / "probe-observed.json").read_text())
                self.assertEqual(observed, {key: expected[key] for key in ("models", "data", "state")})
                self.mutant("return env", 'env.pop("XDG_DATA_HOME", None)\n    return env')
                # The real measurement entry now reaches its load lock
                # before inference can report the missing model inputs.
                result = self.install(1)
                self.assertEqual(result.stderr.splitlines()[0].split("=", 2)[:2],
                                 ["jarvis-setup: failed", "probe log"])
                self.assertIn(str(self.home / ".local/share/vgshell/jarvis/local/local-load.lock"),
                              (self.state / "setup-local.log").read_text())
                self.assertFalse((self.state / "local-ready.json").exists())
                report = self.report()
                self.assertEqual([report["tone"], report["action"], report["failure"]["cause"], report["failure"]["tier"]],
                                 ["warning", True, "probe", "small"])
                if name == "inner-vgs":
                    (self.plugin / "setup-local").write_text(original)
                    self.mutant("return env",
                        'env["XDG_DATA_HOME"] = str(data.resolve().parents[2])\n    return env')
                    self.install(1)
                    self.assertFalse((self.state / "local-ready.json").exists())
                    self.assertEqual(self.report()["failure"]["cause"], "probe")

    def test_lock_install_flags_control(self):
        self.install()
        self.ready()
        self.mutant('"--require-hashes", "--only-binary", ":all:", str(requirements)',
                    '"--only-binary", ":all:", str(requirements)')
        self.install(1)
        self.not_ready()

    def test_cancel_and_retry(self):
        self.install()
        self.config["hold_probe"] = True
        self.write_config()
        with subprocess.Popen([sys.executable, "-I", str(self.plugin / "setup-local"), "install", "small"],
                              env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as child:
            # Wait for the private interpreter double to reach inference.
            deadline = time.monotonic() + 10
            while not (self.data / "probe-held").exists():
                self.assertIsNone(child.poll())
                self.assertLess(time.monotonic(), deadline)
                time.sleep(0.01)
            child.send_signal(signal.SIGTERM)
            self.assertEqual(child.wait(timeout=10), 143)
        self.assertFalse((self.state / "local-ready.json").exists())
        self.assertFalse((self.data / "venv").exists())
        self.not_ready()
        # Release the double, not a host interpreter or process by name.
        (self.data / "probe-release").write_text("release")
        self.config["hold_probe"] = False
        self.write_config()
        self.install()
        self.ready()
        # No extra control is needed for Python's process termination.
        # The marker-invalidation and child-exit controls prove the owned
        # readiness mechanism; the OS signal is not a new production guard.

    def tui(self, settings=None, release="off", quiet=True):
        """The window's run inside a VGS tree whose bin/vgshell is a double:
        `plugin settings` answers SETTINGS, and the local voice release asks
        answer as RELEASE has Jarvis do: "off" refuses, as a Jarvis that is
        not running does; "release" lets the lock holder go and answers
        released once it has; "stuck" keeps waiting. QUIET silences the
        header and the error lines. Answers (run, env); each vgshell call is
        a line of env["VGSHELL_CALLS"]."""
        tree = self.root / "vgs"
        (tree / "bin/lib").mkdir(parents=True, exist_ok=True)
        (tree / "bin/lib/tui.sh").write_text('source "' + str(REPO / "bin/lib/tui.sh") + '"\n'
            + ('vgs_tui_header() { :; }\nvgs_tui_error() { :; }\n' if quiet else 'vgs_tui_header() { :; }\n')
            + 'vgs_tui_confirm() { printf "%s\\n" "$1" >>"$QUESTIONS"; return "$CONFIRM"; }\n')
        (tree / "bin/vgshell").write_text("""#!/bin/sh
printf '%s\\n' "$*" >>"$VGSHELL_CALLS"
case "$1 $2 $5 $6" in
  "plugin settings  ") cat "$VGSHELL_SETTINGS" ;;
  "ipc call local-setup begin")
    case "$RELEASE" in
      off) printf 'refused: jarvis=not-running\\n'; exit 69 ;;
      release) : >"$HOLDER_RELEASE"; printf 'waiting\\n' ;;
      *) printf 'waiting\\n' ;;
    esac ;;
  "ipc call local-setup state")
    if [ "$RELEASE" = release ] && [ ! -e "$HOLDER_HELD" ]; then printf 'released\\n'; else printf 'waiting\\n'; fi ;;
  *) exit 2 ;;
esac
""")
        (tree / "bin/vgshell").chmod(0o700)
        (self.root / "settings.json").write_text(json.dumps(settings or {"localTier": "auto"}))
        env = dict(self.env, VGS_TUI_LIB=str(tree / "bin/lib/tui.sh"), VGS_PLUGIN_DIR=str(self.plugin), VGS_PLUGIN_ID="vgs.jarvis",
                   QUESTIONS=str(self.root / "questions"), CONFIRM="0", VGSHELL_CALLS=str(self.root / "vgshell-calls"),
                   VGSHELL_SETTINGS=str(self.root / "settings.json"), RELEASE=release,
                   HOLDER_HELD=str(self.root / "holder-held"), HOLDER_RELEASE=str(self.root / "holder-release"))
        script = self.plugin / "tui/setup-local.sh"
        run = lambda *args: subprocess.run(["bash", str(script), *args],
            env=env, capture_output=True, text=True, check=False, timeout=60)
        return run, env

    def vgshell_calls(self):
        path = self.root / "vgshell-calls"
        return path.read_text().splitlines() if path.exists() else []

    def hold_lock(self):
        """A stand-in for the daemon's local speech sidecar: it holds
        local-setup.lock shared, as local-speech.py's hold() does, until
        the vgshell double's release asks it to let go. Answers its pid."""
        self.state.mkdir(parents=True, exist_ok=True)
        held, release = self.root / "holder-held", self.root / "holder-release"
        release.unlink(missing_ok=True)
        holder = subprocess.Popen([sys.executable, "-I", "-c", """
import fcntl, os, sys, time
from pathlib import Path
lock = open(sys.argv[1], "a")
fcntl.flock(lock, fcntl.LOCK_SH | fcntl.LOCK_NB)
Path(sys.argv[2]).write_text(str(os.getpid()))
while not Path(sys.argv[3]).exists():
    time.sleep(0.05)
Path(sys.argv[2]).unlink()
""", str(self.state / "local-setup.lock"), str(held), str(release)])
        def stop():
            release.touch()
            holder.wait(timeout=10)
        self.addCleanup(stop)
        deadline = time.monotonic() + 10
        while not held.exists():
            self.assertIsNone(holder.poll())
            self.assertLess(time.monotonic(), deadline)
            time.sleep(0.01)
        return holder

    def test_tui_and_control(self):
        # Neutral core presentation double. The actual TUI executes the real
        # installer with the tier it is handed, or the setting's, or none for
        # the pick. The confirmation double records each question and
        # answers CONFIRM.
        run, env = self.tui()
        questions = self.root / "questions"
        script = self.plugin / "tui/setup-local.sh"
        # With no argument and Auto, a PX13-class laptop's pick, small, ends
        # ready; Jarvis is off, so nothing holds the lock.
        self.plant_machine(None, 32000000, 24)
        result = run()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.ready()
        self.assertEqual(self.vgshell_calls(), ["plugin settings vgs.jarvis", "ipc call vgs.jarvis invoke local-setup begin"])
        # The terminal hides diagnostic keys; the setup log keeps them.
        self.assertFalse(any(line.startswith("jarvis-setup:") for line in result.stdout.splitlines()))
        logged = (self.state / "setup-local.log").read_text()
        for key in ("step=runtime", "step=model", "step=probe", "ready=small"):
            self.assertIn("jarvis-setup: " + key, logged)
        self.assertEqual(len(questions.read_text().splitlines()), 1, "a first download asks once")
        # The page's choice reaches the installer, without a settings read.
        self.config["tier"] = "medium"
        self.write_config()
        (self.root / "vgshell-calls").unlink()
        result = run("medium")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.ready()
        self.assertEqual(self.vgshell_calls(), ["ipc call vgs.jarvis invoke local-setup begin"])
        self.assertEqual(len(questions.read_text().splitlines()), 2, "replacing small asks once")
        # A No keeps the ready tier and installs nothing.
        source = script.read_text()
        for name, changed in (("shipped", source),
                              ("control", source.replace('if [[ -n $question ]] && ! vgs_tui_confirm', 'if false && ! vgs_tui_confirm'))):
            with self.subTest(case=name):
                self.assertNotEqual(name == "control", changed == source)
                script.write_text(changed)
                # The double's probe accepts small, so a run that ignores
                # the No replaces medium.
                self.config["tier"] = "small"
                self.write_config()
                env["CONFIRM"] = "1"
                result = run("small")
                env["CONFIRM"] = "0"
                self.assertEqual(self.report()["text"], "Ready: " + ("medium" if name == "shipped" else "small"))
                if name == "shipped":
                    self.assertEqual(result.returncode, 130, result.stdout + result.stderr)
        script.write_text(source)
        self.assertEqual(run("medium", "small").returncode, 2)
        (self.commands / "uv").unlink()
        self.assertEqual(run().returncode, 77)
        source = script.read_text()
        needle = 'vgs_tui_split "$log" jarvis-setup python3 -I "$VGS_PLUGIN_DIR/setup-local" install ${tier:+"$tier"}'
        self.assertEqual(source.count(needle), 1)
        changed = source.replace(needle, ': python3 -I "$VGS_PLUGIN_DIR/setup-local" install ${tier:+"$tier"}')
        self.assertNotEqual(changed, source)
        script.write_text(changed)
        shutil.copyfile(DOUBLE, self.commands / "uv")
        (self.commands / "uv").chmod(0o700)
        (self.state / "local-ready.json").unlink()
        self.assertEqual(run("small").returncode, 0)
        self.not_ready()

    def test_tui_busy_names_the_holder_and_keeps_the_chosen_model(self):
        # The px13 case: Small is ready, the Local voice model setting reads
        # Medium, and a holder that never lets go keeps the lock shared
        # while Jarvis answers nothing, so the install fails busy. A copy
        # with a one-second bound keeps it short.
        self.install()
        self.ready()
        self.mutant("LOCK_WAIT = 30\n", "LOCK_WAIT = 1\n")
        log = self.state / "setup-local.log"
        holder = self.hold_lock()
        run, env = self.tui({"localTier": "medium"}, quiet=False)
        result = run()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        program = Path(f"/proc/{holder.pid}/comm").read_text().strip()
        self.assertIn(f"jarvis-setup: failed=setup=busy holder={holder.pid} program={program}", log.read_text().splitlines())
        # setup-local's own plain line follows its keyed one and reaches the
        # screen; the window then names the way back and the log.
        direct = self.run_command("install", "medium")
        lines = direct.stderr.splitlines()
        self.assertEqual(lines[0], f"jarvis-setup: failed=setup=busy holder={holder.pid} program={program}")
        self.assertFalse(lines[1].startswith("jarvis-setup:"), "the busy refusal carries a plain line")
        self.assertIn(" ".join(lines[1].split()), " ".join(re.sub(r"\x1b\[[0-9;]*m", "", result.stdout + result.stderr).split()))
        # The state root sits outside HOME here, so the log reads in full,
        # wrapped over the terminal's rows.
        screen = "".join(line.strip() for line in re.sub(r"\x1b\[[0-9;]*m", "", result.stderr).splitlines())
        self.assertIn(str(log), screen)
        report = self.report()
        self.assertEqual([report["tone"], report["text"], report["failure"]["cause"], report["failure"]["tier"], report["failure"]["log"]],
                         ["ok", "Ready: small", "busy", "medium", str(log)])
        # With the holder gone, a run with no argument installs Medium, the
        # setting's tier, not the pick, and clears the record.
        holder_release = Path(env["HOLDER_RELEASE"])
        holder_release.touch()
        holder.wait(timeout=10)
        self.config["tier"] = "medium"
        self.write_config()
        result = run()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.ready()
        self.assertFalse((self.state / "local-setup-failed.json").exists())

    def test_tui_releases_the_sidecar_before_it_installs_and_control(self):
        # A replacement over a ready tier whose sidecar holds the lock: the
        # window asks Jarvis first, which lets the holder go, and the
        # install ends ready, not busy.
        self.install()
        self.ready()
        self.config["tier"] = "medium"
        self.write_config()
        self.hold_lock()
        run, env = self.tui(release="release")
        result = run("medium")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.ready()
        calls = self.vgshell_calls()
        self.assertEqual(calls[0], "ipc call vgs.jarvis invoke local-setup begin")
        self.assertIn("ipc call vgs.jarvis invoke local-setup state", calls)
        # Control: a window that does not ask installs over the holder and
        # fails busy.
        self.config["tier"] = "small"
        self.write_config()
        self.hold_lock()
        self.mutant("LOCK_WAIT = 30\n", "LOCK_WAIT = 1\n")
        self.mutant('    answer = ask("begin")\n    if answer', '    answer = ""\n    if answer')
        result = run("small")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(self.report()["failure"]["cause"], "busy")

    def test_tui_release_time_out_installs_nothing_and_logs(self):
        self.install()
        self.ready()
        marker = (self.state / "local-ready.json").read_bytes()
        self.reset_calls()
        # A copy with a one-second bound on the release.
        self.mutant("LOCK_WAIT = 30\n", "LOCK_WAIT = 1\n")
        run, _ = self.tui({"localTier": "medium"}, release="stuck")
        result = run()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("jarvis-setup: failed=setup=busy release=waiting", (self.state / "setup-local.log").read_text().splitlines())
        self.assertEqual([call[0] for call in self.calls() if call[0] != "nvidia-smi"], [], "the install never ran")
        self.assertEqual((self.state / "local-ready.json").read_bytes(), marker)

    def test_release_names_a_stop_only_over_a_ready_tier_and_control(self):
        # Jarvis stops a local voice only when one is ready to run: a first
        # setup says nothing of it, a replacement does.
        module = self.load_module()
        run, env = self.tui(release="release")
        release = lambda: subprocess.run([sys.executable, "-I", str(self.plugin / "setup-local"), "release",
                                          env["VGS_TUI_LIB"].replace("lib/tui.sh", "vgshell")],
                                         env=env, capture_output=True, text=True, check=False, timeout=60)
        for label, ready in (("first setup", False), ("replacement", True)):
            with self.subTest(case=label):
                if ready:
                    self.install()
                    self.ready()
                result = release()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(module.STOPPING in result.stdout.splitlines(), ready, result.stdout)
                self.assertEqual(result.stdout.splitlines()[-1], "jarvis-setup: release=released")
        self.mutant("        if ready is not None:\n            print(STOPPING", "        if True:\n            print(STOPPING")
        (self.state / "local-ready.json").unlink()
        result = release()
        self.assertIn(module.STOPPING, result.stdout.splitlines(), "the control prints the line on a first setup")

    def test_plan_names_the_tier_the_page_offers_and_control(self):
        # The window's header names the tier and size the page's Auto offer
        # names, from the one tier table, on each machine.
        tiers = self.spec["tiers"]
        size = lambda count: f"{round(count / 10**6)} MB" if round(count / 10**6) < 1000 else f"{count / 10**9:.1f} GB"
        def check():
            for label, gpu, ram, threads in (("no graphics card", None, 32000000, 24), ("a large card", 24576, 64000000, 32)):
                self.plant_machine(gpu, ram, threads)
                offers = self.offered()
                pick = offers["pick"]
                named = f"{tiers[pick]['name']} local voice, {size(tiers[pick]['downloadBytes'])}"
                self.assertTrue(offers["choices"][0]["label"].startswith(f"Auto: {tiers[pick]['name']}, "), label)
                result = self.run_command("plan")
                self.assertEqual(result.returncode, 0, result.stderr)
                header, question = result.stdout.split("\n")[:2]
                self.assertIn(named, header, label)
                self.assertIn(named, question, label + ": a first download asks, naming the tier and its size")
        check()
        self.mutant('    target = tier or offers["pick"]', '    target = tier or "small"')
        with self.assertRaises(AssertionError):
            check()
        (self.plugin / "setup-local").write_text((PLUGIN / "setup-local").read_text())
        # The ready tier asks nothing; another asks to replace it.
        self.plant_machine(None, 32000000, 24)
        self.install()
        self.ready()
        self.assertEqual(self.run_command("plan", "small").stdout.split("\n")[1], "")
        replace = self.run_command("plan", "medium").stdout.split("\n")[1]
        self.assertIn(tiers["small"]["name"], replace)
        self.assertIn(tiers["medium"]["name"], replace)

    def test_child_errors_reach_the_log_and_control(self):
        # The log a failure names holds a child's own error line, beside its
        # keyed lines; a progress meter's redraws keep only their last.
        self.config.update(curl_exit=22, curl_stderr="\r  10 %\r  60 %\ncurl: (22) The requested URL returned error: 404\n")
        self.write_config()
        log = self.state / "setup-local.log"
        result = self.install(22)
        self.assertIn("curl: (22) The requested URL returned error: 404", result.stderr, "the screen still shows it")
        lines = log.read_text().splitlines()
        self.assertIn("curl: (22) The requested URL returned error: 404", lines)
        self.assertIn("  60 %", lines)
        self.assertNotIn("  10 %", lines)
        log.unlink()
        self.mutant('"--proto-redir", "=https", "--output", str(partial), "--", url], data, log=log)',
                    '"--proto-redir", "=https", "--output", str(partial), "--", url], data)')
        self.install(22)
        self.assertFalse(log.exists() and "curl: (22)" in log.read_text(), "the control leaves the cause out of the log")

    def test_paths_read_home_relative(self):
        module = self.load_module()
        home = str(self.home)
        old = os.environ.get("HOME")
        os.environ["HOME"] = home
        try:
            for path, want in ((home + "/.local/state/vgshell/jarvis/setup-local.log", "~/.local/state/vgshell/jarvis/setup-local.log"),
                               (home, "~"), (home + "-other/x", home + "-other/x"), ("/var/tmp/x", "/var/tmp/x")):
                self.assertEqual(module.shown(Path(path)), want, path)
        finally:
            if old is None:
                del os.environ["HOME"]
            else:
                os.environ["HOME"] = old

    def test_failure_record_causes(self):
        # Each install that ends without its voice ready records its cause,
        # its tier and the log that names it, and status answers it; a
        # finished install removes it. [label, config, tier, cause, keyed
        # line prefix, a plain line follows]
        for label, config, tier, cause, keyed, plain in (
                ("the download stops", {"curl_exit": 7}, "small", "download", "jarvis-setup: failed=exit code=7 stage=download", True),
                ("the disk fills up", {"curl_exit": 23}, "small", "disk", "jarvis-setup: failed=disk=full file=", True),
                ("a tier no longer offered", {}, "huge", "refused", "jarvis-setup: failed=tier=unknown tier=huge", True)):
            with self.subTest(case=label):
                self.config = {"tier": "small", **config}
                self.write_config()
                result = self.run_command("install", tier)
                self.assertNotEqual(result.returncode, 0)
                lines = result.stderr.splitlines()
                keyed_lines = [line for line in lines if line.startswith(keyed)]
                self.assertEqual(len(keyed_lines), 1, result.stderr)
                after = lines[lines.index(keyed_lines[0]) + 1:]
                self.assertEqual(bool(after) and not after[0].startswith("jarvis-setup:"), plain, result.stderr)
                record = json.loads((self.state / "local-setup-failed.json").read_text())
                self.assertEqual(record, {"cause": cause, "tier": tier, "log": str(self.state / "setup-local.log")})
                report = self.report()
                self.assertEqual([report["tone"], report["action"], report["failure"]["cause"], report["failure"]["tier"]],
                                 ["warning", True, cause, tier])
        self.config = {"tier": "small"}
        self.write_config()
        self.install()
        self.ready()
        self.assertFalse((self.state / "local-setup-failed.json").exists())
        # A full disk anywhere else in the install reads as the disk.
        module = self.load_module()
        self.assertEqual(module.failure_cause(OSError(28, "No space left on device"), "runtime"), "disk")
        self.assertEqual(module.failure_cause(OSError(13, "Permission denied"), "runtime"), "other")

    def test_lock_holders_parse(self):
        # /proc/locks rows with synthetic ids: flock holders of the inode,
        # each once, and neither a waiter, a POSIX lock nor another inode.
        table = "\n".join((
            "1: FLOCK  ADVISORY  READ  4101 00:2a:7001 0 EOF",
            "2: FLOCK  ADVISORY  READ  4102 00:2a:7001 0 EOF",
            "3: -> FLOCK  ADVISORY  WRITE 4103 00:2a:7001 0 EOF",
            "4: POSIX  ADVISORY  WRITE 4104 00:2a:7001 0 EOF",
            "5: FLOCK  ADVISORY  READ  4105 00:2a:7002 0 EOF",
            "6: FLOCK  ADVISORY  READ  4101 00:2a:7001 0 EOF",
            "garbage"))
        self.assertEqual(self.load_module().lock_holders(table, 7001), [4101, 4102])

    # The pick for a machine reading: [label, GPU MiB or None, RAM MiB,
    # threads, tier]. This host and a PX13-class laptop are the issue's
    # machines; the others each prove one input is read.
    PICKS = [
        ("this host: RTX 5090, MemTotal 129444736 kB, 32 threads", 32607, 129444736 / 1024, 32, "large"),
        ("a PX13-class laptop: no NVIDIA GPU, about 32 GB, 24 threads", None, 32000000 / 1024, 24, "small"),
        ("a 4 GiB GPU on a PX13-class laptop is small", 4096, 32000000 / 1024, 24, "small"),
        ("a 6 GiB GPU on a PX13-class laptop is small", 6144, 32000000 / 1024, 24, "small"),
        ("a GPU of twice large's sampled peak and dictation's model is large", 11504, 129444736 / 1024, 32, "large"),
        ("a GPU one MiB below that is not large", 11503, 129444736 / 1024, 32, "medium"),
        ("a large GPU on 24 threads is large", 32607, 129444736 / 1024, 24, "large"),
        ("a large GPU with 16 GiB of RAM is medium", 32607, 16384, 32, "medium"),
        ("128 GB, 32 threads and no GPU is medium", None, 131072, 32, "medium"),
        ("128 GB, 24 threads and no GPU is small", None, 131072, 24, "small"),
        ("12 GiB, 32 threads and no GPU is small", None, 12288, 32, "small"),
    ]

    def assert_picks(self, module):
        for label, gpu, ram, threads, tier in self.PICKS:
            self.assertEqual(module.pick({"gpu": gpu, "ram": ram, "threads": threads}), tier, label)

    def test_pick_reads_each_input_and_controls(self):
        self.assert_picks(self.load_module())
        # Each control keeps the rule's text and drops one input from it.
        original = (self.plugin / "setup-local").read_text()
        for name, needle, replacement in (
                ("GPU memory", 'reading["gpu"] is not None and reading["gpu"] >= GPU_SHARE * (NEED["large"]["gpu"] + DICTATION_GPU)', 'reading["gpu"] is not None'),
                ("dictation's model", '(NEED["large"]["gpu"] + DICTATION_GPU)', 'NEED["large"]["gpu"]'),
                ("RAM for large", '\n            and reading["ram"] >= RAM_SHARE * NEED["large"]["ram"]):', "):"),
                ("RAM for medium", 'if (reading["ram"] >= RAM_SHARE * NEED["medium"]["ram"]\n            and ', "if ("),
                ("threads", '\n            and reading["threads"] is not None and reading["threads"] >= MEDIUM_THREADS):', "):")):
            with self.subTest(control=name):
                self.mutant(needle, replacement)
                with self.assertRaises(AssertionError):
                    self.assert_picks(self.load_module())
                (self.plugin / "setup-local").write_text(original)

    # The characters the closed Local voice field drew of a 58-character
    # automatic label before it cut the rest: scripts/sandbox-shots.sh
    # jarvis-setup on host cachy, 2026-10-11, dark and light. The core's
    # choices judge accepts more, STATUS_LABEL_MAX of shell/Core/PluginLogic.js.
    AUTO_LABEL_FIT = 48

    def assert_auto_label(self, label, row):
        """The automatic row reads the pick's name, description and download
        size, in a line the closed field draws whole."""
        self.assertIn(f": {row['name']}, {row['description']}, ", label)
        self.assertRegex(label, r", [0-9]+(\.[0-9])? (MB|GB)$")
        self.assertLessEqual(len(label), self.AUTO_LABEL_FIT, label)

    def test_choices_follow_the_machine_and_control(self):
        tiers = self.spec["tiers"]
        # Discovery floors: the producer declares both providers.
        cpu = [tier for tier, row in tiers.items() if row["provider"] == "cpu"]
        self.assertIn("small", cpu, "tier discovery is broken: no small CPU tier")
        self.assertIn("large", [tier for tier, row in tiers.items() if row["provider"] == "cuda"])
        tiers["small"]["downloadBytes"] = 796490765
        tiers["medium"]["downloadBytes"] = 1455131612
        (self.plugin / "artifacts.json").write_text(json.dumps(self.spec))
        # [machine, pick, the tiers offered after auto].
        for machine, pick, rest in (
                ((32607, 129444736, 32), "large", [tier for tier in tiers if tier != "large"]),
                ((None, 129444736, 32), "medium", [tier for tier in cpu if tier != "medium"]),
                ((None, 32000000, 24), "small", [tier for tier in cpu if tier != "small"])):
            with self.subTest(pick=pick):
                self.plant_machine(*machine)
                offered = self.offered()
                self.assertEqual([offered["pick"], offered["ready"]], [pick, None])
                self.assertEqual(offered["choices"][0]["value"], "auto")
                self.assert_auto_label(offered["choices"][0]["label"], tiers[pick])
                self.assertEqual([row["value"] for row in offered["choices"][1:]], rest)
                for row in offered["choices"]:
                    # The core's choices judge: a printable line of at most 60 characters.
                    self.assertTrue(row["label"].isprintable() and 0 < len(row["label"]) <= 60, row)
                for row in offered["choices"][1:]:
                    self.assertTrue(row["label"].startswith(tiers[row["value"]]["name"] + ": "), row)
                    self.assertRegex(row["label"], r", [0-9]+(\.[0-9])? (MB|GB)$")
                labels = {row["value"]: row["label"] for row in offered["choices"]}
                self.assertTrue(labels.get("small", " 796 MB").endswith(" 796 MB"), labels)
                self.assertTrue(labels.get("medium", " 1.5 GB").endswith(" 1.5 GB"), labels)
        self.assertIn(["nvidia-smi", "--query-gpu=memory.total", "--format=csv,noheader,nounits"], self.calls())
        # Controls on the host reading: the name alone, then a description
        # that makes the label one character longer than the field draws.
        self.plant_machine(32607, 129444736, 32)
        longest = self.offered()["choices"][0]["label"]
        self.assert_auto_label(longest, tiers["large"])
        original = (self.plugin / "setup-local").read_text()
        self.mutant("label(f\"Auto: {value['tiers'][best]['name']}, \", value[\"tiers\"][best])",
                    "\"Auto: \" + value[\"tiers\"][best][\"name\"]")
        with self.assertRaises(AssertionError):
            self.assert_auto_label(self.offered()["choices"][0]["label"], tiers["large"])
        (self.plugin / "setup-local").write_text(original)
        fitted = (self.plugin / "artifacts.json").read_text()
        tiers["large"]["description"] += "x" * (self.AUTO_LABEL_FIT + 1 - len(longest))
        (self.plugin / "artifacts.json").write_text(json.dumps(self.spec))
        over = self.offered()["choices"][0]["label"]
        self.assertEqual(len(over), self.AUTO_LABEL_FIT + 1)
        with self.assertRaises(AssertionError):
            self.assert_auto_label(over, tiers["large"])
        (self.plugin / "artifacts.json").write_text(fitted)
        self.plant_machine(None, 32000000, 24)
        # The ready tier, as status verifies it.
        self.config["tier"] = "small"
        self.write_config()
        self.install()
        self.assertEqual(self.offered()["ready"], "small")
        self.mutant('return reading["gpu"] is not None', "return True")
        self.assertIn("large", [row["value"] for row in self.offered()["choices"]])

    def test_install_without_tier_installs_the_pick_and_control(self):
        # The double's probe asserts the tier it is run for.
        for machine, tier in (((32607, 129444736, 32), "large"), ((None, 32000000, 24), "small")):
            with self.subTest(tier=tier):
                self.plant_machine(*machine)
                self.config["tier"] = tier
                self.write_config()
                self.install(tier=False)
                self.ready()
        self.plant_machine(32607, 129444736, 32)
        self.config["tier"] = "large"
        self.write_config()
        self.mutant("pick(reading) if args.tier is None else args.tier", '"small" if args.tier is None else args.tier')
        self.install(1, tier=False)
        self.not_ready()

    def test_gpu_refusal_keeps_ready_and_control(self):
        self.install()
        self.ready()
        marker = (self.state / "local-ready.json").read_bytes()
        (self.data / "calls.jsonl").unlink()
        self.config.update(tier="large", gpu_exit=9)
        self.write_config()
        result = self.install(1)
        self.assertEqual(result.stderr.splitlines()[0], "jarvis-setup: failed=gpu=unavailable tier=large")
        self.assertEqual([call[0] for call in self.calls()], ["nvidia-smi"])
        self.assertEqual((self.state / "local-ready.json").read_bytes(), marker)
        self.assertEqual(self.report(), {"tone": "ok", "text": "Ready: small", "action": False,
            "failure": {"cause": "unavailable", "tier": "large", "log": str(self.state / "setup-local.log"),
                        "text": self.spec["tiers"]["large"]["name"] + " is not set up"}})
        self.mutant("if not runnable(provider, reading):", "if False and not runnable(provider, reading):")
        self.install()
        self.ready()

    def test_disk_refusal_and_control(self):
        self.install()
        (self.data / "calls.jsonl").unlink()
        self.spec["tiers"]["small"]["downloadBytes"] = 10**18
        (self.plugin / "artifacts.json").write_text(json.dumps(self.spec))
        result = self.install(1)
        self.assertRegex(result.stderr.splitlines()[0], r"^jarvis-setup: failed=disk=insufficient "
                         r"need=[0-9]+ free=[0-9]+ path=" + re.escape(str(self.data)) + "$")
        # The machine reading's GPU query is the one child before the refusal.
        self.assertEqual([call[0] for call in self.calls()], ["nvidia-smi"])
        self.assertTrue((self.state / "local-ready.json").exists())
        self.mutant("if free < need:", "if False and free < need:")
        self.install()
        self.ready()

    def test_probe_failure_reports_plainly_and_controls(self):
        engine = 'Traceback (most recent call last):\n  File "probe"\nRuntimeError: fixture provider\n'
        self.config.update(probe_exit=1, probe_stderr=engine)
        self.write_config()
        log = self.state / "setup-local.log"
        original = (self.plugin / "setup-local").read_text()
        result = self.install(1)
        self.assertNotIn("Traceback", result.stderr)
        self.assertIn(engine, log.read_text())
        lines = result.stderr.splitlines()
        self.assertEqual(lines[0], f"jarvis-setup: failed=probe log={log}")
        for name in ("venv", "models", "requirements-cuda.lock"):
            self.assertFalse((self.data / name).exists(), name)
        # What remains is reported: every regular file below the data root.
        kept = sum(path.lstat().st_size for path in self.data.rglob("*")
                   if path.is_file() and not path.is_symlink())
        self.assertGreater(kept, 0)
        self.assertEqual([line for line in lines if line.startswith("jarvis-setup: kept=")],
                         [f"jarvis-setup: kept={self.data} bytes={kept}"])
        # Only a CUDA tier is told to fall back to a tier that runs on any computer.
        fallback = "choose a model that runs on any computer"
        self.assertNotIn(fallback, result.stderr)
        self.config["tier"] = "large"
        self.write_config()
        result = self.install(1)
        self.assertEqual(result.stderr.splitlines()[0], f"jarvis-setup: failed=probe log={log}")
        self.assertIn(fallback, result.stderr)
        self.config["tier"] = "small"
        self.write_config()
        self.mutant('if provider == "cuda" else ""', 'if True or provider == "cuda" else ""')
        self.assertIn(fallback, self.install(1).stderr)
        (self.plugin / "setup-local").write_text(original)
        self.mutant('"probe", tier], data, offline=True, stderr=output, stdout=reading)',
                    '"probe", tier], data, offline=True, stdout=reading)')
        self.assertIn("Traceback", self.install(1).stderr)
        (self.plugin / "setup-local").write_text(original)
        self.mutant("except BaseException:\n            remove_runtime(data)",
                    "except BaseException:\n            False and remove_runtime(data)")
        self.install(1)
        self.assertTrue((self.data / "venv").exists(), "cleanup control did not reach the runtime")

    def test_missing_setup_requirement_and_control(self):
        script = self.plugin / "tui/setup-local.sh"
        source = script.read_text()
        # The presentation boundary records all attempted setup work. Every
        # executable in PATH is a stand-in and none reaches an installer.
        commands = self.root / "tui-commands"
        commands.mkdir()
        required = ("gum", "uv", "curl", "unshare", "python3")
        declared = {row["command"] for row in json.loads(
            (self.plugin / "manifest.json").read_text())["requirements"]}
        self.assertTrue(set(required) <= declared)
        for tool in required:
            path = commands / tool
            path.write_text('#!/bin/sh\nprintf "%s\\n" called >>"$SETUP_CALLS"\nexit 99\n')
            path.chmod(0o700)
        # The library's log helpers make the log's folder; no installer.
        for tool in ("mkdir", "dirname"):
            (commands / tool).symlink_to(shutil.which(tool))
        calls = self.root / "setup-calls"
        library = self.root / "setup-library"
        library.write_text((REPO / "bin/lib/tui.sh").read_text() +
            '\nvgs_tui_header() { printf "header\\n" >>"$SETUP_CALLS"; }\n'
            'vgs_tui_choose() { printf "choose\\n" >>"$SETUP_CALLS"; return 99; }\n')
        env = dict(self.env, PATH=str(commands), VGS_TUI_LIB=str(library),
                   VGS_PLUGIN_DIR=str(self.plugin), SETUP_CALLS=str(calls))
        def run():
            return subprocess.run(["/bin/bash", str(script)], env=env,
                capture_output=True, text=True, check=False, timeout=30)
        log = self.state / "setup-local.log"
        def assert_withheld(tool):
            log.unlink(missing_ok=True)
            result = run()
            self.assertEqual(result.returncode, 77, result.stderr)
            self.assertEqual(log.read_text().splitlines(), ["jarvis-setup: command=missing name=" + tool])
            self.assertFalse(any(line.startswith("jarvis-setup:") for line in result.stderr.splitlines()))
            self.assertEqual(result.stdout, "")
            self.assertFalse(calls.exists(), "missing requirement started setup")
        for tool in required:
            with self.subTest(tool=tool):
                path = commands / tool
                original = path.read_text()
                path.unlink()
                assert_withheld(tool)
                path.write_text(original)
                path.chmod(0o700)
        needle = 'command -v "$tool" >/dev/null || missing+=("$tool")'
        self.assertEqual(source.count(needle), 1)
        changed = source.replace(needle, 'true || missing+=("$tool")')
        self.assertNotEqual(changed, source)
        self.assertFalse(script.is_symlink())
        script.write_text(changed)
        (commands / "gum").unlink()
        with self.assertRaises(AssertionError):
            assert_withheld("gum")
        self.assertTrue(calls.exists(), "guard control never started setup")

    def test_install_tree_namespace_result_controls(self):
        # Copy the real installation assertions, namespace consumer and closing
        # verdict into a private script. Omit unrelated package/control rows.
        # Both effectful producers are explicit local doubles inside J09.
        tree = self.root / "install-source"
        (tree / "scripts/lib").mkdir(parents=True)
        (tree / "packaging").mkdir()
        helper = tree / "scripts/lib/jarvis-env.sh"
        helper.write_text('#!/usr/bin/env bash\nprintf "jarvis-env: status=not-measured reason=namespaces-unavailable\\n" >&2\nexit 77\n')
        helper.chmod(0o700)
        installer = tree / "packaging/install-system.sh"
        source = (REPO / "scripts/test-install-tree.sh").read_text()

        def section(text, start, end=None):
            self.assertEqual(text.count(start), 1, start)
            result = text.split(start, 1)[1]
            if end is not None:
                self.assertEqual(result.count(end), 1, end)
                result = result.split(end, 1)[0]
            return start + result

        functions = section(source, "ok() {", "voice_command=")
        install = section(source, 'run_capture "$tmp/install.out"', 'run_capture "$tmp/check.out"')
        readiness = section(source, 'setup_standins="$tmp/setup-standins"', 'private_node=')
        ending = section(source, 'if [[ $failures -gt 0 ]]; then')
        program = self.root / "install-check.sh"
        env = dict(self.env, FIXTURE_TREE=str(tree), FIXTURE_SCRATCH=str(self.root))

        def run(changed=None, broken_install=False, generator_missing=False):
            installer.write_text('#!/usr/bin/env bash\n' + ('exit 1\n' if broken_install else
                'printf "install-system: ok prefix=/usr root=%s/usr\\n" "$DESTDIR"\n'))
            installer.chmod(0o700)
            program.write_text('set -euo pipefail\nrepo="$FIXTURE_TREE"\ntmp="$FIXTURE_SCRATCH"\n'
                               'dest="$tmp/install"\nfailures=0\nunavailable=false\n' +
                               'generator_missing=%s\n' % ("true" if generator_missing else "false") +
                               functions + install + (readiness if changed is None else changed[0]) +
                               (ending if changed is None else changed[1]))
            return subprocess.run(["bash", str(program)], env=env, capture_output=True,
                                  text=True, check=False, timeout=30)

        result = run()
        self.assertEqual(result.returncode, 77, result.stdout + result.stderr)
        self.assertIn("test-install-tree: status=not-measured reason=jarvis-isolation", result.stdout)
        self.assertNotIn("test-install-tree: ok", result.stdout)
        self.assertNotIn("  FAIL", result.stdout)
        needle = "if [[ $unavailable == true ]]; then"
        self.assertEqual(ending.count(needle), 1)
        changed = ending.replace(needle, "if false && [[ $unavailable == true ]]; then")
        self.assertNotEqual(changed, ending)
        result = run((readiness, changed))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("test-install-tree: ok", result.stdout)
        needle = "if [[ $status == 77 ]]; then"
        self.assertEqual(readiness.count(needle), 1)
        changed = readiness.replace(needle, "if false && [[ $status == 77 ]]; then")
        self.assertNotEqual(changed, readiness)
        result = run((changed, ending))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("installed local readiness reads without source-tree files", result.stdout)
        # The suite's real installation assertion, not a planted counter.
        result = run(broken_install=True)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("  FAIL  the installer succeeds into a staged /usr prefix", result.stdout)
        self.assertNotIn("test-install-tree: status=not-measured reason=jarvis-isolation", result.stdout)
        needle = "if [[ $failures -gt 0 ]]; then"
        self.assertEqual(ending.count(needle), 1)
        changed = ending.replace(needle, "if false && [[ $failures -gt 0 ]]; then")
        self.assertNotEqual(changed, ending)
        result = run((readiness, changed), broken_install=True)
        self.assertEqual(result.returncode, 77, result.stdout + result.stderr)
        self.assertIn("  FAIL  the installer succeeds into a staged /usr prefix", result.stdout)
        # A host without the autostart generator, the namespace readiness
        # left out so unavailable stays false: the autostart branch alone
        # turns the verdict into 77.
        result = run(("", ending), generator_missing=True)
        self.assertEqual(result.returncode, 77, result.stdout + result.stderr)
        self.assertIn("test-install-tree: status=not-measured reason=autostart-generator-missing", result.stdout)
        self.assertNotIn("test-install-tree: ok", result.stdout)
        needle = "  [[ $unavailable == true ]] || exit 77\n"
        self.assertEqual(ending.count(needle), 1)
        changed = ending.replace(needle, "")
        self.assertNotEqual(changed, ending)
        result = run(("", changed), generator_missing=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("test-install-tree: ok", result.stdout)

    # The cloned voice. A large tier is ready first: the clone runs beside it.
    def large(self):
        self.config["tier"] = "large"
        self.write_config()
        self.install()
        self.ready()
        self.reset_calls()

    def clone(self, *args, stdin=None):
        return subprocess.run([sys.executable, "-I", str(self.plugin / "setup-local"), "clone", *args],
                              env=self.env, input=stdin, capture_output=True, check=False, timeout=30)

    def clone_status(self):
        result = self.clone("status")
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def tone(self, seconds, amplitude=0.5):
        return b"".join(int(amplitude * 32767 * ((i // 50) % 2 * 2 - 1)).to_bytes(2, "little", signed=True)
                        for i in range(int(seconds * 24000)))

    def tree(self):
        """Every file below the scratch world's state and data roots, with its bytes."""
        return {str(path): path.read_bytes() for root in (self.root / "state", self.root / "data")
                for path in root.rglob("*") if path.is_file()}

    def tree_without_clone_log(self):
        return {path: data for path, data in self.tree().items() if not path.endswith("/clone-voice.log")}

    def clone_tui(self, script, answers, source=None):
        """Run a clone TUI with a presentation double: each confirmation
        takes the next of ANSWERS, yes once they run out."""
        library, answered = self.root / "clone-lib.sh", self.root / "answers"
        library.write_text('vgs_tui_header() { :; }\nvgs_tui_clear() { :; }\nvgs_tui_text() { :; }\nvgs_tui_step() { :; }\nvgs_tui_success() { :; }\n'
                           'vgs_tui_error() { :; }\nvgs_tui_split() { shift 2; "$@"; }\n'
                           'vgs_tui_cancelled() { printf "%s\\n" "$*"; }\n'
                           'vgs_tui_confirm() { local answers; mapfile -t answers <"$ANSWERS"; '
                           'printf "%s\\n" "${answers[@]:1}" >"$ANSWERS"; [[ ${answers[0]:-yes} == yes ]]; }\n')
        answered.write_text("".join(answer + "\n" for answer in answers))
        path = self.plugin / "tui" / script
        if source is not None:
            path.write_text(source)
        env = dict(self.env, VGS_TUI_LIB=str(library), VGS_PLUGIN_DIR=str(self.plugin), ANSWERS=str(answered),
                   UV_CACHE_DIR=str(self.data / "cache"))
        return subprocess.run(["bash", str(path)], env=env, capture_output=True, text=True, check=False, timeout=60)

    def clone_tui_real(self, source=None, extra=None):
        """Run the setup TUI through the shipped presentation library."""
        path = self.plugin / "tui/clone-voice.sh"
        if source is not None:
            path.write_text(source)
        env = dict(self.env, VGS_TUI_LIB=str(REPO / "bin/lib/tui.sh"), VGS_PLUGIN_DIR=str(self.plugin),
                   VGS_TUI_UNATTENDED="1", UV_CACHE_DIR=str(self.data / "cache"))
        if extra:
            env.update(extra)
        return subprocess.run(["bash", "-c", "umask \"${UMASK:-077}\"; exec \"$1\"", "clone-tui", str(path)],
                              env=env, capture_output=True, text=True, check=False, timeout=60)

    def recording_text_at_edge(self, stdout):
        """Whether every line the Recording step shows before its question,
        three or more with the sample's wrap, starts at the library's
        content edge, column 3, read as the 80 columns a run with no
        terminal draws."""
        plain = [re.sub(r"\x1b\[[0-9;:]*m", "", line) for line in stdout.splitlines()]
        start = plain.index("   Recording") + 1
        end = next(i for i, line in enumerate(plain) if "Start recording?" in line)
        shown = [line for line in plain[start:end] if line]
        return len(shown) >= 3 and all(re.match(r"   \S", line) for line in shown)

    @staticmethod
    def cleared_after_consent(stdout):
        """Whether the screen clears after the second consent question and
        before the download step."""
        clear = stdout.find("\x1b[H\x1b[2J")
        return stdout.find("permission?") < clear < stdout.find("Downloading the model")

    def clone_tui_pty(self, source, gum_exit="1", closed=False, columns=80):
        """Run the setup TUI on a pseudo-terminal; when CLOSED, followed by
        the library's closing prompt for its exit code, as bin/vgshell-tui
        present ends a floating terminal (scripts/test-vgshell-tui.sh holds
        the presenter to that call)."""
        path = self.plugin / "tui/clone-voice.sh"
        path.write_text(source)
        env = dict(self.env, VGS_TUI_LIB=str(REPO / "bin/lib/tui.sh"), VGS_PLUGIN_DIR=str(self.plugin),
                   UV_CACHE_DIR=str(self.data / "cache"), GUM_CONFIRM_EXIT=gum_exit)
        pty_fd, slave = pty.openpty()
        cmd = shlex.join(["bash", str(path)])
        if closed:
            cmd = shlex.join(["bash", "-c", 'code=0; bash "$1" || code=$?; source "$VGS_TUI_LIB"; '
                              'vgs_tui_close_prompt "$code"; exit "$code"', "closed", str(path)])
        script_bin = shutil.which("script", path="/usr/bin:/bin")
        self.assertIsNotNone(script_bin)
        # Keep long temporary log paths on one row when the test requests it.
        fcntl.ioctl(pty_fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, columns, 0, 0))
        proc = subprocess.Popen([script_bin, "-qec", cmd, "/dev/null"], env=env, stdin=slave, stdout=slave, stderr=slave,
                                text=False, close_fds=True)
        os.close(slave)
        return proc, pty_fd

    def read_pty_until(self, proc, pty_fd, needle, timeout=5):
        out = b""
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            ready, _, _ = select.select([pty_fd], [], [], 0.05)
            if ready:
                try:
                    chunk = os.read(pty_fd, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                out += chunk
                if needle.encode() in out:
                    return out.decode(errors="replace")
            if proc.poll() is not None:
                break
        return out.decode(errors="replace")

    def read_pty_rest(self, proc, pty_fd, timeout=5):
        out = b""
        end = time.monotonic() + timeout
        while proc.poll() is None and time.monotonic() < end:
            ready, _, _ = select.select([pty_fd], [], [], 0.05)
            if ready:
                try:
                    out += os.read(pty_fd, 4096)
                except OSError:
                    break
        try:
            proc.wait(timeout=max(0.1, end - time.monotonic()))
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        while True:
            ready, _, _ = select.select([pty_fd], [], [], 0)
            if not ready:
                break
            try:
                chunk = os.read(pty_fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            out += chunk
        return out.decode(errors="replace")

    # One row per consent question: a No there, a planted Yes on the other.
    CONSENT = [
        ("read the use text", ["no", "yes"], 'vgs_tui_confirm "Have you read Resemble AI\'s text above?" || declined'),
        ("own voice or permission", ["yes", "no"],
         'vgs_tui_confirm "Is the voice you will record your own, or do you have the speaker\'s permission?" || declined'),
    ]

    def test_clone_consent_rows_and_controls(self):
        self.large()
        source = (PLUGIN / "tui/clone-voice.sh").read_text()
        for name, answers, gate in self.CONSENT:
            with self.subTest(question=name):
                before = self.tree_without_clone_log()
                result = self.clone_tui("clone-voice.sh", answers, source)
                self.assertEqual(result.returncode, 130, result.stdout + result.stderr)
                self.assertEqual(self.calls(), [], "a No downloads and runs nothing")
                self.assertEqual(self.tree_without_clone_log(), before, "a No writes no model or recording")
                self.assertEqual((self.state / "clone-voice.log").read_text(), "")
                # The control drops this question's gate and keeps its text.
                self.assertEqual(source.count(gate), 1)
                control = source.replace(gate, gate.replace("|| declined", "|| true"))
                result = self.clone_tui("clone-voice.sh", answers, control)
                self.assertNotEqual(self.tree(), before, "must-fail control stayed green: " + name)
                self.assertTrue(any(call[0] == "curl" for call in self.calls()))
                self.clone("remove")
                shutil.rmtree(self.data / "clone")
                (self.state / "clone-setup.log").unlink(missing_ok=True)
                (self.state / "clone-setup.lock").unlink(missing_ok=True)
                self.reset_calls()
        (self.plugin / "tui/clone-voice.sh").write_text(source)

    def test_clone_consent_no_waits_for_a_key_and_control(self):
        self.large()
        self.reset_calls()
        source = (PLUGIN / "tui/clone-voice.sh").read_text()
        before = self.tree_without_clone_log()
        proc, pty_fd = self.clone_tui_pty(source)
        try:
            output = self.read_pty_until(proc, pty_fd, "Press any key to close")
            self.assertIn("Nothing was downloaded or stored.", output)
            self.assertIn("Press any key to close", output)
            self.assertIsNone(proc.poll(), "the TUI exited before the user could read the No sentence")
            os.write(pty_fd, b"x")
            output += self.read_pty_rest(proc, pty_fd)
            self.assertEqual(proc.returncode, 130, output)
        finally:
            os.close(pty_fd)
            if proc.poll() is None:
                proc.kill()
                proc.wait()
        self.assertEqual([call[0] for call in self.calls() if call[0] == "curl"], [])
        self.assertEqual(self.tree_without_clone_log(), before, "a No writes no model or recording")

        control = source.replace('vgs_tui_cancelled "Nothing was downloaded or stored."', 'printf "Nothing was downloaded or stored.\\n"')
        self.assertNotEqual(control, source)
        proc, pty_fd = self.clone_tui_pty(control)
        try:
            output = self.read_pty_until(proc, pty_fd, "Press any key to close", timeout=1)
            output += self.read_pty_rest(proc, pty_fd)
            self.assertNotIn("Press any key to close", output)
            self.assertEqual(proc.returncode, 130)
        finally:
            os.close(pty_fd)
            if proc.poll() is None:
                proc.kill()
                proc.wait()

    def test_clone_tier_refusal_closes_without_failed_and_control(self):
        """Without the Large tier the setup closes on the neutral prompt
        with no log path; the control sends the refusal down the failure
        path, which names the task failure and the log."""
        self.install()
        self.ready()
        source = (PLUGIN / "tui/clone-voice.sh").read_text()

        def closed(text):
            proc, pty_fd = self.clone_tui_pty(text, closed=True, columns=240)
            try:
                output = self.read_pty_until(proc, pty_fd, "Press any key to close")
                self.assertIsNone(proc.poll(), "the window closed before its key: " + output)
                os.write(pty_fd, b"x")
                output += self.read_pty_rest(proc, pty_fd)
            finally:
                os.close(pty_fd)
                if proc.poll() is None:
                    proc.kill()
                    proc.wait()
            return proc.returncode, output

        code, output = closed(source)
        self.assertEqual(code, 69, output)
        self.assertIn("jarvis-setup: refused=clone=needs-large-tier",
                      (self.state / "clone-voice.log").read_text().splitlines())
        self.assertIn("Press any key to close", output)
        self.assertNotIn("The task failed.", output)
        self.assertNotIn("clone-voice.log", output)
        control = source.replace("  69) exit 69 ;;\n", "  69) details; exit 1 ;;\n")
        self.assertNotEqual(control, source)
        code, output = closed(control)
        self.assertEqual(code, 1, output)
        self.assertIn("The task failed.", output, "must-fail control: the failure path names the task failure")
        self.assertIn("clone-voice.log", output, "must-fail control: the failure path named its log")
        (self.plugin / "tui/clone-voice.sh").write_text(source)

    def test_clone_tui_terminal_text_and_controls(self):
        source = (PLUGIN / "tui/clone-voice.sh").read_text()
        self.large()
        result = self.clone_tui_real(source)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertFalse(any(line.startswith("jarvis-setup:") for line in output.splitlines()), output)
        row = next(a for a in self.spec["artifacts"] if a["id"] == "chatterbox")
        count = len(row["files"])
        self.assertIn(f"Downloading the model: file 1 of {count}.", output)
        self.assertIn(f"Downloading the model: file {count} of {count}.", output)
        recording = "Recording now: read the text aloud. Recording stops after 10 seconds."
        probe = "Testing the cloned voice on this computer."
        self.assertIn(recording, output)
        self.assertLess(output.index(recording), output.index(probe))
        log = self.state / "clone-voice.log"
        logged = log.read_text().splitlines()
        self.assertTrue(any(line.startswith("jarvis-setup: step=runtime") for line in logged))
        self.assertTrue(any(f"index=1 count={count}" in line for line in logged))
        self.assertTrue(any(line.startswith("jarvis-setup: clone=installed") for line in logged))
        self.assertTrue(any(line.startswith("jarvis-setup: step=probe") for line in logged))
        self.assertTrue(any(line.startswith("jarvis-setup: clone=ready") for line in logged))
        self.assertTrue(self.recording_text_at_edge(result.stdout), result.stdout)
        # The download starts on a cleared screen after both consents, so
        # the logo cannot be left part way off the window's top.
        self.assertTrue(self.cleared_after_consent(result.stdout), result.stdout)
        uncleared = source.replace("\nvgs_tui_clear\n", "\n:\n")
        self.assertNotEqual(uncleared, source)
        self.assertFalse(self.cleared_after_consent(self.clone_tui_real(uncleared).stdout),
                         "must-fail control: the download started under the consent text")
        hand_printed = source.replace("vgs_tui_text '\"The quick", "printf '%s\\n' '\"The quick")
        self.assertNotEqual(hand_printed, source)
        self.assertFalse(self.recording_text_at_edge(self.clone_tui_real(hand_printed).stdout),
                         "must-fail control: the sample printed past the library kept the edge")

        direct = source.replace(
            'vgs_tui_split "$log" jarvis-setup python3 -I "$VGS_PLUGIN_DIR/setup-local" clone install',
            'python3 -I "$VGS_PLUGIN_DIR/setup-local" clone install')
        self.assertNotEqual(direct, source)
        result = self.clone_tui_real(direct)
        self.assertTrue(any(line.startswith("jarvis-setup:") for line in (result.stdout + result.stderr).splitlines()),
                        "must-fail control: split did not hide keyed lines")

        no_recording_line = source.replace(
            'vgs_tui_step "Recording now: read the text aloud. Recording stops after $seconds seconds."',
            ':')
        self.assertNotEqual(no_recording_line, source)
        result = self.clone_tui_real(no_recording_line)
        self.assertNotIn(recording, result.stdout + result.stderr, "must-fail control: recording line stayed visible")

        self.config["curl_exit"] = 1
        self.write_config()
        shutil.rmtree(self.data / "clone", ignore_errors=True)
        result = self.clone_tui_real(source)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 1)
        self.assertFalse(any(line.startswith("jarvis-setup:") for line in output.splitlines()), output)
        self.assertNotIn("exit code", output)
        self.assertIn("Removed the cloned voice's downloads and runtime.", output)
        self.assertIn("The details are in", output)

        self.config.pop("curl_exit")
        self.config["tier"] = "small"
        self.write_config()
        self.install()
        self.ready()
        self.reset_calls()
        result = self.clone_tui_real(source)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 69)
        self.assertIn("The cloned voice runs beside the Large local voice model", output)
        self.assertNotIn("Have you read", output)
        self.assertNotIn("Downloading the model", output)
        late_check = source.replace('python3 -I "$VGS_PLUGIN_DIR/setup-local" clone check', "true")
        self.assertNotEqual(late_check, source)
        result = self.clone_tui_real(late_check)
        late_output = result.stdout + result.stderr
        self.assertIn("Have you read", late_output, "must-fail control: the question was not asked before refusal")
        self.assertIn("Downloading the model", late_output, "must-fail control: the download heading was not shown before refusal")
        (self.plugin / "tui/clone-voice.sh").write_text(source)

    def test_clone_tui_keeps_state_private_and_control(self):
        source = (PLUGIN / "tui/clone-voice.sh").read_text()
        shutil.rmtree(self.state, ignore_errors=True)
        env = {"UMASK": "022"}
        result = self.clone_tui_real(source, env)
        self.assertEqual(result.returncode, 69, result.stdout + result.stderr)
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((self.state / "clone-voice.log").stat().st_mode), 0o600)
        control = source.replace("# The recording log and state directory hold a user's voice setup evidence.\numask 077\n", "")
        self.assertNotEqual(control, source)
        shutil.rmtree(self.state, ignore_errors=True)
        shutil.rmtree(self.data / "clone", ignore_errors=True)
        result = self.clone_tui_real(control, env)
        self.assertEqual(result.returncode, 69, result.stdout + result.stderr)
        self.assertNotEqual(stat.S_IMODE(self.state.stat().st_mode), 0o700,
                            "must-fail control: state root stayed private without the umask")

    def test_clone_setup_recording_and_remove(self):
        self.large()
        self.assertEqual(self.clone_status(), {"tone": "info", "text": "Not set up", "action": "setup",
                                               "recording": False, "tierReady": True})
        result = self.clone_tui("clone-voice.sh", ["yes", "yes"])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        row = next(a for a in self.spec["artifacts"] if a["id"] == "chatterbox")
        self.assertEqual([call[-1] for call in self.calls() if call[0] == "curl"],
                         [row["baseUrl"] + name for name in row["files"]])
        reference = self.state / "voice-reference.wav"
        info = reference.lstat()
        self.assertEqual((stat.S_ISREG(info.st_mode), stat.S_IMODE(info.st_mode)), (True, 0o600))
        self.assertFalse(reference.resolve().is_relative_to(self.plugin.resolve()))
        self.assertEqual((self.data / "clone-probed").read_bytes(), reference.read_bytes(), "the probe read the recording")
        with wave.open(str(reference)) as wav:
            self.assertEqual((wav.getnchannels(), wav.getsampwidth(), wav.getframerate(), wav.getnframes()),
                             (1, 2, 24000, 10 * 24000))
        # One environment holds one onnxruntime: the projection swaps that pin alone.
        local = (PLUGIN / "requirements-local.lock").read_text().splitlines()
        projected = (self.data / "clone/requirements-clone.lock").read_text().splitlines()
        self.assertEqual([line for line in projected if line not in local],
                         [line for line in (PLUGIN / "requirements-clone.lock").read_text().splitlines()
                          if line.startswith("onnxruntime-gpu==")])
        self.assertEqual([line for line in local if line not in projected],
                         [line for line in local if line.startswith("onnxruntime==")])
        self.assertEqual(self.clone_status(), {"tone": "ok", "text": "Ready", "action": "remove",
                                               "recording": True, "tierReady": True})
        # Remove deletes the recording and the marker; the model stays.
        result = self.clone_tui("clone-voice-remove.sh", ["yes"])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(reference.exists())
        self.assertFalse((self.state / "clone-ready.json").exists())
        self.assertTrue((self.data / "clone/models/tokenizer.json").is_file())
        self.assertEqual(self.clone_status()["action"], "setup")
        # A No keeps it.
        self.clone_tui("clone-voice.sh", ["yes", "yes"])
        self.assertEqual(self.clone_tui("clone-voice-remove.sh", ["no"]).returncode, 130)
        self.assertTrue(reference.exists())
        needle = '        (state / REFERENCE).unlink(missing_ok=True)\n    print("jarvis-setup: clone=removed"'
        self.mutant(needle, '    print("jarvis-setup: clone=removed"')
        self.clone_tui("clone-voice-remove.sh", ["yes"])
        self.assertTrue(reference.exists(), "must-fail control: the recording survives a Remove")

    def test_clone_status_needs_row_and_recording_and_controls(self):
        self.large()
        self.assertEqual(self.clone_tui("clone-voice.sh", ["yes", "yes"]).returncode, 0)
        self.assertEqual(self.clone_status()["tone"], "ok")
        reference = self.state / "voice-reference.wav"
        model = self.data / "clone/models/onnx/language_model_fp16.onnx_data"
        original = model.read_bytes()
        # The row must verify: a corrupt model file reads not ready.
        model.write_bytes(b"corrupt")
        self.assertEqual(self.clone_status()["tone"], "warning")
        model.write_bytes(original)
        self.assertEqual(self.clone_status()["tone"], "ok")
        # The recording must exist as this user's 0600 file.
        recording = reference.read_bytes()
        reference.unlink()
        self.assertEqual(self.clone_status(), {"tone": "info", "text": "Not set up", "action": "setup",
                                               "recording": False, "tierReady": True})
        reference.write_bytes(recording)
        reference.chmod(0o644)
        self.assertNotEqual(self.clone_status()["tone"], "ok")
        reference.chmod(0o600)
        self.assertEqual(self.clone_status()["tone"], "ok")
        # A tier off the graphics card leaves it not ready.
        self.config["tier"] = "small"
        self.write_config()
        self.install()
        self.assertEqual(self.clone_status()["tierReady"], False)
        self.assertNotEqual(self.clone_status()["tone"], "ok")
        self.config["tier"] = "large"
        self.write_config()
        self.install()
        self.assertEqual(self.clone_status()["tone"], "ok")
        # Controls: each drops one rule; its defect then reads ready.
        for name, needle, replacement, plant, restore in [
                ("row verifies", '            judge.verify(value, data / CLONE / "models", [clone_row(value)])\n        except',
                 "        except", lambda: model.write_bytes(b"corrupt"), lambda: model.write_bytes(original)),
                ("recording mode", "stat.S_IMODE(info.st_mode) == 0o600 and ", "",
                 lambda: reference.chmod(0o644), lambda: reference.chmod(0o600))]:
            with self.subTest(control=name):
                plant()
                self.assertNotEqual(self.clone_status()["tone"], "ok")
                self.mutant(needle, replacement)
                self.assertEqual(self.clone_status()["tone"], "ok", "must-fail control stayed green: " + name)
                (self.plugin / "setup-local").write_text((PLUGIN / "setup-local").read_text())
                restore()

    def test_clone_status_verifies_no_tier_and_control(self):
        # The Local voice row verifies the tier; the clone row reads its
        # marker, so a tier model the verifier would refuse leaves the
        # clone row's tier verdict as the marker gives it.
        self.large()
        self.assertEqual(self.clone_tui("clone-voice.sh", ["yes", "yes"]).returncode, 0)
        artifact = next(a for a in self.spec["artifacts"] if a["id"] == self.spec["tiers"]["large"]["artifacts"][0])
        tier_model = self.data / "models" / artifact["directory"] / next(iter(artifact["files"]))
        tier_model.write_bytes(b"corrupt")
        self.not_ready()
        self.assertEqual(self.clone_status()["tone"], "ok")
        self.mutant("tier = marked_tier(judge.manifest(HERE / \"artifacts.json\"), state)",
                    "tier = clone_tier(judge, judge.manifest(HERE / \"artifacts.json\"), state, data)")
        self.assertEqual(self.clone_status()["tierReady"], False, "must-fail control: the clone row verified the tier")
        # A marker naming a CPU tier, or none, reads no graphics card tier.
        (self.plugin / "setup-local").write_text((PLUGIN / "setup-local").read_text())
        marker = self.state / "local-ready.json"
        saved = marker.read_text()
        for text in (json.dumps(dict(json.loads(saved), tier="small")), "{", ""):
            with self.subTest(marker=text[:20]):
                marker.write_text(text)
                self.assertEqual(self.clone_status()["tierReady"], False)
        marker.unlink()
        self.assertEqual(self.clone_status()["tierReady"], False)

    def test_clone_install_needs_large_tier_and_control(self):
        self.install()
        self.ready()
        self.reset_calls()
        result = self.clone("check")
        self.assertEqual(result.returncode, 69)
        self.assertEqual(result.stderr.decode().splitlines()[0], "jarvis-setup: refused=clone=needs-large-tier")
        self.assertEqual(result.stdout, b"")
        result = self.clone("install")
        self.assertEqual(result.returncode, 69)
        self.assertEqual(result.stderr.decode().splitlines()[0], "jarvis-setup: refused=clone=needs-large-tier")
        self.assertEqual([call[0] for call in self.calls()], [], "nothing is built or downloaded")
        self.assertFalse((self.data / "clone").exists())
        self.mutant("        require_clone_tier(judge, value, state, data)\n", "")
        self.assertEqual(self.clone("install").returncode, 0)
        self.assertTrue(any(call[0] == "curl" for call in self.calls()))

    def test_clone_install_failure_removes_what_it_made(self):
        self.large()
        bad = next(iter(next(a for a in self.spec["artifacts"] if a["id"] == "chatterbox")["files"]))
        (self.downloads / "clone" / bad).write_bytes(b"bad hash")
        result = self.clone("install")
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"download=hash-mismatch", result.stderr)
        self.assertEqual(sorted(path.name for path in (self.data / "clone").iterdir()), [])
        self.mutant("            remove_runtime(root, CLONE_RUNTIME)\n", "")
        self.clone("install")
        self.assertTrue((self.data / "clone/venv").exists(), "must-fail control kept the runtime")

    # Recordings record refuses: (label, PCM, keyed refusal, needle of its rule).
    RECORDINGS = [
        ("too short", 2, 0.5, "recording=length", "if len(pcm) % 2 or not REFERENCE_SECONDS[0] <= seconds <= REFERENCE_SECONDS[1]:"),
        ("too long", 16, 0.5, "recording=length", "if len(pcm) % 2 or not REFERENCE_SECONDS[0] <= seconds <= REFERENCE_SECONDS[1]:"),
        ("no sound", 10, 0, "recording=silent", "if max(map(abs, samples)) < REFERENCE_PEAK:"),
    ]

    def test_clone_record_refusals_and_controls(self):
        self.large()
        self.assertEqual(self.clone("install").returncode, 0)
        for label, seconds, amplitude, key, needle in self.RECORDINGS:
            with self.subTest(recording=label):
                result = self.clone("record", stdin=self.tone(seconds, amplitude))
                self.assertEqual(result.returncode, 1)
                self.assertRegex(result.stderr.decode().splitlines()[0], "^jarvis-setup: failed=" + key + "( seconds=[0-9.]+)?$")
                self.assertFalse((self.state / "voice-reference.wav").exists())
                self.mutant(needle, "if False:")
                self.assertEqual(self.clone("record", stdin=self.tone(seconds, amplitude)).returncode, 0,
                                 "must-fail control stayed green: " + label)
                self.assertTrue((self.state / "voice-reference.wav").exists())
                (self.plugin / "setup-local").write_text((PLUGIN / "setup-local").read_text())
                self.clone("remove")
        # A failed probe keeps no recording and publishes nothing.
        self.config["clone_probe_exit"] = 1
        self.write_config()
        result = self.clone("record", stdin=self.tone(10))
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"jarvis-setup: failed=clone-probe", result.stderr)
        self.assertFalse((self.state / "voice-reference.wav").exists())
        self.assertFalse((self.state / "clone-ready.json").exists())

    def test_clone_lock_projection_control(self):
        self.large()
        lock = self.plugin / "requirements-clone.lock"
        original = lock.read_text()
        lock.write_text(original + original.splitlines()[-1] + "\n")
        result = self.clone("install")
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"clone-lock=unprojectable pins=2 replaced=1", result.stderr)
        self.mutant("if len(pins) != 1 or len(replaced) != 1:", "if False:")
        self.assertEqual(self.clone("install").returncode, 0)

    def test_shipped_lock_runtime_pins(self):
        lines = (PLUGIN / "requirements-local.lock").read_text().splitlines()
        lines += (PLUGIN / "requirements-local-cpu.lock").read_text().splitlines()
        lines += (PLUGIN / "requirements-clone.lock").read_text().splitlines()
        pins = {}
        for line in lines:
            if not line or line.startswith(("#", "-r ")):
                continue
            match = re.fullmatch(r"([a-z0-9-]+)==([0-9.]+) --hash=sha256:([a-f0-9]{64})", line)
            self.assertIsNotNone(match, line)
            self.assertNotIn(match[1], pins)
            pins[match[1]] = match[2]
        for name, runtime in self.spec["runtimes"].items():
            self.assertIn(pins[name], runtime["versions"])
        self.assertIn("sherpa-onnx-core", pins)
        # This data test has no production behavior to mutate. The install
        # fixture separately refuses removing require-hashes from its argv.


if __name__ == "__main__":
    namespace_entry()
    unittest.main()
