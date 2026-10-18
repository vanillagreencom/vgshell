#!/usr/bin/env bash
# Controls for vgs.updates/bin/check: required argv, concurrent probes and
# signal cleanup of probe process groups.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
check="$repo/shell/plugins/vgs.updates/bin/check"
root="$repo/tmp/test-updates-check-$$"
rm -rf -- "$root"
mkdir -p -- "$root/bin" "$root/state" "$root/runtime" "$root/home"
mkdir -p -- "$root/bin/lib"
ln -s -- "$repo/bin/lib/qml-library.js" "$root/bin/lib/qml-library.js"
mkdir -p -- "$root/shell/Commons"
cp -- "$repo/shell/Commons/PageReference.js" "$root/shell/Commons/"
trap 'chmod -R u+rwx -- "${root:?}" 2>/dev/null; rm -rf -- "${root:?}"' EXIT
failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }
now_ms() { printf '%s\n' $(( $(date +%s%N) / 1000000 )); }
live_pids_from() {
  local list="$1" left=0 child
  while read -r child; do
    [[ -n $child && -d /proc/$child ]] && left=$((left + 1))
  done <"$list"
  printf '%s\n' "$left"
}
wait_no_live_pids() {
  local list="$1" deadline left
  deadline=$(( $(now_ms) + 5000 ))
  while true; do
    left="$(live_pids_from "$list")"
    [[ $left -eq 0 ]] && { printf '0\n'; return 0; }
    (( $(now_ms) < deadline )) || { printf '%s\n' "$left"; return 1; }
    sleep 0.05
  done
}
line_count() { [[ -f $1 ]] && wc -l <"$1" || printf '0\n'; }
wait_log_lines() {
  local log="$1" want="$2" deadline
  deadline=$(( $(now_ms) + 5000 ))
  while true; do
    [[ $(line_count "$log") -eq $want ]] && return 0
    (( $(now_ms) < deadline )) || return 1
    sleep 0.1
  done
}
node_dir="$(dirname -- "$(node -e 'process.stdout.write(process.execPath)')")"
run_env=(env -i HOME="$root/home" PATH="$node_dir:/usr/bin:/bin" XDG_STATE_HOME="$root/state" XDG_RUNTIME_DIR="$root/runtime" LC_ALL=C)
cat >"$root/bin/vgshell" <<'VGSHELL'
#!/usr/bin/env bash
record="$XDG_STATE_HOME/vgshell/updates-test"
mkdir -p -- "$record"
printf '%s %s at=%s\n' "$1" "$2" "$(date +%s%N)" >>"$record/calls"
case "$1 $2" in
  'pkg check') sleep "${VGS_UPDATES_TEST_SLEEP:-0}"; printf '[]\n' ;;
  'self status') sleep "${VGS_UPDATES_TEST_SLEEP:-0}"; printf '{"version":"0.1.0","method":"checkout","package":null,"current":"0.1.0","latest":"0.1.0","behind":false,"step":"none","reason":null,"error":null}\n' ;;
  'plugin outdated') sleep "${VGS_UPDATES_TEST_SLEEP:-0}"; printf '[]\n' ;;
  'theme outdated') sleep "${VGS_UPDATES_TEST_SLEEP:-0}"; printf '[]\n' ;;
  *) exit 2 ;;
esac
VGSHELL
chmod 755 "$root/bin/vgshell"
if "${run_env[@]}" "$check" >/dev/null 2>"$root/missing.err"; then
  fail "check refuses without --vgshell"
elif grep -q 'updates-check: refused: vgshell=missing' "$root/missing.err"; then
  ok "check refuses without --vgshell"
else
  fail "missing --vgshell refusal text"
fi
start_ms=$(( $(date +%s%N) / 1000000 ))
"${run_env[@]}" VGS_UPDATES_TEST_SLEEP=1 "$check" --vgshell "$root/bin/vgshell" >/dev/null
elapsed=$(( $(date +%s%N) / 1000000 - start_ms ))
if [[ $elapsed -lt 3000 ]]; then ok "check runs independent probes concurrently"; else fail "check runs independent probes concurrently: elapsed=${elapsed}ms"; fi
if [[ $(wc -l <"$root/state/vgshell/updates-test/calls") -eq 4 ]]; then ok "check runs four probes once"; else fail "check runs four probes once"; fi
missing_tree="$root/missing-page-reference"
mkdir -p -- "$missing_tree/bin/lib"
ln -s -- "$repo/bin/lib/qml-library.js" "$missing_tree/bin/lib/qml-library.js"
module_status=0
"${run_env[@]}" node "$repo/shell/plugins/vgs.updates/NormalizeCheck.js" "$missing_tree/bin/lib/qml-library.js" \
  "$repo/shell/plugins/vgs.updates/UpdatesLogic.js" "$root/state" missing >"$root/module.out" 2>"$root/module.err" || module_status=$?
if [[ $module_status == 2 ]] && grep -qxF "qml-library: refused: unreadable path=$missing_tree/shell/Commons/PageReference.js error=ENOENT" "$root/module.err"; then
  ok "normalizer refuses a missing page-reference module"
