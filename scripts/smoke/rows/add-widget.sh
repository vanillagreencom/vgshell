# The real empty-bar menu's Manage widgets opens the existing bar plugin's
# chooser window. A newly discovered fixture appears without a hand-kept
# inventory. Each row ends in one control and shows no chip.
# Turning an unplaced widget's Switch on inserts it once at the clicked
# section's edge and preserves the rest of the persisted configuration;
# the Switch then reads on, and turning it off takes the widget off the
# bar and keeps a plugin with other kinds on. A mouse click leaves no
# focus ring. Turning a widget-only plugin's Switch off turns the plugin
# off, which insertWidget then refuses, and turning it on again turns it
# back on and places it in one write. Placing, unplacing, turning off and
# turning on the fixture from the CLI shows in the open window with no
# reopen; turning it on also puts its widget on the bar
# (PluginLogic.withEnabled). A plugin with other kinds that is off ends in
# an Enable plugin link: a click, or Return after the arrows reach it,
# turns it on and puts its widget on the bar in one write with no other
# window, and the row then shows its Switch, on, with the focus moved to
# it, drawing its ring only after the keys. Every row is one height.
# No latency budget: waits poll reported state at the harness interval.
# The control removes the widget filter's result in a disposable tree;
# the same inventory reader must then reject the missing fixture.
# Generic Settings Open keeps the Calendar and an open chooser's click
# context. Each same-title sibling can retake native keyboard focus. Its
# control restores window preference in a disposable tree.
# A place-then-move chooser control must fail the ordinary one-write judge.
# inputs: shell/plugins/vgs.bar/manifest.json shell/plugins/vgs.bar/Bar.qml shell/plugins/vgs.bar/AddWidget.qml shell/Ui/layout/ContentRow.qml shell/Ui/layout/ListItem.qml shell/Ui/controls/Switch.qml shell/Ui/controls/RowAction.qml shell/Ui/foundation/FocusRing.qml shell/Ui/foundation/KeyNav.qml shell/Ui/foundation/KeyNavLogic.js shell/plugins/vgs.bar/Calendar.qml shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/Core/Capabilities.qml shell/Core/Plugins.qml shell/Core/PluginLogic.js shell/Core/Config.qml shell/Core/Registry.qml scripts/smoke/fixtures/plugins/acme.tick/* scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail

aw_saved="$sandbox/add-widget-saved.json"
cp -- "$home/.config/vgshell/shell.json" "$aw_saved"
aw_fixture="$home/.config/vgshell/plugins/acme.add-widget"
aw_lone="$home/.config/vgshell/plugins/acme.add-only"
mkdir -- "$aw_fixture" "$aw_lone"
aw_cleanup() {
  rm -rf -- "$aw_fixture" "$aw_lone"
  cp -- "$aw_saved" "$home/.config/vgshell/shell.json"
  expect "the original user configuration reloads" ok ipc shell reloadConfig
  rescan "the private chooser fixture leaves the registry"
}
smoke_row_abandon=(aw_cleanup)
cp -R -- "$repo/scripts/smoke/fixtures/plugins/acme.tick/." "$aw_fixture/"
python3 - "$aw_fixture/manifest.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
m = json.loads(p.read_text())
m.update(id="acme.add-widget", name="A widget to add", kinds=["bar-widget", "service"])
m["entryPoints"]["service"] = "Widget.qml"
p.write_text(json.dumps(m))
PY
cp -R -- "$repo/scripts/smoke/fixtures/plugins/acme.tick/." "$aw_lone/"
python3 - "$aw_lone/manifest.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
m = json.loads(p.read_text())
assert m["kinds"] == ["bar-widget"]
m.update(id="acme.add-only", name="A lone widget")
p.write_text(json.dumps(m))
PY
rescan "the newly installed widget enters the existing registry"
expect "the new fixture is enabled" ok ipc shell setPluginEnabled acme.add-widget true
expect "the multi-kind fixture starts unplaced but enabled" ok ipc shell setPluginPlaced acme.add-widget false
# FIELD of plugin ID as the shell lists it.
aw_listed() { ipc shell listPlugins | py_reply 'import json,sys; rows=[p for p in json.load(sys.stdin)["plugins"] if p["id"]==sys.argv[1]]; print(rows[0][sys.argv[2]] if len(rows)==1 else "absent")' "$1" "$2"; }
# Whether plugin ID, acme.add-widget when none is named, is placed or on.
aw_placed() { aw_listed "${1:-acme.add-widget}" placed; }
aw_enabled() { aw_listed "${1:-acme.add-widget}" enabled; }
expect_poll "the fixture is unplaced" False aw_placed

