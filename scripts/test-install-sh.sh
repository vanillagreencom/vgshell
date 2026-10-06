#!/usr/bin/env bash
# Controls for install.sh, the curl installer. Every row runs the script
# under env -i with a fresh fixture HOME, a scratch TMPDIR and a PATH of
# stubs and the tools it calls, never the developer's own home or package
# manager. Releases come from a file:// release fixture, VGS_RELEASE_API
# under VGS_TEST_RUN: the GitHub API's release documents and their assets,
# built from this repository's bin/ and installer. --git clones a local
# bare repository through the fixture home's url.insteadOf. A distribution
# is a fixture os-release bound over /etc/os-release under `unshare -rm`,
# the row then mapped back to the caller's uid, since the script refuses
# root.
#
# The drift rows hold the script's floor and package tables to their
# sources, bin/vgshell's preflight_floor and config/requirements.json, read by
# node below, and its package-manager choice and install command to
# `vgshell pkg detect` and `vgshell pkg plan` under the same os-release.
#
# /usr/bin/vgshell is not planted: no user namespace can create a file there,
# so the system-package rows use a stub pacman database instead.
#
# The controls at the end run copies of install.sh with one rule removed
# each, and every row that judges that rule must turn red on its copy.
set -euo pipefail

# shellcheck source=scripts/vgshell-rows.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"

suite=test-install-sh
not_measured() { echo "$suite: status=not-measured missing=$1"; exit 77; }
unshare_bin="$(command -v unshare)" || not_measured unshare
"$unshare_bin" -rm true 2>/dev/null || not_measured user-namespaces
command -v gpg >/dev/null || not_measured gpg
command -v gpgconf >/dev/null || not_measured gpgconf
uid="$(id -u)" gid="$(id -g)"

installer="$repo/install.sh"

# The rows' PATH: floor stubs, then the tools install.sh, the release's
# installer and the namespace wrapper call. $tools_nogit lacks git, the tool
# the distribution rows leave missing.
stubs="$tmp/stubs"; tools="$tmp/tools"; tools_nogit="$tmp/tools-nogit"
mkdir -p "$stubs" "$tools" "$tools_nogit"
for tool in bash sh env readlink dirname mkdir rmdir mktemp mv rm ln cp cat head sed uname flock setpriv git python3 curl tar gzip sha256sum gpg unshare mount id setsid script; do
  tool_bin="$(command -v "$tool")" || not_measured "$tool"
  ln -s -- "$tool_bin" "$tools/$tool"
  [[ $tool == git ]] || ln -s -- "$tool_bin" "$tools_nogit/$tool"
done
ln -s -- "$node_bin" "$tools/node"
ln -s -- "$node_bin" "$tools_nogit/node"
stub() { # DIR NAME STDOUT [STATUS]
  printf '#!/bin/sh\nprintf "%%s\\n" "%s"\nexit %s\n' "$3" "${4:-0}" >"$1/$2"
  chmod +x "$1/$2"
}
stub "$stubs" qs "Quickshell 0.3.1 (revision 41651d7, distributed by fixture)"
stub "$stubs" Hyprland "Hyprland 0.56 built from branch fixture"
stub "$stubs" nmcli "nmcli tool, version 1.56.0"
stub "$stubs" qrencode "qrencode version 4.1.1"
stub "$stubs" xdg-terminal-exec ""
install_managers="$tmp/install-managers"; mkdir -p "$install_managers"
stub "$install_managers" pacman "" 1
stub "$install_managers" paru "" 1
run_path="$stubs:$install_managers:$tools"

# A direct run inherits the caller's XDG_CONFIG_HOME, where git writes its
# global file when the fixture home holds no .gitconfig. The suite points it
# at a planted git/config, and the last row holds that file unchanged.
caller_config="$tmp/caller-config"; mkdir -p "$caller_config/git"
printf '[user]\n\tname = caller\n' >"$caller_config/git/config"
cp -- "$caller_config/git/config" "$tmp/caller-git-config"
export XDG_CONFIG_HOME="$caller_config"

scratch="$tmp/scratch"; mkdir -p "$scratch"
gnupg_empty="$tmp/gnupg-empty"; mkdir -m 700 "$gnupg_empty"
default_os="$tmp/default-os"; printf 'ID=arch\n' >"$default_os"
install_log="$tmp/runtime-install.log"

# The independent package recipes supply the expected install groups.
# The presenter checks the command after -- and runs no terminal or auth.
install_expected="$tmp/install-expected.json"
node - "$repo" >"$install_expected" <<'JS'
const fs = require("fs"), path = require("path");
const root = process.argv[2];
const aur = new Set();
for (const plugin of fs.readdirSync(path.join(root, "shell/plugins"), { withFileTypes: true })) {
    if (!plugin.isDirectory()) continue;
    const manifest = JSON.parse(fs.readFileSync(path.join(root, "shell/plugins", plugin.name, "manifest.json"), "utf8"));
    for (const row of manifest.requirements || []) if (row.packages?.aur) aur.add(row.packages.aur);
}
const systemOnly = new Set(["xdg-desktop-portal-gnome"]);
const hard = [...fs.readFileSync(path.join(root, "packaging/arch/vgshell/.SRCINFO"), "utf8").matchAll(/^\tdepends = (\S+)$/gm)]
    .map(match => match[1].split(/[<>=]/)[0])
    .filter(name => !systemOnly.has(name));
const fedora = [...fs.readFileSync(path.join(root, "packaging/fedora/vgshell.spec"), "utf8").matchAll(/^Requires:\s+(\S+)/gm)]
    .map(match => match[1])
    .filter(name => !systemOnly.has(name));
if (hard.length < 6 || fedora.length < 6 || !hard.includes("tesseract-data-eng") || !hard.includes("agent-browser-bin") || !fedora.includes("qrencode")) throw Error("package group extractor is broken");
process.stdout.write(JSON.stringify({ pacman: hard.filter(name => !aur.has(name)), aur: hard.filter(name => aur.has(name)), dnf: fedora }));
JS
installer_source_tree() {
  local manifest plugin
  source_tree "$1" "$2"
  cp -- "$repo/config/requirements.json" "$1/config/"
  cp -- "$repo/shell/Core/PluginLogic.js" "$repo/shell/Core/Pads.js" "$repo/shell/Core/HyprlandLayer.js" "$1/shell/Core/"
  mkdir -p "$1/shell/Commons" "$1/shell/Ui/icons" "$1/shell/plugins"
  cp -- "$repo/shell/Commons/SettingValues.js" "$1/shell/Commons/"
  cp -- "$repo/shell/Ui/icons/Lucide.js" "$1/shell/Ui/icons/"
  for manifest in "$repo/shell/plugins"/*/manifest.json; do
    plugin="${manifest%/manifest.json}"; plugin="${plugin##*/}"
    mkdir -p "$1/shell/plugins/$plugin"
    cp -- "$manifest" "$1/shell/plugins/$plugin/"
  done
  cat >"$1/bin/vgshell-tui" <<'PRESENTER'
#!/bin/bash
set -e
case "$1" in
  launch|present)
    printf '%s\n' "$@" >>"$VGS_INSTALL_LOG"
    node - "$VGS_INSTALL_EXPECTED" "$0" "$@" <<'JS'
