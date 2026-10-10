# Production reader and views over a disposable net-dev file, recorded ss,
# physical interface resolver, and a capture probe seam. No capture or host
# authentication runs. No latency budget: CPU evidence is in the item.
# Polls use expect_poll. A dropped panel release must fail the lease check.
# inputs: shell/plugins/vgs.traffic/* shell/plugins/vgs.traffic/tui/* scripts/fixtures/traffic/* scripts/smoke/fixtures/traffic/* scripts/smoke/fixtures/tui/vgs.traffic/tui/* shell/Core/PluginLogic.js shell/Core/SystemSteps.qml shell/Core/TuiRunner.qml shell/Ui/BarWidget.qml shell/Ui/controls/BarItem.qml shell/Hosts/SummonPopup.qml shell/Ui/layout/SurfaceHeight.qml shell/Hosts/PluginSlot.qml scripts/smoke/toplevel/* scripts/smoke/rows/capabilities.sh shell/Commons/AnchorTracker.qml
set -euo pipefail
traffic_dir="$sandbox/traffic"
mkdir -p -- "$traffic_dir"
cp -- "$home/.config/vgshell/shell.json" "$traffic_dir/shell.json"
traffic_source="$repo/shell/plugins/vgs.traffic"
for file in Service.qml Panel.qml; do cp -- "$traffic_source/$file" "$traffic_dir/$file"; done
cp -- "$traffic_source/tui/bandwhich.sh" "$traffic_dir/bandwhich.sh"
cp -- "$repo/scripts/fixtures/traffic/net-dev-before.txt" "$traffic_dir/net-dev"
printf '#!/usr/bin/env bash\nexec python3 %q %q "$@"\n' "$repo/scripts/smoke/fixtures/traffic/ss.py" "$traffic_dir" >"$traffic_dir/ss"
printf '#!/usr/bin/env bash\nfor arg; do case "$arg" in /sys/class/net/enp5s0) echo /sys/devices/pci/net/enp5s0 ;; /sys/class/net/wlan0) echo /sys/devices/pci/net/wlan0 ;; /sys/class/net/*) echo /sys/devices/virtual/net/"${arg##*/}" ;; esac; done\n' >"$traffic_dir/readlink"
# Player's socket belongs to the row's own sleep child, so Inspect reads a
# real command line. The Kill stand-in records its argv and signals
# nothing; it exits 1, as kill(1) does when a signal fails, while
# WORLD/kill-fail exists.
spawn "$traffic_dir/child.log" sleep 600
traffic_child="$spawn_pid"
printf '{"Player": %d}\n' "$traffic_child" >"$traffic_dir/pids"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>%q\nif [[ -e %q ]]; then echo "kill: sending signal failed: No such process" >&2; exit 1; fi\n' "$traffic_dir/kills" "$traffic_dir/kill-fail" >"$traffic_dir/kill"
chmod +x "$traffic_dir/ss" "$traffic_dir/readlink" "$traffic_dir/kill"
cp -- "$repo/scripts/smoke/fixtures/tui/vgs.traffic/tui/bandwhich.sh" "$traffic_source/tui/bandwhich.sh"
python3 - "$traffic_source/Service.qml" "$traffic_dir" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();root=sys.argv[2]
for old,new in [('path: "/proc/net/dev"','path: "'+root+'/net-dev"'), ('["readlink", "-m", "--"]','["'+root+'/readlink", "-m", "--"]'), ('["ss", "-tinpeH", "state", "connected"]','["'+root+'/ss", "-tinpeH", "state", "connected"]'), ('["kill", "-TERM"]','["'+root+'/kill", "-TERM"]'),('shell.system.state["bandwhich-capture"]','root.fixtureCapture')]:
    assert s.count(old)==1,old;s=s.replace(old,new)
