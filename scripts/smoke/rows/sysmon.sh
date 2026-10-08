# System Monitor reads real kernel CPU and memory values and releases its
# poller when its widget leaves the bar. A disposable window hosts the
# shipped widget to deliver Enter through the nested keyboard seat: the
# bar itself has no keyboard focus. Its fixture service publishes no GPU.
# No latency or CPU ceiling is asserted. expect_poll uses IPC round trips.
# inputs: shell/plugins/vgs.sysmon/* shell/plugins/vgs.sysmon/tui/* shell/Ui/BarWidget.qml shell/Ui/controls/BarItem.qml scripts/smoke/fixtures/tui/vgs.sysmon/tui/btop.sh scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail
sysmon_saved="$sandbox/sysmon-before.json"
cp -- "$home/.config/vgshell/shell.json" "$sysmon_saved"
sysmon_key="$(bar_key)" || return
sysmon_shown() {
  local geometry
  geometry="$(ipc smoke instanceGeometry "$1" "$2")" || return
  if [[ $geometry == absent ]]; then echo hidden; else echo shown; fi
}
sysmon_numeric() { ipc smoke statusValues vgs.sysmon | py_reply 'import json,sys; r=json.load(sys.stdin).get("readings",{}); print("numeric" if all(isinstance(r.get(k,{}).get("use"),(int,float)) for k in ("cpu","memory")) else "pending")'; }
sysmon_icons() { ipc smoke itemValues "$1" "$2" BarItem iconName,visible | py_reply 'import json,sys; print(json.dumps([r["iconName"] for r in json.load(sys.stdin) if r["visible"]]))'; }
sysmon_setting() {
  python3 - "$home/.config/vgshell/shell.json" "$1" "$2" <<'PYSETTING' || return
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); data=json.loads(p.read_text())
rows=data.setdefault("plugins",[])
row=next((r for r in rows if r.get("id")=="vgs.sysmon"),None)
if row is None: row={"id":"vgs.sysmon"}; rows.append(row)
row[sys.argv[2]]=json.loads(sys.argv[3])
for entries in data.get("bar",{}).get("layout",{}).values():
    for entry in entries:
        if entry.get("id")=="vgs.sysmon": entry[sys.argv[2]]=json.loads(sys.argv[3])
p.write_text(json.dumps(data))
PYSETTING
  ipc shell reloadConfig
}
expect "System Monitor enables" ok ipc shell setPluginEnabled vgs.sysmon true
expect "System Monitor places its widget" ok ipc shell setPluginPlaced vgs.sysmon true
expect_poll "CPU and memory publish real numbers" numeric sysmon_numeric
expect_poll "the placed widget starts polling" true ipc smoke readInstance service vgs.sysmon polling
expect "GPU hides through Settings" ok sysmon_setting showGpu false
expect "memory hides through Settings" ok sysmon_setting showMemory false
expect_poll "Settings reaches the widget" '["cpu"]' sysmon_icons "$sysmon_key" vgs.sysmon
click_centre "$sysmon_key" vgs.sysmon || fail "the CPU reading takes a click"
expect_poll "click opens the flyout" shown sysmon_shown panel vgs.sysmon
type_keys -k Escape
expect_poll "Escape closes the flyout" hidden sysmon_shown panel vgs.sysmon
click_centre "$sysmon_key" vgs.sysmon || fail "the CPU reading opens again"
expect_poll "the flyout opens before outside click" shown sysmon_shown panel vgs.sysmon
click 10 "$((mon_h - 10))"
expect_poll "outside click closes the flyout" hidden sysmon_shown panel vgs.sysmon
expect "the widget leaves the bar" ok ipc shell setPluginPlaced vgs.sysmon false
expect_poll "unplacing releases every lease" 0 ipc smoke readInstance service vgs.sysmon leaseCount
expect_poll "unplacing stops the only poller" false ipc smoke readInstance service vgs.sysmon polling

# A fresh plugin directory avoids Qt's cached directory entries. The
# widget and panel are byte copies of the production files, with a status
# publisher at the test boundary and a window that gives the widget focus.
sysmon_fixture_install() {
sysmon_fixture_id="acme.sysmon-keys-$BASHPID-$1"
sysmon_fixture="$home/.config/vgshell/plugins/$sysmon_fixture_id"
mkdir -- "$sysmon_fixture"
cp -R -- "$repo/shell/plugins/vgs.sysmon/." "$sysmon_fixture/"
python3 - "$sysmon_fixture" "$sysmon_fixture_id" "$1" <<'PYFIXTURE'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); m=json.loads((p/"manifest.json").read_text())
m["id"]=sys.argv[2]; m["name"]="System Monitor keyboard fixture"
m["kinds"]=["service","bar-widget","panel","window"]
m["entryPoints"]["window"]="Window.qml"
(p/"manifest.json").write_text(json.dumps(m))
(p/"Service.qml").write_text('''import QtQuick
Item {
    property var shell: null
    onShellChanged: if (shell !== null) {
        shell.ipc.handle("lease", () => "ok");
        shell.status.set("readings", {cpu:{use:5,temperature:54,cores:16},memory:{use:25,used:1073741824,total:4294967296,available:3221225472,swapUse:0,swapUsed:0,swapTotal:0},gpu:null});
    }
}
''')
if sys.argv[3]=="control":
    widget=p/"Widget.qml"; source=widget.read_text(); old="onClicked: root.toggle()"
    assert source.count(old)==3
    source=source.replace(old,"onClicked: root.controlActivations += 1")
    old="    id: root\n"; assert source.count(old)==1
    widget.write_text(source.replace(old,old+"    property int controlActivations: 0\n"))
