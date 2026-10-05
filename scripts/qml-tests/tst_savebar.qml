import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// SaveBar: no taller than zero and not drawn while the page holds no edit;
// with one, the line "Unsaved changes" at the left and Discard and Save at
// the right, `saveBar.gap`, 8, apart, a md control, 32, tall; a press on
// each emits its signal and takes the keyboard from no field, while Tab
// reaches both; `confirm()` reads "Saved" in `saveBar.saved` with no action
// for `saveBar.duration`, then the bar leaves; an edit in that time shows
// the actions again; and `confirm()` under an edit changes nothing.
// Expected values are worked by hand from the defaults in Tokens.js, never
// read from Theme. The tests still the motion and shorten the wait through
// the theme, so a fade never stands between a change and its reading.
Item {
    id: root
    width: 400
    height: 200

    TextField { id: field; width: 200 }
    SaveBar { id: bar; y: 100; width: 360 }
    SignalSpy { id: saves; target: bar; signalName: "save" }
    SignalSpy { id: discards; target: bar; signalName: "discard" }

    TestCase {
        name: "saveBar"
        when: windowShown

        readonly property int dwell: 200

        function init() {
            UnitTheme.reset();
            compare(UnitTheme.override({ motion: { scale: 0 }, saveBar: { duration: dwell } }), "ok");
            bar.dirty = true;
            bar.dirty = false;
            tryCompare(bar, "drawn", false);
            saves.clear();
            discards.clear();
            field.forceActiveFocus();
        }

        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++)
                for (const child of found[i].children || []) found.push(child);
            return found;
        }
        function button(text) { return descendants(bar).find(child => child.text === text && child.clicked !== undefined); }
        function line() { return descendants(bar).find(child => child.text === "Saved" || child.text === "Unsaved changes"); }
        function shown(item) {
            for (let at = item; at !== null && at !== bar.parent; at = at.parent)
                if (!at.visible) return false;
            return true;
        }

        function test_a_page_with_no_edit_draws_no_bar() {
            verify(!bar.visible, "the bar is not drawn");
            compare(bar.height, 0);
        }

        function test_an_edit_shows_the_line_and_both_actions() {
            bar.dirty = true;
            tryCompare(bar, "drawn", true);
            compare(bar.height, 32);
            compare(line().text, "Unsaved changes");
            const discard = button("Discard"), save = button("Save");
            verify(shown(discard) && shown(save), "both actions are drawn");
            compare(line().mapToItem(bar, 0, 0).x, 0);
            compare(save.mapToItem(bar, save.width, 0).x, 360);
            compare(save.mapToItem(bar, 0, 0).x - discard.mapToItem(bar, discard.width, 0).x, 8);
        }

        function test_each_action_emits_its_signal() {
            bar.dirty = true;
            tryCompare(bar, "drawn", true);
            mouseClick(button("Save"));
            compare([saves.count, discards.count], [1, 0]);
            mouseClick(button("Discard"));
            compare([saves.count, discards.count], [1, 1]);
        }

        function test_a_press_on_an_action_leaves_the_keyboard_in_the_field() {
            bar.dirty = true;
            tryCompare(bar, "drawn", true);
            mouseClick(button("Save"));
            verify(field.activeFocus, "the field keeps the keyboard");
            verify(!bar.activeFocus, "the bar takes none");
        }

        function test_tab_reaches_both_actions() {
            bar.dirty = true;
            tryCompare(bar, "drawn", true);
            keyClick(Qt.Key_Tab);
            verify(button("Discard").activeFocus, "Tab from the field reaches Discard");
            keyClick(Qt.Key_Tab);
            verify(button("Save").activeFocus, "the next Tab reaches Save");
            verify(bar.activeFocus, "the bar's scope holds the keyboard");
            keyClick(Qt.Key_Return);
            compare(saves.count, 1);
        }

        // palette.success, #b4c96f.
        function test_confirm_reads_saved_then_the_bar_leaves() {
            bar.dirty = true;
            tryCompare(bar, "drawn", true);
            bar.dirty = false;
            bar.confirm();
            verify(bar.saved && bar.drawn, "the bar stays for the Saved line");
            compare(bar.height, 32);
            compare(line().text, "Saved");
            compare(String(line().color), "#b4c96f");
            verify(!shown(button("Save")) && !shown(button("Discard")), "the Saved line draws no action");
            wait(dwell / 2);
            verify(bar.drawn, "the line holds for the token's wait");
            tryCompare(bar, "drawn", false, 4 * dwell);
            compare(bar.height, 0);
            compare(line().text, "Saved");
        }

        function test_a_theme_moves_the_saved_colour() {
            compare(UnitTheme.override({ motion: { scale: 0 }, saveBar: { duration: dwell, saved: "#112233" } }), "ok");
            bar.dirty = true;
            bar.dirty = false;
            bar.confirm();
            compare(String(line().color), "#112233");
        }

        // The wait is long here, so the bar that leaves with the edit is
        // not one whose Saved line ran out.
        function test_an_edit_during_the_saved_line_shows_the_actions_again() {
            compare(UnitTheme.override({ motion: { scale: 0 }, saveBar: { duration: 20 * dwell } }), "ok");
            bar.dirty = true;
            bar.dirty = false;
            bar.confirm();
            compare(line().text, "Saved");
            bar.dirty = true;
            compare(line().text, "Unsaved changes");
            verify(shown(button("Save")), "Save is drawn again");
            bar.dirty = false;
            tryCompare(bar, "drawn", false, 5 * dwell);
        }

        function test_confirm_under_an_edit_changes_nothing() {
            bar.dirty = true;
            tryCompare(bar, "drawn", true);
            bar.confirm();
            verify(!bar.saved, "the line does not read Saved");
            compare(line().text, "Unsaved changes");
            bar.dirty = false;
            tryCompare(bar, "drawn", false, dwell / 2);
        }
    }
}
