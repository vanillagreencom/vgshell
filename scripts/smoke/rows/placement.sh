# Show in bar and bar reorder: setPluginPlaced takes a widget off the bar
# and puts it back in its default section and never writes disabledPlugins.
# movePluginWidget moves the same layout entry between section lists and
# positions. The bar's shared widget frame starts a drag only after pointer
# motion and keeps right-click Hide. Over the installed fixture acme.probe,
# a service plus a bar widget that rows/plugins.sh enabled and placed, each
# call is read back from the bar's build records, the user shell.json,
# listPlugins and the service's build record. Pointer checks drag real
# widgets, cancel outside the bar and with Escape, prove a still click stays
# a click, and prove a drag cancels the widget's own click. Controls run a
# copy whose move ignores the index, a copy whose drag capture is missing
# and a copy whose BarWidget cannot drag. The row restores the user file
# byte for byte, so rows after it find the fixture placed as before. The
# disabled widget the refusals name is acme.tick, disabled for them and
# enabled again.
# inputs: shell/plugins/vgs.bar/* config/shell.json scripts/smoke/fixtures/plugins/acme.probe/* scripts/smoke/fixtures/plugins/acme.tick/* shell/plugins/vgs.settings/* shell/Commons/Reply.js shell/Core/PluginLogic.js shell/Core/Plugins.qml shell/Core/Registry.qml shell/Core/Capabilities.qml shell/Core/Config.qml shell/Core/KeyCapture.qml shell/Core/HyprlandLayer.js shell/Core/Compositor.qml shell/Core/Dispatch.js shell/Hosts/BarHost.qml shell/shell.qml shell/Ui/BarWidget.qml shell/Ui/feedback/Dialog.qml shell/Ui/overlay/Menu.qml shell/Ui/overlay/MenuItem.qml shell/Ui/overlay/DismissScope.qml scripts/smoke/pointer/click.c scripts/smoke/fixtures/plugins/acme.bare/* scripts/smoke/rows/plugins.sh scripts/smoke/rows/manager.sh scripts/smoke/rows/settings.sh scripts/smoke/rows/sources.sh scripts/smoke/rows/hyprland-consent.sh scripts/smoke/rows/capabilities.sh shell/Commons/Tokens.js
set -euo pipefail
placement_file="$home/.config/vgshell/shell.json"
placement_saved="$sandbox/shell-before-placement.json"
cp -- "$placement_file" "$placement_saved"
cp -- "$placement_file" "$sandbox/shell-placement-entry.json"
# [enabled, placed] of plugin ID in listPlugins.
placement_listed() { ipc shell listPlugins | py_reply 'import json,sys; r=[p for p in json.load(sys.stdin)["plugins"] if p["id"] == sys.argv[1]]; print(json.dumps([r[0]["enabled"], r[0]["placed"]]) if r else "absent")' "$1"; }
# Whether each bar draws the fixture's widget, as the set of answers over
# every bar: [true] in every bar, [false] in none.
placement_in_bars() { bar_widget_ids | py_reply 'import json,sys; print(json.dumps(sorted(set("acme.probe" in ids for ids in json.load(sys.stdin)))))'; }
placement_service() { ipc shell built | py_reply 'import json,sys; print(any(r["id"] == "acme.probe" and r["kind"] == "service" for r in json.load(sys.stdin).get("service", [])))'; }
# The sections of the user file's layout that hold a fixture entry, one per
# entry, and the user file's disabledPlugins.
placement_sections() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); l=d.get("bar", {}).get("layout", {}); print(json.dumps([s for s in ("left", "center", "right") for e in l.get(s, []) if e["id"] == "acme.probe"]))' "$placement_file"; }
placement_disabled() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])).get("disabledPlugins")))' "$placement_file"; }
# The fixture's `placed` on the manager row the Settings window draws.
placement_page() { ipc smoke readInstance window vgs.settings plugins | py_reply 'import json,sys; print(json.dumps([p["placed"] for p in json.load(sys.stdin) if p["id"] == "acme.probe"][0]))'; }
placement_unchanged() { if cmp -s -- "$placement_file" "$placement_saved"; then echo unchanged; else echo changed; fi; }
placement_same_as() { if cmp -s -- "$placement_file" "$1"; then echo unchanged; else echo changed; fi; }
placement_order() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps({s:[e["id"] for e in d["bar"]["layout"][s]] for s in ("left", "center", "right")}))' "$placement_file"; }
# The operations change these four entries. Every other saved entry,
# including disabled widgets, must retain its section and relative order.
placement_expected_order() {
  py_reply 'import json,sys
baseline=json.load(sys.stdin)["bar"]["layout"]; want=json.loads(sys.argv[1])
owned={"acme.tick","acme.probe","vgs.bar/center-clock","vgs.bar/left-workspaces"}
print(json.dumps({s:want[s]+[e["id"] for e in baseline[s] if e["id"] not in owned] for s in want}))' "$1" <"$placement_saved"
}
placement_drawn_start='{"left": ["vgs.bar/left-workspaces"], "center": ["acme.probe", "vgs.bar/center-clock", "acme.tick"], "right": []}'
placement_drawn_before='{"left": ["vgs.bar/left-workspaces"], "center": ["vgs.bar/center-clock", "acme.probe", "acme.tick"], "right": []}'
placement_drawn_after='{"left": ["vgs.bar/left-workspaces"], "center": ["vgs.bar/center-clock", "acme.tick", "acme.probe"], "right": []}'
placement_drawn_left='{"left": ["acme.probe", "vgs.bar/left-workspaces"], "center": ["vgs.bar/center-clock", "acme.tick"], "right": []}'
placement_drawn_pointer_left='{"left": ["vgs.bar/left-workspaces", "acme.probe"], "center": ["vgs.bar/center-clock", "acme.tick"], "right": []}'
placement_drawn_right='{"left": ["vgs.bar/left-workspaces"], "center": ["vgs.bar/center-clock", "acme.tick"], "right": ["acme.probe"]}'
for placement_expected in start before after left pointer_left right; do
  placement_drawn_name="placement_drawn_$placement_expected"
  placement_full="$(placement_expected_order "${!placement_drawn_name}")" || fail "the complete placement expectation is unreadable"
  printf -v "placement_want_$placement_expected" '%s' "$placement_full"
