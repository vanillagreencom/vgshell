#!/usr/bin/env bash
# Controls for `vgshell self status [--json]` and `vgshell self update`: one tree
# per install method, each a copy under $tmp, never this repository's own
# checkout. A checkout clones a local bare repository; a curl install is a
# versioned directory under a fixture XDG_DATA_HOME with a `current` link; a
# package tree is owned by a stub pacman under a fixture Arch os-release,
# bound over /etc/os-release under `unshare -rm`; a Nix tree lies under a
# fixture NIX_STORE_DIR. The newest release is a local release fixture
# served on 127.0.0.1, and main's commit for vgshell-git comes from the bare
# repository through the fixture home's url.insteadOf. Every row runs with a
# PATH of the tools vgshell, its judges and the installer call, and no real
# package manager. Expected values come from the fixtures' own git and
# files, never from vgshell. The controls at the end run copies of self.js
# with one rule removed.
set -euo pipefail

# shellcheck source=scripts/vgshell-rows.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"

unshare_bin="$(command -v unshare)" || { echo "test-vgshell-self: status=not-measured missing=unshare"; exit 77; }
"$unshare_bin" -rm true 2>/dev/null || { echo "test-vgshell-self: status=not-measured missing=user-namespaces"; exit 77; }
mount_bin="$(command -v mount)" || { echo "test-vgshell-self: status=not-measured missing=mount"; exit 77; }

# The rows' PATH: stubs first, then the tools bin/vgshell, bin/lib/self.js,
# bin/vgshell-pkg and packaging/install-system.sh call.
stubs="$tmp/stubs"; tools="$tmp/tools"; mkdir -p "$stubs" "$tools"
for tool in bash sh readlink dirname mkdir flock awk git mktemp mv rm head cat setsid timeout env tar gzip python3 cp ln sed setpriv date grep; do
  tool_bin="$(command -v "$tool")" || { echo "test-vgshell-self: status=not-measured missing=$tool"; exit 77; }
  ln -s -- "$tool_bin" "$tools/$tool"
done
ln -s -- "$node_bin" "$tools/node"
INST_PATH="$stubs:$tools"; export INST_PATH
# probe_migration TREE NAME: a migration in TREE that appends its own name
# and the tree it ran from to the fixture home's `migrated`.
probe_migration() {
  printf '%s\n' 'printf "%s %s\n" "$VGS_MIGRATION" "$VGS_ROOT" >>"$HOME/migrated"' >"$1/bin/migrations/$2"
}

version_text="0.1.0"
release="0.2.0"
cfg="$tmp/cfg-self"
data="$tmp/data"

# Install source DIR's tree with the shared installer and move its runtime
# tree to TARGET, as every channel lays it out.
install_tree() { # SOURCE TARGET
  local stage
  stage="$(mktemp -d "$tmp/stage.XXXXXX")"
  DESTDIR="$stage" PREFIX=/p TMPDIR="$tmp" bash "$1/packaging/install-system.sh" >/dev/null
  mkdir -p "$(dirname -- "$2")"
  mv -T -- "$stage/p/share/vgshell" "$2"
}

# The release fixture: the GitHub API's latest-release document and its two
# assets, served from $www on 127.0.0.1. The server writes its port once it
# listens; the EXIT trap stops it.
www="$tmp/www"; mkdir -p "$www/dl" "$www/repos/vanillagreencom/vgshell/releases"
ready="$tmp/www-port"
python3 -c '
import functools, http.server, os, sys
class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=sys.argv[2]))
with open(sys.argv[1] + ".part", "w") as f:
    f.write(str(server.server_address[1]))
os.rename(sys.argv[1] + ".part", sys.argv[1])
server.serve_forever()
' "$ready" "$www" </dev/null >/dev/null 2>&1 &
www_pid=$!
trap 'kill "$www_pid" 2>/dev/null || true; rm -rf -- "${tmp:?}"' EXIT
for _ in $(seq 1 100); do
  [[ -s $ready ]] && break
  sleep 0.1 # the server binds in its own process; poll for its port file
