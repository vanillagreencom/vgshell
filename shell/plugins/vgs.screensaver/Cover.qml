import QtQuick
import Quickshell.Io
import qs.Commons
import "ScreensaverLogic.js" as Logic

Item {
    id: root

    property var shell: null
    property var screen: null
    property string artPath: Logic.fileUrlPath(Qt.resolvedUrl("logo.txt"))
    property var rows: []
    property var pendingRows: null
    property bool focusReady: false
    property bool pointerReady: false
    property real firstX: 0
    property real firstY: 0

    readonly property bool shown: shell !== null && shell.status.values.state !== undefined && shell.status.values.state.text === "Running" && !(shell.session.locked)
    readonly property bool canRun: shell !== null && shell.requirements.missing.indexOf("ttfx") === -1
    readonly property int frameRate: shell === null || shell.settings.frameRate === undefined ? 30 : shell.settings.frameRate
    readonly property string selectedEffect: shell === null ? "random" : shell.settings.effect
    readonly property int cellWidth: Math.max(1, Math.ceil(cellSize.width))
    readonly property int cellHeight: Math.max(1, Math.ceil(fontMetrics.height))
    readonly property var canvas: Logic.canvasSize(width, height, cellWidth, cellHeight)
    readonly property string background: Logic.backgroundHex(Theme.color.background)

    focus: shown
    Keys.onPressed: event => {
        event.accepted = true;
        stop();
    }

    onShownChanged: {
        pointerReady = false;
        focusReady = false;
        rows = [];
        pendingRows = null;
        if (shown) Qt.callLater(() => {
            root.forceActiveFocus(Qt.ActiveWindowFocusReason);
            start();
        });
        else stopProcess();
    }
    onCanRunChanged: if (shown) start()
    onSelectedEffectChanged: restart()
    onFrameRateChanged: restart()
    onCanvasChanged: restart()
    onArtPathChanged: restart()
    onBackgroundChanged: restart()
    onActiveFocusChanged: {
        if (activeFocus) focusReady = true;
        else if (shown && focusReady) stop();
    }

    function stop() {
        if (shell !== null) shell.ipc.call("stop", "");
    }

    function start() {
        if (!shown || !canRun || effect.running) return;
        effect.command = Logic.command(artPath, selectedEffect, frameRate, canvas.columns, canvas.rows, background);
        effect.running = true;
    }

    function stopProcess() {
        restartDelay.stop();
        if (effect.running) effect.running = false;
    }

    function restart() {
        if (!shown) return;
        stopProcess();
        restartDelay.restart();
    }

    function receiveFrame(frame) {
        const parsed = Logic.parseFrame(frame);
        if (parsed.length === 0) return;
        pendingRows = Logic.newestFrame(pendingRows, parsed);
    }

    FileView {
        id: configuredArt
        path: Paths.configDir + "/screensaver.txt"
        watchChanges: true
        printErrors: false
        onLoaded: root.artPath = path
        onLoadFailed: error => root.artPath = Logic.fileUrlPath(Qt.resolvedUrl("logo.txt"))
        onFileChanged: reload()
    }

    FontMetrics {
        id: fontMetrics
        font.family: Theme.font.family.mono
        font.pixelSize: Theme.text.code.size
    }

    TextMetrics {
        id: cellSize
        font.family: Theme.font.family.mono
        font.pixelSize: Theme.text.code.size
        text: "M"
    }

    Process {
        id: effect
        stdout: SplitParser {
            splitMarker: "\u001b8"
            onRead: frame => root.receiveFrame(frame)
        }
        stderr: SplitParser { onRead: line => console.warn("screensaver: ttfx " + line) }
        onRunningChanged: if (!running && root.shown) restartDelay.restart()
    }

    Timer {
        id: restartDelay
        interval: 250
        onTriggered: root.start()
    }

    FrameAnimation {
        running: root.pendingRows !== null && root.shown
        onTriggered: {
            root.rows = root.pendingRows;
            root.pendingRows = null;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
    }

    Column {
        anchors.centerIn: parent
        spacing: 0
        Repeater {
            model: root.rows
            Text {
                textFormat: Text.StyledText
                text: modelData
                color: Theme.color.text
                font.family: Theme.font.family.mono
                font.pixelSize: Theme.text.code.size
                lineHeightMode: Text.FixedHeight
                lineHeight: root.cellHeight
            }
        }
    }

    // pointer-cursor-exempt: the whole cover dismisses the screensaver and hides the cursor, not a control
    // keyboard-path: any key dismisses the cover
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        cursorShape: Qt.BlankCursor
        onPressed: mouse => {
            mouse.accepted = true;
            root.stop();
        }
        onPositionChanged: mouse => {
            if (!root.shown) return;
            if (!root.pointerReady) {
                root.firstX = mouse.x;
                root.firstY = mouse.y;
                root.pointerReady = true;
                return;
            }
            const dx = mouse.x - root.firstX;
            const dy = mouse.y - root.firstY;
            if (dx * dx + dy * dy > 16) root.stop();
        }
    }
}
