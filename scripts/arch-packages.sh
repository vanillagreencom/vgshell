#!/usr/bin/env bash
# Build and install both Arch recipes in a throwaway archlinux:latest
# container, and run the installed vgshell.
#
# Usage: scripts/arch-packages.sh
#
# Nothing runs against the host's pacman, /etc or the live session. The
# script writes under this repository's tmp/ only: the scratch inputs in
# tmp/arch-packages.<pid>/, removed on exit, and the container's pacman
# package cache in tmp/arch-packages-cache/, kept so a rerun downloads no
# package it already has. podman keeps the image in its own store.
#
# What is built is the working tree as `git add -A` would commit it: HEAD
# when the tree is clean, else a commit object over HEAD that no ref names.
# From that commit the host makes the release tarball with
# scripts/lib/release-tarball.sh, the builder scripts/release calls, and a
# bare repository holding it as main and every tag, serving partial clones.
# Copies of the recipes take the tarball's sha256 (vgshell) and, as the URL
# vgshell-git's prepare() clones, `file://` of that repository; each
# substitution must match exactly once.
#
# In the rootless podman container, as root: update the system, install
# base-devel, git, sudo and the depends the vgshell recipe's .SRCINFO lists.
# Official packages come from pacman. AUR dependencies build as builder
# after their own declared dependencies install in this container. Then
# build vgshell and vgshell-git with makepkg as an unprivileged user and no network.
# Install vgshell with `pacman -U`: `vgshell --version` must print `vgshell
# <VERSION>`, /usr/bin/vgshell must link to ../share/vgshell/bin/vgshell, pacman's
# output must hold every line of the first-install text, and the browser
# theme writer /usr/bin/vgshell-browser-policy must be a regular file root:root
# 0755 beside the rule /etc/sudoers.d/vgshell-theme-browser, root:root 0440,
# that `visudo -cf` accepts and that grants every user the writer with six
# hex classes; `vgshell theme setup` must read the chromium setup not-detected
# without a browser and done with a stand-in chromium on PATH. Then remove
# vgshell with `pacman -R` and check it is gone, since neither recipe
# declares conflicts, replaces or provides and both own the same files, and
# install vgshell-git the same way: its build must have made a partial clone,
# the pkgver must be X.Y.Z.r<N>.g<hash> with the hash a prefix of the built
# commit, and the vgshell checks must hold again.
#
# Exit 0 prints `arch-packages: ok commit=<sha> vgshell=<version> vgshell-git=<pkgver>`.
# Exit 1 prints `arch-packages: refused: <key>=<value> ...` first: a
# recipe, build, install or assertion failure. Exit 77 prints
# `arch-packages: status=not-measured reason=<key>`: podman-missing,
# image-pull, container-start or container-setup (the system update or the
# depends download failed); that is not a pass. Exit 2: an argument.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd -P)"
image='docker.io/library/archlinux:latest'

