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
# The review rows put stand-in agent CLIs on PATH, each recording its argv
# but the prompt, the start directory it ran from, the packages.txt, build
# files and install diffs in the review directory named by the prompt, and
# writing the
# verdict there. An agent writes its verdict only once the
# pipeline's lock wait is recorded, or once the pipeline asked to go on
# without one: a barrier on the stand-in flock's record, not a sleep. The
# stand-in vgshell answers the service's `review` IPC call by running the
# shipped tui/review.sh of the copy in the background, as the review TUI
# would, and writes the review directory's `ended` after it, as the
# service's `done` does; `ipc-refuses` answers a refusal, and `ipc-ended`
# writes `ended` alone, as a terminal that failed after the answer does.
# The stand-in paru's -G saves each package under its base, as the real one
# does, with a PKGBUILD and the build files a row put in $FIX/build-<base>.
# No row reaches a real agent or the network.
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
mkdir -p "$tree/bin/lib"
cp -- "$repo/bin/lib/tui.sh" "$repo/bin/lib/qml-library.js" "$repo/bin/lib/judge-files.js" "$tree/bin/lib/"
printf '0.1.0\n' >"$tree/VERSION"
calls="$tmp/calls"; fix="$tmp/fix"; rt="$tmp/rt"; state="$tmp/state"
mkdir -p "$fix" "$rt" "$state"
log="$state/vgshell/updates/update.log"
# Keep the test terminal's input open like a live terminal. An early EOF
# from /dev/null can be echoed by the nested script(1) log recorder.
mkfifo "$tmp/terminal-input"
exec {terminal_input}<>"$tmp/terminal-input"

# Stand-ins. Each first appends `<name> <arguments>` to $CALLS.
stubs="$tmp/stubs"; snapper_dir="$tmp/snapper-bin"; tools="$tmp/tools"
mkdir -p "$stubs" "$snapper_dir" "$tools"
record='printf "%s" "${0##*/}" >>"$CALLS"; for a; do printf " %s" "$a" >>"$CALLS"; done; echo >>"$CALLS"'
stub() { # DIR NAME BODY
  printf '#!/bin/sh\n%s\n%s\n' "$record" "$3" >"$1/$2"
  chmod +x "$1/$2"
}
# vgshell answers each read from $FIX; pacman's plan names the elevator in
# $FIX/elevator; `pkg detect` fails with 5 while $FIX/fail-detect exists.
# `pkg run` for a manager ID: fails with 9 for $FIX/fail-<id>, after a
# coloured error line on stderr ending in a carriage return; exits 130, as
# a Ctrl-C ends it, for $FIX/interrupt-<id>; leaves pacman's question
# unanswered on stderr, as a no does, for $FIX/decline-<id>, and before its
# closing `rescan=` refusal for $FIX/decline-rescan-<id>; fails after a
# question answered yes for $FIX/answered-<id>; ends on its closing
# `rescan=` refusal after an error line for $FIX/rescan-<id>; and for
# $FIX/hup-<id> hangs up the tee that copies its stderr, as a closed window
# does, then writes a last error line. `plugin|theme update` for an ID
# declines, as its [y/N] question answered no does, for $FIX/decline-<id>,
# and refuses an offline fetch with git's message for $FIX/offline-<id>.
# `pkg owner` answers only while $FIX/owner exists, with a new version
# after its first answer when $FIX/owner-changes does.
stub "$tree/bin" vgshell 'hup_tee() {
  pipe="$(readlink /proc/$$/fd/2)" tee_pid="" i=0
  while [ -z "$tee_pid" ] && [ "$i" -lt 100 ]; do
    for f in /proc/[0-9]*/stat; do
      read -r pid comm rest 2>/dev/null <"$f" || continue
      [ "$comm" = "(tee)" ] && [ "$(readlink "/proc/$pid/fd/0" 2>/dev/null)" = "$pipe" ] && tee_pid="$pid"
    done
    [ -n "$tee_pid" ] || { sleep 0.02; i=$((i + 1)); }
  done
  kill -HUP "$tee_pid"
  i=0
  while [ "$i" -lt 20 ]; do
    read -r pid comm state rest 2>/dev/null <"/proc/$tee_pid/stat" || break
    [ "$state" != Z ] || break
    sleep 0.05; i=$((i + 1))
  done
  printf "error: interrupted by a hangup\n" >&2
  exit 1
}
case "$1 $2" in
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
    [ ! -e "$FIX/interrupt-$5" ] || exit 130
    [ ! -e "$FIX/fail-$5" ] || { printf "\033[31merror:\033[0m failed to install crush\r\n" >&2; exit 9; }
    [ ! -e "$FIX/decline-$5" ] || { printf ":: Proceed with installation? [Y/n] " >&2; exit 1; }
    [ ! -e "$FIX/decline-rescan-$5" ] || { printf ":: Proceed with installation? [Y/n] vgshell: refused: rescan=refused\nthe plugin files changed; run vgshell ipc call shell rescanPlugins\n" >&2; exit 1; }
    [ ! -e "$FIX/answered-$5" ] || { printf ":: Proceed with installation? [Y/n] error: failed to commit transaction (conflicting files)\n" >&2; exit 1; }
    [ ! -e "$FIX/rescan-$5" ] || { printf "error: failed to commit transaction (conflicting files)\nvgshell: refused: rescan=refused\nthe plugin files changed; run vgshell ipc call shell rescanPlugins\n" >&2; exit 1; }
    [ ! -e "$FIX/hup-$5" ] || hup_tee ;;
  "plugin update"|"theme update")
    for id; do :; done
    [ ! -e "$FIX/decline-$id" ] || { printf "vgshell: update %s? [y/N] vgshell: refused: declined=%s\nthe checkout stays at its commit\n" "$id" "$id" >&2; exit 1; }
    [ ! -e "$FIX/offline-$id" ] || { printf "vgshell: refused: fetch=%s\nfatal: unable to access https://example.org/acme.git/: Could not resolve host: example.org\n" "$id" >&2; exit 1; } ;;
  "pkg check")
    if [ -e "$FIX/check-$5.json" ]; then cat "$FIX/check-$5.json"
    else echo "[{\"source\":\"$5\",\"count\":0,\"packages\":[],\"checkedAt\":\"x\",\"error\":null}]"
    fi ;;
  "ipc call")
    case "$5" in
      check)
        if [ -e "$FIX/ipc-check-refuses" ]; then echo "refused: ipc=check reason=test"; exit 8; fi
        echo started ;;
      review)
        if [ -e "$FIX/ipc-refuses" ]; then echo "refused: tui=review reason=launcher-missing"; exit 0; fi
        if [ -e "$FIX/ipc-ended" ]; then echo "reason=launcher-failed" >"$6/ended"; echo ok; exit 0; fi
        ( bash "$VGS_PLUGIN_DIR/tui/review.sh" "$6"; echo "code=$?" >"$6/ended" ) </dev/null >/dev/null 2>&1 &
        echo ok ;;
    esac ;;
  "pkg owner")
    [ -e "$FIX/owner" ] || exit 1
    v=1
    if [ -e "$FIX/owner-asked" ] && [ -e "$FIX/owner-changes" ]; then v=2; fi
    : >"$FIX/owner-asked"
    echo "{\"manager\":\"pacman\",\"package\":\"vgshell-git\",\"version\":\"0.1.0.r$v\"}" ;;
  "pid ") [ -e "$FIX/running" ] || exit 69; echo 42 ;;
