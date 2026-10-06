# Every plugin with a bar widget shows in the bar once it is installed,
# with no step in Settings, and every widget's right-click menu hides it.
# A copy of the acme.pane fixture, a service plus a bar widget, installed
# as acme.hideable, is placed in its default section and enabled by the
# rescan that finds it (PluginLogic.firstPresence). A real right click on
# its widget opens the shared frame's menu (shell/Ui/BarWidget.qml); its
# one entry, Hide, opens the dialog, whose Cancel holds the focus: Return
# and Escape each close it and leave the user file and the bar as they
# were. Return on Hide after a Tab takes the widget off every bar and out
# of the user file's layout, keeps the plugin enabled, leaves a plugins[]
# row and no disabledPlugins change. A restart keeps it hidden while
# acme.hideable-new, installed while the shell was stopped, is placed by
# the same pass, and the Settings page's Show in bar switch brings the
# hidden widget back. That restart is an update too: with a user file from
# before vgs.voice and vgs.webapps shipped, both are on after it and Voice's
# widget is placed, while vgs.tray, which the user file turned off, stays
# off. The control starts a tree whose firstPresence names nothing, whose
# frame opens no menu on a right click, whose enablement rule asks every
# first-party plugin for a plugins row and whose disabled check lets
# vgs.tray past: an
# installed widget then stays off the bar, the right click opens nothing,
# the two shipped plugins stay off and vgs.tray comes on. The row
# restores the user file, removes its copies and puts the pointer back
# where it found it.
# inputs: shell/Ui/BarWidget.qml shell/Ui/feedback/Dialog.qml shell/Ui/overlay/Menu.qml shell/Ui/overlay/MenuItem.qml shell/Ui/overlay/DismissScope.qml shell/Core/PluginLogic.js shell/Core/Plugins.qml shell/Core/Config.qml scripts/smoke/fixtures/plugins/acme.pane/* shell/plugins/vgs.settings/* shell/plugins/vgs.voice/manifest.json shell/plugins/vgs.webapps/manifest.json shell/plugins/vgs.tray/manifest.json
set -euo pipefail
hide_file="$home/.config/vgshell/shell.json"
hide_saved="$sandbox/shell-before-widget-hide.json"
hide_pointer="$pointer_at"
cp -- "$hide_file" "$hide_saved"
# [enabled, placed] of plugin ID in listPlugins.
hide_listed() { ipc shell listPlugins | py_reply 'import json,sys; r=[p for p in json.load(sys.stdin)["plugins"] if p["id"] == sys.argv[1]]; print(json.dumps([r[0]["enabled"], r[0]["placed"]]) if r else "absent")' "$1"; }
# Whether each bar draws ID's widget, as the set of answers over every bar.
hide_in_bars() { bar_widget_ids | py_reply 'import json,sys; print(json.dumps(sorted(set(sys.argv[1] in ids for ids in json.load(sys.stdin)))))' "$1"; }
# The sections of the user file's layout that hold an entry of ID.
hide_sections() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); l=d.get("bar", {}).get("layout", {}); print(json.dumps([s for s in ("left", "center", "right") for e in l.get(s, []) if e["id"] == sys.argv[2]]))' "$hide_file" "$1"; }
# Whether the user file's plugins[] holds a row for ID.
hide_row() { python3 -c 'import json,sys; print(any(e["id"] == sys.argv[2] for e in json.load(open(sys.argv[1])).get("plugins", [])))' "$hide_file" "$1"; }
hide_disabled() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])).get("disabledPlugins")))' "$hide_file"; }
hide_read() { ipc smoke readInstance "$(bar_key)" "$1" "$2"; }
# Rewrite the user file as one from before vgs.voice and vgs.webapps
# shipped, neither id in disabledPlugins, plugins[] or a layout section,
# whose user turned vgs.tray off: its id in disabledPlugins.
hide_before_update() {
  python3 - "$hide_file" <<'PY'
import json, os, sys
path = sys.argv[1]
d = json.load(open(path))
new = ("vgs.voice", "vgs.webapps")
d["disabledPlugins"] = [i for i in d.get("disabledPlugins", []) if i not in new and i != "vgs.tray"] + ["vgs.tray"]
d["plugins"] = [r for r in d.get("plugins", []) if r["id"] not in new]
layout = d.get("bar", {}).get("layout", {})
for section in layout:
    layout[section] = [e for e in layout[section] if e["id"] not in new]
with open(path + ".tmp", "w") as out:
    json.dump(d, out)
os.replace(path + ".tmp", path)
PY
}
# hide_right_click ID: a real right click on the centre of ID's widget on
# the first bar, the pointer moved a pixel off first so the press follows a
# motion.
hide_right_click() {
  local box x y
  box="$(ipc smoke instanceGeometry "$(bar_key)" "$1")" || return 1
  [[ $box == \[* ]] || return 1
  read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2), int(y+h/2))' "$box") || return 1
  hover "$((x - 1))" "$y" && right_click "$x" "$y"
}
# hide_ask ID: the right click, then Return on the menu's one entry, Hide,
# which opens the dialog.
hide_ask() {
  hide_right_click "$1" || fail "the right click on $1's widget failed"
  expect_poll "a right click on $1's widget opens its menu" true hide_read "$1" frameMenuOpen
  type_keys -k Return || fail "Return on $1's Hide entry failed"
  expect_poll "Hide closes the menu" false hide_read "$1" frameMenuOpen
  expect_poll "Hide opens the dialog" true hide_read "$1" frameDialogOpen
}
hide_unchanged() { if cmp -s -- "$hide_file" "$1"; then echo unchanged; else echo changed; fi; }

