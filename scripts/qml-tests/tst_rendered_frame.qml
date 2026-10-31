import QtQuick
import QtTest
import qs.Unit

// The rendered-frame wait every unit test shares (UnitCase.renderedFrame).
// QtTest's waitForRendering waits for the window's next frame swap and a
// window with its state drawn schedules none, so the bare wait reports a
// settled window as not rendered; the shared wait asks for the frame first
// and still answers. This file calls the bare wait on purpose, the one
// call scripts/qml-unit.sh excuses, to find the window settled.
Item {
    width: 200
    height: 200

    Rectangle {
        id: drawn
        anchors.fill: parent
        color: "red"
    }

    UnitCase {
        name: "rendered_frame"
        when: windowShown

        function test_the_rendered_wait_answers_on_a_settled_window() {
            let settled = false;
            const until = Date.now() + 10000;
            while (!settled && Date.now() < until) settled = !waitForRendering(drawn, 50);
            verify(settled, "the window stops swapping frames once its state is drawn");
            verify(renderedFrame(drawn, 1000), "a settled window draws the frame it is asked for");
        }
    }
}