esac'
# gum confirm answers the exit status in $FIX/answer-<question>, 0 when
# absent: `skip` for the review's Skip or Install anyway, `reboot` for the
# reboot question; style prints its lines.
stub "$stubs" gum 'case "$1" in
  confirm)
    for q; do :; done
    case "$q" in "Start the update?") f=start ;; Remove*) f=orphans ;; *Reboot*) f=reboot ;; Skip*) f=skip ;; Continue*) f=continue ;; *) f=other ;; esac
    st=0; [ ! -e "$FIX/answer-$f" ] || read -r st <"$FIX/answer-$f"; exit "$st" ;;
  style) shift; for a; do printf "%s\n" "$a"; done ;;
esac'
# sudo refuses every authorization and every command while
# $FIX/sudo-refuses exists; doas runs its command.
stub "$stubs" sudo 'case "$1" in -k) exit 0 ;; esac
[ ! -e "$FIX/sudo-refuses" ] || exit 1
case "$1" in -n|/usr/bin/true) exit 0 ;; esac
exec "$@"'
stub "$stubs" doas 'exec "$@"'
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
stub "$stubs" pacman-conf 'case "$1 ${3:-}" in
  "DBPath ") echo "$FIX/db/" ;;
  "RootDir ") [ ! -e "$FIX/fail-rootdir" ] || exit 1; echo "$FIX/root/" ;;
  "--repo-list ") cat "$FIX/repos" ;;
  "--repo Server") cat "$FIX/server-$2" ;;
  "--repo SigLevel") [ ! -e "$FIX/siglevel-$2" ] || cat "$FIX/siglevel-$2" ;;
  "SigLevel ") echo PackageRequired ;;
esac'
# The agent CLIs: claude, codex and a custom my-agent, in their own
# directory, which a review row puts on PATH.
agents="$tmp/agents"
mkdir -p "$agents"
for agent in claude codex my-agent; do
  cat >"$agents/$agent" <<'SH'
