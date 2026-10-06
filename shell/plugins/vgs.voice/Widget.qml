import QtQuick
import qs.Commons
import qs.Ui
import "Appearance.js" as Appearance

BarWidget {
    id: root

    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
    readonly property var value: shell === null || shell.status.values.dictation === undefined ? null : shell.status.values.dictation
    readonly property string dictation: value === null ? "idle" : String(value.text)
    readonly property bool recording: dictation === "recording"
    readonly property bool transcribing: dictation === "transcribing"
    readonly property bool stopped: dictation === "stopped"
    readonly property color itemTone: recording ? look.palette.accent : root.bar ? root.bar.foreground : "transparent"

    implicitWidth: item.implicitWidth
    implicitHeight: barSize

    function configure() {
        const reply = shell.tui.run("configure");
        if (reply !== "ok") console.warn("voice: configure " + reply);
        return reply;
    }

    BarItem {
        id: item
        anchors.centerIn: parent
        label: "Voice"
        iconName: "mic"
        active: root.recording || root.transcribing
        spinning: root.transcribing
        tone: root.itemTone
        tooltip: root.recording ? "Recording" : root.transcribing ? "Transcribing" : root.stopped ? "Voice stopped" : "Voice"
        onClicked: root.configure()
    }
}
