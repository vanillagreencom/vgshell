# The System window, vgs.system: the holder of the exclusive `panes`
# capability (D088), a Hyprland window titled System Settings. Over four
# copies of the acme.pane fixture, three enabled in two groups and one left
# disabled, the row reads the sidebar listing exactly the enabled sections
# under their groups in the capability's order; `{}` opening the first
# section, then the one shown last; a deep link mounting its section with
# the rest of the payload; an unknown id opening with a notice; the plugin's
# own open and toggle IPC; an own-pane summon; each switch destroying the
# section before it in the window host's build records; a click on Show in
# bar placing and removing the fixture widget, offered only to a section
# with one; a section taller than the room scrolling in the page and a
# shorter one filling it; the selection staying on its section as another
# joins and leaves; a disabled section leaving the sidebar while the window
# is open, the window showing the first section left in place of the shown
# one and a group with no section left losing its heading; the window read
# as every application window is (app_window_rows,
# scripts/smoke/app-window.sh); its edges within one pixel; and a keyboard
# path from SUPER+PERIOD to every step and back out. Shell & Plugins hands
# the Settings summon command to a
# stand-in vgshell in the shell's own PATH directory, which records its argv
# and runs nothing.
#
# A hover in the sidebar moves its plate and not its selection, the shown
# section's text alone keeps the accent, and the plate returns to the shown
# section once the pointer leaves the list.
#
# Controls: a copy of the window that keeps the list it read when it opened
# lists a section disabled while it is open and is titled with its own name,
# a copy that shows nothing in place of a section that leaves while shown
# mounts no section, a shell copy whose PaneHost hands the holder no pane
# height shows the tall section cut to the room, and SUPER+COMMA opens no
# System window. The row reads no latency. It starts with no other panes
# holder installed and every enabled shipped section set aside, so the
# sidebar lists its fixtures alone, and leaves the user file, vgs.system's
# and each shipped section's enablement, the plugins directory and the
# shell's PATH directory as it found them.
# inputs: shell/plugins/vgs.system/* shell/Ui/layout/ListCursor* shell/Ui/layout/ListItem.qml shell/Core/PluginLogic.js shell/plugins/*/manifest.json scripts/smoke/fixtures/plugins/acme.pane/* shell/Hosts/PaneHost.qml shell/Hosts/AppWindow.qml shell/Core/Capabilities.qml shell/Core/Config.qml shell/Commons/WatchedFile.qml scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail

sys_file="$home/.config/vgshell/shell.json"
sys_saved="$sandbox/shell-before-system.json"
sys_calls="$sandbox/system-vgshell.calls"
cp -- "$sys_file" "$sys_saved"
rm -f -- "$sys_calls"
if [[ -e $shim/vgshell ]]; then mv -- "$shim/vgshell" "$sandbox/system-vgshell.saved"; fi
cat >"$shim/vgshell" <<EOF
#!/usr/bin/env bash
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "\$@" >>"$sys_calls"
EOF
chmod 755 "$shim/vgshell"