done
port="$(cat -- "$ready" 2>/dev/null)" || port=""
[[ $port =~ ^[0-9]+$ ]] || { echo "test-vgshell-self: release-server=not-listening" >&2; exit 1; }
api="http://127.0.0.1:$port"
archive="vgshell-$release.tar.gz"
source_tree "$tmp/rel/vgshell-$release" "$release"
probe_migration "$tmp/rel/vgshell-$release" 1000000001-release-probe.sh
tar -C "$tmp/rel" -czf "$www/dl/$archive" "vgshell-$release"
good_sum="$(sha256sum "$www/dl/$archive" | cut -d' ' -f1)"
printf '%s  %s\n' "$good_sum" "$archive" >"$www/dl/SHA256SUMS"
printf '{"tag_name":"v%s","assets":[{"name":"%s","browser_download_url":"%s/dl/%s"},{"name":"SHA256SUMS","browser_download_url":"%s/dl/SHA256SUMS"}]}\n' \
  "$release" "$archive" "$api" "$archive" "$api" >"$www/repos/vanillagreencom/vgshell/releases/latest"
inst_env=(VGS_RELEASE_API="$api" XDG_DATA_HOME="$data" NIX_STORE_DIR="$tmp/nix/store")

status_json() { # VERSION METHOD PACKAGE CURRENT LATEST BEHIND ERROR: null for an absent value
  python3 -c 'import json, sys
v = [None if a == "null" else a for a in sys.argv[1:]]
b = {"true": True, "false": False, None: None}[v[5]]
print(json.dumps({"version": v[0], "method": v[1], "package": v[2], "current": v[3], "latest": v[4], "behind": b, "error": v[6]}, separators=(",", ":")))' "$@"
}

# Checkout. The upstream is a bare repository; git hooks are live for every
# git call from here on through the fixture home's core.hooksPath, whose
# reference-transaction hook leaves a marker when a ref moves.
seed="$tmp/seed"; source_tree "$seed" "$version_text"
g init -q "$seed"; g -C "$seed" add -A; g -C "$seed" commit -q -m one
upstream="$tmp/up.git"; g init -q --bare "$upstream"; g -C "$seed" push -q "$upstream" main
co="$tmp/co"; g clone -q "$upstream" "$co"
hooks="$tmp/hooks"; mkdir -p "$hooks"; marker="$hooks/reference-transaction.marker"
printf '#!/bin/sh\nprintf "" >"$0.marker"\n' >"$hooks/reference-transaction"; chmod +x "$hooks/reference-transaction"
g config --global core.hooksPath "$hooks"
g -C "$seed" commit -q --allow-empty -m probe; g -C "$seed" push -q "$upstream" main
rm -f -- "$marker"; g -C "$co" fetch -q
check "a plain fetch under the fixture configuration runs the reference-transaction hook" test -e "$marker"
g -C "$co" merge -q --ff-only origin/main
describe() { printf '%s.r%s.g%s' "$version_text" "$(g -C "$1" rev-list --count "$2")" "$(g -C "$1" rev-parse --short "$2")"; }
here="$(describe "$co" HEAD)"
rm -f -- "$marker"
INST_BIN="$co/bin/vgshell" inst "a current checkout is not behind" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" checkout null "$here" "$here" false null)" "" self status --json
check "status runs no git hook" test ! -e "$marker"
# The upstream's next commit ships a migration, which the update runs
# from the updated checkout.
probe_migration "$seed" 1000000000-checkout-probe.sh
g -C "$seed" add -A; g -C "$seed" commit -q -m two; g -C "$seed" push -q "$upstream" main; rm -f -- "$marker"
there="$(describe "$seed" HEAD)"
INST_BIN="$co/bin/vgshell" inst "a checkout behind its upstream names the upstream's describe form" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" checkout null "$here" "$there" true null)" "" self status --json
check "the behind status runs no git hook either" test ! -e "$marker"
INST_BIN="$co/bin/vgshell" inst "the text form is one line of fields" "$cfg" "$rt_empty" 0 "version=$version_text method=checkout current=$here latest=$there behind=true" "" self status
check "status leaves HEAD where it was" test "$(g -C "$co" rev-parse --short HEAD)" == "${here##*.g}"

