# inputs: shell/plugins/vgs.launcher/* shell/plugins/vgs.tray/* scripts/smoke/fixtures/tray/* scripts/smoke/fixtures/devices/hid-world.json scripts/smoke/fixtures/devices/hid-fake.py config/shell.json shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/plugins/vgs.sound/* shell/plugins/vgs.network/* shell/plugins/vgs.bluetooth/* shell/plugins/vgs.displays/* shell/plugins/vgs.keyboard/* shell/plugins/vgs.tailscale/* shell/plugins/vgs.vpn/* shell/plugins/vgs.sudo/* shell/plugins/vgs.mouse/* shell/plugins/vgs.bar/* scripts/smoke/fixtures/plugins/acme.tick/* scripts/smoke/fixtures/plugins/acme.idle/* shell/Hosts/BarHost.qml shell/Ui/controls/BarItem.qml shell/Ui/BarWidget.qml shell/Core/Plugins.qml shell/Core/Config.qml shell/Commons/Workspaces.qml shell/Commons/Time.qml shell/plugins/*/manifest.json shell/Core/Capabilities.qml shell/Ui/overlay/Menu.qml shell/Ui/overlay/MenuItem.qml shell/Commons/Tokens.js shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Service.qml shell/plugins/vgs.settings/Widget.qml shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/PageHeader.qml shell/plugins/vgs.settings/EditSet.qml shell/plugins/vgs.settings/Steps.js shell/plugins/vgs.settings/StatusRow.qml shell/plugins/vgs.settings/StatusLine.qml shell/plugins/vgs.settings/RequirementRow.qml shell/plugins/vgs.agent-warden/* shell/plugins/vgs.ai-usage/* shell/plugins/vgs.capture/* shell/plugins/vgs.jarvis/* shell/plugins/vgs.power/* shell/plugins/vgs.traffic/* shell/plugins/vgs.updates/* shell/plugins/vgs.voice/* shell/plugins/vgs.sysmon/* shell/Ui/controls/IconButton.qml shell/Ui/controls/Button.qml shell/Hosts/SummonPopup.qml shell/Commons/DesktopLaunch.js shell/Commons/AnchorTracker.qml scripts/smoke/fixtures/plugins/acme.tiplink/* shell/Ui/overlay/Tooltip.qml shell/Ui/feedback/LinkText.qml shell/Commons/PageReference.js shell/Hosts/NoticeHost.qml shell/Core/KeyCapture.qml shell/Core/HyprlandLayer.qml
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
  py_dumps "$bar_box" "$ws" "$clock" "$pad" "$gap" "$floor" <<'PY'
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
# A bar item draws its text and count as Readings (BarItem.qml), Labels
# that hold a sample width.
text_types = ("Label", "Reading")
def within(rows, i, kinds):
    found, frontier = [], [i]
    while frontier:
        at = frontier.pop()
        for j, c in enumerate(rows):
            if c["parent"] == at:
                frontier.append(j)
                if c["type"] in kinds and c.get("visible", True): found.append(c)
    return found
centre = bar[1] + bar[3] / 2
for name, rows in (("workspaces", ws), ("clock", clock)):
    roles = sorted({str(r.get("role")) for r in rows if r["type"] in text_types})
    if roles != ["bar"]: out.append("%s roles=%s" % (name, roles))
pills = sorted(((r, [l for l in within(ws, i, text_types) if l["box"][2] > 0]) for i, r in enumerate(ws) if r["type"] == "BarItem"), key=lambda p: p[0]["box"][0])
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
clock_labels = [r for r in clock if r["type"] in text_types and r["visible"]]
if len(clock_labels) != 1: out.append("clock labels=%d" % len(clock_labels))
for label in clock_labels: check("clock.label.y", mid_y(label), centre)
print(json.dumps(out))
PY
}
geometry expect_poll "the workspace pills and the clock share the bar's centre" '[]' bar_alignment

expect "the core built the bar, its placed widget and the vgs.themes background per screen, the vgs.bar, vgs.themes, vgs.windows and always-on vgs.settings services once each, and no built-in" "$((3 * monitors + 4))" builds
calendar_want() { # OFFSET [TODAY]
  python3 -c 'import datetime,sys
t=datetime.date.today(); n=t.year*12+t.month-1+int(sys.argv[1])
names="January February March April May June July August September October November December".split()
mark=sys.argv[2] if len(sys.argv)>2 else (str(t.day) if sys.argv[1]=="0" else "none")
print("%s %d cells=42 today=%s" % (names[n%12], n//12, mark))' "$@"
}
calendar_read() {
  local labels days fill
  labels="$(ipc smoke itemValues panel vgs.bar Label objectName,text)" || return
  days="$(ipc smoke itemValues panel vgs.bar Button text,fill)" || return
  fill="$(ipc smoke themeValue button.variant.primary.background)" || return
  python3 - "$labels" "$days" "$fill" <<'PY'
import json, sys
if sys.argv[1] == "absent" or sys.argv[2] == "absent":
    print("closed")
    sys.exit()
labels, days, fill = (json.loads(a) for a in sys.argv[1:])
def opaque(colour):
    colour = str(colour).lower()
    return colour[-6:] if len(colour) == 7 or colour[1:3] == "ff" else None
title = [label["text"] for label in labels if label["objectName"] == "calendarTitle"]
marked = [day["text"] for day in days if opaque(day["fill"]) == opaque(fill)]
print("%s cells=%d today=%s" % (title[0] if title else "untitled", len(days), ",".join(marked) or "none"))
PY
}
calendar_click_box() {
  local x y
  [[ $1 == \[* ]] || return 1
  read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x + w / 2), int(y + h / 2))' "$1") || return
  click "$x" "$y" && echo ok
}
calendar_summon() { ipc shell summon panel vgs.bar '{}'; }
calendar_day() { calendar_click_box "$(ipc smoke itemGeometry panel vgs.bar Button "$1")"; }

# Later rows read the private device world even when bar controls do not run.
bar_devices_ready=false
if devices_ready bar; then bar_devices_ready=true; fi