# The sidebar as drawn, top to bottom: its group headings, then its rows'
# titles. A Repeater adds its rows after the items declared beside it, so
# tree order is not drawing order.
sys_sidebar() { # [ID]
  ipc smoke descendantGeometry window "${1:-vgs.system}" | py_reply '
import json, sys
rows = json.load(sys.stdin)
def shown(j):
    while j != -1:
        if not rows[j]["visible"]: return False
        j = rows[j]["parent"]
    return True
def under(j, kind):
    while j != -1:
        if rows[j]["type"] == kind: return j
        j = rows[j]["parent"]
    return -1
heads = sorted((r["box"][1], r["text"]) for i, r in enumerate(rows) if r["type"] == "Label" and r.get("role") == "eyebrow" and under(i, "Sidebar") != -1 and shown(i))
items = sorted((r["box"][1], r["text"]) for i, r in enumerate(rows) if r["type"] == "ListItem" and under(i, "Sidebar") != -1 and shown(i))
print(json.dumps([[t for _, t in heads], [t for _, t in items]], separators=(",", ":")))'
}
sys_read() { ipc smoke readInstance window vgs.system "$1"; }
sys_current() { ipc smoke readDescendant window vgs.system Sidebar current; }
sys_search() { ipc smoke readDescendant window vgs.system TextField text; }
# The label of the item that holds the window's keyboard focus: a text
# field's text, or its placeholder while it is empty.
sys_focus() { ipc smoke focused window vgs.system | py_reply 'import json,sys; r=json.load(sys.stdin); print(r[1] if isinstance(r, list) else r)'; }
# Whether each Show in bar switch draws: its text shows only while it does.
sys_switch() { ipc smoke itemTexts window vgs.system Switch | py_reply 'import json,sys; print(json.dumps([t != [] for t in json.load(sys.stdin)]))'; }
sys_switch_checked() { ipc smoke readDescendant window vgs.system Switch checked; }
sys_payload() { ipc smoke readInstance window "$1" payload; }
# Every argv the stand-in vgshell received, one JSON list per call.
sys_calls_all() { [[ -s $sys_calls ]] && python3 -c 'import json,sys; print(json.dumps([json.loads(l) for l in open(sys.argv[1])]))' "$sys_calls" || echo '[]'; }
widget_placed() { bar_widget_ids | py_reply 'import json,sys; print(any(sys.argv[1] in ids for ids in json.load(sys.stdin)))' "$1"; }
sys_binds() { hypr -j binds | py_reply 'import json,sys; print(json.dumps(sorted([b["modmask"], b["key"]] for b in json.load(sys.stdin) if b["description"] == "vgs.system:toggle" and b.get("submap", "") in ("", "default"))))'; }
sys_lent() { ipc shell lent | py_reply 'import json,sys; d=json.load(sys.stdin); print("vgs.system:toggle" in d["shortcuts"] and "vgs.system" in d["ipcTargets"])'; }
press_system() { type_keys -M logo -k period -m logo; }
# `fits` when the mounted section ID's box is its implicit height tall, or
# the detail's room when that is more; else both. The room is the page's
# ScrollArea height less the focus ring's room above and below it.
sys_pane_fits() { # ID
  local box implicit rows ring
  box="$(ipc smoke instanceGeometry window "$1")" && implicit="$(ipc smoke readInstance window "$1" implicitHeight)" && rows="$(ipc smoke descendantGeometry window vgs.system)" || return 1
  [[ $box == \[* && $rows == \[* ]] || { echo "pane=$box window=${rows:0:20}"; return; }
  ring="$(( $(ipc smoke themeValue focusRing.width) + $(ipc smoke themeValue focusRing.offset) ))" || return 1
  python3 - "$box" "$implicit" "$rows" "$ring" <<'PY'
import json, sys
box, implicit, rows, ring = json.loads(sys.argv[1]), float(sys.argv[2]), json.loads(sys.argv[3]), float(sys.argv[4])
side = [i for i, r in enumerate(rows) if r["type"] == "Sidebar"]
def inside(j, i):
    while j != -1:
        if j == i: return True
        j = rows[j]["parent"]
    return False
areas = [r for i, r in enumerate(rows) if r["type"] == "ScrollArea" and side and not inside(i, side[0]) and r["box"][0] < box[0] + 1 and r["box"][0] + r["box"][2] > box[0]]
if len(areas) < 1: print("areas=0"); sys.exit()
room = min(a["box"][3] for a in areas) - 2 * ring
want = max(room, implicit)
print("fits" if abs(box[3] - want) <= 1 else "height=%g want=%g implicit=%g room=%g" % (box[3], want, implicit, room))
PY
}

# Preconditions: no other holder of `panes` is installed, since panes is
# exclusive. vgs.system is enabled or not as the rows before left it, and
# the restore puts that back.
sys_was="$(plugin_enabled vgs.system)" || fail "vgs.system's enabled state is unreadable"
# The sidebar must list the fixture sections alone, so every enabled
# shipped section, such as vgs.displays from the default set rows/hidpi.sh
# restarts over, is set aside; the restore below puts each back.
sys_aside="$(shipped_panes_enabled)" || { fail "the enabled shipped sections are unreadable"; sys_aside='[]'; }
set_aside_shipped_panes "$sys_aside"
expect "no fixture panes holder is installed" absent plugin_enabled acme.panehost

install_plugin_copy acme.pane acme.pane "Pane" 10
# Pane Alt sorts before Pane by order and after it by name.
install_plugin_copy acme.pane acme.pane-alt "Pane Alt" 5
install_plugin_copy acme.pane acme.pane-net "Pane Net" 10 Connectivity
install_plugin_copy acme.pane acme.pane-off "Pane Off" 1
# Pane Net has no bar widget and is taller than any room.
python3 - "$home/.config/vgshell/plugins/acme.pane-net" <<'PY'
import json, os, sys
root = sys.argv[1]
path = os.path.join(root, "manifest.json")
doc = json.load(open(path))
doc["kinds"].remove("bar-widget")
del doc["entryPoints"]["bar-widget"]
del doc["defaultSection"]
json.dump(doc, open(path, "w"))
os.remove(os.path.join(root, "Widget.qml"))
qml = os.path.join(root, "Pane.qml")
text = open(qml).read()
old = "implicitHeight: Theme.size.control.lg * 3"
assert text.count(old) == 1, old
open(qml, "w").write(text.replace(old, "implicitHeight: Theme.size.control.lg * 60"))
PY
rescan "rescan after adding the System fixtures answers ok"
# A copy with a bar widget is placed and enabled once it is discovered
# (PluginLogic.firstPresence); Pane Off is disabled so the sidebar leaves
# it out, and Pane Net, with no widget, waits for Enable below.
expect_poll "the last System fixture is discovered enabled" True plugin_enabled acme.pane-off
expect "disabling the last System fixture is allowed" ok ipc shell setPluginEnabled acme.pane-off false
expect "Pane Net, with no bar widget, is discovered disabled" False plugin_enabled acme.pane-net
for id in acme.pane acme.pane-alt acme.pane-net; do
  expect "enabling $id for the System window is allowed" ok ipc shell setPluginEnabled "$id" true
done
expect "enabling the System window is allowed" ok ipc shell setPluginEnabled vgs.system true
expect_poll "the System service registered its shortcut and IPC target" True sys_lent
expect_poll "the Hyprland layer binds SUPER+PERIOD to the System shortcut" '[[64, "PERIOD"]]' sys_binds

# `{}` with nothing remembered opens the first section, with the keyboard
# in the sidebar's search field.
expect "the IPC opens the System window" ok ipc shell summon window vgs.system '{}'
expect_poll "the sidebar lists exactly the enabled sections under their groups in order" '[["Connectivity","Fixtures"],["Pane Net","Pane Alt","Pane","Shell & Plugins"]]' sys_sidebar
expect_poll "{} with nothing remembered mounts the first section" '["acme.pane-net"]' window_panes
expect "the first section receives an empty payload" '"{}"' sys_payload acme.pane-net
expect_poll "{} opens with the keyboard in the search field" "Search sections" sys_focus
expect "a section with no bar widget offers no Show in bar" '[false]' sys_switch
geometry expect_poll "a section taller than the room grows the page, which scrolls it" fits sys_pane_fits acme.pane-net
app_window_rows "System Settings" vgs.system

# Deep links: the section named, with the rest of the payload; an id no
# section has, which opens the last section with a notice; and payloads
# open() refuses.
expect "a deep link opens the System window" ok ipc shell summon window vgs.system '{"pane":"acme.pane-alt","from":"link"}'
expect_poll "the deep link mounts its section alone" '["acme.pane-alt"]' window_panes
expect "the deep-linked section receives the payload without pane" '"{\"from\":\"link\"}"' sys_payload acme.pane-alt
expect_poll "the deep link puts the keyboard in the section" "Pane edit" sys_focus
expect "the sidebar selects the deep-linked section" 1 sys_current
expect "an unknown id answers ok" ok ipc shell summon window vgs.system '{"pane":"acme.nope"}'
expect_poll "an unknown id shows a plain notice" '"That section is not available."' sys_read notice
expect "an unknown id keeps the section shown last" '["acme.pane-alt"]' window_panes

# The plugin's own IPC: open shows a section and keeps an open window
# open; toggle closes it, then opens it on the section shown last.
expect "the plugin's IPC opens a section" ok ipc vgs.system invoke open '{"pane":"acme.pane-net"}'
expect_poll "the plugin's IPC open mounts its section" '["acme.pane-net"]' window_panes
expect "the plugin's IPC open again answers ok" ok ipc vgs.system invoke open '{"pane":"acme.pane-net"}'
expect "a second open keeps the System window open" 1 window_count "System Settings"
expect "the plugin's IPC toggle answers ok" ok ipc vgs.system invoke toggle ''
expect_poll "toggle closes the open System window" 0 window_count "System Settings"
expect "the plugin's IPC toggle again answers ok" ok ipc vgs.system invoke toggle ''
expect_poll "toggle opens the System window again" 1 window_count "System Settings"
expect_poll "toggle opens on the section shown last" '["acme.pane-net"]' window_panes

# Switching destroys the section before it.
expect "showing Pane through the window is allowed" ok ipc smoke invokeInstance window vgs.system enterPane acme.pane
expect_poll "switching to Pane destroys Pane Alt's build record" '["acme.pane"]' window_panes
expect_poll "the shown section clears the notice" '""' sys_read notice
geometry expect_poll "a section shorter than the room fills the room" fits sys_pane_fits acme.pane

# Hover in the sidebar, a navigation list: the plate follows the pointer to
# a section that is not shown while the selection stays on the shown one,
# whose text keeps the accent alone; with the pointer off the list the
# plate is back on the shown section. The hovered reading is the contrast:
# the same reader sees the plate on another row.
# sys_plate_row: the title of the sidebar row the plate sits on, or none.
sys_plate_row() {
  ipc smoke descendantGeometry window vgs.system | py_reply '
import json, sys
rows = json.load(sys.stdin)
def under(j, kind):
    while j != -1:
        if rows[j]["type"] == kind: return j
        j = rows[j]["parent"]
    return -1
def shown(j):
    while j != -1:
        if not rows[j]["visible"]: return False
        j = rows[j]["parent"]
    return True
plates = [r for i, r in enumerate(rows) if r["type"] == "ListCursor" and under(i, "Sidebar") != -1 and shown(i)]
items = [r for i, r in enumerate(rows) if r["type"] == "ListItem" and under(i, "Sidebar") != -1 and shown(i)]
on = [r["text"] for p in plates for r in items if abs(r["box"][1] - p["box"][1]) < 1 and abs(r["box"][3] - p["box"][3]) < 1]
print(on[0] if len(on) == 1 else "none")'
}
# sys_accent_rows: the sidebar titles drawn in listItem.selectedForeground.
sys_accent_rows() {
  local accent
  accent="$(ipc smoke themeValue listItem.selectedForeground)" || return 1
  ipc smoke itemValues window vgs.system Label text,color,role | py_reply '
import json, sys
def norm(c):
    c = str(c).strip("\"").lower()
    return "#" + c[3:] if len(c) == 9 and c.startswith("#ff") else c
names = {"Pane Net", "Pane Alt", "Pane", "Shell & Plugins"}
want = norm(sys.argv[1])
print(json.dumps(sorted(r["text"] for r in json.load(sys.stdin) if r["role"] == "item" and r["text"] in names and norm(r["color"]) == want)))' "$accent"
}
sys_hover_box="$(ipc smoke windowGeometry window vgs.system ListItem "Pane Net")" || sys_hover_box=""
sys_box="$(surface_box "window:System Settings")" || sys_box=""
if read -r sys_hx sys_hy < <(at_centre "window:System Settings" "$sys_hover_box") && [[ $sys_box == \[* ]]; then
  expect_poll "before the hover the plate sits on the shown section" Pane sys_plate_row
  hover "$((sys_hx - 6))" "$sys_hy"; hover "$sys_hx" "$sys_hy"
  expect_poll "a hover puts the sidebar's plate on Pane Net" "Pane Net" sys_plate_row
  expect "the hover leaves the selection on the shown section" 2 sys_current
  expect "while Pane Net holds the plate only the shown section's text keeps the accent" '["Pane"]' sys_accent_rows
  read -r sys_ox sys_oy < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x + w - 40), int(y + h / 2))' "$sys_box")
  hover "$sys_ox" "$sys_oy" || fail "moving the pointer off the sidebar failed"
  expect_poll "with the pointer off the list the plate is back on the shown section" Pane sys_plate_row
  expect "with the pointer off the list only the shown section's text keeps the accent" '["Pane"]' sys_accent_rows
  rest_pointer || fail "resting the pointer after the sidebar hover failed"
else
  fail "the sidebar's Pane Net row is unplaced: ${sys_hover_box:-unread}"
fi

# The selection follows its section: a section that sorts before the
# selected one joins the list while the window is open, and the selection
# stays on Pane.
expect "Pane is selected before another section joins" 2 sys_current
expect "enabling Pane Off while the window is open is allowed" ok ipc shell setPluginEnabled acme.pane-off true
expect_poll "Pane Off joins the sidebar before Pane Alt" '[["Connectivity","Fixtures"],["Pane Net","Pane Off","Pane Alt","Pane","Shell & Plugins"]]' sys_sidebar
expect_poll "the selection stays on Pane as Pane Off joins" 3 sys_current
expect "disabling Pane Off again is allowed" ok ipc shell setPluginEnabled acme.pane-off false
expect_poll "the selection stays on Pane as Pane Off leaves" 2 sys_current

# Show in bar: offered to a section with a widget, a click on the drawn
# switch places and removes that widget through panes.setPlaced.
expect_poll "a section with a bar widget offers Show in bar" '[true]' sys_switch
expect_poll "the fixture widget starts in the bar" True widget_placed acme.pane
expect "Show in bar reads the widget placed" true sys_switch_checked
click_in "window:System Settings" window vgs.system Switch "Show in bar" || fail "the click on Show in bar failed"
expect_poll "the fixture widget leaves the bar" False widget_placed acme.pane
expect_poll "Show in bar follows the removal" false sys_switch_checked
expect "the fixture stays enabled once unplaced" True plugin_enabled acme.pane
click_in "window:System Settings" window vgs.system Switch "Show in bar" || fail "the second click on Show in bar failed"
expect_poll "the fixture widget returns to the bar" True widget_placed acme.pane
expect_poll "Show in bar follows the placement" true sys_switch_checked

# Edges: the sidebar's search field, headings and rows share its content
# edges, the rule stands between the columns, and the section's icon, its
# Show in bar switch and the mounted section share the detail's.
sys_edges() {
  local rows inset pane
  rows="$(ipc smoke descendantGeometry window vgs.system)" && inset="$(ipc smoke themeValue inset.window)" && pane="$(ipc smoke instanceGeometry window acme.pane)" || return 1
  [[ $rows == \[* && $pane == \[* ]] || { echo "window=${rows:0:20} pane=$pane"; return; }
  python3 - "$rows" "$inset" "$pane" <<'PY'
import json, sys
rows, inset, pane = (json.loads(a) for a in sys.argv[1:])
out = []
def inside(j, i):
    while j != -1:
        if j == i: return True
        j = rows[j]["parent"]
    return False
def shown(j):
    while j != -1:
        if not rows[j]["visible"]: return False
        j = rows[j]["parent"]
    return True
def right(r): return r["box"][0] + r["box"][2]
def check(name, got, want):
    if abs(got - want) > 1: out.append("%s=%.2f want=%.2f" % (name, got, want))
side = [i for i, r in enumerate(rows) if r["type"] == "Sidebar"]
rules = [i for i, r in enumerate(rows) if r["type"] == "Divider" and shown(i)]
if len(side) != 1 or len(rules) != 1: print(json.dumps(["sidebars=%d rules=%d" % (len(side), len(rules))])); sys.exit()
sb, rule, win = rows[side[0]], rows[rules[0]], rows[0]
under = lambda kind: [i for i, r in enumerate(rows) if r["type"] == kind and inside(i, side[0]) and shown(i)]
search, items = under("TextField"), under("ListItem")
eyebrows = [i for i in under("Label") if rows[i].get("role") == "eyebrow"]
if len(search) != 1 or len(items) < 2 or not eyebrows: print(json.dumps(["search=%d items=%d eyebrows=%d" % (len(search), len(items), len(eyebrows))])); sys.exit()
edge_l, edge_r = rows[search[0]]["box"][0], right(rows[search[0]])
check("sidebar.leftInset", edge_l - sb["box"][0], inset)
check("sidebar.rightInset", right(sb) - edge_r, inset)
icon_x = None
for n, i in enumerate(items):
    check("item%d.left" % n, rows[i]["box"][0], edge_l)
    check("item%d.right" % n, right(rows[i]), edge_r)
    icons = [j for j, r in enumerate(rows) if r["type"] == "Icon" and rows[r["parent"]]["parent"] == i]
    if len(icons) != 1: out.append("item%d icons=%d" % (n, len(icons))); continue
    if icon_x is None: icon_x = rows[icons[0]]["box"][0]
    check("item%d.icon.x" % n, rows[icons[0]]["box"][0], icon_x)
for n, i in enumerate(eyebrows):
    check("heading%d.x" % n, rows[i]["box"][0], icon_x)
check("rule.x", rule["box"][0], right(sb))
check("rule.height", rule["box"][3], win["box"][3])
panes = [i for i, r in enumerate(rows) if r["type"] == "Pane" and not inside(i, side[0]) and r["box"][0] >= right(rule) - 1]
if not panes: print(json.dumps(out + ["detail=absent"])); sys.exit()
dp = max(panes, key=lambda i: rows[i]["box"][2])
check("detail.x", rows[dp]["box"][0], right(rule))
check("detail.right", right(rows[dp]), right(win))
head = [i for i, r in enumerate(rows) if r["type"] == "Icon" and inside(i, dp) and shown(i)]
switch = [i for i, r in enumerate(rows) if r["type"] == "Switch" and inside(i, dp) and shown(i)]
if len(head) < 1 or len(switch) != 1: print(json.dumps(out + ["head=%d switch=%d" % (len(head), len(switch))])); sys.exit()
left, end = rows[dp]["box"][0] + inset, right(rows[dp]) - inset
check("head.icon.x", rows[head[0]]["box"][0], left)
check("head.switch.right", right(rows[switch[0]]), end)
check("pane.left", pane[0], left)
check("pane.right", pane[0] + pane[2], end)
print(json.dumps(out))
PY
}
geometry expect_poll "the sidebar, the rule and the detail share their edges within one pixel" '[]' sys_edges

# A section disabled while the window is open leaves the sidebar, its
# mount goes with it, and the window shows the first section left. A group
# whose last section leaves loses its heading.
expect "showing Pane Alt before it is disabled is allowed" ok ipc smoke invokeInstance window vgs.system enterPane acme.pane-alt
expect_poll "Pane Alt is mounted before it is disabled" '["acme.pane-alt"]' window_panes
expect "disabling the shown section is allowed" ok ipc shell setPluginEnabled acme.pane-alt false
expect_poll "the sidebar lists exactly the sections still enabled" '[["Connectivity","Fixtures"],["Pane Net","Pane","Shell & Plugins"]]' sys_sidebar
expect_poll "disabling the shown section mounts the first section left in its place" '["acme.pane-net"]' window_panes
expect_poll "the window shows the first section left" '"acme.pane-net"' sys_read paneId
expect_poll "the window names the section that left" '"Pane Alt is no longer enabled."' sys_read notice
expect "disabling Pane Net, the last of its group, is allowed" ok ipc shell setPluginEnabled acme.pane-net false
expect_poll "an emptied group leaves the sidebar" '[["Fixtures"],["Pane","Shell & Plugins"]]' sys_sidebar
expect_poll "the window shows the first section left again" '["acme.pane"]' window_panes
expect "enabling Pane Alt again is allowed" ok ipc shell setPluginEnabled acme.pane-alt true
expect "enabling Pane Net again is allowed" ok ipc shell setPluginEnabled acme.pane-net true
expect_poll "Pane Alt and Pane Net return to the sidebar" '[["Connectivity","Fixtures"],["Pane Net","Pane Alt","Pane","Shell & Plugins"]]' sys_sidebar
expect "the returning sections leave the shown section mounted" '["acme.pane"]' window_panes

# A payload open() refuses closes the window.
expect "a payload that is no object is refused" "refused: open-failed=vgs.system" ipc shell summon window vgs.system '[1]'
expect "a payload key without pane is refused" "refused: open-failed=vgs.system" ipc shell summon window vgs.system '{"from":"x"}'
expect "a pane that is no string is refused" "refused: open-failed=vgs.system" ipc shell summon window vgs.system '{"pane":5}'
expect_poll "a refused payload leaves no System window" 0 window_count "System Settings"

# Own-pane summon: a section's own Settings link opens the window on it.
expect_poll "the System window is closed" 0 window_count "System Settings"
expect "a section's own-pane summon answers ok" ok ipc smoke invokeInstance service acme.pane summonPane ''
expect_poll "the own-pane summon mounts the caller's section" '["acme.pane"]' window_panes
expect "the caller's section receives its payload without pane" '"{\"from\":\"service\"}"' sys_payload acme.pane
expect "hiding the System window after the own-pane summon is allowed" ok ipc shell hide window vgs.system
expect_poll "hiding the System window drops the mounted section" '[]' window_panes

# Keyboard alone: SUPER+PERIOD opens the section shown last with the keys
# in the search field; Up and Down move the selection and mount nothing;
# Return enters and mounts; Escape leaves the section for the search
# field; typed text filters, and Down from its reset selects a middle
# match; Right at the end of the query enters; Ctrl+End and Return on
# Shell & Plugins open Settings, which Right never does; Escape clears a
# query, then closes the window.
# wtype types with keycodes of its own, which a bind resolves only by
# keysym, so the row turns that on
# after the layer's line and puts hyprland.lua back after the path.
hypr_lua_save system-window
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$home/.config/hypr/hyprland.lua"
expect "the nested instance reloads with binds resolved by keysym" ok hypr reload config-only
rest_pointer || fail "moving the pointer off the System window failed"
press_system || fail "typing SUPER+PERIOD failed"
expect_poll "SUPER+PERIOD opens the System window" 1 window_count "System Settings"
expect_poll "SUPER+PERIOD opens the section shown last" '["acme.pane"]' window_panes
expect_poll "the keyboard starts in the search field" "Search sections" sys_focus
expect "the selection starts on the shown section" 2 sys_current
type_keys -k Up || fail "typing Up in the System search failed"
expect_poll "Up moves the selection to Pane Alt" 1 sys_current
expect "Up mounts nothing" '["acme.pane"]' window_panes
type_keys -k Return || fail "typing Return in the System search failed"
expect_poll "Return mounts the selected section in place of the shown one" '["acme.pane-alt"]' window_panes
expect_poll "Return puts the keyboard in the section" "Pane edit" sys_focus
type_keys -k Escape || fail "typing Escape in the section failed"
expect_poll "Escape in the section returns the keyboard to the search field" "Search sections" sys_focus
expect "Escape in the section keeps it mounted" '["acme.pane-alt"]' window_panes
type_keys net || fail "typing a query into the System search failed"
expect_poll "typing filters the sections" '[["Connectivity"],["Pane Net","Shell & Plugins"]]' sys_sidebar
type_keys -k BackSpace -k BackSpace -k BackSpace pane || fail "typing a wider query failed"
expect_poll "a query every section matches lists them all" '[["Connectivity","Fixtures"],["Pane Net","Pane Alt","Pane","Shell & Plugins"]]' sys_sidebar
expect_poll "a new query selects its first match" 0 sys_current
type_keys -k Down -k Down || fail "typing Down in the System search failed"
expect_poll "Down from the first match selects a middle row" 2 sys_current
type_keys -k Return || fail "typing Return on the searched row failed"
expect_poll "Return in the search field enters the selected match" '["acme.pane"]' window_panes
expect_poll "Return in the search field puts the keyboard in the section" "Pane edit" sys_focus
type_keys -k Escape || fail "typing Escape in the searched section failed"
expect_poll "Escape returns the keyboard to the search field, which holds the query" "pane" sys_focus
expect "the query stays after the section is left" '"pane"' sys_search
type_keys -k Up || fail "typing Up after the search failed"
expect_poll "Up selects Pane Alt again" 1 sys_current
type_keys -k Right || fail "typing Right at the end of the query failed"
expect_poll "Right at the end of the query enters the selected section" '["acme.pane-alt"]' window_panes
type_keys -k Escape || fail "typing Escape in the right-entered section failed"
expect_poll "Escape returns the keyboard to the search field again" "pane" sys_focus
type_keys -M ctrl -k End -m ctrl || fail "typing Ctrl+End in the System search failed"
expect_poll "Ctrl+End selects Shell & Plugins" 3 sys_current
type_keys -k Right -k Return || fail "typing Right and Return on Shell & Plugins failed"
expect_poll "Return on Shell & Plugins alone hands vgshell the Settings summon, Right before it none" '[["ipc", "call", "shell", "summon", "window", "vgs.settings", "{}"]]' sys_calls_all
type_keys zz || fail "typing into the System search failed"
expect_poll "typing filters every section out" '[[],["Shell & Plugins"]]' sys_sidebar
type_keys -k Escape || fail "typing Escape in the System search failed"
expect_poll "Escape with a query clears it" '""' sys_search
expect "Escape with a query keeps the window open" 1 window_count "System Settings"
type_keys -k Escape || fail "typing Escape in the empty System search failed"
expect_poll "Escape with no query closes the System window" 0 window_count "System Settings"
expect_poll "closing the window drops its section" '[]' window_panes
expect "vgshell still holds that one call once the window closed" '[["ipc", "call", "shell", "summon", "window", "vgs.settings", "{}"]]' sys_calls_all
press_system || fail "typing SUPER+PERIOD again failed"
expect_poll "SUPER+PERIOD reopens on the section shown last" '["acme.pane-alt"]' window_panes
expect_poll "the reopened window starts with an empty query" '""' sys_search
press_system || fail "typing SUPER+PERIOD to close failed"
expect_poll "SUPER+PERIOD closes the open System window" 0 window_count "System Settings"
# Control: SUPER+COMMA, typed as SUPER+PERIOD is, opens no System window.
sys_never_opens() { local got; for _ in $(seq 1 10); do got="$(window_count "System Settings")" || return 1; [[ $got == 0 ]] || { echo opened; return 0; }; sleep 0.2; done; echo closed; }
type_keys -M logo -k comma -m logo || fail "control: typing SUPER+COMMA failed"
expect "control: SUPER+COMMA opens no System window" closed sys_never_opens
hypr_lua_restore system-window || fail "hyprland.lua is put back after the System keyboard path"
expect "the nested instance reloads hyprland.lua as the row found it" ok hypr reload config-only

# Control: a copy of the window that keeps the list it read when it
# opened. A section disabled while it is open stays listed, and the
# sidebar reading names it.
stale_dir="$home/.config/vgshell/plugins/acme.system-stale"
rm -rf -- "${stale_dir:?}"
cp -R -- "$repo/shell/plugins/vgs.system" "$stale_dir"
python3 - "$stale_dir" <<'PY'
import json, os, sys
root = sys.argv[1]
path = os.path.join(root, "manifest.json")
doc = json.load(open(path))
doc["id"], doc["name"] = "acme.system-stale", "System Copy"
del doc["hyprland"]
json.dump(doc, open(path, "w"))
qml = os.path.join(root, "Window.qml")
text = open(qml).read()
old = "readonly property var panes: shell === null ? [] : shell.panes.list"
assert text.count(old) == 1, old
changed = text.replace(old, "property var panes: []\n    onShellChanged: if (shell !== null && panes.length === 0) panes = shell.panes.list")
assert changed != text
open(qml, "w").write(changed)
PY
expect "disabling vgs.system for the stale-list control is allowed" ok ipc shell setPluginEnabled vgs.system false
rescan "rescan after adding the stale-list copy answers ok"
expect_poll "the stale-list copy is discovered" False plugin_enabled acme.system-stale
expect "enabling the stale-list copy is allowed" ok ipc shell setPluginEnabled acme.system-stale true
expect "the stale-list copy opens" ok ipc shell summon window acme.system-stale '{}'
expect_poll "the stale-list copy lists the enabled sections when it opens" '[["Connectivity","Fixtures"],["Pane Net","Pane Alt","Pane","Shell & Plugins"]]' sys_sidebar acme.system-stale
expect_poll "control: the copy's window is titled with its own name" 1 window_count "System Copy"
expect "control: no window titled System Settings is open beside the copy" 0 window_count "System Settings"
expect "disabling Pane Alt under the stale-list copy is allowed" ok ipc shell setPluginEnabled acme.pane-alt false
expect_poll "control: a sidebar that keeps its first list still lists the disabled section" '[["Connectivity","Fixtures"],["Pane Net","Pane Alt","Pane","Shell & Plugins"]]' sys_sidebar acme.system-stale
expect "hiding the stale-list copy is allowed" ok ipc shell hide window acme.system-stale
expect "disabling the stale-list copy is allowed" ok ipc shell setPluginEnabled acme.system-stale false
rm -rf -- "${stale_dir:?}"
rescan "rescan after removing the stale-list copy answers ok"
expect_poll "the stale-list copy is gone" absent plugin_enabled acme.system-stale
expect "enabling Pane Alt after the stale-list control is allowed" ok ipc shell setPluginEnabled acme.pane-alt true

# Control: a copy of the window that shows nothing in place of a section
# that leaves while shown. Disabling the shown section leaves no section
# mounted.
blank_dir="$home/.config/vgshell/plugins/acme.system-blank"
rm -rf -- "${blank_dir:?}"
cp -R -- "$repo/shell/plugins/vgs.system" "$blank_dir"
python3 - "$blank_dir" <<'PY'
import json, os, sys
root = sys.argv[1]
path = os.path.join(root, "manifest.json")
doc = json.load(open(path))
doc["id"], doc["name"] = "acme.system-blank", "System Blank"
del doc["hyprland"]
json.dump(doc, open(path, "w"))
qml = os.path.join(root, "Window.qml")
text = open(qml).read()
old = 'const reply = panes.length > 0 ? show(panes[0].id, "{}") : "ok";'
assert text.count(old) == 1, old
changed = text.replace(old, 'const reply = "ok";')
assert changed != text
open(qml, "w").write(changed)
PY
rescan "rescan after adding the blank copy answers ok"
expect_poll "the blank copy is discovered" False plugin_enabled acme.system-blank
expect "enabling the blank copy is allowed" ok ipc shell setPluginEnabled acme.system-blank true
expect "the blank copy opens on Pane Alt" ok ipc shell summon window acme.system-blank '{"pane":"acme.pane-alt"}'
expect_poll "the blank copy mounts Pane Alt" '["acme.pane-alt"]' window_panes
expect "disabling Pane Alt under the blank copy is allowed" ok ipc shell setPluginEnabled acme.pane-alt false
expect_poll "control: a window that shows nothing in place of the section that left mounts no section" '[]' window_panes
expect "hiding the blank copy is allowed" ok ipc shell hide window acme.system-blank
expect "disabling the blank copy is allowed" ok ipc shell setPluginEnabled acme.system-blank false
rm -rf -- "${blank_dir:?}"
rescan "rescan after removing the blank copy answers ok"
expect_poll "the blank copy is gone" absent plugin_enabled acme.system-blank
expect "enabling Pane Alt after the blank control is allowed" ok ipc shell setPluginEnabled acme.pane-alt true
expect "enabling vgs.system after the stale-list control is allowed" ok ipc shell setPluginEnabled vgs.system true

# Control: a shell copy whose PaneHost takes no implicit height from the
# pane, so the holder's container keeps the room alone and the tall
# section is cut to it.
if copy_tree system-pane-height && edit_tree system-pane-height shell/Hosts/PaneHost.qml 'implicitHeight: slot.instance === null ? 0 : slot.instance.implicitHeight' 'implicitHeight: 0'; then
  stop_shell
  start_shell "$sandbox/tree-system-pane-height" "$sandbox/qs-system-pane-height.log" || fail "the pane-height control shell starts"
  expect_poll "control: the pane-height shell knows vgs.system" True plugin_enabled vgs.system
  expect "control: the pane-height shell opens Pane Net" ok ipc shell summon window vgs.system '{"pane":"acme.pane-net"}'
  expect_poll "control: the pane-height shell mounts Pane Net" '["acme.pane-net"]' window_panes
  control_fit="$(sys_pane_fits acme.pane-net)" || control_fit="unreadable"
  expect "control: a holder handed no pane height cuts the tall section to the room" True python3 -c 'import sys; print(sys.argv[1].startswith("height="))' "$control_fit"
  stop_shell
  start_shell "$repo" "$sandbox/qs-restored-system.log" || fail "the shell starts again after the pane-height control"
fi
expect_poll "the restored shell knows vgs.system" True plugin_enabled vgs.system
expect "the restored shell opens Pane Net" ok ipc shell summon window vgs.system '{"pane":"acme.pane-net"}'
geometry expect_poll "the restored shell grows the page to the tall section" fits sys_pane_fits acme.pane-net
expect "hiding the System window after the controls is allowed" ok ipc shell hide window vgs.system
expect_poll "the System window is gone after the controls" 0 window_count "System Settings"

cp -- "$sys_saved" "$sys_file.tmp" && mv -T -- "$sys_file.tmp" "$sys_file"
rm -rf -- "${home:?}/.config/vgshell/plugins/acme.pane" "${home:?}/.config/vgshell/plugins/acme.pane-alt" "${home:?}/.config/vgshell/plugins/acme.pane-net" "${home:?}/.config/vgshell/plugins/acme.pane-off"
rm -f -- "$shim/vgshell"
if [[ -e $sandbox/system-vgshell.saved ]]; then mv -- "$sandbox/system-vgshell.saved" "$shim/vgshell"; fi
rescan "rescan after removing the System fixtures answers ok"
expect_poll "the System fixtures are gone after restore" absent plugin_enabled acme.pane
expect_poll "vgs.system is enabled again as the row found it" "$sys_was" plugin_enabled vgs.system
expect_poll "each shipped section the row set aside is enabled again" "$sys_aside" shipped_panes_enabled