else
  fail "normalizer refuses a missing page-reference module: exit=$module_status"
fi
# The record of a failed vgshell-git rebuild that tui/pipeline.sh leaves in
# the state directory reaches the VGS row of the snapshot. The control is
# the normalizer with the record's read removed, whose row carries none.
record_dir="$root/record"
mkdir -p -- "$record_dir"
for name in pkg plugins themes; do printf '[]\n' >"$record_dir/.$name.rec.out"; done
printf '{"version":"0.1.0","method":"package","package":"vgshell-git","current":"0.1.0.r2.gaaaaaaa","latest":"%s","behind":true,"step":"rebuild","reason":null,"error":null}\n' \
  "$(printf 'b%.0s' {1..40})" >"$record_dir/.self.rec.out"
for name in pkg self plugins themes; do printf '0\n' >"$record_dir/.$name.rec.status"; : >"$record_dir/.$name.rec.err"; done
printf '{"current":"0.1.0.r2.gaaaaaaa","helper":"paru","exit":1,"conflict":"quickshell"}\n' >"$record_dir/rebuild-failed.json"
# record_note NORMALIZER: the VGS row's note of the snapshot NORMALIZER
# writes from the record directory, as one JSON line.
record_note() {
  "${run_env[@]}" node "$1" "$root/bin/lib/qml-library.js" "$repo/shell/plugins/vgs.updates/UpdatesLogic.js" "$record_dir" rec |
    node -e 'let t = ""; process.stdin.on("data", d => t += d).on("end", () => console.log(JSON.stringify(JSON.parse(t).sources.find(s => s.source === "vgs").note)))'
}
want_note='{"kind":"rebuildFailed","conflict":"quickshell"}'
got_note="$(record_note "$repo/shell/plugins/vgs.updates/NormalizeCheck.js" || :)"
if [[ $got_note == "$want_note" ]]; then ok "a failed rebuild's record reaches the VGS row"; else fail "a failed rebuild's record reaches the VGS row: $got_note"; fi
no_record="$root/NormalizeCheck-no-record.js"
python3 - "$repo/shell/plugins/vgs.updates/NormalizeCheck.js" "$no_record" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
old = 'rebuildFailed: rebuildFailed() };'
assert source.count(old) == 1
pathlib.Path(sys.argv[2]).write_text(source.replace(old, 'rebuildFailed: null };'))
PY
got_note="$(record_note "$no_record" || :)"
if [[ $got_note == null ]]; then ok "control: without the record's read the VGS row has no note"; else fail "control: without the record's read the VGS row has no note: $got_note"; fi
# Process groups: each probe's vgshell leaves a grandchild in its group. TERM
# to bin/check must reach it; the control signals each probe's pid alone
# and leaves the grandchild running.
cat >"$root/bin/vgshell" <<'VGSHELL'
#!/usr/bin/env bash
record="$XDG_STATE_HOME/vgshell/updates-test"
mkdir -p -- "$record"
(sleep 60) &
echo "$!" >>"$record/grandchildren-$RUN"
wait
VGSHELL
chmod 755 "$root/bin/vgshell"
# grandchild_run LABEL CHECK: TERM CHECK once its four probes started a
# grandchild; print CHECK's status and how many grandchildren outlived it.
grandchild_run() {
  local label="$1" helper="$2" pid status left=0 child log="$root/state/vgshell/updates-test/grandchildren-$1"
  set +e
  "${run_env[@]}" RUN="$label" "$helper" --vgshell "$root/bin/vgshell" >/dev/null 2>"$root/$label.err" &
  pid=$!
  if ! wait_log_lines "$log" 4; then
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    echo "0 -1"
    return
  fi
  kill -TERM "$pid"
  wait "$pid"
  status=$?
  set -e
  left="$(wait_no_live_pids "$log" || :)"
  echo "$status $left"
  while read -r child; do kill -KILL "$child" 2>/dev/null || true; done <"$log"
}
read -r status left <<<"$(grandchild_run groups "$check")"
if [[ $status -eq 143 ]]; then ok "TERM exits as 128 plus the signal"; else fail "TERM exits as 128 plus the signal: $status"; fi
if [[ $left -eq 0 ]]; then ok "TERM kills probe grandchildren"; else fail "TERM kills probe grandchildren: left=$left"; fi
pid_only="$root/check-pid-only"
python3 - "$check" "$pid_only" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
old = 'kill -"$sig" -- "-$pid" 2>/dev/null || kill -"$sig" -- "$pid" 2>/dev/null || true'
new = 'kill -"$sig" -- "$pid" 2>/dev/null || true'
assert source.count(old) == 1
pathlib.Path(sys.argv[2]).write_text(source.replace(old, new))
PY
chmod 755 "$pid_only"
read -r _ left <<<"$(grandchild_run pid-only "$pid_only")"
if [[ $left -gt 0 ]]; then ok "control: signalling each probe's pid alone leaves its grandchild"; else fail "control: signalling each probe's pid alone leaves its grandchild"; fi
# Delayed shutdown: the package probe, the first bin/check waits on, takes
# three seconds to end after TERM; the other probes end at once. bin/check
# must wait again for a probe whose wait the signal interrupted, so no
# probe outlives it. The control is bin/check with only that re-wait
# removed, which returns while the package probe still runs.
cat >"$root/bin/vgshell" <<'VGSHELL'
#!/usr/bin/env bash
record="$XDG_STATE_HOME/vgshell/updates-test"
mkdir -p -- "$record"
echo "$$" >>"$record/delayed-$RUN"
if [[ $1 == pkg ]]; then trap 'sleep 3; exit 143' TERM; else trap 'exit 143' TERM; fi
sleep 60 &
wait
VGSHELL
chmod 755 "$root/bin/vgshell"
# delayed_run LABEL CHECK: run CHECK until its four probes recorded
# themselves, TERM it, and print how many probes outlived it.
delayed_run() {
  local label="$1" helper="$2" pid left=0 probe log="$root/state/vgshell/updates-test/delayed-$1"
  set +e
  "${run_env[@]}" RUN="$label" "$helper" --vgshell "$root/bin/vgshell" >/dev/null 2>"$root/$label.err" &
  pid=$!
  if ! wait_log_lines "$log" 4; then
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    echo "-1"
    return
  fi
  kill -TERM "$pid"
  wait "$pid"
  set -e
  while read -r probe; do [[ -n $probe && -d /proc/$probe ]] && left=$((left + 1)); done <"$log"
  echo "$left"
  while read -r probe; do kill -KILL "$probe" 2>/dev/null || true; done <"$log"
}
shipped_left="$(delayed_run shipped "$check")"
if [[ $shipped_left -eq 0 ]]; then ok "TERM waits for a probe's delayed shutdown"; else fail "TERM waits for a probe's delayed shutdown: left=$shipped_left"; fi
mutant="$root/check-no-rewait"
python3 - "$check" "$mutant" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
old = """  while true; do
    wait "${pids[$i]}" || status=$?
    if [[ -z $stop_status || ! -d /proc/${pids[$i]} ]]; then break; fi
    status=0
  done"""