const fs = require("fs"), path = require("path");
const [file, presenter, ...args] = process.argv.slice(2);
const separator = args.indexOf("--");
const command = args.slice(separator + 1);
const manager = command[5];
const expected = JSON.parse(fs.readFileSync(file, "utf8"))[manager];
if (separator < 0 || command[0] !== path.join(path.dirname(presenter), "vgshell") || JSON.stringify(command.slice(1, 5)) !== JSON.stringify(["pkg", "run", "install", "--manager"]) || !Array.isArray(expected) || JSON.stringify(command.slice(6).sort()) !== JSON.stringify(expected.sort())) process.exit(2);
JS
    [[ $1 != present ]] || exit "${VGS_INSTALL_CODE:-0}"
    ;;
  wait) printf '{"state":"ended","code":%s}\n' "${VGS_INSTALL_CODE:-0}" ;;
  *) exit 2 ;;
esac
PRESENTER
  chmod +x "$1/bin/vgshell-tui"
}

# new_home NAME: sets h to a new, empty fixture home and d to its vgshell data
# directory.
homes=0
new_home() {
  homes=$((homes + 1))
  h="$tmp/homes/$homes-$1"
  d="$h/.local/share/vgshell"
  scratch="$tmp/scratch/$homes-$1"
  install_log="$tmp/runtime-install-$homes-$1.log"
  gnupg_empty="$tmp/gnupg-empty-$homes-$1"
  rt_empty="$tmp/rt-empty-$homes-$1"
  mkdir -p "$h" "$scratch" "$rt_empty"
  mkdir -m 700 "$gnupg_empty"
}

