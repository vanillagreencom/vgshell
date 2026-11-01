#!/usr/bin/env bash
# Controls for the vgs.updates update pipeline: tui/update.sh and
# tui/update-source.sh over tui/pipeline.sh and bin/facts, and tui/log.sh,
# which shows the log the pipeline writes. Each row runs a
# copy of the plugin on a pseudo-terminal script(1) opens, as
# `vgshell-tui present` runs it, under an explicit environment whose PATH
# holds only stand-ins and the few tools the pipeline runs. VGS_TUI_LIB
# names a fixture tree holding the shipped bin/lib/tui.sh, the loader and
# judge-files.js bin/facts reads, and a stand-in
# vgshell. Every stand-in appends its name and arguments to one calls file, so
# a row reads the order of every step and its argv. No row reaches a real
# vgshell, package manager, sudo, doas, snapshot tool or live session. The reboot
# rows stand a copied `sleep` in for Hyprland and remove its file while it
# runs, so /proc names its executable deleted. The stand-in pacman-conf
# names a RootDir in the fixture, where a reboot row puts the CachyOS
# reboot hook, and the stand-in findmnt names the mounted file systems.
#
# Package review behavior lives in fixtures/pkg-review/runtime-test.js. This
# suite retains the pipeline's caller-order contract and other step results.
#
# Each control runs a row against a copy of the plugin whose
# tui/pipeline.sh drops one rule, and that row must fail.
set -euo pipefail

# shellcheck source=scripts/vgshell-rows.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
for tool in script flock; do
  command -v "$tool" >/dev/null || { echo "test-updates-pipeline: status=not-measured missing=$tool"; exit 77; }
done
kernel=""
for dir in /lib/modules/*/; do [[ -d $dir ]] && { kernel="$(basename -- "$dir")"; break; }; done
[[ -n $kernel ]] || { echo "test-updates-pipeline: status=not-measured missing=/lib/modules/<release>"; exit 77; }

plugin="$tmp/plugin"
cp -R -- "$repo/shell/plugins/vgs.updates" "$plugin"
tree="$tmp/tree"
mkdir -p "$tree/bin/lib" "$tree/shell/Commons"
cp -- "$repo/bin/lib/tui.sh" "$repo/bin/lib/hyprland-instance.sh" "$repo/bin/lib/qml-library.js" "$repo/bin/lib/judge-files.js" "$repo/bin/lib/aur-helper.sh" "$repo/bin/lib/pkg-config.js" "$tree/bin/lib/"
cp -- "$repo/shell/Commons/PageReference.js" "$tree/shell/Commons/"
# This fixture loader observes the real library returned to facts. The
# existing self verb never draws a window, so the fixture checks that same
# library's window rows without adding a test verb to the shipped command.
cat >>"$tree/bin/lib/qml-library.js" <<'JS'
const shippedLoad = module.exports.load;
module.exports.load = function(file, modules) {
  const library = shippedLoad(file, modules);
  if (process.env.FIX && require("node:fs").existsSync(process.env.FIX + "/transaction") && library.rebootPackages) {
    const rebootPackages = library.rebootPackages;
    library.rebootPackages = function(...args) {
      const result = rebootPackages(...args);
      for (const name of result) require("node:fs").appendFileSync(process.env.CALLS, "reboot-package " + name + "\n");
      return result;
    };
  }
  if (process.env.UPDATES_TEST_SECONDARY === "1" && path.basename(file) === "UpdatesLogic.js") {
    const assert = require("node:assert/strict");
    const reason = "helper-missing=checkupdates";
    const secondary = library.windowRows({ sources: [{ source: "pacman", count: null, error: reason }] })[0].detail;
    process.stderr.write("updates-test: secondary=reached\n");
    assert.match(library.errorText(reason), /\]\(page:/);
    assert.doesNotMatch(secondary, /[\[\]]|\(page:/, "updates-test: secondary=markup");
    assert.ok(secondary.length > 0);
    process.stderr.write("updates-test: secondary=plain\n");
  }
  return library;
};
JS
printf '0.1.0\n' >"$tree/VERSION"
calls="$tmp/calls"; fix="$tmp/fix"; rt="$tmp/rt"; state="$tmp/state"
mkdir -p "$fix" "$rt" "$state"
log="$state/vgshell/updates/update.log"
# Keep the test terminal's input open like a live terminal. An early EOF
# from /dev/null can be echoed by the nested script(1) log recorder.
mkfifo "$tmp/terminal-input"
exec {terminal_input}<>"$tmp/terminal-input"

# Stand-ins. Each first appends `<name> <arguments>` to $CALLS as one whole
# line, written with a single append so stand-ins that run at once never mix
# their records.
stubs="$tmp/stubs"; snapper_dir="$tmp/snapper-bin"; tools="$tmp/tools"
mkdir -p "$stubs" "$snapper_dir" "$tools"
record='_r="${0##*/}"; for a; do _r="$_r $a"; done; printf "%s\n" "$_r" >>"$CALLS"'
stub() { # DIR NAME BODY
  printf '#!/bin/sh\n%s\n%s\n' "$record" "$3" >"$1/$2"
  chmod +x "$1/$2"
}
# vgshell answers each read from $FIX; pacman's plan names the elevator in
# $FIX/elevator; `pkg detect` fails with 5 while $FIX/fail-detect exists.
# `pkg run` for a manager ID ends, however its steps ended, with the scan
# line bin/vgshell-pkg's rescanShell prints on stdout, `shell=rescan-started`,
# unless its fixture ends on the `rescan=` refusal instead. It fails with 9
# for $FIX/fail-<id>, after a
# coloured error line on stderr ending in a carriage return; exits 130, as
# a Ctrl-C ends it, for $FIX/interrupt-<id>; leaves pacman's question
# unanswered on stderr, as a no does, for $FIX/decline-<id>, and before its
# closing `rescan=` refusal for $FIX/decline-rescan-<id>; fails after a
# question answered yes for $FIX/answered-<id>; ends on its closing
# `rescan=` refusal after an error line for $FIX/rescan-<id>. For
# $FIX/order-<id> it writes pacman's size summary to stdout and then its
# question to stderr with no newline, and records in $FIX/terminals
# whether stdin, stdout and stderr are terminals; $FIX/relay-<id> does
# the same through use-pty-relay, as sudo's use_pty runs pacman. For
# $FIX/ask-<id> it asks pacman's [Y/n] and reads the answer, for
# $FIX/ask-default-no-<id> a [y/N]; both then exit 1, as a no does. For
# $FIX/unprefixed-<id> it fails after an error line the error table does
# not name. For $FIX/faulted-<id> it fails as pacman's failed commit does, in its order
# and streams: pm_printf's `error: ` line and the conflicting file on
# stderr, then `Errors occurred, no packages were upgraded.` on stdout
# (pacman src/pacman/sync.c sync_prepare_execute and src/pacman/util.c
# pm_printf, master read through the GitLab API on 2026-10-17; both
# strings are in pacman 7.1.0's /usr/bin/pacman). For
# $FIX/transcript-gone-<id> it removes the run's transcript and fails, and
# for $FIX/transcript-replaced-<id> it puts an empty file at the
# transcript's path, which script(1) no longer writes, and fails. `plugin|theme update` for an ID
# declines, as its [y/N] question answered no does, for $FIX/decline-<id>,
# and refuses an offline fetch with git's message for $FIX/offline-<id>.
# `pkg owner` answers only while $FIX/owner exists, with a new version
# after its first answer when $FIX/owner-changes does.
stub "$tree/bin" vgshell 'pkg_run() {
  case "$5" in pacman|aur) [ ! -e "$FIX/transaction" ] || "$FIX/transaction" "$5" "$@" || exit "$?" ;; esac
  [ ! -e "$FIX/build-$5" ] || { printf "==> ERROR: A failure occurred in build().\n    Aborting...\n" >&2; exit 4; }
  [ ! -e "$FIX/interrupt-$5" ] || exit 130
  [ ! -e "$FIX/fail-$5" ] || { printf "\033[31merror:\033[0m failed to install crush\r\n" >&2; exit 9; }
  [ ! -e "$FIX/decline-$5" ] || { printf ":: Proceed with installation? [Y/n] " >&2; exit 1; }
  [ ! -e "$FIX/decline-rescan-$5" ] || { printf ":: Proceed with installation? [Y/n] vgshell: refused: rescan=refused\nthe plugin files changed; run vgshell ipc call shell rescanPlugins\n" >&2; exit 1; }
  [ ! -e "$FIX/answered-$5" ] || { printf ":: Proceed with installation? [Y/n] error: failed to commit transaction (conflicting files)\n" >&2; exit 1; }
  [ ! -e "$FIX/rescan-$5" ] || { printf "error: failed to commit transaction (conflicting files)\nvgshell: refused: rescan=refused\nthe plugin files changed; run vgshell ipc call shell rescanPlugins\n" >&2; exit 1; }
  [ ! -e "$FIX/order-$5" ] || { t=""; for fd in 0 1 2; do [ -t "$fd" ] && t="$t$fd"; done; echo "$t" >"$FIX/terminals"; order; }
  [ ! -e "$FIX/relay-$5" ] || exec use-pty-relay /bin/sh -c "$(sed -n "/^order() {/,/^}/p" "$0"); order"
  [ ! -e "$FIX/ask-$5" ] || { printf ":: Proceed with installation? [Y/n] " >&2; read -r answer; exit 1; }
  [ ! -e "$FIX/ask-default-no-$5" ] || { printf ":: Remove the old kernel? [y/N] " >&2; read -r answer; exit 1; }
  [ ! -e "$FIX/unprefixed-$5" ] || { printf "mise ERROR Failed to install core:node@22.0.0\n" >&2; exit 1; }
  [ ! -e "$FIX/faulted-$5" ] || { printf "error: failed to commit transaction (conflicting files)\ncrush: /usr/bin/crush exists in filesystem\n" >&2; printf "Errors occurred, no packages were upgraded.\n"; exit 1; }
  [ ! -e "$FIX/transcript-gone-$5" ] || { rm -f -- "${VGS_TUI_TRANSCRIPT:?}"; printf "error: failed to install crush\n" >&2; exit 1; }
  [ ! -e "$FIX/transcript-replaced-$5" ] || { rm -f -- "${VGS_TUI_TRANSCRIPT:?}"; : >"$VGS_TUI_TRANSCRIPT"; printf "error: failed to install crush\n" >&2; exit 1; }
}
order() {
  printf "Total Download Size:    952.82 MiB\nTotal Installed Size:  3120.40 MiB\nNet Upgrade Size:        12.04 MiB\n"
  printf "\n:: Proceed with installation? [Y/n] " >&2
  exit 1
}
case "$1 $2" in
  "pkg review-transaction") exec node "$(cat "${0%/*}/review-owner")" review-transaction ;;
  "pkg review")
    printf "{\"version\":1,\"decision\":\"proceed\",\"reviewed\":[],\"skipped\":[],\"coverage\":\"declined\",\"receipt\":\"fixture\"}\n" >"$6" ;;
  "pkg review-custom-mode") echo unknown ;;
  "pkg review-custom-consume") : ;;
  "pkg ensure-helper")
    # The owner clones through aur-helper.sh into its private tree and
    # builds there (bin/vgshell-pkg bootstrapHelper).
    d="$(mktemp -d)" s=0
    bash "${0%/*}/lib/aur-helper.sh" "$0" "$d/paru" && (cd "$d/paru" && makepkg -si) || s=$?
    rm -rf -- "${d:?}"
    exit "$s" ;;
  "plugin settings") cat "$FIX/settings.json" ;;
  "pkg detect") [ ! -e "$FIX/fail-detect" ] || exit 5; cat "$FIX/detect.json" ;;
  "pkg plan")
    case "$4" in
      pacman) echo "{\"manager\":\"pacman\",\"binary\":\"pacman\",\"action\":\"upgrade\",\"elevate\":true,\"steps\":[[\"pacman\",\"-Syu\"]],\"elevator\":{\"ok\":true,\"command\":\"$(cat "$FIX/elevator")\"}}" ;;
      flatpak) echo "{\"manager\":\"flatpak\",\"binary\":\"flatpak\",\"action\":\"upgrade\",\"elevate\":false,\"steps\":[[\"flatpak\",\"update\"]],\"elevator\":null}" ;;
      mise) echo "{\"manager\":\"mise\",\"binary\":\"mise\",\"action\":\"upgrade\",\"elevate\":false,\"steps\":[[\"env\",\"MISE_MINIMUM_RELEASE_AGE=0\",\"mise\",\"upgrade\"]],\"elevator\":null}" ;;
      aur) echo "{\"manager\":\"aur\",\"binary\":\"paru\",\"action\":\"upgrade\",\"elevate\":false,\"steps\":[[\"paru\",\"-Sua\"]],\"elevator\":null}" ;;
      *) echo "vgshell: refused: manager=$4 action=upgrade reason=unsupported" >&2; exit 1 ;;
    esac ;;
  "self status") cat "$FIX/self.json" ;;
  "self update") echo "ok updated=vgs from=a to=b" ;;
  "plugin outdated") cat "$FIX/plugins.json" ;;
  "theme outdated") cat "$FIX/themes.json" ;;
  "pkg run")
    if [ "$3" = reinstall ] && [ "$5" = aur ]; then
      shift 5
      exec paru -S "$@"
    fi
    st=0
    ( pkg_run "$@" ) || st=$?
    [ -e "$FIX/rescan-$5" ] || [ -e "$FIX/decline-rescan-$5" ] || echo "shell=rescan-started"
    exit "$st" ;;
  "plugin update"|"theme update")
    if [ "$1" = theme ] && [ -x "$FIX/theme-update" ]; then exec "$FIX/theme-update" "$@"; fi
    for id; do :; done
    [ ! -e "$FIX/busy-$id" ] || { printf "vgshell: refused: theme=%s reason=busy\nanother theme command holds the theme lock\n" "$id" >&2; exit 75; }
    [ ! -e "$FIX/decline-$id" ] || { printf "vgshell: update %s? [y/N] vgshell: refused: declined=%s\nthe checkout stays at its commit\n" "$id" "$id" >&2; exit 1; }
    [ ! -e "$FIX/offline-$id" ] || { printf "vgshell: refused: fetch=%s\nfatal: unable to access https://example.org/acme.git/: Could not resolve host: example.org\n" "$id" >&2; exit 1; } ;;
  "pkg check")
    if [ -e "$FIX/check-$5.json" ]; then cat "$FIX/check-$5.json"
    else echo "[{\"source\":\"$5\",\"count\":0,\"packages\":[],\"checkedAt\":\"x\",\"error\":null}]"
    fi ;;
  "ipc call")
    case "$5" in
      check)
        if [ -e "$FIX/real-ipc" ]; then exec "$FIX/real-ipc" "$@"; fi
        if [ -e "$FIX/ipc-check-refuses" ]; then echo "refused: ipc=check reason=test"; exit 8; fi
        echo started ;;
    esac ;;
  "pkg owner")
    [ -e "$FIX/owner" ] || exit 1
    v=1
    if [ -e "$FIX/owner-asked" ] && [ -e "$FIX/owner-changes" ]; then v=2; fi
    : >"$FIX/owner-asked"
    echo "{\"manager\":\"pacman\",\"package\":\"vgshell-git\",\"version\":\"0.1.0.r$v\"}" ;;
  "pid ") [ -e "$FIX/running" ] || exit 69; echo 42 ;;
esac'
printf '%s\n' "$repo/bin/vgshell-pkg" >"$tree/bin/review-owner"
# gum confirm answers the exit status in $FIX/answer-<question>, 0 when
# absent: `skip` for the review's Skip or Install anyway, `reboot` for the
# reboot question; style prints its lines.
stub "$stubs" gum 'case "$1" in
  confirm)
    for q; do :; done
    case "$q" in "Start the update?"*) f=start ;; Remove*) f=orphans ;; *Reboot*) f=reboot ;; Skip*) f=skip ;; Continue*) f=continue ;; *) f=other ;; esac
    st=0; [ ! -e "$FIX/answer-$f" ] || read -r st <"$FIX/answer-$f"; exit "$st" ;;
  choose)
    st=0; [ ! -e "$FIX/review-choice-exit" ] || read -r st <"$FIX/review-choice-exit"
    [ "$st" = 0 ] || exit "$st"
    if [ -e "$FIX/answer-review" ]; then cat "$FIX/answer-review"; else echo Yes; fi ;;
  style) while [ "$#" -gt 0 ] && [ "$1" != -- ]; do shift; done; [ "$#" -gt 0 ] && shift; for a; do printf "%s\n" "$a"; done ;;
esac'
# sudo refuses every authorization and every command while
# $FIX/sudo-refuses exists; doas runs its command.
stub "$stubs" sudo 'case "$1" in -k) exit 0 ;; esac
[ ! -e "$FIX/sudo-refuses" ] || exit 1
case "$1" in -n|/usr/bin/true) exit 0 ;; esac
exec "$@"'
stub "$stubs" doas 'exec "$@"'
# use-pty-relay COMMAND...: COMMAND on a pseudo-terminal of its own, as
# sudo's use_pty runs it (sudo src/exec_pty.c): its stdout, and its stderr
# when that is a terminal, go through the new terminal, whose output is
# relayed apart from a stderr that is not a terminal, which passes to the
# command unchanged. The relay holds what it read until the question
# reaches the run's terminal, $TERMINAL_OUT, or 2 s pass, the order a
# loaded relay loop gives; that bound is the wait before an in-order relay
# releases both streams.
cat >"$stubs/use-pty-relay" <<'SH'
#!/usr/bin/env bash
hold() {
  local i=0
  while (( i < 40 )) && ! grep -qF "Proceed with installation" "$TERMINAL_OUT"; do sleep 0.05; i=$((i + 1)); done
  cat
}
cmd="$(printf '%q ' "$@")"
if [[ -t 2 ]]; then
  SHELL="$BASH" script -qfec "$cmd" /dev/null | hold
else
  SHELL="$BASH" script -qfec "$cmd 2>&3" /dev/null 3>&2 | hold
fi
exit "${PIPESTATUS[0]}"
SH
chmod +x "$stubs/use-pty-relay"
stub "$snapper_dir" snapper 'case "$*" in
  "--csvout list-configs") printf "config,subvolume\nroot,/\n" ;;
  *create*) [ ! -e "$FIX/fail-snapper" ] || exit 1 ;;
esac'
# pacman -Q answers $FIX/installed, and from its second answer on
# $FIX/installed-after when that exists, and fails while
# $FIX/fail-pacman-q exists; pacman -Q NAME answers NAME's line of
# $FIX/installed.
stub "$stubs" pacman 'case "$1" in
  -Sl) cat "$FIX/sl-$2" ;;
  -Q)
    [ ! -e "$FIX/fail-pacman-q" ] || [ -n "${2:-}" ] || exit 1
    if [ -n "${2:-}" ]; then
      while read -r n v; do [ "$n" != "$2" ] || { echo "$n $v"; exit 0; }; done <"$FIX/installed"
      exit 1
    fi
    f="$FIX/installed"
    if [ -e "$FIX/installed-asked" ] && [ -e "$FIX/installed-after" ]; then f="$FIX/installed-after"; fi
    : >"$FIX/installed-asked"
    cat "$f" ;;
  *) [ -e "$FIX/orphans" ] || exit 1; cat "$FIX/orphans" ;;
esac'
stub "$stubs" pacman-conf 'if [ "$1" = --config ]; then
  [ ! -e "$FIX/fail-hookdirs" ] || exit 1
  printf "%s\n" "$2" >>"$FIX/config-sources"
  printf "%s\n" "$FIX/hooks"
  exit 0
fi
case "$1 ${3:-}" in
  "DBPath ") echo "$FIX/db/" ;;
  "RootDir ") [ ! -e "$FIX/fail-rootdir" ] || exit 1; echo "$FIX/root/" ;;
  "--repo-list ") cat "$FIX/repos" ;;
  "--repo Server") cat "$FIX/server-$2" ;;
  "--repo SigLevel") [ ! -e "$FIX/siglevel-$2" ] || cat "$FIX/siglevel-$2" ;;
  "SigLevel ") echo PackageRequired ;;
esac'
# flock records its call and runs the real one.
stub "$stubs" flock "exec '$tools/flock' \"\$@\""
# The real vgshell IPC command judges qs output and emits its keyed
# multiline refusal. Its instance lock names this still-live suite.
stub "$stubs" qs 'if [ -e "$FIX/qs-reply" ]; then cat "$FIX/qs-reply"; exit 0; fi
if [ -e "$FIX/ipc-check-pending" ]; then
  [ -e "$FIX/ipc-persistent" ] || rm -- "$FIX/ipc-check-pending"
  echo "Target not found."
  exit 0
fi
echo "updates-target-reached" >>"$CALLS"
echo started'
stub "$stubs" sleep 'if [ "$1" = 0.2 ] && [ -e "$FIX/fast-sleep" ]; then exit 0; fi
exec "${0%/*}/../tools/sleep" "$@"'
stub "$stubs" pikaur ''
stub "$stubs" df 'a=99999999999; [ ! -e "$FIX/avail" ] || read -r a <"$FIX/avail"; printf "  Avail\n%s\n" "$a"'
stub "$stubs" hyprctl 'exit 1'
stub "$stubs" uname "echo $kernel"
stub "$stubs" systemctl ''
# findmnt lists the mounted file system types in $FIX/fstypes, none when
# it is absent, and fails while $FIX/fail-findmnt exists.
stub "$stubs" findmnt '[ ! -e "$FIX/fail-findmnt" ] || exit 1; [ ! -e "$FIX/fstypes" ] || cat "$FIX/fstypes"'
# paru authorizes through sudo and fails with 7 while $FIX/fail-paru exists,
# and with 130, as a Ctrl-C ends it, while $FIX/interrupt-paru does; while
# $FIX/conflict-paru does it exits 1 after pacman's conflict question,
# answered no, with the package versions faint as pacman colours them. Its -G
# saves each package under its base, the one $FIX/base-<package> names,
# else the package's own name, with a PKGBUILD, the files of
# $FIX/build-<base>, links kept as links, and a .SRCINFO of the base and
# the package when that holds none.
stub "$stubs" paru 'if [ "$1" = -G ]; then shift; for p; do
  b="$p"; [ ! -e "$FIX/base-$p" ] || read -r b <"$FIX/base-$p"
  mkdir -p "$b"; echo "pkgname=$p" >"$b/PKGBUILD"
  for f in "$FIX/build-$b"/* "$FIX/build-$b"/.SRCINFO; do
    if [ -L "$f" ]; then ln -sfn -- "$(readlink -- "$f")" "$b/${f##*/}"
    elif [ -e "$f" ]; then cat "$f" >"$b/${f##*/}"
    fi
  done
  [ -e "$b/.SRCINFO" ] || printf "pkgbase = %s\n\npkgname = %s\n" "$b" "$p" >"$b/.SRCINFO"
