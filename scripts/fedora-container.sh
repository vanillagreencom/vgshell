#!/usr/bin/env bash
# Build and install both Fedora packages in a clean Fedora container.
#
# Usage: scripts/fedora-container.sh [--image IMAGE]
#
# The pre-publication test of COPR vanillagreen/vgshell, run by hand before the
# project is created and before a new Fedora release's chroots are added:
# docs/architecture/distribution-fedora.md. IMAGE defaults to
# registry.fedoraproject.org/fedora:44. Needs podman and the network; the
# host's session, configuration and package manager are never touched.
#
# On the host it clones HEAD into a scratch directory and packs HEAD's
# release tarball with scripts/lib/release-tarball.sh, the builder
# scripts/release calls. Inside the container it enables the repositories
# packaging/fedora/copr-project names; writes the vgshell-git source RPM
# through .copr/Makefile, as COPR does; tags the clone v<VERSION> and
# writes the vgshell source RPM from that tarball; installs each source RPM's
# build dependencies and rebuilds it as an unprivileged user, failing on any
# RPM warning; installs sudo, then vgshell, checks that each floor's epoch is
# its installed provider's, then checks `vgshell --version`, the /usr/bin/vgshell
# link, the preflight, that dnf's output holds every line of the
# first-install text, and the browser theme writer and its rule: a regular
# /usr/bin/vgshell-browser-policy root:root 0755 and
# /etc/sudoers.d/vgshell-theme-browser root:root 0440 that `visudo -cf`
# accepts, granting every user the writer with six hex classes, with
# `vgshell theme setup` reading the chromium setup not-detected without a
# browser and done with a stand-in chromium on PATH; proves vgshell-git
# refuses to install beside vgshell,
# replaces it with --allowerasing, provides vgshell at its own version, and
# passes the same checks; and proves vgshell then refuses to install beside
# vgshell-git.
#
# The preflight runs twice per package. `vgshell run` with no Hyprland must
# refuse at hyprland alone, so the installed Quickshell met its floor. Then
# a stand-in hyprctl that reports the installed hyprland package's version
# lets `vgshell restart` pass the whole floor and refuse at shell=not-running.
#
# Exit 0: every check passed. Exit 1: a check failed. Exit 2: bad usage or a
# dirty tree. Exit 77: podman, the image or the package repositories could
# not be reached; that is not a pass.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"

