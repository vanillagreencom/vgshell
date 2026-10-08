# vgs.displays over the sandbox's device fakes
# (docs/architecture/validation.md § Host safety): the HID fake's Pro
# Display XDR, hidraw0, and two Studio Displays with one serial, hidraw1
# and hidraw2, which only their HID devices' directories tell apart. No
# sandbox output has an Apple model, so the helper places none of them.
# The row adds a headless output, SMOKE-DISPLAYS, beside the main one and
# enables vgs.displays and the System window.
#
# Rows: the service lists the three displays and places none, so neither
# bar shows the widget; on the keyboard alone, in System → Displays, Tab
# moves from the arrangement canvas to the XDR's slider, Up raises the XDR,
# its slider follows a level set elsewhere so the next Up steps from that
# level, and Down on its Screen choice puts it on the main output; the
# pane's IPC puts Studio A on SMOKE-DISPLAYS, so each
# bar's widget controls its own display, and a burst of 10 scroll notches
# from 1 % on the SMOKE-DISPLAYS widget makes at most 2 helper runs,
# leaves the burst's summed level, 51 %, in the fake and changes neither
# other display; the on-screen display maps on that screen alone; a
# brightness key acts on the focused output, first the main one, then
# SMOKE-DISPLAYS; the flyout lists its screen's display first; Identify
# shows every screen's name and flashes the display, then puts it back,
# also after a second press during the first, and keeps a level set while
# it runs; a closed hidraw2 reads no-access after a plugin scan, the Apple
# access entry offers Allow, the pane's access row reads it through
# `status.rows` and draws it as the one line of its Access section, with
# Allow, and the pane's Allow, through `status.act`, hands the stand-in
# terminal `vgshell system apply apple-displays`; with hidraw2 open again
# the pane draws no Access section; the choices persist in the assignments
# file and come back after the service is rebuilt, and the second Studio
# Display still waits for its own; the service holds one idle watch at
# the default 120 s and none at 0, which the rest of the row keeps, so no
# dim lands between its readings; System → Displays draws the Dimming
# section with the settings' values; after 3 s without input every display
# brighter than the dim level, 20 %, dims to it and a darker one takes no
# write, a level set while dimmed stays, and a key brings each other
# display back to its level; a stub kernel backlight, which the
# brightnessctl stand-in lists and sets, reads as a laptop panel, and a
# mouse drag on its slider in System → Displays sets it while the drag
# moves and leaves it at the drag's end, 1 %; after another program sets
# the panel to 80 %, a brightness key steps it down and up by one step
# from that level, to 75 % and back to 80 %.
#
# Control: the same 10 notches from 1 %, each sent once the run before it
# ended, make 10 helper runs and reach the same 51 %, so the burst's
# reading is the coalescing's and not a counter that cannot see more, and
# a lost or repeated notch shows in the level, which stays under the 100 %
# ceiling. A click on the panel's slider with no move sets it once, so
# the drag's two or more sets are its moves. Three copies of the pane,
# built under the shown pane with its `shell`, are read as the pane is: the
# copy as shipped draws no Access section, the copy that takes every entry
# as needed draws the ready Apple entry, and the copy that never hides the
# section keeps its heading over no line. With the dim off, 4 s without
# input write no display, so the dim's writes are the watch's. The helper
# runs and their
# levels are read from the HID fake's log, every feature report it
# served, and from the brightnessctl stand-in's calls. Every
# reading is expect_poll's: 25 reads 0.2 s apart. The row puts back the
# user file, so vgs.system and vgs.displays are as it found them, and
# removes the output, the assignments file and the stub backlight and
# gives hidraw2 its mode back. The dim settings live in the user file.
# inputs: shell/plugins/vgs.displays/* shell/plugins/vgs.system/* scripts/smoke/fixtures/devices/* shell/Core/SystemSteps.qml shell/Core/MonitorState.qml shell/Core/MonitorLogic.js shell/Core/HyprlandLayer.js shell/Core/HyprctlReader.qml shell/Hosts/BarHost.qml shell/Hosts/PluginSlot.qml shell/Core/Plugins.qml shell/Core/Lifetime.js shell/Core/PluginLogic.js shell/Hosts/PaneHost.qml shell/Hosts/OverlaySurface.qml shell/Ui/overlay/ModalDialog.qml shell/Ui/feedback/Dialog.qml shell/Ui/foundation/Scrim.qml shell/Ui/controls/FormRow.qml shell/Ui/feedback/LinkText.qml bin/vgshell-system scripts/smoke/rows/device-fakes.sh scripts/smoke/rows/start-order.sh scripts/smoke/rows/hyprland-consent.sh bin/vgshell-tui shell/Ui/controls/RowAction.qml
set -euo pipefail
devices_ready displays || return 0
# The core probes the system steps once vgs.displays holds `system`, and
# the fakes' tree keeps that probe off the host's /sys and /dev.
disp_tree="$(devices_system_tree)" || { fail "displays: the fakes' system tree: $disp_tree"; return 0; }
disp_output=SMOKE-DISPLAYS
disp_file="$home/.local/state/vgshell/plugins/vgs.displays/assignments.json"
disp_xdr=hidraw:class/hidraw/hidraw0/device
disp_a=hidraw:class/hidraw/hidraw1/device
disp_b=hidraw:class/hidraw/hidraw2/device
disp_a_key="usb:class/hidraw/hidraw1/device#VGSSMOKESTUDIO"
disp_xdr_key="usb:class/hidraw/hidraw0/device#VGSSMOKEXDR01"
disp_hidraw2="$devices_dev_root/hidraw2"
disp_user="$home/.config/vgshell/shell.json"
disp_user_saved="$sandbox/shell-before-displays.json"
cp -- "$disp_user" "$disp_user_saved"
rm -f -- "${disp_file:?}"

