#!/usr/bin/env bash
# Run the shell inside a nested Hyprland sandbox and check it end to end.
#
# Usage: scripts/qml-smoke.sh [--timeout SECONDS] [--keep] [--rows NAME[,NAME...]]
#        scripts/qml-smoke.sh --first-bar-runs N [--plugin-set smoke|default] [--timeout SECONDS]
#        scripts/qml-smoke.sh --list-rows
#
# The sandbox is built from the repository alone: its own HOME, XDG dirs and
# runtime dir, a minimal compositor config, no user state. It never touches
# the live session: the nested compositor gets its own runtime dir, the
# shell is addressed through that runtime dir, and teardown kills only the
# process groups this run created.
#
# Exit 0 when every check passed. Exit 77 when a prerequisite is missing,
# naming it; when the nested compositor still lists a monitor with no size
# after 10 s, nested-monitor=unsized, since it configures no bar there;
# or when a run whose only failures are geometry or render rows
# met a sandbox fault: the nested window's output rejected a state because
# its buffers could not be allocated, which the nested compositor logs as
# `Output WAYLAND-<n>: pending state rejected: swapchain failed
# reconfiguring` (a bare GBM allocation failure, which passing runs log for
# the headless output, is not that fault), or the host withheld frame
# callbacks so the shell never drew again; that is not a pass. A run whose
# every failure came after the nested output left a mode a row held,
# nested-output=mode-reset, is not a pass either.
# scripts/smoke/verdict.sh holds the verdict. Exit 1 when a check failed.
#
# --first-bar-runs N, N a positive integer, measures the first bar alone:
# it starts the sandbox N times, runs no row, and prints one line per run,
# `run=<i> latency_first_bar_ms=<ms> cpu_some_pct=<pct>
# services_released=<reason> waited_ms=<ms>`, the last two from the
# service gate's release line (unreleased and - when it logged none), or
# `run=<i> status=not-measured exit=<status> log=<path>` for a run whose
# harness exited non-zero or read no bar. The last line is
# `qml-smoke: first-bar runs=<N> measured=<M> highest_ms=<H> budget_ms=<2H>
# highest_waited_ms=<W> deadline_ms=<2W>`, W over the runs released on a
# first frame. Exit 0 when every run measured; otherwise a line naming how
# many did not and where their logs are, then exit 77. One run takes about
# 2 s. --plugin-set picks the set each run starts with: `smoke`, the rows'
# own and the default, or `default`, every first-party plugin enabled as
# in a live session (scripts/smoke/harness.sh); it needs --first-bar-runs.
#
# --rows runs only the named rows, each a name --list-rows prints, in the
# order scripts/smoke/rows.list fixes, with the harness steps between them;
# without it every row runs. It adds no row: the core rows and the rows an
# input line names come only from scripts/validate, which passes it on a
# diff-scoped run:
# docs/architecture/validation-runner.md § Method. A name the runner does
# not hold is refused as `qml-smoke: refused: argument=--rows value=<name>
# reason=unknown-row`. --list-rows prints the rows a run with the same
# --rows would run, one name per line in run order, and every row without
# --rows; it starts nothing. qml_smoke_wanted decides both.
#
# VGSH_SMOKE_RSS_CEILING_KIB: resident-size ceiling for the largest reading
# of the shells the run starts up to rows/diagnostics.sh: each shell a row
# stopped, read at its stop, and the one that row reads (shell_memory_note
# in scripts/smoke/harness.sh). A row that stops and starts the shell
# therefore hides no shell from the ceiling. It catches an allocation
# blow-up at startup or in a row and nothing else: a run this short cannot
# see growth over a session, which the sampler in docs/architecture/memory.md
# measures, the largest reading grows with the rows the run holds, and it carries the machine's
# graphics stack. The default is twice the highest rss_peak_kib of three
# runs of this script on the owner's machine (host cachy, AMD Ryzen 9
# 9950X) on 2026-10-02, at load average 5 to 12, on one nested monitor:
# 576964 to 587008 KiB over main at 7bb195940, each the run's first shell
# read at its first stop. docs/architecture/validation-latency.md holds the
# readings. Each reading prints its high-water mark beside it.
#
# VGSH_SMOKE_FIRST_BAR_BUDGET_MS: ceiling on the time from the runner's exec
# to the first bar surface with a client in the compositor's layer list,
# polled every 10 ms. The default is twice the highest reading of two passes
# of --first-bar-runs 12 on the owner's machine (host cachy, AMD Ryzen 9
# 9950X) on 2026-09-29, at load average 10 to 14; each pass lost one start
# to an unsized nested monitor. The 22 readings, each a start with no
# compiled QML cache, were 253 to 310 ms with cpu_some_pct at most 1.3.
# VGSH_SMOKE_DEFAULT_FIRST_BAR_BUDGET_MS: the same ceiling for the start
# over the default set that rows/start-order.sh reads. The default is twice
# the highest reading of two passes of --first-bar-runs 12 --plugin-set
# default on the same machine on 2026-09-29, at load average 4 to 8; each
# pass lost one start to an unsized nested monitor. The 22 readings were
# 206 to 271 ms with cpu_some_pct at most 1.3.
# VGSH_SMOKE_RECONCILE_BUDGET_MS: ceiling on the time from a
# setPluginEnabled reply to the build records no longer listing the
# disabled widget, polled with qs ipc. The default is twice the highest
# reading of twelve runs of this script on the same machine on 2026-09-23,
# which read 12 to 15 ms.
# VGSH_SMOKE_EMOJI_TOAST_BUDGET_MS: ceiling on the time from the notify
# call for a Slack card with six custom emoji to its body naming the
# images on every screen. VGSH_SMOKE_EMOJI_INBOX_BUDGET_MS is the time
# from the history call to forty summoned-panel rows naming their emoji
# images on the visible cards (rows/notifications.sh), counted by a probe
# readback and polled back to back. Each polling turn pays about 22 ms of
# smoke IPC round-trip cost. The toast default is twice the highest reading
# of 14 runs of that row in the nested sandbox on the owner's machine on
# 2026-09-30, at load average 4 to 8, one toast and one inbox reading a
# run: toast 43 to 50 ms, inbox 79 to 95 ms. The inbox default is twice the
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
first_bar_runs=""
plugin_set=smoke
qml_smoke_only=""
qml_smoke_list=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) timeout_s="$2"; shift 2 ;;
    --keep) keep=true; shift ;;
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
      qml_smoke_only=",$2,"; shift 2 ;;
    --list-rows) qml_smoke_list=true; shift ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) printf 'qml-smoke: refused: argument=%s\n' "$1" >&2; exit 2 ;;
  esac