#!/bin/sh
n=$#
line="${0##*/}"
i=0
for a; do i=$((i + 1)); [ "$i" -lt "$n" ] && line="$line $a"; done
echo "$line" >>"$CALLS"
eval "last=\${$n}"
printf '%s' "$last" >"$FIX/prompt-seen"
pwd >"$FIX/agent-cwd"
review_dir="$(printf '%s\n' "$last" | sed -n 's|^The review directory is `\(.*\)`. The files below are in it\. Read and write paths relative to that directory\.$|\1|p' | sed -n '1p')"
if [ -n "$review_dir" ]; then
  cat "$review_dir/packages.txt" >"$FIX/packages-seen" 2>/dev/null || :
  for f in "$review_dir"/build/*/PKGBUILD "$review_dir"/install/*.diff; do [ ! -e "$f" ] || echo "${f#"$review_dir"/}"; done >"$FIX/build-seen"
else
  : >"$FIX/packages-seen"
  : >"$FIX/build-seen"
fi
polls=0
while [ "$polls" -lt 600 ]; do
  seen=0
  while IFS= read -r l; do
    case "$l" in "flock "[0123456789]*|*"Continue without a review?") seen=1 ;; esac
  done <"$CALLS"
  [ "$seen" = 0 ] || break
  sleep 0.05
  polls=$((polls + 1))
done
[ ! -e "$FIX/verdict" ] || { [ -n "$review_dir" ] && cat "$FIX/verdict" >"$review_dir/verdict"; }
SH
  chmod +x "$agents/$agent"
done
# flock records its call and runs the real one.
stub "$stubs" flock "exec '$tools/flock' \"\$@\""
stub "$stubs" pikaur ''
stub "$stubs" df 'a=99999999999; [ ! -e "$FIX/avail" ] || read -r a <"$FIX/avail"; printf "  Avail\n%s\n" "$a"'
stub "$stubs" pgrep '[ -e "$FIX/pids" ] || exit 1; cat "$FIX/pids"'
stub "$stubs" uname "echo $kernel"
stub "$stubs" systemctl ''
# findmnt lists the mounted file system types in $FIX/fstypes, none when
# it is absent, and fails while $FIX/fail-findmnt exists.
stub "$stubs" findmnt '[ ! -e "$FIX/fail-findmnt" ] || exit 1; [ ! -e "$FIX/fstypes" ] || cat "$FIX/fstypes"'
# paru authorizes through sudo and fails with 7 while $FIX/fail-paru exists,
# and with 130, as a Ctrl-C ends it, while $FIX/interrupt-paru does. Its -G
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
[ ! -e "$FIX/interrupt-paru" ] || { sudo /usr/bin/true; exit 130; }
[ ! -e "$FIX/fail-paru" ] || { sudo /usr/bin/true; exit 7; }'
stub "$stubs" less ''
for tool in bash env readlink dirname mkdir chmod mv rm script flock sleep cat id sed tee diff ln; do
  found="$(command -v "$tool")" || { echo "test-updates-pipeline: status=not-measured missing=$tool"; exit 77; }
  ln -s -- "$(readlink -f -- "$found")" "$tools/$tool"
done
ln -s -- "$node_bin" "$tools/node"

replaced_binary "$tmp/Hyprland"
# shellcheck disable=SC2154 # replaced_binary sets it
hyprland_pid="$replaced_pid"

settings() { # AUR_COMMAND TRUST [REVIEW AGENT COMMAND]
  printf '{"intervalHours":6,"hideWhenCurrent":false,"aurCommand":"%s","snapshot":"auto","trustPluginUpdates":%s,"reviewThirdParty":%s,"reviewAgent":"%s","reviewCommand":"%s","placement":"center"}\n' \
    "$1" "$2" "${3:-true}" "${4:-}" "${5:-}" >"$fix/settings.json"
}
self_json() { # METHOD PACKAGE_JSON BEHIND
  printf '{"version":"0.1.0","method":"%s","package":%s,"current":"a","latest":"b","behind":%s,"error":null}\n' "$1" "$2" "$3" >"$fix/self.json"
}
# The fixture every row starts from: pacman with the AUR through paru,
# Flatpak and mise; a checkout one commit behind; one plugin and one theme
# behind; no snapshot tool, no orphan, no replaced Hyprland, no package
# upgraded, every answer yes.
reset_fix() {
  rm -rf -- "${fix:?}" "$state/vgshell"
  mkdir -p "$fix"
  printf 'linux 6.1-1\nmesa 24.1-1\nvgshell-git 0.1.0.r1-1\n' >"$fix/installed"
  settings "" false
  echo sudo >"$fix/elevator"
  printf '{"primary":{"id":"pacman","binary":"pacman"},"overlays":[{"id":"aur","binary":"paru"},{"id":"flatpak","binary":"flatpak"}],"sources":[{"id":"mise","binary":"mise"}]}\n' >"$fix/detect.json"
  self_json checkout null true
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

# Third-party updates: one AUR package, and beside linux from core one
# package of chaotic, a repository that is not official, whose servers
# and signature level the review lists.
third_party() {
  printf '[{"source":"aur","count":1,"packages":[{"name":"tool-bin","old":"1.0-1","new":"1.1-1"}],"checkedAt":"x","error":null}]\n' >"$fix/check-aur.json"
  printf '[{"source":"pacman","count":2,"packages":[{"name":"linux","old":"6.1-1","new":"6.2-1"},{"name":"foo","old":"2-1","new":"3-1"}],"checkedAt":"x","error":null}]\n' >"$fix/check-pacman.json"
  printf 'core\nextra\ncachyos-extra-znver4\nchaotic\n' >"$fix/repos"
  printf 'chaotic foo 3-1 [installed: 2-1]\nchaotic bar 1-1\n' >"$fix/sl-chaotic"
  printf 'https://mirror:s3cret@chaotic.example/x86_64\n' >"$fix/server-chaotic"
  printf 'Optional\nTrustAll\n' >"$fix/siglevel-chaotic"
}

# pipeline SCRIPT ARG...: the plugin copy $PLUGIN, else $plugin, runs
# tui/SCRIPT on a pseudo-terminal; its output in $tmp/out, the exit status
# in $status, and the calls, but for the free-space and reboot probes and
# the plan box, in $tmp/seq. PIPE_PATH puts a directory before the stubs.
pipeline() {
  local script_path="${PLUGIN:-$plugin}/tui/$1"
  shift
  : >"$calls"
  status=0
  "${base_env[@]}" PATH="${PIPE_PATH:+$PIPE_PATH:}$stubs:$tools" VGS_TUI_LIB="$tree/bin/lib/tui.sh" VGS_PLUGIN_ID=vgs.updates VGS_PLUGIN_DIR="${PLUGIN:-$plugin}" \
    XDG_STATE_HOME="$state" XDG_RUNTIME_DIR="$rt" CALLS="$calls" FIX="$fix" \
    script -qec "$(printf '%q ' "$BASH" "$script_path" "$@")" /dev/null <"$tmp/terminal-input" {terminal_input}>&- >"$tmp/out" 2>&1 || status=$?
  local filtered=0
  grep -v -e '^df ' -e '^uname ' -e '^pgrep ' -e '^gum style' -e '^flock ' "$calls" >"$tmp/seq" || filtered=$?
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
  assert "a full run lists each source installed" out_has "System: installed"
  assert "a full run lists each plugin installed" out_has "Plugin acme.one: installed"
  assert "nothing core upgraded asks no reboot" no_call "gum confirm --affirmative=Reboot"
  touch "$fix/decline-acme.one"
  pipeline update.sh
  assert "a declined plugin update leaves the exit 0" test "$status" == 0
  assert "a declined plugin update reads skipped" out_has "Plugin acme.one: skipped, you declined it"
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
# source; the reboot question still follows the result list, and the run
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
  assert "the result list names the failed source with its cause line" out_has "mise: failed, error: failed to install crush"
  assert "the result list names the later source installed" out_has "AUR: installed"
  assert "the failure stays in the developer log" diag_has "updates: failed source=mise exit=9"
  assert "a failed source asks the service for one check" test "$(grep -cxF "vgshell ipc call vgs.updates invoke check " "$tmp/seq")" == 1
  assert "a failed source is not a stopped run" out_lacks "The update stopped."
  assert "a failed source still asks to reboot after an upgraded kernel" has_call "gum confirm --affirmative=Reboot --negative=Later --default=false -- The run updated linux, which takes effect after a reboot. Reboot now?"
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
  assert "an offline plugin update is listed with git's message" out_has "Plugin acme.one: failed, fatal: unable to access https://example.org/acme.git/: Could not resolve host: example.org"
  assert "an offline plugin update ends the run with 1" test "$status" == 1
  reset_fix
  touch "$fix/rescan-flatpak"
  pipeline update.sh
  assert "pkg run's closing refusal leaves its manager's line as the cause" out_has "Flatpak: failed, error: failed to commit transaction (conflicting files)"
  reset_fix
  touch "$fix/answered-flatpak"
  pipeline update.sh
  assert "a failure after a question answered yes is listed without the question" out_has "Flatpak: failed, error: failed to commit transaction (conflicting files)"
  reset_fix
  touch "$fix/decline-pacman"
  pipeline update.sh
  assert "a system upgrade answered no reads skipped" out_has "System: skipped, you declined it"
  assert "a system upgrade answered no leaves the exit 0" test "$status" == 0
  reset_fix
  touch "$fix/decline-rescan-pacman"
  pipeline update.sh
  assert "a question answered no before pkg run's closing refusal reads skipped" out_has "System: skipped, you declined it"
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
  assert "a failed system upgrade lists the AUR skipped with its cause" out_has "AUR: skipped, the system upgrade failed, and AUR packages build against it"
  assert "a later source installs after a failed system upgrade" out_has "mise: installed"
  assert "a plugin updates after a failed system upgrade" out_has "Plugin acme.one: installed"
  reset_fix
  self_json package '"vgshell-git"' true
  touch "$fix/owner" "$fix/owner-changes" "$fix/running" "$fix/fail-pacman"
  pipeline update.sh
  assert "a failed system upgrade rebuilds no vgshell-git" no_call "paru -S vgshell-git"
  assert "a failed system upgrade lists the rebuild skipped" out_has "VGS package: skipped, the system upgrade failed, and AUR packages build against it"
  reset_fix
  touch "$fix/decline-pacman"
  pipeline update.sh
  assert "a declined system upgrade runs no AUR step" no_call "vgshell pkg run upgrade --manager aur"
  assert "a declined system upgrade lists the AUR skipped with its cause" out_has "AUR: skipped, you declined the system upgrade, and AUR packages build against it"
  assert "a later source installs after a declined system upgrade" out_has "mise: installed"
}
# A closed window hangs up the step's group; the tee that copies its
# stderr ignores it, so the step's last line still reaches the terminal
# and the cause, and the step is not killed by SIGPIPE.
row_hangup() {
  reset_fix
  touch "$fix/hup-mise"
  pipeline update.sh
  assert "a hung-up step's last line is its cause" out_has "mise: failed, error: interrupted by a hangup"
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
  printf '%s\n' "$hyprland_pid" >"$fix/pids"
  pipeline update.sh
  assert "a replaced Hyprland asks to reboot" has_call "gum confirm --affirmative=Reboot --negative=Later --default=false -- Hyprland was updated. Reboot now?"
  assert "a replaced Hyprland rechecks before it asks to reboot" before "vgshell ipc call vgs.updates invoke check " "gum confirm --affirmative=Reboot --negative=Later --default=false -- Hyprland was updated. Reboot now?"
  assert "a yes reboots" test "$(tail -n 1 "$tmp/seq")" == "systemctl reboot"
  echo 1 >"$fix/answer-reboot"
  pipeline update.sh
  assert "a no does not reboot" test "$(grep -c '^systemctl' "$tmp/seq")" == 0
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
  assert "a reboot asked after an upgraded kernel reboots on a yes" test "$(tail -n 1 "$tmp/seq")" == "systemctl reboot"
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
  assert "btrfs-progs with btrfs mounted asks to reboot" has_call "gum confirm --affirmative=Reboot --negative=Later --default=false -- The run updated btrfs-progs, which takes effect after a reboot. Reboot now?"
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
  assert "a failed AUR step with no stderr is listed with its status" out_has "AUR: failed, exit 7"
  assert "the credential is dropped after the failed AUR step" before "paru -Sua --devel" "sudo -k"
  rm -f -- "${fix:?}/fail-paru"
  touch "$fix/interrupt-paru"
  pipeline update.sh
  assert "an interrupted AUR step ends the run with 130" test "$status" == 130
  assert "an interrupted AUR step drops the credential it cached, last" test "$(tail -n 1 "$tmp/seq")" == "sudo -k"
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
  self_json package '"vgshell-git"' true
  touch "$fix/owner" "$fix/owner-changes" "$fix/running"
  PIPE_PATH="$snapper_dir" pipeline update-source.sh vgs
  assert "a VGS rebuild alone exits 0" test "$status" == 0
  assert "a VGS rebuild alone takes a snapshot before it" before "sudo snapper -c root create -c number -d VGS update" "paru -S vgshell-git"
  assert "a VGS rebuild alone drops the credential after it" before "paru -S vgshell-git" "sudo -k"
  assert "a VGS rebuild alone restarts the running shell" has_call "vgshell restart"
  assert "a VGS rebuild alone upgrades no other package" test "$(grep -c -e 'pkg run' -e '^pacman -[^Q]' "$tmp/seq")" == 0
}
row_vgs_git() {
  reset_fix
  self_json package '"vgshell-git"' true
  touch "$fix/owner" "$fix/owner-changes" "$fix/running"
  pipeline update.sh
  assert "a package tree runs no self update" test "$(grep -c 'self update' "$tmp/seq")" == 0
  assert "a behind vgshell-git is rebuilt after the AUR" before "vgshell pkg run upgrade --manager aur" "paru -S vgshell-git"
  assert "the credential is dropped after the rebuild" before "paru -S vgshell-git" "sudo -k"
  assert "a replaced VGS package restarts the running shell" has_call "vgshell restart"
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
  { if [[ $keys == yes ]]; then while :; do printf x; sleep 0.2; done; else sleep 3; fi; } |
    timeout "$ceiling" "${base_env[@]}" PATH="$stubs:$tools" VGS_TUI_LIB="$tree/bin/lib/tui.sh" VGS_PLUGIN_ID=vgs.updates VGS_PLUGIN_DIR="${PLUGIN:-$plugin}" \
      XDG_STATE_HOME="$state" XDG_RUNTIME_DIR="$rt" CALLS="$calls" FIX="$fix" \
      script -qec "$(printf '%q ' "$BASH" "$script_path" "$@")" /dev/null >"$tmp/out" 2>&1
  status=${PIPESTATUS[1]}
  set -e
  grep -v -e '^df ' -e '^uname ' -e '^pgrep ' -e '^gum style' -e '^flock ' "$calls" >"$tmp/seq" || filtered=$?
  [[ $filtered -le 1 ]] || { echo "test-updates-pipeline: calls=unreadable exit=$filtered" >&2; exit 1; }
}
# The first line of the output, without the typed keys the terminal echoed
# before the script read any.
first_line() { head -n 1 "$tmp/out" | tr -d '\r' | sed -e 's/^x*//'; }
failed_prompt="Failed (exit code 1)! Press any key to close..."
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