(p/"Window.qml").write_text('''import QtQuick
import qs.Ui
Item {
    id: root
    property var shell: null
    property Item initialFocus: null
    implicitWidth: 400
    implicitHeight: 100
    function focusCpu() {
        const row = widget.children.find(child => child instanceof Row);
        initialFocus = row.children.find(child => child.iconName === "cpu");
        initialFocus.forceActiveFocus(Qt.TabFocusReason);
    }
    // The host captures initialFocus during open(), before mapping the
    // window, then applies that captured target when Qt activates it.
    function open(payload) { focusCpu(); }
    function close() {}
    Pane { anchors.fill: parent
        Widget { id: widget; shell: root.shell; settings: root.shell === null ? ({}) : root.shell.settings }
    }
}
''')
PYFIXTURE
cp -- "$repo/scripts/smoke/fixtures/tui/vgs.sysmon/tui/btop.sh" "$sysmon_fixture/tui/btop.sh"
}
sysmon_fixture_install normal
rescan "the keyboard fixture is discovered"
expect "the keyboard fixture enables" ok ipc shell setPluginEnabled "$sysmon_fixture_id" true
expect "the keyboard fixture enters the bar" ok ipc shell setPluginPlaced "$sysmon_fixture_id" true
expect_poll "no GPU hides its reading in the bar" '["cpu", "memory-stick"]' sysmon_icons "$sysmon_key" "$sysmon_fixture_id"
expect "the real widget opens in the disposable keyboard window" ok ipc shell summon window "$sysmon_fixture_id" '{}'
expect_poll "the keyboard window appears" shown sysmon_shown window "$sysmon_fixture_id"
expect_poll "the keyboard window holds the nested keyboard" true ipc smoke windowFocused window "$sysmon_fixture_id"
expect_poll "the CPU button holds Qt focus before Enter" true ipc smoke readMatchingDescendant window "$sysmon_fixture_id" BarItem iconName cpu activeFocus
type_keys -k Return
expect_poll "Enter on the real widget opens the flyout" shown sysmon_shown panel "$sysmon_fixture_id"
type_keys -k Escape
expect_poll "the keyboard flyout closes" hidden sysmon_shown panel "$sysmon_fixture_id"
expect "the keyboard window closes" ok ipc shell hide window "$sysmon_fixture_id"
expect "the fixture disables" ok ipc shell setPluginEnabled "$sysmon_fixture_id" false
rm -rf -- "${sysmon_fixture:?}"
rescan "the disposable fixture is removed"
sysmon_fixture_install control
rescan "the Enter control is discovered"
expect "the Enter control enables" ok ipc shell setPluginEnabled "$sysmon_fixture_id" true
expect "the Enter control opens in its keyboard window" ok ipc shell summon window "$sysmon_fixture_id" '{}'
expect_poll "the Enter control window appears" shown sysmon_shown window "$sysmon_fixture_id"
expect_poll "the Enter control window holds the nested keyboard" true ipc smoke windowFocused window "$sysmon_fixture_id"
expect_poll "the control CPU button holds Qt focus before Enter" true ipc smoke readMatchingDescendant window "$sysmon_fixture_id" BarItem iconName cpu activeFocus
type_keys -k Return
expect_poll "control: the same Enter reaches the disabled activation" 1 ipc smoke readDescendant window "$sysmon_fixture_id" Widget controlActivations
expect "control: disabled activation leaves the flyout closed" hidden sysmon_shown panel "$sysmon_fixture_id"
expect "the Enter control window closes" ok ipc shell hide window "$sysmon_fixture_id"
expect "the Enter control disables" ok ipc shell setPluginEnabled "$sysmon_fixture_id" false
rm -rf -- "${sysmon_fixture:?}"
rescan "the Enter control is removed"
cp -- "$sysmon_saved" "$home/.config/vgshell/shell.json"
expect "the original configuration returns" ok ipc shell reloadConfig
rest_pointer
# smoke_row runs scripts/smoke/leaks.sh on this restored state.