printf 'local\n' >"$co/LOCAL"
INST_BIN="$co/bin/vgshell" inst "update refuses a modified checkout" "$cfg" "$rt_empty" 1 "" "vgshell: refused: modified=$co" self update
rm -- "$co/LOCAL"
old="$(g -C "$co" rev-parse HEAD)" new="$(g -C "$upstream" rev-parse main)"
INST_BIN="$co/bin/vgshell" inst "update fast-forwards the checkout and names no running shell" "$cfg" "$rt_empty" 0 "shell=not-running" "" self update
check "update prints the commits it moved between" has_line "ok updated=vgshell from=${old:0:12} to=${new:0:12}"
check "the checkout is at its upstream" test "$(g -C "$co" rev-parse HEAD)" == "$new"
check "update runs the updated checkout's new migration" has_line "vgshell-migrate: ran=1000000000-checkout-probe.sh"
check "the migration ran from the checkout" grep -qxF "1000000000-checkout-probe.sh $co" "$tmp/home/migrated"
check "update runs no git hook" test ! -e "$marker"
INST_BIN="$co/bin/vgshell" inst "a current checkout is up to date" "$cfg" "$rt_empty" 0 "ok up-to-date=vgshell" "" self update
g -C "$co" remote set-url origin "$tmp/gone.git"
INST_BIN="$co/bin/vgshell" inst "an unreachable upstream is the report's error, exit 0" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" checkout null "$there" null null "fetch=vgshell")" "$any_out" self status --json
# A stop during the checkout's fetch: status ends the fetch, returns once
# it ended and exits 128 plus the signal, printing no report. The stop
# controls are test-vgshell-outdated.sh's.
stop_git slow
INST_BIN="$co/bin/vgshell" stop_run TERM self status --json
check "TERM during a checkout's fetch ends self status with exit 143" test "$stop_status" == 143
check "self status stopped during a checkout's fetch prints no report" test ! -s "$tmp/out"
check "self status returns after the checkout's fetch TERM stopped has ended" test "$stop_ended/$stop_alive" == yes/no

# Curl: a versioned directory with a `current` link, an older version to
# prune, and the command through the link as ~/.local/bin/vgshell reaches it.
install_tree "$seed" "$data/vgshell/$version_text"
install_tree "$seed" "$data/vgshell/0.0.9"
ln -s -- "$version_text" "$data/vgshell/current"
curl_bin="$data/vgshell/current/bin/vgshell"
INST_BIN="$curl_bin" inst "a curl install compares VERSION with the newest release" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" curl null "$version_text" "$release" true null)" "" self status --json
saved_env=("${inst_env[@]}")
inst_env=(VGS_RELEASE_API="$api/elsewhere" XDG_DATA_HOME="$data")
INST_BIN="$curl_bin" inst "a repository with no release is the report's error" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" curl null "$version_text" null null "release=none repository=vanillagreencom/vgshell")" "" self status --json
inst_env=(VGS_RELEASE_API="http://example.invalid" XDG_DATA_HOME="$data")
INST_BIN="$curl_bin" inst "a release API other than loopback is refused" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" curl null "$version_text" null null 'release-api=refused value="http://example.invalid"')" "$any_out" self status --json
inst_env=("${saved_env[@]}")
INST_TEST_RUN="" INST_BIN="$curl_bin" inst "a loopback release API outside a test run is refused" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" curl null "$version_text" null null "release-api=refused value=\"$api\"")" "$any_out" self status --json

printf '%s  %s\n' "$(printf '0%.0s' $(seq 1 64))" "$archive" >"$www/dl/SHA256SUMS"
INST_BIN="$curl_bin" inst "update refuses an archive its SHA256SUMS does not list" "$cfg" "$rt_empty" 1 "" \
  "vgshell: refused: checksum=mismatch name=$archive want=$(printf '0%.0s' $(seq 1 64)) got=$good_sum" self update
