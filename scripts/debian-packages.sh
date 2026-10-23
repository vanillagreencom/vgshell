#!/usr/bin/env bash
# Build the pinned amd64 engine in rootless Debian forky, with no host package action.
# Usage: scripts/debian-packages.sh [--output DIRECTORY]
# The output directory receives the release-named .deb. Build inputs are the
# working tree as git add -A would commit it. Missing podman exits 77;
# setup or build failure exits 1. Full logs remain on stdout/stderr.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
out="$repo/dist"
case "${1:-}" in
  '') [[ $# == 0 ]] ;;
  --output) [[ $# == 2 ]] || exit 2; out="$2" ;;
  -h|--help) sed -n '2,6{s/^# \{0,1\}//;p}' "${BASH_SOURCE[0]}"; exit 0 ;;
  *) exit 2 ;;
esac
refuse() { printf 'debian-packages: refused: %s\n' "$1" >&2; exit 1; }
command -v podman >/dev/null || { echo 'debian-packages: status=not-measured reason=podman-missing'; exit 77; }
[[ $(podman info --format '{{.Host.Security.Rootless}}') == true ]] || refuse 'container=not-rootless'
mkdir -p -- "$repo/tmp" "$out"
out="$(cd -- "$out" && pwd -P)"
scratch="$(mktemp -d -- "$repo/tmp/debian-packages.XXXXXX")" || refuse 'scratch=mktemp-failed'
trap 'rm -rf -- "${scratch:?}"' EXIT
mkdir "$scratch/source"
index="$scratch/index"
GIT_INDEX_FILE="$index" git -C "$repo" read-tree HEAD
GIT_INDEX_FILE="$index" git -C "$repo" add -A
tree="$(GIT_INDEX_FILE="$index" git -C "$repo" write-tree)"
git -C "$repo" archive "$tree" | tar -x -C "$scratch/source"
printf 'debian-packages: tree=%s architecture=amd64\n' "$tree"
status=0
podman run --rm --arch amd64 -v "$scratch/source:/source:ro" -v "$out:/output" \
  docker.io/library/debian:forky /bin/bash -euc '
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential curl ca-certificates \
  devscripts equivs patch
mkdir /build
cp -a /source/packaging/debian/vgshell-quickshell /build/debian
mk-build-deps --install --remove --tool "apt-get -y --no-install-recommends" /build/debian/control
revision=2b4501a282689792b62e94f3fb30d8f512324fe6
curl --fail --show-error --location --proto =https --proto-redir =https --tlsv1.2 \
  --max-time 120 "https://git.outfoxxed.me/quickshell/quickshell/archive/$revision.tar.gz" -o /build/source.tar.gz
printf "%s  %s\n" 326d14142c50578f0a4efc3fd1180cac5066256bfa7e09329e1d5167d1c3ccb6 /build/source.tar.gz | sha256sum -c -
mkdir /build/quickshell
tar -xzf /build/source.tar.gz --strip-components=1 -C /build/quickshell
mv /build/debian /build/quickshell/debian
cd /build/quickshell
for name in vgs-989-deletelater vgs-1109-log-filter-mutex vgs-1993-managed-process-lifetime; do
  patch --forward --fuzz=0 -p1 <"/source/packaging/arch/vgshell-quickshell/$name.patch"
done
chmod +x debian/rules
useradd --create-home builder
chown -R builder:builder /build
runuser -u builder -- env DEB_BUILD_OPTIONS=parallel=8 dpkg-buildpackage --build=binary --no-sign
version="$(dpkg-parsechangelog -S Version)"
asset="vgshell-quickshell_${version}_debian-forky_amd64.deb"
cp "/build/vgshell-quickshell_${version}_amd64.deb" "/output/$asset"
[[ $(dpkg-deb --field "/output/$asset" Package) == vgshell-quickshell ]]
[[ $(dpkg-deb --field "/output/$asset" Version) == "$version" ]]
[[ $(dpkg-deb --field "/output/$asset" Architecture) == amd64 ]]
dpkg-deb --field "/output/$asset" Package Version Architecture
printf "debian-packages: built=%s\n" "$asset"
' || status=$?
[[ $status == 0 ]] || refuse "build=failed exit=$status"
