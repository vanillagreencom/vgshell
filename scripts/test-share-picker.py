#!/usr/bin/env python3
"""Exercise the picker through vgshell's real IPC judge, with a scratch qs.

The independent C++ fixture executes xdph's selection parser. Defect controls
prove that a wrong handle, a missing newline, and wrong remember flags cannot
pass a typed consumer readback. No portal, shell, or live config is started.
"""

import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parent.parent
PICKER = REPO / "bin/vgshell-share-picker"
WINDOW_LIST = "31[HC>]org.editor[HT>]Editor document[HE>]291[HA>]4294967295[HC>]org.web[HT>]Browser $ title[HE>]18446744073709551615[HA>]"
EXPECTED_WINDOWS = [
    {"id": "31", "address": "0x123", "class": "org.editor", "title": "Editor document"},
    {"id": "4294967295", "address": "0xffffffffffffffff", "class": "org.web", "title": "Browser $ title"},
]
loader = importlib.machinery.SourceFileLoader("share_picker", str(PICKER))
spec = importlib.util.spec_from_loader(loader.name, loader)
picker = importlib.util.module_from_spec(spec)
loader.exec_module(picker)

QS = r'''#!/usr/bin/env python3
import json, os, pathlib, sys, time
root = pathlib.Path(os.environ["HOME"])
world = json.loads((root / "world.json").read_text())
assert sys.argv[1:3] == ["ipc", "--pid"]
assert sys.argv[4:8] == ["call", "vgs.capture", "invoke", sys.argv[7]]
command, payload = sys.argv[7], json.loads(sys.argv[8])
assert isinstance(payload, dict)
with (root / "calls.jsonl").open("a") as log:
    log.write(json.dumps({"command": command, "payload": payload, "leaked": "CALLER_SECRET" in os.environ}) + "\n")
if command == "share-begin":
    (root / "began").write_text(payload["id"])
    if world.get("hang_begin"):
        (root / "child-ready").write_text(str(os.getpid()))
        time.sleep(60)
    print(world.get("begin", "ok"))
elif command == "share-result":
    (root / "result-ready").write_text("ready")
    count_path = root / "poll-count"
    count = int(count_path.read_text()) if count_path.exists() else 0
    count_path.write_text(str(count + 1))
    if count < world.get("pending", 0) or world.get("always_pending"):
        print("pending")
    elif "reply" in world:
        print(world["reply"])
    else:
        print("INFO fixture log before the response")
        print(json.dumps({"choice": world["choice"]}))
elif command == "share-cancel":
    (root / "cancelled").write_text(payload["id"])
    print("ok")
else:
    sys.exit(1)
'''

SYSTEMCTL = r'''#!/usr/bin/env python3
import json, os, pathlib, sys, time
root = pathlib.Path(os.environ["HOME"])
world_path = root / "world.json"
world = json.loads(world_path.read_text()) if world_path.exists() else {}
with (root / "systemctl.jsonl").open("a") as log:
    log.write(json.dumps({"args": sys.argv[1:], "leaked": "CALLER_SECRET" in os.environ}) + "\n")
if "show" in sys.argv:
    if world.get("probe_fail"):
        sys.exit(1)
    if "probe_reply" in world:
        print(world["probe_reply"])
        sys.exit(0)
    restarted = (root / "backend-started").exists()
    active = world.get("backend_state", "failed" if (root / "backend-failed").exists() else "active" if restarted else "inactive")
    print("LoadState=" + world.get("load_state", "loaded"))
    print("ActiveState=" + active)
    sys.exit(0)
if world.get("restart_mutate"):
    (root / "config/hypr/xdph.conf").write_text("# Concurrent owner edit\n")
assert sys.argv[1:] in (["--user", "restart", "xdg-desktop-portal-hyprland.service"],
                       ["--user", "try-restart", "xdg-desktop-portal-hyprland.service"])
if world.get("restart_fail"):
    if not world.get("restart_denied"):
        (root / "backend-failed").write_text("failed")
        (root / "backend-started").unlink(missing_ok=True)
elif "try-restart" not in sys.argv or world.get("backend_state") == "active":
    (root / "backend-failed").unlink(missing_ok=True)
    (root / "backend-started").write_text(str(time.time_ns()))
sys.exit(1 if world.get("restart_fail") else 0)
'''

