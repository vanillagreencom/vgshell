# inputs: shell/plugins/vgs.launcher/* shell/plugins/vgs.tray/* scripts/smoke/fixtures/tray/* config/shell.json shell/Core/PluginLogic.js shell/plugins/vgs.sound/* shell/plugins/vgs.network/* shell/plugins/vgs.bluetooth/* shell/plugins/vgs.displays/* shell/plugins/vgs.keyboard/* shell/plugins/vgs.vpn/* shell/plugins/vgs.mouse/* shell/plugins/vgs.bar/* scripts/smoke/fixtures/plugins/acme.tick/* scripts/smoke/fixtures/plugins/acme.idle/* shell/Hosts/BarHost.qml shell/Ui/controls/BarItem.qml shell/Core/Plugins.qml shell/Core/Config.qml shell/Commons/Workspaces.qml shell/Commons/Time.qml shell/plugins/*/manifest.json
set -euo pipefail
expect "instance guard accepts the runner's shell" true ipc shell guarded

# Plugins scan asynchronously; wait for the bundled bar and the placed widget.
plugins_json=""
for _ in $(seq 1 100); do
  if plugins_json="$(ipc shell listPlugins)" && [[ $(py_reply 'import json,sys; ids={p["id"] for p in json.load(sys.stdin)["plugins"]}; print({"vgs.bar","acme.tick"} <= ids)' <<<"$plugins_json") == True ]]; then break; fi
  sleep 0.2
done
# A bundled plugin is enabled unless the harness's user file disables it.
if python3 - "$plugins_json" "$home/.config/vgshell/shell.json" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
harness_disabled = json.load(open(sys.argv[2])).get("disabledPlugins", [])
by = {p["id"]: p for p in d["plugins"]}
missing = [i for i in ("vgs.bar", "acme.tick") if i not in by]
bundled = [i for i in by if i.startswith("vgs.")]
disabled = [i for i in bundled if not by[i]["enabled"] and i not in harness_disabled]
if missing or disabled or d["errors"] or d["collisions"]:
    print("missing=%s disabled=%s errors=%s collisions=%s" % (missing, disabled, d["errors"], d["collisions"]))
    sys.exit(1)
PY
then ok "bundled plugins discovered, enabled and error-free"; else fail "bundled plugin state"; fi

bars=-1
for _ in $(seq 1 50); do
  if bars="$(bar_count)" && [[ $bars == "$monitors" ]]; then break; fi
  sleep 0.2
done
if [[ $bars == "$monitors" && $monitors != 0 && $monitors != -1 ]]; then ok "one bar surface per monitor ($bars of $monitors)"; else fail "bar surfaces: $bars for $monitors monitors"; fi

expect_widgets "every bar mounted the placed plugin widget" '["acme.tick"]'
expect_builtins "every bar registered its built-in workspaces and clock" '["vgs.bar/center-clock","vgs.bar/left-workspaces"]'

# Preserve cold geometry before disable, placement or bar reconstruction.
bar_initial_key="$(bar_key)"
for bar_initial_id in vgs.bar vgs.bar/left-workspaces vgs.bar/center-clock; do
  printf '  cold_geometry id=%s value=%s\n' "$bar_initial_id" "$(ipc smoke descendantGeometry "$bar_initial_key" "$bar_initial_id")"
done
for bar_initial_section in left center right; do
  printf '  cold_section section=%s value=%s\n' "$bar_initial_section" "$(ipc smoke barSectionGeometry "$bar_initial_key" "$bar_initial_section")"
done
printf '  cold_profile value=%s\n' "$(ipc shell listShellConfig)"

