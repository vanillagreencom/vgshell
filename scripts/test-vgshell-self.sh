#!/usr/bin/env bash
# Controls for `vgshell self status [--json]` and `vgshell self update`: one tree
# per install method, each a copy under $tmp, never this repository's own
# checkout. A checkout clones a local bare repository; a curl install is a
# versioned directory under a fixture XDG_DATA_HOME with a `current` link; a
# package tree is owned by a stub pacman under a fixture Arch os-release, or
# a stub rpm under a Fedora one, bound over /etc/os-release under
# `unshare -rm`; a Nix tree lies under a
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
for tool in bash sh readlink dirname mkdir flock awk git mktemp mv rm head cat setsid timeout env tar gzip python3 cp ln sed setpriv date grep script; do
  tool_bin="$(command -v "$tool")" || { echo "test-vgshell-self: status=not-measured missing=$tool"; exit 77; }
  ln -s -- "$tool_bin" "$tools/$tool"
done
ln -s -- "$node_bin" "$tools/node"
INST_PATH="$stubs:$tools"; export INST_PATH
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
# assets, served from $www on 127.0.0.1. A file with a `<file>.stall`
# marker beside it answers 200 and its headers, then stalls its body for
# 20 seconds, past self.js's 10-second API timeout. The server writes its
# port once it listens; the EXIT trap stops it.
www="$tmp/www"; mkdir -p "$www/dl" "$www/repos/vanillagreencom/vgshell/releases"
ready="$tmp/www-port"
python3 -c '
import functools, http.server, os, sys, time
class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_GET(self):
        if not os.path.exists(self.translate_path(self.path) + ".stall"):
            return super().do_GET()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"{")
        self.wfile.flush()
        time.sleep(20)
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=sys.argv[2]))
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
tar -C "$tmp/rel" -czf "$www/dl/$archive" "vgshell-$release"
good_sum="$(sha256sum "$www/dl/$archive" | cut -d' ' -f1)"
printf '%s  %s\n' "$good_sum" "$archive" >"$www/dl/SHA256SUMS"
printf '{"tag_name":"v%s","assets":[{"name":"%s","browser_download_url":"%s/dl/%s"},{"name":"SHA256SUMS","browser_download_url":"%s/dl/SHA256SUMS"}]}\n' \
  "$release" "$archive" "$api" "$archive" "$api" >"$www/repos/vanillagreencom/vgshell/releases/latest"
inst_env=(VGS_RELEASE_API="$api" XDG_DATA_HOME="$data" NIX_STORE_DIR="$tmp/nix/store")

