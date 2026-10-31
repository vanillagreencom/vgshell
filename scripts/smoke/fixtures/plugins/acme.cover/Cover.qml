import QtQuick
import Quickshell.Io

// The fixture's cover: while its presentation is active it runs one
// renderer, a shell loop that prints a numbered frame for each line written
// to it, and draws the last frame beside a planted magenta square at
// (100, 100). `identity` is stamped once per instance, so a reader can tell
// one instance from a rebuilt one; `inputs` counts the pointer and key
// events the cover itself received while held in the lock.
Item {
    id: root

    property var shell: null
    property var screen: null
    property var presentation: null
    readonly property bool active: presentation !== null && presentation.active
    readonly property bool held: active && presentation.placement === "secure"
    property string identity: ""
    property string frame: ""
    property var rendererPid: null
    property int rendererStarts: 0
    property int inputs: 0

    Component.onCompleted: identity = "cover-" + Math.floor(Math.random() * 1e9)
    onActiveChanged: if (!active) frame = ""

    function advance() {
        renderer.write("\n");
        return "ok";
    }

    focus: active && presentation.placement === "desktop"
    Keys.onPressed: event => { if (root.held) root.inputs += 1; }

    Process {
        id: renderer
        running: root.active
        stdinEnabled: true
        command: ["sh", "-c", "i=0; while :; do i=$((i+1)); echo frame-$i; read -r _ || exit 0; done"]
        stdout: SplitParser { onRead: data => { root.frame = data; } }
        onStarted: {
            root.rendererStarts += 1;
            root.rendererPid = processId;
        }
        onRunningChanged: if (!running) root.rendererPid = null
    }

    Rectangle { anchors.fill: parent; color: "#000000" }
    Rectangle { x: 100; y: 100; width: 60; height: 60; color: "#ff00ff" }
    Text {
        anchors.centerIn: parent
        text: root.frame
        color: "#ffffff"
        font.pixelSize: 48
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onPositionChanged: if (root.held) root.inputs += 1
        onPressed: if (root.held) root.inputs += 1
    }
}
