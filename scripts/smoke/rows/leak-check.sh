# The leak check scripts/smoke/leaks.sh runs at every row's end, and its
# controls. Raw detector fixtures run privately, retain their defect for
# inspection and undo it afterward. Restoration fixtures run in the living
# Bash world: each client or foreign-layer plant fails before one restore,
# and its successor compares with the planting row's immutable baseline.
# The restoration-disabled control must fail that same successor. The plants:
# - clients: a toplevel maps, unfocused under a window rule with
#   no_initial_focus;
# - focus: a click focuses that toplevel;
# - submap: a dispatch into a submap this row defines through
#   `hyprctl eval`, since Hyprland enters no submap it has not registered;
# - layers: a Wayland output, which gets a bar; and a vgs.themes
#   background, a state file naming a 5000x5000 image, which maps one on
#   every screen;
# - options: one live option set through `hyprctl eval`;
# - variables: shell_start_path assigned;
# - shell: shell_qs_pid pointed at a process holding the shell's
#   environment with a PATH that holds no stand-in, which breaks
#   devices_guard's path-shim rule;
# - shim: a file written into the shell's stand-in directory;
# - plugins: a fixture enabled without restoring its enablement;
# - bus-names: a restart with no notification holder loses the name,
#   while a restart with a holder keeps the shell relation unassisted.
# A planted row whose header declares `# leaves: options` sets the same
# option, fails nothing and prints what it left; a header word that names
# no class fails its row once; a row after which the compositor answers
# nothing fails once for each class read through it, as unreadable.
# The row first reads the harness seed's Themes disabled, then enables
# Themes for its background controls. A theme apply
# with Themes off, from an absent selection, passes its boundary, and its
# successor starts at the plant's start.
# Crash detection leaves the shell and reporter untouched for the raw end
# reading. The boundary retains the original crash/client failures, removes
# the proved reporter and starts the run tree, even after a row names a
# mutant tree. Empty-instance reports retain their rewrite/deduplication
# controls. Holder-enabled restart assertions run before managed teardown;
# a product mutant stays failed after successful restoration. A fault
# table plants one fault per restore phase (a stopped shell, a forced name
# release, an overrun stop, a gone runner, a restarted shell that dies, a
# managed step that cannot finish, a held lock): each costs its own row at
# most, and the successor starts at the planting row's start. Two rows pin
# the stop's 10 s TERM threshold. A layer whose owner process is gone, kept by a
# holder of its connection, reads unreadable at once under its own key, and
# the holder diagnostic names that holder.
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
# files, for the feed, every 50 ms for up to timeout_s. Notification owner
# waits poll every 0.2 s at the harness's state-wait bound.
# inputs: scripts/smoke/fixtures/plugins/acme.probe/* shell/Core/NotificationHub.qml shell/Core/Capabilities.qml scripts/smoke/leaks.sh scripts/smoke/display-record.sh bin/vgshell shell/plugins/vgs.themes/Background.qml shell/plugins/vgs.themes/WallpaperState.qml shell/Hosts/BackgroundHost.qml shell/Commons/WatchedFile.qml scripts/smoke/rows/capabilities.sh
set -euo pipefail
expect "the seed starts Themes disabled" False plugin_enabled vgs.themes
leak_plugin_setup vgs.themes true || { fail "leak-check: fixture precondition failed"; return 1; }
lc_plants="$sandbox/leak-plants"
mkdir -p -- "$lc_plants"
lc_class=vgs-leak-quiet
lc_output=VGS-LEAK
lc_option=general:gaps_workspaces

