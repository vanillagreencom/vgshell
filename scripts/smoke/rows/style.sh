# The launcher's Style menu, which vgs.themes and vgs.bar contribute
# through their manifests' `menu` rows, and the two toggles behind it.
# The row opens the launcher on `style` and reads its rows through the
# probe; Theme and Wallpaper summon the theme browser on its two views; the
# gaps toggle writes `noWindowGaps`, the Hyprland layer's zero-gap
# workspace rule, which a tiled toplevel and `hyprctl workspacerules` read
# back with a user `general` gaps line after the loading line, across a
# theme apply; the bar toggle writes vgs.bar's `hidden`, which unmaps every
# bar and frees the space it reserved. Both toggles hold across a restart
# whose stop follows the second toggle's answer at once, and three tree
# copies are the controls of that restart: one whose bar host maps a hidden
# bar, one whose service gate waits on a hidden bar, and one whose write
# comes after its answer, which loses the edit at the stop.
# Disabling vgs.themes takes the Style category and the bar's row under it
# away. Each label the launcher draws follows its setting. A user menu file
# that relabels a plugin row is the control of the row list. It runs in the
# tail, since it restarts the shell, and leaves the launcher disabled,
# vgs.themes enabled only when it found it so, the gaps and the bar as they
# were and hyprland.lua as it found it.
# inputs: shell/plugins/vgs.themes/manifest.json shell/plugins/vgs.themes/Service.qml shell/plugins/vgs.bar/* shell/plugins/vgs.launcher/* shell/Core/ShortcutRegistry.qml shell/Core/Registry.qml shell/Core/PluginLogic.js shell/Core/HyprlandLayer.js shell/Core/ServiceGate.qml shell/Core/Config.qml shell/Commons/WatchedFile.qml shell/Hosts/BarHost.qml scripts/smoke/toplevel/* scripts/smoke/rows/launcher.sh scripts/smoke/rows/hyprland.sh scripts/smoke/rows/themes.sh themes/catalog/flexoki-light/*
set -euo pipefail
user_config="$home/.config/vgshell/shell.json"
# The value of setting KEY in plugin ID's `plugins` row of the user file,
# `absent` without one.
user_setting() { python3 -c 'import json,sys; rows=[r for r in json.load(open(sys.argv[1])).get("plugins", []) if r.get("id") == sys.argv[2]]; print(json.dumps(rows[0][sys.argv[3]]) if rows and sys.argv[3] in rows[0] else "absent")' "$user_config" "$1" "$2"; }
# The launcher's rows as [kind, label] pairs.
row_labels() { launcher_rows | py_reply 'import json,sys; print(json.dumps([r[:2] for r in json.load(sys.stdin)]))'; }
style_rows() { # GAPS_LABEL BAR_LABEL
  printf '[["shortcut", "Theme"], ["shortcut", "Wallpaper"], ["shortcut", "%s"], ["shortcut", "%s"]]' "$1" "$2"
}
open_style() { # LABEL
  expect "$1: the launcher opens on Style" ok ipc shell summon overlay vgs.launcher '{"menu":"style"}'
  focused "$1: the launcher holds the keyboard"
}
# Select the row at INDEX of the open list with the keyboard.
pick_row() { # INDEX
  local i
  for ((i = 0; i < $1; i++)); do type_keys -k Down || return; done
  type_keys -k Return
}
browser_view() { ipc smoke readInstance overlay vgs.themes view; }
# Zero gaps as Hyprland reads its workspace rules: the empty selector's
# rule's inner and outer gaps, `none` without the rule.
gap_rule() { hypr -j workspacerules | py_reply 'import json,sys; r=[w for w in json.load(sys.stdin) if w.get("workspaceString") == ""]; print(json.dumps([r[0].get("gapsIn"), r[0].get("gapsOut")]) if r else "none")'; }
# How far the tiled toplevel of pid PID sits inside its monitor's work
# area, less the border Hyprland draws around it: [left, top, right,
# bottom] in logical pixels, 0 on every side with no gaps.
tile_inset() { # PID
  local border monitors_json
  border="$(hypr_option general:border_size)" || return
  monitors_json="$(hypr -j monitors)" || return
  hypr -j clients | py_reply '
import json, sys
border, pid, monitors = int(sys.argv[1]), int(sys.argv[2]), json.loads(sys.argv[3])
cs = [c for c in json.load(sys.stdin) if c["pid"] == pid]
if len(cs) != 1 or cs[0]["floating"]:
    print("clients=%d" % len(cs) if len(cs) != 1 else "floating")
    sys.exit(0)
c = cs[0]
m = next(m for m in monitors if m["id"] == c["monitor"])
w, h = round(m["width"] / m["scale"]), round(m["height"] / m["scale"])
left, top, right, bottom = m["reserved"]
x0, y0, x1, y1 = m["x"] + left, m["y"] + top, m["x"] + w - right, m["y"] + h - bottom
print(json.dumps([c["at"][0] - x0 - border, c["at"][1] - y0 - border, x1 - (c["at"][0] + c["size"][0]) - border, y1 - (c["at"][1] + c["size"][1]) - border]))
' "$border" "$1" "$monitors_json"; }
# Hyprland's outer gap as `general:gaps_out` reads, its top side.
user_gaps_out() { hypr -j getoption general:gaps_out | py_reply 'import json,sys; print(json.load(sys.stdin)["css"].split()[0])'; }
bar_top() { monitor_size | cut -d' ' -f3; }
services_released() {
  local line
  if line="$(grep -o -E -m 1 'plugins: services released reason=[a-z-]+' -- "$instance_log")" && [[ $line =~ reason=([a-z-]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo absent
  fi
}
services_ready() { local reason; reason="$(services_released)" || return; if [[ $reason == absent ]]; then echo false; else echo true; fi; }

expect "enabling the launcher for the Style rows is allowed" ok ipc shell setPluginEnabled vgs.launcher true
expect_poll "the Style rows' launcher service is built" True record_exists vgs.launcher
themes_were_enabled="$(plugin_enabled vgs.themes)" || themes_were_enabled=unread
expect "enabling vgs.themes for the Style rows is allowed" ok ipc shell setPluginEnabled vgs.themes true
expect_poll "vgs.themes' service is built for the Style rows" True record_exists vgs.themes

# The list: Theme, Wallpaper and the two toggles, each naming what it does,
# and no theme name. A user file relabelling a plugin row is the control:
# the same reading reads the relabelled row, and its removal reads the
# plugin's label again.
open_style "the Style rows"
expect_poll "Style lists Theme, Wallpaper, the gaps row and the bar row" "$(style_rows "No window gaps" "Hide top bar")" row_labels
write_menu '{ "schemaVersion": 1, "items": { "style.theme": { "label": "Pick a theme" } } }'
expect_poll "control: a user file relabels a plugin row" '[["shortcut", "Pick a theme"], ["shortcut", "Wallpaper"], ["shortcut", "No window gaps"], ["shortcut", "Hide top bar"]]' row_labels
rm -f -- "$user_menu"
expect_poll "the plugin's label returns with the user file gone" "$(style_rows "No window gaps" "Hide top bar")" row_labels

# Theme and Wallpaper summon the browser on the views SUPER+T and SUPER+W
# open; the launcher closes and the browser holds the keyboard. Each reading
# is the other's control.
pick_row 0 || fail "selecting Theme failed"
expect_poll "Theme opens the theme browser on its themes view" '"themes"' browser_view
expect_poll "Theme closes the launcher" absent read_launcher opened
expect_poll "the theme browser holds the keyboard" true ipc smoke activeFocusIn overlay vgs.themes
expect "the host hides the theme browser" ok ipc shell hide overlay vgs.themes
expect_poll "the theme browser closed" 0 layer_count vgs:overlay
open_style "Wallpaper"
pick_row 1 || fail "selecting Wallpaper failed"
expect_poll "Wallpaper opens the browser on its wallpapers view" '"wallpapers"' browser_view
expect_poll "Wallpaper closes the launcher" absent read_launcher opened
expect "the host hides the wallpaper view" ok ipc shell hide overlay vgs.themes
expect_poll "the wallpaper view closed" 0 layer_count vgs:overlay
# A route naming a plugin's row by its alias runs it without opening.
expect "the launcher summons on the route theme" ok ipc shell summon overlay vgs.launcher '{"menu":"theme"}'
expect_poll "the route theme opens the theme browser" '"themes"' browser_view
expect_poll "the route theme leaves no launcher open" absent read_launcher opened
expect "the host hides the browser the route opened" ok ipc shell hide overlay vgs.themes
expect_poll "the browser the route opened closed" 0 layer_count vgs:overlay

# Gaps. A user `general` gaps line after the loading line sets gaps of its
# own; the toggle's workspace rule wins over it, and turning the toggle off
# gives the user's back.
hypr_lua_save style
printf '%s\n' 'hl.config({ general = { gaps_in = 11, gaps_out = 37 } })' >>"$hypr_lua"
expect "the nested instance reloads with the user's gaps" ok hypr reload config-only
expect_poll "the user's gaps line reaches Hyprland" 37 user_gaps_out
tile_pid=""
if open_tui org.vgs.smoke.tile; then tile_pid="$tui_pid"; else fail "the toplevel helper maps a tiled window"; fi
geometry expect_poll "a tiled window sits inside the user's outer gaps" '[37, 37, 37, 37]' tile_inset "$tile_pid"
expect "the layer writes no gap rule while the toggle is off" none gap_rule
open_style "No window gaps"
pick_row 2 || fail "selecting No window gaps failed"
expect_poll "No window gaps writes the setting to shell.json" true user_setting vgs.themes noWindowGaps
expect_poll "No window gaps closes the launcher" absent read_launcher opened
expect_poll "Hyprland holds the zero-gap workspace rule" '[[0, 0, 0, 0], [0, 0, 0, 0]]' gap_rule
geometry expect_poll "the tiled window fills the work area over the user's gaps" '[0, 0, 0, 0]' tile_inset "$tile_pid"
expect "Hyprland reports no configuration error" '[]' config_errors
open_style "the gaps label"
expect_poll "the gaps row then offers the default gaps" "$(style_rows "Default window gaps" "Hide top bar")" row_labels
expect "the host hides the launcher" ok ipc shell hide overlay vgs.launcher
# A theme carries no gaps: applying another, an installed copy of the
# catalog's flexoki-light, leaves the rule, and turning the toggle off then
# gives the user's gaps under that theme.
plant_flexoki_light "$home/.config/vgshell/themes" || fail "the flexoki-light copy could not be installed"
expect "applying the flexoki-light theme succeeds" "ok theme=flexoki-light" applied flexoki-light
expect_poll "the flexoki-light theme is applied" flexoki-light ipc smoke themeName
expect_poll "the zero-gap rule holds across a theme apply" '[[0, 0, 0, 0], [0, 0, 0, 0]]' gap_rule
geometry expect_poll "the tiled window still fills the work area" '[0, 0, 0, 0]' tile_inset "$tile_pid"
expect "the gaps IPC verb turns the gaps back on" ok ipc vgs.themes invoke gaps ''
expect_poll "the IPC verb writes the setting" false user_setting vgs.themes noWindowGaps
expect_poll "the zero-gap rule is gone" none gap_rule
geometry expect_poll "the tiled window sits inside the user's gaps again" '[37, 37, 37, 37]' tile_inset "$tile_pid"
expect "applying vgs again succeeds" "ok theme=vgs" applied vgs
expect_poll "vgs is applied again" vgs ipc smoke themeName
rm -rf -- "${home:?}/.config/vgshell/themes/flexoki-light"
[[ -z $tile_pid ]] || { tui_pid="$tile_pid"; close_tui "the tiled window's helper exits 0 on SIGTERM"; }
hypr_lua_restore style || fail "hyprland.lua is put back after the gaps rows"

geometry read_bar_settled "the bar set has settled before the bar is hidden"
# The bar. The toggle hides the bar on every screen and frees its space;
# the IPC verb shows it again. Each reading is the other's control.
open_style "Hide top bar"
pick_row 3 || fail "selecting Hide top bar failed"
expect_poll "Hide top bar writes vgs.bar's setting to shell.json" true user_setting vgs.bar hidden
expect_poll "no screen holds a bar surface" 0 bar_count
expect_poll "no monitor reserves space for a bar" 0 reserved_total
open_style "the bar label"
expect_poll "the bar row then offers to show the bar" "$(style_rows "No window gaps" "Show top bar")" row_labels
expect "the host hides the launcher" ok ipc shell hide overlay vgs.launcher
expect "the bar IPC verb shows the bar" ok ipc vgs.bar invoke toggle ''
expect_poll "the IPC verb writes the setting" false user_setting vgs.bar hidden
expect_poll "every screen holds its bar again" "$monitors" bar_count
expect_poll "the bar reserves its space again" "$bar_reserved" bar_top

# Both toggles hold across a restart. The bar starts hidden: no surface, no
# reserved space, and the services start at once, since no shown bar has a
# frame to wait for. A copy whose bar host maps a hidden bar, and one whose
# service gate waits for a hidden bar, are the controls.
expect "the bar toggle hides the bar for the restart" ok ipc vgs.bar invoke toggle ''
expect_poll "the bar is hidden before the restart" 0 bar_count
# A toggle's ok means shell.json holds the edit (Config.writeUser), so the
# stop follows the second toggle's answer with nothing between, and the file
# is read once the shell has ended. stop_shell fails the row itself when the
# instance lock stays held. A copy whose write comes 5 s after its answer
# is the control: its stop loses the edit.
expect "the gaps toggle turns gaps off for the restart" ok ipc vgs.themes invoke gaps ''
stop_shell || :
expect "the stopped shell left the gaps toggle in shell.json" true user_setting vgs.themes noWindowGaps
expect "the stopped shell left the bar toggle in shell.json" true user_setting vgs.bar hidden
restart_hidden() { # TREE LABEL
  if stop_shell && start_shell "$1" "$sandbox/style-$2.log" no-bar; then
    expect_poll "$2: the services start" true services_ready
  else
    fail "$2: the shell starts with the bar hidden"
  fi
}
restart_hidden "$repo" restart
expect_poll "the restarted shell keeps the bar hidden" 0 bar_count
expect_poll "the restarted shell reserves no bar space" 0 reserved_total
expect_poll "the restarted shell releases its services with no bar to wait for" no-bar services_released
expect_poll "the restarted shell writes the zero-gap rule again" '[[0, 0, 0, 0], [0, 0, 0, 0]]' gap_rule
copy_tree style-bar-host
if edit_tree style-bar-host shell/Hosts/BarHost.qml '            visible: PluginLogic.barShown(slot.instance)
' ''; then
  restart_hidden "$sandbox/tree-style-bar-host" control-bar-host
  expect_poll "control: a bar host that ignores shown maps the hidden bar" "$monitors" bar_count
fi
copy_tree style-service-gate
if edit_tree style-service-gate shell/Core/ServiceGate.qml ' && Logic.barShown(row.instance)) out.push' ') out.push'; then
  restart_hidden "$sandbox/tree-style-service-gate" control-service-gate
  expect_poll "control: a service gate that waits on a hidden bar releases at its deadline" deadline services_released
  expected_errors+=('plugins: services released reason=deadline')
fi
copy_tree style-late-save
if edit_tree style-late-save shell/Commons/WatchedFile.qml '        view.setText(content);' "        Qt.createQmlObject('import QtQuick; Timer { interval: 5000; running: true }', file).triggered.connect(() => view.setText(content));"; then
  restart_hidden "$sandbox/tree-style-late-save" control-late-save
  expect "control: the copy's gaps toggle answers ok" ok ipc vgs.themes invoke gaps ''
  stop_shell || :
  expect "control: a shell that defers the write loses the edit at the stop" true user_setting vgs.themes noWindowGaps
fi
restart_hidden "$repo" restored
expect "the bar IPC verb shows the bar after the restarts" ok ipc vgs.bar invoke toggle ''
expect_poll "every screen holds its bar after the restarts" "$monitors" bar_count
expect "the gaps IPC verb turns gaps back on after the restarts" ok ipc vgs.themes invoke gaps ''
expect_poll "the zero-gap rule is gone after the restarts" none gap_rule

# Disabling vgs.themes takes the Style category away, and the bar's row
# with it, whose parent vgs.themes declares. Each search comes in the
# summon's payload; the readings while the category stands are the
# controls of those after, and System, which a search for "s" lists either
# way, shows the search ran.
search_for() { # QUERY
  expect "search $1: the launcher summons on a search" ok ipc shell summon overlay vgs.launcher "{\"query\":\"$1\"}"
  expect_poll "search $1: the search reads the query" "\"$1\"" read_launcher filterText
}
search_for s
expect_poll "a search lists System" True launcher_has_row menu System
expect_poll "a search lists Style while vgs.themes is enabled" True launcher_has_row menu Style
search_for "top bar"
expect_poll "a search finds the bar row while Style stands" True launcher_has_row shortcut "Hide top bar"
expect "the host hides the launcher" ok ipc shell hide overlay vgs.launcher
expect "disabling vgs.themes is allowed" ok ipc shell setPluginEnabled vgs.themes false
expect_poll "vgs.themes' service is gone" False record_exists vgs.themes
search_for s
expect_poll "a search lists System without vgs.themes" True launcher_has_row menu System
expect_poll "Style is absent without vgs.themes" False launcher_has_row menu Style
search_for "top bar"
expect_poll "a search finds no bar row without its parent" False launcher_has_row shortcut "Hide top bar"
expect "the host hides the launcher" ok ipc shell hide overlay vgs.launcher
if [[ $themes_were_enabled == True ]]; then
  expect "enabling vgs.themes again is allowed" ok ipc shell setPluginEnabled vgs.themes true
  expect_poll "vgs.themes' service is back" True record_exists vgs.themes
fi
expect "disabling the launcher after the Style rows is allowed" ok ipc shell setPluginEnabled vgs.launcher false
expect_poll "the launcher holds no surface after the Style rows" 0 layer_count vgs:overlay
