#!/usr/bin/env bash
# Controls for scripts/release. Each row runs a copy of the script as
# scripts/release of a scratch git repository at version 3.4.5, tagged
# v3.4.5 at HEAD, under env -i with a fixture HOME whose url.insteadOf
# turns the GitHub URL into a local bare repository, the tag's GitHub
# stand-in. Stub gpg and gh first on PATH record their arguments: the stub
# gpg holds the secret keys STUB_GPG_SECRET names and writes a signature
# naming the sha256 of the file it signed; the stub gh records its working
# directory and the files there.
#
# The real-tree row runs the dry run on this repository's working tree, as
# `git add -A` would commit it, with a fixture fingerprint in its
# install.sh, and installs the archive it built with the archive's own
# installer and install-tree check.
#
# No production edit of `gzip -n` alone reddens the archive row: gzip reads
# a pipe, so it writes no name and a zero time either way. The row pins
# that header, and the header's XFL byte, which only `gzip -9` sets to 02.
#
# The parity rows run a channel build's host side in the release fixture,
# with a stub podman that keeps the directory the container would mount.
# The tarball the channel hands its container must be the release asset of
# the same commit, byte for byte. The fixture keeps the builder,
# scripts/lib/release-tarball.sh, out of its commit, so a row can hand the
# channel a builder copy without changing the files the tarball holds.
#
# The controls at the end run copies of the script, or of the builder, with
# one rule removed each, and the row that judges that rule must turn red on
# its copy.
# The Arch doctor row executes the package proof's Python assertion against
# private unit files and pacman ownership answers, without starting a daemon.
set -euo pipefail

# shellcheck source=scripts/vgshell-rows.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"

suite=test-release
for tool in git gzip tar sha256sum python3 makepkg; do
  command -v "$tool" >/dev/null || { echo "$suite: status=not-measured missing=$tool"; exit 77; }
done

script="$repo/scripts/release"
builder="$repo/scripts/lib/release-tarball.sh"
fpr=0123456789ABCDEF0123456789ABCDEF01234567
github=https://github.com/vanillagreencom/vgshell.git
record="$tmp/record"; stubs="$tmp/release-stubs"; scratch="$tmp/scratch"; gnupg="$tmp/gnupg-empty"
mkdir -p "$record" "$stubs" "$scratch"
mkdir -m 700 "$gnupg"

