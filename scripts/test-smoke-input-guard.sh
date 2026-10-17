#!/usr/bin/env bash
# Pins nested_input_check in scripts/smoke/harness.sh, the one display
# check every smoke and shot input helper runs before its tool, and each
# helper's call to it, including display clients. The check passes when shell_env
# starts from an empty environment and names the socket the harness
# started; any other shell_env gets the keyed refusal
# `nested-input: refused tool=TOOL ...` and no tool runs.
#
# Display-client controls name the host runtime directory in shell_env.
# The terminal control inherits it, then builds the final client environment
# from those inherited display values. The outer test has no live names.
# Each case runs code extracted from the real file in a clean bash whose
# environment carries no WAYLAND_DISPLAY, DISPLAY or HYPRLAND_INSTANCE_
# SIGNATURE, with recording stubs first on PATH (wtype, wl-copy) and at
# $sandbox/click, $sandbox/keyboard and $sandbox/keyboard-silent, so a
# guard the stub does not see reaches no display either. A helper's other
# commands that the case does not define succeed and print `10 20`
# (command_not_found_handle), a point every coordinate reader accepts, so
# only the guard stands between the helper and its tool. The rule cases
# run type_keys over the table of shell_env forms; the helper cases run
# each helper with shell_env naming the nested socket's name in the host
# runtime directory, as wayland-1 can on a live session. The controls at the end plant one defect per rule in a copy of
# the check and one per helper in a copy of that helper, and require the
# case each defect owns to go red.
#
# Exit 0 when every case and control holds, 1 otherwise.
set -euo pipefail
unset WAYLAND_DISPLAY WAYLAND_SOCKET DISPLAY HYPRLAND_INSTANCE_SIGNATURE

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"

tmp="$(mktemp -d)" || { echo "test-smoke-input-guard: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "test-smoke-input-guard: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)" || { echo "test-smoke-input-guard: scratch=resolve-failed" >&2; exit 1; }
trap 'rm -rf -- "${tmp:?}"' EXIT
# Case words split on spaces, so the paths they name hold none.
[[ $tmp != *[[:space:]]* ]] || { echo "test-smoke-input-guard: scratch=has-space value=[$tmp]" >&2; exit 1; }

failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

# extract FILE SPEC NEEDLE OUT: the unit SPEC names in FILE, written to OUT.
# fn:NAME is a function, at any indent; block:PREFIX runs from the line
# that starts with PREFIX to the `fi` at its indent; case:LINE is a case
# arm from that exact line to its first line ending `;;`, wrapped in a case
# that selects it.
# line:LINE extracts exactly that call, including a call in a planted row.
# The unit's anchor occurs once in FILE and the unit holds NEEDLE, the
# tool call the guard stands before.
extract() {
  python3 - "$@" <<'PY'
import re, sys
from pathlib import Path
path, spec, needle, out = sys.argv[1:]
lines = Path(path).read_text().split("\n")
kind, _, name = spec.partition(":")
if kind == "fn":
    hits = [i for i, l in enumerate(lines) if re.match(r"\s*" + re.escape(name) + r"\(\) \{", l)]
elif kind in ("block", "statement", "heredoc"):
    hits = [i for i, l in enumerate(lines) if l.startswith(name)]
else:
    hits = [i for i, l in enumerate(lines) if l == name]
if len(hits) != 1:
    sys.exit("test-smoke-input-guard: extract=anchor-count value=%d spec=[%s] file=%s" % (len(hits), spec, path))
start = hits[0]
indent = lines[start][: len(lines[start]) - len(lines[start].lstrip())]
end = None
if kind == "statement":
    end = start
    while lines[end].endswith("\\"):
        end += 1
elif kind == "heredoc":
    marker = lines[start].split("<<", 1)[1].strip("'\"")
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == marker)
elif kind == "line" or (kind == "fn" and lines[start].rstrip().endswith("}")):
    end = start