done
placement_visual_order() {
  local key records ids section id box rows=""
  key="$(bar_key)" && records="$(ipc shell built)" || return 1
  ids="$(py_reply 'import json,sys; print(" ".join(r["id"] for r in json.load(sys.stdin)[sys.argv[1]] if r["origin"]=="plugin" or r["kind"]=="bar-widget"))' "$key" <<<"$records")" || return 1
  [[ -n $ids ]] || { echo absent; return; }
  for section in left center right; do
    box="$(ipc smoke barSectionGeometry "$key" "$section")" || return 1
    rows+="$section $box"$'\n'
  done
  for id in $ids; do
    box="$(ipc smoke instanceGeometry "$key" "$id")" || return 1
    rows+="$id $box"$'\n'
  done
  py_reply 'import json,sys
boxes={}
for line in sys.stdin:
    if line.strip():
        ident,value=line.split(" ",1); boxes[ident]=json.loads(value) if value.startswith("[") else None
sections={s:boxes.pop(s) for s in ("left","center","right")}; order={s:[] for s in sections}; errors=[]
for ident,box in boxes.items():
    if box is None or box[2]<=0 or box[3]<=0: errors.append(ident+":not-drawn"); continue
    matches=[s for s,parent in sections.items() if parent is not None and box[0]>=parent[0]-1 and box[1]>=parent[1]-1 and box[0]+box[2]<=parent[0]+parent[2]+1 and box[1]+box[3]<=parent[1]+parent[3]+1]
    if len(matches)!=1: errors.append(ident+":outside-section"); continue
    order[matches[0]].append((box[0],ident))
print(json.dumps({s:[ident for _,ident in sorted(entries)] for s,entries in order.items()}) if not errors else json.dumps({"errors":errors}))' <<<"$rows"
}
placement_center() { ipc smoke instanceGeometry "$(bar_key)" "$1" | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print("%d %d" % (x + w / 2, y + h / 2))'; }
# A Row transition can still move a widget after its layout is published.
# Read the same box across the harness's 200 ms polls before pressing it.
placement_point() {
  local box previous="" stable=0
  smoke_poll_tries 200
  for _ in $(seq 1 "$smoke_poll_n"); do
    box="$(ipc smoke instanceGeometry "$(bar_key)" "$1")" || return 1
    [[ $box == \[* ]] || return 1
    if [[ $box == "$previous" ]]; then stable=$((stable + 1)); else stable=0; fi
    if [[ $stable -ge 2 ]]; then
      py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print("%d %d" % (x+w/2,y+h/2))' <<<"$box"
      return
    fi
    previous="$box"
    sleep 0.2
  done
  printf 'placement: widget did not settle: %s\n' "$1" >&2
  return 1
}
# Aim before the neighbour after the gap displaces it, rather than at its
# original midpoint, which can become the slot after the neighbour.
placement_before() {
  local x y source_box gap
  read -r x y < <(placement_point "$1") || return 1
  source_box="$(ipc smoke instanceGeometry "$(bar_key)" "$2")" || return 1
  gap="$(ipc smoke themeValue bar.gap)" || return 1
  py_reply 'import json,sys; width=json.load(sys.stdin)[2]; print("%d %d" % (int(sys.argv[1])-width-float(sys.argv[3]),int(sys.argv[2])))' "$x" "$y" "$gap" <<<"$source_box"
}
placement_drag_widget() {
  local x y
  read -r x y < <(placement_point "$1") || return 1
  hover "$((x + 1))" "$y" && drag "$x" "$y" "$2" "$3"
}
placement_drag_escape() {
  local id="$1" x2="$2" y2="$3" expected="$4" x y line done_line out_fd in_fd pid status=0
  read -r x y < <(placement_point "$id") || return 1
  hover "$((x + 1))" "$y" || return 1
  coproc placement_hold { "${shell_env[@]}" "$sandbox/click" "$x" "$y" "$mon_w" "$mon_h" drag "$x2" "$y2" hold; }
  out_fd="${placement_hold[0]}"
  in_fd="${placement_hold[1]}"
  pid="$placement_hold_PID"
  if ! read -r -t 10 line <&"$out_fd"; then
    fail "the held drag reaches the barrier"
    status=1
  elif [[ $line != "holding $x2 $y2" ]]; then
    fail "the held drag barrier reads $line"
    status=1
  fi
  if [[ $status -eq 0 && $expected == vgs:passthrough ]]; then
    expect_poll "a held drag enters the pass-through submap" vgs:passthrough key_submap
  elif [[ $status -eq 0 ]]; then
    expect "a held drag without capture leaves the submap default" default key_submap
  fi
  if [[ $status -eq 0 ]]; then
    type_keys -k Escape || { fail "Escape during the held drag"; status=1; }
  fi
  if [[ $status -eq 0 ]]; then
    expect_poll "Escape during a drag leaves the pass-through submap" default key_submap
    expect "the press is still held after Escape" true ipc smoke readInstance "$(bar_key)" "$id" frameDragging
  fi
  printf '\n' >&"$in_fd" || status=1
  exec {in_fd}>&-
  if ! read -r -t 10 done_line <&"$out_fd"; then
    fail "the held drag releases"
    status=1
  fi
  wait "$pid" || status=$?
  exec {out_fd}<&-
  pointer_at="$x2 $y2"
  if [[ $done_line != "dragged $x $y $x2 $y2" ]]; then
    fail "the held drag ended as $done_line"
    status=1
  fi
  return "$status"
}
placement_click_widget() {
  local x y
  read -r x y < <(placement_point "$1") || return 1
  hover "$((x + 1))" "$y" && click "$x" "$y"
}
placement_right_click() {
  local x y
  read -r x y < <(placement_point "$1") || return 1
  hover "$((x + 1))" "$y" && right_click "$x" "$y"
}
placement_bar_below() {
  surface_box vgs:bar | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print("%d %d" % (x + w / 2, y + h + 20))'
}
placement_bar_left_inside() {
  surface_box vgs:bar | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print("%d %d" % (x + w / 6, y + h / 2))'
}
placement_bar_below_left() {
  surface_box vgs:bar | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print("%d %d" % (x + w / 6, y + h + 20))'
}
# placement_reads LABEL PLACED SECTIONS: the reads after a placement edit.
placement_reads() {
  expect_poll "the bar's build records follow $1" "[$2]" placement_in_bars
  expect_poll "the user file's layout follows $1" "$3" placement_sections
  expect_poll "listPlugins reads the fixture enabled and its placement after $1" "[true, $2]" placement_listed acme.probe
  expect "the fixture's service is still built after $1" True placement_service
  expect "disabledPlugins is unchanged by $1" "$placement_disabled_before" placement_disabled
}

expect "the fixture starts enabled and placed" '[true, true]' placement_listed acme.probe
placement_disabled_before="$(placement_disabled)" || fail "the user file's disabledPlugins is unreadable"

expect "the clock moves beside workspaces through the ordinary API" ok ipc shell movePluginWidget vgs.bar/center-clock left 0
expect_builtins "both builtins keep their IDs in the left section" '["vgs.bar/center-clock","vgs.bar/left-workspaces"]'
expect "the builtin reorder snapshot includes both widgets" '["acme.probe","acme.tick","vgs.bar/center-clock","vgs.bar/left-workspaces"]' ipc smoke rememberBarWidgets "$(bar_key)"
expect "workspaces moves before clock through the ordinary API" ok ipc shell movePluginWidget vgs.bar/left-workspaces left 0
placement_left_builtin_order() {
  local ws clock
  ws="$(ipc smoke instanceGeometry "$(bar_key)" vgs.bar/left-workspaces)" || return
  clock="$(ipc smoke instanceGeometry "$(bar_key)" vgs.bar/center-clock)" || return
  py_reply 'import json,sys; a=json.load(sys.stdin); b=json.loads(sys.argv[1]); print(a[0]<b[0])' "$clock" <<<"$ws"
}
geometry expect_poll "the ordinary API reorders the existing builtins" True placement_left_builtin_order
expect "builtin section transfer and reorder keep all objects" '[]' ipc smoke barWidgetIdentities
expect "the builtin snapshot is released" ok ipc smoke forgetBarWidgets
expect "the clock returns to center after its ordinary reorder" ok ipc shell movePluginWidget vgs.bar/center-clock center 0
expect_poll "the ordinary reorder restores the complete saved profile" "$placement_want_right" placement_order

placement_builtin_section() {
  ipc shell listShellConfig | py_reply 'import json,sys; layout=json.load(sys.stdin)["bar"]["layout"]; print(json.dumps([s for s in ("left","center","right") for e in layout[s] if e["id"]==sys.argv[1]]))' "$1"
}
placement_clock_zone() {
  local section="$1" box bounds
  box="$(ipc smoke instanceGeometry "$(bar_key)" vgs.bar/center-clock)" || return
  bounds="$(ipc smoke barSectionGeometry "$(bar_key)" "$section")" || return
  ipc shell listShellConfig | py_reply 'import json,sys; d=json.load(sys.stdin); b=json.loads(sys.argv[2]) if sys.argv[2].startswith("[") else []; s=json.loads(sys.argv[3]) if sys.argv[3].startswith("[") else []; sections=[zone for zone,rows in d.get("bar",{}).get("layout",{}).items() for row in rows if row.get("id")=="vgs.bar/center-clock"]; inside=len(b)==4 and len(s)==4 and b[2]>0 and b[3]>0 and b[0]>=s[0]-1 and b[0]+b[2]<=s[0]+s[2]+1; print(json.dumps({"sections":sections,"inside":inside}))' "$section" "$box" "$bounds"
}
placement_zone_point() {
  surface_box vgs:bar | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); zone={"left":1,"center":3,"right":5}.get(sys.argv[1]); print("%d %d"%(x+w*zone/6,y+h/2) if zone else "unknown")' "$1"
}
placement_clock_hidden() {
  local records before
  records="$(ipc shell built)" || return
  before="$(cat "$sandbox/shell-placement-clock-contract.json")" || return
  ipc shell listShellConfig | py_reply 'import json,sys; effective=json.load(sys.stdin); records=json.loads(sys.argv[1]); before=json.loads(sys.argv[2]); user=json.load(open(sys.argv[3])); bars=[rows for host,rows in records.items() if host.startswith("bar:")]; layout=effective.get("bar",{}).get("layout",{}); placed=any(row.get("id")=="vgs.bar/center-clock" for rows in layout.values() for row in rows); built=any(row.get("id")=="vgs.bar/center-clock" for rows in bars for row in rows); unchanged=all(user.get(key)==before.get(key) for key in ("plugins","disabledPlugins")); print(json.dumps({"placed":placed,"built":built,"ownerEnabled":"vgs.bar" not in effective.get("disabledPlugins",[]),"settingsKept":unchanged}) if bars else "absent")' "$records" "$before" "$placement_file"
}
placement_clock_hide_menu() {
  local id="${1:-vgs.bar/center-clock}"
  placement_right_click "$id" || return 1
  expect_poll "builtin right click opens the shared menu" true ipc smoke readInstance "$(bar_key)" "$id" frameMenuOpen
  expect "builtin Hide keeps the owner's independent enablement" '[true, false]' placement_clock_hide_facts "$id"
  type_keys -k Return || return 1
}
placement_clock_hide_facts() {
  ipc smoke barWidgetFrameFacts "$(bar_key)" "${1:-vgs.bar/center-clock}" | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([d.get("builtin"),d.get("stops")]))'
}
placement_builtin_field() {
  ipc smoke invokeInstance window vgs.settings fieldBoolean "{\"id\":\"$1\",\"key\":\"\"}"
}
placement_builtin_toggle() {
  expect "the existing builtin switch takes keyboard focus" focused ipc smoke invokeInstance window vgs.settings focusBoolean "{\"id\":\"$1\",\"key\":\"\"}"
  type_keys -k Space
}
placement_builtin_saved() {
  python3 - "$placement_file" "$sandbox/shell-before-builtin-field.json" "$1" <<'PY'
import json,sys
after,before=[json.load(open(path)) for path in sys.argv[1:3]]; ident=sys.argv[3]
def without_entry(d):
    for rows in d.get("bar",{}).get("layout",{}).values(): rows[:]=[e for e in rows if e.get("id")!=ident]
    return d
sections=[section for section,rows in after.get("bar",{}).get("layout",{}).items() for row in rows if row.get("id")==ident]
print(json.dumps({"sections":sections,"otherStateKept":without_entry(after)==without_entry(before)}))
PY
}
placement_before_clock() {
  local clock tick bounds
  clock="$(ipc smoke instanceGeometry "$(bar_key)" vgs.bar/center-clock)" || return
  tick="$(ipc smoke instanceGeometry "$(bar_key)" acme.tick)" || return
  bounds="$(ipc smoke barSectionGeometry "$(bar_key)" center)" || return
  ipc shell listShellConfig | py_reply 'import json,sys; d=json.load(sys.stdin); clock,tick,bounds=[json.loads(a) if a.startswith("[") else [] for a in sys.argv[1:]]; center=[r["id"] for r in d.get("bar",{}).get("layout",{}).get("center",[]) if r.get("id") in ("vgs.bar/center-clock","acme.tick")]; visual=all(len(b)==4 and b[2]>0 for b in (clock,tick,bounds)) and tick[0]+tick[2]<=clock[0]+1 and tick[0]>=bounds[0]-1 and clock[0]+clock[2]<=bounds[0]+bounds[2]+1; print(json.dumps({"center":center,"before":visual}))' "$clock" "$tick" "$bounds"
}