check "a refused update keeps the current link" test "$(readlink -- "$data/vgshell/current")" == "$version_text"
check "a refused update leaves no new version and no staging directory" test -z "$(find "$data/vgshell" -maxdepth 1 \( -name "$release" -o -name '.self-update-*' \))"
printf '%s  %s\n' "$good_sum" "$archive" >"$www/dl/SHA256SUMS"
exec 7>>"$data/vgshell/.self.lock"; flock 7
INST_BIN="$curl_bin" inst "a held self lock refuses the update busy" "$cfg" "$rt_empty" 75 "" "vgshell: refused: self=busy path=$data/vgshell/.self.lock" self update
exec 7>&-
INST_BIN="$curl_bin" inst "update installs the newest release and names no running shell" "$cfg" "$rt_empty" 0 "shell=not-running" "" self update
check "update prints the versions and the new tree" has_line "ok updated=vgshell from=$version_text to=$release path=$data/vgshell/$release"
check "update runs the new tree's migration" has_line "vgshell-migrate: ran=1000000001-release-probe.sh"
check "the migration ran from the new tree" grep -qxF "1000000001-release-probe.sh $data/vgshell/$release" "$tmp/home/migrated"
check "the current link names the new version" test "$(readlink -- "$data/vgshell/current")" == "$release"
check "the new tree is the release's" test "$(<"$data/vgshell/$release/VERSION")" == "$release"
check "the new tree's command runs" test -x "$data/vgshell/$release/bin/vgshell"
check "the tree that was current stays" test -d "$data/vgshell/$version_text"
check "every other version is removed" test ! -e "$data/vgshell/0.0.9"
check "no staging directory stays" test -z "$(find "$data/vgshell" -maxdepth 1 -name '.self-update-*')"
INST_BIN="$curl_bin" inst "the new tree is current" "$cfg" "$rt_empty" 0 "$(status_json "$release" curl null "$release" "$release" false null)" "" self status --json
INST_BIN="$curl_bin" inst "a current curl install is up to date" "$cfg" "$rt_empty" 0 "ok up-to-date=vgshell version=$release" "" self update

# A shell whose restart was refused still runs from a tree `current` no
# longer names. A stub qs started as `qs -p <tree>/shell`, as `vgshell run`
# execs it, with its pid in the instance lock, stands in for that shell.
# The update keeps its tree; the restart then refuses below the runtime
# floor, since the stub answers no version.
cat >"$stubs/qs" <<'EOF'
#!/bin/sh
[ "$1" = -p ] || exit 1
while :; do sleep 1; done
EOF
chmod +x "$stubs/qs"
running_layout() { # DATA: current 0.1.0, the running shell's 0.0.8, a stale 0.0.7
  install_tree "$seed" "$1/vgshell/$version_text"
  install_tree "$seed" "$1/vgshell/0.0.8"
  install_tree "$seed" "$1/vgshell/0.0.7"
  ln -s -- "$version_text" "$1/vgshell/current"
}
rt_running="$tmp/rt-running"; mkdir -p "$rt_running"
running_data="$tmp/data-running"; running_layout "$running_data"
"$stubs/qs" -p "$running_data/vgshell/0.0.8/shell" &
fake_shell=$!
trap 'kill "$fake_shell" "$www_pid" 2>/dev/null || true; rm -rf -- "${tmp:?}"' EXIT
printf '%s\n' "$fake_shell" >"$rt_running/vgshell.lock"
inst_env=(VGS_RELEASE_API="$api" XDG_DATA_HOME="$running_data")
# The release's migration ran in the curl rows above, so the update's run
# finds none pending before the restart.
INST_BIN="$running_data/vgshell/current/bin/vgshell" inst "an update beside a running shell restarts it, refused here below the floor" "$cfg" "$rt_running" 78 \
  "vgshell-migrate: ok ran=0" "vgshell: refused: preflight=quickshell have=unknown need=0.3.1" self update
check "the update beside a running shell names the new tree" has_line "ok updated=vgshell from=$version_text to=$release path=$running_data/vgshell/$release"
check "the running shell's tree stays" test -d "$running_data/vgshell/0.0.8/shell"
check "the tree the update ran from stays" test -d "$running_data/vgshell/$version_text"
check "a tree nothing runs is removed" test ! -e "$running_data/vgshell/0.0.7"
kill "$fake_shell" 2>/dev/null || true
inst_env=("${saved_env[@]}")

# Package: the tree a package recipe installs, owned by a stub pacman
# answering -Qoq and -Q as pacman(8) states, for the file and package the
# row names; any other call exits 99. The os-release fixture names Arch.
pkg_root="$tmp/pkgroot/usr/share/vgshell"; install_tree "$seed" "$pkg_root"
cat >"$stubs/pacman" <<'EOF'
#!/bin/sh
case "$1 $2 $3" in
  "-Qoq $STUB_OWNED ") [ -n "$STUB_PACKAGE" ] && { echo "$STUB_PACKAGE"; exit 0; } ;;
  "-Q -- $STUB_PACKAGE") echo "$STUB_PACKAGE $STUB_PKGVER-1"; exit 0 ;;
  *) exit 99 ;;
