import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Commons

// One per-screen layer host. Background plugins draw under windows and map
// unless every instance hides itself. Cover plugins draw above windows and
// map only when an instance asks to show. Each plugin receives the screen
// through its slot's context.
Item {
    id: host

    required property var modelData
    required property string kind
    required property string namespace
    required property int shellLayer
    required property int keyboardFocus
    readonly property var screen: modelData
    // The screen is null while its Variants entry is torn down.
    readonly property string hostKey: kind + ":" + (screen ? screen.name : "")

    // Plugin id -> the slot key whose build failed, one per plugin, so the
    // record stays as small as the plugin set. A source revision change
    // makes a new key, so a fixed plugin is tried again.
    property var brokenKeys: ({})
    Connections {
        target: Registry
        function onChanged() {
            // Plugins prunes its failure records on this same signal.
            Qt.callLater(() => {
                const ids = Object.keys(host.brokenKeys);
                const next = {};
                for (const id of ids)
                    if (Plugins.failedRevision(host.hostKey, host.kind, id) !== null) next[id] = host.brokenKeys[id];
                if (Object.keys(next).length !== ids.length) host.brokenKeys = next;
            });
        }
    }
    readonly property var ids: Registry.enabledOfKind(kind).filter(id => {
        const key = Registry.slotKey(id);
        return key !== "" && host.brokenKeys[id] !== key;
    })

    Loader {
        id: surface
        // Quickshell.screens drops a removed screen before Qt moves its
        // windows to another screen, and a window still built then gets a
        // layer surface there, a second background until it goes.
        active: Quickshell.screens.indexOf(host.screen) !== -1 && host.ids.length > 0
        sourceComponent: PanelWindow {
            id: win

            screen: host.screen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: Theme.color.background
            WlrLayershell.namespace: host.namespace
            WlrLayershell.layer: host.shellLayer
            WlrLayershell.keyboardFocus: PluginLogic.perScreenLayerTakesKeyboard(host.kind, Quickshell.screens, host.screen) ? host.keyboardFocus : WlrKeyboardFocus.None
            visible: slots.instances.some(slot => PluginLogic.perScreenLayerShown(host.kind, slot.instance))

            Variants {
                id: slots
                model: host.ids

                PluginSlot {
                    required property string modelData
                    parent: win.contentItem
                    anchors.fill: parent
                    z: host.ids.indexOf(modelData)
                    listed: surface.active && host.ids.indexOf(modelData) !== -1
                    kind: host.kind
                    pluginId: modelData
                    hostKey: host.hostKey
                    screen: host.screen
                    context: ({ screen: host.screen })
                    onBuildFailed: key => Qt.callLater(() => {
                        const next = Object.assign({}, host.brokenKeys);
                        next[modelData] = key;
                        host.brokenKeys = next;
                    })
                }
            }
        }
    }
}
