import QtQuick

// The frames a list's cursor draws, for rows/list-motion.sh: built inside a
// surface's instance by the probe's popupLoad with `host` that instance,
// `start()` takes the first ListCursor under `host` whose ancestors all
// show and records, from then on, the wall time and the cursor's y at each
// change of y and at each frame its window swaps, and the wall time and
// row text at each change of the row that holds the selection. `moves`,
// `frames` and `targets` read them, in milliseconds since the epoch.
Item {
    property Item host: null
    property Item plate: null
    property var moves: []
    property var frames: []
    property var targets: []

    function start() {
        plate = find();
        moves = [];
        frames = [];
        targets = [];
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

    Connections {
        target: plate
        function onYChanged() { moves.push([Date.now(), plate.y]); }
        function onTargetChanged() { targets.push([Date.now(), plate.target === null ? "" : String(plate.target.text)]); }
    }
    Connections {
        target: plate === null ? null : plate.Window.window
        function onFrameSwapped() { frames.push([Date.now(), plate.y]); }
    }
}
