# inputs: shell/plugins/vgs.launcher/* shell/plugins/vgs.tray/* scripts/smoke/fixtures/tray/* config/shell.json shell/Core/PluginLogic.js shell/plugins/vgs.sound/* shell/plugins/vgs.network/* shell/plugins/vgs.bluetooth/* shell/plugins/vgs.displays/* shell/plugins/vgs.keyboard/* shell/plugins/vgs.vpn/* shell/plugins/vgs.sudo/* shell/plugins/vgs.mouse/* shell/plugins/vgs.bar/* scripts/smoke/fixtures/plugins/acme.tick/* scripts/smoke/fixtures/plugins/acme.idle/* shell/Hosts/BarHost.qml shell/Ui/controls/BarItem.qml shell/Ui/BarWidget.qml shell/Core/Plugins.qml shell/Core/Config.qml shell/Commons/Workspaces.qml shell/Commons/Time.qml shell/plugins/*/manifest.json shell/Core/Capabilities.qml shell/Ui/overlay/Menu.qml shell/Ui/overlay/MenuItem.qml shell/Commons/Tokens.js
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
values = []
for raw in sys.argv[1:]:
    try: values.append(json.loads(raw))
    except (ValueError, TypeError):
        print(json.dumps(["absent"])); sys.exit()
