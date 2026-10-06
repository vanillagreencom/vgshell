import QtQuick
import qs.Commons
import qs.Ui

// The Sound flyout under the bar widget: the output's device and volume,
// the input's, one volume per app that plays (SoundControls), and a footer
// whose Sound settings opens System on this plugin's pane through
// own-pane summon and closes the flyout. The playing-apps line draws here
// only while it offers pactl. It is built on summon, destroyed on hide,
// takes no payload, and opens with the keyboard on the output's device.
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation, and
    // again when the plugin's settings change.
    property var shell: null
    property Item initialFocus: controls.firstFocus

    function open(payloadJson) {}
    function close() {}

    // Open System on the Sound pane and close the flyout; answers the
    // panes holder's reply.
    function openSettings() {
        const reply = shell.surfaces.summon("pane", "{}");
        if (reply !== "ok") {
            console.warn("sound panel: pane " + reply);
            controls.problem = "System Settings is not available. Turn it on in Plugins.";
            return reply;
        }
        shell.surfaces.hide("panel");
        return reply;
    }

    implicitWidth: Theme.size.panel.lg
    implicitHeight: layout.implicitHeight

    Surface {
        anchors.fill: parent
    }

    Audio { id: audio }

    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight
        title: "Sound"

        SoundControls {
            id: controls
            width: layout.contentWidth
            shell: root.shell
            audio: audio
            streamsLine: false
        }

        footer: [
            Button {
                text: "Sound settings"
                variant: "secondary"
                onClicked: root.openSettings()
            }
        ]
    }
}
