import QtQuick
import qs.Commons
import qs.Ui
import "PowerLogic.js" as Logic

// The Power item in the bar: battery level where a laptop battery exists,
// and the active power-profile icon where none does, or beside the battery
// while the `barProfile` setting is on (Logic.widgetView). While Stay
// awake is on, the cup takes the first shown item's icon, or stands alone
// where neither shows, drawn in `bar.active`, the focused workspace's
// colour, while the battery level keeps the bar's text colour; the
// tooltip reads its time left. It reads only the
// service's status value and its settings, and it opens or closes the
// flyout on a click.
BarWidget {
    id: widget

    readonly property var power: shell === null || shell.status.values.power === undefined ? null : shell.status.values.power
    // Read at each minute Time.now ticks while Stay awake is on, at
    // Date.now(), as StayAwake.qml reads its time left.
    readonly property var view: {
        if (Logic.stayAwakeView(power).active) Time.now;
        return Logic.widgetView(power, setting("barProfile", false), Date.now());
    }
    // The cup draws no text, so the item it marks names the state in its
    // accessible name.
    readonly property string awakeName: "Stay awake on"
    readonly property color tone: widget.bar ? widget.bar.foreground : Theme.bar.foreground

    visible: view.shown
    implicitWidth: view.shown ? row.implicitWidth : 0
    implicitHeight: barSize

    function toggle() {
        const reply = shell.surfaces.toggle("panel", "{}", widget);
        if (reply !== "ok") console.warn("power widget: panel " + reply);
        return reply;
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.bar.item.gap

        BarItem {
            id: batteryItem
            visible: widget.view.batteryShown
            label: widget.view.cupHost === "battery" ? "Battery, " + widget.awakeName : "Battery"
            iconName: widget.view.batteryIcon
            text: widget.view.levelText
            tone: widget.tone
            iconTone: widget.view.cupHost === "battery" ? Theme.bar.active : widget.tone
            tooltip: widget.view.tooltip
            tooltipDetails: widget.view.tooltipDetails
            onClicked: widget.toggle()
        }

        BarItem {
            id: profileItem
            visible: widget.view.profileShown
            label: widget.view.cupHost === "profile" ? "Power profile, " + widget.awakeName : "Power profile"
            iconName: widget.view.profileIcon
            tone: widget.tone
            iconTone: widget.view.cupHost === "profile" ? Theme.bar.active : widget.tone
            tooltip: widget.view.tooltip
            tooltipDetails: widget.view.tooltipDetails
            onClicked: widget.toggle()
        }

        BarItem {
            id: stayAwakeItem
            visible: widget.view.cupHost === "alone"
            label: "Stay awake"
            iconName: Logic.CUP
            tone: widget.tone
            iconTone: Theme.bar.active
            tooltip: widget.view.tooltip
            tooltipDetails: widget.view.tooltipDetails
            onClicked: widget.toggle()
        }
    }
}
