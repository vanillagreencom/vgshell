#!/usr/bin/env bash
# Drive scripts/smoke/verdict.sh, the nested smoke's closing verdict, with
# the counters smoke_finish hands it and fixture compositor logs, and fail,
# which writes those counters by the row's class whatever the held mode
# reads, a row not_measured records beside them, and read_count, the count
# a row adds to, with a stub reader, and the judges' readings harness.sh
# takes around each row with the judgement scripts/smoke/row-inputs.sh
# makes of them. No case needs a sandbox.
# Each verdict case pins the exit status and the first line the verdict
# prints. The controls at the end plant one defect per rule in a
# copy of the file and require the case that rule owns to go red.
#
# The passing log holds lines copied from a passing run's nested
# hyprland.log: the nested window's output configured, then the failed
# allocations every passing run logs for Hyprland's headless output. The
# fault log adds the lines a failed allocation on the nested window's own
# output writes, built from Aquamarine's format strings in
# src/allocator/GBM.cpp, src/allocator/Swapchain.cpp and
# src/backend/Wayland.cpp (v0.15.1); no run here has logged them.
#
# Exit 0 when every case and control holds, 1 otherwise.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
verdict="$repo/scripts/smoke/verdict.sh"

# The EXIT trap is armed only on the directory mktemp made: an empty or
# non-directory answer never reaches rm -rf.
tmp="$(mktemp -d)" || { echo "test-smoke-verdict: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "test-smoke-verdict: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)"
trap 'rm -rf -- "${tmp:?}"' EXIT
failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

{
  echo 'DEBUG from aquamarine ]: Output WAYLAND-1: initialized'
  echo 'DEBUG from aquamarine ]: Output WAYLAND-1: configure toplevel with 1755x933'
  echo 'DEBUG from aquamarine ]: Swapchain: Reconfigured a swapchain to [Vector2D: x: 1755, y: 933] XR24 of length 3'
  for _ in $(seq 1 16); do
    echo 'ERR from aquamarine ]: GBM: Allocating with modifiers failed, falling back to modifier-less allocation'
    echo 'ERR from aquamarine ]: GBM: Failed to allocate a GBM buffer: bo null'
    echo "ERR from aquamarine ]: Couldn't allocate a gbm buffer with size [Vector2D: x: 1920, y: 1080] and format XR24"
    echo 'ERR from aquamarine ]: Swapchain: Failed acquiring a buffer'
  done
} >"$tmp/passing.log"
{
  cat "$tmp/passing.log"
  echo 'DEBUG from aquamarine ]: Output WAYLAND-1: configure toplevel with 1920x1040'
  echo 'ERR from aquamarine ]: GBM: Failed to allocate a GBM buffer: bo null'
  echo "ERR from aquamarine ]: Couldn't allocate a gbm buffer with size [Vector2D: x: 1920, y: 1040] and format XR24"
  echo 'ERR from aquamarine ]: Swapchain: Failed acquiring a buffer'
  echo 'ERR from aquamarine ]: Output WAYLAND-1: pending state rejected: swapchain failed reconfiguring'
} >"$tmp/fault.log"

# run_case FILE ROW: true when the verdict FILE defines gives the row's
# status and first line. The caller's shell options are the harness's.
run_case() {
  local file="$1" label failures_n behaviour logs want_status want_line out status=0 names=() paths=() name
  IFS='|' read -r label failures_n behaviour logs want_status want_line <<<"$2"
  read -r -a names <<<"$logs"
  for name in "${names[@]}"; do paths+=("$tmp/$name.log"); done
  out="$(env -i PATH="$PATH" bash -c 'set -euo pipefail; source "$1"; shift; smoke_verdict "$@"' _ \
    "$file" "$failures_n" "$behaviour" "${paths[@]}")" || status=$?
  [[ $status -eq $want_status && ${out%%$'\n'*} == "$want_line" ]] && return 0
  printf '        %s: status=%s want=%s first line: %s\n' "$label" "$status" "$want_status" "${out%%$'\n'*}"
  return 1
}

