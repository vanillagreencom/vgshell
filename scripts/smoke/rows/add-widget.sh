# The real empty-bar menu opens the existing bar plugin's chooser window.
# A newly discovered fixture appears without a hand-kept inventory. Add
# inserts once at the clicked section's edge, preserves the rest of the
# persisted configuration and replaces Add with On bar. Names and a grey
# disabled row open the existing separate Plugins window on Settings.
# No latency budget: waits poll reported state at the harness interval.
# The control removes the widget filter's result in a disposable tree;
# the same inventory reader must then reject the missing fixture.
# inputs: shell/plugins/vgs.bar/manifest.json shell/plugins/vgs.bar/Bar.qml shell/plugins/vgs.bar/AddWidget.qml shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/Core/Capabilities.qml shell/Core/Plugins.qml shell/Core/PluginLogic.js shell/Core/Config.qml shell/Core/Registry.qml scripts/smoke/fixtures/plugins/acme.tick/* scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail

aw_saved="$sandbox/add-widget-saved.json"
cp -- "$home/.config/vgshell/shell.json" "$aw_saved"
aw_fixture="$home/.config/vgshell/plugins/acme.add-widget"
mkdir -p -- "$aw_fixture"
cp -R -- "$repo/scripts/smoke/fixtures/plugins/acme.tick/." "$aw_fixture/"
python3 - "$aw_fixture/manifest.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
m = json.loads(p.read_text())
m.update(id="acme.add-widget", name="A widget to add", kinds=["bar-widget", "service"])
m["entryPoints"]["service"] = "Widget.qml"
p.write_text(json.dumps(m))
PY
tree_rescan "the newly installed widget enters the existing registry"
expect "the new fixture is enabled" ok ipc shell setPluginEnabled acme.add-widget true
expect "the multi-kind fixture starts unplaced but enabled" ok ipc shell setPluginPlaced acme.add-widget false
aw_placed() { ipc shell listPlugins | py_reply 'import json,sys; rows=[p for p in json.load(sys.stdin)["plugins"] if p["id"]=="acme.add-widget"]; print(rows[0]["placed"] if len(rows)==1 else "absent")'; }
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
  hover "$((x+1))" "$y" && right_click "$x" "$y" || return 1
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
# The current fixture's actual Add control, chips and boxes.
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
aw_persisted() {
  python3 -c 'import json,sys
before=json.load(open(sys.argv[1])); after=json.load(open(sys.argv[2])); section=sys.argv[3]
layout=before["bar"]["layout"]; entries=layout[section]
entries.insert(len(entries) if section=="left" else 0,{"id":"acme.add-widget"})
print(before==after)' "$sandbox/add-widget-before-add.json" "$home/.config/vgshell/shell.json" "$1"
}
for aw_section in left center right; do
  aw_open "$aw_section"
  expect "an unplaced enabled widget offers Add" true aw_row acme.add-widget add
  cp -- "$home/.config/vgshell/shell.json" "$sandbox/add-widget-before-add.json"
  expect "the Add commit observer starts empty" 0 ipc smoke chooserCount true
  aw_click acme.add-widget button
  expect_poll "Add inserts at the clicked $aw_section edge and preserves the saved file" True aw_persisted "$aw_section"
  expect "Add commits exactly one configuration update" 1 ipc smoke chooserCount false
  expect_poll "a placed widget no longer offers Add" false aw_row acme.add-widget add
  expect "the placed widget shows On bar" '["On bar"]' aw_row acme.add-widget chips
  expect "the duplicate observer starts empty" 0 ipc smoke chooserCount true
  expect "the delivered manager refuses duplicate insertion" "refused: placed=acme.add-widget reason=placed" ipc smoke chooserInsert acme.add-widget "$(first_name)" 20
  expect "the refused duplicate commits nothing" 0 ipc smoke chooserCount false
  expect "the chooser closes" ok ipc shell hide window vgs.bar
  expect_poll "the chooser window is gone" 0 window_count Bar
  expect "the fixture is hidden for the next section" ok ipc shell setPluginPlaced acme.add-widget false
done

aw_open left
aw_click acme.add-widget name
expect_poll "the separate Plugins window opens" 1 window_count Plugins
expect_poll "the manager shows that plugin's Settings page" '"acme.add-widget"' ipc smoke readInstance window vgs.settings page
expect "the chooser remains open beside Plugins" 1 window_count Bar
expect "Plugins closes after the name route" ok ipc shell hide window vgs.settings
expect "the fixture is disabled without removing its inventory row" ok ipc shell setPluginEnabled acme.add-widget false
expect_poll "the disabled widget has no Add action" false aw_row acme.add-widget add
expect "the disabled row shows its shared reason chip" '["Plugin disabled"]' aw_row acme.add-widget chips
expect "the disabled observer starts empty" 0 ipc smoke chooserCount true
expect "the delivered manager refuses a disabled widget" "refused: placed=acme.add-widget reason=disabled" ipc smoke chooserInsert acme.add-widget "$(first_name)" 20
expect "the delivered manager refuses a non-widget" "refused: placed=vgs.bar reason=no-bar-widget" ipc smoke chooserInsert vgs.bar "$(first_name)" 20
expect "refused rows commit nothing" 0 ipc smoke chooserCount false
aw_click acme.add-widget row
expect_poll "clicking the grey row opens Plugins" 1 window_count Plugins
expect_poll "the disabled row opens its own Settings page" '"acme.add-widget"' ipc smoke readInstance window vgs.settings page
expect "Plugins closes after the disabled route" ok ipc shell hide window vgs.settings
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

rm -rf -- "$aw_fixture"
cp -- "$aw_saved" "$home/.config/vgshell/shell.json"
expect "the original user configuration reloads" ok ipc shell reloadConfig
tree_rescan "the private chooser fixture leaves the registry"
