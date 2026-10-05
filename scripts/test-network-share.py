#!/usr/bin/env python3
"""Exercise the shipped Share owner with private command doubles and controls."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / "shell/plugins/vgs.network/bin/share-qr"
TOOLS = ROOT / "scripts/smoke/fixtures/devices/network-qr-tools.py"


class ShareTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="network-share-")
        self.home = Path(self.temp.name).resolve()
        self.bin = self.home / "bin"
        self.bin.mkdir()
        for name in ("nmcli", "qrencode"):
            target = self.bin / name
            target.write_text(TOOLS.read_text())
            target.chmod(0o755)
        self.calls = self.home / "calls"
        self.ready = self.home / "ready"
        self.world = self.home / "world.json"
        self.env = {"HOME": str(self.home), "PATH": str(self.bin) + ":" + os.defpath,
                    "NETWORK_QR_WORLD": str(self.world), "NETWORK_QR_CALLS": str(self.calls),
                    "NETWORK_QR_READY": str(self.ready), "PYTHONDONTWRITEBYTECODE": "1",
                    "VGS_TEST_RUN": "1", "TMPDIR": str(self.home), "XDG_CONFIG_HOME": str(self.home / "config"),
                    "XDG_STATE_HOME": str(self.home / "state"), "XDG_RUNTIME_DIR": str(self.home / "runtime")}
        self.secret = "network-share-fixture-secret"
        self.ssid = "VGS Smoke Wi-Fi"

    def tearDown(self):
        self.temp.cleanup()

    def prepare(self, *, expected="WIFI:T:WPA;S:VGS Smoke Wi-Fi;P:network-share-fixture-secret;;",
                key_management="wpa-psk", hidden="no", **options):
        world = {"profiles": [{"uuid": "profile-other", "ssid": "Other", "key_management": "wpa-psk", "hidden": "no", "secret_codes": [120] * 8},
                               {"uuid": "profile-smoke", "ssid": self.ssid, "key_management": key_management,
                                "hidden": hidden, "secret_codes": [ord(c) for c in self.secret]}],
                 "active": "--", "payload_digest": hashlib.sha256(expected.encode()).hexdigest(), **options}
        self.world.write_text(json.dumps(world))

    def run_helper(self, helper=HELPER, security="Wpa2Psk"):
        return subprocess.run([sys.executable, str(helper), "wlan0", self.ssid, security], cwd=self.home, env=self.env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)

    def assert_private(self, result):
        self.assertNotIn(self.secret.encode(), result.stdout + result.stderr)
        for path in self.home.rglob("*"):
            if path.is_file():
                self.assertNotIn(self.secret.encode(), path.read_bytes(), str(path))
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual([args[-1] for tool, args in calls if tool == "nmcli" and "--show-secrets" in args], ["profile-smoke"])
        self.assertEqual([args for tool, args in calls if tool == "qrencode"], [["--type", "ASCII", "--margin", "4", "--output", "-"]])
        self.assertTrue(all("--ask" not in args and "agent" not in args for tool, args in calls))

    def test_saved_disconnected_profile_and_private_transport(self):
        self.prepare()
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b"111\n101\n111\n")
        self.assert_private(result)

    def test_special_characters_and_hidden_network(self):
        self.ssid = 'Office:west;\\desk,"Wi-Fi"'
        self.secret = ' a:b;c,d\\e"f '
        self.prepare(hidden="yes", expected='WIFI:T:WPA;S:Office\\:west\\;\\\\desk\\,\\"Wi-Fi\\";P: a\\:b\\;c\\,d\\\\e\\"f ;H:true;;')
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_private(result)

    def test_open_wep_and_sae(self):
        for security, qr_type, key_management in [("Open", "nopass", "--"), ("Owe", "nopass", "owe"), ("StaticWep", "WEP", "none"), ("Sae", "WPA", "sae")]:
            with self.subTest(security=security):
                if self.calls.exists():
                    self.calls.unlink()
                self.prepare(expected="WIFI:T:" + qr_type + ";S:VGS Smoke Wi-Fi;P:" + ("" if qr_type == "nopass" else "network-share-fixture-secret") + ";;", key_management=key_management)
                result = self.run_helper(security=security)
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
                reads = [args for tool, args in calls if tool == "nmcli" and "--show-secrets" in args]
                if qr_type == "nopass":
                    self.assertEqual(reads, [], "an open network must not request a stored secret")
                else:
                    field = "802-11-wireless-security.wep-key0" if qr_type == "WEP" else "802-11-wireless-security.psk"
                    self.assertEqual([args[args.index("--get-values") + 1] for args in reads], [field])
                    self.assert_private(result)

    def test_refusal_and_invalid_encoder_are_visible(self):
        for option in ("refused", "invalid"):
            self.prepare(**{option: True})
            result = self.run_helper()
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, b"")
            self.assertIn(b"network-share: refused:", result.stderr)
        self.prepare(key_management="wpa-eap")
        self.assertEqual(self.run_helper(security="Wpa2Eap").returncode, 1)

    def test_cancel_stops_the_owned_child(self):
        self.prepare(hold=True)
        owner = subprocess.Popen([sys.executable, str(HELPER), "wlan0", self.ssid, "Wpa2Psk"], cwd=self.home, env=self.env,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            # The fixture's ready file is a barrier, not a guessed startup sleep.
            deadline = time.monotonic() + 5
            while not self.ready.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(self.ready.exists(), "the encoder reached its private pipe")
            child = int(self.ready.read_text())
            owner.send_signal(signal.SIGTERM)
            out, err = owner.communicate(timeout=3)
            self.assertEqual(out, b"")
            self.assertNotIn(self.secret.encode(), out + err)
            with self.assertRaises(ProcessLookupError):
                os.kill(child, 0)
        finally:
            if owner.poll() is None:
                owner.kill()
                owner.wait()

    def test_secret_and_format_controls(self):
        source = HELPER.read_text()
        for name, needle, replacement in [
            ("argv", '["qrencode", "--type", "ASCII", "--margin", "4", "--output", "-"]', '["qrencode", "--type", "ASCII", "--margin", "4", "--output", "-", payload]'),
            ("disk", 'payload += ";"', 'payload += ";"\n        open("share-leak", "w").write(secret)'),
            ("escaping", 'value = value.replace(character, "\\\\" + character)', 'value = value.replace(character, character)'),
        ]:
            with self.subTest(control=name):
                self.assertEqual(source.count(needle), 1)
                mutant = self.home / "mutant.py"
                mutant.write_text(source.replace(needle, replacement))
                self.ssid = "Office:west;desk"
                self.prepare(expected="WIFI:T:WPA;S:Office\\:west\\;desk;P:network-share-fixture-secret;;")
                if self.calls.exists():
                    self.calls.unlink()
                leak = self.home / "share-leak"
                if leak.exists():
                    leak.unlink()
                result = self.run_helper(mutant)
                if name == "escaping":
                    self.assertEqual(result.returncode, 1, "bad escaping must reach the encoder's stdin check")
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    with self.assertRaises(AssertionError):
                        self.assert_private(result)
                mutant.unlink()
                if leak.exists():
                    leak.unlink()
                print("network-share: control=" + name + " red")


if __name__ == "__main__":
    unittest.main()