new = """  wait "${pids[$i]}" || status=$?"""
assert source.count(old) == 1
pathlib.Path(sys.argv[2]).write_text(source.replace(old, new))
PY
chmod 755 "$mutant"
mutant_left="$(delayed_run mutant "$mutant")"
if [[ $mutant_left -gt 0 ]]; then ok "control: without the re-wait a probe outlives bin/check"; else fail "control: without the re-wait a probe outlives bin/check"; fi
# SIGINT: each probe starts in the background of bin/check, so with SIGINT
# ignored, and a bash probe cannot trap it; a check stopped by INT still
# sends every probe group TERM. The stand-in probe notes each TERM it gets.
# The control forwards INT, which the probes ignore until their 3 s sleep
# ends.
cat >"$root/bin/vgshell" <<'VGSHELL'
#!/usr/bin/env bash
record="$XDG_STATE_HOME/vgshell/updates-test"
mkdir -p -- "$record"
echo "$$" >>"$record/int-$RUN"
trap ': >"$record/termed-$RUN-$$"; exit 143' TERM
sleep 3 &
wait
VGSHELL
chmod 755 "$root/bin/vgshell"
# int_run LABEL CHECK: run CHECK with SIGINT at its default, as a terminal's
# foreground job has it, until its four probes recorded themselves, INT
# it, and print its status and how many probes got TERM.
int_run() {
  local label="$1" helper="$2" pid status log="$root/state/vgshell/updates-test/int-$1"
  set +e
  "${run_env[@]:0:2}" --default-signal=INT "${run_env[@]:2}" RUN="$label" "$helper" --vgshell "$root/bin/vgshell" >/dev/null 2>"$root/$label.err" &
  pid=$!
  if ! wait_log_lines "$log" 4; then
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    echo "0 -1"
    return
  fi
  kill -INT "$pid"
  wait "$pid"
  status=$?
  set -e
  echo "$status $(find "$root/state/vgshell/updates-test" -name "termed-$label-*" | wc -l)"
}
read -r status termed <<<"$(int_run int "$check")"
if [[ $status -eq 130 ]]; then ok "INT exits as 128 plus the signal"; else fail "INT exits as 128 plus the signal: $status"; fi
if [[ $termed -eq 4 ]]; then ok "INT sends every probe TERM"; else fail "INT sends every probe TERM: termed=$termed"; fi
int_mutant="$root/check-forwards-int"
python3 - "$check" "$int_mutant" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
old = '  signal_groups TERM\n'
new = '  signal_groups INT\n'
assert source.count(old) == 1
pathlib.Path(sys.argv[2]).write_text(source.replace(old, new))
PY
chmod 755 "$int_mutant"
read -r _ termed <<<"$(int_run int-mutant "$int_mutant")"
if [[ $termed -eq 0 ]]; then ok "control: forwarding INT stops no probe"; else fail "control: forwarding INT stops no probe: termed=$termed"; fi
if [[ $failures -gt 0 ]]; then echo "test-updates-check: failed=$failures"; exit 1; fi
echo "test-updates-check: ok"
