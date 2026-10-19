#!/usr/bin/env bash
# Drive scripts/smoke/mode-hold.sh, the mode a row holds on a nested
# output, with no sandbox. A stub hypr stands in for the nested
# compositor: each batch command returns its own reply. A reload answers
# the case's reply and, when it is
# `ok`, records the rule from the hold file. `hypr -j monitors` lists
# WAYLAND-1 at the mode and scale the case plans for the reloads so far,
# so the real monitor_rule, reload reader and mode_scale_of run. A stub sleep keeps the
# 5 s polls instant. Each case pins the exit status, the tallies, the
# hold's state as held_mode_state reads it, the rules applied and the
# typed not-measured diagnostic. Startup and capture cases execute their source
# operations and require a checked monitor before the shell stand-in runs.
# Run-base cases suspend that startup hold for a row and put it back, at
# the row's end and through the row's early-end command.
# A second table runs
# whole_scale_mode, the mode and scale a hold above scale 1 takes, and
# pins its output and exit status. A third reads base_mode_scale. The
# controls after them plant one defect per rule in a copy of the file and
# require the case that rule owns to go red. The coordinate cases at the
# end run the pointer steps of scripts/smoke/harness.sh and the Surfaces
# row's reader under a held mode, and refuse a step once the output left
# it.
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
  python3 - "$repo/scripts/smoke/harness.sh" "$repo/scripts/qml-smoke.sh" "$repo/scripts/sandbox-shots.sh" "$dir/startup.sh" "$dir/capture.sh" "$call" <<'PYEXTRACT' || return 1
import pathlib,sys
harness,entry,capture,startup,out=map(pathlib.Path,sys.argv[1:6])
text=harness.read_text()
parts=[]
for name in ("unscaled_mode_of", "hidpi_mode_of"):
    start=text.index(name+"() {")
    parts.append(text[start:text.index("\n}\n",start)+3])
size=[line for line in entry.read_text().splitlines() if line.startswith("shell_output_size=")]
assert len(size)==1
if sys.argv[6].startswith("capture-"): size=[]
start=text.index('# shell_output_scale is')
end=text.index('# The one live layer',start)
startup.write_text("\n".join(parts)+"\n"+"\n".join(size)+"\n"+text[start:end])
text=capture.read_text()
start=text.index('if [[ -n $shot_size ]]; then')
out.write_text(text[start:text.index("\nfi\n",start)+4])
PYEXTRACT
  out="$(env -i PATH="$PATH" "$BASH" -c '
set -euo pipefail
source "$1/scripts/smoke/verdict.sh"
source "$2"
# The stub state carries a prefix: a local of the subject shadows a global
# of the same name inside every function it calls, the stub hypr included.
repo="$1"; stub_dir="$3"; stub_reply="$4"; stub_call="$6"
# A call ending in -unallocated logs WAYLAND-1'\''s allocation failure at
# each reload, -other WAYLAND-2'\''s, and -earlier holds WAYLAND-1'\''s in the
# log before the call; every other call runs over an empty log.
stub_log="$stub_dir/hypr/stub/hyprland.log" stub_reject=""
mkdir -p "$stub_dir/hypr/stub"
: >"$stub_log"
reject_line() { echo "ERR from aquamarine ]: Output $1: pending state rejected: swapchain failed reconfiguring"; }
case "$stub_call" in
  *-unallocated) stub_reject=WAYLAND-1 ;;
  *-other) stub_reject=WAYLAND-2 ;;
  *-earlier) reject_line WAYLAND-1 >"$stub_log" ;;