# Each clock interaction uses the complete settled profile as its restore point.
expect "the clock starts its interaction checks in center" ok ipc shell movePluginWidget vgs.bar/center-clock center 0
cp -- "$placement_file" "$sandbox/shell-placement-clock-contract.json"
expect "the clock move snapshot includes its wrapper" '["acme.probe","acme.tick","vgs.bar/center-clock","vgs.bar/left-workspaces"]' ipc smoke rememberBarWidgets "$(bar_key)"
for clock_zone in left center right; do
  read -r clock_x clock_y < <(placement_zone_point "$clock_zone") || fail "the clock zone target is unreadable"
  placement_drag_widget vgs.bar/center-clock "$clock_x" "$clock_y" || fail "the clock pointer move completes"
  geometry expect_poll "clock pointer drop keeps the ordinary entry inside $clock_zone" "{\"sections\": [\"$clock_zone\"], \"inside\": true}" placement_clock_zone "$clock_zone"
  expect "clock transfer keeps every original wrapper" '[]' ipc smoke barWidgetIdentities
  expect_poll "clock transfer releases keyboard capture" default key_submap
done
expect "the clock move snapshot is released" ok ipc smoke forgetBarWidgets
cp -- "$sandbox/shell-placement-clock-contract.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
expect_poll "the settled clock profile returns" '["center"]' placement_builtin_section vgs.bar/center-clock
expect "the neighbor moves away before its drop to clock's left" ok ipc shell movePluginWidget acme.tick right 0
read -r clock_x clock_y < <(placement_before vgs.bar/center-clock acme.tick) || fail "the point before clock is unreadable"
placement_drag_widget acme.tick "$clock_x" "$clock_y" || fail "the neighbor pointer drop completes"
geometry expect_poll "a widget pointer drop reaches clock's left in center" '{"center": ["acme.tick", "vgs.bar/center-clock"], "before": true}' placement_before_clock
expect_poll "the neighbor drop releases keyboard capture" default key_submap
cp -- "$sandbox/shell-placement-clock-contract.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
expect_poll "the clock profile returns before Hide" '["center"]' placement_builtin_section vgs.bar/center-clock
placement_clock_hide_menu || fail "the clock shared Hide action completes"
expect_poll "clock Hide removes only its ordinary placement" '{"placed": false, "built": false, "ownerEnabled": true, "settingsKept": true}' placement_clock_hidden
expect_poll "clock Hide releases keyboard capture" default key_submap
expect "Settings opens the bar's placement fields after clock Hide" ok ipc shell summon window vgs.settings '{"plugin":"vgs.bar"}'
expect_poll "the hidden clock retains its existing boolean field" '{"type":"boolean","value":false,"checked":false,"enabled":true}' placement_builtin_field vgs.bar/center-clock
cp -- "$sandbox/shell-placement-clock-contract.json" "$sandbox/shell-before-builtin-field.json"
placement_builtin_toggle vgs.bar/center-clock || fail "the clock recovery switch executes"
expect_poll "the clock switch restores the sole layout state" '{"sections": ["center"], "otherStateKept": true}' placement_builtin_saved vgs.bar/center-clock
expect_poll "the restored clock field reads its ordinary membership" '{"type":"boolean","value":true,"checked":true,"enabled":true}' placement_builtin_field vgs.bar/center-clock
expect_poll "the restored clock has no Hide confirmation" false ipc smoke readInstance "$(bar_key)" vgs.bar/center-clock frameDialogOpen
cp -- "$placement_file" "$sandbox/shell-before-builtin-field.json"
placement_builtin_toggle vgs.bar/center-clock || fail "the clock Hide switch executes"
expect_poll "the clock switch hides without second state" '{"sections": [], "otherStateKept": true}' placement_builtin_saved vgs.bar/center-clock
expect_poll "the clock field remains available when its wrapper is absent" '{"type":"boolean","value":false,"checked":false,"enabled":true}' placement_builtin_field vgs.bar/center-clock
placement_builtin_toggle vgs.bar/center-clock || fail "the clock switch restores again"
expect_poll "the clock switch recovers again" '{"sections": ["center"], "otherStateKept": true}' placement_builtin_saved vgs.bar/center-clock
cp -- "$placement_file" "$sandbox/shell-before-builtin-field.json"
placement_clock_hide_menu vgs.bar/left-workspaces || fail "the workspace Hide menu executes"
expect_poll "workspace Hide removes the sole layout state" '{"sections": [], "otherStateKept": true}' placement_builtin_saved vgs.bar/left-workspaces
expect_poll "the hidden workspace retains its field" '{"type":"boolean","value":false,"checked":false,"enabled":true}' placement_builtin_field vgs.bar/left-workspaces
placement_builtin_toggle vgs.bar/left-workspaces || fail "the workspace switch restores"
expect_poll "the workspace switch restores its declared left section" '{"sections": ["left"], "otherStateKept": true}' placement_builtin_saved vgs.bar/left-workspaces
expect_poll "the workspace field reads restored membership" '{"type":"boolean","value":true,"checked":true,"enabled":true}' placement_builtin_field vgs.bar/left-workspaces
expect "Settings closes after builtin recovery" ok ipc shell hide window vgs.settings
cp -- "$sandbox/shell-placement-clock-contract.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
expect_builtins "restoring the settled profile registers both builtins" '["vgs.bar/center-clock","vgs.bar/left-workspaces"]'
placement_bar_cleanups() {
  ipc shell built | py_reply 'import json,sys; bars=[rows for host,rows in json.load(sys.stdin).items() if host.startswith("bar:")]; counts=[r["pendingCleanups"] for rows in bars for r in rows if r["id"]=="vgs.bar" and r["origin"]=="core"]; print(json.dumps(sorted(counts)) if len(counts)==len(bars) and bars else "absent")'
}
placement_cleanup_baseline="$(placement_bar_cleanups)" || fail "the bar registration count is unreadable"
for builtin_round in 1 2; do
  for builtin_id in vgs.bar/center-clock vgs.bar/left-workspaces; do
    expect "an ordinary builtin can leave its owner bar" ok ipc shell setPluginPlaced "$builtin_id" false
    expect_poll "builtin removal leaves no ordinary placement" '[]' placement_builtin_section "$builtin_id"
    cp -- "$sandbox/shell-placement-clock-contract.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
    expect_builtins "the whole settled profile restores one registration per builtin" '["vgs.bar/center-clock","vgs.bar/left-workspaces"]'
    expect_poll "builtin restore balances its owner's registration releases" "$placement_cleanup_baseline" placement_bar_cleanups
  done
  expect "the owner bar can be disabled after builtin removal cycles" 'ok hidden=acme.probe,acme.tick' ipc shell setPluginEnabled vgs.bar false
  expect_builtins "bar teardown releases every builtin registration" '[]'
  expect_poll "bar teardown releases keyboard capture" default key_submap
  expect "the owner bar can return after teardown" ok ipc shell setPluginEnabled vgs.bar true
  expect_builtins "bar re-enable registers each builtin once" '["vgs.bar/center-clock","vgs.bar/left-workspaces"]'
  expect_poll "the new owner has the same pending registrations" "$placement_cleanup_baseline" placement_bar_cleanups