# lc_planted NAME: the failure count of planted row NAME, its lines in
# $sandbox/NAME.log.
lc_planted() { # NAME
  (failures=0 behaviour_failures=0
   # Private detector fixtures keep their raw defects for assertions below.
   # Ordinary row restoration is proved by lc_boundary in the same world.
   leak_managed_delta() {
     if [[ $2 == persisted-inputs ]]; then printf 'qml-smoke: boundary row=%s class=%s delta=%s\n' "$1" "$2" "$3"
     else fail "$1: leaves $2: $3"; fi
   }
   leak_row_restore() { display_record_call row-release "${leak_starts[-1]}" >/dev/null; unset 'leak_starts[-1]'; }
   smoke_row "$1" "$lc_plants" >"$sandbox/$1.log" 2>&1; echo "$failures")
}
lc_boundary() { # NAME
  local saved_failures="$failures" saved_behaviour="$behaviour_failures"
  failures=0 behaviour_failures=0
  smoke_row "$1" "$lc_plants" >"$sandbox/$1.log" 2>&1
  lc_result="$failures"
  failures="$saved_failures" behaviour_failures="$saved_behaviour"
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
expect "the planted client's no-focus precondition is installed" ok hypr eval "hl.window_rule({ name = \"$lc_class\", match = { class = \"^$lc_class\$\" }, no_initial_focus = true })"
lc_toplevel_log="$sandbox/leak-plant-toplevel-$BASHPID-$leak_seq.log"
display_stream_kind=probe
spawn_display "$lc_toplevel_log" "${shell_env[@]}" -- "$sandbox/toplevel" "$lc_class"
printf '%s\n' "$spawn_pid" >"$lc_plants/toplevel.pid"
expect_poll "the planted toplevel maps" 1 grep -c -x -F -- "mapped $lc_class" "$lc_toplevel_log"
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

# Unlike the detector fixtures above, these run the real boundary in this
# Bash world. Their successor targets the planting row's original reading.
cat >"$lc_plants/leak-successor.sh" <<'SH'
expect "the successor starts at the planting row's immutable baseline" "" leak_judge /dev/null "$lc_restore_baseline" "${leak_starts[-1]}"
expect "the successor retains the literal writer input unit" 0 lc_input_equal "$lc_restore_baseline" "${leak_starts[-1]}"
SH
lc_input_equal() { local status=0; leak_input_compare "$1" "$2" || status=$?; printf '%s\n' "$status"; }
leak_dir_next
lc_restore_baseline="$leak_next"
lc_boundary leak-plant-clients
expect "a restored client plant keeps its original failure" 1 printf '%s\n' "$lc_result"
expect "the restored client plant records one transaction" 1 grep -c '^qml-smoke: restore=begin ' "$sandbox/leak-plant-clients.log"
expect "restoration closes the newly owned client" 0 lc_quiet_count
lc_boundary leak-successor
expect "the client plant's successor passes against the original baseline" 0 printf '%s\n' "$lc_result"

mkdir -p "$lc_plants/foreign-layer"
cat >"$lc_plants/foreign-layer/shell.qml" <<'QML'
import Quickshell
import Quickshell.Wayland
PanelWindow {
    anchors { top: true; left: true }
    implicitWidth: 10
    implicitHeight: 10
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "vgs:leak-foreign"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: true
}
QML
cat >"$lc_plants/leak-foreign-layer.sh" <<'SH'
display_stream_kind=probe
spawn_display "$sandbox/leak-foreign-layer.log" "${shell_env[@]}" -- qs -p "$lc_plants/foreign-layer"
expect_poll "the separate fixture owner maps its layer" 1 layer_count vgs:leak-foreign
SH
leak_dir_next
lc_restore_baseline="$leak_next"
lc_boundary leak-foreign-layer
expect "a restored foreign layer keeps its original failure" 1 printf '%s\n' "$lc_result"
expect "the layer plant records owner diagnostics before its one restore" true python3 - "$sandbox/leak-foreign-layer.log" <<'PY'
import sys
s=open(sys.argv[1]).read()
failure=s.index('FAIL  leak-foreign-layer: leaves layers:')
owner=s.index('layer-owner ', failure)
restore=s.index('qml-smoke: restore=begin ')
print(str(failure < owner < restore and s.count('qml-smoke: restore=begin ')==1).lower())
PY
expect "restoration closes the foreign layer" 0 layer_count vgs:leak-foreign
lc_boundary leak-successor
expect "the layer plant's successor passes against the original baseline" 0 printf '%s\n' "$lc_result"

lc_disabled_successor() {
  (failures=0 behaviour_failures=0
   leak_row_restore() { display_record_call row-release "${leak_starts[-1]}" >/dev/null; unset 'leak_starts[-1]'; }
   leak_dir_next; lc_restore_baseline="$leak_next"
   smoke_row leak-plant-clients "$lc_plants" >"$sandbox/leak-disabled-plant.log" 2>&1
   smoke_row leak-successor "$lc_plants" >"$sandbox/leak-disabled-successor.log" 2>&1
   local result="$failures"
   display_record_call stop-process "$(<"$lc_plants/toplevel.pid")" "$BASHPID" "$stop_lock_wait_s" >/dev/null || exit 1
   printf '%s\n' "$result")
}
expect "control: without restoration the original-baseline successor fails too" 2 lc_disabled_successor
expect_poll "the disabled-restoration control closes its owned fixture" 0 lc_quiet_count

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
expect "the planted output is created" ok create_output "$lc_output"
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
# Changing the identity under test also reclassifies the real shell's bus
# names; this plant isolates the environment guard from that separate class.
leak_classes=(shell)
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

# Capture a real owned stop, then plant its layer only in the compositor
# reply at another row's end. This tests attribution, not a Wayland leak.
lc_stopped_pid="$shell_qs_pid"
hypr -j layers >"$lc_plants/stopped.layers"
lc_stopped_layer="$(py_reply 'import json,sys
layers=json.load(sys.stdin); pid=int(sys.argv[1])
print(json.dumps(next(([screen,level,l] for screen,m in layers.items() for level,ls in m["levels"].items() for l in ls if l["pid"]==pid and l["namespace"]=="vgs:bar"), None)))' "$lc_stopped_pid" <"$lc_plants/stopped.layers")"
stop_shell || fail "the diagnostic control cannot acknowledge its owned stop"
if ! lc_stop_key="$(py_reply 'import json,sys
events=[json.loads(line) for line in sys.stdin]; pid=sys.argv[1]
print(next((e["data"]["layerStop"]["stop"] for e in reversed(events) if e["kind"] in ("local-owner-end","unobserved-adoption-end") and e["data"].get("layerStop",{}).get("instance",{}).get("pid")==pid), "unobserved"))' "$lc_stopped_pid" <"$display_record_dir/events.jsonl")"; then
  fail "the diagnostic control cannot read its acknowledged stop"
fi
start_shell "$repo" "$sandbox/leak-check-owner-qs.log" || fail "the diagnostic control restores the shell"
if [[ $lc_stopped_layer == \[* && $lc_stop_key == owner-* ]]; then
  cat >"$lc_plants/leak-plant-stopped-layer.sh" <<'SH'
leak_dir_next
printf '%s\n' "$leak_next" >"$lc_plants/stopped.end"
lc_native_hypr="$(declare -f hypr)"
eval "lc_native_$lc_native_hypr"
hypr() {
  if [[ $* == '-j layers' ]]; then
    lc_native_hypr "$@" | py_reply 'import json,sys
layers=json.load(sys.stdin); screen,level,layer=json.loads(sys.argv[1])
layers[screen]["levels"][level].append(layer)
print(json.dumps(layers))' "$lc_stopped_layer"
  else
    lc_native_hypr "$@"
  fi
}
SH
  expect "control: a stopped instance's planted surviving layer fails its end reading once" 1 lc_planted leak-plant-stopped-layer
  lc_end="$(cat -- "$lc_plants/stopped.end")"
  expect "control: the stopped layer keeps its raw layer reply and probe" true python3 -c 'import json,pathlib,sys
root=pathlib.Path(sys.argv[1]); expected=json.loads(sys.argv[2])[2]
layers=json.loads((root/"layers.raw").read_text())
print(str(isinstance(json.loads((root/"layers.probe").read_text()),list) and any(l["address"]==expected["address"] and l["pid"]==expected["pid"] for m in layers.values() for ls in m["levels"].values() for l in ls)).lower())' "$lc_end" "$lc_stopped_layer" </dev/null
  expect "control: the stopped layer reports its independent PID, address and acknowledged stop" true py_reply 'import json,sys
expected=json.loads(sys.argv[1])[2]; stop=sys.argv[2]
reports=[json.loads(line.split("layer-owner ",1)[1]) for line in sys.stdin if "layer-owner {" in line]
print(str(any(l["pid"]==expected["pid"] and l["address"]==expected["address"] and l["stop"]==stop and l["liveness"]["status"] in ("gone","ended") for r in reports for l in r["layers"])).lower())' "$lc_stopped_layer" "$lc_stop_key" <"$sandbox/leak-plant-stopped-layer.log"
  control_output "$sandbox/leak-plant-stopped-layer.log"

  # The same namespace still satisfies legacy settlement. Its diagnostic
  # hostOwner must depend on PID, and must never alter that verdict.
  lc_foreign="$lc_plants/foreign"
  mkdir -p -- "$lc_foreign"
  python3 -c 'import json,pathlib,sys
screen,level,layer=json.loads(sys.argv[1]); root=pathlib.Path(sys.argv[2])
(root/"layers.raw").write_text(json.dumps({screen:{"levels":{level:[layer]}}}))
(root/"layers.probe").write_text(json.dumps([dict(screen=screen,namespace=layer["namespace"],visible=True,settling=[])]))' "$lc_stopped_layer" "$lc_foreign" </dev/null
  expect "control: foreign PID ownership leaves the namespace settlement verdict unchanged" rest leak_layers_state "$(<"$lc_foreign/layers.probe")" "$(<"$lc_foreign/layers.raw")"
  lc_foreign_report="$(display_record_call layer-reading "$lc_foreign" "$shell_qs_pid")"
  expect "control: a foreign PID is not the live host's own mapping" false py_reply 'import json,sys; print(str(json.load(sys.stdin)["layers"][0]["hostOwner"]).lower())' <<<"$lc_foreign_report"
  expect "control: the diagnostic names the PID ownership mismatch" true py_reply 'import json,sys; print(str(json.load(sys.stdin)["layers"][0]["ownershipMismatch"]).lower())' <<<"$lc_foreign_report"
  lc_same_report="$(display_record_call layer-reading "$lc_foreign" "$lc_stopped_pid")"
  expect "control: matching PID ownership belongs to the named host" true py_reply 'import json,sys; print(str(json.load(sys.stdin)["layers"][0]["hostOwner"]).lower())' <<<"$lc_same_report"
  printf 'unreadable-probe\n' >"$lc_foreign/layers.probe"
  lc_unreadable_report="$(display_record_call layer-reading "$lc_foreign" "$shell_qs_pid")"
  expect "control: an unreadable probe keeps the layer identities" true py_reply 'import json,sys
r=json.load(sys.stdin); print(str(r.get("probeStatus")=="unreadable" and r["layers"][0]["pid"]==int(sys.argv[1])).lower())' "$lc_stopped_pid" <<<"$lc_unreadable_report"
else
  fail "the stopped-layer control needs an owned bar and stop: layer=[$lc_stopped_layer] stop=$lc_stop_key"
fi

cat >"$lc_plants/leak-plant-unsettled-layer.sh" <<'SH'
leak_dir_next
printf '%s\n' "$leak_next" >"$lc_plants/unsettled.end"
lc_native_ipc="$(declare -f ipc)"
eval "lc_native_$lc_native_ipc"
ipc() {
  if [[ $1 == smoke && $2 == perScreenLayers ]]; then printf '[{}]\n'; else lc_native_ipc "$@"; fi
}
SH
expect "control: an unjudgeable layer probe keeps the existing unreadable failure" 1 lc_planted leak-plant-unsettled-layer
lc_end="$(cat -- "$lc_plants/unsettled.end")"
expect "control: the unsettled boundary retains its exact raw layers and probe" true python3 -c 'import json,pathlib,sys
root=pathlib.Path(sys.argv[1])
print(str(json.loads((root/"layers.probe").read_text())==[{}] and isinstance(json.loads((root/"layers.raw").read_text()),dict) and (root/"layers.unsettled").is_file() and not (root/"layers").exists()).lower())' "$lc_end" </dev/null
printf ':\n' >"$lc_plants/leak-plant-owner-pass.sh"
expect "a passing boundary still fails nothing" 0 lc_planted leak-plant-owner-pass
expect "a passing boundary prints no owner diagnostic" 0 python3 -c 'import sys; print(sum("layer-owner " in line for line in sys.stdin))' <"$sandbox/leak-plant-owner-pass.log"

# Drive the actual recorder with a native-query fixture. Namespace-only
# close events cannot select one of two addresses without a later reply.
display_record_program >"$lc_plants/recorder.py"
if python3 - "$lc_plants/recorder.py" "$lc_plants/record-control" <<'PY'
import json, os, pathlib, runpy, socket, subprocess, sys
module=runpy.run_path(sys.argv[1]); root=pathlib.Path(sys.argv[2]); root.mkdir()
r=module["Record"](root)
child=subprocess.Popen([sys.executable,"-c","import time; time.sleep(600)"],env={"PATH":os.environ["PATH"]})
try:
    def mark(*args):
        with socket.socket(socket.AF_UNIX,socket.SOCK_SEQPACKET) as client:
            with module["socket_name"](root/"control") as name:
                client.connect(name)
            client.sendall(json.dumps(["mark",*args]).encode())
            r.control()
            assert json.loads(client.recv(65536))["ok"], "mark-accepted"
    pid=str(child.pid); runner=str(os.getpid())
    for case, recorded, runner_match, generation_match, supplied, expected in [
        ("known", True, True, True, "/instance/current/log.log", "/instance/current/log.log"),
        ("adopted-stale-log", False, True, True, "/instance/previous/log.log", None),
        ("other-runner", True, False, True, "/instance/previous/log.log", None),
        ("reused-pid", True, True, False, "/instance/previous/log.log", None),
        ("missing-log", True, True, True, "", None),
    ]:
        r.shell_owners.pop(pid,None)
        owner=r.owner_context(runner)
        if recorded:
            mark("shell-identity",runner if runner_match else pid,pid,"/tree/current","/launch/current.log")
            if not generation_match:
                r.shell_owners[pid]["identity"]["startTicks"]="previous-generation"
        mark("stop-shell",owner,pid,supplied,"1")
        instance=r.owner_contexts.pop(owner)["stopInstance"]
        assert instance["pid"]==pid and instance["instanceLog"]==expected, case
        assert instance["instanceLogStatus"]==("bound" if expected else "unavailable"), case
        assert (instance["instanceLogReason"] is None)==bool(expected), case
        assert r.shell_owners[pid]==instance, case
    pid=str(child.pid); owner=r.owner_context(pid)
    r.owner_contexts[owner].update(stopShell=pid,stopInstance=dict(pid=pid,snapshot=module["process_binding"](pid)))
    child.terminate(); child.wait()
    ended_owner=r.owner_context(runner)
    mark("stop-shell",ended_owner,pid,"/instance/current/log.log","1")
    ended_instance=r.owner_contexts.pop(ended_owner)["stopInstance"]
    assert ended_instance["instanceLog"]=="/instance/current/log.log" and ended_instance["snapshot"]["status"]=="gone", "known-ended-generation"
    def raw(addresses):
        return json.dumps({"CONTROL":{"levels":{"2":[dict(address=a,namespace="vgs:bar",pid=int(pid)) for a in addresses]}}})
    r.layers_query=lambda:raw(["0xa","0xb"])
    r.end_owner(owner,pid)
    assert set(r.layer_stops)=={"0xa","0xb"}, "stop-addresses"
    rows=[json.loads(line) for line in (root/"events.jsonl").read_text().splitlines()]
    assert rows[-1]["data"]["layerStop"]["stillListed"] is True, "stop-still-listed"
    r.layers_query=lambda:"unreadable:fixture"
    r.parse_line(dict(source="nested-ipc",kind="ipc"),b"closelayer>>vgs:bar")
    assert set(r.layer_stops)=={"0xa","0xb"}, "unreadable-stays-pending"
    r.layers_query=lambda:raw(["0xb"])
    r.parse_line(dict(source="nested-ipc",kind="ipc"),b"closelayer>>vgs:bar")
    assert set(r.layer_stops)=={"0xb"}, "still-present-stays-pending"
    rows=[json.loads(line) for line in (root/"events.jsonl").read_text().splitlines()]
    joined=[e for e in rows if e["kind"]=="layer-close-join"]
    assert len(joined)==1 and joined[0]["data"]["address"]=="0xa" and joined[0]["data"]["stop"]==owner, "close-address-stop"
    assert joined[0]["data"]["closeReceipt"] < joined[0]["data"]["snapshotReceipt"], "receipt-order"
    r.layer_stops["0xa"]=joined[0]["data"]
    r.layers_query=lambda:raw([])
    r.parse_line(dict(source="nested-ipc",kind="ipc"),b"closelayer>>vgs:bar")
    rows=[json.loads(line) for line in (root/"events.jsonl").read_text().splitlines()]
    joined=[e for e in rows if e["kind"]=="layer-close-join"]
    assert len(joined)==3 and all(e["data"]["closeAttribution"]=="ambiguous" for e in joined[-2:]), "namespace-close-ambiguity"
    pid=str(os.getpid()); current=module["process_binding"](pid)
    assert current["status"]=="live", "live-generation-prerequisite"
    r.shell_owners[pid]=dict(pid=pid,identity=dict(startTicks="other-generation"),stop=owner)
    r.layer_stops["0xb"]=dict(address="0xb",namespace="vgs:bar",pid=int(pid),stop=owner,instance=dict(snapshot=dict(startTicks="other-generation")))
    report=r.layers_report(raw(["0xb"]),pid)
    assert report["layers"][0]["stop"]=="none" and report["layers"][0]["instance"]["status"]=="pid-reused", "reused-pid-cannot-inherit-stop"
    r.layers_query=lambda:raw(["0xb"])
    r.parse_line(dict(source="nested-ipc",kind="ipc"),b"closelayer>>vgs:bar")
    assert not r.layer_stops, "observed-new-generation-retires-old-join"
    print("recorder-layer-controls=proved")
finally:
    if child.poll() is None:
        child.terminate(); child.wait()
    r.output.close(); r.server.close(); r.selector.close()
    if r.notify_fd is not None:
        os.close(r.notify_fd)
PY
then
  ok "control: recorder joins only the absent stopped address and keeps unreadable evidence pending"
else
  fail "the recorder layer identity control failed"
fi

# Detection is reporting-only. Each planted crash then uses the real
# boundary, preserving the original reporter and a run-tree restart.
lc_ran() { local secs; secs="$(ps -o etimes= -p "$shell_qs_pid")" || { echo gone; return; }; secs="${secs// /}"; if ((secs >= 11)); then echo ran; else echo "secs=$secs"; fi; }
lc_reports() { shell_crash_reports | grep -c . || true; }
lc_strays() { shell_strays | grep -c . || true; }
lc_check_again() { if shell_crash_check "$sandbox/leak-plant-crash-again.crashes"; then echo none; else echo found; fi; }
cat >"$lc_plants/leak-actual-crash.sh" <<'SH'
lc_reports_before="$(lc_reports)"
expect_poll "the shell has run past Quickshell's restart floor" ran lc_ran
lc_crashed_pid="$shell_qs_pid"
lc_crashed_log="$instance_log"
shell_memory_note
kill -SEGV -- "$shell_qs_pid" || fail "the planted crash signal was not sent"
expect_poll "the planted crash leaves a crash report" "$((lc_reports_before + 1))" lc_reports
expect_poll "the planted crash maps Quickshell's crash reporter window" 1 lc_strays
if shell_crash_check "$sandbox/leak-detected-crash.crashes"; then fail "the detector missed the planted crash"; fi
expect "detection keeps the reporter for the raw snapshot" 1 lc_strays
expect "detection keeps the shell identity unchanged" "$lc_crashed_pid" printf '%s\n' "$shell_qs_pid"
shell_tree="$sandbox/row-final-mutant"
SH
lc_boundary leak-actual-crash
expect "the actual crash remains failed after cleanup" true python3 -c 'import sys; print(str(int(sys.argv[1]) > 0).lower())' "$lc_result"
expect "the detector names the planted crash once" 1 grep -c -E -- '^crash=[0-9a-z-]+ report=.*/report\.txt$' "$sandbox/leak-detected-crash.crashes"
expect "the detector preserves the crash stack trace" 1 grep -c -E -- '^        #0 ' "$sandbox/leak-detected-crash.crashes"
expect "the boundary removes the actual reporter" 0 lc_strays
expect "the boundary restarts the run tree, not the row's final mutant" "$repo" printf '%s\n' "$shell_tree"
expect "the crash has a new shell and log" true python3 -c 'import sys; print(str(sys.argv[1] != sys.argv[2]).lower())' "$shell_qs_pid:$instance_log" "$lc_crashed_pid:$lc_crashed_log"
expect "the raw crash evidence precedes one restoration" true python3 - "$sandbox/leak-actual-crash.log" <<'PYCRASH'
import sys
s=open(sys.argv[1]).read()
print(str('the shell crashed: crash=' in s and 'leaves clients:' in s and s.index('leaves clients:') < s.index('restore=begin') and s.count('restore=begin') == 1).lower())
PYCRASH
expect "a second crash check reads no crash" none lc_check_again

# Quickshell can rewrite the single empty-instance report. Detect each
# rewrite once, without cleaning before the immutable end reading.
lc_empty="$home/.cache/quickshell/crashes/report.txt"
lc_report_copy="$sandbox/leak-plant-report.txt"
lc_report="$(shell_crash_reports | head -n 1)"
cp -- "$lc_report" "$lc_report_copy"
cat >"$lc_plants/leak-empty-crash.sh" <<'SH'
cp -- "$lc_report_copy" "$lc_empty"
display_stream_kind=probe
spawn_display "$sandbox/leak-plant-reporter-$leak_seq.log" "${shell_env[@]}" -- "$sandbox/toplevel" "$shell_reporter_class"
expect_poll "the planted empty-record reporter maps" 1 lc_strays
if shell_crash_check "$sandbox/leak-empty-detected.crashes"; then fail "the empty-record detector missed its report"; fi
expect "empty-record detection leaves its reporter mapped" 1 lc_strays
SH
for lc_empty_round in first rewritten; do
  lc_boundary leak-empty-crash
  expect "the $lc_empty_round empty-record detection names its report once" 1 grep -c -E -- '^crash=empty-instance-record report=.*/crashes/report\.txt$' "$sandbox/leak-empty-detected.crashes"
  expect "the $lc_empty_round empty-record detection preserves the crash stack trace" 1 grep -c -E -- '^        #0 ' "$sandbox/leak-empty-detected.crashes"
  expect "the $lc_empty_round empty-record report remains failed" true python3 -c 'import sys; print(str(int(sys.argv[1]) > 0).lower())' "$lc_result"
  expect "the $lc_empty_round empty-record reporter is removed by the boundary" 0 lc_strays
  expect "the $lc_empty_round empty-record report is not counted twice" none lc_check_again
done

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
# This control deliberately keeps a dead shell identity. Its environment
# assertion is independent of names now held by the runner's replacement.
leak_classes=(shell)
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

# Reproduce input + enablement + process-lifetime name coupling through
# the ordinary living boundary. These are explicit outer fixture inputs,
# acquired before the planting row's immutable start, never start/stop repair.
lc_selection_image="$lc_plants/selection.png"
lc_selection_baseline="$lc_plants/selection-baseline.png"
solid_png "$lc_selection_image" 32 32 40 120 200 || fail "the selection plant image is available"
solid_png "$lc_selection_baseline" 32 32 120 40 200 || fail "the populated baseline image is available"
lc_sentinel_path="$home/.config/vgshell/themes/leak-sentinel"
lc_sentinel_owned=false
lc_sentinel_identity=""
lc_sentinel_state() {
  python3 - "$lc_sentinel_path" <<'PY'
import os,sys
try:
    os.lstat(sys.argv[1])
except FileNotFoundError:
    print('absent')
else:
    print('present')
PY
}
lc_sentinel_acquire() {
  [[ $lc_sentinel_owned == false ]] || { printf 'leak-check: sentinel=acquire cause=already-owned\n' >&2; return 1; }
  mkdir -p -- "${lc_sentinel_path%/*}" || return 1
  mkdir -- "$lc_sentinel_path" || return 1
  lc_sentinel_owned=true lc_sentinel_identity=""
  # The current row owns command-error release. Process exit ends this
  # world; its existing D112 owner retains/removes the whole acquired root.
  smoke_row_abandon=(lc_sentinel_release)
  lc_sentinel_identity="$(stat -c '%d:%i:%u' -- "$lc_sentinel_path")" || return 1
  printf '%s\n' '{"schemaVersion":1,"name":"leak-sentinel","tokens":{}}' >"$lc_sentinel_path/theme.json" || return 1
}
lc_sentinel_release() {
  [[ $lc_sentinel_owned == true ]] || return 0
  local identity canonical state
  state="$(lc_sentinel_state)" || return 1
  if [[ $state != absent ]]; then
    [[ -n $lc_sentinel_identity && -d $lc_sentinel_path && ! -L $lc_sentinel_path ]] || { printf 'leak-check: sentinel=release cause=unbound-or-unsafe-type path=%s\n' "$lc_sentinel_path" >&2; return 1; }
    identity="$(stat -c '%d:%i:%u' -- "$lc_sentinel_path")" || return 1
    canonical="$(realpath -e -- "$lc_sentinel_path")" || return 1
    [[ $identity == "$lc_sentinel_identity" && $canonical == "$lc_sentinel_path" ]] || { printf 'leak-check: sentinel=release cause=changed-path expected=%s actual=%s canonical=%s\n' "$lc_sentinel_identity" "$identity" "$canonical" >&2; return 1; }
    # Delete only the known regular manifest. An unexpected entry leaves
    # rmdir failed; no recursive removal can consume another fixture.
    if [[ -e $lc_sentinel_path/theme.json || -L $lc_sentinel_path/theme.json ]]; then
      [[ -f $lc_sentinel_path/theme.json && ! -L $lc_sentinel_path/theme.json ]] || { printf 'leak-check: sentinel=release cause=unexpected-manifest path=%s\n' "$lc_sentinel_path" >&2; return 1; }
      rm -- "$lc_sentinel_path/theme.json" || return 1
    fi
    rmdir -- "$lc_sentinel_path" || return 1
  fi
  lc_sentinel_owned=false lc_sentinel_identity=""
  smoke_row_abandon=()
}

# Each real row returns before the observer checks its fixture lifetime.
# The deliberately unreleased input proves that observer rejects leftovers;
# the same creator then releases it before another case may acquire it.
cat >"$lc_plants/leak-sentinel-case.sh" <<'SH'
lc_sentinel_acquire
case "$lc_sentinel_mode" in
  pass) : ;;
  assertion) fail "sentinel-lifetime planted assertion" ;;
  command) return 23 ;;
  unreleased) return 0 ;;
  *) return 1 ;;