# run BIN ARGS...: install.sh BIN from $h under the rows' environment.
# Stdout lands in $tmp/out, stderr in $tmp/err, the exit status in
# $status. RUN_PATH, RUN_RT (XDG_RUNTIME_DIR) and RUN_GNUPG replace the
# defaults; RUN_WRAP holds a command the script runs under.
RUN_WRAP=()
run() {
  local bin="$1"
  local -a wrap=("${RUN_WRAP[@]}")
  shift
  if ((${#wrap[@]} == 0)); then
    wrap=(unshare -rm sh -c 'mount --bind "$1" /etc/os-release && u="$2" g="$3" && shift 3 && exec unshare --map-user="$u" --map-group="$g" "$@"' sh "$default_os" "$uid" "$gid")
  fi
  status=0
  local -a invocation=(env -i PATH="${RUN_PATH:-$run_path}" HOME="$h" TMPDIR="$scratch" VGS_TEST_RUN=1 VGS_RELEASE_API="file://$www" \
    XDG_RUNTIME_DIR="${RUN_RT:-$rt_empty}" GIT_CONFIG_NOSYSTEM=1 GNUPGHOME="${RUN_GNUPG:-$gnupg_empty}" \
    VGS_INSTALL_LOG="$install_log" VGS_INSTALL_EXPECTED="$install_expected" VGS_INSTALL_CODE="${RUN_INSTALL_CODE:-0}" \
    "${wrap[@]}" bash "$bin" "$@")
  if [[ ${RUN_TTY:-false} == true ]]; then
    local terminal_command
    printf -v terminal_command '%q ' "${invocation[@]}"
    script -qec "$terminal_command" /dev/null >"$tmp/out" 2>"$tmp/err" </dev/null || status=$?
  else
    setsid -w "${invocation[@]}" >"$tmp/out" 2>"$tmp/err" </dev/null || status=$?
  fi
}
first_err() { local line=""; [[ -s $tmp/err ]] && IFS= read -r line <"$tmp/err"; printf '%s' "$line"; }
out_has() { grep -qxF -- "$1" "$tmp/out"; }
err_has() { grep -qxF -- "$1" "$tmp/err"; }
# refused STATUS FIRST_ERR: the last run exited STATUS with FIRST_ERR
# first on stderr.
refused() { [[ $status == "$1" && $(first_err) == "$2" ]]; }
scratch_empty() { [[ -z $(find "$scratch" -mindepth 1 -print -quit) ]]; }
no_stage() { ! compgen -G "$d/.self-update-*" >/dev/null; }
# with_os FILE: the next run sees FILE as /etc/os-release, as the caller's
# uid and gid; the caller clears RUN_WRAP after it.
with_os() {
  RUN_WRAP=(unshare -rm sh -c 'mount --bind "$1" /etc/os-release && u="$2" g="$3" && shift 3 && exec unshare --map-user="$u" --map-group="$g" "$@"' sh "$1" "$uid" "$gid")
}

# The release fixture. Each release is a document under
# repos/vanillagreencom/vgshell/releases/tags/v<X.Y.Z> naming its assets under
# dl/v<X.Y.Z>/; releases/latest is v0.2.0's.
www="$tmp/www"; releases="$www/repos/vanillagreencom/vgshell/releases"; mkdir -p "$releases/tags"
release_doc() { # TAG ASSET...
  local tag="$1" name out=""
  shift
  for name in "$@"; do out+="${out:+,}{\"name\":\"$name\",\"browser_download_url\":\"file://$www/dl/$tag/$name\"}"; done
  printf '{"tag_name":"%s","assets":[%s]}\n' "$tag" "$out" >"$releases/tags/$tag"
}
# release VERSION [TOP_DIR]: the archive vgshell-VERSION.tar.gz, whose one top
# directory is TOP_DIR, default vgshell-VERSION, and its SHA256SUMS line.
release() {
  local v="$1" top="${2:-vgshell-$1}" dir="$www/dl/v$1"
  mkdir -p "$dir" "$tmp/rel/$v"
  installer_source_tree "$tmp/rel/$v/$top" "$v"
  tar -C "$tmp/rel/$v" -czf "$dir/vgshell-$v.tar.gz" "$top"
  (cd "$dir" && sha256sum "vgshell-$v.tar.gz" >SHA256SUMS)
  release_doc "v$v" "vgshell-$v.tar.gz" SHA256SUMS
}
release 0.1.0
release 0.2.0
cp -- "$releases/tags/v0.2.0" "$releases/latest"
# v0.3.0's archive differs from its SHA256SUMS line, and v0.4.0's
# SHA256SUMS lists another file.
release 0.3.0
printf 'tampered\n' >>"$www/dl/v0.3.0/vgshell-0.3.0.tar.gz"
release 0.4.0
printf '%064d  vgshell-9.9.9.tar.gz\n' 0 >"$www/dl/v0.4.0/SHA256SUMS"
# v0.7.0 unpacks to a top directory of another name; v0.8.0's tag is no
# version.
release 0.7.0 vgs-main
release 0.8.0
sed -i 's/"v0.8.0"/"v0.8"/' "$releases/tags/v0.8.0"

# Signed releases: v0.5.0's SHA256SUMS signed by the release key, v0.6.0's
# by another key the keyring also holds. $signing is install.sh with the
# fixture key's fingerprint in place of the published one, and $no_key is
# install.sh with none.
keys="$tmp/gnupg"; mkdir -m 700 "$keys"
trap 'gpgconf --homedir "$keys" --kill gpg-agent >/dev/null 2>&1 || true; rm -rf -- "${tmp:?}"' EXIT
gen_key() { # NAME: prints the new key's fingerprint
  GNUPGHOME="$keys" gpg --batch --quiet --pinentry-mode loopback --passphrase '' --quick-gen-key "$1" ed25519 sign never >/dev/null 2>&1
  GNUPGHOME="$keys" gpg --batch --with-colons --list-keys -- "$1" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }'
}
release_fpr="$(gen_key "VGS release fixture")"
other_fpr="$(gen_key "Another key")"
[[ $release_fpr =~ ^[0-9A-F]{40}$ && $other_fpr =~ ^[0-9A-F]{40}$ ]] || { echo "$suite: gpg=keygen-failed" >&2; exit 1; }
signed_release() { # VERSION FINGERPRINT
  release "$1"
  GNUPGHOME="$keys" gpg --batch --quiet --local-user "$2" --armor --detach-sign --output "$www/dl/v$1/SHA256SUMS.asc" "$www/dl/v$1/SHA256SUMS"
  release_doc "v$1" "vgshell-$1.tar.gz" SHA256SUMS SHA256SUMS.asc
}
signed_release 0.5.0 "$release_fpr"
signed_release 0.6.0 "$other_fpr"

published='release_key="8BC162233D519169B9574148CC6862AD90B7D7EA"'
copy_with signing "$installer" "$published" "release_key=\"$release_fpr\""
signing="$copy"
copy_with no-key "$installer" "$published" 'release_key=""'
no_key="$copy"
release_keys="$tmp/release-keys.asc"
GNUPGHOME="$keys" gpg --batch --quiet --armor --export "$release_fpr" "$other_fpr" >"$release_keys"
release_keyring() {
  RUN_GNUPG="$tmp/gnupg-row-$homes"
  mkdir -m 700 "$RUN_GNUPG"
  GNUPGHOME="$RUN_GNUPG" gpg --batch --quiet --import "$release_keys" >/dev/null 2>&1
}

# The rows each judge one rule, on the install.sh BIN names, so a control
# can run them again on a copy with that rule removed.

mismatch_row() { # BIN: a checksum mismatch refuses and leaves nothing
  new_home mismatch
  run "$1" --version 0.3.0
  [[ $status == 1 && $(first_err) == "install.sh: refused: checksum=mismatch name=vgshell-0.3.0.tar.gz "* ]] &&
    [[ ! -e $h/.local ]] && scratch_empty
}
unlisted_row() { # BIN: an archive SHA256SUMS does not list refuses
  new_home unlisted
  run "$1" --version 0.4.0
  refused 1 "install.sh: refused: checksum=unlisted name=vgshell-0.4.0.tar.gz count=0" && [[ ! -e $h/.local ]]
}
tag_row() { # BIN
  new_home tag
  run "$1" --version 0.8.0
  refused 1 "install.sh: refused: tag=v0.8 reason=not-a-version"
}
layout_row() { # BIN: an archive with another top directory refuses under the lock and changes nothing
  new_home layout
  run "$1" --version 0.1.0
  run "$1" --version 0.7.0
  refused 1 "install.sh: refused: archive=layout name=vgshell-0.7.0.tar.gz top=vgs-main" &&
    [[ $(readlink -- "$d/current") == 0.1.0 && ! -e $d/0.7.0 ]] && no_stage
}
busy_row() { # BIN
  new_home busy
  mkdir -p "$d"
  exec 7>>"$d/.self.lock"
  flock 7
  run "$1"
  exec 7>&-
  refused 75 "install.sh: refused: self=busy path=$d/.self.lock" && [[ ! -e $d/0.2.0 && ! -e $d/current ]]
}
signature_other_row() { # BIN: a signature by another key in the keyring refuses and leaves nothing
  new_home sig-other
  release_keyring
  run "$1" --version 0.6.0
  unset RUN_GNUPG
  refused 1 "install.sh: refused: signature=bad name=SHA256SUMS key=$release_fpr" && [[ ! -e $h/.local ]]
}
root_row() { # BIN
  new_home root
  RUN_WRAP=(unshare -r)
  run "$1"
  RUN_WRAP=()
  refused 1 "install.sh: refused: user=root" && [[ ! -e $h/.local ]]
}
darwin="$tmp/darwin"; mkdir -p "$darwin"; stub "$darwin" uname Darwin
os_row() { # BIN
  new_home os
  RUN_PATH="$darwin:$run_path" run "$1"
  refused 1 "install.sh: refused: os=Darwin" && [[ ! -e $h/.local ]]
}
vgs_db="$tmp/vgs-db"; mkdir -p "$vgs_db"
cat >"$vgs_db/pacman" <<'SH'
#!/bin/sh
[ "$1" = -Q ] && [ "$3" = vgshell-git ] && { echo "vgshell-git 0.1.0.r1.gabc1234-1"; exit 0; }
exit 1
SH
chmod +x "$vgs_db/pacman"
system_row() { # BIN: vgshell-git in the pacman database refuses
  new_home system
  RUN_PATH="$vgs_db:$run_path" run "$1"
  refused 1 "install.sh: refused: system=package manager=pacman package=vgshell-git" && [[ ! -e $h/.local ]]
}
foreign_row() { # BIN: a ~/.local/bin/vgshell install.sh did not make refuses and stays
  new_home foreign
  mkdir -p "$h/.local/bin"
  ln -s /opt/elsewhere/vgshell "$h/.local/bin/vgshell"
  run "$1"
  refused 1 "install.sh: refused: link=foreign path=$h/.local/bin/vgshell" &&
    [[ $(readlink -- "$h/.local/bin/vgshell") == /opt/elsewhere/vgshell && ! -e $d ]]
}

# The --git fixture: a bare repository main is cloned from, through the
# fixture home's url.insteadOf.
bare="$tmp/vgs.git"; seed="$tmp/seed"
installer_source_tree "$seed" 0.2.0
g init -q -b main "$seed"; g -C "$seed" add -A; g -C "$seed" commit -q -m seed
g init -q --bare "$bare"; g -C "$seed" push -q "$bare" main
# git_home NAME: a new home with release v0.1.0 and a --git clone installed.
git_home() {
  new_home "$1"
  git config --file "$h/.gitconfig" url."file://$bare".insteadOf https://github.com/vanillagreencom/vgshell.git
  run "$installer" --version 0.1.0
  [[ $status == 0 ]] || { echo "$suite: fixture=release status=$status" >&2; cat "$tmp/err" >&2; exit 1; }
  run "$installer" --git
  [[ $status == 0 ]] || { echo "$suite: fixture=git status=$status" >&2; cat "$tmp/err" >&2; exit 1; }
}
modified_row() { # BIN: --uninstall refuses a clone with changes
  git_home modified
  printf 'change\n' >>"$d/git/VERSION"
  run "$1" --uninstall
  refused 1 "install.sh: refused: modified=$d/git" && [[ -d $d/git && -d $d/0.1.0 && -L $h/.local/bin/vgshell ]]
}
unpublished_row() { # BIN: --uninstall refuses a clone with a commit on HEAD no remote branch has
  git_home unpublished
  g -C "$d/git" commit -q --allow-empty -m local
  run "$1" --uninstall
  refused 1 "install.sh: refused: unpublished=1 path=$d/git" && [[ -d $d/git ]]
}
branch_row() { # BIN: --uninstall refuses a clone whose other local branch holds such a commit
  git_home branch
  g -C "$d/git" switch -q -c topic
  g -C "$d/git" commit -q --allow-empty -m local
  g -C "$d/git" switch -q main
  run "$1" --uninstall
  refused 1 "install.sh: refused: unpublished=1 path=$d/git" && [[ -d $d/git ]]
}
stash_row() { # BIN: --uninstall refuses a clone holding a stash
  git_home stash
  printf 'change\n' >>"$d/git/VERSION"
  g -C "$d/git" stash -q
  run "$1" --uninstall
  refused 1 "install.sh: refused: stash=present path=$d/git" && [[ -d $d/git ]]
}
running_row() { # BIN: --uninstall refuses while the running shell was started from a tree it removes
  local pid ok=0 rt_shell="$tmp/rt-shell"
  mkdir -p "$rt_shell"
  git_home running
  # A stand-in for the running shell: one process whose command line names
  # the tree as `qs -p <tree>/shell` does, ended once the row has run.
  python3 -c 'import time; time.sleep(30)' -p "$d/0.1.0/shell" </dev/null >/dev/null 2>&1 &
  pid=$!
  printf '%s\n' "$pid" >"$rt_shell/vgshell.lock"
  RUN_RT="$rt_shell" run "$1" --uninstall --force
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  refused 1 "install.sh: refused: shell=running pid=$pid path=$d/0.1.0" && [[ -d $d/0.1.0 ]] || ok=1
  return "$ok"
}
keep_foreign_row() { # BIN: --uninstall removes the install and keeps a foreign link
  new_home keep-foreign
  run "$installer"
  ln -sfn /opt/elsewhere/vgshell "$h/.local/bin/vgshell"
  run "$1" --uninstall
  [[ $status == 0 && ! -e $d/current && ! -e $d/0.2.0 && $(readlink -- "$h/.local/bin/vgshell") == /opt/elsewhere/vgshell ]] &&
    out_has "kept=$h/.local/bin/vgshell reason=foreign"
}

latest_row() {
  new_home latest
  run "$installer"
  check "the newest release installs" test "$status" = 0
  check "it names the release it installed" out_has "ok installed=vgshell version=0.2.0 path=$d/0.2.0"
  check "a release with no signature says so" out_has "signature=unchecked reason=no-signature"
  check "the version directory holds the release's runtime tree" test -f "$d/0.2.0/bin/vgshell" -a -f "$d/0.2.0/VERSION" -a ! -e "$d/0.2.0/share"
  check "current is a relative link to the version" test -L "$d/current" -a "$(readlink -- "$d/current")" = 0.2.0
  check "the command links to current's vgshell" test -L "$h/.local/bin/vgshell" -a "$(readlink -- "$h/.local/bin/vgshell")" = "$d/current/bin/vgshell"
  check "it prints the Hyprland autostart line" out_has "  hl.on(\"hyprland.start\", function () hl.exec_cmd(\"$h/.local/bin/vgshell run\") end)"
  check "it names a command directory missing from PATH" out_has "path=missing dir=$h/.local/bin: add it to PATH to run vgshell by name"
  check "it leaves no staging directory" no_stage
  check "it leaves nothing in TMPDIR" scratch_empty
  check "the linked vgshell runs the installed tree" test "$("${base_env[@]}" HOME="$h" XDG_RUNTIME_DIR="$rt_empty" "$h/.local/bin/vgshell" --version)" = "vgshell 0.2.0"
  "${base_env[@]}" HOME="$h" XDG_CONFIG_HOME="$h/.config" XDG_RUNTIME_DIR="$rt_empty" VGS_RELEASE_API=http://127.0.0.1:9 "$h/.local/bin/vgshell" self status --json >"$tmp/status.json" 2>/dev/null
  check "vgshell self status judges the layout a curl install" json_is "$tmp/status.json" 'd["method"] == "curl" and d["version"] == "0.2.0" and d["current"] == "0.2.0"'
}

packages_row() { # BIN: required packages use the existing floating presenter
  new_home runtime-packages
  : >"$install_log"
  run "$1" --version 0.1.0
  [[ $status == 0 ]] || return 1
  for arg in launch --record core/requirements-install --manager pacman aur tesseract-data-eng agent-browser-bin wlrctl vsys; do
    grep -qxF -- "$arg" "$install_log" || return 1
  done
  ! grep -qxE 'ddcutil|nvidia-utils|timeshift|cronie|greetd|tmux' "$install_log"
}
# A missing launcher refuses before fetch. The real presenter also refuses
# before setsid; its isolated PATH has no launcher or live-session program.
missing_launcher_fixture() {
  missing_launcher="$tmp/missing-launcher"
  launcher_fetches="$tmp/launcher-fetches"
  launcher_starts="$tmp/launcher-starts"
  mkdir -p "$missing_launcher"
  for tool in "$stubs"/*; do [[ ${tool##*/} == xdg-terminal-exec ]] || cp -- "$tool" "$missing_launcher/"; done
  cat >"$missing_launcher/curl" <<SH