done
cp -- "$sandbox/shell-placement-clock-contract.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
# Hold the builtin's own shared frame across a section move into a plugin
# neighbour. The same pointer barrier proves it stays the grabbed object.
placement_held_builtin() {
  local x y tx ty barrier out_fd in_fd hold_pid
  read -r x y < <(placement_point vgs.bar/left-workspaces) || return 1
  # One pixel left of the tick's left edge: a slot comes from the
  # neighbours' shifted boxes (Plugins.dragMove), and whether the preview
  # stands before the clock or before the tick, this point lies past the
  # clock's middle and short of the tick's, so it reads before the tick
  # whatever path the pointer took.
  read -r tx ty < <(placement_point acme.tick) || return 1
  tx="$(ipc smoke instanceGeometry "$(bar_key)" acme.tick | py_reply 'import json,sys; print(int(json.load(sys.stdin)[0]) - 1)')" || return 1
  expect "the builtin drag snapshot includes all widgets" '["acme.probe","acme.tick","vgs.bar/center-clock","vgs.bar/left-workspaces"]' ipc smoke rememberBarWidgets "$(bar_key)"
  hover "$((x + 1))" "$y" || return 1
  coproc builtin_hold { "${shell_env[@]}" "$sandbox/click" "$x" "$y" "$mon_w" "$mon_h" drag "$tx" "$ty" hold; }
  out_fd="${builtin_hold[0]}" in_fd="${builtin_hold[1]}" hold_pid="$builtin_hold_PID"
  read -r -t 10 barrier <&"$out_fd" || return 1
  [[ $barrier == "holding $tx $ty" ]] || return 1
  expect_poll "the builtin drag holds keyboard capture" vgs:passthrough key_submap
  expect "the builtin's press stays held across visual section transfer" true ipc smoke readInstance "$(bar_key)" vgs.bar/left-workspaces frameDragging
  expect "the held builtin preview keeps every widget object" '[]' ipc smoke barWidgetIdentities
  expect "the builtin preview selects before its plugin neighbour" '["center", 1]' placement_preview_slot
  printf '\n' >&"$in_fd"
  exec {in_fd}>&-
  read -r -t 10 barrier <&"$out_fd" || return 1
  wait "$hold_pid" || return 1
  exec {out_fd}<&-
  pointer_at="$tx $ty"
  expect_poll "the builtin pointer drop persists its new section" '["center"]' placement_builtin_section vgs.bar/left-workspaces
  expect "the builtin pointer drop keeps every object" '[]' ipc smoke barWidgetIdentities
  expect_poll "the builtin drop releases keyboard capture" default key_submap
  expect "the builtin drag snapshot is released" ok ipc smoke forgetBarWidgets
}
placement_preview_slot() { ipc smoke barDragGeometry "$(bar_key)" | py_reply 'import json,sys; state=json.load(sys.stdin); print(json.dumps([state["section"],state["index"]]) if isinstance(state,dict) else "absent")'; }
placement_held_builtin || fail "the builtin held pointer move completes"
expect "workspaces returns to left after its pointer move" ok ipc shell movePluginWidget vgs.bar/left-workspaces left 0
cp -- "$placement_file" "$sandbox/shell-before-builtin-escape.json"
read -r tick_x tick_y < <(placement_point acme.tick) || fail "the builtin Escape target is unreadable"
placement_drag_escape vgs.bar/left-workspaces "$tick_x" "$tick_y" vgs:passthrough || fail "the builtin Escape press completes"
expect "builtin Escape leaves its layout unchanged" unchanged placement_same_as "$sandbox/shell-before-builtin-escape.json"
expect_poll "builtin Escape leaves no keyboard capture" default key_submap
workspace_before="$(hypr -j activeworkspace | py_reply 'import json,sys; print(json.load(sys.stdin)["id"])')" || fail "the focused workspace is unreadable"
workspace_target=1
[[ $workspace_before == 1 ]] && workspace_target=2
workspace_box="$(ipc smoke itemGeometry "$(bar_key)" vgs.bar/left-workspaces BarItem "$workspace_target")" || fail "the workspace pill is unreadable"
workspace_point="$(py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print("%d %d" % (x+w/2,y+h/2))' <<<"$workspace_box")" || fail "the workspace pill point is unreadable"
read -r workspace_x workspace_y <<<"$workspace_point"
hover "$((workspace_x + 1))" "$workspace_y" && click "$workspace_x" "$workspace_y" || fail "the still workspace click completes"
placement_focused_workspace() { hypr -j activeworkspace | py_reply 'import json,sys; print(json.load(sys.stdin)["id"])'; }
expect_poll "a still click on the builtin keeps its workspace action" "$workspace_target" placement_focused_workspace
expect "the original workspace returns after the builtin click" ok probe dispatch "focusWorkspace $workspace_before"
expect_poll "the original workspace is focused again" "$workspace_before" placement_focused_workspace

expect "disabling acme.tick for the refusals is allowed" ok ipc shell setPluginEnabled acme.tick false
expect_poll "acme.tick reads disabled for the refusals" False plugin_enabled acme.tick
placement_refused="$sandbox/shell-before-placement-refusals.json"
cp -- "$placement_file" "$placement_refused"
expect "an id no plugin has is unknown" "unknown: acme.nowhere" ipc shell setPluginPlaced acme.nowhere true
expect "a plugin without a bar widget is refused" "refused: placed=acme.bare reason=no-bar-widget" ipc shell setPluginPlaced acme.bare true
expect "a disabled plugin's widget is refused" "refused: placed=acme.tick reason=disabled" ipc shell setPluginPlaced acme.tick true
expect "the refusals leave the user file as it was" unchanged placement_same_as "$placement_refused"
expect "an id no plugin has is unknown for move" "unknown: acme.nowhere" ipc shell movePluginWidget acme.nowhere center 0
expect "a plugin without a bar widget is refused for move" "refused: moved=acme.bare reason=no-bar-widget" ipc shell movePluginWidget acme.bare center 0
expect "a disabled plugin's widget is refused for move" "refused: moved=acme.tick reason=disabled" ipc shell movePluginWidget acme.tick left 0
expect "an unknown section is refused for move" 'refused: section="top" want=left|center|right' ipc shell movePluginWidget acme.probe top 0
expect "a negative index is refused for move" 'refused: index=-1 want=integer>=0' ipc shell movePluginWidget acme.probe center -1
expect "the move refusals leave the user file as it was" unchanged placement_same_as "$placement_refused"
expect "enabling acme.tick after the refusals is allowed" ok ipc shell setPluginEnabled acme.tick true
expect_poll "acme.tick reads enabled after the refusals" True plugin_enabled acme.tick

expect "moving the fixture to the start of center is allowed" ok ipc shell movePluginWidget acme.probe center 0
expect_poll "the user file order follows the move to center" "$placement_want_start" placement_order
expect_poll "the rendered order follows the move to center" "$placement_drawn_start" placement_visual_order
expect "moving the fixture after the center widget is allowed" ok ipc shell movePluginWidget acme.probe center 2
expect_poll "the user file order follows the move within center" "$placement_want_after" placement_order
expect_poll "the rendered order follows the move within center" "$placement_drawn_after" placement_visual_order
expect "moving the fixture across sections is allowed" ok ipc shell movePluginWidget acme.probe left 0
expect_poll "the user file order follows the move to left" "$placement_want_left" placement_order
expect_poll "the rendered order follows the move to left" "$placement_drawn_left" placement_visual_order
expect "moving the fixture back to right is allowed" ok ipc shell movePluginWidget acme.probe right 0
expect_poll "the fixture is back in the right section after move tests" "$placement_want_right" placement_order

