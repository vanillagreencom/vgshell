import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import qs.Hosts as Hosts

// The notice host's centered surface places the shared dialog outside the
// caller's scrolling body. QsWindow supplies the caller's screen:
// https://quickshell.org/docs/v0.3.1/types/Quickshell/QsWindow/.
// The Loader owns the surface, so hiding or destroying the caller releases
// its keyboard and window together.
Item {
    id: root

    property bool shown: false
    property string title: ""
    property string message: ""
    property var actions: []
    property bool busy: false
    property Component body: null
    // Confirmations keep their held background; informational help may
    // dismiss through the same scrim without accepting an action.
    property bool dismissOnOutside: false
    readonly property var screen: OverlayState.outputOf(root)
    visible: surfaceLoader.item !== null && surfaceLoader.item.visible && surfaceLoader.item.backingWindowVisible
    property bool counted: false
    function share(open) {
        if (open === counted) return;
        counted = open;
        if (open) OverlayState.opened(); else OverlayState.closed();
    }
    Component.onCompleted: share(surfaceLoader.active)
    Component.onDestruction: share(false)

    signal accepted()
    signal rejected()

    Loader {
        id: surfaceLoader
        active: root.shown && root.screen !== null
        onActiveChanged: root.share(active)
        sourceComponent: Hosts.OverlaySurface {
            screen: root.screen
            placement: "center"
            inset: Theme.dialog.margin
            inputAll: true
            WlrLayershell.namespace: "vgs:dialog"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            // The shared scrim consumes background input. A timed trial
            // can only end through its actions, Escape or its countdown.
            Scrim { onClicked: if (root.dismissOnOutside && !root.busy) root.rejected() }

            Dialog {
                id: card
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width)
                availableHeight: parent.height
                title: root.title
                message: root.message
                actions: root.actions
                busy: root.busy
                onAccepted: root.accepted()
                onRejected: root.rejected()
                Component.onCompleted: forceActiveFocus(Qt.OtherFocusReason)
                Loader {
                    width: parent.width
                    sourceComponent: root.body
                }
            }
        }
    }
}
