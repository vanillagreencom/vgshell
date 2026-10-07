import QtQuick
import Quickshell.Io
import Quickshell.Hyprland
import "KeyboardLogic.js" as Logic

Item {
    id: root
    property var shell: null
    property var catalog: []
    property string catalogState: "pending"
    property var layoutEvent: null
    readonly property var devices: shell === null ? null : shell.hyprland.devices
    readonly property var active: Logic.activeValue(devices, layoutEvent)

    onShellChanged: { publishCatalog(); publishActive(); }
    onCatalogStateChanged: publishCatalog()
    onActiveChanged: publishActive()

    function publishValue(key, value) {
        if (shell === null) return;
        const reply = shell.status.set(key, value);
        if (reply !== "ok" && reply.indexOf("reason=retired") === -1) console.warn("keyboard: status " + reply);
    }

    function publishCatalog() { publishValue("catalog", { state: catalogState, layouts: catalog }); }
    function publishActive() { publishValue("active", active); }

    // FileView loads once without watchChanges. loaded precedes text(),
    // so parsing never blocks startup. Quickshell 0.3.1 FileView reference:
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/FileView
    FileView {
        path: "/usr/share/X11/xkb/rules/evdev.xml"
        onLoaded: {
            try {
                root.catalog = Logic.parseCatalog(text());
                root.catalogState = "ready";
            } catch (error) {
                root.catalogState = "failed";
                console.warn("keyboard: " + error.message);
            }
        }
        onLoadFailed: error => {
            root.catalogState = "failed";
            console.warn("keyboard: catalog-read=" + error);
        }
    }

    // rawEvent supplies a HyprlandEvent; parse(2) keeps commas in the
    // layout name. Quickshell 0.3.1 HyprlandEvent reference:
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/HyprlandEvent
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activelayout") return;
            const args = event.parse(2);
            root.layoutEvent = { keyboard: args[0], name: args[1] };
        }
    }
}
