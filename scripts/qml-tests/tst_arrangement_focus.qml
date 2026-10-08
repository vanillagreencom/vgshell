import QtQuick
import QtTest
import qs.Ui
import "../../shell/plugins/vgs.displays" as Displays

Item {
    id: root
    width: 480
    height: 400

    Displays.Arrangement {
        id: canvas
        width: parent.width
        selected: "fixture"
    }
    Button { id: next; y: 300; text: "Next" }
    SignalSpy { id: moves; target: canvas; signalName: "moved" }

    TestCase {
        name: "arrangement_focus"
        when: windowShown

        function ring() { return canvas.children.find(child => String(child).indexOf("FocusRing") === 0); }
        function init() { moves.clear(); canvas.forceActiveFocus(Qt.OtherFocusReason); canvas.focusReason = Qt.OtherFocusReason; }

        function test_initial_focus_has_no_ring_and_tab_shows_it() {
            compare(canvas.activeFocus, true);
            compare(ring().visible, false);
            keyClick(Qt.Key_Tab);
            compare(next.activeFocus, true);
            keyClick(Qt.Key_Backtab);
            compare(canvas.activeFocus, true);
            compare(ring().visible, true);
            compare(moves.count, 0);
        }

        function test_arrow_navigation_shows_the_ring() {
            compare(ring().visible, false);
            keyClick(Qt.Key_Right);
            compare(ring().visible, true);
            compare(moves.count, 1);
        }
    }
}