esac
echo "error: No package owns $2" >&2
exit 1
EOF
chmod +x "$stubs/pacman"
printf 'NAME="Arch Linux"\nID=arch\n' >"$tmp/os-release"
cat >"$tmp/bound-vgshell" <<EOF
#!$tools/sh
exec $unshare_bin -rm $tools/sh -c 'mount_bin=\$1 fixture=\$2; shift 2; "\$mount_bin" --bind "\$fixture" /etc/os-release && exec "\$@"' sh $mount_bin $tmp/os-release $pkg_root/bin/vgshell "\$@"
EOF
chmod +x "$tmp/bound-vgshell"
g config --global "url.$upstream.insteadOf" https://github.com/vanillagreencom/vgshell.git
main_commit="$(g -C "$upstream" rev-parse main)"
built="$version_text.r7.g${main_commit:0:7}"
inst_env+=(STUB_OWNED="$pkg_root/VERSION" STUB_PACKAGE=vgshell-git STUB_PKGVER="$built")
INST_BIN="$tmp/bound-vgshell" inst "a vgshell-git package built from main's commit is not behind" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" package vgshell-git "$built" "$main_commit" false null)" "" self status --json
g -C "$seed" commit -q --allow-empty -m three; g -C "$seed" push -q "$upstream" main
main_commit="$(g -C "$upstream" rev-parse main)"
INST_BIN="$tmp/bound-vgshell" inst "a vgshell-git package is behind once main moves" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" package vgshell-git "$built" "$main_commit" true null)" "" self status --json
# A stop during the ls-remote of main, as during a checkout's fetch.
INST_BIN="$tmp/bound-vgshell" stop_run TERM self status --json
check "TERM during main's ls-remote ends self status with exit 143" test "$stop_status" == 143
check "self status stopped during main's ls-remote prints no report" test ! -s "$tmp/out"
check "self status returns after the ls-remote TERM stopped has ended" test "$stop_ended/$stop_alive" == yes/no
INST_BIN="$tmp/bound-vgshell" inst "update refuses a package and names its manager" "$cfg" "$rt_empty" 1 "" "vgshell: refused: method=package package=vgshell-git manager=pacman" self update
inst_env+=(STUB_PACKAGE=vgshell STUB_PKGVER="$version_text")
INST_BIN="$tmp/bound-vgshell" inst "a vgshell package compares its version with the newest release" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" package vgshell "$version_text" "$release" true null)" "" self status --json
inst_env+=(STUB_PACKAGE=vgs-shell)
INST_BIN="$tmp/bound-vgshell" inst "a package that is not vgshell is the report's error" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" null null null null null "package=vgs-shell manager=pacman reason=not-vgs")" "" self status --json
inst_env+=(STUB_PACKAGE=)
INST_BIN="$tmp/bound-vgshell" inst "a tree no method claims is method=unknown" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" null null null null null "method=unknown path=$pkg_root")" "$any_out" self status --json
inst_env=("${saved_env[@]}")

# Nix: a tree under the fixture store.
nix_root="$tmp/nix/store/0000-vgshell-$version_text/share/vgshell"; install_tree "$seed" "$nix_root"
INST_BIN="$nix_root/bin/vgshell" inst "a Nix tree compares VERSION with the newest release" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" nix null "$version_text" "$release" true null)" "" self status --json
INST_BIN="$nix_root/bin/vgshell" inst "update refuses a Nix tree" "$cfg" "$rt_empty" 1 "" "vgshell: refused: method=nix" self update

for args in 'self' 'self sync' 'self status extra' 'self status --json extra' 'self update extra'; do
  read -r -a words <<<"$args"
  case "$args" in
    self) want="self-subcommand=missing" ;;
    'self sync') want="self-subcommand=sync" ;;
    *) want="argument=${words[-1]}" ;;
  esac
  INST_BIN="$co/bin/vgshell" inst "$args is a bad invocation" "$cfg" "$rt_empty" 2 "" "vgshell: refused: $want" "${words[@]}"
done

