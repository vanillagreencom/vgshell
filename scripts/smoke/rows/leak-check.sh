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
# - layers: a headless output, which gets a bar; and a vgs.themes
#   background, a state file naming a 5000x5000 image, which maps one on
#   every screen;
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
# and a second check reads nothing. Quickshell's reporter can read an empty
# instance record (shell_crash_check's header), so the planted crash counts
# in either form, and the empty-record form has its own controls: a report
# planted at the path that form writes, beside a toplevel with Quickshell's
# default app id, reads as one crash named for the form and the check ends
# the toplevel; the same path written again reads as a crash again.
# smoke_row puts the pointer at rest before every row it runs outside
# another row: a planted row run so, with the pointer moved away first,
# reads the pointer at rest when it starts.
# A planted row whose shell is killed and which takes up no other, ending
# once the runner's next shell answers and maps its bars, fails once, on
# the shell class, and the failure carries the runner's exit line.
# The layers class is read once the per-screen layers are at rest. With
# each screen's background held in a FIFO until the end reading has read
# the layers or found them unsettled, a planted row whose shell the
# runner starts again after a SIGKILL, ending once the shell answers and
# maps its bars, fails nothing, and its end reading recorded the held
# background settling before it came to rest; its copy whose end reading
# does not wait for rest fails once, naming the background it missed.
# Before them the row restarts the shell with the background configured
# and prints, judging nothing, how long after start_shell returned the
# per-screen layers came to rest. The background's state file as it was
# comes back after, its layers go, and the row ends with a shell and a
# runner started anew.
# No latency budget. The toplevel's map is polled every 0.2 s for 5 s; the
# per-screen layers every 0.1 s for up to timeout_s; the end reading's
# files, for the feed, every 50 ms for up to timeout_s.
# inputs: scripts/smoke/leaks.sh bin/vgshell shell/plugins/vgs.themes/Background.qml shell/plugins/vgs.themes/WallpaperState.qml shell/Hosts/BackgroundHost.qml shell/Commons/WatchedFile.qml
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
spawn_display "$sandbox/leak-plant-toplevel.log" "${shell_env[@]}" -- "$sandbox/toplevel" "$lc_class"
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
lc_reports() { shell_crash_reports | grep -c . || true; }
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
expect "control: the crash check names the planted crash once" 1 grep -c -E -- "^crash=[0-9a-z-]+ report=.*/report\\.txt\$" "$lc_crashes"
expect "control: the crash check prints the crash's stack trace" 1 grep -c -E -- "^        #0 " "$lc_crashes"
expect "the crash check leaves no crash reporter window" 0 lc_strays
lc_new_shell() { [[ $shell_qs_pid != "$lc_crashed_pid" && $instance_log != "$lc_crashed_log" ]] && echo new || echo "pid=$shell_qs_pid log=$instance_log"; }
expect "the crash check starts a new shell with its own log" new lc_new_shell
expect "the new shell answers" ok ipc shell ping
lc_check_again() { if shell_crash_check "$sandbox/leak-plant-crash-again.crashes"; then echo none; else echo found; fi; }
expect "a second crash check reads no crash" none lc_check_again

# The empty-record controls: the planted crash's own report, copied to the
# path a reporter with an empty record writes.
lc_empty="$home/.cache/quickshell/crashes/report.txt"
lc_empty_crashes="$sandbox/leak-plant-empty-record.crashes"
lc_report_copy="$sandbox/leak-plant-report.txt"
lc_empty_named() { grep -c -E -- "^crash=empty-instance-record report=.*/crashes/report\\.txt\$" "$lc_empty_crashes" || true; }
lc_report="$(shell_crash_reports | head -n 1)"
if [[ -n $lc_report ]] && cp -- "$lc_report" "$lc_report_copy" && cp -- "$lc_report_copy" "$lc_empty"; then
  spawn_display "$sandbox/leak-plant-reporter.log" "${shell_env[@]}" -- "$sandbox/toplevel" "$shell_reporter_class"
  lc_reporter="$spawn_pid"
  expect_poll "the planted reporter window maps" 1 lc_strays
  if shell_crash_check "$lc_empty_crashes"; then fail "control: the crash check read no crash from an empty-record report"; fi
  expect "control: the crash check names the empty-record crash once, by its form" 1 lc_empty_named
  expect "control: the crash check prints the empty-record crash's stack trace" 1 grep -c -E -- "^        #0 " "$lc_empty_crashes"
  expect "the crash check leaves no window of Quickshell's default class" 0 lc_strays
  expect_poll "the crash check ended the planted reporter" gone lc_comm "$lc_reporter"
  expect "the shell answers after the empty-record crash" ok ipc shell ping
  expect "a crash check after the empty-record one reads no crash" none lc_check_again
  cp -- "$lc_report_copy" "$lc_empty" || fail "the empty-record report could not be written again"
  if shell_crash_check "$lc_empty_crashes"; then fail "control: the crash check read no crash from an empty-record report written again"; fi
  expect "control: the crash check names the empty-record crash written again" 1 lc_empty_named
  expect "the shell answers after the second empty-record crash" ok ipc shell ping
