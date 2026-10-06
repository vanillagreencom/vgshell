import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Commons

// One bar surface per screen. The core owns the window; the active bar
// plugin draws inside the slot and receives the screen through the slot's
// context. The window exists only while a bar instance can be built: a
// disabled, unknown or broken bar leaves no surface and reserves no space,
// so the desktop stays whole. A hidden window would keep its layer
// surface alive; destroying the window is what releases it. The surface is
// mapped only while the bar instance is shown, one without the property
// included: hiding a layer-shell window deletes its Wayland surface, which
// releases the space it reserves, and keeps the instance to show it again.
Item {
    id: host

    required property var modelData
    readonly property var screen: modelData
    // The screen is null while its Variants entry is torn down.
    readonly property string hostKey: "bar:" + (screen ? screen.name : "")

    // The slot key the active bar would load under, or "" when no bar can
    // be built. A key whose build failed is remembered so the window is not
    // re-created for it; a source revision change makes a new key.
    readonly property string wantedKey: Registry.slotKey(Registry.activeBarId)
    property string brokenKey: ""

    Loader {
        // Quickshell.screens drops a removed screen before Qt moves its
        // windows to another screen, and a window still built then gets a
        // layer surface there, reserving space twice until it goes.
        active: Quickshell.screens.indexOf(host.screen) !== -1 && host.wantedKey !== "" && host.wantedKey !== host.brokenKey
        sourceComponent: PanelWindow {
            screen: host.screen

            anchors { top: true; left: true; right: true }
            implicitHeight: Theme.bar.height
            exclusiveZone: implicitHeight
            color: Theme.bar.background
            WlrLayershell.namespace: "vgs:bar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: Plugins.barDrag !== null && Plugins.barDrag.hostKey === host.hostKey ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            visible: PluginLogic.barShown(slot.instance)

            PluginSlot {
                id: slot
                kind: "bar"
                pluginId: Registry.activeBarId
                hostKey: host.hostKey
                screen: host.screen
                context: ({ screen: host.screen })
                anchors.fill: parent
                onBuildFailed: key => host.brokenKey = key
            }

            Rectangle {
                id: dropMarker
                readonly property var drag: Plugins.barDrag
                visible: drag !== null && drag.hostKey === host.hostKey
                x: visible ? drag.markerX - width / 2 : 0
                y: Theme.bar.padding
                width: Theme.border.thick
                height: Math.max(Theme.border.thick, parent.height - 2 * Theme.bar.padding)
                radius: Theme.radius.full
                color: Theme.color.focus
                z: 1
            }

            Item {
                anchors.fill: parent
                visible: Plugins.barDrag !== null && Plugins.barDrag.hostKey === host.hostKey
                focus: visible
                z: 2
                onVisibleChanged: if (visible) forceActiveFocus(Qt.ShortcutFocusReason)
                Keys.onEscapePressed: event => {
                    Plugins.cancelBarDrag();
                    event.accepted = true;
                }
            }
        }
    }
}
