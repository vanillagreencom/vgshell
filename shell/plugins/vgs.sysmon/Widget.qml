import QtQuick
import qs.Commons
import qs.Ui
import "SysmonLogic.js" as Logic

BarWidget {
    id: root
    readonly property var readings: shell === null ? ({}) : shell.status.values.readings || ({})
    readonly property var cpu: readings.cpu || ({})
    readonly property var memory: readings.memory || ({})
    readonly property var gpu: readings.gpu || null
    property bool leased: false
    property var leaseShell: null
    property string leaseId: ""
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    visible: setting("showCpu", true) || setting("showMemory", true) || (setting("showGpu", true) && gpu !== null)

    function percent(value) { return typeof value === "number" ? Math.round(value) + "%" : "--"; }
    function degrees(value) { return Logic.degrees(value, setting("temperatureUnit", "Celsius")); }
    function gb(value) { return typeof value === "number" ? (value / 1073741824).toFixed(1) + " GB" : "--"; }
    function tone(value, warning, danger) {
        const state = Logic.tone(value, warning, danger);
        return state === "danger" ? Theme.color.danger : state === "warning" ? Theme.color.warning : Theme.bar.foreground;
    }
    function holdLease() {
        if (shell === null || leased) return;
        if (leaseId === "") leaseId = String(root);
        if (shell.ipc.call("lease", JSON.stringify({ id: leaseId, open: true })) === "ok") { leased = true; leaseShell = shell; }
    }
    onShellChanged: holdLease()
    // The service starts after the first bar frame. Its initial status
    // publish retries the lifetime lease without a widget poller.
    onReadingsChanged: holdLease()
    Component.onDestruction: if (leased && leaseShell !== null) leaseShell.ipc.call("lease", JSON.stringify({ id: leaseId, open: false }))
    function toggle() {
        const reply = shell.surfaces.toggle("panel", "{}", root);
        if (reply !== "ok") console.warn("sysmon widget: panel " + reply);
        return reply;
    }

    Row {
        id: row
        spacing: Theme.bar.item.gap
        BarItem {
            visible: root.setting("showCpu", true)
            label: "CPU"
            iconName: "cpu"
            text: root.percent(root.cpu.use)
            reservedText: "100%"
            count: root.setting("cpuTemperature", false) ? "/" + root.degrees(root.cpu.temperature) : ""
            compactCount: true
            reservedCount: root.setting("temperatureUnit", "Celsius") === "Fahrenheit" ? "/212°" : "/100°"
            tone: root.tone(root.cpu.use, 60, 80)
            textTone: Theme.bar.foreground
            countTone: root.tone(root.cpu.temperature, 70, 85)
            tooltip: "CPU " + root.percent(root.cpu.use) + " · " + root.degrees(root.cpu.temperature)
            onClicked: root.toggle()
        }
        BarItem {
            visible: root.setting("showMemory", true)
            label: "Memory"
            iconName: "memory-stick"
            text: root.setting("memoryUnit", "percent") === "used" ? root.gb(root.memory.used) : root.percent(root.memory.use)
            reservedText: root.setting("memoryUnit", "percent") === "used" ? "999.9 GB" : "100%"
            count: root.setting("showSwap", false) ? "· " + root.percent(root.memory.swapUse) : ""
            reservedCount: "· 100%"
            tone: root.tone(root.memory.use, 75, 90)
            textTone: Theme.bar.foreground
            countTone: Theme.bar.foreground
            tooltip: "Memory " + root.gb(root.memory.used) + " of " + root.gb(root.memory.total)
            onClicked: root.toggle()
        }
        BarItem {
            visible: root.setting("showGpu", true) && root.gpu !== null
            label: "GPU"
            iconName: "gpu"
            text: root.percent(root.gpu && root.gpu.state === "asleep" ? null : root.gpu ? root.gpu.use : null)
            reservedText: "100%"
            count: root.setting("gpuTemperature", false) ? root.degrees(root.gpu && root.gpu.state !== "asleep" ? root.gpu.temperature : null) : ""
            reservedCount: root.setting("temperatureUnit", "Celsius") === "Fahrenheit" ? "212°" : "100°"
            countTone: root.tone(root.gpu ? root.gpu.temperature : null, 65, 80)
            tooltip: root.gpu ? root.gpu.name + " · " + (root.gpu.state === "asleep" ? "Asleep" : root.percent(root.gpu.use) + " · " + root.degrees(root.gpu.temperature)) : "GPU"
            onClicked: root.toggle()
        }
    }
}
