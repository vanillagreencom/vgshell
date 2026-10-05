import QtQuick
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui
import "BluetoothLogic.js" as Logic

// The Bluetooth icon in the bar: off, on, or connected with the count of
// connected devices, as BluetoothLogic.barView decides from the power the
// service publishes and the devices Quickshell's Bluetooth singleton
// lists. It starts no process and writes nothing to BlueZ. A click opens
// or closes the flyout under it. A hidden icon stays placed. The bar takes
// no keyboard focus: the System window's Bluetooth section, SUPER+COMMA,
// is the keyboard path.
BarWidget {
    id: widget

    readonly property var power: shell === null ? null : Logic.publishedPower(shell.status.values)
    readonly property int connected: Bluetooth.devices.values.filter(d => d.connected).length
    readonly property var view: Logic.barView(power, connected, setting("hideWhenOff", false) === true)

    visible: view.shown
    implicitWidth: view.shown ? button.implicitWidth : 0
    implicitHeight: barSize

    // Open or close the flyout under this widget; answers the panel host's
    // reply.
    function toggle() {
        const reply = shell.surfaces.toggle("panel", "{}", widget);
        if (reply !== "ok") console.warn("bluetooth widget: panel " + reply);
        return reply;
    }

    BarItem {
        id: button
        anchors.centerIn: parent
        label: "Bluetooth"
        iconName: widget.view.icon
        count: widget.view.count
        tone: widget.bar ? widget.bar.foreground : Theme.bar.foreground
        tooltip: widget.view.tooltip
        onClicked: widget.toggle()
    }
}
