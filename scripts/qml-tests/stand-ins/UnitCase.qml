import QtQuick
import QtTest

// The TestCase of a unit test that waits for the window to draw. QtTest's
// waitForRendering waits for the window's next frame swap, and a window
// whose requested state is already drawn schedules none, so the bare wait
// fails on a settled window under host load with no product change.
// renderedFrame asks the window for the frame first, so the wait answers on
// whether the window draws. scripts/qml-unit.sh refuses a test file that
// calls waitForRendering itself.
TestCase {
    // True when ITEM's window drew a frame within TIMEOUT milliseconds
    // (QtTest's default when omitted).
    function renderedFrame(item, timeout) {
        const window = item.Window.window;
        if (window)
            window.update();
        return waitForRendering(item, timeout);
    }
}
