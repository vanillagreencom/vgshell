#!/usr/bin/env bash
# Drive scripts/smoke/hypr-call.sh, the nested smoke's one hyprctl caller,
# its bound and the run's end when the compositor stops answering. Each
# case starts a child bash that sources scripts/smoke/verdict.sh and the
# file the way harness.sh does, with a sandbox under this suite's scratch
# directory, a stand-in hyprctl first on the PATH that shell_env hands the
# call, a bound of 1 s, a fault log the verdict reads, and a row whose
# lines run after the call only if the run did not end. The stand-in never
# answers, answers only once the bound's kill arrives, prints hyprctl's
# read-timeout lines and exits 6, exits 6 without them, or answers at once.
# Each case pins the child's exit status, the lines it prints and does not
# print, and its elapsed time under the suite's own timeout. The controls
# at the end plant one defect per rule in a copy of the file and require
# the case that rule owns to go red.
#
# The child gets an explicit environment and stdin from /dev/null. Nothing
# here starts Hyprland; the suite signals only processes it started.
#
# Exit 0 when every case and control holds, 1 otherwise.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
hypr_call="$repo/scripts/smoke/hypr-call.sh"
verdict="$repo/scripts/smoke/verdict.sh"

# The EXIT trap is armed only on the directory mktemp made: an empty or
# non-directory answer never reaches rm -rf.
tmp="$(mktemp -d)" || { echo "test-smoke-hypr-bound: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "test-smoke-hypr-bound: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)"
trap 'rm -rf -- "${tmp:?}"' EXIT
failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

# The stand-in hyprctl logs its argv and acts as its case's mode file says.
mkdir -p -- "$tmp/home"
cat >"$tmp/hyprctl" <<'SH'
#!/usr/bin/env bash
dir="${0%/*}/.."
printf '%s\n' "$*" >>"$dir/calls"
case "$(<"$dir/mode")" in
  silent) exec sleep infinity ;;
  deaf) trap '' TERM; while :; do sleep 1; done ;;
  read-timeout) printf "Hyprland IPC didn't respond in time\nCouldn't read (6)\n"; exit 6 ;;
  refused) printf 'Couldn'\''t connect to the socket\n'; exit 6 ;;
  answer) printf 'ok\n\n\n[]\n\n'; printf 'stand-in stderr\n' >&2 ;;
  *) exit 99 ;;
esac
SH
chmod 755 "$tmp/hyprctl"

# The child: what harness.sh sets up before its first hypr call, then the
# case's row, then the verdict. The minimal smoke_finish is harness.sh's
# without the log tails it prints first. `subshell` sources it all inside
# ( ... ), as scripts/qml-smoke.sh --first-bar-runs does, and the parent
# goes on after it.
cat >"$tmp/child.sh" <<'SH'
set -euo pipefail
case_dir="$1" hypr_call="$2" verdict="$3" row="$4" shape="$5"
run() {
  source "$verdict"
  sandbox="$case_dir/sandbox"
  shell_env=(env PATH="$case_dir/bin:$PATH")
  signature=test
  ok() { printf '  ok    %s\n' "$*"; }
  expect() {
    local label="$1" want="$2" got status=0
    shift 2
    got="$("$@")" || status=$?
    if [[ $status -ne 0 ]]; then fail "$label: command failed: $*"
    elif [[ $got == "$want" ]]; then ok "$label"
    else fail "$label: got $got"; fi
  }
  smoke_finish() {
    local status=0
    smoke_verdict "$failures" "$behaviour_failures" "$sandbox/hyprland.log" || status=$?
    exit "$status"
  }
  source "$hypr_call"
  hypr_bound_s=1
  source "$row"
  smoke_finish
}
if [[ $shape == subshell ]]; then
  set +e
  ( run )
  status=$?
  set -e
  echo "PARENT-CONTINUED status=$status"
  exit 0
fi
run
SH

