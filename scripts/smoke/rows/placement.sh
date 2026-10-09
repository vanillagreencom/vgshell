# Show in bar and bar reorder: setPluginPlaced takes a widget off the bar
# and puts it back in its default section and never writes disabledPlugins.
# movePluginWidget moves the same layout entry between section lists and
# positions. The bar's shared widget frame starts a drag only after pointer
# motion and keeps right-click Hide. Over the installed fixture acme.probe,
# a service plus a bar widget that rows/plugins.sh enabled and placed, each
# call is read back from the bar's build records, the user shell.json,
# listPlugins and the service's build record. Pointer checks drag real
# widgets, cancel with Escape, prove a still click stays a click, and prove
# a drag cancels the widget's own click. Outside the bar a drag goes on: a
# drag out and back drops where it returns, a release just inside one bar
# height of the bar drops at the slot nearest along the bar, also with a
# window holding the keyboard, Escape on a drag held far below writes
# nothing, a drag held far below draws the widget inside the bar at the
# pointer's x, and a release just past that line asks to remove the widget,
# with Cancel focused and no focus ring; Cancel and Escape put it back and
# write nothing, and Remove leaves it unplaced as Hide does. After a drop
# on an empty workspace, and after the question closes, the bar holds no
# keyboard. Controls run a copy whose move ignores the index, a copy whose
# drag capture is missing, a copy whose BarWidget cannot drag, a copy that
# draws the held widget at the pointer's y, a copy with the old cancel of
# a release outside the bar, a copy whose grab leaves the bar's keyboard
# interactivity alone, a copy with neither the focus grab nor that step,
# and a copy whose remove question takes the keyboard's focus reason once
# its window is active. A copy whose neighbours slide for a minute must
# still pick the slot before the plugin neighbour, and that copy reading
# the neighbours' drawn boxes picks the slot after it. Over a left zone
# crowded with separators, a drag held at the zone's end reaches the
# section's last slot and drops there, one held at its start reaches the
# slot before the workspaces, and a drag that left the end steps the zone
# no further. Controls run a copy whose hold timer never runs, a copy whose
# zone slides for a minute, which must still reach the last slot and still
# slide then, that copy reading the section's drawn place, that copy ending
# its slide on every scroll change, and a copy that keeps the end the drag
# once stood past. The row restores the
# user file byte for byte, so rows after it find the fixture placed as
# before. The disabled widget the refusals name is acme.tick, disabled for
# them and enabled again.
# inputs: shell/plugins/vgs.bar/* config/shell.json scripts/smoke/fixtures/plugins/acme.probe/* scripts/smoke/fixtures/plugins/acme.tick/* shell/plugins/vgs.settings/* shell/Commons/Reply.js shell/Core/PluginLogic.js shell/Core/Plugins.qml shell/Core/Registry.qml shell/Core/Capabilities.qml shell/Core/Config.qml shell/Core/KeyCapture.qml shell/Core/HyprlandLayer.js shell/Core/Compositor.qml shell/Core/Dispatch.js shell/Hosts/BarHost.qml shell/shell.qml shell/Ui/BarWidget.qml shell/Ui/feedback/Dialog.qml shell/Ui/controls/Button.qml shell/Commons/Theme.qml shell/Ui/overlay/Menu.qml shell/Ui/overlay/MenuItem.qml shell/Ui/overlay/DismissScope.qml scripts/smoke/pointer/click.c scripts/smoke/fixtures/plugins/acme.bare/* scripts/smoke/rows/plugins.sh scripts/smoke/rows/manager.sh scripts/smoke/rows/settings.sh scripts/smoke/rows/sources.sh scripts/smoke/rows/hyprland-consent.sh scripts/smoke/rows/capabilities.sh shell/Commons/Tokens.js
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
# A point half a bar height below the bar, under widget ID's centre.
placement_below() {
  local x y
  read -r x y < <(placement_point "$1") || return 1
  surface_box vgs:bar | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print("%d %d" % (int(sys.argv[1]), y + h + h / 2))' "$x"
}
placement_bar_left_inside() {
  surface_box vgs:bar | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print("%d %d" % (x + w / 6, y + h / 2))'
}
# Below the left third of the bar, on either side of the line
# Plugins.dragEnd draws one bar height outside it: 4 px short of it is near
# and drops, 4 px past it is far and asks.
placement_bar_below_left() {
  surface_box vgs:bar | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print("%d %d" % (x + w / 6, y + h + h - 4))'
}
placement_bar_far_left() {
  surface_box vgs:bar | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print("%d %d" % (x + w / 6, y + h + h + 4))'
}
# The key capture's begin count, and `released` once a capture begun after
# SINCE has ended: a bar drag's capture ends at its release or cancel, after
# which the drop has written or the cancel has written nothing.
# `left` once the bar's window no longer holds the keyboard, polled as
# expect_poll polls, or `kept` at the bound: the drag's focus grab hands the
# bar the keyboard until the release.
placement_keyboard_left() {
  local at
  smoke_poll_tries 200 1
  for _ in $(seq 1 "$smoke_poll_n"); do
    at="$(ipc smoke windowFocused "$(bar_key)" acme.probe)" || return 1
    [[ $at == false ]] && { echo left; return; }
    sleep 0.2
  done
  echo kept
}
placement_capture_generation() { ipc smoke keyCaptureState | py_reply 'import json,sys; print(json.load(sys.stdin)[0])'; }
placement_capture_released() { ipc smoke keyCaptureState | py_reply 'import json,sys; g,c=json.load(sys.stdin); print("released" if g > int(sys.argv[1]) and not c else "held")' "$1"; }
# placement_drag_path ID X Y [X Y ...]: a real drag from widget ID's centre
# that first moves inside the bar, so the drag starts there, then passes
# each point and releases at the last.
placement_drag_path() {
  local id="$1" x y
  shift
  read -r x y < <(placement_point "$id") || return 1
  hover "$((x + 1))" "$y" || return 1
  "${shell_env[@]}" "$sandbox/click" "$x" "$y" "$mon_w" "$mon_h" drag "$((x - 24))" "$y" "$@" >/dev/null || return 1
  pointer_at="${*: -2:1} ${*: -1}"
}
# The open remove question of the fixture: the dialog shows its Remove
# action, and the held widget sits over the gap of the slot it previewed.
placement_asking() {
  local remove drag
  remove="$(ipc smoke popupItemGeometry "$(bar_key)" acme.probe "" "" Button Remove)" || return 1
  drag="$(ipc smoke barDragGeometry "$(bar_key)")" || return 1
  py_reply 'import json,sys; raw=sys.stdin.read().strip(); d=json.loads(raw) if raw.startswith("{") else None; over=d is not None and abs(d["item"][0]-d["gap"][0])<=1 and abs(d["item"][1]-d["gap"][1])<=1; print(json.dumps({"remove": sys.argv[1].startswith("["), "overGap": over}))' "$remove" <<<"$drag"
}
# placement_held_far LABEL WANT: a drag of the fixture held far below the
# bar, whose held box reads {inside, atPointer}: inside the bar's box, and
# its centre at the pointer's x, as WANT; then its release asks, and
# Escape closes the question.
placement_held_box() {
  local bar drag
  bar="$(surface_box vgs:bar)" || return 1
  drag="$(ipc smoke barDragGeometry "$(bar_key)")" || return 1
  py_reply 'import json,sys; raw=sys.stdin.read().strip(); d=json.loads(raw) if raw.startswith("{") else None; b=json.loads(sys.argv[1]); x=float(sys.argv[2])
if d is None: print("absent"); sys.exit()
i=d["item"]; print(json.dumps({"inside": i[1] >= 0 and i[1]+i[3] <= b[3], "atPointer": abs(i[0]+i[2]/2-x) <= 1}))' "$bar" "$1" <<<"$drag"
}
placement_held_far() {
  local label="$1" want="$2" x y far_x far_y line out_fd in_fd pid
  read -r x y < <(placement_point acme.probe) || return 1
  read -r far_x far_y < <(placement_bar_far_left) || return 1
  hover "$((x + 1))" "$y" || return 1
  coproc placement_far { "${shell_env[@]}" "$sandbox/click" "$x" "$y" "$mon_w" "$mon_h" drag "$((x - 24))" "$y" "$far_x" "$far_y" hold; }
  out_fd="${placement_far[0]}" in_fd="${placement_far[1]}" pid="$placement_far_PID"
  read -r -t 10 line <&"$out_fd" || return 1
  [[ $line == "holding $far_x $far_y" ]] || return 1
  geometry expect_poll "$label" "$want" placement_held_box "$far_x"
  printf '\n' >&"$in_fd"
  exec {in_fd}>&-
  read -r -t 10 line <&"$out_fd" || return 1
  wait "$pid" || return 1
  exec {out_fd}<&-
  pointer_at="$far_x $far_y"
  expect_poll "the held far release asks to remove the fixture" true ipc smoke readInstance "$(bar_key)" acme.probe frameDialogOpen
  type_keys -k Escape || return 1
  expect_poll "Escape closes the held far release's question" false ipc smoke readInstance "$(bar_key)" acme.probe frameDialogOpen
}
# placement_far_ask: a drag of the fixture released far below the bar,
# then the remove question it opens.
placement_far_ask() {
  local far_x far_y
  read -r far_x far_y < <(placement_bar_far_left) || return 1
  placement_drag_path acme.probe "$far_x" "$far_y" || return 1
  expect_poll "a release far below the bar asks to remove the fixture" true ipc smoke readInstance "$(bar_key)" acme.probe frameDialogOpen
  expect_poll "the remove question shows Remove over the held widget" '{"remove": true, "overGap": true}' placement_asking
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
# PATH `stepped` holds the drag just inside the centre third until the
# preview stands there, then sends the one motion to the target, so that
# motion reads neighbours the gap has displaced, whatever the shell's pace.
# WANT is the slot the preview must name under the name SLOT; LABEL starts
# every other check's name.
placement_held_builtin() { # PATH WANT SLOT LABEL
  local path="$1" want="$2" slot="$3" label="$4" x y tx ty px barrier out_fd in_fd hold_pid
  read -r x y < <(placement_point vgs.bar/left-workspaces) || return 1
  # One pixel left of the tick's left edge: a slot comes from the
  # neighbours' shifted boxes (Plugins.dragMove), and whether the preview
  # stands before the clock or before the tick, this point lies past the
  # clock's middle and short of the tick's, so it reads before the tick
  # whatever path the pointer took.
  read -r tx ty < <(placement_point acme.tick) || return 1
  tx="$(ipc smoke instanceGeometry "$(bar_key)" acme.tick | py_reply 'import json,sys; print(int(json.load(sys.stdin)[0]) - 1)')" || return 1
  px="$tx"
  if [[ $path == stepped ]]; then
    px="$(surface_box vgs:bar | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print(int(x+w/3)+2)')" || return 1
  fi
  expect "${label}the builtin drag snapshot includes all widgets" '["acme.probe","acme.tick","vgs.bar/center-clock","vgs.bar/left-workspaces"]' ipc smoke rememberBarWidgets "$(bar_key)"
  hover "$((x + 1))" "$y" || return 1
  coproc builtin_hold { "${shell_env[@]}" "$sandbox/click" "$x" "$y" "$mon_w" "$mon_h" drag "$px" "$ty" hold; }
  out_fd="${builtin_hold[0]}" in_fd="${builtin_hold[1]}" hold_pid="$builtin_hold_PID"
  read -r -t 10 barrier <&"$out_fd" || return 1
  [[ $barrier == "holding $px $ty" ]] || return 1
  if [[ $path == stepped ]]; then
    expect_poll "${label}the builtin preview enters the centre before the clock" '["center", 0]' placement_preview_slot
    hover "$tx" "$ty" || return 1
  fi
  expect_poll "${label}the builtin drag holds keyboard capture" vgs:passthrough key_submap
  expect "${label}the builtin's press stays held across visual section transfer" true ipc smoke readInstance "$(bar_key)" vgs.bar/left-workspaces frameDragging
  expect "${label}the held builtin preview keeps every widget object" '[]' ipc smoke barWidgetIdentities
  # The last motion publishes the slot, and no later one changes it.
  expect_poll "$slot" "$want" placement_preview_slot
  printf '\n' >&"$in_fd"
  exec {in_fd}>&-
  read -r -t 10 barrier <&"$out_fd" || return 1
  wait "$hold_pid" || return 1
  exec {out_fd}<&-
  pointer_at="$tx $ty"
  expect_poll "${label}the builtin pointer drop persists its new section" '["center"]' placement_builtin_section vgs.bar/left-workspaces
  expect "${label}the builtin pointer drop keeps every object" '[]' ipc smoke barWidgetIdentities
  expect_poll "${label}the builtin drop releases keyboard capture" default key_submap
  expect "${label}the builtin drag snapshot is released" ok ipc smoke forgetBarWidgets
}
placement_preview_slot() { ipc smoke barDragGeometry "$(bar_key)" | py_reply 'import json,sys; state=json.load(sys.stdin); print(json.dumps([state["section"],state["index"]]) if isinstance(state,dict) else "absent")'; }
placement_held_builtin paced '["center", 1]' "the builtin preview selects before its plugin neighbour" "" || fail "the builtin held pointer move completes"
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
# Outside the bar the drag goes on. Near the bar a release drops at the
# slot nearest the pointer along the bar; far from it the release asks to
# remove the widget, and only Remove changes the file.
placement_near_drop() {
  read -r below_x below_y < <(placement_bar_below_left) || fail "the point below the left third of the bar is unreadable"
  placement_drag_path acme.probe "$below_x" "$below_y" || fail "dragging the fixture below the bar failed"
}
expect "no window holds the keyboard for the empty-workspace drop" '[]' active_window
placement_near_drop
expect_poll "a drag released near below the bar's left third drops after workspaces in the file" "$placement_want_pointer_left" placement_order
geometry expect_poll "a drag released near below the bar's left third draws the fixture after workspaces" "$placement_drawn_pointer_left" placement_visual_order
expect_poll "the near drop releases keyboard capture" default key_submap
expect "the bar gives the keyboard back after an empty-workspace drop" left placement_keyboard_left
expect "the outside snapshot includes every widget" '["acme.probe","acme.tick","vgs.bar/center-clock","vgs.bar/left-workspaces"]' ipc smoke rememberBarWidgets "$(bar_key)"
placement_leave_return() {
  read -r far_x far_y < <(placement_bar_far_left) || fail "the point far below the bar is unreadable"
  read -r tick_x tick_y < <(placement_before acme.tick acme.probe) || fail "the point before tick is unreadable"
  placement_drag_path acme.probe "$far_x" "$far_y" "$tick_x" "$tick_y" || fail "the drag out of the bar and back failed"
}
expect "no window holds the keyboard for the empty-workspace drag out and back" '[]' active_window
placement_leave_return
expect_poll "a drag that leaves the bar and returns drops before tick in the file" "$placement_want_before" placement_order
geometry expect_poll "a drag that leaves the bar and returns draws the fixture before tick" "$placement_drawn_before" placement_visual_order
expect "the remove question is not open after a drop" false ipc smoke readInstance "$(bar_key)" acme.probe frameDialogOpen
cp -- "$placement_file" "$sandbox/shell-before-outside-drop.json"
placement_far_ask
expect_poll "the remove question opens with Cancel focused" '["Button","Cancel",false]' ipc smoke popupFocus "$(bar_key)" acme.probe
expect "the remove question writes nothing while it asks" unchanged placement_same_as "$sandbox/shell-before-outside-drop.json"
expect_poll "the far release releases keyboard capture" default key_submap
type_keys -k Return || fail "Return on the remove question failed"
expect_poll "Return on the focused Cancel closes the remove question" false ipc smoke readInstance "$(bar_key)" acme.probe frameDialogOpen
expect_poll "Cancel ends the held drag" absent ipc smoke barDragGeometry "$(bar_key)"
expect "the bar gives the keyboard back after the remove question closes" left placement_keyboard_left
expect "Cancel leaves the user file as it was" unchanged placement_same_as "$sandbox/shell-before-outside-drop.json"
geometry expect_poll "Cancel puts the fixture back before tick" "$placement_drawn_before" placement_visual_order
placement_far_ask
type_keys -k Escape || fail "Escape on the remove question failed"
expect_poll "Escape closes the remove question" false ipc smoke readInstance "$(bar_key)" acme.probe frameDialogOpen
expect_poll "Escape ends the held drag" absent ipc smoke barDragGeometry "$(bar_key)"
expect "Escape leaves the user file as it was" unchanged placement_same_as "$sandbox/shell-before-outside-drop.json"
geometry expect_poll "Escape puts the fixture back before tick" "$placement_drawn_before" placement_visual_order
expect "the outside drags keep every widget object" '[]' ipc smoke barWidgetIdentities
expect "the outside snapshot is released" ok ipc smoke forgetBarWidgets
placement_held_far "a drag held far below the bar draws the widget inside the bar at the pointer's x" '{"inside": true, "atPointer": true}' || fail "the drag held far below the bar completes"
expect "the held far drag writes nothing" unchanged placement_same_as "$sandbox/shell-before-outside-drop.json"
placement_far_ask
type_keys -k Tab -k Return || fail "Tab and Return on Remove failed"
expect_poll "Remove ends the held drag" absent ipc smoke barDragGeometry "$(bar_key)"
placement_reads "Remove" false '[]'
expect_poll "Remove releases keyboard capture" default key_submap
expect "Show in bar restores the removed fixture" ok ipc shell setPluginPlaced acme.probe true
placement_reads "the restore after Remove" true '["right"]'
# With a window holding the keyboard, Hyprland keeps the press itself; the
# near drop still lands where the pointer points.
expect "Settings opens and holds the keyboard for the focused-window drop" ok ipc shell summon window vgs.settings '{"plugin":"acme.probe"}'
expect_poll "the Settings window holds the keyboard" true ipc smoke windowFocused window vgs.settings
placement_near_drop
expect_poll "a near drop with a focused window drops after workspaces in the file" "$placement_want_pointer_left" placement_order
expect "Settings closes after the focused-window drop" ok ipc shell hide window vgs.settings
expect "moving the fixture back after the center widget is allowed" ok ipc shell movePluginWidget acme.probe center 2
expect_poll "the fixture is back after the center widget after the outside drags" "$placement_want_after" placement_order
hypr_lua_save placement
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$home/.config/hypr/hyprland.lua"
expect "the nested instance reloads with keysym binds" ok hypr reload config-only
cp -- "$placement_file" "$sandbox/shell-before-escape-drop.json"
read -r tick_x tick_y < <(placement_point acme.tick) || fail "the tick widget point is unreadable before Escape"
placement_drag_escape acme.probe "$tick_x" "$tick_y" vgs:passthrough || fail "holding a drag and pressing Escape failed"
expect_poll "Escape during a drag ends frame dragging after release" false ipc smoke readInstance "$(bar_key)" acme.probe frameDragging
expect_poll "Escape during a drag keeps the rendered order" "$placement_drawn_after" placement_visual_order
expect "Escape during a drag leaves the user file as it was" unchanged placement_same_as "$sandbox/shell-before-escape-drop.json"
read -r far_x far_y < <(placement_bar_far_left) || fail "the point far below the bar is unreadable before Escape"
placement_drag_escape acme.probe "$far_x" "$far_y" vgs:passthrough || fail "holding a drag far below the bar and pressing Escape failed"
expect_poll "Escape on a drag held far below ends frame dragging after release" false ipc smoke readInstance "$(bar_key)" acme.probe frameDragging
expect "Escape on a drag held far below asks nothing" false ipc smoke readInstance "$(bar_key)" acme.probe frameDialogOpen
expect "Escape on a drag held far below leaves the user file as it was" unchanged placement_same_as "$sandbox/shell-before-escape-drop.json"
geometry expect_poll "Escape on a drag held far below keeps the rendered order" "$placement_drawn_after" placement_visual_order
hypr_lua_restore placement || fail "placement puts the harness hyprland.lua back"
expect "the nested instance reloads the harness hyprland.lua" ok hypr reload config-only
tick_clicks_before="$(ipc smoke readInstance "$(bar_key)" acme.tick clicks)" || fail "the tick click count is unreadable"
placement_click_widget acme.tick || fail "clicking acme.tick failed"
expect_poll "a click without movement reaches acme.tick" "$((tick_clicks_before + 1))" ipc smoke readInstance "$(bar_key)" acme.tick clicks
tick_clicks_before="$(ipc smoke readInstance "$(bar_key)" acme.tick clicks)" || fail "the tick click count is unreadable before a drag"
tick_cancels_before="$(ipc smoke readInstance "$(bar_key)" acme.tick cancels)" || fail "the tick cancel count is unreadable before a drag"
cp -- "$placement_file" "$sandbox/shell-before-tick-drag.json"
read -r below_x below_y < <(placement_below acme.tick) || fail "the point below acme.tick is unreadable"
tick_capture="$(placement_capture_generation)" || fail "the key capture count is unreadable before the tick drag"
placement_drag_widget acme.tick "$below_x" "$below_y" || fail "dragging acme.tick failed"
expect_poll "the tick drag's release ends its capture" released placement_capture_released "$tick_capture"
expect "a near drop under acme.tick's own slot writes nothing" unchanged placement_same_as "$sandbox/shell-before-tick-drag.json"
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
  && edit_tree placement-move-control shell/Core/PluginLogic.js 'target.splice(at, 0, entry);' 'target.push(entry);'; then
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
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-move-control-restored.log" || fail "the shell starts again after the move control"
fi

# The cancel this change removed: a release outside the bar's box writes
# nothing, so the near drop reads red.
if copy_tree placement-outside-cancel-control \
  && edit_tree placement-outside-cancel-control shell/Core/Plugins.qml '        if (outside > Theme.bar.height) {' '        if (outside > 0) { cancelBarDrag(); return "none"; }
        if (outside > Theme.bar.height) {'; then
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-outside-cancel-control" "$sandbox/placement-outside-cancel-control.log" || fail "the outside cancel control shell starts"
  expect "control: the fixture starts after the center widget" ok ipc shell movePluginWidget acme.probe center 2
  expect_poll "control: the near drop starts from after the center widget" "$placement_want_after" placement_order
  control_capture="$(placement_capture_generation)" || fail "control: the key capture count is unreadable"
  placement_near_drop
  expect_poll "control: the cancelled near drop's release ends its capture" released placement_capture_released "$control_capture"
  expect "control: the old outside cancel makes the near drop keep the file order" "$placement_want_after" placement_order
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-outside-cancel-restored.log" || fail "the shell starts again after the outside cancel control"
fi

# A held widget drawn at the pointer's y leaves the bar's box below the
# bar, so the inside reading reads red.
if copy_tree placement-ride-control \
  && edit_tree placement-ride-control shell/Core/Plugins.qml 'drag.item.y = Math.max(0, Math.min(mount.row.instance.height - drag.item.height, point.y - drag.offset.y));' 'drag.item.y = point.y - drag.offset.y;'; then
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-ride-control" "$sandbox/placement-ride-control.log" || fail "the ride control shell starts"
  placement_held_far "control: a widget drawn at the pointer's y leaves the bar's box" '{"inside": false, "atPointer": true}' || fail "control: the drag held far below the bar completes"
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-ride-restored.log" || fail "the shell starts again after the ride control"
fi

# A grab that leaves the bar's keyboard interactivity alone leaves the bar
# holding the keyboard after the release on an empty workspace.
if copy_tree placement-keyboard-control \
  && edit_tree placement-keyboard-control shell/Core/Plugins.qml '        barPressGrab.layer.keyboardFocus = WlrKeyboardFocus.OnDemand;' ''; then
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-keyboard-control" "$sandbox/placement-keyboard-control.log" || fail "the keyboard control shell starts"
  expect "control: the fixture starts after the center widget" ok ipc shell movePluginWidget acme.probe center 2
  expect_poll "control: the near drop starts from after the center widget" "$placement_want_after" placement_order
  expect "control: no window holds the keyboard" '[]' active_window
  placement_near_drop
  expect_poll "control: the near drop still lands after workspaces" "$placement_want_pointer_left" placement_order
  expect "control: without the interactivity step the bar keeps the keyboard" kept placement_keyboard_left
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-keyboard-restored.log" || fail "the shell starts again after the keyboard control"
fi

# Without the focus grab and the OnDemand interactivity, either of which
# gives the bar the keyboard that Hyprland's held-button rule asks for,
# Hyprland ends the press at the bar's edge on the sandbox's empty
# workspace, so the drag out and back reads red.
if copy_tree placement-grab-control \
  && edit_tree placement-grab-control shell/Core/Plugins.qml '        barPressGrab.active = true;' '        barPressGrab.active = false;' \
  && edit_tree placement-grab-control shell/Core/Plugins.qml '        barPressGrab.layer.keyboardFocus = WlrKeyboardFocus.OnDemand;' ''; then
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-grab-control" "$sandbox/placement-grab-control.log" || fail "the grab control shell starts"
  expect "control: the fixture starts after workspaces" ok ipc shell movePluginWidget acme.probe left 1
  expect_poll "control: the drag out and back starts after workspaces" "$placement_want_pointer_left" placement_order
  control_capture="$(placement_capture_generation)" || fail "control: the key capture count is unreadable"
  placement_leave_return
  expect_poll "control: the lost press ends its capture" released placement_capture_released "$control_capture"
  control_order="$(placement_order)" || fail "control: the order after the drag out and back is unreadable"
  if [[ $control_order != "$placement_want_before" ]]; then ok "control: without the focus grab the drag out and back reads red"; else fail "control: without the focus grab the drag out and back still dropped before tick"; fi
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-grab-restored.log" || fail "the shell starts again after the grab control"
fi

# A remove question that takes the keyboard's focus reason once its window
# is active draws the ring at open, so the no-ring check reads red.
if copy_tree placement-ring-control \
  && edit_tree placement-ring-control shell/Ui/BarWidget.qml \
    'Qt.callLater(() => dialog.forceActiveFocus(Qt.OtherFocusReason));' \
    'Qt.callLater(() => {
                    dialog.forceActiveFocus(Qt.OtherFocusReason);
                    if (kind === "remove") {
                        const keyboardInitial = () => {
                            if (!dialog.Window.window.active) return;
                            dialog.focusInitial();
                            dialog.buttons()[dialog.focusIndex].focusReason = Qt.TabFocusReason;
                        };
                        dialog.Window.window.activeChanged.connect(keyboardInitial);
                        keyboardInitial();
                    }
                });'; then
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-ring-control" "$sandbox/placement-ring-control.log" || fail "the ring control shell starts"
  placement_far_ask
  expect_poll "control: the keyboard focus reason makes the no-ring reader see the ring" '["Button","Cancel",true]' ipc smoke popupFocus "$(bar_key)" acme.probe
  type_keys -k Escape || fail "control: Escape on the remove question failed"
  expect_poll "control: Escape closes the remove question" false ipc smoke readInstance "$(bar_key)" acme.probe frameDialogOpen
  expect "control: Escape on the remove question writes nothing" unchanged placement_same_as "$placement_saved"
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-ring-restored.log" || fail "the shell starts again after the ring control"
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
  && edit_tree placement-clock-before-control shell/Core/PluginLogic.js 'var before = target !== null ? clone(target.locator) : null;' 'var before = null;'; then
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

