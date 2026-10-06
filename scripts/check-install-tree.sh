#!/usr/bin/env bash
# Assert the installed VGS file list against packaging/install-tree.manifest.
#
# Usage:
#   scripts/check-install-tree.sh [--write] DESTDIR [PREFIX [SYSCONFDIR]]
#
# DESTDIR is the staging root passed to packaging/install-system.sh. PREFIX
# defaults to /usr/local and must match the installer call. The manifest lists
# files and symlinks relative to PREFIX. --write rewrites the manifest from the
# installed tree after a legitimate shipped file is added.
# SYSCONFDIR, the installer's own, checks a system package's tree: the
# expected set adds packaging/install-tree-system.manifest, whose
# SYSCONFDIR/ rows name files relative to it, the writer must be mode 0755,
# the sudoers rule mode 0440, holding exactly what the installed writer's
# `package-rule PREFIX` prints, and the autostart entry and portal preference
# must be mode 0644. --write takes no SYSCONFDIR: the system rows are written
# by hand.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd -P)"
manifest="$repo/packaging/install-tree.manifest"
system_manifest="$repo/packaging/install-tree-system.manifest"
write=false
if [[ ${1:-} == --write ]]; then write=true; shift; fi
case "${1:-}" in
  -h|--help) sed -n '2,17{s/^# \{0,1\}//;p}' "$self"; exit 0 ;;
esac
[[ $# -ge 1 && $# -le 3 ]] || { echo 'install-tree: refused: usage=DESTDIR [PREFIX [SYSCONFDIR]]' >&2; exit 2; }
destdir="$1"
prefix="${2:-/usr/local}"
[[ -n $prefix && $prefix == /* && $prefix != */ ]] || { printf 'install-tree: refused: prefix=%s\n' "${prefix:-empty}" >&2; exit 2; }
root="$destdir$prefix"
[[ -d $root ]] || { printf 'install-tree: refused: root=missing path=%s\n' "$root" >&2; exit 1; }
sysconf_root=""
if [[ $# == 3 ]]; then
  [[ $3 == /* && $3 != */ ]] || { printf 'install-tree: refused: sysconfdir=%s\n' "${3:-empty}" >&2; exit 2; }
  [[ $write == false ]] || { echo 'install-tree: refused: write=system' >&2; echo '--write writes the base manifest; edit packaging/install-tree-system.manifest by hand' >&2; exit 2; }
  sysconf_root="$destdir$3"
  [[ -d $sysconf_root ]] || { printf 'install-tree: refused: sysconfdir=missing path=%s\n' "$sysconf_root" >&2; exit 1; }
fi

# Every file and link under ROOT's shipped directories, relative to ROOT,
# and with SYSCONF_ROOT every one under it, as SYSCONFDIR/<path>.
list_tree() { # ROOT [SYSCONF_ROOT]
  python3 - "$@" <<'PY'
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
tops = [(root, "", base) for base in (root / "bin", root / "share" / "vgshell", root / "share" / "doc" / "vgshell", root / "share" / "licenses" / "vgshell")]
if len(sys.argv) > 2:
    sysconf = pathlib.Path(sys.argv[2])
    tops.append((sysconf, "SYSCONFDIR/", sysconf))
rows = []
for top, label, base in tops:
    if not base.exists() and not base.is_symlink():
        continue
    for current, dirs, files in os.walk(base, followlinks=False):
        dirs[:] = sorted(dirs)
        for name in sorted(files):
            path = pathlib.Path(current) / name
            rel = label + path.relative_to(top).as_posix()
            if path.is_symlink():
                rows.append(f"l {rel} -> {os.readlink(path)}")
            elif path.is_file():
                rows.append(f"f {rel}")
            else:
                rows.append(f"special {rel}")
for row in sorted(rows):
    print(row)
PY
}

actual_file="$repo/tmp/install-tree-actual.$$"
cleanup() { rm -f -- "$actual_file" "$actual_file.expected"; }
trap cleanup EXIT
mkdir -p -- "$repo/tmp"
list_args=("$root")
[[ -z $sysconf_root ]] || list_args+=("$sysconf_root")
list_tree "${list_args[@]}" | LC_ALL=C sort >"$actual_file"

if [[ $write == true ]]; then
  cp -- "$actual_file" "$manifest"
  printf 'install-tree=manifest-updated path=%s\n' "$manifest"
  exit 0
fi
manifests=("$manifest")
[[ -z $sysconf_root ]] || manifests+=("$system_manifest")
for file in "${manifests[@]}"; do
  [[ -f $file ]] || { printf 'install-tree: refused: manifest=missing path=%s\n' "$file" >&2; exit 1; }
done
manifest_names="$(IFS=,; echo "${manifests[*]}")"
LC_ALL=C sort -- "${manifests[@]}" >"$actual_file.expected"
failed=false
if ! cmp -s -- "$actual_file.expected" "$actual_file"; then
  failed=true
  LC_ALL=C comm -23 -- "$actual_file.expected" "$actual_file" | sed 's/^/install-tree=missing entry=/'
  LC_ALL=C comm -13 -- "$actual_file.expected" "$actual_file" | sed 's/^/install-tree=extra entry=/'
fi
if [[ -n $sysconf_root ]]; then
  # A row the list compare already reports missing or not a file is not
  # judged again here.
  writer="$root/bin/vgshell-browser-policy" rule="$sysconf_root/sudoers.d/vgshell-theme-browser"
  portal_config="$sysconf_root/xdg/xdg-desktop-portal/hyprland-portals.conf"
  for pair in "755 $writer" "440 $rule" "644 $sysconf_root/xdg/autostart/vgshell.desktop" "644 $portal_config"; do
    want="${pair%% *}" path="${pair#* }"
    [[ -f $path && ! -L $path ]] || continue
    have="$(stat -c %a -- "$path")" || { printf 'install-tree: refused: stat=failed path=%s\n' "$path" >&2; exit 1; }
    [[ $have == "$want" ]] || { printf 'install-tree=mode path=%s have=%s want=%s\n' "$path" "$have" "$want"; failed=true; }
  done
  if [[ -f $writer && ! -L $writer && -f $rule && ! -L $rule ]]; then
    if ! want_rule="$("$writer" package-rule "$prefix")"; then
      printf 'install-tree=rule-unprinted writer=%s prefix=%s\n' "$writer" "$prefix"
      failed=true
    elif [[ $(<"$rule") != "$want_rule" ]]; then
      printf 'install-tree=rule-differs path=%s\n' "$rule"
      failed=true
    fi
  fi
  if [[ -f $portal_config && ! -L $portal_config ]]; then
    if ! cmp -s -- "$repo/packaging/xdg-desktop-portal/hyprland-portals.conf" "$portal_config"; then
      printf 'install-tree=portal-config-differs path=%s\n' "$portal_config"
      failed=true
    fi
  fi
fi
if [[ $failed == false ]]; then
  printf 'install-tree=ok root=%s manifest=%s\n' "$root" "$manifest_names"
  exit 0
fi
echo "install-tree=failed manifest=$manifest_names"
echo "run: packaging/install-system.sh with the same DESTDIR and PREFIX, then scripts/check-install-tree.sh --write DESTDIR PREFIX"
exit 1
