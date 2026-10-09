# The user's Appearance values over the theme (D104): capability
# `appearance`, the one writer of shell.json `appearance`, Theme's one
# resolution of it, the Hyprland layer that writes it, and the Motion,
# Windows and UI sections of the System window that set it.
#
# Through the acme.appearance fixture the row writes a corner radius of 12
# and reads it in the file, in the capability, in the window radius token,
# in a flyout's token at 12 * 0.75 = 9, in a menu entry that follows its
# menu, in the nested Hyprland's rounding and in its group tab rounding at
# half the radius times the layer's highest monitor scale; it reads that the
# capability refuses Use my Hyprland value for the control radius and writes
# nothing, that a motion style reaches the Hyprland preset, and that an
# unset puts the theme's values back. Only the fixture holds the capability.
#
# In the Windows section it reads the corner radius Set by theme, clicks the
# slider to about 24, adds a user line `rounding = 10` after the VGS loading line,
# reads that the section's value holds over it and that the row names the
# user's 10, clicks Use my Hyprland value and reads the setting, the layer's
# radius group and VGS's rounding gone, Hyprland's 10 shown and the keys on
# the slider, then Use theme value. A section a click on the sidebar opens
# shows no focus ring. In the Motion
# section Space turns Motion off and every duration goes still, Use theme
# value moves them again, and Window animations writes Hyprland's
# animations. In the UI section End sets the control radius to 16 for
# buttons, text fields and segmented controls.
#
# Control run on 2026-10-08, host cachy, through this row after
# hyprland-consent, on a source_tree copy of the shell whose
# ThemeLogic.APPEARANCE_RATIOS gives flyouts the full radius: "a flyout
# takes three quarters of it, 12 * 0.75" and "a menu entry follows its
# menu" failed, each reading 12.
#
# No latency is budgeted: each reading polls through expect_poll every
# 0.2 s for up to the harness's poll bound. The row leaves the user file,
# hyprland.lua, the plugins directory and every enablement as it found
# them.
# inputs: shell/plugins/vgs.motion/* shell/plugins/vgs.windows/* shell/plugins/vgs.ui/* shell/plugins/vgs.system/* scripts/smoke/fixtures/plugins/acme.appearance/* shell/Commons/ThemeLogic.js shell/Commons/ThemeSource.qml shell/Commons/Theme.qml shell/Commons/Tokens.js shell/Core/Config.qml shell/Core/Capabilities.qml shell/Core/PluginLogic.js shell/Core/HyprlandLayer.* shell/Core/HyprlandState.* shell/Core/Plugins.qml shell/Hosts/PaneHost.qml shell/Ui/controls/ValueSourceRow.qml shell/Ui/controls/FormRow.qml shell/Ui/controls/RowAction.qml shell/Ui/controls/RowActions.qml shell/Ui/controls/Slider.qml shell/Ui/controls/SavedSlider.qml shell/Ui/controls/Switch.qml scripts/smoke/Probe.qml scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail

app_file="$home/.config/vgshell/shell.json"
app_layer="$home/.local/state/vgshell/hypr/vgs.lua"
app_fixture="$home/.config/vgshell/plugins/acme.appearance"
cp -- "$app_file" "$sandbox/shell-before-appearance-row.json"
hypr_lua_save appearance
app_system_was="$(plugin_enabled vgs.system)" || fail "vgs.system's enabled state is unreadable"

