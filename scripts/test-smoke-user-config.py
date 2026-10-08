#!/usr/bin/env python3
"""Read the destination while the real smoke restore still copies its source.

The FIFO holds cp after its first byte. The same check must fail when the
writer copies into the watched file. Row checks establish source wiring only.
"""
import errno
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]
WRITER = REPO / "scripts/smoke/user-config.sh"
BASH = shutil.which("bash")
ENV = {"PATH": os.defpath, "LANG": "C"}
BEFORE = b'{"version":1,"plugins":[]}\n'
AFTER = b'{"version":1,"plugins":[{"id":"acme.tick"}]}\n'


def restore(writer, home, backup):
    return subprocess.Popen(
        [BASH, "-c", 'set -euo pipefail; source "$1"; home="$2"; user_config_restore "$3"',
         "restore", str(writer), str(home), str(backup)],
        env=ENV, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )


def concurrent_read(writer, scratch):
    home = scratch / "home"
    config = home / ".config/vgshell"
    config.mkdir(parents=True)
    destination = config / "shell.json"
    destination.write_bytes(BEFORE)
    fifo = scratch / "backup.fifo"
    os.mkfifo(fifo)
    child = restore(writer, home, fifo)
    fd = None
    try:
        deadline = time.monotonic() + 5
        while fd is None:
            try:
                fd = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
            except OSError as error:
                if error.errno != errno.ENXIO:
                    raise
                assert child.poll() is None, "restore stopped before opening the backup"
                assert time.monotonic() < deadline, "restore never opened the backup"
                time.sleep(0.01)
        os.write(fd, AFTER[:1])
        # A non-empty staging file or a changed destination proves cp made
        # progress. The source stays open until after the concurrent read.
        while not (any(p.stat().st_size for p in config.glob(".shell.json.*"))
                   or destination.read_bytes() != BEFORE):
            assert child.poll() is None, "restore stopped before copying the prefix"
            assert time.monotonic() < deadline, "restore never copied the prefix"
            time.sleep(0.01)
        assert child.poll() is None, "restore ended before the source finished"
        observed = json.loads(destination.read_bytes())
        assert observed == {"version": 1, "plugins": []}, "unfinished restore replaced the document"
        os.write(fd, AFTER[1:])
        os.close(fd)
        fd = None
        out, errors = child.communicate(timeout=5)
        assert child.returncode == 0, (out, errors)
        assert destination.read_bytes() == AFTER, "completed restore lost backup bytes"
        assert not list(config.glob(".shell.json.*")), "completed restore left staging files"
    finally:
        if fd is not None:
            os.close(fd)
        if child.poll() is None:
            child.terminate()
        child.communicate(timeout=5)


class RestoreTests(unittest.TestCase):
    def test_concurrent_read_keeps_complete_document(self):
        with tempfile.TemporaryDirectory() as scratch:
            concurrent_read(WRITER, Path(scratch))

    def test_direct_copy_control_fails_same_contract(self):
        with tempfile.TemporaryDirectory() as scratch:
            scratch = Path(scratch)
            text = WRITER.read_text()
            old = 'cp -- "$1" "$staged"'
            self.assertEqual(text.count(old), 1)
            changed = text.replace(old, 'cp -- "$1" "$destination"')
            self.assertNotEqual(changed, text)
            mutant = scratch / "direct-copy.sh"
            mutant.write_text(changed)
            with self.assertRaises(json.JSONDecodeError):
                concurrent_read(mutant, scratch)

    def test_missing_backup_keeps_document_and_removes_staging(self):
        with tempfile.TemporaryDirectory() as scratch:
            home = Path(scratch) / "home"
            config = home / ".config/vgshell"
            config.mkdir(parents=True)
            destination = config / "shell.json"
            destination.write_bytes(BEFORE)
            child = restore(WRITER, home, Path(scratch) / "missing-backup")
            child.communicate(timeout=5)
            self.assertNotEqual(child.returncode, 0)
            self.assertEqual(destination.read_bytes(), BEFORE)
            self.assertEqual(list(config.glob(".shell.json.*")), [])

    def test_repaired_rows_use_restore_owner(self):
        # This establishes wiring, separately from the executed writer test.
        required = {"hold-shortcuts", "jarvis-keys", "jarvis-widget", "sound", "network", "vpn"}
        consumers = set()
        for name in required:
            path = REPO / "scripts/smoke/rows" / (name + ".sh")
            text = path.read_text().replace("\r\n", "\n")
            if any(line.startswith("user_config_restore ") for line in text.splitlines()):
                consumers.add(path.stem)
                inputs = next(line for line in text.splitlines() if line.startswith("# inputs:"))
                self.assertIn("scripts/smoke/user-config.sh", inputs.split())
        self.assertTrue(required <= consumers, "a repaired row bypasses the restore owner")


if __name__ == "__main__":
    assert BASH and Path(BASH).is_absolute(), "bash is unavailable"
    unittest.main()
