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
    readonly property var screen: OverlayState.outputOf(root)
    signal accepted()
    signal rejected()

    Loader {
        active: root.shown && root.screen !== null
        sourceComponent: Hosts.OverlaySurface {
            screen: root.screen
            placement: "center"
            inset: Theme.dialog.margin
            inputItems: [card]
            WlrLayershell.namespace: "vgs:dialog"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

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
                Component.onCompleted: forceActiveFocus(Qt.TabFocusReason)
            }
        }
    }
}
