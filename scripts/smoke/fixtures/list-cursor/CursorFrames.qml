import QtQuick

// The frames a list's cursor draws, for rows/list-motion.sh: built inside a
// surface's instance by the probe's popupLoad with `host` that instance,
// `start()` takes the first ListCursor under `host` whose ancestors all
// show and records, from then on, the wall time and the cursor's y at each
// change of y and before each scene synchronization, and the wall time,
// row text and starting y at each selection change. `moves`, `frames` and
// `targets` read them, in milliseconds since the epoch.
Item {
    id: root
    property Item host: null
    property Item plate: null
    property var moves: []
    property var frames: []
    property var targets: []
    property int ceilingMs: 0
    property real elapsed: 0

    function start() {
        plate = find();
        moves = [];
        frames = [];
        targets = [];
        tick.stop();
        elapsed = 0;
    }

    function shown(item) {
        for (let at = item.parent; at !== null && at !== host; at = at.parent)
            if (!at.visible) return false;
        return true;
    }

    // A ListCursor by its members, since this file loads outside qs.Ui.
    function find() {
        const queue = [host];
        for (let i = 0; i < queue.length; i++) {
            const item = queue[i];
            if (item.follow !== undefined && item.hoverTakes !== undefined && item.snap !== undefined && shown(item)) return item;
            for (const child of item.children) queue.push(child);
        }
        return null;
    }

    // This clock shares Qt's animation ticks with the plate, independently
    // of y. The first drawn tick at the ceiling must show the plate at rest;
    // a host gap without a frame cannot count as a stationary plate.
    // https://doc.qt.io/qt-6/animation-overview.html#the-animation-architecture
    NumberAnimation { id: tick; target: root; property: "elapsed"; from: 0; to: root.ceilingMs; duration: root.ceilingMs }

    Connections {
        target: plate
        function onYChanged() { moves.push([Date.now(), plate.y]); }
        function onTargetChanged() {
            if (targets.length === 0) tick.restart();
            targets.push([Date.now(), plate.target === null ? "" : String(plate.target.text), plate.y]);
        }
    }
    Connections {
        target: plate === null ? null : plate.Window.window
        // Qt emits afterAnimating on the GUI thread before scene sync.
        // frameSwapped is emitted on the render thread: its queued QML
        // handler can read y from a later animation tick.
        // https://doc.qt.io/qt-6/qquickwindow.html#afterAnimating
        function onAfterAnimating() { frames.push([Date.now(), plate.y, targets.length, root.elapsed]); }
    }
}
