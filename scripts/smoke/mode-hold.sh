# Sourced by harness.sh after verdict.sh; the mode and scale a row holds on
# a nested output. It reads the nested compositor through hypr, which
# harness.sh defines, and writes mode_hold, mode_hold_window and
# mode_hold_file, which verdict.sh and harness.sh declare. release_mode
# reports through expect and expect_poll, and hold_mode through ok and
# fail.

# monitor_rule NAME MODE [SCALE]: the Lua monitor rule that gives output
# NAME the mode MODE, such as 480x720, at SCALE, 1 by default, and the
# layout's origin. The nested Wayland output takes any mode and an integer
# scale; a headless output stays 0x0 in the sandbox.
monitor_rule() { printf 'hl.monitor({ output = "%s", mode = "%s", position = "0x0", scale = %s })\n' "$1" "$2" "${3:-1}"; }
# output_mode NAME MODE [SCALE]: the nested compositor applies
# monitor_rule's rule now through `hyprctl eval`; the reply is hyprctl's.
# A configuration reload drops the rule but leaves the output at its mode
# and scale, unless a rule the configuration loads gives the output
# another. Under a hold it stands for a reset, and a reload applies the held rule again
# from mode_hold_file. A row restores the mode it read first.
output_mode() { hypr eval "$(monitor_rule "$@")"; }
# mode_scale_of NAME: output NAME's mode and scale as `WxH scale=S`, such
# as `3510x1866 scale=2`, the mode in device pixels; returns 1 when no
# monitor has that name.
mode_scale_of() { hypr -j monitors | python3 -c 'import json,sys; m=[m for m in json.load(sys.stdin) if m["name"]==sys.argv[1]]; print("%dx%d scale=%g" % (m[0]["width"], m[0]["height"], m[0]["scale"])) if len(m)==1 else sys.exit(1)' "$1"; }
# base_mode_scale NAME: the mode and scale a temporary hold restores.
# A matching outer hold owns that state even after a host configure resets
# the output. With no matching hold, the output's current state owns it.
base_mode_scale() {
  if [[ ${#mode_hold[@]} -gt 0 && ${mode_hold[0]} == "$1" ]]; then
    printf '%s\n' "${mode_hold[1]}"
  else
    mode_scale_of "$1"
  fi
}
# whole_scale_mode MODE: the mode and scale, as `WxH S`, that a hold above
# scale 1 takes on an output whose own mode at scale 1 is MODE, such as
# 1755x933. S is the scale from 2 to 4 that removes the fewest device
# pixels when each side is trimmed to a multiple of it, the smaller scale
# on a tie, so the held mode divides into whole logical pixels at S. A
# mode some scale divides is kept whole: a hold at the window's own mode
# survives a host configure of the same size. The host window rule sizes
# the nested window, and it can leave no divisor, as 1756x933 does (933 is
# 3 x 311, 1756 is 4 x 439); the trimmed mode differs from the window by
# fewer than S pixels per side, so a host configure resets it and
# held_mode_state reads `reset`, which the verdict counts as a mode reset,
# not measured. Prints `whole-scale-mode: refused mode=[<MODE>]` and
# returns 1 for a MODE that is not two positive integers joined by `x`, or
# one a scale trims to nothing.
whole_scale_mode() {
  local w h s tw th trim best="" best_trim=-1
  if [[ $1 =~ ^([1-9][0-9]*)x([1-9][0-9]*)$ ]]; then
    w="${BASH_REMATCH[1]}" h="${BASH_REMATCH[2]}"
    for s in 2 3 4; do
      tw=$((w - w % s)) th=$((h - h % s))
      if ((tw == 0 || th == 0)); then best=""; break; fi
      trim=$((w * h - tw * th))
      if ((best_trim < 0 || trim < best_trim)); then best="${tw}x$th $s" best_trim=$trim; fi
    done
  fi
  if [[ -z $best ]]; then
    printf 'whole-scale-mode: refused mode=[%s]\n' "$1"
    return 1
  fi
  echo "$best"
}
# Reload the nested Hyprland and read its configuration errors in the same
# batch request, printed as a JSON list. Hyprland v0.56.2 empties the list
# on every `hyprctl eval` (CConfigManager::eval) and the shell evals after
# each reload, so a configerrors request of its own can read [] while the
# configuration holds errors. A reload that does not answer ok prints its
# answer and fails.
hypr_reload_errors() {
  hypr --batch 'reload config-only ; j/configerrors' | py_reply '
import json, sys
reload, errors = sys.stdin.read().split("\n\n\n")
if reload.strip() != "ok":
    print("reload answered " + json.dumps(reload.strip()))
    sys.exit(1)
print(json.dumps([e for e in json.loads(errors) if e]))'
}

# mode_attempts: how many times take_mode reloads one held rule. A host
# configure of the nested window that arrives after the rule gives the
# output the host window's size again (held_mode_state), so a rule that
# took can read as another mode. The bound stops the retries when the
# host keeps configuring the window.
mode_attempts=3
mode_hold_parents=()
# take_mode NAME MODE SCALE: output NAME takes the rule already written
# to mode_hold_file. A config-only reload applies monitor rules directly.
# hl.monitor through eval only schedules their application on render.preChecks
# (CMonitorRuleManager, Hyprland v0.56.2); an output without frame callbacks
# can acknowledge eval yet never apply the rule. Then mode_scale_of reads
# the output every 200 ms for
# up to 5 s; an output that never reads `MODE scale=SCALE` gets the rule
# again, up to mode_attempts times. Prints `attempts=<n> got=[<reading>]`,
# the last reading `unreadable` when the monitor cannot be read, and
# returns 0 when the output reads the mode and scale, 77 when a readable
# output never takes it, and 1 when the rule file, reload or read fails.
# A reload hyprctl does not answer `ok` prints its reply and returns 1.
take_mode() {
  local output="$1" mode="$2" scale="$3" attempt reply got=""
  if [[ ! -r $mode_hold_file ]]; then
    printf 'reason=hold-file-unreadable path=%s\n' "$mode_hold_file"
    return 1
  fi
  for ((attempt = 1; attempt <= mode_attempts; attempt++)); do
    if ! reply="$(hypr_reload_errors)" || [[ $reply != '[]' ]]; then
      printf 'attempts=%s reload=[%s]\n' "$attempt" "$reply"
      return 1
    fi
    for _ in $(seq 1 25); do
      got="$(mode_scale_of "$output")" || got=unreadable
      if [[ $got == "$mode scale=$scale" ]]; then
        printf 'attempts=%s got=[%s]\n' "$attempt" "$got"
        return 0
      fi
      sleep 0.2
    done
  done
  printf 'attempts=%s got=[%s]\n' "$mode_attempts" "$got"
  [[ $got != unreadable ]] || return 1
  return 77
}
# mode_unavailable OUTPUT WANT READING: stop before a product check uses
# geometry from a readable output that could not take its requested mode.
# scripts/main-run.sh consumes status=not-measured; no new FAIL line is
# emitted. Earlier failures keep the closing verdict's classification.
mode_unavailable() {
  if [[ $failures -gt 0 ]]; then
    printf 'qml-smoke: nested-output=mode-unavailable output=%s want=[%s] %s\n' "$1" "$2" "$3"
    smoke_verdict "$failures" "$behaviour_failures" "$stalled_render" "$mode_resets" "$rt_dir"/hypr/*/hyprland.log || exit $?
  fi
  printf 'qml-smoke: status=not-measured nested-output=mode-unavailable output=%s want=[%s] %s\n' "$1" "$2" "$3"
  exit 77
}
# hold_mode LABEL NAME MODE [SCALE]: output NAME takes MODE at SCALE, 1 by
# default, until release_mode restores the previous hold, or the caller's
# mode when no outer hold exists. The first hold's WxH is kept as the
# host window's size (mode_hold_window) once the hold begins. The rule
# goes into mode_hold_file, which every load of the configuration runs,
# and take_mode reloads it now. The hold begins once the monitor reads
# both. A readable output that never takes the mode stops the run as
# not measured before any product fit check runs.
hold_mode() {
  local label="$1" output="$2" want="$3 scale=${4:-1}" taken window previous_rule="" status=0
  local row_class=hold
  if [[ ${#mode_hold[@]} -gt 0 ]]; then
    previous_rule="$(cat -- "$mode_hold_file")" || { fail "$label: the held rule is unreadable"; return 0; }
    mode_hold_parents+=("${mode_hold[0]}" "${mode_hold[1]}" "$mode_hold_window" "$previous_rule")
  fi
  if window="$(mode_scale_of "$output")"; then window="${window% scale=*}"; else window=""; fi
  if [[ ${#mode_hold[@]} -gt 0 && $output == "${mode_hold[0]}" ]]; then window="$mode_hold_window"; fi
  if ! { [[ -z $previous_rule ]] || printf '%s\n' "$previous_rule"; monitor_rule "$output" "$3" "${4:-1}"; } >"$mode_hold_file.next" || ! mv -T -- "$mode_hold_file.next" "$mode_hold_file"; then
    fail "$label: the hold file $mode_hold_file is not written"
    rm -f -- "$mode_hold_file.next" || fail "$label: the partial hold file $mode_hold_file.next is not removed"
    return 0
  fi
  if taken="$(take_mode "$output" "$3" "${4:-1}")"; then
    mode_hold=("$output" "$want")
    mode_hold_window="$window"
    ok "$label: $output reads $want, $taken"
  else
    status=$?
    [[ $status != 77 ]] || mode_unavailable "$output" "$want" "$taken"
    fail "$label: $output does not read $want: $taken"
    if [[ -n $previous_rule ]]; then
      printf '%s\n' "$previous_rule" >"$mode_hold_file" || fail "$label: the outer hold file is not restored"
      hold_restore || fail "$label: the outer hold is not restored"
    else
      rm -f -- "$mode_hold_file" || fail "$label: the hold file $mode_hold_file of a hold never taken is not removed"
    fi
  fi
  return 0
}
# hold_restore: the held mode and scale again, after held_mode_state read
# a reset, through take_mode with the held rule. Returns 0 once the
# output reads them. Otherwise prints `hold-restore: not-held
# output=<name> want=[<state>] <take_mode's reading>`, or
# `hold-restore: refused hold=none` when no row holds a mode, and returns
# 1. It writes no hold file: the file already holds the rule.
hold_restore() {
  local taken
  if [[ ${#mode_hold[@]} -eq 0 ]]; then
    echo 'hold-restore: refused hold=none'
    return 1
  fi
  if ! taken="$(take_mode "${mode_hold[0]}" "${mode_hold[1]% scale=*}" "${mode_hold[1]##*scale=}")"; then
    printf 'hold-restore: not-held output=%s want=[%s] %s\n' "${mode_hold[0]}" "${mode_hold[1]}" "$taken"
    return 1
  fi
}
# held_mode_state: what became of the held mode, as one word. `held`: the
# output reads its mode and scale. `reset`: the output reads another mode
# or another scale. Once the hold began, the host moves a nested output
# off it, and that is not what a held row measures. Aquamarine's Wayland
# backend turns every xdg_toplevel configure the host sends the nested
# window into a state event with the configure's size
# (CWaylandOutput::CWaylandOutput in src/backend/Wayland.cpp, aquamarine
# v0.15.1), and the host sends one whenever it resizes the window or
# changes its state, focus and tiling included. For a Wayland-backend
# output, Hyprland's state listener applies the active rule again with
# that size in place of the rule's mode, unless the two are equal
# (CMonitor::onConnect in src/output/Monitor.cpp, Hyprland v0.56.2). The
# rule keeps its scale, and CMonitor::applyMonitorRule moves a scale that
# leaves fractional logical pixels to the nearest one that does not: a
# 1755x933 window under a 3510x1866 hold at scale 2 reads 1755x933 at
# scale 1.5. A hold at the window's own size survives a configure of the
# same size and no resize. Each applied rule, the host's size included,
# becomes the active rule (CMonitor::applyMonitorRuleSoft, same file), so
# after a resize away a configure back to the window's own size differs
# from the active rule and gives the output that size again: a scale-1
# hold at the window's own size comes back without its rule, and a
# reading after both configures reads `held`. No host configure equals a
# doubled mode, so a scale-2 hold comes back only through its rule
# applied again (hold_restore), or a configuration reload, which the
# shell runs when its Hyprland layer changes: a reload drops every rule
# `hyprctl eval` added (src/config/lua/ConfigManager.cpp,
# CConfigManager::reload, v0.56.2) and applies the rule mode_hold_file
# names again. The shell writes no monitor rule of its own.
# `unreadable`: the monitor cannot be read, which excuses nothing.
held_mode_state() {
  local state
  state="$(mode_scale_of "${mode_hold[0]}")" || { echo unreadable; return; }
  if [[ $state == "${mode_hold[1]}" ]]; then echo held; else echo reset; fi
}
# held_mode_host_sized: true when the held output reads the host window's
# own WxH, mode_hold_window, and the held mode is another WxH. The output
# read the held mode once the hold began, so a host configure moved it
# back to the window's size (held_mode_state), and a reading then
# measured the sandbox, not the hold or the shell. False when the monitor
# cannot be read; an empty mode_hold_window, a size hold_mode could not
# read, equals no reading mode_scale_of prints.
held_mode_host_sized() {
  local state
  [[ $mode_hold_window != "${mode_hold[1]% scale=*}" ]] || return 1
  state="$(mode_scale_of "${mode_hold[0]}")" || return 1
  [[ ${state% scale=*} == "$mode_hold_window" ]]
}
# release_mode LABEL NAME MODE [SCALE]: end the inner hold and restore its
# parent's rule, mode and scale. Without a parent, remove the hold file and
# give NAME the caller's MODE at SCALE, 1 by default. Read both before the
# rows go on, whether or not the inner hold took.
release_mode() {
  local taken status=0
  if [[ ${#mode_hold_parents[@]} -gt 0 ]]; then
    local top=$((${#mode_hold_parents[@]} - 4))
    mode_hold=("${mode_hold_parents[top]}" "${mode_hold_parents[top + 1]}")
    mode_hold_window="${mode_hold_parents[top + 2]}"
    printf '%s\n' "${mode_hold_parents[top + 3]}" >"$mode_hold_file" || fail "$1: the outer hold file is not restored"
    mode_hold_parents=("${mode_hold_parents[@]:0:top}")
  else
    mode_hold=()
    mode_hold_window=""
    # A reload needs the base rule even without frame callbacks. Remove
    # it once the base takes, leaving no outer hold.
    if ! monitor_rule "$2" "$3" "${4:-1}" >"$mode_hold_file.next" || ! mv -T -- "$mode_hold_file.next" "$mode_hold_file"; then
      fail "$1: the restore rule is not written"
      rm -f -- "$mode_hold_file.next" || fail "$1: the partial restore rule is not removed"
      return 0
    fi
  fi
  local output="${mode_hold[0]:-$2}" want="${mode_hold[1]:-$3 scale=${4:-1}}"
  if taken="$(take_mode "$output" "${want% scale=*}" "${want##*scale=}")"; then
    ok "$1: $output reads $want, $taken"
  else
    status=$?
    [[ $status != 77 ]] || mode_unavailable "$output" "$want" "$taken"
    fail "$1: $output does not read $want: $taken"
  fi
  if ((${#mode_hold[@]} == 0)); then
    rm -f -- "$mode_hold_file" || fail "$1: the hold file $mode_hold_file is not removed"
  fi
  return 0
}
