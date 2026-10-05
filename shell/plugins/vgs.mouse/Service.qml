import QtQuick
import "MouseLogic.js" as Logic

Item {
    id: root

    property var shell: null
    property var registeredWith: null
    readonly property var devices: shell === null ? null : shell.hyprland.devices
    readonly property var published: Logic.statusValue(devices)

    onShellChanged: {
        if (shell === null || registeredWith !== null) return;
        registeredWith = shell;
        publish();
    }
    onDevicesChanged: publish()

    function publish() {
        if (shell === null || shell.status === undefined) return;
        const reply = shell.status.set("devices", published);
        if (reply !== "ok" && reply.indexOf("reason=retired") === -1) console.warn("mouse: devices " + reply);
    }
}
