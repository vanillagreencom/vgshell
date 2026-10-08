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

placement_preview_slot() { ipc smoke barDragGeometry "$(bar_key)" | py_reply 'import json,sys; state=json.load(sys.stdin); print(json.dumps([state["section"],state["index"]]) if isinstance(state,dict) else "absent")'; }
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
  local x y tx ty before_x barrier out_fd in_fd hold_pid
  read -r x y < <(placement_point acme.probe) || return 1
  read -r tx ty < <(placement_before acme.tick acme.probe) || return 1
  before_x="$(ipc smoke instanceGeometry "$(bar_key)" acme.tick | py_reply 'import json,sys; print(json.load(sys.stdin)[0])')" || return 1
  expect "the identity snapshot includes built-ins and mounted widgets" '["acme.probe","acme.tick","vgs.bar/center-clock","vgs.bar/left-workspaces"]' ipc smoke rememberBarWidgets "$(bar_key)"
  hover "$((x + 1))" "$y" || return 1
  coproc placement_preview { "${shell_env[@]}" "$sandbox/click" "$x" "$y" "$mon_w" "$mon_h" drag "$tx" "$ty" hold; }
  out_fd="${placement_preview[0]}" in_fd="${placement_preview[1]}" hold_pid="$placement_preview_PID"
  read -r -t 10 barrier <&"$out_fd" || return 1
  [[ $barrier == "holding $tx $ty" ]] || return 1
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
placement_held_preview || fail "the held preview press completes"
expect "the fixture returns to right before the other pointer checks" ok ipc shell movePluginWidget acme.probe right 0
expect_poll "the fixture is back in right" "$placement_want_right" placement_order
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

if copy_tree placement-rebuild-control \
  && edit_tree placement-rebuild-control shell/Core/Plugins.qml 'if (at !== -1) {' 'if (false) {'; then
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
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-rebuild-restored.log" || fail "the shell starts after the rebuild control"
fi

cp -- "$sandbox/shell-placement-entry.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
expect_poll "the restored user file places the fixture again" '[true, true]' placement_listed acme.probe
expect_poll "the restored fixture widget is in every bar" '[true]' placement_in_bars
