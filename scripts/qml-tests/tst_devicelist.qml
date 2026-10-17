import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// DeviceList: a DeviceRow per entry with the action and the menu its
// owner names; one Tab stop, the selected row; arrows, Home and End move
// the selection and the keyboard; Enter and the action button emit
// `acted`, a menu entry `chose`; a busy row shows a Spinner and emits no
// action; Delete emits `removed` only when `removable`, and the row that
// takes a removed row's place takes the keyboard; the selection shows only
// while the list holds the keyboard; a change to the rows that keeps their
// count keeps the keyboard where it is; a row's `secondaryTone` reaches
// its DeviceRow; a hover over the row at a scroll area's edge moves the
// plate and neither the keyboard nor the page, while the arrows still
// reveal. A list given a `disabledReason` keeps its selected row a
// Tab stop, takes no click and no key, on a row or its action, moves no
// selection under the pointer, offers no overflow menu, draws its rows'
// content faded under a full-strength ring, and shows the reason on hover
// and on keyboard focus; an empty reason leaves it as it was. The tooltip
// waits on `tooltip.delay` in real time, so this proves its wiring.
Item {
    id: root
    width: 480
    height: 600

    readonly property string reason: "Only the administrator can change Tailscale."

    readonly property var three: [
        { key: "a", text: "Headset", secondary: "Connected", iconName: "headphones", battery: 0.5 },
        { key: "b", text: "Mouse", iconName: "mouse" },
        { key: "c", text: "Speaker", secondary: "Stopped", secondaryTone: "danger", badge: "Nearby", badgeTone: "info" }
    ]

    Button { id: before; text: "Scan" }
    DeviceList {
        id: list
        y: 40
        width: 420
        rows: root.three
        actionOf: row => row.key === "a" ? { text: "Disconnect" } : null
        menuOf: row => row.key === "a" ? [{ key: "rename", text: "Rename" }, { key: "forget", text: "Forget" }] : []
    }
    SignalSpy { id: acted; target: list; signalName: "acted" }
    SignalSpy { id: chose; target: list; signalName: "chose" }
    SignalSpy { id: removed; target: list; signalName: "removed" }
    // Made by the cases that lock it, so the list above keeps the window's
    // Tab chain.
    Component {
        id: lockedList
        DeviceList {
            y: 320
            width: 420
            rows: root.three
            removable: true
            disabledReason: root.reason
            actionOf: row => row.key === "a" ? { text: "Disconnect" } : null
            menuOf: row => row.key === "a" ? [{ key: "rename", text: "Rename" }] : []
        }
    }
    Component { id: spyComponent; SignalSpy {} }
    // A list taller than the area it scrolls in, as a device pane's.
    Component {
        id: scrolledList
        ScrollArea {
            readonly property alias list: inner
            y: 320
            width: 440
            height: 100
            DeviceList {
                id: inner
                width: 400
                rows: root.three.concat([
                    { key: "d", text: "Keyboard", iconName: "keyboard" },
                    { key: "e", text: "Printer", iconName: "printer" },
                    { key: "f", text: "Phone", iconName: "smartphone" }
                ])
            }
        }
    }

    TestCase {
        name: "devicelist"
        when: windowShown

        function trailing(row) { return row.contentItem.children[2].children; }
        function spinnerOf(row) { return trailing(row)[1].children[0]; }
        function actionOf(row) { return trailing(row)[1].children[1]; }
        function menuOf(row) { return trailing(row)[2].children.find(child => child.triggerCurrent !== undefined); }

        function init() {
            UnitTheme.reset();
            list.rows = root.three;
            list.actionOf = row => row.key === "a" ? { text: "Disconnect" } : null;
            list.menuOf = row => row.key === "a" ? [{ key: "rename", text: "Rename" }, { key: "forget", text: "Forget" }] : [];
            list.removable = false;
            list.current = 0;
            acted.clear();
            chose.clear();
            removed.clear();
            root.Window.window.requestActivate();
            before.forceActiveFocus(Qt.TabFocusReason);
        }

        function test_a_rows_line_tone_reaches_its_row() {
            compare(list.rowAt(0).secondaryTone, "");
            compare(list.rowAt(2).secondaryTone, "danger");
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

        function test_a_busy_row_shows_a_spinner_and_takes_no_action() {
            list.rows = [
                { key: "busy", text: "Earbuds", secondary: "Connecting…", iconName: "headphones", busy: true },
                { key: "ready", text: "Speaker", secondary: "Not connected", iconName: "speaker" }
            ];
            list.actionOf = row => ({ text: row.key === "busy" ? "Connect" : "Open" });
            // Rows the new list builds are placed on the next polish.
            tryVerify(() => list.rowAt(1).y >= list.rowAt(0).y + list.rowAt(0).height, 1000, "the rows are laid out");
            verify(spinnerOf(list.rowAt(0)).visible, "a busy row shows its spinner");
            verify(!actionOf(list.rowAt(0)).visible, "a busy row hides its action");
            mouseClick(list.rowAt(0));
            compare(acted.count, 0, "a click on a busy row does not act");
            focusList();
            keyClick(Qt.Key_Return);
            compare(acted.count, 0, "Return on a busy row does not act");
            keyClick(Qt.Key_Space);
            compare(acted.count, 0, "Space on a busy row does not act");
            list.current = 1;
            focusList();
            verify(!spinnerOf(list.rowAt(1)).visible, "a ready row hides its spinner");
            verify(actionOf(list.rowAt(1)).visible, "a ready row keeps its action");
            mouseClick(list.rowAt(1));
            compare(acted.count, 1);
            compare(acted.signalArguments[0][0], "ready");
            keyClick(Qt.Key_Return);
            compare(acted.count, 2);
            compare(acted.signalArguments[1][0], "ready");
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

        // A hover never moves the keyboard: the scroll area reveals the item
        // that takes it, so a hover over the row at the area's edge would
        // scroll the page under a resting pointer. The arrows still reveal.
        function test_a_hover_at_a_scrolled_lists_edge_moves_no_keyboard_and_no_page() {
            const area = createTemporaryObject(scrolledList, root);
            const made = area.list;
            tryVerify(() => made.rowAt(5) !== null && made.rowAt(5).y >= made.rowAt(4).y + made.rowAt(4).height, 1000, "the rows are laid out");
            area.height = made.rowAt(0).height * 2.5;
            tryVerify(() => area.overflowing, 1000, "the list overflows its area");
            made.focusCurrent(Qt.TabFocusReason);
            tryCompare(made.rowAt(0), "activeFocus", true);
            compare(area.contentY, 0);
            let edge = 0;
            while (made.rowAt(edge + 1).y < area.height) edge++;
            const row = made.rowAt(edge);
            verify(edge > 0 && row.y + row.height > area.height - area.fadeExtent, "row " + edge + " lies in the bottom band");
            mouseMove(row, 20, (area.height - row.y) / 2);
            mouseMove(row, 24, (area.height - row.y) / 2);
            compare(plateOf(made).placed, row, "the plate follows the pointer");
            // Frames for a hover delivered again to reach the rows.
            wait(100);
            compare(area.contentY, 0, "the page stays where the pointer rests");
            compare(made.rowAt(0).activeFocus, true, "the keyboard stays on the selected row");
            compare(made.current, 0);
            for (let index = 0; index < edge; index++) keyClick(Qt.Key_Down);
            compare(made.rowAt(edge).activeFocus, true);
            verify(area.contentY > 0, "an arrow reveals the row it moves to");
            mouseMove(root, root.width - 1, 0);
        }

        function reasonTip(control) { return control.lock.children.map(child => child.item).find(item => item && item.objectName === "disabledReasonTip") || null; }
        function ringOf(row) { return row.background.children.find(child => child.target === row); }
        function plateOf(control) { return control.children.find(child => child.followRow !== undefined); }

        // The opacity an item draws at: its own times every ancestor's.
        function drawnOpacity(item) {
            let out = 1;
            for (let at = item; at !== null; at = at.parent) out *= at.opacity;
            return out;
        }

        // A locked list under the first, its rows laid out.
        function locked() {
            compare(UnitTheme.override({ tooltip: { delay: 200 } }), "ok");
            const made = createTemporaryObject(lockedList, root);
            tryVerify(() => made.rowAt(2).y >= made.rowAt(1).y + made.rowAt(1).height, 1000, "the rows are laid out");
            return made;
        }

        // Tab reaches the selected row from the item before it, then the
        // row's action, and the reason opens on each focus.
        function test_a_locked_list_stays_a_tab_stop_and_says_why() {
            const made = locked();
            const row = made.rowAt(0);
            row.nextItemInFocusChain(false).forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Tab);
            compare(row.activeFocus, true, "Tab reaches the locked list's selected row");
            compare(made.visualFocus, true);
            const tip = reasonTip(made);
            verify(tip !== null, "the locked list holds its reason");
            tryCompare(tip, "opened", true);
            compare(tip.text, root.reason);
            compare(made.Accessible.description, root.reason);
            compare(ringOf(row).visible, true);
            // A row fades in as it enters the list.
            tryVerify(() => drawnOpacity(ringOf(row)) === 1, 1000, "the row's ring draws at full strength: " + drawnOpacity(ringOf(row)));
            keyClick(Qt.Key_Tab);
            compare(actionOf(row).activeFocus, true, "Tab reaches the row's action");
            compare(made.visualFocus, true, "the keyboard on the action holds the reason open");
            compare(tip.opened, true);
            before.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(tip, "opened", false);
        }

        function test_a_locked_list_says_why_on_hover_and_moves_no_selection() {
            const made = locked();
            const tip = reasonTip(made);
            const second = made.rowAt(1);
            mouseMove(second, 20, second.height / 2);
            mouseMove(second, 24, second.height / 2);
            tryCompare(tip, "opened", true);
            compare(tip.text, root.reason);
            compare(made.current, 0, "a hover moves the selection of a locked list");
            compare(second.highlighted, false);
            compare(made.engaged, false, "a locked list shows a selection");
            compare(plateOf(made).shown, false, "a hover lights a row of a locked list");
            mouseMove(actionOf(made.rowAt(0)), 2, 2);
            compare(actionOf(made.rowAt(0)).hovered, false, "a locked list's action draws hover");
            mouseMove(root, root.width - 1, 0);
            tryCompare(tip, "opened", false);
        }

        function test_a_locked_list_takes_no_click_or_key() {
            const made = locked();
            const row = made.rowAt(0);
            const spies = ["acted", "chose", "removed"].map(name => createTemporaryObject(spyComponent, root, { target: made, signalName: name }));
            function unchanged(input) {
                for (const spy of spies) compare(spy.count, 0, input + ": no " + spy.signalName);
                compare(made.current, 0, input + ": the selection stays");
            }
            mouseClick(row, 20, row.height / 2);
            unchanged("click on a row");
            mouseClick(made.rowAt(1), 20, row.height / 2);
            unchanged("click on another row");
            mouseClick(actionOf(row));
            unchanged("click on the action");
            made.focusCurrent(Qt.TabFocusReason);
            tryCompare(row, "activeFocus", true);
            for (const key of [Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter, Qt.Key_Down, Qt.Key_End, Qt.Key_Delete, Qt.Key_Menu]) {
                keyClick(key);
                unchanged("key " + key);
            }
            compare(row.activeFocus, true, "the keys leave the focus on the row");
            compare(menuOf(row).items().length, 0, "a locked list offers an overflow menu");
            verify(!trailing(row)[2].visible, "a locked list draws an overflow button");
            actionOf(row).forceActiveFocus(Qt.TabFocusReason);
            for (const key of [Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter]) {
                keyClick(key);
                unchanged("key " + key + " on the action");
            }
        }

        // The rows' content fades; the list and its rows do not.
        function test_a_locked_list_draws_faded() {
            const made = locked();
            compare(made.opacity, 1);
            for (let index = 0; index < made.count; index++) {
                // A row fades in as it enters the list.
                tryCompare(made.rowAt(index), "opacity", 1);
                compare(made.rowAt(index).contentItem.opacity, Theme.opacity.disabled);
            }
            compare(list.rowAt(0).contentItem.opacity, 1);
        }

        function test_an_empty_reason_leaves_the_list_as_it_was() {
            compare(reasonTip(list), null);
            compare(list.Accessible.description, "");
            const made = locked();
            const spy = createTemporaryObject(spyComponent, root, { target: made, signalName: "acted" });
            made.disabledReason = "";
            compare(reasonTip(made), null, "clearing the reason drops the tooltip");
            compare(made.rowAt(0).contentItem.opacity, 1);
            compare(menuOf(made.rowAt(0)).items().length, 1);
            mouseClick(made.rowAt(1), 20, made.rowAt(1).height / 2);
            compare(spy.count, 1);
            compare(spy.signalArguments[0][0], "b");
            keyClick(Qt.Key_Down);
            compare(made.current, 2);
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
