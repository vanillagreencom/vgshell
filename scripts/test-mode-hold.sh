#!/usr/bin/env bash
# Drive scripts/smoke/mode-hold.sh, the mode a row holds on a nested
# output, with no sandbox. A stub hypr stands in for the nested
# compositor: each batch command returns its own reply. A reload answers
# the case's reply and, when it is
# `ok`, records the rule from the hold file. `hypr -j monitors` lists
# WAYLAND-1 at the mode and scale the case plans for the reloads so far,
# so the real monitor_rule, reload reader and mode_scale_of run. A stub sleep keeps the
# 5 s polls instant. Each case pins the exit status, the tallies, mode
# resets among them, the hold's state as held_mode_state reads it, the
# window size the hold records, the rules applied and the typed
# not-measured diagnostic. A second table runs
# whole_scale_mode, the mode and scale a hold above scale 1 takes, and
# pins its output and exit status. A third runs held_mode_host_sized, whether
# a taken hold reads the host window's own size, over the stub monitor. The
# controls at the end plant one
# defect per rule in a copy of the file and require the case that rule
# owns to go red.
#
# Exit 0 when every case and control holds, 1 otherwise.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
subject="$repo/scripts/smoke/mode-hold.sh"

tmp="$(mktemp -d)" || { echo "test-mode-hold: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "test-mode-hold: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)"
trap 'rm -rf -- "${tmp:?}"' EXIT
failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

