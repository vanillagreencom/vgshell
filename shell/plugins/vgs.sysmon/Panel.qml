import QtQuick
import qs.Commons
import qs.Ui
import "SysmonLogic.js" as Logic

FocusScope {
    id: root
    property var shell: null
    readonly property var readings: shell === null ? ({}) : shell.status.values.readings || ({})
    readonly property var cpu: readings.cpu || ({})
    readonly property var memory: readings.memory || ({})
    readonly property var gpu: readings.gpu || null
    readonly property bool btopPresent: shell !== null && shell.requirements.missing.indexOf("btop") === -1
    readonly property Item initialFocus: root
    property string problem: ""
    property bool leased: false
    property var leaseShell: null
    property string leaseId: ""
    implicitWidth: Theme.size.panel.md
    implicitHeight: layout.implicitHeight
    function open(payloadJson) {
        problem = "";
        if (leaseId === "") leaseId = String(root);
        if (!leased && shell !== null && shell.ipc.call("lease", JSON.stringify({ id: leaseId, open: true })) === "ok") { leased = true; leaseShell = shell; }
    }
    function close() {
        if (leased && leaseShell !== null) leaseShell.ipc.call("lease", JSON.stringify({ id: leaseId, open: false }));
        leased = false;
        leaseShell = null;
    }
    Component.onDestruction: close()
    function setting(name, fallback) { return shell !== null && shell.settings[name] !== undefined ? shell.settings[name] : fallback; }
    function percent(value) { return typeof value === "number" ? Math.round(value) + "%" : "--"; }
    function degrees(value) { return typeof value === "number" ? Math.round(value) + "°" : "--"; }
    function gb(value) { return typeof value === "number" ? (value / 1073741824).toFixed(1) + " GB" : "--"; }
    function tone(value, warning, danger) { const state = Logic.tone(value, warning, danger); return state === "normal" ? "accent" : state; }
    function seeAll() {
        const reply = shell.tui.run("btop", []);
        if (reply === "ok" || reply === "busy") shell.surfaces.hide("panel");
        else { problem = "The process list could not open."; console.warn("sysmon panel: btop " + reply); }
        return reply;
    }

    Surface { anchors.fill: parent }
    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight
        title: "System Monitor"
        footer: [
            Column {
                width: layout.contentWidth
                spacing: Theme.stack.row
                Label { visible: text !== ""; width: parent.width; role: "hint"; text: root.problem; wrapMode: Text.WordWrap }
                Button { visible: root.btopPresent; width: parent.width; text: "See all"; iconName: "external-link"; variant: "tertiary"; onClicked: root.seeAll() }
            }
        ]
        GroupList {
            width: layout.contentWidth
            Reading {
                width: parent.width
                visible: root.setting("showCpu", true)
                title: "CPU"; iconName: "cpu"
                reading: root.percent(root.cpu.use)
                value: root.cpu.use
                tone: root.tone(root.cpu.use, 60, 80)
                details: ["Temperature " + root.degrees(root.cpu.temperature) + " · " + (typeof root.cpu.cores === "number" ? root.cpu.cores + " cores" : "-- cores")]
            }
            Reading {
                width: parent.width
                visible: root.setting("showMemory", true)
                title: "Memory"; iconName: "memory-stick"
                reading: root.percent(root.memory.use)
                value: root.memory.use
                tone: root.tone(root.memory.use, 75, 90)
                details: [root.gb(root.memory.used) + " of " + root.gb(root.memory.total), root.gb(root.memory.available) + " available", "Swap " + root.gb(root.memory.swapUsed) + " of " + root.gb(root.memory.swapTotal)]
            }
            Reading {
                width: parent.width
                visible: root.setting("showGpu", true) && root.gpu !== null
                title: "GPU"; iconName: "gpu"
                reading: root.gpu && root.gpu.state === "asleep" ? "Asleep" : root.percent(root.gpu ? root.gpu.use : null)
                value: root.gpu && root.gpu.state !== "asleep" ? root.gpu.use : null
                description: root.gpu ? root.gpu.name + (root.gpu.state === "unsupported" ? " · Use not available" : "") : ""
                details: root.gpu && root.gpu.state === "asleep" ? ["The graphics card is asleep."] : ["VRAM " + root.gb(root.gpu ? root.gpu.vramUsed : null) + " of " + root.gb(root.gpu ? root.gpu.vramTotal : null), "Temperature " + root.degrees(root.gpu ? root.gpu.temperature : null)]
            }
        }
    }
}
