import QtQuick
import qs.Commons
import "DisplaysLogic.js" as Logic
import qs.Ui

// Passive trial countdown while no pane has the mapped Keep/Revert modal.
Item {
    id: root

    property var screen: null
    property var service: null
    readonly property var trialState: service === null || service.shell === null ? ({ phase: "idle", deadline: 0 }) : service.shell.monitors.trialState
    readonly property bool shown: trialState.phase === "holding" && (service === null || service.trialDialogs === 0)
    property int nowSeconds: Math.floor(Date.now() / 1000)

    visible: shown

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.dialog.margin
        width: Math.min(parent.width - 2 * Theme.dialog.margin, Theme.dialog.width)
        height: content.implicitHeight
        radius: Theme.dialog.radius
        color: Theme.dialog.background
        border.width: Theme.border.thin
        border.color: Theme.dialog.border

        Pane {
            id: content
            anchors.fill: parent
            container: "dialog"
            fitToContent: true
            title: "Keep these display settings?"
            titleRole: Theme.dialog.titleRole
            titleWrapMode: Text.Wrap
            Label {
                width: parent.width
                role: Theme.dialog.bodyRole
                text: Logic.countdownDetail(root.trialState.deadline - root.nowSeconds)
                wrapMode: Text.Wrap
            }
        }
    }

    Timer {
        interval: 250
        running: root.visible
        repeat: true
        onTriggered: root.nowSeconds = Math.floor(Date.now() / 1000)
    }
}
