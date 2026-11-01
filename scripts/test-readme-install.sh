#!/usr/bin/env bash
# Controls for the host side of scripts/readme-install.sh. The containers
# themselves are the runner's own hand run; here stub podman, git and curl
# on a PATH of only the tools the runner calls answer instead. Each row
# runs a copy of the runner in a scratch tree holding the files
# scripts/check-readme.js reads, and pins the exit status and the keyed
# first line. The rows: an unknown argument, a README check-readme refuses,
# no podman, an AUR probe that fails or answers no result list, a COPR
# probe that fails or answers neither 200 nor 404, a COPR package with no
# succeeded build, a release probe that fails, a curl download that fails
# with no output, each fence in its own container, and dnf answered `y`.
# Under STUB_PODMAN_WORKS the stub podman runs each `exec` on the host in a
# scratch home, where every command the README names is a stub, and records
# each container it starts and each command it runs. COPR answers 404 unless
# STUB_COPR_PUBLISHED is set, so the rows that plant no COPR state skip the
# Fedora fence. The controls: a runner copy that reads a failed release or
# COPR probe as an answer must fail its probe row, one without pipefail must
# fail the download row, and one that answers dnf with the default must
# fail the `y` row.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd -P)"
tmp="$(mktemp -d)" || { echo "test-readme-install: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "test-readme-install: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)"
trap 'rm -rf -- "${tmp:?}"' EXIT
failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

# --- the tree ---------------------------------------------------------------
tree="$tmp/tree"
files=(README.md VERSION bin/vgshell bin/vgshell-scan bin/lib/qml-library.js install.sh docs/architecture/runtime.md shell/Core/PackageManagers.js
  packaging/arch/vgshell/PKGBUILD packaging/arch/vgshell-git/PKGBUILD
  packaging/fedora/copr-project packaging/fedora/vgshell.spec packaging/fedora/vgshell-git.spec
  scripts/readme-install.sh scripts/check-readme.js)
for dir in "$repo"/shell/plugins/*/; do
  dir="${dir%/}"
  [[ -f $dir/manifest.json ]] || continue
  files+=("shell/plugins/${dir##*/}/manifest.json")
  [[ ! -f $dir/README.md ]] || files+=("shell/plugins/${dir##*/}/README.md")
done
for rel in "${files[@]}"; do
  mkdir -p -- "$tree/$(dirname -- "$rel")"
  cp -p -- "$repo/$rel" "$tree/$rel"
done
python3 - "$tree/scripts/check-readme.js" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = 'command: c.command })'
assert text.count(old) == 1
path.write_text(text.replace(old, 'command: c.command + (process.env.STUB_MALFORMED_COMMAND ? " )" : "") })'))
PY
version="$(<"$tree/VERSION")"

# --- PATH -------------------------------------------------------------------
# The farm holds only what the runner and check-readme call; stubs/ adds
# podman, git and curl, each answering from STUB_* in its environment.
farm="$tmp/farm"
stubs="$tmp/stubs"
mkdir -p -- "$farm" "$stubs"
for tool in bash env readlink realpath dirname mkdir mktemp rm cp ln mv chown cat tail sed grep python3 yes sleep timeout script chmod bwrap; do
  found="$(command -v -- "$tool")" || { echo "test-readme-install: status=not-measured missing=$tool"; exit 77; }
  ln -s -- "$(readlink -f -- "$found")" "$farm/$tool"