status_json() { # VERSION METHOD PACKAGE CURRENT LATEST BEHIND STEP REASON ERROR: null for an absent value
  python3 -c 'import json, sys
v = [None if a == "null" else a for a in sys.argv[1:]]
b = {"true": True, "false": False, None: None}[v[5]]
print(json.dumps({"version": v[0], "method": v[1], "package": v[2], "current": v[3], "latest": v[4], "behind": b, "step": v[6], "reason": v[7], "error": v[8]}, separators=(",", ":")))' "$@"
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
INST_BIN="$co/bin/vgshell" inst "a current checkout is not behind" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" checkout null "$here" "$here" false none null null)" "" self status --json
check "status runs no git hook" test ! -e "$marker"
# The upstream advances to a new commit.
printf 'next\n' >"$seed/update-probe"
g -C "$seed" add -A; g -C "$seed" commit -q -m two; g -C "$seed" push -q "$upstream" main; rm -f -- "$marker"
there="$(describe "$seed" HEAD)"
INST_BIN="$co/bin/vgshell" inst "a checkout behind its upstream names the upstream's describe form" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" checkout null "$here" "$there" true self null null)" "" self status --json
check "the behind status runs no git hook either" test ! -e "$marker"
INST_BIN="$co/bin/vgshell" inst "the text form is one line of fields" "$cfg" "$rt_empty" 0 "version=$version_text method=checkout current=$here latest=$there behind=true step=self" "" self status
check "status leaves HEAD where it was" test "$(g -C "$co" rev-parse --short HEAD)" == "${here##*.g}"

printf 'local\n' >"$co/LOCAL"
INST_BIN="$co/bin/vgshell" inst "update refuses a modified checkout" "$cfg" "$rt_empty" 1 "" "vgshell: refused: modified=$co" self update
rm -- "$co/LOCAL"
old="$(g -C "$co" rev-parse HEAD)" new="$(g -C "$upstream" rev-parse main)"
INST_BIN="$co/bin/vgshell" inst "update fast-forwards the checkout and names no running shell" "$cfg" "$rt_empty" 0 "shell=not-running" "" self update
check "update prints the commits it moved between" has_line "ok updated=vgshell from=${old:0:12} to=${new:0:12}"
check "the checkout is at its upstream" test "$(g -C "$co" rev-parse HEAD)" == "$new"
check "update runs no git hook" test ! -e "$marker"
INST_BIN="$co/bin/vgshell" inst "a current checkout is up to date" "$cfg" "$rt_empty" 0 "ok up-to-date=vgshell" "" self update
g -C "$co" remote set-url origin "$tmp/gone.git"
INST_BIN="$co/bin/vgshell" inst "an unreachable upstream is the report's error, exit 0" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" checkout null "$there" null null null null "fetch=vgshell")" "$any_out" self status --json
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
INST_BIN="$curl_bin" inst "a curl install compares VERSION with the newest release" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" curl null "$version_text" "$release" true self null null)" "" self status --json
saved_env=("${inst_env[@]}")
inst_env=(VGS_RELEASE_API="$api/elsewhere" XDG_DATA_HOME="$data")
INST_BIN="$curl_bin" inst "a repository with no release is the report's error" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" curl null "$version_text" null null null null "release=none repository=vanillagreencom/vgshell")" "" self status --json
inst_env=(VGS_RELEASE_API="http://example.invalid" XDG_DATA_HOME="$data")
INST_BIN="$curl_bin" inst "a release API other than loopback is refused" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" curl null "$version_text" null null null null 'release-api=refused value="http://example.invalid"')" "$any_out" self status --json
inst_env=("${saved_env[@]}")
INST_TEST_RUN="" INST_BIN="$curl_bin" inst "a loopback release API outside a test run is refused" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" curl null "$version_text" null null null null "release-api=refused value=\"$api\"")" "$any_out" self status --json

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
check "the current link names the new version" test "$(readlink -- "$data/vgshell/current")" == "$release"
check "the new tree is the release's" test "$(<"$data/vgshell/$release/VERSION")" == "$release"
check "the new tree's command runs" test -x "$data/vgshell/$release/bin/vgshell"
check "the tree that was current stays" test -d "$data/vgshell/$version_text"
check "every other version is removed" test ! -e "$data/vgshell/0.0.9"
check "no staging directory stays" test -z "$(find "$data/vgshell" -maxdepth 1 -name '.self-update-*')"
INST_BIN="$curl_bin" inst "the new tree is current" "$cfg" "$rt_empty" 0 "$(status_json "$release" curl null "$release" "$release" false none null null)" "" self status --json
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
INST_BIN="$running_data/vgshell/current/bin/vgshell" inst "an update beside a running shell restarts it, refused here below the floor" "$cfg" "$rt_running" 78 \
  "ok updated=vgshell from=$version_text to=$release path=$running_data/vgshell/$release" "vgshell: refused: preflight=quickshell have=unknown need=0.3.1" self update
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
bound_bin() { # TREE OUT: OUT runs TREE's vgshell under the Arch os-release fixture
  cat >"$2" <<EOF
#!$tools/sh
exec $unshare_bin -rm $tools/sh -c 'mount_bin=\$1 fixture=\$2; shift 2; "\$mount_bin" --bind "\$fixture" /etc/os-release && exec "\$@"' sh $mount_bin $tmp/os-release $1/bin/vgshell "\$@"
EOF
  chmod +x "$2"
}
bound_bin "$pkg_root" "$tmp/bound-vgshell"
g config --file "$tmp/home/.gitconfig" "url.$upstream.insteadOf" https://github.com/vanillagreencom/vgshell.git
main_commit="$(g -C "$upstream" rev-parse main)"
built_commit="${main_commit:0:7}"
built="$version_text.r7.g$built_commit"
inst_env+=(STUB_OWNED="$pkg_root/VERSION" STUB_PACKAGE=vgshell-git STUB_PKGVER="$built")
INST_BIN="$tmp/bound-vgshell" inst "a vgshell-git package built from main's commit is not behind" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" package vgshell-git "$built" "$main_commit" false none null null)" "" self status --json

