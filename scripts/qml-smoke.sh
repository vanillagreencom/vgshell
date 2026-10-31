#!/usr/bin/env bash
# Run the shell inside a nested Hyprland sandbox and check it end to end.
#
# Usage: scripts/qml-smoke.sh [--tree DIR] [--nix-store STORE] [--timeout SECONDS] [--keep] [--rows NAME[,NAME...]] [--log-dir DIR]
#        scripts/qml-smoke.sh --first-bar-runs N [--plugin-set smoke|default] [--timeout SECONDS]
#        scripts/qml-smoke.sh --list-rows
#
# --tree selects an installed runtime tree; rows, probes and fixtures come
# from this checkout. --nix-store supplies its exported /nix for the world
# to copy and mount privately. It requires a NixOS graphics host; another
# host reports nixos-graphics-required, exit 77, before starting anything.
# The tested tree enters the world read-only.
# The sandbox has its own HOME, XDG dirs and
# runtime dir, a minimal compositor config, no user state. It never touches
# the live session: the nested compositor gets its own runtime dir and
# draws to the harness's own sink compositor (scripts/smoke/sink/sink.c),
# which configures each output once at 1920x1080 and paces frames at its
# own 60 Hz, so no host display or lit monitor is needed. The shell is
# addressed through that runtime dir, and teardown kills only the process
# groups this run created. It needs XDG_RUNTIME_DIR and a render node in
# the GPU fence, and no WAYLAND_DISPLAY.
#
# Exit 0 when every check passed. Exit 77 when a prerequisite is missing,
# naming it, the sink's build (missing=sink-helper-build), the render
# node it names (missing=render-node) and a sink that exits before the
# nested compositor is up (missing=sink sink=exited) among them; when the nested
# compositor still lists a monitor with no size at the bound
# scripts/smoke/harness.sh names from its launch, nested-monitor=unsized,
# since it configures no bar there; or when a run whose only failures are
# geometry or render rows met a sandbox fault: the nested output rejected a
# state because its buffers could not be allocated, which the nested
# compositor logs as `Output WAYLAND-<n>: pending state rejected: swapchain
# failed reconfiguring` (a bare GBM allocation failure, which passing runs
# log for the headless output, is not that fault), or a held mode the
# output did not take while it logged that fault for itself
# (nested-output=mode-unavailable);
# that is not a pass. A sink that exits later fails the row it ended in as
# sink=exited.
# scripts/smoke/verdict.sh holds the verdict. Exit 1 when a check failed.
# Failed or interrupted rows retain bounded logs and probe dumps beside a
# redirected run log, or under tmp/qml-smoke when stdout is not a file.
# --log-dir names that run's log directory explicitly. Each row retains at
# most 8 MiB; scripts/smoke/evidence.py owns the retained set and byte caps.
# Ordinary runs print `qml-smoke: completion=PATH`. That retained JSON is
# the managed run authority: `exit`, `reason`, `requestedStop` and `attempts`
# (the immutable attempt record paths). Each attempt binds `world` (root,
# sandbox and recorder paths), `nativeExit`, `readerExit`, both `joins`,
# and the recorder's separate `collection` judgment to its effective exit
# and reason. Only completion.json is published; hidden candidates are not
# receipts. A missing required record is incomplete, never passing proof.
#
# --first-bar-runs N, N a positive integer, measures the first bar alone:
# it starts the sandbox N times, runs no row, and prints one line per run,
# `run=<i> latency_first_bar_ms=<ms> cpu_some_pct=<pct>
# services_released=<reason> waited_ms=<ms> nested_monitor_ready_secs=<s>`,
# the released reason and waited_ms from the service gate's release line
# (unreleased and - when it logged none), the last the harness's
# nested-monitor-ready reading, or
# `run=<i> status=not-measured exit=<status> log=<path>` for a run whose
# harness exited non-zero or read no bar. The last line is
# `qml-smoke: first-bar runs=<N> measured=<M> highest_ms=<H> budget_ms=<2H>
# highest_waited_ms=<W> deadline_ms=<2W>`, W over the runs released on a
# first frame. A run whose nested compositor stopped answering prints
# `run=<i> status=failed reason=compositor-stalled log=<path>` and the
# mode exits 1 (scripts/smoke/hypr-call.sh). Exit 0 when every run
# measured; otherwise a line naming how many did not and where their logs
# are, then exit 77. One run takes about
# 2 s. --plugin-set picks the set each run starts with: `smoke`, the rows'
# own and the default, or `default`, every first-party plugin enabled as
# in a live session (scripts/smoke/harness.sh); it needs --first-bar-runs.
#
# --rows runs the named rows, each a name --list-rows prints, the core
# rows, and each row one of those reads: the rows its input line names, and
# theirs in turn. scripts/smoke/row-inputs.sh holds the core rows and the
# reader, the ones scripts/validate selects with, so the set it passes on a
# diff-scoped run is already closed and gains no row here:
# docs/architecture/validation.md. The rows run in the order
# scripts/smoke/rows.list fixes, with the harness steps between them;
# without --rows every row runs. The run prints
# `qml-smoke: rows named=<name>,... run=<row>,...` once, before the
# harness starts. A name the runner does not hold is refused as
# `qml-smoke: refused: argument=--rows value=<name> reason=unknown-row`, a
# core row the list does not hold as `qml-smoke: refused: argument=--rows
# value=<row> reason=core-row-missing`, and a row whose input line names a
# row file that the list does not hold and the tree does not have as
# `qml-smoke: refused: argument=--rows value=<row>
# reason=reads-unknown-row reads=<name>`, each before anything starts. A row file the tree has and the list does not is
# one the row runs itself through smoke_row. A row whose input line cannot
# be read prints `qml-smoke: rows inputs=<fault> row=<row>` on stderr and
# brings no row. --list-rows prints the rows a run with the same --rows
# would run, one name per line in run order, and every row without --rows;
# it starts nothing. qml_smoke_wanted decides both.
#
# VGSHELL_SMOKE_RSS_CEILING_KIB: resident-size ceiling for the largest reading
# of the shells the run starts up to rows/diagnostics.sh: each shell a row
# stopped, read at its stop, and the one that row reads (shell_memory_note
# in scripts/smoke/harness.sh). A row that stops and starts the shell
# therefore hides no shell from the ceiling. It catches an allocation
# blow-up at startup or in a row and nothing else: a run this short cannot
# see growth over a session, which the sampler in docs/architecture/runtime.md
# measures, the largest reading grows with the rows the run holds, and it carries the machine's
# graphics stack. The default is twice the highest rss_peak_kib of three
# runs of this script on the owner's machine (host cachy, AMD Ryzen 9
# 9950X) on 2026-10-02, at load average 5 to 12, on one nested monitor:
# 576964 to 587008 KiB over main at 7bb195940, each the run's first shell
# read at its first stop: docs/architecture/validation.md § Latency budgets.
# Each reading prints its high-water mark beside it.
#
# VGSHELL_SMOKE_FIRST_BAR_BUDGET_MS: ceiling on the time from runner startup
# to the first bar surface with a client in the compositor's layer list,
# with 10 ms between unsuccessful polls. The default is twice the highest
# actual diagnostics reading in 20 independent --rows diagnostics runs of
# main bf2f463a5 on cachy (AMD Ryzen 9 9950X, installed engine VGS 2),
# 2026-10-22: 536 to 658 ms, cpu_some_pct 0.5 to 1.0, nearby 1-minute load
# 7.93 to 13.21. Each reading is the session row's final shell restart,
# with that run's fixture and cache state, rather than --first-bar-runs'
# initial shell. VGS-2012 holds the raw distribution and timing limits.
# VGSHELL_SMOKE_DEFAULT_FIRST_BAR_BUDGET_MS: the same ceiling for the start
# over the default set that rows/start-order.sh reads, where every bundled
# plugin's bar widget now takes its first presence. The default is twice
# the highest kept reading of two passes of --first-bar-runs 6
# --plugin-set default on the same machine on 2026-10-05, at load average
# 11 to 15, interleaved with passes over origin/main at d1ff7b3: a pass is
# kept when every run read cpu_some_pct at most 1.3. This tree's 12 kept
# readings were 553 to 713 ms (cpu_some_pct 0.5 to 1.2); main's 11 kept
# readings, one start lost to an unsized nested monitor, were 363 to 467 ms
# (0.5 to 1.3). A pass of each with a run over 1.3 read 646 to 790 ms here
# and 412 to 523 ms on main, and is not kept.
# VGSHELL_SMOKE_RECONCILE_BUDGET_MS: ceiling on the time from a
# setPluginEnabled reply to the build records no longer listing the
# disabled widget, polled with qs ipc. The default is twice the highest
# reading of twelve runs of this script on the same machine on 2026-09-23,
# which read 12 to 15 ms.
# VGSHELL_SMOKE_EMOJI_TOAST_BUDGET_MS: ceiling on the time from the notify
# call for a Slack card with six custom emoji to its body naming the
# images on every screen. VGSHELL_SMOKE_EMOJI_INBOX_BUDGET_MS is the time
# from the history call to forty summoned-panel rows naming their emoji
# images on the visible cards (rows/notifications.sh), counted by a probe
# readback and polled back to back. Each polling turn pays about 22 ms of
# smoke IPC round-trip cost. The toast default is twice the highest reading
# of 21 runs of --rows bar,hyprland-consent,plugins,capabilities,status,
# notifications over main at b30c8a16 on the owner's machine (host cachy,
# AMD Ryzen 9 9950X) on 2026-10-06, under the fleet's load of ten lanes,
# load average 7.4 to 13.7, cpu_some_pct 0.1 to 1.7, one toast reading a
# run; one start was lost to an unsized nested monitor. The 20 readings
# were 34 to 58 ms; the nine at load average under 9 read 34 to 38 ms.
# A reading above harness.sh's latency_pressure_limit, such as one at
# cpu_some_pct 33.7 (130 ms), is unmeasured. The inbox default is twice the
# highest reading of the summoned-panel image-count reader on the same
# machine on 2026-10-01, at load average 5.58 to 8.80: 651 to 688 ms.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
# The rows, in the order they run: scripts/smoke/rows.list, which holds the
# reasons for the order beside them. A line that is not a comment, blank or
# one row name is refused, so a list read here is the list scripts/validate
# selects from.
qml_smoke_list_file="$repo/scripts/smoke/rows.list"
if ! mapfile -t qml_smoke_lines <"$qml_smoke_list_file"; then
  printf 'qml-smoke: refused: rows-list=unreadable path=%s\n' "$qml_smoke_list_file" >&2; exit 2