#!/bin/sh
printf 'fetch\n' >>"$launcher_fetches"
exec "$tools/curl" "\$@"
SH
  cat >"$missing_launcher/setsid" <<SH
#!/bin/sh
printf 'launch\n' >>"$launcher_starts"
exit 0
SH
  chmod +x "$missing_launcher/curl" "$missing_launcher/setsid"
  : >"$launcher_fetches"; : >"$launcher_starts"
}
launcher_row() { # BIN: prerequisite and real presenter both stop before launch
  local presenter_status=0
  new_home missing-launcher
  missing_launcher_fixture
  : >"$install_log"
  RUN_PATH="$missing_launcher:$install_managers:$tools" run "$1" --version 0.1.0
  refused 78 "install.sh: refused: floor=xdg-terminal-exec have=none need=present" &&
    err_has "Install them as root: pacman -S --needed -- xdg-terminal-exec" &&
    [[ ! -e $h/.local && ! -s $launcher_fetches && ! -s $install_log ]] && scratch_empty || return 1
  env -i PATH="$missing_launcher:$tools" HOME="$h" XDG_RUNTIME_DIR="$rt_empty" \
    "$repo/bin/vgshell-tui" launch --title "Prerequisite fixture" -- "$tools/sh" -c ':' \
    >"$tmp/presenter-out" 2>"$tmp/presenter-err" </dev/null || presenter_status=$?
  [[ $presenter_status == 69 && ! -s $launcher_starts ]] &&
    [[ $(sed -n '1p' "$tmp/presenter-err") == "vgshell-tui: refused: terminal=missing" ]]
}

# Real reports read a PATH made only from fixture providers and bootstrap
# tools. The available required set has no optional or unmapped providers.
nix_present="$tmp/nix-present"; nix_missing="$tmp/nix-missing"; nix_manager="$tmp/nix-manager"
mkdir -p "$nix_present" "$nix_missing" "$nix_manager"
stub "$nix_manager" nix "" 1
nix_os="$tmp/nix-os"; printf 'ID=nixos\n' >"$nix_os"
for tool in "$stubs"/*; do cp -- "$tool" "$nix_present/"; done
python3 - "$repo" >"$tmp/nix-commands" <<'PYFIXTURE'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1])
rows=json.loads((root/'config/requirements.json').read_text())
for manifest in (root/'shell/plugins').glob('*/manifest.json'):
    rows.extend(json.loads(manifest.read_text()).get('requirements', []))
commands=sorted({row['command'] for row in rows if not row.get('optional', False) and 'nix' in row.get('packages', {})})
assert len(commands)>6 and 'qrencode' in commands and 'bwrap' in commands
print('\n'.join(commands))
PYFIXTURE
while IFS= read -r command; do
  [[ -e $nix_present/$command || -e $tools/$command ]] || stub "$nix_present" "$command" ""