else:
    close = {"fn": indent + "}", "block": indent + "fi"}.get(kind)
    heredoc = None
    for i in range(start + 1, len(lines)):
        if heredoc is not None:
            if lines[i] == heredoc:
                heredoc = None
            continue
        marker = re.search(r"<<-?['\"]?(\w+)['\"]?", lines[i])
        if marker:
            heredoc = marker.group(1)
            continue
        if (close is not None and lines[i] == close) or (kind == "case" and lines[i].endswith(";;")):
            end = i
            break
if end is None:
    sys.exit("test-smoke-input-guard: extract=no-end spec=[%s] file=%s" % (spec, path))
unit = "\n".join(lines[start : end + 1])
if needle not in unit:
    sys.exit("test-smoke-input-guard: extract=no-tool-call needle=[%s] spec=[%s]" % (needle, spec))
if kind == "case":
    unit = "case %s in\n%s\nesac" % (name.strip()[:-1], unit)
Path(out).write_text(unit + "\n")
PY
}

units="$tmp/units"
mkdir -p -- "$units"
harness="$repo/scripts/smoke/harness.sh"
extract "$harness" fn:nested_input_check 'fail "nested-input: refused tool=$1 ' "$units/check.sh" || exit 1
extract "$harness" fn:type_keys '"${shell_env[@]}" wtype "$@"' "$units/type-keys.sh" || exit 1
extract "$harness" fn:spawn_display 'spawn "$1" "${shell_env[@]}" "${@:2}"' "$units/spawn-display.sh" || exit 1
extract "$harness" fn:spawn 'setsid "$@"' "$units/spawn.sh" || exit 1
extract "$harness" fn:write_display_client 'exec "${shell_env[@]}" "$@"' "$units/display-client.sh" || exit 1

# make_world DIR: DIR/bin and DIR/sandbox, each tool a stub that records
# its name, arguments and display in DIR/calls.
make_world() {
  local dir="$1" tool
  mkdir -p -- "$dir/bin" "$dir/sandbox" "$dir/rt" "$dir/host"
  for tool in bin/wtype bin/wl-copy sandbox/click sandbox/keyboard sandbox/keyboard-silent sandbox/toplevel sandbox/lock-client sandbox/other; do
    printf '#!%s\nprintf %q "${0##*/}" "$*" "${WAYLAND_DISPLAY:-}" "${XDG_RUNTIME_DIR:-}" >>%q\n' \
      "$BASH" 'tool=%s args=%s display=%s runtime=%s\n' "$dir/calls" >"$dir/$tool"
    chmod 755 "$dir/$tool"
  done
  printf '#!%s\nexit 0\n' "$BASH" >"$dir/bin/wl-paste"
  chmod 755 "$dir/bin/wl-paste"
  printf '#!%s\nfor ((i=0; i<100; i++)); do [[ ! -e %q ]] || exit 0; sleep 0.01; done\nexit 1\n' \
    "$BASH" "$dir/calls" >"$dir/bin/vgshell-tui"
  chmod 755 "$dir/bin/vgshell-tui"
}

# run_world DIR CHECK UNIT WORDS CALL: CALL in a clean bash that has
# sourced CHECK and UNIT, with shell_env set from WORDS; fail appends to
# DIR/fails. Prints the exit status.
run_world() {
  local dir="$1" status=0
  env -i PATH="$dir/bin:$PATH" HOME="$dir" LC_ALL=C TMPDIR="$dir" \
    CASE_WORDS="$4" CASE_CALL="$5" CASE_DIR="$dir" timeout 15 "$BASH" -c '
    set -euo pipefail
    # A held drag runs its tool in a coproc, which can outlive a helper
    # that returns early; the world waits for it, so its call is recorded
    # before the case reads the calls.
    trap wait EXIT
    fail() { printf "%s\n" "$*" >>"$CASE_DIR/fails"; }
    # It reads its input first, so a reader before it in a pipe ends whole.
    command_not_found_handle() { cat >/dev/null; echo 10 20; }
    # Exercise the real session spawn. The exit trap reaps it before the
    # outer case reads the stub record. Only controls use the bypass.
    pgids=()
    source "$3"
    source "$4"
    unguarded_display_spawn() { local log="$1"; shift; spawn "$log" "${shell_env[@]}" "$@"; }
    nested_socket=wayland-1 rt_dir="$CASE_DIR/rt" sandbox="$CASE_DIR/sandbox" home="$CASE_DIR"
    mon_w=100 mon_h=100 pointer_at="" failures=0
    share_world="$sandbox" traffic_dir="$sandbox" lc_class=smoke.leak shell_reporter_class=smoke.reporter
    tui_record="$sandbox/terminal.calls" tui_refused="$sandbox/refused" tui_fixtures="$sandbox/fixtures"
    tui_terminal="$sandbox/terminal" tui_terminal_written="$sandbox/terminal-written"
    wa_dir="$sandbox" wa_launches="$sandbox/browser.calls" jd_entry="$sandbox/app.desktop"
    read -r -a shell_env <<<"$CASE_WORDS"
    source "$1"
    source "$5"
    write_display_client
    source "$2"
    eval "$CASE_CALL"' _ "$2" "$3" "$units/spawn.sh" "$units/spawn-display.sh" "$units/display-client.sh" </dev/null >/dev/null 2>&1 || status=$?
  printf '%s\n' "$status"
}

