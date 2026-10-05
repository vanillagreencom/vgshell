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
# runs, so /proc names its executable deleted.
#
# The review rows put stand-in agent CLIs on PATH, each recording its argv
# but the prompt, which it keeps beside its working directory and the
# packages.txt it was handed, and writing the verdict the row planted. The
# stand-in vgshell answers the service's `review` IPC call by running the
# shipped tui/review.sh of the copy in the background, as the review TUI
# would, and writes the review directory's `ended` after it, as the
# service's `done` does. No row reaches a real agent or the network.
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
# $FIX/elevator; `pkg run` fails with 9 for a manager $FIX/fail-<id> names;
# `pkg owner` answers only while $FIX/owner exists, with a new version after
# its first answer when $FIX/owner-changes does.
stub "$tree/bin" vgshell 'case "$1 $2" in
  "plugin settings") cat "$FIX/settings.json" ;;
  "pkg detect") cat "$FIX/detect.json" ;;
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
  "pkg run") [ ! -e "$FIX/fail-$5" ] || exit 9 ;;
  "pkg check")
    if [ -e "$FIX/check-$5.json" ]; then cat "$FIX/check-$5.json"
    else echo "[{\"source\":\"$5\",\"count\":0,\"packages\":[],\"checkedAt\":\"x\",\"error\":null}]"
    fi ;;
  "ipc call")
    if [ -e "$FIX/ipc-refuses" ]; then echo "refused: tui=review reason=launcher-missing"; exit 0; fi
    ( bash "$VGS_PLUGIN_DIR/tui/review.sh" "$6"; echo "code=$?" >"$6/ended" ) </dev/null >/dev/null 2>&1 &
    echo ok ;;
  "pkg owner")
    [ -e "$FIX/owner" ] || exit 1
    v=1
    if [ -e "$FIX/owner-asked" ] && [ -e "$FIX/owner-changes" ]; then v=2; fi
    : >"$FIX/owner-asked"
    echo "{\"manager\":\"pacman\",\"package\":\"vgshell-git\",\"version\":\"0.1.0.r$v\"}" ;;
  "pid ") [ -e "$FIX/running" ] || exit 69; echo 42 ;;
esac'
# gum confirm answers the exit status in $FIX/answer-<question>, 0 when
# absent; style prints its lines.
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
stub "$stubs" pacman 'if [ "$1" = -Sl ]; then cat "$FIX/sl-$2"; exit; fi
[ -e "$FIX/orphans" ] || exit 1; cat "$FIX/orphans"'
stub "$stubs" pacman-conf 'case "$1 ${3:-}" in
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
cat packages.txt >"$FIX/packages-seen"
sleep 0.5
[ ! -e "$FIX/verdict" ] || cat "$FIX/verdict" >verdict
SH
  chmod +x "$agents/$agent"
done
stub "$stubs" df 'a=99999999999; [ ! -e "$FIX/avail" ] || read -r a <"$FIX/avail"; printf "  Avail\n%s\n" "$a"'
stub "$stubs" pgrep '[ -e "$FIX/pids" ] || exit 1; cat "$FIX/pids"'
stub "$stubs" uname "echo $kernel"
stub "$stubs" systemctl ''
# paru authorizes through sudo and fails with 7 while $FIX/fail-paru exists.
stub "$stubs" paru '[ ! -e "$FIX/fail-paru" ] || { sudo /usr/bin/true; exit 7; }'
stub "$stubs" less ''
for tool in bash env readlink dirname mkdir mv rm script flock sleep cat id; do
  found="$(command -v "$tool")" || { echo "test-updates-pipeline: status=not-measured missing=$tool"; exit 77; }
  ln -s -- "$(readlink -f -- "$found")" "$tools/$tool"
done
ln -s -- "$node_bin" "$tools/node"

cp -- "$(command -v sleep)" "$tmp/Hyprland"
"$tmp/Hyprland" 300 &
hyprland_pid=$!
trap 'kill "$hyprland_pid" 2>/dev/null; rm -rf -- "${tmp:?}"' EXIT
rm -- "$tmp/Hyprland"

settings() { # AUR_COMMAND TRUST [REVIEW AGENT COMMAND]
  printf '{"intervalHours":6,"hideWhenCurrent":false,"aurCommand":"%s","snapshot":"auto","trustPluginUpdates":%s,"reviewThirdParty":%s,"reviewAgent":"%s","reviewCommand":"%s","placement":"center"}\n' \
    "$1" "$2" "${3:-true}" "${4:-}" "${5:-}" >"$fix/settings.json"
}
self_json() { # METHOD PACKAGE_JSON BEHIND
  printf '{"version":"0.1.0","method":"%s","package":%s,"current":"a","latest":"b","behind":%s,"error":null}\n' "$1" "$2" "$3" >"$fix/self.json"
}
# The fixture every row starts from: pacman with the AUR through paru,
# Flatpak and mise; a checkout one commit behind; one plugin and one theme
# behind; no snapshot tool, no orphan, no replaced Hyprland, every answer yes.
reset_fix() {
  rm -rf -- "${fix:?}" "$state/vgshell"
  mkdir -p "$fix"
  settings "" false
  echo sudo >"$fix/elevator"
  printf '{"primary":{"id":"pacman","binary":"pacman"},"overlays":[{"id":"aur","binary":"paru"},{"id":"flatpak","binary":"flatpak"}],"sources":[{"id":"mise","binary":"mise"}]}\n' >"$fix/detect.json"
  self_json checkout null true
  printf '[{"id":"acme.one","behind":2,"head":"h","upstream":"u","error":null},{"id":"acme.two","behind":0,"head":"h","upstream":"h","error":null}]\n' >"$fix/plugins.json"
  printf '[{"id":"night","behind":1,"head":"h","upstream":"u","error":null}]\n' >"$fix/themes.json"
}

