# shellcheck shell=bash
# tui/pipeline.sh: the Updates pipeline, sourced by tui/update.sh, which
# runs every source, and tui/update-source.sh, which runs one. Both hold one
# lock and one log and run the same steps in the same order; a source the
# run leaves out is skipped where its step would stand. bin/vgshell-tui runs
# both from a private copy of the plugin's snapshot, so bin/facts is beside
# this file's directory, and the VGS tree is the one VGS_TUI_LIB lies in.
# The order:
#
#   1. the log, script(1) into $XDG_STATE_HOME/vgshell/updates/update.log, then
#      the lock vgs-tui-updates; the run writes a file of its own that
#      becomes update.log once it holds the lock, so a second run refused
#      busy never truncates the log of the run it found
#   2. a warning when / has less than 10 GiB free
#   3. the plan box, then one question unless -y
#   4. the review of third-party packages, when the `reviewThirdParty`
#      setting is on, an agent resolves (UpdatesLogic.reviewPlan through
#      bin/facts review) and the AUR or a pacman repository that is not
#      official has an update pending: the run fetches the AUR build files
#      itself, and the agent runs in a second window, the `review` TUI,
#      which the service opens from the stable review start directory. The
#      per-run directory is inside it, so the agent's folder trust is
#      keyed on one path and the user trusts it once. The run waits for
#      the verdict, so a flagged package the user skips reaches its
#      upgrade step as `--ignore <name>`. The review runs before any
#      credential is cached: shell/plugins/vgs.updates/pipeline.md § Third-party review
#   5. one sudo session, when the package layer's elevation command is
#      sudo and a snapshot or the system step needs root. That command is
#      the one `vgshell pkg plan upgrade <primary>` names, from shell.json's
#      `packages.elevate`, else the first of sudo, doas and run0 on PATH;
#      doas and run0 ask as their own rules say, as bin/lib/pkg-run.sh does
#   6. a snapshot through snapper or timeshift behind that command, before
#      any step that replaces a package: the system's, the AUR's or the
#      vgshell-git rebuild. None is taken when the plugin's `snapshot` setting
#      is off, when neither tool is on PATH or when no elevation command
#      resolves, and the plan box says which; a failed snapshot warns and
#      the update goes on
#   7. VGS itself: `vgshell self update` for a checkout or a curl install
#   8. the system: `vgshell pkg run upgrade --manager <primary>`, which joins
#      the session
#   9. Flatpak and mise: `vgshell pkg run upgrade --manager flatpak|mise`
#  10. each plugin, then each theme, behind its upstream:
#      `vgshell plugin|theme update <id>`, which shows its diff and asks
#      [y/N]; `--yes` only when the `trustPluginUpdates` setting is on
#  11. the end of the sudo session, which drops the credential
#  12. the AUR, last, so no PKGBUILD runs under the update's credential:
#      the `aurCommand` setting's words, else `vgshell pkg run upgrade
#      --manager aur`, then `<helper> -S vgshell-git` when VGS is that package
#      and behind, since an AUR helper rebuilds a -git package only when
#      its recipe's version changes. The helper asks sudo itself, so the
#      phase runs under tui.sh's sudo guard: the credential it caches is
#      dropped when the phase ends, fails or is interrupted
#  13. pacman's orphaned packages, removed only on a yes, default no, after
#      a system or AUR upgrade
#  14. a shell restart when a package step or the rebuild replaced the VGS
#      package
#  15. a check request to refresh the widget and window
#  16. a reboot question when the kernel or the running Hyprland was
#      replaced (tui.sh's vgs_tui_reboot_check)
#
# The package steps are the package-manager table's own plans, read with
# `vgshell pkg plan` and run with `vgshell pkg run`: they take no -y, so each
# manager asks its own questions in this terminal. -y answers only the
# pipeline's own start question; the orphan and reboot questions are then
# reported instead of asked, and the review's questions are still asked. A plugin or theme update that fails or is
# declined warns and the run goes on. Any other failing step ends the run:
# the ERR trap prints `updates: failed exit=<n> log=<file>` and how to
# recover, and the session's or the guard's EXIT trap drops the credential.
#
# Every refusal prints `updates: refused: <key>=<value>` first. A bad
# invocation exits 2; a held lock exits 75.

# The ERR trap needs errtrace, so the file sets the mode its steps rely on
# whichever entry script sources it.
set -Eeuo pipefail
# Character classes spelled out: the user's locale collates a range.
_updates_digits='^[0123456789]+$'
_updates_usage="usage: update.sh [-y] | update-source.sh <source> [-y]"

_updates_diagnostic() { # RAW_LINE
  local dir
  dir="$(updates_state_dir)"
  mkdir -p -- "$dir"
  printf '%s\n' "$1" >>"$dir/diagnostics.log"
}

