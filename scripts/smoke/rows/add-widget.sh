# The real empty-bar menu opens the existing bar plugin's chooser window.
# A newly discovered fixture appears without a hand-kept inventory. Add
# inserts once at the clicked section's edge, preserves the rest of the
# persisted configuration and turns into Remove, which takes the widget
# off the bar and keeps a plugin with other kinds on. A mouse click leaves
# no focus ring. Remove turns a widget-only plugin off, which insertWidget
# then refuses, and the chooser's Add turns it back on and places it in
# one write. A plugin with other kinds that is off offers Settings, which
# opens the existing separate Plugins window on its page. Every row is one
# height.
# No latency budget: waits poll reported state at the harness interval.
# The control removes the widget filter's result in a disposable tree;
# the same inventory reader must then reject the missing fixture.
# Generic Settings Open keeps the Calendar and an open chooser's click
# context. Each same-title sibling can retake native keyboard focus. Its
# control restores window preference in a disposable tree.
# A place-then-move chooser control must fail the ordinary one-write judge.
# inputs: shell/plugins/vgs.bar/manifest.json shell/plugins/vgs.bar/Bar.qml shell/plugins/vgs.bar/AddWidget.qml shell/Ui/layout/ContentRow.qml shell/Ui/layout/ListItem.qml shell/Ui/controls/Button.qml shell/Ui/foundation/FocusRing.qml shell/Ui/foundation/KeyNav.qml shell/plugins/vgs.bar/Calendar.qml shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/Core/Capabilities.qml shell/Core/Plugins.qml shell/Core/PluginLogic.js shell/Core/Config.qml shell/Core/Registry.qml scripts/smoke/fixtures/plugins/acme.tick/* scripts/smoke/rows/hyprland-consent.sh
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
  [[ $x =~ ^-?[0-9]+$ && $y =~ ^-?[0-9]+$ ]] || { fail "Add widget: no empty $1 bar point"; return 1; }
  hover "$x" "$y" && right_click "$x" "$y" || return 1
  expect_poll "the empty $1 bar opens its menu" true ipc smoke readInstance "$key" vgs.bar spacerMenuOpen
  expect "the real menu includes Add widget before the spacer actions" '["Add widget","Add separator","Add gap"]' ipc smoke readInstance "$key" vgs.bar spacerMenuEntries
  type_keys -k Down -k Return
  expect_poll "the chooser is a real Bar application window" 1 window_count Bar
  expect_poll "the chooser reads the new widget and excludes non-widgets" True aw_inventory
  expect "the chooser keeps the clicked bar screen and coordinate" True aw_payload "$key" "$x"
}
aw_payload() {
  aw_read payload | py_reply 'import json,sys; p=json.load(sys.stdin); print(p=={"screen":sys.argv[1].split(":",1)[1],"x":int(sys.argv[2])})' "$1" "$2"
}
# The current fixture's row action, chips and boxes.
aw_row() {
  ipc smoke chooserRows | py_reply 'import json,sys
rows=[r for r in json.load(sys.stdin) if r["id"]==sys.argv[1]]
print(json.dumps(rows[0].get(sys.argv[2])) if len(rows)==1 else "absent")' "$1" "$2"
}
aw_click() {
  local box x y
  box="$(aw_row "$1" "$2")" || return 1
  [[ $box == \[* ]] || { fail "Add widget: $1 has no $2 box"; return 1; }
  read -r x y < <(at_centre window:Bar "$box") || return 1
  click "$x" "$y"
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
  expect "an unplaced enabled widget offers Add" '"add"' aw_row acme.add-widget action
  cp -- "$home/.config/vgshell/shell.json" "$sandbox/add-widget-before-add.json"
  expect "the Add commit observer starts empty" 0 ipc smoke chooserCount true
  aw_click acme.add-widget button
  expect_poll "Add inserts at the clicked $aw_section edge and preserves the saved file" True aw_persisted "$aw_section"
  expect "Add commits exactly one configuration update" single aw_one_write
  expect_poll "a placed widget offers Remove" '"remove"' aw_row acme.add-widget action
  expect "the placed widget shows no chip" '[]' aw_row acme.add-widget chips
  expect "a click on Add leaves no focus ring" '[false, false]' aw_ring
  expect "the duplicate observer starts empty" 0 ipc smoke chooserCount true
  expect "the delivered manager refuses duplicate insertion" "refused: placed=acme.add-widget reason=placed" ipc smoke chooserInsert acme.add-widget "$(first_name)" 20
  expect "the refused duplicate commits nothing" 0 ipc smoke chooserCount false
  aw_click acme.add-widget button
  expect_poll "Remove takes the widget off the bar for the next section" False aw_placed
  expect "Remove keeps a plugin with other kinds on" True aw_enabled
  expect_poll "the unplaced widget offers Add again" '"add"' aw_row acme.add-widget action
  expect "a click on Remove leaves no focus ring" '[false, false]' aw_ring
  expect "the chooser closes" ok ipc shell hide window vgs.bar
  expect_poll "the chooser window is gone" 0 window_count Bar
done

# A widget-only plugin: Remove turns it off, which the delivered manager's
# insertWidget then refuses, and the chooser's Add turns it back on and
# places it, in one write.
expect "the widget-only fixture is enabled" ok ipc shell setPluginEnabled acme.add-only true
expect_poll "the enabled widget-only fixture is placed" True aw_placed acme.add-only
aw_open left
expect "every chooser row is one height" True aw_even
expect "the placed widget-only fixture offers Remove" '"remove"' aw_row acme.add-only action
aw_click acme.add-only button
expect_poll "Remove takes the widget-only fixture off the bar" False aw_placed acme.add-only
expect_poll "an unplaced widget-only plugin reads off" False aw_enabled acme.add-only
expect "the delivered manager still refuses a widget-only plugin that is off" "refused: placed=acme.add-only reason=disabled" ipc smoke chooserInsert acme.add-only "$(first_name)" 20
expect_poll "the widget-only fixture that is off offers Add" '"add"' aw_row acme.add-only action
expect "the turn-on observer starts empty" 0 ipc smoke chooserCount true
aw_click acme.add-only button
expect_poll "Add turns the widget-only fixture back on" True aw_enabled acme.add-only
expect_poll "Add places the widget-only fixture" True aw_placed acme.add-only
expect "Add turns it on in one configuration update" single aw_one_write
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

aw_open left
expect "the fixture is disabled without removing its inventory row" ok ipc shell setPluginEnabled acme.add-widget false
expect_poll "a disabled plugin with other kinds offers Settings" '"settings"' aw_row acme.add-widget action
expect "the disabled row shows no chip" '[]' aw_row acme.add-widget chips
expect "the disabled observer starts empty" 0 ipc smoke chooserCount true
expect "the delivered manager refuses a disabled widget" "refused: placed=acme.add-widget reason=disabled" ipc smoke chooserInsert acme.add-widget "$(first_name)" 20
expect "the delivered manager refuses a non-widget" "refused: placed=vgs.bar reason=no-bar-widget" ipc smoke chooserInsert vgs.bar "$(first_name)" 20
expect "refused rows commit nothing" 0 ipc smoke chooserCount false
aw_click acme.add-widget button
expect_poll "Settings opens the separate Plugins window" 1 window_count Plugins
expect_poll "the manager shows that plugin's Settings page" '"acme.add-widget"' ipc smoke readInstance window vgs.settings page
expect "the chooser remains open beside Plugins" 1 window_count Bar
expect "Plugins closes after the Settings route" ok ipc shell hide window vgs.settings
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