# A neighbour slides to its place while a drag is on, and the slot must not
# read how far that slide has come. Both copies slide for a minute, so the
# neighbours still stand where the gap's arrival left them when the last
# motion picks the slot. The second copy reads their drawn boxes.
placement_slide='NumberAnimation { duration: Theme.motion.duration.normal; easing.type: Theme.motion.easing.standard }'
if copy_tree placement-slide \
  && edit_tree placement-slide shell/Ui/BarWidget.qml "$placement_slide" 'NumberAnimation { duration: 60000 }' \
  && copy_tree placement-slide-control \
  && edit_tree placement-slide-control shell/Ui/BarWidget.qml "$placement_slide" 'NumberAnimation { duration: 60000 }' \
  && edit_tree placement-slide-control shell/Core/Plugins.qml 'const x = sectionPoint.x + restX(placed.slice(0, placed.indexOf(entry.widget)), container.spacing);' 'const x = entry.widget.mapToItem(null, 0, 0).x;'; then
  stop_shell
  cp -- "$sandbox/shell-placement-clock-contract.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-slide" "$sandbox/placement-slide.log" || fail "the slow slide copy starts"
  placement_held_builtin stepped '["center", 1]' "slow slide: the builtin preview selects before its plugin neighbour while the neighbours slide" "slow slide: " || fail "the slow slide held pointer move completes"
  stop_shell
  cp -- "$sandbox/shell-placement-clock-contract.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-placement-slide-control" "$sandbox/placement-slide-control.log" || fail "the slide control starts"
  placement_held_builtin stepped '["center", 2]' "control: a slot read from the neighbours' drawn boxes makes the same reader name the slot after the plugin neighbour" "control: " || fail "control: the held pointer move over drawn boxes completes"
  stop_shell
  cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$repo" "$sandbox/placement-slide-restored.log" || fail "the shell starts after the slide control"