cat >"$stubs/gpg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_RECORD/gpg"
signed="${*: -1}"
case " $* " in
  *" --list-secret-keys "*)
    [[ -n ${STUB_GPG_SECRET:-} && $signed == "$STUB_GPG_SECRET" ]] ;;
  *" --export "*) printf "public-only fixture key\n" ;;
  *" --detach-sign "*)
    [[ -z ${STUB_GPG_FAIL:-} ]] || exit 2
    out=""
    while [[ $# -gt 0 ]]; do [[ $1 == --output ]] && out="$2"; shift; done
    sum="$(sha256sum -- "$signed")" || exit 2
    printf 'stub signature of %s\n' "${sum%% *}" >"$out" ;;
  *) exit 64 ;;
esac
EOF
cat >"$stubs/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_RECORD/gh"
printf '%s\n' "$(pwd -P)" >"$STUB_RECORD/gh.cwd"
ls -A >"$STUB_RECORD/gh.ls"
exit "${STUB_GH_EXIT:-0}"
EOF
cat >"$stubs/podman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_RECORD/podman"
[[ $1 != info ]] || { echo true; exit 0; }
[[ $1 == run ]] || exit 0
for ((i=1; i<=$#; i++)); do
  if [[ ${!i} == *:/output ]]; then
    output=${!i}; output=${output%:/output}
    printf 'fixture Debian asset\n' >"$output/vgshell-quickshell_0.3.2+git2b4501a+vgs4-1_debian-forky_amd64.deb"
    exit 0
  fi
done
while [[ $# -gt 0 ]]; do
  [[ $1 == -v ]] && { cp -R -- "${2%%:*}" "$STUB_RECORD/mount"; exit 0; }
  shift
done
exit 64
EOF
chmod +x "$stubs/gpg" "$stubs/gh" "$stubs/podman"

# fixture NAME SCRIPT: sets r to a new scratch repository holding SCRIPT as
# scripts/release, the builder as an ignored scripts/lib/release-tarball.sh
# and an install.sh whose release_key is $fpr, tagged
# v3.4.5 at HEAD and pushed with main to its GitHub stand-in $r.git, and h
# to a home whose git configuration reaches that stand-in. Every call makes
# new directories, so a control's copy never meets a row's repository. A
# fixture that cannot be built stops the suite.
fixtures=0
fixture() {
  fixtures=$((fixtures + 1))
  r="$tmp/rows/$fixtures-$1"
  h="$tmp/homes/$fixtures-$1"
  {
    mkdir -p "$r/scripts/lib" "$r/bin/lib" "$r/docs" "$h" &&
      cp -- "$repo/bin/lib/engine.js" "$r/bin/lib/engine.js" &&
      cp -- "$repo/scripts/debian-packages.sh" "$r/scripts/" &&
      cp -- "$2" "$r/scripts/release" && cp -- "$builder" "$r/scripts/lib/release-tarball.sh" &&
      printf '3.4.5\n' >"$r/VERSION" &&
      printf '#!/usr/bin/env bash\n{\nmain() {\n  release_key="%s"\n}\nmain "$@"\n}\n' "$fpr" >"$r/install.sh" &&
      printf 'fixture\n' >"$r/docs/README.md" &&
      printf 'dist/\ntmp/\nscripts/lib/\n' >"$r/.gitignore" &&
      g init -q "$r" && g -C "$r" add -A && g -C "$r" commit -q -m release &&
      g -C "$r" tag -a v3.4.5 -m "VGS 3.4.5" &&
      g init -q --bare "$r.git" && g -C "$r" push -q "$r.git" main v3.4.5 &&
      g config --file "$h/.gitconfig" "url.file://$r.git.insteadOf" "$github"
  } || { echo "$suite: fixture=$1" >&2; exit 1; }
}
# retag MESSAGE: moves v3.4.5 to HEAD with MESSAGE and pushes it.
retag() { g -C "$r" tag -fa v3.4.5 -m "$1" >/dev/null && g -C "$r" push -qf "$r.git" v3.4.5 2>/dev/null; }
# key_line VALUE: commits install.sh with release_key="VALUE" and retags.
key_line() { sed -i "s/^  release_key=.*/  release_key=\"$1\"/" "$r/install.sh" && g -C "$r" commit -q -am key && retag key; }

# run_file FILE ARGS...: FILE from $h. Stdout lands in $tmp/out, stderr in
# $tmp/err, the exit status in $status; the stubs' records start empty.
# RUN_SECRET replaces the key the stub gpg holds. run ARGS... runs
# $r/scripts/release.
run_git_env=()
run_file() {
  rm -rf -- "${record:?}"/*
  status=0
  env -i PATH="$stubs:$base_path" HOME="$h" GIT_CONFIG_NOSYSTEM=1 GNUPGHOME="$gnupg" TMPDIR="$scratch" \
    STUB_RECORD="$record" STUB_GPG_SECRET="${RUN_SECRET-$fpr}" STUB_GPG_FAIL="${RUN_GPG_FAIL:-}" STUB_GH_EXIT="${RUN_GH_EXIT:-0}" \
    "${run_git_env[@]}" bash "$@" >"$tmp/out" 2>"$tmp/err" </dev/null || status=$?
}
run() { run_file "$r/scripts/release" "$@"; }
first_err() { local line=""; [[ -s $tmp/err ]] && IFS= read -r line <"$tmp/err"; printf '%s' "$line"; }
last_out() { local line=""; [[ -s $tmp/out ]] && line="$(tail -n 1 -- "$tmp/out")"; printf '%s' "$line"; }
recorded() { [[ -f $record/$1 ]] && grep -qxF -- "$2" "$record/$1"; }
sha_of() { local s; s="$(sha256sum -- "$1")" && printf '%s' "${s%% *}"; }
engine_asset=vgshell-quickshell_0.3.2+git2b4501a+vgs4-1_debian-forky_amd64.deb
assets=(vgshell-3.4.5.tar.gz install.sh "$engine_asset" release-key.asc SHA256SUMS SHA256SUMS.asc)

# The rows each judge one rule, on the script SCRIPT names, so a control
# can run them again on a copy with that rule removed.

archive_row() { # SCRIPT: the tarball is git archive of the tag under vgshell-3.4.5/, gzip -9 with no name and no time
  local header want got
  fixture archive "$1"
  run 3.4.5
  [[ $status == 0 ]] || return 1
  want="$(g -C "$r" ls-tree -r --name-only v3.4.5 | sed 's|^|vgshell-3.4.5/|' | LC_ALL=C sort)" || return 1
  got="$(tar -tzf "$r/dist/vgshell-3.4.5.tar.gz" | grep -v '/$' | LC_ALL=C sort)" || return 1
  header="$(od -An -tx1 -N9 -- "$r/dist/vgshell-3.4.5.tar.gz" | tr -d ' \n')" || return 1
  [[ $got == "$want" && $header == 1f8b08000000000002 ]] &&
    grep -qxF -- "release: sha256 name=vgshell-3.4.5.tar.gz value=$(sha_of "$r/dist/vgshell-3.4.5.tar.gz")" "$tmp/out"
}
sums_row() { # SCRIPT: SHA256SUMS lists the tarball and the tag's install.sh, one line each
  fixture sums "$1"
  run 3.4.5
  [[ $status == 0 ]] || return 1
  cmp -s -- "$r/dist/install.sh" <(g -C "$r" show v3.4.5:install.sh) &&
    [[ $(cat -- "$r/dist/SHA256SUMS") == "$(sha_of "$r/dist/vgshell-3.4.5.tar.gz")  vgshell-3.4.5.tar.gz
$(sha_of "$r/dist/install.sh")  install.sh
$(sha_of "$r/dist/$engine_asset")  $engine_asset
$(sha_of "$r/dist/release-key.asc")  release-key.asc" ]]
}
sign_row() { # SCRIPT: gpg signs the published SHA256SUMS with the release key
  fixture sign "$1"
  run 3.4.5
  [[ $status == 0 ]] &&
    grep -qE -- "^--local-user $fpr --armor --detach-sign --output $r/dist/\.release\.[A-Za-z0-9]+/SHA256SUMS\.asc -- $r/dist/\.release\.[A-Za-z0-9]+/SHA256SUMS\$" "$record/gpg" &&
    [[ $(cat -- "$r/dist/SHA256SUMS.asc") == "stub signature of $(sha_of "$r/dist/SHA256SUMS")" ]]
}
upload_row() { # SCRIPT: gh creates the release from the verified tag with the four assets alone
  fixture upload "$1"
  mkdir -p "$r/dist"
  printf 'other\n' >"$r/dist/notes.txt"
  run 3.4.5
  [[ $status == 0 && $(last_out) == "release: ok tag=v3.4.5 dry-run=false" ]] &&
    recorded gh "release create --repo vanillagreencom/vgshell --verify-tag --title VGS 3.4.5 --generate-notes -- v3.4.5 ${assets[*]}" &&
    [[ $(wc -l <"$record/gh") == 1 && $(cat -- "$record/gh.cwd") == "$r/dist" ]] &&
    [[ $(cat -- "$record/gh.ls") == "$(printf '%s\n' "${assets[@]}" notes.txt | LC_ALL=C sort)" ]] &&
    [[ $(cat -- "$r/dist/notes.txt") == other ]]
}
dry_row() { # SCRIPT: --dry-run checks and builds, and neither signs nor uploads
  fixture dry "$1"
  run --dry-run 3.4.5
  [[ $status == 0 && $(last_out) == "release: ok tag=v3.4.5 dry-run=true" ]] &&
    [[ ! -e $record/gh && $(cat -- "$record/gpg") == "--batch --list-secret-keys -- $fpr"$'\n'"--batch --armor --export -- $fpr" ]] &&
    [[ -f $r/dist/vgshell-3.4.5.tar.gz && -f $r/dist/SHA256SUMS && -f $r/dist/install.sh && ! -e $r/dist/SHA256SUMS.asc ]] &&
    grep -qxF -- "release: would-sign key=$fpr name=SHA256SUMS" "$tmp/out"
}
stale_row() { # SCRIPT: an asset an earlier run left in dist/ is replaced or removed
  fixture stale "$1"
  mkdir -p "$r/dist"
  printf 'stale\n' >"$r/dist/SHA256SUMS.asc"
  printf 'stale\n' >"$r/dist/SHA256SUMS"
  run --dry-run 3.4.5
  [[ $status == 0 && ! -e $r/dist/SHA256SUMS.asc && $(cat -- "$r/dist/SHA256SUMS") != stale ]]
}
sign_failure_row() { # SCRIPT: a failed signature refuses before gh and publishes nothing into dist/
  fixture sign-failure "$1"
  RUN_GPG_FAIL=1 run 3.4.5
  [[ $status == 1 && $(first_err) == "release: refused: gpg=sign-failed key=$fpr" && ! -e $record/gh ]] &&
    [[ -z $(find "$r/dist" -mindepth 1 -print -quit) ]]
}
gh_failure_row() { # SCRIPT: a failed gh refuses
  fixture gh-failure "$1"
  RUN_GH_EXIT=1 run 3.4.5
  [[ $status == 1 && $(first_err) == "release: refused: gh=release-create tag=v3.4.5" ]]
}

# The channel builds whose host side packs the release tarball: the script
# | the tarball under the directory it mounts | the recipe there that pins
# the tarball's sum, or none | that recipe's pin line, %s for the sum.
declare -A channels=(
  [arch]="scripts/arch-packages.sh|vgshell/vgshell-3.4.5.tar.gz|vgshell/PKGBUILD|sha256sums=('%s')"
  [fedora]="scripts/fedora-container.sh|vgshell-3.4.5.tar.gz||"
)
# parity_row BUILDER CHANNEL [SCRIPT]: SCRIPT, default the channel's own,
# is committed as the channel's script.
parity_row() { # BUILDER CHANNEL [SCRIPT]: the tarball CHANNEL hands its container, packed by BUILDER, is the release asset of the same commit
  local command tarball recipe pin sum
  IFS='|' read -r command tarball recipe pin <<<"${channels[$2]}"
  fixture "parity-$2" "$script"
  { mkdir -p "$r/packaging" && cp -R -- "$repo/packaging/arch" "$r/packaging/" &&
    cp -- "$repo/scripts/arch-packages.sh" "$repo/scripts/fedora-container.sh" "$r/scripts/" &&
    cp -- "${3:-$repo/$command}" "$r/$command" && g -C "$r" add -A && g -C "$r" commit -q -m channels && retag channels; } || { echo "$suite: fixture=parity-$2" >&2; exit 1; }
  run --dry-run 3.4.5
  [[ $status == 0 ]] || return 1
  sum="$(sed -n 's/^release: sha256 name=vgshell-3\.4\.5\.tar\.gz value=\([0-9a-f]\{64\}\)$/\1/p' "$tmp/out")" || return 1
  [[ -n $sum && $sum == "$(sha_of "$r/dist/vgshell-3.4.5.tar.gz")" ]] || return 1
  cp -- "$1" "$r/scripts/lib/release-tarball.sh" && chmod 755 "$r/scripts/lib/release-tarball.sh" || return 1
  run_file "$r/$command"
  [[ $status == 0 && -f $record/mount/$tarball && $(sha_of "$record/mount/$tarball") == "$sum" ]] || return 1
  [[ -z $recipe ]] || grep -qxF -- "${pin//%s/$sum}" "$record/mount/$recipe"
}

# The Copilot harness sets this protected git option in its tool shells.
# Exercise the host runner and makepkg's real VCS source download.
arch_bare_row() { # SCRIPT
  local result=0 head copy
  run_git_env=(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=explicit)
  parity_row "$builder" arch "$1" || result=$?
  if [[ $result == 0 ]]; then
    head="$(g -C "$r" rev-parse HEAD)" &&
      copy_with arch-vcs-source "$record/mount/vgshell-git/PKGBUILD" \
        'file:///build/srcrepo.git' "file://$record/mount/srcrepo.git" &&
      cp -- "$copy" "$record/mount/vgshell-git/PKGBUILD" &&
      env -i PATH="$base_path" HOME="$h" GIT_CONFIG_NOSYSTEM=1 "${run_git_env[@]}" \
        "$BASH" -c 'cd -- "$1" && makepkg --verifysource &&
          [[ $(git --git-dir="$1/vgshell" rev-parse refs/heads/main) == "$2" ]]' \
        _ "$record/mount/vgshell-git" "$head" || result=$?
  fi
  run_git_env=()
  return "$result"
}

# Exercise the host runner across linked worktrees at its Podman boundary.
# The stand-in applies podman-run(1)'s descriptor contract, then keeps a
# cache writer alive after host death. Real package runs prove OCI wiring.
arch_cache_row() { # SCRIPT
  parity_row "$builder" arch "$1" || return 1
  "${base_env[@]}" python3 - "$r" "$tmp/arch-cache-$fixtures" "$BASH" "$base_path" <<'PY'
import fcntl, os, pathlib, select, shutil, signal, subprocess, sys, time

root, area, bash = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
area.mkdir()
tools = {name: shutil.which(name, path=sys.argv[4]) for name in ("flock", "git")}
assert all(tools.values()), tools
env = dict(os.environ, PATH=str(area) + ":" + sys.argv[4], CACHE_PROBE=str(area))
def git(*args):
    return subprocess.check_output([tools["git"], "-C", str(root), *args], env=env, text=True).strip()

lane = area / "lane"
git("worktree", "add", "--detach", str(lane), "HEAD")
(lane / "scripts/lib").mkdir(exist_ok=True)
shutil.copyfile(root / "scripts/lib/release-tarball.sh", lane / "scripts/lib/release-tarball.sh")
(lane / "scripts/lib/release-tarball.sh").chmod(0o755)
(area / "flock").write_text("#!" + bash + '\n: >"$CACHE_PROBE/$CACHE_CASE-$CACHE_LANE.arrived"\nexec ' +
                           tools["flock"] + ' "$@"\n')
(area / "flock").chmod(0o755)
(area / "podman").write_text("""#!/usr/bin/python3
import os, pathlib, shutil, sys, time
if sys.argv[1] != "run":
    sys.exit(0)
area = pathlib.Path(os.environ["CACHE_PROBE"])
key = os.environ["CACHE_CASE"] + "-" + os.environ["CACHE_LANE"]
cache = next(pathlib.Path(v.split(":")[0]) for v in sys.argv if v.endswith(":/var/cache/pacman/pkg"))
# A non-preserved descriptor must not survive the container boundary.
if "--preserve-fds=1" not in sys.argv:
    try:
        os.close(3)
    except OSError:
        pass
(area / (key + ".cache")).write_text(str(cache))
pending = cache / ("download-" + key)
pending.mkdir()
(pending / "partial").write_bytes(b"pending")
(area / (key + ".entered")).write_text(str(os.getpid()))
deadline = time.monotonic() + 15
while not (area / (key + ".release")).exists():
    if time.monotonic() >= deadline:
        sys.exit(91)
    time.sleep(.01)
# The production EXIT cleanup runs while the inherited lock is still held.
for path in cache.glob("download-*"):
    shutil.rmtree(path)
(cache / (key + ".pkg.tar.zst")).write_bytes(b"complete")
(area / (key + ".ended")).touch()
""")
(area / "podman").chmod(0o755)
cache = pathlib.Path(git("rev-parse", "--path-format=absolute", "--git-common-dir")) / "arch-packages"
def await_file(path, child=None):
    deadline = time.monotonic() + 10
    while not path.exists():
        if child is not None and child.poll() is not None:
            raise AssertionError(("early-exit", path.name, child.returncode))
        if time.monotonic() >= deadline:
            raise AssertionError(("barrier-timeout", path.name))
        time.sleep(.01)
def held():
    with (cache / ".lock").open("a") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        return False

children = []
writers = []
try:
    # One host-lifetime contract: normal exit, TERM and untrappable KILL.
    for label, sig in (("normal", None), ("term", signal.SIGTERM), ("kill", signal.SIGKILL)):
        current = []
        for which, tree in (("first", root), ("second", lane)):
            log = (area / (label + "-" + which + ".log")).open("w")
            child = subprocess.Popen([bash, str(tree / "scripts/arch-packages.sh")], env=dict(
                env, CACHE_CASE=label, CACHE_LANE=which), stdin=subprocess.DEVNULL,
                stdout=log, stderr=log, start_new_session=True)
            log.close()
            children.append(child)
            current.append(child)
            key = label + "-" + which
            if which == "first":
                await_file(area / (key + ".entered"), child)
                writers.append(os.pidfd_open(int((area / (key + ".entered")).read_text())))
                assert pathlib.Path((area / (key + ".cache")).read_text()) == cache, "cache-not-common"
                assert held(), "cache-not-locked"
                if sig is not None:
                    child.send_signal(sig)
                    assert child.wait(timeout=10) == -sig
                    assert held(), "cache-unlocked-before-container-exit"
            else:
                await_file(area / (key + ".arrived"), child)
                assert held(), "cache-unlocked-before-cleanup"
                assert not (area / (key + ".entered")).exists(), "second-entered-before-cleanup"
                assert (cache / ("download-" + label + "-first") / "partial").read_bytes() == b"pending"
                (area / (label + "-first.release")).touch()
                await_file(area / (label + "-first.ended"))
                await_file(area / (key + ".entered"), child)
                writers.append(os.pidfd_open(int((area / (key + ".entered")).read_text())))
                assert pathlib.Path((area / (key + ".cache")).read_text()) == cache, "cache-not-common"
                assert (cache / (label + "-first.pkg.tar.zst")).read_bytes() == b"complete"
                assert not (cache / ("download-" + label + "-first")).exists()
                (area / (key + ".release")).touch()
                assert child.wait(timeout=10) == 0
        if sig is None:
            assert current[0].wait(timeout=10) == 0
        assert not held(), "cache-lock-leaked"
        assert not list(cache.glob("download-*")), "pending-downloads-kept"
        assert (cache / (label + "-second.pkg.tar.zst")).read_bytes() == b"complete"
        print("arch-cache=ok case=" + label)
finally:
    if sys.exc_info()[0] is not None:
        for path in sorted(area.glob("*.log")):
            print(path.name + ":\n" + path.read_text(), file=sys.stderr)
    # pidfds retain each writer's identity after its host has been reaped.
    for fd in writers:
        try:
            signal.pidfd_send_signal(fd, signal.SIGKILL)
        except ProcessLookupError:
            pass
        assert select.select([fd], [], [], 10)[0], "writer-stop-timeout"
        os.close(fd)
    for child in children:
        if child.poll() is None:
            child.kill()
        child.wait(timeout=10)
    git("worktree", "remove", "--force", str(lane))
PY
}

# Refusals before anything is written: name | the fixture change | the
# arguments | exit status | the first stderr line, %r the repository and
# %h its HEAD. Each leaves no dist/ and calls no gh.
tweak_none() { :; }
tweak_dirty() { printf 'x\n' >"$r/untracked"; }
tweak_untagged() { g -C "$r" tag -d v3.4.5 >/dev/null; }
tweak_moved() { printf 'more\n' >>"$r/docs/README.md" && g -C "$r" commit -q -am more; }
tweak_unpushed() { g -C "$r.git" tag -d v3.4.5 >/dev/null; }
tweak_retagged() { g -C "$r" tag -fa v3.4.5 -m "VGS 3.4.5 again" >/dev/null; }
tweak_unset() { key_line ""; }
tweak_lower() { key_line 0123456789abcdef0123456789abcdef01234567; }
tweak_twice() { printf '  release_key=""\n' >>"$r/install.sh" && g -C "$r" commit -q -am twice && retag twice; }
declare -A refusals=(
  [no-argument]="tweak_none||2|release: refused: argument=missing"
  [not-a-version]="tweak_none|1.2|2|release: refused: version=1.2 reason=not-a-version"
  [version-mismatch]="tweak_none|3.4.6|1|release: refused: version=mismatch want=3.4.5 got=3.4.6"
  [dirty]="tweak_dirty|3.4.5|1|release: refused: tree=dirty path=%r"
  [tag-missing]="tweak_untagged|3.4.5|1|release: refused: tag=missing name=v3.4.5"
  [tag-not-head]="tweak_moved|3.4.5|1|release: refused: tag=not-head name=v3.4.5 commit=* head=%h"
  [key-unset]="tweak_unset|3.4.5|1|release: refused: release-key=unset path=install.sh"
  [key-malformed]="tweak_lower|3.4.5|1|release: refused: release-key=malformed value=0123456789abcdef0123456789abcdef01234567 path=install.sh"
  [key-twice]="tweak_twice|3.4.5|1|release: refused: release-key=unreadable path=install.sh count=2"
  [no-secret-key]="tweak_none|3.4.5|1|release: refused: release-key=no-secret-key key=$fpr"
  [tag-not-pushed]="tweak_unpushed|3.4.5|1|release: refused: tag=not-pushed name=v3.4.5 url=$github"
  [tag-differs]="tweak_retagged|3.4.5|1|release: refused: tag=differs name=v3.4.5 local=* remote=*"
)
refusal_row() { # SCRIPT NAME
  local entry tweak args want_status want_err err
  entry="${refusals[$2]}"
  IFS='|' read -r tweak args want_status want_err <<<"$entry"
  fixture "refuse-$2" "$1"
  "$tweak" || { echo "$suite: fixture=$tweak" >&2; exit 1; }
  want_err="${want_err//%r/$r}"
  want_err="${want_err//%h/$(g -C "$r" rev-parse HEAD)}"
  # shellcheck disable=SC2086 # args holds zero or one word
  if [[ $2 == no-secret-key ]]; then RUN_SECRET="" run $args; else run $args; fi
  err="$(first_err)" || return 1
  # shellcheck disable=SC2053 # want_err is a glob: * stands for an object id
  [[ $status == "$want_status" && $err == $want_err && ! -e $r/dist && ! -e $record/gh ]]
}

# Execute the package consumer's assertions against setup's machine-read lines.
# Other targets' wiring rows must not hide the chromium state or reject it.
arch_setup_row() { # SCRIPT
  "${base_env[@]}" python3 - "$1" "$BASH" <<'PY'
import os, re, subprocess, sys
source = open(sys.argv[1]).read()
checks = re.findall(r'^  (.+) \|\| refuse "setup=unexpected browser=(absent|chromium) package=\$1" "\$out"$', source, re.M)
assert {browser for _, browser in checks} == {"absent", "chromium"}, checks
for expression, browser in checks:
    wanted = "not-detected" if browser == "absent" else "done"
    line = "setup=chromium command=vgshell-browser-policy state=" + wanted
    wiring = "\nwiring=oh-my-posh state=not-wired file=/home/builder/.bashrc"
    for output, accepted in [
        (line, True), (line + wiring, True), (wiring.lstrip(), False),
        (line.replace(wanted, "absent"), False),
        (line.replace(wanted, "done" if wanted == "not-detected" else "not-detected") + wiring, False),
        (line + "-unexpected" + wiring, False), ("prefix " + line + wiring, False)
    ]:
        result = subprocess.run([sys.argv[2], "-c", 'out="$1"; ' + expression, "_", output], env=os.environ, capture_output=True)
        assert result.returncode == (0 if accepted else 1), (browser, output, result.returncode, result.stderr)
PY
}

# Execute the installed-provider judge itself. Only its fixed unit directory
# changes in the disposable copy; the unit bytes, executable and ownership
# answers belong to the fixture. No host package manager is called.
arch_doctor_row() { # SCRIPT
  "${base_env[@]}" python3 - "$1" "$tmp/arch-doctor" <<'PY'
import json, pathlib, re, subprocess, sys
source = pathlib.Path(sys.argv[1]).read_text()
blocks = re.findall(r"^  python - \"\$report\" <<'PY_DOCTOR'[^\n]*\n(.*?)^PY_DOCTOR$", source, re.M | re.S)
assert len(blocks) == 1, "one doctor assertion"
root = pathlib.Path(sys.argv[2])
units = root / "systemd/system"
units.mkdir(parents=True, exist_ok=True)
binary = root / "NetworkManager"
binary.write_text("fixture executable, never started\n")
binary.chmod(0o755)
unit = units / "NetworkManager.service"
initrd = units / "NetworkManager-config-initrd.service"
# These forms come from the networkmanager 1.58.1-3 Arch package: the
# config-initrd command ends its continuation with an unindented quote;
# initrd conditions and the main unit's Also entries repeat.
initrd.write_text("[Service]\nType=oneshot\nExecStartPost=/bin/sh -c ' \\\n    for i in /run/NetworkManager/*; do \\\n        break; \\\n    done; \\\n'\nRemainAfterExit=yes\n")
code = blocks[0]
fixed = 'pathlib.Path("/usr/lib/systemd/system")'
assert code.count(fixed) == 1, "one installed unit directory"
judge = root / "judge.py"
judge.write_text(code.replace(fixed, "pathlib.Path(" + repr(str(units)) + ")"))
stubs = root / "bin"
stubs.mkdir(exist_ok=True)
pacman = stubs / "pacman"
pacman.write_text("#!" + sys.executable + "\n" + '''import json, os, sys
data = json.load(open(os.environ["PACMAN_FIXTURE"]))
if sys.argv[1:] == ["-Qlq", "--", "networkmanager"]:
    print(data["files"])
    sys.exit(data.get("list_status", 0))
if sys.argv[1:3] == ["-Qqo", "--"] and len(sys.argv) == 4:
    print(data["owners"].get(sys.argv[3], ""))
    sys.exit(data.get("owner_status", 0))
sys.exit(99)
''')
pacman.chmod(0o755)
name = "org.freedesktop.NetworkManager"
valid = ("[Unit]\nConditionPathExistsGlob=|/usr/lib/NetworkManager/system-connections/*\n"
         "ConditionPathExistsGlob=|/run/NetworkManager/system-connections/*\n"
         "[Service]\nType=dbus\nBusName=" + name + "\nExecStart=" + str(binary) + " --no-daemon\n"
         "[Install]\nAlso=NetworkManager-dispatcher.service\nAlso=NetworkManager-wait-online.service\n")
row = {"name": name, "bus": "system", "packages": {"pacman": "networkmanager"},
       "optional": False, "onRequest": False, "state": "missing"}
missing = "doctor-required=missing"
cases = [
    ("installed-inactive", {}, 0, ""),
    ("present", {"row": {"state": "present"}, "files": ""}, 0, ""),
    ("optional", {"row": {"optional": True}, "files": ""}, 0, ""),
    ("on-request", {"row": {"onRequest": True}, "files": ""}, 0, ""),
    ("command", {"row": {"bus": None}}, 1, missing),
    ("session", {"row": {"bus": "session"}}, 1, missing),
    ("package-undeclared", {"row": {"packages": {}}}, 1, missing),
    ("unit-absent", {"files": ""}, 1, missing),
    ("type-absent", {"unit": valid.replace("Type=dbus\n", "")}, 1, missing),
    ("type-wrong", {"unit": valid.replace("Type=dbus", "Type=simple")}, 1, missing),
    ("name-absent", {"unit": valid.replace("BusName=" + name + "\n", "")}, 1, missing),
    ("name-wrong", {"unit": valid.replace(name, name + ".Other")}, 1, missing),
    ("exec-absent", {"unit": valid.split("ExecStart=")[0]}, 1, missing),
    ("exec-relative", {"unit": valid.replace(str(binary), "NetworkManager")}, 1, missing),
    ("exec-expanded", {"unit": valid.replace(str(binary), "%t/NetworkManager")}, 1, missing),
    ("exec-missing", {"unit": valid.replace(str(binary), str(binary) + "-absent")}, 1, missing),
    ("exec-not-executable", {"mode": 0o644}, 1, missing),
    ("unit-owner", {"owners": {str(unit): "another-package", str(binary): "networkmanager"}}, 1, missing),
    ("exec-owner", {"owners": {str(unit): "networkmanager", str(binary): "another-package"}}, 1, missing),
    ("list-failed", {"list_status": 1}, 1, "doctor-provider=query-failed"),
    ("owner-failed", {"owner_status": 1}, 1, "doctor-provider=query-failed"),
    ("unit-unreadable", {"files": str(units / "absent.service")}, 1, "doctor-provider=unit-unreadable"),
]
for label, change, status, category in cases:
    unit.write_text(change.get("unit", valid))
    binary.chmod(change.get("mode", 0o755))
    evidence = {"files": str(initrd) + "\n" + str(unit), "owners": {str(unit): "networkmanager", str(binary): "networkmanager"}}
    evidence.update({key: value for key, value in change.items() if key in ("files", "owners", "list_status", "owner_status")})
    evidence_file = root / "pacman.json"
    evidence_file.write_text(json.dumps(evidence))
    report = {"core": [], "plugins": {"fixture": [dict(row, **change.get("row", {}))]}}
    result = subprocess.run([sys.executable, str(judge), json.dumps(report)],
                            env={"PATH": str(stubs), "PACMAN_FIXTURE": str(evidence_file)}, capture_output=True, text=True)
    got = result.stderr.split(maxsplit=1)[0] if result.stderr else ""
    if result.returncode != status or got != category:
        print(f"arch-doctor=contract case={label} status={result.returncode} category={got} want-status={status} want-category={category}")
        print(result.stderr)
        sys.exit(3)
PY
}

echo "rows"
check "the release archive is the tag under vgshell-3.4.5/ with no gzip name or time" archive_row "$script"
check "SHA256SUMS lists the archive and the tag's install.sh" sums_row "$script"
check "the release key signs the published SHA256SUMS" sign_row "$script"
check "gh creates the release from the verified tag with the four assets" upload_row "$script"
check "--dry-run neither signs nor uploads" dry_row "$script"
check "assets an earlier run left in dist/ are replaced or removed" stale_row "$script"
check "a failed signature uploads nothing" sign_failure_row "$script"
check "a failed gh refuses" gh_failure_row "$script"
for name in $(printf '%s\n' "${!channels[@]}" | LC_ALL=C sort); do
  check "parity: the $name build hands its container the release asset of its commit" parity_row "$builder" "$name"
done
check "Arch host preparation and makepkg VCS sources accept explicit bare repositories" arch_bare_row "$repo/scripts/arch-packages.sh"
check "Arch worktrees share cache ownership through container cleanup after host death" arch_cache_row "$repo/scripts/arch-packages.sh"
check "Arch setup reads the chromium state independently of other target rows" arch_setup_row "$repo/scripts/arch-packages.sh"
check "Arch doctor accepts only an installed package-owned system bus provider" arch_doctor_row "$repo/scripts/arch-packages.sh"
for name in $(printf '%s\n' "${!refusals[@]}" | LC_ALL=C sort); do
  check "refusal: $name" refusal_row "$script" "$name"
done

# The dry run on this repository's working tree, with a fixture release
# key pinned in its install.sh and its tag pushed to a stand-in.
real_tree_row() {
  local version dest unpacked
  r="$tmp/real"
  work_tree_repo "$r"
  version="$(cat -- "$r/VERSION")"
  python3 - "$r/install.sh" "$fpr" <<'PY' || return 1
import re, sys
path, fpr = sys.argv[1:]
text = open(path).read()
changed, n = re.subn(r'^(\s*release_key=)"[^"]*"$', lambda m: m.group(1) + '"' + fpr + '"', text, flags=re.M)
if n != 1:
    sys.exit("release_key assignments: %d" % n)
open(path, "w").write(changed)
PY
  h="$tmp/homes/real"
  { g -C "$r" commit -q -am "pin a fixture release key" && g -C "$r" tag -a "v$version" -m "VGS $version" &&
    g init -q --bare "$r.git" && g -C "$r" push -q "$r.git" "v$version" && mkdir -p "$h" &&
    g config --file "$h/.gitconfig" "url.file://$r.git.insteadOf" "$github"; } || { echo "$suite: fixture=real-tree" >&2; exit 1; }
  run --dry-run "$version"
  [[ $status == 0 && $(last_out) == "release: ok tag=v$version dry-run=true" ]] || { cat -- "$tmp/err"; return 1; }
  # The archive holds exactly the tag's files, and installs with its own
  # installer into the tree its own manifest lists.
  unpacked="$tmp/real-unpacked"; dest="$tmp/real-dest"
  mkdir -p "$unpacked" && tar -C "$unpacked" -xzf "$r/dist/vgshell-$version.tar.gz" || return 1
  [[ $(ls -A "$unpacked") == "vgshell-$version" && $(cat -- "$unpacked/vgshell-$version/VERSION") == "$version" ]] &&
    [[ $(cd -- "$unpacked/vgshell-$version" && find . -type f -o -type l | sed 's|^\./||' | LC_ALL=C sort) == "$(g -C "$r" ls-tree -r --name-only "v$version" | LC_ALL=C sort)" ]] &&
    env DESTDIR="$dest" PREFIX=/usr "$unpacked/vgshell-$version/packaging/install-system.sh" >/dev/null &&
    "$unpacked/vgshell-$version/scripts/check-install-tree.sh" "$dest" /usr >/dev/null
}
check "the dry run on this working tree builds an archive that installs" real_tree_row

echo "controls"
copy_with arch-cache "$repo/scripts/arch-packages.sh" 'podman run --rm --preserve-fds=1' 'podman run --rm --preserve-fds=0'
if arch_cache_row "$copy" >"$tmp/arch-cache-control" 2>&1; then
  fail "control: a host-only cache lock passed the Arch cache row"
elif grep -q 'cache-unlocked-before-container-exit' "$tmp/arch-cache-control"; then
  ok "control: the Arch cache row rejects release before container exit"
else
  cat -- "$tmp/arch-cache-control"
  fail "control: the Arch cache row failed outside inherited ownership"
fi
copy_with arch-doctor "$repo/scripts/arch-packages.sh" \
  'for path in (name, executable)' 'for path in ()'
doctor_control=0
arch_doctor_row "$copy" >"$tmp/arch-doctor-control" 2>&1 || doctor_control=$?
if [[ $doctor_control == 3 ]] && grep -q '^arch-doctor=contract case=unit-owner ' "$tmp/arch-doctor-control"; then
  cat -- "$tmp/arch-doctor-control"
  ok "control: accepting an unowned unit fails the Arch provider row"
else
  fail "control: Arch provider row did not reject the ownership bypass"
  cat -- "$tmp/arch-doctor-control"
fi
copy_with arch-setup "$repo/scripts/arch-packages.sh" \
  'grep -qxF -e "setup=chromium command=vgshell-browser-policy state=not-detected" <<<"$out"' \
  '[[ $out == "setup=chromium command=vgshell-browser-policy state=not-detected" ]]'
if arch_setup_row "$copy" >"$tmp/arch-setup-control" 2>&1; then
  fail "control: whole-answer matching passed the Arch setup row"
else
  ok "control: whole-answer matching rejects the multi-line setup answer"
fi
copy_with arch-bare "$repo/scripts/arch-packages.sh" \
  'git --git-dir="$scratch/in/srcrepo.git" symbolic-ref' 'git -C "$scratch/in/srcrepo.git" symbolic-ref'
if arch_bare_row "$copy" >/dev/null; then
  fail "control: implicit bare repository passed the Arch row"
elif [[ $status == 1 ]] && grep -q '^arch-packages: refused: git=symbolic-ref path=' "$tmp/out"; then
  ok "control: implicit bare repository fails at host symbolic-ref"
else
  fail "control: implicit bare repository failed outside host symbolic-ref"
fi
# rule NAME ROW NEEDLE REPLACEMENT [ROW_ARG]: a copy of the script without
# one rule, NEEDLE replaced, on which ROW must fail.
rule() {
  copy_with "$1" "$script" "$3" "$4"
  if "$2" "$copy" ${5:+"$5"} >/dev/null; then fail "control: $1: $2 passed on the copy"; else ok "control: a copy without the $1 rule"; fi
}
rule version refusal_row '[[ $version == "$want" ]] ||' '[[ $version == "$version" ]] ||' version-mismatch
rule dirty-tree refusal_row '[[ -z $changes ]] ||' 'true ||' dirty
rule tag-at-head refusal_row '[[ $tag_commit == "$head" ]] ||' '[[ $tag_commit == "$tag_commit" ]] ||' tag-not-head
rule tag-pushed refusal_row '[[ -n $remote_object ]] ||' 'true ||' tag-not-pushed
rule same-tag refusal_row '[[ $remote_object == "$tag_object" ]] ||' 'true ||' tag-differs
rule key-set refusal_row '[[ -n $key ]] ||' 'true ||' key-unset
rule key-format refusal_row '[[ $key =~ ^([0-9A-F]{40}|[0-9A-F]{64})$ ]] ||' 'true ||' key-malformed
rule secret-key refusal_row 'gpg --batch --list-secret-keys -- "$key" >/dev/null 2>&1 ||' 'true ||' no-secret-key
rule archive-version archive_row '"$tag_commit" "$version" "$stage/$archive"' '"$tag_commit" "0.0.0" "$stage/$archive"'
rule sums-cover-installer sums_row 'sha256sum -- "$archive" install.sh "$engine_asset" release-key.asc >SHA256SUMS' 'sha256sum -- "$archive" >SHA256SUMS'
rule signing-key sign_row '--local-user "$key" ' ''
rule verify-tag upload_row '--repo "$repository" --verify-tag' '--repo "$repository"'
rule dry-run-signs-nothing dry_row 'if [[ $dry_run == false ]]; then' 'if true; then'
rule stale-assets stale_row 'rm -f -- "${dist:?}/$name" ||' 'true ||'
rule sign-failure sign_failure_row '"$stage/SHA256SUMS" ||' '"$stage/SHA256SUMS" || true ||'
rule gh-failure gh_failure_row '(cd -- "$dist" && "${create[@]}") ||' '(cd -- "$dist" && "${create[@]}") || true ||'
# builder_rule NAME NEEDLE REPLACEMENT: a builder copy that packs another
# way, NEEDLE replaced, handed to each channel alone; every channel's parity
# row must fail on it.
builder_rule() {
  local name
  copy_with "builder-$1" "$builder" "$2" "$3"
  for name in $(printf '%s\n' "${!channels[@]}" | LC_ALL=C sort); do
    if parity_row "$copy" "$name" >/dev/null; then fail "control: builder-$1: parity_row $name passed on the copy"; else ok "control: the $name parity row fails on a builder that changes the $1"; fi
  done
}
builder_rule prefix '--prefix="vgshell-$version/"' '--prefix="vgshell/"'
builder_rule compression '| gzip -n -9 >"$out"' '| gzip -n >"$out"'
# channel_rule CHANNEL NEEDLE REPLACEMENT: a copy of the channel's script
# that packs its tarball under another name; its parity row must fail.
channel_rule() {
  local command
  command="${channels[$1]%%|*}"
  copy_with "channel-$1" "$repo/$command" "$2" "$3"
  if parity_row "$builder" "$1" "$copy" >/dev/null; then fail "control: channel-$1: parity_row passed on the copy"; else ok "control: the $1 parity row fails on a channel copy that passes the builder another version"; fi
}
channel_rule arch '"$commit" "$version" "$scratch/in/vgshell/' '"$commit" "$commit" "$scratch/in/vgshell/'
channel_rule fedora '"$head" "$version" "$work/' '"$head" "$head" "$work/'

rows_done "$suite"