_updates_refuse() { # STATUS FIRST_LINE [ENGLISH...]
  local status="$1"
  if [[ -z ${VGS_TUI_LIB:-} ]]; then
    printf 'updates: refused: %s\n' "$2" >&2
  else
    _updates_diagnostic "updates: refused: $2"
    case "$2" in
      log=absent*) printf 'No update has run yet. There is no log to show.\n' >&2 ;;
      pager=missing) printf 'The log reader is unavailable. Open Updates to try again.\n' >&2 ;;
      source=missing) printf 'No update source was selected. Open Updates and choose a source.\n' >&2 ;;
      *reason=absent) printf 'This update source is not installed. Choose another source.\n' >&2 ;;
      *reason=no-plan) printf 'VGS cannot update this source. Choose another source.\n' >&2 ;;
      *) printf 'This update request is invalid. Open Updates and try again.\n' >&2 ;;
    esac
  fi
  exit "$status"
}

# The recovery message, printed once by the pipeline's own process: with
# errtrace a failing command inside a substitution runs the trap there too.
_updates_failed() { # STATUS
  [[ $BASHPID == "${_updates_pid:-}" ]] || return 0
  printf '\n' >&2
  _updates_diagnostic "updates: failed exit=$1 log=$_updates_log"
  _updates_recheck failed
  vgs_tui_error "The update stopped. Read the output above and try again from Updates."
  vgs_tui_error "Select Open last log in Updates to read this run's output."
}

# Runs ARGV from $HOME after a step line, as vgshell pkg run runs its steps,
# so a project's configuration in the caller's directory changes nothing.
_updates_run() { # LABEL ARGV...
  vgs_tui_step "$1"
  shift
  (cd -- "$HOME" && "$@")
}

# The directory a run writes its log in, and the last run's log in it,
# which tui/log.sh shows.
updates_state_dir() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/updates"
}
updates_log_file() {
  printf '%s\n' "$(updates_state_dir)/update.log"
}

# bin/facts VERB [SOURCE] on the answer on stdin.
_updates_facts() {
  "$_updates_facts_bin" "$_updates_loader" "$@"
}

# `vgshell pkg plan upgrade ID`: sets _updates_plan_text, the steps joined by
# `; `, and _updates_plan_elevator, the elevation command the steps run
# behind, empty when they need none or none resolves; or returns 1 with the
# refusal's first line in _updates_plan_text. A refusal that leaves no
# elevator, the elevator's or the plan's own, is in
# _updates_plan_elevator_refused.
_updates_plan() { # ID
  local out facts key value
  _updates_plan_text=""
  _updates_plan_elevator=""
  _updates_plan_elevator_refused=""
  if ! out="$("$_updates_vgshell" pkg plan upgrade "$1" 2>&1)"; then
    _updates_plan_text="${out%%$'\n'*}"
    _updates_plan_elevator_refused="$_updates_plan_text"
    return 1
  fi
  facts="$(_updates_facts plan <<<"$out")"
  while read -r key value; do
    case "$key" in
      elevator) _updates_plan_elevator="$value" ;;
      elevator-refused) _updates_plan_elevator_refused="$value" ;;
      step) _updates_plan_text+="${_updates_plan_text:+; }$value" ;;
    esac
  done <<<"$facts"
}

# The snapshot tool on PATH: snapper, else timeshift; 1 when neither is.
_updates_snapshot_tool() {
  if command -v snapper >/dev/null; then echo snapper
  elif command -v timeshift >/dev/null; then echo timeshift
  else return 1
  fi
}

# One snapshot per snapper configuration, or one timeshift snapshot, each
# command behind ELEVATOR. A tool with nothing configured takes none and
# says so: a quiet success would read as a snapshot the next update could
# roll back to.
_updates_snapshot() { # snapper|timeshift ELEVATOR
  local tool="$1" elevator="$2" csv config configs=() first=1
  case "$tool" in
    snapper)
      csv="$("$elevator" snapper --csvout list-configs)" || return
      while IFS=, read -r config _; do
        if [[ $first == 1 ]]; then first=0; continue; fi
        [[ -z $config ]] || configs+=("$config")
      done <<<"$csv"
      if [[ ${#configs[@]} -eq 0 ]]; then
        vgs_tui_warn "snapper has no configuration, so no snapshot was taken."
        return 1
      fi
      vgs_tui_step "Taking a snapshot"
      for config in "${configs[@]}"; do
        "$elevator" snapper -c "$config" create -c number -d "VGS update" || return
        "$elevator" snapper -c "$config" cleanup number || return
      done
      ;;
    timeshift)
      if [[ ! -f /etc/timeshift/timeshift.json ]]; then
        vgs_tui_warn "timeshift is not set up, so no snapshot was taken."
        return 1
      fi
      vgs_tui_step "Taking a snapshot"
      "$elevator" timeshift --create --comments "VGS update" --scripted || return
      ;;
    *) _updates_diagnostic "updates: snapshot-tool=$tool"; vgs_tui_error "The snapshot tool is not supported."; return 1 ;;
  esac
}

# The version of the package that owns the VGS tree, or nothing when no
# package owns it, as for a checkout, a curl install or a Nix tree, whose
# owner query refuses.
_updates_vgs_package_version() {
  local out facts key value
  out="$("$_updates_vgshell" pkg owner "$_updates_tree/VERSION" 2>/dev/null)" || return 0
  facts="$(_updates_facts owner <<<"$out")"
  while read -r key value; do
    if [[ $key == version ]]; then printf '%s' "$value"; fi
  done <<<"$facts"
}

