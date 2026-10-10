# The launcher, vgs.launcher: a first-party overlay, bar entry and service.
# The harness starts it disabled; this row enables it, drives every path
# that opens it (the shortcut, the service's IPC, the host's summon and the
# bar entry), types into it on the nested seat and reads what it drew back
# through the probe: its rows, its look and its shader, and the hand over a
# row. A picker answers
# through two files under the sandbox's runtime directory, read here. The
# Packages holds Install, Update and Remove while vgs.updates is enabled.
# Those rows open floating TUIs, read back from the stand-in terminal
# scripts/smoke/rows/tui.sh left. The Settings category
# holds Plugin settings and, while vgs.system is enabled, System Settings,
# each opening its window. The row ends with the plugin disabled and every
# registration released.
# inputs: shell/plugins/vgs.launcher/* shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Service.qml shell/plugins/vgs.system/manifest.json shell/plugins/vgs.system/Service.qml shell/plugins/vgs.updates/* shell/Ui/BarWidget.qml scripts/smoke/fixtures/plugins/acme.tui/* shell/Ui/layout/ListCursor.qml shell/Core/TuiRunner.qml shell/Core/ShortcutRegistry.qml shell/Core/PluginLogic.js shell/Core/PluginStatus.qml bin/vgshell-tui shell/Commons/DesktopLaunch.js scripts/smoke/rows/capabilities.sh scripts/smoke/rows/tui.sh shell/Ui/foundation/GlassSurface.qml shell/Commons/Glass.js
set -euo pipefail
launcher() { ipc vgs.launcher invoke "$1" "${2:-}"; }
tui_fixture() { ipc acme.tui invoke "$1" "${2:-}"; }
read_launcher() { ipc smoke readInstance overlay vgs.launcher "$1"; }
launcher_rows() { ipc smoke launcherRows overlay vgs.launcher | py_reply 'import json,sys; t=sys.stdin.read(); print(json.dumps(json.loads(t)) if t.startswith("[") else t.strip())'; }
# The launcher's rows whose kind is $1, as [label, detail] pairs.
rows_of() { launcher_rows | py_reply 'import json,sys; print(json.dumps([[l, d] for k, l, d in json.load(sys.stdin) if k == sys.argv[1]]))' "$1"; }
tui_labels() { launcher_rows | py_reply 'import json,sys; print(json.dumps([l for k, l, d in json.load(sys.stdin) if k == "tui"]))'; }
launcher_has_row() { launcher_rows | py_reply 'import json,sys; print(any(r[0] == sys.argv[1] and r[1] == sys.argv[2] for r in json.load(sys.stdin)))' "$1" "$2"; }
# Notification rows publish an unrelated has_row helper later in the run.
# The launcher keeps its reader when that producer replaces the generic name.
launcher_row_namespace_case() (
  local reader="$1" got
  launcher_rows() { printf '%s\n' '[["menu","System"]]'; }
  has_row() { printf 'False\n'; }
  got="$("$reader" menu System)" || return 1
  [[ $got == True ]]
)
if launcher_row_namespace_case launcher_has_row; then ok "the launcher reader survives an unrelated row-reader replacement"; else fail "the launcher reader lost its row after replacement"; fi
if launcher_row_namespace_case has_row; then fail "control: the generic row reader survived replacement"; else ok "control: the generic row reader loses the launcher row after replacement"; fi
setup_notice() { launcher_rows | py_reply 'import json,sys; print(any(r[0] == "notice" and r[1].startswith("The setup window could not open.") for r in json.load(sys.stdin)))'; }
first_row() { launcher_rows | py_reply 'import json,sys; r=json.load(sys.stdin); print(json.dumps(r[0][:2]) if r else "none")'; }
lent_launcher() { ipc shell lent | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([[s for s in d["shortcuts"] if s.startswith("vgs.launcher")], [t for t in d["ipcTargets"] if t == "vgs.launcher"]]))'; }
file_text() { if [[ -f $1 ]]; then python3 -c 'import sys; print(repr(open(sys.argv[1]).read()))' "$1"; else echo absent; fi; }
file_search_children() { ps -e -o ppid=,args= | python3 -c 'import sys; print(sum(1 for l in sys.stdin if l.split(None, 1)[0] == sys.argv[1] and "file-search.sh" in l))' "$shell_qs_pid"; }
# The launcher's own look as the running instance holds it, one path.
look_at() { read_launcher look | py_reply 'import json,sys; v=json.load(sys.stdin)
for k in sys.argv[1].split("."): v=v[k]
print(json.dumps(v))' "$1"; }
theme="$home/.config/vgshell/theme.json"
write_theme() { printf '%s\n' "$1" >"$theme.tmp" && mv -T -- "$theme.tmp" "$theme"; }
user_menu="$home/.config/vgshell/launcher/menu.json"
write_menu() { mkdir -p -- "${user_menu%/*}" && printf '%s\n' "$1" >"$user_menu.tmp" && mv -T -- "$user_menu.tmp" "$user_menu"; }
launcher_shell_config="$home/.config/vgshell/shell.json"
launcher_save_shell_config() { # NAME
  if [[ -e $launcher_shell_config ]]; then
    cp -p -- "$launcher_shell_config" "$sandbox/launcher-shell-$1.json"
  else
    rm -f -- "$sandbox/launcher-shell-$1.json"
    : >"$sandbox/launcher-shell-$1.absent"
  fi
}
launcher_same_shell_config() { # NAME
  if [[ -e $sandbox/launcher-shell-$1.json ]]; then
    if cmp -s -- "$launcher_shell_config" "$sandbox/launcher-shell-$1.json"; then echo same; else echo differs; fi
  elif [[ -e $launcher_shell_config ]]; then
    echo present
  else
    echo same
  fi
}
launcher_restore_shell_config() { # NAME LABEL
  if [[ -e $sandbox/launcher-shell-$1.json ]]; then
    cp -p -- "$sandbox/launcher-shell-$1.json" "$launcher_shell_config.next"
    mv -T -- "$launcher_shell_config.next" "$launcher_shell_config"
  else
    rm -f -- "${launcher_shell_config:?}"
  fi
  expect "$2: the shell reads the restored configuration" ok ipc shell reloadConfig
  expect_poll "$2: the restored configuration settles" true ipc smoke configSettled
  expect "$2: shell.json is as vgs.updates found it" same launcher_same_shell_config "$1"
}
selection="$rt_dir/launcher-selection"
done_file="$rt_dir/launcher-done"
reset_answer() { rm -f -- "${selection:?}" "${done_file:?}"; }
# The compositor hands a new layer the keyboard after it maps; a row types
# only once the launcher holds it.
focused() { expect_poll "${1:-the launcher holds the keyboard}" true ipc smoke activeFocusIn overlay vgs.launcher; }

# An application the apps menu lists, whose launch leaves a file behind.
mkdir -p -- "$home/.local/share/applications"
printf '[Desktop Entry]\nType=Application\nName=Smoke Launch Probe\nGenericName=Probe\nIcon=vgssmokeunknownicon\nExec=touch %s\n' "$home/launched-app" >"$home/.local/share/applications/smoke-launch-probe.desktop"
# Files the file search finds, one name twice.
mkdir -p -- "$home/launcher-files/older"
touch -- "$home/launcher-files/smoke-report.txt"
touch -d '2020-01-01' -- "$home/launcher-files/older/smoke-report.txt"

expect "the launcher starts disabled in the sandbox" False plugin_enabled vgs.launcher
expect "enabling the launcher is allowed" ok ipc shell setPluginEnabled vgs.launcher true
expect_poll "the launcher's service is built" True record_exists vgs.launcher
expect_poll "the service registered its shortcut and IPC target" '[["vgs.launcher:toggle"], ["vgs.launcher"]]' lent_launcher
launcher_shortcuts() { hypr globalshortcuts | python3 -c 'import sys; print(sum(1 for line in sys.stdin if "vgs.launcher:toggle" in line))'; }
expect_poll "the compositor lists the launcher's shortcut" 1 launcher_shortcuts
expect "a closed launcher holds no surface" 0 layer_count vgs:overlay

# The service's IPC summons the overlay: the bare search field, no rows.
expect "the service summons the launcher" ok launcher summon '{}'
expect_poll "the launcher maps one overlay surface" 1 layer_count vgs:overlay
expect_poll "the launcher is open" true read_launcher opened
focused "the open launcher holds the keyboard"
expect "the launcher opens as a bare search field" '[]' launcher_rows
expect "the bare field shows no list" 0 read_launcher visibleRowsHeight
shader_ok() { ipc smoke launcherShader overlay vgs.launcher | py_reply 'import json,re,sys; d=json.loads(sys.stdin.read()); print(bool(re.search(r"/vgshell-sources-[0-9]+/[0-9a-f]+/shaders/edgelight\.frag\.qsb$", d["url"])) and d["compiled"])'; }
render expect_poll "the edge light's shader compiled from the published revision" True shader_ok

# Typing searches every row and application; Enter launches the first.
type_keys "smoke launch" || fail "typing into the launcher failed"
expect_poll "typing reaches the search" '"smoke launch"' read_launcher filterText
expect_poll "the search ranks the planted application first" '["app", "Smoke Launch Probe"]' first_row
# The planted application names an icon no theme has, one word, since an
# icon theme lookup drops a dashed name's last part and tries again: its
# row shows the application glyph on a tile, so its title never keeps an empty tile's
# indentation. The control is at the end of the file search block.
glyph_tiles() { ipc smoke itemValues overlay vgs.launcher IconTile iconName,visible | py_reply 'import json,sys; print("app-window" in [v["iconName"] for v in json.load(sys.stdin) if v["visible"]])'; }
expect_poll "an application whose icon no theme has shows the glyph tile" True glyph_tiles
type_keys -k Return || fail "sending Return failed"
expect_poll "Enter launched the application" True bash -c '[[ -f $1 ]] && echo True' _ "$home/launched-app"
expect_poll "a launch closes the launcher" 0 layer_count vgs:overlay

# Settings: Plugins, always on, declares the category and its Plugin
# settings row in its manifest's `menu`; vgs.system adds System Settings
# under it while enabled. Each row runs its plugin's `open` shortcut, which
# opens its window. The reading with vgs.system enabled is the control of
# the reading without it, and a user menu file that relabels Plugin
# settings is the control of the Plugin settings reading.
launcher_settings_open() { # LABEL
  expect "$1: the launcher opens on Settings" ok ipc shell summon overlay vgs.launcher '{"menu":"settings"}'
  expect_poll "$1: the Settings menu is open" '"settings"' read_launcher activeMenu
  focused "$1: the launcher holds the keyboard"
}
launcher_window_open() { [[ $(ipc smoke instanceGeometry window "$1") != absent ]] && echo open || echo closed; }
expect "vgs.system starts disabled in the sandbox" False plugin_enabled vgs.system
launcher_settings_open "without System"
expect_poll "Settings lists Plugin settings" True launcher_has_row shortcut "Plugin settings"
expect "Settings lists no System Settings while vgs.system is disabled" False launcher_has_row shortcut "System Settings"
type_keys -k Return || fail "selecting Plugin settings failed"
expect_poll "Plugin settings opens the Plugins window" open launcher_window_open vgs.settings
expect_poll "the launcher closes on Plugin settings" 0 layer_count vgs:overlay
expect "the Plugins window hides after Plugin settings" ok ipc shell hide window vgs.settings
expect_poll "the Plugins window is gone after Plugin settings" closed launcher_window_open vgs.settings
expect "enabling vgs.system for the Settings rows is allowed" ok ipc shell setPluginEnabled vgs.system true
expect_poll "vgs.system's service is built for the Settings rows" True record_exists vgs.system
launcher_settings_open "with System"
expect_poll "control: Settings lists System Settings while vgs.system is enabled" True launcher_has_row shortcut "System Settings"
expect "Settings lists Plugin settings beside System Settings" True launcher_has_row shortcut "Plugin settings"
type_keys -k Down -k Return || fail "selecting System Settings failed"
expect_poll "System Settings opens the System window" open launcher_window_open vgs.system
expect_poll "the launcher closes on System Settings" 0 layer_count vgs:overlay
expect "the System window hides after System Settings" ok ipc shell hide window vgs.system
expect_poll "the System window is gone after System Settings" closed launcher_window_open vgs.system
expect "disabling vgs.system after the Settings rows is allowed" ok ipc shell setPluginEnabled vgs.system false
expect_poll "vgs.system's service is gone after the Settings rows" False record_exists vgs.system
write_menu '{ "schemaVersion": 1, "items": { "settings.plugins": { "label": "Smoke plugins" } } }'
launcher_settings_open "relabelled"
expect_poll "control: a user menu that relabels Plugin settings shows its label" True launcher_has_row shortcut "Smoke plugins"
expect "control: the relabelled menu reads no Plugin settings" False launcher_has_row shortcut "Plugin settings"
expect "the host hides the relabelled launcher" ok ipc shell hide overlay vgs.launcher
expect_poll "the relabelled launcher closes" 0 layer_count vgs:overlay
rm -f -- "${user_menu:?}"

# Categories: Ctrl+B shows the tree; a route opens a submenu by id or alias.
expect "the service toggles the launcher open" ok launcher toggle ''
expect_poll "the toggled launcher maps" 1 layer_count vgs:overlay
focused
type_keys -M ctrl -k b -m ctrl || fail "sending Ctrl+B failed"
expect_poll "Ctrl+B shows the categories" True launcher_has_row menu System
expect "Packages is hidden while vgs.updates is disabled" False launcher_has_row menu Packages
expect "the categories list Settings, which always-on Plugins declares" True launcher_has_row menu Settings
type_keys -M ctrl -k b -m ctrl || fail "sending Ctrl+B failed"
expect_poll "Ctrl+B hides them again" '[]' launcher_rows
expect "a route by alias opens its menu" ok ipc shell summon overlay vgs.launcher '{"menu":"power-menu"}'
expect_poll "the alias resolved to the system menu" '"system"' read_launcher activeMenu
expect_poll "the submenu lists its actions" True launcher_has_row action Reboot
type_keys -k BackSpace || fail "sending BackSpace failed"
expect_poll "BackSpace on an empty search goes back" '"root"' read_launcher activeMenu
expect "a query payload opens with the search filled" ok ipc shell summon overlay vgs.launcher '{"query":"reb"}'
expect_poll "the query searched the rows" True launcher_has_row action Reboot
focused
type_keys -k Escape -k Escape || fail "sending Escape failed"
expect_poll "Escape clears the search, then closes" 0 layer_count vgs:overlay

# TUI rows open their TUI through the tui capability. The argv reaches the
# stand-in xdg-terminal-exec harness.sh's terminal_stand_in wrote, read
# with the harness's `words`, `core_words`, `recorded`, `forget_record` and
# `expect_run_end`. vgs.updates owns the Packages category. Install and
# Remove open the core's package pickers, and Update opens vgs.updates/update.
# The index of the launcher's row of kind $1 and label $2, or none.
row_index() { launcher_rows | py_reply 'import json,sys; r=[i for i, x in enumerate(json.load(sys.stdin)) if x[0] == sys.argv[1] and x[1] == sys.argv[2]]; print(r[0] if r else "none")' "$1" "$2"; }
# categories LABEL: summon the launcher and show its categories.
categories() {
  expect "the launcher summons for $1" ok ipc shell summon overlay vgs.launcher '{}'
  focused
  type_keys -M ctrl -k b -m ctrl || fail "sending Ctrl+B failed"
  expect_poll "the categories show for $1" True launcher_has_row menu System
}

# Keyboard-only path: the list cursor moves by edges, Escape backs out of a
# user-opened submenu, and Right opens only menus.
row_count() { launcher_rows | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
categories "keyboard-only list"
last_index="$(row_count)"
last_index="$((last_index - 1))"
type_keys -k End || fail "sending End in the launcher failed"
expect_poll "End moves to the last launcher row" "$last_index" read_launcher selectedIndex
type_keys -k Home || fail "sending Home in the launcher failed"
expect_poll "Home moves to the first launcher row" 0 read_launcher selectedIndex
system_index="$(row_index menu System)" || system_index=none
if [[ $system_index =~ ^[0-9]+$ ]]; then
  keys=()
  for ((n = 0; n < system_index; n++)); do keys+=(-k Down); done
  if ((system_index > 0)); then type_keys "${keys[@]}" || fail "moving to System failed"; fi
  type_keys -k Return || fail "opening System from the keyboard failed"
  expect_poll "Return opens the user-selected submenu" '"system"' read_launcher activeMenu
  type_keys -k Escape || fail "sending Escape from the submenu failed"
  expect_poll "Escape leaves the user-selected submenu open launcher" '"root"' read_launcher activeMenu
  expect "Escape from a user-selected submenu keeps the launcher open" 1 layer_count vgs:overlay
  type_keys -k Escape || fail "closing after the submenu keyboard path failed"
  expect_poll "the launcher closes after the submenu keyboard path" 0 layer_count vgs:overlay
else
  fail "System row was not found for the launcher keyboard-only path"
fi
expect "a direct menu payload opens for Escape control" ok ipc shell summon overlay vgs.launcher '{"menu":"power-menu"}'
expect_poll "the direct payload opens the system menu" '"system"' read_launcher activeMenu
type_keys -k Escape || fail "sending Escape for the direct payload control failed"
expect_poll "Escape closes a direct payload menu" 0 layer_count vgs:overlay

# pick_tui LABEL: in the open list, move the cursor to the tui row LABEL
# and press Return. The pointer rests over the list, which opens and
# animates under it, so Qt delivers the rows hover with no motion; the
# launcher must not read that as a pointer taking the cursor.
pick_tui() {
  local index n keys=()
  index="$(row_index tui "$1")" || { fail "the launcher's rows are unreadable for $1"; return 1; }
  [[ $index =~ ^[0-9]+$ ]] || { fail "no tui row $1 to pick: $index"; return 1; }
  for ((n = 0; n < index; n++)); do keys+=(-k Down); done
  if ((index > 0)); then type_keys "${keys[@]}" || { fail "moving to $1 failed"; return 1; }; fi
  expect_poll "the cursor rests on $1" "$index" read_launcher selectedIndex
  expect "the resting pointer took no row before $1" false ipc smoke readShownDescendant overlay vgs.launcher ListCursor armed
  type_keys -k Return || fail "sending Return on $1 failed"
}
update_words() {
  local update_snapshot="$1"
  words --app-id=org.vgs.tui.tall "--title=VGS · Update everything" -- "$tui_self" present --presentation full --plugin vgs.updates --dir "$update_snapshot" \
    --record vgs.updates/update --run RUN --record-dir "$rt_dir/vgshell/tui" --app-id org.vgs.tui.tall --window-title "VGS · Update everything" -- tui/update.sh
}
packages_menu() {
  expect "the launcher opens Packages for $1" ok ipc shell summon overlay vgs.launcher '{"menu":"packages"}'
  expect_poll "the Packages menu is open for $1" '"packages"' read_launcher activeMenu
  focused "the Packages menu holds the keyboard for $1"
}
# The pointer rests at the screen's centre, over the rows the categories
# list, where Hyprland's warp to a focused window's centre leaves it after
# the gallery's window rows.
hover "$((mon_w / 2))" "$((mon_h / 2))" || fail "resting the pointer at the screen's centre failed"
expect "vgs.updates starts disabled for Packages" False plugin_enabled vgs.updates
categories "Packages disabled"
expect "Packages is absent before vgs.updates is enabled" False launcher_has_row menu Packages
launcher_save_shell_config packages
# The shipped updates service would probe the real host without a fresh cache.
updates_cache_fresh
expect "enabling vgs.updates while the launcher is open is allowed" ok ipc shell setPluginEnabled vgs.updates true
expect_poll "vgs.updates' service is built for Packages" True record_exists vgs.updates
expect_poll "control: Packages appears when vgs.updates is enabled" True launcher_has_row menu Packages
type_keys -k Escape || fail "sending Escape before Packages TUI rows failed"
expect_poll "Escape closes the Packages category control" 0 layer_count vgs:overlay
for row in "Install|install|Install packages" "Remove|remove|Remove packages"; do
  IFS='|' read -r label verb title <<<"$row"
  forget_record
  packages_menu "$label"
  pick_tui "$label"
  expect_poll "$label hands the terminal the core's vgshell pkg $verb" "$(core_words "core/pkg-$verb" "$title" org.vgs.tui pkg "$verb")" recorded
  expect_poll "$label closes the launcher" 0 layer_count vgs:overlay
  expect_run_end "the $verb picker's run ends" "core/pkg-$verb"
done

# A held core picker leaves its key busy. The second launcher pick follows
# shell.tui.open's shared shown answer, so it closes without a notice, and
# IPC sees the same answer while the runner focuses the live window.
forget_record
hold_runs
packages_menu "held Install"
pick_tui Install
expect_poll "held Install hands the terminal the core's vgshell pkg install" "$(core_words core/pkg-install "Install packages" org.vgs.tui pkg install)" recorded
expect_poll "the held install picker stays live" busy key_idle core/pkg-install
expect_poll "held Install closes the launcher" 0 layer_count vgs:overlay
packages_menu "busy Install"
pick_tui Install
expect_poll "busy Install closes the launcher" 0 layer_count vgs:overlay
expect "busy Install is not logged as a launcher refusal" 0 log_lines 'launcher: tui core/pkg-install refused: tui=core/pkg-install reason=busy'
expect "IPC openTui answers ok for the busy install picker" ok ipc shell openTui core/pkg-install
release_runs
expect_run_end "the held install picker run ends" core/pkg-install

updates_revision="$(ipc shell listPlugins | py_reply 'import json,sys; print([p["revision"] for p in json.load(sys.stdin)["plugins"] if p["id"]=="vgs.updates"][0])')" || { fail "vgs.updates revision is readable for Packages"; updates_revision=""; }
updates_snapshot="$rt_dir/vgshell-sources-$shell_qs_pid/$updates_revision"
forget_record
packages_menu "Update"
expect "the Packages menu lists Install, Update and Remove in order" '["Install", "Update", "Remove"]' tui_labels
pick_tui Update
expect_poll "Update hands the terminal the updates plugin's Update script" "$(update_words "$updates_snapshot")" recorded
expect_poll "Update closes the launcher" 0 layer_count vgs:overlay
expect_run_end "the Update run ends" vgs.updates/update
categories "Packages disable"
expect "Packages shows while vgs.updates is enabled" True launcher_has_row menu Packages
expect "disabling vgs.updates while the launcher is open is allowed" ok ipc shell setPluginEnabled vgs.updates false
expect_poll "the open launcher hides Packages once vgs.updates is disabled" False launcher_has_row menu Packages
launcher_restore_shell_config packages "after Packages"
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape closes the launcher after Packages" 0 layer_count vgs:overlay

write_menu '{ "schemaVersion": 1, "items": { "tools.smoke-update": { "label": "Smoke update", "icon": "refresh-cw", "tuiGroup": "Update" } } }'
expect "the Update fixture starts disabled, as tui.sh left it" False plugin_enabled acme.tui
expect "the launcher opens Tools for the smoke update row" ok ipc shell summon overlay vgs.launcher '{"menu":"tools"}'
expect_poll "the Tools menu is open for the smoke update row" '"tools"' read_launcher activeMenu
focused "the Tools menu holds the keyboard for the smoke update row"
expect "Smoke update is hidden while the Update fixture is disabled" False launcher_has_row tui "Smoke update"
expect "enabling the Update fixture while the launcher is open is allowed" ok ipc shell setPluginEnabled acme.tui true
expect_poll "the open launcher shows Smoke update once the fixture lists Update" True launcher_has_row tui "Smoke update"
expect "disabling the Update fixture while the launcher is open is allowed" ok ipc shell setPluginEnabled acme.tui false
expect_poll "the open launcher hides Smoke update once the fixture leaves Update" False launcher_has_row tui "Smoke update"
type_keys -k Escape || fail "sending Escape after the smoke update row failed"
expect_poll "Escape closes the launcher after the smoke update row" 0 layer_count vgs:overlay
rm -f -- "${user_menu:?}"

# Plugin-published launcher providers: the category is hidden until the
# fixture publishes rows, live rows search from the root, and activation
# passes the provider's item id to the shortcut handler.
provider_marker="$rt_dir/launcher-provider-item"
rm -f -- "$provider_marker"
categories "empty plugin provider"
expect "the disabled provider fixture has no category" False launcher_has_row menu "Smoke provider"
expect "enabling the provider fixture while the launcher is open is allowed" ok ipc shell setPluginEnabled acme.tui true
expect_poll "the provider fixture's service is built" True record_exists acme.tui
expect "an enabled provider with no rows stays hidden" False launcher_has_row menu "Smoke provider"
expect "publishing provider rows is allowed" ok tui_fixture publish-launcher "$provider_marker"
expect_poll "publishing rows shows the provider category live" True launcher_has_row menu "Smoke provider"
expect "the launcher searches provider rows from the root" ok ipc shell summon overlay vgs.launcher '{"query":"provideralias"}'
focused "the provider search holds the keyboard"
expect_poll "root search finds the plugin provider row by alias" True launcher_has_row plugin "Smoke clean"
type_keys -k Return || fail "activating the provider row failed"
expect_poll "the provider row handed its item id to the shortcut" "'tools.clean'" file_text "$provider_marker"
expect_poll "the provider row activation closes the launcher" 0 layer_count vgs:overlay
expect "an unlisted provider item is refused" "refused: shortcut=acme.tui:open item=missing reason=unlisted" tui_fixture activate-launcher missing
categories "provider removal"
expect_poll "the provider category shows before disable" True launcher_has_row menu "Smoke provider"
expect "disabling the provider fixture while the launcher is open is allowed" ok ipc shell setPluginEnabled acme.tui false
expect_poll "disabling the provider fixture removes the category" False launcher_has_row menu "Smoke provider"
type_keys -k Escape || fail "sending Escape after provider disable failed"
expect_poll "Escape closes the launcher after provider disable" 0 layer_count vgs:overlay

# A refusal other than busy stays in the list as a notice. tui.sh's
# stand-in bin/vgshell-tui, which finds no terminal, makes the core's launcher
# state missing through one launch that answered ok; the next pick answers
# launcher-missing at once. The real one returns, and the probe a direct
# request starts finds the terminal again.
launcher_save_shell_config launcher-missing
# The shipped updates service would probe the real host without a fresh cache.
updates_cache_fresh
expect "enabling vgs.updates for launcher-missing is allowed" ok ipc shell setPluginEnabled vgs.updates true
expect_poll "vgs.updates is built for launcher-missing" True record_exists vgs.updates
cp -- "$sandbox/vgshell-tui.missing" "$repo/bin/vgshell-tui.next" && mv -T -- "$repo/bin/vgshell-tui.next" "$repo/bin/vgshell-tui"
expected_errors+=('tui: refused: tui=core/pkg-install reason=launcher-missing' 'launcher: tui core/pkg-install refused: tui=core/pkg-install reason=launcher-missing')
packages_menu "Install without a terminal"
pick_tui Install
expect_poll "the launch that answered ok closed the launcher" 0 layer_count vgs:overlay
expect_poll "the launch that found no terminal leaves the launcher state missing" '"missing"' lent tui.launcher
packages_menu "Install refused"
pick_tui Install
expect_poll "the launcher-missing answer shows as a notice" True setup_notice
expect_log "the launcher logs the refused TUI" 1 'launcher: tui core/pkg-install refused: tui=core/pkg-install reason=launcher-missing'
expect "the refused row leaves the launcher open" 1 layer_count vgs:overlay
expect_poll "the probe the refusal started ends" false lent tui.probing
cp -- "$sandbox/vgshell-tui.real" "$repo/bin/vgshell-tui.next" && mv -T -- "$repo/bin/vgshell-tui.next" "$repo/bin/vgshell-tui"
expect "a request before the next probe answers launcher-missing" "refused: tui=core/pkg-install reason=launcher-missing" ipc shell openTui core/pkg-install
expect_poll "the probe that request started finds the terminal again" '"present"' lent tui.launcher
expect "disabling vgs.updates after launcher-missing is allowed" ok ipc shell setPluginEnabled vgs.updates false
expect_poll "vgs.updates is gone after launcher-missing" False record_exists vgs.updates
launcher_restore_shell_config launcher-missing "after launcher-missing"
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape closes the refused launcher" 0 layer_count vgs:overlay

# A user menu merges over the shipped one per key; a route naming an action
# runs it without opening; a row whose command is missing says so.
write_menu "{ \"schemaVersion\": 1, \"items\": { \"system\": { \"label\": \"Power\" }, \"smoke-run\": { \"label\": \"Smoke run\", \"run\": [\"touch\", \"$home/ran-action\"] }, \"smoke-missing\": { \"label\": \"Smoke missing\", \"requires\": [\"no-such-command-smoke\"], \"run\": [\"no-such-command-smoke\"] } } }"
expect "a route naming an action runs it" ok ipc shell summon overlay vgs.launcher '{"menu":"smoke-run"}'
expect_poll "the action ran" True bash -c '[[ -f $1 ]] && echo True' _ "$home/ran-action"
expect_poll "an action route leaves no surface" 0 layer_count vgs:overlay
rm -f -- "$home/ran-action"
expect "the launcher summons with the action row as a search result" ok ipc shell summon overlay vgs.launcher '{"query":"Smoke run"}'
focused
expect_poll "the action row is selected by the query" '["action", "Smoke run"]' first_row
type_keys -k Right || fail "sending Right on an action row failed"
expect "Right on an action row does not run it" absent file_text "$home/ran-action"
expect "Right on an action row keeps the launcher open" 1 layer_count vgs:overlay
type_keys -k Return || fail "sending Return on an action row failed"
expect_poll "Return on the action row runs it" True bash -c '[[ -f $1 ]] && echo True' _ "$home/ran-action"
expect_poll "Return on the action row closes the launcher" 0 layer_count vgs:overlay
expect "the launcher summons with the categories" ok ipc shell summon overlay vgs.launcher '{}'
focused
type_keys -M ctrl -k b -m ctrl || fail "sending Ctrl+B failed"
expect_poll "the user's label replaced the shipped one" True launcher_has_row menu Power
missing_row() { rows_of unavailable | py_reply 'import json,sys; print(json.dumps([r for r in json.load(sys.stdin) if r[0] == "Smoke missing"]))'; }
expect_poll "a row with a missing command is unavailable and names it" '[["Smoke missing", "needs no-such-command-smoke"]]' missing_row
expected_errors+=('launcher: menu refused: file=.*/launcher/menu\.json items\.bad-item has unknown key "action"')
write_menu '{ "schemaVersion": 1, "items": { "bad-item": { "action": "other-menu" } } }'
expect_log "a user menu the judge refuses is logged with its defect" 1 'launcher: menu refused: file=.*/launcher/menu\.json items\.bad-item has unknown key "action"'
expect_poll "the refused user menu shows as a notice" True launcher_has_row notice "Your menu is unavailable"
expect_poll "the shipped menu stands after the refusal" True launcher_has_row menu System
rm -f -- "${user_menu:?}"
expect_poll "a removed user menu clears its notice" False launcher_has_row notice "Your menu is unavailable"
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape closes the launcher" 0 layer_count vgs:overlay

# A menu first created while the launcher is open, its directory absent
# when the launcher was summoned, is read: the launcher makes the directory
# before its watch starts.
rm -rf -- "${user_menu%/*}"
expect "the launcher summons without a menu directory" ok ipc shell summon overlay vgs.launcher '{}'
focused
type_keys -M ctrl -k b -m ctrl || fail "sending Ctrl+B failed"
expect_poll "the shipped menu shows with no user menu" True launcher_has_row menu System
expect_poll "the launcher made its menu directory" True bash -c '[[ -d $1 ]] && echo True' _ "${user_menu%/*}"
write_menu '{ "schemaVersion": 1, "items": { "system": { "label": "Power" } } }'
expect_poll "a menu created while the launcher is open is read" True launcher_has_row menu Power
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape closes the launcher" 0 layer_count vgs:overlay
rm -f -- "${user_menu:?}"

# Controls: a sandbox copy with one rule of the user menu's read taken out
# fails a check above that rests on it. The host builds the launcher from
# the revision the last completed scan published.
launcher_qml="$repo/shell/plugins/vgs.launcher/Launcher.qml"
cp -p -- "$launcher_qml" "$sandbox/Launcher.qml.real"
menu_model_js="$repo/shell/plugins/vgs.launcher/MenuModel.js"
cp -p -- "$menu_model_js" "$sandbox/MenuModel.js.real"
# launcher_source LABEL FILE: install FILE as the plugin's source and wait
# for the scan that publishes it; false when it could not be installed.
launcher_source() {
  cp -p -- "$2" "$launcher_qml.tmp" && mv -T -- "$launcher_qml.tmp" "$launcher_qml" || { fail "$1: $2 could not be installed"; return 1; }
  rescan "a rescan publishes $1"
}
# launcher_mutant LABEL OLD NEW: install the real source with OLD, which
# must occur once, replaced by NEW.
launcher_mutant() {
  if [[ $(grep -c -F -- "$2" "$sandbox/Launcher.qml.real") != 1 ]]; then
    fail "$1: its text occurs once in $launcher_qml"
    return 1
  fi
  python3 -c 'import sys; p, q, old, new = sys.argv[1:]; open(q, "w").write(open(p).read().replace(old, new))' "$sandbox/Launcher.qml.real" "$sandbox/Launcher.qml.mutant" "$2" "$3" || { fail "$1: the mutant could not be written"; return 1; }
  launcher_source "$1" "$sandbox/Launcher.qml.mutant"
}
menu_model_source() {
  cp -p -- "$2" "$menu_model_js.tmp" && mv -T -- "$menu_model_js.tmp" "$menu_model_js" || { fail "$1: $2 could not be installed"; return 1; }
  rescan "a rescan publishes $1"
}
menu_model_mutant() {
  if [[ $(grep -c -F -- "$2" "$sandbox/MenuModel.js.real") != 1 ]]; then
    fail "$1: its text occurs once in $menu_model_js"
    return 1
  fi
  python3 -c 'import sys; p, q, old, new = sys.argv[1:]; open(q, "w").write(open(p).read().replace(old, new))' "$sandbox/MenuModel.js.real" "$sandbox/MenuModel.js.mutant" "$2" "$3" || { fail "$1: the mutant could not be written"; return 1; }
  menu_model_source "$1" "$sandbox/MenuModel.js.mutant"
}

# A copy that always shows provider menus exposes an empty plugin provider
# category before its service publishes any rows.
if menu_model_mutant "the empty-provider control" 'if (entry.provider && entry.provider !== "plugin") return true;' 'if (entry.provider) return true;'; then
  categories "the empty-provider control"
  expect "enabling the provider fixture under the empty-provider control is allowed" ok ipc shell setPluginEnabled acme.tui true
  expect_poll "control: the provider fixture builds under the empty-provider control" True record_exists acme.tui
  expect_poll "control: the empty-provider control shows the empty category" True launcher_has_row menu "Smoke provider"
  expect "disabling the provider fixture under the empty-provider control is allowed" ok ipc shell setPluginEnabled acme.tui false
  expect "the host hides the empty-provider control" ok ipc shell hide overlay vgs.launcher
  expect_poll "the empty-provider control closed" 0 layer_count vgs:overlay
fi
menu_model_source "the restored menu model" "$sandbox/MenuModel.js.real" || true

# A copy that never reads on a change keeps the menu it read when it was
# built. It waits the five seconds of sleep in expect_poll's 25 polls, the
# window the real launcher had to show the refused menu's notice above.
if launcher_mutant "the unwatched control" 'onChanged: read()' 'onChanged: {}'; then
  write_menu '{ "schemaVersion": 1, "items": { "system": { "label": "Power" } } }'
  expect "the unwatched control summons" ok ipc shell summon overlay vgs.launcher '{}'
  focused "the unwatched control holds the keyboard"
  type_keys -M ctrl -k b -m ctrl || fail "sending Ctrl+B failed"
  expect_poll "the unwatched control read the user menu it was built with" True launcher_has_row menu Power
  write_menu '{ "schemaVersion": 1, "items": { "bad-item": { "action": "other-menu" } } }'
  sleep 5
  expect "the unwatched control keeps the menu it was built with" True launcher_has_row menu Power
  expect "the host hides the unwatched control" ok ipc shell hide overlay vgs.launcher
  expect_poll "the unwatched control closed" 0 layer_count vgs:overlay
fi

# A copy whose menus count as read from the start routes in open(), before
# either file's first read ends: a route to a user action opens the menu
# instead of running it. Which of the two reads ends first is not fixed,
# so the control takes the whole gate out rather than the user file's half.
rm -f -- "${home:?}/ran-action"
if launcher_mutant "the ungated control" 'readonly property bool menusReady: shippedSettled && userSettled' 'readonly property bool menusReady: true'; then
  write_menu "{ \"schemaVersion\": 1, \"items\": { \"smoke-run\": { \"label\": \"Smoke run\", \"run\": [\"touch\", \"$home/ran-action\"] } } }"
  expect "the ungated control is summoned with the action route" ok ipc shell summon overlay vgs.launcher '{"menu":"smoke-run"}'
  expect_poll "the ungated control opened a menu instead" true read_launcher opened
  expect "the ungated control ran no action" absent file_text "$home/ran-action"
  expect "the host hides the ungated control" ok ipc shell hide overlay vgs.launcher
  expect_poll "the ungated control closed" 0 layer_count vgs:overlay
fi

# A copy that makes no menu directory watches none when it is summoned
# without one, and a menu created while it is open goes unread. It waits the
# five seconds the real launcher had to read that menu above.
rm -rf -- "${user_menu%/*}"
if launcher_mutant "the undirected control" 'command: ["mkdir", "-p", "--", root.userDir]' 'command: ["true"]'; then
  expect "the undirected control summons" ok ipc shell summon overlay vgs.launcher '{}'
  focused "the undirected control holds the keyboard"
  type_keys -M ctrl -k b -m ctrl || fail "sending Ctrl+B failed"
  expect_poll "the undirected control shows the shipped menu" True launcher_has_row menu System
  write_menu '{ "schemaVersion": 1, "items": { "system": { "label": "Power" } } }'
  sleep 5
  expect "the undirected control never read the menu created while open" True launcher_has_row menu System
  expect "the host hides the undirected control" ok ipc shell hide overlay vgs.launcher
  expect_poll "the undirected control closed" 0 layer_count vgs:overlay
fi
rm -f -- "${user_menu:?}"

# A copy that resolves its TUI rows only when its menus are read keeps a
# user menu's Update group row hidden when the fixture is enabled while it
# is open. It waits the five seconds the real launcher had to show the row
# above.
if launcher_mutant "the unresolved control" 'onTuiEntriesChanged: {' 'function unresolved() {'; then
  write_menu '{ "schemaVersion": 1, "items": { "tools.smoke-update": { "label": "Smoke update", "icon": "refresh-cw", "tuiGroup": "Update" } } }'
  expect "the unresolved control opens Tools" ok ipc shell summon overlay vgs.launcher '{"menu":"tools"}'
  expect_poll "the unresolved control opens the Tools menu" '"tools"' read_launcher activeMenu
  focused "the unresolved control holds the keyboard"
  expect "the unresolved control hides Smoke update" False launcher_has_row tui "Smoke update"
  expect "enabling the Update fixture under the unresolved control is allowed" ok ipc shell setPluginEnabled acme.tui true
  sleep 5
  expect "the unresolved control keeps Smoke update hidden" False launcher_has_row tui "Smoke update"
  expect "disabling the Update fixture under the unresolved control is allowed" ok ipc shell setPluginEnabled acme.tui false
  expect "the host hides the unresolved control" ok ipc shell hide overlay vgs.launcher
  expect_poll "the unresolved control closed" 0 layer_count vgs:overlay
  rm -f -- "${user_menu:?}"
fi
launcher_source "the restored launcher" "$sandbox/Launcher.qml.real" || true

# A payload the judge refuses throws out of open(), and the host refuses the
# summon and takes the surface down.
expected_errors+=('summon host: vgs\.launcher open\(\) failed: launcher: refused: payload=')
expect "a payload that is not JSON is refused" "refused: open-failed=vgs.launcher" ipc shell summon overlay vgs.launcher 'nope'
expect "a payload with an unknown key is refused" "refused: open-failed=vgs.launcher" ipc shell summon overlay vgs.launcher '{"fontFamily":"x"}'
expect "a picker writing outside the runtime directory is refused" "refused: open-failed=vgs.launcher" ipc shell summon overlay vgs.launcher '{"mode":"select","selectionFile":"/tmp/x","doneFile":"/tmp/y"}'
expect_poll "a refused summon leaves no surface" 0 layer_count vgs:overlay

# Pickers: a select answers its row with `ok`, Escape answers `cancel`, an
# input answers what was typed, and a second summon cancels the first.
picker() { printf '{"mode":"%s","prompt":"Pick",%s"selectionFile":"%s","doneFile":"%s"}' "$1" "${2:+\"options\":$2,}" "$selection" "$done_file"; }
reset_answer
expect "a select summons" ok ipc shell summon overlay vgs.launcher "$(picker select '["alpha","x\tbeta\tsecond"]')"
expect_poll "the select lists its options, the glyph dropped" '[["option", "alpha", ""], ["option", "beta", "second"]]' launcher_rows
focused
type_keys -k Down -k Return || fail "sending keys to the select failed"
expect_poll "the select answered ok" "'ok\\n'" file_text "$done_file"
expect "the selection is the label and its detail" "'beta\\tsecond\\n'" file_text "$selection"
expect_poll "the answered select closed" 0 layer_count vgs:overlay
reset_answer
expect "a select summons again" ok ipc shell summon overlay vgs.launcher "$(picker select '["alpha"]')"
focused
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape answers cancel" "'cancel\\n'" file_text "$done_file"
expect "a cancelled select writes no selection" absent file_text "$selection"
reset_answer
expect "an input summons" ok ipc shell summon overlay vgs.launcher "$(picker input)"
expect_poll "the input is open" '"input"' read_launcher mode
focused
type_keys "hello" -k Return || fail "typing into the input failed"
expect_poll "the input answered ok" "'ok\\n'" file_text "$done_file"
expect "the input's selection is what was typed" "'hello\\n'" file_text "$selection"
reset_answer
expect "a select summons for replacement" ok ipc shell summon overlay vgs.launcher "$(picker select '["alpha"]')"
expect "a menu summon replaces the waiting select" ok ipc shell summon overlay vgs.launcher '{}'
expect_poll "the replaced select was answered cancel" "'cancel\\n'" file_text "$done_file"
reset_answer
expect "a select summons before a hide" ok ipc shell summon overlay vgs.launcher "$(picker select '["alpha"]')"
expect "the host hides the waiting select" ok ipc shell hide overlay vgs.launcher
expect_poll "a hidden select answers cancel" "'cancel\\n'" file_text "$done_file"
expect_poll "the hidden select holds no surface" 0 layer_count vgs:overlay

# File search: f: finds files by name, same-named hits newest first; F:
# folders; a helper that cannot build its index says why in the list.
expect "the launcher summons for files" ok ipc shell summon overlay vgs.launcher '{"query":"f:smoke-report"}'
expect_poll "f: lists both files of one name, newest first" '[["smoke-report.txt", "~/launcher-files"], ["smoke-report.txt", "~/launcher-files/older"]]' rows_of file
expect "the file index lives in the launcher's cache" True bash -c '[[ -s $1 ]] && echo True' _ "$home/.cache/vgshell/launcher/f.idx"
selected_before_flyout="$(read_launcher selectedIndex)"
type_keys -k Menu || fail "opening the file flyout with the Menu key failed"
expect_poll "Menu opens the selected file's flyout" true ipc smoke readShownDescendant overlay vgs.launcher ContextMenu opened
expect_poll "the file flyout has a keyboard selection" 0 ipc smoke readShownDescendant overlay vgs.launcher ContextMenu hovered
type_keys -k Down || fail "sending Down in the file flyout failed"
expect "Down in the file flyout leaves the launcher list selection alone" "$selected_before_flyout" read_launcher selectedIndex
expect_poll "Down in the file flyout moves its own selection" 1 ipc smoke readShownDescendant overlay vgs.launcher ContextMenu hovered
type_keys -k Escape || fail "closing the file flyout with Escape failed"
expect_poll "Escape closes the file flyout and keeps the launcher open" false ipc smoke readShownDescendant overlay vgs.launcher ContextMenu opened
type_keys -M shift -k F10 -m shift || fail "opening the file flyout with Shift+F10 failed"
expect_poll "Shift+F10 opens the selected file's flyout" true ipc smoke readShownDescendant overlay vgs.launcher ContextMenu opened
type_keys -k Escape || fail "closing the Shift+F10 flyout failed"
expect "F: searches folders" ok ipc shell summon overlay vgs.launcher '{"query":"F:launcher-files"}'
expect_poll "F: lists the folder" '[["launcher-files", "~"]]' rows_of folder
focused
type_keys -k Escape -k Escape || fail "sending Escape failed"
expect_poll "the file search closed" 0 layer_count vgs:overlay
rm -rf -- "${home:?}/.cache/vgshell/launcher"
printf 'not a directory\n' >"$home/.cache/vgshell/launcher"
expected_errors+=('launcher: file-search: index=f error=mkdir')
expect "the launcher summons with no usable cache" ok ipc shell summon overlay vgs.launcher '{"query":"f:smoke-report"}'
expect_poll "an index the helper cannot build is a notice" '[["File search unavailable", "The file list could not be read. Try the search again."]]' rows_of notice
focused
type_keys -k Escape -k Escape || fail "sending Escape failed"
expect_poll "the failed file search closed" 0 layer_count vgs:overlay
rm -f -- "${home:?}/.cache/vgshell/launcher"
expect_poll "no file search helper outlives the launcher" 0 file_search_children
# Control: a copy of the row that shows its image slot whatever the image
# loaded draws no glyph tile for the same application.
row_qml="$repo/shell/plugins/vgs.launcher/LauncherRow.qml"
cp -- "$row_qml" "$sandbox/LauncherRow.qml.kept"
python3 - "$row_qml" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
needle = 'readonly property bool imageShown: imageIcon && image.source.toString().length > 0 && image.status !== Image.Error && !(image.status === Image.Ready && image.implicitWidth === 0)'
assert text.count(needle) == 1, "the image rule to plant occurs once"
open(path, "w").write(text.replace(needle, "readonly property bool imageShown: imageIcon"))
PY
rescan "a rescan builds the row copy that always shows its image slot"
expect "the launcher summons the row copy for the application" ok ipc shell summon overlay vgs.launcher '{"query":"smoke launch"}'
expect_poll "the row copy ranks the planted application first" '["app", "Smoke Launch Probe"]' first_row
expect_poll "control: the row copy draws no glyph tile for the application" False glyph_tiles
focused
type_keys -k Escape -k Escape || fail "sending Escape failed"
expect_poll "the row copy's search closed" 0 layer_count vgs:overlay
cp -- "$sandbox/LauncherRow.qml.kept" "$row_qml"
rescan "a rescan restores the row"

# Repeated summons and hides leave one surface at most and none at the end.
for _ in 1 2 3 4 5; do
  launcher toggle '' >/dev/null
  launcher toggle '' >/dev/null
done
expect_poll "ten toggles leave no surface" 0 layer_count vgs:overlay
expect "the compositor's shortcut toggles the launcher" ok hypr dispatch 'hl.dsp.global("vgs.launcher:toggle")'
expect_poll "the shortcut opened the launcher" 1 layer_count vgs:overlay
expect "the shortcut toggles it closed" ok hypr dispatch 'hl.dsp.global("vgs.launcher:toggle")'
expect_poll "the shortcut closed the launcher" 0 layer_count vgs:overlay

# The bar entry: enabling placed it in the left section; a click opens the
# launcher on its screen, and a click outside the card closes it.
widget_placed() { bar_widget_ids | py_reply 'import json,sys; print(all("vgs.launcher" in bar for bar in json.load(sys.stdin)))'; }
expect_poll "the bar entry is placed" True widget_placed
forget_record
click_centre "$(bar_key)" vgs.launcher || fail "the click on the bar entry failed"
expect_poll "the bar entry opened the launcher" 1 layer_count vgs:overlay
# A mapped layer takes input once the compositor has configured it and
# handed it the keyboard; a click before that reaches no launcher surface.
expect_poll "the bar entry's launcher is open" true read_launcher opened
focused "the bar entry's launcher holds the keyboard"
# The press on the bar entry holds the pointer on the bar's surface; a
# motion moves it onto the launcher's before the click.
hover 10 "$((mon_h - 10))" || fail "moving the pointer off the card failed"
click 10 "$((mon_h - 10))" || fail "the click outside the card failed"
expect_poll "a click outside the card closed it" 0 layer_count vgs:overlay
# A right click on the bar entry opens the widget frame's menu: Hide, as on
# every bar widget, then the launcher's Open terminal. The right click
# itself opens neither a terminal nor the launcher; Escape closes the menu.
# Open terminal runs the stand-in xdg-terminal-exec, which records a run
# with no words. The left click above is the control for the record: it
# recorded no run.
expect "a left click on the bar entry opens no terminal" absent recorded
launcher_menu() { ipc smoke readInstance "$(bar_key)" vgs.launcher "$1"; }
launcher_right_click() {
  local box x y
  box="$(ipc smoke instanceGeometry "$(bar_key)" vgs.launcher)" || return 1
  [[ $box == \[* ]] || return 1
  read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2), int(y+h/2))' "$box") || return 1
  hover "$((x - 1))" "$y" && right_click "$x" "$y"
}
launcher_pointer="$pointer_at"
if launcher_right_click; then
  expect_poll "a right click on the bar entry opens its menu" true launcher_menu frameMenuOpen
  expect "the menu holds Hide, then Open terminal, then Settings" '["Hide","Open terminal","Settings"]' launcher_menu frameMenuEntries
  expect "a right click on the bar entry opens no terminal" absent recorded
  expect "a right click on the bar entry opens no launcher" 0 layer_count vgs:overlay
  type_keys -k Escape || fail "Escape to the bar entry's menu failed"
  expect_poll "Escape closes the menu" false launcher_menu frameMenuOpen
else
  fail "the right click on the bar entry failed"
fi
if launcher_right_click; then
  expect_poll "a second right click opens the menu again" true launcher_menu frameMenuOpen
  type_keys -k Down -k Return || fail "Down and Return on the bar entry's menu failed"
  expect_poll "Open terminal opens a terminal" '[]' recorded
  expect_poll "Open terminal closes the menu" false launcher_menu frameMenuOpen
  expect "Open terminal opens no launcher" 0 layer_count vgs:overlay
else
  fail "the second right click on the bar entry failed"
fi
forget_record
read -r launcher_x launcher_y <<<"${launcher_pointer:-10 $((mon_h - 10))}"
hover "$launcher_x" "$launcher_y" || fail "putting the pointer back after the bar entry's menu failed"

# A row shows the hand.
expect "the launcher opens its System menu" ok ipc shell summon overlay vgs.launcher '{"menu":"system"}'
focused
expect_poll "the System menu lists the Reboot row" True launcher_has_row action Reboot
expect_cursor "a launcher row shows the hand" pointer vgs:overlay "$(ipc smoke windowGeometry overlay vgs.launcher LauncherRow Reboot)"
rest_pointer || fail "moving the pointer off the launcher's rows failed"
expect "the host hides the System menu" ok ipc shell hide overlay vgs.launcher
expect_poll "the System menu closed" 0 layer_count vgs:overlay

# The themes provider, which the shipped menu no longer uses, stays for an
# owner's own menu file: a user row naming it lists the packages the theme
# capability reports. Whether an apply succeeded is
# MenuModel.applySucceeded, pinned under node.
write_menu '{ "schemaVersion": 1, "items": { "my-themes": { "label": "My themes", "icon": "palette", "provider": "themes" } } }'
expect "the launcher opens the user's themes menu" ok ipc shell summon overlay vgs.launcher '{"menu":"my-themes"}'
focused
expect_poll "the user's themes menu lists the vgs package" True launcher_has_row theme vgs
expect "the host hides the user's themes menu" ok ipc shell hide overlay vgs.launcher
expect_poll "the user's themes menu closed" 0 layer_count vgs:overlay
rm -f -- "${user_menu:?}"

# The look: the theme reaches it through its mode, accent, motion scale and
# interface font alone. Every other token of the theme moves and the look
# stays; the accent moves the accent; the interface family moves the text's
# family; light mode applies the light glass.
expect "the launcher summons for its look" ok ipc shell summon overlay vgs.launcher '{}'
expect_poll "the look resolved" '"#c7151515"' look_at card.fill
if ! look_before="$(read_launcher look)"; then fail "the launcher's look is unreadable"; fi
write_theme '{ "schemaVersion": 1, "name": "unrelated", "tokens": { "palette": { "foreground": "#ff00ff", "background": "#00ff00", "success": "#123456" }, "font": { "size": 22, "family": { "mono": "Serif" } }, "space": { "unit": 7 }, "radius": { "md": 9 }, "text": { "body": { "size": 30 } }, "color": { "surface": "#ff0000" } } }'
expected_errors+=('theme: font=Serif unavailable')
expect_poll "the unrelated theme is accepted" unrelated ipc smoke themeName
unchanged_look() { [[ "$(read_launcher look)" == "$look_before" ]] && echo same || echo moved; }
expect_poll "every unrelated token leaves the launcher's look as it was" same unchanged_look
expect "the launcher's text draws in the shipped interface font" '"Inter Variable"' look_at font.family.sans
write_theme '{ "schemaVersion": 1, "name": "typeface", "tokens": { "font": { "family": { "sans": "JetBrains Mono" } } } }'
expect_poll "the interface font reaches the launcher's text" '"JetBrains Mono"' look_at font.family.sans
write_theme '{ "schemaVersion": 1, "name": "accent", "tokens": { "palette": { "accent": "#7aa2f7" } } }'
expect_poll "the accent reaches the launcher" '"#ff7aa2f7"' look_at palette.accent
expect "the accent reaches the caret's halo" '"#2e7aa2f7"' look_at caret.halo
expect "the accent leaves the glass" '"#c7151515"' look_at card.fill
write_theme '{ "schemaVersion": 1, "name": "bright", "tokens": { "scheme": { "mode": "light" }, "palette": { "accent": "#a8330a" } } }'
expect_poll "light mode applies the light glass" '"#ccefefef"' look_at card.fill
expect "light mode applies the light text" '"#ff2a2a2a"' look_at text.foreground
expect "light mode lights the edge white, brighter than the fill" '"#ffffffff"' look_at edge.neutral
expect "light mode keeps the theme's accent" '"#ffa8330a"' look_at palette.accent
write_theme '{ "schemaVersion": 1, "name": "still", "tokens": { "motion": { "scale": 0 } } }'
expect_poll "reduced motion stills the launcher's durations" 0 look_at motion.duration.medium4
write_theme '{ "schemaVersion": 1, "name": "vgs", "tokens": {} }'
expect_poll "the defaults return" vgs ipc smoke themeName
expect_poll "the defaults' look is the first look" same unchanged_look

# A rescan that changes the plugin rebuilds it: a waiting picker is answered
# cancel, and the service registers its shortcut once again.
reset_answer
expect "a select summons before a rescan" ok ipc shell summon overlay vgs.launcher "$(picker select '["alpha"]')"
printf '\n' >>"$repo/shell/plugins/vgs.launcher/README.md"
rescan "the rescan is accepted"
expect_poll "the rebuilt launcher answered the old picker cancel" "'cancel\\n'" file_text "$done_file"
expect_poll "the rebuilt service holds one shortcut and one target" '[["vgs.launcher:toggle"], ["vgs.launcher"]]' lent_launcher
# The rebuilt launcher reopened with the same payload, so it waits too.
expect "the host hides the rebuilt picker" ok ipc shell hide overlay vgs.launcher
expect_poll "the rebuilt picker closed" 0 layer_count vgs:overlay

# Disabling the plugin while a picker waits answers it, takes the surface
# down and releases every registration.
reset_answer
expect "a select summons before the disable" ok ipc shell summon overlay vgs.launcher "$(picker select '["alpha"]')"
expect "disabling the launcher is allowed" ok ipc shell setPluginEnabled vgs.launcher false
expect_poll "disabling answered the waiting picker cancel" "'cancel\\n'" file_text "$done_file"
expect_poll "the disabled launcher holds no surface" 0 layer_count vgs:overlay
expect_poll "the disabled launcher holds no registration" '[[], []]' lent_launcher
expect_poll "the disabled launcher has no build record" False record_exists vgs.launcher
expect_poll "no file search helper outlives the plugin" 0 file_search_children
