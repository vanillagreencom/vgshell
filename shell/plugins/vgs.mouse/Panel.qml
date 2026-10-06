import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root

    property var shell: null
    property Item initialFocus: controls.firstFocus

    function open(payloadJson) {}
    function close() {}

    function openSettings() {
        const reply = shell.surfaces.summon("pane", "{}");
        if (reply !== "ok") {
            controls.problem = "System is not available. Turn it on in Plugins.";
            console.warn("mouse panel: pane " + reply);
            return reply;
        }
        shell.surfaces.hide("panel");
        return reply;
    }

    implicitWidth: Theme.size.panel.md
    implicitHeight: layout.implicitHeight

    Surface { anchors.fill: parent }

    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight

        header: [
            Label { role: "h3"; text: "Mouse" }
        ]

        MouseControls {
            id: controls
            width: layout.contentWidth
            shell: root.shell
            compact: true
        }

        footer: [
            Button {
                width: layout.contentWidth
                variant: "tertiary"
                text: "Mouse Settings"
                iconName: "settings"
                onClicked: root.openSettings()
            }
        ]
    }
}