done
# The rows read the smoke set's state, so another set only measures.
if [[ $plugin_set != smoke && -z $first_bar_runs ]]; then
  printf 'qml-smoke: refused: argument=--plugin-set value=%s reason=needs-first-bar-runs\n' "$plugin_set" >&2
  exit 2
fi
if [[ -n $qml_smoke_only && -n $first_bar_runs ]]; then
  printf 'qml-smoke: refused: argument=--rows reason=first-bar-runs-runs-no-row\n' >&2
  exit 2
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
"$repo/scripts/smoke/gpu-fence.sh" --check || exec "$repo/scripts/smoke/gpu-fence.sh" "$self" "${argv[@]}"
rss_ceiling_kib="${VGSH_SMOKE_RSS_CEILING_KIB:-1174016}"
first_bar_budget_ms="${VGSH_SMOKE_FIRST_BAR_BUDGET_MS:-620}"
default_first_bar_budget_ms="${VGSH_SMOKE_DEFAULT_FIRST_BAR_BUDGET_MS:-542}"
reconcile_budget_ms="${VGSH_SMOKE_RECONCILE_BUDGET_MS:-30}"
emoji_toast_budget_ms="${VGSH_SMOKE_EMOJI_TOAST_BUDGET_MS:-100}"
emoji_inbox_budget_ms="${VGSH_SMOKE_EMOJI_INBOX_BUDGET_MS:-1376}"

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
  highest=0
  highest_waited=""
  for ((run = 1; run <= first_bar_runs; run++)); do
    log="$first_bar_logs/run-$run.log"
    result="$first_bar_logs/run-$run.result"
    set +e
    (
      source "$repo/scripts/smoke/harness.sh"
      printf '%s %s %s\n' "${first_bar_ms:-unmeasured}" "$first_bar_cpu_some_pct" "$(service_release)" >"$result"
    ) >"$log" 2>&1 </dev/null
    status=$?
    set -e
    ms=""
    pct=""
    reason=""
    waited=""
    if [[ $status -eq 0 && -f $result ]]; then read -r ms pct reason waited <"$result"; fi
    if [[ $status -eq 0 && $ms =~ ^[0-9]+$ ]]; then
      measured=$((measured + 1))
      if ((ms > highest)); then highest=$ms; fi
      if [[ $reason == first-frame ]] && { [[ -z $highest_waited ]] || ((waited > highest_waited)); }; then highest_waited=$waited; fi
      printf 'run=%d latency_first_bar_ms=%d cpu_some_pct=%s services_released=%s waited_ms=%s\n' "$run" "$ms" "$pct" "$reason" "$waited"
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
  if ((measured < first_bar_runs)); then
    printf 'qml-smoke: status=not-measured first-bar-unmeasured=%d logs=%s\n' $((first_bar_runs - measured)) "$first_bar_logs"
    exit 77
  fi
  rm -rf -- "$first_bar_logs"
  exit 0
fi


# Every sandbox shell finds vsys and the browser-policy writer absent,
# whatever the host holds, so the rows press Install all missing for vsys
# and Install browser theming on any host (harness.sh's shell_hidden_commands); a row
# that needs one present stands its own stand-in for it.
# shellcheck disable=SC2034 # the harness sourced below reads it
shell_hidden_commands=(vsys vgs-browser-policy tesseract)
source "$repo/scripts/smoke/harness.sh"

# smoke_row (harness.sh) sources each row and fails one whose output holds
# a traceback. The step after hyprland-consent runs whatever --rows names.
for qml_smoke_row in "${qml_smoke_rows[@]}"; do
  if qml_smoke_wanted "$qml_smoke_row"; then smoke_row "$qml_smoke_row"; fi
  if [[ $qml_smoke_row == hyprland-consent ]]; then
    # bar.sh read the startup latencies; the cursor rows need the log.
    if compositor_logs_on; then ok "the nested compositor logs from here on"; else fail "the nested compositor's logs did not turn on"; fi
  fi
done

smoke_finish