# The built-ins share one vertical centre, the bar's, and draw in the
# `text.bar` role alone. A workspace pill is a BarItem: its label plus
# `bar.item.paddingX` a side, never narrower than it is tall, and
# `bar.item.height` tall, with the label at its centre; pills stand
# `bar.item.gap` apart. The sandbox keeps workspaces 1, 2 and
# 100, so three pills stand in a row and the last is wider than the floor.
# Read from the first bar's items, each within one pixel; the answer is
# the list of misplaced items, so `[]` is the pass.
bar_alignment() {
  local key bar_box ws clock pad gap floor xs
  key="$(bar_key)" || return
  bar_box="$(ipc smoke instanceGeometry "$key" vgs.bar)" || return
  ws="$(ipc smoke descendantGeometry "$key" vgs.bar/left-workspaces)" || return
  clock="$(ipc smoke descendantGeometry "$key" vgs.bar/center-clock)" || return
  pad="$(ipc smoke themeValue bar.item.paddingX)" || return
  gap="$(ipc smoke themeValue bar.item.gap)" || return
  floor="$(ipc smoke themeValue bar.item.height)" || return
  python3 - "$bar_box" "$ws" "$clock" "$pad" "$gap" "$floor" <<'PY'
import json, sys
bar, ws, clock, pad, gap, floor = (json.loads(a) for a in sys.argv[1:])
out = []
def near(a, b): return abs(a - b) <= 1
def mid_x(r): return r["box"][0] + r["box"][2] / 2
def mid_y(r): return r["box"][1] + r["box"][3] / 2
def check(name, got, want):
    if not near(got, want): out.append("%s=%.2f want=%.2f" % (name, got, want))
def children(rows, i, kind): return [c for c in rows if c["parent"] == i and c["type"] == kind]
def within(rows, i, kind):
    found, frontier = [], [i]
    while frontier:
        at = frontier.pop()
        for j, c in enumerate(rows):
            if c["parent"] == at:
                frontier.append(j)
                if c["type"] == kind and c.get("visible", True): found.append(c)
    return found
centre = bar[1] + bar[3] / 2
for name, rows in (("workspaces", ws), ("clock", clock)):
    roles = sorted({str(r.get("role")) for r in rows if r["type"] == "Label"})
    if roles != ["bar"]: out.append("%s roles=%s" % (name, roles))
pills = sorted(((r, [l for l in within(ws, i, "Label") if l["box"][2] > 0]) for i, r in enumerate(ws) if r["type"] == "BarItem"), key=lambda p: p[0]["box"][0])
if len(pills) != 3: out.append("workspaces pills=%d want=3" % len(pills))
if not any(pill["box"][2] > floor + 1 for pill, _ in pills): out.append("workspaces wide=0")
for n, (pill, (label,)) in enumerate(pills):
    check("pill%d.width" % n, pill["box"][2], max(floor, label["implicit"][0] + 2 * pad))
    check("pill%d.height" % n, pill["box"][3], floor)
    check("pill%d.label.x" % n, mid_x(label), mid_x(pill))
    check("pill%d.label.y" % n, mid_y(label), mid_y(pill))
    check("pill%d.y" % n, mid_y(pill), centre)
    if n: check("pill%d.gap" % n, pill["box"][0] - (pills[n - 1][0]["box"][0] + pills[n - 1][0]["box"][2]), gap)
clock_labels = [r for r in clock if r["type"] == "Label"]
if len(clock_labels) != 1: out.append("clock labels=%d" % len(clock_labels))
for label in clock_labels: check("clock.label.y", mid_y(label), centre)
print(json.dumps(out))
PY
}
geometry expect_poll "the workspace pills and the clock share the bar's centre" '[]' bar_alignment
bar_font_family() { ipc smoke readInstance "$(bar_key)" vgs.bar fontFamily; }
expect "the bar API names the family of the bar role" '"JetBrains Mono"' bar_font_family
expect "the core built the bar, its placed widget and the vgs.themes background per screen, the vgs.bar, vgs.themes and always-on vgs.settings services once each, and no built-in" "$((3 * monitors + 3))" builds

