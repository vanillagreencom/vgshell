# Sourced by harness.sh and by scripts/test-smoke-verdict.sh; defines the
# failure tally the rows write, the count reading that fails a row in
# place of ending the run, and the smoke's closing verdict, and reads no
# sandbox state of its own.

failures=0
# A row that reads positions, sizes or reserved space from the compositor
# runs under `geometry`; a row whose subject shows only once the shell
# draws a frame runs under `render`; a row that reads the held mode itself,
# whose failure is the hold misbehaving, runs under `hold`; every other
# failure counts as behaviour, `hold` included. Only a run whose failures
# are all geometry or render can be excused by a sandbox fault: the nested
# output's buffers.
behaviour_failures=0
row_class=behaviour
# A mode a row holds on a nested output, as (OUTPUT STATE), STATE its mode
# and scale as mode_scale_of in mode-hold.sh reads them, empty when no row
# holds one; hold_mode, release_mode, suspend_run_base and resume_run_base
# alone write it.
mode_hold=()
# The mode owner keeps complete parents here. The harness marks its
# acquired bottom hold for the sandbox lifetime without copying its state;
# a row that tests monitor rules suspends it and holds it again at its end
# (suspend_run_base in mode-hold.sh).
mode_hold_parents=()
mode_hold_run_base=false
# A row that could not measure on this host, as `ROW:REASON` words, which
# not_measured alone writes: a prerequisite the row needs is missing, or a
# guard read the shell reaching past the sandbox (scripts/smoke/devices.sh).
# The row stops there and every other row still runs; a run with no
# failure and any such row is not measured, never a pass.
not_measured_rows=()
# not_measured ROW REASON: the row ROW recorded as not measured and printed.
not_measured() {
  not_measured_rows+=("$1:$2")
  printf '  SKIP  %s: not measured: %s\n' "$1" "$2"
}
# fail MESSAGE: one failed row, counted by its class and printed.
fail() {
  failures=$((failures + 1))
  [[ $row_class == geometry || $row_class == render ]] || behaviour_failures=$((behaviour_failures + 1))
  printf '  FAIL  %s\n' "$*"
}
# read_count VAR LABEL CMD...: VAR takes CMD's last stdout line when CMD
# succeeds and that line is a count, a run of digits. Any other reading,
# a probe's state word such as `undefined` or an empty reply among them,
# fails the row under LABEL and leaves VAR 0, so the row goes on to its
# own cleanup. A row adds to a count it read: bash takes a word inside
# $(( )) as a variable's name, and under set -u an unset one ends the
# sourced row and the run with it, every later row unreported.
read_count() {
  local -n read_count_var="$1"
  local read_count_label="$2" read_count_got read_count_status=0
  shift 2
  read_count_got="$("$@")" || read_count_status=$?
  read_count_got="${read_count_got##*$'\n'}"
  if [[ $read_count_status -eq 0 && $read_count_got =~ ^[0-9]+$ ]]; then
    read_count_var="$read_count_got"
    return 0
  fi
  read_count_var=0
  fail "$read_count_label: no count was read: status=$read_count_status got=[$read_count_got]"
}

# nested_output_unallocated LOG...: true when a nested compositor log holds
# the line Aquamarine's Wayland backend writes when the nested window's own
# output rejects a state because its swapchain could not allocate buffers
# (src/backend/Wayland.cpp, aquamarine v0.15.1). A GBM allocation line alone
# names no output: every passing run logs failed 1920x1080 XR24 allocations
# for Hyprland's headless FALLBACK output. Five passing runs of
# scripts/qml-smoke.sh --keep on the owner's machine (host cachy, AMD Ryzen 9
# 9950X, Hyprland 0.56.2, aquamarine 0.15.1) on 2026-09-27, counted with
# grep -c in each kept hyprland.log, each logged 16 `Failed to allocate a GBM
# buffer` lines and no rejection line. An unreadable log holds no line, so
# the run fails.
nested_output_unallocated() {
  grep -q -s -E 'Output WAYLAND-[0-9]+: pending state rejected: swapchain failed reconfiguring' -- "$@"
}
# nested_output_unallocated_since OUTPUT OFFSET LOG: true when LOG, past its
# first OFFSET bytes, holds that rejection for OUTPUT itself, so neither an
# earlier rejection nor another output's is read as this output's.
nested_output_unallocated_since() {
  [[ -f $3 ]] || return 1
  grep -q -F -e "Output $1: pending state rejected: swapchain failed reconfiguring" < <(tail -c "+$(($2 + 1))" -- "$3")
}

# smoke_verdict FAILURES BEHAVIOUR_FAILURES LOG...: prints the run's
# closing line and returns its exit status. A run whose failures are all
# geometry or render rows met a sandbox fault when the nested output could
# not allocate its buffers; it reports not-measured, which is never a pass,
# and names the cause. Any behaviour failure is a failure. A run with no
# failure whose not_measured_rows holds a row is not measured, and its line
# names each row and reason.
smoke_verdict() {
  local failures="$1" behaviour_failures="$2"
  shift 2
  if [[ $failures -eq 0 && ${#not_measured_rows[@]} -gt 0 ]]; then
    printf 'qml-smoke: status=not-measured rows=%s\n' "$(IFS=,; echo "${not_measured_rows[*]}")"
    return 77
  fi
  if [[ $failures -eq 0 ]]; then
    echo "qml-smoke: ok"
    return 0
  fi
  if [[ $behaviour_failures -eq 0 ]] && nested_output_unallocated "$@"; then
    printf 'qml-smoke: status=not-measured nested-compositor=buffer-allocation-failed failed=%s\n' "$failures"
    return 77
  fi
  echo "qml-smoke: failed=$failures"
  return 1
}
