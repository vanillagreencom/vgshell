import QtQuick
import qs.Commons
import qs.Ui
import "PowerLogic.js" as Logic

// The Power item in the bar: battery level where a laptop battery exists,
// and the active power-profile icon where none does, or beside the battery
// while the `barProfile` setting is on (Logic.widgetView). While Stay
// awake is on, a cup glyph leads the first item shown, in the item's own
// foreground, or stands alone where neither shows, and the tooltip reads
// its time left. It reads only the service's status value and its
// settings, and it opens or closes the flyout on a click.
BarWidget {
    id: widget

    readonly property var power: shell === null || shell.status.values.power === undefined ? null : shell.status.values.power
    // Read at each minute Time.now ticks while Stay awake is on, at
    // Date.now(), as StayAwake.qml reads its time left.
    readonly property var view: {
        if (Logic.stayAwakeView(power).active) Time.now;
        return Logic.widgetView(power, setting("barProfile", false), Date.now());
    }
    readonly property string cup: "coffee"
    // The cup draws no text, so the item it leads names the state in its
    // accessible name.
    readonly property string awakeName: "Stay awake on"

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
            leadingIconName: widget.view.cupHost === "battery" ? widget.cup : ""
            text: widget.view.levelText
            tone: widget.bar ? widget.bar.foreground : Theme.bar.foreground
            tooltip: widget.view.tooltip
            tooltipDetails: widget.view.tooltipDetails
            onClicked: widget.toggle()
        }

        BarItem {
            id: profileItem
            visible: widget.view.profileShown
            label: widget.view.cupHost === "profile" ? "Power profile, " + widget.awakeName : "Power profile"
            iconName: widget.view.profileIcon
            leadingIconName: widget.view.cupHost === "profile" ? widget.cup : ""
            tone: widget.bar ? widget.bar.foreground : Theme.bar.foreground
            tooltip: widget.view.tooltip
            tooltipDetails: widget.view.tooltipDetails
            onClicked: widget.toggle()
        }

        BarItem {
            id: stayAwakeItem
            visible: widget.view.cupHost === "alone"
            label: "Stay awake"
            iconName: widget.cup
            tone: widget.bar ? widget.bar.foreground : Theme.bar.foreground
            tooltip: widget.view.tooltip
            tooltipDetails: widget.view.tooltipDetails
            onClicked: widget.toggle()
        }
    }
}
