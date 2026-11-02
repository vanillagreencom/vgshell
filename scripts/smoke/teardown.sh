# Sourced by harness.sh and the teardown tests. Closes the display recorder
# and ends the process groups spawn recorded. The world owns the temporary
# trees and retains row evidence after the namespace ends.
#
# Ignore repeat stop signals while closing producers and the recorder.
# SIGKILL is handled by the world's PID namespace and after-namespace copy.
# A stop that TERMs the world's bubblewrap monitor too, as a systemd unit's
# stop TERMs every process of the unit, ends the namespace before this
# cleanup finishes (gpu-fence.sh's --die-with-parent): a probe of a world
# command's EXIT trap under `systemctl --user stop` on 2026-11-02 found it
# cut off, and finished when the command alone got the TERM.
set -euo pipefail
if ! "${source_repo:-${repo:-${BASH_SOURCE[0]%/scripts/smoke/teardown.sh}}}/scripts/smoke/gpu-fence.sh" --check; then
  printf 'qml-smoke: status=not-measured missing=gpu-fence\n'
  exit 77
fi

cleanup() {
  local original_status=$?
  trap '' TERM INT HUP
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
}
trap cleanup EXIT
