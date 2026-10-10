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
    frameActions: [{ label: "Voxtype Settings", icon: "sliders-horizontal", action: root.configure }]

    // The service owns dictation: the click asks it for the toggle its keys
    // run, and never starts a recording itself. `busy` is a toggle the
    // service holds until the one in flight ends. Without voxtype the
    // service starts none, and the click is the Settings page's Set up
    // press: the setup entry's action, whose notice installs what is
    // missing and then opens Set up, and which no earlier Not now holds back.
    function toggle() {
        const reply = shell.ipc.call("toggle", "");
        if (reply === "refused: voxtype=missing") {
            const setup = shell.status.act("setup");
            if (setup !== "ok") console.warn("voice: setup " + setup);
        } else if (reply !== "ok" && reply !== "busy") {
            console.warn("voice: toggle " + reply);
        }
        return reply;
    }

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
        onClicked: root.toggle()
    }
}
