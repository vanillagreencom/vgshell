import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Built only for an explicit Share. Destroying this view releases the matrix,
// its collector and the helper which owns the NetworkManager secret pipe.
FocusScope {
    id: root
    objectName: "network-share-view"
    property var target: null
    property var shareState: ({ kind: "loading", data: "" })
    signal dismissed()
    readonly property Item initialFocus: closeButton
    readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("bin/share-qr")).replace(/^file:\/\//, ""))
    implicitHeight: content.implicitHeight
    Keys.onEscapePressed: event => { root.dismissed(); event.accepted = true; }

    function clear() {
        shareState = { kind: "closed", data: "" };
        helper.running = false;
    }
    Component.onDestruction: clear()
    Component.onCompleted: {
        helper.command = ["python3", helperPath, target.interface, target.name, target.security];
        helper.running = true;
        Qt.callLater(() => closeButton.forceActiveFocus(Qt.ShortcutFocusReason));
    }
    Process {
        id: helper
        stdout: StdioCollector { id: output; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: code => {
            if (root.shareState.kind === "closed") return;
            root.shareState = code === 0 && output.text !== "" ? { kind: "ready", data: output.text } : { kind: "failed", data: "" };
        }
    }
    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group
        Label { width: parent.width; role: "bodyStrong"; text: root.target === null ? "Share Wi-Fi" : root.target.name; wrapMode: Text.Wrap }
        Label { width: parent.width; role: "hint"; text: root.shareState.kind === "loading" ? "Creating QR code…" : root.shareState.kind === "failed" ? "This network could not be shared. NetworkManager may require access to its saved password." : "Scan to join this network."; wrapMode: Text.Wrap }
        QrMatrix {
            id: matrix
            objectName: "network-share-matrix"
            width: Math.min(parent.width, implicitWidth)
            height: width
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.shareState.kind === "ready"
            matrixData: root.shareState.data
        }
        Button { id: closeButton; text: "Close QR code"; variant: "secondary"; onClicked: root.dismissed() }
    }
}