bar, ws, clock, pad, gap, floor = values
if not isinstance(bar, list) or len(bar) != 4 or not isinstance(ws, list) or not isinstance(clock, list):
    print(json.dumps(["absent"])); sys.exit()
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
for n, (pill, labels) in enumerate(pills):
    if len(labels) != 1:
        out.append("pill%d labels=%d" % (n, len(labels))); continue
    label = labels[0]
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
# Use the runner's EPOCHREALTIME clock conversion in this shell so date,
# seq and tail processes add no caller work to that interval.
reconcile_ms=""
reconcile_cpu_some_pct=unmeasured
if disable_reply="$(ipc shell setPluginEnabled acme.tick false)"; then
  replied_ms=$(( ${EPOCHREALTIME//[!0-9]/} / 1000 ))
  reconcile_cpu_start="$(cpu_some_us)"
  reconcile_poll_count=0
  for ((reconcile_poll = 0; reconcile_poll < 500; ++reconcile_poll)); do
    reconcile_poll_count=$((reconcile_poll_count + 1))
    if built_output="$("${shell_env[@]}" qs ipc --pid "$shell_qs_pid" call shell built 2>>"$sandbox/ipc.log")"; then
      vgs_ipc_last_line_into "$built_output"
      built_now="$vgs_ipc_last_line"
      if [[ $built_now == \{*\} && $built_now != *'"id":"acme.tick"'* ]]; then
        reconcile_ms=$(( ${EPOCHREALTIME//[!0-9]/} / 1000 - replied_ms ))
        reconcile_cpu_some_pct="$(cpu_some_pct "$reconcile_cpu_start" "$(cpu_some_us)" "$reconcile_ms")"
        break
      fi
    fi
    sleep 0.005
  done
fi
printf '  reconcile_observation polls=%s latency_ms=%s cpu_some_pct=%s\n' "${reconcile_poll_count:-0}" "$reconcile_ms" "$reconcile_cpu_some_pct"
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
fresh_want='{"left":["vgs.launcher","vgs.bar/left-workspaces","vgs.tray"],"center":["vgs.bar/center-clock"],"right":["vgs.sudo","vgs.vpn","vgs.network","vgs.bluetooth","vgs.sound","vgs.displays","vgs.keyboard","vgs.settings"]}'
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
  python3 - "$home/.config/vgshell/shell.json" <<'PYREAD'
import json,os,sys
path=sys.argv[1]; config=json.load(open(path)); layout=config["bar"]["layout"]
entry=next(e for e in layout["left"] if e["id"]=="vgs.bar/left-workspaces")
layout["left"]=[e for e in layout["left"] if e["id"]!="vgs.bar/left-workspaces"]
layout["right"].insert(0,entry)
with open(path+".tmp","w") as out: json.dump(config,out)
os.replace(path+".tmp",path)
PYREAD
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

# Exercise the shipped positive-width Network hide route and a private
# Tick size producer in the same mounted section. All four entries stay
# present; the reader measures boxes and the real drop geometry.
bar_participation_state() {
  python3 - "$bar_participation_profile" "$home/.config/vgshell/shell.json" "$1" <<'PY'
import json,os,sys
config=json.load(open(sys.argv[1])); state=sys.argv[3]
for entry in config["bar"]["layout"]["center"]:
    if entry["id"]=="vgs.network": entry["showDisconnected"]=state!="hidden"
    if entry["id"]=="acme.tick": entry["format"]=state
with open(sys.argv[2]+".tmp","w") as out: json.dump(config,out)
os.replace(sys.argv[2]+".tmp",sys.argv[2])
PY
}
bar_participation() {
  local snapshot
  snapshot="$(ipc smoke barParticipationGeometry "$(bar_key)")" || return 1
  py_reply 'import json,sys
data=json.load(sys.stdin); state=sys.argv[1]; errors=[]
if not isinstance(data,dict): print("absent"); sys.exit()
if data["shown"]!=(sys.argv[2]=="shown") or data["windowVisible"]!=(sys.argv[2]=="shown"): errors.append("window")
if sys.argv[2]=="hidden": print(json.dumps(errors)); sys.exit()
sections=data.get("sections",[])
center=next((s for s in sections if s["section"]=="center"),None)
if center is None: print("missing-center"); sys.exit()
rows=center["entries"]; ids=[r["id"] for r in rows]
want=["vgs.bar/left-workspaces","vgs.network","acme.tick","vgs.bar/center-clock"]
if ids!=want or any(not r["present"] or r["box"] is None for r in rows):
    print("membership"); sys.exit()
by={r["id"]:r for r in rows}; network=by["vgs.network"]; tick=by["acme.tick"]
if network["visible"]!=(state!="hidden") or network["box"][2]<=0 or network["box"][3]<=0: errors.append("producer")
if not tick["visible"] or (tick["box"][2]==0)!=(state=="zero-width") or (tick["box"][3]==0)!=(state=="zero-height"): errors.append("producer")
drawn=[r for r in rows if r["id"]!="vgs.network" or state!="hidden"]
drawn=[r for r in drawn if r["id"]!="acme.tick" or state not in ("zero-width","zero-height")]
gap=center["gap"]; width=sum(r["box"][2] for r in drawn)+(len(drawn)-1)*gap
if abs(center["width"]-width)>0.5: errors.append("width")
x=0
for row in drawn:
    if abs(row["box"][0]-x)>0.5: errors.append("position"); break
    x+=row["box"][2]+gap
drop=center["drop"]
if abs(drop["width"]-width)>0.5 or [w["locator"]["id"] for w in drop["widgets"]]!=[r["id"] for r in drawn]: errors.append("drop")
if sys.argv[3]:
    before=json.load(open(sys.argv[3]))
    if [s["section"] for s in sections]!=[s["section"] for s in before["sections"]]: errors.append("membership")
    else:
        for actual,prior in zip(sections,before["sections"]):
            if abs(actual["width"]-prior["width"])>0.5 or actual["gap"]!=prior["gap"]: errors.append("width")
            if [(r["locator"],r["present"]) for r in actual["entries"]]!=[(r["locator"],r["present"]) for r in prior["entries"]]: errors.append("membership"); continue
            for row,old in zip(actual["entries"],prior["entries"]):
                if row["visible"]!=old["visible"] or any(abs(a-b)>0.5 for a,b in zip(row["box"][2:],old["box"][2:])): errors.append("producer")
                if any(abs(a-b)>0.5 for a,b in zip(row["box"][:2],old["box"][:2])): errors.append("position")
            a,p=actual["drop"],prior["drop"]
            if abs(a["width"]-p["width"])>0.5 or abs(a["x"]-p["x"])>0.5 or a["widgets"]!=p["widgets"]: errors.append("drop")
print(json.dumps(sorted(set(errors))))' "$1" "${2:-shown}" "${3:-}" <<<"$snapshot"
}
bar_participation_fault() {
  bar_participation "$1" | py_reply 'import json,sys; errors=json.load(sys.stdin); print(isinstance(errors,list) and {"width","position","drop"}<=set(errors) and "producer" not in errors and "window" not in errors)'
}
bar_participation_saved="$sandbox/bar-participation-saved.json"
bar_participation_profile="$sandbox/bar-participation-profile.json"
bar_participation_tick="$home/.config/vgshell/plugins/acme.tick/Widget.qml"
cp -- "$home/.config/vgshell/shell.json" "$bar_participation_saved"
cp -- "$bar_participation_tick" "$sandbox/bar-participation-tick.qml"
stop_shell
python3 - "$bar_participation_saved" "$bar_participation_profile" "$bar_participation_tick" <<'PY'
import json,pathlib,sys
config=json.load(open(sys.argv[1])); owned={"vgs.bar/left-workspaces","vgs.network","acme.tick","vgs.bar/center-clock"}
for section in config["bar"]["layout"]:
    config["bar"]["layout"][section]=[e for e in config["bar"]["layout"][section] if e["id"] not in owned]
config["bar"]["layout"]["center"]=[{"id":i} for i in ("vgs.bar/left-workspaces","vgs.network","acme.tick","vgs.bar/center-clock")]
config["disabledPlugins"]=[i for i in config["disabledPlugins"] if i!="vgs.network"]
with open(sys.argv[2],"w") as out: json.dump(config,out)
path=pathlib.Path(sys.argv[3]); source=path.read_text()
for old,new in (("    implicitWidth: 20", "    implicitWidth: format === \"zero-width\" ? 0 : 20"),
                ("    implicitHeight: barSize", "    implicitHeight: format === \"zero-height\" ? 0 : barSize")):
    assert source.count(old)==1
    source=source.replace(old,new)
path.write_text(source)
PY
bar_participation_state shown
start_shell "$repo" "$sandbox/bar-participation.log" || fail "the participation shell starts"
geometry expect_poll "all shown entries occupy their exact width and gaps" '[]' bar_participation shown
bar_participation_snapshot="$(ipc smoke rememberBarWidgets "$(bar_key)")" || fail "participation cannot read mounted objects"
expect "participation remembers every test object" True py_reply 'import json,sys; ids=json.load(sys.stdin); print({"acme.tick","vgs.bar/center-clock","vgs.bar/left-workspaces","vgs.network"}<=set(ids) and len(ids)==len(set(ids)))' <<<"$bar_participation_snapshot"
for bar_participation_case in hidden zero-width zero-height; do
  bar_participation_state "$bar_participation_case"
  geometry expect_poll "$bar_participation_case leaves no width, neighbour gap or drop target" '[]' bar_participation "$bar_participation_case"
  expect "$bar_participation_case retains every mounted object" '[]' ipc smoke barWidgetIdentities
  bar_participation_state shown
  geometry expect_poll "shown geometry returns after $bar_participation_case" '[]' bar_participation shown
done
bar_participation_before="$sandbox/bar-participation-before.json"
ipc smoke barParticipationGeometry "$(bar_key)" >"$bar_participation_before" || fail "shown participation geometry is unreadable before Hide"
expect "the mapped bar hides through its shipped toggle" ok ipc vgs.bar invoke toggle ''
expect_poll "the hidden bar unmaps its window" '[]' bar_participation shown hidden
expect "the hidden bar keeps its mounted objects" '[]' ipc smoke barWidgetIdentities
expect "the hidden bar reveals through its shipped toggle" ok ipc vgs.bar invoke toggle ''
geometry expect_poll "the revealed bar restores its shown section geometry" '[]' bar_participation shown shown "$bar_participation_before"
expect "the revealed bar keeps its mounted objects" '[]' ipc smoke barWidgetIdentities
expect "participation releases the object snapshot" ok ipc smoke forgetBarWidgets
stop_shell
for bar_participation_case in hidden zero-width zero-height; do
  case "$bar_participation_case" in
    hidden) bar_participation_mutant='return item.width > 0 && item.height > 0;' ;;
    zero-width) bar_participation_mutant='return item.visible && item.height > 0;' ;;
    zero-height) bar_participation_mutant='return item.visible && item.width > 0;' ;;
  esac
  if copy_tree "bar-participation-$bar_participation_case" \
    && edit_tree "bar-participation-$bar_participation_case" shell/Core/Plugins.qml 'return item.visible && item.width > 0 && item.height > 0;' "$bar_participation_mutant"; then
    bar_participation_state "$bar_participation_case"
    start_shell "$sandbox/tree-bar-participation-$bar_participation_case" "$sandbox/bar-participation-$bar_participation_case.log" || fail "the participation control starts"
    geometry expect_poll "control: $bar_participation_case fails width, neighbour gaps and drop geometry" True bar_participation_fault "$bar_participation_case"
    stop_shell
  fi
done
# A section that stays collapsed after Show must fail the same restoration
# reader as the real toggle, with a shown baseline from this control.
if copy_tree bar-participation-restore \
  && edit_tree bar-participation-restore shell/plugins/vgs.bar/Bar.qml '    id: bar' $'    id: bar\n    property bool smokeHidden: false\n    onShownChanged: if (!shown) smokeHidden = true' \
  && edit_tree bar-participation-restore shell/plugins/vgs.bar/Bar.qml '        id: center' $'        id: center\n        width: bar.smokeHidden ? 0 : implicitWidth'; then
  bar_participation_state shown
  start_shell "$sandbox/tree-bar-participation-restore" "$sandbox/bar-participation-restore.log" || fail "the restoration control starts"
  geometry expect_poll "control: the section starts with shown geometry" '[]' bar_participation shown
  ipc smoke barParticipationGeometry "$(bar_key)" >"$bar_participation_before" || fail "the restoration control baseline is unreadable"
  expect "control: Hide reaches the real toggle before restoration" ok ipc vgs.bar invoke toggle ''
  expect_poll "control: the collapsed section window hides" '[]' bar_participation shown hidden
  expect "control: Show reaches the real toggle after collapse" ok ipc vgs.bar invoke toggle ''
  geometry expect_poll "control: a section that stays zero width fails the restoration reader" '["drop", "width"]' bar_participation shown shown "$bar_participation_before"
  stop_shell
fi
# The real Hide route must unmap its window. Retained Item boxes are not
# evidence of a mapped surface; the same typed reader checks both states.
if copy_tree bar-participation-window \
  && edit_tree bar-participation-window shell/Hosts/BarHost.qml 'visible: host.screenPresent && PluginLogic.barShown(slot.instance)' 'visible: true'; then
  bar_participation_state shown
  start_shell "$sandbox/tree-bar-participation-window" "$sandbox/bar-participation-window.log" || fail "the hidden-window control starts"
  geometry expect_poll "control: the mapped window starts with shown geometry" '[]' bar_participation shown
  expect "control: Hide reaches the shipped bar toggle" ok ipc vgs.bar invoke toggle ''
  expect_poll "control: the hidden-state reader rejects a window that stays visible" '["window"]' bar_participation shown hidden
  stop_shell
fi
cp -- "$sandbox/bar-participation-tick.qml" "$bar_participation_tick"
cp -- "$bar_participation_saved" "$home/.config/vgshell/shell.json.tmp"
mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
start_shell "$repo" "$sandbox/bar-participation-restored.log" || fail "the shell returns after participation controls"
expect_widgets "participation restores the original mounted fixture" '["acme.tick"]'

# Row owns a read-only implicitWidth (QQuickImplicitSizeItem, Qt 6.11).
# This disposable control binds its writable width so the bar builds.
# Its transitions must then fail the same cold vertical-alignment reader.
# https://github.com/qt/qtdeclarative/blob/6.11/src/quick/items/qquickimplicitsizeitem_p.h
bar_alignment_misplaced() {
  bar_alignment | py_reply 'import json,sys; rows=json.load(sys.stdin); print(any(s.startswith("clock.label.y=") for s in rows) and any(s.startswith("pill0.y=") for s in rows))'
}
if copy_tree bar-motion-control \
  && edit_tree bar-motion-control shell/plugins/vgs.bar/Bar.qml '    Item {
        id: left
        readonly property real spacing: Theme.bar.gap' '    Row {
        move: Transition { NumberAnimation { properties: "x"; duration: 0 } }
        add: Transition { NumberAnimation { properties: "x"; duration: 0 } }
        id: left
        spacing: Theme.bar.gap' \
  && edit_tree bar-motion-control shell/plugins/vgs.bar/Bar.qml '    Item {
        id: center
        readonly property real spacing: Theme.bar.gap' '    Row {
        move: Transition { NumberAnimation { properties: "x"; duration: 0 } }
        add: Transition { NumberAnimation { properties: "x"; duration: 0 } }
        id: center
        spacing: Theme.bar.gap' \
  && edit_tree bar-motion-control shell/plugins/vgs.bar/Bar.qml '    Item {
        id: right
        readonly property real spacing: Theme.bar.gap' '    Row {
        move: Transition { NumberAnimation { properties: "x"; duration: 0 } }
        add: Transition { NumberAnimation { properties: "x"; duration: 0 } }
        id: right
        spacing: Theme.bar.gap' \
  && edit_tree bar-motion-control shell/Core/Plugins.qml 'container.implicitWidth = Qt.binding(() => {' 'container.width = Qt.binding(() => {'; then
  stop_shell
  start_shell "$sandbox/tree-bar-motion-control" "$sandbox/bar-motion-control.log" || fail "the Row motion control shell starts"
  expect_poll "control: the cold Row builds its bar surface" "$monitors" bar_count
  printf "  cold_control_log=%s\n" "$sandbox/bar-motion-control.log"
  expect_builtins "control: the Row motion bar still registers both builtins" '["vgs.bar/center-clock","vgs.bar/left-workspaces"]'
  printf '  cold_control_alignment=%s\n' "$(bar_alignment)"
  geometry expect "control: the alignment reader rejects Row's cold transition writes" True bar_alignment_misplaced
  stop_shell
  start_shell "$repo" "$sandbox/bar-motion-restored.log" || fail "the shell starts after the Row motion control"
  geometry expect_poll "the restored cold bar centers both builtin contents" '[]' bar_alignment
fi

# Gaps and separators: a right click on the empty bar opens the bar's own
# menu, Add separator first and Add gap second; the entry lands where a
# widget dragged to the click would drop. Each kind is added in every
# section through the real pointer and keys, read back from the effective
# layout and the drawn boxes, kept across a restart, dragged into another
# section and removed through its frame menu's first entry. The first
# control runs a copy whose core catalogue leaves out the bar's families:
# the entry is written but never drawn, so the drawn reader fails. The
# second runs a copy whose separator line sits at the bar's top in the
# input boundary colour, and the drawn reader names both faults.
spacer_saved="$sandbox/bar-spacer-saved.json"
cp -- "$home/.config/vgshell/shell.json" "$spacer_saved"
spacer_pattern='^vgs\.bar/(gap|separator)-[1-9][0-9]*$'
# The spacer ids of FILE's layout (the effective layout when FILE is
# absent), per section, in order.
spacer_layout() {
  if [[ -n ${1:-} ]]; then cat -- "$1"; else ipc shell listShellConfig; fi | py_reply 'import json,re,sys
l=json.load(sys.stdin).get("bar",{}).get("layout",{})
print(json.dumps({s:[e["id"] for e in l.get(s,[]) if re.match(sys.argv[1],e["id"])] for s in ("left","center","right")}))' "$spacer_pattern"
}
spacer_user() { spacer_layout "$home/.config/vgshell/shell.json"; }
# A point on the empty bar in SECTION: past the end of the left section,
# or before the start of the centre or right one, inside that third.
spacer_point() {
  local key bar sec
  key="$(bar_key)" || return 1
  bar="$(ipc smoke instanceGeometry "$key" vgs.bar)" && sec="$(ipc smoke barSectionGeometry "$key" "$1")" || return 1
  py_reply 'import json,sys
bar=json.loads(sys.argv[1]); sec=json.load(sys.stdin); s=sys.argv[2]; room=8
x=sec[0]+sec[2]+room if s=="left" else sec[0]-room
low,high={"left":(0,1),"center":(1,2),"right":(2,3)}[s]
if not bar[0]+bar[2]*low/3<x<bar[0]+bar[2]*high/3: sys.exit("spacer_point: refused: section=%s crowded" % s)
print("%d %d" % (x,bar[1]+bar[3]/2))' "$bar" "$1" <<<"$sec"
}
spacer_read() { ipc smoke readInstance "$(bar_key)" vgs.bar "$1"; }
spacer_entries() { spacer_read spacerMenuEntries | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
# spacer_add SECTION KIND: the right click and the menu entry for KIND.
spacer_add() {
  local x y
  read -r x y < <(spacer_point "$1") && [[ $x =~ ^-?[0-9]+$ && $y =~ ^-?[0-9]+$ ]] || { fail "no empty point in the $1 section"; return 1; }
  hover "$((x + 1))" "$y" && right_click "$x" "$y" || { fail "the right click on the empty $1 bar failed"; return 1; }
  expect_poll "a right click on the empty $1 bar opens the add menu" true spacer_read spacerMenuOpen
  expect "the add menu holds its two entries" 2 spacer_entries
  if [[ $2 == gap ]]; then type_keys -k Down -k Return; else type_keys -k Return; fi
  expect_poll "choosing Add $2 closes the add menu" false spacer_read spacerMenuOpen
}
# The drawn spacers per section, in x order, and every box that breaks
# its size: a gap `bar.spacer.gap` wide, a separator its line plus
# `bar.spacer.inset` a side, the line `divider.thickness` by
# `bar.spacer.height` (`:line`), centred on the bar within 1 px
# (`:centre`), in `bar.foreground` at 0x33 alpha within 1 (`:colour`),
# each inside its section.
spacer_rendered() {
  local key records ids id rows="" section box tokens text
  key="$(bar_key)" && records="$(ipc shell built)" && box="$(ipc smoke instanceGeometry "$key" vgs.bar)" || return 1
  rows+="bar $box"$'\n'
  ids="$(py_reply 'import json,re,sys; print(" ".join(r["id"] for r in json.load(sys.stdin)[sys.argv[1]] if re.match(sys.argv[2],r["id"])))' "$key" "$spacer_pattern" <<<"$records")" || return 1
  for section in left center right; do
    box="$(ipc smoke barSectionGeometry "$key" "$section")" || return 1
    rows+="$section $box"$'\n'
  done
  for id in $ids; do
    box="$(ipc smoke itemColours "$key" "$id" BarWidget QQuickRectangle)" || return 1
    rows+="$id:colour $box"$'\n'
    box="$(ipc smoke descendantGeometry "$key" "$id")" || return 1
    rows+="$id $box"$'\n'
  done
  tokens="$(for t in bar.spacer.gap bar.spacer.inset bar.spacer.height divider.thickness; do ipc smoke themeValue "$t" || exit 1; done | paste -sd ' ')" \
    && text="$(ipc smoke themeValue bar.foreground)" || return 1
  py_reply 'import json,sys
gap,inset,height,thick=[float(v) for v in sys.argv[1].split()]
# themeValue writes the Qt form #aarrggbb, itemColours #rrggbbaa.
text=json.loads(sys.argv[2])[3:].lower()
sections={}; drawn={"left":[],"center":[],"right":[]}; errors=[]; bar=None; colours={}
for line in sys.stdin:
    if not line.strip(): continue
    ident,value=line.split(" ",1); value=json.loads(value) if value[:1] in "[{" else None
    if ident=="bar": bar=value; continue
    if ident in drawn: sections[ident]=value; continue
    if ident.endswith(":colour"): colours[ident[:-7]]=value; continue
    if not value: errors.append(ident+":absent"); continue
    box=value[0]["box"]
    home=[s for s,b in sections.items() if b and box[0]>=b[0]-1 and box[0]+box[2]<=b[0]+b[2]+1 and box[2]>0]
    if len(home)!=1: errors.append(ident+":outside-section"); continue
    drawn[home[0]].append((box[0],ident))
    lines=[r for r in value if r["type"] in ("QQuickRectangle","Rectangle") and r.get("visible",True)]
    if "/gap-" in ident:
        if abs(box[2]-gap)>0.5 or lines: errors.append(ident+":gap")
    else:
        want=2*inset+thick
        if abs(box[2]-want)>0.5 or len(lines)!=1: errors.append(ident+":separator"); continue
        l=lines[0]["box"]
        if abs(l[0]-box[0]-inset)>0.5 or abs(l[2]-thick)>0.5 or abs(l[3]-height)>0.5: errors.append(ident+":line")
        if not bar or abs(l[1]+l[3]/2-(bar[1]+bar[3]/2))>1: errors.append(ident+":centre")
        drew=[c for item in colours.get(ident) or [] for c in item]
        if len(drew)!=1 or drew[0][1:7].lower()!=text or abs(int(drew[0][7:9],16)-0x33)>1: errors.append(ident+":colour")
print(json.dumps({"drawn":{s:[i for _,i in sorted(v)] for s,v in drawn.items()},"errors":errors}))' "$tokens" "$text" <<<"$rows"
}
# spacer_faults ID: the kinds of size error the drawn reader finds on ID.
spacer_faults() {
  spacer_rendered | py_reply 'import json,sys; print(json.dumps(sorted(e.split(":")[-1] for e in json.load(sys.stdin)["errors"] if e.rsplit(":",1)[0]==sys.argv[1])))' "$1"
}
# spacer_drawn WANT_LAYOUT_JSON: True when the drawn spacers match WANT
# with no size errors.
spacer_drawn() {
  spacer_rendered | py_reply 'import json,sys; d=json.load(sys.stdin); print(d["drawn"]==json.loads(sys.argv[1]) and not d["errors"])' "$1"
}
# spacer_centre ID: the centre of ID's box on the first bar.
spacer_centre() { ipc smoke instanceGeometry "$(bar_key)" "$1" | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print("%d %d" % (x+w/2,y+h/2))'; }
spacer_holds() { spacer_layout | py_reply 'import json,sys; print(any(sys.argv[1] in ids for ids in json.load(sys.stdin).values()))' "$1"; }
spacer_remove() {
  local x y
  read -r x y < <(spacer_centre "$1") || { fail "$1 has no box to right-click"; return 1; }
  hover "$((x + 1))" "$y" && right_click "$x" "$y" || { fail "the right click on $1 failed"; return 1; }
  expect_poll "a right click on $1 opens its frame menu" true ipc smoke readInstance "$(bar_key)" "$1" frameMenuOpen
  type_keys -k Return
}
spacer_none='{"left": [], "center": [], "right": []}'
expect "the smoke profile starts with no spacer" "$spacer_none" spacer_layout
for spacer_section in left center right; do
  for spacer_kind in separator gap; do spacer_add "$spacer_section" "$spacer_kind"; done
done
# Left appends at its end; centre and right insert before their first
# widget, so the later gap stands before the earlier separator.
spacer_added='{"left": ["vgs.bar/separator-1", "vgs.bar/gap-1"], "center": ["vgs.bar/gap-2", "vgs.bar/separator-2"], "right": ["vgs.bar/gap-3", "vgs.bar/separator-3"]}'
expect_poll "each kind lands in each section where it was added" "$spacer_added" spacer_layout
expect "the user file holds the added spacers" "$spacer_added" spacer_user
expect_builtins "every bar registers each spacer once beside the fixed builtins" '["vgs.bar/center-clock","vgs.bar/gap-1","vgs.bar/gap-2","vgs.bar/gap-3","vgs.bar/left-workspaces","vgs.bar/separator-1","vgs.bar/separator-2","vgs.bar/separator-3"]'
# The drawn order holds the same members; every section draws a spacer,
# within left the spacers end the section, within centre and right they
# start it.
spacer_edges() {
  local key records ids id rows="" box
  key="$(bar_key)" && records="$(ipc shell built)" || return 1
  ids="$(py_reply 'import json,sys; print(" ".join(r["id"] for r in json.load(sys.stdin)[sys.argv[1]] if r["origin"]=="plugin" or r["kind"]=="bar-widget"))' "$key" <<<"$records")" || return 1
  for id in left center right; do rows+="$id $(ipc smoke barSectionGeometry "$key" "$id")"$'\n'; done
  for id in $ids; do
    box="$(ipc smoke instanceGeometry "$key" "$id")" && [[ "$(ipc smoke readInstance "$key" "$id" visible)" == true ]] || continue
    rows+="$id $box"$'\n'
  done
  py_reply 'import json,re,sys
sections={}; order={"left":[],"center":[],"right":[]}
for line in sys.stdin:
    if not line.strip(): continue
    ident,value=line.split(" ",1); box=json.loads(value) if value.startswith("[") else None
    if ident in order: sections[ident]=box; continue
    if box is None or box[2]<=0: continue
    for s,b in sections.items():
        if b and box[0]>=b[0]-1 and box[0]+box[2]<=b[0]+b[2]+1: order[s].append((box[0],ident))
ids={s:[i for _,i in sorted(v)] for s,v in order.items()}
spacer=lambda i: re.match(sys.argv[1],i) is not None
n={s:len([i for i in v if spacer(i)]) for s,v in ids.items()}
print(all(n.values()) and all(spacer(i) for i in ids["left"][len(ids["left"])-n["left"]:]) and all(spacer(i) for s in ("center","right") for i in ids[s][:n[s]]))' "$spacer_pattern" <<<"$rows"
}
geometry expect_poll "the added spacers draw at the drop places with their token sizes" True spacer_drawn "$spacer_added"
geometry expect_poll "left spacers end their section, centre and right ones start theirs" True spacer_edges
stop_shell
start_shell "$repo" "$sandbox/bar-spacer-restart.log" || fail "the shell starts again over the added spacers"
expect_poll "the spacers keep their places across a restart" "$spacer_added" spacer_layout
geometry expect_poll "the restarted bar draws every spacer again" True spacer_drawn "$spacer_added"
# A drag moves each kind into another section as it moves any widget:
# the left separator past the right section's last widget, the centre gap
# to the start of the left section.
spacer_drag() { # ID SECTION end|start
  local x y x2 y2
  read -r x y < <(spacer_centre "$1") || return 1
  read -r x2 y2 < <(ipc smoke barSectionGeometry "$(bar_key)" "$2" | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print("%d %d" % (x+w-2 if sys.argv[1]=="end" else x+2, y+h/2))' "$3") || return 1
  hover "$((x + 1))" "$y" && drag "$x" "$y" "$x2" "$y2"
}
spacer_drag vgs.bar/separator-1 right end || fail "the separator drag failed"
spacer_drag vgs.bar/gap-2 left start || fail "the gap drag failed"
spacer_moved='{"left": ["vgs.bar/gap-2", "vgs.bar/gap-1"], "center": ["vgs.bar/separator-2"], "right": ["vgs.bar/gap-3", "vgs.bar/separator-3", "vgs.bar/separator-1"]}'
expect_poll "a drag moves a separator and a gap into other sections" "$spacer_moved" spacer_layout
expect "the user file holds the moved spacers" "$spacer_moved" spacer_user
geometry expect_poll "the moved spacers draw in their new sections" True spacer_drawn "$spacer_moved"
for spacer_id in vgs.bar/separator-1 vgs.bar/gap-2 vgs.bar/separator-2 vgs.bar/gap-1 vgs.bar/separator-3 vgs.bar/gap-3; do
  spacer_remove "$spacer_id"
  expect_poll "the frame menu's first entry removes $spacer_id" False spacer_holds "$spacer_id"
done
expect_poll "removing every spacer leaves none in the layout" "$spacer_none" spacer_layout
expect "the user file holds no spacer" "$spacer_none" spacer_user
expect_builtins "removed spacers release their registrations" '["vgs.bar/center-clock","vgs.bar/left-workspaces"]'
stop_shell
if copy_tree bar-spacer-control \
  && edit_tree bar-spacer-control shell/Core/Plugins.qml 'return bar.builtinNames.concat(Logic.placedFamilyNames(Config.effective, row.id, families));' 'return bar.builtinNames;'; then
  start_shell "$sandbox/tree-bar-spacer-control" "$sandbox/bar-spacer-control.log" || fail "the spacer control shell starts"
  spacer_add left separator
  expect_poll "control: Add separator still writes its entry" '{"left": ["vgs.bar/separator-1"], "center": [], "right": []}' spacer_layout
  # The real bar draws an added entry within the reconcile its write
  # starts; the control's must stay undrawn across the harness's polls.
  spacer_ever_drawn() {
    smoke_poll_tries 200
    for _ in $(seq 1 "$smoke_poll_n"); do
      [[ "$(spacer_drawn "$1")" == True ]] && { echo True; return; }
      sleep 0.2
    done
    echo False
  }
  geometry expect "control: the drawn reader rejects a separator the catalogue leaves out" False spacer_ever_drawn '{"left": ["vgs.bar/separator-1"], "center": [], "right": []}'
  stop_shell
fi
if copy_tree bar-separator-control \
  && edit_tree bar-separator-control shell/plugins/vgs.bar/Builtin.qml 'anchors.verticalCenter: parent.verticalCenter' 'y: 0' \
  && edit_tree bar-separator-control shell/plugins/vgs.bar/Builtin.qml 'color: Commons.Theme.bar.spacer.line' 'color: Commons.Theme.color.borderControl'; then
  start_shell "$sandbox/tree-bar-separator-control" "$sandbox/bar-separator-control.log" || fail "the separator control shell starts"
  # The first control leaves its separator in the user file.
  [[ "$(spacer_holds vgs.bar/separator-1)" == True ]] || spacer_add left separator
  geometry expect_poll "control: the drawn reader names a separator off the bar's centre and in another colour" '["centre", "colour"]' spacer_faults vgs.bar/separator-1
  stop_shell
fi
cp -- "$spacer_saved" "$home/.config/vgshell/shell.json.tmp"
mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
start_shell "$repo" "$sandbox/bar-spacer-restored.log" || fail "the shell returns after the spacer checks"
expect_poll "the restored profile holds no spacer" "$spacer_none" spacer_layout