fi

# A side zone that does not fit scrolls by whole widgets, and a dragged
# widget held past the widgets it shows steps it there, one widget every
# bar.scroll.hold, with no pointer motion. Separators crowd the left zone
# until five of them do not fit, so the zone rests at its start with a >
# button. placement_edge_zone reads that zone: its view's x and width on
# the screen, the bar's middle line, whether a button shows at each end,
# and whether its scroll has finished drawing.
placement_edge_zone() {
  local key bar zones
  key="$(bar_key)" && bar="$(ipc smoke instanceGeometry "$key" vgs.bar)" \
    && zones="$(ipc smoke itemValues "$key" vgs.bar Zone objectName,x,width,room,moreBefore,moreAfter,scroll,drawnScroll)" || return 1
  py_reply 'import json,sys
bar=json.loads(sys.argv[1]) if sys.argv[1].startswith("[") else None
zone=[z for z in json.load(sys.stdin) if z["objectName"]=="bar-zone-left"]
if bar is None or not zone: print("absent"); sys.exit()
z=zone[0]
print(json.dumps({"x":bar[0]+z["x"],"y":bar[1]+bar[3]/2,"width":z["width"],"room":z["room"],"start":z["moreBefore"],"end":z["moreAfter"],"settled":abs(z["scroll"]-z["drawnScroll"])<0.5}))' "$bar" <<<"$zones"
}
placement_edge_ends() { placement_edge_zone | py_reply 'import json,sys; z=json.load(sys.stdin); print(json.dumps([z["start"],z["end"],z["settled"]]))'; }
# placement_edge_point start|middle|end: a point on the bar's middle line
# two pixels inside that end of the left zone's view, past every shown
# widget's middle, or at the view's middle.
placement_edge_point() {
  placement_edge_zone | py_reply 'import json,sys; z=json.load(sys.stdin); print("%d %d" % ({"start":z["x"]+2,"middle":z["x"]+z["width"]/2,"end":z["x"]+z["width"]-2}[sys.argv[1]],z["y"]))' "$1"
}
# The separators that leave five outside the left zone's room, from the
# room its widgets leave now and a separator's width with the bar's gap.
placement_edge_count() {
  local inset line gap
  inset="$(ipc smoke themeValue bar.spacer.inset)" && line="$(ipc smoke themeValue divider.thickness)" && gap="$(ipc smoke themeValue bar.gap)" || return 1
  placement_edge_zone | py_reply 'import json,sys; z=json.load(sys.stdin); inset,line,gap=(float(v) for v in sys.argv[1:]); print(int((z["room"]-z["width"])//(2*inset+line+gap))+5)' "$inset" "$line" "$gap"
}
# placement_edge_plant COUNT: COUNT separators after the user file's left
# entries, under names no entry holds.
placement_edge_plant() {
  python3 -c 'import json,os,sys
path,count=sys.argv[1],int(sys.argv[2]); config=json.load(open(path)); layout=config["bar"]["layout"]
held={e["id"] for s in layout.values() for e in s}
free=[i for i in ("vgs.bar/separator-%d" % n for n in range(1,count+len(held)+1)) if i not in held][:count]
layout["left"]+=[{"id":i} for i in free]
with open(path+".tmp","w") as out: json.dump(config,out)
os.replace(path+".tmp",path)' "$placement_file" "$1"
}
# The left section's slot before the workspaces and its last slot, as
# Plugins.dragMove counts them: over the entries without the fixture.
placement_edge_slots() {
  ipc shell listShellConfig | py_reply 'import json,sys; left=[e["id"] for e in json.load(sys.stdin)["bar"]["layout"]["left"] if e["id"]!="acme.probe"]; print("%d %d" % (left.index("vgs.bar/left-workspaces"),len(left)))'
}
# placement_edge_hold X: a held drag of the fixture from its centre to the
# left zone's middle, then to X on the bar's middle line, and no motion
# after it. The preview gap widens the centre section while it stands
# there, which narrows the zone's room; from the zone's middle the gap
# stands in the left section and the zone's end is where
# placement_edge_point read it. The drag's pipes are placement_edge_out
# and placement_edge_in and its pid placement_edge_pid.
placement_edge_hold() {
  local x y mx line
  read -r x y < <(placement_point acme.probe) && read -r mx _ < <(placement_edge_point middle) || return 1
  hover "$((x + 1))" "$y" || return 1
  placement_edge_to="$1 $y"
  coproc placement_edge_press { "${shell_env[@]}" "$sandbox/click" "$x" "$y" "$mon_w" "$mon_h" drag "$mx" "$y" "$1" "$y" hold; }
  placement_edge_out="${placement_edge_press[0]}" placement_edge_in="${placement_edge_press[1]}" placement_edge_pid="$placement_edge_press_PID"
  read -r -t 10 line <&"$placement_edge_out" && [[ $line == "holding $1 $y" ]]
}
placement_edge_release() {
  local line status=0
  printf '\n' >&"$placement_edge_in" || status=1
  exec {placement_edge_in}>&-
  read -r -t 10 line <&"$placement_edge_out" || status=1
  wait "$placement_edge_pid" || status=1
  exec {placement_edge_out}<&-
  pointer_at="$placement_edge_to"
  return "$status"
}
# placement_edge_reach SLOT DEPTH: `reached` once the held drag's preview
# names the left section's SLOT, polled as expect_poll polls under
# smoke_poll_tries' DEPTH; at the bound `short` for a preview on another
# slot of the left section, else `elsewhere`.
placement_edge_reach() {
  local got
  smoke_poll_tries 200 "$2"
  for _ in $(seq 1 "$smoke_poll_n"); do
    got="$(placement_preview_slot)" || return 1
    [[ $got == "[\"left\", $1]" ]] && { echo reached; return; }
    sleep 0.2
  done
  if [[ $got == "[\"left\", "* ]]; then echo short; else echo elsewhere; fi
}
# placement_edge_scrolls start|end DEPTH: True once the left zone shows no
# button at that end, having scrolled all the way there, or False at the
# bound smoke_poll_tries gives DEPTH.
placement_edge_scrolls() {
  local got
  smoke_poll_tries 200 "$2"
  for _ in $(seq 1 "$smoke_poll_n"); do
    got="$(placement_edge_zone | py_reply 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1")" || return 1
    [[ $got == False ]] && { echo True; return; }
    sleep 0.2
  done
  echo False
}
# Where the user file's left section holds the fixture: `last`, `first`
# right before the workspaces, `inner` anywhere else in it, or `away`.
placement_edge_dropped() {
  python3 -c 'import json,sys; left=[e["id"] for e in json.load(open(sys.argv[1]))["bar"]["layout"]["left"]]
at=left.index("acme.probe") if "acme.probe" in left else -1
print("away" if at<0 else "last" if at==len(left)-1 else "first" if left[at+1]=="vgs.bar/left-workspaces" else "inner")' "$placement_file"
}
# placement_edge_held END SLOT DEPTH REACH LABEL: the fixture held at the
# left zone's END, start or end; LABEL holds when the preview reads REACH
# for the left section's SLOT. Then the release.
placement_edge_held() {
  local x y
  read -r x y < <(placement_edge_point "$1") || { fail "$5: the left zone's $1 is unreadable"; return; }
  placement_edge_hold "$x" || { fail "$5: the held drag reaches the left zone's $1"; return; }
  expect "$5" "$4" placement_edge_reach "$2" "$3"
  placement_edge_release || fail "$5: the held drag releases"
  expect_poll "$5: the release leaves rearrange mode" absent ipc smoke barDragGeometry "$(bar_key)"
}
# placement_edge_leave DEPTH WANT LABEL: the fixture held at the left
# zone's end, then moved to the zone's middle and held there; LABEL holds
# when the zone reads WANT for having scrolled to its end. Then the release.
placement_edge_leave() {
  local x y mx my
  read -r x y < <(placement_edge_point end) && read -r mx my < <(placement_edge_point middle) || { fail "$3: the left zone is unreadable"; return; }
  placement_edge_hold "$x" && hover "$mx" "$my" || { fail "$3: the held drag leaves the left zone's end"; return; }
  placement_edge_to="$mx $my"
  expect "$3" "$2" placement_edge_scrolls end "$1"
  placement_edge_release || fail "$3: the held drag releases"
  expect_poll "$3: the release leaves rearrange mode" absent ipc smoke barDragGeometry "$(bar_key)"
}
# placement_edge_start NAME: the shell from the copy NAME over the crowded
# layout, its left zone at rest.
placement_edge_start() {
  stop_shell
  cp -- "$sandbox/shell-placement-edge.json" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
  start_shell "$sandbox/tree-$1" "$sandbox/$1.log" || { fail "the $1 copy starts"; return 1; }
  geometry expect_poll "$1: the crowded left zone rests at its start" '[false, true, true]' placement_edge_ends
}
placement_edge_separators="$(placement_edge_count)" || fail "the left zone's room is unreadable"
placement_edge_plant "$placement_edge_separators" || fail "the separators are planted in the left section"
cp -- "$placement_file" "$sandbox/shell-placement-edge.json"
geometry expect_poll "the crowded left zone clips and rests at its start" '[false, true, true]' placement_edge_ends
read -r placement_edge_first placement_edge_last < <(placement_edge_slots) || fail "the left section's slots are unreadable"
placement_edge_held end "$placement_edge_last" 1 reached "a drag held at the clipped zone's end reaches the left section's last slot"
expect_poll "the release at the end lands the fixture last in the left section" last placement_edge_dropped
geometry expect_poll "the held drag left the zone at its end" '[true, false, true]' placement_edge_ends
# The fixture is now the zone's last widget; held at the < button it
# steps the zone back to its start.
placement_edge_held start "$placement_edge_first" 1 reached "a drag held at the clipped zone's start reaches the slot before the workspaces"
expect_poll "the release at the start lands the fixture before the workspaces" first placement_edge_dropped
geometry expect_poll "the held drag left the zone at its start" '[false, true, true]' placement_edge_ends
placement_edge_leave 0 False "a drag that left the zone's end steps the zone no further"
# Controls. A copy whose hold timer never runs stays on the slot the last
# motion picked and drops there. A copy whose zone slides for a minute
# still reaches the last slot, since each step reads the slot from where
# the section settles, and its zone is still sliding then: the preview
# gap's moves end no slide. That copy reading the section's drawn place
# stops short of the last slot, and that copy ending its slide on every
# scroll change stands settled. A copy that keeps the end it once stood
# past steps on after the drag has left it.
placement_edge_slide='            duration: Theme.motion.duration.normal'
placement_edge_settled='const sectionPoint = scrolled ? container.parent.mapToItem(null, container.settledX, 0) : drawn;'
placement_edge_read='edge: barDragEdge(barDrag.gap.parent, point.x) });'
if copy_tree placement-edge-control \
  && edit_tree placement-edge-control shell/Core/Plugins.qml 'running: root.barDrag !== null && root.barDrag.held && root.barDrag.edge !== 0' 'running: false && root.barDrag !== null && root.barDrag.held && root.barDrag.edge !== 0' \
  && copy_tree placement-edge-slide \
  && edit_tree placement-edge-slide shell/plugins/vgs.bar/Bar.qml "$placement_edge_slide" '            duration: 60000' \
  && copy_tree placement-edge-slide-control \
  && edit_tree placement-edge-slide-control shell/plugins/vgs.bar/Bar.qml "$placement_edge_slide" '            duration: 60000' \
  && edit_tree placement-edge-slide-control shell/Core/Plugins.qml "$placement_edge_settled" 'const sectionPoint = drawn;' \
  && copy_tree placement-edge-snap-control \
  && edit_tree placement-edge-snap-control shell/plugins/vgs.bar/Bar.qml "$placement_edge_slide" '            duration: 60000' \
  && edit_tree placement-edge-snap-control shell/plugins/vgs.bar/Bar.qml '        property real lag: 0' $'        property real lag: 0\n        onScrollChanged: { slide.stop(); lag = 0; }' \
  && copy_tree placement-edge-leave-control \
  && edit_tree placement-edge-leave-control shell/Core/Plugins.qml "$placement_edge_read" 'edge: barDrag.edge !== 0 ? barDrag.edge : barDragEdge(barDrag.gap.parent, point.x) });'; then
  if placement_edge_start placement-edge-control; then
    placement_edge_held end "$placement_edge_last" 0 short "control: without the hold timer the held drag stays short of the last slot"
    expect_poll "control: without the hold timer the release lands the fixture short of the last slot" inner placement_edge_dropped
  fi
  if placement_edge_start placement-edge-slide; then
    placement_edge_held end "$placement_edge_last" 1 reached "slow slide: the held drag reaches the last slot while the zone still slides"
    expect_poll "slow slide: the release lands the fixture last in the left section" last placement_edge_dropped
    geometry expect "slow slide: the zone still slides after its last step" '[true, false, false]' placement_edge_ends
  fi
  if placement_edge_start placement-edge-slide-control; then
    placement_edge_held end "$placement_edge_last" 0 short "control: a slot read from the section's drawn place stays short of the last slot"
    expect_poll "control: over the section's drawn place the release lands the fixture short of the last slot" inner placement_edge_dropped
  fi
  if placement_edge_start placement-edge-snap-control; then
    placement_edge_held end "$placement_edge_last" 1 reached "control: a zone that ends its slide on a scroll change still reaches the last slot"
    geometry expect_poll "control: a zone that ends its slide on a scroll change stands settled after its last step" '[true, false, true]' placement_edge_ends
  fi
  placement_edge_start placement-edge-leave-control \
    && placement_edge_leave 1 True "control: a copy that keeps the end it stood past steps the zone to its end after the drag left"
fi
stop_shell
cp -- "$placement_saved" "$placement_file.tmp" && mv -T -- "$placement_file.tmp" "$placement_file"
start_shell "$repo" "$sandbox/placement-edge-restored.log" || fail "the shell starts after the edge controls"

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