# An unchanged drop still must return the held widget to its section. The
# configuration writer publishes no change for this exact same slot.
placement_same_slot() {
  local x y tx ty barrier out_fd in_fd hold_pid last original_box
  last="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["bar"]["layout"]["right"])-1)' "$placement_file")" || return 1
  expect "the unchanged-drop fixture moves after every right entry" ok ipc shell movePluginWidget acme.probe right "$last"
  read -r x y < <(placement_point acme.probe) || return 1
  original_box="$(ipc smoke instanceGeometry "$(bar_key)" acme.probe)" || return 1
  geometry expect "the unchanged-drop fixture starts at the right edge" True probe_at_right_edge
  # Vertical motion activates the handler without selecting another x gap.
  tx="$x" ty="$((y + 12))"
  cp -- "$placement_file" "$sandbox/shell-before-same-slot.json"
  hover "$((x + 1))" "$y" || return 1
  coproc placement_same { "${shell_env[@]}" "$sandbox/click" "$x" "$y" "$mon_w" "$mon_h" drag "$tx" "$ty" hold; }
  out_fd="${placement_same[0]}" in_fd="${placement_same[1]}" hold_pid="$placement_same_PID"
  read -r -t 10 barrier <&"$out_fd" || return 1
  [[ $barrier == "holding $tx $ty" ]] || return 1
  expect "the unchanged drop has an active original-slot preview" "[\"right\", $last]" placement_preview_slot
  printf '\n' >&"$in_fd"
  exec {in_fd}>&-
  read -r -t 10 barrier <&"$out_fd" || return 1
  wait "$hold_pid" || return 1
  exec {out_fd}<&-
  pointer_at="$tx $ty"
  expect_poll "the unchanged drop leaves rearrange mode" absent ipc smoke barDragGeometry "$(bar_key)"
  expect "the unchanged drop writes no configuration" unchanged placement_same_as "$sandbox/shell-before-same-slot.json"
  geometry expect_poll "the unchanged drop restores the original widget geometry" "$original_box" ipc smoke instanceGeometry "$(bar_key)" acme.probe
  geometry expect_poll "the unchanged drop restores the widget to the right edge" True probe_at_right_edge
}
placement_same_slot || fail "the unchanged drop press completes"

# The same held press opens the target gap before it writes. The probe
# retains QObject references, including the registered built-ins, so a
# rebuilt section cannot pass the identity check.
placement_live_gap() {
  local before_x="$1" target_x="$2" drag_json tick_box
  drag_json="$(ipc smoke barDragGeometry "$(bar_key)")" || return
  tick_box="$(ipc smoke instanceGeometry "$(bar_key)" acme.tick)" || return
  py_reply 'import json,sys
state=json.load(sys.stdin); tick=json.loads(sys.argv[1]); old=float(sys.argv[2]); pointer=float(sys.argv[3])
if not isinstance(state,dict): print("absent"); sys.exit()
print(json.dumps({"section":state["section"], "index":state["index"], "slid":abs(tick[0]-old)>1,
 "held":abs(state["item"][0]+state["item"][2]/2-pointer)<=1,
 "gap":state["gap"][2]>0 and state["gap"][0]>=state["target"][0]-1}))' "$tick_box" "$before_x" "$target_x" <<<"$drag_json"
}
placement_held_preview() {
  local motion="$1" x y tx ty before_x barrier out_fd in_fd hold_pid reading sample motion_seen samples=()
  read -r x y < <(placement_point acme.probe) || return 1
  read -r tx ty < <(placement_before acme.tick acme.probe) || return 1
  before_x="$(ipc smoke instanceGeometry "$(bar_key)" acme.tick | py_reply 'import json,sys; print(json.load(sys.stdin)[0])')" || return 1
  expect "the identity snapshot includes built-ins and mounted widgets" '["acme.probe","acme.tick","vgs.bar/center-clock","vgs.bar/left-workspaces"]' ipc smoke rememberBarWidgets "$(bar_key)"
  hover "$((x + 1))" "$y" || return 1
  coproc placement_preview { "${shell_env[@]}" "$sandbox/click" "$x" "$y" "$mon_w" "$mon_h" drag "$tx" "$ty" hold; }
  out_fd="${placement_preview[0]}" in_fd="${placement_preview[1]}" hold_pid="$placement_preview_PID"
  read -r -t 10 barrier <&"$out_fd" || return 1
  [[ $barrier == "holding $tx $ty" ]] || return 1
  # With the pointer held at its target, distinct successive local x
  # readings prove the neighbor glides rather than jumping into place.
  for reading in 1 2 3 4 5 6; do
    sample="$(ipc smoke readInstance "$(bar_key)" acme.tick x)" || return 1
    samples+=("$sample")
  done
  motion_seen="$(py_reply 'import json,sys; values=[json.loads(v) for v in sys.argv[1:]]; print("unreadable" if not all(isinstance(v,(int,float)) for v in values) else "moving" if any(a!=b for a,b in zip(values,values[1:])) else "still")' "${samples[@]}" <<<'{}')" || return 1
  printf '  held_motion expected=%s observed=%s samples=%s\n' "$motion" "$motion_seen" "${samples[*]}"
  geometry expect "the held neighbor's successive positions show $motion motion" "$motion" printf '%s\n' "$motion_seen"
  printf '  held_operation source=%s,%s target=%s,%s drag=%s frame=%s submap=%s pointer=%s profile=%s\n' "$x" "$y" "$tx" "$ty" "$(ipc smoke barDragGeometry "$(bar_key)")" "$(ipc smoke readInstance "$(bar_key)" acme.probe frameDragging)" "$(key_submap)" "$(hypr cursorpos)" "$(ipc shell listShellConfig)"
  for placement_held_id in acme.probe acme.tick vgs.bar/center-clock; do
    printf '  held_geometry id=%s value=%s\n' "$placement_held_id" "$(ipc smoke descendantGeometry "$(bar_key)" "$placement_held_id")"
  done
  geometry expect_poll "the held widget follows the pointer while the target widget slides around its gap" '{"section": "center", "index": 1, "slid": true, "held": true, "gap": true}' placement_live_gap "$before_x" "$tx"
  expect "a held drag writes no configuration" unchanged placement_same_as "$sandbox/shell-before-live-drop.json"
  expect "the held preview keeps every widget object" '[]' ipc smoke barWidgetIdentities
  printf '\n' >&"$in_fd"
  exec {in_fd}>&-
  read -r -t 10 barrier <&"$out_fd" || return 1
  wait "$hold_pid" || return 1
  exec {out_fd}<&-
  pointer_at="$tx $ty"
  expect_poll "the release commits the order the gap showed" "$placement_want_before" placement_order
  geometry expect_poll "the release draws the complete order the gap showed" "$placement_drawn_before" placement_visual_order
  expect "the drop keeps the moved widget and every other widget object" '[]' ipc smoke barWidgetIdentities
  expect_poll "the release leaves rearrange mode" absent ipc smoke barDragGeometry "$(bar_key)"
  expect "the identity snapshot is released" ok ipc smoke forgetBarWidgets
}
cp -- "$placement_file" "$sandbox/shell-before-live-drop.json"
placement_motion_theme="$home/.config/vgshell/theme.json"
placement_motion_original_duration="$(ipc smoke themeValue motion.duration.normal)" || fail "the original motion duration is unreadable"
placement_motion_had_theme=false
if [[ -f $placement_motion_theme ]]; then
  cp -- "$placement_motion_theme" "$sandbox/placement-motion-theme.json"
  placement_motion_had_theme=true
fi
printf '%s\n' '{"schemaVersion":1,"name":"bar-motion","tokens":{"motion":{"scale":4}}}' >"$placement_motion_theme.tmp"
mv -T -- "$placement_motion_theme.tmp" "$placement_motion_theme"
expect_poll "the slowed motion reaches the held widget check" 600 ipc smoke themeValue motion.duration.normal
placement_held_preview moving || fail "the held preview press completes"
expect "the fixture returns to right before the other pointer checks" ok ipc shell movePluginWidget acme.probe right 0
expect_poll "the fixture is back in right" "$placement_want_right" placement_order
if copy_tree placement-motion-control \
  && edit_tree placement-motion-control shell/Ui/BarWidget.qml 'enabled: !root.frameDragging && root.bar !== null' 'enabled: false && !root.frameDragging && root.bar !== null'; then
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-motion-control" "$sandbox/placement-motion-control.log" || fail "the horizontal motion control shell starts"
  cp -- "$placement_file" "$sandbox/shell-before-live-drop.json"
  placement_held_preview still || fail "control: the same held preview press completes without horizontal animation"
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-motion-restored.log" || fail "the shell starts after the horizontal motion control"
fi
printf '%s\n' '{"schemaVersion":1,"name":"bar-motion-off","tokens":{"motion":{"scale":0}}}' >"$placement_motion_theme.tmp"
mv -T -- "$placement_motion_theme.tmp" "$placement_motion_theme"
expect_poll "Motion off reaches the held widget check" 0 ipc smoke themeValue motion.duration.normal
cp -- "$placement_file" "$sandbox/shell-before-live-drop.json"
placement_held_preview still || fail "Motion off keeps the held neighbours still"
expect "the fixture returns to right after Motion off" ok ipc shell movePluginWidget acme.probe right 0
expect_poll "Motion off restores the complete profile" "$placement_want_right" placement_order
if copy_tree placement-reduced-motion-control \
  && edit_tree placement-reduced-motion-control shell/Ui/BarWidget.qml 'duration: Theme.motion.duration.normal;' 'duration: Theme.motion.duration.normal === 0 ? 600 : Theme.motion.duration.normal;'; then
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-reduced-motion-control" "$sandbox/placement-reduced-motion-control.log" || fail "the Motion off control shell starts"
  expect "control: Motion off remains selected" 0 ipc smoke themeValue motion.duration.normal
  cp -- "$placement_file" "$sandbox/shell-before-live-drop.json"
  placement_held_preview moving || fail "control: ignoring Motion off makes the held neighbours move"
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-reduced-motion-restored.log" || fail "the shell starts after the Motion off control"
fi
if [[ $placement_motion_had_theme == true ]]; then
  cp -- "$sandbox/placement-motion-theme.json" "$placement_motion_theme.tmp"
  mv -T -- "$placement_motion_theme.tmp" "$placement_motion_theme"
