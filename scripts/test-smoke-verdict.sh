#!/usr/bin/env bash
# Drive scripts/smoke/verdict.sh, the nested smoke's closing verdict, with
# the counters smoke_finish hands it and fixture compositor logs, and fail,
# which writes those counters by the row's class whatever the held mode
# reads, a row not_measured records beside them, and read_count, the count
# a row adds to, with a stub reader. No case needs a sandbox.
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
    start=text.index(name+'() {')
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

# mutate OLD NEW OUT: a copy of the verdict with OLD, which must occur once,
# replaced by NEW.
mutate() {
  local text rest count
  text="$(<"$verdict")"
  rest="${text//"$1"/}"
  count=$(( (${#text} - ${#rest}) / ${#1} ))
  if [[ $count -ne 1 ]]; then
    printf '        mutation matched %s times: %s\n' "$count" "$1"
    return 1
  fi
  printf '%s\n' "${text/"$1"/"$2"}" >"$3"
  cmp -s -- "$verdict" "$3" && { printf '        mutation left the file unchanged: %s\n' "$1"; return 1; }
  return 0
}

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