done <"$tmp/nix-commands"
for tool in "$nix_present"/*; do [[ ${tool##*/} == qrencode ]] || cp -- "$tool" "$nix_missing/"; done
nix_present_row() { # BIN: installed available requirements allow release, current and Git
  local installed_head expected_head
  new_home nix-present
  : >"$install_log"
  with_os "$nix_os"
  RUN_PATH="$nix_present:$nix_manager:$tools" run "$1" --version 0.1.0
  [[ $status == 0 && $(readlink -- "$d/current") == 0.1.0 ]] || { RUN_WRAP=(); return 1; }
  RUN_PATH="$nix_present:$nix_manager:$tools" run "$1" --version 0.1.0
  [[ $status == 0 ]] && out_has "ok up-to-date=vgshell version=0.1.0 path=$d/0.1.0" || { RUN_WRAP=(); return 1; }
  git config --file "$h/.gitconfig" url."file://$bare".insteadOf https://github.com/vanillagreencom/vgshell.git || { RUN_WRAP=(); return 1; }
  RUN_PATH="$nix_present:$nix_manager:$tools" run "$1" --git
  RUN_WRAP=()
  [[ $status == 0 && -f $d/git/bin/vgshell && ! -s $install_log ]] || return 1
  installed_head="$(g -C "$d/git" rev-parse HEAD)" || return 1
  expected_head="$(g -C "$bare" rev-parse main)" || return 1
  [[ $installed_head == "$expected_head" ]] && scratch_empty
}
nix_missing_row() { # BIN: only the absent available package blocks publication
  new_home nix-missing
  : >"$install_log"
  with_os "$nix_os"
  RUN_PATH="$nix_missing:$nix_manager:$tools" run "$1" --version 0.1.0
  RUN_WRAP=()
  refused 78 "install.sh: refused: requirements=configuration manager=nix" &&
    err_has "Add these required packages to the Nix configuration: qrencode" &&
    [[ ! -e $d/current && ! -e $d/0.1.0 && ! -s $install_log ]] && no_stage && scratch_empty
}

terminal_row() { # BIN: no launcher is needed in the caller's terminal
  new_home terminal-install
  missing_launcher_fixture
  : >"$install_log"
  RUN_PATH="$missing_launcher:$install_managers:$tools" RUN_TTY=true run "$1" --version 0.1.0
  [[ $status == 0 && $(readlink -- "$d/current") == 0.1.0 ]] || return 1
  grep -qxF present "$install_log" && ! grep -qxF launch "$install_log" || return 1
  for arg in --presentation plain xdg-terminal-exec --manager pacman aur; do
    grep -qxF -- "$arg" "$install_log" || return 1
  done
  RUN_TTY=true RUN_INSTALL_CODE=42 run "$1" --version 0.2.0
  [[ $status == 1 && $(readlink -- "$d/current") == 0.1.0 && ! -e $d/0.2.0 ]] &&
    grep -q 'requirements=install-failed manager=pacman code=42' "$tmp/out" && no_stage
}
runtime_failure_row() { # BIN: a failed recorded install leaves current unchanged
  new_home runtime-failure
  run "$installer" --version 0.1.0
  [[ $status == 0 ]] || return 1
  RUN_INSTALL_CODE=42 run "$1" --version 0.2.0
  refused 1 "install.sh: refused: requirements=install-failed manager=pacman code=42" &&
    [[ $(readlink -- "$d/current") == 0.1.0 && ! -e $d/0.2.0 ]] && no_stage
}
pinned_row() {
  new_home pinned
  run "$installer" --version v0.1.0
  check "--version installs the release it names" test "$status" = 0 -a "$(readlink -- "$d/current")" = 0.1.0
  run "$installer" --version 0.2.0
  check "a reinstall of a newer release succeeds" test "$status" = 0
  check "the reinstall swaps current to the new version" test -L "$d/current" -a "$(readlink -- "$d/current")" = 0.2.0
  check "the reinstall keeps the earlier version's tree" test -f "$d/0.1.0/VERSION"
  run "$installer"
  check "the installed release again is up to date" out_has "ok up-to-date=vgshell version=0.2.0 path=$d/0.2.0"
  check "an up-to-date run leaves current alone" test "$(readlink -- "$d/current")" = 0.2.0
}
stage_row() {
  new_home stage
  mkdir -p "$d/.self-update-dead"
  run "$installer"
  no_stage
}
missing_release_row() {
  new_home missing
  run "$installer" --version 0.9.0
  [[ $status == 1 && $(first_err | cut -d' ' -f3-4) == "release=failed url=file://$www/repos/vanillagreencom/vgshell/releases/tags/v0.9.0" ]]
}

echo "releases"
row_job latest_row
row_job check "the caller's terminal installs launcher packages and preserves failed-install status" terminal_row "$installer"
row_job check "required packages install through the floating presenter, with AUR and English data and no optional packages" packages_row "$installer"
row_job check "a failed dependency install keeps the previous release and removes staging" runtime_failure_row "$installer"
row_job check "the launcher prerequisite and real presenter refuse before fetch or launch" launcher_row "$installer"
row_job check "Nix with every available required command permits release, current and Git installs" nix_present_row "$installer"
row_job check "Nix names only the missing available required package" nix_missing_row "$installer"
row_job pinned_row
row_job check "a writer under the lock removes a dead run's staging directory" stage_row
row_job check "a checksum mismatch refuses and leaves nothing: no data directory, no link, no download" mismatch_row "$installer"
row_job check "an archive SHA256SUMS does not list refuses and leaves nothing" unlisted_row "$installer"
row_job check "a release tag that is no version refuses" tag_row "$installer"
row_job check "a release that does not exist refuses on the fetch" missing_release_row
row_job check "an archive with another top directory refuses and leaves current, no version and no stage" layout_row "$installer"
row_job check "a held self lock refuses with 75 and installs nothing" busy_row "$installer"
rows_join

signature_rows() {
  new_home sig-none
  run "$no_key" --version 0.5.0
  check "with no release key published the signature is unchecked" out_has "signature=unchecked reason=no-release-key"
  new_home sig-good
  release_keyring
  run "$signing" --version 0.5.0
  check "a signature by the release key passes" test "$status" = 0
  check "it names the key" out_has "signature=good key=$release_fpr"
  unset RUN_GNUPG
  check "a signature by another key in the keyring refuses and leaves nothing" signature_other_row "$signing"
  new_home sig-unimported
  run "$signing" --version 0.5.0
  check "a release key gpg does not hold leaves the signature unchecked" out_has "signature=unchecked reason=key-not-imported key=$release_fpr"
}
echo "signatures"
row_job signature_rows
rows_join

args_row() {
  new_home args
  run "$installer" --version 1.2
  check "a malformed --version exits 2" refused 2 "install.sh: refused: version=1.2"
  run "$installer" --git --uninstall
  check "--git with --uninstall exits 2" refused 2 "install.sh: refused: argument=--uninstall conflict=--git"
  run "$installer" --version 0.1.0 --git
  check "--version with --git exits 2" refused 2 "install.sh: refused: argument=--version conflict=--git"
}
force_system_row() {
  new_home force-system
  RUN_PATH="$vgs_db:$run_path" run "$installer" --force
  [[ $status == 0 ]]
}
foreign_force_row() {
  check "a command install.sh did not make is refused and stays" foreign_row "$installer"
  run "$installer" --force
  check "--force replaces the foreign link" test "$status" = 0 -a "$(readlink -- "$h/.local/bin/vgshell")" = "$d/current/bin/vgshell"
}
echo "refusals"
row_job args_row
row_job check "root is refused" root_row "$installer"
row_job check "a system other than Linux is refused" os_row "$installer"
row_job check "an installed system package is refused" system_row "$installer"
row_job check "--force installs beside a system package" force_system_row
row_job foreign_force_row
rows_join

