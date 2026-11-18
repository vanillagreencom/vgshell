#!/usr/bin/env python3
"""Compile each shipped shader's source with Qt qsb and compare its pack.

qsb is a build/validation tool, not a runtime requirement. Find it on PATH
or in Qt's Linux tool directories; QSB overrides the lookup for test copies.
Exit 77 when it is absent. Exit 1 on unreadable, invalid, stale or forbidden
source, and on a Jarvis manifest whose orb styles cannot be read
(`shader-judge: failed orb-styles=unread ...`) or are invalid
(`shader-judge: failed orb-styles=invalid reason=...`). shaders() holds the
shipped shaders, VoiceOrb's, RadialBackdrop's, GlassSurface's lens,
vgs.voice's plasma and one jarvis-STYLE row for each orb style orb_styles()
reads, each with its source and the rules that source keeps; the judge checks
each, or the one --shader names. A source's rules are read over the text the
compiler reads: the source with each file it includes in its place.
It judges no other shader. --write
regenerates the pack. --source, with --shader, selects a disposable copy.
The qsb --qt6 targets and --qsbversion 64 are the reproducible build contract.
A pack is fresh when it holds the shader a fresh compile holds. A pack is
qCompress output, a 4-byte big-endian length and a zlib stream, and two zlib
builds deflate one shader to different bytes (zlib 1.3.2 on Arch, zlib-ng
2.3.3 on CachyOS), so the pack is compared decompressed. check() is the one
judge of a shipped pack; scripts/measure-shader.sh reads its compiler and
its orb styles.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
OPTIONS = ("--qt6", "--qsbversion", "64")
# Each rule a source may break, as a pattern over its code.
PATTERNS = {
    "loop": r"\b(?:for|while|do)\b",
    "texture": r"\b(?:sampler\w*|texture\w*|texelFetch\w*)\b",
}
# The shaders this judge holds, each with its source and the rules it keeps;
# another shipped shader is not judged here. VoiceOrb, RadialBackdrop and
# GlassSurface's lens are analytic and need no iteration. Voice's plasma is
# a short volumetric raymarch and each style of Jarvis's orb draws a bounded
# set of shells, bands, blades or strands per pixel, so each may loop, every
# loop to a constant bound. None samples a texture.
FIXED = {
    "voiceorb": (ROOT / "shell/Ui/feedback/shaders/voiceorb.frag", ("loop", "texture")),
    "radial-backdrop": (ROOT / "shell/Ui/feedback/shaders/radialbackdrop.frag", ("loop", "texture")),
    "glass-lens": (ROOT / "shell/Ui/foundation/shaders/glasslens.frag", ("loop", "texture")),
    "plasma": (ROOT / "shell/plugins/vgs.voice/shaders/plasma.frag", ("loop-bound", "texture")),
}
ORB_RULES = ("loop-bound", "texture")
JARVIS = ROOT / "shell/plugins/vgs.jarvis"
INCLUDE = re.compile(r'^[ \t]*#[ \t]*include[ \t]+"([^"]+)"[ \t]*$', re.M)


class OrbStylesRefused(ValueError):
    """The Jarvis manifest's orb styles cannot be used; the message leads
    with its stable key."""


def orb_styles(manifest=JARVIS / "manifest.json"):
    """The default and the options of the Jarvis manifest's Orb style
    setting, the one list of orb styles; each value names its style's
    shader under the plugin's shaders folder."""
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise OrbStylesRefused(f"orb-styles=unread manifest={manifest} cause={error}") from error
    try:
        styles = tuple(option["value"] for option in data["schema"]["orbStyle"]["options"])
        default = data["settings"]["orbStyle"]
    except (KeyError, TypeError) as error:
        raise OrbStylesRefused(f"orb-styles=invalid reason=no-setting missing={error}") from error
    if not styles:
        raise OrbStylesRefused("orb-styles=invalid reason=no-options")
    if default not in styles:
        raise OrbStylesRefused(f"orb-styles=invalid reason=default-not-an-option default={default}")
    return default, styles


def shaders():
    """The judge's table: the fixed shaders and one row per orb style."""
    _, styles = orb_styles()
    return {**FIXED, **{f"jarvis-{style}": (JARVIS / "shaders" / f"{style}.frag", ORB_RULES) for style in styles}}


def expanded(source, seen=()):
    """SOURCE's text with each file it includes, by a path relative to the
    including file as qsb resolves it, read in its place."""
    if source in seen:
        raise OSError(f"include cycle at {source}")
    text = source.read_text(encoding="utf-8")
    return INCLUDE.sub(lambda found: expanded(source.parent / found[1], seen + (source,)), text)


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


def check(source, write, rules, label):
    """Judge one source/pack pair against RULES; never alter the source."""
    tool = qsb_tool()
    if tool is None:
        print(f"{label}: status=not-measured missing=qsb")
        return 77
    try:
        code = re.sub(r"/\*.*?\*/|//[^\n]*", "", expanded(source), flags=re.S)
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


def main():
    try:
        table = shaders()
    except OrbStylesRefused as error:
        print(f"shader-judge: failed {error}")
        return 1
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shader", choices=list(table))
    parser.add_argument("--source", type=Path)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    if args.source is not None and args.shader is None:
        parser.error("--source needs --shader")
    status = 0
    for name in [args.shader] if args.shader is not None else list(table):
        default, rules = table[name]
        result = check(args.source or default, args.write, rules, name + "-shader")
        if result == 77:
            return 77
        status = max(status, result)
    return status


if __name__ == "__main__":
    raise SystemExit(main())
