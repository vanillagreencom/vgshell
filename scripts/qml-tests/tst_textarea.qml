import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

Item {
    id: root
    width: 480
    height: 300
    TextArea { id: area; width: 300; height: 120; placeholderText: "Notes" }
    Button { id: next; y: 160; text: "Next" }

    TestCase {
        name: "textarea"
        when: windowShown
        function init() { UnitTheme.reset(); area.clear(); area.error = false; next.forceActiveFocus(Qt.OtherFocusReason); }
        function ring() { return area.background.children.find(child => String(child).indexOf("FocusRing") === 0); }
        function test_initial_focus_keeps_text_entry_without_focus_border_then_tab_shows_it() {
            root.Window.window.requestActivate();
            tryCompare(root.Window.window, "active", true);
            wait(0);
            area.forceActiveFocus(Qt.OtherFocusReason);
            compare(area.activeFocus, true);
            compare(ring().visible, false);
            compare(String(area.outline), String(Qt.color(Theme.textField.borderColor)));
            area.error = true;
            compare(String(area.outline), String(Qt.color(Theme.textField.error)));
            compare(ring().visible, false);
            area.error = false;
            keyClick(Qt.Key_A);
            compare(area.text, "a");
            // TextArea keeps Tab for indentation; a Tab from the next
            // control enters it with the platform keyboard reason.
            next.forceActiveFocus(Qt.OtherFocusReason);
            keyClick(Qt.Key_Tab);
            compare(area.activeFocus, true);
            compare(ring().visible, true);
            compare(String(area.outline), String(Qt.color(Theme.textField.focus)));
            area.error = true;
            compare(String(area.outline), String(Qt.color(Theme.textField.error)));
            compare(String(ring().border.color), String(Qt.color(Theme.textField.error)));
        }
    }
}