done; exit 0; fi
[ ! -e "$FIX/transaction" ] || "$FIX/transaction" "${0##*/}" "$@" || exit "$?"
[ ! -e "$FIX/pkgver-paru" ] || { printf "==> ERROR: A failure occurred in pkgver().\n    Aborting...\n" >&2; exit 4; }
[ ! -e "$FIX/conflict-paru" ] || { printf "\033[1;34m::\033[0m quickshell-\033[2m0.3.1-1\033[0m and quickshell-git-\033[2mr120.g1a2b3c4-1\033[0m are in conflict. Remove quickshell-git? [y/N] error: unresolvable package conflicts detected\nerror: failed to prepare transaction (conflicting dependencies)\n" >&2; exit 1; }
[ ! -e "$FIX/interrupt-paru" ] || { sudo /usr/bin/true; exit 130; }
[ ! -e "$FIX/fail-paru" ] || { sudo /usr/bin/true; exit 7; }'
stub "$stubs" git '[ ! -e "$FIX/fail-helper-git" ] || exit 6
for dest; do :; done
mkdir -p -- "$dest"
printf "%s\n" "$dest" >"$FIX/helper-build"'
stub "$stubs" makepkg '[ ! -e "$FIX/fail-helper-makepkg" ] || exit 8'
stub "$stubs" less ''
for tool in bash env readlink dirname mkdir chmod mv rm cp date script flock sleep cat id sed tee diff ln stty mktemp stat tail head timeout grep awk; do
  found="$(command -v "$tool")" || { echo "test-updates-pipeline: status=not-measured missing=$tool"; exit 77; }
  ln -s -- "$(readlink -f -- "$found")" "$tools/$tool"
done
ln -s -- "$node_bin" "$tools/node"

replaced_binary "$tmp/Hyprland"
# shellcheck disable=SC2154 # replaced_binary sets it
hyprland_pid="$replaced_pid"

