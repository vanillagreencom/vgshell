# Sourced by scripts/sandbox-shots.sh, scripts/smoke/harness.sh and
# scripts/test-sandbox-shots.sh: export a revision's product tree.

# tree_export CHECKOUT REV DIR: extract the product tree and its
# installer files into DIR. Non-zero when git or tar fails.
tree_export() {
  local checkout="$1" rev="$2" dir="$3" package=()
  # A revision from before VGS-1195 holds no Jarvis base package, and git
  # archive refuses a path the revision lacks.
  ! git -C "$checkout" cat-file -e "$rev:.agents/skills/jarvis" 2>/dev/null || package=(.agents/skills/jarvis)
  git -C "$checkout" archive "$rev" shell bin config themes "${package[@]}" VERSION LICENSE README.md | tar -x -C "$dir"
}

# tree_harness_copy CHECKOUT TARGET TREE: make the sandbox copy the smoke
# harness runs. TREE is the product tree under test. CHECKOUT supplies the
# packaging and the smoke scripts. TREE supplies its own VERSION,
# LICENSE and README.md.
tree_harness_copy() {
  python3 - "$1" "$2" "$3" <<'PY'
import pathlib, shutil, sys
source, target, tree = map(pathlib.Path, sys.argv[1:])
for directory in ("shell", "bin", "config", "themes"):
    shutil.copytree(tree / directory, target / directory)
# The base package Jarvis copies into a home folder (backend/Core.js
# basePackage): without it Jarvis refuses every home folder as home=package.
# A tree exported from before VGS-1195 holds none.
package = pathlib.Path(".agents/skills/jarvis")
if (tree / package).is_dir():
    shutil.copytree(tree / package, target / package)
shutil.copytree(source / "packaging", target / "packaging")
shutil.copytree(source / "scripts", target / "scripts")
for file_name in ("VERSION", "LICENSE", "README.md"):
    origin = tree / file_name
    shutil.copyfile(origin, target / file_name)
PY
}

# tree_smoke_observer CHECKOUT TARGET: instrument a disposable runtime tree,
# including an installed prefix, before its read-only snapshot is taken.
tree_smoke_observer() {
  python3 - "$1" "$2" <<'PY'
import pathlib, shutil, sys
source, target = map(pathlib.Path, sys.argv[1:])
shutil.copyfile(source / "scripts/smoke/Probe.qml", target / "shell/Probe.qml")
path = target / "shell/shell.qml"
text = path.read_text()
needle = "ShellRoot {\n"
assert text.count(needle) == 1, "smoke root insertion must match once"
path.write_text(text.replace(needle, needle + "    Probe {}\n"))
path = target / "shell/Core/Config.qml"
text = path.read_text()
needle = "    id: root\n"
assert text.count(needle) == 1, "smoke Config alias insertion must match once"
path.write_text(text.replace(needle, needle + "    property alias smokeUserView: userView\n"))
path = target / "shell/Hosts/BackgroundHost.qml"
text = path.read_text()
needle = "    id: host\n"
assert text.count(needle) == 1, "smoke background observer insertion must match once"
path.write_text(text.replace(needle, needle + '    onBrokenKeysChanged: console.info("smoke: backgroundFailures=" + Object.keys(brokenKeys).length)\n'))
PY
}
