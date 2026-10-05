import QtQuick
import qs.Commons
import qs.Ui
import "Appearance.js" as Appearance

// Voice's on-screen display, one copy per screen in the plugin's passive
// layer: the plasma orb or the VGS voice ring at the bottom centre, mapped
// only on the focused screen while voxtype records or transcribes. Its input
// list is empty, so every press reaches the window below, and the layer takes
// no key, so dictated text keeps going to the focused field.
Item {
    id: root

    // The core assigns the copy's screen; the service owns what it shows.
    property var screen: null
    property var service: null
    property var inputItems: []
    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
    readonly property string mode: service === null ? "off" : service.osdMode
    readonly property bool shown: service !== null && service.osdActive && screen !== null && screen.name === service.focusedOutput
    readonly property bool recording: service !== null && service.dictation === "recording"
    readonly property bool transcribing: service !== null && service.dictation === "transcribing"
    // The ring's breathing level while the words are transcribed.
    property real breath: look.pulse.low

    Plasma {
        id: plasma
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.look.osd.margin
        visible: root.mode === "plasma"
        active: root.shown && visible
        transcribing: root.transcribing
    }

    VoiceOrb {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.look.osd.margin
        visible: root.mode === "ring"
        active: root.shown && visible && root.recording
        level: root.transcribing ? root.breath : root.service === null ? 0 : root.service.level
    }

    SequentialAnimation {
        running: root.shown && root.mode === "ring" && root.transcribing && root.look.pulse.period > 0
        loops: Animation.Infinite
        onStopped: root.breath = root.look.pulse.low
        NumberAnimation {
            target: root
            property: "breath"
            to: root.look.pulse.high
            duration: root.look.pulse.period / 2
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "breath"
            to: root.look.pulse.low
            duration: root.look.pulse.period / 2
            easing.type: Easing.InOutSine
        }
    }

    // Only the shown copy takes the bridge's frames.
    Connections {
        target: root.service
        enabled: root.shown
        function onFrame(level) { plasma.push(level); }
        function onBridgeDisconnected() { plasma.reset(); }
    }
}
