import QtQuick
import qs.Commons
import qs.Ui
import "Remote.js" as Remote

// The red remote session indicator, after Omarchy's RemoteSession.qml,
// with who is viewing on hover. Idle, it draws nothing and takes no room.
// A click opens System Settings › Remote desktop, the keyboard path, since
// the bar takes no keyboard focus.
BarWidget {
    id: widget

    readonly property var session: shell === null || shell.status.values.session === undefined ? null : shell.status.values.session
    readonly property bool shown: session !== null && session.active === true
    readonly property var tip: shown ? Remote.tooltip(session) : ({ title: "", details: [] })

    visible: shown
    implicitWidth: shown ? item.implicitWidth : 0
    implicitHeight: barSize

    BarItem {
        id: item
        anchors.centerIn: parent
        iconName: "screen-share"
        tone: Theme.color.danger
        label: widget.tip.title
        tooltip: widget.tip.title
        tooltipDetails: widget.tip.details
        onClicked: {
            const reply = widget.shell.surfaces.summon("pane", "{}");
            if (reply !== "ok") console.warn("remote-desktop widget: pane " + reply);
        }
    }
}