# Disable only lists the id: the layout entry and its settings stay, so
# re-enabling restores the exact screen. The effective configuration is
# read back for the entry, the user file for what the manager wrote.
# Latency from a setPluginEnabled reply to `built` reflecting it, polled
# with qs ipc against the shell's pid; the reading carries one IPC round trip.
reconcile_ms=""
if disable_reply="$(ipc shell setPluginEnabled acme.tick false)"; then
  replied_ms="$(now_ms)"
  reconcile_poll_count=0
  for _ in $(seq 1 500); do
    reconcile_poll_count=$((reconcile_poll_count + 1))
    if built_now="$("${shell_env[@]}" qs ipc --pid "$shell_qs_pid" call shell built 2>>"$sandbox/ipc.log" | tail -n 1)" && [[ -n $built_now && $built_now != *'"id":"acme.tick"'* ]]; then
      reconcile_ms=$(( $(now_ms) - replied_ms ))
      break
    fi
    sleep 0.005
  done
fi
printf '  reconcile_observation polls=%s latency_ms=%s cpu=%s\n' "${reconcile_poll_count:-0}" "$reconcile_ms" "$(cat /proc/pressure/cpu)"
if [[ $disable_reply == ok ]]; then ok "disabling a widget is allowed"; else fail "disabling a widget is allowed: got $disable_reply"; fi
tick_entry() { ipc shell listShellConfig | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([e for e in d["bar"]["layout"]["center"] if e["id"]=="acme.tick"]))'; }
user_keys() { python3 -c 'import json,sys; print(",".join(sorted(json.load(open(sys.argv[1])).keys())))' "$home/.config/vgshell/shell.json"; }
expect_widgets "the bar dropped the disabled widget" '[]'
expect_builtins "the built-ins stay while a plugin widget leaves" '["vgs.bar/center-clock","vgs.bar/left-workspaces"]'
expect "widget reads disabled after the user file changed" False plugin_enabled acme.tick
expect "the disabled widget keeps its layout entry and settings" '[{"id": "acme.tick", "format": "ddd d MMM  HH:mm"}]' tick_entry
expect "disable wrote only the disabled list" "bar,disabledPlugins,plugins,version" user_keys
expect "re-enabling the widget is allowed" ok ipc shell setPluginEnabled acme.tick true
expect_widgets "the bar rebuilt the re-enabled widget" '["acme.tick"]'
expect "re-enable wrote only the disabled list" "bar,disabledPlugins,plugins,version" user_keys

expect "disabling the bar names the widgets it hides" "ok hidden=acme.tick" ipc shell setPluginEnabled vgs.bar false
expect_widgets "the bar host unloaded the disabled bar" '[]'
expect_builtins "the disabled bar's built-ins left the build records" '[]'
bars_now=-1
for _ in $(seq 1 50); do
  if bars_now="$(bar_count)" && [[ $bars_now == 0 ]]; then break; fi
  sleep 0.2
done
if [[ $bars_now == 0 ]]; then ok "the bar host destroyed its surface with no bar"; else fail "bar surfaces with the bar disabled: $bars_now"; fi
expect "no bar reserves no screen space" 0 reserved_total
expect "re-enabling the bar is allowed" ok ipc shell setPluginEnabled vgs.bar true
expect_widgets "the bar host rebuilt the re-enabled bar" '["acme.tick"]'
expect_builtins "the re-enabled bar registered its built-ins again" '["vgs.bar/center-clock","vgs.bar/left-workspaces"]'
for _ in $(seq 1 50); do
  if bars_now="$(bar_count)" && [[ $bars_now == "$monitors" ]]; then break; fi
  sleep 0.2
done
if [[ $bars_now == "$monitors" ]]; then ok "the bar host mapped its surface again"; else fail "bar surfaces after re-enable: $bars_now"; fi
reserved=0
for _ in $(seq 1 50); do
  if reserved="$(reserved_total)" && [[ $reserved -gt 0 ]]; then break; fi
  sleep 0.2
