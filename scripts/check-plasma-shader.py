#!/usr/bin/env python3
"""Compile Voice's plasma orb source with Qt qsb and compare its shipped pack.

The pack contract, the compiler lookup and the exits are
scripts/check-voiceorb-shader.py's, whose check() judges this source too.
The plasma is a short volumetric raymarch, so its source may loop, each
loop bounded by a constant; it samples no texture. --write regenerates the pack. --source selects a
disposable copy.
"""
import argparse
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "shell/plugins/vgs.voice/shaders/plasma.frag"
RULES = ("loop-bound", "texture")

# The pack's judge has a hyphenated filename; import it through its path.
spec = importlib.util.spec_from_file_location("voiceorb_shader", Path(__file__).with_name("check-voiceorb-shader.py"))
judge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(judge)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    raise SystemExit(judge.check(args.source, args.write, RULES, "plasma-shader"))