settings() { # AUR_COMMAND TRUST
  printf '{"intervalHours":6,"hideWhenCurrent":false,"aurCommand":"%s","snapshot":"auto","trustPluginUpdates":%s,"placement":"center"}\n' "$1" "$2" >"$fix/settings.json"
}
# The status `vgshell self status --json` prints: a STEP other than none, or
# a REASON, is behind.
self_json() { # METHOD PACKAGE_JSON STEP [REASON]
  local behind=true reason=null
  [[ -z ${4:-} ]] || reason="\"$4\""
  [[ $3 != none || -n ${4:-} ]] || behind=false
  printf '{"version":"0.1.0","method":"%s","package":%s,"current":"0.1.0.r1.gabc1234","latest":"b","behind":%s,"step":"%s","reason":%s,"error":null}\n' "$1" "$2" "$behind" "$3" "$reason" >"$fix/self.json"
}
# The fixture every row starts from: pacman with the AUR through paru,
# Flatpak and mise; a checkout one commit behind; one plugin and one theme
# behind; no snapshot tool, no orphan, no replaced Hyprland, no package
# upgraded, every answer yes.
reset_fix() {
  rm -rf -- "${fix:?}" "$state/vgshell"
  mkdir -p "$fix" "$tmp/home/.config/paru" "$rt/hypr/session"
  printf '%s\nwayland-test\n' "$$" >"$rt/hypr/session/hyprland.lock"
  printf "[options]\n" >"$tmp/home/.config/paru/paru.conf"
  printf 'linux 6.1-1\nmesa 24.1-1\nvgshell-git 0.1.0.r1-1\n' >"$fix/installed"
  settings "" false
  echo sudo >"$fix/elevator"
  printf '{"primary":{"id":"pacman","binary":"pacman"},"overlays":[{"id":"aur","binary":"paru"},{"id":"flatpak","binary":"flatpak"}],"sources":[{"id":"mise","binary":"mise"}]}\n' >"$fix/detect.json"
  self_json checkout null self
  printf '[{"id":"acme.one","behind":2,"head":"h","upstream":"u","error":null},{"id":"acme.two","behind":0,"head":"h","upstream":"h","error":null}]\n' >"$fix/plugins.json"
  printf '[{"id":"night","behind":1,"head":"h","upstream":"u","error":null}]\n' >"$fix/themes.json"
}

# The [Trigger] of CachyOS's reboot hook, cachyos-hooks'
# /usr/share/libalpm/hooks/cachyos-reboot-required.hook, under the RootDir
# the stand-in pacman-conf names.
reboot_hook() {
  mkdir -p "$fix/root/usr/share/libalpm/hooks"
  cat >"$fix/root/usr/share/libalpm/hooks/cachyos-reboot-required.hook" <<'HOOK'
[Trigger]
Operation = Upgrade
Type = Package
Target = amd-ucode
Target = intel-ucode
Target = btrfs-progs
Target = e2fsprogs
Target = xfsprogs
Target = cryptsetup
Target = linux
Target = linux-hardened
Target = linux-lts
Target = linux-zen
Target = linux-firmware
Target = linux-cachyos*
Target = linux-cacule*
Target = nvidia
Target = nvidia-dkms
Target = nvidia-*xx-dkms
Target = nvidia-*xx
Target = nvidia-*lts-dkms
Target = nvidia*-lts
Target = mesa
Target = systemd*
Target = wayland
Target = egl-wayland
Target = xf86-video-*
Target = xorg-server*
Target = xorg-fonts*
Target = mkinitcpio*
Target = booster*
Target = dracut*
Target = winesync-dkms
HOOK
}

# pipeline SCRIPT ARG...: the plugin copy $PLUGIN, else $plugin, runs
# tui/SCRIPT on a pseudo-terminal; its output in $tmp/out, the exit status
# in $status, and the calls, but for the free-space and reboot probes and
# the plan box, in $tmp/seq. PIPE_PATH puts a directory before the stubs.
pipeline() {
  local script_path="${PLUGIN:-$plugin}/tui/$1" bound=()
  shift
  : >"$calls"
  status=0
  [[ -z ${PIPE_DEADLINE:-} ]] || bound=(timeout "$PIPE_DEADLINE")
  "${base_env[@]}" PATH="${PIPE_PATH:+$PIPE_PATH:}$stubs:$tools" VGS_TUI_LIB="$tree/bin/lib/tui.sh" VGS_PLUGIN_ID=vgs.updates VGS_PLUGIN_DIR="${PLUGIN:-$plugin}" \
    XDG_STATE_HOME="$state" XDG_RUNTIME_DIR="$rt" HYPRLAND_INSTANCE_SIGNATURE=session CALLS="$calls" FIX="$fix" TERMINAL_OUT="$tmp/out" UPDATES_TEST_SECONDARY="${UPDATES_TEST_SECONDARY:-0}" \
    "${bound[@]}" script -qec "$(printf '%q ' "$tools/stty" cols "${PIPE_COLUMNS:-80}") && $(printf '%q ' "$BASH" "$script_path" "$@")" /dev/null <"$tmp/terminal-input" {terminal_input}>&- >"$tmp/out" 2>&1 || status=$?
  local filtered=0
  grep -v -e '^df ' -e '^uname ' -e '^gum style' -e '^flock ' -e '^sleep ' -e '^pacman-conf --config ' -e '^yay --show ' -e '^vgshell pkg review'  -e '^$' -e $'^\e\\[22m' "$calls" |
    sed -E "s/ --review-receipt [^ ]+//g; s/ --config [^ ]+\/transaction-[^ ]+\/[^ ]+\.conf//g; s/ ${confirm_margins[*]}//" >"$tmp/seq" || filtered=$?
  # grep -v exits 1 when every call is filtered out, and above 1 when it failed.
  [[ $filtered -le 1 ]] || { echo "test-updates-pipeline: calls=unreadable exit=$filtered" >&2; exit 1; }
}
seq_is() { [[ "$(cat "$tmp/seq")" == "$(printf '%s\n' "$@")" ]]; } # LINE...
has_call() { grep -qxF -- "$1" "$tmp/seq"; }
no_call() { ! grep -q -- "^$1" "$tmp/seq"; } # PREFIX
# Whether no call starting with PREFIX comes before the first call
# starting with LINE, which is there.
none_before() { # PREFIX LINE
  local l
  grep -q -- "^$2" "$tmp/seq" || return 1
  while IFS= read -r l; do
    [[ $l != "$2"* ]] || return 0
    [[ $l != "$1"* ]] || return 1
  done <"$tmp/seq"
}
diag_has() { grep -qxF -- "$1" "$state/vgshell/updates/diagnostics.log" 2>/dev/null; }
out_has() { grep -qF -- "$1" "$tmp/out"; }
out_lacks() { ! grep -qF -- "$1" "$tmp/out"; }
# Text assertions read only the final result. row_failed_end separately
# checks the physical lines, widths, word boundaries and hanging indents.
result_has() {
  python3 - "$tmp/out" "$1" <<'PY'
import pathlib
import re
import sys

raw = pathlib.Path(sys.argv[1]).read_text()
assert "Update result" in raw, "end block missing"
raw_end = raw.rsplit("Update result", 1)[1].split("\n", 1)[1]
for line in raw_end.splitlines():
    plain = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", line)
    if re.match(r"^ +[0-9]+ of [0-9]+ parts failed$", plain):
        break
    assert "\x1b" not in line, ("tool colour in result", line)
text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", raw)
assert "Update result\n" in text, "end block missing"
end = text.rsplit("Update result\n", 1)[1]
assert sys.argv[2] in " ".join(end.split()), (sys.argv[2], end)
PY
}
# Whether the first call A comes before the last call B.
before() { # A B
  local lines i a="" b=""
  mapfile -t lines <"$tmp/seq"
  for i in "${!lines[@]}"; do
    [[ -z $a && ${lines[i]} == "$1" ]] && a="$i"
    [[ ${lines[i]} == "$2" ]] && b="$i"
  done
  [[ -n $a && -n $b && $a -lt $b ]]
}

# assert NAME CMD...: an ok or FAIL line unless QUIET=1; a failure adds to
# $red either way.
red=0
assert() {
  local name="$1"
  shift
  if "$@"; then [[ ${QUIET:-0} == 1 ]] || ok "$name"
  else red=$((red + 1)); [[ ${QUIET:-0} == 1 ]] || fail "$name"
  fi
}

# The whole run, in order: the reads, the question, the sudo session, VGS,
# the system, Flatpak, mise, the plugin and the theme, the session's end,
# the AUR, the drop after it, the orphans. No snapshot tool is 127: no
# warning, and the run goes on.
full_seq=("vgshell plugin settings vgs.updates" "vgshell pkg detect --json" "vgshell self status --json"
  "vgshell pkg plan upgrade pacman" "vgshell pkg plan upgrade flatpak" "vgshell pkg plan upgrade mise" "vgshell pkg plan upgrade aur"
  "vgshell plugin outdated --json" "vgshell theme outdated --json" "gum confirm -- Start the update?"
  "vgshell pkg owner $tree/VERSION" "sudo -k" "sudo /usr/bin/true" "pacman -Q" "vgshell self update"
  "vgshell pkg run upgrade --manager pacman" "vgshell pkg run upgrade --manager flatpak" "vgshell pkg run upgrade --manager mise"
  "vgshell plugin update acme.one" "vgshell theme update night" "sudo -k"
  "vgshell pkg run upgrade --manager aur" "sudo -k" "pacman -Q" "pacman -Qtdq" "vgshell ipc call vgs.updates invoke check ")
