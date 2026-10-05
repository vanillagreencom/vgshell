import QtQuick
import qs.Commons
import qs.Ui
import "VpnLogic.js" as Logic

// The VPN icon in the bar: connected, off, or an exit node in use, as
// VpnLogic.barView decides from the `vpn` value the service publishes. It
// starts no process. A click opens or closes the flyout under it. It is
// hidden while Tailscale is not installed and stays placed. The bar takes
// no keyboard focus: the System window's VPN section is the keyboard path.
BarWidget {
    id: widget

    readonly property var view: Logic.barView(shell === null ? null : shell.status.values.vpn || null)

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