done
# node on PATH may be a version-manager shim that reads the developer's own
# configuration; the farm links the binary it resolves to.
node_bin="$(node -e 'process.stdout.write(process.execPath)')" || { echo "test-readme-install: status=not-measured missing=node"; exit 77; }
ln -s -- "$node_bin" "$farm/node"
cat >"$stubs/podman" <<'EOF'
#!/usr/bin/env bash
# Without STUB_PODMAN_WORKS every image is absent and every pull fails.
[[ -n ${STUB_PODMAN_WORKS:-} ]] || exit 1
case "$1" in
  image|commit|rm|rmi) exit 0 ;;
  inspect)
    if [[ -n ${STUB_VOLUME_CANDIDATE:-} ]]; then printf '%s\n' "$STUB_VOLUME_CANDIDATE"; exit 0; fi
    cat "$STUB_RECORD.${@: -1}.volume"
    exit ;;
  volume)
    if [[ $2 == inspect ]]; then printf '%s\n' "$STUB_HOME"; exit 0; fi
    printf 'volume-rm %s\n' "${@: -1}" >>"$STUB_RECORD"
    exit 0 ;;
  cp)
    shift
    [[ $1 != -- ]] || shift
    source="${1#*:}"
    [[ $source != /nix/store/* ]] || source="$STUB_HOME/store/store/${source#/nix/store/}"
    cp -a -- "$source" "$2"
    exit ;;
  run)
    shift
    [[ $1 == -d ]] || { printf 'prepare %s\n' "${@: -1}" >>"$STUB_RECORD"; exit 0; }
    printf 'start %s\n' "$3" >>"$STUB_RECORD"
    if [[ $* == *'vgs-validate-nix-2.35.2:/nix'* ]]; then
      printf 'vgs-validate-nix-2.35.2\n' >"$STUB_RECORD.$3.volume"
    else
      printf 'private-nix-%s\n' "$3" >"$STUB_RECORD.$3.volume"
    fi
    exit 0 ;;
  exec)
    export STUB_OCI_USER=root
    while [[ $1 != -- ]]; do
      if [[ $1 == -e ]]; then export "$2"; shift; fi
      if [[ $1 == --user ]]; then export STUB_OCI_USER="$2"; shift; fi
      shift
    done
    container="$2"
    case "$container" in
      vgs-readme-install-3.*|vgs-readme-install-5.*|vgs-readme-install-6.*|vgs-readme-install-7.*) export STUB_VERSION="${STUB_CHECKOUT_VERSION:-$STUB_VERSION}" ;;
      *) export STUB_VERSION="${STUB_PACKAGE_VERSION:-$STUB_VERSION}" ;;
    esac
    shift 2
    [[ $1 != install ]] || exit 0
    if [[ $1 == chown ]]; then printf 'private-owner %s %s\n' "$container" "${@: -1}" >>"$STUB_RECORD"; exit 0; fi
    # An early consumer exit can SIGPIPE the export under pipefail.
    if [[ $1 == nix-store && $2 == --import ]]; then exec cat >/dev/null; fi
    [[ $1 != nix-store || $2 != --add-root ]] || exit 0
    [[ $1 != rm || ${@: -1} != */dependency-proof ]] || exit 0
    [[ $1 != bash || $2 != -n ]] || exec "$@"
    if [[ $* == *'VGS install test'* ]]; then
      [[ -n ${STUB_REAL_ACCOUNT_FILES:-} ]] || exit 0
      # /home may hide the fixture's PATH farm and account store-link targets.
      exec bwrap --ro-bind / / --bind "$STUB_ACCOUNT_ETC" /etc --bind "$STUB_ACCOUNT_HOME" /home \
        --bind "$STUB_FIXTURE_ROOT" "$STUB_FIXTURE_ROOT" "$@"
    fi
    if [[ $* == *'id -u'* ]]; then [[ $STUB_OCI_USER == user ]]; exit; fi
    if [[ $1 == cat && $2 == /vgs-runtime-path ]]; then printf '%s\n' "$PATH"; exit 0; fi
    if [[ $1 == cat && $2 == /vgs-runtime-output ]]; then printf '%s\n' "$STUB_HOME/vgshell"; exit 0; fi
    if [[ $1 == cat && $2 == /vgs-runtime-closure ]]; then printf '/nix/store/fixture\n'; exit 0; fi
    if [[ $* == *'engine.js" path'* ]]; then printf '%s\n' "$STUB_HOME/.engines/git-original/bin"; exit 0; fi
    if [[ $1 == du ]]; then printf '%s\t/nix/store/fixture\n' "${STUB_CLOSURE_BYTES:-15}"; exit 0; fi
    printf 'exec %s %s\n' "$container" "${@: -1}" >>"$STUB_RECORD"
    cd -- "$STUB_HOME" && HOME="$STUB_HOME" exec "$@" ;;
  *) exit 64 ;;
esac
EOF
cat >"$stubs/curl" <<'EOF'
#!/usr/bin/env bash
# The AUR probe answers from STUB_CURL_*; the COPR probe from STUB_COPR_*,
# its body and then the status line `-w` asks for; a README download from
# STUB_FETCH_EXIT, failing with no output, else an empty script.
if [[ $* == *copr.fedorainfracloud.org* ]]; then
  [[ -z ${STUB_COPR_EXIT:-} ]] || { echo "curl: (7) stub failure" >&2; exit "$STUB_COPR_EXIT"; }
  if [[ -z ${STUB_COPR_PUBLISHED:-} ]]; then printf '{"error": "stub"}\n404'; exit 0; fi
  if [[ $* == *packagename=* ]]; then
    if [[ -n ${STUB_COPR_UNBUILT:-} ]]; then body='{"builds": {"latest_succeeded": null}}'; else body='{"builds": {"latest_succeeded": {"id": 1}}}'; fi
  else
    body='{"full_name": "vanillagreen/vgshell"}'
  fi
  printf '%s\n%s' "$body" "${STUB_COPR_CODE:-200}"
  exit 0