# GitHub's compare of the package's commit with main's, served where the API
# answers it: the commits main holds past it and each file changed, a
# rename with its old path, read from the fixture upstream's own git.
compare_dir="$www/repos/vanillagreencom/vgshell/compare"; mkdir -p "$compare_dir"
compare_fixture() { # BASE HEAD
  python3 - "$compare_dir/$1...$2" "$(g -C "$upstream" rev-list "$1..$2")" "$(g -C "$upstream" diff --name-status -M "$1" "$2")" <<'PY'
import json, sys
commits = [{"sha": c} for c in sys.argv[2].split()]
files = []
for line in sys.argv[3].splitlines():
    parts = line.split("\t")
    entry = {"filename": parts[-1], "status": {"A": "added", "M": "modified", "D": "removed", "R": "renamed"}[parts[0][0]]}
    if parts[0][0] == "R":
        entry["previous_filename"] = parts[1]
    files.append(entry)
json.dump({"status": "ahead", "total_commits": len(commits), "commits": commits, "files": files}, open(sys.argv[1], "w"))
PY
}
# Main moves by a commit that changes only paths the package does not
# install.
mkdir -p "$seed/.agents" "$seed/docs"
printf 'notes\n' >"$seed/.agents/notes.md"; printf '{}\n' >"$seed/.kendex-lock.json"; printf 'doc\n' >"$seed/docs/guide.md"
g -C "$seed" add -A; g -C "$seed" commit -q -m three; g -C "$seed" push -q "$upstream" main
main_commit="$(g -C "$upstream" rev-parse main)"
compare_fixture "$built_commit" "$main_commit"
check "the uninstalled-only compare lists its three files" json_is "$compare_dir/$built_commit...$main_commit" 'sorted(f["filename"] for f in d["files"]) == [".agents/notes.md", ".kendex-lock.json", "docs/guide.md"]'
INST_BIN="$tmp/bound-vgshell" inst "a main that changed no installed path leaves vgshell-git up to date" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" package vgshell-git "$built" "$main_commit" false none null null)" "" self status --json
# The must-fail control: a package tree whose self.js judges by the hash
# compare it replaced reads that main behind.
hash_root="$tmp/pkghash/usr/share/vgshell"; mkdir -p "$(dirname -- "$hash_root")"; cp -R -- "$pkg_root" "$hash_root"
copy_with self-hash "$hash_root/bin/lib/self.js" 'if (pkg === "vgshell-git") return fact === "true";' 'if (pkg === "vgshell-git") return !latest.startsWith(GIT_PACKAGE_PATTERN.exec(current)[1]);'
cp -- "$copy" "$hash_root/bin/lib/self.js"
bound_bin "$hash_root" "$tmp/bound-hash"
inst_env+=(STUB_OWNED="$hash_root/VERSION")
INST_BIN="$tmp/bound-hash" inst "the hash-compare mutant answers the uninstalled-only main" "$cfg" "$rt_empty" 0 "$any_out" "" self status --json
check "and reads it behind, which the row above refuses" json_is "$tmp/out" 'd["behind"] is True'
inst_env+=(STUB_OWNED="$pkg_root/VERSION")
# Main moves by a commit that changes an installed path.
printf 'fixture\n' >"$seed/shell/Core/Probe.js"
g -C "$seed" add -A; g -C "$seed" commit -q -m four; g -C "$seed" push -q "$upstream" main
main_commit="$(g -C "$upstream" rev-parse main)"
compare_fixture "$built_commit" "$main_commit"
INST_BIN="$tmp/bound-vgshell" inst "a vgshell-git package without an AUR helper offers helper installation" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" package vgshell-git "$built" "$main_commit" true install-helper null null)" "" self status --json
INST_BIN="$tmp/bound-vgshell" inst "the text form names helper installation" "$cfg" "$rt_empty" 0 "version=$version_text method=package package=vgshell-git current=$built latest=$main_commit behind=true step=install-helper" "" self status
printf '#!/bin/sh\nexit 99\n' >"$stubs/paru"; chmod +x "$stubs/paru"
for helper in paru yay; do
  rm -f -- "${stubs:?}/paru" "${stubs:?}/yay"
  printf '#!/bin/sh\nexit 99\n' >"$stubs/$helper"; chmod +x "$stubs/$helper"
  INST_BIN="$tmp/bound-vgshell" inst "a vgshell-git package with $helper takes the rebuild" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" package vgshell-git "$built" "$main_commit" true rebuild null null)" "" self status --json
done
rm -f -- "${stubs:?}/yay"
printf '#!/bin/sh\nexit 99\n' >"$stubs/paru"; chmod +x "$stubs/paru"
# Answers whose files GitHub may have cut short, or that cannot prove the
# installed tree unchanged, read behind; an answer GitHub could not give
# is the report's error, exit 0. `stall` sends 200 and its headers, then
# stalls the body past the timeout.
compare_file="$compare_dir/$built_commit...$main_commit"
compare_url="$api/repos/vanillagreencom/vgshell/compare/$built_commit...$main_commit"
while IFS='|' read -r name body want; do
  rm -f -- "${compare_file:?}.stall"
  if [[ $body == absent ]]; then rm -f -- "${compare_file:?}"
  elif [[ $body == stall ]]; then : >"$compare_file.stall"
  else python3 -c 'import json, sys; json.dump(eval(sys.argv[2]), open(sys.argv[1], "w"))' "$compare_file" "$body"
  fi
  case "$want" in
    behind) want_json="$(status_json "$version_text" package vgshell-git "$built" "$main_commit" true rebuild null null)" ;;
    current) want_json="$(status_json "$version_text" package vgshell-git "$built" "$main_commit" false none null null)" ;;
    *) want_json="$(status_json "$version_text" package vgshell-git "$built" null null null null "$want url=$compare_url")" ;;
  esac
  INST_BIN="$tmp/bound-vgshell" inst "$name" "$cfg" "$rt_empty" 0 "$want_json" "" self status --json
