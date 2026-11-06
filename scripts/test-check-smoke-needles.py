#!/usr/bin/env python3
"""Exercise the production needle reader on disposable smoke rows and sources.

The planted comment needles are must-fail controls, including values assembled
outside the edit call. An unrelated label containing a comment marker must
pass; only the matched source span decides overlap.
"""
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

CHECK = pathlib.Path(__file__).with_name('check-smoke-needles.py')
SOURCE = 'Item {\n    property string url: "file://host/*literal*/"\n    // stable note\n    width: 1 /* trailing */\n}\n'


class SmokeNeedles(unittest.TestCase):
    def test_static_value_forms_and_comment_overlap(self):
        cases = [
            ('code', "edit_tree c shell/Test.qml '    width: 1' '    width: 2'\n", 0, None),
            ('literal URL', "edit_tree c shell/Test.qml '\"file://host/*literal*/\"' '\"other\"'\n", 0, None),
            ('irrelevant label', "plugin_control Test.qml '// label' '    width: 1' '    width: 2'\n", 0, None),
            ('line comment', "edit_tree c shell/Test.qml '// stable note' ''\n", 1, 'needle-comment'),
            ('block comment', "edit_tree c shell/Test.qml '1 /* trailing */' '2'\n", 1, 'needle-comment'),
            ('inside comment', "edit_tree c shell/Test.qml 'stable note' ''\n", 1, 'needle-comment'),
            ('variable', "old='// stable note'\nedit_tree c shell/Test.qml \"$old\" ''\n", 1, 'needle-comment'),
            ('concatenated variables', "a='/'\nb='/ stable note'\nold=\"$a$b\"\nedit_tree c shell/Test.qml \"$old\" ''\n", 1, 'needle-comment'),
            ('heredoc value', "old=$(cat <<'NEEDLE'\n// stable note\nNEEDLE\n)\nedit_tree c shell/Test.qml \"$old\" ''\n", 1, 'needle-comment'),
            ('forwarded parameter', "change() { local old=\"$1\"; shift; edit_tree c shell/Test.qml \"$old\" ''; }\nchange '// stable note'\n", 1, 'needle-comment'),
            ('array argument', "change() { edit_tree c \"$1\" \"$2\" ''; }\na=(shell/Test.qml '// stable note')\nchange \"${a[@]}\"\n", 1, 'needle-comment'),
            ('unresolved helper invocation', "change() { edit_tree c shell/Test.qml \"$1\" ''; }\nunknown_runner change '// stable note'\n", 2, 'needle-unreadable'),
            ('unknown value', "edit_tree c shell/Test.qml \"$unknown\" ''\n", 2, 'needle-unreadable'),
            ('computed value', "old=$(generate)\nedit_tree c shell/Test.qml \"$old\" ''\n", 2, 'needle-unreadable'),
        ]
        for name, row, status, key in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as tmp:
                root = pathlib.Path(tmp)
                rows = root / 'scripts/smoke/rows'
                rows.mkdir(parents=True)
                (root / 'shell/plugins/vgs.themes').mkdir(parents=True)
                (root / 'shell/Test.qml').write_text(SOURCE)
                (root / 'shell/plugins/vgs.themes/Test.qml').write_text(SOURCE)
                (rows / 'test.sh').write_text(row)
                result = subprocess.run([sys.executable, str(CHECK), str(root)], capture_output=True, text=True,
                                        env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'}, timeout=30)
                self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                if key:
                    self.assertTrue(result.stdout.startswith(key + ' '), result.stdout)
                else:
                    self.assertRegex(result.stdout, r'^check-smoke-needles: ok rows=1 edits=1\n$')

    def test_missing_source_tree_cannot_certify_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            rows = root / 'scripts/smoke/rows'
            rows.mkdir(parents=True)
            (rows / 'test.sh').write_text("edit_tree c shell/Test.qml 'width: 1' 'width: 2'\n")
            result = subprocess.run([sys.executable, str(CHECK), str(root)], capture_output=True, text=True,
                                    env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'}, timeout=30)
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertTrue(result.stdout.startswith('needle-unreadable '), result.stdout)

    def test_repository_discovery_covers_the_current_edit_family(self):
        result = subprocess.run([sys.executable, str(CHECK)], capture_output=True, text=True,
                                env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'}, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        # The incident had 119 edit_tree and 26 plugin_control sites. Leave
        # room for deletions, while a broken value/call extractor cannot pass.
        match = re.fullmatch(r'check-smoke-needles: ok rows=(\d+) edits=(\d+)\n', result.stdout)
        self.assertIsNotNone(match, result.stdout)
        self.assertGreaterEqual(int(match[1]), 30)
        self.assertGreaterEqual(int(match[2]), 100)


if __name__ == '__main__':
    unittest.main()
