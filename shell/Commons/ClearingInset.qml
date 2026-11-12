import QtQuick

QtObject {
    id: insetter

    property real pad: 0
    // The box gap ends at ink, not at a text item's leading. Separate
    // edge items let a Pane keep its header and sticky footer independent.
    property Item content: null
    property Item endContent: content
    readonly property real topPadding: pad - Math.floor(topInk)
    readonly property real bottomPadding: pad - Math.floor(bottomInk)
    property real topInk: 0
    property real bottomInk: 0
    readonly property real observedTopInk: alive ? Theme.inkAbove(content) : 0
    readonly property real observedBottomInk: alive ? Theme.inkBelow(endContent) : 0
    property real radius: 0
    property real width: 0
    property real height: 0
    property real step: Theme.inset.cornerStep
    // How far the content's top edge stands in from the container's.
    property real top: 0
    property real inset: pad
    property bool settlePending: false
    property bool alive: true

    // Ink can read a child's assigned geometry, which reads these paddings
    // through Pane.bodyRoom. Observe it reactively, but publish it outside
    // that binding evaluation, just as wrapping and corner clearing settle.
    // Qt.callLater coalesces the updates until control returns to the loop:
    // https://doc.qt.io/qt-6/qml-qtqml-qt.html#callLater-method
    function reset() {
        inset = pad;
        scheduleSettle();
    }

    function targetInset() {
        return Math.ceil(Inset.clearing(pad, radius, width, height, step, top));
    }

    function scheduleSettle() {
        if (settlePending || !alive) return;
        settlePending = true;
        Qt.callLater(settle);
    }

    function settle() {
        // Qt.callLater can run while the owner is being destroyed.
        if (!alive) return;
        settlePending = false;
        topInk = observedTopInk;
        bottomInk = observedBottomInk;
        const next = targetInset();
        if (Math.abs(inset - next) <= 0.01) return;
        inset = next;
        scheduleSettle();
    }

    Component.onCompleted: settle()
    Component.onDestruction: alive = false
    onPadChanged: reset()
    onRadiusChanged: reset()
    onWidthChanged: reset()
    onHeightChanged: scheduleSettle()
    onStepChanged: reset()
    onTopChanged: reset()
    onObservedTopInkChanged: scheduleSettle()
    onObservedBottomInkChanged: scheduleSettle()
}