# The must-fail controls: copies of the Nix tree whose self.js lacks one
# rule, each shown to answer what the rows above refuse to accept.
self_control() { # NAME NEEDLE REPLACEMENT: sets control_bin to the copy's vgshell
  local tree_copy="$tmp/nix/store/$1-vgs/share/vgshell"
  mkdir -p "$(dirname -- "$tree_copy")"
  cp -R -- "$nix_root" "$tree_copy"
  copy_with "self-$1" "$tree_copy/bin/lib/self.js" "$2" "$3"
  cp -- "$copy" "$tree_copy/bin/lib/self.js"
  control_bin="$tree_copy/bin/vgshell"
}
self_control everycheckout 'if (checkout) return ["checkout"' 'if (true) return ["checkout"'
INST_BIN="$control_bin" inst "the every-tree-a-checkout mutant calls the Nix tree a checkout" "$cfg" "$rt_empty" 0 "$any_out" "$any_out" self status --json
check "so the Nix row would fail on it" json_is "$tmp/out" 'd["method"] == "checkout"'
self_control testrun '!process.env.VGS_TEST_RUN || ' ''
INST_TEST_RUN="" INST_BIN="$control_bin" inst "the marker-blind mutant takes a loopback API outside a test run" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" nix null "$version_text" "$release" true null)" "" self status --json

# The checksum control needs a curl install: the release fixture's sums are
# made wrong and a curl tree whose self.js skips the comparison installs it.
self_control checksum 'if (got !== want) refuse(' 'if (false) refuse('
mut_data="$tmp/data-mut"; mkdir -p "$mut_data/vgshell"
cp -R -- "$(dirname -- "$(dirname -- "$control_bin")")" "$mut_data/vgshell/$version_text"
ln -s -- "$version_text" "$mut_data/vgshell/current"
printf '%s  %s\n' "$(printf '0%.0s' $(seq 1 64))" "$archive" >"$www/dl/SHA256SUMS"
inst_env=(VGS_RELEASE_API="$api" XDG_DATA_HOME="$mut_data")
INST_BIN="$mut_data/vgshell/current/bin/vgshell" inst "the checksum-blind mutant installs an archive its sums do not list" "$cfg" "$rt_empty" 0 "shell=not-running" "" self update
inst_env=("${saved_env[@]}")
printf '%s  %s\n' "$good_sum" "$archive" >"$www/dl/SHA256SUMS"

# The running-tree control: a curl tree whose self.js keeps no running
# shell's tree removes it.
self_control shellblind 'if (running !== null && path.dirname(running) === real(data)) kept.push(path.basename(running));' ''
blind_data="$tmp/data-shellblind"; running_layout "$blind_data"
cp -- "$(dirname -- "$(dirname -- "$control_bin")")/bin/lib/self.js" "$blind_data/vgshell/$version_text/bin/lib/self.js"
"$stubs/qs" -p "$blind_data/vgshell/0.0.8/shell" &
blind_shell=$!
trap 'kill "$fake_shell" "$blind_shell" "$www_pid" 2>/dev/null || true; rm -rf -- "${tmp:?}"' EXIT
printf '%s\n' "$blind_shell" >"$rt_running/vgshell.lock"
inst_env=(VGS_RELEASE_API="$api" XDG_DATA_HOME="$blind_data")
INST_BIN="$blind_data/vgshell/current/bin/vgshell" inst "the shell-blind mutant updates beside the running shell" "$cfg" "$rt_running" 78 "$any_out" "$any_out" self update
check "and removes the running shell's tree, which the row above keeps" test ! -e "$blind_data/vgshell/0.0.8"
kill "$blind_shell" 2>/dev/null || true
inst_env=("${saved_env[@]}")

# The migration control: a curl tree whose vgshell runs no migration after
# the update, with a state directory of its own, installs the release and
# runs none of its migrations, which the curl row above requires.
nomig_data="$tmp/data-nomigrate"; mkdir -p "$nomig_data/vgshell"
install_tree "$seed" "$nomig_data/vgshell/$version_text"
ln -s -- "$version_text" "$nomig_data/vgshell/current"
copy_with nomigrate "$nomig_data/vgshell/$version_text/bin/vgshell" '      self_migrate "$data_home/vgshell/current/bin/vgshell-migrate"' ''
cp -- "$copy" "$nomig_data/vgshell/$version_text/bin/vgshell"
inst_env=(VGS_RELEASE_API="$api" XDG_DATA_HOME="$nomig_data" XDG_STATE_HOME="$tmp/state-nomigrate")
INST_BIN="$nomig_data/vgshell/current/bin/vgshell" inst "the migration-blind mutant updates the curl install" "$cfg" "$rt_empty" 0 "shell=not-running" "" self update
check "and runs none of the release's migrations, which the curl row requires" test ! -e "$tmp/state-nomigrate/vgshell/migrations/1000000001-release-probe.sh"
inst_env=("${saved_env[@]}")

rows_done test-vgshell-self
