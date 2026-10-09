#!/usr/bin/env python3
import pathlib
import shutil
import sys
import tomllib

repo = pathlib.Path(__file__).resolve().parent.parent
config = repo / "shell" / "plugins" / "vgs.voice" / "config.toml"
required = {
    "DP 1": "DP-1", "DP 2": "DP-2", "D P 1": "DP-1", "D P 2": "DP-2",
    "DP one": "DP-1", "DP two": "DP-2", "D P one": "DP-1", "D P two": "DP-2",
    "way bar": "waybar", "hyper land": "hyprland", "Quick Shell": "Quickshell", "vox type": "voxtype",
    "InVim": "Nvim", "in vim": "Nvim", "simlink": "symlink", "neary": "Niri",
    "Codeks": "Codex", "Graptile": "Greptile", "Versel": "Vercel",
}
forbidden = {"luxe", "Q one", "fiscal year 2026", "Y T D"}

def load(path: pathlib.Path):
    return tomllib.loads(path.read_text())

def verify(path: pathlib.Path):
    data = load(path)
    assert data["engine"] == "parakeet"
    assert data["osd"]["enabled"] is False
    # VGS plays the dictation sounds (the manifest's `sounds`), so voxtype's
    # own would play each a second time.
    assert data["audio"]["feedback"]["enabled"] is False
    assert data["parakeet"]["model"] == "parakeet-tdt-0.6b-v3"
    assert "meeting" not in data
    replacements = data["text"]["replacements"]
    for key, value in required.items():
        assert replacements.get(key) == value, key
    for key in forbidden:
        assert key not in replacements, key

verify(config)
scratch = repo / "tmp" / f"voice-config-control-{pathlib.os.getpid()}"
if scratch.exists():
    shutil.rmtree(scratch)
scratch.mkdir(parents=True)
try:
    controls = [
        ("osd", lambda text: text.replace("[osd]\nenabled = false", "[osd]\nenabled = true", 1)),
        ("feedback", lambda text: text.replace("[audio.feedback]\nenabled = false", "[audio.feedback]\nenabled = true", 1)),
        ("engine", lambda text: text.replace('engine = "parakeet"', 'engine = "whisper"', 1)),
        ("required replacement", lambda text: text.replace('"Versel" = "Vercel"\n', "", 1)),
        ("forbidden replacement", lambda text: text.replace('[text.replacements]\n', '[text.replacements]\n"luxe" = "LUKS"\n', 1)),
    ]
    original = config.read_text()
    for label, edit in controls:
        copy = scratch / f"{label}.toml"
        changed = edit(original)
        assert changed != original, label
        copy.write_text(changed)
        try:
            verify(copy)
        except AssertionError:
            pass
        else:
            raise AssertionError(f"control {label}: config check passed without the rule")
finally:
    shutil.rmtree(scratch)
print("test-voice-config: ok controls=5")
