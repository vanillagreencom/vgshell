# Sourced by harness.sh once the nested compositor's shell_env and signature
# exist, and by scripts/test-smoke-hypr-bound.sh. Defines hypr, the one
# caller of the nested compositor's hyprctl, its bound, and the end of the
# run when the compositor stops answering, and arms that end on USR1 in the
# shell that sources it. It reads the caller's shell_env, signature and
# sandbox, fail and row_class from verdict.sh, and smoke_finish,
# which the caller defines before the first call.
#
# hyprctl bounds its read but not its connect, so once a stopped compositor's
# listen backlog is full every later call blocks for good, holding the slot
# the run runs in.

# The shell that sourced this file, which the stall signal ends. $$ would
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
# line below on stdout), is a stall: compositor_stalled ends the run. A call
# after a stall, from a subshell the harness shell has not ended yet,
# returns 1 at once.
hypr() {
  local out="$sandbox/hypr-$BASHPID.out" status=0 copied=0
  [[ ! -e $sandbox/compositor-stalled ]] || return 1
  "${shell_env[@]}" timeout -k 2 "$hypr_bound_s" hyprctl -i "$signature" "$@" >"$out" || status=$?
  cat -- "$out" || copied=$?
  if [[ $status -eq 124 || $status -eq 137 ]]; then
    compositor_stalled "$*" "no answer within ${hypr_bound_s}s"
  elif [[ $status -eq 6 ]] && grep -qF "Hyprland IPC didn't respond in time" -- "$out"; then
    compositor_stalled "$*" "hyprctl read timed out after 5s"
  fi
  rm -f -- "$out"
  [[ $status -ne 0 ]] || status=$copied
  return "$status"
}

# compositor_stalled CALL REASON: record the first stall as one line in
# $sandbox/compositor-stalled and signal the harness shell. hypr runs inside
# command substitutions, process substitutions and pipelines, where an exit
# would end only that subshell, so the signal is how the stall reaches the
# harness shell; bash runs its trap once the call in the foreground returns.
compositor_stalled() {
  (set -C; printf 'hyprctl %s: %s\n' "$1" "$2" >"$sandbox/compositor-stalled") 2>/dev/null || true
  kill -USR1 -- "$harness_pid"
}

# smoke_stalled: the run's end after a stall. The failure counts as
# behaviour, so the verdict never excuses it as a sandbox fault or exit 77.
# The EXIT trap (teardown.sh) then stops the nested compositor and removes
# the sandbox.
smoke_stalled() {
  trap '' USR1
  row_class=behaviour
  fail "the nested compositor stopped answering: $(<"$sandbox/compositor-stalled"); the run ends here"
  smoke_finish
  exit 1
}
trap smoke_stalled USR1
