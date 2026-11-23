# Sourced by harness.sh once the nested compositor's shell_env and signature
# exist, and by scripts/test-smoke-hypr-bound.sh. Defines hypr, the one
# caller of the nested compositor's hyprctl, its bound, and the end of the
# run when an operation cannot leave a usable world, and arms that end on USR1 in the
# shell that sources it. It reads the caller's shell_env, signature and
# sandbox, fail and row_class from verdict.sh, and smoke_finish,
# which the caller defines before the first call. A reload also reads the
# caller's repo, the tree whose MonitorLogic.js judges it, and node.
#
# hyprctl bounds its read but not its connect, so once a stopped compositor's
# listen backlog is full every later call blocks for good, holding the slot
# the run runs in.

# The shell that sourced this file, which the abort signal ends. $$ would
# name the parent when the harness is sourced inside ( ... ), as
# scripts/qml-smoke.sh --first-bar-runs does.
harness_pid=$BASHPID
# hyprctl's own read timeout is 5 s, so a reply hyprctl would accept always
# lands inside the bound, and the bound catches the connect that never
# returns once the compositor's backlog is full.
hypr_bound_s=10

# hypr ARG...: hyprctl ARG... against the nested instance, its stdout copied
# byte for byte, its stderr passed through, its status returned. A call that
# hits the bound, or that hyprctl's own read timeout ends (exit 6 with the
# line below on stdout), is a stall: smoke_abort ends the run. A call
# after a stall, from a subshell the harness shell has not ended yet,
# returns 1 at once. A caller's local hypr_advisory=true retains that failed
# status without aborting the world, for observation-only reads.
hypr() {
  local out="$sandbox/hypr-$BASHPID.out" status=0 copied=0
  [[ ! -e $sandbox/smoke-aborted ]] || return 1
  if hypr_reloads "$@" && ! hypr_reload_clear "$*"; then return 1; fi
  "${shell_env[@]}" timeout -k 2 "$hypr_bound_s" hyprctl -i "$signature" "$@" >"$out" || status=$?
  cat -- "$out" || copied=$?
  if [[ ${hypr_advisory:-false} != true ]]; then
    if [[ $status -eq 124 || $status -eq 137 ]]; then
      smoke_abort "the nested compositor stopped answering: hyprctl $*: no answer within ${hypr_bound_s}s"
    elif [[ $status -eq 6 ]] && grep -qF "Hyprland IPC didn't respond in time" -- "$out"; then
      smoke_abort "the nested compositor stopped answering: hyprctl $*: hyprctl read timed out after 5s"
    fi
  fi
  rm -f -- "$out"
  [[ $status -ne 0 ]] || status=$copied
  return "$status"
}

# hypr_reloads ARG...: whether the call asks Hyprland to reload its
# configuration, as its command or as one command of a --batch.
hypr_reloads() {
  local arg command batch=false
  local -a commands
  for arg in "$@"; do
    if [[ $batch == true ]]; then
      IFS=';' read -r -a commands <<<"$arg"
      for command in "${commands[@]}"; do
        read -r command _ <<<"$command"
        if [[ $command == reload ]]; then return 0; fi
      done
      return 1
    fi
    case "$arg" in
      --batch) batch=true ;;
      -*) ;;
      *) if [[ $arg == reload ]]; then return 0; fi; return 1 ;;
    esac
  done
  return 1
}

# hypr_reload_clear REQUEST: true once `monitors all` lists no FALLBACK,
# judged by MonitorLogic.fallbackLit. A reload while it is listed aborts
# Hyprland 0.57 and hides the row's own failure behind a dead compositor,
# so FALLBACK listed, a failed read or a failed judge ends the run here
# with the cause. REVISIT(VGS-2136): remove the check once the oldest
# Hyprland VGS supports carries hyprwm/Hyprland#16927.
hypr_reload_clear() {
  local reply verdict status=0
  reply="$(hypr -j monitors all)" || status=$?
  if [[ $status -ne 0 ]]; then
    smoke_abort "hypr-reload: refused cause=monitors-read status=$status request=[$1]"
    return 1
  fi
  verdict="$(node -e '
const repo = process.argv[1];
const logic = require(repo + "/bin/lib/qml-library.js").load(repo + "/shell/Core/MonitorLogic.js");
const read = logic.parseOutputs(require("fs").readFileSync(0, "utf8"));
const answer = logic.fallbackLit(read.ok ? read.outputs : null);
process.stdout.write(!read.ok ? read.error : !answer.ok ? answer.error : answer.lit ? "fallback=listed" : "clear");' "$repo" <<<"$reply")" || verdict="judge=failed status=$? out=${verdict//$'\n'/ }"
  [[ $verdict != clear ]] || return 0
  smoke_abort "hypr-reload: refused cause=[$verdict] request=[$1]"
  return 1
}

# smoke_abort REASON: record the first fatal operation in
# $sandbox/smoke-aborted and signal the harness shell. Calls run inside
# command substitutions, process substitutions and pipelines, where an exit
# would end only that subshell, so the signal is how the stall reaches the
# harness shell; bash runs its trap once the call in the foreground returns.
smoke_abort() {
  (set -C; printf '%s\n' "$1" >"$sandbox/smoke-aborted") 2>/dev/null || true
  kill -USR1 -- "$harness_pid"
}

# smoke_aborted: the run's end after a fatal operation. The failure counts as
# behaviour, so the verdict never excuses it as a sandbox fault or exit 77.
# The EXIT trap (teardown.sh) then stops the nested compositor and removes
# the sandbox.
smoke_aborted() {
  trap '' USR1
  row_class=behaviour
  fail "$(<"$sandbox/smoke-aborted"); the run ends here"
  smoke_finish
  exit 1
}
trap smoke_aborted USR1
