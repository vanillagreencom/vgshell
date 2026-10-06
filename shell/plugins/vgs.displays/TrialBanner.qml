import QtQuick
import qs.Commons
import qs.Ui
import "DisplaysLogic.js" as Logic

// Passive trial countdown on every screen. The pane owns Keep and Revert.
Item {
    id: root

    property var screen: null
    property var service: null
    readonly property var trialState: service === null || service.shell === null ? ({ phase: "idle", deadline: 0 }) : service.shell.monitors.trialState
    readonly property bool shown: trialState.phase === "holding"
    property int nowSeconds: Math.floor(Date.now() / 1000)

    visible: shown

    Surface {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.stack.section
        level: "raised"
        width: label.implicitWidth + 2 * Theme.osd.padding
        height: label.implicitHeight + 2 * Theme.osd.padding

        Label {
            id: label
            anchors.centerIn: parent
            role: "body"
            text: Logic.countdownText(root.trialState.deadline - root.nowSeconds)
        }
    }

    Timer {
        interval: 250
        running: root.visible
        repeat: true
        onTriggered: root.nowSeconds = Math.floor(Date.now() / 1000)
    }
}
