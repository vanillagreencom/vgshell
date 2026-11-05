# Sourced by harness.sh and the teardown tests. Closes the display recorder
# and ends the process groups spawn recorded. The world owns the temporary
# trees and retains row evidence after the namespace ends.
#
# Ignore repeat stop signals while closing producers and the recorder.
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

cleanup() {
  local original_status=$?
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
trap cleanup EXIT