done <<'ROWS'
a compare of uninstalled paths alone is up to date|{"status": "ahead", "total_commits": 1, "commits": [{}], "files": [{"filename": "docs/a.md"}]}|current
a rename out of an installed path is behind|{"status": "ahead", "total_commits": 1, "commits": [{}], "files": [{"filename": "docs/moved.json", "previous_filename": "config/moved.json"}]}|behind
a full file list is behind|{"status": "ahead", "total_commits": 1, "commits": [{}], "files": [{"filename": "docs/%d.md" % i} for i in range(300)]}|behind
a cut commit list is behind|{"status": "ahead", "total_commits": 2, "commits": [{}], "files": [{"filename": "docs/a.md"}]}|behind
a main that no longer holds the package's commit is behind|{"status": "diverged", "total_commits": 1, "commits": [{}], "files": [{"filename": "docs/a.md"}]}|behind
a compare without a file list is the report's error|{"status": "ahead", "total_commits": 1, "commits": [{}]}|compare=malformed
a compare GitHub does not know is the report's error|absent|compare=http status=404
a compare whose body stalls past the timeout is the report's timeout|stall|compare=timeout seconds=10
ROWS
# The stall row's control: a package tree whose self.js reads a failed body
# as empty text reads the same stall as malformed, so the stub's headers
# arrived and the timeout came from the body read.
stall_root="$tmp/pkgstall/usr/share/vgshell"; mkdir -p "$(dirname -- "$stall_root")"; cp -R -- "$pkg_root" "$stall_root"
copy_with self-stall "$stall_root/bin/lib/self.js" 'text = await response.text();' 'text = await response.text().catch(() => "");'
cp -- "$copy" "$stall_root/bin/lib/self.js"
bound_bin "$stall_root" "$tmp/bound-stall"
inst_env+=(STUB_OWNED="$stall_root/VERSION")
INST_BIN="$tmp/bound-stall" inst "the body-blind mutant answers the stalled compare" "$cfg" "$rt_empty" 0 "$any_out" "" self status --json
check "and names it malformed, which the row above refuses" json_is "$tmp/out" 'd["error"] == "compare=malformed url='"$compare_url"'"'
inst_env+=(STUB_OWNED="$pkg_root/VERSION")
rm -f -- "${compare_file:?}.stall" "${stubs:?}/paru"
# A stop during the ls-remote of main, as during a checkout's fetch.
INST_BIN="$tmp/bound-vgshell" stop_run TERM self status --json
check "TERM during main's ls-remote ends self status with exit 143" test "$stop_status" == 143
check "self status stopped during main's ls-remote prints no report" test ! -s "$tmp/out"
check "self status returns after the ls-remote TERM stopped has ended" test "$stop_ended/$stop_alive" == yes/no
INST_BIN="$tmp/bound-vgshell" inst "update refuses a package and names its manager" "$cfg" "$rt_empty" 1 "" "vgshell: refused: method=package package=vgshell-git manager=pacman" self update
inst_env+=(STUB_PACKAGE=vgshell STUB_PKGVER="$version_text")
INST_BIN="$tmp/bound-vgshell" inst "an AUR vgshell package without an AUR helper is behind and takes no step" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" package vgshell "$version_text" "$release" true none no-aur-helper null)" "" self status --json
# The must-fail control: a package tree whose self.js judges the reason by
# the package's name, not its manager, sends the same AUR package to the
# system's update.
name_root="$tmp/pkgname/usr/share/vgshell"; mkdir -p "$(dirname -- "$name_root")"; cp -R -- "$pkg_root" "$name_root"
copy_with self-name "$name_root/bin/lib/self.js" 'if (manager === AUR_PRIMARY && helper === null)' 'if (pkg === "vgshell-git" && helper === null)'
cp -- "$copy" "$name_root/bin/lib/self.js"
bound_bin "$name_root" "$tmp/bound-name"
inst_env+=(STUB_OWNED="$name_root/VERSION")
INST_BIN="$tmp/bound-name" inst "the name-judging mutant answers the helperless AUR vgshell" "$cfg" "$rt_empty" 0 "$any_out" "" self status --json
check "and names the package manager, which the row above refuses" json_is "$tmp/out" 'd["reason"] == "package-manager"'
inst_env+=(STUB_OWNED="$pkg_root/VERSION")
printf '#!/bin/sh\nexit 99\n' >"$stubs/paru"; chmod +x "$stubs/paru"
INST_BIN="$tmp/bound-vgshell" inst "an AUR vgshell package with an AUR helper updates with the system's packages" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" package vgshell "$version_text" "$release" true none package-manager null)" "" self status --json
rm -f -- "${stubs:?}/paru"
# A Fedora vgshell package: dnf's owner and version queries go to a stub rpm
# under a Fedora os-release, with no AUR helper anywhere.
cp -- "$tmp/os-release" "$tmp/os-release.arch"
printf 'NAME="Fedora Linux"\nID=fedora\n' >"$tmp/os-release"
printf '#!/bin/sh\nexit 99\n' >"$stubs/dnf5"; chmod +x "$stubs/dnf5"
cat >"$stubs/rpm" <<'EOF'
#!/bin/sh
[ "$1 $2 $4" = "-qf --queryformat $STUB_OWNED" ] && { echo "$STUB_PACKAGE"; exit 0; }
[ "$1 $2 $4 $5" = "-q --queryformat -- $STUB_PACKAGE" ] && { echo "$STUB_PKGVER"; exit 0; }
exit 99
EOF
chmod +x "$stubs/rpm"
INST_BIN="$tmp/bound-vgshell" inst "a Fedora vgshell package updates with the system's packages" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" package vgshell "$version_text" "$release" true none package-manager null)" "" self status --json
rm -f -- "${stubs:?}/dnf5" "${stubs:?}/rpm"
mv -f -- "$tmp/os-release.arch" "$tmp/os-release"
inst_env+=(STUB_PACKAGE=unrelated-package)
INST_BIN="$tmp/bound-vgshell" inst "a package that is not vgshell is the report's error" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" null null null null null null null "package=unrelated-package manager=pacman reason=not-vgs")" "" self status --json
inst_env+=(STUB_PACKAGE=)
INST_BIN="$tmp/bound-vgshell" inst "a tree no method claims is method=unknown" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" null null null null null null null "method=unknown path=$pkg_root")" "$any_out" self status --json
inst_env=("${saved_env[@]}")

# Nix: a tree under the fixture store.
nix_root="$tmp/nix/store/0000-vgshell-$version_text/share/vgshell"; install_tree "$seed" "$nix_root"
INST_BIN="$nix_root/bin/vgshell" inst "a Nix tree compares VERSION with the newest release" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" nix null "$version_text" "$release" true none nix null)" "" self status --json
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

