import QtQuick
import Quickshell.Io
import qs.Commons
import "ScreensaverLogic.js" as Logic

Item {
    id: root

    property var shell: null
    property var screen: null
    property string artPath: Logic.fileUrlPath(Qt.resolvedUrl("logo.txt"))
    property string pendingFrame: ""
    property var frameState: Logic.createState()
    property var exitState: Logic.createExitState()
    property real effectStartedAt: 0
    property bool intentionalStop: false
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
        clearRows();
        pendingFrame = "";
        exitState = Logic.createExitState();
        intentionalStop = false;
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
    onWidthChanged: if (shown) restartDelay.restart()
    onHeightChanged: if (shown) restartDelay.restart()
    onArtPathChanged: restart()
    onBackgroundChanged: restart()

    function stop() {
        if (shell !== null) shell.ipc.call("stop", "");
    }

    function start() {
        if (!shown || !canRun || effect.running) return;
        if (width <= 0 || height <= 0) return;
        intentionalStop = false;
        effect.command = Logic.command(artPath, selectedEffect, frameRate, canvas.columns, canvas.rows, background);
        console.info("screensaver: command=" + JSON.stringify(effect.command));
        effect.running = true;
    }

    function stopProcess() {
        restartDelay.stop();
        if (effect.running) {
            intentionalStop = true;
            effect.running = false;
        }
    }

    function effectFailed() {
        restartDelay.stop();
        if (shell !== null) shell.ipc.call("effect-failed", "");
    }

    function restart() {
        if (!shown) return;
        stopProcess();
        restartDelay.restart();
    }

    function receiveFrame(frame) {
        pendingFrame = Logic.newestFrame(pendingFrame, frame);
    }

    function clearRows() {
        frameState = Logic.createState();
        for (let i = 0; i < lineRepeater.count; i++) {
            const item = lineRepeater.itemAt(i);
            if (item !== null) item.text = "";
        }
    }

    function setRows(nextRows) {
        for (let i = 0; i < lineRepeater.count; i++) {
            const item = lineRepeater.itemAt(i);
            if (item === null) continue;
            const next = nextRows[i] || "";
            if (item.text !== next) item.text = next;
        }
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
        font.pixelSize: Theme.text.display.size
    }

    TextMetrics {
        id: cellSize
        font.family: Theme.font.family.mono
        font.pixelSize: Theme.text.display.size
        text: "M"
    }

    Process {
        id: effect
        stdout: SplitParser {
            splitMarker: "\u001b8"
            onRead: frame => root.receiveFrame(frame)
        }
        stderr: SplitParser { onRead: line => console.warn("screensaver: ttfx " + line) }
        onRunningChanged: {
            if (running) {
                root.effectStartedAt = Date.now();
                return;
            }
            if (root.intentionalStop) {
                root.intentionalStop = false;
                return;
            }
            if (!root.shown) return;
            if (Logic.effectExitAction(root.effectStartedAt, Date.now(), root.exitState) === "fail") root.effectFailed();
            else restartDelay.restart();
        }
    }

    Timer {
        id: restartDelay
        interval: 250
        onTriggered: root.start()
    }

    Timer {
        interval: 100
        repeat: true
        running: root.shown && !root.activeFocus
        onTriggered: root.forceActiveFocus(Qt.ActiveWindowFocusReason)
    }

    Timer {
        interval: Math.max(16, Math.round(1000 / root.frameRate))
        repeat: true
        running: root.shown
        onTriggered: {
            if (root.pendingFrame === "") return;
            const parsed = Logic.parseFrame(root.pendingFrame, root.frameState);
            root.pendingFrame = "";
            root.frameState = parsed;
            if (parsed.rows.length === 0) return;
            root.setRows(parsed.rows);
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
            id: lineRepeater
            model: root.canvas.rows
            Text {
                textFormat: Text.StyledText
                text: ""
                color: Theme.color.text
                font.family: Theme.font.family.mono
                font.pixelSize: Theme.text.display.size
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
