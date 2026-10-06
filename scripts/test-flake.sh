#!/usr/bin/env bash
# Builds flake.nix in a nix container and checks the package it ships.
#
# The suite stages the working tree's tracked and untracked files, the way a
# `github:` flake reference sees a commit, and mounts the copy read-only. The
# nix store lives in the podman or docker volume named in `volume` below, so
# later runs reuse the downloads; `podman volume rm` on that name frees it.
#
# Rows, each a keyed `ok` or `FAIL` line:
#   - `nix flake check` passes with the committed flake.lock unchanged.
#   - `nix build` succeeds. The build runs scripts/check-install-tree.sh on the
#     installed tree, so it ships the tree every other channel ships.
#   - `nix run .# -- --version` prints `vgshell <VERSION>`.
#   - For the file $out/bin/vgshell resolves to and for bin/vgshell-tui, the PATH
#     row: the one `# vgs-nix-path` line, run in an empty environment,
#     resolves the mapped required commands in the core and all shipped
#     manifests and `qs`, but
#     not `hyprctl`, since the session supplies Hyprland; a second run
#     leaves PATH unchanged.
#   - The same two files are their source with only that line added, right
#     after the leading comment block the usage text is read from.
# Controls:
#   - flake.nix with the requirements rows cut from the runtime PATH must fail
#     the PATH row on every requirement.
#   - the closure without qrencode must fail the PATH row for
#     the saved-network sharing command.
#   - bin/vgshell-tui from the build with its PATH line removed must fail the
#     PATH row.
#   - flake.nix whose insertion loop reaches only bin/vgshell must fail the
#     build with vgshell-tui's `nix-path=missing` line.
#   - packaging/install-tree.manifest with a planted entry must fail the build
#     with that entry's `install-tree=missing` line.
#
# Exit 0 when every row and control hold, 1 otherwise. Exit 77 names what
# could not run: no podman or docker, the image cannot be pulled, or the
# container cannot reach cache.nixos.org.
set -euo pipefail

repo="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd -P)"
image=docker.io/nixos/nix:2.35.2
volume=vgs-validate-nix-2.35.2

not_measured() { # REASON [DETAIL...]
  printf 'test-flake: status=not-measured reason=%s\n' "$1" >&2
  shift
  [[ $# -gt 0 ]] && printf '%s\n' "$@" >&2
  exit 77
}

if command -v podman >/dev/null; then runtime=podman
elif command -v docker >/dev/null; then runtime=docker
else not_measured no-container-runtime
fi
if ! "$runtime" image inspect "$image" >/dev/null 2>&1; then
  pull_error="$("$runtime" pull -q "$image" 2>&1 >/dev/null)" ||
    not_measured "image-unavailable runtime=$runtime image=$image" "$pull_error"
fi

tmp="$repo/tmp/test-flake.$$"
cleanup() { rm -rf -- "$tmp"; }
trap cleanup EXIT
rm -rf -- "$tmp"
mkdir -p -- "$tmp/src"

# Tracked and untracked files that exist; a deleted tracked file is left out,
# as it is from the commit that deletes it.
while IFS= read -r -d '' path; do
  [[ -e $path || -L $path ]] && printf '%s\0' "$path"
done < <(git -C "$repo" ls-files -z -co --exclude-standard) >"$tmp/files"
tar -C "$repo" --null -T "$tmp/files" -cf - | tar -C "$tmp/src" -xf -

version="$(<"$repo/VERSION")"
commands="$(python3 - "$repo" <<'PYREQ'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
rows = json.loads((root / "config/requirements.json").read_text())
for manifest in sorted((root / "shell/plugins").glob("*/manifest.json")):
    rows += json.loads(manifest.read_text()).get("requirements", [])
print(" ".join(sorted({row.get("command") or row["dbus"]["name"] for row in rows if not row.get("optional", False) and "nix" in row.get("packages", {})})))
PYREQ
)"

status=0
"$runtime" run --rm -i \
  -v "$volume:/nix" -v "$tmp/src:/src:ro" \
  -e NIX_CONFIG='experimental-features = nix-command flakes' \
  -e VGS_VERSION="$version" -e VGS_COMMANDS="$commands" \
  "$image" bash -s <<'CONTAINER' || status=$?
set -uo pipefail
nix store info --store https://cache.nixos.org >/dev/null 2>&1 || exit 77
failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }
flags=(--no-update-lock-file --no-link --print-out-paths)

marker='# vgs-nix-path'

