#!/usr/bin/env python3
"""Controls for the glyph discriminator; the row holds the real slow-path control."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "launcher_latency", Path(__file__).parent / "smoke/launcher-latency.py")
latency = importlib.util.module_from_spec(spec)
spec.loader.exec_module(latency)


class FirstChangedGlyph(unittest.TestCase):
    def test_capture_starts_at_the_plain_input_origin(self):
        surface = "[100,200,1755,933]"
        for field, expected in (
                ("[10,20,300,40]", "110,220 12x40"),
                ("[34,20,300,40]", "134,220 12x40"),
                ("[42,20,300,40]", "142,220 12x40")):
            with self.subTest(field=field):
                self.assertEqual(latency.glyph_geometry(field, surface), expected)

    def test_missing_or_invalid_text_origin_is_not_a_capture(self):
        for field, surface in (
                ("absent", "[0,0,1755,933]"),
                ("null", "[0,0,1755,933]"),
                ("[0,0,300,40]", "absent"),
                ("[0,null,300,40]", "[0,0,1755,933]"),
                ("[0,true,300,40]", "[0,0,1755,933]"),
                ("[0,NaN,300,40]", "[0,0,1755,933]"),
                ("[0,0,11,40]", "[0,0,1755,933]"),
                ("[0,0,300,0]", "[0,0,1755,933]")):
            with self.subTest(field=field, surface=surface):
                with self.assertRaises(ValueError):
                    latency.glyph_geometry(field, surface)

    def test_preceding_queued_frame_is_not_the_response(self):
        blank = bytes([0] * 24)
        glyph = bytes([200] * 24)
        frames = [{"pixels": blank}, {"pixels": blank}, {"pixels": glyph}]
        self.assertEqual(latency.first_glyph(blank, glyph, frames, 8), (2, 24))

    def test_glyph_does_not_wait_for_the_adjacent_caret_to_settle(self):
        blank = bytes([0] * 36)
        glyph = bytes([200] * 24 + [0] * 12)
        final = bytes([200] * 24 + [255] * 12)
        frames = [{"pixels": glyph}, {"pixels": final}]
        self.assertEqual(latency.first_glyph(blank, final, frames, 8), (0, 24))

    def test_unread_first_character_width_refuses(self):
        for columns in (None, 0, 13, True, 8.5):
            with self.subTest(columns=columns), self.assertRaises(ValueError):
                latency.first_glyph(bytes([0] * 36), bytes([200] * 36),
                                    [{"pixels": bytes([200] * 36)}], columns)

    def test_unmeasured_never_becomes_zero_latency(self):
        for final, frames in (
                (bytes([0] * 24), [{"pixels": bytes([0] * 24)}]),
                (bytes([200] * 24), [{"pixels": bytes([0] * 24)}])):
            with self.subTest(final=final), self.assertRaises(ValueError):
                latency.first_glyph(bytes([0] * 24), final, frames, 8)


if __name__ == "__main__":
    unittest.main()