row_full() {
  reset_fix
  pipeline update.sh
  assert "a full run exits 0" test "$status" == 0
  assert "a full run takes every step in order, the AUR after the session ends" seq_is "${full_seq[@]}"
  assert "a plugin update gets no --yes by default" has_call "vgshell plugin update acme.one"
  assert "a finished run asks the service for one check" test "$(grep -cxF "vgshell ipc call vgs.updates invoke check " "$tmp/seq")" == 1
  assert "no snapshot tool warns nothing" out_lacks "snapshot=failed"
  assert "no snapshot tool keeps the update going quietly" out_lacks "without a snapshot"
  assert "the log keeps the plan box" grep -qF "Update everything" "$log"
  assert "a full run lists each source installed" result_has "System installed."
  assert "a full run lists each plugin installed" result_has "Plugin acme.one installed."
  assert "nothing core upgraded asks no reboot" no_call "gum confirm --affirmative=Reboot"
  touch "$fix/decline-acme.one"
  pipeline update.sh
  assert "a declined plugin update leaves the exit 0" test "$status" == 0
  assert "a declined plugin update reads skipped" result_has "Plugin acme.one skipped. You declined it."
  assert "a declined plugin update leaves the theme update to run" has_call "vgshell theme update night"
}
row_trusted() {
  reset_fix
  settings "" true
  pipeline update.sh
  assert "trustPluginUpdates passes --yes to the plugin update" has_call "vgshell plugin update --yes acme.one"
  assert "trustPluginUpdates passes --yes to the theme update" has_call "vgshell theme update --yes night"
}
row_snapshot() {
  reset_fix
  PIPE_PATH="$snapper_dir" pipeline update.sh
  assert "a snapper configuration takes a snapshot inside the session" before "sudo /usr/bin/true" "sudo snapper -c root create -c number -d VGS update"
  assert "the snapshot comes before VGS" before "sudo snapper -c root cleanup number" "vgshell self update"
  touch "$fix/fail-snapper"
  PIPE_PATH="$snapper_dir" pipeline update.sh
  assert "a failed snapshot warns" out_has "The snapshot failed."
  assert "a failed snapshot does not stop the update" has_call "vgshell pkg run upgrade --manager pacman"
  assert "a failed snapshot leaves the exit 0" test "$status" == 0
}
# A failed source records its cause and the run goes on with every later
# source; the result list follows the reboot question, and the run
# exits 1.
row_failure() {
  reset_fix
  reboot_hook
  touch "$fix/fail-mise"
  printf 'linux 6.2-1\nmesa 24.1-1\nvgshell-git 0.1.0.r1-1\n' >"$fix/installed-after"
  pipeline update.sh
  assert "a failed source ends the run with 1" test "$status" == 1
  assert "the plugin update runs after the failed source" before "vgshell pkg run upgrade --manager mise" "vgshell plugin update acme.one"
  assert "the AUR runs after the failed source" before "vgshell pkg run upgrade --manager mise" "vgshell pkg run upgrade --manager aur"
  assert "the result list names the failed source with its cause line" result_has "mise failed. error: failed to install crush."
  assert "an unknown cause gives a next step and the log button" result_has "Next: update again; if it fails again, the log names the cause. Select Open last log in Updates."
  assert "the result list names the later source installed" result_has "AUR installed."
  assert "the failure stays in the developer log" diag_has "updates: failed source=mise exit=9"
  assert "a failed source asks the service for one check" test "$(grep -cxF "vgshell ipc call vgs.updates invoke check " "$tmp/seq")" == 1
  assert "a failed source is not a stopped run" out_lacks "The update stopped."
  assert "a failed source still asks to reboot after an upgraded kernel" has_call "gum confirm --affirmative=Reboot --negative=Later --default=false -- The run updated linux, which takes effect after a reboot. Reboot now?"
}
# A failed theme change and AUR build skip the VGS rebuild and leave one
# end block after the shell restart and reboot answer. These wording
# assertions are the issue's explicit acceptance, including its control.
row_failed_end() {
  local columns
  for columns in 60 80; do
    reset_fix
    reboot_hook
    self_json package '"vgshell-git"' rebuild
    printf '[{"id":"tokyo-night","behind":1,"head":"h","upstream":"u","error":null}]\n' >"$fix/themes.json"
    touch "$fix/busy-tokyo-night" "$fix/build-aur" "$fix/owner" "$fix/owner-changes" "$fix/running"
    printf 'linux 6.2-1\nmesa 24.1-1\nvgshell-git 0.1.0.r2-1\n' >"$fix/installed-after"
    echo 1 >"$fix/answer-reboot"
    PIPE_COLUMNS="$columns" pipeline update.sh
    assert "two failed parts keep the failure exit" test "$status" == 1
    assert "two failed parts still recheck before the reboot answer" none_before "gum confirm --affirmative=Reboot" "vgshell ipc call vgs.updates invoke check "
    assert "the final block wraps sentences and aligns every line at $columns columns" python3 - "$tmp/out" "$columns" <<'PY'
import pathlib
import re
import sys

text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", pathlib.Path(sys.argv[1]).read_text()).replace("\r", "")
columns = int(sys.argv[2])
indent = 3
start = text.rfind("Update result\n")
assert start >= 0, "end block missing"
assert text.index("Restarting the shell on the updated VGS") < start
assert text.index("Reboot later to run the updated system.") < start
end = text[start:]
lines = end.splitlines()[1:]
for line in lines:
    assert len(line) <= columns - indent, (columns, len(line), line)
count = lines.index(" " * indent + "2 of 7 parts failed")
results = {}
part = None
for line in lines[:count]:
    match = re.match(r"^ {3}(\S.*?) (installed|skipped|failed)\.", line)
    if match:
        part = match[1]
        assert part not in results, (part, lines)
        results[part] = [line[indent:]]
    else:
        assert part is not None, line
        hanging = indent + len(part) + 1
        assert line.startswith(" " * hanging) and not line[hanging:].startswith(" "), (part, hanging, line)
        results[part].append(line[hanging:])
expected = {
    "System": "System installed.",
    "Flatpak": "Flatpak installed.",
    "mise": "mise installed.",
    "Plugin acme.one": "Plugin acme.one installed.",
    "Theme tokyo-night": "Theme tokyo-night failed. Another theme change is still running. Next: wait for it to finish, then update again from the Updates panel.",
    "VGS package": None,
    "AUR packages": "AUR packages failed. A package could not be built. Next: update again from the Updates panel.",
}
assert results.keys() == expected.keys(), results
for part, sentence in expected.items():
    if sentence is None:
        assert results[part][0].startswith("VGS package skipped."), results[part]
        continue
    assert " ".join(results[part]) == sentence, (part, results[part])
    if " failed. " in sentence:
        assert len(results[part]) > 1, (part, results[part])
summary = lines[count + 1:]
assert summary[0].startswith(" " * indent + "Failed parts: "), summary
hanging = indent + len("Failed parts: ")
for line in summary[1:]:
    assert line.startswith(" " * hanging) and not line[hanging:].startswith(" "), (hanging, line)
assert " ".join(line.strip() for line in summary) == "Failed parts: Theme tokyo-night, AUR packages", summary
assert "pkgver()" not in end and "theme lock" not in end and "Aborting" not in end, end
PY
  done
}
# The cause line VGS's own refusals leave, and a step the user said no to.
# A fetch the plugin update refuses names git's message; `vgshell pkg
# run`'s closing refusal leaves its manager's line; a line printed after a
# question answered yes shares its line and is the cause alone; a question
# left unanswered on stderr, as a no leaves pacman's, reads skipped.
row_cause() {
  reset_fix
  touch "$fix/offline-acme.one"
  pipeline update.sh
  assert "an offline plugin update is listed with git's message" result_has "Plugin acme.one failed. fatal: unable to access https://example.org/acme.git/: Could not resolve host: example.org."
  assert "an offline plugin update ends the run with 1" test "$status" == 1
  reset_fix
  touch "$fix/rescan-flatpak"
  pipeline update.sh
  assert "pkg run's closing refusal leaves its manager's line as the cause" result_has "Flatpak failed. error: failed to commit transaction (conflicting files)."
  reset_fix
  touch "$fix/answered-flatpak"
  pipeline update.sh
  assert "a failure after a question answered yes is listed without the question" result_has "Flatpak failed. error: failed to commit transaction (conflicting files)."
  reset_fix
  touch "$fix/decline-pacman"
  pipeline update.sh
  assert "a system upgrade answered no reads skipped" result_has "System skipped. You declined it."
  assert "a system upgrade answered no leaves the exit 0" test "$status" == 0
  reset_fix
  touch "$fix/decline-rescan-pacman"
  pipeline update.sh
  assert "a question answered no before pkg run's closing refusal reads skipped" result_has "System skipped. You declined it."
}
# After a failed or declined system upgrade the AUR step and the vgshell-git
# rebuild build against the system it left, so they are skipped; every
# other source still runs.
row_system_failed() {
  reset_fix
  touch "$fix/fail-pacman"
  pipeline update.sh
  assert "a failed system upgrade ends the run with 1" test "$status" == 1
  assert "a failed system upgrade runs no AUR step" no_call "vgshell pkg run upgrade --manager aur"
  assert "a failed system upgrade lists the AUR skipped with its cause" result_has "AUR skipped. The system upgrade failed, and AUR packages build against it."
  assert "a later source installs after a failed system upgrade" result_has "mise installed."
  assert "a plugin updates after a failed system upgrade" result_has "Plugin acme.one installed."
  reset_fix
  self_json package '"vgshell-git"' rebuild
  touch "$fix/owner" "$fix/owner-changes" "$fix/running" "$fix/fail-pacman"
  pipeline update.sh
  assert "a failed system upgrade rebuilds no vgshell-git" no_call "vgshell pkg run reinstall --manager aur vgshell-git"
  assert "a failed system upgrade lists the rebuild skipped" result_has "VGS package skipped. The system upgrade failed, and AUR packages build against it."
  reset_fix
  self_json package '"vgshell-git"' rebuild
  touch "$fix/decline-pacman"
  pipeline update.sh
  assert "a declined system upgrade runs no AUR step" no_call "vgshell pkg run upgrade --manager aur"
  assert "a declined system upgrade rebuilds no VGS package" no_call "vgshell pkg run reinstall --manager aur vgshell-git"
  assert "a declined system upgrade lists the AUR skipped with its cause" result_has "AUR skipped. You declined the system upgrade, and AUR packages build against it."
  assert "a later source installs after a declined system upgrade" result_has "mise installed."
}
# The terminal shows pacman's question on its own line after its whole
# size summary, which it writes to stdout before the question on stderr,
# and the step keeps a terminal on stdin, stdout and stderr. The relay
# form runs the stand-in as sudo's use_pty runs pacman.
question_after_summary() {
  python3 - "$tmp/out" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_bytes().decode("utf-8", "replace")
text = re.sub(r"\x1b\][^\x07\x1b]*(\x07|\x1b\\)", "", text)
text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
lines = [re.sub(r"^.*\r", "", l.rstrip("\r")) for l in text.split("\n")]
summary = [i for i, l in enumerate(lines) if re.search(r"Total Download Size|Total Installed Size|Net Upgrade Size", l)]
question = [i for i, l in enumerate(lines) if "Proceed with installation?" in l]
assert len(summary) == 3 and len(question) == 1, (summary, question)
assert question[0] > max(summary), lines[min(summary + question):max(summary + question) + 1]
assert lines[question[0]].strip().startswith(":: Proceed with installation? [Y/n]"), lines[question[0]]
PY
}
row_order() {
  reset_fix
  touch "$fix/order-pacman"
  pipeline update-source.sh pacman
  assert "the question follows the size summary on its own line" question_after_summary
  assert "the step keeps a terminal on stdin, stdout and stderr" test "$(cat "$fix/terminals")" == 012
  assert "an unanswered question still reads declined" result_has "System skipped. You declined it."
  reset_fix
  touch "$fix/relay-pacman"
  pipeline update-source.sh pacman
  assert "through a relay like sudo's use_pty the question follows the summary" question_after_summary
  assert "through a relay the unanswered question reads declined" result_has "System skipped. You declined it."
}
# The terminal echoes the user's answer after the question; an answer of
# no, or Enter on a question whose default is no, reads declined.
answer() { # TEXT FIX_FILE: TEXT typed once the question shows
  local i=0
  : >"$tmp/out"
  (
    while (( i < 200 )) && ! grep -qE "Proceed with installation|Remove the old kernel" "$tmp/out"; do sleep 0.05; i=$((i + 1)); done
    printf '%s\r' "$1" >&"$terminal_input"
  ) &
  touch "$fix/$2"
  pipeline update-source.sh pacman
  wait "$!" || :
}
cause_file_has() { grep -qF -- "$1" "$state/vgshell/updates/.step-output"; } # TEXT
row_answer() {
  reset_fix
  answer n ask-pacman
  assert "a [Y/n] answered n reads declined" result_has "System skipped. You declined it."
  reset_fix
  answer '' ask-default-no-pacman
  assert "a [y/N] answered with Enter reads declined" result_has "System skipped. You declined it."
  reset_fix
  answer y ask-pacman
  assert "a [Y/n] answered y that fails reads failed" result_has "System packages failed."
}
# The cause is the error line, not stdout that follows it, and a cut the
# transcript cannot give is a stated cause with a keyed diagnostic.
row_cause_output() {
  reset_fix
  touch "$fix/faulted-mise"
  pipeline update.sh
  assert "an error line before stdout is the cause" result_has "mise failed. error: failed to commit transaction (conflicting files)."
  reset_fix
  touch "$fix/unprefixed-mise"
  pipeline update.sh
  assert "an unprefixed error line before the scan line is the cause" result_has "mise failed. mise ERROR Failed to install core:node@22.0.0."
  reset_fix
  touch "$fix/transcript-gone-mise"
  pipeline update.sh
  assert "a step whose output cannot be cut says so" result_has "mise failed. VGS could not read this step's output."
  assert "a cut that cannot run is keyed in the developer log" diag_has "updates: transcript=unread source=mise reason=absent"
  # The end mark goes to the file script(1) still writes, so the wait on
  # the new one ends at its ceiling.
  reset_fix
  touch "$fix/transcript-replaced-mise"
  pipeline update.sh
  assert "an end mark that never arrives says so" result_has "mise failed. VGS could not read this step's output."
  assert "an end mark that never arrives is keyed in the developer log" diag_has "updates: transcript=unread source=mise reason=late"
  assert "the run goes on after an end mark that never arrives" result_has "AUR installed."
}
# A read the reboot question needs that fails stays in the developer log
# and warns once.
row_reboot_unread() {
  reset_fix
  reboot_hook
  printf 'linux 6.2-1\nmesa 24.1-1\nvgshell-git 0.1.0.r1-1\n' >"$fix/installed-after"
  touch "$fix/fail-findmnt" "$fix/fail-rootdir"
  pipeline update.sh
  assert "a failed RootDir read stays in the developer log" diag_has "updates: reboot-hook=unread exit=1"
  assert "a failed mounts read stays in the developer log" diag_has "updates: mounts=unread exit=1"
  assert "two failed reboot reads warn once" test "$(grep -cF "Could not check which updates need a restart." "$tmp/out")" == 1
  assert "a failed reboot read leaves the run successful" test "$status" == 0
  reset_fix
  touch "$fix/fail-pacman-q"
  pipeline update.sh
  assert "a failed package list stays in the developer log" diag_has "updates: installed=unread when=before"
  assert "a failed package list warns" out_has "Could not check which updates need a restart."
}
# A step that fails outside the sources ends the run: the ERR trap prints
# the recovery message.
row_stopped() {
  reset_fix
  touch "$fix/fail-detect"
  pipeline update.sh
  assert "a failed read ends the run with its status" test "$status" == 5
  assert "a failed read asks the service for one check" test "$(grep -cxF "vgshell ipc call vgs.updates invoke check " "$tmp/seq")" == 1
  assert "a failed read names the log in its recovery message" out_has "Select Open last log in Updates to read this run's output."
  assert "the failure code stays in the developer log" grep -qsF "updates: failed exit=5" "$state/vgshell/updates/diagnostics.log"
  assert "a failed read runs no step" test "$(grep -c 'pkg run' "$tmp/seq")" == 0
}
# A Ctrl-C in a source step ends the run with 130 and drops the credential.
row_interrupted() {
  reset_fix
  touch "$fix/interrupt-pacman"
  pipeline update.sh
  assert "an interrupted step ends the run with 130" test "$status" == 130
  assert "an interrupted step runs no later source" no_call "vgshell pkg run upgrade --manager flatpak"
  assert "an interrupted step drops the credential last" test "$(tail -n 1 "$tmp/seq")" == "sudo -k"
}
row_reboot() {
  reset_fix
  printf '%s\nwayland-test\n' "$hyprland_pid" >"$rt/hypr/session/hyprland.lock"
  pipeline update.sh
  assert "a replaced Hyprland asks to reboot" has_call "gum confirm --affirmative=Reboot --negative=Later --default=false -- Hyprland was updated. Reboot now?"
  assert "a replaced Hyprland rechecks before it asks to reboot" before "vgshell ipc call vgs.updates invoke check " "gum confirm --affirmative=Reboot --negative=Later --default=false -- Hyprland was updated. Reboot now?"
  assert "a yes reboots" test "$(tail -n 1 "$tmp/seq")" == "vgshell power reboot"
  echo 1 >"$fix/answer-reboot"
  pipeline update.sh
  assert "a no does not reboot" test "$(grep -c '^systemctl' "$tmp/seq")" == 0
  assert "a no asks for no power action" no_call "vgshell power "
}
# The run's own upgrade list, pacman -Q before the first package step and
# after the last, judged by the CachyOS reboot hook's targets and its
# script's conditions.
row_reboot_core() {
  reset_fix
  reboot_hook
  printf 'linux 6.2-1\nlinux-headers 6.2-1\nmesa 24.1-1\nvgshell-git 0.1.0.r1-1\n' >"$fix/installed-after"
  pipeline update.sh
  assert "an upgraded kernel the hook names asks to reboot, naming it" has_call "gum confirm --affirmative=Reboot --negative=Later --default=false -- The run updated linux, which takes effect after a reboot. Reboot now?"
  assert "the installed packages are read before the first package step" before "pacman -Q" "vgshell pkg run upgrade --manager pacman"
  assert "the installed packages are read again after the last" before "vgshell pkg run upgrade --manager aur" "pacman -Q"
  assert "the hook is read under pacman's RootDir" has_call "pacman-conf RootDir"
  assert "a reboot asked after an upgraded kernel reboots on a yes" test "$(tail -n 1 "$tmp/seq")" == "vgshell power reboot"
  reset_fix
  reboot_hook
  printf 'linux 6.1-1\nmesa 24.1-1\nvgshell-git 0.1.0.r1-1\nfirefox 130-1\n' >"$fix/installed"
  printf 'linux 6.1-1\nmesa 24.1-1\nvgshell-git 0.1.0.r1-1\nfirefox 131-1\nfoo 1-1\n' >"$fix/installed-after"
  pipeline update.sh
  assert "nothing the hook names upgraded asks no reboot" no_call "gum confirm --affirmative=Reboot"
  # A new package the hook names is no upgrade, which its trigger lists.
  reset_fix
  reboot_hook
  printf 'linux 6.1-1\nlinux-lts 6.6-1\nmesa 24.1-1\nvgshell-git 0.1.0.r1-1\n' >"$fix/installed-after"
  pipeline update.sh
  assert "a new kernel package asks no reboot" no_call "gum confirm --affirmative=Reboot"
  # A file system tool needs a reboot only while its file system is mounted.
  reset_fix
  reboot_hook
  printf 'linux 6.1-1\nmesa 24.1-1\nvgshell-git 0.1.0.r1-1\nbtrfs-progs 6.10-1\n' >"$fix/installed"
  printf 'linux 6.1-1\nmesa 24.1-1\nvgshell-git 0.1.0.r1-1\nbtrfs-progs 6.11-1\n' >"$fix/installed-after"
  printf 'ext4\ntmpfs\n' >"$fix/fstypes"
  pipeline update.sh
  assert "btrfs-progs with no btrfs mounted asks no reboot" no_call "gum confirm --affirmative=Reboot"
  printf 'btrfs\ntmpfs\n' >"$fix/fstypes"
  rm -f -- "${fix:?}/installed-asked"
  pipeline update.sh
  # The question is wider than the content edges of an 80-column terminal,
  # so its last word goes on a line of its own.
  assert "btrfs-progs with btrfs mounted asks to reboot" has_call "gum confirm --affirmative=Reboot --negative=Later --default=false -- The run updated btrfs-progs, which takes effect after a reboot. Reboot"
  assert "the btrfs-progs reboot question ends on its wrapped line" has_call "now?"
  # Without the hook no package needs a reboot.
  reset_fix
  printf 'linux 6.2-1\nmesa 24.1-1\nvgshell-git 0.1.0.r1-1\n' >"$fix/installed-after"
  pipeline update.sh
  assert "an upgraded kernel without the hook asks no reboot" no_call "gum confirm --affirmative=Reboot"
  assert "a run without the hook ends successfully" test "$status" == 0
  # A hook bin/facts cannot read is logged, and the run still ends.
  reset_fix
  reboot_hook
  chmod 000 "$fix/root/usr/share/libalpm/hooks/cachyos-reboot-required.hook"
  printf 'linux 6.2-1\nmesa 24.1-1\nvgshell-git 0.1.0.r1-1\n' >"$fix/installed-after"
  pipeline update.sh
  assert "an unreadable hook is logged" diag_has "updates: reboot-packages=failed exit=1"
  assert "an unreadable hook leaves the run successful" test "$status" == 0
  assert "an unreadable hook asks no reboot" no_call "gum confirm --affirmative=Reboot"
}
row_orphans() {
  reset_fix
  printf 'foo\nbar\n' >"$fix/orphans"
  echo 1 >"$fix/answer-orphans"
  pipeline update.sh
  assert "orphans are asked about, default no" has_call "gum confirm --default=false -- Remove 2 orphaned package(s)?"
  assert "a no removes no orphan" test "$(grep -c 'pkg run remove' "$tmp/seq")" == 0
  rm -f -- "$fix/answer-orphans"
  pipeline update.sh
  assert "a yes removes the orphans through the package table" has_call "vgshell pkg run remove --manager pacman foo bar"
}
row_yes() {
  reset_fix
  printf 'foo\n' >"$fix/orphans"
  pipeline update.sh -y
  assert "-y asks no start question" test "$(grep -c 'Start the update' "$tmp/seq")" == 0
  assert "-y reports orphans instead of asking" test "$(grep -c 'orphaned' "$tmp/seq")" == 0
  assert "-y still runs the system step" has_call "vgshell pkg run upgrade --manager pacman"
}
row_recheck_failure() {
  reset_fix
  touch "$fix/ipc-check-refuses"
  pipeline update-source.sh flatpak
  assert "a refused recheck leaves a successful run successful" test "$status" == 0
  assert "a refused recheck is kept in diagnostics" diag_has "updates: recheck=failed exit=8 reply=refused: ipc=check reason=test"
  assert "a refused recheck still reaches the reboot check" grep -qxF "uname -r" "$calls"
}
# A package transaction replaces the command tree. The restarted core is
# ready before its Updates service, as ServiceGate permits. The first call
# observes the missing target; its completion releases the fixture's
# registration barrier, and the next call reaches the new service.
row_recheck_replaced_tree() {
  reset_fix
  settings "" false false
  self_json package '"vgshell-git"' rebuild
  touch "$fix/owner" "$fix/owner-changes" "$fix/running"
  ln -s -- "$repo/bin/vgshell" "$fix/real-ipc"
  printf '%s\n' "$$" >"$rt/vgshell.lock"
  local replacement="$tmp/tree-next" previous="$tmp/tree-previous"
  cp -R -- "$tree" "$replacement"
  {
    printf '#!%s\n' "$BASH"
    printf '[[ ! -e %q ]] || exit 0\n' "$fix/tree-replaced"
    printf 'mv -- %q %q\nmv -- %q %q\n' "$tree" "$previous" "$replacement" "$tree"
    printf ': >%q\n: >%q\n' "$fix/tree-replaced" "$fix/ipc-check-pending"
  } >"$fix/transaction"
  chmod +x "$fix/transaction"
  pipeline update.sh
  assert "the package transaction replaced the command tree" test -d "$previous"
  assert "the replacement run restarts the shell" has_call "vgshell restart"
  assert "the recheck reaches the replacement's Updates service" has_call "updates-target-reached"
  assert "a missing target during registration is not a failed recheck" test ! -e "$state/vgshell/updates/diagnostics.log"
  rm -rf -- "${tree:?}"
  mv -- "$previous" "$tree"
}