refuse() { # STATUS KEY [DETAIL...]
  local status="$1"
  printf 'arch-packages: refused: %s\n' "$2"
  shift 2
  [[ $# -eq 0 ]] || printf '%s\n' "$@"
  exit "$status"
}
not_measured() { # REASON [DETAIL...]
  printf 'arch-packages: status=not-measured reason=%s\n' "$1"
  shift
  [[ $# -eq 0 ]] || printf '%s\n' "$@"
  exit 77
}

case "${1:-}" in
  "") ;;
  -h|--help) sed -n '2,46{s/^# \{0,1\}//;p}' "$self"; exit 0 ;;
  *) refuse 2 "argument=$1" ;;
esac
[[ $# -le 1 ]] || refuse 2 "argument=$2"

command -v podman >/dev/null 2>&1 || not_measured podman-missing "install podman to build the packages in a container"

version="$(<"$repo/VERSION")"
scratch="$repo/tmp/arch-packages.$$"
cache="$repo/tmp/arch-packages-cache"
cleanup() { rm -rf -- "$scratch"; }
trap cleanup EXIT
rm -rf -- "$scratch"
mkdir -p -- "$scratch/in/vgshell" "$scratch/in/vgshell-git" "$cache"

# The commit to build.
git_env=(env GIT_AUTHOR_NAME=arch-packages GIT_AUTHOR_EMAIL=arch-packages@example.invalid
  GIT_COMMITTER_NAME=arch-packages GIT_COMMITTER_EMAIL=arch-packages@example.invalid)
status_out="$(git -C "$repo" status --porcelain --untracked-files=normal)" || refuse 1 "git=status path=$repo"
if [[ -z $status_out ]]; then
  commit="$(git -C "$repo" rev-parse --verify HEAD)" || refuse 1 "git=rev-parse path=$repo"
else
  index="$scratch/index"
  GIT_INDEX_FILE="$index" git -C "$repo" read-tree HEAD || refuse 1 "git=read-tree path=$repo"
  GIT_INDEX_FILE="$index" git -C "$repo" add -A || refuse 1 "git=add path=$repo"
  tree="$(GIT_INDEX_FILE="$index" git -C "$repo" write-tree)" || refuse 1 "git=write-tree path=$repo"
  commit="$("${git_env[@]}" git -C "$repo" commit-tree "$tree" -p HEAD -m 'arch-packages: working tree')" ||
    refuse 1 "git=commit-tree path=$repo"
fi
echo "arch-packages: commit=$commit dirty=$([[ -n $status_out ]] && echo true || echo false)"

sum="$("$repo/scripts/lib/release-tarball.sh" "$commit" "$version" "$scratch/in/vgshell/vgshell-$version.tar.gz")" ||
  refuse 1 "archive=failed commit=$commit"

git init -q --bare "$scratch/in/srcrepo.git" || refuse 1 "git=init path=$scratch/in/srcrepo.git"
git -C "$repo" push -q "$scratch/in/srcrepo.git" "$commit:refs/heads/main" 'refs/tags/*:refs/tags/*' ||
  refuse 1 "git=push path=$scratch/in/srcrepo.git"
# Without it the server ignores --filter=blob:none and sends every blob.
git --git-dir="$scratch/in/srcrepo.git" config uploadpack.allowFilter true || refuse 1 "git=config path=$scratch/in/srcrepo.git"

# Copy a recipe, replacing the one match of PATTERN with REPLACEMENT.
recipe_copy() { # RECIPE PATTERN REPLACEMENT
  cp -- "$repo/packaging/arch/$1/PKGBUILD" "$scratch/in/$1/PKGBUILD"
  cp -- "$repo/packaging/arch/$1/.SRCINFO" "$scratch/in/$1/.SRCINFO"
  cp -- "$repo/packaging/arch/$1/$1.install" "$scratch/in/$1/$1.install"
  python3 - "$scratch/in/$1/PKGBUILD" "$2" "$3" <<'PY' || refuse 1 "recipe=unedited recipe=$1"
import pathlib, re, sys
path, pattern, replacement = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text()
matches = len(re.findall(pattern, text, flags=re.M))
if matches != 1:
    raise SystemExit(f"pattern {pattern!r} matched {matches} times, want 1")
changed = re.sub(pattern, lambda m: replacement, text, flags=re.M)
if changed == text:
    raise SystemExit("the substitution changed nothing")
path.write_text(changed)
PY
}
recipe_copy vgshell "^sha256sums=\('[^']*'\)$" "sha256sums=('$sum')"
recipe_copy vgshell-git ' -- "\$url\.git" "\$srcdir/vgshell"$' ' -- "file:///build/srcrepo.git" "$srcdir/vgshell"'

cat >"$scratch/in/run.sh" <<'RUN'
#!/usr/bin/env bash
# Runs as root in the container. Arguments: VERSION COMMIT.
set -euo pipefail
version="$1" commit="$2"
refuse() { printf 'arch-packages: refused: %s\n' "$1"; shift; [[ $# -eq 0 ]] || printf '%s\n' "$@"; exit 1; }
not_measured() { printf 'arch-packages: status=not-measured reason=%s\n' "$1"; shift; [[ $# -eq 0 ]] || printf '%s\n' "$@"; exit 77; }

# The cache is the host's tmp/arch-packages-cache. Downloads run as root,
# which is the host user, so no file there is owned by a uid the host
# cannot remove; a download directory left behind is removed on exit.
sed -i 's/^DownloadUser/#DownloadUser/' /etc/pacman.conf || refuse "pacman-conf=unedited"
if grep -q '^DownloadUser' /etc/pacman.conf; then refuse "pacman-conf=download-user"; fi
trap 'rm -rf /var/cache/pacman/pkg/download-*' EXIT

mapfile -t depends < <(sed -n 's/^\tdepends = //p' /in/vgshell/.SRCINFO)
[[ ${#depends[@]} -gt 0 ]] || refuse "depends=empty path=/in/vgshell/.SRCINFO"
pacman -Syu --noconfirm --needed base-devel git sudo python >/tmp/setup.log 2>&1 ||
  not_measured container-setup "$(tail -n 20 /tmp/setup.log)"
useradd -m builder
cp -a /in/. /build/
chown -R builder:builder /build

# Only the container's root installs packages. makepkg runs unprivileged
# without --syncdeps, so dependency setup never invokes sudo or PAM.
declare -A building=()
install_dependency() { # DEPENDENCY
  local dependency="$1" name="${1%%[<>=]*}" dir metadata child status=0
  local -a children files
  pacman -T "$dependency" >/tmp/missing.log 2>&1 || status=$?
  case "$status" in
    0) return 0 ;;
    127) ;;
    *) refuse "depends=query-failed package=$dependency status=$status" "$(cat /tmp/missing.log)" ;;
  esac
  if pacman -Sp --print-format %n "$dependency" >/tmp/resolve.log 2>&1; then
    pacman -S --noconfirm --needed --asdeps "$dependency" >/tmp/depends.log 2>&1 ||
      not_measured container-setup "$(tail -n 20 /tmp/depends.log)"
    return 0
  fi
  [[ $name =~ ^[a-zA-Z0-9][a-zA-Z0-9+_.-]*$ ]] || refuse "depends=malformed package=$name"
  [[ ! -v building[$name] ]] || refuse "depends=cycle package=$name"
  building[$name]=true
  dir="/build/aur/$name"
  mkdir -p /build/aur
  chown builder:builder /build/aur
  runuser -u builder -- git clone --quiet --depth 1 -- "https://aur.archlinux.org/$name.git" "$dir" >/tmp/aur-fetch.log 2>&1 ||
    not_measured "aur-source package=$name" "$(tail -n 20 /tmp/aur-fetch.log)"
  metadata="$(runuser -u builder -- bash -c 'cd -- "$1" && makepkg --printsrcinfo' _ "$dir")" ||
    refuse "aur-metadata=unreadable package=$name"
  mapfile -t children < <(sed -n -E 's/^\t(depends|makedepends) = //p' <<<"$metadata" | sort -u)
  for child in "${children[@]}"; do install_dependency "$child"; done
  # Dependency checks can require their own compositor or hardware. Only
  # VGS acceptance runs here; dependency packages build without check().
  runuser -u builder -- bash -c 'cd -- "$1" && makepkg --noconfirm --nocheck' _ "$dir" >"/tmp/aur-build-$name.log" 2>&1 ||
    refuse "aur-build=failed package=$name" "$(tail -n 40 "/tmp/aur-build-$name.log")"
  mapfile -t files < <(find "$dir" -maxdepth 1 -type f -name '*.pkg.tar.*' ! -name '*.sig')
  [[ ${#files[@]} -gt 0 ]] || refuse "aur-build=empty package=$name"
  pacman -U --noconfirm --asdeps -- "${files[@]}" >/tmp/aur-install.log 2>&1 ||
    refuse "aur-install=failed package=$name" "$(tail -n 20 /tmp/aur-install.log)"
  pacman -T "$dependency" >/tmp/missing.log 2>&1 || refuse "depends=unsatisfied package=$dependency"
  unset 'building[$name]'
}
for dependency in "${depends[@]}"; do install_dependency "$dependency"; done

# The one package file makepkg built for RECIPE.
package_file() { # RECIPE
  local files=()
  shopt -s nullglob
  files=(/build/"$1"/*.pkg.tar.*)
  shopt -u nullglob
  [[ ${#files[@]} -eq 1 ]] || refuse "package=count recipe=$1 count=${#files[@]}"
  printf '%s' "${files[0]}"
}
for recipe in vgshell vgshell-git; do
  runuser -u builder -- bash -c 'cd "/build/$1" && makepkg --noconfirm' _ "$recipe" >"/tmp/build-$recipe.log" 2>&1 ||
    refuse "build=failed recipe=$recipe" "$(tail -n 40 "/tmp/build-$recipe.log")"
done
vgs_pkg="$(package_file vgshell)"; git_pkg="$(package_file vgshell-git)"
# vgshell-git's prepare() cloned without file contents beyond its checkout:
# some object the history reaches is absent. git sets
# remote.origin.promisor even when the server ignored the filter, so the
# setting proves nothing.
objects="$(runuser -u builder -- git -C /build/vgshell-git/src/vgshell rev-list --objects --missing=print HEAD)" ||
  refuse "clone=unreadable package=vgshell-git"
grep -q '^?' <<<"$objects" || refuse "clone=unfiltered package=vgshell-git" "every object the history reaches is in /build/vgshell-git/src/vgshell"

# Whether a package named NAME, not one providing NAME, is installed.
installed() { # NAME
  local names
  names="$(pacman -Qq)" || refuse "pacman=query-failed"
  grep -qxF -e "$1" <<<"$names"
}
install_pkg() { # FILE NAME
  pacman -U --noconfirm "$1" >"/tmp/install-$2.log" 2>&1 ||
    refuse "install=failed package=$2" "$(tail -n 40 "/tmp/install-$2.log")"
  installed "$2" || refuse "install=absent package=$2"
}
vgshell_version() { # PACKAGE
  local out
  out="$(runuser -u builder -- vgshell --version 2>&1)" || refuse "vgshell=failed package=$1" "$out"
  [[ $out == "vgshell $version" ]] || refuse "vgshell-version=${out// /_} want=vgshell_$version package=$1"
}

# The doctor reads D-Bus requirements on a private system bus over the
# installed system-services directory, so such a requirement reads present
# only when an installed package can activate its name.
doctor_holds() { # PACKAGE
  local report bus_pid status=0
  mkdir -p /tmp/doctor-home /tmp/doctor-runtime /tmp/doctor-bus
  chown builder:builder /tmp/doctor-home /tmp/doctor-runtime
  printf '%s\n' '<busconfig>' '  <type>system</type>' '  <listen>unix:path=/tmp/doctor-bus/socket</listen>' '  <auth>EXTERNAL</auth>' \
    '  <standard_system_servicedirs/>' '  <policy context="default"><allow user="*"/><allow own="*"/><allow send_destination="*"/><allow receive_sender="*"/></policy>' \
    '</busconfig>' >/tmp/doctor-bus/bus.conf
  bus_pid="$(dbus-daemon --config-file=/tmp/doctor-bus/bus.conf --fork --print-pid 2>/tmp/doctor-bus.err)" ||
    refuse "doctor-bus=failed package=$1" "$(cat /tmp/doctor-bus.err)"
  report="$(runuser -u builder -- env -i PATH=/usr/bin HOME=/tmp/doctor-home XDG_CONFIG_HOME=/tmp/doctor-home/.config \
    XDG_RUNTIME_DIR=/tmp/doctor-runtime DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/doctor-bus/socket vgshell doctor --json 2>/tmp/doctor.err)" || status=$?
  kill "$bus_pid"
  [[ $status -eq 0 ]] || refuse "doctor=failed package=$1" "$(cat /tmp/doctor.err)"
  python -c 'import json,sys
report=json.loads(sys.argv[1])
missing=[row["name"] for rows in [report["core"], *report["plugins"].values()] for row in rows if not row["optional"] and row["state"] == "missing"]
if missing: sys.exit("missing required: " + ",".join(missing))
if not report["plugins"]: sys.exit("doctor plugin discovery is empty")' "$report" || refuse "doctor=required-missing package=$1"
}

# pacman printed every line of the installed first-install text when it
# installed PACKAGE.
message_printed() { # PACKAGE
  local line count=0 message=/usr/share/vgshell/bin/lib/post-install.txt
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    count=$((count + 1))
    grep -qxF -e "$line" "/tmp/install-$1.log" || refuse "message=absent package=$1 line=$count" "$line" "$(tail -n 20 "/tmp/install-$1.log")"
  done <"$message" || refuse "message=unreadable path=$message package=$1"
  [[ $count -gt 0 ]] || refuse "message=empty path=$message package=$1"
}

# The package's browser theme writer and its rule: real files root owns,
# a rule visudo accepts granting every user the writer with a colour alone,
# and the setup report reading done once a browser of the family is on
# PATH. The stand-in chromium runs nothing.
browser_policy() { # PACKAGE
  local file want info out rule
  rule='ALL ALL=(root) NOPASSWD: /usr/bin/vgshell-browser-policy [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]'
  for file in "/usr/bin/vgshell-browser-policy|regular file root:root 755" "/etc/sudoers.d/vgshell-theme-browser|regular file root:root 440"; do
    want="${file#*|}" file="${file%%|*}"
    info="$(stat -c '%F %U:%G %a' -- "$file" 2>&1)" || refuse "browser-policy=absent path=$file package=$1" "$info"
    [[ $info == "$want" ]] || refuse "browser-policy=${info// /_} want=${want// /_} path=$file package=$1"
  done
  command -v visudo >/dev/null || refuse "visudo=missing package=$1" "sudo is in the setup install, so visudo must be on PATH"
  out="$(visudo -cf /etc/sudoers.d/vgshell-theme-browser 2>&1)" || refuse "browser-policy=rule-refused package=$1" "$out"
  grep -qxF -e "$rule" /etc/sudoers.d/vgshell-theme-browser || refuse "browser-policy=grant package=$1" "$(cat /etc/sudoers.d/vgshell-theme-browser)"
  mkdir -p /tmp/browser-standin
  out="$(runuser -u builder -- env PATH=/usr/bin vgshell theme setup 2>&1)" || refuse "setup=failed package=$1" "$out"
  [[ $out == "setup=chromium command=vgshell-browser-policy state=done" ]] || refuse "setup=unexpected browser=installed package=$1" "$out"
  printf '#!/bin/sh\nexit 1\n' >/tmp/browser-standin/chromium
  chmod 755 /tmp/browser-standin/chromium
  out="$(runuser -u builder -- env PATH=/tmp/browser-standin:/usr/bin vgshell theme setup 2>&1)" || refuse "setup=failed package=$1" "$out"
  rm -f /tmp/browser-standin/chromium
  [[ $out == "setup=chromium command=vgshell-browser-policy state=done" ]] || refuse "setup=unexpected browser=chromium package=$1" "$out"
}

install_pkg "$vgs_pkg" vgshell
vgshell_version vgshell
doctor_holds vgshell
message_printed vgshell
link="$(readlink /usr/bin/vgshell)" || refuse "link=missing path=/usr/bin/vgshell"
[[ $link == ../share/vgshell/bin/vgshell ]] || refuse "link=$link path=/usr/bin/vgshell"
browser_policy vgshell
vgs_ver="$(pacman -Q vgshell)"; vgs_ver="${vgs_ver#vgshell }"

pacman -R --noconfirm vgshell >/tmp/remove-vgshell.log 2>&1 ||
  refuse "remove=failed package=vgshell" "$(tail -n 40 /tmp/remove-vgshell.log)"
! installed vgshell || refuse "remove=kept package=vgshell"
install_pkg "$git_pkg" vgshell-git
full="$(pacman -Q vgshell-git)"; full="${full#vgshell-git }"; pkgver="${full%-*}"
[[ $pkgver =~ ^[0-9]+\.[0-9]+\.[0-9]+\.r[0-9]+\.g([0-9a-f]{7,})$ && $commit == "${BASH_REMATCH[1]}"* ]] ||
  refuse "pkgver=$pkgver commit=$commit package=vgshell-git"
vgshell_version vgshell-git
doctor_holds vgshell-git
message_printed vgshell-git
browser_policy vgshell-git

echo "arch-packages: ok commit=$commit vgshell=$vgs_ver vgshell-git=$full"
RUN
chmod 755 "$scratch/in/run.sh"

if ! podman image exists "$image"; then
  pull_out="$(podman pull -q "$image" 2>&1)" || not_measured image-pull "$pull_out"
fi

status=0
podman run --rm \
  -v "$scratch/in:/in:ro" \
  -v "$cache:/var/cache/pacman/pkg" \
  "$image" /in/run.sh "$version" "$commit" || status=$?
case "$status" in
  0|1|77) exit "$status" ;;
  125) not_measured container-start "podman run exited 125" ;;
  *) refuse 1 "container=failed status=$status" ;;
esac