# Rows: label | failures | behaviour failures | fixture logs,
# space-delimited, `missing` naming none written | status | first line.
cases=(
  "a clean run passes|0|0|passing|0|qml-smoke: ok"
  "all-geometry failure with a passing log fails|3|0|passing|1|qml-smoke: failed=3"
  "all-geometry failure with the nested output's fault is not measured|3|0|fault|77|qml-smoke: status=not-measured nested-compositor=buffer-allocation-failed failed=3"
  "the fault in a second log is read|3|0|passing fault|77|qml-smoke: status=not-measured nested-compositor=buffer-allocation-failed failed=3"
  "a behaviour failure with the fault fails|3|1|fault|1|qml-smoke: failed=3"
  "all-geometry failure with no readable log fails|3|0|missing|1|qml-smoke: failed=3"
)
for row in "${cases[@]}"; do
  if run_case "$verdict" "$row"; then ok "${row%%|*}"; else fail "${row%%|*}"; fi
done

# run_tally FILE ROW: true when fail, as the file FILE defines it, counts one
# failed row as the row wants, printed as failures and behaviour failures,
# starts its line with the row's word, never asks the held mode, and the
# verdict on that tally exits with the row's status. scripts/main-run.sh
# reports every line that starts `  FAIL` as a failure, so the word is the
# line's machine-read part. held_mode_state is the harness's reading of the
# monitor; a stub in its place reads the row's state and marks that it was
# asked.
run_tally() {
  local file="$1" label class hold state want_counts want_status want_word out status=0
  IFS='|' read -r label class hold state want_counts want_status want_word <<<"$2"
  out="$(env -i PATH="$PATH" bash -c '
set -euo pipefail
source "$1"
stub_state="$4" asked_mark="$5.asked"
held_mode_state() { : >"$asked_mark"; printf "%s\n" "$stub_state"; }
row_class="$2"
[[ $3 == none ]] || mode_hold=(WAYLAND-1 "480x720 scale=1")
[[ $3 != base ]] || mode_hold_run_base=true
rm -f -- "$5.asked"
fail "a row" >"$5"
read -r word _ <"$5"
asked=no
[[ ! -e $5.asked ]] || asked=yes
printf "%s %s %s asked=%s\n" "$failures" "$behaviour_failures" "$word" "$asked"
smoke_verdict "$failures" "$behaviour_failures" /dev/null >/dev/null' _ \
    "$file" "$class" "$hold" "$state" "$tmp/tally-line")" || status=$?
  [[ $status -eq $want_status && $out == "$want_counts $want_word asked=no" ]] && return 0
  printf '        %s: status=%s want=%s counts: %s want %s %s asked=no\n' "$label" "$status" "$want_status" "$out" "$want_counts" "$want_word"
  return 1
}

# Rows: label | row class | hold, `none`, `held` or `base` | the state the
# stub held_mode_state reads | failures and behaviour failures | verdict
# status | the first word fail prints.
tallies=(
  "a behaviour row failing with no hold is behaviour|behaviour|none|reset|1 1|1|FAIL"
  "a geometry row failing with no hold is geometry|geometry|none|reset|1 0|1|FAIL"
  "a render row failing with no hold is render|render|none|reset|1 0|1|FAIL"
  "an operation failure is behaviour|operation|none|reset|1 1|1|FAIL"
  "a row failing while the mode holds is behaviour|behaviour|held|held|1 1|1|FAIL"
  "a row failing after the held mode's reset is behaviour|behaviour|held|reset|1 1|1|FAIL"
  "a geometry row failing after the held mode's reset is geometry|geometry|held|reset|1 0|1|FAIL"
  "a hold row failing after the held mode's reset is behaviour|hold|held|reset|1 1|1|FAIL"
  "a render row under the reset run base is render|render|base|reset|1 0|1|FAIL"
)
for row in "${tallies[@]}"; do
  if run_tally "$verdict" "$row"; then ok "${row%%|*}"; else fail "${row%%|*}"; fi
