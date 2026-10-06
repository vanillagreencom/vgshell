import QtQuick
import qs.Commons
import qs.Ui
import "PowerLogic.js" as Logic

// The Power item in the bar: battery level where a laptop battery exists,
// and the active power-profile icon on laptops and desktops. It reads only
// the service's status value, and it opens or closes the flyout on a click.
BarWidget {
    id: widget

    readonly property var power: shell === null || shell.status.values.power === undefined ? null : shell.status.values.power
    readonly property var view: Logic.widgetView(power)

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
            label: "Battery"
            iconName: widget.view.batteryIcon
            text: widget.view.levelText
            tone: widget.bar ? widget.bar.foreground : Theme.bar.foreground
            tooltip: widget.view.tooltip
            onClicked: widget.toggle()
        }

        BarItem {
            id: profileItem
            visible: widget.view.profileShown
            label: "Power profile"
            iconName: widget.view.profileIcon
            tone: widget.bar ? widget.bar.foreground : Theme.bar.foreground
            tooltip: widget.view.tooltip
            onClicked: widget.toggle()
        }
    }
}