BUSCTL = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ["HOME"])
world_path = root / "world.json"
world = json.loads(world_path.read_text()) if world_path.exists() else {}
expected = ["--user", "get-property", "org.freedesktop.systemd1",
            "/org/freedesktop/systemd1/unit/xdg_2ddesktop_2dportal_2dhyprland_2eservice",
            "org.freedesktop.systemd1.Service", "ExecMainStartTimestamp"]
assert sys.argv[1:] == expected
with (root / "busctl.jsonl").open("a") as log:
    log.write(json.dumps({"args": sys.argv[1:], "leaked": "CALLER_SECRET" in os.environ}) + "\n")
if world.get("bus_fail"):
    sys.exit(1)
if "bus_reply" in world:
    print(world["bus_reply"])
else:
    started_path = root / "backend-started"
    started_ns = int(started_path.read_text()) if started_path.exists() else world.get("backend_started_ns", 0)
    print("t " + str(started_ns // 1000))
'''


class PickerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix="vgs-share-picker-", dir=REPO / "tmp")
        cls.root = Path(cls.scratch.name)
        cls.consumer = cls.root / "xdph-selection"
        compiler = shutil.which("g++")
        if not compiler:
            raise RuntimeError("share-picker-tests: compiler=missing")
        subprocess.run([compiler, "-std=c++17", "-o", str(cls.consumer),
                        str(REPO / "scripts/fixtures/share-picker/xdph-selection.cpp")],
                       env={"PATH": os.defpath, "HOME": str(cls.root), "VGS_TEST_RUN": "1"},
                       check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def setUp(self):
        self.case = tempfile.TemporaryDirectory(dir=self.root)
        self.home = Path(self.case.name)
        self.runtime = self.home / "runtime"
        self.runtime.mkdir()
        (self.runtime / "vgshell.lock").write_text(str(os.getpid()) + "\n")
        self.tools = self.home / "tools"
        self.tools.mkdir()
        (self.tools / "qs").write_text(QS)
        (self.tools / "qs").chmod(0o755)
        (self.tools / "systemctl").write_text(SYSTEMCTL)
        (self.tools / "systemctl").chmod(0o755)
        (self.tools / "busctl").write_text(BUSCTL)
        (self.tools / "busctl").chmod(0o755)
        self.environment = {
            "HOME": str(self.home), "PATH": str(self.tools) + ":" + os.defpath,
            "XDG_CONFIG_HOME": str(self.home / "config"), "XDG_RUNTIME_DIR": str(self.runtime),
            "LANG": "C.UTF-8", "VGS_TEST_RUN": "1", "CALLER_SECRET": "must-not-reach-child",
            "XDPH_WINDOW_SHARING_LIST": WINDOW_LIST,
        }

    def tearDown(self):
        self.case.cleanup()

    def world(self, **values):
        (self.home / "world.json").write_text(json.dumps(values))

    def calls(self):
        path = self.home / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def restarts(self):
        return [row for row in self.systemctl_calls() if set(row["args"]) & {"restart", "try-restart"}]

    def systemctl_calls(self):
        path = self.home / "systemctl.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def run_picker(self, *arguments, executable=PICKER):
        return subprocess.run([str(executable), *arguments], env=self.environment,
                              stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10)

    def read_selection(self, line):
        result = subprocess.run([str(self.consumer)], input=line, text=True, capture_output=True,
                                env={"PATH": os.defpath, "HOME": str(self.home), "VGS_TEST_RUN": "1"}, timeout=5)
        self.assertEqual(result.returncode, 0)
        return result.stdout.rstrip("\n").split("\t")

    def wait_marker(self, name, process):
        deadline = time.monotonic() + 5
        path = self.home / name
        while not path.exists():
            self.assertIsNone(process.poll(), "child ended before its readiness barrier")
            self.assertLess(time.monotonic(), deadline, "readiness barrier timed out")
            time.sleep(0.01)
        return path.read_text()

    def test_upstream_consumer_forms_and_remember(self):
        cases = [
            ({"type": "screen", "output": "HEADLESS-1"}, ["screen", "HEADLESS-1"]),
            ({"type": "window", "id": "31"}, ["window", "31"]),
            ({"type": "window", "id": "4294967295"}, ["window", "4294967295"]),
            ({"type": "region", "output": "HEADLESS-1", "x": 13, "y": 27, "width": 401, "height": 233},
             ["region", "HEADLESS-1", "13,27,401,233"]),
        ]
        for base, wanted in cases:
            for remember in (False, True):
                with self.subTest(choice=base, remember=remember):
                    self.world(choice={**base, "remember": remember})
                    result = self.run_picker(*(["--allow-token"] if remember else []))
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(self.read_selection(result.stdout), [wanted[0], str(int(remember)), *wanted[1:]])
                    calls = self.calls()
                    begin = next(row for row in reversed(calls) if row["command"] == "share-begin")
                    self.assertEqual(begin["payload"]["windows"], EXPECTED_WINDOWS)
                    self.assertEqual(begin["payload"]["remember"], remember)
                    self.assertEqual((self.home / "cancelled").read_text(), begin["payload"]["id"])
                    self.assertTrue(all(not row["leaked"] for row in calls))

    def test_consumer_must_fail_controls(self):
        choice = {"type": "screen", "output": "HEADLESS-1", "remember": True}
        line = picker.serialize_choice(choice, EXPECTED_WINDOWS)
        expected = ["screen", "1", "HEADLESS-1"]
        self.assertEqual(self.read_selection(line), expected)
        for malformed in (line.rstrip("\n"), line.replace("[SELECTION]r/", "[SELECTION]/")):
            self.assertNotEqual(self.read_selection(malformed), expected)
        window = picker.serialize_choice({"type": "window", "id": "31", "remember": False}, EXPECTED_WINDOWS)
        self.assertNotEqual(self.read_selection(window.replace("window:31", "window:291")), ["window", "0", "31"])
        bad_prefix = subprocess.run([str(self.consumer)], input=line.replace("[SELECTION]", "[BROKEN]"),
                                    env={"PATH": os.defpath, "VGS_TEST_RUN": "1"}, capture_output=True, text=True, timeout=5)
        self.assertNotEqual(bad_prefix.returncode, 0)

    def test_window_input_refuses_malformed_and_accepts_empty(self):
        self.assertEqual(picker.parse_windows(""), [])
        bad = ["1[HC>]a[HT>]b[HE>]3", "-1[HC>]a[HT>]b[HE>]3[HA>]",
               "4294967296[HC>]a[HT>]b[HE>]3[HA>]", "1[HC>]a[HT>]b[HE>]18446744073709551616[HA>]",
               "1[HC>]a[HT>]b[HE>]3[HA>]1[HC>]c[HT>]d[HE>]4[HA>]"]
        for value in bad:
            with self.subTest(value=value), self.assertRaises(picker.PickerError):
                picker.parse_windows(value)

    def test_selection_refuses_invalid_choices(self):
        base = {"type": "region", "output": "HEADLESS-1", "x": 1, "y": 2, "width": 3, "height": 4, "remember": False}
        choices = [None, {**base, "remember": 1}, {**base, "output": "HEADLESS-1\n"},
                   {**base, "x": -1}, {**base, "y": True}, {**base, "height": 0},
                   {**base, "width": 0x80000000}, {**base, "type": "unknown"},
                   {"type": "window", "id": "291", "remember": False},
                   {"type": "window", "id": "4294967296", "remember": False}]
        for value in choices:
            with self.subTest(choice=value), self.assertRaises(picker.PickerError):
                picker.serialize_choice(value, EXPECTED_WINDOWS)

    def test_cancel_bad_result_and_qs_failure_produce_no_selection(self):
        for world in ({"reply": "cancelled"}, {"reply": "not-json"},
                      {"reply": "Target not found."}, {"begin": "busy"}):
            with self.subTest(world=world):
                self.world(**world)
                result = self.run_picker()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertEqual((self.home / "cancelled").read_text(), (self.home / "began").read_text())

    def test_no_shell_produces_no_selection(self):
        (self.runtime / "vgshell.lock").unlink()
        result = self.run_picker()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.calls(), [])

    def test_pending_result_then_selection(self):
        self.world(pending=1, choice={"type": "screen", "output": "HEADLESS-1", "remember": False})
        result = self.run_picker()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read_selection(result.stdout), ["screen", "0", "HEADLESS-1"])
        self.assertEqual(int((self.home / "poll-count").read_text()), 2)

    def test_timeout_wiring_uses_disposable_short_deadline(self):
        # Only the deadline changes in the scratch program. All IPC and cleanup
        # run unchanged; the real parent deadline bounds a broken timeout.
        copy = self.home / "vgshell-share-picker"
        source = PICKER.read_text()
        self.assertEqual(source.count("PICKER_TIMEOUT = 120.0"), 1)
        copy.write_text(source.replace("PICKER_TIMEOUT = 120.0", "PICKER_TIMEOUT = 0.2"))
        copy.chmod(0o755)
        (self.home / "vgshell").symlink_to(REPO / "bin/vgshell")
        self.world(always_pending=True)
        result = self.run_picker(executable=copy)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual((self.home / "cancelled").read_text(), (self.home / "began").read_text())

    def blocked_ipc_deadline(self, executable):
        self.world(hang_begin=True)
        for name in ("child-ready", "began", "cancelled"):
            (self.home / name).unlink(missing_ok=True)
        child = subprocess.Popen([str(executable)], env=self.environment, stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        blocked_pid = None
        timed_out = False
        try:
            ready = self.wait_marker("child-ready", child)
            try:
                blocked_pid = os.pidfd_open(int(ready))
            except ProcessLookupError:
                pass
            try:
                stdout, stderr = child.communicate(timeout=2)
            except subprocess.TimeoutExpired:
                timed_out = True
            self.assertFalse(timed_out, "deadline-control=parent-expired")
            self.assertNotEqual(child.returncode, 0)
            self.assertEqual(stdout, "")
            self.assertIn("ipc-share-begin=timeout", stderr)
            request_id = (self.home / "began").read_text()
            cancellations = [row for row in self.calls() if row["command"] == "share-cancel"]
            self.assertEqual(cancellations[-1]["payload"], {"id": request_id})
            self.assertEqual((self.home / "cancelled").read_text(), request_id)
            state = Path("/proc") / ready / "stat"
            self.assertTrue(not state.exists() or state.read_text().split()[2] == "Z")
        finally:
            # The mutant lacks only the deadline. Its signal path still owns
            # IPC cleanup. A pidfd also bounds cleanup if that path regresses.
            if child.poll() is None:
                child.send_signal(signal.SIGTERM)
            try:
                child.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                if blocked_pid is not None:
                    try:
                        signal.pidfd_send_signal(blocked_pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                child.communicate(timeout=5)
            finally:
                if blocked_pid is not None:
                    os.close(blocked_pid)

    def test_unsignalled_blocked_ipc_deadline_and_must_fail_control(self):
        source = PICKER.read_text()
        self.assertEqual(source.count("IPC_TIMEOUT = 3.0"), 1)
        source = source.replace("IPC_TIMEOUT = 3.0", "IPC_TIMEOUT = 0.2")
        copy = self.home / "vgshell-share-picker"
        copy.write_text(source)
        copy.chmod(0o755)
        (self.home / "vgshell").symlink_to(REPO / "bin/vgshell")
        self.blocked_ipc_deadline(copy)
        guard = "if remaining <= 0:"
        self.assertEqual(source.count(guard), 2)
        # Only run_child's guard is disabled; the picker deadline and signal
        # cancellation still run. The same contract must reject this program.
        copy.write_text(source.replace(guard, "if False and remaining <= 0:", 1))
        control = unittest.FunctionTestCase(lambda: self.blocked_ipc_deadline(copy))
        verdict = unittest.TestResult()
        control.run(verdict)
        self.assertEqual(verdict.errors, [])
        self.assertEqual(len(verdict.failures), 1)
        self.assertIn("deadline-control=parent-expired", verdict.failures[0][1])

    def test_signal_cancels_request_and_reaps_blocked_ipc_child(self):
        for blocked in (False, True):
            with self.subTest(blocked=blocked):
                for name in ("child-ready", "result-ready", "cancelled"):
                    (self.home / name).unlink(missing_ok=True)
                self.world(always_pending=True, hang_begin=blocked)
                child = subprocess.Popen([str(PICKER)], env=self.environment, stdin=subprocess.DEVNULL,
                                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                try:
                    ready = self.wait_marker("child-ready" if blocked else "result-ready", child)
                    child.send_signal(signal.SIGTERM)
                    stdout, stderr = child.communicate(timeout=10)
                    self.assertNotEqual(child.returncode, 0, stderr)
                    self.assertEqual(stdout, "")
                    self.assertEqual((self.home / "cancelled").read_text(), (self.home / "began").read_text())
                    if blocked:
                        state = Path("/proc") / ready / "stat"
                        self.assertTrue(not state.exists() or state.read_text().split()[2] == "Z")
                finally:
                    if child.poll() is None:
                        child.kill()
                    child.communicate()

    def test_configure_preserves_values_comments_and_is_idempotent(self):
        directory = self.home / "config/hypr"
        directory.mkdir(parents=True)
        config = directory / "xdph.conf"
        before = ("# Owner settings\r\ngeneral {\r\n toplevel_dynamic_bind = 1\r\n}\r\n"
                  "screencopy { # Screen capture\r\n allow_token_by_default = 1 # Remember\r\n"
                  " max_fps = 57\r\n custom_picker_binary = /old/picker  # Picker\r\n}\r\n")
        config.write_bytes(before.encode())
        config.chmod(0o640)
        result = self.run_picker("--configure")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(config.read_bytes(), before.replace("/old/picker", str(PICKER)).encode())
        self.assertEqual(config.stat().st_mode & 0o777, 0o640)
        original = config.stat()
        result = self.run_picker("--configure")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(config.stat().st_ino, original.st_ino)
        self.assertEqual(config.stat().st_mtime_ns, original.st_mtime_ns)
        self.assertEqual(self.restarts(), [{"args": ["--user", "restart", "xdg-desktop-portal-hyprland.service"], "leaked": False}])

    def test_configure_adds_only_picker_and_supports_qualified_assignment(self):
        for before in ("", "# Existing\nscreencopy {\n allow_token_by_default = 0\n}\n",
                       "screencopy:custom_picker_binary = /old/picker # Keep\n"):
            with self.subTest(before=before):
                config = self.home / "config/hypr/xdph.conf"
                config.parent.mkdir(parents=True, exist_ok=True)
                config.write_text(before)
                result = self.run_picker("--configure")
                self.assertEqual(result.returncode, 0, result.stderr)
                after = config.read_text()
                self.assertIn(str(PICKER), after)
                if "/old/picker" in before:
                    self.assertEqual(after, before.replace("/old/picker", str(PICKER)))
                else:
                    self.assertTrue(after.startswith(before))
                    self.assertNotIn("allow_token_by_default", after[len(before):])

    def test_configure_creates_missing_file_without_setting_remember(self):
        result = self.run_picker("--configure")
        self.assertEqual(result.returncode, 0, result.stderr)
        config = self.home / "config/hypr/xdph.conf"
        self.assertEqual(config.read_text(), "screencopy {\n    custom_picker_binary = " + str(PICKER) + "\n}\n")
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)

    def test_configure_does_not_remove_an_unowned_temporary_file(self):
        directory = self.home / "config/hypr"
        directory.mkdir(parents=True)
        existing = directory / ".xdph.conf.fixture"
        existing.write_text("other writer\n")
        fixed_uuid = type("FixedUuid", (), {"hex": "fixture"})()
        with patch.dict(os.environ, self.environment, clear=True), patch.object(picker.uuid, "uuid4", return_value=fixed_uuid):
            with self.assertRaises(FileExistsError):
                picker.configure()
        self.assertEqual(existing.read_text(), "other writer\n")
        self.assertFalse((directory / "xdph.conf").exists())

    def test_failed_restart_keeps_picker_needed_and_retries_activation(self):
        config = self.home / "config/hypr/xdph.conf"
        cases = [(before, denied) for before in (None, "# Original settings\nscreencopy {\n allow_token_by_default = 1\n}\n")
                 for denied in (False, True)]
        for before, denied in cases:
            with self.subTest(before=before, denied=denied):
                config.parent.mkdir(parents=True, exist_ok=True)
                config.unlink(missing_ok=True)
                if before is not None:
                    config.write_text(before)
                (self.home / "backend-started").unlink(missing_ok=True)
                (self.home / "backend-failed").unlink(missing_ok=True)
                self.world(restart_fail=True, restart_denied=denied)
                result = self.run_picker("--configure")
                self.assertEqual(result.returncode, 75)
                self.assertEqual(result.stdout, "")
                self.assertIn(str(PICKER), config.read_text())
                if before is not None:
                    self.assertTrue(config.read_text().startswith(before))
                status = self.run_picker("--probe")
                self.assertEqual(status.returncode, 0, status.stderr)
                self.assertEqual(json.loads(status.stdout)["state"], "needed")
                written = config.stat()
                calls = len(self.restarts())
                status = self.run_picker("--probe")
                self.assertEqual(json.loads(status.stdout), {"state": "needed"})
                self.assertEqual(config.stat().st_ino, written.st_ino)
                self.assertEqual(config.stat().st_mtime_ns, written.st_mtime_ns)
                self.assertEqual(len(self.restarts()), calls)
                self.world()
                count = len(self.restarts())
                result = self.run_picker("--configure")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(len(self.restarts()), count + 1)
                self.assertEqual(self.restarts()[-1]["args"], ["--user", "restart", "xdg-desktop-portal-hyprland.service"])
                self.assertIn(str(PICKER), config.read_text())
                status = self.run_picker("--probe")
                self.assertEqual(json.loads(status.stdout), {"state": "ready"})

    def test_failed_activation_becomes_ready_on_next_backend_start(self):
        for denied in (False, True):
            with self.subTest(denied=denied):
                config = self.home / "config/hypr/xdph.conf"
                config.unlink(missing_ok=True)
                (self.home / "backend-started").unlink(missing_ok=True)
                (self.home / "backend-failed").unlink(missing_ok=True)
                self.world(restart_fail=True, restart_denied=denied)
                self.assertEqual(self.run_picker("--configure").returncode, 75)
                calls = len(self.restarts())
                written = config.stat()
                self.assertEqual(json.loads(self.run_picker("--probe").stdout), {"state": "needed"})
                (self.home / "backend-started").write_text(str(time.time_ns()))
                (self.home / "backend-failed").unlink(missing_ok=True)
                self.world()
                result = self.run_picker("--probe")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), {"state": "ready"})
                self.assertEqual(len(self.restarts()), calls)
                self.assertEqual(config.stat().st_ino, written.st_ino)
                self.assertEqual(config.stat().st_mtime_ns, written.st_mtime_ns)

    def test_probe_is_read_only_for_missing_wrong_and_configured_picker(self):
        result = self.run_picker("--probe")
        self.assertEqual(json.loads(result.stdout), {"state": "needed"})
        self.assertFalse((self.home / "config").exists())
        self.assertEqual(self.systemctl_calls(), [])
        config = self.home / "config/hypr/xdph.conf"
        config.parent.mkdir(parents=True)
        config.write_text("# Owner\nscreencopy {\n custom_picker_binary = /other/picker\n}\n")
        before = config.read_bytes()
        result = self.run_picker("--probe")
        self.assertEqual(json.loads(result.stdout), {"state": "needed"})
        self.assertEqual(config.read_bytes(), before)
        self.assertEqual(self.systemctl_calls(), [])
        config.write_text("screencopy {\n custom_picker_binary = " + str(PICKER) + "\n}\n")
        before = config.stat()
        for world, expected in (({"backend_state": "inactive"}, "needed"),
                                ({"backend_state": "failed"}, "needed"),
                                ({"backend_state": "active", "backend_started_ns": 0}, "needed"),
                                ({"backend_state": "activating"}, "needed"),
                                ({"probe_fail": True}, "needed"),
                                ({"load_state": "not-found"}, "needed"),
                                ({"backend_state": "active", "bus_fail": True}, "needed"),
                                ({"backend_state": "active", "bus_reply": "s invalid"}, "needed")):
            self.world(**world)
            result = self.run_picker("--probe")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["state"], expected)
            self.assertEqual(config.stat().st_ino, before.st_ino)
            self.assertEqual(config.stat().st_mtime_ns, before.st_mtime_ns)
            self.assertEqual(self.restarts(), [])

    def test_probe_compares_typed_epoch_microseconds_with_file_nanoseconds(self):
        config = self.home / "config/hypr/xdph.conf"
        config.parent.mkdir(parents=True)
        config.write_text("screencopy {\n custom_picker_binary = " + str(PICKER) + "\n}\n")
        timestamp = 1791395939000000000
        os.utime(config, ns=(timestamp, timestamp))
        cases = [(active, started, state) for active in ("active", "inactive")
                 for started, state in ((timestamp - 1000, "needed"), (timestamp, "ready"), (timestamp + 1000, "ready"))]
        for active, started, state in cases:
            with self.subTest(active=active, started=started):
                self.world(backend_state=active, backend_started_ns=started)
                result = self.run_picker("--probe")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), {"state": state})
                self.assertEqual(self.restarts(), [])
        bus_calls = [json.loads(line) for line in (self.home / "busctl.jsonl").read_text().splitlines()]
        self.assertTrue(bus_calls)
        self.assertTrue(all(not row["leaked"] for row in bus_calls))

    def test_failed_restart_preserves_a_concurrent_owner_edit(self):
        self.world(restart_fail=True, restart_mutate=True)
        result = self.run_picker("--configure")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.home / "config/hypr/xdph.conf").read_text(), "# Concurrent owner edit\n")

    def test_configure_refuses_unread_malformed_and_symlink_files(self):
        directory = self.home / "config/hypr"
        directory.mkdir(parents=True)
        config = directory / "xdph.conf"
        for content in (b"screencopy {\n max_fps = 57\n", b"}\n", b"[screencopy]\n", b"\xff"):
            with self.subTest(content=content):
                config.write_bytes(content)
                before = config.stat()
                result = self.run_picker("--configure")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(config.read_bytes(), content)
                self.assertEqual(config.stat().st_ino, before.st_ino)
        config.write_text("# unread\n")
        config.chmod(0)
        try:
            if os.geteuid() != 0:
                self.assertNotEqual(self.run_picker("--configure").returncode, 0)
                self.assertEqual(config.stat().st_size, len("# unread\n"))
        finally:
            config.chmod(0o600)
        outside = self.home / "outside"
        outside.write_text("# Outside\n")
        config.unlink()
        config.symlink_to(outside)
        self.assertNotEqual(self.run_picker("--configure").returncode, 0)
        self.assertTrue(config.is_symlink())
        self.assertEqual(outside.read_text(), "# Outside\n")
        config.unlink()
        directory.rmdir()
        directory.symlink_to(self.home)
        self.assertNotEqual(self.run_picker("--configure").returncode, 0)
        self.assertFalse((self.home / "xdph.conf").exists())
        self.assertEqual(self.restarts(), [])


if __name__ == "__main__":
    unittest.main()
