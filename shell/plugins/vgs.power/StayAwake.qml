import QtQuick
import qs.Commons
import qs.Ui
import "PowerLogic.js" as Logic

// Stay awake's one control, which the flyout and Power's section both
// draw inside a Field that shows `hint` and `problem`: while off, the
// durations and Start; while on, the time left and End. A press asks the
// service through IPC, which owns the hold (Service.qml stayAwakeRequest);
// the control reads the status value alone. With `fill`, the reading or
// the list takes the row's width less the button's.
Row {
    id: root

    property var shell: null
    property bool fill: false
    property string problem: ""
    readonly property var awake: Logic.stayAwakeView(shell === null ? null : shell.status.values.power)
    readonly property var durations: Logic.STAY_AWAKE_DURATIONS
    readonly property string hint: awake.active ? "Dimming and locking resume after it ends" : "Keeps the computer from dimming, locking or sleeping"
    readonly property real slotWidth: width - button.width - spacing

    spacing: Theme.stack.inline

    function request() {
        const arg = awake.active ? "end" : String(durations[list.currentIndex].minutes);
        const reply = shell.ipc.call("stay-awake", arg);
        problem = reply === "ok" ? "" : reply === "refused: stay-awake=battery-critical"
            ? "Stay awake does not start while the battery is critically low." : "VGS could not change Stay awake.";
        if (reply !== "ok") console.warn("power: stay-awake " + arg + " " + reply);
        list.currentIndex = Qt.binding(() => root.durations.findIndex(d => d.minutes === root.awake.minutes));
        return reply;
    }

    Label {
        visible: root.awake.active
        width: root.fill ? root.slotWidth : implicitWidth
        anchors.verticalCenter: parent.verticalCenter
        role: "value"
        // Read at each change of the hold and at each minute Time.now
        // ticks, at Date.now(): Time.now trails a start by up to a
        // minute, which would read a minute too many.
        text: { Time.now; return root.awake.active ? Logic.stayAwakeLeft(root.awake, Date.now()) : ""; }
    }
    Select {
        id: list
        visible: !root.awake.active
        width: root.fill ? root.slotWidth : implicitWidth
        model: root.durations
        textRole: "label"
        currentIndex: root.durations.findIndex(d => d.minutes === root.awake.minutes)
        Accessible.name: "Stay awake for"
    }
    Button {
        id: button
        anchors.verticalCenter: parent.verticalCenter
        variant: "secondary"
        size: "sm"
        text: root.awake.active ? "End" : "Start"
        onClicked: root.request()
    }
}