# expand DIR TEXT: TEXT with @bin, @sandbox, @rt and @host made paths
# under DIR.
expand() {
  local text="$2"
  text="${text//@bin/$1/bin}"
  text="${text//@sandbox/$1/sandbox}"
  text="${text//@rt/$1/rt}"
  printf '%s\n' "${text//@host/$1/host}"
}

# refusals DIR TOOL: the refusal lines DIR/fails holds, and how many name
# another tool.
refusals() {
  local line count=0 other=0
  if [[ -e $1/fails ]]; then
    while IFS= read -r line; do
      [[ $line == "nested-input: refused tool="* ]] || continue
      count=$((count + 1))
      [[ $line == "nested-input: refused tool=$2 socket="* ]] || other=$((other + 1))
    done <"$1/fails"
  fi
  printf '%s %s\n' "$count" "$other"
}

# Rule cases: NAME|WANT|SHELL_ENV words. The nested socket is
# @rt/wayland-1; the host's is @host/wayland-1.
rule_cases=(
  "the nested socket by name in the sandbox runtime directory|accepted|env -i PATH=@bin XDG_RUNTIME_DIR=@rt WAYLAND_DISPLAY=wayland-1"
  "the nested socket by absolute path|accepted|env -i PATH=@bin WAYLAND_DISPLAY=@rt/wayland-1"
  "shell_env replaced by command|refused|command"
  "an empty shell_env|refused|"
  "env without -i, which keeps the caller's environment|refused|env PATH=@bin XDG_RUNTIME_DIR=@rt WAYLAND_DISPLAY=wayland-1"
  "no WAYLAND_DISPLAY word|refused|env -i PATH=@bin XDG_RUNTIME_DIR=@rt"
  "the nested socket's name in the host runtime directory|refused|env -i PATH=@bin XDG_RUNTIME_DIR=@host WAYLAND_DISPLAY=wayland-1"
  "a later WAYLAND_DISPLAY word naming the host socket|refused|env -i PATH=@bin XDG_RUNTIME_DIR=@rt WAYLAND_DISPLAY=wayland-1 WAYLAND_DISPLAY=@host/wayland-1"
)

