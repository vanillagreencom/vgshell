import QtQuick
import qs.Commons
import qs.Ui
import "VpnLogic.js" as Logic

// The VPN shield in the bar, as VpnLogic.barView decides from the
// `profiles` value the service publishes: a spinner while a profile
// connects or disconnects, the warning shield while a profile needs its
// password or could not connect, else connected or off. It hides while
// NetworkManager is unavailable or no profile is saved, and keeps its
// placement. A click opens or closes the flyout under it.
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
        spinning: widget.view.spinning
        spinnerColor: widget.bar ? widget.bar.foreground : Theme.bar.foreground
        tone: widget.view.warning ? Theme.color.warning : widget.bar ? widget.bar.foreground : Theme.bar.foreground
        tooltip: widget.view.tooltip
        onClicked: {
            const reply = widget.shell.surfaces.toggle("panel", "{}", widget);
            if (reply !== "ok") console.warn("vpn widget: panel " + reply);
        }
    }
}
