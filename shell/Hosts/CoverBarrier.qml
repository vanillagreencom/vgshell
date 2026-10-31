import QtQuick

// The input barrier over one lock surface while the secure cover shows. It
// holds the keyboard and takes every pointer event, and the first real
// movement, press, scroll or key reports `consumed` and goes no further:
// LockHost builds the lock content only after that, so the event never
// reaches the password field or the desktop. A surface that maps under a
// resting pointer receives the pointer's position, so movement counts once
// the pointer has gone more than four pixels from where it entered, as the
// desktop cover's dismissal does.
FocusScope {
    id: barrier

    property bool up: false
    signal consumed(string cause)

    property bool ready: false
    property real firstX: 0
    property real firstY: 0

    enabled: up
    visible: up
    focus: up
    onUpChanged: {
        ready = false;
        if (up) forceActiveFocus();
    }
    // A lock surface built while the cover is already held raises its
    // barrier from the start.
    Component.onCompleted: if (up) forceActiveFocus()

    function consume(cause) {
        if (up) consumed(cause);
    }

    Keys.onPressed: event => {
        event.accepted = true;
        barrier.consume("key");
    }

    // pointer-cursor-exempt: the barrier hides the cursor over the cover, not a control
    // keyboard-path: any key ends the cover through the barrier's own Keys handler
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        cursorShape: Qt.BlankCursor
        onEntered: {
            barrier.firstX = mouseX;
            barrier.firstY = mouseY;
            barrier.ready = true;
        }
        onPressed: mouse => {
            mouse.accepted = true;
            barrier.consume("click");
        }
        onWheel: wheel => {
            wheel.accepted = true;
            barrier.consume("scroll");
        }
        onPositionChanged: mouse => {
            if (!barrier.ready) {
                barrier.firstX = mouse.x;
                barrier.firstY = mouse.y;
                barrier.ready = true;
                return;
            }
            const dx = mouse.x - barrier.firstX;
            const dy = mouse.y - barrier.firstY;
            if (dx * dx + dy * dy > 16) barrier.consume("move");
        }
    }
}
