import QtQuick
import qs.Commons
import "DisplaysLogic.js" as Logic
import qs.Ui

// Passive trial countdown on every screen. The pane owns Keep and Revert.
Item {
    id: root

    property var screen: null
    property var service: null
    readonly property var trialState: service === null || service.shell === null ? ({ phase: "idle", deadline: 0 }) : service.shell.monitors.trialState
    readonly property bool shown: trialState.phase === "holding"
    property int nowSeconds: Math.floor(Date.now() / 1000)

    visible: shown

    Dialog {
        id: dialog
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.dialog.margin
        width: Math.min(parent.width - 2 * Theme.dialog.margin, implicitWidth)
        modal: false
        title: "Keep these display settings?"
        message: Logic.countdownDetail(root.trialState.deadline - root.nowSeconds)
        actions: []
    }

    Timer {
        interval: 250
        running: root.visible
        repeat: true
        onTriggered: root.nowSeconds = Math.floor(Date.now() / 1000)
    }
}