else
  rm -- "$placement_motion_theme"
fi
expect_poll "the original motion returns after the held checks" "$placement_motion_original_duration" ipc smoke themeValue motion.duration.normal

read -r tick_x tick_y < <(placement_before acme.tick acme.probe) || fail "the tick widget point is unreadable"
placement_drag_widget acme.probe "$tick_x" "$tick_y" || fail "dragging the fixture into center failed"
expect_poll "a pointer drag moves the fixture into center in the file" "$placement_want_before" placement_order
expect_poll "a pointer drag moves the fixture into center on the bar" "$placement_drawn_before" placement_visual_order
read -r tick_x tick_y < <(placement_point acme.tick) || fail "the tick widget point is unreadable after the first drag"
placement_drag_widget acme.probe "$((tick_x + 40))" "$tick_y" || fail "dragging the fixture within center failed"
expect_poll "a pointer drag reorders within center in the file" "$placement_want_after" placement_order
expect_poll "a pointer drag reorders within center on the bar" "$placement_drawn_after" placement_visual_order
read -r left_x left_y < <(placement_bar_left_inside) || fail "the point in the bar's left third is unreadable"
placement_drag_widget acme.probe "$left_x" "$left_y" || fail "dragging the fixture past workspaces in the left section failed"
expect_poll "a pointer drag moves the fixture after workspaces in the left section" "$placement_want_pointer_left" placement_order
geometry expect_poll "the pointer drop draws the fixture after workspaces" "$placement_drawn_pointer_left" placement_visual_order
expect "moving the fixture back into center is allowed" ok ipc shell movePluginWidget acme.probe center 2
expect_poll "the fixture is back after the center widget" "$placement_want_after" placement_order
cp -- "$placement_file" "$sandbox/shell-before-outside-drop.json"
read -r below_x below_y < <(placement_bar_below_left) || fail "the point below the left third of the bar is unreadable"
placement_drag_widget acme.probe "$below_x" "$below_y" || fail "dragging the fixture below the bar failed"
expect_poll "a drag released below the left third of the bar leaves the user file as it was" unchanged placement_same_as "$sandbox/shell-before-outside-drop.json"
hypr_lua_save placement
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$home/.config/hypr/hyprland.lua"
expect "the nested instance reloads with keysym binds" ok hypr reload config-only
cp -- "$placement_file" "$sandbox/shell-before-escape-drop.json"
read -r tick_x tick_y < <(placement_point acme.tick) || fail "the tick widget point is unreadable before Escape"
placement_drag_escape acme.probe "$tick_x" "$tick_y" vgs:passthrough || fail "holding a drag and pressing Escape failed"
expect_poll "Escape during a drag ends frame dragging after release" false ipc smoke readInstance "$(bar_key)" acme.probe frameDragging
expect_poll "Escape during a drag keeps the rendered order" "$placement_drawn_after" placement_visual_order
expect "Escape during a drag leaves the user file as it was" unchanged placement_same_as "$sandbox/shell-before-escape-drop.json"
hypr_lua_restore placement || fail "placement puts the harness hyprland.lua back"
expect "the nested instance reloads the harness hyprland.lua" ok hypr reload config-only
tick_clicks_before="$(ipc smoke readInstance "$(bar_key)" acme.tick clicks)" || fail "the tick click count is unreadable"
placement_click_widget acme.tick || fail "clicking acme.tick failed"
expect_poll "a click without movement reaches acme.tick" "$((tick_clicks_before + 1))" ipc smoke readInstance "$(bar_key)" acme.tick clicks
tick_clicks_before="$(ipc smoke readInstance "$(bar_key)" acme.tick clicks)" || fail "the tick click count is unreadable before a drag"
tick_cancels_before="$(ipc smoke readInstance "$(bar_key)" acme.tick cancels)" || fail "the tick cancel count is unreadable before a drag"
read -r below_x below_y < <(placement_bar_below) || fail "the point below the bar is unreadable before the tick drag"
placement_drag_widget acme.tick "$below_x" "$below_y" || fail "dragging acme.tick failed"
expect "a drag that starts on acme.tick emits no click" "$tick_clicks_before" ipc smoke readInstance "$(bar_key)" acme.tick clicks
expect "a drag that starts on acme.tick cancels its MouseArea" "$((tick_cancels_before + 1))" ipc smoke readInstance "$(bar_key)" acme.tick cancels
placement_right_click acme.probe || fail "right clicking the fixture failed"
expect_poll "a right click on a moved widget still opens its menu" true ipc smoke readInstance "$(bar_key)" acme.probe frameMenuOpen
type_keys -k Escape || fail "Escape on the frame menu failed"
expect_poll "Escape closes the frame menu" false ipc smoke readInstance "$(bar_key)" acme.probe frameMenuOpen
expect "moving the fixture back to right after pointer tests is allowed" ok ipc shell movePluginWidget acme.probe right 0
expect_poll "the fixture is back in the right section after pointer tests" "$placement_want_right" placement_order

expect "unplacing the fixture is allowed" ok ipc shell setPluginPlaced acme.probe false
placement_reads "the unplace" false '[]'
cp -- "$placement_file" "$sandbox/shell-before-unplaced-move.json"
expect "an unplaced widget is refused for move" "refused: moved=acme.probe reason=unplaced" ipc shell movePluginWidget acme.probe center 0
if cmp -s -- "$placement_file" "$sandbox/shell-before-unplaced-move.json"; then ok "the unplaced move refusal leaves the user file as it was"; else fail "the unplaced move refusal changed the user file"; fi
expect "placing the fixture is allowed" ok ipc shell setPluginPlaced acme.probe true
placement_reads "the place" true '["right"]'
expect "unplacing the fixture again is allowed" ok ipc shell setPluginPlaced acme.probe false
placement_reads "the second unplace" false '[]'

# The drawn switch: real clicks on the page's Show in bar Switch.
settings_page_open acme.probe
expect_poll "the page reads the fixture unplaced" false placement_page
settings_press --type Switch "" Field "Show in bar" || fail "the click on the Show in bar switch failed"
expect_poll "the switch places the widget in the user file" '["right"]' placement_sections
expect_poll "the switch puts the widget in every bar" '[true]' placement_in_bars
expect_poll "listPlugins reads the fixture enabled and placed after the switch" '[true, true]' placement_listed acme.probe
expect_poll "the page reads the fixture placed" true placement_page
settings_press --type Switch "" Field "Show in bar" || fail "the second click on the Show in bar switch failed"
expect_poll "the switch takes the widget out of the user file" '[]' placement_sections
expect_poll "the switch takes the widget off every bar" '[false]' placement_in_bars
expect_poll "listPlugins reads the fixture enabled and unplaced after the switch" '[true, false]' placement_listed acme.probe
expect "the fixture's service is still built after the switch" True placement_service
# A widget-only plugin's Enabled switch is its placement: the same lookup
# that found the probe's switch finds none on acme.tick's page.
expect "Settings is summoned on acme.tick's page" ok ipc shell summon window vgs.settings '{"plugin":"acme.tick"}'
expect_poll "the Settings window shows acme.tick's page" '"acme.tick"' ipc smoke readInstance window vgs.settings page
expect_poll "a widget-only plugin's page draws no Show in bar" absent ipc smoke scopedWindowGeometry window vgs.settings Field "Show in bar" Switch ""
settings_page_close acme.probe