# run_case FILE ROW: true when the hold FILE defines gives the row's
# result. The case runs in a clean bash with the harness's options; its
# stub state lives in files, since take_mode runs in a command
# substitution.
run_case() {
  local file="$1" label call reply plan want_status want_rules dir out status=0 got_state got_rules
  IFS='|' read -r label call reply plan want_status want_rules <<<"$2"
  dir="$(mktemp -d "$tmp/case.XXXXXX")" || { printf '        %s: scratch=mktemp-failed\n' "$label"; return 1; }
  out="$(env -i PATH="$PATH" bash -c '
set -euo pipefail
source "$1/scripts/smoke/verdict.sh"
source "$2"
# The stub state carries a prefix: a local of the subject shadows a global
# of the same name inside every function it calls, the stub hypr included.
stub_dir="$3"; stub_reply="$4"; stub_call="$6"
IFS=, read -r -a stub_plan <<<"$5"
mode_hold_file="$stub_dir/monitor-hold.lua"
rt_dir="$stub_dir"
ok() { printf "ok %s\n" "$*"; }
sleep() { :; }
py_reply() { python3 -c "$@"; }
# The plan names, for each rule applied, what the monitor then reads:
# `take` is the rule'\''s own mode and scale, anything else that reading,
# as the host'\''s configure leaves it. The last entry stands for every
# later rule. Before any rule, the output reads its own mode at scale 1.
hypr() {
  local rules=0 reading rule command separator="" commands=()
  [[ -f $stub_dir/rules ]] && rules="$(wc -l <"$stub_dir/rules")"
  if [[ $1 == --batch ]]; then
    IFS=";" read -r -a commands <<<"$2"
    for command in "${commands[@]}"; do
      command="${command#"${command%%[![:space:]]*}"}"
      command="${command%"${command##*[![:space:]]}"}"
      printf "%s" "$separator"
      case "$command" in
        "reload config-only")
          if [[ $stub_reply == config-error ]]; then printf "ok"; else printf "%s" "$stub_reply"; fi
          [[ $stub_reply != ok ]] || tail -n 1 "$mode_hold_file" >>"$stub_dir/rules" ;;
        j/configerrors)
          if [[ $stub_reply == config-error ]]; then printf "[\"invalid rule\"]"; else printf "[]"; fi ;;
        *) return 1 ;;
      esac
      separator=$'\''\n\n\n'\''
    done
    printf "\n"
    return 0
  fi
  if [[ $1 == eval ]]; then
    printf "ok\n"
    return 0
  fi
  reading="1755x933 scale=1"
  if ((rules > 0)); then
    reading="${stub_plan[rules - 1]:-${stub_plan[-1]}}"
    if [[ $reading == take ]]; then
      rule="$(tail -n 1 "$stub_dir/rules")"
      [[ $rule =~ mode\ =\ \"([0-9x]+)\".*scale\ =\ ([0-9.]+) ]]
      reading="${BASH_REMATCH[1]} scale=${BASH_REMATCH[2]}"
    fi
  fi
  if [[ $reading == unreadable ]]; then echo "[]"; return 0; fi
  printf "[{\"name\": \"WAYLAND-1\", \"width\": %s, \"height\": %s, \"scale\": %s}]\n" \
    "${reading%%x*}" "$(r="${reading#*x}"; echo "${r% scale=*}")" "${reading##*scale=}"
}
status=0
case "$stub_call" in
  hold-after-behaviour|hold-after-geometry|hold-after-render)
    row_class="${stub_call#hold-after-}"
    fail "product failure"
    hold_mode "the case" WAYLAND-1 3510x1866 2 ;;
  take-missing) take_mode WAYLAND-1 3510x1866 2 || status=$? ;;
  release-only) release_mode "the release" WAYLAND-1 3510x1866 2 ;;
  hold) hold_mode "the case" WAYLAND-1 3510x1866 2 ;;
  restore)
    printf "%s\n" "$(monitor_rule WAYLAND-1 3510x1866 2)" >"$mode_hold_file"
    mode_hold=(WAYLAND-1 "3510x1866 scale=2")
    hold_restore || status=$? ;;
  restore-none) hold_restore || status=$? ;;
  hold-release)
    expect() { :; }
    expect_poll() { :; }
    hold_mode "the case" WAYLAND-1 3510x1866 2
    release_mode "the release" WAYLAND-1 1755x933 ;;
  nested)
    expect() { local label="$1" want="$2" got; shift 2; got="$("$@")"; [[ $got == "$want" ]] || failures=$((failures + 1)); }
    expect_poll() { expect "$@"; }
    check_hold() {
      [[ ${mode_hold[1]} == "$1" && $mode_hold_window == 1755x933 && $(held_mode_state) == held ]] || failures=$((failures + 1))
      local rule
      rule="$(tail -n 1 "$mode_hold_file")"
      [[ $rule =~ mode\ =\ \"([0-9x]+)\".*scale\ =\ ([0-9.]+) ]]
      [[ "${BASH_REMATCH[1]} scale=${BASH_REMATCH[2]}" == "$1" ]] || failures=$((failures + 1))
    }
    hold_mode "the case" WAYLAND-1 3510x1866 2
    hold_mode "the middle" WAYLAND-1 1440x900
    check_hold "1440x900 scale=1"
    hold_mode "the inner" WAYLAND-1 1440x320
    check_hold "1440x320 scale=1"
    release_mode "the inner release" WAYLAND-1 1755x933
    check_hold "1440x900 scale=1"
    release_mode "the middle release" WAYLAND-1 1755x933
    check_hold "3510x1866 scale=2"
    release_mode "the outer release" WAYLAND-1 1755x933
    [[ $(mode_scale_of WAYLAND-1) == "1755x933 scale=1" && ${#mode_hold_parents[@]} -eq 0 ]] || failures=$((failures + 1)) ;;
esac
file=absent; [[ -f $mode_hold_file ]] && file=present
state=none; [[ ${#mode_hold[@]} -eq 0 ]] || state="$(held_mode_state)"
printf "result status=%s failures=%s resets=%s held=[%s] window=[%s] state=%s file=%s\n" "$status" "$failures" "$mode_resets" "${mode_hold[*]:-}" "$mode_hold_window" "$state" "$file"
' _ "$repo" "$file" "$dir" "$reply" "$plan" "$call")" || status=$?
  got_state="$(grep -m 1 '^result ' <<<"$out")" || got_state=""
  got_rules=0; [[ -f $dir/rules ]] && got_rules="$(wc -l <"$dir/rules")"
  local want_exit=0
  if [[ $want_status == 'qml-smoke: failed='* ]]; then
    want_exit=1
    got_state="$(grep '^qml-smoke: failed=' <<<"$out")" || got_state=""
    [[ $out != *'status=not-measured'* && $out != *'result '* ]] || return 1
  elif [[ $want_status == qml-smoke:* ]]; then
    want_exit=77
    got_state="$(grep '^qml-smoke: status=not-measured ' <<<"$out")" || got_state=""
    [[ $out != *'  FAIL  '* && $out != *'result '* ]] || return 1
  else
    want_status="result $want_status"
  fi
  if [[ $status -eq $want_exit && $got_state == "$want_status" && $got_rules -eq $want_rules ]]; then
    return 0
  fi
  printf '        %s: exit=%s state=[%s] rules=%s want exit=%s [%s] rules=%s\n' \
    "$label" "$status" "$got_state" "$got_rules" "$want_exit" "$want_status" "$want_rules"
  return 1
}

# Rows: label | call | reload reply | readings after each rule, comma
# separated | result or typed diagnostic | rules applied.
# The output reads 1755x933 at scale 1 before any rule, the size a taken
# hold records as the host window's.
cases=(
  "an unavailable mode preserves an earlier product failure|hold-after-behaviour|ok|1755x933 scale=1.5|qml-smoke: failed=1|3"
  "an unavailable mode preserves an earlier geometry failure|hold-after-geometry|ok|1755x933 scale=1.5|qml-smoke: failed=1|3"
  "an unavailable mode preserves an earlier render failure|hold-after-render|ok|1755x933 scale=1.5|qml-smoke: failed=1|3"
  "a hold that cannot take a readable mode stops unmeasured|hold|ok|1755x933 scale=1.5|qml-smoke: status=not-measured nested-output=mode-unavailable output=WAYLAND-1 want=[3510x1866 scale=2] attempts=3 got=[1755x933 scale=1.5]|3"
  "a release that cannot take its base stops unmeasured|release-only|ok|1700x900 scale=1|qml-smoke: status=not-measured nested-output=mode-unavailable output=WAYLAND-1 want=[3510x1866 scale=2] attempts=3 got=[1700x900 scale=1]|3"
  "an unreadable output fails instead of being excused|hold|ok|unreadable|status=0 failures=1 resets=0 held=[] window=[] state=none file=absent|3"
  "an unreadable hold file fails before reload|take-missing|ok|take|status=1 failures=0 resets=0 held=[] window=[] state=none file=absent|0"
  "configuration errors fail instead of being excused|hold|config-error|take|status=0 failures=1 resets=0 held=[] window=[] state=none file=absent|0"
  "a hold the output takes at once is held|hold|ok|take|status=0 failures=0 resets=0 held=[WAYLAND-1 3510x1866 scale=2] window=[1755x933] state=held file=present|1"
  "a hold the host resets once is applied again and held|hold|ok|1755x933 scale=1.5,take|status=0 failures=0 resets=0 held=[WAYLAND-1 3510x1866 scale=2] window=[1755x933] state=held file=present|2"
  "a refused rule fails at once|hold|error|take|status=0 failures=1 resets=0 held=[] window=[] state=none file=absent|0"
  "a restore after a reset takes the held mode and scale|restore|ok|1755x933 scale=1.5,take|status=0 failures=0 resets=0 held=[WAYLAND-1 3510x1866 scale=2] window=[] state=held file=present|2"
  "a restore the host always resets fails after the bound|restore|ok|1755x933 scale=1.5|status=1 failures=0 resets=0 held=[WAYLAND-1 3510x1866 scale=2] window=[] state=reset file=present|3"
  "a release empties the recorded window size|hold-release|ok|take|status=0 failures=0 resets=0 held=[] window=[] state=none file=absent|2"
  "a restore with no hold is refused|restore-none|ok|take|status=1 failures=0 resets=0 held=[] window=[] state=none file=absent|0"
  "nested holds restore each parent and its scale|nested|ok|take|status=0 failures=0 resets=0 held=[] window=[] state=none file=absent|6"
)
for row in "${cases[@]}"; do
  if run_case "$subject" "$row"; then ok "${row%%|*}"; else fail "${row%%|*}"; fi
done

# scale_case FILE ROW: true when whole_scale_mode, as FILE defines it,
# prints the row's line and exits with its status, in a clean bash with
# the harness's options.
scale_case() {
  local label mode want got status=0
  IFS='|' read -r label mode want <<<"$2"
  got="$(env -i PATH="$PATH" bash -c '
set -euo pipefail
source "$1/scripts/smoke/verdict.sh"
source "$2"
status=0
out="$(whole_scale_mode "$3")" || status=$?
printf "status=%s out=[%s]\n" "$status" "$out"
' _ "$repo" "$1" "$mode")" || status=$?
  [[ $status -eq 0 && $got == "$want" ]] && return 0
  printf '        %s: exit=%s got [%s] want [%s]\n' "$label" "$status" "$got" "$want"
  return 1
}

# Rows: label | own mode | what whole_scale_mode prints and returns. The
# modes are the nested window's sizes on host cachy (1755x933, 1756x933)
# and the window rule's floor (1250x720).
scale_cases=(
  "a mode scale 3 divides keeps its size at scale 3|1755x933|status=0 out=[1755x933 3]"
  "a mode scale 2 divides keeps its size at scale 2|1250x720|status=0 out=[1250x720 2]"
  "a mode no scale divides is trimmed by the fewest pixels|1756x933|status=0 out=[1755x933 3]"
  "a tie goes to the smaller scale|1756x932|status=0 out=[1756x932 2]"
  "a zero side is refused|0x933|status=1 out=[whole-scale-mode: refused mode=[0x933]]"
  "a mode with trailing text is refused|1755x933junk|status=1 out=[whole-scale-mode: refused mode=[1755x933junk]]"
  "a mode a scale trims to nothing is refused|1x5|status=1 out=[whole-scale-mode: refused mode=[1x5]]"
)
for row in "${scale_cases[@]}"; do
  if scale_case "$subject" "$row"; then ok "${row%%|*}"; else fail "${row%%|*}"; fi
done

# sized_case FILE ROW: true when held_mode_host_sized, as FILE defines it,
# answers the row's word for a hold of the row's mode and recorded window
# size, while a stub hypr lists WAYLAND-1 at the row's reading, so the
# real mode_scale_of runs. `unreadable` lists no monitor.
sized_case() {
  local label held window reading want got status=0
  IFS='|' read -r label held window reading want <<<"$2"
  got="$(env -i PATH="$PATH" bash -c '
set -euo pipefail
source "$1/scripts/smoke/verdict.sh"
source "$2"
stub_reading="$5"
hypr() {
  if [[ $stub_reading == unreadable ]]; then echo "[]"; return 0; fi
  printf "[{\"name\": \"WAYLAND-1\", \"width\": %s, \"height\": %s, \"scale\": %s}]\n" \
    "${stub_reading%%x*}" "$(r="${stub_reading#*x}"; echo "${r% scale=*}")" "${stub_reading##*scale=}"
}
mode_hold=(WAYLAND-1 "$3")
mode_hold_window="$4"
if held_mode_host_sized; then echo true; else echo false; fi
' _ "$repo" "$1" "$held" "$window" "$reading")" || status=$?
  [[ $status -eq 0 && $got == "$want" ]] && return 0
  printf '        %s: exit=%s got [%s] want [%s]\n' "$label" "$status" "$got" "$want"
  return 1
}

# Rows: label | held mode and scale | recorded window size | what the
# monitor reads | whether the hold reads host-sized.
sized_cases=(
  "the window's size under another held mode is host-sized|3510x1866 scale=2|1755x933|1755x933 scale=1.5|true"
  "the held mode is not host-sized|3510x1866 scale=2|1755x933|3510x1866 scale=2|false"
  "another size is not host-sized|3510x1866 scale=2|1755x933|1700x900 scale=1|false"
  "a hold at the window's own size is never host-sized|1755x933 scale=3|1755x933|1755x933 scale=1|false"
  "an unreadable monitor is not host-sized|3510x1866 scale=2|1755x933|unreadable|false"
  "no recorded window size is not host-sized|3510x1866 scale=2||1755x933 scale=1|false"
)
for row in "${sized_cases[@]}"; do
  if sized_case "$subject" "$row"; then ok "${row%%|*}"; else fail "${row%%|*}"; fi
done

# base_case FILE ROW: the base of a temporary hold comes from its matching
# outer hold, even when the live output has reset to a different scale.
base_case() {
  local label output held_output held want got status=0
  IFS='|' read -r label output held_output held want <<<"$2"
  got="$(env -i PATH="$PATH" bash -c '
set -euo pipefail
source "$1/scripts/smoke/verdict.sh"
source "$2"
mode_scale_of() { printf "%s\n" "1755x933 scale=1.5"; }
mode_hold=()
[[ -z $4 ]] || mode_hold=("$4" "$5")
base_mode_scale "$3"
' _ "$repo" "$1" "$output" "$held_output" "$held")" || status=$?
  [[ $status -eq 0 && $got == "$want" ]] && return 0
  printf '        %s: exit=%s got [%s] want [%s]\n' "$label" "$status" "$got" "$want"
  return 1
}
base_cases=(
  "a reset output keeps its matching outer hold as the fixture base|WAYLAND-1|WAYLAND-1|3510x1866 scale=2|3510x1866 scale=2"
  "an unheld output uses its live mode and scale as the fixture base|WAYLAND-1|||1755x933 scale=1.5"
  "another output's hold does not replace the fixture base|WAYLAND-1|WAYLAND-2|3510x1866 scale=2|1755x933 scale=1.5"
)
for row in "${base_cases[@]}"; do
  if base_case "$subject" "$row"; then ok "${row%%|*}"; else fail "${row%%|*}"; fi
done

# mutate OLD NEW OUT: a copy of the hold with OLD, which must occur once,
# replaced by NEW.
mutate() {
  local text rest count
  text="$(<"$subject")"
  rest="${text//"$1"/}"
  count=$(( (${#text} - ${#rest}) / ${#1} ))
  if [[ $count -ne 1 ]]; then
    printf '        mutation matched %s times: %s\n' "$count" "$1"
    return 1
  fi
  printf '%s\n' "${text/"$1"/"$2"}" >"$3"
  cmp -s -- "$subject" "$3" && { printf '        mutation left the file unchanged: %s\n' "$1"; return 1; }
  return 0
}

# Rows: label | text | replacement | the case label that must go red. A
# field holds no `|`, the separator.
controls=(
  "configuration errors are accepted|[[ \$reply != '[]' ]]|[[ \$reply == never ]]|configuration errors fail instead of being excused"
  "an unreadable output is excused|[[ \$got != unreadable ]]|true|an unreadable output fails instead of being excused"
  "an unavailable mode excuses an earlier product failure|if [[ \$failures -gt 0 ]]; then|if false; then|an unavailable mode preserves an earlier product failure"
  "an unavailable mode checks only earlier behaviour failures|if [[ \$failures -gt 0 ]]; then|if [[ \$behaviour_failures -gt 0 ]]; then|an unavailable mode preserves an earlier geometry failure"
  "mode application omits configuration reload|reload config-only ; j/configerrors|j/configerrors|a hold the output takes at once is held"
  "take_mode defers mode application until a frame|reply=\"\$(hypr_reload_errors)\"|reply=\"\$(output_mode \"\$output\" \"\$mode\" \"\$scale\")\"|a hold the output takes at once is held"
  "an unavailable mode uses a product failure|  exit 77|  return 0|a hold that cannot take a readable mode stops unmeasured"
  "an unreadable hold file is excused|if [[ ! -r \$mode_hold_file ]]; then|if false; then|an unreadable hold file fails before reload"
  "take_mode applies the rule once|attempt <= mode_attempts; attempt++|attempt <= 1; attempt++|a hold the host resets once is applied again and held"
  "take_mode applies the rule past the bound|mode_attempts=3|mode_attempts=4|a hold that cannot take a readable mode stops unmeasured"
  "hold_mode records no window size|    mode_hold_window=\"\$window\"|    mode_hold_window=\"\"|a hold the output takes at once is held"
  "release_mode keeps the window size|  mode_hold_window=\"\"|  mode_hold_window=\"\$mode_hold_window\"|a release empties the recorded window size"
  "held_mode_host_sized always answers true|held_mode_host_sized() {|held_mode_host_sized() { return 0|the held mode is not host-sized"
  "held_mode_host_sized reads a hold at the window's own size|[[ \$mode_hold_window != \"\${mode_hold[1]% scale=*}\" ]]|true|a hold at the window's own size is never host-sized"
  "a refused reload is accepted|if reload.strip() != \"ok\":|if False:|a refused rule fails at once"
  "hold_restore drops the held scale|take_mode \"\${mode_hold[0]}\" \"\${mode_hold[1]% scale=*}\" \"\${mode_hold[1]##*scale=}\"|take_mode \"\${mode_hold[0]}\" \"\${mode_hold[1]% scale=*}\" \"1\"|a restore after a reset takes the held mode and scale"
  "a release drops every parent|if [[ \${#mode_hold_parents[@]} -gt 0 ]]; then|if false; then|nested holds restore each parent and its scale"
  "the fixture base ignores a matching outer hold|base_mode_scale() {|base_mode_scale() { mode_scale_of \"\$1\"; return|a reset output keeps its matching outer hold as the fixture base"
  "the fixture base takes another output's hold|\${mode_hold[0]} == \"\$1\"|true|another output's hold does not replace the fixture base"
  "hold_restore runs with no hold|if [[ \${#mode_hold[@]} -eq 0 ]]; then|if [[ \${#mode_hold[@]} -eq -1 ]]; then|a restore with no hold is refused"
  "whole_scale_mode takes only a scale that divides|tw=\$((w - w % s)) th=\$((h - h % s))|tw=\$((w % s ? 0 : w)) th=\$((h % s ? 0 : h))|a mode no scale divides is trimmed by the fewest pixels"
  "whole_scale_mode takes the first scale tried|trim < best_trim))|trim < -1))|a mode no scale divides is trimmed by the fewest pixels"
  "whole_scale_mode reads a mode inside other text|=~ ^([1-9][0-9]*)x([1-9][0-9]*)\$ ]]|=~ ([1-9][0-9]*)x([1-9][0-9]*) ]]|a mode with trailing text is refused"
  "whole_scale_mode keeps a side trimmed to nothing|((tw == 0 |((tw == -1 |a mode a scale trims to nothing is refused"
)
for i in "${!controls[@]}"; do
  IFS='|' read -r label old new target <<<"${controls[i]}"
  mutant="$tmp/mutant-$i.sh"
  if ! mutate "$old" "$new" "$mutant"; then fail "control: $label"; continue; fi
  row="" runner=""
  for candidate in "${cases[@]}"; do [[ ${candidate%%|*} == "$target" ]] && row="$candidate" runner=run_case; done
  for candidate in "${scale_cases[@]}"; do [[ ${candidate%%|*} == "$target" ]] && row="$candidate" runner=scale_case; done
  for candidate in "${sized_cases[@]}"; do [[ ${candidate%%|*} == "$target" ]] && row="$candidate" runner=sized_case; done
  for candidate in "${base_cases[@]}"; do [[ ${candidate%%|*} == "$target" ]] && row="$candidate" runner=base_case; done
  if [[ -z $row ]]; then fail "control: $label names no case: $target"; continue; fi
  if "$runner" "$mutant" "$row" >/dev/null 2>&1; then fail "control: $label left '$target' green"; else ok "control: $label"; fi
done

if [[ $failures -gt 0 ]]; then
  echo "test-mode-hold: failed=$failures"
  exit 1
fi
echo "test-mode-hold: ok"