done

# run_skip FILE ROW: true when, after not_measured as the file FILE
# defines it records one row and fail counts the row's failures, the
# verdict gives the row's status and first line.
run_skip() {
  local file="$1" label failed want_status want_line out status=0
  IFS='|' read -r label failed want_status want_line <<<"$2"
  out="$(env -i PATH="$PATH" bash -c '
set -euo pipefail
source "$1"
not_measured device-fakes missing=python-dbusmock >/dev/null
for ((i = 0; i < $2; i++)); do fail "a row" >/dev/null; done
smoke_verdict "$failures" "$behaviour_failures" /dev/null' _ \
    "$file" "$failed")" || status=$?
  [[ $status -eq $want_status && ${out%%$'\n'*} == "$want_line" ]] && return 0
  printf '        %s: status=%s want=%s first line: %s\n' "$label" "$status" "$want_status" "${out%%$'\n'*}"
  return 1
}

# Rows: label | failed rows beside the not-measured one | status | first
# line.
skips=(
  "a not-measured row in a run with no failure is not measured|0|77|qml-smoke: status=not-measured rows=device-fakes:missing=python-dbusmock"
  "a failure beside a not-measured row fails|1|1|qml-smoke: failed=1"
)
for row in "${skips[@]}"; do
  if run_skip "$verdict" "$row"; then ok "${row%%|*}"; else fail "${row%%|*}"; fi
done

# run_count FILE ROW: true when read_count, as the file FILE defines it,
# reads the row's reply from a reader exiting with the row's status, and
# the lines after it run as a row's do: one adds 1 to the count it read,
# under the harness's set -u, and the next prints that sum and the
# failures. A reading that ends the shell prints nothing and is red.
run_count() {
  local file="$1" label reply reader_status want out status=0
  IFS='|' read -r label reply reader_status want <<<"$2"
  out="$(env -i PATH="$PATH" bash -c '
set -euo pipefail
source "$1"
reader() { printf "%s\n" "$1"; return "$2"; }
read_count presses "a reading" reader "$2" "$3" >/dev/null
next=$((presses + 1))
printf "%s %s\n" "$next" "$failures"' _ "$file" "$reply" "$reader_status" 2>/dev/null)" || status=$?
  [[ $status -eq 0 && $out == "$want" ]] && return 0
  printf '        %s: status=%s got: %s want %s\n' "$label" "$status" "$out" "$want"
  return 1
}

# Rows: label | the reader's reply | the reader's exit status | the count
# plus 1 and the failures the row holds after the reading.
counts=(
  "a count is read and fails no row|7|0|8 0"
  "a probe's state word fails the row, which goes on|undefined|0|1 1"
  "an empty reply fails the row, which goes on||0|1 1"
  "a count from a failed reader fails the row|7|1|1 1"
)
for row in "${counts[@]}"; do
  if run_count "$verdict" "$row"; then ok "${row%%|*}"; else fail "${row%%|*}"; fi
done

