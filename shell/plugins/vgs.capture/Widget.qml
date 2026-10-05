import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    readonly property var capture: shell === null || shell.status.values.capture === undefined ? ({ phase: "idle" }) : shell.status.values.capture
    readonly property bool recording: capture.phase === "recording" || capture.phase === "stopping"
    implicitWidth: button.implicitWidth
    implicitHeight: barSize

    BarItem {
        id: button
        anchors.centerIn: parent
        label: root.recording ? "Recording" : "Capture"
        iconName: root.recording ? "circle-stop" : "camera"
        tone: root.recording ? Theme.color.danger : root.bar ? root.bar.foreground : Theme.color.text
        tooltip: root.capture.phase === "stopping" ? "Saving recording" : root.recording ? "Stop recording" : "Capture options"
        onClicked: root.shell.ipc.call(root.recording ? "record" : "toggle", "")
    }
}
