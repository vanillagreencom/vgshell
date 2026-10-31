import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Commons

// One screen's presented cover: the cover kind of the screensaver stage's
// owner (CoverPresentation.ownerId), in one slot that lives as long as the
// screen and the owner. The slot draws on this host's cover layer while the
// presentation is on the desktop and moves into the screen's lock surface
// while it is secure. Only its visual parent changes: the Variants owns the
// slot, so a window or lock surface that goes leaves it unparented, not
// destroyed, and the same instance keeps its rows, its last frame and its
// renderer process across the move (a nested run of the VGS-2097
// feasibility probe on Quickshell 0.3.1, 2026-10-31: one identity, one
// renderer pid and the frame text across three locks and a lock surface's
// teardown). The slot fills the surface it sits in, as BackgroundHost's
// slots do: the screen's own geometry did not match the cover layer's size
// in the sandbox-shots world, which drew the art off centre. Both surfaces
// cover the whole output; the slot moves into the lock only once the lock
// surface's root has its size, so the move resizes nothing, since a resize
// would restart a cover's effect.
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
    // QsWindow.contentItem, the window's root item:
    // https://quickshell.org/docs/v0.3.1/types/Quickshell/QsWindow/
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
            // On demand, as BackgroundHost's cover layer takes it.
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