# Third-party updates: one AUR package, and beside linux from core one
# package of chaotic, a repository that is not official, whose servers
# and signature level the review lists.
third_party() {
  printf '[{"source":"aur","count":1,"packages":[{"name":"tool-bin","old":"1.0-1","new":"1.1-1"}],"checkedAt":"x","error":null}]\n' >"$fix/check-aur.json"
  printf '[{"source":"pacman","count":2,"packages":[{"name":"linux","old":"6.1-1","new":"6.2-1"},{"name":"foo","old":"2-1","new":"3-1"}],"checkedAt":"x","error":null}]\n' >"$fix/check-pacman.json"
  printf 'core\nextra\ncachyos-extra-znver4\nchaotic\n' >"$fix/repos"
  printf 'chaotic foo 3-1 [installed: 2-1]\nchaotic bar 1-1\n' >"$fix/sl-chaotic"
  printf 'https://chaotic.example/x86_64\n' >"$fix/server-chaotic"
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
  grep -v -e '^df ' -e '^uname ' -e '^pgrep ' -e '^gum style' "$calls" >"$tmp/seq" || filtered=$?
  # grep -v exits 1 when every call is filtered out, and above 1 when it failed.
  [[ $filtered -le 1 ]] || { echo "test-updates-pipeline: calls=unreadable exit=$filtered" >&2; exit 1; }
}
seq_is() { [[ "$(cat "$tmp/seq")" == "$(printf '%s\n' "$@")" ]]; } # LINE...
has_call() { grep -qxF -- "$1" "$tmp/seq"; }
no_call() { ! grep -q -- "^$1" "$tmp/seq"; } # PREFIX
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
  "vgshell pkg owner $tree/VERSION" "sudo -k" "sudo /usr/bin/true" "vgshell self update"
  "vgshell pkg run upgrade --manager pacman" "vgshell pkg run upgrade --manager flatpak" "vgshell pkg run upgrade --manager mise"
  "vgshell plugin update acme.one" "vgshell theme update night" "sudo -k"
  "vgshell pkg run upgrade --manager aur" "sudo -k" "pacman -Qtdq")