# The third-party review
# (shell/plugins/vgs.updates/pipeline.md § Third-party review). Each row has
# the third-party updates pending; review_dir is the review directory the
# run asked the service to open, from its recorded IPC call.
review_call="vgshell ipc call vgs.updates invoke review "
review_dir() { sed -n "s|^$review_call||p" "$tmp/seq" | head -n 1; }
expected_review_prompt() { # DIR
  python3 - "$plugin/review/third-party.md" "$1" <<'PY'
import pathlib
import sys

print(pathlib.Path(sys.argv[1]).read_text().replace("{review_dir}", sys.argv[2]), end="")
PY
}
# r1: off, a run is today's, whatever agent is on PATH.
row_review_off() {
  reset_fix
  third_party
  settings "" false false
  PIPE_PATH="$agents" pipeline update.sh
  assert "a review that is off leaves the run as it is" seq_is "${full_seq[@]}"
}
# r6: on with no agent CLI on PATH, a run is today's too.
row_review_no_agent() {
  reset_fix
  third_party
  pipeline update.sh
  assert "a review with no agent found leaves the run as it is" seq_is "${full_seq[@]}"
}
# r2: on with an agent and nothing third-party pending, no window opens.
row_review_none_pending() {
  reset_fix
  printf 'core\nchaotic\n' >"$fix/repos"
  printf 'chaotic foo 3-1\n' >"$fix/sl-chaotic"
  printf '[{"source":"pacman","count":1,"packages":[{"name":"linux","old":"6.1-1","new":"6.2-1"}],"checkedAt":"x","error":null}]\n' >"$fix/check-pacman.json"
  PIPE_PATH="$agents" pipeline update.sh
  assert "nothing third-party pending exits 0" test "$status" == 0
  assert "nothing third-party pending asks the AUR and the system for their updates" has_call "vgshell pkg check --json --source pacman"
  assert "nothing third-party pending opens no review" no_call "$review_call"
  assert "nothing third-party pending still upgrades" has_call "vgshell pkg run upgrade --manager aur"
}
# r3: a clean verdict: the window runs the default command with the
# prompt naming the review directory, from the stable review start
# directory, before any credential, and the run goes on with no package
# kept out.
row_review_clean() {
  reset_fix
  third_party
  printf 'verdict clean\n' >"$fix/verdict"
  PIPE_PATH="$agents" pipeline update.sh
  local dir expected_prompt
  dir="$(review_dir)"
  expected_prompt="$(expected_review_prompt "$dir")" || return 1
  assert "a clean review exits 0" test "$status" == 0
  assert "the review directory is the run's own inside the start directory" test "${dir%/*}" == "$rt/vgshell/updates/review"
  assert "the agent runs the default command in its restricted mode" has_call "claude --model opus --effort medium --permission-mode default"
  assert "the run fetches the AUR build files itself" has_call "paru -G tool-bin"
  assert "the agent finds the fetched build files" test "$(cat "$fix/build-seen" 2>/dev/null)" == "build/tool-bin/PKGBUILD"
  assert "the agent's last argument is the bundled prompt with the review directory" test "$(cat "$fix/prompt-seen" 2>/dev/null)" == "$expected_prompt"
  assert "the agent runs in the review start directory" test "$(cat "$fix/agent-cwd" 2>/dev/null)" == "$rt/vgshell/updates/review"
  assert "the agent is handed the third-party packages alone" test "$(cat "$fix/packages-seen" 2>/dev/null)" == "$(printf '%s\n' "helper paru" "aur tool-bin 1.0-1 1.1-1" "repo chaotic foo 2-1 3-1" "server chaotic https://chaotic.example/x86_64" "siglevel chaotic Optional TrustAll" "install tool-bin none")"
  assert "no credential is asked before the review" none_before "sudo" "$review_call"
  assert "the review comes before the sudo session" before "$review_call$dir" "sudo /usr/bin/true"
  assert "a clean verdict asks nothing more" no_call "gum confirm --default=false -- Continue without a review?"
  assert "a clean verdict runs the system step as it is" has_call "vgshell pkg run upgrade --manager pacman"
  assert "a clean verdict runs the AUR step as it is" has_call "vgshell pkg run upgrade --manager aur"
  assert "the review directory is removed" test ! -e "$dir"
}
# r3b: separate runs use separate private directories under one stable
# start directory, so the agent's folder trust sees the same path.
row_review_start_stable() {
  reset_fix
  third_party
  printf 'verdict clean\n' >"$fix/verdict"
  PIPE_PATH="$agents" pipeline update.sh
  local first_dir first_start second_dir second_start
  first_dir="$(review_dir)"
  first_start="$(cat "$fix/agent-cwd" 2>/dev/null)"
  reset_fix
  third_party
  printf 'verdict clean\n' >"$fix/verdict"
  PIPE_PATH="$agents" pipeline update.sh
  second_dir="$(review_dir)"
  second_start="$(cat "$fix/agent-cwd" 2>/dev/null)"
  assert "two reviews start from the same stable directory" test "$first_start" == "$second_start"
  assert "the stable review start directory is the trust path" test "$first_start" == "$rt/vgshell/updates/review"
  assert "two reviews keep separate per-run directories" test "$first_dir" != "$second_dir"
  assert "both review directories are inside the stable start directory" test "${first_dir%/*}:${second_dir%/*}" == "$rt/vgshell/updates/review:$rt/vgshell/updates/review"
}
# r4: a flagged verdict asks per package, Skip or Install anyway: Skip
# keeps it out of its own upgrade step and lists it skipped, Install anyway
# installs it, and the run goes on either way.
row_review_flagged() {
  reset_fix
  third_party
  printf 'verdict flagged\nflag tool-bin Its source moved to a new domain.\nflag foo The repository is unsigned.\n' >"$fix/verdict"
  PIPE_PATH="$agents" pipeline update.sh
  assert "a flagged review asks Skip or Install anyway for each package" has_call "gum confirm --affirmative=Skip --negative=Install anyway -- Skip tool-bin, or install it anyway?"
  assert "a skipped repository package is kept out of the system step" has_call "vgshell pkg run upgrade --manager pacman --ignore foo"
  assert "a skipped AUR package is kept out of the AUR step" has_call "vgshell pkg run upgrade --manager aur --ignore tool-bin"
  assert "a skipped package is listed skipped" out_has "tool-bin: skipped, the review flagged it"
  assert "a run that skipped packages exits 0" test "$status" == 0
  settings "paru -Sua --devel" false
  PIPE_PATH="$agents" pipeline update.sh
  assert "both skipped packages are kept out of the aurCommand, which may sync the system" has_call "paru -Sua --devel --ignore tool-bin --ignore foo"
  settings "" false
  echo 1 >"$fix/answer-skip"
  PIPE_PATH="$agents" pipeline update.sh
  assert "Install anyway runs the run to its end" test "$status" == 0
  assert "Install anyway installs the AUR package" has_call "vgshell pkg run upgrade --manager aur"
  assert "Install anyway installs the repository package" has_call "vgshell pkg run upgrade --manager pacman"
  assert "Install anyway lists nothing skipped" out_lacks "skipped, the review flagged it"
  # A behind vgshell-git, as row_vgs_git's, is reviewed for its rebuild,
  # and skipping it keeps the rebuild out.
  reset_fix
  third_party
  self_json package '"vgshell-git"' true
  touch "$fix/owner" "$fix/owner-changes" "$fix/running"
  printf 'verdict flagged\nflag vgshell-git Its source moved to a new domain.\n' >"$fix/verdict"
  PIPE_PATH="$agents" pipeline update.sh
  assert "the rebuilt vgshell-git is reviewed" grep -qxF "aur vgshell-git ? ?" "$fix/packages-seen"
  assert "the rebuilt vgshell-git's installed version is asked of pacman" has_call "pacman -Q vgshell-git"
  assert "a skipped vgshell-git is not rebuilt" no_call "paru -S vgshell-git"
  assert "a skipped vgshell-git leaves the AUR step to the rest" has_call "vgshell pkg run upgrade --manager aur --ignore vgshell-git"
}
# r5: no verdict asks to go on without a review, default no; a no stops
# the run. A review the service refuses to open is no verdict too.
row_review_no_verdict() {
  reset_fix
  third_party
  echo 1 >"$fix/answer-continue"
  PIPE_PATH="$agents" pipeline update.sh
  assert "no verdict asks to go on, default no" has_call "gum confirm --default=false -- Continue without a review?"
  assert "no verdict stopped exits 0" test "$status" == 0
  assert "no verdict stopped upgrades nothing" test "$(grep -c -e '^sudo' -e 'pkg run' "$tmp/seq")" == 0
  assert "no verdict names its cause in the developer log" diag_has "updates: review=none verdict=absent"
  # The service refuses to open the window.
  touch "$fix/ipc-refuses"
  PIPE_PATH="$agents" pipeline update.sh
  assert "a refused review window asks to go on" has_call "gum confirm --default=false -- Continue without a review?"
  assert "a refused review window names the refusal in the developer log" diag_has "updates: review=none open=refused: tui=review reason=launcher-missing exit=0"
  # The window's run ends without starting: the wait ends on `ended`.
  rm -f -- "$fix/ipc-refuses"
  touch "$fix/ipc-ended"
  PIPE_PATH="$agents" pipeline update.sh
  assert "a review run that never started asks to go on" has_call "gum confirm --default=false -- Continue without a review?"
  assert "a review run that never started names its end in the developer log" diag_has "updates: review=none start=none ended=reason=launcher-failed"
  # The packages cannot be listed.
  rm -f -- "$fix/ipc-ended"
  printf '[{"source":"aur","count":null,"packages":[],"checkedAt":"x","error":"exit=1"}]\n' >"$fix/check-aur.json"
  PIPE_PATH="$agents" pipeline update.sh
  assert "an unreadable list asks to go on" has_call "gum confirm --default=false -- Continue without a review?"
  assert "an unreadable list stopped upgrades nothing" test "$(grep -c -e '^sudo' -e 'pkg run' "$tmp/seq")" == 0
  assert "an unreadable list opens no review" no_call "$review_call"
  assert "an unreadable list names its cause in the developer log" diag_has "updates: review=none list=unreadable"
}
# The AUR through an aurCommand helper the table does not know: the AUR is
# not reviewed, and the repository packages still are.
row_review_no_helper() {
  reset_fix
  third_party
  printf 'verdict clean\n' >"$fix/verdict"
  printf '{"primary":{"id":"pacman","binary":"pacman"},"overlays":[{"id":"flatpak","binary":"flatpak"}],"sources":[]}\n' >"$fix/detect.json"
  settings "pikaur -Sua" false
  PIPE_PATH="$agents" pipeline update.sh
  assert "an unknown helper's AUR is not listed" no_call "vgshell pkg check --json --source aur"
  assert "an unknown helper's AUR still has the repository packages reviewed" test "$(cat "$fix/packages-seen" 2>/dev/null)" == "$(printf '%s\n' "repo chaotic foo 2-1 3-1" "server chaotic https://chaotic.example/x86_64" "siglevel chaotic Optional TrustAll")"
  assert "an unknown helper's AUR step still runs" has_call "pikaur -Sua"
}
# r7: an edited command runs as written.
row_review_custom() {
  reset_fix
  third_party
  printf 'verdict clean\n' >"$fix/verdict"
  settings "" false true "" "my-agent --model x  --yolo"
  PIPE_PATH="$agents" pipeline update.sh
  assert "an edited command runs as written" has_call "my-agent --model x --yolo"
  assert "an edited command runs instead of the default" no_call "claude"
}
# The 1password install script at AUR commit e4388fb, 8.12.38, which
# d0a8a7e, 8.12.40, ships unchanged.
onepassword_install() {
  cat <<'SH'
# Do not add your user, or any others, to this group.
GROUP_NAME="onepassword"

app_group_exists() {
    if [ $(getent group "${GROUP_NAME}") ]; then
        true
    else
        false
    fi
}

setup_browser_helper() {
    # Setup the Core App Integration helper binary with the correct permissions and group
    BROWSER_SUPPORT_PATH="/opt/1Password/1Password-BrowserSupport"

    chgrp "${GROUP_NAME}" $BROWSER_SUPPORT_PATH
    chmod g+s $BROWSER_SUPPORT_PATH
}

pre_install() {
    if app_group_exists; then
        : # Do nothing
    else
        groupadd "${GROUP_NAME}"
    fi
}

pre_upgrade() {
    if app_group_exists; then
        : # Do nothing
    else
        groupadd "${GROUP_NAME}"
    fi
}

post_install() {
    setup_browser_helper
}

post_upgrade() {
    setup_browser_helper
}

post_remove() {
    if app_group_exists; then
        groupdel "${GROUP_NAME}"
    fi
}
SH
}
# 1password pending 8.12.38 -> 8.12.40: the installed script in pacman's
# local database, and the fetched build files naming theirs.
onepassword_pending() {
  printf '[{"source":"aur","count":1,"packages":[{"name":"1password","old":"8.12.38-1","new":"8.12.40-1"}],"checkedAt":"x","error":null}]\n' >"$fix/check-aur.json"
  mkdir -p "$fix/db/local/1password-8.12.38-1" "$fix/build-1password"
  onepassword_install >"$fix/db/local/1password-8.12.38-1/install"
  printf 'pkgbase = 1password\n\tpkgver = 8.12.40\n\tinstall = 1password.install\n\npkgname = 1password\n' >"$fix/build-1password/.SRCINFO"
  onepassword_install >"$fix/build-1password/1password.install"
  printf 'verdict clean\n' >"$fix/verdict"
}
# An install script is judged by its change: the same script asks nothing
# under a clean verdict, though it sets a setgid bit and adds a group; a
# change that adds a setgid line asks, whatever the agent said.
row_review_install() {
  reset_fix
  onepassword_pending
  PIPE_PATH="$agents" pipeline update.sh
  assert "an unchanged install script is named unchanged to the agent" grep -qxF "install 1password unchanged" "$fix/packages-seen"
  assert "an unchanged install script asks nothing" no_call "gum confirm --affirmative=Skip"
  assert "an unchanged install script's package installs" has_call "vgshell pkg run upgrade --manager aur"
  reset_fix
  onepassword_pending
  printf 'chmod 2755 /opt/1Password/extra\n' >>"$fix/build-1password/1password.install"
  PIPE_PATH="$agents" pipeline update.sh
  assert "a changed install script is named changed to the agent" grep -qxF "install 1password changed" "$fix/packages-seen"
  assert "a changed install script's diff is in the run's own directory" grep -qxF "install/1password.diff" "$fix/build-seen"
  assert "an added setgid line asks under a clean verdict" has_call "gum confirm --affirmative=Skip --negative=Install anyway -- Skip 1password, or install it anyway?"
  assert "an added setgid line is named above the question" out_has "1password: The install script adds: chmod 2755 /opt/1Password/extra"
  assert "a skipped changed script's package is kept out" has_call "vgshell pkg run upgrade --manager aur --ignore 1password"
}