inside() {
  local version srpm srpm_git srpm_rel git_version rpms hypr_version out status line key value want have floor_re
  fail() { printf 'fedora-container: fail: %s\n' "$*" >&2; exit 1; }
  step() { printf 'fedora-container: %s\n' "$*"; }
  # Runs COMMAND with its output in /work/logs/NAME.log, printed only when
  # it fails; leaves the log's last line in $line.
  logged() { # NAME COMMAND...
    local name="$1"
    shift
    if ! "$@" >"/work/logs/$name.log" 2>&1; then
      tail -n 60 -- "/work/logs/$name.log" >&2
      fail "$name: $*"
    fi
    line="$(tail -n 1 -- "/work/logs/$name.log")"
  }
  # True when installing RPM failed because of the vgshell conflict, not for
  # any other cause; prints dnf's conflict line.
  refused_as_conflict() { # NAME RPM
    ! dnf -y install "$2" >"/work/logs/$1.log" 2>&1 &&
      grep -m 1 -E 'conflicts with vgshell provided by vgshell(-git)?-[0-9]' "/work/logs/$1.log" | sed 's/^ */fedora-container: refused as wanted: /'
  }

  cd /work/src
  mkdir -p /work/logs /work/out
  version="$(cat VERSION)"
  dnf -y makecache >/work/logs/makecache.log 2>&1 ||
    { echo 'fedora-container: status=not-measured reason=repositories-unreachable' >&2; exit 77; }
  logged tools dnf -y install make dnf-plugins-core sudo
  while read -r key value; do
    [[ $key == repo ]] || continue
    logged "copr-${value//\//-}" dnf -y copr enable "$value"
    step "enabled copr $value"
  done <packaging/fedora/copr-project

  logged srpm-vgshell-git make -s -f .copr/Makefile srpm outdir=/work/out spec=packaging/fedora/vgshell-git.spec
  [[ $line =~ ^srpm:\ ok\ path=([^ ]+)\ version=([^ ]+)$ ]] || fail "vgshell-git srpm printed: $line"
  srpm_git="${BASH_REMATCH[1]}" git_version="${BASH_REMATCH[2]}"
  [[ $git_version =~ ^[0-9]+\.[0-9]+\.[0-9]+\^[0-9]+\.git[0-9a-f]+$ ]] || fail "vgshell-git version $git_version"
  step "vgshell-git source RPM $git_version"

  # The scratch clone's release tag, moved to HEAD, so the release package
  # is built from this tree whether or not v<VERSION> exists upstream. The
  # host packed HEAD's tarball.
  git tag -f "v$version" >/dev/null
  logged srpm-vgs packaging/fedora/srpm.sh --spec packaging/fedora/vgshell.spec --outdir /work/out --tarball "/work/vgshell-$version.tar.gz"
  [[ $line =~ ^srpm:\ ok\ path=([^ ]+)\ version=$version$ ]] || fail "vgshell srpm printed: $line"
  srpm_rel="${BASH_REMATCH[1]}"
  step "vgshell source RPM $version"

  useradd -m builder
  for srpm in "$srpm_rel" "$srpm_git"; do
    logged "builddep-${srpm##*/}" dnf -y builddep "$srpm"
    logged "rebuild-${srpm##*/}" runuser -u builder -- rpmbuild --rebuild --define '_topdir /home/builder/rpmbuild' "$srpm"
    ! grep -E '^(warning|error):' "/work/logs/rebuild-${srpm##*/}.log" ||
      fail "rpmbuild --rebuild ${srpm##*/} printed the warnings above"
  done
  rpms=/home/builder/rpmbuild/RPMS/noarch
  step "built $(cd "$rpms" && echo *.rpm)"

  hypr_version=""
  checks() { # WANT_PACKAGE
    local link err text count=0
    # dnf prefixes each line a scriptlet prints.
    while IFS= read -r text; do
      [[ -n $text ]] || continue
      count=$((count + 1))
      grep -qF -e "$text" "/work/logs/install-$1.log" || fail "install-$1.log lacks line $count of the first-install text: $text"
    done </usr/share/vgshell/bin/lib/post-install.txt
    [[ $count -gt 0 ]] || fail "/usr/share/vgshell/bin/lib/post-install.txt is empty"
    out="$(vgshell --version)" || fail "vgshell --version exited $?"
    [[ $out == "vgshell $version" ]] || fail "vgshell --version printed [$out], want [vgshell $version]"
    link="$(readlink /usr/bin/vgshell)"
    [[ $link == ../share/vgshell/bin/vgshell ]] || fail "/usr/bin/vgshell links to [$link]"
    rpm -V "$1" || fail "rpm -V $1"
    [[ -n $hypr_version ]] || hypr_version="$(rpm -q --qf '%{VERSION}' hyprland)"
    mkdir -p /tmp/rt /tmp/standin
    chown builder /tmp/rt
    cat >/tmp/standin/hyprctl <<EOF
#!/bin/bash
[[ \$* == "-j version" ]] || exit 1
printf '{"version": "%s"}\n' "$hypr_version"
EOF
    chmod 755 /tmp/standin/hyprctl
    set +e
    err="$(runuser -u builder -- env XDG_RUNTIME_DIR=/tmp/rt vgshell run 2>&1 >/dev/null)"
    status=$?
    set -e
    [[ $status == 78 && ${err%%$'\n'*} == "vgshell: refused: preflight=hyprland have=unknown need=0.56" ]] ||
      fail "vgshell run with no Hyprland: exit=$status stderr=[$err]"
    set +e
    err="$(runuser -u builder -- env XDG_RUNTIME_DIR=/tmp/rt PATH="/tmp/standin:$PATH" vgshell restart 2>&1 >/dev/null)"
    status=$?
    set -e
    [[ $status == 69 && ${err%%$'\n'*} == "vgshell: refused: shell=not-running lock=/tmp/rt/vgshell.lock" ]] ||
      fail "vgshell restart past the preflight with hyprland $hypr_version: exit=$status stderr=[$err]"
    step "$1: vgshell --version, /usr/bin/vgshell and the preflight hold (hyprland $hypr_version)"
    browser_policy "$1"
  }

  # The package's browser theme writer and its rule: real files root owns,
  # a rule visudo accepts granting every user the writer with a colour alone,
  # and the setup report reading done once a browser of the family is on
  # PATH. The stand-in chromium runs nothing.
  browser_policy() { # PACKAGE
    local file want info rule
    rule='ALL ALL=(root) NOPASSWD: /usr/bin/vgshell-browser-policy [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]'
    for file in "/usr/bin/vgshell-browser-policy|regular file root:root 755" "/etc/sudoers.d/vgshell-theme-browser|regular file root:root 440"; do
      want="${file#*|}" file="${file%%|*}"
      info="$(stat -c '%F %U:%G %a' -- "$file" 2>&1)" || fail "$1: $file: $info"
      [[ $info == "$want" ]] || fail "$1: $file is [$info], want [$want]"
    done
    command -v visudo >/dev/null || fail "$1: visudo is missing though sudo was installed"
    out="$(visudo -cf /etc/sudoers.d/vgshell-theme-browser 2>&1)" || fail "$1: visudo refused the rule: $out"
    grep -qxF -e "$rule" /etc/sudoers.d/vgshell-theme-browser || fail "$1: the rule grants [$(cat /etc/sudoers.d/vgshell-theme-browser)], want [$rule]"
    mkdir -p /tmp/browser-standin
    out="$(runuser -u builder -- env PATH=/usr/bin vgshell theme setup 2>&1)" || fail "$1: vgshell theme setup without a browser: $out"
    [[ $out == "setup=chromium command=vgshell-browser-policy state=not-detected" ]] || fail "$1: vgshell theme setup without a browser printed [$out]"
    printf '#!/bin/sh\nexit 1\n' >/tmp/browser-standin/chromium
    chmod 755 /tmp/browser-standin/chromium
    out="$(runuser -u builder -- env PATH=/tmp/browser-standin:/usr/bin vgshell theme setup 2>&1)" || fail "$1: vgshell theme setup with a stand-in chromium: $out"
    rm -f /tmp/browser-standin/chromium
    [[ $out == "setup=chromium command=vgshell-browser-policy state=done" ]] || fail "$1: vgshell theme setup with a stand-in chromium printed [$out]"
    step "$1: the browser theme writer and its rule hold, and the chromium setup reads done"
  }

  logged install-vgs dnf -y install "$rpms/vgshell-$version-"*.noarch.rpm
  step "installed $(rpm -q vgshell) with $(rpm -q quickshell hyprland | tr '\n' ' ')"
  # Each floor's epoch is the one its installed provider carries, so no
  # floor reads as epoch 0 against an epoch-1 package.
  floor_re='^([^ ]+) >= (([0-9]+):)?[^ ]+$'
  while read -r key value; do
    [[ $key == Requires: && $value =~ $floor_re ]] || continue
    want="${BASH_REMATCH[3]:-0}"
    have="$(rpm -q --whatprovides "${BASH_REMATCH[1]}" --qf '%{EPOCHNUM}\n' | head -n 1)"
    [[ $have == "$want" ]] || fail "Requires: $value names epoch $want; the installed ${BASH_REMATCH[1]} has epoch $have"
    step "floor ${BASH_REMATCH[1]} epoch $want matches the installed package"
  done < <(sed -n '/^# begin runtime dependencies$/,/^# end runtime dependencies$/p' packaging/fedora/vgshell.spec)
  checks vgshell

  refused_as_conflict refuse-vgshell-git "$(echo "$rpms"/vgshell-git-*.noarch.rpm)" ||
    fail "vgshell-git beside vgshell was not refused as a conflict: $(tail -n 5 /work/logs/refuse-vgshell-git.log)"
  logged install-vgshell-git dnf -y install --allowerasing "$rpms"/vgshell-git-*.noarch.rpm
  ! rpm -q vgshell >/dev/null || fail "vgshell is still installed beside vgshell-git"
  out="$(rpm -q --qf '%{VERSION}' vgshell-git)"
  [[ $out == "$git_version" ]] || fail "vgshell-git version [$out], want [$git_version]"
  out="$(rpm -q --whatprovides --qf '%{NAME} %{VERSION}\n' vgshell)"
  [[ $out == "vgshell-git $git_version" ]] || fail "vgshell provided by [$out]"
  checks vgshell-git

  refused_as_conflict refuse-vgs "$(echo "$rpms/vgshell-$version-"*.noarch.rpm)" ||
    fail "vgshell beside vgshell-git was not refused as a conflict: $(tail -n 5 /work/logs/refuse-vgs.log)"
  step "ok vgshell=$version vgshell-git=$git_version"
}

