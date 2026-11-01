# Sourced by harness.sh after verdict.sh; the mode and scale a row holds on
# a nested output. It reads the nested compositor through hypr, which
# harness.sh defines, and writes mode_hold and mode_hold_file, which
# verdict.sh and harness.sh declare. release_mode
# reports through expect and expect_poll, and hold_mode through ok and
# fail. suspend_run_base and resume_run_base also write
# mode_hold_run_base and the smoke_row_abandon of the row that calls them,
# a local of smoke_row in harness.sh.

# create_output NAME: add a usable output to the nested sink and return
# only once it has a sized mode. Headless outputs on cachy's NVIDIA stack
# reject buffer allocation and stay 0x0. A layer reload in Hyprland
# 0.57.0 then reaches CPropRefresher::refreshProp's REFRESH_BLUR_FB loop,
# CMonitor::resources and CMonitorResources::initFB; the allocation hits
# src/render/Framebuffer.cpp:10's positive-size assertion (VGS-2133's
# unchanged-main displays-modes run, 2026-10-31). A Wayland configure can
# precede aquamarine 0.15.1's newOutput announcement, leaving Hyprland no
# preferred mode (the compositor-reveal run in VGS-2133). Install an
# explicit mode copied from the sized primary before creating the output;
# Wayland accepts that custom mode, as the run-base hold does. New fixture
# outputs stand auto-right at scale 1. Read up to 25 times, 0.2 s between
# readings, as take_mode does; each IPC keeps hypr's bound. The row removes its
# output; the harness owns the whole compositor.
create_output() {
  local output="$1" reply mode got=unreadable status=0
  got="$(mode_scale_of "$output" all)" || :
  if [[ $got != absent ]]; then
    printf 'output-create: operation=acquire output=%s state=[%s]\n' "$output" "$got" >&2
    return 1
  fi
  mode="$(first_mode)" || return
  reply="$(hypr eval "$(monitor_rule "$output" "$mode" 1 "" auto-right)")" || status=$?
  if [[ $status != 0 || $reply != ok ]]; then
    printf 'output-create: operation=rule status=%s output=%s reply=[%s]\n' "$status" "$output" "$reply" >&2
    [[ $status == 0 ]] || return "$status"
    return 1
  fi
  reply="$(hypr output create wayland "$output")" || status=$?
  if [[ $status != 0 || $reply != ok ]]; then
    printf 'output-create: operation=create status=%s output=%s reply=[%s]\n' "$status" "$output" "$reply" >&2
    [[ $status == 0 ]] || return "$status"
    return 1
  fi
  for _ in $(seq 1 25); do
    got="$(mode_scale_of "$output")" || :
    [[ -n $got ]] || got=unreadable
    if [[ $got =~ ^[1-9][0-9]*x[1-9][0-9]*\ scale= ]]; then
      echo ok
      return 0
    fi
    sleep 0.2
  done
  printf 'output-create: output=%s state=[%s]\n' "$output" "$got" >&2
  # Fixture names have one creator in this private world. The checked absent name
  # and accepted creation own this output; a refusal above owns nothing.
  # hyprctl can answer normally while this read is unreadable or the
  # backend's accepted removal leaves it listed, so transport timeout
  # handling alone cannot make the next layer reload safe.
  if ! create_output_remove "$output"; then
    smoke_abort "output-create: cleanup=unproved output=$output"
  fi
  return 1
}

# The failed acquisition's release phase. Never called for a refused name.
create_output_remove() {
  local output="$1" reply got status=0
  reply="$(hypr output remove "$output")" || status=$?
  if [[ $status != 0 || $reply != ok ]]; then
    printf 'output-create: operation=remove status=%s output=%s reply=[%s]\n' "$status" "$output" "$reply" >&2
    return 1
  fi
  for _ in $(seq 1 25); do
    status=0
    got="$(mode_scale_of "$output" all)" || status=$?
    [[ $status != 0 && $got == absent ]] && return 0
    if [[ $status != 0 ]]; then
      printf 'output-create: operation=release-read output=%s state=[%s]\n' "$output" "$got" >&2
      return 1
    fi
    sleep 0.2
  done
  printf 'output-create: operation=release output=%s state=[%s]\n' "$output" "$got" >&2
  return 1
}

