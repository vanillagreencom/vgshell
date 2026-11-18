import QtQuick
import qs.Commons
import qs.Ui
import "PowerLogic.js" as Logic

// Stay awake's one control, which the flyout and Power's section both
// draw inside a Field that shows `hint` and `problem`: while off, the
// durations and Start; while on, the time left and End. A press asks the
// service through IPC, which owns the hold (Service.qml stayAwakeRequest);
// the control reads the status value alone. The action stays outside the
// input and moves below it when the value column has no trailing room.
Item {
    id: root

    property var shell: null
    property string problem: ""
    readonly property var awake: Logic.stayAwakeView(shell === null ? null : shell.status.values.power)
    readonly property var durations: Logic.STAY_AWAKE_DURATIONS
    readonly property string hint: awake.active ? "" : "Prevents the computer from sleeping"
    readonly property real availableWidth: parent !== null ? (parent.availableWidth ?? parent.width) : Infinity
    readonly property bool buttonBelow: !awake.active && list.width + Theme.stack.inline + button.width > availableWidth
    readonly property real firstLineHeight: buttonBelow ? Theme.textField.height : 0
    implicitWidth: awake.active ? reading.implicitWidth + Theme.stack.inline + button.width
        : list.width + (buttonBelow ? 0 : Theme.stack.inline + button.width)
    implicitHeight: buttonBelow ? list.height + Theme.field.gap + button.height : Math.max(awake.active ? reading.height : list.height, button.height)

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
        id: reading
        visible: root.awake.active
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
        model: root.durations
        textRole: "label"
        currentIndex: root.durations.findIndex(d => d.minutes === root.awake.minutes)
        Accessible.name: "Stay awake for"
    }
    Button {
        id: button
        x: root.buttonBelow ? 0 : (root.awake.active ? reading.width : list.width) + Theme.stack.inline
        y: root.buttonBelow ? list.height + Theme.field.gap : Math.round((root.height - height) / 2)
        variant: "secondary"
        size: "md"
        text: root.awake.active ? "End" : "Start"
        onClicked: root.request()
    }
}