# The installed paths self.js lists are the vgshell-git recipe's: its
# package() runs packaging/install-system.sh with PREFIX=/usr and
# SYSCONFDIR=/etc, here over this repository's tracked files. Each file the
# tree holds comes from its path under share/vgshell; each other file comes
# from the tracked file of its name and bytes, and one with none, the
# sudoers rule and the autostart entry, is the installer's own text. The
# recipe's own inputs count too. A floor of members the installer always
# copies catches a mapping that found nothing; the forbidden paths are the
# ones the issue names and the release package's recipe.
recipe="$tmp/recipe"
"${base_env[@]}" DESTDIR="$recipe" PREFIX=/usr SYSCONFDIR=/etc bash "$repo/packaging/install-system.sh" >/dev/null
recipe_listed() { # SELF_JS: exit 0 when its list matches the recipe
  "$node_bin" - "$1" "$recipe" "$repo" <<'JS'
const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const [selfJs, recipe, repo] = process.argv.slice(2);
const { installedPath } = require(selfJs);
const tracked = childProcess.execFileSync("git", ["-C", repo, "ls-files", "-z"], { encoding: "utf8" }).split("\0").filter(Boolean);
const tree = "usr/share/vgshell/";
const sources = [];
const unlisted = [];
(function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const file = path.join(dir, entry.name);
        const rel = path.relative(recipe, file);
        if (entry.isDirectory()) walk(file);
        else if (rel.startsWith(tree)) sources.push(rel.slice(tree.length));
        else if (entry.isFile()) {
            const bytes = fs.readFileSync(file);
            const from = tracked.filter(t => path.basename(t) === entry.name && fs.existsSync(path.join(repo, t)) && fs.readFileSync(path.join(repo, t)).equals(bytes));
            if (from.length > 0 && !from.some(installedPath)) unlisted.push(rel + " from " + from.join(","));
            sources.push(...from.filter(installedPath));
        }
    }
})(recipe);
for (const file of sources) if (!installedPath(file)) unlisted.push(file);
for (const file of ["packaging/install-system.sh", "packaging/arch/vgshell-git/PKGBUILD", "packaging/arch/vgshell-git/vgshell-git.install"])
    if (!installedPath(file)) unlisted.push(file);
const floor = ["bin/vgshell", "shell/Core/PluginLogic.js", "config/shell.json", "VERSION", "README.md", "LICENSE", "packaging/xdg-desktop-portal/hyprland-portals.conf"];
const missing = floor.filter(file => !sources.includes(file));
const forbidden = [".agents/skills/dev/SKILL.md", ".kendex-lock.json", "docs/architecture/distribution.md", "scripts/validate", "packaging/arch/vgshell/PKGBUILD"].filter(installedPath);
for (const [key, list] of [["unlisted", unlisted], ["floor-missing", missing], ["forbidden", forbidden]])
    for (const file of list) process.stderr.write("recipe: " + key + "=" + file + "\n");
process.exit(unlisted.length + missing.length + forbidden.length === 0 ? 0 : 1);
JS
}
check "self.js lists every path the vgshell-git recipe installs or builds from" recipe_listed "$repo/bin/lib/self.js"
# Its control: a self.js copy whose list lacks themes/.
recipe_copy="$tmp/recipe-control"; mkdir -p "$recipe_copy"
cp -- "$repo/bin/lib/judge-files.js" "$recipe_copy/"
copy_with self-recipe "$repo/bin/lib/self.js" '"config/", "themes/", ' '"config/", '
cp -- "$copy" "$recipe_copy/self.js"
recipe_refused() { ! recipe_listed "$1" 2>/dev/null; } # SELF_JS
check "a list without themes/ fails the recipe check" recipe_refused "$recipe_copy/self.js"

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
INST_TEST_RUN="" INST_BIN="$control_bin" inst "the marker-blind mutant takes a loopback API outside a test run" "$cfg" "$rt_empty" 0 "$(status_json "$version_text" nix null "$version_text" "$release" true none nix null)" "" self status --json

# Package-method stubs do not describe the engine in later curl controls.
rm -f -- "${stubs:?}/pacman"

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