# monitor_rule NAME MODE [SCALE [RIGHT [POSITION]]]: give output NAME the
# mode MODE, such as 480x720, at SCALE, 1 by default, and POSITION, the
# layout's origin by default, with RIGHT logical pixels reserved on its
# right edge when given. Layer surfaces are arranged inside the output less its
# reserved area (arrangeLayersForMonitor, Hyprland v0.56.2), so a bar
# anchored left and right draws RIGHT narrower at the output's own mode.
# The nested Wayland output takes any mode and an integer scale; a
# headless output stays 0x0 in the sandbox.
monitor_rule() {
  local reserved=""
  [[ -z ${4:-} ]] || reserved=", reserved = { right = $4 }"
  printf 'hl.monitor({ output = "%s", mode = "%s", position = "%s", scale = %s%s })\n' "$1" "$2" "${5:-0x0}" "${3:-1}" "$reserved"
}
# output_mode NAME MODE [SCALE]: the nested compositor applies
# monitor_rule's rule now through `hyprctl eval`; the reply is hyprctl's.
# A configuration reload drops the rule but leaves the output at its mode
# and scale, unless a rule the configuration loads gives the output
# another. Under a hold a reload applies the held rule again from
# mode_hold_file. A row restores the mode it read first.
output_mode() { hypr eval "$(monitor_rule "$@")"; }
# mode_scale_of NAME [all]: output NAME's mode and scale as `WxH scale=S`, such
# as `3510x1866 scale=2`, the mode in device pixels; returns 1 with
# `absent` for no match or `ambiguous` for more than one. `all` includes
# disabled outputs when acquisition or release must judge ownership.
mode_scale_of() {
  local scope=()
  [[ ${2:-} != all ]] || scope=(all)
  hypr -j monitors "${scope[@]}" | python3 -c 'import json,sys; m=[m for m in json.load(sys.stdin) if m["name"]==sys.argv[1]]
if len(m)!=1: print("absent" if not m else "ambiguous"); sys.exit(1)
print("%dx%d scale=%g" % (m[0]["width"], m[0]["height"], m[0]["scale"]))' "$1"
}
# base_mode_scale NAME: the mode and scale a temporary hold restores.
# A matching outer hold owns that state. With no matching hold, the
# output's current state owns it.
base_mode_scale() {
  if [[ ${#mode_hold[@]} -gt 0 && ${mode_hold[0]} == "$1" ]]; then
    printf '%s\n' "${mode_hold[1]}"
  else
    mode_scale_of "$1"
  fi
}
# whole_scale_mode MODE: the mode and scale, as `WxH S`, that a hold above
# scale 1 takes on an output whose own mode at scale 1 is MODE, such as
# 1920x1080. S is the scale from 2 to 4 that removes the fewest device
# pixels when each side is trimmed to a multiple of it, the smaller scale
# on a tie, so the held mode divides into whole logical pixels at S. A
# mode some scale divides is kept whole; one no scale divides, as 1756x933
# (933 is 3 x 311, 1756 is 4 x 439), is trimmed by fewer than S pixels per
# side. Prints `whole-scale-mode: refused mode=[<MODE>]` and returns 1 for
# a MODE that is not two positive integers joined by `x`, or one a scale
# trims to nothing.
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

# take_mode NAME MODE SCALE: output NAME takes the rule already written
# to mode_hold_file. A config-only reload applies monitor rules directly.
# hl.monitor through eval only schedules their application on render.preChecks
# (CMonitorRuleManager, Hyprland v0.56.2), so the hold reloads instead.
# Then mode_scale_of reads the output every 200 ms for up to 5 s. Prints
# `got=[<reading>]`, the last reading `unreadable` when the monitor cannot
# be read, and returns 0 when the output reads `MODE scale=SCALE`, 77 when
# a readable output never takes it, which mode_unavailable judges, and 1
# when the rule file, reload or read fails. A reload hyprctl does not
# answer `ok` prints its reply and returns 1.
take_mode() {
  local output="$1" mode="$2" scale="$3" reply got=""
  if [[ ! -r $mode_hold_file ]]; then
    printf 'reason=hold-file-unreadable path=%s\n' "$mode_hold_file"
    return 1
  fi
  if ! reply="$(hypr_reload_errors)" || [[ $reply != '[]' ]]; then
    printf 'reload=[%s]\n' "$reply"
    return 1
  fi
  for _ in $(seq 1 25); do
    got="$(mode_scale_of "$output")" || got=unreadable
    if [[ $got == "$mode scale=$scale" ]]; then
      printf 'got=[%s]\n' "$got"
      return 0
    fi
    sleep 0.2
  done
  printf 'got=[%s]\n' "$got"
  [[ $got != unreadable ]] || return 1
  return 77
}
# mode_log_mark: the nested compositor's log as `SIZE PATH`, its size now,
# or `0 none` before the compositor wrote one; a hold reads it before its
# take_mode, so mode_unavailable reads only what that take_mode logged.
mode_log_mark() {
  local log
  for log in "$rt_dir"/hypr/*/hyprland.log; do
    [[ -f $log ]] || continue
    printf '%s %s\n' "$(stat -c %s -- "$log")" "$log"
    return
  done
  echo "0 none"
}
# mode_unavailable OUTPUT WANT READING MARK: a readable output that did not
# take its requested mode, MARK being mode_log_mark's reading before its
# take_mode. The one sandbox cause left is OUTPUT itself rejecting a state
# because it could not allocate its buffers, logged after MARK
# (nested_output_unallocated_since): the run then
# stops before a product check uses its geometry, as not measured, which
# scripts/main-run.sh consumes; earlier failures keep the closing
# verdict's classification. Any other cause is the hold's own defect, so
# it returns and its caller fails the hold.
mode_unavailable() {
  local size log
  read -r size log <<<"$4"
  nested_output_unallocated_since "$1" "$size" "$log" || return 0
  if [[ $failures -gt 0 ]]; then
    printf 'qml-smoke: nested-output=mode-unavailable output=%s want=[%s] %s\n' "$1" "$2" "$3"
    smoke_verdict "$failures" "$behaviour_failures" "$rt_dir"/hypr/*/hyprland.log || exit $?
  fi
  printf 'qml-smoke: status=not-measured nested-output=mode-unavailable output=%s want=[%s] %s\n' "$1" "$2" "$3"
  exit 77
}
# hold_mode LABEL NAME MODE [SCALE [RIGHT]]: output NAME takes MODE at
# SCALE, 1 by default, with RIGHT logical pixels reserved on its right
# edge when given (monitor_rule), until release_mode restores the previous
# hold, or the caller's mode with no reserved area when no outer hold
# exists. The rule goes into mode_hold_file, which every load of the
# configuration runs, and take_mode reloads it now. The hold begins once
# the monitor reads both. A mode the output does not take fails the hold,
# unless mode_unavailable reads the nested output's allocation failure. An
# inner hold that does not take gives the outer hold its rule and mode
# again.
hold_mode() {
  local label="$1" output="$2" want="$3 scale=${4:-1}" taken mark previous_rule="" status=0
  local row_class=hold
  if [[ ${#mode_hold[@]} -gt 0 ]]; then
    previous_rule="$(cat -- "$mode_hold_file")" || { fail "$label: the held rule is unreadable"; return 0; }
  fi
  if ! { [[ -z $previous_rule ]] || printf '%s\n' "$previous_rule"; monitor_rule "$output" "$3" "${4:-1}" "${5:-}"; } >"$mode_hold_file.next" || ! mv -T -- "$mode_hold_file.next" "$mode_hold_file"; then
    fail "$label: the hold file $mode_hold_file is not written"
    rm -f -- "$mode_hold_file.next" || fail "$label: the partial hold file $mode_hold_file.next is not removed"
    return 0
  fi
  mark="$(mode_log_mark)"
  if taken="$(take_mode "$output" "$3" "${4:-1}")"; then
    if [[ -n $previous_rule ]]; then
      mode_hold_parents+=("${mode_hold[0]}" "${mode_hold[1]}" "$previous_rule")
    fi
    mode_hold=("$output" "$want")
    ok "$label: $output reads $want, $taken"
  else
    status=$?
    [[ $status != 77 ]] || mode_unavailable "$output" "$want" "$taken" "$mark"
    fail "$label: $output does not read $want: $taken"
    if [[ -n $previous_rule ]]; then
      printf '%s\n' "$previous_rule" >"$mode_hold_file" || fail "$label: the outer hold file is not restored"
      taken="$(take_mode "${mode_hold[0]}" "${mode_hold[1]% scale=*}" "${mode_hold[1]##*scale=}")" || fail "$label: the outer hold is not restored: $taken"
    else
      rm -f -- "$mode_hold_file" || fail "$label: the hold file $mode_hold_file of a hold never taken is not removed"
    fi
  fi
  return 0
}
# coordinate_mode_check: the held mode stands before a pointer step, whose
# coordinates were sampled under it. Prints `coordinate-mode: reset
# output=<name> want=[<state>] pointer-step=refused` on stderr and returns 1
# when the output reads another mode, and returns 1 when the monitor
# cannot be read; a step it refuses sends nothing.
coordinate_mode_check() {
  [[ ${#mode_hold[@]} -gt 0 ]] || return 0
  case "$(held_mode_state)" in
    held) return 0 ;;
    reset) printf 'coordinate-mode: reset output=%s want=[%s] pointer-step=refused\n' "${mode_hold[0]}" "${mode_hold[1]}" >&2; return 1 ;;
    *) printf 'coordinate-mode: unreadable output=%s\n' "${mode_hold[0]}" >&2; return 1 ;;
  esac
}
# held_mode_state: what became of the held mode, as one word. `held`: the
# output reads its mode and scale. `reset`: the output reads another mode
# or another scale. The sink sends each nested output one configure, so
# only the compositor's own monitor rules move an output off a hold: a row
# that applies another rule, or a configuration reload, which drops every
# rule `hyprctl eval` added (src/config/lua/ConfigManager.cpp,
# CConfigManager::reload, Hyprland v0.56.2) and applies the rule
# mode_hold_file names again. The shell writes no monitor rule of its own.
# `unreadable`: the monitor cannot be read.
held_mode_state() {
  local state
  state="$(mode_scale_of "${mode_hold[0]}")" || { echo unreadable; return; }
  if [[ $state == "${mode_hold[1]}" ]]; then echo held; else echo reset; fi
}
# release_mode LABEL NAME MODE [SCALE]: end the inner hold and restore its
# parent's rule, mode, scale and reserved area. Without a parent, remove
# the hold file and give NAME the caller's MODE at SCALE, 1 by default,
# with no reserved area. Read both before the rows go on, whether or not
# the inner hold took. A marked run base stays held when no parent remains.
release_mode() {
  local taken status=0
  if [[ ${#mode_hold_parents[@]} -gt 0 ]]; then
    local top=$((${#mode_hold_parents[@]} - 3))
    mode_hold=("${mode_hold_parents[top]}" "${mode_hold_parents[top + 1]}")
    printf '%s\n' "${mode_hold_parents[top + 2]}" >"$mode_hold_file" || fail "$1: the outer hold file is not restored"
    mode_hold_parents=("${mode_hold_parents[@]:0:top}")
  elif [[ $mode_hold_run_base != true ]]; then
    mode_hold=()
    # A reload needs the base rule even without frame callbacks. Remove
    # it once the base takes, leaving no outer hold.
    if ! monitor_rule "$2" "$3" "${4:-1}" >"$mode_hold_file.next" || ! mv -T -- "$mode_hold_file.next" "$mode_hold_file"; then
      fail "$1: the restore rule is not written"
      rm -f -- "$mode_hold_file.next" || fail "$1: the partial restore rule is not removed"
      return 0
    fi
  fi
  local output="${mode_hold[0]:-$2}" want="${mode_hold[1]:-$3 scale=${4:-1}}" mark
  mark="$(mode_log_mark)"
  if taken="$(take_mode "$output" "${want% scale=*}" "${want##*scale=}")"; then
    ok "$1: $output reads $want, $taken"
  else
    status=$?
    [[ $status != 77 ]] || mode_unavailable "$output" "$want" "$taken" "$mark"
    fail "$1: $output does not read $want: $taken"
  fi
  if ((${#mode_hold[@]} == 0)); then
    rm -f -- "$mode_hold_file" || fail "$1: the hold file $mode_hold_file is not removed"
  fi
  return 0
}
# The run base suspend_run_base took out of the configuration, as (OUTPUT
# STATE) in mode_hold's form, empty when none is suspended; suspend_run_base and resume_run_base alone write it.
mode_hold_suspended=()
# suspend_run_base LABEL: take the run base out of the configuration for a
# row that tests monitor rules. Every load of the configuration runs the
# hold file after the shell's generated layer, so the held rule replaces a
# rule the layer keeps, and every reload the shell runs gives the output
# the held mode again. With the base suspended, release_mode gives the
# output the caller's mode and removes the hold file, as with no outer
# hold. Removing the file takes no reload of its own: Hyprland runs the
# file only when it loads the configuration, so every later reload, the
# shell's or the row's, loads no held rule, and until then the output
# keeps the base's mode. The row's smoke_row_abandon then names
# resume_run_base, so a row that ends early still gives the next row the
# base. With no run base, as in a capture run, it suspends nothing. A run
# base under a stacked hold, or with no hold, fails
# `LABEL: suspend-run-base: refused parents=<n> held=[<hold>]` and
# suspends nothing, since the stacked rules would leave with the base.
suspend_run_base() {
  [[ $mode_hold_run_base == true ]] || return 0
  if [[ ${#mode_hold_parents[@]} -ne 0 || ${#mode_hold[@]} -eq 0 ]]; then
    fail "$1: suspend-run-base: refused parents=$((${#mode_hold_parents[@]} / 3)) held=[${mode_hold[*]:-}]"
    return 0
  fi
  if ! rm -f -- "$mode_hold_file"; then
    fail "$1: suspend-run-base: the run base's hold file $mode_hold_file is not removed"
    return 0
  fi
  mode_hold_suspended=("${mode_hold[0]}" "${mode_hold[1]}")
  mode_hold=() mode_hold_run_base=false
  smoke_row_abandon=(resume_run_base "$1")
}
# resume_run_base LABEL: the run base suspend_run_base took out, held again
# through hold_mode and marked as the run base; then the row's
# smoke_row_abandon is emptied. A base that does not take fails in
# hold_mode and is not marked. With no base suspended it does nothing.
resume_run_base() {
  [[ ${#mode_hold_suspended[@]} -gt 0 ]] || return 0
  local output="${mode_hold_suspended[0]}" want="${mode_hold_suspended[1]}"
  hold_mode "$1: the run base is held again" "$output" "${want% scale=*}" "${want##*scale=}"
  [[ ${#mode_hold[@]} -eq 0 ]] || mode_hold_run_base=true
  mode_hold_suspended=()
  smoke_row_abandon=()
}