aw_read() { ipc smoke readInstance window vgs.bar "$1"; }
aw_inventory() {
  if [[ ${1:-} == control ]]; then ipc smoke popupRead chooser-inventory widgets; else aw_read widgets; fi | py_reply 'import json,sys
rows=json.load(sys.stdin); ids={p["id"] for p in rows}
print("acme.add-widget" in ids and "vgs.bar" not in ids and all("bar-widget" in p["kinds"] for p in rows))'
}
aw_point() {
  local key bar section
  key="$(bar_key)" || return 1
  bar="$(ipc smoke instanceGeometry "$key" vgs.bar)" || return 1
  section="$(ipc smoke barSectionGeometry "$key" "$1")" || return 1
  py_reply 'import json,sys
b=json.loads(sys.argv[1]); s=json.load(sys.stdin); zone=sys.argv[2]
x=s[0]+s[2]+12 if zone=="left" else s[0]-12
lo,hi={"left":(0,1),"center":(1,2),"right":(2,3)}[zone]
print("%d %d" % (x,b[1]+b[3]/2) if b[0]+b[2]*lo/3<x<b[0]+b[2]*hi/3 else "crowded")' "$bar" "$1" <<<"$section"
}
aw_open() {
  local x y key
  key="$(bar_key)" || return 1
  read -r x y < <(aw_point "$1")
  [[ $x =~ ^-?[0-9]+$ && $y =~ ^-?[0-9]+$ ]] || { fail "Manage widgets: no empty $1 bar point"; return 1; }
  hover "$x" "$y" && right_click "$x" "$y" || return 1
  expect_poll "the empty $1 bar opens its menu" true ipc smoke readInstance "$key" vgs.bar spacerMenuOpen
  expect "the real menu includes Manage widgets before the spacer actions" '["Manage widgets","Add separator","Add gap"]' ipc smoke readInstance "$key" vgs.bar spacerMenuEntries
  type_keys -k Down -k Return
  expect_poll "the chooser is a real Bar application window" 1 window_count Bar
  expect_poll "the chooser reads the new widget and excludes non-widgets" True aw_inventory
  expect "the chooser keeps the clicked bar screen and coordinate" True aw_payload "$key" "$x"
}
aw_payload() {
  aw_read payload | py_reply 'import json,sys; p=json.load(sys.stdin); print(p=={"screen":sys.argv[1].split(":",1)[1],"x":int(sys.argv[2])})' "$1" "$2"
}
# FIELD of plugin ID's chooser row (Probe chooserRows).
aw_row() {
  ipc smoke chooserRows | py_reply 'import json,sys
rows=[r for r in json.load(sys.stdin) if r["id"]==sys.argv[1]]
print(json.dumps(rows[0].get(sys.argv[2])) if len(rows)==1 else "absent")' "$1" "$2"
}
aw_click() {
  local box x y
  box="$(aw_row "$1" "$2")" || return 1
  [[ $box == \[* ]] || { fail "Manage widgets: $1 has no $2 box"; return 1; }
  read -r x y < <(at_centre window:Bar "$box") || return 1
  click "$x" "$y"
}
# The one control of plugin ID's row, acme.add-widget when none is named:
# its type, the link's text and the Switch's checked state.
aw_control() {
  ipc smoke chooserRows | py_reply 'import json,sys
rows=[r for r in json.load(sys.stdin) if r["id"]==sys.argv[1]]
print(json.dumps([rows[0]["type"], rows[0]["text"], rows[0]["checked"]]) if len(rows)==1 else "absent")' "${1:-acme.add-widget}"
}
# Plugin ID's place in the chooser's list, which the arrows count.
aw_index() { aw_read widgets | py_reply 'import json,sys; ids=[p["id"] for p in json.load(sys.stdin)]; print(ids.index(sys.argv[1]) if sys.argv[1] in ids else "absent")' "$1"; }
# Moves the keyboard to plugin ID's row: Home selects the first row and
# each Down the next.
aw_key_to() {
  local index i keys=(-k Home)
  index="$(aw_index "$1")" || return 1
  [[ $index =~ ^[0-9]+$ ]] || { fail "Manage widgets: $1 is not listed"; return 1; }
  for ((i = 0; i < index; i++)); do keys+=(-k Down); done
  type_keys "${keys[@]}"
}
# Whether the chooser's focused control shows keyboard focus and its ring.
aw_ring() { ipc smoke focused window vgs.bar | py_reply 'import json,sys; r=json.load(sys.stdin); print(json.dumps([r[2], r[3]]))'; }
# Whether every row of the chooser is one height.
aw_even() { ipc smoke chooserRows | py_reply 'import json,sys; h={r["row"][3] for r in json.load(sys.stdin)}; print(len(h)==1)'; }
aw_persisted() {
  python3 -c 'import json,sys
before=json.load(open(sys.argv[1])); after=json.load(open(sys.argv[2])); section=sys.argv[3]
layout=before["bar"]["layout"]; entries=layout[section]
entries.insert(len(entries) if section=="left" else 0,{"id":"acme.add-widget"})
print(before==after)' "$sandbox/add-widget-before-add.json" "$home/.config/vgshell/shell.json" "$1"
}
aw_one_write() {
  ipc smoke chooserCount false | py_reply 'import sys; n=sys.stdin.read().strip(); print("single" if n=="1" else "commits="+n)'
}
# The shipped Settings entry calls manager.open, not an explicit summon.
aw_generic_open() {
  aw_generic_payload="$(aw_read payload)" || return 1
  settings_page_open vgs.bar
  expect "the Bar page's generic Open answers ok" ok ipc smoke invokeInstance window vgs.settings openSurface vgs.bar
}
aw_generic_state() {
  local calendar payload
  calendar="$(ipc smoke windowDrawn panel vgs.bar)" || return 1
  payload="$(aw_read payload)" || return 1
  py_reply 'import json,sys; print(sys.argv[1]=="drawn" and json.load(sys.stdin)==json.loads(sys.argv[2]))' "$calendar" "$aw_generic_payload" <<<"$payload"
}
aw_open left
aw_generic_open
expect_poll "generic Bar Open draws Calendar and preserves the chooser's original click context" True aw_generic_state
expect_poll "generic Bar Open gives Calendar native keyboard focus" true ipc smoke windowFocused panel vgs.bar
expect "the existing chooser opens beside Calendar" ok ipc shell summon window vgs.bar "$aw_generic_payload"
expect_poll "the same-title chooser retakes native keyboard focus" true ipc smoke windowFocused window vgs.bar
expect "generic Open returns to the existing Calendar" ok ipc smoke invokeInstance window vgs.settings openSurface vgs.bar
expect_poll "the same-title Calendar retakes native keyboard focus" true ipc smoke windowFocused panel vgs.bar
expect "both native windows preserve the chooser's original click context" True aw_generic_state
expect "Calendar closes after generic Open" ok ipc shell hide panel vgs.bar
settings_page_close vgs.bar
expect "the chooser closes after generic Open" ok ipc shell hide window vgs.bar
expect_poll "the generic Open chooser is gone" 0 window_count Bar

for aw_section in left center right; do
  aw_open "$aw_section"
  expect "an unplaced enabled widget offers add" '"add"' aw_row acme.add-widget action
  expect "an unplaced enabled widget shows its Switch off" '["Switch", "", false]' aw_control
  expect "the unplaced widget shows no chip" '[]' aw_row acme.add-widget chips
  cp -- "$home/.config/vgshell/shell.json" "$sandbox/add-widget-before-add.json"
  expect "the add commit observer starts empty" 0 ipc smoke chooserCount true
  aw_click acme.add-widget control
  expect_poll "turning the Switch on inserts at the clicked $aw_section edge and preserves the saved file" True aw_persisted "$aw_section"
  expect "turning the Switch on commits exactly one configuration update" single aw_one_write
  expect_poll "a placed widget offers remove" '"remove"' aw_row acme.add-widget action
  expect "a placed widget shows its Switch on" '["Switch", "", true]' aw_control
  expect "the placed widget shows no chip" '[]' aw_row acme.add-widget chips
  expect "a click on the Switch leaves no focus ring" '[false, false]' aw_ring
  expect "the duplicate observer starts empty" 0 ipc smoke chooserCount true
  expect "the delivered manager refuses duplicate insertion" "refused: placed=acme.add-widget reason=placed" ipc smoke chooserInsert acme.add-widget "$(first_name)" 20
  expect "the refused duplicate commits nothing" 0 ipc smoke chooserCount false
  aw_click acme.add-widget control
  expect_poll "turning the Switch off takes the widget off the bar for the next section" False aw_placed
  expect "turning the Switch off keeps a plugin with other kinds on" True aw_enabled
  expect_poll "the unplaced widget offers add again" '"add"' aw_row acme.add-widget action
  expect "the unplaced widget shows its Switch off again" '["Switch", "", false]' aw_control
  expect "a second click on the Switch leaves no focus ring" '[false, false]' aw_ring
  expect "the chooser closes" ok ipc shell hide window vgs.bar
  expect_poll "the chooser window is gone" 0 window_count Bar
done

# A widget-only plugin: turning its Switch off turns the plugin off, which
# the delivered manager's insertWidget then refuses, and turning it on
# again turns it back on and places it, in one write.
expect "the widget-only fixture is enabled" ok ipc shell setPluginEnabled acme.add-only true
expect_poll "the enabled widget-only fixture is placed" True aw_placed acme.add-only
aw_open left
expect "every chooser row is one height" True aw_even
expect "the placed widget-only fixture offers remove" '"remove"' aw_row acme.add-only action
expect "the placed widget-only fixture shows its Switch on" '["Switch", "", true]' aw_control acme.add-only
aw_click acme.add-only control
expect_poll "turning the Switch off takes the widget-only fixture off the bar" False aw_placed acme.add-only
expect_poll "an unplaced widget-only plugin reads off" False aw_enabled acme.add-only
expect "the delivered manager still refuses a widget-only plugin that is off" "refused: placed=acme.add-only reason=disabled" ipc smoke chooserInsert acme.add-only "$(first_name)" 20
expect_poll "the widget-only fixture that is off offers add" '"add"' aw_row acme.add-only action
expect "the widget-only fixture that is off shows its Switch off, not a link" '["Switch", "", false]' aw_control acme.add-only
expect "the turn-on observer starts empty" 0 ipc smoke chooserCount true
aw_click acme.add-only control
expect_poll "turning the Switch on turns the widget-only fixture back on" True aw_enabled acme.add-only
expect_poll "turning the Switch on places the widget-only fixture" True aw_placed acme.add-only
expect "turning the Switch on turns it on in one configuration update" single aw_one_write
expect_poll "the placed widget-only fixture shows its Switch on again" '["Switch", "", true]' aw_control acme.add-only
expect "the chooser closes after the widget-only rows" ok ipc shell hide window vgs.bar
expect_poll "the widget-only chooser is gone" 0 window_count Bar

# The real manager places in the fixture's default center, then moves to
# left. Both persisted changes reach the same observer the Add check uses.
aw_open left
mkdir -p -- "$sandbox/tree-add-widget-writes/shell/plugins/vgs.bar"
cp -- "$repo/shell/plugins/vgs.bar/AddWidget.qml" "$sandbox/tree-add-widget-writes/shell/plugins/vgs.bar/AddWidget.qml"
if edit_tree add-widget-writes shell/plugins/vgs.bar/AddWidget.qml \
    'const reply = shell.manager.insertWidget(id, payload.screen, payload.x);' \
    $'const reply = shell.manager.setPlaced(id, true);\n        if (Reply.isOk(reply)) return shell.manager.moveWidget(id, "left", 0);'; then
  expect "control: the multi-write chooser uses the delivered manager" ok ipc smoke chooserControl "$sandbox/tree-add-widget-writes/shell/plugins/vgs.bar/AddWidget.qml"
  expect "control: the multi-write observer starts empty" 0 ipc smoke chooserCount true
  expect "control: Add runs the real placement and move" ok ipc smoke popupCallWith chooser-inventory addWidget acme.add-widget
  expect "control: the ordinary one-write judge rejects the two real commits" commits=2 aw_one_write
  expect "control: the multi-write chooser is released" ok ipc smoke popupDrop chooser-inventory
  expect "control: the fixture returns to unplaced" ok ipc shell setPluginPlaced acme.add-widget false
  expect_poll "control: the fixture is unplaced again" False aw_placed
fi
expect "the chooser closes after the multi-write control" ok ipc shell hide window vgs.bar
expect_poll "the multi-write chooser is gone" 0 window_count Bar

# A change from outside reaches the open window through the same
# shell.manager.plugins binding, with no reopen: the CLI's setPluginEnabled
# reaches Plugins.setEnabled as the Settings switch does.
aw_open left
expect "the open window reads the unplaced fixture's Switch off" '["Switch", "", false]' aw_control
expect "the CLI places the fixture" ok ipc shell setPluginPlaced acme.add-widget true
expect_poll "the open window shows the outside placement as its Switch on" '["Switch", "", true]' aw_control
expect "the CLI takes the fixture off the bar" ok ipc shell setPluginPlaced acme.add-widget false
expect_poll "the open window shows the outside removal as its Switch off" '["Switch", "", false]' aw_control
expect "the CLI turns the fixture off" ok ipc shell setPluginEnabled acme.add-widget false
expect_poll "the open window shows the plugin turned off outside as its Enable plugin link" '["RowAction", "Enable plugin", null]' aw_control
expect "the CLI turns the fixture on" ok ipc shell setPluginEnabled acme.add-widget true
expect_poll "the open window shows the plugin turned on outside, which places it, as its Switch on" '["Switch", "", true]' aw_control
expect "turning the fixture on from outside put it on the bar" True aw_placed
expect "the outside changes reopened no window" 1 window_count Bar

expect "the fixture is taken off the bar before it is turned off" ok ipc shell setPluginPlaced acme.add-widget false
expect_poll "the fixture is off the bar before the link" False aw_placed
expect "the fixture is disabled without removing its inventory row" ok ipc shell setPluginEnabled acme.add-widget false
expect_poll "a disabled plugin with other kinds offers its link" '"enable"' aw_row acme.add-widget action
expect "the disabled row ends in its Enable plugin link" '["RowAction", "Enable plugin", null]' aw_control
expect "the disabled row shows no chip" '[]' aw_row acme.add-widget chips
expect "the disabled observer starts empty" 0 ipc smoke chooserCount true
expect "the delivered manager refuses a disabled widget" "refused: placed=acme.add-widget reason=disabled" ipc smoke chooserInsert acme.add-widget "$(first_name)" 20
expect "the delivered manager refuses a non-widget" "refused: placed=vgs.bar reason=no-bar-widget" ipc smoke chooserInsert vgs.bar "$(first_name)" 20
expect "refused rows commit nothing" 0 ipc smoke chooserCount false
expect "the link observer starts empty" 0 ipc smoke chooserCount true
aw_click acme.add-widget control
expect_poll "a click on Enable plugin turns the plugin on" True aw_enabled
expect "Enable plugin turns it on in one configuration update" single aw_one_write
expect_poll "the clicked row then shows its Switch on" '["Switch", "", true]' aw_control
expect "Enable plugin puts the widget on the bar" True aw_placed
expect "the clicked row offers remove" '"remove"' aw_row acme.add-widget action
expect "Enable plugin opens no Plugins window" 0 window_count Plugins
expect "the chooser stays the one Bar window" 1 window_count Bar
expect "the click moves the focus to the row's Switch" true aw_row acme.add-widget focused
expect "the focus a click moved draws no ring" '[false, false]' aw_ring

expect "the fixture is taken off the bar again for the keyboard path" ok ipc shell setPluginPlaced acme.add-widget false
expect_poll "the fixture is off the bar before the keys" False aw_placed
expect "the fixture is turned off again for the keyboard path" ok ipc shell setPluginEnabled acme.add-widget false
expect_poll "the row shows its link again" '["RowAction", "Enable plugin", null]' aw_control
expect_poll "the chooser holds the keyboard before the keys" true ipc smoke windowFocused window vgs.bar
aw_key_to acme.add-widget
expect_poll "the arrows reach the Enable plugin link" true aw_row acme.add-widget focused
expect "the link the arrows reached shows its ring" '[true, true]' aw_ring
expect "the key observer starts empty" 0 ipc smoke chooserCount true
type_keys -k Return
expect_poll "Return on Enable plugin turns the plugin on" True aw_enabled
expect "Return turns it on in one configuration update" single aw_one_write
expect_poll "the row then shows its Switch on after Return" '["Switch", "", true]' aw_control
expect "Return puts the widget on the bar" True aw_placed
expect "Return opens no Plugins window" 0 window_count Plugins
expect "Return moves the focus to the row's Switch" true aw_row acme.add-widget focused
expect "the focus a key moved shows its ring" '[true, true]' aw_ring
mkdir -p -- "$sandbox/tree-add-widget-inventory/shell/plugins/vgs.bar"
cp -- "$repo/shell/plugins/vgs.bar/AddWidget.qml" "$sandbox/tree-add-widget-inventory/shell/plugins/vgs.bar/AddWidget.qml"
if edit_tree add-widget-inventory shell/plugins/vgs.bar/AddWidget.qml \
    'plugin.kinds.indexOf("bar-widget") !== -1' 'false && plugin.kinds.indexOf("bar-widget") !== -1'; then
  expect "control: the disposable chooser reads the same delivered manager" ok ipc smoke chooserControl "$sandbox/tree-add-widget-inventory/shell/plugins/vgs.bar/AddWidget.qml"
  expect_poll "control: the same inventory reading rejects the omitted widget" False aw_inventory control
  expect "control: the empty chooser has no widget rows" '[]' ipc smoke popupRead chooser-inventory widgets
  expect "control: the disposable chooser is released" ok ipc smoke popupDrop chooser-inventory
fi
expect "the chooser closes after the control" ok ipc shell hide window vgs.bar

# Load the real routing owner with only the former preference restored.
# The same Settings entry and state reader must reject that preference.
if copy_tree add-widget-open \
  && edit_tree add-widget-open shell/Core/PluginLogic.js \
    'manifest.kinds.indexOf("bar") !== -1 && manifest.kinds.indexOf("panel") !== -1' \
    'false && manifest.kinds.indexOf("bar") !== -1 && manifest.kinds.indexOf("panel") !== -1'; then
  stop_shell
  start_shell "$sandbox/tree-add-widget-open" "$sandbox/add-widget-open-control.log" || { fail "the generic Open control shell starts"; return 1; }
  aw_open left
  aw_generic_open
  expect_poll "control: generic Open replaces the chooser context" '{}' aw_read payload
  expect "control: the ordinary generic Open judge rejects window preference" False aw_generic_state
  settings_page_close vgs.bar
  expect "control: the chooser closes after the generic Open control" ok ipc shell hide window vgs.bar
  stop_shell
  start_shell "$repo" "$sandbox/add-widget-open-restored.log" || { fail "the shell returns after the generic Open control"; return 1; }
fi

aw_cleanup
smoke_row_abandon=()
