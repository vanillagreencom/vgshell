import QtQuick
import qs.Ui

// The launcher's bar entry: a magnifier in the bar's own colour, drawn as
// the shared BarItem so it matches the bar's other entries whatever the
// launcher's own look. A click opens or closes the launcher on this bar's
// screen; the right-click menu adds Open terminal after Hide.
BarWidget {
    id: root

    implicitWidth: item.implicitWidth
    implicitHeight: barSize
    frameActions: [{ label: "Open terminal", icon: "terminal", action: root.openTerminal }]

    function open() {
        if (root.shell === null) return;
        const reply = root.shell.surfaces.toggle("overlay", "{}");
        if (reply !== "ok") console.warn("launcher: bar entry " + reply);
    }

    function openTerminal() {
        if (root.shell === null) return;
        const reply = root.shell.run.detached(["xdg-terminal-exec"]);
        if (reply !== "ok") console.warn("launcher: bar entry " + reply);
    }

    BarItem {
        id: item
        anchors.centerIn: parent
        label: "Launcher"
        iconName: "search"
        tone: root.bar ? root.bar.foreground : "transparent"
        onClicked: root.open()
    }
}