esac
lc_sentinel_release
SH
for lc_sentinel_mode in pass assertion command unreleased; do
  lc_sentinel_row="leak-sentinel-$lc_sentinel_mode"
  cp -- "$lc_plants/leak-sentinel-case.sh" "$lc_plants/$lc_sentinel_row.sh"
  lc_boundary "$lc_sentinel_row"
  case "$lc_sentinel_mode" in
    pass|unreleased) expect "$lc_sentinel_mode fixture row has no assertion failure" 0 printf '%s\n' "$lc_result" ;;
    assertion|command) expect "$lc_sentinel_mode fixture row preserves its original failure" 1 printf '%s\n' "$lc_result" ;;
  esac
  if [[ $lc_sentinel_mode == unreleased ]]; then
    expect "control: the after-row observer rejects an unreleased sentinel" present lc_sentinel_state
    lc_sentinel_release || { fail "the sentinel control cannot release its acquired fixture"; return 1; }
  fi
  expect "after the $lc_sentinel_mode Leak Check fixture row no sentinel remains" absent lc_sentinel_state
done
expect "the failed-command fixture uses the original command-error route" 1 lc_failed leak-sentinel-command 'a command outside every check failed status=23, .*'
lc_sentinel_acquire || { fail "the preservation case cannot acquire its sentinel"; return 1; }
lc_fixture_inventory() {
  python3 - "$home/.config/vgshell" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1])
