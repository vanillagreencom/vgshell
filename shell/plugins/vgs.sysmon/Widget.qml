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
    readonly property bool captions: setting("labelStyle", "icons") === "text"
    readonly property var gpuTemperature: gpu && gpu.state !== "asleep" ? gpu.temperature : null
    visible: setting("showCpu", true) || setting("showMemory", true) || (setting("showGpu", true) && gpu !== null)

    function percent(value) { return typeof value === "number" ? Math.round(value) + "%" : "--"; }
    function degrees(value) { return Logic.degrees(value, setting("temperatureUnit", "Celsius")); }
    // The widest form of each reading, which its BarItem holds.
    readonly property string percentSample: percent(100)
    readonly property string degreesSample: degrees(100)
    function gb(value) { return typeof value === "number" ? (value / 1073741824).toFixed(1) + " GB" : "--"; }
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
        spacing: Theme.bar.gap
        BarItem {
            visible: root.setting("showCpu", true)
            label: "CPU"
            iconName: root.captions ? "" : "cpu"
            caption: root.captions ? "CPU" : ""
            text: root.percent(root.cpu.use)
            count: root.setting("cpuTemperature", false) ? root.degrees(root.cpu.temperature) : ""
            textSample: root.percentSample
            countSample: root.degreesSample
            separator: "/"
            textLevel: Logic.tone(root.cpu.use, 60, 80)
            countLevel: Logic.tone(root.cpu.temperature, 70, 85)
            tooltip: "CPU " + root.percent(root.cpu.use) + " · " + root.degrees(root.cpu.temperature)
            onClicked: root.toggle()
        }
        BarItem {
            visible: root.setting("showMemory", true)
            label: "Memory"
            iconName: root.captions ? "" : "memory-stick"
            caption: root.captions ? "RAM" : ""
            text: root.setting("memoryUnit", "percent") === "used" ? root.gb(root.memory.used) : root.percent(root.memory.use)
            count: root.setting("showSwap", false) ? root.percent(root.memory.swapUse) : ""
            // Used memory never exceeds the total.
            textSample: root.setting("memoryUnit", "percent") === "used" ? root.gb(root.memory.total) : root.percentSample
            countSample: root.percentSample
            separator: "/"
            textLevel: Logic.tone(root.memory.use, 75, 90)
            tooltip: "Memory " + root.gb(root.memory.used) + " of " + root.gb(root.memory.total)
            onClicked: root.toggle()
        }
        BarItem {
            visible: root.setting("showGpu", true) && root.gpu !== null
            label: "GPU"
            iconName: root.captions ? "" : "gpu"
            caption: root.captions ? "GPU" : ""
            text: root.percent(root.gpu && root.gpu.state === "asleep" ? null : root.gpu ? root.gpu.use : null)
            count: root.setting("gpuTemperature", false) ? root.degrees(root.gpuTemperature) : ""
            textSample: root.percentSample
            countSample: root.degreesSample
            separator: "/"
            countLevel: Logic.tone(root.gpuTemperature, 65, 80)
            tooltip: root.gpu ? root.gpu.name + " · " + (root.gpu.state === "asleep" ? "Asleep" : root.percent(root.gpu.use) + " · " + root.degrees(root.gpu.temperature)) : "GPU"
            onClicked: root.toggle()
        }
    }
}