# The fetched tree is untrusted: the diff is written outside it, so a link
# the AUR repository planted is never written through, and an install
# script that is a link, or that is not there, is not read and is flagged.
row_review_install_links() {
  reset_fix
  onepassword_pending
  printf 'chmod 2755 /opt/1Password/extra\n' >>"$fix/build-1password/1password.install"
  printf 'mine\n' >"$fix/victim"
  ln -s -- "$fix/victim" "$fix/build-1password/install.diff"
  PIPE_PATH="$agents" pipeline update.sh
  assert "a link planted in the build files is never written through" test "$(cat "$fix/victim")" == mine
  assert "a changed script's diff is in the run's own directory" grep -qxF "install/1password.diff" "$fix/build-seen"
  reset_fix
  onepassword_pending
  printf 'mine\n' >"$fix/secret"
  ln -sf -- "$fix/secret" "$fix/build-1password/1password.install"
  PIPE_PATH="$agents" pipeline update.sh
  assert "an install script that is a link is named unread to the agent" grep -qxF "install 1password unread" "$fix/packages-seen"
  assert "an install script that is a link is named above the question" out_has "1password: The install script is a link or not a regular file."
  assert "an install script that is a link asks under a clean verdict" has_call "gum confirm --affirmative=Skip --negative=Install anyway -- Skip 1password, or install it anyway?"
  reset_fix
  onepassword_pending
  rm -- "${fix:?}/build-1password/1password.install"
  PIPE_PATH="$agents" pipeline update.sh
  assert "an install script .SRCINFO names that is not there is named unread" grep -qxF "install 1password unread" "$fix/packages-seen"
}
# A split base, base-utils: its base section and two of its packages name
# their own install scripts, and a third package takes the base's. Each
# installed script is the old text; only b.install adds a setgid line.
split_pending() { # NAME
  printf '[{"source":"aur","count":1,"packages":[{"name":"%s","old":"1.0-1","new":"1.1-1"}],"checkedAt":"x","error":null}]\n' "$1" >"$fix/check-aur.json"
  echo base-utils >"$fix/base-$1"
  mkdir -p "$fix/build-base-utils" "$fix/db/local/a-utils-1.0-1" "$fix/db/local/b-utils-1.0-1"
  printf 'pkgbase = base-utils\n\tpkgver = 1.1\n\tinstall = base.install\n\npkgname = a-utils\n\tinstall = a.install\n\npkgname = b-utils\n\tinstall = b.install\n\npkgname = c-utils\n' >"$fix/build-base-utils/.SRCINFO"
  local old
  old="$(printf 'post_install() {\n    true\n}')"
  local file
  for file in "$fix/build-base-utils/base.install" "$fix/build-base-utils/a.install" "$fix/db/local/a-utils-1.0-1/install" "$fix/db/local/b-utils-1.0-1/install"; do
    printf '%s\n' "$old" >"$file"
  done
  printf '%s\nchmod 2755 /opt/b/extra\n' "$old" >"$fix/build-base-utils/b.install"
  printf 'verdict clean\n' >"$fix/verdict"
}
row_review_split() {
  reset_fix
  split_pending b-utils
  PIPE_PATH="$agents" pipeline update.sh
  assert "a split package's own install script is judged" grep -qxF "install b-utils changed" "$fix/packages-seen"
  assert "a split package's added setgid line asks" has_call "gum confirm --affirmative=Skip --negative=Install anyway -- Skip b-utils, or install it anyway?"
  reset_fix
  split_pending c-utils
  PIPE_PATH="$agents" pipeline update.sh
  assert "a split package with no install line of its own takes its base's" grep -qxF "install c-utils new" "$fix/packages-seen"
  reset_fix
  split_pending d-utils
  PIPE_PATH="$agents" pipeline update.sh
  assert "a package no fetched .SRCINFO names is named unread" grep -qxF "install d-utils unread" "$fix/packages-seen"
  assert "a package no fetched .SRCINFO names is flagged" out_has "d-utils: Could not find the install script."
  assert "a package no fetched .SRCINFO names asks" has_call "gum confirm --affirmative=Skip --negative=Install anyway -- Skip d-utils, or install it anyway?"
}