config=json.loads((root/'shell.json').read_bytes())
config.pop('disabledPlugins',None)
files={}
for item in ('plugins/acme.probe','plugins/acme.bare','plugins/acme.tick','themes/leak-sentinel'):
    directory=root/item
    if not directory.is_dir(): raise ValueError('missing-provider:'+item)
    for path in sorted(directory.rglob('*')):
        if path.is_symlink(): files[str(path.relative_to(root))]=['link',str(path.readlink())]
        elif path.is_file(): files[str(path.relative_to(root))]=['file',hashlib.sha256(path.read_bytes()).hexdigest()]
print(json.dumps([config,files],sort_keys=True))
PY
}
lc_selection_setup() { # absent|populated
  leak_plugin_setup acme.probe false vgs.notifications false vgs.themes true || return 1
  leak_input_idle || return 1
  stop_shell || return 1
  mkdir -p "$bg_state"
  rm -f -- "$bg_state/backgrounds.json" "$bg_state/background"
  if [[ $1 == populated ]]; then
    bg_state_names "$lc_selection_baseline" || return 1
    ln -s "$lc_selection_baseline" "$bg_state/background" || return 1
  fi
  start_shell "$repo" "$sandbox/leak-selection-setup-$BASHPID-$leak_seq.log" || return 1
  leak_name_wait org.freedesktop.Notifications none || return 1
  if [[ $1 == populated ]]; then
    expect_poll "the populated selection fixture maps its baseline" "$lc_screen_count" layer_count vgs:background
  else
    expect_poll "the empty selection fixture maps no background" 0 layer_count vgs:background
  fi
  leak_input_idle
}
cat >"$lc_plants/leak-managed-selection.sh" <<'SH'
expect "the plant starts with Themes enabled" True plugin_enabled vgs.themes
expect "the plant starts without a notification owner" 'org.freedesktop.Notifications none' leak_bus_names org.freedesktop.Notifications
bg_state_names "$lc_selection_image" || fail "the plant writes a valid selection"
rm -f -- "$bg_state/background"
ln -s "$lc_selection_image" "$bg_state/background"
leak_plugin_setup acme.probe true || fail "the plant acquires Notifications"
expect_poll "the plant owns Notifications before disabling its holder" 'org.freedesktop.Notifications shell' leak_bus_names org.freedesktop.Notifications
leak_plugin_setup acme.probe false vgs.themes false || fail "the plant disables both holders"
expect_poll "the disabled host has no background before teardown" 0 layer_count vgs:background
if [[ $lc_selection_kind == populated ]]; then
  leak_plugin_setup vgs.themes true || fail "the populated plant restores the mapped-layer precondition"
  expect_poll "the populated plant ends with the same mapped namespaces" "$lc_screen_count" layer_count vgs:background
