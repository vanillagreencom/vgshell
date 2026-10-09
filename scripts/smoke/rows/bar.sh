# inputs: shell/plugins/vgs.launcher/* shell/plugins/vgs.tray/* scripts/smoke/fixtures/tray/* config/shell.json shell/Core/PluginLogic.js shell/plugins/vgs.sound/* shell/plugins/vgs.network/* shell/plugins/vgs.bluetooth/* shell/plugins/vgs.displays/* shell/plugins/vgs.keyboard/* shell/plugins/vgs.vpn/* shell/plugins/vgs.sudo/* shell/plugins/vgs.mouse/* shell/plugins/vgs.bar/* scripts/smoke/fixtures/plugins/acme.tick/* scripts/smoke/fixtures/plugins/acme.idle/* shell/Hosts/BarHost.qml shell/Ui/controls/BarItem.qml shell/Ui/BarWidget.qml shell/Core/Plugins.qml shell/Core/Config.qml shell/Commons/Workspaces.qml shell/Commons/Time.qml shell/plugins/*/manifest.json shell/Core/Capabilities.qml shell/Ui/overlay/Menu.qml shell/Ui/overlay/MenuItem.qml shell/Commons/Tokens.js shell/plugins/vgs.settings/* shell/plugins/vgs.agent-warden/* shell/plugins/vgs.ai-usage/* shell/plugins/vgs.capture/* shell/plugins/vgs.jarvis/* shell/plugins/vgs.power/* shell/plugins/vgs.traffic/* shell/plugins/vgs.updates/* shell/plugins/vgs.voice/* shell/plugins/vgs.sysmon/* shell/Ui/controls/IconButton.qml shell/Ui/controls/Button.qml shell/Hosts/SummonPopup.qml shell/Commons/DesktopLaunch.js
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