# Exercise the previous updater against a release containing the migration.
# The real package table runs stand-in helpers under each private os-release.
migration_source="$tmp/migration-source/vgshell-$release"
source_tree "$migration_source" "$release"
cp -- "$repo/shell/Core/ConfigLogic.js" "$migration_source/shell/Core/"
cat >"$migration_source/bin/vgshell-tui" <<'PRESENTER'
#!/bin/bash
[[ $1 == present ]] || exit 61
shift
while [[ $1 != -- ]]; do shift; done
shift
exec "$@"
PRESENTER
# The root step has its own production suite. This stand-in proves that
# migration requests it before Fedora installs from that repository.
cat >"$migration_source/bin/vgshell-system" <<'SYSTEM'
#!/bin/bash
[[ $* == 'apply vgs-quickshell-repository' ]] || exit 62
printf '%s\n' "$*" >>"$ENGINE_STATE/system.log"
touch "$ENGINE_STATE/vgs-repository"
SYSTEM
chmod +x "$migration_source/bin/vgshell-tui" "$migration_source/bin/vgshell-system"
migration_helpers="$tmp/migration-helpers"; mkdir -p "$migration_helpers"
cat >"$migration_helpers/pacman" <<'PACMAN'
#!/bin/bash
[[ $1 == -Qoq ]] || exit 63
touch "$ENGINE_STATE/query"
cat "$ENGINE_STATE/owner"
PACMAN
cat >"$migration_helpers/rpm" <<'RPM'
#!/bin/bash
[[ $1 == -qf ]] || exit 63
touch "$ENGINE_STATE/query"
cat "$ENGINE_STATE/owner"
RPM
cat >"$migration_helpers/qs" <<'QS'
#!/bin/bash
[[ $* == --version ]] || exit 64
printf 'Quickshell 0.3.2 (revision stub, distributed by VGS %s (package: vgshell-quickshell))\n' "$(cat "$ENGINE_STATE/release")"
QS
cat >"$migration_helpers/paru" <<'PARU'
#!/bin/bash
[[ $* == '-S --needed -- vgshell-quickshell' ]] || exit 63
[[ -t 0 && -t 1 && -t 2 ]] || exit 65
printf '%s\n' "$*" >>"$ENGINE_STATE/install.log"
printf 'Replace stock engine? [y/N] '
read -r answer || exit 130
[[ $answer == y ]] || exit 0
[[ ! -f $ENGINE_STATE/fail ]] || exit 42
[[ ! -f $ENGINE_STATE/retain ]] || exit 0
printf 'vgshell-quickshell\n' >"$ENGINE_STATE/owner"
[[ -f $ENGINE_STATE/stale ]] || printf '2\n' >"$ENGINE_STATE/release"
PARU
cat >"$migration_helpers/dnf" <<'DNF'
#!/bin/bash
[[ $* == 'install vgshell-quickshell' && -f $ENGINE_STATE/vgs-repository ]] || exit 63
exec "$ENGINE_HELPERS/paru" -S --needed -- vgshell-quickshell
DNF
cat >"$migration_helpers/sudo" <<'SUDO'
#!/bin/bash
case "$1" in -k|-n) exit 0 ;; esac
exec "$@"
SUDO
chmod +x "$migration_helpers/"*
git -C "$repo" show 18c62b11fb19f074b5167cf857ffa2c34be50862:bin/lib/self.js >"$tmp/previous-self.js"
migration_pack() {
  tar -C "$tmp/migration-source" -czf "$www/dl/$archive" "vgshell-$release"
  printf '%s  %s\n' "$(sha256sum "$www/dl/$archive" | cut -d' ' -f1)" "$archive" >"$www/dl/SHA256SUMS"
}
migration_invoke() { # STATE DATA HELPERS ANSWER SELF_JS
  local command status=0
  printf -v command '%q ' "$unshare_bin" -rm "$BASH" -c 'mount --bind "$1" /etc/os-release && shift && exec "$@"' bash "$1/os-release" \
    "$unshare_bin" --user --map-user="$(id -u)" --map-group="$(id -g)" env -i PATH="$3:$tools" HOME="$tmp/home" XDG_CONFIG_HOME="$cfg" XDG_RUNTIME_DIR="$rt_empty" XDG_DATA_HOME="$2" \
    TMPDIR="$tmp" VGS_TEST_RUN=1 VGS_RELEASE_API="$api" ENGINE_STATE="$1" ENGINE_HELPERS="$migration_helpers" \
    "$node_bin" "$5" install vanillagreencom/vgshell "$2" "$2/vgshell/$version_text" "$(cat "${5%/bin/lib/self.js}/VERSION")" -
  printf '%s\n' "$4" | SHELL="$BASH" script -qec "$command" /dev/null >"$tmp/migration.out" 2>&1 || status=$?
  if [[ $status != 0 ]]; then cat "$tmp/migration.out"; fi
  return "$status"
}
migration_run() { # NAME DISTRIBUTION IDENTITY ANSWER WANT_EXIT
  local name="$1" distro="$2" identity="$3" answer="$4" wanted="$5" status=0 binary
  local state="$tmp/engine-$name" mdata="$tmp/engine-data-$name" helperdir="$tmp/engine-path-$name"
  mkdir -p "$state" "$helperdir" "$mdata/vgshell"
  if [[ $name == *symlink* ]]; then
    mv "$mdata" "$mdata-real"
    ln -s "$mdata-real" "$mdata"
  fi
  printf '%s\n' "$identity" >"$state/owner"
  printf '1\n' >"$state/release"
  printf 'ID=%s\n' "$distro" >"$state/os-release"
  for binary in qs sudo; do ln -s "$migration_helpers/$binary" "$helperdir/$binary"; done
  if [[ $distro == arch ]]; then
    for binary in pacman paru; do ln -s "$migration_helpers/$binary" "$helperdir/$binary"; done
  else
    for binary in rpm dnf; do ln -s "$migration_helpers/$binary" "$helperdir/$binary"; done
  fi
  install_tree "$seed" "$mdata/vgshell/$version_text"
  cp -- "$tmp/previous-self.js" "$mdata/vgshell/$version_text/bin/lib/self.js"
  ln -s "$version_text" "$mdata/vgshell/current"
  [[ $name != *failure* ]] || touch "$state/fail"
  [[ $name != *retained* ]] || touch "$state/retain"
  [[ $name != *stale* ]] || touch "$state/stale"
  migration_invoke "$state" "$mdata" "$helperdir" "$answer" "$mdata/vgshell/$version_text/bin/lib/self.js" || status=$?
  check "migration $name has expected exit" test "$status" == "$wanted"
  if [[ $wanted == 0 ]]; then
    check "migration $name replaces the stock identity" test "$(cat "$state/owner")" == vgshell-quickshell
    check "migration $name publishes the release" test "$(readlink "$mdata/vgshell/current")" == "$release"
    if [[ $name == control-* ]]; then return; fi
    printf '%s\n' "$identity" >"$state/owner"
    migration_invoke "$state" "$mdata" "$helperdir" y "$mdata/vgshell/current/bin/lib/self.js" || status=$?
    check "migration $name repairs a stock engine at the same version" test "$(cat "$state/owner")" == vgshell-quickshell
    rm -f "${state:?}/install.log"
    migration_invoke "$state" "$mdata" "$helperdir" y "$mdata/vgshell/current/bin/lib/self.js" || status=$?
    check "migration $name remains successful at the same version" test "$status" == 0
    check "migration $name is idempotent at the same version" test ! -e "$state/install.log"
  else
    check "migration $name keeps current" test "$(readlink "$mdata/vgshell/current")" == "$version_text"
    check "migration $name removes the failed stage" test -z "$(find "$mdata/vgshell" -maxdepth 1 -name '.self-update-*')"
    if [[ $name == *failure* ]]; then
      rm "${state:?}/fail"
      migration_invoke "$state" "$mdata" "$helperdir" y "$mdata/vgshell/$version_text/bin/lib/self.js" || status=$?
      check "migration $name resumes after failure" test "$(cat "$state/owner")" == vgshell-quickshell
    fi
  fi
}
ln -s "$mount_bin" "$tools/mount"
for tool in touch tr sleep; do ln -s "$(command -v "$tool")" "$tools/$tool"; done
migration_pack
mkdir "$tmp/ordinary-engine-state"
"${base_env[@]}" PATH="$migration_helpers:$tools" ENGINE_STATE="$tmp/ordinary-engine-state" DESTDIR="$tmp/ordinary-package-stage" PREFIX=/vgshell "$migration_source/packaging/install-system.sh" >"$tmp/ordinary-stage.out"
check "ordinary package staging with curl prefix performs no package action" test -d "$tmp/ordinary-package-stage/vgshell/share/vgshell"
check "ordinary package staging never queries the host engine" test ! -e "$tmp/ordinary-engine-state/query"
for row in 'arch-stock arch quickshell' 'arch-versionless arch quickshell-git' 'arch-symlink arch quickshell' 'fedora-stock fedora quickshell' 'arch-old arch vgshell-quickshell' 'fedora-old fedora vgshell-quickshell'; do
  read -r name distro identity <<<"$row"
  migration_run "$name" "$distro" "$identity" y 0