esac
stub_call="${stub_call%-unallocated}" stub_call="${stub_call%-other}" stub_call="${stub_call%-earlier}"
IFS=, read -r -a stub_plan <<<"$5"
mode_hold_file="$stub_dir/monitor-hold.lua"
rt_dir="$stub_dir"
ok() { printf "ok %s\n" "$*"; }
sleep() { :; }
py_reply() { python3 -c "$@"; }
# The plan names, for each rule applied, what the monitor then reads:
# `take` is the rule'\''s own mode and scale, anything else that reading.
# The last entry stands for every later rule. Before any rule, the output reads its own mode at scale 1.
hypr() {
  local rules=0 reading rule command effective_reply="$stub_reply" separator="" commands=()
  if [[ $effective_reply == error-once ]]; then
    effective_reply=ok
    if [[ ! -e $stub_dir/error-sent && $1 == --batch ]]; then
      : >"$stub_dir/error-sent"
      effective_reply=error
    fi
  fi
  [[ -f $stub_dir/rules ]] && rules="$(wc -l <"$stub_dir/rules")"
  if [[ $1 == --batch ]]; then
    IFS=";" read -r -a commands <<<"$2"
    for command in "${commands[@]}"; do
      command="${command#"${command%%[![:space:]]*}"}"
      command="${command%"${command##*[![:space:]]}"}"
      printf "%s" "$separator"
      case "$command" in
        "reload config-only")
          if [[ $effective_reply == config-error ]]; then printf "ok"; else printf "%s" "$effective_reply"; fi
          [[ -z $stub_reject ]] || reject_line "$stub_reject" >>"$stub_log"
          [[ $effective_reply != ok ]] || tail -n 1 "$mode_hold_file" >>"$stub_dir/rules" ;;
        j/configerrors)
          if [[ $effective_reply == config-error ]]; then printf "[\"invalid rule\"]"; else printf "[]"; fi ;;
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
  case "$stub_call" in startup-*|run-base*|capture-*) reading="1250x720 scale=1" ;; esac
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
first_name() { echo WAYLAND-1; }
start_shell() {
  local reading
  reading="$(mode_scale_of WAYLAND-1)" || exit 1
  case "$stub_call" in
    capture-*)
      if [[ $shell_output_scale == 1 ]]; then [[ $reading == "1250x720 scale=1" ]];
      else [[ $reading == "2500x1440 scale=2" ]]; fi || exit 1
      [[ $mode_hold_run_base == false ]] || exit 1 ;;
    *)
      if [[ $shell_output_scale == 1 ]]; then [[ $reading == "1755x933 scale=1" ]];
      else [[ $reading == "3510x1866 scale=2" ]]; fi || exit 1
      [[ $mode_hold_run_base == true ]] || exit 1 ;;
  esac
  printf "shell-started reading=[%s]\n" "$reading"
}
startup() {
  shell_output_scale="$1"
  sandbox="$stub_dir"
  source "$stub_dir/startup.sh"
}
check_base() {
  [[ ${mode_hold[*]} == "WAYLAND-1 3510x1866 scale=2" && ${#mode_hold_parents[@]} -eq 0 && $(held_mode_state) == held ]] || failures=$((failures + 1))
  cmp -s -- "$mode_hold_file" "$stub_dir/base.lua" || failures=$((failures + 1))
}
status=0
case "$stub_call" in
  startup-1|startup-2) startup "${stub_call#startup-}" ;;
  run-base|run-base-error)
    startup 2
    cp -- "$mode_hold_file" "$stub_dir/base.lua"
    release_mode "the protected base release" WAYLAND-1 1250x720
    check_base
    hold_mode "reserved parent" WAYLAND-1 3510x1866 2 155
    cp -- "$mode_hold_file" "$stub_dir/reserved.lua"
    [[ ${#mode_hold_parents[@]} -eq 3 ]] || failures=$((failures + 1))
    if [[ $stub_call == run-base-error ]]; then stub_reply=error-once; fi
    hold_mode "nested child" WAYLAND-1 1440x900 1 40
    if [[ $stub_call != run-base-error ]]; then release_mode "nested release" WAYLAND-1 1250x720; fi
    [[ ${mode_hold[*]} == "WAYLAND-1 3510x1866 scale=2" && ${#mode_hold_parents[@]} -eq 3 && $(held_mode_state) == held ]] || failures=$((failures + 1))
    cmp -s -- "$mode_hold_file" "$stub_dir/reserved.lua" || failures=$((failures + 1))
    release_mode "reserved release" WAYLAND-1 1250x720
    check_base
    release_mode "final protected release" WAYLAND-1 1250x720
    check_base ;;
  run-base-suspend|run-base-abandon)
    # smoke_row declares the row'\''s smoke_row_abandon empty and runs it
    # only when the row ends early.
    smoke_row_abandon=()
    startup 2
    cp -- "$mode_hold_file" "$stub_dir/base.lua"
    suspend_run_base "the displays row"
    [[ ! -e $mode_hold_file && ${#mode_hold[@]} -eq 0 && $mode_hold_run_base == false ]] || failures=$((failures + 1))
    if [[ $stub_call == run-base-suspend ]]; then
      [[ ${smoke_row_abandon[*]} == "resume_run_base the displays row" ]] || failures=$((failures + 1))
      release_mode "the row release" WAYLAND-1 1755x933
      [[ ! -e $mode_hold_file && $(mode_scale_of WAYLAND-1) == "1755x933 scale=1" ]] || failures=$((failures + 1))
      resume_run_base "the displays row"
    elif [[ ${#smoke_row_abandon[@]} -gt 0 ]]; then
      "${smoke_row_abandon[@]}"
    fi
    check_base
    [[ $mode_hold_run_base == true && ${#smoke_row_abandon[@]} -eq 0 ]] || failures=$((failures + 1)) ;;
  run-base-stacked)
    smoke_row_abandon=()
    startup 2
    hold_mode "a stacked hold" WAYLAND-1 1440x900
    cp -- "$mode_hold_file" "$stub_dir/stacked.lua"
    suspend_run_base "the displays row"
    cmp -s -- "$mode_hold_file" "$stub_dir/stacked.lua" || failures=$((failures + 1))
    [[ ${mode_hold[*]} == "WAYLAND-1 1440x900 scale=1" && ${#mode_hold_parents[@]} -eq 3 && $mode_hold_run_base == true && ${#smoke_row_abandon[@]} -eq 0 ]] || failures=$((failures + 1))
    release_mode "the stacked release" WAYLAND-1 1250x720 ;;
  suspend-no-base)
    smoke_row_abandon=()
    hold_mode "a temporary hold" WAYLAND-1 3510x1866 2
    cp -- "$mode_hold_file" "$stub_dir/temporary.lua"
    suspend_run_base "the displays row"
    resume_run_base "the displays row"
    cmp -s -- "$mode_hold_file" "$stub_dir/temporary.lua" || failures=$((failures + 1))
    [[ ${mode_hold[*]} == "WAYLAND-1 3510x1866 scale=2" && $mode_hold_run_base == false && ${#smoke_row_abandon[@]} -eq 0 ]] || failures=$((failures + 1))
    release_mode "the temporary release" WAYLAND-1 1755x933 ;;
  capture-1|capture-2|capture-size-1|capture-size-2)
    # Capture has no validation size assignment. Run the same density block.
    startup "${stub_call##*-}"
    if [[ $stub_call == capture-size-* ]]; then
      main_name=WAYLAND-1 scale="$shell_output_scale" shot_size=1600x900
      source "$stub_dir/capture.sh"
      if [[ $scale == 1 ]]; then want="1600x900 scale=1"; else want="3200x1800 scale=2"; fi
      [[ $(mode_scale_of WAYLAND-1) == "$want" && ${mode_hold[1]} == "$want" && ${#mode_hold_parents[@]} -eq 0 && $mode_hold_run_base == false ]] || failures=$((failures + 1))
      release_mode "capture release" WAYLAND-1 1250x720
    elif [[ $shell_output_scale == 2 ]]; then release_mode "density release" WAYLAND-1 1250x720; fi ;;

  hold-after-behaviour)
    row_class="${stub_call#hold-after-}"
    fail "product failure"
    hold_mode "the case" WAYLAND-1 3510x1866 2 ;;
  take-missing) take_mode WAYLAND-1 3510x1866 2 || status=$? ;;
  release-only) release_mode "the release" WAYLAND-1 3510x1866 2 ;;
  hold) hold_mode "the case" WAYLAND-1 3510x1866 2 ;;
  hold-release)
    expect() { :; }
    expect_poll() { :; }
    hold_mode "the case" WAYLAND-1 3510x1866 2
    release_mode "the release" WAYLAND-1 1755x933 ;;
  nested)
    expect() { local label="$1" want="$2" got; shift 2; got="$("$@")"; [[ $got == "$want" ]] || failures=$((failures + 1)); }
    expect_poll() { expect "$@"; }
    check_hold() {
      [[ ${mode_hold[1]} == "$1" && $(held_mode_state) == held ]] || failures=$((failures + 1))
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
printf "result status=%s failures=%s held=[%s] state=%s file=%s\n" "$status" "$failures" "${mode_hold[*]:-}" "$state" "$file"
' _ "$repo" "$file" "$dir" "$reply" "$plan" "$call")" || status=$?
  got_state="$(grep -m 1 '^result ' <<<"$out")" || got_state=""
  got_rules=0; [[ -f $dir/rules ]] && got_rules="$(wc -l <"$dir/rules")"
  local want_exit=0
  case "$call" in
    startup-*|run-base*)
      if [[ $want_status != qml-smoke:* ]]; then
        [[ $out == *"logical=1755x933"*$'\n'"shell-started reading="* ]] || return 1
      else [[ $out != *shell-started* ]] || return 1; fi ;;
  esac
  if [[ $want_status == 'qml-smoke: failed='* ]]; then
    want_exit=1
    got_state="$(grep '^qml-smoke: failed=' <<<"$out")" || got_state=""
    [[ $out != *'status=not-measured'* && $out != *'result '* ]] || return 1
  elif [[ $want_status == 'qml-smoke: startup-output='* ]]; then
    want_exit=1
    got_state="$(grep '^qml-smoke: startup-output=' <<<"$out")" || got_state=""
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
# The output reads 1755x933 at scale 1 before any rule. The rows that a
# 77 from take_mode must not excuse run over the allocation failure, the
# one cause mode_unavailable excuses.
cases=(
  "a hold after a product failure that cannot take its mode fails too|hold-after-behaviour|ok|1755x933 scale=1.5|status=0 failures=2 held=[] state=none file=absent|1"
  "an allocation failure stops a hold unmeasured|hold-unallocated|ok|1755x933 scale=1.5|qml-smoke: status=not-measured nested-output=mode-unavailable output=WAYLAND-1 want=[3510x1866 scale=2] got=[1755x933 scale=1.5]|1"
  "an allocation failure preserves an earlier product failure|hold-after-behaviour-unallocated|ok|1755x933 scale=1.5|qml-smoke: failed=1|1"
  "an allocation failure logged before the hold excuses nothing|hold-earlier|ok|1755x933 scale=1.5|status=0 failures=1 held=[] state=none file=absent|1"
  "another output's allocation failure excuses nothing|hold-other|ok|1755x933 scale=1.5|status=0 failures=1 held=[] state=none file=absent|1"
  "a hold that cannot take a readable mode fails|hold|ok|1755x933 scale=1.5|status=0 failures=1 held=[] state=none file=absent|1"
  "a release that cannot take its base fails|release-only|ok|1700x900 scale=1|status=0 failures=1 held=[] state=none file=absent|1"
  "an unreadable output fails instead of being excused|hold-unallocated|ok|unreadable|status=0 failures=1 held=[] state=none file=absent|1"
  "an unreadable hold file fails before reload|take-missing|ok|take|status=1 failures=0 held=[] state=none file=absent|0"
  "configuration errors fail instead of being excused|hold-unallocated|config-error|take|status=0 failures=1 held=[] state=none file=absent|0"
  "a hold the output takes at once is held|hold|ok|take|status=0 failures=0 held=[WAYLAND-1 3510x1866 scale=2] state=held file=present|1"
  "a refused rule fails at once|hold-unallocated|error|take|status=0 failures=1 held=[] state=none file=absent|0"
  "a release ends the hold|hold-release|ok|take|status=0 failures=0 held=[] state=none file=absent|2"
  "nested holds restore each parent and its scale|nested|ok|take|status=0 failures=0 held=[] state=none file=absent|6"
  "startup takes validation mode at density 1 from the host floor|startup-1|ok|take|status=0 failures=0 held=[WAYLAND-1 1755x933 scale=1] state=held file=present|1"
  "startup takes validation mode at density 2 from the host floor|startup-2|ok|take|status=0 failures=0 held=[WAYLAND-1 3510x1866 scale=2] state=held file=present|1"
  "startup fails a readable mode it never takes before shell launch|startup-1|ok|1250x720 scale=1|qml-smoke: startup-output=WAYLAND-1 reason=hold-not-taken|1"
  "startup fails an unreadable monitor before shell launch|startup-1|ok|unreadable|qml-smoke: startup-output=WAYLAND-1 reason=hold-not-taken|1"
  "startup fails a reload error before shell launch|startup-1|error|take|qml-smoke: startup-output=WAYLAND-1 reason=hold-not-taken|0"
  "startup fails configuration errors before shell launch|startup-1|config-error|take|qml-smoke: startup-output=WAYLAND-1 reason=hold-not-taken|0"
  "run base and complete reserved parents survive nested release|run-base|ok|take|status=0 failures=0 held=[WAYLAND-1 3510x1866 scale=2] state=held file=present|7"
  "failed nested acquisition restores the reserved parent without a phantom stack entry|run-base-error|ok|take|status=0 failures=1 held=[WAYLAND-1 3510x1866 scale=2] state=held file=present|6"
  "a suspended run base leaves the configuration and comes back marked|run-base-suspend|ok|take|status=0 failures=0 held=[WAYLAND-1 3510x1866 scale=2] state=held file=present|3"
  "a row that ends early puts the suspended run base back|run-base-abandon|ok|take|status=0 failures=0 held=[WAYLAND-1 3510x1866 scale=2] state=held file=present|2"
  "a run base under a stacked hold is not suspended|run-base-stacked|ok|take|status=0 failures=1 held=[WAYLAND-1 3510x1866 scale=2] state=held file=present|3"
  "with no run base suspend and resume change nothing|suspend-no-base|ok|take|status=0 failures=0 held=[] state=none file=absent|2"
  "capture density 1 keeps the output's layout without a run base|capture-1|ok|take|status=0 failures=0 held=[] state=none file=absent|0"
  "capture density 2 releases its ordinary hold|capture-2|ok|take|status=0 failures=0 held=[] state=none file=absent|2"
  "capture explicit size at density 1 keeps ordinary release|capture-size-1|ok|take|status=0 failures=0 held=[] state=none file=absent|2"
  "capture explicit size at density 2 keeps ordinary release|capture-size-2|ok|take|status=0 failures=0 held=[] state=none file=absent|4"
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
  got="$(env -i PATH="$PATH" "$BASH" -c '
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

# Rows: label | own mode | what whole_scale_mode prints and returns.
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

# base_case FILE ROW: the base of a temporary hold comes from its matching
# outer hold, even when the live output has reset to a different scale.
base_case() {
  local label output held_output held want got status=0
  IFS='|' read -r label output held_output held want <<<"$2"
  got="$(env -i PATH="$PATH" "$BASH" -c '
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
  "release discards the protected run base|elif [[ \$mode_hold_run_base != true ]]; then|else|run base and complete reserved parents survive nested release"
  "configuration errors are accepted|[[ \$reply != '[]' ]]|[[ \$reply == never ]]|configuration errors fail instead of being excused"
  "an unreadable output is excused|[[ \$got != unreadable ]]|true|an unreadable output fails instead of being excused"
  "an unavailable mode excuses an earlier product failure|if [[ \$failures -gt 0 ]]; then|if false; then|an allocation failure preserves an earlier product failure"
  "an unavailable mode is excused without an allocation failure|  nested_output_unallocated_since \"\$1\" \"\$size\" \"\$log\" |  true |a hold that cannot take a readable mode fails"
  "mode application omits configuration reload|reload config-only ; j/configerrors|j/configerrors|a hold the output takes at once is held"
  "take_mode defers mode application until a frame|reply=\"\$(hypr_reload_errors)\"|reply=\"\$(output_mode \"\$output\" \"\$mode\" \"\$scale\")\"|a hold the output takes at once is held"
  "an unavailable mode uses a product failure|  exit 77|  return 0|an allocation failure stops a hold unmeasured"
  "an unreadable hold file is excused|if [[ ! -r \$mode_hold_file ]]; then|if false; then|an unreadable hold file fails before reload"
  "a refused reload is accepted|if reload.strip() != \"ok\":|if False:|a refused rule fails at once"
  "a failed inner hold leaves the outer mode|      taken=\"\$(take_mode \"\${mode_hold[0]}\" \"\${mode_hold[1]% scale=*}\" \"\${mode_hold[1]##*scale=}\")\"|      taken=ok|failed nested acquisition restores the reserved parent without a phantom stack entry"
  "a release drops every parent|if [[ \${#mode_hold_parents[@]} -gt 0 ]]; then|if false; then|nested holds restore each parent and its scale"
  "the fixture base ignores a matching outer hold|base_mode_scale() {|base_mode_scale() { mode_scale_of \"\$1\"; return|a reset output keeps its matching outer hold as the fixture base"
  "the fixture base takes another output's hold|\${mode_hold[0]} == \"\$1\"|true|another output's hold does not replace the fixture base"
  "whole_scale_mode takes only a scale that divides|tw=\$((w - w % s)) th=\$((h - h % s))|tw=\$((w % s ? 0 : w)) th=\$((h % s ? 0 : h))|a mode no scale divides is trimmed by the fewest pixels"
  "whole_scale_mode takes the first scale tried|trim < best_trim))|trim < -1))|a mode no scale divides is trimmed by the fewest pixels"
  "whole_scale_mode reads a mode inside other text|=~ ^([1-9][0-9]*)x([1-9][0-9]*)\$ ]]|=~ ([1-9][0-9]*)x([1-9][0-9]*) ]]|a mode with trailing text is refused"
  "whole_scale_mode keeps a side trimmed to nothing|((tw == 0 |((tw == -1 |a mode a scale trims to nothing is refused"
  "suspend_run_base registers no restore for an early end|  smoke_row_abandon=(resume_run_base \"\$1\")|  smoke_row_abandon=()|a row that ends early puts the suspended run base back"
  "resume_run_base does not mark the run base|mode_hold_run_base=true|mode_hold_run_base=false|a suspended run base leaves the configuration and comes back marked"
  "suspend_run_base leaves the hold file in place|  if ! rm -f -- \"\$mode_hold_file\"; then|  if false; then|a suspended run base leaves the configuration and comes back marked"
  "suspend_run_base takes a run base under a stacked hold|\${#mode_hold_parents[@]} -ne 0|\${#mode_hold_parents[@]} -lt 0|a run base under a stacked hold is not suspended"
  "suspend_run_base takes a temporary hold|[[ \$mode_hold_run_base == true ]]|true|with no run base suspend and resume change nothing"
)
for i in "${!controls[@]}"; do
  IFS='|' read -r label old new target <<<"${controls[i]}"
  mutant="$tmp/mutant-$i.sh"
  if ! mutate "$old" "$new" "$mutant"; then fail "control: $label"; continue; fi
  row="" runner=""
  for candidate in "${cases[@]}"; do [[ ${candidate%%|*} == "$target" ]] && row="$candidate" runner=run_case; done
  for candidate in "${scale_cases[@]}"; do [[ ${candidate%%|*} == "$target" ]] && row="$candidate" runner=scale_case; done
  for candidate in "${base_cases[@]}"; do [[ ${candidate%%|*} == "$target" ]] && row="$candidate" runner=base_case; done
  if [[ -z $row ]]; then fail "control: $label names no case: $target"; continue; fi
  if "$runner" "$mutant" "$row" >/dev/null 2>&1; then fail "control: $label left '$target' green"; else ok "control: $label"; fi
done

# Execute extracted harness and Surfaces operations. Only the compositor
# and pointer executable are stand-ins. Their file state survives the real
# helpers' command substitutions.
coordinate_case() {
  local mode_file="$1" harness_file="$2" surface_file="$3" phase action path expected_status sent skipped sampled expected_args dir out status=0
  IFS='|' read -r phase action path expected_status sent skipped sampled expected_args <<<"$4"
  dir="$(mktemp -d "$tmp/coordinate.XXXXXX")" || return 1
  python3 - "$harness_file" "$surface_file" "$dir/operations.sh" <<'PYEXTRACT' || return 1
import pathlib,sys
harness,surfaces,out=map(pathlib.Path,sys.argv[1:])
def extract(path,names):
    text=path.read_text()
    result=[]
    for name in names:
        start=text.index(name+"() {")
        line=text[start:text.index("\n",start)]
        end=start+len(line)+1 if line.endswith("}") else text.index("\n}\n",start)+3
        result.append(text[start:end])
    return result
parts=extract(harness,("coordinate_observation","pointer_dispatch","nested_input_check","click","hover","right_click","middle_click","drag","wheel","swipe","rest_pointer","point_item","click_item","expect","expect_poll","reader_stderr","smoke_poll_tries","geometry","render"))
parts+=extract(surfaces,("layout_size","layout_click","surf_menu_point","flyout_widget_x","flyout_grow_check"))
out.write_text("\n".join(parts)+"\n")
PYEXTRACT
  out="$(env -i PATH="$PATH" "$BASH" -c '
set -euo pipefail
source "$1/scripts/smoke/verdict.sh"
source "$2"
source "$3/operations.sh"
stub_dir="$3" stub_phase="$4" stub_action="$5" stub_path="$6"
sandbox="$stub_dir" mode_hold_file="$stub_dir/hold.lua"
ipc_timeout_log="$sandbox/ipc-timeout.log"
mon_w=1755 mon_h=933 screen_name=WAYLAND-1
# The nested display nested_input_check passes, so each step reaches the stub.
nested_socket=wayland-1 rt_dir="$stub_dir"
shell_env=(env -i PATH="$PATH" WAYLAND_DISPLAY="$stub_dir/wayland-1")
mode_hold=(WAYLAND-1 "3510x1866 scale=2")
mode_hold_run_base=false
smoke_poll_bound_ms=400 smoke_control_poll_bound_ms=400
pointer_at=before dependent=false continued=false
: >"$stub_dir/cleanup-owned"
ok() { :; }
sleep() { :; }
py_reply() { python3 -c "$@"; }
held_json='\''[{"name":"WAYLAND-1","width":3510,"height":1866,"scale":2,"x":0,"y":0},{"name":"FAR","width":800,"height":600,"scale":1,"x":1755,"y":0}]'\''
reset_json='\''[{"name":"WAYLAND-1","width":1250,"height":720,"scale":1,"x":0,"y":0}]'\''
printf "%s\n" "$held_json" >"$stub_dir/monitors"
[[ $stub_phase != reset-first ]] || printf "%s\n" "$reset_json" >"$stub_dir/monitors"
monitor_rule WAYLAND-1 3510x1866 2 >"$mode_hold_file"
# A pointer step reloads nothing; a reload is counted for the rows.
hypr() {
  if [[ $1 == --batch ]]; then
    echo reload >>"$stub_dir/reloads"
    printf "ok\n\n\n[]\n"
  else cat "$stub_dir/monitors"; fi
}
# Record attempted delivery even when the executable returns an error.
cat >"$sandbox/click" <<'\''POINTER'\''
#!/usr/bin/env bash
printf "%s\n" "$*" >>"${0%/*}/sent"
[[ ! -e ${0%/*}/helper-error ]] || exit 1
[[ ! -e ${0%/*}/helper-unavailable ]] || exit 77
POINTER
chmod +x "$sandbox/click"
[[ $stub_phase != helper-error ]] || : >"$stub_dir/helper-error"
[[ $stub_phase != helper-unavailable ]] || : >"$stub_dir/helper-unavailable"
control_box() { echo "[100, 200, 2, 4]"; }
control_hovered() { echo true; }
ipc() {
  case "$*" in
    *acme.surfaces-tail*grow*) : >"$stub_dir/grown"; echo grown ;;
    *geometry*)
      mode_scale_of WAYLAND-1 >"$stub_dir/sample" || return 1
      if [[ -e $stub_dir/grown ]]; then echo "[0, 200, 2, 4]"; else echo "[100, 200, 2, 4]"; fi ;;
    *) echo 1 ;;
  esac
}
# The no-commit fixture leaves a marker behind. Its intended failure must
# not gain a position failure.
popup_marker_follows() { echo left-behind; }
flyout_rest_x=900
deliver() {
  case "$stub_action" in
    drag) drag "$sample_x" "$sample_y" 301 302 ;;
    wheel|swipe) "$stub_action" "$sample_x" "$sample_y" 3 ;;
    click_item) click_item bar id Control text ;;
    *) "$stub_action" "$sample_x" "$sample_y" ;;
  esac || return $?
  echo delivered
}
observe() {
  local point sample_x sample_y
  point="$(surf_menu_point)" || return $?
  read -r sample_x sample_y <<<"$point" || return 1
  case "$stub_phase" in
    reset) printf "%s\n" "$reset_json" >"$stub_dir/monitors" ;;
    reset-unreadable) echo "[]" >"$stub_dir/monitors" ;;
  esac
  case "$stub_path" in
    expect) expect delivery delivered deliver || return $? ;;
    poll) expect_poll delivery delivered deliver || return $? ;;
    substitution) local result; result="$(deliver)" || return $?; [[ $result == delivered ]] || return 1 ;;
    chain) deliver >/dev/null && : || return $? ;;
    *) deliver >/dev/null || return $? ;;
  esac
  dependent=true
}
reloads=0
# The unscoped path runs click_item outside every coordinate_observation.
# Its row pins the status, the clicks sent, the reloads and the refused
# steps on stderr.
if [[ $stub_path == unscoped ]]; then
  status=0 clicks=0
  click_item bar id Control text 2>"$stub_dir/stderr" || status=$?
  cat -- "$stub_dir/stderr" >&2
  [[ ! -e $stub_dir/sent ]] || clicks="$(grep -c -x -E "[0-9]+ [0-9]+ 1755 933" -- "$stub_dir/sent" || :)"
  [[ ! -e $stub_dir/reloads ]] || reloads="$(wc -l <"$stub_dir/reloads")"
  refused="$(grep -c -x -E "coordinate-mode: reset output=WAYLAND-1 want=\[3510x1866 scale=2\] pointer-step=refused" -- "$stub_dir/stderr" || :)"
  got="status=$status clicks=$clicks reloads=$reloads refused=$refused"
  [[ $got == "status=$7 clicks=$8 reloads=0 refused=$9" ]] || { echo "got $got"; exit 1; }
  exit 0
fi
coordinate_observation coordinates observe 2>"$stub_dir/stderr" && continued=true || exit 1
cat -- "$stub_dir/stderr" >&2
# A step refused under a reset says so on stderr, once; every other
# refusal says nothing of a reset.
refusals="$(grep -c -E "^coordinate-mode: reset output=WAYLAND-1 want=\[3510x1866 scale=2\] " -- "$stub_dir/stderr" || :)"
if [[ $stub_phase == reset ]]; then [[ $refusals == 1 ]]; else [[ $refusals == 0 ]]; fi || exit 1
rm -- "${stub_dir:?}/cleanup-owned"
[[ $continued == true && ${coordinate_scope:-false} == false && ! -e $stub_dir/cleanup-owned && ! -e $stub_dir/reloads ]] || exit 1
sampled=0 sent=0 skipped=${#not_measured_rows[@]} status=0
if [[ -e $stub_dir/sample ]]; then
  sampled=1
  [[ $(cat "$stub_dir/sample") == "3510x1866 scale=2" ]] || exit 1
fi
if [[ -e $stub_dir/sent ]]; then sent="$(wc -l <"$stub_dir/sent")"; fi
[[ $sent == "$8" && $skipped == "$9" && $sampled == "${10}" ]] || exit 1
[[ -z ${11} || $(cat "$stub_dir/sent") == "${11}" ]] || exit 1
if [[ $stub_action == flyout_grow_check ]]; then
  [[ $dependent == true && $failures == 1 && $behaviour_failures == 1 && $pointer_at == before && -e $stub_dir/grown ]] || exit 1
elif [[ $7 == 0 ]]; then
  [[ $dependent == true && $failures == 0 && $pointer_at != before ]] || exit 1
  if [[ $stub_action == layout_click ]]; then
    [[ $(cat "$stub_dir/sent") == "101 202 2555 933" && $pointer_at == "101 202" ]] || exit 1
  fi
else
  [[ $dependent == false && $pointer_at == before && $failures == 1 && $behaviour_failures == 1 ]] || exit 1
fi
smoke_verdict "$failures" "$behaviour_failures" /dev/null || status=$?
[[ $status == "$7" ]]
' _ "$repo" "$mode_file" "$dir" "$phase" "$action" "$path" "$expected_status" "$sent" "$skipped" "$sampled" "$expected_args" 2>&1)" || status=$?
  if [[ $status == 0 ]]; then return 0; fi
  printf '        coordinate %s: %s\n' "$4" "$out"
  return 1
}
# One table covers each mode state, action and shell status path. Rows:
# phase | action | path | verdict status | steps sent | rows not measured
# | whether the box was sampled under the hold | the arguments sent.
coordinate_cases=(
  'held|click|direct|0|1|0|1|101 202 1755 933'
  'held|hover|direct|0|1|0|1|101 202 1755 933 move'
  'held|right_click|direct|0|1|0|1|101 202 1755 933 right'
  'held|middle_click|direct|0|1|0|1|101 202 1755 933 middle'
  'held|drag|direct|0|1|0|1|101 202 1755 933 drag 301 302'
  'held|wheel|direct|0|1|0|1|101 202 1755 933 wheel 3'
  'held|swipe|direct|0|1|0|1|101 202 1755 933 swipe 3'
  'held|layout_click|direct|0|1|0|1|101 202 2555 933'
  'held|flyout_grow_check|direct|1|0|0|1'
  'helper-error|click|direct|1|1|0|1'
  'helper-unavailable|click|direct|1|1|0|1'
  'helper-error|click|expect|1|1|0|1'
  'helper-error|click|poll|1|1|0|1'
  'reset-unreadable|click|direct|1|0|0|1'
  'reset|click|direct|1|0|0|1'
  'reset|hover|direct|1|0|0|1'
  'reset|right_click|direct|1|0|0|1'
  'reset|middle_click|direct|1|0|0|1'
  'reset|drag|direct|1|0|0|1'
  'reset|wheel|direct|1|0|0|1'
  'reset|swipe|direct|1|0|0|1'
  'reset|layout_click|direct|1|0|0|1'
  'reset|click|expect|1|0|0|1'
  'reset|click|poll|1|0|0|1'
  'reset|click|substitution|1|0|0|1'
  'reset|click|chain|1|0|0|1'
  'reset|click_item|expect|1|0|0|1'
)
for row in "${coordinate_cases[@]}"; do
  if coordinate_case "$subject" "$repo/scripts/smoke/harness.sh" "$repo/scripts/smoke/rows/surfaces.sh" "$row"; then ok "coordinate $row"; else fail "coordinate $row"; fi
done
# point_item outside a coordinate_observation. Rows: phase | click_item |
# unscoped | status | clicks sent | refused lines. A held output takes one
# click; an output that left the hold before the first step takes none,
# and the refused step returns 1 with no reload.
unscoped_cases=(
  'held|click_item|unscoped|0|1|0'
  'reset-first|click_item|unscoped|1|0|1'
)
for row in "${unscoped_cases[@]}"; do
  if coordinate_case "$subject" "$repo/scripts/smoke/harness.sh" "$repo/scripts/smoke/rows/surfaces.sh" "$row"; then ok "unscoped $row"; else fail "unscoped $row"; fi
done
# Keep delivery intact while removing the final mode check in scratch.
python3 - "$repo/scripts/smoke/harness.sh" "$tmp/unguarded-harness.sh" <<'PYMUTATE'
import pathlib,sys
source,out=map(pathlib.Path,sys.argv[1:])
text=source.read_text()
old='  coordinate_mode_check || return 1\n'
assert text.count(old)==1
changed=text.replace(old,'')
assert changed!=text and '"$sandbox/click" "$@"' in changed
out.write_text(changed)
PYMUTATE
if coordinate_case "$subject" "$tmp/unguarded-harness.sh" "$repo/scripts/smoke/rows/surfaces.sh" 'reset|click|direct|1|0|0|1' >/dev/null; then
  fail 'control: removing the final mode check permits a forbidden action'
else
  ok 'control: removing the final mode check permits a forbidden action'
fi
# Keep the refusal itself while removing only its stderr reason in scratch.
python3 - "$subject" "$tmp/silent-hold.sh" <<'PYMUTATE'
import pathlib,sys
source,out=map(pathlib.Path,sys.argv[1:])
text=source.read_text()
old="    reset) printf 'coordinate-mode: reset "
assert text.count(old)==1
changed=text.replace(old,"    reset) : printf 'coordinate-mode: reset ")
assert changed!=text
out.write_text(changed)
PYMUTATE
if coordinate_case "$tmp/silent-hold.sh" "$repo/scripts/smoke/harness.sh" "$repo/scripts/smoke/rows/surfaces.sh" 'reset|click|direct|1|0|0|1' >/dev/null; then
  fail 'control: a reset refusal with no stderr reason'
else
  ok 'control: a reset refusal with no stderr reason'
fi

if [[ $failures -gt 0 ]]; then
  echo "test-mode-hold: failed=$failures"
  exit 1
fi
echo "test-mode-hold: ok"