# The entry point's PATH line, run with an empty environment, answers which
# of the names resolve. Prints each name that does not.
unresolved() { # LINE NAME...
  local line="$1"; shift
  env -i "$(command -v bash)" -c 'set -e; PATH=; eval "$1"; shift
    for name in "$@"; do command -v -- "$name" >/dev/null || echo "$name"; done' _ "$line" "$@"
}
path_holds() { # ENTRY: one PATH line; every command resolves, hyprctl does not; a rerun keeps PATH
  local line missing
  if ! line="$(grep -F -- "$marker" "$1")" || [[ $line == *$'\n'* ]]; then
    echo "flake: nix-path=missing path=$1"; return 1
  fi
  missing="$(unresolved "$line" qs $VGS_COMMANDS)" || return 1
  [[ -z $missing ]] || { echo "flake: unresolved=$(echo $missing | tr ' ' ,)"; return 1; }
  [[ $(unresolved "$line" hyprctl) == hyprctl ]] || { echo 'flake: resolved=hyprctl'; return 1; }
  env -i "$(command -v bash)" -c 'PATH=; eval "$1"; once=$PATH; eval "$1"; [[ $PATH == "$once" ]]' _ "$line" ||
    { echo "flake: nix-path=grows path=$1"; return 1; }
}
# ENTRY is SOURCE with one line added: the PATH line, right after the
# comment block that follows the interpreter line. The interpreter line
# itself is fixup's to rewrite.
placed() { # ENTRY SOURCE
  local -a got want
  local i=1
  mapfile -t got <"$1" && mapfile -t want <"$2" || return 1
  while ((i < ${#want[@]})) && [[ ${want[i]} == '#'* ]]; do i=$((i + 1)); done
  [[ ${got[i]:-} == *"$marker" ]] || return 1
  unset 'got[0]' "got[$i]" 'want[0]'
  local IFS=$'\n'
  [[ "${got[*]}" == "${want[*]}" ]]
}

if nix flake check --no-update-lock-file path:/src >/tmp/check.log 2>&1; then ok "nix flake check passes"
else cat /tmp/check.log; fail "nix flake check passes"
fi
if out="$(nix build "${flags[@]}" path:/src 2>/tmp/build.log)"; then
  ok "nix build succeeds and checks the install tree"
  if version="$(nix run --no-update-lock-file path:/src -- --version 2>&1)" && [[ $version == "vgshell $VGS_VERSION" ]]; then
    ok "nix run -- --version prints vgshell $VGS_VERSION"
  else fail "nix run -- --version prints vgshell $VGS_VERSION, got [$version]"
  fi
  vgshell="$(readlink -f "$out/bin/vgshell")"
  language_path="$(grep -F -- "$marker" "$vgshell")"
  languages="$(env -i "$(command -v bash)" -c 'PATH=; eval "$1"; tesseract --list-langs' _ "$language_path" 2>&1)" || languages=""
  if grep -qxF eng <<<"$languages"; then ok "Capture English OCR data is installed"
  else fail "Capture English OCR data is installed"; fi
  for spec in "$vgshell|/src/bin/vgshell" "$out/share/vgshell/bin/vgshell-tui|/src/bin/vgshell-tui"; do
    entry="${spec%%|*}"; source="${spec#*|}"
    if path_holds "$entry"; then ok "${source#/src/}'s PATH line resolves qs and every requirement, not hyprctl, and adds itself once"
    else fail "${source#/src/}'s PATH line resolves qs and every requirement, not hyprctl, and adds itself once"
    fi
    if placed "$entry" "$source"; then ok "${source#/src/} gains only its PATH line, after its comment block"
    else fail "${source#/src/} gains only its PATH line, after its comment block"
    fi
  done
  # Control: an entry point without its PATH line.
  grep -vF -- "$marker" "$out/share/vgshell/bin/vgshell-tui" >/tmp/vgshell-tui-bare
  if [[ $(path_holds /tmp/vgshell-tui-bare) == 'flake: nix-path=missing path=/tmp/vgshell-tui-bare' ]]; then
    ok "control: an entry point without its PATH line fails the PATH row"
  else fail "control: an entry point without its PATH line fails the PATH row"
  fi
else
  cat /tmp/build.log; fail "nix build succeeds and checks the install tree"
  exit 1
fi

# Control: the flake with no requirements rows on the runtime PATH.
# The container supplies Bash. Its builtins assert the block boundaries
# without relying on an editor that the base image does not ship.
cp -r /src /tmp/no-requirements
cut=''
open=0
closed=0
active=0
while IFS= read -r line; do
  if [[ $line == '      runtimePackages = pkgs: [' ]]; then
    open=$((open + 1)); active=1
  fi
  if ((active)); then
    cut+="${cut:+$'\n'}$line"
    if [[ $line == '      ];' ]]; then closed=$((closed + 1)); active=0; fi
  fi
done </src/flake.nix
if ((open != 1 || closed != 1 || active)) || [[ $cut != *"pkgs.nodejs"* ]] || ! flake="$(</src/flake.nix)"; then
  fail "control: the requirements filter appears once in flake.nix"
else
  printf '%s\n' "${flake/"$cut"/"      runtimePackages = pkgs: [ pkgs.quickshell ];"}" >/tmp/no-requirements/flake.nix
  if [[ $(</tmp/no-requirements/flake.nix) == "$flake" ]]; then fail "control: the requirements cut changed flake.nix"
  elif ! mutant="$(nix build "${flags[@]}" path:/tmp/no-requirements 2>/tmp/mutant.log)"; then
    cat /tmp/mutant.log; fail "control: the cut flake builds"
  elif [[ $(path_holds "$(readlink -f "$mutant/bin/vgshell")") == "flake: unresolved=${VGS_COMMANDS// /,}" ]]; then
    ok "control: dropping the requirements fails the PATH row"
  else fail "control: dropping the requirements fails the PATH row on every requirement"
  fi
fi

# Control: dropping the declared Network package loses its command.
# The expected command list still comes from the unmodified source above.
cp -r /src /tmp/no-network-qr
qr_row=$'        pkgs.qrencode\n'
if [[ $(grep -cxF '        pkgs.qrencode' /src/flake.nix) != 1 ]] || ! flake="$(</src/flake.nix)"; then
  fail "control: the QR requirement can be removed"
else
  printf '%s\n' "${flake/"$qr_row"/}" >/tmp/no-network-qr/flake.nix
  if [[ $(</tmp/no-network-qr/flake.nix) == "$flake" ]]; then
    fail "control: the QR removal changed flake.nix"
  elif ! mutant="$(nix build "${flags[@]}" path:/tmp/no-network-qr 2>/tmp/no-network-qr.log)"; then
    cat /tmp/no-network-qr.log; fail "control: the package without the QR requirement builds"
  elif [[ $(path_holds "$(readlink -f "$mutant/bin/vgshell")") == 'flake: unresolved=qrencode' ]]; then
    ok "control: removing the QR requirement loses qrencode from the installed PATH"
  else fail "control: removing the QR requirement loses qrencode from the installed PATH"
  fi
fi

# Control: the build's guard, with the insertion loop reaching only vgshell.
cp -r /src /tmp/vgshell-only
loop='for entry in $out/share/vgshell/bin/*; do'
narrow='for entry in $out/share/vgshell/bin/vgshell; do'
if [[ $(grep -cF -- "$loop" /tmp/vgshell-only/flake.nix) != 1 ]] || ! flake="$(</src/flake.nix)"; then
  fail "control: the insertion loop appears once in flake.nix"
else
  printf '%s\n' "${flake/"$loop"/"$narrow"}" >/tmp/vgshell-only/flake.nix
  if [[ $(</tmp/vgshell-only/flake.nix) == "$flake" ]]; then fail "control: the loop cut changed flake.nix"
  elif nix build "${flags[@]}" path:/tmp/vgshell-only >/dev/null 2>/tmp/vgshell-only.log; then
    fail "control: an entry point left without its PATH line fails the build"
  elif grep -qE 'flake: refused: nix-path=missing path=/nix/store/[^/]+/share/vgshell/bin/vgshell-tui$' /tmp/vgshell-only.log; then
    ok "control: an entry point left without its PATH line fails the build"
  else
    cat /tmp/vgshell-only.log; fail "control: an entry point left without its PATH line fails the build with its nix-path line"
  fi
fi

# Control: a manifest entry the installer never writes.
cp -r /src /tmp/planted
echo 'f share/vgshell/planted' >>/tmp/planted/packaging/install-tree.manifest
if nix build "${flags[@]}" path:/tmp/planted >/dev/null 2>/tmp/planted.log; then
  fail "control: a planted manifest entry fails the build"
elif grep -qF 'install-tree=missing entry=f share/vgshell/planted' /tmp/planted.log; then
  ok "control: a planted manifest entry fails the build"
else
  cat /tmp/planted.log; fail "control: a planted manifest entry fails the build with its install-tree line"
fi

((failures == 0))
CONTAINER

case "$status" in
  0) echo 'test-flake: ok' ;;
  77) not_measured network-unreachable ;;
  *) echo "test-flake: failed status=$status"; exit 1 ;;
esac
