import QtQuick
import qs.Commons
import qs.Ui

// The Plugins plug in the bar: a click opens or closes the Plugins
// window. Hyprland maps a new window on the focused monitor, and the
// pointer on this bar has made its screen the focused one.
BarWidget {
    id: root

    implicitWidth: button.implicitWidth
    implicitHeight: barSize

    // Open or close the Plugins window; answers the window host's reply.
    function toggle() {
        const reply = shell.surfaces.toggle("window", "{}");
        if (reply !== "ok") console.warn("settings: plug " + reply);
        return reply;
    }

    BarItem {
        id: button
        anchors.centerIn: parent
        iconName: "plug"
        label: "Plugins"
        onClicked: root.toggle()
    }
}
