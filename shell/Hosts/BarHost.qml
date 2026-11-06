import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Commons

// A disabled, unknown or broken bar must reserve no desktop space.
// Hiding a layer-shell window releases its Wayland surface's reserved
// space while retaining the plugin instance for the next show.
Item {
    id: host

    required property var modelData
    readonly property var screen: modelData
    readonly property bool screenPresent: Quickshell.screens.indexOf(screen) !== -1
    // The screen is null while its Variants entry is torn down.
    readonly property string hostKey: "bar:" + (screen ? screen.name : "")

    // The slot key the active bar would load under, or "" when no bar can
    // be built. A key whose build failed is remembered so the window is not
    // re-created for it; a source revision change makes a new key.
    readonly property string wantedKey: Registry.slotKey(Registry.activeBarId)
    property string brokenKey: ""

    Loader {
        id: surface
        // Quickshell.screens drops a removed screen before Qt moves its
        // windows to another screen, and a window still built then gets a
        // layer surface there, reserving space twice until it goes.
        active: host.screenPresent && host.wantedKey !== "" && host.wantedKey !== host.brokenKey
        sourceComponent: PanelWindow {
            screen: host.screen

            anchors { top: true; left: true; right: true }
            implicitHeight: Theme.bar.height
            exclusiveZone: implicitHeight
            color: Theme.bar.background
            WlrLayershell.namespace: "vgs:bar"
            WlrLayershell.layer: WlrLayer.Top
            // Quickshell 0.3.1 defers native window deletion after the Loader
            // drops its item. Hide first, or Qt can remap it as a toplevel
            // while a removed output migrates its windows.
            visible: host.screenPresent && PluginLogic.barShown(slot.instance)

            PluginSlot {
                id: slot
                listed: surface.active
                kind: "bar"
                pluginId: Registry.activeBarId
                hostKey: host.hostKey
                screen: host.screen
                context: ({ screen: host.screen })
                anchors.fill: parent
                onBuildFailed: key => host.brokenKey = key
            }
        }
    }
}