row_full; row_trusted; row_snapshot; row_failure; row_cause; row_system_failed; row_hangup; row_stopped; row_interrupted; row_reboot; row_reboot_core; row_reboot_unread; row_orphans; row_yes
row_declined; row_busy; row_aur_command; row_aur_failure; row_doas; row_vgs_only; row_vgs_git; row_source; row_recheck_failure; row_log
row_review_off; row_review_no_agent; row_review_none_pending; row_review_clean; row_review_start_stable; row_review_flagged; row_review_no_verdict; row_review_no_helper; row_review_custom; row_review_install
row_review_install_links; row_review_split

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
control aur-before-revoke 'if [[ $session == 1 ]]; then vgs_tui_sudo_session end; fi' \
  'if [[ $session == 1 ]]; then "$_updates_vgshell" pkg run upgrade --manager aur; vgs_tui_sudo_session end; fi' row_full
control passes-yes '_updates_yes_flag=()' '_updates_yes_flag=(--yes)' row_full
control aur-unguarded '      vgs_tui_sudo_session guard' '      :' row_aur_failure
control session-ignores-elevator 'if [[ $elevator == sudo ]]; then session=1; fi' 'if command -v sudo >/dev/null; then session=1; fi' row_doas
control snapshot-ignores-elevator '_updates_snapshot "$snapshot_tool" "$elevator" || status=$?' '_updates_snapshot "$snapshot_tool" sudo || status=$?' row_doas
control rebuild-unguarded 'if [[ $upgrades == 1 || $rebuild == 1 ]]; then replaces=1; fi' 'if [[ $upgrades == 1 ]]; then replaces=1; fi' row_vgs_only
control no-recovery "trap '_updates_failed \$?' ERR" ':' row_stopped
control no-reboot-check '  _updates_reboot "${_updates_core[@]}"' '  :' row_reboot
control no-success-recheck '  _updates_recheck "$ended"' '  :' row_reboot
control no-failure-recheck '  _updates_recheck failed' '  :' row_stopped
control source-stops-run '"$_updates_cause_file" >&2) || status=$?' '"$_updates_cause_file" >&2)' row_failure
control tee-hangs-up ">(trap '' HUP; exec tee" '>(exec tee' row_hangup
control key-at-line-start '(^|[[:space:]])(vgshell|vgs-tui):' '(^)(vgshell|vgs-tui):' row_full
control refusal-cause-held '    _updates_cause="${after:-$value}"' '    _updates_cause="$held"' row_cause
control rescan-cause-after 'own="${tail:-$held}" _updates_cause="${held:-${after:-$value}}"' 'own="${tail:-$held}" _updates_cause="${after:-$value}"' row_cause
control question-tail-ignored 'own="${tail:-$held}"' 'own="$held"' row_cause
control question-unread 'if [[ $own =~' 'if false && [[ $own =~' row_cause
control answered-question-kept 'then line="${BASH_REMATCH[2]}"; fi' 'then :; fi' row_cause
control aur-after-failed-system 'if [[ -n $aur_blocked ]]; then' 'if false; then' row_system_failed
control aur-after-declined-system '            declined) aur_blocked=' '            declined) ;; x) aur_blocked=' row_system_failed
control reboot-read-silent '  vgs_tui_warn "Could not check which updates need a restart."' '  :' row_reboot_unread
control reboot-warns-twice '  [[ $_updates_reboot_warned == 0 ]] || return 0' '  :' row_reboot_unread
control diff-in-fetched-tree '>"$dir/install/$name.diff"' '>"$_updates_install_dir/install.diff"' row_review_install_links
control install-link-read 'if [[ $file == */* || ! -f $new || -L $new ]]; then' 'if [[ $file == */* || ! -f $new ]]; then' row_review_install_links
control srcinfo-first-install-line '            base) base_file="$value" ;;' '            *) [[ $own_set == 1 ]] || own_file="$value" own_set=1 ;;' row_review_split
control srcinfo-base-ignored '            base) base_file="$value" ;;' '            base) ;;' row_review_split
control unfound-reads-none '    if ! _updates_install_name "$dir/build" "$name"; then' '    if ! _updates_install_name "$dir/build" "$name"; then _updates_install_file="" _updates_install_dir=""; elif false; then' row_review_split
control cause-keeps-escapes 'sed -E -e $'"'"'s/\e' 'sed -E -e $'"'"'s/NEVER\e' row_failure
control failure-exits-0 '  [[ $ended == success ]] || exit 1' '  :' row_failure
control interrupt-goes-on 'if [[ $status -eq 130 ]]; then' 'if false; then' row_interrupted
control declined-fails 'if [[ $_updates_declined == 1 ]]; then' 'if false; then' row_full
control reboot-ignores-upgrades 'if [[ $# -gt 0 ]]; then' 'if false; then' row_reboot_core
control reboot-ignores-hook '[[ ! -f ${root%/}/$_updates_reboot_hook ]] || hook="${root%/}/$_updates_reboot_hook"' ':' row_reboot_core
control reboot-ignores-targets '&& targetsMatch(trigger.targets, change.name);' ';' row_reboot_core UpdatesLogic.js
control reboot-ignores-mounts "printf 'mounted %s\\n' \"\$value\"" ':' row_reboot_core
control reboot-facts-stops-run '} | _updates_facts reboot "$hook" /proc/version)" || status=$?' '} | _updates_facts reboot "$hook" /proc/version)"' row_reboot_core
control reboot-new-as-upgrade 'then changes+=("install $name")' 'then changes+=("upgrade $name")' row_reboot_core
control install-anyway-ignored '      1) echo "Installing $name anyway." ;;' '      1) _updates_skip_aur+=("$name"); _updates_skip_repo+=("$name") ;;' row_review_flagged
control skip-aur-installed 'if _updates_in "$name" "${_updates_review_aur[@]}"; then _updates_skip_aur+=("$name"); fi' ':' row_review_flagged
control risks-unasked '        risk) _updates_review_risks+=("$name The install script adds: $value") ;;' '        risk) ;;' row_review_install
control installed-script-unread 'installed="${db%/}/local/$name-$old/install"; fi' 'installed=-; fi' row_review_install
control orphans-default-yes 'orphaned package(s)?" --default=false || status=$?' 'orphaned package(s)?" || status=$?' row_orphans
control log-clobbers 'vgs_tui_log "$UPDATES_LOG_PART"' 'vgs_tui_log "$_updates_log"' row_busy
control unasked-start 'vgs_tui_confirm "Start the update?" || status=$?' 'true || status=$?' row_declined
control log-elsewhere 'printf '"'"'%s\n'"'"' "$(updates_state_dir)/update.log"' 'printf '"'"'%s\n'"'"' "$(updates_state_dir)/other.log"' row_log
control log-absent-opens '[[ -f $log ]] || _updates_refuse 1' '[[ -n $log ]] || _updates_refuse 1' row_log tui/log.sh
control log-closes-unread "trap 'status=\$?; [[ \$status == 0 ]] || vgs_tui_close_prompt \"\$status\"' EXIT" ':' row_log tui/log.sh
control unknown-source-unchecked '_updates_refuse 2 "source=$only reason=unknown"' \
  ': 2 "source=$only reason=unknown"' row_source
