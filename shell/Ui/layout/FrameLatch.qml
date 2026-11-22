import QtQuick

// One frame after a moment: `arm()` marks the moment, and the latch fires
// `fired()` on the swap of the first frame of `window`
// whose GUI-thread start came after it. A frame already in flight at the
// arm, as one queued before a pane mounts in a shown window, cannot fire it.
// A frame's start is its afterAnimating, emitted on the GUI thread; its
// afterSynchronizing and frameSwapped come from the render thread, queued
// to this one in order, so each start is paired with its sync and swap as
// BarHost pairs them: started frames queue at afterAnimating, the oldest
// leaves at afterSynchronizing, and a swap reads the frame last synced.
// https://doc.qt.io/qt-6/qquickwindow.html#afterAnimating
// https://doc.qt.io/qt-6/qquickwindow.html#frameSwapped
// The signals are followed only while armed; an arm that reconnects starts
// with an empty queue, so a sync whose start it did not see pairs with
// nothing. A frame that syncs no change draws no swap, so a sync replaces
// the frame the last one left. `arm()` asks the window for a frame, so the
// latch fires even when nothing else would draw.
QtObject {
    id: root

    // The QQuickWindow whose frames it follows, such as an item's
    // `Window.window`; null until the item has a window.
    property var window: null
    readonly property bool armed: waiting
    signal fired()

    property bool waiting: false
    property int epoch: 0
    // The arm epoch each started frame saw, oldest first.
    property var started: []
    // The arm epoch of the frame last synced, or -1.
    property int synced: -1

    function arm() {
        if (!waiting) {
            started = [];
            synced = -1;
        }
        epoch++;
        waiting = true;
        if (window !== null) window.update();
    }

    function disarm() {
        waiting = false;
        started = [];
        synced = -1;
    }

    onWindowChanged: {
        started = [];
        synced = -1;
        if (waiting && window !== null) window.update();
    }

    readonly property Connections frames: Connections {
        target: root.waiting ? root.window : null
        function onAfterAnimating() { root.started.push(root.epoch); }
        function onAfterSynchronizing() { root.synced = root.started.length === 0 ? -1 : root.started.shift(); }
        function onFrameSwapped() {
            const drawn = root.synced;
            root.synced = -1;
            if (drawn !== root.epoch || !root.waiting) return;
            root.waiting = false;
            root.started = [];
            root.fired();
        }
    }
}
