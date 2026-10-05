import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
    id: root

    readonly property var value: shell === null || shell.status.values.dictation === undefined ? null : shell.status.values.dictation
    readonly property string dictation: value === null ? "idle" : String(value.text)
    readonly property bool recording: dictation === "recording"
    readonly property bool transcribing: dictation === "transcribing"
    readonly property string shortcut: shell !== null && shell.shortcut !== undefined && shell.shortcut.keys !== undefined
        ? (shell.shortcut.keys.toggle || "")
        : ""
    readonly property color itemTone: recording ? Theme.badge.tone.accent.foreground : root.bar ? root.bar.foreground : Theme.bar.foreground

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
        tooltip: root.recording ? "Recording" : root.transcribing ? "Transcribing" : "Voice"
        shortcut: root.shortcut
        onClicked: root.configure()
    }
}
