# The Workspaces plugin, vgs.workspaces. The Bar plugin registers the clock
# alone, and its Settings page offers the clock's field and no Workspaces
# field. Manage widgets lists Workspaces, and its Switch, reached through
# the list's keyboard path, which scrolls it into view, takes the widget
# off every bar and puts it back, as for any widget-only plugin. Over two monitors, the first holding workspace 1
# and SMOKE-WS holding 2 and 3, each with a window, the drawn pills follow
# its settings. With Split by display off, both bars show 1, 2 and 3 and
# light the focused one; on, the first shows 1 and SMOKE-WS 2 and 3, each
# lighting the workspace its monitor shows. The workspace rules this row
# loads also name an empty 4 on SMOKE-WS and an empty 5 on no monitor.
# With Show empty workspaces off no bar shows them; on, both bars do; on
# with Split by display, SMOKE-WS alone shows 4 and no bar shows 5. A click
# on a pill focuses its workspace. The control is a copy whose widget
# ignores Split by display: SMOKE-WS's bar then reads all three. No latency
# budget: every wait polls reported state at the harness interval.
# inputs: scripts/smoke/workspaces-world.sh shell/plugins/vgs.workspaces/* shell/plugins/vgs.bar/manifest.json shell/plugins/vgs.bar/Bar.qml shell/plugins/vgs.bar/Builtin.qml shell/plugins/vgs.bar/AddWidget.qml shell/Commons/Workspaces.qml shell/Core/HyprlandState.* shell/Core/Capabilities.qml shell/Core/Plugins.qml shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/Core/Config.qml shell/Core/Registry.qml shell/Hosts/BarHost.qml shell/Ui/BarWidget.qml shell/Ui/controls/BarItem.qml shell/Ui/controls/Switch.qml shell/Ui/foundation/KeyNav.qml shell/Ui/foundation/KeyNavLogic.js shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/Ui/controls/SettingField.qml config/shell.json scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail
source "$repo/scripts/smoke/workspaces-world.sh"
ws_config="$home/.config/vgshell/shell.json"
ws_saved="$sandbox/workspaces-saved.json"
cp -- "$ws_config" "$ws_saved"
ws_lua="$home/.config/hypr/hyprland.lua"
ws_first="$(first_name)" || { fail "workspaces: the first monitor is unreadable"; return 1; }
ws_output=SMOKE-WS
ws_windows=()
ws_output_made=false
hypr_lua_save workspaces