if [[ ${1:-} == --inside ]]; then
  inside
  exit 0
fi

image=registry.fedoraproject.org/fedora:44
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) sed -n '2,40{s/^# \{0,1\}//;p}' "$self"; exit 0 ;;
    --image)
      [[ $# -ge 2 && -n $2 ]] || { echo 'fedora-container: refused: argument=--image value=missing' >&2; exit 2; }
      image="$2"; shift 2 ;;
    *) printf 'fedora-container: refused: argument=%s\n' "$1" >&2; exit 2 ;;
  esac
done

command -v podman >/dev/null || { echo 'fedora-container: status=not-measured missing=podman' >&2; exit 77; }
repo="$(git -C "$(dirname -- "$self")" rev-parse --show-toplevel)"
if [[ -n $(git -C "$repo" status --porcelain --untracked-files=normal) ]]; then
  echo 'fedora-container: refused: tree=dirty' >&2
  echo 'the test builds HEAD; commit or stash first' >&2
  exit 2
fi
head="$(git -C "$repo" rev-parse --verify HEAD)"

work="$(mktemp -d "${TMPDIR:-/tmp}/vgs-fedora.XXXXXX")" || { echo 'fedora-container: scratch=mktemp-failed' >&2; exit 1; }
[[ -d $work && ! -L $work ]] || { echo "fedora-container: scratch=not-a-directory value=[$work]" >&2; exit 1; }
# A file the container left under a subordinate uid needs podman's namespace.
cleanup() { rm -rf -- "$work" 2>/dev/null || podman unshare rm -rf -- "$work"; }
trap cleanup EXIT
# The container's unprivileged builder reads the source RPMs under it.
chmod 755 "$work"
git clone -q --no-hardlinks -- "$repo" "$work/src"
git -C "$work/src" checkout -q --detach "$head"
version="$(<"$repo/VERSION")"
"$repo/scripts/lib/release-tarball.sh" "$head" "$version" "$work/vgshell-$version.tar.gz" >/dev/null ||
  { echo "fedora-container: fail: archive=failed commit=$head" >&2; exit 1; }
cp -- "$self" "$work/run.sh"

set +e
podman run --rm --pull=missing -v "$work:/work:Z" "$image" bash /work/run.sh --inside
status=$?
set -e
case "$status" in
  0|1|77) exit "$status" ;;
  125) printf 'fedora-container: status=not-measured reason=podman image=%s\n' "$image" >&2; exit 77 ;;
  *) printf 'fedora-container: fail: container exited %s\n' "$status" >&2; exit 1 ;;
esac
