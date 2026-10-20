import QtQuick
import qs.Commons
import qs.Ui
import "VpnLogic.js" as Logic

// Saved profile state supplies the shield. The icon hides while the
// backend is unavailable or no profile is saved; its placement stays.
BarWidget {
    id: widget

    readonly property var view: Logic.barView(shell === null ? null : shell.status.values.profiles || null)

    visible: view.shown
    implicitWidth: view.shown ? button.implicitWidth : 0
    implicitHeight: barSize

    BarItem {
        id: button
        anchors.centerIn: parent
        label: "VPN"
        iconName: widget.view.icon
        tone: widget.bar ? widget.bar.foreground : Theme.bar.foreground
        tooltip: widget.view.tooltip
        onClicked: {
            const reply = widget.shell.surfaces.toggle("panel", "{}", widget);
            if (reply !== "ok") console.warn("vpn widget: panel " + reply);
        }
    }
}
