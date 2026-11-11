# Sourced by harness.sh and the teardown tests. Closes the display recorder
# and ends the process groups spawn recorded. The world owns the temporary
# trees and retains row evidence after the namespace ends.
#
# Ignore repeat stop signals from the first stop on, and every stop while
# closing producers and the recorder after any other exit.
# SIGKILL is handled by the world's PID namespace and after-namespace copy.
# A stop that TERMs every process of the world, as a systemd unit's stop
# does, reaches this cleanup and every process it ends at once. The world's
# bubblewrap monitor ignores it (gpu-fence.sh), so the namespace outlives
# this cleanup, and the cleanup outlives a dead reader of its output, so it
# still takes its closing reading.
set -euo pipefail
if ! "${source_repo:-${repo:-${BASH_SOURCE[0]%/scripts/smoke/teardown.sh}}}/scripts/smoke/gpu-fence.sh" --check; then
  printf 'qml-smoke: status=not-measured missing=gpu-fence\n'
  exit 77
fi

# cleanup STATUS: STATUS is the exit status the world ends with. Nothing
# before its ignore acts, so a stop the trap below runs there, which runs
# this cleanup again and exits, leaves one teardown.
cleanup() {
  local original_status=$1
  local teardown_started_us="${EPOCHREALTIME/./}"
  trap '' TERM INT HUP
  # A stop that signals every process of the world, as a unit's stop does,
  # also ends what this output runs through: a row's output filter
  # (harness.sh's smoke_row) and the driver's log reader (qml-smoke.sh). A
  # line written to them is lost, and neither its SIGPIPE nor its failed
  # write may end this cleanup before its closing reading. Every step below
  # handles its own failure.
  trap '' PIPE
  set +e
  local pg
  if [[ -n ${display_record_pid:-} ]]; then
    if ! display_record_close "$original_status" cleanup; then
      printf 'qml-smoke: cleanup=recorder-close-failed path=%s\n' "${display_record_dir:-unavailable}" >&2
    fi
  fi
  if declare -F sink_alive >/dev/null && ! sink_alive; then
    printf 'qml-smoke: %s\n' "$sink_exit"
  fi
  for pg in "${pgids[@]}"; do
    [[ $pg == "${display_record_pid:-}" ]] || kill -TERM -- "-$pg" 2>/dev/null || true
  done
  sleep 0.5
  for pg in "${pgids[@]}"; do
    [[ $pg == "${display_record_pid:-}" ]] || kill -KILL -- "-$pg" 2>/dev/null || true
  done
  # A nested smoke attempt's closing reading, once the groups it started
  # have ended, so it reads what they did after the last row's reading
  # (smoke_attempt_judged in row-inputs.sh).
  if declare -F qml_smoke_judge_reading >/dev/null; then qml_smoke_judge_reading - close; fi
  if [[ -n ${display_record_pid:-} ]]; then
    if ! display_record_finish "$original_status"; then
      printf 'qml-smoke: cleanup=recorder-finalization-failed path=%s\n' "${display_record_dir:-unavailable}" >&2
    fi
  fi
  printf 'qml-smoke: fixed-us phase=teardown us=%s\n' "$(( ${EPOCHREALTIME/./} - teardown_started_us ))"
}
# A unit's stop hands this shell two stops: the unit's own TERM and the copy
# gpu-fence.sh's forward hands CMD's process group. Untrapped, the first
# reaches cleanup through Bash's exit path, and a second that comes before
# cleanup's own ignore kills the shell outright, closing reading and all
# (Bash 5.3 sig.c, termsig_sighandler: `if (handling_termsig) kill_shell
# (sig);`). So each stop is trapped, and the trap ignores every later stop,
# then runs cleanup itself and exits with the stop's status. It never exits
# into the EXIT trap: a stop still pending when another exit starts that
# trap, as the SIGPIPE of a write to an output the stop ended does, runs
# before its first command (Bash 5.3 execute_cmd.c, execute_command:
# `QUIT; run_pending_traps ();`), and an exit there would end the EXIT trap
# before cleanup. Bash runs a trap only once the foreground command ends; a
# stop that comes through the fence reaches that command too, since the
# fence hands it to CMD's process group.
trap 'trap "" TERM INT HUP; trap - EXIT; cleanup 143; exit 143' TERM
trap 'trap "" TERM INT HUP; trap - EXIT; cleanup 130; exit 130' INT
trap 'trap "" TERM INT HUP; trap - EXIT; cleanup 129; exit 129' HUP
trap 'cleanup "$?"' EXIT