# rule_case CHECK WANT WORDS: prints nothing when type_keys -k Escape under
# CHECK gives WANT, else the problems found.
rule_case() {
  local dir status count other problems=()
  dir="$(mktemp -d "$tmp/rule.XXXXXX")" || { echo "scratch=mktemp-failed"; return; }
  make_world "$dir"
  if ! status="$(run_world "$dir" "$1" "${4:-$units/type-keys.sh}" "$(expand "$dir" "$3")" "$(expand "$dir" "${5:-type_keys -k Escape}")")"; then echo "run_world-failed"; return; fi
  read -r count other < <(refusals "$dir" wtype)
  case $2 in
    accepted)
      [[ $status == 0 ]] || problems+=("status=$status")
      [[ $count == 0 ]] || problems+=("refusals=$count")
      [[ -e $dir/calls && $(<"$dir/calls") =~ ^tool=wtype\ args=-k\ Escape\ display=(.*)\ runtime=(.*)$ ]] || problems+=("calls=[$(cat -- "$dir/calls" 2>/dev/null)]")
      # The socket wtype reached, resolved as libwayland resolves it.
      local display="${BASH_REMATCH[1]:-}" runtime="${BASH_REMATCH[2]:-}"
      [[ $display == /* ]] || display="$runtime/$display"
      [[ $display == "$dir/rt/wayland-1" ]] || problems+=("wtype-socket=$display")
      ;;
    refused)
      [[ $status == 1 ]] || problems+=("status=$status")
      [[ $count == 1 && $other == 0 ]] || problems+=("refusals=$count other-tool=$other")
      [[ ! -e $dir/calls ]] || problems+=("calls=[$(<"$dir/calls")]")
      ;;
  esac
  [[ ${#problems[@]} == 0 ]] || printf '%s\n' "${problems[*]}"
}

for row in "${rule_cases[@]}"; do
  IFS='|' read -r name want words <<<"$row"
  if found="$(rule_case "$units/check.sh" "$want" "$words")" && [[ -z $found ]]; then
    ok "rule: $want: $name"
  else
    fail "rule: $want: $name: ${found:-rule_case-failed}"
  fi
done

# The display boundary also starts its real session on the nested socket.
for row in "${rule_cases[@]}"; do
  IFS='|' read -r name want words <<<"$row"
  if found="$(rule_case "$units/check.sh" "$want" "$words" "$units/spawn-display.sh" 'spawn_display @sandbox/display.log wtype -k Escape')" && [[ -z $found ]]; then
    ok "display rule: $want: $name"
  else
    fail "display rule: $want: $name: ${found:-rule_case-failed}"
  fi
done

# Helper cases: NAME|FILE|UNIT (extract's SPEC)|NEEDLE, the tool call the
# guard stands before|CALL|TOOL the refusal names|STATUS wanted: nonzero,
# or any for a block its refusal skips|GUARD changed by its control, default
# nested_input_check. Each runs with the host-socket
# shell_env below.
host_words="env -i PATH=@bin XDG_RUNTIME_DIR=@host WAYLAND_DISPLAY=wayland-1"
helpers=(
  'display spawn boundary|scripts/smoke/harness.sh|fn:spawn_display|spawn "$1" "${shell_env[@]}"|spawn_display @sandbox/display.log @sandbox/toplevel smoke.boundary|@sandbox/toplevel|nonzero|nested_input_check'
  'lock client|scripts/smoke/rows/lock.sh|fn:start_lock_client|spawn_display|start_lock_client probe|@sandbox/lock-client|nonzero|spawn_display'
  'application window|scripts/smoke/app-window.sh|fn:open_toplevel|spawn_display|open_toplevel @sandbox/app.log smoke.app App|@sandbox/toplevel|nonzero|spawn_display'
  'Hyprland window|scripts/smoke/rows/hyprland.sh|fn:open_tui|spawn_display|open_tui smoke.hyprland|@sandbox/toplevel|nonzero|spawn_display'
  'leak client|scripts/smoke/rows/leak-check.sh|line:spawn_display "$sandbox/leak-plant-toplevel.log" "$sandbox/toplevel" "$lc_class"|spawn_display|:|@sandbox/toplevel|nonzero|spawn_display'
  'leak reporter|scripts/smoke/rows/leak-check.sh|line:  spawn_display "$sandbox/leak-plant-reporter.log" "$sandbox/toplevel" "$shell_reporter_class"|spawn_display|:|@sandbox/toplevel|nonzero|spawn_display'
  'traffic window|scripts/smoke/rows/traffic.sh|line:spawn_display "$traffic_dir/other.log" "$sandbox/toplevel" org.example.traffic Traffic-other|spawn_display|:|@sandbox/toplevel|nonzero|spawn_display'
  'TUI other window|scripts/smoke/rows/tui.sh|line:spawn_display "$sandbox/toplevel-other.log" "$sandbox/toplevel" org.example.other Other|spawn_display|:|@sandbox/toplevel|nonzero|spawn_display'
  'share target|scripts/smoke/rows/share-picker.sh|line:spawn_display "$share_world/other.log" "$share_world/other" smoke.share-other "Other share target"|spawn_display|:|@sandbox/other|nonzero|spawn_display'
  'inherited display boundary|scripts/smoke/harness.sh|fn:write_display_client|exec "${shell_env[@]}" "$@"|write_display_client; env XDG_RUNTIME_DIR=@host WAYLAND_DISPLAY=wayland-1 "$sandbox/display-client" "$sandbox/toplevel" 2>"$CASE_DIR/fails"|@sandbox/toplevel|nonzero|nested_input_check "$1"'
  'terminal window|scripts/smoke/harness.sh|fn:terminal_stand_in|"$display_client" "$toplevel"|terminal_stand_in; env XDG_RUNTIME_DIR=@host WAYLAND_DISPLAY=wayland-1 "$tui_terminal" --app-id=smoke.terminal --title=Terminal -- @bin/vgshell-tui present -- true 2>"$CASE_DIR/fails"|@sandbox/toplevel|nonzero|"$display_client" '
  'webapps browser|scripts/smoke/rows/webapps.sh|heredoc:cat >"$wa_dir/chromium" <<EOF|"$sandbox/display-client"|env XDG_RUNTIME_DIR=@host WAYLAND_DISPLAY=wayland-1 "$BASH" "$wa_dir/chromium" --app=https://example.com 2>"$CASE_DIR/fails"|@sandbox/toplevel|nonzero|$(printf '\''%q'\'' "$sandbox/display-client") '
  'Jarvis application|scripts/smoke/rows/jarvis-desktop.sh|statement:printf '\''[Desktop Entry]|"$sandbox/display-client"|read -r -a desktop_exec <<<"$(sed -n '\''s/^Exec=//p'\'' "$jd_entry")"; env XDG_RUNTIME_DIR=@host WAYLAND_DISPLAY=wayland-1 "${desktop_exec[@]}" 2>"$CASE_DIR/fails"|@sandbox/toplevel|nonzero|"$sandbox/display-client" '
  'type_keys|scripts/smoke/harness.sh|fn:type_keys|"${shell_env[@]}" wtype|type_keys -k Escape|wtype|nonzero'
  'pointer_dispatch|scripts/smoke/harness.sh|fn:pointer_dispatch|"$sandbox/click" "$@"|pointer_dispatch 10 20 100 100|@sandbox/click|nonzero'
  'hold_start_keyboard keyboard|scripts/smoke/rows/hold-shortcuts.sh|fn:hold_start_keyboard|spawn "$hold_keyboard_log" "${shell_env[@]}" "$2"|hold_start_keyboard probe @sandbox/keyboard us ""|@sandbox/keyboard|nonzero'
  'hold_start_keyboard keyboard-silent|scripts/smoke/rows/hold-shortcuts.sh|fn:hold_start_keyboard|spawn "$hold_keyboard_log" "${shell_env[@]}" "$2"|hold_start_keyboard silent @sandbox/keyboard-silent us ""|@sandbox/keyboard-silent|nonzero'
  'reset_keyboard_start|scripts/smoke/rows/reset.sh|fn:reset_keyboard_start|"${shell_env[@]}" "$sandbox/keyboard"|reset_keyboard_fifo=@sandbox/reset.fifo reset_keyboard_log=@sandbox/reset.log; reset_keyboard_start|@sandbox/keyboard|nonzero'
  'voice_start_keyboard|scripts/smoke/rows/voice.sh|fn:voice_start_keyboard|"${shell_env[@]}" "$sandbox/keyboard"|voice_start_keyboard|@sandbox/keyboard|nonzero'
  'zone_hold_press|scripts/smoke/rows/bar.sh|fn:zone_hold_press|"${shell_env[@]}" "$sandbox/click"|zone_hold_press acme.probe 0 12|@sandbox/click|nonzero'
  'tiplink_drag|scripts/smoke/rows/bar.sh|fn:tiplink_drag|"${shell_env[@]}" "$sandbox/click"|tiplink_drag acme.tiplink far|@sandbox/click|nonzero'
  'placement_drag_escape|scripts/smoke/rows/placement.sh|fn:placement_drag_escape|"${shell_env[@]}" "$sandbox/click"|placement_drag_escape acme.probe 1 2 vgs:passthrough|@sandbox/click|nonzero'
  'placement_drag_path|scripts/smoke/rows/placement.sh|fn:placement_drag_path|"${shell_env[@]}" "$sandbox/click"|placement_drag_path acme.probe 1 2|@sandbox/click|nonzero'
  'placement_held_far|scripts/smoke/rows/placement.sh|fn:placement_held_far|"${shell_env[@]}" "$sandbox/click"|placement_held_far label want|@sandbox/click|nonzero'
  'placement_held_builtin|scripts/smoke/rows/placement.sh|fn:placement_held_builtin|"${shell_env[@]}" "$sandbox/click"|placement_held_builtin stepped want slot label|@sandbox/click|nonzero'
  'placement_same_slot|scripts/smoke/rows/placement.sh|fn:placement_same_slot|"${shell_env[@]}" "$sandbox/click"|placement_file=@sandbox/shell.json; echo {\"bar\":{\"layout\":{\"right\":[0]}}} >"$placement_file"; placement_same_slot|@sandbox/click|nonzero'
  'placement_held_preview|scripts/smoke/rows/placement.sh|fn:placement_held_preview|"${shell_env[@]}" "$sandbox/click"|placement_held_preview moving|@sandbox/click|nonzero'
  'placement_edge_hold|scripts/smoke/rows/placement.sh|fn:placement_edge_hold|"${shell_env[@]}" "$sandbox/click"|placement_edge_tip_file=@sandbox/tips; placement_edge_hold 50|@sandbox/click|nonzero'
  'fade_pressed_card_pair|scripts/smoke/rows/notifications.sh|fn:fade_pressed_card_pair|"${shell_env[@]}" "$sandbox/click"|fade_pressed_card_pair prefix summary edge|@sandbox/click|nonzero'
  'clip_copy|scripts/smoke/rows/clipboard.sh|fn:clip_copy|"${shell_env[@]}" wl-copy|clip_copy "smoke text"|wl-copy|nonzero'
  'clip_copy_file|scripts/smoke/rows/clipboard.sh|fn:clip_copy_file|"${shell_env[@]}" wl-copy|: >@sandbox/image.png; clip_copy_file image/png @sandbox/image.png|wl-copy|nonzero'
  'clip_copy_secret|scripts/smoke/rows/clipboard.sh|fn:clip_copy_secret|"${shell_env[@]}" wl-copy|clip_copy_secret "smoke secret"|wl-copy|nonzero'
  'launcher paste block|scripts/smoke/rows/launcher.sh|block:if ! command -v wl-copy >/dev/null |"${shell_env[@]}" wl-copy|:|wl-copy|any'
  'sandbox-shots clipboard scene|scripts/sandbox-shots.sh|case:    clipboard)|"${shell_env[@]}" wl-copy|: >@sandbox/shots-clipboard.png|wl-copy|nonzero'
)

# helper_case UNIT CALL TOOL STATUS: prints nothing when UNIT, run with
# CALL in the host-socket world, refuses through nested_input_check naming
# TOOL and reaches no stub, else the problems found.
helper_case() {
  local dir status count other tool problems=()
  dir="$(mktemp -d "$tmp/helper.XXXXXX")" || { echo "scratch=mktemp-failed"; return; }
  make_world "$dir"
  tool="$(expand "$dir" "$3")"
  if ! status="$(run_world "$dir" "$units/check.sh" "$1" "$(expand "$dir" "$host_words")" "$(expand "$dir" "$2")")"; then echo "run_world-failed"; return; fi
  read -r count other < <(refusals "$dir" "$tool")
  [[ $4 == any || $status != 0 ]] || problems+=("status=$status")
  [[ $count -ge 1 && $other == 0 ]] || problems+=("refusals=$count other-tool=$other")
  [[ ! -e $dir/calls ]] || problems+=("calls=[$(<"$dir/calls")]")
  [[ ${#problems[@]} == 0 ]] || printf '%s\n' "${problems[*]}"
}

helper_unit() { printf '%s/helper-%s.sh\n' "$units" "$1"; }
for i in "${!helpers[@]}"; do
  IFS='|' read -r name file spec needle call tool want guard <<<"${helpers[i]}"
  if ! extract "$repo/$file" "$spec" "$needle" "$(helper_unit "$i")"; then
    fail "helper: $name: extract failed"
    continue
  fi
  if found="$(helper_case "$(helper_unit "$i")" "$call" "$tool" "$want")" && [[ -z $found ]]; then
    ok "helper: $name refuses with no tool call"
  else
    fail "helper: $name: ${found:-helper_case-failed}"
  fi
done

# plant FILE OLD NEW OUT: OUT is FILE with OLD, which occurs once, made NEW.
plant() {
  python3 - "$@" <<'PY'
from pathlib import Path
import sys
source, old, new, out = Path(sys.argv[1]).read_text(), sys.argv[2], sys.argv[3], Path(sys.argv[4])
if source.count(old) != 1:
    sys.exit("test-smoke-input-guard: control-edit=match-count value=%d old=[%s]" % (source.count(old), old))
out.write_text(source.replace(old, new, 1))
PY
}

# Rule controls: NAME|rule case it turns red|OLD|NEW, planted in a copy
# of nested_input_check; the case must go red with a wtype call. No cell
# holds a `|`.
rule_controls=(
  'no refusal|shell_env replaced by command|if [[ -z ${nested_socket:-} |if false && [[ -z ${nested_socket:-} '
  "no -i required|env without -i, which keeps the caller's environment|&& \${shell_env[1]:-} == -i ]]|]]"
  "the socket name alone compared|the nested socket's name in the host runtime directory|\$socket != \"\$rt_dir/\$nested_socket\"|\${socket##*/} != \"\$nested_socket\""
  'the first WAYLAND_DISPLAY word taken|a later WAYLAND_DISPLAY word naming the host socket|display="${word#*=}"|display="${display:-${word#*=}}"'
)
for i in "${!rule_controls[@]}"; do
  IFS='|' read -r name target old new <<<"${rule_controls[i]}"
  mutant="$tmp/rule-mutant-$i.sh"
  plant "$units/check.sh" "$old" "$new" "$mutant" || { fail "control: $name: the defect could not be planted"; continue; }
  row=""
  for candidate in "${rule_cases[@]}"; do [[ ${candidate%%|*} != "$target" ]] || row="$candidate"; done
  if [[ -z $row ]]; then fail "control: $name names no rule case \"$target\""; continue; fi
  IFS='|' read -r _ want words <<<"$row"
  if found="$(rule_case "$mutant" "$want" "$words")" && [[ $found == *calls=\[tool=wtype* ]]; then ok "control: $name turns \"$target\" red: $found"; else fail "control: $name leaves \"$target\" green"; fi
done

# Helper controls bypass the guard in each disposable unit. Display callers
# restore the old unguarded spawn with host shell_env. The generated terminal
# bypasses the shared check in its script body.
for i in "${!helpers[@]}"; do
  IFS='|' read -r name _ _ _ call tool want guard <<<"${helpers[i]}"
  mutant="$tmp/helper-mutant-$i.sh"
  [[ -e $(helper_unit "$i") ]] || { fail "control: $name: no unit was extracted"; continue; }
  replacement=:
  [[ ${guard:-nested_input_check} != spawn_display ]] || replacement=unguarded_display_spawn
  case $name in
    'terminal window'|'webapps browser') replacement="" ;;
    'Jarvis application') replacement='"" ' ;;
  esac
  plant "$(helper_unit "$i")" "${guard:-nested_input_check}" "$replacement" "$mutant" || { fail "control: $name: the defect could not be planted"; continue; }
  if found="$(helper_case "$mutant" "$call" "$tool" "$want")" && [[ $found == *"calls=[tool=${tool##*/} "* ]]; then ok "control: $name without its guard goes red: $found"; else fail "control: $name without its guard stays green"; fi
  if [[ -n $guard && $found != *"display=wayland-1 runtime="*"/host"* ]]; then
    fail "control: $name did not reach the host display fixture"
  fi
done

if [[ $failures -gt 0 ]]; then echo "test-smoke-input-guard: failures=$failures"; exit 1; fi
echo "test-smoke-input-guard: ok"