row_full() {
  reset_fix
  pipeline update.sh
  assert "a full run exits 0" test "$status" == 0
  assert "a full run takes every step in order, the AUR after the session ends" seq_is "${full_seq[@]}"
  assert "a plugin update gets no --yes by default" has_call "vgshell plugin update acme.one"
  assert "no snapshot tool warns nothing" out_lacks "snapshot=failed"
  assert "no snapshot tool keeps the update going quietly" out_lacks "without a snapshot"
  assert "the log keeps the plan box" grep -qF "Update everything" "$log"
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
row_failure() {
  reset_fix
  touch "$fix/fail-pacman"
  pipeline update.sh
  assert "a failed system step ends the run with its status" test "$status" == 9
  assert "a failed step names the log in its recovery message" out_has "Select Open last log in Updates to read this run's output."
  assert "the failure code stays in the developer log" grep -qF "updates: failed exit=9" "$state/vgshell/updates/diagnostics.log"
  assert "a failed step drops the credential last" test "$(tail -n 1 "$tmp/seq")" == "sudo -k"
  assert "a failed step runs no AUR" test "$(grep -c 'manager aur' "$tmp/seq")" == 0
}
row_reboot() {
  reset_fix
  printf '%s\n' "$hyprland_pid" >"$fix/pids"
  pipeline update.sh
  assert "a replaced Hyprland asks to reboot" has_call "gum confirm -- Hyprland was updated. Reboot now?"
  assert "a yes reboots" test "$(tail -n 1 "$tmp/seq")" == "systemctl reboot"
  echo 1 >"$fix/answer-reboot"
  pipeline update.sh
  assert "a no does not reboot" test "$(grep -c '^systemctl' "$tmp/seq")" == 0
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
# dropped, after it, and the run ends with the helper's status and the
# recovery message.
row_aur_failure() {
  reset_fix
  settings "paru -Sua --devel" false
  touch "$fix/fail-paru"
  pipeline update.sh
  assert "a failed AUR step ends the run with its status" test "$status" == 7
  assert "a failed AUR step names the log in its recovery message" out_has "Select Open last log in Updates to read this run's output."
  assert "a failed AUR step drops the credential it cached, last" test "$(tail -n 1 "$tmp/seq")" == "sudo -k"
  assert "the credential is dropped after the failed AUR step" before "paru -Sua --devel" "sudo -k"
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
  assert "a VGS rebuild alone upgrades no other package" test "$(grep -c -e 'pkg run' -e '^pacman' "$tmp/seq")" == 0
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
    "gum confirm -- Start the update?" "vgshell pkg run upgrade --manager flatpak"
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
  grep -v -e '^df ' -e '^uname ' -e '^pgrep ' -e '^gum style' "$calls" >"$tmp/seq" || filtered=$?
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

# The third-party review (pipeline.md § Third-party review). Each row has
# the third-party updates pending; review_dir is the review directory the
# run asked the service to open, from its recorded IPC call.
review_call="vgshell ipc call vgs.updates invoke review "
review_dir() { sed -n "s|^$review_call||p" "$tmp/seq" | head -n 1; }
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
# prompt, from the review directory, before any credential, and the run
# goes on with no package kept out.
row_review_clean() {
  reset_fix
  third_party
  printf 'verdict clean\n' >"$fix/verdict"
  PIPE_PATH="$agents" pipeline update.sh
  local dir
  dir="$(review_dir)"
  assert "a clean review exits 0" test "$status" == 0
  assert "the review directory is the run's own" test "${dir%.*}" == "$rt/vgshell/updates/review"
  assert "the box names the agent and the packages" out_has "Review: Claude Code checks 2 third-party packages: tool-bin, foo"
  assert "the agent runs the default command" has_call "claude --model opus --effort medium"
  assert "the agent's last argument is the bundled prompt" test "$(cat "$fix/prompt-seen" 2>/dev/null)" == "$(cat "$plugin/review/third-party.md")"
  assert "the agent runs in the review directory" test "$(cat "$fix/agent-cwd" 2>/dev/null)" == "$dir"
  assert "the agent is handed the third-party packages alone" test "$(cat "$fix/packages-seen" 2>/dev/null)" == "$(printf '%s\n' "helper paru" "aur tool-bin 1.0-1 1.1-1" "repo chaotic foo 2-1 3-1" "server chaotic https://chaotic.example/x86_64" "siglevel chaotic Optional TrustAll")"
  assert "the review comes before the sudo session" before "$review_call$dir" "sudo /usr/bin/true"
  assert "a clean verdict asks nothing more" no_call "gum confirm --default=false -- Continue without a review?"
  assert "a clean verdict runs the system step as it is" has_call "vgshell pkg run upgrade --manager pacman"
  assert "a clean verdict runs the AUR step as it is" has_call "vgshell pkg run upgrade --manager aur"
  assert "the review directory is removed" test ! -e "$dir"
}
# r4: a flagged verdict asks per package; a yes keeps it out of its own
# upgrade step, and a no stops the run before any step.
row_review_flagged() {
  reset_fix
  third_party
  printf 'verdict flagged\nflag tool-bin Its source moved to a new domain.\nflag foo The repository is unsigned.\n' >"$fix/verdict"
  PIPE_PATH="$agents" pipeline update.sh
  assert "a flagged review asks to skip each package" has_call "gum confirm -- Skip tool-bin?"
  assert "a skipped repository package is kept out of the system step" has_call "vgshell pkg run upgrade --manager pacman --ignore foo"
  assert "a skipped AUR package is kept out of the AUR step" has_call "vgshell pkg run upgrade --manager aur --ignore tool-bin"
  settings "paru -Sua --devel" false
  PIPE_PATH="$agents" pipeline update.sh
  assert "a skipped AUR package is kept out of the aurCommand" has_call "paru -Sua --devel --ignore tool-bin"
  echo 1 >"$fix/answer-skip"
  PIPE_PATH="$agents" pipeline update.sh
  assert "a flagged package not skipped stops the run with 0" test "$status" == 0
  assert "a stopped run upgrades nothing and asks no credential" test "$(grep -c -e '^sudo' -e 'pkg run' "$tmp/seq")" == 0
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
  touch "$fix/ipc-refuses"
  PIPE_PATH="$agents" pipeline update.sh
  assert "a refused review window starts no agent" no_call "claude"
  assert "a refused review window asks to go on" has_call "gum confirm --default=false -- Continue without a review?"
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

row_full; row_trusted; row_snapshot; row_failure; row_reboot; row_orphans; row_yes
row_declined; row_busy; row_aur_command; row_aur_failure; row_doas; row_vgs_only; row_vgs_git; row_source; row_log
row_review_off; row_review_no_agent; row_review_none_pending; row_review_clean; row_review_flagged; row_review_no_verdict; row_review_custom

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
control no-recovery "trap '_updates_failed \$?' ERR" ':' row_failure
control no-reboot-check '  _updates_reboot' '  :' row_reboot
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
control skip-not-passed 'ignore=(--ignore "${_updates_skip_repo[@]}")' 'ignore=()' row_review_flagged
control no-verdict-continues '"Continue without a review?" --default=false || status=$?' '"Continue without a review?" || status=$?' row_review_no_verdict
control custom-replaced 'if (words.length > 0) {' 'if (false) {' row_review_custom UpdatesLogic.js

rows_done test-updates-pipeline