expect "placing the fixture before the restart check is allowed" ok ipc shell setPluginPlaced acme.probe true
expect "moving the fixture to left before restart is allowed" ok ipc shell movePluginWidget acme.probe left 0
expect_poll "the user file order is moved before restart" "$placement_want_left" placement_order
stop_shell
start_shell "$repo" "$sandbox/placement-restart.log" || fail "the shell starts again for moved placement"
expect_poll "a restart keeps the moved file order" "$placement_want_left" placement_order
expect_poll "a restart keeps the moved rendered order" "$placement_drawn_left" placement_visual_order
expect "moving the fixture back to right after restart is allowed" ok ipc shell movePluginWidget acme.probe right 0
expect_poll "the fixture is back in the right section after restart" "$placement_want_right" placement_order

cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
expect_poll "the restored user file is ready for placement controls" "$placement_want_right" placement_order
if copy_tree placement-move-control \
  && edit_tree placement-move-control shell/Core/PluginLogic.js 'target.splice(at, 0, entry);' 'target.push(entry);' \
  && edit_tree placement-move-control shell/Core/Plugins.qml '        if (barDrop !== null && barDrop.hostKey === hostKey) barDrop = null;
        if (barDrag !== null && barDrag.hostKey === hostKey) cancelBarDrag();' ';'; then
  stop_shell
  start_shell "$sandbox/tree-placement-move-control" "$sandbox/placement-move-control.log" || fail "the placement move control shell starts"
  expect "control: moving the fixture before tick answers ok" ok ipc shell movePluginWidget acme.probe center 1
  control_order="$(placement_order)" || fail "control: the moved order is unreadable"
  if [[ $control_order == "$placement_want_after" ]]; then
    ok "control: withMoved ignoring the index reads red"
    geometry expect_poll "control: the drawn ordinary order also rejects the ignored index" "$placement_drawn_after" placement_visual_order
  else
    fail "control: withMoved ignoring the index did not read red: $control_order"
  fi
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  expect_poll "control: the user file is restored before the outside-drop control" "$placement_want_right" placement_order
  read -r below_x below_y < <(placement_bar_below_left) || fail "control: the point below the left third of the bar is unreadable"
  placement_drag_widget acme.probe "$below_x" "$below_y" || fail "control: dragging the fixture below the left third failed"
  expect_poll "control: without the outside-bar guard the file changes" changed placement_same_as "$placement_saved"
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-move-control-restored.log" || fail "the shell starts again after the move control"
fi

if copy_tree placement-escape-control \
  && edit_tree placement-escape-control shell/Core/Plugins.qml '        Capabilities.keyCapture.begin(ctx, item, { anyWindow: true });' ';'; then
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-escape-control" "$sandbox/placement-escape-control.log" || fail "the placement Escape control shell starts"
  hypr_lua_save placement-escape-control
  printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$home/.config/hypr/hyprland.lua"
  expect "control Escape: the nested instance reloads with keysym binds" ok hypr reload config-only
  cp -- "$placement_file" "$sandbox/shell-before-escape-control.json"
  read -r tick_x tick_y < <(placement_point acme.tick) || fail "control Escape: the tick widget point is unreadable"
  placement_drag_escape acme.probe "$tick_x" "$tick_y" default || fail "control Escape: holding a drag and pressing Escape failed"
  expect_poll "control Escape: without drag capture the release drops the widget" changed placement_same_as "$sandbox/shell-before-escape-control.json"
  hypr_lua_restore placement-escape-control || fail "control Escape: placement puts the harness hyprland.lua back"
  expect "control Escape: the nested instance reloads the harness hyprland.lua" ok hypr reload config-only
  # A fresh layer can miss the first press under a resting pointer.
  read -r below_x below_y < <(placement_bar_below_left) || fail "control Escape: the point below the bar is unreadable before restart"
  hover "$below_x" "$below_y" || fail "control Escape: resting the pointer below the bar failed"
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-escape-control-restored.log" || fail "the shell starts again after the Escape control"
fi

if copy_tree placement-drag-control \
  && edit_tree placement-drag-control shell/Ui/BarWidget.qml 'root.frame.dragStart(root.dragPoint());' 'return;'; then
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-drag-control" "$sandbox/placement-drag-control.log" || fail "the placement drag control shell starts"
  tick_presses_before="$(ipc smoke readInstance "$(bar_key)" acme.tick presses)" || fail "control: the tick press count is unreadable"
  read -r left_x left_y < <(placement_bar_left_inside) || fail "control: the point in the bar's left third is unreadable"
  placement_drag_widget acme.tick "$left_x" "$left_y" || fail "control: dragging acme.tick into the left third failed"
  expect_poll "control: the pointer still reached acme.tick without frame drag" "$((tick_presses_before + 1))" ipc smoke readInstance "$(bar_key)" acme.tick presses
  expect "control: a BarWidget without frame drag writes nothing for an in-bar drop" unchanged placement_same_as "$placement_saved"
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-drag-control-restored.log" || fail "the shell starts again after the drag control"
fi

if copy_tree placement-clock-zone-control \
  && edit_tree placement-clock-zone-control shell/Core/PluginLogic.js 'var section = x < width / 3 ? "left" : x < 2 * width / 3 ? "center" : "right";' 'var section = "center";'; then
  stop_shell
  cp -- "$sandbox/shell-placement-clock-contract.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-clock-zone-control" "$sandbox/placement-clock-zone-control.log" || fail "the clock zone control starts"
  read -r clock_x clock_y < <(placement_zone_point left) || fail "control: the left clock target is unreadable"
  placement_drag_widget vgs.bar/center-clock "$clock_x" "$clock_y" || fail "control: the clock pointer reaches the left zone"
  expect_poll "control: a forced center target makes the clock zone reader reject left" '{"sections": ["center"], "inside": false}' placement_clock_zone left
  expect_poll "control: clock zone capture is released" default key_submap
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-clock-zone-restored.log" || fail "the shell starts after the clock zone control"
fi

if copy_tree placement-clock-before-control \
  && edit_tree placement-clock-before-control shell/Core/PluginLogic.js 'var before = slot < widgets.length ? clone(widgets[slot].locator) : null;' 'var before = null;'; then
  stop_shell
  cp -- "$sandbox/shell-placement-clock-contract.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-clock-before-control" "$sandbox/placement-clock-before-control.log" || fail "the clock neighbor control starts"
  expect "control: the neighbor starts away from center" ok ipc shell movePluginWidget acme.tick right 0
  read -r clock_x clock_y < <(placement_before vgs.bar/center-clock acme.tick) || fail "control: the point before clock is unreadable"
  placement_drag_widget acme.tick "$clock_x" "$clock_y" || fail "control: the neighbor pointer reaches clock's left"
  geometry expect_poll "control: an ignored neighbor makes the same center-before reader reject the drop" '{"center": ["vgs.bar/center-clock", "acme.tick"], "before": false}' placement_before_clock
  expect_poll "control: clock neighbor capture is released" default key_submap
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-clock-before-restored.log" || fail "the shell starts after the clock neighbor control"
fi

if copy_tree placement-clock-hide-control \
  && edit_tree placement-clock-hide-control shell/Core/Plugins.qml 'hide: () => root.setPlaced(id, false),' 'hide: () => "ok",'; then
  stop_shell
  cp -- "$sandbox/shell-placement-clock-contract.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-clock-hide-control" "$sandbox/placement-clock-hide-control.log" || fail "the clock Hide control starts"
  placement_clock_hide_menu || fail "control: the real clock menu executes"
  expect_poll "control: an inert shared Hide callback makes the same removal reader reject it" '{"placed": true, "built": true, "ownerEnabled": true, "settingsKept": true}' placement_clock_hidden
  expect_poll "control: clock Hide capture is released" default key_submap
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-clock-hide-restored.log" || fail "the shell starts after the clock Hide control"
fi