# The rows. The verdict's fault log is planted in every case, so a stall
# the verdict excused as a sandbox fault would read not-measured.
mkdir -p -- "$tmp/rows"
fault='ERR from aquamarine ]: Output WAYLAND-1: pending state rejected: swapchain failed reconfiguring'
cat >"$tmp/rows/expect.sh" <<'SH'
expect "the nested instance reloads" ok hypr reload config-only
echo ROW-KEPT-RUNNING
SH
cat >"$tmp/rows/answer.sh" <<'SH'
status=0
hypr --batch 'reload config-only ; j/configerrors' >"$case_dir/got" 2>"$case_dir/err" || status=$?
echo "hypr-status=$status"
if cmp -s -- "$case_dir/got" "$case_dir/want"; then echo BYTE-EXACT; fi
if [[ "$(<"$case_dir/err")" == "stand-in stderr" ]]; then echo STDERR-PASSED; fi
if [[ ! -e $sandbox/compositor-stalled ]]; then echo NO-STALL; fi
if ! compgen -G "$sandbox/hypr-*.out" >/dev/null; then echo NO-CAPTURE-LEFT; fi
echo "CALLED $(<"$case_dir/calls")"
echo ROW-KEPT-RUNNING
SH
cat >"$tmp/rows/refused.sh" <<'SH'
status=0
hypr version >/dev/null || status=$?
echo "hypr-status=$status"
if [[ ! -e $sandbox/compositor-stalled ]]; then echo NO-STALL; fi
echo ROW-KEPT-RUNNING
SH
cat >"$tmp/rows/substitution.sh" <<'SH'
got="$(for _ in 1 2 3 4 5 6 7 8; do hypr -j monitors || true; done)" || true
echo ROW-KEPT-RUNNING
SH
cat >"$tmp/rows/pipeline.sh" <<'SH'
hypr -j monitors | cat >/dev/null || true
echo ROW-KEPT-RUNNING
SH
cat >"$tmp/rows/process.sh" <<'SH'
read -r got < <(hypr -j monitors) || true
echo ROW-KEPT-RUNNING
SH
cat >"$tmp/rows/geometry.sh" <<'SH'
row_class=geometry
expect "the nested instance reloads" ok hypr reload config-only
echo ROW-KEPT-RUNNING
SH

stall_line() { printf '  FAIL  the nested compositor stopped answering: hyprctl %s: %s; the run ends here' "$1" "$2"; }
silent_line="$(stall_line 'reload config-only' 'no answer within 1s')"
monitors_line="$(stall_line '-j monitors' 'no answer within 1s')"
read_line="$(stall_line 'reload config-only' 'hyprctl read timed out after 5s')"