fi
SH
for lc_selection_kind in absent populated; do
  lc_selection_setup "$lc_selection_kind" || { fail "selection fixture acquisition failed"; return 1; }
  lc_fixture_before="$(lc_fixture_inventory)" || { fail "provider inventory is unreadable"; return 1; }
  leak_dir_next; lc_restore_baseline="$leak_next"
  lc_selection_runner="$shell_pid"
  lc_boundary leak-managed-selection
  expect "the $lc_selection_kind managed selection boundary passes" 0 printf '%s\n' "$lc_result"
  expect "the $lc_selection_kind name release replaces the runner" true python3 -c 'import sys; print(str(sys.argv[1] != sys.argv[2]).lower())' "$shell_pid" "$lc_selection_runner"
  expect "the $lc_selection_kind boundary restores the actual name relation" 'org.freedesktop.Notifications none' leak_bus_names org.freedesktop.Notifications
  lc_boundary leak-successor
  expect "the $lc_selection_kind successor compares the original unit and every class" 0 printf '%s\n' "$lc_result"
  expect "the $lc_selection_kind boundary preserves provider files, placements and settings" "$lc_fixture_before" lc_fixture_inventory
done

lc_selection_setup absent || { fail "the nested fixture is unavailable"; return 1; }
lc_selection_kind=absent
cat >"$lc_plants/leak-nested-selection.sh" <<'SH'
lc_outer_start="${leak_starts[-1]}"
lc_nested_failures="$failures"
smoke_row leak-managed-selection "$lc_plants"
expect "the inner selection plant passes" "$lc_nested_failures" printf '%s\n' "$failures"
expect "the outer immutable context survives inner restoration" "$lc_outer_start" printf '%s\n' "${leak_starts[-1]}"
source "$lc_plants/leak-managed-selection.sh"
SH
leak_dir_next; lc_restore_baseline="$leak_next"
lc_boundary leak-nested-selection
expect "nested selection restoration passes" 0 printf '%s\n' "$lc_result"
lc_boundary leak-successor
expect "the nested successor compares the outer original baseline" 0 printf '%s\n' "$lc_result"

# A raw mapped background remains an original failure, even though one
# full restoration now also returns the selection to its literal baseline.
cat >"$lc_plants/leak-raw-selection.sh" <<'SH'
bg_state_names "$lc_selection_image" || fail "the raw layer plant writes its image"
expect_poll "the raw plant maps its background" "$lc_screen_count" layer_count vgs:background
SH
leak_dir_next; lc_restore_baseline="$leak_next"
lc_boundary leak-raw-selection
expect "the raw background keeps its original failure after full restoration" 1 printf '%s\n' "$lc_result"
expect "the raw background takes exactly one full restoration" 1 grep -c '^qml-smoke: restore=begin .*scope=full ' "$sandbox/leak-raw-selection.log"
lc_boundary leak-successor
expect "the raw background successor compares its original baseline" 0 printf '%s\n' "$lc_result"