app_read() { ipc smoke readInstance service acme.appearance "$1"; }
app_source() { app_read sources | py_reply 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }
app_set() { ipc smoke invokeInstance service acme.appearance set "$1"; }
app_unset() { ipc smoke invokeInstance service acme.appearance unset "$1"; }
app_refused() { app_set "$1" | py_reply 'import sys; print("refused" if sys.stdin.read().startswith("refused: ") else "accepted")'; }
app_key_path() { app_read keys | py_reply 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]]["hyprland"])' "$1"; }
# Whether the file's corner radius is a whole number within 2 of WANT.
app_saved_radius() { python3 -c 'import json,sys; v=(json.load(open(sys.argv[1])).get("appearance") or {}).get("windowRadius"); print("near" if isinstance(v, int) and abs(v - int(sys.argv[2])) <= 2 else json.dumps(v))' "$app_file" "$1"; }
app_holders() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["holders"].get("appearance", [])))'; }
# The user file's `appearance`, `null` for none.
app_saved() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])).get("appearance"), sort_keys=True))' "$app_file"; }
hypr_int() { hypr -j getoption "$1" | py_reply 'import json,sys; print(json.load(sys.stdin)["int"])'; }
hypr_bool() { hypr -j getoption "$1" | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps(v.get("bool", v.get("int"))))'; }
app_layer_has() { if grep -qE -- "$1" "$app_layer"; then echo yes; else echo no; fi; }
# Group tabs against the layer: half the radius, 6, times the highest
# monitor scale the layer names, rounded and bounded to 20, as
# HyprlandLayer.radiusLines writes it.
app_groupbar() {
  local scale got
  scale="$(sed -n 's/.*group tab radius (6) times the highest monitor scale (\([0-9.]*\)).*/\1/p' "$app_layer" | head -n 1)"
  [[ -n $scale ]] || { echo "layer=unwritten"; return; }
  got="$(hypr_int group:groupbar:rounding)" || return
  python3 -c 'import sys; want = min(20, int(6 * float(sys.argv[1]) + 0.5)); print("ok" if int(sys.argv[2]) == want else "want=%d got=%s" % (want, sys.argv[2]))' "$scale" "$got"
}
# A section's row labelled LABEL, its PROPERTY as JSON.
app_row() { ipc smoke readMatchingDescendant window "$1" ValueSourceRow label "$2" "$3"; }
# The screen centre of the first shown row action named NAME in section ID,
# once two readings 0.1 s apart match.
app_action_point() { # ID NAME
  local rect now last=""
  for _ in $(seq 1 30); do
    rect="$(ipc smoke descendantGeometry window "$1" | py_reply 'import json,sys; r=[i["box"] for i in json.load(sys.stdin) if i["name"] == sys.argv[1] and i["visible"]]; print(json.dumps(r[0]) if r else "absent")' "$2")" || return 1
    [[ $rect == \[* ]] || { sleep 0.1; continue; }
    now="$(at_centre "window:System Settings" "$rect")" || return 1
    [[ $now == "$last" ]] && { echo "$now"; return 0; }
    last="$now"
    sleep 0.1
  done
  echo "app_action_point: no settled $2 in $1" >&2
  return 1
}
app_click_action() { # ID NAME
  local x y
  read -r x y < <(app_action_point "$1" "$2") || { fail "the $2 action of $1 has no box"; return; }
  hover "$x" "$y" || fail "hovering the $2 action of $1 failed"
  click "$x" "$y" || fail "clicking the $2 action of $1 failed"
}
# The screen point FRACTION along the first shown slider of section ID.
app_slider_point() { # ID FRACTION
  local rect x y
  rect="$(ipc smoke descendantGeometry window "$1" | py_reply 'import json,sys; r=[i["box"] for i in json.load(sys.stdin) if i["type"] == "Slider" and i["visible"]]; print(json.dumps(r[0]) if r else "absent")')" || return 1
  [[ $rect == \[* ]] || { echo "app_slider_point: no slider: $rect" >&2; return 1; }
  read -r x y < <(at_centre "window:System Settings" "$rect") || return 1
  python3 -c 'import json,sys; r=json.loads(sys.argv[1]); print(int(int(sys.argv[2]) - r[2] / 2 + r[2] * float(sys.argv[4])), sys.argv[3])' "$rect" "$x" "$y" "$2"
}
app_focus() { ipc smoke activeFocusItem window "$1"; }
app_visual_focus() { ipc smoke readShownDescendant window "$1" Slider visualFocus; }

# The capability, through the fixture.
mkdir -p "$app_fixture"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.appearance/." "$app_fixture/"
rescan "rescan discovers the appearance fixture"
expect_poll "the appearance fixture is known" True plugin_known acme.appearance
expect "enabling the appearance fixture is allowed" ok ipc shell setPluginEnabled acme.appearance true
expect_poll "the appearance fixture builds" True record_exists acme.appearance
expect_poll "the fixture reads back the exact appearance members it was given" '"keys,set,sources,theme,unset,values"' app_read members
expect "only the fixture holds the appearance capability" '["acme.appearance"]' app_holders
expect "the fixture reads no value before one is set" '{}' app_read values
expect "the corner radius reads Set by theme" theme app_source windowRadius
expect "the corner radius maps to Hyprland's rounding" decoration.rounding app_key_path windowRadius
expect "a corner radius of 12 is written" ok app_set '{"key":"windowRadius","value":12}'
expect "the user file holds the corner radius" '{"windowRadius": 12}' app_saved
expect_poll "the fixture reads the corner radius back" '{"windowRadius":12}' app_read values
expect "the corner radius reads as the user's" user app_source windowRadius
expect_poll "the window radius token is the user's 12" 12 ipc smoke themeValue hyprland.window.radius
expect_poll "a flyout takes three quarters of it, 12 * 0.75" 9 ipc smoke themeValue popover.radius
expect_poll "a menu entry follows its menu" 9 ipc smoke themeValue menu.item.radius
expect_poll "group tabs take half of it" 6 ipc smoke themeValue hyprland.window.groupRadius
expect_poll "Hyprland's window rounding is the user's 12" 12 hypr_int decoration:rounding
expect_poll "Hyprland's group tabs take half the radius times the highest scale" ok app_groupbar
expect "Use my Hyprland value is refused for the control radius" refused app_refused '{"key":"controlRadius","value":"hyprland"}'
expect "a refused value leaves the user file as it was" '{"windowRadius": 12}' app_saved
expect "the Snappy style is written" ok app_set '{"key":"motionStyle","value":"snappy"}'
expect_poll "the Snappy style reaches the Hyprland preset token" '"snappy"' ipc smoke themeValue hyprland.motion.preset
expect "the style is unset" ok app_unset motionStyle
expect "the corner radius is unset" ok app_unset windowRadius
expect "the user file holds no Appearance value" null app_saved
expect_poll "the flyout radius is the theme's again" 0 ipc smoke themeValue popover.radius
expect_poll "Hyprland's window rounding is the theme's again" 0 hypr_int decoration:rounding
expect "disabling the appearance fixture is allowed" ok ipc shell setPluginEnabled acme.appearance false
expect_poll "the appearance fixture is disabled" False plugin_enabled acme.appearance
rm -rf -- "${app_fixture:?}"
rescan "rescan removes the appearance fixture"

# The Windows section.
expect "enabling the System window is allowed" ok ipc shell setPluginEnabled vgs.system true
for id in vgs.motion vgs.windows vgs.ui; do
  expect "enabling $id is allowed" ok ipc shell setPluginEnabled "$id" true
done
expect "the Windows section summons" ok ipc shell summon window vgs.system '{"pane":"vgs.windows"}'
expect_poll "the Windows section is mounted" '["vgs.windows"]' window_panes
expect_poll "the corner radius row reads Set by theme" '"theme"' app_row vgs.windows "Corner radius" messageKind
expect "the border width row reads Set by theme" '"theme"' app_row vgs.windows "Border width" messageKind
read -r sx sy < <(app_slider_point vgs.windows 0.75) || fail "the corner radius slider has no box"
hover "$sx" "$sy" || fail "hovering the corner radius slider failed"
click "$sx" "$sy" || fail "clicking the corner radius slider failed"
# Three quarters along the slider is about 24, as the click lands.
expect_poll "the slider writes a corner radius of about 24" near app_saved_radius 24
app_radius="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["appearance"]["windowRadius"])' "$app_file")" || app_radius=unread
expect_poll "the row reads the user's value" '"user"' app_row vgs.windows "Corner radius" messageKind
expect_poll "Hyprland's rounding is the section's $app_radius" "$app_radius" hypr_int decoration:rounding
printf '%s\n' 'hl.config({ decoration = { rounding = 10 } })' >>"$home/.config/hypr/hyprland.lua"
expect "the nested instance reloads with the user's rounding" ok hypr reload config-only
expect_poll "the section's radius holds over the user's later line" "$app_radius" hypr_int decoration:rounding
expect_poll "the row names the user's own rounding" 10 app_row vgs.windows "Corner radius" hyprlandConfigValue
expect_poll "the row warns of the user's own line" '"config"' app_row vgs.windows "Corner radius" messageKind
app_click_action vgs.windows useHyprlandValue
expect_poll "Use my Hyprland value keeps the user's own radius in the file" '{"windowRadius": "hyprland"}' app_saved
expect_poll "the layer writes no radius group" no app_layer_has '^[[:space:]]*rounding ='
expect_poll "Hyprland's rounding is the user's 10" 10 hypr_int decoration:rounding
expect_poll "the row reads Set by your Hyprland config" '"hyprland"' app_row vgs.windows "Corner radius" messageKind
expect_poll "the row shows Hyprland's own 10" 10 app_row vgs.windows "Corner radius" shownValue
expect_poll "the action leaves the keys on the row's slider" '["Slider",null]' app_focus vgs.windows
app_click_action vgs.windows useThemeValue
expect_poll "Use theme value removes the corner radius from the file" null app_saved
expect_poll "the theme's radius holds over the user's line again" 0 hypr_int decoration:rounding
expect_poll "over the theme's value the row names the user's line" '"config"' app_row vgs.windows "Corner radius" messageKind
hypr_lua_restore appearance || fail "hyprland.lua is put back after the user's rounding"
expect "the nested instance reloads without the user's rounding" ok hypr reload config-only
expect_poll "the row reads Set by theme once the user's line is gone" '"theme"' app_row vgs.windows "Corner radius" messageKind

# A section a click on the sidebar opens takes the keys with no focus ring.
expect "the Motion section summons before the click" ok ipc shell summon window vgs.system '{"pane":"vgs.motion"}'
expect_poll "the Motion section is mounted before the click" '["vgs.motion"]' window_panes
app_entry="$(ipc smoke windowGeometry window vgs.system ListItem "Windows")" || app_entry=""
if read -r ex ey < <(at_centre "window:System Settings" "$app_entry"); then
  hover "$ex" "$ey" || fail "hovering the Windows entry failed"
  click "$ex" "$ey" || fail "clicking the Windows entry failed"
  expect_poll "a click on the Windows entry mounts its section" '["vgs.windows"]' window_panes
  expect_poll "the clicked section's slider holds the keys" '["Slider",null]' app_focus vgs.windows
  expect "a section a click opens shows no focus ring" false app_visual_focus vgs.windows
else
  fail "the Windows entry of the sidebar has no box: $app_entry"
fi

# The Motion section.
expect "the Motion section summons" ok ipc shell summon window vgs.system '{"pane":"vgs.motion"}'
expect_poll "the Motion section is mounted" '["vgs.motion"]' window_panes
expect_poll "the Motion row reads Set by theme" '"theme"' app_row vgs.motion Motion messageKind
expect_poll "the keyboard starts on the Motion switch" '["Switch",""]' app_focus vgs.motion
type_keys -k space || fail "Space on the Motion switch failed"
expect_poll "Space turns Motion off in the file" '{"motion": false}' app_saved
expect_poll "every duration goes still" 0 ipc smoke themeValue motion.duration.normal
expect_poll "the Motion row reads the user's value" '"user"' app_row vgs.motion Motion messageKind
app_click_action vgs.motion useThemeValue
expect_poll "Use theme value removes Motion from the file" null app_saved
expect_poll "the durations move again" 150 ipc smoke themeValue motion.duration.normal
app_switch="$(ipc smoke windowGeometry window vgs.motion Switch "Use these settings for windows")" || app_switch=""
if read -r wx wy < <(at_centre "window:System Settings" "$app_switch"); then
  hover "$wx" "$wy" || fail "hovering the Window animations switch failed"
  click "$wx" "$wy" || fail "clicking the Window animations switch failed"
  expect_poll "Window animations moves the windows with the shell's motion" '{"windowAnimations": true}' app_saved
  expect_poll "the layer writes the windows animation" yes app_layer_has '^[[:space:]]*hl\.animation\(\{ leaf = "windows"'
  expect_poll "Hyprland's animations are on" true hypr_bool animations:enabled
  expect_poll "the Window animations row reads the user's value" '"user"' app_row vgs.motion "Window animations" source
else
  fail "the Window animations switch has no box: $app_switch"
fi

# The UI section.
expect "the UI section summons" ok ipc shell summon window vgs.system '{"pane":"vgs.ui"}'
expect_poll "the UI section is mounted" '["vgs.ui"]' window_panes
expect_poll "the keyboard starts on the control radius slider" '["Slider",null]' app_focus vgs.ui
type_keys -k End || fail "End on the control radius slider failed"
expect_poll "End writes a control radius of 16 beside the window animations" '{"controlRadius": 16, "windowAnimations": true}' app_saved
expect_poll "buttons take the control radius" 16 ipc smoke themeValue button.radius
expect_poll "text fields take the control radius" 16 ipc smoke themeValue textField.radius
expect_poll "segmented controls take the control radius" 16 ipc smoke themeValue segmented.radius
expect "checkboxes keep the theme's radius" 0 ipc smoke themeValue checkbox.radius

expect "the System window hides after the Appearance sections" ok ipc shell hide window vgs.system
cp -- "$sandbox/shell-before-appearance-row.json" "$app_file.next" && mv -T -- "$app_file.next" "$app_file"
expect "the configuration reloads as the row found it" ok ipc shell reloadConfig
expect_poll "the control radius is the theme's again" 0 ipc smoke themeValue button.radius
expect_poll "Hyprland's animations are the user's own again" no app_layer_has '^[[:space:]]*hl\.animation\(\{ leaf = "windows"'
expect_poll "vgs.system's enablement is as the row found it" "$app_system_was" plugin_enabled vgs.system