arch_os="$tmp/os-arch"; printf 'NAME="Arch Linux"\nID=arch\n' >"$arch_os"
pm_all="$tmp/pm-all"; mkdir -p "$pm_all"
for pm in pacman apt-get dnf5 dnf xbps-install emerge nix; do stub "$pm_all" "$pm" "" 1; done
low="$tmp/low"; mkdir -p "$low"
stub "$low" Hyprland "Hyprland 0.55.2 built from branch fixture"
stub "$low" nmcli "nmcli tool, version 1.56.0"
stub "$low" qrencode "qrencode version 4.1.1"
floor_rows() {
  new_home floor
  with_os "$arch_os"
  RUN_PATH="$low:$pm_all:$tools_nogit" run "$installer" --version 0.1.0
  RUN_WRAP=()
  check "a floor miss exits 78" test "$status" = 78
  check "a missing tool is named with have=none" err_has "install.sh: refused: floor=quickshell have=none need=0.3.1"
  check "a tool below its floor names its version" err_has "install.sh: refused: floor=hyprland have=0.55.2 need=0.56"
  check "every miss is named, not the first alone" err_has "install.sh: refused: floor=git have=none need=present"
  check "the missing launcher is named with have=none" err_has "install.sh: refused: floor=xdg-terminal-exec have=none need=present"
  check "the miss names the distribution's install command" err_has "Install them as root: pacman -S --needed -- quickshell hyprland git xdg-terminal-exec"
  check "the floor miss writes nothing" test ! -e "$h/.local"
  check "the floor miss leaves nothing in TMPDIR" scratch_empty
}

# Hyprland's main() throws before it parses --version when XDG_RUNTIME_DIR
# is unset: an uncaught std::runtime_error, so SIGABRT and 134.
# $needs_rt's Hyprland answers only with XDG_RUNTIME_DIR set, $aborts'
# never does.
hyprland_abort() { # DIR CONDITION: a Hyprland that aborts while CONDITION holds
  cat >"$1/Hyprland" <<SH
#!/bin/sh
if $2; then
  echo "terminate called after throwing an instance of 'std::runtime_error'" >&2
  echo "  what():  XDG_RUNTIME_DIR is not set!" >&2
  exit 134
fi
echo "Hyprland 0.56 built from branch fixture"
SH
  chmod +x "$1/Hyprland"
}
needs_rt="$tmp/needs-rt"; aborts="$tmp/aborts"; mkdir -p "$needs_rt" "$aborts"
hyprland_abort "$needs_rt" '[ -z "${XDG_RUNTIME_DIR:-}" ]'
hyprland_abort "$aborts" true
runtime_row() { # BIN: a Hyprland that aborts with no XDG_RUNTIME_DIR meets the floor when the caller has none
  new_home runtime
  with_os "$default_os"
  RUN_WRAP+=(env -u XDG_RUNTIME_DIR)
  RUN_PATH="$needs_rt:$run_path" run "$1" --version 0.1.0
  RUN_WRAP=()
  [[ $status == 0 ]] && ! grep -q -e '^install\.sh: refused: floor=' -e '^Install them' "$tmp/err" && scratch_empty
}
unreadable_row() { # BIN: an installed Hyprland whose version cannot be read is named with its cause, not an install command
  new_home unreadable
  with_os "$arch_os"
  RUN_PATH="$aborts:$stubs:$pm_all:$tools" run "$1" --version 0.1.0
  RUN_WRAP=()
  refused 78 "install.sh: refused: floor=hyprland have=unknown need=0.56" &&
    err_has "hyprland is installed, but its version could not be read: Hyprland --version exited 134:" &&
    err_has "    what():  XDG_RUNTIME_DIR is not set!" &&
    ! grep -q -e '^Install them' -e '^No supported package manager' "$tmp/err" &&
    [[ ! -e $h/.local ]] && scratch_empty
}
# The distributions: os-release text and the package managers on PATH. Each
# row leaves git missing and compares the command install.sh names with the
# one `vgshell pkg detect` and `vgshell pkg plan install` give on the same system.
pm_dnf4="$tmp/pm-dnf4"; mkdir -p "$pm_dnf4"; stub "$pm_dnf4" dnf "" 1
pm_none="$tmp/pm-none"; mkdir -p "$pm_none"
distros=(
  "arch|ID=arch|$pm_all"
  "cachyos|ID=cachyos\nID_LIKE=arch|$pm_all"
  "fedora with dnf5|ID=fedora|$pm_all"
  "fedora with dnf 4|ID=fedora|$pm_dnf4"
  "debian|ID=debian|$pm_all"
  "pop, like ubuntu|ID=pop\nID_LIKE=\"ubuntu debian\"|$pm_all"
  "void|ID=\"void\"|$pm_all"
  "gentoo|ID=gentoo|$pm_all"
  "nixos|ID=nixos|$pm_all"
  "an unknown distribution|ID=plan9|$pm_all"
  "arch without pacman|ID=arch|$pm_none"
)
# The package config/requirements.json names for COMMAND on MANAGER.
requirement_package() { # COMMAND MANAGER
  python3 -c 'import json, sys
rows = [r for r in json.load(open(sys.argv[1])) if r["command"] == sys.argv[2]]
print(rows[0]["packages"][sys.argv[3]])' "$repo/config/requirements.json" "$1" "$2"
}
distro_row() { # BIN NAME OS_TEXT PM_DIR: install.sh names the command vgshell pkg plans
  local os="$tmp/os-row" want detect id plan
  printf '%b\n' "$3" >"$os"
  detect="$("$unshare_bin" -rm sh -c 'mount --bind "$1" /etc/os-release && shift && exec "$@"' sh "$os" \
    "${base_env[@]}" PATH="$4:$tools" "$repo/bin/vgshell" pkg detect --json)" || return 1
  id="$(python3 -c 'import json, sys
p = json.loads(sys.argv[1])["primary"]
print(p["id"] if p else "-")' "$detect")"
  if [[ $id == - ]]; then
    want="No supported package manager found: install git with your distribution's package manager."
  elif plan="$("${base_env[@]}" PATH="$4:$tools" "$repo/bin/vgshell" pkg plan install "$id" "$(requirement_package git "$id")" 2>/dev/null)"; then
    want="$(python3 -c 'import json, sys
p = json.loads(sys.argv[1])
print(("Install them as root: " if p["elevate"] else "Install them: ") + " ".join(p["steps"][0]))' "$plan")"
  else
    want="Add these $id packages to your system configuration: $(requirement_package git "$id")"
  fi
  new_home distro
  with_os "$os"
  RUN_PATH="$stubs:$4:$tools_nogit" run "$1" --version 0.1.0
  RUN_WRAP=()
  if [[ $status == 78 ]] && err_has "$want"; then return 0; fi
  printf '    want [%s]\n' "$want"
  sed 's/^/    got  /' "$tmp/err"
  return 1
}
# The tables against their sources, read by node from the files themselves.
drift_row() { # BIN: prints each drift, fails on any
  node - "$1" "$repo/bin/vgshell" "$repo/config/requirements.json" <<'JS'
"use strict";
const fs = require("fs");
const [installer, vgshell, requirementsFile] = process.argv.slice(2);
const block = (text, name, file) => {
    const m = new RegExp("\\n\\s*" + name + "='\\n([\\s\\S]*?)\\n'\\n").exec(text);
    if (m === null) { console.log("extractor=broken block=" + name + " file=" + file); process.exit(1); }
    return m[1].split("\n").filter(l => l.trim() !== "").map(l => l.trim().split(/\s+/));
};
const script = fs.readFileSync(installer, "utf8");
const floor = block(script, "floor", installer);
const packages = block(script, "packages", installer);
const preflight = block(fs.readFileSync(vgshell, "utf8"), "preflight_floor", vgshell);
const start = /^  start_tools=\(([^)]*)\)$/m.exec(script);
if (start === null) { console.log("extractor=broken block=start_tools file=" + installer); process.exit(1); }
const startTools = start[1].trim().split(/\s+/);
const required = JSON.parse(fs.readFileSync(requirementsFile, "utf8")).filter(r => !r.optional && (floor.some(row => row[0] === r.command) || startTools.includes(r.command)));
// Floors: a broken extractor reads fewer rows than the sources hold today.
if (floor.length < 6 || packages.length < 6 || preflight.length < 5 || required.length !== 6 || !startTools.includes("xdg-terminal-exec")
        || !["node", "python3", "git", "flock", "setpriv", "xdg-terminal-exec"].every(command => required.some(row => row.command === command))) {
    console.log("extractor=broken floor=" + floor.length + " packages=" + packages.length + " preflight=" + preflight.length + " required=" + required.length);
    process.exit(1);
}
const drift = [];
const floorRow = new Map(floor.map(r => [r[0], r]));
for (const p of preflight) {
    const f = floorRow.get(p[0]);
    if (f === undefined) { drift.push("floor=" + p[0] + " reason=missing"); continue; }
    if (f[1] !== p[1]) drift.push("floor=" + p[0] + " need=" + f[1] + " preflight=" + p[1]);
    // Hyprland alone is probed differently: its binary, not the session.
    if (p[0] !== "hyprland" && f.slice(2).join(" ") !== p.slice(2).join(" ")) drift.push("floor=" + p[0] + " reason=probe");
}
const packageRow = new Map(packages.map(r => [r[0], new Map(r.slice(1).map(pair => pair.split("=")))]));
for (const r of required) {
    if (!floorRow.has(r.command) && !startTools.includes(r.command)) drift.push("floor=" + r.command + " reason=missing-requirement");
    const mine = packageRow.get(r.command);
    if (mine === undefined) { drift.push("packages=" + r.command + " reason=missing"); continue; }
    const want = Object.entries(r.packages).sort().join(" ");
    const have = [...mine.entries()].sort().join(" ");
    if (want !== have) drift.push("packages=" + r.command + " have=" + have + " want=" + want);
}
for (const tool of floorRow.keys()) if (!packageRow.has(tool)) drift.push("packages=" + tool + " reason=no-row");
for (const d of drift) console.log(d);
process.exit(drift.length === 0 ? 0 : 1);
JS
}
echo "floor"
row_job floor_rows
row_job check "a Hyprland that needs a runtime directory meets the floor from a shell with none" runtime_row "$installer"
row_job check "an installed Hyprland whose version cannot be read is named with its exit and error, not an install command" unreadable_row "$installer"
for row in "${distros[@]}"; do
  IFS='|' read -r name os_text pm_dir <<<"$row"
  row_job check "on $name install.sh names vgshell pkg's install command" distro_row "$installer" "$name" "$os_text" "$pm_dir"
