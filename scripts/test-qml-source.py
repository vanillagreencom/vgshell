#!/usr/bin/env python3
"""The source reader preserves literals and code whitespace while blanking comments.

The table covers the literal forms selection and smoke needle checking read.
A changed template-interpolation comment is the regression control: the old
opaque-template reader left it visible. Literal changes must remain visible.
"""
import unittest
from qml_source import blank_comments


class SourceComments(unittest.TestCase):
    def test_comment_spans_preserve_every_other_byte(self):
        # Mark comment spans with « and » in independent expected fixtures.
        cases = [
            'const x = "https://host/a/*b*/"; «// note»\n',
            "const x = 'https://host/a/*b*/'; «/* note */»\n",
            'const x = "escaped \\\" // /*"; «// note»\n',
            'const x = `https://host/a/*b*/ ${"//" + \'/*\'}`; «// note»\n',
            'const x = `literal ${1 «/* inner */» + 2} // /*`;\n',
            'const x = `outer ${`inner ${"/*" + 1 «/* nested */»}`} //`;\n',
            'const x = /[/*]/; const y = /https?:\\/\\//; «// note»\n',
            'function f() { return /[/*]/; } «/* note */»\n',
            'if (ready) /[/*]/.test(value); «// note»\n',
            'Item { property string url: "file://some/*path*/"; property string label: \'// /*\' } «// note»\n',
            'const x = left / right; «/* two\nlines */»\n',
            '//@ pragma Env QV4_GC_TIMELIMIT = 0\nItem {}\n',
            '«// keyboard-path: shell open»\nItem {}\n',
            '«// pointer-cursor-exempt: no pointer»\nItem {}\n',
            '«// focus-indicator: outline»\nItem {}\n',
        ]
        for marked in cases:
            with self.subTest(source=marked):
                text = ''
                expected = ''
                spans = []
                comment = False
                start = None
                for ch in marked:
                    if ch == '«':
                        comment, start = True, len(text)
                    elif ch == '»':
                        comment = False
                        spans.append((start, len(text)))
                    else:
                        text += ch
                        expected += '\n' if ch == '\n' else (' ' if comment else ch)
                found = []
                self.assertEqual(blank_comments(text, comments=found), expected)
                self.assertEqual(found, spans)

    def test_literal_changes_are_visible(self):
        for old, new in [
            ('"// old"', '"// new"'),
            ("'/* old */'", "'/* new */'"),
            ('`// old ${1}`', '`// new ${1}`'),
            ('`value ${1}`', '`value ${2}`'),
            ('/[/*]old/', '/[/*]new/'),
        ]:
            with self.subTest(old=old):
                self.assertNotEqual(blank_comments('const x = ' + old), blank_comments('const x = ' + new))

    def test_engine_pragmas_remain_code_for_both_readings(self):
        old = '//@ pragma Env QV4_GC_TIMELIMIT = 0\n'
        new = '//@ pragma Env QV4_GC_TIMELIMIT = 1\n'
        for literals in (True, False):
            self.assertEqual(blank_comments(old, literals=literals), old)
            self.assertNotEqual(blank_comments(old, literals=literals), blank_comments(new, literals=literals))

    def test_masked_templates_do_not_expose_braces(self):
        masked = blank_comments('`text ${ {x: "}"} /* c */ }`', literals=False)
        self.assertEqual((masked[0], masked[-1]), ('`', '`'))
        self.assertTrue(masked[1:-1].isspace())


if __name__ == '__main__':
    unittest.main()