install_plugin_copy acme.pane acme.hideable "Hideable" 10
rescan "rescan after installing the hideable fixture answers ok"
expect_poll "the installed widget is enabled and placed with no further step" '[true, true]' hide_listed acme.hideable
expect_poll "the installed widget is in every bar" '[true]' hide_in_bars acme.hideable
expect "the installed widget sits in its default section of the user file" '["right"]' hide_sections acme.hideable
hide_disabled_before="$(hide_disabled)" || fail "the user file's disabledPlugins is unreadable"
cp -- "$hide_file" "$sandbox/shell-widget-hide-placed.json"

# Cancel holds the focus: Return presses it. Escape rejects too.
hide_ask acme.hideable
type_keys -k Return || fail "Return on the Hide dialog failed"
expect_poll "Return on the dialog's focused Cancel closes it" false hide_read acme.hideable frameDialogOpen
expect "Cancel leaves the user file as it was" unchanged hide_unchanged "$sandbox/shell-widget-hide-placed.json"
expect "Cancel leaves the widget in every bar" '[true]' hide_in_bars acme.hideable
hide_ask acme.hideable
type_keys -k Escape || fail "Escape on the Hide dialog failed"
expect_poll "Escape closes the dialog" false hide_read acme.hideable frameDialogOpen
expect "Escape leaves the user file as it was" unchanged hide_unchanged "$sandbox/shell-widget-hide-placed.json"

# Tab moves from Cancel to Hide, and Return on Hide hides the widget.
hide_ask acme.hideable
type_keys -k Tab -k Return || fail "Tab and Return on the Hide dialog failed"
expect_poll "Hide takes the widget off every bar" '[false]' hide_in_bars acme.hideable
expect_poll "Hide takes the widget out of the user file's layout" '[]' hide_sections acme.hideable
expect "Hide keeps the plugin enabled" '[true, false]' hide_listed acme.hideable
expect "Hide leaves a plugins row as the record of the choice" True hide_row acme.hideable
expect "Hide leaves disabledPlugins as it was" "$hide_disabled_before" hide_disabled

# A restart keeps the hidden widget hidden; the same pass places a widget
# installed while the shell was stopped, which proves the pass ran.
# The restart is also an update: the user file is made one from before
# vgs.voice and vgs.webapps shipped, so it names neither. Each is on after
# the restart, Voice with its widget in its default section, while
# vgs.tray, which that file turned off, stays off and in no bar.
stop_shell
install_plugin_copy acme.pane acme.hideable-new "Hideable New" 10
hide_before_update || fail "the user file from before the shipped plugins could not be written"
start_shell "$repo" "$sandbox/widget-hide-restart.log" || fail "the shell starts again for the hidden widget"
expect_poll "after a restart a widget installed meanwhile is placed" '[true, true]' hide_listed acme.hideable-new
expect "after a restart the hidden widget stays hidden" '[true, false]' hide_listed acme.hideable
expect "after a restart the hidden widget is in no bar" '[false]' hide_in_bars acme.hideable
expect_poll "after an update a shipped plugin the user never had is on with its widget placed" '[true, true]' hide_listed vgs.voice
expect "after an update the shipped widget sits in its default section" '["right"]' hide_sections vgs.voice
expect_poll "after an update the shipped widget is in every bar" '[true]' hide_in_bars vgs.voice
expect "after an update a shipped plugin with no widget is on" '[true, false]' hide_listed vgs.webapps
expect "after an update a shipped plugin the user turned off stays off" False plugin_enabled vgs.tray
expect "after an update a shipped widget the user turned off is in no bar" '[false]' hide_in_bars vgs.tray