done
row_job check "the floor and package tables match bin/vgshell and config/requirements.json" drift_row "$installer"
rows_join

git_rows() {
  git_home git
  check "--git clones main" test "$(g -C "$d/git" rev-parse HEAD)" = "$(g -C "$bare" rev-parse main)"
  check "--git names the clone" out_has "ok installed=vgshell git=$d/git"
  check "--git points the command at the clone" test "$(readlink -- "$h/.local/bin/vgshell")" = "$d/git/bin/vgshell"
  check "--git leaves the release's current alone" test "$(readlink -- "$d/current")" = 0.1.0
  "${base_env[@]}" HOME="$h" XDG_CONFIG_HOME="$h/.config" XDG_RUNTIME_DIR="$rt_empty" "$h/.local/bin/vgshell" self status --json >"$tmp/status.json" 2>/dev/null
  check "vgshell self status judges the clone a checkout" json_is "$tmp/status.json" 'd["method"] == "checkout"'
  run "$installer" --git
  check "a second --git refuses" refused 1 "install.sh: refused: git=exists path=$d/git"
}
echo "git"
row_job git_rows
rows_join

uninstall_rows() {
  git_home uninstall
  mkdir -p "$h/.config/vgshell" "$h/.local/state/vgshell"
  printf 'mine\n' >"$h/.config/vgshell/shell.json"; printf 'mine\n' >"$h/.local/state/vgshell/applied.json"
  printf 'other\n' >"$d/notes"
  run "$installer" --uninstall
  check "--uninstall succeeds" test "$status" = 0
  check "it removes the versions, current and the clone" test ! -e "$d/0.1.0" -a ! -e "$d/current" -a ! -e "$d/git"
  check "it keeps a file it did not install" test -f "$d/notes"
  check "it says it kept the data directory" out_has "kept=$d reason=not-vgs-files"
  check "it removes the link" test ! -e "$h/.local/bin/vgshell" -a ! -L "$h/.local/bin/vgshell"
  check "it keeps the configuration" test -f "$h/.config/vgshell/shell.json"
  check "it names the configuration it kept" out_has "kept=$h/.config/vgshell"
  check "it keeps the state" test -f "$h/.local/state/vgshell/applied.json"
  check "it names the state it kept" out_has "kept=$h/.local/state/vgshell"
}
lock_kept_row() { # BIN: --uninstall keeps the lock file, the inode a concurrent writer may hold open
  local inode
  git_home lock-kept
  inode="$(stat -c %i -- "$d/.self.lock")"
  run "$1" --uninstall
  [[ $status == 0 && ! -e $d/current && $(stat -c %i -- "$d/.self.lock" 2>/dev/null) == "$inode" ]]
}
echo "uninstall"
row_job check "--uninstall refuses a clone with changes and removes nothing" modified_row "$installer"
row_job check "--uninstall refuses a clone with a commit no remote branch has" unpublished_row "$installer"
row_job check "--uninstall refuses a clone whose other local branch holds such a commit" branch_row "$installer"
row_job check "--uninstall refuses a clone holding a stash" stash_row "$installer"
row_job check "--uninstall refuses while the running shell was started from a tree it removes" running_row "$installer"
row_job uninstall_rows
row_job check "it keeps the lock a concurrent writer may hold open" lock_kept_row "$installer"
row_job check "--uninstall keeps a foreign link and names it" keep_foreign_row "$installer"
rows_join

