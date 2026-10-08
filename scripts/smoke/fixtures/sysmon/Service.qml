import QtQuick

// The picture runner supplies readings through Probe's held status provider.
Item {
    property var shell: null
    property bool registered: false
    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("lease", () => "ok");
        shell.status.set("cpuSensors", [
            { value: "automatic", label: "Automatic" },
            { value: "hwmon:k10temp:temp1:Tctl", label: "AMD CPU · Tctl" },
            { value: "hwmon:k10temp:temp2:Tccd1", label: "AMD CPU · Tccd1" }
        ]);
    }
}