# The Settings page's Show in bar switch brings it back.
settings_page_open acme.hideable
settings_press --type Switch "" Field "Show in bar" || fail "the click on the Show in bar switch failed"
expect_poll "Show in bar puts the hidden widget back in every bar" '[true]' hide_in_bars acme.hideable
expect_poll "Show in bar puts the hidden widget back in its default section" '["right"]' hide_sections acme.hideable
settings_page_close acme.hideable

# The control: no first presence and no menu. An installed widget stays
# off the bar, and a right click on a placed widget opens nothing. The same
# copy gives every first-party plugin the row rule, so the user file from
# before vgs.voice and vgs.webapps shipped leaves both off, and lets
# vgs.tray past isEnabled's disabled
# check, so the plugin the user turned off comes on.
if copy_tree widget-hide-control \
  && edit_tree widget-hide-control shell/Core/PluginLogic.js 'return !isPlaced(effective, m) && pluginRow(effective, id) === undefined;' 'return false;' \
  && edit_tree widget-hide-control shell/Ui/BarWidget.qml 'frameUi.item.openMenu();' '' \
  && edit_tree widget-hide-control shell/Core/PluginLogic.js 'return manifest.id.indexOf(FIRST_PARTY_PREFIX) === 0 ? "first-party" : "row";' 'return "row";' \
  && edit_tree widget-hide-control shell/Core/PluginLogic.js $'if (disabled.indexOf(manifest.id) !== -1)\n        return false;' $'if (disabled.indexOf(manifest.id) !== -1 && manifest.id !== "vgs.tray")\n        return false;'; then
  stop_shell
  hide_before_update || fail "control: the user file from before the shipped plugins could not be written"
  start_shell "$sandbox/tree-widget-hide-control" "$sandbox/widget-hide-control.log" || fail "the widget-hide control shell starts"
  install_plugin_copy acme.pane acme.hideable-control "Hideable Control" 10
  rescan "control: rescan after installing a widget answers ok"
  expect_poll "control: the installed widget is discovered" True plugin_known acme.hideable-control
  expect "control: with no first presence the installed widget stays off the bar" '[false, false]' hide_listed acme.hideable-control
  expect "control: a shipped plugin under the row rule stays off after an update" '[false, false]' hide_listed vgs.voice
  expect "control: a shipped plugin with no widget under the row rule stays off after an update" '[false, false]' hide_listed vgs.webapps
  expect "control: a disabled check that lets vgs.tray past turns it on" True plugin_enabled vgs.tray
  expect_poll "control: the placed widget is built" '[true]' hide_in_bars acme.hideable
  hide_right_click acme.hideable || fail "control: the right click on the widget failed"
  sleep 0.5
  expect "control: a frame with no menu opens nothing on a right click" false hide_read acme.hideable frameMenuOpen
  stop_shell
  start_shell "$repo" "$sandbox/widget-hide-restored.log" || fail "the shell starts again after the widget-hide control"
fi

cp -- "$hide_saved" "$hide_file.tmp" && mv -T -- "$hide_file.tmp" "$hide_file"
rm -rf -- "${home:?}/.config/vgshell/plugins/acme.hideable" "${home:?}/.config/vgshell/plugins/acme.hideable-new" "${home:?}/.config/vgshell/plugins/acme.hideable-control"
rescan "rescan after removing the hideable fixtures answers ok"
expect_poll "the hideable fixture is gone after restore" absent hide_listed acme.hideable
expect "the restore leaves the user file as the row found it" unchanged hide_unchanged "$hide_saved"
if [[ -n $hide_pointer ]]; then
  read -r hide_x hide_y <<<"$hide_pointer"
  hover "$hide_x" "$hide_y" || fail "putting the pointer back failed"
else
  rest_pointer || fail "resting the pointer failed"
fi