echo "truncation"
# truncated_row BIN: no prefix of BIN piped to bash runs a command. The
# cuts are every line end, every 97th byte and every byte of the last 256,
# which hold main's call; bash -x traces each command it runs as a line
# starting with +.
truncated_row() {
  local size cut body chunks chunk pid failed=0 LC_ALL=C
  local -a cuts pids
  # A cut that drops only the trailing newlines leaves the whole script.
  body="$(<"$1")"
  size="${#body}"
  mapfile -t cuts < <({ LC_ALL=C awk '{ n += length($0) + 1; print n }' "$1"; seq 97 97 "$size"; seq $((size > 256 ? size - 256 : 1)) "$size"; } | sort -nu)
  ((${#cuts[@]} > 300)) || { echo "    cuts=${#cuts[@]}: the cut extractor read too few"; return 1; }
  new_home truncated
  chunks="$(nproc)"
  ((chunks > 8)) && chunks=8
  ((chunks > ${#cuts[@]})) && chunks=${#cuts[@]}
  mkdir -p "$tmp/truncated"
  for ((chunk = 0; chunk < chunks; chunk++)); do
    (
      local i line trace="$tmp/truncated/trace-$chunk"
      for ((i = chunk; i < ${#cuts[@]}; i += chunks)); do
        [[ ! -e $tmp/truncated/found ]] || exit 0
        cut="${cuts[i]}"
        ((cut < size)) || continue
        printf '%s' "${body:0:cut}" | env -i PATH="$run_path" HOME="$h" TMPDIR="$scratch" VGS_TEST_RUN=1 VGS_RELEASE_API="file://$www" \
          XDG_RUNTIME_DIR="$rt_empty" bash -x >/dev/null 2>"$trace" || true
        line=""
        while IFS= read -r line; do
          [[ $line != +* ]] || break
          line=""
        done <"$trace"
        if [[ -n $line ]] && mkdir "$tmp/truncated/found" 2>/dev/null; then
          printf 'cut=%s ran: %s\n' "$cut" "$line" >"$tmp/truncated/found/message"
          exit 0
        fi
      done
    ) &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
  ((failed == 0)) || return 1
  if [[ -s $tmp/truncated/found/message ]]; then
    echo "    $(<"$tmp/truncated/found/message")"
    return 1
  fi
  [[ ! -e $h/.local ]]
}
row_job check "no truncated download of install.sh runs a command" truncated_row "$installer"
rows_join

echo "controls"
# control NAME ROW [ARGS...]: ROW must fail on $copy, which the caller made.
control() {
  local name="$1" row="$2"
  shift 2
  if "$row" "$copy" "$@" >/dev/null; then fail "control: $name: $row passed on the copy"; else ok "control: $name"; fi
}
# unwrap NAME DROP...: sets copy to install.sh without the wrapper lines
# DROP names: group-open, main-open, main-close, call, group-close.
unwrap() {
  local name="$1"
  shift
  copy="$tmp/copies/$name"
  mkdir -p "$tmp/copies"
  python3 - "$installer" "$copy" "$@" <<'PY'
import sys
source, target, drop = sys.argv[1], sys.argv[2], set(sys.argv[3:])
lines = open(source).read().split("\n")
closes = [i for i, l in enumerate(lines) if l == "}"]
wrapper = {
    "group-open": lines.index("{"),
    "main-open": lines.index("main() {"),
    "main-close": closes[-2],
    "call": lines.index('main "$@"'),
    "group-close": closes[-1],
}
order = [wrapper[k] for k in ("group-open", "main-open", "main-close", "call", "group-close")]
if order != sorted(order) or len(set(order)) != 5:
    sys.exit("unwrap: wrapper=unrecognised lines=" + str(order))
cut = {wrapper[k] for k in drop}
open(target, "w").write("\n".join(l for i, l in enumerate(lines) if i not in cut))
PY
}
unwrap unwrapped group-open main-open main-close call group-close
row_job control "a copy with the body outside main runs a truncated download" truncated_row
unwrap ungrouped group-open group-close
row_job control "a copy whose call of main stands outside the group runs a cut after the word main" truncated_row

# rule NAME ROW NEEDLE REPLACEMENT: a copy of install.sh without one rule,
# NEEDLE replaced, on which ROW, the row that judges the rule, must fail.
rule() {
  copy_with "$1" "$installer" "$3" "$4"
  control "a copy without the $1 rule" "$2"
}
row_job rule checksum mismatch_row '[[ $got == "$want" ]] ||' '[[ $got == "$got" ]] ||'
row_job rule sum-count unlisted_row '((count == 1)) || refuse 1 "checksum=unlisted' '((count == count)) || refuse 1 "checksum=unlisted'
row_job rule tag tag_row '[[ $tag =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] ||' '[[ v0.8.0 =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] ||'
row_job rule layout layout_row 'if ((${#top[@]} != 1)) || [[' 'if ((${#top[@]} != 1)) && [['
row_job rule lock busy_row 'flock -n 9 || refuse 75' 'flock -n 9 || true || refuse 75'
row_job rule root root_row '((EUID != 0)) ||' '((EUID != -1)) ||'
row_job rule os os_row '[[ $os == Linux ]] ||' '[[ $os == "$os" ]] ||'
row_job rule package-database system_row 'pacman -Q -- "$name" >/dev/null 2>&1; then' 'pacman -Q -- "$name" >/dev/null 2>&1 && false; then'
row_job rule foreign-link foreign_row '&& $(link_state) == foreign ]]' '&& $(link_state) == none ]]'
row_job rule modified-clone modified_row '[[ -z $out ]] || refuse 1 "modified=' 'true || refuse 1 "modified='
row_job rule unpublished-commit unpublished_row '((out == 0)) || refuse 1 "unpublished=' 'true || refuse 1 "unpublished='
row_job rule other-branches branch_row 'rev-list --count HEAD --branches --not --remotes' 'rev-list --count HEAD --not --remotes'
row_job rule stash stash_row 'if "${git_in[@]}" rev-parse -q --verify refs/stash >/dev/null; then' 'if false; then'
row_job rule running-shell running_row 'if [[ $tree == "$(readlink -f -- "$data")"/* ]]; then' 'if false; then'
row_job rule keep-foreign-link keep_foreign_row '[[ $state != ours ]] || rm -f -- "$link"' 'rm -f -- "$link"'
row_job rule keep-lock lock_kept_row '^(current|git|\.self-update-.*|[0-9]+' '^(current|git|\.self\.lock|\.self-update-.*|[0-9]+'
row_job rule floor-need drift_row 'quickshell 0.3.1   ^Quickshell' 'quickshell 0.3.0   ^Quickshell'
row_job rule requirement-package drift_row 'dnf=util-linux-core' 'dnf=util-linux'
row_job rule runtime-packages packages_row 'runtime_install() { # TREE' 'runtime_install() { return 0 # TREE'
row_job rule runtime-result runtime_failure_row '[[ $code == 0 ]] || refuse 1' '[[ $code == "$code" ]] || refuse 1'
row_job rule package-verb packages_row '"$tree/bin/vgshell" pkg run install' '"$tree/bin/vgshell" pkg plan install'
row_job rule launcher-prerequisite launcher_row 'start_tools=(xdg-terminal-exec)' 'start_tools=()'
row_job rule caller-terminal terminal_row 'if { : 2>/dev/null <>/dev/tty; }; then' 'if false; then'
row_job rule nix-present nix_present_row '[[ -z $names ]] || refuse 78 "requirements=configuration manager=nix"' '[[ -n $names ]] || refuse 78 "requirements=configuration manager=nix"'
row_job rule nix-missing nix_missing_row 'row.state === "missing"' 'row.state === "present"'
row_job rule nix-optional nix_present_row '!row.optional && row.state' 'true && row.state'
row_job rule probe-runtime runtime_row 'XDG_RUNTIME_DIR="$tmp/runtime" "${argv[@]}"' 'XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" "${argv[@]}"'
row_job rule unknown-not-installable unreadable_row '[[ $have == unknown ]] || names+=' '[[ $have == nothing ]] || names+='
copy_with manager-order "$installer" 'fedora        dnf5,dnf' 'fedora        dnf,dnf5'
row_job control "a copy that prefers dnf 4 over dnf5" distro_row "fedora with dnf5" "ID=fedora" "$pm_all"
copy_with any-key "$signing" '[[ ${field[2]} == "$release_key" ||' '[[ -n ${field[2]} ||'
row_job control "a copy that accepts a signature by any key in the keyring" signature_other_row
rows_join

check "the rows' git writes leave the caller's XDG git configuration unchanged" cmp -s -- "$tmp/caller-git-config" "$caller_config/git/config"

rows_done "$suite"