# The CLI distinguishes a missing service, an unavailable instance and a
# rejected request. Fake sleep advances only the startup wait, not a clock
# in the product; the persistent case must consume its existing ceiling.
row_recheck_cli() {
  local reply pending expected
  while IFS='|' read -r reply pending expected; do
    reset_fix
    ln -s -- "$repo/bin/vgshell" "$fix/real-ipc"
    printf '%s\n' "$$" >"$rt/vgshell.lock"
    touch "$fix/fast-sleep"
    [[ -z $reply ]] || printf '%s\n' "$reply" >"$fix/qs-reply"
    [[ $pending != persistent ]] || touch "$fix/ipc-check-pending" "$fix/ipc-persistent"
    PIPE_DEADLINE=20 pipeline update-source.sh flatpak
    assert "the recheck finishes its CLI response class" test "$status" == 0
    assert "the CLI class makes only its allowed calls" test "$(grep -c '^qs ipc ' "$calls")" == "$expected"
    assert "a refused CLI response retains a diagnostic" grep -q '^updates: recheck=failed exit=69 ' "$state/vgshell/updates/diagnostics.log"
  done <<'ROWS'
Function not found.||1
|persistent|301
ROWS
}
row_declined() {
  reset_fix
  echo 1 >"$fix/answer-start"
  pipeline update.sh
  assert "a declined start exits 0" test "$status" == 0
  assert "a declined start runs nothing" test "$(grep -c -e '^sudo' -e 'pkg run' "$tmp/seq")" == 0
}
row_busy() {
  reset_fix
  mkdir -p "$state/vgshell/updates"
  printf 'earlier run\n' >"$log"
  # This suite's own shell holds the lock, so closing its descriptor frees it.
  local held
  exec {held}>>"$rt/vgs-tui-updates.lock"
  flock -n "$held"
  pipeline update.sh
  exec {held}>&-
  assert "a second run is refused busy" test "$status" == 75
  assert "a busy run leaves the running run's log" test "$(cat "$log")" == "earlier run"
  assert "a busy run asks vgshell nothing" test ! -s "$tmp/seq"
}
row_aur_command() {
  reset_fix
  settings "paru -Sua --devel" false
  pipeline update.sh
  assert "aurCommand replaces the table's AUR plan" test "$(grep -c 'plan upgrade aur' "$tmp/seq")" == 0
  assert "aurCommand runs after the session ends" before "vgshell theme update night" "paru -Sua --devel"
}
# An AUR helper that caches a sudo credential and then fails still has it
# dropped, after it; with no line on stderr its cause is its status. One a
# Ctrl-C ends has it dropped as the run exits.
row_aur_failure() {
  reset_fix
  settings "paru -Sua --devel" false
  touch "$fix/fail-paru"
  pipeline update.sh
  assert "a failed AUR step ends the run with 1" test "$status" == 1
  assert "a failed AUR step with no stderr is listed with its status" result_has "AUR packages failed. exit 7."
  assert "the credential is dropped after the failed AUR step" before "paru -Sua --devel" "sudo -k"
  rm -f -- "${fix:?}/fail-paru"
  touch "$fix/interrupt-paru"
  pipeline update.sh
  assert "an interrupted AUR step ends the run with 130" test "$status" == 130
  assert "an interrupted AUR step drops the credential it cached, last" test "$(tail -n 1 "$tmp/seq")" == "sudo -k"
}
# Paru's review refusal exits 1 at the question; yay's review refusal exits
# 1 after ErrUserAbort prints its cause. Neither may retry the declined
# engine as a dependency of a separate VGS rebuild, through either route.
row_aur_rebuild_stopped() {
  local route ending outcome expected aur_call
  while read -r route ending outcome expected; do
    reset_fix
    self_json package '"vgshell-git"' rebuild
    aur_call="vgshell pkg run upgrade --manager aur"
    if [[ $route == custom ]]; then settings "paru -Sua --devel" false; aur_call="paru -Sua --devel"; fi
    printf '%s\n' "$ending" >"$fix/review-ending"
    cat >"$fix/transaction" <<'SH'
#!/bin/sh
case "$1" in
  aur|paru)
    read -r ending <"$FIX/review-ending"
    printf 'Aur (3) agent-browser-bin vgshell-quickshell vsys-git\n'
    if [ "$ending" = paru ]; then printf ':: Proceed to review? [Y/n]: n\n'
    else printf ':: Proceed with install? [Y/n] n\naborting due to user\n'
    fi
    exit 1 ;;