control review-ignores-toggle 'if (s.reviewThirdParty !== true) return' 'if (false) return' row_review_off UpdatesLogic.js
control review-ignores-path 'return table.REVIEW_AGENTS.map(row => row.id).filter(onPath);' 'return table.REVIEW_AGENTS.map(row => row.id);' row_review_no_agent bin/facts
control review-without-packages 'if [[ ${#reviewed[@]} -gt 0 ]]; then' 'if true; then' row_review_none_pending
control verdict-before-unlock '  flock "$lock"' '  :' row_review_clean
control review-starts-from-run-dir 'cd -- "${dir%/*}"' 'cd -- "$dir"' row_review_start_stable tui/review.sh
control prompt-placeholder-kept 'prompt="${prompt//\{review_dir\}/$dir}"' 'prompt="$prompt"' row_review_clean tui/review.sh
control skip-not-passed 'ignore=(--ignore "${_updates_skip_repo[@]}")' 'ignore=()' row_review_flagged
control no-verdict-continues '"Continue without a review?" --default=false || status=$?' '"Continue without a review?" || status=$?' row_review_no_verdict
control custom-replaced 'if (words.length > 0) {' 'if (false) {' row_review_custom UpdatesLogic.js
control list-failure-unreviewed '        review=2' '        review=0' row_review_no_verdict
control refusal-unread 'if [[ $status -ne 0 || $reply != ok ]]; then _updates_review_reason=' 'if false; then _updates_review_reason=' row_review_no_verdict
control end-unread 'while [[ ! -e $dir/started && ! -e $dir/ended ]] && ((polls < 300)); do' 'while [[ ! -e $dir/started ]] && ((polls < 300)); do' row_review_no_verdict
control rebuild-of-skipped 'if [[ $rebuild == 1 ]] && ! _updates_in vgshell-git "${_updates_skip_aur[@]}"; then' 'if [[ $rebuild == 1 ]]; then' row_review_flagged
control rebuild-unreviewed 'if [[ $4 == 1 ]] && ! _updates_in vgshell-git' 'if false && ! _updates_in vgshell-git' row_review_flagged
control session-before-review '  if [[ $review == 1 ]]; then _updates_review 1' '  if [[ $session == 1 ]]; then vgs_tui_sudo_session start; fi; if [[ $review == 1 ]]; then _updates_review 1' row_review_clean
control credentials-kept 'if [[ $line =~ ^([^:/]+://)[^/@]*@(.*)$ ]]; then' 'if false; then' row_review_clean
control agent-fetches 'if ! (cd -- "$dir/build" && "$_updates_review_helper" -G "${_updates_review_aur[@]}"); then' 'if false; then' row_review_clean
control aur-command-keeps-repository 'for name in "${_updates_skip_aur[@]}" "${_updates_skip_repo[@]}"; do' 'for name in "${_updates_skip_aur[@]}"; do' row_review_flagged
control aur-reviewed-without-helper '      if [[ -n $aur_binary ]]; then review_aur=1' '      if true; then review_aur=1' row_review_no_helper

rows_done test-updates-pipeline