fi
if [[ $* == *aur.archlinux.org* ]]; then
  [[ -z ${STUB_CURL_EXIT:-} ]] || { echo "curl: (7) stub failure" >&2; exit "$STUB_CURL_EXIT"; }
  printf '%s\n' "$STUB_CURL_OUT"
  exit 0
fi
if [[ -n ${STUB_REQUIRE_PAGER:-} ]]; then
  printf '%s\n' '[[ ${PARU_PAGER:-} == cat ]] || exit 69'
fi
if [[ -n ${STUB_REQUIRE_NONROOT:-} ]]; then
  printf '%s\n' '[[ ${STUB_OCI_USER:-root} != root ]] || exit 79'
fi
if [[ -n ${STUB_REQUIRE_TTY:-} ]]; then
  printf '%s\n' 'if ! { : 2>/dev/null <>/dev/tty; }; then echo "install.sh: refused: floor=xdg-terminal-exec have=none need=present" >&2; exit 78; fi'
fi
exit "${STUB_FETCH_EXIT:-0}"
EOF
cat >"$stubs/paru" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} != --version ]] || echo "vgshell $STUB_VERSION"
exit 0
EOF
cat >"$stubs/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
cat >"$stubs/dnf" <<'EOF'
#!/usr/bin/env bash
# Under STUB_REQUIRE_YES, dnf's default no declines, as dnf does.
if [[ -n ${STUB_REQUIRE_YES:-} ]]; then
  read -r answer || exit 1
  [[ $answer == y ]] || exit 1