esac
SH
    chmod +x "$fix/transaction"
    pipeline update.sh
    assert "$route $ending reports its original result" test "$status" == "$expected"
    assert "$route $ending does not re-offer the engine through VGS" no_call "vgshell pkg run reinstall --manager aur vgshell-git"
    assert "$route $ending records why the rebuild was skipped" diag_has "updates: skipped source=vgshell-git reason=aur-$outcome"
    assert "$route $ending drops credentials after the AUR" before "$aur_call" "sudo -k"
  done <<'ROWS'
table paru declined 0
custom paru declined 0
table yay failed 1
custom yay failed 1
ROWS
}
# packages.elevate names doas: sudo is installed but refuses, and the
# update runs through doas without a sudo session.
row_doas() {
  reset_fix
  echo doas >"$fix/elevator"
  touch "$fix/sudo-refuses"
  PIPE_PATH="$snapper_dir" pipeline update.sh
  assert "a doas update exits 0" test "$status" == 0
  assert "a doas update starts no sudo session" test "$(grep -c '^sudo /usr/bin/true' "$tmp/seq")" == 0
  assert "a doas update takes its snapshot through doas" has_call "doas snapper -c root create -c number -d VGS update"
  assert "a doas update names doas in the plan box" out_has "Snapshot: snapper through doas, first"
  assert "a doas update runs the system step" has_call "vgshell pkg run upgrade --manager pacman"
}
# update-source.sh vgs on a vgshell-git behind: the rebuild replaces the
# package, so a snapshot comes first and the running shell restarts on the
# new version, and no other package is upgraded.
row_vgs_only() {
  reset_fix
  self_json package '"vgshell-git"' rebuild
  touch "$fix/owner" "$fix/owner-changes" "$fix/running"
  PIPE_PATH="$snapper_dir" pipeline update-source.sh vgs
  assert "a VGS rebuild alone exits 0" test "$status" == 0
  assert "a VGS rebuild alone takes a snapshot before it" before "sudo snapper -c root create -c number -d VGS update" "vgshell pkg run reinstall --manager aur vgshell-git"
  assert "a VGS rebuild alone drops the credential after it" before "vgshell pkg run reinstall --manager aur vgshell-git" "sudo -k"
  assert "a VGS rebuild alone restarts the running shell" has_call "vgshell restart"
  assert "a VGS rebuild alone upgrades no other package" test "$(grep -c -e 'pkg run upgrade' -e '^pacman -[^Q]' "$tmp/seq")" == 0
}
# The new helper step runs through stand-ins only. Each failing producer
# prevents the following build and VGS rebuild, and scratch is removed.
row_vgs_helper() {
  local failure expected
  while read -r failure expected; do
    reset_fix
    self_json package '"vgshell-git"' install-helper
    printf '{"primary":{"id":"pacman","binary":"pacman"},"overlays":[],"sources":[]}\n' >"$fix/detect.json"
    [[ $failure == none ]] || touch "$fix/fail-$failure"
    pipeline update-source.sh vgs
    assert "helper $failure exits $expected" test "$status" == "$expected"
    assert "helper $failure installs prerequisites through package runner" has_call "vgshell pkg run install --manager pacman base-devel git"
    if [[ $failure == none ]]; then
      assert "helper success builds paru before VGS" before "makepkg -si" "vgshell pkg run reinstall --manager aur vgshell-git"
      assert "helper success clones the official AUR recipe" grep -q '^git clone -- https://aur.archlinux.org/paru.git ' "$tmp/seq"
    else
      assert "helper $failure prevents VGS rebuild" no_call "vgshell pkg run reinstall --manager aur vgshell-git"
    fi
    if [[ -f $fix/helper-build ]]; then
      assert "helper $failure removes its build directory" test ! -e "$(cat "$fix/helper-build")"
    fi
  done <<'ROWS'
none 0
pacman 1
helper-git 1
helper-makepkg 1
ROWS
  reset_fix
  self_json package '"vgshell-git"' install-helper
  pipeline update-source.sh vgs
  assert "a helper found since status skips installation" no_call "vgshell pkg run install --manager pacman base-devel git"
  assert "a helper found since status rebuilds VGS" has_call "vgshell pkg run reinstall --manager aur vgshell-git"
}
row_vgs_git() {
  reset_fix
  self_json package '"vgshell-git"' rebuild
  touch "$fix/owner" "$fix/owner-changes" "$fix/running"
  pipeline update.sh
  assert "a package tree runs no self update" test "$(grep -c 'self update' "$tmp/seq")" == 0
  assert "a behind vgshell-git is rebuilt after the AUR" before "vgshell pkg run upgrade --manager aur" "vgshell pkg run reinstall --manager aur vgshell-git"
  assert "the credential is dropped after the rebuild" before "vgshell pkg run reinstall --manager aur vgshell-git" "sudo -k"
  assert "a replaced VGS package restarts the running shell" has_call "vgshell restart"
}
# The step the status names is what runs. A step of none, whatever its
# reason, and a status that could not check run no self update and no
# rebuild, though the AUR helper or an aurCommand is here. The plan box
# names what updates VGS: with no AUR helper, the aurCommand words update
# the release `vgshell` package and cannot rebuild `vgshell-git`. HELPER
# empty drops paru from `pkg detect`.
row_vgs_step() {
  local method package reason helper aur plan name
  while IFS='|' read -r method package reason helper aur plan; do
    reset_fix
    self_json "$method" "$package" none "$reason"
    [[ -n $helper ]] || printf '{"primary":{"id":"pacman","binary":"pacman"},"overlays":[],"sources":[]}\n' >"$fix/detect.json"
    settings "$aur" false
    name="step none ${reason:-current} on $method $package, helper ${helper:-none}, aurCommand ${aur:-none},"
    PIPE_COLUMNS=200 pipeline update-source.sh vgs
    assert "$name exits 0" test "$status" == 0
    assert "$name runs no self update" no_call "vgshell self update"
    assert "$name rebuilds nothing" no_call "vgshell pkg run reinstall --manager aur"
    assert "$name plans its reason" out_has "$plan"
  done <<'ROWS'
package|"vgshell-git"||paru||VGS: current
package|"vgshell"|no-aur-helper|||VGS: the vgshell package is behind, and no AUR helper is here to update it
package|"vgshell"|no-aur-helper||pikaur -Sua|VGS: the vgshell package updates with its package manager
package|"vgshell"|package-manager|paru||VGS: the vgshell package updates with its package manager
nix|null|nix|paru||VGS: its flake updates it
checkout|null||paru||VGS: current
ROWS
  reset_fix
  printf '{"version":"0.1.0","method":"package","package":"vgshell-git","current":"0.1.0.r1.gabc1234","latest":null,"behind":null,"step":null,"reason":null,"error":"compare=http status=404 url=x"}\n' >"$fix/self.json"
  pipeline update-source.sh vgs
  assert "a status that could not check exits 0" test "$status" == 0
  assert "a status that could not check rebuilds nothing" no_call "vgshell pkg run reinstall --manager aur"
  assert "a status that could not check keeps its error in the developer log" diag_has "VGS: compare=http status=404 url=x"
}
# A rebuild that fails writes its record: the installed version the status
# named, the helper, its exit and the package pacman's conflict line names
# first, without its version, or null with no such line. The next rebuild
# that succeeds leaves none.
row_rebuild_failed() {
  local record="$state/vgshell/updates/rebuild-failed.json"
  reset_fix
  self_json package '"vgshell-git"' rebuild
  touch "$fix/conflict-paru"
  pipeline update-source.sh vgs
  assert "a rebuild the helper fails ends the run with 1" test "$status" == 1
  assert "a conflicting rebuild records its exit and the first conflicting package" json_is "$record" \
    'd == {"current": "0.1.0.r1.gabc1234", "helper": "paru", "exit": 1, "conflict": "quickshell"}'
  assert "the record leaves no partial file" test ! -e "$record.part"
  mv -- "${fix:?}/conflict-paru" "${fix:?}/pkgver-paru"
  pipeline update-source.sh vgs
  assert "a rebuild that fails with no conflict line records a null conflict" json_is "$record" \
    'd == {"current": "0.1.0.r1.gabc1234", "helper": "paru", "exit": 4, "conflict": None}'
  mv -- "${fix:?}/pkgver-paru" "${fix:?}/passed-paru"
  pipeline update-source.sh vgs
  assert "a rebuild that succeeds exits 0" test "$status" == 0
  assert "a rebuild that succeeds leaves no record" test ! -e "$record"
}
row_source() {
  reset_fix
  pipeline update-source.sh flatpak
  assert "one source runs its step alone" seq_is \
    "vgshell plugin settings vgs.updates" "vgshell pkg detect --json" "vgshell pkg plan upgrade flatpak" \
    "gum confirm -- Start the update?" "vgshell pkg run upgrade --manager flatpak" "vgshell ipc call vgs.updates invoke check "
  pipeline update-source.sh aur
  assert "the AUR alone holds no session" test "$(grep -c '^sudo /usr/bin/true' "$tmp/seq")" == 0
  assert "the AUR alone drops the credential after it" before "vgshell pkg run upgrade --manager aur" "sudo -k"
  pipeline update-source.sh nope
  assert "an unknown source is refused" test "$status:$(head -n 1 "$tmp/out" | tr -d '\r')" == "2:This update request is invalid. Open Updates and try again."
  assert "an unknown source starts no update or authorization" seq_is \
    "vgshell plugin settings vgs.updates" "vgshell pkg detect --json"
  assert "an unknown source keeps its diagnostic in the developer log" grep -qxF \
    "updates: refused: source=nope reason=unknown" "$state/vgshell/updates/diagnostics.log"
  pipeline update-source.sh
  assert "a missing source is refused" test "$status:$(head -n 1 "$tmp/out" | tr -d '\r')" == "2:No update source was selected. Open Updates and choose a source."
}
# log_tui KEYS [ARG...]: tui/log.sh as `pipeline` runs a script, on a
# pseudo-terminal whose input stays open. With KEYS `yes` a key is typed
# every 0.2 s, since the closing prompt drops keys queued within 0.1 s of
# each other as terminal replies; with `no` none is, and a run still
# waiting after 2 s is ended by timeout, exiting 124.
log_tui() {
  local keys="$1" script_path="${PLUGIN:-$plugin}/tui/log.sh" filtered=0 ceiling=10
  shift
  [[ $keys == yes ]] || ceiling=2
  : >"$calls"
  set +e
  { if [[ $keys == yes ]]; then while printf x; do sleep 0.2; done; else sleep 3; fi; } |
    timeout "$ceiling" "${base_env[@]}" PATH="$stubs:$tools" VGS_TUI_LIB="$tree/bin/lib/tui.sh" VGS_PLUGIN_ID=vgs.updates VGS_PLUGIN_DIR="${PLUGIN:-$plugin}" \
      XDG_STATE_HOME="$state" XDG_RUNTIME_DIR="$rt" CALLS="$calls" FIX="$fix" \
      script -qec "$(printf '%q ' "$BASH" "$script_path" "$@")" /dev/null >"$tmp/out" 2>&1
  status=${PIPESTATUS[1]}
  set -e
  grep -v -e '^df ' -e '^uname ' -e '^gum style' -e '^flock ' -e '^pacman-conf --config ' -e '^yay --show ' -e '^vgshell pkg review'  -e '^$' -e $'^\e\\[22m' "$calls" |
    sed -E "s/ --review-receipt [^ ]+//g; s/ --config [^ ]+\/transaction-[^ ]+\/[^ ]+\.conf//g; s/ ${confirm_margins[*]}//" >"$tmp/seq" || filtered=$?
  [[ $filtered -le 1 ]] || { echo "test-updates-pipeline: calls=unreadable exit=$filtered" >&2; exit 1; }
}
# The first line of the output, without the typed keys the terminal echoed
# before the script read any.
first_line() { head -n 1 "$tmp/out" | tr -d '\r' | sed -e 's/^x*//'; }
failed_prompt="The task failed. Press any key to close."
# tui/log.sh opens the log the pipeline wrote, at its end, and refuses
# before any run wrote one and without less. Its presentation is plain, so
# a refusal holds the window on the closing prompt until a key: with no key
# typed the run is still waiting at the ceiling.
row_log() {
  reset_fix
  log_tui yes
  assert "the log TUI before any run is refused" test "$status:$(first_line)" == "1:No update has run yet. There is no log to show."
  assert "the log TUI's refusal ends on the Failed prompt" out_has "$failed_prompt"
  assert "the log TUI before any run opens no pager" test ! -s "$tmp/seq"
  log_tui no
  assert "the log TUI holds its refusal until a key" test "$status:$(first_line)" == "124:No update has run yet. There is no log to show."
  assert "the held refusal shows the Failed prompt" out_has "$failed_prompt"
  pipeline update.sh
  mv -- "$stubs/less" "$tmp/less.off"
  log_tui no
  mv -- "$tmp/less.off" "$stubs/less"
  assert "the log TUI without less holds its refusal until a key" test "$status:$(first_line)" == "124:The log reader is unavailable. Open Updates to try again."
  assert "the held pager refusal shows the Failed prompt" out_has "$failed_prompt"
  log_tui yes
  assert "the log TUI opens the log the pipeline wrote, at its end" seq_is "less -R +G -- $log"
  assert "the log TUI exits with the pager's status" test "$status" == 0
  assert "the log TUI leaves the window to the pager with no prompt" out_lacks "Press any key"
  log_tui yes extra
  assert "the log TUI refuses an argument" test "$status:$(first_line)" == "2:This update request is invalid. Open Updates and try again."
}