done
migration_run arch-cancel arch quickshell n 1
migration_run fedora-failure fedora quickshell y 1
migration_run arch-retained arch quickshell y 1
migration_run arch-stale arch vgshell-quickshell y 1
migration_run fedora-stale fedora vgshell-quickshell y 1
# The same replacement assertions reject a release with its hook removed.
cp -- "$migration_source/packaging/install-system.sh" "$tmp/migration-installer"
python3 - "$migration_source/packaging/install-system.sh" <<'CONTROL'
from pathlib import Path
import sys
p = Path(sys.argv[1]); s = p.read_text()
needle = '  node "$source_root/bin/lib/self.js" migrate-curl-stage "$source_root" "$destdir" "$prefix"'
assert s.count(needle) == 1
p.write_text(s.replace(needle, '  :'))
CONTROL
migration_pack
for distro in arch fedora; do
  before="$failures"
  migration_run "control-$distro" "$distro" quickshell y 0
  if ((failures > before)); then failures="$before"; ok "control: $distro replacement rejects a missing migration"; else fail "control: $distro replacement accepted missing migration"; fi
done
mv -- "$tmp/migration-installer" "$migration_source/packaging/install-system.sh"

# Same-version repair runs against fresh stand-in installs. It never uses
# the owner machine's package database or a remote release endpoint.
repair_source="$tmp/repair-source"; source_tree "$repair_source" "$version_text"
rm -f -- "$stubs/pacman" "$stubs/rpm" "$stubs/dnf" "$stubs/dnf5" "$stubs/paru" "$stubs/yay"
repair_checkout="$tmp/repair-checkout"; cp -R -- "$repair_source" "$repair_checkout"
g init -q "$repair_checkout"; g -C "$repair_checkout" add -A; g -C "$repair_checkout" commit -qm repair
repair_persona=packaging/jarvis-home/.agents/skills/jarvis/persona.md
repair_original="$(cat "$repair_checkout/$repair_persona")"
rm -- "$repair_checkout/$repair_persona"
printf 'edited\n' >"$repair_checkout/config/shell.json"
inst_env=()
INST_BIN="$repair_checkout/bin/vgshell" on_terminal n self repair
check "declining checkout repair keeps edited files" test "$(cat "$repair_checkout/config/shell.json")" == edited
check "declining checkout repair keeps missing files absent" test ! -e "$repair_checkout/$repair_persona"
INST_BIN="$repair_checkout/bin/vgshell" on_terminal y self repair
check "checkout repair restores the same commit without an upstream" test "$term_status" == 0
check "checkout repair restores a missing Jarvis file" test "$(cat "$repair_checkout/$repair_persona")" == "$repair_original"