# Remove only the new input publication from a disposable boundary copy.
# Its post-layer failure must terminate before the successor. The private
# control's EXIT owns stopping its current generation; it preserves status.
python3 - "$repo/scripts/smoke/leaks.sh" "$lc_plants/no-input-restore.sh" <<'PY'
import pathlib,sys
source=pathlib.Path(sys.argv[1]).read_text()
lines=source.splitlines(keepends=True)
matches=[i for i,line in enumerate(lines) if 'leak_inputs restore ' in line]
assert len(matches)==1
lines[matches[0]]='  : # disposable control: '+lines[matches[0]].strip()+'\n'
pathlib.Path(sys.argv[2]).write_text(''.join(lines))
PY
lc_selection_setup absent || { fail "the disabled-input control fixture is unavailable"; return 1; }
lc_disabled_status=0
# The private control's restore stops this shell inside its subshell,
# whose memory note the run's list never sees.
shell_memory_note
(
  source "$lc_plants/no-input-restore.sh"
  trap 'lc_control_status=$?; trap - EXIT; if stop_shell; then echo stopped >"$lc_plants/input-control.stopped"; fi; exit "$lc_control_status"' EXIT
  smoke_row leak-managed-selection "$lc_plants"
  echo input-control-successor-ran
) >"$sandbox/leak-input-disabled.log" 2>&1 || lc_disabled_status=$?
expect "control: without input restoration the post layer terminates the world" 1 printf '%s\n' "$lc_disabled_status"
expect "control: the new post layer is diagnosed" 1 grep -c 'restoration=leaves class=layers value=+vgs:background' "$sandbox/leak-input-disabled.log"
lc_input_successors() { grep -c '^input-control-successor-ran$' "$sandbox/leak-input-disabled.log" || [[ $? == 1 ]]; }
expect "control: terminal restoration never starts its successor" 0 lc_input_successors
expect "control: its acquired replacement is stopped" stopped cat "$lc_plants/input-control.stopped"
[[ -f $lc_plants/input-control.stopped && $(<"$lc_plants/input-control.stopped") == stopped ]] || return 1
shell_pid="" shell_qs_pid=""
# A new explicit fixture starts only after the failed private world is gone.
start_shell "$repo" "$sandbox/leak-input-control-return.log" || { fail "the control's return shell is unavailable"; return 1; }
lc_selection_setup absent || { fail "the following controls' empty selection is unavailable"; return 1; }
lc_sentinel_release || { fail "the preservation case cannot release its acquired sentinel"; return 1; }
expect "the Leak Check preservation case leaves no sentinel for its successor" absent lc_sentinel_state

# A theme apply under the seed's disabled Themes draws no background.
leak_plugin_setup vgs.themes false || { fail "the theme-apply fixture cannot disable Themes"; return 1; }
leak_input_idle || { fail "the theme-apply fixture is not idle"; return 1; }
rm -f -- "${bg_state:?}/backgrounds.json" "${bg_state:?}/background"
cat >"$lc_plants/leak-theme-apply.sh" <<'SH'
"${shell_env[@]}" "$repo/bin/vgshell" theme apply vgs >/dev/null || fail "the plant applies vgs"
expect "the plant's apply settles" idle theme_idle
expect_poll "the plant draws no background with Themes off" 0 layer_count vgs:background
SH
leak_dir_next; lc_restore_baseline="$leak_next"
lc_boundary leak-theme-apply
expect "a theme apply with Themes off passes its boundary" 0 printf '%s\n' "$lc_result"
lc_boundary leak-successor
expect "the theme-apply successor compares the plant's start" 0 printf '%s\n' "$lc_result"

# The holder creates the per-process notification server without retaining
# its enablement. Each planted restart runs the product path unchanged.
expect "the notification controls start without the shipped holder" ok ipc shell setPluginEnabled vgs.notifications false
expect "the probe establishes the controls' notification server" ok ipc shell setPluginEnabled acme.probe true
expect_poll "the control starts with the notification name owned by the shell" 'org.freedesktop.Notifications shell' leak_bus_names org.freedesktop.Notifications
expect "the control releases the probe's enablement" ok ipc shell setPluginEnabled acme.probe false
expect_poll "the probe is disabled before the enablement control" False plugin_enabled acme.probe
cat >"$lc_plants/leak-plant-plugins-unscanned.sh" <<'SH'
lc_native_ipc="$(declare -f ipc)"
eval "lc_native_$lc_native_ipc"
ipc() {
  if [[ $* == 'shell listPlugins' ]]; then echo '{"scanned":false,"plugins":[]}'; else lc_native_ipc "$@"; fi
}
SH
expect "control: an incomplete registry report fails its row once" 1 lc_planted leak-plant-plugins-unscanned
expect "control: incomplete discovery is unreadable rather than plugin removal" 1 lc_failed leak-plant-plugins-unscanned "leak-check reading=unreadable class=plugins at=end .*"
cat >"$lc_plants/leak-plant-plugins.sh" <<'SH'
expect "the planted row enables its plugin" ok ipc shell setPluginEnabled acme.probe true
expect_poll "the planted enablement is reported" True plugin_enabled acme.probe
SH
expect "control: a row that changes plugin enablement fails once" 1 lc_planted leak-plant-plugins
expect "control: the failure names the plugin and both enablement states" 1 lc_failed leak-plant-plugins 'leaves plugins: \+acme.probe=true -acme.probe=false'
expect "the enablement control restores the disabled holder" ok ipc shell setPluginEnabled acme.probe false
expect_poll "the restarted row will have no notification holder" False plugin_enabled acme.probe
cat >"$lc_plants/leak-plant-bus-names.sh" <<'SH'
printf '%s\n' "$shell_qs_pid" >"$lc_plants/bus-names.killed"
lc_bus_bars="$(bar_count)"
kill -KILL -- "$shell_qs_pid" || fail "the notification control's kill failed"
adopt_shell "$(cat -- "$lc_plants/bus-names.killed")" || fail "the notification control could not adopt its restarted shell"
expect_poll "the notification control's bars return" "$lc_bus_bars" bar_count
SH
shell_memory_note
expect "control: restarting with no holder and losing the name fails once" 1 lc_planted leak-plant-bus-names
expect "control: the leaking row names the notification relation from shell to none" 1 lc_failed leak-plant-bus-names 'leaves bus-names: \+org.freedesktop.Notifications none -org.freedesktop.Notifications shell'
adopt_shell "$(cat -- "$lc_plants/bus-names.killed")" || fail "the bus-name control leaves an adopted shell"
expect "the product restart with no holder leaves no name" 'org.freedesktop.Notifications none' leak_bus_names org.freedesktop.Notifications
control_output "$sandbox/leak-plant-bus-names.log"
leak_notifications_setup || fail "the holder control establishes its own notification precondition"
expect "the next control keeps its disabled holder disabled in setup" False plugin_enabled acme.probe
expect "the restart control enables its notification holder" ok ipc shell setPluginEnabled acme.probe true
expect_poll "the holder takes the notification name before restart" 'org.freedesktop.Notifications shell' leak_bus_names org.freedesktop.Notifications
cp -- "$lc_plants/leak-plant-bus-names.sh" "$lc_plants/leak-plant-bus-holder.sh"
cat >>"$lc_plants/leak-plant-bus-holder.sh" <<'SH'
expect_poll "the product takes the name with its holder enabled after restart" 'org.freedesktop.Notifications shell' leak_bus_names org.freedesktop.Notifications
SH
shell_memory_note
expect "control: restarting with a holder preserves the owner relation without a harness step" 0 lc_planted leak-plant-bus-holder
adopt_shell "$(cat -- "$lc_plants/bus-names.killed")" || fail "the holder control leaves an adopted shell"
# Ordinary managed teardown changes neither the row's restart assertions
# nor its verdict. These execute in the living world, after those checks.
leak_plugin_setup acme.probe false vgs.notifications false || fail "the ordinary name controls establish disabled holders"
lc_boundary leak-plant-plugins
expect "ordinary teardown restores an enablement change without a class failure" 0 printf '%s\n' "$lc_result"
expect "ordinary teardown restores the captured probe flag" False plugin_enabled acme.probe
cp -- "$lc_plants/leak-plant-bus-names.sh" "$lc_plants/leak-managed-bus.sh"
cat >>"$lc_plants/leak-managed-bus.sh" <<'SH'
expect "a no-holder product restart owns no notification name before teardown" 'org.freedesktop.Notifications none' leak_bus_names org.freedesktop.Notifications
SH
shell_memory_note
lc_boundary leak-managed-bus
expect "ordinary teardown restores the name after the row's no-holder assertion" 0 printf '%s\n' "$lc_result"
expect "the captured shell relation is restored" 'org.freedesktop.Notifications shell' leak_bus_names org.freedesktop.Notifications

