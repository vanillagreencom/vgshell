import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import qs.Hosts as Hosts

// The notice host's centered surface places the shared dialog outside the
// caller's scrolling body. QsWindow supplies the caller's screen:
// https://quickshell.org/docs/v0.3.1/types/Quickshell/QsWindow/.
// The opening owns the surface and its caller hold. Closing or destroying
// it releases native input before returning the popup grab to its caller.
Item {
    id: root

    property bool shown: false
    property string title: ""
    property string message: ""
    property var actions: []
    property bool busy: false
    property Component body: null
    // A menu detaches its content from the backing window when it hides
    // (Menu.qml, Quickshell 0.3.1 deleteOnInvisible). Help opened there
    // belongs to the durable opener's output instead of that popup.
    property Item screenOwner: root
    // Confirmations keep their held background; informational help may
    // dismiss through the same scrim without accepting an action.
    property bool dismissOnOutside: false
    readonly property var availableScreen: OverlayState.outputOf(screenOwner)
    // One opening owns its caller hold and output. A native popup can lose
    // its window while the modal has the keyboard, without losing either
    // its plugin or this modal's output.
    property var presentation: null
    property bool disposing: false
    readonly property bool outputPresent: presentation === null || Quickshell.screens.indexOf(presentation.screen) !== -1
    readonly property var screen: presentation === null ? availableScreen : presentation.screen
    visible: surfaceLoader.item !== null && surfaceLoader.item.visible && surfaceLoader.item.backingWindowVisible
    function syncPresentation() {
        if (disposing) return;
        if (!shown) { endPresentation(); return; }
        const available = availableScreen !== null && Quickshell.screens.indexOf(availableScreen) !== -1;
        if (presentation !== null) {
            if (available && availableScreen !== presentation.screen)
                presentation = { screen: availableScreen, release: presentation.release };
            return;
        }
        if (!available) return;
        // QsWindow exposes the QML window owner, not its Qt backer
        // (Quickshell 0.3.1, ProxyWindowAttached::setWindow).
        const caller = screenOwner === null ? null : screenOwner.QsWindow.window;
        const release = caller !== null && typeof caller.holdForModal === "function" ? caller.holdForModal() : null;
        OverlayState.opened();
        presentation = { screen: availableScreen, release: release };
    }
    function endPresentation() {
        const held = presentation;
        if (held === null) return;
        // Loader clears its object with deleteLater. Release native input
        // before clearing it, not when deferred QObject teardown runs.
        // https://code.qt.io/cgit/qt/qtdeclarative.git/tree/src/quick/items/qquickloader.cpp?h=6.12
        const surface = surfaceLoader && surfaceLoader.item;
        if (surface && surface.visible !== undefined) surface.visible = false;
        presentation = null;
        // Unmap the modal before its caller retakes the popup grab.
        if (held.release !== null) held.release();
        OverlayState.closed();
    }
    onShownChanged: syncPresentation()
    onAvailableScreenChanged: syncPresentation()
    onOutputPresentChanged: if (!outputPresent && !disposing) { endPresentation(); rejected(); }
    Component.onCompleted: syncPresentation()
    Component.onDestruction: { disposing = true; endPresentation(); }

    signal accepted()
    signal rejected()

    Loader {
        id: surfaceLoader
        active: root.presentation !== null
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