disp_read() { ipc smoke readInstance service vgs.displays "$1"; }
# The displays the service publishes, by HID node, as [node, state,
# percent, outputs, assigned].
disp_items() { disp_read values | py_reply '
import json, re, sys
items = json.load(sys.stdin)["displays"]["items"]
print(json.dumps([[re.search(r"hidraw\d+", d["id"]).group(0), d["state"], d["percent"], d["outputs"], d["assigned"]] for d in items]))'; }
disp_item() { disp_items | py_reply 'import json,sys; found=[d for d in json.load(sys.stdin) if d[0] == sys.argv[1]]; print(json.dumps(found[0]) if found else "absent")' "$1"; }
disp_value() { disp_read values | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]], sort_keys=True))' "$1"; }
disp_idle() { disp_read runs | py_reply 'import json,sys; r=json.load(sys.stdin); print(r["busy"] is None and r["sets"] == [] and not r["list"])'; }
disp_identifier() { disp_read outputs | py_reply 'import json,sys; print([o["identifier"] for o in json.load(sys.stdin) if o["name"] == sys.argv[1]][0])' "$1"; }
disp_widget() { ipc smoke readInstance "bar:$1" vgs.displays "$2"; }
# The HID fake's set-feature calls for a node: how many, and the last
# report one wrote.
disp_sets() { python3 - "$devices_hid_log" "$1" <<'PY'
import json, os, sys
path, node = sys.argv[1:]
rows = [json.loads(l) for l in open(path)] if os.path.exists(path) else []
print(sum(1 for r in rows if r["request"].get("device") == node and r["request"].get("request", 0) & 0xFF == 0x06))
PY
}
disp_report() { hid_fake_call "$1" 0xC0074807 01000000000000 | py_reply 'import json,sys; print(json.load(sys.stdin)["data"])'; }
# The screens each passive layer of the plugin maps on, in registration
# order: the on-screen display, Identify, then the display-trial banner.
disp_layers() { ipc smoke layerWindows vgs.displays | py_reply '
import json, sys
rows = json.load(sys.stdin)
third = len(rows) // 3
print(json.dumps([sorted(r["screen"] for r in rows[:third] if r["shown"]), sorted(r["screen"] for r in rows[third:2*third] if r["shown"])]))'; }
disp_keys() { ipc shell lent | py_reply 'import json,sys; s=json.load(sys.stdin)["shortcuts"]; print("vgs.displays:brightness-up" in s and "vgs.displays:brightness-down" in s)'; }
disp_focus() { ipc smoke focused window vgs.system | py_reply 'import json,sys; r=json.load(sys.stdin); print(json.dumps(r[:2]) if isinstance(r, list) else r)'; }
disp_widget_id() { disp_widget "$1" display | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["id"]))'; }
disp_other_sets() { echo "$(disp_sets hidraw0) $(disp_sets hidraw2)"; }
disp_panel_rows() { ipc smoke readInstance panel vgs.displays rows | py_reply 'import json,sys; print(json.dumps([r["id"] for r in json.load(sys.stdin)]))'; }
# The pane's access row for an entry, as `status.rows` lends it: [tone,
# text, action label, offered].
disp_access_row() { ipc smoke readInstance window vgs.displays accessRows | py_reply '
import json, sys
row = [r for r in json.load(sys.stdin) if r["key"] == sys.argv[1]]
print(json.dumps([row[0]["tone"], row[0]["value"]["text"], row[0]["action"]["label"], row[0]["action"]["offered"]]) if row else "absent")' "$1"; }
# The Access section as SCOPE draws it, the pane or, by its type's name, a
# copy of the pane built under it: whether its heading shows, and each
# shown row as [label, message, the shown button's text or null].
disp_access_copies=(PaneAsShipped PaneReadyDrawn PaneHeaderKept)
disp_access_drawn() { ipc smoke descendantGeometry window vgs.displays | py_reply '
import json, sys
scope, copies = sys.argv[1], sys.argv[2:]
items = json.load(sys.stdin)
def owner(at):
    while at > 0:
        if items[at]["type"] in copies: return items[at]["type"]
        at = items[at]["parent"]
    return ""
def under(at, top):
    while at > 0:
        at = items[at]["parent"]
        if at == top: return True
    return False
mine = [n for n in range(len(items)) if owner(n) == scope]
headers = [n for n in mine if items[n]["type"] == "SectionHeader" and items[n].get("text") == "Access"]
if len(headers) != 1:
    print("headers=%d" % len(headers)); sys.exit()
lines = []
for row in mine:
    if items[row].get("name") != "fieldRow" or items[row]["parent"] != items[headers[0]]["parent"] or not items[row]["visible"]: continue
    parts = [items[n] for n in mine if items[n]["visible"] and under(n, row)]
    line = lambda role: next((p.get("text") for p in parts if p["type"] in ("Label", "LinkText") and p.get("role") == role and p["parent"] == row), None)
    lines.append([line("label"), line("hint"), next((p.get("text") for p in parts if p["type"] == "RowAction"), None)])
print(json.dumps({"header": items[headers[0]]["visible"], "lines": lines}))' "${1:-}" "${disp_access_copies[@]}"; }
# disp_setting KEY VALUE: the plugin's setting KEY in the user file, a
# JSON VALUE, or `null` for the manifest's default.
disp_setting() {
  python3 - "$disp_user" "$1" "$2" <<'PY'
import json, os, sys
path, key, value = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
config = json.load(open(path))
rows = config.setdefault("plugins", [])
row = next((r for r in rows if r.get("id") == "vgs.displays"), None)
if row is None:
    row = {"id": "vgs.displays"}
    rows.append(row)
if value is None:
    row.pop(key, None)
else:
    row[key] = value
with open(path + ".tmp", "w") as out:
    json.dump(config, out)
os.replace(path + ".tmp", path)
PY
}
# The timeouts of the plugin's idle watches, as the lending record lists
# them.
# The global VRR option read from the nested compositor after the layer reload.
disp_vrr() { hypr -j getoption misc:vrr | py_reply 'import json,sys; print(json.load(sys.stdin)["int"])'; }
disp_watches() { ipc shell lent | py_reply 'import json,sys; print(json.dumps([w["timeout"] for w in json.load(sys.stdin)["idle"] if w["id"] == "vgs.displays"]))'; }
# The idle dim as the service holds it: its state, and while dimmed each
# kept display as [node, level].
disp_dim() { disp_read dim | py_reply '
import json, re, sys
dim = json.load(sys.stdin)
print(json.dumps([dim["state"]] + ([[re.search(r"hidraw\d+", k["id"]).group(0), k["percent"]] for k in dim["kept"]] if dim["state"] == "dimmed" else [])))'; }
# True when System → Displays shows a Select at each of the two values
# given: the Dimming section's, since every other Select names a screen.
disp_dim_drawn() { ipc smoke itemTexts window vgs.displays Select | py_reply 'import json,sys; t=json.load(sys.stdin); print(all(any(v in texts for texts in t) for v in sys.argv[1:]))' "$1" "$2"; }
disp_all_sets() { echo "$(disp_sets hidraw0) $(disp_sets hidraw1) $(disp_sets hidraw2)"; }
disp_file_entries() { python3 -c 'import json,sys; print(json.dumps(sorted([e["device"], e["output"]] for e in json.load(open(sys.argv[1]))["assignments"])))' "$disp_file"; }

disp_main="$(hypr -j monitors | py_reply 'import json,sys; print(sorted(json.load(sys.stdin), key=lambda m: m["id"])[0]["name"])')" || { fail "displays: the main output is unreadable"; return 0; }
device_reply_clear ddcutil

expect "enabling the System window for the displays pane is allowed" ok ipc shell setPluginEnabled vgs.system true
expect "enabling vgs.displays is allowed" ok ipc shell setPluginEnabled vgs.displays true
# The default set rows/start-order.sh leaves enables the plugin without
# its widget in the bar.
expect "placing the displays widget is allowed" ok ipc shell setPluginPlaced vgs.displays true
expect_poll "the displays service is built" True record_exists vgs.displays
expect_poll "the service watches for 120 s without input, the dim's default" '[120]' disp_watches
disp_setting dimAfterSeconds 0
expect_poll "with the dim off the service holds no idle watch" '[]' disp_watches
# rows/device-fakes.sh left the XDR's report at 20000, 40 %.
expect_poll "the service lists the three Apple displays and places none" \
  '[["hidraw0", "ready", 40, [], false], ["hidraw1", "ready", 50, [], false], ["hidraw2", "ready", 70, [], false]]' disp_items
expect_poll "the service registered both brightness keys" True disp_keys
for disp_vrr_choice in 1 2 3 0; do
  disp_setting vrr "$disp_vrr_choice"
  expect "the configuration reloads for the global VRR choice" ok ipc shell reloadConfig
  expect_poll "the layer writes global misc:vrr=$disp_vrr_choice" "$disp_vrr_choice" disp_vrr
done
disp_setting vrr null
expect "the configuration reloads with the VRR choice removed" ok ipc shell reloadConfig
expect_poll "removing the choice restores Hyprland's VRR default" 0 disp_vrr
expect "the widget hides while no display lights its screen" false disp_widget "$disp_main" visible
expect "the two Studio Displays wait for a choice, and no choice is saved" '{"entries": [], "error": null}' disp_value assignments

# The keyboard alone, in System → Displays: the pane opens on the
# arrangement canvas, Tabs past Use this display, which the only output
# cannot turn off, to Resolution, since one output has nothing to mirror,
# past Colour depth, the one colour row a panel with no EDID shows, and on to the XDR's slider, Up raises it one step,
# Tab reaches its Screen choice and Down picks the first output, the main
# one.
read -r mon_w mon_h < <(hypr -j monitors | py_reply 'import json,sys; m=json.load(sys.stdin)[0]; print(m["width"], m["height"])')
rest_pointer || fail "moving the pointer off the bar failed"
expect "the deep link opens the System window on Displays" ok ipc shell summon window vgs.system '{"pane":"vgs.displays"}'
expect_poll "the System window mounts the displays pane" '["vgs.displays"]' window_panes
expect_poll "the pane opens with the keyboard on the arrangement canvas" '["Arrangement", "Display arrangement"]' disp_focus
# The copies keep the production layout and substitute only the holding
# trial and capable-panel input. The headless output has no VRR panel.
# Typed properties report the actual card geometry and row parents.
# Each control changes shipped QML in a fresh directory before Qt reads it.
disp_layout_dir="$(mktemp -d "$repo/shell/plugins/vgs.displays/layout-copies.XXXXXX")" || { fail "the display layout copies cannot be allocated"; return 0; }
python3 - "$repo/shell/plugins/vgs.displays/Pane.qml" "$repo/shell/Ui/overlay/ModalDialog.qml" "$disp_layout_dir" <<'PY'
from pathlib import Path
import sys
pane, modal, folder = Path(sys.argv[1]).read_text(), Path(sys.argv[2]).read_text(), Path(sys.argv[3])
def swap(source, old, new):
    assert source.count(old) == 1, old
    changed = source.replace(old, new)
    assert changed != source
    return changed
pane = swap(pane, 'import "DisplaysLogic.js" as Logic', 'import ".."\nimport "../DisplaysLogic.js" as Logic')
pane = swap(pane, 'property var shell: null', 'property var shell: parent.shell')
pane = swap(pane, 'readonly property bool vrrShown: shell !== null && Logic.hasVrrPanel(shell.monitors.support)', 'readonly property bool vrrShown: true')
pane = swap(pane, 'readonly property var trialState: shell === null ? ({ phase: "idle", token: "", deadline: 0, failure: "" }) : shell.monitors.trialState', 'readonly property var trialState: ({ phase: "holding", token: "", deadline: Math.floor(Date.now() / 1000) + 60, failure: "" })')
pane = swap(pane, '    function keepTrial() {', '    function keepTrial() {\n        trialActionCalls++;')
pane = swap(pane, '    function revertTrial() {', '    function revertTrial() {\n        trialActionCalls++;')
end = pane.rfind('}')
pane = pane[:end] + '''
    property int trialActionCalls: 0
    function closeBeforeLoad() { open(""); close(); }
    function hideCopyBody() { content.visible = false; }
    readonly property bool vrrGrouped: vrrRow.parent === refreshRow.parent && vrrRow.y >= refreshRow.y + refreshRow.height && vrrRow.y <= refreshRow.y + refreshRow.height + Theme.stack.group
    readonly property var modalEvidence: {
        const surface = trialDialog.children[0].item;
        if (surface === null) return { loaded: false };
        const card = surface.contentItem.children.find(child => child.modal !== undefined);
        if (card === undefined) return { loaded: true, card: false };
        const scrim = surface.contentItem.children.find(child => child.clicked !== undefined && child.color !== undefined);
        const washed = scrim !== undefined && scrim.color.toString() === Theme.color.scrim.toString() && scrim.width === surface.contentItem.width && scrim.height === surface.contentItem.height;
        const centerErrorX = card.x + card.width / 2 - surface.contentItem.width / 2;
        const centerErrorY = card.y + card.height / 2 - surface.contentItem.height / 2;
        // Qt rounds centered anchors to whole pixels on an odd-sized output.
        return { loaded: true, card: card.width > 0 && card.height > 0, modal: card.modal,
            centered: Math.abs(centerErrorX) <= 0.5 && Math.abs(centerErrorY) <= 0.5,
            focused: card.activeFocus, screen: surface.screen.name,
            scrim: washed, inputAll: surface.inputAll, scrimHovered: scrim !== undefined && scrim.children[0].containsMouse,
            x: card.x, y: card.y, width: card.width, height: card.height,
            surfaceWidth: surface.contentItem.width, surfaceHeight: surface.contentItem.height,
            centerErrorX: centerErrorX, centerErrorY: centerErrorY };
    }
''' + pane[end:]
(folder / 'PaneLayout.qml').write_text(pane)
(folder / 'ModalNotModal.qml').write_text(swap(modal, '                id: card', '                id: card\n                modal: false'))
(folder / 'ModalNotCentered.qml').write_text(swap(modal, '                anchors.centerIn: parent', '                anchors.left: parent.left\n                anchors.top: parent.top'))
(folder / 'ModalNoScrim.qml').write_text(swap(modal, '            Scrim {}', '            Item {}'))
(folder / 'ModalMasked.qml').write_text(swap(modal, '            inputAll: true', '            inputItems: [card]'))
for name, host in [('PaneNotModal', 'ModalNotModal'), ('PaneNotCentered', 'ModalNotCentered'), ('PaneNoScrim', 'ModalNoScrim'), ('PaneMasked', 'ModalMasked')]:
    (folder / (name + '.qml')).write_text(swap(pane, '    ModalDialog {', '    ' + host + ' {'))
start = pane.index('            FormRow {\n                id: vrrRow')
end = pane.index('\n            FormRow {', start + 1)
row = pane[start:end]
changed = pane[:start] + pane[end:]
at = changed.index('    Column {\n        id: content')
changed = changed[:at] + row + '\n' + changed[at:]
assert changed != pane
(folder / 'PaneVrrOutside.qml').write_text(changed)
PY
disp_modal_read() { ipc smoke popupRead "displays-layout-$1" modalEvidence; }
disp_modal_focus() { disp_modal_read PaneLayout | py_reply 'import json,sys; print(json.load(sys.stdin).get("focused") is True)'; }
disp_modal_matches() {
  disp_modal_read "$1" | py_reply 'import json,sys; value=json.load(sys.stdin); print(value.get("loaded") is True and value.get("card") is True and value.get("modal") is True and value.get("centered") is True and value.get("screen")==sys.argv[1])' "$disp_main"
}
disp_bottom="$(ipc smoke revealText window vgs.system FormRow "Dimmed brightness")" || { fail "the System page cannot scroll for the modal test"; return 0; }
[[ $disp_bottom =~ ^[0-9.]+$ ]] || fail "the System page scroll is unavailable: $disp_bottom"
disp_page_at_bottom() {
  ipc smoke viewHolding window vgs.system "Dimmed brightness" | py_reply 'import json,sys; value=json.load(sys.stdin); print(value["contentY"] > 0 and abs(value["contentY"] - max(0,value["contentHeight"] - value["height"])) < 0.5)'
}
geometry expect_poll "the System page reaches its bottom before the modal test" True disp_page_at_bottom
disp_scrim_matches() {
  disp_modal_read "$1" | py_reply 'import json,sys; v=json.load(sys.stdin); print(v.get("loaded") is True and v.get("card") is True and v.get("scrim") is True and v.get("inputAll") is True)'
}
for disp_layout in PaneLayout PaneNotModal PaneNotCentered PaneVrrOutside PaneNoScrim PaneMasked; do
  expect "the probe builds the layout copy $disp_layout" ok ipc smoke popupLoad "displays-layout-$disp_layout" "$disp_layout_dir/$disp_layout.qml" window vgs.displays '{"width":600}'
  expect "the layout copy closes before its modal can map" ok ipc smoke popupCall "displays-layout-$disp_layout" closeBeforeLoad
  expect "closing before mapping keeps the dialog hold count zero" 0 disp_read trialDialogs
  expect "the layout copy opens through its pane lifecycle" ok ipc smoke popupCall "displays-layout-$disp_layout" open
  expect_poll "the mapped layout copy holds one passive-banner suppression" 1 disp_read trialDialogs
  if [[ $disp_layout == PaneLayout ]]; then
    geometry expect_poll "the display trial is modal and centered on its screen at the bottom scroll" True disp_modal_matches "$disp_layout"
    expect_poll "the display trial takes keyboard focus" True disp_modal_focus
    expect_poll "the modal has a full shared scrim and full input region" True disp_scrim_matches "$disp_layout"
    expect_poll "the VRR row follows Refresh rate in the display group" true ipc smoke popupRead "displays-layout-$disp_layout" vrrGrouped
    expect "the disposable body hides for real-page pointer checks" ok ipc smoke popupCall "displays-layout-$disp_layout" hideCopyBody
    read -r disp_bg_x disp_bg_y < <(at_centre "window:System Settings" "$(control_box window vgs.system ListItem 'Shell & Plugins')")
    hover "$disp_bg_x" "$disp_bg_y" || fail "hovering behind the trial failed"
    disp_scrim_hovered() { disp_modal_read PaneLayout | py_reply 'import json,sys; print(json.load(sys.stdin).get("scrimHovered") is True)'; }
    expect_poll "the scrim takes background hover" True disp_scrim_hovered
    expect "the Settings sidebar does not take hover through the scrim" false control_hovered window vgs.system ListItem 'Shell & Plugins'
    click "$disp_bg_x" "$disp_bg_y" || fail "clicking the trial scrim failed"
    expect "clicking the trial scrim does not activate the sidebar" 0 window_count Plugins
    expect "clicking the trial scrim calls neither Keep nor Revert" 0 ipc smoke popupRead displays-layout-PaneLayout trialActionCalls
    disp_page_before="$(ipc smoke viewHolding window vgs.system 'Dimmed brightness')"
    # Use the blank left gutter. The former bottom-right point landed on
    # Dimmed brightness's Select, not a blank part of the scrolling page.
    disp_wheel_evidence="$(python3 -c 'import json,sys
page,window,surface,card,items=[json.loads(a) for a in sys.argv[1:]]
x,y,w,h=page["box"]; px,py=x+2,y+h-20
sx,sy=window[0]+px,window[1]+py
cx,cy=surface[0]+card["x"],surface[1]+card["y"]
assert x<px<x+w and y<py<y+h
assert not(cx<=sx<cx+card["width"] and cy<=sy<cy+card["height"])
assert not any(i["type"]=="Select" and i["visible"] and i["box"][0]<=px<i["box"][0]+i["box"][2] and i["box"][1]<=py<i["box"][1]+i["box"][3] for i in items)
print(json.dumps({"point":[int(sx),int(sy)],"page":page["box"],"card":[cx,cy,card["width"],card["height"]],"outsideCard":True,"outsideSelects":True}))' "$disp_page_before" "$(surface_box 'window:System Settings')" "$(surface_box vgs:dialog)" "$(disp_modal_read PaneLayout)" "$(ipc smoke descendantGeometry window vgs.displays)")"
    printf '  display-background-point=%s\n' "$disp_wheel_evidence"
    read -r disp_wheel_x disp_wheel_y < <(py_reply 'import json,sys; print(*json.load(sys.stdin)["point"])' <<<"$disp_wheel_evidence")
    wheel "$disp_wheel_x" "$disp_wheel_y" -2 || fail "wheeling behind the trial failed"
    sleep 0.2
    expect "the trial scrim blocks the Settings page wheel" "$disp_page_before" ipc smoke viewHolding window vgs.system 'Dimmed brightness'
    disp_copy_holding() { ipc smoke popupRead displays-layout-PaneLayout trialState | py_reply 'import json,sys; print(json.load(sys.stdin)["phase"])'; }
    expect "the trial remains holding after background input" holding disp_copy_holding

  elif [[ $disp_layout == PaneNoScrim || $disp_layout == PaneMasked ]]; then
    geometry expect_poll "control: $disp_layout retains its modal centered card" True disp_modal_matches "$disp_layout"
    expect_poll "control: $disp_layout fails the scrim and full input contract" False disp_scrim_matches "$disp_layout"
    if [[ $disp_layout == PaneMasked ]]; then
      expect "the masked copy hides its disposable body for real-page input" ok ipc smoke popupCall "displays-layout-$disp_layout" hideCopyBody
      disp_masked_before="$(ipc smoke viewHolding window vgs.system 'Dimmed brightness')"
      hover "$((disp_wheel_x+1))" "$disp_wheel_y" || fail "entering the masked wheel gutter failed"
      hover "$disp_wheel_x" "$disp_wheel_y" || fail "resting on the masked wheel gutter failed"
      geometry expect_poll "control: the masked modal remains mapped before its wheel" True disp_modal_matches "$disp_layout"
      wheel "$disp_wheel_x" "$disp_wheel_y" -2 || fail "the masked modal wheel control failed"
      disp_masked_page_moved() { ipc smoke viewHolding window vgs.system 'Dimmed brightness' | py_reply 'import json,sys; before=json.loads(sys.argv[1]); after=json.load(sys.stdin); print(abs(before["contentY"]-after["contentY"])>=1)' "$disp_masked_before"; }
      expect_poll "control: a card-only input region lets the same wheel move the page" True disp_masked_page_moved
      ipc smoke revealText window vgs.system FormRow 'Dimmed brightness' >/dev/null
      geometry expect_poll "control: the masked modal retains its real card after scrolling" True disp_modal_matches "$disp_layout"
      printf '  modal-evidence expected-screen=%s copy=%s before-sidebar-action=' "$disp_main" "$disp_layout"
      disp_modal_read "$disp_layout"
      # The real sidebar action replaces the pane and destroys this copy.
      # Check the native mutant before that action and its teardown after.
      disp_masked_hover() { hover "$((disp_bg_x+1))" "$disp_bg_y" >/dev/null && hover "$disp_bg_x" "$disp_bg_y" >/dev/null && control_hovered window vgs.system ListItem 'Shell & Plugins'; }
      expect_poll "control: a card-only input region lets the sidebar take hover" true disp_masked_hover
      click "$disp_bg_x" "$disp_bg_y" || fail "clicking the masked sidebar control failed"
      expect_poll "control: a card-only input region lets the sidebar open Plugins" 1 window_count Plugins
      expect_poll "the unblocked sidebar action removes the copied modal" 0 layer_count vgs:dialog
      expect_poll "the unblocked sidebar action releases the copied dialog hold" 0 disp_read trialDialogs
      expect_poll "the unblocked sidebar action destroys its disposable pane" undefined ipc smoke popupRead "displays-layout-$disp_layout" modalEvidence
      expect "the masked sidebar control closes Plugins" ok ipc shell hide window vgs.settings
      expect_poll "the masked sidebar control closes its Plugins window" 0 window_count Plugins

    fi
  elif [[ $disp_layout == PaneVrrOutside ]]; then
    expect_poll "control: the VRR row outside the display group is rejected" false ipc smoke popupRead "displays-layout-$disp_layout" vrrGrouped
  else
    disp_modal_expected='[false, true]'
    [[ $disp_layout != PaneNotCentered ]] || disp_modal_expected='[true, false]'
    disp_modal_control() {
      disp_modal_read "$disp_layout" | py_reply 'import json,sys; value=json.load(sys.stdin); print(value.get("loaded") is True and value.get("card") is True and value.get("screen")==sys.argv[1] and [value.get("modal"),value.get("centered")]==json.loads(sys.argv[2]))' "$disp_main" "$disp_modal_expected"
    }
    geometry expect_poll "control: $disp_layout keeps a drawn card and breaks only its named property" True disp_modal_control
    geometry expect_poll "control: $disp_layout fails the modal and centering contract" False disp_modal_matches "$disp_layout"
  fi
  if [[ $disp_layout == PaneMasked ]]; then
    # The owning pane was destroyed by the sidebar route. The probe's
    # dead reference ends with its next shell, so do not call its methods.
    continue
  fi
  printf '  modal-evidence expected-screen=%s copy=%s value=' "$disp_main" "$disp_layout"
  disp_modal_read "$disp_layout"
  if [[ $disp_layout == PaneVrrOutside ]]; then
    expect "the destruction control still has a mapped dialog hold" 1 disp_read trialDialogs
    expect "the probe destroys a still-open layout copy" ok ipc smoke popupDrop "displays-layout-$disp_layout"
    expect_poll "destroying a mapped copy releases its one dialog hold" 0 disp_read trialDialogs
    expect_poll "destroying a mapped copy removes its modal surface" 0 layer_count vgs:dialog
  else
    expect "closing the layout copy hides its modal" ok ipc smoke popupCall "displays-layout-$disp_layout" close
    expect_poll "closing the layout copy releases its one dialog hold" 0 disp_read trialDialogs
    expect "the probe drops the layout copy $disp_layout" ok ipc smoke popupDrop "displays-layout-$disp_layout"
  fi
done
expect "destroying already-closed copies leaves no dialog hold" 0 disp_read trialDialogs
rm -r -- "${disp_layout_dir:?}" || fail "removing the display layout copies failed"
expect_poll "destroying the display layout copies removes their modal surfaces" 0 layer_count vgs:dialog
# A real guarded mode trial outlives its Settings pane. Closing Settings
# removes the modal and restores the passive banner without ending the trial.
disp_banner_screens() { ipc smoke layerWindows vgs.displays | py_reply 'import json,sys; rows=json.load(sys.stdin); print(json.dumps(sorted(r["screen"] for r in rows[2*(len(rows)//3):] if r["shown"])))'; }
disp_trial_phase() { ipc smoke readInstance window vgs.displays trialState | py_reply 'import json,sys; print(json.load(sys.stdin)["phase"])'; }
disp_mode_args="$(ipc smoke readInstance window vgs.displays selectedRule | py_reply 'import json,sys; mode=json.load(sys.stdin)["mode"]; mode["refresh"]=75; print(json.dumps({"args":[{"mode":mode}]}))')"
expect "the mode draft starts the real banner lifecycle test" "" ipc smoke invokeInstanceArgs window vgs.displays setOutputDraft "$disp_mode_args"
expect "the real display trial starts" "" ipc smoke invokeInstance window vgs.displays applyOutputDraft ''
expect_poll "the real trial holds" holding disp_trial_phase
expect_poll "the real trial modal suppresses the passive banner" 1 disp_read trialDialogs
expect "the passive trial banner is hidden while its modal is mapped" '[]' disp_banner_screens
click "$disp_bg_x" "$disp_bg_y" || fail "clicking the real trial scrim failed"
expect "a real trial keeps holding after its scrim is clicked" holding disp_trial_phase
expect "Settings closes during the real holding trial" ok ipc shell hide window vgs.system
expect_poll "closing Settings removes the real modal" 0 layer_count vgs:dialog
expect_poll "closing Settings releases its dialog hold" 0 disp_read trialDialogs
expect_poll "the passive banner returns with Settings closed" "[\"$disp_main\"]" disp_banner_screens
expect "Settings reopens during the holding trial" ok ipc shell summon window vgs.system '{"pane":"vgs.displays"}'
expect_poll "reopening Settings restores one dialog hold" 1 disp_read trialDialogs
expect "the reopened pane reverts the real trial" "" ipc smoke invokeInstance window vgs.displays revertTrial ''
expect_poll "reverting clears the dialog hold" 0 disp_read trialDialogs
ipc smoke revealText window vgs.system SectionHeader Display >/dev/null || fail "restoring the System page scroll failed"
expect "the System window restores Displays after the modal test" ok ipc shell summon window vgs.system '{"pane":"vgs.displays"}'
expect_poll "the arrangement regains keyboard focus after the modal test" '["Arrangement", "Display arrangement"]' disp_focus
type_keys -k Tab -k Tab || fail "typing Tab to the Resolution choice failed"
expect_poll "Tab passes the Use this display switch the only display cannot turn off, and no Mirror choice, to Resolution" '["Select", "Resolution"]' disp_focus
type_keys -k Tab -k Tab -k Tab -k Tab || fail "typing Tab to the Colour depth choice failed"
expect_poll "Tab reaches Colour depth, the one colour row the nested panel shows" '["Select", "Colour depth"]' disp_focus
type_keys -k Tab || fail "typing Tab to the XDR's slider failed"
expect_poll "Tab reaches the XDR's slider" '["Slider", "Apple Pro Display XDR"]' disp_focus
disp_xdr_sets="$(disp_sets hidraw0)"
type_keys -k Up || fail "typing Up on the XDR's slider failed"
expect_poll "Up on the slider raises the XDR to 41" '["hidraw0", "ready", 41, [], false]' disp_item hidraw0
expect_poll "the helper wrote the XDR once" "$((disp_xdr_sets + 1))" disp_sets hidraw0
# A level set elsewhere moves the slider's handle, so the next Up steps
# from it and not from the handle's old place.
expect "the XDR is set to 30 % while the pane is open" ok ipc vgs.displays invoke set "{\"id\":\"$disp_xdr\",\"percent\":30}"
expect_poll "the service shows the XDR at 30 %" '["hidraw0", "ready", 30, [], false]' disp_item hidraw0
type_keys -k Up || fail "typing Up on the XDR's slider again failed"
expect_poll "Up after the outside change raises the XDR to 31" '["hidraw0", "ready", 31, [], false]' disp_item hidraw0
type_keys -k Tab || fail "typing Tab in the pane failed"
expect_poll "Tab reaches the XDR's Screen choice" '["Select", "Screen for Apple Pro Display XDR"]' disp_focus
type_keys -k Down || fail "typing Down on the Screen choice failed"
expect_poll "Down on the Screen choice puts the XDR on the main output" "[\"hidraw0\", \"ready\", 31, [\"$disp_main\"], true]" disp_item hidraw0
expect_poll "the main bar's widget shows for the XDR" true disp_widget "$disp_main" visible
expect "hiding the System window after the keyboard path is allowed" ok ipc shell hide window vgs.system
expect_poll "the System window is gone" 0 window_count "System Settings"

# A second output, whose bar's widget hides until a display lights it.
expect "the nested compositor adds a monitor for the displays rows" ok hypr output create headless "$disp_output"
expect_poll "the new monitor gets a bar" "$((monitors + 1))" bar_count
expect_poll "the new bar's widget hides while no display lights its screen" false disp_widget "$disp_output" visible

# Studio A on the new output, as the pane's Screen choice asks.
disp_new_id="$(disp_identifier "$disp_output")" || { fail "displays: the new output's identifier is unreadable"; return 0; }
disp_main_id="$(disp_identifier "$disp_main")" || { fail "displays: the main output's identifier is unreadable"; return 0; }
expect "the pane's choice puts Studio A on the new output" ok ipc vgs.displays invoke assign "{\"device\":\"$disp_a_key\",\"output\":\"$disp_new_id\"}"
expect_poll "Studio A lights the new output" "[\"hidraw1\", \"ready\", 50, [\"$disp_output\"], true]" disp_item hidraw1
expect_poll "the new bar's widget controls Studio A" "\"$disp_a\"" disp_widget_id "$disp_output"
expect "the second Studio Display still waits for its own choice" '["hidraw2", "ready", 70, [], false]' disp_item hidraw2
expect "an output no display could take is refused" "refused: assign=$disp_a_key output=DP-404 reason=absent" ipc vgs.displays invoke assign "{\"device\":\"$disp_a_key\",\"output\":\"DP-404\"}"

# A burst of 10 scroll notches up from 1 % on the new bar's widget, in one
# turn as a fast drag lands between two frames: at most two helper runs,
# the last carrying the burst's level, 1 + 10 × 5 = 51 %; neither other
# display changes.
expect "Studio A is set to 1 % for the burst" ok ipc vgs.displays invoke set "{\"id\":\"$disp_a\",\"percent\":1}"
expect_poll "the helper is idle before the burst" True disp_idle
disp_a_sets="$(disp_sets hidraw1)"
disp_xdr_sets="$(disp_sets hidraw0)"
disp_b_sets="$(disp_sets hidraw2)"
expect "the burst's 10 notches each answer ok" "$(python3 -c 'import json; print(json.dumps(["ok"] * 10, separators=(",", ":")))')" ipc smoke invokeBurst "bar:$disp_output" vgs.displays scroll 1 10
expect_poll "the helper is idle after the burst" True disp_idle
disp_burst_runs() { echo "$(( $(disp_sets hidraw1) - disp_a_sets ))"; }
disp_burst_at_most_two() { local runs; runs="$(disp_burst_runs)"; if ((runs >= 1 && runs <= 2)); then echo "1-2"; else echo "$runs"; fi; }
expect "the 10-notch burst made one or two helper runs" "1-2" disp_burst_at_most_two
# The Studio Display's report for 51 %: 400 + 51 % of 400..60000, 30796,
# little-endian after report id 1 (helper/brightness.py raw_from_percent).
expect "the fake holds the burst's summed level, 51 %" 014c7800000000 disp_report hidraw1
expect "the service shows Studio A at 51 %" "[\"hidraw1\", \"ready\", 51, [\"$disp_output\"], true]" disp_item hidraw1
expect "the burst wrote no other display" "$disp_xdr_sets $disp_b_sets" disp_other_sets
expect_poll "the on-screen display maps on the new output alone" "[[\"$disp_output\"], []]" disp_layers
expect_poll "the on-screen display goes after its time" "[[], []]" disp_layers

# Control: the same 10 notches, each once the run before it ended, make
# 10 runs and reach the same level.
expect "Studio A is set to 1 % for the control" ok ipc vgs.displays invoke set "{\"id\":\"$disp_a\",\"percent\":1}"
expect_poll "the helper is idle before the control" True disp_idle
disp_a_sets="$(disp_sets hidraw1)"
for _ in $(seq 1 10); do
  expect "control: one notch answers ok" ok ipc smoke invokeInstance "bar:$disp_output" vgs.displays scroll 1
  expect_poll "control: the helper is idle after the notch" True disp_idle
done
expect "control: 10 paced notches made 10 helper runs" 10 disp_burst_runs
expect "control: the fake holds the paced notches' level, 51 %" 014c7800000000 disp_report hidraw1

# A brightness key acts on the focused output.
expect "the main output takes the focus" ok hypr dispatch "hl.dsp.focus({ monitor = \"$disp_main\" })"
expect_poll "the service reads the main output focused" "\"$disp_main\"" disp_read focusedOutput
expect "the brightness-up key is pressed" ok hypr dispatch 'hl.dsp.global("vgs.displays:brightness-up")'
expect_poll "the key raises the XDR on the focused output" "[\"hidraw0\", \"ready\", 36, [\"$disp_main\"], true]" disp_item hidraw0
expect "the key leaves Studio A" "[\"hidraw1\", \"ready\", 51, [\"$disp_output\"], true]" disp_item hidraw1
expect_poll "the key's on-screen display maps on the main output alone" "[[\"$disp_main\"], []]" disp_layers
expect "the new output takes the focus" ok hypr dispatch "hl.dsp.focus({ monitor = \"$disp_output\" })"
expect_poll "the service reads the new output focused" "\"$disp_output\"" disp_read focusedOutput
expect "the brightness-down key is pressed" ok hypr dispatch 'hl.dsp.global("vgs.displays:brightness-down")'
expect_poll "the key dims Studio A on the focused output" "[\"hidraw1\", \"ready\", 46, [\"$disp_output\"], true]" disp_item hidraw1
expect "the key leaves the XDR" "[\"hidraw0\", \"ready\", 36, [\"$disp_main\"], true]" disp_item hidraw0
expect_poll "the helper is idle after the keys" True disp_idle

# The flyout on the new output lists Studio A first.
expect "the new output takes the focus for the flyout" ok hypr dispatch "hl.dsp.focus({ monitor = \"$disp_output\" })"
expect_poll "the service reads the new output focused for the flyout" "\"$disp_output\"" disp_read focusedOutput
expect "the flyout opens on the focused output" ok ipc shell summon panel vgs.displays '{}'
expect_poll "the flyout is on the new output" "\"$disp_output\"" ipc smoke readInstance panel vgs.displays screenName
expect_poll "the flyout lists its screen's display first" "[\"$disp_a\", \"$disp_xdr\", \"$disp_b\"]" disp_panel_rows
expect "hiding the flyout is allowed" ok ipc shell hide panel vgs.displays

# Identify: every screen shows its name and Studio A shows its other level,
# then goes back.
disp_a_sets="$(disp_sets hidraw1)"
expect "Identify answers ok" ok ipc vgs.displays invoke identify "$disp_a"
expect_poll "Identify shows on every screen" "$(python3 -c 'import json,sys; print(json.dumps([[], sorted(sys.argv[1:])]))' "$disp_main" "$disp_output")" disp_layers
expect_poll "Identify flashes Studio A, below 50 %, at 100 %" "[\"hidraw1\", \"ready\", 100, [\"$disp_output\"], true]" disp_item hidraw1
expect_poll "Identify ends" "[[], []]" disp_layers
expect_poll "Identify puts Studio A back at 46 %" "[\"hidraw1\", \"ready\", 46, [\"$disp_output\"], true]" disp_item hidraw1
expect_poll "the helper is idle after Identify" True disp_idle
expect "Identify wrote Studio A twice" "$((disp_a_sets + 2))" disp_sets hidraw1
# A second press during the first still puts back the user's level, not
# the first press's flash level.
expect "Identify answers ok again" ok ipc vgs.displays invoke identify "$disp_a"
expect "a second Identify during the first answers ok" ok ipc vgs.displays invoke identify "$disp_a"
expect_poll "the second Identify ends" "[[], []]" disp_layers
expect_poll "the helper is idle after the second Identify" True disp_idle
expect "two presses put Studio A back at 46 %" "[\"hidraw1\", \"ready\", 46, [\"$disp_output\"], true]" disp_item hidraw1
# A level set while Identify runs is the one that stays.
expect "Identify answers ok a third time" ok ipc vgs.displays invoke identify "$disp_a"
expect_poll "Identify flashes Studio A again" "[\"hidraw1\", \"ready\", 100, [\"$disp_output\"], true]" disp_item hidraw1
expect "Studio A is set to 60 % during Identify" ok ipc vgs.displays invoke set "{\"id\":\"$disp_a\",\"percent\":60}"
expect_poll "the third Identify ends" "[[], []]" disp_layers
expect_poll "the helper is idle after the third Identify" True disp_idle
expect "Identify keeps the level set while it ran, 60 %" "[\"hidraw1\", \"ready\", 60, [\"$disp_output\"], true]" disp_item hidraw1

# A display the user may not open: after a plugin scan probes the steps
# again, Studio B reads no-access and the Apple entry offers Allow, which
# the pane hands to the core through status.act.
disp_hidraw2_mode="$(stat -c %a -- "$disp_hidraw2")" || { fail "displays: the HID fake planted no hidraw2"; return 0; }
chmod 0000 "$disp_hidraw2"
rescan "a rescan with hidraw2 closed answers ok"
expect_poll "the Apple access entry offers Allow" '{"action": true, "text": "Needs your permission", "tone": "warning"}' disp_value appleAccess
expect_poll "Studio B reads no-access" '["hidraw2", "no-access", null, [], false]' disp_item hidraw2
terminal_stand_in
terminal_ready "displays"
expect "the deep link opens System → Displays again" ok ipc shell summon window vgs.system '{"pane":"vgs.displays"}'
expect_poll "the System window mounts the displays pane again" '["vgs.displays"]' window_panes
expect_poll "the pane's Apple access row, from status.rows, offers Allow in the warning tone" '["warning", "Needs your permission", "Allow", true]' disp_access_row appleAccess
expect_poll "the pane draws the one step that is needed as one line with its action" '{"header": true, "lines": [["Apple displays", "Needs your permission", "Allow"]]}' disp_access_drawn
forget_record
expect "the pane's Allow, through status.act, answers ok" ok ipc smoke invokeInstance window vgs.displays runAction appleAccess
expect_poll "Allow hands the terminal vgshell system apply apple-displays" \
  "$(core_words core/system "System setup" org.vgs.tui system apply apple-displays)" recorded
expect_run_end "the Allow core/system run ends" core/system
forget_record
chmod "$disp_hidraw2_mode" "$disp_hidraw2"
rescan "a rescan with hidraw2 open again answers ok"
expect_poll "the Apple access entry reads allowed again" '{"action": false, "text": "Allowed", "tone": "ok"}' disp_value appleAccess
expect_poll "Studio B reads ready again" '["hidraw2", "ready", 70, [], false]' disp_item hidraw2
expect_poll "with every step ready the pane draws no Access section" '{"header": false, "lines": []}' disp_access_drawn
# Copies of the shipped pane, built under the shown pane and reading its
# `shell`: one as shipped, one that takes every access entry as needed and
# one whose Access section never hides. The type loader keeps the listing
# of a directory it has read, so the copies go in a fresh
# folder, named as the types they make, and import the plugin's directory
# for its rows and its logic. A copy takes no focus from the pane.
disp_copy_dir="$repo/shell/plugins/vgs.displays/access-copies"
mkdir -- "$disp_copy_dir"
python3 - "$repo/shell/plugins/vgs.displays/Pane.qml" "$disp_copy_dir" "${disp_access_copies[@]}" <<'PY'
import pathlib, sys
source, folder, shipped, ready_drawn, header_kept = pathlib.Path(sys.argv[1]).read_text(), pathlib.Path(sys.argv[2]), *sys.argv[3:]
def swap(text, needle, replacement):
    assert text.count(needle) == 1, needle
    return text.replace(needle, replacement)
copy = swap(source, 'import "DisplaysLogic.js" as Logic\n', 'import ".."\nimport "../DisplaysLogic.js" as Logic\n')
copy = swap(copy, "    property var shell: null\n", "    property var shell: parent.shell\n")
copy = swap(copy, "    focus: true\n", "    focus: false\n")
(folder / (shipped + ".qml")).write_text(copy)
(folder / (ready_drawn + ".qml")).write_text(swap(copy, "Logic.accessNeeded(r.value)", "true"))
(folder / (header_kept + ".qml")).write_text(swap(copy, "            visible: root.accessRows.length > 0\n", "            visible: true\n"))
PY
disp_ready_drawn() { disp_access_drawn PaneReadyDrawn | py_reply 'import json,sys; d=json.load(sys.stdin); print(d["header"] and ["Apple displays", "Allowed", None] in d["lines"])'; }
for disp_copy in "${disp_access_copies[@]}"; do
  expect "the probe builds the pane copy $disp_copy" ok ipc smoke popupLoad "displays-$disp_copy" "$disp_copy_dir/$disp_copy.qml" window vgs.displays '{"width": 600}'
done
expect_poll "the pane copy as shipped draws no Access section" '{"header": false, "lines": []}' disp_access_drawn PaneAsShipped
expect_poll "control: a pane that takes every entry as needed draws the ready Apple entry" True disp_ready_drawn
expect_poll "control: a pane that never hides the section keeps its heading over no line" '{"header": true, "lines": []}' disp_access_drawn PaneHeaderKept
for disp_copy in "${disp_access_copies[@]}"; do
  expect "the probe drops the pane copy $disp_copy" ok ipc smoke popupDrop "displays-$disp_copy"
done
rm -r -- "${disp_copy_dir:?}" || fail "removing the pane copies failed"
expect "hiding the System window is allowed" ok ipc shell hide window vgs.system

# The choices persist: the file holds both, and a rebuilt service applies
# them again while Studio B still waits.
expect "the assignments file holds both choices" "$(python3 -c 'import json,sys; print(json.dumps(sorted([[sys.argv[1], sys.argv[2]], [sys.argv[3], sys.argv[4]]])))' "$disp_a_key" "$disp_new_id" "$disp_xdr_key" "$disp_main_id")" disp_file_entries
expect "disabling vgs.displays is allowed" ok ipc shell setPluginEnabled vgs.displays false
expect_poll "the displays service is gone" False record_exists vgs.displays
expect "enabling vgs.displays again is allowed" ok ipc shell setPluginEnabled vgs.displays true
expect_poll "the rebuilt service puts Studio A on the new output from the file" "[\"hidraw1\", \"ready\", 60, [\"$disp_output\"], true]" disp_item hidraw1
expect "the rebuilt service puts the XDR on the main output from the file" "[\"hidraw0\", \"ready\", 36, [\"$disp_main\"], true]" disp_item hidraw0
expect "the second Studio Display still waits after the rebuild" '["hidraw2", "ready", 70, [], false]' disp_item hidraw2

# The idle dim over the three displays: the XDR at 10 %, below the dim
# level, Studio A at 60 % and Studio B at 70 %. System → Displays draws
# the Dimming section with the settings' values.
expect "the XDR is set to 10 % for the dim" ok ipc vgs.displays invoke set "{\"id\":\"$disp_xdr\",\"percent\":10}"
expect_poll "the helper is idle before the dim" True disp_idle
expect "the deep link opens System → Displays for the dim" ok ipc shell summon window vgs.system '{"pane":"vgs.displays"}'
expect_poll "the System window mounts the displays pane for the dim" '["vgs.displays"]' window_panes
expect_poll "the Dimming section draws the dim off at the default level" True disp_dim_drawn Never 30%
disp_setting dimPercent 20
expect_poll "the Dimming section follows the dim level" True disp_dim_drawn Never 20%
expect "hiding the System window before the dim is allowed" ok ipc shell hide window vgs.system
expect_poll "the System window is gone before the dim" 0 window_count "System Settings"
expect_poll "the helper is idle before the dim's watch" True disp_idle
disp_xdr_sets="$(disp_sets hidraw0)"
disp_setting dimAfterSeconds 3
expect_poll "the service watches for 3 s without input" '[3]' disp_watches
expect_poll "3 s without input dim the displays above 20 %, keeping their levels" '["dimmed", ["hidraw1", 60], ["hidraw2", 70]]' disp_dim
expect_poll "the helper is idle after the dim" True disp_idle
expect "the dim set Studio A and Studio B to 20 % and left the darker XDR" \
  "[[\"hidraw0\", \"ready\", 10, [\"$disp_main\"], true], [\"hidraw1\", \"ready\", 20, [\"$disp_output\"], true], [\"hidraw2\", \"ready\", 20, [], false]]" disp_items
# 400 + 20 % of 400..60000, 12320, little-endian after report id 1.
expect "the fake holds Studio A at 20 %" 01203000000000 disp_report hidraw1
expect "the dim wrote nothing to the darker XDR" "$disp_xdr_sets" disp_sets hidraw0
expect "Studio B is set to 40 % while dimmed" ok ipc vgs.displays invoke set "{\"id\":\"$disp_b\",\"percent\":40}"
expect_poll "a level set while dimmed is no longer kept" '["dimmed", ["hidraw1", 60]]' disp_dim
expect_poll "the helper is idle after the set while dimmed" True disp_idle
type_keys -k Shift_L || fail "typing a key to end the dim failed"
expect_poll "a key ends the dim" '["awake"]' disp_dim
# A longer watch keeps a second dim off the readings below; the service
# is awake, so the new watch writes nothing.
disp_setting dimAfterSeconds 600
expect_poll "the service watches for 600 s without input" '[600]' disp_watches
expect_poll "a key brings Studio A back to 60 %, keeps Studio B at 40 % and the XDR at 10 %" \
  "[[\"hidraw0\", \"ready\", 10, [\"$disp_main\"], true], [\"hidraw1\", \"ready\", 60, [\"$disp_output\"], true], [\"hidraw2\", \"ready\", 40, [], false]]" disp_items
# 400 + 60 % of 400..60000, 36160.
expect_poll "the fake holds Studio A at 60 % again" 01408d00000000 disp_report hidraw1
disp_setting dimAfterSeconds 0
expect_poll "the dim is off again" '[]' disp_watches
expect_poll "the helper is idle with the dim off" True disp_idle
expect "turning the dim off leaves every level" \
  "[[\"hidraw0\", \"ready\", 10, [\"$disp_main\"], true], [\"hidraw1\", \"ready\", 60, [\"$disp_output\"], true], [\"hidraw2\", \"ready\", 40, [], false]]" disp_items
# Control: with the dim off, 4 s without input, past the 3 s watch above,
# write no display.
disp_quiet_sets="$(disp_all_sets)"
sleep 4
expect "control: with the dim off, 4 s without input write no display" "$disp_quiet_sets" disp_all_sets
expect "control: with the dim off the service stays awake" '["awake"]' disp_dim

# A laptop panel: a stub kernel backlight in the fakes' sysfs, which the
# brightnessctl stand-in lists at 50 % and sets to any level. A mouse drag
# on its slider in System → Displays, from near the slider's end past its
# start, sets the panel while the drag moves, the first set at a level
# between, and leaves it at 1 %.
disp_bl=vgs_smoke_panel
disp_bl_dir="$devices_sysfs_root/class/backlight/$disp_bl"
disp_bl_item() { disp_read values | py_reply '
import json, sys
found = [[d["id"], d["state"], d["percent"]] for d in json.load(sys.stdin)["displays"]["items"] if d["id"] == sys.argv[1]]
print(json.dumps(found[0]) if found else "absent")' "backlight:$disp_bl"; }
disp_bl_calls() { device_calls brightnessctl | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
# The levels the stand-in set the panel to after its first N calls.
disp_bl_levels() { device_calls brightnessctl | py_reply '
import json, sys
calls = json.load(sys.stdin)[int(sys.argv[2]):]
print(json.dumps([c[3] for c in calls if c[:3] == ["-d", sys.argv[1], "set"]]))' "$disp_bl" "$1"; }
disp_bl_live() { disp_bl_levels "$1" | py_reply '
import json, sys
levels = json.load(sys.stdin)
print("live" if len(levels) >= 2 and levels[0] != "1%" and levels[-1] == "1%" else json.dumps(levels))'; }
disp_bl_count() { disp_bl_levels "$1" | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
disp_bl_raised() { disp_bl_item | py_reply 'import json,sys; print(json.load(sys.stdin)[2] > 1)'; }
# The stand-in lists the panel at LEVEL from here on, as a panel holds
# what was set last; it does not follow the sets itself.
disp_bl_holds() { device_reply brightnessctl 0 "$disp_bl,backlight,$1,$1%,100" -l -m -c backlight; }
# True once the service's rescan inputs held still for 1.5 s, past its
# 1 s debounce, and the helper is idle, so no list an earlier change
# started lands on a later reading; `moving` while they change.
disp_settled() {
  local before after
  before="$(disp_read systemRevision) $(disp_read requirementsRevision)" || return 1
  sleep 1.5
  after="$(disp_read systemRevision) $(disp_read requirementsRevision)" || return 1
  if [[ $before != "$after" ]]; then echo moving; return 0; fi
  disp_idle
}
# revealText answers the new contentY, or a word for no row or no area.
# The page's ScrollArea is the System window's, around the pane, so the
# window's instance holds it.
disp_bl_reveal() { ipc smoke revealText window vgs.system DisplayRow "Built-in display" | py_reply 'import json,sys; json.load(sys.stdin); print("scrolled")'; }
mkdir -p -- "$disp_bl_dir"
disp_bl_holds 50
for disp_level in $(seq 1 100); do device_reply brightnessctl 0 "" -d "$disp_bl" set "$disp_level%"; done
rescan "a rescan with the stub backlight answers ok"
expect_poll "the service lists the stub backlight at 50 %" "[\"backlight:$disp_bl\", \"ready\", 50]" disp_bl_item
expect_poll "the helper is idle before the drag" True disp_idle
expect "the deep link opens System → Displays for the panel" ok ipc shell summon window vgs.system '{"pane":"vgs.displays"}'
expect_poll "the System window mounts the displays pane for the panel" '["vgs.displays"]' window_panes
expect_poll "the service's rescans are over before the drag" True disp_settled
expect "the service still shows the panel at 50 %" "[\"backlight:$disp_bl\", \"ready\", 50]" disp_bl_item
expect_poll "the panel's row scrolls into view" scrolled disp_bl_reveal
# The slider and its level share one line: the level's centre is the
# slider's, and the slider ends just before the level. The row's left
# edge lies in its label column, before the slider starts. Prints the
# drag's start and end in layout coordinates, or the first reading that
# is no box, or `outside` when the line lies outside the window.
disp_bl_points() {
  local window row level box
  window="$(surface_box "window:System Settings")" || return 1
  row="$(ipc smoke windowGeometry window vgs.displays DisplayRow "Built-in display")" || return 1
  level="$(ipc smoke scopedWindowGeometry window vgs.displays DisplayRow "Built-in display" Label "$1")" || return 1
  for box in "$window" "$row" "$level"; do [[ $box == \[* ]] || { echo "$box"; return 1; }; done
  python3 -c '
import json, sys
w, r, l = (json.loads(a) for a in sys.argv[1:4])
y = l[1] + l[3] / 2
if not 0 < y < w[3]:
    print("outside"); sys.exit(1)
print(int(w[0] + l[0] - 24), int(w[1] + y), int(w[0] + r[0] + 4), int(w[1] + y))' "$window" "$row" "$level"
}
disp_bl_at="$(disp_bl_points 50%)" || { fail "displays: the panel's slider is unreadable: $disp_bl_at"; return 0; }
read -r disp_x disp_y disp_x2 disp_y2 <<<"$disp_bl_at"
disp_bl_mark="$(disp_bl_calls)"
drag "$disp_x" "$disp_y" "$disp_x2" "$disp_y2" || fail "the drag on the panel's slider failed"
expect_poll "the drag leaves the panel at 1 %" "[\"backlight:$disp_bl\", \"ready\", 1]" disp_bl_item
expect_poll "the helper is idle after the drag" True disp_idle
expect "the drag set the panel while it moved, first between, last at 1 %" live disp_bl_live "$disp_bl_mark"
# Control: a click on the same track point, with no move, sets the panel
# once, so the drag's two or more sets are its moves and not a count that
# reads every press twice.
disp_bl_at="$(disp_bl_points 1%)" || { fail "displays: the panel's slider is unreadable after the drag: $disp_bl_at"; return 0; }
read -r disp_x disp_y _ _ <<<"$disp_bl_at"
disp_bl_mark="$(disp_bl_calls)"
click "$disp_x" "$disp_y" || fail "the click on the panel's slider failed"
expect_poll "control: the click moves the panel off 1 %" True disp_bl_raised
expect_poll "control: the helper is idle after the click" True disp_idle
expect "control: the click set the panel once" 1 disp_bl_count "$disp_bl_mark"
expect "hiding the System window after the panel is allowed" ok ipc shell hide window vgs.system

# A key steps from the level the panel holds, not the one the service set
# last: the service sets the panel to 30 %, another program then sets it
# to 80 %, as an idle daemon dims through brightnessctl, and a step down
# and a step up land on 75 % and 80 %. A key that stepped from the
# service's 30 % would set 25 %.
disp_bl_last() { disp_bl_levels 0 | py_reply 'import json,sys; levels=json.load(sys.stdin); print(levels[-1] if levels else "none")'; }
disp_bl_holds 30
expect "the panel is set to 30 % before the outside write" ok ipc vgs.displays invoke set "{\"id\":\"backlight:$disp_bl\",\"percent\":30}"
expect_poll "the service's rescans are over after the 30 % set" True disp_settled
expect "the pane's choice puts the panel on the new output" ok ipc vgs.displays invoke assign "{\"device\":\"backlight:$disp_bl\",\"output\":\"$disp_new_id\"}"
expect_poll "the service shows the panel at 30 % on the new output" "[\"backlight:$disp_bl\", \"ready\", 30]" disp_bl_item
expect "the new output takes the focus for the panel's keys" ok hypr dispatch "hl.dsp.focus({ monitor = \"$disp_output\" })"
expect_poll "the service reads the new output focused for the panel" "\"$disp_output\"" disp_read focusedOutput
disp_bl_holds 80
expect "the brightness-down key is pressed after the outside write" ok hypr dispatch 'hl.dsp.global("vgs.displays:brightness-down")'
expect_poll "the key steps down from the panel's 80 %, to 75 %" 75% disp_bl_last
expect_poll "the helper is idle after the step down" True disp_idle
disp_bl_holds 75
expect "the brightness-up key is pressed" ok hypr dispatch 'hl.dsp.global("vgs.displays:brightness-up")'
expect_poll "the key steps up by as much, to 80 %" 80% disp_bl_last
expect_poll "the service shows the panel at 80 %" "[\"backlight:$disp_bl\", \"ready\", 80]" disp_bl_item
expect_poll "the helper is idle after the step up" True disp_idle
rm -rf -- "${disp_bl_dir:?}"
device_reply_clear brightnessctl

expect "disabling vgs.displays at the end is allowed" ok ipc shell setPluginEnabled vgs.displays false
expect_poll "no displays layer is left" '[]' ipc smoke layerWindows vgs.displays
rm -f -- "${disp_file:?}"
# Native deletion can run after the bar's layer is already gone. Observe
# clients and focus for 5 s, every 0.2 s, so a later Qt remap cannot pass
# the immediate surface-count check and leak into Power's start snapshot.
disp_window_state() {
  hypr --batch 'j/clients; j/activewindow' | py_reply 'import json,sys
text=sys.stdin.read(); decoder=json.JSONDecoder(); at=0; parts=[]
while len(parts)<2:
    while text[at].isspace(): at+=1
    part,at=decoder.raw_decode(text,at); parts.append(part)
clients,active=parts
print(json.dumps([sorted([c["address"],c["class"],c["title"]] for c in clients),active.get("address", "")]))'
}
disp_windows_preserved() { # BEFORE
  local reading
  for _ in $(seq 1 25); do
    sleep 0.2
    reading="$(disp_window_state)" || return 1
    if [[ $reading != "$1" ]]; then
      printf '{"before":%s,"after":%s}\n' "$1" "$reading" >"$sandbox/displays-removal-state.json"
      printf '  display-removal before=%s after=%s\n' "$1" "$reading" >&2
      echo False
      return
    fi
  done
  echo True
}
# PluginSlot clears its instance after retirement. barShown(null) returns
# true, so the old host can re-show a removed bar while its native window
# awaits deletion. Observe that actual owner transition, not Qt's later
# client mapping race. Existing Probe popup ownership holds the observer
# on the surviving bar, with a release handle for its lifetime observation.
disp_lifetime_dir="$repo/shell/SmokeDisplayLifetime"
mkdir -p -- "$disp_lifetime_dir"
cat > "$disp_lifetime_dir/BarLifetime.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Core
Item {
    id: observer
    required property string output
    property QtObject ownerWindow: null
    property var ownerLifetime: null
    property var releaseOwner: null
    property bool retired: false
    property bool visibleAfterRetirement: false
    property var events: []
    property bool visibleListening: false
    property bool screensListening: false
    property bool visibleNow: false
    property bool lossSeen: false
    property var visibleAtRetirement: null
    property string state: "unavailable:bar"
    readonly property var evidence: ({ state: state, lossSeen: lossSeen, retired: retired, visibleAtRetirement: visibleAtRetirement, visibleNow: visibleNow, visibleAfterRetirement: visibleAfterRetirement, events: events })
    function noteScreensChanged() {
        if (lossSeen || Quickshell.screens.some(screen => screen.name === output)) return;
        lossSeen = true;
        events = events.concat([["screen-removed", visibleNow, retired]]);
        state = "removed";
        Qt.callLater(() => { state = retired ? "retired-turn-complete" : "unavailable:no-retirement"; });
    }
    function noteVisibleChanged() {
        if (ownerWindow === null) return;
        visibleNow = ownerWindow.visible;
        events = events.concat([["visible", visibleNow, retired]]);
        if (retired && visibleNow) visibleAfterRetirement = true;
    }
    function noteRetirement() {
        if (ownerLifetime.active) return; // An early observer drop only unregisters.
        visibleAtRetirement = visibleNow;
        retired = true;
        events = events.concat([["retired", visibleNow, retired]]);
    }
    Component.onCompleted: {
        const rows = Plugins.built["bar:" + output] || [];
        const bar = rows.find(row => row.origin === "core" && row.kind === "bar");
        if (bar === undefined) return;
        const win = bar.instance.QsWindow.window;
        if (win === null) { state = "unavailable:owner-window"; return; }
        ownerWindow = win;
        ownerLifetime = bar.lifetime;
        visibleNow = win.visible;
        if (!visibleNow) { state = "unavailable:bar-hidden"; return; }
        try {
            state = "unavailable:visible-signal";
            win.visibleChanged.connect(observer.noteVisibleChanged);
            visibleListening = true;
            state = "unavailable:screens-signal";
            Quickshell.screensChanged.connect(observer.noteScreensChanged);
            screensListening = true;
            state = "unavailable:owner-lifetime";
            releaseOwner = ownerLifetime.register(observer.noteRetirement);
            state = "watching";
        } catch (error) { state += ":" + String(error); }
    }
    Component.onDestruction: {
        if (screensListening) Quickshell.screensChanged.disconnect(observer.noteScreensChanged);
        if (releaseOwner !== null) releaseOwner();
        if (ownerWindow !== null && visibleListening) {
            ownerWindow.visibleChanged.disconnect(observer.noteVisibleChanged);
        }
    }
}
QML
disp_lifetime_read() { ipc smoke popupRead displays-bar-lifetime evidence; }
disp_lifetime_state() { disp_lifetime_read | py_reply 'import json,sys; print(json.load(sys.stdin)["state"])'; }
disp_lifetime_ack() { disp_lifetime_read | py_reply 'import json,sys; state=json.load(sys.stdin); print(state["lossSeen"] and state["retired"] and state["state"]=="retired-turn-complete")'; }
disp_lifetime_read_visible() { disp_lifetime_read | py_reply 'import json,sys
value=json.load(sys.stdin)["visibleAfterRetirement"]
if type(value) is not bool: sys.exit("visibility evidence is not a boolean")
print(value)'; }
disp_bar_hidden_check() {
  local visible
  # ipc_call can return 69. An unavailable or invalid read is not proof
  # that the old host reopens: only a valid boolean can reach the assertion.
  if visible="$(disp_lifetime_read_visible)"; then
    case $visible in
      True|False) ;;
      *) printf 'visibility evidence is unavailable or invalid: [%s]\n' "$visible" >&2; return 69 ;;
    esac
  else
    return "$?"
  fi
  expect "the removed bar never reopens after its instance retires" False printf '%s\n' "$visible"
}
expect "the existing probe owns the removed bar lifetime observer on the surviving bar" ok \
  ipc smoke popupLoad displays-bar-lifetime "$disp_lifetime_dir/BarLifetime.qml" "bar:$disp_main" vgs.bar "{\"output\":\"$disp_output\"}"
expect "the observer starts on the real visible bar owner" watching disp_lifetime_state
rm -f -- "$sandbox/displays-removal-state.json"
disp_windows_before="$(disp_window_state)"
# Keep the restore and output removal adjacent: an extra compositor read
# here can let the old window finish deletion and hide the lifetime fault.
cp -- "$disp_user_saved" "$disp_user.tmp" && mv -T -- "$disp_user.tmp" "$disp_user"
expect "the nested compositor removes the displays monitor" ok hypr output remove "$disp_output"
expect_poll "the removed monitor's bar surface is gone" "$monitors" bar_count
disp_removal_check() { expect "removing the display preserves clients and focus through later turns" True disp_windows_preserved "$disp_windows_before"; }
disp_removal_control() {
  (failures=0 behaviour_failures=0
   if disp_bar_hidden_check >"$sandbox/displays-removal-control.log" 2>&1; then
     echo "$failures"
   else
     return "$?"
   fi)
}
disp_reader_failure_control() { # CASE REPLY STATUS
  local reader_case="$1" reader_reply="$2" reader_status="$3"
  (failures=0 behaviour_failures=0
   disp_lifetime_read_visible() { printf '%s' "$reader_reply"; return "$reader_status"; }
   expect "the old-host assertion must reject unreadable evidence" 1 disp_removal_control \
     >"$sandbox/displays-reader-$reader_case.log" 2>&1
   echo "$failures")
}
for disp_reader_case in ipc empty invalid; do
  case $disp_reader_case in
    ipc) disp_reader_reply=True; disp_reader_status=69 ;;
    empty) disp_reader_reply=''; disp_reader_status=0 ;;
    invalid) disp_reader_reply=None; disp_reader_status=0 ;;
  esac
  expect "control: $disp_reader_case visibility evidence fails the parent row" 1 \
    disp_reader_failure_control "$disp_reader_case" "$disp_reader_reply" "$disp_reader_status"
  sed 's/^/  CONTROL  /' "$sandbox/displays-reader-$disp_reader_case.log"
done
expect_poll "the native visibility observer acknowledges the completed screen-loss turn" True disp_lifetime_ack
disp_bar_hidden_check || fail "the removed bar visibility evidence could not be read"
disp_removal_check
expect "the existing probe releases the fixed bar lifetime observer" ok ipc smoke popupDrop displays-bar-lifetime
# Reproduce the same owner boundary on the complete old host. The
# control checks requested visibility across retirement even when Qt
# deletes the native window before it can map a generic client.
if copy_tree bar-visible-removed && edit_tree bar-visible-removed shell/Hosts/BarHost.qml \
    'visible: host.screenPresent && PluginLogic.barShown(slot.instance)' \
    'visible: PluginLogic.barShown(slot.instance)' \
  && edit_tree bar-visible-removed shell/Hosts/BarHost.qml \
    'active: host.screenPresent && host.wantedKey' \
    'active: Quickshell.screens.indexOf(host.screen) !== -1 && host.wantedKey' \
  && edit_tree bar-visible-removed shell/Hosts/BarHost.qml \
    '    readonly property bool screenPresent: Quickshell.screens.indexOf(screen) !== -1
' '' \
  && stop_shell; then
  if start_shell "$sandbox/tree-bar-visible-removed" "$sandbox/displays-bar-visible-removed.log"; then
    expect "the old-host control adds its own monitor" ok hypr output create headless "$disp_output"
    expect_poll "the old-host control waits for the monitor's bar" "$((monitors+1))" bar_count
    expect "the existing probe owns the old host's bar observer" ok ipc smoke popupLoad \
      displays-bar-lifetime "$sandbox/tree-bar-visible-removed/shell/SmokeDisplayLifetime/BarLifetime.qml" \
      "bar:$disp_main" vgs.bar "{\"output\":\"$disp_output\"}"
    expect "the old-host observer starts on the real visible bar" watching disp_lifetime_state
    expect "the old-host control removes its own monitor" ok hypr output remove "$disp_output"
    expect_poll "the old-host control acknowledges retirement and the screen-loss turn" True disp_lifetime_ack
    expect "control: the old host fails the same owner visibility check" 1 disp_removal_control
    disp_lifetime_read
    sed 's/^/  CONTROL  /' "$sandbox/displays-removal-control.log"
    expect "the existing probe releases the old bar lifetime observer" ok ipc smoke popupDrop displays-bar-lifetime
  else
    fail "the removed-screen bar control could not start its mutant shell"
  fi
else
  fail "the removed-screen bar control could not start its mutant shell"
fi
stop_shell && start_shell "$repo" "$sandbox/displays-restored.log"
rm -rf -- "${sandbox:?}/tree-bar-visible-removed"
