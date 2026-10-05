import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// TabPages: the first page shows, at the component's width, and the height
// is the strip, the spacing and that page; a click on a tab and Left and
// Right on the strip show another page and hide the rest; Tab from the
// strip enters the shown page alone and Shift+Tab returns; Ctrl+Tab,
// Ctrl+Shift+Tab, Ctrl+PageDown and Ctrl+PageUp step the page from the
// strip, each its own way and round the ends, and from a control of the
// shown page, where a Select, a SegmentedControl and a Slider keep the
// value they hold; a page that
// hides while it holds the keyboard hands it to the strip with its ring,
// and one that hides while the keyboard is elsewhere leaves the strip the
// component's focus, which the strip is from the start.
Item {
    id: root
    width: 400
    height: 460

    Button { id: before; text: "Before" }
    TabPages {
        id: pages
        y: 60
        width: 300
        model: ["Settings", "Details"]
        Column {
            id: first
            Button { id: save; text: "Save" }
            TextField { id: field; width: parent.width }
            Select { id: choice; model: ["one", "two", "three"]; currentIndex: 1 }
            SegmentedControl { id: segments; model: ["a", "b", "c"]; currentIndex: 1 }
            Slider { id: level; from: 0; to: 100; value: 50; width: parent.width }
        }
        Column {
            id: second
            Button { id: update; text: "Update" }
        }
    }
    Button { id: after; y: 320; text: "After" }
    TabPages { id: untouched; y: 360; width: 300; model: ["One"]; Item {} }
    TabPages { id: three; y: 400; width: 300; model: ["One", "Two", "Three"]; Item {} Item {} Item {} }

    TestCase {
        name: "tabpages"
        when: windowShown

        function init() {
            UnitTheme.reset();
            pages.currentIndex = 0;
            root.Window.window.requestActivate();
            before.forceActiveFocus(Qt.TabFocusReason);
        }

        function focusStrip() {
            pages.tabs.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(pages.tabs, "activeFocus", true);
        }

        function test_the_first_page_shows_at_the_components_width() {
            compare(pages.count, 2);
            compare(pages.currentIndex, 0);
            compare(pages.currentPage, first);
            verify(first.visible, "the first page is hidden");
            verify(!second.visible, "the second page shows beside the first");
            compare(first.width, 300);
            compare(second.width, 300);
            verify(first.height !== second.height, "the pages are one height, so the height reading holds for either");
            compare(pages.height, pages.tabs.height + Theme.stack.page + first.height);
        }

        function test_a_click_on_a_tab_shows_its_page() {
            mouseClick(pages.tabs.itemAt(1));
            compare(pages.currentIndex, 1);
            compare(pages.currentPage, second);
            verify(second.visible, "the chosen page is hidden");
            verify(!first.visible, "the page left behind still shows");
            compare(pages.height, pages.tabs.height + Theme.stack.page + second.height);
            pages.spacing = 4;
            compare(pages.height, pages.tabs.height + 4 + second.height);
            pages.spacing = Qt.binding(() => Theme.stack.page);
        }

        function test_left_and_right_on_the_strip_change_the_page() {
            focusStrip();
            keyClick(Qt.Key_Right);
            compare(pages.currentIndex, 1);
            verify(second.visible && !first.visible, "Right left the first page shown");
            keyClick(Qt.Key_Left);
            compare(pages.currentIndex, 0);
            compare(pages.tabs.activeFocus, true);
        }

        function test_tab_enters_the_shown_page_alone() {
            pages.currentIndex = 1;
            keyClick(Qt.Key_Tab);
            compare(pages.tabs.activeFocus, true, "the strip is no Tab stop");
            compare(pages.tabs.visualFocus, true);
            keyClick(Qt.Key_Tab);
            compare(update.activeFocus, true, "Tab from the strip misses the shown page");
            keyClick(Qt.Key_Tab, Qt.ShiftModifier);
            compare(pages.tabs.activeFocus, true, "Shift+Tab does not return to the strip");
            keyClick(Qt.Key_Tab);
            keyClick(Qt.Key_Tab);
            compare(after.activeFocus, true, "a hidden page's control is a Tab stop");
        }

        // Three pages tell a step forward from a step back.
        function test_the_tab_keys_step_from_the_strip_round_the_ends() {
            three.currentIndex = 0;
            three.tabs.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(three.tabs, "activeFocus", true);
            keyClick(Qt.Key_Tab, Qt.ControlModifier);
            compare(three.currentIndex, 1);
            keyClick(Qt.Key_PageDown, Qt.ControlModifier);
            compare(three.currentIndex, 2);
            keyClick(Qt.Key_Tab, Qt.ControlModifier);
            compare(three.currentIndex, 0, "Ctrl+Tab stops at the last page");
            keyClick(Qt.Key_Backtab, Qt.ControlModifier | Qt.ShiftModifier);
            compare(three.currentIndex, 2, "Ctrl+Shift+Tab stops at the first page");
            keyClick(Qt.Key_PageUp, Qt.ControlModifier);
            compare(three.currentIndex, 1);
        }

        function test_the_tab_keys_step_from_a_control_of_the_page() {
            save.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_PageDown, Qt.ControlModifier);
            compare(pages.currentIndex, 1);
            pages.currentIndex = 0;
            field.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Tab, Qt.ControlModifier);
            compare(pages.currentIndex, 1, "a text field keeps Ctrl+Tab");
        }

        function test_the_tab_keys_step_from_a_control_with_keys_of_its_own_data() {
            return [
                { tag: "Select", control: choice, value: "currentIndex" },
                { tag: "SegmentedControl", control: segments, value: "currentIndex" },
                { tag: "Slider", control: level, value: "value" }
            ];
        }

        // Each control starts mid-range, so a key it took as its own, either
        // way, would move the value it holds.
        function test_the_tab_keys_step_from_a_control_with_keys_of_its_own(data) {
            const keys = [
                [Qt.Key_Tab, Qt.ControlModifier],
                [Qt.Key_Backtab, Qt.ControlModifier | Qt.ShiftModifier],
                [Qt.Key_PageDown, Qt.ControlModifier],
                [Qt.Key_PageUp, Qt.ControlModifier]
            ];
            const held = data.control[data.value];
            for (const [key, modifiers] of keys) {
                pages.currentIndex = 0;
                data.control.forceActiveFocus(Qt.TabFocusReason);
                compare(data.control.activeFocus, true);
                keyClick(key, modifiers);
                compare(pages.currentIndex, 1, "key " + key + " with " + modifiers + " stays in the control");
                compare(data.control[data.value], held, "key " + key + " with " + modifiers + " moves the control");
            }
        }

        function test_the_strip_is_the_components_focus() {
            untouched.forceActiveFocus(Qt.TabFocusReason);
            compare(untouched.tabs.activeFocus, true);
        }

        function test_a_page_that_hides_hands_the_keyboard_to_the_strip() {
            save.forceActiveFocus(Qt.MouseFocusReason);
            compare(save.activeFocus, true);
            pages.currentIndex = 1;
            compare(save.activeFocus, false, "a hidden control keeps the keyboard");
            compare(pages.tabs.activeFocus, true);
            compare(pages.tabs.visualFocus, true, "the strip takes the keyboard without its ring");
            compare(pages.tabs.itemAt(1).background.children[1].visible, true);
        }

        function test_a_page_that_hides_without_the_keyboard_leaves_it_where_it_is() {
            save.forceActiveFocus(Qt.TabFocusReason);
            before.forceActiveFocus(Qt.TabFocusReason);
            pages.currentIndex = 1;
            compare(before.activeFocus, true, "a page change took the keyboard from outside the component");
            pages.forceActiveFocus(Qt.TabFocusReason);
            compare(save.activeFocus, false, "the component gives the keyboard to a hidden control");
            compare(pages.tabs.activeFocus, true);
        }
    }
}
