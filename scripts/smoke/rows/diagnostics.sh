# Every QML warning and error the shell logged, minus the lines rows
# provoked on purpose, plus the engine's own error classes.
# The host pressure limit uses theme-latency.sh's owner-approved measurement:
# host cachy, Ryzen 9 9950X, 2026-10-08, VGS-1100 note 1791448368.
# Above 2.8% CPU pressure the reconcile reading is not measured, including
# a fast reading. bar.sh samples the reply-to-built window, one IPC round
# trip per poll with a 5 ms wait between unsuccessful polls.
# inputs: shell/* scripts/sample-shell-memory.sh bin/vgshell scripts/smoke/rows/bar.sh
set -euo pipefail
check_unexpected_log "shell log" "$instance_log"

echo "  latency_first_bar_ms=${first_bar_ms:-unmeasured} budget_ms=$first_bar_budget_ms cpu_some_pct=$first_bar_cpu_some_pct"
if [[ -n $first_bar_ms && $first_bar_ms -le $first_bar_budget_ms ]]; then ok "the first bar maps within its budget"; else fail "first bar latency ${first_bar_ms:-unmeasured} ms over budget $first_bar_budget_ms ms"; fi
diagnostics_reconcile_verdict() { # MS CPU_SOME_PCT BUDGET_MS
  local ms="$1" pressure="$2" budget="$3" pressure_tenths
  if [[ ! $ms =~ ^[0-9]+$ || ! $pressure =~ ^[0-9]+\.[0-9]$ ]]; then
    echo unread
    return
  fi
  pressure_tenths=$((10#${pressure%.*} * 10 + 10#${pressure#*.}))
  if ((pressure_tenths > 28)); then echo unmeasured
  elif ((ms <= budget)); then echo within
  else echo over
  fi
}
reconcile_result="$(diagnostics_reconcile_verdict "$reconcile_ms" "$reconcile_cpu_some_pct" "$reconcile_budget_ms")"
echo "  latency_reconcile_ms=${reconcile_ms:-unmeasured} budget_ms=$reconcile_budget_ms cpu_some_pct=$reconcile_cpu_some_pct result=$reconcile_result"
case "$reconcile_result" in
  within) ok "a disable reaches the build records within its budget" ;;
  unmeasured) not_measured diagnostics "reconcile-cpu_some_pct=$reconcile_cpu_some_pct-above-2.8" ;;
  over) fail "reconcile latency $reconcile_ms ms over budget $reconcile_budget_ms ms" ;;
  unread) fail "reconcile reading unavailable: latency_ms=${reconcile_ms:-unmeasured} cpu_some_pct=$reconcile_cpu_some_pct" ;;
  *) fail "reconcile verdict invalid: $reconcile_result" ;;
esac
# Planted slow readings fail only with measured low pressure. Busy readings
# carry a typed unmeasured result, never a latency pass or a latency failure.
while read -r diagnostics_control_ms diagnostics_control_pressure diagnostics_control_want; do
  expect "control: reconcile $diagnostics_control_ms ms at pressure $diagnostics_control_pressure" "$diagnostics_control_want" diagnostics_reconcile_verdict "$diagnostics_control_ms" "$diagnostics_control_pressure" "$reconcile_budget_ms"
done <<CONTROLS
$reconcile_budget_ms 0.0 within
$((reconcile_budget_ms + 1)) 0.0 over
$((reconcile_budget_ms + 1)) 2.8 over
$((reconcile_budget_ms + 1)) 2.9 unmeasured
$reconcile_budget_ms 2.9 unmeasured
$((reconcile_budget_ms + 1)) unmeasured unread
$reconcile_budget_ms unmeasured unread
unmeasured 2.9 unread
CONTROLS

# The memory sampler finds the shell `vgshell run` started through the runner's
# lock file and the instance list, and samples it by pid.
sampler_rows() { awk -F'\t' -v pid="$shell_qs_pid" 'NR > 1 && $2 == pid { n++ } END { print n + 0 }' "$sandbox/memory.tsv"; }
if "${shell_env[@]}" "$repo/scripts/sample-shell-memory.sh" --interval 1 --samples 2 --log "$sandbox/memory.tsv" >"$sandbox/sampler.out" 2>"$sandbox/sampler.err"; then
  expect "the memory sampler logged two samples of the runner's shell" 2 sampler_rows
else
  fail "memory sampler exited non-zero: $(head -n 2 "$sandbox/sampler.err")"
fi

# The ceiling holds the largest resident size of the shells the run read up
# to here: each shell a row stopped, read at its stop, and this one.
shell_memory_note
if [[ $rss_kib -gt 0 && $hwm_kib -gt 0 ]]; then ok "this shell's resident size and high-water mark are read"; else fail "resident size unreadable for pid $shell_qs_pid: rss_kib=$rss_kib hwm_kib=$hwm_kib"; fi
expect "every shell the run started was read" none shells_unread
echo "  rss_peak_kib=$rss_peak_kib rss_peak_row=${rss_peak_row:-none} ceiling_kib=$rss_ceiling_kib"
expect "the largest resident size is under the ceiling" under rss_verdict "$rss_peak_kib" "$rss_ceiling_kib"
# The controls: a reading one over the ceiling, no reading, and a larger
# reading that an earlier shell left and a smaller, later one does not
# replace.
peak_after() { # RSS_KIB ROW [RSS_KIB ROW]...
  (
    rss_peak_kib=0
    rss_peak_row=""
    while [[ $# -gt 0 ]]; do shell_memory_keep "$1" "$2"; shift 2; done
    echo "$rss_peak_kib $rss_peak_row $(rss_verdict "$rss_peak_kib" "$rss_ceiling_kib")"
  )
}
expect "control: a resident size one over the ceiling reads over" over rss_verdict "$((rss_ceiling_kib + 1))" "$rss_ceiling_kib"
expect "control: a resident size at the ceiling reads under" under rss_verdict "$rss_ceiling_kib" "$rss_ceiling_kib"
expect "control: no reading reads unread" unread rss_verdict 0 "$rss_ceiling_kib"
expect "control: an earlier shell's reading over the ceiling stays the largest" "$((rss_ceiling_kib + 1)) earlier over" peak_after "$((rss_ceiling_kib + 1))" earlier 1 later
expect "control: a later, larger reading replaces a smaller one" "2 later under" peak_after 1 earlier 2 later
unread_after() { ( shell_pids_started+=("$1"); shells_unread ) } # PID
expect "control: a started shell no note read is named" 1 unread_after 1