fi
exit 0
EOF
cat >"$stubs/nix" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == build ]]; then echo "$STUB_HOME/vgshell"; exit 0; fi
if [[ $* == *--version ]]; then echo "vgshell $STUB_VERSION"; exit 0; fi
echo 'vgshell: refused: hyprland=unreachable' >&2
exit 69
EOF
cat >"$stubs/nix-store" <<'EOF'
#!/usr/bin/env bash
printf '/nix/store/fixture\n'
[[ $# -le 2 ]] || printf '/nix/store/engine\n'
EOF
home="$tmp/home"
mkdir -p -- "$home/vgshell/bin"
mkdir -p -- "$home/vgshell/shell" "$home/vgshell/config" "$home/vgshell/themes" "$home/store/store"
mkdir -p -- "$home/store/store/engine/bin" "$home/.engines"
: >"$home/store/store/engine/bin/qs"
ln -s -- "$home/store/store/engine" "$home/.engines/git-original"
printf 'runtime\n' >"$home/vgshell/VERSION"
printf 'exported store\n' >"$home/store/store/fixture"
cat >"$home/vgshell/bin/vgshell" <<'EOF'
#!/usr/bin/env bash
if [[ $* == *'version --json' ]]; then
  node -e 'console.log(JSON.stringify({version: process.env.STUB_VERSION, describe: process.env.STUB_DESCRIBE ?? null, running: null, restart: null}))'
  exit 0
fi
if [[ $* == *--version ]]; then echo "vgshell ${STUB_DISPLAY:-${STUB_DESCRIBE:-$STUB_VERSION}}"; exit 0; fi
echo 'vgshell: refused: hyprland=unreachable' >&2
exit 69
EOF
chmod 755 "$home/vgshell/bin/vgshell"
mkdir -p "$home/.local/bin"
ln -s "$home/vgshell/bin/vgshell" "$home/.local/bin/vgshell"
ln -s "$home/vgshell/bin/vgshell" "$stubs/vgshell"
record="$tmp/record"
cat >"$stubs/git" <<'EOF'
#!/usr/bin/env bash
[[ -z ${STUB_GIT_EXIT:-} ]] || { echo "fatal: stub failure" >&2; exit "$STUB_GIT_EXIT"; }
printf '%s' "${STUB_GIT_OUT:-}"
EOF
chmod 755 "$stubs"/*

# row NAME WANT_EXIT WANT_FIRST PATH [VAR=VALUE...] -- ARGS...
# Runs TREE's runner under env -i with PATH and the variables.
row() {
  local name="$1" want_exit="$2" want_first="$3" path="$4" status=0 out first
  shift 4
  local vars=()
  while [[ $1 != -- ]]; do vars+=("$1"); shift; done
  shift
  : >"$record"
  out="$(env -i PATH="$path" HOME="$tmp" LC_ALL=C STUB_RECORD="$record" STUB_HOME="$home" STUB_VERSION="$version" STUB_FIXTURE_ROOT="$tmp" "${vars[@]}" "$tree/scripts/readme-install.sh" "$@" 2>&1)" || status=$?
  row_output="$out"
  if ! first="$(sed '/^readme-install: syntax /d; /^readme-install: space /d' <<<"$out")"; then fail "$name: syntax receipt filter failed"; return; fi
  first="${first%%$'\n'*}"
  # WANT_FIRST is a glob pattern: only the timing row uses `*`.
  # shellcheck disable=SC2053
  if [[ $status == "$want_exit" && $first == $want_first ]]; then
    ok "$name"
  else
    fail "$name: exit=$status want=$want_exit first=[$first] want=[$want_first]"
    printf '%s\n' "$out" | sed 's/^/        /'
  fi
}

stubbed="$stubs:$farm"
empty_aur='{"results":[]}'

row "an unknown argument is refused" 2 "readme-install: refused: argument=--bogus" "$stubbed" -- --bogus
row "an unknown channel is refused" 2 "readme-install: refused: channel=missing reason=unknown" "$stubbed" -- --channel missing
row "no podman is not measured" 77 "readme-install: status=not-measured reason=podman-missing" "$farm" --
row "a failed AUR probe is not measured" 77 "readme-install: status=not-measured reason=aur-probe package=vgshell-git" "$stubbed" STUB_CURL_EXIT=7 --
row "an AUR answer with no result list is not measured" 77 "readme-install: status=not-measured reason=aur-probe package=vgshell-git" "$stubbed" STUB_CURL_OUT='{}' --
curl_url='https://raw.githubusercontent.com/vanillagreencom/vgshell/main/install.sh'
curl_command="curl -fsSL $curl_url | bash -s -- --git"
curl_line="$(grep -n -F -x -- "$curl_command" "$tree/README.md")" || { echo "test-readme-install: readme=no-curl-line"; exit 1; }
curl_line="${curl_line%%:*}"
download_first="readme-install: refused: line=$curl_line exit=22 command=$curl_command"
row "a failed COPR probe is not measured" 77 "readme-install: status=not-measured reason=copr-probe need=copr:vanillagreen/vgshell" "$stubbed" STUB_CURL_OUT="$empty_aur" STUB_COPR_EXIT=7 --
row "a COPR answer neither 200 nor 404 is not measured" 77 "readme-install: status=not-measured reason=copr-probe need=copr:vanillagreen/vgshell http=500" "$stubbed" STUB_CURL_OUT="$empty_aur" STUB_COPR_PUBLISHED=1 STUB_COPR_CODE=500 --
row "a curl download that fails with no output is refused" 1 "$download_first" "$stubbed" STUB_PODMAN_WORKS=1 STUB_CURL_OUT="$empty_aur" STUB_FETCH_EXIT=22 --
aur_first="$(grep -n -F -x -- "paru -S vgshell-git" "$tree/README.md")" || { echo "test-readme-install: readme=no-paru-line"; exit 1; }
published=("$stubbed" STUB_PODMAN_WORKS=1 STUB_CURL_OUT='{"results":[{"Name":"vgshell-git"}]}' STUB_COPR_PUBLISHED=1)
row "malformed commands fail syntax before an install starts" 1 "readme-install: refused: block=1 syntax=refused" "${published[@]}" STUB_MALFORMED_COMMAND=1 -- --export "$tmp/syntax-exports"
row "the published commands run" 0 "readme-install: ok line=${aur_first%%:*} channel=aur exit=0 seconds=*" "${published[@]}" --
# Each command the record names, after its fence's number in the README.
fence_want=$'1 paru -S vgshell-git\n1 vgshell --version\n2 sudo dnf copr enable vanillagreen/vgshell\n2 sudo dnf install vgshell\n2 vgshell --version\n3 '"$curl_command"$'\n3 ~/.local/bin/vgshell --version\n3 ~/.local/bin/vgshell version --json\n4 nix run github:vanillagreencom/vgshell -- start\n4 nix run github:vanillagreencom/vgshell -- --version\n5 git clone https://github.com/vanillagreencom/vgshell\n5 vgshell/bin/vgshell start\n5 vgshell/bin/vgshell --version\n5 vgshell/bin/vgshell version --json'
for block in 6 7; do fence_want+=$'\n'"$block $curl_command"$'\n'"$block ~/.local/bin/vgshell --version"$'\n'"$block ~/.local/bin/vgshell version --json"; done
fence_have="$(sed -n -E 's/^exec vgs-readme-install-([0-9]+)\.[0-9]+ /\1 /p' -- "$record")"
fence_starts="$(sed -n -E 's/^start vgs-readme-install-([0-9]+)\.[0-9]+$/\1/p' -- "$record")"
if [[ $fence_have == "$fence_want" && $fence_starts == $'1\n2\n3\n4\n5\n6\n7' ]]; then
  ok "each fence runs in its own container"
else
  fail "each fence runs in its own container"
  sed 's/^/        /' -- "$record"
fi

export_row() {
  rm -rf -- "$tmp/exports"
  row "published installs export their runtime trees and Nix store" 0 "readme-install: ok line=${aur_first%%:*} channel=aur exit=0 seconds=*" "${published[@]}" -- --export "$tmp/exports"
  if python3 - "$tmp/exports" "$row_output" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
trees = {}
for line in sys.argv[2].splitlines():
    if not line.startswith("readme-install: tree "): continue
    match = re.fullmatch(r"readme-install: tree line=(\d+) channel=([\w-]+) path=(\S+)(?: store=(\S+))?", line)
    assert match, line
    number, channel, path, store = match.groups()
    assert channel not in trees, channel
    tree = pathlib.Path(path)
    assert tree == root / f"line-{number}-{channel}", path
    assert (tree / "bin/vgshell").is_file(), path
    assert (tree / "VERSION").read_text() == "runtime\n", path
    assert not (tree / "README.md").exists(), path
    if channel in ("nix", "curl-nixos"):
        assert pathlib.Path(store) == tree / "nix"
        assert (pathlib.Path(store) / "store/fixture").read_text() == "exported store\n"
    else: assert store is None, line
    trees[channel] = tree
    if channel == "curl-nixos":
        assert len(list((tree / ".engines").iterdir())) == 1
        assert (tree / "nix/store/engine/bin/qs").is_file()
assert set(trees) == {"aur", "fedora", "curl", "checkout", "nix", "curl-debian", "curl-nixos"}, trees
PY
  then ok "each installed block exports once, without installed documentation"; else fail "installed tree/store exports differ"; fi
}
export_row
row "selected added channels reuse only their curl blocks" 0 "readme-install: ok line=$curl_line channel=curl-debian exit=0 seconds=*" "${published[@]}" -- --channel curl-debian --channel curl-nixos
if [[ $(sed -n -E 's/^start vgs-readme-install-([0-9]+)\.[0-9]+$/\1/p' -- "$record") == $'6\n7' ]]; then ok "selection starts no completed channel"; else fail "selection started another channel"; fi
row "both NixOS routes run as their nonroot user with a private writable store" 0 "readme-install: ok line=* channel=nix exit=69 seconds=*" "${published[@]}" STUB_REQUIRE_NONROOT=1 -- --channel nix --channel curl-nixos
if python3 - "$record" <<'PY'
from pathlib import Path
import re, sys
record = Path(sys.argv[1])
lines = record.read_text().splitlines()
owners = [m.group(1) for line in lines if (m := re.fullmatch(r"private-owner (\S+) /nix", line))]
assert owners
for owner in owners:
    volume = Path(str(record) + "." + owner + ".volume").read_text().strip()
    assert volume.startswith("private-nix-")
    assert "volume-rm " + volume in lines, volume
PY
then ok "every handed-over private store is removed"; else fail "private Nix store ownership or cleanup was not exercised"; fi
private_store_refusal() {
  row "a shared volume candidate is refused before cleanup ownership" 77 'readme-install: status=not-measured reason=container-setup step=private-store' "${published[@]}" STUB_VOLUME_CANDIDATE=vgs-validate-nix-2.35.2 -- --channel curl-nixos
  if grep -qxF 'volume-rm vgs-validate-nix-2.35.2' "$record"; then fail "cleanup removed the rejected shared candidate"; else ok "cleanup never removes the rejected shared candidate"; fi
}
private_store_refusal
# The volume-inspect stub hands space_check $home. Keep the fake closure
# larger than the free space on the same filesystem, whatever its size.
oversized_closure="$(python3 - "$home" <<'PY'
import os, sys
fs = os.statvfs(sys.argv[1])
print(fs.f_bavail * fs.f_frsize + 3_000_000_000)
PY
)"
row "a private NixOS store that would leave less than 3 GB is refused" 77 "readme-install: ok line=${aur_first%%:*} channel=aur exit=0 seconds=*" "${published[@]}" STUB_CLOSURE_BYTES="$oversized_closure" -- --export "$tmp/no-space-exports"
if [[ $row_output == *'reason=container-setup step=private-store-space'* ]] && ! compgen -G "$tmp/no-space-exports/line-*-nix" >/dev/null; then ok "the closure space refusal precedes the Nix copy"; else fail "the Nix closure ignored the available space"; fi
# The new export assertion must reject a runner that never hands trees out.
cp -p -- "$tree/scripts/readme-install.sh" "$tmp/readme-install-export.orig"
python3 - "$tree/scripts/readme-install.sh" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = '    export_tree "$version_command"'
assert text.count(old) == 1
path.write_text(text.replace(old, '    : "$version_command"'))
PY
export_before=$failures
export_row >"$tmp/export-control.log" 2>&1
cp -p -- "$tmp/readme-install-export.orig" "$tree/scripts/readme-install.sh"
if ((failures == export_before + 1)); then failures=$export_before; ok "control: an absent export fails its row"; else fail "control: an absent export passed its row"; fi

row "dnf's prompts are answered y" 0 "readme-install: ok line=${aur_first%%:*} channel=aur exit=0 seconds=*" "${published[@]}" STUB_REQUIRE_YES=1 --
dnf_line="$(grep -n -F -x -- "sudo dnf install vgshell" "$tree/README.md")" || { echo "test-readme-install: readme=no-dnf-line"; exit 1; }
dnf_line="${dnf_line%%:*}"
row "a COPR package with no succeeded build is not measured" 77 "readme-install: ok line=${aur_first%%:*} channel=aur exit=0 seconds=*" "${published[@]}" STUB_COPR_UNBUILT=1 --
if grep -qxF "readme-install: status=not-measured reason=unpublished line=$dnf_line needs=copr:vanillagreen/vgshell/vgshell" <<<"$row_output" &&
  grep -q -E "^readme-install: ok line=$((dnf_line - 1)) channel=fedora " <<<"$row_output"; then
  ok "the unbuilt package alone is unpublished"
else
  fail "the unbuilt package alone is unpublished"
  printf '%s\n' "$row_output" | sed 's/^/        /'
fi

# readme_edit OLD NEW: replace OLD, which must occur once, in the tree's
# README.
readme_edit() {
  python3 - "$tree/README.md" "$1" "$2" <<'PY'
import pathlib, sys
path, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text()
if text.count(old) != 1:
    raise SystemExit(f"README edit: matches={text.count(old)}")
path.write_text(text.replace(old, new))
PY
}
cp -p -- "$tree/README.md" "$tmp/README.md.orig"
readme_edit 'AUR helper: paru or yay.' 'AUR helper: yay.'
row "the image installs the helper named by the README" 77 "readme-install: ok line=$curl_line channel=curl exit=0 seconds=*" "$stubbed" STUB_PODMAN_WORKS=1 STUB_CURL_OUT="$empty_aur" --
if grep -qxF 'prepare yay' "$record"; then ok "the image reads the README helper"; else fail "the image did not read the README helper"; fi
cp -p -- "$tmp/README.md.orig" "$tree/README.md"
cp -p -- "$tree/scripts/readme-install.sh" "$tmp/readme-install-owner.orig"
python3 - "$tree/scripts/readme-install.sh" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = '    [[ -n $candidate && $candidate != "$nix_volume" ]]'
assert text.count(old) == 1
path.write_text(text.replace(old, '    nixos_volume="$candidate"\n' + old))
PY
owner_before=$failures
private_store_refusal >"$tmp/owner-control.log" 2>&1
cp -p -- "$tmp/readme-install-owner.orig" "$tree/scripts/readme-install.sh"
if ((failures == owner_before + 1)); then failures=$owner_before; ok "control: old cleanup publication order fails its ownership assertion"; else fail "control: old cleanup publication order passed its ownership assertion"; fi
row "curl receives a controlling terminal" 77 "readme-install: ok line=$curl_line channel=curl exit=0 seconds=*" "$stubbed" STUB_PODMAN_WORKS=1 STUB_CURL_OUT="$empty_aur" STUB_REQUIRE_TTY=1 --
row "curl receives a noninteractive recipe pager" 77 "readme-install: ok line=$curl_line channel=curl exit=0 seconds=*" "$stubbed" STUB_PODMAN_WORKS=1 STUB_CURL_OUT="$empty_aur" STUB_REQUIRE_PAGER=1 --
row "checkout versions use the canonical version and describe report" 77 "readme-install: ok line=$curl_line channel=curl exit=0 seconds=*" "$stubbed" STUB_PODMAN_WORKS=1 STUB_CURL_OUT="$empty_aur" STUB_DESCRIBE="$version.r14.g797b0cb" --
if grep -qxF "readme-install: version line=$curl_line channel=curl value=vgshell $version.r14.g797b0cb" <<<"$row_output"; then ok "the checkout display is logged without alteration"; else fail "the checkout display was not logged"; fi
row "an inconsistent checkout version display is refused" 1 "readme-install: ok line=$curl_line channel=curl exit=0 seconds=*" "$stubbed" STUB_PODMAN_WORKS=1 STUB_CURL_OUT="$empty_aur" STUB_DISPLAY=broken --
row "an unexpected installed version is refused" 1 "readme-install: ok line=$curl_line channel=curl exit=0 seconds=*" "$stubbed" STUB_PODMAN_WORKS=1 STUB_CURL_OUT="$empty_aur" STUB_CHECKOUT_VERSION=broken --
if grep -qxF "readme-install: refused: line=$curl_line version=unexpected" <<<"$row_output"; then ok "the installed version refusal names its cause"; else fail "the installed version refusal has another cause"; fi
readme_edit "paru -S vgshell-git" "yay -S vgshell-git"
row "a README check-readme refuses is refused" 1 "readme-install: refused: check-readme=refused" "$stubbed" --
cp -p -- "$tmp/README.md.orig" "$tree/README.md"
# The README's commands need no release, so the release probe rows plant
# the curl release install, which does.
readme_edit "$curl_command" "curl -fsSL $curl_url | bash"
release_probe=("$stubbed" STUB_CURL_OUT="$empty_aur" STUB_GIT_EXIT=128 --)
row "a failed release probe is not measured" 77 "readme-install: status=not-measured reason=release-probe tag=v$version" "${release_probe[@]}"

# --- controls ---------------------------------------------------------------
# control NAME OLD NEW ROW_ARGS...: the row, run on a runner copy with OLD
# replaced by NEW once, must fail.
control() {
  local name="$1" old="$2" new="$3" before=$failures
  shift 3
  cp -p -- "$tree/scripts/readme-install.sh" "$tmp/readme-install.sh.orig"
  python3 - "$tree/scripts/readme-install.sh" "$old" "$new" <<'PY'
import pathlib, sys
path, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text()
if text.count(old) != 1:
    raise SystemExit(f"runner edit: matches={text.count(old)}")
path.write_text(text.replace(old, new))
PY
  row "$@" >/dev/null
  cp -p -- "$tmp/readme-install.sh.orig" "$tree/scripts/readme-install.sh"
  if ((failures == before + 1)); then
    failures=$before
    ok "control: $name fails its row"
  else
    failures=$((before + 1))
    fail "control: $name passed its row"
  fi
}
# The OLD and NEW texts are the runner's own shell, never expanded here.
cp -p -- "$tmp/README.md.orig" "$tree/README.md"
# shellcheck disable=SC2016
control "an omitted same-image syntax check" 'container_exec bash -n -c "$syntax"' 'true' \
  "syntax" 1 "readme-install: refused: block=1 syntax=refused" "${published[@]}" STUB_MALFORMED_COMMAND=1 -- --export "$tmp/syntax-exports"
control "NixOS curl using root" 'image="$nixos_prepared" user=user' 'image="$nixos_prepared" user=root' \
  "nonroot" 0 "readme-install: ok line=$curl_line channel=curl-nixos exit=0 seconds=*" "${published[@]}" STUB_REQUIRE_NONROOT=1 -- --channel curl-nixos
# shellcheck disable=SC2016
control "a shared store selected for handover" 'run_args+=(-v /nix ' 'run_args+=(-v "$nix_volume:/nix" ' \
  "private-store" 0 "readme-install: ok line=$curl_line channel=curl-nixos exit=0 seconds=*" "${published[@]}" STUB_REQUIRE_NONROOT=1 -- --channel curl-nixos
mkdir -p "$tmp/account-files/etc" "$tmp/account-files/home" "$tmp/account-files/store"
printf 'root:x:0:0:fixture:/root:/bin/sh\n' >"$tmp/account-files/store/passwd"
printf 'root:x:0:\n' >"$tmp/account-files/store/group"
cp -- "$tmp/account-files/store/passwd" "$tmp/account-files/passwd.before"
cp -- "$tmp/account-files/store/group" "$tmp/account-files/group.before"
chmod 444 "$tmp/account-files/store/passwd" "$tmp/account-files/store/group"
ln -s "$tmp/account-files/store/passwd" "$tmp/account-files/etc/passwd"
ln -s "$tmp/account-files/store/group" "$tmp/account-files/etc/group"
account_case=("${published[@]}" STUB_REQUIRE_NONROOT=1 STUB_REAL_ACCOUNT_FILES=1 "STUB_ACCOUNT_ETC=$tmp/account-files/etc" "STUB_ACCOUNT_HOME=$tmp/account-files/home" -- --channel curl-nixos)
# shellcheck disable=SC2016
control "account writes through the store link" 'mv -T -- "$copy" "$file"' 'cat "$copy" >"$file"' \
  "image-owned accounts" 0 "readme-install: ok line=$curl_line channel=curl-nixos exit=0 seconds=*" "${account_case[@]}"
row "account files detach from the store before the fixture is appended" 0 "readme-install: ok line=$curl_line channel=curl-nixos exit=0 seconds=*" "${account_case[@]}"
if python3 - "$tmp/account-files" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
for name in ("passwd", "group"):
    assert not (root / "etc" / name).is_symlink()
    assert (root / "store" / name).read_bytes() == (root / (name + ".before")).read_bytes()
assert "user:x:1000:1000:" in (root / "etc/passwd").read_text()
assert (root / "home/user").is_dir()
PY
then ok "the container account changed and the shared-store fixture stayed byte-identical"; else fail "the shared-store account fixture changed"; fi
control "an omitted closure space check" 'if free - size < 3_000_000_000:' 'if False:' \
  "space" 77 "readme-install: ok line=${aur_first%%:*} channel=aur exit=0 seconds=*" "${published[@]}" STUB_CLOSURE_BYTES="$oversized_closure" -- --export "$tmp/space-control-exports"
# shellcheck disable=SC2016
readme_edit "$curl_command" "curl -fsSL $curl_url | bash"
control "a runner that reads a failed release probe as an answer" \
  '2>&1)" ||
        not_measured "release-probe tag=${1#release:}" "$out"' '2>&1)" || true' \
  "release probe" 77 "readme-install: status=not-measured reason=release-probe tag=v$version" "${release_probe[@]}"
cp -p -- "$tmp/README.md.orig" "$tree/README.md"
# shellcheck disable=SC2016
control "a runner that reads a failed COPR probe as an answer" \
  '"$url" 2>&1)" || not_measured "copr-probe need=$1" "$out"' '"$url" 2>&1)" || true' \
  "COPR probe" 77 "readme-install: status=not-measured reason=copr-probe need=copr:vanillagreen/vgshell" "$stubbed" STUB_CURL_OUT="$empty_aur" STUB_COPR_EXIT=7 --
# shellcheck disable=SC2016
control "a runner that answers dnf with its default" "fedora) wrapper='yes y |" "fedora) wrapper='yes \"\" |" \
  "dnf answer" 0 "readme-install: ok line=${aur_first%%:*} channel=aur exit=0 seconds=*" "${published[@]}" STUB_REQUIRE_YES=1 --
# shellcheck disable=SC2016
control "a runner without pipefail" 'printf -v argv "%q " timeout "$1" bash -o pipefail -c "$2"' 'printf -v argv "%q " timeout "$1" bash -c "$2"' \
  "download" 1 "$download_first" "$stubbed" STUB_PODMAN_WORKS=1 STUB_CURL_OUT="$empty_aur" STUB_FETCH_EXIT=22 --

# shellcheck disable=SC2016
control "curl without a controlling terminal" 'script -qE never -ec "$argv" /dev/null' 'bash -c "$argv"' \
  "terminal" 77 "readme-install: ok line=$curl_line channel=curl exit=0 seconds=*" "$stubbed" STUB_PODMAN_WORKS=1 STUB_CURL_OUT="$empty_aur" STUB_REQUIRE_TTY=1 --
# shellcheck disable=SC2016
control "an interactive recipe pager" 'env PARU_PAGER=cat ' 'env ' \
  "pager" 77 "readme-install: ok line=$curl_line channel=curl exit=0 seconds=*" "$stubbed" STUB_PODMAN_WORKS=1 STUB_CURL_OUT="$empty_aur" STUB_REQUIRE_PAGER=1 --
# shellcheck disable=SC2016
control "an unchecked checkout base version" 'if (report.version !== process.argv[2]) process.exit(1);' '' \
  "version" 1 "readme-install: ok line=$curl_line channel=curl exit=0 seconds=*" "$stubbed" STUB_PODMAN_WORKS=1 STUB_CURL_OUT="$empty_aur" STUB_CHECKOUT_VERSION=broken --
# shellcheck disable=SC2016
control "an unchecked checkout display" 'if (process.argv[3] !== `vgshell ${report.describe ?? report.version}`) process.exit(1);' '' \
  "display" 1 "readme-install: ok line=$curl_line channel=curl exit=0 seconds=*" "$stubbed" STUB_PODMAN_WORKS=1 STUB_CURL_OUT="$empty_aur" STUB_DISPLAY=broken --
# shellcheck disable=SC2016
control "an unchecked packaged version" '[[ $version_out == "vgshell $(<"$repo/VERSION")" ]]' 'true' \
  "package version" 1 "readme-install: ok line=${aur_first%%:*} channel=aur exit=0 seconds=*" "$stubbed" STUB_PODMAN_WORKS=1 STUB_CURL_OUT='{"results":[{"Name":"vgshell-git"}]}' STUB_PACKAGE_VERSION=broken --

if ((failures > 0)); then
  echo "test-readme-install: failed=$failures"
  exit 1
fi
echo "test-readme-install: ok"
