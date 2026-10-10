# The leak check scripts/smoke/leaks.sh runs at every row's end, and its
# controls. Each control plants a row that leaves one class's state and
# runs it through smoke_row in a subshell whose failure count is its
# answer and whose lines go to their own file, as rows/updates.sh does for
# smoke_row's traceback rule. The check fails the planted row once, on a
# line that names the row, the class and the value; the control then
# undoes what the planted row left, so this row leaves nothing. The plants:
# - clients: a toplevel maps, unfocused under a window rule with
#   no_initial_focus;
# - focus: a click focuses that toplevel;
# - submap: a dispatch into a submap this row defines through
#   `hyprctl eval`, since Hyprland enters no submap it has not registered;
# - layers: a headless output, which gets a bar;
# - options: one live option set through `hyprctl eval`;
# - variables: shell_start_path assigned;
# - shell: shell_qs_pid pointed at a process holding the shell's
#   environment with a PATH that holds no stand-in, which breaks
#   devices_guard's path-shim rule;
# - shim: a file written into the shell's stand-in directory.
# A planted row whose header declares `# leaves: options` sets the same
# option, fails nothing and prints what it left; a header word that names
# no class fails its row once; a row after which the compositor answers
# nothing fails once for each class read through it, as unreadable.
# The crash check smoke_row runs before the leak check has its control
# here too: a crash signal to the shell leaves a Quickshell crash report
# and its reporter's window; the check names the report once with its
# stack trace, ends the reporter and starts a new shell with its own log,
# and a second check reads nothing.
# smoke_row puts the pointer at rest before every row it runs outside
# another row: a planted row run so, with the pointer moved away first,
# reads the pointer at rest when it starts.
# No latency budget. The toplevel's map is polled every 0.2 s for 5 s.
# inputs: scripts/smoke/leaks.sh
set -euo pipefail
lc_plants="$sandbox/leak-plants"
mkdir -p -- "$lc_plants"
lc_class=vgs-leak-quiet
lc_output=VGS-LEAK
lc_option=general:gaps_workspaces

# lc_planted NAME: the failure count of planted row NAME, its lines in
# $sandbox/NAME.log.
lc_planted() { # NAME
  (failures=0 behaviour_failures=0; smoke_row "$1" "$lc_plants" >"$sandbox/$1.log" 2>&1; echo "$failures")
}
# lc_planted_alone NAME: as lc_planted, with NAME run as a row no other
# row holds, as qml-smoke.sh runs one.
lc_planted_alone() { # NAME
  (leak_starts=() failures=0 behaviour_failures=0; smoke_row "$1" "$lc_plants" >"$sandbox/$1.log" 2>&1; echo "$failures")
}
lc_pointer() { hypr -j cursorpos | py_reply 'import json,sys; p=json.load(sys.stdin); print("%d %d" % (p["x"], p["y"]))'; }
# lc_failed NAME PATTERN: the count of NAME's FAIL lines matching PATTERN,
# an extended regex for the text after `FAIL  NAME: `.
lc_failed() { # NAME PATTERN
  grep -c -E -- "^  FAIL  $1: $2\$" "$sandbox/$1.log" || true
}
lc_option_value() { hypr -j getoption "$lc_option" | py_reply 'import json,sys; print(json.load(sys.stdin)["int"])'; }
lc_quiet_box() { hypr -j clients | py_reply 'import json,sys; c=[c for c in json.load(sys.stdin) if c["class"]==sys.argv[1] and c["mapped"]]; print("%d %d" % (c[0]["at"][0] + c[0]["size"][0] // 2, c[0]["at"][1] + c[0]["size"][1] // 2) if len(c) == 1 else "clients=%d" % len(c))' "$lc_class"; }
lc_quiet_count() { hypr -j clients | py_reply 'import json,sys; print(sum(1 for c in json.load(sys.stdin) if c["class"]==sys.argv[1]))' "$lc_class"; }
lc_comm() { cat -- "/proc/$1/comm" 2>/dev/null || echo gone; }
# lc_output_bar: `built` once the shell holds a bar on the planted output,
# `absent` once it holds none. Hyprland lists the output's layers before
# the shell has followed the screen change, so the layer count alone can
# read settled while the shell still builds or drops a bar.
lc_output_bar() { ipc shell built | py_reply 'import json,sys; print("built" if any(k.startswith("bar:") and k.endswith(sys.argv[1]) for k in json.load(sys.stdin)) else "absent")' "$lc_output"; }

