import QtQuick
import qs.Commons
import qs.Ui
import "TailscaleLogic.js" as Logic

// The Tailscale icon in the bar: connected, off, or an exit node in use, as
// TailscaleLogic.barView decides from the `tailscale` value the service publishes,
// with the count of devices connected to this one as its corner badge, as
// TailscaleLogic.inboundBadge reads the `inbound` value. It
// starts no process. A click opens or closes the flyout under it. It is
// hidden while its backend is absent and stays placed. The bar takes
// no keyboard focus: the System window's Tailscale section is the keyboard path.
BarWidget {
    id: widget

    readonly property var view: Logic.barView(shell === null ? null : shell.status.values.tailscale || null)
    readonly property var badge: Logic.inboundBadge(shell === null ? undefined : shell.status.values.inbound)

    visible: view.shown
    implicitWidth: view.shown ? button.implicitWidth : 0
    implicitHeight: barSize

    BarItem {
        id: button
        anchors.centerIn: parent
        label: widget.badge.label
        iconName: widget.view.icon
        count: widget.badge.count
        spinning: widget.view.spinning
        spinnerColor: widget.bar ? widget.bar.foreground : Theme.bar.foreground
        tone: widget.view.warning ? Theme.color.warning : widget.bar ? widget.bar.foreground : Theme.bar.foreground
        tooltip: widget.view.tooltip
        // The tooltip leaves the corner count out (BarItem.qml), so the
        // count's line names it under the connection.
        tooltipDetails: widget.badge.detail === "" ? [] : [widget.badge.detail]
        onClicked: {
            const reply = widget.shell.surfaces.toggle("panel", "{}", widget);
            if (reply !== "ok") console.warn("tailscale widget: panel " + reply);
        }
    }
}