done
if [[ $reserved -gt 0 ]]; then ok "the re-enabled bar reserves screen space again"; else geometry fail "reserved space after re-enable: $reserved"; fi
if [[ -f "$home/.config/vgshell/shell.json" ]]; then ok "manager wrote the user file"; else fail "user file missing"; fi

# An unrelated key in the user file builds nothing: the shell is seen to
# have read the write (the key is in the effective configuration) before
# the build count is compared. Every write the smoke makes to the user file
# is a rename, so the watching shell never reads half a file.
unrelated_key() { ipc shell listShellConfig | py_reply 'import json,sys; print(json.load(sys.stdin).get("unrelated"))'; }
if before="$(builds)"; then
  python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
d["unrelated"] = 1
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PY
  expect_poll "the shell read the unrelated key" 1 unrelated_key
  expect "an unrelated configuration write rebuilds nothing" "$before" builds
  # Every completed scan logs whether the plugin set changed. A rescan
  # that changes nothing moves no slot key, so it builds nothing; the
  # logged line says the landed scan changed nothing.
  if unchanged_scans="$(log_lines 'plugins: scan complete changed=false$')"; then
    rescan "a rescan that changes nothing answers ok"
    expect_log "the rescan that changes nothing completed" "$((unchanged_scans + 1))" 'plugins: scan complete changed=false$'
    expect "a rescan that changes nothing rebuilds nothing" "$before" builds
  else
    fail "instance log unreadable: $instance_log"
  fi
  # A rescan that adds a plugin nothing enables changes the set but moves
  # no other plugin's slot key, so nothing is built: not the bars, not
  # the placed widget, not the new plugin.
  idle="$home/.config/vgshell/plugins/acme.idle"
  mkdir -p "$idle"
  cp -R "$repo/scripts/smoke/fixtures/plugins/acme.idle/." "$idle/"
  rescan "a rescan after adding a plugin answers ok"
  expect_poll "the rescan discovered the plugin, disabled" False plugin_enabled acme.idle
  expect "a rescan that adds a disabled plugin does not build it" False record_exists acme.idle
  expect "a rescan that adds a plugin rebuilds no other plugin" "$before" builds
else
  fail "buildCount unreadable"
fi