# Drive the real scope and action through command substitution. The nested
# output leaves the held mode after the coordinates were sampled: the
# pointer step is refused and fails the row, independent failures before
# and after it stay visible, and the row still cleans up.
run_observation() {
  local file="$1" label position want_count dir out status=0
  IFS='|' read -r label position want_count <<<"$2"
  dir="$(mktemp -d "$tmp/observation.XXXXXX")" || return 1
  python3 - "$repo/scripts/smoke/harness.sh" "$dir/operations.sh" <<'PYEXTRACT' || return 1
import pathlib,sys
source,out=map(pathlib.Path,sys.argv[1:])
text=source.read_text()
parts=[]
for name in ('coordinate_observation','pointer_dispatch','hover'):
    start=text.index('\n'+name+'() {')+1
    line=text[start:text.index('\n',start)]
    end=start+len(line)+1 if line.endswith('}') else text.index('\n}\n',start)+3
    parts.append(text[start:end])
out.write_text('\n'.join(parts)+'\n')
PYEXTRACT
  out="$(env -i PATH="$PATH" "$BASH" -c '
set -euo pipefail
source "$1"
source "$2/scripts/smoke/mode-hold.sh"
source "$3/operations.sh"
sandbox="$3" stub_position="$4"
mode_hold=(WAYLAND-1 "3510x1866 scale=2")
mode_hold_run_base=true
mon_w=1755 mon_h=933 shell_env=()
pointer_at=before dependent=false cleaned=false
: >"$sandbox/cleanup-owned"
hypr() {
  if [[ -e $sandbox/reset ]]; then
    echo '\''[{"name":"WAYLAND-1","width":1250,"height":720,"scale":1}]'\''
  else
    echo '\''[{"name":"WAYLAND-1","width":3510,"height":1866,"scale":2}]'\''
  fi
}
cat >"$sandbox/click" <<'\''POINTER'\''
#!/usr/bin/env bash
echo sent >"${0%/*}/sent"
POINTER
chmod +x "$sandbox/click"
observe() {
  local result
  : >"$sandbox/reset"
  if [[ $stub_position == before || $stub_position == both ]]; then fail independent-before; fi
  result="$(hover 20 30)" || return $?
  dependent=true
}
coordinate_observation coordinates observe && cleaned=true || exit 1
rm -- "${sandbox:?}/cleanup-owned"
[[ ! -e $sandbox/cleanup-owned ]] || exit 1
if [[ $stub_position == after || $stub_position == both ]]; then fail independent-after; fi
[[ $cleaned == true && $dependent == false && $pointer_at == before && ! -e $sandbox/sent ]] || exit 1
[[ $failures == "$5" && $behaviour_failures == "$5" && ${#not_measured_rows[@]} == 0 ]] || exit 1
status=0
smoke_verdict "$failures" "$behaviour_failures" /dev/null || status=$?
[[ $status == 1 ]] || exit 1
echo observation=continued
' _ "$file" "$repo" "$dir" "$position" "$want_count")" || status=$?
  # scripts/main-run.sh consumes the FAIL prefix, not the prose after it.
  local visible=0 line
  while IFS= read -r line; do [[ $line != '  FAIL  '* ]] || visible=$((visible + 1)); done <<<"$out"
  [[ $status == 0 && $visible == "$want_count" && $out == *observation=continued ]] && return 0
  printf '        %s: status=%s visible=%s wanted=%s output=[%s]\n' "$label" "$status" "$visible" "$want_count" "$out"
  return 1
}
# Rows: label | where the independent failure goes | the FAIL lines, the
# refused step's among them.
observations=(
  'an independent failure before a refused action remains a failure|before|2'
  'an independent failure after a refused action remains a failure|after|2'
  'independent failures before and after a refused action remain failures|both|3'
)
for row in "${observations[@]}"; do
  if run_observation "$verdict" "$row"; then ok "${row%%|*}"; else fail "${row%%|*}"; fi
done

# The judges' readings: harness.sh's smoke_judge_reading, the predicates it
# shares with rows/auth-sentinel.sh and rows/tui-guard.sh and the target
# lists, qml-smoke.sh's qml_smoke_judge_reading, which records a reading,
# and teardown.sh's cleanup, which takes the closing one, extracted from
# the files, read a world of the files they read in a sandbox: the
# sentinels, the browser-policy writer and the stand-in terminal as the
# harness writes them, an empty authentication log, refusal log and stood
# list, and a fixture tree whose one plugin holds a TUI script as the
# shipped plugins. An attempt of rows w, x, tui-guard and auth-sentinel
# takes a reading at each row's start and end, each row's results pass,
# and the real teardown ends it. The case plants one defect inside one
# row's window; a cut leaves that row open with a partial record and runs
# no later row. The window `-` plants a call from a process in the
# attempt's process groups as the teardown's TERM ends it, which only the
# closing reading, taken after the groups end, reads. `killed` ends the
# attempt with no teardown, as a SIGKILL of its world leaves it; every
# other attempt ends by the teardown and must leave the closing reading.
# scripts/smoke/row-inputs.sh's smoke_attempt_judged judges the readings.
# The files run are judge_harness, judge_teardown and judge_inputs, the
# shipped ones unless a control names a copy.
judge_harness="$repo/scripts/smoke/harness.sh"
judge_teardown="$repo/scripts/smoke/teardown.sh"
judge_inputs="$repo/scripts/smoke/row-inputs.sh"
run_judged() { # ROW
  local label defect window cut want end dir out status=0 closed=no want_closed=yes
  IFS='|' read -r label defect window cut want end <<<"$1"
  [[ $end != killed ]] || want_closed=no
  dir="$(mktemp -d "$tmp/judged.XXXXXX")" || return 1
  python3 - "$dir/judges.sh" "$judge_harness" "$judge_teardown" "$repo/scripts/qml-smoke.sh" <<'PYEXTRACT' || return 1
import pathlib,sys
out,harness,teardown,smoke=map(pathlib.Path,sys.argv[1:])
def body(text,name):
    start=text.index('\n'+name+'() {')+1
    line=text[start:text.index('\n',start)]
    end=start+len(line)+1 if line.endswith('}') else text.index('\n}\n',start)+3
    return text[start:end]
text=harness.read_text()
parts=[]
for name in ('auth_sentinels','auth_sentinel_files'):
    start=text.index('\n'+name+'=(')+1
    parts.append(text[start:text.index('\n',start)])
for name in ('shell_resolves','tui_refusal_shipped','sentinel_state','command_placement','auth_call_count','stand_in_state','smoke_judge_reading'):
    parts.append(body(text,name))
parts.append(body(smoke.read_text(),'qml_smoke_judge_reading'))
parts.append(body(teardown.read_text(),'cleanup'))
out.write_text('\n'.join(parts)+'\n')
PYEXTRACT
  local script='
set -euo pipefail
sandbox="$1" defect="$2" window="$3" cut="$4" end="$5"
shim="$sandbox/shim" repo="$sandbox/repo" source_repo="$sandbox/shipped"
auth_log="$sandbox/auth-sentinel.calls" tui_refused="$sandbox/tui-refused.calls" sentinels_stood="$sandbox/sentinels.stood"
tui_terminal="$shim/xdg-terminal-exec" tui_terminal_written="$sandbox/xdg-terminal-exec.harness"
shell_start_path="$shim:$PATH"
mkdir -p "$shim" "$repo/bin" "$source_repo/shell/plugins/acme.shipped/tui"
printf "#!/bin/sh\nexit 0\n" >"$source_repo/shell/plugins/acme.shipped/tui/run.sh"
source "$sandbox/judges.sh"
for target in "${auth_sentinel_files[@]}"; do
  printf "#!/bin/sh\nprintf \"%%s\\\\n\" \"%s \$*\" >>%q\nexit 1\n" "${target##*/}" "$auth_log" >"$target"
  chmod 755 "$target"
done
printf "#!/bin/sh\nexit 0\n" >"$tui_terminal"
chmod 755 "$tui_terminal"
cp -- "$tui_terminal" "$tui_terminal_written"
: >"$tui_refused"
: >"$sentinels_stood"
plant() {
  case "$defect" in
    none) ;;
    call) PATH="$shell_start_path" sudo -n true || true ;;
    unshipped) printf "%s\n" "acme.made-up/nothing acme.made-up tui/nothing.sh" >>"$tui_refused" ;;
    shipped) printf "%s\n" "acme.shipped/run acme.shipped tui/run.sh" >>"$tui_refused" ;;
    stood) printf "%s\n" "$shim/sudo" >>"$sentinels_stood" ;;
    rewritten) printf "#!/bin/sh\nexit 0\n" >"$shim/pkexec" ;;
    unexecutable) chmod 644 "$shim/su" ;;
    writer) printf "#!/bin/sh\nexit 0\n" >"$repo/bin/vgshell-browser-policy" ;;
    writer-gone) rm -- "$repo/bin/vgshell-browser-policy" ;;
    terminal) printf "echo changed\n" >>"$tui_terminal" ;;
    refusals-gone) rm -- "$tui_refused" ;;
    *) echo "defect=$defect unknown" >&2; exit 2 ;;
  esac
}
# late_call PATH READY: a process group that makes one authentication call
# through PATH as a TERM ends it, after it writes its group to READY. The
# loop is a bound on a group no teardown ends, not a reading.
late_call() {
  trap "PATH=$(printf %q "$1") sudo -n true; exit 0" TERM
  printf "%s\n" "$$" >"$2"
  for ((tick = 0; tick < 300; tick++)); do sleep 0.1; done
}
qml_smoke_attempt="$sandbox/attempt"
a="$qml_smoke_attempt"
mkdir -p "$a/results" "$a/partial"
printf "0\0" >"$a/outside-failures"
pgids=()
if [[ $window == - ]]; then
  [[ $defect == call ]] || { echo "defect=$defect window=- unknown" >&2; exit 2; }
  setsid "$BASH" -c "$(declare -f late_call); late_call \"\$@\"" _ "$shell_start_path" "$sandbox/late.pgid" </dev/null >/dev/null 2>&1 &
  for ((tick = 0; tick < 100; tick++)); do [[ ! -s $sandbox/late.pgid ]] || break; sleep 0.05; done
  pgids+=("$(<"$sandbox/late.pgid")")
