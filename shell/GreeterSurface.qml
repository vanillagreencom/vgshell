import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// The interactive instance belongs to the host, not a screen delegate.
// QsWindow.screen can move a window to another screen without replacing
// its content: https://quickshell.org/docs/v0.3.1/types/Quickshell/QsWindow/
PanelWindow {
    id: root

    property var output: null
    property string view: ""
    property bool interactive: false
    signal unloadable()

    screen: output
    visible: output !== null && view !== ""
    color: Theme.color.background
    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "vgs:greeter"
    WlrLayershell.keyboardFocus: interactive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Loader {
        anchors.fill: parent
        source: root.view === "" ? "" : "file://" + root.view
        onLoaded: {
            item.screen = Qt.binding(() => root.output);
            item.interactive = root.interactive;
        }
        onStatusChanged: if (status === Loader.Error) root.unloadable()
    }
}