# The transaction stand-in reads the emitted configuration and resolves
# same-name hooks from its directories. It emits a notice only when that
# lookup retains the distribution hook. The production reboot judge still
# reads the real fixture hook through bin/facts, independent of this stand-in.
transaction_fixture() {
  mkdir -p "$fix/hooks"
  printf 'unrelated\n' >"$fix/hooks/other.hook"
  printf 'notice\n' >"$fix/hooks/cachyos-reboot-required.hook"
  cat >"$fix/transaction" <<'JS'
#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const [step, ...args] = process.argv.slice(2);
const fix = process.env.FIX;
const at = args.indexOf('--config');
const config = at === -1 ? null : args[at + 1];
const calls = line => fs.appendFileSync(process.env.CALLS, line + '\n');
let dirs = [path.join(fix, 'hooks')];
if (config !== null) {
    const text = fs.readFileSync(config, 'utf8');
    fs.appendFileSync(path.join(fix, 'generated'), text);
    fs.appendFileSync(path.join(fix, 'scratch'), path.dirname(config) + '\n');
    dirs = text.split('\n').filter(line => line.startsWith('HookDir = ')).map(line => line.slice(10));
    if (dirs[0] !== path.join(fix, 'hooks')) process.exit(17);
    if ((fs.statSync(path.dirname(config)).mode & 0o777) !== 0o700) process.exit(18);
}
const hooks = new Map();
for (const dir of dirs) for (const name of fs.readdirSync(dir)) hooks.set(name, path.join(dir, name));
for (const [name, file] of hooks) {
    if (fs.lstatSync(file).isSymbolicLink() && fs.readlinkSync(file) === '/dev/null') continue;
    calls(name === 'cachyos-reboot-required.hook' ? 'notification reboot' : 'hook ' + name);
}
calls('transaction-ended ' + step);
JS
  chmod +x "$fix/transaction"
}
row_reboot_deferred() {
  reset_fix
  reboot_hook
  transaction_fixture
  settings "" false false
  printf 'linux 6.1-1\nmesa 24.2-1\nvgshell-git 0.1.0.r1-1\n' >"$fix/installed-after"
  pipeline update.sh
  assert "masked transactions finish successfully" test "$status" == 0
  assert "no package transaction sends an early reboot notice" no_call 'notification reboot'
  assert "custom hooks still run" has_call 'hook other.hook'
  assert "the final question waits for the AUR transaction" none_before 'gum confirm --affirmative=Reboot' 'transaction-ended aur'
  assert "the original hook still identifies the changed mesa package" has_call 'reboot-package mesa'
  assert "the changed package still produces a final reboot question" grep -q '^gum confirm --affirmative=Reboot ' "$tmp/seq"
  local scratch
  while IFS= read -r scratch; do
    assert "a completed transaction removes its private config" test ! -e "$scratch"
  done <"$fix/scratch"
  "${base_env[@]}" PATH="$stubs:$tools" FIX="$fix" CALLS="$calls" "$fix/transaction" outside
  assert "outside VGS retains the reboot notification" grep -qxF 'notification reboot' "$calls"
}
row_helper_configs() {
  local helper mode
  for helper in paru yay; do
    for mode in automatic custom rebuild; do
      reset_fix
      transaction_fixture
      printf '[options]\n' >"$fix/selected.conf"
      if [[ $helper == paru ]]; then
        printf '[options]\nInclude = %s/paru-include\n[bin]\nPacmanConf = ignored-program\n' "$fix" >"$tmp/home/.config/paru/paru.conf"
        printf 'PacmanConf = %s/selected.conf\n' "$fix" >"$fix/paru-include"
      fi
      if [[ $helper == yay ]]; then
        mkdir -p "$fix/yay-bin"
        stub "$fix/yay-bin" yay 'if [ "$1" = --show ] && [ "$2" = --currentconfig ]; then
          [ ! -e "$FIX/fail-yay-config" ] || exit 6
          printf "{\"pacmanconf\":\"%s/selected.conf\"}\n" "$FIX"; exit 0
        fi
        [ "$1" != --print ] || exit 98
        [ ! -e "$FIX/transaction" ] || "$FIX/transaction" yay "$@"'
        PIPE_PATH="$fix/yay-bin"
      fi
      printf '{"primary":{"id":"pacman","binary":"pacman"},"overlays":[{"id":"aur","binary":"%s"}],"sources":[]}\n' "$helper" >"$fix/detect.json"
      case $mode in
        custom) settings "$helper -Sua --config=$fix/explicit.conf" false false ;;
        rebuild) self_json package '"vgshell-git"' rebuild; settings "" false false ;;
        *) settings "" false false ;;
      esac
      pipeline update.sh
      assert "$helper $mode finishes successfully" test "$status" == 0
      local expected="$fix/selected.conf"
      [[ $mode != custom ]] || expected="$fix/explicit.conf"
      assert "$helper $mode retains its source config" grep -qxF "$expected" "$fix/config-sources"
      assert "$helper $mode includes that same source config" grep -qxF "Include = $expected" "$fix/generated"
      assert "$helper $mode remains masked" no_call 'notification reboot'
      if [[ $helper:$mode == yay:automatic ]]; then
        touch "$fix/fail-yay-config"
        pipeline update-source.sh aur
        assert "a failed yay settings read fails the run" test "$status" == 1
        assert "a failed yay settings read runs no AUR transaction" no_call 'vgshell pkg run upgrade --manager aur'
      fi
      unset PIPE_PATH
    done
  done
  local stopped want scratch
  for stopped in fail-pacman interrupt-pacman fail-aur interrupt-aur; do
    reset_fix
    transaction_fixture
    touch "$fix/$stopped"
    pipeline update.sh
    want=1
    [[ $stopped != interrupt-* ]] || want=130
    assert "$stopped retains the step result" test "$status" == "$want"
    while IFS= read -r scratch; do
      assert "$stopped removes scratch after the step ends" test ! -e "$scratch"
    done <"$fix/scratch"
  done
  reset_fix
  : >"$fix/fail-hookdirs"
  pipeline update.sh
  assert "an unreadable hook configuration runs no system transaction" no_call 'vgshell pkg run upgrade --manager pacman'
  assert "an unreadable hook configuration fails the run" test "$status" == 1
  reset_fix
  printf '[options]\nInclude = %s/missing\n' "$fix" >"$tmp/home/.config/paru/paru.conf"
  pipeline update-source.sh aur
  assert "an unreadable paru include runs no transaction" no_call 'vgshell pkg run upgrade --manager aur'
  assert "an unreadable paru include fails the run" test "$status" == 1
}

row_facts_plain() {
  reset_fix
  status=0
  "${base_env[@]}" UPDATES_TEST_SECONDARY=1 "${PLUGIN:-$plugin}/bin/facts" "$tree/bin/lib/qml-library.js" self \
    <"$fix/self.json" >"$tmp/facts.out" 2>"$tmp/out" || status=$?
  assert "facts loads the window's plain secondary text" test "$status" == 0
  assert "facts reaches the window secondary check" out_has "updates-test: secondary=reached"
  assert "facts leaves no page markup in the window secondary" out_has "updates-test: secondary=plain"
}
row_pipeline_plain() {
  reset_fix
  UPDATES_TEST_SECONDARY=1 pipeline update.sh
  assert "the pipeline loads the window's plain secondary text" test "$status" == 0
  assert "the pipeline reaches the window secondary check" out_has "updates-test: secondary=reached"
  assert "the pipeline leaves no page markup in the window secondary" out_has "updates-test: secondary=plain"
}
# Two stand-ins record at once, as the sudo keepalive's `sleep` and `pacman -Q`
# do. The first runs under sh -x, whose PS4 runs hold before each command: hold
# stops it at its first command after it wrote to the calls file, if it has,
# and lets it go once the second has run to its end. A record made of separate
# appends is left split by the second's line; a whole line is already written.
row_record_whole() {
  local dir="$tmp/record-whole" polls=0
  rm -rf -- "$dir"
  mkdir -p "$dir/bin"
  stub "$dir/bin" pacman ''
  stub "$dir/bin" sleep ''
  cat >"$dir/hold" <<'SH'
#!/bin/sh
{ [ -s "$CALLS" ] && [ ! -e "$HOLD.held" ]; } || exit 0
: >"$HOLD.held"
read -r _ <"$HOLD.go"
SH
  chmod +x "$dir/hold"
  mkfifo "$dir/hold.go"
  : >"$dir/calls"
  CALLS="$dir/calls" HOLD="$dir/hold" PS4='$("$HOLD")' sh -x "$dir/bin/pacman" -Q 2>/dev/null &
  local first=$!
  while kill -0 "$first" 2>/dev/null && [[ ! -e $dir/hold.held ]] && ((polls < 500)); do sleep 0.01; polls=$((polls + 1)); done
  CALLS="$dir/calls" sh "$dir/bin/sleep" 60
  [[ ! -e $dir/hold.held ]] || echo >"$dir/hold.go"
  wait "$first" || :
  assert "two stand-ins recording at once leave two whole lines" test "$(sort "$dir/calls")" == $'pacman -Q\nsleep 60'
}
row_facts_plain; row_pipeline_plain; row_record_whole
row_full; row_trusted; row_snapshot; row_failure; row_failed_end; row_cause; row_system_failed; row_order; row_answer; row_cause_output; row_stopped; row_interrupted; row_reboot; row_reboot_core; row_reboot_unread; row_orphans; row_yes
row_declined; row_busy; row_aur_command; row_aur_failure; row_aur_rebuild_stopped; row_doas; row_vgs_only; row_vgs_helper; row_vgs_git; row_vgs_step; row_rebuild_failed; row_source; row_recheck_failure; row_recheck_replaced_tree; row_recheck_cli; row_reboot_deferred; row_helper_configs; row_log

# Controls: each runs one row against a plugin copy whose FILE, relative
# to the plugin and tui/pipeline.sh unless named, drops one rule, quietly,
# and that row must turn red.
control() { # NAME NEEDLE REPLACEMENT ROW [FILE]
  local copy_dir="$tmp/plugin-$1" file="${5:-tui/pipeline.sh}"
  cp -R -- "$plugin" "$copy_dir"
  copy_with "$1" "$plugin/$file" "$2" "$3"
  cp -- "$copy" "$copy_dir/$file"
  red=0
  PLUGIN="$copy_dir" QUIET=1 "$4"
  check "the $1 mutant fails $4" test "$red" -gt 0
}
# The record helper this suite wrote before VGS-2001: the name, each argument
# and the newline as separate appends. The row must fail on it.
record_whole="$record"
record='printf "%s" "${0##*/}" >>"$CALLS"; for a; do printf " %s" "$a" >>"$CALLS"; done; echo >>"$CALLS"'
red=0
QUIET=1 row_record_whole
record="$record_whole"
check "the separate-appends record mutant fails row_record_whole" test "$red" -gt 0
control helper-install-skipped '_updates_source paru Paru _updates_run _updates_install_helper' ':' row_vgs_helper
for row in row_facts_plain row_pipeline_plain; do
  control "secondary-markup-$row" 'Commons.PageReference.plain(errorText(error, true))' 'errorText(error, true)' "$row" UpdatesLogic.js
  check "the $row markup control reaches windowRows" out_has "updates-test: secondary=reached"
  check "the $row markup control fails on markup" out_has "updates-test: secondary=markup"