fi
for row in w x tui-guard auth-sentinel; do
  qml_smoke_judge_reading "$row" start
  [[ $row != "$window" ]] || plant
  if [[ $row == "$window" && -n $cut ]]; then printf "%s\0" "$cut" >"$a/partial/$row"; break; fi
  qml_smoke_judge_reading "$row" end
  printf "0\0" >"$a/results/$row"
done
[[ $end == killed ]] || cleanup 0
'
  env -i PATH="$PATH" "$BASH" -c "$script" _ "$dir" "$defect" "$window" "$cut" "$end" || status=$?
  if grep -q '^- close ' "$dir/attempt/judge-readings" 2>/dev/null; then closed=yes; fi
  out="$(set -euo pipefail; source "$judge_inputs"; if smoke_attempt_judged "$dir/attempt"; then echo proved; else echo unproved; fi)" || out=judge-failed
  [[ $status == 0 && $out == "$want" && $closed == "$want_closed" ]] && return 0
  printf '        %s: status=%s got=%s want=%s close=%s want=%s readings:\n' "$label" "$status" "$out" "$want" "$closed" "$want_closed"
  sed 's/^/          /' "$dir/attempt/judge-readings" 2>/dev/null || true
  return 1
}
# Rows: label | the defect | the row in whose window it lands, `-` for a
# call a process makes as the teardown ends it | empty when every row
# ends, else the failure count of that row's partial record, the attempt
# cut in that row | proved or unproved | killed when no teardown ends the
# attempt, else empty.
judged_killed="an attempt whose world was killed before its teardown has no closing reading and proves nothing|none|x||unproved|killed"
judged=(
  "readings that show nothing prove the attempt|none|x||proved"
  "an authentication call in a row's window voids the attempt|call|x||unproved"
  "a refusal of a script no shipped plugin holds voids the attempt|unshipped|x||unproved"
  "a refusal of a shipped plugin's TUI script proves the attempt|shipped|x||proved"
  "a sentinel left stood over voids the attempt|stood|x||unproved"
  "a sentinel that no longer logs voids the attempt|rewritten|x||unproved"
  "a sentinel no longer first on the shell's PATH voids the attempt|unexecutable|x||unproved"
  "a browser-policy writer that no longer logs voids the attempt|writer|x||unproved"
  "a missing browser-policy writer voids the attempt|writer-gone|x||unproved"
  "a rewritten stand-in terminal voids the attempt|terminal|x||unproved"
  "an unreadable refusal log voids the attempt|refusals-gone|x||unproved"
  "a call in auth-sentinel's window, whose controls plant calls, proves the attempt|call|auth-sentinel||proved"
  "a refusal in tui-guard's window, whose controls plant refusals, proves the attempt|unshipped|tui-guard||proved"
  "a call in tui-guard's window voids the attempt|call|tui-guard||unproved"
  "a refusal in auth-sentinel's window voids the attempt|unshipped|auth-sentinel||unproved"
  "a call a process makes as the teardown ends it, read by the closing reading, voids the attempt|call|-||unproved"
  "a judge row left open with a failure voids the attempt|none|tui-guard|1|unproved"
  "a call in auth-sentinel's window, cut before its end reading, voids the attempt|call|auth-sentinel|0|unproved"
  "a refusal in tui-guard's window, cut before its end reading, voids the attempt|unshipped|tui-guard|0|unproved"
  "$judged_killed"
)
for row in "${judged[@]}"; do
  if run_judged "$row"; then ok "${row%%|*}"; else fail "${row%%|*}"; fi