# Each control invokes the drawn field's keyboard path, not a manager substitute.
if copy_tree placement-builtin-field-control \
  && edit_tree placement-builtin-field-control shell/plugins/vgs.settings/Window.qml 'return keep(pageId, shell.manager.setPlaced(id, placed));' 'return "ok";'; then
  stop_shell
  cp -- "$sandbox/shell-placement-clock-contract.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-builtin-field-control" "$sandbox/placement-builtin-field-control.log" || fail "the builtin field control starts"
  expect "control: the clock leaves its ordinary entry" ok ipc shell setPluginPlaced vgs.bar/center-clock false
  cp -- "$placement_file" "$sandbox/shell-before-builtin-field.json"
  expect "control: Settings opens the hidden builtin field" ok ipc shell summon window vgs.settings '{"plugin":"vgs.bar"}'
  expect_poll "control: the hidden clock switch remains available" '{"type":"boolean","value":false,"checked":false,"enabled":true}' placement_builtin_field vgs.bar/center-clock
  placement_builtin_toggle vgs.bar/center-clock || fail "control: the real field receives Space"
  expect_poll "control: an inert field callback makes the restore reader reject it" '{"sections": [], "otherStateKept": true}' placement_builtin_saved vgs.bar/center-clock
  expect "control: a refused restore keeps the checked value bound" '{"type":"boolean","value":false,"checked":false,"enabled":true}' placement_builtin_field vgs.bar/center-clock
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-builtin-field-restored.log" || fail "the shell starts after the field control"
fi
if copy_tree placement-builtin-catalogue-control \
  && edit_tree placement-builtin-catalogue-control shell/Core/Plugins.qml 'return bar.builtinNames.map(name => ({' 'return bar.builtinNames.filter(name => Logic.layoutPositionOf(Config.effective, id + "/" + name, null) !== null).map(name => ({'; then
  stop_shell
  cp -- "$sandbox/shell-placement-clock-contract.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-builtin-catalogue-control" "$sandbox/placement-builtin-catalogue-control.log" || fail "the catalogue control starts"
  expect "control: the clock leaves its ordinary entry" ok ipc shell setPluginPlaced vgs.bar/center-clock false
  expect "control: Settings opens the catalogue with the hidden clock" ok ipc shell summon window vgs.settings '{"plugin":"vgs.bar"}'
  expect_poll "control: placement-dependent discovery loses the hidden clock field" absent placement_builtin_field vgs.bar/center-clock
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-builtin-catalogue-restored.log" || fail "the shell starts after the catalogue control"
fi
if copy_tree placement-builtin-default-control \
  && edit_tree placement-builtin-default-control shell/Core/Plugins.qml 'Config.effective, id, Config.shipped));' 'Config.effective, id));'; then
  stop_shell
  cp -- "$sandbox/shell-placement-clock-contract.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-builtin-default-control" "$sandbox/placement-builtin-default-control.log" || fail "the default placement control starts"
  expect "control: workspaces leaves its ordinary entry" ok ipc shell setPluginPlaced vgs.bar/left-workspaces false
  cp -- "$placement_file" "$sandbox/shell-before-builtin-field.json"
  expect "control: Settings opens the workspace field" ok ipc shell summon window vgs.settings '{"plugin":"vgs.bar"}'
  expect_poll "control: the workspace field starts unchecked" '{"type":"boolean","value":false,"checked":false,"enabled":true}' placement_builtin_field vgs.bar/left-workspaces
  placement_builtin_toggle vgs.bar/left-workspaces || fail "control: the workspace switch executes"
  expect_poll "control: missing shipped defaults makes the same section reader reject restore" '{"sections": ["center"], "otherStateKept": true}' placement_builtin_saved vgs.bar/left-workspaces
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-builtin-default-restored.log" || fail "the shell starts after the default placement control"
fi
if copy_tree placement-builtin-confirm-control \
  && edit_tree placement-builtin-confirm-control shell/Ui/BarWidget.qml 'if (root.frame.describe().builtin) {' 'if (false) {'; then
  stop_shell
  cp -- "$sandbox/shell-placement-clock-contract.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-builtin-confirm-control" "$sandbox/placement-builtin-confirm-control.log" || fail "the confirmation control starts"
  placement_clock_hide_menu || fail "control: the actual Hide menu executes"
  expect_poll "control: a confirmation leaves the clock placed" '{"placed": true, "built": true, "ownerEnabled": true, "settingsKept": true}' placement_clock_hidden
  expect_poll "control: the confirmation reader rejects direct Hide" true ipc smoke readInstance "$(bar_key)" vgs.bar/center-clock frameDialogOpen
  type_keys -k Escape
  expect_poll "control: Escape releases confirmation capture" default key_submap
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-builtin-confirm-restored.log" || fail "the shell starts after the confirmation control"
fi

# A real ordinary plugin can share a catalogue suffix after the bar prefix's
# length. Removing the bar's own prefix filter must create an unwanted clock.
placement_foreign_builtin_state() {
  ipc shell built | py_reply 'import json,sys; bars=[rows for host,rows in json.load(sys.stdin).items() if host.startswith("bar:")]; states={(any(r.get("id")=="vgs.bar/center-clock" for r in rows),any(r.get("id")=="acme.xyzcenter-clock" for r in rows)) for rows in bars}; print(json.dumps(sorted(states)) if bars else "absent")'
}
cp -- "$placement_file" "$sandbox/shell-placement-catalogue-entry.json"
install_plugin_copy acme.tick acme.xyzcenter-clock "Catalogue suffix fixture"
rescan "the private catalogue suffix plugin is discovered"
expect_poll "the private catalogue suffix fixture is enabled" True plugin_enabled acme.xyzcenter-clock
expect "the real clock is removed before the foreign catalogue read" ok ipc shell setPluginPlaced vgs.bar/center-clock false
expect_poll "the bar rejects a foreign ID with its clock suffix" '[[false, true]]' placement_foreign_builtin_state
cp -- "$placement_file" "$sandbox/shell-placement-catalogue-settled.json"
if copy_tree placement-catalogue-control \
  && edit_tree placement-catalogue-control shell/plugins/vgs.bar/Bar.qml '.filter(entry => shell !== null && entry.id.indexOf(shell.manifest.id + "/") === 0)' '.filter(entry => true)'; then
  stop_shell
  start_shell "$sandbox/tree-placement-catalogue-control" "$sandbox/placement-catalogue-control.log" || fail "the independent bar catalogue control starts"
  expect_poll "control: removing the bar prefix filter makes its registration reader reject the foreign ID" '[[true, true]]' placement_foreign_builtin_state
fi
stop_shell
rm -rf -- "$home/.config/vgshell/plugins/acme.xyzcenter-clock"
cp -- "$sandbox/shell-placement-catalogue-entry.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
start_shell "$repo" "$sandbox/placement-catalogue-restored.log" || fail "the shell starts after the independent catalogue control"
expect_builtins "the full settled profile restores its builtin registrations" '["vgs.bar/center-clock","vgs.bar/left-workspaces"]'

if copy_tree placement-rebuild-control \
  && edit_tree placement-rebuild-control shell/Core/Plugins.qml 'if (at !== -1) {' 'if (false) {' \
  && edit_tree placement-rebuild-control shell/plugins/vgs.bar/Bar.qml 'const names = JSON.parse(key);' 'const names = JSON.parse(key); model.clear();'; then
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-rebuild-control" "$sandbox/placement-rebuild-control.log" || fail "the rebuild control shell starts"
  expect_poll "control: the fixture is mounted before its snapshot" '[true]' placement_in_bars
  expect "control: the identity snapshot includes the widgets" '["acme.probe","acme.tick","vgs.bar/center-clock","vgs.bar/left-workspaces"]' ipc smoke rememberBarWidgets "$(bar_key)"
  read -r tick_x tick_y < <(placement_before acme.tick acme.probe) || fail "control: the target point is unreadable"
  placement_drag_widget acme.probe "$tick_x" "$tick_y" || fail "control: the pointer drop completes"
  expect_poll "control: the rebuild still commits the same order" "$placement_want_before" placement_order
  expect "control: restoring the rebuild makes the object check red" '["acme.probe","acme.tick"]' ipc smoke barWidgetIdentities
  expect "control: the identity snapshot is released" ok ipc smoke forgetBarWidgets
  expect "control: clock moves into left with the same ID" ok ipc shell movePluginWidget vgs.bar/center-clock left 0
  expect_builtins "control: both builtin IDs remain registered" '["vgs.bar/center-clock","vgs.bar/left-workspaces"]'
  expect "control: the builtin identity snapshot includes both widgets" '["acme.probe","acme.tick","vgs.bar/center-clock","vgs.bar/left-workspaces"]' ipc smoke rememberBarWidgets "$(bar_key)"
  expect "control: workspaces moves before clock" ok ipc shell movePluginWidget vgs.bar/left-workspaces left 0
  geometry expect_poll "control: the rebuild still reorders the builtins" True placement_left_builtin_order
  expect "control: rebuilding builtin delegates makes the object check red" '["acme.probe","acme.tick","vgs.bar/center-clock","vgs.bar/left-workspaces"]' ipc smoke barWidgetIdentities
  expect "control: the builtin snapshot is released" ok ipc smoke forgetBarWidgets
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-rebuild-restored.log" || fail "the shell starts after the rebuild control"
fi

cp -- "$sandbox/shell-placement-entry.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
expect_poll "the restored user file places the fixture again" '[true, true]' placement_listed acme.probe
expect_poll "the restored fixture widget is in every bar" '[true]' placement_in_bars