# run_case FILE ROW: true when the child, sourcing the copy FILE of
# hypr-call.sh, exits with the row's status within its limit, prints each
# wanted line and no line holding a refused text. It prints why not.
run_case() {
  local file="$1" label mode row shape want_status limit_ms wants refuses
  IFS='|' read -r label mode row shape want_status limit_ms wants refuses <<<"$2"
  local dir out status=0 started elapsed_ms line reasons=() want=() refuse=()
  dir="$(mktemp -d "$tmp/case.XXXXXX")"
  mkdir -p -- "$dir/bin" "$dir/sandbox"
  cp -- "$tmp/hyprctl" "$dir/bin/hyprctl"
  printf '%s\n' "$mode" >"$dir/mode"
  printf '%s\n' "$fault" >"$dir/sandbox/hyprland.log"
  printf 'ok\n\n\n[]\n\n' >"$dir/want"
  started="$(date +%s%N)"
  out="$(timeout -k 1 $((limit_ms / 1000 + 2)) env -i PATH="$PATH" HOME="$tmp/home" LC_ALL=C \
    "$BASH" "$tmp/child.sh" "$dir" "$file" "$verdict" "$tmp/rows/$row.sh" "$shape" </dev/null 2>&1)" || status=$?
  elapsed_ms=$((($(date +%s%N) - started) / 1000000))
  [[ $status -eq $want_status ]] || reasons+=("status=$status want=$want_status")
  ((elapsed_ms <= limit_ms)) || reasons+=("elapsed_ms=$elapsed_ms limit_ms=$limit_ms")
  IFS='~' read -r -a want <<<"$wants"
  IFS='~' read -r -a refuse <<<"$refuses"
  for line in "${want[@]}"; do
    grep -qxF -- "$line" <<<"$out" || reasons+=("missing line: [$line]")
  done
  for line in "${refuse[@]}"; do
    [[ $out != *"$line"* ]] || reasons+=("refused text printed: [$line]")
  done
  [[ ${#reasons[@]} -eq 0 ]] && return 0
  printf '%s:' "$label"
  printf ' %s;' "${reasons[@]}"
  printf '\n'
  return 1
}

# Rows: label | stand-in mode | row | `plain` or `subshell` | status |
# elapsed limit in ms | wanted lines, `~`-delimited | refused texts,
# `~`-delimited. A stall's limit is the 1 s bound, the 2 s kill-after and
# 3 s of slack.
cases=(
  "a call that never returns ends the run|silent|expect|plain|1|6000|$silent_line~qml-smoke: failed=1|ROW-KEPT-RUNNING~status=not-measured"
  "a call that outlives the bound's TERM ends the run|deaf|expect|plain|1|7000|$silent_line~qml-smoke: failed=1|ROW-KEPT-RUNNING~status=not-measured"
  "hyprctl's own read timeout ends the run|read-timeout|expect|plain|1|3000|$read_line~qml-smoke: failed=1|ROW-KEPT-RUNNING~status=not-measured"
  "an answer is copied byte for byte and the row goes on|answer|answer|plain|0|3000|hypr-status=0~BYTE-EXACT~STDERR-PASSED~NO-STALL~NO-CAPTURE-LEFT~CALLED -i test --batch reload config-only ; j/configerrors~ROW-KEPT-RUNNING~qml-smoke: ok|FAIL"
  "exit 6 without the read-timeout line is no stall|refused|refused|plain|0|3000|hypr-status=6~NO-STALL~ROW-KEPT-RUNNING~qml-smoke: ok|FAIL"
  "a stall in a command substitution ends the run and later calls return at once|silent|substitution|plain|1|6000|$monitors_line~qml-smoke: failed=1|ROW-KEPT-RUNNING"
  "a stall in a pipeline ends the run|silent|pipeline|plain|1|6000|$monitors_line~qml-smoke: failed=1|ROW-KEPT-RUNNING"
  "a stall in a process substitution ends the run|silent|process|plain|1|6000|$monitors_line~qml-smoke: failed=1|ROW-KEPT-RUNNING"
  "a stall in a geometry row is a behaviour failure|silent|geometry|plain|1|6000|$silent_line~qml-smoke: failed=1|ROW-KEPT-RUNNING~status=not-measured"
  "a stall in a harness sourced inside a subshell ends the subshell only|silent|expect|subshell|0|6000|$silent_line~qml-smoke: failed=1~PARENT-CONTINUED status=1|ROW-KEPT-RUNNING"
)
for row in "${cases[@]}"; do
  if detail="$(run_case "$hypr_call" "$row")"; then ok "${row%%|*}"; else fail "${row%%|*}"; printf '        %s\n' "$detail"; fi
done

# mutate OLD NEW OUT: a copy of hypr-call.sh with OLD, which must occur
# once, replaced by NEW.
mutate() {
  local text rest count
  text="$(<"$hypr_call")"
  rest="${text//"$1"/}"
  count=$(( (${#text} - ${#rest}) / ${#1} ))
  if [[ $count -ne 1 ]]; then
    printf '        mutation matched %s times: %s\n' "$count" "$1"
    return 1
  fi
  printf '%s\n' "${text/"$1"/"$2"}" >"$3"
  cmp -s -- "$hypr_call" "$3" && { printf '        mutation left the file unchanged: %s\n' "$1"; return 1; }
  return 0
}

# Rows: label @ text @ replacement @ the case label that must go red. A
# field holds no `@`, the separator.
controls=(
  "the call is unbounded@timeout -k 2 \"\$hypr_bound_s\" hyprctl@hyprctl@a call that never returns ends the run"
  "a stall does not signal the harness shell@kill -USR1 -- \"\$harness_pid\"@:@a call that never returns ends the run"
  "a stall keeps the row's class@  row_class=behaviour@  :@a stall in a geometry row is a behaviour failure"
  "the harness shell is named by \$\$@harness_pid=\$BASHPID@harness_pid=\$\$@a stall in a harness sourced inside a subshell ends the subshell only"
  "a call after a stall reaches hyprctl@[[ ! -e \$sandbox/compositor-stalled ]] || return 1@:@a stall in a command substitution ends the run and later calls return at once"
  "the bound's kill is no stall@\$status -eq 124 || \$status -eq 137@\$status -eq 124@a call that outlives the bound's TERM ends the run"
  "hyprctl's read timeout is no stall@grep -qF \"Hyprland IPC didn't respond in time\"@grep -qF \"no such line\"@hyprctl's own read timeout ends the run"
  "every exit 6 is a stall@\$status -eq 6 ]] && grep@\$status -eq 6 ]] || grep@exit 6 without the read-timeout line is no stall"
  "the answer is not copied byte for byte@  cat -- \"\$out\" || copied=\$?@  printf '%s\\n' \"\$(<\"\$out\")\" || copied=\$?@an answer is copied byte for byte and the row goes on"
)
for i in "${!controls[@]}"; do
  IFS='@' read -r label old new target <<<"${controls[i]}"
  mutant="$tmp/mutant-$i.sh"
  if ! mutate "$old" "$new" "$mutant"; then fail "control: $label"; continue; fi
  row=""
  for candidate in "${cases[@]}"; do [[ ${candidate%%|*} == "$target" ]] && row="$candidate"; done
  if [[ -z $row ]]; then fail "control: $label names no case: $target"; continue; fi
  if detail="$(run_case "$mutant" "$row")"; then
    fail "control: $label left '$target' green"
  else
    ok "control: $label"
    printf '  CONTROL  %s\n' "$detail"
  fi
done

if [[ $failures -gt 0 ]]; then
  echo "test-smoke-hypr-bound: failed=$failures"
  exit 1
fi
echo "test-smoke-hypr-bound: ok"