done
missing_tree="$tmp/missing-page-reference"
mkdir -p "$missing_tree/bin/lib"
cp -- "$tree/bin/lib/qml-library.js" "$missing_tree/bin/lib/"
status=0
"${base_env[@]}" "$plugin/bin/facts" "$missing_tree/bin/lib/qml-library.js" self \
  <"$fix/self.json" >"$tmp/facts.out" 2>"$tmp/out" || status=$?
check "facts refuses a missing page-reference module" test "$status" == 2
check "facts names the missing module file" out_has "qml-library: refused: unreadable path=$missing_tree/shell/Commons/PageReference.js error=ENOENT"
control aur-before-revoke 'if [[ $session == 1 ]]; then vgs_tui_sudo_session end; fi' \
  'if [[ $session == 1 ]]; then "$_updates_vgshell" pkg run upgrade --manager aur; vgs_tui_sudo_session end; fi' row_full
control passes-yes '_updates_yes_flag=()' '_updates_yes_flag=(--yes)' row_full
control aur-unguarded '      vgs_tui_sudo_session guard' '      :' row_aur_failure
control session-ignores-elevator 'if [[ $elevator == sudo ]]; then session=1; fi' 'if command -v sudo >/dev/null; then session=1; fi' row_doas
control snapshot-ignores-elevator '_updates_snapshot "$snapshot_tool" "$elevator" || status=$?' '_updates_snapshot "$snapshot_tool" sudo || status=$?' row_doas
control rebuild-unguarded 'if [[ $upgrades == 1 || $rebuild == 1 ]]; then replaces=1; fi' 'if [[ $upgrades == 1 ]]; then replaces=1; fi' row_vgs_only
control rebuild-by-package '[[ $vgs_step == rebuild || $vgs_step == install-helper ]]; then rebuild=1' '[[ $vgs_package == vgshell-git ]]; then rebuild=1' row_vgs_step
control release-aur-command-unread '&& $aur_here == 1 ]]; then vgs_reason=package-manager' '&& false ]]; then vgs_reason=package-manager' row_vgs_step
control rebuild-unrecorded 'if [[ $_updates_outcome == failed ]]; then _updates_rebuild_failed' 'if false; then _updates_rebuild_failed' row_rebuild_failed
control conflict-versioned 'conflict="\"$(_updates_json_text "${BASH_REMATCH[2]%-*-*}")\""' 'conflict="\"$(_updates_json_text "${BASH_REMATCH[2]}")\""' row_rebuild_failed
control record-kept '      rm -f -- "${state:?}/rebuild-failed.json"' '      :' row_rebuild_failed
control no-recovery "trap '_updates_failed \$?' ERR" ':' row_stopped
control no-reboot-check '  _updates_reboot "${_updates_core[@]}"' '  :' row_reboot
control later-powers '    1) echo "Reboot later to run the updated system." ;;' '    1) "$_updates_vgshell" power reboot ;;' row_reboot
control no-success-recheck '  _updates_recheck "$ended"' '  :' row_reboot
control recheck-before-service 'local reply status polls=0' 'local reply status polls=300' row_recheck_replaced_tree
control no-failure-recheck '  _updates_recheck failed' '  :' row_stopped
control source-stops-run '  "$@" || status=$?' '  "$@"' row_failure
# The step's stderr split from stdout through a pipe, as before VGS-1839.
control stderr-split '  "$@" || status=$?' '  { "$@"; } 2> >(exec tee -a -- "$_updates_cause_file" >&2) || status=$?' row_order
control key-at-line-start '(^|[[:space:]])(vgshell|vgs-tui):' '(^)(vgshell|vgs-tui):' row_full
control refusal-cause-held '    _updates_cause="${after:-$value}"' '    _updates_cause="$held"' row_cause
control rescan-cause-after 'own="${tail:-$held}" _updates_cause="${held_fault:-${held:-${after:-$value}}}"' 'own="${tail:-$held}" _updates_cause="${after:-$value}"' row_cause
control cause-ignores-error-line 'own="$last" _updates_cause="${fault:-$last}"' 'own="$last" _updates_cause="$last"' row_cause_output
control scan-line-read '      if [[ $line =~ $_updates_scan_line ]]; then' '      if false; then' row_answer
control scan-line-cause '      if [[ $line =~ $_updates_scan_line ]]; then' '      if false; then' row_cause_output
control answer-unread '$rest =~ $_updates_answer && $rest != *[Yy]*' '-z ${rest//[[:space:]]/}' row_answer
control question-tail-ignored 'own="${tail:-$held}"' 'own="$held"' row_cause
control question-unread 'if [[ $own =~' 'if false && [[ $own =~' row_cause
control reboot-mask-missing 'ln -s -- /dev/null' 'ln -s -- /dev/zero' row_reboot_deferred
control answered-question-kept '[[ $rest =~ $_updates_answer ]] || line="$rest"' ':' row_cause
control aur-after-failed-system 'if [[ -n $aur_blocked ]]; then' 'if false; then' row_system_failed
control aur-after-declined-system '            declined) aur_blocked=' '            declined) ;; x) aur_blocked=' row_system_failed
control rebuild-after-aur-refusal 'if [[ $rebuild_run == 1 && $_updates_outcome != installed ]]; then' 'if false; then' row_aur_rebuild_stopped
control reboot-read-silent '  vgs_tui_warn "Could not check which updates need a restart."' '  :' row_reboot_unread
control reboot-warns-twice '  [[ $_updates_reboot_warned == 0 ]] || return 0' '  :' row_reboot_unread
control cause-keeps-escapes 'sed -E -e $'"'"'s/\e' 'sed -E -e $'"'"'s/NEVER\e' row_failure
control failure-exits-0 '  [[ $ended == success ]] || exit 1' '  :' row_failure
control no-failure-next-step ' Next: $_updates_next' '' row_failed_end
control result-unwrapped '  _vgs_tui_lines lines "$width" "$text"' '  lines=("$text")' row_failed_end
control result-without-hanging-indent '    printf -v prefix '"'"'%*s'"'"' "${#prefix}" '"'"''"'"'' '    prefix=""' row_failed_end
control failed-summary-at-left '    _updates_result "$width" '"'"'Failed parts: '"'"' "$failed_parts"' '    printf '"'"'Failed parts: %s\n'"'"' "$failed_parts"' row_failed_end
control interrupt-goes-on 'if [[ $status -eq 130 ]]; then' 'if false; then' row_interrupted
control declined-fails 'if [[ $_updates_declined == 1 ]]; then' 'if false; then' row_full
control reboot-ignores-upgrades 'if [[ $# -gt 0 ]]; then' 'if false; then' row_reboot_core
control reboot-ignores-hook '[[ ! -f ${root%/}/$_updates_reboot_hook ]] || hook="${root%/}/$_updates_reboot_hook"' ':' row_reboot_core
control reboot-ignores-targets '&& targetsMatch(trigger.targets, change.name);' ';' row_reboot_core UpdatesLogic.js
control reboot-ignores-mounts "printf 'mounted %s\\n' \"\$value\"" ':' row_reboot_core
control reboot-facts-stops-run '} | _updates_facts reboot "$hook" /proc/version)" || status=$?' '} | _updates_facts reboot "$hook" /proc/version)"' row_reboot_core
control reboot-new-as-upgrade 'then changes+=("install $name")' 'then changes+=("upgrade $name")' row_reboot_core
control orphans-default-yes 'orphaned package(s)?" --default=false || status=$?' 'orphaned package(s)?" || status=$?' row_orphans
control log-clobbers 'vgs_tui_log "$UPDATES_LOG_PART"' 'vgs_tui_log "$_updates_log"' row_busy
control unasked-start 'vgs_tui_confirm "Start the update?" || status=$?' 'true || status=$?' row_declined
control log-elsewhere 'printf '"'"'%s\n'"'"' "$(updates_state_dir)/update.log"' 'printf '"'"'%s\n'"'"' "$(updates_state_dir)/other.log"' row_log
control log-absent-opens '[[ -f $log ]] || _updates_refuse 1' '[[ -n $log ]] || _updates_refuse 1' row_log tui/log.sh
control log-closes-unread "trap 'status=\$?; [[ \$status == 0 ]] || vgs_tui_close_prompt \"\$status\"' EXIT" ':' row_log tui/log.sh
control unknown-source-unchecked '_updates_refuse 2 "source=$only reason=unknown"' \
  ': 2 "source=$only reason=unknown"' row_source

# The pipeline keeps its other command stand-ins. Theme updates run the real
# command and judge over local git sources. Before each update, a holder
# releases the lock only after /proc/locks reports the blocked update.
(
  pipeline_stubs="$stubs"
  pipeline_command="$tree/bin/vgshell"
  tmp="$tmp/real-themes"; mkdir -p "$tmp"
  ln -s -- "${tmp%/*}/terminal-input" "$tmp/terminal-input"
  theme_tree
  for tool in env python3 setsid setpriv timeout sleep; do
    tool_bin="$(command -v "$tool")" || exit 77
    ln -s -- "$tool_bin" "$theme_path/$tool"
  done
  mv -- "$tree/bin/vgshell" "$tree/bin/vgshell.real"
  cp -- "$pipeline_command" "$tree/bin/vgshell"
  cp -- "${pipeline_command%/*}/review-owner" "$tree/bin/review-owner"
  stubs="$pipeline_stubs"
  state="$tmp/state"; log="$state/vgshell/updates/update.log"
  cfg="$tmp/config"; mkdir -p "$cfg/vgshell"
  run_real() {
    "${base_env[@]}" PATH="$theme_path" XDG_CONFIG_HOME="$cfg" XDG_STATE_HOME="$state" "$tree/bin/vgshell.real" "$@"
  }
  for name in amberbyte tokyo-night vengeance; do
    theme_source "$name" "$(doc "$name")"
    run_real theme add "$tmp/tsrc/$name.git" >/dev/null
    theme_commit "$name" theme.json "$(doc "$name" '{ "palette": { "accent": "#123456" } }')"
  done
  cp -R -- "$cfg" "$tmp/old-config"
  tree_control update-no-wait bin/vgshell.real '  theme_lock_change "theme=$name" -w "$theme_lock_wait_s"' '  theme_lock_change "theme=$name" -n'
  mutant_command="${THEME_BIN%/*}/vgshell.real"
  for command in "$tree/bin/vgshell.real" "$mutant_command"; do
    rm -rf -- "${cfg:?}"; cp -R -- "$tmp/old-config" "$cfg"
    reset_fix
    settings "" true
    run_real theme outdated --json >"$fix/themes.json"
    python3 -c 'import json,sys
rows = {r["id"]: r for r in json.load(open(sys.argv[1]))}
for name in ("amberbyte", "tokyo-night", "vengeance"):
    assert name in rows and rows[name]["error"] is None and rows[name]["behind"] > 0, rows.get(name)
' "$fix/themes.json"
    {
      printf '#!/usr/bin/env bash\nset -euo pipefail\n'
      printf 'PATH=%q\ntmp=%q\n' "$base_path" "$tmp/lock-holder"
      printf 'mkdir -p "$tmp"\nfail() { echo "$*" >&2; exit 1; }\n'
      declare -f theme_lock_holder
      printf 'theme_lock_holder exclusive %q\n' "$cfg/vgshell/theme.lock"
      printf 'status=0\n'
      printf '%q ' "${base_env[@]}" PATH="$theme_path" XDG_CONFIG_HOME="$cfg" XDG_STATE_HOME="$state" "$command"
      printf '"$@" || status=$?\n'
      printf ': >"$tmp/release"\nwait "$holder"\nexit "$status"\n'
    } >"$fix/theme-update"
    chmod +x "$fix/theme-update"
    pipeline update.sh -y
    if [[ $command == "$tree/bin/vgshell.real" ]]; then
      check "the pipeline updates three themes behind the apply lock" test "$status" == 0
      for name in amberbyte tokyo-night vengeance; do
        check "the pipeline installs $name's new commit" test "$(head_of "$cfg/vgshell/themes/$name")" == "$(head_of "$tmp/tsrc/$name")"
      done
    else
      check "the planted busy refusal fails the three-theme pipeline" test "$status" == 1
      for name in amberbyte tokyo-night vengeance; do
        check "the refusal leaves $name at its old commit" test "$(head_of "$cfg/vgshell/themes/$name")" != "$(head_of "$tmp/tsrc/$name")"
        check "the control reaches $name's busy lock refusal" diag_has "updates: failed source=theme:$name exit=75"
      done
    fi
  done
  rows_done test-updates-pipeline-themes
)

rows_done test-updates-pipeline