bar_font_family() { ipc smoke readInstance "$(bar_key)" vgs.bar fontFamily; }
expect "the bar API names the family of the bar role" '"JetBrains Mono"' bar_font_family
expect "the core built the bar, its placed widget and the vgs.themes background per screen, the vgs.bar, vgs.themes and always-on vgs.settings services once each, and no built-in" "$((3 * monitors + 3))" builds
# The clock's calendar, the bar's panel: a click on the clock opens it on
# this month, Left and Right and its month buttons switch the month, a
# click on a day opens that day in the default web calendar and closes it,
# and Escape or a second click on the clock closes it. The reading is the
# drawn title, the count of day buttons and the days whose button takes
# the primary fill: Qt's month grid holds 42 days for every month, so the
# calendar keeps one height, and today is marked in its own month alone.
# calendar_off counts the day buttons off the bar's screen. calendar_want
# names the reading for the month OFFSET from this one, with today's day
# unless a second argument replaces it. The sandbox runs in the C locale,
# whose month names are English.
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
calendar_off() {
  local rows bar_box
  rows="$(ipc smoke descendantGeometry panel vgs.bar)" || return
  bar_box="$(ipc smoke instanceGeometry "$(bar_key)" vgs.bar)" || return
  python3 - "$rows" "$bar_box" <<'PY'
import json, sys
if sys.argv[1] == "absent":
    print("closed")
    sys.exit()
rows, bar = (json.loads(a) for a in sys.argv[1:])
print(len([1 for r in rows if r["type"] == "Button" and (r["box"][0] < bar[0] or r["box"][0] + r["box"][2] > bar[0] + bar[2] or r["box"][1] < bar[1])]))
PY
}
clock_click() {
  local box x y
  box="$(ipc smoke descendantGeometry "$(bar_key)" vgs.bar/center-clock | py_reply 'import json,sys; print(json.dumps(next(r["box"] for r in json.load(sys.stdin) if r["type"] == "BarItem")))')" || return
  read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x + w / 2), int(y + h / 2))' "$box") || return
  click "$x" "$y" && echo ok
}
# A click at the centre of BOX, a [x, y, w, h] reading, or no click when
# the box is absent.
calendar_click_box() {
  local x y
  [[ $1 == \[* ]] || return 1
  read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x + w / 2), int(y + h / 2))' "$1") || return
  click "$x" "$y" && echo ok
}
calendar_keys() { type_keys "$@" && echo ok; }
# Each day's number sits at its square's centre both ways, one digit or
# two: the ink box of the number inside each day button against the
# button's box, within 1 px. The reading lists the off-centre numbers as
# [text, dx, dy], so [] is the pass; a button with no number in it reads
# as missing.
calendar_off_centre() {
  local rows inks
  rows="$(ipc smoke descendantGeometry panel vgs.bar)" || return
  inks="$(ipc smoke textInk panel vgs.bar Label)" || return
  python3 - "$rows" "$inks" <<'PY'
import json, sys
if "absent" in sys.argv[1:]:
    print("closed")
    sys.exit()
rows, inks = (json.loads(a) for a in sys.argv[1:])
out = []
for button in (r for r in rows if r["type"] == "Button"):
    x, y, w, h = button["box"]
    inside = [i for i in inks if i["text"] == button["text"] and x <= i["ink"][0] + i["ink"][2] / 2 <= x + w and y <= i["ink"][1] + i["ink"][3] / 2 <= y + h]
    if len(inside) != 1:
        out.append([button["text"], "missing"])
        continue
    ix, iy, iw, ih = inside[0]["ink"]
    dx, dy = round(ix + iw / 2 - (x + w / 2), 2), round(iy + ih / 2 - (y + h / 2), 2)
    if abs(dx) > 1 or abs(dy) > 1:
        out.append([button["text"], dx, dy])
print(json.dumps(out))
PY
}
# The off-centre numbers a control planted: True once a one-digit and a
# two-digit number both read off centre on AXIS (0 across, 1 down).
calendar_off_axis() { # AXIS
  calendar_off_centre | py_reply 'import json,sys
t=sys.stdin.read().strip(); rows=[] if t=="closed" else json.loads(t); axis=int(sys.argv[1])
off={r[0] for r in rows if r[1]!="missing" and abs(r[1+axis])>1}
print(any(len(n)==1 for n in off) and any(len(n)==2 for n in off))' "$1"
}
# The controls run on a shell just started, whose bar can take a click
# before the compositor maps it, so they build the same Calendar.qml through
# the core's summon, unanchored in the layer host, not under the clock.
calendar_summon() { ipc shell summon panel vgs.bar '{}'; }
# A key press can be lost before the new layer has the keyboard, so the
# control presses Left again, each press given 3 s, only while the title
# still names this month: a second press never runs after the first moved
# the month.
calendar_back() {
  local this _ i
  this="$(calendar_want 0 | cut -d' ' -f1,2)"
  for _ in 1 2 3 4 5; do
    calendar_keys -k Left >/dev/null || return
    for i in $(seq 1 15); do
      [[ $(calendar_read | cut -d' ' -f1,2) == "$this" ]] || { echo ok; return; }
      sleep 0.2
    done
  done
  echo unmoved
}
calendar_button() { calendar_click_box "$(ipc smoke labelledGeometry panel vgs.bar IconButton "$1")"; }
calendar_day() { calendar_click_box "$(ipc smoke itemGeometry panel vgs.bar Button "$1")"; }
expect "a click on the clock reaches it" ok clock_click
expect_poll "the calendar opens on this month with today marked" "$(calendar_want 0)" calendar_read
geometry expect_poll "every day's number sits at its square's centre both ways" '[]' calendar_off_centre
expect "Right reaches the calendar" ok calendar_keys -k Right
expect_poll "Right shows the next month with no day marked" "$(calendar_want 1)" calendar_read
expect "Left twice reaches the calendar" ok calendar_keys -k Left -k Left
expect_poll "Left twice shows the previous month with no day marked" "$(calendar_want -1)" calendar_read
expect "Next month is pressed" ok calendar_button "Next month"
expect_poll "Next month returns to this month with today marked" "$(calendar_want 0)" calendar_read
expect "Previous month is pressed" ok calendar_button "Previous month"
expect_poll "Previous month shows the previous month" "$(calendar_want -1)" calendar_read
expect "a second click on the clock reaches it" ok clock_click
expect_poll "a second click on the clock closes the calendar" closed calendar_read
expect "a third click on the clock reaches it" ok clock_click
expect_poll "the calendar opens on this month again" "$(calendar_want 0)" calendar_read
expect "Escape reaches the calendar" ok calendar_keys -k Escape
expect_poll "Escape closes the calendar" closed calendar_read
# A day opens through `gio open`, which the shell resolves to the device
# fakes' stand-in (scripts/smoke/devices.sh), which records its argv, so no
# browser starts; with gio resolving anywhere else the row clicks no day.
# The day is in the next month and its number is not today's, so neither
# today's month nor today's day stands in for the one clicked.
expect "the shell resolves gio to the device stand-in" "$shim/gio" shell_resolves gio
if [[ $(shell_resolves gio) == "$shim/gio" ]]; then
  calendar_gio_before="$(device_calls gio | py_reply 'import json,sys; print(len(json.load(sys.stdin)))')"
  read -r calendar_pick calendar_day_want < <(python3 -c 'import datetime,json
t=datetime.date.today(); n=t.year*12+t.month; d=14 if t.day==15 else 15
print(d, json.dumps([["open", "https://calendar.google.com/calendar/r/day/%d/%d/%d" % (n//12, n%12+1, d)]]))')
  calendar_gio_since() { device_calls gio | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[int(sys.argv[1]):]))' "$calendar_gio_before"; }
  device_reply gio 0 "" open "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])[0][1])' "$calendar_day_want")"
  expect "a click on the clock opens the calendar for a day" ok clock_click
  expect_poll "the calendar is open on this month for a day" "$(calendar_want 0)" calendar_read
  expect "Right reaches the calendar for a day" ok calendar_keys -k Right
  expect_poll "the calendar shows the next month for a day" "$(calendar_want 1)" calendar_read
  expect "day $calendar_pick of the next month is pressed" ok calendar_day "$calendar_pick"
  expect_poll "day $calendar_pick opens that day of the next month in Google Calendar" "$calendar_day_want" calendar_gio_since
  expect_poll "a day that opened closes the calendar" closed calendar_read
fi
# The clock at the left and at the right end of the bar, written into the
# user file as the Settings layout editor writes a move; the file is put
# back after. The calendar centres under the clock and slides to stay on
# the screen.
calendar_saved="$sandbox/calendar-shell.json"
cp -- "$home/.config/vgshell/shell.json" "$calendar_saved"
calendar_place() { # left|right
  python3 - "$home/.config/vgshell/shell.json" "$1" <<'PY'
import json, os, sys
path, section = sys.argv[1:]
config = json.load(open(path))
layout = config["bar"]["layout"]
for name in layout:
    layout[name] = [e for e in layout[name] if e["id"] != "vgs.bar/center-clock"]
if section == "left": layout["left"].insert(0, {"id": "vgs.bar/center-clock"})
else: layout["right"].append({"id": "vgs.bar/center-clock"})
with open(path + ".tmp", "w") as out: json.dump(config, out)
os.replace(path + ".tmp", path)
PY
}
# Where the clock's middle stands on the bar: left, center or right third.
clock_third() {
  local key bar_box clock
  key="$(bar_key)" || return
  bar_box="$(ipc smoke instanceGeometry "$key" vgs.bar)" || return
  clock="$(ipc smoke descendantGeometry "$key" vgs.bar/center-clock)" || return
  python3 - "$bar_box" "$clock" <<'PY'
import json, sys
bar, rows = (json.loads(a) for a in sys.argv[1:])
box = next(r["box"] for r in rows if r["type"] == "BarItem")
share = (box[0] + box[2] / 2 - bar[0]) / bar[2]
print("left" if share < 1 / 3 else "right" if share > 2 / 3 else "center")
PY
}
for calendar_section in left right; do
  calendar_place "$calendar_section"
  geometry expect_poll "the clock moves to the $calendar_section end" "$calendar_section" clock_third
  expect "a click on the clock at the $calendar_section end reaches it" ok clock_click
  expect_poll "at the $calendar_section end the calendar opens on this month" "$(calendar_want 0)" calendar_read
  geometry expect_poll "at the $calendar_section end every day stays on the bar's screen" 0 calendar_off
  expect "Escape reaches the calendar at the $calendar_section end" ok calendar_keys -k Escape
  expect_poll "Escape closes the calendar at the $calendar_section end" closed calendar_read
done
cp -- "$calendar_saved" "$home/.config/vgshell/shell.json.tmp"
mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
geometry expect_poll "the clock returns to the centre" center clock_third

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
  # A zone that would run into its neighbour clips to the room from its
  # bar edge to the centre, less the gap, and scrolls by whole widgets
  # (Bar.qml's Zone). The owner's own layout, 16 widgets in the right
  # section with every System Monitor reading on, over the default set,
  # which enables each of them. The sandbox's stand-ins draw narrower than
  # his live widgets, which run into the clock at his 2560 logical pixels,
  # so the row holds 1600, where the stand-ins run into it too. System
  # Monitor and Network Traffic hold One line, the widths the walks below
  # count widgets by; their Stacked default draws narrower.
  zone_right='["vgs.vpn","vgs.network","vgs.bluetooth","vgs.sound","vgs.displays","vgs.keyboard","vgs.settings","vgs.agent-warden","vgs.ai-usage","vgs.capture","vgs.jarvis","vgs.power","vgs.traffic","vgs.updates","vgs.voice","vgs.sysmon"]'
  # zone_plant [N]: the owner's layout in the user file, the first N of
  # his right widgets alone when N is given, the rest off the bar;
  # zone_planted names those placed.
  zone_plant() {
    zone_planted="$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); print(json.dumps(r[:int(sys.argv[2])] if sys.argv[2] else r))' "$zone_right" "${1:-}")" || return 1
    python3 - "$home/.config/vgshell/shell.json" "$zone_planted" "$zone_right" <<'PYZONE'
import json, os, sys
path, right, owner = sys.argv[1], json.loads(sys.argv[2]), json.loads(sys.argv[3])
config = json.load(open(path))
# A widget off the layout with a plugins row stays off the bar, as the
# owner's Passwordless Sudo does; with none, first presence places it.
rows = config.setdefault("plugins", [])
held = {r["id"] for r in rows}
rows += [{"id": i} for i in owner + ["vgs.sudo"] if i not in right and i not in held]
entries = [{"id": i} for i in right]
for entry in entries:
    if entry["id"] == "vgs.sysmon":
        entry.update({"cpuTemperature": True, "gpuTemperature": True, "showSwap": True, "showMemory": True, "memoryUnit": "percent", "layout": "One line"})
    if entry["id"] == "vgs.traffic":
        entry["layout"] = "One line"
config["bar"] = {"id": "vgs.bar", "layout": {"left": [{"id": "vgs.launcher"}, {"id": "vgs.bar/left-workspaces"}, {"id": "vgs.tray"}],
                                             "center": [{"id": "vgs.bar/center-clock"}], "right": entries}}
with open(path + ".tmp", "w") as out:
    json.dump(config, out)
os.replace(path + ".tmp", path)
PYZONE
  }
  # Whether the first bar mounted the planted right section in its order.
  zone_mounted() {
    ipc smoke barParticipationGeometry "$(bar_key)" | py_reply 'import json,sys
d=json.load(sys.stdin); want=json.loads(sys.argv[1])
if not isinstance(d,dict): print("absent"); sys.exit()
ids=[e["id"] for s in d["sections"] if s["section"]=="right" for e in s["entries"] if e["present"]]
print([i for i in ids if i in want]==want)' "$zone_planted"
  }
  # The first bar's side zones as one JSON object: per zone its view in
  # screen coordinates, whether it clips, whether it draws flush with its
  # section as before, which buttons show, the widgets it draws over the
  # centre section or the gap beside it, the widgets whose left edge
  # meets the view's start and whose right edge meets its end, each beside
  # a shown button's fade, the widgets it shows whole and its drawn
  # widgets in order; `centre` is the centre section's box and `settled`
  # whether every zone's scroll has finished drawing.
  zone_read() {
    local key bar part zones buttons
    key="$(bar_key)" || return 1
    bar="$(ipc smoke instanceGeometry "$key" vgs.bar)" && part="$(ipc smoke barParticipationGeometry "$key")" \
      && zones="$(ipc smoke itemValues "$key" vgs.bar Zone objectName,x,width,clip,inset,scroll,travel,drawnScroll)" \
      && buttons="$(ipc smoke itemValues "$key" vgs.bar BarItem objectName,visible)" || return 1
    py_reply 'import json,sys
part=json.load(sys.stdin)
if not isinstance(part,dict): print("absent"); sys.exit()
try: bar,zones,buttons=(json.loads(a) for a in sys.argv[1:4])
except ValueError: print("absent"); sys.exit()
sections={s["section"]:s for s in part["sections"]}
center=sections["center"]["drop"]; gap=sections["center"]["gap"]
named={b["objectName"]:b["visible"] for b in buttons if b["objectName"].startswith("bar-zone-")}
out={"centre":[round(center["x"],1),round(center["width"],1)],"gap":gap,"settled":all(abs(min(z["scroll"],z["travel"])-z["drawnScroll"])<0.5 for z in zones)}
for zone in zones:
    side=zone["objectName"].replace("bar-zone-","")
    x0=bar[0]+zone["x"]; x1=x0+zone["width"]
    start,end=named.get("bar-zone-%s-start" % side),named.get("bar-zone-%s-end" % side)
    # The drop reader names the widgets the section draws; their places
    # come from the section box, so a drop control leaves them true.
    drop=sections[side]["drop"]; drawn_ids={w["locator"]["id"] for w in drop["widgets"]}
    rows=[e for e in sections[side]["entries"] if e["id"] in drawn_ids]
    ids=[e["id"] for e in rows]; spans=[(drop["x"]+e["box"][0],drop["x"]+e["box"][0]+e["box"][2]) for e in rows]
    drawn=[(max(a,x0),min(b,x1)) if zone["clip"] else (a,b) for a,b in spans]
    low,high=center["x"]-gap,center["x"]+center["width"]+gap
    first=x0+(zone["inset"] if start else 0); last=x1-(zone["inset"] if end else 0)
    out[side]={"view":[round(x0,1),round(x1-x0,1)],"clips":zone["clip"],"flush":abs(x0-drop["x"])<=0.5 and abs(x1-x0-drop["width"])<=0.5,
        "start":start,"end":end,"over":[i for i,(a,b) in zip(ids,drawn) if b-a>0.5 and a<high-0.5 and b>low+0.5],
        "starts":[i for i,(a,b) in zip(ids,spans) if abs(a-first)<=1],"ends":[i for i,(a,b) in zip(ids,spans) if abs(b-last)<=1],
        "shown":[i for i,(a,b) in zip(ids,spans) if a>=first-1 and b<=last+1],"range":[round(first,1),round(last,1)],"inset":zone["inset"],"ids":ids,
        "spans":[[round(a,1),round(b-a,1)] for a,b in spans]}
print(json.dumps(out))' "$bar" "$zones" "$buttons" <<<"$part"
  }
  # zone_pick PROGRAM: PROGRAM, a Python expression over the reading `d`,
  # printed once every zone's scroll has finished drawing, or `unsettled`
  # when it has not within the bound.
  zone_pick() {
    local reading="" settled=False
    for _ in $(seq 1 50); do
      reading="$(zone_read)" || return 1
      settled="$(py_reply 'import json,sys; d=json.load(sys.stdin); print(isinstance(d,dict) and d["settled"])' <<<"$reading")"
      [[ $settled == True ]] && break
      sleep 0.1
    done
    [[ $settled == True ]] || { echo unsettled; return; }
    py_reply 'import json,sys
d=json.load(sys.stdin)
if not isinstance(d,dict): print("absent"); sys.exit()
print(eval(sys.argv[1]))' "$1" <<<"$reading"
  }
  # What a check names of SIDE's zone: whether it clips, which buttons
  # show and what it draws over the centre.
  zone_ends() { zone_pick "json.dumps([d['$1'][k] for k in ('clips','start','end','over')])"; }
  zone_shown() { zone_pick "json.dumps(d['$1']['shown'])"; }
  # One step lands a widget's edge at the end it moved toward: the start
  # beside the fade, or the zone's own edge once no button shows there.
  zone_landed() { zone_pick "bool(d['$1']['starts'] if '$2'=='start' else d['$1']['ends'])"; }
  zone_others() { zone_pick "json.dumps([d['centre'], d['left']['view'], d['left']['spans']])"; }
  # zone_button SIDE start|end: the centre of that zone button.
  zone_button() {
    zone_pick "'%d %d' % (d['$1']['view'][0]+(d['$1']['inset']-$zone_fade)/2 if '$2'=='start' else d['$1']['view'][0]+d['$1']['view'][1]-(d['$1']['inset']-$zone_fade)/2, $zone_bar_y)"
  }
  zone_press() { # SIDE start|end
    local x y
    read -r x y < <(zone_button "$1" "$2") && hover "$((x + 1))" "$y" && click "$x" "$y"
  }
  # zone_ever PROGRAM DEPTH: True once PROGRAM reads True within the poll
  # bound, False when it read and never did, `unread` when no read
  # answered. DEPTH is the subshell depth the caller reads it from, as
  # smoke_poll_tries takes it: a positive check passes it, so load cannot
  # fail it within the control bound, and a control asserting False passes
  # one less, keeping the control bound.
  zone_ever() {
    local got read=0
    smoke_poll_tries 200 "$2"
    for _ in $(seq 1 "$smoke_poll_n"); do
      got="$(zone_pick "$1")" || got=""
      [[ $got == True ]] && { echo True; return; }
      [[ $got == False ]] && read=1
      sleep 0.2
    done
    if ((read)); then echo False; else echo unread; fi
  }
  # zone_ever_true DEPTH READER...: as zone_ever, over READER's true and
  # false.
  zone_ever_true() {
    local depth="$1" got read=0
    shift
    smoke_poll_tries 200 "$depth"
    for _ in $(seq 1 "$smoke_poll_n"); do
      got="$("$@")" || got=""
      [[ $got == true ]] && { echo True; return; }
      [[ $got == false ]] && read=1
      sleep 0.2
    done
    if ((read)); then echo False; else echo unread; fi
  }
  # zone_moved SIDE PLACE DEPTH: True once SIDE's first widget stands
  # elsewhere than PLACE, the shell having taken the input.
  zone_moved() { zone_ever "json.dumps(d['$1']['spans'][0]) != '$2'" "$3"; }
  # zone_walk SIDE start|end: that button clicked while it shows, each
  # step read as landing on a widget edge: `walked`, `unmoved=<click>`,
  # `unlanded=<click>`, or `stuck` when it still shows after more clicks
  # than widgets.
  zone_walk() {
    local n place
    for ((n = 1; n <= 20; n++)); do
      place="$(zone_pick "json.dumps(d['$1']['spans'][0])")" || return 1
      zone_press "$1" "$2" || return 1
      [[ $(zone_moved "$1" "$place" 2) == True ]] || { echo "unmoved=$n"; return; }
      [[ $(zone_landed "$1" "$2") == True ]] || { echo "unlanded=$n"; return; }
      [[ $(zone_pick "d['$1']['$2']") == True ]] || { echo walked; return; }
    done
    echo stuck
  }
  # The widget of SIDE under that zone's start button, or `none`.
  zone_under_start() { zone_pick "next((i for i, (a, w) in zip(d['$1']['ids'], d['$1']['spans']) if a <= d['$1']['view'][0] + (d['$1']['inset'] - $zone_fade) / 2 <= a + w), 'none')"; }
  # zone_wheel_walk SIDE: wheel notches up over SIDE's < button while it
  # shows, each read as moving the zone: `walked over=<ids>`, naming the
  # widgets that lay under the button, or `stuck=<notch> under=<id>` when
  # a notch moved nothing.
  zone_wheel_walk() {
    local n place x y under seen=""
    for ((n = 1; n <= 20; n++)); do
      [[ $(zone_pick "d['$1']['start']") == True ]] || { echo "walked over=${seen#,}"; return; }
      place="$(zone_pick "json.dumps(d['$1']['spans'][0])")" && under="$(zone_under_start "$1")" || return 1
      seen+=",$under"
      read -r x y < <(zone_button "$1" start) || return 1
      hover "$((x + 1))" "$y" && wheel "$x" "$y" -1 || return 1
      [[ $(zone_moved "$1" "$place" 2) == True ]] || { echo "stuck=$n under=$under"; return; }
    done
    echo stuck
  }
  # zone_hold_press ID DX DY: a held press on ID's centre moved by DX, DY,
  # its pipes in zone_out and zone_in and its pid in zone_pid.
  zone_hold_press() {
    local box x y line
    box="$(ipc smoke instanceGeometry "$(bar_key)" "$1")" || return 1
    read -r x y < <(py_reply 'import json,sys; b=json.load(sys.stdin); print(int(b[0]+b[2]/2), int(b[1]+b[3]/2))' <<<"$box") || return 1
    zone_to="$((x + $2)) $((y + $3))"
    hover "$((x + 1))" "$y" || return 1
    coproc zone_held { "${shell_env[@]}" "$sandbox/click" "$x" "$y" "$mon_w" "$mon_h" drag "$((x + $2))" "$((y + $3))" hold; }
    zone_out="${zone_held[0]}" zone_in="${zone_held[1]}" zone_pid="$zone_held_PID"
    read -r -t 10 line <&"$zone_out" && [[ $line == "holding $((x + $2)) $((y + $3))" ]]
  }
  zone_release() {
    local line status=0
    printf '\n' >&"$zone_in" || status=1
    exec {zone_in}>&-
    read -r -t 10 line <&"$zone_out" || status=1
    wait "$zone_pid" || status=1
    exec {zone_out}<&-
    pointer_at="$zone_to"
    return "$status"
  }
  # Focus that moves onto a hidden widget scrolls it into view. The bar
  # holds the keyboard only while a press holds a widget, so a held press
  # on the last widget, moved down and back to its own slot, gives the
  # bar the keyboard, and the first widget, hidden at rest, takes focus.
  # A host configure that resets the held mode moves the bar under the
  # press, so a press the reset spoiled is let go and made once more on
  # the mode taken again.
  zone_focus() { # LABEL WANT
    local first last attempt depth=1
    [[ $2 == True ]] || depth=0
    for attempt in 1 2; do
      [[ $(held_mode_state) == held ]] || hold_restore >/dev/null || true
      first="$(zone_pick "d['right']['ids'][0]")" && last="$(zone_pick "d['right']['ids'][-1]")" || { fail "$1: the right zone is unreadable"; return; }
      zone_hold_press "$last" 0 12 || { fail "$1: the held press on $last"; return; }
      # The drag shows its preview gap once it starts, which the focus
      # must follow.
      [[ $(zone_ever_true 1 ipc smoke readInstance "$(bar_key)" "$last" frameDragging) == True ]] && zone_pick True >/dev/null
      ipc smoke invokeInstanceArgs "$(bar_key)" "$first" forceActiveFocus '{"args":[]}' >/dev/null
      [[ $attempt == 2 || $(zone_ever_true 1 ipc smoke readInstance "$(bar_key)" "$first" activeFocus) == True || $(held_mode_state) == held ]] && break
      type_keys -k Escape || fail "$1: Escape ends the spoiled press"
      zone_release || fail "$1: the spoiled press releases"
    done
    expect_poll "$1: the first widget holds the keyboard" true ipc smoke readInstance "$(bar_key)" "$first" activeFocus
    geometry expect "$1" "$2" zone_ever "'$first' in d['right']['shown']" "$depth"
    type_keys -k Escape || fail "$1: Escape ends the held press"
    zone_release || fail "$1: the held press releases"
  }
  # zone_pair before|past WIDTH: two neighbours the right zone shows whole
  # and the point between them, as `A B X`, past the bar's last third, or
  # left of it yet clear of the centre and of the start button once a
  # preview gap WIDTH wide widens the centre on the way.
  zone_pair() {
    zone_pick "next(('%s %s %d' % (a, b, m) for (a, sa), (b, sb) in zip(zip(d['right']['ids'], d['right']['spans']), zip(d['right']['ids'][1:], d['right']['spans'][1:])) for m in [(sa[0]+sa[1]+sb[0])/2] if a in d['right']['shown'] and b in d['right']['shown'] and (m > 2*$mon_w/3 + 2 if '$1'=='past' else d['centre'][0] + d['centre'][1] + $2 / 2 + 2 * d['gap'] + d['right']['inset'] + 8 < m < 2*$mon_w/3 - 2)), 'none')"
  }
  # zone_drop LABEL ID before|past [control]: a held press on ID, a
  # left-zone widget, moved to the point between two neighbours the right
  # zone shows, left of the bar's last third or past it; the preview gap
  # opens between them, inside the view, and the release writes ID there.
  # A press bound left of the last third crosses the clock, whose preview
  # gap widens the centre, so its point stands clear of the widened
  # centre.
  # A control reads only where the release writes.
  zone_drop() {
    local pair box x w
    box="$(ipc smoke instanceGeometry "$(bar_key)" "$2")" || { fail "$1: $2 has no box"; return; }
    read -r x w < <(py_reply 'import json,sys; b=json.load(sys.stdin); print(int(b[0]+b[2]/2), int(b[2]))' <<<"$box")
    pair="$(zone_pair "$3" "$w")" || { fail "$1: the right zone is unreadable"; return; }
    read -r zone_a zone_b zone_x <<<"$pair"
    [[ $zone_x =~ ^[0-9]+$ ]] || { fail "$1: no two shown neighbours $3 the last third: $pair"; return; }
    zone_hold_press "$2" "$((zone_x - x))" 0 || { fail "$1: the held press on $2"; return; }
    [[ -n ${4:-} ]] || geometry expect_poll "$1: the preview gap opens between the two shown neighbours, over nothing" '[true, true, []]' zone_pick "json.dumps([$(zone_gap_open_program "$w"), d['right']['clips'], d['right']['over']])"
    zone_release || fail "$1: the held press releases"
  }
  # The open preview gap: B stands past A's end by the dragged widget's
  # width WIDTH and a bar gap either side of it, and the room between
  # them lies in the part of the zone that shows whole widgets.
  zone_gap_open_program() { # WIDTH
    echo "(lambda s, r: s['$zone_b'][0] - s['$zone_a'][0] - s['$zone_a'][1] >= $1 + 2 * d['gap'] - 1 and s['$zone_a'][0] + s['$zone_a'][1] + d['gap'] >= r[0] - 1 and s['$zone_b'][0] - d['gap'] <= r[1] + 1)(dict(zip(d['right']['ids'], d['right']['spans'])), d['right']['range'])"; }
  # zone_layout ID: ID with its right-section neighbours, or the right
  # section when ID is not in it.
  zone_layout() { ipc shell listShellConfig | py_reply 'import json,sys; ids=[e["id"] for e in json.load(sys.stdin)["bar"]["layout"]["right"]]; t=sys.argv[1]; i=ids.index(t) if t in ids else -1; print(json.dumps(ids[i-1:i+2] if i>0 else ids))' "$1"; }
  zone_layout_elsewhere() { zone_layout "$1" | py_reply 'import json,sys; got=json.load(sys.stdin); print(got!=json.loads(sys.argv[1]))' "[\"$zone_a\", \"$1\", \"$zone_b\"]"; }
  # The widgets the right zone clips away stand under the clock and draw
  # above it. A right click reaches every frame handler under it, so only
  # the clip keeps it from the hidden widget's menu as well as the
  # clock's. The click lands on the clock where a clipped widget lies.
  zone_clock_click() { # LABEL
    local pick x
    pick="$(zone_pick "next(('%d %s' % ((max(a, d['centre'][0]) + min(a + w, d['centre'][0] + d['centre'][1])) / 2, i) for i, (a, w) in zip(d['right']['ids'], d['right']['spans']) if a + w > d['centre'][0] + 4 and a < d['centre'][0] + d['centre'][1] - 4), 'clear')")" || { fail "$1: the zones are unreadable"; return 1; }
    read -r x zone_under <<<"$pick"
    [[ $x =~ ^[0-9]+$ ]] || { fail "$1: no clipped widget under the clock: $pick"; return 1; }
    hover "$((x + 1))" "$zone_bar_y" && right_click "$x" "$zone_bar_y" || { fail "$1: the right click on the clock failed"; return 1; }
  }
  zone_menus() { echo "[$(ipc smoke readInstance "$(bar_key)" vgs.bar/center-clock frameMenuOpen), $(ipc smoke readInstance "$(bar_key)" "$zone_under" frameMenuOpen)]"; }
  # The empty bar before the clock, over widgets the right zone clips
  # away, still opens the bar's add menu.
  zone_empty_menu() { # LABEL WANT
    local x depth=1
    [[ $2 == True ]] || depth=0
    x="$(zone_pick "int((d['right']['spans'][0][0] + d['centre'][0]) / 2) if d['right']['spans'][0][0] < d['centre'][0] - 8 and d['right']['spans'][0][0] > d['left']['view'][0] + d['left']['view'][1] else 'crowded'")" || { fail "$1: the zones are unreadable"; return; }
    [[ $x =~ ^[0-9]+$ ]] || { fail "$1: no empty bar over clipped widgets: $x"; return; }
    hover "$((x + 1))" "$zone_bar_y" && right_click "$x" "$zone_bar_y" || { fail "$1: the right click on the empty bar failed"; return; }
    geometry expect "$1" "$2" zone_ever_true "$depth" ipc smoke readInstance "$(bar_key)" vgs.bar spacerMenuOpen
    type_keys -k Escape || fail "$1: Escape closes the menu"
  }
  # A right click on the shown < button steps the zone, and the widget it
  # covers opens no menu. A step lands a widget beside the fade, so the
  # one before it lies under the button.
  zone_button_right_click() { # LABEL
    local x y
    zone_place="$(zone_pick "json.dumps(d['right']['spans'][0])")" || { fail "$1: the right zone is unreadable"; return 1; }
    hover "$zone_wx" "$zone_wy" && wheel "$zone_wx" "$zone_wy" -1 && [[ $(zone_moved right "$zone_place" 1) == True ]] || { fail "$1: the wheel notch before it moved nothing"; return 1; }
    zone_place="$(zone_pick "json.dumps(d['right']['spans'][0])")" && zone_under="$(zone_under_start right)" || { fail "$1: the right zone is unreadable"; return 1; }
    [[ $zone_under != none ]] || { fail "$1: no widget under the < button"; return 1; }
    read -r x y < <(zone_button right start) || { fail "$1: the < button has no place"; return 1; }
    hover "$((x + 1))" "$y" && right_click "$x" "$y" || { fail "$1: the right click on the < button failed"; return 1; }
  }

  zone_fade="$(ipc smoke themeValue bar.scroll.fade)" || fail "the fade token is unreadable"
  zone_bar_y="$(ipc smoke instanceGeometry "$(bar_key)" vgs.bar | py_reply 'import json,sys; b=json.load(sys.stdin); print(int(b[1]+b[3]/2))')" || fail "the bar box is unreadable"
  zone_monitor="$(first_name)" || fail "the monitor is unreadable"
  zone_state="$(base_mode_scale "$zone_monitor")" || fail "the monitor's mode is unreadable"
  zone_mode="${zone_state% scale=*}" zone_scale="${zone_state##*scale=}"
  zone_saved_w="$mon_w" zone_saved_h="$mon_h"
  # zone_width WIDTH: the monitor held WIDTH logical pixels wide at its
  # own height and scale, the pointer helpers sized to it. At 1600 the
  # owner's right section hides seven widgets, which the walks need; at
  # 1900 it hides one, so two neighbours it shows stand left of the
  # bar's last third, where the drops need them.
  zone_width() {
    [[ ${#mode_hold[@]} -eq 0 ]] || release_mode "the nested compositor gives the monitor its own mode back" "$zone_monitor" "$zone_mode" "$zone_scale"
    hold_mode "the nested compositor holds its monitor $1 logical pixels wide" "$zone_monitor" "$(($1 * zone_scale))x${zone_mode#*x}" "$zone_scale"
    mon_w="$1" mon_h="$((${zone_mode#*x} / zone_scale))"
    expect_poll "the monitor reads $1 logical pixels wide" "$1" first_width
  }
  # The view's middle, where the wheel turns.
  zone_middle() { read -r zone_wx zone_wy < <(zone_pick "'%d %d' % (d['right']['view'][0]+d['right']['view'][1]/2, $zone_bar_y)"); }
  zone_width 1600
  # The fit path: three right widgets fit, draw flush and show no button.
  zone_plant 3
  expect_poll "the bar mounts three of the owner's right widgets" True zone_mounted
  geometry expect_poll "a right zone that fits shows no button and clips nothing" '[false, false, false, []]' zone_ends right
  geometry expect "zones that fit draw flush with their sections, as before" '[true, true]' zone_pick "json.dumps([d['left']['flush'], d['right']['flush']])"
  zone_plant
  expect_poll "the bar mounts the owner's right section" True zone_mounted
  geometry expect_poll "at rest the clipped right zone shows its end and its < button alone, over nothing" '[true, true, false, []]' zone_ends right
  geometry expect "the left zone fits and shows no button" '[false, false, false, []]' zone_ends left
  geometry expect "at rest the right zone's last widget meets its edge" True zone_pick "d['right']['ends'] == d['right']['ids'][-1:]"
  zone_rest="$(zone_shown right)" || fail "the resting right zone is unreadable"
  zone_middle
  if zone_button_right_click "a right click on the < button"; then
    geometry expect "a right click on the < button steps the zone" True zone_moved right "$zone_place" 1
    expect "a right click on the < button opens no menu of the widget under it" false ipc smoke readInstance "$(bar_key)" "$zone_under" frameMenuOpen
  fi
  wheel "$zone_wx" "$zone_wy" 20 || fail "the wheel over the right zone failed"
  geometry expect_poll "the zone returns to its end" "$zone_rest" zone_shown right
  if zone_clock_click "a right click on the clock over clipped widgets"; then
    expect_poll "a right click on the clock over clipped widgets opens the clock's menu alone" '[true, false]' zone_menus
    type_keys -k Escape || fail "Escape to the clock's menu failed"
    expect_poll "Escape closes the clock's menu" '[false, false]' zone_menus
  fi
  zone_empty_menu "a right click on the empty bar over clipped widgets opens the add menu" True
  expect_poll "Escape closes the add menu" false ipc smoke readInstance "$(bar_key)" vgs.bar spacerMenuOpen
  zone_beside="$(zone_others)" || fail "the left zone and the centre are unreadable"
  # A wheel notch up steps toward the start and down toward the end; a
  # turn past the end stops there.
  wheel "$zone_wx" "$zone_wy" -1 || fail "the wheel over the right zone failed"
  geometry expect_poll "a wheel notch up lands a widget at the start, beside the fade" True zone_landed right start
  geometry expect "a wheel notch up leaves the end, so > shows too" '[true, true, true, []]' zone_ends right
  geometry expect "scrolled one notch, the right zone moves neither the left zone nor the centre" "$zone_beside" zone_others
  zone_one="$(zone_shown right)" || fail "the wheeled right zone is unreadable"
  expect "a wheel notch up shows a widget before those at rest" True py_reply 'import json,sys; a,b=json.load(sys.stdin),json.loads(sys.argv[1]); print(bool(a) and a[0] not in b)' "$zone_rest" <<<"$zone_one"
  wheel "$zone_wx" "$zone_wy" 3 || fail "the wheel over the right zone failed"
  geometry expect_poll "wheel notches down stop at the end" "$zone_rest" zone_shown right
  # The < button steps exactly as a notch up, then walks to the start a
  # whole widget a click; the > button walks back to the end. Neither
  # moves the left zone or the centre.
  zone_press right start || fail "the < button click failed"
  geometry expect_poll "a < click shows what a wheel notch up showed" "$zone_one" zone_shown right
  geometry expect "the < button walks to the start, a widget edge at each step" walked zone_walk right start
  geometry expect "at the start the first widget meets the zone's edge and > shows alone" '[true, false, true, []]' zone_pick "json.dumps([d['right']['starts'] == d['right']['ids'][:1], d['right']['start'], d['right']['end'], d['right']['over']])"
  geometry expect "scrolled to the start, the right zone moves neither the left zone nor the centre" "$zone_beside" zone_others
  geometry expect "the > button walks to the end, a widget edge at each step" walked zone_walk right end
  geometry expect "the > walk ends at rest" "$zone_rest" zone_shown right
  geometry expect "back at rest the left zone and the centre stand where they stood" "$zone_beside" zone_others
  # A wheel turned over the < button scrolls the zone, though Sound, which
  # takes the wheel itself, passes under the button on the way.
  geometry expect "wheel notches over the < button walk to the start past Sound" True py_reply 'import sys; r=sys.stdin.read().strip(); print(r.startswith("walked over=") and "vgs.sound" in r.split("=",1)[1].split(","))' <<<"$(zone_wheel_walk right)"
  wheel "$zone_wx" "$zone_wy" 20 || fail "the wheel over the right zone failed"
  geometry expect_poll "the zone returns to its end after the wheel walk" "$zone_rest" zone_shown right
  zone_width 1900
  geometry expect_poll "at 1900 the right zone clips and rests at its end" '[true, true, false, []]' zone_ends right
  zone_middle
  # Drops land at the slot under the pointer in what the zone shows: past
  # the bar's last third, and left of it, where the thirds alone would
  # pick the centre section. Each drop shows the widget it lands.
  zone_drop "a drop past the last third into the clipped right zone" vgs.launcher past
  expect_poll "the drop past the last third lands the Launcher between the neighbours under the pointer" "[\"$zone_a\", \"vgs.launcher\", \"$zone_b\"]" zone_layout vgs.launcher
  geometry expect_poll "the dropped Launcher shows and the zone still clips, over nothing" '[true, true, []]' zone_pick "json.dumps(['vgs.launcher' in d['right']['shown'], d['right']['clips'], d['right']['over']])"
  zone_drop "a drop left of the last third into the clipped right zone" vgs.bar/left-workspaces before
  expect_poll "the drop left of the last third lands the workspaces in the right section between the neighbours under the pointer" "[\"$zone_a\", \"vgs.bar/left-workspaces\", \"$zone_b\"]" zone_layout vgs.bar/left-workspaces
  wheel "$zone_wx" "$zone_wy" 20 || fail "the wheel over the right zone failed"
  geometry expect_poll "the zone returns to its end after the drops" '[true, true, false, []]' zone_ends right
  # Last, since the widget keeps its focus for the next time the bar
  # holds the keyboard.
  zone_focus "focus on a hidden widget scrolls it into view" True
  # Controls: each copy drops one rule, and its check reads the fault.
  zone_width 1600
  zone_middle
  zone_control() { # NAME FILE OLD NEW
    stop_shell
    zone_plant
    copy_tree "zone-$1" && edit_tree "zone-$1" "$2" "$3" "$4" || return 1
    start_shell "$sandbox/tree-zone-$1" "$sandbox/bar-zone-$1.log" || { fail "the zone control $1 starts"; return 1; }
    expect_poll "control $1: the bar mounts the owner's right section" True zone_mounted
    geometry expect_poll "control $1: the right zone shows its < button" True zone_pick "d['right']['start']"
  }
  # The stand-ins draw their widgets a moment after the mount.
  zone_under_clock() { geometry expect_poll "control $1: the right section runs under the clock" True zone_pick "d['right']['spans'][0][0] < d['centre'][0] - 8"; }
  if zone_control clip shell/plugins/vgs.bar/Bar.qml '    clip: clipped' '    clip: false'; then
    zone_under_clock clip
    geometry expect_poll "control: a zone that does not clip draws over the centre" True zone_pick "bool(d['right']['over'])"
    if zone_clock_click "control: a right click on the clock over unclipped widgets"; then
      geometry expect "control: without the clip the hidden widget under the clock opens its menu too" True zone_ever_true 1 ipc smoke readInstance "$(bar_key)" "$zone_under" frameMenuOpen
    fi
  fi
  if zone_control empty shell/plugins/vgs.bar/Bar.qml 'section.parent.contains(section.parent.mapFromItem(bar, x, y)) && ' ''; then
    zone_under_clock empty
    zone_empty_menu "control: a bar that counts clipped widgets as drawn keeps its add menu shut" False
  fi
  if zone_control buttons shell/plugins/vgs.bar/Bar.qml 'readonly property bool moreAfter: clipped && before < travel - 0.5' 'readonly property bool moreAfter: clipped'; then
    geometry expect_poll "control: a > button shown at the end fails the resting read" '[true, true, true, []]' zone_ends right
  fi
  # The button's bar item takes the right press over its own box, so the
  # control turns the backdrop and the item in it off together.
  if zone_control backdrop shell/plugins/vgs.bar/Bar.qml '            acceptedButtons: Qt.AllButtons' $'            acceptedButtons: Qt.AllButtons\n            enabled: false'; then
    if zone_button_right_click "control: a right click on a < button that takes no press"; then
      geometry expect "control: the widget under a < button that takes no press opens its menu" True zone_ever_true 1 ipc smoke readInstance "$(bar_key)" "$zone_under" frameMenuOpen
    fi
  fi
  if zone_control steps shell/plugins/vgs.bar/Bar.qml 'scrollTo(previous === undefined ? 0 : previous.x - inset);' 'scrollTo(before - Theme.bar.gap);'; then
    zone_place="$(zone_pick "json.dumps(d['right']['spans'][0])")" || fail "control: the right zone is unreadable"
    zone_press right start || fail "control: the < button click failed"
    geometry expect "control: the < click moves the zone" True zone_moved right "$zone_place" 1
    geometry expect "control: a step by the gap lands no widget edge at the start" False zone_landed right start
  fi
  if zone_control wheel shell/plugins/vgs.bar/Bar.qml 'enabled: zone.clipped' 'enabled: false'; then
    wheel "$zone_wx" "$zone_wy" -1 || fail "control: the wheel over the right zone failed"
    geometry expect "control: a zone that takes no wheel never leaves its end" False zone_ever "d['right']['end']" 0
  fi
  if zone_control button-wheel shell/plugins/vgs.bar/Bar.qml '            onWheel: wheel => scroller.owner.takeWheel(wheel)' ''; then
    geometry expect "control: a < button that lets the wheel through sticks on a widget that takes the wheel" True py_reply 'import sys; r=sys.stdin.read().strip(); print(r.startswith("stuck=") and r.split("under=")[-1] in ("vgs.sound", "vgs.displays"))' <<<"$(zone_wheel_walk right)"
  fi
  if zone_control focus shell/plugins/vgs.bar/Bar.qml '        if (!clipped) return;' '        return;'; then
    zone_focus "control: a zone deaf to focus leaves the focused widget hidden" False
  fi
  zone_width 1900
  if zone_control drop shell/Core/Plugins.qml 'const x = sectionPoint.x + restX(placed.slice(0, placed.indexOf(entry.widget)), container.spacing);' 'const x = restX(placed.slice(0, placed.indexOf(entry.widget)), container.spacing);'; then
    zone_drop "control: a drop that reads the section's own places" vgs.launcher past control
    geometry expect_poll "control: the drop lands elsewhere than under the pointer" True zone_layout_elsewhere vgs.launcher
  fi
  if zone_control view shell/Core/PluginLogic.js 'x >= view.x && x < view.x + view.width) section = side;' 'false) section = side;'; then
    zone_drop "control: a drop that the thirds alone place" vgs.bar/left-workspaces before control
    geometry expect_poll "control: the drop left of the last third leaves the right section" True zone_layout_elsewhere vgs.bar/left-workspaces
  fi
  release_mode "the nested compositor gives the monitor its own mode back" "$zone_monitor" "$zone_mode" "$zone_scale"
  mon_w="$zone_saved_w" mon_h="$zone_saved_h"
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
  && edit_tree bar-motion-control shell/plugins/vgs.bar/Bar.qml '        Item {
            id: section
            readonly property real spacing: Theme.bar.gap' '        Row {
            move: Transition { NumberAnimation { properties: "x"; duration: 0 } }
            add: Transition { NumberAnimation { properties: "x"; duration: 0 } }
            id: section
            spacing: Theme.bar.gap' \
  && edit_tree bar-motion-control shell/plugins/vgs.bar/Bar.qml '    Item {
        id: center
        readonly property real spacing: Theme.bar.gap' '    Row {
        move: Transition { NumberAnimation { properties: "x"; duration: 0 } }
        add: Transition { NumberAnimation { properties: "x"; duration: 0 } }
        id: center
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
# The calendar's control: a calendar that marks no day fails the reading
# that passed above.
stop_shell
if copy_tree calendar-unmarked \
  && edit_tree calendar-unmarked shell/plugins/vgs.bar/Calendar.qml 'variant: today ? "primary" : "ghost"' 'variant: "ghost"'; then
  start_shell "$sandbox/tree-calendar-unmarked" "$sandbox/calendar-unmarked.log" || fail "the unmarked calendar control starts"
  expect "control: the calendar opens" ok calendar_summon
  expect_poll "control: a calendar that marks no day reads no today" "$(calendar_want 0 none)" calendar_read
  stop_shell
fi
# Today's day falls among another month's days on some dates only, so a
# tree whose today is the 1st of this month proves the in-month rule on
# every date: the previous month's grid always ends with this month's
# first days. Its control drops the rule and marks that day.
for calendar_case in first first-unguarded; do
  copy_tree "calendar-$calendar_case" \
    && edit_tree "calendar-$calendar_case" shell/plugins/vgs.bar/Calendar.qml 'readonly property int todayDay: Time.now.getDate()' 'readonly property int todayDay: 1' \
    || continue
  if [[ $calendar_case == first-unguarded ]]; then
    edit_tree "calendar-$calendar_case" shell/plugins/vgs.bar/Calendar.qml 'readonly property bool today: inMonth && year' 'readonly property bool today: year' || continue
  fi
  start_shell "$sandbox/tree-calendar-$calendar_case" "$sandbox/calendar-$calendar_case.log" || fail "the $calendar_case calendar tree starts"
  expect "$calendar_case: the calendar opens" ok calendar_summon
  expect_poll "$calendar_case: the calendar marks the 1st of this month" "$(calendar_want 0 1)" calendar_read
  expect "$calendar_case: Left moves the calendar back" ok calendar_back
  if [[ $calendar_case == first ]]; then
    expect_poll "the previous month leaves this month's 1st unmarked among its days" "$(calendar_want -1 none)" calendar_read
  else
    expect_poll "control: without the in-month rule the previous month marks this month's 1st" "$(calendar_want -1 1)" calendar_read
  fi
  stop_shell
done
# The centring's controls: a number drawn from its square's left edge
# reads off centre across, and one drawn from its top edge reads off
# centre down, for one-digit and two-digit days alike.
for calendar_case in left top; do
  case "$calendar_case" in
    left) calendar_old='x: Math.round(parent.width / 2 - ink.tightBoundingRect.x - ink.tightBoundingRect.width / 2)'; calendar_new='x: 0'; calendar_axis=0 ;;
    top) calendar_old='y: Math.round(parent.height / 2 - baselineOffset - ink.tightBoundingRect.y - ink.tightBoundingRect.height / 2)'; calendar_new='y: 0'; calendar_axis=1 ;;
  esac
  copy_tree "calendar-$calendar_case" \
    && edit_tree "calendar-$calendar_case" shell/plugins/vgs.bar/Calendar.qml "$calendar_old" "$calendar_new" \
    || continue
  start_shell "$sandbox/tree-calendar-$calendar_case" "$sandbox/calendar-$calendar_case.log" || fail "the $calendar_case calendar tree starts"
  expect "$calendar_case: the calendar opens" ok calendar_summon
  geometry expect_poll "control: numbers drawn from the square's $calendar_case edge read off centre" True calendar_off_axis "$calendar_axis"
  stop_shell
done
start_shell "$repo" "$sandbox/calendar-restored.log" || fail "the shell returns after the calendar control"
