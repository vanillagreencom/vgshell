import QtQuick
import qs.Commons
import qs.Ui

// System → Sound: the section the panes holder mounts. It is a body alone,
// from x 0, its height its implicitHeight; the holder draws its title,
// inset and scrolling. It draws SoundControls with the input's level meter,
// which listens to PipeWire only while the pane is open, and the
// playing-apps line. The holder builds it when shown and destroys it on a
// switch or close; it takes no payload keys and opens with the keyboard on
// the output's device.
FocusScope {
    id: root

    // The core assigns the plugin's scoped shell object after creation, and
    // again when the plugin's settings change.
    property var shell: null
    readonly property Item initialFocus: controls.firstFocus
    property bool opened: false

    function open(payloadJson) {
        opened = true;
    }

    function close() {
        opened = false;
    }

    implicitWidth: Theme.size.window.width
    implicitHeight: controls.implicitHeight
    focus: true

    Audio { id: audio }

    SoundControls {
        id: controls
        width: root.width
        shell: root.shell
        audio: audio
        meter: root.opened
    }
}