else
  fail "the planted crash's report could not be copied to the empty-record path: $lc_report"
fi

cat >"$lc_plants/leak-plant-rest.sh" <<'SH'
expect "the row starts with the pointer at rest" "10 $((mon_h - 10))" lc_pointer
SH
hover "$((mon_w / 2))" "$((mon_h / 2))" || fail "the pointer could not be moved off its rest"
expect "the pointer is away from its rest before the planted row" "$((mon_w / 2)) $((mon_h / 2))" lc_pointer
expect "control: a row run alone starts with the pointer at rest" 0 lc_planted_alone leak-plant-rest
rest_pointer || fail "the pointer could not be put back at rest"

# The background controls.
lc_bg_image="$lc_plants/background.png"
lc_bg_prior="$lc_plants/backgrounds.json.prior"
lc_hold="$lc_plants/hold"
lc_screen_names() { hypr -j monitors | py_reply 'import json,sys; print(" ".join(m["name"] for m in json.load(sys.stdin)))'; }
# lc_layers_now: leak_layers_state's reading of the per-screen layers now.
lc_layers_now() { local probe layers; probe="$(ipc smoke perScreenLayers)" && layers="$(hypr -j layers)" && leak_layers_state "$probe" "$layers"; }
# lc_hold_names: the state file replaced whole with one naming, for each
# screen, its own held image: $lc_hold/<screen>.png, a FIFO. Qt's
# asynchronous Image reader opens it and blocks in the open, the Image
# Loading, until a writer feeds it the PNG, then reads it to Ready (a
# PySide6 6.11.2 run of such Images under scripts/smoke/gpu-fence.sh on
# 2026-10-11, on this host's Qt 6.11.2; that run also showed that an
# application with an unfed FIFO open does not exit). Each screen holds
# its own FIFO, since one reader takes every write a FIFO gets while it
# is open.
lc_hold_names() {
  python3 - "$bg_state" "$lc_hold" "${lc_screens[@]}" <<'PY'
import json, os, sys
state, hold, names = sys.argv[1], sys.argv[2], sys.argv[3:]
doc = {"schemaVersion": 1, "current": None, "stamp": None, "themes": {},
       "screens": {name: {"path": os.path.join(hold, name + ".png"), "stamp": "row"} for name in names}}
with open(os.path.join(state, "backgrounds.json.tmp"), "w") as f:
    json.dump(doc, f)
os.replace(os.path.join(state, "backgrounds.json.tmp"), os.path.join(state, "backgrounds.json"))
PY
}
# lc_feed: each held image fed the PNG at once, each write bounded by
# timeout_s. Prints `fed`, or `fed=failed status=<n>` with the last
# failed write's status, 124 for a FIFO no reader opened in the bound.
lc_feed() {
  local fifo pid pids=() status=0
  for fifo in "$lc_hold"/*.png; do
    timeout "$timeout_s" cp -- "$lc_bg_image" "$fifo" &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do wait "$pid" || status=$?; done
  if ((status)); then echo "fed=failed status=$status"; else echo fed; fi
}
# lc_feed_after: lc_feed once the end reading restart.end names holds its
# layers reply or its first unsettled layers reading, polled every 50 ms
# for up to timeout_s. Prints lc_feed's line; `fed=bound` when the bound
# passed, and the shell is fed all the same, so no open is left blocked.
lc_feed_after() {
  local dir="" i
  for ((i = 0; i < timeout_s * 20; i++)); do
    [[ -n $dir ]] || read -r dir 2>/dev/null <"$lc_plants/restart.end" || dir=""
    if [[ -n $dir && ( -s $dir/layers || -s $dir/layers.first-unsettled ) ]]; then
      lc_feed
      return
    fi
    sleep 0.05
  done
  lc_feed >/dev/null
  echo fed=bound
}
# lc_restart NAME: planted row NAME, which restarts the shell, with the
# shell it killed noted first, its held images fed by lc_feed_after, and
# the shell the runner started taken up after; its failure count in
# $lc_plants/NAME.failures.
lc_restart() { # NAME
  local killed feeder
  rm -f -- "$lc_plants/restart.end" "$lc_plants/restart.killed"
  shell_memory_note
  lc_feed_after >"$lc_plants/$1.feed" 2>&1 &
  feeder=$!
  lc_planted "$1" >"$lc_plants/$1.failures"
  wait "$feeder" || fail "$1: its feeder exited $?"
  if killed="$(cat -- "$lc_plants/restart.killed")"; then adopt_shell "$killed" || :; else fail "$1: the killed shell's pid is unrecorded"; fi
  expect "$1: the held images are fed once its end reading has read the layers" fed cat -- "$lc_plants/$1.feed"
  expect_poll "$1: the background maps again on every screen" "$lc_screen_count" layer_count vgs:background
}
# lc_waited DIR: `waited` when reading DIR came to rest after its first
# reading found the held background settling and unmapped; its readings
# otherwise.
lc_waited() { # DIR
  local ms first
  ms="$(cat -- "$1/layers.rest-ms" 2>/dev/null)" || ms=unread
  first="$(cat -- "$1/layers.first-unsettled" 2>/dev/null)" || first=none
  if [[ $ms =~ ^[0-9]+$ && $first =~ (^|\ )vgs:background@[^\ ]+\ visible=false\ mapped=false\ settling=vgs\.themes(=unbuilt)?(\ |$) ]]; then
    echo waited
  else
    echo "rest_ms=$ms first_unsettled=[$first] unprobed=[$(cat -- "$1/layers.unprobed" 2>/dev/null || echo none)]"
  fi
}
lc_bg_before="$(layer_count vgs:background)" || lc_bg_before=""
lc_screen_list="$(lc_screen_names)" || lc_screen_list=""
read -r -a lc_screens <<<"$lc_screen_list"
lc_screen_count="${#lc_screens[@]}"
if [[ $lc_bg_before == 0 && $lc_screen_count -gt 0 ]] && mkdir -p -- "$bg_state" && solid_png "$lc_bg_image" 5000 5000 40 120 200; then
  if [[ -e $bg_state/backgrounds.json ]]; then cp -p -- "$bg_state/backgrounds.json" "$lc_bg_prior"; fi
  cat >"$lc_plants/leak-plant-background.sh" <<'SH'
bg_state_names "$lc_bg_image" || fail "the planted background's state file was not written"
expect_poll "the planted background maps on every screen" "$lc_screen_count" layer_count vgs:background
SH
  expect "control: a row that leaves a background layer fails once" 1 lc_planted leak-plant-background
  expect "control: the failure names the layers class and the background" 1 lc_failed leak-plant-background "leaves layers: \\+vgs:background( \\+vgs:background)*"
  sed -n 's/^  FAIL  /    planted fail: /p' -- "$sandbox/leak-plant-background.log"

  # The cause, judged by nothing: with that background configured, the
  # shell stopped and started as overlay-capture ends, and the per-screen
  # layers read from start_shell's return, once the shell answered ping,
  # until they rest.
  mkdir -p -- "$lc_plants/cause"
  stop_shell || :
  start_shell "$repo" "$sandbox/leak-check-cause-qs.log" || fail "the shell starts again with the background configured"
  leak_layers_rest "$lc_plants/cause" || :
  echo "  restart_rest_ms_after_start_shell=$(cat -- "$lc_plants/cause/layers.rest-ms" 2>/dev/null || echo unread) first_unsettled=[$(cat -- "$lc_plants/cause/layers.first-unsettled" 2>/dev/null || echo none)]"

  # A row that restarts the shell with each screen's background held in
  # its FIFO: the runner starts the shell again after a SIGKILL, and the
  # row ends once the shell answers and maps its bars, where start_shell
  # returns. lc_feed_after feeds the new shell's images only once the end
  # reading has read the layers or found them unsettled, so that reading
  # meets the background unmapped whatever the decode's speed. A stop and
  # start would leave this row a runner the planted row's subshell
  # started, which it cannot wait on. The two copies differ in the wait
  # alone.
  mkdir -p -- "$lc_hold"
  for lc_screen in "${lc_screens[@]}"; do mkfifo -- "$lc_hold/$lc_screen.png" || fail "the held image for $lc_screen was not made"; done
  lc_hold_names || fail "the held images' state file was not written"
  expect "the running shell reads the held images" fed lc_feed
  expect_poll "the held background is at rest" rest lc_layers_now
  cat >"$lc_plants/leak-plant-restart.sh" <<'SH'
leak_dir_next
printf '%s\n' "$leak_next" >"$lc_plants/restart.end"
printf '%s\n' "$shell_qs_pid" >"$lc_plants/restart.killed"
lc_restart_bars="$(bar_count)" || fail "the bar count is unreadable before the planted restart"
kill -KILL -- "$shell_qs_pid" || fail "the planted restart's kill failed"
adopt_shell "$(cat -- "$lc_plants/restart.killed")" || fail "the runner did not start the shell again"
expect_poll "the restarted shell maps its bars again" "$lc_restart_bars" bar_count
SH
  { printf 'leak_layers_rest() { return 0; }\n'; cat -- "$lc_plants/leak-plant-restart.sh"; } >"$lc_plants/leak-plant-restart-unwaited.sh"

  lc_restart leak-plant-restart
  lc_end="$(cat -- "$lc_plants/restart.end")" || lc_end="$lc_plants/restart.end-unread"
  expect "a row that restarts the shell with a background configured fails nothing" 0 cat -- "$lc_plants/leak-plant-restart.failures"
  sed -n 's/^  FAIL  /    planted fail: /p' -- "$sandbox/leak-plant-restart.log"
  expect "control: its end reading found the held background settling and waited for rest" waited lc_waited "$lc_end"
  echo "  leak_layers_rest_ms=$(cat -- "$lc_end/layers.rest-ms" 2>/dev/null || echo unread) first_unsettled=[$(cat -- "$lc_end/layers.first-unsettled" 2>/dev/null || echo none)]"
  lc_restart leak-plant-restart-unwaited
  expect "control: the restart read with no wait for rest fails once" 1 cat -- "$lc_plants/leak-plant-restart-unwaited.failures"
  expect "control: the failure names the background its end reading missed" 1 lc_failed leak-plant-restart-unwaited "leaves layers: -vgs:background( -vgs:background)*"
  sed -n 's/^  FAIL  /    planted fail: /p' -- "$sandbox/leak-plant-restart-unwaited.log"

  if [[ -e $lc_bg_prior ]]; then mv -T -- "$lc_bg_prior" "$bg_state/backgrounds.json"; else rm -f -- "${bg_state:?}/backgrounds.json"; fi
  expect_poll "the background layers are as they were" "$lc_bg_before" layer_count vgs:background
  rm -f -- "${lc_plants:?}/background.png" "${lc_plants:?}/hold"/*.png
  rmdir -- "${lc_plants:?}/hold" || fail "the held images' directory was not removed"

  # The ended-shell control: the planted row's shell ends and the row takes
  # up no other, as a row does whose shell exits under it. The runner
  # starts a shell again, and the row waits for its bars so the layers
  # read as they were; the shell class alone is left. The shell it kills
  # is noted first, as lc_restart notes its own, so rows/diagnostics.sh
  # reads every shell the run started.
  cat >"$lc_plants/leak-plant-ended.sh" <<'SH'
printf '%s\n' "$shell_qs_pid" >"$lc_plants/ended.killed"
lc_ended_bars="$(bar_count)" || fail "the bar count is unreadable before the planted end"
kill -KILL -- "$shell_qs_pid" || fail "the planted end's kill failed"
expect "the runner starts a shell again after the planted end" back relaunched_within "$shell_qs_pid" 20000
expect_poll "the runner's shell answers" ok ipc shell ping
expect_poll "the runner's shell maps its bars again" "$lc_ended_bars" bar_count
SH
  shell_memory_note
  expect "control: a row whose shell ended under it fails once" 1 lc_planted leak-plant-ended
  expect "control: the failure names the shell class and the runner's exit line" 1 lc_failed leak-plant-ended "leaves shell: \\+environ=unreadable runner=\\[vgshell: shell=exited status=137 [^]]*\\] -.*"
  sed -n 's/^  FAIL  /    planted fail: /p' -- "$sandbox/leak-plant-ended.log"
  if lc_ended="$(cat -- "$lc_plants/ended.killed")"; then adopt_shell "$lc_ended" || :; else fail "the ended shell's pid is unrecorded"; fi
  # The runner counts the kills above as one relaunch streak in its log,
  # so the rows after get a runner and a log of their own, as
  # rows/key-passthrough.sh ends.
  stop_shell || :
  start_shell "$repo" "$sandbox/leak-check-final-qs.log" || fail "leak-check leaves a live shell for the rows after it"
else
  fail "the background controls need no background mapped and a readable screen list: backgrounds=$lc_bg_before screens=[$lc_screen_list]"
fi