repair_data="$tmp/repair-data"; mkdir -p "$repair_data/vgshell"
install_tree "$repair_source" "$repair_data/vgshell/$version_text"
install_tree "$repair_source" "$repair_data/vgshell/0.0.8"
ln -s -- "$version_text" "$repair_data/vgshell/current"
repair_archive="vgshell-$version_text.tar.gz"
mkdir -p "$tmp/repair-release" "$www/repos/vanillagreencom/vgshell/releases/tags"
cp -R -- "$repair_source" "$tmp/repair-release/vgshell-$version_text"
tar -C "$tmp/repair-release" -czf "$www/dl/$repair_archive" "vgshell-$version_text"
repair_sum="$(sha256sum "$www/dl/$repair_archive" | cut -d' ' -f1)"
printf '%s  %s\n' "$repair_sum" "$repair_archive" >"$www/dl/repair-sums"
printf '{"tag_name":"v%s","assets":[{"name":"%s","browser_download_url":"%s/dl/%s"},{"name":"SHA256SUMS","browser_download_url":"%s/dl/repair-sums"}]}\n' \
  "$version_text" "$repair_archive" "$api" "$repair_archive" "$api" >"$www/repos/vanillagreencom/vgshell/releases/tags/v$version_text"
rm -- "$repair_data/vgshell/$version_text/$repair_persona"
inst_env=(VGS_RELEASE_API="$api" XDG_DATA_HOME="$repair_data")
repair_base_env=("${base_env[@]}")
base_env+=(VGS_RELEASE_API="$api" XDG_DATA_HOME="$repair_data")
wait "$fake_shell" 2>/dev/null || true
"$stubs/qs" -p "$repair_data/vgshell/0.0.8/shell" &
fake_shell=$!
printf '%s\n' "$fake_shell" >"$rt_running/vgshell.lock"
repair_empty_runtime="$rt_empty"; rt_empty="$rt_running"
INST_BIN="$repair_data/vgshell/current/bin/vgshell" on_terminal y self repair
rt_empty="$repair_empty_runtime"
if [[ $term_status != 78 ]]; then cat "$tmp/out" >&2; fi
check "curl repair reaches the existing restart refusal" test "$term_status" == 78
check "curl repair restores a missing Jarvis file" test "$(cat "$repair_data/vgshell/current/$repair_persona")" == "$repair_original"
check "curl repair retains the previous selected tree" test -d "$repair_data/vgshell/$version_text"
check "failed restart retains the distinct running tree" test -d "$repair_data/vgshell/0.0.8/shell"
check "curl repair publishes a new tree" test "$(readlink "$repair_data/vgshell/current")" != "$version_text"
base_env=("${repair_base_env[@]}")

repair_package="$tmp/repair-package"; cp -R -- "$repair_source" "$repair_package"
rm -- "$repair_package/$repair_persona"
cat >"$repair_package/bin/vgshell-pkg" <<'REPAIR_PKG'
const fs=require("node:fs"),path=require("node:path");
const root=path.resolve(__dirname,".."),args=process.argv.slice(2);
if(args[0]==="owner") console.log(JSON.stringify({manager:"pacman",package:"vgshell",version:"0.1.0"}));
else if(args[0]==="detect") console.log(JSON.stringify({overlays:fs.existsSync(path.join(root,"no-helper"))?[]:[{id:"aur",binary:"paru"}]}));
else if(args[0]==="ensure-helper") {
 fs.appendFileSync(path.join(root,"helper.json"),JSON.stringify(args)+"\n");
 if(fs.existsSync(path.join(root,"fail-helper"))) process.exit(8);
 fs.unlinkSync(path.join(root,"no-helper"));
}
else if(args.join(" ")==="run reinstall --manager aur vgshell") {
 if(fs.existsSync(path.join(root,"no-helper"))) process.exit(9);
 fs.copyFileSync(path.join(root,"baseline-persona"),path.join(root,"packaging/jarvis-home/.agents/skills/jarvis/persona.md"));
 fs.writeFileSync(path.join(root,"reinstall.json"),JSON.stringify(args));
} else process.exit(99);
REPAIR_PKG
cp -- "$repair_source/$repair_persona" "$repair_package/baseline-persona"
inst_env=()
INST_BIN="$repair_package/bin/vgshell" on_terminal y self repair
check "package repair runs the AUR owner's reinstall" test "$term_status" == 0
check "package reinstall restores missing Jarvis files" test "$(cat "$repair_package/$repair_persona")" == "$repair_original"
check "package repair calls the reinstall action" test -s "$repair_package/reinstall.json"

for helper_case in declined failed installed; do
  touch "$repair_package/no-helper"
  rm -f -- "$repair_package/helper.json" "$repair_package/reinstall.json" "$repair_package/fail-helper"
  case "$helper_case" in
    declined) answer=n; expected=1 ;;
    failed) answer=y; expected=8; touch "$repair_package/fail-helper" ;;
    installed) answer=y; expected=0 ;;
  esac
  INST_BIN="$repair_package/bin/vgshell" on_terminal "$answer" self repair
  check "package helper $helper_case returns its status" test "$term_status" == "$expected"
  if [[ $helper_case == declined ]]; then
    check "declined repair starts no helper setup" test ! -e "$repair_package/helper.json"
  else
    check "package helper $helper_case calls shared helper setup" test -s "$repair_package/helper.json"
  fi
  if [[ $helper_case == installed ]]; then
    check "helper installation precedes package reinstall" test -s "$repair_package/reinstall.json"
  else
    check "package helper $helper_case starts no reinstall" test ! -e "$repair_package/reinstall.json"
  fi
done

rows_done test-vgshell-self