done

# mutate OLD NEW OUT [FILE]: a copy of FILE, the verdict by default, with
# OLD, which must occur once, replaced by NEW.
mutate() {
  local file="${4:-$verdict}" text rest count
  text="$(<"$file")"
  rest="${text//"$1"/}"
  count=$(( (${#text} - ${#rest}) / ${#1} ))
  if [[ $count -ne 1 ]]; then
    printf '        mutation matched %s times: %s\n' "$count" "$1"
    return 1
  fi
  printf '%s\n' "${text/"$1"/"$2"}" >"$3"
  cmp -s -- "$file" "$3" && { printf '        mutation left the file unchanged: %s\n' "$1"; return 1; }
  return 0
}

# The judges' controls, each a copy of one file run in its place, the
# file's judge_ variable naming it: label | variable | text | replacement
# | the row that must go red | what its diagnostic must show, empty for
# any. A field holds no `|`.
judged_controls=(
  "a reading that pins the calls to 0|judge_harness|printf '%s %s %s\\n' \"\$((calls))\" \"\$refused\" \"\$state\"|printf '%s %s %s\\n' 0 \"\$refused\" \"\$state\"|${judged[1]}|"
  "a teardown that takes no closing reading|judge_teardown|if declare -F qml_smoke_judge_reading >/dev/null; then qml_smoke_judge_reading - close; fi|:|${judged[15]}|"
  "a judgement that does not require the closing reading|judge_inputs|  [[ \$closed == true ]]|  :|$judged_killed|got=proved want=unproved"
)
for control in "${judged_controls[@]}"; do
  IFS='|' read -r label variable old new row_label row_defect row_window row_cut row_want row_end want_shown <<<"$control"
  row="$row_label|$row_defect|$row_window|$row_cut|$row_want|$row_end"
  case "$variable" in
    judge_harness) original="$judge_harness" ;;
    judge_teardown) original="$judge_teardown" ;;
    judge_inputs) original="$judge_inputs" ;;
    *) fail "control: $label names no file: $variable"; continue ;;
  esac
  mutant="$tmp/mutant-$variable.sh"
  if ! mutate "$old" "$new" "$mutant" "$original"; then fail "control: $label"; continue; fi
  if shown="$(printf -v "$variable" '%s' "$mutant"; run_judged "$row")"; then
    fail "control: $label left '$row_label' green"
  elif [[ $shown != *"$want_shown"* ]]; then
    fail "control: $label turned '$row_label' red without $want_shown"; printf '%s\n' "$shown"
  else
    ok "control: $label"
  fi
