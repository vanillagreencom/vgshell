import QtQuick
import QtQuick.Window
import QtTest
import qs.Ui
import qs.Unit

// A scrolled area keeps its place when its window loses the focus and
// gets it back, as on a desktop switch: neither a focused list scope
// taller than the view, as a Settings page's TabPages is, nor a focused
// row inside it moves the view. Nor does the focus that falls back to that
// scope when the focused row leaves. An area hidden while its window is
// away, as a retained flyout closes, starts its list scope at the top when
// the focus comes back. tst_scroll.qml holds the first focus entry into
// such a scope, which starts it at the top.
Item {
    id: root
    width: 300
    height: 300

    ScrollArea {
        id: area
        width: 200
        height: 100

        Column {
            width: parent.width
            Item { width: 1; height: 40 }
            FocusScope {
                id: list
                width: parent.width
                height: 600
                Button { id: row; y: 20; text: "Row" }
                // A row that leaves while it holds the focus, as a list's
                // row does when its item is removed.
                Repeater {
                    id: leaving
                    model: 0
                    Button { y: 400; text: "Leaving" }
                }
            }
        }
    }

    // The window the focus goes to while the test's window is away.
    Window { id: other; width: 50; height: 50 }

    UnitCase {
        name: "scroll_refocus"
        when: windowShown

        // The test window's focus goes to another window and comes back.
        // The offscreen platform reads both windows active throughout, so
        // the wait is on TARGET's focus: Qt clears the window's
        // activeFocusItem as it loses the focus and hands it back to the
        // same item as it gets it again (qmltestrunner, Qt 6.12, 2026-11-19).
        function switchAway(target) {
            other.show();
            other.requestActivate();
            tryCompare(target, "activeFocus", false);
            other.hide();
            root.Window.window.requestActivate();
            tryCompare(target, "activeFocus", true);
        }

        function init() {
            row.focus = false;
            leaving.model = 0;
            area.contentY = 0;
            root.Window.window.requestActivate();
        }

        function test_a_window_that_gets_the_focus_back_keeps_the_scroll_place_data() {
            return [
                { tag: "the list scope", target: () => list },
                { tag: "a row inside it", target: () => row }
            ];
        }

        function test_a_window_that_gets_the_focus_back_keeps_the_scroll_place(data) {
            const target = data.target();
            target.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(target, "activeFocus", true);
            // The row lies above the view from here.
            area.contentY = 300;
            switchAway(target);
            compare(area.contentY, 300, "the view stays where it was scrolled");
        }

        function test_an_area_hidden_while_away_starts_its_list_at_the_top_again() {
            list.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(list, "activeFocus", true);
            area.contentY = 300;
            other.show();
            other.requestActivate();
            tryCompare(list, "activeFocus", false);
            area.visible = false;
            area.visible = true;
            other.hide();
            root.Window.window.requestActivate();
            tryCompare(list, "activeFocus", true);
            compare(area.contentY, 0, "the shown list starts at the top");
        }

        function test_the_focus_that_falls_back_from_a_leaving_row_keeps_the_scroll_place() {
            leaving.model = 1;
            const gone = leaving.itemAt(0);
            gone.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(gone, "activeFocus", true);
            area.contentY = 300;
            leaving.model = 0;
            tryCompare(list, "activeFocus", true);
            compare(area.contentY, 300, "the view stays where it was scrolled");
        }
    }
}