# The plugins or themes behind their upstream, into _updates_behind; a
# checkout whose probe failed warns, and a probe that failed as a whole
# skips the source.
_updates_outdated() { # plugin|theme SOURCE
  local out facts key value
  _updates_behind=()
  if ! out="$("$_updates_vgshell" "$1" outdated --json)"; then
    _updates_diagnostic "updates: skipped=$2 reason=outdated-failed"; vgs_tui_warn "Could not check $2 for updates. This step was skipped."
    return 0
  fi
  facts="$(_updates_facts outdated "$2" <<<"$out")"
  while read -r key value; do
    case "$key" in
      update) _updates_behind+=("$value") ;;
      error) _updates_diagnostic "$2: $value"; vgs_tui_warn "Could not check one of the $2 for updates." ;;
    esac
  done <<<"$facts"
}

_updates_update_each() { # plugin|theme ID...
  local kind="$1" id status
  shift
  for id in "$@"; do
    vgs_tui_step "Updating the $kind $id"
    status=0
    "$_updates_vgshell" "$kind" update "${_updates_yes_flag[@]}" "$id" || status=$?
    if [[ $status -ne 0 ]]; then _updates_diagnostic "updates: $kind=$id exit=$status"; vgs_tui_warn "Could not update $id. The update continues."; fi
  done
}

_updates_orphans() {
  local out status=0 orphans=()
  out="$(pacman -Qtdq)" || status=$?
  # pacman -Qtdq exits 1 when no package is orphaned.
  if [[ $status -eq 1 && -z $out ]]; then return 0; fi
  if [[ $status -ne 0 ]]; then
    _updates_diagnostic "updates: orphans=unreadable exit=$status"; vgs_tui_warn "Could not check for unused packages. Package removal was skipped."
    return 0
  fi
  mapfile -t orphans <<<"$out"
  vgs_tui_step "Orphaned packages"
  printf '  %s\n' "${orphans[@]}"
  if [[ $_updates_yes == 1 ]]; then
    printf 'The unused packages were kept. Open Updates to review them.\n'
    return 0
  fi
  status=0
  vgs_tui_confirm "Remove ${#orphans[@]} orphaned package(s)?" --default=false || status=$?
  case "$status" in
    0) "$_updates_vgshell" pkg run remove --manager pacman "${orphans[@]}" || { _updates_diagnostic "updates: orphans=remove-failed exit=$?"; vgs_tui_warn "Could not remove the unused packages. Try again from Updates."; } ;;
    1) echo "Keeping the orphaned packages." ;;
    *) exit "$status" ;;
  esac
}

_updates_recheck() {
  local reply status=0
  reply="$("$_updates_vgshell" ipc call "$VGS_PLUGIN_ID" invoke check '' 2>&1)" || status=$?
  if [[ $status -ne 0 || ( $reply != started && $reply != queued ) ]]; then
    _updates_diagnostic "updates: recheck=failed exit=$status reply=${reply%%$'\n'*}"
  fi
}

_updates_reboot() {
  local out status=0 reason reasons=()
  out="$(vgs_tui_reboot_check)" || status=$?
  case "$status" in
    0) ;;
    1) return 0 ;;
    *) _updates_diagnostic "updates: reboot-check=failed exit=$status"; vgs_tui_warn "Could not check whether a restart is needed."; return 0 ;;
  esac
  while read -r reason; do
    case "$reason" in
      reboot=kernel) reasons+=("The kernel was updated.") ;;
      reboot=hyprland) reasons+=("Hyprland was updated.") ;;
    esac
  done <<<"$out"
  if [[ $_updates_yes == 1 ]]; then
    printf '%s Reboot when you are ready.\n' "${reasons[*]}"
    return 0
  fi
  status=0
  vgs_tui_confirm "${reasons[*]} Reboot now?" || status=$?
  case "$status" in
    0) systemctl reboot ;;
    1) echo "Reboot later to run the updated system." ;;
    *) exit "$status" ;;
  esac
}

# Whether WORD is one of the rest.
_updates_in() { # WORD LIST...
  local word="$1" item
  shift
  for item in "$@"; do [[ $item == "$word" ]] && return 0; done
  return 1
}

# The agent a review runs, from SETTINGS, the plugin's settings answer:
# _updates_review_state, _updates_review_label and _updates_review_words,
# the command's words, as bin/facts review prints UpdatesLogic.reviewPlan.
_updates_review_agent() { # SETTINGS
  local facts key value
  _updates_review_state="" _updates_review_label="" _updates_review_words=()
  facts="$(_updates_facts review <<<"$1")"
  while read -r key value; do
    case "$key" in
      review) _updates_review_state="$value" ;;
      label) _updates_review_label="$value" ;;
      word) _updates_review_words+=("$value") ;;
    esac
  done <<<"$facts"
}