done

# Rows: label | text | replacement | the case label that must go red. A
# field holds no `|`, the separator.
controls=(
  "a reset suppresses independent failures|fail() {|fail() { if [[ \$(held_mode_state) == reset ]]; then return 0; fi|independent failures before and after a refused action remain failures"
  "a reset excuses a failure|fail() {|fail() { if [[ \${#mode_hold[@]} -gt 0 && \$(held_mode_state) == reset ]]; then failures=\$((failures + 1)); return 0; fi|a row failing after the held mode's reset is behaviour"
  "a geometry failure counts as behaviour|[[ \$row_class == geometry |[[ \$row_class == never |a geometry row failing with no hold is geometry"
  "a render failure counts as behaviour|\$row_class == render ]]|\$row_class == never ]]|a render row failing with no hold is render"
  "the excuse reads any GBM allocation failure|'Output WAYLAND-[0-9]+: pending state rejected: swapchain failed reconfiguring'|'Failed to allocate a GBM buffer'|all-geometry failure with a passing log fails"
  "the nested output's fault is not read|nested_output_unallocated \"\$@\"; then|false; then|all-geometry failure with the nested output's fault is not measured"
  "a behaviour failure is excused by the fault|if [[ \$behaviour_failures -eq 0 ]] && nested_output_unallocated|if nested_output_unallocated|a behaviour failure with the fault fails"
  "a not-measured row is not read|\$failures -eq 0 && \${#not_measured_rows[@]} -gt 0|\$failures -eq 0 && \${#not_measured_rows[@]} -gt 9|a not-measured row in a run with no failure is not measured"
  "a not-measured row excuses a failure|if [[ \$failures -eq 0 && \${#not_measured_rows[@]}|if [[ \${#not_measured_rows[@]}|a failure beside a not-measured row fails"
  "a state word is read as a count|\$read_count_status -eq 0 && \$read_count_got =~ ^[0-9]+\$ ]]|\$read_count_status -eq 0 ]]|a probe's state word fails the row, which goes on"
  "a failed reader's count is kept|\$read_count_status -eq 0 && \$read_count_got =~|\$read_count_got =~|a count from a failed reader fails the row"
)
for i in "${!controls[@]}"; do
  IFS='|' read -r label old new target <<<"${controls[i]}"
  mutant="$tmp/mutant-$i.sh"
  if ! mutate "$old" "$new" "$mutant"; then fail "control: $label"; continue; fi
  row="" runner=""
  for candidate in "${cases[@]}"; do [[ ${candidate%%|*} == "$target" ]] && { row="$candidate"; runner=run_case; }; done
  for candidate in "${tallies[@]}"; do [[ ${candidate%%|*} == "$target" ]] && { row="$candidate"; runner=run_tally; }; done
  for candidate in "${skips[@]}"; do [[ ${candidate%%|*} == "$target" ]] && { row="$candidate"; runner=run_skip; }; done
  for candidate in "${counts[@]}"; do [[ ${candidate%%|*} == "$target" ]] && { row="$candidate"; runner=run_count; }; done
  for candidate in "${observations[@]}"; do [[ ${candidate%%|*} == "$target" ]] && { row="$candidate"; runner=run_observation; }; done
  if [[ -z $row ]]; then fail "control: $label names no case: $target"; continue; fi
  if "$runner" "$mutant" "$row" >/dev/null; then fail "control: $label left '$target' green"; else ok "control: $label"; fi
done

if [[ $failures -gt 0 ]]; then
  echo "test-smoke-verdict: failed=$failures"
  exit 1
fi
echo "test-smoke-verdict: ok"
