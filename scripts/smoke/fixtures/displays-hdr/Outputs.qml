import QtQuick
import qs.Core
import "../../../../shell/Core/MonitorLogic.js" as Monitors

// Built through Probe.qml's existing popupLoad boundary.
// Only the shell's JSON observation is posed; the nested compositor retains
// its own capability flags and native HDR admission.
Item {
    id: root
    property var fixture: null

    function pose(text) {
        const read = Monitors.parseOutputs(JSON.stringify(JSON.parse(text).outputs));
        if (!read.ok) throw new Error(read.error);
        fixture = read.outputs;
        publish();
    }

    function publish() {
        if (fixture !== null && JSON.stringify(Capabilities.monitors.outputs) !== JSON.stringify(fixture))
            Capabilities.monitors.outputs = fixture;
    }

    function release() {
        fixture = null;
        Capabilities.monitors.readOutputs();
    }

    Connections {
        target: Capabilities.monitors
        function onOutputsChanged() { root.publish(); }
    }
}