fi
qml_smoke_rows=()
for qml_smoke_line_no in "${!qml_smoke_lines[@]}"; do
  qml_smoke_row="${qml_smoke_lines[qml_smoke_line_no]}"
  [[ -z $qml_smoke_row || $qml_smoke_row == '#'* ]] && continue
  if [[ ! $qml_smoke_row =~ ^[a-z0-9-]+$ ]]; then
    printf 'qml-smoke: refused: rows-list=malformed line=%d path=%s\none row name a line, or a line that starts with #\n' "$((qml_smoke_line_no + 1))" "$qml_smoke_list_file" >&2; exit 2
  fi
  qml_smoke_rows+=("$qml_smoke_row")
done
if [[ ${#qml_smoke_rows[@]} -eq 0 ]]; then
  printf 'qml-smoke: refused: rows-list=empty path=%s\n' "$qml_smoke_list_file" >&2; exit 2
fi

argv=("$@")
timeout_s=60
keep=false
smoke_log_dir=""
source_tree="$repo"
nix_store=""
first_bar_runs=""
plugin_set=smoke
qml_smoke_only=""
qml_smoke_named=()
qml_smoke_list=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) timeout_s="$2"; shift 2 ;;
    --keep) keep=true; shift ;;
    --tree|--nix-store)
      if [[ $# -lt 2 || ! -d $2 ]]; then printf 'qml-smoke: refused: argument=%s value=%s\n' "$1" "${2-}" >&2; exit 2; fi
      if [[ $1 == --tree ]]; then source_tree="$(realpath -e -- "$2")"; else nix_store="$(realpath -e -- "$2")"; fi
      shift 2 ;;
    --log-dir)
      if [[ $# -lt 2 || -z $2 ]]; then printf 'qml-smoke: refused: argument=--log-dir value=missing\n' >&2; exit 2; fi
      smoke_log_dir="$(realpath -m -- "$2")"; shift 2 ;;
    --first-bar-runs)
      if [[ $# -lt 2 || ! $2 =~ ^[1-9][0-9]*$ ]]; then printf 'qml-smoke: refused: argument=--first-bar-runs value=%s\n' "${2-}" >&2; exit 2; fi
      first_bar_runs="$2"; shift 2 ;;
    --plugin-set)
      if [[ $# -lt 2 || ! $2 =~ ^(smoke|default)$ ]]; then printf 'qml-smoke: refused: argument=--plugin-set value=%s\n' "${2-}" >&2; exit 2; fi
      plugin_set="$2"; shift 2 ;;
    --rows)
      if [[ $# -lt 2 || ! $2 =~ ^[a-z0-9-]+(,[a-z0-9-]+)*$ ]]; then printf 'qml-smoke: refused: argument=--rows value=%s\n' "${2-}" >&2; exit 2; fi
      IFS=, read -r -a qml_smoke_named <<<"$2"
      for qml_smoke_row in "${qml_smoke_named[@]}"; do
        if [[ " ${qml_smoke_rows[*]} " != *" $qml_smoke_row "* ]]; then printf 'qml-smoke: refused: argument=--rows value=%s reason=unknown-row\n' "$qml_smoke_row" >&2; exit 2; fi
      done
      shift 2 ;;
    --list-rows) qml_smoke_list=true; shift ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) printf 'qml-smoke: refused: argument=%s\n' "$1" >&2; exit 2 ;;
  esac
done
if [[ -n $nix_store && $qml_smoke_list != true && ! -e /etc/NIXOS ]]; then
  printf 'qml-smoke: status=not-measured reason=nixos-graphics-required tree=%s\n' "$source_tree" >&2
  exit 77
fi
# The rows read the smoke set's state, so another set only measures.
if [[ $plugin_set != smoke && -z $first_bar_runs ]]; then
  printf 'qml-smoke: refused: argument=--plugin-set value=%s reason=needs-first-bar-runs\n' "$plugin_set" >&2
  exit 2
fi
if [[ ${#qml_smoke_named[@]} -gt 0 && -n $first_bar_runs ]]; then
  printf 'qml-smoke: refused: argument=--rows reason=first-bar-runs-runs-no-row\n' >&2
  exit 2
fi
# The rows --rows names bring the core rows, whose state any row may read,
# and the rows each of those reads: qml_smoke_reach holds each row
# reached, and the queue each row whose input line is still to read. A
# named row file that is no listed row is the reading row's own
# when the tree has it; one the tree lacks is a row that left or a
# misspelt name, which would end the run in a command not found.
if [[ ${#qml_smoke_named[@]} -gt 0 ]]; then
  source "$repo/scripts/smoke/row-inputs.sh"
  declare -A qml_smoke_reach=()
  for qml_smoke_row in "${smoke_core[@]}"; do
    if [[ " ${qml_smoke_rows[*]} " != *" $qml_smoke_row "* ]]; then printf 'qml-smoke: refused: argument=--rows value=%s reason=core-row-missing\n' "$qml_smoke_row" >&2; exit 2; fi
  done
  qml_smoke_queue=("${qml_smoke_named[@]}" "${smoke_core[@]}")
  while [[ ${#qml_smoke_queue[@]} -gt 0 ]]; do
    qml_smoke_row="${qml_smoke_queue[0]}"
    qml_smoke_queue=("${qml_smoke_queue[@]:1}")
    [[ -z ${qml_smoke_reach[$qml_smoke_row]-} ]] || continue
    qml_smoke_reach[$qml_smoke_row]=1
    if ! smoke_inputs_read "$repo/scripts/smoke/rows/$qml_smoke_row.sh"; then
      printf 'qml-smoke: rows inputs=%s row=%s\n' "$smoke_inputs_fault" "$qml_smoke_row" >&2
      continue
    fi
    smoke_inputs_rows "$qml_smoke_row"
    for qml_smoke_read in "${smoke_inputs_named[@]}"; do
      if [[ " ${qml_smoke_rows[*]} " == *" $qml_smoke_read "* ]]; then
        qml_smoke_queue+=("$qml_smoke_read")
      elif [[ ! -f $repo/scripts/smoke/rows/$qml_smoke_read.sh ]]; then
        printf 'qml-smoke: refused: argument=--rows value=%s reason=reads-unknown-row reads=%s\n' "$qml_smoke_row" "$qml_smoke_read" >&2; exit 2
      fi
    done
  done
  for qml_smoke_row in "${qml_smoke_rows[@]}"; do
    [[ -z ${qml_smoke_reach[$qml_smoke_row]-} ]] || qml_smoke_only+=",$qml_smoke_row"
  done
  qml_smoke_only+=,
fi
# qml_smoke_wanted ROW: whether this run runs ROW, the one answer the row
# loop below and --list-rows read.
qml_smoke_wanted() { [[ -z $qml_smoke_only || $qml_smoke_only == *",$1,"* ]]; }
if [[ $qml_smoke_list == true ]]; then
  for qml_smoke_row in "${qml_smoke_rows[@]}"; do
    if qml_smoke_wanted "$qml_smoke_row"; then printf '%s\n' "$qml_smoke_row"; fi
  done
  exit 0
fi

# No process this run starts may open an amdgpu node, so the run goes on
# only where none is visible: scripts/smoke/gpu-fence.sh.
world_args=(--out "$repo/tmp/display-record")
[[ $source_tree == "$repo" ]] || world_args+=(--input "$source_tree")
[[ -z $nix_store ]] || world_args+=(--nix-store "$nix_store")
[[ $keep != true ]] || world_args+=(--keep)
if [[ -z $smoke_log_dir ]]; then
  # Keep the caller's fd: a command substitution gives its child a pipe.
  smoke_stdout="/proc/$BASHPID/fd/1"
  if [[ -f $smoke_stdout ]]; then
    smoke_log_file="$(readlink -f -- "$smoke_stdout")"
    smoke_log_dir="${smoke_log_file%/*}"
  else
    smoke_log_dir="$repo/tmp/qml-smoke"
  fi
fi
world_args+=(--out "$smoke_log_dir")
if [[ -n $first_bar_runs || -n ${qml_smoke_attempt:-} ]]; then
  "$repo/scripts/smoke/gpu-fence.sh" --check || exec "$repo/scripts/smoke/gpu-fence.sh" "${world_args[@]}" "$self" "${argv[@]}"
fi
if [[ -n $qml_smoke_only && -z ${qml_smoke_attempt:-} ]]; then
  qml_smoke_run="${qml_smoke_only#,}"
  (IFS=,; printf 'qml-smoke: rows named=%s run=%s\n' "${qml_smoke_named[*]}" "${qml_smoke_run%,}")
fi
rss_ceiling_kib="${VGSHELL_SMOKE_RSS_CEILING_KIB:-1174016}"
first_bar_budget_ms="${VGSHELL_SMOKE_FIRST_BAR_BUDGET_MS:-1316}"
default_first_bar_budget_ms="${VGSHELL_SMOKE_DEFAULT_FIRST_BAR_BUDGET_MS:-1426}"
reconcile_budget_ms="${VGSHELL_SMOKE_RECONCILE_BUDGET_MS:-30}"
emoji_toast_budget_ms="${VGSHELL_SMOKE_EMOJI_TOAST_BUDGET_MS:-116}"
emoji_inbox_budget_ms="${VGSHELL_SMOKE_EMOJI_INBOX_BUDGET_MS:-1376}"

# The measurement mode. Each run sources the harness in its own subshell,
# so its teardown runs when the subshell exits, and the harness's output
# goes to that run's log. The subshell is no operand of || or &&, where
# bash would ignore the harness's set -e.
if [[ -n $first_bar_runs ]]; then
  if ! first_bar_logs="$(mktemp -d "${TMPDIR:-/tmp}/qml-smoke-first-bar.XXXXXX")"; then
    printf 'qml-smoke: refused: scratch=%s\n' "${TMPDIR:-/tmp}" >&2
    exit 1
  fi
  measured=0
  stalled=0
  highest=0
  highest_waited=""
  for ((run = 1; run <= first_bar_runs; run++)); do
    log="$first_bar_logs/run-$run.log"
    result="$first_bar_logs/run-$run.result"
    set +e
    (
      source "$repo/scripts/smoke/harness.sh"
      printf '%s %s %s %s\n' "${first_bar_ms:-unmeasured}" "$first_bar_cpu_some_pct" "$(service_release)" "$nested_monitor_ready_secs" >"$result"
    ) >"$log" 2>&1 </dev/null
    status=$?
    set -e
    ms=""
    pct=""
    reason=""
    waited=""
    ready=""
    if [[ $status -eq 0 && -f $result ]]; then read -r ms pct reason waited ready <"$result"; fi
    if [[ $status -eq 0 && $ms =~ ^[0-9]+$ ]]; then
      measured=$((measured + 1))
      if ((ms > highest)); then highest=$ms; fi
      if [[ $reason == first-frame ]] && { [[ -z $highest_waited ]] || ((waited > highest_waited)); }; then highest_waited=$waited; fi
      printf 'run=%d latency_first_bar_ms=%d cpu_some_pct=%s services_released=%s waited_ms=%s nested_monitor_ready_secs=%s\n' "$run" "$ms" "$pct" "$reason" "$waited" "$ready"
    elif grep -qF -- '  FAIL  the nested compositor stopped answering: ' "$log"; then
      stalled=$((stalled + 1))
      printf 'run=%d status=failed reason=compositor-stalled log=%s\n' "$run" "$log"
    else
      printf 'run=%d status=not-measured exit=%d log=%s\n' "$run" "$status" "$log"
    fi
  done
  if ((measured > 0)); then
    printf 'qml-smoke: first-bar runs=%d measured=%d highest_ms=%d budget_ms=%d highest_waited_ms=%s deadline_ms=%s\n' "$first_bar_runs" "$measured" "$highest" $((highest * 2)) \
      "${highest_waited:-unmeasured}" "$([[ -n $highest_waited ]] && echo $((highest_waited * 2)) || echo unmeasured)"
  else
    printf 'qml-smoke: first-bar runs=%d measured=0 highest_ms=unmeasured budget_ms=unmeasured\n' "$first_bar_runs"
  fi
  if ((stalled > 0)); then
    printf 'qml-smoke: failed first-bar-stalled=%d logs=%s\n' "$stalled" "$first_bar_logs"
    exit 1
  fi
  if ((measured < first_bar_runs)); then
    printf 'qml-smoke: status=not-measured first-bar-unmeasured=%d logs=%s\n' $((first_bar_runs - measured)) "$first_bar_logs"
    exit 77
  fi
  rm -rf -- "$first_bar_logs"
  exit 0
fi

# A fatal expansion bypasses ERR. Keep the existing world entry as its
# completion boundary: it returns only after EXIT and namespace teardown.
# The private source invocation selects one attempt without exporting state
# or moving any of the harness's jobs, waits or descriptors to this driver.
if [[ -z ${qml_smoke_attempt:-} ]]; then
  # Only private bookkeeping is written here. The world owns validation and
  # creation of every requested output before the worker writes there.
  qml_smoke_driver="$(mktemp -d "${TMPDIR:-/tmp}/qml-smoke-resume.XXXXXX")" || { echo 'qml-smoke: scratch=mktemp-failed' >&2; exit 1; }
  [[ -d $qml_smoke_driver && ! -L $qml_smoke_driver ]] || { echo 'qml-smoke: scratch=not-a-directory' >&2; exit 1; }
  qml_smoke_driver="$(cd -- "$qml_smoke_driver" && pwd -P)" || { echo 'qml-smoke: scratch=resolve-failed' >&2; exit 1; }
  qml_smoke_pending=()
  for qml_smoke_row in "${qml_smoke_rows[@]}"; do
    qml_smoke_wanted "$qml_smoke_row" && qml_smoke_pending+=("$qml_smoke_row")
  done
  declare -A qml_smoke_results=() qml_smoke_fatal=() qml_smoke_blocked=()
  qml_smoke_status=0
  qml_smoke_incomplete=false
  qml_smoke_outside_failures=0
  qml_smoke_attempt_no=0
  qml_smoke_cancel_status=0
  qml_smoke_cancel_forwarded=0
  qml_smoke_fence_pid=""
  qml_smoke_log_pid=""
  qml_smoke_phase=between
  qml_smoke_completions=()
  printf 'qml-smoke: completion=%s/completion.json\n' "$qml_smoke_driver"
  # Each child stays with this driver until its wait completes. As in the
  # fence's monitor wait, checking its parent excludes a reused foreign PID.
  qml_smoke_owns_child() {
    local fields=()
    read -r -a fields 2>/dev/null <"/proc/$1/stat" && [[ ${fields[3]-} == "$BASHPID" ]]
  }
  qml_smoke_wait_child() {
    while qml_smoke_owns_child "$1"; do wait "$1" || true; done
    wait "$1"
  }
  qml_smoke_cancel() {
    ((qml_smoke_cancel_status != 0 || (qml_smoke_cancel_status=$2)))
    # The fleet caller normalizes every stop to TERM. A PID-only INT can
    # leave Bash's foreground child running, so use that same stop form.
    if [[ $qml_smoke_phase == attempt && -n $qml_smoke_fence_pid ]] && qml_smoke_owns_child "$qml_smoke_fence_pid" && ((qml_smoke_cancel_forwarded++ == 0)); then
      kill -TERM -- "$qml_smoke_fence_pid" 2>/dev/null || true
    fi
  }
  # Prepare every possible first-stop outcome while acceptance is open.
  # The seal selects one already-written record; no earlier snapshot can
  # compete with a trap during serialization. Only this driver publishes.
  qml_smoke_prepare_completion() { # KIND DIRECTORY NATIVE_EXIT READER_EXIT RECORD...
    python3 - "$@" <<'PY'
import json, pathlib, sys
kind, directory, native, reader, *records = sys.argv[1:]
root = pathlib.Path(directory)
native, reader = int(native), int(reader)
payload = dict(schema="vgs.smoke-completion.v1", kind=kind, authority=str(root / "completion.json"))
try:
    if kind == "attempt":
        world, sandbox, recorder, authority, empty = (root / "world").read_bytes().split(b"\0")
        world, sandbox, recorder, authority = [v.decode() for v in (world, sandbox, recorder, authority)]
        if empty or authority != str(root / "completion.json") or not all((world, sandbox, recorder)):
            raise ValueError("world-binding")
        teardown = dict(line.split("=", 1) for line in (pathlib.Path(recorder) / "teardown").read_text().splitlines())
        if teardown["completion"] != authority:
            raise ValueError("recorder-authority")
        collection = json.loads((pathlib.Path(recorder) / "completeness.json").read_text())
        payload.update(attempt=root.name, world=dict(root=world, sandbox=sandbox, recorder=recorder),
                       nativeExit=native, readerExit=reader, worldExit=int(teardown["world_exit"]),
                       recorderExit=int(teardown["recorder_exit"]), collection=collection,
                       joins=dict(fence=True, reader=True))
    else:
        for record in records:
            attempt = json.loads(pathlib.Path(record).read_text())
            if attempt["kind"] != "attempt" or attempt["authority"] != record:
                raise ValueError("attempt-binding")
        payload["attempts"] = records
    # Completeness remains the recorder's collection judgment. A native
    # product verdict does not promote incomplete observations to complete.
    for stop in (0, 129, 130, 143):
        status = stop or (1 if reader else native)
        reason = {0: "passed", 1: "failed", 77: "not-measured"}.get(status, "interrupted:" + str(status))
        value = dict(payload, exit=status, reason=reason, requestedStop=stop)
        with (root / (".completion-" + str(stop))).open("x") as file:
            json.dump(value, file)
            file.write("\n")
except (OSError, ValueError, KeyError, TypeError) as error:
    print("qml-smoke: failed-operation=completion-input path=" + str(root) + " cause=" + str(error), file=sys.stderr)
    sys.exit(1)
PY
  }
  trap 'qml_smoke_cancel TERM 143' TERM
  trap 'qml_smoke_cancel INT 130' INT
  trap 'qml_smoke_cancel HUP 129' HUP
  while ((${#qml_smoke_pending[@]})); do
    ((qml_smoke_cancel_status == 0)) || break
    qml_smoke_left=()
    for qml_smoke_row in "${qml_smoke_pending[@]}"; do
      qml_smoke_blocker=""
      if ((${#qml_smoke_fatal[@]})); then
        qml_smoke_dependencies="$("$self" --rows "$qml_smoke_row" --list-rows)"
        while read -r qml_smoke_dependency; do
          if [[ -n ${qml_smoke_fatal[$qml_smoke_dependency]-} ]]; then
            qml_smoke_blocker=$qml_smoke_dependency
            break
          fi
        done <<<"$qml_smoke_dependencies"
      fi
      if [[ -n $qml_smoke_blocker ]]; then
        qml_smoke_blocked[$qml_smoke_row]=$qml_smoke_blocker
        printf '  FAIL  %s: blocked producer=%s diagnostic=[%s]\n' "$qml_smoke_row" "$qml_smoke_blocker" "${qml_smoke_fatal[$qml_smoke_blocker]}"
      else
        qml_smoke_left+=("$qml_smoke_row")
      fi
    done
    qml_smoke_pending=("${qml_smoke_left[@]}")
    ((${#qml_smoke_pending[@]})) || break
    qml_smoke_attempt_no=$((qml_smoke_attempt_no + 1))
    qml_smoke_attempt="$qml_smoke_driver/$qml_smoke_attempt_no"
    qml_smoke_completion="$qml_smoke_attempt/completion.json"
    mkdir -p -- "$qml_smoke_attempt/results" "$qml_smoke_attempt/partial"
    qml_smoke_next="$(IFS=,; printf '%s' "${qml_smoke_pending[*]}")"
    printf 'qml-smoke: attempt=%s targets=%s\n' "$qml_smoke_attempt" "$qml_smoke_next"
    ((qml_smoke_cancel_status == 0)) || break
    qml_smoke_phase=attempt
    # Separate waits make the public PID interruptible without signalling
    # the log reader. Close the driver's writer before waiting for EOF.
    qml_smoke_log_pid=pending
    exec {qml_smoke_log_fd}> >(exec env --default-signal=INT,QUIT tee "$qml_smoke_attempt/run.log")
    qml_smoke_log_pid=$!
    if ((qml_smoke_cancel_status == 0)); then
      env --default-signal=INT,QUIT "$repo/scripts/smoke/gpu-fence.sh" --fresh "${world_args[@]}" --out "$qml_smoke_attempt" \
        "$BASH" -c 'qml_smoke_attempt=$1; qml_smoke_completion=$2; shift 2; source "$@"' "$self" "$qml_smoke_attempt" "$qml_smoke_completion" "$self" \
        "${argv[@]}" --rows "$qml_smoke_next" --log-dir "$smoke_log_dir" >&"$qml_smoke_log_fd" 2>&1 {qml_smoke_log_fd}>&- &
      qml_smoke_fence_pid=$!
      if ((qml_smoke_cancel_status != 0)); then qml_smoke_cancel stop "$qml_smoke_cancel_status"; fi
    fi
    exec {qml_smoke_log_fd}>&-
    qml_smoke_attempt_status=0
    if [[ -n $qml_smoke_fence_pid ]]; then
      qml_smoke_wait_child "$qml_smoke_fence_pid" || qml_smoke_attempt_status=$?
      qml_smoke_fence_pid=""
    fi
    qml_smoke_log_status=0
    qml_smoke_wait_child "$qml_smoke_log_pid" || qml_smoke_log_status=$?
    qml_smoke_log_pid=""
    if [[ $qml_smoke_log_status != 0 ]]; then
      printf 'qml-smoke: failed-operation=run-log path=%s\n' "$qml_smoke_attempt/run.log" >&2
    fi
    if ! qml_smoke_prepare_completion attempt "$qml_smoke_attempt" "$qml_smoke_attempt_status" "$qml_smoke_log_status"; then
      qml_smoke_status=1
      break
    fi
    # One Bash command orders first-stop acceptance against this attempt.
    # A subsequent stop belongs to the still-open run alone.
    qml_smoke_attempt_stop=$qml_smoke_cancel_status qml_smoke_phase=between
    if ! mv -- "$qml_smoke_attempt/.completion-$qml_smoke_attempt_stop" "$qml_smoke_completion"; then
      printf 'qml-smoke: failed-operation=completion-publish path=%s\n' "$qml_smoke_completion" >&2
      qml_smoke_status=1
      break
    fi
    qml_smoke_completions+=("$qml_smoke_completion")
    ((qml_smoke_cancel_status == 0)) || break
    if [[ $qml_smoke_log_status != 0 ]]; then
      qml_smoke_status=1
      break
    fi
    if [[ -f $qml_smoke_attempt/outside-failures ]]; then
      mapfile -d '' -t qml_smoke_outside <"$qml_smoke_attempt/outside-failures"
      ((qml_smoke_outside[0] <= qml_smoke_outside_failures)) || qml_smoke_outside_failures=${qml_smoke_outside[0]}
    fi
    # A producer runs again to rebuild state; its result appears once. Keep
    # its worst reading, including a new failure or unavailable measurement.
    # Partial outcomes share the format; only results/ proves completion.
    for qml_smoke_row in "${qml_smoke_rows[@]}"; do
      for qml_smoke_record in "$qml_smoke_attempt/partial/$qml_smoke_row" "$qml_smoke_attempt/results/$qml_smoke_row"; do
        [[ -f $qml_smoke_record ]] || continue
        mapfile -d '' -t qml_smoke_result <"$qml_smoke_record"
        qml_smoke_previous=(0)
        if [[ -n ${qml_smoke_results[$qml_smoke_row]-} ]]; then
          mapfile -d '' -t qml_smoke_previous <"${qml_smoke_results[$qml_smoke_row]}"
        fi
        if ((qml_smoke_result[0] > qml_smoke_previous[0] || (qml_smoke_result[0] == qml_smoke_previous[0] && ${#qml_smoke_result[@]} >= ${#qml_smoke_previous[@]}))); then
          qml_smoke_results[$qml_smoke_row]=$qml_smoke_record
        fi
      done
    done
    qml_smoke_left=()
    for qml_smoke_row in "${qml_smoke_pending[@]}"; do
      if [[ ! -f $qml_smoke_attempt/results/$qml_smoke_row ]]; then
        qml_smoke_left+=("$qml_smoke_row")
      fi
    done
    qml_smoke_pending=("${qml_smoke_left[@]}")
    qml_smoke_open=""
    [[ ! -f $qml_smoke_attempt/active ]] || read -r qml_smoke_open <"$qml_smoke_attempt/active"
    qml_smoke_diagnostic=""
    qml_smoke_sandbox_name=""
    [[ ! -f $qml_smoke_attempt/sandbox ]] || read -r qml_smoke_sandbox_name <"$qml_smoke_attempt/sandbox"
    qml_smoke_output="$smoke_log_dir/smoke-evidence-$qml_smoke_sandbox_name/$qml_smoke_open/row/$qml_smoke_open.out"
    if [[ -n $qml_smoke_sandbox_name && -f $qml_smoke_output ]]; then
      qml_smoke_diagnostic="$(sed -n '/^\/.*: line [0-9][0-9]*: .*\(unbound variable\|syntax error\|value too great for base\)/p' "$qml_smoke_output" | tail -n 1)"
    fi
    if [[ $qml_smoke_attempt_status != 0 && -n $qml_smoke_open && -n $qml_smoke_diagnostic ]]; then
      printf '  FAIL  %s: fatal Bash error status=%s diagnostic=[%s]\n' "$qml_smoke_open" "$qml_smoke_attempt_status" "$qml_smoke_diagnostic"
      qml_smoke_fatal[$qml_smoke_open]=$qml_smoke_diagnostic
      qml_smoke_status=1
      qml_smoke_left=()
      for qml_smoke_row in "${qml_smoke_pending[@]}"; do
        [[ $qml_smoke_row == "$qml_smoke_open" ]] || qml_smoke_left+=("$qml_smoke_row")
      done
      qml_smoke_pending=("${qml_smoke_left[@]}")
      # Before another world, each newly fatal row or its pending consumers
      # leave the target set. Known-fatal producers are never replayed.
      ((${#qml_smoke_pending[@]} == 0)) || printf 'qml-smoke: resume after=%s remaining=%s\n' "$qml_smoke_open" "$(IFS=,; printf '%s' "${qml_smoke_pending[*]}")"
      continue
    fi
    if [[ $qml_smoke_attempt_status != 0 ]]; then
      if [[ $qml_smoke_attempt_status == 77 && $qml_smoke_status == 0 ]]; then qml_smoke_status=77; else qml_smoke_status=1; fi
    fi
    if [[ $qml_smoke_attempt_status == 0 && ${#qml_smoke_pending[@]} -gt 0 ]]; then
      qml_smoke_status=1
      qml_smoke_incomplete=true
      printf 'qml-smoke: incomplete-attempt=%s remaining=%s\n' "$qml_smoke_attempt" "$(IFS=,; printf '%s' "${qml_smoke_pending[*]}")" >&2
    fi
    break
  done
  qml_smoke_failures=$((${#qml_smoke_fatal[@]} + ${#qml_smoke_blocked[@]} + qml_smoke_outside_failures))
  qml_smoke_unmeasured=()
  for qml_smoke_row in "${qml_smoke_rows[@]}"; do
    if [[ -n ${qml_smoke_results[$qml_smoke_row]-} ]]; then
      mapfile -d '' -t qml_smoke_result <"${qml_smoke_results[$qml_smoke_row]}"
      qml_smoke_failures=$((qml_smoke_failures + qml_smoke_result[0]))
      qml_smoke_unmeasured+=("${qml_smoke_result[@]:1}")
    fi
    if [[ -n ${qml_smoke_fatal[$qml_smoke_row]-} ]]; then
      printf 'qml-smoke: row-result row=%s status=failed cause=fatal-bash\n' "$qml_smoke_row"
    elif [[ -n ${qml_smoke_blocked[$qml_smoke_row]-} ]]; then
      printf 'qml-smoke: row-result row=%s status=blocked producer=%s\n' "$qml_smoke_row" "${qml_smoke_blocked[$qml_smoke_row]}"
    elif [[ $qml_smoke_incomplete == true && " ${qml_smoke_pending[*]} " == *" $qml_smoke_row "* ]]; then
      qml_smoke_failures=$((qml_smoke_failures + 1))
      printf 'qml-smoke: row-result row=%s status=failed cause=incomplete-attempt\n' "$qml_smoke_row"
    elif [[ -n ${qml_smoke_results[$qml_smoke_row]-} ]]; then
      if ((qml_smoke_result[0] > 0)); then qml_smoke_row_status=failed
      elif ((${#qml_smoke_result[@]} > 1)); then qml_smoke_row_status=not-measured
      else qml_smoke_row_status=ok; fi
      printf 'qml-smoke: row-result row=%s status=%s\n' "$qml_smoke_row" "$qml_smoke_row_status"
    fi
  done
  if ((qml_smoke_status == 1 || (qml_smoke_failures > 0 && qml_smoke_status != 77))); then
    printf 'qml-smoke: failed=%s\n' "$qml_smoke_failures"
    qml_smoke_status=1
  elif ((qml_smoke_status != 0 || ${#qml_smoke_unmeasured[@]})); then
    printf 'qml-smoke: status=not-measured rows=%s\n' "$(IFS=,; printf '%s' "${qml_smoke_unmeasured[*]}")"
    qml_smoke_status=77
  fi
  if ! qml_smoke_prepare_completion run "$qml_smoke_driver" "$qml_smoke_status" 0 "${qml_smoke_completions[@]}"; then
    ((qml_smoke_cancel_status != 0)) || qml_smoke_cancel_status=1
    trap '' TERM INT HUP
    exit "$qml_smoke_cancel_status"
  fi
  # Final run seal: later stop signals cannot alter this record or exit.
  trap '' TERM INT HUP
  qml_smoke_run_stop=$qml_smoke_cancel_status
  qml_smoke_run_exit=$qml_smoke_status
  ((qml_smoke_run_stop == 0)) || qml_smoke_run_exit=$qml_smoke_run_stop
  if ! mv -- "$qml_smoke_driver/.completion-$qml_smoke_run_stop" "$qml_smoke_driver/completion.json"; then
    printf 'qml-smoke: failed-operation=completion-publish path=%s/completion.json\n' "$qml_smoke_driver" >&2
    exit 1
  fi
  if ((qml_smoke_run_stop != 0)); then
    case "$qml_smoke_run_stop" in 129) qml_smoke_cancel_signal=HUP ;; 130) qml_smoke_cancel_signal=INT ;; 143) qml_smoke_cancel_signal=TERM ;; esac
    printf 'qml-smoke: cancelled signal=%s status=%s\n' "$qml_smoke_cancel_signal" "$qml_smoke_run_stop"
  elif ((qml_smoke_run_exit == 0)); then
    echo 'qml-smoke: ok'
  fi
  exit "$qml_smoke_run_exit"
fi


# Every sandbox shell finds vsys, the browser-policy writer, tesseract,
# voxtype, voxtype-audio-bridge, claude and codex absent, whatever the
# host holds, so the rows press Install all missing for vsys and Install
# browser theming on any host, read OCR and Voice missing without
# restarting the shell, and reach no host Claude Code or Codex, whose
# sign-ins AI Usage reads (harness.sh's shell_hidden_commands); a row that
# needs one present stands its own stand-in for it.
# shellcheck disable=SC2034 # the harness sourced below reads it
shell_hidden_commands+=(vsys vgshell-browser-policy tesseract voxtype voxtype-audio-bridge claude codex)
# The Bar's width checks need a validation layout independent of the host.
# shellcheck disable=SC2034 # the harness sourced below reads it
shell_output_size=1755x933
source "$repo/scripts/smoke/harness.sh"
printf '%s\n' "${sandbox##*/}" >"$qml_smoke_attempt/sandbox"
qml_smoke_row_failures=0
qml_smoke_attempt_owner=$BASHPID

# smoke_row (harness.sh) sources each row and fails one whose output holds
# a traceback. The step after hyprland-consent runs whatever --rows names.
for qml_smoke_row in "${qml_smoke_rows[@]}"; do
  if qml_smoke_wanted "$qml_smoke_row"; then
    qml_smoke_failures_before=$failures
    qml_smoke_not_measured_before=${#not_measured_rows[@]}
    qml_smoke_leak_before="$BASHPID-$((leak_seq + 1))"
    smoke_outcome_journal
    printf '%s\n' "$qml_smoke_row" "${instance_log:-}" "$qml_smoke_leak_before" >"$sandbox/evidence/active" || true
    printf '%s\n' "$qml_smoke_row" >"$qml_smoke_attempt/active"
    smoke_row "$qml_smoke_row"
    qml_smoke_row_failures=$((qml_smoke_row_failures + failures - qml_smoke_failures_before))
    printf '%s\0' "$((failures - qml_smoke_failures_before))" "${not_measured_rows[@]:qml_smoke_not_measured_before}" >"$qml_smoke_attempt/results/$qml_smoke_row.new"
    mv -- "$qml_smoke_attempt/results/$qml_smoke_row.new" "$qml_smoke_attempt/results/$qml_smoke_row"
    rm -- "$qml_smoke_attempt/active"
    if ((failures > qml_smoke_failures_before)); then
      printf '%s\n' "$BASHPID-$leak_seq" >>"$sandbox/evidence/active" || true
      mv -- "$sandbox/evidence/active" "$sandbox/evidence/failed/$qml_smoke_row" || true
    else
      rm -f -- "$sandbox/evidence/active" || true
    fi
  fi
  if [[ $qml_smoke_row == hyprland-consent ]]; then
    # bar.sh read the startup latencies; the cursor rows need the log.
    if compositor_logs_on; then ok "the nested compositor logs from here on"; else fail "the nested compositor's logs did not turn on"; fi
  fi
done

smoke_outcome_journal
smoke_finish
