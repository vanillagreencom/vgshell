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
    TextArea { id: grows; x: 320; width: 150; minimumHeight: 0; placeholderText: "Message" }
    Button { id: next; y: 160; text: "Next" }

    UnitCase {
        name: "textarea"
        when: windowShown
        function init() { UnitTheme.reset(); area.clear(); grows.clear(); area.error = false; next.forceActiveFocus(Qt.OtherFocusReason); }
        function ring() { return area.background.children.find(child => String(child).indexOf("FocusRing") === 0); }
        // A zero floor starts the area at one line, its `textField.paddingX`
        // of 10 above and below it, under the default floor of three large
        // controls, 3 * 40; each further line grows it.
        function test_a_zero_floor_starts_at_one_line_and_grows_with_its_text() {
            compare(grows.lineCount, 1);
            const one = grows.implicitHeight;
            compare(one, grows.contentHeight + 2 * 10);
            verify(one < 120, "one line stands under the default floor: " + one);
            grows.text = "first\nsecond";
            compare(grows.lineCount, 2);
            compare(grows.implicitHeight, grows.contentHeight + 2 * 10);
            verify(grows.implicitHeight > one, "a second line grows the area");
        }

        function test_retained_keyboard_border_clears_on_initial_focus_after_one_frame_data() {
            return [{tag: "neutral", hovered: false, error: false}, {tag: "hovered", hovered: true, error: false}, {tag: "error", hovered: true, error: true}];
        }
        function test_retained_keyboard_border_clears_on_initial_focus_after_one_frame(data) {
            root.Window.window.requestActivate();
            tryCompare(root.Window.window, "active", true);
            mouseMove(root, root.width - 1, root.height - 1);
            area.forceActiveFocus(Qt.OtherFocusReason);
            compare(area.cursorVisible, true);
            next.forceActiveFocus(Qt.OtherFocusReason);
            for (let step = 0; step < 8 && !area.activeFocus; step++) keyClick(Qt.Key_Tab);
            compare(area.activeFocus, true);
            tryCompare(area.background.border, "color", Qt.color(Theme.textField.focus));
            if (data.hovered) {
                mouseMove(area, area.width / 2, area.height / 2);
                tryCompare(area, "hovered", true);
            }
            KeyNavLogic.focusInitial(area, root.Window.window);
            area.error = data.error;
            compare(area.focusReason, Qt.OtherFocusReason);
            compare(area.cursorVisible, true);
            renderedFrame(area);
            const expected = data.error ? Theme.textField.error : data.hovered ? Theme.textField.hover : Theme.textField.borderColor;
            compare(String(area.background.border.color), String(Qt.color(expected)));
            area.error = false;
            mouseMove(root, root.width - 1, root.height - 1);
        }

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