# Declaration and effective placement use one independent expected contract.
# Runtime reads permit first-presence additions outside the requested group.
fresh_want='{"left":["vgs.launcher","vgs.bar/left-workspaces","vgs.tray"],"center":["vgs.bar/center-clock"],"right":["vgs.vpn","vgs.network","vgs.bluetooth","vgs.sound","vgs.displays","vgs.keyboard","vgs.settings"]}'
fresh_bar_declared() {
  py_reply 'import json,sys
config=json.load(sys.stdin); want=json.loads(sys.argv[1])
layout={s:[e["id"] for e in config["bar"]["layout"][s]] for s in want}
mouse=any(e["id"]=="vgs.mouse" for e in config["plugins"])
print(layout==want and mouse and "vgs.mouse" not in config["disabledPlugins"])' "$fresh_want" <"$1"
}
fresh_bar_placement() {
  local config records
  config="$(ipc shell listShellConfig)" && records="$(ipc shell built)" || return 1
  py_reply 'import json,sys
config,records,want=json.load(sys.stdin),json.loads(sys.argv[1]),json.loads(sys.argv[3])
requested={i for ids in want.values() for i in ids}
layout={s:[e["id"] for e in config["bar"]["layout"][s]] for s in want}
ordered={s:[i for i in layout[s] if i in requested] for s in want}
bars=[[r["id"] for r in rows if r["origin"]=="plugin" or r["kind"]=="bar-widget"] for key,rows in records.items() if key.startswith("bar:")]
built=len(bars)==int(sys.argv[2]) and bool(bars) and all(all(ids.count(i)==1 for i in requested) and "vgs.mouse" not in ids for ids in bars)
print("placed" if ordered==want and layout["left"][:1]==["vgs.launcher"] and all("vgs.mouse" not in ids for ids in layout.values()) and built else json.dumps({"ordered":ordered,"layout":layout,"bars":bars}))' "$records" "$monitors" "$fresh_want" <<<"$config"
}
fresh_bar_complete() { local state; state="$(fresh_bar_placement)" || return 1; [[ $state == placed ]] && echo True || echo False; }
# Read actual boxes, including unrelated widgets, rather than record order.
fresh_bar_rendered() {
  local records hosts key id section box visible rows="" ids
  records="$(ipc shell built)" || return 1
  hosts="$(py_reply 'import json,sys; print(" ".join(k for k in json.load(sys.stdin) if k.startswith("bar:")))' <<<"$records")" || return 1
  [[ -n $hosts ]] || { echo absent; return; }
  for key in $hosts; do
    box="$(ipc smoke instanceGeometry "$key" vgs.bar)" || return 1
    rows+="$key bar $box"$'\n'
    for section in left center right; do
      box="$(ipc smoke barSectionGeometry "$key" "$section")" || return 1
      rows+="$key $section $box"$'\n'
    done
    ids="$(py_reply 'import json,sys; print(" ".join(r["id"] for r in json.load(sys.stdin)[sys.argv[1]] if r["origin"]=="plugin" or r["kind"]=="bar-widget"))' "$key" <<<"$records")" || return 1
    for id in $ids; do
      box="$(ipc smoke instanceGeometry "$key" "$id")" && visible="$(ipc smoke readInstance "$key" "$id" visible)" || return 1
      rows+="$key $id $visible $box"$'\n'
    done
  done
  py_reply 'import json,sys
want=json.loads(sys.argv[1]); hosts={}; failures=[]
for line in sys.stdin:
    fields=line.strip().split(" ",2)
    if len(fields)!=3: continue
    host,key,value=fields; rows=hosts.setdefault(host,{})
    if key in ("bar","left","center","right"):
        rows[key]=json.loads(value) if value.startswith("[") else None
    else:
        visible,box=value.split(" ",1); rows[key]=(visible=="true",json.loads(box) if box.startswith("[") else None)
def inside(box,parent):
    return box is not None and parent is not None and box[0]>=parent[0]-1 and box[1]>=parent[1]-1 and box[0]+box[2]<=parent[0]+parent[2]+1 and box[1]+box[3]<=parent[1]+parent[3]+1
for host,rows in hosts.items():
    if any(rows.get(s) is None for s in ("bar","left","center","right")): failures.append(host+":missing-section"); continue
    for section,ids in want.items():
        drawn=[]
        for ident in ids:
            visible,box=rows.get(ident,(False,None))
            if box is None: failures.append(ident+":missing"); continue
            # Displays draws only for a matching ready display. Keyboard
            # draws only with multiple layouts. Both records remain required.
            if ident in ("vgs.displays","vgs.keyboard") and not visible: continue
            if not visible or box[2]<=0 or box[3]<=0: failures.append(ident+":not-drawn"); continue
            if not inside(box,rows[section]) or not inside(box,rows["bar"]): failures.append(ident+":outside-section")
            drawn.append((box[0],ident))
        expected=[ident for ident in ids if ident not in ("vgs.displays","vgs.keyboard") or rows.get(ident,(False,None))[0]]
        if [ident for _,ident in sorted(drawn)]!=expected: failures.append(section+":order")
    launcher=rows.get("vgs.launcher",(False,None))[1]
    if launcher is not None:
        for ident,value in rows.items():
            if ident in ("bar","left","center","right"): continue
            visible,box=value
            if visible and box is not None and box[2]>0 and inside(box,rows["left"]) and box[0]<launcher[0]-1: failures.append(ident+":before-launcher")
print("drawn" if len(hosts)==int(sys.argv[2]) and not failures else json.dumps({"hosts":list(hosts),"failures":failures}))' "$fresh_want" "$monitors" <<<"$rows"
}
fresh_bar_drawn() { local state; state="$(fresh_bar_rendered)" || return 1; [[ $state == drawn ]] && echo True || echo False; }
fresh_restore() {
  cp -- "$fresh_settled" "$home/.config/vgshell/shell.json.tmp"
  mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
  expect_poll "the full settled automatic placement profile returns" placed fresh_bar_placement
}
expect "the shipped lists match the complete requested declaration" True fresh_bar_declared "$repo/config/shell.json"
fresh_declared_control="$sandbox/bar-declared-control.json"
python3 - "$repo/config/shell.json" "$fresh_declared_control" <<'PY'
import json,sys
config=json.load(open(sys.argv[1])); config["bar"]["layout"]["right"].append({"id":"vgs.mouse"})
with open(sys.argv[2],"w") as out: json.dump(config,out)
PY
expect "control: declaration rejects an extra shipped entry" False fresh_bar_declared "$fresh_declared_control"
fresh_saved="$sandbox/bar-fresh-saved.json"
cp -- "$home/.config/vgshell/shell.json" "$fresh_saved"
if devices_ready bar; then
  stop_shell
  fresh_history="$sandbox/bar-fresh-history"
  mkdir -p -- "$fresh_history"
  cp -a -- "$devices_dir/calls" "$fresh_history/calls"
  cp -a -- "$shim" "$fresh_history/shim"
  fresh_paths=("$dev_state" "$home/.local/state/vgshell/updates/status.json")
  for fresh_i in "${!fresh_paths[@]}"; do
    if [[ -e ${fresh_paths[fresh_i]} ]]; then cp -a -- "${fresh_paths[fresh_i]}" "$fresh_history/state-$fresh_i"; fi
  done
  if [[ -f $devices_hid_log ]]; then cp -- "$devices_hid_log" "$fresh_history/hid.calls"; fi
  default_set_prepare '[]'
  expect "the fresh profile has no user bar" False python3 -c 'import json,sys; print("bar" in json.load(open(sys.argv[1])))' "$home/.config/vgshell/shell.json"
  spawn "$sandbox/bar-fresh-tray.log" env -i PATH="$PATH" HOME="$home" DBUS_SESSION_BUS_ADDRESS="unix:path=$rt_dir/bus" python3 "$source_repo/scripts/smoke/fixtures/tray/mock-sni.py" "$sandbox/bar-fresh-tray.calls"
  fresh_tray_pid="$spawn_pid"
  start_shell "$repo" "$sandbox/qs-bar-fresh.log" || fail "the fresh profile shell starts"
  expect_poll "the fresh bar preserves requested order and automatic widgets" placed fresh_bar_placement
  geometry expect_poll "the fresh bar draws Launcher, workspaces, tray and clock in order" drawn fresh_bar_rendered
  expect "Mouse stays enabled off the fresh bar" True plugin_enabled vgs.mouse
  fresh_settled="$sandbox/bar-fresh-settled.json"
  cp -- "$home/.config/vgshell/shell.json" "$fresh_settled"
  for fresh_missing in vgs.settings vgs.sound; do
    expect "control: $fresh_missing can leave the fresh bar" ok ipc shell setPluginPlaced "$fresh_missing" false
    expect_poll "control: placement rejects a bar missing $fresh_missing" False fresh_bar_complete
    fresh_restore
  done
  expect "control: Sound can move before VPN" ok ipc shell movePluginWidget vgs.sound right 0
  expect_poll "control: placement rejects the wrong right order" False fresh_bar_complete
  fresh_restore
  expect "control: Launcher can move after workspaces" ok ipc shell movePluginWidget vgs.launcher left 1
  expect_poll "control: typed placement rejects Launcher after workspaces" False fresh_bar_complete
  geometry expect_poll "control: rendered placement rejects Launcher after workspaces" False fresh_bar_drawn
  fresh_restore
  fresh_snapshot="$(ipc smoke rememberBarWidgets "$(bar_key)")" || fail "the fresh identity snapshot is unreadable"
  expect "the fresh snapshot includes builtin identities" True py_reply 'import json,sys; ids=json.load(sys.stdin); print({"vgs.bar/left-workspaces","vgs.bar/center-clock"} <= set(ids))' <<<"$fresh_snapshot"
  expect "control: workspaces moves to right with the same ID" ok ipc shell movePluginWidget vgs.bar/left-workspaces right 0
  expect_poll "control: placement rejects workspaces in another section" False fresh_bar_complete
  expect "builtin section transfer keeps every object" '[]' ipc smoke barWidgetIdentities
  expect "the fresh identity snapshot is released" ok ipc smoke forgetBarWidgets
  fresh_restore
  python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json,os,sys