ws_listed() { ipc shell listPlugins | py_reply 'import json,sys; r=[p for p in json.load(sys.stdin)["plugins"] if p["id"]==sys.argv[1]]; print(json.dumps(r[0][sys.argv[2]], separators=(",", ":")) if r else "absent")' "$1" "$2"; }
ws_state() { ws_listed vgs.workspaces enabled | py_reply 'import json,sys; print(json.dumps([json.load(sys.stdin), json.loads(sys.argv[1])], separators=(",", ":")))' "$(ws_listed vgs.workspaces placed)"; }
# The Switch of builtin ID's placement field on the open Settings page, or
# `absent` when the page draws none (Probe fieldBoolean).
ws_bar_field() { ipc smoke invokeInstance window vgs.settings fieldBoolean "{\"id\":\"$1\",\"key\":\"\"}"; }
# FIELD of vgs.workspaces's row in the open chooser (Probe chooserRows).
ws_chooser() { ipc smoke chooserRows | py_reply 'import json,sys; r=[x for x in json.load(sys.stdin) if x["id"]=="vgs.workspaces"]; print(json.dumps(r[0][sys.argv[1]]) if len(r)==1 else "absent")' "$1"; }
# Moves the keyboard to the Workspaces row: Home selects the first row and
# each Down the next, and the focused row scrolls into the list's view.
ws_chooser_reveal() {
  local index i keys=(-k Home)
  index="$(ipc smoke readInstance window vgs.bar widgets | py_reply 'import json,sys; ids=[p["id"] for p in json.load(sys.stdin)]; print(ids.index("vgs.workspaces") if "vgs.workspaces" in ids else "absent")')" || return 1
  [[ $index =~ ^[0-9]+$ ]] || return 1
  for ((i = 0; i < index; i++)); do keys+=(-k Down); done
  type_keys "${keys[@]}"
}
ws_chooser_click() {
  local box x y
  box="$(ws_chooser control)" || return 1
  [[ $box == \[* ]] || return 1
  read -r x y < <(at_centre window:Bar "$box") || return 1
  click "$x" "$y"
}
ws_open_window() { # WORKSPACE
  expect "workspace $1 takes the focus" ok hypr dispatch "hl.dsp.focus({ workspace = \"$1\" })"
  expect_poll "workspace $1 is focused before its window opens" "$1" ws_focused
  open_toplevel "$sandbox/workspaces-window-$1.log" smoke.workspaces "Workspace $1" || { fail "the workspace $1 window maps"; return 1; }
  ws_windows+=("$toplevel_pid")
}
ws_cleanup() {
  local pid
  for pid in "${ws_windows[@]}"; do close_toplevel "$pid" "the workspaces row closes its window" cleanup; done
  ws_windows=()
  if [[ $ws_output_made == true ]]; then
    create_output_remove "$ws_output" >/dev/null || fail "the workspaces row removes $ws_output"
    ws_output_made=false
  fi
  hypr_lua_restore workspaces
  hypr_config_reload || fail "the workspaces row reloads the harness's configuration"
  user_config_restore "$ws_saved" || fail "the workspaces row restores the user file"
}
smoke_row_abandon=(ws_cleanup)

# The Bar plugin: the clock is its one built-in, and its Settings page's
# placement fields come from that list alone.
expect_builtins "the Bar registers its clock and draws no workspaces" '["vgs.bar/center-clock"]'
expect "Settings opens the Bar's page" ok ipc shell summon window vgs.settings '{"plugin":"vgs.bar"}'
expect_poll "the Bar's Settings page offers the placed clock's field" '{"type":"boolean","value":true,"checked":true,"enabled":true}' ws_bar_field vgs.bar/center-clock
expect "the Bar's Settings page offers no Workspaces field" absent ws_bar_field vgs.bar/left-workspaces
expect "Settings closes after the Bar's page" ok ipc shell hide window vgs.settings
expect_widgets "every bar mounts the Workspaces widget" '["acme.tick","vgs.workspaces"]'

# Manage widgets, opened on the first bar's left side.
expect "Manage widgets opens" ok ipc shell summon window vgs.bar "{\"screen\":\"$ws_first\",\"x\":40}"
expect_poll "the chooser is a real Bar application window" 1 window_count Bar
expect_poll "Manage widgets lists Workspaces with its Switch on" '"Switch"' ws_chooser type
expect "the placed Workspaces row's Switch is on" true ws_chooser checked
ws_chooser_reveal || fail "the keyboard could not be moved to the Workspaces row"
expect_poll "the keyboard reaches the Workspaces row's Switch" true ws_chooser focused
ws_chooser_click || fail "the Workspaces Switch could not be clicked off"
expect_widgets "turning the Switch off takes Workspaces off every bar" '["acme.tick"]'
expect_poll "Workspaces is off once unplaced" '[false,false]' ws_state
expect_poll "the unplaced Workspaces row's Switch is off" false ws_chooser checked
ws_chooser_click || fail "the Workspaces Switch could not be clicked on"
expect_widgets "turning the Switch on puts Workspaces on every bar again" '["acme.tick","vgs.workspaces"]'
expect_poll "Workspaces is on and placed again" '[true,true]' ws_state
expect "the chooser closes" ok ipc shell hide window vgs.bar
expect_poll "the chooser window is gone" 0 window_count Bar
user_config_restore "$ws_saved" || fail "the user file is restored after Manage widgets"
expect_poll "the saved layout's Workspaces widget is back" '[true,true]' ws_state

# Two monitors: the harness's persistent 2 and 100 give way to this row's
# rules, 1 on the first monitor, 2 (the default there), 3 and an empty 4
# on SMOKE-WS, and an empty 5 on none. The rules load before SMOKE-WS
# exists, since a reload would drop the mode create_output gives it.
ws_rules "$ws_lua" "$ws_first" "$ws_output" "4=monitor = \"$ws_output\"" "5=persistent = false" || fail "the workspaces row could not write its workspace rules"
expect "the nested instance loads the row's workspace rules" ok hypr reload config-only
expect_poll "only workspace 1 is left on the first monitor" "{\"1\":\"$ws_first\"}" ws_placed
expect "the nested compositor adds $ws_output" ok create_output "$ws_output"
ws_output_made=true
expect_poll "$ws_output gets a bar" "$((monitors + 1))" bar_count
ws_open_window 2
ws_open_window 3
ws_open_window 1
expect_poll "the first monitor holds 1 and $ws_output holds 2 and 3" "{\"1\":\"$ws_first\",\"2\":\"$ws_output\",\"3\":\"$ws_output\"}" ws_placed

expect_poll "Split by display off: the first bar shows 1, 2 and 3 and lights the focused 1" '[[1,true],[2,false],[3,false]]' ws_pills "$ws_first"
expect_poll "Split by display off: $ws_output's bar shows 1, 2 and 3" '[[1,true],[2,false],[3,false]]' ws_pills "$ws_output"
ws_set '{"thisDisplayOnly": true}' || fail "Split by display could not be turned on"
expect_poll "Split by display on: the first bar shows 1 alone" '[[1,true]]' ws_pills "$ws_first"
expect_poll "Split by display on: $ws_output's bar shows 2 and 3 and lights the 3 it shows" '[[2,false],[3,true]]' ws_pills "$ws_output"
ws_set '{"thisDisplayOnly": false, "showEmpty": false}' || fail "the settings could not be reset"
expect_poll "Show empty workspaces off: no bar shows the empty 4 or 5" '[[1,true],[2,false],[3,false]]' ws_pills "$ws_output"
ws_set '{"showEmpty": true}' || fail "Show empty workspaces could not be turned on"
expect_poll "Show empty workspaces on: the first bar adds the empty 4 and 5" '[[1,true],[2,false],[3,false],[4,false],[5,false]]' ws_pills "$ws_first"
expect_poll "Show empty workspaces on: $ws_output's bar adds them too" '[[1,true],[2,false],[3,false],[4,false],[5,false]]' ws_pills "$ws_output"
ws_set '{"thisDisplayOnly": true}' || fail "Split by display could not be turned on beside Show empty workspaces"
expect_poll "both on: the first bar shows 1 and no empty workspace" '[[1,true]]' ws_pills "$ws_first"
expect_poll "both on: $ws_output's bar adds the empty 4 its rule names, and 5, on no monitor, shows nowhere" '[[2,false],[3,true],[4,false]]' ws_pills "$ws_output"

# A still click on the first bar's 2 focuses it, through the widget's own
# compositor capability.
ws_set '{"thisDisplayOnly": false, "showEmpty": false}' || fail "the settings could not be reset before the click"
expect_poll "the first bar shows 2 before the click" '[[1,true],[2,false],[3,false]]' ws_pills "$ws_first"
ws_box="$(ipc smoke itemGeometry "bar:$ws_first" vgs.workspaces BarItem 2)" || fail "the 2 pill is unreadable"
read -r ws_x ws_y < <(py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print("%d %d" % (x+w/2,y+h/2))' <<<"$ws_box") || fail "the 2 pill has no box: $ws_box"
hover "$((ws_x + 1))" "$ws_y" && click "$ws_x" "$ws_y" || fail "the click on the 2 pill completes"
expect_poll "a click on a pill focuses its workspace" 2 ws_focused
expect_poll "the bars light the newly focused 2" '[[1,false],[2,true],[3,false]]' ws_pills "$ws_first"
expect "workspace 1 takes the focus again" ok hypr dispatch 'hl.dsp.focus({ workspace = "1" })'
expect_poll "workspace 1 is focused again" 1 ws_focused

# Control: a widget that ignores Split by display shows every workspace on
# SMOKE-WS's bar, so the reader above would turn red.
if copy_tree workspaces-unsplit \
  && edit_tree workspaces-unsplit shell/plugins/vgs.workspaces/Widget.qml 'Workspaces.monitors, thisDisplayOnly ? screenName : "", Workspaces.focusedId)' 'Workspaces.monitors, "", Workspaces.focusedId)'; then
  ws_set '{"thisDisplayOnly": true}' || fail "control: Split by display could not be turned on"
  stop_shell
  start_shell "$sandbox/tree-workspaces-unsplit" "$sandbox/workspaces-unsplit.log" || fail "control: the unsplit copy starts"
  expect_poll "control: the unsplit copy maps a bar on both monitors" "$((monitors + 1))" bar_count
  expect_poll "control: a widget that ignores Split by display shows 1, 2 and 3 on $ws_output" '[[1,true],[2,false],[3,false]]' ws_pills "$ws_output"
  stop_shell
  start_shell "$repo" "$sandbox/workspaces-restored.log" || fail "the shell returns after the unsplit control"
  # The click above focused 2, so $ws_output shows 2.
  expect_poll "the restored shell splits $ws_output's bar again and lights the 2 it shows" '[[2,true],[3,false]]' ws_pills "$ws_output"
fi

ws_cleanup
smoke_row_abandon=()
expect_poll "one bar per monitor once $ws_output goes" "$monitors" bar_count
expect_poll "the harness's workspaces return" "{\"1\":\"$ws_first\",\"100\":\"$ws_first\",\"2\":\"$ws_first\"}" ws_placed
expect_widgets "the restored user file mounts its widgets" '["acme.tick","vgs.workspaces"]'
# The sink configures each output once, so SMOKE-WS's add and remove leave
# the first output in the mode the harness holds (coordinate_mode_check).
if [[ ${#mode_hold[@]} -gt 0 ]]; then
  expect "the held mode stands after $ws_output" held held_mode_state
fi