# A holder-enabled restart defect stays failed even though full cleanup
# subsequently restores the run tree and takes the expected name.
if copy_tree no-notification-server && edit_tree no-notification-server shell/Core/NotificationHub.qml 'active: root.active' 'active: false'; then
  leak_plugin_setup acme.probe true || fail "the product control enables its holder before restart"
  cat >"$lc_plants/leak-product-notification.sh" <<'SH'
stop_shell
start_shell "$sandbox/tree-no-notification-server" "$sandbox/no-notification-server.log"
expect_poll "the product takes the name with its holder enabled after restart" 'org.freedesktop.Notifications shell' leak_bus_names org.freedesktop.Notifications
SH
  lc_boundary leak-product-notification
  expect "the product mutant stays failed after successful restoration" 1 printf '%s\n' "$lc_result"
  expect "the product mutant has exactly one full restoration" 1 grep -c '^qml-smoke: restore=begin .*scope=full ' "$sandbox/leak-product-notification.log"
  expect "cleanup restores the original product's actual owner relation" 'org.freedesktop.Notifications shell' leak_bus_names org.freedesktop.Notifications
fi
# The restore's fault table. Each row plants one fault in one restore phase
# and runs it through the real boundary: the fault fails only its own row,
# or nothing where the restore accepts it as cleanup, the restoration ends
# nothing, and the successor starts at the planting row's start. The
# no-input-restore control above is the world truly not restored: its post
# reading ends that private world. A runner copy that handles its TERM
# after VGS_LC_TERM_DELAY seconds pins the stop threshold at its real
# 10 s first, and stands in for a shell that ignores its TERM.
lc_term_trap="trap 'stop=1; forwarded=1; [[ -z \$shell_child ]] || kill -TERM \"\$shell_child\" 2>/dev/null || :' HUP INT TERM"
lc_term_delayed="trap 'sleep \"\${VGS_LC_TERM_DELAY:-0}\"; stop=1; forwarded=1; [[ -z \$shell_child ]] || kill -TERM \"\$shell_child\" 2>/dev/null || :' HUP INT TERM"
if copy_tree term-delay && edit_tree term-delay bin/vgshell "$lc_term_trap" "$lc_term_delayed"; then
  # lc_term_stop DELAY LOW_MS HIGH_MS: sets lc_term_result to the typed
  # stop's outcome for that runner, and 1 when the stop took LOW_MS to
  # HIGH_MS, else 0.
  lc_term_stop() {
    local outcome started elapsed
    lc_term_result=start-failed
    start_shell "$sandbox/tree-term-delay" "$sandbox/leak-term-delay-$1.log" bar VGS_LC_TERM_DELAY="$1" || return 0
    started="$(now_ms)"
    shell_stop outcome
    elapsed=$(( $(now_ms) - started ))
    lc_term_result="$outcome $(( elapsed >= $2 && elapsed < $3 ))"
  }
  stop_shell || fail "the threshold rows stop the run tree's shell"
  lc_term_stop 8 8000 10000
  expect "a runner that ends 8 s after its TERM is stopped, not forced" "stopped 1" printf '%s\n' "$lc_term_result"
  lc_term_stop 13 10000 13000
  expect "a runner that would end 13 s after its TERM is forced at 10 s" "forced 1" printf '%s\n' "$lc_term_result"

  # lc_fault NAME: NAME through the real boundary, then its successor:
  # lc_fault_result and lc_fault_successor are their failure counts.
  lc_fault() {
    leak_dir_next
    lc_restore_baseline="$leak_next"
    lc_boundary "$1"
    lc_fault_result="$lc_result"
    lc_boundary leak-successor
    lc_fault_successor="$lc_result"
  }
  lc_log_count() { grep -c -E -- "$2" "$sandbox/$1.log" || [[ $? == 1 ]]; } # NAME PATTERN

  # A full restoration forces a stopped shell and goes on.
  start_shell "$repo" "$sandbox/leak-fault-shell.log" || fail "the fault table starts the run tree's shell"
  cat >"$lc_plants/leak-fault-stopped-shell.sh" <<'SH'
kill -STOP -- "$shell_qs_pid" || fail "leak-fault-stopped-shell: the planted stop was not sent"
fail "leak-fault-stopped-shell: the row fails with its shell stopped"
SH
  lc_fault leak-fault-stopped-shell
  expect "stopped shell: the row keeps its own failure" 1 lc_failed leak-fault-stopped-shell "the row fails with its shell stopped"
  expect "stopped shell: the restore forces the runner and goes on" 1 lc_log_count leak-fault-stopped-shell '^qml-smoke: restore row=leak-fault-stopped-shell step=stop outcome=forced$'
  expect "stopped shell: the successor starts at the planting row's start" 0 printf '%s\n' "$lc_fault_successor"

  # A managed name release whose runner ignores its TERM is forced, which
  # the restore accepts: the passing row stays passing.
  # The notification server lives as long as its process, so the holders
  # are off before that runner's shell starts.
  leak_plugin_setup acme.probe false vgs.notifications false || fail "the managed forced row starts without a notification holder"
  stop_shell || fail "the managed forced row stops the run tree's shell"
  start_shell "$sandbox/tree-term-delay" "$sandbox/leak-fault-managed-forced-qs.log" bar VGS_LC_TERM_DELAY=30 || fail "the managed forced row starts its TERM-ignoring runner"
  leak_name_wait org.freedesktop.Notifications none || fail "the managed forced row starts with no notification owner"
  cat >"$lc_plants/leak-fault-managed-forced.sh" <<'SH'
leak_plugin_setup acme.probe true || fail "leak-fault-managed-forced: the plant enables its holder"
expect_poll "leak-fault-managed-forced: the shell owns the notification name" 'org.freedesktop.Notifications shell' leak_bus_names org.freedesktop.Notifications
leak_plugin_setup acme.probe false || fail "leak-fault-managed-forced: the plant disables its holder"
SH
  lc_fault leak-fault-managed-forced
  expect "managed forced: the passing row stays passing" 0 printf '%s\n' "$lc_fault_result"
  expect "managed forced: the name release forces the runner and goes on" 1 lc_log_count leak-fault-managed-forced '^qml-smoke: restore row=leak-fault-managed-forced step=name-release outcome=forced$'
  expect "managed forced: the successor starts at the planting row's start" 0 printf '%s\n' "$lc_fault_successor"

  # A stop whose forced kill overruns its bound reads unproved: the row
  # fails on it, and the runner that ended on its TERM is started anew.
  # shell_stop reads the recorder's answer in a command substitution, so the
  # one-shot is a marker file, and the row puts the recorder call back.
  lc_saved_record="$(declare -f display_record_call)"
  cat >"$lc_plants/leak-fault-force-overrun.sh" <<'SH'
display_record_call() {
  if [[ $1 == stop-shell-owner && ! -e $lc_plants/force-overrun.done ]]; then
    : >"$lc_plants/force-overrun.done"
    (eval "$lc_saved_record"; display_record_call stop-shell-owner "$2" "$3" 0)
    return
  fi
  (eval "$lc_saved_record"; display_record_call "$@")
}
fail "leak-fault-force-overrun: the row fails before its stop overruns"
SH
  lc_fault leak-fault-force-overrun
  eval "$lc_saved_record"
  expect "force overrun: the restore names its unproved stop" 1 lc_log_count leak-fault-force-overrun '^  FAIL  leak-fault-force-overrun: restoration step=stop cause=unproved$'
  expect "force overrun: the successor starts at the planting row's start" 0 printf '%s\n' "$lc_fault_successor"

  # A runner already gone is a stop that worked.
  cat >"$lc_plants/leak-fault-runner-gone.sh" <<'SH'
