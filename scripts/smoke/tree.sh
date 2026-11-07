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
import os, pathlib, shutil, stat, sys
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
# Nix store inputs have read-only modes. Instrumentation edits this owned
# copy, while the input and any links outside the copy stay untouched.
for directory, _, files in os.walk(target, followlinks=False):
    owned = pathlib.Path(directory)
    owned.chmod(owned.stat().st_mode | stat.S_IWUSR)
    for name in files:
        owned = pathlib.Path(directory, name)
        mode = owned.lstat().st_mode
        if not stat.S_ISLNK(mode):
            owned.chmod(mode | stat.S_IWUSR)
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

# A row's acquired fixture files, not product configuration or state. The
# caller owns SOURCE and SHIM in the disposable world and stops their users
# before restore. Executable shims are kept; their diagnostic records are not
# rolled back. Nested rows acquire the outer row's actual instrumented input.
tree_fixture_files() { # capture|check|restore CHECKPOINT SOURCE... SHIM
  python3 - "$@" <<'PY'
import json, os, pathlib, stat, sys
operation, checkpoint, *targets = sys.argv[1:]
checkpoint = pathlib.Path(checkpoint)
roots = list(map(pathlib.Path, targets))
def inventory(root, commands):
    if not commands and not root.exists() and not root.is_symlink():
        return {}
    if not commands and root.is_file() and not root.is_symlink():
        return {"": ["file", stat.S_IMODE(root.stat().st_mode), root.read_bytes().hex()]}
    if root.is_symlink() or not root.is_dir():
        raise ValueError(f"fixture-root={root}")
    rows = {}
    def visit(directory):
        for item in sorted(directory.iterdir()):
            mode = item.lstat().st_mode
            name = str(item.relative_to(root))
            if stat.S_ISDIR(mode):
                visit(item)
                if not commands or any(key.startswith(name + "/") for key in rows):
                    rows[name] = ["directory", stat.S_IMODE(mode)]
            elif stat.S_ISREG(mode):
                if not commands or mode & 0o111:
                    rows[name] = ["file", stat.S_IMODE(mode), item.read_bytes().hex()]
            elif stat.S_ISLNK(mode):
                if not commands or os.access(item, os.X_OK):
                    rows[name] = ["link", os.readlink(item)]
            else:
                raise ValueError(f"fixture-entry={item}")
    visit(root)
    return rows
def read():
    return [inventory(root, index == len(roots) - 1) for index, root in enumerate(roots)]
try:
    if operation == "capture":
        checkpoint.mkdir()
        if any(not root.exists() or root.is_symlink() for root in roots):
            raise ValueError("fixture-acquisition=missing-or-linked")
        rows = read()
        # Publish only a complete acquisition. A partial capture has no reader.
        (checkpoint / "files.json").write_text(json.dumps({"targets": targets, "rows": rows}))
        print("captured")
    else:
        saved = json.loads((checkpoint / "files.json").read_text())
        rows = saved["rows"]
        if saved["targets"] != targets or not isinstance(rows, list) or len(rows) != len(roots):
            raise ValueError("fixture-checkpoint=shape")
        current = read()
        if operation == "check":
            print("clean" if current == rows else "changed")
        elif operation == "restore":
            for root, before, after in zip(roots, rows, current):
                # Remove children before parents. Never follow a replaced link.
                changed = {name for name in before.keys() | after.keys() if before.get(name) != after.get(name)}
                for name in sorted(changed & after.keys(), key=lambda name: (-name.count("/"), name)):
                    item = root / name
                    if after[name][0] == "directory":
                        if name not in before or before[name][0] != "directory":
                            item.rmdir()
                    else:
                        item.unlink()
                for name in sorted(changed & before.keys(), key=lambda name: (name.count("/"), name)):
                    item, row = root / name, before[name]
                    if row[0] == "directory":
                        item.mkdir(exist_ok=True)
                        item.chmod(row[1])
                    elif row[0] == "link":
                        item.symlink_to(row[1])
                    elif row[0] == "file":
                        item.write_bytes(bytes.fromhex(row[2]))
                        item.chmod(row[1])
                    else:
                        raise ValueError("fixture-checkpoint=entry")
            if read() != rows:
                raise ValueError("fixture-restoration=different")
            print("restored")
        else:
            raise ValueError("fixture-operation=" + operation)
except (OSError, ValueError, KeyError, TypeError) as error:
    print("fixture-files: " + str(error), file=sys.stderr)
    sys.exit(1)
PY
}
