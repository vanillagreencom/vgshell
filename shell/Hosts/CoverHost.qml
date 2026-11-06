import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Commons

// Variants owns the slot; moving its visual parent between desktop and
// lock surfaces must preserve the instance and its renderer.
// Size from the actual parent, not the screen's logical geometry. Wait
// for a sized lock root before moving, since a resize restarts cover effects.
// Under the lock the slot takes no input; LockHost's barrier does. Every
// other cover plugin stays in BackgroundHost and never enters the lock.
Item {
    id: host

    required property var modelData
    readonly property var screen: modelData
    // The background host's cover key, so a cover's records and readers
    // name one host per screen whichever host builds it.
    readonly property string hostKey: "cover:" + (screen ? screen.name : "")
    readonly property var covers: Capabilities.covers
    readonly property var owners: covers.ownerId === "" ? [] : [covers.ownerId]
    readonly property var secureRoot: screen !== null && PluginLogic.hasOwn(covers.secureRoots, screen.name) ? covers.secureRoots[screen.name] : null
    // Until the lock surface offers its root with a size, the slot stays on
    // this layer, which the compositor no longer draws once the session is
    // locked.
    readonly property bool secureReady: secureRoot !== null && secureRoot.width > 0 && secureRoot.height > 0
    readonly property bool secure: covers.placement === "secure" && secureReady
    readonly property var presentation: covers.contextFor()
    readonly property var desktopRoot: surface.item === null ? null : surface.item.contentItem
    // Whether this screen holds a built cover instance of the owner. A
    // build that failed or was refused (a restart owed) leaves the slot with
    // none; CoverPresentation starts no presentation without one and ends
    // the running one when the last goes.
    readonly property bool built: slots.instances.some(slot => slot.instance !== null)
    property var releaseBuilt: null
    onBuiltChanged: offerBuilt()
    Component.onCompleted: offerBuilt()
    Component.onDestruction: if (releaseBuilt !== null) releaseBuilt()
    function offerBuilt() {
        if (built && releaseBuilt === null) {
            releaseBuilt = covers.registerBuilt();
        } else if (!built && releaseBuilt !== null) {
            releaseBuilt();
            releaseBuilt = null;
        }
    }

    Loader {
        id: surface
        // Quickshell.screens drops a removed screen before Qt moves its
        // windows to another screen (BackgroundHost).
        active: Quickshell.screens.indexOf(host.screen) !== -1 && host.owners.length > 0
        sourceComponent: PanelWindow {
            screen: host.screen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: Theme.color.background
            WlrLayershell.namespace: "vgs:cover"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: PluginLogic.perScreenLayerTakesKeyboard("cover", Quickshell.screens, host.screen) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            visible: host.covers.placement !== "none" && !host.secure && slots.instances.some(slot => slot.instance !== null)
        }
    }

    Variants {
        id: slots
        model: host.owners

        PluginSlot {
            required property string modelData
            parent: host.secure ? host.secureRoot : host.desktopRoot
            x: 0
            y: 0
            width: parent === null ? 0 : parent.width
            height: parent === null ? 0 : parent.height
            enabled: !host.secure
            listed: host.owners.indexOf(modelData) !== -1
            kind: "cover"
            pluginId: modelData
            hostKey: host.hostKey
            screen: host.screen
            context: ({ screen: host.screen, presentation: host.presentation })
        }
    }
}