# The third-party packages a review checks: the AUR's pending updates when
# AUR is 1, through HELPER, with vgshell-git when REBUILD is 1, since the
# rebuild builds it whether or not its recipe's version changed; and when
# REPO is 1 the system's pending updates that a pacman repository outside
# the official ones holds, with each such repository's servers, without the
# credentials a URL can carry, and signature level. Sets
# _updates_review_lines, the lines of packages.txt (review/third-party.md
# names their form), _updates_review_aur and _updates_review_repo, the
# names, and _updates_review_helper. Returns 1 after a diagnostic when a
# list cannot be read.
_updates_review_list() { # AUR REPO HELPER REBUILD
  local out facts key name old new repo repos=() listed line
  local -A pending=()
  _updates_review_lines=() _updates_review_aur=() _updates_review_repo=() _updates_review_helper="$3"
  if [[ $1 == 1 ]]; then
    if ! out="$("$_updates_vgshell" pkg check --json --source aur)" || ! facts="$(_updates_facts pending <<<"$out")"; then
      _updates_diagnostic "updates: review=unlisted source=aur"; return 1
    fi
    while read -r key name old new; do
      [[ $key == pending ]] || continue
      _updates_review_lines+=("aur $name $old $new")
      _updates_review_aur+=("$name")
    done <<<"$facts"
  fi
  if [[ $4 == 1 ]] && ! _updates_in vgshell-git "${_updates_review_aur[@]}"; then
    _updates_review_lines+=("aur vgshell-git ? ?")
    _updates_review_aur+=(vgshell-git)
  fi
  if [[ ${#_updates_review_aur[@]} -gt 0 ]]; then _updates_review_lines=("helper $3" "${_updates_review_lines[@]}"); fi
  [[ $2 == 1 ]] || return 0
  if ! out="$("$_updates_vgshell" pkg check --json --source pacman)" || ! facts="$(_updates_facts pending <<<"$out")"; then
    _updates_diagnostic "updates: review=unlisted source=pacman"; return 1
  fi
  while read -r key name old new; do
    if [[ $key == pending ]]; then pending[$name]="$old $new"; fi
  done <<<"$facts"
  [[ ${#pending[@]} -gt 0 ]] || return 0
  if ! out="$(pacman-conf --repo-list)"; then _updates_diagnostic "updates: review=unlisted query=repo-list"; return 1; fi
  mapfile -t repos <<<"$out"
  facts="$(_updates_facts third-party "${repos[@]}")"
  while read -r key repo; do
    [[ $key == third-party ]] || continue
    if ! out="$(pacman -Sl "$repo")"; then _updates_diagnostic "updates: review=unlisted repository=$repo"; return 1; fi
    listed=0
    while read -r _ name _; do
      [[ -n $name && -n ${pending[$name]+set} ]] || continue
      _updates_review_lines+=("repo $repo $name ${pending[$name]}")
      _updates_review_repo+=("$name")
      listed=1
    done <<<"$out"
    [[ $listed == 1 ]] || continue
    if ! out="$(pacman-conf --repo "$repo" Server)"; then _updates_diagnostic "updates: review=unlisted servers=$repo"; return 1; fi
    while read -r line; do
      [[ -n $line ]] || continue
      if [[ $line =~ ^([^:/]+://)[^/@]*@(.*)$ ]]; then line="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"; fi
      _updates_review_lines+=("server $repo $line")
    done <<<"$out"
    # A repository with no SigLevel of its own takes pacman's default.
    if ! out="$(pacman-conf --repo "$repo" SigLevel)" || { [[ -z $out ]] && ! out="$(pacman-conf SigLevel)"; }; then
      _updates_diagnostic "updates: review=unlisted siglevel=$repo"; return 1
    fi
    _updates_review_lines+=("siglevel $repo ${out//$'\n'/ }")
  done <<<"$facts"
}

# Removes the review directory. The service writes `ended` with a shell
# redirect, which makes no directory, so a write after the directory is gone
# fails; a write while rm runs leaves rm's last rmdir a name, and the next
# pass removes it. The service writes once per run, so 5 passes are a
# ceiling, not a measurement.
_updates_review_remove() {
  local passes=0
  while [[ -e ${_updates_review_dir:?} ]] && ((passes < 5)); do
    rm -rf -- "${_updates_review_dir:?}" 2>/dev/null || :
    passes=$((passes + 1))
  done
}

# The review in the second window, through the service's `review` IPC
# handler, which opens the `review` TUI from the stable review start
# directory. The run's 0700 directory is inside that start directory, made
# by an exclusive mkdir and removed when the review ends or the run exits,
# so the agent's folder trust is keyed on one path. The run fetches the
# AUR build files into its build/ first, through the helper as the user, so
# the agent reads them offline; a fetch runs no package code. NAMEs are
# the packages listed. Sets
# _updates_review_verdict to clean, flagged or none, _updates_review_flags
# to `<name> <concern>` per flag and _updates_review_reason, for the
# developer log, when there is no verdict.
_updates_review_run() { # NAME...
  local start dir reply status=0 polls=0 facts key value lock
  _updates_review_verdict=none _updates_review_reason="" _updates_review_flags=()
  start="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/vgshell/updates/review"
  mkdir -p -- "$start"
  chmod 700 -- "$start"
  dir="$start/$$"
  if ! mkdir -m 700 -- "$dir" 2>/dev/null; then _updates_review_reason="dir=taken path=$dir"; return 0; fi
  _updates_review_dir="$dir"
  trap '_updates_review_remove' EXIT
  printf '%s\n' "${_updates_review_words[@]}" >"$dir/command"
  printf '%s\n' "${_updates_review_lines[@]}" >"$dir/packages.txt"
  if [[ ${#_updates_review_aur[@]} -gt 0 ]]; then
    mkdir -m 700 -- "$dir/build"
    vgs_tui_step "Fetching the AUR build files"
    if ! (cd -- "$dir/build" && "$_updates_review_helper" -G "${_updates_review_aur[@]}"); then
      _updates_review_reason="fetch=failed helper=$_updates_review_helper"; return 0
    fi
  fi
  reply="$("$_updates_vgshell" ipc call "$VGS_PLUGIN_ID" invoke review "$dir" 2>&1)" || status=$?
  if [[ $status -ne 0 || $reply != ok ]]; then _updates_review_reason="open=${reply%%$'\n'*} exit=$status"; return 0; fi
  # tui/review.sh writes `started` once it holds the lock, and the service
  # writes `ended` when the run ends, a run that never started included.
  # Read every 0.2 s up to 300 times: a 60 s ceiling on a terminal's start,
  # not a measurement of one.
  while [[ ! -e $dir/started && ! -e $dir/ended ]] && ((polls < 300)); do
    sleep 0.2
    polls=$((polls + 1))
  done
  if [[ ! -e $dir/started ]]; then
    _updates_review_reason="start=$( ((polls < 300)) && echo none || echo timeout) ended=$(cat -- "$dir/ended" 2>/dev/null || echo absent)"; return 0
  fi
  # The lock is free once tui/review.sh has ended: its agent exited, or
  # the user closed the window.
  exec {lock}>>"$dir/review.lock"
  flock "$lock"
  exec {lock}>&-
  if [[ ! -f $dir/verdict ]]; then _updates_review_reason="verdict=absent"; return 0; fi
  if ! facts="$(_updates_facts verdict "$@" <"$dir/verdict")"; then _updates_review_reason="verdict=unreadable"; return 0; fi
  while read -r key value; do
    case "$key" in
      verdict) _updates_review_verdict="$value" ;;
      flag) _updates_review_flags+=("$value") ;;
      reason) _updates_review_reason="verdict=$value" ;;
    esac
  done <<<"$facts"
}

# The review and what its verdict leads to: a clean verdict goes on; each
# flagged package asks to be skipped, a yes adding it to _updates_skip_aur
# or _updates_skip_repo and a no stopping the run; no verdict asks to go on
# without a review, default no. A stopped run exits 0. LISTED is 0 when the
# packages could not be listed, which is no verdict.
_updates_review() { # LISTED
  local status flag name
  if [[ $1 == 1 ]]; then
    vgs_tui_step "Reviewing third-party packages in a second window"
    _updates_review_run "${_updates_review_aur[@]}" "${_updates_review_repo[@]}"
  else
    _updates_review_verdict=none _updates_review_reason="list=unreadable" _updates_review_flags=()
  fi
  if [[ -n ${_updates_review_dir:-} ]]; then
    _updates_review_remove
    _updates_review_dir=""
    trap - EXIT
  fi
  local count=$((${#_updates_review_aur[@]} + ${#_updates_review_repo[@]}))
  case "$_updates_review_verdict" in
    clean) echo "The review found no risk in the $count package$([[ $count == 1 ]] || echo s) it listed." ;;
    flagged)
      for flag in "${_updates_review_flags[@]}"; do
        name="${flag%% *}"
        vgs_tui_warn "$name: ${flag#* }"
        status=0
        vgs_tui_confirm "Skip $name?" || status=$?
        case "$status" in
          0)
            if _updates_in "$name" "${_updates_review_aur[@]}"; then _updates_skip_aur+=("$name"); fi
            if _updates_in "$name" "${_updates_review_repo[@]}"; then _updates_skip_repo+=("$name"); fi
            ;;
          1) echo "Update stopped."; exit 0 ;;
          *) exit "$status" ;;
        esac
      done
      ;;
    *)
      _updates_diagnostic "updates: review=none $_updates_review_reason"
      if [[ $1 == 1 ]]; then vgs_tui_warn "The review ended without a result."
      else vgs_tui_warn "Could not list the third-party packages."
      fi
      status=0
      vgs_tui_confirm "Continue without a review?" --default=false || status=$?
      case "$status" in
        0) ;;
        1) echo "Update stopped."; exit 0 ;;
        *) exit "$status" ;;
      esac
      ;;
  esac
}

# updates_main all ARG... | updates_main source SOURCE ARG...: the pipeline
# over every source, or over SOURCE alone, named as a status row names it:
# the primary manager's id, aur, flatpak, mise, vgs, plugins or themes. The
# ARGs after SOURCE are -y alone; update-source.sh passes its SOURCE twice,
# once here and once among the entry script's own ARGs, which the log runs
# it again with.
updates_main() {
  local mode="$1" only="" arg
  shift
  if [[ $mode == source ]]; then
    only="${1:-}"
    [[ -n $only && $only != -* ]] || _updates_refuse 2 "source=missing" "$_updates_usage"
    shift
  fi
  local entry_args=("$@")
  [[ $mode == all ]] || entry_args=("$only" "$@")
  _updates_yes=0
  for arg in "$@"; do
    case "$arg" in
      -y) _updates_yes=1 ;;
      *) _updates_refuse 2 "argument=$arg" "$_updates_usage" ;;
    esac
  done

  local lib="${VGS_TUI_LIB:-}"
  _updates_tree="${lib%/bin/lib/tui.sh}"
  if [[ -z $lib || $_updates_tree == "$lib" || -z ${VGS_PLUGIN_ID:-} ]]; then
    _updates_refuse 2 "tui=missing" "run this through the vgs.updates floating TUI, which sets VGS_TUI_LIB and VGS_PLUGIN_ID"
  fi
  # shellcheck source=SCRIPTDIR/../../../../bin/lib/tui.sh
  source "$lib"
  _updates_vgshell="$_updates_tree/bin/vgshell"
  _updates_loader="$_updates_tree/bin/lib/qml-library.js"
  _updates_facts_bin="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)/bin/facts"

  local state
  state="$(updates_state_dir)"
  _updates_log="$(updates_log_file)"
  if [[ ${VGS_TUI_LOGGED:-} != 1 ]]; then
    mkdir -p -- "$state"
    export UPDATES_LOG_PART="$state/.update.$$.log"
  fi
  vgs_tui_log "$UPDATES_LOG_PART" "${entry_args[@]}"
  local status=0
  vgs_tui_lock updates || status=$?
  if [[ $status -ne 0 ]]; then
    rm -f -- "$UPDATES_LOG_PART"
    exit "$status"
  fi
  mv -f -- "$UPDATES_LOG_PART" "$_updates_log"
  _updates_pid=$BASHPID
  trap '_updates_failed $?' ERR

  # What the run acts on: the plugin's settings and the system's managers.
  local out facts key value aur_command=() snapshot_setting="" trust=false
  local settings
  settings="$("$_updates_vgshell" plugin settings "$VGS_PLUGIN_ID")"
  facts="$(_updates_facts settings <<<"$settings")"
  while read -r key value; do
    case "$key" in
      aur-command) read -r -a aur_command <<<"$value" ;;
      snapshot) snapshot_setting="$value" ;;
      trust) trust="$value" ;;
    esac
  done <<<"$facts"
  _updates_yes_flag=()
  if [[ $trust == true ]]; then _updates_yes_flag=(--yes); fi

  local primary="" present=() aur_binary=""
  out="$("$_updates_vgshell" pkg detect --json)"
  facts="$(_updates_facts detect <<<"$out")"
  while read -r key value; do
    case "$key" in
      primary) primary="$value" ;;
      present)
        present+=("${value%% *}")
        if [[ ${value%% *} == aur ]]; then aur_binary="${value#* }"; fi
        ;;
    esac
  done <<<"$facts"
  local aur_here=0
  if _updates_in aur "${present[@]}" || [[ ${#aur_command[@]} -gt 0 && $primary == pacman ]]; then aur_here=1; fi

  # The sources this run takes, in step order.
  local run=()
  if [[ $mode == all ]]; then
    run=(vgs)
    if [[ -n $primary ]]; then run+=("$primary"); fi
    for arg in flatpak mise; do
      if _updates_in "$arg" "${present[@]}"; then run+=("$arg"); fi
    done
    run+=(plugins themes)
    if [[ $aur_here == 1 ]]; then run+=(aur); fi
  else
    case "$only" in
      vgs|plugins|themes) ;;
      aur) [[ $aur_here == 1 ]] || _updates_refuse 1 "source=aur reason=absent" ;;
      flatpak|mise) _updates_in "$only" "${present[@]}" || _updates_refuse 1 "source=$only reason=absent" ;;
      "$primary") ;;
      *) _updates_refuse 2 "source=$only reason=unknown" "a source is the primary manager's id, aur, flatpak, mise, vgs, plugins or themes" ;;
    esac
    run=("$only")
  fi

  # Each source's plan, for the box and the steps. A package source whose
  # plan the table refuses, as it refuses nix's, leaves the run.
  local plan=() kept=() id label vgs_method="" vgs_package="" vgs_behind=false plugins=() themes=()
  local primary_planned=0 elevator="" elevator_refused=""
  local _updates_plan_text _updates_plan_elevator _updates_plan_elevator_refused
  if _updates_in vgs "${run[@]}"; then
    out="$("$_updates_vgshell" self status --json)"
    facts="$(_updates_facts self <<<"$out")"
    while read -r key value; do
      case "$key" in
        method) vgs_method="$value" ;;
        package) vgs_package="$value" ;;
        behind) vgs_behind="$value" ;;
        error) _updates_diagnostic "VGS: $value"; vgs_tui_warn "Could not check VGS for updates." ;;
      esac
    done <<<"$facts"
    case "$vgs_method:$vgs_behind:$vgs_package" in
      checkout:true:*|curl:true:*) plan+=("VGS: update VGS") ;;
      package:true:vgshell-git)
        if [[ -n $aur_binary ]]; then plan+=("VGS: rebuild the VGS package after AUR updates")
        else plan+=("VGS: vgshell-git is behind, and no AUR helper is here to rebuild it")
        fi
        ;;
      package:true:*) plan+=("VGS: the $vgs_package package updates with its package manager") ;;
      nix:true:*) plan+=("VGS: its flake updates it") ;;
      *) plan+=("VGS: current") ;;
    esac
  fi
  for id in "${run[@]}"; do
    case "$id" in
      vgs|plugins|themes) kept+=("$id"); continue ;;
      aur) if [[ ${#aur_command[@]} -gt 0 ]]; then kept+=(aur); continue; fi; label="AUR, last" ;;
      flatpak) label=Flatpak ;;
      mise) label=mise ;;
      *) label=System ;;
    esac
    if _updates_plan "$id"; then
      kept+=("$id")
      plan+=("$label: install available updates")
    else
      [[ $mode == all ]] || _updates_refuse 1 "source=$only reason=no-plan" "$_updates_plan_text"
      _updates_diagnostic "$label: $_updates_plan_text"; plan+=("$label: VGS cannot update this source")
    fi
    if [[ $id == "$primary" ]]; then
      primary_planned=1
      elevator="$_updates_plan_elevator"
      elevator_refused="$_updates_plan_elevator_refused"
    fi
  done
  run=("${kept[@]}")
  if [[ ${#aur_command[@]} -gt 0 ]] && _updates_in aur "${run[@]}"; then plan+=("AUR: install updates after system updates"); fi
  if _updates_in plugins "${run[@]}"; then
    _updates_outdated plugin plugins
    plugins=("${_updates_behind[@]}")
    plan+=("Plugins: ${plugins[*]:-current}")
  fi
  if _updates_in themes "${run[@]}"; then
    _updates_outdated theme themes
    themes=("${_updates_behind[@]}")
    plan+=("Themes: ${themes[*]:-current}")
  fi

  # A snapshot and the VGS version check guard every step that replaces
  # packages: the upgrades, the system's and the AUR's, and the vgshell-git
  # rebuild. The orphans follow the upgrades alone.
  local upgrades=0 rebuild=0 replaces=0
  if _updates_in aur "${run[@]}" || { [[ -n $primary ]] && _updates_in "$primary" "${run[@]}"; }; then upgrades=1; fi
  if _updates_in vgs "${run[@]}" && [[ $vgs_method:$vgs_behind:$vgs_package == package:true:vgshell-git && -n $aur_binary ]]; then rebuild=1; fi
  if [[ $upgrades == 1 || $rebuild == 1 ]]; then replaces=1; fi
  local snapshot_line="" snapshot_tool=""
  if [[ $replaces == 1 ]]; then
    if [[ $snapshot_setting == off ]]; then
      snapshot_line="Snapshot: off in the plugin's settings"
    elif ! snapshot_tool="$(_updates_snapshot_tool)"; then
      snapshot_tool=""
      snapshot_line="Snapshot: none, no snapper or timeshift found"
    else
      # The primary's plan names the elevation command, also when the run
      # leaves the system step out; a refused plan leaves its refusal in
      # elevator_refused, for the box.
      if [[ $primary_planned == 0 && -n $primary ]]; then
        _updates_plan "$primary" || true
        elevator="$_updates_plan_elevator"
        elevator_refused="$_updates_plan_elevator_refused"
      fi
      if [[ -n $elevator ]]; then
        snapshot_line="Snapshot: $snapshot_tool through $elevator, first"
      else
        snapshot_tool=""
        _updates_diagnostic "snapshot: $elevator_refused"; snapshot_line="Snapshot: unavailable because administrator access is not available"
      fi
    fi
  fi
  local session=0
  if [[ $elevator == sudo ]]; then session=1; fi

  # The free space and the plan box.
  local avail
  out="$(df --output=avail --block-size=1 /)"
  avail="${out##*$'\n'}"
  avail="${avail//[[:space:]]/}"
  if [[ ! $avail =~ $_updates_digits ]]; then
    _updates_diagnostic "updates: free-space=unreadable"; vgs_tui_warn "Could not check free disk space."
  elif ((avail < 10 * 1024 * 1024 * 1024)); then
    vgs_tui_warn "Less than 10 GiB is free on /. An update can fail when the disk fills up."
  fi
  # The review: 1 when one runs, 2 when its packages could not be listed,
  # and its line in the box.
  # The AUR is reviewed through a helper of the package table alone: the
  # helper fetches its build files.
  local box_review_aur="" review=0 review_line="" review_aur=0 review_repo=0 review_rebuild=0 reviewed=() listing="" name
  _updates_skip_aur=() _updates_skip_repo=()
  _updates_review_agent "$settings"
  if [[ $_updates_review_state == command || $_updates_review_state == agent ]]; then
    if _updates_in aur "${run[@]}"; then
      if [[ -n $aur_binary ]]; then review_aur=1
      else box_review_aur="Review: the AUR is not reviewed without paru or yay"
      fi
    fi
    if [[ $rebuild == 1 ]]; then review_rebuild=1; fi
    if [[ $primary == pacman ]] && _updates_in pacman "${run[@]}"; then review_repo=1; fi
    if [[ -n $primary && $primary != pacman ]] && _updates_in "$primary" "${run[@]}"; then review_line="Review: VGS reviews Arch packages only"; fi
    if [[ $review_aur == 1 || $review_repo == 1 || $review_rebuild == 1 ]]; then
      if _updates_review_list "$review_aur" "$review_repo" "$aur_binary" "$review_rebuild"; then
        reviewed=("${_updates_review_aur[@]}" "${_updates_review_repo[@]}")
        if [[ ${#reviewed[@]} -gt 0 ]]; then
          review=1
          for name in "${reviewed[@]:0:6}"; do listing+="${listing:+, }$name"; done
          if [[ ${#reviewed[@]} -gt 6 ]]; then listing+=", and $((${#reviewed[@]} - 6)) more"; fi
          review_line="Review: $_updates_review_label checks ${#reviewed[@]} third-party package$([[ ${#reviewed[@]} == 1 ]] || echo s): $listing"
        fi
      else
        review=2
        review_line="Review: the third-party packages could not be listed"
      fi
    fi
  fi

  local box=("Update ${only:-everything}" "")
  [[ -z $snapshot_line ]] || box+=("$snapshot_line")
  box+=("${plan[@]}")
  [[ -z $review_line ]] || box+=("$review_line")
  [[ -z $box_review_aur ]] || box+=("$box_review_aur")
  if [[ $rebuild == 1 ]] || _updates_in aur "${run[@]}"; then box+=("The AUR runs last, after every step that runs as root."); fi
  box+=("" "Log: $_updates_log")
  vgs_tui_header "${box[@]}"
  if [[ $_updates_yes != 1 ]]; then
    status=0
    vgs_tui_confirm "Start the update?" || status=$?
    case "$status" in
      0) ;;
      1) echo "Update cancelled."; exit 0 ;;
      *) exit "$status" ;;
    esac
  fi

  # The run.
  if [[ $review == 1 ]]; then _updates_review 1
  elif [[ $review == 2 ]]; then _updates_review 0
  fi
  local vgs_before=""
  if [[ $replaces == 1 ]]; then vgs_before="$(_updates_vgs_package_version)"; fi
  if [[ $session == 1 ]]; then vgs_tui_sudo_session start; fi
  # A failed snapshot said what went wrong; it does not block the update,
  # but it must not pass for one either.
  if [[ -n $snapshot_tool ]]; then
    status=0
    _updates_snapshot "$snapshot_tool" "$elevator" || status=$?
    if [[ $status -ne 0 ]]; then
      _updates_diagnostic "updates: snapshot=failed exit=$status"; vgs_tui_warn "The snapshot failed."
      vgs_tui_warn "Continuing the update without a snapshot."
    fi
  fi
  if _updates_in vgs "${run[@]}" && [[ $vgs_behind == true && ( $vgs_method == checkout || $vgs_method == curl ) ]]; then
    vgs_tui_step "Updating VGS"
    "$_updates_vgshell" self update
  fi
  local ignore=()
  for id in "${run[@]}"; do
    case "$id" in
      vgs|plugins|themes|aur) ;;
      *)
        ignore=()
        if [[ $id == pacman && ${#_updates_skip_repo[@]} -gt 0 ]]; then ignore=(--ignore "${_updates_skip_repo[@]}"); fi
        "$_updates_vgshell" pkg run upgrade --manager "$id" "${ignore[@]}"
        ;;
    esac
  done
  if [[ ${#plugins[@]} -gt 0 ]]; then _updates_update_each plugin "${plugins[@]}"; fi
  if [[ ${#themes[@]} -gt 0 ]]; then _updates_update_each theme "${themes[@]}"; fi
  if [[ $session == 1 ]]; then vgs_tui_sudo_session end; fi

  if [[ $rebuild == 1 ]] || _updates_in aur "${run[@]}"; then
    local guarded=0
    if command -v sudo >/dev/null; then
      vgs_tui_sudo_session guard
      guarded=1
    fi
    if _updates_in aur "${run[@]}"; then
      ignore=()
      if [[ ${#aur_command[@]} -gt 0 ]]; then
        # The words may sync the system too, so both lists are kept out.
        for name in "${_updates_skip_aur[@]}" "${_updates_skip_repo[@]}"; do ignore+=(--ignore "$name"); done
        _updates_run "Updating AUR packages" "${aur_command[@]}" "${ignore[@]}"
      else
        if [[ ${#_updates_skip_aur[@]} -gt 0 ]]; then ignore=(--ignore "${_updates_skip_aur[@]}"); fi
        "$_updates_vgshell" pkg run upgrade --manager aur "${ignore[@]}"
      fi
    fi
    if [[ $rebuild == 1 ]] && ! _updates_in vgshell-git "${_updates_skip_aur[@]}"; then _updates_run "Rebuilding VGS" "$aur_binary" -S vgshell-git; fi
    if [[ $guarded == 1 ]]; then vgs_tui_sudo_session end; fi
  fi

  if [[ $primary == pacman ]] && [[ $upgrades == 1 ]]; then _updates_orphans; fi
  if [[ -n $vgs_before ]] && [[ "$(_updates_vgs_package_version)" != "$vgs_before" ]] && "$_updates_vgshell" pid >/dev/null 2>&1; then
    vgs_tui_step "Restarting the shell on the updated VGS"
    "$_updates_vgshell" restart || { _updates_diagnostic "updates: restart=failed exit=$?"; vgs_tui_warn "VGS could not restart. Save your work and restart the computer."; }
  fi
  _updates_recheck success
  _updates_reboot
}
