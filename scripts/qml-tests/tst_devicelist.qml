import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// DeviceList: a DeviceRow per entry with the action and the menu its
// owner names; one Tab stop, the selected row; arrows, Home and End move
// the selection and the keyboard; Enter and the action button emit
// `acted`, a menu entry `chose`; Delete emits `removed` only when
// `removable`, and the row that takes a removed row's place takes the
// keyboard; the selection shows only while the list holds the keyboard;
// a change to the rows that keeps their count keeps the keyboard where it
// is.
Item {
    id: root
    width: 480
    height: 400

    readonly property var three: [
        { key: "a", text: "Headset", secondary: "Connected", iconName: "headphones", battery: 0.5 },
        { key: "b", text: "Mouse", iconName: "mouse" },
        { key: "c", text: "Speaker", badge: "Nearby", badgeTone: "info" }
    ]

    Button { id: before; text: "Scan" }
    DeviceList {
        id: list
        y: 40
        width: 420
        rows: root.three
        actionOf: row => row.key === "a" ? { text: "Disconnect", variant: "secondary" } : null
        menuOf: row => row.key === "a" ? [{ key: "rename", text: "Rename" }, { key: "forget", text: "Forget" }] : []
    }
    SignalSpy { id: acted; target: list; signalName: "acted" }
    SignalSpy { id: chose; target: list; signalName: "chose" }
    SignalSpy { id: removed; target: list; signalName: "removed" }

    TestCase {
        name: "devicelist"
        when: windowShown

        function trailing(row) { return row.contentItem.children[2].children; }
        function actionOf(row) { return trailing(row)[1].children[0]; }
        function menuOf(row) { return trailing(row)[2].children.find(child => child.triggerCurrent !== undefined); }

        function init() {
            UnitTheme.reset();
            list.rows = root.three;
            list.removable = false;
            list.current = 0;
            acted.clear();
            chose.clear();
            removed.clear();
            root.Window.window.requestActivate();
            before.forceActiveFocus(Qt.TabFocusReason);
        }

        function focusList() {
            list.focusCurrent(Qt.TabFocusReason);
            tryCompare(list.rowAt(list.current), "activeFocus", true);
        }

        function test_a_row_per_entry_with_its_action_and_menu() {
            compare(list.count, 3);
            compare(list.rowAt(0).text, "Headset");
            compare(list.rowAt(0).secondary, "Connected");
            compare(list.rowAt(2).badge, "Nearby");
            verify(actionOf(list.rowAt(0)).visible, "the first row's action is hidden");
            compare(actionOf(list.rowAt(0)).text, "Disconnect");
            compare(actionOf(list.rowAt(0)).variant, "secondary");
            verify(!actionOf(list.rowAt(1)).visible, "a row with no action draws one");
            compare(menuOf(list.rowAt(0)).items().map(item => item.text), ["Rename", "Forget"]);
            verify(!trailing(list.rowAt(1))[2].visible, "a row with no menu draws its overflow button");
        }

        function test_only_the_selected_row_is_a_tab_stop() {
            keyClick(Qt.Key_Tab);
            tryCompare(list.rowAt(0), "activeFocus", true);
            keyClick(Qt.Key_Tab);
            compare(actionOf(list.rowAt(0)).activeFocus, true, "Tab passes the row's action by");
            keyClick(Qt.Key_Tab);
            compare(trailing(list.rowAt(0))[2].activeFocus, true, "Tab passes the row's overflow by");
            keyClick(Qt.Key_Tab);
            compare(list.rowAt(1).activeFocus, false, "an unselected row is a Tab stop");
            compare(list.rowAt(2).activeFocus, false, "an unselected row is a Tab stop");
            compare(before.activeFocus, true);
        }

        function test_arrows_home_and_end_move_the_keyboard() {
            focusList();
            keyClick(Qt.Key_Down);
            compare(list.current, 1);
            compare(list.rowAt(1).activeFocus, true);
            tryCompare(list.rowAt(1), "visualFocus", true);
            keyClick(Qt.Key_End);
            compare(list.currentKey, "c");
            compare(list.rowAt(2).activeFocus, true);
            keyClick(Qt.Key_Home);
            compare(list.current, 0);
            compare(list.rowAt(0).activeFocus, true);
        }

        function test_enter_and_the_action_button_act() {
            focusList();
            keyClick(Qt.Key_Return);
            compare(acted.count, 1);
            compare(acted.signalArguments[0][0], "a");
            mouseClick(actionOf(list.rowAt(0)));
            compare(acted.count, 2);
            compare(acted.signalArguments[1][0], "a");
        }

        function test_a_menu_entry_chooses() {
            menuOf(list.rowAt(0)).items()[1].triggered();
            compare(chose.count, 1);
            compare(chose.signalArguments[0][0], "a");
            compare(chose.signalArguments[0][1], "forget");
        }

        function test_delete_removes_only_when_removable() {
            focusList();
            keyClick(Qt.Key_Delete);
            compare(removed.count, 0, "a list that removes nothing emits removed");
            list.removable = true;
            list.current = 2;
            focusList();
            keyClick(Qt.Key_Delete);
            compare(removed.count, 1);
            compare(removed.signalArguments[0][0], "c");
            list.rows = [root.three[0], root.three[1]];
            tryCompare(list.rowAt(1), "activeFocus", true);
            compare(list.rowAt(1).text, "Mouse");
        }

        function test_the_selection_shows_only_while_the_list_holds_the_keyboard() {
            compare(list.rowAt(0).highlighted, false);
            focusList();
            compare(list.rowAt(0).highlighted, true);
            before.forceActiveFocus(Qt.TabFocusReason);
            compare(list.rowAt(0).highlighted, false);
        }

        function test_a_rows_change_keeps_the_keyboard() {
            list.current = 1;
            focusList();
            const held = list.rowAt(1);
            list.rows = root.three.map(row => Object.assign({}, row, { secondary: "Changed" }));
            compare(list.rowAt(1), held);
            compare(held.activeFocus, true);
            compare(held.secondary, "Changed");
        }
    }
}