shell_memory_note
kill -KILL -- "$shell_pid" || fail "leak-fault-runner-gone: the planted kill was not sent"
fail "leak-fault-runner-gone: the row fails with its runner gone"
SH
  lc_fault leak-fault-runner-gone
  expect "runner gone: the restore's stop names no failure" 0 lc_log_count leak-fault-runner-gone '^  FAIL  leak-fault-runner-gone: restoration step=stop '
  expect "runner gone: the successor starts at the planting row's start" 0 printf '%s\n' "$lc_fault_successor"

  # A restarted shell that dies as soon as it answered is taken up again
  # from its runner.
  cat >"$lc_plants/leak-fault-shell-dies.sh" <<'SH'
lc_saved_start="$(declare -f start_shell)"
start_shell() {
  local lc_dying
  eval "$lc_saved_start"
  start_shell "$@" || return
  lc_dying="$shell_qs_pid"
  shell_memory_note
  kill -KILL -- "$lc_dying"
  for _ in $(seq 1 40); do
    lc_state="$(ps -o stat= -p "$lc_dying")" || break
    [[ $lc_state != Z* ]] || break
    sleep 0.05
  done
}
fail "leak-fault-shell-dies: the row fails before its restarted shell dies"
SH
  lc_fault leak-fault-shell-dies
  expect "restarted shell dies: the restore names the ended shell" 1 lc_log_count leak-fault-shell-dies '^  FAIL  leak-fault-shell-dies: restoration step=start-shell cause=shell-ended pid=[0-9]+$'
  expect "restarted shell dies: the successor starts at the planting row's start" 0 printf '%s\n' "$lc_fault_successor"

  # A managed step that cannot finish after a passing row fails that row.
  cat >"$lc_plants/leak-fault-managed-step.sh" <<'SH'
lc_saved_idle="$(declare -f leak_input_idle)"
leak_input_idle() {
  eval "$lc_saved_idle"
  printf 'qml-smoke: persisted-inputs=idle state=planted-busy\n' >&2
  return 1
}
SH
  lc_fault leak-fault-managed-step
  expect "managed step: the passing row fails once, on the restore" 1 printf '%s\n' "$lc_fault_result"
  expect "managed step: the restore names its step" 1 lc_log_count leak-fault-managed-step '^  FAIL  leak-fault-managed-step: restoration step=input-idle cause=not-idle$'
  expect "managed step: the successor starts at the planting row's start" 0 printf '%s\n' "$lc_fault_successor"

  # A process that takes the instance lock as the runner ends holds it past
  # the stop's lock wait; the restart waits for it.
  cat >"$lc_plants/leak-fault-lock-held.sh" <<'SH'
setsid -f flock "$rt_dir/vgshell.lock" sleep 13 </dev/null >/dev/null 2>&1 || fail "leak-fault-lock-held: the planted holder did not start"
fail "leak-fault-lock-held: the row fails with a holder waiting on the instance lock"
SH
  lc_fault leak-fault-lock-held
  expect "lock held: the restore names the held lock" 1 lc_log_count leak-fault-lock-held '^  FAIL  leak-fault-lock-held: restoration step=stop cause=lock-held$'
  expect "lock held: the restart waits for the lock" 0 lc_log_count leak-fault-lock-held '^  FAIL  leak-fault-lock-held: restoration step=start-shell '
  expect "lock held: the successor starts at the planting row's start" 0 printf '%s\n' "$lc_fault_successor"
fi
# A layer whose owner is gone. A launcher connects to the nested Wayland
# socket, forks a holder that keeps that connection until a gate exists,
# and execs qs on it through WAYLAND_SOCKET, so the compositor names the
# qs pid as the layer's owner. Killing qs leaves the holder keeping the
# client, as a process that inherited a shell's connection does. The row's
# end reading reads the layer unreadable at once under its owner-gone key,
# with no settle wait, and the holder diagnostic names the holder.
mkdir -p "$lc_plants/gone-owner"
cat >"$lc_plants/gone-owner/shell.qml" <<'QML'
import Quickshell
import Quickshell.Wayland
PanelWindow {
    anchors { top: true; left: true }
    implicitWidth: 10
    implicitHeight: 10
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "vgs:leak-gone"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: true
}
QML
cat >"$lc_plants/gone-owner.py" <<'PY'
import os, socket, sys, time
path, gate, holder_file, fixture = sys.argv[1:5]
connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
connection.connect(path)
fd = connection.detach()
os.set_inheritable(fd, True)
if os.fork() == 0:
    with open(holder_file, "w") as record:
        record.write(str(os.getpid()))
    deadline = time.monotonic() + 120
    while not os.path.exists(gate) and time.monotonic() < deadline:
        time.sleep(0.05)
    os._exit(0)
os.environ["WAYLAND_SOCKET"] = str(fd)
os.execvp("qs", ["qs", "-p", fixture])
PY
cat >"$lc_plants/leak-plant-gone-owner.sh" <<'SH'
"${shell_env[@]}" python3 "$lc_plants/gone-owner.py" "$rt_dir/$nested_socket" "$lc_plants/gone-owner.gate" "$lc_plants/gone-owner.holder" "$lc_plants/gone-owner" >"$sandbox/gone-owner-qs.log" 2>&1 &
lc_gone_client=$!
printf '%s\n' "$lc_gone_client" >"$lc_plants/gone-owner.client"
expect_poll "the gone-owner fixture maps its layer" 1 layer_count vgs:leak-gone
kill -KILL -- "$lc_gone_client" || fail "the gone-owner fixture's client kill was not sent"
wait "$lc_gone_client" 2>/dev/null || :
SH
rm -f -- "${lc_plants:?}/gone-owner.gate" "${lc_plants:?}/gone-owner.holder" "${lc_plants:?}/gone-owner.client"
expect "control: a layer whose owner is gone fails its row once" 1 lc_planted leak-plant-gone-owner
lc_gone_line() { grep -c -E -- "^  FAIL  leak-plant-gone-owner: leak-check reading=unreadable class=layers at=end start=[^ ]+ end=[^ ]+ cause=owner-gone pid=$(<"$lc_plants/gone-owner.client") namespace=vgs:leak-gone " "$sandbox/leak-plant-gone-owner.log" || [[ $? == 1 ]]; }
expect "control: the reading names the gone owner under its own key" 1 lc_gone_line
lc_gone_secs() { local secs; secs="$(sed -n 's/^qml-smoke: row-secs row=leak-plant-gone-owner secs=\([0-9]*\) .*/\1/p' -- "$sandbox/leak-plant-gone-owner.log")"; if [[ $secs =~ ^[0-9]+$ ]] && (( secs < timeout_s )); then echo prompt; else echo "secs=${secs:-unread}"; fi; }
expect "control: the gone-owner reading takes no settle wait" prompt lc_gone_secs
lc_gone_holder() { grep -c -E -- "^qml-smoke: socket-holder class=layers reading=[^ ]+ bus=wayland inode=[0-9]+ pid=$(<"$lc_plants/gone-owner.holder") " "$sandbox/leak-plant-gone-owner.log" || [[ $? == 1 ]]; }
expect "control: the holder diagnostic names the process holding the gone owner's connection" 1 lc_gone_holder
: >"$lc_plants/gone-owner.gate"
expect_poll "the gone-owner fixture's layer leaves with its holder" 0 layer_count vgs:leak-gone
expect "the Leak Check row leaves no sentinel package for later rows" absent lc_sentinel_state