expect "a window rule keeps the planted toplevel unfocused on map" ok hypr eval "hl.window_rule({ name = \"$lc_class\", match = { class = \"^$lc_class\$\" }, no_initial_focus = true })"
lc_focus_before="$(active_window)" || fail "the active window is unreadable before the controls"

cat >"$lc_plants/leak-plant-clients.sh" <<'SH'
spawn "$sandbox/leak-plant-toplevel.log" "${shell_env[@]}" "$sandbox/toplevel" "$lc_class"
printf '%s\n' "$spawn_pid" >"$lc_plants/toplevel.pid"
expect_poll "the planted toplevel maps" 1 grep -c -x -F -- "mapped $lc_class" "$sandbox/leak-plant-toplevel.log"
expect_poll "the planted toplevel is a client" 1 lc_quiet_count
SH
expect "control: a row that leaves a client window fails once" 1 lc_planted leak-plant-clients
expect "control: the failure names the clients class and the window" 1 lc_failed leak-plant-clients "leaves clients: \\+0x[0-9a-f]+ $lc_class \"$lc_class\""
expect "the planted toplevel left the focus where it was" "$lc_focus_before" active_window

lc_point="$(lc_quiet_box)" || lc_point=""
cat >"$lc_plants/leak-plant-focus.sh" <<'SH'
click ${lc_point% *} ${lc_point#* } || fail "the planted click on the toplevel failed"
expect_poll "the planted click focuses the toplevel" "[\"$lc_class\", \"$lc_class\"]" active_window
SH
if [[ $lc_point =~ ^[0-9]+\ [0-9]+$ ]]; then
  expect "control: a row that leaves the focus moved fails once" 1 lc_planted leak-plant-focus
  expect "control: the failure names the focus class and the window" 1 lc_failed leak-plant-focus "leaves focus: \\+\\[\"$lc_class\", \"$lc_class\"\\] -.*"
  pointer_at="$lc_point"
else
  fail "the planted toplevel's box is unreadable: $lc_point"
fi

lc_toplevel="$(cat -- "$lc_plants/toplevel.pid")" || lc_toplevel=""
if [[ -n $lc_toplevel ]]; then kill -TERM -- "$lc_toplevel" 2>/dev/null || true; fi
expect_poll "the planted toplevel closes" 0 lc_quiet_count
expect_poll "the focus is back where it was" "$lc_focus_before" active_window

expect "the planted submap is defined" ok hypr eval 'hl.define_submap("vgs-leak-plant", function() hl.bind("Escape", hl.dsp.submap("reset")) end)'
cat >"$lc_plants/leak-plant-submap.sh" <<'SH'
expect "the planted submap dispatch answers ok" ok hypr dispatch 'hl.dsp.submap("vgs-leak-plant")'
expect "the planted submap is current" vgs-leak-plant key_submap
SH
expect "control: a row that leaves a submap fails once" 1 lc_planted leak-plant-submap
expect "control: the failure names the submap class and the submap" 1 lc_failed leak-plant-submap "leaves submap: \\+vgs-leak-plant -default"
expect "the submap resets" ok hypr dispatch 'hl.dsp.submap("reset")'
expect "the submap is the default again" default key_submap

lc_bars="$(bar_count)" || lc_bars=""
cat >"$lc_plants/leak-plant-layers.sh" <<'SH'
expect "the planted output is created" ok hypr output create headless "$lc_output"
expect_poll "the shell builds a bar on the planted output" built lc_output_bar
expect_poll "the planted output gets a bar" "$((lc_bars + 1))" bar_count
SH
if [[ $lc_bars =~ ^[0-9]+$ ]]; then
  expect "control: a row that leaves a layer fails once" 1 lc_planted leak-plant-layers
  expect "control: the failure names the layers class and the namespace" 1 lc_failed leak-plant-layers "leaves layers: \\+vgs:bar"
  expect "the planted output is removed" ok hypr output remove "$lc_output"
  expect_poll "the shell drops the planted output's bar" absent lc_output_bar
  expect_poll "the bars are as they were" "$lc_bars" bar_count
else
  fail "the bar count is unreadable before the layers control: $lc_bars"
fi

lc_option_was="$(lc_option_value)" || lc_option_was=""
if [[ $lc_option_was =~ ^[0-9]+$ ]]; then
  lc_option_set=$((lc_option_was + 7))
  printf '%s\n' "expect \"the planted option is set\" ok hypr eval 'hl.config({ general = { gaps_workspaces = $lc_option_set } })'" >"$lc_plants/leak-plant-options.sh"
  expect "control: a row that leaves a live option fails once" 1 lc_planted leak-plant-options
  expect "control: the failure names the options class, the option and both values" 1 lc_failed leak-plant-options "leaves options: \\+$lc_option=\\{\"int\": $lc_option_set\\} -$lc_option=\\{\"int\": $lc_option_was\\}"
  expect "the option is set back after its control" ok hypr eval "hl.config({ general = { gaps_workspaces = $lc_option_was } })"
  { printf '# leaves: options\n'; cat -- "$lc_plants/leak-plant-options.sh"; } >"$lc_plants/leak-plant-declared.sh"
  expect "a row whose header declares the options it leaves fails nothing" 0 lc_planted leak-plant-declared
  expect "the declared row prints the options it left" 1 grep -c -x -F -- "  ok    leak-plant-declared: leaves options, as its header declares: +$lc_option={\"int\": $lc_option_set} -$lc_option={\"int\": $lc_option_was}" "$sandbox/leak-plant-declared.log"
  expect "the option is set back after the declared row" ok hypr eval "hl.config({ general = { gaps_workspaces = $lc_option_was } })"
  expect "the option reads its value again" "$lc_option_was" lc_option_value
else
  fail "$lc_option is unreadable before the options control: $lc_option_was"
fi

printf '# leaves: windows\n:\n' >"$lc_plants/leak-plant-unknown.sh"
expect "control: a header word that names no class fails its row once" 1 lc_planted leak-plant-unknown
expect "control: the failure names the word" 1 lc_failed leak-plant-unknown "leak-check refused: leaves=windows reason=unknown-class"

cat >"$lc_plants/leak-plant-variables.sh" <<'SH'
shell_start_path="$sandbox/leak-plant:$shell_start_path"
SH
expect "control: a row that leaves a start variable assigned fails once" 1 lc_planted leak-plant-variables
expect "control: the failure names the variables class and the value" 1 lc_failed leak-plant-variables "leaves variables: \\+declare -[-a-zA-Z]* shell_start_path=\"$sandbox/leak-plant:.*"

cat >"$lc_plants/leak-plant-shell.sh" <<'SH'
mapfile -d '' lc_environ <"/proc/$shell_qs_pid/environ"
spawn "$sandbox/leak-plant-shell-process.log" env -i "${lc_environ[@]}" PATH=/usr/bin:/bin sleep 600
printf '%s\n' "$spawn_pid" >"$lc_plants/shell.pid"
expect_poll "the planted process holds its own environment" sleep lc_comm "$spawn_pid"
shell_qs_pid="$spawn_pid"
SH
expect "control: a row that leaves the shell outside the stand-ins fails once" 1 lc_planted leak-plant-shell
expect "control: the failure names the shell class and the rule" 1 lc_failed leak-plant-shell "leaves shell: \\+leak=path-shim value=.*"
lc_process="$(cat -- "$lc_plants/shell.pid")" || lc_process=""
if [[ -n $lc_process ]]; then kill -TERM -- "$lc_process" 2>/dev/null || true; fi
expect_poll "the planted process ends" gone lc_comm "$lc_process"

cat >"$lc_plants/leak-plant-shim.sh" <<'SH'
printf '#!/bin/sh\nexit 0\n' >"$shim/vgs-leak-plant"
chmod 755 "$shim/vgs-leak-plant"
SH
expect "control: a row that leaves a file in the stand-in directory fails once" 1 lc_planted leak-plant-shim
expect "control: the failure names the shim class and the file" 1 lc_failed leak-plant-shim "leaves shim: \\+vgs-leak-plant [0-9a-f]{12}"
rm -f -- "${shim:?}/vgs-leak-plant"

cat >"$lc_plants/leak-plant-unreadable.sh" <<'SH'
hypr() { return 1; }
SH
expect "control: a row after which the compositor answers nothing fails once per class read through it" 5 lc_planted leak-plant-unreadable
expect "control: the failure names the unreadable class and the end" 1 lc_failed leak-plant-unreadable "leak-check reading=unreadable class=clients at=end .*"

# The crash control: a crash signal past Quickshell's 10 s restart floor.
lc_ran() { local secs; secs="$(ps -o etimes= -p "$shell_qs_pid")" || { echo gone; return; }; secs="${secs// /}"; if ((secs >= 11)); then echo ran; else echo "secs=$secs"; fi; }
lc_reports() { local n=0 report; for report in "$home/.cache/quickshell/crashes"/*/report.txt; do [[ -f $report ]] && n=$((n + 1)); done; echo "$n"; }
lc_strays() { shell_strays | grep -c . || true; }
lc_crashes="$sandbox/leak-plant-crash.crashes"
lc_reports_before="$(lc_reports)"
expect_poll "the shell has run past Quickshell's restart floor" ran lc_ran
lc_crashed_pid="$shell_qs_pid"
lc_crashed_log="$instance_log"
# Read before the signal: the crash check's stop reads this pid again, and
# a read that comes before Quickshell has started again in it finds no
# resident size, which would leave this shell unread for
# rows/diagnostics.sh.
shell_memory_note
kill -SEGV -- "$shell_qs_pid" || fail "the planted crash signal was not sent"
expect_poll "the planted crash leaves a crash report" "$((lc_reports_before + 1))" lc_reports
expect_poll "the planted crash maps Quickshell's crash reporter window" 1 lc_strays
if shell_crash_check "$lc_crashes"; then fail "control: the crash check read no crash after the planted one"; fi
expect "control: the crash check names the planted crash once" 1 grep -c -E -- "^crash=[0-9a-z]+ report=.*/report\\.txt\$" "$lc_crashes"
expect "control: the crash check prints the crash's stack trace" 1 grep -c -E -- "^        #0 " "$lc_crashes"
expect "the crash check leaves no crash reporter window" 0 lc_strays
lc_new_shell() { [[ $shell_qs_pid != "$lc_crashed_pid" && $instance_log != "$lc_crashed_log" ]] && echo new || echo "pid=$shell_qs_pid log=$instance_log"; }
expect "the crash check starts a new shell with its own log" new lc_new_shell
expect "the new shell answers" ok ipc shell ping
lc_check_again() { if shell_crash_check "$sandbox/leak-plant-crash-again.crashes"; then echo none; else echo found; fi; }
expect "a second crash check reads no crash" none lc_check_again

cat >"$lc_plants/leak-plant-rest.sh" <<'SH'
expect "the row starts with the pointer at rest" "10 $((mon_h - 10))" lc_pointer
SH
hover "$((mon_w / 2))" "$((mon_h / 2))" || fail "the pointer could not be moved off its rest"
expect "the pointer is away from its rest before the planted row" "$((mon_w / 2)) $((mon_h / 2))" lc_pointer
expect "control: a row run alone starts with the pointer at rest" 0 lc_planted_alone leak-plant-rest
rest_pointer || fail "the pointer could not be put back at rest"
