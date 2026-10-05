#!/usr/bin/env python3
"""Compile VoiceOrb's source with Qt qsb and compare its shipped pack.

qsb is a build/validation tool, not a runtime requirement. Find it on PATH
or in Qt's Linux tool directories; QSB overrides the lookup for test copies.
Exit 77 when it is absent. Exit 1 on unreadable, invalid, stale or forbidden
source. --write regenerates the pack. --source selects a disposable copy.
The qsb --qt6 targets and --qsbversion 64 are the reproducible build contract.
A pack is fresh when it holds the shader a fresh compile holds. A pack is
qCompress output, a 4-byte big-endian length and a zlib stream, and two zlib
builds deflate one shader to different bytes (zlib 1.3.2 on Arch, zlib-ng
2.3.3 on CachyOS), so the pack is compared decompressed. check() is the one
judge of a shipped pack; scripts/check-plasma-shader.py hands it Voice's
plasma source with that source's own rules.
"""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zlib

SOURCE = Path(__file__).resolve().parents[1] / "shell/Ui/feedback/shaders/voiceorb.frag"
OPTIONS = ("--qt6", "--qsbversion", "64")
# Each rule a source may break, as a pattern over its code.
PATTERNS = {
    "loop": r"\b(?:for|while|do)\b",
    "texture": r"\b(?:sampler\w*|texture\w*|texelFetch\w*)\b",
}
# The visual is analytic. No iteration or texture sampling is needed.
RULES = ("loop", "texture")


def breaks(rule, code):
    """Whether CODE breaks RULE. `loop-bound` takes a `for` loop only when
    its condition compares the counter with a literal or a `const int`, so
    a frame's work cannot grow with a uniform; it takes no `while` or `do`."""
    if rule != "loop-bound":
        return re.search(PATTERNS[rule], code) is not None
    if re.search(r"\b(?:while|do)\b", code):
        return True
    constants = set(re.findall(r"\bconst\s+int\s+(\w+)\s*=\s*\d+\s*;", code))
    for condition in re.findall(r"\bfor\s*\([^;]*;([^;]*);", code):
        bound = re.fullmatch(r"\s*\w+\s*<=?\s*(\w+)\s*", condition)
        if bound is None or not (bound[1].isdigit() or bound[1] in constants):
            return True
    return False


def qsb_tool():
    """Resolve the documented tool locations, or an explicit test override."""
    if "QSB" in os.environ:
        candidate = os.environ["QSB"]
        return candidate if os.path.isfile(candidate) and os.access(candidate, os.X_OK) else None
    return shutil.which("qsb") or next(
        (str(p) for p in (Path("/usr/lib/qt6/bin/qsb"), Path("/usr/lib64/qt6/bin/qsb"))
         if p.is_file() and os.access(p, os.X_OK)), None)


def shader(pack):
    """The serialized shader a qCompress pack holds, or None."""
    try:
        held = zlib.decompress(pack[4:])
    except zlib.error:
        return None
    return held if len(pack) >= 4 and int.from_bytes(pack[:4], "big") == len(held) else None


def check(source, write=False, rules=RULES, label="voiceorb-shader"):
    """Judge one source/pack pair against RULES; never alter the source."""
    tool = qsb_tool()
    if tool is None:
        print(f"{label}: status=not-measured missing=qsb")
        return 77
    try:
        text = source.read_text(encoding="utf-8")
        code = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)
        for rule in rules:
            if breaks(rule, code):
                print(f"{label}: refused rule={rule} source={source}")
                return 1
        with tempfile.TemporaryDirectory(prefix="vgs-qsb-") as scratch:
            output = Path(scratch) / (source.name + ".qsb")
            result = subprocess.run(
                [tool, *OPTIONS, "-o", str(output), str(source)],
                env={"PATH": "/usr/bin:/bin", "HOME": scratch, "LC_ALL": "C"},
                capture_output=True, text=True, check=False)
            if result.returncode != 0:
                print(f"{label}: compile-failed source={source} exit={result.returncode}")
                print(result.stdout + result.stderr, end="")
                return 1
            compiled = source.with_suffix(source.suffix + ".qsb")
            fresh = output.read_bytes()
            if write:
                compiled.write_bytes(fresh)
            elif (held := shader(compiled.read_bytes())) is None or held != shader(fresh):
                print(f"{label}: stale pack={compiled}")
                return 1
    except (OSError, UnicodeError) as error:
        print(f"{label}: unreadable source={source} cause={error}")
        return 1
    print(f"{label}: ok source={source}")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    raise SystemExit(check(args.source, args.write))