s=s.replace('shell !== null && shell.requirements.missing.indexOf("bandwhich") === -1', 'root.fixtureTool')
s=s.replace('property bool registered: false','property bool registered: false\n    property bool fixtureTool: false\n    property var fixtureCapture: ({ state: "needed", reason: "capture-needed" })')
s=s.replace('shell.ipc.handle("lease", root.lease);','shell.ipc.handle("lease", root.lease);\n            shell.ipc.handle("capture-fixture", arg => { const value = JSON.parse(arg); root.fixtureCapture = value; root.fixtureTool = value.tool === true; return "ok"; });')
p.write_text(s)
panel=pathlib.Path(sys.argv[1]).with_name("Panel.qml")
s=panel.read_text();old='shell.tui.run("bandwhich")';assert s.count(old)==1
s=s.replace(old, 'shell.tui.run("bandwhich", ["'+root+'/tui-hold"])')
# A count of the row items the panel has built, read to show that a sample
# changes rows in place.
for old,new in [('property bool leased: false','property bool leased: false\n    property int rowsBuilt: 0'), ('                            cursor: listCursor\n','                            cursor: listCursor\n                            Component.onCompleted: root.rowsBuilt++\n')]:
    assert s.count(old)==1,old;s=s.replace(old,new)
panel.write_text(s)
PY
traffic_read() { ipc smoke readInstance service vgs.traffic "$1"; }
traffic_values() { ipc smoke statusValues vgs.traffic; }
traffic_state() { traffic_values | py_reply 'import json,sys;print(json.dumps(json.load(sys.stdin)["traffic"]["state"]))'; }
traffic_panel() { [[ $(ipc smoke instanceGeometry panel vgs.traffic) != absent ]] && echo shown || echo hidden; }
traffic_ss_calls() { if [[ -f $traffic_dir/calls ]]; then wc -l <"$traffic_dir/calls" | tr -d ' '; else echo 0; fi; }
traffic_has_totals() { traffic_values | py_reply 'import json,sys;t=json.load(sys.stdin)["traffic"]; print(isinstance(t["down"],(int,float)) and isinstance(t["up"],(int,float)) and [i["name"] for i in t["interfaces"]]==["enp5s0","wlan0"])'; }
traffic_captured() { traffic_values | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["capture"]["action"]))'; }
traffic_foot() { ipc smoke readInstance panel vgs.traffic footShown; }
traffic_search_focus_contract() { expect_poll "search takes focus on open" true ipc smoke activeFocusWithin panel vgs.traffic TextField; }
traffic_socket_stopped() { python3 - "$traffic_dir" <<'PY'
import pathlib,sys
root=pathlib.Path(sys.argv[1]);p=root/'pid'
if not p.exists(): print('not-started')
else:
    proc=pathlib.Path('/proc')/p.read_text().strip()/'cmdline'
    try: alive=str(root).encode() in proc.read_bytes()
    except FileNotFoundError: alive=False
    print('running' if alive else 'stopped')
PY
}
traffic_snapshot_ready() { traffic_values | py_reply 'import json,sys;t=json.load(sys.stdin)["traffic"]; print(t["state"]=="ready" and {r["name"] for r in t["apps"]}=={"Browser","Player"})'; }
traffic_rows_built() { ipc smoke readInstance panel vgs.traffic rowsBuilt; }
traffic_started_since() { local now; now="$(traffic_read ssStarts)" || return; ((now >= $1)) && echo true || echo false; }
# Two whole samples, each of which hands the rows a new list at every
# status write, leave every row item the panel built in place: the count
# and the ss starts are marked, three more starts mean two samples ended,
# and traffic_rows_kept compares. A control's polls end after 5 s, so the
# wait for samples stays outside a control.
traffic_rows_mark() {
  traffic_mark_built="$(traffic_rows_built)" traffic_mark_started="$(traffic_read ssStarts)"
  expect_poll "two more samples land" true traffic_started_since "$((traffic_mark_started + 3))"
}
traffic_rows_kept() { # LABEL
  expect "$1" "$traffic_mark_built" traffic_rows_built
}
traffic_popup_reads() { [[ $(ipc smoke popupItemGeometry panel vgs.traffic "" "" "$1" "$2") != absent ]] && echo true || echo false; }
traffic_menu_open() { traffic_popup_reads MenuItem Kill; }
traffic_kills() { if [[ -f $traffic_dir/kills ]]; then wc -l <"$traffic_dir/kills" | tr -d ' '; else echo 0; fi; }
traffic_last_kill() { tail -n 1 "$traffic_dir/kills" 2>/dev/null; }
traffic_ending() { traffic_values | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["traffic"]["ending"]))'; }
traffic_inspect_pids() { ipc vgs.traffic invoke inspect "{\"name\":\"$1\"}" | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["pids"]))'; }
# Each contract below is a mark, the steps that reach the state, and a
# read, one assertion; a control runs the read alone in its subshell,
# whose polls end after 5 s, after the mark ran outside it.
# The plate under a hovered row is not laid out as a row: FIRST keeps its
# place while the pointer rests on HOVERED and the plate shows.
traffic_hover_mark() { # FIRST HOVERED
  rest_pointer
  traffic_first_box="$(ipc smoke itemGeometry panel vgs.traffic ListItem "$1")"
  point_item panel vgs.traffic ListItem "$2" >/dev/null || fail "Traffic row hover failed"
  expect_poll "a hovered row shows the list's plate" true ipc smoke readDescendant panel vgs.traffic ListCursor visible
}
traffic_hover_kept() { expect "a hover moves no row" "$traffic_first_box" ipc smoke itemGeometry panel vgs.traffic ListItem "$1"; } # FIRST
# A click on ROW opens its actions; once Escape closes them and the panel
# holds the keyboard again, ROW is not highlighted, which it is only while
# the list holds the keyboard.
traffic_click_mark() { # ROW
  click_item panel vgs.traffic ListItem "$1" || fail "Traffic row click failed"
  expect_poll "a row click opens its actions" true traffic_menu_open
  type_keys -k Escape
  expect_poll "Escape closes the row's actions" false traffic_menu_open
  expect_poll "the panel holds the keyboard again" true ipc smoke activeFocusIn panel vgs.traffic
}
traffic_click_kept() { expect "a row click leaves the list without keyboard focus" false ipc smoke readMatchingDescendant panel vgs.traffic ListItem text "$1" highlighted; } # ROW
traffic_panel_edit() { # OLD NEW
  python3 - "$traffic_source/Panel.qml" "$1" "$2" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();old,new=sys.argv[2:]
assert s.count(old)==1,old;p.write_text(s.replace(old,new))
PY
}
traffic_control_open() { # NAME
  rescan "the $1 control is scanned"
  expect "the $1 control's widget is placed" ok ipc shell setPluginPlaced vgs.traffic true
  expect_poll "the $1 control's widget leases" 1 traffic_read leaseCount
  click_centre "$(bar_key)" vgs.traffic || fail "the $1 control did not open"
  expect_poll "the $1 control publishes per-app traffic" True traffic_snapshot_ready
}
traffic_control_close() { # NAME
  expect "the $1 control closes" ok ipc shell hide panel vgs.traffic
  expect "the $1 control's widget unplaces" ok ipc shell setPluginPlaced vgs.traffic false
  expect_poll "the $1 control releases every lease" 0 traffic_read leaseCount
}
rescan "Traffic's reader fixture is scanned"
expect "Traffic enables" ok ipc shell setPluginEnabled vgs.traffic true
expect "Traffic is placed" ok ipc shell setPluginPlaced vgs.traffic true
expect_poll "Traffic's widget leases totals" 1 traffic_read leaseCount
expect_poll "Traffic publishes physical totals" True traffic_has_totals
expect "a closed panel holds no socket lease" 0 traffic_read socketLeaseCount
expect "a closed panel starts no ss" 0 traffic_ss_calls
: >"$traffic_dir/hold"
click_centre "$(bar_key)" vgs.traffic || fail "Traffic click failed"
expect_poll "a click opens Traffic" shown traffic_panel
traffic_search_focus_contract
expect_poll "the panel acquires its socket lease" 1 traffic_read socketLeaseCount
expect_poll "the first socket sample starts" true traffic_read ssRunning
expect "the first sample shows Measuring" '"measuring"' traffic_state
traffic_started="$(traffic_read ssStarts)"
for _ in 1 2 3; do ipc smoke invokeInstance service vgs.traffic read "" >/dev/null; done
expect "overlapping reads start no second ss" "$traffic_started" traffic_read ssStarts
expect_poll "one socket child is live" running traffic_socket_stopped
expect "ss receives the specified connected TCP request" '["-tinpeH", "state", "connected"]' head -1 "$traffic_dir/calls"
rm -- "${traffic_dir:?}/hold"
expect_poll "the reader publishes per-app traffic" True traffic_snapshot_ready
expect "a needed capture probe offers Allow" true traffic_captured
expect "bandwhich is absent in the stock fixture" false traffic_foot
expect "KB/s shows no decimals by default" "34 KB/s" ipc smoke invokeInstanceArgs panel vgs.traffic rate '{"args":[34816]}'
expect "MB/s shows one decimal by default" "12.2 MB/s" ipc smoke invokeInstanceArgs panel vgs.traffic rate '{"args":[12792627]}'
traffic_rows_mark
traffic_rows_kept "samples change the rows in place"
traffic_built="$(traffic_rows_built)"
click_item panel vgs.traffic Button Upload || fail "Traffic upload header click failed"
expect_poll "a pointer sorts by upload" '"up"' ipc smoke readInstance panel vgs.traffic sortKey
expect "upload starts in descending order" false ipc smoke readInstance panel vgs.traffic ascending
type_keys -k Return
expect_poll "Return reverses the focused header" true ipc smoke readInstance panel vgs.traffic ascending
expect "a sort moves the rows it built" "$traffic_built" traffic_rows_built
# Ascending upload puts Player first.
traffic_hover_mark Player Browser
traffic_hover_kept Player
traffic_click_mark Browser
expect "a row click selects its app" '"app:Browser"' ipc smoke readInstance panel vgs.traffic currentKey
traffic_click_kept Browser
click_item panel vgs.traffic ListItem Player || fail "Traffic Inspect row click failed"
expect_poll "the Inspect row's actions open" true traffic_menu_open
click_item popup:panel vgs.traffic "" "" MenuItem Inspect || fail "Traffic Inspect click failed"
expect_poll "Inspect shows the app's command line" true traffic_popup_reads Label "sleep 600"
expect "Inspect shows the app's pid" true traffic_popup_reads Label "$traffic_child"
expect "Inspect shows the app's peer" true traffic_popup_reads Label "198.51.100.1:443"
expect "Inspect shows the connection's state" true traffic_popup_reads Label "Open"
type_keys -k Escape
expect_poll "Escape closes Inspect" false traffic_popup_reads Label "sleep 600"
expect "the service names the row's own pid" "[$traffic_child]" traffic_inspect_pids Player
expect "a kill of a pid outside the row is refused" "refused: kill=changed" ipc vgs.traffic invoke kill '{"name":"Player","pids":[42]}'
expect "a refused kill runs no kill" 0 traffic_kills
click_item panel vgs.traffic ListItem Player || fail "Traffic Kill row click failed"
expect_poll "the Kill row's actions open" true traffic_menu_open
click_item popup:panel vgs.traffic "" "" MenuItem Kill || fail "Traffic Kill click failed"
expect_poll "Kill asks first, naming the app" true traffic_popup_reads Label "Kill Player?"
expect "the question names the pid" true traffic_popup_reads Label "Process $traffic_child"
expect "nothing is signalled before the answer" 0 traffic_kills
click_item popup:panel vgs.traffic "" "" Button Kill || fail "Traffic Kill answer failed"
expect_poll "Kill sends SIGTERM to the row's process" "-TERM $traffic_child" traffic_last_kill
expect_poll "the panel learns the request was sent" '{"name": "Player", "state": "sent"}' traffic_ending
# The question opens with Cancel focused: Return cancels, and Tab then
# Return presses Kill.
click_item panel vgs.traffic ListItem Player || fail "Traffic cancelled Kill row click failed"
expect_poll "the cancelled Kill row's actions open" true traffic_menu_open
click_item popup:panel vgs.traffic "" "" MenuItem Kill || fail "Traffic cancelled Kill click failed"
expect_poll "the cancelled Kill asks first" true traffic_popup_reads Label "Kill Player?"
type_keys -k Return
expect_poll "Return presses the focused Cancel" false traffic_popup_reads Label "Kill Player?"
expect "a cancelled Kill runs no kill" 1 traffic_kills
: >"$traffic_dir/kill-fail"
click_item panel vgs.traffic ListItem Player || fail "Traffic failing Kill row click failed"
expect_poll "the failing Kill row's actions open" true traffic_menu_open
click_item popup:panel vgs.traffic "" "" MenuItem Kill || fail "Traffic failing Kill click failed"
expect_poll "the failing Kill asks first" true traffic_popup_reads Label "Kill Player?"
type_keys -k Tab -k Return
expect_poll "Tab and Return press Kill" 2 traffic_kills
expect_poll "a failed kill reaches the panel" '{"name": "Player", "state": "failed"}' traffic_ending
rm -- "${traffic_dir:?}/kill-fail"
kill "$traffic_child" 2>/dev/null || true
wait "$traffic_child" 2>/dev/null || true
click_item panel vgs.traffic TextField "" || fail "Traffic search focus failed"
expect_poll "a click focuses search" true ipc smoke activeFocusWithin panel vgs.traffic TextField
type_keys 'zzzz' || fail "Traffic search input failed"
expect_poll "search filters named apps" true ipc smoke readInstance panel vgs.traffic emptyShown
type_keys -k Escape
expect_poll "Escape clears the search" '""' ipc smoke readDescendant panel vgs.traffic TextField text
expect "the cleared search keeps its panel" shown traffic_panel
type_keys -k Escape
expect_poll "the second Escape closes the panel" hidden traffic_panel
expect_poll "closing releases ss" 0 traffic_read socketLeaseCount
expect_poll "the socket child ends" stopped traffic_socket_stopped
# The bar host is passive. A disposable popup gives the production Widget
# a keyboard seat and focuses its production BarItem before a real Return.
mkdir -p -- "$traffic_dir/keyboard"
python3 - "$traffic_dir/keyboard/Keyboard.qml" "$traffic_source" <<'PY'
import pathlib,sys
pathlib.Path(sys.argv[1]).write_text('''import QtQuick
import Quickshell
import "file://'''+sys.argv[2]+'''" as Traffic
PopupWindow {
    id: win
    required property var original
    anchor.item: original
    grabFocus: true
    visible: true
    implicitWidth: widget.implicitWidth
    implicitHeight: widget.implicitHeight
    readonly property bool focused: widget.children.some(child => child.activeFocus)
    readonly property bool rateCaseCorrect: {
        function labels(item) {
            let found = item.role === "bar" && item.visible && String(item.text).indexOf("/s") >= 0 ? [item] : [];
            for (const child of item.children || []) found = found.concat(labels(child));
            return found;
        }
        const rates = labels(widget);
        return rates.length === 2 && rates.every(label => label.font.capitalization === Font.MixedCase);
    }
    Traffic.Widget {
        id: widget
        shell: win.original.shell
        bar: win.original.bar
        settings: win.original.settings
        Component.onCompleted: Qt.callLater(() => {
            const button = widget.children.find(child => child.label === "Network Traffic" && child.visible);
            if (button) button.forceActiveFocus(Qt.TabFocusReason);
        })
    }
}
''')
PY
expect "the production widget builds in a keyboard popup" ok ipc smoke popupLoad traffic-keyboard "$traffic_dir/keyboard/Keyboard.qml" "$(bar_key)" vgs.traffic '{"original":"@instance"}'
expect_poll "the production BarItem holds focus" true ipc smoke popupRead traffic-keyboard focused
expect_poll "both rendered bar rates keep the lowercase s" true ipc smoke popupRead traffic-keyboard rateCaseCorrect
type_keys -k Return
expect_poll "Return on the focused widget opens Traffic" shown traffic_panel
rest_pointer
click 10 "$((mon_h - 10))" || fail "Traffic outside click failed"
expect_poll "a click outside closes Traffic" hidden traffic_panel
expect_poll "outside dismissal releases ss" 0 traffic_read socketLeaseCount
expect "the keyboard popup is released" ok ipc smoke popupDrop traffic-keyboard
# Actual requirement presence plus probe state seam, through production
# status.act. The terminal stand-in never executes core/system.
printf '#!/usr/bin/env bash\nexit 0\n' >"$shim/bandwhich"
chmod +x "$shim/bandwhich"
rescan "Traffic sees the optional tool"
expect_poll "Traffic's widget reacquires after scan" 1 traffic_read leaseCount
click_centre "$(bar_key)" vgs.traffic || fail "Traffic present-tool click failed"
expect "the needed capture seam publishes" ok ipc vgs.traffic invoke capture-fixture '{"state":"needed","reason":"capture-needed","tool":true}'
expect_poll "the installed optional tool shows the foot" true traffic_foot
expect_poll "the foot offers Allow" true traffic_captured
terminal_stand_in
terminal_ready Traffic
hold_runs
forget_record
expect "Allow uses the declared core system action" ok ipc smoke invokeInstance panel vgs.traffic seeAll ""
expect_poll "Allow opens the core system step in a visible terminal" "$(core_words core/system 'System setup' org.vgs.tui system apply bandwhich-capture)" recorded
release_runs
expect_run_end "the capture terminal stand-in ends" core/system
expect "the ready capture seam publishes" ok ipc vgs.traffic invoke capture-fixture '{"state":"ready","reason":"granted","tool":true}'
expect_poll "ready removes Allow" false traffic_captured
click_centre "$(bar_key)" vgs.traffic || fail "Traffic ready-tool click failed"
expect_poll "Traffic opens again after the capture terminal" shown traffic_panel
: >"$traffic_dir/tui-hold"
forget_record
expect "See all launches the plugin's safe TUI fixture" ok ipc smoke invokeInstance panel vgs.traffic seeAll ""
expect_poll "See all selects its declared TUI" "$(words vgs.traffic/bandwhich tui/bandwhich.sh "$traffic_dir/tui-hold")" recorded_tail
traffic_tui_window() { hypr -j clients | py_reply 'import json,sys; print(sum(c["class"]=="org.vgs.tui.wide" for c in json.load(sys.stdin)))'; }
traffic_active_class() { hypr -j activewindow | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get("class")))'; }
expect_poll "See all opens one terminal" 1 traffic_tui_window
expect_poll "the launcher ends while its terminal stays open" '[]' lent tui.launching
expect "Traffic remains available for launch-or-focus" ok ipc shell summon panel vgs.traffic '{}'
spawn "$traffic_dir/other.log" "${shell_env[@]}" "$sandbox/toplevel" org.example.traffic Traffic-other
traffic_other_pid="$spawn_pid"
expect_poll "another client takes focus" '"org.example.traffic"' traffic_active_class
expect "a second See all finds the live key" "refused: tui=bandwhich reason=busy" ipc smoke invokeInstance panel vgs.traffic seeAll ""
expect_poll "the second See all focuses its terminal" '"org.vgs.tui.wide"' traffic_active_class
expect "the second See all starts no second terminal" 1 traffic_tui_window
kill "$traffic_other_pid" 2>/dev/null || true
wait "$traffic_other_pid" 2>/dev/null || true
rm -- "${traffic_dir:?}/tui-hold"
expect_run_end "the all-traffic terminal ends" vgs.traffic/bandwhich
expect "Traffic closes after its footer cases" ok ipc shell hide panel vgs.traffic
traffic_widget_box="$(ipc smoke instanceGeometry "$(bar_key)" vgs.traffic)"
read -r traffic_x traffic_y < <(python3 -c 'import json,sys;x,y,w,h=json.loads(sys.argv[1]);print(int(x+w/2),int(y+h/2))' "$traffic_widget_box")
hover "$((traffic_x - 1))" "$traffic_y" && right_click "$traffic_x" "$traffic_y" || fail "Traffic right click failed"
expect_poll "right click keeps the shared widget menu" true ipc smoke readInstance "$(bar_key)" vgs.traffic frameMenuOpen
expect "Traffic keeps Hide and Settings" '["Hide","Settings"]' ipc smoke readInstance "$(bar_key)" vgs.traffic frameMenuEntries
type_keys -k Return
expect_poll "Hide opens the confirmation" true ipc smoke readInstance "$(bar_key)" vgs.traffic frameDialogOpen
type_keys -k Tab -k Return
expect_poll "no widget or panel leaves a lease" 0 traffic_read leaseCount
expect_poll "no lease leaves a running timer" false traffic_read timerRunning
expect_poll "no lease leaves ss running" false traffic_read ssRunning
# A disposable panel that feeds its rows a plain list must fail the same
# in-place assertion: the Repeater then rebuilds every row at each status
# write. The control's log keeps the count it built.
python3 - "$traffic_source/Panel.qml" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();old='model: ScriptModel { values: root.rows; objectProp: "key" }'
assert s.count(old)==1;s=s.replace(old,'model: root.rows');p.write_text(s)
PY
rescan "the plain-list rows control is scanned"
expect "the rows control's widget is placed" ok ipc shell setPluginPlaced vgs.traffic true
expect_poll "the rows control's widget leases" 1 traffic_read leaseCount
click_centre "$(bar_key)" vgs.traffic || fail "the rows control did not open"
expect_poll "the rows control publishes per-app traffic" True traffic_snapshot_ready
traffic_rows_mark
traffic_rows_control() { (failures=0 behaviour_failures=0; traffic_rows_kept "the control's rows" >"$traffic_dir/rows-control.log"; echo "$failures"); }
expect "a plain list breaks the in-place test" 1 traffic_rows_control
printf '  control log: rows built %s -> %s while ss started %s -> %s\n' "$traffic_mark_built" "$(traffic_rows_built)" "$traffic_mark_started" "$(traffic_read ssStarts)"
expect "the rows control closes" ok ipc shell hide panel vgs.traffic
expect "the rows control's widget unplaces" ok ipc shell setPluginPlaced vgs.traffic false
expect_poll "the rows control releases every lease" 0 traffic_read leaseCount
python3 - "$traffic_source/Panel.qml" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();old='model: root.rows'
assert s.count(old)==1;s=s.replace(old,'model: ScriptModel { values: root.rows; objectProp: "key" }');p.write_text(s)
PY
# A disposable panel whose cursor sits in the rows' Column must fail the
# hover read: the shown plate is laid out as the first row.
traffic_list_cursor=$'                ListCursor { id: listCursor }\n'
traffic_entries_open=$'                    id: entries\n                    width: parent.width\n'
traffic_panel_edit "$traffic_list_cursor" ""
traffic_cursor_in_column=$'                    ListCursor { id: listCursor }\n'
traffic_panel_edit "$traffic_entries_open" "$traffic_entries_open$traffic_cursor_in_column"
traffic_control_open "cursor-in-column"
traffic_hover_mark Player Browser
traffic_hover_control() { (failures=0 behaviour_failures=0; traffic_hover_kept Player >"$traffic_dir/hover-control.log"; echo "$failures"); }
expect "a cursor in the rows' Column breaks the hover test" 1 traffic_hover_control
sed 's/^ */  control log: /' "$traffic_dir/hover-control.log"
rest_pointer
traffic_control_close "cursor-in-column"
traffic_panel_edit "$traffic_entries_open$traffic_cursor_in_column" "$traffic_entries_open"
traffic_panel_edit $'                Column {\n                    id: entries\n' "$traffic_list_cursor"$'                Column {\n                    id: entries\n'
# A disposable panel whose row click takes the keyboard, as before, must
# fail the click read.
traffic_click_act='root.act(modelData, "menu", false);'
traffic_panel_edit "$traffic_click_act" "$traffic_click_act appList.forceActiveFocus(Qt.MouseFocusReason);"
traffic_control_open "click-focus"
traffic_click_mark Browser
traffic_click_control() { (failures=0 behaviour_failures=0; traffic_click_kept Browser >"$traffic_dir/click-control.log"; echo "$failures"); }
expect "a click that takes the keyboard breaks the click test" 1 traffic_click_control
sed 's/^ */  control log: /' "$traffic_dir/click-control.log"
traffic_control_close "click-focus"
traffic_panel_edit "$traffic_click_act appList.forceActiveFocus(Qt.MouseFocusReason);" "$traffic_click_act"
# A disposable panel with the wrong initial target must fail the same
# search-focus assertion used before any click in the first open.
python3 - "$traffic_source/Panel.qml" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();old='readonly property Item initialFocus: search'
assert s.count(old)==1;s=s.replace(old,'readonly property Item initialFocus: root');p.write_text(s)
PY
rescan "the wrong initial focus control is scanned"
expect "the focus control's widget is placed" ok ipc shell setPluginPlaced vgs.traffic true
expect_poll "the focus control's widget leases" 1 traffic_read leaseCount
click_centre "$(bar_key)" vgs.traffic || fail "the focus control did not open"
expect_poll "the focus control opens Traffic" shown traffic_panel
expect_poll "the focus control leaves search unfocused" false ipc smoke activeFocusWithin panel vgs.traffic TextField
traffic_focus_control() { (failures=0 behaviour_failures=0; traffic_search_focus_contract >"$traffic_dir/focus-control.log"; echo "$failures"); }
expect "the wrong initial target breaks the focus test" 1 traffic_focus_control
expect "the focus control closes" ok ipc shell hide panel vgs.traffic
expect "the focus control's widget unplaces" ok ipc shell setPluginPlaced vgs.traffic false
expect_poll "the focus control releases every lease" 0 traffic_read leaseCount
python3 - "$traffic_source/Panel.qml" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();old='readonly property Item initialFocus: root'
assert s.count(old)==1;s=s.replace(old,'readonly property Item initialFocus: search');p.write_text(s)
PY
# A disposable production panel copy omits its close release. Its reading
# must report a surviving lease after Escape and widget unplacement.
python3 - "$traffic_source/Panel.qml" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();old='if (leased && shell !== null) shell.ipc.call("lease", JSON.stringify({ id: String(root), open: false }));'
assert s.count(old)==1;s=s.replace(old,'if (false) shell.ipc.call("lease", JSON.stringify({ id: String(root), open: false }));');p.write_text(s)
PY
rescan "the dropped panel release control is scanned"
expect "the release control's widget is placed" ok ipc shell setPluginPlaced vgs.traffic true
expect_poll "the release control's widget leases" 1 traffic_read leaseCount
click_centre "$(bar_key)" vgs.traffic || fail "the release control did not open"
expect_poll "the release control's panel leases" 1 traffic_read socketLeaseCount
expect "the release control closes" ok ipc shell hide panel vgs.traffic
expect "the release control's widget unplaces" ok ipc shell setPluginPlaced vgs.traffic false
expect_poll "the control leaves its dropped panel lease" 1 traffic_read leaseCount
traffic_release_control() { (failures=0 behaviour_failures=0; expect "the panel must release its lease" 0 traffic_read leaseCount >"$traffic_dir/release-control.log"; echo "$failures"); }
expect "a dropped release breaks the lease test" 1 traffic_release_control
expect "Traffic disables after its row" ok ipc shell setPluginEnabled vgs.traffic false
expect_poll "the service is destroyed" False record_exists vgs.traffic
for file in Service.qml Panel.qml; do cp -- "$traffic_dir/$file" "$traffic_source/$file"; done
cp -- "$traffic_dir/bandwhich.sh" "$traffic_source/tui/bandwhich.sh"
rm -f -- "${shim:?}/bandwhich"
cp -- "$traffic_dir/shell.json" "$home/.config/vgshell/shell.json.next"
mv -T -- "$home/.config/vgshell/shell.json.next" "$home/.config/vgshell/shell.json"
rescan "Traffic restores its files and configuration"
rest_pointer