path=sys.argv[1]; config=json.load(open(path)); config["bar"]["layout"]["center"]=[e for e in config["bar"]["layout"]["center"] if e["id"]!="vgs.bar/center-clock"]
with open(path+".tmp","w") as out: json.dump(config,out)
os.replace(path+".tmp",path)
PY
  expect_poll "control: placement rejects a missing builtin clock" False fresh_bar_complete
  fresh_restore
  expect "control: enabled Mouse can be placed" ok ipc shell setPluginPlaced vgs.mouse true
  expect_poll "control: placement rejects any Mouse placement" False fresh_bar_complete
  fresh_restore
  geometry expect_poll "rendered placement returns after all controls" drawn fresh_bar_rendered
  stop_shell
  kill -TERM "$fresh_tray_pid" 2>/dev/null || true
  wait "$fresh_tray_pid" 2>/dev/null || true
  rm -rf -- "${devices_dir:?}/calls" "${shim:?}"
  cp -a -- "$fresh_history/calls" "$devices_dir/calls"
  cp -a -- "$fresh_history/shim" "$shim"
  for fresh_i in "${!fresh_paths[@]}"; do
    rm -rf -- "${fresh_paths[fresh_i]:?}"
    if [[ -e $fresh_history/state-$fresh_i ]]; then cp -a -- "$fresh_history/state-$fresh_i" "${fresh_paths[fresh_i]}"; fi
  done
  if [[ -f $fresh_history/hid.calls ]]; then cp -- "$fresh_history/hid.calls" "$devices_hid_log"; else rm -f -- "$devices_hid_log"; fi
  cp -- "$fresh_saved" "$home/.config/vgshell/shell.json.tmp"
  mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
  start_shell "$repo" "$sandbox/qs-bar-restored.log" || fail "the smoke profile shell starts again"
  expect_widgets "the original placed widget returns after the fresh profile" '["acme.tick"]'
fi

# Reproduce the cold zero-height mount in a disposable bar. The same
# descendant reader must reject it while both registrations still exist.
bar_alignment_misplaced() {
  bar_alignment | py_reply 'import json,sys; rows=json.load(sys.stdin); print(any(s.startswith("clock.label.y=") for s in rows) and any(s.startswith("pill0.y=") for s in rows))'
}
if copy_tree bar-height-control \
  && edit_tree bar-height-control shell/plugins/vgs.bar/Bar.qml 'implicitHeight: barSize' 'implicitHeight: 0'; then
  stop_shell
  start_shell "$sandbox/tree-bar-height-control" "$sandbox/bar-height-control.log" || fail "the cold-height control shell starts"
  expect_builtins "control: the cold-height bar still registers both builtins" '["vgs.bar/center-clock","vgs.bar/left-workspaces"]'
  geometry expect "control: the alignment reader rejects a cold mount with no intrinsic bar height" True bar_alignment_misplaced
  stop_shell
  start_shell "$repo" "$sandbox/bar-height-restored.log" || fail "the shell starts after the cold-height control"
  geometry expect_poll "the restored cold bar centers both builtin contents" '[]' bar_alignment
fi
