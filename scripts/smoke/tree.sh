# Sourced by scripts/sandbox-shots.sh, scripts/smoke/harness.sh and
# scripts/test-sandbox-shots.sh: export a revision's product tree.

# tree_export CHECKOUT REV DIR: extract the product tree and its
# installer files into DIR. Non-zero when git or tar fails.
tree_export() {
  local checkout="$1" rev="$2" dir="$3" package=() at
  # The Jarvis base package a revision holds: none before VGS-1195, the
  # jarvis skill until VGS-1542, then the package's home render. git
  # archive refuses a path the revision lacks.
  for at in .agents/skills/jarvis packaging/jarvis-home; do
    ! git -C "$checkout" cat-file -e "$rev:$at" 2>/dev/null || package+=("$at")
  done
  git -C "$checkout" archive "$rev" shell bin config themes "${package[@]}" VERSION LICENSE README.md | tar -x -C "$dir"
}

# tree_harness_copy CHECKOUT TARGET TREE: make the sandbox copy the smoke
# harness runs. TREE is the product tree under test. CHECKOUT supplies the
# packaging, smoke scripts and documentation. TREE supplies its own VERSION.
tree_harness_copy() {
  python3 - "$1" "$2" "$3" <<'PY'
import pathlib, shutil, sys
source, target, tree = map(pathlib.Path, sys.argv[1:])
for directory in ("shell", "bin", "config", "themes"):
    shutil.copytree(tree / directory, target / directory)
shutil.copytree(source / "packaging", target / "packaging")
# The base package Jarvis copies into a home folder (backend/Core.js), the
# revision's own: without it Jarvis refuses every home folder as
# home=package. A tree exported from before VGS-1195 holds none.
for package in map(pathlib.Path, (".agents/skills/jarvis", "packaging/jarvis-home")):
    shutil.rmtree(target / package, ignore_errors=True)
    if (tree / package).is_dir():
        shutil.copytree(tree / package, target / package)
shutil.copytree(source / "scripts", target / "scripts")
for file_name in ("VERSION", "LICENSE", "README.md"):
    origin = (tree if file_name == "VERSION" else source) / file_name
    shutil.copyfile(origin, target / file_name)
PY
}

# Restore the one exported install's managed engine using the runtime's
# identity owner. The sandbox copy has no .git, so its identity is a release.
tree_harness_engine() { # TREE TARGET DATA_HOME
  local tree="$1" target="$2" data="$3" engine root
  [[ -d $tree/.engines ]] || return 0
  local engines=("$tree/.engines/"*)
  [[ ${#engines[@]} -eq 1 && -e ${engines[0]}/bin/qs ]] || return 1
  engine="$(readlink -f -- "${engines[0]}")" || return
  root="$(node - "$target/bin/lib/engine.js" "$data" "$target" <<'JS'
process.stdout.write(require(process.argv[2]).rootFor(process.argv[3], process.argv[4]));
JS
)" || return
  mkdir -p -- "${root%/*}"
  ln -s -- "$engine" "$root"
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
